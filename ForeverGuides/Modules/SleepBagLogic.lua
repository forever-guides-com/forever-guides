-- Pure part of the sleeping bag display (Modules/SleepBag.lua): the state machine and the texts. No game calls;
-- the clock (`now`, seconds like GetTime), the resting flag and the readings of the aura and the cast are passed in.
--
-- The run of the bag, as measured in the game (build 1.60.1.70862):
--   1. The player casts "Sack ausrollen" (UNROLL_SPELL) for a variable time.
--   2. After the cast the player walks to the unrolled bag.
--   3. Within 0 to 5 seconds the player lies down by itself (PLAYER_UPDATE_RESTING, IsResting true).
--   4. From lying down every REST_SECONDS the aura "Gut erholt" (RESTED_AURA, 7200 s) gains one stack, up to
--      MAX_STACKS. Every stack renews the duration. Lying down again after a new cast adds stacks the same way; at
--      MAX_STACKS lying only renews the duration.
-- Phases: off (setting off), ready, casting, walking, lying, aura. The walk shows "settling" (lying down) once the
-- player has stopped after moving. While lying the display counts the stacks: the number comes from the aura
-- (applications) and, when the game hides it, from the own count of one stack per REST_SECONDS (marked "~").
-- Every REST_SECONDS of lying something happens: a stack comes, or at the full number the duration is renewed. The
-- renewal is seen as the end time of the aura (expirationTime) jumping up; it restarts the countdown, so the
-- countdown runs for every number of stacks, also at 3/3.
-- As long as the aura lasts the display stays: standing up (also because of a mob) keeps it in the phase "aura"
-- (stack and time left) at any number of stacks. Only the cast starts a run: a resting flag without it (cities,
-- inns set the same flag) starts nothing. A standing aura is adopted as internal state only (the bar stays hidden while
-- standing). Standing up with no stack and no aura ends the run, the machine still watches
-- for a late first stack a little longer. While lying the run is exported (Record) and put back after a /reload
-- (Restore); a standing aura is adopted again (Adopt).
-- REST_SECONDS is the measured value; after every observed first stack the median of the last MEASURE_KEEP runs
-- replaces it.
local _, ns = ...

local L = {}
ns.SleepBagLogic = L

-- "Sack ausrollen" and "Gut erholt" of the Forever client.
L.UNROLL_SPELL = 429961
L.RESTED_AURA = 429959
-- The icon of the aura.
L.ICON = 132802
-- Seconds from lying down to the first stack and from one stack to the next (measured: 60.3).
L.REST_SECONDS = 60
-- The aura stacks up to this number.
L.MAX_STACKS = 3
-- Seconds the player may need after the cast to lie down before the run is dropped.
L.WALK_LIMIT = 30
-- Movement events this long after lying down are ignored (the game flickers around the moment of lying down).
L.MOVE_GRACE = 1.5
-- Seconds after the expected aura time the machine still waits for it after an early end.
L.LATE_GRACE = 10
-- A cast without a stop event is dropped after this many seconds.
L.CAST_LIMIT = 600
-- A channel that stops this close to its end counts as completed.
L.END_SLACK = 1.5
-- Observed runs kept for the estimate and the range one may have (seconds).
L.MEASURE_KEEP, L.MEASURE_MIN, L.MEASURE_MAX = 5, 10, 600
-- A saved run older than this many seconds after the expected aura time is dropped; a rested one lives as long as the aura.
L.RECORD_RESTED_MAX = 7200 + 600
-- The end time of the aura jumping up by more than this many seconds is a renewal.
L.RENEW_JUMP = 1
-- Seconds between two paints of the display.
L.TICK = 1

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function plain(v, isSecret)
  if type(isSecret) == "function" then
    local ok, hidden = pcall(isSecret, v)
    if not ok or hidden then
      return nil
    end
  end
  return v
end

-- Readings -------------------------------------------------------------------------------------------------------

