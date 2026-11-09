-- Access to the quests of the instances in the load-on-demand add-on "Forever Guides: Instance data".
-- The add-on fills ns.InstanceQuests[English instance name] (docs/INSTANZEN-DATEN.md). This module loads it
-- on first use and puts every list back into its entry of ns.Data.Instances as `q`, so the readers of the
-- instance data see the same fields as before. Not in combat: the load waits for PLAYER_REGEN_ENABLED and
-- then sends FG_INSTANCE_DATA.
local _, ns = ...

local D = {}
ns.InstanceDataAccess = D

D.ADDON = "ForeverGuides_InstanceData"
-- ok: merged. combat: load postponed. missing: add-on not loadable. noData: add-on loaded without quests.
D.STATUS = { ok = "ok", combat = "combat", missing = "missing", noData = "noData" }

ns.AddLocale("enUS", {
  ["instancedata.combat"] = "Quest data loads after combat.",
  ["instancedata.missing"] = "Quest data missing or switched off",
  ["instancedata.noData"] = "No quest data found.",
  ["instancedata.counts"] = "%d boss(es), quests not loaded.",
})
ns.AddLocale("deDE", {
  ["instancedata.combat"] = "Daten laden nach dem Kampf.",
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

local function lists()
  local all = rawget(ns, "InstanceQuests")
  return type(all) == "table" and next(all) ~= nil and all or nil
end

-- Puts the quest list of every instance into its entry. Safe to call again. Returns true when there was data.
function D.Merge()
  local all = lists()
  local instances = ns.Data and ns.Data.Instances
  if not all or type(instances) ~= "table" then
    return false
  end
  for _, inst in ipairs(instances) do
    local rows = type(inst.n) == "table" and all[inst.n.en] or nil
    if type(rows) == "table" then
      inst.q = rows
    end
  end
  return true
end

-- True once the quests are in the instance entries.
function D.Loaded()
  return status == D.STATUS.ok
end

-- Loads the add-on when needed and merges. Returns "ok", "combat", "missing" or "noData". Cheap when done.
function D.Ensure()
  if status then
    return status
  end
  if not lists() and inCombat() then
    waiting = true
    return D.STATUS.combat
  end
  if not lists() then
    local ok = ns.LoadPackage(D.ADDON) == true
    if not ok then
      status = D.STATUS.missing
      return status
    end
  end
  status = D.Merge() and D.STATUS.ok or D.STATUS.noData
  return status
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
