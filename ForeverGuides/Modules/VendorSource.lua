-- "Who sells this": the game side of the vendor data (ForeverGuides_Professions/VendorData.lua, a load-on-demand
-- file). Loads the data once, builds the index (VendorLogic), names the zones in the client's language, knows
-- the player's faction and position, and gives the tooltip lines, the text for the shopping list and the place a
-- waypoint is set on. Reads stored data only, nothing is sent and nothing is bought.
local _, ns = ...
local VL = ns.VendorLogic

local S = {}
ns.VendorSource = S

S.ADDON = "ForeverGuides_Professions"
S.STATUS = { ok = "ok", missing = "missing" }

ns.AddLocale("enUS", {
  ["vendordata.missing"] = "Data add-on missing: install Forever Guides: Professions.",
  ["vendor.where"] = "Vendor: %s",
  ["vendor.whereCoord"] = "%s (%s, %s)",
  ["vendor.listTip"] = "Click: set a waypoint at the nearest vendor",
  ["vendor.set"] = "Vendor %s",
})
ns.AddLocale("deDE", {
  ["vendordata.missing"] = "Daten-Addon fehlt: Forever Guides: Berufsdaten installieren.",
  ["vendor.where"] = "Händler: %s",
  ["vendor.whereCoord"] = "%s (%s, %s)",
  ["vendor.listTip"] = "Klick: Wegpunkt am nächsten Händler setzen",
  ["vendor.set"] = "Händler %s",
})

local attempted, loaded = false, false
local cached -- { data = table, index = index }

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function data()
  local d = rawget(ns, "VendorData")
  return type(d) == "table" and type(d.vendors) == "table" and d or nil
end

-- One load attempt per session (none while in combat): a missing add-on does not appear without a reload.
local function load()
  if loaded then
    return true
  end
  if attempted or inCombat() then
    return false
  end
  attempted = true
  loaded = ns.LoadPackage(S.ADDON) == true
  return loaded
end

-- The index, nil plus "missing" when the data is not there. loadIt = false never loads the add-on.
function S.Index(loadIt)
  local d = data()
  if not d and loadIt ~= false and load() then
    d = data()
  end
  if not d then
    return nil, S.STATUS.missing
  end
  if not cached or cached.data ~= d then
    cached = { data = d, index = VL.Build(d) }
  end
  return cached.index, S.STATUS.ok
end

function S.Hint()
  return ns.L["vendordata.missing"]
end

-- Forgets the load attempt and the index (tests, and the package banner switched the add-on on).
function S.Reset()
  attempted, loaded, cached = false, false, nil
end

ns.On("FG_PACKAGE_CHANGED", function(_, name)
  if name == S.ADDON then
    S.Reset()
  end
end)

-- Names ----------------------------------------------------------------------------------------------

local zoneCache = {}

-- Zone of an entry in the client's language, the English name of the data as the fallback.
function S.ZoneName(entry)
  local hit = zoneCache[entry.map]
  if not hit then
    local api = rawget(_G, "C_Map")
    if type(api) == "table" and type(api.GetMapInfo) == "function" then
      local ok, info = pcall(api.GetMapInfo, entry.map)
      if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
        hit = info.name
        zoneCache[entry.map] = hit
      end
    end
  end
  return hit or entry.zoneEn
end

-- Name of an item from the client, nil while it is not loaded.
function S.ItemName(id)
  local item = rawget(_G, "C_Item")
  local byId = type(item) == "table" and item.GetItemNameByID or rawget(_G, "GetItemInfo")
  if type(byId) == "function" then
    local ok, name = pcall(byId, id)
    if ok and type(name) == "string" and name ~= "" then
      return name
    end
  end
end

function S.Money(copper)
  return ns.CostLogic.Format(copper)
end

local function context()
  return { zone = S.ZoneName, money = S.Money }
end

-- Sellers --------------------------------------------------------------------------------------------

local function playerFrom()
  local wp = rawget(ns, "Waypoints")
  if not (wp and wp.PlayerPosition) then
    return nil
  end
  local ok, map, x, y = pcall(wp.PlayerPosition)
  if ok and map then
    return { map = map, x = x, y = y }
  end
end

local function playerFaction()
  local kit = rawget(ns, "PageKit")
  return kit and kit.PlayerFaction and kit.PlayerFaction() or nil
end

-- The sellers of an item for this player (faction, distance), loading the data when it is not there. Empty when
-- the data is missing or nobody sells the item. Items that no vendor data knows cost one table lookup.
function S.Sellers(itemId, loadIt)
  local index = S.Index(loadIt)
  if not (index and index.byItem[itemId]) then
    return {}
  end
  return VL.Sellers(index, itemId, {
    faction = playerFaction(),
    from = playerFrom(),
    distance = ns.WaypointLogic and ns.WaypointLogic.distanceYards,
  })
end

-- Tooltip lines of an item ("Sold by:" and up to three sellers), nil when no vendor sells it.
function S.Lines(itemId)
  if type(itemId) ~= "number" then
    return nil
  end
  local ok, lines = pcall(function()
    return VL.Lines(S.Sellers(itemId), context())
  end)
  if not ok then
    ns.Log.warn("vendor tooltip failed: %s", tostring(lines))
    return nil
  end
  return lines
end

-- The setting that switches the block off in tooltips (settings.vendors.tooltip = false).
function S.Enabled()
  local settings = type(ns.db) == "table" and ns.db.settings
  local s = type(settings) == "table" and settings.vendors
  return not (type(s) == "table" and s.tooltip == false)
end

-- Shopping list and route ----------------------------------------------------------------------------

-- The best seller of an item with the place text "Name (Zone, x, y)" and the waypoint place, nil without one.
-- Only vendors free of conditions count as the place of a click.
function S.Best(itemId, loadIt)
  for _, seller in ipairs(S.Sellers(itemId, loadIt)) do
    if not VL.Restricted(seller.offer.flags) then
      local v = seller.vendor
      local zone = S.ZoneName(v) or "?"
      local coords = string.format("%.1f, %.1f", v.x * 100, v.y * 100)
      return {
        seller = seller,
        text = string.format(ns.L["vendor.whereCoord"], v.name, zone, coords),
        place = VL.Place(v, zone),
      }
    end
  end
end

-- Sets the waypoint on a seller or place and tells the player (the PageKit marker action).
function S.SetWaypoint(place)
  if place then
    ns.PageKit.PlaceMarker(place)
  end
end
