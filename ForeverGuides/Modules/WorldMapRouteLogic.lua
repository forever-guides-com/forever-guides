-- The route plan of the player as plain data and the rules around it: an ordered list of points (the last
-- one is the goal), the start, three switches (optimize the order, return to the start, hearthstone) and
-- the option "start at my position" (off by default: the first point is the start, so a route does not depend
-- on where the player stands). Without that option a state with points always has a start (Normalize). Pure logic without WoW API; RoutePlan.lua keeps the state, the world map and the page show
-- it. A point is a place slug or a free point "@map_x_y" (TravelLogic.PointSlug), so it survives a reload as
-- text.
--
--   WRL.Clean(raw) -> state          validated copy of a stored plan, anything wrong is dropped
--   WRL.Add / Insert / Remove / Move / SetGoal / Replace / SetStart / Clear   (state, ...) -> ok, reason
--   WRL.Request(state, here) -> TravelPlan request or nil
--   WRL.Rows(state, plan, name) -> the stop list in the order the route visits it
--   WRL.Summary(plan) -> totals and counts for the header line
--   WRL.PlanSlugs(state, plan, here) -> start, stops in order, goal as slugs (numbered pins)
--   WRL.StepsOnMap(steps, posOf, project) -> the steps both ends of which lie on the shown map
local _, ns = ...
local TL = ns.TravelLogic

local WRL = {}
ns.WorldMapRouteLogic = WRL

WRL.VERSION = 1
-- Stops plus the goal.
WRL.MAX_POINTS = TL.MAX_STOPS + 1

local SLUG_MAX = 80

local function validSlug(slug)
  if type(slug) ~= "string" or slug == "" or #slug > SLUG_MAX then
    return false
  end
  if TL.IsPoint(slug) then
    return TL.ParsePoint(slug) ~= nil
  end
  return slug:match("^[%w_%-%.:]+$") ~= nil
end
WRL.ValidSlug = validSlug

function WRL.New()
  return {
    v = WRL.VERSION,
    start = nil,
    points = {},
    optimize = false,
    returnToStart = false,
    hearth = false,
    fromHere = false,
  }
end

