-- Ores and herbs, pure side (no frames): filters and sorts the items of the gathering data, lists the
-- zones a set of items occurs in, decodes the points of a zone, and keeps the per zone choice of items
-- for the map (ns.GatherSelection). The data shape is in docs/GATHERING-FORMAT.md, the page is
-- Modules/GatheringPage.lua.
local _, ns = ...

local G = {}
ns.GatheringLogic = G

-- Profession ids of the data, in list order. They equal the route slugs of ProfessionRouteLogic.
G.PROFESSIONS = { "mining", "herbalism" }

local PROF_INDEX = { mining = 1, herbalism = 2 }
local OPPOSITE = { A = "H", H = "A" }
-- Zones without a level range (the capitals) are listed after the others.
local NO_LEVEL = 1000
local POINT_CHARS = 4

local function listOf(value)
  return type(value) == "table" and value or {}
end

local function folded(text)
  return ns.SearchLogic.fold(text)
end

-- Items ----------------------------------------------------------------------------------------

-- Name of an item in the active language, the id when the data has none.
function G.ItemName(id, item)
  item = listOf(item)
  return ns.T({ de = item.de, en = item.en }) or ("#" .. tostring(id))
end

-- Icon path of an item: the file of the data, else the client's icon of the item, else the question mark.
function G.IconPath(id, item)
  local icon = type(item) == "table" and item.icon
  if type(icon) == "string" and icon ~= "" then
    return "Interface\\Icons\\" .. icon
  end
  local api = rawget(_G, "C_Item")
  if type(api) == "table" and type(api.GetItemIconByID) == "function" then
    local ok, file = pcall(api.GetItemIconByID, id)
    if ok and file then
      return file
    end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local zoneIndex

-- Zones of the travel data by map id: { n = { de, en }, f = "A"|"H"|"N"|"C", lmin, lmax }.
local function travelZones()
  if zoneIndex then
    return zoneIndex
  end
  zoneIndex = {}
  local travel = ns.Data and ns.Data.Travel
  for _, z in ipairs(listOf(travel and travel.zones)) do
    if type(z) == "table" and type(z.um) == "number" then
      zoneIndex[z.um] = z
    end
  end
  return zoneIndex
end

-- Forgets the cached zone index (tests).
function G.ResetZones()
  zoneIndex = nil
end

-- Name of a zone: the travel data, else the client's map name, else the id.
function G.ZoneName(mapId)
  local z = travelZones()[mapId]
  local name = z and ns.T(z.n)
  if name then
    return name
  end
  local api = rawget(_G, "C_Map")
  if type(api) == "table" and type(api.GetMapInfo) == "function" then
    local ok, info = pcall(api.GetMapInfo, mapId)
    if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
      return info.name
    end
  end
  return "#" .. tostring(mapId)
end

-- "A", "H", "N" (neutral) or "C" (contested) of a zone, nil when the travel data does not know it.
function G.ZoneFaction(mapId)
  local z = travelZones()[mapId]
  return z and z.f or nil
end

-- Only a zone of the opposite faction is closed; unknown zones and neutral ones are always open.
local function zoneOpen(mapId, faction)
  return not (OPPOSITE[faction] ~= nil and G.ZoneFaction(mapId) == OPPOSITE[faction])
end

-- Level range of a zone: the data first, else the travel data. nil, nil for a capital.
local function levelsOf(zone, mapId)
  local lvl = zone.lvl
  if type(lvl) == "table" and tonumber(lvl[1]) then
    return tonumber(lvl[1]), tonumber(lvl[2]) or tonumber(lvl[1])
  end
  local z = travelZones()[mapId]
  if z and tonumber(z.lmin) then
    return tonumber(z.lmin), tonumber(z.lmax) or tonumber(z.lmin)
  end
  return nil, nil
end

-- A list or a set of item ids as a set; nil stays nil (every item).
local function idSet(ids)
  if ids == nil then
    return nil
  end
  local set = {}
  for k, v in pairs(listOf(ids)) do
    if type(k) == "number" and v == true then
      set[k] = true
    elseif type(v) == "number" then
      set[v] = true
    end
  end
  return set
end

