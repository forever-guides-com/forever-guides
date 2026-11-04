-- The game-facing side of the time text (ns.TimeFormat). A time the game keeps secret cannot be read, compared
-- or calculated, but a duration object can write it: the numeric rule formatter (TimeFormatLogic.Rules) is handed
-- to the object's FormatRemainingDuration and the finished text, possibly secret itself, goes to a font string.
-- Nothing here is measured in the client: every call is protected, the first variant that works is kept for the
-- session and a refusal is not asked again. Also builds a duration object from the add-on's own numbers (the
-- computed aura timer) the same adaptive way.
local _, ns = ...
local TL, K = ns.TimeFormatLogic, ns.CooldownCore
local G = ns.CursorTimers.Guard
local finite, hidden = G.finite, G.hidden

local M = {}
ns.TimeFormat = M

-- What the session learned: per stage true (it worked), false (refused, not asked again), nil (untried), the
-- breakpoint order and time modifier that worked, the way an own duration object was filled. diag is what the
-- probes and the diagnosis windows read: the stage that wrote the last text and the reason of each refusal.
M.state = { rule = nil, order = nil, modifier = nil, own = nil, ownDead = false }
M.diag = { stage = nil, why = {}, ownVariant = nil, ownWhy = nil }

-- Time modifiers tried for FormatRemainingDuration: real time, base time, none.
local MODIFIERS = { "RealTime", "BaseTime", false }

local function methodOf(obj, name)
  local ok, fn = pcall(function()
    return obj[name]
  end)
  return ok and type(fn) == "function" and fn or nil
end

-- obj:name(...) protected: true and the first result, or false and "absent" or the error text.
local function invoke(obj, name, ...)
  local fn = methodOf(obj, name)
  if not fn then
    return false, "absent"
  end
  local ok, a = pcall(fn, obj, ...)
  if not ok then
    return false, tostring(a)
  end
  return true, a
end

local function enumValue(group, name)
  local enum = rawget(_G, "Enum")
  local list = type(enum) == "table" and enum[group] or nil
  local value = type(list) == "table" and list[name] or nil
  return finite(value) and value or nil
end

-- Formatters ------------------------------------------------------------------------------------------

local formatters = {}

-- The rules as the game takes them: the rounding as its enum value (left out when the client lacks the enum).
local function gameRules(rules)
  local out = {}
  for i, r in ipairs(rules) do
    out[i] = { threshold = r.threshold, format = r.format, step = r.step, components = r.components }
    out[i].rounding = enumValue("NumericRuleFormatRounding", r.rounding)
  end
  return out
end

-- The order tried first: the one that worked, else the constant; the other follows.
local function orders()
  local first = M.state.order or TL.RULE_ORDER
  return { first, first == "ascending" and "descending" or "ascending" }
end

local function build(p, gate)
  local util = rawget(_G, "C_StringUtil")
  local create = type(util) == "table" and util.CreateNumericRuleFormatter or nil
  if type(create) ~= "function" then
    return nil, "absent"
  end
  local why = "no formatter"
  for _, order in ipairs(orders()) do
    local ok, formatter = pcall(create)
    if ok and formatter ~= nil then
      local set, err = invoke(formatter, "SetBreakpoints", gameRules(TL.Rules(p, order, gate)))
      if set then
        M.state.order = order
        return formatter
      end
      why = err
    elseif not ok then
      why = tostring(formatter)
    end
  end
  return nil, why
end

-- The numeric rule formatter of a time style, made once per look and kept. nil and the reason when the client
-- cannot make it. A `gate` (seconds) makes it write nothing from that time on.
function M.Formatter(p, gate)
  local key = TL.Key(p, nil, gate)
  local formatter = formatters[key]
  if formatter == nil then
    local why
    formatter, why = build(p, gate)
    if formatter == nil then
      return nil, why
    end
    formatters[key] = formatter
  end
  return formatter
end

-- Stages ----------------------------------------------------------------------------------------------

local function refused(stage, why)
  M.diag.why[stage] = why
  M.state[stage] = false
  return false, why
end

