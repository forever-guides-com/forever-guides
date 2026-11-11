-- The data of the statistics: what is stored, how it is kept small, how an older or damaged saved table becomes a
-- valid one. Pure, no game calls and no clock: times, the UTC offset and names come from outside.
--
-- Shape of ForeverGuidesStatsDB (schema version S.VERSION):
--   v        schema version, a table of a newer version is never touched
--   names    [id] = text, one dictionary for monster and zone names
--   chars    [characterKey] = { name, realm, class, since, last, kills, uses, sess, pvp }
-- kills and uses hold
--   tot      [nameId or itemId] = totals ("Gesamt"); kills: { n, xp, last, z = { [zoneId] = n }, ty, cl, lv = { min, max } },
--            uses: { n, g, last, cat } where g is the part counted without proof
--   day      [dayIndex] = { [id] = n }, only the last keepDays days (the local calendar day)
--   skip     counters of what could not be read
-- sess is { at, kills = { [nameId] = n }, uses = { [itemId] = n } }, pvp a count of players defeated (never a name).
-- Every table has an upper limit (S.LIMITS), the oldest entries leave first and the entry just booked never.
local _, ns = ...

local S = {}
ns.StatsStore = S

S.VERSION = 1

S.LIMITS = {
  killItems = 500,
  useItems = 250,
  zonesPerMob = 8,
  dayEntries = 2500,
  chars = 12,
  names = 1500,
  nameLength = 64,
  keyLength = 96,
  count = 1000000000,
}

S.DEFAULT_KEEP_DAYS = 30
S.KEEP_DAYS = { 7, 30, 90 }
S.SESSION_GAP = 600
S.BYTES_PER_COUNTER = 14
S.BUDGET_BYTES = 1048576
S.DOMAINS = { "kills", "uses" }

-- Steps from one schema version to the next: STEPS[v](db) turns a table of version v into v + 1.
-- None yet, the first schema is version 1. The tests give their own steps to prove the mechanism.
S.STEPS = {}

local MAX_TIME = 4e9
local MAX_DAY = 1e6
local MAX_ID = 4e9

local function number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function whole(value, min, max)
  if not number(value) then
    return nil
  end
  value = math.floor(value)
  if value < min or value > max then
    return nil
  end
  return value
end

local function key(value, max)
  return whole(value, 1, max) == value and value or nil
end

local function text(value, limit)
  if type(value) ~= "string" or value == "" then
    return nil
  end
  limit = limit or S.LIMITS.nameLength
  if #value > limit then
    value = value:sub(1, limit)
  end
  return value
end

local function count(tbl)
  local n = 0
  for _ in pairs(tbl) do
    n = n + 1
  end
  return n
end

local function add(a, b)
  return math.min(S.LIMITS.count, a + b)
end

