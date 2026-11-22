-- Walking navigation data: decoding of the per-tile blobs of the ForeverGuides_Nav_* data add-ons
-- (docs/NAVGRID-FORMAT.md) and the cached source the router reads from. The pure part (Terrain, Graph, NewSource)
-- needs no game API; Load / Source at the end load the data add-on of a continent on demand, never in combat.
local _, ns = ...

local ND = {}
ns.NavData = ND

ND.ADDONS = { [0] = "ForeverGuides_Nav_EK", [1] = "ForeverGuides_Nav_Kalimdor", [2991] = "ForeverGuides_Nav_Zephras" }
-- Lifts and elevators the walk grid cannot know: the router joins the two ends of each with a fixed cost (ride plus
-- average wait, seconds) and draws the ride as a straight segment. Per map: { id, n = { de, en }, a = { x, y, z } (lower
-- end), b = upper end, ride, wait }, positions as UnitPosition (x north, y west).
local function lift(id, de, en, a, b, ride, wait)
  return { id = id, n = { de = de, en = en }, a = a, b = b, ride = ride, wait = wait }
end
ND.LIFTS = {
  [0] = {
    lift("undercity-ruins-1", "Unterstadt, Aufzug 1", "Undercity lift 1", { 1594.8, 188.5, -41.4 }, { 1594.8, 196.9, 55.2 }, 4, 8),
    lift("undercity-ruins-2", "Unterstadt, Aufzug 2", "Undercity lift 2", { 1544.8, 240.6, -41.4 }, { 1553.1, 240.6, 55.2 }, 4, 8),
    lift("undercity-ruins-3", "Unterstadt, Aufzug 3", "Undercity lift 3", { 1596.9, 292.7, -41.4 }, { 1596.9, 284.4, 55.2 }, 4, 8),
    lift("cauldron-1", "Der Kessel, Aufzug 1", "The Cauldron lift 1", { -6905.2, -1207.3, 178.1 }, { -6901, -1207.3, 240.1 }, 8, 8),
    lift("cauldron-2", "Der Kessel, Aufzug 2", "The Cauldron lift 2", { -6905.2, -1340.6, 212.8 }, { -6896.9, -1338.5, 239.9 }, 8, 8),
  },
  [1] = {
    lift("freewind-1", "Freiwindposten, Aufzug 1", "Freewind Post lift 1", { -5401, -2507.3, -40.6 }, { -5401, -2501, 88.9 }, 10, 8),
    lift("freewind-2", "Freiwindposten, Aufzug 2", "Freewind Post lift 2", { -5378.1, -2488.5, -40.6 }, { -5384.4, -2486.5, 88.9 }, 10, 8),
    lift("great-lift-1", "Großer Aufzug 1", "Great Lift 1", { -4665.6, -1824, -43.9 }, { -4661.5, -1828.1, 85.3 }, 10, 8),
    lift("great-lift-2", "Großer Aufzug 2", "Great Lift 2", { -4674, -1851, -44.2 }, { -4667.7, -1851, 85.3 }, 10, 8),
    lift("thunder-bluff-1", "Donnerfels, Aufzug Nord 1", "Thunder Bluff lift north 1", { -1024, -28.1, 69.3 }, { -1032.3, -28.1, 140.7 }, 10, 15),
    lift("thunder-bluff-2", "Donnerfels, Aufzug Nord 2", "Thunder Bluff lift north 2", { -1036.5, -53.1, 69.3 }, { -1040.6, -49, 140.7 }, 10, 15),
    lift("thunder-bluff-3", "Donnerfels, Aufzug Süd 1", "Thunder Bluff lift south 1", { -1284.4, 192.7, 68.6 }, { -1286.5, 186.5, 130 }, 10, 15),
    lift("thunder-bluff-4", "Donnerfels, Aufzug Süd 2", "Thunder Bluff lift south 2", { -1311.5, 184.4, 68.6 }, { -1305.2, 182.3, 130.3 }, 10, 15),
  },
}
ND.TERRAIN_CACHE = 24 -- decoded tiles kept per map (about 150 KB each)
ND.GRAPH_CACHE = 256 -- decoded entrance lists kept per map
ND.EDGE = 14 -- bytes of an edge record

