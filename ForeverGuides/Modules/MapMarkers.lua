-- Free markers on the map page. A marker is a waypoint of ns.Waypoints (source "map", pinned),
-- there is no second data model: the pins read WP.List() and repaint on FG_WAYPOINTS_CHANGED.
-- This file owns the pins (one pool), the name field at the click point, the context menu, the
-- "Places | Markers" mode group and the side column section. MapPage.lua hands in the canvas
-- and the few things only it knows (active view, route setters) through the Attach context.
local _, ns = ...
local W, L, Theme, K, MW = ns.W, ns.L, ns.Theme, ns.PageKit, ns.MapWorld

local MM = {}
ns.MapMarkers = MM

MM.MODE_WIDTH = 284 -- 90 + 90 + 96 px buttons and two 4 px gaps
MM.PIN = 16
MM.FIELD_W, MM.FIELD_H = 170, 26
MM.HINT_MIN = 16 -- height of the Start/Goal hint line
MM.DONE_HEIGHT = 24 -- the Done button, a full click target
MM.HINT_INLINE_MIN = 120 -- narrower hint text moves the Done button below it

local PIN, RING = MM.PIN, 4
local LABEL_GAP, LABEL_MAX = 3, 120
local MENU_W, MENU_ROW, SWATCH, SWATCH_GAP = 214, 26, 24, 2
local SECTION_GAP = 6
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

ns.AddLocale("enUS", {
  ["map.mode.places"] = "Places",
  ["map.mode.placesTip"] = "Click a place to select it.",
  ["map.mode.markers"] = "Markers",
  ["map.mode.markersTip"] = "Left click: set marker. {key:mapMarker}: any mode.\nRight click on a marker: menu. Esc: cancel name.",
  ["map.mode.done"] = "Done",
  ["map.mode.route"] = "Start/Goal",
  ["map.mode.routeTip"] = "Click a place: start, next click: goal.\nEsc or Done ends the mode.",
  ["map.marker.heading"] = "Markers",
  ["map.marker.default"] = "Marker %d",
  ["map.marker.name"] = "Marker name",
  ["map.marker.noZone"] = "No zone here, click inside an area.",
  ["map.marker.noMap"] = "No game map for this zone, so no marker here.",
  ["map.marker.pos"] = "Position %s %%",
  ["map.marker.dist"] = "Distance %s",
  ["map.marker.hint"] = "Right click for the menu.",
  ["map.marker.rename"] = "Rename",
  ["map.marker.color"] = "Color",
  ["map.marker.pin"] = "Pin",
  ["map.marker.unpin"] = "Unpin",
  ["map.marker.arrow"] = "Make arrow",
  ["map.marker.asStart"] = "Set as start",
  ["map.marker.asDest"] = "Set as destination",
  ["map.marker.remove"] = "Remove",
  ["map.marker.empty"] = "No markers: use Markers mode or hold {mod:mapMarker}, then click.",
  ["map.marker.removeAll"] = "Remove all markers",
  ["map.marker.window"] = "Waypoint window",
  ["map.marker.confirm.title"] = "Remove all markers",
  ["map.marker.confirm.text"] = "Remove all markers?\nPermanent. Other waypoints stay.",
  ["map.marker.noneToRemove"] = "There are no map markers to remove.",
})

ns.AddLocale("deDE", {
  ["map.mode.places"] = "Orte",
  ["map.mode.placesTip"] = "Klicke einen Ort an, um ihn auszuwählen.",
  ["map.mode.markers"] = "Marker",
  ["map.mode.markersTip"] = "Linksklick: Marker setzen. {key:mapMarker}: jeder Modus.\nRechtsklick auf Marker: Menü. Esc: Namen abbrechen.",
  ["map.mode.done"] = "Beenden",
  ["map.mode.route"] = "Start/Ziel",
  ["map.mode.routeTip"] = "Klick auf Ort: Start, nächster Klick: Ziel.\nEsc oder Beenden schließt den Modus.",
  ["map.marker.heading"] = "Marker",
  ["map.marker.default"] = "Marker %d",
  ["map.marker.name"] = "Name des Markers",
  ["map.marker.noZone"] = "Hier keine Zone, klicke in ein Gebiet.",
  ["map.marker.noMap"] = "Keine Spielkarte für diese Zone, kein Marker möglich.",
  ["map.marker.pos"] = "Position %s %%",
  ["map.marker.dist"] = "Entfernung %s",
  ["map.marker.hint"] = "Rechtsklick öffnet das Menü.",
  ["map.marker.rename"] = "Umbenennen",
  ["map.marker.color"] = "Farbe",
  ["map.marker.pin"] = "Anheften",
  ["map.marker.unpin"] = "Lösen",
  ["map.marker.arrow"] = "Zum Pfeil machen",
  ["map.marker.asStart"] = "Als Start",
  ["map.marker.asDest"] = "Als Ziel",
  ["map.marker.remove"] = "Entfernen",
  ["map.marker.empty"] = "Keine Marker: Modus Marker oder {mod:mapMarker} halten, dann klicken.",
  ["map.marker.removeAll"] = "Alle Marker entfernen",
  ["map.marker.window"] = "Wegpunkt-Fenster",
  ["map.marker.confirm.title"] = "Alle Marker entfernen",
  ["map.marker.confirm.text"] = "Alle Marker entfernen?\nEndgültig. Fremde Wegpunkte bleiben.",
  ["map.marker.noneToRemove"] = "Es gibt keine Karten-Marker zum Entfernen.",
})

