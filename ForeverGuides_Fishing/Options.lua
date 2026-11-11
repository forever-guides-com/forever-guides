-- The options of the fishing helper: the defaults, the limits and the cleaning of stored values.
-- Pure, no game calls. Every switch is off by default, a missing or invalid value falls back to
-- the default, so a damaged SavedVariables file can never switch a feature on.
local _, fish = ...
if not fish.FG then
  return
end

local O = {}
fish.Options = O

-- Switches in the order of the settings card. Each has a hint text "fishing.opt.<id>.hint".
O.TOGGLES = {
  "oneKey",
  "doubleClick",
  "doubleClickMounted",
  "recast",
  "recastInvert",
  "improveSound",
  "hideNames",
  "hideBobberIcon",
  "bobberMark",
  "autoLoot",
}

-- Switches that are on by default and need no binding or setting of the game: the catch journal only
-- listens to events. They are not part of TOGGLES, so "every function is off" keeps meaning the
-- functions that act on the game.
O.RECORD = { "recordCatches" }

-- Slider limits. The step is also the grid a stored value snaps to.
O.SLIDERS = {
  doubleClickTime = { min = 0.1, max = 0.8, step = 0.05, default = 0.2, decimals = 2 },
  recastPause = { min = 0, max = 3, step = 0.1, default = 1, decimals = 1 },
  soundVolume = { min = 0, max = 100, step = 5, default = 100, decimals = 0 },
  effectVolume = { min = 0, max = 100, step = 5, default = 100, decimals = 0 },
  -- Pixels of the own bobber icon below the name plate anchor of the bobber. The default is derived from
  -- the gap measured for the gathering sparkles at the same anchor, the player tunes it in the game.
  markOffset = { min = -200, max = 40, step = 5, default = -60, decimals = 0 },
}

O.DEFAULTS = {
  oneKey = false,
  doubleClick = false,
  doubleClickMounted = false,
  recast = false,
  recastInvert = false,
  improveSound = false,
  hideNames = false,
  hideBobberIcon = false,
  bobberMark = false,
  autoLoot = false,
  recordCatches = true,
  doubleClickTime = O.SLIDERS.doubleClickTime.default,
  recastPause = O.SLIDERS.recastPause.default,
  soundVolume = O.SLIDERS.soundVolume.default,
  effectVolume = O.SLIDERS.effectVolume.default,
  markOffset = O.SLIDERS.markOffset.default,
}

local IS_TOGGLE = {}
for _, id in ipairs(O.TOGGLES) do
  IS_TOGGLE[id] = true
end
for _, id in ipairs(O.RECORD) do
  IS_TOGGLE[id] = true
end

-- The value of a slider, snapped to its step and kept inside the limits; nil for anything that is no
-- finite number.
local function snap(def, value)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    return nil
  end
  local steps = math.floor((value - def.min) / def.step + 0.5)
  local out = def.min + steps * def.step
  out = math.max(def.min, math.min(def.max, out))
  local scale = 10 ^ def.decimals
  return math.floor(out * scale + 0.5) / scale
end

-- The clean value of one option, nil when the id is unknown or the value has the wrong kind.
function O.CleanValue(id, value)
  if IS_TOGGLE[id] then
    if type(value) == "boolean" then
      return value
    end
    return nil
  end
  local def = O.SLIDERS[id]
  if def then
    return snap(def, value)
  end
  return nil
end

-- A complete table of valid options from whatever was stored (nil, a damaged table, an older version).
function O.Clean(stored)
  local out = {}
  for id, default in pairs(O.DEFAULTS) do
    -- No "and ... or" here: a stored false is a valid value of a switch that is on by default.
    local value
    if type(stored) == "table" then
      value = O.CleanValue(id, stored[id])
    end
    if value == nil then
      value = default
    end
    out[id] = value
  end
  return out
end

-- True when at least one switch is on: without one the add-on creates no binding and changes no setting.
function O.AnyOn(options)
  for _, id in ipairs(O.TOGGLES) do
    if options[id] == true then
      return true
    end
  end
  return false
end

-- True when the throw after the reel in is on and has a way to start: the key or the double click.
function O.RecastOn(options)
  return options.recast == true and (options.oneKey == true or options.doubleClick == true)
end

-- The soft interaction target is only needed for reeling in with the key or the double click.
function O.NeedsSoftTarget(options)
  return options.oneKey == true or options.doubleClick == true
end

-- True when the own icon at the bobber is on and has a soft target to work with (the key or the double
-- click). The game icon is switched off for it while the line is out.
function O.MarkOn(options)
  return options.bobberMark == true and O.NeedsSoftTarget(options)
end
