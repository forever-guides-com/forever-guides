-- Rules and data of the mouse cursor ring (ns.CursorLogic), without WoW API: the defaults and the repair
-- of settings.cursorRing, the props of the element types (schemas and repair, one registry so a new type
-- only adds an entry), the visibility rules, the hysteresis of mouselook with an injected clock, the
-- position math and the presets. Drawing lives in CursorElements.lua, the host in Cursor.lua.
local _, ns = ...
local U, L, CL, A = ns.U, ns.L, ns.CanvasLogic, ns.CursorAssets

local CU = {
  -- The game's frame layers, lowest first.
  STRATA = {
    "BACKGROUND",
    "LOW",
    "MEDIUM",
    "HIGH",
    "DIALOG",
    "FULLSCREEN",
    "FULLSCREEN_DIALOG",
    "TOOLTIP",
  },
  -- What the ring does while the camera is turned with the mouse: disappear, stay at the cursor, or stand
  -- in the middle of the screen.
  MOUSELOOK = { "hide", "keep", "center" },
  -- Yes/no rules, in the order the settings show them.
  RULES = { "combatOnly", "instanceOnly", "needsTarget", "hideMounted", "hideInVehicle" },
  BLENDS = { "DISABLE", "ADD" },
  CROSS_STYLES = { "arms", "lines" },
  -- Mouselook counts as started only after this many seconds, so a quick right click does not flicker.
  HYSTERESIS = 0.15,
  THICKNESS_MIN = 1,
  THICKNESS_MAX = 6,
  -- On-screen line width of a ring in px.
  RING_THICKNESS_MIN = 1,
  RING_THICKNESS_MAX = 64,
  GAP_MAX = 128,
}
ns.CursorLogic = CU

CU.DEFAULTS = {
  enabled = false,
  strata = "TOOLTIP",
  mouselook = "hide",
  combatOnly = false,
  instanceOnly = false,
  needsTarget = false,
  hideMounted = false,
  hideInVehicle = false,
  layoutId = "standard",
  layouts = {},
}

ns.AddLocale("enUS", {
  ["cursor.preset.standard"] = "Standard ring",
  ["cursor.preset.crosshair"] = "Crosshair",
  ["cursor.preset.double"] = "Double ring",
  ["cursor.preset.dot"] = "Dot",
  ["cursor.el.ring"] = "Ring",
  ["cursor.el.ring2"] = "Inner ring",
  ["cursor.el.cross"] = "Crosshair",
  ["cursor.el.dot"] = "Dot",
})
ns.AddLocale("deDE", {
  ["cursor.preset.standard"] = "Standard-Ring",
  ["cursor.preset.crosshair"] = "Fadenkreuz",
  ["cursor.preset.double"] = "Doppelring",
  ["cursor.preset.dot"] = "Punkt",
  ["cursor.el.ring"] = "Ring",
  ["cursor.el.ring2"] = "Innerer Ring",
  ["cursor.el.cross"] = "Fadenkreuz",
  ["cursor.el.dot"] = "Punkt",
})

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function hex(v, default)
  local raw = type(v) == "string" and v:match("^#?(%x%x%x%x%x%x)$")
  return raw and raw:lower() or default
end

local function oneOf(v, list, default)
  for _, item in ipairs(list) do
    if v == item then
      return v
    end
  end
  return default
end

local function whole(v, default, lo, hi)
  return finite(v) and U.clamp(math.floor(v + 0.5), lo, hi) or default
end

local function opacity(v, default)
  return finite(v) and U.clamp(v, 0, 1) or default
end

-- Settings ---------------------------------------------------------------------------------------------

-- The settings of a raw table with every field valid (layoutId and layouts belong to the layout set).
function CU.Clean(raw)
  raw = type(raw) == "table" and raw or {}
  local d = CU.DEFAULTS
  local cfg = {
    enabled = raw.enabled == true,
    strata = oneOf(raw.strata, CU.STRATA, d.strata),
    mouselook = oneOf(raw.mouselook, CU.MOUSELOOK, d.mouselook),
  }
  for _, key in ipairs(CU.RULES) do
    cfg[key] = type(raw[key]) == "boolean" and raw[key] or d[key]
  end
  return cfg
end

-- Element types ----------------------------------------------------------------------------------------

local kinds, order = {}, {}

