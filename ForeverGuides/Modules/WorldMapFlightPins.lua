-- Flight point icons on Blizzard's world map (WorldMapFrame), from Data.FlightPoints. A zone map shows
-- the points inside it, a continent or world map those of its child zones as small icons. A point the
-- character has not discovered is dimmed (FlightKnown), a character that never read a flight map sees
-- them all normal. A pin is a button of its own: hover shows the tooltip, a left click sets the
-- waypoint. Like WorldMapInstancePins it only hooks Blizzard's map and keeps its pins as children of
-- the canvas; the keyboard route is the list of the nearest flight points (FlightPointList, /fg flights),
-- the world map has no focus ring.
local _, ns = ...
local L, WML, FP, MI = ns.L, ns.WorldMapLinks, ns.FlightPointsLogic, ns.MapIcons

local WMF = {}
ns.WorldMapFlightPins = WMF

local SIZE_ZONE, SIZE_OVERVIEW = 16, 12

local map
local pins = {}
local hooked = {}

local function hidePins(from)
  for i = from, #pins do
    local pin = pins[i]
    pin.point = nil
    pin.badge:Highlight(0)
    pin:Hide()
  end
end

local function tooltip(pin)
  local point = pin.point
  local from, x, y = ns.Waypoints.PlayerPosition()
  local yards = from and ns.WaypointLogic.distanceYards(from, x, y, point.map, point.x, point.y)
  ns.ShowTooltip(pin, point.name, FP.TooltipText(pin.state, yards, L))
end

local function newPin(canvas)
  local pin = CreateFrame("Button", nil, canvas)
  pin:SetSize(ns.MapPins.HIT, ns.MapPins.HIT)
  pin:RegisterForClicks("LeftButtonUp")
  pin.badge = MI.NewBadge(pin)
  pin.badge.box:SetPoint("CENTER")
  pin:SetScript("OnEnter", function(self)
    self.badge:Highlight(1)
    tooltip(self)
  end)
  pin:SetScript("OnLeave", function(self)
    self.badge:Highlight(0)
    ns.HideTooltip()
  end)
  pin:SetScript(
    "OnClick",
    ns.Wrap("wmf-click", function(self)
      ns.FlightPointList.SetWaypoint(self.point)
    end)
  )
  return pin
end

-- The flight points of the shown map with their place on it: the ones of the map itself, on a world or
-- continent map those of the child zones. A point without a rectangle on the map is left out.
local function placements(id)
  local points = FP.Build(ns.Data.FlightPoints, { faction = ns.PageKit.PlayerFaction() })
  local known, hasData = ns.FlightKnown.Set()
  local kind, list = WML.MapType(id), {}
  for _, p in ipairs(points) do
    local x, y = WML.Project(p.map, p.x, p.y, id, kind)
    if x then
      list[#list + 1] = { point = p, state = FP.State(p, known, hasData), x = x, y = y }
    end
  end
  return list
end

local function draw()
  if not (map and ns.ProtectedAllowed(map)) then
    return
  end
  local canvas = WML.Enabled("mapFlightWorld") and map:IsShown() and WML.Canvas()
  local id = canvas and WML.MapID()
  if not id then
    hidePins(1)
    return
  end
  local items, scale = placements(id), WML.CanvasScale()
  for i, it in ipairs(items) do
    local pin = pins[i]
    if not pin then
      pin = newPin(canvas)
      pins[i] = pin
    end
    pin.point, pin.state, pin.nx, pin.ny = it.point, it.state, it.x, it.y
    pin.badge:Set(
      "flightMaster",
      it.point.faction,
      it.point.map == id and SIZE_ZONE or SIZE_OVERVIEW,
      false,
      it.state == "unknown"
    )
    pin:SetFrameLevel(WML.CanvasLevel(canvas, "flights"))
    WML.PlacePin(pin, canvas, scale)
    pin:Show()
  end
  hidePins(#items + 1)
end

-- Zoom and canvas size changes: only position and scale, no new data.
local function rescale()
  local canvas = WML.Canvas()
  if not canvas then
    return
  end
  local scale = WML.CanvasScale()
  for _, pin in ipairs(pins) do
    if pin.point then
      WML.PlacePin(pin, canvas, scale)
    end
  end
end

WMF.Refresh = ns.Wrap("wmf-refresh", draw)

-- Number of shown pins.
function WMF.Count()
  local n = 0
  for _, pin in ipairs(pins) do
    if pin.point then
      n = n + 1
    end
  end
  return n
end

-- State for /fg mapdiag: point counts per stage, the flight map knowledge, the first pins, hooks.
function WMF.Debug()
  local id = WML.MapID()
  local points = FP.Build(ns.Data.FlightPoints, { faction = ns.PageKit.PlayerFaction() })
  local known, hasData = ns.FlightKnown.Set()
  local out = {
    map = id,
    filtered = #points,
    hasData = hasData,
    known = 0,
    pins = {},
    hooks = {},
    count = WMF.Count(),
    pool = pins,
  }
  for _ in pairs(known or {}) do
    out.known = out.known + 1
  end
  out.placed = id and #placements(id) or 0
  out.badge = pins[1] and pins[1].badge
  for i = 1, math.min(3, #pins) do
    out.pins[i] = WML.PinInfo(pins[i])
  end
  for name, on in pairs(hooked) do
    out.hooks[name] = on
  end
  return out
end

-- WML.HookMethod queues the work for the next frame, when the map already reports its new id.
local function hookMethod(name, fn)
  hooked[name] = WML.HookMethod("flights", name, fn) or hooked[name]
end

-- Runs after WorldMapLinks has attached: it owns the lookup of the map frame.
function WMF.Attach()
  if map then
    return
  end
  map = WML.Map()
  if not map then
    return
  end
  WML.HookScript("flights", "OnShow", WMF.Refresh)
  hookMethod("OnMapChanged", draw)
  hookMethod("OnCanvasScaleChanged", rescale)
  hookMethod("OnCanvasSizeChanged", rescale)
  WMF.Refresh()
end

ns.On("PLAYER_LOGIN", WMF.Attach)

-- Blizzard_WorldMap is load-on-demand on some clients.
ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_WorldMap" then
    WMF.Attach()
  end
end)
