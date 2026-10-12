-- Areas (sub-zones) of the dungeons and the map each one belongs to. Inside instances the client gives no
-- map ID and no position, only the sub-zone text (GetSubZoneText, ZONE_CHANGED*), so the text is matched
-- against the names of the instance. Pure logic, no WoW API.
--
-- Data of the areas: Forever Guides database, client build 1.60.1.70205, enUS and deDE. The `map` field is
-- the floor number of Data.DungeonAssets.maps[..].floors; nil keeps the map that is shown (the assignment
-- area to floor is not in any table). The player's own assignments (learned) take precedence over `map`.
-- Learned data lives in ns.db.dungeonAreas = { v = 1, items = { [instanceId] = { [key] = entry } } } with
-- entry = { name, floor, x, y } (x, y = rough centre of the area on that floor, 0..1, optional).
local _, ns = ...

local A = {}
ns.DungeonAreaLogic = A

A.SCHEMA = 1
A.MAX_FLOOR = 99
A.MAX_INSTANCES = 100
A.MAX_AREAS = 60
A.MAX_NAME = 80

-- areas[instanceId][areaId] = { en, de, map, x, y }
A.areas = {
  -- Ruins of Lordaeron: one map for all areas.
  [2999] = {
    [16611] = { en = "Ruins of Lordaeron", de = "Die Ruinen von Lordaeron", map = 1 },
    [16612] = { en = "King's Alley", de = "Königsgasse", map = 1 },
    [16614] = { en = "Lordaeron Graveyard", de = "Friedhof von Lordaeron", map = 1 },
    [16615] = { en = "Lordamere Overlook", de = "Warte Lordamere", map = 1 },
    [16617] = { en = "Market Street", de = "Marktstraße", map = 1 },
  },
  -- City of Dalaran: the minimap crop of the city is the only map (the sewers have no tiles).
  [2959] = {
    [16544] = { en = "Dalaran", de = "Dalaran", map = 1 },
    [16558] = { en = "Dalaran", de = "Dalaran", map = 1 },
    [16559] = { en = "Fel Grove", de = "Teufelshain", map = 1 },
    [16560] = { en = "Dalaran", de = "Dalaran", map = 1 },
    [16562] = { en = "Hillsbrad Foothills", de = "Vorgebirge von Hillsbrad", map = 1 },
  },
  -- Excavation Site: Wetlands: one map for all areas.
  [2998] = {
    [16732] = { en = "Excavation Site: Wetlands", de = "Ausgrabungsstätte: Sumpfland", map = 1 },
    [16877] = { en = "Lost Marsh", de = "Verlorener Marsch", map = 1 },
    [16878] = { en = "Stalker's Thicket", de = "Pirscherdickicht", map = 1 },
    [16879] = { en = "Site of the Guardian", de = "Stätte des Wächters", map = 1 },
    [16880] = { en = "Lost Dig Site", de = "Vergessene Ausgrabungsstätte", map = 1 },
  },
  [3065] = {
    [16919] = { en = "Hall of Thanes", de = "Die Halle der Thanen", map = 1 },
  },
}

-- Text matching ---------------------------------------------------------------------------------

local UMLAUT = { ["\195\132"] = "\195\164", ["\195\150"] = "\195\182", ["\195\156"] = "\195\188" }
local ARTICLES = { "the ", "die ", "der ", "das " }

-- Folds what differs between the client text and the data: case (also of umlauts), the typographic
-- apostrophes and dashes, runs of spaces. "" for anything that is not a string.
function A.Normalize(text)
  if type(text) ~= "string" then
    return ""
  end
  local s = text:gsub("\226\128[\152\153]", "'")
  s = s:gsub("\194\180", "'"):gsub("`", "'")
  s = s:gsub("\226\128[\147\148]", "-")
  s = s:gsub("\194\160", " ")
  s = s:gsub("\195[\132\150\156]", UMLAUT)
  s = s:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return s
end