local floor, abs = math.floor, math.abs
local byte = string.byte

-- Directions of a step: +x, -x, +y, -y, +x+y, +x-y, -x+y, -x-y (x runs north, y west, as UnitPosition).
ND.DX = { [0] = 1, -1, 0, 0, 1, 1, -1, -1 }
ND.DY = { [0] = 0, 0, 1, -1, 1, -1, 1, -1 }
local DX, DY = ND.DX, ND.DY

-- DIRS[mask] = the directions of the bits of an open-steps byte, ascending.
local DIRS = {}
for mask = 0, 255 do
  local list, rest = {}, mask
  for d = 0, 7 do
    if rest % 2 == 1 then
      list[#list + 1] = d
    end
    rest = floor(rest / 2)
  end
  DIRS[mask] = list
end
ND.DIRS = DIRS

local function zag(v)
  return v % 2 == 0 and v / 2 or -(v + 1) / 2
end

-- n-byte big-endian numbers of a plane: value i (1-based) of the plane that starts at pos with n values.
local function plane2(s, pos, n, i)
  local a, b = byte(s, pos + i - 1), byte(s, pos + n + i - 1)
  return a * 256 + b
end

local function plane3(s, pos, n, i)
  return (byte(s, pos + i - 1) * 256 + byte(s, pos + n + i - 1)) * 256 + byte(s, pos + 2 * n + i - 1)
end

-- Kind byte of a node: value * 32 + ground class. value 0 blocked, 1 ground, 2 water.
function ND.Kind(t, node)
  return byte(t.raw, t.kindAt + node + 1)
end

function ND.Walkable(t, node)
  return byte(t.raw, t.kindAt + node + 1) >= 32
end

-- A terrain blob (decompressed) as a tile table: { raw, cells, n (base cells), nf (floors), fcell[i], fz[i] (floor i,
-- 1-based, its cell and height in yards), first[cell] / count[cell] (the node of a cell's first floor and their
-- number), kindAt / openAt (positions in raw) }. nil on a blob that is too short.
function ND.Terrain(raw, cells)
  if type(raw) ~= "string" or #raw < 10 then
    return nil
  end
  local n = cells * cells
  local nf, w = byte(raw, 1) * 256 + byte(raw, 2), byte(raw, 3) * 256 + byte(raw, 4)
  local na = (byte(raw, 5) * 256 + byte(raw, 6)) * 256 + byte(raw, 7)
  local nl = (byte(raw, 8) * 256 + byte(raw, 9)) * 256 + byte(raw, 10)
  local pos = 11
  local t = { raw = raw, cells = cells, n = n, nf = nf, w = w, na = na, nl = nl, kindAt = pos - 1 }
  pos = pos + n + nf
  t.openAt = pos - 1
  pos = pos + n
  t.zAt = pos
  pos = pos + 2 * w
  t.fcellAt, t.fhAt, t.stepAt = pos, pos + 2 * nf, pos + 4 * nf
  pos = pos + 5 * nf
  t.linkAt = pos
  pos = pos + 5 * nl
  t.arcAt = pos
  if #raw < pos + 8 * na - 1 then
    return nil
  end
  local fcell, fz, first, count = {}, {}, {}, {}
  local h = 0
  local ca, ha = t.fcellAt, t.fhAt
  for i = 1, nf do
    local c = byte(raw, ca + i - 1) * 256 + byte(raw, ca + nf + i - 1)
    local v = byte(raw, ha + i - 1) * 256 + byte(raw, ha + nf + i - 1)
    h = h + (v % 2 == 0 and v / 2 or -(v + 1) / 2)
    fcell[i], fz[i] = c, h
    if first[c] then
      count[c] = count[c] + 1
    else
      first[c], count[c] = n + i - 1, 1
    end
  end
  t.fcell, t.fz, t.first, t.count = fcell, fz, first, count
  return t
end

-- The tile's cell of a node.
function ND.CellOf(t, node)
  if node < t.n then
    return node
  end
  return t.fcell[node - t.n + 1]
end

-- Heights of the base cells (yards, nil where blocked), decoded on first use.
local function baseHeights(t)
  local z = t.z
  if z then
    return z
  end
  z = {}
  local raw, n, c, w = t.raw, t.n, t.cells, t.w
  local kindAt, zAt = t.kindAt, t.zAt
  local at, last = 0, 0
  for cell = 0, n - 1 do
    if byte(raw, kindAt + cell + 1) >= 32 then
      at = at + 1
      local pred = last
      if cell % c > 0 and z[cell] then
        pred = z[cell] / 2
      elseif cell >= c and z[cell - c + 1] then
        pred = z[cell - c + 1] / 2
      end
      local v = byte(raw, zAt + at - 1) * 256 + byte(raw, zAt + w + at - 1)
      last = pred + (v % 2 == 0 and v / 2 or -(v + 1) / 2)
      z[cell + 1] = last * 2
    end
  end
  t.z = z
  return z
end

-- Height of a node in yards.
function ND.Height(t, node)
  if node < t.n then
    return baseHeights(t)[node + 1]
  end
  return t.fz[node - t.n + 1]
end

-- The node on cell for a layer: 0 the base surface, i > 0 the ith floor up, -1 the surface nearest height h.
local function surface(t, cell, layer, h)
  if layer == 0 then
    return byte(t.raw, t.kindAt + cell + 1) >= 32 and cell or nil
  end
  local first, count = t.first[cell], t.count[cell] or 0
  if layer > 0 then
    return first and layer <= count and first + layer - 1 or nil
  end
  local best, gap
  if byte(t.raw, t.kindAt + cell + 1) >= 32 then
    best, gap = cell, abs(baseHeights(t)[cell + 1] - h)
  end
  for node = first or 0, (first or 0) + count - 1 do
    local g = abs(t.fz[node - t.n + 1] - h)
    if not gap or g < gap then
      best, gap = node, g
    end
  end
  return best
end
ND.Surface = surface

-- The extra moves of a tile (floor steps, floor links, one-way arcs) as t.mo[node] = { to, yards, to, yards, ... }
-- and, for a search out of the goal, t.mi[node] the same backwards. Built on first use. cs is the cell size.
function ND.Moves(t, cs)
  if t.mo then
    return t.mo, t.mi
  end
  local mo, mi, seen = {}, {}, {}
  local n, c, raw = t.n, t.cells, t.raw
  local diag = cs * 1.41421356
  local function add(a, b, yards)
    local key = a * 262144 + b
    if seen[key] then
      return
    end
    seen[key] = true
    local o = mo[a]
    if not o then
      o = {}
      mo[a] = o
    end
    o[#o + 1], o[#o + 2] = b, yards
    local i = mi[b]
    if not i then
      i = {}
      mi[b] = i
    end
    i[#i + 1], i[#i + 2] = a, yards
  end
  local function stepTo(node, d, layer)
    local cell = ND.CellOf(t, node)
    local tx, ty = floor(cell / c) + DX[d], cell % c + DY[d]
    if tx < 0 or ty < 0 or tx >= c or ty >= c then
      return nil
    end
    return surface(t, tx * c + ty, layer, ND.Height(t, node))
  end
  for f = 1, t.nf do
    local node = n + f - 1
    local list = DIRS[byte(raw, t.stepAt + f - 1)]
    for i = 1, #list do
      local d = list[i]
      local len = d >= 4 and diag or cs
      local target = stepTo(node, d, -1)
      if target then
        add(node, target, len)
        if target < n then
          add(target, node, len)
        end
      end
    end
  end
  local at, prev = t.linkAt, 0
  for i = 1, t.nl do
    prev = prev + zag(plane3(raw, at, t.nl, i))
    local d, layer = byte(raw, at + 3 * t.nl + i - 1), byte(raw, at + 4 * t.nl + i - 1)
    local walkable = prev < n and byte(raw, t.kindAt + prev + 1) >= 32 or (prev >= n and prev < n + t.nf)
    if walkable then
      local target = stepTo(prev, d, layer)
      if target then
        local len = d >= 4 and diag or cs
        add(prev, target, len)
        if prev >= n and target < n then
          add(target, prev, len)
        end
      end
    end
  end
  local na, aAt = t.na, t.arcAt
  local from = 0
  for i = 1, na do
    from = from + plane3(raw, aAt, na, i)
    local to = from + zag(plane3(raw, aAt + 3 * na, na, i))
    add(from, to, plane2(raw, aAt + 6 * na, na, i) / 4)
  end
  t.mo, t.mi = mo, mi
  return mo, mi
end

-- An entrance blob as { s, n, cell[i], node[i] (0-based entrance i), estart[i] (index of its first edge, 0-based),
-- edges at ND.EDGE bytes each from e0 }.
function ND.Graph(raw)
  if type(raw) ~= "string" or #raw < 2 then
    return nil
  end
  local n = byte(raw, 1) * 256 + byte(raw, 2)
  local cell, node, estart = {}, {}, {}
  local pos, e = 3, 0
  for i = 0, n - 1 do
    local a, b, c, d, f, deg = byte(raw, pos, pos + 5)
    cell[i], node[i], estart[i] = a * 256 + b, (c * 256 + d) * 256 + f, e
    e = e + deg
    pos = pos + 6
  end
  estart[n] = e
  if #raw < pos - 1 + e * ND.EDGE then
    return nil
  end
  return { s = raw, n = n, cell = cell, node = node, estart = estart, e0 = pos }
end

-- A source for the router over the tiles of one map: header fields (cx0, cy0, nx, ny, cells, swim) and tiles[k] = {
-- terrain blob, entrance blob}; inflate(blob) gives the decompressed bytes. terrain(k) / graph(k) decode on demand
-- and keep the most recent ones.
function ND.NewSource(map, head, tiles, inflate)
  local src = {
    map = map,
    cx0 = head.cx0,
    cy0 = head.cy0,
    nx = head.nx,
    ny = head.ny,
    cells = head.cells,
    swim = head.swim or 3,
    tile = head.tile or 1600 / 3,
    tiles = tiles,
  }
  src.cs = src.tile / src.cells
  local function cache(slot, limit, build)
    local store, order = {}, {}
    return function(k)
      local hit = store[k]
      if hit ~= nil then
        return hit or nil
      end
      local entry = tiles[k]
      local value = entry and build(inflate(entry[slot])) or false
      store[k] = value
      order[#order + 1] = k
      if #order > limit then
        store[table.remove(order, 1)] = nil
      end
      return value or nil
    end
  end
  src.terrain = cache(1, ND.TERRAIN_CACHE, function(raw)
    return raw and ND.Terrain(raw, src.cells)
  end)
  src.graph = cache(2, ND.GRAPH_CACHE, ND.Graph)
  return src
end

-- Game part ----------------------------------------------------------------------------------------------------

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- zlib bytes of a base64 blob: the client's codec; nil without it.
function ND.Inflate(blob)
  local util = rawget(_G, "C_EncodingUtil")
  if type(util) ~= "table" or not util.DecodeBase64 or not util.DecompressString then
    return nil
  end
  local packed = util.DecodeBase64(blob)
  return packed and util.DecompressString(packed, Enum.CompressionMethod.Zlib)
end

local attempted = {}

-- Is the data add-on of the map loaded? Loads it when it is not, never in combat and once per session.
function ND.Load(map)
  local data = rawget(ns, "NavMaps")
  if data and data[map] and data[map].tiles then
    return true
  end
  local name = ND.ADDONS[map]
  local package = ns.PackageUI
  if not name or attempted[name] or inCombat() or not package or package.State(name) ~= "idle" then
    return false
  end
  local ok, reason = package.Enable(name)
  attempted[name] = reason ~= "COMBAT"
  return ok and rawget(ns, "NavMaps") ~= nil and ns.NavMaps[map] ~= nil
end

local sources = {}

-- The source of a loaded map, nil while its data is not there.
function ND.Source(map)
  local hit = sources[map]
  if hit then
    return hit
  end
  local data = rawget(ns, "NavMaps")
  local head = data and data[map]
  if not (head and head.tiles) then
    return nil
  end
  sources[map] = ND.NewSource(map, head, head.tiles, ND.Inflate)
  return sources[map]
end

-- Test seam.
function ND.Reset()
  sources = {}
  attempted = {}
end
