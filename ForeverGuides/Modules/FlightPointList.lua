-- The list of the nearest flight points for the player: rows with distance for the tab of the world map
-- bar and for /fg flights, and the waypoint a click on a flight point sets. The ordering and the texts
-- are FlightPointsLogic; this module reads the position, the faction, the known set and the settings.
local _, ns = ...
local L, FP = ns.L, ns.FlightPointsLogic

local FPL = {}
ns.FlightPointList = FPL

local function settings()
  return ns.db and ns.db.settings or {}
end

-- Length of the list from the setting (always 3 to 10).
function FPL.Count()
  return FP.ClampCount(settings().flightListCount)
end

-- rows, positioned: the nearest count points of the player's faction as FlightPointsLogic.Rows, and whether
-- the player's position is known (without it there are no rows).
function FPL.Rows(count)
  local points = FP.Build(ns.Data.FlightPoints, { faction = ns.PageKit.PlayerFaction() })
  local known, hasData = ns.FlightKnown.Set()
  local map, x, y = ns.Waypoints.PlayerPosition()
  local from = map and { map = map, x = x, y = y }
  local entries = FP.NearestList(
    points,
    known,
    hasData,
    from,
    count or FPL.Count(),
    { onlyKnown = settings().flightListOnlyKnown == true }
  )
  local active = ns.Waypoints.Active()
  local function isActive(point)
    return active ~= nil and ns.WaypointLogic.findDuplicate({ active }, point.map, point.x, point.y) ~= nil
  end
  return FP.Rows(entries, L, isActive), from ~= nil
end

-- Sets and activates the waypoint on a flight point of FlightPointsLogic.Build and tells the player.
function FPL.SetWaypoint(point)
  local wp = ns.Waypoints.Set({ map = point.map, x = point.x, y = point.y, title = point.name, source = "map" })
  if wp then
    ns.Notify(string.format(L["wp.activated"], wp.title), "info")
  end
end

-- /fg flights [n]: the nearest flight points as plain chat lines, n (3 to 10) for this call only.
function FPL.Slash(rest)
  local count
  if rest ~= "" then
    count = tonumber(rest)
    if not count then
      ns.Notify(L["fp.slash.usage"], "warning")
      return
    end
  end
  local rows, positioned = FPL.Rows(count and FP.ClampCount(count))
  if not positioned or #rows == 0 then
    ns.Notify.chat(L[positioned and "fp.list.empty" or "fp.list.noPosition"])
    return
  end
  for i, row in ipairs(rows) do
    ns.Notify.chat(FP.ChatLine(i, row, L))
  end
end
