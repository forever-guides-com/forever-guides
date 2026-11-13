-- The effect window of the gathering sparkles ("Gathering spot effects"): a window of its own for the effect of
-- each kind of object. Left the seven kinds with their switch state, right the editor of the chosen kind: a
-- gallery of style tiles (every tile with a small preview drawn from the textures of the style, still under
-- reduced motion), the color, and sliders for size, height, number of sparks and spread. Everything writes
-- settings.sparkles.kinds.<kind>.<field> through the helpers of GatherSparklesSettings, so the effect at the
-- object follows live like it did on the settings card.
local _, ns = ...
local W, Store, Logic = ns.W, ns.Store, ns.GatherSparklesLogic
local S = ns.GatherSparklesSettings

local GW = {}
ns.GatherSparklesWindow = GW

ns.AddLocale("enUS", {
  ["sparkles.win.title"] = "Gathering spot effects",
  ["sparkles.win.close"] = "Close the window",
  ["sparkles.win.kinds"] = "Kinds of object",
  ["sparkles.win.kindTip"] = "Shows and edits the effect for this kind of object.",
  ["sparkles.win.style"] = "Choose a style",
  ["sparkles.win.chosen"] = "Chosen: %s",
  ["sparkles.win.tileTip"] = "Click to use this style for %s.",
  ["sparkles.win.autoTip"] = "Automatic uses %s for this kind.",
  ["sparkles.win.noPreview"] = "No preview",
  ["sparkles.win.autoName"] = "%s (%s)",
})
ns.AddLocale("deDE", {
  ["sparkles.win.title"] = "Sammelstellen-Effekte",
  ["sparkles.win.close"] = "Fenster schließen",
  ["sparkles.win.kinds"] = "Objektarten",
  ["sparkles.win.kindTip"] = "Zeigt und bearbeitet den Effekt dieser Objektart.",
  ["sparkles.win.style"] = "Stil wählen",
  ["sparkles.win.chosen"] = "Gewählt: %s",
  ["sparkles.win.tileTip"] = "Klicken, um diesen Stil für %s zu nutzen.",
  ["sparkles.win.autoTip"] = "Automatisch nimmt für diese Art %s.",
  ["sparkles.win.noPreview"] = "Keine Vorschau",
  ["sparkles.win.autoName"] = "%s (%s)",
})

local WIDTH, HEIGHT, TITLE_H, PAD = 800, 600, 26, 12
local LEFT_W = 190
local ROW_H = 36
local TILE_W, TILE_H, TILE_GAP = 104, 94, 8
local PREVIEW_W, PREVIEW_H = 96, 58
local GALLERY_H = 290
local COLS = 5
-- Preview: share of the real size, number of sprites and the redraw rate.
local SCALE, MAX_DRAW, FRAME_STEP = 0.55, 24, 1 / 24

local frame
local rows, tiles = {}, {}
local clock, sinceStep, stillDrawn, lastScroll = 0, 0, false, 0

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function frameDb()
  local frames = ns.db.frames
  if type(frames.sparkleEffectsWindow) ~= "table" then
    frames.sparkleEffectsWindow = {}
  end
  return frames.sparkleEffectsWindow
end

local function kindEntry(key)
  for _, entry in ipairs(Logic.KINDS) do
    if entry.key == key then
      return entry
    end
  end
end

local function styleLabel(key)
  for _, entry in ipairs(Logic.STYLE_CATALOG) do
    if entry.key == key then
      return entry.label
    end
  end
  return "sparkles.style.auto"
end

local function reduced()
  return ns.Theme ~= nil and ns.Theme.reduceMotion() == true
end

-- Style previews -----------------------------------------------------------------------------------------

local function takeDraw(tile)
  tile.used = tile.used + 1
  local d = tile.draw[tile.used]
  if not d then
    d = { tex = tile.preview:CreateTexture(nil, "OVERLAY") }
    tile.draw[tile.used] = d
  end
  d.tex:Show()
  return d
end

local function paintTexture(tex, id, atlas, fallback)
  return ns.GatherSparkles.PaintTexture(tex, id, atlas, fallback)
end

