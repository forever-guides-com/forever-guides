-- Forever Guides inside Blizzard's world map (WorldMapFrame): a button that opens the Map & Route
-- page at the zone shown, a marker and route bar (WorldMapBar.lua) and pins for our markers on the
-- canvas. A marker is a waypoint of ns.Waypoints (source "map", pinned), like on the addon's own map.
--
-- Nothing is written into Blizzard tables except hooks: hooksecurefunc on OnMapChanged,
-- OnCanvasScaleChanged, OnCanvasSizeChanged and RefreshOverlayFrames, HookScript on the map, a click
-- handler (AddCanvasClickHandler, the way Blizzard's own data providers listen: it returns true only
-- for the clicks we use) and a cursor handler, both added after combat and idle in combat. A hook
-- (WML.HookMethod, WML.HookScript) only queues its work for the next frame: Blizzard builds its pins
-- and quest entries inside the hooked call, and code of ours running there would taint that path. Every
-- frame we create is a child of the map under our own name, anchored to Blizzard frames but never the
-- other way round. The button sits at the right
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
  ["wm.menu.here"] = "Set waypoint here",
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
  ["wm.place.hint"] = "Click the map to set a marker.\nEsc or the button ends the mode, {key:mapMarker} always works.",
  ["wm.count"] = "%d marker(s) on this map",
  ["wm.count.part"] = "%d marker(s) on this map, %d shown",
  ["wm.empty"] = "No markers on this map yet.",
  ["wm.swap"] = "Swap",
  ["wm.set.heading"] = "Blizzard world map",
  ["wm.set.button"] = "Button in the world map",
  ["wm.set.bar"] = "Marker and route bar in the world map",
  ["wm.set.pins"] = "Show own markers in the world map",
  ["wm.set.rightClick"] = "Right click sets a waypoint (otherwise {mod:mapMenu} + right click)",
  ["wm.tip.tab.markers"] = "Your markers on this map: set new ones and pick them from the list.",
  ["wm.tip.tab.flights"] = "Lists the flight points nearest to you with their distance. A click sets a waypoint.",
  ["wm.tip.tab.gather"] = "Shows ore and herb spots on the map and the explored look of the map.",
  ["wm.place.tip"] = "Switches clicks on the map to setting markers. Click the map to set one, click here again to stop.",
  ["wm.swap.tip"] = "Swaps start and destination.",
})

ns.AddLocale("deDE", {
  ["wm.button"] = "Forever Guides: Karte & Route öffnen",
  ["wm.button.tip"] = "Öffnet Karte & Route bei dieser Zone.\nRechtsklick: Menü.",
  ["wm.menu.barShow"] = "Markerleiste anzeigen",
  ["wm.menu.barHide"] = "Markerleiste ausblenden",
  ["wm.noMarker"] = "Auf dieser Karte können keine Marker gesetzt werden.",
  ["wm.menu.here"] = "Wegpunkt hier setzen",
  ["wm.bar.title"] = "Forever Guides",
  ["wm.bar.toggleTip"] = "Klick: auf- oder zuklappen. Ziehen: verschieben.",
  ["wm.corner.TOPLEFT"] = "Nach oben links",
  ["wm.corner.TOPRIGHT"] = "Nach oben rechts",
  ["wm.corner.BOTTOMLEFT"] = "Nach unten links",
  ["wm.corner.BOTTOMRIGHT"] = "Nach unten rechts",
  ["wm.tab"] = "Forever Guides: Karte",
  ["wm.tab.tip"] = "Öffnet den Kartenbereich des Addons.",
  ["wm.place"] = "Marker setzen",
  ["wm.place.stop"] = "Marker setzen beenden",
  ["wm.place.hint"] = "Klicke auf die Karte, um einen Marker zu setzen.\nEsc oder Knopf beendet den Modus, {key:mapMarker} geht immer.",
  ["wm.count"] = "%d Marker auf dieser Karte",
  ["wm.count.part"] = "%d Marker auf dieser Karte, %d angezeigt",
  ["wm.empty"] = "Auf dieser Karte gibt es noch keine Marker.",
  ["wm.swap"] = "Tauschen",
  ["wm.set.heading"] = "Blizzard-Weltkarte",
  ["wm.set.button"] = "Knopf in der Weltkarte",
  ["wm.set.bar"] = "Marker- und Routenleiste in der Weltkarte",
  ["wm.set.pins"] = "Eigene Marker in der Weltkarte anzeigen",
  ["wm.set.rightClick"] = "Rechtsklick setzt Wegpunkt (sonst {mod:mapMenu} + Rechtsklick)",
  ["wm.tip.tab.markers"] = "Deine Marker auf dieser Karte: neue setzen und aus der Liste wählen.",
  ["wm.tip.tab.flights"] = "Listet die nächsten Flugpunkte mit ihrer Entfernung. Ein Klick setzt einen Wegpunkt.",
  ["wm.tip.tab.gather"] = "Zeigt Fundorte von Erzen und Kräutern auf der Karte und die erkundete Darstellung der Karte.",
  ["wm.place.tip"] = "Schaltet Klicks auf die Karte auf das Setzen von Markern um. Ein Klick auf die Karte setzt einen Marker, ein erneuter Klick hier beendet den Modus.",
  ["wm.swap.tip"] = "Tauscht Start und Ziel.",
})

