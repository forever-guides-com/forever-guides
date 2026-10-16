-- Pure part of the auction house price database (PriceDb.lua): unit price rounding, per item
-- aggregation (min, median, max), the incremental buckets of a scan, the passive browse row rule,
-- trim and purge of the saved items. No game calls; everything that comes from the game is checked
-- here as a plain finite number (the caller may pass a stricter readable test).
-- Saved item entry (flat integers only, server time epoch): mn = lowest unit price in copper,
-- tn = time of mn, md = median, mx = highest, ts = time of md and mx (set by a scan only).
local _, ns = ...

local PL = {}
ns.PriceDbLogic = PL

PL.VERSION = 1
PL.MAX_ITEMS = 20000
PL.PURGE_DAYS = 60
PL.DAY = 86400
-- One scan tick reads this many rows or handles this many items, so no tick runs long.
PL.ROWS_PER_SLICE = 250
PL.ITEMS_PER_SLICE = 150
PL.SLICE_DELAY = 0.01
-- The game allows one full list request per 15 minutes; no answer after the timeout ends the scan.
PL.SCAN_COOLDOWN = 900
PL.SCAN_TIMEOUT = 30
-- Rows of one browse event that are read at most.
PL.MAX_PASSIVE_ROWS = 1000
-- Rough size of one entry in the saved variables file, for the size estimate of the diagnostics.
PL.BYTES_PER_ITEM = 60

local floor, max = math.floor, math.max

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end
PL.finite = finite

local function round(v)
  return floor(v + 0.5)
end

local function positiveInt(v)
  return finite(v) and v >= 1 and v == floor(v)
end

-- Price of one piece in whole copper (nearest), nil without a usable price or count.
function PL.UnitPrice(buyout, count)
  if not (finite(buyout) and finite(count)) or buyout <= 0 or count < 1 then
    return nil
  end
  local unit = round(buyout / count)
  return unit >= 1 and unit or nil
end