-- Builds the sprites of a style (a key of the catalog, "auto" already resolved) into the preview of a tile.
local function buildPreview(tile, styleKey)
  for _, d in ipairs(tile.draw) do
    d.tex:Hide()
  end
  tile.used = 0
  local entry = Logic.StyleSpec(styleKey)
  if entry then
    tile.none:Hide()
  else
    tile.none:Show()
    return
  end
  if entry.kind == "beam" then
    local beam = takeDraw(tile)
    beam.mode = "beam"
    paintTexture(beam.tex, entry.textures[1], entry.atlas)
    beam.tex:SetBlendMode(entry.blend)
    beam.tex:ClearAllPoints()
    beam.tex:SetPoint("BOTTOM", tile.preview, "BOTTOM", 0, 4)
    beam.tex:SetSize(entry.width * SCALE, PREVIEW_H * 0.8)
    local spark = takeDraw(tile)
    spark.mode = "spark"
    paintTexture(spark.tex, entry.sparkTexture)
    spark.tex:SetBlendMode(entry.blend)
    spark.tex:ClearAllPoints()
    spark.tex:SetPoint("BOTTOM", tile.preview, "BOTTOM", 0, 0)
    spark.tex:SetSize(entry.sparkSize * SCALE, entry.sparkSize * SCALE)
    return
  end
  if entry.glow then
    local glow = takeDraw(tile)
    glow.mode = "glow"
    paintTexture(glow.tex, Logic.GLOW_TEXTURE)
    glow.tex:SetBlendMode("ADD")
    glow.tex:ClearAllPoints()
    glow.tex:SetPoint("CENTER", tile.preview, "CENTER")
    glow.tex:SetSize(Logic.GLOW_SIZE * SCALE, Logic.GLOW_SIZE * SCALE)
  end
  for _, layer in ipairs(Logic.ExpandLayers(entry, entry.count, 100)) do
    local n = math.min(layer.count, 12)
    for i = 1, n do
      for j = 0, layer.trail or 0 do
        if tile.used < MAX_DRAW then
          local d = takeDraw(tile)
          d.mode, d.layer, d.i, d.n, d.j, d.frame = layer.motion and "posed" or "fade", layer, i, n, j, nil
          local source = paintTexture(d.tex, layer.textures[(i - 1) % #layer.textures + 1], layer.atlas, layer.fallback)
          d.sheeted = layer.sheet ~= nil and source ~= nil
          d.tex:SetBlendMode(layer.blend or "ADD")
          d.tex:SetDrawLayer("OVERLAY", layer.sublevel or 0)
          if d.tex.SetRotation then
            d.tex:SetRotation(0)
          end
        end
      end
    end
  end
end

-- One frame of a tile at the time t in seconds (nil: the still picture of reduced motion), tinted with the color
-- of the kind.
local function paintTile(tile, t, color)
  local r, g, b = color.r, color.g, color.b
  for k = 1, tile.used do
    local d = tile.draw[k]
    local tex = d.tex
    if d.mode == "beam" then
      tex:SetVertexColor(r, g, b, t and 0.65 + 0.2 * math.sin(t * 2) or 0.8)
    elseif d.mode == "spark" then
      tex:SetVertexColor(r, g, b, t and 0.65 + 0.35 * math.sin(t * 4.6) or 0.9)
    elseif d.mode == "glow" then
      tex:SetVertexColor(r, g, b, t and 0.45 + 0.15 * math.sin(t * 2.2) or 0.5)
    else
      local layer = d.layer
      local x, y, alpha, size, wide
      if d.mode == "posed" then
        local scale, stretch, rotation
        x, y, alpha, scale, stretch, rotation = Logic.Pose(layer, d.i, d.n, d.j, t)
        size = layer.sizeMax * scale * SCALE
        wide = size * stretch
        if d.sheeted then
          local sheetFrame = Logic.SheetFrame(layer, d.i, t)
          if sheetFrame ~= d.frame then
            d.frame = sheetFrame
            tex:SetTexCoord(Logic.SheetCoords(layer.sheet, sheetFrame))
          end
        end
        if layer.spin and tex.SetRotation then
          tex:SetRotation(rotation)
        end
      else
        x, y = Logic.StaticSpot(d.i, d.n, layer.radius)
        alpha = t and 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * 2.1 + d.i * 1.9)) or 0.75
        size = layer.sizeMax * SCALE
        wide = size
      end
      tex:ClearAllPoints()
      tex:SetPoint("CENTER", tile.preview, "CENTER", x * SCALE, y * SCALE)
      tex:SetSize(wide, size)
      tex:SetVertexColor(r, g, b, alpha)
    end
  end
