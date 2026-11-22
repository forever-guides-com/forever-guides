-- Dungeon map widget: the floors of one instance as a picture of 256 px tiles (FileDataIDs from
-- Data.DungeonAssets, the client loads the files) with the boss, entrance, passage and marker
-- pins of Modules/PinLogic.lua on top, and an editor mode for the player's own pins. A floor is either
-- the older 4 by 3 grid cut to 3:2, or a minimap crop of any cols by rows (floor.cols, floor.rows), also
-- portrait; the picture is fitted into the room that is left (see DMV.MapSize) and pins and marker use
-- fractions of the visible picture. More than one floor: a dropdown picks the floor. An instance
-- without a map shows a dimmed loading screen with "map coming soon". Players have no position inside
-- instances, so there is no player marker, only the optional rough area marker (SetMarker). Hosts:
-- Modules/InstancesPage.lua and Modules/DungeonWorldMap.lua (which uses the hooks onFloorPick and
-- onMapClick, the height limit maxHeight and zoomBlocked). Tiles and pins come from pools and go back
-- (textures cleared) when the widget hides.
-- Zoom: the picture sits on a canvas that grows with the zoom (100 to 400 percent, MapMagnify) inside a
-- clipping viewport. Pins keep their pixel size (scaled by the pin size setting) and are placed by fractions
-- of the canvas, so data, clicks and the marker are independent of the zoom.
-- Route: when the data add-on has routes for the instance (docs/DUNGEONROUTES-FORMAT.md) a checkbox shows their
-- paths (strokes of Modules/MapRouteStrokeLogic.lua, rebuilt with the zoom, own pool) and numbered stop markers
-- (pool like the pins) on the floor; a dropdown picks between several routes. A stop whose boss is defeated
-- (Modules/BossProgress.lua) shows a tick instead of its number.
-- Rooms: when the data add-on has room names for the instance (docs/DUNGEONROUTES-FORMAT.md) a second checkbox shows
-- them as small faint labels (pool of font strings). A label that would overlap a stop, a pin or a label placed before
-- it is skipped (DungeonRouteLogic.PickLabels), the choice is made again with every zoom step.
-- Composed floor (floor.mm, docs/DUNGEONMINIMAPS-FORMAT.md): no tile grid but a list of minimap pictures of the
-- client from the data add-on, each placed in the 1002x668 frame with its own texture coordinates (a picture can
-- be turned) and draw sublevel. They share the texture pool with the tiles.
local _, ns = ...
local W, L, Theme, P, PD = ns.W, ns.L, ns.Theme, ns.PinLogic, ns.DungeonPinDialogs
local MG, R, S = ns.MapMagnify, ns.DungeonRouteLogic, ns.MapRouteStrokeLogic

local DMV = {}
ns.DungeonMapView = DMV

DMV.COLS, DMV.ROWS = 4, 3
-- 256 px tiles; of the 4 by 3 grid only the top left 1002x668 px (3:2) of the 1024x768 show map.
DMV.TILE, DMV.VIEW_W, DMV.VIEW_H = 256, 1002, 668
DMV.LAST_W = DMV.VIEW_W - (DMV.COLS - 1) * DMV.TILE
DMV.LAST_H = DMV.VIEW_H - (DMV.ROWS - 1) * DMV.TILE
DMV.MAX_W = 720
-- Tallest and lowest the picture gets; a host can lower the top with view.maxHeight (height of the widget).
DMV.MAX_H, DMV.MIN_H = 600, 120
DMV.PIN = 20
-- The entrance pin is bigger than the others; "show entrance" zooms in to at least this many percent.
DMV.ENTRANCE_SCALE, DMV.ENTRANCE_ZOOM = 1.25, 200
DMV.FLOOR_VIEW = "floor"
-- Route display: on or off (kept while the game runs), strokes per floor at most.
DMV.showRoute = true
DMV.ROUTE_BUDGET = 3000
-- Room labels: on or off (kept while the game runs), alpha of a label.
DMV.showRooms = true
DMV.ROOM_ALPHA = 0.75

local GAP, CTRL_H, DROP_W, DROP_H, MARKER = 6, 24, 170, 46, 22
local PIN_GROUP_W, PIN_SLIDER_W, PIN_VALUE_W = 250, 90, 40

-- Visible part of a floor in texture pixels: { cols, rows, w, h }. A minimap crop (floor.cols and
-- floor.rows) shows every tile whole, any other floor is the 4 by 3 grid cut to 3:2. A composed floor has the
-- same 1002x668 frame without tiles (mm = true).
function DMV.Geometry(floor)
  if floor and floor.mm then
    return { cols = 1, rows = 1, w = DMV.VIEW_W, h = DMV.VIEW_H, mm = true }
  end
  if floor and floor.cols and floor.rows then
    return { cols = floor.cols, rows = floor.rows, w = floor.cols * DMV.TILE, h = floor.rows * DMV.TILE }
  end
  return { cols = DMV.COLS, rows = DMV.ROWS, w = DMV.VIEW_W, h = DMV.VIEW_H }
end

-- Size of the picture in a widget of this width: as wide as the width allows (at most MAX_W), as high
-- as its aspect says, at most maxHeight (default MAX_H). When the height is the limit the picture is
-- fitted into that room (R.Fit) and sits in the middle of it. Returns x (offset inside the room), w, h.
function DMV.MapSize(width, geo, maxHeight)
  local roomW = math.max(1, math.floor(math.min(width, DMV.MAX_W)))
  local natural = math.max(1, math.floor(roomW * geo.h / geo.w + 0.5))
  local roomH = math.max(DMV.MIN_H, math.floor(math.min(maxHeight or DMV.MAX_H, DMV.MAX_H)))
  if natural <= roomH then
    return 0, roomW, natural
  end
  local x, _, w, h = ns.MapRevealLogic.Fit(geo.w, geo.h, roomW, roomH)
  return math.floor(x + 0.5), math.max(1, math.floor(w + 0.5)), math.max(1, math.floor(h + 0.5))
end

