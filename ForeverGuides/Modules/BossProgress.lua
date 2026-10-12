-- Boss progress per instance: connects BossProgressLogic to the client. Sources are ENCOUNTER_START,
-- UPDATE_INSTANCE_INFO (with the lockout list, which settles the guess), and the looted boss corpse
-- (FG_LOOT_SOURCE from LootCapture). ENCOUNTER_END, BOSS_KILL and the combat log are not used (the client
-- does not deliver the first two, the combat log is reserved for Blizzard).
--
-- Bosses are addressed by their 1-based position in Data.Instances[..].bo (the same index PinLogic.BossList
-- and the instance view use). Stored in ns.charDB.bossProgress = { [instanceId] = { exp, t, st = { [idx] = "l"|"c" } } }
-- until the lockout ends (t = time of the latest kill); without a lockout a visit is remembered for VISIT_TTL.
-- Every client call is guarded.
local _, ns = ...

local BP = {}
ns.BossProgress = BP

local Logic = ns.BossProgressLogic
local MAX_INSTANCES = 40
local VISIT_TTL = 2 * 3600

-- Logic state per instance id (false = the data has no bosses for it).
local states = {}
-- The state that saw the latest ENCOUNTER_START.
local running

local function now()
  return ns.CharRoster.Now()
end

local function store()
  local db = ns.charDB
  if type(db) ~= "table" then
    return nil
  end
  if type(db.bossProgress) ~= "table" then
    db.bossProgress = {}
  end
  return db.bossProgress
end

-- Drops ended and malformed entries and keeps the table within MAX_INSTANCES.
local function prune(db)
  local t, count, oldest, oldestExp = now(), 0, nil, nil
  for id, e in pairs(db) do
    if type(id) ~= "number" or type(e) ~= "table" or type(e.exp) ~= "number" or e.exp <= t then
      db[id] = nil
    else
      count = count + 1
      if not oldestExp or e.exp < oldestExp then
        oldest, oldestExp = id, e.exp
      end
    end
  end
  if count > MAX_INSTANCES then
    db[oldest] = nil
  end
end

-- kill: a status was just earned, so the time of the latest kill moves to now.
local function save(state, kill)
  local db = store()
  if not db then
    return
  end
  local packed = Logic.Pack(state)
  if next(packed) == nil then
    db[state.instanceId] = nil
    return
  end
  state.exp = state.exp or (now() + VISIT_TTL)
  if kill then
    state.t = now()
  end
  db[state.instanceId] = { exp = state.exp, t = state.t, st = packed }
  prune(db)
end

-- The lockout or visit has ended: the next one starts without kills.
local function expire(state)
  if state.exp and state.exp <= now() then
    state.status, state.exp, state.t = {}, nil, nil
    local db = store()
    if db then
      db[state.instanceId] = nil
    end
  end
end

local function get(instanceId)
  if type(instanceId) ~= "number" then
    return nil
  end
  local state = states[instanceId]
  if state == nil then
    local list = ns.PinLogic.BossList(instanceId)
    if #list == 0 then
      states[instanceId] = false
      return nil
    end
    state = Logic.New(instanceId, list)
    local db = store()
    local saved = db and db[instanceId]
    if type(saved) == "table" and type(saved.exp) == "number" and saved.exp > now() then
      state.exp = saved.exp
      state.t = type(saved.t) == "number" and saved.t or nil
      Logic.Unpack(state, saved.st)
    end
    states[instanceId] = state
  end
  if state then
    expire(state)
  end
  return state or nil
end

ns.AddLocale("enUS", {
  ["bossprogress.defeated"] = "defeated",
  ["bossprogress.likely"] = "probably defeated",
  ["bossprogress.summary.one"] = "%d of 1 boss defeated",
  ["bossprogress.summary.other"] = "%d of %d bosses defeated",
  ["bossprogress.saved.one"] = "%d of 1 boss saved as defeated",
  ["bossprogress.saved.other"] = "%d of %d bosses saved as defeated",
})

ns.AddLocale("deDE", {
  ["bossprogress.defeated"] = "besiegt",
  ["bossprogress.likely"] = "wahrscheinlich besiegt",
  ["bossprogress.summary.one"] = "%d von 1 Boss besiegt",
  ["bossprogress.summary.other"] = "%d von %d Bossen besiegt",
  ["bossprogress.saved.one"] = "%d von 1 Boss als besiegt gespeichert",
  ["bossprogress.saved.other"] = "%d von %d Bossen als besiegt gespeichert",
})

-- Public API -------------------------------------------------------------------------------------

-- "confirmed" (lockout or looted corpse), "likely" (encounter seen, then the instance info) or nil.
function BP.Status(instanceId, bossIndex)
  local state = get(instanceId)
  return state and state.status[bossIndex] or nil
