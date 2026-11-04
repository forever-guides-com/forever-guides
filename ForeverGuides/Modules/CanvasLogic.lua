-- Layout model of the reusable canvas editor, without WoW API: a layout is a canvas plus elements,
-- every element sits at one of nine anchors of the canvas with an offset and a size. This file holds
-- the model, the anchor math (an anchor change keeps the element where it is), snapping, aligning,
-- the z order, the repair of broken numbers, the undo history and the exchange format. Drawing lives
-- in CanvasRender.lua, the window in CanvasEditor.lua.
--
-- Offsets follow SetPoint: x grows to the right, y grows UP, both measured from the anchor of the
-- canvas to the same anchor of the element. Rectangles for the screen (Rect) use the canvas corner
-- at the top left as origin and y grows DOWN. Element types are unknown here: `props` is passed
-- through, unknown types stay in the layout (a newer version may have written them).
--
-- Groups (GroupLogic.lua) are ordinary elements of type "group"; a child names its group in `group` and
-- its place among the siblings in `slot`, and its offsets are measured inside the box of the group
-- (Rect), AbsRect gives the canvas position.
local _, ns = ...
local U, L = ns.U, ns.L

local CL = {
  KIND = "canvaslayout",
  MIN_CANVAS = 16,
  MAX_CANVAS = 1024,
  MAX_ELEMENTS = 64,
  MAX_OFFSET = 4096,
  MAX_SIZE = 2048,
  MAX_Z = 9999,
  MAX_NAME = 40,
  MAX_LAYOUT_NAME = 60,
  MAX_UNDO = 100,
  MERGE_WINDOW = 0.4,
  TOLERANCE = 4,
  COPY_OFFSET = 10,
  CANVAS = { w = 240, h = 60, bg = "000000", bgAlpha = 0.6, borderAlpha = 1 },
  -- Canvas kinds: "bar" is a window of its own (default), "cursor" a canvas around the mouse cursor, "area" a
  -- free window of cooldowns and auras (no hotspot, the defaults of a bar).
  KINDS = { "bar", "cursor", "area" },
  CANVAS_CURSOR = { w = 256, h = 256, bg = "000000", bgAlpha = 0, borderAlpha = 1 },
  CANVAS_AREA = { w = 240, h = 60, bg = "000000", bgAlpha = 0.6, borderAlpha = 1 },
  -- Hosts of the exchange format and the canvas kind each one accepts.
  HOSTS = { xpbar = "bar", cursor = "cursor", area = "area" },
  DEFAULT_HOST = "xpbar",
  HOT_DEFAULT = 0.5,
  -- Highest envelope version Import reads. The envelope is 2 only for a layout with groups (Export), so older
  -- versions refuse such a string instead of drawing the children in the wrong place.
  MAX_ENVELOPE = 2,
  -- `fmt` of the exchange data of a layout that needs a version with groups.
  FORMAT = 2,
  -- Row by row, as the 3 x 3 grid of the editor shows them.
  POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
  ALIGN = { "left", "hcenter", "right", "top", "vcenter", "bottom" },
}
ns.CanvasLogic = CL

ns.AddLocale("enUS", {
  ["canvas.copy"] = "%s copy",
})
ns.AddLocale("deDE", {
  ["canvas.copy"] = "%s Kopie",
})

-- Share of the free canvas width and height at which an anchor sits (0 = left or top).
local FRACTION = {
  TOPLEFT = { 0, 0 },
  TOP = { 0.5, 0 },
  TOPRIGHT = { 1, 0 },
  LEFT = { 0, 0.5 },
  CENTER = { 0.5, 0.5 },
  RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 1 },
  BOTTOM = { 0.5, 1 },
  BOTTOMRIGHT = { 1, 1 },
}
local MAX_DEPTH = 6
local MAX_ENTRIES = 200
local MAX_TYPE = 40
local MAX_ID = 32
-- Offsets and element sizes sit on half pixels, so odd sizes can still be centered.
local STEP = 0.5

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Number from saved data: the default for anything that is not a finite number, else clamped.
local function num(v, default, lo, hi)
  if not finite(v) then
    return default
  end
  return U.clamp(v, lo, hi)
end

-- Text -----------------------------------------------------------------------------------------

-- Names are plain data. CleanText makes any string safe to show in a list, a title or a tooltip and
-- to carry through an exchange string: valid UTF-8 only, one line, no invisible direction controls,
-- no UI escape bar. The bar "|" (the start of every colour, texture, link and newline escape of the
-- client) becomes the full-width bar U+FF5C, so the text stays readable and cannot inject anything.
-- The result is a fixed point: cleaning it again changes nothing.
local BAR = "\239\189\156"

