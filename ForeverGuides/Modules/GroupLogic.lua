-- Groups of the canvas editor (ns.GroupLogic), without WoW API and without frames. A group is an ordinary
-- element of type "group"; a child names it in `group` and its place among the siblings in `slot`. The
-- offsets of a child are measured inside the box of the group (CanvasLogic.Rect). Five arrangements place
-- the children: row, column, grid and circle compute the places, free leaves the children where they are.
--
-- Normalize writes the computed places (full occupancy, order of the slots) into point = TOPLEFT, x and y of
-- every child and the box into w and h of the group, so Rect, hit tests, guides and the exchange string work
-- without a special case. Reflow computes the places for the running game (children that are not there give
-- up their place, the others close up); that result is only kept in memory.
--
-- The model works with any nesting depth (GL.MAX_LEVEL), the first stage allows one level: a group may not
-- sit in a group yet.
local _, ns = ...
local U, L, CL = ns.U, ns.L, ns.CanvasLogic

local GL = {
  TYPE = "group",
  MAX_CHILDREN = 32,
  MAX_LEVEL = 1,
  DEFAULT_SIZE = 32,
  MODES = { "free", "row", "column", "grid", "circle" },
  GROW_ROW = { "right", "left" },
  GROW_COLUMN = { "down", "up" },
  LINE_GROW = { "down", "up" },
  ALIGN = { "start", "center", "end" },
  CELL = { "auto", "uniform" },
  JUSTIFY = { "start", "center", "end" },
  COLLAPSE = { "never", "readable" },
  SORT = { "manual", "active", "remaining", "name" },
  SORT_DIR = { "asc", "desc" },
  DIR = { "cw", "ccw" },
  GAP_MAX = 64,
  COLS_MAX = 16,
  RADIUS_MIN = 8,
  RADIUS_MAX = 512,
  ARC_MIN = 30,
}
ns.GroupLogic = GL

ns.AddLocale("enUS", {
  ["group.name"] = "Group",
})
ns.AddLocale("deDE", {
  ["group.name"] = "Gruppe",
})

-- Places and boxes sit on half pixels like every offset of the canvas.
local STEP = 0.5

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
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

-- A number on a half pixel, never -0 (it would reach the exchange string as "-0").
local function snap(v)
  return U.round(v, STEP) + 0
end

local function up(v)
  return math.ceil(v / STEP - 1e-9) * STEP
end

