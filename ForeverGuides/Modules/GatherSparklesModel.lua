-- Gathering sparkles, the settings model (pure, no game access): one block of settings per kind of object
-- (settings.sparkles.kinds) and the general options (settings.sparkles.general), their cleaning, the
-- migration from the flat keys of the first version and the small decisions the options need (reach look,
-- professions, rare nodes, gather spells, finish effects). Extends GatherSparklesLogic.
local _, ns = ...
local Logic = ns.GatherSparklesLogic
local isNumber = Logic.IsNumber

ns.AddLocale("enUS", {
  ["sparkles.kind.herbs"] = "Herbs",
  ["sparkles.kind.ore"] = "Ore veins",
  ["sparkles.kind.chests"] = "Chests",
  ["sparkles.kind.quests"] = "Quest objects",
  ["sparkles.kind.others"] = "Other objects",
  ["sparkles.kind.bobber"] = "Fishing bobber",
  ["sparkles.kind.skinning"] = "Skinnable creatures",
  ["sparkles.finish.none"] = "None",
  ["sparkles.finish.fade"] = "Fade out",
  ["sparkles.finish.flash"] = "Flash",
  ["sparkles.finish.gatherIn"] = "Draw in",
  ["sparkles.finish.scatter"] = "Scatter",
  ["sparkles.finish.risingLight"] = "Rising light",
})
ns.AddLocale("deDE", {
  ["sparkles.kind.herbs"] = "Kräuter",
  ["sparkles.kind.ore"] = "Erzvorkommen",
  ["sparkles.kind.chests"] = "Truhen",
  ["sparkles.kind.quests"] = "Questobjekte",
  ["sparkles.kind.others"] = "Sonstige Objekte",
  ["sparkles.kind.bobber"] = "Angelschwimmer",
  ["sparkles.kind.skinning"] = "Kürschnerbare Tiere",
  ["sparkles.finish.none"] = "Keiner",
  ["sparkles.finish.fade"] = "Ausblenden",
  ["sparkles.finish.flash"] = "Aufblitzen",
  ["sparkles.finish.gatherIn"] = "Einsaugen",
  ["sparkles.finish.scatter"] = "Zerstreuen",
  ["sparkles.finish.risingLight"] = "Aufsteigendes Licht",
})

-- Number of the model in settings.sparkles.model; the migration runs while it differs. 1 added the kinds (carried
-- over from the flat keys), 2 renamed area to spread and moved the default color from gold to amber white.
Logic.MODEL_VERSION = 2

-- Spread and number of the sprites of a style: count is the number of sprites, spread the spread in percent of
-- the radius of the style.
Logic.COUNT_MIN, Logic.COUNT_MAX, Logic.COUNT_DEFAULT = 1, 24, Logic.PARTICLES
Logic.SPREAD_MIN, Logic.SPREAD_MAX, Logic.SPREAD_DEFAULT = 30, 200, 100
Logic.BRIGHTNESS_MIN, Logic.BRIGHTNESS_MAX = 0, 100

-- The kinds in the order of the settings. category: what the detection calls it (Logic.Classify), legacy: the
-- flat key of the first version, on: the default. auto: the style "automatic" draws for the kind (chests keep
-- the twinkle until the coin sheet is confirmed in the game). styles: the styles allowed for the kind (nil =
-- all); the catalog limits a style to kinds with its own allowed list.
Logic.KINDS = {
  { key = "herbs", label = "sparkles.kind.herbs", category = "herbs", legacy = "herbs", on = true, auto = "twinkle" },
  { key = "ore", label = "sparkles.kind.ore", category = "ore", legacy = "ore", on = true, auto = "emberspark" },
  { key = "chests", label = "sparkles.kind.chests", category = "chests", on = true, auto = "twinkle" },
  { key = "quests", label = "sparkles.kind.quests", category = "quest", legacy = "quest", on = false, auto = "beacon" },
  { key = "others", label = "sparkles.kind.others", category = "others", on = false, auto = "glowmark" },
  { key = "bobber", label = "sparkles.kind.bobber", category = "bobber", on = false, auto = "glowmark" },
  { key = "skinning", label = "sparkles.kind.skinning", category = "skinning", on = false, auto = "wisp" },
}

local KIND, CATEGORY_KEY, LEGACY_ON = {}, {}, {}
for _, entry in ipairs(Logic.KINDS) do
  KIND[entry.key] = entry
  CATEGORY_KEY[entry.category] = entry.key
  if entry.legacy then
    LEGACY_ON[entry.legacy] = entry.key
  end
