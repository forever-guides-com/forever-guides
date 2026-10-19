-- The element types of the mouse cursor ring (ns.CursorElements) for CanvasRender and the layout editor:
-- ring, shape and cross. render only sets the appearance, so the editor can redraw at every drag step.
-- drive and release are the hooks for sources that run on their own (cooldowns, casts, swings): nothing
-- runs yet. A later type adds its data with CursorLogic.Register and its drawing with Register here.
-- Textures are white with the shape in the alpha channel and are tinted with SetVertexColor.
local _, ns = ...
local U, L, CU, A = ns.U, ns.L, ns.CursorLogic, ns.CursorAssets

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local E = {}
ns.CursorElements = E

-- The game's own disc, used when the client does not know a texture of the add-on.
E.DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

ns.AddLocale("enUS", {
  ["cursor.type.ring"] = "Ring",
  ["cursor.type.shape"] = "Shape",
  ["cursor.type.cross"] = "Crosshair",
  ["cursor.type.ring.desc"] = "A ring around the mouse pointer. Choose its shape, line thickness and color.",
  ["cursor.type.shape.desc"] = "A filled shape such as a soft dot or a spark at the mouse pointer.",
  ["cursor.type.cross.desc"] = "A crosshair at the mouse pointer, drawn with four arms or two lines.",
  ["cursor.panel.shape"] = "Shape",
  ["cursor.panel.innerFill"] = "Inner fill",
  ["cursor.panel.fillColor"] = "Fill color",
  ["cursor.panel.color"] = "Color",
  ["cursor.panel.rotation"] = "Rotation",
  ["cursor.panel.blend"] = "Blending",
  ["cursor.panel.blend.DISABLE"] = "Normal",
  ["cursor.panel.blend.ADD"] = "Glowing",
  ["cursor.panel.style"] = "Style",
  ["cursor.panel.style.arms"] = "Four arms",
  ["cursor.panel.style.lines"] = "Two lines",
  ["cursor.panel.thickness"] = "Thickness",
  ["cursor.panel.gap"] = "Gap in the middle",
})
ns.AddLocale("deDE", {
  ["cursor.type.ring"] = "Ring",
  ["cursor.type.shape"] = "Form",
  ["cursor.type.cross"] = "Fadenkreuz",
  ["cursor.type.ring.desc"] = "Ein Ring um den Mauszeiger. Wähle Form, Linienstärke und Farbe.",
  ["cursor.type.shape.desc"] = "Eine gefüllte Form am Mauszeiger, zum Beispiel ein weicher Punkt oder ein Funke.",
  ["cursor.type.cross.desc"] = "Ein Fadenkreuz am Mauszeiger, gezeichnet mit vier Armen oder zwei Linien.",
  ["cursor.panel.shape"] = "Form",
  ["cursor.panel.innerFill"] = "Innenfüllung",
  ["cursor.panel.fillColor"] = "Füllfarbe",
  ["cursor.panel.color"] = "Farbe",
  ["cursor.panel.rotation"] = "Drehung",
  ["cursor.panel.blend"] = "Überblendung",
  ["cursor.panel.blend.DISABLE"] = "Normal",
  ["cursor.panel.blend.ADD"] = "Leuchtend",
  ["cursor.panel.style"] = "Art",
  ["cursor.panel.style.arms"] = "Vier Arme",
  ["cursor.panel.style.lines"] = "Zwei Linien",
  ["cursor.panel.thickness"] = "Dicke",
  ["cursor.panel.gap"] = "Lücke in der Mitte",
})

-- Texture path of a stem: the file of the add-on when the client knows it, else the stock disc.
function E.Texture(stem)
  local path = A.Path(stem)
  if not path then
    return E.DISC
  end
  local resolved = ns.ResolveIcon(path, E.DISC)
  return resolved == ns.ICON_FALLBACK and E.DISC or resolved
end

-- Rendering --------------------------------------------------------------------------------------------

local function nothing() end

-- The texture of `field` over the whole frame, created once in `layer`.
local function layerTexture(frame, field, layer)
  local tex = frame[field]
  if not tex then
    tex = frame:CreateTexture(nil, layer)
    tex:SetAllPoints(frame)
    frame[field] = tex
  end
  return tex
end

