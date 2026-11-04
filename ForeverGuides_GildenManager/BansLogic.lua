-- The ban list, former members and alt groups, no game calls. All of it is local: guild.bans[key] =
-- { name, reason, note, day } with the roster key of the member. A warning is a hint, nothing here
-- invites, removes or changes anyone.
local _, gm = ...
if not gm.ext then
  return
end
local PN, U = gm.FG.PlayerName, gm.FG.U

local BL = {}
gm.BansLogic = BL

BL.MAX_REASON = 60
BL.MAX_NOTE = 120
BL.MAX_BANS = 1000
BL.MAX_NAME = 48

local function whole(v)
  return type(v) == "number" and v == v and v >= 0 and v < math.huge and v == math.floor(v) and v or nil
end

-- One line, no control characters or pipes (colour codes), cut at limit characters.
local function line(v, limit)
  if type(v) ~= "string" then
    return ""
  end
  v = v:gsub("[%z\1-\31\127|]", " "):gsub("%s+", " ")
  return PN.Cut(U.trim(v), limit)
end
BL.Line = line

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

local function byName(a, b)
  local x, y = PN.Lower(a.name), PN.Lower(b.name)
  if x ~= y then
    return x < y
  end
  return a.key < b.key
end

-- One entry repaired, nil when it cannot be one.
local function cleanEntry(key, e)
  if type(key) ~= "string" or key == "" or type(e) ~= "table" then
    return nil
  end
  local name = PN.Normalize(line(e.name, BL.MAX_NAME))
  if name == "" then
    name = line(key, BL.MAX_NAME)
  end
  return {
    name = name,
    reason = line(e.reason, BL.MAX_REASON),
    note = line(e.note, BL.MAX_NOTE),
    day = whole(e.day) or 0,
  }
end

