-- Ore and herb spots and the explored look on Blizzard's world map, pure side (no frames, no client
-- calls): on which maps they show, how big a symbol is on a canvas the client zooms, and what the
-- "show the map as explored" switch does. The frames are Modules/WorldMapGather.lua.
local _, ns = ...

local WL = {}
ns.WorldMapGatherLogic = WL

-- Edge of a symbol on the screen in px. It does not grow with the zoom of the map.
WL.PIN_PX = 14

-- Enum.UIMapType values with no zone art of their own: cosmic, world, continent. Everything else (zones,
-- cities, dungeons) may hold spots or overlays, the data decides.
local WIDE = { [0] = true, [1] = true, [2] = true }

-- True when the map type (nil: the client does not say) can hold spots and explored areas.
function WL.ZoneMap(mapType)
  return mapType == nil or WIDE[mapType] ~= true
end

-- Canvas units per screen px for the canvas scale the client reports (1 when it reports nothing sound).
function WL.Unit(scale)
  if type(scale) == "number" and scale == scale and scale > 0 and scale < math.huge then
    return 1 / scale
  end
  return 1
end

-- Edge of a symbol in canvas units.
function WL.PinSize(scale)
  return WL.PIN_PX * WL.Unit(scale)
end

-- True when the world map shows spots for the map: the switch is on and the map is a zone map.
function WL.PinsWanted(on, mapId, mapType)
  return on == true and type(mapId) == "number" and mapId > 0 and WL.ZoneMap(mapType)
end

-- What the explored switch does for a map. state is the state of the data add-on (ns.PackageUI.State:
-- "ready", "idle" = on but not loaded, "off", "missing").
--   "off"     the normal look, nothing drawn
--   "draw"    draw all areas of the zone (loads the data add-on first when it is idle)
--   "banner"  wanted, but the data add-on is missing or switched off: the panel offers its button
function WL.RevealMode(on, mapId, mapType, state)
  if on ~= true or type(mapId) ~= "number" or mapId <= 0 or not WL.ZoneMap(mapType) then
    return "off"
  end
  if state == "missing" or state == "off" then
    return "banner"
  end
  return "draw"
end
