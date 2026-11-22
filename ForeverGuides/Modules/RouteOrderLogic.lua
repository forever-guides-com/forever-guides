-- Best order of the stops of a route. Pure logic over a cost matrix: node 1 is the start, node m the
-- goal (both fixed), nodes 2..m-1 are the stops. cost[i][j] is the time from node i to node j
-- (math.huge when there is no connection); the matrix may be asymmetric (timetables, flights).
local _, ns = ...

local RO = {}
ns.RouteOrderLogic = RO

-- Up to this many stops every order is tried (7! = 5040 paths with pruning), above it a heuristic runs.
RO.EXACT_MAX = 7

local EPS = 1e-9

-- Total cost of start, order..., goal.
function RO.PathCost(cost, m, order)
  local total, prev = 0, 1
  for _, k in ipairs(order) do
    total = total + cost[prev][k]
    prev = k
  end
  return total + cost[prev][m]
end

local function identity(m)
  local order = {}
  for k = 2, m - 1 do
    order[#order + 1] = k
  end
  return order
end

-- Depth first over all orders; only a strictly cheaper path replaces the best one, so the given
-- order wins every tie and the result never depends on iteration luck.
local function exact(cost, m)
  local best = identity(m)
  local bestCost = RO.PathCost(cost, m, best)
  local cur, used = {}, {}
  local stops = m - 2
  local function walk(prev, acc)
    if acc >= bestCost - EPS then
      return
    end
    if #cur == stops then
      local total = acc + cost[prev][m]
      if total < bestCost - EPS then
        bestCost = total
        best = { unpack(cur) }
      end
      return
    end
    for k = 2, m - 1 do
      if not used[k] then
        used[k] = true
        cur[#cur + 1] = k
        walk(k, acc + cost[prev][k])
        cur[#cur] = nil
        used[k] = nil
      end
    end
  end
  walk(1, 0)
  return best, bestCost
end

-- Nearest neighbor from the start, then 2-opt (reverse a stretch while that makes the path cheaper).
local function heuristic(cost, m)
  local order, used, prev = {}, {}, 1
  for _ = 1, m - 2 do
    local pick
    for k = 2, m - 1 do
      if not used[k] and (not pick or cost[prev][k] < cost[prev][pick]) then
        pick = k
      end
    end
    used[pick] = true
    order[#order + 1] = pick
    prev = pick
  end
  local best = RO.PathCost(cost, m, order)
  local improved = true
  while improved do
    improved = false
    for i = 1, #order - 1 do
      for j = i + 1, #order do
        local try = { unpack(order) }
        local a, b = i, j
        while a < b do
          try[a], try[b] = try[b], try[a]
          a, b = a + 1, b - 1
        end
        local total = RO.PathCost(cost, m, try)
        if total < best - EPS then
          order, best, improved = try, total, true
        end
      end
    end
  end
  return order, best
end

-- Returns order (the stop nodes 2..m-1 in the best sequence found), its total cost, and the
-- cost of the given order. With fewer than two stops there is nothing to change.
function RO.Solve(cost, m)
  local given = identity(m)
  local givenCost = RO.PathCost(cost, m, given)
  if m - 2 < 2 then
    return given, givenCost, givenCost
  end
  local order, total
  if m - 2 <= RO.EXACT_MAX then
    order, total = exact(cost, m)
  else
    order, total = heuristic(cost, m)
    -- The input order is a candidate as well: a good hand-made order is never made worse.
    if givenCost <= total + EPS then
      order, total = given, givenCost
    end
  end
  return order, total, givenCost
end
