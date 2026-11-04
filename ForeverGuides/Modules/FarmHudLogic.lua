-- Farm HUD, pure side (no frames, no client calls): the validated settings, the size of the enlarged
-- minimap, the choice of the terrain variant, what has to be cached before the minimap is moved and in
-- which order it is put back, the plan that decides what to do next (move, put back, hide, wait for the
-- end of the combat), and the places of the compass and of the gather ring. The frames and hooks are
-- Modules/FarmHud.lua.
local _, ns = ...
local ML = ns.MinimapPinLogic

local FH = {}
ns.FarmHudLogic = FH

-- Size factor (share of the smaller screen side), frame strata of the HUD (BACKGROUND lies behind the user
-- interface and in front of the 3D world), terrain variants.
FH.SCALE_MIN, FH.SCALE_MAX, FH.SCALE_DEFAULT = 0.5, 2, 1
FH.STRATA = { "BACKGROUND", "LOW", "MEDIUM" }
FH.STRATA_DEFAULT = "BACKGROUND"
-- auto takes the first variant the client supports; ground switches the ground textures off, alpha fades the
-- whole minimap, none leaves it as it is.
FH.TERRAINS = { "auto", "ground", "alpha", "none" }
FH.TERRAIN_DEFAULT = "auto"
FH.ALPHA_MIN, FH.ALPHA_MAX, FH.ALPHA_DEFAULT = 0, 1, 0.3
-- Zoom step set while the HUD is on; ZOOM_KEEP leaves the zoom alone. The old zoom comes back afterwards.
FH.ZOOM_KEEP, FH.ZOOM_MIN, FH.ZOOM_MAX, FH.ZOOM_DEFAULT = -1, 0, 5, 0
FH.PIN_SCALE_MIN, FH.PIN_SCALE_MAX, FH.PIN_SCALE_DEFAULT = 0.5, 2, 1
FH.COMPASS_SIZE_MIN, FH.COMPASS_SIZE_MAX, FH.COMPASS_SIZE_DEFAULT = 8, 32, 14
FH.COMPASS_COLORS = {
  white = { 1, 1, 1 },
  yellow = { 1, 0.82, 0.1 },
  green = { 0.3, 1, 0.3 },
  red = { 1, 0.3, 0.3 },
  blue = { 0.4, 0.7, 1 },
}
FH.COMPASS_ORDER = { "white", "yellow", "green", "red", "blue" }
FH.COMPASS_COLOR_DEFAULT = "white"
FH.RING_YARDS_MIN, FH.RING_YARDS_MAX, FH.RING_YARDS_STEP, FH.RING_YARDS_DEFAULT = 5, 100, 5, 20
-- The compass letters sit at this share of the half size (the terrain ends a little inside the edge).
FH.COMPASS_RATIO = 0.92

FH.DEFAULTS = {
  scale = FH.SCALE_DEFAULT,
  strata = FH.STRATA_DEFAULT,
  terrain = FH.TERRAIN_DEFAULT,
  alpha = FH.ALPHA_DEFAULT,
  zoom = FH.ZOOM_DEFAULT,
  hideInCombat = false,
  hideInInstance = true,
  compass = true,
  compassSize = FH.COMPASS_SIZE_DEFAULT,
  compassColor = FH.COMPASS_COLOR_DEFAULT,
  ring = false,
  ringYards = FH.RING_YARDS_DEFAULT,
  pinScale = FH.PIN_SCALE_DEFAULT,
}

local IS_STRATA, IS_TERRAIN = {}, {}
for _, v in ipairs(FH.STRATA) do
  IS_STRATA[v] = true
end
for _, v in ipairs(FH.TERRAINS) do
  IS_TERRAIN[v] = true
end

local function finite(v)
  return ML.finite(v)
end

local function choice(value, allowed, default)
  return allowed[value] and value or default
end

local function flag(value, default)
  if type(value) == "boolean" then
    return value
  end
  return default
end

