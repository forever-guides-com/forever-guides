-- Card flow, pure side (no frames): how many columns a width holds and where blocks of different height
-- go. Used by K.RowPool (PageKit.lua) when a page lists self-contained blocks as cards.
local _, ns = ...

local C = {}
ns.CardFlow = C

C.MAX_COLUMNS = 3

-- Columns that fit `width` with at least `minWidth` per card (1 to MAX_COLUMNS) and the card width of
-- that split (maxColumns raises or lowers the cap of MAX_COLUMNS). One column takes the full width, so a
-- narrow window looks like a plain list.
function C.Columns(width, minWidth, gap, maxColumns)
  width = math.max(1, width)
  local cols = math.floor((width + gap) / (math.max(1, minWidth) + gap))
  cols = math.max(1, math.min(maxColumns or C.MAX_COLUMNS, cols))
  return cols, (width - gap * (cols - 1)) / cols
end

-- Places blocks of the given heights. Each block goes to the shortest column (the leftmost on a tie), so
-- uneven heights leave no holes and the order still reads left to right, top to bottom within a column
-- pair. Returns { { col, x, y }, ... } (x, y from the top left) and the total height.
function C.Place(heights, cols, colWidth, gap)
  local tops, out = {}, {}
  for c = 1, cols do
    tops[c] = 0
  end
  for i, h in ipairs(heights) do
    local best = 1
    for c = 2, cols do
      if tops[c] < tops[best] then
        best = c
      end
    end
    out[i] = { col = best, x = (best - 1) * (colWidth + gap), y = tops[best] }
    tops[best] = tops[best] + h + gap
  end
  local total = 0
  for c = 1, cols do
    total = math.max(total, tops[c] - gap)
  end
  return out, math.max(0, total)
end