local function equalValue(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not equalValue(v, b[k]) then
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

-- Props -------------------------------------------------------------------------------------------------------

-- The props of a group with every value valid. Anything unknown stays (a newer version may have written it);
-- the cell of a grid and of a circle is uniform unless chosen otherwise, the growth direction follows the mode.
function GL.Clean(raw)
  raw = type(raw) == "table" and raw or {}
  local out = U.copy(raw)
  local mode = oneOf(raw.mode, GL.MODES, "row")
  out.mode = mode
  out.gap = whole(raw.gap, 4, 0, GL.GAP_MAX)
  out.gapY = finite(raw.gapY) and whole(raw.gapY, nil, 0, GL.GAP_MAX) or nil
  out.cols = whole(raw.cols, 4, 1, GL.COLS_MAX)
  local column = mode == "column"
  out.grow = oneOf(raw.grow, column and GL.GROW_COLUMN or GL.GROW_ROW, column and "down" or "right")
  out.lineGrow = oneOf(raw.lineGrow, GL.LINE_GROW, "down")
  out.align = oneOf(raw.align, GL.ALIGN, "center")
  out.cell = oneOf(raw.cell, GL.CELL, (mode == "grid" or mode == "circle") and "uniform" or "auto")
  out.justify = oneOf(raw.justify, GL.JUSTIFY, "start")
  out.collapse = oneOf(raw.collapse, GL.COLLAPSE, "readable")
  out.sort = oneOf(raw.sort, GL.SORT, "manual")
  out.sortDir = oneOf(raw.sortDir, GL.SORT_DIR, "asc")
  out.radius = whole(raw.radius, 48, GL.RADIUS_MIN, GL.RADIUS_MAX)
  out.start = whole(raw.start, 0, 0, 359)
  out.dir = oneOf(raw.dir, GL.DIR, "cw")
  out.arc = whole(raw.arc, 360, GL.ARC_MIN, 360)
  return out
end

-- Default props of a new group of `mode` (default row).
function GL.NewProps(mode)
  return GL.Clean({ mode = mode })
end

-- Arrangement -------------------------------------------------------------------------------------------------

local function sizeOf(el)
  local h = finite(el.h) and el.h > 0 and el.h or 1
  local w = finite(el.w) and el.w > 0 and el.w or h
  return { w = w, h = h }
end

-- Row or column. Positions are computed along the growth direction (g = 0 at its origin) and mirrored for
-- "left" and "up".
local function arrangeLine(p, sizes, present, vertical)
  local n = #sizes
  local function main(s)
    return vertical and s.h or s.w
  end
  local function cross(s)
    return vertical and s.w or s.h
  end
  local maxMain, maxCross = 0, 0
  for _, s in ipairs(sizes) do
    maxMain, maxCross = math.max(maxMain, main(s)), math.max(maxCross, cross(s))
  end
  local cell, total = {}, p.gap * (n - 1)
  for i, s in ipairs(sizes) do
    cell[i] = p.cell == "uniform" and maxMain or main(s)
    total = total + cell[i]
  end
  local count, used = 0, 0
  for i = 1, n do
    if present[i] then
      count, used = count + 1, used + cell[i]
    end
  end
  used = used + p.gap * math.max(count - 1, 0)
  local free = total - used
  local g = p.justify == "center" and free / 2 or (p.justify == "end" and free or 0)
  local reverse = p.grow == "left" or p.grow == "up"
  local pos, cells = {}, {}
  for i, s in ipairs(sizes) do
    if present[i] then
      local m, c = main(s), cross(s)
      local at = g + (cell[i] - m) / 2
      local mainPos = reverse and (total - at - m) or at
      local cellPos = reverse and (total - g - cell[i]) or g
      local crossPos = p.align == "start" and 0 or (p.align == "end" and maxCross - c or (maxCross - c) / 2)
      if vertical then
        pos[i] = { x = crossPos, y = mainPos, w = s.w, h = s.h }
        cells[i] = { x = 0, y = cellPos, w = maxCross, h = cell[i] }
      else
        pos[i] = { x = mainPos, y = crossPos, w = s.w, h = s.h }
        cells[i] = { x = cellPos, y = 0, w = cell[i], h = maxCross }
      end
      g = g + cell[i] + p.gap
    end
  end
  return { w = vertical and maxCross or total, h = vertical and total or maxCross, pos = pos, cells = cells }
end

local function arrangeGrid(p, sizes, present)
  local n = #sizes
  local cols = p.cols
  local colsUsed = math.min(cols, n)
  local rows = math.ceil(n / cols)
  local gapY = p.gapY or p.gap
  local maxW, maxH = 0, 0
  for _, s in ipairs(sizes) do
    maxW, maxH = math.max(maxW, s.w), math.max(maxH, s.h)
  end
  -- The size of a place belongs to the place: column widths and row heights come from all children.
  local colW, rowH = {}, {}
  for j = 0, colsUsed - 1 do
    colW[j] = p.cell == "uniform" and maxW or 0
  end
  for r = 0, rows - 1 do
    rowH[r] = p.cell == "uniform" and maxH or 0
  end
  if p.cell ~= "uniform" then
    for i, s in ipairs(sizes) do
      local j, r = (i - 1) % cols, math.floor((i - 1) / cols)
      colW[j] = math.max(colW[j], s.w)
      rowH[r] = math.max(rowH[r], s.h)
    end
  end
  local boxW, boxH = p.gap * (colsUsed - 1), gapY * (rows - 1)
  for j = 0, colsUsed - 1 do
    boxW = boxW + colW[j]
  end
  for r = 0, rows - 1 do
    boxH = boxH + rowH[r]
  end
  -- The children that are there fill the places in order.
  local list = {}
  for i = 1, n do
    if present[i] then
      list[#list + 1] = i
    end
  end
  local pos, cells = {}, {}
  for q, i in ipairs(list) do
    local j, r = (q - 1) % cols, math.floor((q - 1) / cols)
    -- Width of the row this child is in (the last one may be short), the rest goes by `justify`.
    local inRow = math.min(cols, #list - r * cols)
    local rowW = p.gap * (inRow - 1)
    for k = 0, inRow - 1 do
      rowW = rowW + colW[k]
    end
    local free = boxW - rowW
    local offset = p.justify == "center" and free / 2 or (p.justify == "end" and free or 0)
    local gx = offset + p.gap * j
    for k = 0, j - 1 do
      gx = gx + colW[k]
    end
    local gy = gapY * r
    for k = 0, r - 1 do
      gy = gy + rowH[k]
    end
    local cw, ch = colW[j], rowH[r]
    local cx = p.grow == "left" and (boxW - gx - cw) or gx
    local cy = p.lineGrow == "up" and (boxH - gy - ch) or gy
    local s = sizes[i]
    pos[i] = { x = cx + (cw - s.w) / 2, y = cy + (ch - s.h) / 2, w = s.w, h = s.h }
    cells[i] = { x = cx, y = cy, w = cw, h = ch }
  end
  return { w = boxW, h = boxH, pos = pos, cells = cells }
end

local function arrangeCircle(p, sizes, present)
  local maxW, maxH, maxSide = 0, 0, 0
  for _, s in ipairs(sizes) do
    maxW, maxH = math.max(maxW, s.w), math.max(maxH, s.h)
    maxSide = math.max(maxSide, s.w, s.h)
  end
  local side = 2 * p.radius + maxSide
  local center = side / 2
  local list = {}
  for i = 1, #sizes do
    if present[i] then
      list[#list + 1] = i
    end
  end
  local count = #list
  local step = 0
  if count > 1 then
    step = p.arc >= 360 and p.arc / count or p.arc / (count - 1)
  end
  local sign = p.dir == "ccw" and -1 or 1
  local pos, cells = {}, {}
  for q, i in ipairs(list) do
    -- 0 degrees is the top, the angle grows clockwise.
    local angle = math.rad(p.start + sign * (q - 1) * step)
    local cx, cy = center + p.radius * math.sin(angle), center - p.radius * math.cos(angle)
    local s = sizes[i]
    pos[i] = { x = cx - s.w / 2, y = cy - s.h / 2, w = s.w, h = s.h }
    cells[i] = { x = cx - maxW / 2, y = cy - maxH / 2, w = maxW, h = maxH }
  end
  return { w = side, h = side, pos = pos, cells = cells }
end

-- Places for children of the given sizes ({ w, h } each, in slot order). `present` (optional) is a list of
-- booleans: a child with false is not there and gives up its place, the others close up. The box is always the
-- one of the full set, so a group never changes its size while children come and go. Returns
-- { w, h, pos = { [i] = { x, y, w, h } }, cells = { [i] = { x, y, w, h } } } (origin top left of the box, y down,
-- floats), nil for a free group and for no children.
function GL.Arrange(props, sizes, present)
  local p = GL.Clean(props)
  if p.mode == "free" or #sizes == 0 then
    return nil
  end
  local here = {}
  for i = 1, #sizes do
    here[i] = not present or present[i] ~= false
  end
  if p.mode == "grid" then
    return arrangeGrid(p, sizes, here)
  elseif p.mode == "circle" then
    return arrangeCircle(p, sizes, here)
  end
  return arrangeLine(p, sizes, here, p.mode == "column")
end

-- Reading the layout --------------------------------------------------------------------------------------------

-- Which of the number fields X, Y, width and height of the panel the arrangement of a group decides, so the
-- editor shows them off: a child of an arranged group sits on a computed place (x, y), the box of an arranged group
-- with children is computed from them (w, h). `parent` is the group of `el` (nil outside a group), `kids` the
-- number of children of `el` when it is a group. Free groups decide nothing. Returns { x, y, w, h } booleans and
-- the reason ("place" or "box"), nil when every field is the element's own.
function GL.FieldLocks(el, parent, kids)
  local function arranged(group)
    return type(group) == "table" and group.type == GL.TYPE and GL.Clean(group.props).mode ~= "free"
  end
  local none = { x = false, y = false, w = false, h = false }
  if type(el) ~= "table" then
    return none
  end
  if el.group ~= nil and type(parent) == "table" and parent.id == el.group and arranged(parent) then
    return { x = true, y = true, w = false, h = false }, "place"
  end
  if arranged(el) and (tonumber(kids) or 0) > 0 then
    return { x = false, y = false, w = true, h = true }, "box"
  end
  return none
end

-- The children of a group by slot (a missing slot after the others, equal slots by list position).
function GL.Children(layout, groupId)
  local list = {}
  for i, el in ipairs(layout.elements) do
    if el.group ~= nil and el.group == groupId then
      list[#list + 1] = { el = el, i = i }
    end
  end
  table.sort(list, function(a, b)
    local sa, sb = a.el.slot or math.huge, b.el.slot or math.huge
    if sa ~= sb then
      return sa < sb
    end
    return a.i < b.i
  end)
  for i, item in ipairs(list) do
    list[i] = item.el
  end
  return list
end

-- Number of groups on the way up from `el`, itself included when it is a group; nil for a loop.
local function chainLevel(el, byId)
  local seen, node, n = {}, el, 0
  while node do
    if seen[node] then
      return nil
    end
    seen[node] = true
    if node.type == GL.TYPE then
      n = n + 1
    end
    node = node.group ~= nil and byId[node.group] or nil
  end
  return n
end

local function idMap(layout)
  local byId = {}
  for _, el in ipairs(layout.elements) do
    byId[el.id] = el
  end
  return byId
end

local function groupsOf(layout)
  local list = {}
  for _, el in ipairs(layout.elements) do
    if el.type == GL.TYPE then
      list[#list + 1] = el
    end
  end
  return list
end

-- Normalize and slots -----------------------------------------------------------------------------------------

local function sizesOf(kids)
  local sizes = {}
  for i, kid in ipairs(kids) do
    sizes[i] = sizeOf(kid)
  end
  return sizes
end

-- Writes the places of the arranged groups (full occupancy, order of the slots) into their children and the
-- box into the group. Inner groups first, they are children with a size. Returns the number of elements that
-- changed.
function GL.Normalize(layout)
  local byId = idMap(layout)
  local groups = groupsOf(layout)
  local level = {}
  for _, g in ipairs(groups) do
    level[g] = chainLevel(g, byId) or 1
  end
  table.sort(groups, function(a, b)
    return level[a] > level[b]
  end)
  local changed = 0
  for _, g in ipairs(groups) do
    local p = GL.Clean(g.props)
    local kids = GL.Children(layout, g.id)
    local w, h = g.w, g.h
    if p.mode ~= "free" and #kids > 0 then
      local a = GL.Arrange(p, sizesOf(kids))
      for i, kid in ipairs(kids) do
        local x, y = snap(a.pos[i].x), 0 - snap(a.pos[i].y)
        local width = sizeOf(kid).w
        if kid.point ~= "TOPLEFT" or kid.x ~= x or kid.y ~= y or kid.w ~= width then
          changed = changed + 1
        end
        kid.point, kid.x, kid.y, kid.w = "TOPLEFT", x, y, width
      end
      g.w, g.h = U.clamp(up(a.w), 1, CL.MAX_SIZE), U.clamp(up(a.h), 1, CL.MAX_SIZE)
    elseif not (finite(g.w) and g.w > 0) then
      g.w = GL.DEFAULT_SIZE
    end
    if g.w ~= w or g.h ~= h then
      changed = changed + 1
    end
  end
  return changed
end

-- Numbers the slots of every group 1..n in their current order; elements outside a group have none.
function GL.Renumber(layout)
  local byId = idMap(layout)
  for _, el in ipairs(layout.elements) do
    if el.group == nil or not byId[el.group] then
      el.slot = nil
    end
  end
  for _, g in ipairs(groupsOf(layout)) do
    for i, kid in ipairs(GL.Children(layout, g.id)) do
      kid.slot = i
    end
  end
end

-- Renumbers the slots and places the children: what every change of a group ends with.
function GL.Settle(layout)
  GL.Renumber(layout)
  GL.Normalize(layout)
end

-- Repair ----------------------------------------------------------------------------------------------------------

local function note(problems, i, key)
  problems[#problems + 1] = "elements[" .. i .. "]." .. key
end

-- Called at the end of CanvasLogic.Validate on the repaired layout: drops every reference that points nowhere
-- (a missing element, an element that is no group, itself, a loop, a level beyond MAX_LEVEL), keeps at most
-- MAX_CHILDREN children per group (the others go back to the canvas where they are), numbers the slots, gives the
-- children of arranged groups a width, cleans the props of the groups and places the children.
function GL.Repair(layout, problems)
  local els = layout.elements
  local byId = idMap(layout)
  for i, el in ipairs(els) do
    if el.group ~= nil then
      local target = byId[el.group]
      if not target or target == el or target.type ~= GL.TYPE then
        el.group = nil
        note(problems, i, "group")
      end
    end
  end
  for i, el in ipairs(els) do
    if el.group ~= nil and el.type == GL.TYPE then
      local level = chainLevel(el, byId)
      if not level or level > GL.MAX_LEVEL then
        el.group = nil
        note(problems, i, "group")
      end
    end
  end
  -- Too many children: the later ones leave the group where they stand.
  for _, g in ipairs(groupsOf(layout)) do
    for n, kid in ipairs(GL.Children(layout, g.id)) do
      if n > GL.MAX_CHILDREN then
        local left, top = CL.AbsRect(layout, kid)
        kid.group, kid.slot = nil, nil
        CL.Place(layout, kid, left, top)
        for k, el in ipairs(els) do
          if el == kid then
            note(problems, k, "group")
          end
        end
      end
    end
  end
  for i, el in ipairs(els) do
    if el.group == nil and el.slot ~= nil then
      el.slot = nil
      note(problems, i, "slot")
    elseif el.group ~= nil and el.slot == nil then
      note(problems, i, "slot")
    end
  end
  GL.Renumber(layout)
  for i, el in ipairs(els) do
    if el.type == GL.TYPE then
      local clean = GL.Clean(el.props)
      for k, v in pairs(el.props) do
        if not equalValue(v, clean[k]) then
          note(problems, i, "props")
          break
        end
      end
      el.props = clean
    elseif el.group ~= nil and el.w <= 0 then
      local parent = byId[el.group]
      if parent and GL.Clean(parent.props).mode ~= "free" then
        el.w = el.h
        note(problems, i, "w")
      end
    end
  end
  GL.Normalize(layout)
end

CL.OnValidate(GL.Repair)

-- Operations ----------------------------------------------------------------------------------------------------

local function idOf(ref)
  return type(ref) == "table" and ref.id or ref
end

-- The elements of a list of ids or tables, once each, in the order given; groups only when `groupsToo`.
local function pick(layout, ids, groupsToo)
  local out, seen = {}, {}
  for _, ref in ipairs(type(ids) == "table" and ids or { ids }) do
    local el = CL.Find(layout, idOf(ref))
    if el and not seen[el] and (groupsToo or el.type ~= GL.TYPE) then
      seen[el] = true
      out[#out + 1] = el
    end
  end
  return out
end

-- Width of an element that sizes itself: what `measure` says, else its height.
local function fixedWidth(el, measure)
  if el.w > 0 then
    return el.w
  end
  local w = measure and measure(el)
  return finite(w) and w > 0 and w or el.h
end

-- Takes children out of their groups (into the group of that group, or onto the canvas) where they stand.
local function release(layout, kids)
  local byId = idMap(layout)
  for _, kid in ipairs(kids) do
    local from = byId[kid.group]
    if from then
      local left, top = CL.AbsRect(layout, kid)
      local dest = from.group ~= nil and byId[from.group] or nil
      kid.group = dest and dest.id or nil
      kid.slot = dest and (from.slot or 0) + 0.5 or nil
      if dest then
        local gl, gt = CL.AbsRect(layout, dest)
        CL.Place(layout, kid, left - gl, top - gt)
      else
        kid.z = from.z
        CL.Place(layout, kid, left, top)
      end
    end
  end
end

-- Makes a group around the given elements (ids or tables, ones that are groups are left out). `opts`
-- (optional): mode or props, name, id (a wish, made unique), measure(element) -> width for elements that size
-- themselves. The box
-- fits around them, the first stage keeps them in the order given. A free group keeps the places of the
-- elements; an arranged one places them. Returns the group, or nil and "limit" | "none".
function GL.Wrap(layout, ids, opts)
  opts = opts or {}
  local kids = pick(layout, ids, false)
  for i = #kids, 1, -1 do
    if kids[i].group ~= nil then
      table.remove(kids, i)
    end
  end
  if #kids == 0 then
    return nil, "none"
  end
  if #layout.elements >= CL.MAX_ELEMENTS or #kids > GL.MAX_CHILDREN then
    return nil, "limit"
  end
  local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
  local z = -math.huge
  for _, kid in ipairs(kids) do
    kid.w = fixedWidth(kid, opts.measure)
    local l, t, w, h = CL.AbsRect(layout, kid)
    left, top = math.min(left, l), math.min(top, t)
    right, bottom = math.max(right, l + w), math.max(bottom, t + h)
    z = math.max(z, kid.z)
  end
  local used = idMap(layout)
  local props = GL.Clean(type(opts.props) == "table" and opts.props or { mode = opts.mode })
  local name = type(opts.name) == "string" and opts.name ~= "" and opts.name or L["group.name"]
  local group = {
    id = CL.UniqueId(opts.id or GL.TYPE, used),
    type = GL.TYPE,
    name = CL.CleanText(name, CL.MAX_NAME),
    point = "TOPLEFT",
    x = 0,
    y = 0,
    w = up(right - left),
    h = up(bottom - top),
    z = z,
    visible = true,
    props = props,
  }
  layout.elements[#layout.elements + 1] = group
  CL.Place(layout, group, left, top)
  local positions = {}
  for i, kid in ipairs(kids) do
    positions[i] = { CL.AbsRect(layout, kid) }
  end
  local gl, gt = CL.AbsRect(layout, group)
  for i, kid in ipairs(kids) do
    kid.group, kid.slot = group.id, i
    -- A free group keeps the places: the offsets are measured from the new box now.
    CL.Place(layout, kid, positions[i][1] - gl, positions[i][2] - gt)
  end
  GL.Settle(layout)
  return group
end

-- Moves elements (ids or tables) into a group at place `index` (default: the end). They stay where they are on
-- the screen in a free group, an arranged group puts them on their places. `measure` (optional) gives the
-- width of elements that size themselves. Returns the number moved, or nil and "group" | "limit" | "level".
function GL.MoveInto(layout, ids, groupId, index, measure)
  local group = CL.Find(layout, idOf(groupId))
  if not group or group.type ~= GL.TYPE then
    return nil, "group"
  end
  local byId = idMap(layout)
  local moving = {}
  for _, el in ipairs(pick(layout, ids, true)) do
    if el ~= group then
      if el.type == GL.TYPE then
        local own = chainLevel(group, byId)
        if not own or own + 1 > GL.MAX_LEVEL then
          return nil, "level"
        end
      end
      moving[#moving + 1] = el
    end
  end
  local mine = {}
  for _, el in ipairs(moving) do
    mine[el] = true
  end
  local rest = {}
  for _, kid in ipairs(GL.Children(layout, group.id)) do
    if not mine[kid] then
      rest[#rest + 1] = kid
    end
  end
  if #rest + #moving > GL.MAX_CHILDREN then
    return nil, "limit"
  end
  local before = {}
  for i, el in ipairs(moving) do
    before[i] = { CL.AbsRect(layout, el, measure) }
    el.w = fixedWidth(el, measure)
  end
  local at = U.clamp(finite(index) and math.floor(index) or #rest + 1, 1, #rest + 1)
  for i, el in ipairs(moving) do
    table.insert(rest, at + i - 1, el)
  end
  for i, el in ipairs(rest) do
    el.group, el.slot = group.id, i
  end
  local gl, gt = CL.AbsRect(layout, group)
  for i, el in ipairs(moving) do
    CL.Place(layout, el, before[i][1] - gl, before[i][2] - gt)
  end
  GL.Settle(layout)
  return #moving
end

-- Takes elements (ids or tables) out of their groups; they stay where they are. Returns the number moved.
function GL.MoveOut(layout, ids)
  local kids = {}
  for _, el in ipairs(pick(layout, ids, true)) do
    if el.group ~= nil then
      kids[#kids + 1] = el
    end
  end
  release(layout, kids)
  GL.Settle(layout)
  return #kids
end

-- Removes a group (table or id). "dissolve" keeps the children where they are on the screen, "all" removes them
-- too. Returns the group and its index, nil and "group" when it is no group.
function GL.Remove(layout, ref, how)
  local group, index = CL.Find(layout, idOf(ref))
  if not group or group.type ~= GL.TYPE then
    return nil, "group"
  end
  if how == "all" then
    local doomed = { [group] = true }
    local grew = true
    while grew do
      grew = false
      for _, el in ipairs(layout.elements) do
        if not doomed[el] and el.group ~= nil and doomed[CL.Find(layout, el.group)] then
          doomed[el], grew = true, true
        end
      end
    end
    for i = #layout.elements, 1, -1 do
      if doomed[layout.elements[i]] then
        table.remove(layout.elements, i)
      end
    end
  else
    release(layout, GL.Children(layout, group.id))
    local _, now = CL.Find(layout, group)
    table.remove(layout.elements, now)
  end
  GL.Settle(layout)
  return group, index
end

-- Dissolves a group: the children stay where they are.
function GL.Ungroup(layout, ref)
  return GL.Remove(layout, ref, "dissolve")
end

-- Copies a group with its children (new ids, the name through CanvasLogic.CopyName) a few pixels down and to the
-- right, on top. Returns the new group, or nil and "missing" | "limit" | "max" (a type limit of `types`) with the
-- layout left alone.
function GL.Duplicate(layout, ref, types)
  local group = CL.Find(layout, idOf(ref))
  if not group or group.type ~= GL.TYPE then
    return nil, "missing"
  end
  local kids = GL.Children(layout, group.id)
  if #layout.elements + 1 + #kids > CL.MAX_ELEMENTS then
    return nil, "limit"
  end
  local need = {}
  for _, kid in ipairs(kids) do
    need[kid.type] = (need[kid.type] or 0) + 1
  end
  for kind, n in pairs(need) do
    local def = type(types) == "table" and types[kind] or nil
    if type(def) == "table" and finite(def.max) then
      local have = 0
      for _, el in ipairs(layout.elements) do
        have = have + (el.type == kind and 1 or 0)
      end
      if have + n > def.max then
        return nil, "max"
      end
    end
  end
  local copy = U.copy(group)
  copy.id, copy.z = nil, nil
  copy.name = CL.CopyName(layout, group.name)
  CL.Move(copy, CL.COPY_OFFSET, CL.COPY_OFFSET)
  local made, why = CL.AddElement(layout, copy, types)
  if not made then
    return nil, why
  end
  for _, kid in ipairs(kids) do
    local child = U.copy(kid)
    child.id, child.z = nil, nil
    child.group = made.id
    CL.AddElement(layout, child, types)
  end
  GL.Settle(layout)
  return made
end

-- Moves a child among its siblings: "up" and "down" one place in the list (up = toward the first), "first" or
-- "last", or a number: that place among the siblings. Renumbers the slots and places the children. Returns true
-- when the order changed.
function GL.Reorder(layout, ref, how)
  local el = CL.Find(layout, idOf(ref))
  if not el or el.group == nil then
    return false
  end
  local list = GL.Children(layout, el.group)
  local from
  for i, kid in ipairs(list) do
    if kid == el then
      from = i
    end
  end
  if not from then
    return false
  end
  local to
  if how == "up" then
    to = math.max(1, from - 1)
  elseif how == "down" then
    to = math.min(#list, from + 1)
  elseif how == "first" then
    to = 1
  elseif how == "last" then
    to = #list
  elseif finite(how) then
    to = U.clamp(math.floor(how), 1, #list)
  else
    return false
  end
  if to == from then
    return false
  end
  table.remove(list, from)
  table.insert(list, to, el)
  for i, kid in ipairs(list) do
    kid.slot = i
  end
  GL.Normalize(layout)
  return true
end

-- Changes props of a group (the others stay). Free to arranged puts the children on their places, arranged to
-- free keeps the places they have. Returns true when something changed, false for a missing group.
function GL.SetMode(layout, ref, props)
  local group = CL.Find(layout, idOf(ref))
  if not group or group.type ~= GL.TYPE or type(props) ~= "table" then
    return false
  end
  local merged = U.copy(group.props)
  for k, v in pairs(props) do
    merged[k] = v
  end
  local clean = GL.Clean(merged)
  local before = U.copy(layout)
  group.props = clean
  GL.Normalize(layout)
  return not equalValue(before, layout)
end

-- Running game -------------------------------------------------------------------------------------------------

local function numberOf(readings, id, key)
  local r = readings and readings[id]
  local v = type(r) == "table" and r[key] or nil
  return finite(v) and v or nil
end

-- The children in the order the sorting of the group asks for. readings = { [id] = { active = true | false | nil
-- (running, ready, unknown), remaining = seconds | nil } }. `frozen` (optional, a list of ids) keeps the last order
-- of a sorting by remaining time while the time cannot be read (combat): ids that are gone drop out, new ones come
-- last in slot order. The sort is stable, equal children stay in slot order.
function GL.Order(children, props, readings, frozen)
  local p = GL.Clean(props)
  local list, index = {}, {}
  for i, el in ipairs(children) do
    list[i], index[el] = el, i
  end
  if p.sort == "manual" then
    return list
  end
  if p.sort == "remaining" and type(frozen) == "table" then
    local rank = {}
    for i, id in ipairs(frozen) do
      rank[id] = rank[id] or i
    end
    table.sort(list, function(a, b)
      local ra, rb = rank[a.id] or math.huge, rank[b.id] or math.huge
      if ra ~= rb then
        return ra < rb
      end
      return index[a] < index[b]
    end)
    return list
  end
  local desc = p.sortDir == "desc"
  local function before(a, b)
    if p.sort == "name" then
      local na, nb = tostring(a.name or ""):lower(), tostring(b.name or ""):lower()
      if na ~= nb then
        return (na < nb) ~= desc
      end
    elseif p.sort == "active" then
      -- Running, unknown, ready.
      local function rank(el)
        local active = readings and readings[el.id] and readings[el.id].active
        return active == true and 1 or (active == false and 3 or 2)
      end
      local ra, rb = rank(a), rank(b)
      if ra ~= rb then
        return (ra < rb) ~= desc
      end
    else
      local ta, tb = numberOf(readings, a.id, "remaining"), numberOf(readings, b.id, "remaining")
      if ta ~= tb then
        if ta == nil or tb == nil then
          return ta ~= nil
        end
        return (ta < tb) ~= desc
      end
    end
    return index[a] < index[b]
  end
  table.sort(list, before)
  return list
end

-- The places of the children of a group for the running game, relative to the box of the group. occupancy =
-- { [id] = "yes" | "no" | nil (not known) }: with collapse "readable" a child that is "no" gives up its place
-- and the others close up, a child that is not known keeps one. readings and frozen as in Order. Returns
-- { order = { ids }, pos = { [id] = { x, y } } (origin top left, y down, a child without a place is missing),
-- w, h }, nil for a free group and for no children.
function GL.Reflow(layout, groupId, occupancy, readings, frozen)
  local group = CL.Find(layout, groupId)
  if not group or group.type ~= GL.TYPE then
    return nil
  end
  local p = GL.Clean(group.props)
  local kids = GL.Children(layout, group.id)
  if p.mode == "free" or #kids == 0 then
    return nil
  end
  local ordered = GL.Order(kids, p, readings, frozen)
  local present, order = {}, {}
  for i, kid in ipairs(ordered) do
    order[i] = kid.id
    present[i] = p.collapse == "never" or not occupancy or occupancy[kid.id] ~= "no"
  end
  local a = GL.Arrange(p, sizesOf(ordered), present)
  local pos = {}
  for i, kid in ipairs(ordered) do
    if a.pos[i] then
      pos[kid.id] = { x = snap(a.pos[i].x), y = snap(a.pos[i].y) }
    end
  end
  return { order = order, pos = pos, w = up(a.w), h = up(a.h) }
end

-- Occupancy -------------------------------------------------------------------------------------------------------

local occupancyOf, readingOf = {}, {}

-- Tells how one element type reports whether its frame holds a place: fn(frame, element) -> "yes" | "no" | nil
-- (not known, the game keeps it secret).
function GL.RegisterOccupancy(kind, fn)
  occupancyOf[kind] = fn
end

-- Tells what one element type reads for the sorting: fn(frame, element, combat) -> { active, remaining }.
function GL.RegisterReading(kind, fn)
  readingOf[kind] = fn
end

-- "yes", "no" or nil for an element and its frame. A hidden element is "no", a type nobody registered is "yes"
-- (it cannot hide), an adapter that fails or answers anything else gives nil (the place stays).
function GL.Occupancy(el, frame)
  if el.visible == false then
    return "no"
  end
  local fn = occupancyOf[el.type]
  if not fn then
    return "yes"
  end
  local ok, value = pcall(fn, frame, el)
  if ok and (value == "yes" or value == "no") then
    return value
  end
  return nil
end

-- What the sorting reads of one element, nil when its type reads nothing.
function GL.Reading(el, frame, combat)
  local fn = readingOf[el.type]
  if not fn then
    return nil
  end
  local ok, value = pcall(fn, frame, el, combat)
  return ok and type(value) == "table" and value or nil
end

-- Status ----------------------------------------------------------------------------------------------------------

-- How a child behaves in combat: "known" (its state is readable), "calc" (a calculated aura), "secret" (the game
-- decides, Lua does not learn it). `caps.classify(element)` replaces this rule.
local function classify(el, caps)
  if type(caps.classify) == "function" then
    return caps.classify(el)
  end
  if el.visible == false then
    return "known"
  end
  local CU = ns.CursorLogic
  local p = CU and CU.Has(el.type) and CU.Props(el.type, el.props, { el.w, el.h }) or el.props or {}
  if p.showWhen == "below" then
    return "secret"
  elseif el.type == "aura" then
    local NL = ns.AuraNativeLogic
    return NL and NL.Plan(p, caps).mode == "native" and "secret" or "calc"
  end
  return "known"
end

-- What a group does in combat, for the line "Works in combat". Returns { key, color, notes, kids }: key "fixed"
-- (the places are fixed, nothing closes up), "readable" (children close up, every state is readable) or
-- "partial" (at least one child keeps its place because the game keeps its state secret); color a theme colour
-- name; notes the lines to say in addition ("remaining": the order by remaining time is the one from the start of
-- the fight); kids = { { id, mode = "known" | "calc" | "secret" } }.
function GL.Status(layout, groupId, caps)
  local group = CL.Find(layout, groupId)
  if not group or group.type ~= GL.TYPE then
    return nil
  end
  caps = type(caps) == "table" and caps or {}
  local p = GL.Clean(group.props)
  local kids, secret = {}, false
  for i, kid in ipairs(GL.Children(layout, group.id)) do
    local mode = classify(kid, caps)
    kids[i] = { id = kid.id, mode = mode }
    secret = secret or mode == "secret"
  end
  local moves = p.mode ~= "free" and (p.collapse == "readable" or p.sort ~= "manual")
  local key = (not moves) and "fixed" or (secret and "partial" or "readable")
  local notes = {}
  if p.mode ~= "free" and p.sort == "remaining" then
    notes[#notes + 1] = "remaining"
  end
  return { key = key, color = key == "partial" and "warning" or "success", notes = notes, kids = kids }
end
