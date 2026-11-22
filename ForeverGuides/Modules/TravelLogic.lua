-- Route planning over the generated travel graph (ns.Data.Travel). Pure
-- logic without WoW API, same rules as the website's travelRoute.ts.
local _, ns = ...

local TL = {}
ns.TravelLogic = TL

TL.MODES = { "flight", "boat", "zeppelin", "tram", "portal", "walk", "spell", "teleport", "lift" }
-- Lifts join the parts of one place and have no switch of their own.
local ALWAYS_ON = { lift = true }

local FOOT_FACTOR = 1.6
TL.FOOT_FACTOR = FOOT_FACTOR
-- "Prefer flying" adds max(FLY_MIN, sec * (FLY_FACTOR - 1)) seconds to the search weight of every walk
-- edge; the shown durations stay the real ones. o.flyFactor and o.flyMin override both.
TL.FLY_FACTOR = 1.5
TL.FLY_MIN = 60
local MAX_ALTERNATIVES = 3
TL.MAX_STOPS = 10

-- Free points: "@<map>_<x>_<y>" names a spot of a UiMap, x and y in ten-thousandths of the map. They are
-- no graph places; a search joins them to the nearest places by walking (see addPointEdges).
TL.YARDS_PER_SEC = 7
TL.HEARTH_SEC = 25 -- cast time plus the loading screen
TL.DETOUR = 1.3 -- estimated path length over the straight line
local POINT_NEAREST = 3 -- places a free point is joined to
local POINT_DIRECT_MAX = 3000 -- yards; free points closer than this also walk to each other

function TL.IsPoint(slug)
  return type(slug) == "string" and slug:sub(1, 1) == "@"
end

function TL.PointSlug(map, x, y)
  return string.format("@%d_%d_%d", map, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5))
end

-- { s, map, x, y } with x, y as fractions, or nil for anything that is no valid point.
function TL.ParsePoint(slug)
  local map, x, y = tostring(slug):match("^@(%d+)_(%d+)_(%d+)$")
  map, x, y = tonumber(map), tonumber(x), tonumber(y)
  if not map or map < 1 or x > 10000 or y > 10000 then
    return nil
  end
  return { s = slug, map = map, x = x / 10000, y = y / 10000 }
end

-- Optional d overrides for walk links from world coordinates (TravelWalk), keyed by LinkKey.
local walkD

function TL.LinkKey(link)
  return link.from .. ">" .. link.to
end

function TL.SetWalkDurations(map)
  walkD = map
end

function TL.WalkDurations()
  return walkD
end

-- o: { faction = "A"|"H", level, class = "MAGE"|"DRUID"|..., skyborne, modes = { [mode] = true }, mount, today = "YYYY-MM-DD",
-- flightTimes = measured flight times (default: the saved ones) }
function TL.NodeVisible(node, o)
  if node.f ~= "B" and node.f ~= o.faction then
    return false
  end
  if node.ra and o.today and o.today < node.ra then
    return false
  end
  return true
end

function TL.LinkAllowed(link, o)
  if link.f ~= "B" and link.f ~= o.faction then
    return false
  end
  if link.ml and (o.level or 60) < link.ml then
    return false
  end
  if link.ra and o.today and o.today < link.ra then
    return false
  end
  local rq = link.rq
  if rq == "classMage" and o.class ~= "MAGE" then
    return false
  end
  if rq == "classDruid" and o.class ~= "DRUID" then
    return false
  end
  if rq == "skyborne" and not o.skyborne then
    return false
  end
  return true
end

