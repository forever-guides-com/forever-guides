-- Boss progress of one dungeon visit as pure logic (no UI, no events; Modules/BossProgress.lua connects it). The Forever
-- client does not fire ENCOUNTER_END or BOSS_KILL (measured in the Ruins of Lordaeron), so a kill is read
-- from what does arrive:
--   ENCOUNTER_START (encounter ID and name)      -> Start: which boss is being fought
--   UPDATE_INSTANCE_INFO after that              -> InstanceInfo: the boss is "likely" dead (a wipe is not
--                                                   distinguishable by this event alone)
--   LOOT_OPENED with a corpse source (NPC ID)    -> Loot: the boss is "confirmed" dead
--   lockout list of the client                   -> Lock: kills it lists are "confirmed", open bosses drop a guess
-- Bosses come from PinLogic.BossList: { idx, name = { en, de }, eid, npc, opt }.
local _, ns = ...

local BP = {}
ns.BossProgressLogic = BP

BP.LIKELY, BP.CONFIRMED = "likely", "confirmed"
-- An encounter that started longer ago than this (seconds) is not claimed by a later UPDATE_INSTANCE_INFO.
BP.MAX_AGE = 1800

function BP.New(instanceId, bosses)
  return { instanceId = instanceId, bosses = bosses or {}, current = nil, status = {} }
end

local function sameName(boss, key)
  local n = boss.name or {}
  return key ~= nil and (ns.DungeonAreaLogic.Key(n.en) == key or ns.DungeonAreaLogic.Key(n.de) == key)
end

-- By encounter ID when the data has one, else by name (either language).
local function byEncounter(state, encounterId, name)
  local key = ns.DungeonAreaLogic.Key(name)
  for _, b in ipairs(state.bosses) do
    if (encounterId and b.eid == encounterId) or (not b.eid and sameName(b, key)) then
      return b.idx
    end
  end
end

-- ENCOUNTER_START: remembers the fight. Returns the boss index, nil for an encounter the data does not list.
function BP.Start(state, encounterId, name, now)
  local idx = byEncounter(state, encounterId, name)
  state.current = { idx = idx, id = encounterId, name = name, t = now }
  return idx
end

-- UPDATE_INSTANCE_INFO: claims the running encounter as a likely kill. Returns the boss index or nil.
function BP.InstanceInfo(state, now)
  local c = state.current
  if not c then
    return nil
  end
  state.current = nil
  if now and c.t and now - c.t > BP.MAX_AGE then
    return nil
  end
  if c.idx and state.status[c.idx] ~= BP.CONFIRMED then
    state.status[c.idx] = BP.LIKELY
    return c.idx
  end
end

-- The NPC ID of a creature GUID ("Creature-0-3913-2999-1234-250657-00001A2B3C"), nil for anything else.
function BP.NpcFromGuid(guid)
  if type(guid) ~= "string" then
    return nil
  end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-[^-]+$")
  if kind == "Creature" or kind == "Vehicle" then
    return tonumber(id)
  end
end

-- LOOT_OPENED source: a boss corpse confirms the kill. npcId from NpcFromGuid. A boss whose data has an NPC ID
-- matches only that ID; one without matches by encounter ID or by the corpse name. Returns the boss index or nil.
function BP.Loot(state, npcId, name, encounterId)
  if type(npcId) ~= "number" then
    return nil
  end
  local key = ns.DungeonAreaLogic.Key(name)
  for _, b in ipairs(state.bosses) do
    local hit
    if b.npc then
      hit = b.npc == npcId
    else
      hit = (encounterId ~= nil and b.eid == encounterId) or (key ~= nil and sameName(b, key))
    end
    if hit then
      state.status[b.idx] = BP.CONFIRMED
      if state.current and state.current.idx == b.idx then
        state.current = nil
      end
      return b.idx
    end
  end
end

-- Lockout of the client: lock = { [bossIdx] = true (killed) | false (open) } for the bosses the lockout lists.
-- A listed kill is certain, an open boss cancels a "likely" guess. Returns true when a status changed.
function BP.Lock(state, lock)
  local changed = false
  for _, b in ipairs(state.bosses) do
    local v = lock[b.idx]
    if v == true and state.status[b.idx] ~= BP.CONFIRMED then
      state.status[b.idx] = BP.CONFIRMED
      changed = true
    elseif v == false and state.status[b.idx] == BP.LIKELY then
      state.status[b.idx] = nil
      changed = true
    end
  end
  local c = state.current
  if c and c.idx and lock[c.idx] == true then
    state.current = nil
  end
  return changed
end

-- Storable form of the statuses: { [bossIdx] = "l" | "c" }.
function BP.Pack(state)
  local out = {}
  for idx, s in pairs(state.status) do
    out[idx] = s == BP.CONFIRMED and "c" or "l"
  end
  return out
end

-- Takes statuses back from Pack; unknown bosses and values are dropped.
function BP.Unpack(state, packed)
  if type(packed) ~= "table" then
    return
  end
  for _, b in ipairs(state.bosses) do
    local v = packed[b.idx]
    if v == "c" or v == "l" then
      state.status[b.idx] = v == "c" and BP.CONFIRMED or BP.LIKELY
    end
  end
end

-- { killed = number of bosses likely or confirmed dead, total, next = index of the first boss not yet dead
-- that is not optional (nil when all are) }.
function BP.Summary(state)
  local killed, nextIdx = 0, nil
  for _, b in ipairs(state.bosses) do
    if state.status[b.idx] then
      killed = killed + 1
    elseif not b.opt and not nextIdx then
      nextIdx = b.idx
    end
  end
  return { killed = killed, total = #state.bosses, next = nextIdx }
end