-- The comparison key of an area name: normalized, without a leading article ("The Hall of Thanes" and
-- "Hall of Thanes" are the same area). nil for an empty text.
function A.Key(text)
  local s = A.Normalize(text)
  for _, article in ipairs(ARTICLES) do
    if s:sub(1, #article) == article and #s > #article then
      s = s:sub(#article + 1)
      break
    end
  end
  return s ~= "" and s or nil
end

local sortedIds = {}

local function areaIds(instanceId)
  local list = sortedIds[instanceId]
  if not list then
    list = {}
    for id in pairs(A.areas[instanceId] or {}) do
      list[#list + 1] = id
    end
    table.sort(list)
    sortedIds[instanceId] = list
  end
  return list
end

-- The area of an instance whose name (en or de) equals the text: areaId, entry. With equal names (Dalaran
-- has three areas of that name) the lowest ID wins.
function A.Match(instanceId, text)
  local key = A.Key(text)
  local areas = A.areas[instanceId]
  if not (key and areas) then
    return nil
  end
  for _, id in ipairs(areaIds(instanceId)) do
    local entry = areas[id]
    if A.Key(entry.en) == key or A.Key(entry.de) == key then
      return id, entry
    end
  end
end

local function validFloor(n)
  return type(n) == "number" and n >= 1 and n <= A.MAX_FLOOR and n == math.floor(n)
end

local function unit(v)
  return type(v) == "number" and v == v and v >= 0 and v <= 1
end

local function round3(v)
  return math.floor(v * 1000 + 0.5) / 1000
end

-- Learned data ----------------------------------------------------------------------------------

local function learnedEntry(store, instanceId, key)
  local items = type(store) == "table" and type(store.items) == "table" and store.items[instanceId]
  local entry = type(items) == "table" and key and items[key]
  return type(entry) == "table" and entry or nil
end

-- What to show for the sub-zone text in this instance. nil for an empty text. Otherwise
-- { key, name, area (area ID or nil), floor (number or nil = keep the map), source ("learned" or "data" or
-- nil), point = { x, y, floor } or nil, known (data or learned entry exists) }.
function A.Resolve(instanceId, text, store)
  local key = A.Key(text)
  if not key then
    return nil
  end
  local out = { key = key, name = text, known = false }
  local id, entry = A.Match(instanceId, text)
  if entry then
    out.area, out.known = id, true
    if validFloor(entry.map) then
      out.floor, out.source = entry.map, "data"
    end
    if unit(entry.x) and unit(entry.y) then
      out.point = { x = entry.x, y = entry.y, floor = out.floor }
    end
  end
  -- Learned in the other language of the client counts too: the area of the data has both names.
  local learned = learnedEntry(store, instanceId, key)
  if not learned and entry then
    learned = learnedEntry(store, instanceId, A.Key(entry.en)) or learnedEntry(store, instanceId, A.Key(entry.de))
  end
  if learned then
    out.known = true
    if validFloor(learned.floor) then
      out.floor, out.source = learned.floor, "learned"
    end
    if unit(learned.x) and unit(learned.y) then
      out.point = { x = learned.x, y = learned.y, floor = validFloor(learned.floor) and learned.floor or out.floor }
    end
  end
  return out
end

-- Whether the text names a part of the dungeon that may be learned: not empty, not the dungeon itself and
-- not the zone text of the client (a dungeon without sub-zones reports its own name or the zone).
-- names = { en, de } of the instance, zoneText = GetZoneText() or nil.
function A.CanLearn(text, names, zoneText)
  local key = A.Key(text)
  if not key then
    return false
  end
  if key == A.Key(zoneText) then
    return false
  end
  for _, n in pairs(names or {}) do
    if key == A.Key(n) then
      return false
    end
  end
  return true
end

-- Cleans a stored table in place: wrong types and out-of-range values are dropped. Returns the table.
function A.Clean(store)
  if type(store) ~= "table" then
    return { v = A.SCHEMA, items = {} }
  end
  store.v = A.SCHEMA
  if type(store.items) ~= "table" then
    store.items = {}
  end
  local instances = 0
  for instanceId, areas in pairs(store.items) do
    instances = instances + 1
    if type(instanceId) ~= "number" or type(areas) ~= "table" or instances > A.MAX_INSTANCES then
      store.items[instanceId] = nil
    else
      local count = 0
      for key, entry in pairs(areas) do
        count = count + 1
        local ok = type(key) == "string" and key ~= "" and type(entry) == "table" and count <= A.MAX_AREAS
        if ok then
          entry.name = type(entry.name) == "string" and entry.name:sub(1, A.MAX_NAME) or key
          ok = validFloor(entry.floor)
          if not (unit(entry.x) and unit(entry.y)) then
            entry.x, entry.y = nil, nil
          end
        end
        if not ok then
          areas[key] = nil
        end
      end
      if next(areas) == nil then
        store.items[instanceId] = nil
      end
    end
  end
  return store
end

-- Remembers that the area of the text belongs to the floor, optionally with its rough centre (x, y in 0..1).
-- Returns true, or false and the reason ("text", "floor", "point", "full").
function A.Learn(store, instanceId, text, floor, x, y)
  local key = A.Key(text)
  if not key then
    return false, "text"
  end
  if type(instanceId) ~= "number" or not validFloor(floor) then
    return false, "floor"
  end
  if (x ~= nil or y ~= nil) and not (unit(x) and unit(y)) then
    return false, "point"
  end
  store.items = type(store.items) == "table" and store.items or {}
  local areas = store.items[instanceId]
  if not areas then
    local instances = 0
    for _ in pairs(store.items) do
      instances = instances + 1
    end
    if instances >= A.MAX_INSTANCES then
      return false, "full"
    end
    areas = {}
    store.items[instanceId] = areas
  end
  local entry = areas[key]
  if not entry then
    local count = 0
    for _ in pairs(areas) do
      count = count + 1
    end
    if count >= A.MAX_AREAS then
      return false, "full"
    end
    entry = {}
    areas[key] = entry
  end
  -- A centre belongs to one floor: moving the area to another floor drops it.
  local moved = entry.floor ~= nil and entry.floor ~= floor
  entry.name, entry.floor = text:sub(1, A.MAX_NAME), floor
  if x ~= nil then
    entry.x, entry.y = round3(x), round3(y)
  elseif moved then
    entry.x, entry.y = nil, nil
  end
  return true
end

-- Number of learned areas of one instance, or of all when instanceId is nil.
function A.Count(store, instanceId)
  local n = 0
  local items = type(store) == "table" and type(store.items) == "table" and store.items or {}
  for id, areas in pairs(items) do
    if instanceId == nil or id == instanceId then
      for _ in pairs(areas) do
        n = n + 1
      end
    end
  end
  return n
end

function A.Forget(store, instanceId)
  if type(store) == "table" and type(store.items) == "table" then
    store.items[instanceId] = nil
  end
end

-- One line per learned area: "id | instance | area | floor | x | y" (x and y empty when unknown), sorted, so
-- the same data always gives the same text. nameOf(instanceId) returns the instance name.
function A.Export(store, nameOf)
  local lines = {}
  local items = type(store) == "table" and type(store.items) == "table" and store.items or {}
  local ids = {}
  for id in pairs(items) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local keys = {}
    for key in pairs(items[id]) do
      keys[#keys + 1] = key
    end
    table.sort(keys)
    local instance = nameOf and nameOf(id) or tostring(id)
    for _, key in ipairs(keys) do
      local e = items[id][key]
      lines[#lines + 1] = string.format(
        "%d | %s | %s | %d | %s | %s",
        id,
        instance,
        e.name or key,
        e.floor,
        e.x and string.format("%.3f", e.x) or "",
        e.y and string.format("%.3f", e.y) or ""
      )
    end
  end
  return table.concat(lines, "\n")
end
