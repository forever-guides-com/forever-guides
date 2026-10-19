-- Mouse trail and click effect of the cursor ring (ns.CursorTrail): two element types for the layout
-- editor, `trail` (short-lived particles or lightning behind the cursor) and `click` (an expanding ring
-- at the cursor on a mouse click). The engine animates everything: each particle is a pooled texture
-- (or line) with an AnimationGroup (Scale + Alpha), so Lua only runs when a particle is placed.
-- Budgets:
--   trail: one OnUpdate on the element frame, only while the host shows it. It adds the frame time and
--     samples the cursor at a fixed 30 Hz (a hitch is cut at MAX_CATCH_UP, one sample covers it, the
--     distance between two samples is filled with at most MAX_PER_STEP particles). The pool is a ring of
--     at most `cap` slots (hard cap 150), the oldest slot is reused, so memory is bounded and nothing is
--     allocated while it runs. Lightning segments take one slot each.
--   click: no timer. GLOBAL_MOUSE_DOWN places one of CLICK_POOL pooled rings. Whether the event also
--     fires for the 3D world is not known, so a polling OnUpdate on the same watcher frame covers the
--     buttons until a click over the world has come through the event.
-- Both do nothing while the host does not show the element, and nothing in the editor preview except the
-- static sample and the optional simulation source.
local _, ns = ...
local U, CU, E, A, S = ns.U, ns.CursorLogic, ns.CursorElements, ns.CursorAssets, ns.CursorSim

local T = {}
ns.CursorTrail = T

T.STEP = 1 / 30
T.MAX_CATCH_UP = 0.25
T.MAX_PER_STEP = 4
T.CAP_MIN, T.CAP_DEFAULT, T.CAP_HARD = 8, 64, 150
T.CLICK_POOL = 3
T.SIM_PERIOD = 1.2
T.STYLES = { "sprites", "bolt" }
T.SHAPES = { "trail-dot", "trail-diamond", "trail-star4", "soft-dot", "spark", "ring" }
T.CLICK_SHAPES = { "ring", "soft-ring", "soft-dot" }
T.PREVIEW_COUNT = 6

-- Preview path: a loop through the element box, the sample points sit a fixed phase apart on it.
local STATIC_PHASE, PHASE_GAP, SIM_SPEED = 0.9, 0.3, 2.2
local WHITE = "Interface\\Buttons\\WHITE8X8"

