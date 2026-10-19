-- Forever Guides inside Blizzard's world map (WorldMapFrame): a button that opens the Map & Route
-- page at the zone shown, a marker and route bar (WorldMapBar.lua) and pins for our markers on the
-- canvas. A marker is a waypoint of ns.Waypoints (source "map", pinned), like on the addon's own map.
--
-- Nothing is written into Blizzard tables except hooks: hooksecurefunc on OnMapChanged,
-- OnCanvasScaleChanged, OnCanvasSizeChanged and RefreshOverlayFrames, HookScript on the map, a click
-- handler (AddCanvasClickHandler, the way Blizzard's own data providers listen: it returns true only
-- for the clicks we use) and a cursor handler. Every frame we create is a child of the map under our
-- own name, anchored to Blizzard frames but never the other way round. The button sits at the right
-- edge of the canvas below the stacked tracking buttons: its spot is searched from the measured
-- rectangles of the overlay frames, so it never covers a neighbor whatever the layout (Mainline or
-- Camelot) puts there.
local _, ns = ...
local W, L, Theme, MM, MW = ns.W, ns.L, ns.Theme, ns.MapMarkers, ns.MapWorld
local WP, WL = ns.Waypoints, ns.WaypointLogic
local B = ns.BlizzardLinks

ns.AddLocale("enUS", {
  ["wm.button"] = "Forever Guides: Open map & route",
  ["wm.button.tip"] = "Opens Map & Route at this zone.\nRight click: menu.",
  ["wm.menu.barShow"] = "Show marker bar",
  ["wm.menu.barHide"] = "Hide marker bar",
  ["wm.noMarker"] = "No markers can be set on this map.",
  ["wm.bar.title"] = "Forever Guides",
  ["wm.bar.toggleTip"] = "Click: fold or unfold. Drag: move.",
  ["wm.corner.TOPLEFT"] = "Move to top left",
  ["wm.corner.TOPRIGHT"] = "Move to top right",
  ["wm.corner.BOTTOMLEFT"] = "Move to bottom left",
  ["wm.corner.BOTTOMRIGHT"] = "Move to bottom right",
  ["wm.tab"] = "Forever Guides: Map",
  ["wm.tab.tip"] = "Opens the map area of the addon.",
  ["wm.place"] = "Set marker",
  ["wm.place.stop"] = "Stop setting markers",
  ["wm.place.hint"] = "Click the map to set a marker.\nEsc or the button ends, {key:mapMarker} works anytime.",
  ["wm.count"] = "%d marker(s) on this map",
  ["wm.count.part"] = "%d marker(s) on this map, %d shown",
  ["wm.empty"] = "No markers on this map yet.",
  ["wm.swap"] = "Swap",
  ["wm.calc"] = "Calculate",
  ["wm.search"] = "Search a place",
  ["wm.noPlace"] = "No place found.",
  ["wm.noData"] = "The travel data is not available.",
  ["wm.route.show"] = "Show in addon",
  ["wm.route.more"] = "+%d more leg(s) in the addon",
  ["wm.set.heading"] = "Blizzard world map",
  ["wm.set.button"] = "Button in the world map",
  ["wm.set.bar"] = "Marker and route bar in the world map",
  ["wm.set.pins"] = "Show own markers in the world map",
})

