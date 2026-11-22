-- Grid walk times and paths for the free-point legs of a planned route. The planner first uses a straight line
-- estimate (TravelLogic); Refine then asks ns.WalkLogic for the real walk of every estimated leg in the chosen
-- walking style (setting routeWalkStyle), one search after the other in slices, and calls back so the page plans
-- again with the results. Results are cached per pair and style for the session. Needs the data add-on, never
-- loads it in combat.
local _, ns = ...

local RW = {}
ns.RouteWalk = RW

local cache = {} -- key -> { sec, yards, pts } on foot, false = no grid result (estimate stays)
local active = {} -- handles of the running searches

-- The walking style of the settings: "fastest", "balanced" (default) or "roads".
function RW.Style()
  local s = ns.db and ns.db.settings
  return ns.WalkPathLogic.Style(s and s.routeWalkStyle)
end

local function key(a, b, style)
  local ax, ay, bx, by = math.floor(a.x + 0.5), math.floor(a.y + 0.5), math.floor(b.x + 0.5), math.floor(b.y + 0.5)
  if ax > bx or (ax == bx and ay > by) then
    ax, ay, bx, by = bx, by, ax, ay
  end
  return string.format("%s:%s:%d:%d:%d:%d", style or RW.Style(), tostring(a.cont), ax, ay, bx, by)
end

local function reversed(pts)
  local out = {}
  for i = #pts, 1, -1 do
    out[#out + 1] = pts[i]
  end
  return out
end

-- The grid time on foot of the walk between two { cont, x, y } positions in a style (the setting by default), nil
-- while unknown, then the path from a to b ({ { x, y, uiMap }, ... }, nil when the search gave none) and the yards.
-- Plugged into the planner as o.walkCost.
function RW.Cost(a, b, style)
  local hit = cache[key(a, b, style)]
  if not hit then
    return nil
  end
  local pts = hit.pts
  if pts and (math.floor(a.x + 0.5) ~= hit.fromX or math.floor(a.y + 0.5) ~= hit.fromY) then
    hit.back = hit.back or reversed(pts)
    pts = hit.back
  end
  return hit.sec, pts, hit.yards
end

-- The estimated point legs of the steps that still have no grid answer: { { key, a, b }, ... }.
function RW.Missing(steps)
  local out, seen = {}, {}
  for _, step in ipairs(steps or {}) do
    if step.pt and step.est and step.pa and step.pb and step.pa.cont == step.pb.cont then
      local k = key(step.pa, step.pb)
      if cache[k] == nil and not seen[k] then
        seen[k] = true
        out[#out + 1] = { key = k, a = step.pa, b = step.pb }
      end
    end
  end
  return out
end

function RW.Cancel()
  for _, h in ipairs(active) do
    h.Cancel()
  end
  active = {}
end

-- Searches the given pairs (from RW.Missing) one after the other, then calls onDone(count of grid
-- results). Pairs on a continent without loaded walk data are left out; returns false when nothing runs (onDone is
-- not called).
function RW.Refine(pairsList, onDone)
  local WL = ns.WalkLogic
  if not WL then
    return false
  end
  local ready = {}
  for _, item in ipairs(pairsList) do
    if WL.Ensure(item.a.cont) then
      ready[#ready + 1] = item
    end
  end
  pairsList = ready
  if #pairsList == 0 then
    return false
  end
  RW.Cancel()
  local at, found = 0, 0
  local function nextPair()
    at = at + 1
    local item = pairsList[at]
    if not item then
      active = {}
      ns.Safe("route-walk-done", onDone, found)
      return
    end
    local style = RW.Style()
    local h = WL.CostAsync(item.a.cont, item.a.x, item.a.y, item.b.x, item.b.y, function(sec, yards, source, _, pts)
      if source == "grid" and type(sec) == "number" then
        cache[item.key] = {
          sec = sec,
          yards = yards,
          pts = pts,
          fromX = math.floor(item.a.x + 0.5),
          fromY = math.floor(item.a.y + 0.5),
        }
        found = found + 1
      else
        cache[item.key] = false
      end
      nextPair()
    end, { style = style, path = true })
    active = { h }
  end
  nextPair()
  return true
end

-- Test seam.
function RW.Reset()
  RW.Cancel()
  cache = {}
end

-- A new style: plan again (the results of the old one stay cached under their own key).
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.routeWalkStyle" then
    RW.Cancel()
    if ns.RoutePlan then
      ns.RoutePlan.Replan()
    end
  end
end)
