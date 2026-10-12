-- Talent apply and read-back through C_Traits. Stages a build in the active
-- config (ResetTree / PurchaseRank on node IDs), opens Blizzard's own talent
-- window, checks the staged points and commits them. Also reads the active
-- config back for the editor. Every game call is defensive: a missing API
-- degrades to "staged only" or to an error message, never to a Lua error.
-- Errors are returned as (false, localeKey, arg1, arg2).
local _, ns = ...

ns.AddLocale("enUS", {
  ["talents.err.combat"] = "Not possible in combat.",
  ["talents.err.noconfig"] = "Talent data cannot be read in this game version.",
  ["talents.err.notree"] = "Talent tree could not be determined.",
  ["talents.err.empty"] = "There is nothing to apply.",
  ["talents.err.points"] = "Build needs %d points, you have %d: not applied",
  ["talents.err.pointsunknown"] = "Build needs %d points, at least %d spent, rest unreadable: not applied",
  ["talents.err.partial"] = "Only %d of %d talents settable: nothing applied",
  ["talents.err.mismatch"] = "Talent window does not match the build: nothing applied",
  ["talents.apply.committed"] = "%d of %d talents set and applied",
  ["talents.apply.unchanged"] = "This build is already active, nothing was changed.",
  ["talents.apply.staged"] = "Points prepared: click Apply in the talent window",
})

ns.AddLocale("deDE", {
  ["talents.err.combat"] = "Im Kampf nicht möglich.",
  ["talents.err.noconfig"] = "Talentdaten sind in dieser Spielversion nicht auslesbar.",
  ["talents.err.notree"] = "Talentbaum konnte nicht ermittelt werden.",
  ["talents.err.empty"] = "Es gibt nichts anzuwenden.",
  ["talents.err.points"] = "Build braucht %d Punkte, du hast %d: nicht angewendet",
  ["talents.err.pointsunknown"] = "Build braucht %d Punkte, mindestens %d investiert, Rest unlesbar: nicht angewendet",
  ["talents.err.partial"] = "Nur %d von %d Talenten setzbar: nichts angewendet",
  ["talents.err.mismatch"] = "Talentfenster passt nicht zum Build: nichts angewendet",
  ["talents.apply.committed"] = "%d von %d Talenten gesetzt und angewendet",
  ["talents.apply.unchanged"] = "Dieser Build ist bereits aktiv, es wurde nichts geändert.",
  ["talents.apply.staged"] = "Punkte vorbereitet: im Talentfenster auf Anwenden klicken",
})

local TalentApply = {}
ns.TalentApply = TalentApply

-- Calls _G[owner][name](...) (or _G[name] without owner). Returns false when
-- the function is missing or raised, otherwise true plus its results.
local function call(owner, name, ...)
  local scope = owner and _G[owner] or _G
  local fn = type(scope) == "table" and scope[name]
  if type(fn) ~= "function" then
    return false
  end
  return pcall(fn, ...)
end

local function inCombat()
  local ok, locked = pcall(InCombatLockdown)
  return not ok or locked and true or false
end

-- Talent UI addon name differs between client generations.
local function loadTalentUi()
  for _, name in ipairs({ "Blizzard_PlayerSpells", "Blizzard_ClassTalentUI" }) do
    call("C_AddOns", "LoadAddOn", name)
  end
end

-- Blizzard's talent window ---------------------------------------------------------

local TALENT_FRAMES = { "PlayerSpellsFrame", "ClassTalentFrame", "TalentFrame" }
local TALENT_TOGGLES = { "ToggleTalentFrame", "ToggleClassTalentFrame" }

local function talentFrameShown()
  for _, name in ipairs(TALENT_FRAMES) do
    local frame = _G[name]
    if type(frame) == "table" and type(frame.IsShown) == "function" then
      local ok, shown = pcall(frame.IsShown, frame)
      if ok and shown then
        return true
      end
    end
  end
  return false
end