ns.AddLocale("enUS", {
  ["dmap.floor"] = "Choose floor",
  ["dmap.floorN"] = "Floor %d",
  ["dmap.edit"] = "Edit pins",
  ["dmap.export"] = "Export",
  ["dmap.import"] = "Import",
  ["dmap.noInstance"] = "Select an instance to see its map.",
  ["dmap.surface"] = "Dungeon map",
  ["dmap.soon"] = "Map to follow",
  ["dmap.pins.none"] = "No pins on this floor yet.",
  ["dmap.pins.bosses"] = "Bosses on this floor: %s",
  ["dmap.pins.noBosses"] = "No bosses set on this floor yet.",
  ["dmap.editHint"] = "Left click sets, drag moves, right click deletes",
  ["dmap.link.to"] = "Passage to floor %d",
  ["dmap.own"] = "Your own pin",
  ["dmap.pin.editHint"] = "Drag to move, right click to delete.",
  ["dmap.delete.title"] = "Delete pin",
  ["dmap.delete.text"] = "Delete this pin?",
  ["dmap.error"] = "Pin not saved: %s",
  ["dmap.entrance"] = "Show entrance",
  ["dmap.entrance.tip"] = "Zooms in and centers the map on the entrance.",
  ["dmap.entrance.none"] = "No entrance set on this floor.",
  ["dmap.pinSize"] = "Pin size",
  ["dmap.pinSize.tip"] = "Changes the size of all pins on the map.",
  ["dmap.legend"] = "Legend: %s",
  ["dmap.legend.entrance"] = "E Entrance",
  ["dmap.legend.boss"] = "Skull Boss",
  ["dmap.legend.link"] = "Number Passage to that floor",
  ["dmap.route"] = "Show route",
  ["dmap.route.tip"] = "Draws the route and its stops on the map.",
  ["dmap.rooms"] = "Show rooms",
  ["dmap.rooms.tip"] = "Writes the names of the rooms on the map.",
  ["dmap.route.choose"] = "Choose route",
  ["dmap.routeN"] = "Route %d",
  ["dmap.route.stop"] = "Stop %d",
  ["dmap.route.optional"] = "Optional stop",
  ["dmap.route.rare"] = "Rare stop",
  ["dmap.route.note"] = "Note",
  ["dmap.route.done"] = "Defeated",
})
ns.AddLocale("deDE", {
  ["dmap.floor"] = "Ebene wählen",
  ["dmap.floorN"] = "Ebene %d",
  ["dmap.edit"] = "Pins bearbeiten",
  ["dmap.export"] = "Exportieren",
  ["dmap.import"] = "Importieren",
  ["dmap.noInstance"] = "Wähle eine Instanz, um ihre Karte zu sehen.",
  ["dmap.surface"] = "Dungeonkarte",
  ["dmap.soon"] = "Karte folgt",
  ["dmap.pins.none"] = "Auf dieser Ebene sind noch keine Pins gesetzt.",
  ["dmap.pins.bosses"] = "Bosse auf dieser Ebene: %s",
  ["dmap.pins.noBosses"] = "Auf dieser Ebene sind noch keine Bosse gesetzt.",
  ["dmap.editHint"] = "Linksklick setzt, Ziehen verschiebt, Rechtsklick löscht",
  ["dmap.link.to"] = "Übergang zu Ebene %d",
  ["dmap.own"] = "Dein eigener Pin",
  ["dmap.pin.editHint"] = "Ziehen verschiebt, Rechtsklick löscht.",
  ["dmap.delete.title"] = "Pin löschen",
  ["dmap.delete.text"] = "Diesen Pin löschen?",
  ["dmap.error"] = "Pin nicht gespeichert: %s",
  ["dmap.entrance"] = "Eingang anzeigen",
  ["dmap.entrance.tip"] = "Zoomt hinein und zentriert die Karte auf den Eingang.",
  ["dmap.entrance.none"] = "Auf dieser Ebene ist kein Eingang gesetzt.",
  ["dmap.pinSize"] = "Pin-Größe",
  ["dmap.pinSize.tip"] = "Ändert die Größe aller Pins auf der Karte.",
  ["dmap.legend"] = "Legende: %s",
  ["dmap.legend.entrance"] = "E Eingang",
  ["dmap.legend.boss"] = "Totenkopf Boss",
  ["dmap.legend.link"] = "Zahl Übergang zu dieser Ebene",
  ["dmap.route"] = "Route anzeigen",
  ["dmap.route.tip"] = "Zeichnet die Route und ihre Stopps auf die Karte.",
  ["dmap.rooms"] = "Räume anzeigen",
  ["dmap.rooms.tip"] = "Schreibt die Namen der Räume auf die Karte.",
  ["dmap.route.choose"] = "Route wählen",
  ["dmap.routeN"] = "Route %d",
  ["dmap.route.stop"] = "Stopp %d",
  ["dmap.route.optional"] = "Optionaler Stopp",
  ["dmap.route.rare"] = "Seltener Stopp",
  ["dmap.route.note"] = "Hinweis",
  ["dmap.route.done"] = "Besiegt",
})

local function maps()
  return ns.Data.DungeonAssets and ns.Data.DungeonAssets.maps or {}
end

local function round3(v)
  return math.floor(v * 1000 + 0.5) / 1000
end

-- Instance lookup -------------------------------------------------------------------------------

-- Data.Instances entry by game instance ID (number) or by name in either language (string).
local function findInstance(what)
  for _, inst in ipairs(ns.Data.Instances or {}) do
    local n = inst.n or {}
    if (type(what) == "number" and inst.id == what) or (type(what) == "string" and (n.en == what or n.de == what)) then
      return inst
    end
  end
end

-- DungeonAssets key (English name) for GetInstanceInfo() results: the instance ID or the name.
-- Nil when the instance is unknown or has no entry in the map data.
function DMV.KeyFor(what)
  if type(what) == "string" and maps()[what] then
    return what
  end
  local inst = findInstance(what)
  local en = inst and inst.n and inst.n.en
  return en and maps()[en] and en or nil
end

-- The Data.Instances entry of the dungeon or raid the player is in, else nil.
function DMV.Current()
  if not GetInstanceInfo then
    return nil
  end
  local name, kind, _, _, _, _, _, id = GetInstanceInfo()
  if kind ~= "party" and kind ~= "raid" then
    return nil
  end
  return findInstance(id) or findInstance(name)
end

-- Widget ----------------------------------------------------------------------------------------

local function canEdit(pin)
  return pin.own or pin.kind == "boss"
end

