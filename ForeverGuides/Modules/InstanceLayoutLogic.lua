-- Pure layout rules of the instance detail page (Modules/InstancesPage.lua): which of the three width modes
-- applies, how wide list and detail are, how the banner chips and the tab row give way when the room gets small, and
-- when the page has to scroll as a whole. No frames here: the page measures chip and tab widths and hands them in, so
-- every breakpoint is testable offline. All breakpoints live in this file.
local _, ns = ...

local ILL = {}
ns.InstanceLayoutLogic = ILL

-- Width of the content area (window minus sidebar).
ILL.WIDE_MIN = 900 -- from here list and detail sit side by side with a proportional list
ILL.MEDIUM_MIN = 600 -- from here side by side with a fixed list; below it one column
ILL.LIST_MIN = 260
ILL.LIST_SHARE = 0.32 -- wanted share of the list in wide mode
ILL.LIST_CAP_SHARE = 0.4 -- the list never takes more than this share
ILL.LIST_MEDIUM = 240
ILL.PANE_GAP = 12

-- What the page frame takes from the content width (page padding both sides and the scroll bar lane).
ILL.CHROME = 44

-- Heights.
ILL.BANNER_H = 72
ILL.BANNER_COLLAPSED_H = 32
ILL.TAB_ROW_H = 28
ILL.ROW_GAP = 8
ILL.BODY_MIN_H = 220 -- the least room an area needs; below it the banner collapses, then the page scrolls

ILL.CHIP_LINES_MAX = 2
ILL.CHIP_GAP = 6
ILL.TAB_GAP = 4
ILL.BANNER_PAD = 10
ILL.CHIP_ROW_H = 22
ILL.CHIP_ROW_GAP = 4
ILL.STACK_GAP = 6 -- space around the facts when they sit below the name
ILL.NAME_SHARE = 0.45 -- the left block of the banner never takes more than this share of the width

local floor, max, min = math.floor, math.max, math.min

function ILL.Mode(width)
  if width >= ILL.WIDE_MIN then
    return "wide"
  elseif width >= ILL.MEDIUM_MIN then
    return "medium"
  end
  return "narrow"
end

-- Width of the page column inside a content area of this width.
function ILL.Inner(width)
  return max(1, width - ILL.CHROME)
end

