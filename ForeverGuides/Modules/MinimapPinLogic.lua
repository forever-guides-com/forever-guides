-- Pins on the real minimap, pure side (no frames, no client calls): the radius the minimap shows, the
-- projection of a spot (yards north and west of the player) to a place on the minimap, the world
-- position of a zone point, a grid that finds the points near the player without looking at the
-- whole zone, and the gate that says when the pins need a new layout. The frames are
-- Modules/MinimapLayer.lua. Map fractions are x east and y south on a north-up map; yards are
-- north (dN) and west (dW) of the player, so no assumption about the axes of the game's world is
-- needed: the axes of a map are measured through its corners (ZoneFrame).
local _, ns = ...

local ML = {}
ns.MinimapPinLogic = ML

-- Diameter in yards the minimap shows per zoom step 0 (all the way out) to 5, outdoors and indoors.
-- The radius is half. The client's own radius (C_Minimap.GetViewRadius) wins where it exists.
ML.ZOOM_OUTDOOR = { [0] = 466.67, 400, 333.33, 266.33, 200, 133.33 }
ML.ZOOM_INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

-- A pin is placed up to this share of the radius (the round mask cuts the border of the minimap).
ML.EDGE = 0.9
-- Pins up to this share of the radius are kept in "clamp" mode: they sit on the edge as a hint.
ML.CLAMP_REACH = 1.2
ML.EDGE_MODES = { clamp = true, hide = true }
ML.DEFAULT_EDGE_MODE = "clamp"

-- Layout gate: a new layout when the player moved this far (yards), turned this far (radians), or
-- after FULL_REFRESH seconds whatever happened.
ML.MOVE_EPS = 0.2
ML.TURN_EPS = 0.005
ML.FULL_REFRESH = 1

-- Edge of the grid cells in world yards.
ML.CELL = 100

-- Near range: spots up to this many yards from the player are drawn as a circle only (no symbol), so the
-- blip the game draws itself stays visible. 0 is off. Circle diameter and line width in px.
ML.NEAR_MIN, ML.NEAR_MAX, ML.NEAR_STEP, ML.NEAR_DEFAULT = 0, 200, 5, 60
ML.RING_SIZE_MIN, ML.RING_SIZE_MAX, ML.RING_SIZE_DEFAULT = 8, 40, 18
ML.RING_WIDTH_MIN, ML.RING_WIDTH_MAX, ML.RING_WIDTH_DEFAULT = 1, 4, 2

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end
ML.finite = finite

local function numbers(...)
  for i = 1, select("#", ...) do
    if not finite((select(i, ...))) then
      return false
    end
  end
  return true
end

local function hypot(a, b)
  return math.sqrt(a * a + b * b)
end

-- A number held between min and max, default for anything that is not a number.
function ML.Clamp(value, min, max, default)
  value = tonumber(value)
  if not value or value ~= value then
    return default
  end
  return math.max(min, math.min(max, value))
end

-- The stored near range in yards: bounded and rounded to the step, 0 stays 0 (off).
function ML.NearRange(value)
  local yards = ML.Clamp(value, ML.NEAR_MIN, ML.NEAR_MAX, ML.NEAR_DEFAULT)
  return math.floor(yards / ML.NEAR_STEP + 0.5) * ML.NEAR_STEP
end

-- How a spot at dist yards from the player is drawn for the near range: "ring" up to and including the
-- range, else "symbol". No range (0, nil, negative) or no distance means "symbol".
function ML.Style(dist, near)
  if finite(dist) and finite(near) and near > 0 and dist <= near + 1e-9 then
    return "ring"
  end
  return "symbol"
end

-- Radius ------------------------------------------------------------------------------------------

-- Yards from the center to the border of the minimap. viewRadius is what the client reports (nil when it
-- has no such call), else the table by zoom step and indoors. nil when neither says.
function ML.Radius(viewRadius, zoom, indoors)
  if finite(viewRadius) and viewRadius > 0 then
    return viewRadius
  end
  if not finite(zoom) then
    return nil
  end
  local diameter = (indoors == true and ML.ZOOM_INDOOR or ML.ZOOM_OUTDOOR)[math.floor(zoom)]
  return diameter and diameter / 2 or nil
end

-- The edge mode of a stored value ("clamp" or "hide"), the default for anything else.
function ML.EdgeMode(value)
  return ML.EDGE_MODES[value] and value or ML.DEFAULT_EDGE_MODE
