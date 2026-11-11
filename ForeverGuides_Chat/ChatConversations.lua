-- Forever Chat, the model of the conversations (pure, no game access, the caller passes every clock value).
-- A conversation is one chat partner or room in the list: whisper, party, raid, instance, guild, officer or
-- channel. Its messages live in a ring buffer in MEMORY only; nothing here touches SavedVariables. The
-- local chat history (settings.chat.enabled, off by default) may fill and read the buffers through
-- Import and Export, when the caller allows it (HistoryAllowed).
--
-- state = { convs = { [key] = conversation }, count, limits, pins, own }
-- conversation = { key, kind, name, lines, seq, readSeq, marked, last }   (readSeq and marked: ChatUnread.lua)
-- line = { seq, time, dir, sender, text, type, hidden, id, reply, reactions, unread, mention, class }
--   seq       counts up per conversation and never repeats, so a position survives dropped lines
--   dir       ChatHistoryLogic.DIR_IN or DIR_OUT
--   type      ChatHistoryLogic.TYPES id
--   hidden    text or sender could not be read (secret value), text is "" then
--   id        optional line id of the game, equal ids are one line
--   reply     placeholder: seq of the quoted line
--   reactions placeholder for the reactions of a line, never set yet
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local Logic, PN, Limits = FG.ChatHistoryLogic, FG.PlayerName, FG.ChatHistoryLimits
local fold = FG.LfgBrowseFilterLogic.Fold

local Conv = {}
chat.Conversations = Conv

-- "bnet" is a Battle.net whisper partner: read only, the game chat answers it.
Conv.KINDS = { "whisper", "bnet", "party", "raid", "instance", "guild", "officer", "channel", "local", "team" }
Conv.KEY_BYTES = 96

-- List tabs of the window (in this order) and the kinds in each. The tab "teams" holds the conversations of
-- the kind "team" that ChatTeams.lua fills.
Conv.TAB_ORDER = { "whisper", "group", "teams", "guild", "raid", "channel" }
Conv.TAB_KINDS = {
  whisper = { whisper = true, bnet = true },
  group = { party = true, instance = true },
  teams = { team = true },
  guild = { guild = true, officer = true },
  raid = { raid = true },
  channel = { channel = true, ["local"] = true },
}

local T = Logic.TYPES
Conv.DEFAULT_TYPE = {
  whisper = T.whisper,
  bnet = T.whisper,
  party = T.party,
  raid = T.raid,
  instance = T.party,
  guild = T.guild,
  officer = T.officer,
  channel = T.channel,
  ["local"] = T.say,
  team = T.party,
}

-- Every limit is clamped, nothing is unlimited. ageDays is used by Prune.
Conv.Limits = {
  lines = { default = 200, min = 25, max = 1000 },
  conversations = { default = 100, min = 10, max = 200 },
  chars = { default = 512, min = 255, max = 1024 },
  ageDays = { default = 30, min = 1, max = 365 },
}

-- A line equal to one of the last DEDUPE_LINES lines within DEDUPE_SECONDS is the same line twice.
Conv.DEDUPE_SECONDS = 2
Conv.DEDUPE_LINES = 5

local IN, OUT = Logic.DIR_IN, Logic.DIR_OUT
local KIND, KIND_RANK = {}, {}
for rank, kind in ipairs(Conv.KINDS) do
  KIND[kind] = true
  KIND_RANK[kind] = rank
end