-- Opens the talent window by whatever the client offers, newest API first.
-- Toggles only run while the window is closed so they cannot close it again.
-- Returns whether a talent window is visible afterwards.
function TalentApply.openTalentFrame()
  loadTalentUi()
  call("PlayerSpellsUtil", "OpenToClassTalentsTab")
  if talentFrameShown() then
    return true
  end
  for _, name in ipairs(TALENT_TOGGLES) do
    call(nil, name)
    if talentFrameShown() then
      return true
    end
  end
  for _, name in ipairs(TALENT_FRAMES) do
    if type(_G[name]) == "table" then
      call(nil, "ShowUIPanel", _G[name])
      if talentFrameShown() then
        return true
      end
    end
  end
  return false
end

-- Config access ---------------------------------------------------------------------

local function activeConfigId()
  local ok, id = call("C_ClassTalents", "GetActiveConfigID")
  return ok and id or nil
end

local function treeIdOf(configId)
  local ok, info = call("C_Traits", "GetConfigInfo", configId)
  if not ok or type(info) ~= "table" or type(info.treeIDs) ~= "table" then
    return nil
  end
  return info.treeIDs[1]
end

-- { [nodeID] = purchased ranks } for every node of the tree that holds points,
-- or nil when the tree cannot be read.
local function readRanks(configId, treeId)
  local ok, nodes = call("C_Traits", "GetTreeNodes", treeId)
  if not ok or type(nodes) ~= "table" then
    return nil
  end
  local ranks = {}
  for _, nodeId in ipairs(nodes) do
    local nOk, info = call("C_Traits", "GetNodeInfo", configId, nodeId)
    if nOk and type(info) == "table" and (info.ranksPurchased or 0) > 0 then
      ranks[nodeId] = info.ranksPurchased
    end
  end
  return ranks
end

-- Whether the talent config can be used right now: true, or false plus the
-- locale key of the reason (combat, no config, no tree). `combat` = true
-- forces the combat answer for combat events, where the lockdown flag may lag.
function TalentApply.available(combat)
  if combat or inCombat() then
    return false, "talents.err.combat"
  end
  local configId = activeConfigId()
  if not configId then
    return false, "talents.err.noconfig"
  end
  if not treeIdOf(configId) then
    return false, "talents.err.notree"
  end
  return true
end

-- Purchased ranks of the player's active config as { [nodeID] = ranks }, or
-- nil plus a locale key. Staged, uncommitted points count as well.
function TalentApply.readNodeRanks()
  local ok, key = TalentApply.available()
  if not ok then
    return nil, key
  end
  local configId = activeConfigId()
  local ranks = readRanks(configId, treeIdOf(configId))
  if not ranks then
    return nil, "talents.err.noconfig"
  end
  return ranks
end

-- Staging ----------------------------------------------------------------------------

local function purchaseEntries(configId, entries)
  local done = 0
  for i, node in pairs(entries) do
    local success = false
    if node.selectionEntryID then
      local ok, res = call("C_Traits", "SetSelection", configId, node.nodeID, node.selectionEntryID)
      success = ok and res
    elseif node.ranksPurchased then
      -- Buy only missing ranks: an earlier pass may have placed some.
      local function current()
        local ok, info = call("C_Traits", "GetNodeInfo", configId, node.nodeID)
        return ok and type(info) == "table" and info.ranksPurchased or 0
      end
      local guard = node.ranksPurchased
      while current() < node.ranksPurchased and guard > 0 do
        guard = guard - 1
        local ok, res = call("C_Traits", "PurchaseRank", configId, node.nodeID)
        if not (ok and res) then
          break
        end
      end
      success = current() >= node.ranksPurchased
    end
    if success then
      done = done + 1
      entries[i] = nil
    end
  end
  return done
end

local function count(map)
  local n = 0
  for _ in pairs(map) do
    n = n + 1
  end
  return n
end

local function stage(configId, treeId, entries)
  -- purchaseEntries empties what it placed, the caller's list stays intact.
  local pending = {}
  for i, e in pairs(entries) do
    pending[i] = e
  end
  local total = count(pending)
  if total == 0 then
    return false, "talents.err.empty"
  end
  if not call("C_Traits", "ResetTree", configId, treeId) then
    return false, "talents.err.notree"
  end
  -- Purchasing unlocks further nodes, so repeat until a pass places nothing.
  while purchaseEntries(configId, pending) > 0 do
  end
  return true, total - count(pending), total