local WML = {}
ns.WorldMapLinks = WML

local LOGO = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local BUTTON = 31
local EDGE, GAP = 6, 4
local TAB_INSET, TAB_DROP = 4, 64 -- side tab: outside the right edge, under the close button
local RIGHT_ZONE = 0.25 -- overlays within this share of the canvas width at the right edge form the column
local FALLBACK_Y = 70 -- below Blizzard's two stacked tracking buttons, used when no rectangles are known
local PLACE_TRIES = 24
local LIFT_MIN, LIFT_ZONE = 30, 320 -- the bar keeps clear of the coordinates strip and the left overlays
local COSMIC_MAP, MAP_COSMIC = 946, 0
local WORLD_AND_CONTINENT = { [1] = true, [2] = true } -- Enum.UIMapType: markers of child maps show here
local LEVEL_CAP = 9990
-- Frame levels of everything we draw on Blizzard's world map, bottom to top. All but ui count from the canvas,
-- ui from the map. Measured on the canvas of the Forever client (/fg mapdiag lists them): MapExplorationPin 2002
-- (opaque, full canvas), FogOfWarPin 2006, QuestBlobPin 2007, ScenarioBlobPin 2008, MapHighlightPin 2009,
-- QuestPin 2740 to 2758, GroupMembersPin 2920.
-- reveal stays far below the client's explored pieces on purpose: it only fills what the client has not drawn,
-- and a piece drawn over it is the same picture. The pins lie over the exploration and the highlight (which
-- would take their mouse and tooltips) and under the quest pins: spots, zone level labels, then zone transition arrows (they sit
-- on the zone edge, flight points and instance markers win where they meet), flight points, instance markers,
-- guild members, rare enemies (their card must not hide under other markers), and the waypoint pins on top, which count up per entry (room for about 500 before the quest
-- pins). The controls clear the client's quest pins, stay under the dungeon panel (3000) and keep room for
-- the overlay at ui + 100.
local LEVELS = {
  reveal = 1,
  spots = 2020,
  levels = 2080,
  arrows = 2090,
  flights = 2100,
  instances = 2110,
  guild = 2150,
  rares = 2170,
  waypoints = 2200,
  ui = 2850,
}
WML.LEVELS = LEVELS
WML.LEVEL_CAP = LEVEL_CAP
local PIN_RING = 4
local CURSOR = "MAP_PIN_CURSOR"
local HANDLER_PRIORITY = 100
local NEIGHBORS = { "WorldMapTrackingOptionsButton", "WorldMapTrackingPinButton", "SidePanelToggle", "NavBar" }
local MENU_W, MENU_ROW = 214, 26

local map, attached
local button, tab, overlay, bar, keys
local tabHost, tabRise = nil, 0 -- frame the side tab hangs on instead of the map (WML.SetTabHost)
local pins = {}
local placing = false
local fieldCtl, markerMenu, buttonMenu
local hooked = {}
local handlersAdded = false

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
WML.CApi = capi

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
  return level(LEVELS.ui)
end