-- A stored plan as a valid state: unknown fields and wrong types are dropped, the list is cut to MAX_POINTS.
function WRL.Clean(raw)
  local st = WRL.New()
  if type(raw) ~= "table" then
    return st
  end
  if validSlug(raw.start) then
    st.start = raw.start
  end
  if type(raw.points) == "table" then
    for _, slug in ipairs(raw.points) do
      if #st.points > WRL.MAX_POINTS then
        break
      end
      if validSlug(slug) and slug ~= st.points[#st.points] then
        st.points[#st.points + 1] = slug
      end
    end
  end
  st.optimize = raw.optimize == true
  st.returnToStart = raw.returnToStart == true
  st.hearth = raw.hearth == true
  st.fromHere = raw.fromHere == true
  WRL.Normalize(st)
  while #st.points > WRL.MAX_POINTS do
    table.remove(st.points)
  end
  return st
end

-- Without "start at my position" the first point is the start. Returns true when something moved.
function WRL.Normalize(st)
  if not st.fromHere and not st.start and #st.points > 0 then
    st.start = table.remove(st.points, 1)
    return true
  end
  return false
end

-- Switches the option. Turning it on hands an explicit start back to the list (the route then starts at the
-- player and still visits it), turning it off makes the first point the start.
function WRL.SetFromHere(st, on)
  st.fromHere = on == true
  if st.fromHere then
    if st.start and #st.points < WRL.MAX_POINTS then
      table.insert(st.points, 1, st.start)
      st.start = nil
    end
  else
    WRL.Normalize(st)
  end
end

-- The shape that is written to the saved variables (a copy, nothing shared with the live state).
function WRL.Persist(st)
  local out = {
    v = WRL.VERSION,
    points = {},
    optimize = st.optimize == true,
    returnToStart = st.returnToStart == true,
    hearth = st.hearth == true,
    fromHere = st.fromHere == true,
  }
  out.start = st.start
  for i, slug in ipairs(st.points) do
    out.points[i] = slug
  end
  return out
end

-- Changes ------------------------------------------------------------------------------------------

-- Appends a point as the new goal. false + "invalid", "full" or "same" (the point before is the same one).
function WRL.Add(st, slug)
  if not validSlug(slug) then
    return false, "invalid"
  end
  if #st.points >= WRL.MAX_POINTS then
    return false, "full"
  end
  if slug == (st.points[#st.points] or st.start) then
    return false, "same"
  end
  st.points[#st.points + 1] = slug
  return true
end

-- A new stop in front of the goal (the goal stays the goal). Without a goal the point becomes the goal.
function WRL.Insert(st, slug)
  local n = #st.points
  if n == 0 then
    return WRL.Add(st, slug)
  end
  if not validSlug(slug) then
    return false, "invalid"
  end
  if n >= WRL.MAX_POINTS then
    return false, "full"
  end
  if slug == st.points[n - 1] or slug == st.points[n] or (n == 1 and slug == st.start) then
    return false, "same"
  end
  table.insert(st.points, n, slug)
  return true
end

function WRL.Remove(st, i)
  if st.points[i] == nil then
    return false, "none"
  end
  table.remove(st.points, i)
  return true
end

-- Swaps a point with its neighbor in the list (delta -1 up, 1 down).
function WRL.Move(st, i, delta)
  local j = i + delta
  if not (st.points[i] and st.points[j]) then
    return false, "none"
  end
  st.points[i], st.points[j] = st.points[j], st.points[i]
  return true
end

-- Takes point `from` out and puts it at the place `to` (drag and drop in the list).
function WRL.Reorder(st, from, to)
  if st.points[from] == nil or st.points[to] == nil or from == to then
    return false, "none"
  end
  table.insert(st.points, to, table.remove(st.points, from))
  return true
end

-- The row a point moves to when it goes one row up (-1) or down (1) in the shown list `rows` (WRL.Rows):
-- the place in state.points of the neighbor row, nil at the ends of the list.
function WRL.NeighborIndex(rows, index, delta)
  for p, row in ipairs(rows) do
    if row.index == index then
      local other = rows[p + delta]
      return other and other.index or nil
    end
  end
end

-- Makes point i the last one, the goal.
function WRL.SetGoal(st, i)
  if st.points[i] == nil or i == #st.points then
    return false, "none"
  end
  table.insert(st.points, table.remove(st.points, i))
  return true
end

-- A point moved elsewhere (drag): the new place takes its row.
function WRL.Replace(st, i, slug)
  if st.points[i] == nil or not validSlug(slug) then
    return false, "invalid"
  end
  st.points[i] = slug
  return true
end

-- The start point; nil goes back to the player position (with the option) or to the first point.
function WRL.SetStart(st, slug)
  if slug ~= nil and not validSlug(slug) then
    return false, "invalid"
  end
  st.start = slug
  return true
end

function WRL.Clear(st)
  st.start, st.points = nil, {}
  return true
end

-- Planning -----------------------------------------------------------------------------------------

-- The request for TravelPlan.Plan, nil when there is no goal yet. `here` is the player position
-- ({ map, x, y } or a slug), the start when none was set.
function WRL.Request(st, here)
  local n = #st.points
  local start = st.start or (st.fromHere and here or nil)
  if n == 0 or start == nil then
    return nil
  end
  local stops = {}
  for i = 1, n - 1 do
    stops[i] = st.points[i]
  end
  return {
    start = start,
    stops = stops,
    goal = st.points[n],
    optimize = st.optimize == true,
    returnToStart = st.returnToStart == true,
  }
end

local function legSeconds(plan)
  local byStop, goalSec = {}, nil
  for _, leg in ipairs(plan and plan.legs or {}) do
    if leg.role == "stop" and leg.stop then
      byStop[leg.stop] = (byStop[leg.stop] or 0) + (leg.sec or 0)
    elseif leg.role == "goal" then
      goalSec = (goalSec or 0) + (leg.sec or 0)
    end
  end
  return byStop, goalSec
end

-- The list the route visits, as rows { index (place in state.points), number (1..m, nil for a stop that
-- cannot be reached), label ("1".."m", goal "Z"), name, goal, error (reason of TravelPlan), sec (leg
-- time to this row) }. Reachable stops come in the order of the plan (the optimized one when the plan
-- has it), stops that cannot be reached follow, the goal ends the list. Without a plan the order is the
-- given one.
function WRL.Rows(st, plan, name, goalLabel)
  local n = #st.points
  local rows = {}
  if n == 0 then
    return rows
  end
  local failed, errorOf = {}, {}
  for _, e in ipairs(plan and plan.errors or {}) do
    if e.stop then
      failed[e.stop] = true
      errorOf[e.stop] = e.reason
    end
  end
  local visited, seen = {}, {}
  if plan and plan.order then
    for _, k in ipairs(plan.order) do
      if st.points[k] and k < n and not seen[k] then
        seen[k] = true
        visited[#visited + 1] = k
      end
    end
  else
    for k = 1, n - 1 do
      if not failed[k] then
        seen[k] = true
        visited[#visited + 1] = k
      end
    end
  end
  local secOf, goalSec = legSeconds(plan)
  for number, k in ipairs(visited) do
    rows[#rows + 1] = {
      index = k,
      number = number,
      label = tostring(number),
      name = name(st.points[k]),
      sec = secOf[k],
    }
  end
  for k = 1, n - 1 do
    if not seen[k] then
      rows[#rows + 1] = { index = k, label = "!", name = name(st.points[k]), error = errorOf[k] or "unreachable" }
    end
  end
  rows[#rows + 1] = {
    index = n,
    label = goalLabel or "Z",
    name = name(st.points[n]),
    goal = true,
    sec = goalSec,
    error = plan and plan.status == "unreachable" and not next(failed) and "unreachable" or nil,
  }
  return rows
end

-- Header numbers of a plan: status, total and waiting seconds, saved seconds (optimized order only),
-- the errors that belong to no stop (goal, start) apart from the ones per stop.
function WRL.Summary(plan)
  local out = { status = "none", totalSec = 0, waitSec = 0, saved = 0, optimized = false, errors = {} }
  if not plan then
    return out
  end
  out.status = plan.status or "none"
  out.totalSec = plan.totalSec or 0
  out.waitSec = plan.waitSec or 0
  out.optimized = plan.optimized == true
  out.saved = out.optimized and (plan.saved or 0) or 0
  for _, e in ipairs(plan.errors or {}) do
    out.errors[#out.errors + 1] = e
  end
  return out
end

-- The numbered places of the map pins: start first, the reachable stops in visiting order, the goal last.
-- The same list the pins and the panel use, so numbers agree. The second result gives the place of every
-- entry in state.points (nil for the start).
function WRL.PlanSlugs(st, plan, startSlug)
  local out, at = {}, {}
  local n = #st.points
  if n == 0 then
    return out, at
  end
  out[1] = startSlug
  for _, row in ipairs(WRL.Rows(st, plan, tostring)) do
    if row.number or row.goal then
      out[#out + 1] = st.points[row.index]
      at[#out] = row.index
    end
  end
  return out, at
end

-- Which steps of a route show on the map that is shown: the ones whose both ends have a position there.
-- posOf(slug) gives { map, x, y } or nil, project(map, x, y) gives the place on the shown map or nil.
-- Returns the steps in order together with their number in the whole route.
function WRL.StepsOnMap(steps, posOf, project)
  local out, at = {}, {}
  local function onMap(slug)
    local p = posOf(slug)
    if not p then
      return false
    end
    return project(p.map, p.x, p.y) ~= nil
  end
  for i, step in ipairs(steps or {}) do
    if onMap(step.from) and onMap(step.to) then
      out[#out + 1] = step
      at[#out] = i
    end
  end
  return out, at
end
