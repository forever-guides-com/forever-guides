-- "You are here" on the map page: an arrow that turns with the player's facing (a round dot when the client
-- gives no facing or has no line objects) at the player's position, on the zone view when the open zone is the
-- player's, on the world view when the player's zone lies on it. One frame without mouse sits over the canvas
-- (clicks go to the map and the places below), one throttled read of the position moves the marker, and it
-- does nothing while position, facing and canvas stay as they were. The numbers are in MapPlayerMarkerLogic.lua,
-- MapPage.lua hands in the view and the switch through the Attach context.
local _, ns = ...
local L, K, MI = ns.L, ns.PageKit, ns.MapIcons
local ML = ns.MapPlayerMarkerLogic

local MPM = {}
ns.MapPlayerMarker = MPM

-- Bright fill with a dark edge: readable on a pale and on a dark map image alike (gold on black is about
-- 12:1, the dark edge keeps it apart from a pale background).
local FILL = { 1, 0.82, 0, 1 }
local EDGE = { 0, 0, 0, 0.9 }
-- Above the places, the spots and the waypoint pins, below the zoom bar and the name field.
local LEVEL = 100

ns.AddLocale("enUS", {
  ["map.player"] = "Show my position",
  ["map.player.tip"] = "Shows an arrow at your position on the map. It points the way you face and appears in your zone and on the world view, never in instances.",
  ["map.player.here"] = "You are here",
})

ns.AddLocale("deDE", {
  ["map.player"] = "Meine Position zeigen",
  ["map.player.tip"] = "Zeigt einen Pfeil an deiner Position auf der Karte. Er zeigt in deine Blickrichtung und erscheint in deinem Gebiet und auf der Weltansicht, nicht in Instanzen.",
  ["map.player.here"] = "Du bist hier",
})

