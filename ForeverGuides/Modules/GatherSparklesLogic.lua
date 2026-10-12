-- Gathering sparkles, the pure side (no game access): which kind of object the soft target is, the
-- state machine with hold times and fades, the style choice, the console variable sets and how the
-- original values are kept and restored, the colors per state and the step of one particle.
-- Modules/GatherSparkles.lua reads the client and draws.
local _, ns = ...

local Logic = {}
ns.GatherSparklesLogic = Logic

-- Original effect model of the client and the two textures of its particles (the sharp star, the soft
-- glow). Only references, nothing of it is shipped. The client takes the model by its file data id only,
-- a path gives "Invalid model file", and textures outside Interface draw nothing.
Logic.MODEL_ID = 5735510
Logic.STAR_TEXTURE = 166963
Logic.GLOW_TEXTURE = 3996644
Logic.TEXTURE_IDS = { Logic.STAR_TEXTURE, Logic.GLOW_TEXTURE }
-- Whether "automatic" draws the original model when it loads. Off until it is confirmed that the model
-- draws something at the target: a model that loads can still be invisible.
Logic.AUTO_PREFERS_MODEL = false
Logic.TEXTURE_FALLBACK = "Interface\\Cooldown\\star4"

Logic.STYLES = { "auto", "original", "particles" }
Logic.CATEGORIES = { "ore", "herbs", "quest" }

-- Timing in seconds: poll of the soft target, hold time before a state change, cross fade between
-- two states, fade in and out, fixed step of the animation.
Logic.POLL = 0.12
Logic.HOLD = { ready = 0.15, far = 0.15, locked = 0.6 }
Logic.FADE_MIX = 0.3
Logic.FADE_IN = 0.35
Logic.FADE_OUT = 0.3
Logic.STEP = 1 / 30

-- Look of the effect in a state: color and brightness, plus the dark color of the layer behind the glow
-- (it keeps the effect readable on bright ground, where additive light vanishes). Gold when ready,
-- dimmed when too far, gray when the skill is too low. No state is fainter than MIN_ALPHA once faded in.
Logic.MIN_ALPHA = 0.5
local LOOKS = {
  ready = { r = 1, g = 0.88, b = 0.52, a = 1, dr = 0.45, dg = 0.3, db = 0.04 },
  far = { r = 1, g = 0.88, b = 0.52, a = 0.6, dr = 0.35, dg = 0.24, db = 0.03 },
  locked = { r = 0.62, g = 0.62, b = 0.62, a = 0.5, dr = 0.2, dg = 0.2, db = 0.2 },
}
Logic.LOOKS = LOOKS

-- Stars of the own effect: count, size range and spread radius in pixels. Size of the host frame, the
-- distance below the name plate to the object, strata and level (above the interface, nothing covers it).
Logic.PARTICLES = 7
Logic.STAR_SIZE_MIN = 40
Logic.STAR_SIZE_MAX = 56
Logic.RADIUS = 46
Logic.HOST_SIZE = 128
Logic.HOST_STRATA = "HIGH"
Logic.HOST_LEVEL = 500

-- The effect is a child of the name plate, so it takes over the scale the client gives the plate with
-- the distance of the object: a fixed gap in plate units sits right at every camera distance. OFFSET is
-- the gap below the plate center (the plate hangs at the height of the game icon), tuned by the player.
Logic.OFFSET_DEFAULT = -45
Logic.OFFSET_MIN = -200
Logic.OFFSET_MAX = 0
Logic.OFFSET_STEP = 5

local function isNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- The setting inside its range, the default for anything that is no number.
function Logic.CleanOffset(value)
  if not isNumber(value) then
    return Logic.OFFSET_DEFAULT
  end
  return math.min(Logic.OFFSET_MAX, math.max(Logic.OFFSET_MIN, value))
end

-- Size of all textures of the effect in percent of the base sizes (the host frame keeps its size), and
-- the soft target range in yards. The range setting is "max" (the most the game offers) or a number of
-- yards below that.
Logic.SIZE_DEFAULT = 75
Logic.SIZE_MIN = 30
Logic.SIZE_MAX = 150
Logic.SIZE_STEP = 5
Logic.RANGE_MIN = 0
Logic.RANGE_STEP = 1
Logic.RANGE_MAX_SETTING = "max"
-- Measured in the Forever client 1.60.1 (build 70338): larger values of SoftTargetInteractRange change nothing.
Logic.RANGE_GAME_MAX = 16