-- Lifts a control of ours (button, bar) above the parts of Blizzard's window, measured: its border frame and
-- title strip can lie above a level that is only "map level plus a constant".
function WML.Lift(frame)
  if map and frame then
    ns.Layer.Panel(frame, map, WML.UILevel(), field(map, "ScrollContainer"))
  end
end

-- Frame level of the layer `key` of WML.LEVELS on the canvas. A map add-on that stitches its own art over the
-- canvas moves every layer above that art (ns.StitchedMapCompat), else the layers count from the canvas.
function WML.CanvasLevel(canvas, key)
  local compat = ns.StitchedMapCompat
  local lifted = compat and compat.Level(key)
  return lifted or math.min(canvas:GetFrameLevel() + LEVELS[key], LEVEL_CAP)
end

-- Frames that get their level once (not on every paint), kept so a change of the art below can lift them again.
local tracked = setmetatable({}, { __mode = "k" })

local function applyLevel(frame, spec)
  frame:SetFrameLevel(WML.CanvasLevel(spec.canvas, spec.key) + spec.extra)
end

-- Sets the level of `frame` to layer `key` (plus `extra`) and keeps it up to date with WML.ReapplyLevels.
function WML.TrackLevel(frame, canvas, key, extra)
  local spec = { canvas = canvas, key = key, extra = extra or 0 }
  tracked[frame] = spec
  applyLevel(frame, spec)
end

function WML.ReapplyLevels()
  for frame, spec in pairs(tracked) do
    applyLevel(frame, spec)
  end
end

local function enabled(key)
  local s = ns.db and ns.db.settings
  return not s or s[key] ~= false
end
WML.Enabled = enabled

-- Blizzard's world map frame once attached, else nil.
function WML.Map()
  return map
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
WML.MapType = mapType

local function isCosmic(id)
  return id == COSMIC_MAP or mapType(id) == MAP_COSMIC
end

function WML.Container()
  return field(map, "ScrollContainer") or map
end

-- The canvas the markers sit on, nil when the client has none.
function WML.Canvas()
  return call(map, "GetCanvas")
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
  overlay:SetFrameLevel(level(LEVELS.ui + 100))
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

-- "Set waypoint here" popup at the cursor. The waypoint is added directly (no name field, so nothing is
-- parented to the map and the menu works in combat); rename it later from its own menu.
local hereMenu, hereAnchor, herePoint

local function setHere()
  local p = herePoint
  herePoint = nil
  if not p or #WP.List() >= WL.MAX then
    if p then
      ns.Notify(string.format(L["wp.full"], WL.MAX), "warning")
    end
    return
  end
  local wp, status =
    WP.Add({ map = p.map, x = p.x, y = p.y, title = MM.DefaultName(WP.List()), source = "map", pinned = true })
  if wp then
    WP.Activate(wp.id)
    local key = status == "duplicate" and "wp.duplicate" or "wp.set"
    ns.Notify(
      status == "duplicate" and string.format(L[key], wp.title)
        or string.format(L[key], wp.title, WL.coordText(wp.x, wp.y), WP.MapName(wp.map)),
      status == "duplicate" and "info" or "success"
    )
  end
end

local function buildHereMenu()
  local layer = ns.Desktop.Layer
  local p = layer.newPopup("surface2")
  local b = W.Button(p, {
    key = "wm.menu.here",
    variant = "ghost",
    width = MENU_W - 4,
    height = MENU_ROW,
    onClick = function()
      layer.close("select")
      setHere()
    end,
  })
  b.label:SetJustifyH("LEFT")
  b:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -2)
  p.buttons = { b }
  p:SetSize(MENU_W, MENU_ROW + 4)
  p:EnableKeyboard(true)
  p:SetScript("OnKeyDown", function(self, key)
    local handled = true
    if key == "ESCAPE" then
      layer.close("escape")
    elseif key == "ENTER" or key == "SPACE" then
      ns.Focus.activate()
    else
      handled = false
    end
    ns.PropagateKeys(self, not handled)
  end)
  return p
end

