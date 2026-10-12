-- Walk durations of the travel graph from real world coordinates. The generated graph only has
-- estimates from the canvas distance; where both ends of a walk link have a UiMap position on the
-- same continent, the distance in yards gives a better value. The result is a table of overrides
-- that TravelLogic uses (TL.SetWalkDurations), Data\Travel.lua stays untouched.
-- Pure part: NewRun/Step/ApplyWorldDistances take a worldPos function. Game part: Ensure.
local _, ns = ...
local TL = ns.TravelLogic

local TW = {}
ns.TravelWalk = TW

ns.AddLocale("enUS", {
  ["map.cf.world"] = "from world coordinates",
})
ns.AddLocale("deDE", {
  ["map.cf.world"] = "aus Weltkoordinaten",
})

TW.YARDS_PER_SEC = 7 -- running on foot; a ground mount is FOOT_FACTOR times faster
TW.MIN_SEC = 20
TW.MIN_RATIO, TW.MAX_RATIO = 0.5, 3
TW.BATCH = 30 -- walk links per tick

local floor, sqrt = math.floor, math.sqrt

local function isNumber(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- Pure part -------------------------------------------------------------------------

-- worldPos(um, x, y) -> continent, wx, wy. A run is stepped in packets so the game never stalls.
function TW.NewRun(data, worldPos)
  local nodes = {}
  for _, n in ipairs(data.nodes or {}) do
    nodes[n.s] = n
  end
  return {
    links = data.links or {},
    nodes = nodes,
    worldPos = worldPos,
    at = 0,
    places = {},
    overrides = {},
    -- walk: all walk links; overridden/kept add up to walk. noPos and split say why a link was kept,
    -- uncertain counts world values outside the plausible range.
    stats = { walk = 0, overridden = 0, kept = 0, uncertain = 0, noPos = 0, split = 0 },
  }
end

-- Continent and world position of a node, false when it has none (cached per run).
local function place(run, slug)
  local hit = run.places[slug]
  if hit ~= nil then
    return hit
  end
  local n = run.nodes[slug]
  hit = false
  if n and isNumber(n.um) and isNumber(n.ux) and isNumber(n.uy) then
    local ok, cont, wx, wy = pcall(run.worldPos, n.um, n.ux, n.uy)
    if ok and cont ~= nil and isNumber(wx) and isNumber(wy) then
      hit = { cont = cont, x = wx, y = wy }
    end
  end
  run.places[slug] = hit
  return hit
end

local function judge(run, link)
  local stats = run.stats
  stats.walk = stats.walk + 1
  local a, b = place(run, link.from), place(run, link.to)
  if not (a and b) then
    stats.noPos, stats.kept = stats.noPos + 1, stats.kept + 1
    return
  end
  if a.cont ~= b.cont then
    stats.split, stats.kept = stats.split + 1, stats.kept + 1
    return
  end
  local estimate = link.d
  if not (isNumber(estimate) and estimate > 0) then
    stats.kept = stats.kept + 1
    return
  end
  local yards = sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
  -- d is the mounted base of the graph: foot time = d * FOOT_FACTOR = yards / YARDS_PER_SEC.
  local base = yards / (TW.YARDS_PER_SEC * TL.FOOT_FACTOR)
  if base < estimate * TW.MIN_RATIO or base > estimate * TW.MAX_RATIO then
    stats.uncertain, stats.kept = stats.uncertain + 1, stats.kept + 1
    return
  end
  run.overrides[TL.LinkKey(link)] = math.max(TW.MIN_SEC, floor(base + 0.5))
  stats.overridden = stats.overridden + 1
end

-- Judges up to limit walk links; returns true when the run is complete.
function TW.Step(run, limit)
  local done = 0
  while run.at < #run.links and done < limit do
    run.at = run.at + 1
    local link = run.links[run.at]
    if link.m == "walk" and link.from and link.to then
      done = done + 1
      judge(run, link)
    end
  end
  return run.at >= #run.links
end

-- All at once: overrides[TL.LinkKey(link)] = seconds, plus the counters.
function TW.ApplyWorldDistances(data, worldPos)
  local run = TW.NewRun(data, worldPos)
  TW.Step(run, math.huge)
  return run.overrides, run.stats
end

-- Game part -------------------------------------------------------------------------

-- The client's conversion; nil results mean "no position" and keep the estimate.
function TW.GamePos(um, x, y)
  local fn = C_Map and C_Map.GetWorldPosFromMapPos
  local vec = rawget(_G, "CreateVector2D")
  if type(fn) ~= "function" or type(vec) ~= "function" then
    return nil
  end
  local ok, cont, pos = pcall(fn, um, vec(x, y))
  if not (ok and cont ~= nil and type(pos) == "table") then
    return nil
  end
  local wx, wy = pos.x, pos.y
  if wx == nil and pos.GetXY then
    wx, wy = pos:GetXY()
  end
  return cont, wx, wy
end

function TW.CanConvert()
  return type(C_Map) == "table"
    and type(C_Map.GetWorldPosFromMapPos) == "function"
    and type(rawget(_G, "CreateVector2D")) == "function"
end

local state = { status = "idle", waiting = {} } -- idle | running | done | failed

local function buildKey()
  local build = type(GetBuildInfo) == "function" and select(2, GetBuildInfo()) or nil
  return build ~= nil and tostring(build) or nil
end

-- ns.db.travelWalk is saved data: only positive numbers pass.
local function loadCache(build)
  local saved = ns.db and ns.db.travelWalk
  if not (build and type(saved) == "table" and saved.build == build and saved.version == ns.version) then
    return nil
  end
  if type(saved.d) ~= "table" then
    return nil
  end
  local d = {}
  for key, sec in pairs(saved.d) do
    if type(key) == "string" and isNumber(sec) and sec > 0 then
      d[key] = sec
    end
  end
  return d
end

local function finish(run, build)
  TL.SetWalkDurations(run.overrides)
  state.status, state.stats = "done", run.stats
  if build and ns.db then
    ns.db.travelWalk = { build = build, version = ns.version, d = run.overrides }
  end
  local waiting = state.waiting
  state.waiting, state.run = {}, nil
  for _, fn in ipairs(waiting) do
    ns.Safe("travel-walk-done", fn)
  end
end

local function schedule(fn, delay)
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, fn)
  else
    fn()
  end
