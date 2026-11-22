-- The planned walking path as a line on the real minimap. Pure part: Strokes turns world points into minimap pixels
-- (projection of MinimapPinLogic, the pattern and clipping of MapRouteStrokeLogic, the round border cut off).
-- Game part: one frame over the minimap with a pool of lines, redrawn about ten times a second and only while a plan
-- with a walking path is shown and the view (position, facing, zoom, plan) changed. Own frame only, nothing of the
-- client's is touched.
local _, ns = ...

local MR = {}
ns.MinimapRoute = MR

MR.INTERVAL = 0.1 -- seconds between two looks at the view
MR.GAP = 9 -- px around the player arrow that stay free
MR.MAX_LINES = 160 -- lines in the pool: the minimap is small, a long path is cut by the border
MR.TOKEN = "heading"

local sqrt, floor = math.sqrt, math.floor
local ML, SL = ns.MinimapPinLogic, ns.MapRouteStrokeLogic

-- The setting "routeMinimapLine" (default on).
function MR.Enabled()
  local s = ns.db and ns.db.settings
  return not s or s.routeMinimapLine ~= false
end

-- The parts of a segment (px around the minimap center, t from 0 to 1) inside the circle of radius outer and outside
-- the circle of radius inner: calls put(t0, t1) for each.
local function annulus(x1, y1, x2, y2, outer, inner, put)
  local dx, dy = x2 - x1, y2 - y1
  local a = dx * dx + dy * dy
  if a < 1e-9 then
    local d2 = x1 * x1 + y1 * y1
    if d2 <= outer * outer and d2 >= inner * inner then
      put(0, 1)
    end
    return
  end
  local b, c = x1 * dx + y1 * dy, x1 * x1 + y1 * y1
  local disc = b * b - a * (c - outer * outer)
  if disc <= 0 then
    return
  end
  local root = sqrt(disc)
  local lo, hi = math.max(0, (-b - root) / a), math.min(1, (-b + root) / a)
  if lo >= hi then
    return
  end
  local hole = b * b - a * (c - inner * inner)
  if hole > 0 then
    local h = sqrt(hole)
    local from, to = (-b - h) / a, (-b + h) / a
    if from > lo then
      put(lo, math.min(hi, from))
    end
    if to < hi then
      put(math.max(lo, to), hi)
    end
  else
    put(lo, hi)
  end
end

local scratch = SL.NewBuffer()

-- Draw segments in px from the top left of the minimap square into buf: the world points pts ({ x north, y west })
-- around the player view { wx, wy, facing, rotate, radius, halfW, halfH }. cfg: style, width, spacing (px). What lies
-- beyond the round border or inside the gap around the player arrow is cut off. Returns the stroke count.
function MR.Strokes(buf, pts, view, cfg, xs, ys)
  SL.Reset(buf)
  local n = #pts
  if n < 2 then
    return 0
  end
  local halfW, halfH, radius = view.halfW, view.halfH, view.radius
  local facing = view.rotate and view.facing or 0
  for i = 1, n do
    local p = pts[i]
    local ahead, left = ML.Rotate(p.x - view.wx, p.y - view.wy, facing)
    xs[i] = halfW - left / radius * halfW
    ys[i] = halfH - ahead / radius * halfH
  end
  SL.Reset(scratch)
  SL.Build(scratch, xs, ys, n, { 0, 0, 2 * halfW, 2 * halfH }, {
    style = cfg.style,
    width = cfg.width,
    spacing = cfg.spacing,
    budget = MR.MAX_LINES,
  })
  buf.thinned = scratch.thinned
  local outer = math.min(halfW, halfH)
  local kept = 0
  for k = 1, scratch.n do
    local x1, y1, x2, y2 = scratch.x1[k] - halfW, scratch.y1[k] - halfH, scratch.x2[k] - halfW, scratch.y2[k] - halfH
    annulus(x1, y1, x2, y2, outer, MR.GAP, function(t0, t1)
      kept = kept + 1
      buf.x1[kept], buf.y1[kept] = x1 + (x2 - x1) * t0 + halfW, y1 + (y2 - y1) * t0 + halfH
      buf.x2[kept], buf.y2[kept] = x1 + (x2 - x1) * t1 + halfW, y1 + (y2 - y1) * t1 + halfH
      buf.w[kept], buf.shadow[kept], buf.dot[kept] = scratch.w[k], scratch.shadow[k], scratch.dot[k]
    end)
  end
  buf.n = kept
  return kept
end