end

-- Tiles ------------------------------------------------------------------------------------------------------

local function selectedStyle()
  return S.KindData().style
end

local function paintSelection(tile)
  local on = tile.value ~= nil and tile.value == selectedStyle()
  tile.fgSelected = on
  tile.mark:SetShown(on)
  tile.markBack:SetShown(on)
  tile.border.set(on and "accent2" or "accentDim", 1)
  W.SetColor(tile.name, on and "accent2" or "text")
end

local function tileName(kindKey, value, key)
  if value == "auto" then
    return string.format(ns.L["sparkles.win.autoName"], ns.L[key], ns.L[styleLabel(Logic.AutoStyle(kindKey))])
  end
  return ns.L[key]
end

-- Whether a tile lies in the visible part of the gallery.
local function inView(tile)
  local scroll, height = frame.gallery:GetVerticalScroll() or 0, frame.gallery:GetHeight() or GALLERY_H
  return tile.value ~= nil and tile.top ~= nil and tile.top + TILE_H >= scroll and tile.top <= scroll + height
end

local function bindTile(tile, kindKey, choice)
  tile.value = choice.value
  tile.nameText = tileName(kindKey, choice.value, choice.key)
  tile.name:SetText(tile.nameText)
  tile.fgName = tile.nameText
  buildPreview(tile, choice.value == "auto" and Logic.AutoStyle(kindKey) or choice.value)
  paintSelection(tile)
  tile:Show()
end

local function newTile(parent, index)
  local tile = CreateFrame("Button", nil, parent)
  tile:SetSize(TILE_W, TILE_H)
  tile.fgId = "sparkles-win-tile-" .. index
  W.Fill(tile, "surface", 1)
  tile.border = W.Border(tile, "accentDim", 1, 2)
  tile.preview = CreateFrame("Frame", nil, tile)
  tile.preview:SetSize(PREVIEW_W, PREVIEW_H)
  tile.preview:SetPoint("TOPLEFT", 4, -4)
  if tile.preview.SetClipsChildren then
    tile.preview:SetClipsChildren(true)
  end
  local back = tile.preview:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0.04, 0.04, 0.06, 1)
  tile.none = W.Text(tile.preview, { key = "sparkles.win.noPreview", role = "micro", color = "textMuted", justify = "CENTER", wrap = true })
  tile.none:SetPoint("LEFT", 4, 0)
  tile.none:SetPoint("RIGHT", -4, 0)
  tile.none:Hide()
  tile.name = W.Text(tile, { role = "micro", justify = "CENTER", wrap = true })
  tile.name:SetPoint("TOPLEFT", tile.preview, "BOTTOMLEFT", 0, -3)
  tile.name:SetPoint("TOPRIGHT", tile.preview, "BOTTOMRIGHT", 0, -3)
  tile.name:SetHeight(28)
  -- The chosen tile also carries a check mark on a light plate, never the border color alone.
  tile.markBack = tile.preview:CreateTexture(nil, "OVERLAY")
  tile.markBack:SetDrawLayer("OVERLAY", 6)
  tile.markBack:SetSize(18, 18)
  tile.markBack:SetPoint("TOPRIGHT", tile.preview, "TOPRIGHT", -2, -2)
  tile.markBack:SetColorTexture(0, 0, 0, 0.75)
  tile.markFrame = CreateFrame("Frame", nil, tile.preview)
  tile.markFrame:SetAllPoints(tile.markBack)
  tile.mark = W.CheckMark(tile.markFrame, 14, "accent2")
  tile.mark:SetPoint("CENTER")
  tile.markBack:Hide()
  tile.mark:Hide()
  tile.draw, tile.used = {}, 0
  tile:SetScript("OnEnter", function(self)
    if not self.fgSelected then
      self.border.set("accent", 1)
    end
    local kindName = ns.L[kindEntry(S.Selected()).label]
    local text = string.format(ns.L["sparkles.win.tileTip"], kindName)
    if self.value == "auto" then
      text = string.format(ns.L["sparkles.win.autoTip"], ns.L[styleLabel(Logic.AutoStyle(S.Selected()))])
    end
    ns.ShowTooltip(self, self.nameText, text)
  end)
  tile:SetScript("OnLeave", function(self)
    paintSelection(self)
    ns.HideTooltip()
  end)
  tile:SetScript(
    "OnClick",
    ns.Wrap("sparkles-tile", function(self)
      if self.value then
        S.SetStyle(S.Selected(), self.value)
      end
    end)
  )
  ns.Focus.register(tile, function(self)
    self:Click()
  end)
  return tile
