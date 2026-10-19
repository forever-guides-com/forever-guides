-- Texture assets of the cursor ring (Media/Cursor): the list of
-- file stems, the path helper and the shape catalogue the settings page offers. Every file is white with
-- its shape in the alpha channel, so a texture is tinted with SetVertexColor.
--
-- A release only ships a Media file when a Lua file names its stem, so STEMS spells every stem out as a
-- literal; tests/test_cursorassets.lua keeps the list, the catalogue and the files on disk in step.
local _, ns = ...

local A = {}
ns.CursorAssets = A

local DIR = "Interface\\AddOns\\ForeverGuides\\Media\\Cursor\\"

A.STEMS = {
  "ring-circle-1",
  "ring-circle-2",
  "ring-circle-3",
  "ring-circle-4",
  "ring-circle-5",
  "ring-circle-6",
  "ring-circle-8",
  "ring-circle-10",
  "ring-circle-12",
  "ring-circle-16",
  "ring-circle-20",
  "ring-circle-26",
  "ring-circle-32",
  "ring-circle-40",
  "ring-circle-52",
  "ring-circle-64",
  "ring-square-1",
  "ring-square-2",
  "ring-square-3",
  "ring-square-4",
  "ring-square-5",
  "ring-square-6",
  "ring-square-8",
  "ring-square-10",
  "ring-square-12",
  "ring-square-16",
  "ring-square-20",
  "ring-square-26",
  "ring-square-32",
  "ring-square-40",
  "ring-square-52",
  "ring-square-64",
  "ring-rounded-1",
  "ring-rounded-2",
  "ring-rounded-3",
  "ring-rounded-4",
  "ring-rounded-5",
  "ring-rounded-6",
  "ring-rounded-8",
  "ring-rounded-10",
  "ring-rounded-12",
  "ring-rounded-16",
  "ring-rounded-20",
  "ring-rounded-26",
  "ring-rounded-32",
  "ring-rounded-40",
  "ring-rounded-52",
  "ring-rounded-64",
  "ring-diamond-1",
  "ring-diamond-2",
  "ring-diamond-3",
  "ring-diamond-4",
  "ring-diamond-5",
  "ring-diamond-6",
  "ring-diamond-8",
  "ring-diamond-10",
  "ring-diamond-12",
  "ring-diamond-16",
  "ring-diamond-20",
  "ring-diamond-26",
  "ring-diamond-32",
  "ring-diamond-40",
  "ring-diamond-52",
  "ring-diamond-64",
  "ring-hexagon-1",
  "ring-hexagon-2",
  "ring-hexagon-3",
  "ring-hexagon-4",
  "ring-hexagon-5",
  "ring-hexagon-6",
  "ring-hexagon-8",
  "ring-hexagon-10",
  "ring-hexagon-12",
  "ring-hexagon-16",
  "ring-hexagon-20",
  "ring-hexagon-26",
  "ring-hexagon-32",
  "ring-hexagon-40",
  "ring-hexagon-52",
  "ring-hexagon-64",
  "ring-triangle-1",
  "ring-triangle-2",
  "ring-triangle-3",
  "ring-triangle-4",
  "ring-triangle-5",
  "ring-triangle-6",
  "ring-triangle-8",
  "ring-triangle-10",
  "ring-triangle-12",
  "ring-triangle-16",
  "ring-triangle-20",
  "ring-triangle-26",
  "ring-triangle-32",
  "ring-triangle-40",
  "ring-triangle-52",
  "ring-triangle-64",
  "ring-star5-1",
  "ring-star5-2",
  "ring-star5-3",
  "ring-star5-4",
  "ring-star5-5",
  "ring-star5-6",
  "ring-star5-8",
  "ring-star5-10",
  "ring-star5-12",
  "ring-star5-16",
  "ring-star5-20",
  "ring-star5-26",
  "ring-star5-32",
  "ring-star5-40",
  "ring-star5-52",
  "ring-star5-64",
  "ring-star8-1",
  "ring-star8-2",
  "ring-star8-3",
  "ring-star8-4",
  "ring-star8-5",
  "ring-star8-6",
  "ring-star8-8",
  "ring-star8-10",
  "ring-star8-12",
  "ring-star8-16",
  "ring-star8-20",
  "ring-star8-26",
  "ring-star8-32",
  "ring-star8-40",
  "ring-star8-52",
  "ring-star8-64",
  "fill-circle",
  "fill-square",
  "fill-rounded",
  "fill-diamond",
  "fill-hexagon",
  "fill-triangle",
  "fill-star5",
  "fill-star8",
  "soft-dot",
  "soft-ring",
  "spark",
  "trail-dot",
  "trail-diamond",
  "trail-star4",
}

-- Size of the ring and fill textures in px and the strokes baked into the rings (px at that size, strictly
-- increasing, about 1.25 times the one before).
A.BAKED_SIZE = 256
A.STROKES = { 1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 26, 32, 40, 52, 64 }