local function clampSetting(value, default, min, max)
  if not isNumber(value) then
    return default
  end
  return math.min(max, math.max(min, value))
end

function Logic.CleanSize(value)
  return clampSetting(value, Logic.SIZE_DEFAULT, Logic.SIZE_MIN, Logic.SIZE_MAX)
end

-- Yards for SoftTargetInteractRange: the game maximum for nil, "max" and anything that is no number, a
-- number inside 0 to the game maximum.
function Logic.EffectiveRange(setting)
  if not isNumber(setting) then
    return Logic.RANGE_GAME_MAX
  end
  return math.min(Logic.RANGE_GAME_MAX, math.max(Logic.RANGE_MIN, setting))
end

-- The stored setting with numbers from the time of larger ranges (60, 95, 100) made "max".
function Logic.NormalizeRange(setting)
  if isNumber(setting) and setting >= Logic.RANGE_GAME_MAX then
    return Logic.RANGE_MAX_SETTING
  end
  return setting
end

-- Slider position of a setting.
function Logic.RangeSlider(setting)
  return Logic.EffectiveRange(setting)
end

-- The setting a slider position stands for: the top is "max", below it the yards.
function Logic.RangeSetting(position)
  if not isNumber(position) or position >= Logic.RANGE_GAME_MAX then
    return Logic.RANGE_MAX_SETTING
  end
  return math.max(Logic.RANGE_MIN, position)
end

-- A base size in pixels scaled by the size setting (percent, kept inside its range): whole pixels, at least 1.
function Logic.ScaledSize(base, percent)
  return math.max(1, math.floor(base * Logic.CleanSize(percent) / 100 + 0.5))
end

-- Whether the soft target exists: world objects do not "exist" for UnitExists, so UnitIsGameObject
-- counts as well. true when either is true, false when both are false, nil when unknown (a value
-- is secret or missing and the other is not true).
function Logic.Exists(exists, isObject)
  if exists == true or isObject == true then
    return true
  end
  if exists == false and isObject == false then
    return false
  end
  return nil
end

-- Frame level of the effect: one under the plate (its text stays readable), nil when the plate level
-- is not a usable number (the level stays as it is).
function Logic.HostLevel(plateLevel)
  if not isNumber(plateLevel) then
    return nil
  end
  return math.max(0, plateLevel - 1)
end

-- Glow under the stars: size of the additive glow and of the dark layer behind it, the pulse period in
-- seconds, the alpha range of the pulse and the alpha of the dark layer (before the state brightness).
Logic.GLOW_SIZE = 84
Logic.DARK_SIZE = 96
Logic.GLOW_PERIOD = 2.4
Logic.GLOW_ALPHA_MIN = 0.5
Logic.GLOW_ALPHA_MAX = 0.9
Logic.DARK_ALPHA = 0.55
-- Seconds between two looks at a soft target the kind of which is not known yet, and how many looks.
Logic.WATCH = 0.12
Logic.RECHECKS = 3
-- Placement of the original model in its frame, to tune in the game.
Logic.MODEL = { scale = 1, x = 0, y = 0, z = 0, facing = 0 }

-- Kind of object ---------------------------------------------------------------------------------

-- The category of an object and whether it is locked, from the name of its cursor icon (a path or an
-- atlas name, any case). A number or anything unknown gives nil: the caller tries the tooltip next.
local function iconName(texture, atlas)
  if type(atlas) == "string" and atlas ~= "" then
    return atlas:lower()
  elseif type(texture) == "string" and texture ~= "" then
    return texture:lower()
  end
end

function Logic.Classify(texture, atlas)
  local name = iconName(texture, atlas)
  if not name then
    return nil, false
  end
  local locked = name:find("unable", 1, true) ~= nil
  if name:find("mine", 1, true) then
    return "ore", locked
  elseif name:find("gather", 1, true) or name:find("herb", 1, true) then
    return "herbs", locked
  elseif name:find("quest", 1, true) then
    return "quest", locked
  end
  return nil, locked
end

-- Fallback when the kind is not recognized: a world object (a game object, neither player nor creature)
-- the cursor icon of which names neither a quest nor a plain interaction (doors, mailboxes, benches).
-- Such an object is taken for something to gather, so ore and herbs the client names oddly still glitter.
Logic.OBJECT = "object"

-- "GameObject" of "GameObject-0-1234-...", nil without a usable guid.
function Logic.GuidKind(guid)
  if type(guid) ~= "string" then
    return nil
  end
  return guid:match("^(%a+)%-")
