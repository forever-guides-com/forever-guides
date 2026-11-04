-- Zone transition arrows on Blizzard's world map (WorldMapFrame), from Modules/ZoneBorderLogic.lua. A zone
-- map shows an arrow at every crossing to a neighbouring zone, pointing into it (a dashed one is an estimate);
-- hover names the zone and says how sure the place is, a click opens the zone on the add-on map. The borders come from the outlines of Data.Travel and the zone rectangles on the
-- continent (C_Map.GetMapRectOnMap), the same zone view the map page uses. Other map types and zones without
-- data get none. Like WorldMapFlightPins it only hooks Blizzard's map and keeps its pins as children of the
-- canvas; the world map has no focus ring, the zone list of the map page is the keyboard route.
local _, ns = ...
local L, WML, ZBL, MW, MI, ZE =
  ns.L, ns.WorldMapLinks, ns.ZoneBorderLogic, ns.MapWorld, ns.MapIcons, ns.ZoneCrossingEdit

local WMZ = {}
ns.WorldMapZoneArrows = WMZ

local ZONE_MAP = 3 -- Enum.UIMapType.Zone
local SIZE = 18

local map
local pins = {}
local hooked = {}
local index
local parents, views = {}, {}

local function hidePins(from)
  for i = from, #pins do
    local pin = pins[i]
    pin.arrow = nil
    pin.badge:Highlight(0)
    pin:Hide()
  end
end

-- Zone records of the travel data and the zone of every UiMapID (um); zones without one have no arrows.
local function lookup()
  local zones = ns.Data.Travel and ns.Data.Travel.zones
  if not (index and index.zones == zones) then
    index = { zones = zones, bySlug = {}, byMap = {} }
    for _, z in ipairs(zones or {}) do
      index.bySlug[z.s] = z
      if z.um then
        index.byMap[z.um] = z.s
      end
    end
  end
  return index
end

-- The zone view of a zone map: its neighbours are the zones with a rectangle on the same parent map. Kept
-- per map, the rectangles do not change while the game runs; nothing is kept when the client has none.
local function zoneView(id)
  if views[id] then
    return views[id]
  end
  local slug = lookup().byMap[id]
  local info = slug and WML.CApi("GetMapInfo", id)
  local parent = type(info) == "table" and info.parentMapID
  if not (parent and parent > 0) then
    return nil
  end
  local view = parents[parent]
  if not view then
    view = MW.RectView(lookup().zones, function(um)
      return MW.Rect(WML.CApi("GetMapRectOnMap", um, parent))
    end)
    parents[parent] = next(view.zones) and view or nil
  end
  -- The rectangle on the world map is where crossings are kept, so one crossing holds on every map.
  local zv = MW.ZoneView(view, nil, slug, MW.WorldRect(id, view.zones[slug]))
  views[id] = zv
  return zv
end

local function arrowsFor(id, canvas)
  local zv = WML.MapType(id) == ZONE_MAP and zoneView(id)
  if not zv then
    return {}
  end
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  return ZBL.ForView(zv, lookup().bySlug, w > 0 and h / w or 1)
end

-- The click opens the zone on the add-on map. Blizzard's map is never switched from here: SetMapID from
-- addon code runs the map's pin and quest providers tainted.
local function open(pin, button)
  if button ~= "LeftButton" or ZE.Active() then
    return
  end
  ns.HideTooltip()
  if not ns.MapRequest then
    ns.Notify(L["zb.failed"], "warning")
    return
  end
  ns.MapOps.Record("arrow click", pin.arrow.map)
  ns.MapRequest.Open({ map = pin.arrow.map })
  ns.BlizzardLinks.RaiseMain(map)
end

local function newPin(canvas)
  local pin = CreateFrame("Button", nil, canvas)
  pin:SetSize(ns.MapPins.HIT, ns.MapPins.HIT)
  pin:RegisterForClicks("LeftButtonUp")
  pin.badge = MI.NewArrow(pin)
  pin.badge.box:SetPoint("CENTER")
  pin:SetScript("OnEnter", function(self)
    self.badge:Highlight(1)
    local title, lines = ZBL.TooltipLines(self.arrow, L, nil, ZE.HintKey("zb.hint.addon"))
    ns.ShowTooltip(self, title, table.concat(lines, "\n"))
  end)
  pin:SetScript("OnLeave", function(self)
    self.badge:Highlight(0)
    ns.HideTooltip()
  end)
  pin:SetScript("OnClick", ns.Wrap("wmz-click", open))
  ZE.Decorate(pin, WMZ.host)
  return pin
