-- Desktop-style widgets in the addon's own design: popup layer, tool button,
-- sliders, menu bar and status bar. The ribbon pieces (tool grid, swatches,
-- icon dropdown, vertical slider, ribbon groups) live in DesktopRibbon.lua.
-- Generic on purpose: windows pass definitions, nothing here knows a feature.
local _, ns = ...
local W, Theme, L, U = ns.W, ns.Theme, ns.L, ns.U
local Focus, IconDraw = ns.Focus, ns.IconDraw

ns.AddLocale("enUS", {
  ["desk.zoom"] = "Zoom",
  ["desk.zoomIn"] = "Zoom in",
  ["desk.zoomOut"] = "Zoom out",
  ["desk.color"] = "Color %s",
})
ns.AddLocale("deDE", {
  ["desk.zoom"] = "Zoom",
  ["desk.zoomIn"] = "Vergrößern",
  ["desk.zoomOut"] = "Verkleinern",
  ["desk.color"] = "Farbe %s",
})

local max, ceil = math.max, math.ceil

local Desktop = {}
ns.Desktop = Desktop

-- Pixel size that grows with the font scale like the page lists (PageKit).
local function scaled(base)
  return ns.PageKit.scaledHeight(base)
end
Desktop.scaled = scaled

-- Definition fields may be a value or a function evaluated when needed.
local function eval(value, ...)
  if type(value) == "function" then
    return value(...)
  end
  return value
end
Desktop.eval = eval

-- Runs now and once more next frame, after every ns.Bind callback of a
-- refresh has re-applied fonts (bound callbacks run in no fixed order).
local function relayout(owner)
  owner:Layout()
  ns.Debounce(owner, 0, function()
    owner:Layout()
  end)
end

-- Colors: "#rrggbb" strings, { r, g, b } arrays or { r =, g =, b = } tables.
function Desktop.parseColor(c)
  if type(c) == "string" then
    return U.hex(c)
  elseif type(c) == "table" then
    return c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0
  end
  return 0, 0, 0
end

function Desktop.sameColor(a, b)
  if a == nil or b == nil then
    return false
  end
  local r1, g1, b1 = Desktop.parseColor(a)
  local r2, g2, b2 = Desktop.parseColor(b)
  return math.abs(r1 - r2) < 0.004 and math.abs(g1 - g2) < 0.004 and math.abs(b1 - b2) < 0.004
end

-- Popup layer -----------------------------------------------------------------
-- One transient popup group is open at a time (menu or gallery). There is no
-- full-screen click blocker: a menu bar must keep receiving hover and clicks,
-- so a watcher frame polls the mouse and closes the group on a press outside.
-- spec = { frames = { popup... }, owner = frame, beforeClose(reason),
--          onClose(reason), move(step), onEscape() -> handled }

local Layer = {}
Desktop.Layer = Layer
local watcher

local function mouseDown()
  return IsMouseButtonDown ~= nil and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) or false
end

local function pointerInside(spec)
  for _, f in ipairs(spec.frames) do
    if f:IsShown() and f:IsMouseOver() then
      return true
    end
  end
  return spec.owner ~= nil and spec.owner:IsMouseOver() == true
end

local function poll(self)
  local spec = Layer.current
  if not spec then
    self:Hide()
    return
  end
  if spec.owner and not spec.owner:IsVisible() then
    Layer.close("hidden")
    return
  end
  local down = mouseDown()
  if down and not self.wasDown and not pointerInside(spec) then
    Layer.close("outside")
  end
  self.wasDown = down
end

function Layer.open(spec)
  Layer.close("replace")
  Layer.current = spec
  if not watcher then
    watcher = CreateFrame("Frame", nil, UIParent)
    watcher:SetScript("OnUpdate", poll)
    Layer.watcher = watcher
  end
  watcher.wasDown = mouseDown()
  watcher:Show()
end

-- Callbacks are copied before Hide(): hide handlers must not be able to
-- clear them before they run.
function Layer.close(reason)
  local spec = Layer.current
  if not spec then
    return false
  end
  Layer.current = nil
  local before, after = spec.beforeClose, spec.onClose
  if before then
    ns.Safe("popup-before-close", before, reason)
  end
  for _, f in ipairs(spec.frames) do
    f:Hide()
  end
  if watcher then
    watcher:Hide()
  end
  if after then
    ns.Safe("popup-close", after, reason)
  end
  return true
end

-- Esc: a nested popup closes first, then the whole group.
function Layer.escape()
  local spec = Layer.current
  if not spec then
    return false
  end
  if spec.onEscape and spec.onEscape() then
    return true
  end
  return Layer.close("escape")