-- A texture over the whole frame, tinted and blended; rotation in degrees.
local function paintTexture(tex, stem, color, alpha, blend, rotation)
  tex:SetTexture(E.Texture(stem))
  local r, g, b = U.hex(color)
  tex:SetVertexColor(r, g, b, alpha)
  -- The saved name "DISABLE" means normal drawing: the engine mode of that name draws opaque and ignores the
  -- alpha of the texture at full opacity (a ring would become a filled square), so it is drawn as BLEND.
  tex:SetBlendMode(blend == "DISABLE" and "BLEND" or blend)
  tex:SetRotation(math.rad(rotation))
  tex:Show()
end

-- Mean side of the frame in px, the size a ring thickness is measured against.
local function sideOf(frame, element)
  local w, h = frame:GetWidth(), frame:GetHeight()
  if not (finite(w) and finite(h) and w > 0 and h > 0) then
    w, h = element.w, element.h
  end
  return finite(w) and finite(h) and w > 0 and h > 0 and (w + h) / 2 or CU.Size("ring")[1]
end

local function renderRing(frame, element)
  local p = CU.Props("ring", element.props, { element.w, element.h })
  local stem = A.NearestStroke(p.shape, p.thickness, sideOf(frame, element))
  paintTexture(layerTexture(frame, "fgCursorTexture", "ARTWORK"), stem, p.color, p.alpha, p.blend, p.rotation)
  local fill = frame.fgCursorFill
  if p.fill then
    fill = layerTexture(frame, "fgCursorFill", "BACKGROUND")
    paintTexture(fill, A.RingStem(p.shape), p.fill, p.fillAlpha, "DISABLE", p.rotation)
  elseif fill then
    fill:Hide()
  end
end

local function renderShape(frame, element)
  local p = CU.Props("shape", element.props)
  paintTexture(layerTexture(frame, "fgCursorTexture", "ARTWORK"), p.shape, p.color, p.alpha, p.blend, 0)
  if frame.fgCursorFill then
    frame.fgCursorFill:Hide()
  end
end

local function armOf(frame, i)
  local arms = frame.fgCursorArms
  if not arms then
    arms = {}
    frame.fgCursorArms = arms
  end
  if not arms[i] then
    arms[i] = frame:CreateTexture(nil, "ARTWORK")
  end
  return arms[i]
end

-- Places one arm: it sits on `anchor` of the frame center shifted by (x, y) and is w by h; an arm without
-- length is hidden.
local function placeArm(tex, anchor, x, y, w, h, color, alpha)
  if w <= 0 or h <= 0 then
    tex:Hide()
    return
  end
  tex:ClearAllPoints()
  tex:SetPoint(anchor, tex:GetParent(), "CENTER", x, y)
  tex:SetSize(w, h)
  local r, g, b = U.hex(color)
  tex:SetColorTexture(r, g, b, alpha)
  tex:Show()
end

local function renderCross(frame, element)
  local p = CU.Props("cross", element.props)
  local w, h, t = frame:GetWidth(), frame:GetHeight(), p.thickness
  if p.style == "lines" then
    placeArm(armOf(frame, 1), "CENTER", 0, 0, w, t, p.color, p.alpha)
    placeArm(armOf(frame, 2), "CENTER", 0, 0, t, h, p.color, p.alpha)
    armOf(frame, 3):Hide()
    armOf(frame, 4):Hide()
    return
  end
  local halfW, halfH = math.max(0, w / 2 - p.gap), math.max(0, h / 2 - p.gap)
  placeArm(armOf(frame, 1), "RIGHT", -p.gap, 0, halfW, t, p.color, p.alpha)
  placeArm(armOf(frame, 2), "LEFT", p.gap, 0, halfW, t, p.color, p.alpha)
  placeArm(armOf(frame, 3), "BOTTOM", 0, p.gap, t, halfH, p.color, p.alpha)
  placeArm(armOf(frame, 4), "TOP", 0, -p.gap, t, halfH, p.color, p.alpha)
end

-- Editor panels ----------------------------------------------------------------------------------------

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

-- Color and opacity in one row; both values are written, the editor merges the two steps into one undo.
local function colorAlphaRow(state, add)
  local C = controls()
  add(
    C.ColorAlpha(state.panel, {
      label = "cursor.panel.color",
      owner = state.owner(),
      default = "ffffff",
      get = function()
        return state.get("color")
      end,
      alpha = function()
        return state.get("alpha")
      end,
      set = function(color, alpha)
        state.write("color", color)
        state.write("alpha", alpha)
      end,
    }),
    C.HEIGHT.colorAlpha
  )
end

