-- Forever Chat, the rules of the teams (pure, no game access, the caller passes every clock value): the team and
-- its members, the changes only admins may make, the merge of two states, messages and their history, the
-- invitations of strangers, the block list, and the wire format of every packet of the function teamChat.
--
-- team = { id, name, icon, epoch, by, created, members = { [name] = { role = "admin"|"member", joined } } }
--   epoch   counts up with every change of the team (a number, never a clock): the higher epoch wins a merge.
--   by      who made the change of this epoch; at equal epochs the state of the smaller name wins.
-- message = { sender, counter, time, text }   counter rises strictly per sender and team, time is for display only
-- history = { msgs = { message, ... } oldest first, floor = { [sender key] = highest counter that was pruned } }
-- Nothing on the wire is trusted: the sender of a packet is the player name of the game, every payload is read
-- strictly (printable ASCII, escaped text, limits), and a text is plain text (no codes of the game).
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local PN = FG.PlayerName

local TL = {}
chat.TeamsLogic = TL

TL.LIMITS = {
  NAME_CHARS = 24,
  MAX_MEMBERS = 80,
  -- Longest roster payload (characters, escaped): 80 usual names are about 3300, this is the room for long names and
  -- stays under what one transfer of the line (25 blocks) and the queue of the line (40) can carry.
  ROSTER_CHARS = 5500,
  MAX_TEAMS = 30,
  MAX_ICON = 20000000,
  DEFAULT_ICON = 134400,
  -- Bytes of the text of one message, and the longest escaped form that still fits one block of the line.
  TEXT_BYTES = 200,
  TEXT_ESCAPED = 180,
  -- Longest text one send may carry (in bytes), cut into parts of TEXT_BYTES.
  MAX_TEXT = 1600,
  MAX_COUNTER = 999999999,
  HISTORY_MESSAGES = 500,
  -- Messages one character keeps over all its teams (about 1 MB in the saved variables), the oldest fall out first.
  HISTORY_TOTAL = 3000,
  HISTORY_DAYS = 30,
  SYNC_MESSAGES = 50,
  SYNC_CHARS = 3300,
  MAX_INVITES = 10,
  INVITE_TTL = 86400,
  INVITES_PER_HOUR = 3,
  MAX_BLOCKED = 100,
  MAX_CHARACTERS = 10,
  MAX_ID_LENGTH = 10,
  -- How far a stated time may lie in the future (seconds).
  FUTURE_SLACK = 60,
}
local L = TL.LIMITS
local SECONDS_PER_DAY = 86400
local MAX_TIME = 4102444800

local function isInt(v, lo, hi)
  return type(v) == "number" and v == v and v == math.floor(v) and v >= lo and v <= hi
end

----------------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------------

-- Number of characters of a valid UTF-8 string, nil for anything else (overlong forms and surrogates included).
function TL.Utf8Length(s)
  if type(s) ~= "string" then
    return nil
  end
  local i, n, size = 1, 0, #s
  while i <= size do
    local b = s:byte(i)
    local len
    if b < 0x80 then
      len = 1
    elseif b >= 0xC2 and b < 0xE0 then
      len = 2
    elseif b >= 0xE0 and b < 0xF0 then
      len = 3
    elseif b >= 0xF0 and b < 0xF5 then
      len = 4
    else
      return nil
    end
    if i + len - 1 > size then
      return nil
    end
    for k = 1, len - 1 do
      local c = s:byte(i + k)
      if c < 0x80 or c > 0xBF then
        return nil
      end
    end
    if len > 1 then
      local c = s:byte(i + 1)
      if
        (b == 0xE0 and c < 0xA0)
        or (b == 0xED and c > 0x9F)
        or (b == 0xF0 and c < 0x90)
        or (b == 0xF4 and c > 0x8F)
      then
        return nil
      end
    end
    i, n = i + len, n + 1
  end
  return n
end

local function charLength(b)
  if b < 0x80 then
    return 1
  elseif b < 0xE0 then
    return 2
  elseif b < 0xF0 then
    return 3
  end
  return 4
end

-- Cuts a valid UTF-8 string to at most `maxChars` characters.
local function cutChars(s, maxChars)
  local i, n = 1, 0
  while i <= #s and n < maxChars do
    i, n = i + charLength(s:byte(i)), n + 1
  end
  return s:sub(1, i - 1)
end

-- Plain text of a message: no pipe codes of the game (a pipe becomes a broken bar), no control characters, white
-- space runs are one blank, trimmed, cut to `maxBytes` at a character border. nil for a string that is not
-- valid UTF-8 or no string.
function TL.CleanText(text, maxBytes)
  if not TL.Utf8Length(text) then
    return nil
  end
  text = text:gsub("|", "\194\166"):gsub("\194[\128-\159]", ""):gsub("[\t\r\n ]+", " ")
  text = text:gsub("[%z\1-\31\127]", "")
  text = text:gsub("^ +", ""):gsub(" +$", "")
  maxBytes = maxBytes or L.TEXT_BYTES
  if #text > maxBytes then
    local cut = maxBytes
    while cut > 0 and text:byte(cut + 1) and text:byte(cut + 1) >= 0x80 and text:byte(cut + 1) < 0xC0 do
      cut = cut - 1
    end
    text = text:sub(1, cut):gsub(" +$", "")
  end
  return text