end

-- Place a popup below an anchor in the anchor's scale (popups hang on UIParent).
function Layer.place(popup, anchor, point, relPoint, x, y)
  popup:ClearAllPoints()
  popup:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
  popup:SetPoint(point or "TOPLEFT", anchor, relPoint or "BOTTOMLEFT", x or 0, y or 0)
end

function Layer.newPopup(fill)
  local p = CreateFrame("Frame", nil, UIParent)
  p:SetFrameStrata("TOOLTIP")
  p:SetClampedToScreen(true)
  p:EnableMouse(true)
  W.Fill(p, fill or "surface2", 1)
  W.Border(p, "accentDim", 1)
  p:Hide()
  return p
end

-- Esc (the main window key handler calls ns.Popups.close) and Up/Down/Tab
-- (ns.Focus.move) reach the open popup group through the existing entry points.
local closeDropdown = ns.Popups.close
function ns.Popups.close()
  local closed = Layer.escape()
  return closeDropdown() or closed
end

local moveFocus = Focus.move
function Focus.move(step)
  local spec = Layer.current
  if spec and spec.move then
    return spec.move(step)
  end
  return moveFocus(step)
end

ns.On("FG_UI_REFRESHED", function()
  Layer.close("refresh")
end)

-- Tool button -----------------------------------------------------------------
-- def: glyph (IconDraw name, text, or drawer fn(p, px)), letter (fallback text),
--   key|text (optional label right of the icon), width (label buttons),
--   tooltip / tooltipText (locale keys), selected (bool|fn), enabled (bool|fn),
--   onClick(button), size (base px, default 32), chevron (small arrow at right).
-- The def is read on every paint; b:SetDef(newDef) re-targets a pooled button.

local function toolGeometry(b)
  local def = b.def
  local size = scaled(def.size or 32)
  local iconPx = max(12, size - 8)
  local width = size
  b.icon:SetIconSize(iconPx)
  b.icon:ClearAllPoints()
  b.icon:SetPoint("LEFT", (size - iconPx) / 2, 0)
  if def.key or def.text then
    if not b.label then
      b.label = W.Text(b, { role = "ui", justify = "LEFT" })
    end
    W.SetText(b.label, def.key, def.text)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.label:Show()
    width = def.width and scaled(def.width) or (size + 8 + ceil(b.label:GetStringWidth()) + 12)
  elseif b.label then
    b.label:Hide()
  end
  if def.chevron then
    if not b.chevron then
      b.chevron = IconDraw.new(b, 8)
      b.chevron:Draw("chevron-down")
    end
    b.chevron:ClearAllPoints()
    b.chevron:SetPoint("RIGHT", -4, 0)
    b.chevron:Show()
    width = width + scaled(12)
  elseif b.chevron then
    b.chevron:Hide()
  end
  b:SetSize(width, size)
end

local function toolPaint(b)
  local def = b.def
  local enabled = eval(def.enabled, b) ~= false
  local selected = eval(def.selected, b) and true or false
  local active = enabled and (b.hover or Focus.current == b)
  b.fgSelected, b.fgEnabled = selected, enabled
  if selected then
    -- Filled and outlined: the state never rests on color alone.
    local r, g, bl = Theme.rgb("surface3")
    local lift = active and 0.04 or 0
    b.bg:SetColorTexture(r + lift, g + lift, bl + lift, 1)
    b.border.set("accent2", 1)
    b.border.show(true)
  elseif active then
    b.bg:SetColorTexture(Theme.color("surface2"))
    b.border.set("accentDim", 0.8)
    b.border.show(true)
  else
    b.bg:SetColorTexture(0, 0, 0, 0)
    b.border.show(false)
  end
  local tint = (not enabled and "textMuted") or (selected and "accent") or (active and "text") or "textSecondary"
  b.icon:SetTint(tint)
  b.icon:SetAlpha(enabled and 1 or 0.45)
  if b.chevron then
    b.chevron:SetTint(tint)
  end
  if b.label then
    W.SetColor(b.label, tint)
  end
end

