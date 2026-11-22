-- Walking router over the tiles of ForeverGuides_Nav_* (NavData): a hierarchical search. Inside the start and goal
-- tile a local search prices every step by the ground class of the node it enters (style fastest / balanced / roads,
-- WalkPathLogic.STYLES, hostile town hubs dearer); between tiles an A* walks the entrance graph whose edges carry
-- their baked price. The tile sequence is then refined to grid steps and pulled straight by line of sight, never over
-- worse ground. A job is a coroutine: it yields every few milliseconds when it has a deadline (NR.Resume).
-- Pure part, no game API. WalkLogic wraps it for the planner.
local _, ns = ...

local NR = {}
ns.NavRouter = NR

NR.SPEED = 7 -- yards per second running
NR.SWIM_SPEED = 4.7
NR.STEEP_SPEED = 4.5
NR.SNAP = 6 -- cells searched around a start or goal point for ground
NR.ZTOL = 10 -- a point stands on a surface within this height (yards)
NR.HOSTILE = 20 -- price factor of a hostile town hub
NR.GRAPH_FACTOR = 0.8 -- baked edges price at least 0.8 per yard: the entrance search's distance bound
NR.SNAP_WEIGHT = 10 -- price of a yard between a point and the node it stands on: dearer than any ground but a hostile town
NR.CHECK = 128 -- expansions between two looks at the clock
NR.MAX_POINTS = 500 -- points of a drawn path

local floor, sqrt, abs, min, huge = math.floor, math.sqrt, math.abs, math.min, math.huge
local byte = string.byte
local P = ns.WalkPathLogic
local ND = ns.NavData
local DX, DY, DIRS = ND.DX, ND.DY, ND.DIRS
local DIAG = 1.41421356
local DIRINDEX = {}
for d = 0, 7 do
  DIRINDEX[(DX[d] + 1) * 3 + DY[d] + 1] = d
end
local POW = { [0] = 1, 2, 4, 8, 16, 32, 64, 128 }

-- Price factor per kind byte (value * 32 + class) for a style and a player profile ("Alliance", "Horde" or nil), the
-- smallest factor of the style as the search's distance bound. Water costs swim times more; blocked kinds are nil.
function NR.CostTable(style, profile, swim)
  local mult = P.STYLES[P.Style(style)].mult
  local smallest = huge
  for _, m in ipairs(mult) do
    smallest = min(smallest, m)
  end
  local cm = {}
  for b = 0, 255 do
    local value, class = floor(b / 32), b % 32
    if value >= 1 then
      local m = mult[class % 8 + 1] or 1
      local hub = class - class % 8
      if (profile == "Horde" and hub % 16 >= 8) or (profile == "Alliance" and hub % 32 >= 16) then
        m = m * NR.HOSTILE
      end
      cm[b] = value == 2 and m * (swim or 3) or m
    end
  end
  return cm, smallest
end

-- Seconds per yard on a kind byte.
local function slowness(kind)
  if floor(kind / 32) == 2 then
    return 1 / NR.SWIM_SPEED
  end
  if kind % 8 == P.CLASS.STEEP then
    return 1 / NR.STEEP_SPEED
  end
  return 1 / NR.SPEED
end

-- Heap ---------------------------------------------------------------------------------------------------------

local function hpush(a, k, v)
  local hk, hv = a.hk, a.hv
  local i = a.hn + 1
  a.hn = i
  while i > 1 do
    local p = floor(i / 2)
    if hk[p] <= k then
      break
    end
    hk[i], hv[i] = hk[p], hv[p]
    i = p
  end
  hk[i], hv[i] = k, v
end

local function hpop(a)
  local hk, hv, n = a.hk, a.hv, a.hn
  local k, v = hk[1], hv[1]
  local lk, lv = hk[n], hv[n]
  n = n - 1
  a.hn = n
  if n > 0 then
    local i = 1
    while true do
      local c = i * 2
      if c > n then
        break
      end
      if c < n and hk[c + 1] < hk[c] then
        c = c + 1
      end
      if hk[c] >= lk then
        break
      end
      hk[i], hv[i] = hk[c], hv[c]
      i = c
    end
    hk[i], hv[i] = lk, lv
  end
  return k, v