-- Items the data knows, filtered. filter:
--   prof     "mining" | "herbalism" (anything else: both)
--   search   part of the name in either language, case and umlauts do not matter
--   skills   { mining = n, herbalism = n }: only items up to the own skill; a profession missing in
--            the table hides its items (nil: no skill filter)
--   zone     map id: only items with points there
--   faction  "A" | "H": zones of the other faction do not count (as zone filter and for the counts)
-- Returns { id, prof, skill, name, de, en, icon, zones } sorted by profession, skill, name; zones is
-- the number of (counted) zones with points.
function G.Items(data, filter)
  filter = listOf(filter)
  data = listOf(data)
  local zoneCount = {}
  for mapId, zone in pairs(listOf(data.zones)) do
    if (filter.zone == nil or filter.zone == mapId) and zoneOpen(mapId, filter.faction) then
      for id in pairs(listOf(zone.items)) do
        zoneCount[id] = (zoneCount[id] or 0) + 1
      end
    end
  end
  local query = type(filter.search) == "string" and filter.search ~= "" and filter.search or nil
  local out = {}
  for id, item in pairs(listOf(data.items)) do
    local prof = item.prof
    local ok = PROF_INDEX[prof] ~= nil and zoneCount[id] ~= nil
    if ok and PROF_INDEX[filter.prof] then
      ok = prof == filter.prof
    end
    if ok and filter.skills then
      local own = tonumber(filter.skills[prof])
      ok = own ~= nil and (tonumber(item.skill) or 0) <= own
    end
    if ok and query then
      ok = ns.SearchLogic.match(item.de or "", query) or ns.SearchLogic.match(item.en or "", query)
    end
    if ok then
      out[#out + 1] = {
        id = id,
        prof = prof,
        skill = tonumber(item.skill) or 0,
        name = G.ItemName(id, item),
        de = item.de,
        en = item.en,
        icon = item.icon,
        zones = zoneCount[id],
      }
    end
  end
  table.sort(out, function(a, b)
    if a.prof ~= b.prof then
      return PROF_INDEX[a.prof] < PROF_INDEX[b.prof]
    end
    if a.skill ~= b.skill then
      return a.skill < b.skill
    end
    local na, nb = folded(a.name), folded(b.name)
    if na ~= nb then
      return na < nb
    end
    return a.id < b.id
  end)
  return out
end

