-- Remaining flight time without WoW API: the state of one flight (idle or flying), the remaining
-- time and progress from the expected duration, the end of the flight and the measurement of the
-- whole route for FlightLogic. The game side (hook, window) lives in Modules/FlightTimer.lua.
-- A state is a plain table made by FT.new(); every function takes the clock (GetTime) as argument.
local _, ns = ...
local FL, L, U = ns.FlightLogic, ns.L, ns.U

local FT = {}
ns.FlightTimerLogic = FT

ns.AddLocale("enUS", {
  ["flighttimer.overrun"] = "Longer than expected",
  ["flighttimer.unknown"] = "Duration unknown",
})
ns.AddLocale("deDE", {
  ["flighttimer.overrun"] = "Länger als erwartet",
  ["flighttimer.unknown"] = "Dauer unbekannt",
})

-- Seconds the game gets to report UnitOnTaxi after the flight was taken, else the take failed.
FT.GRACE = 10
-- A flight that ends before this share of the expected time was cut short (early landing): no measurement.
FT.MIN_SHARE = 0.4

function FT.new()
  return { phase = "idle" }
end

function FT.flying(s)
  return s.phase == "flying"
end

-- Expected seconds and whether they are approximate, from FlightLogic.estimateRoute. A route with a
-- hop of unknown duration has no expected time (a partial sum would be wrong).
function FT.expected(total)
  if type(total) ~= "table" or type(total.parts) ~= "table" or #total.parts == 0 or total.unknown ~= 0 then
    return nil
  end
  local seconds = tonumber(total.seconds)
  if not seconds or seconds ~= seconds or seconds <= 0 or seconds == math.huge then
    return nil
  end
  return seconds, total.approx == true
end

-- info: { name, key (route key for the measurement), expected (seconds), approx, preview }.
-- A preview loops over its expected time and is never measured.
function FT.start(s, now, info)
  info = info or {}
  local expected = tonumber(info.expected)
  s.phase = "flying"
  s.startedAt = now
  s.name = info.name
  s.key = info.key
  s.expected = expected and expected > 0 and expected < math.huge and expected or nil
  s.approx = info.approx == true
  s.preview = info.preview == true and s.expected ~= nil
  -- A real flight counts once the game confirms it (UnitOnTaxi).
  s.confirmed = s.preview
end

function FT.cancel(s)
  s.phase = "idle"
end

-- State for painting, or nil when idle: elapsed, remaining and progress (0 to 1) are nil without
-- an expected time, overrun is true when the flight outlasts it.
function FT.snapshot(s, now)
  if s.phase ~= "flying" then
    return nil
  end
  local elapsed = math.max(0, now - s.startedAt)
  local snap = { name = s.name, approx = s.approx, preview = s.preview, confirmed = s.confirmed, elapsed = elapsed }
  if s.expected then
    if s.preview then
      elapsed = elapsed % s.expected
      snap.elapsed = elapsed
    end
    snap.known = true
    snap.remaining = math.max(0, s.expected - elapsed)
    snap.progress = U.clamp(elapsed / s.expected, 0, 1)
    snap.overrun = elapsed > s.expected
  else
    snap.known = false
  end
  return snap
end

-- "2:35" for the remaining time (rounded up, so 0:00 only means the end), the elapsed time when the
-- duration is unknown. withApprox puts "ca." before an estimated remaining time.
function FT.timeText(snap, withApprox)
  if not snap.known then
    return FL.formatDuration(math.floor(snap.elapsed))
  end
  local text = FL.formatDuration(math.ceil(snap.remaining))
  if withApprox and snap.approx and not snap.overrun then
    return L["flight.approx"]:format(text)
  end
  return text
end

-- Short note under the time, or nil.
function FT.hint(snap)
  if not snap.known then
    return L["flighttimer.unknown"]
  elseif snap.overrun then
    return L["flighttimer.overrun"]
  end
end

-- Lands the flight and measures it. Returns "landed", seconds, recorded.
function FT.land(s, now)
  local elapsed = now - s.startedAt
  local recorded = false
  if s.key and not (s.expected and elapsed < s.expected * FT.MIN_SHARE) then
    recorded = FL.record(s.key, U.round(elapsed, 0.1)) == true
  end
  s.phase = "idle"
  return "landed", elapsed, recorded
end

-- Follows the game's taxi flag. Returns nil while nothing ends, else "landed", seconds, recorded or
-- "cancelled" (the game never confirmed the flight).
function FT.tick(s, now, onTaxi)
  if s.phase ~= "flying" or s.preview then
    return nil
  end
  if onTaxi then
    s.confirmed = true
    return nil
  end
  if s.confirmed then
    return FT.land(s, now)
  end
  if now - s.startedAt >= FT.GRACE then
    FT.cancel(s)
    return "cancelled"
  end
end
