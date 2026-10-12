-- Small widgets the macro tabs share: buttons with an icon, a wrapping button row, toggle chips,
-- the 255 counter with its traffic light, a finding list, an icon box, a labelled field and a
-- scrolling pane. Built on W.* and ns.PageKit, nothing here knows about macros except the
-- counter thresholds.
local _, ns = ...
local W, L, Theme, K, C = ns.W, ns.L, ns.Theme, ns.PageKit, ns.MacroCore

local Kit = {}
local QUESTION_ICON = 134400 -- the stand-in until an icon is set
ns.MacroKit = Kit

-- Names of the icons of the shared set (ns.UI_ICONS) per action of the macro page.
Kit.ICON = {
  save = "save",
  apply = "play",
  duplicate = "copy",
  delete = "trash",
  export = "export",
  import = "import",
  new = "plus",
  refresh = "refresh",
  compact = "minus",
  text = "copy",
  spell = "search",
  item = "folder",
  merge = "plus",
  sequence = "refresh",
  edit = "pencil",
  web = "search",
}

local function scaled(base)
  return Theme.lineHeight(base)
end
Kit.scaled = scaled

-- Buttons ------------------------------------------------------------------------------------

-- A W.Action with an icon: o.label (short locale key, hidden by the setting "buttonLabels" and by
-- narrow places) or o.key|text (fixed text), icon (name of ns.UI_ICONS), variant, height, tooltip,
-- tooltipText, onClick. A fixed-text button has the exact width o.width (default 100).
function Kit.ActionButton(parent, o)
  local fixed = o.key ~= nil or o.text ~= nil
  return W.Action(parent, {
    key = o.key,
    text = o.text,
    label = o.label,
    icon = o.icon,
    variant = o.variant,
    width = fixed and (o.width or 100) or nil,
    height = o.height or scaled(28),
    tooltip = o.tooltip,
    tooltipText = o.tooltipText,
    onClick = o.onClick,
  })
end

-- Wrapping row of buttons, a FlowLayout.ButtonRow at the common action height (28, grows with the
-- font scale). defs = list of { id, key|text, label + icon, variant, width, tooltip, tooltipText,
-- onClick, shown, enabled }. opts: gap (8), rowGap (6), height. Returns the row: row:GetButton(id),
-- row:SetItemShown(id, v), row:SetItemEnabled(id, v), row:Refresh(), row:fgGridLayout(width).
function Kit.ActionRow(parent, defs, opts)
  opts = opts or {}
  return ns.FlowLayout.ButtonRow(parent, defs, {
    gap = opts.gap,
    rowGap = opts.rowGap,
    height = opts.height or scaled(28),
  })
end

-- Chips ----------------------------------------------------------------------------------------

-- A toggle button with a text (W.Action). o: label (literal), onClick(chip), tooltip (literal).
-- chip:SetSelected(bool), chip.selected. Selected = filled, accent text and a 2 px ring (never
-- color alone). chip:Measure() gives the width and height the chip wants.
function Kit.Chip(parent, o)
  local b
  b = W.Action(parent, {
    text = o.label,
    size = 24,
    manual = true,
    wrap = "macro-chip",
    onClick = function()
      o.onClick(b)
    end,
  })
  function b.fgName()
    return o.label
  end
  local setSelected = b.SetSelected
  function b:SetSelected(on)
    self.selected = on and true or false
    setSelected(self, on)
  end
  if o.tooltip then
    b:HookScript("OnEnter", function()
      ns.ShowTooltip(b, o.tooltip)
    end)
    b:HookScript("OnLeave", ns.HideTooltip)
  end
  function b:Measure()
    return self:FullWidth(), scaled(24)
  end
  return b
end

