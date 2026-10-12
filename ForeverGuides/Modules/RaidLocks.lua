-- Raid lockouts of the current character: asks the client (RequestRaidInfo), reads the
-- saved instances when UPDATE_INSTANCE_INFO arrives and stores them in the roster entry
-- (raids). Every call is guarded, a client without one of the functions only leaves the
-- lockouts as they were. Matching and expiry live in RaidLockLogic.lua.
local _, ns = ...

local RL = {}
ns.RaidLocks = RL

local REQUEST_DELAY = 2
local MAX_READ = 40

local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local r = { pcall(fn, ...) }
  if r[1] then
    return unpack(r, 2)
  end
end

-- First boolean among the returns after the name: the kill flag sits there in the
-- clients known so far, its exact position is not relied on.
local function killed(r)
  for i = 3, 5 do
    if type(r[i]) == "boolean" then
      return r[i]
    end
  end
  return false
end

local function readBosses(index, total)
  local out = {}
  for j = 1, math.min(type(total) == "number" and total or 0, MAX_READ) do
    local r = { pcall(GetSavedInstanceEncounterInfo, index, j) }
    if r[1] and type(r[2]) == "string" then
      out[#out + 1] = { name = r[2], killed = killed(r) }
    end
  end
  return out
end

-- The client's lockout rows as raw rows for RaidLockLogic.Build, nil when the client
-- has no such list.
function RL.Read()
  local n = try(GetNumSavedInstances)
  if type(n) ~= "number" or type(GetSavedInstanceInfo) ~= "function" then
    return nil
  end
  local rows = {}
  for i = 1, math.min(n, MAX_READ) do
    local r = { pcall(GetSavedInstanceInfo, i) }
    if r[1] and type(r[2]) == "string" then
      local total = r[12]
      rows[#rows + 1] = {
        name = r[2],
        lockId = r[3],
        reset = r[4],
        difficultyID = r[5],
        locked = r[6],
        extended = r[7],
        difficultyName = r[11],
        numEncounters = total,
        encounterProgress = r[13],
        instanceID = r[15],
        bosses = type(GetSavedInstanceEncounterInfo) == "function" and readBosses(i, total) or {},
      }
    end
  end
  return rows
end

-- Reads the lockouts and writes them to the current character. Returns the number of
-- active lockouts, nil when nothing was written.
function RL.Capture()
  local Roster = ns.CharRoster
  if not Roster.Enabled() then
    return nil
  end
  local rows = RL.Read()
  local key = rows and Roster.CurrentKey()
  if not key then
    return nil
  end
  local t = type(ns.db) == "table" and ns.db.roster
  if type(t) ~= "table" or type(t[key]) ~= "table" then
    key = Roster.Capture()
    t = key and ns.db.roster
  end
  if not (key and type(t[key]) == "table") then
    return nil
  end
  local locks = ns.RaidLockLogic.Build(rows, Roster.Now())
  t[key].raids = locks
  t[key].raidsAt = Roster.Now()
  ns.RaidWeek.SyncLocks(key, locks)
  ns.Emit("FG_ROSTER_CHANGED")
  return #locks
end

-- At most one request per REQUEST_DELAY, whatever the number of events.
function RL.Request()
  if type(RequestRaidInfo) ~= "function" then
    return
  end
  ns.Debounce("raidlocks-request", REQUEST_DELAY, function()
    try(RequestRaidInfo)
  end)
end

ns.On("UPDATE_INSTANCE_INFO", function()
  RL.Capture()
end)

for _, event in ipairs({ "ENCOUNTER_END", "BOSS_KILL", "RAID_INSTANCE_WELCOME", "PLAYER_ENTERING_WORLD" }) do
  ns.On(event, RL.Request)
end