end

local function newArena()
  return { g = {}, par = {}, st = {}, dn = {}, ep = 0, hk = {}, hv = {}, hn = 0 }
end

-- Job ----------------------------------------------------------------------------------------------------------

-- The path of the search that just ended: { { node, g }, ... } from a source to node.
local function trace(a, node)
  local out, n = {}, 0
  while node do
    n = n + 1
    out[n] = { node, a.g[node] }
    node = a.par[node]
  end
  for i = 1, floor(n / 2) do
    out[i], out[n + 1 - i] = out[n + 1 - i], out[i]
  end
  return out
end

local function newJob(src, opts)
  local profile = opts.profile
  local cm, smallest = NR.CostTable(opts.style, profile, src.swim)
  return {
    src = src,
    cm = cm,
    minm = smallest,
    cs = src.cs,
    arena = newArena(),
    ops = 0,
    clock = nil,
    deadline = nil,
    profile = profile,
  }
end

local function tick(j)
  j.ops = j.ops + 1
  if j.ops >= NR.CHECK then
    j.ops = 0
    if j.deadline and j.clock() >= j.deadline then
      coroutine.yield()
    end
  end
end

-- Local search in tile T. srcs: { { node, g0 }, ... }. goal: stop at this node (A*). want / wantN: stop when wantN
-- of the nodes in the set want are settled (a tree to the entrances). back: walk the moves backwards (a search out of
-- the goal; steps are priced by the node nearer the goal). pens: { [node] = price } of goal nodes, the search ends
-- at the cheapest sum of way and price and returns it as its second value. Results stay in the job's arena until the
-- next search.
local function localSearch(j, T, srcs, goal, back, want, wantN, pens)
  local a = j.arena
  a.ep = a.ep + 1
  a.hn = 0
  local ep, g, par, st, dn = a.ep, a.g, a.par, a.st, a.dn
  local C, N, raw, kindAt, openAt = T.cells, T.n, T.raw, T.kindAt, T.openAt
  local cm, cs, minm = j.cm, j.cs, j.minm
  local ORTH, DIAGL = cs, cs * DIAG
  local ext
  if T.nf > 0 or T.na > 0 then
    local mo, mi = ND.Moves(T, cs)
    ext = back and mi or mo
  end
  local gcx, gcy
  if goal then
    local gc = ND.CellOf(T, goal)
    gcx, gcy = floor(gc / C), gc % C
  end
  local function bound(node)
    if not goal then
      return 0
    end
    local cell = node < N and node or T.fcell[node - N + 1]
    local dx, dy = abs(floor(cell / C) - gcx), abs(cell % C - gcy)
    return (dx > dy and dx + 0.41421356 * dy or dy + 0.41421356 * dx) * cs * minm
  end
  for _, s in ipairs(srcs) do
    local node = s[1]
    if st[node] ~= ep or s[2] < g[node] then
      g[node], par[node], st[node] = s[2], false, ep
      hpush(a, s[2] + bound(node), node)
    end
  end
  local left = wantN or 0
  local bestTotal, bestNode = huge, nil
  while a.hn > 0 do
    local f, u = hpop(a)
    if pens and f >= bestTotal then
      break
    end
    if dn[u] ~= ep then
      dn[u] = ep
      if u == goal then
        return true, u
      end
      local pen = pens and pens[u]
      if pen and g[u] + pen < bestTotal then
        bestTotal, bestNode = g[u] + pen, u
      end
      if want and want[u] then
        left = left - 1
        if left <= 0 then
          return true
        end
      end
      tick(j)
      local gu = g[u]
      local cu = cm[byte(raw, kindAt + u + 1)]
      if u < N then
        local m = byte(raw, openAt + u + 1)
        if m ~= 0 then
          local lx = floor(u / C)
          local ly = u - lx * C
          local list = DIRS[m]
          for i = 1, #list do
            local d = list[i]
            local nx, ny = lx + DX[d], ly + DY[d]
            if nx >= 0 and ny >= 0 and nx < C and ny < C then
              local v = nx * C + ny
              local mult = back and cu or cm[byte(raw, kindAt + v + 1)]
              if mult then
                local ng = gu + (d >= 4 and DIAGL or ORTH) * mult
                if st[v] ~= ep or ng < g[v] then
                  g[v], par[v], st[v] = ng, u, ep
                  hpush(a, ng + bound(v), v)
                end
              end
            end
          end
        end
      end
      local list = ext and ext[u]
      if list then
        for i = 1, #list, 2 do
          local v = list[i]
          local mult = back and cu or cm[byte(raw, kindAt + v + 1)]
          if mult then
            local ng = gu + list[i + 1] * mult
            if st[v] ~= ep or ng < g[v] then
              g[v], par[v], st[v] = ng, u, ep
              hpush(a, ng + bound(v), v)
            end
          end
        end
      end
    end
  end
  return bestNode ~= nil, bestNode
