-- Zone crossings without WoW API: where roads and passes lead from one zone into the next, kept as
-- fractions of the world map (MapWorld.WORLD_ID) so one crossing holds on both sides, whichever zone map shows
-- it. Pairs are keyed "slugA|slugB" (alphabetical). Four sources: shipped (Data\ZoneCrossings.lua), recorded
-- while walking (ns.db.zoneCrossings.recorded), set by hand (.items) and deleted (.hidden). Merging, the
-- states of an arrow, the conversion to zone coordinates, the pairs that have a path in the travel data,
-- the recorder's decision, and the text export and import all live here; the arrows are drawn by
-- ZoneBorderLogic and the two map layers.
-- Data\ZoneCrossings.lua: { version = 1, pairs = { ["a|b"] = { { x, y }, ... } }, hidden = { "a|b|n", ... } } with
-- the estimated arrows deleted for good (they act like the player's own deletions).
-- ns.db.zoneCrossings: { v = 1, recorded = { [key] = { { x, y, n }, ... } }, items = { [key] = { { x, y }, ... } },
-- hidden = { [id] = true } } with the ids below.
local _, ns = ...

local ZCL = {}
ns.ZoneCrossingLogic = ZCL

ZCL.VERSION = 1
-- Export text: ZC2 separates the fields with ";" (a "|" in text shown by the client starts a colour, texture or
-- link code and swallows the next letter), ZC1 with "|" and is only read.
ZCL.HEADER = "ZC2"
ZCL.LEGACY_HEADER = "ZC1"
-- Points closer than this (share of the world map width) are one crossing.
ZCL.MERGE = 0.005
ZCL.MAX_PER_PAIR = 6
-- The recorder: a sample of the player every second, a crossing counts when the sample before the change of
-- zone is younger than PROBE_GAP seconds and no more than MAX_STEP yards away from the first one in the new zone.
ZCL.PROBE_GAP = 4
ZCL.MAX_STEP = 100
-- Offset of the estimated ids seen from the second zone of a pair, above any number of arrows per neighbour.
ZCL.SIDE = 10
-- Two points that agree to the 4 decimals of an id.
local SAME = 1.5e-4

local RANK = { recorded = 1, shipped = 2, user = 3 }
local STATE_OF_RANK = { "recorded", "shipped", "user" }
local SOURCE_STATE = { recorded = "recorded", user = "user", shipped = "shipped" }

ZCL.revision = 0
local muted = false

-- Names and keys -----------------------------------------------------------------------------

local function slug(v)
  return type(v) == "string" and v ~= "" and not v:find("|", 1, true) and v or nil
end

-- "a|b" for two different zone slugs, alphabetical (plain byte order, the slugs are ASCII); nil otherwise.
function ZCL.PairKey(a, b)
  if not (slug(a) and slug(b)) or a == b then
    return nil
  end
  return a < b and a .. "|" .. b or b .. "|" .. a
end

-- Both zones of a pair key, nil unless it is a valid key in alphabetical order.
function ZCL.SplitKey(key)
  local a, b = tostring(key):match("^([^|]+)|([^|]+)$")
  if a and ZCL.PairKey(a, b) == key then
    return a, b
  end
end

function ZCL.RealId(key, x, y)
  return string.format("%s|%.4f,%.4f", key, x, y)
end

-- Id of the n-th estimated arrow of the zone view of `zone` toward `other`: the arrows seen from the
-- second zone of the pair count on from SIDE, so both views of a pair never share an id.
function ZCL.EstimateId(zone, other, n)
  local key = ZCL.PairKey(zone, other)
  return key and key .. "|" .. (zone < other and n or n + ZCL.SIDE)
end

local function unit(v)
  return type(v) == "number" and v == v and v >= 0 and v <= 1
end

-- key, kind ("real" or "estimated"), x, y (real) or n (estimated) of an id; nil when it is none.
function ZCL.ParseId(id)
  local key, rest = tostring(id):match("^([^|]+|[^|]+)|([^|]+)$")
  if not (key and ZCL.SplitKey(key)) then
    return nil
  end
  local n = rest:match("^%d+$")
  if n then
    return key, "estimated", tonumber(n)
  end
  local x, y = rest:match("^(%d*%.?%d+),(%d*%.?%d+)$")
  x, y = tonumber(x), tonumber(y)
  if unit(x) and unit(y) then
    return key, "real", x, y
  end
end

-- Frames ----------------------------------------------------------------------------------------

-- A point of a zone (fractions of its map) as fractions of the world map, given the zone's rectangle on it.
function ZCL.ToWorld(rect, x, y)
  return rect.left + x * (rect.right - rect.left), rect.top + y * (rect.bottom - rect.top)
end

-- Inverse of ToWorld; the result lies outside 0..1 for a point beyond the zone's rectangle.
function ZCL.FromWorld(rect, wx, wy)
  return (wx - rect.left) / (rect.right - rect.left), (wy - rect.top) / (rect.bottom - rect.top)
end

-- Walk links ------------------------------------------------------------------------------------

local walkMemo = setmetatable({}, { __mode = "k" })
local NONE = {}

-- The zone pairs that a walk link of the travel data joins: { ["a|b"] = true }. A link end is a node (its zone is
-- the field z, a zone node is its own zone) or a zone slug.
function ZCL.WalkPairs(travel)
  if type(travel) ~= "table" then
    return {}
  end
  local links = type(travel.links) == "table" and travel.links or NONE
  local hit = walkMemo[travel]
  if hit and hit.links == links and hit.n == #links then
    return hit.set
  end
  local zoneOfNode, zones = {}, {}
  for _, z in ipairs(type(travel.zones) == "table" and travel.zones or {}) do
    zones[z.s] = true
  end
  for _, n in ipairs(type(travel.nodes) == "table" and travel.nodes or {}) do
    zoneOfNode[n.s] = n.z or (n.k == "zone" and n.s) or nil
  end
  local function zoneOf(s)
    return zoneOfNode[s] or (zones[s] and s) or nil
  end
  local set = {}
  for _, link in ipairs(links) do
    local key = link.m == "walk" and ZCL.PairKey(zoneOf(link.from), zoneOf(link.to))
    if key then
      set[key] = true
    end
  end
  walkMemo[travel] = { links = links, n = #links, set = set }
  return set
end

-- Stores -----------------------------------------------------------------------------------------

-- A section of ns.db.zoneCrossings, created when missing or damaged.
local function section(name)
  local db = ns.db
  if type(db) ~= "table" then
    return {}
  end
  if type(db.zoneCrossings) ~= "table" then
    db.zoneCrossings = { v = ZCL.VERSION }
  end
  local z = db.zoneCrossings
  if type(z[name]) ~= "table" then
    z[name] = {}
  end
  return z[name]
end

local function shippedPairs()
  local data = ns.Data and ns.Data.ZoneCrossings
  if type(data) == "table" and data.version == ZCL.VERSION and type(data.pairs) == "table" then
    return data.pairs
  end
  return {}
end

-- The estimated arrows deleted in the shipped data as { [id] = true }.
local function shippedHidden()
  local data = ns.Data and ns.Data.ZoneCrossings
  local set = {}
  if type(data) == "table" and data.version == ZCL.VERSION and type(data.hidden) == "table" then
    for _, id in ipairs(data.hidden) do
      set[id] = true
    end
  end
  return set
end

-- Tells the layers that draw crossings: the revision changes the memo of ZoneBorderLogic.ForView.
local function touch()
  ZCL.revision = ZCL.revision + 1
  if not muted and ns.Emit then
    ns.Emit("FG_ZONECROSS_CHANGED")
  end
end
ZCL.Touch = touch

-- The valid points of a stored list as { x, y, n, src, ref } (ref: the stored entry, to find it again).
local function readList(list, src, out)
  for _, raw in ipairs(type(list) == "table" and list or {}) do
    local x, y = type(raw) == "table" and (raw[1] or raw.x), type(raw) == "table" and (raw[2] or raw.y)
    if unit(x) and unit(y) then
      local n = type(raw.n) == "number" and raw.n >= 1 and raw.n or 1
      out[#out + 1] = { x = x, y = y, n = n, rank = RANK[src == "items" and "user" or src], src = src, ref = raw }
    end
  end
  return out
end

local function hiddenPoints(key)
  local out, prefix = {}, key .. "|"
  for id in pairs(section("hidden")) do
    if type(id) == "string" and id:sub(1, #prefix) == prefix then
      local k, kind, x, y = ZCL.ParseId(id)
      if k == key and kind == "real" then
        out[#out + 1] = { x = x, y = y }
      end
    end
  end
  return out
end

local function close(a, b, reach)
  return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 < reach * reach
end

local function anyClose(list, p, reach)
  for _, q in ipairs(list) do
    if close(q, p, reach) then
      return true
    end
  end
  return false
end

-- Merging ------------------------------------------------------------------------------------------

local function byPlace(a, b)
  if a.x ~= b.x then
    return a.x < b.x
  end
  return a.y < b.y
end

-- The crossings of a list of points { x, y, n, rank, ... }: points next to a deleted one go, the rest is
-- grouped (a point joins the first group whose centre is nearer than MERGE, highest rank first, so the
-- group is placed by its highest rank and the weights n), at most MAX_PER_PAIR groups stay (highest rank,
-- then weight). Returns { x, y, n, state, members } ordered by place; members are the points of the group.
function ZCL.MergePoints(points, hidden)
  local kept = {}
  for _, p in ipairs(points) do
    if not anyClose(hidden or {}, p, SAME) then
      kept[#kept + 1] = p
    end
  end
  table.sort(kept, function(a, b)
    if a.rank ~= b.rank then
      return a.rank > b.rank
    end
    return byPlace(a, b)
  end)
  local groups = {}
  for _, p in ipairs(kept) do
    local hit
    for _, g in ipairs(groups) do
      if close(g, p, ZCL.MERGE) then
        hit = g
        break
      end
    end
    if not hit then
      groups[#groups + 1] = { x = p.x, y = p.y, n = p.n, rank = p.rank, members = { p } }
    else
      hit.members[#hit.members + 1] = p
      if p.rank == hit.rank then
        hit.x = (hit.x * hit.n + p.x * p.n) / (hit.n + p.n)
        hit.y = (hit.y * hit.n + p.y * p.n) / (hit.n + p.n)
        hit.n = hit.n + p.n
      end
    end
  end
  table.sort(groups, function(a, b)
    if a.rank ~= b.rank then
      return a.rank > b.rank
    end
    if a.n ~= b.n then
      return a.n > b.n
    end
    return byPlace(a, b)
  end)
  for i = ZCL.MAX_PER_PAIR + 1, #groups do
    groups[i] = nil
  end
  table.sort(groups, byPlace)
  for _, g in ipairs(groups) do
    g.state = STATE_OF_RANK[g.rank]
  end
  return groups
end

local function pointsOf(key)
  local out = {}
  readList(shippedPairs()[key], "shipped", out)
  readList(section("items")[key], "items", out)
  readList(section("recorded")[key], "recorded", out)
  return out
end

-- The real crossings of a pair: { x, y, state, id, members } in world fractions.
function ZCL.Real(key)
  local groups = ZCL.MergePoints(pointsOf(key), hiddenPoints(key))
  for _, g in ipairs(groups) do
    g.id = ZCL.RealId(key, g.x, g.y)
  end
  return groups
end

-- The real crossings of the zone of a view for each neighbour, in the zone coordinates of that zone:
-- { [slug] = { { x, y, state = , id = }, ... } }. Empty without the zone's rectangle on the world map
-- (zv.world), a crossing cannot be placed then.
function ZCL.ForZone(zv)
  local rect = zv and zv.world
  local out = {}
  if not rect then
    return out
  end
  for _, other in ipairs(zv.neighbors or {}) do
    local key = ZCL.PairKey(zv.zone, other)
    local real = key and ZCL.Real(key) or {}
    if #real > 0 then
      local list = {}
      for _, g in ipairs(real) do
        local x, y = ZCL.FromWorld(rect, g.x, g.y)
        list[#list + 1] = { x, y, state = g.state, id = g.id }
      end
      out[other] = list
    end
  end
  return out
end

-- The arrows of a zone view with their ids; the estimated ones deleted by the player or in the shipped data drop
-- out. Arrows are { slug, state, n (estimated), id (real) }.
function ZCL.Label(zone, arrows)
  local hidden, gone = section("hidden"), shippedHidden()
  local out = {}
  for _, a in ipairs(arrows) do
    if a.state == "estimated" then
      a.id = ZCL.EstimateId(zone, a.slug, a.n)
    end
    if not (a.id and (hidden[a.id] or gone[a.id])) then
      out[#out + 1] = a
    end
  end
  return out
end

-- What is stored: { shipped, user, recorded, hidden } as numbers of points and deleted ids, and the same per zone
-- in zones[slug] (a pair counts for both its zones).
function ZCL.Summary()
  local out = { shipped = 0, user = 0, recorded = 0, hidden = 0, zones = {} }
  local function add(key, field, n)
    local a, b = ZCL.SplitKey(key)
    if not a then
      return
    end
    out[field] = out[field] + n
    for _, zone in ipairs({ a, b }) do
      local z = out.zones[zone] or { shipped = 0, user = 0, recorded = 0, hidden = 0 }
      z[field] = z[field] + n
      out.zones[zone] = z
    end
  end
  local sources = {
    { shippedPairs(), "shipped", "shipped" },
    { section("items"), "items", "user" },
    { section("recorded"), "recorded", "recorded" },
  }
  for _, spec in ipairs(sources) do
    for key, list in pairs(spec[1]) do
      add(key, spec[3], #readList(list, spec[2], {}))
    end
  end
  for id in pairs(section("hidden")) do
    local key = ZCL.ParseId(id)
    if key then
      add(key, "hidden", 1)
    end
  end
  return out
end

-- Arrows per state: { estimated, recorded, user, shipped }.
function ZCL.Counts(arrows)
  local n = { estimated = 0, recorded = 0, user = 0, shipped = 0 }
  for _, a in ipairs(arrows) do
    n[a.state] = (n[a.state] or 0) + 1
  end
  return n
end

-- Changes -------------------------------------------------------------------------------------------

local function removeRef(list, ref)
  for i, raw in ipairs(list or {}) do
    if raw == ref then
      table.remove(list, i)
      return true
    end
  end
  return false
end

local function unhide(key, p)
  local hidden = section("hidden")
  for id in pairs(hidden) do
    local k, kind, x, y = ZCL.ParseId(id)
    if k == key and kind == "real" and close({ x = x, y = y }, p, ZCL.MERGE) then
      hidden[id] = nil
    end
  end
end

-- A crossing the player sets or an import brings ("user", or "recorded" from an import of a recording). Returns
-- true, or false and "invalid" or "full" (the pair holds MAX_PER_PAIR already).
function ZCL.Add(key, x, y, source)
  if not (ZCL.SplitKey(key) and unit(x) and unit(y)) then
    return false, "invalid"
  end
  local store = source == "recorded" and section("recorded") or section("items")
  local p = { x = x, y = y }
  unhide(key, p)
  local list = store[key] or {}
  if #list >= ZCL.MAX_PER_PAIR then
    return false, "full"
  end
  list[#list + 1] = source == "recorded" and { x = x, y = y, n = 1 } or { x = x, y = y }
  store[key] = list
  touch()
  return true
end

-- The merged crossing an id names: the one with that id, else the one nearest to the id's place.
local function findGroup(key, id, x, y)
  local found
  for _, g in ipairs(ZCL.Real(key)) do
    if g.id == id then
      return g
    end
    if not found and close(g, { x = x, y = y }, ZCL.MERGE) then
      found = g
    end
  end
  return found
end

-- Removes a crossing by the id of its arrow. A real one: its stored points go (the player's own and the
-- recorded ones) and every point of it is remembered as deleted, so nothing brings it back; an estimated
-- one is remembered by its id. Returns whether something changed.
function ZCL.Delete(id)
  local key, kind, x, y = ZCL.ParseId(id)
  if not key then
    return false
  end
  local hidden = section("hidden")
  if kind == "estimated" then
    hidden[id] = true
    touch()
    return true
  end
  local group = findGroup(key, id, x, y)
  if not group then
    return false
  end
  for _, m in ipairs(group.members) do
    if m.src ~= "shipped" then
      removeRef(section(m.src)[key], m.ref)
    end
    -- Only the player's own points can go for good; the others come back with every load without this note.
    if m.src ~= "items" then
      hidden[ZCL.RealId(key, m.x, m.y)] = true
    end
  end
  touch()
  return true
end

-- Moves the crossing of an id to a place on the world map and makes it the player's own; an estimated arrow
-- becomes a real crossing. Nothing is deleted when the new one cannot be stored. Returns true or false and the
-- reason of Add.
function ZCL.Move(id, wx, wy)
  local key, kind, x, y = ZCL.ParseId(id)
  if not (key and unit(wx) and unit(wy)) then
    return false, "invalid"
  end
  local group = kind == "real" and findGroup(key, id, x, y)
  local gives = false
  for _, m in ipairs(group and group.members or {}) do
    gives = gives or m.src == "items"
  end
  if #(section("items")[key] or {}) >= ZCL.MAX_PER_PAIR and not gives then
    return false, "full"
  end
  if group then
    ZCL.Delete(id)
  end
  return ZCL.Add(key, wx, wy, "user")
end

-- Makes crossings of the player's own of a list { { key, x, y }, ... } (the estimated arrows of a zone, once
-- confirmed). Returns the number added.
function ZCL.Adopt(list)
  local added = 0
  for _, c in ipairs(list) do
    if ZCL.Add(c.key, c.x, c.y, "user") then
      added = added + 1
    end
  end
  return added
end

-- Forgets what the player and the recorder know about a zone: own and recorded crossings and deletions of
-- every pair that names it. Shipped crossings stay. Returns the number of removed entries.
function ZCL.ResetZone(zone)
  local removed = 0
  local function involves(key)
    local a, b = ZCL.SplitKey(key)
    return a == zone or b == zone
  end
  for _, name in ipairs({ "items", "recorded" }) do
    local store = section(name)
    for key, list in pairs(store) do
      if involves(key) then
        removed = removed + #list
        store[key] = nil
      end
    end
  end
  local hidden = section("hidden")
  for id in pairs(hidden) do
    local key = ZCL.ParseId(id)
    if key and involves(key) then
      hidden[id] = nil
      removed = removed + 1
    end
  end
  touch()
  return removed
end

-- Recording ---------------------------------------------------------------------------------------------

-- Stores a crossing the recorder saw. Returns "new" (a point of the pair), "merged" (it moved a recorded point
-- by the mean), "known" (a shipped or own point is there already), "hidden" (the player deleted it) or "full".
function ZCL.Record(key, x, y)
  if not (ZCL.SplitKey(key) and unit(x) and unit(y)) then
    return "invalid"
  end
  local p = { x = x, y = y }
  if anyClose(hiddenPoints(key), p, ZCL.MERGE) then
    return "hidden"
  end
  local list = section("recorded")[key] or {}
  for _, raw in ipairs(list) do
    if unit(raw.x) and unit(raw.y) and close(raw, p, ZCL.MERGE) then
      local n = type(raw.n) == "number" and raw.n >= 1 and raw.n or 1
      raw.x, raw.y, raw.n = (raw.x * n + x) / (n + 1), (raw.y * n + y) / (n + 1), n + 1
      touch()
      return "merged"
    end
  end
  local real = ZCL.Real(key)
  for _, g in ipairs(real) do
    if close(g, p, ZCL.MERGE) then
      return "known"
    end
  end
  if #real >= ZCL.MAX_PER_PAIR then
    return "full"
  end
  list[#list + 1] = { x = x, y = y, n = 1 }
  section("recorded")[key] = list
  touch()
  return "new"
end

function ZCL.NewTracker()
  return {}
end

-- One sample of the recorder: { t (seconds), map (UiMapID), x, y (fractions of that map), blocked (a reason
-- text while the player rides a taxi, is dead or in an instance) }. Returns the crossing { key, a, b, x, y } (x, y
-- on the world map, the middle between the last sample in the old zone and the first in the new) or nil and
-- why not: "nopos", "blocked", "start", "same", "stale", "unknown" (a zone or its rectangle is missing) or "far".
-- env: zoneOfMap(map) -> slug, worldRect(slug) -> rectangle, distance(mapA, xA, yA, mapB, xB, yB) -> yards.
function ZCL.Observe(tracker, s, env)
  local prev = tracker.last
  tracker.last = (type(s) == "table" and s.map and not s.blocked) and s or nil
  if not tracker.last then
    return nil, type(s) == "table" and s.blocked and "blocked" or "nopos"
  end
  if not prev then
    return nil, "start"
  end
  if prev.map == s.map then
    return nil, "same"
  end
  if s.t - prev.t >= ZCL.PROBE_GAP then
    return nil, "stale"
  end
  local a, b = env.zoneOfMap(prev.map), env.zoneOfMap(s.map)
  local ra, rb = a and env.worldRect(a), b and env.worldRect(b)
  local key = ZCL.PairKey(a, b)
  if not (key and ra and rb) then
    return nil, "unknown"
  end
  local yards = env.distance(prev.map, prev.x, prev.y, s.map, s.x, s.y)
  if not (type(yards) == "number" and yards <= ZCL.MAX_STEP) then
    return nil, "far"
  end
  local ax, ay = ZCL.ToWorld(ra, prev.x, prev.y)
  local bx, by = ZCL.ToWorld(rb, s.x, s.y)
  return { key = key, a = a, b = b, x = (ax + bx) / 2, y = (ay + by) / 2 }
end

-- Text export and import ----------------------------------------------------------------------------

local FIELD = ";"

-- The text form of a key or id: the "|" of the stored form becomes the field separator.
local function field(text)
  return (text:gsub("|", FIELD))
end

local function pointLine(key, x, y, source)
  return string.format("%s;%.4f;%.4f;%s", field(key), x, y, source)
end

local function idLine(id)
  return "-;" .. field(id)
end

-- "ZC2", then one line per crossing "a;b;x;y;source" (x, y on the world map, source user, recorded or shipped)
-- and "-;a;b;n" or "-;a;b;x,y" per deleted one; LF. No line holds a "|".
function ZCL.Export()
  local keys, seen = {}, {}
  for _, store in ipairs({ shippedPairs(), section("items"), section("recorded") }) do
    for key in pairs(store) do
      if not seen[key] and ZCL.SplitKey(key) then
        seen[key] = true
        keys[#keys + 1] = key
      end
    end
  end
  table.sort(keys)
  local lines = { ZCL.HEADER }
  for _, key in ipairs(keys) do
    for _, g in ipairs(ZCL.Real(key)) do
      lines[#lines + 1] = pointLine(key, g.x, g.y, g.state)
    end
  end
  local ids = {}
  for id in pairs(section("hidden")) do
    if ZCL.ParseId(id) then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    lines[#lines + 1] = idLine(id)
  end
  return table.concat(lines, "\n") .. "\n"
end

-- A crossing line from its fields: the entry { key, x, y, source }, or nil and the reason "key", "zone",
-- "coordinate" or "source". zones: optional set of the known slugs.
local function pointEntry(a, b, x, y, source, zones)
  local key = ZCL.PairKey(a, b)
  x, y = tonumber(x), tonumber(y)
  if key ~= a .. "|" .. b then
    return nil, "key"
  elseif zones and not (zones[a] and zones[b]) then
    return nil, "zone"
  elseif not (unit(x) and unit(y)) then
    return nil, "coordinate"
  elseif not SOURCE_STATE[source] then
    return nil, "source"
  end
  return { key = key, x = x, y = y, source = source }
end

-- Each reader returns the entry { key, x, y, source } or { id, key } of a line, or nil and the reason ("format",
-- "key", "zone", "coordinate", "source" or "repair"); a third result true says that the line was damaged and
-- repaired.
local function readCurrent(line, zones)
  local text = line:match("^%-;(.+)$")
  if text then
    local id = text:gsub(FIELD, "|")
    local key = ZCL.ParseId(id)
    if key then
      return { id = id, key = key }
    end
    return nil, "key"
  end
  local a, b, x, y, source = line:match("^([^;]+);([^;]+);([^;]+);([^;]+);([^;]+)$")
  if not a then
    return nil, "format"
  end
  return pointEntry(a, b, x, y, source, zones)
end

-- The source a field names; a field that lost its first letter to a swallowed "|x" names it as well (second result).
local function sourceOf(text)
  for name in pairs(SOURCE_STATE) do
    if text == name then
      return name, false
    elseif text == name:sub(2) then
      return name, true
    end
  end
end

-- The zone pair a damaged head of a ZC1 line stands for. A client reads "|t" or "|r" in shown text as a code and
-- drops it with the letter, so "ashenvale|the-barrens" turns into "ashenvalehe-barrens". head: the text before the
-- numbers; lead: a "|" stands in front of the first slug, which may be lost with the slug's first letter ("-|a|b|n").
-- Returns the pair key and whether the head was damaged, or nil and the number of readings when there is not
-- exactly one pair of known zones that fits.
local function readings(head, zones, lead)
  local found, count = {}, 0
  for a in pairs(zones) do
    for _, front in ipairs(lead and { "|" .. a, a:sub(2) } or { a }) do
      if head:sub(1, #front) == front then
        local rest = head:sub(#front + 1)
        for b in pairs(zones) do
          local key = ZCL.PairKey(a, b)
          if key == a .. "|" .. b and (rest == "|" .. b or rest == b:sub(2)) then
            count = count + (found[key] == nil and 1 or 0)
            found[key] = front ~= (lead and "|" .. a or a) or rest ~= "|" .. b
          end
        end
      end
    end
  end
  if count == 1 then
    return next(found)
  end
  return nil, count
end

local function readLegacyId(line, zones)
  local id = line:sub(1, 2) == "-|" and line:sub(3)
  local key = id and ZCL.ParseId(id)
  if key then
    return { id = id, key = key }
  end
  local rest = line:sub(2)
  local head, tail = rest:match("^(.*)|(%d+)$")
  if not head then
    head, tail = rest:match("^(.*)|(%d*%.?%d+,%d*%.?%d+)$")
  end
  if not (zones and head) then
    return nil, "key"
  end
  local pair, damaged = readings(head, zones, true)
  if not pair then
    return nil, "repair"
  end
  local fixed = pair .. "|" .. tail
  if not ZCL.ParseId(fixed) then
    return nil, "key"
  end
  return { id = fixed, key = pair }, nil, damaged
end

local function readLegacyPoint(line, zones)
  local a, b, x, y, source = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
  if a then
    return pointEntry(a, b, x, y, source, zones)
  end
  local head, wx, wy, tail = line:match("^(.*)|([%d.]+)|([%d.]+)|?(%a+)$")
  if not (zones and head) then
    return nil, "format"
  end
  local name, lost = sourceOf(tail)
  local pair, damaged = readings(head, zones, false)
  if not (pair and name) then
    return nil, "repair"
  end
  local first, second = ZCL.SplitKey(pair)
  local entry, reason = pointEntry(first, second, wx, wy, name, zones)
  return entry, reason, entry and (damaged or lost) or nil
end

local function readLegacy(line, zones)
  if line:sub(1, 1) == "-" then
    return readLegacyId(line, zones)
  end
  return readLegacyPoint(line, zones)
end

local READERS = { [ZCL.HEADER] = readCurrent, [ZCL.LEGACY_HEADER] = readLegacy }

-- The lines of an export as { entries, invalid, repaired }: entry { key, x, y, source } or { id }; invalid { line,
-- reason, text } with the reasons of the readers; repaired { line, before, after } with the line as ZC2 text.
-- zones: optional set of the known slugs; ZC1 lines are repaired with it only.
local function parse(text, zones)
  local entries, invalid, repaired, read = {}, {}, {}, nil
  local index = 0
  for raw in (tostring(text):gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do
    index = index + 1
    local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      if not read then
        read = READERS[line]
        if not read then
          return nil, "header"
        end
      else
        local entry, reason, damaged = read(line, zones)
        if not entry then
          invalid[#invalid + 1] = { line = index, reason = reason, text = line }
        else
          entries[#entries + 1] = entry
          if damaged then
            local after = entry.id and idLine(entry.id) or pointLine(entry.key, entry.x, entry.y, entry.source)
            repaired[#repaired + 1] = { line = index, before = line, after = after }
          end
        end
      end
    end
  end
  if not read then
    return nil, "header"
  end
  return { entries = entries, invalid = invalid, repaired = repaired }
end

local function copy(v)
  if type(v) ~= "table" then
    return v
  end
  local out = {}
  for k, item in pairs(v) do
    out[k] = copy(item)
  end
  return out
end

-- Applies the entries to the store; returns the counts.
local function applyEntries(entries)
  local result = { added = 0, changed = 0, unchanged = 0, full = 0 }
  local gone = shippedHidden()
  for _, e in ipairs(entries) do
    if e.id then
      local hidden = section("hidden")
      if hidden[e.id] or gone[e.id] then
        result.unchanged = result.unchanged + 1
      else
        hidden[e.id] = true
        result.changed = result.changed + 1
      end
    else
      local nearest, best
      for _, g in ipairs(ZCL.Real(e.key)) do
        local d = math.sqrt((g.x - e.x) ^ 2 + (g.y - e.y) ^ 2)
        if not best or d < best then
          nearest, best = g, d
        end
      end
      if nearest and best <= SAME then
        result.unchanged = result.unchanged + 1
      else
        local target = e.source == "recorded" and "recorded" or "items"
        if nearest and best < ZCL.MERGE then
          for _, m in ipairs(nearest.members) do
            if m.src == target then
              removeRef(section(target)[e.key], m.ref)
            end
          end
        end
        local ok = ZCL.Add(e.key, e.x, e.y, e.source == "recorded" and "recorded" or "user")
        if ok then
          local key = nearest and best < ZCL.MERGE and "changed" or "added"
          result[key] = result[key] + 1
        else
          result.full = result.full + 1
        end
      end
    end
  end
  return result
end

-- Reads an export (ZC2, or the older ZC1 whose damaged lines are repaired when exactly one reading fits). mode
-- "preview" only counts (on a copy of the store), "apply" stores. Returns { added, changed, unchanged, full,
-- repaired = { { line, before, after } }, invalid = { { line, reason, text } } }, or nil and "header" when the text
-- does not start with a header line. Lines that cannot be read are listed in invalid and skipped.
-- zones: optional set of known zone slugs, other zones make a line invalid.
function ZCL.Import(text, mode, zones)
  local parsed, why = parse(text, zones)
  if not parsed then
    return nil, why
  end
  -- A preview runs the same code on a copy of the store, so its counts are the ones the import will give.
  local real = ns.db and ns.db.zoneCrossings
  if mode ~= "apply" and ns.db then
    ns.db.zoneCrossings = copy(real)
  end
  muted = true
  local ok, result = pcall(applyEntries, parsed.entries)
  muted = false
  if mode ~= "apply" and ns.db then
    ns.db.zoneCrossings = real
  end
  if not ok then
    error(result, 0)
  end
  result.invalid, result.repaired = parsed.invalid, parsed.repaired
  if mode == "apply" then
    touch()
  end
  return result
end