end

local function sumRanks(entries)
  local n = 0
  for _, e in pairs(entries) do
    n = n + (e.ranksPurchased or 1)
  end
  return n
end

local function sumValues(map)
  local n = 0
  for _, v in pairs(map) do
    n = n + v
  end
  return n
end

-- Unspent points of the tree's currency, nil when the game does not report it.
-- The config info has no currency field; the tree currency call is what the
-- game's own talent UI reads (staged changes included).
local function unspentPoints(configId, treeId)
  local ok, list = call("C_Traits", "GetTreeCurrencyInfo", configId, treeId, false)
  local currency = ok and type(list) == "table" and list[1] or nil
  if type(currency) == "table" and type(currency.quantity) == "number" then
    return currency.quantity
  end
  return nil
end

-- Refuses a build that needs more points than invested plus unspent ones, and
-- one that cannot be measured at all, so the reset in stage() never leaves the
-- player with fewer talents than before.
local function stageWithinBudget(configId, treeId, entries)
  local current = readRanks(configId, treeId)
  if not current then
    return false, "talents.err.noconfig"
  end
  local required, invested = sumRanks(entries), sumValues(current)
  local unspent = unspentPoints(configId, treeId)
  if unspent then
    if required > invested + unspent then
      return false, "talents.err.points", required, invested + unspent
    end
  elseif required > invested then
    return false, "talents.err.pointsunknown", required, invested
  end
  return stage(configId, treeId, entries)
end

-- Stages entries of the shape { nodeID, ranksPurchased, selectionEntryID? }
-- (for example from the talent editor) in the active, uncommitted config.
-- Returns true, applied, total or false, localeKey, arg1, arg2.
function TalentApply.applyEntries(entries)
  if inCombat() then
    return false, "talents.err.combat"
  end
  loadTalentUi()
  local configId = activeConfigId()
  local treeId = configId and treeIdOf(configId)
  if not treeId then
    return false, "talents.err.notree"
  end
  return stageWithinBudget(configId, treeId, entries)
end

-- Commit -----------------------------------------------------------------------------

-- True when the tree holds exactly the wanted ranks, nothing more or less.
local function stagedMatches(configId, entries)
  local treeId = treeIdOf(configId)
  local have = treeId and readRanks(configId, treeId)
  if not have then
    return false
  end
  local want = {}
  for _, e in ipairs(entries) do
    want[e.nodeID] = (want[e.nodeID] or 0) + (e.ranksPurchased or 1)
  end
  for nodeId, ranks in pairs(want) do
    if have[nodeId] ~= ranks then
      return false
    end
  end
  return count(have) == count(want)
end

-- Asks the game to commit the staged config. The class-talent wrapper is only
-- the fallback for a client without C_Traits.CommitConfig.
local function commit(configId)
  local ok, res = call("C_Traits", "CommitConfig", configId)
  if not ok then
    ok, res = call("C_ClassTalents", "CommitConfig")
  end
  return ok and res and true or false
end

-- Opens the talent window, places the entries, checks them and commits.
-- Returns true, state, applied, total with state "committed" (the game took
-- the commit request), "unchanged" (the build was already active) or
-- "staged" (points are placed, commit refused or unavailable: the player
-- presses Apply). Failures return false, localeKey, arg1, arg2 and leave
-- the character's talents untouched (staged points are rolled back).
function TalentApply.applyAndCommit(entries)
  if inCombat() then
    return false, "talents.err.combat"
  end
  TalentApply.openTalentFrame()
  local ok, applied, total, extra = TalentApply.applyEntries(entries)
  if not ok then
    return false, applied, total, extra
  end
  local configId = activeConfigId()
  if applied < total or not stagedMatches(configId, entries) then
    call("C_Traits", "RollbackConfig", configId)
    return false, applied < total and "talents.err.partial" or "talents.err.mismatch", applied, total
  end
  local hasChanges, changed = call("C_Traits", "ConfigHasStagedChanges", configId)
  if hasChanges and changed == false then
    return true, "unchanged", applied, total
  end
  return true, commit(configId) and "committed" or "staged", applied, total
end
