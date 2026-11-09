-- Cooldown logic without WoW API (ns.CooldownCore), shared by the cooldown element of the mouse cursor ring
-- and the planned cooldown manager: the spell a saved base id means on this character, the state of a
-- cooldown from the raw values the game gave (a value it keeps secret arrives as nil), the charges, the
-- time text, the end of a cooldown and what a game event means for one element. The code that talks to the
-- game reads every value protected and passes only what it could read.
local _, ns = ...

local K = {}
ns.CooldownCore = K

-- Where the cooldown comes from. The game-facing side keeps one entry per source.
K.SOURCES = { "spell", "pet", "item" }
-- Which rank of a chosen spell counts: the highest learned rank of its chain, or only the chosen id.
K.RANK_MODES = { "max", "exact" }
K.TIME_FORMATS = { "auto", "short" }
-- How a time is written: by length (a decimal below ten seconds, minutes and hours from a minute on), as the
-- one number of seconds the game formats, as a clock, or compact (whole minutes and hours).
K.TIME_STYLES = { "auto", "seconds", "clock", "short" }
-- An item is chosen by the equipment slot it sits in (the cooldown follows the item worn there) or by its id.
K.ITEM_MODES = { "slot", "id" }
K.ITEM_ID_MAX = 9999999
K.SLOT_MAX = 19
-- The two trinket slots, then the other slots that can hold an item with a use effect.
K.TRINKET_SLOTS = { 13, 14 }
K.USABLE_SLOTS = { 13, 14, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 17, 18 }
-- Digits after the decimal point of the formatted time.
K.DECIMALS = { 0, 1, 2 }

-- Reference spell whose cooldown is the global cooldown, its longest length in seconds and the slack that
-- tells the global cooldown from a short cooldown of the spell itself.
K.GCD_SPELL = 29515
K.GCD_MAX = 1.5
K.GCD_SLACK = 0.05
-- Below this many seconds the time text shows tenths.
K.DECIMAL_BELOW = 3
-- Below this many seconds the auto style shows decimals, and the longest time any style writes (999 hours).
K.AUTO_DECIMALS_BELOW = 10
K.TIME_MAX = 999 * 3600
-- Slack that keeps a float product like 9.9 * 10 from rounding up to the next whole number.
local EPSILON = 1e-6

-- The unit that casts for a source.
local UNIT = { spell = "player", pet = "pet" }
-- What an event means for an item: the cooldown changed, or the worn or carried items did.
local ITEM_EVENTS = {
  BAG_UPDATE_COOLDOWN = "refresh",
  ACTIONBAR_UPDATE_COOLDOWN = "refresh",
  SPELL_UPDATE_COOLDOWN = "refresh",
  PLAYER_EQUIPMENT_CHANGED = "resolve",
  BAG_UPDATE = "resolve",
}

-- A base id of a well-known cooldown for each class (the example of the preset), checked against the data
-- in the tests.
K.SAMPLES = {
  WARRIOR = 2687,
  PALADIN = 853,
  HUNTER = 3045,
  ROGUE = 2983,
  PRIEST = 8122,
  SHAMAN = 8042,
  MAGE = 1953,
  WARLOCK = 6789,
  DRUID = 5229,
}

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- The example base id of a class token, nil for an unknown class.
function K.Sample(class)
  return K.SAMPLES[class]
end

-- Spells ----------------------------------------------------------------------------------------------

-- The base id of the rank chain a spell id belongs to (the id itself for a spell without a chain).
function K.BaseOf(id)
  local spell = ns.DataApi.Spell(id)
  return spell and (spell.b or spell.id) or id
end

