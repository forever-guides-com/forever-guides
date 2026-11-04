-- Draws a canvas layout into a frame: one child frame per element, placed by anchor, offset and
-- size, stacked by z, shown or hidden. The editor preview and the real window call the same
-- Draw, the element types paint themselves (types[type].render). Child frames are reused: a frame
-- of a removed element or of a changed type goes to a pool per type, so repeated calls create
-- nothing new once the layout has settled.
--
-- A group (GroupLogic) is drawn as a frame of its own that holds its children: the children hang on the
-- group frame and are placed inside its box. While the player is in combat, a change of the structure
-- (which element hangs on which frame) waits until the combat ends (Deferred), the host draws again then.
-- Closing up of the children (Reflow) only moves frames of ours.
local _, ns = ...
local U, CL = ns.U, ns.CanvasLogic

local CR = {}
ns.CanvasRender = CR

-- Canvases that show a group whose places change while the game runs (it closes up or sorts), as a weak set.
-- GroupRuntime watches them; `CR.onLive` (optional) is told when the set changes.
CR.live = setmetatable({}, { __mode = "k" })

-- A group has no look of its own: its frame only sets the box the children are placed in.
local GROUP = "group"
local GROUP_TYPE = {
  render = function() end,
}

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

-- The drawing state kept on the canvas frame: items = { [id] = { frame, type, def, parent } }, pool of
-- frames per type, the background and the four border lines. For groups: `sig` (what hangs on what, as drawn),
-- `layout` (the layout of the last draw), `placed` (places Reflow set), `order` (last order of a group by
-- remaining time), `deferred` (a draw waits for the end of combat).
local function stateOf(canvas)
  local state = canvas.fgCanvas
  if not state then
    state = { items = {}, pool = {}, edges = {}, placed = {}, order = {} }
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
  local def = CL.CanvasDefaults(CL.Kind(cv))
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

-- Whether the player is in combat or the game withholds aura values: no frame changes its parent then.
local function restricted()
  local AN = ns.AuraNative
  if AN and AN.Restricted then
    local ok, value = pcall(AN.Restricted)
    return ok and value == true
  end
  local ok, value = pcall(InCombatLockdown)
  return ok and value == true
end