-- The settings table of the Store (any value, also nil) as a complete table with every field valid.
function FH.Settings(raw)
  raw = type(raw) == "table" and raw or {}
  local d = FH.DEFAULTS
  local zoom = tonumber(raw.zoom)
  if zoom == nil or zoom ~= zoom then
    zoom = d.zoom
  elseif zoom < FH.ZOOM_MIN then
    zoom = FH.ZOOM_KEEP
  else
    zoom = math.floor(math.min(zoom, FH.ZOOM_MAX) + 0.5)
  end
  local yards = ML.Clamp(raw.ringYards, FH.RING_YARDS_MIN, FH.RING_YARDS_MAX, d.ringYards)
  return {
    scale = ML.Clamp(raw.scale, FH.SCALE_MIN, FH.SCALE_MAX, d.scale),
    strata = choice(raw.strata, IS_STRATA, d.strata),
    terrain = choice(raw.terrain, IS_TERRAIN, d.terrain),
    alpha = ML.Clamp(raw.alpha, FH.ALPHA_MIN, FH.ALPHA_MAX, d.alpha),
    zoom = zoom,
    hideInCombat = flag(raw.hideInCombat, d.hideInCombat),
    hideInInstance = flag(raw.hideInInstance, d.hideInInstance),
    compass = flag(raw.compass, d.compass),
    compassSize = ML.Clamp(raw.compassSize, FH.COMPASS_SIZE_MIN, FH.COMPASS_SIZE_MAX, d.compassSize),
    compassColor = choice(raw.compassColor, FH.COMPASS_COLORS, d.compassColor),
    ring = flag(raw.ring, d.ring),
    ringYards = math.floor(yards / FH.RING_YARDS_STEP + 0.5) * FH.RING_YARDS_STEP,
    pinScale = ML.Clamp(raw.pinScale, FH.PIN_SCALE_MIN, FH.PIN_SCALE_MAX, d.pinScale),
  }
end

-- Size -------------------------------------------------------------------------------------------------

-- Edge of the enlarged minimap in its own units: the smaller screen side times the factor, divided by the
-- scale the minimap keeps (its size is set, the scale stays as it was). nil when a number is unusable.
function FH.Size(screenW, screenH, factor, ownScale)
  if not (finite(screenW) and finite(screenH) and screenW > 0 and screenH > 0) then
    return nil
  end
  factor = ML.Clamp(factor, FH.SCALE_MIN, FH.SCALE_MAX, FH.SCALE_DEFAULT)
  ownScale = finite(ownScale) and ownScale > 0 and ownScale or 1
  return math.min(screenW, screenH) * factor / ownScale
end

-- Factor for the size of the pins: the pins keep the size they had on the small minimap (the minimap now
-- sits in another parent with another effective scale) times the player's pin scale.
function FH.PinFactor(pinScale, oldEffective, newEffective)
  pinScale = ML.Clamp(pinScale, FH.PIN_SCALE_MIN, FH.PIN_SCALE_MAX, FH.PIN_SCALE_DEFAULT)
  if finite(oldEffective) and finite(newEffective) and oldEffective > 0 and newEffective > 0 then
    return pinScale * oldEffective / newEffective
  end
  return pinScale
end

-- Pixels from the center for yards, where the minimap shows `radius` yards up to `half` px.
function FH.YardsToPx(yards, radius, half)
  if not (finite(yards) and finite(radius) and finite(half) and radius > 0) then
    return nil
  end
  return yards / radius * half
end

-- Terrain ------------------------------------------------------------------------------------------------

-- What to do about the terrain: { mode = "ground" | "alpha" | "none", alpha = number (for "alpha"),
-- fellBack = true when the wanted variant is not supported }. caps = { ground = the client can switch the
-- ground textures off }. "alpha" and "none" work everywhere.
function FH.Terrain(wanted, caps, alpha)
  wanted = choice(wanted, IS_TERRAIN, FH.TERRAIN_DEFAULT)
  alpha = ML.Clamp(alpha, FH.ALPHA_MIN, FH.ALPHA_MAX, FH.ALPHA_DEFAULT)
  local ground = type(caps) == "table" and caps.ground == true
  if wanted == "none" then
    return { mode = "none", alpha = alpha }
  end
  if wanted == "alpha" then
    return { mode = "alpha", alpha = alpha }
  end
  if ground then
    return { mode = "ground", alpha = alpha }
  end
  return { mode = "alpha", alpha = alpha, fellBack = wanted == "ground" }
end

-- Cache and restore ------------------------------------------------------------------------------------

-- The state of the minimap read before it is moved. Fields: parent, points ({ point, rel, relPoint, x, y }
-- each), width, height, scale, strata, level, alpha, mouse, wheel, shown (all needed), zoom, ground,
-- backdropShown, backdropMouse, backdropWheel, compassShown, effective (the effective scale, only read).
local REQUIRED = { "parent", "width", "height", "scale", "strata", "level", "alpha", "mouse", "wheel", "shown" }

