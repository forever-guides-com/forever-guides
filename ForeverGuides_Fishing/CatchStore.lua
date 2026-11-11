-- The data of the catch journal: what is stored, how it is kept small, how an older or damaged saved
-- table becomes a valid one. Pure, no game calls and no clock: times and names come from outside.
--
-- Shape of ForeverGuidesFishingDB.journal (schema version S.VERSION):
--   v        schema version
--   account  one ledger for everything the account caught
--   chars    [characterKey] = { name, realm, last, ledger }, one ledger per character (last = last seen)
-- A ledger holds
--   items    [itemId] = { n, first, last, best, nm, zones = { [zoneKey] = { n, last, best } } }
--   zones    [zoneKey] = { n, casts, hits, last, nm }
-- n is a count, first and last are server times in seconds, best is the most caught in one session.
-- Every table has an upper limit (S.LIMITS), the oldest entries leave first.
local _, fish = ...
if not fish.FG then
  return
end

local S = {}
fish.CatchStore = S

S.VERSION = 1

-- Upper limits. A ledger of a character is smaller than the one of the account.
S.LIMITS = {
  items = 300,
  charItems = 150,
  zones = 80,
  zonesPerItem = 16,
  chars = 12,
  nameLength = 64,
  count = 1000000000,
}

-- Steps from one schema version to the next: STEPS[v](journal) turns a table of version v into v + 1.
-- None yet, the first schema is version 1. The tests give their own steps to prove the mechanism.
S.STEPS = {}

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

