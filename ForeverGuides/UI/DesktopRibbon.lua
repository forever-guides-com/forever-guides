-- Ribbon pieces of the desktop-style widgets: tool grid, color swatches, icon
-- dropdown, vertical slider, separator and the ribbon with captioned groups.
-- Builds on Desktop.lua (popup layer, tool button, slider) and DesktopIcons.lua.
local _, ns = ...
local W, Theme, L, U = ns.W, ns.Theme, ns.L, ns.U
local Focus = ns.Focus
local Desktop = ns.Desktop
local Layer, scaled = Desktop.Layer, Desktop.scaled

local max, floor, ceil = math.max, math.floor, math.ceil

local function copyDef(def)
  local out = {}
  for k, v in pairs(def) do
    out[k] = v
  end
  return out
end

-- Tool grid ------------------------------------------------------------------

-- opts: columns, size (base px, default 32), gap (px, default 2),
--   items = { W.ToolButton defs }. Returns a Frame with .buttons, :Refresh().
function W.ToolGrid(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f.buttons = {}
  for i, item in ipairs(opts.items) do
    local def = copyDef(item)
    def.size = def.size or opts.size
    f.buttons[i] = W.ToolButton(f, def)
  end
  function f:Layout()
    local size, gap = scaled(opts.size or 32), opts.gap or 2
    local cols = max(1, math.min(opts.columns or #f.buttons, max(1, #f.buttons)))
    for i, b in ipairs(f.buttons) do
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", f, "TOPLEFT", ((i - 1) % cols) * (size + gap), -floor((i - 1) / cols) * (size + gap))
    end
    local rows = ceil(#f.buttons / cols)
    f:SetSize(cols * size + (cols - 1) * gap, max(1, rows * size + (rows - 1) * gap))
  end
  function f:Refresh()
    for _, b in ipairs(f.buttons) do
      b:Refresh()
    end
  end
  ns.Bind(f, f.Layout)
  return f
end

-- Color swatches -------------------------------------------------------------

local function hexOf(color)
  if type(color) == "string" then
    return "#" .. color:gsub("#", ""):lower()
  end
  local r, g, b = Desktop.parseColor(color)
  return string.format("#%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- opts: colors (list of "#rrggbb" or {r,g,b}), columns (default 8), swatchSize
--   (base px, default 18), gap (px, default 4), onPick(color, index),
--   get() -> current color, tooltipFor(color, index) -> text.
-- The current color wears a light outer ring (a shape, not only a color).
-- Methods: SetColors(list) (pooled), Refresh(), Layout(); fields .swatches.
function W.ColorSwatchGrid(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f.swatches, f.colors = {}, {}
  local PAD = 3

  local function newSwatch()
    local sw = CreateFrame("Button", nil, f)
    sw.tex = sw:CreateTexture(nil, "ARTWORK")
    sw.tex:SetPoint("TOPLEFT", 1, -1)
    sw.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    sw.border = W.Border(sw, "accentDim", 1)
    sw.ring = CreateFrame("Frame", nil, sw)
    sw.ring:SetPoint("TOPLEFT", -2, 2)
    sw.ring:SetPoint("BOTTOMRIGHT", 2, -2)
    sw.ring.border = W.Border(sw.ring, "text", 1, 2)
    sw.ring:Hide()
    sw:SetScript(
      "OnClick",
      ns.Wrap("swatch", function(self)
        if opts.onPick then
          opts.onPick(self.color, self.index)
        end
        f:Refresh()
      end)
    )
    sw:SetScript("OnEnter", function(self)
      local text = opts.tooltipFor and opts.tooltipFor(self.color, self.index)
      ns.ShowTooltip(self, text or string.format(L["desk.color"], hexOf(self.color)))
    end)
    sw:SetScript("OnLeave", ns.HideTooltip)
    Focus.register(sw, function(self)
      self:Click()
    end)
    return sw
  end

  function f:Layout()
    local size, gap = scaled(opts.swatchSize or 18), opts.gap or 4
    local count = #f.colors
    local cols = max(1, math.min(opts.columns or 8, max(1, count)))
    for i = 1, count do
      local sw = f.swatches[i]
      sw:SetSize(size, size)
      sw:ClearAllPoints()
      sw:SetPoint(
        "TOPLEFT",
        f,
        "TOPLEFT",
        PAD + ((i - 1) % cols) * (size + gap),
        -PAD - floor((i - 1) / cols) * (size + gap)
      )
    end
    local rows = ceil(count / cols)
    f:SetSize(2 * PAD + cols * size + (cols - 1) * gap, 2 * PAD + max(1, rows * size + (rows - 1) * gap))
  end

  function f:Refresh()
    local current = opts.get and opts.get()
    for i = 1, #f.colors do
      local sw = f.swatches[i]
      sw.fgCurrent = Desktop.sameColor(sw.color, current)
      sw.ring:SetShown(sw.fgCurrent)
    end
  end

  function f:SetColors(list)
    f.colors = list
    for i, color in ipairs(list) do
      local sw = f.swatches[i]
      if not sw then
        sw = newSwatch()
        f.swatches[i] = sw
      end
      sw.index, sw.color = i, color
      local r, g, b = Desktop.parseColor(color)
      sw.tex:SetColorTexture(r, g, b, 1)
      sw:Show()
    end
    for i = #list + 1, #f.swatches do
      f.swatches[i]:Hide()
    end
    f:Layout()
    f:Refresh()
  end

  ns.Bind(f, f.Layout)
  f:SetColors(opts.colors or {})
  return f
end

-- Icon dropdown ---------------------------------------------------------------

local gallery, galleryState

local function galleryCells()
  local list = {}
  for _, cell in ipairs(gallery.cells) do
    if cell:IsShown() then
      list[#list + 1] = cell
    end
  end
  return list
end

local function focusCell(cell)
  Focus.set(cell)
  for _, c in ipairs(gallery.cells) do
    if c:IsShown() then
      c:Refresh()
    end
  end
end

-- Moves the keyboard focus inside the open gallery by `delta` cells.
local function stepCell(delta)
  local cells = galleryCells()
  if #cells == 0 then
    return
  end
  local index = 0
  for i, c in ipairs(cells) do
    if c == Focus.current then
      index = i
    end
  end
  focusCell(cells[index == 0 and 1 or U.clamp(index + delta, 1, #cells)])
end

local function openGallery(btn, o, byKeyboard)
  Layer.close("replace")
  if not gallery then
    gallery = Layer.newPopup("surface")
    gallery.cells = {}
    Desktop.gallery = gallery
  end
  local cols = max(1, o.columns or 1)
  local list = cols == 1
  local cell = o.cellSize or (list and 28 or 32)
  local pad, gap = 4, 2
  galleryState = { btn = btn, cols = cols, kbd = byKeyboard }
  local current = o.get and o.get()
  local cellW, cellH = scaled(list and (o.width or 150) or cell), scaled(cell)
  for i, item in ipairs(o.items) do
    local def = {
      glyph = item.glyph,
      letter = item.letter,
      size = cell,
      selected = function()
        return o.get ~= nil and o.get() == item.value
      end,
      onClick = function()
        -- Copy first: closing the popup must not be able to drop what we call.
        local fn, value = o.onPick, item.value
        Layer.close("select")
        if fn then
          fn(value, item)
        end
        btn:Refresh()
      end,
    }
    if list then
      def.key, def.text, def.width = item.key, item.text, o.width or 150
    else
      def.tooltip, def.tooltipText = item.tooltip or item.key, item.tooltipText
    end
    local c = gallery.cells[i]
    if c then
      c:SetDef(def)
    else
      c = W.ToolButton(gallery, def)
      c.fgArrow = function(_, delta)
        stepCell(delta)
      end
      gallery.cells[i] = c
    end
    c.value = item.value
    c:ClearAllPoints()
    c:SetPoint(
      "TOPLEFT",
      gallery,
      "TOPLEFT",
      pad + ((i - 1) % cols) * (cellW + gap),
      -pad - floor((i - 1) / cols) * (cellH + gap)
    )
    c:Show()
  end
  for i = #o.items + 1, #gallery.cells do
    gallery.cells[i]:Hide()
  end
  local rows = ceil(#o.items / cols)
  gallery:SetSize(2 * pad + cols * cellW + (cols - 1) * gap, 2 * pad + rows * cellH + max(0, rows - 1) * gap)
  Layer.place(gallery, btn, "TOPLEFT", "BOTTOMLEFT", 0, -2)
  gallery:Show()
  Layer.open({
    frames = { gallery },
    owner = btn,
    move = function(step)
      stepCell(step * cols)
    end,
    beforeClose = function(reason)
      local cur = Focus.current
      if cur and cur:GetParent() == gallery then
        if reason == "escape" and galleryState and galleryState.kbd then
          Focus.set(btn)
        else
          Focus.clear()
        end
      end
    end,
    onClose = function()
      galleryState = nil
      btn:Refresh()
    end,
  })
  btn:Refresh()
  if byKeyboard then
    for i, item in ipairs(o.items) do
      if current ~= nil and item.value == current then
        focusCell(gallery.cells[i])
        return
      end
    end
    focusCell(gallery.cells[1])
  end
end

-- A tool button with a chevron that opens a popup list (columns = 1, labels) or
-- icon grid (columns > 1) below it.
-- opts: items = { { value, glyph, letter, key|text (list rows), tooltip (locale key,
--   grid cells; default key), tooltipText } }, columns (default 1), cellSize (base
--   px), width (list row width, base px), get() -> current value (marks the cell
--   and, without opts.glyph, supplies the button icon), onPick(value, item),
--   plus ToolButton fields: glyph, letter, key|text, tooltip, tooltipText, size, enabled.
-- Methods: Refresh(); the popup is Desktop.gallery. Esc, outside click, picking
--   and Up/Down/Left/Right (when opened by keyboard) work like the menu bar.
function W.IconDropdownButton(parent, opts)
  local btn
  local function currentItem()
    local value = opts.get and opts.get()
    for _, item in ipairs(opts.items) do
      if value ~= nil and item.value == value then
        return item
      end
    end
    return nil
  end
  local function isOpen()
    return Layer.current ~= nil and Layer.current.owner == btn
  end
  local first = currentItem()
  btn = W.ToolButton(parent, {
    glyph = opts.glyph or (first and first.glyph),
    letter = opts.letter or (first and first.letter),
    key = opts.key,
    text = opts.text,
    width = opts.width,
    tooltip = opts.tooltip,
    tooltipText = opts.tooltipText,
    size = opts.size,
    enabled = opts.enabled,
    chevron = true,
    selected = isOpen,
    onClick = function()
      if isOpen() then
        Layer.close("api")
      else
        openGallery(btn, opts, Focus.current == btn)
      end
    end,
  })
  local paint = btn.Refresh
  function btn:Refresh()
    local item = currentItem()
    if opts.glyph == nil and item and item.glyph ~= btn.def.glyph then
      btn:SetGlyph(item.glyph)
    end
    paint(btn)
  end
  return btn
end

-- Vertical slider ---------------------------------------------------------------

-- opts: min, max, step, get(), set(v), height (base px, default 160), invert
--   (default true: the top is the maximum), icon / iconBottom (glyph of the
--   step buttons above / below the track), iconTip / iconBottomTip (locale
--   keys), tooltip (locale key).
-- Methods: SetValue(v) (like a drag, calls set), GetValue(), Refresh() (silent
--   re-read of get); field .slider is the native Slider.
function W.VSlider(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  local function stepBy(dir)
    return function()
      f.slider:SetUserValue(U.clamp(opts.get(), opts.min, opts.max) + dir * (opts.step or 1))
    end
  end
  if opts.icon then
    f.top = W.ToolButton(f, { glyph = opts.icon, size = 24, tooltip = opts.iconTip, onClick = stepBy(1) })
    f.top:SetPoint("TOP", 0, 0)
  end
  if opts.iconBottom then
    f.bottom =
      W.ToolButton(f, { glyph = opts.iconBottom, size = 24, tooltip = opts.iconBottomTip, onClick = stepBy(-1) })
    f.bottom:SetPoint("BOTTOM", 0, 0)
  end
  f.slider = Desktop.buildSlider(f, true, opts)
  f.slider:SetWidth(18)
  f.slider:SetPoint("TOP", f.top or f, f.top and "BOTTOM" or "TOP", 0, f.top and -4 or 0)
  f.slider:SetPoint("BOTTOM", f.bottom or f, f.bottom and "TOP" or "BOTTOM", 0, f.bottom and 4 or 0)
  ns.Bind(f, function()
    f:SetSize(scaled(26), scaled(opts.height or 160))
  end)
  function f:SetValue(v)
    f.slider:SetUserValue(v)
  end
  function f:GetValue()
    return U.clamp(opts.get(), opts.min, opts.max)
  end
  function f:Refresh()
    f.slider:SyncValue()
  end
  return f
end

-- Separator --------------------------------------------------------------------

-- opts: vertical (default true), length (base px, default 40). Anchoring both
-- ends (TOP and BOTTOM, or LEFT and RIGHT) overrides the length.
function W.Separator(parent, opts)
  opts = opts or {}
  local vertical = opts.vertical ~= false
  local f = CreateFrame("Frame", nil, parent)
  local line = f:CreateTexture(nil, "ARTWORK")
  if vertical then
    line:SetPoint("TOP")
    line:SetPoint("BOTTOM")
    line:SetWidth(1)
  else
    line:SetPoint("LEFT")
    line:SetPoint("RIGHT")
    line:SetHeight(1)
  end
  ns.Bind(f, function()
    local length = scaled(opts.length or 40)
    if vertical then
      f:SetSize(9, length)
    else
      f:SetSize(length, 9)
    end
    line:SetColorTexture(Theme.color("accentDim", 0.6))
  end)
  return f
end

-- Ribbon ----------------------------------------------------------------------

-- opts: height (base px, default 96), fill (theme color, default "surface").
-- local g = ribbon:AddGroup({ key|text = caption, gap = px })
-- g:Add(widget)       widget must be created with the group as its parent;
--                     groups lay widgets out left to right, centered above the caption
-- g:AddTools(opts)    shortcut for W.ToolGrid(g, opts) + g:Add
-- ribbon:Layout(), ribbon:Refresh() (calls :Refresh() of every added widget).
function W.Ribbon(parent, opts)
  opts = opts or {}
  local r = CreateFrame("Frame", nil, parent)
  W.Fill(r, opts.fill or "surface", 1)
  local bottom = r:CreateTexture(nil, "BORDER")
  bottom:SetPoint("BOTTOMLEFT")
  bottom:SetPoint("BOTTOMRIGHT")
  bottom:SetHeight(1)
  ns.Bind(bottom, function(t)
    t:SetColorTexture(Theme.color("accentDim", 0.7))
  end)
  r.groups, r.seps = {}, {}

  function r:Layout()
    r:SetHeight(scaled(opts.height or 96))
    local captionH, pad, gap = scaled(18), scaled(8), scaled(4)
    local x = 0
    for gi, g in ipairs(r.groups) do
      local itemGap = g.gap or gap
      local ix = pad
      for _, item in ipairs(g.items) do
        item:ClearAllPoints()
        item:SetPoint("LEFT", g, "LEFT", ix, captionH / 2)
        ix = ix + item:GetWidth() + itemGap
      end
      local width = max(ix - itemGap + pad, ceil(g.caption:GetStringWidth()) + 2 * pad)
      g:ClearAllPoints()
      g:SetPoint("TOPLEFT", r, "TOPLEFT", x, 0)
      g:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 0)
      g:SetWidth(width)
      if g.sep then
        g.sep:ClearAllPoints()
        g.sep:SetPoint("TOPLEFT", r, "TOPLEFT", x - 4, -8)
        g.sep:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x - 4, 8)
      end
      x = x + width
      if gi == #r.groups then
        r.contentWidth = x
      end
    end
  end

  function r.AddGroup(_, gdef)
    local g = CreateFrame("Frame", nil, r)
    g.items, g.gap = {}, gdef.gap
    g.caption = W.Text(g, { key = gdef.key, text = gdef.text, role = "micro", color = "textMuted", justify = "CENTER" })
    g.caption:SetPoint("BOTTOM", g, "BOTTOM", 0, 4)
    if #r.groups > 0 then
      g.sep = W.Separator(r)
    end
    function g:Add(widget)
      g.items[#g.items + 1] = widget
      r:Layout()
      return widget
    end
    function g:AddTools(toolOpts)
      return g:Add(W.ToolGrid(g, toolOpts))
    end
    r.groups[#r.groups + 1] = g
    r:Layout()
    return g
  end

  function r:Refresh()
    for _, g in ipairs(r.groups) do
      for _, item in ipairs(g.items) do
        if item.Refresh then
          item:Refresh()
        end
      end
    end
  end

  ns.Bind(r, function()
    r:Layout()
    ns.Debounce(r, 0, function()
      r:Layout()
    end)
  end)
  return r
end
