-- Draws a canvas layout into a frame: one child frame per element, placed by anchor, offset and
-- size, stacked by z, shown or hidden. The editor preview and the real window call the same
-- Draw, the element types paint themselves (types[type].render). Child frames are reused: a frame
-- of a removed element or of a changed type goes to a pool per type, so repeated calls create
-- nothing new once the layout has settled.
local _, ns = ...
local U, CL = ns.U, ns.CanvasLogic

local CR = {}
ns.CanvasRender = CR

-- Width and height of the frame of an element that sizes itself (w = 0) until its type measures it.
local AUTO = 1
local BORDER = 1
-- The side lines stop at the top and bottom lines: a corner is painted once, so a border that is not
-- fully opaque has no darker corner pixels.
local EDGES = {
  { "TOPLEFT", "TOPRIGHT", "w", 0, 0 },
  { "BOTTOMLEFT", "BOTTOMRIGHT", "w", 0, 0 },
  { "TOPLEFT", "BOTTOMLEFT", "h", -BORDER, BORDER },
  { "TOPRIGHT", "BOTTOMRIGHT", "h", -BORDER, BORDER },
}

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function number(v, default, lo, hi)
  return finite(v) and U.clamp(v, lo, hi) or default
end

-- The drawing state kept on the canvas frame: items = { [id] = { frame, type, def } }, pool of
-- frames per type, the background and the four border lines.
local function stateOf(canvas)
  local state = canvas.fgCanvas
  if not state then
    state = { items = {}, pool = {}, edges = {} }
    canvas.fgCanvas = state
  end
  return state
end

local function paint(texture, hex, alpha)
  local r, g, b = U.hex(hex)
  texture:SetColorTexture(r, g, b, alpha)
  texture:Show()
end

-- Background and border of the canvas from layout.canvas.
local function drawCanvas(canvas, state, cv)
  local def = CL.Kind(cv) == "cursor" and CL.CANVAS_CURSOR or CL.CANVAS
  local w = number(cv.w, def.w, CL.MIN_CANVAS, CL.MAX_CANVAS)
  local h = number(cv.h, def.h, CL.MIN_CANVAS, CL.MAX_CANVAS)
  canvas:SetSize(w, h)
  if not state.bg then
    state.bg = canvas:CreateTexture(nil, "BACKGROUND")
  end
  local border = type(cv.border) == "string" and cv.border:find("^#?%x%x%x%x%x%x$") and cv.border or nil
  -- The background stops inside the border: the border opacity does not mix with the background.
  local inset = border and BORDER or 0
  if state.inset ~= inset then
    state.inset = inset
    state.bg:ClearAllPoints()
    state.bg:SetPoint("TOPLEFT", canvas, "TOPLEFT", inset, -inset)
    state.bg:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -inset, inset)
  end
  local bg = type(cv.bg) == "string" and cv.bg:find("^#?%x%x%x%x%x%x$") and cv.bg or def.bg
  paint(state.bg, bg, number(cv.bgAlpha, def.bgAlpha, 0, 1))
  local borderAlpha = number(cv.borderAlpha, def.borderAlpha, 0, 1)
  for i, edge in ipairs(EDGES) do
    local line = state.edges[i]
    if border and not line then
      line = canvas:CreateTexture(nil, "BORDER")
      line:SetPoint(edge[1], canvas, edge[1], 0, edge[4])
      line:SetPoint(edge[2], canvas, edge[2], 0, edge[5])
      if edge[3] == "w" then
        line:SetHeight(BORDER)
      else
        line:SetWidth(BORDER)
      end
      state.edges[i] = line
    end
    if line then
      if border then
        paint(line, border, borderAlpha)
      else
        line:Hide()
      end
    end
  end
end

