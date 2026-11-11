-- Pure side of the panel on Blizzard's world map (WorldMapBar.lua, no frames, no client calls): the room
-- a tab may use down to the edge of the map window and how high the page viewport gets when the content
-- is taller than that room (the rest scrolls).
local _, ns = ...

local Logic = {}
ns.WorldMapBarLogic = Logic

-- Smallest room a page gets, so a tiny window still shows a few rows and a scroll bar.
Logic.MIN_AVAIL = 60
-- Content may exceed the room by this much (px) before it counts as overflow (rounding of text heights).
Logic.SLACK = 0.5

local function num(v, default)
  if type(v) == "number" and v == v and v > -math.huge and v < math.huge then
    return v
  end
  return default
end

-- Room in px for the page: the height of the map canvas minus the offset of the bar from its edge, the
-- margin, the space the overlays at the far edge keep (`reserve`), the header with the tabs (`pageTop`)
-- and the bottom padding.
function Logic.Space(mapHeight, offset, margin, reserve, pageTop, pad)
  local room = num(mapHeight, 0) - num(offset, 0) - num(margin, 0) - num(reserve, 0) - num(pageTop, 0) - num(pad, 0)
  return math.max(Logic.MIN_AVAIL, room)
end

-- Height of the page viewport for a content of `content` px in `avail` px. Returns the height and whether
-- the content has to scroll. A content that fits keeps its own height and gets no scroll bar.
function Logic.Fit(content, avail)
  content = math.max(0, num(content, 0))
  avail = math.max(Logic.MIN_AVAIL, num(avail, Logic.MIN_AVAIL))
  if content <= avail + Logic.SLACK then
    return content, false
  end
  return avail, true
end
