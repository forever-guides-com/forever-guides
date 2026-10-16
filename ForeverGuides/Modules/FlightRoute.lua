-- Reads the open flight map of the game: the flight points (slot, name, state) and, for a chosen
-- destination, the hops of the flight with their names. Read only, nothing here takes a flight.
-- The client has two flight windows (source: Blizzard_FlightMap and TaxiFrame):
--   "map"  = FlightMapFrame with C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID()), slotIndex per node
--   "taxi" = TaxiFrame with NumTaxiNodes / TaxiNodeName / TaxiNodeGetType per slot
-- Both share GetNumRoutes(slot) and TaxiGetNodeSlot(slot, hop, fromSlot). Every call is guarded
-- and wrapped in pcall, so a client without a function gives fewer nodes and never an error.
local _, ns = ...
local FL = ns.FlightLogic

local FR = {}
ns.FlightRoute = FR

-- Which source delivered the last node list: "map", "taxi", "map+taxi" or nil.
FR.variant = nil

local FRAMES = { "FlightMapFrame", "TaxiFrame" }
-- Enum.FlightPathState of the map variant, the strings TaxiNodeGetType returns.
local MAP_STATE = { [0] = "CURRENT", [1] = "REACHABLE", [2] = "UNREACHABLE" }

local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
  return nil
end

local function game(name)
  return _G[name]
end

-- "A" or "H" for the faction of the player, nil when the game does not say.
local function factionCode()
  local faction = try(game("UnitFactionGroup"), "player")
  return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end

local function inCombat()
  return InCombatLockdown ~= nil and InCombatLockdown() == true
end

-- Name of the flight window that is shown ("FlightMapFrame" or "TaxiFrame"), or nil.
function FR.OpenFrame()
  for _, name in ipairs(FRAMES) do
    local frame = game(name)
    if type(frame) == "table" and type(frame.IsShown) == "function" and try(frame.IsShown, frame) == true then
      return name
    end
  end
end

local function entry(list, bySlot, slot)
  local e = bySlot[slot]
  if not e then
    e = { slot = slot }
    bySlot[slot] = e
    list[#list + 1] = e
  end
  return e
end

-- Flight points of the open window: { list = { { slot, name, state, match } ... }, bySlot }, or
-- nil and the reason ("combat", "closed", "empty"). match is FlightLogic.match of the name.
function FR.Nodes()
  if inCombat() then
    return nil, "combat"
  end
  if not FR.OpenFrame() then
    return nil, "closed"
  end
  local list, bySlot, viaTaxi, viaMap = {}, {}, false, false
  local count = tonumber(try(game("NumTaxiNodes")))
  if count and type(game("TaxiNodeName")) == "function" then
    for slot = 1, count do
      local name = try(game("TaxiNodeName"), slot)
      if type(name) == "string" and name ~= "" and not FL.isObsolete(name) then
        local e = entry(list, bySlot, slot)
        e.name = name
        e.state = try(game("TaxiNodeGetType"), slot)
        viaTaxi = true
      end
    end
  end
  local map = game("C_TaxiMap")
  local mapId = type(map) == "table" and type(map.GetAllTaxiNodes) == "function" and try(game("GetTaxiMapID")) or nil
  local data = mapId and try(map.GetAllTaxiNodes, mapId)
  if type(data) == "table" then
    for _, d in ipairs(data) do
      if
        type(d) == "table"
        and type(d.slotIndex) == "number"
        and type(d.name) == "string"
        and not FL.isObsolete(d.name)
      then
        local e = entry(list, bySlot, d.slotIndex)
        e.name = e.name or d.name
        e.state = MAP_STATE[d.state] or e.state
        e.transition = d.isMapLayerTransition == true
        viaMap = true
      end
    end
  end
  if #list == 0 then
    FR.variant = nil
    return nil, "empty"
  end
  FR.variant = (viaMap and viaTaxi) and "map+taxi" or (viaMap and "map" or "taxi")
  table.sort(list, function(a, b)
    return a.slot < b.slot
  end)
  for _, e in ipairs(list) do
    e.match = FL.match(e.name)
  end
  return { list = list, bySlot = bySlot }
end

local function describe(nodes, slot)
  local e = nodes and nodes.bySlot[slot]
  if e then
    return e.name, e.match and e.match.id
  end
  local name = try(game("TaxiNodeName"), slot)
  if type(name) == "string" and name ~= "" then
    return name, FL.match(name).id
  end
end

-- Route to the destination slot: { hops = { { fromName, toName, fromNode, toNode, fromSlot,
-- toSlot } ... }, total = FlightLogic.estimateRoute }, or nil and the reason. fromNode and toNode
-- are our node ids (nil when the name is not matched clearly). nodes: result of FR.Nodes().
function FR.Route(slot, nodes)
  if inCombat() then
    return nil, "combat"
  end
  local count = tonumber(try(game("GetNumRoutes"), slot))
  if not count or count < 1 then
    return nil, "noRoute"
  end
  local hops, pairsForTotal = {}, {}
  for i = 1, count do
    local fromSlot = try(game("TaxiGetNodeSlot"), slot, i, true)
    local toSlot = try(game("TaxiGetNodeSlot"), slot, i, false)
    if type(fromSlot) ~= "number" or type(toSlot) ~= "number" then
      return nil, "noSlot"
    end
    local fromName, fromNode = describe(nodes, fromSlot)
    local toName, toNode = describe(nodes, toSlot)
    hops[i] = {
      fromName = fromName,
      toName = toName,
      fromNode = fromNode,
      toNode = toNode,
      fromSlot = fromSlot,
      toSlot = toSlot,
    }
    pairsForTotal[i] = { from = fromNode, to = toNode }
  end
  return { hops = hops, total = FL.estimateRoute(pairsForTotal, nil, nil, factionCode()) }
end