-- Removes the entries with the oldest "last" until at most `limit` remain. `keep` is never removed.
local function trim(tbl, limit, keep)
  local n = count(tbl)
  if n <= limit then
    return
  end
  local order = {}
  for id, entry in pairs(tbl) do
    if id ~= keep then
      order[#order + 1] = { id = id, last = entry.last or 0, n = entry.n or 0, text = tostring(id) }
    end
  end
  table.sort(order, function(a, b)
    if a.last ~= b.last then
      return a.last < b.last
    end
    if a.n ~= b.n then
      return a.n < b.n
    end
    return a.text < b.text
  end)
  for i = 1, n - limit do
    tbl[order[i].id] = nil
  end
end

-- Zone counts of one monster: the smallest leave first, `keep` never.
local function trimZones(zones, limit, keep)
  local n = count(zones)
  if n <= limit then
    return
  end
  local order = {}
  for id, qty in pairs(zones) do
    if id ~= keep then
      order[#order + 1] = { id = id, n = qty }
    end
  end
  table.sort(order, function(a, b)
    if a.n ~= b.n then
      return a.n < b.n
    end
    return a.id > b.id
  end)
  for i = 1, n - limit do
    zones[order[i].id] = nil
  end
end

-- Days: the oldest day leaves first until at most `limit` entries remain over all days, `keepDay` never.
local function trimDays(days, limit, keepDay)
  local total = 0
  for _, map in pairs(days) do
    total = total + count(map)
  end
  if total <= limit then
    return
  end
  local order = {}
  for day in pairs(days) do
    if day ~= keepDay then
      order[#order + 1] = day
    end
  end
  table.sort(order)
  for _, day in ipairs(order) do
    if total <= limit then
      return
    end
    total = total - count(days[day])
    days[day] = nil
  end
end

-- Days and dates --------------------------------------------------------------------------------------------------

-- The local calendar day of a server time, the offset (seconds east of UTC) is injected.
function S.Day(time, offset)
  return math.floor(((whole(time, 0, MAX_TIME) or 0) + (number(offset) and offset or 0)) / 86400)
end

-- "YYYY-MM-DD" of a day index (proleptic Gregorian calendar).
function S.DayDate(day)
  local z = (whole(day, 0, MAX_DAY) or 0) + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400 + (m <= 2 and 1 or 0)
  return string.format("%04d-%02d-%02d", y, m, d)
end

-- A retention in days: one of S.KEEP_DAYS, else the default.
function S.KeepDays(value)
  for _, days in ipairs(S.KEEP_DAYS) do
    if value == days then
      return days
    end
  end
  return S.DEFAULT_KEEP_DAYS
end

-- Schema ---------------------------------------------------------------------------------------------------------------

local function newDomain(skip)
  return { tot = {}, day = {}, skip = skip }
end

function S.NewChar()
  return {
    since = 0,
    last = 0,
    kills = newDomain({ secret = 0 }),
    uses = newDomain({ window = 0, secret = 0 }),
    sess = { at = 0, kills = {}, uses = {} },
    pvp = 0,
  }
end

function S.New()
  return { v = S.VERSION, names = {}, chars = {} }
end

-- A table of this version can be written, one of a newer version never.
function S.Writable(db)
  return type(db) == "table" and db.v == S.VERSION and type(db.names) == "table" and type(db.chars) == "table"
end

-- Names ------------------------------------------------------------------------------------------------------------------

-- Reverse lookup per table, not saved. Rebuilt when it does not match the dictionary.
local index = setmetatable({}, { __mode = "k" })

local function buildIndex(db)
  local map = {}
  for id, name in pairs(db.names) do
    if map[name] == nil or id < map[name] then
      map[name] = id
    end
  end
  index[db] = map
  return map
end

-- Which dictionary ids a character refers to, and how recent (the newest "last" of an entry that uses the name).
local function references(db)
  local score = {}
  local function touch(id, last)
    if db.names[id] and (score[id] or -1) < last then
      score[id] = last
    end
  end
  for _, char in pairs(db.chars) do
    for id, entry in pairs(char.kills.tot) do
      touch(id, entry.last or 0)
      for zone in pairs(entry.z or {}) do
        touch(zone, entry.last or 0)
      end
    end
    for _, map in pairs(char.kills.day) do
      for id in pairs(map) do
        touch(id, 0)
      end
    end
    for id in pairs(char.sess.kills) do
      touch(id, 0)
    end
  end
  return score
end

local function dropIds(db, gone)
  for _, char in pairs(db.chars) do
    for id, entry in pairs(char.kills.tot) do
      if gone[id] then
        char.kills.tot[id] = nil
      elseif entry.z then
        for zone in pairs(entry.z) do
          if gone[zone] then
            entry.z[zone] = nil
          end
        end
      end
    end
    for day, map in pairs(char.kills.day) do
      for id in pairs(map) do
        if gone[id] then
          map[id] = nil
        end
      end
      if next(map) == nil then
        char.kills.day[day] = nil
      end
    end
    for id in pairs(char.sess.kills) do
      if gone[id] then
        char.sess.kills[id] = nil
      end
    end
  end
  for id in pairs(gone) do
    db.names[id] = nil
  end
  index[db] = nil
end

-- Removes the names nothing refers to, then the least recent ones while more than LIMITS.names - room remain.
-- `protect` is a set of ids that stay. Ids are never renumbered, so an id taken before stays valid.
function S.Compact(db, protect, room)
  protect = protect or {}
  local score = references(db)
  local gone = {}
  for id in pairs(db.names) do
    if score[id] == nil and not protect[id] then
      gone[id] = true
    end
  end
  local kept = {}
  for id in pairs(db.names) do
    if not gone[id] and not protect[id] then
      kept[#kept + 1] = id
    end
  end
  local limit = S.LIMITS.names - (room or 0)
  local inUse = count(db.names) - count(gone)
  if inUse > limit then
    table.sort(kept, function(a, b)
      if score[a] ~= score[b] then
        return score[a] < score[b]
      end
      return a > b
    end)
    for i = 1, math.min(#kept, inUse - limit) do
      gone[kept[i]] = true
    end
  end
  if next(gone) then
    dropIds(db, gone)
  end
end

-- The dictionary id of a name, created when new. nil for a name that is not usable.
function S.NameId(db, value, protect)
  local name = text(value)
  if not (name and S.Writable(db)) then
    return nil
  end
  local map = index[db]
  local id = map and map[name]
  if id and db.names[id] == name then
    return id
  end
  map = buildIndex(db)
  if map[name] then
    return map[name]
  end
  if count(db.names) >= S.LIMITS.names then
    S.Compact(db, protect, 1)
    map = buildIndex(db)
  end
  id = 1
  while db.names[id] do
    id = id + 1
  end
  db.names[id] = name
  map[name] = id
  return id
end

-- Clean -----------------------------------------------------------------------------------------------------------------

local function cleanCounts(raw, valid)
  local out = {}
  if type(raw) == "table" then
    for id, qty in pairs(raw) do
      local n = whole(qty, 1, S.LIMITS.count)
      if n and valid(id) then
        out[id] = n
      end
    end
  end
  return out
end

local function cleanDays(raw, valid, limit)
  local out = {}
  if type(raw) == "table" then
    for day, map in pairs(raw) do
      if whole(day, 0, MAX_DAY) == day then
        local clean = cleanCounts(map, valid)
        if next(clean) then
          out[day] = clean
        end
      end
    end
  end
  trimDays(out, limit)
  return out
end

local function cleanKillTot(raw, names)
  local out = {}
  if type(raw) ~= "table" then
    return out
  end
  for id, entry in pairs(raw) do
    local n = type(entry) == "table" and names[id] and key(id, MAX_DAY) and whole(entry.n, 1, S.LIMITS.count)
    if n then
      local item = {
        n = n,
        xp = whole(entry.xp, 0, S.LIMITS.count) or 0,
        last = whole(entry.last, 0, MAX_TIME) or 0,
        z = cleanCounts(entry.z, function(zone)
          return names[zone] ~= nil and key(zone, MAX_DAY) ~= nil
        end),
        ty = whole(entry.ty, 0, 255),
        cl = whole(entry.cl, 0, 255),
      }
      trimZones(item.z, S.LIMITS.zonesPerMob)
      local lv = type(entry.lv) == "table" and entry.lv
      local lo, hi = lv and whole(lv[1], 1, 255), lv and whole(lv[2], 1, 255)
      if lo and hi and lo <= hi then
        item.lv = { lo, hi }
      end
      out[id] = item
    end
  end
  trim(out, S.LIMITS.killItems)
  return out
end

local function cleanUseTot(raw)
  local out = {}
  if type(raw) ~= "table" then
    return out
  end
  for id, entry in pairs(raw) do
    local n = type(entry) == "table" and key(id, MAX_ID) and whole(entry.n, 1, S.LIMITS.count)
    if n then
      out[id] = {
        n = n,
        g = math.min(n, whole(entry.g, 0, S.LIMITS.count) or 0),
        last = whole(entry.last, 0, MAX_TIME) or 0,
        cat = whole(entry.cat, 1, 99),
      }
    end
  end
  trim(out, S.LIMITS.useItems)
  return out
end

local function cleanSkip(raw, fields)
  local out = {}
  for _, field in ipairs(fields) do
    out[field] = type(raw) == "table" and whole(raw[field], 0, S.LIMITS.count) or 0
  end
  return out
end

local function cleanChar(raw, names)
  local out = S.NewChar()
  if type(raw) ~= "table" then
    return out
  end
  out.name, out.realm, out.class = text(raw.name), text(raw.realm), text(raw.class, 32)
  out.since = whole(raw.since, 0, MAX_TIME) or 0
  out.last = whole(raw.last, 0, MAX_TIME) or 0
  out.pvp = whole(raw.pvp, 0, S.LIMITS.count) or 0
  local function validName(id)
    return names[id] ~= nil and key(id, MAX_DAY) ~= nil
  end
  local function validItem(id)
    return key(id, MAX_ID) ~= nil
  end
  local kills, uses = type(raw.kills) == "table" and raw.kills or {}, type(raw.uses) == "table" and raw.uses or {}
  out.kills.tot = cleanKillTot(kills.tot, names)
  out.kills.day = cleanDays(kills.day, validName, S.LIMITS.dayEntries)
  out.kills.skip = cleanSkip(kills.skip, { "secret" })
  out.uses.tot = cleanUseTot(uses.tot)
  out.uses.day = cleanDays(uses.day, validItem, S.LIMITS.dayEntries)
  out.uses.skip = cleanSkip(uses.skip, { "window", "secret" })
  local sess = type(raw.sess) == "table" and raw.sess or {}
  out.sess = {
    at = whole(sess.at, 0, MAX_TIME) or 0,
    kills = cleanCounts(sess.kills, validName),
    uses = cleanCounts(sess.uses, validItem),
  }
  return out
end

-- A valid table from whatever was stored: every number checked, every table rebuilt, the limits applied.
function S.Clean(raw)
  local out = S.New()
  if type(raw) ~= "table" then
    return out
  end
  if type(raw.names) == "table" then
    for id, name in pairs(raw.names) do
      if key(id, MAX_DAY) and text(name) then
        out.names[id] = text(name)
      end
    end
  end
  if type(raw.chars) == "table" then
    for charKey, entry in pairs(raw.chars) do
      if type(charKey) == "string" and charKey ~= "" and #charKey <= S.LIMITS.keyLength then
        out.chars[charKey] = cleanChar(entry, out.names)
      end
    end
    trim(out.chars, S.LIMITS.chars)
  end
  S.Compact(out)
  return out
end

-- Migration -------------------------------------------------------------------------------------------------------------

-- A valid table from whatever is stored. Returns the table and a status:
--   "fresh"     nothing usable was stored, a new table
--   "ok"        the stored table had the current version (cleaned, limits applied)
--   "migrated"  the stored table was older and went through the steps
--   "newer"     the stored table is from a later version of the add-on: returned untouched, nothing may write it
function S.Migrate(raw, steps)
  steps = steps or S.STEPS
  if type(raw) ~= "table" or not number(raw.v) then
    return S.New(), "fresh"
  end
  local version = math.floor(raw.v)
  if version > S.VERSION then
    return raw, "newer"
  end
  if version < 1 then
    return S.New(), "fresh"
  end
  local migrated = false
  while version < S.VERSION do
    local step = steps[version]
    if type(step) ~= "function" then
      return S.New(), "fresh"
    end
    local ok, result = pcall(step, raw)
    if not ok or type(result) ~= "table" then
      return S.New(), "fresh"
    end
    raw, version, migrated = result, version + 1, true
    raw.v = version
  end
  return S.Clean(raw), migrated and "migrated" or "ok"
end

-- Rotation and limits ----------------------------------------------------------------------------------------------

local function rotateChar(char, today, keepDays)
  local oldest = today - S.KeepDays(keepDays) + 1
  local removed = 0
  for _, domain in ipairs(S.DOMAINS) do
    for day in pairs(char[domain].day) do
      if day < oldest then
        char[domain].day[day] = nil
        removed = removed + 1
      end
    end
  end
  return removed
end

-- Drops the day entries older than keepDays for every character. Returns how many days left.
function S.Rotate(db, ctx)
  if not S.Writable(db) then
    return 0
  end
  local today = S.Day(ctx.time, ctx.offset)
  local removed = 0
  for _, char in pairs(db.chars) do
    removed = removed + rotateChar(char, today, ctx.keepDays)
  end
  if removed > 0 then
    S.Compact(db)
  end
  return removed
end

-- Applies every upper limit to a table that was changed from outside, and removes unused names.
function S.Enforce(db)
  if not S.Writable(db) then
    return
  end
  trim(db.chars, S.LIMITS.chars)
  for _, char in pairs(db.chars) do
    trim(char.kills.tot, S.LIMITS.killItems)
    trim(char.uses.tot, S.LIMITS.useItems)
    for _, entry in pairs(char.kills.tot) do
      trimZones(entry.z, S.LIMITS.zonesPerMob)
    end
    trimDays(char.kills.day, S.LIMITS.dayEntries)
    trimDays(char.uses.day, S.LIMITS.dayEntries)
  end
  S.Compact(db)
end

-- Booking ---------------------------------------------------------------------------------------------------------------

-- The character entry, created on first use. info: name, realm, class, time. Old characters leave when too many.
function S.Char(db, charKey, info)
  if not (S.Writable(db) and type(charKey) == "string" and charKey ~= "" and #charKey <= S.LIMITS.keyLength) then
    return nil
  end
  local char = db.chars[charKey]
  local time = info and whole(info.time, 0, MAX_TIME) or nil
  if not char then
    char = S.NewChar()
    char.since = time or 0
    db.chars[charKey] = char
    local before = count(db.chars)
    trim(db.chars, S.LIMITS.chars, charKey)
    if count(db.chars) < before then
      S.Compact(db)
    end
  end
  if info then
    char.name = text(info.name) or char.name
    char.realm = text(info.realm) or char.realm
    char.class = text(info.class, 32) or char.class
  end
  char.last = math.max(char.last, time or 0)
  return char
end

-- Starts a session when the last one is older than the gap (default 10 minutes), else continues it.
-- Returns true for a new session.
function S.Session(db, charKey, time, gap)
  local char = S.Writable(db) and db.chars[charKey]
  time = whole(time, 0, MAX_TIME)
  if not (char and time) then
    return false
  end
  local fresh = char.sess.at == 0 or time - char.sess.at > (gap or S.SESSION_GAP) or time < char.sess.at
  if fresh then
    char.sess = { at = time, kills = {}, uses = {} }
  else
    char.sess.at = time
  end
  return fresh
end

-- Common start of a booking: the writable character, the time, the day, the rotation on the first booking of a day.
local function begin(db, charKey, ctx)
  local char = S.Writable(db) and type(ctx) == "table" and db.chars[charKey]
  if not char then
    return nil
  end
  local time = whole(ctx.time, 0, MAX_TIME) or 0
  local day = S.Day(time, ctx.offset)
  if char.kills.day[day] == nil and char.uses.day[day] == nil then
    rotateChar(char, day, ctx.keepDays)
  end
  char.last = math.max(char.last, time)
  if char.since == 0 then
    char.since = time
  end
  char.sess.at = math.max(char.sess.at, time)
  return char, time, day
end

local function dayMap(domain, day)
  local map = domain.day[day]
  if not map then
    map = {}
    domain.day[day] = map
  end
  return map
end

-- Books kills of one monster. ev: name, zone, qty (default 1), xp, ty, cl, lv. ctx: time, offset, keepDays.
function S.Kill(db, charKey, ctx, ev)
  local char, time, day = begin(db, charKey, ctx)
  local qty = type(ev) == "table" and whole(ev.qty or 1, 1, S.LIMITS.count)
  local mob = char and qty and S.NameId(db, ev.name)
  if not (char and mob) then
    return false
  end
  local zone = ev.zone and S.NameId(db, ev.zone, { [mob] = true })
  local tot = char.kills.tot
  local entry = tot[mob]
  local created = entry == nil
  if created then
    entry = { n = 0, xp = 0, last = time, z = {} }
    tot[mob] = entry
  end
  entry.n = add(entry.n, qty)
  entry.xp = add(entry.xp, whole(ev.xp, 0, S.LIMITS.count) or 0)
  entry.last = math.max(entry.last, time)
  if zone then
    entry.z[zone] = add(entry.z[zone] or 0, qty)
    trimZones(entry.z, S.LIMITS.zonesPerMob, zone)
  end
  entry.ty = whole(ev.ty, 1, 255) or entry.ty
  entry.cl = whole(ev.cl, 0, 255) or entry.cl
  local level = whole(ev.lv, 1, 255)
  if level then
    local lv = entry.lv or { level, level }
    entry.lv = { math.min(lv[1], level), math.max(lv[2], level) }
  end
  local map = dayMap(char.kills, day)
  local newDay = map[mob] == nil
  map[mob] = add(map[mob] or 0, qty)
  char.sess.kills[mob] = add(char.sess.kills[mob] or 0, qty)
  if created then
    trim(tot, S.LIMITS.killItems, mob)
  end
  if newDay then
    trimDays(char.kills.day, S.LIMITS.dayEntries, day)
  end
  return true
end

-- Books used items. ev: item, qty (default 1), cat, assumed (true counts into g, the part without proof).
function S.Use(db, charKey, ctx, ev)
  local char, time, day = begin(db, charKey, ctx)
  local qty = type(ev) == "table" and whole(ev.qty or 1, 1, S.LIMITS.count)
  local id = qty and key(ev.item, MAX_ID)
  if not (char and id) then
    return false
  end
  local tot = char.uses.tot
  local entry = tot[id]
  local created = entry == nil
  if created then
    entry = { n = 0, g = 0, last = time }
    tot[id] = entry
  end
  entry.n = add(entry.n, qty)
  if ev.assumed then
    entry.g = add(entry.g, qty)
  end
  entry.last = math.max(entry.last, time)
  entry.cat = whole(ev.cat, 1, 99) or entry.cat
  local map = dayMap(char.uses, day)
  local newDay = map[id] == nil
  map[id] = add(map[id] or 0, qty)
  char.sess.uses[id] = add(char.sess.uses[id] or 0, qty)
  if created then
    trim(tot, S.LIMITS.useItems, id)
  end
  if newDay then
    trimDays(char.uses.day, S.LIMITS.dayEntries, day)
  end
  return true
end

-- Counts something that could not be read: domain "kills" (secret) or "uses" (window, secret).
function S.Skip(db, charKey, domain, reason, n)
  local char = S.Writable(db) and db.chars[charKey]
  local skip = char and (domain == "kills" or domain == "uses") and char[domain].skip
  if not (skip and skip[reason]) then
    return false
  end
  skip[reason] = add(skip[reason], whole(n or 1, 1, S.LIMITS.count) or 1)
  return true
end

-- One player defeated, a count only.
function S.Pvp(db, charKey)
  local char = S.Writable(db) and db.chars[charKey]
  if not char then
    return false
  end
  char.pvp = add(char.pvp, 1)
  return true
end

-- Budget -------------------------------------------------------------------------------------------------------------------

local function killCost(entry)
  return 6 + count(entry.z or {})
end

local USE_COST = 4

-- An estimate from the entry counts, no serialization: S.BYTES_PER_COUNTER bytes per stored number, a name counts 3.
function S.Budget(db)
  local counters, chars = 3 * count(db.names), 0
  for _, char in pairs(db.chars) do
    chars = chars + 1
    counters = counters + 8
    for _, entry in pairs(char.kills.tot) do
      counters = counters + killCost(entry)
    end
    counters = counters + USE_COST * count(char.uses.tot)
    for _, domain in ipairs(S.DOMAINS) do
      for _, map in pairs(char[domain].day) do
        counters = counters + 1 + count(map)
      end
      counters = counters + count(char.sess[domain])
    end
  end
  local bytes = counters * S.BYTES_PER_COUNTER
  return { counters = counters, bytes = bytes, limit = S.BUDGET_BYTES, chars = chars, over = bytes > S.BUDGET_BYTES }
end

-- Brings the table under the budget: the oldest days first, then the least counted totals. Returns the entries removed.
function S.FitBudget(db)
  if not S.Writable(db) then
    return 0
  end
  local removed = 0
  while S.Budget(db).over do
    local oldest
    for _, char in pairs(db.chars) do
      for _, domain in ipairs(S.DOMAINS) do
        for day in pairs(char[domain].day) do
          if not oldest or day < oldest then
            oldest = day
          end
        end
      end
    end
    if oldest then
      for _, char in pairs(db.chars) do
        for _, domain in ipairs(S.DOMAINS) do
          if char[domain].day[oldest] then
            char[domain].day[oldest] = nil
            removed = removed + 1
          end
        end
      end
    else
      local pick
      for _, char in pairs(db.chars) do
        for _, domain in ipairs(S.DOMAINS) do
          for id, entry in pairs(char[domain].tot) do
            if not pick or entry.n < pick.entry.n or (entry.n == pick.entry.n and entry.last < pick.entry.last) then
              pick = { tbl = char[domain].tot, id = id, entry = entry }
            end
          end
        end
      end
      if not pick then
        break
      end
      pick.tbl[pick.id] = nil
      removed = removed + 1
    end
  end
  S.Compact(db)
  return removed
end

-- Reset ----------------------------------------------------------------------------------------------------------------------

-- What a reset would remove, for the confirmation: { entries, chars, since, last }. domain nil counts both,
-- charKey nil counts every character.
function S.Summary(db, domain, charKey)
  local out = { entries = 0, chars = 0 }
  if not S.Writable(db) then
    return out
  end
  for id, char in pairs(db.chars) do
    if charKey == nil or id == charKey then
      out.chars = out.chars + 1
      for _, name in ipairs(S.DOMAINS) do
        if domain == nil or domain == name then
          out.entries = out.entries + count(char[name].tot)
        end
      end
      if char.since > 0 and (not out.since or char.since < out.since) then
        out.since = char.since
      end
      if not out.last or char.last > out.last then
        out.last = char.last
      end
    end
  end
  return out
end

-- Removes one character. Returns true when it existed.
function S.ResetChar(db, charKey)
  if not (S.Writable(db) and db.chars[charKey]) then
    return false
  end
  db.chars[charKey] = nil
  S.Compact(db)
  return true
end

-- Everything: returns the new table and true. A table of a newer version is returned as it is, with false.
function S.ResetAll(db)
  if type(db) == "table" and number(db.v) and db.v > S.VERSION then
    return db, false
  end
  return S.New(), true
end

-- Only one domain ("kills" with the players defeated, or "uses"), for one character or all.
function S.ResetDomain(db, domain, charKey)
  if not (S.Writable(db) and (domain == "kills" or domain == "uses")) then
    return false
  end
  for id, char in pairs(db.chars) do
    if charKey == nil or id == charKey then
      char[domain] = newDomain(domain == "kills" and { secret = 0 } or { window = 0, secret = 0 })
      char.sess[domain] = {}
      if domain == "kills" then
        char.pvp = 0
      end
    end
  end
  S.Compact(db)
  return true
end

-- Export ---------------------------------------------------------------------------------------------------------------------

local function field(value)
  return (tostring(value):gsub("[|\r\n]", " "))
end

-- The text of the copy window: "FGSTAT v1 <build> <date>", then char|domain|id|name|period|n|g per line. Periods are
-- "total" and one date per kept day. The character shows by name, never by key. Nothing is sent anywhere.
function S.Export(db, build, date)
  local lines = { string.format("FGSTAT v%d %s %s", S.VERSION, field(build or "?"), field(date or "?")) }
  if not S.Writable(db) then
    return table.concat(lines, "\n")
  end
  local order = {}
  for charKey, char in pairs(db.chars) do
    order[#order + 1] = { key = charKey, label = char.name or charKey, char = char }
  end
  table.sort(order, function(a, b)
    if a.label ~= b.label then
      return a.label < b.label
    end
    return a.key < b.key
  end)
  local function sortedIds(tbl)
    local ids = {}
    for id in pairs(tbl) do
      ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
  end
  for _, item in ipairs(order) do
    local label = field(item.label)
    for _, domain in ipairs(S.DOMAINS) do
      local function line(id, period, n, g)
        local name = domain == "kills" and db.names[id] or ""
        lines[#lines + 1] = string.format("%s|%s|%d|%s|%s|%d|%d", label, domain, id, field(name), period, n, g)
      end
      local tot = item.char[domain].tot
      for _, id in ipairs(sortedIds(tot)) do
        line(id, "total", tot[id].n, tot[id].g or 0)
      end
      local days = item.char[domain].day
      for _, day in ipairs(sortedIds(days)) do
        for _, id in ipairs(sortedIds(days[day])) do
          line(id, S.DayDate(day), days[day][id], 0)
        end
      end
    end
  end
  return table.concat(lines, "\n")
end