end

-- guid: the guid of the target when readable, isPlayer: UnitIsPlayer, creatureType: what UnitCreatureType
-- says (nil for an object, any text for a creature, "?" when the client cannot tell).
function Logic.IsWorldObject(guid, isPlayer, creatureType)
  local kind = Logic.GuidKind(guid)
  if kind then
    return kind == "GameObject"
  end
  return isPlayer == false and creatureType == nil
end

function Logic.ClassifyObject(guid, isPlayer, creatureType, texture, atlas)
  if not Logic.IsWorldObject(guid, isPlayer, creatureType) then
    return nil
  end
  local name = iconName(texture, atlas)
  if name and (name:find("interact", 1, true) or name:find("quest", 1, true)) then
    return nil
  end
  return Logic.OBJECT
end

-- Whether the settings allow a category: the fallback object counts as ore or herbs.
function Logic.CategoryOn(category, cfg)
  if category == Logic.OBJECT then
    return cfg.ore == true or cfg.herbs == true
  end
  return cfg[category] == true
end

-- The profession a tooltip line asks for: "Requires Mining (150)", "Benötigt Kräuterkunde" or a line
-- with the profession alone. The first line is the name of the object and never counts.
local PROFESSIONS = {
  { "mining", "ore" },
  { "bergbau", "ore" },
  { "herbalism", "herbs" },
  { "kräuterkunde", "herbs" },
  { "kraeuterkunde", "herbs" },
}
local REQUIRES = { "requires", "benötigt", "erfordert" }

local function hasAny(text, words)
  for _, word in ipairs(words) do
    if text:find(word, 1, true) then
      return true
    end
  end
  return false
end

function Logic.ClassifyTooltip(lines)
  for i = 2, #(lines or {}) do
    local line = lines[i]
    if type(line) == "string" then
      local text = line:lower()
      local bare = text:gsub("%(%d+%)", ""):gsub("^%s+", ""):gsub("%s+$", "")
      for _, entry in ipairs(PROFESSIONS) do
        if text:find(entry[1], 1, true) and (bare == entry[1] or hasAny(text, REQUIRES)) then
          return entry[2]
        end
      end
    end
  end
end

-- Quest objects ------------------------------------------------------------------------------------

Logic.QUEST_TEXT_MIN = 4
-- A quest text shorter than this only counts one way (the name must contain it, not the other way round).
Logic.QUEST_TEXT_CONTAINED_MIN = 5

-- A quest objective or an object name in one comparable form: lower case, no non-breaking space, a plain
-- apostrophe, no progress counter ("0/6"), no leading or trailing spaces, colons and hyphens. lower() works
-- per byte, so an umlaut stays as it is; both sides use this same function, which is all that is needed.
-- nil for anything that is no text or shorter than QUEST_TEXT_MIN.
function Logic.NormalizeQuestText(text)
  if type(text) ~= "string" then
    return nil
  end
  text = text:lower():gsub("\194\160", " "):gsub("\226\128\153", "'"):gsub("%d+%s*/%s*%d+", " ")
  text = text:gsub("%s+", " "):gsub("^[%s:%-]+", ""):gsub("[%s:%-]+$", "")
  if #text < Logic.QUEST_TEXT_MIN then
    return nil
  end
  return text
end