local function isNumber(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function clamp(spec, value)
  if type(value) ~= "number" or value ~= value then
    return spec.default
  end
  return math.floor(math.min(spec.max, math.max(spec.min, value)) + 0.5)
end

-- The value, or nil when it is secret or the client says the add-on may not read it.
local function safe(value)
  local guard = FG.AutoGuard
  if guard and guard.Safe then
    return guard.Safe(value)
  end
  return value
end

-- Text of a line. Returns the text and false, "" and true for an unreadable value, nil for a missing or wrong one.
-- An unreadable value is never compared, only stored as the placeholder.
local function readText(value, chars)
  if value == nil then
    return nil
  end
  local readable = safe(value)
  if readable == nil then
    return "", true
  end
  if type(readable) ~= "string" then
    return nil
  end
  local ok, text = pcall(Logic.TruncateText, readable, chars)
  if not ok then
    return "", true
  end
  return text, false
end

-- The class token of a writer when it is one of the known classes (the color of the name), else nil.
local function knownClass(value)
  local kit = FG.GuildKit
  return type(value) == "string" and kit and kit.KNOWN_CLASS and kit.KNOWN_CLASS[value] and value or nil
end

local function readSender(value)
  if value == nil then
    return "", false
  end
  local readable = safe(value)
  if readable == nil then
    return "", true
  end
  if type(readable) ~= "string" then
    return "", false
  end
  local ok, name = pcall(PN.Clean, readable)
  if not ok then
    return "", true
  end
  return Limits.CutUtf8(name, Limits.NAME_MAX_BYTES), false
end

-- Control characters and pipes gone, white space runs one space, trimmed.
local function plain(text)
  text = text:gsub("[%z\1-\8\11\12\14-\31\127|]", ""):gsub("[ \t\r\n]+", " ")
  return (text:gsub("^ ", ""):gsub(" $", ""))
end

local function ident(value)
  if type(value) == "number" and isNumber(value) then
    return "#" .. math.floor(value)
  end
  if type(value) == "string" then
    return fold(plain(value))
  end
  return ""
end

-- The key of a conversation: the kind, a colon and the normalized name ("whisper:anna smith-realm",
-- "guild:my guild", "channel:trade", "channel:#5"). Party, raid and instance take an optional session
-- name or number ("party", "party:3"; "local" holds say, yell and emote lines). homeRealm (optional) is
-- dropped from whisper names. identity (optional, Battle.net partners): BattleTag or account id that replaces
-- the name in the key. nil for an unknown kind, a missing name or a key over KEY_BYTES.
function Conv.Key(kind, name, homeRealm, identity)
  if not KIND[kind] then
    return nil
  end
  local id
  if kind == "whisper" then
    id = type(name) == "string" and Logic.WhisperKey(name, homeRealm) or nil
  elseif kind == "bnet" and identity ~= nil then
    -- A Battle.net partner is told apart by account (BattleTag or account id), never by the name shown for it.
    id = ident(identity)
  else
    id = ident(name)
  end
  if kind == "party" or kind == "raid" or kind == "instance" or kind == "local" then
    id = id and id ~= "" and id or nil
    return id and (kind .. ":" .. id) or kind
  end
  if not id or id == "" then
    return nil
  end
  local key = kind .. ":" .. id
  return #key <= Conv.KEY_BYTES and key or nil
end

-- The kind of a key, nil for anything else.
function Conv.KindOf(key)
  local kind = type(key) == "string" and key:match("^(%a+)") or nil
  return KIND[kind] and kind or nil
end

local function displayName(kind, name)
  if type(name) == "number" then
    return "#" .. math.floor(name)
  end
  if type(name) ~= "string" then
    return ""
  end
  return Limits.CutUtf8(kind == "whisper" and PN.Clean(name) or plain(name), Limits.NAME_MAX_BYTES)
end

----------------------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------------------

-- limits: optional table with lines, conversations, chars, ageDays (clamped). pins: the table of pinned keys
-- (ForeverGuidesChatDB.pins, read live).
function Conv.New(limits, pins)
  local state = { convs = {}, count = 0, limits = {}, pins = type(pins) == "table" and pins or {}, own = "" }
  for key, spec in pairs(Conv.Limits) do
    state.limits[key] = clamp(spec, type(limits) == "table" and limits[key] or nil)
  end
  return state
end

-- The own full name, so own lines in group chats and whispers to oneself get the direction "out".
function Conv.SetOwn(state, name)
  state.own = type(name) == "string" and PN.Clean(name) or ""
end

function Conv.Get(state, key)
  return state.convs[key]
end

function Conv.Count(state)
  return state.count
end

function Conv.Remove(state, key)
  if not state.convs[key] then
    return false
  end
  state.convs[key] = nil
  state.count = state.count - 1
  return true
end

function Conv.Clear(state)
  state.convs, state.count = {}, 0
end

-- The line limit of a conversation: the limit of the state, or what state.lineLimit(conv) says (the archive
-- keeps more lines for some kinds than the plain memory buffer).
local function lineCap(state, conv)
  local fn = state.lineLimit
  local cap = type(fn) == "function" and fn(conv) or nil
  return isNumber(cap) and cap >= 1 and math.floor(cap) or state.limits.lines
end

-- Drops the oldest lines of a buffer, count of them.
local function dropFront(lines, count)
  local size = #lines
  if count <= 0 then
    return
  end
  count = math.min(count, size)
  for i = 1, size - count do
    lines[i] = lines[i + count]
  end
  for i = size - count + 1, size do
    lines[i] = nil
  end
end

-- The conversation that has been quiet longest goes, a pinned one stays. With force a pinned one goes when
-- everything is pinned, so a new line is never refused. False when nothing could go.
local function evict(state, force)
  local victim
  for _, conv in pairs(state.convs) do
    if force or state.pins[conv.key] ~= true then
      if not victim or conv.last < victim.last or (conv.last == victim.last and conv.key < victim.key) then
        victim = conv
      end
    end
  end
  return victim ~= nil and Conv.Remove(state, victim.key)
end

local function isDuplicate(lines, cand, ignoreDir)
  if cand.hidden then
    return false
  end
  for i = #lines, math.max(1, #lines - Conv.DEDUPE_LINES + 1), -1 do
    local line = lines[i]
    if not line.hidden then
      if cand.id and line.id and not ignoreDir then
        if cand.id == line.id then
          return true
        end
      elseif
        math.abs(cand.time - line.time) <= Conv.DEDUPE_SECONDS
        and line.text == cand.text
        and line.sender == cand.sender
        and line.type == cand.type
        and (ignoreDir or line.dir == cand.dir)
      then
        return true
      end
    end
  end
  return false
end

-- What the game says about a Battle.net partner right now: the character in the game (nil when the partner is
-- not in WoW), the BattleTag and the session account id. Taken from the target on every line, so a change shows.
function Conv.SetBnet(conv, target)
  local character = displayName("bnet", target.character)
  conv.character = character ~= "" and character or nil
  conv.tag = type(target.tag) == "string" and displayName("bnet", target.tag) or nil
  conv.accountId = isNumber(target.accountId) and target.accountId or nil
end

-- Adds a line. target = { kind, name, homeRealm, id, character, tag, accountId } names the conversation (see Key), input = { time, text,
-- sender, dir, type, id, reply }. Returns the line and its conversation, or nil and the reason:
-- "key", "time", "text" or "duplicate". A full list drops the quietest conversation, a pinned one only when
-- all are pinned: the newest line is never the one that falls.
-- Unreadable text or sender is stored as the placeholder (hidden, text ""), input.hidden asks for it. The line
-- is not counted as unread,
-- ChatUnread.Note does that.
function Conv.AddLine(state, target, input)
  if type(state) ~= "table" or type(target) ~= "table" or type(input) ~= "table" then
    return nil, "key"
  end
  local kind = target.kind
  local key = Conv.Key(kind, target.name, target.homeRealm, target.id)
  if not key then
    return nil, "key"
  end
  if not isNumber(input.time) then
    return nil, "time"
  end
  if state.onBefore then
    state.onBefore(key)
  end
  local limits = state.limits
  local text, hidden = readText(input.text, limits.chars)
  if input.hidden == true then
    text, hidden = "", true
  end
  if not text then
    return nil, "text"
  end
  local sender, senderHidden = readSender(input.sender)
  hidden = hidden or senderHidden
  if hidden then
    text = ""
  end
  local own = state.own ~= ""
  -- A whisper to oneself arrives twice (in and out): one line, always "out".
  local selfChat = kind == "whisper" and own and PN.Equal(target.name, state.own)
  local dir = input.dir == OUT and OUT or IN
  if selfChat or (own and not senderHidden and sender ~= "" and PN.Equal(sender, state.own)) then
    dir = OUT
  end
  local id = safe(input.id)
  local line = {
    time = math.floor(input.time),
    dir = dir,
    sender = sender,
    text = text,
    type = Logic.TYPE_NAMES[input.type] and input.type or Conv.DEFAULT_TYPE[kind],
    hidden = hidden or nil,
    id = isNumber(id) and id or nil,
    class = knownClass(input.class),
  }
  local conv = state.convs[key]
  if conv and isDuplicate(conv.lines, line, selfChat) then
    return nil, "duplicate"
  end
  if not conv then
    if state.count >= limits.conversations and not evict(state, false) and not evict(state, true) then
      return nil, "full"
    end
    conv = { key = key, kind = kind, name = "", lines = {}, seq = 0, readSeq = 0, marked = false, last = 0 }
    state.convs[key] = conv
    state.count = state.count + 1
  end
  local name = displayName(kind, target.name)
  if name ~= "" then
    conv.name = name
  end
  if target.public ~= nil then
    conv.public = target.public == true or nil
  end
  if kind == "bnet" then
    Conv.SetBnet(conv, target)
  end
  conv.seq = conv.seq + 1
  line.seq = conv.seq
  if isNumber(input.reply) and input.reply >= 1 and input.reply < line.seq then
    line.reply = math.floor(input.reply)
  end
  conv.lines[#conv.lines + 1] = line
  dropFront(conv.lines, #conv.lines - lineCap(state, conv))
  conv.last = math.max(conv.last, line.time)
  if state.onAdd then
    state.onAdd(conv, line)
  end
  return line, conv
end

-- The conversation of a target, made without a line when it does not exist yet (a new message the player is
-- about to write). Returns the conversation, or nil and why: "key" (no key for the target) or "full" (no
-- room: Ensure never drops another conversation). now (epoch seconds) is its first activity.
function Conv.Ensure(state, target, now)
  if type(state) ~= "table" or type(target) ~= "table" then
    return nil, "key"
  end
  local kind = target.kind
  local key = Conv.Key(kind, target.name, target.homeRealm, target.id)
  if not key then
    return nil, "key"
  end
  local conv = state.convs[key]
  if conv then
    return conv
  end
  if state.count >= state.limits.conversations then
    return nil, "full"
  end
  conv = { key = key, kind = kind, name = displayName(kind, target.name), lines = {}, seq = 0, readSeq = 0 }
  if kind == "bnet" then
    Conv.SetBnet(conv, target)
  end
  conv.marked, conv.last = false, isNumber(now) and math.floor(now) or 0
  state.convs[key] = conv
  state.count = state.count + 1
  return conv
end

-- Removes lines older than the age limit (ageDays) as seen from now. A conversation that runs empty goes.
-- Returns the number of removed lines.
function Conv.Prune(state, now)
  if not isNumber(now) then
    return 0
  end
  local cutoff, removed = now - state.limits.ageDays * Logic.SECONDS_PER_DAY, 0
  local empty = {}
  for key, conv in pairs(state.convs) do
    local kept = {}
    for _, line in ipairs(conv.lines) do
      if line.time >= cutoff then
        kept[#kept + 1] = line
      end
    end
    removed = removed + #conv.lines - #kept
    conv.lines = kept
    if #kept == 0 then
      empty[#empty + 1] = key
    end
  end
  for _, key in ipairs(empty) do
    Conv.Remove(state, key)
  end
  return removed
end

-- Tabs that list their kinds apart: after the pins, the kinds come in the order of KINDS.
Conv.KIND_SORTED_TABS = { whisper = true }

-- Pinned first, then (in a tab of KIND_SORTED_TABS) by kind, then the latest activity first, equal ones by key.
-- tab (optional): one of TAB_ORDER.
function Conv.Sorted(state, tab)
  local kinds = tab and Conv.TAB_KINDS[tab]
  local byKind = tab and Conv.KIND_SORTED_TABS[tab] and true or false
  local list = {}
  for _, conv in pairs(state.convs) do
    if not kinds or kinds[conv.kind] then
      list[#list + 1] = conv
    end
  end
  local pins = state.pins
  table.sort(list, function(a, b)
    local pinA, pinB = pins[a.key] == true, pins[b.key] == true
    if pinA ~= pinB then
      return pinA
    end
    if byKind and a.kind ~= b.kind then
      return KIND_RANK[a.kind] < KIND_RANK[b.kind]
    end
    if a.last ~= b.last then
      return a.last > b.last
    end
    return a.key < b.key
  end)
  return list
end

-- Puts the lines of conversation from into conversation into (same kind), in the order of their time,
-- without double lines, cut to the line limit. What was read in either stays read. from is gone.
-- The settings of the keys are joined by the caller (Store.Move). Returns whether it merged.
function Conv.Merge(state, intoKey, fromKey)
  local into, from = state.convs[intoKey], state.convs[fromKey]
  if not into or not from or into == from or into.kind ~= from.kind then
    return false
  end
  local all = {}
  for _, conv in ipairs({ into, from }) do
    for _, line in ipairs(conv.lines) do
      all[#all + 1] = { line = line, read = line.seq <= conv.readSeq, order = #all }
    end
  end
  table.sort(all, function(a, b)
    if a.line.time ~= b.line.time then
      return a.line.time < b.line.time
    end
    return a.order < b.order
  end)
  local lines, readSeq = {}, 0
  for _, item in ipairs(all) do
    if not isDuplicate(lines, item.line) then
      lines[#lines + 1] = item.line
      if item.read then
        readSeq = #lines
      end
    end
  end
  local drop = math.max(0, #lines - lineCap(state, into))
  dropFront(lines, drop)
  -- New positions, so a reply marker of the old numbering is gone.
  for i, line in ipairs(lines) do
    line.seq, line.reply = i, nil
  end
  into.lines, into.seq = lines, #lines
  into.readSeq = math.max(0, readSeq - drop)
  into.marked = into.marked or from.marked
  into.last = math.max(into.last, from.last)
  if into.name == "" then
    into.name = from.name
  end
  Conv.Remove(state, fromKey)
  return true
end

-- Puts a saved conversation back into memory (ChatArchive.lua). spec = { name, public, tag, character, lines }
-- with lines as { time, dir, sender, text, type } oldest first. The lines count as read and make no unread
-- mark. A conversation that exists already is left alone, so a new line never lands before older ones.
-- Returns the conversation, or nil and why: "key", "exists" or "full".
function Conv.Restore(state, key, spec)
  local kind = Conv.KindOf(key)
  if not kind or kind == "team" or type(spec) ~= "table" or type(spec.lines) ~= "table" then
    return nil, "key"
  end
  if state.convs[key] then
    return nil, "exists"
  end
  if state.count >= state.limits.conversations then
    return nil, "full"
  end
  local conv =
    { key = key, kind = kind, name = displayName(kind, spec.name), lines = {}, seq = 0, readSeq = 0, last = 0 }
  conv.marked = false
  conv.public = spec.public == true or nil
  if kind == "bnet" then
    Conv.SetBnet(conv, { character = spec.character, tag = spec.tag })
  end
  local cap = lineCap(state, conv)
  local from = math.max(1, #spec.lines - cap + 1)
  for i = from, #spec.lines do
    local line = spec.lines[i]
    conv.seq = conv.seq + 1
    conv.lines[#conv.lines + 1] = {
      seq = conv.seq,
      time = line.time,
      dir = line.dir,
      sender = line.sender,
      text = line.text,
      type = line.type,
    }
    conv.last = math.max(conv.last, line.time)
  end
  conv.readSeq = conv.seq
  state.convs[key] = conv
  state.count = state.count + 1
  return conv
end

----------------------------------------------------------------------------------------------------
-- Local chat history (opt-in)
----------------------------------------------------------------------------------------------------

-- The history may be used only with its main switch on (settings = ForeverGuides settings table).
function Conv.HistoryAllowed(settings)
  return type(settings) == "table" and type(settings.chat) == "table" and settings.chat.enabled == true
end

-- The lines of a conversation in the format of the history (ChatHistoryLogic lines, oldest first). Lines
-- with an unreadable text are left out.
function Conv.Export(state, conv, ownName)
  local out = {}
  for _, line in ipairs(conv.lines) do
    if not line.hidden then
      local entry
      if conv.kind == "whisper" then
        entry = Logic.MakeWhisperLine(line.time, line.dir, line.sender, line.text, ownName or "", state.limits.chars)
      else
        entry = Logic.MakeLine(line.time, line.type, line.sender, line.text, state.limits.chars)
      end
      out[#out + 1] = entry
    end
  end
  return out
end

-- Fills a conversation from history lines (oldest first). The lines count as read. Returns the number
-- of lines taken.
function Conv.Import(state, target, entries)
  local count = 0
  if type(entries) ~= "table" then
    return count
  end
  local F = Logic.FIELDS
  for _, entry in ipairs(entries) do
    if type(entry) == "table" then
      local line = Conv.AddLine(state, target, {
        time = entry[F.TIME],
        type = entry[F.TYPE],
        sender = entry[F.SENDER],
        text = entry[F.TEXT],
        dir = entry[F.DIR],
      })
      if line then
        count = count + 1
      end
    end
  end
  return count
end

-- The state of this session. The pinned keys are the ones of the store.
chat.convs = Conv.New(nil, chat.db and chat.db.pins)