-- The spell a saved base id means on this character: the highest rank it has learned, replaced by what the
-- game puts in its place right now (a talent or an aura can do that). env.known(id) answers true, false or
-- nil (the game cannot say), env.override(id) the replacing id or nil.
-- Returns { id, base, known = true|false|nil, ids = set of the ids an event may name }. A chain without any
-- learned rank is unknown (known false, id = base); when the game cannot say, the highest rank stands in.
function K.Resolve(base, env)
  local chain = ns.DataApi.RankChain(base)
  if #chain == 0 then
    chain = { { id = base } }
  end
  local id, known, unsure
  for i = #chain, 1, -1 do
    local answer = env.known(chain[i].id)
    if answer == true then
      id, known = chain[i].id, true
      break
    elseif answer == nil then
      unsure = true
    end
  end
  if not id then
    if unsure then
      id = chain[#chain].id
    else
      id, known = base, false
    end
  end
  local out = { id = id, base = base, known = known, ids = { [base] = true, [id] = true } }
  if known ~= false then
    local replaced = env.override(id)
    if finite(replaced) and replaced > 0 then
      out.id = replaced
      out.ids[replaced] = true
    end
  end
  return out
end

-- The id an exact choice means: the saved exact id, the base id for a choice saved without one.
function K.ExactOf(props)
  if finite(props.spellExact) and props.spellExact > 0 then
    return props.spellExact
  end
  return props.spellBase
end

-- The spell of one exact id, no other rank stands in for it. Same shape as K.Resolve: the id is known, unknown
-- or unsure (nil, it then stands), and an override replaces a known one.
function K.ResolveExact(id, env)
  local known = env.known(id)
  local out = { id = id, base = id, known = known, ids = { [id] = true } }
  if known ~= false then
    local replaced = env.override(id)
    if finite(replaced) and replaced > 0 then
      out.id = replaced
      out.ids[replaced] = true
    end
  end
  return out
end

-- The spell the props mean: the exact id for rankMode "exact", else the highest learned rank of the base chain.
function K.ResolveSpell(props, env)
  if props.rankMode == "exact" then
    return K.ResolveExact(K.ExactOf(props), env)
  end
  return K.Resolve(props.spellBase, env)
end

-- The item a saved choice means right now. props: itemMode, itemSlot, itemId. env.slotItem(slot) answers the
-- id worn there (nil for an empty slot), env.count(id) how many the character has (nil when the client cannot
-- say). Returns { id, slot, known = true|false|nil, ids }: id 0 and known false when nothing is worn or chosen.
function K.ResolveItem(props, env)
  local slot = props.itemMode == "slot" and props.itemSlot or nil
  local id = slot and env.slotItem(slot) or props.itemId
  if not finite(id) or id <= 0 then
    return { id = 0, slot = slot, known = false, ids = {} }
  end
  local known = true
  if not slot then
    local count = env.count(id)
    if finite(count) then
      known = count > 0
    else
      known = nil
    end
  end
  return { id = id, slot = slot, known = known, ids = { [id] = true } }
end

-- Cooldown state ----------------------------------------------------------------------------------------

-- { current, max } of a charge reading with both numbers readable, else nil.
function K.Charges(c)
  if type(c) ~= "table" or not (finite(c.current) and finite(c.max)) or c.max < 1 then
    return nil
  end
  local max = math.floor(c.max)
  return { current = math.min(math.max(math.floor(c.current), 0), max), max = max }
end

-- The state of one cooldown. f holds what could be read, every field nil when it could not:
--   isActive, isOnGCD (booleans), start, duration (seconds), zero (boolean from a duration object),
--   charges = { current, max }, secret = true when the game kept something back, enabled = false when an item
--   says its cooldown does not count now (the game then draws none).
-- gcd is the length of the global cooldown in seconds (nil when unknown, always for an item), now the clock.
-- Returns { state = "ready" | "active" | "gcd" | "unknown", secret, remaining, charges }: "gcd" is a cooldown
-- that is only the global one, "unknown" that nothing readable says either way. A spell with charges is ready
-- while one charge is left; `remaining` then is the time until the next charge.
function K.State(f, now, gcd)
  local out = { state = "unknown", secret = f.secret == true, charges = K.Charges(f.charges) }
  local start, duration = f.start, f.duration
  if finite(start) and finite(duration) and finite(now) and start > 0 and duration > 0 then
    out.remaining = math.max(0, start + duration - now)
  end
  local running
  if f.enabled == false then
    running, out.remaining = false, nil
  elseif out.charges and out.charges.max > 1 and out.charges.current > 0 then
    running = false
  elseif out.remaining ~= nil then
    running = out.remaining > 0
  elseif f.isActive ~= nil then
    running = f.isActive
  elseif finite(duration) then
    running = duration > 0
  elseif f.zero ~= nil then
    running = not f.zero
  end
  if running == nil then
    return out
  end
  if not running then
    out.state = "ready"
    return out
  end
  local onGcd = f.isOnGCD
  if onGcd == nil and finite(duration) and finite(gcd) then
    onGcd = duration <= gcd + K.GCD_SLACK
  end
  out.state = onGcd == true and "gcd" or "active"
  return out
end

-- What a change of state means: "ready" when a cooldown has ended (the moment to warn, also when the global
-- cooldown takes over at that moment), "started" when one begins, nil otherwise. A state that was unknown
-- counts only with `ended`, the game's own word that a cooldown ran out.
function K.Transition(previous, state, ended)
  if (previous == "active" or (previous == "unknown" and ended == true)) and (state == "ready" or state == "gcd") then
    return "ready"
  end
  if state == "active" and previous ~= "active" then
    return "started"
  end
  return nil
end

-- Whether a running cooldown has ended, from the two booleans the game keeps readable in combat: `isActive`
-- of the cooldown table and `zero` (IsZero of the duration object, which leaves the global cooldown out).
-- "ready" when either says nothing runs (the global cooldown may), "active" when one says it runs and none
-- says otherwise, nil when neither could be read.
function K.Poll(isActive, zero)
  if zero == true or isActive == false then
    return "ready"
  end
  if isActive == true or zero == false then
    return "active"
  end
  return nil
end

-- The way a list of readings gets its time text: "readable" when every one gave start and duration as
-- numbers, "secret" when none did, "mixed" otherwise; nil for an empty list.
function K.TextPath(list)
  local readable, secret = 0, 0
  for _, ok in ipairs(list) do
    if ok then
      readable = readable + 1
    else
      secret = secret + 1
    end
  end
  if readable + secret == 0 then
    return nil
  end
  return secret == 0 and "readable" or readable == 0 and "secret" or "mixed"
end

-- Text -------------------------------------------------------------------------------------------------

-- The time left as short text, "" for no time. Tenths below DECIMAL_BELOW seconds, whole seconds up to a
-- minute, then minutes and seconds and from an hour on hours and minutes ("auto"). "short" counts whole
-- minutes ("2m") and hours ("1h") instead. A partial second counts as the whole one, so the text never
-- shows 0.
function K.FormatTime(seconds, format)
  if not finite(seconds) or seconds <= 0 then
    return ""
  end
  if seconds < K.DECIMAL_BELOW then
    return string.format("%.1f", math.ceil(seconds * 10) / 10)
  end
  local whole = math.ceil(seconds)
  if whole < 60 then
    return tostring(whole)
  end
  if format == "short" then
    local minutes = math.ceil(whole / 60)
    if minutes < 60 then
      return string.format("%dm", minutes)
    end
    return string.format("%dh", math.ceil(whole / 3600))
  end
  if whole < 3600 then
    return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
  end
  return string.format("%dh %02dm", math.floor(whole / 3600), math.floor((whole % 3600) / 60))
end

local function wholeSeconds(seconds)
  return math.ceil(seconds - EPSILON)
end

-- h:mm or, with units, "1h 05m": the minutes of an hour and more count up.
local function hoursText(whole, units)
  local total = math.ceil(whole / 60)
  return string.format(units and "%dh %02dm" or "%d:%02d", math.floor(total / 60), total % 60)
end

-- The time left in the way the style says; "" for no time. p holds timeStyle, timeDecimals, timeSuffix and
-- timeFormat, `mode` is the timer look that writes the text ("own" or the formatted one).
--   seconds: what each look wrote before the styles existed (the game-formatted decimal number, or the own
--     text of timeFormat), so a long time stays one big number.
--   clock: m:ss and h:mm:ss, whole seconds.
--   auto: a decimal below ten seconds (timeDecimals), whole seconds below a minute, m:ss to an hour, then
--     h:mm. timeSuffix writes the units ("4.2s", "29m 05s", "1h 05m"), timeFormat "short" counts whole
--     minutes and hours ("29m", "1h"). A partial second counts as a whole one, the text never shows 0.
function K.FormatStyled(seconds, p, mode)
  if not finite(seconds) or seconds <= 0 then
    return ""
  end
  seconds = math.min(seconds, K.TIME_MAX)
  if p.timeStyle == "seconds" then
    if mode == "own" then
      return K.FormatTime(seconds, p.timeFormat)
    end
    return K.FormatDecimals(seconds, p.timeDecimals, p.timeSuffix)
  end
  local whole = wholeSeconds(seconds)
  if p.timeStyle == "clock" then
    if whole < 3600 then
      return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
    end
    return string.format("%d:%02d:%02d", math.floor(whole / 3600), math.floor((whole % 3600) / 60), whole % 60)
  end
  local units = p.timeSuffix == true
  if seconds < K.AUTO_DECIMALS_BELOW then
    local digits = (p.timeDecimals == 0 or p.timeDecimals == 2) and p.timeDecimals or 1
    local scale = 10 ^ digits
    local shown = math.max(1, math.ceil(seconds * scale - EPSILON)) / scale
    if shown < K.AUTO_DECIMALS_BELOW then
      return string.format("%." .. digits .. "f", shown) .. (units and "s" or "")
    end
  end
  if whole < 60 then
    return string.format("%d", whole) .. (units and "s" or "")
  end
  local short = p.timeFormat == "short" or p.timeStyle == "short"
  if whole < 3600 then
    local minutes = math.ceil(whole / 60)
    if short and minutes < 60 then
      return string.format("%dm", minutes)
    elseif not short then
      return string.format(units and "%dm %02ds" or "%d:%02d", math.floor(whole / 60), whole % 60)
    end
  end
  if short then
    return string.format("%dh", math.ceil(whole / 3600))
  end
  return hoursText(whole, units)
end

-- The format string the game formats the remaining time with: `decimals` digits, "s" after the number when
-- `suffix`. %.0f takes any number, %d would refuse a fraction.
function K.TimeFormat(decimals, suffix)
  local digits = (decimals == 0 or decimals == 1 or decimals == 2) and decimals or 1
  return "%." .. digits .. "f" .. (suffix and "s" or "")
end

-- The text of K.TimeFormat for a readable time, "" for no time: what the editor preview shows for the
-- formatted look.
function K.FormatDecimals(seconds, decimals, suffix)
  if not finite(seconds) or seconds <= 0 then
    return ""
  end
  return string.format(K.TimeFormat(decimals, suffix), seconds)
end

-- The colour (hex) and opacity of the curve at `remaining` seconds, the same steps as the game's colour curve: the
-- last colour below `curveLow`, the middle one from there to `curveMid`, the first one from `curveMid` on.
-- p holds curveMid, curveLow, curveColorHigh/Mid/Low and curveAlphaHigh/Mid/Low.
function K.CurveColor(remaining, p)
  local step = "Low"
  if remaining >= p.curveMid then
    step = "High"
  elseif remaining >= p.curveLow then
    step = "Mid"
  end
  return p["curveColor" .. step], p["curveAlpha" .. step]
end

-- Items -------------------------------------------------------------------------------------------------

-- The ways to read the duration object of an item's cooldown, in the order they are tried: a call of the game
-- that gives one for an item (`direct`, when the client has it), the object of the spell the item casts
-- (`spell`, needs the id of that spell), an object built from readable start and duration (`built`, which
-- only works while the game lets the add-on read them). An item without a use spell keeps the last way.
function K.ItemReads(direct, spellId)
  local list = {}
  if direct == true then
    list[#list + 1] = "direct"
  end
  if finite(spellId) and spellId > 0 then
    list[#list + 1] = "spell"
  end
  list[#list + 1] = "built"
  return list
end

-- Events ------------------------------------------------------------------------------------------------

-- What an event means for one element: "resolve" (the spell list or the pet changed, find the learned rank
-- again and read the cooldown), "refresh" (read the cooldown again) or nil (not this element's spell).
-- own = { source, ids = set of ids, slot = equipment slot of an item chosen by slot }. a1..a3 are the event arguments, nil when the game keeps one secret:
-- a missing spell id counts as "any spell", so a secret payload refreshes instead of being missed.
function K.Route(event, own, a1, a2, a3)
  if own.source == "item" then
    -- a1 slot of PLAYER_EQUIPMENT_CHANGED; an item chosen by slot ignores the bags, one chosen by id the slots.
    if event == "PLAYER_EQUIPMENT_CHANGED" and own.slot ~= nil and a1 ~= nil and a1 ~= own.slot then
      return nil
    elseif event == "BAG_UPDATE" and own.slot ~= nil then
      return nil
    end
    return ITEM_EVENTS[event]
  end
  if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
    return "resolve"
  elseif event == "UNIT_PET" then
    return own.source == "pet" and "resolve" or nil
  elseif event == "PET_BAR_UPDATE_COOLDOWN" then
    return own.source == "pet" and "refresh" or nil
  elseif event == "SPELL_UPDATE_CHARGES" then
    return "refresh"
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    -- a1 unit, a3 spell id
    if a1 ~= nil and a1 ~= UNIT[own.source] then
      return nil
    end
    return (a3 == nil or own.ids[a3]) and "refresh" or nil
  elseif event == "SPELL_UPDATE_COOLDOWN" then
    -- a1 spell id, a2 base spell id
    return (a1 == nil or own.ids[a1] or (a2 ~= nil and own.ids[a2])) and "refresh" or nil
  end
  return nil
end