ns.AddLocale("enUS", {
  ["cursor.type.trail"] = "Trail",
  ["cursor.type.click"] = "Click effect",
  ["cursor.type.trail.desc"] = "Short-lived particles or bolts that follow the mouse pointer while you move it.",
  ["cursor.type.click.desc"] = "A ring that grows at the mouse pointer when you click the left or right mouse button.",
  ["cursor.preset.trail"] = "Ring with trail",
  ["cursor.preset.click"] = "Ring with click effect",
  ["cursor.el.trail"] = "Trail",
  ["cursor.el.click"] = "Click effect",
  ["cursor.fx.ring"] = "Ring",
  ["cursor.trail.shape.ring"] = "Thin ring",
  ["cursor.trail.style.sprites"] = "Particles",
  ["cursor.trail.style.bolt"] = "Lightning",
  ["cursor.trail.sizeStart"] = "Size at start",
  ["cursor.trail.sizeEnd"] = "Size at end",
  ["cursor.trail.lifetime"] = "Lifetime",
  ["cursor.trail.spacing"] = "Spacing",
  ["cursor.trail.colorStart"] = "Start color",
  ["cursor.trail.colorEnd"] = "End color",
  ["cursor.trail.limits"] = "Limits",
  ["cursor.trail.cap"] = "Particle limit",
  ["cursor.trail.bolt"] = "Lightning",
  ["cursor.trail.segments"] = "Segments",
  ["cursor.trail.jitter"] = "Jitter",
  ["cursor.trail.width"] = "Width",
  ["cursor.click.duration"] = "Duration",
  ["cursor.click.colorLeft"] = "Left button color",
  ["cursor.click.colorRight"] = "Right button color",
  ["cursor.click.overUI"] = "Also over the interface",
})
ns.AddLocale("deDE", {
  ["cursor.type.trail"] = "Spur",
  ["cursor.type.click"] = "Klick-Effekt",
  ["cursor.type.trail.desc"] = "Kurzlebige Teilchen oder Blitze, die dem Mauszeiger folgen, solange du ihn bewegst.",
  ["cursor.type.click.desc"] = "Ein Ring, der am Mauszeiger wächst, wenn du die linke oder rechte Maustaste klickst.",
  ["cursor.preset.trail"] = "Ring mit Spur",
  ["cursor.preset.click"] = "Ring mit Klick-Effekt",
  ["cursor.el.trail"] = "Spur",
  ["cursor.el.click"] = "Klick-Effekt",
  ["cursor.fx.ring"] = "Ring",
  ["cursor.trail.shape.ring"] = "Dünner Ring",
  ["cursor.trail.style.sprites"] = "Teilchen",
  ["cursor.trail.style.bolt"] = "Blitz",
  ["cursor.trail.sizeStart"] = "Größe am Anfang",
  ["cursor.trail.sizeEnd"] = "Größe am Ende",
  ["cursor.trail.lifetime"] = "Lebensdauer",
  ["cursor.trail.spacing"] = "Abstand",
  ["cursor.trail.colorStart"] = "Startfarbe",
  ["cursor.trail.colorEnd"] = "Endfarbe",
  ["cursor.trail.limits"] = "Grenzen",
  ["cursor.trail.cap"] = "Teilchen-Limit",
  ["cursor.trail.bolt"] = "Blitz",
  ["cursor.trail.segments"] = "Segmente",
  ["cursor.trail.jitter"] = "Streuung",
  ["cursor.trail.width"] = "Breite",
  ["cursor.click.duration"] = "Dauer",
  ["cursor.click.colorLeft"] = "Farbe linke Maustaste",
  ["cursor.click.colorRight"] = "Farbe rechte Maustaste",
  ["cursor.click.overUI"] = "Auch über der Oberfläche",
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

-- Hundredths, so a slider step never leaves float noise in the saved value.
local function decimal(v, default, lo, hi)
  return finite(v) and U.clamp(math.floor(v * 100 + 0.5) / 100, lo, hi) or default
end

local function opacity(v, default)
  return finite(v) and U.clamp(v, 0, 1) or default
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

-- Data -------------------------------------------------------------------------------------------------

CU.Register("trail", {
  defaults = {
    style = "sprites",
    shape = "trail-dot",
    sizeStart = 14,
    sizeEnd = 2,
    lifetime = 0.5,
    spacing = 12,
    colorStart = "ffd24a",
    colorEnd = "e8562a",
    alphaStart = 0.9,
    alphaEnd = 0,
    blend = "ADD",
    cap = T.CAP_DEFAULT,
    segments = 4,
    jitter = 8,
    width = 2,
  },
  size = { 96, 48 },
  clean = function(raw, d)
    return {
      style = oneOf(raw.style, T.STYLES, d.style),
      shape = oneOf(raw.shape, T.SHAPES, d.shape),
      sizeStart = whole(raw.sizeStart, d.sizeStart, 1, 64),
      sizeEnd = whole(raw.sizeEnd, d.sizeEnd, 1, 64),
      lifetime = decimal(raw.lifetime, d.lifetime, 0.1, 2),
      spacing = whole(raw.spacing, d.spacing, 2, 64),
      colorStart = hex(raw.colorStart, d.colorStart),
      colorEnd = hex(raw.colorEnd, d.colorEnd),
      alphaStart = opacity(raw.alphaStart, d.alphaStart),
      alphaEnd = opacity(raw.alphaEnd, d.alphaEnd),
      blend = oneOf(raw.blend, CU.BLENDS, d.blend),
      cap = whole(raw.cap, d.cap, T.CAP_MIN, T.CAP_HARD),
      segments = whole(raw.segments, d.segments, 3, 6),
      jitter = whole(raw.jitter, d.jitter, 0, 32),
      width = whole(raw.width, d.width, 1, 8),
    }
  end,
})

CU.Register("click", {
  defaults = {
    shape = "ring",
    thickness = 2,
    sizeStart = 8,
    sizeEnd = 40,
    duration = 0.35,
    colorLeft = "ffd24a",
    colorRight = "5fd3d8",
    alpha = 0.9,
    blend = "ADD",
    overUI = false,
  },
  size = { 64, 64 },
  clean = function(raw, d)
    return {
      shape = oneOf(raw.shape, T.CLICK_SHAPES, d.shape),
      thickness = whole(raw.thickness, d.thickness, 1, 16),
      sizeStart = whole(raw.sizeStart, d.sizeStart, 1, 128),
      sizeEnd = whole(raw.sizeEnd, d.sizeEnd, 1, 128),
      duration = decimal(raw.duration, d.duration, 0.15, 1),
      colorLeft = hex(raw.colorLeft, d.colorLeft),
      colorRight = hex(raw.colorRight, d.colorRight),
      alpha = opacity(raw.alpha, d.alpha),
      blend = oneOf(raw.blend, CU.BLENDS, d.blend),
      overUI = raw.overUI == true,
    }
  end,
})

-- True when two repaired prop tables hold the same values.
function T.Same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  for k, v in pairs(a) do
    if b[k] ~= v then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

-- Fixed step and spawning (no WoW API) -------------------------------------------------------------------

-- Number of fixed steps `elapsed` seconds add to the accumulator st.acc; a hitch is cut at MAX_CATCH_UP so
-- the loop below stays short.
function T.Steps(st, elapsed)
  local acc = st.acc + (finite(elapsed) and elapsed or 0)
  if acc > T.MAX_CATCH_UP then
    acc = T.MAX_CATCH_UP
  end
  local n = 0
  while acc >= T.STEP do
    acc = acc - T.STEP
    n = n + 1
  end
  st.acc = acc
  return n
end

-- Walks from the last anchor st.x, st.y to the point (x, y) and calls emit(owner, nx, ny, px, py) for every
-- `spacing` px on the way (new point, previous point). At most MAX_PER_STEP points per call; a longer way
-- (a jump of the cursor) moves the anchor to the end point instead of filling the gap. gate(owner) is asked
-- only when something would be placed: false drops the way and re-anchors (mouselook). Returns the number
-- of points placed.
function T.Advance(pos, x, y, spacing, emit, owner, gate)
  if pos.x == nil then
    pos.x, pos.y = x, y
    return 0
  end
  local dx, dy = x - pos.x, y - pos.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < spacing then
    return 0
  end
  if gate and not gate(owner) then
    pos.x, pos.y = x, y
    return 0
  end
  local steps = math.floor(dist / spacing)
  local n = math.min(steps, T.MAX_PER_STEP)
  local ux, uy = dx / dist, dy / dist
  local px, py = pos.x, pos.y
  local ax, ay = px, py
  for i = 1, n do
    local nx, ny = ax + ux * spacing * i, ay + uy * spacing * i
    emit(owner, nx, ny, px, py)
    px, py = nx, ny
  end
  if steps > n then
    pos.x, pos.y = x, y
  else
    pos.x, pos.y = px, py
  end
  return n
end

-- Position of the sample point of phase s on the preview loop, in a w by h box around the center.
function T.PathPoint(s, w, h)
  return math.sin(s) * w * 0.4, math.sin(2 * s) * h * 0.3
end

-- Game readings ------------------------------------------------------------------------------------------

-- The cursor in UI units of UIParent, nil when the client gives no usable position.
local function cursorPoint()
  local read = rawget(_G, "GetCursorPosition")
  if type(read) ~= "function" then
    return nil
  end
  local x, y = read()
  local scale = UIParent:GetEffectiveScale()
  if not (finite(x) and finite(y) and finite(scale) and scale > 0) then
    return nil
  end
  return x / scale, y / scale
end

-- The host's own mouselook answer (ns.Cursor.State().mouselook, after its hysteresis). The copy it makes is
-- taken only when a particle would be placed.
function T.Looking()
  local cursor = ns.Cursor
  return type(cursor) == "table" and type(cursor.State) == "function" and cursor.State().mouselook == true
end

local function notLooking()
  return not T.Looking()
end

-- True when the mouse is over the 3D world (nothing of the interface under it). Without a way to ask, the
-- answer is yes.
function T.OverWorld()
  local world = rawget(_G, "WorldFrame")
  local foci = rawget(_G, "GetMouseFoci")
  if type(foci) == "function" then
    local list = foci()
    return type(list) == "table" and list[1] == world
  end
  local legacy = rawget(_G, "GetMouseFocus")
  if type(legacy) == "function" then
    return legacy() == world
  end
  return true
end

local function canLines()
  return ns.can ~= nil and ns.can.lineObject == true
end

-- Engine animated objects ---------------------------------------------------------------------------------

-- A texture or line with a group that scales (textures) and fades it; it hides itself when the group ends.
local function newFx(parent, line, layer)
  local obj = line and parent:CreateLine(nil, layer) or parent:CreateTexture(nil, layer)
  local group = obj:CreateAnimationGroup()
  -- The final alpha holds until OnFinished hides the object, so the last frame does not flash.
  group:SetToFinalAlpha(true)
  local alpha = group:CreateAnimation("Alpha")
  alpha:SetOrder(1)
  alpha:SetSmoothing("NONE")
  local scale
  if not line then
    scale = group:CreateAnimation("Scale")
    scale:SetOrder(1)
    scale:SetOrigin("CENTER", 0, 0)
  end
  group:SetScript("OnFinished", function()
    obj:Hide()
  end)
  obj:Hide()
  return { obj = obj, group = group, alpha = alpha, scale = scale, line = line, ver = -1 }
end

local function stopFx(fx)
  fx.group:Stop()
  fx.obj:Hide()
end

local function restart(fx)
  fx.group:Stop()
  fx.obj:Show()
  fx.group:Play()
end

-- Duration, fade and growth of an object; sizes are px, `base` the px size of the texture itself.
local function timing(fx, duration, a0, a1, s0, s1, base, smoothing)
  fx.alpha:SetDuration(duration)
  fx.alpha:SetFromAlpha(a0)
  fx.alpha:SetToAlpha(a1)
  if fx.scale then
    fx.scale:SetDuration(duration)
    fx.scale:SetSmoothing(smoothing)
    fx.scale:SetScaleFrom(s0 / base, s0 / base)
    fx.scale:SetScaleTo(s1 / base, s1 / base)
  end
end

-- Color of a line: a color texture where the client has it, the white pixel tinted otherwise.
local function lineColor(line, r, g, b, a)
  if ns.can.lineColorTexture then
    line:SetColorTexture(r, g, b, a)
  else
    line:SetTexture(WHITE)
    line:SetVertexColor(r, g, b, a)
  end
end

local function tint(fx, color, blend)
  local r, g, b = U.hex(color)
  if fx.line then
    lineColor(fx.obj, r, g, b, 1)
  else
    fx.obj:SetVertexColor(r, g, b, 1)
  end
  fx.obj:SetBlendMode(blend)
end

-- File of a trail or click shape at `size` px; the ring is the thin (trail) or chosen (click) circle.
local function stemOf(shape, size, thickness)
  if shape == "ring" then
    return A.NearestStroke("circle", thickness, size)
  end
  return shape
end

-- Trail runtime ------------------------------------------------------------------------------------------

local function trailState(frame)
  local st = frame.fgTrail
  if not st then
    st = {
      frame = frame,
      acc = 0,
      ver = 0,
      slots = {},
      cursor = 1,
      pos = {},
      bx = {},
      by = {},
      random = math.random,
      layers = 1,
      reduce = false,
    }
    frame.fgTrail = st
  end
  return st
end

local SLOT_KINDS = { "sprite", "bolt" }

local function eachFx(st, fn)
  for _, slot in pairs(st.slots) do
    for _, kind in ipairs(SLOT_KINDS) do
      for _, fx in ipairs(slot[kind] or {}) do
        fn(fx)
      end
    end
  end
end

local function stopAll(st)
  eachFx(st, stopFx)
end

-- Sets the layer of a slot object: role 0 is the only layer, 1 the start color fading out, 2 the end color
-- fading in. Two layers stand in for a color that changes over the life: the engine only fades alpha.
local function configure(fx, st, role)
  local cfg = st.cfg
  local a0, a1 = cfg.alphaStart, cfg.alphaEnd
  if role == 1 then
    a1 = 0
  elseif role == 2 then
    a0 = 0
  end
  tint(fx, role == 2 and cfg.colorEnd or cfg.colorStart, cfg.blend)
  if fx.line then
    fx.obj:SetThickness(cfg.width)
    timing(fx, cfg.lifetime, a0, a1, 1, 1, 1, "NONE")
    return
  end
  local base = math.max(cfg.sizeStart, cfg.sizeEnd)
  fx.obj:SetTexture(E.Texture(stemOf(cfg.shape, base, 1)))
  fx.obj:SetSize(base, base)
  timing(fx, cfg.lifetime, a0, a1, cfg.sizeStart, cfg.sizeEnd, base, "NONE")
end

-- The next slot of the ring of at most cap slots; the oldest one is reused when all are in use.
local function takeSlot(st)
  local i = st.cursor
  local slot = st.slots[i]
  if not slot then
    slot = { ver = -1 }
    st.slots[i] = slot
  end
  st.cursor = i % st.cfg.cap + 1
  return slot
end

-- The objects of a slot for the current style, created on first use and set again when the props changed.
local function prepare(slot, st)
  local kind = st.bolt and "bolt" or "sprite"
  local set = slot[kind]
  if not set then
    set = {}
    slot[kind] = set
  end
  local want = st.layers
  for i = #set + 1, want do
    set[i] = newFx(st.frame, st.bolt, "ARTWORK")
  end
  if slot.ver ~= st.ver then
    for i, fx in ipairs(set) do
      if i <= want then
        configure(fx, st, want == 1 and 0 or i)
      else
        stopFx(fx)
      end
    end
    slot.ver = st.ver
  end
  return set, want
end

local function emitSprite(st, x, y)
  local set, want = prepare(takeSlot(st), st)
  for i = 1, want do
    local obj = set[i].obj
    obj:ClearAllPoints()
    obj:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    restart(set[i])
  end
end

-- One flash from the previous point to the new one: `segments` lines, the points between them pushed
-- sideways by up to `jitter` px.
local function emitBolt(st, x, y, px, py)
  local cfg = st.cfg
  local count = cfg.segments
  local dx, dy = x - px, y - py
  local len = math.sqrt(dx * dx + dy * dy)
  if len <= 0 then
    return
  end
  local nx, ny = -dy / len, dx / len
  local bx, by = st.bx, st.by
  for k = 0, count do
    local t = k / count
    local off = (k > 0 and k < count) and (st.random() * 2 - 1) * cfg.jitter or 0
    bx[k], by[k] = px + dx * t + nx * off, py + dy * t + ny * off
  end
  for j = 1, count do
    local set, want = prepare(takeSlot(st), st)
    for i = 1, want do
      local obj = set[i].obj
      obj:SetStartPoint("BOTTOMLEFT", UIParent, bx[j - 1], by[j - 1])
      obj:SetEndPoint("BOTTOMLEFT", UIParent, bx[j], by[j])
      restart(set[i])
    end
  end
end

-- Takes the repaired props: a changed look bumps the version (slots set themselves again on next use), a
-- changed style or a smaller pool puts what is in flight away.
local function applyTrail(st, cfg, reduce)
  local old = st.cfg
  st.reduce = reduce == true
  if old and T.Same(old, cfg) then
    return
  end
  local bolt = cfg.style == "bolt" and canLines()
  if old and (bolt ~= st.bolt or cfg.cap < old.cap) then
    stopAll(st)
    st.cursor = 1
  end
  st.cfg = cfg
  st.bolt = bolt
  st.emit = bolt and emitBolt or emitSprite
  st.layers = cfg.colorStart ~= cfg.colorEnd and 2 or 1
  st.ver = st.ver + 1
  st.pos.x = nil
end

local function trailTick(st)
  if st.reduce then
    st.pos.x = nil
    return
  end
  local x, y = cursorPoint()
  if x then
    T.Advance(st.pos, x, y, st.cfg.spacing, st.emit, st, notLooking)
  end
end

local function onTrailUpdate(frame, elapsed)
  local st = frame.fgTrail
  if st and T.Steps(st, elapsed) > 0 then
    trailTick(st)
  end
end

-- Preview ---------------------------------------------------------------------------------------------------

-- The n-th preview texture or line of a frame, created on first use.
local function previewObject(frame, kind, i)
  local fx = frame.fgFx
  if not fx then
    fx = { texture = {}, line = {} }
    frame.fgFx = fx
  end
  local list = fx[kind]
  if not list[i] then
    list[i] = kind == "line" and frame:CreateLine(nil, "ARTWORK") or frame:CreateTexture(nil, "ARTWORK")
  end
  return list[i]
end

-- Hides the preview objects from index `from` on.
local function hidePreview(frame, kind, from)
  local list = frame.fgFx and frame.fgFx[kind]
  for i = from, list and #list or 0 do
    list[i]:Hide()
  end
end

-- Width and height of an element frame, with the type size where the frame has none yet.
local function boxOf(frame, kind)
  local w, h = frame:GetWidth(), frame:GetHeight()
  local size = CU.Size(kind)
  return finite(w) and w > 1 and w or size[1], finite(h) and h > 1 and h or size[2]
end

local function mix(a, b, t)
  local r1, g1, b1 = U.hex(a)
  local r2, g2, b2 = U.hex(b)
  return lerp(r1, r2, t), lerp(g1, g2, t), lerp(b1, b2, t)
end

-- A static fan of sample points along a curve, or the same points moving along a loop when the editor
-- simulation plays (sim.trailT = seconds). Newest point first, age 0 to 1.
local function drawTrailPreview(frame, cfg, sim)
  local w, h = boxOf(frame, "trail")
  local phase = sim and finite(sim.trailT) and sim.trailT * SIM_SPEED or STATIC_PHASE
  if cfg.style == "bolt" and canLines() then
    local count = cfg.segments
    local px, py = T.PathPoint(phase, w, h)
    for j = 1, count do
      local x, y = T.PathPoint(phase - j * PHASE_GAP * 1.5, w, h)
      local age = (j - 0.5) / count
      local off = (j % 2 == 0 and 1 or -1) * cfg.jitter * 0.5
      local line = previewObject(frame, "line", j)
      line:SetThickness(cfg.width)
      line:SetStartPoint("CENTER", frame, px, py)
      line:SetEndPoint("CENTER", frame, x, y + off)
      local r, g, b = mix(cfg.colorStart, cfg.colorEnd, age)
      lineColor(line, r, g, b, lerp(cfg.alphaStart, cfg.alphaEnd, age))
      line:SetBlendMode(cfg.blend)
      line:Show()
      px, py = x, y + off
    end
    hidePreview(frame, "line", count + 1)
    hidePreview(frame, "texture", 1)
    return
  end
  local last = T.PREVIEW_COUNT - 1
  for i = 0, last do
    local age = i / last
    local size = lerp(cfg.sizeStart, cfg.sizeEnd, age)
    local x, y = T.PathPoint(phase - i * PHASE_GAP, w, h)
    local tex = previewObject(frame, "texture", i + 1)
    tex:SetTexture(E.Texture(stemOf(cfg.shape, size, 1)))
    tex:SetSize(size, size)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", frame, "CENTER", x, y)
    local r, g, b = mix(cfg.colorStart, cfg.colorEnd, age)
    tex:SetVertexColor(r, g, b, lerp(cfg.alphaStart, cfg.alphaEnd, age))
    tex:SetBlendMode(cfg.blend)
    tex:Show()
  end
  hidePreview(frame, "texture", T.PREVIEW_COUNT + 1)
  hidePreview(frame, "line", 1)
end

-- One ring of the click preview at progress p (0 to 1) of the effect.
local function clickRing(frame, i, cfg, p, color)
  local size = lerp(cfg.sizeStart, cfg.sizeEnd, p)
  local tex = previewObject(frame, "texture", i)
  tex:SetTexture(E.Texture(stemOf(cfg.shape, size, cfg.thickness)))
  tex:SetSize(size, size)
  tex:ClearAllPoints()
  tex:SetPoint("CENTER", frame, "CENTER", 0, 0)
  local r, g, b = U.hex(color)
  tex:SetVertexColor(r, g, b, cfg.alpha * (1 - p))
  tex:SetBlendMode(cfg.blend)
  tex:Show()
end

-- Static: an inner ring in the left color and an outer one in the right color. Simulated: one ring that
-- grows and fades, left and right in turn (sim.clickT = seconds into the period, sim.clickButton).
local function drawClickPreview(frame, cfg, sim)
  hidePreview(frame, "line", 1)
  local at = sim and sim.clickT
  if not finite(at) then
    clickRing(frame, 1, cfg, 0.35, cfg.colorLeft)
    clickRing(frame, 2, cfg, 0.8, cfg.colorRight)
    return
  end
  local p = at / cfg.duration
  if p > 1 then
    hidePreview(frame, "texture", 1)
    return
  end
  clickRing(frame, 1, cfg, p, sim.clickButton == "right" and cfg.colorRight or cfg.colorLeft)
  hidePreview(frame, "texture", 2)
end

-- Trail element -------------------------------------------------------------------------------------------

local function renderTrail(frame, element, ctx)
  local cfg = CU.Props("trail", element.props)
  if ctx and ctx.editor then
    drawTrailPreview(frame, cfg, ctx.sim)
    return
  end
  hidePreview(frame, "texture", 1)
  hidePreview(frame, "line", 1)
  applyTrail(trailState(frame), cfg, ctx and ctx.reduceMotion == true)
end

local function driveTrail(frame, _, ctx)
  local st = frame.fgTrail
  if (ctx and ctx.editor) or not st then
    return
  end
  st.acc = 0
  st.pos.x = nil
  frame:SetScript("OnUpdate", onTrailUpdate)
end

local function releaseTrail(frame)
  frame:SetScript("OnUpdate", nil)
  local st = frame.fgTrail
  if st then
    stopAll(st)
    st.pos.x = nil
    st.acc = 0
    st.cursor = 1
  end
  hidePreview(frame, "texture", 1)
  hidePreview(frame, "line", 1)
end

-- Click runtime ---------------------------------------------------------------------------------------------

local function clickState(frame)
  local st = frame.fgClick
  if not st then
    st = { frame = frame, pool = {}, cursor = 1, ver = 0, left = false, right = false, reduce = false }
    frame.fgClick = st
  end
  return st
end

local function configureClick(fx, st)
  local cfg = st.cfg
  local base = math.max(cfg.sizeStart, cfg.sizeEnd)
  fx.obj:SetTexture(E.Texture(stemOf(cfg.shape, base, cfg.thickness)))
  fx.obj:SetSize(base, base)
  fx.obj:SetBlendMode(cfg.blend)
  timing(fx, cfg.duration, cfg.alpha, 0, cfg.sizeStart, cfg.sizeEnd, base, "OUT")
  fx.ver = st.ver
end

-- Plays one pooled ring at the cursor in the color of the button; the oldest ring is reused on a burst.
local function playClick(st, button)
  local x, y = cursorPoint()
  if not x then
    return
  end
  local cfg = st.cfg
  local i = st.cursor
  local fx = st.pool[i]
  if not fx then
    fx = newFx(st.frame, false, "OVERLAY")
    st.pool[i] = fx
  end
  st.cursor = i % T.CLICK_POOL + 1
  if fx.ver ~= st.ver then
    configureClick(fx, st)
  end
  local r, g, b = U.hex(button == "LeftButton" and cfg.colorLeft or cfg.colorRight)
  fx.obj:SetVertexColor(r, g, b, 1)
  fx.obj:ClearAllPoints()
  fx.obj:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
  restart(fx)
end

-- A press of `button`: the effect plays unless the host does not show it, motion is reduced, or the mouse
-- is over the interface (without the option). Returns true when the press was over the world.
local function press(st, button)
  if st.reduce or not st.cfg or not st.frame:IsVisible() then
    return false
  end
  local world = T.OverWorld()
  if world or st.cfg.overUI then
    playClick(st, button)
  end
  return world
end

local function onMouseDown(watcher, event, button)
  local st = watcher.fgClick
  if event ~= "GLOBAL_MOUSE_DOWN" or not st then
    return
  end
  if button ~= "LeftButton" and button ~= "RightButton" then
    return
  end
  -- The poll must not play this press again.
  if button == "LeftButton" then
    st.left = true
  else
    st.right = true
  end
  if press(st, button) then
    -- A click over the world came through the event: the poll is not needed any more.
    watcher:SetScript("OnUpdate", nil)
  end
end

-- Fallback: edges of the two buttons read every frame, until the event has proven itself.
local function pollButtons(watcher)
  local st = watcher.fgClick
  local left = IsMouseButtonDown("LeftButton") and true or false
  local right = IsMouseButtonDown("RightButton") and true or false
  local wasLeft, wasRight = st.left, st.right
  st.left, st.right = left, right
  if left and not wasLeft then
    press(st, "LeftButton")
  end
  if right and not wasRight then
    press(st, "RightButton")
  end
end

local function renderClick(frame, element, ctx)
  local cfg = CU.Props("click", element.props)
  if ctx and ctx.editor then
    drawClickPreview(frame, cfg, ctx.sim)
    return
  end
  hidePreview(frame, "texture", 1)
  local st = clickState(frame)
  st.reduce = ctx and ctx.reduceMotion == true or false
  if not (st.cfg and T.Same(st.cfg, cfg)) then
    st.cfg = cfg
    st.ver = st.ver + 1
  end
end

local function driveClick(frame, _, ctx)
  local st = frame.fgClick
  if (ctx and ctx.editor) or not st then
    return
  end
  local watcher = st.watcher
  if not watcher then
    watcher = CreateFrame("Frame", nil, frame)
    watcher:EnableMouse(false)
    watcher.fgClick = st
    st.watcher = watcher
  end
  st.left, st.right = false, false
  watcher:SetScript("OnEvent", onMouseDown)
  if type(rawget(_G, "IsMouseButtonDown")) == "function" then
    watcher:SetScript("OnUpdate", pollButtons)
  end
  watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
end

local function releaseClick(frame)
  local st = frame.fgClick
  if st and st.watcher then
    st.watcher:UnregisterAllEvents()
    st.watcher:SetScript("OnEvent", nil)
    st.watcher:SetScript("OnUpdate", nil)
  end
  if st then
    for _, fx in ipairs(st.pool) do
      stopFx(fx)
    end
    st.cursor = 1
  end
  hidePreview(frame, "texture", 1)
end

-- Panels --------------------------------------------------------------------------------------------------------

local function controls()
  return ns.CanvasEditor.Controls
end

local function newPanel(parent, kind, element, onChange, build)
  return controls().NewPanel(parent, {
    element = element,
    onChange = onChange,
    build = build,
    props = function(raw, current)
      return CU.Props(kind, raw, current and { current.w, current.h })
    end,
  })
end

local function slider(state, add, label, key, min, max, step, format, shown)
  local C = controls()
  add(
    C.Slider(state.panel, {
      label = label,
      min = min,
      max = max,
      step = step,
      get = function()
        return state.get(key)
      end,
      set = function(v)
        state.write(key, v)
      end,
      format = format,
    }),
    C.HEIGHT.slider,
    shown
  )
end

local function px(v)
  return v .. " px"
end

local function seconds(v)
  return string.format("%.2f s", v)
end

local function colorAlpha(state, add, label, colorKey, alphaKey)
  local C = controls()
  add(
    C.ColorAlpha(state.panel, {
      label = label,
      owner = state.owner(),
      default = "ffffff",
      get = function()
        return state.get(colorKey)
      end,
      alpha = function()
        return state.get(alphaKey)
      end,
      set = function(color, alpha)
        state.write(colorKey, color)
        state.write(alphaKey, alpha)
      end,
    }),
    C.HEIGHT.colorAlpha
  )
end

local function gallery(state, add, items, shown)
  local row = controls().Gallery(state.panel, {
    label = "cursor.panel.shape",
    items = items,
    resolve = E.Texture,
    get = function()
      return state.get("shape")
    end,
    set = function(value)
      state.write("shape", value)
    end,
  })
  add(row, row:GetHeight(), shown)
end

local function shapeKeys()
  local keys = {}
  for _, soft in ipairs(A.SOFT) do
    keys[soft.id] = soft.key
  end
  for _, mark in ipairs(A.TRAIL) do
    keys[mark.id] = mark.key
  end
  return keys
end

function T.TrailPanel(parent, element, onChange)
  return newPanel(parent, "trail", element, onChange, function(state, add)
    local C = controls()
    local function sprites()
      return not (state.get("style") == "bolt" and canLines())
    end
    local function bolt()
      return not sprites()
    end
    add(
      C.Choice(state.panel, {
        label = "cursor.panel.style",
        options = C.Choices(T.STYLES, "cursor.trail.style."),
        get = function()
          return state.get("style")
        end,
        set = function(value)
          state.write("style", value)
        end,
      }),
      C.HEIGHT.choice,
      canLines
    )
    local keys, items = shapeKeys(), {}
    for i, shape in ipairs(T.SHAPES) do
      local stem = shape == "ring" and A.RingStem("circle", 2) or shape
      items[i] = { shape, stem, shape == "ring" and "cursor.trail.shape.ring" or keys[shape] }
    end
    gallery(state, add, items, sprites)
    slider(state, add, "cursor.trail.sizeStart", "sizeStart", 1, 64, 1, px, sprites)
    slider(state, add, "cursor.trail.sizeEnd", "sizeEnd", 1, 64, 1, px, sprites)
    add(C.Section(state.panel, "cursor.trail.bolt"), C.HEIGHT.section, bolt)
    slider(state, add, "cursor.trail.width", "width", 1, 8, 1, px, bolt)
    slider(state, add, "cursor.trail.segments", "segments", 3, 6, 1, nil, bolt)
    slider(state, add, "cursor.trail.jitter", "jitter", 0, 32, 1, px, bolt)
    slider(state, add, "cursor.trail.lifetime", "lifetime", 0.1, 2, 0.05, seconds)
    slider(state, add, "cursor.trail.spacing", "spacing", 2, 64, 1, px)
    colorAlpha(state, add, "cursor.trail.colorStart", "colorStart", "alphaStart")
    colorAlpha(state, add, "cursor.trail.colorEnd", "colorEnd", "alphaEnd")
    C.ChoiceRow(state, add, "cursor.panel.blend", "blend", CU.BLENDS, "cursor.panel.blend.")
    add(C.Section(state.panel, "cursor.trail.limits"), C.HEIGHT.section)
    slider(state, add, "cursor.trail.cap", "cap", T.CAP_MIN, T.CAP_HARD, 1)
  end)
end

function T.ClickPanel(parent, element, onChange)
  return newPanel(parent, "click", element, onChange, function(state, add)
    local C = controls()
    local keys, items = shapeKeys(), {}
    for i, shape in ipairs(T.CLICK_SHAPES) do
      items[i] = {
        shape,
        shape == "ring" and A.RingStem("circle", 4) or shape,
        shape == "ring" and "cursor.fx.ring" or keys[shape],
      }
    end
    gallery(state, add, items)
    slider(state, add, "cursor.panel.thickness", "thickness", 1, 16, 1, px, function()
      return state.get("shape") == "ring"
    end)
    slider(state, add, "cursor.trail.sizeStart", "sizeStart", 1, 128, 1, px)
    slider(state, add, "cursor.trail.sizeEnd", "sizeEnd", 1, 128, 1, px)
    slider(state, add, "cursor.click.duration", "duration", 0.15, 1, 0.05, seconds)
    C.ColorRow(state, add, "cursor.click.colorLeft", "colorLeft", "ffd24a")
    C.ColorRow(state, add, "cursor.click.colorRight", "colorRight", "5fd3d8")
    slider(state, add, "canvas.opacity", "alpha", 0, 1, 0.05, function(v)
      return math.floor(v * 100 + 0.5) .. "%"
    end)
    C.ChoiceRow(state, add, "cursor.panel.blend", "blend", CU.BLENDS, "cursor.panel.blend.")
    C.ToggleRow(state, add, "cursor.click.overUI", "overUI")
  end)
end

-- Registration ---------------------------------------------------------------------------------------------------

E.Register("trail", { render = renderTrail, drive = driveTrail, release = releaseTrail, panel = T.TrailPanel })
E.Register("click", { render = renderClick, drive = driveClick, release = releaseClick, panel = T.ClickPanel })

local function setTrailTime(sim, _, t)
  sim.trailT = t
end

local function clearTrailTime(sim)
  sim.trailT = nil
end

-- One click per period, left and right in turn.
local function setClickTime(sim, _, t)
  local n = math.floor(t / T.SIM_PERIOD)
  sim.clickT = t - n * T.SIM_PERIOD
  sim.clickButton = n % 2 == 0 and "left" or "right"
end

local function clearClickTime(sim)
  sim.clickT, sim.clickButton = nil, nil
end

S.RegisterSource("trail", { step = setTrailTime, reset = clearTrailTime })
S.RegisterSource("click", { step = setClickTime, reset = clearClickTime })

-- Presets ----------------------------------------------------------------------------------------------------------

-- A ring with the trail and a ring with the click effect, listed after the built-in presets. The hook hands
-- over the element and canvas helpers of CursorLogic.
CU.RegisterPreset("trail", function(el, build)
  return build("trail", {
    el("ring", "ring", 48, 48, { thickness = 1, alpha = 0.85 }),
    el("trail", "trail", 96, 48),
  })
end)
CU.RegisterPreset("click", function(el, build)
  return build("click", {
    el("ring", "ring", 48, 48, { thickness = 1, alpha = 0.85 }),
    el("click", "click", 64, 64),
  })
end)
