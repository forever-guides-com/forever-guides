-- Access to the quests and the loot of the instances in the load-on-demand add-on "Forever Guides: Instance data".
-- The add-on fills ns.InstanceQuests[English instance name] and ns.InstanceLoot[English instance name]
-- (docs/INSTANZEN-DATEN.md). This module loads it on first use and puts every list back into its entry of
-- ns.Data.Instances: the quests as `q`, the loot of a boss as `lo` and the loot of the instance as `tl`, so the
-- readers of the instance data see the same fields as before. Readers outside the instance page call D.Loot or
-- D.Trash (they load first). Not in combat: the load waits for PLAYER_REGEN_ENABLED and then sends FG_INSTANCE_DATA.
local _, ns = ...

local D = {}
ns.InstanceDataAccess = D

D.ADDON = "ForeverGuides_InstanceData"
-- ok: merged. combat: load postponed. missing: add-on not loadable. noData: add-on loaded without data.
D.STATUS = { ok = "ok", combat = "combat", missing = "missing", noData = "noData" }

ns.AddLocale("enUS", {
  ["instancedata.combat"] = "Quest data loads after combat.",
  ["instancedata.missing"] = "Quest data missing or switched off",
  ["instancedata.noData"] = "No quest data found.",
  ["instancedata.counts"] = "%d boss(es), quests not loaded.",
})
ns.AddLocale("deDE", {
  ["instancedata.combat"] = "Questdaten laden nach dem Kampf.",
  ["instancedata.missing"] = "Questdaten fehlen oder sind ausgeschaltet",
  ["instancedata.noData"] = "Keine Questdaten gefunden.",
  ["instancedata.counts"] = "%d Boss(e), Quests nicht geladen.",
})

-- status: nil until the first try that ran, then ok, missing or noData (one load attempt per session).
local status
local waiting = false

local function inCombat()
  local fn = rawget(_G, "InCombatLockdown")
  if type(fn) ~= "function" then
    return false
  end
  local ok, value = pcall(fn)
  return ok and value == true
end

local function filled(key)
  local all = rawget(ns, key)
  return type(all) == "table" and next(all) ~= nil and all or nil
end

local function lists()
  return filled("InstanceQuests"), filled("InstanceLoot")
end

-- Loot entry of an instance: [boss number] = rows of that boss, tl = rows of the instance.
local function mergeLoot(inst, entry)
  for key, rows in pairs(entry) do
    if key == "tl" then
      inst.tl = rows
    elseif type(key) == "number" and type(inst.bo) == "table" and inst.bo[key] then
      inst.bo[key].lo = rows
    end
  end
end

-- Puts the quest list and the loot of every instance into its entry. Safe to call again. Returns true when there was data.
function D.Merge()
  local quests, loot = lists()
  local instances = ns.Data and ns.Data.Instances
  if not (quests or loot) or type(instances) ~= "table" then
    return false
  end
  for _, inst in ipairs(instances) do
    local name = type(inst.n) == "table" and inst.n.en or nil
    local rows = quests and name and quests[name]
    if type(rows) == "table" then
      inst.q = rows
    end
    local entry = loot and name and loot[name]
    if type(entry) == "table" then
      mergeLoot(inst, entry)
    end
  end
  return true
end

-- True once the quests and the loot are in the instance entries.
function D.Loaded()
  return status == D.STATUS.ok
end

-- Loads the add-on when needed and merges. Returns "ok", "combat", "missing" or "noData". Cheap when done.
function D.Ensure()
  if status then
    return status
  end
  local quests, loot = lists()
  local loaded = quests ~= nil or loot ~= nil
  if not loaded and inCombat() then
    waiting = true
    return D.STATUS.combat
  end
  if not loaded then
    local ok = ns.LoadPackage(D.ADDON) == true
    if not ok then
      status = D.STATUS.missing
      return status
    end
  end
  status = D.Merge() and D.STATUS.ok or D.STATUS.noData
  return status
end

-- Loot rows of boss number `index` of the instance, nil when the data has none (or is not loaded yet).
function D.Loot(inst, index)
  D.Ensure()
  local boss = type(inst) == "table" and type(inst.bo) == "table" and inst.bo[index] or nil
  return boss and boss.lo or nil
end

-- Loot rows of the instance that no boss owns, nil when the data has none.
function D.Trash(inst)
  D.Ensure()
  return type(inst) == "table" and inst.tl or nil
end

-- Routes of a dungeon map (list of routes, ForeverGuides_InstanceData/DungeonRoutes_<n>.lua) by DungeonAssets key.
function D.Routes(name)
  D.Ensure()
  local all = rawget(ns, "DungeonRoutes")
  local routes = type(all) == "table" and name and all[name] or nil
  return type(routes) == "table" and routes or nil
end

-- Room labels of a dungeon map (list of { f, x, y, n }, ForeverGuides_InstanceData/DungeonRooms_<n>.lua) by DungeonAssets key.
function D.Rooms(name)
  D.Ensure()
  local all = rawget(ns, "DungeonRooms")
  local rooms = type(all) == "table" and name and all[name] or nil
  return type(rooms) == "table" and rooms or nil
end

-- Reputation of a quest row of the instance data: gains = { { faction = id, amount = n }, ... } (empty when the quest gives
-- none) and need = { faction = id, standing = n } or nil. standing is the standing id of the reputation guide data
-- (1 Hated ... 8 Exalted, 4 Neutral). Pure: reads only the row, the faction name is the caller's business.
function D.Reputation(quest)
  local gains, need = {}, nil
  if type(quest) ~= "table" then
    return gains, need
  end
  for _, row in ipairs(type(quest.rp) == "table" and quest.rp or {}) do
    if type(row) == "table" and type(row.fac) == "number" and type(row.v) == "number" then
      gains[#gains + 1] = { faction = row.fac, amount = row.v }
    end
  end
  local req = quest.rr
  if type(req) == "table" and type(req.fac) == "number" and type(req.st) == "number" then
    need = { faction = req.fac, standing = req.st }
  end
  return gains, need
end

-- Pieces of a composed map floor (rows of 14 numbers, ForeverGuides_InstanceData/DungeonMinimaps_<n>.lua,
-- docs/DUNGEONMINIMAPS-FORMAT.md) by DungeonAssets key and floor number, nil when the data has none.
function D.Minimaps(name, floor)
  D.Ensure()
  local all = rawget(ns, "DungeonMinimaps")
  local floors = type(all) == "table" and name and all[name] or nil
  local pieces = type(floors) == "table" and floors[floor] or nil
  return type(pieces) == "table" and pieces or nil
end

-- The hint text for a status other than "ok".
function D.Hint(state)
  return ns.L["instancedata." .. (state == D.STATUS.combat and "combat" or state == D.STATUS.noData and "noData" or "missing")]
end

-- Forgets the load attempt (tests, and a switched-on add-on).
function D.Reset()
  status, waiting = nil, false
end

ns.On("PLAYER_REGEN_ENABLED", function()
  if waiting then
    waiting = false
    local state = D.Ensure()
    -- A search index built in the meantime has no quests.
    if ns.SearchLogic then
      ns.SearchLogic.ResetIndex()
    end
    ns.Emit("FG_INSTANCE_DATA", state)
  end
end)

-- The package banner switched the add-on on: ask again, the old "missing" answer is out of date.
ns.On("FG_PACKAGE_CHANGED", function(_, name)
  if name == D.ADDON then
    D.Reset()
  end
end)