local function text(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end
  if #value > S.LIMITS.nameLength then
    value = value:sub(1, S.LIMITS.nameLength)
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

-- Ledgers ---------------------------------------------------------------------------------------------------------

function S.NewLedger()
  return { items = {}, zones = {} }
end

function S.New()
  return { v = S.VERSION, account = S.NewLedger(), chars = {} }
end

-- Removes the entries with the oldest "last" until at most `limit` remain. `keep` is never removed.
local function trim(tbl, limit, keep)
  local n = count(tbl)
  if n <= limit then
    return
  end
  local order = {}
  for key, entry in pairs(tbl) do
    if key ~= keep then
      order[#order + 1] = { key = key, last = entry.last or 0, n = entry.n or 0, text = tostring(key) }
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
    tbl[order[i].key] = nil
  end
end

local function cleanZones(raw, limit)
  local out = {}
  if type(raw) ~= "table" then
    return out
  end
  for key, entry in pairs(raw) do
    if type(key) == "string" and type(entry) == "table" then
      local n = whole(entry.n, 1, S.LIMITS.count)
      if n then
        out[key] = {
          n = n,
          last = whole(entry.last, 0, 4e9) or 0,
          best = whole(entry.best, 0, S.LIMITS.count),
        }
      end
    end
  end
  trim(out, limit)
  return out
end

-- A valid ledger from whatever was stored.
function S.CleanLedger(raw, itemLimit)
  local out = S.NewLedger()
  if type(raw) ~= "table" then
    return out
  end
  if type(raw.items) == "table" then
    for id, entry in pairs(raw.items) do
      local n = type(entry) == "table" and whole(entry.n, 1, S.LIMITS.count)
      if whole(id, 1, 4e9) == id and n then
        out.items[id] = {
          n = n,
          first = whole(entry.first, 0, 4e9),
          last = whole(entry.last, 0, 4e9) or 0,
          best = whole(entry.best, 0, S.LIMITS.count),
          nm = text(entry.nm),
          zones = cleanZones(entry.zones, S.LIMITS.zonesPerItem),
        }
      end
    end
  end
  if type(raw.zones) == "table" then
    for key, entry in pairs(raw.zones) do
      if type(key) == "string" and type(entry) == "table" then
        local n = whole(entry.n, 0, S.LIMITS.count)
        if n then
          out.zones[key] = {
            n = n,
            casts = whole(entry.casts, 0, S.LIMITS.count) or 0,
            hits = whole(entry.hits, 0, S.LIMITS.count) or 0,
            last = whole(entry.last, 0, 4e9) or 0,
            nm = text(entry.nm),
          }
        end
      end
    end
  end
  trim(out.items, itemLimit or S.LIMITS.items)
  trim(out.zones, S.LIMITS.zones)
  return out
end

-- Migration -------------------------------------------------------------------------------------------------------

-- A valid journal from whatever is stored. Returns the journal and a status:
--   "fresh"     nothing usable was stored, a new journal
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
  local out = S.New()
  out.account = S.CleanLedger(raw.account, S.LIMITS.items)
  if type(raw.chars) == "table" then
    for key, entry in pairs(raw.chars) do
      if type(key) == "string" and type(entry) == "table" then
        out.chars[key] = {
          name = text(entry.name),
          realm = text(entry.realm),
          last = whole(entry.last, 0, 4e9) or 0,
          ledger = S.CleanLedger(entry.ledger, S.LIMITS.charItems),
        }
      end
    end
    trim(out.chars, S.LIMITS.chars)
  end
  return out, migrated and "migrated" or "ok"
end

-- Recording --------------------------------------------------------------------------------------------------------

-- The key of a place: the map id when the game tells it, else the zone name. A place that is not known at all
-- gets one shared key so its catches are not lost.
function S.ZoneKey(zone)
  if type(zone) == "table" then
    if whole(zone.id, 1, 1e9) then
      return "m" .. whole(zone.id, 1, 1e9)
    end
    if text(zone.name) then
      return "n" .. text(zone.name)
    end
  end
  return "?"
end

local function zoneEntry(ledger, key, zone)
  local entry = ledger.zones[key]
  if not entry then
    entry = { n = 0, casts = 0, hits = 0, last = 0 }
    ledger.zones[key] = entry
  end
  local name = type(zone) == "table" and text(zone.name) or nil
  if name then
    entry.nm = name
  end
  return entry
end

local function addTo(ledger, limitItems, ev, zoneKey, zone, hit)
  local qty = whole(ev.qty, 1, S.LIMITS.count)
  local id = whole(ev.item, 1, 4e9)
  if not (qty and id) then
    return false
  end
  local time = whole(ev.time, 0, 4e9) or 0
  local item = ledger.items[id]
  if not item then
    item = { n = 0, first = time, last = time, zones = {} }
    ledger.items[id] = item
  end
  item.n = math.min(S.LIMITS.count, item.n + qty)
  item.first = item.first or time
  item.last = math.max(item.last or 0, time)
  local name = text(ev.name)
  if name then
    item.nm = name
  end
  if whole(ev.sessionItem, 0, S.LIMITS.count) then
    item.best = math.max(item.best or 0, whole(ev.sessionItem, 0, S.LIMITS.count))
  end
  local at = item.zones[zoneKey]
  if not at then
    at = { n = 0, last = time }
    item.zones[zoneKey] = at
  end
  at.n = math.min(S.LIMITS.count, at.n + qty)
  at.last = math.max(at.last or 0, time)
  if whole(ev.sessionZone, 0, S.LIMITS.count) then
    at.best = math.max(at.best or 0, whole(ev.sessionZone, 0, S.LIMITS.count))
  end
  local z = zoneEntry(ledger, zoneKey, zone)
  z.n = math.min(S.LIMITS.count, z.n + qty)
  z.last = math.max(z.last or 0, time)
  if hit then
    z.hits = math.min(S.LIMITS.count, z.hits + 1)
  end
  trim(item.zones, S.LIMITS.zonesPerItem, zoneKey)
  trim(ledger.items, limitItems, id)
  trim(ledger.zones, S.LIMITS.zones, zoneKey)
  return true
end

-- The ledger of a character, created on first use. Old characters leave when there are too many.
function S.CharLedger(journal, key, info)
  if type(key) ~= "string" or key == "" then
    return nil
  end
  local entry = journal.chars[key]
  if not entry then
    entry = { ledger = S.NewLedger(), last = 0 }
    journal.chars[key] = entry
  end
  entry.name = info and text(info.name) or entry.name
  entry.realm = info and text(info.realm) or entry.realm
  entry.last = info and whole(info.time, 0, 4e9) or entry.last or 0
  trim(journal.chars, S.LIMITS.chars, key)
  return entry.ledger
end

-- Writes one caught item into the account ledger and the one of the character.
-- ev: item, qty, time, name, sessionItem, sessionZone (the session totals after this catch), first (the
-- first item of a cast: counts the cast as a hit). zone: { id, name }. char: { key, name, realm }.
function S.Record(journal, char, zone, ev)
  local key = S.ZoneKey(zone)
  local ok = addTo(journal.account, S.LIMITS.items, ev, key, zone, ev.first == true)
  local mine = char and S.CharLedger(journal, char.key, { name = char.name, realm = char.realm, time = ev.time })
  if mine then
    addTo(mine, S.LIMITS.charItems, ev, key, zone, ev.first == true)
  end
  return ok
end

-- Counts one cast that began in a zone (the denominator of the hit rate).
function S.NoteCast(journal, char, zone, time)
  local key = S.ZoneKey(zone)
  local when = whole(time, 0, 4e9) or 0
  local function bump(ledger)
    local z = zoneEntry(ledger, key, zone)
    z.casts = math.min(S.LIMITS.count, z.casts + 1)
    z.last = math.max(z.last or 0, when)
    trim(ledger.zones, S.LIMITS.zones, key)
  end
  bump(journal.account)
  local mine = char and S.CharLedger(journal, char.key, { name = char.name, realm = char.realm, time = when })
  if mine then
    bump(mine)
  end
end

-- Totals of a ledger: catches, different items, places.
function S.Totals(ledger)
  local total, kinds = 0, 0
  for _, item in pairs(ledger.items) do
    total = total + item.n
    kinds = kinds + 1
  end
  return { catches = total, kinds = kinds, places = count(ledger.zones) }
end

-- The ledger to read: the account, or one character.
function S.Scope(journal, key)
  if key and journal.chars[key] then
    return journal.chars[key].ledger
  end
  return journal.account
end

-- A session: the counts since login, to find the best session of an item and of an item in a place.
function S.NewSession()
  local session = { items = {}, places = {} }
  -- Adds a catch, returns the session total of the item and of the item in the place.
  function session:Add(item, zoneKey, qty)
    self.items[item] = (self.items[item] or 0) + qty
    local place = self.places[zoneKey]
    if not place then
      place = {}
      self.places[zoneKey] = place
    end
    place[item] = (place[item] or 0) + qty
    return self.items[item], place[item]
  end
  return session
end
