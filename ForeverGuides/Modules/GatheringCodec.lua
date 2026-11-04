-- Point strings of the gathering data (docs/GATHERING-FORMAT.md): a point is four characters, two per
-- axis, in a 64 character alphabet (4096 steps per axis). The strings of ForeverGuides_Gathering and
-- the points the player tracks later use the same coding. Pure functions, no game access. Damaged
-- input never raises: a point with an unknown character is skipped, a short tail is ignored.
local _, ns = ...

local C = {}
ns.GatherCodec = C

C.ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
C.POINT_CHARS = 4
-- Highest value of one axis (64 * 64 - 1).
C.STEPS = 4095

local floor, byte, char = math.floor, string.byte, string.char

-- Byte of a character -> value 0..63.
local VALUE = {}
for index = 1, #C.ALPHABET do
  VALUE[byte(C.ALPHABET, index)] = index - 1
end

local function isNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function quantize(value)
  if value < 0 then
    value = 0
  elseif value > 1 then
    value = 1
  end
  return floor(value * C.STEPS + 0.5)
end

-- The points of a string as { { x, y }, ... }, x and y as fractions 0..1 of the map width and height.
function C.Decode(text)
  local points = {}
  if type(text) ~= "string" then
    return points
  end
  local steps = C.STEPS
  for start = 1, #text - (C.POINT_CHARS - 1), C.POINT_CHARS do
    local a, b, c, d = byte(text, start, start + 3)
    a, b, c, d = VALUE[a], VALUE[b], VALUE[c], VALUE[d]
    if a and b and c and d then
      points[#points + 1] = { (a * 64 + b) / steps, (c * 64 + d) / steps }
    end
  end
  return points
end

-- The string of a list { { x, y }, ... }: unique points, sorted by x, then y (the same order as the
-- generator writes). Entries that are not two finite numbers are dropped, values outside 0..1 are clamped.
function C.Encode(points)
  if type(points) ~= "table" then
    return ""
  end
  local seen, list = {}, {}
  for _, point in ipairs(points) do
    if type(point) == "table" and isNumber(point[1]) and isNumber(point[2]) then
      local x, y = quantize(point[1]), quantize(point[2])
      local key = x * 4096 + y
      if not seen[key] then
        seen[key] = true
        list[#list + 1] = key
      end
    end
  end
  table.sort(list)
  local out = {}
  for index, key in ipairs(list) do
    local x, y = floor(key / 4096), key % 4096
    out[index] = char(
      byte(C.ALPHABET, floor(x / 64) + 1),
      byte(C.ALPHABET, x % 64 + 1),
      byte(C.ALPHABET, floor(y / 64) + 1),
      byte(C.ALPHABET, y % 64 + 1)
    )
  end
  return table.concat(out)
end