function W.ToolButton(parent, def)
  local b = CreateFrame("Button", nil, parent)
  b.hover = false
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.border = W.Border(b, "accent2", 1)
  b.border.show(false)
  b.icon = IconDraw.new(b, 16)

  function b:SetDef(newDef)
    self.def = newDef
    self.icon.glyph = nil
    toolGeometry(self)
    self.icon:Draw(newDef.glyph, newDef.letter)
    toolPaint(self)
  end
  function b:SetGlyph(glyph)
    self.def.glyph = glyph
    self.icon:Draw(glyph, self.def.letter)
  end
  b.Refresh = toolPaint

  b:SetScript("OnEnter", function(self)
    self.hover = true
    toolPaint(self)
    local d = self.def
    if d.tooltip then
      ns.ShowTooltip(self, L[d.tooltip], d.tooltipText and L[d.tooltipText])
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    toolPaint(self)
    ns.HideTooltip()
  end)
  b:SetScript(
    "OnClick",
    ns.Wrap("tool-button", function(self)
      if not self.fgEnabled then
        return
      end
      local onClick = self.def.onClick
      if onClick then
        onClick(self)
      end
      toolPaint(self)
    end)
  )
  Focus.register(b, function(self)
    self:Click()
  end)
  b.def = def
  toolGeometry(b)
  b.icon:Draw(def.glyph, def.letter)
  ns.Bind(b, function(self)
    toolGeometry(self)
    toolPaint(self)
  end)
  return b
end

-- Sliders -----------------------------------------------------------------------

-- o: min, max, step, get(), set(v), invert (vertical only, default true: the
-- top is the maximum), onValue(v) after each change, tooltip (locale key).
-- Returns the native Slider with :SyncValue() (silent, reads o.get) and
-- :SetUserValue(v) (like a drag: clamps, rounds, calls o.set).
local function buildSlider(parent, vertical, o)
  local s = CreateFrame("Slider", nil, parent)
  s:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
  s:EnableMouse(true)
  local lo, hi, step = o.min, o.max, o.step or 1
  -- The client's vertical slider runs top (min) to bottom (max).
  local invert = vertical and o.invert ~= false
  local function toRaw(v)
    return invert and (lo + hi - v) or v
  end
  s.fgInvert, s.fgToRaw = invert, toRaw
  s:SetMinMaxValues(lo, hi)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then
    s:SetObeyStepOnDrag(true)
  end
  local track = s:CreateTexture(nil, "BACKGROUND")
  local thumb = s:CreateTexture(nil, "ARTWORK")
  if vertical then
    track:SetPoint("TOP")
    track:SetPoint("BOTTOM")
    track:SetWidth(4)
    thumb:SetSize(18, 10)
  else
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    thumb:SetSize(10, 18)
  end
  s:SetThumbTexture(thumb)
  s.hover = false
  local function paint()
    track:SetColorTexture(Theme.color("accentDim", 0.7))
    thumb:SetColorTexture(Theme.color(s.hover and "accent" or "accent2"))
  end
  ns.Bind(s, paint)
  s:SetScript("OnEnter", function()
    s.hover = true
    paint()
  end)
  s:SetScript("OnLeave", function()
    s.hover = false
    paint()
  end)
  local function current()
    return U.clamp(o.get(), lo, hi)
  end
  local syncing = false
  s:SetScript(
    "OnValueChanged",
    ns.Wrap("slider", function(_, raw)
      if syncing then
        return
      end
      local v = U.clamp(U.round(invert and (lo + hi - raw) or raw, step), lo, hi)
      if o.onValue then
        o.onValue(v)
      end
      o.set(v)
    end)
  )
  function s:SyncValue()
    syncing = true
    s:SetValue(toRaw(current()))
    syncing = false
    if o.onValue then
      o.onValue(current())
    end
  end
  function s:SetUserValue(v)
    s:SetValue(toRaw(U.clamp(U.round(v, step), lo, hi)))
  end
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(_, delta)
    s:SetUserValue(current() + delta * step)
  end)
  Focus.register(s, nil)
  function s.fgArrow(_, delta)
    s:SetUserValue(current() + delta * step)
  end
  if o.tooltip then
    W.AttachTooltip(s, o.tooltip)
  end
  s:SyncValue()
  return s
end
Desktop.buildSlider = buildSlider

