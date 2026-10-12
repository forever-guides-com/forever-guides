-- Background maps of the drawing sheet (docs/ZEICHNUNGEN-FORMAT.md). A drawing stores only the key of
-- its map (DrawingLogic cleanMap: a zone by UiMapID, a dungeon or raid floor by its Data.DungeonAssets
-- name and floor number), never pictures. This file lists what can be chosen (Choices), narrows the
-- list by a search (Filter), and turns a stored key into the art ns.MapReveal.DrawBase paints
-- (Resolve), on this client only: a key the client does not know gives no art and the sheet shows
-- without a map. Zones come from the discovery of the map page (MapWorld), instances and floors from
-- Data.DungeonAssets. No file of another addon or project is used.
local _, ns = ...
local L, D, MW, DMV = ns.L, ns.DrawingLogic, ns.MapWorld, ns.DungeonMapView

local DM = {}
ns.DrawingMap = DM

-- Long side of a sheet fitted to a map, in cells (288 x 192 for the 3:2 maps).
DM.FIT_SIDE = 288

ns.AddLocale("enUS", {
  ["draw.map.group.zones"] = "Zones",
  ["draw.map.group.instances"] = "Dungeons and raids",
  ["draw.map.floors"] = "%d floors",
  ["draw.map.floor1"] = "1 floor",
  ["draw.map.zoneN"] = "Map %d",
})
ns.AddLocale("deDE", {
  ["draw.map.group.zones"] = "Gebiete",
  ["draw.map.group.instances"] = "Dungeons und Raids",
  ["draw.map.floors"] = "%d Ebenen",
  ["draw.map.floor1"] = "1 Ebene",
  ["draw.map.zoneN"] = "Karte %d",
})

local function assets()
  local all = ns.Data and ns.Data.DungeonAssets
  return all and all.maps or {}
end

-- Lower case, trimmed, capital umlauts folded, for the search.
local function fold(text)
  local s = MW.NormalizeName(text)
  if not s then
    return ""
  end
  return (s:gsub("\195\132", "\195\164"):gsub("\195\150", "\195\182"):gsub("\195\156", "\195\188"))
end

-- Choices ---------------------------------------------------------------------------------------

-- Number of floors with a map of a DungeonAssets name (0: none yet, "map coming soon").
function DM.FloorCount(key)
  local entry = assets()[key]
  if not entry or entry.soon or type(entry.floors) ~= "table" then
    return 0
  end
  return #entry.floors
end

-- "Floor 2", or the name the data gives the floor.
function DM.FloorName(key, n)
  local entry = assets()[key]
  local floor = entry and entry.floors and entry.floors[n]
  local name = floor and floor.n and ns.T(floor.n)
  return name or string.format(L["dmap.floorN"], n)
end

local function instanceNames()
  local out = {}
  for _, inst in ipairs(ns.Data.Instances or {}) do
    local en = inst.n and inst.n.en
    if en and not out[en] then
      out[en] = inst.n
    end
  end
  return out
end

local function zoneChoices()
  local data = ns.Data and ns.Data.Travel
  if not (data and MW and MW.Discover) then
    return {}
  end
  local ok, world = ns.Safe("drawmap-world", MW.Discover, data)
  if not (ok and type(world) == "table" and world.ok and world.maps) then
    return {}
  end
  local continents = {}
  for _, c in ipairs(data.continents or {}) do
    continents[c.s] = c.n
  end
  local list = {}
  for _, z in ipairs(data.zones or {}) do
    local id = world.maps[z.s]
    if type(id) == "number" and id >= 1 and id <= D.MAP_MAX_ID and z.k == "zone" then
      local cont = continents[z.c]
      list[#list + 1] = {
        id = "zone:" .. id,
        map = { kind = "zone", id = id },
        title = ns.T(z.n),
        sub = cont and ns.T(cont) or nil,
        search = fold(table.concat({ z.n.en or "", z.n.de or "", cont and cont.en or "" }, " ")),
      }
    end
  end
  return list
end

local function instanceChoices()
  local names, list = instanceNames(), {}
  for key in pairs(assets()) do
    if D.validMapKey(key) then
      local floors = DM.FloorCount(key)
      local n = names[key]
      local sub = L["dmap.soon"]
      if floors == 1 then
        sub = L["draw.map.floor1"]
      elseif floors > 1 then
        sub = string.format(L["draw.map.floors"], floors)
      end
      list[#list + 1] = {
        id = "instance:" .. key,
        map = { kind = "instance", key = key, floor = 1 },
        title = n and ns.T(n) or key,
        sub = sub,
        floors = floors,
        soon = floors == 0,
        search = fold(table.concat({ key, n and n.de or "", n and n.en or "" }, " ")),
      }
    end
  end
  return list
end

local function byTitle(a, b)
  local x, y = fold(a.title), fold(b.title)
  if x ~= y then
    return x < y
  end
  return a.id < b.id
end

