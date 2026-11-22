-- Walk path helpers, pure: the three walking styles (cost per ground class),
-- line-of-sight smoothing that never raises the cost, and a point limit for drawing. The grid itself stays in
-- NavRouter; what needs it (the cost of a straight line over cells) comes in as a function.
local _, ns = ...

local P = {}
ns.WalkPathLogic = P

-- Ground classes of the navigation data (docs/NAVGRID-FORMAT.md): the low bits of a node's kind byte.
P.CLASS = { NORMAL = 0, ROAD = 1, GENTLE = 2, STEEP = 3, INDOOR = 4, CITY = 5 }

-- Cost factor per class (index class + 1) for a step into a cell of that class. heur scales the search's distance
-- bound: the smallest factor itself would be exact but expands about twice as many cells, plain ground (1) hides
-- roads next to the direct line. Halfway keeps both in check.
P.STYLES = {
  fastest = { mult = { 1.0, 1.0, 1.0, 1.2, 2.0, 1.0 }, heur = 1.0 },
  balanced = { mult = { 1.0, 0.8, 1.3, 2.5, 2.0, 1.0 }, heur = 0.9 },
  roads = { mult = { 1.0, 0.5, 1.6, 4.0, 2.0, 1.0 }, heur = 0.75 },
}
P.DEFAULT_STYLE = "balanced"
P.ORDER = { "fastest", "balanced", "roads" }

-- A style name; anything unknown (nil, a damaged setting) is the default.
function P.Style(name)
  return P.STYLES[name] and name or P.DEFAULT_STYLE
end

-- The factor of a class in a style, 1 for a class past the table.
function P.Mult(style, class)
  return P.STYLES[P.Style(style)].mult[(class or 0) + 1] or 1
end

local sqrt, abs = math.sqrt, math.abs

-- Drops the cells in the middle of a straight run of steps (same direction): only the corners stay as candidates.
function P.Collapse(nodes)
  local n = #nodes
  if n < 3 then
    return nodes
  end
  local out = { nodes[1] }
  local dx, dy = nodes[2][1] - nodes[1][1], nodes[2][2] - nodes[1][2]
  for i = 2, n - 1 do
    local ndx, ndy = nodes[i + 1][1] - nodes[i][1], nodes[i + 1][2] - nodes[i][2]
    if ndx ~= dx or ndy ~= dy then
      out[#out + 1] = nodes[i]
      dx, dy = ndx, ndy
    end
  end
  out[#out + 1] = nodes[n]
  return out
end

-- The cells of the straight line between two cells, one step at a time (diagonal or orthogonal steps), calling
-- visit(fromX, fromY, toX, toY) for each step; stops and returns false as soon as visit returns false.
function P.Line(ax, ay, bx, by, visit)
  local dx, dy = abs(bx - ax), abs(by - ay)
  local sx, sy = ax < bx and 1 or -1, ay < by and 1 or -1
  local err = dx - dy
  local x, y = ax, ay
  while x ~= bx or y ~= by do
    local nx, ny = x, y
    local e2 = 2 * err
    if e2 > -dy then
      err = err - dy
      nx = x + sx
    end
    if e2 < dx then
      err = err + dx
      ny = y + sy
    end
    if visit(x, y, nx, ny) == false then
      return false
    end
    x, y = nx, ny
  end
  return true
end

-- Smoothing ------------------------------------------------------------------------------------------------------

-- String pulling: from each kept node the farthest later node whose straight line is open and costs no more than the
-- path between them (lineCost(ax, ay, bx, by) returns the cost, nil when closed). Roads therefore stay: a cut over
-- worse ground costs more and is refused. look limits how many nodes ahead are tried. tick() runs about every
-- TICK line tests, so a caller can hand control back (coroutine yield) between them.
P.LOOK = 40
P.TICK = 8

function P.Smooth(nodes, lineCost, tick, look)
  local n = #nodes
  if n < 3 then
    return nodes
  end
  look = look or P.LOOK
  local out, i, tests = { nodes[1] }, 1, 0
  while i < n do
    local best = i + 1
    for j = math.min(n, i + look), i + 2, -1 do
      tests = tests + 1
      if tick and tests % P.TICK == 0 then
        tick()
      end
      local a, b = nodes[i], nodes[j]
      local cost = lineCost(a[1], a[2], b[1], b[2])
      if cost and cost <= (b[3] - a[3]) * 1.0001 + 1e-9 then
        best = j
        break
      end
    end
    out[#out + 1] = nodes[best]
    i = best
  end
  return out
end

-- Point limit -------------------------------------------------------------------------------------------------------

local function distance(p, a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  local len2 = dx * dx + dy * dy
  if len2 == 0 then
    return sqrt((p.x - a.x) ^ 2 + (p.y - a.y) ^ 2)
  end
  return abs(dx * (a.y - p.y) - (a.x - p.x) * dy) / sqrt(len2)
end

local function douglasPeucker(pts, eps)
  local n = #pts
  local keep = { [1] = true, [n] = true }
  local stack = { { 1, n } }
  while #stack > 0 do
    local seg = table.remove(stack)
    local from, to = seg[1], seg[2]
    local far, at = 0, nil
    for i = from + 1, to - 1 do
      local d = distance(pts[i], pts[from], pts[to])
      if d > far then
        far, at = d, i
      end
    end
    if at and far > eps then
      keep[at] = true
      stack[#stack + 1] = { from, at }
      stack[#stack + 1] = { at, to }
    end
  end
  local out = {}
  for i = 1, n do
    if keep[i] then
      out[#out + 1] = pts[i]
    end
  end
  return out
end

-- At most max points ({ x, y, ... }): Douglas-Peucker with a growing tolerance (start eps, in yards).
function P.Simplify(pts, max, eps)
  local out = pts
  eps = eps or 1
  local rounds = 0
  while #out > max and rounds < 24 do
    out = douglasPeucker(pts, eps)
    eps = eps * 2
    rounds = rounds + 1
  end
  return out
end
