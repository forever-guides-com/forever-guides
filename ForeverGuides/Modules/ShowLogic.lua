-- The "show when" rule shared by the cooldown and the aura element of the mouse cursor ring (ns.ShowLogic), without
-- WoW API: when the element is visible (always, only below a number of seconds, only while it runs, only while
-- it is ready), the repair of the saved values and the decision from what could be read. A time the game keeps
-- secret is never compared: the decision then asks for "curve", and the game-facing side lets the engine
-- evaluate a step curve (CurvePoints) on the duration object.
local _, ns = ...

local S = {}
ns.ShowLogic = S

-- Cooldown: all four. Aura: no "ready" (an aura has no ready state; "missing" is a condition of its own).
S.SHOW_WHEN = { "always", "below", "running", "ready" }
S.AURA_SHOW_WHEN = { "always", "below", "running" }
S.BELOW_MIN, S.BELOW_MAX, S.BELOW_STEP, S.BELOW_DEFAULT = 0.5, 600, 0.5, 5
-- The curve steps down this far above the threshold, so a time of exactly the threshold still shows.
S.EPSILON = 0.01

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- The threshold in seconds: halves, clamped to the range.
function S.CleanBelow(v, default)
  if not finite(v) then
    return default
  end
  local halves = math.floor(v / S.BELOW_STEP + 0.5) * S.BELOW_STEP
  return math.min(math.max(halves, S.BELOW_MIN), S.BELOW_MAX)
end

-- showWhen and showBelow of a saved element. `allowed` lists the rules the element knows. A layout from before
-- the rule existed has no showWhen: its hideReady flag (hide while ready) is the rule "running".
function S.Clean(raw, default, below, allowed)
  local value = raw.showWhen
  local known = false
  for _, item in ipairs(allowed) do
    if value == item then
      known = true
    end
  end
  if not known then
    value = raw.showWhen == nil and raw.hideReady == true and "running" or default
  end
  return value, S.CleanBelow(raw.showBelow, below)
end

-- What the rule means for one reading. rule = { showWhen, showBelow, permanentCounts }; s holds
--   idle: true when nothing runs (the cooldown is ready or only the global one, the aura is absent), false when
--     it runs, nil when that is not known;
--   remaining: seconds left when readable; permanent: the aura has no end; canCurve: the client can evaluate
--     a curve on a duration object.
-- Returns "show", "hide" or "curve" (the time is not readable: the engine decides through CurvePoints).
function S.Decide(rule, s)
  local when = rule.showWhen
  if when == "running" then
    return s.idle == true and "hide" or "show"
  elseif when == "ready" then
    return s.idle == true and "show" or "hide"
  elseif when ~= "below" then
    return "show"
  end
  if s.idle == true then
    return "hide"
  end
  if s.permanent == true then
    return rule.permanentCounts == true and "show" or "hide"
  end
  if finite(s.remaining) then
    return s.remaining <= rule.showBelow and "show" or "hide"
  end
  return s.canCurve == true and "curve" or "show"
end

-- The points of the step curve over the remaining seconds: full alpha from 0, none from just above `below`.
-- { seconds, alpha } each, for the colour curve whose alpha the frame takes.
function S.CurvePoints(below)
  return { { 0, 1 }, { below + S.EPSILON, 0 } }
end

-- Seconds until a hidden element has to show because its readable time left falls to the threshold, nil when
-- the rule has no such moment (the caller reads again then and decides anew).
function S.CrossIn(rule, remaining)
  if rule.showWhen == "below" and finite(remaining) and remaining > rule.showBelow then
    return remaining - rule.showBelow
  end
  return nil
end
