-- Marker of the player on the map page, pure side (no frames): where the player stands on the shown view,
-- the arrow outline for a facing, the pixel position on the canvas, hit test and change detection. The
-- frames are in Modules/MapPlayerMarker.lua.
local _, ns = ...

local ML = {}
ns.MapPlayerMarkerLogic = ML

ML.INTERVAL = 0.1 -- seconds between two reads of the position
ML.ARROW = 22 -- px, tip to tail
ML.DOT = 12 -- px, the round fallback
ML.THICKNESS = 3 -- px, the bright line of the arrow
ML.EDGE = 3 -- px, extra thickness of the dark line under it
ML.HIT = 13 -- px, hover radius around the marker
ML.STEPS = 90 -- the facing is rounded to 1/90 of a turn, a finer change repaints nothing

local TURN = 2 * math.pi
local STEP = TURN / ML.STEPS

-- Corners of the arrow head for a facing of 0 (up), in units of the arrow size: tip, left, notch, right.
local HEAD = { { 0, 0.5 }, { -0.38, -0.5 }, { 0, -0.2 }, { 0.38, -0.5 } }
ML.CORNERS = #HEAD

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- The facing of the client (radians, 0 = north, counter-clockwise) rounded to a step and kept in 0..2pi;
-- nil when it is no readable number.
function ML.SnapFacing(facing)
  if not finite(facing) then
    return nil
  end
  local n = math.floor((facing % TURN) / STEP + 0.5)
  return (n % ML.STEPS) * STEP
end

-- Where the player stands on a view (a world layout, an island view or a zone view, see MapWorld.lua):
-- the point as fractions of the map and the slug of the zone. The zone is the one of the view whose game
-- map is `mapId`; a position the view does not show (another zone, an instance) answers nil.
function ML.Locate(view, mapId, x, y)
  local maps, zones = view and view.maps, view and view.zones
  if not (type(maps) == "table" and type(zones) == "table" and finite(mapId) and finite(x) and finite(y)) then
    return nil
  end
  local slug
  for s, id in pairs(maps) do
    if id == mapId and zones[s] and (slug == nil or s < slug) then
      slug = s
    end
  end
  if not slug then
    return nil
  end
  local nx, ny = ns.MapWorld.ZoneToPoint(view, slug, x, y)
  if nx then
    return nx, ny, slug
  end
end

-- A point of the map as canvas px (x right, y down); nil while the canvas has no size.
function ML.CanvasPoint(nx, ny, cw, ch)
  if not (finite(nx) and finite(ny) and finite(cw) and finite(ch) and cw > 0 and ch > 0) then
    return nil
  end
  return nx * cw, ny * ch
end

-- The corners of the arrow head for a facing, as offsets from the center (x right, y up), written into
-- `out` (a list that grows to four { x, y } pairs and is reused afterwards).
function ML.Outline(facing, size, out)
  local sin, cos = math.sin(facing), math.cos(facing)
  for i, c in ipairs(HEAD) do
    local p = out[i]
    if not p then
      p = { 0, 0 }
      out[i] = p
    end
    local x, y = c[1] * size, c[2] * size
    p[1], p[2] = x * cos - y * sin, x * sin + y * cos
  end
  return out
end

-- True when (x, y) lies within `radius` of (cx, cy).
function ML.Hit(x, y, cx, cy, radius)
  if not (finite(x) and finite(y) and finite(cx) and finite(cy)) then
    return false
  end
  local dx, dy = x - cx, y - cy
  return dx * dx + dy * dy <= radius * radius
end

-- Compares the state with the last one stored in `last` and stores it. True when something that shows
-- changed (position, facing, canvas size or zone), false when nothing did.
function ML.Changed(last, px, py, facing, cw, ch, slug)
  if
    last.px == px
    and last.py == py
    and last.facing == facing
    and last.cw == cw
    and last.ch == ch
    and last.slug == slug
  then
    return false
  end
  last.px, last.py, last.facing, last.cw, last.ch, last.slug = px, py, facing, cw, ch, slug
  return true
end