-- Groups of chips with a caption each, wrapping. groups = list of { key (caption), label (literal
-- caption), chips = { { value, label, tooltip } } }; get(value) -> bool, toggle(value). Returns a frame
-- with fgGridLayout(width), :Refresh() and .chips[value].
function Kit.ChipGroups(parent, o)
  local f = CreateFrame("Frame", nil, parent)
  local blocks, chips = {}, {}
  for _, group in ipairs(o.groups) do
    local block =
      { caption = W.Text(f, { key = group.key, text = group.label, role = "micro", color = "textMuted" }), chips = {} }
    for _, def in ipairs(group.chips) do
      local chip = Kit.Chip(f, {
        label = def.label,
        tooltip = def.tooltip,
        onClick = function()
          o.toggle(def.value)
          f.Refresh()
        end,
      })
      chip.value = def.value
      block.chips[#block.chips + 1] = chip
      chips[def.value] = chip
    end
    blocks[#blocks + 1] = block
  end
  function f.Refresh()
    for _, chip in pairs(chips) do
      chip:SetSelected(o.get(chip.value))
    end
  end
  function f:fgGridLayout(width)
    local y = 0
    for _, block in ipairs(blocks) do
      block.caption:ClearAllPoints()
      block.caption:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      y = y + scaled(14) + 2
      local x, rowH = 0, 0
      for _, chip in ipairs(block.chips) do
        local w, h = chip:Measure()
        w = math.min(w, width)
        if x > 0 and x + w > width then
          x, y, rowH = 0, y + rowH + 4, 0
        end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
        chip:SetSize(w, h)
        x = x + w + 4
        rowH = math.max(rowH, h)
      end
      y = y + rowH + 8
    end
    f:SetHeight(math.max(1, y))
    return y
  end
  f.chips = chips
  f.Refresh()
  return f
end

-- Counter ----------------------------------------------------------------------------------------

-- The 255 counter: a line of text and a bar with a traffic light (green below 230, yellow from 230,
-- red above 255). counter:Set(chars, bytes). The text carries the state too ("close to the limit",
-- "too many"), the colors are a second signal.
function Kit.Counter(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(scaled(34))
  f.text = W.Text(f, { role = "ui", color = "success" })
  f.text:SetPoint("TOPLEFT")
  f.text:SetPoint("RIGHT")
  f.bar = CreateFrame("Frame", nil, f)
  f.bar:SetHeight(6)
  f.bar:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -4)
  f.bar:SetPoint("RIGHT")
  f.back = f.bar:CreateTexture(nil, "BACKGROUND")
  f.back:SetAllPoints()
  ns.Bind(f.back, function(t)
    t:SetColorTexture(Theme.color("surface2"))
  end)
  f.fill = f.bar:CreateTexture(nil, "ARTWORK")
  f.fill:SetPoint("TOPLEFT")
  f.fill:SetPoint("BOTTOMLEFT")
  local last
  local function paint()
    if not last then
      return
    end
    local frac = math.min(1, last.chars / C.MAX_BODY)
    f.fill:SetWidth(math.max(1, (f.bar:GetWidth() or 0) * frac))
    f.fill:SetColorTexture(Theme.color(last.level))
  end
  f.bar:SetScript("OnSizeChanged", paint)
  function f:Set(chars, bytes)
    local level = C.level(chars)
    if level == "success" and bytes > C.MAX_BODY then
      level = "warning"
    end
    local left = C.MAX_BODY - chars
    local text = left >= 0 and string.format(L["macros.editor.counter"], chars, C.MAX_BODY, left)
      or string.format(L["macros.editor.counterOver"], chars, C.MAX_BODY, -left)
    if bytes ~= chars then
      text = text .. string.format(L["macros.editor.counterBytes"], bytes)
    end
    if level == "warning" and chars <= C.MAX_BODY then
      text = text .. "  -  " .. L["macros.counter.near"]
    end
    f.text:SetText(text)
    W.SetColor(f.text, level)
    last = { chars = chars, level = level }
    f.level = level
    paint()
  end
  ns.On("FG_UI_REFRESHED", paint)
  return f
end

-- Finding list -----------------------------------------------------------------------------------

local LEVEL_KEY = { error = "macros.level.error", warning = "macros.level.warning", info = "macros.level.info" }

-- Text of one finding: severity word, line and message in the addon language.
function Kit.findingTitle(f)
  local where = f.line > 0 and string.format(L["macros.find.line"], f.line) or L["macros.find.whole"]
  return L[LEVEL_KEY[f.severity]] .. "  -  " .. where
end

-- A list of findings (ns.MacroLines.validate result) with a message of two lines per row.
-- o.onPick(finding): click on a row (jump to the line), o.rows: visible rows (default 4).
function Kit.FindingList(parent, o)
  local Lines = ns.MacroLines
  local list = K.NewList(parent, {
    rowHeight = 52,
    onClick = function(item)
      if item.finding and o.onPick then
        o.onPick(item.finding)
      end
    end,
    bind = function(item)
      if item.none then
        return { title = L["macros.problems.none"], sub = "" }
      end
      local text = Lines.text(item.finding, L)
      return {
        title = Kit.findingTitle(item.finding),
        sub = text,
        wrapSub = true,
        tooltip = text,
        right = item.finding.code,
      }
    end,
  })
  list.rows = o.rows or 4
  function list:SetFindings(findings)
    local data = {}
    for i, f in ipairs(findings) do
      data[i] = { finding = f }
    end
    if #data == 0 then
      data[1] = { none = true }
    end
    self.count = #findings
    self:SetData(data)
    return #data
  end
  return list
end

-- Tabs -------------------------------------------------------------------------------------------

-- A tab strip like W.Tabs that wraps to a second line when the width runs out (four tabs do not fit
-- into 320 px). opts: tabs = { { id, key } }, onSelect(id). tabs:Select(id), tabs.selected,
-- tabs.buttons[id], tabs:fgGridLayout(width) for a page stack.
function Kit.TabBar(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f.buttons = {}
  local order = {}
  local lastWidth
  local line = f:CreateTexture(nil, "BACKGROUND")
  line:SetPoint("BOTTOMLEFT")
  line:SetPoint("BOTTOMRIGHT")
  line:SetHeight(1)
  ns.Bind(line, function(t)
    t:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)
  for _, tab in ipairs(opts.tabs) do
    local b = CreateFrame("Button", nil, f)
    b.label = W.Text(b, { key = tab.key, role = "ui", color = "textSecondary", justify = "CENTER" })
    b.label:SetPoint("CENTER")
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetPoint("BOTTOMRIGHT")
    b.bar:SetHeight(2)
    ns.Bind(b, function()
      b.bar:SetColorTexture(Theme.color("accent2"))
    end)
    b:SetScript(
      "OnClick",
      ns.Wrap("macro-tab", function()
        f:Select(tab.id)
      end)
    )
    ns.Focus.register(b, function(self)
      self:Click()
    end)
    b.bar:Hide()
    f.buttons[tab.id] = b
    order[#order + 1] = tab.id
  end
  function f:fgGridLayout(width)
    lastWidth = width
    local rowH = scaled(28)
    local x, y = 0, 0
    for _, id in ipairs(order) do
      local b = f.buttons[id]
      local w = math.min(width, math.ceil(b.label:GetStringWidth()) + 24)
      if x > 0 and x + w > width then
        x, y = 0, y + rowH + 2
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
      b:SetSize(w, rowH)
      x = x + w + 4
    end
    f:SetHeight(y + rowH)
    return y + rowH
  end
  function f:Select(id)
    f.selected = id
    for tid, b in pairs(f.buttons) do
      local on = tid == id
      b.bar:SetShown(on)
      W.SetColor(b.label, on and "accent" or "textSecondary")
    end
    if opts.onSelect then
      opts.onSelect(id)
    end
  end
  ns.On("FG_UI_REFRESHED", function()
    if lastWidth then
      f:fgGridLayout(lastWidth)
    end
  end)
  return f
end

-- Fields -----------------------------------------------------------------------------------------

-- A caption above an edit box. o: key (caption), onChange(text), onEnter(text), maxLetters. Returns the
-- frame (height 46) with f.edit (the EditBox), f:SetValue(text), f:GetValue().
function Kit.Field(parent, o)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(scaled(46))
  f.label = W.Text(f, { key = o.key, text = o.text, role = "micro", color = "textMuted" })
  f.label:SetPoint("TOPLEFT")
  f.label:SetPoint("RIGHT")
  f.box = W.EditBox(f, { onChange = o.onChange, onEnter = o.onEnter, placeholder = o.placeholder, clear = o.clear })
  f.box:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -2)
  f.box:SetPoint("RIGHT")
  f.edit = f.box.edit
  if o.maxLetters then
    f.edit:SetMaxLetters(o.maxLetters)
  end
  function f:SetValue(text)
    f.edit:SetText(text or "")
  end
  function f:GetValue()
    return f.edit:GetText()
  end
  return f
end

-- A button that shows an icon (file id or path), W.Action with a raw texture. :SetIcon(icon).
-- Keyboard reachable.
function Kit.IconBox(parent, size, o)
  local b = W.Action(parent, {
    texture = QUESTION_ICON,
    size = size,
    boxed = true,
    tooltip = o.tooltip,
    tooltipText = o.tooltipText,
    onClick = o.onClick,
    wrap = "macro-iconbox",
  })
  b.fgOnFocus = function()
    if o.tooltip then
      ns.ShowTooltip(b, L[o.tooltip], o.tooltipText and L[o.tooltipText])
    end
  end
  b.fgOnBlur = ns.HideTooltip
  return b
end

-- Panes ------------------------------------------------------------------------------------------

-- A scrolling stack inside a pane (the right half of a two-pane split). Returns the ScrollArea and the
-- W.Stack; the stack lays itself out again when the pane changes size.
function Kit.ScrollPane(pane, pad)
  local area = W.ScrollArea(pane)
  area:SetFrameLevel(pane:GetFrameLevel() + 1)
  area:SetAllPoints()
  local stack = W.Stack(area, pad or 6)
  area:HookScript("OnSizeChanged", function()
    ns.Debounce(stack, 0.05, function()
      stack:Layout()
    end)
  end)
  return area, stack
end

-- Toggle button with an icon that reads as pressed (ring, accent icon) when on; the name is a
-- tooltip. o: icon (name of ns.UI_ICONS), tooltip (locale key), get(), set(on).
function Kit.GlyphToggle(parent, o)
  local b
  local function tip()
    ns.ShowTooltip(
      b,
      L[o.tooltip],
      o.tooltipText and L[o.tooltipText] or (o.get() and L["macros.toggle.on"] or L["macros.toggle.off"])
    )
  end
  b = W.Action(parent, { icon = o.icon, size = 26, boxed = true, manual = true })
  b.fgNameKey = o.tooltip
  function b.Refresh()
    b:SetSelected(o.get())
  end
  b:SetScript(
    "OnClick",
    ns.Wrap("macro-toggle", function()
      o.set(not o.get())
      b.Refresh()
    end)
  )
  b:HookScript("OnEnter", tip)
  b:HookScript("OnLeave", ns.HideTooltip)
  b.fgOnFocus, b.fgOnBlur = tip, ns.HideTooltip
  b.Refresh()
  return b
end

-- Simple list ------------------------------------------------------------------------------------

-- A one-line list (virtual) with an optional icon and a state text. o: rowHeight (22), click(item),
-- bind(row, item) fills row.icon / row.label / row.state, isSelected(item), onEnter(row, item). Items
-- with `empty` (a locale key) show as a muted line and do not react.
function Kit.SimpleList(parent, o)
  local rowH = o.rowHeight or 22
  local function create(p)
    local row = CreateFrame("Button", nil, p)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    ns.Bind(row, function()
      hl:SetColorTexture(1, 1, 1, 0.08)
      row.sel:SetColorTexture(Theme.color("action", 0.5))
    end)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(rowH - 4, rowH - 4)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.label = W.Text(row, { role = "ui" })
    row.state = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
    row.state:SetPoint("RIGHT", -4, 0)
    local function activate()
      if row.item and not row.item.empty and o.click then
        o.click(row.item)
      end
    end
    row:SetScript("OnClick", ns.Wrap("macro-row", activate))
    if o.onEnter then
      row:SetScript("OnEnter", function()
        if row.item and not row.item.empty then
          o.onEnter(row, row.item)
        end
      end)
      row:SetScript("OnLeave", ns.HideTooltip)
    end
    ns.Focus.register(row, activate)
    return row
  end
  local function bindRow(row, item)
    row.item = item
    row.state:SetText("")
    row.label:ClearAllPoints()
    if item.empty then
      row.icon:Hide()
      row.label:SetPoint("LEFT", 8, 0)
      row.label:SetPoint("RIGHT", -4, 0)
      W.SetText(row.label, item.empty)
      W.SetColor(row.label, "textMuted")
      row.sel:Hide()
      return
    end
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
    W.SetColor(row.label, "text")
    o.bind(row, item)
    row.sel:SetShown(o.isSelected ~= nil and o.isSelected(item) or false)
  end
  return W.ScrollList(parent, { rowHeight = rowH, createRow = create, bindRow = bindRow })
end
