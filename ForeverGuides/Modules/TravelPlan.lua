-- Trip planner on top of TravelLogic: free points and places as start, stops and goal, an optional
-- optimized order, an optional return to the start, a clear error per stop that cannot be reached,
-- and the legs, steps and guidance targets a UI or a journey needs. Pure logic without WoW API:
-- the caller hands in the player position as the start and o.worldPos (see TravelLogic) for points.
--
--   TP.Plan(data, o, req) -> plan
--   req = {
--     start = point,           -- the player position or any place
--     stops = { point, ... },  -- up to TL.MAX_STOPS, more are reported as errors
--     goal = point,            -- optional with returnToStart (then the start is the goal)
--     optimize = bool,         -- reorder the stops (the goal stays last), default: order as given
--     returnToStart = bool,    -- one more leg from the goal back to the start
--   }
--   point = place slug | { map = uiMapId, x = 0..1, y = 0..1 } | free point slug "@map_x_y"
--   plan = {
--     status = "ok" | "same" | "unreachable",
--     legs = { { index, from, to, role = "stop"|"goal"|"return", stop = request stop number or nil,
--                steps = { edge... }, sec, waitSec, est, first, last } },
--     steps = every edge in order, edge = { from, to, mode = walk|flight|boat|zeppelin|tram|portal|
--             lift|spell|teleport, sec, wait, per, ... },
--     targets = TP.Targets(...) (the places the arrow points to, in order),
--     totalSec, waitSec,       -- total trip time and the part of it spent waiting for rides
--     order = { request stop numbers in the order visited },
--     optimized, saved,        -- saved seconds against the given order (optimize only)
--     best,                    -- the best route as TravelLogic.RouteVia returns it (steps, parts)
--     alternatives,            -- whole routes without one transport, as TravelLogic.RouteVia
--     errors = { { stop = request stop number or nil, slug, reason = "unknown"|"invalid"|"unreachable"|
--                  "toomany"|"goal" } },
--     list,                    -- places in the order used, start first
--   }
-- A stop at the very place of the point before it has no leg. A stop that cannot be reached is
-- dropped with an error and the rest is still planned. When the way to a stop breaks off at its
-- goal, the stop before it takes the blame (the goal is assumed reachable).
local _, ns = ...
local TL = ns.TravelLogic

local TP = {}
ns.TravelPlan = TP

-- A request point as a slug, or nil and a reason.
local function toSlug(data, o, point)
  if type(point) == "table" then
    if point.s then
      point = point.s
    elseif type(point.map) == "number" and type(point.x) == "number" and type(point.y) == "number" then
      if point.map < 1 or point.x < 0 or point.x > 1 or point.y < 0 or point.y > 1 then
        return nil, "invalid"
      end
      return TL.PointSlug(point.map, point.x, point.y)
    else
      return nil, "invalid"
    end
  end
  if type(point) ~= "string" then
    return nil, "invalid"
  end
  if TL.IsPoint(point) then
    return TL.ParsePoint(point) and point or nil, "invalid"
  end
  for _, n in ipairs(data.nodes) do
    if n.s == point then
      return TL.NodeVisible(n, o) and point or nil, "unknown"
    end
  end
  for _, n in ipairs(data.via or {}) do
    if n.s == point then
      return point
    end
  end
  return nil, "unknown"
end

-- { map, x, y } (UiMap fractions) of a place or free point, nil for stations without a map position.
function TP.PositionOf(data, slug)
  if TL.IsPoint(slug) then
    local p = TL.ParsePoint(slug)
    return p and { map = p.map, x = p.x, y = p.y } or nil
  end
  for _, n in ipairs(data.nodes) do
    if n.s == slug then
      if type(n.um) == "number" and type(n.ux) == "number" and type(n.uy) == "number" then
        return { map = n.um, x = n.ux, y = n.uy }
      end
      return nil
    end
  end
  return nil
end

