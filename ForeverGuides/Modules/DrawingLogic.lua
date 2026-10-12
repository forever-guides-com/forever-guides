-- Raster canvas model for the drawings feature (pure Lua, no frames).
-- A drawing is { w, h, palette = { {r,g,b}, ... }, cells = { index... } } with
-- 1-based coordinates (x in 1..w, y in 1..h) and cells = palette indices in
-- row-major order. Palette index 1 is the background.
--
-- Every tool is D.<tool>(drawing, opts) and returns a changeset
-- { n, cells = {i...}, old = {...}, new = {...} } (cell index, old and new
-- palette index, one entry per really changed cell). Common opts: color
-- (palette index), size (brush 1..9, or 0.25 / 0.5 / 0.75 for a sub-cell pen with
-- soft edges), shape ("square"|"round"), preview (the
-- bitmap stays untouched, the changeset only lists what would change), into
-- (an open changeset to merge into, used by the editor for one undo step).
-- Tools return nil, "args" for unusable input.
-- Soft edges (opts.aa = true on pencil, eraser, line, rect, ellipse): instead of
-- whole cells the tool computes a coverage 0..1 per cell and blends the stroke
-- color over what is there. The blended color is looked up in the palette
-- (nearby entry reused, else appended and flagged in d.auto so the swatch grids
-- skip it). Within one changeset a cell keeps the maximum coverage, so a freehand
-- stroke never darkens where its segments overlap.
-- Resizing the canvas (D.resize, D.cropToSelection) is not a cell tool: its
-- changeset has kind = "resize" and keeps the old size and the cropped-off cells,
-- so D.apply / D.revert and the editor's undo restore size and content exactly.
local _, ns = ...

local D = {
  MIN_DIM = 8,
  MAX_DIM = 320,
  MAX_CELLS = 80000,
  MAX_PALETTE = 256,
  AA_LEVELS = 8,
  AA_REUSE = 6,
  MAX_BRUSH = 9,
  MIN_BRUSH = 0.25,
  THIN_MIN_COVERAGE = 1 / 16,
  THIN_GAMMA = 1 / 1.4,
  MAX_UNDO = 60,
  UNDO_CELL_CAP = 150000,
  BACKGROUND = 1,
  COORD_LIMIT = 512,
}
ns.DrawingLogic = D

-- Brush widths the editor offers, in cells. Below 1 the stroke is soft only.
D.BRUSH_SIZES = { 0.25, 0.5, 0.75, 1, 2, 3, 4, 5, 6, 7, 8, 9 }

D.PRESETS = {
  { w = 64, h = 48 },
  { w = 96, h = 64 },
  { w = 128, h = 96 },
  { w = 192, h = 144 },
  { w = 256, h = 192 },
  { w = 320, h = 240 },
}

-- Fill tolerance steps in percent of the largest possible color distance.
D.TOLERANCES = { 0, 6, 12, 25, 40 }
D.DEFAULT_TOLERANCE = 12

-- Index 1 white (background), 2 black, then the classic Paint colors and
-- twelve extras (grays, skin tones, saturated primaries).
D.DEFAULT_PALETTE = {
  { 255, 255, 255 },
  { 0, 0, 0 },
  { 127, 127, 127 },
  { 136, 0, 21 },
  { 237, 28, 36 },
  { 255, 127, 39 },
  { 255, 242, 0 },
  { 34, 177, 76 },
  { 0, 162, 232 },
  { 63, 72, 204 },
  { 163, 73, 164 },
  { 195, 195, 195 },
  { 185, 122, 87 },
  { 255, 174, 201 },
  { 255, 201, 14 },
  { 239, 228, 176 },
  { 181, 230, 29 },
  { 153, 217, 234 },
  { 112, 146, 190 },
  { 200, 191, 231 },
  { 64, 64, 64 },
  { 0, 100, 0 },
  { 0, 0, 128 },
  { 0, 255, 255 },
  { 255, 0, 255 },
  { 0, 0, 255 },
  { 0, 255, 0 },
  { 0, 128, 128 },
  { 128, 128, 0 },
  { 255, 224, 189 },
  { 141, 85, 36 },
  { 210, 180, 140 },
}

local floor, abs = math.floor, math.abs

-- Model ---------------------------------------------------------------------------

local function isInt(v)
  return type(v) == "number" and v % 1 == 0
end

function D.validDims(w, h)
  return isInt(w)
    and isInt(h)
    and w >= D.MIN_DIM
    and w <= D.MAX_DIM
    and h >= D.MIN_DIM
    and h <= D.MAX_DIM
    and w * h <= D.MAX_CELLS
end

local function validColor(c)
  if type(c) ~= "table" then
    return false
  end
  for k = 1, 3 do
    if not (isInt(c[k]) and c[k] >= 0 and c[k] <= 255) then
      return false
    end
  end
  return true
end

-- Returns a copy of a palette list or nil, "palette".
function D.cleanPalette(list)
  if type(list) ~= "table" or #list < 1 or #list > D.MAX_PALETTE then
    return nil, "palette"
  end
  local out = {}
  for i = 1, #list do
    if not validColor(list[i]) then
      return nil, "palette"
    end
    out[i] = { list[i][1], list[i][2], list[i][3] }
  end
  return out
end

-- Blank drawing, every cell is the background. Returns nil, "dims" | "palette".
function D.new(w, h, palette)
  if not D.validDims(w, h) then
    return nil, "dims"
  end
  local pal, why = D.cleanPalette(palette or D.DEFAULT_PALETTE)
  if not pal then
    return nil, why
  end
  local cells = {}
  for i = 1, w * h do
    cells[i] = D.BACKGROUND
  end
  return { w = w, h = h, palette = pal, cells = cells }
end

-- d.auto is optional: { [paletteIndex] = true } for colors the soft-edge tools
-- added (never index 1). The swatch grids only list the other colors.
local function validAuto(auto, count)
  if auto == nil then
    return true
  end
  if type(auto) ~= "table" then
    return false
  end
  for k, v in pairs(auto) do
    if not (isInt(k) and k >= 2 and k <= count and v == true) then
      return false
    end
  end
  return true
end

-- True when palette entry i was added by a soft-edge tool.
function D.isAuto(d, i)
  return d.auto ~= nil and d.auto[i] == true
end