local function openHereMenu(id, nx, ny)
  if not (ns.Desktop and ns.Desktop.Layer) then
    return
  end
  local layer = ns.Desktop.Layer
  hereMenu = hereMenu or buildHereMenu()
  if not hereAnchor then
    hereAnchor = CreateFrame("Frame", nil, UIParent)
    hereAnchor:SetSize(1, 1)
  end
  local cx, cy = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  hereAnchor:ClearAllPoints()
  hereAnchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / s, cy / s)
  herePoint = { map = id, x = nx, y = ny }
  layer.open({ frames = { hereMenu }, owner = hereAnchor, move = function() end })
  layer.place(hereMenu, hereAnchor, "TOPLEFT", "BOTTOMLEFT", 0, 0)
  hereMenu:Show()
  ns.Focus.set(hereMenu.buttons[1])
end

-- Right click on an empty spot: the menu opens with the setting on, else with Alt held, so the client's own
-- right click (zoom out) keeps working by default.
local function onRightClick(nx, ny)
  local s = ns.db and ns.db.settings
  if not (s and s.worldMapRightClick == true) and not ns.Keys.Matches("mapMenu") then
    return false
  end
  local id = WML.MapID()
  if not id then
    return false
  end
  if isCosmic(id) then
    ns.Notify(L["wm.noMarker"], "info")
    return true
  end
  if not (WL.readable(nx) and WL.readable(ny)) then
    nx, ny = call(map, "GetNormalizedCursorPosition")
  end
  if not (WL.readable(nx) and WL.readable(ny)) then
    return false
  end
  openHereMenu(id, nx, ny)
  return true
end

-- The game's own pin of the user waypoint passes right clicks through to the canvas, where they would zoom
-- out. When the cursor is on that pin and a waypoint of ours stands behind it, our marker menu opens instead.
local USER_PIN = "WaypointLocationPinTemplate"

local function userPinUnderCursor()
  if type(field(map, "EnumeratePinsByTemplate")) ~= "function" then
    return nil
  end
  local ok, iter, state, first = pcall(map.EnumeratePinsByTemplate, map, USER_PIN)
  if not (ok and type(iter) == "function") then
    return nil
  end
  local walked, found = pcall(function()
    for a, b in iter, state, first do
      local pin = type(a) == "table" and a or b
      if type(pin) == "table" and call(pin, "IsShown") and call(pin, "IsMouseOver") then
        return pin
      end
    end
  end)
  return walked and found or nil
end

local function onUserPinRightClick()
  local pin = userPinUnderCursor()
  if not pin then
    return false
  end
  local id, x, y = WP.UserWaypoint()
  local wp = id and WL.findDuplicate(WP.List(), id, x, y)
  if not wp then
    return false
  end
  WML.OpenMarkerMenu(wp, pin)
  return true
end

-- Handler of the canvas: true only for the clicks we use (marker mode or the marker key held, the right-click
-- menu), so Blizzard's own click handling (navigating into a zone, zooming out) stays untouched for every
-- other click.
local clickUses = {}

-- Other modules (route planning) use clicks of the same handler: fn(mouse, nx, ny) answers true when it used
-- the click. One handler keeps the list of Blizzard's handlers short.
function WML.AddClickUse(fn)
  clickUses[#clickUses + 1] = fn
end

local function onCanvasClick(_, mouse, nx, ny)
  for _, use in ipairs(clickUses) do
    if use(mouse, nx, ny) then
      return true
    end
  end
  if not enabled("worldMapPanel") then
    return false
  end
  if mouse == "RightButton" then
    return onUserPinRightClick() or onRightClick(nx, ny)
  end
  if ns.CombatLocked() or mouse ~= "LeftButton" then
    return false
  end
  if not (placing or ns.Keys.Matches("mapMarker")) then
    return false
  end
  ns.MapOps.Record("canvas click", "marker")
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
      id = "next",
      key = "map.marker.next",
      run = function(wp)
        if WP.MoveToTop(wp.id) then
          ns.Notify(string.format(L["wp.activated"], wp.title), "info")
        end
      end,
    },
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

-- Position of a point of map `from` on the shown map `id` (of map type `kind`): the point itself, or
-- on a world or continent map the place of its zone inside it. nil when the client has no rectangle.
function WML.Project(from, x, y, id, kind)
  if from == id then
    return x, y
  end
  if WORLD_AND_CONTINENT[kind] then
    local rect = MW.Rect(capi("GetMapRectOnMap", from, id))
    if rect then
      return MW.Place(rect, x, y)
    end
  end
end