local function isNumber(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function worldOf(o, cache, key, um, x, y)
  local hit = cache[key]
  if hit == nil then
    hit = false
    local ok, cont, wx, wy = pcall(o.worldPos, um, x, y)
    if ok and cont ~= nil and isNumber(wx) and isNumber(wy) then
      hit = { cont = cont, x = wx, y = wy }
    end
    cache[key] = hit
  end
  return hit or nil
end

-- A walk edge between two world positions: seconds, whether it is an estimate. The grid time of
-- o.walkCost(a, b, o.walkStyle) (on foot, nil while unknown) wins over the straight line estimate. A grid walk also
-- brings its path (pts, { x, y, uiMap } from a to b) and its length (walked yards); both ride on the edge.
local function walkEdge(o, from, to, a, b)
  local yards = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
  local foot, pts, walked
  if o.walkCost then
    foot, pts, walked = o.walkCost(a, b, o.walkStyle)
  end
  local est = not isNumber(foot)
  if est then
    foot = yards * TL.DETOUR / TL.YARDS_PER_SEC
  end
  local sec = math.max(1, math.floor(foot / (o.mount == false and 1 or FOOT_FACTOR) + 0.5))
  return {
    from = from,
    to = to,
    mode = "walk",
    sec = sec,
    weight = sec,
    cf = est and "estimate" or "grid",
    est = est or nil,
    grid = not est or nil,
    pt = true,
    pa = a,
    pb = b,
    pts = not est and type(pts) == "table" and pts or nil,
    walked = not est and isNumber(walked) and walked or nil,
  },
    yards
end

-- Joins every free point to its nearest places (those with a way on) and to near free points.
-- Without o.worldPos or a world position nothing is joined and the point stays unreachable.
local function addPointEdges(data, o, points, cache, out, visible, add)
  if not o.worldPos then
    return
  end
  local placed = {}
  for _, p in ipairs(points) do
    local w = worldOf(o, cache, p.s, p.map, p.x, p.y)
    if w then
      visible[p.s] = true
      placed[#placed + 1] = { p = p, w = w }
    end
  end
  local both = function(a, b, wa, wb)
    add((walkEdge(o, a, b, wa, wb)))
    add((walkEdge(o, b, a, wb, wa)))
  end
  for _, q in ipairs(placed) do
    local near = {}
    for _, n in ipairs(data.nodes) do
      if visible[n.s] and out[n.s] and isNumber(n.um) and isNumber(n.ux) and isNumber(n.uy) then
        local w = worldOf(o, cache, n.s, n.um, n.ux, n.uy)
        if w and w.cont == q.w.cont then
          near[#near + 1] = { n = n, w = w, d = (w.x - q.w.x) ^ 2 + (w.y - q.w.y) ^ 2 }
        end
      end
    end
    table.sort(near, function(a, b)
      if a.d ~= b.d then
        return a.d < b.d
      end
      return a.n.s < b.n.s
    end)
    for i = 1, math.min(POINT_NEAREST, #near) do
      both(q.p.s, near[i].n.s, q.w, near[i].w)
    end
  end
  for i = 1, #placed - 1 do
    for j = i + 1, #placed do
      local a, b = placed[i], placed[j]
      if a.w.cont == b.w.cont and a.p.s ~= b.p.s then
        local _, yards = walkEdge(o, a.p.s, b.p.s, a.w, b.w)
        if yards <= POINT_DIRECT_MAX then
          both(a.p.s, b.p.s, a.w, b.w)
        end
      end
    end
  end
end

local function buildEdges(data, o, skip, points, worldCache)
  local visible = {}
  local origins = {}
  for _, n in ipairs(data.nodes) do
    if TL.NodeVisible(n, o) then
      visible[n.s] = true
      origins[#origins + 1] = n.s
    end
  end
  -- Stations that are no places of the map (lift tops and bottoms) take part in the search only.
  for _, n in ipairs(data.via or {}) do
    if TL.NodeVisible(n, o) then
      visible[n.s] = true
    end
  end
  local out = {}
  local function add(e)
    if not visible[e.from] or not visible[e.to] or e.from == e.to then
      return
    end
    if skip == e.mode or (o.modes and not o.modes[e.mode] and not ALWAYS_ON[e.mode]) then
      return
    end
    out[e.from] = out[e.from] or {}
    table.insert(out[e.from], e)
  end
  -- Flights take the time of their direction, the same as the flight times shown in the game.
  local flightHop
  local function flightSeconds(from, to)
    if not (flightHop or ns.FlightLogic) then
      return nil
    end
    flightHop = flightHop or ns.FlightLogic.hopper(data, o.flightTimes, o.faction)
    return flightHop(from, to)
  end
  for _, l in ipairs(data.links) do
    if TL.LinkAllowed(l, o) then
      local foot = (l.m == "walk" and o.mount == false) and FOOT_FACTOR or 1
      local world = walkD and l.m == "walk" and l.from and walkD[TL.LinkKey(l)] or nil
      local function mk(from, to)
        local base, cf = world or l.d or 0, l.cf
        if l.m == "flight" and l.from then
          local hop = flightSeconds(from, to)
          if hop then
            base, cf = hop.seconds, hop.source
          end
        end
        local sec = math.floor((base + (l.w or 0)) * foot + 0.5)
        local weight = sec
        if o.preferFlight and l.m == "walk" then
          weight = sec + math.max(o.flyMin or TL.FLY_MIN, math.floor(sec * ((o.flyFactor or TL.FLY_FACTOR) - 1) + 0.5))
        end
        return {
          from = from,
          to = to,
          mode = l.m,
          sec = sec,
          weight = weight,
          cf = cf,
          rq = l.rq,
          rn = l.rn,
          cost = l.cost,
          per = l.per,
          dep = l.dep,
          wait = l.w,
          wc = world and true or nil,
        }
      end
      if l.from then
        add(mk(l.from, l.to))
        if l.bi ~= false then
          add(mk(l.to, l.from))
        end
      else
        for _, from in ipairs(origins) do
          add(mk(from, l.to))
        end
      end
    end
  end
  if points and #points > 0 then
    addPointEdges(data, o, points, worldCache, out, visible, add)
  end
  -- Hearthstone: an optional dynamic link from every place and free point to the bound place. The
  -- caller says where it is bound and that the stone is ready; the search never assumes either.
  local hearth = o.hearth
  if hearth and hearth.to and hearth.ready ~= false and visible[hearth.to] then
    local sec = math.max(1, math.floor(hearth.sec or TL.HEARTH_SEC))
    local froms = {}
    for from in pairs(visible) do
      froms[#froms + 1] = from
    end
    table.sort(froms)
    for _, from in ipairs(froms) do
      if from ~= hearth.to then
        add({ from = from, to = hearth.to, mode = "teleport", sec = sec, weight = sec, cf = "reported", hearth = true })
      end
    end
  end
  return out, visible
end

-- ponytail: Dijkstra without a heap, O(n^2) over ~130 nodes; use a binary heap beyond a few thousand.
-- Without a target the search runs to the end and dist holds every reachable node.
local function dijkstra(graph, from, to)
  local out = graph.out
  local dist = { [from] = 0 }
  local prev, done = {}, {}
  while true do
    local cur, best
    for k, d in pairs(dist) do
      if not done[k] and (best == nil or d < best or (d == best and k < cur)) then
        cur, best = k, d
      end
    end
    if cur == nil or cur == to then
      return dist, prev
    end
    done[cur] = true
    for _, e in ipairs(out[cur] or {}) do
      local nd = best + e.weight
      if nd < (dist[e.to] or math.huge) then
        dist[e.to] = nd
        prev[e.to] = e
      end
    end
  end
end

local function shortest(graph, from, to)
  if not graph.visible[from] or not graph.visible[to] then
    return nil
  end
  local dist, prev = dijkstra(graph, from, to)
  if dist[to] == nil then
    return nil
  end
  local steps = {}
  local at, total = to, 0
  while at ~= from do
    local e = prev[at]
    table.insert(steps, 1, e)
    total = total + e.sec
    at = e.from
  end
  return { steps = steps, totalSec = total, weight = dist[to] }
end

local function signature(route)
  local parts = {}
  for _, s in ipairs(route.steps) do
    parts[#parts + 1] = s.from .. ">" .. s.to .. ":" .. s.mode
  end
  return table.concat(parts, "|")
end

-- The route along the places of list one leg after the other (a leg between equal places is
-- skipped). Returns nil and the index of the first leg without a connection, or the route with
-- parts = { { k = leg index in list, from, to, stop = number of the stop it ends at (nil at the goal),
-- first, last = step range, totalSec, est = a walk of the part is an estimate } }. The route has est too.
local function graphFor(data, o, skip, graphs)
  local key = skip or false
  local graph = graphs[key]
  if not graph then
    graph = {}
    graph.out, graph.visible = buildEdges(data, o, skip, graphs.points, graphs.world)
    graphs[key] = graph
  end
  return graph
end

local function viaRoute(data, o, list, skip, graphs)
  local graph = graphFor(data, o, skip, graphs)
  local steps, parts, total, weight = {}, {}, 0, 0
  local anyEst
  for k = 1, #list - 1 do
    local from, to = list[k], list[k + 1]
    if from ~= to then
      local leg = shortest(graph, from, to)
      if not leg then
        return nil, k
      end
      local first = #steps + 1
      local est
      for _, e in ipairs(leg.steps) do
        steps[#steps + 1] = e
        est = est or e.est
      end
      anyEst = anyEst or est
      parts[#parts + 1] = {
        k = k,
        from = from,
        to = to,
        stop = k < #list - 1 and k or nil,
        first = first,
        last = #steps,
        totalSec = leg.totalSec,
        est = est,
      }
      total, weight = total + leg.totalSec, weight + leg.weight
    end
  end
  return { steps = steps, totalSec = total, weight = weight, parts = parts, est = anyEst }
end

-- The stop order with the least search weight (start and goal stay): a matrix from one search per
-- start and stop, then RouteOrderLogic. Returns the new list, or list itself when nothing is better.
local function optimizeList(data, o, list, graphs)
  local m = #list
  local graph = graphFor(data, o, nil, graphs)
  local cost = {}
  for i = 1, m do
    cost[i] = {}
    local dist = i < m and graph.visible[list[i]] and dijkstra(graph, list[i], nil) or {}
    for j = 1, m do
      cost[i][j] = (i == j and 0) or dist[list[j]] or math.huge
    end
  end
  local order, total, given = ns.RouteOrderLogic.Solve(cost, m)
  if total >= given then
    return list
  end
  local out, took = { list[1] }, { 1 }
  for _, k in ipairs(order) do
    out[#out + 1] = list[k]
    took[#took + 1] = k
  end
  out[#out + 1] = list[m]
  took[#took + 1] = m
  return out, took
end

-- Route over list = { start, stop, ..., goal }; list entries are place slugs or free points. popts:
--   optimize = true      reorder the stops for the shortest trip (start and goal stay)
--   returnToStart = true after the goal one more leg leads back to the start
-- Returns { status = "ok", best, alternatives, list, order }, or { status = "same" } when every leg
-- stays in one place, or { status = "unreachable", leg, legs, from, to, list, order } naming the
-- first leg without a connection. list is the order used and order[i] the position in the given
-- list of list[i] (the return leg maps to 1). With optimize the result has optimized = true and
-- saved (seconds against the given order, nil when that order has no route). An alternative is the
-- whole route recomputed without one transport of the best route.
function TL.RouteVia(data, o, list, popts)
  popts = popts or {}
  local graphs = { world = {} }
  local points = {}
  for _, slug in ipairs(list) do
    local p = TL.IsPoint(slug) and TL.ParsePoint(slug)
    if p then
      points[#points + 1] = p
    end
  end
  local home = o.hearth and o.hearth.to
  if home and TL.IsPoint(home) and TL.ParsePoint(home) then
    points[#points + 1] = TL.ParsePoint(home)
  end
  graphs.points = points
  local given = list
  local optimized = popts.optimize and #list >= 4
  local order = {}
  for i = 1, #list do
    order[i] = i
  end
  if optimized then
    local took
    list, took = optimizeList(data, o, list, graphs)
    order = took or order
  end
  local reordered = list ~= given
  if popts.returnToStart and #list >= 2 then
    list = { unpack(list) }
    list[#list + 1] = list[1]
    given = { unpack(given) }
    given[#given + 1] = given[1]
    order = { unpack(order) }
    order[#order + 1] = 1
  end
  local best, bad = viaRoute(data, o, list, nil, graphs)
  if not best then
    return {
      status = "unreachable",
      leg = bad,
      legs = #list - 1,
      from = list[bad],
      to = list[bad + 1],
      list = list,
      order = order,
    }
  end
  if #best.steps == 0 then
    return { status = "same", list = list, order = order }
  end
  local saved = optimized and 0 or nil
  if optimized and reordered then
    local before = viaRoute(data, o, given, nil, graphs)
    saved = before and math.max(0, before.totalSec - best.totalSec) or nil
  end
  local seen = { [signature(best)] = true }
  local alternatives = {}
  local used, modes = {}, {}
  for _, s in ipairs(best.steps) do
    if not used[s.mode] then
      used[s.mode] = true
      modes[#modes + 1] = s.mode
    end
  end
  for _, mode in ipairs(modes) do
    local alt = viaRoute(data, o, list, mode, graphs)
    if alt and not seen[signature(alt)] and #alternatives < MAX_ALTERNATIVES then
      seen[signature(alt)] = true
      alt.without = mode
      alternatives[#alternatives + 1] = alt
    end
  end
  table.sort(alternatives, function(a, b)
    return a.weight < b.weight
  end)
  return {
    status = "ok",
    best = best,
    alternatives = alternatives,
    list = list,
    order = order,
    optimized = optimized or nil,
    saved = saved,
  }
end

-- Returns { status = "ok", best, alternatives } or { status = "same"|"unreachable" }.
function TL.Route(data, o)
  if o.from == o.to then
    return { status = "same" }
  end
  if not (o.from and o.to) then
    return { status = "unreachable" }
  end
  return TL.RouteVia(data, o, { o.from, o.to })
end

-- Nodes shown for the faction, optionally filtered by a folded name query, sorted by name.
-- nameOf(node) -> display name. match(text, query) -> boolean (query may be nil/"").
function TL.Nodes(data, o, nameOf, query, match)
  local out = {}
  for _, n in ipairs(data.nodes) do
    if TL.NodeVisible(n, o) then
      local name = nameOf(n)
      if not query or query == "" or match(name, query) then
        out[#out + 1] = { node = n, name = name }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.node.s < b.node.s
  end)
  return out
end

function TL.FormatDuration(sec)
  sec = math.floor(sec + 0.5)
  if sec < 3600 then
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
  end
  return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60)
end

-- Maps a node's canvas position (Travel.canvas) to 0..1 fractions.
function TL.CanvasFraction(data, node)
  local c = data.canvas
  if not (c and node.x and node.y) then
    return nil
  end
  return math.min(1, math.max(0, node.x / c.w)), math.min(1, math.max(0, node.y / c.h))
end