-- Repairs guild.bans in place: a damaged entry goes, at most MAX_BANS stay (the oldest ones go first).
function BL.Clean(guild)
  local clean, keys = {}, {}
  if type(guild.bans) == "table" then
    for key, e in pairs(guild.bans) do
      local entry = cleanEntry(key, e)
      if entry then
        clean[key] = entry
        keys[#keys + 1] = key
      end
    end
  end
  if #keys > BL.MAX_BANS then
    table.sort(keys, function(a, b)
      if clean[a].day ~= clean[b].day then
        return clean[a].day > clean[b].day
      end
      return a < b
    end)
    for i = BL.MAX_BANS + 1, #keys do
      clean[keys[i]] = nil
    end
  end
  guild.bans = clean
end

-- Adds or replaces the ban of a member. fields: { name, reason, note }. Answers true and the entry, or
-- false and a reason: "name" (empty), "limit" (too many bans).
function BL.Set(bans, fields, today)
  local name = PN.Normalize(line(type(fields) == "table" and fields.name or "", BL.MAX_NAME))
  local key = PN.Key(name)
  if key == "" then
    return false, "name"
  end
  local old = bans[key]
  if not old then
    local n = 0
    for _ in pairs(bans) do
      n = n + 1
    end
    if n >= BL.MAX_BANS then
      return false, "limit"
    end
  end
  local entry = {
    name = name,
    reason = line(fields.reason, BL.MAX_REASON),
    note = line(fields.note, BL.MAX_NOTE),
    day = old and old.day or whole(today) or 0,
  }
  bans[key] = entry
  return true, entry, key
end

function BL.Remove(bans, key)
  local had = bans[key] ~= nil
  bans[key] = nil
  return had
end

-- Entries sorted by name, as { key, name, reason, note, day }. needle: part of name, reason or note.
function BL.List(bans, needle)
  needle = PN.Lower(U.trim(type(needle) == "string" and needle or ""))
  local out = {}
  for key, e in pairs(bans) do
    local hit = needle == ""
    for _, field in ipairs({ e.name, e.reason, e.note }) do
      hit = hit or PN.Lower(field):find(needle, 1, true) ~= nil
    end
    if hit then
      out[#out + 1] = { key = key, name = e.name, reason = e.reason, note = e.note, day = e.day }
    end
  end
  table.sort(out, byName)
  return out
end

-- The ban that applies to a member: its own, else the one of its main. Answers entry, key, via
-- ("self" or "main"), or nil.
function BL.Match(guild, key)
  local own = guild.bans[key]
  if own then
    return own, key, "self"
  end
  local member = guild.members[key]
  local mainKey = member and member.mainKey or ""
  if mainKey ~= "" and guild.bans[mainKey] then
    return guild.bans[mainKey], mainKey, "main"
  end
end

-- Former members --------------------------------------------------------------------------------------

local GONE = { leave = "leave", remove = "remove" }

-- Members who left or were removed and are not back: { key, name, day, how ("leave" or "remove"), by,
-- rank, banned }. Built from the events, completed by the "left" mark of a member entry. The rank is the
-- last one the log knows. current: set of roster keys to leave out. Newest first.
function BL.Former(guild, needle, current)
  current = current or {}
  local last, rank = {}, {}
  for _, e in ipairs(guild.events) do
    if e.kind == "join" or GONE[e.kind] then
      last[e.key] = e
    elseif (e.kind == "promote" or e.kind == "demote") and e.to and e.to ~= "" then
      rank[e.key] = e.to
    end
    if GONE[e.kind] and e.from and e.from ~= "" then
      rank[e.key] = e.from
    end
  end
  local found = {}
  for key, e in pairs(last) do
    if GONE[e.kind] and not current[key] then
      found[key] = { key = key, name = e.name ~= "" and e.name or key, day = e.day, how = e.kind, by = e.by }
    end
  end
  for key, m in pairs(guild.members) do
    if m.left and not found[key] and not current[key] and not (last[key] and last[key].kind == "join") then
      found[key] =
        { key = key, name = m.name, day = m.left.day, how = m.left.reason == "removed" and "remove" or "leave" }
    end
  end
  needle = PN.Lower(U.trim(type(needle) == "string" and needle or ""))
  local out = {}
  for _, key in ipairs(sortedKeys(found)) do
    local f = found[key]
    f.rank = rank[key]
    f.banned = guild.bans[key] ~= nil
    if needle == "" or PN.Lower(f.name):find(needle, 1, true) or PN.Lower(f.rank or ""):find(needle, 1, true) then
      out[#out + 1] = f
    end
  end
  table.sort(out, function(a, b)
    if a.day ~= b.day then
      return a.day > b.day
    end
    return byName(a, b)
  end)
  return out
end

-- Alt groups ------------------------------------------------------------------------------------------

-- Main and alt links as groups: { key, name, alts = { names }, banned }, sorted by the name of the main.
-- A group is banned when its main or one of its alts is on the ban list.
function BL.AltGroups(guild, needle)
  local groups = {}
  for key, m in pairs(guild.members) do
    if m.mainKey ~= "" and m.mainKey ~= key then
      local g = groups[m.mainKey]
      if not g then
        local main = guild.members[m.mainKey]
        g = { key = m.mainKey, name = main and main.name or m.main, alts = {}, banned = guild.bans[m.mainKey] ~= nil }
        groups[m.mainKey] = g
      end
      g.alts[#g.alts + 1] = m.name
      g.banned = g.banned or guild.bans[key] ~= nil
    end
  end
  needle = PN.Lower(U.trim(type(needle) == "string" and needle or ""))
  local out = {}
  for _, g in pairs(groups) do
    table.sort(g.alts, function(a, b)
      return PN.Lower(a) < PN.Lower(b)
    end)
    if needle == "" or PN.Lower(g.name .. " " .. table.concat(g.alts, " ")):find(needle, 1, true) then
      out[#out + 1] = g
    end
  end
  table.sort(out, byName)
  return out
end

-- Warnings -------------------------------------------------------------------------------------------

-- People on the ban list (or alts of a banned main) who are in the roster or joined recently. rows: roster
-- members { key, name }; today: day number; shown: set of keys that were already reported, filled here.
-- Answers a list of { key, name, ban, via, where ("roster" or "join") }.
function BL.Warnings(guild, rows, today, shown)
  shown = shown or {}
  local out = {}
  local function add(key, name, where)
    if shown[key] then
      return
    end
    local ban, _, via = BL.Match(guild, key)
    if ban then
      shown[key] = true
      out[#out + 1] = { key = key, name = name, ban = ban, via = via, where = where }
    end
  end
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    add(row.key, row.name, "roster")
  end
  for _, e in ipairs(guild.events) do
    if e.kind == "join" and type(today) == "number" and e.day >= today - 1 then
      add(e.key, e.name ~= "" and e.name or e.key, "join")
    end
  end
  table.sort(out, byName)
  return out
end