end

-- Share of the radius up to which pins are kept for the mode: the edge itself for "hide", more for
-- "clamp" (those pins are pulled onto the edge).
function ML.Reach(mode, edge)
  edge = finite(edge) and edge > 0 and edge or ML.EDGE
  if ML.EdgeMode(mode) == "clamp" then
    return math.max(ML.CLAMP_REACH, edge)
  end
  return edge
end

-- Projection ---------------------------------------------------------------------------------------

-- Turns the offset (dN north, dW west, yards) by the facing of the player (radians, 0 = north,
-- counter-clockwise as GetPlayerFacing): returns how far ahead (up on the minimap) and how far to the
-- left the spot lies.
function ML.Rotate(dN, dW, facing)
  local c, s = math.cos(facing), math.sin(facing)
  return dN * c + dW * s, -dN * s + dW * c
end

-- Place of a spot on the minimap. p = {
--   dN, dW      yards north and west of the player
--   facing      radians, needed when rotate is true
--   rotate      the minimap turns with the player (CVar rotateMinimap): up is where the player looks,
--               else up is north
--   radius      yards from the center to the border
--   halfW, halfH  half the width and height of the minimap in its own units
--   edge        share of the radius where pins are pulled back to (default ML.EDGE)
--   reach       share of the radius up to which the spot is shown at all (default: edge)
-- }
-- Returns { x, y (offset from the center, y up), dist (yards), ratio (share of the radius), clamped (it
-- lay beyond the edge and was pulled back), visible }, or nil when the numbers do not allow a place
-- (no radius, no facing for a rotating minimap).
function ML.Project(p)
  if not (numbers(p.dN, p.dW, p.radius, p.halfW, p.halfH) and p.radius > 0) then
    return nil
  end
  local up, left = p.dN, p.dW
  if p.rotate then
    if not finite(p.facing) then
      return nil
    end
    up, left = ML.Rotate(p.dN, p.dW, p.facing)
  end
  local edge = finite(p.edge) and p.edge > 0 and p.edge or ML.EDGE
  local reach = finite(p.reach) and p.reach > 0 and p.reach or edge
  local dist = hypot(p.dN, p.dW)
  local ratio = dist / p.radius
  local clamped = ratio > edge + 1e-9
  local k = clamped and edge / ratio or 1
  return {
    x = -left / p.radius * p.halfW * k,
    y = up / p.radius * p.halfH * k,
    dist = dist,
    ratio = ratio,
    clamped = clamped,
    visible = ratio <= reach + 1e-9,
  }
end

-- World frame of a map ---------------------------------------------------------------------------

-- The map as a rectangle in world yards, from three corner samples. toWorld(mapId, x, y) returns
-- continent, worldX, worldY or nil (the client's conversion). Returns { map, cont, ox, oy (world of the
-- top left corner), exx, exy (world step for x 0 to 1), eyx, eyy (same for y), w, h (yards), ux, uy
-- (unit step to the east), vx, vy (unit step to the south), l, t, r, b (world bounding box) } or nil.
function ML.ZoneFrame(toWorld, mapId)
  local c0, ox, oy = toWorld(mapId, 0, 0)
  local c1, x1, y1 = toWorld(mapId, 1, 0)
  local c2, x2, y2 = toWorld(mapId, 0, 1)
  if c0 == nil or c0 ~= c1 or c0 ~= c2 or not numbers(ox, oy, x1, y1, x2, y2) then
    return nil
  end
  local exx, exy, eyx, eyy = x1 - ox, y1 - oy, x2 - ox, y2 - oy
  local w, h = hypot(exx, exy), hypot(eyx, eyy)
  if w <= 0 or h <= 0 then
    return nil
  end
  local x3, y3 = ox + exx + eyx, oy + exy + eyy
  return {
    map = mapId,
    cont = c0,
    ox = ox,
    oy = oy,
    exx = exx,
    exy = exy,
    eyx = eyx,
    eyy = eyy,
    w = w,
    h = h,
    ux = exx / w,
    uy = exy / w,
    vx = eyx / h,
    vy = eyy / h,
    l = math.min(ox, x1, x2, x3),
    r = math.max(ox, x1, x2, x3),
    t = math.min(oy, y1, y2, y3),
    b = math.max(oy, y1, y2, y3),
  }
