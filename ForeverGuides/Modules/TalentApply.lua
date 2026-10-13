-- Talent apply and read-back through C_Traits. Adds the missing points of a build to the active
-- config (PurchaseRank on node IDs), opens Blizzard's own talent window, checks the staged
-- points and commits them. Points the character already spent are never taken back: the game
-- only refunds them at the class trainer for gold, so a build is applied as far as it fits (see
-- TL.Plan). Also reads the active config back for the editor. Every game call is defensive: a
-- missing API degrades to "staged only" or to an error message, never to a Lua error.
-- Errors are returned as (false, localeKey, arg1, arg2).
local _, ns = ...

ns.AddLocale("enUS", {
  ["talents.err.combat"] = "Not possible in combat.",
  ["talents.err.noconfig"] = "Talent data cannot be read in this game version.",
  ["talents.err.notree"] = "Talent tree could not be determined.",
  ["talents.err.empty"] = "There is nothing to apply.",
  ["talents.err.pointsunknown"] = "Your free talent points cannot be read in this game version: nothing applied",
  ["talents.err.nothing"] = "None of the missing points can be bought right now: nothing applied",
  ["talents.err.partial"] = "Only %d of %d points could be set: nothing applied",
  ["talents.err.mismatch"] = "Talent window does not match the plan: nothing applied",
  ["talents.apply.committed"] = "%d of %d missing points set and applied",
  ["talents.apply.unchanged"] = "All points of this build are already set, nothing was changed.",
  ["talents.apply.staged"] = "Points prepared: click Apply in the talent window",
})

ns.AddLocale("deDE", {
  ["talents.err.combat"] = "Im Kampf nicht möglich.",
  ["talents.err.noconfig"] = "Talentdaten sind in dieser Spielversion nicht auslesbar.",
  ["talents.err.notree"] = "Talentbaum konnte nicht ermittelt werden.",
  ["talents.err.empty"] = "Es gibt nichts anzuwenden.",
  ["talents.err.pointsunknown"] = "Deine freien Talentpunkte sind in dieser Spielversion nicht auslesbar: nichts angewendet",
  ["talents.err.nothing"] = "Von den fehlenden Punkten ist gerade keiner kaufbar: nichts angewendet",
  ["talents.err.partial"] = "Nur %d von %d Punkten setzbar: nichts angewendet",
  ["talents.err.mismatch"] = "Talentfenster passt nicht zum Plan: nichts angewendet",
  ["talents.apply.committed"] = "%d von %d fehlenden Punkten gesetzt und angewendet",
  ["talents.apply.unchanged"] = "Alle Punkte dieser Skillung sind schon gesetzt, es wurde nichts geändert.",
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

-- Unspent points of the tree's currency, nil when the game does not report it.
-- The config info has no currency field; the tree currency call is what the
-- game's own talent UI reads (staged changes included).
local function unspentOf(configId, treeId)
  local ok, list = call("C_Traits", "GetTreeCurrencyInfo", configId, treeId, false)
  local currency = ok and type(list) == "table" and list[1] or nil
  if type(currency) == "table" and type(currency.quantity) == "number" then
    return currency.quantity
  end
  return nil
end

-- Unspent talent points of the active config, nil when they cannot be read.
function TalentApply.unspentPoints()
  local configId = activeConfigId()
  local treeId = configId and treeIdOf(configId)
  return treeId and unspentOf(configId, treeId) or nil
end

-- Plan and staging ------------------------------------------------------------------

local function count(map)
  local n = 0
  for _ in pairs(map) do
    n = n + 1
  end
  return n
end

-- { [nodeID] = ranks } of entries { nodeID, ranksPurchased }.
local function nodeRanksOf(entries)
  local ranks = {}
  for _, e in ipairs(entries) do
    ranks[e.nodeID] = (ranks[e.nodeID] or 0) + (e.ranksPurchased or 1)
  end
  return ranks
end

-- What applying the entries (the build as { nodeID, ranksPurchased }, see TL.NodeEntries) would do
-- to the character right now, as a TL.Plan. Nothing is changed and no window is opened. `specs`
-- are the trees of the build's class (default: the player's class). Returns the plan and the
-- node ranks it was made from, or nil plus a locale key.
function TalentApply.preview(entries, specs)
  if inCombat() then
    return nil, "talents.err.combat"
  end
  local TL = ns.TalentLogic
  specs = specs or TL.Specs(ns.PageKit.PlayerClass())
  if not specs then
    return nil, "talents.err.notree"
  end
  if type(entries) ~= "table" or #entries == 0 then
    return nil, "talents.err.empty"
  end
  loadTalentUi()
  local current, key = TalentApply.readNodeRanks()
  if not current then
    return nil, key
  end
  local free = TalentApply.unspentPoints()
  if not free then
    return nil, "talents.err.pointsunknown"
  end
  local want = TL.RanksFromNodes(specs, nodeRanksOf(entries))
  local have = TL.RanksFromNodes(specs, current)
  return TL.Plan(specs, want, have, free), current
end

-- The game's own answer whether this rank can be bought. A client without the call leaves it to
-- PurchaseRank and the read-back.
local function canPurchase(configId, step)
  if type(C_Traits) ~= "table" or type(C_Traits.CanPurchaseRank) ~= "function" then
    return true
  end
  local ok, res = pcall(C_Traits.CanPurchaseRank, configId, step.node, step.entry)
  return ok and res and true or false
end

-- Buys the steps in their order and stops at the first one the game refuses. Never refunds a
-- point. Returns how many ranks were bought.
local function purchase(configId, steps)
  local bought = 0
  for _, step in ipairs(steps) do
    if not canPurchase(configId, step) then
      break
    end
    local ok, res = call("C_Traits", "PurchaseRank", configId, step.node)
    if not (ok and res) then
      break
    end
    bought = bought + 1
  end
  return bought
end

-- Commit -----------------------------------------------------------------------------

-- True when the tree holds exactly the ranks before plus the steps, nothing more or less.
local function stagedMatches(configId, before, steps)
  local treeId = treeIdOf(configId)
  local have = treeId and readRanks(configId, treeId)
  if not have then
    return false
  end
  local want = {}
  for node, ranks in pairs(before) do
    want[node] = ranks
  end
  for _, step in ipairs(steps) do
    want[step.node] = step.rank
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

-- Buys the points of the build that can be bought now, opens the talent window, checks the
-- result and commits. Never resets the tree: points the character spent elsewhere stay.
-- Returns true, state, applied, total with state "committed" (the game took the commit request),
-- "unchanged" (every point of the build is already set) or "staged" (points are placed, commit
-- refused or unavailable: the player presses Apply); applied counts the points bought, total
-- the points the build lacked. Failures return false, localeKey, arg1, arg2 and leave the
-- character's talents untouched (staged points are rolled back).
function TalentApply.applyAndCommit(entries, specs)
  local plan, current = TalentApply.preview(entries, specs)
  if not plan then
    return false, current
  end
  local sum = plan.summary
  if sum.total == 0 then
    return true, "unchanged", 0, 0
  end
  if sum.now == 0 then
    return false, "talents.err.nothing"
  end
  TalentApply.openTalentFrame()
  local configId = activeConfigId()
  local applied = purchase(configId, plan.steps)
  if applied < sum.now or not stagedMatches(configId, current, plan.steps) then
    call("C_Traits", "RollbackConfig", configId)
    return false, applied < sum.now and "talents.err.partial" or "talents.err.mismatch", applied, sum.now
  end
  return true, commit(configId) and "committed" or "staged", applied, sum.total
end