-- Hides a frame and puts it into the pool of its type.
local function release(state, id)
  local item = state.items[id]
  state.items[id] = nil
  if not item then
    return
  end
  if type(item.def) == "table" and type(item.def.release) == "function" then
    ns.Safe("canvas.release." .. item.type, item.def.release, item.frame)
  end
  item.frame:Hide()
  item.frame:ClearAllPoints()
  local pool = state.pool[item.type]
  if not pool then
    pool = {}
    state.pool[item.type] = pool
  end
  pool[#pool + 1] = item.frame
end

local function acquire(canvas, state, id, kind, def)
  local item = state.items[id]
  if item and item.type == kind then
    item.def = def
    return item.frame
  end
  release(state, id)
  local pool = state.pool[kind]
  local frame = pool and table.remove(pool) or CreateFrame("Frame", nil, canvas)
  state.items[id] = { frame = frame, type = kind, def = def }
  return frame
end

-- Draws `layout` into `canvas` (a frame). types = { [type] = { render(frame, element, ctx),
-- drive(frame, element, ctx), release(frame) (both optional) } }; an element of a type that is not in
-- `types` is not drawn but stays in the layout. render runs protected: an error of one type is recorded
-- and the other elements still draw. render only sets appearance: it runs on every redraw (the editor
-- redraws at every drag step), so it must not start timers, cooldowns or animations. drive runs once
-- after the first draw of a frame, and again after the frame was released, and starts such running
-- sources; release stops them. ctx goes to every render unchanged (nil becomes an empty table). An element with
-- w = 0 gets a frame of 1 x h and its type sets the real width. Returns { [id] = element frame }
-- of the drawn elements (visible ones only), read only.
function CR.Draw(canvas, layout, types, ctx)
  local state = stateOf(canvas)
  ctx = ctx or {}
  types = types or {}
  layout = type(layout) == "table" and layout or {}
  drawCanvas(canvas, state, type(layout.canvas) == "table" and layout.canvas or {})
  local order = {}
  for i, el in ipairs(type(layout.elements) == "table" and layout.elements or {}) do
    if type(el) == "table" and type(el.id) == "string" and type(el.type) == "string" then
      order[#order + 1] = { el = el, i = i, z = number(el.z, 0, -CL.MAX_Z, CL.MAX_Z) }
    end
  end
  table.sort(order, function(a, b)
    if a.z ~= b.z then
      return a.z < b.z
    end
    return a.i < b.i
  end)
  local base = canvas:GetFrameLevel() + 1
  local frames, seen = {}, {}
  for rank, entry in ipairs(order) do
    local el = entry.el
    local def = types[el.type]
    if not seen[el.id] and type(def) == "table" and type(def.render) == "function" then
      seen[el.id] = true
      if el.visible ~= false then
        local frame = acquire(canvas, state, el.id, el.type, def)
        local point = CL.POINTS[1]
        for _, p in ipairs(CL.POINTS) do
          if p == el.point then
            point = p
          end
        end
        frame:ClearAllPoints()
        frame:SetPoint(
          point,
          canvas,
          point,
          number(el.x, 0, -CL.MAX_OFFSET, CL.MAX_OFFSET),
          number(el.y, 0, -CL.MAX_OFFSET, CL.MAX_OFFSET)
        )
        local w = number(el.w, 0, 0, CL.MAX_SIZE)
        frame:SetSize(w > 0 and w or AUTO, number(el.h, 16, 1, CL.MAX_SIZE))
        frame:SetFrameLevel(base + rank)
        frame:Show()
        ns.Safe("canvas.render." .. el.type, def.render, frame, el, ctx)
        local item = state.items[el.id]
        if not item.driven then
          item.driven = true
          if type(def.drive) == "function" then
            ns.Safe("canvas.drive." .. el.type, def.drive, frame, el, ctx)
          end
        end
        frames[el.id] = frame
      else
        release(state, el.id)
      end
    end
  end
  for id in pairs(state.items) do
    if not frames[id] then
      release(state, id)
    end
  end
  return frames
end

-- The frame an element was drawn into (nil when it is hidden or was not drawn).
function CR.Frame(canvas, id)
  local state = canvas.fgCanvas
  local item = state and state.items[id]
  return item and item.frame or nil
end

-- Function(element) -> width of its frame, for the `measure` argument of CanvasLogic (rectangles of
-- elements with automatic width).
function CR.Measurer(canvas)
  return function(el)
    local frame = CR.Frame(canvas, el.id)
    return frame and frame:GetWidth() or nil
  end
end

-- Takes every element frame out of the picture (into the pool) and hides background and border.
-- The next Draw brings them back.
function CR.Clear(canvas)
  local state = canvas.fgCanvas
  if not state then
    return
  end
  for id in pairs(state.items) do
    release(state, id)
  end
  if state.bg then
    state.bg:Hide()
  end
  for _, line in pairs(state.edges) do
    line:Hide()
  end
end
