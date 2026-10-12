-- Raid boss kills per week without game calls. A week is the interval between two weekly
-- resets, given as server-time epochs (UTC seconds), so no time zone or local clock enters.
-- The next reset comes from the client (seconds until reset) or, without that, from the last
-- known reset plus whole weeks.
--
-- Stored kills (ns.db.roster[key].kills):
--   { [raidKey] = { week (epoch of the week start), ends (epoch of the next reset),
--                   bosses = { [bossKey] = server time of the kill } } }
-- raidKey and bossKey are the normalized English (else German) names of Data.Instances.
local _, ns = ...

local W = {}
ns.RaidWeekLogic = W

W.WEEK = 7 * 86400
-- A daylight saving change moves the reset by an hour in epoch terms, readings jitter by seconds.
W.TOLERANCE = 2 * 3600
W.MAX_RAIDS = 60
W.MAX_BOSSES = 40
local MAX_TIME = 1e11

local function number(v, lo, hi)
  if type(v) ~= "number" or v ~= v or v < lo or v > hi then
    return nil
  end
  return v
end

local function key(v)
  if type(v) ~= "string" or v == "" or #v > 60 then
    return nil
  end
  return v
end

-- Reset arithmetic ----------------------------------------------------------------------

-- The next weekly reset (epoch) and where it came from ("api" or "anchor"). `secs` is the
-- client's seconds until the reset, `anchor` any known reset of the past or future. Nil
-- when neither is usable; the local clock is never consulted.
function W.Next(now, secs, anchor)
  if not number(now, 0, MAX_TIME) then
    return nil
  end
  if number(secs, 0, W.WEEK + W.TOLERANCE) and secs > 0 then
    return math.floor(now + secs + 0.5), "api"
  end
  if number(anchor, 1, MAX_TIME) then
    -- Lua's % is never negative here, so past and future anchors (clock jumps) both work.
    local left = (anchor - now) % W.WEEK
    if left == 0 then
      left = W.WEEK
    end
    return now + left, "anchor"
  end
end

function W.Start(nextReset)
  return nextReset - W.WEEK
end

-- True when the record belongs to the week that ends at `nextReset`. Without a known
-- reset only plausibility is checked: it must end in the future and not further away
-- than one week.
function W.Current(rec, nextReset, now)
  if type(rec) ~= "table" or not number(rec.ends, 0, MAX_TIME) then
    return false
  end
  if nextReset then
    return math.abs(rec.ends - nextReset) <= W.TOLERANCE
  end
  return type(now) == "number" and rec.ends > now and rec.ends <= now + W.WEEK + W.TOLERANCE
end

-- Storage ----------------------------------------------------------------------------------

local function cleanBosses(raw)
  local out, count = {}, 0
  for boss, at in pairs(type(raw) == "table" and raw or {}) do
    local k, t = key(boss), number(at, 0, MAX_TIME)
    if k and t and count < W.MAX_BOSSES then
      out[k] = t
      count = count + 1
    end
  end
  return out
end

-- A clean copy of stored kills; damaged records are dropped.
function W.CleanKills(raw)
  local out, count = {}, 0
  for raid, rec in pairs(type(raw) == "table" and raw or {}) do
    local k = key(raid)
    local ends = type(rec) == "table" and number(rec.ends, 1, MAX_TIME)
    if k and ends and count < W.MAX_RAIDS then
      out[k] = {
        week = number(rec.week, 0, MAX_TIME) or ends - W.WEEK,
        ends = ends,
        bosses = cleanBosses(rec.bosses),
      }
      count = count + 1
    end
  end
  return out
end

-- Removes the records of other weeks. Returns how many went.
function W.Prune(kills, nextReset, now)
  local removed = 0
  for raid, rec in pairs(kills) do
    if not W.Current(rec, nextReset, now) then
      kills[raid] = nil
      removed = removed + 1
    end
  end
  return removed
end

