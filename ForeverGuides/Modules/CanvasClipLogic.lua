-- Copying and pasting elements of the canvas editor, without WoW API: one element, or one group with all its
-- children, packed into an exchange string of its own (envelope type "canvas-elements", same encoding as a whole
-- layout), read back with the same strictness as a layout, and pasted into a layout with new ids. The first element
-- of the string is the root: the element itself or the group, every other element is a child of that group. A string
-- is data only, nothing in it is ever run. CanvasLogic.lua holds the model, GroupLogic.lua the groups.
local _, ns = ...
local U, CL, GL = ns.U, ns.CanvasLogic, ns.GroupLogic

local CC = {
  KIND = CL.KIND_ELEMENTS,
  -- `fmt` and envelope version of a string with a group, the same numbers a layout with groups carries.
  FORMAT = CL.FORMAT,
  MAX_ENVELOPE = CL.MAX_ENVELOPE,
  -- A group and its children at most.
  MAX_ELEMENTS = 1 + GL.MAX_CHILDREN,
  -- Displays that read each other's elements: the ring and the HUD windows draw the same element types.
  COMPATIBLE = { cursor = true, area = true },
}
ns.CanvasClipLogic = CC

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Elements ---------------------------------------------------------------------------------------------------

-- The element (table or id) and, for a group, its children by slot: { root, child, ... }. Returns nil and "missing"
-- when the layout has no such element.
function CC.Collect(layout, ref)
  local root = CL.Find(layout, ref)
  if not root then
    return nil, "missing"
  end
  local list = { root }
  if root.type == GL.TYPE then
    for _, kid in ipairs(GL.Children(layout, root.id)) do
      list[#list + 1] = kid
    end
  end
  return list
end

-- Plain data of the element or the group of `layout`: { fmt?, canvas = { kind, w, h }, root = id, elements }. The root
-- comes first and no longer names a group: a child that is copied alone keeps its place on the canvas.
function CC.Pack(layout, ref)
  local list, why = CC.Collect(layout, ref)
  if not list then
    return nil, why
  end
  local root = list[1]
  local elements = {}
  for i, el in ipairs(list) do
    elements[i] = U.copy(el)
  end
  local head = elements[1]
  if root.group ~= nil then
    local left, top = CL.AbsRect(layout, root)
    head.group, head.slot = nil, nil
    head.point, head.x, head.y = "TOPLEFT", left, -top
  end
  local c = layout.canvas
  local clean = CL.Validate({
    id = "clip",
    canvas = { kind = CL.Kind(layout), w = c.w, h = c.h },
    elements = elements,
  })
  local data = {
    canvas = { kind = clean.canvas.kind, w = clean.canvas.w, h = clean.canvas.h },
    root = clean.elements[1] and clean.elements[1].id,
    elements = clean.elements,
  }
  local need = CL.RequiredVersion(clean.elements)
  if need > 1 then
    data.fmt = need
  end
  return data
end

-- Exchange string of an element or a group (one token), or nil and "missing" | "too-large" | the reason of
-- Strings.encode. The envelope names the display like a layout does.
function CC.Export(layout, ref, host)
  local data, why = CC.Pack(layout, ref)
  if not data then
    return nil, why
  end
  local s, err = ns.Strings.encode(CC.KIND, data, nil, type(host) == "string" and host or CL.HostOf(layout), data.fmt)
  if s and #s > ns.Strings.MAX_INPUT then
    return nil, "too-large"
  end
  return s, err
end

-- A clip from decoded data: { elements, kind, w, h, problems }, or nil and "shape". Only the first element and, when it
-- is a group, the elements that name it as their group are taken (no nested group), everything else is dropped.
-- Every value is repaired by CanvasLogic.Validate.
function CC.Unpack(data)
  if type(data) ~= "table" or type(data.elements) ~= "table" then
    return nil, "shape"
  end
  local head = CL.Upgrade(data.elements[1])
  if type(head) ~= "table" or type(head.type) ~= "string" or head.type == "" then
    return nil, "shape"
  end
  local rootId = head.id
  if type(rootId) ~= "string" or rootId == "" then
    return nil, "shape"
  end
  local first = {}
  for k, v in pairs(head) do
    first[k] = v
  end
  first.group, first.slot = nil, nil
  local list = { first }
  if head.type == GL.TYPE then
    for i = 2, #data.elements do
      local item = data.elements[i]
      if type(item) == "table" and item.group == rootId and item.type ~= GL.TYPE and #list < CC.MAX_ELEMENTS then
        list[#list + 1] = item
      end
    end
  end
  local canvas = type(data.canvas) == "table" and data.canvas or {}
  local clean, problems = CL.Validate({
    id = "clip",
    canvas = { kind = canvas.kind, w = canvas.w, h = canvas.h },
    elements = list,
  })
  local root = clean.elements[1]
  if not root or root.group ~= nil or root.type ~= head.type then
    return nil, "shape"
  end
  for i = #clean.elements, 2, -1 do
    if clean.elements[i].group ~= root.id then
      table.remove(clean.elements, i)
    end
  end
  return {
    elements = clean.elements,
    kind = clean.canvas.kind,
    w = clean.canvas.w,
    h = clean.canvas.h,
    problems = problems,
  }
end

-- Whether elements of display `from` may be pasted into display `to`.
function CC.Compatible(from, to)
  return from == to or (CC.COMPATIBLE[from] == true and CC.COMPATIBLE[to] == true)
end

-- Reads a pasted exchange string that holds a whole layout or elements. `host` ("xpbar", "cursor" or "area") names
-- the display it is for, `maxJson` lowers the inflated size (see Strings.decode). Returns
-- { kind = "layout", layout, problems } or { kind = "elements", clip, host, problems }, or nil, "empty" | "too-large" | "decode" | "json" | "shape" | "type" | "version" | "host" and, once the envelope was
-- read, what the string is ("layout" or "elements") so a message can name it.
function CC.Read(text, host, maxJson)
  local env, why = ns.Strings.decode(text, maxJson)
  if not env then
    return nil, why
  end
  if env.type == CC.KIND then
    if env.v > CC.MAX_ENVELOPE then
      return nil, "version", "elements"
    end
    local from = type(env.host) == "string" and env.host or CL.DEFAULT_HOST
    if host ~= nil and not CC.Compatible(from, host) then
      return nil, "host", "elements"
    end
    local clip, reason = CC.Unpack(env.data)
    if not clip then
      return nil, reason, "elements"
    end
    return { kind = "elements", clip = clip, host = from, problems = clip.problems }
  end
  local layout, problems = CL.Import(text, host, maxJson)
  if not layout then
    return nil, problems, env.type == CL.KIND and "layout" or nil
  end
  return { kind = "layout", layout = layout, problems = problems }
end

-- What a clip holds: { count, group (boolean), name (the first element), children }.
function CC.Describe(clip)
  local root = clip.elements[1]
  local group = root.type == GL.TYPE
  return { count = #clip.elements, group = group, name = root.name, children = group and #clip.elements - 1 or 0 }
end

-- Paste ------------------------------------------------------------------------------------------------------

-- How many elements of a clip a display with the types `types` does not offer (0 without a type table).
function CC.Unsupported(clip, types)
  if type(types) ~= "table" then
    return 0
  end
  local n = 0
  for _, el in ipairs(clip.elements) do
    if type(types[el.type]) ~= "table" then
      n = n + 1
    end
  end
  return n
end

local function topZ(layout)
  local top = 0
  for _, el in ipairs(layout.elements) do
    top = math.max(top, el.z)
  end
  return top
end

local function countType(layout, kind)
  local n = 0
  for _, el in ipairs(layout.elements) do
    n = n + (el.type == kind and 1 or 0)
  end
  return n
end

-- Whether an element of the canvas already sits exactly where `el` is.
local function covered(layout, el)
  for _, other in ipairs(layout.elements) do
    if other.group == nil and other.point == el.point and other.x == el.x and other.y == el.y then
      return true
    end
  end
  return false
end

-- Adds the elements of a clip to `layout` with new ids (the group references follow), the root on top of the canvas.
-- The root moves a few pixels while an element sits exactly where it would land. `opts` (optional):
--   types = { [type] = { max?, clean?(props, element) } }   the types of the display: one the display does not
--           offer is left out (the root: the whole paste is refused), `max` limits the elements of a type, `clean`
--           repairs the props of an element of that type
-- Returns { root = id, ids = { id, ... }, skipped = n } or nil and "missing" | "type" | "max" | "limit" (then also the
-- room left and the number of elements that would be added). The layout is not touched.
function CC.Paste(layout, clip, opts)
  if type(clip) ~= "table" or type(clip.elements) ~= "table" or not clip.elements[1] then
    return nil, "missing"
  end
  local types = type(opts) == "table" and type(opts.types) == "table" and opts.types or nil
  local picked, skipped, added = {}, 0, {}
  for i, source in ipairs(clip.elements) do
    local def = types and types[source.type]
    local reason
    if types and type(def) ~= "table" then
      reason = "type"
    elseif
      type(def) == "table"
      and finite(def.max)
      and countType(layout, source.type) + (added[source.type] or 0) >= def.max
    then
      reason = "max"
    end
    if reason and i == 1 then
      return nil, reason
    elseif reason then
      skipped = skipped + 1
    else
      picked[#picked + 1] = source
      added[source.type] = (added[source.type] or 0) + 1
    end
  end
  local room = CL.MAX_ELEMENTS - #layout.elements
  if #picked > room then
    return nil, "limit", math.max(0, room), #picked
  end
  local used, names = {}, {}
  for _, el in ipairs(layout.elements) do
    used[el.id] = true
    names[el.name] = true
  end
  local ids = {}
  local rootId
  for i, source in ipairs(picked) do
    local el = U.copy(source)
    local id = CL.UniqueId(el.id, used)
    used[id] = true
    el.id = id
    if i == 1 then
      rootId = id
      el.group, el.slot = nil, nil
      el.z = topZ(layout) + 1
      for _ = 1, 10 do
        if not covered(layout, el) then
          break
        end
        CL.Move(el, CL.COPY_OFFSET, CL.COPY_OFFSET)
      end
    else
      el.group = rootId
    end
    if names[el.name] then
      el.name = CL.CopyName(layout, el.name)
    end
    names[el.name] = true
    local def = types and types[el.type]
    if type(def) == "table" and type(def.clean) == "function" then
      local ok, props = pcall(def.clean, el.props, el)
      if ok and type(props) == "table" then
        el.props = props
      end
    end
    layout.elements[#layout.elements + 1] = el
    ids[#ids + 1] = id
  end
  GL.Settle(layout)
  CL.Clamp(layout)
  return { root = rootId, ids = ids, skipped = skipped }
end
