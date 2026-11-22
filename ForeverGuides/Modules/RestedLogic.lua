-- Rested XP of the characters on the account: the snapshot stored at logout and the estimate for a
-- character that is not logged in. Pure functions, no game calls.
--
-- Classic rules (the game accrues rested XP only while logged out in the estimate):
--   resting (inn or capital at logout): 5 % of the level's XP per 8 hours
--   anywhere else:                      a quarter of that (5 % per 32 hours)
--   maximum:                            150 % of one level's XP
-- A snapshot is { xp, xpMax, exhaustion, resting, at, maxLevel, alerted }, `at` is the server time of
-- the reading, `alerted` the `at` of the snapshot the "rested is full" notice was already shown for.
local _, ns = ...

local RL = {}
ns.RestedLogic = RL

RL.RATE = 0.05
RL.HOURS_PER_STEP = 8
RL.OUTSIDE_FACTOR = 0.25
RL.CAP_LEVELS = 1.5

local HOUR = 3600

local function number(v, lo, hi)
  if type(v) ~= "number" or v ~= v or v < lo or v > hi then
    return nil
  end
  return v
end

-- A clean copy of a stored snapshot, nil without a usable level size or reading time. A missing
-- exhaustion is 0 (the game answers nil for "no rested XP").
function RL.Clean(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local xpMax, at = number(raw.xpMax, 1, 1e9), number(raw.at, 1, 1e11)
  if not (xpMax and at) then
    return nil
  end
  return {
    xp = number(raw.xp, 0, xpMax) or 0,
    xpMax = xpMax,
    exhaustion = number(raw.exhaustion, 0, 1e10) or 0,
    resting = raw.resting == true,
    at = at,
    maxLevel = raw.maxLevel == true,
    alerted = number(raw.alerted, 0, 1e11),
  }
end

function RL.Cap(xpMax)
  return xpMax * RL.CAP_LEVELS
end

-- Rested XP gained per hour offline.
function RL.PerHour(snap)
  local rate = snap.xpMax * RL.RATE / RL.HOURS_PER_STEP
  return snap.resting and rate or rate * RL.OUTSIDE_FACTOR
end

local function result(snap, rested, elapsed, live)
  local cap = RL.Cap(snap.xpMax)
  local full = rested >= cap
  local perHour = RL.PerHour(snap)
  return {
    xp = snap.xp,
    xpMax = snap.xpMax,
    xpPct = snap.xp / snap.xpMax * 100,
    rested = rested,
    restedPct = rested / snap.xpMax * 100,
    cap = cap,
    full = full,
    hoursToFull = (not full and perHour > 0) and (cap - rested) / perHour or nil,
    elapsed = elapsed,
    live = live or nil,
  }
end

-- The estimate of a snapshot at `now`. A clock that went backwards counts as no time passed.
-- nil for a character at the maximum level or without a usable snapshot. live: the snapshot was read
-- from the game just now, nothing is added.
function RL.Estimate(raw, now, live)
  local snap = RL.Clean(raw)
  if not snap or snap.maxLevel then
    return nil
  end
  local elapsed = live and 0 or math.max(0, (number(now, 0, 1e11) or snap.at) - snap.at)
  local rested = math.min(RL.Cap(snap.xpMax), snap.exhaustion + elapsed / HOUR * RL.PerHour(snap))
  return result(snap, rested, elapsed, live)
end

-- True once for each snapshot: the character reached the cap after the logout and the notice was not
-- shown for this snapshot yet. A new logout writes a new `at`, so the next cap event can notify again.
function RL.NeedsAlert(raw, now)
  local snap = RL.Clean(raw)
  local est = snap and RL.Estimate(snap, now)
  return est ~= nil and est.full and snap.exhaustion < est.cap and snap.alerted ~= snap.at
end

-- Where the rested XP of an estimate ends once it exceeds the rest of the current level: the overflow
-- carries into the following levels, each with its own size (need[level], maxLevel from the XP table).
-- Returns { level, xp, xpMax, pct } or nil while the rested XP fits into the current level. At the highest
-- reachable level xpMax and pct are nil (that level has no size, nothing is carried further).
function RL.Reach(est, level, need, maxLevel)
  if type(est) ~= "table" or type(level) ~= "number" or type(need) ~= "table" then
    return nil
  end
  local over = est.rested - (est.xpMax - est.xp)
  if over <= 0 then
    return nil
  end
  local top = maxLevel or level
  while level < top and need[level + 1] do
    level = level + 1
    local size = need[level]
    if over < size then
      return { level = level, xp = over, xpMax = size, pct = over / size * 100 }
    end
    over = over - size
  end
  return { level = level }
end

-- A sort key: the fraction of the cap that is filled, so full characters come first.
function RL.Fill(raw, now)
  local est = RL.Estimate(raw, now)
  return est and est.rested / est.cap or -1
end
