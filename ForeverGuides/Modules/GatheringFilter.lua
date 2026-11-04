-- Which ores and herbs the player wants to see on the Blizzard world map (and on the minimap):
-- the player's own choice, the same in every zone and independent of the choice on the page "Ores and
-- herbs". Two switches for the professions and a list of the items switched off, all in settings.gather
-- (herbs, mining, hidden). An item the data adds later is on without a stored entry. No frames here; the
-- control is Modules/GatheringFilterUI.lua. Every change ends with the message FG_GATHER_FILTER_CHANGED.
-- ZoneItems is the one filter both maps draw with: everything this filter shows, narrowed by the choice of a
-- zone (ns.GatherSelection) when the player made one.
local _, ns = ...

local F = {}
ns.GatherFilter = F

-- The profession ids of the data and the setting key of each.
F.KEYS = { mining = "mining", herbalism = "herbs" }

local function section()
  local gather = ns.Store.get("settings.gather")
  return type(gather) == "table" and gather or {}
end

local function items(data)
  return type(data) == "table" and type(data.items) == "table" and data.items or {}
end

-- True when the profession ("mining" or "herbalism") is switched on.
function F.ProfessionOn(prof)
  local key = F.KEYS[prof]
  return key ~= nil and section()[key] ~= false
end

-- True when the item has no entry in the list of the items switched off.
function F.ItemOn(itemId)
  local hidden = section().hidden
  return not (type(hidden) == "table" and hidden[itemId] == true)
end

-- True when the item is known to the data, its profession is on and the item itself is not switched off.
function F.IsVisible(data, itemId)
  local item = items(data)[itemId]
  return type(item) == "table" and F.ProfessionOn(item.prof) and F.ItemOn(itemId)
end

-- The visible items of the data as a set { [itemId] = true }.
function F.VisibleItems(data)
  local out = {}
  for id in pairs(items(data)) do
    if F.IsVisible(data, id) then
      out[id] = true
    end
  end
  return out
end

-- The items to draw in a zone as a set { [itemId] = true }: every item the data has there that passes the
-- filter above. A zone without a stored choice shows all of them, a stored choice (an empty one too)
-- narrows them to the items it holds.
function F.ZoneItems(data, mapId)
  local out = {}
  local zones = type(data) == "table" and type(data.zones) == "table" and data.zones or {}
  local zone = zones[mapId]
  local chain = type(zone) == "table" and type(zone.items) == "table" and zone.items or {}
  local Sel = ns.GatherSelection
  local chosen = Sel.Has(mapId) and Sel.Get(mapId) or nil
  for id in pairs(chain) do
    if F.IsVisible(data, id) and (chosen == nil or chosen[id] == true) then
      out[id] = true
    end
  end
  return out
end

local function copyHidden()
  local out = {}
  local hidden = section().hidden
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

-- Items of the data that belong to the profession (nil: all of them), as a list of ids.
local function idsOf(data, prof)
  local ids = {}
  for id, item in pairs(items(data)) do
    if type(item) == "table" and F.KEYS[item.prof] and (prof == nil or item.prof == prof) then
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

-- Switches a profession on or off; the list of the items switched off stays as it is.
function F.SetProfession(prof, on)
  local key = F.KEYS[prof]
  if not key then
    return
  end
  ns.Store.set("settings.gather." .. key, on and true or false)
  changed()
end

-- Switches one item on or off.
function F.SetItem(itemId, on)
  if type(itemId) ~= "number" then
    return
  end
  local hidden = copyHidden()
  hidden[itemId] = (not on) and true or nil
  ns.Store.set("settings.gather.hidden", hidden)
  changed()
end

-- Everything on: the profession (nil: both) and each of its items. data is optional, it is read through
-- ns.GatherDataAccess when left out.
function F.All(prof, data)
  local hidden = copyHidden()
  if prof == nil then
    hidden = {}
  else
    for _, id in ipairs(idsOf(dataOrAccess(data), prof)) do
      hidden[id] = nil
    end
  end
  for p, key in pairs(F.KEYS) do
    if prof == nil or prof == p then
      ns.Store.set("settings.gather." .. key, true)
    end
  end
  ns.Store.set("settings.gather.hidden", hidden)
  changed()
end

-- Every item of the profession (nil: all) off. The switch of the profession stays as it is.
function F.None(prof, data)
  local hidden = copyHidden()
  for _, id in ipairs(idsOf(dataOrAccess(data), prof)) do
    hidden[id] = true
  end
  ns.Store.set("settings.gather.hidden", hidden)
  changed()
end
