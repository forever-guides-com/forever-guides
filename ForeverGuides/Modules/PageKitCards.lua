-- Card pieces of the page kit, built on W.Panel and K.IconSlot: framed icon, section card, card row, hero,
-- attribute and stat lines, key/value grid, tags. Every piece that sits in a W.Stack answers
-- fgGridLayout(width) -> height; pooled parts answer fgLayout(width) -> height (same function). Space tokens are
-- read at layout time, never into constants. Interactive parts are plain frames registered with ns.Focus
-- (tooltip on hover and on focus, Enter or Space activates), no raw buttons.
local _, ns = ...
local W, Theme, L, K = ns.W, ns.Theme, ns.L, ns.PageKit

local scaled = K.scaledHeight

local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local UNKNOWN_ICON = 134400
local TAG_PAD, TAG_ICON = 6, 12

-- Caps ------------------------------------------------------------------------------------------------

-- The client's string.upper leaves umlauts and accents alone. Latin-1 letters are the two bytes C3 xx, the
-- upper case is xx - 32 (the sharp s becomes SS). Color, texture and link escapes stay as they are.
local function capsPlain(s)
  s = s:gsub("\195\159", "SS")
  s = s:gsub("[a-z]", string.upper)
  s = s:gsub("\195([\160-\182\184-\190])", function(c)
    return "\195" .. string.char(c:byte() - 32)
  end)
  return s
end

