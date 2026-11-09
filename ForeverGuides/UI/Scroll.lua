-- Scroll containers: ScrollArea for page content of variable height and
-- a virtualized ScrollList that only creates rows for the visible part.
local _, ns = ...
local W, Theme, U = ns.W, ns.Theme, ns.U

-- Visual line count of a multi-line EditBox. Falls back to counting text
-- lines when the client has no GetNumLines (wrapped lines are then missed).
function W.EditLineCount(eb)
  if eb.GetNumLines then
    local ok, n = pcall(eb.GetNumLines, eb)
    if ok and type(n) == "number" then
      return n
    end
  end
  local _, breaks = (eb:GetText() or ""):gsub("\n", "")
  return breaks + 1
end

local function scrollbar(parent, onScroll)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetWidth(6)
  bar:SetPoint("TOPRIGHT", -2, -2)
  bar:SetPoint("BOTTOMRIGHT", -2, 2)
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  thumb:SetWidth(6)
  ns.Bind(thumb, function(t)
    t:SetColorTexture(Theme.color("accentDim", 0.9))
  end)
  bar.thumb = thumb
  -- fraction visible (0-1], position 0-1
  function bar:Update(visibleFrac, pos)
    if visibleFrac >= 1 then
      bar:Hide()
      return
    end
    bar:Show()
    local h = bar:GetHeight()
    local th = math.max(20, h * visibleFrac)
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", 0, -(h - th) * pos)
  end
  bar:EnableMouse(true)
  -- nil while the game gives no usable cursor position.
  local function fracAtCursor(self)
    local _, cy = GetCursorPosition()
    local scale, top, height = self:GetEffectiveScale(), self:GetTop(), self:GetHeight()
    if type(cy) ~= "number" or type(scale) ~= "number" or scale <= 0 or type(top) ~= "number" then
      return nil
    end
    if type(height) ~= "number" or height <= 0 then
      return nil
    end
    return U.clamp((top - cy / scale) / height, 0, 1)
  end
  -- Click jumps to that position; holding the button down and moving the
  -- mouse keeps dragging it from wherever the cursor currently is, same as
  -- a browser scrollbar thumb. OnUpdate polls IsMouseButtonDown because
  -- Frame-type widgets have no OnDragStart/OnMouseUp drag gesture, only
  -- Button-type ones do.
  bar:SetScript("OnMouseDown", function(self)
    local frac = fracAtCursor(self)
    if frac then
      onScroll(frac)
    end
    self:SetScript("OnUpdate", function(bar2)
      if not IsMouseButtonDown("LeftButton") then
        bar2:SetScript("OnUpdate", nil)
        return
      end
      local now = fracAtCursor(bar2)
      if now then
        onScroll(now)
      end
    end)
  end)
  bar:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  return bar
end
W.Scrollbar = scrollbar

-- ScrollArea: area.content is the child to fill; call area:SetContentHeight(h).
function W.ScrollArea(parent)
  local area = CreateFrame("ScrollFrame", nil, parent)
  local content = CreateFrame("Frame", nil, area)
  content:SetSize(1, 1)
  area:SetScrollChild(content)
  area.content = content
  local function range()
    return math.max(0, content:GetHeight() - area:GetHeight())
  end
  local bar
  local function update()
    local r = range()
    local pos = r > 0 and area:GetVerticalScroll() / r or 0
    bar:Update(r > 0 and area:GetHeight() / content:GetHeight() or 1, pos)
  end
  bar = scrollbar(area, function(frac)
    area:SetVerticalScroll(range() * frac)
    update()
  end)
  function area:ScrollTo(y)
    area:SetVerticalScroll(U.clamp(y, 0, range()))
    update()
  end
  function area:SetContentHeight(h)
    content:SetHeight(math.max(1, h))
    area:ScrollTo(area:GetVerticalScroll())
  end
  area:EnableMouseWheel(true)
  area:SetScript("OnMouseWheel", function(_, delta)
    area:ScrollTo(area:GetVerticalScroll() - delta * 40)
  end)
  area:SetScript("OnSizeChanged", function(_, w)
    content:SetWidth(math.max(1, w - 12))
    update()
  end)
  return area
