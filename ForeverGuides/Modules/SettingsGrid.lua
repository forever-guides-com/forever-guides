-- Cards in a responsive grid for the settings tabs. The grid is one item of a page Stack
-- (fgGridLayout); every card holds a nested Stack, so the section functions of the tabs fill a
-- card like a page view (view.content, view.stack, view:Layout()).
local _, ns = ...
local W, Theme = ns.W, ns.Theme

local SG = {}
ns.SettingsGrid = SG

SG.GAP = 12
SG.PAD = 12
SG.MAX_COLUMNS = 3
-- A switch needs its track and state text (76 px) plus its label in one line, and the longest
-- label is about 235 px wide, so a card of this width keeps every label whole.
SG.MIN_CARD = 340

-- Columns that fit into the width. Larger text needs wider cards, so the minimum grows with it.
function SG.Columns(width)
  local minCard = SG.MIN_CARD * math.max(1, Theme.fontScale())
  return math.max(1, math.min(SG.MAX_COLUMNS, math.floor((width + SG.GAP) / (minCard + SG.GAP))))
end

-- Trailing gap of the last visible entry, or nil when the stack shows nothing.
local function lastGap(stack)
  for i = #stack.items, 1, -1 do
    local entry = stack.items[i]
    if entry.item:IsShown() or entry.opts.keepSpace then
      return entry.opts.gap or 10
    end
  end
end

-- A card is a surface with a nested Stack. opts.span = "full" takes the whole width of the grid.
local function newCard(grid, view, opts)
  local frame = W.Card(grid)
  local card = { frame = frame, content = frame, grid = grid, span = opts.span }
  -- Stands in for the scroll area of a page view: the stack reads the viewport height from it and
  -- hands the inner height back.
  local area = { content = frame }
  function area.GetHeight()
    return view.area:GetHeight()
  end
  function area.SetContentHeight(_, h)
    card.inner = h
  end
  -- A section that scrolls to one of its controls asks for a position inside the card.
  function area.ScrollTo(_, y)
    view.area:ScrollTo((card.top or 0) + y)
  end
  card.area = area
  card.stack = W.Stack(area, SG.PAD)

  function card:Layout()
    view:Layout()
  end

  function card:Refresh()
    for _, entry in ipairs(self.stack.items) do
      if entry.item.Refresh then
        entry.item:Refresh()
      end
    end
  end

  -- Places the content at the given width and returns the card height, 0 for a card without a
  -- visible entry.
  function card:Measure(width)
    local gap = lastGap(self.stack)
    if not gap then
      frame:Hide()
      frame:SetHeight(0)
      return 0
    end
    frame:Show()
    frame:SetWidth(width)
    self.stack:Layout()
    local h = (self.inner or 0) - gap
    frame:SetHeight(h)
    return h
  end
  return card
end

-- Adds a grid to the page view and returns it. grid:Card(opts) appends a card and returns an
-- object with content, stack, area, Layout() and Refresh(); grid.cards lists them in order.
function SG.New(view)
  local grid = CreateFrame("Frame", nil, view.content)
  grid.cards = {}
  local busy = false

  function grid:Card(opts)
    local card = newCard(self, view, opts or {})
    self.cards[#self.cards + 1] = card
    return card
  end

  function grid:Refresh()
    for _, card in ipairs(self.cards) do
      card:Refresh()
    end
  end

  -- Every card goes to the shortest column, so the reading order stays and no gap opens.
  local function place(self, width, info)
    local columns = SG.Columns(width)
    local colWidth = (width - SG.GAP * (columns - 1)) / columns
    local bottoms = {}
    for c = 1, columns do
      bottoms[c] = 0
    end
    local function lowest()
      local at = 1
      for c = 2, columns do
        if bottoms[c] < bottoms[at] then
          at = c
        end
      end
      return at
    end
    local top = info and info.top or 0
    for _, card in ipairs(self.cards) do
      local full = card.span == "full" and columns > 1
      local first = full and 1 or lowest()
      local last = full and columns or first
      local y = 0
      for c = first, last do
        y = math.max(y, bottoms[c])
      end
      local h = card:Measure(full and width or colWidth)
      if h > 0 then
        card.top = top + y
        card.frame:ClearAllPoints()
        card.frame:SetPoint("TOPLEFT", self, "TOPLEFT", (first - 1) * (colWidth + SG.GAP), -y)
        for c = first, last do
          bottoms[c] = y + h + SG.GAP
        end
      end
    end
    local total = 0
    for c = 1, columns do
      total = math.max(total, bottoms[c])
    end
    total = math.max(0, total - SG.GAP)
    self:SetHeight(total)
    return total
  end

  function grid:fgGridLayout(width, info)
    -- A banner that changes its height while it is placed asks for a layout of the whole tab.
    if busy then
      return self:GetHeight()
    end
    busy = true
    local ok, total = pcall(place, self, width, info)
    busy = false
    if not ok then
      error(total, 0)
    end
    return total
  end

  view.grid = grid
  view.stack:Add(grid, { gap = 0 })
  return grid
end
