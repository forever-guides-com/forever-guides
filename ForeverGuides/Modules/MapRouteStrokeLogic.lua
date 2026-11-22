-- Pure geometry of a drawn walking path: a polyline in canvas px becomes draw segments in a
-- reusable buffer. Styles: "line" (solid, shadow underneath, round joints at sharp bends), "dots"
-- (round dots at a fixed spacing) and "dash" (short dashes). The pattern phase runs on across
-- bends, only the visible rectangle is emitted, and a budget thins the result (fewer vertices for
-- a line, a larger spacing for dots and dashes) instead of cutting the path off. No frames here.
local _, ns = ...

local S = {}
ns.MapRouteStrokeLogic = S

S.STYLES = { "line", "dots", "dash" }
S.DEFAULT_STYLE = "line"
S.WIDTH_MIN, S.WIDTH_MAX, S.WIDTH_DEFAULT = 1, 8, 3
S.SPACING_MIN, S.SPACING_MAX, S.SPACING_DEFAULT = 5, 24, 9
S.ALPHA_MIN, S.ALPHA_MAX, S.ALPHA_DEFAULT = 0.3, 1, 0.9
S.BUDGET = 1500 -- strokes of one path; a full continent leg has about 200 vertices and 2500 px

local DASH_ON, DASH_OFF = 3.2, 2.2 -- dash and gap in widths
local JOINT_COS = 0.97 -- bends sharper than this get a round joint (line style)
local SHADOW_EXTRA = 2

local floor, ceil, sqrt, max, min = math.floor, math.ceil, math.sqrt, math.max, math.min

local function number(v, lo, hi, default)
  if type(v) ~= "number" or v ~= v then
    return default
  end
  return max(lo, min(hi, v))
end

function S.Style(v)
  for _, name in ipairs(S.STYLES) do
    if v == name then
      return v
    end
  end
  return S.DEFAULT_STYLE
end

function S.Width(v)
  return number(v, S.WIDTH_MIN, S.WIDTH_MAX, S.WIDTH_DEFAULT)
end

function S.Spacing(v)
  return number(v, S.SPACING_MIN, S.SPACING_MAX, S.SPACING_DEFAULT)
end

function S.Alpha(v)
  return number(v, S.ALPHA_MIN, S.ALPHA_MAX, S.ALPHA_DEFAULT)
end

-- A buffer of parallel arrays, reused for every build: x1, y1, x2, y2, w (px), shadow, dot.
function S.NewBuffer()
  return { n = 0, thinned = false, x1 = {}, y1 = {}, x2 = {}, y2 = {}, w = {}, shadow = {}, dot = {} }
end

function S.Reset(buf)
  buf.n, buf.thinned = 0, false
end

local function put(buf, x1, y1, x2, y2, w, shadow, dot)
  local n = buf.n + 1
  buf.n = n
  buf.x1[n], buf.y1[n], buf.x2[n], buf.y2[n] = x1, y1, x2, y2
  buf.w[n], buf.shadow[n], buf.dot[n] = w, shadow, dot
end

-- The part of the segment (0..1) inside the rectangle (Liang-Barsky); nil when it misses.
local function clip(ax, ay, bx, by, l, t, r, b)
  local dx, dy = bx - ax, by - ay
  local t0, t1 = 0, 1
  local function edge(p, q)
    if p == 0 then
      return q >= 0
    end
    local u = q / p
    if p < 0 then
      if u > t1 then
        return false
      end
      if u > t0 then
        t0 = u
      end
    else
      if u < t0 then
        return false
      end
      if u < t1 then
        t1 = u
      end
    end
    return true
  end
  if edge(-dx, ax - l) and edge(dx, r - ax) and edge(-dy, ay - t) and edge(dy, b - ay) then
    return t0, t1
  end
  return nil
end

-- Length of the path inside the rectangle, to size the thinning before anything is emitted.
local function visibleLength(xs, ys, n, rect)
  local sum = 0
  for i = 1, n - 1 do
    local t0, t1 = clip(xs[i], ys[i], xs[i + 1], ys[i + 1], rect[1], rect[2], rect[3], rect[4])
    if t0 then
      local dx, dy = xs[i + 1] - xs[i], ys[i + 1] - ys[i]
      sum = sum + sqrt(dx * dx + dy * dy) * (t1 - t0)
    end
  end
  return sum
end