-- The frame of an element: the one it had (when it still hangs on `parent`), else one of the pool of its type,
-- else a new one. In combat a pooled frame is only taken when it already hangs on `parent`.
local function acquire(state, id, kind, def, parent, locked)
  local item = state.items[id]
  if item and item.type == kind and item.frame:GetParent() == parent then
    item.def = def
    return item.frame
  end
  release(state, id)
  local pool = state.pool[kind]
  local frame
  for i = pool and #pool or 0, 1, -1 do
    if not locked or pool[i]:GetParent() == parent then
      frame = table.remove(pool, i)
      break
    end
  end
  if frame then
    if frame:GetParent() ~= parent then
      frame:SetParent(parent)
    end
  else
    frame = CreateFrame("Frame", nil, parent)
  end
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
-- Elements of type "group" are drawn without an entry in `types`; their children (`group` = the id of the group)
-- hang on the group frame, in the order of their slots, and the frame levels run on over the whole picture
-- (group, its children, next element). A child of a group that is missing or hidden is not drawn.
-- In combat a change of what hangs on what is not applied: the frames stay as they are, Deferred says so and the
-- host draws again after the combat.
function CR.Draw(canvas, layout, types, ctx)
  local state = stateOf(canvas)
  ctx = ctx or {}
  types = types or {}
  layout = type(layout) == "table" and layout or {}
  drawCanvas(canvas, state, type(layout.canvas) == "table" and layout.canvas or {})
  local top, kids, byId = {}, {}, {}
  for i, el in ipairs(type(layout.elements) == "table" and layout.elements or {}) do
    if type(el) == "table" and type(el.id) == "string" and type(el.type) == "string" then
      byId[el.id] = byId[el.id] or el
      top[#top + 1] = { el = el, i = i, z = number(el.z, 0, -CL.MAX_Z, CL.MAX_Z) }
    end
  end
  local roots = {}
  for _, entry in ipairs(top) do
    local group = type(entry.el.group) == "string" and byId[entry.el.group] or nil
    if group and group ~= entry.el and group.type == GROUP then
      kids[group.id] = kids[group.id] or {}
      table.insert(kids[group.id], entry)
      entry.slot = number(entry.el.slot, math.huge, -CL.MAX_Z, CL.MAX_Z)
    else
      roots[#roots + 1] = entry
    end
  end
  table.sort(roots, function(a, b)
    if a.z ~= b.z then
      return a.z < b.z
    end
    return a.i < b.i
  end)
  for _, list in pairs(kids) do
    table.sort(list, function(a, b)
      if a.slot ~= b.slot then
        return a.slot < b.slot
      end
      return a.i < b.i
    end)
  end
  -- The plan: every element that is drawn or taken out, in drawing order, with its place in the tree.
  local plan, seen, rank = {}, {}, 0
  local function walk(entry, parent)
    rank = rank + 1
    local el = entry.el
    local def = el.type == GROUP and (types[GROUP] or GROUP_TYPE) or types[el.type]
    if seen[el.id] or type(def) ~= "table" or type(def.render) ~= "function" then
      return
    end
    seen[el.id] = true
    local item = { el = el, def = def, rank = rank, parent = parent, show = el.visible ~= false }
    plan[#plan + 1] = item
    if item.show and el.type == GROUP then
      for _, kid in ipairs(kids[el.id] or {}) do
        walk(kid, el.id)
      end
    end
  end
  for _, entry in ipairs(roots) do
    walk(entry, nil)
  end
  local signature, grouped, dynamic = {}, false, false
  for _, item in ipairs(plan) do
    if item.show then
      signature[#signature + 1] = item.el.id .. ":" .. item.el.type .. ":" .. (item.parent or "")
      grouped = grouped or item.parent ~= nil or item.el.type == GROUP
      if item.el.type == GROUP then
        local p = ns.GroupLogic.Clean(item.el.props)
        dynamic = dynamic or (p.mode ~= "free" and (p.collapse == "readable" or p.sort ~= "manual"))
      end
    end
  end
  signature = table.concat(signature, ";")
  local locked = restricted()
  local frames = {}
  if locked and (grouped or state.grouped) and state.sig ~= nil and state.sig ~= signature then
    -- Structure changes wait for the end of the combat.
    state.deferred = true
    for id, item in pairs(state.items) do
      frames[id] = item.frame
    end
    return frames
  end
  state.deferred, state.sig, state.grouped, state.layout = false, signature, grouped, layout
  state.placed = {}
  local base = canvas:GetFrameLevel() + 1
  for _, item in ipairs(plan) do
    local el = item.el
    if item.show then
      local parentFrame = item.parent and frames[item.parent] or canvas
      local frame = acquire(state, el.id, el.type, item.def, parentFrame, locked)
      local point = CL.POINTS[1]
      for _, p in ipairs(CL.POINTS) do
        if p == el.point then
          point = p
        end
      end
      frame:ClearAllPoints()
      frame:SetPoint(
        point,
        parentFrame,
        point,
        number(el.x, 0, -CL.MAX_OFFSET, CL.MAX_OFFSET),
        number(el.y, 0, -CL.MAX_OFFSET, CL.MAX_OFFSET)
      )
      local w = number(el.w, 0, 0, CL.MAX_SIZE)
      frame:SetSize(w > 0 and w or AUTO, number(el.h, 16, 1, CL.MAX_SIZE))
      frame:SetFrameLevel(base + item.rank)
      frame:Show()
      ns.Safe("canvas.render." .. el.type, item.def.render, frame, el, ctx)
      local entry = state.items[el.id]
      if not entry.driven then
        entry.driven = true
        if type(item.def.drive) == "function" then
          ns.Safe("canvas.drive." .. el.type, item.def.drive, frame, el, ctx)
        end
      end
      frames[el.id] = frame
    else
      release(state, el.id)
    end
  end
  for id in pairs(state.items) do
    if not frames[id] then
      release(state, id)
    end
  end
  local live = dynamic and not ctx.editor or nil
  if (CR.live[canvas] == true) ~= (live == true) then
    CR.live[canvas] = live
    if CR.onLive then
      ns.Safe("canvas.live", CR.onLive, canvas)
    end
  end
  return frames
end

-- Whether the last Draw waited for the end of the combat (the host draws again then).
function CR.Deferred(canvas)
  local state = canvas.fgCanvas
  return state ~= nil and state.deferred == true
end

-- Applies the places GroupLogic.Reflow computes for the groups of the last drawn layout: the children that are
-- there close up, a sorting by remaining time keeps the order it had when the fight began. inputs = { occupancy =
-- { [id] = "yes" | "no" | nil }, readings = { [id] = { active, remaining } }, combat = boolean }. Only SetPoint on
-- frames of ours, so it runs in combat. Returns the number of frames that moved.
function CR.Reflow(canvas, layout, inputs)
  local state = canvas.fgCanvas
  if not state or type(layout) ~= "table" or type(layout.elements) ~= "table" then
    return 0
  end
  inputs = type(inputs) == "table" and inputs or {}
  local GL = ns.GroupLogic
  local moved = 0
  for _, group in ipairs(layout.elements) do
    local holder = group.type == GROUP and state.items[group.id] or nil
    if holder then
      local frozen = inputs.combat and state.order[group.id] or nil
      local result = GL.Reflow(layout, group.id, inputs.occupancy, inputs.readings, frozen)
      if result then
        if not inputs.combat then
          state.order[group.id] = result.order
        end
        for id, at in pairs(result.pos) do
          local item = state.items[id]
          local el = CL.Find(layout, id)
          if item and el and item.frame:GetParent() == holder.frame then
            local last = state.placed[id] or { x = el.x, y = -el.y }
            if math.abs(last.x - at.x) > 0.01 or math.abs(last.y - at.y) > 0.01 then
              item.frame:ClearAllPoints()
              item.frame:SetPoint("TOPLEFT", holder.frame, "TOPLEFT", at.x, -at.y)
              state.placed[id] = { x = at.x, y = at.y }
              moved = moved + 1
            end
          end
        end
      end
    end
  end
  return moved
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
  state.sig, state.grouped, state.deferred, state.layout = nil, false, false, nil
  state.placed, state.order = {}, {}
  if CR.live[canvas] then
    CR.live[canvas] = nil
    if CR.onLive then
      ns.Safe("canvas.live", CR.onLive, canvas)
    end
  end
  if state.bg then
    state.bg:Hide()
  end
  for _, line in pairs(state.edges) do
    line:Hide()
  end
end