-- ctx = {
--   canvas                the map canvas the marker sits on
--   view()                the view the canvas shows (a layout, an island view or a zone view), nil on the flat canvas
--   enabled()             the switch of the map page
--   zoneName(slug)        display name of a zone
--   window()              left, top, width, height of the visible part of the canvas in canvas px
--   cursor()              the cursor as fractions (0..1) of the visible part, nil when it is off the map
-- }
-- Returns the controller: Update(force), layer, marker, last, shown, hover, mode, edgeLines, fillLines.
function MPM.Attach(ctx)
  local canvas = ctx.canvas
  local ctl = { last = {}, shown = false }

  local layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:SetFrameLevel(canvas:GetFrameLevel() + LEVEL)
  layer:EnableMouse(false)
  ctl.layer = layer

  local marker = CreateFrame("Frame", nil, layer)
  marker:SetSize(ML.ARROW, ML.ARROW)
  marker:EnableMouse(false)
  marker:Hide()
  ctl.marker = marker

  -- Round fallback: a dark disc with a bright one on it, squares when the client does not know the disc file.
  local disc = MI.DiscKnown()
  local edgeDot = marker:CreateTexture(nil, "BORDER")
  local fillDot = marker:CreateTexture(nil, "ARTWORK")
  for _, dot in ipairs({ edgeDot, fillDot }) do
    dot:SetPoint("CENTER")
    if disc then
      dot:SetTexture(MI.DISC)
    end
  end
  local function paintDot(dot, c)
    if disc then
      dot:SetVertexColor(c[1], c[2], c[3], c[4])
    else
      dot:SetColorTexture(c[1], c[2], c[3], c[4])
    end
  end
  paintDot(edgeDot, EDGE)
  paintDot(fillDot, FILL)
  edgeDot:SetSize(ML.DOT + 4, ML.DOT + 4)
  fillDot:SetSize(ML.DOT, ML.DOT)

  -- The arrow is drawn with line objects: the dark line of a side under the bright one.
  local canLines = ns.can.lineObject and ns.can.lineThickness and ns.can.lineColorTexture
  local edgeLines, fillLines, corners = {}, {}, {}
  ctl.edgeLines, ctl.fillLines = edgeLines, fillLines
  if canLines then
    for i = 1, ML.CORNERS do
      edgeLines[i] = marker:CreateLine(nil, "BORDER")
      edgeLines[i]:SetThickness(ML.THICKNESS + ML.EDGE)
      edgeLines[i]:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
      fillLines[i] = marker:CreateLine(nil, "ARTWORK")
      fillLines[i]:SetThickness(ML.THICKNESS)
      fillLines[i]:SetColorTexture(FILL[1], FILL[2], FILL[3], FILL[4])
    end
  end

  local function showShape(facing)
    local arrow = canLines and facing ~= nil
    for i = 1, #edgeLines do
      edgeLines[i]:SetShown(arrow)
      fillLines[i]:SetShown(arrow)
    end
    edgeDot:SetShown(not arrow)
    fillDot:SetShown(not arrow)
    ctl.mode = arrow and "arrow" or "dot"
    if not arrow then
      return
    end
    ML.Outline(facing, ML.ARROW, corners)
    for i = 1, ML.CORNERS do
      local a, b = corners[i], corners[i % ML.CORNERS + 1]
      edgeLines[i]:SetStartPoint("CENTER", marker, a[1], a[2])
      edgeLines[i]:SetEndPoint("CENTER", marker, b[1], b[2])
      fillLines[i]:SetStartPoint("CENTER", marker, a[1], a[2])
      fillLines[i]:SetEndPoint("CENTER", marker, b[1], b[2])
    end
  end

  -- Tooltip ------------------------------------------------------------------------------------------
  local function hideTip()
    local tip = rawget(_G, "GameTooltip")
    if tip and tip:GetOwner() == layer then
      tip:Hide()
    end
  end

  local function showTip()
    local last, parts = ctl.last, {}
    local zone = last.slug and ctx.zoneName(last.slug)
    if zone then
      parts[#parts + 1] = zone
    end
    local coord = K.Coord(last.x, last.y)
    if coord then
      parts[#parts + 1] = coord
    end
    ns.ShowTooltip(layer, L["map.player.here"], table.concat(parts, "\n"), { anchor = "ANCHOR_CURSOR" })
  end

  -- Same test as the spots of the zone map: only the map itself under the cursor counts, not a place
  -- symbol, the zoom bar or a window. A client without the call gives no answer, the map is assumed.
  local function mouseOnMap()
    local foci, legacy = rawget(_G, "GetMouseFoci"), rawget(_G, "GetMouseFocus")
    local target
    if foci then
      target = foci()[1]
    elseif legacy then
      target = legacy()
    end
    return target == nil or target == canvas or target == layer
  end

  local function setHover(on)
    if on == ctl.hover then
      return
    end
    ctl.hover = on
    if on then
      showTip()
    else
      hideTip()
    end
  end

  local function pollHover()
    local over = false
    local fx, fy = ctx.cursor()
    if fx and mouseOnMap() then
      local l, t, w, h = ctx.window()
      over = ML.Hit(l + fx * w, t + fy * h, ctl.last.px, ctl.last.py, ML.HIT)
    end
    setHover(over)
  end

  -- Position ------------------------------------------------------------------------------------------
  local function hide()
    if ctl.shown then
      ctl.shown = false
      marker:Hide()
    end
    ctl.last.px = nil
    setHover(false)
  end

  -- Reads the position and moves the marker. force = true places it again even when nothing changed (the
  -- canvas was laid out), otherwise nothing is touched while the state is the same.
  function ctl.Update(force)
    local wp = ns.Waypoints
    if not (wp and ctx.enabled()) then
      return hide()
    end
    local map, x, y = wp.PlayerPosition()
    local nx, ny, slug
    if map then
      nx, ny, slug = ML.Locate(ctx.view(), map, x, y)
    end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local px, py
    if nx then
      px, py = ML.CanvasPoint(nx, ny, cw, ch)
    end
    if not px then
      return hide()
    end
    local facing = ML.SnapFacing(wp.Facing())
    local last = ctl.last
    local changed = ML.Changed(last, px, py, facing, cw, ch, slug)
    last.x, last.y = x, y
    if changed or force then
      -- Only a new facing changes the arrow, a step of the player only moves it.
      if changed and (ctl.mode == nil or facing ~= ctl.shapeFacing) then
        ctl.shapeFacing = facing
        showShape(facing)
      end
      marker:ClearAllPoints()
      marker:SetPoint("CENTER", canvas, "TOPLEFT", px, -py)
      marker:Show()
      ctl.shown = true
      if ctl.hover then
        showTip()
      end
    end
    pollHover()
  end

  local elapsed = 0
  layer:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed >= ML.INTERVAL then
      elapsed = 0
      ns.Safe("map-player-marker", ctl.Update, false)
    end
  end)
  layer:SetScript("OnHide", function()
    ctl.hover = nil
    hideTip()
  end)

  return ctl
end