ns.AddLocale("deDE", {
  ["wm.button"] = "Forever Guides: Karte & Route öffnen",
  ["wm.button.tip"] = "Öffnet Karte & Route bei dieser Zone.\nRechtsklick: Menü.",
  ["wm.menu.barShow"] = "Marker-Leiste zeigen",
  ["wm.menu.barHide"] = "Marker-Leiste ausblenden",
  ["wm.noMarker"] = "Auf dieser Karte können keine Marker gesetzt werden.",
  ["wm.bar.title"] = "Forever Guides",
  ["wm.bar.toggleTip"] = "Klick: auf- oder zuklappen. Ziehen: verschieben.",
  ["wm.corner.TOPLEFT"] = "Nach oben links",
  ["wm.corner.TOPRIGHT"] = "Nach oben rechts",
  ["wm.corner.BOTTOMLEFT"] = "Nach unten links",
  ["wm.corner.BOTTOMRIGHT"] = "Nach unten rechts",
  ["wm.tab"] = "Forever Guides: Karte",
  ["wm.tab.tip"] = "Öffnet den Karten-Bereich des Addons.",
  ["wm.place"] = "Marker setzen",
  ["wm.place.stop"] = "Marker setzen beenden",
  ["wm.place.hint"] = "Karte anklicken setzt einen Marker.\nEsc oder Knopf beendet, {key:mapMarker} geht immer.",
  ["wm.count"] = "%d Marker auf dieser Karte",
  ["wm.count.part"] = "%d Marker auf dieser Karte, %d angezeigt",
  ["wm.empty"] = "Auf dieser Karte gibt es noch keine Marker.",
  ["wm.swap"] = "Tauschen",
  ["wm.calc"] = "Berechnen",
  ["wm.search"] = "Ort suchen",
  ["wm.noPlace"] = "Kein Ort gefunden.",
  ["wm.noData"] = "Die Reisedaten sind nicht verfügbar.",
  ["wm.route.show"] = "Im Addon anzeigen",
  ["wm.route.more"] = "+%d weitere Etappe(n) im Addon",
  ["wm.set.heading"] = "Blizzard-Weltkarte",
  ["wm.set.button"] = "Button in der Weltkarte",
  ["wm.set.bar"] = "Marker und Routen-Leiste in der Weltkarte",
  ["wm.set.pins"] = "Eigene Marker in der Weltkarte anzeigen",
})

local WML = {}
ns.WorldMapLinks = WML

local LOGO = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local BUTTON = 28
local EDGE, GAP = 6, 4
local TAB_INSET, TAB_DROP = 4, 64 -- side tab: outside the right edge, under the close button
local RIGHT_ZONE = 0.25 -- overlays within this share of the canvas width at the right edge form the column
local FALLBACK_Y = 70 -- below Blizzard's two stacked tracking buttons, used when no rectangles are known
local PLACE_TRIES = 24
local LIFT_MIN, LIFT_ZONE = 30, 320 -- the bar keeps clear of the coordinates strip and the left overlays
local COSMIC_MAP, MAP_COSMIC = 946, 0
local WORLD_AND_CONTINENT = { [1] = true, [2] = true } -- Enum.UIMapType: markers of child maps show here
local LEVEL_PIN, LEVEL_UI = 1500, 2000 -- above Blizzard's pins, then above ours
local LEVEL_CAP = 9990
local PIN_RING = 4
local CURSOR = "MAP_PIN_CURSOR"
local HANDLER_PRIORITY = 100
local NEIGHBORS = { "WorldMapTrackingOptionsButton", "WorldMapTrackingPinButton", "SidePanelToggle", "NavBar" }
local MENU_W, MENU_ROW = 214, 26

local map, attached
local button, tab, overlay, bar, keys
local pins = {}
local placing = false
local fieldCtl, markerMenu, buttonMenu
local hooked = {}

-- Blizzard access ----------------------------------------------------------------------

local function worldMap()
  local frame = rawget(_G, "WorldMapFrame")
  if type(frame) == "table" and type(frame.HookScript) == "function" then
    return frame
  end
end

local function field(object, name)
  local ok, value = pcall(function()
    return object[name]
  end)
  return ok and value or nil
end

-- Method call that never raises; up to two results.
local function call(object, method, ...)
  local fn = type(object) == "table" and field(object, method)
  if type(fn) ~= "function" then
    return nil
  end
  local r = { pcall(fn, object, ...) }
  if r[1] then
    return r[2], r[3]
  end
end

-- C_Map.<name>(...) that never raises; up to four results.
local function capi(name, ...)
  local fn = C_Map and C_Map[name]
  if type(fn) ~= "function" then
    return nil
  end
  local r = { pcall(fn, ...) }
  if r[1] then
    return r[2], r[3], r[4], r[5]
  end
end

local function rectOf(frame)
  local ok, l, r, t, b = pcall(function()
    return frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  end)
  if ok and WL.readable(l) and WL.readable(r) and WL.readable(t) and WL.readable(b) then
    return { l = l, r = r, t = t, b = b }
  end
end

local function isShown(frame)
  local ok, value = pcall(frame.IsShown, frame)
  return ok and value == true
