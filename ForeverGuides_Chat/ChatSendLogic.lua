-- Forever Chat, the logic of sending (pure, no game access, the caller passes every game fact): cutting a text
-- into parts the chat accepts, chat type and target of a conversation, the availability of a conversation
-- and the delivery states of a message.
--
-- job = { id, conv, chatType, target, parts, lines, index, state, reason, time, attempts, gated }
--   conv      { key, kind, name } of the conversation
--   index     the next part to send (> #parts once everything went out)
--   lines     the line of each part in the conversation (false when none was kept)
--   state     one of SL.STATES, reason says why for waiting and failed (see below)
--   gated     the game accepts one part per click only (numbered channels outside instances)
-- Refusal reasons of Split and Route: text, empty, toolong, markup, utf8, unsplittable, conversation, target,
-- channel. Availability: group, raid, instance, guild, officer. Job reasons: restricted, click, expired,
-- discarded, error, rejected, notfound, queuefull, plus the availability reasons.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local PN = FG.PlayerName

local SL = {}
chat.SendLogic = SL

SL.MAX_BYTES = 255
SL.MAX_PARTS = 8
SL.DELAY = 0.3
SL.NOT_FOUND_WINDOW = 15
SL.NOT_FOUND_FALLBACK = "No player named '%s' is currently playing."

SL.CHAT_TYPES = {
  whisper = "WHISPER",
  party = "PARTY",
  raid = "RAID",
  instance = "INSTANCE_CHAT",
  guild = "GUILD",
  officer = "OFFICER",
  channel = "CHANNEL",
}

SL.STATES = { "queued", "sending", "sent", "failed", "waiting" }

----------------------------------------------------------------------------------------------------
-- Cutting
----------------------------------------------------------------------------------------------------

-- Length of the UTF-8 character that starts with this byte, nil for a byte that starts none.
local function charLength(byte)
  if byte < 0x80 then
    return 1
  elseif byte >= 0xC2 and byte < 0xE0 then
    return 2
  elseif byte >= 0xE0 and byte < 0xF0 then
    return 3
  elseif byte >= 0xF0 and byte < 0xF5 then
    return 4
  end
end

-- Tabs and line breaks become blanks, other control characters go, the ends are trimmed.
local function clean(text)
  text = text:gsub("[\t\r\n]", " "):gsub("[%z\1-\8\11\12\14-\31\127]", "")
  return (text:gsub("^ +", ""):gsub(" +$", ""))
end

-- One element of the text at pos: kind ("text", "space", "color", "reset", "link"), its bytes and the next
-- position. nil and a reason for broken markup or UTF-8.
local function nextItem(text, pos)
  local byte = text:byte(pos)
  if byte == 124 then
    local two = text:sub(pos, pos + 1)
    if two == "||" then
      return "text", two, pos + 2
    elseif two == "|r" then
      return "reset", two, pos + 2
    elseif two == "|c" then
      local color = text:match("^|c%x%x%x%x%x%x%x%x", pos)
      if color then
        return "color", color, pos + #color
      end
    elseif two == "|H" then
      local _, headEnd = text:find("^|H[^|]*|h", pos)
      local _, bodyEnd = text:find("|h", (headEnd or pos) + 1, true)
      if headEnd and bodyEnd then
        return "link", text:sub(pos, bodyEnd), bodyEnd + 1
      end
    elseif two == "|T" or two == "|A" then
      local _, closeAt = text:find(two == "|T" and "^|T[^|]*|t" or "^|A[^|]*|a", pos)
      if closeAt then
        return "link", text:sub(pos, closeAt), closeAt + 1
      end
    end
    return nil, "markup"
  end
  if byte == 32 then
    return "space", " ", pos + 1
  end
  local length = charLength(byte)
  if not length then
    return nil, "utf8"
  end
  local char = text:sub(pos, pos + length - 1)
  if #char < length or char:find("[^\128-\191]", 2) then
    return nil, "utf8"
  end
  return "text", char, pos + length
end

-- Units that must not be cut apart: a color code belongs to the element behind it, a reset to the one in
-- front of it. unit = { s = bytes, space = true for a plain blank, after = the color still open behind it }.
local function tokenize(text)
  local units, active, pending, pendingColor = {}, nil, "", nil
  local pos, size = 1, #text
  while pos <= size do
    local kind, s, nextPos = nextItem(text, pos)
    if not kind then
      return nil, s
    end
    pos = nextPos
    if kind == "color" then
      pending, pendingColor = pending .. s, s
    elseif kind == "reset" and pending == "" and #units > 0 then
      local unit = units[#units]
      unit.s, unit.space, unit.after, active = unit.s .. s, false, nil, nil
    else
      if pendingColor then
        active, pendingColor = pendingColor, nil
      end
      local unit = { s = pending .. s, space = kind == "space" and pending == "", after = active }
      pending = ""
      if kind == "reset" then
        active, unit.after = nil, nil
      end
      units[#units + 1] = unit
    end
  end
  if pending ~= "" then
    units[#units + 1] = { s = pending, space = false, after = pendingColor }
  end
  return units
end

-- Cuts a text into parts of at most maxBytes bytes (default 255). Never inside a UTF-8 character, a link,
-- a texture or a color code, preferably at a blank. A color still open at the end of a part is closed there
-- and opened again in the next one. Returns the list of parts, or nil and a reason: "text" (no string),
-- "empty", "toolong" (more than maxParts parts), "markup" (a broken or unknown escape), "utf8" (invalid),
-- "unsplittable" (one element does not fit into a part).
function SL.Split(text, maxBytes, maxParts)
  if type(text) ~= "string" then
    return nil, "text"
  end
  maxBytes = math.min(SL.MAX_BYTES, math.max(20, math.floor(tonumber(maxBytes) or SL.MAX_BYTES)))
  maxParts = math.max(1, math.floor(tonumber(maxParts) or SL.MAX_PARTS))
  if #text > 2 * maxParts * maxBytes then
    return nil, "toolong"
  end
  text = clean(text)
  if text == "" then
    return nil, "empty"
  end
  if #text > maxParts * maxBytes then
    return nil, "toolong"
  end
  local units, reason = tokenize(text)
  if not units then
    return nil, reason
  end
  local parts, count, i, carry = {}, #units, 1, nil
  while i <= count do
    local bytes, j, lastSpace = carry and #carry or 0, i, nil
    while j <= count do
      local unit = units[j]
      if bytes + #unit.s + (unit.after and 2 or 0) > maxBytes then
        break
      end
      -- A blank early in the part is no good place to cut, the part would stay mostly empty.
      if unit.space and bytes * 2 >= maxBytes then
        lastSpace = j
      end
      bytes = bytes + #unit.s
      j = j + 1
    end
    if j == i then
      return nil, "unsplittable"
    end
    local last, nextStart = j - 1, j
    if j <= count and not units[j].space and lastSpace and lastSpace > i then
      last, nextStart = lastSpace - 1, lastSpace
    end
    while last > i and units[last].space do
      last = last - 1
    end
    local pieces = { carry }
    for k = i, last do
      pieces[#pieces + 1] = units[k].s
    end
    local after = units[last].after
    if after then
      pieces[#pieces + 1] = "|r"
    end
    parts[#parts + 1] = table.concat(pieces)
    if #parts > maxParts then
      return nil, "toolong"
    end
    carry, i = after, nextStart
    while i <= count and units[i].space do
      i = i + 1
    end
  end
  return parts
end

----------------------------------------------------------------------------------------------------
-- Chat type, target and availability
----------------------------------------------------------------------------------------------------

-- { kind, name } of a conversation (a table with key, kind, name, or a key). The name keeps its letter case
-- when the conversation has one, a key is lower case only. nil for an unknown kind.
function SL.Target(conv)
  local key, kind, name
  if type(conv) == "table" then
    key, kind, name = conv.key, conv.kind, conv.name
  else
    key = conv
  end
  if type(key) == "string" then
    kind = kind or key:match("^(%a+)")
    if type(name) ~= "string" or name == "" then
      name = key:match("^%a+:(.+)$")
    end
  end
  if type(kind) ~= "string" or not SL.CHAT_TYPES[kind] then
    return nil
  end
  return { kind = kind, name = type(name) == "string" and name or "" }
end

-- Chat type and target for SendChatMessage: "WHISPER" and the full name (spaces and realm kept, see
-- PlayerName), "CHANNEL" and the channel number, any other type and nil. nil and a reason when there is no
-- target. resolveChannel(nameOrNumber) returns the number of a channel the player has joined, or nil.
function SL.Route(conv, resolveChannel)
  local target = SL.Target(conv)
  if not target then
    return nil, "conversation"
  end
  local kind = target.kind
  if kind == "whisper" then
    local name = PN.Clean(target.name)
    if name == "" then
      return nil, "target"
    end
    return "WHISPER", name
  elseif kind == "channel" then
    local ref = tonumber(target.name:match("^#(%d+)$")) or target.name
    local id = type(resolveChannel) == "function" and resolveChannel(ref) or nil
    if type(id) ~= "number" or id < 1 then
      return nil, "channel"
    end
    return "CHANNEL", id
  end
  return SL.CHAT_TYPES[kind], nil
end

-- Whether the player can write to the conversation now. facts = { inHomeGroup, inInstanceGroup, inRaid,
-- inGuild, guildName, canOfficer }; a fact that is nil is unknown and never blocks. Returns true, or false
-- and a reason: group, raid, instance, guild, officer.
function SL.Available(conv, facts)
  local target = SL.Target(conv)
  if not target then
    return false, "conversation"
  end
  facts = type(facts) == "table" and facts or {}
  local kind = target.kind
  if kind == "party" then
    if facts.inRaid == true then
      return false, "raid"
    end
    if facts.inHomeGroup == false then
      return false, "group"
    end
  elseif kind == "raid" then
    if facts.inRaid == false then
      return false, "raid"
    end
  elseif kind == "instance" then
    if facts.inInstanceGroup == false then
      return false, "instance"
    end
  elseif kind == "guild" or kind == "officer" then
    if facts.inGuild == false then
      return false, "guild"
    end
    local name, current = PN.Lower(PN.Clean(target.name)), type(facts.guildName) == "string" and facts.guildName
    if name ~= "" and current and name ~= PN.Lower(PN.Clean(current)) then
      return false, "guild"
    end
    if kind == "officer" and facts.canOfficer == false then
      return false, "officer"
    end
  end
  return true
end

----------------------------------------------------------------------------------------------------
-- Delivery states
----------------------------------------------------------------------------------------------------

-- queued: waits for its turn. sending: some parts went out. sent: all parts went out. waiting: held back
-- (restriction, one part per click), only a click moves it on. failed: the game refused it, a click can
-- try again. A sent message turns failed when the game later answers "no such player".
local MOVES = {
  queued = { sending = true, waiting = true, failed = true },
  sending = { sent = true, waiting = true, failed = true },
  waiting = { queued = true, failed = true },
  failed = { queued = true },
  sent = { failed = true },
}

-- A new job. conv: { key, kind, name }. nil when chat type or parts are missing.
function SL.NewJob(id, conv, chatType, target, parts, now)
  if type(conv) ~= "table" or type(chatType) ~= "string" or type(parts) ~= "table" or #parts == 0 then
    return nil
  end
  return {
    id = id,
    conv = { key = conv.key, kind = conv.kind, name = conv.name },
    chatType = chatType,
    target = target,
    parts = parts,
    lines = {},
    index = 1,
    state = "queued",
    time = now,
    attempts = 0,
  }
end

-- Moves a job to a state the automaton allows. Leaving "waiting" or "failed" for "queued" (release,
-- retry) needs byClick = true: nothing is ever sent again on its own. Returns true, or false and
-- "state" or "click". reason is kept for waiting and failed, cleared otherwise.
function SL.Move(job, to, reason, byClick)
  local moves = type(job) == "table" and MOVES[job.state]
  if not moves or not moves[to] then
    return false, "state"
  end
  if to == "queued" and byClick ~= true then
    return false, "click"
  end
  if job.state == "failed" and to == "queued" then
    job.attempts = job.attempts + 1
  end
  job.state = to
  job.reason = (to == "waiting" or to == "failed") and reason or nil
  return true
end

-- State and reason of a finished SendChatMessage call: ok is the pcall result, ret what the game returned.
-- A raised error is "error", an explicit false "rejected".
function SL.Outcome(ok, ret)
  if not ok then
    return "failed", "error"
  end
  if ret == false then
    return "failed", "rejected"
  end
  return "sent"
end

-- The name in the game's "no player named X" message (template: ERR_CHAT_PLAYER_NOT_FOUND_S), nil for any
-- other text.
function SL.NotFoundName(text, template)
  if type(text) ~= "string" then
    return nil
  end
  if type(template) ~= "string" or template == "" then
    template = SL.NOT_FOUND_FALLBACK
  end
  local escaped = template:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  return text:match("^" .. escaped:gsub("%%%%s", "(.+)") .. "$")
end