local function sum(list, gap)
  local total = 0
  for _, w in ipairs(list) do
    total = total + w
  end
  return total + gap * max(0, #list - 1)
end

-- Number of lines the widths take when packed left to right into `room` px (an item wider than the room has a
-- line of its own).
function ILL.Lines(widths, room, gap)
  if #widths == 0 then
    return 0
  end
  local lines, x = 1, 0
  for _, w in ipairs(widths) do
    if x > 0 and x + w > room then
      lines, x = lines + 1, 0
    end
    x = x + w + gap
  end
  return lines
end

local function listWidth(mode, inner)
  if mode == "narrow" then
    return inner
  elseif mode == "medium" then
    return min(ILL.LIST_MEDIUM, inner)
  end
  return max(ILL.LIST_MIN, min(floor(inner * ILL.LIST_SHARE), floor(inner * ILL.LIST_CAP_SHARE)))
end

local function compact(widths)
  local out = {}
  for i, w in ipairs(widths) do
    out[i] = floor(w * 0.72)
  end
  return out
end

-- Compute(width, height, opts) -> layout table.
-- width: content area width, height: room of the page below its padding. opts (all optional, px):
--   nameW (width of the name text), buttonsW (back and reset button side by side), factionH (height of the faction
--   switch on a row of its own), chipWidths (fact chips), actionW (map button, data hint), summaryW (the
--   collapsed chip), tabWidths, tabCompactWidths, moreW (the "More" button), factionW (nil: the faction filter has no
--   effect on this tab and takes no room).
-- Result: mode, listW, detailW (both inside the page column), nameW, chipRoom (banner), bannerH, bannerCollapsed, chipsMode ("wrap"|"summary"),
-- chipLines, factionRow ("inline"|"own"), tabsMode ("normal"|"compact"|"more"), tabRows, headH, pageScroll.
function ILL.Compute(width, height, opts)
  opts = opts or {}
  local mode = ILL.Mode(width)
  local inner = ILL.Inner(width)
  local listW = listWidth(mode, inner)
  local detailW = mode == "narrow" and inner or max(1, inner - listW - ILL.PANE_GAP)

  -- Banner: the left block (buttons above name) never gets less than its buttons, at most its share of the width
  -- otherwise. The facts sit right of it, packed into at most two lines, else in one summary chip. When even that does
  -- not fit beside the left block the facts move below it (bannerStacked), the banner grows by their lines.
  local nameW = min(opts.nameW or 200, floor(inner * ILL.NAME_SHARE))
  local leftW = max(opts.buttonsW or 0, nameW)
  local actions = opts.actionW or {}
  local function pack(room)
    local all = {}
    for _, w in ipairs(opts.chipWidths or {}) do
      all[#all + 1] = w
    end
    for _, w in ipairs(actions) do
      all[#all + 1] = w
    end
    local chipsMode, lines = "wrap", ILL.Lines(all, room, ILL.CHIP_GAP)
    local widest = 0
    for _, w in ipairs(all) do
      widest = max(widest, w)
    end
    if lines > ILL.CHIP_LINES_MAX then
      chipsMode = "summary"
      local folded = { opts.summaryW or 150 }
      widest = folded[1]
      for _, w in ipairs(actions) do
        folded[#folded + 1] = w
        widest = max(widest, w)
      end
      lines = ILL.Lines(folded, room, ILL.CHIP_GAP)
    end
    return chipsMode, lines, widest
  end
  local chipRoom = max(1, inner - 2 * ILL.BANNER_PAD - leftW - ILL.PANE_GAP)
  local chipsMode, chipLines, widest = pack(chipRoom)
  local stacked = chipRoom < widest or chipLines > ILL.CHIP_LINES_MAX
  if stacked then
    chipRoom = max(1, inner - 2 * ILL.BANNER_PAD)
    chipsMode, chipLines = pack(chipRoom)
  end
  local rightH = chipLines * ILL.CHIP_ROW_H + max(0, chipLines - 1) * ILL.CHIP_ROW_GAP

  -- Tab row: faction filter inline, else on its own row, else compact tabs, last the "More" button.
  local tabs = opts.tabWidths or {}
  local small = opts.tabCompactWidths or compact(tabs)
  local factionW = opts.factionW
  local gap = ILL.TAB_GAP
  local tabsMode, factionRow = "normal", "inline" -- the defaults are the first case
  local function withFaction(total)
    return factionW and (total + gap + factionW) or total
  end
  if withFaction(sum(tabs, gap)) > inner and sum(tabs, gap) <= inner then
    tabsMode, factionRow = "normal", factionW and "own" or "inline"
  elseif withFaction(sum(tabs, gap)) > inner and sum(small, gap) <= inner then
    tabsMode, factionRow = "compact", factionW and "own" or "inline"
  elseif withFaction(sum(tabs, gap)) > inner then
    tabsMode = "more"
    factionRow = (factionW and (opts.moreW or 80) + gap + factionW > inner) and "own" or "inline"
  end
  local tabRows = (factionW and factionRow == "own") and 2 or 1
  local tabsH = ILL.TAB_ROW_H
  if tabRows == 2 then
    tabsH = tabsH + ILL.ROW_GAP + max(ILL.TAB_ROW_H, opts.factionH or 0)
  end

  -- Height: the full banner, else the one-line banner, else the page scrolls as a whole.
  local fullBanner = stacked and (ILL.BANNER_H + ILL.STACK_GAP + rightH + ILL.STACK_GAP) or ILL.BANNER_H
  local fullHead = fullBanner + ILL.ROW_GAP + tabsH
  local oneLineHead = ILL.BANNER_COLLAPSED_H + ILL.ROW_GAP + tabsH
  local collapsed, pageScroll = false, false
  if height < fullHead + ILL.ROW_GAP + ILL.BODY_MIN_H then
    collapsed = true
    pageScroll = height < oneLineHead + ILL.ROW_GAP + ILL.BODY_MIN_H
  end
  local bannerH = collapsed and ILL.BANNER_COLLAPSED_H or fullBanner
  return {
    mode = mode,
    listW = listW,
    detailW = detailW,
    bannerH = bannerH,
    bannerCollapsed = collapsed,
    nameW = nameW,
    leftW = leftW,
    chipRoom = chipRoom,
    bannerStacked = stacked and not collapsed,
    rightH = rightH,
    chipsMode = chipsMode,
    chipLines = chipLines,
    factionRow = factionRow,
    tabsMode = tabsMode,
    tabRows = tabRows,
    headH = bannerH + ILL.ROW_GAP + tabsH,
    pageScroll = pageScroll,
  }
end

function ILL.Equal(a, b)
  if not (a and b) then
    return false
  end
  for k, v in pairs(a) do
    if b[k] ~= v then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end
