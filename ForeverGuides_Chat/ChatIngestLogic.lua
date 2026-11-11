-- Forever Chat, the input side (pure, no game access): maps one chat event of the game to the conversation
-- and the line the model (ChatConversations.lua) takes. The caller passes the clock and the own name.
-- Every argument of an event may be a secret value: each one that is read here goes through
-- AutoGuard.Safe first and is never compared or measured raw. Text and sender are handed on untouched,
-- the model keeps an unreadable one as a placeholder line.
--
-- Arguments of a chat event (CHAT_MSG_*), by position: 1 text, 2 sender (the partner for both whisper
-- events), 3 language, 4 channel string ("5. Trade - City"), 7 zone channel id, 8 channel number,
-- 9 channel base name, 11 line id, 12 sender guid, 13 Battle.net account id (CHAT_MSG_BN_*).
--
-- ctx = {
--   now         clock in epoch seconds
--   own         own full name (optional, "" until the client knows it)
--   homeRealm   realm of the own server (optional, dropped from whisper keys)
--   guild       guild name or function() -> guild name (optional)
--   localChat   true takes say, yell and the emotes too
--   blocked     function(name, guid) -> true for an ignored player (optional)
--   bnetAccount function(args) -> { id, name, tag, character } of the Battle.net partner of a line, nil when
--               unknown (optional). name is the plain display name, nil for an escape form or secret value
--   bnetUnknownName  name of a Battle.net partner the game gives no readable name or BattleTag for
--   community   function(channelString) -> name of a community channel, nil when unknown (optional)
--   restrictedName  name of the conversation that holds lines whose partner or channel is a secret value
--   classOf     function(sender, guid) -> class token of the writer, nil when unknown (optional)
-- }
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local Logic = FG.ChatHistoryLogic

local IL = {}
chat.IngestLogic = IL

local IN, OUT = Logic.DIR_IN, Logic.DIR_OUT

IL.ARG = {
  TEXT = 1,
  SENDER = 2,
  CHANNEL_STRING = 4,
  ZONE_ID = 7,
  NUMBER = 8,
  BASE_NAME = 9,
  LINE_ID = 11,
  GUID = 12,
  BN_ID = 13,
}
local ARG = IL.ARG

-- event -> { kind (Conversations kind), dir (whispers), type (name in ChatHistoryLogic.TYPES, default of
-- the kind otherwise), optional (only with ctx.localChat) }. Every line a player sees in the chat of the game
-- has a row here; what no player wrote (system, loot, monster speech, boss emotes, achievements) has none.
-- A client does not know every event (Battle.net and community lines only exist in Retail, the guide channel
-- and the battleground channel only in some clients): the intake registers each one with pcall.
IL.EVENTS = {
  CHAT_MSG_WHISPER = { kind = "whisper", dir = IN },
  CHAT_MSG_WHISPER_INFORM = { kind = "whisper", dir = OUT },
  -- The automatic answers "is away" and "is busy" of the partner read like whispers in the game chat.
  CHAT_MSG_AFK = { kind = "whisper", dir = IN },
  CHAT_MSG_DND = { kind = "whisper", dir = IN },
  CHAT_MSG_BN_WHISPER = { kind = "bnet", dir = IN },
  CHAT_MSG_BN_WHISPER_INFORM = { kind = "bnet", dir = OUT },
  CHAT_MSG_PARTY = { kind = "party" },
  CHAT_MSG_PARTY_LEADER = { kind = "party" },
  CHAT_MSG_PARTY_GUIDE = { kind = "party" },
  CHAT_MSG_RAID = { kind = "raid" },
  CHAT_MSG_RAID_LEADER = { kind = "raid" },
  CHAT_MSG_RAID_WARNING = { kind = "raid" },
  CHAT_MSG_INSTANCE_CHAT = { kind = "instance" },
  CHAT_MSG_INSTANCE_CHAT_LEADER = { kind = "instance" },
  CHAT_MSG_BATTLEGROUND = { kind = "instance" },
  CHAT_MSG_BATTLEGROUND_LEADER = { kind = "instance" },
  CHAT_MSG_GUILD = { kind = "guild" },
  CHAT_MSG_OFFICER = { kind = "officer" },
  CHAT_MSG_CHANNEL = { kind = "channel" },
  CHAT_MSG_COMMUNITIES_CHANNEL = { kind = "channel", community = true },
  CHAT_MSG_SAY = { kind = "local", type = "say", optional = true },
  CHAT_MSG_YELL = { kind = "local", type = "yell", optional = true },
  CHAT_MSG_EMOTE = { kind = "local", type = "emote", optional = true },
  CHAT_MSG_TEXT_EMOTE = { kind = "local", type = "emote", optional = true },
}

