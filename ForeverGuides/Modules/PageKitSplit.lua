-- Master/detail shell of the page kit (extends ns.PageKit): a list on the left, a scrollable detail pane on the
-- right. Wide pages show both side by side; narrow pages show one of them, a back button leads to the list.
--
--   local split = K.MasterDetail(view.content, {
--     list = list,                                   -- a K.NewList (created before the shell: Tab reaches it first)
--     detail = function(width, height, narrow, md)   -- lays out md.content, answers the content height
--     end,
--     backKey = "x.back", backTip = "x.backTip",     -- optional, defaults to the shared "Back" texts
--     backFit = true,                                -- the back button takes the width of its label
--     onToggle = function(showingDetail) end,        -- narrow mode switched between list and detail
--   })
--   view.stack:Add(split, { gap = Theme.space.lg })  -- split:fgGridLayout(width, room) sizes it
--   split:SetSelected(item)                          -- remembers the item, narrow mode shows its detail
--   split:ShowDetail(false)                          -- narrow mode back to the list
--   split:ShowList()                                 -- the same for the back button: also focuses the selected row
local _, ns = ...
local W, Theme = ns.W, ns.Theme
local K = ns.PageKit

ns.AddLocale("enUS", {
  ["kit.split.back"] = "Back",
  ["kit.split.backTip"] = "Back to the list",
})
ns.AddLocale("deDE", {
  ["kit.split.back"] = "Zurück",
  ["kit.split.backTip"] = "Zurück zur Liste",
})

local floor, max, min = math.floor, math.max, math.min

-- Width of the scrollbar lane inside a W.ScrollArea (its default gutter).
local GUTTER = 12

local function scaled(px)
  return K.scaledHeight and K.scaledHeight(px) or px
end

local function defaultListWidth(width)
  return max(240, min(340, floor(width * 0.36)))
end

local function within(frame, root)
  while frame do
    if frame == root then
      return true
    end
    frame = frame.GetParent and frame:GetParent() or nil
  end
  return false
end