-- What the aura says, as { present, duration, expiration, stacks }: plain numbers only (a secret or missing value
-- stays nil, and so does a duration or end time of 0, which means "no end"). `stacks` is the number of applications
-- (1 to MAX_STACKS) from `applications` or `count`.
function L.AuraInfo(aura, isSecret)
  if type(aura) ~= "table" then
    return { present = false }
  end
  local info = { present = true }
  pcall(function()
    local duration, expiration = plain(aura.duration, isSecret), plain(aura.expirationTime, isSecret)
    if finite(duration) and duration > 0 and finite(expiration) and expiration > 0 then
      info.duration, info.expiration = duration, expiration
    end
  end)
  pcall(function()
    local stacks = plain(aura.applications, isSecret)
    if stacks == nil then
      stacks = plain(aura.count, isSecret)
    end
    if finite(stacks) then
      info.stacks = math.min(L.MAX_STACKS, math.max(1, math.floor(stacks)))
    end
  end)
  return info
end

-- Start and end (seconds, GetTime base) of a cast or channel from the list UnitCastingInfo or UnitChannelInfo
-- returned: name, text, texture, startMs, endMs, ... and the spell id at `spellIndex` (9 for a cast, 8 for a
-- channel). nil when it is not the bag, the times are secret, or they do not fit the clock `now`.
function L.CastTimes(values, spellIndex, now, isSecret)
  if type(values) ~= "table" then
    return nil
  end
  local id = plain(values[spellIndex], isSecret)
  if id ~= nil and id ~= L.UNROLL_SPELL then
    return nil
  end
  local startMs, endMs = plain(values[4], isSecret), plain(values[5], isSecret)
  if not (finite(startMs) and finite(endMs) and finite(now)) then
    return nil
  end
  local start, stop = startMs / 1000, endMs / 1000
  if stop <= start or stop - start > 3600 or start < now - 3600 or start > now + 5 then
    return nil
  end
  return start, stop
end

-- Time format -----------------------------------------------------------------------------------------------------

-- Seconds as m:ss, from an hour on h:mm:ss; `up` rounds a time left up, else down. nil for a non-number.
function L.Clock(seconds, up)
  if not finite(seconds) then
    return nil
  end
  seconds = math.max(0, math[up and "ceil" or "floor"](seconds))
  local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%d:%02d", m, s)
end

-- Measurements -----------------------------------------------------------------------------------------------------