end

-- The settings key of a detected category ("quest" is "quests"); the fallback category "object" stays as it is.
function Logic.KindKey(category)
  return CATEGORY_KEY[category] or category
end

-- The kind that shows a detected category, nil when its switch is off. kinds = { [key] = { on } } (cleaned
-- settings). The fallback category "object" (a gatherable object the client names oddly) counts as herbs or
-- ore, and as "others" when those are off.
function Logic.KindOf(category, kinds)
  local function on(key)
    return type(kinds) == "table" and type(kinds[key]) == "table" and kinds[key].on == true
  end
  if category == Logic.OBJECT then
    for _, key in ipairs({ "herbs", "ore", "others" }) do
      if on(key) then
        return key
      end
    end
    return nil
  end
  local key = CATEGORY_KEY[category]
  return key and on(key) and key or nil
end

local function boolOr(value, default)
  if type(value) == "boolean" then
    return value
  end
  return default
end

local function whole(value, default, min, max)
  if not isNumber(value) then
    return default
  end
  return math.min(max, math.max(min, math.floor(value + 0.5)))
end

local function channel(value, default)
  if isNumber(value) and value >= 0 and value <= 1 then
    return value
  end
  return default
end

-- Whether a style is allowed for a kind: the catalog entry lists its kinds (none = every kind) and the kind may
-- restrict its styles as well. "auto" and "original" are allowed everywhere.
function Logic.KindAllows(kindKey, style)
  local function listed(list)
    for _, key in ipairs(list) do
      if key == kindKey then
        return true
      end
    end
    return false
  end
  local entry = KIND[kindKey]
  local byStyle = Logic.StyleAllowed(style)
  if byStyle and not listed(byStyle) then
    return false
  end
  if entry and entry.styles then
    for _, allowed in ipairs(entry.styles) do
      if allowed == style then
        return true
      end
    end
    return false
  end
  return true
end

-- The style "automatic" draws for a kind: the default of the kind, the particles for an unknown kind.
function Logic.AutoStyle(kindKey)
  local entry = KIND[kindKey]
  return entry and entry.auto or "particles"
end

-- The style of a kind: the one asked for (an old key counts as its replacement) when the catalog knows it and the kind allows it, else "auto".
function Logic.KindStyle(kindKey, style)
  style = Logic.CanonicalStyle(style)
  for _, key in ipairs(Logic.STYLES) do
    if key == style then
      return Logic.KindAllows(kindKey, style) and style or "auto"
    end
  end
  return "auto"
end