-- The places the arrow points to, one after the other. A walk step ends in a "walk" target, the
-- start of a ride is a "board" target (flight master, dock, portal, lift; it merges with the walk
-- that ends there), a ride that ends a leg adds an "arrive" target. Each target:
--   { slug, pos, kind, mode (of the ride after a "board"), rides (steps of that ride), hearth, leg,
--     step, stop, goal }
-- step is the number of the step in plan.steps that this target leads to. rides counts the steps of
-- one taxi trip (flight after flight is one trip, every other ride is its own). stop is set where a
-- leg ends at a stop, goal where it ends at the goal or the way back.
function TP.Targets(data, legs)
  local targets = {}
  local function add(t)
    t.pos = TP.PositionOf(data, t.slug)
    targets[#targets + 1] = t
    return t
  end
  for _, leg in ipairs(legs) do
    local prev, board
    for k, e in ipairs(leg.steps) do
      local at = leg.first + k - 1
      if e.mode == "walk" then
        add({ slug = e.to, kind = "walk", leg = leg.index, step = at })
      elseif prev and prev.mode == "flight" and e.mode == "flight" and prev.to == e.from then
        board.rides = board.rides + 1
      else
        local last = targets[#targets]
        if last and last.slug == e.from and last.kind == "walk" and last.leg == leg.index then
          board = last
          board.step = at
        else
          board = add({ slug = e.from, leg = leg.index, step = at })
        end
        board.kind, board.mode, board.rides, board.hearth = "board", e.mode, 1, e.hearth
      end
      prev = e
    end
    local end_ = targets[#targets]
    local lastStep = leg.steps[#leg.steps]
    if lastStep and lastStep.mode ~= "walk" then
      end_ = add({ slug = lastStep.to, kind = "arrive", leg = leg.index, step = leg.last })
    end
    if end_ then
      end_.stop = leg.stop
      end_.goal = leg.role ~= "stop" or nil
    end
  end
  return targets
end

local function legsOf(best, plan)
  local legs = {}
  for i, part in ipairs(best.parts) do
    local steps, wait = {}, 0
    for s = part.first, part.last do
      local e = best.steps[s]
      steps[#steps + 1] = e
      wait = wait + (e.mode ~= "walk" and e.wait or 0)
    end
    local at = plan.order[part.k + 1]
    local role = "stop"
    local nStops = plan.nStops
    if at == 1 or (at == nStops + 2 and plan.noGoal) then
      role = "return"
    elseif at == nStops + 2 then
      role = "goal"
    end
    legs[i] = {
      index = i,
      from = part.from,
      to = part.to,
      role = role,
      stop = role == "stop" and plan.stopNumber[at - 1] or nil,
      steps = steps,
      sec = part.totalSec,
      waitSec = wait,
      est = part.est,
      first = part.first,
      last = part.last,
    }
  end
  return legs
end

function TP.Plan(data, o, req)
  local plan = { status = "unreachable", legs = {}, steps = {}, targets = {}, errors = {}, order = {} }
  local function fail(stop, slug, reason)
    plan.errors[#plan.errors + 1] = { stop = stop, slug = slug, reason = reason }
  end
  local start, why = toSlug(data, o, req.start)
  if not start then
    fail(nil, req.start, why)
    return plan
  end
  local stops = {}
  for i, point in ipairs(req.stops or {}) do
    if i > TL.MAX_STOPS then
      fail(i, nil, "toomany")
    else
      local slug, reason = toSlug(data, o, point)
      if slug then
        stops[#stops + 1] = { slug = slug, n = i }
      else
        fail(i, type(point) == "string" and point or nil, reason)
      end
    end
  end
  local goal = start
  plan.noGoal = req.goal == nil or nil
  if req.goal ~= nil then
    local reason
    goal, reason = toSlug(data, o, req.goal)
    if not goal then
      fail(nil, req.goal, reason)
      return plan
    end
  elseif not req.returnToStart then
    fail(nil, nil, "goal")
    return plan
  end
  -- Each failed attempt drops one stop, so the loop ends after at most #stops + 1 rounds.
  while true do
    local list = { start }
    for _, s in ipairs(stops) do
      list[#list + 1] = s.slug
    end
    list[#list + 1] = goal
    local r = TL.RouteVia(data, o, list, { optimize = req.optimize, returnToStart = req.returnToStart })
    local nStops = #stops
    if r.status == "unreachable" then
      local to = r.order[r.leg + 1]
      local from = r.order[r.leg]
      local blame
      if to >= 2 and to <= nStops + 1 then
        blame = to - 1
      elseif from >= 2 and from <= nStops + 1 then
        blame = from - 1
      end
      if not blame then
        fail(nil, r.to, "goal")
        return plan
      end
      fail(stops[blame].n, stops[blame].slug, "unreachable")
      table.remove(stops, blame)
    else
      plan.status = r.status
      plan.list = r.list
      plan.nStops = nStops
      plan.stopNumber = {}
      for i, s in ipairs(stops) do
        plan.stopNumber[i] = s.n
      end
      plan.order = r.order
      plan.visited = {}
      for i = 2, #r.order do
        local at = r.order[i]
        if at >= 2 and at <= nStops + 1 then
          plan.visited[#plan.visited + 1] = plan.stopNumber[at - 1]
        end
      end
      if r.status == "ok" then
        plan.legs = legsOf(r.best, plan)
        plan.best = r.best
        plan.steps = r.best.steps
        plan.targets = TP.Targets(data, plan.legs)
        plan.totalSec = r.best.totalSec
        plan.waitSec = 0
        for _, leg in ipairs(plan.legs) do
          plan.waitSec = plan.waitSec + leg.waitSec
        end
        plan.alternatives = r.alternatives
        plan.optimized, plan.saved = r.optimized, r.saved
      end
      plan.order = plan.visited
      plan.stopNumber, plan.visited, plan.nStops, plan.noGoal = nil, nil, nil, nil
      return plan
    end
  end
end
