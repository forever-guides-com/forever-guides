-- Route planning over the generated travel graph (ns.Data.Travel). Pure
-- logic without WoW API, same rules as the website's travelRoute.ts.
local _, ns = ...

local TL = {}
ns.TravelLogic = TL

TL.MODES = { "flight", "boat", "zeppelin", "tram", "portal", "walk", "spell", "teleport" }

local FOOT_FACTOR = 1.6
TL.FOOT_FACTOR = FOOT_FACTOR
-- "Prefer flying" adds max(FLY_MIN, sec * (FLY_FACTOR - 1)) seconds to the search weight of every walk
-- edge; the shown durations stay the real ones. o.flyFactor and o.flyMin override both.
TL.FLY_FACTOR = 1.5
TL.FLY_MIN = 60
local MAX_ALTERNATIVES = 3
TL.MAX_STOPS = 5

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

local function buildEdges(data, o, skip)
  local visible = {}
  local origins = {}
  for _, n in ipairs(data.nodes) do
    if TL.NodeVisible(n, o) then
      visible[n.s] = true
      origins[#origins + 1] = n.s
    end
  end
  local out = {}
  local function add(e)
    if not visible[e.from] or not visible[e.to] or e.from == e.to then
      return
    end
    if skip == e.mode or (o.modes and not o.modes[e.mode]) then
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
  return out, visible
end

-- ponytail: Dijkstra without a heap, O(n^2) over ~130 nodes; use a binary heap beyond a few thousand.
local function shortest(graph, from, to)
  local out, visible = graph.out, graph.visible
  if not visible[from] or not visible[to] then
    return nil
  end
  local dist = { [from] = 0 }
  local prev, done = {}, {}
  while true do
    local cur, best
    for k, d in pairs(dist) do
      if not done[k] and (best == nil or d < best or (d == best and k < cur)) then
        cur, best = k, d
      end
    end
    if cur == nil then
      return nil
    end
    if cur == to then
      break
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
-- first, last = step range, totalSec } }.
local function viaRoute(data, o, list, skip, graphs)
  local key = skip or false
  local graph = graphs[key]
  if not graph then
    graph = {}
    graph.out, graph.visible = buildEdges(data, o, skip)
    graphs[key] = graph
  end
  local steps, parts, total, weight = {}, {}, 0, 0
  for k = 1, #list - 1 do
    local from, to = list[k], list[k + 1]
    if from ~= to then
      local leg = shortest(graph, from, to)
      if not leg then
        return nil, k
      end
      local first = #steps + 1
      for _, e in ipairs(leg.steps) do
        steps[#steps + 1] = e
      end
      parts[#parts + 1] = {
        k = k,
        from = from,
        to = to,
        stop = k < #list - 1 and k or nil,
        first = first,
        last = #steps,
        totalSec = leg.totalSec,
      }
      total, weight = total + leg.totalSec, weight + leg.weight
    end
  end
  return { steps = steps, totalSec = total, weight = weight, parts = parts }
end

-- Route over list = { start, stop, ..., goal }. Returns { status = "ok", best, alternatives }, or
-- { status = "same" } when every leg stays in one place, or { status = "unreachable", leg, legs,
-- from, to } naming the first leg without a connection. An alternative is the whole route
-- recomputed without one transport of the best route.
function TL.RouteVia(data, o, list)
  local graphs = {}
  local best, bad = viaRoute(data, o, list, nil, graphs)
  if not best then
    return { status = "unreachable", leg = bad, legs = #list - 1, from = list[bad], to = list[bad + 1] }
  end
  if #best.steps == 0 then
    return { status = "same" }
  end
  local seen = { [signature(best)] = true }
  local alternatives = {}
  local used, order = {}, {}
  for _, s in ipairs(best.steps) do
    if not used[s.mode] then
      used[s.mode] = true
      order[#order + 1] = s.mode
    end
  end
  for _, mode in ipairs(order) do
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
  return { status = "ok", best = best, alternatives = alternatives }
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
