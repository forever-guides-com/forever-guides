-- Records where the player walks or rides from one zone into the next. Once a second the position of the player
-- is sampled (Waypoints.PlayerPosition); when the map changes between two samples, ZoneCrossingLogic.Observe
-- decides whether that was a real crossing (neither a taxi, a teleport, a death nor an instance) and the
-- place goes to the zone pair as a recorded crossing. Reading the position is all it does, also in combat. The
-- recordings stay in SavedVariables on this computer, nothing is sent anywhere.
local _, ns = ...
local WP, WL, MW, ZCL, Guard = ns.Waypoints, ns.WaypointLogic, ns.MapWorld, ns.ZoneCrossingLogic, ns.AutoGuard

ns.AddLocale("enUS", {
  ["zcr.set.record"] = "Record zone crossings while walking",
  ["zcr.set.recordHint"] = "When you walk or ride from one zone into the next, the add-on notes where you crossed and shows the place as a real crossing on the maps. Flights, teleports, deaths and instances are skipped. Saved on this computer only, nothing is sent anywhere.",
  ["zcr.set.notify"] = "Message for every new crossing",
  ["zcr.recorded"] = "Crossing %s to %s recorded",
})
ns.AddLocale("deDE", {
  ["zcr.set.record"] = "Zonenübergänge beim Laufen aufnehmen",
  ["zcr.set.recordHint"] = "Wenn du von einer Zone in die nächste läufst oder reitest, merkt sich das Addon die Stelle und zeigt sie auf den Karten als echten Übergang. Flüge, Teleports, Tod und Instanzen zählen nicht. Gespeichert wird nur auf diesem Computer, es wird nichts gesendet.",
  ["zcr.set.notify"] = "Meldung bei jedem neuen Übergang",
  ["zcr.recorded"] = "Übergang %s zu %s aufgenommen",
})

local ZCR = {}
ns.ZoneCrossingRecorder = ZCR

ZCR.INTERVAL = 1
-- Instance types in which nothing is recorded: everything but the open world.
local OPEN_WORLD = "none"

local tracker = ZCL.NewTracker()
local ticker
local index, rects = nil, {}

local function now()
  return type(GetTime) == "function" and GetTime() or 0
end

-- Zone slug by UiMapID and UiMapID by slug of the travel data.
local function lookup()
  local zones = ns.Data.Travel and ns.Data.Travel.zones
  if not (index and index.zones == zones) then
    index = { zones = zones, bySlug = {}, byMap = {} }
    rects = {}
    for _, z in ipairs(zones or {}) do
      if z.um and z.pc ~= "canvas" then
        index.byMap[z.um], index.bySlug[z.s] = z.s, z.um
      end
    end
  end
  return index
end

local env = {
  zoneOfMap = function(map)
    return lookup().byMap[map]
  end,
  worldRect = function(slug)
    local map = lookup().bySlug[slug]
    if map and not rects[slug] then
      rects[slug] = MW.WorldRect(map)
    end
    return rects[slug]
  end,
  distance = function(...)
    return WL.distanceYards(...)
  end,
}

-- found, readable, then the two results of a game function; found is false when the client has no such function,
-- readable is false when a result is a value the game does not let us read.
local function ask(name, ...)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then
    return false
  end
  local ok, a, b = pcall(fn, ...)
  if not ok then
    return true, false
  end
  local x, y = Guard.Safe(a), Guard.Safe(b)
  return true, (a == nil or x ~= nil) and (b == nil or y ~= nil), x, y
end

-- Why the player cannot make a crossing right now: a taxi flight, death or ghost (a spirit release is a
-- teleport), an instance or battleground; nil in the open world. A value the game does not let us read counts as
-- a reason, a function the client lacks does not.
local function blocked()
  local found, readable, taxi = ask("UnitOnTaxi", "player")
  if found and (not readable or taxi) then
    return "taxi"
  end
  local dead
  found, readable, dead = ask("UnitIsDeadOrGhost", "player")
  if found and (not readable or dead) then
    return "dead"
  end
  local kind
  found, readable, _, kind = ask("IsInInstance")
  if found and (not readable or (kind ~= nil and kind ~= OPEN_WORLD)) then
    return "instance"
  end
end

-- One sample and what follows from it; returns whatever ZoneCrossingLogic.Record says about a crossing, else nil.
function ZCR.Probe()
  local map, x, y = WP.PlayerPosition()
  local crossing = ZCL.Observe(tracker, { t = now(), map = map, x = x, y = y, blocked = blocked() }, env)
  if not crossing then
    return nil
  end
  local result = ZCL.Record(crossing.key, crossing.x, crossing.y)
  if result == "new" and ns.db.settings.zoneCrossNotify ~= false then
    local zones = lookup().zones
    local names = {}
    for _, z in ipairs(zones or {}) do
      if z.s == crossing.a or z.s == crossing.b then
        names[z.s] = ns.T(z.n)
      end
    end
    ns.Notify(
      string.format(ns.L["zcr.recorded"], names[crossing.a] or crossing.a, names[crossing.b] or crossing.b),
      "info"
    )
  end
  return result
end

local function enabled()
  return ns.db and ns.db.settings.zoneCrossRecord ~= false
end

-- Starts or stops the sampling to match the setting.
function ZCR.Apply()
  if enabled() and not ticker then
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.NewTicker) == "function" then
      ticker = timer.NewTicker(ZCR.INTERVAL, ns.Wrap("zone-crossing-probe", ZCR.Probe))
    end
  elseif not enabled() and ticker then
    ticker:Cancel()
    ticker, tracker = nil, ZCL.NewTracker()
  end
end

function ZCR.Running()
  return ticker ~= nil
end

ns.On("PLAYER_LOGIN", ZCR.Apply)

-- A new zone shows up in the sample at once instead of up to a second later.
ns.On("ZONE_CHANGED_NEW_AREA", function()
  if ticker then
    ns.Safe("zone-crossing-probe", ZCR.Probe)
  end
end)