end

local function level(extra)
  local base = call(map, "GetFrameLevel")
  return math.min((WL.readable(base) and base or 1) + extra, LEVEL_CAP)
end

-- Frame level of our controls on the map: above the canvas and Blizzard's overlays.
function WML.UILevel()
  return level(LEVEL_UI)
end

local function enabled(key)
  local s = ns.db and ns.db.settings
  return not s or s[key] ~= false
end

-- The map shown in Blizzard's window (uiMapID), nil when the client reports none.
function WML.MapID()
  local id = call(map, "GetMapID")
  return WL.readable(id) and id > 0 and id or nil
end

local function mapType(id)
  local info = capi("GetMapInfo", id)
  return type(info) == "table" and info.mapType or nil
end

local function isCosmic(id)
  return id == COSMIC_MAP or mapType(id) == MAP_COSMIC
end

function WML.Container()
  return field(map, "ScrollContainer") or map
end

-- Placement ----------------------------------------------------------------------------

local function overlaps(a, b, margin)
  return a.l < b.r + margin and b.l < a.r + margin and a.b < b.t + margin and b.b < a.t + margin
end

-- Rectangles of the Blizzard frames that sit on the canvas: the tracking buttons, the side panel
-- toggle and every shown overlay frame. Frames that span most of the canvas are no neighbors.
local function obstacles(c)
  local list, seen = {}, {}
  local function add(frame)
    if type(frame) ~= "table" or seen[frame] or frame == button or frame == bar then
      return
    end
    seen[frame] = true
    if not isShown(frame) then
      return
    end
    local r = rectOf(frame)
    if r and overlaps(r, c, 0) and (r.r - r.l) < 0.6 * (c.r - c.l) and (r.t - r.b) < 0.6 * (c.t - c.b) then
      list[#list + 1] = r
    end
  end
  for _, name in ipairs(NEIGHBORS) do
    add(field(map, name))
  end
  local overlays = field(map, "overlayFrames")
  if type(overlays) == "table" then
    for i = 1, #overlays do
      add(overlays[i])
    end
  end
  return list
end

-- Moves the button to the first free spot at the right edge, top down.
function WML.PlaceButton()
  if not (map and button) then
    return
  end
  local container = WML.Container()
  local c = rectOf(container)
  local y = FALLBACK_Y
  if c then
    y = EDGE
    local right, list = c.r - EDGE, obstacles(c)
    for _ = 1, PLACE_TRIES do
      local spot = { l = right - BUTTON, r = right, t = c.t - y, b = c.t - y - BUTTON }
      local hit
      for _, o in ipairs(list) do
        if overlaps(spot, o, GAP / 2) then
          hit = o
          break
        end
      end
      if not hit then
        break
      end
      y = c.t - hit.b + GAP
    end
    if y + BUTTON > (c.t - c.b) - EDGE then
      y = FALLBACK_Y
    end
  end
  button:ClearAllPoints()
  button:SetPoint("TOPRIGHT", container, "TOPRIGHT", -EDGE, -y)
end

-- Room for the bar at the lower left of the canvas: how far the busy overlays reach up from the
-- bottom edge, and the size of the canvas. Returns lift, width, height.
function WML.BarSpace()
  local c = rectOf(WML.Container())
  if not c then
    return LIFT_MIN, 800, 500
  end
  local width, height = c.r - c.l, c.t - c.b
  local lift = LIFT_MIN
  for _, o in ipairs(obstacles(c)) do
    if o.l < c.l + LIFT_ZONE and o.b - c.b < height / 3 then
      lift = math.max(lift, o.t - c.b + GAP)
    end
  end
  return math.min(lift, height / 3), width, height
end

function WML.ContainerRect()
  return rectOf(WML.Container())
end

-- How far the busy column at the right edge of the canvas reaches inwards: the tracking buttons,
-- the side panel toggle and our own button. The bar keeps clear of it.
function WML.RightClear()
  local c = WML.ContainerRect()
  if not c then
    return BUTTON + 2 * EDGE
  end
  local width, clear = c.r - c.l, EDGE
  local function take(o)
    if o.r > c.r - RIGHT_ZONE * width and o.l > c.l + width / 2 then
      clear = math.max(clear, c.r - o.l)
    end
  end
  for _, o in ipairs(obstacles(c)) do
    take(o)
  end
  local mine = button and isShown(button) and rectOf(button)
  if mine then
    take(mine)
  end
  return clear
end

function WML.Relayout()
  if not map or not ns.ProtectedAllowed(map) then
    return
  end
  if button and button:IsShown() then
    WML.PlaceButton()
  end
  if bar and bar:IsShown() then
    bar:Layout()
  end
end

-- Cursor and name field ----------------------------------------------------------------

local function ensureOverlay()
  if overlay then
    return overlay
  end
  overlay = CreateFrame("Frame", "ForeverGuidesWorldMapOverlay", map)
  overlay:SetAllPoints(WML.Container())
  overlay:SetFrameLevel(level(LEVEL_UI + 100))
  keys = CreateFrame("Frame", nil, overlay)
  keys:EnableKeyboard(true)
  keys:SetScript("OnKeyDown", function(self, key)
    local handled = key == "ESCAPE"
    if handled then
      WML.SetPlacing(false)
    end
    ns.PropagateKeys(self, not handled)
  end)
  keys:Hide()
  return overlay
end

-- Opens the name field at the cursor (the click that led here), inside the canvas.
local function openField(spec, text)
  ensureOverlay()
  fieldCtl = fieldCtl or MM.NewField(overlay)
  local px, py = 8, 8
  local fx, fy = MM.CursorFraction(overlay)
  if fx then
    px, py = fx * overlay:GetWidth() + 6, fy * overlay:GetHeight() + 6
  end
  fieldCtl.Open(spec, text, px, py)
end

function WML.Placing()
  return placing
end

function WML.SetPlacing(on)
  on = on == true and map ~= nil and enabled("worldMapPanel")
  if on == placing then
    return
  end
  placing = on
  if on then
    ensureOverlay()
  end
  if keys then
    keys:SetShown(on)
  end
  ns.Emit("FG_WORLDMAP_PLACING", on)
end

local function placeMarker(nx, ny)
  local id = WML.MapID()
  if not id then
    return
  end
  if isCosmic(id) then
    ns.Notify(L["wm.noMarker"], "info")
    return
  end
  if #WP.List() >= WL.MAX then
    ns.Notify(string.format(L["wp.full"], WL.MAX), "warning")
    return
  end
  if not (WL.readable(nx) and WL.readable(ny)) then
    nx, ny = call(map, "GetNormalizedCursorPosition")
  end
  if not (WL.readable(nx) and WL.readable(ny)) then
    return
  end
  openField({ kind = "new", map = id, x = nx, y = ny }, MM.DefaultName(WP.List()))
end

-- Handler of the canvas: true only for the clicks we use (marker mode or the marker key held), so Blizzard's
-- own click handling (navigating into a zone) stays untouched for every other click.
local function onCanvasClick(_, mouse, nx, ny)
  if mouse ~= "LeftButton" or not enabled("worldMapPanel") then
    return false
  end
  if not (placing or ns.Keys.Matches("mapMarker")) then
    return false
  end
  placeMarker(nx, ny)
  return true
end

-- Marker menu ------------------------------------------------------------------------------

local function activate(wp)
  if WP.Activate(wp.id) then
    ns.Notify(string.format(L["wp.activated"], wp.title), "info")
  end
end
WML.Activate = activate

local function markerEntries()
  return {
    {
      id = "rename",
      key = "map.marker.rename",
      run = function(wp)
        openField({ kind = "rename", id = wp.id }, wp.title)
      end,
    },
    {
      id = "pin",
      keyFor = function(wp)
        return wp.pinned and "map.marker.unpin" or "map.marker.pin"
      end,
      run = function(wp)
        WP.SetPinned(wp.id, not wp.pinned)
      end,
    },
    { id = "arrow", key = "map.marker.arrow", run = activate },
    {
      id = "remove",
      key = "map.marker.remove",
      run = function(wp)
        WP.Remove(wp.id)
      end,
    },
  }
end

-- Rename, color, pin and remove, shared by the pins and the rows of the bar.
function WML.OpenMarkerMenu(wp, anchor)
  markerMenu = markerMenu or MM.NewMenu(markerEntries())
  markerMenu.Open(wp, anchor)
end

-- Pins -----------------------------------------------------------------------------------------

local function tipFor(wp)
  local lines = { WP.MapName(wp.map), string.format(L["map.marker.pos"], WL.coordText(wp.x, wp.y)) }
  local yards = WP.Distance(wp)
  if yards then
    lines[#lines + 1] = string.format(L["map.marker.dist"], WL.formatDistance(yards, ns.GetActiveLocale()))
  end
  if wp.note ~= "" then
    lines[#lines + 1] = wp.note
  end
  lines[#lines + 1] = Theme.hexText("textMuted", L["map.marker.hint"])
  return table.concat(lines, "\n")
end

local function newPin(canvas)
  local size = MM.PIN
  local pin = CreateFrame("Button", nil, canvas)
  pin:SetSize(size, size)
  pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  pin.ring = pin:CreateTexture(nil, "BACKGROUND")
  pin.ring:SetTexture(DISC)
  pin.ring:SetPoint("CENTER")
  pin.ring:SetSize(size + 2 * PIN_RING, size + 2 * PIN_RING)
  pin.edge = pin:CreateTexture(nil, "BORDER")
  pin.edge:SetTexture(DISC)
  pin.edge:SetPoint("CENTER")
  pin.edge:SetSize(size + 2, size + 2)
  pin.fill = pin:CreateTexture(nil, "ARTWORK")
  pin.fill:SetTexture(DISC)
  pin.fill:SetAllPoints()
  pin:SetScript("OnEnter", function(self)
    local wp = self.wpId and WP.Get(self.wpId)
    if wp then
      ns.ShowTooltip(self, wp.title, tipFor(wp))
    end
  end)
  pin:SetScript("OnLeave", ns.HideTooltip)
  -- The pin is a button of its own: the click ends here and never reaches the map below.
  pin:SetScript(
    "OnClick",
    ns.Wrap("wm-pin", function(self, mouse)
      local wp = self.wpId and WP.Get(self.wpId)
      if not wp then
        return
      end
      if mouse == "RightButton" then
        WML.OpenMarkerMenu(wp, self)
      else
        activate(wp)
      end
    end)
  )
  ns.Bind(pin, function(self)
    if self.colorName then
      self.fill:SetVertexColor(Theme.color(self.colorName))
    end
    self.edge:SetVertexColor(Theme.color("bg", 0.9))
    self.ring:SetVertexColor(Theme.color("text"))
  end)
  return pin
end

-- Position of a waypoint on the shown map: its own map, or for pinned markers on a world or
-- continent map the place of their zone inside it.
local function project(wp, id, kind)
  if wp.map == id then
    return wp.x, wp.y
  end
  if wp.pinned and WORLD_AND_CONTINENT[kind] then
    local rect = MW.Rect(capi("GetMapRectOnMap", wp.map, id))
    if rect then
      return MW.Place(rect, wp.x, wp.y)
    end
  end
end

-- Pins keep their size while the canvas zooms: scale 1 / canvas scale, offsets in the pin's units.
local function placePin(pin, canvas, scale)
  local s = 1 / scale
  pin:SetScale(s)
  pin:ClearAllPoints()
  pin:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * pin.nx / s, -canvas:GetHeight() * pin.ny / s)
end

local function canvasScale()
  local scale = call(map, "GetCanvasScale")
  return WL.readable(scale) and scale > 0 and scale or 1
end

local function hidePins(from)
  for i = from or 1, #pins do
    pins[i].wpId = nil
    pins[i]:Hide()
  end
end

-- Zoom and canvas size changes: only position and scale, no new data.
function WML.RescalePins()
  local canvas = call(map, "GetCanvas")
  if not canvas then
    return
  end
  local scale = canvasScale()
  for _, pin in ipairs(pins) do
    if pin.wpId then
      placePin(pin, canvas, scale)
    end
  end
end

function WML.RefreshPins()
  if map and not ns.ProtectedAllowed(map) then
    return
  end
  local canvas = map and enabled("worldMapPins") and isShown(map) and call(map, "GetCanvas")
  local id = canvas and WML.MapID()
  if not id then
    hidePins()
    return
  end
  local items, active, kind = {}, WP.data().active, mapType(id)
  for _, wp in ipairs(WP.List()) do
    local nx, ny = project(wp, id, kind)
    if nx then
      items[#items + 1] = { wp = wp, x = nx, y = ny, active = wp.id == active }
    end
  end
  MM.SortPins(items)
  local base, scale = canvas:GetFrameLevel() + LEVEL_PIN, canvasScale()
  for i, it in ipairs(items) do
    local pin = pins[i]
    if not pin then
      pin = newPin(canvas)
      pins[i] = pin
    end
    pin.wpId, pin.colorName, pin.nx, pin.ny = it.wp.id, it.wp.color, it.x, it.y
    pin:SetFrameLevel(math.min(base + #items - i, LEVEL_CAP))
    pin.fill:SetVertexColor(Theme.color(it.wp.color))
    pin.ring:SetShown(it.active)
    placePin(pin, canvas, scale)
    pin:Show()
  end
  hidePins(#items + 1)
end

-- Button and menu ---------------------------------------------------------------------------

local function openPage()
  if ns.MapRequest then
    ns.MapRequest.Open({ map = WML.MapID() })
    B.RaiseMain(map)
  end
end

function WML.SetBarShown(on)
  ns.Store.set("settings.worldMapPanel", on == true)
  WML.Apply()
end

local function moveFocus(list, step)
  local index = 0
  for i, b in ipairs(list) do
    if ns.Focus.current == b then
      index = i
    end
  end
  if #list == 0 then
    return
  end
  index = index == 0 and (step > 0 and 1 or #list) or (index - 1 + step) % #list + 1
  ns.Focus.set(list[index])
end

local function buildButtonMenu()
  local layer = ns.Desktop.Layer
  local p = layer.newPopup("surface2")
  local items = {
    {
      id = "bar",
      run = function()
        WML.SetBarShown(not enabled("worldMapPanel"))
      end,
    },
    {
      id = "list",
      key = "map.marker.window",
      run = function()
        ns.WaypointList.Open()
      end,
    },
    {
      id = "settings",
      key = "page.settings",
      run = function()
        ns.Main.Show("settings")
        B.RaiseMain(map)
      end,
    },
  }
  p.buttons, p.byId = {}, {}
  for i, item in ipairs(items) do
    local b = W.Button(p, {
      key = item.key or "wm.menu.barShow",
      variant = "ghost",
      width = MENU_W - 4,
      height = MENU_ROW,
      onClick = function()
        layer.close("select")
        item.run()
      end,
    })
    b.label:SetJustifyH("LEFT")
    b:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -2 - (i - 1) * MENU_ROW)
    p.buttons[i], p.byId[item.id] = b, b
  end
  p:SetSize(MENU_W, #items * MENU_ROW + 4)
  p:EnableKeyboard(true)
  p:SetScript("OnKeyDown", function(self, key)
    local handled = true
    if key == "ESCAPE" then
      layer.close("escape")
    elseif key == "UP" or key == "DOWN" then
      moveFocus(self.buttons, key == "DOWN" and 1 or -1)
    elseif key == "ENTER" or key == "SPACE" then
      ns.Focus.activate()
    else
      handled = false
    end
    ns.PropagateKeys(self, not handled)
  end)
  return p
end

local function openButtonMenu()
  if not (ns.Desktop and ns.Desktop.Layer and button) then
    return
  end
  buttonMenu = buttonMenu or buildButtonMenu()
  W.SetText(buttonMenu.byId.bar.label, enabled("worldMapPanel") and "wm.menu.barHide" or "wm.menu.barShow")
  local layer = ns.Desktop.Layer
  layer.open({
    frames = { buttonMenu },
    owner = button,
    move = function(step)
      moveFocus(buttonMenu.buttons, step)
    end,
  })
  layer.place(buttonMenu, button, "TOPRIGHT", "TOPLEFT", -2, 0)
  buttonMenu:Show()
  ns.Focus.set(buttonMenu.buttons[1])
end

local function ensureButton()
  if button then
    return
  end
  button = W.Action(map, {
    texture = LOGO,
    size = BUTTON,
    tooltip = "wm.button",
    tooltipText = "wm.button.tip",
    onClick = function(_, mouse)
      if mouse == "RightButton" then
        openButtonMenu()
      else
        openPage()
      end
    end,
  })
  B.LeaveFocusRing(button)
  button:SetFrameLevel(level(LEVEL_UI))
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button.icon:ClearAllPoints()
  button.icon:SetPoint("TOPLEFT", 2, -2)
  button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  button.icon:SetTexCoord(0, 1, 0, 1)
  W.Fill(button, "bg", 0.85)
  W.Border(button, "accentDim", 1)
end

local function ensureTab()
  if tab then
    return
  end
  tab = B.CreateSideTab(map, {
    key = "wm.tab",
    tip = "wm.tab.tip",
    onClick = openPage,
    point = "TOPLEFT",
    rel = map,
    relPoint = "TOPRIGHT",
    x = TAB_INSET,
    y = -TAB_DROP,
  })
end

-- The frames and the name field built so far, for the tests.
function WML.Parts()
  return { button = button, tab = tab, bar = bar, overlay = overlay, keys = keys, pins = pins, field = fieldCtl }
end

-- Attach and settings -----------------------------------------------------------------

-- Applies the three settings: builds what is switched on and hides what is switched off.
function WML.Apply()
  if not map or not ns.ProtectedAllowed(map) then
    return
  end
  if enabled("worldMapButton") then
    ensureButton()
    ensureTab()
    button:Show()
    tab:Show()
    WML.PlaceButton()
  else
    if button then
      button:Hide()
    end
    if tab then
      tab:Hide()
    end
  end
  if enabled("worldMapPanel") then
    if not bar then
      bar = ns.WorldMapBar.Create(map)
      WML.bar = bar
    end
    bar:Show()
    bar:Layout()
  elseif bar then
    bar:Hide()
    WML.SetPlacing(false)
  end
  WML.RefreshPins()
end

local function hookMethod(name, fn)
  if hooked[name] or type(hooksecurefunc) ~= "function" or type(field(map, name)) ~= "function" then
    return
  end
  hooked[name] = true
  pcall(hooksecurefunc, map, name, function()
    ns.Safe("wm-" .. name, fn)
  end)
end

local function onMapChanged()
  WML.RefreshPins()
  if bar and bar:IsShown() then
    bar:Refresh()
  end
end

function WML.OnShow()
  WML.Relayout()
  onMapChanged()
end

function WML.OnHide()
  WML.SetPlacing(false)
  if fieldCtl then
    fieldCtl.Close()
  end
end

function WML.Attach()
  if attached then
    return true
  end
  map = worldMap()
  if not map then
    return false
  end
  attached = true
  pcall(map.HookScript, map, "OnShow", ns.Wrap("wm-show", WML.OnShow))
  pcall(map.HookScript, map, "OnHide", ns.Wrap("wm-hide", WML.OnHide))
  pcall(
    map.HookScript,
    map,
    "OnSizeChanged",
    ns.Wrap("wm-size", function()
      ns.Debounce("wm-relayout", 0.05, WML.Relayout)
    end)
  )
  hookMethod("OnMapChanged", onMapChanged)
  hookMethod("OnCanvasScaleChanged", WML.RescalePins)
  hookMethod("OnCanvasSizeChanged", WML.RescalePins)
  hookMethod("RefreshOverlayFrames", WML.Relayout)
  if type(field(map, "AddCanvasClickHandler")) == "function" then
    pcall(map.AddCanvasClickHandler, map, ns.Wrap("wm-click", onCanvasClick), HANDLER_PRIORITY)
  end
  if type(field(map, "AddCursorHandler")) == "function" then
    pcall(map.AddCursorHandler, map, function()
      if placing then
        return CURSOR
      end
    end, HANDLER_PRIORITY)
  end
  WML.Apply()
  return true
end

ns.On("PLAYER_LOGIN", function()
  WML.Attach()
end)

-- Blizzard_WorldMap is load-on-demand on some clients.
ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_WorldMap" then
    WML.Attach()
  end
end)

ns.On("FG_WAYPOINTS_CHANGED", function()
  if attached then
    WML.RefreshPins()
  end
end)
