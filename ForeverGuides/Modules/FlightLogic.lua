-- Flight times without WoW API: name matching of flight masters (game name to ns.Data.Travel
-- node), duration of a hop from the travel data or from times measured in game
-- (ns.db.flightTimes), and the sum over the hops of a route. Missing hops are never guessed, the
-- result then says "at least". The game side lives in Modules/FlightRoute.lua.
local _, ns = ...
local L = ns.L

local FL = {}
ns.FlightLogic = FL

ns.AddLocale("enUS", {
  ["flight.approx"] = "approx. %s",
  ["flight.atLeast"] = "at least %s",
  ["flight.unknown"] = "unknown",
})
ns.AddLocale("deDE", {
  ["flight.approx"] = "ca. %s",
  ["flight.atLeast"] = "mind. %s",
  ["flight.unknown"] = "unbekannt",
})

-- A flight outside these limits is a login, a death or a stuck client, not a flight time.
FL.MIN_SECONDS = 5
FL.MAX_SECONDS = 1200
FL.MAX_ENTRIES = 400
-- Measured means of fewer flights than this still count as approximate.
FL.MIN_SAMPLES = 3

local ARTICLES = { "the", "der", "die", "das" }
-- Game names (normalized) that the travel data spells differently: the client shows the zone for
-- Nighthaven and a translation of Tainted Foothills that the data does not have.
local ALIASES = { moonglade = "nighthaven", besudeltesvorgebirge = "tainted-foothills" }
local APPROX_SOURCE = { estimate = true, reported = true }

local function travelData()
  return ns.Data and ns.Data.Travel
end

-- Names ----------------------------------------------------------------------------------------

-- The part behind the first comma ("Orgrimmar, Durotar"), or nil.
function FL.zonePart(name)
  if type(name) ~= "string" then
    return nil
  end
  local zone = name:match(",%s*(.-)%s*$")
  return zone ~= "" and zone or nil
end

-- Leftover flight points of the client that carry a "zzOLD" prefix are never real destinations.
function FL.isObsolete(name)
  return type(name) == "string" and name:lower():find("^zzold") ~= nil
end

-- Comparison key: no zone suffix, folded umlauts and case, no leading article, no spaces or
-- punctuation, so "The Crossroads, The Barrens" and "Kreuzungen" differ only by language.
function FL.normalize(name)
  if type(name) ~= "string" then
    return ""
  end
  local text = ns.SearchLogic.fold(name:match("^([^,]*)"))
  text = text:gsub("\226\128[\152\153\156\157]", "'")
  for _, article in ipairs(ARTICLES) do
    local rest = text:match("^" .. article .. "%s+(.+)$")
    if rest then
      text = rest
      break
    end
  end
  return (text:gsub("[%s%p%c]", ""))
end

-- Lookup tables over the travel data, built once per data table.
local cache = setmetatable({}, { __mode = "k" })

local RANK = { official = 4, classic = 3, reported = 2, estimate = 1 }

local function addLink(links, from, to, link)
  local key = from .. ">" .. to
  local old = links[key]
  if not old or (RANK[link.cf] or 0) > (RANK[old.cf] or 0) then
    links[key] = link
  end
end

