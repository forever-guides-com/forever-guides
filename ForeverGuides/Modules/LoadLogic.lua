-- "When active" (ns.LoadLogic), without WoW API: the data of the conditions under which a HUD window or the
-- mouse cursor ring is there at all, their repair, the decision against a reading of the game state, the
-- one-time carry-over of the six old yes/no visibility rules and the one-line summary for the settings.
-- The game state itself is read by Modules/LoadState.lua, the controls are Modules/CanvasEditorLoad.lua.
--
-- Storage: a field `load` = { combat, instance, grouped, mounted, vehicle, target = true | false,
-- class = { mode = "is" | "isnot", list = { "WARLOCK", ... } }, spec = { mode, list = { specId, ... } },
-- character = { mode, list = { "Name-Realm", ... } } }.
-- A topic that is missing does not matter ("any"), true means it has to apply ("on"), false that it must not
-- ("off"). A load without any condition is nil.
local _, ns = ...
local L, CS = ns.L, ns.CharScopeLogic

local LL = {
  -- The yes/no topics in the order the settings show them.
  TOPICS = { "combat", "instance", "grouped", "mounted", "vehicle", "target" },
  -- The topics that hold a list of values.
  LISTS = { "class", "spec", "character" },
  MODES = { "is", "isnot" },
  CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" },
  MAX_LIST = 12,
  -- A list of characters may name every character of the register.
  MAX_CHARACTERS = CS.MAX_CHARACTERS,
  MAX_SPEC_ID = 99999,
  -- The keys of the first version: six booleans on a window, the first five of them on the ring.
  LEGACY = { "combatOnly", "outOfCombatOnly", "instanceOnly", "needsTarget", "hideMounted", "hideInVehicle" },
  -- Topics whose reading is not verified in combat on the Forever client yet (see docs/AREAS.md).
  UNVERIFIED = { grouped = true, spec = true },
}
ns.LoadLogic = LL

local TOPIC_SET, MODE_SET, CLASS_RANK, LIST_SET = {}, {}, {}, {}
for _, topic in ipairs(LL.TOPICS) do
  TOPIC_SET[topic] = true
end
for _, key in ipairs(LL.LISTS) do
  LIST_SET[key] = true
end
for _, mode in ipairs(LL.MODES) do
  MODE_SET[mode] = true
end
for i, token in ipairs(LL.CLASSES) do
  CLASS_RANK[token] = i
end

-- The words of a topic in the sentence "only <word>" / "not <word>", per topic and value.
local PARTS = {
  combat = { [true] = "load.sum.combatOn", [false] = "load.sum.combatOff" },
  instance = { [true] = "load.sum.instanceOn", [false] = "load.sum.instanceOff" },
  grouped = { [true] = "load.sum.groupedOn", [false] = "load.sum.groupedOff" },
  mounted = { [true] = "load.sum.mountedOn", [false] = "load.sum.mountedOff" },
  vehicle = { [true] = "load.sum.vehicleOn", [false] = "load.sum.vehicleOff" },
  target = { [true] = "load.sum.targetOn", [false] = "load.sum.targetOff" },
}

ns.AddLocale("enUS", {
  ["load.sum.none"] = "Always active.",
  ["load.sum.some"] = "Active: %s.",
  ["load.sum.combatOn"] = "only in combat",
  ["load.sum.combatOff"] = "only out of combat",
  ["load.sum.instanceOn"] = "only in instances",
  ["load.sum.instanceOff"] = "not in instances",
  ["load.sum.groupedOn"] = "only in a group",
  ["load.sum.groupedOff"] = "only without a group",
  ["load.sum.mountedOn"] = "only on a mount",
  ["load.sum.mountedOff"] = "not on a mount",
  ["load.sum.vehicleOn"] = "only in a vehicle",
  ["load.sum.vehicleOff"] = "not in a vehicle",
  ["load.sum.targetOn"] = "only with a target",
  ["load.sum.targetOff"] = "only without a target",
  ["load.sum.classIs"] = "only for %s",
  ["load.sum.classIsnot"] = "not for %s",
  ["load.sum.specIs"] = "only for %d chosen specializations",
  ["load.sum.specIsnot"] = "not for %d chosen specializations",
  ["load.sum.characterIs"] = "only for the %d chosen characters",
  ["load.sum.characterIsnot"] = "not for the %d chosen characters",
})
ns.AddLocale("deDE", {
  ["load.sum.none"] = "Immer aktiv.",
  ["load.sum.some"] = "Aktiv: %s.",
  ["load.sum.combatOn"] = "nur im Kampf",
  ["load.sum.combatOff"] = "nur außerhalb des Kampfes",
  ["load.sum.instanceOn"] = "nur in Instanzen",
  ["load.sum.instanceOff"] = "nicht in Instanzen",
  ["load.sum.groupedOn"] = "nur in einer Gruppe",
  ["load.sum.groupedOff"] = "nur ohne Gruppe",
  ["load.sum.mountedOn"] = "nur auf dem Reittier",
  ["load.sum.mountedOff"] = "nicht auf dem Reittier",
  ["load.sum.vehicleOn"] = "nur im Fahrzeug",
  ["load.sum.vehicleOff"] = "nicht im Fahrzeug",
  ["load.sum.targetOn"] = "nur mit Ziel",
  ["load.sum.targetOff"] = "nur ohne Ziel",
  ["load.sum.classIs"] = "nur für %s",
  ["load.sum.classIsnot"] = "nicht für %s",
  ["load.sum.specIs"] = "nur für %d gewählte Spezialisierungen",
  ["load.sum.specIsnot"] = "nicht für %d gewählte Spezialisierungen",
  ["load.sum.characterIs"] = "nur für die %d gewählten Charaktere",
  ["load.sum.characterIsnot"] = "nicht für die %d gewählten Charaktere",
})

