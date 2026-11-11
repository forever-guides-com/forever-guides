-- Spots without an item id on the maps: chests, clams and dig spots ("treasure") and fishing
-- schools and wreckage ("school"). The data add-on lists them as kinds (GatherData.objects.kinds, one entry
-- per game object with its names and icon) and as one point chain per zone and kind (objects.zones). They
-- have their own display choice next to the one of the ores and herbs (ns.GatherFilter): a switch per
-- category and a list of the kinds switched off, all in settings.gather (treasure, schools, hiddenKinds).
-- A kind the data adds later is on without a stored entry. No frames here: the layer is ns.GatheringMap
-- fed with GO.Feed, the control is Modules/GatheringFilterUI.lua. Every change ends with the message
-- FG_GATHER_FILTER_CHANGED, the same one the filter of the ores and herbs sends.
local _, ns = ...

local GO = {}
ns.GatherObjects = GO

ns.AddLocale("enUS", {
  ["gather.cat.treasure"] = "Chest",
  ["gather.cat.school"] = "Fishing school",
  ["gather.obj.several"] = "The kind changes from visit to visit.",
})
ns.AddLocale("deDE", {
  ["gather.cat.treasure"] = "Truhe",
  ["gather.cat.school"] = "Fischschwarm",
  ["gather.obj.several"] = "Die Art wechselt von Besuch zu Besuch.",
})

-- The categories in list order and the key of each switch below settings.gather.
GO.CATEGORIES = { "treasure", "school" }
GO.KEYS = { treasure = "treasure", school = "schools" }

local STEPS = 4095

local function section()
  local gather = ns.Store.get("settings.gather")
  return type(gather) == "table" and gather or {}
end

local function kindsOf(data)
  local objects = type(data) == "table" and data.objects
  return type(objects) == "table" and type(objects.kinds) == "table" and objects.kinds or {}
end

local function zoneChains(data, mapId)
  local objects = type(data) == "table" and data.objects
  local zones = type(objects) == "table" and type(objects.zones) == "table" and objects.zones or {}
  local zone = zones[mapId]
  return type(zone) == "table" and zone or {}
end

-- True when the data holds spots without an item.
function GO.Has(data)
  return next(kindsOf(data)) ~= nil
end

-- Filter ----------------------------------------------------------------------------------------------

-- True when the category ("treasure" or "school") is switched on.
function GO.CategoryOn(cat)
  local key = GO.KEYS[cat]
  return key ~= nil and section()[key] ~= false
end

-- True when the kind has no entry in the list of the kinds switched off.
function GO.KindOn(kindId)
  local hidden = section().hiddenKinds
  return not (type(hidden) == "table" and hidden[kindId] == true)
end

-- True when the kind is known to the data, its category is on and the kind itself is not switched off.
function GO.IsVisible(data, kindId)
  local kind = kindsOf(data)[kindId]
  return type(kind) == "table" and GO.CategoryOn(kind.cat) and GO.KindOn(kindId)
end

-- The kinds to draw in a zone as a set { [kindId] = true }: every kind the data has there that passes the filter.
function GO.ZoneKinds(data, mapId)
  local out = {}
  for id, chain in pairs(zoneChains(data, mapId)) do
    if type(chain) == "string" and GO.IsVisible(data, id) then
      out[id] = true
    end
  end
  return out
end

-- True when the data has any spot of a kind in the zone, switched on or not.
function GO.ZoneHas(data, mapId)
  return next(zoneChains(data, mapId)) ~= nil
end

local function copyHidden()
  local out = {}
  local hidden = section().hiddenKinds
  for id, on in pairs(type(hidden) == "table" and hidden or {}) do
    if on == true then
      out[id] = true
    end
  end
  return out
end

local function changed()
  ns.Emit("FG_GATHER_FILTER_CHANGED")
end