local function index(data)
  local idx = cache[data]
  if idx then
    return idx
  end
  idx = { byId = {}, byName = {}, links = {}, out = {}, zoneKeys = {}, flightIds = {} }
  for _, z in ipairs(data.zones or {}) do
    local keys = { [FL.normalize((z.s:gsub("-", " ")))] = true }
    for _, name in pairs(z.n or {}) do
      keys[FL.normalize(name)] = true
    end
    idx.zoneKeys[z.s] = keys
  end
  -- Both directions unless the link says bi = false; an explicit link wins over a mirrored one.
  for _, l in ipairs(data.links or {}) do
    if l.m == "flight" and l.from and l.to and l.d then
      idx.flightIds[l.from], idx.flightIds[l.to] = true, true
      idx.out[l.from] = true
      addLink(idx.links, l.from, l.to, l)
    end
  end
  for _, l in ipairs(data.links or {}) do
    if l.m == "flight" and l.from and l.to and l.d and l.bi ~= false then
      local key = l.to .. ">" .. l.from
      idx.out[l.to] = true
      if not idx.links[key] then
        idx.links[key] = l
      end
    end
  end
  for _, node in ipairs(data.nodes or {}) do
    if node.k == "flightMaster" or idx.flightIds[node.s] then
      idx.byId[node.s] = node
      idx.flightIds[node.s] = true
      local seen = {}
      for _, name in pairs(node.n or {}) do
        local key = FL.normalize(name)
        if key ~= "" and not seen[key] then
          seen[key] = true
          idx.byName[key] = idx.byName[key] or {}
          table.insert(idx.byName[key], node.s)
        end
      end
    end
  end
  for key, id in pairs(ALIASES) do
    if idx.byId[id] then
      local ids = idx.byName[key] or {}
      idx.byName[key] = ids
      local known = false
      for _, other in ipairs(ids) do
        known = known or other == id
      end
      if not known then
        ids[#ids + 1] = id
      end
    end
  end
  for _, ids in pairs(idx.byName) do
    table.sort(ids)
  end
  cache[data] = idx
  return idx
end

-- Test seam: number of our nodes and how many of them have flight
-- connections.
function FL.coverage(data)
  data = data or travelData()
  local idx = index(data)
  local total, linked = 0, 0
  for id in pairs(idx.byId) do
    total = total + 1
    linked = linked + (idx.out[id] and 1 or 0)
  end
  return total, linked
end

-- Maps a game flight point to one of our nodes. confidence: "exact" (name and zone agree),
-- "name" (one node of that name, zone absent or different), "ambiguous" (several nodes, the zone
-- does not decide) or "none". The zone comes from the argument or from the text behind a comma.
function FL.match(name, zone, data)
  if FL.isObsolete(name) then
    return { confidence = "none", candidates = {} }
  end
  local idx = index(data or travelData() or { nodes = {}, links = {} })
  local key = FL.normalize(name)
  local list = key ~= "" and idx.byName[key] or nil
  if not list then
    return { confidence = "none", candidates = {} }
  end
  local zoneKey = FL.normalize(zone or FL.zonePart(name))
  local hits = {}
  if zoneKey ~= "" then
    for _, id in ipairs(list) do
      local keys = idx.zoneKeys[idx.byId[id].z]
      if keys and keys[zoneKey] then
        hits[#hits + 1] = id
      end
    end
  end
  if #hits == 1 then
    return { id = hits[1], node = idx.byId[hits[1]], confidence = "exact", candidates = list }
  end
  if #list == 1 then
    return { id = list[1], node = idx.byId[list[1]], confidence = "name", candidates = list }
  end
  return { confidence = "ambiguous", candidates = list }
end

-- Learned times ----------------------------------------------------------------------------------

local function timesTable(create)
  local db = ns.db
  if not db then
    return nil
  end
  if type(db.flightTimes) ~= "table" then
    if not create then
      return nil
    end
    db.flightTimes = {}
  end
  return db.flightTimes
end

-- Mean seconds and sample count of a measured route key, or nil.
function FL.learned(routeKey, times)
  local e = (times or timesTable(false) or {})[routeKey]
  if type(e) == "table" and type(e.n) == "number" and e.n > 0 and type(e.sum) == "number" then
    return e.sum / e.n, e.n
  end
end

-- Stores one measured flight. Returns true, or false and the reason.
function FL.record(routeKey, seconds)
  if type(routeKey) ~= "string" or routeKey == "" then
    return false, "key"
  end
  if type(seconds) ~= "number" or seconds ~= seconds or seconds < FL.MIN_SECONDS or seconds > FL.MAX_SECONDS then
    return false, "range"
  end
  local times = timesTable(true)
  if not times then
    return false, "store"
  end
  local e = times[routeKey]
  if type(e) ~= "table" then
    local count, weakest, weakestN = 0, nil, math.huge
    for key, other in pairs(times) do
      count = count + 1
      local n = type(other) == "table" and tonumber(other.n) or 0
      if n < weakestN or (n == weakestN and tostring(key) < tostring(weakest)) then
        weakest, weakestN = key, n
      end
    end
    -- Full: the least measured route makes room.
    if count >= FL.MAX_ENTRIES then
      times[weakest] = nil
    end
    e = { n = 0, sum = 0, min = seconds, max = seconds, last = seconds }
    times[routeKey] = e
  end
  e.n = (tonumber(e.n) or 0) + 1
  e.sum = (tonumber(e.sum) or 0) + seconds
  e.last = seconds
  e.min = math.min(tonumber(e.min) or seconds, seconds)
  e.max = math.max(tonumber(e.max) or seconds, seconds)
  return true
end

-- Durations -------------------------------------------------------------------------------------

-- One hop from node id to node id: { seconds, source, n } or nil. Order of trust: official data,
-- measured mean, classic or reported data, estimate.
function FL.hop(from, to, data, times)
  if not (from and to) then
    return nil
  end
  local link = index(data or travelData() or { nodes = {}, links = {} }).links[from .. ">" .. to]
  if link and link.cf == "official" then
    return { seconds = link.d, source = "official" }
  end
  local mean, n = FL.learned(from .. ">" .. to, times)
  if mean then
    return { seconds = mean, source = "learned", n = n }
  end
  if link then
    return { seconds = link.d, source = link.cf or "estimate" }
  end
end

-- Key of a whole route "id>id>id" over start, stops and destination, nil when a node is unknown.
-- One hop gives the key of that hop.
function FL.routeKey(hops)
  local ids = {}
  for i, h in ipairs(hops or {}) do
    if not h.to or (i == 1 and not h.from) then
      return nil
    end
    if i == 1 then
      ids[1] = h.from
    end
    ids[#ids + 1] = h.to
  end
  return #ids >= 2 and table.concat(ids, ">") or nil
end

-- hops: { { from = id|nil, to = id|nil }, ... }. A hop without a known duration is no guess:
-- seconds sums the known ones, unknown counts the others, approx marks estimated or thinly
-- measured parts. parts has one entry per hop (source "unknown" without seconds). A route of
-- several hops that was flown and measured as a whole (FlightTimerLogic) uses that mean instead
-- (measured = true).
function FL.estimateRoute(hops, data, times)
  local total, unknown, approx, parts = 0, 0, false, {}
  for _, h in ipairs(hops or {}) do
    local r = FL.hop(h.from, h.to, data, times)
    if r then
      total = total + r.seconds
      approx = approx or APPROX_SOURCE[r.source] == true or (r.source == "learned" and r.n < FL.MIN_SAMPLES)
    else
      unknown = unknown + 1
    end
    parts[#parts + 1] = { from = h.from, to = h.to, seconds = r and r.seconds, source = r and r.source or "unknown" }
  end
  local result = { seconds = math.floor(total + 0.5), approx = approx, parts = parts, unknown = unknown }
  local key = #(hops or {}) > 1 and FL.routeKey(hops) or nil
  local mean, n = FL.learned(key, times)
  if mean then
    result.seconds, result.approx, result.unknown, result.measured = math.floor(mean + 0.5), n < FL.MIN_SAMPLES, 0, true
  end
  return result
end

-- Format ----------------------------------------------------------------------------------------

-- "2:35" up to 59:59, "1:02:10" from one hour.
function FL.formatDuration(seconds)
  return ns.TravelLogic.FormatDuration(math.max(0, tonumber(seconds) or 0))
end

-- Route text with prefix: "ca. 2:35", "mind. 2:35", "unbekannt" (no hop known), nil without hops.
function FL.format(route)
  if not route or not route.parts or #route.parts == 0 then
    return nil
  end
  if route.unknown > 0 then
    return route.seconds > 0 and L["flight.atLeast"]:format(FL.formatDuration(route.seconds)) or L["flight.unknown"]
  end
  local text = FL.formatDuration(route.seconds)
  return route.approx and L["flight.approx"]:format(text) or text
end

-- Short text for a label: like format, but "?" when no hop has a duration.
function FL.shortText(route)
  local text = FL.format(route)
  if text and route.unknown > 0 and route.seconds <= 0 then
    return "?"
  end
  return text
end

local SOURCE_KIND =
  { learned = "measured", official = "classic", classic = "classic", reported = "estimate", estimate = "estimate" }
local KIND_RANK = { measured = 3, classic = 2, estimate = 1 }

-- Weakest source of the known hops: "measured", "classic" or "estimate", nil without a known hop.
function FL.sourceKind(route)
  if route and route.measured then
    return "measured"
  end
  local weakest
  for _, part in ipairs(route and route.parts or {}) do
    local kind = SOURCE_KIND[part.source]
    if kind and (not weakest or KIND_RANK[kind] < KIND_RANK[weakest]) then
      weakest = kind
    end
  end
  return weakest
end