-- The comparable texts of a list of raw objective texts (unusable entries dropped).
function Logic.QuestTexts(raw)
  local out = {}
  for _, text in ipairs(raw or {}) do
    local normalized = Logic.NormalizeQuestText(text)
    if normalized then
      out[#out + 1] = normalized
    end
  end
  return out
end

-- Whether the object name fits an open objective (texts = Logic.QuestTexts): the objective contains the
-- name, or (objective of at least QUEST_TEXT_CONTAINED_MIN characters) the name contains the objective.
-- The second result is the name in comparable form (nil when unusable).
function Logic.MatchesQuestText(name, texts)
  local needle = Logic.NormalizeQuestText(name)
  if not needle then
    return false, nil
  end
  for _, text in ipairs(texts or {}) do
    if text:find(needle, 1, true) or (#text >= Logic.QUEST_TEXT_CONTAINED_MIN and needle:find(text, 1, true)) then
      return true, needle
    end
  end
  return false, needle
end

-- Which check makes an object a quest object, in this order: the client relates it to an active quest,
-- its tooltip has a quest objective line, its name fits an open objective. Only true counts (nil = unknown).
function Logic.QuestSource(related, tooltipLine, nameMatch)
  if related == true then
    return "related"
  elseif tooltipLine == true then
    return "tooltip"
  elseif nameMatch == true then
    return "name"
  end
  return nil
end

-- State machine -----------------------------------------------------------------------------------

-- The state to show: nil without target, "far" out of reach, "locked" in reach with too low a skill,
-- else "ready". inRange nil (the client cannot tell) counts as in reach.
function Logic.WantedState(inRange, locked)
  if inRange == false then
    return "far"
  end
  return locked and "locked" or "ready"
end

-- Whether a target gets an effect at all: a locked object (skill too low or profession missing) only
-- when the player asked for it (lockedNodes).
function Logic.ShowsTarget(locked, lockedNodes)
  return not locked or lockedNodes == true
end

function Logic.NewState()
  return { shown = nil, from = nil, mix = 1, alpha = 0, cand = nil, held = 0 }
end

local function approach(value, target, step)
  if value < target then
    return math.min(target, value + step)
  end
  return math.max(target, value - step)
end

-- One step of dt seconds towards the wanted state (nil = nothing to show). A change of state waits
-- for its hold time, so a flickering target does not flip the color. Without anything visible the
-- first state shows at once. instant skips every fade (reduced motion).
function Logic.Update(s, want, dt, instant)
  if want ~= nil and want ~= s.shown then
    if s.shown == nil or s.alpha <= 0 then
      s.from, s.shown, s.mix, s.cand, s.held = want, want, 1, nil, 0
    elseif want ~= s.cand then
      s.cand, s.held = want, 0
    else
      s.held = s.held + dt
      if s.held >= Logic.HOLD[want] then
        s.from, s.shown, s.mix, s.cand, s.held = s.shown, want, 0, nil, 0
        -- Back to ready: the caller restarts all sparks together, a short burst as feedback.
        s.burst = want == "ready"
      end
    end
  elseif want == s.shown or want == nil then
    s.cand, s.held = nil, 0
  end
  if instant then
    s.mix, s.alpha = 1, want and 1 or 0
    return
  end
  s.mix = math.min(1, s.mix + dt / Logic.FADE_MIX)
  if want then
    s.alpha = approach(s.alpha, 1, dt / Logic.FADE_IN)
  else
    s.alpha = approach(s.alpha, 0, dt / Logic.FADE_OUT)
  end
end

-- Color and brightness of the moment (cross fade of the last two states, times the fade in). The
-- brightness never falls below MIN_ALPHA before the fade in.
function Logic.Look(s)
  local cur = LOOKS[s.shown]
  if not cur then
    return 1, 1, 1, 0
  end
  local prev = LOOKS[s.from] or cur
  local m = s.mix
  local alpha = math.max(Logic.MIN_ALPHA, prev.a + (cur.a - prev.a) * m)
  return prev.r + (cur.r - prev.r) * m, prev.g + (cur.g - prev.g) * m, prev.b + (cur.b - prev.b) * m, alpha * s.alpha
end

-- The dark color of the layer behind the glow, cross faded like Look.
function Logic.DarkLook(s)
  local cur = LOOKS[s.shown]
  if not cur then
    return 0, 0, 0
  end
  local prev = LOOKS[s.from] or cur
  local m = s.mix
  return prev.dr + (cur.dr - prev.dr) * m, prev.dg + (cur.dg - prev.dg) * m, prev.db + (cur.db - prev.db) * m
end

-- 0 to 1 wave of the glow pulse at the time t in seconds; nil gives the middle (reduced motion).
function Logic.Pulse(t)
  if t == nil then
    return 0.5
  end
  return 0.5 + 0.5 * math.sin(t / Logic.GLOW_PERIOD * 2 * math.pi)
end

-- Alpha of the additive glow: the pulse range times the brightness a of the state.
function Logic.GlowAlpha(a, t)
  return (Logic.GLOW_ALPHA_MIN + (Logic.GLOW_ALPHA_MAX - Logic.GLOW_ALPHA_MIN) * Logic.Pulse(t)) * a
end

-- Alpha of the dark layer behind the glow.
function Logic.DarkAlpha(a)
  return Logic.DARK_ALPHA * a
end

-- Style ----------------------------------------------------------------------------------------------

function Logic.CleanStyle(value)
  for _, style in ipairs(Logic.STYLES) do
    if value == style then
      return style
    end
  end
  return "auto"
end

-- True when the choice needs the original model (so its probe is worth the frame).
function Logic.WantsModel(choice)
  choice = Logic.CleanStyle(choice)
  return choice == "original" or (choice == "auto" and Logic.AUTO_PREFERS_MODEL)
end

-- A model counts as loaded when SetModel raised nothing and, where the client can tell, it names the
-- file afterwards.
function Logic.ModelLoaded(setOk, hasGetter, fileId)
  return setOk == true and (not hasGetter or fileId ~= nil)
end

-- The style to draw: "original" or "particles". Automatic means particles while AUTO_PREFERS_MODEL is off.
-- The second result is true when the player asked for the original model and it did not load (one chat line).
function Logic.ResolveStyle(choice, modelLoaded)
  choice = Logic.CleanStyle(choice)
  if not Logic.WantsModel(choice) then
    return "particles", false
  end
  if modelLoaded then
    return "original", false
  end
  return "particles", choice == "original"
end

-- Console variables ---------------------------------------------------------------------------------

-- The quest item glitter of the client hangs on this variable while the outline mode is off.
Logic.QUEST_ITEM_CVARS = {
  { "outlineModeShowLootEffectWhenDisabled", "1" },
  { "graphicsOutlineMode", "0" },
  { "OutlineEngineMode", "0" },
  { "raidGraphicsOutlineMode", "0" },
  { "RAIDOutlineEngineMode", "0" },
}

-- Soft targeting reaches objects up to the game maximum or the lower setting. The range entry is a
-- placeholder, Desired takes the effective range.
Logic.TARGET_CVARS = {
  { "SoftTargetInteract", "3" },
  { "SoftTargetInteractRange", tostring(Logic.RANGE_GAME_MAX) },
  { "SoftTargetInteractArc", "2" },
  { "SoftTargetInteractOnlyInRange", "0" },
  { "SoftTargetIconInteract", "1" },
  { "SoftTargetIconGameObject", "1" },
  { "SoftTargetLowPriorityIcons", "1" },
}
Logic.NAMEPLATE_CVAR = "SoftTargetNameplateInteract"
Logic.RANGE_CVAR = "SoftTargetInteractRange"
-- Earlier versions saved the original of this variable; ApplyLegacy puts it back once.
Logic.LEGACY_CVAR = "SoftTargetInteractRangeIsHard"
-- The icons over objects are drawn by the game, not by the effect. They are part of TARGET_CVARS and
-- go to "0" when the player does not want them (gameIcons off).
Logic.ICON_CVARS = { "SoftTargetIconInteract", "SoftTargetIconGameObject" }

-- Variables whose change by the client (graphics presets) makes us apply the set again, lower case.
local WATCHED = {
  graphicsquality = true,
  raidgraphicsquality = true,
  graphicsoutlinemode = true,
  outlineenginemode = true,
  raidgraphicsoutlinemode = true,
  raidoutlineenginemode = true,
  outlinemodeshowlooteffectwhendisabled = true,
}

function Logic.IsWatched(name)
  return type(name) == "string" and WATCHED[name:lower()] == true
end

-- Every variable we may touch, in a fixed order.
function Logic.ManagedNames()
  local out = {}
  for _, list in ipairs({ Logic.QUEST_ITEM_CVARS, Logic.TARGET_CVARS }) do
    for _, entry in ipairs(list) do
      out[#out + 1] = entry[1]
    end
  end
  out[#out + 1] = Logic.NAMEPLATE_CVAR
  return out
end

-- The values that should be set now. opts: enabled, questItems, ore, herbs, quest, gameIcons (the
-- settings, gameIcons only counts as off when it is false), range (the setting), sparkling (an object sparkles right now). Soft targeting is only changed while a
-- category is on, the name plate of the soft target only while an object sparkles. An empty result means: restore all.
function Logic.Desired(opts)
  local out = {}
  if not opts.enabled then
    return out
  end
  if opts.questItems then
    for _, entry in ipairs(Logic.QUEST_ITEM_CVARS) do
      out[entry[1]] = entry[2]
    end
  end
  if opts.ore or opts.herbs or opts.quest then
    for _, entry in ipairs(Logic.TARGET_CVARS) do
      out[entry[1]] = entry[2]
    end
    out[Logic.RANGE_CVAR] = tostring(Logic.EffectiveRange(opts.range))
    if opts.gameIcons == false then
      for _, name in ipairs(Logic.ICON_CVARS) do
        out[name] = "0"
      end
    end
    -- Names only for the object the player wants to see; open when the client hides the target.
    out[Logic.NAMEPLATE_CVAR] = opts.sparkling and "1" or "0"
  end
  return out
end

-- Console variable values are strings, a client may write 60 as "60.000000": numbers compare as numbers.
function Logic.SameValue(a, b)
  if a == b then
    return true
  end
  local x, y = tonumber(a), tonumber(b)
  return x ~= nil and x == y
end

-- What to do to get from the current values to the desired ones. saved = the original values kept so far
-- ({ [name] = value }), current = what the client says now (nil = the client has no such variable, left
-- alone), desired = Logic.Desired. Returns
--   remember { [name] = original }  keep before the first change,
--   set      { [name] = value }     to write,
--   restore  { [name] = original }  to write back, forget the original after it worked,
--   forget   { name, ... }          originals that are in place already.
function Logic.PlanCVars(saved, current, desired)
  local plan = { remember = {}, set = {}, restore = {}, forget = {} }
  for name, value in pairs(desired) do
    local now = current[name]
    if now ~= nil then
      if saved[name] == nil then
        plan.remember[name] = now
      end
      if not Logic.SameValue(now, value) then
        plan.set[name] = value
      end
    end
  end
  for name, original in pairs(saved) do
    if desired[name] == nil then
      local now = current[name]
      if now == nil or Logic.SameValue(now, original) then
        plan.forget[#plan.forget + 1] = name
      else
        plan.restore[name] = original
      end
    end
  end
  return plan
end

-- Earlier versions switched Logic.LEGACY_CVAR and kept its original in saved. The value to write back
-- once, nil when there is nothing to write (no saved value, the client has no such variable or it is
-- in place). The caller forgets the saved entry in every case.
function Logic.LegacyRestore(saved, now)
  local original = saved[Logic.LEGACY_CVAR]
  if original == nil or now == nil or Logic.SameValue(now, original) then
    return nil
  end
  return original
end

-- Particles -----------------------------------------------------------------------------------------

-- Gives a particle a new place, size and timing; a negative age is a short wait before it appears.
function Logic.Respawn(p, rnd, wait)
  local angle = rnd() * 2 * math.pi
  local radius = Logic.RADIUS * math.sqrt(rnd())
  p.x, p.y = math.cos(angle) * radius, math.sin(angle) * radius
  p.size = Logic.STAR_SIZE_MIN + (Logic.STAR_SIZE_MAX - Logic.STAR_SIZE_MIN) * rnd()
  p.fin, p.hold, p.fout = 0.1 + rnd() * 0.15, 0.05 + rnd() * 0.15, 0.2 + rnd() * 0.3
  p.age = wait and -rnd() * wait or 0
end

-- Advances a particle by dt; true when it got a new place (the caller moves its texture).
function Logic.StepParticle(p, dt, rnd)
  p.age = p.age + dt
  if p.age >= p.fin + p.hold + p.fout then
    Logic.Respawn(p, rnd, 0.4)
    return true
  end
  return false
end

-- 0 to 1: fade in, hold, fade out.
function Logic.Envelope(p)
  local age = p.age
  if age <= 0 then
    return 0
  elseif age < p.fin then
    return age / p.fin
  elseif age < p.fin + p.hold then
    return 1
  end
  return math.max(0, 1 - (age - p.fin - p.hold) / p.fout)
end

-- Fixed place and brightness of particle i of n without motion (reduced motion).
function Logic.StaticSpot(i, n)
  local angle = (i - 1) / n * 2 * math.pi
  local radius = Logic.RADIUS * (i % 2 == 0 and 0.75 or 0.45)
  return math.cos(angle) * radius, math.sin(angle) * radius, 0.75
end

-- Support report ------------------------------------------------------------------------------------

-- One value as short text: nil stays "nil", booleans use the words of the language, anything the
-- report cannot print (a table, a secret that slipped through) becomes "?".
local function show(value, words)
  local kind = type(value)
  if value == nil then
    return "nil"
  elseif kind == "boolean" then
    return value and words.yes or words.no
  elseif kind == "number" then
    return (string.format("%.2f", value):gsub("%.?0+$", ""))
  elseif kind == "string" then
    return #value > 60 and value:sub(1, 57) .. "..." or value
  end
  return "?"
end
Logic.ShowValue = show

-- Measuring the detection range ----------------------------------------------------------------------
-- The client gives no distance to world objects, but the own position is readable. The place where the
-- soft target first shows up and the place where the player reaches the object are the detection
-- distance, minus the interaction range of the object (the player stops that far in front of it). The
-- start is as exact as the poll (Logic.WATCH): at running speed that is below a yard, mounted a few.

Logic.IsNumber = isNumber
-- A distance above the cap counts as the cap, one above the reject limit is no measurement at all.
Logic.MEASURE_CAP = 200
Logic.MEASURE_REJECT = 300

-- Yards between two positions { x, y, z }, flat when one of them has no height. nil for anything else.
function Logic.Distance(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return nil
  end
  if not (isNumber(a.x) and isNumber(a.y) and isNumber(b.x) and isNumber(b.y)) then
    return nil
  end
  local dz = (isNumber(a.z) and isNumber(b.z)) and a.z - b.z or 0
  return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + dz ^ 2)
end

-- Two positions belong together when they come from the same source and the same map or instance.
function Logic.SamePlace(a, b)
  return type(a) == "table" and type(b) == "table" and a.source == b.source and a.map == b.map
end

-- The distance walked between the start and the end, nil when the places differ or a position is bad.
function Logic.NewSample(startPos, endPos)
  if not Logic.SamePlace(startPos, endPos) then
    return nil
  end
  return Logic.Distance(startPos, endPos)
end

-- Whole yards for display.
function Logic.RoundYards(value)
  return math.floor(value + 0.5)
end

-- The counters of the stored measurement as { n, min, max, avg, last, at }, nil without a usable one.
function Logic.MeasureSummary(stats)
  if type(stats) ~= "table" or not (isNumber(stats.n) and stats.n >= 1) then
    return nil
  end
  if not (isNumber(stats.min) and isNumber(stats.max) and isNumber(stats.sum) and isNumber(stats.last)) then
    return nil
  end
  return {
    n = stats.n,
    min = stats.min,
    max = stats.max,
    avg = stats.sum / stats.n,
    last = stats.last,
    at = stats.at,
  }
end

-- Adds one measurement to the counters { n, min, max, sum, last, at } (no list of raw values) and
-- returns the value that counted, nil when it was refused.
function Logic.AddSample(stats, yards, at)
  if type(stats) ~= "table" or not isNumber(yards) or yards < 0 or yards > Logic.MEASURE_REJECT then
    return nil
  end
  yards = math.min(yards, Logic.MEASURE_CAP)
  if not Logic.MeasureSummary(stats) then
    stats.n, stats.sum, stats.min, stats.max = 0, 0, nil, nil
  end
  stats.n = stats.n + 1
  stats.sum = stats.sum + yards
  stats.min = stats.min and math.min(stats.min, yards) or yards
  stats.max = stats.max and math.max(stats.max, yards) or yards
  stats.last = yards
  stats.at = at
  return yards
end

function Logic.NewMeasure()
  return { phase = "none", start = nil, guid = nil, note = nil }
end

local function dropMeasure(m, note)
  m.phase, m.start, m.guid = "none", nil, nil
  if note then
    m.note = note
  end
end

-- One look of the poller. obs = { object = a recognized object is the soft target, guid, inRange = the
-- player reached it (nil unknown), read = function giving the own position or nil }. Phases: "none" (no
-- target), "tracking" (it showed up, the start is kept), "held" (nothing to measure for this target:
-- it was in reach already, no position, or it was measured; waits until the target is gone). Returns
-- the measured yards at the moment the object is reached, nil otherwise. m.note names the last outcome.
function Logic.SampleReady(m, obs)
  obs = obs or {}
  if not obs.object then
    dropMeasure(m, m.phase == "tracking" and "lost" or nil)
    return nil
  end
  if m.phase ~= "none" and obs.guid ~= m.guid then
    dropMeasure(m, m.phase == "tracking" and "changed" or nil)
  end
  if m.phase == "none" then
    m.guid = obs.guid
    local pos = obs.inRange ~= true and obs.read and obs.read() or nil
    if obs.inRange == true then
      m.phase, m.note = "held", "inReachAtStart"
    elseif not pos then
      m.phase, m.note = "held", "noPosition"
    else
      m.phase, m.start, m.note = "tracking", pos, "tracking"
    end
    return nil
  end
  if m.phase == "tracking" and obs.inRange == true then
    local startPos = m.start
    local pos = obs.read and obs.read() or nil
    m.phase, m.start = "held", nil
    local yards = pos and Logic.NewSample(startPos, pos)
    m.note = yards and "reached" or pos and "otherPlace" or "noPosition"
    return yards
  end
  return nil
end

-- The lines of the sparkle section of the support report from what the module read (see GatherSparkles.DiagInfo).
-- Every field may be nil. words = { yes, no }.
function Logic.DiagLines(info, words)
  info = info or {}
  local host, cursor, quest = info.host or {}, info.cursor or {}, info.questCheck or {}
  local function v(value)
    return show(value, words)
  end
  local lines = {
    string.format(
      "sparkles: on=%s style=%s->%s ore=%s herbs=%s quest=%s lockedNodes=%s",
      v(info.enabled),
      v(info.styleSetting),
      v(info.styleActual),
      v(info.ore),
      v(info.herbs),
      v(info.quest),
      v(info.lockedNodes)
    ),
    string.format(
      "sparkles soft target: exists=%s name=%s plate=%s plateSecret=%s inRange=%s",
      v(info.soft),
      v(info.name),
      v(info.plate),
      v(info.plateSecret),
      v(info.inRange)
    ),
    string.format(
      "sparkles kind: %s via %s locked=%s state=%s kept=%s",
      v(info.category),
      v(info.source),
      v(info.locked),
      v(info.state),
      v(info.kept)
    ),
    string.format(
      "sparkles quest: related=%s tooltipLine=%s nameMatch=%s texts=%s name=%s kind=%s",
      v(quest.related),
      v(quest.tooltipLine),
      v(quest.nameMatch),
      v(quest.texts),
      v(quest.name),
      v(info.category)
    ),
    string.format(
      "sparkles cursor: SetUnitCursorTexture=%s ok=%s returned=%s file=%s atlas=%s",
      v(info.cursorApi),
      v(cursor.ok),
      v(cursor.ret),
      v(cursor.file),
      v(cursor.atlas)
    ),
    string.format(
      "sparkles host: shown=%s visible=%s size=%sx%s alpha=%s strata=%s level=%s",
      v(host.shown),
      v(host.visible),
      v(host.width),
      v(host.height),
      v(host.alpha),
      v(host.strata),
      v(host.level)
    ),
    string.format(
      "sparkles anchor: point=%s onPlate=%s hostSecret=%s stars=%s of %s",
      v(host.point),
      v(host.onPlate),
      v(host.secret),
      v(host.active),
      v(host.stars)
    ),
    string.format(
      "sparkles parent: offsetY=%s parentIsPlate=%s level=%s plateLevel=%s ignoreParentAlpha=%s directWorks=%s activeUnits=%s exists=%s isGameObject=%s",
      v(info.offsetY),
      v(host.parentIsPlate),
      v(host.level),
      v(host.plateLevel),
      v(host.ignoreAlpha),
      v(info.directWorks),
      v(info.activeUnits),
      v(info.unitExists),
      v(info.unitIsGameObject)
    ),
  }
  lines[#lines + 1] = string.format(
    "sparkles reach: size=%s range=%s effective=%s SoftTargetInteractRange=%s distance=%s distSeen=%s",
    v(info.size),
    v(info.range == nil and Logic.RANGE_MAX_SETTING or info.range),
    v(info.effective),
    v(info.rangeNow),
    v(info.distance),
    info.distSeen == nil and info.distTried and words.noDistance or v(info.distSeen)
  )
  -- Distances only, never a position (the report is shared).
  local measure = info.measure or {}
  lines[#lines + 1] = string.format(
    "sparkles measure: posSource=%s n=%s last=%s min=%s max=%s avg=%s state=%s start=%s note=%s chat=%s",
    v(info.posSource or "none"),
    v(measure.n or 0),
    v(measure.last),
    v(measure.min),
    v(measure.max),
    v(measure.avg),
    v(info.measureState),
    v(info.measureStart == true),
    v(info.measureNote),
    v(info.measureChat == true)
  )
  local parts = {}
  for _, cvar in ipairs(info.cvars or {}) do
    parts[#parts + 1] = string.format("%s=%s (saved %s)", cvar.name, v(cvar.now), v(cvar.saved))
    if #parts == 2 then
      lines[#lines + 1] = "sparkles cvars: " .. table.concat(parts, ", ")
      parts = {}
    end
  end
  if #parts > 0 then
    lines[#lines + 1] = "sparkles cvars: " .. table.concat(parts, ", ")
  end
  return lines
end