-- Compact horizontal slider with a value readout and - / + buttons, used for
-- the status bar zoom. o: min, max, step, get, set, format(v), zoomTips (bool).
-- Returns a Frame with .slider, :SyncValue(), :SetUserValue(v).
function Desktop.HSlider(parent, o)
  local f = CreateFrame("Frame", nil, parent)
  local fmt = o.format or function(v)
    return string.format("%d %%", v)
  end
  f.value = W.Text(f, { role = "ui", color = "textSecondary", justify = "RIGHT" })
  f.value:SetPoint("LEFT", 0, 0)
  local function stepBy(dir)
    return function()
      f.slider:SetUserValue(U.clamp(o.get(), o.min, o.max) + dir * (o.step or 1))
    end
  end
  f.minus = W.Action(f, { icon = "minus", size = 20, tooltip = "desk.zoomOut", onClick = stepBy(-1) })
  f.minus:SetPoint("LEFT", f.value, "RIGHT", 4, 0)
  f.plus = W.Action(f, { icon = "plus", size = 20, tooltip = "desk.zoomIn", onClick = stepBy(1) })
  f.plus:SetPoint("RIGHT", 0, 0)
  local inner = {}
  for k, v in pairs(o) do
    inner[k] = v
  end
  inner.onValue = function(v)
    f.value:SetText(fmt(v))
  end
  f.slider = buildSlider(f, false, inner)
  f.slider:SetHeight(16)
  f.slider:SetPoint("LEFT", f.minus, "RIGHT", 4, 0)
  f.slider:SetPoint("RIGHT", f.plus, "LEFT", -4, 0)
  ns.Bind(f, function()
    f.value:SetWidth(scaled(44))
    f:SetHeight(scaled(22))
  end)
  function f:SyncValue()
    f.slider:SyncValue()
  end
  function f:SetUserValue(v)
    f.slider:SetUserValue(v)
  end
  return f
end

-- Menu bar ----------------------------------------------------------------------

local ROW_H, SEP_H = 26, 9
local Menus = { active = nil }
Desktop.Menus = Menus

local function paintRow(row)
  if row.isSeparator then
    row.hl:SetColorTexture(0, 0, 0, 0)
    row.line:Show()
    row.line:SetColorTexture(Theme.color("accentDim", 0.6))
    row.label:Hide()
    row.shortcut:Hide()
    row.check:Hide()
    row.arrow:Hide()
    row.focusBorder.show(false)
    return
  end
  row.line:Hide()
  row.label:Show()
  row.shortcut:Show()
  local lit = (row.hover or row.kbd) and not row.disabled
  if lit then
    row.hl:SetColorTexture(Theme.color("surface3"))
  else
    row.hl:SetColorTexture(0, 0, 0, 0)
  end
  -- Keyboard focus gets its own outline, the shared focus ring can sit under the popup.
  row.focusBorder.show(row.kbd == true and not row.disabled)
  W.SetColor(row.label, row.disabled and "textMuted" or "text")
  row.label:SetAlpha(row.disabled and 0.55 or 1)
  row.shortcut:SetAlpha(row.disabled and 0.55 or 1)
  row.check:SetTint(row.disabled and "textMuted" or "accent")
  row.arrow:SetTint(row.disabled and "textMuted" or "textSecondary")
end

local function refreshRow(row)
  if row.isSeparator or not row.item then
    row:Disable()
    paintRow(row)
    return
  end
  local item = row.item
  row.disabled = eval(item.enabled, item) == false
  row.checked = eval(item.checked, item) and true or false
  if row.disabled then
    row:Disable()
  else
    row:Enable()
  end
  row.check:SetShown(row.checked)
  row.arrow:SetShown(row.level == 1 and item.items ~= nil)
  W.SetText(row.shortcut, nil, eval(item.shortcut, item) or "")
  paintRow(row)
end

local function refreshRows(p)
  for i = 1, p.count or 0 do
    refreshRow(p.rows[i])
  end
end

local mainPopup, subPopup, closeSub, openSub, focusRow, navigable

local function newRow(p)
  local row = CreateFrame("Button", nil, p)
  row.popup = p
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints()
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("LEFT", 8, 0)
  row.line:SetPoint("RIGHT", -8, 0)
  row.line:SetHeight(1)
  row.focusBorder = W.Border(row, "actionHi", 1, 1)
  row.focusBorder.show(false)
  row.check = IconDraw.new(row, 12)
  row.check:SetPoint("LEFT", 9, 0)
  row.check:Draw("check")
  row.label = W.Text(row, { role = "ui" })
  row.label:SetPoint("LEFT", 30, 0)
  row.shortcut = W.Text(row, { role = "ui", color = "textMuted", justify = "RIGHT" })
  row.shortcut:SetPoint("RIGHT", -12, 0)
  row.arrow = IconDraw.new(row, 10)
  row.arrow:SetPoint("RIGHT", -8, 0)
  row.arrow:Draw("chevron-right")
  row.hover, row.kbd = false, false

  row:SetScript("OnEnter", function(self)
    if self.isSeparator then
      return
    end
    self.hover = true
    paintRow(self)
    if self.popup == Desktop.menuPopup then
      if self.item and self.item.items and not self.disabled then
        openSub(self, false)
      else
        closeSub()
      end
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.hover = false
    paintRow(self)
  end)
  row:SetScript(
    "OnClick",
    ns.Wrap("menu-item", function(self)
      local item = self.item
      if self.isSeparator or self.disabled or not item then
        return
      end
      if item.items and self.level == 1 then
        openSub(self, Focus.current == self)
        return
      end
      -- Close first, then run: the callback may open dialogs or move focus.
      local fn = item.onClick
      Layer.close("select")
      if fn then
        fn(item)
      end
    end)
  )
  Focus.register(row, function(self)
    self:Click()
  end)
  function row.fgArrow(self, delta)
    Menus.arrow(self, delta)
  end
  return row