-- room.fill = { height, mode, listW } (a page that owns the whole height): the shell takes exactly that height and the
-- mode ("narrow" or not) and list width of the caller instead of its own breakpoints.
-- opts: list, detail(width, height, narrow, md) -> content height, minHeight (360), wideFrom (640),
-- listWidth(width) -> px (default max(240, min(340, 36 percent))), gap (Theme.space.md), backKey, backTip,
-- onToggle(showingDetail).
-- Fields: md.list, md.detail (the panel), md.scroll (W.ScrollArea), md.content (its child, the detail callback
-- fills it), md.selected, md.showing (narrow mode shows the detail).
function K.MasterDetail(parent, opts)
  local md = CreateFrame("Frame", nil, parent)
  md.list, md.opts = opts.list, opts
  md.list:SetParent(md)
  md.detail = W.Panel(md)
  md.scroll = W.ScrollArea(md.detail)
  md.content = md.scroll.content
  md.back = W.Button(md.detail, {
    key = opts.backKey or "kit.split.back",
    tooltip = opts.backTip or "kit.split.backTip",
    width = opts.backFit and 160 or 110,
    onClick = function()
      md:ShowList()
    end,
  })

  function md:SelectedItem()
    return self.selected
  end

  -- Narrow mode: true shows the detail, false the list. Wide mode shows both and ignores it.
  function md:ShowDetail(on)
    on = on and self.selected ~= nil or false
    if self.showing == on then
      return
    end
    self.showing = on
    if self.fgWidth then
      self:fgGridLayout(self.fgWidth, self.fgRoom)
    end
    if self.opts.onToggle then
      self.opts.onToggle(on)
    end
  end

  -- Narrow mode back from the detail: the list keeps its scroll position and selection, the row of the item the
  -- player came from has the focus again.
  function md:ShowList()
    local item = self.selected
    self:ShowDetail(false)
    if item ~= nil and self.list.FocusItem and self.list:IsShown() then
      self.list:FocusItem(item)
    end
  end

  -- Esc and the back key: narrow mode leaves the detail for the list. Returns true when it did.
  function md:CloseDetail()
    if self.fgNarrow and self.showing and self.detail:IsShown() then
      self:ShowList()
      return true
    end
    return false
  end

  -- A new item scrolls the detail back to the top; in narrow mode it opens the detail.
  function md:SetSelected(item)
    local changed = item ~= self.selected
    self.selected = item
    if changed then
      self.scroll:ScrollTo(0)
    end
    if item == nil then
      self.showing = false
    elseif changed then
      self.showing = true
    end
    if self.fgWidth then
      self:fgGridLayout(self.fgWidth, self.fgRoom)
    end
    if changed and self.opts.onToggle then
      self.opts.onToggle(self.showing)
    end
  end

  -- Keyboard order: the list first, then the detail (back button and controls inside). Focus walks the
  -- controls in registration order, so the detail controls that came before a list stop move behind it.
  function md:SyncFocusOrder()
    local items = ns.Focus.items
    local lastList = 0
    for i, frame in ipairs(items) do
      if within(frame, self.list) then
        lastList = i
      end
    end
    if lastList == 0 then
      return
    end
    local moved, kept = {}, {}
    for i, frame in ipairs(items) do
      if i < lastList and within(frame, self.detail) then
        moved[#moved + 1] = frame
      else
        kept[#kept + 1] = frame
      end
    end
    if #moved == 0 then
      return
    end
    local at
    for i, frame in ipairs(kept) do
      if within(frame, self.list) then
        at = i
      end
    end
    for n, frame in ipairs(moved) do
      table.insert(kept, at + n, frame)
    end
    for i = #items, 1, -1 do
      items[i] = nil
    end
    for i, frame in ipairs(kept) do
      items[i] = frame
    end
  end

  function md:fgGridLayout(width, room)
    self.fgWidth, self.fgRoom = width, room
    local o = self.opts
    local gap = o.gap or Theme.space.md
    local free = room and (room.viewHeight - room.top - room.pad) or 0
    local fill = room and room.fill or nil
    local full = fill and max(1, floor(fill.height)) or max(scaled(o.minHeight or 360), floor(free))
    local narrow = width < (o.wideFrom or 640)
    if fill then
      narrow = fill.mode == "narrow"
    end
    self.fgNarrow = narrow
    local listW, detailW, detailX
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.detail:ClearAllPoints()
    if narrow then
      local showDetail = self.showing and self.selected ~= nil
      listW, detailW, detailX = width, width, 0
      self.list:SetShown(not showDetail)
      self.detail:SetShown(showDetail)
    else
      listW = fill and min(fill.listW or width, width - gap) or (o.listWidth or defaultListWidth)(width)
      detailW, detailX = width - listW - gap, listW + gap
      self.list:Show()
      self.detail:Show()
    end
    self.list:SetSize(listW, full)
    self.detail:SetPoint("TOPLEFT", self, "TOPLEFT", detailX, 0)
    self.detail:SetSize(detailW, full)

    local pad = self.detail.pad
    local top = pad
    self.back:ClearAllPoints()
    self.back:SetShown(narrow)
    if narrow and o.backFit then
      self.back:SetWidth(self.back:Fit(detailW))
    end
    if narrow then
      self.back:SetPoint("TOPLEFT", self.detail, "TOPLEFT", pad, -pad)
      top = pad + self.back:GetHeight() + Theme.space.sm
    end
    local innerW, innerH = max(1, detailW - 2 * pad), max(1, full - top - pad)
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", self.detail, "TOPLEFT", pad, -top)
    self.scroll:SetSize(innerW, innerH)
    self.content:SetWidth(max(1, innerW - GUTTER))
    if self.detail:IsShown() and o.detail then
      local h = o.detail(max(1, innerW - GUTTER), innerH, narrow, self)
      self.scroll:SetContentHeight(type(h) == "number" and h or innerH)
    end
    self:SetHeight(full)
    self:SyncFocusOrder()
    return full
  end

  return md
end
