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
-- (it keeps the effect readable on bright ground, where additive light vanishes). Warm amber white when ready,
-- dimmed when too far, gray when the skill is too low. No state is fainter than MIN_ALPHA once faded in.
Logic.MIN_ALPHA = 0.5
local LOOKS = {
  ready = { r = 1, g = 0.93, b = 0.76, a = 1, dr = 0.42, dg = 0.31, db = 0.12 },
  far = { r = 1, g = 0.93, b = 0.76, a = 0.6, dr = 0.33, dg = 0.25, db = 0.09 },
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

-- The selectable styles, in the order of the dropdown. Every entry has the key and the locale key of its
-- name. kind "sprites" draws count textures (textures are file data ids of the client, used in turn;
-- sizeMin and sizeMax in pixels at 100 percent size, radius the spread; atlas is tried first where the
-- client knows it; fallback is the id drawn when neither resolves, nil keeps the cooldown star). Their
-- motion is a driver with parameters: none or "fade" lets the sprites fade in and out at random places
-- (life stretches the fade times, drift is the speed in pixels per second, rise or sink point the drift
-- up or down, glow adds the dark layer and the pulsing glow of the original look), "spot" keeps them at
-- fixed places and pulses them (see Logic.Pose), "loop" flies them along a closed path with an optional
-- trail, "ping" lets a ring or flash expand and fade, "fall" lets sprites sink along a lane and fade at both
-- ends (sway, spin). sheet = { cols, rows, fps } animates the frames of a sprite sheet through TexCoord;
-- sheet.fixed gives every sprite one cell for good instead (step cells apart, 0 keeps them all on the first). maxCount caps the count setting, extras are more layers drawn with
-- the same drivers (count "main" follows the first layer). allowed lists the kinds (Logic.KINDS keys) that may
-- use the style, nil allows every kind. kind "beam" draws one tall beam (atlas first, the texture when the
-- client lacks it, width and height in pixels at 100 percent size) with a spark at its foot. "auto" and
-- "original" draw no textures of their own. hidden keeps a style out of the gallery (no preview possible).
-- Ids marked "unverified" were named by the owner and could not be checked without the game.
Logic.NODE_SPARKLE = 984391
local NODE_SPARKLE = Logic.NODE_SPARKLE
Logic.STYLE_CATALOG = {
  { key = "auto", label = "sparkles.style.auto" },
  { key = "original", label = "sparkles.style.original", hidden = true },
  {
    key = "particles",
    label = "sparkles.style.particles",
    kind = "sprites",
    textures = { Logic.STAR_TEXTURE },
    blend = "ADD",
    count = Logic.PARTICLES,
    sizeMin = Logic.STAR_SIZE_MIN,
    sizeMax = Logic.STAR_SIZE_MAX,
    radius = Logic.RADIUS,
    glow = true,
  },
  {
    key = "glints",
    label = "sparkles.style.glints",
    kind = "sprites",
    textures = { 131010, 131011 },
    blend = "ADD",
    count = 9,
    sizeMin = 22,
    sizeMax = 38,
    radius = Logic.RADIUS,
  },
  {
    key = "lightbeam",
    label = "sparkles.style.lightbeam",
    kind = "beam",
    atlas = "GarrisonFX-StarBurst",
    textures = { 984391 },
    blend = "ADD",
    width = 44,
    height = Logic.HOST_SIZE * 3,
    sparkTexture = 131010,
    sparkSize = 34,
  },
  {
    key = "fireflies",
    label = "sparkles.style.fireflies",
    kind = "sprites",
    textures = { 190732 },
    blend = "ADD",
    count = 6,
    sizeMin = 18,
    sizeMax = 28,
    radius = 52,
    life = 4,
    drift = 9,
  },
  {
    key = "dust",
    label = "sparkles.style.dust",
    kind = "sprites",
    textures = { 984391 },
    blend = "ADD",
    count = 10,
    sizeMin = 8,
    sizeMax = 16,
    radius = Logic.RADIUS,
    life = 3,
    drift = 7,
    rise = true,
  },
  {
    key = "twinkle",
    label = "sparkles.style.twinkle",
    kind = "sprites",
    motion = "spot",
    textures = { NODE_SPARKLE },
    fallback = NODE_SPARKLE,
    blend = "ADD",
    count = 6,
    sizeMin = 30,
    sizeMax = 30,
    radius = Logic.RADIUS,
    period = 2.4,
    alphaMin = 0.25,
    scaleMin = 0.6,
    extras = {
      {
        motion = "spot",
        textures = { NODE_SPARKLE },
        fallback = NODE_SPARKLE,
        count = "main",
        sizeMin = 12,
        sizeMax = 12,
        period = 2.4,
        alphaMin = 0.5,
        scaleMin = 0.8,
      },
    },
  },
  {
    key = "pollen",
    label = "sparkles.style.pollen",
    kind = "sprites",
    atlas = "BonusChest-CircleGlow",
    textures = { NODE_SPARKLE },
    fallback = NODE_SPARKLE,
    blend = "ADD",
    count = 12,
    sizeMin = 8,
    sizeMax = 14,
    radius = 54,
    life = 4,
    drift = 6,
  },
  {
    key = "starcrown",
    label = "sparkles.style.starcrown",
    kind = "sprites",
    motion = "loop",
    path = "ellipse",
    textures = { 131010 },
    fallback = NODE_SPARKLE,
    blend = "ADD",
    count = 3,
    maxCount = 3,
    sizeMin = 18,
    sizeMax = 18,
    radius = 38,
    ry = 12,
    cy = 44,
    period = 6,
    extras = {
      {
        motion = "spot",
        atlas = "GarrisonFX-StarBurst",
        textures = { NODE_SPARKLE },
        fallback = NODE_SPARKLE,
        count = 1,
        sizeMin = 64,
        sizeMax = 64,
        radius = 1,
        cy = 8,
        period = 3.2,
        alphaMin = 0.55,
        scaleMin = 0.85,
        sublevel = -1,
      },
    },
  },
  {
    key = "wisp",
    label = "sparkles.style.wisp",
    kind = "sprites",
    motion = "loop",
    path = "eight",
    textures = { NODE_SPARKLE },
    fallback = NODE_SPARKLE,
    blend = "ADD",
    count = 2,
    maxCount = 3,
    sizeMin = 22,
    sizeMax = 22,
    radius = 40,
    ry = 22,
    period = 5,
    trail = 5,
    trailStep = 0.09,
  },
  {
    key = "settledust",
    label = "sparkles.style.settledust",
    kind = "sprites",
    textures = { NODE_SPARKLE },
    fallback = NODE_SPARKLE,
    blend = "ADD",
    count = 10,
    sizeMin = 6,
    sizeMax = 12,
    radius = 46,
    life = 3.5,
    drift = 6,
    sink = true,
  },
  {
    key = "lens",
    label = "sparkles.style.lens",
    kind = "sprites",
    motion = "spot",
    textures = { 1109038 },
    fallback = NODE_SPARKLE,
    blend = "ADD",
    count = 3,
    maxCount = 6,
    sizeMin = 34,
    sizeMax = 34,
    radius = 32,
    period = 2.6,
    alphaMin = 0.4,
    scaleMin = 0.6,
    extras = {
      {
        motion = "spot",
        textures = { 219371 },
        fallback = NODE_SPARKLE,
        count = 1,
        sizeMin = 70,
        sizeMax = 70,
        radius = 1,
        period = 3.4,
        alphaMin = 0.35,
        scaleMin = 0.8,
        sublevel = -1,
      },
    },
  },
  {
    key = "orbglow",
    label = "sparkles.style.orbglow",
    allowed = { "chests", "quests" },
    kind = "sprites",
    motion = "spot",
    textures = { 918928 },
    fallback = NODE_SPARKLE,
    sheet = { cols = 4, rows = 4, fps = 10 },
    blend = "ADD",
    count = 3,
    maxCount = 5,
    sizeMin = 26,
    sizeMax = 26,
    radius = 30,
    period = 3,
    alphaMin = 0.5,
    scaleMin = 0.8,
    extras = {
      {
        motion = "spot",
        textures = { 166232 },
        fallback = NODE_SPARKLE,
        count = "main",
        sizeMin = 46,
        sizeMax = 46,
        period = 3,
        alphaMin = 0.3,
        scaleMin = 0.8,
        sublevel = -1,
      },
    },
  },
  {
    key = "halo",
    label = "sparkles.style.halo",
    allowed = { "others", "bobber" },
    kind = "sprites",
    motion = "ping",
    textures = { 167071 },
    fallback = NODE_SPARKLE,
    blend = "ADD",
    count = 2,
    maxCount = 3,
    sizeMin = 84,
    sizeMax = 84,
    radius = 1,
    period = 3,
    power = 1.2,
    scaleMin = 0.4,
    extras = {
      {
        motion = "spot",
        textures = { 166232 },
        fallback = NODE_SPARKLE,
        count = 1,
        sizeMin = 34,
        sizeMax = 34,
        radius = 1,
        period = 3,
        alphaMin = 0.4,
        scaleMin = 0.8,
      },
    },
  },
  {
    key = "tumble",
    label = "sparkles.style.tumble",
    kind = "sprites",
    motion = "spot",
    textures = { 1397441 },
    fallback = NODE_SPARKLE,
    sheet = { cols = 4, rows = 4, fps = 12 },
    blend = "ADD",
    count = 6,
    maxCount = 12,
    sizeMin = 24,
    sizeMax = 24,
    radius = 40,
    period = 2.2,
    alphaMin = 0.5,
    scaleMin = 0.8,
  },
  {
    key = "prism",
    label = "sparkles.style.prism",
    kind = "sprites",
    motion = "spot",
    textures = { 166970 },
    fallback = NODE_SPARKLE,
    sheet = { cols = 2, rows = 2, fixed = true, step = 0 },
    blend = "ADD",
    count = 3,
    maxCount = 5,
    sizeMin = 40,
    sizeMax = 40,
    radius = 32,
    period = 2.8,
    alphaMin = 0.3,
    scaleMin = 0.5,
  },
  {
    key = "snowfall",
    label = "sparkles.style.snowfall",
    kind = "sprites",
    textures = { 166914 },
    fallback = NODE_SPARKLE,
    blend = "BLEND",
    count = 8,
    maxCount = 16,
    sizeMin = 10,
    sizeMax = 18,
    radius = 48,
    life = 4,
    drift = 8,
    sink = true,
  },
  {
    key = "flare",
    label = "sparkles.style.flare",
    allowed = { "ore", "chests" },
    kind = "sprites",
    motion = "spot",
    atlas = "OBJFX_StarBurst",
    textures = { 166976 },
    fallback = NODE_SPARKLE,
    blend = "ADD",
    count = 2,
    maxCount = 3,
    sizeMin = 52,
    sizeMax = 52,
    radius = 22,
    period = 2.4,
    alphaMin = 0.4,
    scaleMin = 0.7,
  },
  {
    key = "petals",
    label = "sparkles.style.petals",
    allowed = { "herbs" },
    kind = "sprites",
    motion = "fall",
    textures = { 646587 },
    fallback = NODE_SPARKLE,
    sheet = { cols = 8, rows = 2, fixed = true, step = 5 },
    blend = "BLEND",
    count = 6,
    maxCount = 10,
    sizeMin = 16,
    sizeMax = 16,
    radius = 38,
    ry = 70,
    cy = 14,
    period = 7,
    sway = 8,
    spin = 0.8,
  },
  {
    key = "leaves",
    label = "sparkles.style.leaves",
    allowed = { "herbs" },
    kind = "sprites",
    motion = "fall",
    textures = { 979604 },
    fallback = NODE_SPARKLE,
    sheet = { cols = 2, rows = 2, fixed = true, step = 1 },
    blend = "BLEND",
    count = 4,
    maxCount = 8,
    sizeMin = 22,
    sizeMax = 22,
    radius = 36,
    ry = 70,
    cy = 14,
    period = 9,
    sway = 10,
    spin = 0.5,
  },
  {
    key = "emberspark",
    label = "sparkles.style.emberspark",
    allowed = { "ore" },
    kind = "sprites",
    textures = { NODE_SPARKLE },
    fallback = NODE_SPARKLE,
    blend = "ADD",
    count = 8,
    maxCount = 14,
    sizeMin = 8,
    sizeMax = 14,
    radius = 38,
    life = 1.2,
    drift = 26,
    extras = {
      {
        motion = "ping",
        textures = { 131011 },
        fallback = NODE_SPARKLE,
        count = 1,
        sizeMin = 70,
        sizeMax = 70,
        radius = 1,
        period = 2.2,
        power = 3,
        scaleMin = 0.5,
      },
    },
  },
  {
    key = "goldglint",
    label = "sparkles.style.goldglint",
    allowed = { "chests" },
    kind = "sprites",
    motion = "spot",
    textures = { 2449274 },
    fallback = NODE_SPARKLE,
    sheet = { cols = 8, rows = 2, fps = 14 },
    blend = "BLEND",
    count = 3,
    maxCount = 4,
    sizeMin = 30,
    sizeMax = 30,
    radius = 36,
    period = 2.8,
    alphaMin = 0.8,
    scaleMin = 1,
    bob = 4,
  },
  {
    key = "beacon",
    label = "sparkles.style.beacon",
    allowed = { "quests" },
    kind = "sprites",
    motion = "spot",
    textures = { 132049 },
    fallback = NODE_SPARKLE,
    blend = "BLEND",
    count = 1,
    maxCount = 1,
    sizeMin = 34,
    sizeMax = 34,
    radius = 1,
    cy = 20,
    period = 1.6,
    alphaMin = 1,
    scaleMin = 1,
    bob = 6,
  },
  {
    key = "glowmark",
    label = "sparkles.style.glowmark",
    kind = "sprites",
    motion = "ping",
    textures = { 136440 },
    fallback = NODE_SPARKLE,
    blend = "ADD",
    count = 2,
    maxCount = 2,
    sizeMin = 70,
    sizeMax = 70,
    radius = 1,
    period = 2.4,
    power = 1.5,
    scaleMin = 0.3,
  },
}

Logic.STYLES = {}
local SPECS = {}
for _, entry in ipairs(Logic.STYLE_CATALOG) do
  Logic.STYLES[#Logic.STYLES + 1] = entry.key
  SPECS[entry.key] = entry
end

-- Style keys of earlier versions and the style that took their place, so a saved choice survives the rename.
Logic.STYLE_ALIASES = {
  butterflies = "petals",
  flies = "wisp",
  pickaxe = "emberspark",
  coins = "goldglint",
  questmark = "beacon",
}

-- The current key of a saved style key: an old key becomes its replacement, anything else stays as it is.
function Logic.CanonicalStyle(key)
  return Logic.STYLE_ALIASES[key] or key
end

-- The catalog entry of a style key, nil for "auto", "original" (no textures of their own) and unknown keys.
function Logic.StyleSpec(key)
  local spec = SPECS[key]
  return spec and spec.kind and spec or nil
end

-- The kinds a style is limited to (keys of Logic.KINDS), nil when it may be used for every kind.
function Logic.StyleAllowed(key)
  local spec = SPECS[key]
  return spec and spec.allowed or nil
end

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
-- the soft target range in yards. The range setting is "max" (RANGE_TOP) or a number of yards from
-- RANGE_MIN to RANGE_TOP.
Logic.SIZE_DEFAULT = 75
Logic.SIZE_MIN = 30
Logic.SIZE_MAX = 150
Logic.SIZE_STEP = 5
Logic.RANGE_MIN = 10
Logic.RANGE_STEP = 5
Logic.RANGE_DEFAULT = 30
Logic.RANGE_MAX_SETTING = "max"
-- The highest value the module writes. What the client keeps of it is read back (see RangeReadback).
Logic.RANGE_TOP = 60

local function clampSetting(value, default, min, max)
  if not isNumber(value) then
    return default
  end
  return math.min(max, math.max(min, value))
end

function Logic.CleanSize(value)
  return clampSetting(value, Logic.SIZE_DEFAULT, Logic.SIZE_MIN, Logic.SIZE_MAX)
end

-- Yards for SoftTargetInteractRange: RANGE_TOP for "max", the number cut to RANGE_MIN up to RANGE_TOP,
-- RANGE_DEFAULT for nil and anything else.
function Logic.EffectiveRange(setting)
  if setting == Logic.RANGE_MAX_SETTING then
    return Logic.RANGE_TOP
  end
  if not isNumber(setting) then
    return Logic.RANGE_DEFAULT
  end
  return math.min(Logic.RANGE_TOP, math.max(Logic.RANGE_MIN, setting))
end

-- The stored setting: numbers outside RANGE_MIN to RANGE_TOP are cut, everything valid stays as it is.
function Logic.NormalizeRange(setting)
  if isNumber(setting) then
    return math.min(Logic.RANGE_TOP, math.max(Logic.RANGE_MIN, setting))
  end
  return setting
end

-- Slider position of a setting.
function Logic.RangeSlider(setting)
  return Logic.EffectiveRange(setting)
end

-- The setting a slider position stands for: the top is "max", below it the yards.
function Logic.RangeSetting(position)
  if not isNumber(position) or position >= Logic.RANGE_TOP then
    return Logic.RANGE_MAX_SETTING
  end
  return math.max(Logic.RANGE_MIN, position)
end

-- What the client keeps of the range we asked for, as one line for the diagnosis. held is the value the
-- variable has after the write (text or number, nil when the client does not tell), managed is false
-- while the module does not write the variable at all.
function Logic.RangeReadback(requested, held, managed)
  local now = tonumber(held)
  local heldText = now ~= nil and string.format("%g", now) or "unknown"
  if not managed then
    return string.format("not written (module idle), client holds %s", heldText)
  end
  local text = string.format("requested %g, client holds %s", requested, heldText)
  if now ~= nil and now ~= requested then
    text = string.format("%s (client clamps to %s)", text, heldText)
  end
  return text
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
-- Seconds between two polls of the watcher (a soft target without a known kind is looked at on every
-- poll) and between two looks at a target whose kind is known (to follow its state).
Logic.WATCH = 0.12
Logic.RECHECK_KNOWN = 1
-- Placement of the original model in its frame, to tune in the game.
Logic.MODEL = { scale = 1, x = 0, y = 0, z = 0, facing = 0 }

-- Kind of object ---------------------------------------------------------------------------------

-- The category of an object and whether its cursor icon says "unable" (not gatherable right now), from
-- the name of the icon (a path or an atlas name, any case). The client shows "unable" for a node out of
-- reach as well, see Logic.IsLocked. A number or anything unknown gives nil: the caller tries the tooltip next.
local function iconName(texture, atlas)
  if type(atlas) == "string" and atlas ~= "" then
    return atlas:lower()
  elseif type(texture) == "string" and texture ~= "" then
    return texture:lower()
  end
end

-- The words of a cursor icon name (lower case) that name a category, in the order they are tried. Data, so
-- more icon names can be added: only "mine" and the quest icons are confirmed by the client ("unable" is a
-- word of its own, see below). "chests" is weak: loot icons also appear on quest items on the ground, so it only
-- counts when the quest checks found nothing (see Logic.WEAK_CATEGORY).
Logic.ICON_WORDS = {
  { "ore", { "mine" } },
  { "herbs", { "gather", "herb" } },
  { "skinning", { "skin" } },
  { "bobber", { "fish" } },
  { "quest", { "quest" } },
  { "chests", { "pickup", "loot", "chest" } },
}
Logic.WEAK_CATEGORY = "chests"

function Logic.Classify(texture, atlas)
  local name = iconName(texture, atlas)
  if not name then
    return nil, false
  end
  local unable = name:find("unable", 1, true) ~= nil
  for _, entry in ipairs(Logic.ICON_WORDS) do
    for _, word in ipairs(entry[2]) do
      if name:find(word, 1, true) then
        return entry[1], unable
      end
    end
  end
  return nil, unable
end

-- The words of an object name (lower case, both languages) that name a category. Data, extend as needed.
Logic.NAME_WORDS = {
  { "bobber", { "bobber", "schwimmer" } },
  { "chests", { "chest", "truhe", "kiste" } },
}

function Logic.ClassifyName(name)
  if type(name) ~= "string" then
    return nil
  end
  name = name:lower()
  for _, entry in ipairs(Logic.NAME_WORDS) do
    for _, word in ipairs(entry[2]) do
      if name:find(word, 1, true) then
        return entry[1]
      end
    end
  end
end

-- An "unable" icon is a lock only in interact reach (skill too low or profession missing). Out of reach
-- or with an unknown range the client shows it for any node, so it says nothing about the skill.
function Logic.IsLocked(unable, inRange)
  return unable == true and inRange == true
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

-- Last resort for a world object: the fallback "object" (see ClassifyObject), else "others" (a plain
-- interaction: doors, mailboxes, benches). nil for anything that is no world object.
Logic.OTHERS = "others"

function Logic.ClassifyWorldObject(guid, isPlayer, creatureType, texture, atlas)
  if not Logic.IsWorldObject(guid, isPlayer, creatureType) then
    return nil
  end
  return Logic.ClassifyObject(guid, isPlayer, creatureType, texture, atlas) or Logic.OTHERS
end

-- The profession a tooltip line asks for: "Requires Mining (150)", "Benötigt Kräuterkunde" or a line
-- with the profession alone. The first line is the name of the object and never counts.
local PROFESSIONS = {
  { "mining", "ore" },
  { "bergbau", "ore" },
  { "herbalism", "herbs" },
  { "kräuterkunde", "herbs" },
  { "kraeuterkunde", "herbs" },
  { "skinning", "skinning" },
  { "kürschnerei", "skinning" },
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

-- extraSkinning: further texts (lower case) of a skinnable creature, e.g. the global string of the client.
function Logic.ClassifyTooltip(lines, extraSkinning)
  for i = 2, #(lines or {}) do
    local line = lines[i]
    if type(line) == "string" then
      local text = line:lower()
      if text:find("skinnable", 1, true) or (extraSkinning and hasAny(text, extraSkinning)) then
        return "skinning"
      end
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

-- The state to show: nil without target, "far" out of reach, "locked" in reach with an "unable" icon,
-- else "ready". With a normal icon an unknown range (nil) counts as in reach; with an "unable" icon it
-- counts as out of reach (see Logic.IsLocked).
function Logic.WantedState(inRange, unable)
  if inRange == false or (unable and inRange ~= true) then
    return "far"
  end
  return unable and "locked" or "ready"
end

-- Whether a target gets an effect at all: a locked object (see Logic.IsLocked) only when the player
-- asked for it (lockedNodes).
function Logic.ShowsTarget(locked, lockedNodes)
  return not locked or lockedNodes == true
end

-- The decision about an "unable" icon in words for the report.
function Logic.LockReason(unable, inRange)
  if unable ~= true then
    return "open"
  elseif inRange == true then
    return "locked: in reach and unable"
  end
  return "far: unable out of reach"
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
        -- Far to ready: the node came into gathering reach, the caller flashes once.
        s.flash = s.shown == "far" and want == "ready"
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

-- The flash when a node comes into reach: a starburst of the game, additive, fading out while it grows.
-- Returns alpha (1 to 0) and scale at the age in seconds, nil once it is over.
Logic.FLASH_TEXTURE = 131011
Logic.FLASH_TIME = 0.35
Logic.FLASH_SIZE = 110
function Logic.FlashLook(age)
  if type(age) ~= "number" or age < 0 or age >= Logic.FLASH_TIME then
    return nil
  end
  local p = age / Logic.FLASH_TIME
  return 1 - p, 0.6 + 0.6 * p
end

-- The color of a state: the color of the kind (nil = the gold of LOOKS) for ready and far, gray stays gray.
local function stateColor(look, key, color)
  if not color or key == "locked" then
    return look.r, look.g, look.b
  end
  return color.r, color.g, color.b
end

-- The dark layer follows the color of the kind by a third of its distance from the gold it was made for (so the
-- default color changes nothing and a blue kind gets a bluish shadow).
Logic.DARK_TINT = 0.35

local function stateDark(look, key, color)
  if not color or key == "locked" then
    return look.dr, look.dg, look.db
  end
  local gold = LOOKS.ready
  local function shifted(dark, value, base)
    return math.min(1, math.max(0, dark + (value - base) * Logic.DARK_TINT))
  end
  return shifted(look.dr, color.r, gold.r), shifted(look.dg, color.g, gold.g), shifted(look.db, color.b, gold.b)
end

-- Color and brightness of the moment (cross fade of the last two states, times the fade in). The
-- brightness never falls below MIN_ALPHA before the fade in. color: { r, g, b } of the kind, nil for the gold.
function Logic.Look(s, color)
  local cur = LOOKS[s.shown]
  if not cur then
    return 1, 1, 1, 0
  end
  local prev = LOOKS[s.from] or cur
  local m = s.mix
  local alpha = math.max(Logic.MIN_ALPHA, prev.a + (cur.a - prev.a) * m)
  local pr, pg, pb = stateColor(prev, s.from, color)
  local cr, cg, cb = stateColor(cur, s.shown, color)
  return pr + (cr - pr) * m, pg + (cg - pg) * m, pb + (cb - pb) * m, alpha * s.alpha
end

-- The dark color of the layer behind the glow, cross faded like Look.
function Logic.DarkLook(s, color)
  local cur = LOOKS[s.shown]
  if not cur then
    return 0, 0, 0
  end
  local prev = LOOKS[s.from] or cur
  local m = s.mix
  local pr, pg, pb = stateDark(prev, s.from, color)
  local cr, cg, cb = stateDark(cur, s.shown, color)
  return pr + (cr - pr) * m, pg + (cg - pg) * m, pb + (cb - pb) * m
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
  value = Logic.CanonicalStyle(value)
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

-- The style to draw: "original" or the key of a texture style. kindKey is the kind of the target: a style the
-- kind does not allow counts as automatic, and automatic means the default of the kind (Logic.AutoStyle, the
-- particles without a kind) while AUTO_PREFERS_MODEL is off. A model that does not load gives the particles, the
-- closest look to it.
-- The second result is true when the player asked for the original model and it did not load (one chat line).
function Logic.ResolveStyle(choice, modelLoaded, kindKey)
  choice = Logic.CleanStyle(choice)
  if kindKey and not Logic.KindAllows(kindKey, choice) then
    choice = "auto"
  end
  if not Logic.WantsModel(choice) then
    return choice == "auto" and Logic.AutoStyle(kindKey) or choice, false
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

-- Soft targeting reaches objects up to the range setting. The range entry is a
-- placeholder, Desired takes the effective range.
Logic.TARGET_CVARS = {
  { "SoftTargetInteract", "3" },
  { "SoftTargetInteractRange", tostring(Logic.RANGE_DEFAULT) },
  { "SoftTargetInteractArc", "2" },
  { "SoftTargetInteractOnlyInRange", "0" },
  { "SoftTargetIconInteract", "1" },
  { "SoftTargetIconGameObject", "1" },
  { "SoftTargetLowPriorityIcons", "1" },
}
-- Not written any more: the plate of a world object exists with the player's value. Still read for the
-- report, and an original saved by an earlier version is put back.
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
-- settings, gameIcons only counts as off when it is false), other (any further kind is on), range (the setting). Soft targeting is only
-- changed while a category is on. An empty result means: restore all.
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
  if opts.ore or opts.herbs or opts.quest or opts.other then
    for _, entry in ipairs(Logic.TARGET_CVARS) do
      out[entry[1]] = entry[2]
    end
    out[Logic.RANGE_CVAR] = tostring(Logic.EffectiveRange(opts.range))
    if opts.gameIcons == false then
      for _, name in ipairs(Logic.ICON_CVARS) do
        out[name] = "0"
      end
    end
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
-- spec (an entry of Logic.STYLE_CATALOG) is kept on the particle, none means the particles style.
function Logic.Respawn(p, rnd, wait, spec)
  p.spec = spec or p.spec
  spec = p.spec or SPECS.particles
  local angle = rnd() * 2 * math.pi
  local radius = spec.radius * math.sqrt(rnd())
  p.x, p.y = math.cos(angle) * radius, math.sin(angle) * radius
  p.size = spec.sizeMin + (spec.sizeMax - spec.sizeMin) * rnd()
  local life = spec.life or 1
  p.fin, p.hold, p.fout = (0.1 + rnd() * 0.15) * life, (0.05 + rnd() * 0.15) * life, (0.2 + rnd() * 0.3) * life
  p.age = wait and -rnd() * wait or 0
  if spec.drift then
    local heading = rnd() * 2 * math.pi
    if spec.rise or spec.sink then
      heading = (spec.rise and 1 or -1) * math.pi / 2 + (rnd() - 0.5) * 0.8
    end
    local speed = spec.drift * (0.5 + rnd())
    p.vx, p.vy = math.cos(heading) * speed, math.sin(heading) * speed
  end
end

-- Advances a particle by dt; true when it got a new place or drifts (the caller moves its texture).
function Logic.StepParticle(p, dt, rnd)
  p.age = p.age + dt
  if p.age >= p.fin + p.hold + p.fout then
    Logic.Respawn(p, rnd, 0.4)
    return true
  end
  if p.vx and p.age > 0 then
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
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
function Logic.StaticSpot(i, n, spreadRadius)
  local angle = (i - 1) / n * 2 * math.pi
  local radius = (spreadRadius or Logic.RADIUS) * (i % 2 == 0 and 0.75 or 0.45)
  return math.cos(angle) * radius, math.sin(angle) * radius, 0.75
end

-- Layers and poses ----------------------------------------------------------------------------------------

local function copyFields(source)
  local out = {}
  for key, value in pairs(source) do
    out[key] = value
  end
  return out
end

-- The layers a style draws for a count and a spread (percent of the radius), built once per effect: the
-- first layer is the style itself (its count is the setting, capped by maxCount), extras follow it. Every
-- layer is a flat table with the fields the drivers read.
function Logic.ExpandLayers(entry, count, spreadPercent)
  local spread = spreadPercent / 100
  local main = copyFields(entry)
  main.extras = nil
  main.count = math.max(1, math.min(math.floor(count or entry.count), entry.maxCount or math.huge))
  main.radius = entry.radius * spread
  local list = { main }
  for _, extra in ipairs(entry.extras or {}) do
    local layer = copyFields(extra)
    layer.blend = extra.blend or entry.blend
    layer.count = extra.count == "main" and main.count or extra.count
    layer.radius = (extra.radius or entry.radius) * spread
    list[#list + 1] = layer
  end
  return list
end

local TAU = 2 * math.pi
local GOLDEN_ANGLE = 2.399963229728653

-- 0 to 1 wave with the period in seconds and a phase in cycles; nil time gives the middle (reduced motion).
local function wave(t, period, phase)
  if t == nil then
    return 0.5
  end
  return 0.5 + 0.5 * math.sin((t / period + phase) * TAU)
end

-- Pose of sprite i of n (j > 0 is a trail sprite) of a layer at the time t in seconds; nil t is the still
-- first frame of reduced motion. Returns x, y in pixels from the center, alpha (0 to 1, before the state
-- brightness), scale and the stretch of the width (a wing beat). No allocation: it runs per sprite and frame.
-- "spot": fixed places on a golden angle spread that pulse in alpha and scale (period, alphaMin, scaleMin) and
-- bob by bob pixels, shifted up by cy. "loop": a closed path ("ellipse" or a figure "eight", rx = radius, ry,
-- centered at cy) walked in period seconds, sprites a cycle apart, trail sprites lag trailStep seconds each
-- and fade; flap beats the width flapRate times a second. "ping": a ring or flash that grows from scaleMin to
-- full size while it fades (power shapes the fade), sprites a cycle apart. "fall": each sprite sinks ry pixels
-- from the top (centered at cy) in period seconds on a lane across radius that changes every cycle, sways by
-- sway pixels, fades in and out at the ends and turns spin radians a second. The sixth value is the rotation
-- in radians, 0 where a layer has no spin.
function Logic.Pose(layer, i, n, j, t)
  local motion = layer.motion
  local period = layer.period or 2.4
  local cy = layer.cy or 0
  if motion == "loop" then
    local lag = (j or 0) * (layer.trailStep or 0.07) / period
    local a = ((t and t / period or 0) + (i - 1) / n - lag) * TAU
    local rx, ry = layer.radius, layer.ry or layer.radius * 0.6
    local x, y
    if layer.path == "eight" then
      x, y = rx * math.sin(a), ry * math.sin(2 * a)
    else
      x, y = rx * math.cos(a), ry * math.sin(a)
    end
    local alpha, scale = 1, 1
    if j and j > 0 then
      local fall = 1 - j / ((layer.trail or 1) + 1)
      alpha, scale = fall * fall, 0.4 + 0.6 * fall
    end
    local stretch = 1
    if t and layer.flap then
      stretch = 1 - layer.flap * (0.5 + 0.5 * math.sin(t * (layer.flapRate or 2) * TAU + i))
    end
    return x, y + cy, alpha, scale, stretch
  elseif motion == "ping" then
    local p = t and (t / period + (i - 1) / n) % 1 or 0.4
    local alpha = math.min(1, p / 0.12) * (1 - p) ^ (layer.power or 1)
    return 0, cy, alpha, (layer.scaleMin or 0.3) + (1 - (layer.scaleMin or 0.3)) * p, 1
  elseif motion == "fall" then
    local cycles = t and t / period + (i - 1) / n or (i - 0.5) / n
    local p = cycles % 1
    local lane = ((i * 0.618 + math.floor(cycles) * 0.382) % 1 - 0.5) * 2
    local sway = (layer.sway or 0) * math.sin((p * 2 + i * 0.31) * TAU)
    local alpha = math.min(1, p / 0.15, (1 - p) / 0.25)
    local ry = layer.ry or 60
    return lane * layer.radius + sway, cy + ry * (0.5 - p), alpha, 1, 1, (layer.spin or 0) * (t or 0) + i
  end
  local x, y = 0, 0
  if n > 1 then
    local radius = layer.radius * math.sqrt((i - 0.5) / n)
    x, y = math.cos(i * GOLDEN_ANGLE) * radius, math.sin(i * GOLDEN_ANGLE) * radius
  end
  local phase = (i * 0.37) % 1
  local w = wave(t, period, phase)
  local alphaMin, scaleMin = layer.alphaMin or 0.3, layer.scaleMin or 0.7
  local bob = t and layer.bob and layer.bob * math.sin((t / period + phase) * TAU) or 0
  return x, y + cy + bob, alphaMin + (1 - alphaMin) * w, scaleMin + (1 - scaleMin) * w, 1
end

-- Frame (0 based) of a sprite sheet animation of sprite i at the time t; sprites start five frames apart so
-- they do not turn in step. nil t (reduced motion) is the first frame. A fixed sheet gives sprite i the cell
-- (i - 1) * step at any time.
function Logic.SheetFrame(layer, i, t)
  local sheet = layer.sheet
  if sheet and sheet.fixed then
    return ((i - 1) * (sheet.step or 1)) % (sheet.cols * sheet.rows)
  end
  if not sheet or t == nil then
    return 0
  end
  return (math.floor(t * sheet.fps) + (i - 1) * 5) % (sheet.cols * sheet.rows)
end

-- TexCoord rectangle (left, right, top, bottom) of a frame in a sheet read row by row from the top left.
function Logic.SheetCoords(sheet, frame)
  local col, row = frame % sheet.cols, math.floor(frame / sheet.cols)
  return col / sheet.cols, (col + 1) / sheet.cols, row / sheet.rows, (row + 1) / sheet.rows
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

-- The soft target icon the game draws on the plate as short text: icon = { frame, shown, iconShown,
-- texture, atlas } or nil when the plate has none.
function Logic.PlateIconText(icon, words)
  if type(icon) ~= "table" or not icon.frame then
    return "none"
  end
  return string.format(
    "shown=%s iconShown=%s texture=%s atlas=%s",
    show(icon.shown, words),
    show(icon.iconShown, words),
    show(icon.texture, words),
    show(icon.atlas, words)
  )
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
      "sparkles flow: token=%s gameObject=%s plate=%s plateIcon=%s",
      v(info.unitExists),
      v(info.unitIsGameObject),
      v(info.plate),
      Logic.PlateIconText(info.plateIcon, words)
    ),
    string.format(
      "sparkles flow: cursor=%s call=%s kind=%s cat=%s want=%s state=%s inRange=%s rechecks=%s locked=%s unable=%s reason=%s",
      v(cursor.atlas or cursor.file or "none"),
      v(cursor.call),
      v(info.kindKey or info.category),
      v(info.cat),
      v(info.want),
      v(info.state),
      v(info.inRange),
      v(info.rechecks),
      v(info.locked),
      v(info.unable),
      Logic.LockReason(info.unable, info.inRange)
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
    v(info.range == nil and Logic.RANGE_DEFAULT or info.range),
    v(info.effective),
    v(info.rangeNow),
    v(info.distance),
    info.distSeen == nil and info.distTried and words.noDistance or v(info.distSeen)
  )
  -- The settings of the kind of the current target (nil without one) and the general options.
  local k, general = info.kindCfg or {}, info.general or {}
  local color = k.color
  lines[#lines + 1] = string.format(
    "sparkles config: kind=%s style=%s colour=%s size=%s height=%s count=%s | general: brightness=%s reachLook=%s combatHide=%s instanceHide=%s myProf=%s rare=%s sound=%s gatherDim=%s finish=%s",
    v(info.configKind or "none"),
    v(k.style),
    color and string.format("%s,%s,%s", v(color.r), v(color.g), v(color.b)) or "nil",
    v(k.size),
    v(k.height),
    v(k.count),
    v(general.brightness),
    v(general.reachLook),
    v(general.combatHide),
    v(general.instanceHide),
    v(general.myProfessionsOnly),
    v(general.rareGlow),
    v(general.sound),
    v(general.gatherDim),
    v(general.finish)
  )
  lines[#lines + 1] = "sparkles range: " .. Logic.RangeReadback(info.effective, info.rangeHeld, info.rangeManaged)
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
