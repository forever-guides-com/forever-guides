-- Fishing helper, the fishing places: rows and texts built from the generated table fish.PlacesData
-- (FishingPlaces.lua). Pure functions, no frames, no client calls: names come in as functions.
local _, fish = ...
if not fish.FG then
  return
end

local P = {}
fish.PlacesLogic = P

-- A chance in 1/100 percent as text: "58.8%", small values with two decimals.
function P.Percent(hundredths)
  local value = (tonumber(hundredths) or 0) / 100
  if value >= 1 then
    return string.format("%.1f%%", value)
  end
  return string.format("%.2f%%", value)
end

-- The rows of the area list, sorted by the skill to cast and then by name. `areaName(id)` gives the name in the
-- client language (nil when the client does not know it), the English name of the data is the fallback.
function P.Rows(data, areaName, query)
  local rows = {}
  local needle = type(query) == "string" and query:lower() or ""
  for id, entry in pairs(data and data.areas or {}) do
    local name = areaName and areaName(id) or nil
    if type(name) ~= "string" or name == "" then
      name = entry[3]
    end
    if needle == "" or name:lower():find(needle, 1, true) then
      rows[#rows + 1] = { key = id, name = name, cast = entry[1], clean = entry[2], fish = math.floor(#entry[4] / 2) }
    end
  end
  table.sort(rows, function(a, b)
    if a.cast ~= b.cast then
      return a.cast < b.cast
    end
    if a.name:lower() ~= b.name:lower() then
      return a.name:lower() < b.name:lower()
    end
    return a.key < b.key
  end)
  return rows
end

-- The fish of one area in the order of the data (highest chance first): { id, chance, name }.
function P.Fish(data, key, itemName)
  local entry = data and data.areas and data.areas[key]
  local list = {}
  if not entry then
    return list
  end
  local flat = entry[4]
  for index = 1, #flat - 1, 2 do
    local id = flat[index]
    list[#list + 1] = { id = id, chance = flat[index + 1], name = itemName and itemName(id) or nil }
  end
  return list
end

-- The area that carries one of the names (the English name of the data or the name in the client language,
-- compared without case), for the zone a map shows. Returns { key, name, cast, clean, fish } with the fish of
-- P.Fish plus `share` (0..1, the chance as a fraction of a cast), or nil when no area has the name.
-- Several areas with one name: the lowest id.
function P.ForNames(data, names, areaName, itemName)
  local wanted = {}
  for _, name in ipairs(type(names) == "table" and names or {}) do
    if type(name) == "string" and name ~= "" then
      wanted[name:lower()] = true
    end
  end
  local best
  for id, entry in pairs(data and data.areas or {}) do
    if best == nil or id < best then
      local localName = areaName and areaName(id) or nil
      if wanted[entry[3]:lower()] or (type(localName) == "string" and wanted[localName:lower()]) then
        best = id
      end
    end
  end
  if not best then
    return nil
  end
  local entry = data.areas[best]
  local name = areaName and areaName(best) or nil
  local list = P.Fish(data, best, itemName)
  for _, item in ipairs(list) do
    item.share = math.min(1, math.max(0, item.chance / 10000))
  end
  return {
    key = best,
    name = (type(name) == "string" and name ~= "") and name or entry[3],
    cast = entry[1],
    clean = entry[2],
    fish = list,
  }
end

-- Sanity check of the shipped table: the problems as a list of texts, empty when fine.
function P.Check(data, limits)
  local problems = {}
  if type(data) ~= "table" or data.v ~= 1 or type(data.areas) ~= "table" then
    return { "no table of version 1" }
  end
  local count = 0
  for key, entry in pairs(data.areas) do
    count = count + 1
    if type(key) ~= "number" or type(entry) ~= "table" or type(entry[4]) ~= "table" then
      problems[#problems + 1] = "bad entry " .. tostring(key)
    elseif entry[1] > entry[2] or #entry[4] % 2 ~= 0 or #entry[4] == 0 then
      problems[#problems + 1] = "bad skills or fish list in " .. tostring(key)
    end
  end
  if limits and limits.areas and count < limits.areas then
    problems[#problems + 1] = "only " .. count .. " areas"
  end
  return problems
end