-- Pure logic ---------------------------------------------------------------------------

-- Label sides for pins in priority order. items[i] = { x, y, w, h } (pin centre and label size
-- in canvas pixels). A label goes to the right of its pin, else to the left, and only when it
-- stays inside the canvas and touches no other pin and no label that was accepted before it.
-- Pins that sit on its own pin (their discs overlap) do not count, or a stack of markers would
-- leave every label out. An item with skip = true gets no label but still blocks the others;
-- obstacles = { { x, y }, ... } are further pins (of the same radius) that no label may cover.
-- An item with force = true (a city) only avoids other forced pins and the labels taken before
-- it: a crowd of small pins around a city must not leave the city without its name.
-- Returns sides[i] = "right" | "left" | false.
local SIDES, NONE = { "right", "left" }, {}
function MM.PlanLabels(items, width, height, radius, gap, obstacles)
  local sides, taken = {}, {}
  local function hit(a, b)
    return a.l < b.r and b.l < a.r and a.t < b.b and b.t < a.b
  end
  local function onPin(rect, o)
    return hit(rect, { l = o.x - radius, r = o.x + radius, t = o.y - radius, b = o.y + radius })
  end
  for i, it in ipairs(items) do
    sides[i] = false
    for _, side in ipairs(it.skip and NONE or SIDES) do
      local l = side == "right" and it.x + radius + gap or it.x - radius - gap - it.w
      local rect = { l = l, r = l + it.w, t = it.y - it.h / 2, b = it.y + it.h / 2 }
      local ok = rect.l >= 0 and rect.r <= width and rect.t >= 0 and rect.b <= height
      if ok then
        for j, o in ipairs(items) do
          local stacked = math.abs(o.x - it.x) < 2 * radius and math.abs(o.y - it.y) < 2 * radius
          if j ~= i and not stacked and (o.force or not it.force) and onPin(rect, o) then
            ok = false
            break
          end
        end
        for _, o in ipairs(obstacles or NONE) do
          if onPin(rect, o) then
            ok = false
            break
          end
        end
      end
      if ok then
        for _, t in ipairs(taken) do
          if hit(rect, t) then
            ok = false
            break
          end
        end
      end
      if ok then
        taken[#taken + 1] = rect
        sides[i] = side
        break
      end
    end
  end
  return sides
end

-- Pin order: the active waypoint first, then by name (case-insensitive), then by id.
function MM.SortPins(items)
  table.sort(items, function(a, b)
    if a.active ~= b.active then
      return a.active
    end
    local na, nb = a.wp.title:lower(), b.wp.title:lower()
    if na ~= nb then
      return na < nb
    end
    return tostring(a.wp.id) < tostring(b.wp.id)
  end)
end

-- "Marker N" with the first N that no waypoint uses as its title yet.
function MM.DefaultName(list)
  local used = {}
  for _, wp in ipairs(list) do
    used[wp.title] = true
  end
  local n = 1
  for _, wp in ipairs(list) do
    if wp.source == "map" then
      n = n + 1
    end
  end
  while used[string.format(L["map.marker.default"], n)] do
    n = n + 1
  end
  return string.format(L["map.marker.default"], n)
end

-- Map id -> zone slug of a layout's maps.
local function reverse(maps)
  local rev = {}
  for slug, id in pairs(maps or {}) do
    rev[id] = slug
  end
  return rev
end

-- The cursor as fractions of a frame, or nil when the frame has no size yet.
local function cursorFraction(frame)
  local cx, cy = GetCursorPosition()
  local s = frame:GetEffectiveScale()
  local left, top, w, h = frame:GetLeft(), frame:GetTop(), frame:GetWidth(), frame:GetHeight()
  if not (left and top and w and h and w > 0 and h > 0 and s and s > 0) then
    return nil
  end
  return (cx / s - left) / w, (top - cy / s) / h
end
MM.CursorFraction = cursorFraction

-- Name field at a click point of a canvas frame, shared by the map page and the Blizzard
-- world map. Open(p, text, px, py): p = { kind = "new", map, x, y } or { kind = "rename", id },
-- (px, py) the field's top left corner in canvas pixels. Enter commits (adds the marker or
-- renames it), Esc or losing the focus drops the field unconfirmed.
function MM.NewField(canvas)
  local WP, WL = ns.Waypoints, ns.WaypointLogic
  local ctl = {}
  local field, pending

  local function closeField()
    pending = nil
    if field then
      field:Hide()
    end
  end
  ctl.Close = closeField

  function ctl.IsOpen()
    return pending ~= nil
  end

  function ctl.Frame()
    return field
  end

  local function commit(text)
    local p = pending
    if not p then
      return
    end
    closeField()
    text = WL.cleanTitle(text)
    if p.kind == "rename" then
      if text ~= "" then
        WP.Rename(p.id, text)
      end
      return
    end
    local list = WP.List()
    local wp, status = WP.Add({
      map = p.map,
      x = p.x,
      y = p.y,
      title = text ~= "" and text or MM.DefaultName(list),
      source = "map",
      pinned = true,
    })
    if not wp then
      if status == "full" then
        ns.Notify(string.format(L["wp.full"], WL.MAX), "warning")
      end
    elseif status == "duplicate" then
      ns.Notify(string.format(L["wp.duplicate"], wp.title), "info")
    else
      ns.Notify(string.format(L["wp.set"], wp.title, WL.coordText(wp.x, wp.y), WP.MapName(wp.map)), "success")
    end
  end

  local function buildField()
    local f = W.EditBox(canvas, { placeholder = "map.marker.name", onEnter = commit })
    f:SetWidth(MM.FIELD_W)
    f:SetFrameLevel(canvas:GetFrameLevel() + 300)
    f.edit:SetMaxLetters(WL.MAX_TITLE)
    -- Esc cancels, Tab must not leave the field, losing the focus drops the field unconfirmed.
    f.edit:SetScript("OnEscapePressed", ns.Wrap("map-marker-esc", closeField))
    f.edit:SetScript("OnTabPressed", function() end)
    f.edit:HookScript("OnEditFocusLost", function()
      closeField()
    end)
    f:Hide()
    return f
  end

  function ctl.Open(p, text, px, py)
    field = field or buildField()
    pending = p
    local x = math.max(0, math.min(px, canvas:GetWidth() - MM.FIELD_W))
    local y = math.max(0, math.min(py, canvas:GetHeight() - MM.FIELD_H))
    field:ClearAllPoints()
    field:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -y)
    field.edit:SetText(text)
    field:Show()
    field.edit:SetFocus()
    field.edit:HighlightText()
  end

  return ctl
