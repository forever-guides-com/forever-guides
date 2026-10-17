-- Reads the layer of the current zone out of the GUIDs of NPCs you can see (target, mouseover, focus, soft
-- targets, name plates, the NPC of a dialog or a merchant window). Only reads: no network, no channel,
-- nothing is sent or changed. Every game call runs in pcall and values the client hides (secret values) are
-- dropped, so the module stays quiet instead of raising. ns.Layer.Get() answers the layer last seen in this
-- zone, ns.Layer.Refresh() reads all sources again; FG_LAYER_CHANGED announces a new or lost layer.
local _, ns = ...
local Guard, LL = ns.AutoGuard, ns.LayerLogic

local R = {}
ns.Layer = R

-- Unit tokens read directly, in the order of Refresh. The source id of a read is the token itself.
R.UNITS = { "target", "mouseover", "focus", "softenemy", "softfriend", "softinteract" }

local state = LL.New()

local function clock()
  local fn = rawget(_G, "GetTime")
  return type(fn) == "function" and fn() or 0
end

-- The answer of a game function by its global path, nil when it is missing, raises or is hidden.
local function call(path, ...)
  local ok, found, value = pcall(Guard.Call, path, ...)
  if ok and found then
    return Guard.Safe(value)
  end
  return nil
end

-- The zone-level map of the player; nil when the client has none. The layer is tied to it.
local function currentMap()
  local id = call("C_Map.GetBestMapForUnit", "player")
  if type(id) ~= "number" then
    return nil
  end
  return LL.ZoneOf(id, function(mapId)
    return call("C_Map.GetMapInfo", mapId)
  end)
end

local function observe(layer, source)
  local result, old = LL.Observe(state, layer, currentMap(), clock(), source)
  if result == "first" or result == "changed" then
    ns.Emit("FG_LAYER_CHANGED", layer, old)
  end
  return result ~= nil
end

-- Reads one unit token. force skips the debounce (the explicit refresh). Players carry no layer id and are
-- skipped before the debounce, so a burst of player plates does not use up the read of the NPC behind them.
local function readUnit(unit, source, force)
  if type(unit) ~= "string" or call("UnitIsPlayer", unit) ~= false then
    return false
  end
  if not (force or LL.Due(state, source, clock())) then
    return false
  end
  local info = LL.ParseGUID(call("UnitGUID", unit))
  return info ~= nil and observe(info.zoneUID, source)
end

-- Unit tokens of the visible name plates, empty without the plate function.
local function plateTokens()
  local plates = call("C_NamePlate.GetNamePlates")
  local out = {}
  if type(plates) ~= "table" then
    return out
  end
  for _, plate in ipairs(plates) do
    local ok, token = pcall(function()
      return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    end)
    if ok and type(token) == "string" then
      out[#out + 1] = token
    end
  end
  return out
end

-- Public API ---------------------------------------------------------------------------------------------

-- layer, map id, clock of the last confirmation, source, previous layer. nil when no layer is known for the
-- zone the player is in.
function R.Get()
  if not LL.Valid(state, currentMap()) then
    return nil
  end
  return state.layer, state.mapId, state.at, state.source, state.previous
end

-- "Layer 4812", or "Layer ?" while the zone has no layer.
function R.Text()
  return LL.Text(state, currentMap(), ns.L)
end

-- "12 s ago" for the layer of this zone, nil without one.
function R.Age()
  if not LL.Valid(state, currentMap()) then
    return nil
  end
  return LL.Age(state, clock(), ns.L)
end

-- The zone-level map the player is in (the map the layer is tied to), nil when the client has none. Known
-- also while the layer itself is not.
function R.Map()
  return currentMap()
end

-- Name of the zone of a map id, "?" when the client does not tell.
function R.ZoneName(mapId)
  local info = mapId and call("C_Map.GetMapInfo", mapId)
  local name = type(info) == "table" and info.name or call("GetRealZoneText")
  return type(name) == "string" and name ~= "" and name or "?"
end

-- Reads every source now, without the debounce. True when a layer was found. One readable plate is enough,
-- all NPCs of a zone show the same layer.
function R.Refresh()
  local found = false
  for _, unit in ipairs(R.UNITS) do
    found = readUnit(unit, unit, true) or found
  end
  for _, token in ipairs(plateTokens()) do
    if readUnit(token, "nameplate", true) then
      found = true
      break
    end
  end
  return found
end

-- Forgets the layer, for a zone change.
function R.Reset()
  local old = state.layer
  LL.Reset(state)
  if old ~= nil then
    ns.Emit("FG_LAYER_CHANGED", nil, old)
  end
end

-- Events --------------------------------------------------------------------------------------------------

ns.On("PLAYER_TARGET_CHANGED", function()
  readUnit("target", "target")
end)
ns.On("UPDATE_MOUSEOVER_UNIT", function()
  readUnit("mouseover", "mouseover")
end)
ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
  readUnit(Guard.Safe(unit), "nameplate")
end)
ns.On("GOSSIP_SHOW", function()
  readUnit("npc", "gossip")
end)
ns.On("MERCHANT_SHOW", function()
  readUnit("npc", "merchant")
end)

-- A new zone has its own layer; the plates and the target of the new place are read a second later.
local function onZone()
  R.Reset()
  ns.Debounce("layer-scan", 1, R.Refresh)
end
ns.On("ZONE_CHANGED_NEW_AREA", onZone)
ns.On("PLAYER_ENTERING_WORLD", onZone)