local function idsOf(data, cat)
  local ids = {}
  for id, kind in pairs(kindsOf(data)) do
    if type(kind) == "table" and GO.KEYS[kind.cat] and (cat == nil or kind.cat == cat) then
      ids[#ids + 1] = id
    end
  end
  return ids
end

local function dataOrAccess(data)
  if data ~= nil then
    return data
  end
  return ns.GatherDataAccess and ns.GatherDataAccess.Get() or nil
end

-- Switches a category on or off; the list of the kinds switched off stays as it is.
function GO.SetCategory(cat, on)
  local key = GO.KEYS[cat]
  if not key then
    return
  end
  ns.Store.set("settings.gather." .. key, on and true or false)
  changed()
end

-- Switches one kind on or off.
function GO.SetKind(kindId, on)
  if type(kindId) ~= "number" then
    return
  end
  local hidden = copyHidden()
  hidden[kindId] = (not on) and true or nil
  ns.Store.set("settings.gather.hiddenKinds", hidden)
  changed()
end

-- The category (nil: both) and each of its kinds on. data is optional, it is read through ns.GatherDataAccess.
function GO.All(cat, data)
  local hidden = copyHidden()
  if cat == nil then
    hidden = {}
  else
    for _, id in ipairs(idsOf(dataOrAccess(data), cat)) do
      hidden[id] = nil
    end
  end
  for c, key in pairs(GO.KEYS) do
    if cat == nil or cat == c then
      ns.Store.set("settings.gather." .. key, true)
    end
  end
  ns.Store.set("settings.gather.hiddenKinds", hidden)
  changed()
end

-- Every kind of the category (nil: all) off. The switch of the category stays as it is.
function GO.None(cat, data)
  local hidden = copyHidden()
  for _, id in ipairs(idsOf(dataOrAccess(data), cat)) do
    hidden[id] = true
  end
  ns.Store.set("settings.gather.hiddenKinds", hidden)
  changed()
end

-- Names and entries ------------------------------------------------------------------------------------

-- Name of a kind in the active language, the id when the data has none.
function GO.Name(kindId, kind)
  kind = type(kind) == "table" and kind or {}
  return ns.T({ de = kind.de, en = kind.en }) or ("#" .. tostring(kindId))
end

-- Icon file of a kind: the file of the data, else the question mark.
function GO.IconPath(kind)
  local icon = type(kind) == "table" and kind.icon
  if type(icon) == "string" and icon ~= "" then
    return "Interface\\Icons\\" .. icon
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- The rows of the list in the control: a heading per category, then its kinds by name. Only categories with kinds.
function GO.Entries(data)
  local out = {}
  local kinds = kindsOf(data)
  for _, cat in ipairs(GO.CATEGORIES) do
    local list = {}
    for id, kind in pairs(kinds) do
      if type(kind) == "table" and kind.cat == cat then
        list[#list + 1] = { id = id, cat = cat, name = GO.Name(id, kind), icon = GO.IconPath(kind) }
      end
    end
    table.sort(list, function(a, b)
      local fa, fb = ns.SearchLogic.fold(a.name), ns.SearchLogic.fold(b.name)
      if fa ~= fb then
        return fa < fb
      end
      return a.id < b.id
    end)
    if #list > 0 then
      out[#out + 1] = { kind = "head", cat = cat }
      for _, entry in ipairs(list) do
        out[#out + 1] = { kind = "object", entry = entry }
      end
    end
  end
  return out
end

-- Points ----------------------------------------------------------------------------------------------

local function sortedIds(set)
  local ids = {}
  for id, on in pairs(type(set) == "table" and set or {}) do
    if on == true and type(id) == "number" then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

local cache = setmetatable({}, { __mode = "k" })

-- The spots of a zone for the kinds of set: { { x, y, kind = first kind id, kinds = { ids } }, ... } in x, y
-- order of the first kind. Kinds that share one spot (a school spot holds several kinds) give one entry.
-- Decoded once per data table and set of kinds, the list is shared: do not change it.
function GO.Points(data, mapId, set)
  if type(data) ~= "table" then
    return {}
  end
  local ids = sortedIds(set)
  local key = mapId .. ":" .. table.concat(ids, ",")
  local byKey = cache[data]
  if not byKey then
    byKey = {}
    cache[data] = byKey
  end
  if byKey[key] then
    return byKey[key]
  end
  local chains = zoneChains(data, mapId)
  local out, at = {}, {}
  for _, id in ipairs(ids) do
    if type(chains[id]) == "string" then
      for _, p in ipairs(ns.GatherCodec.Decode(chains[id])) do
        local x, y = p[1] or p.x, p[2] or p.y
        local spot = math.floor(x * STEPS + 0.5) * (STEPS + 1) + math.floor(y * STEPS + 0.5)
        local entry = at[spot]
        if entry then
          entry.kinds[#entry.kinds + 1] = id
        else
          entry = { x = x, y = y, kind = id, kinds = { id } }
          at[spot] = entry
          out[#out + 1] = entry
        end
      end
    end
  end
  byKey[key] = out
  return out
end

-- Forgets the decoded spots (tests).
function GO.ResetCache()
  cache = setmetatable({}, { __mode = "k" })
end

-- Number of spots and of kinds with spots the set has in a zone.
function GO.Summary(data, mapId, set)
  local list = GO.Points(data, mapId, set)
  local seen, kinds = {}, 0
  for _, spot in ipairs(list) do
    for _, id in ipairs(spot.kinds) do
      if not seen[id] then
        seen[id] = true
        kinds = kinds + 1
      end
    end
  end
  return #list, kinds
end

-- The lines of a spot's tooltip: title and text. One kind: its name, then the category. Several kinds on one
-- spot: the category as the title, the names below.
function GO.TipText(data, pin)
  local kinds = kindsOf(data)
  local ids = pin.kinds or { pin.kind }
  local names = {}
  for i, id in ipairs(ids) do
    names[i] = GO.Name(id, kinds[id])
  end
  local first = kinds[ids[1]]
  local category = ns.L[first and "gather.cat." .. tostring(first.cat) or "map.gather.known"]
  local muted = function(text)
    return ns.Theme.hexText("textMuted", text)
  end
  if #names == 1 then
    return names[1], muted(category) .. "\n" .. muted(ns.L["map.gather.known"])
  end
  return category, table.concat(names, "\n") .. "\n" .. muted(ns.L["gather.obj.several"])
end

-- The feed the layer of ns.GatheringMap draws from (see Attach).
GO.Feed = {
  set = function(mapId)
    local data = ns.GatherDataAccess.Get()
    return data and GO.ZoneKinds(data, mapId) or nil
  end,
  points = GO.Points,
  summary = GO.Summary,
  zoneHas = GO.ZoneHas,
  icon = function(data, pin)
    return GO.IconPath(kindsOf(data)[pin.kind])
  end,
  iconKey = function(pin)
    return pin.kind
  end,
  tip = GO.TipText,
}