end

local function fillPopup(p, items, level, minWidth)
  local entries = {}
  for _, item in ipairs(items) do
    -- separator = true on a labeled item draws the line above it.
    if item.separator and #entries > 0 then
      entries[#entries + 1] = { sep = true }
    end
    if item.key or item.text then
      entries[#entries + 1] = { item = item }
    end
  end
  local rowH, sepH = scaled(ROW_H), scaled(SEP_H)
  local labelW, shortW, y = 0, 0, 1
  p.rows = p.rows or {}
  for i, e in ipairs(entries) do
    local row = p.rows[i]
    if not row then
      row = newRow(p)
      p.rows[i] = row
    end
    row.item, row.isSeparator, row.level = e.item, e.sep == true, level
    row.hover, row.kbd = false, false
    local h = e.sep and sepH or rowH
    row:ClearAllPoints()
    row:SetHeight(h)
    row:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -y)
    row:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -y)
    y = y + h
    if e.item then
      W.SetText(row.label, e.item.key, e.item.text)
      W.SetText(row.shortcut, nil, eval(e.item.shortcut, e.item) or "")
      labelW = max(labelW, row.label:GetStringWidth())
      shortW = max(shortW, row.shortcut:GetStringWidth())
    end
    row:Show()
  end
  for i = #entries + 1, #p.rows do
    p.rows[i]:Hide()
    p.rows[i].item = nil
  end
  p.count = #entries
  refreshRows(p)
  local width = scaled(30) + ceil(labelW) + (shortW > 0 and scaled(28) + ceil(shortW) or 0) + scaled(24)
  p:SetSize(max(width, minWidth or 0, scaled(120)), y + 1)
end

function mainPopup()
  if not Desktop.menuPopup then
    Desktop.menuPopup = Layer.newPopup("surface2")
  end
  return Desktop.menuPopup
end

function subPopup()
  if not Desktop.subPopup then
    Desktop.subPopup = Layer.newPopup("surface2")
  end
  return Desktop.subPopup
end