end

local function draw()
  if not (map and ns.ProtectedAllowed(map)) then
    return
  end
  local canvas = WML.Enabled("mapZoneArrowsWorld") and map:IsShown() and WML.Canvas()
  local id = canvas and WML.MapID()
  if not id then
    hidePins(1)
    return
  end
  local items, scale = arrowsFor(id, canvas), WML.CanvasScale()
  for i, arrow in ipairs(items) do
    local pin = pins[i]
    if not pin then
      pin = newPin(canvas)
      pins[i] = pin
    end
    pin.arrow, pin.nx, pin.ny = arrow, arrow.x, arrow.y
    pin.badge:Set(SIZE * ZE.Scale(), arrow.angle, arrow.state == "estimated")
    pin:SetFrameLevel(WML.CanvasLevel(canvas, "arrows"))
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
    if pin.arrow then
      WML.PlacePin(pin, canvas, scale)
    end
  end
end

WMZ.Refresh = ns.Wrap("wmz-refresh", draw)

-- The zone view of the map that is shown, nil when none is or the layer is off.
local function shownView()
  local id = map and map:IsShown() and WML.MapID()
  return id and WML.MapType(id) == ZONE_MAP and zoneView(id) or nil
end

-- Our own pins only; nothing of Blizzard's map is written.
WMZ.host = {
  id = "blizzard",
  canvas = WML.Canvas,
  view = shownView,
  zones = function()
    return lookup().bySlug
  end,
  aspect = function()
    local canvas = WML.Canvas()
    local w = canvas and canvas:GetWidth() or 0
    return w > 0 and canvas:GetHeight() / w or 1
  end,
  place = function(pin, x, y)
    pin.nx, pin.ny = x, y
    WML.PlacePin(pin, WML.Canvas(), WML.CanvasScale())
  end,
  level = function()
    local canvas = WML.Canvas()
    return canvas and WML.CanvasLevel(canvas, "arrows")
  end,
  refresh = draw,
  pins = function()
    return pins
  end,
}
ZE.Register(WMZ.host)

-- Number of shown pins.
function WMZ.Count()
  local n = 0
  for _, pin in ipairs(pins) do
    if pin.arrow then
      n = n + 1
    end
  end
  return n
end

-- State for /fg mapdiag: the zone of the shown map, the arrows computed for it (the first three), the first
-- pins, hooks.
function WMZ.Debug()
  local id = WML.MapID()
  local canvas = WML.Canvas()
  local out = { map = id, pins = {}, arrows = {}, hooks = {}, count = WMZ.Count(), pool = pins }
  out.zone = id and lookup().byMap[id]
  local list = id and canvas and arrowsFor(id, canvas) or {}
  out.computed = #list
  for i = 1, math.min(3, #list) do
    out.arrows[i] = list[i]
  end
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
  hooked[name] = WML.HookMethod("arrows", name, fn) or hooked[name]
end

-- Runs after WorldMapLinks has attached: it owns the lookup of the map frame.
function WMZ.Attach()
  if map then
    return
  end
  map = WML.Map()
  if not map then
    return
  end
  WML.HookScript("arrows", "OnShow", WMZ.Refresh)
  hookMethod("OnMapChanged", draw)
  hookMethod("OnCanvasScaleChanged", rescale)
  hookMethod("OnCanvasSizeChanged", rescale)
  WMZ.Refresh()
end

ns.On("PLAYER_LOGIN", WMZ.Attach)
-- The crossings or the editor changed (our own events, never inside a call of Blizzard's map).
local function onCrossings()
  ns.MapOps.Record("zone crossings")
  WMZ.Refresh()
end
ns.On("FG_ZONECROSS_CHANGED", onCrossings)
ns.On("FG_ZONECROSS_EDIT", onCrossings)

-- Blizzard_WorldMap is load-on-demand on some clients.
ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_WorldMap" then
    WMZ.Attach()
  end
end)