-- Repair -------------------------------------------------------------------------------------------------

local function whole(v)
  return type(v) == "number" and v == v and v >= 1 and v <= LL.MAX_SPEC_ID and math.floor(v) == v
end

-- The values of a list that are valid, once each: class tokens in the order of LL.CLASSES, spec ids ascending,
-- character keys in alphabetical order.
local function cleanValues(key, raw)
  local seen, out = {}, {}
  if type(raw) ~= "table" then
    return out
  end
  for _, v in ipairs(raw) do
    local valid = key == "class" and CLASS_RANK[v] ~= nil
      or key == "spec" and whole(v)
      or key == "character" and CS.ValidKey(v)
    if valid and not seen[v] then
      seen[v] = true
      out[#out + 1] = v
    end
  end
  if key == "class" then
    table.sort(out, function(a, b)
      return CLASS_RANK[a] < CLASS_RANK[b]
    end)
  else
    table.sort(out)
  end
  local max = key == "character" and LL.MAX_CHARACTERS or LL.MAX_LIST
  while #out > max do
    out[#out] = nil
  end
  return out
end

-- The load of a raw value with every field valid, as a new table; nil when no condition is left.
function LL.Clean(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local load = {}
  for _, topic in ipairs(LL.TOPICS) do
    if type(raw[topic]) == "boolean" then
      load[topic] = raw[topic]
    end
  end
  for _, key in ipairs(LL.LISTS) do
    local entry = raw[key]
    if type(entry) == "table" and MODE_SET[entry.mode] then
      local list = cleanValues(key, entry.list)
      if #list > 0 then
        load[key] = { mode = entry.mode, list = list }
      end
    end
  end
  return next(load) ~= nil and load or nil
end

local function sameList(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

-- Whether two loads mean the same (after repair).
function LL.Equal(a, b)
  a, b = LL.Clean(a), LL.Clean(b)
  if a == nil or b == nil then
    return a == b
  end
  for _, topic in ipairs(LL.TOPICS) do
    if a[topic] ~= b[topic] then
      return false
    end
  end
  for _, key in ipairs(LL.LISTS) do
    local x, y = a[key], b[key]
    if (x == nil) ~= (y == nil) or x and (x.mode ~= y.mode or not sameList(x.list, y.list)) then
      return false
    end
  end
  return true
end

-- Decision ---------------------------------------------------------------------------------------------------

local function listPasses(entry, value, kind)
  if type(entry) ~= "table" or not MODE_SET[entry.mode] or type(entry.list) ~= "table" then
    return true
  end
  if type(value) ~= kind then
    return false
  end
  local found = false
  for _, v in ipairs(entry.list) do
    if v == value then
      found = true
      break
    end
  end
  return found == (entry.mode == "is")
end

-- Whether a load holds for `state` = { combat, instance, grouped, mounted, vehicle, target = boolean, class =
-- token, spec = id, character = "Name-Realm" } as ns.LoadState reads it. A topic the reader could not answer is nil: a condition that
-- does not matter still holds, a condition set to on, off, is or is not does not (the safe side: the thing stays
-- away). A value that is not usable counts as no condition. Does not change its arguments.
function LL.Passes(load, state)
  if type(load) ~= "table" then
    return true
  end
  state = type(state) == "table" and state or {}
  for _, topic in ipairs(LL.TOPICS) do
    local want = load[topic]
    if type(want) == "boolean" and state[topic] ~= want then
      return false
    end
  end
  return listPasses(load.class, state.class, "string")
    and listPasses(load.spec, state.spec, "number")
    and listPasses(load.character, state.character, "string")
end

-- Old rules ----------------------------------------------------------------------------------------------------

-- The load that means what the six old yes/no keys of `item` meant: combatOnly is combat on, outOfCombatOnly
-- combat off (both: the first wins), instanceOnly instance on, needsTarget target on, hideMounted mounted off,
-- hideInVehicle vehicle off. Only a true boolean counted. nil when no rule was on.
function LL.FromLegacy(item)
  if type(item) ~= "table" then
    return nil
  end
  local load = {}
  if item.combatOnly == true then
    load.combat = true
  elseif item.outOfCombatOnly == true then
    load.combat = false
  end
  if item.instanceOnly == true then
    load.instance = true
  end
  if item.needsTarget == true then
    load.target = true
  end
  if item.hideMounted == true then
    load.mounted = false
  end
  if item.hideInVehicle == true then
    load.vehicle = false
  end
  return next(load) ~= nil and load or nil
end

-- The load a stored table means: its `load` when that is a table, else what its old keys meant. Reading
-- never depends on whether the carry-over ran.
function LL.Of(item)
  if type(item) ~= "table" then
    return nil
  end
  if type(item.load) == "table" then
    return LL.Clean(item.load)
  end
  return LL.Clean(LL.FromLegacy(item))
end

-- Carries the old keys of a stored table (a window or the ring settings) over into `load`, once: a table with
-- an own load keeps it, one without gets it from the old keys. The old keys are removed afterwards, so a second
-- run changes nothing. Returns whether it changed something.
function LL.Migrate(item)
  if type(item) ~= "table" then
    return false
  end
  local found = false
  for _, key in ipairs(LL.LEGACY) do
    if item[key] ~= nil then
      found = true
    end
  end
  if not found then
    return false
  end
  if type(item.load) ~= "table" then
    item.load = LL.FromLegacy(item)
  end
  for _, key in ipairs(LL.LEGACY) do
    item[key] = nil
  end
  return true
end

-- Changes ----------------------------------------------------------------------------------------------------

-- A copy of `load` with a yes/no topic set to true, false or nil (any).
function LL.WithTopic(load, topic, value)
  local out = LL.Clean(load) or {}
  if TOPIC_SET[topic] then
    if type(value) == "boolean" then
      out[topic] = value
    else
      out[topic] = nil
    end
  end
  return LL.Clean(out)
end

-- A copy of `load` with the list topic `key` ("class", "spec", "character") in `mode` ("is", "isnot", nil for any); the list
-- stays as it was.
function LL.WithMode(load, key, mode)
  local out = LL.Clean(load) or {}
  local entry = out[key]
  if LIST_SET[key] and MODE_SET[mode] then
    out[key] = { mode = mode, list = entry and entry.list or {} }
  else
    out[key] = nil
  end
  return LL.Clean(out)
end

-- A copy of `load` with `value` added to or removed from the list of `key`; without a mode yet the list
-- starts in "is". A list that ends up empty means any.
function LL.WithMember(load, key, value, on)
  local out = LL.Clean(load) or {}
  local entry = out[key] or { mode = "is", list = {} }
  local list = {}
  for _, v in ipairs(entry.list) do
    if v ~= value then
      list[#list + 1] = v
    end
  end
  if on then
    list[#list + 1] = value
  end
  out[key] = { mode = entry.mode, list = list }
  return LL.Clean(out)
end

-- Text -------------------------------------------------------------------------------------------------------

-- The names of the class tokens of a list, joined.
local function classNames(list)
  local names = {}
  for i, token in ipairs(list) do
    local key = "class." .. token
    names[i] = L[key] ~= key and L[key] or token
  end
  return table.concat(names, ", ")
end

-- One sentence for the settings: "Active: only in combat, only with a target." or "Always active."
function LL.Summary(load)
  load = LL.Clean(load)
  if not load then
    return L["load.sum.none"]
  end
  local parts = {}
  for _, topic in ipairs(LL.TOPICS) do
    if load[topic] ~= nil then
      parts[#parts + 1] = L[PARTS[topic][load[topic]]]
    end
  end
  if load.class then
    parts[#parts + 1] =
      string.format(L["load.sum.class" .. (load.class.mode == "is" and "Is" or "Isnot")], classNames(load.class.list))
  end
  if load.spec then
    parts[#parts + 1] =
      string.format(L["load.sum.spec" .. (load.spec.mode == "is" and "Is" or "Isnot")], #load.spec.list)
  end
  if load.character then
    parts[#parts + 1] =
      string.format(L["load.sum.character" .. (load.character.mode == "is" and "Is" or "Isnot")], #load.character.list)
  end
  return string.format(L["load.sum.some"], table.concat(parts, ", "))
end

-- The topics of `load` that are set and not verified in combat yet, in the order of the settings.
function LL.Unverified(load)
  load = LL.Clean(load)
  local out = {}
  if not load then
    return out
  end
  for _, topic in ipairs(LL.TOPICS) do
    if load[topic] ~= nil and LL.UNVERIFIED[topic] then
      out[#out + 1] = topic
    end
  end
  for _, key in ipairs(LL.LISTS) do
    if load[key] ~= nil and LL.UNVERIFIED[key] then
      out[#out + 1] = key
    end
  end
  return out
end