end

-- World position of a map fraction (x east, y south).
function ML.WorldOf(frame, x, y)
  return frame.ox + x * frame.exx + y * frame.eyx, frame.oy + x * frame.exy + y * frame.eyy
end

-- Yards north and west of the player (at world wx0, wy0) for the world point wx, wy, measured with
-- the axes of the player's map.
function ML.Offset(frame, wx0, wy0, wx, wy)
  local dx, dy = wx - wx0, wy - wy0
  local east = dx * frame.ux + dy * frame.uy
  local south = dx * frame.vx + dy * frame.vy
  return -south, -east
end

-- True when the map lies on the continent and its box comes within reach yards of the world point.
function ML.Near(frame, cont, wx, wy, reach)
  return frame ~= nil
    and frame.cont == cont
    and wx + reach >= frame.l
    and wx - reach <= frame.r
    and wy + reach >= frame.t
    and wy - reach <= frame.b
end

-- Points of a zone in a grid ----------------------------------------------------------------------

local COLUMN = 100000

local function cellKey(cx, cy)
  return cx * COLUMN + cy
end

-- Sorts the points of a zone ({ x, y, itemId } as fractions of the zone map) into a grid of world
-- cells, with the world position worked out once. Returns { cont, cell, buckets, count }.
function ML.BuildIndex(points, frame, cell)
  cell = finite(cell) and cell > 0 and cell or ML.CELL
  local index = { cont = frame.cont, cell = cell, buckets = {}, count = 0 }
  for _, p in ipairs(points or {}) do
    if numbers(p.x, p.y) then
      local wx, wy = ML.WorldOf(frame, p.x, p.y)
      local key = cellKey(math.floor(wx / cell), math.floor(wy / cell))
      local bucket = index.buckets[key]
      if not bucket then
        bucket = {}
        index.buckets[key] = bucket
      end
      bucket[#bucket + 1] = { wx = wx, wy = wy, itemId = p.itemId, own = p.own }
      index.count = index.count + 1
    end
  end
  return index
end

-- The entries of the index inside the square of half edge `reach` yards around the world point, as a
-- new list. Only the cells the square touches are looked at.
function ML.Query(index, wx, wy, reach)
  local out = {}
  if not (index and numbers(wx, wy, reach) and reach >= 0) then
    return out
  end
  local cell = index.cell
  for cx = math.floor((wx - reach) / cell), math.floor((wx + reach) / cell) do
    for cy = math.floor((wy - reach) / cell), math.floor((wy + reach) / cell) do
      for _, e in ipairs(index.buckets[cellKey(cx, cy)] or {}) do
        if math.abs(e.wx - wx) <= reach and math.abs(e.wy - wy) <= reach then
          out[#out + 1] = e
        end
      end
    end
  end
  return out
end

-- Layout gate ---------------------------------------------------------------------------------------

local Gate = {}
Gate.__index = Gate

-- Fields compared with a tolerance; every other field of the state must stay equal.
local TOLERANCE = { wx = "MOVE_EPS", wy = "MOVE_EPS", facing = "TURN_EPS" }

function ML.NewGate()
  return setmetatable({}, Gate)
end

-- The next Check says yes whatever the state is (a switch, the filter or the data changed).
function Gate:Invalidate()
  self.state, self.at = nil, nil
end

-- True when the pins need a new layout for `state` (a flat table of numbers, booleans and strings): nothing
-- was laid out yet, a field changed (position and facing by more than their tolerance), or FULL_REFRESH
-- seconds passed since the last layout. Remembers the state when it says yes. now is in seconds.
function Gate:Check(now, state)
  local last = self.state
  local changed = last == nil or self.at == nil or now - self.at >= ML.FULL_REFRESH or now < self.at
  if not changed then
    for key, value in pairs(state) do
      local old = last[key]
      local eps = TOLERANCE[key]
      if eps and finite(value) and finite(old) then
        changed = math.abs(value - old) > ML[eps]
      else
        changed = value ~= old
      end
      if changed then
        break
      end
    end
    if not changed then
      for key in pairs(last) do
        if state[key] == nil then
          changed = true
          break
        end
      end
    end
  end
  if changed then
    local copy = {}
    for key, value in pairs(state) do
      copy[key] = value
    end
    self.state, self.at = copy, now
  end
  return changed
end