function navigable(p)
  local list = {}
  for i = 1, p.count or 0 do
    local row = p.rows[i]
    if row:IsShown() and not row.isSeparator and not row.disabled then
      list[#list + 1] = row
    end
  end
  return list
end

function focusRow(row)
  for _, p in ipairs({ mainPopup(), subPopup() }) do
    for i = 1, p.count or 0 do
      local r = p.rows[i]
      if r.kbd then
        r.kbd = false
        paintRow(r)
      end
    end
  end
  if row then
    row.kbd = true
    Focus.set(row)
    paintRow(row)
  end
end

function closeSub()
  local sp = Desktop.subPopup
  local active = Menus.active
  if not sp or not sp:IsShown() then
    return false
  end
  local parentRow = active and active.subRow
  sp:Hide()
  if active then
    active.subRow = nil
  end
  if Focus.current and Focus.current.popup == sp then
    focusRow(parentRow)
  end
  return true
end

function openSub(row, byKeyboard)
  local active = Menus.active
  if not active or not row.item or not row.item.items then
    return
  end
  local sp = subPopup()
  if not (active.subRow == row and sp:IsShown()) then
    fillPopup(sp, row.item.items, 2, 0)
    Layer.place(sp, row, "TOPLEFT", "TOPRIGHT", 0, 1)
    sp:Show()
    active.subRow = row
  end
  if byKeyboard then
    focusRow(navigable(sp)[1])
  end
end

-- Up/Down inside an open menu (called through Focus.move).
local function menuMove(step)
  local cur = Focus.current
  local p = mainPopup()
  if cur and cur.popup == Desktop.subPopup and cur.popup:IsShown() then
    p = cur.popup
  end
  local list = navigable(p)
  if #list == 0 then
    return
  end
  local index = 0
  for i, row in ipairs(list) do
    if row == cur then
      index = i
    end
  end
  index = index + step
  if index < 1 then
    index = #list
  elseif index > #list then
    index = 1
  end
  focusRow(list[index])
end

-- Left/Right on a menu row: open or leave a submenu, else switch the menu.
function Menus.arrow(row, delta)
  local active = Menus.active
  if not active then
    return
  end
  if row.popup == Desktop.subPopup and delta < 0 then
    closeSub()
    return
  end
  if row.popup == Desktop.menuPopup and delta > 0 and row.item and row.item.items and not row.disabled then
    openSub(row, true)
    return
  end
  local count = #active.bar.titles
  active.bar:Open((active.index - 1 + delta) % count + 1, true)
end

local function paintTitle(b)
  local bar = b.bar
  local open = bar.openIndex == b.index
  if open then
    b.bg:SetColorTexture(Theme.color("surface3"))
  elseif b.hover then
    b.bg:SetColorTexture(Theme.color("surface2"))
  else
    b.bg:SetColorTexture(0, 0, 0, 0)
  end
  -- The open title also carries an underline, not only a fill.
  b.underline:SetShown(open)
  b.underline:SetColorTexture(Theme.color("accent2"))
  W.SetColor(b.label, open and "accent" or "text")
end

local function paintTitles(bar)
  for _, b in ipairs(bar.titles) do
    paintTitle(b)
  end
end

-- def = { { key|text, items = { { key|text, onClick(item), shortcut = string|fn,
--           checked = bool|fn, enabled = bool|fn, separator = true,
--           items = { ...one submenu level... } } } }, ... }
-- A table with only separator = true is a pure divider; separator = true on a
-- labeled item draws the divider above it. Item states are evaluated every
-- time the menu opens and on bar:Refresh().
-- opts: onClose(reason, bar) with reason select|escape|outside|hidden|replace|
--   refresh|api, height (base px, default 28), fill (theme color, false = none).
-- Methods: Open(indexOrKey, byKeyboard), Close(), IsOpen(), Refresh(), Layout().
function W.MenuBar(parent, def, opts)
  opts = opts or {}
  local bar = CreateFrame("Frame", nil, parent)
  bar.def, bar.opts, bar.titles = def, opts, {}
  if opts.fill ~= false then
    W.Fill(bar, opts.fill or "surface", 1)
  end

  local prev
  for i, menu in ipairs(def) do
    local b = CreateFrame("Button", nil, bar)
    b.bar, b.index, b.menu, b.hover = bar, i, menu, false
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.underline = b:CreateTexture(nil, "ARTWORK")
    b.underline:SetPoint("BOTTOMLEFT", 6, 0)
    b.underline:SetPoint("BOTTOMRIGHT", -6, 0)
    b.underline:SetHeight(2)
    b.label = W.Text(b, { key = menu.key, text = menu.text, role = "ui", justify = "CENTER" })
    b.label:SetPoint("CENTER")
    b:SetPoint("TOPLEFT", prev or bar, prev and "TOPRIGHT" or "TOPLEFT", prev and 0 or 4, 0)
    b:SetPoint("BOTTOMLEFT", prev or bar, prev and "BOTTOMRIGHT" or "BOTTOMLEFT", prev and 0 or 4, 0)
    b:SetScript("OnEnter", function(self)
      self.hover = true
      if bar.openIndex and bar.openIndex ~= i then
        bar:Open(i)
      end
      paintTitle(self)
    end)
    b:SetScript("OnLeave", function(self)
      self.hover = false
      paintTitle(self)
    end)
    b:SetScript(
      "OnClick",
      ns.Wrap("menu-title", function()
        if bar.openIndex == i then
          Layer.close("api")
        else
          bar:Open(i)
        end
      end)
    )
    Focus.register(b, function()
      if bar.openIndex == i then
        Layer.close("api")
      else
        bar:Open(i, true)
      end
    end)
    ns.Bind(b, paintTitle)
    bar.titles[i] = b
    prev = b
  end

  function bar:Layout()
    bar:SetHeight(scaled(opts.height or 28))
    for _, b in ipairs(bar.titles) do
      b:SetWidth(ceil(b.label:GetStringWidth()) + scaled(20))
    end
  end

  local function indexOf(which)
    if type(which) == "number" then
      return bar.titles[which] and which or nil
    end
    for i, menu in ipairs(def) do
      if menu.key == which or menu.id == which then
        return i
      end
    end
    return nil
  end

  function bar:Open(which, byKeyboard)
    local index = indexOf(which)
    if not index then
      return false
    end
    local active = Menus.active
    if active and active.bar ~= bar then
      Layer.close("replace")
      active = nil
    end
    local main, sub = mainPopup(), subPopup()
    if not active then
      active = { bar = bar }
      Menus.active = active
      Layer.open({
        frames = { main, sub },
        owner = bar,
        beforeClose = function(reason)
          -- Focus moves while the rows still exist; hiding them would clear it.
          local cur = Focus.current
          if cur and (cur.popup == main or cur.popup == sub) then
            if reason == "escape" and active.kbd then
              Focus.set(bar.titles[active.index])
            else
              Focus.clear()
            end
          end
        end,
        onClose = function(reason)
          Menus.active = nil
          bar.openIndex = nil
          paintTitles(bar)
          if opts.onClose then
            opts.onClose(reason, bar)
          end
        end,
        move = menuMove,
        onEscape = closeSub,
      })
    end
    active.index, active.kbd = index, byKeyboard == true
    bar.openIndex = index
    closeSub()
    if Focus.current and Focus.current.popup == main then
      Focus.clear()
    end
    local title = bar.titles[index]
    fillPopup(main, title.menu.items or {}, 1, title:GetWidth())
    Layer.place(main, title, "TOPLEFT", "BOTTOMLEFT", 0, 0)
    main:Show()
    paintTitles(bar)
    if byKeyboard then
      focusRow(navigable(main)[1])
    end
    return true
  end

  function bar:Close()
    if bar.openIndex then
      return Layer.close("api")
    end
    return false
  end

  function bar:IsOpen()
    return bar.openIndex ~= nil
  end

  function bar:Refresh()
    paintTitles(bar)
    if bar.openIndex then
      refreshRows(mainPopup())
      if Desktop.subPopup and Desktop.subPopup:IsShown() then
        refreshRows(Desktop.subPopup)
      end
    end
  end

  bar:HookScript("OnHide", function()
    if bar.openIndex then
      Layer.close("hidden")
    end
  end)
  ns.Bind(bar, relayout)
  return bar
end

-- Status bar --------------------------------------------------------------------

local SEG_PAD, SEG_SEP = 8, 1

-- def = { height (base px, default 24), fill, segments = { seg... } }
-- seg: type = "text" (default) | "slider" | "button"
--   all:    id, priority (number: higher hides first when narrow; nil = never),
--           spacer (no separator next to it)
--   text:   key|text (initial), align = LEFT|CENTER|RIGHT, width (fixed base px),
--           fit (width follows the text), minWidth; without width/fit the
--           segment is flexible and takes the leftover space
--   slider: min, max, step, value, onChange(v), format(v), width (default 190)
--   button: glyph, tooltip, tooltipText, selected, onClick, width
-- Methods: SetSegment(indexOrId, textOrNumber), GetSegment(i),
--   IsSegmentShown(i), Layout(width), Refresh().
function W.StatusBar(parent, def)
  local bar = CreateFrame("Frame", nil, parent)
  W.Fill(bar, def.fill or "surface", 1)
  local top = bar:CreateTexture(nil, "BORDER")
  top:SetPoint("TOPLEFT")
  top:SetPoint("TOPRIGHT")
  top:SetHeight(1)
  ns.Bind(top, function(t)
    t:SetColorTexture(Theme.color("accentDim", 0.7))
  end)
  bar.segs, bar.byId, bar.seps = {}, {}, {}

  for i, s in ipairs(def.segments) do
    local seg = CreateFrame("Frame", nil, bar)
    seg.def, seg.index, seg.kind = s, i, s.type or "text"
    if seg.kind == "slider" then
      seg.sliderValue = s.value or s.min
      seg.slider = Desktop.HSlider(seg, {
        min = s.min,
        max = s.max,
        step = s.step,
        format = s.format,
        get = function()
          return seg.sliderValue
        end,
        set = function(v)
          seg.sliderValue = v
          if s.onChange then
            s.onChange(v)
          end
        end,
        tooltip = s.tooltip or "desk.zoom",
      })
      seg.slider:SetPoint("LEFT", SEG_PAD, 0)
      seg.slider:SetPoint("RIGHT", -SEG_PAD, 0)
    elseif seg.kind == "button" then
      seg.button = W.ToolButton(seg, {
        glyph = s.glyph,
        letter = s.letter,
        tooltip = s.tooltip,
        tooltipText = s.tooltipText,
        selected = s.selected,
        onClick = s.onClick,
        size = 20,
      })
      seg.button:SetPoint("CENTER")
    else
      seg.fs = W.Text(seg, { key = s.key, text = s.text, role = "ui", color = "textSecondary", justify = s.align })
      seg.fs:SetPoint("LEFT", SEG_PAD, 0)
      if not s.fit then
        seg.fs:SetPoint("RIGHT", -SEG_PAD, 0)
      end
      seg.value = s.text
    end
    bar.segs[i] = seg
    if s.id then
      bar.byId[s.id] = seg
    end
  end

  local function segOf(which)
    return bar.segs[which] or bar.byId[which]
  end

  local function needOf(seg)
    local s = seg.def
    if seg.kind == "slider" then
      return scaled(s.width or 190)
    elseif seg.kind == "button" then
      return scaled(s.width or 28)
    elseif s.fit then
      return ceil(seg.fs:GetStringWidth()) + 2 * SEG_PAD
    elseif s.width then
      return scaled(s.width)
    end
    return scaled(s.minWidth or 40)
  end

  local function isFlex(seg)
    local s = seg.def
    return seg.kind == "text" and not s.fit and not s.width
  end

  local function sepTexture(k)
    local t = bar.seps[k]
    if not t then
      t = bar:CreateTexture(nil, "ARTWORK")
      t:SetWidth(SEG_SEP)
      bar.seps[k] = t
    end
    return t
  end

  function bar:Layout(width)
    local avail = width or bar:GetWidth()
    if not avail or avail <= 0 then
      return
    end
    for _, seg in ipairs(bar.segs) do
      seg.need, seg.fits = needOf(seg), true
    end
    local function total()
      local n, sum = 0, 0
      for _, seg in ipairs(bar.segs) do
        if seg.fits then
          n = n + 1
          sum = sum + seg.need
        end
      end
      return sum + max(0, n - 1) * SEG_SEP
    end
    -- Narrow: drop the segment with the highest priority number first, later
    -- ones before earlier ones; segments without a priority always stay.
    while total() > avail do
      local victim
      for _, seg in ipairs(bar.segs) do
        local p = seg.def.priority
        if seg.fits and p and (not victim or p >= victim.def.priority) then
          victim = seg
        end
      end
      if not victim then
        break
      end
      victim.fits = false
    end
    local extra, weight = avail - total(), 0
    for _, seg in ipairs(bar.segs) do
      if seg.fits and isFlex(seg) then
        weight = weight + (type(seg.def.flex) == "number" and seg.def.flex or 1)
      end
    end
    local x, prevSeg, sepCount = 0, nil, 0
    for _, seg in ipairs(bar.segs) do
      if not seg.fits then
        seg:Hide()
      else
        if prevSeg then
          if not (prevSeg.def.spacer or seg.def.spacer) then
            sepCount = sepCount + 1
            local t = sepTexture(sepCount)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -6)
            t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 5)
            t:SetColorTexture(Theme.color("accentDim", 0.6))
            t:Show()
          end
          x = x + SEG_SEP
        end
        local w = seg.need
        if weight > 0 and isFlex(seg) then
          w = w + math.floor(extra * (type(seg.def.flex) == "number" and seg.def.flex or 1) / weight)
        end
        seg:ClearAllPoints()
        seg:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -1)
        seg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
        seg:SetWidth(w)
        seg:Show()
        x = x + w
        prevSeg = seg
      end
    end
    for k = sepCount + 1, #bar.seps do
      bar.seps[k]:Hide()
    end
  end

  function bar:SetSegment(which, value)
    local seg = segOf(which)
    if not seg then
      return false
    end
    if seg.kind == "text" then
      seg.value = value
      W.SetText(seg.fs, nil, value ~= nil and tostring(value) or "")
      if seg.def.fit and seg.need ~= ceil(seg.fs:GetStringWidth()) + 2 * SEG_PAD then
        bar:Layout()
      end
    elseif seg.kind == "slider" then
      seg.sliderValue = U.clamp(value, seg.def.min, seg.def.max)
      seg.slider:SyncValue()
    end
    return true
  end

  function bar:GetSegment(which)
    local seg = segOf(which)
    if not seg then
      return nil
    end
    return seg.kind == "slider" and seg.sliderValue or seg.value
  end

  function bar:IsSegmentShown(which)
    local seg = segOf(which)
    return seg ~= nil and seg.fits == true
  end

  -- Re-evaluates the selected state of button segments.
  function bar:Refresh()
    for _, seg in ipairs(bar.segs) do
      if seg.button then
        seg.button:Refresh()
      end
    end
  end

  bar:SetScript("OnSizeChanged", function(_, w)
    bar:Layout(w)
  end)
  ns.Bind(bar, function()
    bar:SetHeight(scaled(def.height or 24))
    relayout(bar)
  end)
  return bar
end