function K.Caps(text)
  text = tostring(text or "")
  local out, i = {}, 1
  while i <= #text do
    local bar = text:find("|", i, true)
    if not bar then
      out[#out + 1] = capsPlain(text:sub(i))
      break
    end
    out[#out + 1] = capsPlain(text:sub(i, bar - 1))
    local esc = text:match("^|c%x%x%x%x%x%x%x%x", bar)
      or text:match("^|T.-|t", bar)
      or text:match("^|H.-|h", bar)
      or text:match("^|[rhnt|]", bar)
      or "|"
    out[#out + 1] = esc
    i = bar + #esc
  end
  return table.concat(out)
end

-- Shared helpers ----------------------------------------------------------------------------------------

local function showTip(f)
  local tip = f.fgTip
  if type(tip) == "table" then
    ns.ShowTooltip(f, tip.title, tip.text)
  elseif tip then
    ns.ShowTooltip(f, tip)
  end
end

-- Makes a plain frame answer to mouse and keyboard: tip (string or { title, text }), click (function), name (accessible name).
-- Calling it again with nothing switches the frame off, so a pooled frame can be reused.
local function interactive(f, tip, click, name)
  f.fgTip, f.fgClick, f.fgName = tip, click, name
  if (tip or click) and not f.fgWired then
    f.fgWired = true
    f:SetScript("OnEnter", function(self)
      if self.fgTip then
        showTip(self)
      end
    end)
    f:SetScript("OnLeave", ns.HideTooltip)
    f:SetScript("OnMouseUp", function(self, button)
      if self.fgClick and button == "LeftButton" then
        self.fgClick()
      end
    end)
    f.fgOnFocus = function(self)
      if self.fgTip then
        showTip(self)
      end
    end
    f.fgOnBlur = ns.HideTooltip
    -- Focus only walks enabled frames: a switched-off pooled frame is skipped.
    f.IsEnabled = function(self)
      return self.fgTip ~= nil or self.fgClick ~= nil
    end
    ns.Focus.register(f, function(self)
      if self.fgClick then
        self.fgClick()
      end
    end)
  end
  f:EnableMouse(tip ~= nil or click ~= nil)
end

local function textOf(o)
  if o.key then
    return L[o.key]
  end
  return o.text or ""
end

-- IconFrame -------------------------------------------------------------------------------------------

local function canMask(f)
  return type(f.CreateMaskTexture) == "function" and type(f.disc.AddMaskTexture) == "function"
end

local function paintFrame(f)
  local name, alpha = f.edge, 1
  if not name then
    name = "lineStrong"
    alpha = Theme.highContrast() and 1 or Theme.fillAlpha.lineStrong
  end
  if f.round then
    f.disc:SetColorTexture(Theme.color(name, alpha))
    f.disc:Show()
    f.rim.show(false)
    f.shade:Hide()
    f.bevel:Hide()
  else
    f.disc:Hide()
    f.rim.set(name, alpha)
    f.rim.show(true)
    f.shade:Show()
    f.bevel:SetShown(f.shape == "round")
  end
  f.glow.show(f.selected == true)
end

local function repaintSpec(f)
  local inner = f.inner
  inner:SetSpec(inner.iconSpec)
  -- The caller-sized frame has its own rim, the inner outline of crests would double it.
  inner.outline:Hide()
  inner.icon:SetDesaturated(f.desaturated == true)
end

local function fitFrame(f, px)
  f.size = px
  f.inset = (f.round and px >= 40) and 2 or 1
  local inner, side = f.inner, px - 2 * f.inset
  f:SetSize(px, px)
  inner.iconSize = side
  inner:SetSize(side, side)
  inner.slot:SetSize(side, side)
  inner.badge:SetSize(side, side)
  inner:ClearAllPoints()
  inner:SetPoint("TOPLEFT", f.inset, -f.inset)
  repaintSpec(f)
end

-- Framed game icon. opts: size (24, 28, 40 or 64, default 28), shape ("square" or "round", fixed at creation),
-- texture (path or fileID) or spec (K.IconSlot spec), edge (token or "#rrggbb", default the faint line),
-- desaturate, glow (gold 2 px edge), tip (string or { title, text }: tooltip and keyboard focus), onClick,
-- name (accessible name). Round needs the client's mask texture; without it a framed square with a bevel
-- stands in (f.round is false then). Methods: SetTexture, SetSpec, SetEdge, SetDesaturated, SetSelected,
-- Resize(px), SetTip(tip, onClick, name).
function K.IconFrame(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  f.shape = opts.shape == "round" and "round" or "square"
  f.edge, f.selected, f.desaturated = opts.edge, opts.glow == true, opts.desaturate == true
  f.shade = f:CreateTexture(nil, "BACKGROUND")
  f.shade:SetAllPoints()
  f.shade:SetColorTexture(Theme.scrim(0.6))
  f.disc = f:CreateTexture(nil, "BORDER")
  f.disc:SetAllPoints()
  f.round = f.shape == "round" and canMask(f)
  f.rim = W.Border(f, "lineStrong", Theme.fillAlpha.lineStrong)
  f.glow = W.Border(f, "selected", 1, 2)
  local bevelHost = CreateFrame("Frame", nil, f)
  bevelHost:SetPoint("TOPLEFT", 1, -1)
  bevelHost:SetPoint("BOTTOMRIGHT", -1, 1)
  W.Border(bevelHost, "hover", 0.25)
  f.bevel = bevelHost
  f.inner = K.IconSlot(f, opts.spec or { kind = "texture", texture = opts.texture or UNKNOWN_ICON })
  if f.round then
    f.ringMask = f:CreateMaskTexture()
    f.ringMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    f.ringMask:SetAllPoints(f)
    f.disc:AddMaskTexture(f.ringMask)
    f.iconMask = f:CreateMaskTexture()
    f.iconMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    f.iconMask:SetAllPoints(f.inner)
    f.inner.icon:AddMaskTexture(f.iconMask)
  end
  fitFrame(f, opts.size or Theme.size.iconFrame.md)
  f.inner:SetAlpha(f.desaturated and 0.5 or 1)
  ns.Bind(f, paintFrame)

  function f:SetSpec(spec)
    self.inner.iconSpec = spec
    repaintSpec(self)
  end
  function f:SetTexture(texture)
    self:SetSpec({ kind = "texture", texture = texture or UNKNOWN_ICON })
  end
  function f:SetEdge(token)
    self.edge = token
    paintFrame(self)
  end
  function f:SetDesaturated(on)
    self.desaturated = on == true
    self.inner:SetAlpha(on and 0.5 or 1)
    repaintSpec(self)
  end
  function f:SetSelected(on)
    self.selected = on == true
    paintFrame(self)
  end
  function f:Resize(px)
    fitFrame(self, px)
  end
  function f:SetTip(tip, onClick, name)
    interactive(self, tip, onClick, name)
  end
  f:SetTip(opts.tip, opts.onClick, opts.name)
  return f
end

-- Tags ------------------------------------------------------------------------------------------------

-- One tag: a small tinted label with a thin edge. opts: key (locale key) or text (plain: name and tooltip),
-- rich (markup shown instead of text), color (Theme token or "#rrggbb", default textSecondary), icon (texture, 12 px), tip. The label always says the state in words,
-- the color only supports it. Methods: SetTag(opts) (reuse), Fit(maxWidth) -> width (a longer label is cut
-- with an ellipsis and names itself in a tooltip).
function K.Tag(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.border = W.Border(f, "textSecondary", 0.6)
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(TAG_ICON, TAG_ICON)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.label = W.Text(f, { role = "small", color = "textSecondary" })

  local function paint()
    local o = f.tag
    if not o then
      return
    end
    local token = o.color or "textSecondary"
    local text = Theme.readable(Theme.hex(token), Theme.hex("surface2"))
    W.SetColor(f.label, text)
    f.bg:SetColorTexture(Theme.color(token, 0.15))
    f.border.set(token, 0.6)
  end
  ns.Bind(f, paint)

  function f:SetTag(o)
    self.tag = o
    W.SetText(self.label, o.key, o.rich or o.text)
    self.icon:SetShown(o.icon ~= nil)
    if o.icon then
      self.icon:SetTexture(o.icon)
    end
    paint()
  end

  function f:Fit(maxWidth)
    local o = self.tag or {}
    local iconW = o.icon and (TAG_ICON + 4) or 0
    self.label:SetWidth(0)
    -- Inline textures (|T) get 2 px of slack each in case a measure misses their width.
    local inline = o.rich and select(2, o.rich:gsub("|T", "")) or 0
    local natural = TAG_PAD * 2 + iconW + math.ceil(self.label:GetStringWidth()) + 2 * inline
    local width = math.max(TAG_PAD * 2 + iconW + 10, math.min(natural, maxWidth or natural))
    local height = scaled(Theme.size.tag)
    self:SetSize(width, height)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("LEFT", TAG_PAD, 0)
    self.label:ClearAllPoints()
    self.label:SetPoint("LEFT", TAG_PAD + iconW, 0)
    self.label:SetWidth(width - TAG_PAD * 2 - iconW)
    local cut = width < natural
    local tip = o.tip or (cut and textOf(o)) or nil
    interactive(self, tip, nil, tip and textOf(o) or nil)
    return width
  end

  if opts then
    f:SetTag(opts)
  end
  return f
end

-- Tags in wrapping rows. row:SetTags(list of K.Tag opts); fgLayout(width) -> height (0 without tags).
function K.TagRow(parent, tags)
  local row = CreateFrame("Frame", nil, parent)
  local pool, shown = {}, 0
  function row:SetTags(list)
    list = list or {}
    for i, o in ipairs(list) do
      local tag = pool[i]
      if not tag then
        tag = K.Tag(row)
        pool[i] = tag
      end
      tag:SetTag(o)
      tag:Show()
    end
    for i = #list + 1, #pool do
      pool[i]:Hide()
    end
    shown = #list
  end
  function row:fgLayout(width)
    local gap, x, y, h = Theme.space.xs, 0, 0, scaled(Theme.size.tag)
    for i = 1, shown do
      local tag = pool[i]
      local w = tag:Fit(width)
      if x > 0 and x + w > width then
        x, y = 0, y + h + gap
      end
      tag:ClearAllPoints()
      tag:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
      x = x + w + gap
    end
    local height = shown > 0 and (y + h) or 0
    row:SetSize(width, height)
    return height
  end
  row.fgGridLayout = row.fgLayout
  if tags then
    row:SetTags(tags)
  end
  return row
end

-- Attribute line ------------------------------------------------------------------------------------------

local ATTR_ICON = 16

-- Label, then the value as text and/or a strip of small icons. opts: icon (texture or UI icon name, 16 px at
-- the left), label (text) or labelKey, value (text), valueColor (token), values (list of { icon, tip }),
-- tip, onClick. The value wraps under the label when the room beside it is below 110 px. Methods: Set(opts)
-- (reuse), fgLayout(width) -> height.
function K.AttrLine(parent, opts)
  local line = CreateFrame("Frame", nil, parent)
  line.label = W.Meta(line, { color = "textSecondary" })
  line.value = W.Text(line, { role = "ui", color = "text", wrap = true })
  local strip, glyph = {}, nil

  function line:Set(o)
    self.opts = o
    W.SetText(self.label, o.labelKey, o.label)
    W.SetText(self.value, nil, o.value or "")
    W.SetColor(self.value, o.valueColor or "text")
    local isTexture = o.icon ~= nil and (type(o.icon) == "number" or tostring(o.icon):find("[\\/]") ~= nil)
    if isTexture and not self.iconFrame then
      self.iconFrame = K.IconFrame(self, { size = ATTR_ICON })
    end
    if self.iconFrame then
      self.iconFrame:SetShown(isTexture)
    end
    if isTexture then
      self.iconFrame:SetTexture(o.icon)
    end
    if o.icon and not isTexture then
      glyph = glyph or W.Glyph(self, o.icon, 14, "textSecondary")
      glyph.iconName = o.icon
      glyph:Update()
    end
    if glyph then
      glyph:SetShown(o.icon ~= nil and not isTexture)
    end
    local values = o.values or {}
    for i, v in ipairs(values) do
      local icon = strip[i]
      if not icon then
        icon = K.IconFrame(self, { size = ATTR_ICON })
        strip[i] = icon
      end
      icon:SetTexture(v.icon)
      icon:SetTip(v.tip, nil, v.tip and (type(v.tip) == "table" and v.tip.title or v.tip) or nil)
      icon:Show()
    end
    for i = #values + 1, #strip do
      strip[i]:SetTip(nil)
      strip[i]:Hide()
    end
    self.stripCount = #values
    interactive(self, o.tip, o.onClick, o.tip and (type(o.tip) == "table" and o.tip.title or o.tip) or nil)
  end

  function line:fgLayout(width)
    local o = self.opts or {}
    local xs, sm = Theme.space.xs, Theme.space.sm
    local lineH = scaled(ATTR_ICON)
    local hasIcon = o.icon ~= nil
    local labelX = hasIcon and (ATTR_ICON + xs) or 0
    local mark = (self.iconFrame and self.iconFrame:IsShown()) and self.iconFrame or glyph
    if hasIcon and mark then
      mark:ClearAllPoints()
      mark:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -math.floor((lineH - ATTR_ICON) / 2))
    end
    self.label:SetWidth(0)
    local labelW = math.min(math.ceil(self.label:GetStringWidth()), math.max(1, width - labelX))
    self.label:ClearAllPoints()
    self.label:SetPoint("TOPLEFT", self, "TOPLEFT", labelX, -math.floor((lineH - self.label:GetHeight()) / 2))
    self.label:SetWidth(labelW)
    local x0, y0 = labelX + labelW + sm, 0
    local hasText = (o.value or "") ~= ""
    if self.stripCount + (hasText and 1 or 0) > 0 and width - x0 < 110 then
      x0, y0 = labelX, lineH + xs
    end
    local x, y, bottom = x0, y0, lineH
    for i = 1, self.stripCount do
      if x > x0 and x + ATTR_ICON > width then
        x, y = x0, y + ATTR_ICON + xs
      end
      strip[i]:ClearAllPoints()
      strip[i]:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
      x = x + ATTR_ICON + xs
      bottom = math.max(bottom, y + ATTR_ICON)
    end
    self.value:SetShown(hasText)
    if hasText then
      local vx, vy = x0, y0
      if self.stripCount > 0 then
        vx, vy = x0, bottom + xs
      end
      local h = W.FitLabel(self.value, math.max(20, width - vx))
      self.value:ClearAllPoints()
      self.value:SetPoint("TOPLEFT", self, "TOPLEFT", vx, -vy)
      bottom = math.max(bottom, vy + h)
    end
    self:SetSize(width, bottom)
    return bottom
  end
  line.fgGridLayout = line.fgLayout
  if opts then
    line:Set(opts)
  end
  return line
end

-- Stat row ---------------------------------------------------------------------------------------------------

-- One value against a baseline. opts: icon (texture), key or text (name), value, baseline (default 1), kind
-- "ratio" (default: x1.08 (+8%), the sign is the cue) or "count" (have / need with a check mark once met, red
-- below). Above the baseline the value is statUp, below statDown, equal text. Methods: Set(opts), fgLayout(width).
function K.StatRow(parent, opts)
  local row = CreateFrame("Frame", nil, parent)
  row.name = W.Text(row, { role = "ui", color = "text", wrap = true })
  row.value = W.Text(row, { role = "ui", color = "text", justify = "RIGHT" })
  row.check = W.CheckMark(row, 12, "statUp")

  function row:Set(o)
    self.opts = o
    W.SetText(self.name, o.key, o.text)
    local baseline = o.baseline or 1
    local value = o.value or baseline
    local token = value > baseline and "statUp" or value < baseline and "statDown" or "text"
    local text
    if o.kind == "count" then
      text = string.format("%d / %d", value, baseline)
      self.check:SetShown(value >= baseline)
      token = value >= baseline and "statUp" or "statDown"
    else
      self.check:Hide()
      text = string.format("x%.2f", value)
      if value ~= baseline then
        local pct = math.floor(math.abs(value / baseline - 1) * 100 + 0.5)
        text = string.format("%s (%s%d%%)", text, value > baseline and "+" or "-", pct)
      end
    end
    W.SetText(self.value, nil, text)
    W.SetColor(self.value, token)
    if o.icon then
      self.icon = self.icon or K.IconFrame(self, { size = Theme.size.iconFrame.sm })
      self.icon:SetTexture(o.icon)
      self.icon:Show()
    elseif self.icon then
      self.icon:Hide()
    end
  end

  function row:fgLayout(width)
    local sm = Theme.space.sm
    local minH = scaled(Theme.size.iconFrame.sm)
    local x = 0
    if self.icon and self.icon:IsShown() then
      self.icon:ClearAllPoints()
      self.icon:SetPoint("LEFT", self, "LEFT", 0, 0)
      x = Theme.size.iconFrame.sm + sm
    end
    self.value:SetWidth(0)
    local valueW = math.ceil(self.value:GetStringWidth())
    local checkW = self.check:IsShown() and (12 + Theme.space.xs) or 0
    self.value:ClearAllPoints()
    self.value:SetPoint("RIGHT", self, "RIGHT", 0, 0)
    self.value:SetWidth(valueW)
    self.check:ClearAllPoints()
    self.check:SetPoint("RIGHT", self.value, "LEFT", -Theme.space.xs, 0)
    local nameW = math.max(20, width - x - valueW - checkW - sm)
    local h = math.max(minH, W.FitLabel(self.name, nameW) + 6)
    self.name:ClearAllPoints()
    self.name:SetPoint("LEFT", self, "LEFT", x, 0)
    self:SetSize(width, h)
    return h
  end
  row.fgGridLayout = row.fgLayout
  if opts then
    row:Set(opts)
  end
  return row
end

-- Key / value grid ---------------------------------------------------------------------------------------------

-- Two columns of facts. opts: rows = list of { key (locale key), value (text), color (token), place (adds a
-- map button), tip, onClick, tags (K.Tag opts) }, keyWidth (default the widest key, at most 40 percent of the
-- width). Below 280 px the key stands above the value. Methods: SetRows(list), Row(i) (the pooled row, with .map
-- for a row with a place), fgLayout(width) -> height.
function K.KeyValue(parent, opts)
  opts = opts or {}
  local kv = CreateFrame("Frame", nil, parent)
  local pool, shown = {}, 0

  local function makeRow()
    local r = CreateFrame("Frame", nil, kv)
    r.key = W.Meta(r, { color = "textSecondary", wrap = true })
    r.value = W.Text(r, { role = "ui", color = "text", wrap = true })
    return r
  end

  function kv:SetRows(list)
    list = list or {}
    for i, e in ipairs(list) do
      local r = pool[i]
      if not r then
        r = makeRow()
        pool[i] = r
      end
      r.entry = e
      W.SetText(r.key, e.key)
      W.SetText(r.value, nil, e.value or "")
      W.SetColor(r.value, e.color or "text")
      if e.place and not r.map then
        r.map = W.MapActionButtons(r, {})
      end
      if r.map then
        r.map:SetPlace(e.place)
        r.map:SetShown(e.place ~= nil)
      end
      if e.tags and not r.tags then
        r.tags = K.TagRow(r)
      end
      if r.tags then
        r.tags:SetTags(e.tags)
        r.tags:SetShown(e.tags ~= nil)
      end
      interactive(r, e.tip, e.onClick, e.tip and (type(e.tip) == "table" and e.tip.title or e.tip) or nil)
      r:Show()
    end
    for i = #list + 1, #pool do
      interactive(pool[i], nil)
      pool[i]:Hide()
    end
    shown = #list
  end

  -- The pooled row i (its .map is the W.MapActionButtons bar of a row with a place), nil past the rows in use.
  function kv:Row(i)
    return i <= shown and pool[i] or nil
  end

  function kv:fgLayout(width)
    local sm, xs = Theme.space.sm, Theme.space.xs
    local stacked = width < 280
    local keyW = width
    if not stacked then
      local widest = 0
      for i = 1, shown do
        pool[i].key:SetWidth(0)
        widest = math.max(widest, math.ceil(pool[i].key:GetStringWidth()))
      end
      keyW = math.max(20, math.min(opts.keyWidth or widest, math.floor(width * 0.4)))
    end
    local y = 0
    for i = 1, shown do
      local r, e = pool[i], pool[i].entry
      local mapW = (r.map and e.place) and (r.map:GetWidth() + sm) or 0
      local valueX = stacked and 0 or (keyW + sm)
      local keyH = W.FitLabel(r.key, keyW)
      local valueW = math.max(20, width - valueX - mapW)
      local hasValue = (e.value or "") ~= ""
      local valueH = hasValue and W.FitLabel(r.value, valueW) or 0
      r.value:SetShown(hasValue)
      local keyY = 0
      local valueY = stacked and (keyH + 2) or 0
      r.key:ClearAllPoints()
      r.key:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -keyY)
      r.value:ClearAllPoints()
      r.value:SetPoint("TOPLEFT", r, "TOPLEFT", valueX, -valueY)
      local h = math.max(keyH, stacked and (valueY + valueH) or valueH)
      if r.map and e.place then
        r.map:ClearAllPoints()
        r.map:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
        h = math.max(h, r.map:GetHeight())
      end
      if r.tags and e.tags then
        local tagY = hasValue and (valueY + valueH + xs) or valueY
        r.tags:ClearAllPoints()
        r.tags:SetPoint("TOPLEFT", r, "TOPLEFT", valueX, -tagY)
        h = math.max(h, tagY + r.tags:fgLayout(math.max(20, width - valueX)))
      end
      h = math.max(h, scaled(16))
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", kv, "TOPLEFT", 0, -y)
      r:SetSize(width, h)
      y = y + h + xs + 2
    end
    local total = shown > 0 and (y - xs - 2) or 0
    kv:SetSize(width, total)
    return total
  end
  kv.fgGridLayout = kv.fgLayout
  if opts.rows then
    kv:SetRows(opts.rows)
  end
  return kv
end

-- Section card ------------------------------------------------------------------------------------------------

local HEAD_ICON = 14

-- A W.Panel with a header band (gold capitals, optional icon, count, muted text and actions at the right), a rule
-- below it and a body the caller lays out. opts: key or text (title), icon (UI icon name or texture), count,
-- caps (default true), actions (widget), sub (text), body(width, bodyFrame) -> height, selected.
-- Methods besides the panel's: SetCount(n), SetActions(widget), SetSub(text), SetBody(fn), Relayout(),
-- fgLayout(width, minHeight) -> height (minHeight lets a card row align the bottoms).
function K.SectionCard(parent, opts)
  opts = opts or {}
  local card = W.Panel(parent, { selected = opts.selected })
  card.fgTitleKey, card.fgTitleText = opts.key, opts.text
  card.fgCaps = opts.caps ~= false
  card.fgBody = opts.body

  local head = CreateFrame("Frame", nil, card)
  head:EnableMouse(true)
  head.fgFlushTop = true -- the band starts at the card's top edge on purpose (see tests/pagematrix.lua)
  card.head = head
  card.divider = card:CreateTexture(nil, "ARTWORK")
  card.divider:SetHeight(1)
  ns.Bind(card, function()
    card.divider:SetColorTexture(Theme.fillColor("line"))
  end)
  card.title = W.Text(card, { role = "small", family = "heading", color = "heading" })
  card.sub = W.Meta(card, { color = "textMuted", justify = "RIGHT" })
  card.sub:Hide()
  card.body = CreateFrame("Frame", nil, card)
  W.TipWhenCut(head, card.title)

  local function paintTitle()
    local text = card.fgTitleKey and L[card.fgTitleKey] or card.fgTitleText or ""
    local shown = card.fgCaps and K.Caps(text) or text
    if card.fgCount then
      shown = string.format("%s (%d)", shown, card.fgCount)
    end
    card.title:SetText(shown)
  end
  ns.Bind(card, paintTitle)

  if opts.icon then
    local isTexture = type(opts.icon) == "number" or tostring(opts.icon):find("[\\/]") ~= nil
    if isTexture then
      card.icon = card:CreateTexture(nil, "ARTWORK")
      card.icon:SetSize(HEAD_ICON, HEAD_ICON)
      card.icon:SetTexture(opts.icon)
      card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
      card.icon = W.Glyph(card, opts.icon, HEAD_ICON, "heading")
    end
  end

  local function anchorHead()
    local xs = Theme.space.xs
    local right = card.actions or (card.sub:IsShown() and card.sub) or nil
    if card.actions then
      card.actions:ClearAllPoints()
      card.actions:SetPoint("RIGHT", head, "RIGHT", 0, 0)
    end
    card.sub:ClearAllPoints()
    if card.actions and card.sub:IsShown() then
      card.sub:SetPoint("RIGHT", card.actions, "LEFT", -Theme.space.sm, 0)
      right = card.sub
    elseif card.sub:IsShown() then
      card.sub:SetPoint("RIGHT", head, "RIGHT", 0, 0)
    end
    card.title:ClearAllPoints()
    if card.icon then
      card.icon:ClearAllPoints()
      card.icon:SetPoint("LEFT", head, "LEFT", 0, 0)
      card.title:SetPoint("LEFT", card.icon, "RIGHT", xs + 2, 0)
    else
      card.title:SetPoint("LEFT", head, "LEFT", 0, 0)
    end
    if right then
      card.title:SetPoint("RIGHT", right, "LEFT", -Theme.space.sm, 0)
    else
      card.title:SetPoint("RIGHT", head, "RIGHT", 0, 0)
    end
  end

  function card:SetCount(n)
    self.fgCount = n
    paintTitle()
  end
  function card:SetActions(widget)
    self.actions = widget
    anchorHead()
  end
  function card:SetSub(text)
    self.sub:SetText(text or "")
    self.sub:SetShown((text or "") ~= "")
    anchorHead()
  end
  function card:SetBody(fn)
    self.fgBody = fn
    self:Relayout()
  end

  function card:fgLayout(width, minHeight)
    self.fgWidth = width
    local pad = Theme.space.inset
    self.pad = pad
    local headH = scaled(Theme.size.sectionHeader)
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", self, "TOPLEFT", pad, 0)
    head:SetPoint("TOPRIGHT", self, "TOPRIGHT", -pad, 0)
    head:SetHeight(headH)
    self.divider:ClearAllPoints()
    self.divider:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -headH)
    self.divider:SetPoint("TOPRIGHT", self, "TOPRIGHT", -pad, -headH)
    anchorHead()
    local bodyTop = headH + 1 + Theme.space.md
    local inner = math.max(1, width - 2 * pad)
    self.body:ClearAllPoints()
    self.body:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -bodyTop)
    self.body:SetWidth(inner)
    local bodyH = self.fgBody and self.fgBody(inner, self.body) or 0
    self.body:SetHeight(math.max(1, bodyH))
    local total = math.max(bodyTop + bodyH + pad, minHeight or 0)
    self:SetSize(width, total)
    return total
  end
  card.fgGridLayout = card.fgLayout

  function card:Relayout()
    if self.fgWidth then
      self:fgLayout(self.fgWidth)
    end
  end

  anchorHead()
  if opts.actions then
    card:SetActions(opts.actions)
  end
  if opts.sub then
    card:SetSub(opts.sub)
  end
  if opts.count then
    card.fgCount = opts.count
    paintTitle()
  end
  return card
end

-- Card row ---------------------------------------------------------------------------------------------------

-- Section cards side by side with equal heights, one column below 2 * minWidth + gap. opts: cards, minWidth
-- (default 240), gap (default the md space). row:SetCards(list) takes over the cards (reparented).
-- fgLayout(width) -> height; hidden cards are skipped.
function K.CardRow(parent, opts)
  opts = opts or {}
  local row = CreateFrame("Frame", nil, parent)
  local cards = {}
  function row:SetCards(list)
    cards = {}
    for i, card in ipairs(list or {}) do
      card:SetParent(row)
      cards[i] = card
    end
  end
  function row:fgLayout(width)
    local gap = opts.gap or Theme.space.md
    local live = {}
    for _, card in ipairs(cards) do
      if card:IsShown() then
        live[#live + 1] = card
      end
    end
    local cols, colW = ns.CardFlow.Columns(width, opts.minWidth or 240, gap)
    local y = 0
    for first = 1, #live, cols do
      local last = math.min(first + cols - 1, #live)
      local tallest = 0
      for i = first, last do
        tallest = math.max(tallest, live[i]:fgLayout(colW))
      end
      for i = first, last do
        local card = live[i]
        card:SetHeight(tallest)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", row, "TOPLEFT", (i - first) * (colW + gap), -y)
      end
      y = y + tallest + gap
    end
    local total = #live > 0 and (y - gap) or 0
    row:SetSize(width, total)
    return total
  end
  row.fgGridLayout = row.fgLayout
  row:SetCards(opts.cards)
  return row
end

-- Hero ------------------------------------------------------------------------------------------------------

local HERO_NARROW = 360

-- Header of a detail view. opts: portrait (K.IconFrame opts, round by default), title (text) or titleKey,
-- subtitle, attrs (list of K.AttrLine opts), tags (list of K.Tag opts), actions (widget at the top right),
-- banner (texture behind the block, under a dark strip). The portrait is 64 px beside the text and 48 px above
-- it below 360 px. Methods: SetTitle(text), SetSubtitle(text), SetPortrait(opts or nil), SetAttrs(list),
-- SetTags(list), SetBanner(texture or nil), SetActions(widget), fgLayout(width) -> height.
function K.Hero(parent, opts)
  opts = opts or {}
  local hero = CreateFrame("Frame", nil, parent)
  hero.banner = hero:CreateTexture(nil, "BACKGROUND")
  hero.banner:SetAllPoints()
  hero.banner:Hide()
  hero.strip = hero:CreateTexture(nil, "BACKGROUND", nil, 1)
  hero.strip:SetAllPoints()
  hero.strip:Hide()
  ns.Bind(hero, function()
    hero.strip:SetColorTexture(Theme.scrim(Theme.highContrast() and 0.92 or 0.78))
  end)
  hero.title = W.Text(hero, { role = "h2", family = "heading", color = "heading", wrap = true })
  hero.subtitle = W.Text(hero, { role = "ui", color = "textSecondary", wrap = true })
  hero.tags = K.TagRow(hero)
  local lines = {}
  local attrCount = 0

  function hero:SetTitle(text, key)
    W.SetText(self.title, key, text or "")
  end
  function hero:SetSubtitle(text)
    W.SetText(self.subtitle, nil, text or "")
  end
  function hero:SetPortrait(o)
    if not o then
      if self.portrait then
        self.portrait:Hide()
      end
      return
    end
    if not self.portrait then
      local po = {}
      for k, v in pairs(o) do
        po[k] = v
      end
      po.shape = po.shape or "round"
      po.size = Theme.size.iconFrame.hero
      self.portrait = K.IconFrame(self, po)
    else
      if o.spec then
        self.portrait:SetSpec(o.spec)
      else
        self.portrait:SetTexture(o.texture)
      end
      self.portrait:SetEdge(o.edge)
      self.portrait:SetTip(o.tip, o.onClick, o.name)
    end
    self.portrait:Show()
  end
  function hero:SetAttrs(list)
    list = list or {}
    for i, o in ipairs(list) do
      lines[i] = lines[i] or K.AttrLine(self)
      lines[i]:Set(o)
      lines[i]:Show()
    end
    for i = #list + 1, #lines do
      lines[i]:Hide()
    end
    attrCount = #list
  end
  function hero:SetTags(list)
    self.tags:SetTags(list)
  end
  function hero:SetBanner(texture)
    self.fgBanner = texture
    self.banner:SetShown(texture ~= nil)
    self.strip:SetShown(texture ~= nil)
    if texture then
      self.banner:SetTexture(texture)
    end
  end
  function hero:SetActions(widget)
    self.actions = widget
  end

  function hero:fgLayout(width)
    local xs, sm, md = Theme.space.xs, Theme.space.sm, Theme.space.md
    local pad = self.fgBanner and md or 0
    local inner = math.max(1, width - 2 * pad)
    local narrow = inner < HERO_NARROW
    local portrait = self.portrait and self.portrait:IsShown() and self.portrait or nil
    local px = narrow and 48 or Theme.size.iconFrame.hero
    local textX, y = 0, 0
    if portrait then
      portrait:Resize(px)
      portrait:ClearAllPoints()
      portrait:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -pad)
      if narrow then
        y = px + sm
      else
        textX = px + md
      end
    end
    local actionsW = 0
    if self.actions and self.actions:IsShown() then
      actionsW = self.actions:GetWidth() + sm
      self.actions:ClearAllPoints()
      self.actions:SetPoint("TOPRIGHT", self, "TOPRIGHT", -pad, -pad)
    end
    local textW = math.max(20, inner - textX)
    local function place(item, h, gapBefore)
      y = y + gapBefore
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", self, "TOPLEFT", pad + textX, -(pad + y))
      y = y + h
    end
    local h = W.FitLabel(self.title, math.max(20, textW - actionsW))
    place(self.title, h, 0)
    local hasSub = (self.subtitle.fgText or "") ~= "" or self.subtitle.fgKey ~= nil
    self.subtitle:SetShown(hasSub)
    if hasSub then
      place(self.subtitle, W.FitLabel(self.subtitle, textW), xs)
    end
    for i = 1, attrCount do
      place(lines[i], lines[i]:fgLayout(textW), i == 1 and sm or xs)
    end
    local tagH = self.tags:fgLayout(textW)
    self.tags:SetShown(tagH > 0)
    if tagH > 0 then
      place(self.tags, tagH, sm)
    end
    if portrait and not narrow then
      y = math.max(y, px)
    end
    local total = y + 2 * pad
    self:SetSize(width, total)
    return total
  end
  hero.fgGridLayout = hero.fgLayout

  hero:SetTitle(opts.title, opts.titleKey)
  hero:SetSubtitle(opts.subtitle)
  hero:SetPortrait(opts.portrait)
  hero:SetAttrs(opts.attrs)
  hero:SetTags(opts.tags)
  hero:SetBanner(opts.banner)
  if opts.actions then
    hero:SetActions(opts.actions)
  end
  return hero
end