end

-- Horizontal scroller for content that is wider than its room (tables). Same look as the vertical bar,
-- laid flat under the content, with a faint track so there is something to click.
local HBAR, HBAR_GAP, WHEEL_STEP = 6, 4, 60

local function hscrollbar(parent, onDrag, onPage)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(HBAR)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.06)
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  thumb:SetHeight(HBAR)
  ns.Bind(thumb, function(t)
    t:SetColorTexture(Theme.color("accentDim", 0.9))
  end)
  bar.thumb = thumb
  local thumbW, pos = 0, 0
  -- fraction visible (0-1], position 0-1
  function bar:Update(visibleFrac, at)
    if visibleFrac >= 1 then
      bar:Hide()
      return
    end
    bar:Show()
    local w = bar:GetWidth()
    thumbW, pos = math.max(20, w * visibleFrac), at
    thumb:SetWidth(thumbW)
    thumb:ClearAllPoints()
    thumb:SetPoint("LEFT", (w - thumbW) * pos, 0)
  end
  bar:EnableMouse(true)
  -- nil while the game gives no usable cursor position.
  local function cursorX(self)
    local cx = GetCursorPosition()
    local scale, left = self:GetEffectiveScale(), self:GetLeft()
    if type(cx) ~= "number" or type(scale) ~= "number" or scale <= 0 or type(left) ~= "number" then
      return nil
    end
    return cx / scale - left
  end
  -- A press on the thumb drags it from where it was grabbed, a press beside it moves one page that way.
  -- OnUpdate polls IsMouseButtonDown, like the vertical bar.
  bar:SetScript("OnMouseDown", function(self)
    local x, left = cursorX(self), (self:GetWidth() - thumbW) * pos
    if not x then
      return
    end
    if x < left or x > left + thumbW then
      onPage(x < left and -1 or 1)
      return
    end
    local grab, room = x - left, self:GetWidth() - thumbW
    self:SetScript("OnUpdate", function(bar2)
      if not IsMouseButtonDown("LeftButton") then
        bar2:SetScript("OnUpdate", nil)
        return
      end
      local at = cursorX(bar2)
      if at then
        onDrag(room > 0 and U.clamp((at - grab) / room, 0, 1) or 0)
      end
    end)
  end)
  bar:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  return bar
end

-- HScrollArea: a view of the width the caller gives it over content of its own width. area.content is the
-- child to fill. opts: onScroll(x) runs after every change of the position (a frozen column follows it),
-- passTo = the scroll area of the page: the wheel without Shift goes on to it, so the page keeps scrolling
-- up and down over the table. Shift and wheel scroll sideways (a fixed convention, not in the key registry).
-- area:SetLayout(viewWidth, contentWidth, height) sizes view, content and bar, clamps the position (0 when
-- everything fits again) and returns the height the whole area needs, bar included.
function W.HScrollArea(parent, opts)
  opts = opts or {}
  local area = CreateFrame("Frame", nil, parent)
  local view = CreateFrame("ScrollFrame", nil, area)
  view.fgHorizontal = true
  view:SetPoint("TOPLEFT")
  local content = CreateFrame("Frame", nil, view)
  content:SetSize(1, 1)
  view:SetScrollChild(content)
  area.view, area.content = view, content
  local pos, range, viewW = 0, 0, 1
  local bar
  function area:GetScroll()
    return pos
  end
  function area:GetRange()
    return range
  end
  function area:ScrollTo(x)
    pos = U.clamp(x, 0, range)
    view:SetHorizontalScroll(pos)
    bar:Update(range > 0 and viewW / (viewW + range) or 1, range > 0 and pos / range or 0)
    if opts.onScroll then
      opts.onScroll(pos)
    end
  end
  bar = hscrollbar(area, function(frac)
    area:ScrollTo(range * frac)
  end, function(direction)
    area:ScrollTo(pos + direction * viewW)
  end)
  area.bar = bar
  bar:SetPoint("TOPLEFT", view, "BOTTOMLEFT", 0, -HBAR_GAP)
  bar:SetPoint("TOPRIGHT", view, "BOTTOMRIGHT", 0, -HBAR_GAP)
  function area:SetLayout(width, contentWidth, height)
    viewW = math.max(1, width)
    range = math.max(0, contentWidth - viewW)
    view:SetSize(viewW, height)
    content:SetSize(math.max(1, contentWidth), height)
    local total = height + (range > 0 and HBAR_GAP + HBAR or 0)
    area:SetHeight(total)
    area:ScrollTo(pos)
    return total
  end
  view:EnableMouseWheel(true)
  view:SetScript("OnMouseWheel", function(_, delta)
    local shift = rawget(_G, "IsShiftKeyDown")
    if range > 0 and shift and shift() then
      area:ScrollTo(pos - delta * WHEEL_STEP)
      return
    end
    local pass = opts.passTo and opts.passTo:GetScript("OnMouseWheel")
    if pass then
      pass(opts.passTo, delta)
    end
  end)
  return area
