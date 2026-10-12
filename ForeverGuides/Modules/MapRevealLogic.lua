-- Pure logic of the revealed zone map: turns the overlay pictures of a map (ForeverGuides_MapData,
-- docs/MAPOVERLAY-FORMAT.md) and the explored pieces of the client into draw commands in art
-- layer pixels, and scales them onto the canvas. No WoW API in this file.
local _, ns = ...

local R = {}
ns.MapRevealLogic = R

-- Edge of a full overlay tile in pixels, the files of the last row and column are cut to the
-- next power of two.
R.TILE = 256
local MIN_FILE = 16
-- Biggest overlay texture the client draws is far below this, a larger one is a broken entry.
local MAX_SIZE = 4096
-- Textures one zone map may use. The biggest zone of the data has 47 tiles.
R.MAX_PIECES = 128

-- File size (a power of two) that holds px pixels.
function R.FileSize(px)
  local size = MIN_FILE
  while size < px do
    size = size * 2
  end
  return size
end

-- Grid of a w x h texture: columns, rows, pixel width of the last column and pixel height of the
-- last row. A width of 315 gives two columns, the last one 59 px wide; 256 gives one full column.
function R.Grid(w, h)
  local cols, rows = math.ceil(w / R.TILE), math.ceil(h / R.TILE)
  return cols, rows, w - R.TILE * (cols - 1), h - R.TILE * (rows - 1)
end

local function inGrid(row, col, rows, cols)
  return type(row) == "number" and type(col) == "number" and row >= 0 and row < rows and col >= 0 and col < cols
end

local function size(v)
  return type(v) == "number" and v > 0 and v <= MAX_SIZE
end

-- Draw commands of one texture of w x h pixels placed at x, y of the art layer. tiles = list of
-- { row, col, fileId } (0-based). A command is { id, x, y, w, h, u, v }: w, h the covered pixels,
-- u, v the used part of the file (texture coordinates 0..1 from the top left). Tiles outside the
-- grid and without a file id are left out.
function R.Cut(w, h, x, y, tiles)
  local out = {}
  if not (size(w) and size(h) and type(tiles) == "table") then
    return out
  end
  x, y = tonumber(x) or 0, tonumber(y) or 0
  local cols, rows, lastW, lastH = R.Grid(w, h)
  for _, t in ipairs(tiles) do
    local row, col, id
    if type(t) == "table" then
      row, col, id = t[1], t[2], t[3]
    end
    if inGrid(row, col, rows, cols) and type(id) == "number" and id > 0 then
      local pw, ph = col < cols - 1 and R.TILE or lastW, row < rows - 1 and R.TILE or lastH
      out[#out + 1] = {
        id = id,
        x = x + R.TILE * col,
        y = y + R.TILE * row,
        w = pw,
        h = ph,
        u = pw / R.FileSize(pw),
        v = ph / R.FileSize(ph),
      }
    end
  end
  return out
end

-- Draw commands of all overlays of one map, in list order (the later ones lie on top). overlays =
-- list of { w, h, x, y, t = { { row, col, fileId } } }. At most `cap` commands (default
-- R.MAX_PIECES); the second result says how many were left out.
function R.Pieces(overlays, cap)
  cap = cap or R.MAX_PIECES
  local out, dropped = {}, 0
  for _, o in ipairs(type(overlays) == "table" and overlays or {}) do
    if type(o) == "table" then
      for _, piece in ipairs(R.Cut(o.w, o.h, o.x, o.y, o.t)) do
        if #out < cap then
          out[#out + 1] = piece
        else
          dropped = dropped + 1
        end
      end
    end
  end
  return out, dropped
end

-- Position and size of a command on a canvas that shows the whole art layer stretched to its
-- size: left, top (from the canvas top left, y down), width, height in canvas pixels.
function R.Place(piece, layerW, layerH, canvasW, canvasH)
  local sx, sy = canvasW / layerW, canvasH / layerH
  return piece.x * sx, piece.y * sy, piece.w * sx, piece.h * sy
end

-- Largest rectangle of the layer's aspect that fits into a canvas, centered: x, y, w, h in canvas
-- pixels. Lets a map sit undistorted on a canvas of another aspect (the drawing sheet).
function R.Fit(layerW, layerH, canvasW, canvasH)
  if not (layerW > 0 and layerH > 0 and canvasW > 0 and canvasH > 0) then
    return 0, 0, 0, 0
  end
  local s = math.min(canvasW / layerW, canvasH / layerH)
  local w, h = layerW * s, layerH * s
  return (canvasW - w) / 2, (canvasH - h) / 2, w, h
end