-- Adds an element type: def = { defaults = props, clean = function(raw, defaults) -> props, size = { w, h } }.
-- CursorElements.Register adds the drawing half under the same name.
function CU.Register(kind, def)
  if not kinds[kind] then
    order[#order + 1] = kind
  end
  kinds[kind] = def
end

function CU.Kinds()
  return order
end

function CU.Has(kind)
  return kinds[kind] ~= nil
end

-- The props of an element of `kind` with every field valid; nil for a type that is not registered.
-- size = { w, h } of the element (optional): a repair that depends on it, like the old ring stroke, reads it.
function CU.Props(kind, props, size)
  local def = kinds[kind]
  if not def then
    return nil
  end
  return def.clean(type(props) == "table" and props or {}, def.defaults, size)
end

function CU.NewProps(kind)
  local def = kinds[kind]
  return def and U.copy(def.defaults) or nil
end

function CU.Size(kind)
  local def = kinds[kind]
  return def and { def.size[1], def.size[2] } or nil
end

-- Stems of the filled shapes: the filled twins of the rings, then the soft shapes.
CU.FILLS = {}
for _, shape in ipairs(A.SHAPES) do
  CU.FILLS[#CU.FILLS + 1] = A.RingStem(shape.id)
end
for _, soft in ipairs(A.SOFT) do
  CU.FILLS[#CU.FILLS + 1] = soft.id
end

CU.SHAPE_IDS = {}
for i, shape in ipairs(A.SHAPES) do
  CU.SHAPE_IDS[i] = shape.id
end

-- The line width of a ring in px. A layout saved with the old fixed `stroke` (px at 256) keeps its look: the
-- stroke scales with the mean side of the element.
local function ringThickness(raw, d, size)
  local lo, hi = CU.RING_THICKNESS_MIN, CU.RING_THICKNESS_MAX
  if finite(raw.thickness) then
    return whole(raw.thickness, d.thickness, lo, hi)
  end
  if finite(raw.stroke) then
    local side = type(size) == "table"
        and finite(size[1])
        and finite(size[2])
        and size[1] > 0
        and size[2] > 0
        and (size[1] + size[2]) / 2
      or 64
    return whole(raw.stroke * side / A.BAKED_SIZE, d.thickness, lo, hi)
  end
  return d.thickness
end

-- `fill` is the colour inside the ring (absent = none), drawn behind it with its own opacity.
CU.Register("ring", {
  defaults = {
    shape = "circle",
    thickness = 4,
    color = "ffffff",
    alpha = 1,
    rotation = 0,
    blend = "DISABLE",
    fillAlpha = 0.5,
  },
  size = { 64, 64 },
  clean = function(raw, d, size)
    return {
      shape = oneOf(raw.shape, CU.SHAPE_IDS, d.shape),
      thickness = ringThickness(raw, d, size),
      color = hex(raw.color, d.color),
      alpha = opacity(raw.alpha, d.alpha),
      rotation = finite(raw.rotation) and U.clamp(math.floor(raw.rotation + 0.5) % 360, 0, 359) or d.rotation,
      blend = oneOf(raw.blend, CU.BLENDS, d.blend),
      fill = hex(raw.fill, nil),
      fillAlpha = opacity(raw.fillAlpha, d.fillAlpha),
    }
  end,
})

CU.Register("shape", {
  defaults = { shape = "fill-circle", color = "ffffff", alpha = 1, blend = "DISABLE" },
  size = { 32, 32 },
  clean = function(raw, d)
    return {
      shape = oneOf(raw.shape, CU.FILLS, d.shape),
      color = hex(raw.color, d.color),
      alpha = opacity(raw.alpha, d.alpha),
      blend = oneOf(raw.blend, CU.BLENDS, d.blend),
    }
  end,
})

-- The extent of a cross is the size of its element: the arms run from the gap to the edge.
CU.Register("cross", {
  defaults = { style = "arms", thickness = 2, gap = 6, color = "ffffff", alpha = 1 },
  size = { 48, 48 },
  clean = function(raw, d)
    return {
      style = oneOf(raw.style, CU.CROSS_STYLES, d.style),
      thickness = whole(raw.thickness, d.thickness, CU.THICKNESS_MIN, CU.THICKNESS_MAX),
      gap = whole(raw.gap, d.gap, 0, CU.GAP_MAX),
      color = hex(raw.color, d.color),
      alpha = opacity(raw.alpha, d.alpha),
    }
  end,
})

-- Visibility -------------------------------------------------------------------------------------------

-- Whether the ring shows, and whether it stands in the middle of the screen instead of at the cursor.
-- rules: the settings (the five yes/no rules, `mouselook`); state: combat, instance, target, mounted,
-- vehicle, mouselook (booleans read from the game by the host).
function CU.Visible(rules, state)
  rules = type(rules) == "table" and rules or {}
  state = type(state) == "table" and state or {}
  if rules.combatOnly == true and state.combat ~= true then
    return false, false
  end
  if rules.instanceOnly == true and state.instance ~= true then
    return false, false
  end
  if rules.needsTarget == true and state.target ~= true then
    return false, false
  end
  if rules.hideMounted == true and state.mounted == true then
    return false, false
  end
  if rules.hideInVehicle == true and state.vehicle == true then
    return false, false
  end
  if state.mouselook == true then
    local mode = oneOf(rules.mouselook, CU.MOUSELOOK, CU.DEFAULTS.mouselook)
    if mode == "hide" then
      return false, false
    end
    return true, mode == "center"
  end
  return true, false
end

-- Mouselook with hysteresis: Start and Stop come from the game's events, Active is true once the start is
-- older than `delay` seconds. `clock` returns seconds (the game's time in the host, a fake in tests).
-- Resync(on) takes the game's own answer after a loading screen, where an event can be lost.
function CU.NewMouselook(clock, delay)
  local m = { delay = finite(delay) and delay or CU.HYSTERESIS }
  local since
  function m.Start()
    if since == nil then
      since = clock()
    end
  end
  function m.Stop()
    since = nil
  end
  function m.Resync(on)
    if on then
      m.Start()
    else
      since = nil
    end
  end
  function m.Looking()
    return since ~= nil
  end
  function m.Active()
    return since ~= nil and clock() - since >= m.delay
  end
  return m
end

-- Position ---------------------------------------------------------------------------------------------

-- Offsets of the center of the ring frame from the bottom left of the screen, in UI units, rounded to
-- whole numbers. cursorX and cursorY are screen pixels (GetCursorPosition), `scale` the effective scale
-- of the parent, dx and dy the distance from the hotspot of the layout to the center of its canvas
-- (to the right and up). nil for a cursor position that is not a number.
function CU.Place(cursorX, cursorY, scale, dx, dy)
  if not (finite(cursorX) and finite(cursorY)) then
    return nil
  end
  scale = finite(scale) and scale > 0 and scale or 1
  dx = finite(dx) and dx or 0
  dy = finite(dy) and dy or 0
  return math.floor(cursorX / scale + dx + 0.5), math.floor(cursorY / scale + dy + 0.5)
end

-- Distances from the hotspot of a layout to the center of its canvas for CU.Place: right and up.
function CU.HotOffset(layout)
  local canvas = layout.canvas
  local hx, hy = CL.HotPoint(layout)
  return canvas.w / 2 - hx, hy - canvas.h / 2
end

-- Presets ----------------------------------------------------------------------------------------------

local function el(id, kind, w, h, over)
  local props = CU.NewProps(kind)
  for k, v in pairs(over or {}) do
    props[k] = v
  end
  local label = "cursor.el." .. id
  return {
    id = id,
    type = kind,
    name = L[label] ~= label and L[label] or L["cursor.type." .. kind],
    point = "CENTER",
    x = 0,
    y = 0,
    w = w,
    h = h,
    visible = true,
    props = CU.Props(kind, props),
  }
end

-- A symmetric cursor canvas without background and border, the elements stacked in the order given.
local function build(id, elements)
  for i, element in ipairs(elements) do
    element.z = i
  end
  return CL.Validate({
    id = id,
    name = "",
    canvas = { kind = "cursor", w = 256, h = 256, bg = "000000", bgAlpha = 0, symmetric = true },
    elements = elements,
  })
end

local BUILDERS = {
  standard = function()
    return build("standard", { el("ring", "ring", 64, 64, { thickness = 1, alpha = 0.85 }) })
  end,
  crosshair = function()
    return build("crosshair", {
      el("cross", "cross", 56, 56, { thickness = 2, gap = 12, alpha = 0.9 }),
      el("ring", "ring", 20, 20, { thickness = 1, alpha = 0.9 }),
    })
  end,
  double = function()
    return build("double", {
      el("ring", "ring", 72, 72, { thickness = 1, color = "ffd24a", alpha = 0.9 }),
      el("ring2", "ring", 40, 40, { thickness = 1, color = "5fd3d8", alpha = 0.9 }),
    })
  end,
  dot = function()
    return build("dot", { el("dot", "shape", 32, 32, { shape = "soft-dot", alpha = 0.9 }) })
  end,
}

CU.PRESET_IDS = { "standard", "crosshair", "double", "dot" }

-- Adds a preset after the built-in ones: builder(el, build) returns a layout, el and build being the helpers
-- above (el(id, kind, w, h, props), build(id, elements)). Its name is the key cursor.preset.<id>.
function CU.RegisterPreset(id, builder)
  if type(id) ~= "string" or type(builder) ~= "function" then
    return false
  end
  if not BUILDERS[id] then
    CU.PRESET_IDS[#CU.PRESET_IDS + 1] = id
  end
  BUILDERS[id] = builder
  return true
end

-- Fresh layout of a preset, nil for an unknown id.
function CU.Preset(id)
  local make = BUILDERS[id]
  return make and make(el, build) or nil
end

-- All presets as the editor lists them: { id, name (language of now), layout }.
function CU.Presets()
  local out = {}
  for _, id in ipairs(CU.PRESET_IDS) do
    local layout = CU.Preset(id)
    layout.name = L["cursor.preset." .. id]
    out[#out + 1] = { id = id, name = layout.name, layout = layout }
  end
  return out
end
