-- Takes over the game's own map pin (the "user waypoint") when the player sets it by hand: Ctrl-click on the
-- map, a flight point or other point of interest, a shared link. The pin becomes a waypoint of ours; removing
-- the pin in the game removes (or, when pinned, deactivates) the waypoint that stood for it.
-- Our own mirror write is skipped through WP.WritingNative, and a pin that matches a waypoint is no new one,
-- so the two directions never feed each other. Switch: setting adoptNative.
local _, ns = ...
local WP, WL = ns.Waypoints, ns.WaypointLogic

local WC = {}
ns.WaypointCapture = WC

local NAME_PATHS = {
  { "name" },
  { "poiInfo", "name" },
  { "areaPoiInfo", "name" },
  { "taxiNodeData", "name" },
}

local function focusFrame()
  local many = rawget(_G, "GetMouseFoci")
  if type(many) == "function" then
    local ok, list = pcall(many)
    return ok and type(list) == "table" and list[1] or nil
  end
  local one = rawget(_G, "GetMouseFocus")
  if type(one) == "function" then
    local ok, frame = pcall(one)
    return ok and frame or nil
  end
end

-- Name of the point of interest under the cursor while the world map is open, else nil.
function WC.PoiName()
  local map = rawget(_G, "WorldMapFrame")
  if type(map) ~= "table" or type(map.IsShown) ~= "function" or not map:IsShown() then
    return nil
  end
  local frame = focusFrame()
  if type(frame) ~= "table" then
    return nil
  end
  for _, path in ipairs(NAME_PATHS) do
    local value = frame
    for _, key in ipairs(path) do
      value = type(value) == "table" and value[key] or nil
    end
    if type(value) == "string" and value ~= "" then
      return value
    end
  end
end

local function zoneTitle(map)
  local name = WP.MapName(map)
  return name ~= "#" .. tostring(map) and name or nil
end

-- The pin was removed in the game: the waypoint it mirrored goes with it. Pinned ones only step down.
local function onCleared()
  local id = WP.NativeFor()
  local active = WP.Active()
  if not (id and active and active.id == id) then
    return
  end
  -- The game drops its pin on arrival; with "keep on arrival" that must not take our marker along.
  local yards = WP.Distance(active)
  if WP.Settings().keepOnArrival and yards and yards <= WP.Settings().arrivalRadius * 2 then
    return
  end
  if active.pinned then
    WP.Deactivate()
  else
    WP.Remove(id, true)
  end
end

function WC.OnUpdated()
  if not ns.db or WP.WritingNative() then
    return
  end
  local map, x, y = WP.UserWaypoint()
  if not map then
    return onCleared()
  end
  if not WP.Settings().adoptNative then
    return
  end
  local active = WP.Active()
  if active and WL.findDuplicate({ active }, map, x, y) then
    return
  end
  WP.Set({ map = map, x = x, y = y, title = WC.PoiName() or zoneTitle(map), source = "map" })
end

ns.On("USER_WAYPOINT_UPDATED", function()
  ns.Safe("waypoint-capture", WC.OnUpdated)
end)