function DMV.Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  local state = { key = nil, floor = 1, floors = 0, edit = false, bosses = {}, width = nil, mapW = 0, mapH = 0 }
  state.routeIndex = 1
  f.state = state
  f.tiles, f.pinFrames = {}, {}
  f.tilesUsed, f.pinsUsed = 0, 0
  f.stopFrames, f.stopsUsed = {}, 0
  f.strokes, f.strokesUsed = { shadow = {}, main = {} }, { shadow = 0, main = 0 }
  f.roomLabels, f.roomsUsed = {}, 0
  local floorDrop, floorOptions, editToggle, exportButton, importButton, map, hint, info, marker, soon
  local view, mag, entranceButton, pinGroup, routeToggle, routeDrop, routeOptions
  local roomToggle
  local pins = {}

  -- Called after a click changed what the widget needs in height (the page lays out again).
  local function changed()
    if f.onChange then
      f.onChange()
    end
  end

  -- Pools ---------------------------------------------------------------------------------------

  local function acquireTile()
    f.tilesUsed = f.tilesUsed + 1
    local tex = f.tiles[f.tilesUsed]
    if not tex then
      tex = map:CreateTexture(nil, "ARTWORK")
      f.tiles[f.tilesUsed] = tex
    end
    tex:Show()
    return tex
  end

  -- A picture of a composed floor: texture, draw sublevel (higher building parts over lower ones). Its place
  -- follows in placeAll. A damaged row is left out.
  local function acquirePiece(row)
    if type(row) ~= "table" or #row < 14 or type(row[1]) ~= "number" then
      return
    end
    local tex = acquireTile()
    tex:SetTexture(row[1])
    tex:SetDrawLayer("BACKGROUND", math.max(0, math.min(7, math.floor(tonumber(row[14]) or 0))))
    tex.piece = row
  end

  local function placePiece(tex, row, sx, sy)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", map, "TOPLEFT", row[2] * sx, -row[3] * sy)
    tex:SetSize(row[4] * sx, row[5] * sy)
    tex:SetTexCoord(row[6], row[7], row[8], row[9], row[10], row[11], row[12], row[13])
  end

  local function cursorFraction()
    local cx, cy = GetCursorPosition()
    local scale = map:GetEffectiveScale()
    local w, h = map:GetWidth(), map:GetHeight()
    if not scale or scale <= 0 or w <= 0 or h <= 0 then
      return 0, 0
    end
    local x = ((cx or 0) / scale - (map:GetLeft() or 0)) / w
    local y = ((map:GetTop() or 0) - (cy or 0) / scale) / h
    return round3(math.min(1, math.max(0, x))), round3(math.min(1, math.max(0, y)))
  end

  -- Pixel size of a pin: the base size times the pin size setting, the entrance a bit bigger.
  local function pinPixels(pin)
    local D = ns.InstanceDisplay
    local size = DMV.PIN * (D and D.PinFactor() or 1)
    if pin.kind == "entrance" then
      size = size * DMV.ENTRANCE_SCALE
    end
    return math.floor(size + 0.5)
  end

  local function bossLabel(pin)
    for _, b in ipairs(state.bosses) do
      if (pin.eid and b.eid == pin.eid) or b.name.en == pin.boss then
        return PD.BossName(b)
      end
    end
    return pin.boss
  end

  local function pinTitle(pin)
    if pin.kind == "boss" then
      return bossLabel(pin) or "?"
    elseif pin.kind == "entrance" then
      return L["dmap.kind.entrance"]
    elseif pin.kind == "link" then
      return string.format(L["dmap.link.to"], pin.toFloor)
    end
    return pin.label or PD.IconName(pin.icon)
  end

  local function showTooltip(pin)
    local lines = {}
    if pin.kind == "marker" and pin.boss then
      lines[#lines + 1] = bossLabel(pin)
    end
    if pin.own then
      lines[#lines + 1] = L["dmap.own"]
    end
    if state.edit and canEdit(pin) then
      lines[#lines + 1] = L["dmap.pin.editHint"]
    end
    ns.ShowTooltip(pin.frame, pinTitle(pin), table.concat(lines, "\n"))
  end

  -- Storage -------------------------------------------------------------------------------------

  local function fail(err)
    ns.Notify(string.format(L["dmap.error"], tostring(err)), "error")
  end

  -- Index of an own pin among the own pins of its kind, the address PinLogic.Remove takes.
  local function ownIndex(pin)
    local n = 0
    for _, p in ipairs(P.OwnPins(state.key)) do
      if p.kind == pin.kind then
        n = n + 1
        if
          p.floor == pin.floor
          and p.x == pin.x
          and p.y == pin.y
          and p.icon == pin.icon
          and p.toFloor == pin.toFloor
        then
          return n
        end
      end
    end
  end

  local function removeOwn(pin)
    if pin.kind == "boss" then
      return P.Remove(state.key, pin.boss)
    end
    local index = ownIndex(pin)
    return index and P.Remove(state.key, pin.kind, index) or false
  end

  local render

  local function move(pin, x, y)
    local moved = {}
    for k, v in pairs(pin) do
      moved[k] = v
    end
    moved.frame, moved.own, moved.x, moved.y = nil, nil, round3(x), round3(y)
    -- Boss pins are replaced by identity, every other kind is identified by its position.
    if pin.own and pin.kind ~= "boss" then
      removeOwn(pin)
    end
    local ok, err = P.Set(moved)
    if not ok then
      fail(err)
    end
    render()
    changed()
  end

  local function delete(pin)
    ns.Dialogs.Confirm("dmap.delete.title", "dmap.delete.text", function()
      removeOwn(pin)
      render()
      changed()
    end)
  end

  local function place(spec, floor, x, y)
    spec.inst, spec.floor, spec.x, spec.y = state.key, floor, x, y
    local ok, err = P.Set(spec)
    if not ok then
      fail(err)
    end
    render()
    changed()
  end

  -- Pins ----------------------------------------------------------------------------------------

  local function createPin()
    local pin = CreateFrame("Button", nil, map)
    pin:SetSize(DMV.PIN, DMV.PIN)
    pin.plate = pin:CreateTexture(nil, "BACKGROUND")
    pin.plate:SetAllPoints()
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("TOPLEFT", 2, -2)
    pin.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    pin.glyph = W.Text(pin, { role = "micro", color = "text", justify = "CENTER" })
    pin.glyph:SetPoint("CENTER")
    W.Border(pin, "white", 0.8, 1)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:RegisterForDrag("LeftButton")
    pin:SetScript("OnEnter", function(self)
      if self.pin then
        showTooltip(self.pin)
      end
    end)
    pin:SetScript("OnLeave", ns.HideTooltip)
    pin:SetScript(
      "OnClick",
      ns.Wrap("dmap-pin", function(self, button)
        if button == "RightButton" and state.edit and self.pin and self.pin.own then
          delete(self.pin)
        end
      end)
    )
    pin:SetScript(
      "OnDragStart",
      ns.Wrap("dmap-drag", function(self)
        if not (state.edit and self.pin and canEdit(self.pin)) then
          return
        end
        state.drag = self
        self:SetScript("OnUpdate", function()
          local x, y = cursorFraction()
          self:ClearAllPoints()
          self:SetPoint("CENTER", map, "TOPLEFT", x * state.mapW, -y * state.mapH)
        end)
      end)
    )
    pin:SetScript(
      "OnDragStop",
      ns.Wrap("dmap-drop", function(self)
        if state.drag ~= self then
          return
        end
        state.drag = nil
        self:SetScript("OnUpdate", nil)
        local x, y = cursorFraction()
        move(self.pin, x, y)
      end)
    )
    return pin
  end

  local function paintPin(frame, pin)
    local plate, glyph
    glyph = ""
    frame.icon:SetTexture(nil)
    if pin.kind == "boss" then
      plate = "danger"
      PD.PaintIcon(frame.icon, "skull")
    elseif pin.kind == "entrance" then
      plate, glyph = "success", "E"
    elseif pin.kind == "link" then
      plate, glyph = "action", tostring(pin.toFloor)
    else
      plate = "accent2"
      if not PD.PaintIcon(frame.icon, pin.icon) then
        glyph = "?"
      end
    end
    frame.plate:SetColorTexture(Theme.color(plate, 0.95))
    W.SetText(frame.glyph, nil, glyph)
  end

  -- The rough area marker sits on its own floor only; it is not a position, the tooltip says so.
  local function placeMarker()
    local spec = state.marker
    if not (spec and state.floors > 0 and state.mapW > 0 and (spec.floor == nil or spec.floor == state.floor)) then
      if marker then
        marker:Hide()
      end
      return
    end
    if not marker then
      marker = CreateFrame("Button", nil, map)
      marker:SetSize(MARKER, MARKER)
      marker.plate = marker:CreateTexture(nil, "BACKGROUND")
      marker.plate:SetAllPoints()
      ns.Bind(marker.plate, function(t)
        t:SetColorTexture(Theme.color("surface", 0.75))
      end)
      marker.glyph = W.Text(marker, { text = "~", role = "ui", color = "accent2", justify = "CENTER" })
      marker.glyph:SetPoint("CENTER")
      W.Border(marker, "accent2", 1, 2)
      marker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      marker:SetScript("OnEnter", function(self)
        if state.marker then
          ns.ShowTooltip(self, state.marker.title, state.marker.text)
        end
      end)
      marker:SetScript("OnLeave", ns.HideTooltip)
      -- A click on the marker is a click on the map below it.
      marker:SetScript("OnClick", function(_, button)
        local click = map:GetScript("OnClick")
        if click then
          click(map, button)
        end
      end)
      f.marker = marker
    end
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", map, "TOPLEFT", spec.x * state.mapW, -spec.y * state.mapH)
    marker:Show()
  end

  -- Route ---------------------------------------------------------------------------------------

  local function activeRoute()
    return DMV.showRoute and state.routes and state.routes[state.routeIndex] or nil
  end

  -- True when the boss of the stop is defeated (BossProgress), false when it is not or the data does not know it.
  local function stopDefeated(stop)
    local idx = R.BossIndex(stop, state.bosses)
    local BP, inst = ns.BossProgress, state.key and findInstance(state.key)
    return idx ~= nil and BP ~= nil and inst ~= nil and BP.WingStatus(inst, idx) ~= nil
  end

  local function stopTitle(item)
    if item.note then
      return L["dmap.route.note"]
    end
    local idx = R.BossIndex(item.stop, state.bosses)
    for _, b in ipairs(state.bosses) do
      if b.idx == idx then
        return PD.BossName(b)
      end
    end
    return ns.T(item.stop.n) or string.format(L["dmap.route.stop"], item.number)
  end

  local function showStopTip(frame)
    local item, lines = frame.row, {}
    local stop = item.stop
    if stop and (stop.k == "optional" or stop.k == "rare") then
      lines[#lines + 1] = L["dmap.route." .. stop.k]
    end
    if item.done then
      lines[#lines + 1] = L["dmap.route.done"]
    end
    local text = ns.T(stop and stop.t or (item.note and item.note.t))
    if text and text ~= "" then
      lines[#lines + 1] = text
    end
    ns.ShowTooltip(frame, stopTitle(item), table.concat(lines, "\n"))
  end

  local function createStop()
    local stop = CreateFrame("Frame", nil, map)
    stop:SetSize(DMV.PIN, DMV.PIN)
    stop.plate = stop:CreateTexture(nil, "BACKGROUND")
    stop.plate:SetAllPoints()
    stop.glyph = W.Text(stop, { role = "micro", color = "text", justify = "CENTER" })
    stop.glyph:SetPoint("CENTER")
    stop.tick = W.CheckMark(stop, 12, "text")
    stop.tick:SetPoint("CENTER")
    W.Border(stop, "white", 0.8, 1)
    stop:EnableMouse(true)
    stop:SetScript("OnEnter", function(self)
      if self.row then
        showStopTip(self)
      end
    end)
    stop:SetScript("OnLeave", ns.HideTooltip)
    -- A click on a stop is a click on the map below it.
    stop:SetScript("OnMouseUp", function(_, button)
      local click = map:GetScript("OnClick")
      if click then
        click(map, button)
      end
    end)
    return stop
  end

  local function acquireStop(item)
    f.stopsUsed = f.stopsUsed + 1
    local frame = f.stopFrames[f.stopsUsed]
    if not frame then
      frame = createStop()
      f.stopFrames[f.stopsUsed] = frame
    end
    item.done = item.stop ~= nil and stopDefeated(item.stop)
    frame.row = item
    frame.plate:SetColorTexture(Theme.color(item.stop and R.StopToken(item.stop.k) or "info", 0.95))
    W.SetText(frame.glyph, nil, (item.done and "") or (item.stop and tostring(item.number)) or "i")
    frame.tick:SetShown(item.done)
    frame:Show()
  end

  -- The rows of the active route on the shown floor and a marker for each stop and note.
  local function fillRoute()
    local route = activeRoute()
    state.routeView = route and R.Visible(route, state.floor) or nil
    local routeView = state.routeView
    if not routeView then
      return
    end
    for _, item in ipairs(routeView.stops) do
      acquireStop(item)
    end
    for _, note in ipairs(routeView.notes) do
      acquireStop({ note = note })
    end
  end

  -- Rooms ---------------------------------------------------------------------------------------

  -- A label per room of the shown floor, text and size are fixed here, the place follows the zoom (placeRooms).
  local function fillRooms()
    if not (DMV.showRooms and state.rooms) then
      return
    end
    for _, row in ipairs(R.RoomLabels(state.rooms, state.floor)) do
      f.roomsUsed = f.roomsUsed + 1
      local label = f.roomLabels[f.roomsUsed]
      if not label then
        label = W.Text(map, { role = "micro", color = "textMuted", justify = "CENTER" })
        label:SetAlpha(DMV.ROOM_ALPHA)
        f.roomLabels[f.roomsUsed] = label
      end
      W.SetText(label, nil, ns.T(row.n))
      label.row = row
      label.w, label.h = math.ceil(label:GetStringWidth()) + 4, math.ceil(label:GetStringHeight()) + 2
    end
  end

  local function placeRooms()
    local items, blockers = {}, {}
    for i = 1, f.roomsUsed do
      local label = f.roomLabels[i]
      items[i] = { x = label.row.x * state.mapW, y = label.row.y * state.mapH, w = label.w, h = label.h }
    end
    local function block(frame, at)
      local size = frame:GetWidth()
      blockers[#blockers + 1] = { x = at.x * state.mapW, y = at.y * state.mapH, w = size, h = size }
    end
    for i = 1, f.stopsUsed do
      block(f.stopFrames[i], f.stopFrames[i].row.stop or f.stopFrames[i].row.note)
    end
    for i = 1, f.pinsUsed do
      block(f.pinFrames[i], f.pinFrames[i].pin)
    end
    local picked = R.PickLabels(items, blockers, state.mapW, state.mapH)
    for i = 1, f.roomsUsed do
      local label, rect = f.roomLabels[i], picked[i]
      label:ClearAllPoints()
      if rect then
        label:SetPoint("CENTER", map, "TOPLEFT", rect.x, -rect.y)
      end
      label:SetShown(rect ~= false)
    end
  end

  local sbuf, pxs, pys = S.NewBuffer(), {}, {}

  local function acquireStroke(kind, sublevel)
    local used = f.strokesUsed[kind] + 1
    f.strokesUsed[kind] = used
    local line = f.strokes[kind][used]
    if not line then
      line = map:CreateLine(nil, "ARTWORK", nil, sublevel)
      f.strokes[kind][used] = line
    end
    return line
  end

  local function hideStrokes()
    for _, kind in ipairs({ "shadow", "main" }) do
      for i = 1, f.strokesUsed[kind] do
        f.strokes[kind][i]:Hide()
      end
      f.strokesUsed[kind] = 0
    end
  end

  -- The paths as strokes in canvas px (a new build per zoom step; the line width stays the same in px).
  local function strokeRoute()
    hideStrokes()
    local routeView = state.routeView
    if not (routeView and state.mapW > 0 and state.mapH > 0 and map.CreateLine) then
      return
    end
    local rect = { 0, 0, state.mapW, state.mapH }
    for _, path in ipairs(routeView.paths) do
      local style = R.PathStyle(path.k)
      local n = R.Points(path.v, state.mapW, state.mapH, pxs, pys)
      S.Reset(sbuf)
      S.Build(sbuf, pxs, pys, n, rect, {
        style = style.style,
        width = style.width,
        budget = math.max(1, DMV.ROUTE_BUDGET - f.strokesUsed.shadow - f.strokesUsed.main),
      })
      for k = 1, sbuf.n do
        local shadow = sbuf.shadow[k]
        local line = acquireStroke(shadow and "shadow" or "main", shadow and 1 or 2)
        line:SetThickness(sbuf.w[k])
        if shadow then
          line:SetColorTexture(Theme.color("bg", style.alpha * 0.7))
        else
          line:SetColorTexture(Theme.color(style.token, style.alpha))
        end
        line:SetStartPoint("TOPLEFT", map, sbuf.x1[k], -sbuf.y1[k])
        line:SetEndPoint("TOPLEFT", map, sbuf.x2[k], -sbuf.y2[k])
        line:Show()
      end
    end
  end

  local function placeAll()
    local geo = state.geo
    for i = 1, geo and f.tilesUsed or 0 do
      local col, row = (i - 1) % geo.cols, math.floor((i - 1) / geo.cols)
      local tex = f.tiles[i]
      local sx, sy = state.mapW / geo.w, state.mapH / geo.h
      if tex.piece then
        placePiece(tex, tex.piece, sx, sy)
      else
        -- The last column and row are cut to the visible area, the rest of the tile is empty.
        local cw = math.min(DMV.TILE, geo.w - col * DMV.TILE)
        local ch = math.min(DMV.TILE, geo.h - row * DMV.TILE)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", map, "TOPLEFT", col * DMV.TILE * sx, -row * DMV.TILE * sy)
        tex:SetSize(cw * sx, ch * sy)
        tex:SetTexCoord(0, cw / DMV.TILE, 0, ch / DMV.TILE)
      end
    end
    for i = 1, f.pinsUsed do
      local frame = f.pinFrames[i]
      local px = pinPixels(frame.pin)
      frame:SetSize(px, px)
      frame:ClearAllPoints()
      frame:SetPoint("CENTER", map, "TOPLEFT", frame.pin.x * state.mapW, -frame.pin.y * state.mapH)
    end
    for i = 1, f.stopsUsed do
      local frame = f.stopFrames[i]
      local at = frame.row.stop or frame.row.note
      local px = math.floor(DMV.PIN * ns.InstanceDisplay.PinFactor() * 0.9 + 0.5)
      frame:SetSize(px, px)
      frame:ClearAllPoints()
      frame:SetPoint("CENTER", map, "TOPLEFT", at.x * state.mapW, -at.y * state.mapH)
    end
    strokeRoute()
    placeRooms()
    placeMarker()
  end

  -- The entrance pin of the shown floor, if the data has one.
  local function entrancePin()
    for _, p in ipairs(pins) do
      if p.kind == "entrance" and p.floor == state.floor then
        return p
      end
    end
  end

  -- The zoom controls follow the state: the entrance button needs a pin and a free zoom.
  local function paintZoomControls()
    mag.Refresh()
    entranceButton:SetEnabled(entrancePin() ~= nil and mag.Blocked() == nil)
  end

  -- The canvas follows the zoom of the viewport: same picture, new size, pins stay as big as they are.
  local function applyZoom()
    if not state.viewW then
      return
    end
    mag.Place(state.viewW, state.viewH)
    local level = mag.Percent() / 100
    state.mapW, state.mapH = state.viewW * level, state.viewH * level
    placeAll()
    paintZoomControls()
  end

  -- Release and fill -----------------------------------------------------------------------------

  local function releaseAll()
    for i = 1, f.tilesUsed do
      local tex = f.tiles[i]
      tex:SetTexture(nil)
      tex:Hide()
      if tex.piece then
        tex.piece = nil
        tex:SetDrawLayer("ARTWORK", 0)
      end
    end
    for i = 1, f.pinsUsed do
      local frame = f.pinFrames[i]
      frame.icon:SetTexture(nil)
      frame.pin = nil
      frame:Hide()
    end
    for i = 1, f.stopsUsed do
      f.stopFrames[i].row = nil
      f.stopFrames[i]:Hide()
    end
    hideStrokes()
    for i = 1, f.roomsUsed do
      f.roomLabels[i]:SetText("")
      f.roomLabels[i].row = nil
      f.roomLabels[i]:Hide()
    end
    f.roomsUsed = 0
    state.routeView = nil
    f.tilesUsed, f.pinsUsed, f.stopsUsed = 0, 0, 0
    soon.pic:SetTexture(nil)
  end

  local function infoText(onFloor)
    local names = {}
    for _, p in ipairs(onFloor) do
      if p.kind == "boss" then
        names[#names + 1] = bossLabel(p) or "?"
      end
    end
    local lines = {}
    if #onFloor == 0 then
      lines[1] = L["dmap.pins.none"]
    elseif #names == 0 then
      lines[1] = L["dmap.pins.noBosses"]
    else
      lines[1] = string.format(L["dmap.pins.bosses"], table.concat(names, ", "))
    end
    local legend = {}
    for _, kind in ipairs({ "entrance", "boss", "link" }) do
      for _, p in ipairs(onFloor) do
        if p.kind == kind then
          legend[#legend + 1] = L["dmap.legend." .. kind]
          break
        end
      end
    end
    if #legend > 0 then
      lines[#lines + 1] = string.format(L["dmap.legend"], table.concat(legend, ", "))
    end
    if state.edit then
      lines[#lines + 1] = L["dmap.editHint"]
    end
    return table.concat(lines, "\n")
  end

  -- The floor entry of the dropdown: the name of the floor when the data has one, else "Floor n".
  local function floorName(n)
    local floor = state.entry and state.entry.floors[n]
    local name = floor and floor.n and ns.T(floor.n)
    return name or string.format(L["dmap.floorN"], n)
  end

  local function paintRoutes()
    for i = #routeOptions, 1, -1 do
      routeOptions[i] = nil
    end
    for i, route in ipairs(state.routes or {}) do
      routeOptions[i] = { value = i, text = ns.T(route.n) or string.format(L["dmap.routeN"], i) }
    end
    routeDrop.Refresh()
  end

  local function paintFloors()
    for i = #floorOptions, 1, -1 do
      floorOptions[i] = nil
    end
    for i = 1, state.floors do
      floorOptions[i] = { value = i, text = floorName(i) }
    end
    floorDrop:SetShown(state.floors > 1)
    floorDrop.Refresh()
  end

  -- The dimmed loading screen of the instance (when there is one) behind the note "map coming soon".
  local function paintSoon()
    local inst = findInstance(state.requested)
    local IV = ns.InstanceView
    local image = inst and IV and IV.LoadingImage(inst) or nil
    soon.image = image
    soon.pic:SetShown(image ~= nil)
    soon.dim:SetShown(image ~= nil)
    soon.pic:SetTexture(image and image.fid or nil)
  end

  function render()
    releaseAll()
    local hasMap = state.floors > 0
    local waiting = not hasMap and state.requested ~= nil
    view:SetShown(hasMap)
    map:SetShown(hasMap)
    info:SetShown(hasMap)
    entranceButton:SetShown(hasMap)
    pinGroup:SetShown(hasMap)
    soon:SetShown(waiting)
    hint:SetShown(not hasMap and not waiting)
    editToggle:SetShown(hasMap)
    routeToggle:SetShown(hasMap and state.routes ~= nil)
    roomToggle:SetShown(hasMap and state.rooms ~= nil)
    routeDrop:SetShown(hasMap and DMV.showRoute and state.routes ~= nil and #state.routes > 1)
    exportButton:SetShown(hasMap)
    importButton:SetShown(hasMap)
    W.SetText(hint, "dmap.noInstance")
    if not hasMap then
      state.geo = nil
      mag.Refresh()
      paintFloors()
      if waiting and f:IsVisible() then
        paintSoon()
      end
      return
    end
    pins = P.Pins(state.key)
    local onFloor = {}
    for _, p in ipairs(pins) do
      if p.floor == state.floor then
        onFloor[#onFloor + 1] = p
      end
    end
    local floor = state.entry.floors[state.floor]
    state.geo = DMV.Geometry(floor)
    paintFloors()
    paintRoutes()
    editToggle.Refresh()
    routeToggle.Refresh()
    roomToggle.Refresh()
    pinGroup.Refresh()
    paintZoomControls()
    W.SetText(info, nil, infoText(onFloor))
    -- Hidden pages keep no textures, OnShow paints again.
    if not f:IsVisible() then
      return
    end
    if floor.mm then
      for _, row in ipairs(ns.InstanceDataAccess and ns.InstanceDataAccess.Minimaps(state.key, state.floor) or {}) do
        acquirePiece(row)
      end
    else
      for i, id in ipairs(floor.fid) do
        acquireTile():SetTexture(id)
        if i >= state.geo.cols * state.geo.rows then
          break
        end
      end
    end
    for _, p in ipairs(onFloor) do
      f.pinsUsed = f.pinsUsed + 1
      local frame = f.pinFrames[f.pinsUsed]
      if not frame then
        frame = createPin()
        f.pinFrames[f.pinsUsed] = frame
      end
      p.frame = frame
      frame.pin = p
      paintPin(frame, p)
      frame:Show()
    end
    fillRoute()
    fillRooms()
    placeAll()
  end

  -- Layout ----------------------------------------------------------------------------------------

  -- Wraps the controls into rows of the given width, returns their height. An item with `low` sits on
  -- the line of the dropdown button when its row holds the (taller) dropdown.
  local function flow(items, width)
    local rows, row, x = {}, nil, 0
    for _, it in ipairs(items) do
      if it.frame:IsShown() then
        if not row or (x > 0 and x + it.w > width) then
          row, x = { h = 0 }, 0
          rows[#rows + 1] = row
        end
        row[#row + 1] = { item = it, x = x }
        row.h = math.max(row.h, it.h)
        x = x + it.w + GAP
      end
    end
    local y = 0
    for _, r in ipairs(rows) do
      for _, cell in ipairs(r) do
        local it = cell.item
        local dy = it.low and math.max(0, r.h - it.h - 4) or 0
        it.frame:ClearAllPoints()
        it.frame:SetPoint("TOPLEFT", f, "TOPLEFT", cell.x, -(y + dy))
        it.frame:SetSize(it.w, it.h)
      end
      y = y + r.h + GAP
    end
    return math.max(0, y - GAP)
  end

  -- Room the picture may take: the host's height limit minus what the widget needs besides the picture.
  local function pictureLimit(used)
    if not f.maxHeight then
      return DMV.MAX_H
    end
    return math.max(DMV.MIN_H, math.min(DMV.MAX_H, f.maxHeight - used))
  end

  -- "Map coming soon": the dimmed loading screen fitted like a map, the note on a plate in the middle.
  local function layoutSoon(width)
    local x0, w, h = DMV.MapSize(width, DMV.Geometry(nil), pictureLimit(0))
    soon:ClearAllPoints()
    soon:SetPoint("TOPLEFT", f, "TOPLEFT", x0, 0)
    soon:SetSize(w, h)
    local image = soon.image
    if image then
      local probe = ns.AssetFiles.cache[image.fid]
      soon.pic:SetTexCoord(ns.InstanceView.Crop(image.src, w, h, probe and probe.w, probe and probe.h))
    end
    soon.text:SetWidth(math.max(1, w - 48))
    local plateW = math.max(1, math.min(w - 16, math.ceil(soon.text:GetStringWidth()) + 32))
    soon.plate:ClearAllPoints()
    soon.plate:SetPoint("CENTER", soon, "CENTER")
    soon.plate:SetSize(plateW, math.ceil(soon.text:GetStringHeight()) + 20)
    soon.text:ClearAllPoints()
    soon.text:SetPoint("TOPLEFT", soon.plate, "TOPLEFT", 16, -10)
    soon.text:SetPoint("BOTTOMRIGHT", soon.plate, "BOTTOMRIGHT", -16, 10)
    return h
  end

  local function layout(width)
    local y
    if state.floors > 0 then
      local items = {
        { frame = floorDrop, w = math.min(DROP_W, width), h = DROP_H },
        { frame = routeDrop, w = math.min(DROP_W, width), h = DROP_H },
        { frame = entranceButton, w = 150, h = CTRL_H, low = true },
        { frame = pinGroup, w = math.min(PIN_GROUP_W, width), h = 22, low = true },
        { frame = routeToggle, w = 170, h = 22, low = true },
        { frame = roomToggle, w = 170, h = 22, low = true },
        { frame = editToggle, w = 170, h = 22, low = true },
        { frame = exportButton, w = 110, h = CTRL_H, low = true },
        { frame = importButton, w = 110, h = CTRL_H, low = true },
      }
      y = flow(items, width) + GAP * 2
      info:SetWidth(width)
      local infoH = info:GetStringHeight()
      local x0, w, h = DMV.MapSize(width, state.geo, pictureLimit(y + GAP + infoH))
      state.viewW, state.viewH = w, h
      view:ClearAllPoints()
      view:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -y)
      view:SetSize(w, h)
      mag.SetMax(DMV.FLOOR_VIEW, MG.MaxPercent(state.geo.w, w))
      applyZoom()
      y = y + h + GAP
      info:ClearAllPoints()
      info:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      info:SetHeight(infoH)
      y = y + infoH
    elseif state.requested then
      y = layoutSoon(width)
    else
      hint:ClearAllPoints()
      hint:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
      hint:SetWidth(width)
      y = hint:GetStringHeight()
      hint:SetHeight(y)
    end
    f:SetHeight(math.max(1, y))
    return y
  end

  -- The page stack calls this with the width it gives the widget and uses the returned height.
  function f:fgGridLayout(width)
    state.width = width
    return layout(width)
  end

  -- Public ---------------------------------------------------------------------------------------

  local function startFloor()
    for _, p in ipairs(P.Pins(state.key)) do
      if p.kind == "entrance" then
        return p.floor
      end
    end
    return 1
  end

  -- Shows the instance with this DungeonAssets key or English name (no floor: "map coming soon"). Returns
  -- true when it has a map.
  function f:SetInstance(key)
    local entry = key and maps()[key] or nil
    if key ~= state.requested then
      mag.ResetView(DMV.FLOOR_VIEW)
    end
    state.requested = key
    state.entry = entry
    state.floors = entry and entry.floors and #entry.floors or 0
    -- Without a floor there is nothing to put pins on.
    state.key = state.floors > 0 and key or nil
    state.bosses = state.key and P.BossList(state.key) or {}
    state.routes = state.key and ns.InstanceDataAccess and R.Routes(ns.InstanceDataAccess.Routes(state.key)) or nil
    state.routeIndex = 1
    state.rooms = state.key and ns.InstanceDataAccess and ns.InstanceDataAccess.Rooms(state.key) or nil
    state.edit = false
    state.marker = nil
    state.floor = state.floors > 0 and startFloor() or 1
    render()
    placeMarker()
    if state.width then
      layout(state.width)
    end
    return state.floors > 0
  end

  function f:SetFloor(n)
    if type(n) ~= "number" or n < 1 or n > state.floors then
      return false
    end
    if n ~= state.floor then
      mag.ResetView(DMV.FLOOR_VIEW)
    end
    state.floor = n
    render()
    if state.width then
      layout(state.width)
    end
    return true
  end

  -- spec = { x, y (0..1), floor (optional), title, text } or nil to remove the marker.
  function f:SetMarker(spec)
    state.marker = spec
    placeMarker()
  end

  -- The zoom bar and the entrance button follow the host's block (combat).
  function f:RefreshZoom()
    if mag then
      paintZoomControls()
    end
  end

  function f:Refresh()
    render()
    if state.width then
      layout(state.width)
    end
  end

  -- Frames ---------------------------------------------------------------------------------------

  floorOptions = {}
  floorDrop = W.Dropdown(f, {
    key = "dmap.floor",
    options = floorOptions,
    width = DROP_W,
    get = function()
      return state.floor
    end,
    set = function(n)
      f:SetFloor(n)
      if f.onFloorPick then
        f.onFloorPick(n)
      end
      changed()
    end,
  })
  ns.FlowLayout.FitDropdown(floorDrop)
  editToggle = W.Checkbox(f, {
    key = "dmap.edit",
    get = function()
      return state.edit
    end,
    set = function(on)
      state.edit = on
      render()
      changed()
    end,
  })
  routeOptions = {}
  routeDrop = W.Dropdown(f, {
    key = "dmap.route.choose",
    options = routeOptions,
    width = DROP_W,
    get = function()
      return state.routeIndex
    end,
    set = function(i)
      state.routeIndex = i
      render()
      changed()
    end,
  })
  ns.FlowLayout.FitDropdown(routeDrop)
  routeToggle = W.Checkbox(f, {
    key = "dmap.route",
    tooltipText = "dmap.route.tip",
    get = function()
      return DMV.showRoute
    end,
    set = function(on)
      DMV.showRoute = on
      render()
      changed()
    end,
  })
  roomToggle = W.Checkbox(f, {
    key = "dmap.rooms",
    tooltipText = "dmap.rooms.tip",
    get = function()
      return DMV.showRooms
    end,
    set = function(on)
      DMV.showRooms = on
      render()
      changed()
    end,
  })
  exportButton = W.Action(f, {
    label = "act.export",
    icon = "export",
    tooltip = "dmap.export",
    width = 110,
    height = CTRL_H,
    opens = true,
    onClick = function()
      PD.Export(state.key)
    end,
  })
  importButton = W.Action(f, {
    label = "act.import",
    icon = "import",
    tooltip = "dmap.import",
    width = 110,
    height = CTRL_H,
    opens = true,
    onClick = function()
      PD.Import(function()
        render()
        changed()
      end)
    end,
  })
  entranceButton = W.Action(f, {
    label = "dmap.entrance",
    icon = "marker",
    tooltip = "dmap.entrance",
    tooltipText = "dmap.entrance.tip",
    width = 150,
    height = CTRL_H,
    onClick = function()
      local pin = entrancePin()
      if pin then
        mag.CenterOn(pin.x, pin.y, math.max(DMV.ENTRANCE_ZOOM, mag.Percent()))
        applyZoom()
      end
    end,
  })
  entranceButton:HookScript("OnEnter", function(self)
    if not entrancePin() then
      ns.ShowTooltip(self, L["dmap.entrance"], L["dmap.entrance.none"])
    end
  end)
  pinGroup = CreateFrame("Frame", nil, f)
  pinGroup:SetSize(PIN_GROUP_W, 22)
  local pinLabel = W.Text(pinGroup, { key = "dmap.pinSize", role = "ui", color = "textSecondary" })
  pinLabel:SetPoint("LEFT", pinGroup, "LEFT", 0, 0)
  local pinValue = W.Text(pinGroup, { role = "ui", color = "text", justify = "RIGHT" })
  local pinSlider = W.CompactSlider(pinGroup, {
    min = ns.InstanceDisplay.PIN_MIN,
    max = ns.InstanceDisplay.PIN_MAX,
    step = ns.InstanceDisplay.PIN_STEP,
    width = PIN_SLIDER_W,
    applyOn = "release",
    preview = function(v)
      pinValue:SetText(string.format("%d %%", v))
    end,
    set = function(v)
      pinValue:SetText(string.format("%d %%", ns.InstanceDisplay.SetPinScale(v)))
      placeAll()
    end,
    tooltip = "dmap.pinSize",
    tooltipText = "dmap.pinSize.tip",
  })
  pinSlider.fgName = function()
    return L["dmap.pinSize"]
  end
  pinSlider:SetPoint("LEFT", pinLabel, "RIGHT", GAP, 0)
  pinValue:SetPoint("LEFT", pinSlider, "RIGHT", GAP, 0)
  pinValue:SetWidth(PIN_VALUE_W)
  function pinGroup.Refresh()
    local percent = ns.InstanceDisplay.PinScale()
    pinSlider:Sync(percent)
    pinValue:SetText(string.format("%d %%", percent))
  end
  view = CreateFrame("Frame", nil, f)
  map = CreateFrame("Button", nil, view)
  map.fgName = function()
    return L["dmap.surface"]
  end
  W.Fill(map, "surface", 1)
  map:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mag = MG.Attach({
    viewport = view,
    canvas = map,
    barParent = map,
    views = { DMV.FLOOR_VIEW },
    view = function()
      return state.floors > 0 and DMV.FLOOR_VIEW or nil
    end,
    blocked = function()
      return f.zoomBlocked and f.zoomBlocked() or nil
    end,
    changed = applyZoom,
    moved = function() end,
  })
  f.mag = mag
  -- The keys go to the picture only while the pointer is on it and no text field has the focus.
  local keys = CreateFrame("Frame", nil, view)
  ns.PropagateKeys(keys, true)
  keys:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then
      return
    end
    local over = view:IsMouseOver() and not (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus())
    local _, handled = ns.Safe("dmap-key", function()
      return over and mag.Key(key)
    end)
    ns.PropagateKeys(self, not handled)
  end)
  keys:EnableKeyboard(true)
  f.keys = keys
  ns.On("PLAYER_REGEN_DISABLED", function()
    ns.PropagateKeys(keys, true)
  end)
  map:SetScript(
    "OnClick",
    ns.Wrap("dmap-map", function(_, button)
      -- The click that ends a drag of the picture is no click on the map.
      if mag.WasDrag() then
        return
      end
      -- A host can take the click (true = used) before the editor sees it.
      if f.onMapClick and f.onMapClick(button, cursorFraction()) then
        return
      end
      if button ~= "LeftButton" or not state.edit or not state.key then
        return
      end
      local x, y = cursorFraction()
      local floor = state.floor
      PD.Choose({ inst = state.key, floor = floor, floors = state.floors }, function(spec)
        place(spec, floor, x, y)
      end)
    end)
  )
  hint = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  info = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  soon = CreateFrame("Frame", nil, f)
  W.Fill(soon, "surface", 1)
  soon.pic = soon:CreateTexture(nil, "ARTWORK")
  soon.pic:SetAllPoints()
  soon.dim = soon:CreateTexture(nil, "OVERLAY")
  soon.dim:SetAllPoints()
  soon.dim:SetColorTexture(ns.Theme.scrim(0.65))
  soon.plate = CreateFrame("Frame", nil, soon)
  W.Fill(soon.plate, "surface", 0.92)
  W.Border(soon.plate, "accent2", 1, 1)
  soon.text = W.Text(soon.plate, { key = "dmap.soon", role = "h3", color = "text", justify = "CENTER", wrap = true })
  f.map, f.view, f.info, f.hint, f.soon, f.floorDrop = map, view, info, hint, soon, floorDrop
  f.entranceButton, f.pinSlider, f.pinGroup = entranceButton, pinSlider, pinGroup
  f.exportButton, f.importButton, f.editToggle = exportButton, importButton, editToggle
  f.routeToggle, f.routeDrop, f.roomToggle = routeToggle, routeDrop, roomToggle

  f:SetScript(
    "OnShow",
    ns.Wrap("dmap-show", function()
      render()
      if state.width then
        layout(state.width)
      end
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("dmap-hide", function()
      releaseAll()
    end)
  )
  render()
  return f
end
