-- The element list of the canvas editor as a tree, and the moves a drag in that list or on the canvas asks for
-- (ns.GroupTree), without WoW API. Rows shows the elements on the canvas front to back with the children of a
-- group under it (first slot first, the reading order of the canvas); Drop turns "this row was let go before or
-- after that row" into a group operation; PlaceAt names the place a child of an arranged group is dragged to.
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
-- and folder icon in front of a group name, RIGHT_W the arrows, pencil and trash with their gaps at the right edge.
GT.BASE, GT.INDENT, GT.FOLD, GT.GLYPH, GT.RIGHT_W = 24, 16, 24, 18, 96

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

-- The group an element let go before (`after` false) or after `anchor` would join, and the place in it, or nil
-- when it would take a place on the canvas. An element joins the group of a child it was let go next to, at that
-- place; next to the heading of an open group it becomes its first child.
local function joins(layout, map, el, anchor, after, folded)
  local anchorGroup = parentOf(anchor, map)
  if anchorGroup then
    local at = 1
    for i, kid in ipairs(GL.Children(layout, anchorGroup.id)) do
      if kid == anchor then
        at = i
      end
    end
    -- The dragged child itself no longer counts when it sits before the anchor.
    for i, kid in ipairs(GL.Children(layout, anchorGroup.id)) do
      if kid == el and i < at then
        at = at - 1
      end
    end
    return anchorGroup, after and at + 1 or at
  elseif anchor.type == GL.TYPE and after and el.type ~= GL.TYPE and not (folded or {})[anchor.id] then
    return anchor, 1
  end
end

-- The move for a row that was let go before (`after` false) or after the row of `anchorId`. An element joins the
-- group of a child it was let go next to, at that place; let go next to the heading of an open group it becomes
-- its first child; next to anything else on the canvas it leaves its group and takes that place in the z order.
-- Returns true, or nil and "level" (a group cannot go into a group), "limit" (the group is full), "missing" or
-- "same" (nothing to do).
function GT.Drop(layout, id, anchorId, after, folded, measure)
  local map = byId(layout)
  local el, anchor = map[id], map[anchorId]
  if not el or not anchor then
    return nil, "missing"
  end
  if el == anchor then
    return nil, "same"
  end
  local into, index = joins(layout, map, el, anchor, after, folded)
  if into then
    if el.type == GL.TYPE then
      return nil, "level"
    end
    local moved, why = GL.MoveInto(layout, { el.id }, into.id, index, measure)
    if not moved then
      return nil, why
    end
    return true
  end
  if parentOf(el, map) then
    GL.MoveOut(layout, { el.id })
  end
  placeZ(layout, el, anchor, after and "back" or "front")
  return true
end

-- Where the line that marks a drop starts, in px from the left edge of a list row: the left edge of the name of a
-- child when the drop would put the row into a group, GT.BASE when it takes a place on the canvas. nil for a
-- layout without a group, whose list keeps the full width line, and for a drop that does nothing or is refused.
function GT.DropIndent(layout, id, anchorId, after, folded)
  local map = byId(layout)
  local el, anchor = map[id], map[anchorId]
  if not el or not anchor or el == anchor then
    return nil
  end
  local hasGroup = false
  for _, other in ipairs(layout.elements) do
    hasGroup = hasGroup or other.type == GL.TYPE
  end
  if not hasGroup then
    return nil
  end
  if joins(layout, map, el, anchor, after, folded) and el.type ~= GL.TYPE then
    return (select(2, GT.RowLeft(1, false)))
  end
  return GT.BASE
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