-- The walking paths of the plan on the continent: one flat list of { x, y } in walking order.
function MR.Path(steps, cont)
  local out = {}
  for _, step in ipairs(steps or {}) do
    local pts = step.mode == "walk" and step.pts
    if type(pts) == "table" and #pts >= 2 and step.pa and step.pa.cont == cont then
      for _, p in ipairs(pts) do
        out[#out + 1] = p
      end
    end
  end
  return out
end

-- A token that changes when the picture must change: position to a yard, facing to a degree, zoom, plan.
function MR.Signature(view, revision)
  return string.format(
    "%d:%d:%d:%d:%d:%d",
    floor(view.wx + 0.5),
    floor(view.wy + 0.5),
    floor((view.rotate and view.facing or 0) * 57.3 + 0.5),
    floor(view.radius + 0.5),
    floor(view.halfW + 0.5),
    revision
  )
end

-- Game part --------------------------------------------------------------------------------------------------------

local frame, lines, used, ticker
local buf, xs, ys = SL.NewBuffer(), {}, {}
local lastSignature, revision, path = nil, 0, nil

local function ensureFrame()
  if frame then
    return frame
  end
  local minimap = rawget(_G, "Minimap")
  if not (minimap and CreateFrame) then
    return nil
  end
  frame = CreateFrame("Frame", nil, minimap)
  frame:SetAllPoints(minimap)
  frame:SetFrameLevel((minimap:GetFrameLevel() or 0) + 4)
  frame:EnableMouse(false)
  lines = {}
  used = 0
  return frame
end

local function hideAll()
  for i = 1, used or 0 do
    lines[i]:Hide()
  end
  used = 0
  lastSignature = nil
end

local function paint(view)
  local host = ensureFrame()
  if not host or not host.CreateLine then
    return
  end
  local s = ns.db and ns.db.settings or {}
  local cfg = {
    style = SL.Style(s.routeLineStyle),
    width = math.max(1, SL.Width(s.routeLineWidth) - 1),
    spacing = SL.Spacing(s.routeDotSpacing) / 2,
  }
  local alpha = SL.Alpha(s.routeLineAlpha)
  MR.Strokes(buf, path, view, cfg, xs, ys)
  for k = 1, buf.n do
    local line = lines[k]
    if not line then
      line = host:CreateLine(nil, "OVERLAY", nil, buf.shadow[k] and 1 or 2)
      lines[k] = line
    end
    line:SetThickness(buf.w[k])
    if buf.shadow[k] then
      line:SetColorTexture(ns.Theme.color("bg", alpha * 0.7))
    else
      line:SetColorTexture(ns.Theme.color(MR.TOKEN, alpha))
    end
    line:SetStartPoint("TOPLEFT", host, buf.x1[k], -buf.y1[k])
    line:SetEndPoint("TOPLEFT", host, buf.x2[k], -buf.y2[k])
    line:Show()
  end
  for k = buf.n + 1, used or 0 do
    lines[k]:Hide()
  end
  used = buf.n
end

local function tick()
  local layer = ns.MinimapLayer
  local view = path and layer and layer.View and layer.View()
  if not view then
    hideAll()
    return
  end
  local sig = MR.Signature(view, revision)
  if sig == lastSignature then
    return
  end
  lastSignature = sig
  paint(view)
end

local function stop()
  if ticker then
    ticker:Cancel()
    ticker = nil
  end
  path = nil
  hideAll()
end

-- Follows the plan: the ticker runs only while a walking path on the minimap's continent exists.
function MR.Refresh()
  local plan = MR.Enabled() and ns.RoutePlan and ns.RoutePlan.Plan()
  local view = plan and ns.MinimapLayer and ns.MinimapLayer.View and ns.MinimapLayer.View()
  local walk = view and MR.Path(plan.steps, view.cont) or {}
  if #walk < 2 then
    stop()
    return
  end
  path = walk
  revision = revision + 1
  lastSignature = nil
  if not ticker and C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(MR.INTERVAL, tick)
  end
  tick()
end

function MR.Active()
  return ticker ~= nil
end

ns.On("FG_ROUTEPLAN_CHANGED", MR.Refresh)
ns.On("FG_SETTING_CHANGED", function(_, key)
  if
    type(key) == "string"
    and (key == "settings.routeMinimapLine" or key:find("^settings%.routeLine") or key:find("^settings%.routeDot"))
  then
    MR.Refresh()
  end
end)
ns.On("PLAYER_ENTERING_WORLD", MR.Refresh)
