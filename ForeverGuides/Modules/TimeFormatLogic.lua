-- Time text rules without WoW API (ns.TimeFormatLogic): the breakpoint tables the game's numeric rule formatter
-- is given so it can write a time the add-on may not read (minutes and seconds of a secret duration), and a
-- model of how such a table formats a plain number, used by tests and the probes to check the game's answer. The
-- tables follow the time styles of CooldownCore.FormatStyled. The game side is TimeFormat.lua.
local _, ns = ...

local T = {}
ns.TimeFormatLogic = T

-- The order the breakpoints are handed over in. The client's expectation is not measured: the game side tries
-- the other order when it refuses this one, and a probe can show which one writes the right text.
T.RULE_ORDER = "ascending"
T.ORDERS = { "ascending", "descending" }
-- A threshold is the time in seconds from which a rule applies (until the next one).
T.HOUR = 3600
T.MINUTE = 60
T.DECIMAL_BELOW = 10
-- The calls that fill a duration object from readable numbers, in the order they are tried: the call and
-- whether the rate argument follows.
T.OWN_VARIANTS = {
  { method = "SetTimeFromStart", rate = false },
  { method = "SetTimeFromStart", rate = true },
  { method = "SetTimeFromEnd", rate = false },
  { method = "SetTimeFromEnd", rate = true },
}
-- Names of the chain in the order they are tried: the numeric rule formatter, the game-formatted decimal
-- number, the game's number in a frame of its own, the game's number in the ring.
T.STAGES = { "rule", "format", "engineText", "engine" }

local EPSILON = 1e-6

local function rule(threshold, format, step, components)
  return { threshold = threshold, format = format, step = step, rounding = "Up", components = components }
end

local function digitsOf(decimals)
  return (decimals == 0 or decimals == 1 or decimals == 2) and decimals or 1
end

-- One rule per length of time of the style, lowest threshold first. p holds timeStyle, timeFormat,
-- timeDecimals and timeSuffix.
local function ascending(p)
  local K = ns.CooldownCore
  local units = p.timeSuffix == true
  local digits = digitsOf(p.timeDecimals)
  if p.timeStyle == "seconds" then
    local seconds = rule(0, K.TimeFormat(digits, units), 10 ^ -digits)
    seconds.rounding = "Nearest"
    return { seconds }
  end
  if p.timeStyle == "clock" then
    return {
      rule(0, "%d:%02d", 1, { { div = T.MINUTE }, { mod = T.MINUTE } }),
      rule(T.HOUR, "%d:%02d:%02d", 1, { { div = T.HOUR }, { div = T.MINUTE, mod = T.MINUTE }, { mod = T.MINUTE } }),
    }
  end
  local short = p.timeFormat == "short" or p.timeStyle == "short"
  local list = {}
  if digits > 0 then
    list[1] = rule(0, "%." .. digits .. "f" .. (units and "s" or ""), 10 ^ -digits)
    list[2] = rule(T.DECIMAL_BELOW, "%d" .. (units and "s" or ""), 1)
  else
    list[1] = rule(0, "%d" .. (units and "s" or ""), 1)
  end
  if short then
    list[#list + 1] = rule(T.MINUTE, "%dm", T.MINUTE, { { div = T.MINUTE } })
    list[#list + 1] = rule(T.HOUR, "%dh", T.HOUR, { { div = T.HOUR } })
  else
    list[#list + 1] = rule(T.MINUTE, units and "%dm %02ds" or "%d:%02d", 1, { { div = T.MINUTE }, { mod = T.MINUTE } })
    list[#list + 1] = rule(
      T.HOUR,
      units and "%dh %02dm" or "%d:%02d",
      T.MINUTE,
      { { div = T.HOUR }, { div = T.MINUTE, mod = T.MINUTE } }
    )
  end
  return list
end

-- The rules cut at `gate` seconds: the rules below it stay, from the gate on the text is empty (the number of an
-- aura that shows only below a time, written by the game without anyone comparing a secret time).
local function gated(list, gate)
  local out = {}
  for _, r in ipairs(list) do
    if r.threshold < gate then
      out[#out + 1] = r
    end
  end
  out[#out + 1] = { threshold = gate, format = "", step = 1, rounding = "Down" }
  return out
end

local function validGate(gate)
  return type(gate) == "number" and gate == gate and gate > 0 and gate < math.huge
end

-- The breakpoint rules of a style: a list of { threshold, format, step, rounding = "Up" | "Down" | "Nearest",
-- components = list of { div, mod } or nil }, in `order` (default T.RULE_ORDER). A valid `gate` (seconds) ends the
-- text there.
function T.Rules(p, order, gate)
  local list = ascending(p)
  if validGate(gate) then
    list = gated(list, gate)
  end
  if (order or T.RULE_ORDER) == "descending" then
    local reversed = {}
    for i = #list, 1, -1 do
      reversed[#reversed + 1] = list[i]
    end
    return reversed
  end
  return list
end

-- A key equal looks share, so a formatter can be cached under it: only what changes the rules counts.
function T.Key(p, order, gate)
  local style = p.timeStyle == "seconds" and "seconds" or p.timeStyle == "clock" and "clock" or "auto"
  local short = style == "auto" and (p.timeFormat == "short" or p.timeStyle == "short")
  return table.concat({
    style,
    short and "short" or "long",
    style == "clock" and "-" or digitsOf(p.timeDecimals),
    style ~= "clock" and p.timeSuffix == true and "s" or "-",
    order or T.RULE_ORDER,
    validGate(gate) and gate or "-",
  }, "|")
end

local function rounded(r, value)
  local scaled = value / r.step
  if r.rounding == "Down" then
    return math.floor(scaled + EPSILON) * r.step
  elseif r.rounding == "Nearest" then
    return math.floor(scaled + 0.5) * r.step
  end
  return math.ceil(scaled - EPSILON) * r.step
end

-- What the rules write for a readable number of seconds (the rule with the highest threshold at or below it,
-- the value rounded to its step, split into the components): the model of the game's formatter. "" for a
-- number below zero.
function T.Evaluate(rules, seconds)
  if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 then
    return ""
  end
  local chosen
  for _, r in ipairs(rules) do
    if r.threshold <= seconds and (chosen == nil or r.threshold > chosen.threshold) then
      chosen = r
    end
  end
  if chosen == nil then
    return ""
  end
  local value = rounded(chosen, seconds)
  if not chosen.components then
    return string.format(chosen.format, value)
  end
  local args = {}
  for i, part in ipairs(chosen.components) do
    local v = value
    if part.div then
      v = math.floor(v / part.div + EPSILON)
    end
    if part.mod then
      v = v % part.mod
    end
    args[i] = v
  end
  return string.format(chosen.format, unpack(args))
end

-- The arguments of the call `variant` of T.OWN_VARIANTS that fills a duration object for a run that began at
-- `start` and lasts `duration` seconds.
function T.OwnArgs(variant, start, duration)
  local args = { variant.method == "SetTimeFromEnd" and start + duration or start, duration }
  if variant.rate then
    args[3] = 1
  end
  return args
end
