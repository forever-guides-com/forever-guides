-- Pure side of the guild members on the minimap (Modules/MinimapGuildSource.lua): the size of a symbol,
-- the world position of a member (its own map, else the middle of the first parent map the client can
-- measure), the selection by filter, group, continent and reach, grouping by yards and the look of one
-- symbol. No frames, no client calls: the frames, the group test and the map parents come in as functions.
-- The filter and the look rules are the ones of the world map (WorldMapGuildLogic).
local _, ns = ...
local ML, GLG = ns.MinimapPinLogic, ns.WorldMapGuildLogic

local MGL = {}
ns.MinimapGuildLogic = MGL

MGL.BASE = 12 -- symbol edge at 100 percent, in pixels
MGL.CONTOUR = 1
MGL.CLUSTER_FACTOR = 1.35
MGL.GROUP_FACTOR = 0.9 -- grouping radius as a share of the symbol edge
MGL.HOLLOW_ALPHA = 0.7

-- Symbol edge in pixels for the percent value of the size option (50 to 200).
function MGL.Size(percent)
  return math.max(1, math.floor(MGL.BASE * GLG.Clamp("miniSize", percent) / 100 + 0.5))
end

-- Grouping radius in world yards: the symbols touch when their centres are closer than this. radius is the
-- yards from the middle of the minimap to its border, halfWidth the same distance in pixels.
function MGL.GroupYards(size, radius, halfWidth)
  if not (ML.finite(radius) and ML.finite(halfWidth) and radius > 0 and halfWidth > 0) then
    return 0
  end
  return size * MGL.GROUP_FACTOR * radius / halfWidth
end

-- World position (yards) of a stored position { map, x, y } (x and y nil for zone only): wx, wy, whether it
-- is only approximate, and the continent. The place itself when `frameOf(map)` has a frame for the map,
-- else the middle of the first map up the chain (`parentOf(id)`, at most GLG.MAX_CLIMB steps) that has one.
-- nil when nothing in the chain can be measured.
function MGL.Locate(entry, frameOf, parentOf)
  local id = entry.map
  for step = 0, GLG.MAX_CLIMB do
    if step > 0 then
      id = parentOf(id)
      if not ML.finite(id) or id <= 0 then
        return nil
      end
    end
    local frame = frameOf(id)
    if frame then
      local exact = step == 0 and ML.finite(entry.x) and ML.finite(entry.y)
      local wx, wy = ML.WorldOf(frame, exact and entry.x or 0.5, exact and entry.y or 0.5)
      return wx, wy, not exact, frame.cont
    end
  end
  return nil
end

-- The members to show, nearest first, as { key, entry, member, wx, wy, dist, approx }. ctx: opts (the
-- clamped options), cont, wx, wy (the player), reach (yards), roster (key -> member of the guild list),
-- isSelf(name), inGroup(name), frameOf, parentOf. A member of another continent, farther than the reach, in the
-- player's group or against the filter falls away.
function MGL.Collect(entries, ctx)
  local out = {}
  for _, e in ipairs(entries) do
    local m = ctx.roster[e.key]
    local member = { known = m ~= nil, level = m and m.level, rank = m and m.rank, online = m and m.online }
    if not ctx.isSelf(e.name) and GLG.Passes(ctx.opts, member) then
      local wx, wy, approx, cont = MGL.Locate(e, ctx.frameOf, ctx.parentOf)
      if wx and cont == ctx.cont then
        local dist = math.sqrt((wx - ctx.wx) ^ 2 + (wy - ctx.wy) ^ 2)
        if dist <= ctx.reach and not ctx.inGroup(e.name) then
          out[#out + 1] = { key = e.key, entry = e, member = m, wx = wx, wy = wy, dist = dist, approx = approx }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.dist ~= b.dist then
      return a.dist < b.dist
    end
    return a.key < b.key
  end)
  return out
end

-- Groups of the items: { wx, wy (centre), items, dist (of the centre) } nearest first, so a cap on the pins
-- keeps the near ones. Without grouping each item is a group of its own.
function MGL.Groups(items, ctx, yards, grouping)
  local points = {}
  for i, item in ipairs(items) do
    points[i] = { key = item.key, px = item.wx, py = item.wy, item = item }
  end
  local out = {}
  for _, g in ipairs(GLG.Group(points, yards, grouping)) do
    local members = {}
    for i, p in ipairs(g.items) do
      members[i] = p.item
    end
    local dist = math.sqrt((g.px - ctx.wx) ^ 2 + (g.py - ctx.wy) ^ 2)
    out[#out + 1] = { wx = g.px, wy = g.py, items = members, dist = dist, key = members[1].key }
  end
  table.sort(out, function(a, b)
    if a.dist ~= b.dist then
      return a.dist < b.dist
    end
    return a.key < b.key
  end)
  return out
end

-- Look of one group: shape and fill as on the world map, the number of a group, rank marks and the label.
function MGL.Spec(group, opts)
  local items = group.items
  local single = #items == 1 and items[1] or nil
  local style = GLG.Style(single and single.approx, single and single.entry.state, single and single.entry.check)
  local member = single and single.member
  return {
    shape = style.shape,
    hollow = single ~= nil and style.hollow,
    cluster = not single and #items or nil,
    member = member,
    ticks = single and opts.showRank and member and GLG.RankTicks(member.rank) or 0,
    text = single and GLG.Label(opts, single.entry.name, member and member.level) or "",
    size = MGL.Size(opts.miniSize),
  }
end