-- Records one kill in the week that ends at `nextReset`, a record of another week is
-- replaced. An existing kill keeps its first time. True when something was added.
function W.Mark(kills, raidKey, bossKey, at, nextReset)
  if not (key(raidKey) and key(bossKey) and number(at, 0, MAX_TIME) and number(nextReset, 1, MAX_TIME)) then
    return false
  end
  local rec = kills[raidKey]
  if not W.Current(rec, nextReset) or type(rec.bosses) ~= "table" then
    rec = { week = W.Start(nextReset), ends = nextReset, bosses = {} }
    kills[raidKey] = rec
  end
  if rec.bosses[bossKey] ~= nil then
    return false
  end
  rec.bosses[bossKey] = at
  return true
end

-- Folds the kills of `from` into `into` (two entries of one character): the same week
-- unites the bosses, the later week wins.
function W.MergeKills(into, from)
  for raid, rec in pairs(from) do
    local mine = into[raid]
    if not mine or rec.ends > mine.ends + W.TOLERANCE then
      into[raid] = rec
    elseif math.abs(rec.ends - mine.ends) <= W.TOLERANCE then
      for boss, at in pairs(rec.bosses) do
        if mine.bosses[boss] == nil then
          mine.bosses[boss] = at
        end
      end
    end
  end
end

-- Matching to Data.Instances ---------------------------------------------------------------

local function nameKey(n)
  local NK = ns.RaidLockLogic.NameKey
  n = type(n) == "table" and n or {}
  local k = NK(n.en)
  return k ~= "" and k or NK(n.de)
end

function W.IsRaid(inst)
  return type(inst) == "table" and inst.t == "raid"
end

function W.RaidKey(inst)
  local k = W.IsRaid(inst) and nameKey(inst.n)
  return k ~= "" and k or nil
end

function W.BossKey(boss, index)
  local k = nameKey(boss.n)
  return k ~= "" and k or ("boss" .. index)
end

-- The raid with that key.
function W.InstanceByKey(raidKey, instances)
  for _, inst in ipairs(instances or (ns.Data and ns.Data.Instances) or {}) do
    if W.RaidKey(inst) == raidKey then
      return inst
    end
  end
end

-- The Forever raid of the instance the client reports (game instance id, else name),
-- nil for dungeons and anything unknown. Second result: its raid key.
function W.FindRaid(instanceId, name, instances)
  local inst = ns.RaidLockLogic.Find({ instId = instanceId, nameKey = ns.RaidLockLogic.NameKey(name) }, instances)
  if W.IsRaid(inst) then
    return inst, W.RaidKey(inst)
  end
end

-- The boss key of a kill: the encounter id when the boss data has one, else the
-- normalized name (en or de).
function W.FindBoss(inst, encounterId, name)
  local wanted = ns.RaidLockLogic.NameKey(name)
  for i, boss in ipairs(inst.bo or {}) do
    local n = type(boss.n) == "table" and boss.n or {}
    if
      (type(boss.id) == "number" and boss.id == encounterId)
      or (wanted ~= "" and (wanted == ns.RaidLockLogic.NameKey(n.en) or wanted == ns.RaidLockLogic.NameKey(n.de)))
    then
      return W.BossKey(boss, i)
    end
  end
end

-- The boss keys a lockout reports as killed in `inst`.
function W.LockKills(lock, inst)
  local out = {}
  for i, s in ipairs((ns.RaidLockLogic.BossStates(lock, inst))) do
    if s.state == true then
      out[#out + 1] = W.BossKey(inst.bo[i], i)
    end
  end
  return out
end

-- Progress of one raid from a current record (or nil): killed count, number of bosses of
-- the instance and the killed ones in boss order as { key, name, at, opt }. Bosses the
-- record has but the instance lacks are ignored. `pick` turns { de, en } into text.
function W.Progress(rec, inst, pick)
  pick = pick or function(n)
    return type(n) == "table" and (n.en or n.de) or ""
  end
  local list = {}
  local bosses = type(rec) == "table" and type(rec.bosses) == "table" and rec.bosses or {}
  for i, boss in ipairs(inst.bo or {}) do
    local k = W.BossKey(boss, i)
    if bosses[k] then
      list[#list + 1] = { key = k, name = pick(boss.n), at = bosses[k], opt = boss.opt }
    end
  end
  return #list, #(inst.bo or {}), list
end
