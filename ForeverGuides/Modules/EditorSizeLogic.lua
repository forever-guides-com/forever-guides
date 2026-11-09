-- Size of the layout editor window without WoW API: the limits (screen, minimum), the plausibility check of
-- a saved size and the split of a window size into the canvas view, the side column and the rows of the
-- lists. CanvasEditor.lua places its parts from the table Metrics returns, nothing there is a fixed size.
--
-- The side column takes a share of the width between a minimum and a maximum, the canvas view gets the
-- rest (so a wide window grows the canvas first once the column is as wide as it gets). Extra height goes to
-- the element list (more rows) and to the property area, the preview takes the rest of the body. The layouts
-- take no list: one row of the side column holds the picker, so a small window keeps its room for the elements.
local _, ns = ...
local U = ns.U

local ES = {
  DEFAULT_W = 1020,
  DEFAULT_H = 640,
  MIN_W = 900,
  MIN_H = 580,
  -- Absolute caps for a very large screen.
  MAX_W = 2400,
  MAX_H = 1600,
  -- Chrome around the body, shared with the window code.
  HEAD_H = 22,
  PAD = 8,
  ROW_H = 24,
  FOOT_H = 40,
  VIEWBAR_H = 46,
  -- The band under the title is two rows of controls on the left (the tools and Export, Import, preset, add)
  -- and, over the side column, the layout row (picker and buttons) with the line under it that says which
  -- layout this player uses.
  BAND_H = 76,
  LAYOUT_HEAD_H = 28,
  STATUS_H = 20,
  ELEMENTS_HEAD_H = 28,
  -- Side column: share of the window width, with a minimum and a maximum.
  SIDE_SHARE = 0.43,
  SIDE_MIN = 380,
  SIDE_MAX = 600,
  ELEMENT_ROWS = 5,
  MAX_ELEMENT_ROWS = 11,
  -- Extra window height (over the default) that adds one more row to the element list.
  ELEMENT_ROW_STEP = 80,
  -- Row of the layout dialog with a second line: the name line (a button of NAME_LINE_H) sits one unit below the
  -- top, the detail text under it with one unit of air.
  NAME_LINE_H = 22,
  DETAIL_PAD = 3,
  -- Line height of a text over its font size (the engine adds the shadow and the leading).
  LINE_FACTOR = 1.3,
}

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function whole(v)
  return math.floor(v + 0.5)
end

-- Smallest and largest window size for a screen of screenW x screenH (in the units of the window). The
-- maximum never falls below the minimum: on a tiny screen the window keeps the room its parts need.
function ES.Limits(screenW, screenH)
  local maxW, maxH = ES.MAX_W, ES.MAX_H
  if finite(screenW) and screenW > 0 then
    maxW = math.min(maxW, math.floor(screenW))
  end
  if finite(screenH) and screenH > 0 then
    maxH = math.min(maxH, math.floor(screenH))
  end
  return ES.MIN_W, ES.MIN_H, math.max(ES.MIN_W, maxW), math.max(ES.MIN_H, maxH)
end

-- A size the window may have: a missing or broken number becomes the default, the rest is held inside the
-- limits and rounded to whole units.
function ES.Clamp(w, h, screenW, screenH)
  local minW, minH, maxW, maxH = ES.Limits(screenW, screenH)
  w = finite(w) and w or ES.DEFAULT_W
  h = finite(h) and h or ES.DEFAULT_H
  return whole(U.clamp(w, minW, maxW)), whole(U.clamp(h, minH, maxH))
end

-- The saved size of the record `db` (w, h) as a usable size.
function ES.Saved(db, screenW, screenH)
  db = type(db) == "table" and db or {}
  return ES.Clamp(db.w, db.h, screenW, screenH)
end

-- Height of a layout dialog row that carries a detail line set in a font of `fontSize` px: the name line and the
-- detail line with their air, never below one and a half normal rows. The detail line starts at TwoLineDetailY.
function ES.TwoLineRowH(fontSize)
  local line = math.ceil((finite(fontSize) and fontSize > 0 and fontSize or 11) * ES.LINE_FACTOR)
  return math.max(ES.ROW_H * 1.5, ES.TwoLineDetailY() + line + ES.DETAIL_PAD), line
end

-- Distance of the detail line from the top of a two line row.
function ES.TwoLineDetailY()
  return 1 + ES.NAME_LINE_H + 1
end

-- The parts of a window of w x h (every number in the units of the window):
--   leftW, viewH           preview view, sideW (column) and contentW (inside the scroll area), halfW (two
--                          fields in a row), fieldW (the position fields), removeW and dupW (the two buttons)
--   bodyY, bodyH           top and height of the body under the band
--   bandH                  height of the band (BAND_H)
--   elementRows, propsH    rows of the element list and the height left for the properties
function ES.Metrics(w, h)
  w = finite(w) and math.max(ES.MIN_W, w) or ES.DEFAULT_W
  h = finite(h) and math.max(ES.MIN_H, h) or ES.DEFAULT_H
  local pad = ES.PAD
  local sideW = U.clamp(whole(w * ES.SIDE_SHARE), ES.SIDE_MIN, ES.SIDE_MAX)
  local leftW = w - pad * 3 - sideW
  local extra = math.max(0, h - ES.DEFAULT_H)
  local elementRows = math.min(ES.MAX_ELEMENT_ROWS, ES.ELEMENT_ROWS + math.floor(extra / ES.ELEMENT_ROW_STEP))
  local bandY = ES.HEAD_H + 4
  local bandH = ES.BAND_H
  local bodyY = bandY + bandH + 6
  local bodyH = h - bodyY - ES.FOOT_H - 4
  local contentW = sideW - 16
  local removeW = math.floor((contentW - 6) * 0.58)
  return {
    w = w,
    h = h,
    leftW = leftW,
    sideW = sideW,
    contentW = contentW,
    halfW = math.floor((contentW - 8) / 2),
    fieldW = math.floor((contentW - 84 - 8) / 2),
    removeW = removeW,
    dupW = contentW - removeW - 6,
    bandY = bandY,
    bandH = bandH,
    bodyY = bodyY,
    bodyH = bodyH,
    viewH = bodyH - ES.VIEWBAR_H - 6,
    elementRows = elementRows,
    propsH = bodyH - (ES.ELEMENTS_HEAD_H + elementRows * ES.ROW_H + 6),
  }
end

ns.EditorSize = ES
