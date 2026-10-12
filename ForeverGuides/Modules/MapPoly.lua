-- Zone outlines of the world map: point in polygon and outline sampling. Pure Lua without WoW API.
-- A zone's poly is a list of rings, each a flat list x1, y1, x2, y2, ... as fractions of the
-- zone rectangle (pc = "canvas": of the whole map). Rings are not closed and may reach a little
-- outside 0..1 on purpose, so nothing is clamped.
local _, ns = ...

local MP = {}
ns.MapPoly = MP

local EPS = 1e-9

-- Edge tests since the last reset, for the per-tick budget test.
MP.edgeTests = 0

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- One ring from a flat list, projected by place(px, py); nil unless it has 3 finite points.
local function buildRing(flat, place)
  local n = type(flat) == "table" and #flat or 0
  if n < 6 or n % 2 ~= 0 then
    return nil
  end
  local p, out = {}, 0
  local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
  local area = 0
  for i = 1, n, 2 do
    local px, py = flat[i], flat[i + 1]
    if not (finite(px) and finite(py)) then
      return nil
    end
    if px < 0 or px > 1 or py < 0 or py > 1 then
      out = out + 1
    end
    local x, y = place(px, py)
    p[#p + 1], p[#p + 2] = x, y
    minx, maxx = math.min(minx, x), math.max(maxx, x)
    miny, maxy = math.min(miny, y), math.max(maxy, y)
  end
  local count = n / 2
  local cx, cy = 0, 0
  for i = 1, count do
    local j = i % count + 1
    local xi, yi, xj, yj = p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j]
    local cross = xi * yj - xj * yi
    area = area + cross
    cx, cy = cx + (xi + xj) * cross, cy + (yi + yj) * cross
  end
  return {
    p = p,
    n = count,
    out = out,
    minx = minx,
    maxx = maxx,
    miny = miny,
    maxy = maxy,
    area = math.abs(area) / 2,
    cx = area ~= 0 and cx / (3 * area) or nil,
    cy = area ~= 0 and cy / (3 * area) or nil,
  }
end

-- The shape of a zone: rings projected into map fractions. rect (left, right, top, bottom) is the
-- zone's rectangle on the map, unused when canvas is true. nil when there is nothing to draw
-- (no valid ring, or no rectangle for a zone-relative poly).
function MP.Build(poly, canvas, rect)
  if type(poly) ~= "table" or not (canvas or type(rect) == "table") then
    return nil
  end
  local place
  if canvas then
    place = function(px, py)
      return px, py
    end
  else
    local w, h = rect.right - rect.left, rect.bottom - rect.top
    place = function(px, py)
      return rect.left + px * w, rect.top + py * h
    end
  end
  local shape = { rings = {}, area = 0, points = 0, out = 0 }
  local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
  local best
  for _, flat in ipairs(poly) do
    local ring = buildRing(flat, place)
    if ring then
      shape.rings[#shape.rings + 1] = ring
      shape.area = shape.area + ring.area
      shape.points = shape.points + ring.n
      shape.out = shape.out + ring.out
      minx, maxx = math.min(minx, ring.minx), math.max(maxx, ring.maxx)
      miny, maxy = math.min(miny, ring.miny), math.max(maxy, ring.maxy)
      if ring.cx and (not best or ring.area > best.area) then
        best = ring
      end
    end
  end
  if #shape.rings == 0 then
    return nil
  end
  shape.minx, shape.maxx, shape.miny, shape.maxy = minx, maxx, miny, maxy
  shape.ax, shape.ay = best and best.cx, best and best.cy
  return shape
end

-- Ray casting; a point on an edge or a corner counts as inside.
local function inRing(ring, x, y)
  local p, n = ring.p, ring.n
  local inside = false
  local j = n
  for i = 1, n do
    local xi, yi, xj, yj = p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j]
    if (yi > y) ~= (yj > y) then
      local xc = xi + (y - yi) * (xj - xi) / (yj - yi)
      if math.abs(x - xc) <= EPS then
        MP.edgeTests = MP.edgeTests + i
        return true
      end
      if x < xc then
        inside = not inside
      end
    elseif yi == y and yj == y and x >= math.min(xi, xj) - EPS and x <= math.max(xi, xj) + EPS then
      MP.edgeTests = MP.edgeTests + i
      return true
    end
    j = i
  end
  MP.edgeTests = MP.edgeTests + n
  return inside