-- The saved list as a clean list: plain numbers in range, the last MEASURE_KEEP.
function L.CleanMeasures(list)
  local out = {}
  if type(list) == "table" then
    for _, v in ipairs(list) do
      if finite(v) and v >= L.MEASURE_MIN and v <= L.MEASURE_MAX then
        out[#out + 1] = v
      end
    end
  end
  while #out > L.MEASURE_KEEP do
    table.remove(out, 1)
  end
  return out
end

-- Seconds from lying down to the aura: the median of the kept runs, REST_SECONDS without any.
function L.RestSeconds(st)
  local n = #st.measures
  if n == 0 then
    return L.REST_SECONDS
  end
  local sorted = {}
  for i, v in ipairs(st.measures) do
    sorted[i] = v
  end
  table.sort(sorted)
  if n % 2 == 1 then
    return sorted[(n + 1) / 2]
  end
  return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

local function remember(st, seconds)
  if finite(seconds) and seconds >= L.MEASURE_MIN and seconds <= L.MEASURE_MAX then
    st.measures[#st.measures + 1] = seconds
    while #st.measures > L.MEASURE_KEEP do
      table.remove(st.measures, 1)
    end
    return true
  end
  return false
end

-- State machine ----------------------------------------------------------------------------------------------------

-- A new machine; `measures` is the saved list of runs. It starts "off" until Enable(st, true).
function L.new(measures)
  return { phase = "off", measures = L.CleanMeasures(measures) }
end

-- True during a run (casting, walking, lying, aura).
function L.Active(st)
  local p = st.phase
  return p == "casting" or p == "walking" or p == "lying" or p == "aura"
end

-- True while the machine needs its events and timer: a run, or the wait for a late stack after an early end.
function L.Running(st)
  return L.Active(st) or st.watch ~= nil
end

local function reset(st)
  st.kind, st.castStart, st.castStop, st.walkStart, st.restAt = nil, nil, nil, nil, nil
  st.moving, st.arrived = nil, nil
  st.auraBefore, st.stacksBefore, st.measurable, st.watch = nil, nil, nil, nil
  st.stacks, st.counted, st.stackAt, st.exp = nil, nil, nil, nil
end

function L.Enable(st, on)
  if on and st.phase == "off" then
    st.phase = "ready"
  elseif not on then
    reset(st)
    st.phase = "off"
  end
end

local function before(aura)
  return aura and aura.present and (aura.expiration or true) or nil
end

-- What the aura held when the run began: the end time (or true), the stacks (0 without the aura, nil when the
-- number is hidden) and whether the run can be measured (no aura before).
local function noteBefore(st, aura)
  st.auraBefore = before(aura)
  if aura and aura.present then
    st.stacksBefore = aura.stacks
  else
    st.stacksBefore = 0
  end
  st.measurable = st.auraBefore == nil
end

-- The player lies down: the stacks start at the number the aura already had (the own count when it is hidden). The
-- countdown (stackAt) starts now; `aura` (optional) gives the end time to compare later readings with.
local function lie(st, now, aura)
  local base = st.stacksBefore
  st.phase, st.restAt, st.stackAt = "lying", now, now
  st.stacks, st.counted = base or 0, base == nil
  local exp = aura and aura.present and aura.expiration or nil
  if exp == nil and type(st.auraBefore) == "number" then
    exp = st.auraBefore
  end
  st.exp = exp
end

-- A rest period has passed at the full number and nothing in the aura shows the renewal (its end time is hidden):
-- the countdown starts over.
local function rollRenew(st, now)
  local need = L.RestSeconds(st)
  while now - st.stackAt >= need do
    st.stackAt = st.stackAt + need
  end
end

-- A run is over: back to ready. Standing up with one or two stacks keeps the display in the phase "aura". After an
-- early end without any stack the first one is still awaited for a while.
local function finish(st, now, reason)
  local lying = st.phase == "lying"
  local stacks = lying and st.stacks or 0
  if lying and reason ~= "idle" then
    reason = stacks == 0 and "early" or "stood"
  end
  local info = { reason = reason, rested = stacks > 0, stacks = stacks, counted = lying and st.counted or nil }
  if st.restAt then
    info.elapsed = math.max(0, now - st.restAt)
    info.need = L.RestSeconds(st)
  end
  local keep, watch
  if lying and stacks > 0 then
    keep = { stacks = stacks, counted = st.counted, exp = st.exp }
  elseif st.auraBefore ~= nil then
    keep = {
      stacks = st.stacksBefore or 1,
      counted = st.stacksBefore == nil,
      exp = type(st.auraBefore) == "number" and st.auraBefore or nil,
    }
  elseif lying and stacks == 0 then
    watch = {
      restAt = st.restAt,
      untilTime = st.restAt + L.RestSeconds(st) + L.LATE_GRACE,
      measurable = st.measurable,
    }
  end
  reset(st)
  st.phase, st.watch = "ready", watch
  if keep then
    st.phase, st.stacks, st.counted, st.exp = "aura", keep.stacks, keep.counted, keep.exp
  end
  return "ended", info
end

local function walk(st, now, resting, aura)
  if resting then
    lie(st, now, aura)
  else
    st.phase, st.walkStart = "walking", now
  end
end

-- The cast ("cast") or channel ("channel") of the bag began. `start` and `stop` are the times the game gave
-- (nil when unreadable); `aura` is the reading of the aura now, so the stacks it already has are known.
function L.Start(st, now, kind, start, stop, aura)
  if st.phase == "off" then
    return nil
  end
  reset(st)
  st.phase, st.kind = "casting", kind
  st.castStart, st.castStop = start or now, start and stop or nil
  noteBefore(st, aura)
  return "started"
end

-- UNIT_SPELLCAST_SUCCEEDED. After a cast it ends the cast. Without a start event (the add-on loaded during the
-- cast) the run begins here with the walk to the bag, nothing else is lost: the timer counts from lying down.
function L.Succeeded(st, now, resting, aura)
  if st.phase == "ready" or st.phase == "aura" then
    reset(st)
    noteBefore(st, aura)
    walk(st, now, resting, aura)
    return "started"
  elseif st.phase == "casting" and st.kind == "cast" then
    walk(st, now, resting, aura)
    return "completed"
  end
end

-- UNIT_SPELLCAST_STOP: before a success it is an abort of a cast, after it (the normal order) nothing.
function L.Stopped(st, now)
  if st.phase == "casting" and st.kind == "cast" then
    return finish(st, now, "aborted")
  end
end

-- UNIT_SPELLCAST_CHANNEL_STOP: the channel ended in time, or the player broke it off.
function L.ChannelStopped(st, now, resting)
  if st.phase ~= "casting" or st.kind ~= "channel" then
    return nil
  end
  if st.castStop and now < st.castStop - L.END_SLACK then
    return finish(st, now, "aborted")
  end
  walk(st, now, resting)
  return "completed"
end

-- UNIT_SPELLCAST_INTERRUPTED and FAILED of the cast.
function L.Aborted(st, now)
  if st.phase == "casting" then
    return finish(st, now, "aborted")
  end
end

-- PLAYER_UPDATE_RESTING. True after the walk: the player lies, the timer starts. A resting flag without the cast of
-- the bag starts nothing: cities and inns set the same flag, and only the bag gives the aura its stacks. False while
-- lying: standing up. Lying down again in the bag takes a new cast and walk.
function L.Resting(st, now, resting, aura)
  if resting then
    if st.phase == "walking" then
      lie(st, now, aura)
      return "lying"
    end
  elseif st.phase == "lying" then
    return finish(st, now, "early")
  end
end

-- PLAYER_REGEN_DISABLED: a fight starts. Lying ends (the countdown stops, the display stays as "aura"); lying down
-- again after the fight starts it again.
function L.Combat(st, now)
  if st.phase == "lying" then
    return finish(st, now, "combat")
  end
end

-- A standing aura found without a run (login, /reload, the setting turned on): kept as the phase "aura", not drawn.
function L.Adopt(st, _now, aura)
  if st.phase ~= "ready" or st.watch ~= nil or not (aura and aura.present) then
    return nil
  end
  reset(st)
  st.phase, st.stacks, st.counted, st.exp = "aura", aura.stacks or 1, aura.stacks == nil, aura.expiration
  return "adopted"
end

-- PLAYER_STARTED_MOVING: moving ends the lying (casting and walking move on purpose). During the walk it only
-- notes that the player is on the way.
function L.Moved(st, now)
  if st.phase == "walking" then
    st.moving, st.arrived = true, nil
    return nil
  end
  if st.phase == "lying" and now - st.restAt >= L.MOVE_GRACE then
    return finish(st, now, "early")
  end
end

-- PLAYER_STOPPED_MOVING: the player who walked to the bag has arrived and is about to lie down.
function L.Arrived(st)
  if st.phase == "walking" and st.moving then
    st.arrived = true
    return "arrived"
  end
end

-- Stacks ---------------------------------------------------------------------------------------------------------

-- The stack count rises to `stacks` now. The time from lying down to the first stack counts for the estimate when
-- the run had no aura before.
local function stack(st, now, stacks)
  local first = st.stacks == 0
  st.stacks, st.stackAt = stacks, now
  local measured = first and st.measurable and st.restAt and remember(st, now - st.restAt) or false
  st.measurable = false
  return "stacked", measured
end

-- A reading of the aura folded into the run. The number the game gives wins over the own count; a hidden number
-- switches to the own count (the first stack of a run without an aura before is still seen as the aura appears).
-- In the phase "aura" a missing aura ends the display.
local function observe(st, now, aura)
  if not (aura and aura.present) then
    if st.phase == "aura" then
      reset(st)
      st.phase = "ready"
      return "faded"
    elseif st.stacks > 0 and not st.counted then
      st.stacks, st.stackAt, st.measurable, st.exp = 0, now, false, nil
      st.auraBefore = nil
      return "reset"
    end
    return nil
  end
  local exp = aura.expiration
  local jumped = finite(exp) and finite(st.exp) and exp > st.exp + L.RENEW_JUMP
  if finite(exp) then
    st.exp = exp
  end
  local seen, event, measured = aura.stacks, nil, nil
  if seen == nil then
    st.counted = true
    if st.stacks == 0 and st.auraBefore == nil then
      event, measured = stack(st, now, 1)
    end
  else
    st.counted = false
    if seen > st.stacks then
      event, measured = stack(st, now, seen)
    elseif seen < st.stacks then
      st.stacks = seen
    end
  end
  if not event and jumped and st.phase == "lying" then
    -- With a hidden number the jump is the stack itself, unless the own count just added it.
    if st.counted and st.stacks < L.MAX_STACKS and now - st.stackAt >= L.RestSeconds(st) / 2 then
      event, measured = stack(st, now, st.stacks + 1)
    else
      st.stackAt = now
      event = "renewed"
    end
  end
  return event, measured
end

-- Own count: one stack per REST_SECONDS of lying while the number is hidden. True when a stack was added.
local function advance(st, now)
  if st.phase ~= "lying" then
    return false
  end
  if st.stacks >= L.MAX_STACKS then
    if st.exp == nil then
      rollRenew(st, now)
    end
    return false
  end
  if not st.counted then
    return false
  end
  local need, added = L.RestSeconds(st), false
  while st.stacks < L.MAX_STACKS and now - st.stackAt >= need do
    st.stacks, st.stackAt = st.stacks + 1, st.stackAt + need
    added = true
  end
  return added
end

-- The first stack after an early end: the display comes back as "aura" (stack and time left).
local function watched(st, now, aura)
  if not (aura and aura.present) then
    return nil
  end
  local w = st.watch
  local measured = w.measurable and remember(st, now - w.restAt) or false
  reset(st)
  st.phase, st.stacks, st.counted, st.exp = "aura", aura.stacks or 1, aura.stacks == nil, aura.expiration
  return "stacked", measured
end

-- UNIT_AURA of the player with the reading of the aura. Returns "stacked" and whether the time counts as a
-- measurement, "reset" (the aura ended while lying) or "faded" (the aura ended after standing up).
function L.Aura(st, now, aura)
  if st.phase == "ready" and st.watch then
    return watched(st, now, aura)
  elseif st.phase == "lying" or st.phase == "aura" then
    return observe(st, now, aura)
  end
end

-- A timer step (once a second while the machine runs): runs that lost their end events end here, the own count
-- advances, and the reading of the aura (`aura`, nil when not read) catches up with missed events.
function L.Tick(st, now, aura)
  local phase = st.phase
  if phase == "walking" and now - st.walkStart >= L.WALK_LIMIT then
    return finish(st, now, "noLie")
  elseif phase == "casting" and now - st.castStart > L.CAST_LIMIT then
    return finish(st, now, "aborted")
  elseif phase == "lying" or phase == "aura" then
    local event, measured
    if aura ~= nil then
      event, measured = observe(st, now, aura)
    end
    if advance(st, now) then
      event = event or "stacked"
    end
    return event, measured
  elseif st.watch then
    if aura ~= nil and aura.present then
      return watched(st, now, aura)
    elseif now > st.watch.untilTime then
      st.watch = nil
    end
  end
end

-- Surviving a /reload ----------------------------------------------------------------------------------------------

-- The run as a plain table for the saved variables (nil unless the player lies): `at` and `stackAt` (moment of
-- lying down and of the last stack) are on the wall clock (`serverNow`, GetServerTime), because GetTime starts over
-- with the reload.
function L.Record(st, now, serverNow)
  if st.phase ~= "lying" or not st.restAt or not (finite(now) and finite(serverNow)) then
    return nil
  end
  return {
    v = 2,
    at = serverNow - (now - st.restAt),
    stackAt = serverNow - (now - st.stackAt),
    stacks = st.stacks,
    counted = st.counted == true,
    hadAura = st.auraBefore ~= nil,
  }
end

-- Puts a saved run back into a machine that is ready: only while the player still lies (`resting`) and the age fits.
-- The reading of the aura now brings the stacks up to date (the aura may have grown while the game reloaded).
-- Returns true when restored.
function L.Restore(st, now, record, serverNow, resting, aura)
  if st.phase ~= "ready" or type(record) ~= "table" or record.v ~= 2 or not resting then
    return false
  end
  local stacks = record.stacks
  if not (finite(record.at) and finite(serverNow) and finite(now) and finite(stacks)) then
    return false
  end
  stacks = math.min(L.MAX_STACKS, math.max(0, math.floor(stacks)))
  local stackAt = finite(record.stackAt) and record.stackAt or record.at
  local age = serverNow - record.at
  local present = aura and aura.present
  if age < 0 or age > L.RECORD_RESTED_MAX then
    return false
  end
  if stacks > 0 and not present then
    return false
  elseif stacks == 0 and age > L.RestSeconds(st) + L.LATE_GRACE and not present then
    return false
  end
  reset(st)
  st.phase, st.restAt, st.stackAt = "lying", now - age, now - math.max(0, serverNow - stackAt)
  st.stacks, st.counted = stacks, record.counted == true
  st.auraBefore = record.hadAura and true or nil
  st.measurable = false
  if stacks >= L.MAX_STACKS then
    rollRenew(st, now)
  end
  observe(st, now, aura)
  advance(st, now)
  return true
end

-- What the display shows -----------------------------------------------------------------------------------------

local function auraLeft(aura, now)
  local left = aura and aura.present and aura.expiration and aura.duration and aura.expiration - now
  if finite(left) and left > 0 then
    return left, aura.duration
  end
end

-- "2/3", or "~2/3" for a count of the add-on (the game hides the number).
function L.StackLabel(stacks, counted)
  return (counted and "~" or "") .. stacks .. "/" .. L.MAX_STACKS
end

-- The picture of the run at `now` (nil while nothing runs): kind, the stacks and where they come from (counted),
-- the seconds to the next stack (nextIn), the time the aura has left (left, nil when unknown) and progress 0..1 for
-- the bar. Kinds: casting, walking, settling, lying (countdown to the next stack; at the full number `renew` is
-- set and it counts to the renewal of the duration), lyingLate (the stack or the renewal is due), rested (standing
-- with the aura on). `aura` is the current reading.
function L.Snapshot(st, now, aura)
  local phase = st.phase
  if phase == "casting" then
    local snap = { kind = "casting", progress = 0 }
    if st.castStop and st.castStop > st.castStart then
      snap.left = math.max(0, st.castStop - now)
      snap.progress = math.min(1, (now - st.castStart) / (st.castStop - st.castStart))
    end
    return snap
  elseif phase == "walking" then
    return { kind = st.arrived and "settling" or "walking", progress = 0 }
  elseif phase ~= "lying" and phase ~= "aura" then
    return nil
  end
  local left, duration = auraLeft(aura, now)
  local progress = left and duration and math.min(1, left / duration) or 1
  if phase == "aura" then
    return {
      kind = "rested",
      stacks = st.stacks,
      counted = st.counted,
      elapsed = st.restAt and math.max(0, now - st.restAt) or nil,
      left = left,
      progress = progress,
    }
  end
  local need = L.RestSeconds(st)
  local snap = {
    kind = "lying",
    stacks = st.stacks,
    counted = st.counted,
    elapsed = math.max(0, now - st.restAt),
    left = st.stacks > 0 and left or nil,
    renew = st.stacks >= L.MAX_STACKS or nil,
  }
  local sinceStack = math.max(0, now - st.stackAt)
  if sinceStack < need then
    snap.nextIn, snap.progress = need - sinceStack, sinceStack / need
  else
    snap.kind, snap.progress = "lyingLate", 1
  end
  return snap
end

-- The one line of the display, which is also its text alternative. `t` maps a key to a format (the locale):
-- sleepbag.casting, .castingLeft, .walking, .settling, .lying (no stack yet), .lyingStack, .lyingStackLeft,
-- .lyingRenew, .lyingRenewLeft, .lyingLate, .stackLate, .renewLate, .rested, .restedPlain.
function L.Text(snap, t)
  if not snap then
    return ""
  end
  local kind = snap.kind
  if kind == "casting" then
    if snap.left then
      return string.format(t("sleepbag.castingLeft"), L.Clock(snap.left, true))
    end
    return t("sleepbag.casting")
  elseif kind == "walking" then
    return t("sleepbag.walking")
  elseif kind == "settling" then
    return t("sleepbag.settling")
  end
  local label = L.StackLabel(snap.stacks, snap.counted)
  if kind == "lying" then
    if snap.stacks == 0 then
      return string.format(t("sleepbag.lying"), L.Clock(snap.elapsed), L.Clock(snap.nextIn, true))
    end
    local key = snap.renew and "sleepbag.lyingRenew" or "sleepbag.lyingStack"
    if snap.left then
      return string.format(t(key .. "Left"), label, L.Clock(snap.nextIn, true), L.Clock(snap.left, true))
    end
    return string.format(t(key), label, L.Clock(snap.nextIn, true))
  elseif kind == "lyingLate" then
    if snap.stacks == 0 then
      return string.format(t("sleepbag.lyingLate"), L.Clock(snap.elapsed))
    end
    return string.format(t(snap.renew and "sleepbag.renewLate" or "sleepbag.stackLate"), label)
  end
  if snap.left then
    return string.format(t("sleepbag.rested"), label, L.Clock(snap.left, true))
  end
  return string.format(t("sleepbag.restedPlain"), label)
end

-- The lines under the title of the tooltip: the stacks (and where the number comes from), the countdown, the
-- time left. `t` maps a key to a format: sleepbag.tip.stacks, .counted, .next, .nextRenew, .left, .full.
function L.TipLines(snap, t)
  local lines = {}
  if not snap or snap.stacks == nil then
    return lines
  end
  lines[#lines + 1] = string.format(t("sleepbag.tip.stacks"), L.StackLabel(snap.stacks, snap.counted))
  if snap.counted then
    lines[#lines + 1] = t("sleepbag.tip.counted")
  end
  if snap.nextIn then
    lines[#lines + 1] = string.format(t(snap.renew and "sleepbag.tip.nextRenew" or "sleepbag.tip.next"), L.Clock(snap.nextIn, true))
  end
  if snap.left then
    lines[#lines + 1] = string.format(t("sleepbag.tip.left"), L.Clock(snap.left, true))
  end
  if snap.stacks >= L.MAX_STACKS then
    lines[#lines + 1] = t("sleepbag.tip.full")
  end
  return lines
end

return L
