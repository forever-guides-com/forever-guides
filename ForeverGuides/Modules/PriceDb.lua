-- Auction house price database: remembers the lowest unit price of every item the player sees in
-- the auction house (passive, from browse and search results) and, on request, reads the whole list
-- of the house in one scan (lowest, median and highest unit price per item). Saved in ns.db.prices
-- per house: { v = 1, lastRequest = server time of the last full list request (one for the whole
-- account, the game limits it per account), houses = { [houseKey] = { items = { [itemId] = { mn, tn,
-- md, mx, ts } }, scan = { at, items, rows, skipped, secs } } } }, see PriceDbLogic for the fields.
-- Houses per realm: alliance, horde, one per neutral house and the legacy houses of older versions
-- (PriceDbLogic.lua, "Houses").
-- Nothing here sends a query of its own except the full list request of StartScan and the exact-name
-- query of the sell slot (live capture).
local _, ns = ...
local PL, L = ns.PriceDbLogic, ns.L
local readable = ns.ItemInfo.readable

local P = {}
ns.PriceDb = P

-- Reason of a scan that got no answer at all (the request may have been refused without a message).
P.REASON_TIMEOUT = "no response (cooldown or busy)"

ns.AddLocale("enUS", {
  ["prices.reason.disabled"] = "Price recording is switched off.",
  ["prices.reason.unsupported"] = "This client cannot read the whole auction house.",
  ["prices.reason.busy"] = "A scan is already running.",
  ["prices.reason.closed"] = "Open the auction house first.",
  ["prices.reason.combat"] = "Not possible in combat.",
  ["prices.reason.house"] = "Stand directly at the auctioneer so the addon can identify the auction house (faction or neutral).",
  ["prices.reason.cooldown"] = "The game allows one full scan every 15 minutes. Next scan possible in %d:%02d.",
  ["prices.reason.timeout"] = "The auction house did not answer (cooldown or busy). Try again later.",
  ["prices.reason.cancelled"] = "Scan cancelled.",
  ["prices.reason.error"] = "The scan stopped because of an error.",
  ["prices.house.alliance"] = "Alliance",
  ["prices.house.horde"] = "Horde",
  ["prices.house.neutral"] = "Neutral",
  ["prices.house.neutral:gadgetzan"] = "Gadgetzan",
  ["prices.house.neutral:booty"] = "Booty Bay",
  ["prices.house.neutral:everlook"] = "Everlook",
  ["prices.house.legacy"] = "Older scan",
})
ns.AddLocale("deDE", {
  ["prices.reason.disabled"] = "Die Preiserfassung ist ausgeschaltet.",
  ["prices.reason.unsupported"] = "Dieser Client kann das ganze Auktionshaus nicht lesen.",
  ["prices.reason.busy"] = "Ein Scan läuft bereits.",
  ["prices.reason.closed"] = "Öffne zuerst das Auktionshaus.",
  ["prices.reason.combat"] = "Im Kampf nicht möglich.",
  ["prices.reason.house"] = "Stell dich direkt an den Auktionator, damit das Addon das Auktionshaus erkennt (Fraktion oder neutral).",
  ["prices.reason.cooldown"] = "Das Spiel erlaubt einen kompletten Scan alle 15 Minuten. Nächster Scan möglich in %d:%02d.",
  ["prices.reason.timeout"] = "Das Auktionshaus hat nicht geantwortet (Wartezeit oder ausgelastet). Versuche es später erneut.",
  ["prices.reason.cancelled"] = "Scan abgebrochen.",
  ["prices.reason.error"] = "Der Scan wurde wegen eines Fehlers beendet.",
  ["prices.house.alliance"] = "Allianz",
  ["prices.house.horde"] = "Horde",
  ["prices.house.neutral"] = "Neutral",
  ["prices.house.neutral:gadgetzan"] = "Gadgetzan",
  ["prices.house.neutral:booty"] = "Beutebucht",
  ["prices.house.neutral:everlook"] = "Ewige Warte",
  ["prices.house.legacy"] = "Älterer Scan",
})

-- open: the auction house window is open. house: the house of the auctioneer of this visit (decided
-- when the window opens, nil while unknown, reset when it closes). scan: the running or last scan.
local state = { open = false, house = nil, scan = nil }

local ACTIVE = { waiting = true, reading = true, aggregating = true }

-- Game access -----------------------------------------------------------------------------------------

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if ok then
    return value
  end
end

