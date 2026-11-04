-- Which flight points this character knows. Every time a flight map opens, the points the client lists
-- are matched to Data.FlightPoints and added to ns.charDB.flightKnown = { v = 1, known = { [slug] = true } }.
-- The table is absent until the first read: no data yet, so nothing may be dimmed (FlightPointsLogic.State).
-- Assumption, not yet verified in the Forever client: the flight map only lists discovered points, so a
-- listed point (CURRENT, REACHABLE or DISTANT) is a known one. /fg flightprobe prints the states to check it.
local _, ns = ...
local FL, FR, FP = ns.FlightLogic, ns.FlightRoute, ns.FlightPointsLogic

local FK = {}
ns.FlightKnown = FK

local LISTED = { CURRENT = true, REACHABLE = true, DISTANT = true }

-- "A", "H" or nil, the player's faction.
local function factionCode()
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end

-- True for the states of a point the flight map lists as a destination or as the own position.
function FK.IsListed(state)
  return LISTED[state] == true
end

-- function(name) -> slug of the flight point the client name stands for, or nil (unknown or ambiguous name).
function FK.Matcher()
  local resolve = FP.Resolver(ns.Data.FlightPoints, factionCode())
  return function(name)
    local id = FL.match(name).id
    return id and resolve(id)
  end
end

-- known set { [slug] = true }, hasData. The set is the stored table: read it, do not change it.
function FK.Set()
  local saved = ns.charDB and ns.charDB.flightKnown
  if type(saved) ~= "table" or type(saved.known) ~= "table" then
    return {}, false
  end
  return saved.known, true
end

local resolver -- { faction, fn } of the last FP.Resolver, the faction of a player does not change

-- State of the flight point behind a Travel node of the add-on map: "known", "unknown", "neutral" (no flight
-- map read yet), or nil when the node has no flight point of the player's faction.
function FK.NodeState(travelSlug)
  local faction = factionCode()
  if not resolver or resolver.faction ~= faction then
    resolver = { faction = faction, fn = FP.Resolver(ns.Data.FlightPoints, faction) }
  end
  local slug = resolver.fn(travelSlug)
  if slug then
    local set, hasData = FK.Set()
    return FP.State({ slug = slug }, set, hasData)
  end
end

-- Reads the flight map the client has open (or is about to show) and stores what it lists. Returns
-- true when it stored a result. Never in combat. A missing API, an empty list or a list without any
-- listed state changes nothing: the player's own point is always CURRENT, so a list without one is not
-- understood, and storing it would dim every point.
function FK.Learn()
  if type(ns.charDB) ~= "table" then
    return false
  end
  local nodes = FR.Nodes(true)
  if not nodes then
    return false
  end
  local names = {}
  for _, e in ipairs(nodes.list) do
    if FK.IsListed(e.state) then
      names[#names + 1] = e.name
    end
  end
  if #names == 0 then
    return false
  end
  local known = FP.Merge((FK.Set()), names, FK.Matcher())
  ns.charDB.flightKnown = { v = 1, known = known }
  return true
end

ns.On("TAXIMAP_OPENED", FK.Learn)
