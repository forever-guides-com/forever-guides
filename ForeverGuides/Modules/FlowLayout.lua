-- Responsive layout helpers for pages: a wrapping row of buttons and a two-pane split.
-- Both take their size from the width they are handed (a page Stack calls fgGridLayout,
-- OnSizeChanged calls it for frames anchored on both sides), and neither rebuilds frames on a
-- resize: buttons are created once and only re-anchored.
local _, ns = ...
local W, Theme, U = ns.W, ns.Theme, ns.U

local FL = {}
ns.FlowLayout = FL

local BUTTON_MIN = 60

local function scaled(base)
  return Theme.lineHeight(base)
end

local function flag(value, default)
  if type(value) == "function" then
    return value() and true or false
  end
  if value == nil then
    return default
  end
  return value and true or false
end

-- Button row ---------------------------------------------------------------------------

-- A row of buttons that keep their content width and wrap to the next line when the width
-- runs out. defs = list of { id, key (locale key) or text (literal), onClick, width (minimum
-- width, default 60), variant, tooltip + tooltipText (locale keys), icon (name of ns.UI_ICONS),
-- label (short locale key shown next to the icon unless the setting "buttonLabels" is off or the
-- row is too narrow, then the icon stands alone and the tooltip names it), shortcut, shown, enabled (boolean or
-- function returning one), fgId }. opts: gap (8), rowGap (6), height (28, grows with the font
-- scale). A button wider than the row shrinks to the row, its label is cut with an ellipsis.
-- Returns the row frame:
--   row:SetWidthAvailable(w)  places the buttons for width w, returns the content height
--   row:GetContentHeight()    height of the placed lines (0 when no button is shown)
--   row:GetRowCount()         number of lines
--   row:GetButton(id)         the W.Action of an item
--   row:SetItemShown(id, v), row:SetItemEnabled(id, v), row:SetItemText(id, key, literal)
--   row:Refresh()             re-evaluates function-valued shown/enabled, then places again
--   row:fgGridLayout(w)       the same as SetWidthAvailable, so a page Stack can hold the row
-- The row also places itself when its own width changes (OnSizeChanged).
function FL.ButtonRow(parent, defs, opts)
  opts = opts or {}
  local gap, rowGap = opts.gap or 8, opts.rowGap or 6
  local height = opts.height or scaled(28)
  local row = CreateFrame("Frame", nil, parent)
  local items, byId = {}, {}
  local lastWidth, lastSignature
  local contentHeight, lines = 0, 0

  for index, def in ipairs(defs) do
    local d = {}
    for k, v in pairs(def) do
      d[k] = v
    end
    local item = { id = d.id or d.fgId or d.key or index, def = d, minWidth = d.width or BUTTON_MIN }
    item.button = W.Action(row, {
      key = d.key,
      text = d.text,
      label = d.label,
      icon = d.icon,
      variant = d.variant,
      width = item.minWidth,
      height = height,
      tooltip = d.tooltip,
      tooltipText = d.tooltipText,
      shortcut = d.shortcut,
      onClick = d.onClick,
      wrap = "button",
    })
    item.button.fgManaged = true -- the row decides the width and whether the short label fits
    item.button.fgId = d.fgId or d.id
    item.shown, item.enabled = flag(d.shown, true), flag(d.enabled, true)
    item.button:SetShown(item.shown)
    item.button:SetEnabled(item.enabled)
    items[#items + 1] = item
    byId[item.id] = item
  end

  -- Width of a button for a row of `width` pixels: an icon with a short label shrinks to the icon
  -- when the label is switched off or does not fit; fixed text keeps its width.
  local function natural(item, width)
    local button = item.button
    if button.fgHasLabel then
      local w = button:Fit(width)
      return button.fgLabelOn and item.def.width and math.max(item.def.width, w) or w
    end
    if button.label then
      return math.max(item.minWidth, button:FullWidth())
    end
    return button:FullWidth()
  end

  local function place(width, force)
    width = math.max(1, math.floor(width))
    local widths, parts = {}, {}
    for i, item in ipairs(items) do
      if item.shown then
        widths[i] = math.min(width, natural(item, width))
        parts[#parts + 1] = i .. ":" .. widths[i]
      end
    end
    local signature = table.concat(parts, ",")
    if not force and width == lastWidth and signature == lastSignature then
      return contentHeight
    end
    lastWidth, lastSignature = width, signature
    local x, y = 0, 0
    lines = 0
    for i, item in ipairs(items) do
      local w = widths[i]
      if w then
        if lines == 0 then
          lines = 1
        elseif x + w > width then
          lines, x, y = lines + 1, 0, y + height + rowGap
        end
        item.button:ClearAllPoints()
        item.button:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
        item.button:SetSize(w, height)
        x = x + w + gap
      end
    end
    contentHeight = lines == 0 and 0 or lines * height + (lines - 1) * rowGap
    row:SetHeight(contentHeight)
    return contentHeight
  end

  local function replace()
    if lastWidth then
      place(lastWidth, true)
    end
  end

  function row:SetWidthAvailable(width)
    return place(width)
  end
  row.fgGridLayout = row.SetWidthAvailable
  function row:GetContentHeight()
    return contentHeight
  end
  function row:GetRowCount()
    return lines
  end
  function row:GetButton(id)
    return byId[id] and byId[id].button
  end
  function row:SetItemShown(id, shown)
    local item = byId[id]
    if item then
      item.def.shown, item.shown = shown and true or false, shown and true or false
      item.button:SetShown(item.shown)
      replace()
    end
  end
  function row:SetItemEnabled(id, enabled)
    local item = byId[id]
    if item then
      item.def.enabled, item.enabled = enabled and true or false, enabled and true or false
      item.button:SetEnabled(item.enabled)
    end
  end
  function row:SetItemText(id, key, literal)
    local item = byId[id]
    if item then
      W.SetText(item.button.label, key, literal)
      replace()
    end
  end
  function row:Refresh()
    for _, item in ipairs(items) do
      item.shown = flag(item.def.shown, true)
      item.enabled = flag(item.def.enabled, true)
      item.button:SetShown(item.shown)
      item.button:SetEnabled(item.enabled)
    end
    replace()
  end

  row:SetScript("OnSizeChanged", function(_, width)
    if width and width > 0 then
      place(width)
    end
  end)
  -- Language and font scale change the label widths; this message follows all label updates.
  ns.On("FG_UI_REFRESHED", replace)
  return row
end

-- Dropdown ------------------------------------------------------------------------------

-- W.Dropdown draws its button at a fixed width. This anchors the button on both sides of the
-- dropdown frame instead, so it follows whatever width the frame gets from its anchors.
function FL.FitDropdown(dropdown)
  local button = dropdown:GetChildren()
  if button then
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 0, -W.DROPDOWN_FIELD_Y)
    button:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", 0, -W.DROPDOWN_FIELD_Y)
  end
  return dropdown
end

-- Two panes -----------------------------------------------------------------------------

local SPLIT = {
  ratio = 0.34, -- left share of the width
  leftMin = 260,
  leftMax = 440,
  gap = 16,
  rightMin = 280, -- below this the panes stack
  stackBelow = 760, -- below this width the panes stack
  stackedShare = 0.4, -- share of the height of the upper pane when stacked
  stackedLeftMin = 180,
  stackedRightMin = 320,
  minHeight = 480, -- side by side
}

-- opts.rightMax (optional) caps the right pane; the left pane takes the rest, leftMax is ignored.
-- Pure geometry. width, height (available, may be nil or 0), opts (any key of SPLIT), needLeft
-- (height the left pane cannot go below), pageWidth (the width stackBelow is compared with,
-- default: width, a page passes its own width when its content is narrower because of padding
-- and scroll bars), needRight (the same for the right pane). Returns { mode = "side" | "stacked", leftWidth,
-- rightWidth, leftHeight, rightHeight, height, gap }.
function FL.ComputeSplit(width, height, opts, needLeft, pageWidth, needRight)
  local o = {}
  for k, v in pairs(SPLIT) do
    o[k] = v
  end
  for k, v in pairs(opts or {}) do
    o[k] = v
  end
  width = math.max(1, math.floor(width))
  height = (height and height > 0) and height or 0
  needLeft, needRight = needLeft or 0, needRight or 0
  local leftWidth = U.clamp(math.floor(width * o.ratio), o.leftMin, o.leftMax)
  if o.rightMax and width - o.gap - leftWidth > o.rightMax then
    leftWidth = width - o.gap - o.rightMax
  end
  local rightWidth = width - o.gap - leftWidth
  if (pageWidth or width) >= o.stackBelow and rightWidth >= o.rightMin then
    local h = math.max(height, o.minHeight, needLeft, needRight)
    return {
      mode = "side",
      leftWidth = leftWidth,
      rightWidth = rightWidth,
      leftHeight = h,
      rightHeight = h,
      height = h,
      gap = o.gap,
    }
  end
  local h = math.max(height, o.stackedLeftMin + o.gap + o.stackedRightMin)
  local leftHeight = math.max(o.stackedLeftMin, needLeft, math.floor(h * o.stackedShare))
  local rightHeight = math.max(o.stackedRightMin, needRight, h - leftHeight - o.gap)
  return {
    mode = "stacked",
    leftWidth = width,
    rightWidth = width,
    leftHeight = leftHeight,
    rightHeight = rightHeight,
    height = leftHeight + o.gap + rightHeight,
    gap = o.gap,
  }
end

-- Two containers, side by side (left width = ratio of the width within leftMin..leftMax, the
-- right one gets the rest) or stacked (left on top, about stackedShare of the height) when the
-- page width is below stackBelow. opts: any key of SPLIT, getHeight(width) -> available height
-- (default: none, so the minimum height), getPageWidth() -> the width stackBelow is compared
-- with (default: the width of the split), onLayout(info, split) -> optional minimum height
-- of the left pane and optionally the right pane (two values), called after every placement
-- (info as returned by FL.ComputeSplit). getHeight also gets the room the Stack hands to
-- fgGridLayout (see W.Stack) as second argument.
-- Returns the frame split with split.left, split.right and:
--   split:SetSizeAvailable(width, height)  places the panes, returns the total height
--   split:fgGridLayout(width, room)        the same with getHeight, for a page Stack
--   split:GetMode()                        "side" or "stacked"
-- The panes are anchored on both sides where the width allows it. The split also places itself
-- when its width changes (OnSizeChanged).
function FL.TwoPane(parent, opts)
  opts = opts or {}
  local split = CreateFrame("Frame", nil, parent)
  local left = CreateFrame("Frame", nil, split)
  local right = CreateFrame("Frame", nil, split)
  split.left, split.right = left, right
  local lastWidth

  local function apply(info)
    left:ClearAllPoints()
    right:ClearAllPoints()
    left:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
    left:SetSize(info.leftWidth, info.leftHeight)
    right:SetHeight(info.rightHeight)
    if info.mode == "side" then
      right:SetPoint("TOPLEFT", split, "TOPLEFT", info.leftWidth + info.gap, 0)
      right:SetPoint("TOPRIGHT", split, "TOPRIGHT", 0, 0)
    else
      local top = -(info.leftHeight + info.gap)
      left:SetPoint("TOPRIGHT", split, "TOPRIGHT", 0, 0)
      right:SetPoint("TOPLEFT", split, "TOPLEFT", 0, top)
      right:SetPoint("TOPRIGHT", split, "TOPRIGHT", 0, top)
    end
    split:SetHeight(info.height)
  end

  function split:SetSizeAvailable(width, height)
    lastWidth = math.floor(width)
    local pageWidth = opts.getPageWidth and opts.getPageWidth()
    pageWidth = pageWidth and pageWidth > 0 and pageWidth or nil
    local info = FL.ComputeSplit(width, height, opts, nil, pageWidth)
    apply(info)
    local need, needRight
    if opts.onLayout then
      need, needRight = opts.onLayout(info, split)
    end
    local grow = need and need > info.leftHeight + 0.5
    grow = grow or (needRight and needRight > info.rightHeight + 0.5)
    if grow then
      info = FL.ComputeSplit(width, height, opts, need, pageWidth, needRight)
      apply(info)
      opts.onLayout(info, split)
    end
    split.info = info
    return info.height
  end
  function split:fgGridLayout(width, room)
    return split:SetSizeAvailable(width, opts.getHeight and opts.getHeight(width, room) or 0)
  end
  function split:GetMode()
    return split.info and split.info.mode
  end

  split:SetScript("OnSizeChanged", function(_, width)
    if width and width > 0 and math.floor(width) ~= lastWidth then
      split:fgGridLayout(width)
    end
  end)
  return split
end
