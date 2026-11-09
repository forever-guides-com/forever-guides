-- The element list of the canvas editor as a tree, and the moves a drag in that list or on the canvas asks for
-- (ns.GroupTree), without WoW API. Rows shows the elements on the canvas front to back with the children of a
-- group under it (first slot first, the reading order of the canvas); Target says what a row let go at the cursor
-- would do and Move does it; PlaceAt names the place a child of an arranged group is dragged to.
local _, ns = ...
local CL, GL = ns.CanvasLogic, ns.GroupLogic

local GT = {}
ns.GroupTree = GT

local function byId(layout)
  local map = {}
  for _, el in ipairs(layout.elements) do
    map[el.id] = el
  end
  return map
end

-- A child whose group is missing counts as an element on the canvas, so it never drops out of the list.
local function parentOf(el, map)
  local parent = el.group ~= nil and map[el.group] or nil
  return parent and parent ~= el and parent.type == GL.TYPE and parent or nil
end

-- The rows of the list, top to bottom: { el, depth (0 or 1), isGroup, open, count }. `folded` is a set of group
-- ids whose children are not listed (nil lists all). Elements on the canvas come front first (z descending), a
-- group is followed by its children by slot.
function GT.Rows(layout, folded)
  folded = folded or {}
  local map = byId(layout)
  local rows = {}
  local sorted = CL.Sorted(layout)
  for i = #sorted, 1, -1 do
    local el = sorted[i]
    if not parentOf(el, map) then
      local isGroup = el.type == GL.TYPE
      local kids = isGroup and GL.Children(layout, el.id) or {}
      local open = isGroup and folded[el.id] ~= true
      rows[#rows + 1] = { el = el, depth = 0, isGroup = isGroup, open = open or false, count = #kids }
      if open then
        for _, kid in ipairs(kids) do
          rows[#rows + 1] = { el = kid, depth = 1, isGroup = kid.type == GL.TYPE, open = false, count = 0 }
        end
      end
    end
  end
  return rows
end

-- Horizontal metrics of a list row in px (the icons are fixed size, so none of this scales with the font):
-- BASE is the left edge of the first level after the eye, INDENT one level of children, FOLD and GLYPH the arrow
-- and folder icon in front of a group name, RIGHT_W the arrows, copy, pencil and trash with their gaps at the right
-- edge, SYMBOL the symbol of what an element shows with its gap in front of the name of a row that is no group.
GT.BASE, GT.INDENT, GT.FOLD, GT.GLYPH, GT.RIGHT_W, GT.SYMBOL = 24, 16, 24, 18, 120, 20

-- Left edges inside a row of `depth`: the arrow of a group (nil for other rows) and the name. The name of a
-- child starts one INDENT right of the name of its group, so the child never looks less indented than the group.
-- A plain top level row keeps BASE, so a layout without groups looks as before.
function GT.RowLeft(depth, isGroup)
  local icons = GT.FOLD + GT.GLYPH
  local left = GT.BASE + depth * GT.INDENT
  if isGroup then
    return left, left + icons
  end
  return nil, depth > 0 and left + icons or left
end

-- Center of the guide line of the children at `depth` (under the arrow of their group).
function GT.GuideX(depth)
  return GT.BASE + (depth - 1) * GT.INDENT + GT.FOLD / 2
end

-- Puts a top level element at a place among the other top level elements: just in front of `anchor` ("front")
-- or just behind it ("back"). Renumbers z of all of them to 1..n.
local function placeZ(layout, el, anchor, where)
  local list = CL.Sorted(layout, false)
  for i = #list, 1, -1 do
    if list[i] == el then
      table.remove(list, i)
    end
  end
  local at = #list + 1
  for i, item in ipairs(list) do
    if item == anchor then
      at = where == "front" and i + 1 or i
    end
  end
  table.insert(list, at, el)
  for i, item in ipairs(list) do
    item.z = i
  end
end

-- Where a drag in the list lands -------------------------------------------------------------------------------

-- Share of a group row (top and bottom) that counts as the gap before or behind it; the middle part is "into".
GT.EDGE = 0.25

-- Where the cursor must be, in px from the left edge of the list, to take a row behind the last child of a group
-- into that group (right of it) or out of it (left of it): halfway between the two lines.
function GT.OutdentX()
  return (GT.BASE + (select(2, GT.RowLeft(1, false)))) / 2
end

local function hasGroup(layout)
  for _, el in ipairs(layout.elements) do
    if el.type == GL.TYPE then
      return true
    end
  end
  return false
end

-- Position among the children of `group` (without `skipId`) just before the child `beforeId`, nil for the end.
local function slotBefore(layout, group, beforeId, skipId)
  local at = 0
  for _, kid in ipairs(GL.Children(layout, group)) do
    if kid.id == beforeId then
      return at + 1
    end
    if kid.id ~= skipId then
      at = at + 1
    end
  end
end

-- What a row let go at the cursor does. `rows` is GT.Rows as shown, `index` the row under the cursor, `frac`
-- (0..1) how far down in that row the cursor is and `x` its distance from the left edge of the list (nil: the
-- left one). Returns nil when nothing would change, else a table:
--   gap     line number 0..#rows the drop line is drawn at (nil for "into")
--   row     the row of the group that takes the element at its end ("into" only), or the row a refusal is about
--   head    the row of the group a line between its children belongs to
--   indent  left end of the line in px (nil for a layout without a group: the line keeps the full width)
--   into, index    the group and the place in it (index nil: the end), for a drop into a group
--   anchor, where  a drop on the canvas: just "front" or "back" of that element in the z order
--   refuse  "level" (a group cannot go into a group), "self" (a group into itself) or "limit" (group is full)
function GT.Target(layout, rows, dragId, index, frac, x)
  local map = byId(layout)
  local drag, hover = map[dragId], rows[index]
  if not drag or not hover then
    return nil
  end
  local isGroup = drag.type == GL.TYPE
  local grouped = hasGroup(layout)
  local childLeft = (select(2, GT.RowLeft(1, false)))
  local function ownBlock(row)
    return row.el == drag or (row.depth > 0 and row.el.group == dragId)
  end

  local function intoGroup(groupRow, at)
    local group = groupRow.el
    if isGroup then
      return { row = at, refuse = group == drag and "self" or "level" }
    end
    local kids = GL.Children(layout, group.id)
    if drag.group ~= group.id and #kids >= GL.MAX_CHILDREN then
      return { row = at, refuse = "limit" }
    end
    if kids[#kids] == drag then
      return nil
    end
    return { row = at, into = group.id }
  end

  -- A place on the canvas after the first `count` rows, i.e. in the z order among the elements on the canvas.
  local function onCanvas(gap)
    local tops, before = {}, 0
    for i, row in ipairs(rows) do
      if row.depth == 0 and row.el ~= drag then
        tops[#tops + 1] = row.el
        if i <= gap then
          before = before + 1
        end
      end
    end
    if #tops == 0 then
      return nil
    end
    if drag.group == nil then
      local mine = 0
      for _, row in ipairs(rows) do
        if row.el == drag then
          break
        end
        if row.depth == 0 then
          mine = mine + 1
        end
      end
      if mine == before then
        return nil
      end
    end
    local target = { gap = gap, indent = grouped and GT.BASE or nil }
    if before < #tops then
      target.anchor, target.where = tops[before + 1].id, "front"
    else
      target.anchor, target.where = tops[#tops].id, "back"
    end
    return target
  end

  local function atGap(gap)
    local prev, nxt = rows[gap], rows[gap + 1]
    if isGroup then
      if (prev and ownBlock(prev) and nxt and ownBlock(nxt)) or (nxt and nxt.depth > 0 and nxt.el.group == dragId) then
        return { row = index, refuse = "self" }
      end
      if nxt and nxt.depth > 0 then
        return { row = index, refuse = "level" }
      end
      return onCanvas(gap)
    end
    local into, place
    if nxt and nxt.depth > 0 then
      into, place = nxt.el.group, slotBefore(layout, nxt.el.group, nxt.el.id, dragId)
    elseif prev and prev.depth > 0 and (x or 0) >= GT.OutdentX() then
      into = prev.el.group
    elseif prev and prev.isGroup and prev.open and prev.count == 0 and (x or 0) >= GT.OutdentX() then
      into = prev.el.id
    end
    if not into then
      return onCanvas(gap)
    end
    local kids = GL.Children(layout, into)
    if drag.group ~= into and #kids >= GL.MAX_CHILDREN then
      return { row = index, refuse = "limit" }
    end
    if drag.group == into then
      local current
      for i, kid in ipairs(kids) do
        if kid == drag then
          current = i
        end
      end
      if (place or #kids) == current then
        return nil
      end
    end
    local head
    for i, row in ipairs(rows) do
      if row.depth == 0 and row.el.id == into then
        head = i
      end
    end
    return { gap = gap, head = head, into = into, index = place, indent = childLeft }
  end

  if hover.isGroup then
    if hover.el == drag then
      return nil
    end
    if frac >= GT.EDGE and frac <= 1 - GT.EDGE then
      return intoGroup(hover, index)
    end
    return atGap(frac < GT.EDGE and index - 1 or index)
  end
  return atGap(frac < 0.5 and index - 1 or index)
end

-- Carries out the drop `target` of GT.Target for element `id`. Returns true, or nil and the reason: "level",
-- "self", "limit", "group" or "missing".
function GT.Move(layout, id, target, measure)
  local map = byId(layout)
  local el = map[id]
  if not el or type(target) ~= "table" then
    return nil, "missing"
  end
  if target.refuse then
    return nil, target.refuse
  end
  if target.into then
    local moved, why = GL.MoveInto(layout, { id }, target.into, target.index, measure)
    if not moved then
      return nil, why
    end
    return true
  end
  local anchor = map[target.anchor]
  if not anchor then
    return nil, "missing"
  end
  if parentOf(el, map) then
    GL.MoveOut(layout, { id })
  end
  placeZ(layout, el, anchor, target.where)
  return true
end

-- The keyboard twin of a drag. IndentTarget: the element joins the group right above it in the list, at its end.
-- Returns the target for GT.Move, or nil and "missing", "level" (a group), "in" (a child already), "above" (no
-- group right above it) or "limit".
function GT.IndentTarget(layout, id)
  local map = byId(layout)
  local el = map[id]
  if not el then
    return nil, "missing"
  end
  if el.type == GL.TYPE then
    return nil, "level"
  end
  if parentOf(el, map) then
    return nil, "in"
  end
  local above
  for _, row in ipairs(GT.Rows(layout)) do
    if row.el == el then
      break
    end
    if row.depth == 0 then
      above = row.el
    end
  end
  if not (above and above.type == GL.TYPE) then
    return nil, "above"
  end
  if #GL.Children(layout, above.id) >= GL.MAX_CHILDREN then
    return nil, "limit"
  end
  return { into = above.id }
end

-- OutdentTarget: a child steps out of its group to the canvas, directly behind the group in the list. Nil and
-- "missing" or "top" (not in a group).
function GT.OutdentTarget(layout, id)
  local map = byId(layout)
  local el = map[id]
  if not el then
    return nil, "missing"
  end
  local group = parentOf(el, map)
  if not group then
    return nil, "top"
  end
  return { anchor = group.id, where = "back" }
end

-- The place (1..n) among the children of an arranged group that is nearest to the point x, y of the canvas, and
-- the box of that place { l, t, w, h }. Places are the boxes of the children as they stand now. Nil for a group
-- without children.
function GT.PlaceAt(layout, groupId, x, y, measure)
  local best, bestDist, box
  for i, kid in ipairs(GL.Children(layout, groupId)) do
    local l, t, w, h = CL.AbsRect(layout, kid, measure)
    local dx, dy = x - (l + w / 2), y - (t + h / 2)
    local dist = dx * dx + dy * dy
    if not bestDist or dist < bestDist then
      best, bestDist, box = i, dist, { l = l, t = t, w = w, h = h }
    end
  end
  return best, box
end

-- Whether children of the group sit on computed places (anything but a free group).
function GT.Arranged(group)
  return group ~= nil and group.type == GL.TYPE and GL.Clean(group.props).mode ~= "free"
end

-- The ids on the way from `id` up to the canvas (the group of a child), for opening a folded group.
function GT.GroupOf(layout, id)
  local map = byId(layout)
  local el = map[id]
  local parent = el and parentOf(el, map)
  return parent and parent.id or nil
end

-- Every element in drawing order (back to front): a group, then its children by slot. Without groups this is
-- the z order of CanvasLogic.Sorted. The order Tab walks through.
function GT.Cycle(layout)
  local map = byId(layout)
  local out = {}
  for _, el in ipairs(CL.Sorted(layout)) do
    if not parentOf(el, map) then
      out[#out + 1] = el
      if el.type == GL.TYPE then
        for _, kid in ipairs(GL.Children(layout, el.id)) do
          out[#out + 1] = kid
        end
      end
    end
  end
  return out
end

-- The visible elements front to back as the mouse meets them: the children of a group (last slot first) before
-- the group itself, so a click on a child never lands on its group. A child of a hidden group is not there.
function GT.HitOrder(layout)
  local map = byId(layout)
  local out = {}
  local sorted = CL.Sorted(layout)
  for i = #sorted, 1, -1 do
    local el = sorted[i]
    if el.visible ~= false and not parentOf(el, map) then
      if el.type == GL.TYPE then
        local kids = GL.Children(layout, el.id)
        for k = #kids, 1, -1 do
          if kids[k].visible ~= false then
            out[#out + 1] = kids[k]
          end
        end
      end
      out[#out + 1] = el
    end
  end
  return out
end
