-- Pure rules of the whisper invite (Modules/Invites.lua): keyword match, who may ask, rate
-- limits and safety checks. No game calls; what the game knows comes in through input.get, so
-- every case is testable. A decision is { action = "invite" | "ignore", reason, keyword }.
local _, ns = ...

local IL = {}
ns.InviteLogic = IL

IL.MAX_WORDS = 8
IL.MAX_WORD = 20
IL.MAX_NAMES = 50
IL.MAX_REPLY = 120
IL.MAX_LEVEL = 80
IL.GROUP_SIZE = 5
IL.RAID_SIZE = 40
-- Wait per sender in seconds (settings.inviteSenderCooldown, 0 = off) and the requests per minute over all
-- senders (settings.inviteGlobalLimit, 0 = unlimited). SENDER_WINDOW is the default of the first.
IL.SENDER_WINDOW = 60
IL.SENDER_CHOICES = { 0, 15, 30, 60, 120, 300 }
IL.GLOBAL_WINDOW = 60
IL.GLOBAL_DEFAULT = 0
IL.GLOBAL_CHOICES = { 0, 20, 60, 200 }
IL.LOG_CAP = 50
IL.MODES = { "everyone", "friends", "guild", "communities", "own", "list" }
IL.SUGGESTED = "inv, invite"

local KNOWN_MODE = {}
for _, mode in ipairs(IL.MODES) do
  KNOWN_MODE[mode] = true
end

local function lower(s)
  local PN = ns.PlayerName
  return PN and PN.Lower(s) or s:lower()
end

local function cut(s, n)
  local PN = ns.PlayerName
  return PN and PN.Cut(s, n) or s:sub(1, n)
end

local function sameName(a, b)
  local PN = ns.PlayerName
  return PN and PN.Equal(a, b) or (a ~= "" and a:lower() == b:lower())
end

-- Settings values ------------------------------------------------------------------------------

function IL.CleanMode(v)
  return KNOWN_MODE[v] and v or "friends"
end

function IL.CleanLevel(v)
  v = tonumber(v)
  if not v or v ~= v then
    return 0
  end
  return math.max(0, math.min(IL.MAX_LEVEL, math.floor(v)))
end

-- Keywords ---------------------------------------------------------------------------------------