-- Waypoints of other maps show only when pinned.
local function project(wp, id, kind)
  if wp.map == id or wp.pinned then
    return WML.Project(wp.map, wp.x, wp.y, id, kind)
  end
end

-- Pins keep their size while the canvas zooms: scale 1 / canvas scale, offsets in the pin's units.
local function placePin(pin, canvas, scale)
  local s = 1 / scale
  pin:SetScale(s)
  pin:ClearAllPoints()
  pin:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * pin.nx / s, -canvas:GetHeight() * pin.ny / s)
end
WML.PlacePin = placePin

-- The state of a pin frame for /fg mapdiag as short texts; every call is guarded.
function WML.PinInfo(pin)
  local info = {}
  local function get(key, fn)
    local r = { pcall(fn) }
    local parts = {}
    for i = 2, 6 do
      local v = r[i]
      if v ~= nil then
        parts[#parts + 1] = type(v) == "number" and string.format("%.6g", v) or tostring(v)
      end
    end
    info[key] = r[1] and table.concat(parts, ",") or "error"
  end
  get("shown", function()
    return pin:IsShown()
  end)
  get("visible", function()
    return pin:IsVisible()
  end)
  get("parent", function()
    local parent = pin:GetParent()
    return parent and (parent:GetName() or tostring(parent))
  end)
  get("level", function()
    return pin:GetFrameLevel()
  end)
  get("scale", function()
    return pin:GetScale()
  end)
  get("size", function()
    return pin:GetWidth(), pin:GetHeight()
  end)
  get("point", function()
    local point, rel, relPoint, x, y = pin:GetPoint(1)
    return point, rel and (rel:GetName() or tostring(rel)), relPoint, x, y
  end)
  get("alpha", function()
    return pin:GetEffectiveAlpha()
  end)
  return info
end

local function canvasScale()
  local scale = call(map, "GetCanvasScale")
  return WL.readable(scale) and scale > 0 and scale or 1
end
WML.CanvasScale = canvasScale

local function hidePins(from)
  for i = from or 1, #pins do
    pins[i].wpId = nil
    pins[i]:Hide()
  end
end

-- Zoom and canvas size changes: only position and scale, no new data.
function WML.RescalePins()
  local canvas = WML.Canvas()
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
  local canvas = map and enabled("worldMapPins") and isShown(map) and WML.Canvas()
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
  local base, scale = WML.CanvasLevel(canvas, "waypoints"), canvasScale()
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

-- Round map button in the client's own style (the art of the tracking and minimap buttons: dark disc, gold ring,
-- glow on hover, icon sunk one pixel and dimmed while pressed).
local RING_ART = "Interface\\Minimap\\MiniMap-TrackingBorder"
local DISC_ART = "Interface\\Minimap\\UI-Minimap-Background"
local GLOW_ART = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local ICON_SIZE = 18

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
  ns.Layer.Own(button)
  WML.Lift(button)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- No flat fill or edge: the art below is the whole look.
  button.fgPalette = { text = "text", textHover = "text" }
  local back = button:CreateTexture(nil, "BACKGROUND")
  back:SetTexture(DISC_ART)
  back:SetSize(20, 20)
  back:SetPoint("TOPLEFT", 6, -5)
  local ring = button:CreateTexture(nil, "OVERLAY")
  ring:SetTexture(RING_ART)
  ring:SetSize(54, 54)
  ring:SetPoint("TOPLEFT")
  local glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
  glow:SetTexture(GLOW_ART)
  glow:SetBlendMode("ADD")
  glow:SetSize(BUTTON, BUTTON)
  glow:SetPoint("TOPLEFT")
  glow:Hide()
  local icon = button.icon
  icon:SetTexCoord(0, 1, 0, 1)
  -- Round the square logo into the ring where the client supports masks.
  if type(icon.SetMask) == "function" then
    pcall(icon.SetMask, icon, DISC)
  end
  button.fgPlace = function(self)
    local pressed = self.fgPressed == true
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", self, "TOPLEFT", 16 + (pressed and 1 or 0), -15 + (pressed and -1 or 0))
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetVertexColor(pressed and 0.7 or 1, pressed and 0.7 or 1, pressed and 0.7 or 1)
    back:SetVertexColor(pressed and 0.6 or 1, pressed and 0.6 or 1, pressed and 0.6 or 1)
  end
  button:HookScript("OnEnter", function()
    glow:Show()
  end)
  button:HookScript("OnLeave", function()
    glow:Hide()
  end)
  button:HookScript("OnHide", function()
    glow:Hide()
  end)
  button.fgPlace(button)
