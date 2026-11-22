-- Walking time and path between two world points on a continent: the hierarchical router (NavRouter) over the data
-- add-ons ForeverGuides_Nav_* (docs/NAVGRID-FORMAT.md), a straight line with a detour factor where no data answers.
-- Pure part: Estimate, Path, WalkCost. Game part: Ensure (loads the continent's data add-on outside combat) and
-- PathAsync / CostAsync (the search in time slices of a few milliseconds per frame, paused in combat). Nothing here
-- touches the route planner.
local _, ns = ...

local WL = {}
ns.WalkLogic = WL

WL.SPEED = 7 -- yards per second running, as TravelWalk and the waypoint arrow
-- Straight line to walked distance where the grid cannot answer (mean of the grid routes, with margin).
WL.DETOUR = 1.3
WL.BUDGET_MS = 3 -- time a slice of an async search may take per frame

local sqrt = math.sqrt
local NR, ND = ns.NavRouter, ns.NavData

local function isNumber(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Seconds and yards of a straight walk with the detour factor.
function WL.Estimate(x1, y1, x2, y2)
  local yards = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) * WL.DETOUR
  return yards / WL.SPEED, yards
end

local WHY = { outside = "outside", nopath = "nopath", error = "cap" }

local function straight(map, x1, y1, x2, y2)
  return { { x = x1, y = y1, uiMap = map }, { x = x2, y = y2, uiMap = map } }
end

local function validPoints(x1, y1, x2, y2)
  return isNumber(x1) and isNumber(y1) and isNumber(x2) and isNumber(y2)
end

-- The answer of a finished job as { seconds, yards, cost, source, why, pts }: the grid result, else the estimate.
local function result(out, map, x1, y1, x2, y2, opts, why)
  if out and out.source == "grid" then
    return out
  end
  local seconds, yards = 0, 0
  if why ~= "invalid" then
    seconds, yards = WL.Estimate(x1, y1, x2, y2)
  end
  local pts
  if not opts.noPath then
    pts = why ~= "invalid" and straight(map, x1, y1, x2, y2) or {}
  end
  return {
    seconds = seconds,
    yards = yards,
    cost = seconds,
    source = "estimate",
    why = why or WHY[out and out.why or ""] or "nodata",
    style = ns.WalkPathLogic.Style(opts.style),
    pts = pts,
  }
end

-- The profile of the player's faction for hostile towns: "Alliance", "Horde", nil for neither.
function WL.Profile()
  local f = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
  return (f == "Alliance" or f == "Horde") and f or nil
end

local function routerOpts(opts)
  return { style = opts.style, profile = opts.profile or WL.Profile(), z1 = opts.z1, z2 = opts.z2, noPath = opts.noPath }
end

-- The whole answer at once (src: a router source, the loaded data of the map by default). opts.style: "fastest",
-- "balanced" (default) or "roads"; opts.noPath skips the points. Returns { seconds, yards, cost, source ("grid" or
-- "estimate"), why, pts = { { x, y, z, uiMap }, ... } }. why of an estimate: "nodata" (no data loaded or the map is not
-- in it), "invalid" (bad input), "outside", "nopath" or "cap".
function WL.Path(map, x1, y1, x2, y2, opts, src)
  opts = opts or {}
  if not validPoints(x1, y1, x2, y2) then
    return result(nil, map, x1, y1, x2, y2, opts, "invalid")
  end
  src = src or ND.Source(map)
  if not src then
    return result(nil, map, x1, y1, x2, y2, opts, "nodata")
  end
  return result(NR.Find(src, x1, y1, x2, y2, routerOpts(opts)), map, x1, y1, x2, y2, opts)
end

-- Walking time from (x1, y1) to (x2, y2) on the map (a continent id, coordinates as UnitPosition and
-- C_Map.GetWorldPosFromMapPos give them). Returns seconds, yards, source ("grid" or "estimate") and, for an
-- estimate, why (see WL.Path). Runs the whole search at once; use PathAsync or CostAsync in the game.
function WL.WalkCost(map, x1, y1, x2, y2, src)
  local r = WL.Path(map, x1, y1, x2, y2, { noPath = true }, src)
  return r.seconds, r.yards, r.source, r.why
end

-- Game part --------------------------------------------------------------------------------------------------------

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- Loads the data add-on of the continent (never in combat). Returns whether its data is there.
function WL.Ensure(map)
  return ND.Source(map) ~= nil or ND.Load(map)
end

local function after(delay, fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, fn)
    return true
  end
  return false
end

local function now()
  local stop = rawget(_G, "debugprofilestop")
  return type(stop) == "function" and stop() or os.clock() * 1000
end

-- Like Path, but in time slices of opts.budget (WL.BUDGET_MS) milliseconds per frame, paused in combat. opts.clock
-- replaces the millisecond clock. onDone(result) runs once, at once when the answer needs no search. Returns a handle
-- with Cancel().
function WL.PathAsync(map, x1, y1, x2, y2, opts, onDone)
  opts = opts or {}
  local handle = { cancelled = false }
  function handle.Cancel()
    handle.cancelled = true
  end
  local src = validPoints(x1, y1, x2, y2) and ND.Source(map)
  if not src then
    onDone(WL.Path(map, x1, y1, x2, y2, opts, nil))
    return handle
  end
  local clock = opts.clock or now
  local budget = opts.budget or WL.BUDGET_MS
  local job = NR.NewJob(src, x1, y1, x2, y2, routerOpts(opts))
  local function slice()
    if handle.cancelled then
      return
    end
    if inCombat() then
      after(1, slice)
      return
    end
    local done, out = NR.Resume(job, clock, budget)
    if not done then
      after(0, slice)
      return
    end
    onDone(result(out, map, x1, y1, x2, y2, opts))
  end
  if not after(0, slice) then
    local _, out = NR.Resume(job)
    onDone(result(out, map, x1, y1, x2, y2, opts))
  end
  return handle
end

-- Like WalkCost, but in slices and paused in combat. onDone(seconds, yards, source, why, pts) runs once; pts (the
-- drawn path) only with opts.path. Returns a handle with Cancel(). opts.style as in Path.
function WL.CostAsync(map, x1, y1, x2, y2, onDone, opts)
  opts = opts or {}
  local o =
    { style = opts.style, noPath = not opts.path, budget = opts.budget, clock = opts.clock, profile = opts.profile }
  return WL.PathAsync(map, x1, y1, x2, y2, o, function(r)
    onDone(r.seconds, r.yards, r.source, r.why, r.pts)
  end)
end