-- Names of the required fields the snapshot lacks (a points list without an entry counts). Empty means the
-- snapshot is whole and everything can be put back.
function FH.Missing(snap)
  local out = {}
  if type(snap) ~= "table" then
    for _, name in ipairs(REQUIRED) do
      out[#out + 1] = name
    end
    out[#out + 1] = "points"
    return out
  end
  for _, name in ipairs(REQUIRED) do
    if snap[name] == nil then
      out[#out + 1] = name
    end
  end
  if type(snap.points) ~= "table" or #snap.points == 0 then
    out[#out + 1] = "points"
  end
  return out
end

-- The steps that put the minimap back, in order: the parent first (it resets level and strata), then the
-- anchors and the size, then the look and the optional parts that were cached.
function FH.RestoreSteps(snap)
  local steps = { "parent", "points", "size", "scale", "strata", "level", "alpha", "mouse", "wheel" }
  if type(snap) == "table" then
    if snap.zoom ~= nil then
      steps[#steps + 1] = "zoom"
    end
    if snap.ground ~= nil then
      steps[#steps + 1] = "ground"
    end
    if snap.backdropShown ~= nil then
      steps[#steps + 1] = "backdrop"
    end
    if snap.compassShown ~= nil then
      steps[#steps + 1] = "compass"
    end
  end
  steps[#steps + 1] = "shown"
  return steps
end

local COMPARED = {
  "parent",
  "width",
  "height",
  "scale",
  "strata",
  "level",
  "alpha",
  "mouse",
  "wheel",
  "zoom",
  "ground",
  "shown",
  "backdropShown",
  "backdropMouse",
  "backdropWheel",
  "compassShown",
}

local function same(a, b)
  if type(a) == "number" and type(b) == "number" then
    return math.abs(a - b) < 0.01
  end
  return a == b
end

local function samePoint(a, b)
  return a.point == b.point and a.rel == b.rel and a.relPoint == b.relPoint and same(a.x, b.x) and same(a.y, b.y)
end

-- Names of the fields in which two snapshots differ (numbers within 0.01); empty when they are the same.
-- A field one side has not read is left out.
function FH.Diff(a, b)
  local out = {}
  if type(a) ~= "table" or type(b) ~= "table" then
    return { "snapshot" }
  end
  for _, name in ipairs(COMPARED) do
    if a[name] ~= nil and b[name] ~= nil and not same(a[name], b[name]) then
      out[#out + 1] = name
    end
  end
  local pa, pb = a.points or {}, b.points or {}
  local equal = #pa == #pb
  for i = 1, equal and #pa or 0 do
    if not samePoint(pa[i], pb[i]) then
      equal = false
      break
    end
  end
  if not equal then
    out[#out + 1] = "points"
  end
  return out
end

-- Plan --------------------------------------------------------------------------------------------------

-- What to do now. state = { attached (the minimap sits in the HUD), shown (the HUD is visible) }; ctx = {
-- wanted (the player's switch), suspended (a loading screen: the minimap goes back), combat, instance,
-- hideInCombat, hideInInstance }. Returns "enter", "leave", "show", "hide", "defer" (a change of the
-- minimap is due and waits for the end of the combat) or "none". Only "show" and "hide" are allowed in
-- combat, they change our own frames and nothing of Blizzard's.
function FH.Plan(state, ctx)
  local want = ctx.wanted == true and not ctx.suspended and not (ctx.instance == true and ctx.hideInInstance == true)
  if want ~= (state.attached == true) then
    if ctx.combat == true then
      return "defer"
    end
    return want and "enter" or "leave"
  end
  if want then
    local visible = not (ctx.combat == true and ctx.hideInCombat == true)
    if visible ~= (state.shown == true) then
      return visible and "show" or "hide"
    end
  end
  return "none"
end

-- Compass and ring -------------------------------------------------------------------------------------

-- The four letters at their place from the center (y up): half is the half size in px, rotate = the minimap
-- turns with the player, facing in radians as GetPlayerFacing. nil for a turning minimap without a facing.
-- A fixed minimap has north up.
function FH.CompassPoints(half, rotate, facing)
  if not finite(half) then
    return nil
  end
  if rotate and not finite(facing) then
    return nil
  end
  local r = half * FH.COMPASS_RATIO
  local out = {}
  -- Offsets in yards-like units: north is (dN 1, dW 0), east (0, -1), south (-1, 0), west (0, 1).
  local dirs = { { "N", 1, 0 }, { "E", 0, -1 }, { "S", -1, 0 }, { "W", 0, 1 } }
  for i, d in ipairs(dirs) do
    local up, left = d[2], d[3]
    if rotate then
      up, left = ML.Rotate(d[2], d[3], facing)
    end
    out[i] = { key = d[1], x = -left * r, y = up * r }
  end
  return out
end