end

-- Vertical stack layout inside a ScrollArea content frame. Items stretch
-- to the full width; wrapped text recomputes its height on relayout.
local Stack = {}
Stack.__index = Stack

-- Left slack in front of every item: the first pixels of a scroll frame are
-- clipped, and a button that starts exactly at the padding lost its left border
-- there. The slack is wider than the 2 px selected border.
local EDGE = 2

function W.Stack(area, padding)
  return setmetatable({ area = area, parent = area.content, items = {}, pad = padding or 16 }, Stack)
end

-- item: frame or fontstring; opts: height (number) or auto for text, gap, indent
function Stack:Add(item, opts)
  opts = opts or {}
  self.items[#self.items + 1] = { item = item, opts = opts }
  return item
end

function Stack:Layout()
  local y = -self.pad
  local width = self.parent:GetWidth() - self.pad * 2
  for _, entry in ipairs(self.items) do
    local item, o = entry.item, entry.opts
    if item:IsShown() or o.keepSpace then
      local indent = o.indent or 0
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.pad + indent + EDGE, y)
      -- A fixed width never reaches past the page on a narrow window.
      local room = width - indent - EDGE
      local itemWidth = o.width and math.min(o.width, room) or room
      if item.fgHasLabel then
        -- An icon button with a short label: the label goes when the setting or the room says so,
        -- then the button is the square of its icon.
        local fit = item:Fit(itemWidth)
        itemWidth = item.fgLabelOn and itemWidth or fit
      end
      item:SetWidth(itemWidth)
      local h = o.height
      if item.fgGridLayout then
        -- The second argument tells an item that fills the page how much room is left.
        h = item:fgGridLayout(
          width - indent - EDGE,
          { top = -y, viewHeight = self.area:GetHeight(), pad = self.pad, gap = o.gap or 10 }
        )
      elseif h then
        -- Explicit height from the caller (e.g. K.NewList) was only ever
        -- used for the y-position math below, never actually applied to
        -- the item itself, leaving it at its creation height (often 0)
        -- forever regardless of how many times Layout() ran.
        item:SetHeight(h)
      elseif item.GetStringHeight then
        h = item:GetStringHeight()
        item:SetHeight(h)
      else
        h = item:GetHeight()
      end
      y = y - h - (o.gap or 10)
    end
  end
  if self.area.SetContentHeight then
    self.area:SetContentHeight(-y + self.pad)
  end
end