end

-- True when the point lies in any ring of the shape; the bounding boxes skip most rings.
function MP.Contains(shape, x, y)
  if not (shape and x >= shape.minx and x <= shape.maxx and y >= shape.miny and y <= shape.maxy) then
    return false
  end
  for _, ring in ipairs(shape.rings) do
    if x >= ring.minx and x <= ring.maxx and y >= ring.miny and y <= ring.maxy and inRing(ring, x, y) then
      return true
    end
  end
  return false
end

-- A point that lies inside the shape: the centroid of the largest ring, else the box centre; nil
-- when neither hits.
function MP.Anchor(shape)
  if not shape then
    return nil
  end
  local saved = MP.edgeTests
  local x, y = shape.ax, shape.ay
  if not (x and MP.Contains(shape, x, y)) then
    x, y = (shape.minx + shape.maxx) / 2, (shape.miny + shape.maxy) / 2
    if not MP.Contains(shape, x, y) then
      x, y = nil, nil
    end
  end
  MP.edgeTests = saved
  return x, y
end

-- Closed outline rings with at most maxSegments segments in total, vertices thinned evenly.
-- Returns a list of flat lists in map fractions.
function MP.Outline(shape, maxSegments)
  local out = {}
  if not shape then
    return out
  end
  for _, ring in ipairs(shape.rings) do
    local keep = ring.n
    if shape.points > maxSegments then
      keep = math.min(ring.n, math.max(3, math.floor(maxSegments * ring.n / shape.points)))
    end
    local flat = {}
    for k = 1, keep do
      local i = math.floor((k - 1) * ring.n / keep) + 1
      flat[#flat + 1], flat[#flat + 2] = ring.p[2 * i - 1], ring.p[2 * i]
    end
    out[#out + 1] = flat
  end
  return out
end

-- Shapes of a view, built on first use. view.polySrc[slug] = { poly, canvas, rect }; only zones
-- the view also shows as a rectangle count. Returns { order, has, count } with order sorted by
-- area (then slug), or nil when the view has no polygons.
function MP.Index(view)
  if not view then
    return nil
  end
  if view.polyIndex ~= nil then
    return view.polyIndex or nil
  end
  local shapes, order, has = {}, {}, {}
  for slug, src in pairs(view.polySrc or {}) do
    local shape = view.zones and view.zones[slug] and MP.Build(src.poly, src.canvas, src.rect)
    if shape then
      shape.slug = slug
      shapes[slug] = shape
      order[#order + 1] = shape
      has[slug] = true
    end
  end
  table.sort(order, function(a, b)
    if a.area ~= b.area then
      return a.area < b.area
    end
    return a.slug < b.slug
  end)
  view.polyIndex = #order > 0 and { order = order, shapes = shapes, has = has, count = #order } or false
  return view.polyIndex or nil
end

-- The shape of one zone in a view, nil for zones without a polygon.
function MP.Shape(view, slug)
  local idx = MP.Index(view)
  return idx and idx.shapes[slug]
end

-- Self check of an index: points reaching outside 0..1 and zones whose anchor point misses.
function MP.Check(idx)
  local r = { zones = idx.count, points = 0, outside = 0, misses = {} }
  for _, shape in ipairs(idx.order) do
    r.points, r.outside = r.points + shape.points, r.outside + shape.out
    if not MP.Anchor(shape) then
      r.misses[#r.misses + 1] = shape.slug
    end
  end
  table.sort(r.misses)
  return r
end