-- Shapes: id, label key, ring strokes in px at 256 px. Every shape has a ring per stroke (ring-<id>-<px>)
-- and a filled twin (fill-<id>).
A.SHAPES = {
  { id = "circle", key = "cursor.shape.circle", strokes = A.STROKES },
  { id = "square", key = "cursor.shape.square", strokes = A.STROKES },
  { id = "rounded", key = "cursor.shape.rounded", strokes = A.STROKES },
  { id = "diamond", key = "cursor.shape.diamond", strokes = A.STROKES },
  { id = "hexagon", key = "cursor.shape.hexagon", strokes = A.STROKES },
  { id = "triangle", key = "cursor.shape.triangle", strokes = A.STROKES },
  { id = "star5", key = "cursor.shape.star5", strokes = A.STROKES },
  { id = "star8", key = "cursor.shape.star8", strokes = A.STROKES },
}

-- Glow and spark (128 px) and the small trail marks (64 px): stem, label key.
A.SOFT = {
  { id = "soft-dot", key = "cursor.shape.softDot" },
  { id = "soft-ring", key = "cursor.shape.softRing" },
  { id = "spark", key = "cursor.shape.spark" },
}
A.TRAIL = {
  { id = "trail-dot", key = "cursor.shape.trailDot" },
  { id = "trail-diamond", key = "cursor.shape.trailDiamond" },
  { id = "trail-star4", key = "cursor.shape.trailStar4" },
}

local known = {}
for _, stem in ipairs(A.STEMS) do
  known[stem] = true
end

function A.Has(stem)
  return known[stem] == true
end

-- Texture path of a stem; the only format is "png" (the default). nil for an unknown stem or format.
function A.Path(stem, format)
  if not known[stem] then
    return nil
  end
  format = format or "png"
  if format == "png" then
    return DIR .. stem .. "." .. format
  end
  return nil
end

-- Stem of a ring (stroke in px at 256 px) or of the filled twin (stroke nil); nil when the file does not exist.
function A.RingStem(shape, stroke)
  local stem = stroke and ("ring-" .. tostring(shape) .. "-" .. tostring(stroke)) or ("fill-" .. tostring(shape))
  return known[stem] and stem or nil
end

-- The ring stem whose baked stroke is closest to the wanted on-screen thickness (px) of an element that
-- is sizePx wide: the wanted stroke at 256 px is thickness / size * 256, compared on a log scale so a step
-- counts by its ratio, and clamped to the first and last step. nil for an unknown shape or a number that
-- is not finite.
function A.NearestStroke(shape, thickness, size)
  local function finite(v)
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge
  end
  if not (finite(thickness) and finite(size) and size > 0 and A.RingStem(shape)) then
    return nil
  end
  local first, last = A.STROKES[1], A.STROKES[#A.STROKES]
  local wanted = math.min(math.max(thickness / size * A.BAKED_SIZE, first), last)
  local best, bestGap
  for _, stroke in ipairs(A.STROKES) do
    local gap = math.abs(math.log(stroke) - math.log(wanted))
    if not bestGap or gap < bestGap then
      best, bestGap = stroke, gap
    end
  end
  return A.RingStem(shape, best)
end

ns.AddLocale("enUS", {
  ["cursor.shape.circle"] = "Circle",
  ["cursor.shape.square"] = "Square",
  ["cursor.shape.rounded"] = "Rounded square",
  ["cursor.shape.diamond"] = "Diamond",
  ["cursor.shape.hexagon"] = "Hexagon",
  ["cursor.shape.triangle"] = "Triangle",
  ["cursor.shape.star5"] = "Star (5 points)",
  ["cursor.shape.star8"] = "Star (8 points)",
  ["cursor.shape.softDot"] = "Soft dot",
  ["cursor.shape.softRing"] = "Soft ring",
  ["cursor.shape.spark"] = "Spark",
  ["cursor.shape.trailDot"] = "Dot",
  ["cursor.shape.trailDiamond"] = "Diamond",
  ["cursor.shape.trailStar4"] = "Star",
})
ns.AddLocale("deDE", {
  ["cursor.shape.circle"] = "Kreis",
  ["cursor.shape.square"] = "Quadrat",
  ["cursor.shape.rounded"] = "Abgerundetes Quadrat",
  ["cursor.shape.diamond"] = "Raute",
  ["cursor.shape.hexagon"] = "Sechseck",
  ["cursor.shape.triangle"] = "Dreieck",
  ["cursor.shape.star5"] = "Stern (5 Zacken)",
  ["cursor.shape.star8"] = "Stern (8 Zacken)",
  ["cursor.shape.softDot"] = "Weicher Punkt",
  ["cursor.shape.softRing"] = "Weicher Ring",
  ["cursor.shape.spark"] = "Funke",
  ["cursor.shape.trailDot"] = "Punkt",
  ["cursor.shape.trailDiamond"] = "Raute",
  ["cursor.shape.trailStar4"] = "Stern",
})
