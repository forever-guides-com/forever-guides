-- Instance entrance pins on Blizzard's world map (WorldMapFrame), from Modules/MapMarkerLogic.lua.
-- A zone map shows the entrances inside it, a continent or world map those of its child zones as
-- small icons. A pin is a button of its own: hover shows the tooltip, a click opens the instance page
-- of the add-on (its dungeon map when there is one). Like WorldMapLinks it only hooks Blizzard's
-- map and keeps its pins as children of the canvas; the keyboard route is the instance list of the
-- add-on, the world map has no focus ring.
local _, ns = ...
local L, WML, MML, MI = ns.L, ns.WorldMapLinks, ns.MapMarkerLogic, ns.MapIcons

local WMI = {}
ns.WorldMapInstancePins = WMI

local ICON = { dungeon = "instanceEntrance", raid = "raidEntrance" }
-- The letter plate does not depend on an atlas of the client: the pin always has a symbol of its own.
local LETTER = { dungeon = "D", raid = "R" }
local SIZE_ZONE, SIZE_OVERVIEW = 16, 12 -- as the flight points

local map
local pins = {}
local hooked = {}

local function hidePins(from)
  for i = from, #pins do
    local pin = pins[i]
    pin.marker = nil
    pin.badge:Highlight(0)
    pin:Hide()
  end
end

-- Router path of the instance page: the map tab when the instance has a dungeon map.
local function route(marker)
  return "instances/" .. marker.slug .. (marker.hasDungeonMap and "/map" or "")
end

local function open(marker)
  if ns.Main and ns.Main.Show then
    ns.Main.Show(route(marker))
    ns.BlizzardLinks.RaiseMain(map)
  end
end

local function newPin(canvas)
  local pin = CreateFrame("Button", nil, canvas)
  pin:SetSize(ns.MapPins.HIT, ns.MapPins.HIT)
  pin:RegisterForClicks("LeftButtonUp")
  pin.badge = MI.NewBadge(pin)
  pin.badge.box:SetPoint("CENTER")
  pin:SetScript("OnEnter", function(self)
    self.badge:Highlight(1)
    local title, lines = MML.TooltipLines(self.marker, L)
    ns.ShowTooltip(self, title, table.concat(lines, "\n"))
  end)
  pin:SetScript("OnLeave", function(self)
    self.badge:Highlight(0)
    ns.HideTooltip()
  end)
  pin:SetScript(
    "OnClick",
    ns.Wrap("wmi-click", function(self)
      open(self.marker)
    end)
  )
  return pin
end

-- The markers of the shown map with their place on it: the ones of the map itself, on a world or
-- continent map those of the child zones. A marker without a rectangle on the map is left out.
local function built()
  return MML.Build(ns.Data.Instances, ns.db and ns.db.mapMarkers)
end

local function filtered(markers)
  local s = ns.db and ns.db.settings or {}
  return MML.Filter(markers, {
    dungeons = s.mapMarkerDungeons,
    raids = s.mapMarkerRaids,
    faction = ns.PageKit.PlayerFaction(),
  })
end

local function placements(id, markers)
  local kind, list = WML.MapType(id), {}
  for _, m in ipairs(markers or filtered(built())) do
    local x, y = WML.Project(m.map, m.x, m.y, id, kind)
    if x then
      list[#list + 1] = { marker = m, x = x, y = y }
    end
  end
  return list
end

local function draw()
  if not (map and ns.ProtectedAllowed(map)) then
    return
  end
  local canvas = WML.Enabled("mapMarkersWorld") and map:IsShown() and WML.Canvas()
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
    pin.marker, pin.nx, pin.ny = it.marker, it.x, it.y
    pin.badge:Set(
      ICON[it.marker.kind],
      it.marker.faction,
      it.marker.map == id and SIZE_ZONE or SIZE_OVERVIEW,
      false,
      false,
      LETTER[it.marker.kind]
    )
    pin:SetFrameLevel(WML.CanvasLevel(canvas, "instances"))
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
    if pin.marker then
      WML.PlacePin(pin, canvas, scale)
    end
  end
end

WMI.Refresh = ns.Wrap("wmi-refresh", draw)

-- Number of shown pins.
function WMI.Count()
  local n = 0
  for _, pin in ipairs(pins) do
    if pin.marker then
      n = n + 1
    end
  end
  return n
end

-- State for /fg mapdiag: marker counts per stage, Wailing Caverns on the shown map, the first pins and the badge of
-- the first, all pins (pool), hooks.
function WMI.Debug()
  local id = WML.MapID()
  local all = built()
  local shown = filtered(all)
  local out = { map = id, built = #all, filtered = #shown, pins = {}, hooks = {}, count = WMI.Count(), pool = pins }
  out.placed = id and #placements(id, shown) or 0
  for _, m in ipairs(all) do
    if m.name and m.name.en == "Wailing Caverns" then
      local x, y = WML.Project(m.map, m.x, m.y, id, WML.MapType(id))
      out.wc = { map = m.map, x = m.x, y = m.y, px = x, py = y }
      break
    end
  end
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
  hooked[name] = WML.HookMethod("instances", name, fn) or hooked[name]
end

-- Runs after WorldMapLinks has attached: it owns the lookup of the map frame.
function WMI.Attach()
  if map then
    return
  end
  map = WML.Map()
  if not map then
    return
  end
  WML.HookScript("instances", "OnShow", WMI.Refresh)
  hookMethod("OnMapChanged", draw)
  hookMethod("OnCanvasScaleChanged", rescale)
  hookMethod("OnCanvasSizeChanged", rescale)
  WMI.Refresh()
end

ns.On("PLAYER_LOGIN", WMI.Attach)

-- Blizzard_WorldMap is load-on-demand on some clients.
ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_WorldMap" then
    WMI.Attach()
  end
end)