end

-- Moves the side tab to the outer edge of `frame` (the route panel at the map edge), nil: back to the map.
-- `rise`: how far the top of the frame lies below the top of the map, the tab keeps its height.
function WML.SetTabHost(frame, rise)
  rise = frame and rise or 0
  if frame == tabHost and rise == tabRise then
    return
  end
  tabHost, tabRise = frame, rise
  if tab then
    tab:ClearAllPoints()
    tab:SetPoint("TOPLEFT", tabHost or map, "TOPRIGHT", TAB_INSET, rise - TAB_DROP)
  end
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
    rel = tabHost or map,
    relPoint = "TOPRIGHT",
    x = TAB_INSET,
    y = tabRise - TAB_DROP,
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
  ns.Emit("FG_WORLDMAP_VIEW", "map")
end

-- Post-hook of the method `name` of the map for the module `owner`, once per pair. Returns whether it hooked.
function WML.HookMethod(owner, name, fn)
  local key = owner .. ":" .. name
  if hooked[key] or not map or type(hooksecurefunc) ~= "function" or type(field(map, name)) ~= "function" then
    return false
  end
  hooked[key] = true
  local label = "hook " .. key
  return pcall(hooksecurefunc, map, name, function()
    ns.MapOps.Defer(label, fn)
  end)
end

-- Post-hook of the script `script` of the map for the module `owner`, once per pair.
function WML.HookScript(owner, script, fn)
  local key = owner .. ":" .. script
  if hooked[key] or not map or type(map.HookScript) ~= "function" then
    return false
  end
  hooked[key] = true
  local label = "script " .. key
  return pcall(map.HookScript, map, script, function()
    ns.MapOps.Defer(label, fn)
  end)
end

-- The map, the zoom and the size of the canvas tell the modules that draw on the map (kind "map", "scale",
-- "size", "hide") with the message FG_WORLDMAP_VIEW.
local function onMapChanged()
  WML.RefreshPins()
  if bar and bar:IsShown() then
    bar:Refresh()
  end
  ns.Emit("FG_WORLDMAP_VIEW", "map")
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
  ns.Emit("FG_WORLDMAP_VIEW", "hide")
end

-- The click and cursor handlers write into Blizzard's handler lists, so they are added once, out of
-- combat; PLAYER_REGEN_ENABLED calls this again when the map attached during a fight.
local function addHandlers()
  if handlersAdded or not map or ns.InCombat() then
    return
  end
  handlersAdded = true
  ns.MapOps.Record("add canvas handlers")
  if type(field(map, "AddCanvasClickHandler")) == "function" then
    pcall(map.AddCanvasClickHandler, map, ns.Wrap("wm-click", onCanvasClick), HANDLER_PRIORITY)
  end
  if type(field(map, "AddCursorHandler")) == "function" then
    pcall(map.AddCursorHandler, map, function()
      if placing and not ns.CombatLocked() then
        return CURSOR
      end
    end, HANDLER_PRIORITY)
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
  WML.HookScript("links", "OnShow", WML.OnShow)
  WML.HookScript("links", "OnHide", WML.OnHide)
  WML.HookScript("links", "OnSizeChanged", function()
    ns.Debounce("wm-relayout", 0.05, WML.Relayout)
  end)
  WML.HookMethod("links", "OnMapChanged", onMapChanged)
  WML.HookMethod("links", "OnCanvasScaleChanged", function()
    WML.RescalePins()
    ns.Emit("FG_WORLDMAP_VIEW", "scale")
  end)
  WML.HookMethod("links", "OnCanvasSizeChanged", function()
    WML.RescalePins()
    ns.Emit("FG_WORLDMAP_VIEW", "size")
  end)
  WML.HookMethod("links", "RefreshOverlayFrames", WML.Relayout)
  addHandlers()
  WML.Apply()
  return true
end

ns.On("PLAYER_REGEN_ENABLED", function()
  if attached then
    addHandlers()
  end
end)

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
