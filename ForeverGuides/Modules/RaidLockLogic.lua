-- Raid lockouts without game calls: raw lockout rows from the client become the stored
-- format, are matched to the Forever instance and its boss list (Data.Instances), and
-- merged over difficulties. A lockout is "open" once its expiry has passed.
--
-- Stored lock (ns.db.roster[key].raids is a list of them):
--   { name, nameKey, instId (game's instance id), lockId, diff (difficulty id), diffName,
--     expires (server time), kills, total, bosses = { { name, killed } } }
local _, ns = ...

local L = {}
ns.RaidLockLogic = L

L.MAX_LOCKS = 40
L.MAX_BOSSES = 40

local function text(v, max)
  if type(v) ~= "string" or v == "" then
    return nil
  end
  return v:sub(1, max or 80)
end

local function number(v, lo, hi)
  if type(v) ~= "number" or v ~= v or v < lo or v > hi then
    return nil
  end
  return v
end

-- Lower case ASCII letters and digits only, so "Twilight-Lord Kelris" and "Twilight Lord
-- Kelris" match. Bytes above 127 (umlauts) fall out on both sides alike.
function L.NameKey(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:lower():gsub("[^a-z0-9]", ""))
end

local function cleanBosses(raw)
  local out = {}
  if type(raw) ~= "table" then
    return out
  end
  for _, b in ipairs(raw) do
    local name = type(b) == "table" and text(b.name, 80)
    if name and #out < L.MAX_BOSSES then
      out[#out + 1] = { name = name, killed = b.killed == true }
    end
  end
  return out
end

-- A clean copy of a stored lock, nil when it cannot be one (no name or expiry).
function L.CleanLock(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local name, expires = text(raw.name), number(raw.expires, 0, 1e11)
  if not (name and expires) then
    return nil
  end
  local diff, kills, total = number(raw.diff, 0, 1e4), number(raw.kills, 0, 1e3), number(raw.total, 0, 1e3)
  return {
    name = name,
    nameKey = L.NameKey(name),
    instId = number(raw.instId, 0, 1e9),
    lockId = number(raw.lockId, 0, 1e15),
    diff = diff and math.floor(diff) or nil,
    diffName = text(raw.diffName, 40),
    expires = expires,
    kills = kills and math.floor(kills) or nil,
    total = total and math.floor(total) or nil,
    bosses = cleanBosses(raw.bosses),
  }
end

function L.CleanLocks(raw)
  local out = {}
  if type(raw) ~= "table" then
    return out
  end
  for _, lock in ipairs(raw) do
    local clean = #out < L.MAX_LOCKS and L.CleanLock(lock)
    if clean then
      out[#out + 1] = clean
    end
  end
  return out
end

-- Raw rows { name, lockId, reset (seconds left), difficultyID, difficultyName, locked,
-- extended, numEncounters, encounterProgress, instanceID, bosses = { { name, killed } } }
-- to stored locks. A row that is neither locked nor extended, or has no time left, is
-- not a lockout (the client keeps such rows around).
function L.Build(raw, now)
  local out = {}
  if type(raw) ~= "table" or type(now) ~= "number" then
    return out
  end
  for _, r in ipairs(raw) do
    if
      type(r) == "table"
      and type(r.reset) == "number"
      and r.reset > 0
      and (r.locked ~= false or r.extended == true)
    then
      local lock = L.CleanLock({
        name = r.name,
        instId = r.instanceID,
        lockId = r.lockId,
        diff = r.difficultyID,
        diffName = r.difficultyName,
        expires = now + r.reset,
        kills = r.encounterProgress,
        total = r.numEncounters,
        bosses = r.bosses,
      })
      if lock and #out < L.MAX_LOCKS then
        out[#out + 1] = lock
      end
    end
  end
  return out
end

function L.Active(lock, now)
  return type(lock) == "table" and type(lock.expires) == "number" and lock.expires > now
end

-- The locks that still hold.
function L.Prune(locks, now)
  local out = {}
  for _, lock in ipairs(locks or {}) do
    if L.Active(lock, now) then
      out[#out + 1] = lock
    end
  end
  return out
end

-- Matching to Data.Instances ------------------------------------------------------

local cache = { src = nil, size = 0, byId = {}, byName = {} }

local function index(instances)
  if cache.src == instances and cache.size == #instances then
    return cache
  end
  cache = { src = instances, size = #instances, byId = {}, byName = {} }
  for _, inst in ipairs(instances) do
    if type(inst) == "table" then
      if type(inst.id) == "number" and not cache.byId[inst.id] then
        cache.byId[inst.id] = inst
      end
      for _, lang in ipairs({ "en", "de" }) do
        local key = L.NameKey(type(inst.n) == "table" and inst.n[lang])
        if key ~= "" and not cache.byName[key] then
          cache.byName[key] = inst
        end
      end
    end
  end
  return cache
end

-- The Forever instance of a lock: by the game's instance id, else by name (en or de).
function L.Find(lock, instances)
  instances = instances or (ns.Data and ns.Data.Instances) or {}
  if type(lock) ~= "table" then
    return nil
  end
  local idx = index(instances)
  return (lock.instId and idx.byId[lock.instId]) or (lock.nameKey and idx.byName[lock.nameKey]) or nil
end

-- One entry per boss of the instance: { n, opt, state }, state true (killed), false
-- (open) or nil (unknown: the lock does not list that boss). The second result lists
-- the names of the lock's bosses that are not in our list.
function L.BossStates(lock, inst)
  local byKey, used = {}, {}
  for i, b in ipairs(lock.bosses or {}) do
    local key = L.NameKey(b.name)
    if key ~= "" and not byKey[key] then
      byKey[key] = i
    end
  end
  local out = {}
  for _, boss in ipairs(inst.bo or {}) do
    local n = type(boss.n) == "table" and boss.n or {}
    local i = byKey[L.NameKey(n.en)] or byKey[L.NameKey(n.de)]
    local state
    if i then
      used[i] = true
      state = lock.bosses[i].killed
    end
    out[#out + 1] = { n = boss.n, opt = boss.opt, state = state }
  end
  local extra = {}
  for i, b in ipairs(lock.bosses or {}) do
    if not used[i] then
      extra[#extra + 1] = b.name
    end
  end
  return out, extra
end

-- All active locks of one instance (every difficulty) as one view:
--   { locked, expires (earliest), diffs = { { diff, diffName, expires } },
--     bosses = { { n, opt, state } }, extra = { name } }
-- A boss counts as killed when any difficulty has it killed. Without an active lock
-- every boss is open.
function L.Combine(locks, inst, now, instances)
  local view = { locked = false, diffs = {}, bosses = {}, extra = {} }
  local seenExtra = {}
  for _, lock in ipairs(locks or {}) do
    if L.Active(lock, now) and L.Find(lock, instances) == inst then
      view.locked = true
      view.expires = math.min(view.expires or lock.expires, lock.expires)
      view.diffs[#view.diffs + 1] = { diff = lock.diff, diffName = lock.diffName, expires = lock.expires }
      local states, extra = L.BossStates(lock, inst)
      for i, s in ipairs(states) do
        local b = view.bosses[i] or { n = s.n, opt = s.opt }
        if s.state == true or (s.state == false and b.state == nil) then
          b.state = s.state
        end
        view.bosses[i] = b
      end
      for _, name in ipairs(extra) do
        if not seenExtra[L.NameKey(name)] then
          seenExtra[L.NameKey(name)] = true
          view.extra[#view.extra + 1] = name
        end
      end
    end
  end
  if not view.locked then
    for i, boss in ipairs(inst.bo or {}) do
      view.bosses[i] = { n = boss.n, opt = boss.opt, state = false }
    end
  end
  return view
end
