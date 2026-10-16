-- Pure side of the save state (Modules/SaveState.lua): which changes are not on disk yet, how heavy they
-- are, and when the reminder may show. No game calls; every time is a number the caller passes in
-- (server time in seconds), so each rule is testable.
local _, ns = ...

local SL = {}
ns.SaveStateLogic = SL

-- Weight of one finished price scan: alone it passes HINT_WEIGHT.
SL.SCAN_WEIGHT = 50
-- Weight that shows the reminder right after a scan.
SL.HINT_WEIGHT = 20
-- At a natural pause the reminder needs this much weight and this many minutes since the first change.
SL.PAUSE_WEIGHT = 5
SL.PAUSE_MINUTES = 30
-- Seconds between two reminders and the length of "Later".
SL.THROTTLE_SECONDS = 1800
SL.SNOOZE_SECONDS = 1800
SL.MAX_WEIGHT = 1000
-- Seconds a reload attempt keeps listening for a late refusal of the client.
SL.ATTEMPT_SECONDS = 1

-- Weight of one change by reason. Anything not listed counts 1.
SL.WEIGHTS = {
  list = 2,
  roster = 3,
  notes = 5,
  drawings = 5,
  waypoints = 2,
  settings = 1,
  inventory = 1,
}

-- Scan phases of the price database that mean "a scan is running".
local ACTIVE_PHASES = { waiting = true, reading = true, aggregating = true }

function SL.ScanActive(phase)
  return ACTIVE_PHASES[phase] == true
end

local function number(v, fallback)
  v = tonumber(v)
  if v == nil or v ~= v or v == math.huge or v == -math.huge then
    return fallback
  end
  return v
end

-- The weight a passive price update gets from the change of the item count: 1 to 20.
function SL.PriceWeight(delta)
  local n = math.abs(number(delta, 0))
  return math.max(1, math.min(20, 1 + math.floor(n / 25)))
end

function SL.New()
  return { since = nil, weight = 0, reasons = {}, lastHint = nil, snoozeUntil = nil }
end

-- Records one unsaved change. since keeps the time of the first one. Returns true when a change was
-- recorded (an empty reason is ignored).
function SL.Mark(st, reason, weight, now)
  if type(reason) ~= "string" or reason == "" then
    return false
  end
  weight = math.max(0, number(weight, SL.WEIGHTS[reason] or 1))
  if st.since == nil then
    st.since = number(now, 0)
  end
  st.weight = math.min(SL.MAX_WEIGHT, st.weight + weight)
  st.reasons[reason] = math.min(SL.MAX_WEIGHT, (st.reasons[reason] or 0) + weight)
  return true
end

-- Everything is on disk: the dirty record starts over. The reminder timers stay.
function SL.Clear(st)
  st.since, st.weight, st.reasons = nil, 0, {}
end

function SL.IsDirty(st)
  return st.since ~= nil
end

function SL.Minutes(st, now)
  if st.since == nil then
    return 0
  end
  return math.max(0, math.floor((number(now, st.since) - st.since) / 60))
end

-- The reasons, heaviest first (ties by name).
function SL.ReasonList(st)
  local out = {}
  for reason in pairs(st.reasons) do
    out[#out + 1] = reason
  end
  table.sort(out, function(a, b)
    if st.reasons[a] ~= st.reasons[b] then
      return st.reasons[a] > st.reasons[b]
    end
    return a < b
  end)
  return out
end

-- "Later": no reminder before now + seconds.
function SL.Snooze(st, now, seconds)
  st.snoozeUntil = number(now, 0) + (seconds or SL.SNOOZE_SECONDS)
end

-- A reminder was shown.
function SL.Shown(st, now)
  st.lastHint = number(now, 0)
end

-- May the reminder show? ctx: enabled (setting), combat, restricted (an addon restriction of the client
-- is active), scanning, trigger ("scan" for a finished scan,
-- "pause" for a natural pause). Returns true, trigger or false, why (the first rule that says no).
function SL.Decide(st, ctx, now)
  now = number(now, 0)
  if not ctx.enabled then
    return false, "off"
  end
  if not SL.IsDirty(st) then
    return false, "clean"
  end
  if ctx.combat then
    return false, "combat"
  end
  if ctx.restricted then
    return false, "restricted"
  end
  if ctx.scanning then
    return false, "scan"
  end
  if st.snoozeUntil and now < st.snoozeUntil then
    return false, "snoozed"
  end
  if st.lastHint and now - st.lastHint < SL.THROTTLE_SECONDS then
    return false, "throttled"
  end
  if ctx.trigger == "scan" then
    if st.weight < SL.HINT_WEIGHT then
      return false, "light"
    end
  elseif ctx.trigger == "pause" then
    if st.weight < SL.PAUSE_WEIGHT or SL.Minutes(st, now) < SL.PAUSE_MINUTES then
      return false, "early"
    end
  else
    return false, "trigger"
  end
  return true, ctx.trigger
end

-- Why the reload should ask first, nil when it can go ahead. ctx: scanning, merchant, group, instance.
function SL.ConfirmReason(ctx)
  if ctx.scanning then
    return "scan"
  end
  if ctx.merchant then
    return "merchant"
  end
  if ctx.instance then
    return "instance"
  end
  if ctx.group then
    return "group"
  end
  return nil
end

-- Does a blocked-action event belong to a reload? True for the name of the reload ("C_UI.Reload()",
-- "ReloadUI") and for the placeholder the client sends when it withholds the name ("UNKNOWN()"). The
-- caller only asks while its own reload attempt is running or has just run.
function SL.IsReloadCall(func)
  if type(func) ~= "string" then
    return false
  end
  return func:find("Reload", 1, true) ~= nil or func:find("^UNKNOWN") ~= nil
end

-- Minutes as a key of the locale and a count: "none" under one minute, "one", "other".
function SL.MinutesForm(minutes)
  minutes = math.max(0, math.floor(number(minutes, 0)))
  if minutes < 1 then
    return "none", 0
  end
  return minutes == 1 and "one" or "other", minutes
end