end

-- Context menu of a waypoint (entries, then the color swatches). entries = { { id, key |
-- keyFor(wp), run(wp), shown(wp)? } }; the popup lives on the shared popup layer of the desktop.
-- Open(wp, anchor) shows it below anchor, Frame() is the popup (nil before the first Open).
function MM.NewMenu(entries)
  local WP, WL = ns.Waypoints, ns.WaypointLogic
  local ctl = {}
  local menu, menuId

  local function layer()
    return ns.Desktop.Layer
  end

  local function menuWaypoint()
    return menuId and WP.Get(menuId)
  end

  local function focusList()
    local out = {}
    for _, b in ipairs(menu.buttons) do
      if b:IsShown() then
        out[#out + 1] = b
      end
    end
    return out
  end

  local function moveMenuFocus(step)
    local list = focusList()
    local index = 0
    for i, b in ipairs(list) do
      if ns.Focus.current == b then
        index = i
      end
    end
    if #list == 0 then
      return
    end
    if index == 0 then
      index = step > 0 and 1 or #list
    else
      index = (index - 1 + step) % #list + 1
    end
    ns.Focus.set(list[index])
  end

  local function buildMenu()
    local p = layer().newPopup("surface2")
    p.buttons, p.byId, p.swatches = {}, {}, {}
    for _, entry in ipairs(entries) do
      local b = W.Button(p, {
        key = entry.key or "map.marker.pin",
        variant = "ghost",
        width = MENU_W - 4,
        height = MENU_ROW,
        onClick = function()
          local wp = menuWaypoint()
          layer().close("select")
          if wp then
            entry.run(wp)
          end
        end,
      })
      b.label:SetJustifyH("LEFT")
      p.buttons[#p.buttons + 1] = b
      p.byId[entry.id] = b
    end
    p.caption = W.Text(p, { key = "map.marker.color", role = "micro", color = "textSecondary" })
    for i, name in ipairs(WL.PALETTE) do
      local b = W.Button(p, {
        text = "",
        variant = "ghost",
        width = SWATCH,
        height = SWATCH,
        tooltip = "wp.color." .. name,
        onClick = function()
          local wp = menuWaypoint()
          layer().close("select")
          if wp then
            WP.SetColor(wp.id, name)
          end
        end,
      })
      b.edge = b:CreateTexture(nil, "BACKGROUND")
      b.edge:SetAllPoints()
      b.fill = b:CreateTexture(nil, "ARTWORK")
      b.fill:SetPoint("TOPLEFT", 4, -4)
      b.fill:SetPoint("BOTTOMRIGHT", -4, 4)
      b.colorName = name
      p.swatches[i] = b
      p.buttons[#p.buttons + 1] = b
    end
    p:SetWidth(MENU_W)
    p:EnableKeyboard(true)
    p:SetScript("OnKeyDown", function(self, key)
      local handled = true
      if key == "ESCAPE" then
        layer().close("escape")
      elseif key == "UP" or key == "DOWN" then
        moveMenuFocus(key == "DOWN" and 1 or -1)
      elseif key == "ENTER" or key == "SPACE" then
        ns.Focus.activate()
      else
        handled = false
      end
      ns.PropagateKeys(self, not handled)
    end)
    return p
  end

  function ctl.Open(wp, anchor)
    if not (wp and ns.Desktop and ns.Desktop.Layer) then
      return
    end
    menu = menu or buildMenu()
    menuId = wp.id
    local y = 2
    for _, entry in ipairs(entries) do
      local b = menu.byId[entry.id]
      local visible = not entry.shown or entry.shown(wp)
      b:SetShown(visible)
      if visible then
        if entry.keyFor then
          W.SetText(b.label, entry.keyFor(wp))
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -y)
        y = y + MENU_ROW
      end
    end
    menu.caption:ClearAllPoints()
    menu.caption:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -(y + 4))
    y = y + 20
    for i, b in ipairs(menu.swatches) do
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", menu, "TOPLEFT", 4 + (i - 1) * (SWATCH + SWATCH_GAP), -y)
      b.edge:SetColorTexture(Theme.color(b.colorName == wp.color and "text" or "surface2"))
      b.fill:SetColorTexture(Theme.color(b.colorName))
    end
    menu:SetHeight(y + SWATCH + 4)
    layer().open({ frames = { menu }, owner = anchor, move = moveMenuFocus })
    layer().place(menu, anchor, "TOPLEFT", "BOTTOMRIGHT", 2, 0)
    menu:Show()
    ns.Focus.set(focusList()[1])
  end

  function ctl.Frame()
    return menu
  end

  return ctl
end

-- Attach -------------------------------------------------------------------------------------
-- ctx = {
--   canvas, toolbar, side        frames of the page (side = { content, stack })
--   view()                       the map view under the canvas (layout or island view) or nil
--   maps()                       zone slug -> UiMapID of the whole layout
--   zoneName(slug)               localized zone name
--   placeFor(wp, zone)           nearest place slug of the marker's zone, or nil
--   setRoute(which, slug)        which = "start" | "dest"
--   relayout()                   lays the page out again
--   onClick(button)              optional, a click that was no marker click and hit no pin or place
--   hintText()                   optional, the hint line of the Start/Goal mode
--   routeModeChanged(on)         optional, the Start/Goal mode was switched
-- }
-- Returns the controller: modeRow, section, mode (marker mode), routeMode (Start/Goal mode),
-- SetMode, SetRouteMode, LayoutHint, done (the Done button of the Start/Goal mode), Paint, Click, OpenMenu, pins, Cancel (closes the name
-- field), FieldOpen. The two modes exclude each other.
function MM.Attach(ctx)
  local canvas = ctx.canvas
  local ctl = { pins = {}, rows = {}, mode = false, routeMode = false }
  local WP, WL = ns.Waypoints, ns.WaypointLogic

  local function zoneOfWaypoint(wp)
    return reverse(ctx.maps())[wp.map]
  end

  local function zoneText(wp)
    local slug = zoneOfWaypoint(wp)
    return (slug and ctx.zoneName(slug)) or WP.MapName(wp.map)
  end

  -- Many changes in a row (remove all) lay the page out once at the end.
  local muted
  local function relayout()
    if canvas:IsVisible() and not muted then
      ctx.relayout()
    end
  end

  -- Name field -------------------------------------------------------------------------
  local nameField = MM.NewField(canvas)
  local closeField, openField = nameField.Close, nameField.Open
  ctl.Cancel = closeField

  function ctl.FieldOpen()
    return nameField.IsOpen()
  end

  -- Placing ------------------------------------------------------------------------------
  local function place(nx, ny)
    local view = ctx.view()
    local zone, x, y = MW.PointToZone(view, nx, ny)
    if not zone then
      ns.Notify(L["map.marker.noZone"], "info")
      return
    end
    local map = view.maps and view.maps[zone]
    if not map then
      ns.Notify(L["map.marker.noMap"], "info")
      return
    end
    if #WP.List() >= WL.MAX then
      ns.Notify(string.format(L["wp.full"], WL.MAX), "warning")
      return
    end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    openField({ kind = "new", map = map, x = x, y = y }, MM.DefaultName(WP.List()), nx * w + 6, ny * h + 6)
  end

  -- True when the click was a marker click (marker mode or the marker key held): the caller then skips
  -- its own handling, so a place dot under the cursor does not swallow it.
  function ctl.Click(button)
    if button ~= "LeftButton" then
      return false
    end
    if not (ctl.mode or ns.Keys.Matches("mapMarker")) then
      return false
    end
    closeField()
    local nx, ny = cursorFraction(canvas)
    if nx and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
      place(nx, ny)
    end
    return true
  end
  canvas:EnableMouse(true)
  canvas:SetScript(
    "OnMouseUp",
    ns.Wrap("map-marker-click", function(_, button)
      if not ctl.Click(button) and ctx.onClick then
        ctx.onClick(button)
      end
    end)
  )

  function ctl.Field()
    return nameField.Frame()
  end

  -- Crosshair --------------------------------------------------------------------------------
  local cross = CreateFrame("Frame", nil, canvas)
  ctl.cross = cross
  cross:SetAllPoints()
  cross.h, cross.v = cross:CreateTexture(nil, "OVERLAY"), cross:CreateTexture(nil, "OVERLAY")
  -- The position under the cursor as zone percent, only on a zone view (view.zone is set).
  cross.back = cross:CreateTexture(nil, "ARTWORK")
  cross.coords = W.Text(cross, { role = "micro", color = "text" })
  cross.coords:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 8, 6)
  cross.back:SetPoint("TOPLEFT", cross.coords, "TOPLEFT", -4, 3)
  cross.back:SetPoint("BOTTOMRIGHT", cross.coords, "BOTTOMRIGHT", 4, -3)
  ns.Bind(cross, function(self)
    self.h:SetColorTexture(Theme.color("text", 0.5))
    self.v:SetColorTexture(Theme.color("text", 0.5))
    self.back:SetColorTexture(Theme.color("bg", 0.75))
  end)
  cross:SetScript("OnUpdate", function(self)
    local nx, ny = cursorFraction(canvas)
    local on = nx ~= nil and canvas:IsMouseOver() and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1
    self.h:SetShown(on)
    self.v:SetShown(on)
    local view = ctx.view()
    local coords = on and view and view.zone ~= nil
    self.coords:SetShown(coords)
    self.back:SetShown(coords)
    if coords then
      local text = string.format(L["map.marker.pos"], WL.coordText(nx, ny))
      if text ~= self.shownText then
        self.shownText = text
        W.SetText(self.coords, nil, text)
      end
    end
    if on then
      local w, h = canvas:GetWidth(), canvas:GetHeight()
      self.h:ClearAllPoints()
      self.h:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -ny * h)
      self.h:SetSize(w, 1)
      self.v:ClearAllPoints()
      self.v:SetPoint("TOPLEFT", canvas, "TOPLEFT", nx * w, 0)
      self.v:SetSize(1, h)
    end
  end)
  cross:Hide()

  -- Mode group ---------------------------------------------------------------------------------
  local FL = ns.FlowLayout
  local hint = W.Text(ctx.toolbar, { role = "ui", color = "textSecondary", wrap = true })
  hint:Hide()
  ctl.hint = hint
  ctl.done = W.Button(ctx.toolbar, {
    key = "map.mode.done",
    width = 70,
    height = MM.DONE_HEIGHT,
    onClick = function()
      ctl.SetRouteMode(false)
    end,
  })
  ctl.done:Hide()

  local function paintMode()
    for id, on in pairs({
      places = not ctl.mode and not ctl.routeMode,
      markers = ctl.mode,
      route = ctl.routeMode,
    }) do
      local b = ctl.modeRow:GetButton(id)
      b.bar:SetShown(on)
    end
    cross:SetShown(ctl.mode)
    hint:SetShown(ctl.routeMode)
    ctl.done:SetShown(ctl.routeMode)
  end

  local function setModes(marker, route)
    if ctl.mode == marker and ctl.routeMode == route then
      return
    end
    local routeChanged = ctl.routeMode ~= route
    ctl.mode, ctl.routeMode = marker, route
    closeField()
    paintMode()
    if routeChanged and ctx.routeModeChanged then
      ctx.routeModeChanged(route)
    end
    relayout()
  end

  function ctl.SetMode(on)
    on = on and true or false
    setModes(on, ctl.routeMode and not on)
  end

  function ctl.SetRouteMode(on)
    on = on and true or false
    setModes(ctl.mode and not on, on)
  end

  -- Places the hint line of the Start/Goal mode at y px below the toolbar top and returns the
  -- height it takes (0 when the mode is off). The Done button sits right of the text, or below it
  -- when the width is too small for both; the text wraps instead of running under the button.
  function ctl.LayoutHint(width, y)
    hint:SetShown(ctl.routeMode)
    ctl.done:SetShown(ctl.routeMode)
    if not ctl.routeMode then
      return 0
    end
    W.SetText(hint, nil, ctx.hintText and ctx.hintText() or "")
    local doneW = math.min(width, math.max(70, math.ceil(ctl.done.label:GetStringWidth()) + 24))
    local doneH = MM.DONE_HEIGHT
    local textW = width - doneW - 8
    ctl.done:SetSize(doneW, doneH)
    hint:ClearAllPoints()
    ctl.done:ClearAllPoints()
    if textW >= MM.HINT_INLINE_MIN then
      hint:SetWidth(textW)
      local textH = math.max(MM.HINT_MIN, math.ceil(hint:GetStringHeight()))
      local lineH = math.max(doneH, textH)
      hint:SetPoint("TOPLEFT", ctx.toolbar, "TOPLEFT", 0, -(y + math.floor((lineH - textH) / 2)))
      ctl.done:SetPoint("TOPLEFT", ctx.toolbar, "TOPLEFT", math.min(math.ceil(hint:GetStringWidth()), textW) + 8, -y)
      return lineH
    end
    hint:SetWidth(width)
    local textH = math.max(MM.HINT_MIN, math.ceil(hint:GetStringHeight()))
    hint:SetPoint("TOPLEFT", ctx.toolbar, "TOPLEFT", 0, -y)
    ctl.done:SetPoint("TOPLEFT", ctx.toolbar, "TOPLEFT", 0, -(y + textH + 4))
    return textH + 4 + doneH
  end

  ctl.modeRow = FL.ButtonRow(ctx.toolbar, {
    {
      id = "places",
      key = "map.mode.places",
      width = 90,
      tooltip = "map.mode.places",
      tooltipText = "map.mode.placesTip",
      onClick = function()
        setModes(false, false)
      end,
    },
    {
      id = "markers",
      key = "map.mode.markers",
      width = 90,
      tooltip = "map.mode.markers",
      tooltipText = "map.mode.markersTip",
      onClick = function()
        ctl.SetMode(true)
      end,
    },
    {
      id = "route",
      key = "map.mode.route",
      width = 96,
      tooltip = "map.mode.route",
      tooltipText = "map.mode.routeTip",
      onClick = function()
        ctl.SetRouteMode(true)
      end,
    },
  }, { gap = 4 })
  for _, id in ipairs({ "places", "markers", "route" }) do
    local b = ctl.modeRow:GetButton(id)
    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
    b.bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.bar:SetHeight(2)
    ns.Bind(b.bar, function(t)
      t:SetColorTexture(Theme.color("accent2"))
    end)
  end
  paintMode()

  -- Context menu -----------------------------------------------------------------------------
  -- Where the name field for a rename sits: at the pin when it is on the map, else the corner.
  local function renameAt(wp)
    local view = ctx.view()
    local zone = zoneOfWaypoint(wp)
    local nx, ny = MW.ZoneToPoint(view, zone, wp.x, wp.y)
    local px, py = 8, 8
    if nx then
      px, py = nx * canvas:GetWidth() + 6, ny * canvas:GetHeight() + 6
    end
    openField({ kind = "rename", id = wp.id }, wp.title, px, py)
  end

  local ENTRIES = {
    {
      id = "rename",
      key = "map.marker.rename",
      run = renameAt,
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
    {
      id = "arrow",
      key = "map.marker.arrow",
      run = function(wp)
        if WP.Activate(wp.id) then
          ns.Notify(string.format(L["wp.activated"], wp.title), "info")
        end
      end,
    },
    {
      id = "start",
      key = "map.marker.asStart",
      shown = function(wp)
        return ctx.placeFor(wp, zoneOfWaypoint(wp)) ~= nil
      end,
      run = function(wp)
        ctx.setRoute("start", ctx.placeFor(wp, zoneOfWaypoint(wp)))
      end,
    },
    {
      id = "dest",
      key = "map.marker.asDest",
      shown = function(wp)
        return ctx.placeFor(wp, zoneOfWaypoint(wp)) ~= nil
      end,
      run = function(wp)
        ctx.setRoute("dest", ctx.placeFor(wp, zoneOfWaypoint(wp)))
      end,
    },
    {
      id = "remove",
      key = "map.marker.remove",
      run = function(wp)
        WP.Remove(wp.id)
      end,
    },
  }

  local menuCtl = MM.NewMenu(ENTRIES)

  -- Opens the menu of a waypoint below anchor (a pin or a list row).
  function ctl.OpenMenu(wp, anchor)
    menuCtl.Open(wp, anchor)
  end

  function ctl.Menu()
    return menuCtl.Frame()
  end

  -- Pins -------------------------------------------------------------------------------------
  local function tipFor(wp)
    local lines = { zoneText(wp), string.format(L["map.marker.pos"], WL.coordText(wp.x, wp.y)) }
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

  local function activate(wp)
    if WP.Activate(wp.id) then
      ns.Notify(string.format(L["wp.activated"], wp.title), "info")
    end
  end

  local function newPin()
    local pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(PIN, PIN)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin.ring = pin:CreateTexture(nil, "BACKGROUND")
    pin.ring:SetTexture(DISC)
    pin.ring:SetPoint("CENTER")
    pin.ring:SetSize(PIN + 2 * RING, PIN + 2 * RING)
    pin.edge = pin:CreateTexture(nil, "BORDER")
    pin.edge:SetTexture(DISC)
    pin.edge:SetPoint("CENTER")
    pin.edge:SetSize(PIN + 2, PIN + 2)
    pin.fill = pin:CreateTexture(nil, "ARTWORK")
    pin.fill:SetTexture(DISC)
    pin.fill:SetAllPoints()
    pin.label = W.Text(pin, { role = "micro", color = "text" })
    pin:SetScript("OnEnter", function(self)
      local wp = self.wpId and WP.Get(self.wpId)
      if wp then
        ns.ShowTooltip(self, wp.title, tipFor(wp))
      end
    end)
    pin:SetScript("OnLeave", ns.HideTooltip)
    pin:SetScript(
      "OnClick",
      ns.Wrap("map-marker-pin", function(self, button)
        local wp = self.wpId and WP.Get(self.wpId)
        if not wp then
          return
        end
        if button == "RightButton" then
          ctl.OpenMenu(wp, self)
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

  -- The waypoints that are on the current view, as { wp, x, y, active } in canvas pixels.
  local function pinItems()
    local view = ctx.view()
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local items = {}
    if view and cw > 0 and ch > 0 then
      local rev = reverse(ctx.maps())
      local active = WP.data().active
      for _, wp in ipairs(WP.List()) do
        local nx, ny = MW.ZoneToPoint(view, rev[wp.map], wp.x, wp.y)
        if nx then
          items[#items + 1] = { wp = wp, x = nx * cw, y = ny * ch, active = wp.id == active }
        end
      end
    end
    return items
  end

  -- Pixel positions { x, y } of the marker pins, so labels of the places keep clear of them.
  function ctl.Points()
    local out = {}
    for i, it in ipairs(pinItems()) do
      out[i] = { x = it.x, y = it.y }
    end
    return out
  end

  -- Repaints every pin from the waypoint list; pins come from the pool, labels from the plan.
  function ctl.Paint()
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local items = pinItems()
    MM.SortPins(items)
    local base = canvas:GetFrameLevel() + 20
    for i, it in ipairs(items) do
      local pin = ctl.pins[i]
      if not pin then
        pin = newPin()
        ctl.pins[i] = pin
      end
      pin.wpId, pin.colorName = it.wp.id, it.wp.color
      pin:SetFrameLevel(base + #items - i)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", canvas, "TOPLEFT", it.x, -it.y)
      pin.fill:SetVertexColor(Theme.color(it.wp.color))
      pin.ring:SetShown(it.active)
      W.SetText(pin.label, nil, it.wp.title)
      it.w, it.h = math.min(math.ceil(pin.label:GetStringWidth()), LABEL_MAX), math.ceil(pin.label:GetStringHeight())
      pin:Show()
    end
    for i = #items + 1, #ctl.pins do
      ctl.pins[i].wpId = nil
      ctl.pins[i]:Hide()
    end
    local sides = MM.PlanLabels(items, cw, ch, PIN / 2 + 2, LABEL_GAP)
    for i, it in ipairs(items) do
      local label, side = ctl.pins[i].label, sides[i]
      label:SetShown(side ~= false)
      if side then
        label:SetWidth(it.w)
        label:ClearAllPoints()
        if side == "right" then
          label:SetPoint("LEFT", ctl.pins[i], "CENTER", PIN / 2 + LABEL_GAP, 0)
          label:SetJustifyH("LEFT")
        else
          label:SetPoint("RIGHT", ctl.pins[i], "CENTER", -(PIN / 2 + LABEL_GAP), 0)
          label:SetJustifyH("RIGHT")
        end
      end
    end
  end

  -- Side section ---------------------------------------------------------------------------------
  local section = CreateFrame("Frame", nil, ctx.side.content)
  K.Anchor("FG.Map.Markers", section)
  ctl.section, ctl.open = section, true
  local rowH = K.scaledHeight(26)

  local head = W.Button(section, {
    text = "",
    variant = "ghost",
    height = rowH,
    onClick = function()
      ctl.open = not ctl.open
      ctx.relayout()
    end,
  })
  head.label:SetJustifyH("LEFT")
  local empty = W.Text(section, { key = "map.marker.empty", role = "ui", color = "textMuted", wrap = true })

  local function newRow()
    local row = CreateFrame("Button", nil, section)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(10, 10)
    row.dot:SetPoint("LEFT", 6, 0)
    row.zone = W.Text(row, { role = "ui", color = "textSecondary", justify = "RIGHT" })
    row.zone:SetPoint("RIGHT", -6, 0)
    row.name = W.Text(row, { role = "ui", color = "text" })
    row.name:SetPoint("LEFT", 22, 0)
    row.name:SetPoint("RIGHT", row.zone, "LEFT", -6, 0)
    row:SetScript("OnEnter", function(self)
      self.hl:SetColorTexture(1, 1, 1, 0.08)
      local wp = self.wpId and WP.Get(self.wpId)
      if wp then
        ns.ShowTooltip(self, wp.title, tipFor(wp))
      end
    end)
    row:SetScript("OnLeave", function(self)
      self.hl:SetColorTexture(1, 1, 1, 0)
      ns.HideTooltip()
    end)
    row:SetScript(
      "OnClick",
      ns.Wrap("map-marker-row", function(self, button)
        local wp = self.wpId and WP.Get(self.wpId)
        if not wp then
          return
        end
        if button == "RightButton" then
          ctl.OpenMenu(wp, self)
        else
          activate(wp)
        end
      end)
    )
    ns.Focus.register(row, function(self)
      self:Click()
    end)
    return row
  end

  local function mapMarkers()
    local out = {}
    for _, wp in ipairs(WP.List()) do
      if wp.source == "map" then
        out[#out + 1] = wp
      end
    end
    return out
  end

  ctl.buttons = FL.ButtonRow(section, {
    {
      id = "removeAll",
      label = "act.clear",
      icon = "trash",
      tooltip = "map.marker.removeAll",
      width = 150,
      onClick = function()
        if #mapMarkers() == 0 then
          ns.Notify(L["map.marker.noneToRemove"], "info")
          return
        end
        ns.Dialogs.Confirm("map.marker.confirm.title", "map.marker.confirm.text", function()
          local removed = 0
          muted = true
          for _, wp in ipairs(mapMarkers()) do
            if WP.Remove(wp.id, true) then
              removed = removed + 1
            end
          end
          muted = false
          relayout()
          ns.Notify(string.format(L["wp.cleared"], removed), "info")
        end)
      end,
    },
    {
      id = "window",
      label = "act.open",
      icon = "open",
      tooltip = "map.marker.window",
      width = 130,
      onClick = function()
        ns.WaypointList.Open()
      end,
    },
  })

  function section:fgGridLayout(width)
    local list = WP.List()
    W.SetText(head.label, nil, string.format("%s %s (%d)", ctl.open and "v" or ">", L["map.marker.heading"], #list))
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", self, "TOPLEFT")
    head:SetSize(width, rowH)
    local y = rowH + 4
    local rev = reverse(ctx.maps())
    for i, wp in ipairs(list) do
      local row = ctl.rows[i]
      if not row then
        row = newRow()
        ctl.rows[i] = row
      end
      row:SetShown(ctl.open)
      if ctl.open then
        local active = WP.data().active == wp.id
        row.wpId = wp.id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        row:SetSize(width, rowH)
        row.dot:SetColorTexture(Theme.color(wp.color))
        W.SetText(row.name, nil, (active and "> " or "") .. wp.title)
        local slug = rev[wp.map]
        W.SetText(row.zone, nil, (slug and ctx.zoneName(slug)) or WP.MapName(wp.map))
        row.zone:SetWidth(math.floor(width * 0.4))
        y = y + rowH
      end
    end
    for i = #list + 1, #ctl.rows do
      ctl.rows[i].wpId = nil
      ctl.rows[i]:Hide()
    end
    empty:SetShown(ctl.open and #list == 0)
    if ctl.open and #list == 0 then
      empty:ClearAllPoints()
      empty:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      empty:SetWidth(width)
      y = y + math.ceil(empty:GetStringHeight()) + SECTION_GAP
    end
    ctl.buttons:SetShown(ctl.open)
    if ctl.open then
      y = y + SECTION_GAP
      ctl.buttons:ClearAllPoints()
      ctl.buttons:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      ctl.buttons:SetWidth(width)
      y = y + ctl.buttons:fgGridLayout(width)
    end
    self:SetHeight(y)
    return y
  end
  ctx.side.stack:Add(section, { gap = SECTION_GAP })

  ns.On("FG_WAYPOINTS_CHANGED", relayout)
  ns.On("FG_UI_REFRESHED", relayout)
  return ctl
end