end

local function bindTiles()
  local kindKey = S.Selected()
  local choices = Logic.StyleChoices(kindKey)
  for i, tile in ipairs(tiles) do
    local choice = choices[i]
    if choice then
      local row, col = math.floor((i - 1) / COLS), (i - 1) % COLS
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", frame.gallery.content, "TOPLEFT", col * (TILE_W + TILE_GAP), -row * (TILE_H + TILE_GAP))
      tile.top = row * (TILE_H + TILE_GAP)
      bindTile(tile, kindKey, choice)
    else
      tile.value = nil
      tile:Hide()
    end
  end
  frame.gallery:SetContentHeight(math.ceil(#choices / COLS) * (TILE_H + TILE_GAP))
  frame.gallery:ScrollTo(0)
  -- Sprites have no anchor or size before their first paint: draw the visible tiles now, not on the next throttled step.
  local color = S.KindData().color
  for _, tile in ipairs(tiles) do
    if inView(tile) then
      paintTile(tile, not reduced() and clock or nil, color)
    end
  end
  stillDrawn = false
end

-- State that follows the settings: switches, chosen tile, color, sliders. Cheap, runs on every change.
local function refreshState()
  if not frame then
    return
  end
  local data = S.KindData()
  for key, row in pairs(rows) do
    local on = S.KindData(key).on
    row.state:SetText(ns.L[on and "common.on" or "common.off"])
    W.SetColor(row.state, on and "accent2" or "textMuted")
    local chosen = key == S.Selected()
    row.bar:SetShown(chosen)
    row.fill:SetShown(chosen)
    W.SetColor(row.label, chosen and "accent" or "text")
    row.fgSelected = chosen
  end
  for _, tile in ipairs(tiles) do
    if tile.value then
      paintSelection(tile)
    end
  end
  local current
  for _, choice in ipairs(Logic.StyleChoices(S.Selected())) do
    if choice.value == data.style then
      current = tileName(S.Selected(), choice.value, choice.key)
    end
  end
  frame.chosen:SetText(string.format(ns.L["sparkles.win.chosen"], current or ""))
  for _, control in ipairs(frame.live) do
    control:Refresh()
  end
end

local function refreshKind()
  local key = S.Selected()
  W.SetText(frame.kindName, kindEntry(key).label)
  frame.note:SetText(ns.L[S.IsAssumed(key) and "sparkles.cfg.assumed" or "sparkles.cfg.certain"])
  bindTiles()
  refreshState()
end

function GW.Select(kindKey)
  if not kindEntry(kindKey) then
    return
  end
  S.Select(kindKey)
  if frame then
    refreshKind()
  end
end

-- Window parts -------------------------------------------------------------------------------------------------

local function newRow(parent, entry, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(LEFT_W, ROW_H)
  row:SetPoint("TOPLEFT", 0, -22 - (index - 1) * (ROW_H + 2))
  row.fgId = "sparkles-win-kind-" .. entry.key
  W.Fill(row, "surface", 1)
  row.fill = W.Fill(row, "surface3", 1, "BORDER")
  row.bar = row:CreateTexture(nil, "ARTWORK")
  row.bar:SetPoint("TOPLEFT")
  row.bar:SetPoint("BOTTOMLEFT")
  row.bar:SetWidth(4)
  ns.Bind(row.bar, function(t)
    t:SetColorTexture(ns.Theme.color("accent2"))
  end)
  row.label = W.Text(row, { key = entry.label, role = "ui" })
  row.label:SetPoint("LEFT", 12, 0)
  row.state = W.Text(row, { role = "micro", justify = "RIGHT" })
  row.state:SetPoint("RIGHT", -8, 0)
  row.label:SetPoint("RIGHT", row.state, "LEFT", -4, 0)
  row.fgName = ns.L[entry.label]
  row:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, ns.L[entry.label], ns.L["sparkles.win.kindTip"])
  end)
  row:SetScript("OnLeave", ns.HideTooltip)
  row:SetScript(
    "OnClick",
    ns.Wrap("sparkles-kind-row", function()
      GW.Select(entry.key)
    end)
  )
  ns.Focus.register(row, function(self)
    self:Click()
  end)
  rows[entry.key] = row
  return row
end

local function colorButton(parent)
  local control
  control = W.Button(parent, {
    key = "sparkles.cfg.color",
    width = 230,
    height = 28,
    opens = true,
    tooltip = "sparkles.cfg.color",
    tooltipText = "sparkles.cfg.colorHint",
    onClick = function()
      S.OpenPicker(S.Selected(), function()
        control:Refresh()
      end)
    end,
  })
  -- A light edge keeps a dark swatch visible on the dark button.
  local edge = control:CreateTexture(nil, "ARTWORK")
  edge:SetSize(20, 20)
  edge:SetPoint("RIGHT", control, "RIGHT", -8, 0)
  edge:SetColorTexture(1, 1, 1, 0.9)
  local swatch = control:CreateTexture(nil, "OVERLAY")
  swatch:SetSize(16, 16)
  swatch:SetPoint("CENTER", edge, "CENTER")
  function control:Refresh()
    local c = S.KindData().color
    swatch:SetColorTexture(c.r, c.g, c.b, 1)
  end
  control.swatch = swatch
  control.fgId = "sparkles-kind-color"
  return control
end

-- A live slider of the chosen kind (the sliders only change the effect, no rebuild).
local function field(parent, name, id, min, max, step, clean, format)
  local s = W.Slider(parent, {
    key = "sparkles.cfg." .. name,
    tooltip = "sparkles.cfg." .. name,
    tooltipText = "sparkles.cfg." .. name .. "Hint",
    min = min,
    max = max,
    step = step,
    get = function()
      return S.KindData()[name]
    end,
    set = function(v)
      Store.set(S.KindPath(name), clean(v))
    end,
    format = function(v)
      return string.format(format, v)
    end,
  })
  s.fgId = id
  return s
end

local function savePosition(f)
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s, db = f:GetScale(), frameDb()
    db.x, db.y = left * s, top * s
  end
end

local function place(f)
  local db = frameDb()
  f:ClearAllPoints()
  local s = f:GetScale()
  if finite(db.x) and finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  ns.WindowShell.FitToScreen(f)
end

local function ownsFocus(f)
  local item = ns.Focus.current
  while item do
    if item == f then
      return true
    end
    item = item.GetParent and item:GetParent() or nil
  end
  return false
end

-- Tab, arrows and Enter like the main window: only while the pointer is over the window or its focus ring is in it.
local function handleKey(f, key)
  if key == "ESCAPE" then
    return ns.EscStack.Close(f)
  end
  if not (ownsFocus(f) or f:IsMouseOver()) then
    return false
  end
  local focus = ns.Focus.current
  if key == "TAB" then
    ns.Focus.move(IsShiftKeyDown() and -1 or 1)
    return true
  elseif (key == "ENTER" or key == "SPACE") and focus and ns.Focus.recent() then
    return ns.Focus.activate()
  elseif (key == "UP" or key == "DOWN") and focus then
    ns.Focus.move(key == "UP" and -1 or 1)
    return true
  elseif (key == "LEFT" or key == "RIGHT") and focus and focus.fgArrow then
    ns.Focus.touch()
    focus:fgArrow(key == "LEFT" and -1 or 1)
    return true
  elseif (key == "HOME" or key == "END") and focus and focus.fgEdge then
    ns.Focus.touch()
    focus:fgEdge(key == "HOME" and -1 or 1)
    return true
  end
  return false
end

-- Redraws the previews of the tiles in view: once when still (reduced motion), else at a fixed rate.
local function animate(elapsed)
  local still = reduced()
  local scroll = frame.gallery:GetVerticalScroll() or 0
  -- Scrolling brings tiles into view that the single still pass has not drawn.
  if scroll ~= lastScroll then
    lastScroll, stillDrawn = scroll, false
  end
  if still then
    if stillDrawn then
      return
    end
  else
    sinceStep = sinceStep + elapsed
    if sinceStep < FRAME_STEP then
      return
    end
    clock, sinceStep = clock + sinceStep, 0
  end
  stillDrawn = still
  local color = S.KindData().color
  for _, tile in ipairs(tiles) do
    if inView(tile) then
      -- One failing tile must not leave the others unpainted.
      ns.Safe("sparkles-window-tile", paintTile, tile, not still and clock or nil, color)
    end
  end
end

local function create()
  local f = CreateFrame("Frame", "FGSparkleEffectsWindow", UIParent)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  W.Fill(f, "bg", 0.97)
  local shell = ns.WindowShell.Attach(f, { title = "sparkles.win.title", titleHeight = TITLE_H, shadow = true })
  f.shell = shell
  frame = f
  f:SetScript(
    "OnDragStop",
    ns.Wrap("sparkles-window-move", function()
      f:StopMovingOrSizing()
      savePosition(f)
    end)
  )

  -- Left: the kinds.
  local left = CreateFrame("Frame", nil, f)
  left:SetPoint("TOPLEFT", PAD, -(TITLE_H + PAD))
  left:SetSize(LEFT_W, HEIGHT - TITLE_H - 2 * PAD)
  local heading = W.Text(left, { key = "sparkles.win.kinds", role = "micro", color = "textSecondary" })
  heading:SetPoint("TOPLEFT", 0, 0)
  for i, entry in ipairs(Logic.KINDS) do
    newRow(left, entry, i)
  end

  -- Right: the editor of the chosen kind.
  local right = CreateFrame("Frame", nil, f)
  local rightW = WIDTH - LEFT_W - 3 * PAD
  right:SetPoint("TOPLEFT", PAD + LEFT_W + PAD, -(TITLE_H + PAD))
  right:SetSize(rightW, HEIGHT - TITLE_H - 2 * PAD)
  f.live = {}
  f.kindName = W.Text(right, { role = "h3", color = "accent2" })
  f.kindName:SetPoint("TOPLEFT", 0, 0)
  f.note = W.Text(right, { role = "micro", color = "textSecondary" })
  f.note:SetPoint("TOPLEFT", 0, -24)
  local on = W.Toggle(right, {
    key = "sparkles.cfg.on",
    tooltip = "sparkles.cfg.on",
    tooltipText = "sparkles.cfg.onHint",
    get = function()
      return S.KindData().on
    end,
    set = function(v)
      Store.set(S.KindPath("on"), v)
    end,
  })
  on.fgId = "sparkles-kind-on"
  on:SetPoint("TOPLEFT", 0, -44)
  on:SetWidth(320)
  f.live[#f.live + 1] = on

  local styleHeading = W.Text(right, { key = "sparkles.win.style", role = "ui", color = "accent" })
  styleHeading:SetPoint("TOPLEFT", 0, -78)
  f.chosen = W.Text(right, { role = "ui", color = "accent2", justify = "RIGHT" })
  f.chosen:SetPoint("TOPRIGHT", 0, -78)
  f.chosen:SetPoint("LEFT", styleHeading, "RIGHT", 8, 0)
  f.gallery = W.ScrollArea(right, {})
  f.gallery:SetPoint("TOPLEFT", 0, -100)
  f.gallery:SetSize(rightW, GALLERY_H)
  local count = 0
  for _, kind in ipairs(Logic.KINDS) do
    count = math.max(count, #Logic.StyleChoices(kind.key))
  end
  for i = 1, count do
    tiles[i] = newTile(f.gallery.content, i)
  end

  local colorY = -(100 + GALLERY_H + 10)
  local color = colorButton(right)
  color:SetPoint("TOPLEFT", 0, colorY)
  f.live[#f.live + 1] = color
  local reset = W.Button(right, {
    key = "sparkles.cfg.colorReset",
    width = 180,
    height = 28,
    tooltip = "sparkles.cfg.colorReset",
    tooltipText = "sparkles.cfg.colorResetHint",
    onClick = function()
      local gold = Logic.LOOKS.ready
      Store.set(S.KindPath("color"), { r = gold.r, g = gold.g, b = gold.b })
      refreshState()
    end,
  })
  reset.fgId = "sparkles-kind-colorReset"
  reset:SetPoint("LEFT", color, "RIGHT", 10, 0)

  local halfW = (rightW - 20) / 2
  local function put(slider, column, row)
    slider:SetWidth(halfW)
    slider:SetPoint("TOPLEFT", column * (halfW + 20), colorY - 40 - row * 52)
    f.live[#f.live + 1] = slider
  end
  put(field(right, "size", "sparkles-kind-size", Logic.SIZE_MIN, Logic.SIZE_MAX, Logic.SIZE_STEP, Logic.CleanSize, "%d%%"), 0, 0)
  put(
    field(right, "height", "sparkles-kind-height", Logic.OFFSET_MIN, Logic.OFFSET_MAX, Logic.OFFSET_STEP, Logic.CleanOffset, "%d"),
    1,
    0
  )
  put(
    field(right, "count", "sparkles-kind-count", Logic.COUNT_MIN, Logic.COUNT_MAX, 1, function(v)
      return S.Whole(v, Logic.COUNT_MIN, Logic.COUNT_MAX)
    end, "%d"),
    0,
    1
  )
  put(
    field(right, "spread", "sparkles-kind-spread", Logic.SPREAD_MIN, Logic.SPREAD_MAX, 5, function(v)
      return S.Whole(v, Logic.SPREAD_MIN, Logic.SPREAD_MAX)
    end, "%d%%"),
    1,
    1
  )

  -- Last in the focus order: the close button of the title strip.
  local close = W.Action(shell.titleBar, { icon = "close", size = 18, tooltip = "sparkles.win.close" })
  close:SetPoint("RIGHT", -4, 0)
  close:SetScript(
    "OnClick",
    ns.Wrap("sparkles-window-close", function()
      f:Hide()
    end)
  )
  shell.titleText:ClearAllPoints()
  shell.titleText:SetPoint("LEFT", 8, 0)
  shell.titleText:SetPoint("RIGHT", close, "LEFT", -4, 0)

  f:SetScript("OnKeyDown", function(self, key)
    local _, handled = ns.Safe("sparkles-window-key", handleKey, self, key)
    ns.PropagateKeys(self, not handled)
  end)
  f:SetScript(
    "OnUpdate",
    ns.Wrap("sparkles-window-preview", function(_, elapsed)
      animate(elapsed)
    end)
  )
  f:SetScript("OnShow", function()
    f:SetScale(ns.Theme.windowScale())
    place(f)
    f:Raise()
    stillDrawn = false
    refreshKind()
  end)
  ns.WindowShell.RegisterEsc(f)
  f:Hide()
  return f
end

-- Opens the window, on a kind when one is given.
function GW.Open(kindKey)
  if not frame then
    create()
  end
  if kindKey then
    S.Select(kindKey)
  end
  if frame:IsShown() then
    refreshKind()
  else
    frame:Show()
  end
  frame:Raise()
  return frame
end

function GW.Close()
  if frame then
    frame:Hide()
  end
end

function GW.IsShown()
  return frame ~= nil and frame:IsShown()
end

function GW.Toggle()
  if GW.IsShown() then
    GW.Close()
  else
    GW.Open()
  end
end

function GW.Frame()
  return frame
end

-- Entry of the slash command: a kind name or key opens on that kind, anything else toggles.
function GW.Slash(rest)
  local word = ns.U.trim(tostring(rest or "")):lower()
  for _, entry in ipairs(Logic.KINDS) do
    if word ~= "" and (word == entry.key or word == ns.L[entry.label]:lower()) then
      GW.Open(entry.key)
      return
    end
  end
  GW.Toggle()
end

-- A change from anywhere (the setup, the dev tools, a profile) shows in the open window.
ns.On("FG_SETTING_CHANGED", function(_, path)
  if frame and frame:IsShown() and type(path) == "string" and path:find("^settings%.sparkles%.kinds") then
    refreshState()
  end
end)