-- The styles a kind offers in its dropdown, in catalog order: "auto" first, then every shown style the kind allows.
-- { value = style key, key = locale key of its name }. An unknown kind gets the whole catalog.
function Logic.StyleChoices(kindKey)
  local out = {}
  for _, entry in ipairs(Logic.STYLE_CATALOG) do
    if entry.key == "auto" or (not entry.hidden and Logic.KindAllows(kindKey, entry.key)) then
      out[#out + 1] = { value = entry.key, key = entry.label }
    end
  end
  return out
end

-- The cleaned settings of a kind from what is saved (any value, also nil): { on, style, color = { r, g, b },
-- size, height, count, spread }. nil for a kind that does not exist.
function Logic.KindSettings(kindKey, saved)
  local entry = KIND[kindKey]
  if not entry then
    return nil
  end
  saved = type(saved) == "table" and saved or {}
  local color = type(saved.color) == "table" and saved.color or {}
  local gold = Logic.LOOKS.ready
  return {
    on = boolOr(saved.on, entry.on),
    style = Logic.KindStyle(kindKey, saved.style),
    color = { r = channel(color.r, gold.r), g = channel(color.g, gold.g), b = channel(color.b, gold.b) },
    size = Logic.CleanSize(saved.size),
    height = Logic.CleanOffset(saved.height),
    count = whole(saved.count, Logic.COUNT_DEFAULT, Logic.COUNT_MIN, Logic.COUNT_MAX),
    spread = whole(
      saved.spread ~= nil and saved.spread or saved.area,
      Logic.SPREAD_DEFAULT,
      Logic.SPREAD_MIN,
      Logic.SPREAD_MAX
    ),
  }
end

-- General options -----------------------------------------------------------------------------------------

-- What happens when a gather completes, in the order of the settings.
Logic.FINISHES = { "none", "fade", "flash", "gatherIn", "scatter", "risingLight" }
Logic.FINISH_DEFAULT = "fade"

-- The options stored in settings.sparkles.general with their defaults. instanceHide is off because the module
-- never hid anything in instances before.
Logic.GENERAL_DEFAULTS = {
  brightness = 100,
  reachLook = true,
  combatHide = true,
  instanceHide = false,
  myProfessionsOnly = false,
  rareGlow = false,
  sound = false,
  gatherDim = true,
  finish = Logic.FINISH_DEFAULT,
}
-- Options that keep their flat key of the first version as the source: general name = flat key.
Logic.GENERAL_FLAT = { reachFlash = "reachFlash", grayTooHard = "lockedNodes", gameIcons = "gameIcons" }
local FLAT_DEFAULTS = { reachFlash = true, grayTooHard = false, gameIcons = true }

function Logic.CleanFinish(value)
  for _, key in ipairs(Logic.FINISHES) do
    if key == value then
      return key
    end
  end
  return Logic.FINISH_DEFAULT
end

local function cleanStored(saved)
  local defaults = Logic.GENERAL_DEFAULTS
  saved = type(saved) == "table" and saved or {}
  local out = {}
  for key, default in pairs(defaults) do
    if type(default) == "boolean" then
      out[key] = boolOr(saved[key], default)
    end
  end
  out.brightness = whole(saved.brightness, defaults.brightness, Logic.BRIGHTNESS_MIN, Logic.BRIGHTNESS_MAX)
  out.finish = Logic.CleanFinish(saved.finish)
  return out
end

-- The cleaned general options. saved is settings.sparkles.general, flat is settings.sparkles (the source of
-- reachFlash, grayTooHard = lockedNodes and gameIcons).
function Logic.General(saved, flat)
  local out = cleanStored(saved)
  flat = type(flat) == "table" and flat or {}
  for key, flatKey in pairs(Logic.GENERAL_FLAT) do
    out[key] = boolOr(flat[flatKey], FLAT_DEFAULTS[key])
  end
  return out
end

-- Migration and cleaning ----------------------------------------------------------------------------------

local function kindsOf(s)
  if type(s.kinds) ~= "table" then
    s.kinds = {}
  end
  return s.kinds
end

-- Every kind and the general options cleaned in place (a hand edited file cannot hold a value out of range).
-- Keys of other versions stay.
function Logic.Validate(s)
  if type(s) ~= "table" then
    return s
  end
  local kinds = kindsOf(s)
  for _, entry in ipairs(Logic.KINDS) do
    kinds[entry.key] = Logic.KindSettings(entry.key, kinds[entry.key])
  end
  s.general = cleanStored(s.general)
  return s
end

-- The sprite count a style asks for (its catalog entry), the default for styles without sprites.
function Logic.StyleCount(style)
  local spec = Logic.StyleSpec(style)
  return spec and spec.count or Logic.COUNT_DEFAULT
end

-- A flat key of the first version changed (the old controls, the setup assistant and the dev tools still write
-- them): carries it into the model. ore, herbs and quest switch their kind, style, offsetY and size go to every
-- kind. true when the key belongs to the model. s.kinds is not cleaned here, Logic.KindSettings does that on use.
function Logic.SyncLegacy(s, key)
  if type(s) ~= "table" then
    return false
  end
  local kinds = kindsOf(s)
  local function kind(entry)
    if type(kinds[entry.key]) ~= "table" then
      kinds[entry.key] = {}
    end
    return kinds[entry.key]
  end
  if LEGACY_ON[key] then
    kind(KIND[LEGACY_ON[key]]).on = s[key] == true
    return true
  end
  if key == "style" then
    for _, entry in ipairs(Logic.KINDS) do
      local k = kind(entry)
      k.style = Logic.KindStyle(entry.key, s.style)
      k.count = Logic.StyleCount(k.style)
    end
    return true
  elseif key == "offsetY" or key == "size" then
    for _, entry in ipairs(Logic.KINDS) do
      kind(entry)[key == "offsetY" and "height" or "size"] = s[key]
    end
    return true
  end
  return false
end

-- The value the model holds for a flat key of the first version (nil for a key that is no part of it). The old
-- controls read through this, so they show the model and not a stale copy; style, offsetY and size are shared by
-- all kinds, the first kind (herbs) stands for them.
local LEGACY_FIELD = { style = "style", offsetY = "height", size = "size" }

function Logic.LegacyValue(s, key)
  if type(s) ~= "table" then
    return nil
  end
  local kinds = type(s.kinds) == "table" and s.kinds or {}
  if LEGACY_ON[key] then
    return Logic.KindSettings(LEGACY_ON[key], kinds[LEGACY_ON[key]]).on
  elseif LEGACY_FIELD[key] then
    return Logic.KindSettings(Logic.KINDS[1].key, kinds[Logic.KINDS[1].key])[LEGACY_FIELD[key]]
  end
end

-- The gold every kind stored as its color before the default became amber white: a kind still holding exactly
-- that never chose it and takes the new default.
local function isOldGold(color)
  return type(color) == "table" and color.r == 1 and color.g == 0.88 and color.b == 0.52
end

-- Once per database: the flat keys of the first version become the model. A value the model already holds
-- stays, the flat keys are never touched (a downgrade still finds them). The three old switches all off mean
-- the player wanted no highlight, so the new chests kind starts off for that player too.
function Logic.Migrate(s)
  if type(s) ~= "table" then
    return s
  end
  if s.model ~= Logic.MODEL_VERSION then
    local kinds = kindsOf(s)
    for _, entry in ipairs(Logic.KINDS) do
      local k = type(kinds[entry.key]) == "table" and kinds[entry.key] or {}
      kinds[entry.key] = k
      if k.spread == nil and k.area ~= nil then
        k.spread = k.area
      end
      k.area = nil
      if isOldGold(k.color) then
        k.color = nil
      end
      if entry.legacy and k.on == nil and type(s[entry.legacy]) == "boolean" then
        k.on = s[entry.legacy]
      end
      if k.style == nil and s.style ~= nil then
        k.style = Logic.KindStyle(entry.key, s.style)
        k.count = k.count == nil and Logic.StyleCount(k.style) or k.count
      end
      if k.height == nil and s.offsetY ~= nil then
        k.height = s.offsetY
      end
      if k.size == nil and s.size ~= nil then
        k.size = s.size
      end
    end
    if s.ore == false and s.herbs == false and s.quest == false and kinds.chests.on == nil then
      kinds.chests.on = false
    end
    s.model = Logic.MODEL_VERSION
  end
  -- The original model has no gallery tile (and no preview) any more: a kind still on it takes the particles,
  -- which is what the effect drew when the model did not load.
  for _, k in pairs(kindsOf(s)) do
    if type(k) == "table" and k.style == "original" then
      k.style = "particles"
    end
  end
  return Logic.Validate(s)
end

-- Reach look, flash and sound -----------------------------------------------------------------------------

-- The state to show: without the reach look "far" is shown as "ready" (nothing dims out of reach).
function Logic.ReachState(wanted, reachLook)
  if wanted == "far" and reachLook == false then
    return "ready"
  end
  return wanted
end

-- true when the target just came into reach (it was out of reach at the last look, in reach now).
function Logic.ReachEntered(before, now)
  return before == false and now == true
end

-- Professions ---------------------------------------------------------------------------------------------

-- The profession a kind needs: the skill line ids of the client and the names (lower case, both languages)
-- as the fallback. Skinnable creatures need Skinning, ore Mining, herbs Herbalism.
Logic.KIND_PROFESSIONS = {
  herbs = { ids = { 182 }, names = { "herbalism", "kräuterkunde" } },
  ore = { ids = { 186 }, names = { "mining", "bergbau" } },
  skinning = { ids = { 393 }, names = { "skinning", "kürschnerei" } },
}

-- Which of the three the player has, from rows { name, id } of the profession list (id = skill line id).
function Logic.ProfessionsFrom(rows)
  local have = { herbs = false, ore = false, skinning = false }
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    if type(row) == "table" then
      local name = type(row.name) == "string" and row.name:lower() or nil
      for key, need in pairs(Logic.KIND_PROFESSIONS) do
        for _, id in ipairs(need.ids) do
          have[key] = have[key] or row.id == id
        end
        for _, text in ipairs(need.names) do
          have[key] = have[key] or name == text
        end
      end
    end
  end
  return have
end

-- Whether a kind may show under "only my professions". have = Logic.ProfessionsFrom, nil when the client could
-- not tell (then everything shows). Kinds without a profession always show.
function Logic.ProfessionAllows(kindKey, onlyMine, have)
  if onlyMine ~= true or type(have) ~= "table" or not Logic.KIND_PROFESSIONS[kindKey] then
    return true
  end
  return have[kindKey] == true
end

-- Rare nodes ----------------------------------------------------------------------------------------------

-- Names of rare gathering nodes (lower case, any language). Empty until data names them: extend via data.
Logic.RARE_NAMES = {}

function Logic.IsRare(name)
  return type(name) == "string" and Logic.RARE_NAMES[name:lower()] == true
end

-- Gather spells ---------------------------------------------------------------------------------------------

-- The gathering spells of the player: base spell ids (Herb Gathering, Mining, Skinning) and, as fallback for
-- the spells of the expansions, their names in lower case in both languages. Extend via data.
Logic.GATHER_SPELL_IDS = { [2366] = true, [2575] = true, [8613] = true }
Logic.GATHER_SPELL_NAMES = {
  ["herb gathering"] = true,
  ["mining"] = true,
  ["skinning"] = true,
  ["kräutersammeln"] = true,
  ["bergbau"] = true,
  ["kürschnerei"] = true,
}

function Logic.IsGatherSpell(spellId, name)
  if isNumber(spellId) and Logic.GATHER_SPELL_IDS[spellId] then
    return true
  end
  return type(name) == "string" and Logic.GATHER_SPELL_NAMES[name:lower()] == true
end

-- How much of the effect stays while the player gathers (brightness factor) and how fast it follows (seconds).
Logic.GATHER_DIM = 0.35
Logic.GATHER_DIM_TIME = 0.2

-- Finish effects -------------------------------------------------------------------------------------------

-- The short effect when a gather completes. Kinds with parts draw count textures (file data ids of the game:
-- 131011 starburst, 131010 star, 984391 node sparkle); the effect itself fades out in every kind but "none".
Logic.FINISH_TIME = 0.5
Logic.FINISH_PARTS = {
  flash = { texture = 131011, count = 1, size = 130 },
  gatherIn = { texture = 131010, count = 6, size = 26 },
  scatter = { texture = 131010, count = 6, size = 26 },
  risingLight = { texture = 984391, count = 3, size = 36 },
}

local function finishProgress(age)
  if not isNumber(age) or age < 0 or age >= Logic.FINISH_TIME then
    return nil
  end
  return age / Logic.FINISH_TIME
end

-- Brightness factor of the running effect at the age in seconds: 1 without a finish, falling to 0 otherwise.
function Logic.FinishFade(kind, age)
  local p = finishProgress(age)
  if kind == "none" or kind == nil then
    return 1
  end
  return p and 1 - p or 0
end

-- Part i of the finish: x, y (pixels from the center), alpha and size in pixels at 100 percent. nil when the
-- finish has no such part or is over. reduce keeps the parts at one place (they only fade).
function Logic.FinishPart(kind, age, i, reduce)
  local spec = Logic.FINISH_PARTS[kind]
  local p = finishProgress(age)
  if not spec or not p or i < 1 or i > spec.count then
    return nil
  end
  local moved = reduce and 0.5 or p
  local alpha = 1 - p
  if kind == "flash" then
    return 0, 0, alpha, spec.size * (reduce and 1 or 0.6 + 0.8 * p)
  end
  local angle = (i - 1) / spec.count * 2 * math.pi
  if kind == "gatherIn" then
    local radius = Logic.RADIUS * (1 - moved)
    return math.cos(angle) * radius, math.sin(angle) * radius, alpha, spec.size
  elseif kind == "scatter" then
    local radius = Logic.RADIUS * 1.2 * moved
    return math.cos(angle) * radius, math.sin(angle) * radius, alpha, spec.size
  end
  return (i - 2) * 14, 70 * moved, alpha, spec.size
end

-- Gather dim ---------------------------------------------------------------------------------------------------

-- The dim mix (0 = none, 1 = fully dimmed) one step of dt seconds closer to its goal; reduce jumps at once.
function Logic.DimStep(mix, dimmed, dt, reduce)
  local goal = dimmed and 1 or 0
  if reduce then
    return goal
  end
  local step = dt / Logic.GATHER_DIM_TIME
  if mix < goal then
    return math.min(goal, mix + step)
  end
  return math.max(goal, mix - step)
end

-- Brightness factor of the effect for a dim mix.
function Logic.GatherFactor(mix)
  return 1 - (1 - Logic.GATHER_DIM) * mix
end

-- Rare glow: size of the second soft glow in pixels at 100 percent and its color (a pale blue next to the gold).
Logic.RARE_SIZE = 150
Logic.RARE_COLOR = { r = 0.55, g = 0.8, b = 1 }