-- Code point as UTF-8.
local function utf8char(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(
    0xF0 + math.floor(cp / 0x40000),
    0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40,
    0x80 + cp % 0x40
  )
end

-- Length and code point of the well-formed sequence at byte i (no overlong form, no value above
-- U+10FFFF), nil for a byte that starts none.
local function sequenceAt(s, i)
  local b = s:byte(i)
  if not b then
    return nil
  elseif b < 0x80 then
    return 1, b
  end
  local len, cp, floor
  if b >= 0xC2 and b <= 0xDF then
    len, cp, floor = 2, b - 0xC0, 0x80
  elseif b >= 0xE0 and b <= 0xEF then
    len, cp, floor = 3, b - 0xE0, 0x800
  elseif b >= 0xF0 and b <= 0xF4 then
    len, cp, floor = 4, b - 0xF0, 0x10000
  else
    return nil
  end
  for k = 1, len - 1 do
    local c = s:byte(i + k)
    if not c or c < 0x80 or c > 0xBF then
      return nil
    end
    cp = cp * 0x40 + (c - 0x80)
  end
  if cp < floor or cp > 0x10FFFF then
    return nil
  end
  return len, cp
end

-- What a code point counts as: "space" (becomes one space), "drop" (leaves out) or nil (stays).
local function classify(cp)
  if
    cp <= 0x20
    or (cp >= 0x7F and cp <= 0xA0)
    or cp == 0x1680
    or (cp >= 0x2000 and cp <= 0x200A)
    or cp == 0x2028
    or cp == 0x2029
    or cp == 0x202F
    or cp == 0x205F
    or cp == 0x3000
  then
    return "space"
  elseif
    (cp >= 0x200B and cp <= 0x200F)
    or (cp >= 0x202A and cp <= 0x202E)
    or (cp >= 0x2060 and cp <= 0x2069)
    or cp == 0xFEFF
    or cp == 0xFFFE
    or cp == 0xFFFF
    or (cp >= 0xE0000 and cp <= 0xE007F)
  then
    return "drop"
  end
end

-- `v` as one clean line of at most `max` bytes (default MAX_NAME), cut between characters, never inside
-- one. Anything that is not a string gives "". Invalid UTF-8 bytes are dropped, a surrogate pair written
-- as two escapes (UTF-16 style) is joined into one character, control characters, line breaks and any run
-- of blanks become one space, leading and trailing blanks go.
function CL.CleanText(v, max)
  if type(v) ~= "string" then
    return ""
  end
  max = finite(max) and max or CL.MAX_NAME
  local out, used, pending = {}, 0, false
  local i, n = 1, #v
  while i <= n do
    local len, cp = sequenceAt(v, i)
    local text
    if not len then
      len = 1
    elseif cp >= 0xD800 and cp <= 0xDBFF then
      -- A high surrogate needs its low half right behind it.
      local nextLen, low = sequenceAt(v, i + len)
      if nextLen and low >= 0xDC00 and low <= 0xDFFF then
        text = utf8char(0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00))
        len = len + nextLen
      end
    elseif cp < 0xD800 or cp > 0xDFFF then
      local kind = classify(cp)
      if kind == "space" then
        pending = used > 0
      elseif not kind then
        text = cp == 0x7C and BAR or v:sub(i, i + len - 1)
      end
    end
    if text then
      local need = #text + (pending and 1 or 0)
      if used + need > max then
        break
      end
      if pending then
        out[#out + 1] = " "
        pending = false
      end
      out[#out + 1] = text
      used = used + need
    end
    i = i + len
  end
  return table.concat(out)
end
local cleanName = CL.CleanText

local function cleanId(v, fallback)
  local s = type(v) == "string" and v:gsub("[^%w_%-]", ""):sub(1, MAX_ID) or ""
  return s ~= "" and s or fallback
end

-- "rrggbb" in lower case, nil for anything else ("#" in front is accepted).
local function hexColor(v)
  if type(v) ~= "string" then
    return nil
  end
  local s = v:gsub("^#", "")
  if s:find("^%x%x%x%x%x%x$") then
    return s:lower()
  end
end

-- Deep copy of the parts of `v` that survive a JSON round trip (strings, booleans, finite numbers,
-- tables with string or number keys), bounded in depth and width. Cycles end at the depth limit.
local function plain(v, depth)
  local kind = type(v)
  if kind == "string" or kind == "boolean" then
    return v
  elseif kind == "number" then
    return finite(v) and v or nil
  elseif kind ~= "table" or (depth or 0) > MAX_DEPTH then
    return nil
  end
  local out, count = {}, 0
  for k, item in pairs(v) do
    local keyKind = type(k)
    if (keyKind == "string" or (keyKind == "number" and finite(k))) and count < MAX_ENTRIES then
      local copy = plain(item, (depth or 0) + 1)
      if copy ~= nil then
        out[k] = copy
        count = count + 1
      end
    end
  end
  return out
end

local function equal(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not equal(v, b[k]) then
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

-- First free id: `base`, then base2, base3, ... `taken` is a set or a function(id) -> boolean.
function CL.UniqueId(base, taken)
  local function used(id)
    if type(taken) == "function" then
      return taken(id) == true
    end
    return type(taken) == "table" and taken[id] ~= nil
  end
  base = cleanId(base, "item")
  if not used(base) then
    return base
  end
  local n = 2
  while used(base .. n) do
    n = n + 1
  end
  return base .. n
end

-- Repair ---------------------------------------------------------------------------------------

-- Writes the repaired value to `out` and notes the key when the value in `src` (the data as it
-- came, broken numbers included) was there and had to change.
local function fix(src, out, key, clean, problems, path)
  if src[key] ~= nil and src[key] ~= clean then
    problems[#problems + 1] = path .. key
  end
  out[key] = clean
end

-- A clean copy of one element, nil without a usable type. `used` is the set of ids already taken.
local function cleanElement(raw, used, problems, path)
  local out = plain(raw)
  if type(out) ~= "table" or type(out.type) ~= "string" or out.type == "" then
    problems[#problems + 1] = path:gsub("%.$", "")
    return nil
  end
  fix(raw, out, "type", out.type:sub(1, MAX_TYPE), problems, path)
  local id = cleanId(out.id, nil)
  if not id or used[id] then
    id = CL.UniqueId(id or out.type, used)
  end
  fix(raw, out, "id", id, problems, path)
  used[id] = true
  local name = cleanName(out.name, CL.MAX_NAME)
  fix(raw, out, "name", name ~= "" and name or out.type, problems, path)
  fix(raw, out, "point", FRACTION[raw.point] and raw.point or "TOPLEFT", problems, path)
  fix(raw, out, "x", num(raw.x, 0, -CL.MAX_OFFSET, CL.MAX_OFFSET), problems, path)
  fix(raw, out, "y", num(raw.y, 0, -CL.MAX_OFFSET, CL.MAX_OFFSET), problems, path)
  fix(raw, out, "w", num(raw.w, 0, 0, CL.MAX_SIZE), problems, path)
  fix(raw, out, "h", num(raw.h, 16, 1, CL.MAX_SIZE), problems, path)
  fix(raw, out, "z", num(raw.z, 0, -CL.MAX_Z, CL.MAX_Z), problems, path)
  -- Group fields only exist on children; GroupLogic checks what they point at.
  if raw.group ~= nil then
    fix(raw, out, "group", cleanId(raw.group, nil), problems, path)
  end
  if raw.slot ~= nil then
    fix(raw, out, "slot", finite(raw.slot) and U.clamp(raw.slot, -CL.MAX_Z, CL.MAX_Z) or nil, problems, path)
  end
  out.visible = out.visible ~= false
  out.props = type(out.props) == "table" and out.props or {}
  return out
end

-- Kind of a canvas or of a layout: "cursor" or "area", anything else counts as "bar".
function CL.Kind(layoutOrCanvas)
  local canvas = type(layoutOrCanvas) == "table" and (layoutOrCanvas.canvas or layoutOrCanvas) or nil
  local kind = type(canvas) == "table" and canvas.kind or nil
  return (kind == "cursor" or kind == "area") and kind or "bar"
end

-- Default canvas of a kind (size, background, border opacity).
function CL.CanvasDefaults(kind)
  if kind == "cursor" then
    return CL.CANVAS_CURSOR
  end
  return kind == "area" and CL.CANVAS_AREA or CL.CANVAS
end

-- The canvas point that sits on the mouse cursor hotspot, in canvas pixels (origin top left, y down).
function CL.HotPoint(layout)
  local c = layout.canvas
  local hx = finite(c.hotX) and c.hotX or CL.HOT_DEFAULT
  local hy = finite(c.hotY) and c.hotY or CL.HOT_DEFAULT
  return hx * c.w, hy * c.h
end

local validators = {}

-- Adds fn(layout, problems): it runs at the end of every Validate on the repaired layout and may change it and
-- append to the problem list (GroupLogic checks the group references there).
function CL.OnValidate(fn)
  validators[#validators + 1] = fn
end

-- Repairs any value into a usable layout and lists what had to change (keys such as
-- "canvas.w" or "elements[2].x"). Never fails and never returns the table it was given.
-- Elements without a type and elements past MAX_ELEMENTS are dropped, ids are made unique, unknown
-- element types and unknown keys stay. A canvas always has a kind; one of kind "cursor" also has
-- hotX, hotY (fractions of the canvas) and symmetric, and symmetric pins the hotspot to the center.
function CL.Validate(raw)
  local problems = {}
  local src = type(raw) == "table" and raw or {}
  if type(raw) ~= "table" then
    problems[1] = "layout"
  end
  local out = {}
  for k, v in pairs(src) do
    if k ~= "canvas" and k ~= "elements" then
      out[k] = plain(v, 1)
    end
  end
  out.id = cleanId(out.id, "layout")
  out.name = cleanName(out.name, CL.MAX_LAYOUT_NAME)

  local rawCanvas = type(src.canvas) == "table" and src.canvas or {}
  local cv = plain(rawCanvas) or {}
  local kind = CL.Kind(rawCanvas)
  local def = CL.CanvasDefaults(kind)
  fix(rawCanvas, cv, "kind", kind, problems, "canvas.")
  fix(rawCanvas, cv, "w", num(rawCanvas.w, def.w, CL.MIN_CANVAS, CL.MAX_CANVAS), problems, "canvas.")
  fix(rawCanvas, cv, "h", num(rawCanvas.h, def.h, CL.MIN_CANVAS, CL.MAX_CANVAS), problems, "canvas.")
  fix(rawCanvas, cv, "bg", hexColor(rawCanvas.bg) or def.bg, problems, "canvas.")
  fix(rawCanvas, cv, "bgAlpha", num(rawCanvas.bgAlpha, def.bgAlpha, 0, 1), problems, "canvas.")
  fix(rawCanvas, cv, "border", hexColor(rawCanvas.border), problems, "canvas.")
  fix(rawCanvas, cv, "borderAlpha", num(rawCanvas.borderAlpha, def.borderAlpha, 0, 1), problems, "canvas.")
  if kind == "cursor" then
    local symmetric = rawCanvas.symmetric == true
    local hot = CL.HOT_DEFAULT
    fix(rawCanvas, cv, "symmetric", symmetric, problems, "canvas.")
    fix(rawCanvas, cv, "hotX", symmetric and hot or num(rawCanvas.hotX, hot, 0, 1), problems, "canvas.")
    fix(rawCanvas, cv, "hotY", symmetric and hot or num(rawCanvas.hotY, hot, 0, 1), problems, "canvas.")
  end
  out.canvas = cv

  out.elements = {}
  local used = {}
  if type(src.elements) == "table" then
    for i, item in ipairs(src.elements) do
      if #out.elements >= CL.MAX_ELEMENTS then
        problems[#problems + 1] = "elements"
        break
      end
      local el = cleanElement(item, used, problems, "elements[" .. i .. "].")
      if el then
        out.elements[#out.elements + 1] = el
      end
    end
  elseif src.elements ~= nil then
    problems[#problems + 1] = "elements"
  end
  for _, fn in ipairs(validators) do
    ns.Safe("canvas.validate", fn, out, problems)
  end
  return out, problems
end

-- An empty layout. opts (all optional): id, name, kind, w, h, bg, bgAlpha, border, borderAlpha, hotX, hotY,
-- symmetric. Without w, h and bgAlpha the canvas takes the defaults of its kind.
function CL.New(opts)
  opts = opts or {}
  local layout = CL.Validate({
    id = opts.id,
    name = opts.name,
    canvas = {
      kind = opts.kind,
      hotX = opts.hotX,
      hotY = opts.hotY,
      symmetric = opts.symmetric,
      w = opts.w,
      h = opts.h,
      bg = opts.bg,
      bgAlpha = opts.bgAlpha,
      border = opts.border,
      borderAlpha = opts.borderAlpha,
    },
    elements = {},
  })
  return layout
end

function CL.Copy(layout)
  return U.copy(layout)
end

-- Whether a layout has a group or a child of one.
function CL.HasGroups(layout)
  for _, el in ipairs(type(layout) == "table" and type(layout.elements) == "table" and layout.elements or {}) do
    if type(el) == "table" and (el.type == "group" or el.group ~= nil) then
      return true
    end
  end
  return false
end

-- Elements -------------------------------------------------------------------------------------

-- The element and its index for a table of the layout or an id, nil when it is not in there.
function CL.Find(layout, ref)
  for i, el in ipairs(layout.elements) do
    if el == ref or (type(ref) == "string" and el.id == ref) then
      return el, i
    end
  end
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
    if el.type == kind then
      n = n + 1
    end
  end
  return n
end

-- Adds a copy of `element` on top. Needs element.type, everything else is filled in: size, props
-- and name from the type definition (types[type] = { label, new(), size = { w, h }, max }), the
-- position (CENTER, 0, 0), the id (the given one when still free). `max` of a definition limits the
-- elements of that type per layout. Returns the new element, or nil and "type" | "limit" | "max".
function CL.AddElement(layout, element, types)
  if type(element) ~= "table" or type(element.type) ~= "string" or element.type == "" then
    return nil, "type"
  end
  if #layout.elements >= CL.MAX_ELEMENTS then
    return nil, "limit"
  end
  local def = type(types) == "table" and types[element.type] or nil
  if type(def) == "table" and finite(def.max) and countType(layout, element.type) >= def.max then
    return nil, "max"
  end
  local raw = plain(element) or {}
  if type(def) == "table" then
    local size = type(def.size) == "table" and def.size or {}
    raw.w = raw.w == nil and size[1] or raw.w
    raw.h = raw.h == nil and size[2] or raw.h
    raw.name = raw.name == nil and type(def.label) == "string" and def.label or raw.name
    if raw.props == nil and type(def.new) == "function" then
      local ok, props = pcall(def.new)
      raw.props = ok and plain(props) or nil
    end
  end
  raw.point = raw.point == nil and "CENTER" or raw.point
  raw.z = raw.z == nil and topZ(layout) + 1 or raw.z
  local used = {}
  for _, el in ipairs(layout.elements) do
    used[el.id] = true
  end
  local clean = cleanElement(raw, used, {}, "")
  layout.elements[#layout.elements + 1] = clean
  return clean
end

-- Removes an element (table or id). Returns it and its index, nil when it was not there.
function CL.RemoveElement(layout, ref)
  local el, index = CL.Find(layout, ref)
  if not el then
    return nil
  end
  local GL = ns.GroupLogic
  if GL and el.type == GL.TYPE then
    -- The children stay: they leave the group where they are.
    return GL.Remove(layout, el, "dissolve")
  end
  table.remove(layout.elements, index)
  if el.group and GL then
    GL.Settle(layout)
  end
  return el, index
end

-- Names an element (table or id) with the cleaned `text`. Empty text gives the cleaned `default`, and
-- without one the type. Names may repeat, the id never follows the name. True when the name changed.
function CL.Rename(layout, ref, text, default)
  local el = CL.Find(layout, ref)
  if not el then
    return false
  end
  local name = cleanName(text, CL.MAX_NAME)
  if name == "" then
    name = cleanName(default, CL.MAX_NAME)
  end
  if name == "" then
    name = el.type
  end
  if name == el.name then
    return false
  end
  el.name = name
  return true
end

-- The name of a copy of `name`: "<name> copy", then "<name> copy 2", "<name> copy 3" while the layout already has
-- that name. A copy of a copy counts from the original name, so names do not pile up ("Ring copy copy").
function CL.CopyName(layout, name)
  local tail = L["canvas.copy"]:format("")
  local base = name:match("^(.-)" .. tail:gsub("%p", "%%%0") .. "[ ]?%d*$")
  if base == nil or base == "" then
    base = name
  end
  local taken = {}
  for _, el in ipairs(layout.elements) do
    taken[el.name] = true
  end
  local n = 1
  while true do
    local suffix = n == 1 and tail or (tail .. " " .. n)
    local candidate = cleanName(base, CL.MAX_NAME - #suffix) .. suffix
    if not taken[candidate] then
      return candidate
    end
    n = n + 1
  end
end

-- Copy of an element on top and a few pixels down and to the right. Same results as AddElement.
function CL.Duplicate(layout, ref, types)
  local el = CL.Find(layout, ref)
  if not el then
    return nil, "missing"
  end
  local GL = ns.GroupLogic
  if GL and el.type == GL.TYPE then
    return GL.Duplicate(layout, el, types)
  end
  if el.group and GL and #GL.Children(layout, el.group) >= GL.MAX_CHILDREN then
    return nil, "limit"
  end
  local copy = plain(el)
  copy.id = nil
  copy.name = CL.CopyName(layout, el.name)
  copy.z = nil
  CL.Move(copy, CL.COPY_OFFSET, CL.COPY_OFFSET)
  -- A child is copied into its group, right behind the original.
  copy.slot = el.group and (el.slot or 0) + 0.5 or nil
  local clean, why = CL.AddElement(layout, copy, types)
  if clean and clean.group and GL then
    GL.Settle(layout)
  end
  return clean, why
end

-- Elements from back to front (z ascending, equal z keep their list order). `scope` narrows the list: nil is every
-- element, false the ones on the canvas (no group), a group id its children.
function CL.Sorted(layout, scope)
  local list = {}
  for i, el in ipairs(layout.elements) do
    if scope == nil or (scope == false and el.group == nil) or (scope and el.group == scope) then
      list[#list + 1] = { el = el, i = i }
    end
  end
  table.sort(list, function(a, b)
    if a.el.z ~= b.el.z then
      return a.el.z < b.el.z
    end
    return a.i < b.i
  end)
  for i, item in ipairs(list) do
    list[i] = item.el
  end
  return list
end

-- Moves an element in the z order: "up" or "down" one step (up = toward the front), "front" or
-- "back". Renumbers the z of the siblings (the elements of the same group, or the ones on the canvas) to 1..n.
-- Returns true when the order changed. The order of the children of an arranged group is their slot
-- (GroupLogic.Reorder).
function CL.Reorder(layout, ref, action)
  local el = CL.Find(layout, ref)
  if not el then
    return false
  end
  local list = CL.Sorted(layout, el.group or false)
  local from
  for i, item in ipairs(list) do
    if item == el then
      from = i
    end
  end
  local to
  if action == "up" then
    to = math.min(#list, from + 1)
  elseif action == "down" then
    to = math.max(1, from - 1)
  elseif action == "front" then
    to = #list
  elseif action == "back" then
    to = 1
  else
    return false
  end
  table.remove(list, from)
  table.insert(list, to, el)
  local changed = false
  for i, item in ipairs(list) do
    changed = changed or item.z ~= i
    item.z = i
  end
  return changed
end

-- Geometry -------------------------------------------------------------------------------------

-- Share (0 to 1) of an anchor along x and y; unknown names count as TOPLEFT.
function CL.Fraction(point)
  local f = FRACTION[point] or FRACTION.TOPLEFT
  return f[1], f[2]
end

-- Width of an element. One with w = 0 (automatic) asks `measure(element)` for the width it has on
-- screen; without an answer it counts as 0.
local function widthOf(el, measure)
  if el.w <= 0 and measure then
    local w = measure(el)
    if finite(w) and w > 0 then
      return w
    end
  end
  return el.w
end

-- Width and height of what an element is laid out in: the canvas, or the box of its group.
local function containerOf(layout, el)
  local c = layout.canvas
  if el.group ~= nil then
    local group = CL.Find(layout, el.group)
    if group and group ~= el then
      return { w = group.w, h = group.h }
    end
  end
  return c
end

-- Left, top, width and height of an element in its container (origin top left, y down). The container is
-- the canvas, or the box of the group of a child; AbsRect gives canvas coordinates.
function CL.Rect(layout, el, measure)
  local fx, fy = CL.Fraction(el.point)
  local c = containerOf(layout, el)
  local w = widthOf(el, measure)
  return fx * (c.w - w) + el.x, fy * (c.h - el.h) - el.y, w, el.h
end

-- Like Rect, measured from the top left corner of the canvas: the offset of every group around the element
-- is added.
function CL.AbsRect(layout, el, measure)
  local left, top, w, h = CL.Rect(layout, el, measure)
  local node = el
  for _ = 1, 4 do
    local parent = node.group ~= nil and CL.Find(layout, node.group) or nil
    if not parent or parent == node then
      break
    end
    local l, t = CL.Rect(layout, parent, measure)
    left, top, node = left + l, top + t, parent
  end
  return left, top, w, h
end

-- Offset an element at `point` needs to have its top left corner at left, top.
local function offsetFor(c, point, w, h, left, top)
  local fx, fy = CL.Fraction(point)
  return left - fx * (c.w - w), fy * (c.h - h) - top
end

-- Puts the top left corner of an element at left, top (container coordinates, as Rect gives them).
function CL.Place(layout, el, left, top, measure)
  local x, y = offsetFor(containerOf(layout, el), el.point, widthOf(el, measure), el.h, left, top)
  el.x = U.round(U.clamp(x, -CL.MAX_OFFSET, CL.MAX_OFFSET), STEP)
  el.y = U.round(U.clamp(y, -CL.MAX_OFFSET, CL.MAX_OFFSET), STEP)
end

-- Moves an element by dx to the right and dy down (screen directions, any anchor).
function CL.Move(el, dx, dy)
  el.x = U.round(U.clamp(el.x + (finite(dx) and dx or 0), -CL.MAX_OFFSET, CL.MAX_OFFSET), STEP)
  el.y = U.round(U.clamp(el.y - (finite(dy) and dy or 0), -CL.MAX_OFFSET, CL.MAX_OFFSET), STEP)
end

-- Changes the anchor and converts the offset so the element stays where it is. Returns false for
-- an unknown anchor.
function CL.SetAnchor(layout, el, point, measure)
  if not FRACTION[point] then
    return false
  end
  local left, top = CL.Rect(layout, el, measure)
  el.point = point
  CL.Place(layout, el, left, top, measure)
  return true
end

-- The anchor with the shortest offset to the element (the first of POINTS on a tie).
function CL.NearestAnchor(layout, el, measure)
  local left, top, w, h = CL.Rect(layout, el, measure)
  local best, bestDist
  for _, point in ipairs(CL.POINTS) do
    local x, y = offsetFor(containerOf(layout, el), point, w, h, left, top)
    local dist = x * x + y * y
    if not bestDist or dist < bestDist - 1e-9 then
      best, bestDist = point, dist
    end
  end
  return best
end

-- Value rounded to the nearest multiple of step; a step that is not a positive number leaves it.
function CL.Snap(value, step)
  if not finite(value) then
    return 0
  end
  if not finite(step) or step <= 0 then
    return value
  end
  return U.round(value, step)
end

-- One guide per axis and position: several matches on it only widen the span.
local function addLine(lines, seen, axis, at, from, to)
  local key = axis .. ":" .. at
  local line = seen[key]
  if line then
    line.from, line.to = math.min(line.from, from), math.max(line.to, to)
  else
    line = { axis = axis, at = at, from = from, to = to }
    seen[key] = line
    lines[#lines + 1] = line
  end
end

-- Best signed distance from one of `features` to one of `targets` ({ at, from, to }) within
-- tolerance, nil when nothing is near.
local function nearest(features, targets, tolerance)
  local best
  for _, f in ipairs(features) do
    for _, t in ipairs(targets) do
      local d = t[1] - f
      if math.abs(d) <= tolerance and (not best or math.abs(d) < math.abs(best)) then
        best = d
      end
    end
  end
  return best
end

-- Snapping of a dragged element to the canvas (edges, center) and to the other visible elements
-- (edges, center). `dragged` is the element at its proposed position. Returns
-- { dx, dy, lines }: dx and dy are what to add to move it onto the guides (canvas pixels, y down,
-- 0 without a guide), lines the guides to draw after that move as { axis, at, from, to }. axis "x"
-- is a vertical line at x = at running from y = from to y = to, axis "y" a horizontal one.
function CL.GuideLines(layout, dragged, tolerance, measure)
  tolerance = finite(tolerance) and U.clamp(tolerance, 0, 64) or CL.TOLERANCE
  local c = layout.canvas
  local left, top, w, h = CL.AbsRect(layout, dragged, measure)
  -- What moves with the dragged element is no target.
  local moves = { [dragged.id] = true }
  for _ = 1, 4 do
    for _, el in ipairs(layout.elements) do
      if el.group ~= nil and moves[el.group] then
        moves[el.id] = true
      end
    end
  end
  -- Targets per axis: { position, span start, span end }.
  local tx = { { 0, 0, c.h }, { c.w / 2, 0, c.h }, { c.w, 0, c.h } }
  local ty = { { 0, 0, c.w }, { c.h / 2, 0, c.w }, { c.h, 0, c.w } }
  for _, el in ipairs(layout.elements) do
    if not moves[el.id] and el ~= dragged and el.visible ~= false then
      local l, t, ew, eh = CL.AbsRect(layout, el, measure)
      for _, at in ipairs({ l, l + ew / 2, l + ew }) do
        tx[#tx + 1] = { at, t, t + eh }
      end
      for _, at in ipairs({ t, t + eh / 2, t + eh }) do
        ty[#ty + 1] = { at, l, l + ew }
      end
    end
  end
  local dx = nearest({ left, left + w / 2, left + w }, tx, tolerance) or 0
  local dy = nearest({ top, top + h / 2, top + h }, ty, tolerance) or 0
  left, top = left + dx, top + dy
  local lines, seen = {}, {}
  for _, f in ipairs({ left, left + w / 2, left + w }) do
    for _, t in ipairs(tx) do
      if math.abs(t[1] - f) < 0.01 then
        addLine(lines, seen, "x", t[1], math.min(t[2], top), math.max(t[3], top + h))
      end
    end
  end
  for _, f in ipairs({ top, top + h / 2, top + h }) do
    for _, t in ipairs(ty) do
      if math.abs(t[1] - f) < 0.01 then
        addLine(lines, seen, "y", t[1], math.min(t[2], left), math.max(t[3], left + w))
      end
    end
  end
  return { dx = dx, dy = dy, lines = lines }
end

-- Aligns elements (a list of elements of the layout) by mode: left, hcenter, right, top, vcenter,
-- bottom. One element aligns to the canvas, several to the box around all of them. Returns the
-- number of elements that moved, nil for an unknown mode.
function CL.Align(layout, elements, mode, measure)
  local known = false
  for _, m in ipairs(CL.ALIGN) do
    known = known or m == mode
  end
  if not known then
    return nil
  end
  local rects = {}
  local box = { l = math.huge, t = math.huge, r = -math.huge, b = -math.huge }
  for i, el in ipairs(elements) do
    local l, t, w, h = CL.AbsRect(layout, el, measure)
    rects[i] = { l = l, t = t, w = w, h = h }
    box.l, box.t = math.min(box.l, l), math.min(box.t, t)
    box.r, box.b = math.max(box.r, l + w), math.max(box.b, t + h)
  end
  if #elements == 1 then
    box = { l = 0, t = 0, r = layout.canvas.w, b = layout.canvas.h }
  end
  local moved = 0
  for i, el in ipairs(elements) do
    local r = rects[i]
    local left, top = r.l, r.t
    if mode == "left" then
      left = box.l
    elseif mode == "hcenter" then
      left = (box.l + box.r) / 2 - r.w / 2
    elseif mode == "right" then
      left = box.r - r.w
    elseif mode == "top" then
      top = box.t
    elseif mode == "vcenter" then
      top = (box.t + box.b) / 2 - r.h / 2
    else
      top = box.b - r.h
    end
    local x, y = el.x, el.y
    -- Place wants container coordinates: take the origin of the group away again.
    local parent = el.group ~= nil and CL.Find(layout, el.group) or nil
    local ol, ot = 0, 0
    if parent and parent ~= el then
      ol, ot = CL.AbsRect(layout, parent, measure)
    end
    CL.Place(layout, el, left - ol, top - ot, measure)
    if el.x ~= x or el.y ~= y then
      moved = moved + 1
    end
  end
  return moved
end

-- Brings the canvas numbers into range and every element inside the canvas (smaller than the
-- canvas, moved in). Returns true when something changed.
function CL.Clamp(layout, measure)
  local c = layout.canvas
  local before = U.copy(layout)
  c.w = num(c.w, CL.CANVAS.w, CL.MIN_CANVAS, CL.MAX_CANVAS)
  c.h = num(c.h, CL.CANVAS.h, CL.MIN_CANVAS, CL.MAX_CANVAS)
  for _, el in ipairs(layout.elements) do
    -- A child stays inside the box of its group.
    local box = containerOf(layout, el)
    el.w = math.min(el.w, box.w)
    el.h = math.min(el.h, box.h)
    local left, top, w, h = CL.Rect(layout, el, measure)
    local newLeft = U.clamp(left, 0, math.max(0, box.w - w))
    local newTop = U.clamp(top, 0, math.max(0, box.h - h))
    if newLeft ~= left or newTop ~= top then
      CL.Place(layout, el, newLeft, newTop, measure)
    end
  end
  if ns.GroupLogic then
    ns.GroupLogic.Normalize(layout)
  end
  return not equal(before, layout)
end

-- Undo history ---------------------------------------------------------------------------------

-- Snapshot history that starts at `layout`. clock() gives seconds (GetTime in the game), limit is
-- the number of undo steps (default MAX_UNDO).
function CL.History(layout, clock, limit)
  return {
    states = { U.copy(layout) },
    index = 1,
    clock = type(clock) == "function" and clock or function()
      return 0
    end,
    limit = finite(limit) and math.max(1, math.floor(limit)) or CL.MAX_UNDO,
  }
end

-- Stores the state after a change. A record within MERGE_WINDOW seconds of the last one with the
-- same key (nil counts as a key) replaces it instead of adding a step, so a drag or a held arrow
-- key is one step. Returns false when nothing differs from the current state.
function CL.Record(h, layout, key)
  local current = h.states[h.index]
  if equal(current, layout) then
    return false
  end
  local now = h.clock()
  now = finite(now) and now or 0
  local snap = U.copy(layout)
  if h.at and now - h.at <= CL.MERGE_WINDOW and h.key == key and h.index > 1 then
    h.states[h.index] = snap
    -- A merged step that ended up where it began is no step.
    if equal(h.states[h.index - 1], snap) then
      table.remove(h.states, h.index)
      h.index = h.index - 1
      h.at = nil
      return true
    end
  else
    for i = #h.states, h.index + 1, -1 do
      h.states[i] = nil
    end
    h.states[#h.states + 1] = snap
    if #h.states > h.limit + 1 then
      table.remove(h.states, 1)
    end
    h.index = #h.states
  end
  h.at, h.key = now, key
  return true
end

function CL.CanUndo(h)
  return h.index > 1
end

function CL.CanRedo(h)
  return h.index < #h.states
end

-- The previous state as a new layout, nil at the start of the history.
function CL.Undo(h)
  if not CL.CanUndo(h) then
    return nil
  end
  h.index, h.at = h.index - 1, nil
  return U.copy(h.states[h.index])
end

-- The state after the one undone, as a new layout, nil at the end of the history.
function CL.Redo(h)
  if not CL.CanRedo(h) then
    return nil
  end
  h.index, h.at = h.index + 1, nil
  return U.copy(h.states[h.index])
end

-- Exchange -------------------------------------------------------------------------------------

-- Plain table for ns.Strings.encode(CL.KIND, ...): the repaired layout, JSON safe.
function CL.Pack(layout)
  local clean = CL.Validate(layout)
  return clean
end

-- Layout from a decoded table (the data of an envelope, or saved data), nil and "shape" when it
-- has no canvas and element list. Returns the layout and what had to be repaired. Unknown element
-- types stay.
function CL.Unpack(data)
  if type(data) ~= "table" or type(data.canvas) ~= "table" or type(data.elements) ~= "table" then
    return nil, "shape"
  end
  return CL.Validate(data)
end

-- Host of a layout for the exchange format: "cursor" for a cursor canvas, "area" for an area, else "xpbar".
function CL.HostOf(layout)
  local kind = CL.Kind(layout)
  return kind == "bar" and CL.DEFAULT_HOST or kind
end

-- Exchange string of a layout (one token), or nil and "too-large" | the reason of Strings.encode. The
-- envelope names the host (default: by the canvas kind) so another display can refuse it.
function CL.Export(layout, host)
  local clean = CL.Pack(layout)
  -- Only a layout with groups needs a newer reader: the others stay exactly as before.
  local groups = CL.HasGroups(clean)
  if groups then
    clean.fmt = CL.FORMAT
  end
  local s, why =
    ns.Strings.encode(CL.KIND, clean, nil, type(host) == "string" and host or CL.HostOf(clean), groups and 2 or nil)
  if s and #s > ns.Strings.MAX_INPUT then
    return nil, "too-large"
  end
  return s, why
end

-- Layout from a pasted exchange string. Returns the layout and the repair list, or nil and
-- "empty" | "too-large" | "decode" | "json" | "shape" | "type" | "version" | "host". With `host` ("xpbar",
-- "cursor" or "area") the string must come from that display: one without a host field counts as "xpbar", and the
-- canvas must be of the kind the host draws.
function CL.Import(text, host)
  local env, why = ns.Strings.decode(text)
  if not env then
    return nil, why
  end
  if env.type ~= CL.KIND then
    return nil, "type"
  end
  if env.v > CL.MAX_ENVELOPE then
    return nil, "version"
  end
  local layout, problems = CL.Unpack(env.data)
  if layout then
    layout.fmt = nil
  end
  if layout and host ~= nil then
    local from = type(env.host) == "string" and env.host or CL.DEFAULT_HOST
    local kind = CL.HOSTS[host]
    if from ~= host or (kind and CL.Kind(layout) ~= kind) then
      return nil, "host"
    end
  end
  return layout, problems
end
