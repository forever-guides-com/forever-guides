-- Zone zoom of the map page. A click on a zone of the world view opens the zone's own map
-- (MW.ZoneView): same canvas, same height, the zone's art over the whole map, places and markers
-- in zone coordinates. This file owns the state (which zone), the hover highlight of the world
-- view and of the areas around an open zone (their name, outline and a click that opens them),
-- the path bar with its list of those areas and the keys that lead back. MapPage.lua hands in the canvas and the few
-- things only it knows through the Attach context.
local _, ns = ...
local W, L, Theme, MW, MM, MP = ns.W, ns.L, ns.Theme, ns.MapWorld, ns.MapMarkers, ns.MapPoly

local MZ = {}
ns.MapZoom = MZ

MZ.BAR_H = 28
MZ.HOVER_INTERVAL = 0.05
MZ.MAX_OUTLINE_LINES = 200
MZ.OUTLINE_THICKNESS = 2

MZ.FOCUS_SECONDS = 4

local BUTTON_W, BUTTON_H = 72, 24
local NEAR_W = 150
local NEAR_LIST_W = 240
local FLAT_PAD = 24
local FOCUS_SIZE, FOCUS_CORE = 32, 10
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

ns.AddLocale("enUS", {
  ["map.zoom.world"] = "World",
  ["map.zoom.back"] = "Back",
  ["map.zoom.backTip"] = "Back to the world map.\nRight click, Backspace or Esc works too.",
  ["map.zoom.open"] = "Click to open the map of this area.",
  ["map.zoom.levels"] = "Levels %d-%d",
  ["map.zoom.near"] = "Nearby areas",
  ["map.zoom.nearTip"] = "Opens the map of an area around this one.\nA click on the area in the map works too.",
  ["map.zoom.noMap"] = "There is no map of its own for this area.",
  ["map.zoom.places"] = "Places: %d",
  ["map.zoom.markers"] = "Markers: %d",
  ["map.zoom.estimated"] = "Estimated position",
  ["map.zoom.noArt"] = "No map image for this zone",
  ["map.zoom.noArtHint"] = "No image for this zone, places and markers still work.",
  ["map.focus.default"] = "Focus point",
  ["map.focus.hint"] = "Click to set a waypoint here.",
})

ns.AddLocale("deDE", {
  ["map.zoom.world"] = "Welt",
  ["map.zoom.back"] = "Zurück",
  ["map.zoom.backTip"] = "Zurück zur Weltkarte.\nRechtsklick, Backspace oder Esc geht auch.",
  ["map.zoom.open"] = "Klicke, um die Karte dieses Gebiets zu öffnen.",
  ["map.zoom.levels"] = "Stufen %d-%d",
  ["map.zoom.near"] = "Nachbargebiete",
  ["map.zoom.nearTip"] = "Öffnet die Karte eines Gebiets rund um dieses.\nEin Klick auf das Gebiet in der Karte geht auch.",
  ["map.zoom.noMap"] = "Für dieses Gebiet gibt es keine eigene Karte.",
  ["map.zoom.places"] = "Orte: %d",
  ["map.zoom.markers"] = "Marker: %d",
  ["map.zoom.estimated"] = "Geschätzte Position",
  ["map.zoom.noArt"] = "Kein Kartenbild für diese Zone",
  ["map.zoom.noArtHint"] = "Kein Bild für diese Zone, Orte und Marker gehen trotzdem.",
  ["map.focus.default"] = "Fokuspunkt",
  ["map.focus.hint"] = "Klicke, um hier einen Wegpunkt zu setzen.",
})