local function emitLine(buf, xs, ys, n, rect, width, step, budget)
  local prevX, prevY, count = nil, nil, buf.n
  local l, t, r, b = rect[1], rect[2], rect[3], rect[4]
  local i = 1
  while i < n do
    local j = min(n, i + step)
    local ax, ay, bx, by = xs[i], ys[i], xs[j], ys[j]
    local t0, t1 = clip(ax, ay, bx, by, l, t, r, b)
    if t0 then
      local dx, dy = bx - ax, by - ay
      local x1, y1, x2, y2 = ax + dx * t0, ay + dy * t0, ax + dx * t1, ay + dy * t1
      if buf.n - count + 3 > budget then
        buf.thinned = true
        return
      end
      put(buf, x1, y1, x2, y2, width + SHADOW_EXTRA, true, false)
      put(buf, x1, y1, x2, y2, width, false, false)
      -- Round joint where the way turns sharply and the vertex itself is on the view.
      if prevX and t0 == 0 then
        local px, py = ax - prevX, ay - prevY
        local pl, cl = sqrt(px * px + py * py), sqrt(dx * dx + dy * dy)
        if pl > 0 and cl > 0 and (px * dx + py * dy) / (pl * cl) < JOINT_COS and buf.n - count + 2 <= budget then
          put(buf, ax - width * 0.45, ay, ax + width * 0.45, ay, width, false, true)
        end
      end
    end
    prevX, prevY = ax, ay
    i = j
  end
end

-- Dots or dashes along the path: `at` is the distance since the start of the pattern, carried over
-- every vertex, so nothing bunches up or restarts at a bend.
local function emitPattern(buf, xs, ys, n, rect, width, dots, spacing, budget)
  local l, t, r, b = rect[1], rect[2], rect[3], rect[4]
  local on = dots and 0 or width * DASH_ON * spacing
  local period = dots and spacing or on + width * DASH_OFF * spacing
  local start = buf.n
  local walked = 0
  for i = 1, n - 1 do
    local ax, ay, bx, by = xs[i], ys[i], xs[i + 1], ys[i + 1]
    local dx, dy = bx - ax, by - ay
    local len = sqrt(dx * dx + dy * dy)
    local t0, t1 = clip(ax, ay, bx, by, l, t, r, b)
    if t0 and len > 0 then
      local ux, uy = dx / len, dy / len
      local from, to = walked + len * t0, walked + len * t1
      local k = floor(from / period)
      while true do
        local p0 = k * period
        if p0 > to then
          break
        end
        if buf.n - start >= budget then
          buf.thinned = true
          return
        end
        if dots then
          if p0 >= from then
            local off = p0 - walked
            local x, y = ax + ux * off, ay + uy * off
            put(buf, x - ux * width * 0.45, y - uy * width * 0.45, x + ux * width * 0.45, y + uy * width * 0.45, width, false, true)
          end
        else
          local a, z = max(p0, from), min(p0 + on, to)
          if z - a > 0.25 then
            put(buf, ax + ux * (a - walked), ay + uy * (a - walked), ax + ux * (z - walked), ay + uy * (z - walked), width, false, false)
          end
        end
        k = k + 1
      end
    end
    walked = walked + len
  end
end

-- Appends the strokes of the polyline xs, ys (n points, canvas px, y down) to buf. rect = { left,
-- top, right, bottom } is the visible area. opts: style, width, spacing, budget (strokes this call
-- may add). Sets buf.thinned when the budget forced a coarser result. Returns the strokes added.
function S.Build(buf, xs, ys, n, rect, opts)
  opts = opts or {}
  local before = buf.n
  if n < 2 then
    return 0
  end
  local style = S.Style(opts.style)
  local width = S.Width(opts.width)
  local budget = opts.budget or S.BUDGET
  if style == "line" then
    local step = 1
    -- Two strokes per piece plus joints: keep every step-th vertex until it fits.
    local pieces = n - 1
    if pieces * 2.5 > budget then
      step = ceil(pieces * 2.5 / budget)
      buf.thinned = true
    end
    emitLine(buf, xs, ys, n, rect, width, step, budget)
  else
    local dots = style == "dots"
    local seen = visibleLength(xs, ys, n, rect)
    local pitch = dots and S.Spacing(opts.spacing) or width * (DASH_ON + DASH_OFF)
    local scale = dots and pitch or 1
    if seen / pitch > budget then
      -- Spread what fits over the whole path: a larger spacing, longer dashes.
      scale = dots and seen / budget or seen / (budget * pitch)
      buf.thinned = true
    end
    emitPattern(buf, xs, ys, n, rect, width, dots, scale, budget)
  end
  return buf.n - before
end