-- Grid of equal cards; columns from the window breakpoint.
function W.Grid(parent, cards, cardHeight, gap)
  local f = CreateFrame("Frame", nil, parent)
  gap = gap or 12
  function f:fgGridLayout(width)
    local cols = (ns.MainLayout and ns.MainLayout.columns) or 2
    local cw = (width - gap * (cols - 1)) / cols
    for i, card in ipairs(cards) do
      local col = (i - 1) % cols
      local row = math.floor((i - 1) / cols)
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", f, "TOPLEFT", col * (cw + gap), -row * (cardHeight + gap))
      card:SetSize(cw, cardHeight)
    end
    local rows = math.ceil(#cards / cols)
    local h = rows * cardHeight + math.max(0, rows - 1) * gap
    f:SetHeight(h)
    return h
  end
  return f
end

-- Virtual list. opts: rowHeight, createRow(parent) -> row, bindRow(row, item, index), onActivate(item),
-- onReorder(item, anchor, after) enables drag and drop of rows (drop before
-- `anchor`, or behind it when `after`), canReorder() -> bool gates it, indentOf(item, anchor, after) -> px (optional)
-- lets the line that marks the drop start that far from the left edge (nil or no option: the full width).
-- dropAt(item, probe) -> target, onDrop(item, target) and ghost(item) -> { text, glyph | texture } let the owner
-- decide what a drop at the cursor means (into a row, between rows) and what the label at the cursor shows.
function W.ScrollList(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  -- Same fix as the Dialogs.lua copy box: a frame nested inside a page's
  -- own scroll content does not automatically raise itself above it, so
  -- its rows render reserved space but no visible content.
  f:SetFrameLevel(parent:GetFrameLevel() + 1)
  f:SetClipsChildren(true)
  local rowH = opts.rowHeight or Theme.size.row
  local rows, data, offset = {}, {}, 0
  local bar
  local function visibleCount()
    return math.max(1, math.floor(f:GetHeight() / rowH))
  end
  local function maxOffset()
    return math.max(0, #data - visibleCount())
  end
  local attachDrag, drag
  local function refresh()
    local count = visibleCount()
    for i = 1, count do
      local row = rows[i]
      if not row then
        row = opts.createRow(f)
        row:SetHeight(rowH)
        rows[i] = row
        if opts.onReorder or opts.dropAt then
          attachDrag(row)
        end
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
      row:SetPoint("TOPRIGHT", -10, -(i - 1) * rowH)
      local item = data[offset + i]
      if item then
        ns.Safe("list-bind", opts.bindRow, row, item, offset + i)
        row:SetAlpha(drag and drag.item == item and 0.5 or 1)
        row:Show()
      else
        row:Hide()
      end
    end
    for i = count + 1, #rows do
      rows[i]:Hide()
    end
    local m = maxOffset()
    bar:Update(#data > 0 and count / #data or 1, m > 0 and offset / m or 0)
  end
  bar = scrollbar(f, function(frac)
    offset = U.round(maxOffset() * frac)
    refresh()
  end)
  function f:SetData(list)
    data = list or {}
    offset = U.clamp(offset, 0, maxOffset())
    refresh()
  end
  -- Rows of another height (a page that lays its rows out differently by width).
  function f:SetRowHeight(h)
    if h ~= rowH then
      rowH = h
      for _, row in ipairs(rows) do
        row:SetHeight(h)
      end
      offset = U.clamp(offset, 0, maxOffset())
      refresh()
    end
  end
  function f:ScrollBy(n)
    offset = U.clamp(offset + n, 0, maxOffset())
    refresh()
  end
  -- Scrolls just far enough to show the item at data index `index`.
  function f:Reveal(index)
    local count = visibleCount()
    if index <= offset then
      offset = math.max(0, index - 1)
    elseif index > offset + count then
      offset = index - count
    end
    offset = U.clamp(offset, 0, maxOffset())
    refresh()
  end

  -- Drag and drop reordering. The row frames are pooled, so the dragged item
  -- is remembered here and not read from the row again.
  local marker, hilite, ghost
  -- Distance of the cursor below the list top and from its left edge, in list units, and whether the cursor is far
  -- beside the list. They are nil, true and nil while the game gives no usable position, so a caller never sees a
  -- non-number.
  local function cursorRel()
    local cx, cy = GetCursorPosition()
    local scale = f:GetEffectiveScale()
    if type(cx) ~= "number" or type(cy) ~= "number" or type(scale) ~= "number" or scale <= 0 then
      return nil, true
    end
    local left, right = f:GetLeft() or 0, f:GetRight() or 0
    local x = cx / scale
    local out = x < left - 24 or x > right + 24
    return (f:GetTop() or 0) - cy / scale, out, x - left
  end
  -- Gap number 0..shown (0 = above the first visible row) under the cursor,
  -- or nil when the cursor is far outside the list (drop is cancelled).
  local function gapAtCursor()
    local rel, outside = cursorRel()
    local h = f:GetHeight()
    if outside or not rel or rel < -2 * rowH or rel > h + 2 * rowH then
      return nil, rel
    end
    local shown = math.min(visibleCount(), #data - offset)
    return U.clamp(math.floor(rel / rowH + 0.5), 0, shown), rel
  end
  local function dragTarget(gap)
    local shown = math.min(visibleCount(), #data - offset)
    if gap < shown then
      return data[offset + gap + 1], false
    end
    return data[offset + shown], true
  end
  -- With dropAt the owner decides what a drop at the cursor means: dropAt(item, { index, frac, x }) gets the data
  -- index of the row under the cursor, how far down in it (0..1) and the px from the left edge of the list, and
  -- answers nil (nothing to do) or a table { gap (line between data rows, 0..#data), row (data index marked),
  -- head (data index of a group row marked softly), indent (px), refuse (the target is forbidden) }.
  -- A drop calls onDrop(item, target) for every target, a refused one too.
  local function probe()
    local rel, outside, x = cursorRel()
    local h = f:GetHeight()
    if outside or not rel or rel < -2 * rowH or rel > h + 2 * rowH then
      return nil
    end
    local shown = math.min(visibleCount(), #data - offset)
    if shown <= 0 then
      return nil
    end
    local slot = math.floor(rel / rowH)
    local frac = rel / rowH - slot
    if slot < 0 then
      slot, frac = 0, 0
    elseif slot >= shown then
      slot, frac = shown - 1, 1
    end
    return { index = offset + slot + 1, frac = frac, x = x }
  end
  local function targetNow(item)
    local p = probe()
    if not p then
      return nil
    end
    local ok, target = ns.Safe("list-target", opts.dropAt, item, p)
    return ok and type(target) == "table" and target or nil
  end
  local function drawLine(gap, indent)
    if not marker then
      marker = CreateFrame("Frame", nil, f)
      marker:SetFrameLevel(f:GetFrameLevel() + 10)
      marker:SetHeight(2)
      marker.tex = marker:CreateTexture(nil, "OVERLAY")
      marker.tex:SetAllPoints()
      ns.Bind(marker.tex, function(t)
        t:SetColorTexture(Theme.color("accent2", 1))
      end)
    end
    local y = -gap * rowH
    if gap == 0 then
      y = 0
    else
      y = math.max(y + 1, -f:GetHeight() + 2)
    end
    marker:ClearAllPoints()
    marker:SetPoint("TOPLEFT", f, "TOPLEFT", indent, y)
    marker:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, y)
    marker:Show()
  end
  local function showMarker(gap, item)
    local indent = 0
    if opts.indentOf and item then
      local anchor, after = dragTarget(gap)
      local ok, px = pcall(opts.indentOf, item, anchor, after)
      indent = ok and type(px) == "number" and px > 0 and math.min(px, f:GetWidth()) or 0
    end
    drawLine(gap, indent)
  end
  -- A row of the list marked as the place the drag goes into (strong, with an edge) or as the group the line
  -- belongs to (soft); a forbidden target gets the warning color. Nothing is marked for data rows out of view.
  local function markRow(dataIndex, strong, forbidden)
    local slot = dataIndex and dataIndex - offset - 1
    if not slot or slot < 0 or slot >= visibleCount() or not data[dataIndex] then
      if hilite then
        hilite:Hide()
      end
      return
    end
    if not hilite then
      hilite = CreateFrame("Frame", nil, f)
      hilite:SetFrameLevel(f:GetFrameLevel() + 9)
      hilite.tex = hilite:CreateTexture(nil, "BACKGROUND")
      hilite.tex:SetAllPoints()
      hilite.border = W.Border(hilite, "accent2", 1, 2)
    end
    local color = forbidden and "danger" or "accent2"
    hilite.tex:SetColorTexture(Theme.color(color, strong and 0.28 or 0.14))
    hilite.border.set(color, 1)
    hilite.border.show(strong or forbidden)
    hilite:ClearAllPoints()
    hilite:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -slot * rowH)
    hilite:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -slot * rowH)
    hilite:SetHeight(rowH)
    hilite:Show()
  end
  -- The small label that follows the cursor: what is dragged, a bar sign when the drop would be refused.
  local function buildGhost()
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetHeight(22)
    W.Fill(ghost, "surface3", 0.96)
    ghost.border = W.Border(ghost, "accent2", 1)
    ghost.glyph = W.Glyph(ghost, "folder", 14, "accent2")
    ghost.glyph:SetPoint("LEFT", 5, 0)
    ghost.texture = ghost:CreateTexture(nil, "ARTWORK")
    ghost.texture:SetSize(14, 14)
    ghost.texture:SetPoint("LEFT", 5, 0)
    ghost.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ghost.ban = W.Glyph(ghost, "close", 12, "danger")
    ghost.ban:SetPoint("RIGHT", -5, 0)
    ghost.text = W.Text(ghost, { role = "ui", color = "text" })
    ghost.text:SetPoint("LEFT", 24, 0)
    ghost.text:SetPoint("RIGHT", -20, 0)
    ghost.text:SetWordWrap(false)
  end
  local function showGhost(item, refused)
    local info = opts.ghost and select(2, ns.Safe("list-ghost", opts.ghost, item)) or nil
    if type(info) ~= "table" then
      if ghost then
        ghost:Hide()
      end
      return
    end
    if not ghost then
      buildGhost()
    end
    if ghost.shownFor ~= item then
      ghost.shownFor = item
      W.SetText(ghost.text, nil, tostring(info.text or ""))
      ghost.texture:SetShown(info.texture ~= nil)
      ghost.glyph:SetShown(info.texture == nil and info.glyph ~= nil)
      if info.texture ~= nil then
        ghost.texture:SetTexture(info.texture)
      elseif info.glyph then
        ghost.glyph:SetIcon(info.glyph)
      end
      local width = ghost.text.GetStringWidth and ghost.text:GetStringWidth() or 120
      ghost:SetWidth(U.clamp((type(width) == "number" and width or 120) + 52, 90, 260))
    end
    ghost.border.set(refused and "danger" or "accent2", 1)
    ghost.ban:SetShown(refused == true)
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if type(cx) == "number" and type(cy) == "number" and type(scale) == "number" and scale > 0 then
      ghost:ClearAllPoints()
      ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale + 14, cy / scale - 6)
    end
    ghost:Show()
  end
  local function clearDrag()
    f:SetScript("OnUpdate", nil)
    if marker then
      marker:Hide()
    end
    if hilite then
      hilite:Hide()
    end
    if ghost then
      ghost.shownFor = nil
      ghost:Hide()
    end
    for _, row in ipairs(rows) do
      row:SetAlpha(1)
    end
  end
  local function endDrag(drop)
    local d = drag
    if not d then
      return
    end
    drag = nil
    clearDrag()
    d.row.fgDragged = true
    C_Timer.After(0.1, function()
      d.row.fgDragged = nil
    end)
    if not drop then
      return
    end
    if opts.dropAt then
      local target = targetNow(d.item)
      if target and opts.onDrop then
        ns.Safe("list-reorder", opts.onDrop, d.item, target)
      end
      return
    end
    local gap = gapAtCursor()
    local anchor, after
    if gap then
      anchor, after = dragTarget(gap)
    end
    if anchor and anchor ~= d.item then
      ns.Safe("list-reorder", opts.onReorder, d.item, anchor, after)
    end
  end
  local function dragTick(_, elapsed)
    if not drag then
      return
    end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
      endDrag(true)
      return
    end
    local rel = cursorRel()
    drag.wait = drag.wait + elapsed
    if rel and drag.wait >= 0.12 then
      local step = (rel < rowH * 0.4 and -1) or (rel > f:GetHeight() - rowH * 0.4 and 1) or 0
      if step ~= 0 then
        drag.wait = 0
        f:ScrollBy(step)
      end
    end
    if opts.dropAt then
      local target = targetNow(drag.item)
      if target and target.gap and not target.refuse then
        drawLine(U.clamp(target.gap - offset, 0, math.min(visibleCount(), #data - offset)), target.indent or 0)
      elseif marker then
        marker:Hide()
      end
      if target and target.row then
        markRow(target.row, true, target.refuse ~= nil)
      elseif target and target.head then
        markRow(target.head, false, false)
      else
        markRow(nil)
      end
      showGhost(drag.item, target ~= nil and target.refuse ~= nil)
      return
    end
    local at
    for i, item in ipairs(data) do
      if item == drag.item then
        at = i
        break
      end
    end
    -- A gap right above or below the dragged row changes nothing.
    local gap = gapAtCursor()
    local pos = gap and offset + gap
    if gap and at and pos ~= at - 1 and pos ~= at then
      showMarker(gap, drag.item)
    elseif marker then
      marker:Hide()
    end
  end
  function attachDrag(row)
    row:RegisterForDrag("LeftButton")
    row:SetScript(
      "OnDragStart",
      ns.Wrap("list-drag", function()
        if (opts.canReorder and not opts.canReorder()) or not row.item then
          return
        end
        drag = { item = row.item, row = row, wait = 0 }
        row:SetAlpha(0.5)
        f:SetScript("OnUpdate", dragTick)
      end)
    )
    row:SetScript(
      "OnDragStop",
      ns.Wrap("list-drag", function()
        endDrag(true)
      end)
    )
  end
  function f:IsDragging()
    return drag ~= nil
  end
  -- Ends a drag without a drop (Esc).
  function f:CancelDrag()
    endDrag(false)
  end
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    f:ScrollBy(-delta * 3)
  end)
  f:SetScript("OnSizeChanged", function()
    ns.Debounce(f, 0.05, refresh)
  end)
  -- A list that goes away in the middle of a drag drops nothing.
  f:HookScript("OnHide", function()
    f:CancelDrag()
  end)
  f.Refresh = refresh
  return f
end

-- Scrolling multi-line EditBox, same structure as the Dialogs.Copy box that
-- is confirmed to render text on this client: native ScrollFrame with an
-- explicitly sized scroll child, EditBox anchored TOPLEFT + TOPRIGHT with a
-- height that is set after every text change from the line count.
-- opts: padLeft (default 4), padRight (default 14, room for the scrollbar),
-- onTextChanged(editBox, user). Returns the ScrollFrame with .edit,
-- .content, :refreshHeight(), :ScrollTo(y) and :UpdateBar().
function W.EditScroll(parent, opts)
  opts = opts or {}
  local area = CreateFrame("ScrollFrame", nil, parent)
  area:SetFrameLevel(parent:GetFrameLevel() + 1)
  area:EnableMouseWheel(true)

  local content = CreateFrame("Frame", nil, area)
  content:SetWidth(area:GetWidth() > 0 and area:GetWidth() or 200)
  content:SetHeight(1)
  area:SetScrollChild(content)
  area.content = content

  local function range()
    return math.max(0, content:GetHeight() - area:GetHeight())
  end
  local bar
  function area:UpdateBar()
    if not bar then
      return
    end
    local r = range()
    local h = content:GetHeight()
    local visibleFrac = (area:GetHeight() > 0 and h > 0) and math.min(1, area:GetHeight() / h) or 1
    bar:Update(visibleFrac, r > 0 and area:GetVerticalScroll() / r or 0)
  end
  bar = scrollbar(area, function(frac)
    area:SetVerticalScroll(range() * frac)
    area:UpdateBar()
  end)
  function area:ScrollTo(y)
    area:SetVerticalScroll(U.clamp(y, 0, range()))
    area:UpdateBar()
  end

  local eb = CreateFrame("EditBox", nil, content)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetHeight(1)
  eb:SetPoint("TOPLEFT", content, "TOPLEFT", opts.padLeft or 4, 0)
  eb:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(opts.padRight or 14), 0)
  ns.Bind(eb, function()
    Theme.applyFont(eb, "ui", "body")
    eb:SetTextColor(Theme.color("text"))
  end)
  area.edit = eb

  -- Last reported caret rectangle, relative to the EditBox top.
  local caretTop, caretH
  local function followCaret()
    if not caretTop then
      return
    end
    local v, vh = area:GetVerticalScroll(), area:GetHeight()
    if caretTop < v then
      area:ScrollTo(caretTop)
    elseif caretTop + caretH > v + vh then
      area:ScrollTo(caretTop + caretH - vh + 4)
    end
  end
  eb:SetScript("OnCursorChanged", function(_, _, y, _, h)
    caretTop, caretH = -y, h
    followCaret()
  end)

  -- Deferred: GetNumLines is only up to date after the layout pass that
  -- follows the text change.
  local pending = false
  function area:refreshHeight()
    if pending then
      return
    end
    pending = true
    C_Timer.After(0.01, function()
      pending = false
      local lineHeight = (eb.GetLineHeight and eb:GetLineHeight()) or 14
      local h = math.max(W.EditLineCount(eb) * lineHeight, area:GetHeight() or 100)
      content:SetHeight(h)
      eb:SetHeight(h)
      area:ScrollTo(area:GetVerticalScroll())
      if eb:HasFocus() then
        followCaret()
      end
    end)
  end

  eb:SetScript("OnTextChanged", function(self, user)
    area:refreshHeight()
    if opts.onTextChanged then
      opts.onTextChanged(self, user)
    end
  end)
  area:SetScript("OnSizeChanged", function(_, w)
    content:SetWidth(math.max(1, w))
    area:refreshHeight()
  end)
  area:SetScript("OnMouseWheel", function(_, delta)
    area:ScrollTo(area:GetVerticalScroll() - delta * 40)
  end)
  content:EnableMouse(true)
  content:SetScript("OnMouseDown", function()
    eb:SetFocus()
  end)
  return area
end

-- Multi-line text field in a scroll area. opts: height, onChange(text), readOnly
function W.TextArea(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(opts.height or 90)
  W.Fill(f, "bg", 0.9)
  local border = W.Border(f, "white", 0.25)
  local scroll = W.EditScroll(f, {
    onTextChanged = ns.Wrap("textarea", function(self, user)
      if opts.readOnly and user then
        self:SetText(f.value or "")
        self:HighlightText()
        return
      end
      if user and opts.onChange then
        opts.onChange(self:GetText())
      end
    end),
  })
  scroll:SetPoint("TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", -4, 4)
  local eb = scroll.edit
  eb:SetScript("OnEscapePressed", eb.ClearFocus)
  eb:SetScript("OnEditFocusGained", function()
    border.set("actionHi", 1)
  end)
  eb:SetScript("OnEditFocusLost", function()
    border.set("white", 0.25)
  end)
  -- Sets text; for read-only fields it is restored on any edit.
  function f:SetValue(text)
    f.value = text or ""
    eb:SetText(f.value)
  end
  function f:GetValue()
    return eb:GetText()
  end
  ns.Focus.register(f, function()
    eb:SetFocus()
  end)
  f.edit = eb
  return f
end