-- ctx = {
--   canvas
--   base()                  the view the zoom starts from (layout or island view) or nil
--   data()                  the travel data
--   zoneName(slug)          localized zone name
--   levels(slug)            lmin, lmax of the zone, nil for zones without a level range
--   placeCount(slug)        number of places in the zone
--   markerCount(mapId)      number of markers on the game map
--   markers                 the MapMarkers controller (name field, marker mode)
--   changed()               lays the page out again after the zone changed
--   over()                  optional: true while the cursor is over the visible map (a magnified
--                           canvas reaches beyond its clipping frame)
--   frame                   optional: the frame the path bar sits on (the clipping viewport of a
--                           magnified canvas), default the canvas
--   zoomKey(key)            optional: true when the key zoomed or moved the open zone (ctl.Key
--                           asks for it while the pointer is on the map)
-- }
-- Returns the controller: Enter, Leave, Reset, Click, View, Art, Zone, Paint, Focus, bar, hover.
function MZ.Attach(ctx)
  local canvas = ctx.canvas
  local ctl = {}

  local function hideTip()
    if ctl.tipShown then
      ctl.tipShown = false
      ns.HideTooltip()
    end
  end

  -- Hover highlight ----------------------------------------------------------------------
  -- World view: a zone with an outline gets its outline as a line loop from a pool of its own, set
  -- once per zone or canvas size change; a zone without one keeps the filled rectangle. Open zone:
  -- the areas around it get their outline only.
  local hover = CreateFrame("Frame", nil, canvas)
  hover:SetFrameLevel(canvas:GetFrameLevel() + 1)
  hover.fill = hover:CreateTexture(nil, "ARTWORK")
  hover.fill:SetAllPoints()
  local hoverLines, linesUsed = {}, 0
  ctl.outlineBuilds = 0
  local function hoverColor(noMap, alpha)
    return Theme.color(noMap and "textMuted" or "accent2", alpha)
  end
  ns.Bind(hover, function(self)
    self.fill:SetColorTexture(hoverColor(self.noMap, self.noMap and 0.18 or 0.28))
    for i = 1, linesUsed do
      hoverLines[i]:SetColorTexture(hoverColor(self.noMap, 0.95))
    end
  end)
  hover:Hide()
  ctl.hover = hover
  ctl.hoverLines = hoverLines

  local function hideOutline()
    for i = 1, linesUsed do
      hoverLines[i]:Hide()
    end
    linesUsed = 0
  end

  -- Draws the closed rings as lines over the canvas, cut off at its edge instead of pulled onto it
  -- (outlines may reach past the map); true when a line is visible.
  local function drawOutline(shape, cw, ch)
    hideOutline()
    if not (shape and hover.CreateLine) then
      return false
    end
    ctl.outlineBuilds = ctl.outlineBuilds + 1
    for _, flat in ipairs(MP.Outline(shape, MZ.MAX_OUTLINE_LINES)) do
      local n = #flat / 2
      for i = 1, n do
        local j = i % n + 1
        local x1, y1, x2, y2 = MP.ClipSegment(flat[2 * i - 1], flat[2 * i], flat[2 * j - 1], flat[2 * j])
        if x1 then
          local line = hoverLines[linesUsed + 1]
          if not line then
            line = hover:CreateLine(nil, "ARTWORK")
            line:SetThickness(MZ.OUTLINE_THICKNESS)
            hoverLines[linesUsed + 1] = line
          end
          linesUsed = linesUsed + 1
          line:SetColorTexture(hoverColor(hover.noMap, 0.95))
          line:SetStartPoint("TOPLEFT", canvas, x1 * cw, -y1 * ch)
          line:SetEndPoint("TOPLEFT", canvas, x2 * cw, -y2 * ch)
          line:Show()
        end
      end
    end
    return linesUsed > 0
  end

  -- Tooltip text of a zone under the cursor: the world view counts places and markers, the areas
  -- around an open zone give their level range.
  local function tipText(slug, mapId, around)
    local lines = {}
    if around then
      local lmin, lmax = ctx.levels(slug)
      if lmin then
        lines[#lines + 1] = string.format(L["map.zoom.levels"], lmin, lmax or lmin)
      end
    else
      lines[#lines + 1] = string.format(L["map.zoom.places"], ctx.placeCount(slug))
      lines[#lines + 1] = string.format(L["map.zoom.markers"], mapId and ctx.markerCount(mapId) or 0)
    end
    lines[#lines + 1] = Theme.hexText("textMuted", mapId and L["map.zoom.open"] or L["map.zoom.noMap"])
    return table.concat(lines, "\n")
  end

  -- view: the world view or the surroundings of the open zone (around), both hold the zone's
  -- rectangle, map and outline.
  local function showHover(slug, view, around)
    local r = view.zones[slug]
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local mapId = view.maps and view.maps[slug]
    -- The lines are placed in pixels, so a new canvas size draws them again.
    if ctl.hoverZone ~= slug or ctl.hoverW ~= cw or ctl.hoverH ~= ch then
      hover.noMap = mapId == nil
      hover.fill:SetColorTexture(hoverColor(hover.noMap, hover.noMap and 0.18 or 0.28))
      ctl.outlined = drawOutline(MP.Shape(view, slug), cw, ch)
      hover.fill:SetShown(not (ctl.outlined or around))
      ctl.hoverW, ctl.hoverH = cw, ch
    end
    hover:ClearAllPoints()
    if ctl.outlined or around then
      hover:SetAllPoints(canvas)
    else
      hover:SetPoint("TOPLEFT", canvas, "TOPLEFT", r.left * cw, -r.top * ch)
      hover:SetSize((r.right - r.left) * cw, (r.bottom - r.top) * ch)
    end
    hover:Show()
    if ctl.hoverZone ~= slug or not (GameTooltip and GameTooltip:IsShown()) then
      ns.ShowTooltip(hover, ctx.zoneName(slug) or slug, tipText(slug, mapId, around), { anchor = "ANCHOR_CURSOR" })
      ctl.tipShown = true
    end
    ctl.hoverZone = slug
  end

  local function clearHover()
    if ctl.hoverZone then
      ctl.hoverZone = nil
      hideOutline()
      hover:Hide()
      hideTip()
    end
  end

  -- The cursor as a point of the canvas (fractions), nil when it is off the map or on the path bar
  -- (which lies over the top of the map).
  local function cursorPoint()
    local nx, ny = MM.CursorFraction(canvas)
    local over
    if ctx.over then
      over = ctx.over()
    else
      over = canvas:IsMouseOver()
    end
    if not (nx and over) or (ctl.zv and ctl.bar:IsMouseOver()) then
      return nil
    end
    return nx, ny
  end

  -- The zone under the cursor of a view, nil when the cursor is off the map.
  local function zoneAtCursor(view)
    local nx, ny = cursorPoint()
    return view and nx and (MW.PointToZone(view, nx, ny)) or nil
  end

  -- The area around the open zone under the cursor, nil over the zone itself.
  local function neighborAtCursor()
    local nx, ny = cursorPoint()
    return nx and MW.NeighborAt(ctl.zv, nx, ny) or nil
  end

  -- One test per tick, never a rebuild: the frame moves and the tooltip changes only when the
  -- zone under the cursor changes.
  function ctl.UpdateHover()
    local zv = ctl.zv
    local view = zv and zv.around or ctx.base()
    local slug
    if zv then
      slug = neighborAtCursor()
    else
      slug = view and zoneAtCursor(view)
    end
    if slug then
      showHover(slug, view, zv ~= nil)
    else
      clearHover()
    end
  end

  local elapsed = 0
  canvas:HookScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed >= MZ.HOVER_INTERVAL then
      elapsed = 0
      ctl.UpdateHover()
    end
  end)

  -- State ---------------------------------------------------------------------------------
  function ctl.View()
    return ctl.zv
  end

  function ctl.Zone()
    return ctl.zv and ctl.zv.zone
  end

  -- The art of the zone's game map, nil when the game gives none.
  function ctl.Art()
    return ctl.art or nil
  end

  -- Focus marker ----------------------------------------------------------------------------
  -- A pulsing point on the open zone for a position handed in by another page (a trainer's
  -- spot). It goes away after MZ.FOCUS_SECONDS, on the next click on the map or when the zone
  -- changes; a click on it sets a waypoint there.
  local focus = CreateFrame("Button", nil, canvas)
  focus:SetSize(FOCUS_SIZE, FOCUS_SIZE)
  focus:SetFrameLevel(canvas:GetFrameLevel() + 30)
  focus.pulse = focus:CreateTexture(nil, "BACKGROUND")
  focus.pulse:SetTexture(DISC)
  focus.pulse:SetPoint("CENTER")
  focus.edge = focus:CreateTexture(nil, "BORDER")
  focus.edge:SetTexture(DISC)
  focus.edge:SetPoint("CENTER")
  focus.edge:SetSize(FOCUS_CORE + 4, FOCUS_CORE + 4)
  focus.core = focus:CreateTexture(nil, "ARTWORK")
  focus.core:SetTexture(DISC)
  focus.core:SetPoint("CENTER")
  focus.core:SetSize(FOCUS_CORE, FOCUS_CORE)
  ns.Bind(focus, function(self)
    self.pulse:SetVertexColor(Theme.color("accent", 0.45))
    self.edge:SetVertexColor(Theme.color("bg", 0.9))
    self.core:SetVertexColor(Theme.color("accent"))
  end)
  focus:Hide()
  ctl.focusFrame = focus

  function ctl.ClearFocus()
    if ctl.focus then
      ctl.focus = nil
      focus:Hide()
      hideTip()
    end
  end

  -- Puts the focus on a zone position (fractions 0..1); false when no zone is open or the
  -- position is not a pair of fractions.
  function ctl.Focus(x, y, label)
    local zv = ctl.zv
    if not (zv and type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
      return false
    end
    ctl.focus = {
      x = x,
      y = y,
      label = label,
      title = label or L["map.focus.default"],
      expires = GetTime() + MZ.FOCUS_SECONDS,
    }
    ctl.PaintFocus()
    return true
  end

  function ctl.PaintFocus()
    local f, zv = ctl.focus, ctl.zv
    local nx, ny
    if f and zv then
      nx, ny = MW.ZoneToPoint(zv, zv.zone, f.x, f.y)
    end
    if not nx then
      focus:Hide()
      return
    end
    focus:ClearAllPoints()
    focus:SetPoint("CENTER", canvas, "TOPLEFT", nx * canvas:GetWidth(), -ny * canvas:GetHeight())
    focus:Show()
  end

  focus:SetScript("OnUpdate", function(self, dt)
    local f = ctl.focus
    if not f then
      return
    end
    if GetTime() >= f.expires then
      ctl.ClearFocus()
      return
    end
    f.age = (f.age or 0) + (tonumber(dt) or 0)
    local phase = (f.age % 1.2) / 1.2
    local size = FOCUS_CORE + (FOCUS_SIZE - FOCUS_CORE) * phase
    self.pulse:SetSize(size, size)
    self.pulse:SetAlpha(1 - phase)
  end)
  focus:SetScript("OnEnter", function(self)
    local f = ctl.focus
    if f then
      ctl.tipShown = true
      ns.ShowTooltip(self, f.title, Theme.hexText("textMuted", L["map.focus.hint"]))
    end
  end)
  focus:SetScript("OnLeave", hideTip)
  focus:SetScript(
    "OnClick",
    ns.Wrap("map-focus-click", function()
      local f, zv = ctl.focus, ctl.zv
      if f and zv then
        ns.Waypoints.Command({ map = zv.mapId, x = f.x, y = f.y, title = f.title })
      end
      ctl.ClearFocus()
    end)
  )

  -- Path bar and flat surface -------------------------------------------------------------
  local bar = CreateFrame("Frame", nil, canvas)
  bar:SetPoint("TOPLEFT", ctx.frame or canvas, "TOPLEFT")
  bar:SetPoint("TOPRIGHT", ctx.frame or canvas, "TOPRIGHT")
  bar:SetHeight(MZ.BAR_H)
  bar:SetFrameLevel(canvas:GetFrameLevel() + 200)
  bar.fill = bar:CreateTexture(nil, "BACKGROUND")
  bar.fill:SetAllPoints()
  ns.Bind(bar, function(self)
    self.fill:SetColorTexture(Theme.color("bg", 0.85))
  end)
  bar.back = W.Action(bar, {
    label = "act.back",
    icon = "chevron-left",
    variant = "ghost",
    width = BUTTON_W,
    height = BUTTON_H,
    tooltip = "map.zoom.back",
    tooltipText = "map.zoom.backTip",
    onClick = function()
      ctl.Leave()
    end,
  })
  bar.back:SetPoint("LEFT", bar, "LEFT", 2, 0)
  bar.world = W.Action(bar, {
    label = "act.world",
    icon = "map",
    tooltip = "map.zoom.world",
    variant = "ghost",
    width = BUTTON_W,
    height = BUTTON_H,
    onClick = function()
      ctl.Leave()
    end,
  })
  bar.world:SetPoint("LEFT", bar.back, "RIGHT", 4, 0)
  bar.sep = W.Text(bar, { text = ">", role = "ui", color = "textMuted" })
  bar.sep:SetPoint("LEFT", bar.world, "RIGHT", 4, 0)
  -- The list of the areas around the open zone for those who do not point: a button that opens
  -- the list of an invisible dropdown (the options are refilled whenever a zone opens).
  local nearOptions = {}
  local nearList = W.Dropdown(bar, {
    options = nearOptions,
    width = NEAR_LIST_W,
    get = function() end,
    set = function(slug)
      ctl.Enter(slug)
    end,
  })
  nearList:Hide()
  bar.near = W.Action(bar, {
    key = "map.zoom.near",
    icon = "chevron-down",
    variant = "ghost",
    width = NEAR_W,
    height = BUTTON_H,
    tooltip = "map.zoom.near",
    tooltipText = "map.zoom.nearTip",
    onClick = function()
      nearList:Open(bar.near)
    end,
  })
  bar.near:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
  bar.name = W.Text(bar, { role = "ui", color = "text" })
  bar.name:SetPoint("LEFT", bar.sep, "RIGHT", 6, 0)
  bar.name:SetPoint("RIGHT", bar.near, "LEFT", -8, 0)
  bar:Hide()
  ctl.bar = bar

  local flat = CreateFrame("Frame", nil, canvas)
  flat:SetAllPoints()
  flat:SetFrameLevel(canvas:GetFrameLevel() + 1)
  flat.fill = flat:CreateTexture(nil, "BACKGROUND")
  flat.fill:SetAllPoints()
  ns.Bind(flat, function(self)
    self.fill:SetColorTexture(Theme.color("surface2", 1))
  end)
  flat.name = W.Text(flat, { role = "h2", family = "heading", color = "textSecondary", justify = "CENTER" })
  flat.hint =
    W.Text(flat, { key = "map.zoom.noArtHint", role = "ui", color = "textMuted", justify = "CENTER", wrap = true })
  flat:Hide()
  ctl.flat = flat

  local function fillNearOptions(zv)
    for i = #nearOptions, 1, -1 do
      nearOptions[i] = nil
    end
    for _, slug in ipairs(zv.neighbors) do
      -- Only areas with a map of their own can be opened.
      if zv.around.maps[slug] then
        local name = ctx.zoneName(slug) or slug
        local lmin, lmax = ctx.levels(slug)
        nearOptions[#nearOptions + 1] = {
          value = slug,
          text = lmin and string.format("%s (%d-%d)", name, lmin, lmax or lmin) or name,
        }
      end
    end
    bar.near:SetShown(#nearOptions > 0)
  end

  -- Shows or hides the bar, the flat surface and the keys for the current state; MapPage calls
  -- it after every canvas size change.
  function ctl.Paint()
    local zoomed = ctl.zv ~= nil
    ctl.PaintFocus()
    bar:SetShown(zoomed)
    flat:SetShown(zoomed and not ctl.art)
    if ctl.keys then
      ctl.keys:EnableKeyboard(zoomed or ctx.markers.routeMode == true)
    end
    if not zoomed then
      return
    end
    local name = ctx.zoneName(ctl.zv.zone) or ctl.zv.zone
    W.SetText(bar.name, nil, name)
    if not ctl.art then
      local w = math.max(1, canvas:GetWidth() - 2 * FLAT_PAD)
      flat.name:ClearAllPoints()
      flat.name:SetPoint("BOTTOM", flat, "CENTER", 0, 6)
      flat.name:SetWidth(w)
      W.SetText(flat.name, nil, name)
      flat.hint:ClearAllPoints()
      flat.hint:SetPoint("TOP", flat, "CENTER", 0, -6)
      flat.hint:SetWidth(w)
    end
  end

  -- Enter and leave -----------------------------------------------------------------------
  -- True when the zone opened: it needs a rectangle in the base view and a game map.
  function ctl.Enter(slug)
    local zv = MW.ZoneView(ctx.base(), ctx.data(), slug)
    if not zv then
      return false
    end
    ctx.markers.Cancel()
    clearHover()
    ctl.ClearFocus()
    ctl.zv, ctl.art = zv, MW.LoadArt(zv.mapId)
    fillNearOptions(zv)
    ctl.Paint()
    ctx.changed()
    return true
  end

  -- Back to the world view; true when there was a zone to leave.
  function ctl.Leave()
    if not ctl.zv then
      return false
    end
    ctx.markers.Cancel()
    clearHover()
    ctl.ClearFocus()
    ctl.zv, ctl.art = nil, nil
    ctl.Paint()
    ctx.changed()
    return true
  end

  -- Forgets the zone without laying the page out (page shown again, closed, other tab).
  function ctl.Reset()
    if ctl.zv then
      ctx.markers.Cancel()
    end
    ctl.ClearFocus()
    ctl.zv, ctl.art = nil, nil
    clearHover()
    ctl.Paint()
  end

  -- Clicks ----------------------------------------------------------------------------------
  -- A click on free space of the canvas that was no marker click: right goes back, left opens
  -- the zone under the cursor when it has a map (in an open zone: the area around it). Returns
  -- true when it did something.
  function ctl.Click(button)
    ctl.ClearFocus()
    if button == "RightButton" then
      return ctl.Leave()
    end
    if button ~= "LeftButton" then
      return false
    end
    local slug
    if ctl.zv then
      slug = neighborAtCursor()
    else
      slug = zoneAtCursor(ctx.base())
    end
    return slug ~= nil and ctl.Enter(slug)
  end

  -- Keys --------------------------------------------------------------------------------------
  -- Backspace only with the pointer on the map and no text field focused; Esc only when it
  -- would close nothing else (dialog, menu, name field, tutorial, keyboard focus).
  local function escFree()
    if ctx.markers.FieldOpen() or (ns.Desktop and ns.Desktop.Layer and ns.Desktop.Layer.current) then
      return false
    end
    if ns.TutorialUI and ns.TutorialUI.IsActive() then
      return false
    end
    if ns.Focus and ns.Focus.current then
      return false
    end
    for f in pairs(ns.Dialogs and ns.Dialogs.open or {}) do
      if f:IsShown() then
        return false
      end
    end
    return true
  end

  function ctl.Key(key)
    -- Esc ends the Start/Goal mode first, a zone stays open until the next Esc.
    if key == "ESCAPE" and ctx.markers.routeMode and escFree() then
      ctx.markers.SetRouteMode(false)
      return true
    end
    if not ctl.zv then
      return false
    end
    if key == "BACKSPACE" then
      return canvas:IsMouseOver() == true
        and not (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus())
        and ctl.Leave()
    elseif key == "ESCAPE" then
      return escFree() and ctl.Leave()
    elseif ctx.zoomKey then
      -- Zoom keys only with the pointer on the map and no text field focused, like Backspace.
      local over = canvas:IsMouseOver()
      if ctx.over then
        over = ctx.over()
      end
      return over == true and not (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()) and ctx.zoomKey(key) == true
    end
    return false
  end

  local keys = CreateFrame("Frame", nil, canvas)
  ns.PropagateKeys(keys, true)
  keys:SetScript("OnKeyDown", function(self, key)
    -- Propagation cannot change in combat; the game then keeps every key.
    if InCombatLockdown() then
      return
    end
    local _, handled = ns.Safe("map-zoom-key", ctl.Key, key)
    ns.PropagateKeys(self, not handled)
  end)
  keys:EnableKeyboard(false)
  ctl.keys = keys
  ns.On("PLAYER_REGEN_DISABLED", function()
    ns.PropagateKeys(keys, true)
  end)

  return ctl
end