-- min, median, max of a list of copper prices (sorted or not, the list is not changed). The median of
-- an even count is the mean of the two middle values, rounded to whole copper. Entries that are not
-- finite numbers are ignored; nil when no price is left.
function PL.Aggregate(prices)
  local values = {}
  for i = 1, #(type(prices) == "table" and prices or {}) do
    if finite(prices[i]) then
      values[#values + 1] = prices[i]
    end
  end
  local n = #values
  if n == 0 then
    return nil
  end
  table.sort(values)
  local median = values[(n + 1) / 2]
  if n % 2 == 0 then
    median = round((values[n / 2] + values[n / 2 + 1]) / 2)
  end
  return values[1], median, values[n]
end

-- Buckets ------------------------------------------------------------------------------------------

function PL.NewBuckets()
  return { items = {}, rows = 0, skipped = 0 }
end

-- One row into its item bucket. Returns true when the row was used (positive integer item id,
-- buyout above 0, count above 0), false when it was skipped.
function PL.Bucket(buckets, itemId, buyout, count)
  local unit = positiveInt(itemId) and PL.UnitPrice(buyout, count)
  if not unit then
    buckets.skipped = buckets.skipped + 1
    return false
  end
  local list = buckets.items[itemId]
  if not list then
    list = {}
    buckets.items[itemId] = list
  end
  list[#list + 1] = unit
  buckets.rows = buckets.rows + 1
  return true
end

-- The rows { itemId, buyout, count } in one go. Returns used, skipped of this call.
function PL.Add(buckets, rows)
  local used, skipped = 0, 0
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    if type(row) == "table" and PL.Bucket(buckets, row.itemId, row.buyout, row.count) then
      used = used + 1
    else
      skipped = skipped + 1
      if type(row) ~= "table" then
        buckets.skipped = buckets.skipped + 1
      end
    end
  end
  return used, skipped
end

-- Item ids of the buckets, ascending.
function PL.Ids(buckets)
  local ids = {}
  for id in pairs(buckets.items) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

-- Saved items --------------------------------------------------------------------------------------

-- The newest time of an entry (0 for a damaged one).
function PL.Stamp(entry)
  if type(entry) ~= "table" then
    return 0
  end
  return max(finite(entry.tn) and entry.tn or 0, finite(entry.ts) and entry.ts or 0)
end

-- A usable entry: a lowest price of 1 copper or more and its time.
function PL.Valid(entry)
  return type(entry) == "table" and positiveInt(entry.mn) and finite(entry.tn) and entry.tn > 0
end

-- The lowest price seen passively (browse, search). Keeps median, highest and their time. An older
-- sighting never replaces a newer lowest price. Returns true when the entry is new.
function PL.Passive(items, itemId, price, now)
  local e = items[itemId]
  if not PL.Valid(e) then
    items[itemId] = { mn = price, tn = now }
    return true
  end
  if now >= e.tn then
    e.mn, e.tn = price, now
  end
  return false
end

-- The result of a scan for one item. A lowest price seen passively after the scan data stays.
function PL.ApplyScan(items, itemId, mn, md, mx, now)
  local e = items[itemId]
  if not PL.Valid(e) then
    e = {}
    items[itemId] = e
  end
  if not PL.Valid(e) or now >= e.tn then
    e.mn, e.tn = mn, now
  end
  e.md, e.mx, e.ts = md, mx, now
end

function PL.Count(items)
  local n = 0
  for _ in pairs(type(items) == "table" and items or {}) do
    n = n + 1
  end
  return n
end

-- Drops the entries with the oldest newest-time until `cap` are left (ties: lower item id first).
-- Counts the times first and sorts only the distinct ones, so a scan (one time for all) stays cheap.
-- Returns how many were dropped.
function PL.Trim(items, cap)
  cap = max(0, floor(finite(cap) and cap or PL.MAX_ITEMS))
  local total, tally = 0, {}
  for _, e in pairs(items) do
    local stamp = PL.Stamp(e)
    tally[stamp] = (tally[stamp] or 0) + 1
    total = total + 1
  end
  local excess = total - cap
  if excess <= 0 then
    return 0
  end
  local stamps = {}
  for stamp in pairs(tally) do
    stamps[#stamps + 1] = stamp
  end
  table.sort(stamps)
  local whole, partial, remaining = nil, nil, excess
  for _, stamp in ipairs(stamps) do
    if tally[stamp] <= remaining then
      whole, remaining = stamp, remaining - tally[stamp]
    else
      partial = stamp
      break
    end
  end
  local ties = {}
  for id, e in pairs(items) do
    local stamp = PL.Stamp(e)
    if whole and stamp <= whole then
      items[id] = nil
    elseif stamp == partial then
      ties[#ties + 1] = id
    end
  end
  table.sort(ties, function(a, b)
    local na, nb = type(a) == "number", type(b) == "number"
    if na and nb then
      return a < b
    end
    if na ~= nb then
      return na
    end
    return tostring(a) < tostring(b)
  end)
  for i = 1, remaining do
    items[ties[i]] = nil
  end
  return excess
end

-- Drops damaged entries (no usable price, no item id) and those not seen for `days` days.
-- Returns how many were dropped.
function PL.Purge(items, now, days)
  local limit = now - days * PL.DAY
  local dropped = 0
  for id, e in pairs(items) do
    if not (positiveInt(id) and PL.Valid(e)) or PL.Stamp(e) < limit then
      items[id] = nil
      dropped = dropped + 1
    end
  end
  return dropped
end

-- Seconds until the next full list request is allowed (0 when it is), from the last request time.
-- A request time in the future (a clock that moved back) counts as a request just now.
function PL.CooldownLeft(requested, now)
  if not (finite(requested) and finite(now)) or requested <= 0 then
    return 0
  end
  return math.min(PL.SCAN_COOLDOWN, max(0, floor(requested + PL.SCAN_COOLDOWN - now)))
end

-- The house name from a faction group: Horde, Alliance or Neutral (any other answer).
function PL.House(faction)
  if faction == "Horde" or faction == "Alliance" then
    return faction
  end
  return "Neutral"
end

function PL.HouseKey(realm, house)
  return string.format("%s-%s", type(realm) == "string" and realm ~= "" and realm or "unknown", PL.House(house))
end

-- Browse -------------------------------------------------------------------------------------------

-- The item id of an item key when it stands for one plain item: no suffix, no battle pet, no item
-- level (gear carries one). Gear prices are not recorded from browse and search results, a variant
-- would pass off as the base item. A missing field counts as 0; a field that is there and not
-- readable rejects the key. `readable` (optional) is the caller's stricter test of a number.
function PL.PlainItemId(key, readable)
  readable = readable or finite
  if type(key) ~= "table" or not readable(key.itemID) or not positiveInt(key.itemID) then
    return nil
  end
  for _, field in ipairs({ "itemSuffix", "battlePetSpeciesID", "itemLevel" }) do
    local v = key[field]
    if v ~= nil and not (readable(v) and v == 0) then
      return nil
    end
  end
  return key.itemID
end

-- itemId, price of one browse result row (minPrice is the lowest unit price), nil when the row is
-- not a plain item or has no readable price.
function PL.BrowseRow(row, readable)
  readable = readable or finite
  if type(row) ~= "table" then
    return nil
  end
  local id = PL.PlainItemId(row.itemKey, readable)
  local price = row.minPrice
  if id and readable(price) and price >= 1 then
    return id, round(price)
  end
  return nil
end