-- Palette indices of the colors a user picks from (everything not auto), in order.
function D.userColors(d)
  local list = {}
  for i = 1, #d.palette do
    if not D.isAuto(d, i) then
      list[#list + 1] = i
    end
  end
  return list
end

-- Background map (optional, d.map): only the key of a map, never its pictures. A zone map is
-- { kind = "zone", id = uiMapID, alpha }, a dungeon or raid floor is { kind = "instance", key =
-- Data.DungeonAssets name, floor, alpha }; alpha is the map's opacity in percent.
D.MAP_ALPHA_DEFAULT = 70
D.MAP_MAX_ID = 65535
D.MAP_MAX_KEY = 48
D.MAP_MAX_FLOOR = 32

-- Instance names are plain ASCII ("Zul'Farrak", "Dire Maul - East").
function D.validMapKey(key)
  return type(key) == "string"
    and #key >= 1
    and #key <= D.MAP_MAX_KEY
    and key:find("^[A-Za-z0-9][A-Za-z0-9 %-':%.]*$") ~= nil
end

-- A normalized copy of a valid map, nil for anything else.
function D.cleanMap(m)
  if type(m) ~= "table" or not (isInt(m.alpha) and m.alpha >= 0 and m.alpha <= 100) then
    return nil
  end
  if m.kind == "zone" and isInt(m.id) and m.id >= 1 and m.id <= D.MAP_MAX_ID then
    return { kind = "zone", id = m.id, alpha = m.alpha }
  end
  if
    m.kind == "instance"
    and D.validMapKey(m.key)
    and isInt(m.floor)
    and m.floor >= 1
    and m.floor <= D.MAP_MAX_FLOOR
  then
    return { kind = "instance", key = m.key, floor = m.floor, alpha = m.alpha }
  end
  return nil
end

-- Same map (or both none), compared by value.
function D.sameMap(a, b)
  if a == nil or b == nil then
    return a == b
  end
  return a.kind == b.kind and a.id == b.id and a.key == b.key and a.floor == b.floor and a.alpha == b.alpha
end

-- Returns true or false, reason ("shape" | "dims" | "palette" | "map" | "cells").
function D.validate(d)
  if type(d) ~= "table" then
    return false, "shape"
  end
  if not D.validDims(d.w, d.h) then
    return false, "dims"
  end
  if d.map ~= nil and not D.cleanMap(d.map) then
    return false, "map"
  end
  if not D.cleanPalette(d.palette) or not validAuto(d.auto, #d.palette) then
    return false, "palette"
  end
  local cells, total, count = d.cells, d.w * d.h, #d.palette
  if type(cells) ~= "table" or cells[total] == nil or cells[total + 1] ~= nil then
    return false, "cells"
  end
  for i = 1, total do
    local v = cells[i]
    if not isInt(v) or v < 1 or v > count then
      return false, "cells"
    end
  end
  return true
end

function D.clone(d)
  local pal, cells = {}, {}
  for i, c in ipairs(d.palette) do
    pal[i] = { c[1], c[2], c[3] }
  end
  for i = 1, #d.cells do
    cells[i] = d.cells[i]
  end
  local out = { w = d.w, h = d.h, palette = pal, cells = cells, map = D.cleanMap(d.map) }
  if d.auto then
    out.auto = {}
    for i in pairs(d.auto) do
      out.auto[i] = true
    end
  end
  return out
end

-- Palette index of an existing or newly appended color; nil, "full" when the
-- palette is at its limit. Channels are rounded and clamped to 0..255. `auto`
-- flags a new entry as soft-edge helper color; picking an existing auto color
-- on purpose (auto = false) turns it into a normal one.
function D.addColor(d, r, g, b, auto)
  local c = {}
  for k, v in ipairs({ r, g, b }) do
    c[k] = floor(math.max(0, math.min(255, tonumber(v) or 0)) + 0.5)
  end
  for i, p in ipairs(d.palette) do
    if p[1] == c[1] and p[2] == c[2] and p[3] == c[3] then
      if not auto and d.auto and d.auto[i] then
        d.auto[i] = nil
      end
      return i
    end
  end
  if #d.palette >= D.MAX_PALETTE then
    return nil, "full"
  end
  d.palette[#d.palette + 1] = c
  if auto then
    d.auto = d.auto or {}
    d.auto[#d.palette] = true
  end
  return #d.palette
end

-- Nearest palette entry to a color: index, distance (RGB, 0..441.7).
local sqrt = math.sqrt

local function nearest(d, r, g, b)
  local best, bestDist = 1, math.huge
  for i, p in ipairs(d.palette) do
    local dr, dg, db = p[1] - r, p[2] - g, p[3] - b
    local dist = dr * dr + dg * dg + db * db
    if dist < bestDist then
      best, bestDist = i, dist
      if dist == 0 then
        break
      end
    end
  end
  return best, sqrt(bestDist)
end

-- RGB distance of two palette entries (0..441.7).
local MAX_DISTANCE = sqrt(3 * 255 * 255)

local function distance(p, q)
  local dr, dg, db = p[1] - q[1], p[2] - q[2], p[3] - q[3]
  return sqrt(dr * dr + dg * dg + db * db)
end

function D.pick(d, x, y)
  if isInt(x) and isInt(y) and x >= 1 and x <= d.w and y >= 1 and y <= d.h then
    return d.cells[(y - 1) * d.w + x]
  end
end

-- Changesets -----------------------------------------------------------------------

local function open(o)
  if o.into then
    return o.into
  end
  return { n = 0, cells = {}, old = {}, new = {}, pos = {}, preview = o.preview == true }
end

-- Records `color` for cell i. The first old value of a cell is kept, so a
-- cell painted twice in one action undoes straight to its original color.
local function put(d, ch, i, color)
  local cells, p = d.cells, ch.pos[i]
  if p then
    ch.new[p] = color
  elseif cells[i] ~= color then
    local n = ch.n + 1
    ch.n, ch.pos[i] = n, n
    ch.cells[n], ch.old[n], ch.new[n] = i, cells[i], color
  end
  if not ch.preview then
    cells[i] = color
  end
end

local function plot(d, ch, x, y, color)
  if x >= 1 and x <= d.w and y >= 1 and y <= d.h then
    put(d, ch, (y - 1) * d.w + x, color)
  end
end

-- Drops entries that ended up unchanged and the bookkeeping map.
function D.compact(ch)
  local n, cells, old, new = 0, ch.cells, ch.old, ch.new
  for k = 1, ch.n do
    if old[k] ~= new[k] then
      n = n + 1
      cells[n], old[n], new[n] = cells[k], old[k], new[k]
    end
  end
  for k = n + 1, ch.n do
    cells[k], old[k], new[k] = nil, nil, nil
  end
  ch.n, ch.pos, ch.aa = n, nil, nil
  return ch
end

local function finish(ch, o)
  if o.into then
    return ch
  end
  return D.compact(ch)
end

-- Writes the new values (redo, or commit of a preview changeset).
function D.apply(d, ch)
  if ch.kind == "resize" then
    return D.reshape(d, ch)
  end
  for k = 1, ch.n do
    d.cells[ch.cells[k]] = ch.new[k]
  end
end

-- Writes the old values (undo).
function D.revert(d, ch)
  if ch.kind == "resize" then
    return D.unshape(d, ch)
  end
  for k = 1, ch.n do
    d.cells[ch.cells[k]] = ch.old[k]
  end
end

-- Input helpers ----------------------------------------------------------------------

local function int(v)
  if type(v) ~= "number" or v ~= v then
    return nil
  end
  return math.max(-D.COORD_LIMIT, math.min(D.COORD_LIMIT, floor(v)))
end

local function colorOf(d, c)
  if isInt(c) and c >= 1 and c <= #d.palette then
    return c
  end
end

local function box(o)
  local x1, y1, x2, y2 = int(o.x1), int(o.y1), int(o.x2), int(o.y2)
  if not (x1 and y1 and x2 and y2) then
    return nil
  end
  return math.min(x1, x2), math.min(y1, y2), math.max(x1, x2), math.max(y1, y2)
end

local function with(o, color)
  local copy = {}
  for k, v in pairs(o) do
    copy[k] = v
  end
  copy.color = color
  return copy
end

-- Brush ----------------------------------------------------------------------------

local masks = {}

-- Offsets (dx, dy) from the cursor cell. Even sizes reach one cell further to
-- the right and down. The round brush is a digital disk (size 3 is a plus).
local function mask(size, shape)
  size = math.max(1, D.brushSize(size))
  shape = shape == "round" and "round" or "square"
  local key = shape .. size
  local m = masks[key]
  if not m then
    local lo = floor((size - 1) / 2)
    local c, r = (size - 1) / 2, (size - 1) / 2 + 0.4
    m = { n = 0, dx = {}, dy = {}, lo = lo, hi = floor(size / 2), size = size }
    for j = 0, size - 1 do
      for i = 0, size - 1 do
        if shape == "square" or (i - c) ^ 2 + (j - c) ^ 2 <= r * r then
          m.n = m.n + 1
          m.dx[m.n], m.dy[m.n] = i - lo, j - lo
        end
      end
    end
    masks[key] = m
  end
  return m
end

local function stamp(d, ch, x, y, color, m)
  for k = 1, m.n do
    plot(d, ch, x + m.dx[k], y + m.dy[k], color)
  end
end

local function bresenham(x1, y1, x2, y2, fn)
  local dx, dy = abs(x2 - x1), -abs(y2 - y1)
  local sx, sy = x1 < x2 and 1 or -1, y1 < y2 and 1 or -1
  local err = dx + dy
  while true do
    fn(x1, y1)
    if x1 == x2 and y1 == y2 then
      break
    end
    local e2 = 2 * err
    if e2 >= dy then
      err, x1 = err + dy, x1 + sx
    end
    if e2 <= dx then
      err, y1 = err + dx, y1 + sy
    end
  end
end

local function drawLine(d, ch, x1, y1, x2, y2, color, m)
  bresenham(x1, y1, x2, y2, function(x, y)
    stamp(d, ch, x, y, color, m)
  end)
end

local function fillBox(d, ch, x1, y1, x2, y2, color)
  for y = math.max(y1, 1), math.min(y2, d.h) do
    for x = math.max(x1, 1), math.min(x2, d.w) do
      put(d, ch, (y - 1) * d.w + x, color)
    end
  end
end

-- The box shrunk by the brush reach, so a thick outline stays inside the box
-- the user dragged.
local function inset(x1, y1, x2, y2, m)
  local a, b, c, e = x1 + m.lo, y1 + m.lo, x2 - m.hi, y2 - m.hi
  if a > c then
    a = floor((x1 + x2) / 2)
    c = a
  end
  if b > e then
    b = floor((y1 + y2) / 2)
    e = b
  end
  return a, b, c, e
end

-- Brush width as a usable number: whole cells 1..MAX_BRUSH, or a quarter step
-- 0.25..0.75 for the sub-cell pen. Anything else (nil, NaN, 1.5, 0) is one cell.
function D.brushSize(size)
  if type(size) ~= "number" or size ~= size then
    return 1
  end
  if size < 1 then
    local q = floor(size * 4 + 0.5) / 4
    return q < D.MIN_BRUSH and 1 or math.min(q, 0.75)
  end
  return isInt(size) and math.min(D.MAX_BRUSH, size) or 1
end

-- The eraser stays on whole cells.
local function wholeSize(size)
  return math.max(1, floor(D.brushSize(size)))
end

-- Soft edges ------------------------------------------------------------------------------

-- Continuous coordinates: cell (x, y) is the unit square around the point (x, y).
local function num(v)
  if type(v) ~= "number" or v ~= v then
    return nil
  end
  return math.max(-D.COORD_LIMIT, math.min(D.COORD_LIMIT, v))
end

-- Even brush sizes reach one cell further right and down, so their center sits
-- half a cell off the anchor cell.
function D.brushOffset(size)
  size = D.brushSize(size)
  return size >= 1 and size % 2 == 0 and 0.5 or 0
end

local function clamp01(v)
  return v < 0 and 0 or v > 1 and 1 or v
end

local function segmentDistance(px, py, x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local len2, t = dx * dx + dy * dy, 0
  if len2 > 0 then
    t = clamp01(((px - x1) * dx + (py - y1) * dy) / len2)
  end
  local qx, qy = x1 + t * dx - px, y1 + t * dy - py
  return sqrt(qx * qx + qy * qy)
end

-- Coverage 0..1 of the cell around (px, py) by a round brush of the given
-- radius moved along the segment: the distance from the cell center to the
-- segment decides, with a linear ramp one cell wide (an edge through the middle
-- of a cell gives 0.5, an axis-aligned stroke of whole-cell width stays crisp).
function D.capsuleCoverage(px, py, x1, y1, x2, y2, radius)
  return clamp01(radius + 0.5 - segmentDistance(px, py, x1, y1, x2, y2))
end

-- Sutherland-Hodgman step: keeps the part of a flat polygon with a*x + b*y <= c.
local function clipPolygon(poly, a, b, c)
  local out, n = {}, #poly
  local px, py = poly[n - 1], poly[n]
  local pin = a * px + b * py <= c
  for i = 1, n, 2 do
    local x, y = poly[i], poly[i + 1]
    local inside = a * x + b * y <= c
    if inside ~= pin then
      local t = (c - a * px - b * py) / (a * (x - px) + b * (y - py))
      out[#out + 1], out[#out + 2] = px + t * (x - px), py + t * (y - py)
    end
    if inside then
      out[#out + 1], out[#out + 2] = x, y
    end
    px, py, pin = x, y, inside
  end
  return out
end

local function polygonArea(poly)
  local n, sum = #poly, 0
  if n < 6 then
    return 0
  end
  local px, py = poly[n - 1], poly[n]
  for i = 1, n, 2 do
    sum = sum + px * poly[i + 1] - poly[i] * py
    px, py = poly[i], poly[i + 1]
  end
  return abs(sum) / 2
end

-- Exact coverage 0..1 of the cell around (px, py) by a square brush of side
-- `size` moved along the segment. The swept square is the bounding box of the
-- two end squares cut by the band around the segment, so the area follows from
-- clipping the cell once or twice.
function D.squareCoverage(px, py, x1, y1, x2, y2, size)
  local h = size / 2
  local ax, bx = math.max(px - 0.5, math.min(x1, x2) - h), math.min(px + 0.5, math.max(x1, x2) + h)
  local ay, by = math.max(py - 0.5, math.min(y1, y2) - h), math.min(py + 0.5, math.max(y1, y2) + h)
  if ax >= bx or ay >= by then
    return 0
  end
  local dx, dy = x2 - x1, y2 - y1
  local len = sqrt(dx * dx + dy * dy)
  if len < 1e-9 then
    return (bx - ax) * (by - ay)
  end
  local nx, ny = -dy / len, dx / len
  local k, c0 = h * (abs(nx) + abs(ny)), nx * x1 + ny * y1
  local lo, hi = math.huge, -math.huge
  for _, v in ipairs({ nx * ax + ny * ay, nx * bx + ny * ay, nx * bx + ny * by, nx * ax + ny * by }) do
    lo, hi = math.min(lo, v), math.max(hi, v)
  end
  if lo >= c0 - k and hi <= c0 + k then
    return (bx - ax) * (by - ay)
  end
  if hi <= c0 - k or lo >= c0 + k then
    return 0
  end
  local poly = { ax, ay, bx, ay, bx, by, ax, by }
  poly = clipPolygon(poly, nx, ny, c0 + k)
  if #poly >= 6 then
    poly = clipPolygon(poly, -nx, -ny, k - c0)
  end
  return clamp01(polygonArea(poly))
end

-- Area of the cell around (px, py) covered by a stroke of the given width (below one
-- cell) along the segment, 0..1: the cell cut by the band around the segment and by
-- the two end lines, half a width beyond the end points. On the center line of a long
-- stroke the value equals the width, a dot is a width x width square.
function D.bandCoverage(px, py, x1, y1, x2, y2, width)
  local h = width / 2
  if segmentDistance(px, py, x1, y1, x2, y2) > 1.42 * h + 0.71 then
    return 0
  end
  local dx, dy = x2 - x1, y2 - y1
  local len = sqrt(dx * dx + dy * dy)
  local ux, uy = 1, 0
  if len > 1e-9 then
    ux, uy = dx / len, dy / len
  else
    len = 0
  end
  local nx, ny = -uy, ux
  local c0, t0 = nx * x1 + ny * y1, ux * x1 + uy * y1
  local poly = { px - 0.5, py - 0.5, px + 0.5, py - 0.5, px + 0.5, py + 0.5, px - 0.5, py + 0.5 }
  for _, clip in ipairs({
    { nx, ny, c0 + h },
    { -nx, -ny, h - c0 },
    { ux, uy, t0 + len + h },
    { -ux, -uy, h - t0 },
  }) do
    poly = clipPolygon(poly, clip[1], clip[2], clip[3])
    if #poly < 6 then
      return 0
    end
  end
  return clamp01(polygonArea(poly))
end

-- Cell colors per (base, stroke color, coverage level), per palette.
local blendCache = setmetatable({}, { __mode = "k" })

local function blendMap(d)
  local c = blendCache[d]
  if not c or c.palette ~= d.palette then
    c = { palette = d.palette, map = {} }
    blendCache[d] = c
  end
  return c.map
end

-- Preview changesets must not grow the palette: their blended colors get
-- negative indices and live in ch.virtual (the view reads them from there).
local VIRTUAL_MAX = 4000

local function virtualColor(ch, key, r, g, b)
  local v = ch.virtual
  if not v then
    v = { n = 0, map = {} }
    ch.virtual = v
  end
  local idx = v.map[key]
  if not idx and v.n < VIRTUAL_MAX then
    v.n = v.n + 1
    v[v.n] = { floor(r + 0.5), floor(g + 0.5), floor(b + 0.5) }
    idx = -v.n
    v.map[key] = idx
  end
  return idx
end

-- Palette index of `color` painted over `base` at coverage `level` (0..AA_LEVELS).
local function blendIndex(d, ch, base, color, level)
  if level >= D.AA_LEVELS or base == color then
    return color
  end
  if level <= 0 then
    return base
  end
  local key = ((base - 1) * 256 + color - 1) * (D.AA_LEVELS + 1) + level
  local map = blendMap(d)
  local hit = map[key]
  if hit then
    return hit
  end
  local p, c, t = d.palette[base], d.palette[color], level / D.AA_LEVELS
  local r, g, b = p[1] + (c[1] - p[1]) * t, p[2] + (c[2] - p[2]) * t, p[3] + (c[3] - p[3]) * t
  local idx, dist = nearest(d, r, g, b)
  if dist > D.AA_REUSE and #d.palette < D.MAX_PALETTE then
    if ch.preview then
      return virtualColor(ch, key, r, g, b) or idx
    end
    idx = D.addColor(d, r, g, b, true)
  end
  map[key] = idx
  return idx
end

-- Paints `color` into cell i with coverage cov (0..1), keeping the strongest
-- coverage seen in this changeset and blending over the cell's color from
-- before the first touch.
local function shade(d, ch, i, color, cov)
  local level = floor(cov * D.AA_LEVELS + 0.5)
  if level <= 0 then
    return
  end
  local aa = ch.aa
  if not aa then
    aa = { level = {}, base = {} }
    ch.aa = aa
  end
  local prev = aa.level[i]
  if prev and prev >= level then
    return
  end
  aa.level[i] = level
  local base = aa.base[i]
  if not base then
    base = d.cells[i]
    aa.base[i] = base
  end
  put(d, ch, i, blendIndex(d, ch, base, color, level))
end

-- Calls fn(x, y) for every cell whose center lies within `reach` of the segment
-- (a superset, the caller computes the real coverage), walking along the longer
-- axis so a long line does not visit its whole bounding box.
local function sweep(d, x1, y1, x2, y2, reach, fn)
  local steep = abs(y2 - y1) > abs(x2 - x1)
  local a1, b1, a2, b2, amax, bmax = x1, y1, x2, y2, d.w, d.h
  if steep then
    a1, b1, a2, b2, amax, bmax = y1, x1, y2, x2, d.h, d.w
  end
  local da, db = a2 - a1, b2 - b1
  for a = math.max(1, math.ceil(math.min(a1, a2) - reach)), math.min(amax, floor(math.max(a1, a2) + reach)) do
    local blo, bhi = math.min(b1, b2), math.max(b1, b2)
    if da ~= 0 then
      local ta, tb = clamp01((a - reach - a1) / da), clamp01((a + reach - a1) / da)
      local ya, yb = b1 + db * ta, b1 + db * tb
      blo, bhi = math.min(ya, yb), math.max(ya, yb)
    end
    for b = math.max(1, math.ceil(blo - reach)), math.min(bmax, floor(bhi + reach)) do
      if steep then
        fn(b, a)
      else
        fn(a, b)
      end
    end
  end
end

-- Soft stroke from brush center (x1, y1) to (x2, y2). A one cell brush is a
-- round pen whatever its tip, so thin lines do not get fatter diagonally.
local function softLine(d, ch, x1, y1, x2, y2, color, size, shape)
  size = D.brushSize(size)
  if size < 1 then
    -- Sub-cell pen: true overlap area, brightened a little so thin dark lines stay visible.
    local w = d.w
    sweep(d, x1, y1, x2, y2, size + 0.5, function(x, y)
      local cov = D.bandCoverage(x, y, x1, y1, x2, y2, size)
      if cov >= D.THIN_MIN_COVERAGE then
        shade(d, ch, (y - 1) * w + x, color, cov ^ D.THIN_GAMMA)
      end
    end)
    return
  end
  local round = shape == "round" or size == 1
  local half = size / 2
  local w = d.w
  sweep(d, x1, y1, x2, y2, half + 0.5, function(x, y)
    local cov
    if round then
      cov = D.capsuleCoverage(x, y, x1, y1, x2, y2, half)
    else
      cov = D.squareCoverage(x, y, x1, y1, x2, y2, size)
    end
    if cov > 0 then
      shade(d, ch, (y - 1) * w + x, color, cov)
    end
  end)
end

-- Pencil, eraser, line ------------------------------------------------------------------

-- opts: x, y, color, size, shape, aa. With aa the position may be fractional
-- (cell centers are whole numbers) and the stroke is blended.
function D.pencil(d, o)
  local x, y, c = int(o.x), int(o.y), colorOf(d, o.color)
  if o.aa then
    x, y = num(o.x), num(o.y)
  end
  if not (x and y and c) then
    return nil, "args"
  end
  local ch = open(o)
  if o.aa then
    local off = D.brushOffset(o.size)
    softLine(d, ch, x + off, y + off, x + off, y + off, c, o.size, o.shape)
  else
    stamp(d, ch, x, y, c, mask(o.size, o.shape))
  end
  return finish(ch, o)
end

-- Same as the pencil with the background color.
function D.eraser(d, o)
  local copy = with(o, D.BACKGROUND)
  copy.size = wholeSize(o.size)
  return D.pencil(d, copy)
end

-- opts: x1, y1, x2, y2, color, size, shape, aa.
function D.line(d, o)
  local x1, y1, x2, y2, c = int(o.x1), int(o.y1), int(o.x2), int(o.y2), colorOf(d, o.color)
  if o.aa then
    x1, y1, x2, y2 = num(o.x1), num(o.y1), num(o.x2), num(o.y2)
  end
  if not (x1 and y1 and x2 and y2 and c) then
    return nil, "args"
  end
  local ch = open(o)
  if o.aa then
    local off = D.brushOffset(o.size)
    softLine(d, ch, x1 + off, y1 + off, x2 + off, y2 + off, c, o.size, o.shape)
  else
    drawLine(d, ch, x1, y1, x2, y2, c, mask(o.size, o.shape))
  end
  return finish(ch, o)
end

-- Shapes ----------------------------------------------------------------------------

local function fillColor(d, o)
  if o.fill == true then
    return o.color
  end
  return colorOf(d, o.fill)
end

-- opts: x1, y1, x2, y2, color, size, shape, aa, fill (true = solid in `color`, or
-- a palette index for the interior with the outline in `color`).
function D.rect(d, o)
  local x1, y1, x2, y2 = box(o)
  local c = colorOf(d, o.color)
  if not (x1 and c) then
    return nil, "args"
  end
  local ch, m = open(o), mask(o.size, o.shape)
  local fill = fillColor(d, o)
  if fill then
    fillBox(d, ch, x1, y1, x2, y2, fill)
  end
  if o.fill ~= true then
    local a, b, e, f = inset(x1, y1, x2, y2, m)
    local line = drawLine
    if o.aa then
      local off = D.brushOffset(o.size)
      line = function(dd, cc, lx1, ly1, lx2, ly2, color)
        softLine(dd, cc, lx1 + off, ly1 + off, lx2 + off, ly2 + off, color, o.size, o.shape)
      end
    end
    line(d, ch, a, b, e, b, c, m)
    line(d, ch, a, f, e, f, c, m)
    line(d, ch, a, b, a, f, c, m)
    line(d, ch, e, b, e, f, c, m)
  end
  return finish(ch, o)
end

-- Midpoint ellipse for any bounding box (even or odd sizes); calls fn(x, y)
-- for the outline cells, symmetric in all four quadrants.
local function ellipsePath(x1, y1, x2, y2, fn)
  local a, b = x2 - x1, y2 - y1
  local b1 = b % 2
  local dx, dy = 4 * (1 - a) * b * b, 4 * (b1 + 1) * a * a
  local err = dx + dy + b1 * a * a
  local xl, xr = x1, x2
  local yt = y1 + floor((b + 1) / 2)
  local yb = yt - b1
  local a8, b8 = 8 * a * a, 8 * b * b
  local top, bottom = yt, yb
  repeat
    fn(xr, yt)
    fn(xl, yt)
    fn(xl, yb)
    fn(xr, yb)
    top, bottom = math.max(top, yt), math.min(bottom, yb)
    local e2 = 2 * err
    if e2 <= dy then
      yt, yb = yt + 1, yb - 1
      dy = dy + a8
      err = err + dy
    end
    if e2 >= dx or 2 * err > dy then
      xl, xr = xl + 1, xr - 1
      dx = dx + b8
      err = err + dx
    end
  until xl > xr
  -- Narrow ellipses end before the tips: continue straight up and down.
  for y = top + 1, y2 do
    fn(xl - 1, y)
    fn(xr + 1, y)
  end
  for y = bottom - 1, y1, -1 do
    fn(xl - 1, y)
    fn(xr + 1, y)
  end
end

local function ellipseSpans(d, ch, x1, y1, x2, y2, color)
  local lo, hi = {}, {}
  ellipsePath(x1, y1, x2, y2, function(x, y)
    if not lo[y] or x < lo[y] then
      lo[y] = x
    end
    if not hi[y] or x > hi[y] then
      hi[y] = x
    end
  end)
  for y = y1, y2 do
    if lo[y] then
      for x = lo[y], hi[y] do
        plot(d, ch, x, y, color)
      end
    end
  end
end

-- Soft outline of the ellipse through the cell centers of the box a..e, b..f as
-- a polyline whose chords stay within about 0.04 cells of the curve.
local function softEllipse(d, ch, a, b, e, f, color, size, shape)
  local off = D.brushOffset(size)
  local cx, cy, rx, ry = (a + e) / 2 + off, (b + f) / 2 + off, (e - a) / 2, (f - b) / 2
  local big = math.max(rx, ry, 0.5)
  local n = math.max(16, math.ceil(math.pi / math.sqrt(0.08 / big)))
  -- An even count keeps the polyline mirror symmetric.
  n = n + n % 2
  local px, py = cx + rx, cy
  for k = 1, n do
    local t = 2 * math.pi * k / n
    local x, y = cx + rx * math.cos(t), cy + ry * math.sin(t)
    softLine(d, ch, px, py, x, y, color, size, shape)
    px, py = x, y
  end
end

-- opts as for rect.
function D.ellipse(d, o)
  local x1, y1, x2, y2 = box(o)
  local c = colorOf(d, o.color)
  if not (x1 and c) then
    return nil, "args"
  end
  local ch, m = open(o), mask(o.size, o.shape)
  if o.fill == true then
    ellipseSpans(d, ch, x1, y1, x2, y2, c)
  else
    local a, b, e, f = inset(x1, y1, x2, y2, m)
    local fill = fillColor(d, o)
    if fill then
      ellipseSpans(d, ch, a, b, e, f, fill)
    end
    if o.aa then
      softEllipse(d, ch, a, b, e, f, c, o.size, o.shape)
    else
      ellipsePath(a, b, e, f, function(x, y)
        stamp(d, ch, x, y, c, m)
      end)
    end
  end
  return finish(ch, o)
end

-- Fill, clear, invert ------------------------------------------------------------------

-- Scanline flood fill. opts: x, y, color, tolerance (percent of the largest
-- possible color distance, default 0 = exact match). With a tolerance every cell
-- within that distance of the clicked cell's color is filled, so the faint cells
-- of a soft outline do not stay behind as a halo; the filled cells get exactly
-- `color`. A little slack (3 of 441 distance units) lets a step of the soft-edge
-- levels count as inside its nominal percentage. Not previewable.
function D.fill(d, o)
  local x, y, c = int(o.x), int(o.y), colorOf(d, o.color)
  if not (x and y and c) or o.preview then
    return nil, o.preview and "no-preview" or "args"
  end
  local ch, w, h, cells = open(o), d.w, d.h, d.cells
  if x >= 1 and x <= w and y >= 1 and y <= h and cells[(y - 1) * w + x] ~= c then
    local target = cells[(y - 1) * w + x]
    local ok = { [target] = true }
    local tol = tonumber(o.tolerance)
    if tol and tol > 0 then
      local limit = math.min(tol, 100) / 100 * MAX_DISTANCE + 3
      for i, p in ipairs(d.palette) do
        if distance(p, d.palette[target]) <= limit then
          ok[i] = true
        end
      end
    end
    -- Filled cells are only tracked when the new color would match again.
    local seen = ok[c] and {} or nil
    local function hit(i)
      return ok[cells[i]] == true and not (seen and seen[i])
    end
    local stack, sp = { x, y }, 2
    local budget = w * h * 4
    while sp > 0 and budget > 0 do
      budget = budget - 1
      local sx, sy = stack[sp - 1], stack[sp]
      sp = sp - 2
      local row = (sy - 1) * w
      if hit(row + sx) then
        local l, r = sx, sx
        while l > 1 and hit(row + l - 1) do
          l = l - 1
        end
        while r < w and hit(row + r + 1) do
          r = r + 1
        end
        for xx = l, r do
          put(d, ch, row + xx, c)
          if seen then
            seen[row + xx] = true
          end
        end
        for ny = sy - 1, sy + 1, 2 do
          if ny >= 1 and ny <= h then
            local nrow, inRun = (ny - 1) * w, false
            for xx = l, r do
              if hit(nrow + xx) then
                if not inRun then
                  stack[sp + 1], stack[sp + 2] = xx, ny
                  sp = sp + 2
                  inRun = true
                end
              else
                inRun = false
              end
            end
          end
        end
      end
    end
  end
  return finish(ch, o)
end

-- opts: color (default background).
function D.clear(d, o)
  local c = colorOf(d, o.color or D.BACKGROUND)
  if not c then
    return nil, "args"
  end
  local ch = open(o)
  for i = 1, d.w * d.h do
    put(d, ch, i, c)
  end
  return finish(ch, o)
end

local function area(d, o)
  if o.x1 == nil then
    return 1, 1, d.w, d.h
  end
  local x1, y1, x2, y2 = box(o)
  if x1 then
    return math.max(x1, 1), math.max(y1, 1), math.min(x2, d.w), math.min(y2, d.h)
  end
end

-- Inverts the colors of the area (opts x1..y2, default all) by mapping every
-- used palette entry to its inverse, which is appended to the palette when it
-- is missing (nearest existing color when the palette is full). Added palette
-- entries are not part of undo. Not previewable.
function D.invert(d, o)
  local x1, y1, x2, y2 = area(d, o)
  if not x1 or o.preview then
    return nil, o.preview and "no-preview" or "args"
  end
  local ch, pal, map = open(o), d.palette, {}
  local function target(idx)
    local want = { 255 - pal[idx][1], 255 - pal[idx][2], 255 - pal[idx][3] }
    local best, bestDist = nil, math.huge
    for j, p in ipairs(pal) do
      local dist = (p[1] - want[1]) ^ 2 + (p[2] - want[2]) ^ 2 + (p[3] - want[3]) ^ 2
      if dist < bestDist then
        best, bestDist = j, dist
      end
    end
    if bestDist > 0 and #pal < D.MAX_PALETTE then
      return D.addColor(d, want[1], want[2], want[3], D.isAuto(d, idx))
    end
    return best
  end
  for y = y1, y2 do
    for x = x1, x2 do
      local i = (y - 1) * d.w + x
      local idx = d.cells[i]
      map[idx] = map[idx] or target(idx)
      put(d, ch, i, map[idx])
    end
  end
  return finish(ch, o)
end

-- Selection ---------------------------------------------------------------------------

-- Copy of the rectangle (clamped to the canvas) as { x, y, w, h, cells } or nil.
function D.copy(d, x1, y1, x2, y2)
  local a, b, c, e = area(d, { x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
  if not a or a > c or b > e then
    return nil
  end
  local clip = { x = a, y = b, w = c - a + 1, h = e - b + 1, cells = {} }
  local n = 0
  for y = b, e do
    for x = a, c do
      n = n + 1
      clip.cells[n] = d.cells[(y - 1) * d.w + x]
    end
  end
  return clip
end

local function pasteClip(d, ch, clip, x, y, transparent)
  local n = 0
  for cy = 0, clip.h - 1 do
    for cx = 0, clip.w - 1 do
      n = n + 1
      local v = clip.cells[n]
      if v <= #d.palette and not (transparent and v == D.BACKGROUND) then
        plot(d, ch, x + cx, y + cy, v)
      end
    end
  end
end

local function validClip(clip)
  return type(clip) == "table"
    and isInt(clip.w)
    and isInt(clip.h)
    and clip.w >= 1
    and clip.h >= 1
    and clip.w * clip.h <= D.MAX_CELLS
    and type(clip.cells) == "table"
    and clip.cells[clip.w * clip.h] ~= nil
end

-- opts: clip, x, y (top left, default the clip's origin), transparent (skip
-- background cells).
function D.paste(d, o)
  if not validClip(o.clip) then
    return nil, "args"
  end
  local x, y = int(o.x or o.clip.x), int(o.y or o.clip.y)
  if not (x and y) then
    return nil, "args"
  end
  local ch = open(o)
  pasteClip(d, ch, o.clip, x, y, o.transparent)
  return finish(ch, o)
end

-- opts: x1, y1, x2, y2, color (default background). Returns changeset, clip.
function D.cut(d, o)
  local x1, y1, x2, y2 = box(o)
  local c = colorOf(d, o.color or D.BACKGROUND)
  local clip = x1 and c and D.copy(d, x1, y1, x2, y2)
  if not clip then
    return nil, "args"
  end
  local ch = open(o)
  fillBox(d, ch, clip.x, clip.y, clip.x + clip.w - 1, clip.y + clip.h - 1, c)
  return finish(ch, o), clip
end

-- Moves the rectangle by dx, dy: clears the source, pastes at the target.
-- opts: x1, y1, x2, y2, dx, dy, transparent. Returns changeset, new rectangle.
function D.move(d, o)
  local x1, y1, x2, y2 = box(o)
  local dx, dy = int(o.dx), int(o.dy)
  local clip = x1 and dx and dy and D.copy(d, x1, y1, x2, y2)
  if not clip then
    return nil, "args"
  end
  local ch = open(o)
  fillBox(d, ch, clip.x, clip.y, clip.x + clip.w - 1, clip.y + clip.h - 1, D.BACKGROUND)
  pasteClip(d, ch, clip, clip.x + dx, clip.y + dy, o.transparent)
  local moved = { x1 = clip.x + dx, y1 = clip.y + dy, x2 = clip.x + dx + clip.w - 1, y2 = clip.y + dy + clip.h - 1 }
  return finish(ch, o), moved
end

local function flip(d, o, horizontal)
  local x1, y1, x2, y2 = area(d, o)
  local clip = x1 and D.copy(d, x1, y1, x2, y2)
  if not clip then
    return nil, "args"
  end
  local ch, n = open(o), 0
  for cy = 0, clip.h - 1 do
    for cx = 0, clip.w - 1 do
      n = n + 1
      local tx = horizontal and clip.w - 1 - cx or cx
      local ty = horizontal and cy or clip.h - 1 - cy
      plot(d, ch, clip.x + tx, clip.y + ty, clip.cells[n])
    end
  end
  return finish(ch, o)
end

-- opts: optional x1..y2 area (default the whole canvas).
function D.flipH(d, o)
  return flip(d, o, true)
end

function D.flipV(d, o)
  return flip(d, o, false)
end

-- Canvas size ---------------------------------------------------------------------------

-- Replaces the cells and the size in place (the table stays the same object).
local function setCells(d, w, h, cells)
  local old = d.w * d.h
  for i = 1, w * h do
    d.cells[i] = cells[i]
  end
  for i = w * h + 1, old do
    d.cells[i] = nil
  end
  d.w, d.h = w, h
end

-- The new canvas shows the old one from offset (ox, oy) on; cells beyond the old
-- canvas are background.
function D.reshape(d, ch)
  local cells, new, n = d.cells, {}, 0
  for y = 1, ch.nh do
    local sy = y + ch.oy
    for x = 1, ch.nw do
      local sx = x + ch.ox
      n = n + 1
      if sx >= 1 and sx <= ch.ow and sy >= 1 and sy <= ch.oh then
        new[n] = cells[(sy - 1) * ch.ow + sx]
      else
        new[n] = D.BACKGROUND
      end
    end
  end
  setCells(d, ch.nw, ch.nh, new)
end

-- Back to the old size: kept cells come from the current canvas, cropped-off
-- cells from ch.lost (row-major over the old canvas).
function D.unshape(d, ch)
  local cells, new, n, k = d.cells, {}, 0, 0
  for y = 1, ch.oh do
    local cy = y - ch.oy
    for x = 1, ch.ow do
      local cx = x - ch.ox
      n = n + 1
      if cx >= 1 and cx <= ch.nw and cy >= 1 and cy <= ch.nh then
        new[n] = cells[(cy - 1) * ch.nw + cx]
      else
        k = k + 1
        new[n] = ch.lost[k]
      end
    end
  end
  setCells(d, ch.ow, ch.oh, new)
end

local function dimension(v)
  v = tonumber(v)
  if not v or v ~= v then
    return D.MIN_DIM
  end
  return math.max(D.MIN_DIM, math.min(D.MAX_DIM, floor(v)))
end

-- Size forced into the limits. When the cell limit bites, `keep` ("w" or "h")
-- names the side that stays, the other one shrinks (default: keep the height).
-- Returns w, h, limited (true when the request had to change).
function D.clampDims(w, h, keep)
  local cw, ch = dimension(w), dimension(h)
  if cw * ch > D.MAX_CELLS then
    if keep == "w" then
      ch = floor(D.MAX_CELLS / cw)
    else
      cw = floor(D.MAX_CELLS / ch)
    end
  end
  return cw, ch, cw ~= w or ch ~= h
end

-- Changes the canvas size in place, anchored at the top left: a smaller size
-- crops the right and bottom, a larger one adds background. opts: ox, oy (the
-- new canvas starts at that offset into the old one, used by cropToSelection).
-- Returns the applied changeset or nil, "dims" | "args" | "same".
function D.resize(d, w, h, o)
  o = o or {}
  local ox, oy = o.ox or 0, o.oy or 0
  if not D.validDims(w, h) then
    return nil, "dims"
  end
  if not (isInt(ox) and isInt(oy)) then
    return nil, "args"
  end
  if w == d.w and h == d.h and ox == 0 and oy == 0 then
    return nil, "same"
  end
  local lost, n, cells = {}, 0, d.cells
  for y = 1, d.h do
    local cy = y - oy
    for x = 1, d.w do
      local cx = x - ox
      if not (cx >= 1 and cx <= w and cy >= 1 and cy <= h) then
        n = n + 1
        lost[n] = cells[(y - 1) * d.w + x]
      end
    end
  end
  local ch = { kind = "resize", n = n, ow = d.w, oh = d.h, nw = w, nh = h, ox = ox, oy = oy, lost = lost }
  D.reshape(d, ch)
  return ch
end

-- Paint's "crop": the canvas becomes the rectangle (clamped to the canvas), the
-- content inside stays. Selections below the minimum size are refused ("dims").
function D.cropToSelection(d, x1, y1, x2, y2)
  if x1 == nil then
    return nil, "args"
  end
  local a, b, c, e = area(d, { x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
  if not a or a > c or b > e then
    return nil, "args"
  end
  return D.resize(d, c - a + 1, e - b + 1, { ox = a - 1, oy = b - 1 })
end

-- Editor: undo/redo and strokes ----------------------------------------------------------

D.TOOLS = {
  pencil = true,
  eraser = true,
  line = true,
  rect = true,
  ellipse = true,
  fill = true,
  clear = true,
  invert = true,
  paste = true,
  cut = true,
  move = true,
  flipH = true,
  flipV = true,
}

local FREEHAND = { pencil = true, eraser = true }
local SHAPE = { line = true, rect = true, ellipse = true }

local Editor = {}
Editor.__index = Editor

-- Wraps a valid drawing (edited in place). Returns nil, reason otherwise.
function D.newEditor(drawing)
  local ok, why = D.validate(drawing)
  if not ok then
    return nil, why
  end
  return setmetatable(
    { drawing = drawing, undoStack = {}, redoStack = {}, size = 0, base = 0, saved = 0, seq = 0 },
    Editor
  )
end

function Editor:inAction()
  return self.action ~= nil
end

-- One action = one undo step. Returns false when one is already open.
function Editor:beginAction()
  if self.action then
    return false
  end
  self.action = { n = 0, cells = {}, old = {}, new = {}, pos = {}, preview = false }
  return true
end

local function trim(self)
  while #self.undoStack > D.MAX_UNDO or (self.size > D.UNDO_CELL_CAP and #self.undoStack > 1) do
    local oldest = table.remove(self.undoStack, 1)
    self.size = self.size - oldest.n
    self.base = oldest.id
  end
end

local function push(self, ch)
  self.seq = self.seq + 1
  ch.id = self.seq
  self.undoStack[#self.undoStack + 1] = ch
  self.size = self.size + ch.n
  self.redoStack = {}
  trim(self)
  return ch
end

-- Closes the action. Returns the changeset, or nil when nothing changed (then
-- no undo step exists).
function Editor:commitAction()
  local ch = self.action
  self.action = nil
  if not ch then
    return nil
  end
  D.compact(ch)
  if ch.n == 0 then
    return nil
  end
  return push(self, ch)
end

-- Rolls the open action back as if it never happened.
function Editor:cancelAction()
  local ch = self.action
  self.action, self.stroke = nil, nil
  if ch then
    D.revert(self.drawing, ch)
  end
  return ch ~= nil
end

-- "resize" (o.w, o.h) and "crop" (o.x1..y2) change the canvas size. They are
-- always their own undo step and cannot run inside an open action.
local function reshape(self, tool, o)
  if self.action then
    return nil, "busy"
  end
  local ch, why
  if tool == "crop" then
    ch, why = D.cropToSelection(self.drawing, o.x1, o.y1, o.x2, o.y2)
  else
    ch, why = D.resize(self.drawing, o.w, o.h)
  end
  if not ch then
    return nil, why
  end
  push(self, ch)
  return true
end

-- Runs one tool by name as an undo step (or inside the open action). Returns
-- true plus the tool's extra result (clip for "cut", new rectangle for "move"),
-- or nil, reason.
function Editor:run(tool, o)
  if tool == "resize" or tool == "crop" then
    return reshape(self, tool, o or {})
  end
  if not D.TOOLS[tool] then
    return nil, "tool"
  end
  o = o or {}
  local own = self:beginAction()
  local opts = with(o, o.color)
  opts.into, opts.preview = self.action, nil
  local ch, extra = D[tool](self.drawing, opts)
  if own then
    if ch then
      self:commitAction()
    else
      self:cancelAction()
    end
  end
  if not ch then
    return nil, extra
  end
  return true, extra
end

function Editor:canUndo()
  return self.action == nil and #self.undoStack > 0
end

function Editor:canRedo()
  return self.action == nil and #self.redoStack > 0
end

-- Returns the reverted changeset (cells to redraw) or nil.
function Editor:undo()
  if not self:canUndo() then
    return nil
  end
  local ch = table.remove(self.undoStack)
  self.size = self.size - ch.n
  D.revert(self.drawing, ch)
  self.redoStack[#self.redoStack + 1] = ch
  return ch
end

function Editor:redo()
  if not self:canRedo() then
    return nil
  end
  local ch = table.remove(self.redoStack)
  D.apply(self.drawing, ch)
  self.undoStack[#self.undoStack + 1] = ch
  self.size = self.size + ch.n
  trim(self)
  return ch
end

local function stateId(self)
  local top = self.undoStack[#self.undoStack]
  return top and top.id or self.base
end

function Editor:markSaved()
  self.saved = stateId(self)
end

-- False again after undoing back to the saved state.
function Editor:isModified()
  return stateId(self) ~= self.saved
end

-- Strokes ----------------------------------------------------------------------------

-- Freehand smoothing: the drawn point is the average of the last few mouse
-- samples (a convex combination, so it never leaves the samples' hull); the
-- path lags by about one sample and the release adds the missing last segment.
D.SMOOTH_WINDOW = 3

local function dirtyBox(d, x1, y1, x2, y2, pad)
  return {
    x1 = math.max(1, floor(math.min(x1, x2)) - pad),
    y1 = math.max(1, floor(math.min(y1, y2)) - pad),
    x2 = math.min(d.w, math.ceil(math.max(x1, x2)) + pad),
    y2 = math.min(d.h, math.ceil(math.max(y1, y2)) + pad),
  }
end

local function unite(a, b)
  if not a then
    return b
  end
  return { x1 = math.min(a.x1, b.x1), y1 = math.min(a.y1, b.y1), x2 = math.max(a.x2, b.x2), y2 = math.max(a.y2, b.y2) }
end

-- Starts a mouse drag. tool: "pencil" | "eraser" (freehand) or "line" | "rect"
-- | "ellipse" (shape from the first point to the current one). o: shape, fill,
-- aa (soft edges), smooth (freehand path smoothing). Soft or smoothed freehand
-- strokes take fractional positions in strokeTo.
function Editor:beginStroke(tool, color, size, o)
  o = o or {}
  if self.action or not (FREEHAND[tool] or SHAPE[tool]) or not colorOf(self.drawing, color) then
    return false
  end
  self:beginAction()
  self.stroke = {
    tool = tool,
    color = color,
    size = tool == "eraser" and wholeSize(size) or size,
    shape = o.shape,
    fill = o.fill,
    aa = o.aa == true,
    smooth = o.smooth == true and FREEHAND[tool] == true,
  }
  return true
end

local function shapeOpts(s, x, y)
  return {
    x1 = s.ax,
    y1 = s.ay,
    x2 = x,
    y2 = y,
    color = s.color,
    size = s.size,
    shape = s.shape,
    fill = s.fill,
    aa = s.aa,
  }
end

-- Draws the freehand segment from the last drawn point to (x, y); returns the
-- dirty rectangle.
local function freehandTo(self, s, x, y, pad)
  local d = self.drawing
  local fx, fy = s.dx or x, s.dy or y
  s.dx, s.dy = x, y
  local color = s.tool == "eraser" and D.BACKGROUND or s.color
  if s.aa then
    local off = D.brushOffset(s.size)
    softLine(d, self.action, fx + off, fy + off, x + off, y + off, color, s.size, s.shape)
  else
    -- Smoothed positions are fractional: the hard brush snaps to the nearest cell.
    D.line(d, {
      x1 = floor(fx + 0.5),
      y1 = floor(fy + 0.5),
      x2 = floor(x + 0.5),
      y2 = floor(y + 0.5),
      color = color,
      size = s.size,
      shape = s.shape,
      into = self.action,
    })
  end
  return dirtyBox(d, fx, fy, x, y, pad)
end

-- Feeds one mouse sample. Freehand tools draw a line from the previous sample,
-- so fast moves leave no gaps. Shape tools only update a preview. Returns the
-- dirty rectangle { x1, y1, x2, y2 } to redraw (nil without a stroke) and, for
-- shapes, the preview changeset (cells and new lists) to draw as an overlay.
function Editor:strokeTo(x, y)
  local s, d = self.stroke, self.drawing
  if not s then
    return nil
  end
  local fractional = FREEHAND[s.tool] and (s.aa or s.smooth)
  if fractional then
    x, y = num(x), num(y)
  else
    x, y = int(x), int(y)
  end
  if not (x and y) then
    return nil
  end
  local pad = mask(s.size, s.shape).size + (s.aa and 2 or 0)
  if FREEHAND[s.tool] then
    s.rx, s.ry = x, y
    if s.smooth then
      local hist = s.hist or {}
      s.hist = hist
      hist[#hist + 1] = { x, y }
      if #hist > D.SMOOTH_WINDOW then
        table.remove(hist, 1)
      end
      local sx, sy = 0, 0
      for _, p in ipairs(hist) do
        sx, sy = sx + p[1], sy + p[2]
      end
      x, y = sx / #hist, sy / #hist
    end
    return freehandTo(self, s, x, y, pad)
  end
  s.lx, s.ly = x, y
  s.ax, s.ay = s.ax or x, s.ay or y
  local o = shapeOpts(s, x, y)
  o.preview = true
  local preview = D[s.tool](d, o)
  local dirty = unite(s.dirty, dirtyBox(d, s.ax, s.ay, x, y, pad))
  s.dirty = dirtyBox(d, s.ax, s.ay, x, y, pad)
  return dirty, preview
end

-- Finishes the drag (optionally with a last sample) and commits one undo
-- step. Returns the committed changeset or nil when nothing changed.
function Editor:endStroke(x, y)
  local s = self.stroke
  if not s then
    return nil
  end
  if x ~= nil and y ~= nil then
    self:strokeTo(x, y)
  end
  if s.smooth and s.rx and (s.dx ~= s.rx or s.dy ~= s.ry) then
    freehandTo(self, s, s.rx, s.ry, 0)
  end
  if SHAPE[s.tool] and s.ax then
    local o = shapeOpts(s, s.lx or s.ax, s.ly or s.ay)
    o.into = self.action
    D[s.tool](self.drawing, o)
  end
  self.stroke = nil
  return self:commitAction()
end

function Editor:cancelStroke()
  return self:cancelAction()
end