-- Groups in the order of the list: { { id = "zones" | "instances", title, items = { entry } } }.
-- An entry is { id, map (without alpha), title, sub, search, floors, soon }. Empty groups are left
-- out (a client without map data has no zones).
function DM.Choices()
  local groups = {}
  for _, spec in ipairs({
    { id = "zones", title = L["draw.map.group.zones"], items = zoneChoices() },
    { id = "instances", title = L["draw.map.group.instances"], items = instanceChoices() },
  }) do
    if #spec.items > 0 then
      table.sort(spec.items, byTitle)
      groups[#groups + 1] = spec
    end
  end
  return groups
end

-- The groups reduced to the entries whose name (in either language) contains every word of the
-- query. An empty query keeps everything.
function DM.Filter(groups, query)
  local words = {}
  for word in fold(query):gmatch("%S+") do
    words[#words + 1] = word
  end
  if #words == 0 then
    return groups
  end
  local out = {}
  for _, g in ipairs(groups) do
    local items = {}
    for _, entry in ipairs(g.items) do
      local hit = true
      for _, word in ipairs(words) do
        if not entry.search:find(word, 1, true) then
          hit = false
          break
        end
      end
      if hit then
        items[#items + 1] = entry
      end
    end
    if #items > 0 then
      out[#out + 1] = { id = g.id, title = g.title, items = items }
    end
  end
  return out
end

-- The id of the entry a stored map belongs to ("zone:1440"), nil for no or an invalid map.
function DM.IdOf(map)
  map = D.cleanMap(map)
  if not map then
    return nil
  end
  return map.kind == "zone" and ("zone:" .. map.id) or ("instance:" .. map.key)
end

-- Resolve ---------------------------------------------------------------------------------------

local cache = {}

function DM.Reset()
  cache = {}
end

local function zoneLabel(id)
  local fn = C_Map and C_Map.GetMapInfo
  local ok, info = false, nil
  if type(fn) == "function" then
    ok, info = pcall(fn, id)
  end
  if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
    return info.name
  end
  return string.format(L["draw.map.zoneN"], id)
end

local function instanceLabel(key, n)
  local names = instanceNames()
  local base = names[key] and ns.T(names[key]) or key
  if DM.FloorCount(key) > 1 then
    return base .. ": " .. DM.FloorName(key, n)
  end
  return base
end

-- The art of a stored map for ns.MapReveal.DrawBase ({ layer = { layerWidth, layerHeight,
-- tileWidth, tileHeight }, textures = file ids row by row }) and a label for the status line.
-- nil, nil, reason ("map" invalid | "soon" no pictures yet | "missing" unknown here | "unavailable"
-- the client gives no art) otherwise. Successes are kept, failures are tried again.
function DM.Resolve(map)
  map = D.cleanMap(map)
  if not map then
    return nil, nil, "map"
  end
  local key = map.kind == "zone" and ("z" .. map.id) or ("i" .. map.key .. "#" .. map.floor)
  local hit = cache[key]
  if hit then
    return hit.art, hit.label
  end
  local art, label
  if map.kind == "zone" then
    local ok, found = ns.Safe("drawmap-art", MW.LoadArt, map.id)
    if not (ok and found) then
      return nil, nil, "unavailable"
    end
    art, label = found, zoneLabel(map.id)
  else
    local entry = assets()[map.key]
    if not entry then
      return nil, nil, "missing"
    end
    if DM.FloorCount(map.key) == 0 then
      return nil, nil, "soon"
    end
    local floor = entry.floors[map.floor]
    if not (floor and type(floor.fid) == "table" and #floor.fid > 0) then
      return nil, nil, "missing"
    end
    local geo = DMV.Geometry(floor)
    art = {
      layer = { layerWidth = geo.w, layerHeight = geo.h, tileWidth = DMV.TILE, tileHeight = DMV.TILE },
      textures = floor.fid,
    }
    label = instanceLabel(map.key, map.floor)
  end
  cache[key] = { art = art, label = label }
  return art, label
end

-- Name of a stored map for messages, also for one this client cannot resolve.
function DM.Describe(map)
  map = D.cleanMap(map)
  if not map then
    return ""
  end
  return map.kind == "zone" and zoneLabel(map.id) or instanceLabel(map.key, map.floor)
end

-- Layer size of a map (width, height), nil when it cannot be resolved here.
function DM.LayerSize(map)
  local art = DM.Resolve(map)
  return art and art.layer.layerWidth, art and art.layer.layerHeight
end

-- Cells (w, h) of a sheet that has the aspect of the map: the long side is FIT_SIDE, within the
-- limits of the sheet. nil when the map cannot be resolved here.
function DM.FitSize(map)
  local lw, lh = DM.LayerSize(map)
  if not lw then
    return nil
  end
  local w, h = DM.FIT_SIDE, DM.FIT_SIDE
  if lw >= lh then
    h = math.floor(DM.FIT_SIDE * lh / lw + 0.5)
  else
    w = math.floor(DM.FIT_SIDE * lw / lh + 0.5)
  end
  w, h = D.clampDims(w, h)
  return w, h
end