end

-- Name of a team: plain, at most NAME_CHARS characters. "" for something unusable.
function TL.CleanName(name)
  if type(name) ~= "string" then
    return ""
  end
  local plain = TL.CleanText(name, 200)
  if not plain then
    return ""
  end
  return (cutChars(plain, L.NAME_CHARS):gsub(" +$", ""))
end

-- A symbol is the file id of an icon: a whole number in the range of the game's file ids.
function TL.CleanIcon(icon)
  if isInt(icon, 1, L.MAX_ICON) then
    return icon
  end
end

-- A member name, as the game writes a whisper target (see PlayerName.CheckWhisper), nil for anything else.
function TL.CleanMember(name)
  if type(name) ~= "string" or #name > 64 or not TL.Utf8Length(name) then
    return nil
  end
  local clean = PN.Clean(name)
  if clean == "" or clean ~= name then
    return nil
  end
  local ok = PN.CheckWhisper(clean)
  return ok and clean or nil
end

-- Splits a text into parts of at most TEXT_BYTES bytes and TEXT_ESCAPED escaped characters, never inside a
-- character, preferably at a blank. Returns the parts, or nil and "text", "utf8", "empty" or "toolong".
function TL.Split(text)
  if type(text) ~= "string" then
    return nil, "text"
  end
  if not TL.Utf8Length(text) then
    return nil, "utf8"
  end
  local plain = TL.CleanText(text, 1 / 0)
  if plain == "" then
    return nil, "empty"
  end
  if #plain > L.MAX_TEXT then
    return nil, "toolong"
  end
  local parts, i, size = {}, 1, #plain
  while i <= size do
    local j, bytes, escaped, lastBlank = i, 0, 0, nil
    while j <= size do
      local len = charLength(plain:byte(j))
      local piece = plain:sub(j, j + len - 1)
      local cost = #TL.Esc(piece)
      if bytes + len > L.TEXT_BYTES or escaped + cost > L.TEXT_ESCAPED then
        break
      end
      if piece == " " and bytes * 2 >= L.TEXT_BYTES * 0.4 then
        lastBlank = j
      end
      bytes, escaped, j = bytes + len, escaped + cost, j + len
    end
    local cut = j
    if j <= size and lastBlank and plain:sub(j, j) ~= " " then
      cut = lastBlank
    end
    local part = plain:sub(i, cut - 1):gsub(" +$", "")
    parts[#parts + 1] = part
    i = cut
    while plain:sub(i, i) == " " do
      i = i + 1
    end
  end
  return parts
end

-- Wire escaping: everything outside a short safe set becomes %XX, so a field never holds a separator, a pipe or
-- a byte of a multi-byte character.
local SAFE = "[^%w ._'!?()+=*/@#&$<>%[%]{}^\"%-]"

function TL.Esc(s)
  return (s:gsub(SAFE, function(c)
    return string.format("%%%02X", c:byte())
  end))
end

-- Reverse of Esc; nil for a `%` that does not start two hex digits.
function TL.Unesc(s)
  if type(s) ~= "string" or s:gsub("%%%x%x", ""):find("%%") then
    return nil
  end
  return (s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

----------------------------------------------------------------------------------------------------
-- Teams
----------------------------------------------------------------------------------------------------

local ID_CHARS = "0123456789abcdefghijklmnopqrstuvwxyz"

function TL.ValidId(id)
  return type(id) == "string" and #id == L.MAX_ID_LENGTH and not id:find("[^0-9a-z]")
end

-- Random team id of 10 characters. `random(n)` returns an integer from 1 to n.
function TL.NewId(random)
  random = random or math.random
  local out = {}
  for k = 1, L.MAX_ID_LENGTH do
    local r = tonumber(random(#ID_CHARS))
    if not r or r ~= r then
      r = 1
    end
    r = math.min(#ID_CHARS, math.max(1, math.floor(r)))
    out[k] = ID_CHARS:sub(r, r)
  end
  return table.concat(out)
end

-- The name as stored in the team and its entry, found without regard to letter case; nil when not a member.
function TL.Find(team, name)
  if type(team) ~= "table" or type(name) ~= "string" then
    return nil
  end
  local key = PN.Key(name)
  if key == "" then
    return nil
  end
  for stored, entry in pairs(team.members) do
    if PN.Key(stored) == key then
      return stored, entry
    end
  end
end

function TL.Count(team)
  local n = 0
  for _ in pairs(team.members) do
    n = n + 1
  end
  return n
end

-- Member names in a fixed order: admins first, then by name.
function TL.Names(team)
  local list = {}
  for name in pairs(team.members) do
    list[#list + 1] = name
  end
  table.sort(list, function(a, b)
    local ra, rb = team.members[a].role == "admin", team.members[b].role == "admin"
    if ra ~= rb then
      return ra
    end
    return PN.Key(a) < PN.Key(b)
  end)
  return list
end

function TL.IsAdmin(team, name)
  local _, entry = TL.Find(team, name)
  return entry ~= nil and entry.role == "admin"
end

-- A new team: the creator is its only member and admin. Returns the team, or nil and "name", "icon" or "creator".
function TL.New(id, name, icon, creator, now)
  local clean = TL.CleanName(name)
  if clean == "" then
    return nil, "name"
  end
  if icon == nil then
    icon = L.DEFAULT_ICON
  end
  if not TL.CleanIcon(icon) then
    return nil, "icon"
  end
  local who = TL.CleanMember(creator)
  if not TL.ValidId(id) or not who then
    return nil, "creator"
  end
  return {
    id = id,
    name = clean,
    icon = icon,
    epoch = 1,
    by = who,
    created = now,
    members = { [who] = { role = "admin", joined = now } },
  }
end

local function adminCount(team)
  local n = 0
  for _, entry in pairs(team.members) do
    if entry.role == "admin" then
      n = n + 1
    end
  end
  return n
end

-- Somebody has to administrate: when the last admin is gone, the member who joined first takes over.
local function ensureAdmin(team)
  if adminCount(team) > 0 or next(team.members) == nil then
    return
  end
  local pick
  for name, entry in pairs(team.members) do
    if
      not pick
      or entry.joined < team.members[pick].joined
      or (entry.joined == team.members[pick].joined and PN.Key(name) < PN.Key(pick))
    then
      pick = name
    end
  end
  team.members[pick].role = "admin"
end

-- A change of a team by `sender`. op = { kind = "add", name, joined } | "remove", name | "leave" | "role", name,
-- admin | "name", name | "icon", icon. Only admins change a team; a member may only remove himself (leave).
-- On success the team is changed, its epoch is one higher and `by` is the sender. Returns true and, when the
-- last member left, "empty"; or false and a reason: notmember, notadmin, self, unknown, member, full, name, icon,
-- lastadmin, op.
function TL.Apply(team, sender, op)
  local sName, sEntry = TL.Find(team, sender)
  if not sEntry then
    return false, "notmember"
  end
  local admin = sEntry.role == "admin"
  local kind = type(op) == "table" and op.kind
  if kind == "leave" then
    team.members[sName] = nil
  elseif kind == "remove" then
    local tName = TL.Find(team, op.name)
    if not tName then
      return false, "unknown"
    end
    if tName == sName then
      return false, "self"
    end
    if not admin then
      return false, "notadmin"
    end
    team.members[tName] = nil
  elseif kind == "add" then
    if not admin then
      return false, "notadmin"
    end
    local who = TL.CleanMember(op.name)
    if not who then
      return false, "name"
    end
    if TL.Find(team, who) then
      return false, "member"
    end
    if TL.Count(team) >= L.MAX_MEMBERS then
      return false, "full"
    end
    team.members[who] = { role = "member", joined = isInt(op.joined, 0, MAX_TIME) and op.joined or 0 }
    if #TL.EncodeRoster(team) > L.ROSTER_CHARS then
      team.members[who] = nil
      return false, "full"
    end
  elseif kind == "role" then
    if not admin then
      return false, "notadmin"
    end
    local _, tEntry = TL.Find(team, op.name)
    if not tEntry then
      return false, "unknown"
    end
    if op.admin ~= true and tEntry.role == "admin" and adminCount(team) <= 1 then
      return false, "lastadmin"
    end
    tEntry.role = op.admin == true and "admin" or "member"
  elseif kind == "name" then
    if not admin then
      return false, "notadmin"
    end
    local clean = TL.CleanName(op.name)
    if clean == "" then
      return false, "name"
    end
    team.name = clean
  elseif kind == "icon" then
    if not admin then
      return false, "notadmin"
    end
    if not TL.CleanIcon(op.icon) then
      return false, "icon"
    end
    team.icon = op.icon
  else
    return false, "op"
  end
  ensureAdmin(team)
  team.epoch, team.by = team.epoch + 1, sName
  if next(team.members) == nil then
    return true, "empty"
  end
  return true
end

-- A change that arrived with the epoch it makes. Returns the result of Apply as "applied" (or "empty"), or:
-- "stale" (an older epoch), "conflict" (the same epoch from another admin, merge by roster), "gap" (changes
-- are missing, ask for the roster), "denied" (not allowed, with the reason second) or "invalid".
function TL.ApplyRemote(team, sender, epoch, op)
  if not isInt(epoch, 1, L.MAX_COUNTER) then
    return "invalid"
  end
  local _, entry = TL.Find(team, sender)
  if not entry then
    return "denied", "notmember"
  end
  if epoch < team.epoch then
    return "stale"
  end
  if epoch == team.epoch then
    return "conflict"
  end
  if epoch > team.epoch + 1 then
    return "gap"
  end
  local ok, why = TL.Apply(team, sender, op)
  if not ok then
    return "denied", why
  end
  return why == "empty" and "empty" or "applied"
end

-- True when two states are the same.
function TL.SameState(a, b)
  if a.epoch ~= b.epoch or a.by ~= b.by or a.name ~= b.name or a.icon ~= b.icon or TL.Count(a) ~= TL.Count(b) then
    return false
  end
  for name, entry in pairs(a.members) do
    local _, other = TL.Find(b, name)
    if not other or other.role ~= entry.role then
      return false
    end
  end
  return true
end

-- Which of two states of one team wins: "remote", "local" or "same". The higher epoch wins; at equal epochs the
-- state of the admin with the smaller name. The time of a sender never counts.
function TL.Merge(localTeam, remote)
  if remote.epoch ~= localTeam.epoch then
    return remote.epoch > localTeam.epoch and "remote" or "local"
  end
  if TL.SameState(localTeam, remote) then
    return "same"
  end
  local a, b = PN.Key(localTeam.by), PN.Key(remote.by)
  if a == b then
    return "local"
  end
  return b < a and "remote" or "local"
end

----------------------------------------------------------------------------------------------------
-- History
----------------------------------------------------------------------------------------------------

function TL.NewHistory()
  return { msgs = {}, floor = {} }
end

-- Clamps a stated time: never older than the history keeps and never later than a minute from now.
function TL.ClampTime(t, now)
  if type(t) ~= "number" or t ~= t then
    return now
  end
  return math.floor(math.min(now + L.FUTURE_SLACK, math.max(now - L.HISTORY_DAYS * SECONDS_PER_DAY, t)))
end

local function before(a, b)
  if a.time ~= b.time then
    return a.time < b.time
  end
  local ka, kb = PN.Key(a.sender), PN.Key(b.sender)
  if ka ~= kb then
    return ka < kb
  end
  return a.counter < b.counter
end

-- Drops what is too old or over the cap and raises the floor of the sender, so a dropped message cannot come
-- back as a new one. Returns the number of dropped messages.
function TL.Prune(h, now)
  local cutoff, dropped = now - L.HISTORY_DAYS * SECONDS_PER_DAY, 0
  local function drop(i)
    local m = table.remove(h.msgs, i)
    local key = PN.Key(m.sender)
    h.floor[key] = math.max(h.floor[key] or 0, m.counter)
    dropped = dropped + 1
  end
  for i = #h.msgs, 1, -1 do
    if h.msgs[i].time < cutoff then
      drop(i)
    end
  end
  while #h.msgs > L.HISTORY_MESSAGES do
    drop(1)
  end
  return dropped
end

-- Keeps at most HISTORY_TOTAL messages over all histories ({ [team id] = history }): the oldest of all go first and
-- raise the floor of their sender. Returns the number of dropped messages.
function TL.PruneTotal(histories)
  local total, dropped = 0, 0
  for _, h in pairs(histories) do
    total = total + #h.msgs
  end
  while total > L.HISTORY_TOTAL do
    local oldest, from, fromId
    for id, h in pairs(histories) do
      local first = h.msgs[1]
      if first and (not oldest or first.time < oldest.time or (first.time == oldest.time and id < fromId)) then
        oldest, from, fromId = first, h, id
      end
    end
    if not from then
      break
    end
    table.remove(from.msgs, 1)
    local key = PN.Key(oldest.sender)
    from.floor[key] = math.max(from.floor[key] or 0, oldest.counter)
    total, dropped = total - 1, dropped + 1
  end
  return dropped
end

-- Puts a message into the history in the order of its (clamped) time. Returns true, or false and "duplicate",
-- "old" (at or below the floor of its sender, or older than the history keeps) or "invalid".
function TL.Add(h, m, now)
  if type(m) ~= "table" or type(m.sender) ~= "string" or not isInt(m.counter, 1, L.MAX_COUNTER) then
    return false, "invalid"
  end
  if type(m.text) ~= "string" or m.text == "" or not isInt(m.time, 0, MAX_TIME) then
    return false, "invalid"
  end
  local key = PN.Key(m.sender)
  if m.counter <= (h.floor[key] or 0) then
    return false, "old"
  end
  for _, other in ipairs(h.msgs) do
    if other.counter == m.counter and PN.Key(other.sender) == key then
      return false, "duplicate"
    end
  end
  if m.time < now - L.HISTORY_DAYS * SECONDS_PER_DAY then
    return false, "old"
  end
  local entry = { sender = m.sender, counter = m.counter, time = m.time, text = m.text }
  local at = #h.msgs + 1
  while at > 1 and before(entry, h.msgs[at - 1]) do
    at = at - 1
  end
  table.insert(h.msgs, at, entry)
  TL.Prune(h, now)
  for _, other in ipairs(h.msgs) do
    if other == entry then
      return true
    end
  end
  return false, "old"
end

-- Highest counter per member (by key), from the messages and the floor: what this client has of each.
function TL.Vector(h, team)
  local vec = {}
  for name in pairs(team.members) do
    local key = PN.Key(name)
    vec[key] = { name = name, counter = h.floor[key] or 0 }
  end
  for _, m in ipairs(h.msgs) do
    local item = vec[PN.Key(m.sender)]
    if item and m.counter > item.counter then
      item.counter = m.counter
    end
  end
  return vec
end

-- The messages above the counters of `vec` (a list of { name, counter }), oldest first, at most SYNC_MESSAGES
-- and SYNC_CHARS characters on the wire. Returns the list and whether more are missing.
function TL.Missing(h, vec)
  local known = {}
  for _, item in ipairs(vec) do
    known[PN.Key(item.name)] = item.counter
  end
  local out, chars, more = {}, 0, false
  for _, m in ipairs(h.msgs) do
    if m.counter > (known[PN.Key(m.sender)] or 0) then
      local cost = #TL.Esc(m.text) + #TL.Esc(m.sender) + 32
      if #out >= L.SYNC_MESSAGES or chars + cost > L.SYNC_CHARS then
        more = true
        break
      end
      out[#out + 1] = m
      chars = chars + cost
    end
  end
  return out, more
end

----------------------------------------------------------------------------------------------------
-- Invitations and the block list
----------------------------------------------------------------------------------------------------

function TL.NewInbox()
  return { nextId = 1, list = {} }
end

-- Removes invitations older than a day. Returns how many went.
function TL.ExpireInvites(inbox, now)
  local gone = 0
  for i = #inbox.list, 1, -1 do
    if now - inbox.list[i].at >= L.INVITE_TTL then
      table.remove(inbox.list, i)
      gone = gone + 1
    end
  end
  return gone
end

-- Takes an invitation in: inv = { tid, name, icon, count, from }. `rate` is the memory of the arrival times per
-- sender key (not stored), `blocked` the block list. Returns the id of the invitation, or nil and "blocked",
-- "rate" (more than INVITES_PER_HOUR in an hour from one sender) or "full".
function TL.AddInvite(inbox, rate, blocked, inv, now)
  TL.ExpireInvites(inbox, now)
  local key = PN.Key(inv.from)
  if blocked[key] then
    return nil, "blocked"
  end
  local times, kept = rate[key] or {}, {}
  for _, t in ipairs(times) do
    if now - t < 3600 then
      kept[#kept + 1] = t
    end
  end
  if #kept >= L.INVITES_PER_HOUR then
    rate[key] = kept
    return nil, "rate"
  end
  kept[#kept + 1] = now
  rate[key] = kept
  for _, old in ipairs(inbox.list) do
    if old.tid == inv.tid and PN.Key(old.from) == key then
      old.name, old.icon, old.count, old.at = inv.name, inv.icon, inv.count, now
      return old.id
    end
  end
  if #inbox.list >= L.MAX_INVITES then
    return nil, "full"
  end
  local id = inbox.nextId
  inbox.nextId = id + 1
  inbox.list[#inbox.list + 1] =
    { id = id, tid = inv.tid, name = inv.name, icon = inv.icon, count = inv.count, from = inv.from, at = now }
  return id
end

-- Adds a sender to the block list. Returns true, or false and "name" or "full".
function TL.Block(blocked, name)
  local who = type(name) == "string" and PN.Clean(name) or ""
  local key = PN.Key(who)
  if key == "" or #who > 64 then
    return false, "name"
  end
  if blocked[key] == nil then
    local n = 0
    for _ in pairs(blocked) do
      n = n + 1
    end
    if n >= L.MAX_BLOCKED then
      return false, "full"
    end
  end
  blocked[key] = who
  return true
end

----------------------------------------------------------------------------------------------------
-- Wire format
----------------------------------------------------------------------------------------------------

-- Packet types of the function teamChat (the letter is the type of the envelope of the line).
TL.TYPES = {
  INVITE = "I",
  ACCEPT = "A",
  DECLINE = "D",
  ROSTER = "R",
  MSG = "M",
  LEAVE = "L",
  REMOVE = "X",
  UPDATE = "U",
  SYNC = "S",
  ANSWER = "Y",
  FAREWELL = "F",
}
local T = TL.TYPES
TL.FAREWELL_PAYLOAD = "x"

local function split(s, sep)
  local out, from = {}, 1
  while true do
    local at = s:find(sep, from, true)
    if not at then
      out[#out + 1] = s:sub(from)
      return out
    end
    out[#out + 1] = s:sub(from, at - 1)
    from = at + #sep
  end
end

local function number(s, lo, hi)
  if type(s) ~= "string" or #s > 10 or not s:find("^%d+$") then
    return nil
  end
  local n = tonumber(s)
  return isInt(n, lo, hi) and n or nil
end

-- A name field: escaped on the wire, a usable member name behind it.
local function nameField(s)
  local plain = TL.Unesc(s)
  return plain and TL.CleanMember(plain) or nil
end

-- A text field: escaped on the wire, valid UTF-8, cleaned to plain text. nil for a text that ends up empty.
local function textField(s)
  local plain = TL.Unesc(s)
  if not plain or #plain > L.TEXT_BYTES then
    return nil
  end
  local clean = TL.CleanText(plain, L.TEXT_BYTES)
  return clean ~= "" and clean or nil
end

local function tidField(s)
  return TL.ValidId(s) and s or nil
end

-- Encoders. They return the payload (printable ASCII), or nil when a value is out of range.
function TL.EncodeInvite(tid, name, icon, count)
  local clean = TL.CleanName(name)
  if not TL.ValidId(tid) or clean == "" or not TL.CleanIcon(icon) or not isInt(count, 1, L.MAX_MEMBERS) then
    return nil
  end
  return table.concat({ tid, TL.Esc(clean), icon, count }, ":")
end

function TL.EncodeTid(tid)
  return TL.ValidId(tid) and tid or nil
end

function TL.EncodeRoster(team)
  local items = {}
  for _, name in ipairs(TL.Names(team)) do
    local entry = team.members[name]
    items[#items + 1] = table.concat({ TL.Esc(name), entry.role == "admin" and "a" or "m", entry.joined }, ",")
  end
  return table.concat({
    team.id,
    team.epoch,
    team.created,
    TL.Esc(team.by),
    TL.Esc(team.name),
    team.icon,
    table.concat(items, ";"),
  }, ":")
end

function TL.EncodeMessage(tid, counter, time, text)
  if not TL.ValidId(tid) or not isInt(counter, 1, L.MAX_COUNTER) or not isInt(time, 0, MAX_TIME) then
    return nil
  end
  local escaped = TL.Esc(text)
  if #text > L.TEXT_BYTES or #escaped > L.TEXT_ESCAPED then
    return nil
  end
  return table.concat({ tid, counter, time, escaped }, ":")
end

function TL.EncodeRemove(tid, epoch, name)
  if not TL.ValidId(tid) or not isInt(epoch, 1, L.MAX_COUNTER) then
    return nil
  end
  return table.concat({ tid, epoch, TL.Esc(name) }, ":")
end

-- op = { kind = "name", name } | "icon", icon | "role", name, admin | "dissolve"
function TL.EncodeUpdate(tid, epoch, op)
  if not TL.ValidId(tid) or not isInt(epoch, 1, L.MAX_COUNTER) then
    return nil
  end
  local base = tid .. ":" .. epoch .. ":"
  if op.kind == "name" then
    return base .. "N:" .. TL.Esc(op.name)
  elseif op.kind == "icon" and TL.CleanIcon(op.icon) then
    return base .. "I:" .. op.icon
  elseif op.kind == "role" then
    return base .. "R:" .. TL.Esc(op.name) .. ":" .. (op.admin and "a" or "m")
  elseif op.kind == "dissolve" then
    return base .. "D"
  end
end

function TL.EncodeSync(tid, epoch, vec)
  if not TL.ValidId(tid) or not isInt(epoch, 1, L.MAX_COUNTER) then
    return nil
  end
  local items = {}
  for _, item in ipairs(vec) do
    items[#items + 1] = TL.Esc(item.name) .. "," .. item.counter
  end
  return table.concat({ tid, epoch, table.concat(items, ";") }, ":")
end

function TL.EncodeAnswer(tid, more, msgs)
  if not TL.ValidId(tid) then
    return nil
  end
  local items = {}
  for _, m in ipairs(msgs) do
    items[#items + 1] = table.concat({ TL.Esc(m.sender), m.counter, m.time, TL.Esc(m.text) }, ",")
  end
  return table.concat({ tid, more and "1" or "0", table.concat(items, ";") }, ":")
end

-- Decoders: one table or nil for anything that is not exactly the format. The sender is never part of a payload.
local DECODE = {}

DECODE[T.INVITE] = function(p)
  local f = split(p, ":")
  if #f ~= 4 then
    return nil
  end
  local name = TL.Unesc(f[2])
  name = name and TL.CleanName(name) or ""
  local tid, icon, count = tidField(f[1]), number(f[3], 1, L.MAX_ICON), number(f[4], 1, L.MAX_MEMBERS)
  if not tid or name == "" or not icon or not count then
    return nil
  end
  return { tid = tid, name = name, icon = icon, count = count }
end

local function tidOnly(p)
  local tid = tidField(p)
  return tid and { tid = tid } or nil
end
DECODE[T.ACCEPT] = tidOnly
DECODE[T.DECLINE] = tidOnly
DECODE[T.LEAVE] = tidOnly

DECODE[T.ROSTER] = function(p)
  local f = split(p, ":")
  if #f ~= 7 then
    return nil
  end
  local name = TL.Unesc(f[5])
  name = name and TL.CleanName(name) or ""
  local by = nameField(f[4])
  local tid = tidField(f[1])
  local epoch, created = number(f[2], 1, L.MAX_COUNTER), number(f[3], 0, MAX_TIME)
  local icon = number(f[6], 1, L.MAX_ICON)
  if not (tid and epoch and created and by and icon) or name == "" then
    return nil
  end
  local items = split(f[7], ";")
  if #p > L.ROSTER_CHARS or #items < 1 or #items > L.MAX_MEMBERS then
    return nil
  end
  local team = { id = tid, name = name, icon = icon, epoch = epoch, by = by, created = created, members = {} }
  for _, item in ipairs(items) do
    local g = split(item, ",")
    local who = #g == 3 and nameField(g[1])
    local joined = #g == 3 and number(g[3], 0, MAX_TIME)
    if not who or not joined or (g[2] ~= "a" and g[2] ~= "m") or TL.Find(team, who) then
      return nil
    end
    team.members[who] = { role = g[2] == "a" and "admin" or "member", joined = joined }
  end
  if adminCount(team) < 1 then
    return nil
  end
  return { team = team }
end

DECODE[T.MSG] = function(p)
  local f = split(p, ":")
  if #f ~= 4 then
    return nil
  end
  local tid, counter, time = tidField(f[1]), number(f[2], 1, L.MAX_COUNTER), number(f[3], 0, MAX_TIME)
  local text = textField(f[4])
  if not (tid and counter and time and text) then
    return nil
  end
  return { tid = tid, counter = counter, time = time, text = text }
end

DECODE[T.REMOVE] = function(p)
  local f = split(p, ":")
  if #f ~= 3 then
    return nil
  end
  local tid, epoch, name = tidField(f[1]), number(f[2], 1, L.MAX_COUNTER), nameField(f[3])
  if not (tid and epoch and name) then
    return nil
  end
  return { tid = tid, epoch = epoch, name = name }
end

DECODE[T.UPDATE] = function(p)
  local f = split(p, ":")
  local tid, epoch = tidField(f[1]), number(f[2] or "", 1, L.MAX_COUNTER)
  if not (tid and epoch) then
    return nil
  end
  local kind = f[3]
  if kind == "N" and #f == 4 then
    local name = TL.Unesc(f[4])
    name = name and TL.CleanName(name) or ""
    return name ~= "" and { tid = tid, epoch = epoch, op = { kind = "name", name = name } } or nil
  elseif kind == "I" and #f == 4 then
    local icon = number(f[4], 1, L.MAX_ICON)
    return icon and { tid = tid, epoch = epoch, op = { kind = "icon", icon = icon } } or nil
  elseif kind == "R" and #f == 5 and (f[5] == "a" or f[5] == "m") then
    local name = nameField(f[4])
    return name and { tid = tid, epoch = epoch, op = { kind = "role", name = name, admin = f[5] == "a" } } or nil
  elseif kind == "D" and #f == 3 then
    return { tid = tid, epoch = epoch, op = { kind = "dissolve" } }
  end
  return nil
end

DECODE[T.SYNC] = function(p)
  local f = split(p, ":")
  if #f ~= 3 then
    return nil
  end
  local tid, epoch = tidField(f[1]), number(f[2], 1, L.MAX_COUNTER)
  if not (tid and epoch) then
    return nil
  end
  local vec = {}
  if f[3] ~= "" then
    local items = split(f[3], ";")
    if #items > L.MAX_MEMBERS then
      return nil
    end
    for _, item in ipairs(items) do
      local g = split(item, ",")
      local who, counter = #g == 2 and nameField(g[1]), #g == 2 and number(g[2], 0, L.MAX_COUNTER)
      if not who or not counter then
        return nil
      end
      vec[#vec + 1] = { name = who, counter = counter }
    end
  end
  return { tid = tid, epoch = epoch, vector = vec }
end

DECODE[T.ANSWER] = function(p)
  local f = split(p, ":")
  if #f ~= 3 or (f[2] ~= "0" and f[2] ~= "1") then
    return nil
  end
  local tid = tidField(f[1])
  if not tid then
    return nil
  end
  local msgs = {}
  if f[3] ~= "" then
    local items = split(f[3], ";")
    if #items > L.SYNC_MESSAGES then
      return nil
    end
    for _, item in ipairs(items) do
      local g = split(item, ",")
      if #g ~= 4 then
        return nil
      end
      local who, counter, time, text =
        nameField(g[1]), number(g[2], 1, L.MAX_COUNTER), number(g[3], 0, MAX_TIME), textField(g[4])
      if not (who and counter and time and text) then
        return nil
      end
      msgs[#msgs + 1] = { sender = who, counter = counter, time = time, text = text }
    end
  end
  return { tid = tid, more = f[2] == "1", msgs = msgs }
end

DECODE[T.FAREWELL] = function(p)
  return p == TL.FAREWELL_PAYLOAD and {} or nil
end

-- The value of a payload of the given type, or nil for anything else.
function TL.Decode(typ, payload)
  local decode = DECODE[typ]
  if not decode or type(payload) ~= "string" or payload:find("[^ -~]") then
    return nil
  end
  return decode(payload)
end

----------------------------------------------------------------------------------------------------
-- Store
----------------------------------------------------------------------------------------------------

local function cleanTeam(raw, id)
  if type(raw) ~= "table" or not TL.ValidId(id) or raw.id ~= id then
    return nil
  end
  local name, icon = TL.CleanName(raw.name), TL.CleanIcon(raw.icon)
  local by = TL.CleanMember(raw.by)
  if name == "" or not icon or not by or not isInt(raw.epoch, 1, L.MAX_COUNTER) or type(raw.members) ~= "table" then
    return nil
  end
  local team = {
    id = id,
    name = name,
    icon = icon,
    epoch = raw.epoch,
    by = by,
    created = isInt(raw.created, 0, MAX_TIME) and raw.created or 0,
    members = {},
  }
  local names = {}
  for member in pairs(raw.members) do
    if type(member) == "string" then
      names[#names + 1] = member
    end
  end
  table.sort(names)
  for _, member in ipairs(names) do
    local entry = raw.members[member]
    local who = TL.CleanMember(member)
    if who and type(entry) == "table" and TL.Count(team) < L.MAX_MEMBERS and not TL.Find(team, who) then
      team.members[who] = {
        role = entry.role == "admin" and "admin" or "member",
        joined = isInt(entry.joined, 0, MAX_TIME) and entry.joined or 0,
      }
    end
  end
  if next(team.members) == nil then
    return nil
  end
  ensureAdmin(team)
  return team
end

local function cleanHistory(raw, now)
  local h = TL.NewHistory()
  if type(raw) ~= "table" then
    return h
  end
  if type(raw.floor) == "table" then
    local n = 0
    for key, value in pairs(raw.floor) do
      if type(key) == "string" and #key <= 64 and isInt(value, 1, L.MAX_COUNTER) and n < L.MAX_MEMBERS * 4 then
        h.floor[key] = value
        n = n + 1
      end
    end
  end
  if type(raw.msgs) == "table" then
    for i = 1, math.min(#raw.msgs, L.HISTORY_MESSAGES * 2) do
      local m = raw.msgs[i]
      if type(m) == "table" and type(m.sender) == "string" and type(m.text) == "string" then
        local who, text = TL.CleanMember(m.sender), TL.CleanText(m.text, L.TEXT_BYTES)
        if who and text and text ~= "" then
          TL.Add(h, { sender = who, counter = m.counter, time = m.time, text = text }, now or m.time or 0)
        end
      end
    end
  end
  return h
end

local function cleanInbox(raw)
  local inbox = TL.NewInbox()
  if type(raw) ~= "table" then
    return inbox
  end
  if isInt(raw.nextId, 1, 2 ^ 31) then
    inbox.nextId = raw.nextId
  end
  for _, item in ipairs(type(raw.list) == "table" and raw.list or {}) do
    if #inbox.list >= L.MAX_INVITES then
      break
    end
    local from = type(item) == "table" and TL.CleanMember(item.from)
    local name = type(item) == "table" and TL.CleanName(item.name)
    if
      from
      and name ~= ""
      and TL.ValidId(item.tid)
      and TL.CleanIcon(item.icon)
      and isInt(item.id, 1, 2 ^ 31)
      and isInt(item.count, 1, L.MAX_MEMBERS)
      and isInt(item.at, 0, MAX_TIME)
    then
      inbox.list[#inbox.list + 1] = {
        id = item.id,
        tid = item.tid,
        name = name,
        icon = item.icon,
        count = item.count,
        from = from,
        at = item.at,
        accepted = item.accepted == true or nil,
      }
      inbox.nextId = math.max(inbox.nextId, item.id + 1)
    end
  end
  return inbox
end

-- The state of one character: teams, history per team, own counters per team, invitations and the block list.
function TL.NewCharacter()
  return { teams = {}, history = {}, counters = {}, invites = TL.NewInbox(), blocked = {} }
end

local function cleanCharacter(raw, now)
  local out = TL.NewCharacter()
  if type(raw) ~= "table" then
    return out
  end
  local ids = {}
  for id in pairs(type(raw.teams) == "table" and raw.teams or {}) do
    if type(id) == "string" then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  local count = 0
  for _, id in ipairs(ids) do
    local team = count < L.MAX_TEAMS and cleanTeam(raw.teams[id], id)
    if team then
      count = count + 1
      out.teams[id] = team
      out.history[id] = cleanHistory(type(raw.history) == "table" and raw.history[id], now)
      local counter = type(raw.counters) == "table" and raw.counters[id]
      out.counters[id] = isInt(counter, 0, L.MAX_COUNTER) and counter or 0
    end
  end
  out.invites = cleanInbox(raw.invites)
  if type(raw.blocked) == "table" then
    local keys = {}
    for key, name in pairs(raw.blocked) do
      if type(key) == "string" and type(name) == "string" and #name <= 64 then
        keys[#keys + 1] = key
      end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
      if TL.Block(out.blocked, raw.blocked[key]) == false then
        break
      end
    end
  end
  return out
end

-- The whole teams store: { v = 1, chars = { [character key] = state } }, every list capped, every value checked.
-- Never changes raw.
function TL.CleanStore(raw, now)
  local out = { v = 1, chars = {} }
  if type(raw) ~= "table" or type(raw.chars) ~= "table" then
    return out
  end
  local keys = {}
  for key in pairs(raw.chars) do
    if type(key) == "string" and key ~= "" and #key <= 96 then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  for i = 1, math.min(#keys, L.MAX_CHARACTERS) do
    out.chars[keys[i]] = cleanCharacter(raw.chars[keys[i]], now)
    TL.PruneTotal(out.chars[keys[i]].history)
  end
  return out
end