end

-- Starts the calculation once (first call outside combat), from the cache when the build is the
-- same. onDone runs after a fresh calculation, not when the cache answered right away. Without
-- C_Map nothing happens and every walk time stays an estimate.
function TW.Ensure(data, onDone)
  if state.status == "running" then
    if onDone then
      state.waiting[#state.waiting + 1] = onDone
    end
    return
  end
  if state.status ~= "idle" or not (data and data.links) or inCombat() or not TW.CanConvert() then
    return
  end
  local build = buildKey()
  local cached = loadCache(build)
  if cached then
    TL.SetWalkDurations(cached)
    state.status = "done"
    return
  end
  local run = TW.NewRun(data, TW.GamePos)
  state.status, state.run, state.waiting = "running", run, { onDone }
  local function tick()
    if inCombat() then
      return schedule(tick, 1)
    end
    local ok, complete = ns.Safe("travel-walk", TW.Step, run, TW.BATCH)
    if not ok then
      state.status, state.run, state.waiting = "failed", nil, {}
    elseif complete then
      finish(run, build)
    else
      schedule(tick, 0)
    end
  end
  schedule(tick, 0)
end

-- Test seam. status: idle | running | done | failed; stats of the
-- calculation of this session (a result loaded from the saved cache has none).
function TW.Status()
  return state.status, state.stats or (state.run and state.run.stats)
end

function TW.Reset()
  state = { status = "idle", waiting = {} }
  TL.SetWalkDurations(nil)
end
