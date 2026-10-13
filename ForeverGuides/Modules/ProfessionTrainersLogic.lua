-- Profession trainers, pure side (no frames, no game calls except the zone lookup on click): merges the
-- trainers of the profession route data (listed per rank) with the trainer data file
-- (ForeverGuides_Professions/TrainerData.lua) into one entry per trainer, filters and sorts them and
-- counts the ones with a position. The data shapes are in docs/BERUFSROUTE-FORMAT.md, the page is
-- Modules/ProfessionTrainersPage.lua.
local _, ns = ...

local P = {}
ns.ProfessionTrainersLogic = P

-- Rank ids of the data in learning order.
P.RANKS = { "apprentice", "journeyman", "expert", "artisan" }

local RANK_INDEX = {}
for i, rank in ipairs(P.RANKS) do
  RANK_INDEX[rank] = i
end

local FACTION_ORDER = { A = 1, H = 2, N = 3 }

-- Two entries are the same trainer when a position of the route data lies this close (percent).
local POSITION_TOLERANCE = 3

local function nonEmpty(value)
  return type(value) == "string" and value ~= ""
end

local function list(value)
  return type(value) == "table" and value or {}
end

-- Names ------------------------------------------------------------------------------------------

-- Second UTF-8 byte (after \195) of a Latin letter with an accent -> the plain letter.
local ACCENT = {}
for b = 160, 165 do
  ACCENT[b] = "a"
end
ACCENT[167] = "c"
for b = 168, 171 do
  ACCENT[b] = "e"
end
for b = 172, 175 do
  ACCENT[b] = "i"
end
ACCENT[177] = "n"
for b = 178, 182 do
  ACCENT[b] = "o"
end
for b = 185, 188 do
  ACCENT[b] = "u"
end
ACCENT[189], ACCENT[191] = "y", "y"

local function foldAccent(second)
  local b = second:byte()
  if b == 159 then
    return ""
  end
  return ACCENT[b < 160 and b + 32 or b] or ""
end

-- Lower case, no accents, no apostrophes or punctuation, single spaces ("Tel'Athir" = "TEL’ATHIR").
function P.NormalizeName(text)
  text = tostring(text or ""):gsub("\226\128\153", ""):gsub("\195([\128-\191])", foldAccent)
  text = text:lower():gsub("'", ""):gsub("[^a-z0-9 ]", "")
  return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local TITLES = {
  doctor = true,
  doktor = true,
  dr = true,
  master = true,
  meister = true,
  meisterin = true,
  alchemist = true,
  alchimist = true,
  alchemistin = true,
  alchimistin = true,
}

-- Normalised name without a leading title ("Doctor Marsh" = "Doktor Marsh").
function P.NameKey(text)
  local key = P.NormalizeName(text)
  local first, rest = key:match("^(%S+) (.+)$")
  return first and TITLES[first] and rest or key
end

-- Zone spellings that mean the same zone of the Classic map.
local ZONE_ALIAS = {
  ["stormwind city"] = "stormwind",
  ["northern barrens"] = "the barrens",
  ["southern barrens"] = "the barrens",
  ["northern stranglethorn"] = "stranglethorn vale",
  ["cape of stranglethorn"] = "stranglethorn vale",
  hinterlands = "the hinterlands",
  ["new tinkertown"] = "dun morogh",
}

function P.ZoneKey(text)
  local key = P.NormalizeName(text)
  return ZONE_ALIAS[key] or key
end

-- "A", "H" or "N" (neutral: both factions use the trainer, also the value of an unknown field).
function P.Faction(t)
  return (t.f == "A" or t.f == "H") and t.f or "N"
end

-- Position of a trainer as fractions of the zone map (the data holds percent 0 to 100), nil, nil
-- when the data has none or it is out of range.
function P.Fractions(t)
  local x, y = t.x, t.y
  if type(x) == "number" and type(y) == "number" and x > 0 and x <= 100 and y > 0 and y <= 100 then
    return x / 100, y / 100
  end
  return nil, nil
end

-- Zone and place texts { de, en }: the place is the finer name ("Elwynn Forest, Northshire").
local function textsOf(t)
  local zone = type(t.zone) == "table" and t.zone or { de = t.locDe, en = t.loc }
  local place = { de = nonEmpty(t.locDe) and t.locDe or zone.de, en = nonEmpty(t.loc) and t.loc or zone.en }
  return zone, place