end

function BP.IsDefeated(instanceId, bossIndex)
  return BP.Status(instanceId, bossIndex) ~= nil
end

-- { killed, total, next } as BossProgressLogic.Summary, nil for an instance without bosses in the data.
function BP.Summary(instanceId)
  local state = get(instanceId)
  return state and Logic.Summary(state) or nil
end

-- "n of m bosses defeated" (kind "summary") or "... saved as defeated" (kind "saved") for a Summary result.
function BP.SummaryText(summary, kind)
  local key = "bossprogress." .. (kind or "summary") .. "." .. (summary.total == 1 and "one" or "other")
  return string.format(ns.L[key], summary.killed, summary.total)
end

-- Client -----------------------------------------------------------------------------------------

-- Id of the dungeon or raid the player is in, nil elsewhere.
local function currentInstanceId()
  if type(GetInstanceInfo) ~= "function" then
    return nil
  end
  local r = { pcall(GetInstanceInfo) }
  if r[1] and (r[3] == "party" or r[3] == "raid") and type(r[9]) == "number" then
    return r[9]
  end
end

-- Lockouts of the character as { [instanceId] = { map = { [bossIdx] = true|false }, expires } }.
local function lockMaps()
  local rows = ns.RaidLocks.Read()
  local maps = {}
  if not rows then
    return maps
  end
  local RLL, t = ns.RaidLockLogic, now()
  local locks = RLL.Build(rows, t)
  for _, lock in ipairs(locks) do
    local inst = RLL.Find(lock)
    if inst and type(inst.id) == "number" and not maps[inst.id] then
      local view = RLL.Combine(locks, inst, t)
      local map = {}
      for i, b in ipairs(view.bosses) do
        map[i] = b.state
      end
      maps[inst.id] = { map = map, expires = view.expires }
    end
  end
  return maps
end

-- Time (server seconds) of the latest kill of this instance, nil when there is none or it is not known.
function BP.LastKill(instanceId)
  local state = get(instanceId)
  return state and next(state.status) ~= nil and state.t or nil
end

-- True while a lockout of the client lists a kill of this instance: the game decides then, not the player.
function BP.Locked(instanceId)
  local m = lockMaps()[instanceId]
  if m then
    for _, killed in pairs(m.map) do
      if killed == true then
        return true
      end
    end
  end
  return false
end

-- Forgets the progress of this instance (a new run starts without kills). Returns true when there was any.
function BP.Reset(instanceId)
  local state = get(instanceId)
  if not state then
    return false
  end
  local had = next(state.status) ~= nil
  state.status, state.exp, state.t, state.current = {}, nil, nil, nil
  local db = store()
  if db then
    db[instanceId] = nil
  end
  if had then
    ns.Emit("FG_BOSS_PROGRESS")
  end
  return had
end

-- Instance ID of the dungeon or raid the player is in (nil elsewhere), for the modules that ask for the progress.
BP.CurrentInstance = currentInstanceId

ns.On("ENCOUNTER_START", function(_, encounterId, name)
  running = get(currentInstanceId())
  if running then
    Logic.Start(
      running,
      type(encounterId) == "number" and encounterId or nil,
      type(name) == "string" and name or nil,
      now()
    )
  end
end)

-- A zone change after the start means a wipe or a leave, not a kill: the kill's UPDATE_INSTANCE_INFO arrives
-- without one.
ns.On("PLAYER_ENTERING_WORLD", function()
  if running then
    running.current = nil
    running = nil
  end
end)

ns.On("UPDATE_INSTANCE_INFO", function()
  local changed = false
  local maps = lockMaps()
  for id, m in pairs(maps) do
    local state = get(id)
    if state then
      local moved = state.exp ~= m.expires
      state.exp = m.expires
      local lockChanged = Logic.Lock(state, m.map)
      if lockChanged or moved then
        save(state, lockChanged)
      end
      changed = changed or lockChanged
    end
  end
  local c = running and running.current
  -- A lockout that lists the running boss decided already; a wipe outside the instance is no kill.
  local m = c and maps[running.instanceId]
  if c and not (m and c.idx and m.map[c.idx] ~= nil) and currentInstanceId() == running.instanceId then
    if Logic.InstanceInfo(running, now()) then
      save(running, true)
      changed = true
    end
  end
  if changed then
    ns.Emit("FG_BOSS_PROGRESS")
  end
end)

ns.On("FG_LOOT_SOURCE", function(_, instanceId, npcId, name, encounterId)
  local state = get(instanceId)
  if state and Logic.Loot(state, npcId, name, encounterId) then
    save(state, true)
    ns.Emit("FG_BOSS_PROGRESS")
  end
end)
