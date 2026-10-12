-- Raid boss kills per character and week: records every raid boss kill (ENCOUNTER_END,
-- BOSS_KILL, lockouts) in the roster entry (kills) and drops them at the weekly reset.
-- All reset arithmetic lives in RaidWeekLogic.lua; every game call is guarded.
local _, ns = ...

local RW = {}
ns.RaidWeek = RW

local W = ns.RaidWeekLogic

local function roster()
  local t = type(ns.db) == "table" and ns.db.roster
  return type(t) == "table" and t or nil
end

local function entryOf(charKey)
  local t = roster()
  return t and type(charKey) == "string" and type(t[charKey]) == "table" and t[charKey] or nil
end

local function now()
  return ns.CharRoster.Now()
end

-- The client's seconds until the weekly reset, nil without the function.
local function secondsUntilReset()
  local api = type(C_DateAndTime) == "table" and C_DateAndTime.GetSecondsUntilWeeklyReset
  if type(api) ~= "function" then
    return nil
  end
  local ok, secs = pcall(api)
  return ok and secs or nil
end

-- Epoch (server time) of the next weekly reset, read again on every call. A client
-- reading is remembered account-wide (ns.db.weekReset) for clients or moments without
-- one. Nil when the reset is not known at all.
function RW.NextReset()
  local db = type(ns.db) == "table" and ns.db or nil
  local reset, source = W.Next(now(), secondsUntilReset(), db and db.weekReset)
  if source == "api" and db then
    db.weekReset = reset
  end
  return reset
end

-- Epoch of the start of the current week, nil when the reset is not known.
function RW.WeekKey()
  local reset = RW.NextReset()
  return reset and W.Start(reset)
end

-- Drops the kills of earlier weeks of one character. True when something went.
local function rollover(entry)
  if type(entry.kills) ~= "table" then
    return false
  end
  return W.Prune(entry.kills, RW.NextReset(), now()) > 0
end

-- Week change for all characters (login), so a character that was offline for weeks
-- starts the new week empty.
function RW.Rollover()
  local changed = false
  for _, entry in pairs(roster() or {}) do
    if type(entry) == "table" and rollover(entry) then
      changed = true
    end
  end
  if changed then
    ns.Emit("FG_ROSTER_CHANGED")
  end
  return changed
end

-- Killed count, number of bosses and the killed ones { key, name, at, opt } (player
-- language) of one raid in the current week. A week change counts first, so the result
-- after the reset is 0.
function RW.Progress(charKey, raidKey)
  local inst = W.InstanceByKey(raidKey)
  if not inst then
    return 0, 0, {}
  end
  local entry = entryOf(charKey)
  if not entry then
    return 0, #(inst.bo or {}), {}
  end
  rollover(entry)
  local rec = type(entry.kills) == "table" and entry.kills[raidKey] or nil
  return W.Progress(rec, inst, ns.T)
end

-- Writes one kill, no event. True when it was new.
local function put(charKey, raidKey, bossKey, at)
  local entry = entryOf(charKey)
  local inst = W.InstanceByKey(raidKey)
  local reset = RW.NextReset()
  if not (entry and inst and reset and ns.CharRoster.Enabled()) then
    return false
  end
  local known = false
  for i, boss in ipairs(inst.bo or {}) do
    known = known or W.BossKey(boss, i) == bossKey
  end
  if not known then
    return false
  end
  if type(entry.kills) ~= "table" then
    entry.kills = {}
  end
  rollover(entry)
  return W.Mark(entry.kills, raidKey, bossKey, at or now(), reset)
end

-- Records a kill of the current week. Repeated reports change nothing (false).
function RW.MarkKill(charKey, raidKey, bossKey, at)
  if put(charKey, raidKey, bossKey, at) then
    ns.Emit("FG_ROSTER_CHANGED")
    return true
  end
  return false
end

-- Bosses a character's lockouts report as killed, for kills whose event was missed
-- (login inside the raid). The caller announces the change.
function RW.SyncLocks(charKey, locks)
  local at = now()
  for _, lock in ipairs(locks or {}) do
    local inst = ns.RaidLockLogic.Active(lock, at) and W.FindRaid(lock.instId, lock.name)
    if inst then
      for _, bossKey in ipairs(W.LockKills(lock, inst)) do
        put(charKey, W.RaidKey(inst), bossKey, at)
      end
    end
  end
end

-- Game events -----------------------------------------------------------------------------

local function currentInstance()
  if type(GetInstanceInfo) ~= "function" then
    return nil
  end
  local ok, name, _, _, _, _, _, _, instanceId = pcall(GetInstanceInfo)
  if ok then
    return name, instanceId
  end
end

-- A kill reported by the client in the current instance.
function RW.OnKill(encounterId, encounterName)
  local Roster = ns.CharRoster
  if not Roster.Enabled() then
    return false
  end
  local name, instanceId = currentInstance()
  local inst, raidKey = W.FindRaid(instanceId, name)
  local bossKey = inst and W.FindBoss(inst, encounterId, encounterName)
  if not bossKey then
    return false
  end
  local charKey = Roster.CurrentKey()
  if charKey and not entryOf(charKey) then
    charKey = Roster.Capture()
  end
  return RW.MarkKill(charKey, raidKey, bossKey)
end

ns.On("ENCOUNTER_END", function(_, encounterId, encounterName, _, _, success)
  if success == 1 or success == true then
    RW.OnKill(encounterId, encounterName)
  end
end)

ns.On("BOSS_KILL", function(_, encounterId, encounterName)
  RW.OnKill(encounterId, encounterName)
end)

ns.On("PLAYER_ENTERING_WORLD", function()
  RW.Rollover()
end)