-- The inner fill of a ring: colour and opacity, a colour of "none" switches it off.
local function innerFillRow(state, add)
  local C = controls()
  add(
    C.ColorAlpha(state.panel, {
      label = "cursor.panel.fillColor",
      owner = state.owner(),
      allowNil = true,
      get = function()
        return state.get("fill")
      end,
      alpha = function()
        return state.get("fillAlpha")
      end,
      set = function(color, alpha)
        state.write("fill", color)
        state.write("fillAlpha", alpha)
      end,
    }),
    C.HEIGHT.colorAlpha
  )
end

local function blendRow(state, add)
  controls().ChoiceRow(state, add, "cursor.panel.blend", "blend", CU.BLENDS, "cursor.panel.blend.")
end

local function galleryRow(state, add, items)
  local gallery = controls().Gallery(state.panel, {
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
  add(gallery, gallery:GetHeight())
end

local function sliderRow(state, add, label, key, min, max, step, format)
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
    C.HEIGHT.slider
  )
end

function E.RingPanel(parent, element, onChange)
  return newPanel(parent, "ring", element, onChange, function(state, add)
    local items = {}
    for i, shape in ipairs(A.SHAPES) do
      items[i] = { shape.id, A.RingStem(shape.id, 4), shape.key }
    end
    galleryRow(state, add, items)
    sliderRow(
      state,
      add,
      "cursor.panel.thickness",
      "thickness",
      CU.RING_THICKNESS_MIN,
      CU.RING_THICKNESS_MAX,
      1,
      function(v)
        return v .. " px"
      end
    )
    colorAlphaRow(state, add)
    sliderRow(state, add, "cursor.panel.rotation", "rotation", 0, 355, 5, function(v)
      return v .. "°"
    end)
    blendRow(state, add)
    add(controls().Section(state.panel, "cursor.panel.innerFill"), controls().HEIGHT.section)
    innerFillRow(state, add)
  end)
end

function E.ShapePanel(parent, element, onChange)
  return newPanel(parent, "shape", element, onChange, function(state, add)
    local keys = {}
    for _, shape in ipairs(A.SHAPES) do
      keys[A.RingStem(shape.id)] = shape.key
    end
    for _, soft in ipairs(A.SOFT) do
      keys[soft.id] = soft.key
    end
    local items = {}
    for i, stem in ipairs(CU.FILLS) do
      items[i] = { stem, stem, keys[stem] }
    end
    galleryRow(state, add, items)
    colorAlphaRow(state, add)
    blendRow(state, add)
  end)
end

function E.CrossPanel(parent, element, onChange)
  return newPanel(parent, "cross", element, onChange, function(state, add)
    controls().ChoiceRow(state, add, "cursor.panel.style", "style", CU.CROSS_STYLES, "cursor.panel.style.")
    sliderRow(state, add, "cursor.panel.thickness", "thickness", CU.THICKNESS_MIN, CU.THICKNESS_MAX, 1)
    sliderRow(state, add, "cursor.panel.gap", "gap", 0, CU.GAP_MAX, 1)
    colorAlphaRow(state, add)
  end)
end

-- Registry ---------------------------------------------------------------------------------------------

local defs = {}

-- The drawing half of an element type: def = { render, drive?, release?, panel, variants?, title? }. The data
-- half is CursorLogic.Register under the same name. variants and title go to the editor as they are (see
-- CanvasEditor: one Add entry per variant, the display title of an element).
function E.Register(kind, def)
  defs[kind] = def
end

E.Register("ring", { render = renderRing, drive = nothing, release = nothing, panel = E.RingPanel })
E.Register("shape", { render = renderShape, drive = nothing, release = nothing, panel = E.ShapePanel })
E.Register("cross", { render = renderCross, drive = nothing, release = nothing, panel = E.CrossPanel })

-- The `types` table of CanvasRender.Draw and the editor, built on every call so the labels follow the
-- language. Only types with both halves are listed.
function E.Types()
  local out = {}
  for _, kind in ipairs(CU.Kinds()) do
    local def = defs[kind]
    if def then
      out[kind] = {
        label = L["cursor.type." .. kind],
        desc = "cursor.type." .. kind .. ".desc",
        variants = def.variants,
        title = def.title,
        new = function()
          return CU.NewProps(kind)
        end,
        size = CU.Size(kind),
        render = def.render,
        drive = def.drive,
        release = def.release,
        panel = def.panel,
      }
    end
  end
  return out
end