-- Splits a list of entries that carry a `prof` (items of the list, chips of a zone) by profession:
-- { { prof, items, count }, ... } in the order of G.PROFESSIONS, the entries of a group in their input
-- order. A profession without entries has no group, an entry of an unknown profession is left out.
function G.GroupByProfession(entries)
  local byProf = {}
  for _, e in ipairs(listOf(entries)) do
    local prof = type(e) == "table" and e.prof
    if PROF_INDEX[prof] then
      local group = byProf[prof]
      if not group then
        group = { prof = prof, items = {}, count = 0 }
        byProf[prof] = group
      end
      group.count = group.count + 1
      group.items[group.count] = e
    end
  end
  local out = {}
  for _, prof in ipairs(G.PROFESSIONS) do
    out[#out + 1] = byProf[prof]
  end
  return out
end

-- True for a profession id of the data.
function G.IsProfession(prof)
  return PROF_INDEX[prof] ~= nil
end

-- The id of the item a text names: an id, an exact name in either language, else the only item whose
-- name contains the text. nil when nothing or several fit.
function G.FindItem(data, text)
  local items = listOf(listOf(data).items)
  text = type(text) == "string" and text:match("^%s*(.-)%s*$") or tostring(text or "")
  if text == "" then
    return nil
  end
  local id = tonumber(text)
  if id and items[id] then
    return id
  end
  local key, partial, count = folded(text), nil, 0
  for itemId, item in pairs(items) do
    if folded(item.de or "") == key or folded(item.en or "") == key then
      return itemId
    end
    if ns.SearchLogic.match(item.de or "", text) or ns.SearchLogic.match(item.en or "", text) then
      partial, count = itemId, count + 1
    end
  end
  return count == 1 and partial or nil
end

-- Zones ----------------------------------------------------------------------------------------

-- The zones where at least one of the items (a list or a set of ids, nil: every item) occurs:
-- { mapId, name, lmin, lmax, faction, counts = { [itemId] = points }, total }, sorted by level
-- (lowest first, zones without levels last), then name. opts.faction "A" | "H" drops the zones of the
-- other faction.
function G.Zones(data, itemIds, opts)
  opts = listOf(opts)
  data = listOf(data)
  local wanted = idSet(itemIds)
  local items = listOf(data.items)
  local out = {}
  for mapId, zone in pairs(listOf(data.zones)) do
    if zoneOpen(mapId, opts.faction) then
      local counts, total = {}, 0
      for id, chain in pairs(listOf(zone.items)) do
        if items[id] and (wanted == nil or wanted[id]) and type(chain) == "string" then
          local n = math.floor(#chain / POINT_CHARS)
          if n > 0 then
            counts[id] = n
            total = total + n
          end
        end
      end
      if total > 0 then
        local lmin, lmax = levelsOf(zone, mapId)
        out[#out + 1] = {
          mapId = mapId,
          name = G.ZoneName(mapId),
          lmin = lmin,
          lmax = lmax,
          faction = G.ZoneFaction(mapId),
          counts = counts,
          total = total,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    local la, lb = a.lmin or NO_LEVEL, b.lmin or NO_LEVEL
    if la ~= lb then
      return la < lb
    end
    local ma, mb = a.lmax or NO_LEVEL, b.lmax or NO_LEVEL
    if ma ~= mb then
      return ma < mb
    end
    local na, nb = folded(a.name), folded(b.name)
    if na ~= nb then
      return na < nb
    end
    return a.mapId < b.mapId
  end)
  return out
end

-- The decoded points of a zone: { { x, y, itemId }, ... } for the items (list or set, nil: every item),
-- items in id order, points as stored. extraPoints (optional, own finds) is a list of { x, y, itemId }
-- that joins the result when its item is wanted.
function G.Points(data, mapId, itemIds, extraPoints)
  local zone = listOf(listOf(listOf(data).zones)[mapId])
  local wanted = idSet(itemIds)
  local ids = {}
  for id in pairs(listOf(zone.items)) do
    if wanted == nil or wanted[id] then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  local out = {}
  for _, id in ipairs(ids) do
    for _, p in ipairs(ns.GatherCodec.Decode(zone.items[id])) do
      out[#out + 1] = { x = p[1] or p.x, y = p[2] or p.y, itemId = id }
    end
  end
  for _, p in ipairs(listOf(extraPoints)) do
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" and p.itemId then
      if wanted == nil or wanted[p.itemId] then
        out[#out + 1] = { x = p.x, y = p.y, itemId = p.itemId }
      end
    end
  end
  return out
end

-- Choice per zone ---------------------------------------------------------------------------------

-- Which items of a zone the player narrowed the map to. Lives for the session only. The page writes it
-- (chips of a zone row, the Map button), GatherFilter.ZoneItems reads it for both maps: a zone without a
-- stored choice shows every item. Get(mapId) answers a new set { [itemId] = true }.
local S = {}
ns.GatherSelection = S

local chosen = {}

function S.Get(mapId)
  local out = {}
  for id, on in pairs(chosen[mapId] or {}) do
    if on then
      out[id] = true
    end
  end
  return out
end

-- True once a choice was stored for the zone (an empty choice counts).
function S.Has(mapId)
  return chosen[mapId] ~= nil
end

-- Stores the choice of a zone: a set { [itemId] = true|false }. Anything but a table clears it.
function S.Set(mapId, set)
  if type(mapId) ~= "number" then
    return
  end
  if type(set) ~= "table" then
    chosen[mapId] = nil
  else
    local copy = {}
    for id, on in pairs(set) do
      copy[id] = on and true or false
    end
    chosen[mapId] = copy
  end
  ns.Emit("FG_GATHER_SELECTION", mapId)
end

-- Switches one item of a zone on or off.
function S.SetItem(mapId, itemId, on)
  if type(mapId) ~= "number" then
    return
  end
  chosen[mapId] = chosen[mapId] or {}
  chosen[mapId][itemId] = on and true or false
  ns.Emit("FG_GATHER_SELECTION", mapId)
end

-- Forgets every choice (tests, reset).
function S.Clear()
  chosen = {}
  ns.Emit("FG_GATHER_SELECTION")
end