end

-- Cells ---------------------------------------------------------------------------------------------------------

local function cellAt(j, gx, gy)
  local src = j.src
  local C = src.cells
  if gx < 0 or gy < 0 or gx >= src.nx * C or gy >= src.ny * C then
    return nil
  end
  local kx, ky = floor(gx / C), floor(gy / C)
  local k = kx * src.ny + ky
  local T = src.terrain(k)
  if not T then
    return nil
  end
  return T, (gx - kx * C) * C + (gy - ky * C), k
end

-- Global cell of a node of tile k.
local function globalCell(src, T, k, node)
  local C = src.cells
  local cell = ND.CellOf(T, node)
  local kx = floor(k / src.ny)
  local ky = k - kx * src.ny
  return kx * C + floor(cell / C), ky * C + cell % C
end

-- The nodes a point may stand on within NR.SNAP cells: all surfaces (within NR.ZTOL of the height h when it is
-- known) with their price, the distance plus twice the height gap, times NR.SNAP_WEIGHT. All of them take part in
-- the search, so an end in a closed pocket, under a floor or on a ledge simply loses against the ground beside it.
-- -> { { gx, gy, T, k, node, price }, ... } by price.
local function snap(j, x, y, h)
  local src = j.src
  local cs = src.cs
  local gx0, gy0 = floor((x - src.cx0 * src.tile) / cs), floor((y - src.cy0 * src.tile) / cs)
  local all = {}
  for dx = -NR.SNAP, NR.SNAP do
    for dy = -NR.SNAP, NR.SNAP do
      local gx, gy = gx0 + dx, gy0 + dy
      local T, lc, k = cellAt(j, gx, gy)
      if T then
        local cx = src.cx0 * src.tile + (gx + 0.5) * cs
        local cy = src.cy0 * src.tile + (gy + 0.5) * cs
        local dist = sqrt((cx - x) ^ 2 + (cy - y) ^ 2)
        local function consider(node)
          local gap = h and abs(ND.Height(T, node) - h) or 0
          if not h or gap <= NR.ZTOL then
            all[#all + 1] = { gx, gy, T, k, node, (dist + 2 * gap) * NR.SNAP_WEIGHT }
          end
        end
        if ND.Walkable(T, lc) then
          consider(lc)
        end
        if T.first[lc] then
          for node = T.first[lc], T.first[lc] + T.count[lc] - 1 do
            consider(node)
          end
        end
      end
    end
  end
  table.sort(all, function(p, q)
    return p[6] < q[6]
  end)
  return all
end

-- Entrance search ----------------------------------------------------------------------------------------------

local function edgeCost(G, e, profile)
  local p = G.e0 + e * ND.EDGE
  local off, t1, t2, a1, a2, a3, h1, h2, h3, n1, n2, n3 = byte(G.s, p, p + 11)
  local cost
  if profile == "Alliance" then
    cost = (a1 * 256 + a2) * 256 + a3
  elseif profile == "Horde" then
    cost = (h1 * 256 + h2) * 256 + h3
  else
    cost = (n1 * 256 + n2) * 256 + n3
  end
  return off, t1 * 256 + t2, cost
end

-- A* over the entrances from the seeds { [entrance key] = cost } of the start tiles to the goal tiles, whose entrances
-- are priced by goalCost[key]. Key = tile * 4096 + entrance index. goalGx / goalGy: the goal point in cells.
-- -> total, key of the last entrance, parent map.
local function entranceRoute(j, seeds, goalCost, goalGx, goalGy)
  local src = j.src
  local C, ny, cs = src.cells, src.ny, src.cs
  local a = newArena()
  local best, bestKey = huge, nil
  local function bound(k, i)
    local G = src.graph(k)
    local kx = floor(k / ny)
    local ky = k - kx * ny
    local cell = G.cell[i]
    local gx, gy = kx * C + floor(cell / C), ky * C + cell % C
    return sqrt((gx - goalGx) ^ 2 + (gy - goalGy) ^ 2) * cs * NR.GRAPH_FACTOR
  end
  local parent = {}
  for key, c in pairs(seeds) do
    a.g[key], parent[key] = c, false
    hpush(a, c + bound(floor(key / 4096), key % 4096), key)
  end
  local done = {}
  while a.hn > 0 do
    local f, key = hpop(a)
    if f >= best then
      break
    end
    if not done[key] then
      done[key] = true
      tick(j)
      local k, i = floor(key / 4096), key % 4096
      local G = src.graph(k)
      local gk = a.g[key]
      local c = goalCost[key]
      if c and gk + c < best then
        best, bestKey = gk + c, key
      end
      for e = G.estart[i], G.estart[i + 1] - 1 do
        local off, t, cost = edgeCost(G, e, j.profile)
        local k2 = k + (floor(off / 3) - 1) * ny + off % 3 - 1
        local G2 = src.graph(k2)
        if G2 and t < G2.n then
          local key2 = k2 * 4096 + t
          local ng = gk + cost
          if not done[key2] and (not a.g[key2] or ng < a.g[key2]) then
            a.g[key2], parent[key2] = ng, key
            hpush(a, ng + bound(k2, t), key2)
          end
        end
      end
    end
  end
  return best, bestKey, parent
end

-- Chain -------------------------------------------------------------------------------------------------------

local function entry(src, T, k, node, g)
  local gx, gy = globalCell(src, T, k, node)
  return { gx, gy, g, node, k }
end

-- Appends the nodes of a local path (skipping its first when the chain already ends there), costs offset by base.
local function append(chain, src, T, k, path, base)
  for i, p in ipairs(path) do
    if not (i == 1 and #chain > 0) then
      chain[#chain + 1] = entry(src, T, k, p[1], base + p[2])
    end
  end
end

local function lastCost(chain)
  return #chain > 0 and chain[#chain][3] or 0
end

-- A local search in tile k from the sources from ({ { node, price }, ... }) to the node to, or with pens to the cheapest
-- of its goal nodes, appended to chain; false when no way.
local function leg(j, chain, k, from, to, pens)
  local T = j.src.terrain(k)
  if not T then
    return false
  end
  local ok, node = localSearch(j, T, from, to, false, nil, nil, pens)
  if not ok then
    return false
  end
  append(chain, j.src, T, k, trace(j.arena, node), lastCost(chain))
  return true
end

-- Smoothing and measuring ----------------------------------------------------------------------------------------

local function lineWalker(j, check)
  local src = j.src
  local C, cm = src.cells, j.cm
  local curK, curT
  local function at(gx, gy)
    local kx, ky = floor(gx / C), floor(gy / C)
    if gx < 0 or gy < 0 then
      return nil
    end
    local k = kx * src.ny + ky
    if k ~= curK then
      curK, curT = k, (kx < src.nx and ky < src.ny) and src.terrain(k) or nil
    end
    if not curT then
      return nil
    end
    return curT, (gx - kx * C) * C + (gy - ky * C)
  end
  -- cost, yards, seconds of the straight run of cells between two cells; nil when check and a step is closed
  return function(ax, ay, bx, by)
    local cost, yards, seconds = 0, 0, 0
    local cs = src.cs
    local open = P.Line(ax, ay, bx, by, function(x, y, nx, ny)
      local dx, dy = nx - x, ny - y
      local T, lc = at(x, y)
      local T2, lc2 = at(nx, ny)
      if not (T and T2) then
        return false
      end
      if check then
        local d = DIRINDEX[(dx + 1) * 3 + dy + 1]
        if floor(byte(T.raw, T.openAt + lc + 1) / POW[d]) % 2 == 0 then
          return false
        end
      end
      local kind = byte(T2.raw, T2.kindAt + lc2 + 1)
      local mult = cm[kind]
      if not mult then
        return false
      end
      local len = (dx ~= 0 and dy ~= 0) and cs * DIAG or cs
      cost = cost + len * mult
      yards = yards + len
      seconds = seconds + len * slowness(kind)
    end)
    if open == false then
      return nil
    end
    return cost, yards, seconds
  end
end

-- Smooths the base-surface runs of the chain, returns the kept nodes.
local function smooth(j, chain)
  local walk = lineWalker(j, true)
  local function lineCost(ax, ay, bx, by)
    return (walk(ax, ay, bx, by))
  end
  local out, n, i = {}, #chain, 1
  local N = j.src.cells * j.src.cells
  while i <= n do
    if chain[i][4] < N then
      local last = i
      while last < n and chain[last + 1][4] < N do
        last = last + 1
      end
      local run = {}
      for q = i, last do
        run[#run + 1] = chain[q]
      end
      run = P.Smooth(P.Collapse(run), lineCost, function()
        tick(j)
      end)
      for _, e in ipairs(run) do
        out[#out + 1] = e
      end
      i = last + 1
    else
      out[#out + 1] = chain[i]
      i = i + 1
    end
  end
  return out
end

-- Yards of the drawn lines and the seconds of the ground under them.
local function measure(j, nodes)
  local walk = lineWalker(j, false)
  local src = j.src
  local yards, seconds = 0, 0
  for i = 2, #nodes do
    local a, b = nodes[i - 1], nodes[i]
    local long = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) * src.cs
    local c, y, s = walk(a[1], a[2], b[1], b[2])
    if c and y > 0 then
      s = s * long / y
    else
      s = long / NR.SPEED
    end
    yards, seconds = yards + long, seconds + s
  end
  return yards, seconds
end

-- Run ------------------------------------------------------------------------------------------------------------

local function fail(why, opts)
  return { why = why, style = P.Style(opts.style) }
end

-- The candidates of one end by tile: { list = { { k, T, srcs = { { node, price } }, pens = { [node] = price } } },
-- map = { [k] = group } }.
local function byTile(cands)
  local out = { list = {}, map = {} }
  for _, c in ipairs(cands) do
    local g = out.map[c[4]]
    if not g then
      g = { k = c[4], T = c[3], srcs = {}, pens = {} }
      out.map[c[4]] = g
      out.list[#out.list + 1] = g
    end
    g.srcs[#g.srcs + 1] = { c[5], c[6] }
    g.pens[c[5]] = c[6]
  end
  return out
end

-- Prices of the entrances of every tile group that a search from (or, back, to) its candidates settles:
-- { [entrance key] = cost }.
local function entranceCosts(j, groups, back)
  local src, out = j.src, {}
  for _, grp in ipairs(groups.list) do
    local G = src.graph(grp.k)
    if G and G.n > 0 then
      local want = {}
      for i = 0, G.n - 1 do
        want[G.node[i]] = true
      end
      localSearch(j, grp.T, grp.srcs, nil, back, want, G.n)
      local a = j.arena
      for i = 0, G.n - 1 do
        local node = G.node[i]
        if a.dn[node] == a.ep and a.st[node] == a.ep then
          out[grp.k * 4096 + i] = a.g[node]
        end
      end
    end
  end
  return out
end

-- One search over all candidate nodes of both ends at once: the cheapest way from any start node to any goal node,
-- priced with the distance of each node from its point.
local function attempt(j, x1, y1, x2, y2, opts, from, to)
  local src = j.src
  local starts, goals = byTile(from), byTile(to)
  local best, direct, route = huge, nil, nil
  for _, S in ipairs(starts.list) do
    local G = goals.map[S.k]
    if G then
      local ok, node = localSearch(j, S.T, S.srcs, nil, false, nil, nil, G.pens)
      if ok and j.arena.g[node] + G.pens[node] < best then
        best = j.arena.g[node] + G.pens[node]
        direct = { k = S.k, T = S.T, path = trace(j.arena, node) }
      end
    end
  end
  if not (direct and best < src.cs * 6) then
    local seeds = entranceCosts(j, starts, false)
    local goalCost = entranceCosts(j, goals, true)
    if next(seeds) and next(goalCost) then
      local cs = src.cs
      local gx, gy = (x2 - src.cx0 * src.tile) / cs - 0.5, (y2 - src.cy0 * src.tile) / cs - 0.5
      local total, lastKey, parent = entranceRoute(j, seeds, goalCost, gx, gy)
      if lastKey and total < best then
        best, direct = total, nil
        local keys, key = {}, lastKey
        while key do
          table.insert(keys, 1, key)
          key = parent[key]
        end
        route = keys
      end
    end
  end
  local chain
  if route then
    chain = {}
    local first = route[1]
    local fk, fi = floor(first / 4096), first % 4096
    if not leg(j, chain, fk, starts.map[fk].srcs, src.graph(fk).node[fi]) then
      return fail("nopath", opts)
    end
    for q = 2, #route do
      local pk, pi = floor(route[q - 1] / 4096), route[q - 1] % 4096
      local ck, ci = floor(route[q] / 4096), route[q] % 4096
      local Gp, Gc = src.graph(pk), src.graph(ck)
      if pk == ck then
        if not leg(j, chain, ck, { { Gp.node[pi], 0 } }, Gc.node[ci]) then
          return fail("nopath", opts)
        end
      else
        local T = src.terrain(ck)
        if not T then
          return fail("nopath", opts)
        end
        local e = entry(src, T, ck, Gc.node[ci], 0)
        local prev = chain[#chain]
        local hop = sqrt((e[1] - prev[1]) ^ 2 + (e[2] - prev[2]) ^ 2) * src.cs
        e[3] = prev[3] + hop * (j.cm[byte(T.raw, T.kindAt + Gc.node[ci] + 1)] or 1)
        chain[#chain + 1] = e
      end
    end
    local lk, li = floor(route[#route] / 4096), route[#route] % 4096
    if not leg(j, chain, lk, { { src.graph(lk).node[li], 0 } }, nil, goals.map[lk].pens) then
      return fail("nopath", opts)
    end
  elseif direct then
    chain = {}
    append(chain, src, direct.T, direct.k, direct.path, 0)
  else
    return fail("nopath", opts)
  end
  local nodes = smooth(j, chain)
  local yards, seconds = measure(j, nodes)
  local pts = {}
  for i, e in ipairs(nodes) do
    local T = src.terrain(e[5])
    pts[i] = {
      x = src.cx0 * src.tile + (e[1] + 0.5) * src.cs,
      y = src.cy0 * src.tile + (e[2] + 0.5) * src.cs,
      z = T and ND.Height(T, e[4]) or nil,
      uiMap = src.map,
    }
  end
  pts[1] = { x = x1, y = y1, z = pts[1] and pts[1].z, uiMap = src.map }
  if #pts == 1 then
    pts[2] = { x = x2, y = y2, uiMap = src.map }
  else
    pts[#pts] = { x = x2, y = y2, z = pts[#pts].z, uiMap = src.map }
  end
  return {
    seconds = seconds,
    yards = yards,
    cost = best,
    source = "grid",
    style = P.Style(opts.style),
    pts = not opts.noPath and P.Simplify(pts, NR.MAX_POINTS, src.cs / 2) or nil,
    tiles = route and #route or 1,
  }
end

-- The best way between the ground next to the two points.
local function walkLeg(j, x1, y1, x2, y2, opts)
  local from, to = snap(j, x1, y1, opts.z1), snap(j, x2, y2, opts.z2)
  if #from == 0 or #to == 0 then
    return fail("outside", opts)
  end
  return attempt(j, x1, y1, x2, y2, opts, from, to)
end

local function legOpts(opts, z1, z2)
  return { style = opts.style, profile = opts.profile, noPath = opts.noPath, z1 = z1, z2 = z2 }
end

local function dist(x1, y1, x2, y2)
  return sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

-- The two walks joined by one ride: the portal's ends are marked on their points, the ride is the straight segment
-- between them.
local function joined(L, p, q, A, B, opts)
  local pts
  if A.pts and B.pts then
    pts = {}
    for _, e in ipairs(A.pts) do
      pts[#pts + 1] = e
    end
    pts[#pts].lift = L.id
    local first = #pts + 1
    for _, e in ipairs(B.pts) do
      pts[#pts + 1] = e
    end
    pts[first].lift = L.id
  end
  local ride = L.ride + L.wait
  return {
    seconds = A.seconds + B.seconds + ride,
    yards = A.yards + B.yards + sqrt(dist(p[1], p[2], q[1], q[2]) ^ 2 + (q[3] - p[3]) ^ 2),
    cost = A.cost + B.cost + ride * NR.SPEED,
    source = "grid",
    style = P.Style(opts.style),
    pts = pts,
    tiles = A.tiles + B.tiles,
    lifts = { { id = L.id, n = L.n, ride = L.ride, wait = L.wait } },
  }
end

-- Direct walk or through one lift (ND.LIFTS of the map), whichever is cheaper. A lift is only tried when the straight
-- distances to its ends plus its ride could still beat the best so far.
local function viaLifts(j, x1, y1, x2, y2, opts, best)
  local cands = {}
  for _, L in ipairs(ND.LIFTS[j.src.map] or {}) do
    for _, dir in ipairs({ { L.a, L.b }, { L.b, L.a } }) do
      local p, q = dir[1], dir[2]
      local ride = (L.ride + L.wait) * NR.SPEED
      local low = (dist(x1, y1, p[1], p[2]) + dist(q[1], q[2], x2, y2)) * NR.GRAPH_FACTOR + ride
      cands[#cands + 1] = { L = L, p = p, q = q, low = low, ride = ride }
    end
  end
  table.sort(cands, function(c, d)
    return c.low < d.low
  end)
  local bestCost = best.source == "grid" and best.cost or huge
  for _, c in ipairs(cands) do
    if c.low >= bestCost then
      break
    end
    local A = walkLeg(j, x1, y1, c.p[1], c.p[2], legOpts(opts, opts.z1, c.p[3]))
    if A.source == "grid" and A.cost + c.ride < bestCost then
      local B = walkLeg(j, c.q[1], c.q[2], x2, y2, legOpts(opts, c.q[3], opts.z2))
      if B.source == "grid" and A.cost + c.ride + B.cost < bestCost then
        best = joined(c.L, c.p, c.q, A, B, opts)
        bestCost = best.cost
      end
    end
  end
  return best
end

local function run(j, x1, y1, x2, y2, opts)
  local best = walkLeg(j, x1, y1, x2, y2, opts)
  if best.why == "outside" or not ND.LIFTS[j.src.map] then
    return best
  end
  return viaLifts(j, x1, y1, x2, y2, opts, best)
end

-- A job for a walk from (x1, y1) to (x2, y2) over src (ND.NewSource). opts: style, profile ("Alliance" / "Horde"),
-- z1 / z2 (heights of the ends), noPath.
function NR.NewJob(src, x1, y1, x2, y2, opts)
  opts = opts or {}
  local j = newJob(src, opts)
  j.co = coroutine.create(function()
    return run(j, x1, y1, x2, y2, opts)
  end)
  return j
end

-- Runs the job for about budget ms by clock (no limit without). -> done, result.
function NR.Resume(j, clock, budget)
  j.clock = clock
  j.deadline = clock and budget and clock() + budget or nil
  local ok, out = coroutine.resume(j.co)
  if not ok then
    return true, { why = "error", detail = out }
  end
  if coroutine.status(j.co) == "dead" then
    return true, out
  end
  return false
end

-- The whole answer at once.
function NR.Find(src, x1, y1, x2, y2, opts)
  local j = NR.NewJob(src, x1, y1, x2, y2, opts)
  local _, out = NR.Resume(j)
  return out
end