-- Trimmed, one blank between words, no control characters or pipes, lower case, without a
-- leading "!".
function IL.Normalize(text)
  if type(text) ~= "string" then
    return ""
  end
  text = text:gsub("[%z\1-\31\127|]", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  if text:sub(1, 1) == "!" then
    text = (text:sub(2):gsub("^%s+", ""))
  end
  return lower(text)
end

-- "Inv, !Invite ,inv" -> { "inv", "invite" }: at most MAX_WORDS words of MAX_WORD characters.
function IL.ParseWords(text)
  local out, seen = {}, {}
  if type(text) ~= "string" then
    return out
  end
  for part in (text .. ","):gmatch("([^,]*),") do
    local word = IL.Normalize(cut(IL.Normalize(part), IL.MAX_WORD))
    if word ~= "" and not seen[word] then
      seen[word] = true
      out[#out + 1] = word
      if #out >= IL.MAX_WORDS then
        break
      end
    end
  end
  return out
end

function IL.JoinWords(words)
  return table.concat(words, ", ")
end

-- The first matching keyword when the whole message or its first word is one of them.
function IL.Match(message, words)
  local text = IL.Normalize(message)
  if text == "" then
    return nil
  end
  -- A keyword is never a player name, so the first word may be cut at the blank.
  local first = text:match("^(%S+)")
  for _, word in ipairs(words or {}) do
    if text == word or first == word then
      return word
    end
  end
  return nil
end

-- Name lists ---------------------------------------------------------------------------------------

-- Names are separated by comma or line break; a name keeps its blank ("Anna Berg").
function IL.ParseNames(text)
  local out = {}
  if type(text) ~= "string" then
    return out
  end
  local PN = ns.PlayerName
  for part in (text:gsub("\n", ",") .. ","):gmatch("([^,]*),") do
    local name = PN and PN.Clean(part) or part
    if name ~= "" then
      out[#out + 1] = name
      if #out >= IL.MAX_NAMES then
        break
      end
    end
  end
  return out
end

function IL.Listed(names, who)
  if type(who) ~= "string" then
    return false
  end
  for _, name in ipairs(names or {}) do
    if sameName(name, who) then
      return true
    end
  end
  return false
end

-- Rate limit ---------------------------------------------------------------------------------------

local function cleanChoice(value, choices, default)
  local n = tonumber(value)
  for _, choice in ipairs(choices) do
    if n == choice then
      return choice
    end
  end
  return default
end

-- A stored wait per sender: one of the choices, else the default.
function IL.CleanCooldown(value)
  return cleanChoice(value, IL.SENDER_CHOICES, IL.SENDER_WINDOW)
end

-- A stored limit over all senders: one of the choices, else unlimited.
function IL.CleanGlobalLimit(value)
  return cleanChoice(value, IL.GLOBAL_CHOICES, IL.GLOBAL_DEFAULT)
end

function IL.NewRate()
  return { senders = {}, stamps = {} }
end

-- Group and guild count apart per sender, so one keyword in both lists invites to both.
function IL.RateKey(kind, sender)
  local PN = ns.PlayerName
  local key = type(sender) == "string" and (PN and PN.Key(sender) or sender:lower()) or ""
  return key ~= "" and (tostring(kind) .. ":" .. key) or ""
end

local function fresh(list, now, window)
  local keep = {}
  for _, at in ipairs(list) do
    if now - at < window then
      keep[#keep + 1] = at
    end
  end
  return keep
end

-- One request per sender and cooldown (0 = no wait), at most `limit` per GLOBAL_WINDOW over all senders (0 = no
-- limit). Both default to the settings defaults when nil or invalid; the settings are cleaned by the caller.
function IL.RateCheck(rate, key, now, cooldown, limit)
  cooldown = tonumber(cooldown)
  cooldown = cooldown and cooldown >= 0 and cooldown or IL.SENDER_WINDOW
  limit = tonumber(limit)
  limit = limit and limit >= 0 and limit or IL.GLOBAL_DEFAULT
  local last = rate.senders[key]
  if cooldown > 0 and last and now - last < cooldown then
    return false, "rate-sender"
  end
  if limit > 0 and #fresh(rate.stamps, now, IL.GLOBAL_WINDOW) >= limit then
    return false, "rate-global"
  end
  return true
end

-- Senders are kept as long as the longest choice, whatever the setting is now.
local KEEP = IL.SENDER_CHOICES[#IL.SENDER_CHOICES]

-- Notes a request that was taken. Also (re)starts the wait of the sender at `now`.
function IL.RateRecord(rate, key, now)
  rate.stamps = fresh(rate.stamps, now, IL.GLOBAL_WINDOW)
  rate.stamps[#rate.stamps + 1] = now
  for sender, at in pairs(rate.senders) do
    if now - at >= KEEP then
      rate.senders[sender] = nil
    end
  end
  rate.senders[key] = now
end

-- Starts the wait of a sender again without counting a request (the player declined or closed the window).
function IL.RateTouch(rate, key, now)
  if key ~= "" then
    rate.senders[key] = now
  end
end

-- Reply ------------------------------------------------------------------------------------------------

-- Template with %s for the name; nil for an empty template.
function IL.Reply(template, name)
  if type(template) ~= "string" or type(name) ~= "string" then
    return nil
  end
  template = template:gsub("[%z\1-\31\127|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  template = cut(template, IL.MAX_REPLY)
  if template == "" then
    return nil
  end
  name = name:gsub("[%z\1-\31\127|]", "")
  return (template:gsub("%%s", function()
    return name
  end))
end

-- Log ------------------------------------------------------------------------------------------------------

function IL.PushLog(list, entry)
  list[#list + 1] = entry
  while #list > IL.LOG_CAP do
    table.remove(list, 1)
  end
  return list
end

-- Decision -----------------------------------------------------------------------------------------

local function call(fn, ...)
  if type(fn) == "function" then
    return fn(...)
  end
  return nil
end

-- Why nobody can be invited to the group right now: "in-group", "group-full", "not-leader", else nil.
-- group = { hasGroup, members, isRaid, isLeader, senderInGroup } (nil = no group).
function IL.GroupBlock(group)
  group = group or {}
  if group.senderInGroup then
    return "in-group"
  end
  if group.hasGroup then
    if (group.members or 0) >= (group.isRaid and IL.RAID_SIZE or IL.GROUP_SIZE) then
      return "group-full"
    end
    if not group.isLeader then
      return "not-leader"
    end
  end
  return nil
end

-- input: kind ("group" | "guild"), cfg { enabled, words, mode, minLevel, skipAway },
-- message, sender, self, allow and block (name lists), now, rate, and get = functions the game
-- answers lazily (nil answer = unknown):
--   relation(mode) -> bool        sender is a friend / guild member / community member / own character
--   available(mode) -> bool       false when the client cannot answer that mode
--   level() -> number, sameFaction() -> bool, away() -> bool (own AFK or DND)
--   group() -> { hasGroup, members, isRaid, isLeader, senderInGroup }
--   canGuildInvite() -> bool, senderInGuild() -> bool
function IL.Decide(input)
  local cfg, get = input.cfg or {}, input.get or {}
  if not cfg.enabled then
    return { action = "ignore", reason = "off" }
  end
  if #(cfg.words or {}) == 0 then
    return { action = "ignore", reason = "no-keywords" }
  end
  local keyword = IL.Match(input.message, cfg.words)
  if not keyword then
    return { action = "ignore", reason = "no-match" }
  end
  local function no(reason)
    return { action = "ignore", reason = reason, keyword = keyword }
  end
  local sender = input.sender
  local key = IL.RateKey(input.kind, sender)
  if key == "" then
    return no("no-sender")
  end
  if sameName(sender, input.self or "") then
    return no("self")
  end
  if IL.Listed(input.block, sender) then
    return no("blocked")
  end
  if input.kind == "guild" and call(get.canGuildInvite) ~= true then
    return no("no-permission")
  end
  local mode = IL.CleanMode(cfg.mode)
  if mode ~= "everyone" then
    if call(get.available, mode) == false then
      return no("mode-unavailable")
    end
    local allowed
    if mode == "list" then
      allowed = IL.Listed(input.allow, sender)
    else
      allowed = call(get.relation, mode) == true
    end
    if not allowed then
      return no("mode")
    end
  end
  if cfg.skipAway and call(get.away) == true then
    return no("away")
  end
  local minLevel = IL.CleanLevel(cfg.minLevel)
  if minLevel > 0 then
    -- The whisper carries no level; an unknown level cannot pass a minimum.
    local level = tonumber(call(get.level))
    if not level then
      return no("level-unknown")
    end
    if level < minLevel then
      return no("level")
    end
  end
  if call(get.sameFaction) == false then
    return no("faction")
  end
  if input.kind == "guild" then
    if call(get.senderInGuild) == true then
      return no("in-guild")
    end
  else
    local blocked = IL.GroupBlock(call(get.group))
    if blocked then
      return no(blocked)
    end
  end
  if input.rate then
    local ok, reason = IL.RateCheck(input.rate, key, input.now or 0, input.cooldown, input.globalLimit)
    if not ok then
      return no(reason)
    end
  end
  return { action = "invite", reason = "ok", keyword = keyword }
end