-- Name of a guild conversation while the guild name is not known.
IL.GUILD_FALLBACK = "guild"
-- Separator of channel base name and zone ("Trade - City").
IL.ZONE_SEPARATOR = " - "

-- The events to register, sorted so every session registers the same list.
function IL.Events(options)
  local out = {}
  local withLocal = type(options) == "table" and options.localChat == true
  for event, spec in pairs(IL.EVENTS) do
    if withLocal or not spec.optional then
      out[#out + 1] = event
    end
  end
  table.sort(out)
  return out
end

-- The value, or nil when it is secret or unreadable.
local function safe(value)
  local guard = FG.AutoGuard
  if guard and guard.Safe then
    return guard.Safe(value)
  end
  return value
end

local function text(value)
  value = safe(value)
  return type(value) == "string" and value ~= "" and value or nil
end

local function number(value)
  value = safe(value)
  return type(value) == "number" and value == value and value or nil
end

local function guildName(ctx)
  local value = ctx.guild
  if type(value) == "function" then
    local ok, name = pcall(value)
    value = ok and name or nil
  end
  return text(value) or IL.GUILD_FALLBACK
end

-- The base name of a channel: the base name argument, else the channel string without its number. A zone
-- channel (zone id above 0) loses its zone ("Trade - City" is "Trade"), so walking on keeps one conversation.
local function channelName(args)
  local name = text(args[ARG.BASE_NAME])
  if not name then
    local full = text(args[ARG.CHANNEL_STRING])
    name = full and full:match("^%d+%.%s*(.+)$") or full
  end
  if not name then
    return nil
  end
  local zone = number(args[ARG.ZONE_ID])
  if zone and zone > 0 then
    local at = name:find(IL.ZONE_SEPARATOR, 1, true)
    if at and at > 1 then
      name = name:sub(1, at - 1)
    end
  end
  return name
end

-- True when the sender of a line is on the block list (the own name never is). Never raises, never reads a
-- secret value.
local function isBlocked(ctx, args)
  if type(ctx.blocked) ~= "function" then
    return false
  end
  local name = text(args[ARG.SENDER])
  if not name or (type(ctx.own) == "string" and FG.PlayerName.Equal(name, ctx.own)) then
    return false
  end
  local ok, blocked = pcall(ctx.blocked, name, text(args[ARG.GUID]))
  return ok and blocked == true
end

-- The conversation of lines whose partner or channel is a secret value: nothing about them may be read, so they
-- share one conversation with a placeholder for every line. nil while the caller gave no name for it.
local function restricted(ctx, input)
  local name = text(ctx.restrictedName)
  if not name then
    return nil
  end
  input.hidden = true
  input.sender = nil
  return { kind = "local", name = name, homeRealm = ctx.homeRealm }
end

-- True for text that is a plain name: no escape sequence of the game ("|Kq1|k" is a name that only the game chat
-- resolves, "|cff..." a color), nothing a window could show as a wrong name.
local function plainName(value)
  local name = text(value)
  return name and not name:find("|", 1, true) and name or nil
end

-- "Lempard#1234" shows as "Lempard", the number behind the hash is the identity, not the name.
local function tagName(tag)
  tag = plainName(tag)
  return tag and (tag:match("^(.-)#%d+$") or tag) or nil
end

-- The Battle.net partner of a line: the target fields of the conversation. The name is the display name of the
-- game (account name), else the BattleTag without its number, else the plain name of the event, else the caller's
-- fallback. The identity (BattleTag, else account id) keeps two partners apart and a renamed partner together.
-- nil when nothing identifies the partner (a secret account id and no readable name).
local function bnetTarget(ctx, args)
  local account
  if type(ctx.bnetAccount) == "function" then
    local ok, value = pcall(ctx.bnetAccount, args)
    account = ok and type(value) == "table" and value or nil
  end
  account = account or {}
  local tag, id = plainName(account.tag), number(account.id)
  local name = plainName(account.name) or tagName(tag) or tagName(args[ARG.SENDER])
  if not name and not tag and not id then
    return nil
  end
  return {
    name = name or text(ctx.bnetUnknownName),
    id = tag or id,
    tag = tag,
    accountId = id,
    character = plainName(account.character),
  }
end

-- Name of a community channel from the channel string ("Community:<club>:<stream>"), else the channel name.
local function communityName(ctx, args)
  if type(ctx.community) == "function" then
    local ok, value = pcall(ctx.community, text(args[ARG.CHANNEL_STRING]))
    local name = ok and text(value) or nil
    if name then
      return name
    end
  end
  return channelName(args)
end

-- Maps one event. args are the event arguments by position. Returns target, input, extra for
-- Conversations.AddLine (extra.number is the channel number), or nil and the reason: "event" (not one of
-- ours or no arguments), "off" (an optional event while ctx.localChat is off), "key" (no usable
-- partner or channel name, a secret one included, and no restrictedName), "blocked". A secret partner or
-- channel with ctx.restrictedName gives the conversation of that name and input.hidden (a placeholder line).
function IL.Build(ctx, event, args)
  local spec = IL.EVENTS[event]
  if not spec or type(ctx) ~= "table" or type(args) ~= "table" then
    return nil, "event"
  end
  if spec.optional and ctx.localChat ~= true then
    return nil, "off"
  end
  local kind = spec.kind
  local target = { kind = kind, homeRealm = ctx.homeRealm }
  local input = {
    time = ctx.now,
    text = args[ARG.TEXT],
    sender = args[ARG.SENDER],
    dir = spec.dir or IN,
    type = spec.type and Logic.TYPES[spec.type] or nil,
    id = args[ARG.LINE_ID],
  }
  local extra = {}
  local own = type(ctx.own) == "string" and ctx.own or ""
  if kind == "whisper" or kind == "bnet" then
    -- Both events name the partner in the second argument; our own lines come from the own name. A Battle.net
    -- partner is read from the account instead: that argument is an escape form the messenger cannot show.
    if kind == "bnet" then
      local partner = bnetTarget(ctx, args)
      for field, value in pairs(partner or {}) do
        target[field] = value
      end
      input.sender = partner and partner.name or nil
    else
      target.name = text(args[ARG.SENDER])
    end
    if not target.name then
      target = restricted(ctx, input)
      if not target then
        return nil, "key"
      end
    elseif kind == "bnet" then
      input.type = Logic.TYPES.whisper
    end
    if spec.dir == OUT and not input.hidden then
      input.sender = own
    end
  elseif kind == "guild" or kind == "officer" then
    target.name = guildName(ctx)
  elseif kind == "channel" then
    target.name = spec.community and communityName(ctx, args) or channelName(args)
    -- A zone channel (General, Trade, Local Defense, Looking For Group) is public and very noisy.
    target.public = not spec.community and (number(args[ARG.ZONE_ID]) or 0) > 0
    extra.number = not spec.community and number(args[ARG.NUMBER]) or nil
    if not target.name and extra.number then
      target.name = extra.number
    end
    if not target.name then
      target = restricted(ctx, input)
      extra.number = nil
      if not target then
        return nil, "key"
      end
    end
  end
  if spec.dir ~= OUT and isBlocked(ctx, args) then
    return nil, "blocked"
  end
  -- One spelling for the own name, so the two events of a whisper to oneself are the same line.
  if spec.dir ~= OUT then
    local sender = text(args[ARG.SENDER])
    if sender and own ~= "" and FG.PlayerName.Equal(sender, own) then
      input.sender = own
    end
  end
  -- The class of the writer, for the color of the name (Battle.net partners have none).
  if type(ctx.classOf) == "function" and kind ~= "bnet" and not input.hidden then
    local sender = text(args[ARG.SENDER])
    if sender then
      local ok, class = pcall(ctx.classOf, sender, text(args[ARG.GUID]))
      input.class = ok and type(class) == "string" and class or nil
    end
  end
  return target, input, extra
end