-- The text the formatter writes for the remaining time of the object: the first modifier that works is kept.
local function formatRemaining(object, formatter)
  local why = "absent"
  local from, to = 1, #MODIFIERS
  if M.state.modifier then
    from, to = M.state.modifier, M.state.modifier
  end
  for i = from, to do
    local name = MODIFIERS[i]
    local modifier = name and enumValue("DurationTimeModifier", name)
    if not name or modifier ~= nil then
      local ok, text
      if name then
        ok, text = invoke(object, "FormatRemainingDuration", formatter, modifier)
      else
        ok, text = invoke(object, "FormatRemainingDuration", formatter)
      end
      if ok and (hidden(text) or type(text) == "string") then
        M.state.modifier = i
        return text
      end
      why = ok and "no text" or text
    end
  end
  return nil, why
end

-- Stage "rule": the numeric rule formatter on the object. A readable empty text is no failure once the stage
-- has worked (the time may just have run out).
local function viaRule(fs, object, p)
  if M.state.rule == false then
    return false, M.diag.why.rule
  end
  local formatter, why = M.Formatter(p)
  if not formatter then
    return refused("rule", why)
  end
  local text
  text, why = formatRemaining(object, formatter)
  if text == nil then
    return refused("rule", why)
  end
  if not hidden(text) and text == "" and M.state.rule ~= true then
    return refused("rule", "empty text")
  end
  local set, err = invoke(fs, "SetText", text)
  if not set then
    return refused("rule", err)
  end
  M.state.rule = true
  return true
end

-- Stage "format": the remaining duration, as the game gives it, formatted by the font string into a decimal
-- number of seconds. Only the seconds style reads like that.
local function viaFormat(fs, object, p)
  local ok, value = invoke(object, "GetRemainingDuration")
  if ok and value == nil then
    ok, value = false, "no value"
  end
  if ok then
    ok, value = invoke(fs, "SetFormattedText", K.TimeFormat(p.timeDecimals, p.timeSuffix), value)
  end
  if not ok then
    M.diag.why.format = value
    return false, value
  end
  -- A text the game keeps secret counts as one; only a readable empty text is a failure.
  local get = methodOf(fs, "GetText")
  local got, text = false, nil
  if get then
    got, text = pcall(get, fs)
  end
  if not got then
    text = nil
  end
  if not hidden(text) and (type(text) ~= "string" or text == "") then
    M.diag.why.format = "empty text"
    return false, "empty text"
  end
  return true
end

local STAGE = { rule = viaRule, format = viaFormat }

-- Whether the stage of the chain may still be tried (it was not refused before).
function M.Open(stage)
  return M.state[stage] ~= false
end

-- Writes the remaining time of a duration object into a font string through the stages listed (names of
-- TimeFormatLogic.STAGES, tried in this order). p holds the time look. Returns true and the stage that wrote it,
-- or false and the reason of the last refusal. The text is a snapshot: call again on every tick.
function M.Write(fs, object, p, stages)
  local why = "no stage"
  for _, stage in ipairs(stages) do
    local ok, result = STAGE[stage](fs, object, p)
    if ok then
      M.diag.stage = stage
      return true, stage
    end
    why = result
  end
  return false, why
end

-- Own duration object --------------------------------------------------------------------------------

-- A duration object for a run that began at `start` and lasts `duration` seconds (readable numbers of the
-- add-on's own, e.g. a computed aura timer). The first call of TimeFormatLogic.OWN_VARIANTS that the client
-- accepts is kept for the session. nil and the reason when none works.
function M.OwnDuration(start, duration)
  if not (finite(start) and finite(duration) and duration > 0) then
    return nil, "no numbers"
  end
  if M.state.ownDead then
    return nil, M.diag.ownWhy
  end
  local holder = rawget(_G, "C_DurationUtil")
  local create = type(holder) == "table" and holder.CreateDuration or nil
  if type(create) ~= "function" then
    M.diag.ownWhy = "absent"
    return nil, "absent"
  end
  local list = {}
  if M.state.own then
    list[1] = M.state.own
  end
  for i = 1, #TL.OWN_VARIANTS do
    if i ~= M.state.own then
      list[#list + 1] = i
    end
  end
  local why = "no object"
  for _, i in ipairs(list) do
    local variant = TL.OWN_VARIANTS[i]
    local ok, object = pcall(create)
    if ok and object ~= nil then
      local set, err = invoke(object, variant.method, unpack(TL.OwnArgs(variant, start, duration)))
      if set then
        M.state.own = i
        M.diag.ownVariant = variant.method .. (variant.rate and "+rate" or "")
        return object
      end
      why = err
    elseif not ok then
      why = tostring(object)
    end
  end
  M.diag.ownWhy = why
  if M.state.own == nil then
    M.state.ownDead = true
  end
  return nil, why
end