end

-- Merging ----------------------------------------------------------------------------------------

local function sortRanks(entry)
  table.sort(entry.ranks, function(a, b)
    return (RANK_INDEX[a.rank] or 99) < (RANK_INDEX[b.rank] or 99)
  end)
end

-- One entry per trainer of one profession in the route data: the same trainer on several ranks is
-- one entry (same name, faction and place).
local function collectRoutes(src, order)
  local out, byKey = {}, {}
  for _, rank in ipairs(list(list(src.data).ranks)) do
    for _, t in ipairs(list(rank.trainers)) do
      if type(t) == "table" and nonEmpty(t.n) then
        local zone, place = textsOf(t)
        local faction = P.Faction(t)
        local key = table.concat({ src.slug, t.n, faction, tostring(place.en or place.de) }, "|")
        local entry = byKey[key]
        local x, y = P.Fractions(t)
        if not entry then
          entry = {
            key = key,
            slug = src.slug,
            order = order,
            profession = src.name,
            name = t.n,
            faction = faction,
            zone = zone,
            place = place,
            ranks = {},
          }
          byKey[key] = entry
          out[#out + 1] = entry
        end
        if not entry.x and x then
          entry.x, entry.y = x, y
        end
        if not entry.mapId and type(t.mapId) == "number" then
          entry.mapId = t.mapId
        end
        local known = false
        for _, r in ipairs(entry.ranks) do
          known = known or r.rank == rank.rank
        end
        if not known and nonEmpty(rank.rank) then
          entry.ranks[#entry.ranks + 1] = { rank = rank.rank, max = tonumber(rank.max) }
        end
      end
    end
  end
  for _, entry in ipairs(out) do
    sortRanks(entry)
  end
  return out
end

local function lastWord(key)
  return key:match("(%S+)$")
end

-- Usable rows of the trainer data of one profession, each { td, zoneKey, faction, x, y, routes }.
local function dataRows(trainerData, slug)
  local all = type(trainerData) == "table" and type(trainerData.trainers) == "table" and trainerData.trainers or {}
  local out = {}
  for _, td in ipairs(list(all[slug])) do
    if type(td) == "table" and type(td.npc) == "number" and nonEmpty(td.n) then
      local x, y = P.Fractions(td)
      out[#out + 1] = {
        td = td,
        zoneKey = P.ZoneKey(type(td.zone) == "table" and (td.zone.en or td.zone.de) or ""),
        faction = P.Faction(td),
        x = x,
        y = y,
        routes = {},
        lastWords = {},
      }
      for _, name in ipairs({ td.n, td.nDe or "" }) do
        local last = lastWord(P.NameKey(name))
        if last then
          out[#out].lastWords[last] = true
        end
      end
    end
  end
  return out
end

local function compatible(a, b)
  return a == b or a == "N" or b == "N"
end

-- The row for a route entry: same normalised name (either language) and zone, a compatible
-- faction; the exact faction first, then the lowest NPC id.
local function matchByName(byName, entry)
  local key, zone = P.NameKey(entry.name), P.ZoneKey(entry.zone.en)
  if key == "" or zone == "" then
    return nil
  end
  local best
  for _, row in ipairs(byName[key] or {}) do
    if row.zoneKey == zone and compatible(row.faction, entry.faction) then
      local exact, bestExact = row.faction == entry.faction, best and best.faction == entry.faction
      if not best or (exact and not bestExact) or (exact == bestExact and row.td.npc < best.td.npc) then
        best = row
      end
    end
  end
  return best
end

-- The free row at the position of a route entry (same zone and faction, within the tolerance, the
-- same last name word), the closest first. Catches a title that is spelled differently in the two
-- lists ("Krankenschwester Neela", "Schwester Neela"); two trainers who stand side by side stay two.
local function matchByPosition(rows, taken, entry)
  local zone, last = P.ZoneKey(entry.zone.en), lastWord(P.NameKey(entry.name))
  if not P.HasPosition(entry) or zone == "" or not last then
    return nil
  end
  local best, bestDistance
  local limit = POSITION_TOLERANCE / 100
  for _, row in ipairs(rows) do
    if not taken[row] and row.x and row.zoneKey == zone and row.faction == entry.faction and row.lastWords[last] then
      local distance = math.max(math.abs(row.x - entry.x), math.abs(row.y - entry.y))
      if distance <= limit and (not bestDistance or distance < bestDistance) then
        best, bestDistance = row, distance
      end
    end
  end
  return best
end

-- The entry of a data row: the data file leads (id, position, ranks, safety); the route
-- entries it was matched to lend the finer place name, the map id and a position the data lacks.
local function fromRow(src, order, row, maxOf)
  local td = row.td
  local zone = type(td.zone) == "table" and { de = td.zone.de or td.zone.en, en = td.zone.en or td.zone.de } or {}
  local entry = {
    key = table.concat({ src.slug, "npc", td.npc }, "|"),
    slug = src.slug,
    order = order,
    profession = src.name,
    npc = td.npc,
    name = td.n,
    nameDe = nonEmpty(td.nDe) and td.nDe or nil,
    faction = row.faction,
    zone = zone,
    place = zone,
    mapId = type(td.mapId) == "number" and td.mapId or nil,
    x = row.x,
    y = row.y,
    cf = type(td.cf) == "number" and td.cf or nil,
    inf = td.inf == true or nil,
    ranks = {},
  }
  for _, r in ipairs(list(td.ranks)) do
    if RANK_INDEX[r] then
      entry.ranks[#entry.ranks + 1] = { rank = r, max = maxOf[r] }
    end
  end
  sortRanks(entry)
  for i, route in ipairs(row.routes) do
    if i == 1 then
      entry.place = route.place
    end
    if not entry.mapId then
      entry.mapId = route.mapId
    end
    if not entry.x and route.x then
      entry.x, entry.y = route.x, route.y
    end
  end
  return entry
end

-- sources: list of { slug, data (route data of the profession, nil is skipped), name = { de, en } }
-- in display order. trainerData: the table of TrainerData.lua (nil without the file). Returns one
-- entry per trainer, the same trainer on several ranks is one entry:
-- { key, slug, order, profession, name (English), nameDe, npc, cf, inf (the last three only for
-- entries of the data file), faction, zone, place, mapId, x, y (fractions or nil),
-- ranks = { { rank, max } } in learning order }.
-- A route entry joins an entry of the data file through name, zone and faction, else through a
-- position within 3 percent; ranks, position and safety then come from the data file. A route
-- entry without a partner stays as it is.
function P.Collect(sources, trainerData)
  local out = {}
  for order, src in ipairs(list(sources)) do
    local routes = collectRoutes(src, order)
    local rows = dataRows(trainerData, src.slug)
    if #rows == 0 then
      for _, entry in ipairs(routes) do
        out[#out + 1] = entry
      end
    else
      local byName = {}
      for _, row in ipairs(rows) do
        local keys = { [P.NameKey(row.td.n)] = true }
        if nonEmpty(row.td.nDe) then
          keys[P.NameKey(row.td.nDe)] = true
        end
        for key in pairs(keys) do
          byName[key] = byName[key] or {}
          byName[key][#byName[key] + 1] = row
        end
      end
      local taken, left = {}, {}
      for _, entry in ipairs(routes) do
        local row = matchByName(byName, entry)
        if row then
          taken[row] = true
          row.routes[#row.routes + 1] = entry
        else
          left[#left + 1] = entry
        end
      end
      for _, entry in ipairs(left) do
        local row = matchByPosition(rows, taken, entry)
        if row then
          taken[row] = true
          row.routes[#row.routes + 1] = entry
        else
          out[#out + 1] = entry
        end
      end
      local maxOf = {}
      for _, rank in ipairs(list(list(src.data).ranks)) do
        if nonEmpty(rank.rank) and not maxOf[rank.rank] then
          maxOf[rank.rank] = tonumber(rank.max)
        end
      end
      for _, row in ipairs(rows) do
        out[#out + 1] = fromRow(src, order, row, maxOf)
      end
    end
  end
  return out
end

-- The skill each rank is learnable up to, from the data: { { rank, max } } in learning order.
function P.RankLimits(entries)
  local seen = {}
  for _, e in ipairs(list(entries)) do
    for _, r in ipairs(e.ranks) do
      if r.max and not seen[r.rank] then
        seen[r.rank] = r.max
      end
    end
  end
  local out = {}
  for _, rank in ipairs(P.RANKS) do
    if seen[rank] then
      out[#out + 1] = { rank = rank, max = seen[rank] }
    end
  end
  return out
end

-- Own sightings -------------------------------------------------------------------------------

-- Slug of the entries whose profession could not be read at the trainer window, listed last.
P.UNKNOWN = "unknown"
local UNKNOWN_ORDER = 1000
local UNKNOWN_NAME = { de = "Beruf unbekannt", en = "Profession unknown" }

-- Rank entries { rank, max } of the rank ids a sighting saw, in learning order. The skill limit
-- stays where the data already knows it.
local function ownRanks(ids, known)
  local max = {}
  for _, r in ipairs(list(known)) do
    max[r.rank] = r.max
  end
  local out = {}
  for _, rank in ipairs(P.RANKS) do
    for _, id in ipairs(list(ids)) do
      if id == rank then
        out[#out + 1] = { rank = rank, max = max[rank] }
      end
    end
  end
  return out
end

local function sameName(e, key)
  return (nonEmpty(e.name) and P.NameKey(e.name) == key) or (nonEmpty(e.nameDe) and P.NameKey(e.nameDe) == key)
end

-- The entries a sighting belongs to: the NPC id first, else the name (in the slug of the sighting
-- when its profession is known). A name that hits several entries is no hit.
local function ownHits(entries, o)
  local byId, byName = {}, {}
  local name = P.NameKey(o.name)
  for i, e in ipairs(entries) do
    if o.prof == nil or e.slug == o.prof then
      if e.npc == o.npc then
        byId[#byId + 1] = i
      elseif sameName(e, name) then
        byName[#byName + 1] = i
      end
    end
  end
  if #byId > 0 then
    return byId
  end
  return byName
end

-- A copy of the entry with the position and ranks of the sighting. Without a position or ranks the
-- data keeps its own.
local function withOwn(e, o)
  local c = {}
  for k, v in pairs(e) do
    c[k] = v
  end
  if type(o.x) == "number" and type(o.y) == "number" then
    c.x, c.y, c.mapId = o.x, o.y, o.mapId
  elseif not c.mapId then
    c.mapId = o.mapId
  end
  if #list(o.ranks) > 0 then
    c.ranks = ownRanks(o.ranks, e.ranks)
  end
  c.npc, c.own, c.cf, c.inf = o.npc, true, 1, nil
  return c
end

local function newOwn(entries, o)
  local slug = o.prof or P.UNKNOWN
  local order, profession = UNKNOWN_ORDER, UNKNOWN_NAME
  local routes = ns.ProfessionRouteLogic
  if o.prof then
    local info = routes and routes.PROFESSIONS[o.prof]
    profession = info and { de = info.de, en = info.en } or { de = o.prof, en = o.prof }
    order = UNKNOWN_ORDER - 1
    for i, s in ipairs(routes and routes.SLUGS or {}) do
      if s == o.prof then
        order = i
      end
    end
    for _, e in ipairs(entries) do
      if e.slug == slug then
        order, profession = e.order, e.profession
        break
      end
    end
  end
  local zone = nonEmpty(o.zone) and o.zone or "?"
  local fraction = (o.faction == "A" or o.faction == "H") and o.faction or "N"
  local e = {
    key = "own|" .. o.npc,
    slug = slug,
    order = order,
    profession = profession,
    name = o.name,
    faction = fraction,
    zone = { de = zone, en = zone },
    place = { de = zone, en = zone },
    mapId = o.mapId,
    ranks = ownRanks(o.ranks, nil),
  }
  return withOwn(e, o)
end

-- Merges the profession trainers the player recorded in game (ns.TrainerLog.Professions(), each
-- { npc, name, faction, prof, ranks = rank ids, zone, mapId, x, y }) into the entry list of Collect
-- and returns a new list, the input stays untouched. A sighting replaces the position and ranks of
-- the entry with the same NPC id or name (own = true, cf = 1), a trainer the list does
-- not know is added with slug P.UNKNOWN when his profession is unknown. Call it before Filter and
-- Sort, Sort puts the new entries in place.
function P.MergeOwn(entries, own)
  local out = {}
  for i, e in ipairs(list(entries)) do
    out[i] = e
  end
  for _, o in ipairs(list(own)) do
    if type(o) == "table" and type(o.npc) == "number" and nonEmpty(o.name) then
      local hits = ownHits(out, o)
      if #hits == 0 then
        out[#out + 1] = newOwn(out, o)
      elseif #hits == 1 or (#hits > 1 and out[hits[1]].npc == o.npc) then
        for _, i in ipairs(hits) do
          out[i] = withOwn(out[i], o)
        end
      end
    end
  end
  return out
end

function P.HasPosition(entry)
  return entry.x ~= nil and entry.y ~= nil
end

-- Counts of the entries: total and with a position.
function P.Count(entries)
  local total, placed = 0, 0
  for _, e in ipairs(list(entries)) do
    total = total + 1
    if P.HasPosition(e) then
      placed = placed + 1
    end
  end
  return total, placed
end

-- Counts per profession: { [slug] = { total, placed } }.
function P.CountBySlug(entries)
  local out = {}
  for _, e in ipairs(list(entries)) do
    local c = out[e.slug] or { total = 0, placed = 0 }
    out[e.slug] = c
    c.total = c.total + 1
    if P.HasPosition(e) then
      c.placed = c.placed + 1
    end
  end
  return out
end

local function plainMatch(text, query)
  return text:lower():find(query:lower(), 1, true) ~= nil
end

local function haystack(e)
  local parts = { e.name, e.nameDe or "" }
  for _, t in ipairs({ e.profession, e.zone, e.place }) do
    if type(t) == "table" then
      parts[#parts + 1] = t.de
      parts[#parts + 1] = t.en
    end
  end
  return table.concat(parts, " ")
end

-- f: slug, faction ("A" or "H", else all; neutral trainers belong to both), rank (a rank id, else
-- all), query (every word has to occur), match(text, word) (default: plain, case-insensitive).
function P.Filter(entries, f)
  f = f or {}
  local match = f.match or plainMatch
  local words = {}
  for word in tostring(f.query or ""):gmatch("%S+") do
    words[#words + 1] = word
  end
  local out = {}
  for _, e in ipairs(list(entries)) do
    local ok = (f.slug == nil or f.slug == "all" or e.slug == f.slug)
      and not ((f.faction == "A" or f.faction == "H") and e.faction ~= "N" and e.faction ~= f.faction)
    if ok and RANK_INDEX[f.rank] then
      ok = false
      for _, r in ipairs(e.ranks) do
        ok = ok or r.rank == f.rank
      end
    end
    if ok and #words > 0 then
      local text = haystack(e)
      for _, word in ipairs(words) do
        ok = ok and match(text, word)
      end
    end
    if ok then
      out[#out + 1] = e
    end
  end
  return out
end

-- In place: profession order, then Alliance, Horde, neutral, then place and name.
function P.Sort(entries)
  table.sort(entries, function(a, b)
    if a.order ~= b.order then
      return a.order < b.order
    end
    if a.faction ~= b.faction then
      return FACTION_ORDER[a.faction] < FACTION_ORDER[b.faction]
    end
    local pa, pb = tostring(a.place.en or ""), tostring(b.place.en or "")
    if pa ~= pb then
      return pa < pb
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.key < b.key
  end)
  return entries
end

-- Places -----------------------------------------------------------------------------------------

-- Name of an entry in the active language (the data file knows the German spelling of some).
function P.DisplayName(entry)
  return ns.T({ de = entry.nameDe, en = entry.name })
end

-- UiMapID of a trainer (an entry or anything with mapId and zone = { de, en }): the map id of the data,
-- else the client map named like the zone (active language, German, English), and only a unique
-- hit counts, a wrong pin is worse than none. Reads the client's zone list, so call it on click.
function P.MapOf(t)
  if t.mapId then
    return t.mapId
  end
  local zone = type(t.zone) == "table" and t.zone or {}
  local index = ns.Waypoints.ZoneIndex()
  for _, name in ipairs({ ns.T(zone) or "", zone.de or "", zone.en or "" }) do
    if name ~= "" then
      local hits = ns.WaypointLogic.matchZones(index, name)
      if #hits == 1 then
        return hits[1].id
      end
    end
  end
  return nil
end

-- The place the Map and Waypoint buttons act on: { map, x, y, label, zone } of an entry, resolved
-- on click (see MapOf).
function P.Place(entry)
  return {
    map = P.MapOf(entry),
    x = entry.x,
    y = entry.y,
    label = P.DisplayName(entry),
    zone = ns.T(entry.zone) or ns.T(entry.place) or entry.name,
  }
end