local function auction(name)
  local api = rawget(_G, "C_AuctionHouse")
  return type(api) == "table" and type(api[name]) == "function" and api[name] or nil
end

local function now()
  local f = rawget(_G, "GetServerTime")
  local t = type(f) == "function" and call(f) or nil
  return readable(t) and t or ns.U.now()
end

local function clock()
  local f = rawget(_G, "GetTime")
  local t = type(f) == "function" and call(f) or nil
  return readable(t) and t or 0
end

local function inCombat()
  local f = rawget(_G, "InCombatLockdown")
  return type(f) == "function" and call(f) == true
end

local function after(delay, fn)
  local timer = rawget(_G, "C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After(delay, fn)
    return true
  end
  return false
end

-- The one place that sends the full list request. Returns true, or false and the error.
local function requestList()
  local api = rawget(_G, "C_AuctionHouse")
  if type(api) ~= "table" or type(api.ReplicateItems) ~= "function" then
    return false, "ReplicateItems is missing"
  end
  return pcall(api.ReplicateItems)
end

-- Storage ---------------------------------------------------------------------------------------------

local function root()
  if type(ns.db) ~= "table" then
    return nil
  end
  local d = ns.db.prices
  if type(d) ~= "table" then
    d = {}
    ns.db.prices = d
  end
  if type(d.houses) ~= "table" then
    d.houses = {}
  end
  if not readable(d.lastRequest) then
    d.lastRequest = 0
  end
  d.v = PL.VERSION
  return d
end

-- The saved house, nil when there is none yet.
local function peek(key)
  local d = key and root()
  local h = d and d.houses[key]
  if type(h) == "table" and type(h.items) == "table" then
    return h
  end
end

-- The saved house, created (or repaired) when missing.
local function houseData(key)
  local d = root()
  if not d then
    return nil
  end
  local h = d.houses[key]
  if type(h) ~= "table" then
    h = {}
    d.houses[key] = h
  end
  if type(h.items) ~= "table" then
    h.items = {}
  end
  if type(h.scan) ~= "table" then
    h.scan = {}
  end
  return h
end

function P.Enabled()
  local s = type(ns.db) == "table" and type(ns.db.settings) == "table" and ns.db.settings.priceDb
  return not (type(s) == "table" and s.enabled == false)
end

-- House ------------------------------------------------------------------------------------------------

local function realmName()
  return ns.Realm.Get()
end

-- true, group of a unit (nil for a unit without a faction); false when the answer cannot be read.
local function groupOf(unit)
  local f = rawget(_G, "UnitFactionGroup")
  if type(f) ~= "function" then
    return false
  end
  local ok, group = pcall(f, unit)
  if not ok or not ns.ItemInfo.accessible(group) or (group ~= nil and type(group) ~= "string") then
    return false
  end
  return true, group
end

-- The house the player belongs to: "alliance" or "horde", nil for a player without a faction.
function P.OwnHouse()
  local _, group = groupOf("player")
  return PL.FactionKey(group)
end

-- The house of the other faction, nil without an own faction.
function P.OtherHouse()
  return PL.OtherFaction(P.OwnHouse())
end

-- The keys of the neutral houses (PriceDbLogic.NEUTRAL_HOUSES).
function P.NeutralHouses()
  return PL.NeutralKeys()
end

-- The legacy house that stands in for a house (data of older versions, see PL.MigrateHouses).
function P.LegacyHouse(house)
  return PL.LegacyKey(house)
end

-- The first readable unit of npc, target and questnpc that exists and is no player is the auctioneer.
-- Returns true, faction group (nil = none) or false when no unit can be read.
local function auctioneerGroup()
  for _, unit in ipairs({ "npc", "target", "questnpc" }) do
    if call(rawget(_G, "UnitExists"), unit) == true and call(rawget(_G, "UnitIsPlayer"), unit) ~= true then
      local ok, group = groupOf(unit)
      if ok then
        return true, group
      end
    end
  end
  return false
end

-- uiMapId of the player and of its parent maps (a sub map of a city leads to the zone).
local function mapChain()
  local ids, api = {}, rawget(_G, "C_Map")
  if type(api) ~= "table" then
    return ids
  end
  local id = call(api.GetBestMapForUnit, "player")
  for _ = 1, 6 do
    if not (readable(id) and id > 0) then
      break
    end
    ids[#ids + 1] = id
    local info = call(api.GetMapInfo, id)
    id = type(info) == "table" and info.parentMapID or nil
  end
  return ids
end

local function zoneTexts()
  local texts = {}
  for _, name in ipairs({ "GetSubZoneText", "GetZoneText", "GetRealZoneText" }) do
    local text = call(rawget(_G, name))
    if type(text) == "string" and ns.ItemInfo.accessible(text) then
      texts[#texts + 1] = text
    end
  end
  return texts
end

-- The house of the auctioneer the player interacts with, read now: key and how it was decided
-- ("faction" = faction of the auctioneer, "map", "text" = neutral by zone). nil when it cannot be told.
function P.Detect()
  local ok, group = auctioneerGroup()
  if not ok then
    return nil
  end
  return PL.ChooseKey(group, mapChain(), zoneTexts())
end

-- The house of the open window. Decided once per visit; while it cannot be told it is tried again.
local function windowHouse()
  if state.house == nil then
    state.house = P.Detect()
  end
  return state.house
end

-- The house of the window that is open, nil without a window or when the auctioneer cannot be read.
function P.House()
  return state.open and windowHouse() or nil
end

-- The house a recording or scan writes into: the house of the auctioneer, nil when it is unknown.
-- Unknown houses are never written (a neutral house must not get faction prices and the other way
-- round), so passive recording skips the event and a scan is refused with the reason "house".
local function recordKey()
  local house = windowHouse()
  return house and PL.HouseKey(realmName(), house) or nil
end

local function keyOf(house)
  house = house or P.OwnHouse()
  return house and PL.HouseKey(realmName(), house) or nil
end

-- The key of the house the data belongs to: normalized realm and house. The house of the open
-- window while there is one that can be told, otherwise the house of the player's faction.
function P.HouseKey()
  return keyOf(P.House())
end

-- Name of a house in the language of the add-on (legacy houses all read "older scan").
function P.HouseName(key)
  local id = PL.IsLegacy(key) and "legacy" or tostring(key)
  local text = L["prices.house." .. id]
  return text ~= "prices.house." .. id and text or tostring(key)
end

-- Reading ----------------------------------------------------------------------------------------------

local function valuesOf(h, itemId)
  local e = h and readable(itemId) and h.items[itemId]
  if not PL.Valid(e) then
    return nil
  end
  local scanned = readable(e.md) and readable(e.mx) and readable(e.ts)
  return {
    min = e.mn,
    minAt = e.tn,
    median = scanned and e.md or nil,
    max = scanned and e.mx or nil,
    scanAt = scanned and e.ts or nil,
  }
end

-- The saved values of an item in a house (a house key, default the house of the player's faction):
-- { min, minAt, median, max, scanAt } in copper and server time. median, max and
-- scanAt are nil when the item was only seen passively. nil when unknown.
function P.Get(itemId, house)
  return valuesOf(peek(keyOf(house)), itemId)
end

-- The lowest unit price in copper, nil when unknown.
function P.Unit(itemId, house)
  local e = P.Get(itemId, house)
  return e and e.min or nil
end

-- Number of items of a house (default the house of the player's faction).
function P.Count(house)
  local h = peek(keyOf(house))
  return h and PL.Count(h.items) or 0
end

-- { at, items, rows, skipped, secs } of the last finished scan of a house (default the house of the
-- player's faction), nil when there was none. rows = rows with a price, skipped = rows without one.
function P.LastScan(house)
  local h = peek(keyOf(house))
  local s = h and type(h.scan) == "table" and h.scan or nil
  if not (s and readable(s.at) and s.at > 0) then
    return nil
  end
  return {
    at = s.at,
    items = s.items or 0,
    rows = s.rows or 0,
    skipped = s.skipped or 0,
    secs = s.secs or 0,
  }
end

-- Scan ---------------------------------------------------------------------------------------------------

local function active()
  return state.scan ~= nil and ACTIVE[state.scan.phase] == true
end

local function emitPhase(s)
  ns.Emit("FG_PRICES_SCAN", s.phase)
end

-- Counts in steps of 5 percent: every step sends the scan message once.
local function progress(s, done)
  s.done = done
  if s.total > 0 then
    local step = math.floor(done * 20 / s.total)
    if step ~= s.step then
      s.step = step
      emitPhase(s)
    end
  end
end

local function setPhase(s, phase, total)
  s.phase, s.done, s.total, s.step = phase, 0, total or 0, 0
  emitPhase(s)
end

local function release(s)
  s.buckets, s.ids, s.mn, s.md, s.mx = nil, nil, nil, nil, nil
end

local function touched()
  ns.Debounce("prices-updated", 1, function()
    ns.Emit("FG_PRICES_UPDATED")
  end)
end

local function fail(s, reason)
  if s ~= state.scan or not ACTIVE[s.phase] then
    return
  end
  release(s)
  s.phase, s.reason, s.endedAt = "failed", reason, clock()
  emitPhase(s)
end

-- Runs one step of the scan later; an error or a scan that ended meanwhile stops the chain.
local function later(s, step)
  local queued = after(PL.SLICE_DELAY, function()
    if s ~= state.scan or not active() then
      return
    end
    if not ns.Safe("prices scan", step, s) then
      fail(s, "error")
    end
  end)
  if not queued then
    fail(s, "error")
  end
end

local function blocked(s)
  if inCombat() then
    fail(s, "combat")
    return true
  end
  if not state.open then
    fail(s, "closed")
    return true
  end
  return false
end

local finishStep

local function purgeStep(s)
  local h = peek(s.key)
  if h then
    PL.Purge(h.items, now(), PL.PURGE_DAYS)
  end
  later(s, finishStep)
end

local function trimStep(s)
  local h = peek(s.key)
  if h then
    PL.Trim(h.items, PL.MAX_ITEMS)
  end
  later(s, purgeStep)
end

function finishStep(s)
  local h = houseData(s.key)
  if h then
    local scan = h.scan
    scan.at, scan.items, scan.rows, scan.skipped = s.stamp, s.items, s.rows, s.skipped
    scan.secs = math.floor(clock() - s.startedAt + 0.5)
  end
  s.endedAt = clock()
  s.phase, s.done = "done", s.total
  emitPhase(s)
  touched()
end

-- Writes the aggregated items into the house, ITEMS_PER_SLICE per tick.
local function writeStep(s)
  if blocked(s) then
    return
  end
  local h = houseData(s.key)
  local n = #s.ids
  local last = math.min(s.cursor + PL.ITEMS_PER_SLICE - 1, n)
  for i = s.cursor, last do
    if h and s.mn[i] then
      PL.ApplyScan(h.items, s.ids[i], s.mn[i], s.md[i], s.mx[i], s.stamp)
    end
  end
  s.cursor = last + 1
  progress(s, n + last)
  if last >= n then
    release(s)
    later(s, trimStep)
  else
    later(s, writeStep)
  end
end

-- Min, median and max per item, ITEMS_PER_SLICE per tick; a finished bucket is freed at once.
local function aggregateStep(s)
  if blocked(s) then
    return
  end
  local n, items = #s.ids, s.buckets.items
  local last = math.min(s.cursor + PL.ITEMS_PER_SLICE - 1, n)
  for i = s.cursor, last do
    local id = s.ids[i]
    s.mn[i], s.md[i], s.mx[i] = PL.Aggregate(items[id])
    items[id] = nil
  end
  s.cursor = last + 1
  progress(s, last)
  if last >= n then
    s.rows, s.skipped = s.buckets.rows, s.buckets.skipped
    s.buckets, s.cursor = nil, 1
    later(s, writeStep)
  else
    later(s, aggregateStep)
  end
end

local function startAggregating(s)
  s.ids = PL.Ids(s.buckets)
  s.items = #s.ids
  s.mn, s.md, s.mx = {}, {}, {}
  s.cursor = 1
  -- The work counts items twice: first the aggregation, then the writing.
  setPhase(s, "aggregating", s.items * 2)
  later(s, aggregateStep)
end

-- Reads ROWS_PER_SLICE rows per tick into the item buckets.
local function readStep(s)
  if blocked(s) then
    return
  end
  local info = auction("GetReplicateItemInfo")
  if not info then
    return fail(s, "error")
  end
  local last = math.min(s.cursor + PL.ROWS_PER_SLICE - 1, s.total)
  local buckets = s.buckets
  for i = s.cursor, last do
    -- count (3), buyoutPrice (10), itemID (17); the rows with hasAllInfo = false are used as well.
    local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemId = pcall(info, i)
    if not ok then
      ns.Log.warn("prices: GetReplicateItemInfo failed at row %d", i)
      return fail(s, "error")
    end
    if readable(itemId) and readable(buyout) and readable(count) then
      PL.Bucket(buckets, itemId, buyout, count)
    else
      buckets.skipped = buckets.skipped + 1
    end
  end
  s.cursor = last + 1
  progress(s, last)
  if last >= s.total then
    startAggregating(s)
  else
    later(s, readStep)
  end
end

-- Every event of the list after the first is counted and ignored: the client keeps sending them while
-- it loads the rows, they must not restart anything.
local function onList()
  local s = state.scan
  if not (s and active()) then
    return
  end
  if s.phase ~= "waiting" then
    s.ignored = s.ignored + 1
    return
  end
  local n = call(auction("GetNumReplicateItems"))
  if not (readable(n) and n >= 1) then
    -- Nothing to read yet: keep waiting for the next event (or the timeout).
    return
  end
  s.stamp, s.cursor, s.buckets = now(), 1, PL.NewBuckets()
  setPhase(s, "reading", math.floor(n))
  later(s, readStep)
end

local function replicateSupported()
  local timer = rawget(_G, "C_Timer")
  return auction("ReplicateItems") ~= nil
    and auction("GetNumReplicateItems") ~= nil
    and auction("GetReplicateItemInfo") ~= nil
    and type(timer) == "table"
    and type(timer.After) == "function"
end

-- Seconds until our own last request is old enough. The game limits the request per account, so
-- one time counts for all houses.
local function cooldownLeft()
  local d = root()
  return d and PL.CooldownLeft(d.lastRequest, now()) or 0
end

-- ok, reason, seconds: reason is "disabled", "unsupported", "busy", "closed" (auction house window not
-- open), "house" (the auctioneer cannot be read, so the house is unknown), "combat" or "cooldown"
-- (seconds = time left).
function P.CanScan()
  if not P.Enabled() then
    return false, "disabled"
  end
  if not replicateSupported() then
    return false, "unsupported"
  end
  if active() then
    return false, "busy"
  end
  if not state.open then
    return false, "closed"
  end
  if not P.House() then
    return false, "house"
  end
  if inCombat() then
    return false, "combat"
  end
  local left = cooldownLeft()
  if left > 0 then
    return false, "cooldown", left
  end
  return true
end

-- Requests the whole list. Returns true, or false, reason and for "cooldown" the seconds left.
function P.StartScan()
  local ok, reason, seconds = P.CanScan()
  if not ok then
    return false, reason, seconds
  end
  local s = {
    phase = "waiting",
    done = 0,
    total = 0,
    step = 0,
    ignored = 0,
    startedAt = clock(),
    key = P.HouseKey(),
    house = P.House(),
  }
  state.scan = s
  local sent, err = requestList()
  if not sent then
    ns.Log.warn("prices: ReplicateItems failed: %s", tostring(err))
    fail(s, "error")
    return false, "error"
  end
  local d = root()
  if d then
    d.lastRequest = now()
  end
  emitPhase(s)
  after(PL.SCAN_TIMEOUT, function()
    if s == state.scan and s.phase == "waiting" then
      fail(s, P.REASON_TIMEOUT)
    end
  end)
  return true
end

-- Stops a running scan. Returns true when one was running.
function P.CancelScan()
  if active() then
    fail(state.scan, "cancelled")
    return true
  end
  return false
end

-- { phase, house, done, total, reason, elapsed, rows, skipped, ignored }: house = the house being
-- scanned (nil while idle), phase is "idle" (no scan since the
-- start), "waiting", "reading" (done and total count rows), "aggregating" (done and total count the
-- work on the items, twice the items), "done" or "failed" (reason). rows and skipped: rows with and
-- without a price so far, ignored: list events after the first.
function P.ScanState()
  local s = state.scan
  if not s then
    return { phase = "idle", done = 0, total = 0, elapsed = 0, rows = 0, skipped = 0, ignored = 0 }
  end
  local b = s.buckets
  return {
    phase = s.phase,
    house = s.house,
    done = s.done,
    total = s.total,
    reason = s.reason,
    elapsed = math.max(0, (s.endedAt or clock()) - s.startedAt),
    rows = s.rows or (b and b.rows) or 0,
    skipped = s.skipped or (b and b.skipped) or 0,
    ignored = s.ignored,
  }
end

-- Deletes all saved prices (every house). The time of the last request stays, the limit of the
-- game does not go away with them.
function P.Clear()
  P.CancelScan()
  local d = root()
  for _, h in pairs(d and d.houses or {}) do
    if type(h) == "table" then
      h.items, h.scan = {}, {}
    end
  end
  touched()
end

-- Text of a failure reason (scan state or CanScan), in the language of the add-on.
function P.ReasonText(reason, seconds)
  local key = reason == P.REASON_TIMEOUT and "timeout" or tostring(reason)
  local text = L["prices.reason." .. key]
  if not text or text == "prices.reason." .. key then
    return tostring(reason)
  end
  if key == "cooldown" then
    seconds = math.max(0, math.floor(readable(seconds) and seconds or 0))
    return text:format(math.floor(seconds / 60), seconds % 60)
  end
  return text
end

-- Passive recording --------------------------------------------------------------------------------------

-- Passive recording keeps the lowest unit price of plain items only (see PL.PlainItemId): gear is
-- skipped on purpose, a variant with an item level would pass off as the base item.
local function trimIfFull(h)
  if PL.Count(h.items) > PL.MAX_ITEMS then
    PL.Trim(h.items, PL.MAX_ITEMS)
  end
end

local function recordOne(id, price)
  local key = recordKey()
  local h = key and houseData(key)
  if h then
    if PL.Passive(h.items, id, math.floor(price + 0.5), now()) then
      trimIfFull(h)
    end
    touched()
  end
end

local function onBrowse(_, added)
  if not P.Enabled() then
    return
  end
  local key = recordKey()
  local h = key and houseData(key)
  local rows = type(added) == "table" and added or call(auction("GetBrowseResults"))
  if not (h and type(rows) == "table") then
    return
  end
  local stamp, new, seen = now(), 0, 0
  for i = 1, math.min(#rows, PL.MAX_PASSIVE_ROWS) do
    local id, price = PL.BrowseRow(rows[i], readable)
    if id then
      seen = seen + 1
      if PL.Passive(h.items, id, price, stamp) then
        new = new + 1
      end
    end
  end
  if new > 0 then
    trimIfFull(h)
  end
  if seen > 0 then
    touched()
  end
end

local function onCommodity(_, itemId)
  if not (P.Enabled() and readable(itemId) and itemId >= 1) then
    return
  end
  local info = call(auction("GetCommoditySearchResultInfo"), itemId, 1)
  local price = type(info) == "table" and info.unitPrice or nil
  if readable(price) and price >= 1 then
    recordOne(itemId, price)
  end
end

local function onItemSearch(_, itemKey)
  if not P.Enabled() then
    return
  end
  local id = PL.PlainItemId(itemKey, readable)
  local info = id and call(auction("GetItemSearchResultInfo"), itemKey, 1)
  local price = type(info) == "table" and info.buyoutAmount or nil
  if readable(price) and price >= 1 then
    recordOne(id, price)
  end
end

-- Live capture (classic list API) -------------------------------------------------------------------------
-- Every list result the client holds is read when AUCTION_ITEM_LIST_UPDATE fires (the player's own
-- searches, other add-ons' searches) unless our full scan runs. One page of many is a partial
-- snapshot (PL.MergePartial); a list whose rows all fit on one page is complete and replaces the
-- values (PL.ApplyScan). A giant list (a full dump by someone else) is skipped, it would not fit a frame.
-- Putting an item into the sell slot sends one exact-name query of ours, all pages, then a complete
-- write. The query is dropped as soon as anyone else searches (post-hook on QueryAuctionItems, no
-- replacement of the game function).
local SELL_RETRY, SELL_RETRIES, SELL_TIMEOUT, SELL_REPEAT, FOREIGN_QUIET, POST_WINDOW = 0.5, 20, 8, 30, 1.5, 10

local live = { sell = nil, sending = false, foreignAt = -1000, lastName = nil, lastAt = -1000, slot = nil }
local hooked = false

function P.LiveEnabled()
  local s = type(ns.db) == "table" and type(ns.db.settings) == "table" and ns.db.settings.priceDb
  return P.Enabled() and not (type(s) == "table" and s.live == false)
end

-- Rows of the current "list" as { itemId, buyout, count }, the number of rows, the total of the query and
-- whether the owner names of all rows are loaded (they arrive with later events).
local function readList()
  local numFn, infoFn = rawget(_G, "GetNumAuctionItems"), rawget(_G, "GetAuctionItemInfo")
  if type(numFn) ~= "function" or type(infoFn) ~= "function" then
    return nil
  end
  local okNum, batch, total = pcall(numFn, "list")
  if not (okNum and readable(batch) and readable(total)) or batch > PL.MAX_PASSIVE_ROWS then
    return nil
  end
  local rows, loaded = {}, true
  for i = 1, batch do
    -- count (3), buyoutPrice (10), owner (14), itemId (17)
    local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemId = pcall(infoFn, "list", i)
    if ok then
      rows[#rows + 1] = { itemId = itemId, buyout = buyout, count = count }
      if owner == nil then
        loaded = false
      end
    end
  end
  return rows, batch, total, loaded
end

local function bucketRows(buckets, rows)
  for _, r in ipairs(rows) do
    if readable(r.itemId) and readable(r.buyout) and readable(r.count) then
      PL.Bucket(buckets, r.itemId, r.buyout, r.count)
    else
      buckets.skipped = buckets.skipped + 1
    end
  end
end

local function writeBuckets(buckets, complete)
  local key = recordKey()
  local h = key and houseData(key)
  if h and PL.Capture(h.items, buckets, complete, now()) > 0 then
    trimIfFull(h)
    touched()
  end
end

local function dropSell()
  live.sell = nil
end

local function finishSell(s, complete)
  local buckets = PL.NewBuckets()
  for _, rows in pairs(s.pages) do
    bucketRows(buckets, rows)
  end
  dropSell()
  writeBuckets(buckets, complete)
end

local trySend

-- Sends the query of the page, or tries again shortly while the game does not allow one yet.
function trySend(s)
  if s ~= live.sell then
    return
  end
  local sendFn, canFn = rawget(_G, "QueryAuctionItems"), rawget(_G, "CanSendAuctionQuery")
  if type(sendFn) ~= "function" or type(canFn) ~= "function" or inCombat() or not state.open or active() then
    return dropSell()
  end
  local quiet = clock() - live.foreignAt >= FOREIGN_QUIET
  local okCan, can = pcall(canFn)
  if not (quiet and okCan and can == true) then
    s.tries = s.tries + 1
    if s.tries > SELL_RETRIES or not after(SELL_RETRY, function()
      trySend(s)
    end) then
      dropSell()
    end
    return
  end
  live.sending = true
  -- text, minLevel, maxLevel, page, usable, rarity, getAll, exactMatch
  local sent = pcall(sendFn, s.name, nil, nil, s.page, nil, nil, false, true)
  live.sending = false
  if not sent then
    return dropSell()
  end
  s.waiting, s.seq = true, s.seq + 1
  local seq = s.seq
  after(SELL_TIMEOUT, function()
    if s == live.sell and s.waiting and s.seq == seq then
      dropSell()
    end
  end)
end

local function onSellPage(s)
  local rows, _, total, loaded = readList()
  if not rows then
    return dropSell()
  end
  if not loaded then
    return
  end
  s.pages[s.page] = rows
  local pages = math.ceil(total / PL.PAGE_SIZE)
  if pages > PL.MAX_QUERY_PAGES then
    return finishSell(s, false)
  end
  if s.page + 1 < pages then
    s.page, s.tries, s.waiting = s.page + 1, 0, false
    return trySend(s)
  end
  finishSell(s, true)
end

local function onListUpdate()
  if not P.LiveEnabled() or active() or not recordKey() then
    return
  end
  local s = live.sell
  if s and s.waiting then
    return onSellPage(s)
  end
  local rows, batch, total = readList()
  if not rows or batch < 1 then
    return
  end
  local buckets = PL.NewBuckets()
  bucketRows(buckets, rows)
  writeBuckets(buckets, total <= batch)
end

local function sellItem()
  local f = rawget(_G, "GetAuctionSellItemInfo")
  if type(f) ~= "function" then
    return nil
  end
  local ok, name, _, _, _, _, _, _, _, _, itemId = pcall(f)
  if ok and type(name) == "string" and ns.ItemInfo.accessible(name) and name ~= "" then
    return name, readable(itemId) and itemId or nil
  end
end

local function onSellSlot()
  local name, id = sellItem()
  live.slot = name and { name = name, id = id } or nil
  if not name then
    return dropSell()
  end
  if not (P.LiveEnabled() and state.open) or active() or inCombat() or not recordKey() then
    return
  end
  if live.sell and live.sell.name == name then
    return
  end
  if live.lastName == name and clock() - live.lastAt < SELL_REPEAT then
    return
  end
  live.lastName, live.lastAt = name, clock()
  live.sell = { name = name, page = 0, tries = 0, seq = 0, pages = {}, waiting = false }
  trySend(live.sell)
end

-- A started post: the price of one piece of the posted stack (the game takes the buyout per stack).
local function onPostStarted(_, buyout, _, stackSize)
  local slot = live.slot
  local unit = slot and slot.id and readable(buyout) and readable(stackSize) and PL.UnitPrice(buyout, stackSize)
  live.posting = unit and { id = slot.id, unit = unit, at = clock() } or nil
end

-- A confirmed post: nobody was seen below the posted unit price in the query, so it is the new lowest
-- (PL.MergePartial keeps a lower known price).
local function onInfoMessage(_, _, message)
  local p = live.posting
  if not p or message ~= rawget(_G, "ERR_AUCTION_STARTED") then
    return
  end
  live.posting = nil
  local key = P.LiveEnabled() and clock() - p.at <= POST_WINDOW and recordKey()
  local h = key and houseData(key)
  if h then
    PL.MergePartial(h.items, p.id, p.unit, nil, now())
    trimIfFull(h)
    touched()
  end
end

-- Post-hooks only (they run after the game function and cannot taint it), installed once.
local function installHooks()
  local hook = rawget(_G, "hooksecurefunc")
  if hooked or type(hook) ~= "function" then
    return
  end
  hooked = true
  if type(rawget(_G, "QueryAuctionItems")) == "function" then
    pcall(hook, "QueryAuctionItems", function()
      if not live.sending then
        live.foreignAt = clock()
        dropSell()
      end
    end)
  end
  if type(rawget(_G, "StartAuction")) == "function" then
    pcall(hook, "StartAuction", function(...)
      ns.Safe("prices post", onPostStarted, ...)
    end)
  end
end

-- Events ----------------------------------------------------------------------------------------------------

local function auctioneerType()
  local types = type(Enum) == "table" and Enum.PlayerInteractionType
  return type(types) == "table" and types.Auctioneer or nil
end

-- The window open signal comes twice (own event and interaction manager).
local function opened()
  installHooks()
  if not state.open then
    state.open, state.house = true, nil
  end
  windowHouse()
end

local function closed()
  state.open, state.house = false, nil
  dropSell()
  if active() then
    fail(state.scan, "closed")
  end
end

ns.On("AUCTION_HOUSE_SHOW", opened)
ns.On("AUCTION_HOUSE_CLOSED", closed)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
  if kind ~= nil and kind == auctioneerType() then
    opened()
  end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
  if kind ~= nil and kind == auctioneerType() then
    closed()
  end
end)
ns.On("PLAYER_REGEN_DISABLED", function()
  if active() then
    fail(state.scan, "combat")
  end
end)
ns.On("REPLICATE_ITEM_LIST_UPDATE", onList)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", onBrowse)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", onBrowse)
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", onCommodity)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", onItemSearch)
ns.On("AUCTION_ITEM_LIST_UPDATE", onListUpdate)
ns.On("NEW_AUCTION_UPDATE", onSellSlot)
ns.On("UI_INFO_MESSAGE", onInfoMessage)

-- Old and damaged entries go at login, a house without items goes too.
ns.On("PLAYER_LOGIN", function()
  local d, t = root(), now()
  for key, h in pairs(d and d.houses or {}) do
    if type(h) ~= "table" or type(h.items) ~= "table" then
      d.houses[key] = nil
    else
      PL.Purge(h.items, t, PL.PURGE_DAYS)
      if next(h.items) == nil then
        d.houses[key] = nil
      end
    end
  end
end)

-- Diagnostics ------------------------------------------------------------------------------------------------

-- One line for /fg diag: the houses (faction part of the key only, no realm names), the entries, the
-- last scan and a size estimate of the saved data.
function P.DiagLine()
  local d = root()
  local keys, total = {}, 0
  for key, h in pairs(d and d.houses or {}) do
    if type(h) == "table" and type(h.items) == "table" then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    local h = d.houses[key]
    local n = PL.Count(h.items)
    total = total + n
    local scan = type(h.scan) == "table" and h.scan or {}
    local last = "no scan"
    if readable(scan.at) and scan.at > 0 then
      local okDate, text = pcall(date, "%Y-%m-%d %H:%M", scan.at)
      last = string.format(
        "scan %s %s rows %s items %ss",
        okDate and text or tostring(scan.at),
        tostring(scan.rows),
        tostring(scan.items),
        tostring(scan.secs)
      )
    end
    parts[#parts + 1] = string.format("%s items=%d %s", key:match("%-([^%-]+)$") or "?", n, last)
  end
  return string.format(
    "prices: enabled=%s own=%s window=%s %s size~%.0f KB",
    tostring(P.Enabled()),
    P.OwnHouse() or "none",
    P.House() or "none",
    #parts > 0 and table.concat(parts, "; ") or "no data",
    total * PL.BYTES_PER_ITEM / 1024
  )
end
