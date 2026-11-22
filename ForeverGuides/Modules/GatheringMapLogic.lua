-- Ore and herb spots on the Forever map, pure side (no frames): which points a zone shows, how big the
-- symbols are, which of them lie in the visible part of the map and which one is under the cursor.
-- The frames are Modules/GatheringMap.lua. Points are { x, y, itemId } with x, y as fractions of the zone
-- map (GatheringLogic.Points); pins are the same points in canvas pixels, y down. Points of different items
-- at one position form one spot (GM.Spots) with several possible items: itemId is the icon item, items
-- all possible ids (selected first), selected how many of them are switched on, multi true for several.
local _, ns = ...

local GM = {}
ns.GatheringMapLogic = GM

-- Smallest symbol edge in px; a symbol is never bigger than a place symbol of the same map.
GM.MIN_SIZE = 8
-- Edge of a spot symbol as a share of the place symbol of the same map and size setting.
GM.SIZE_SHARE = 0.75
-- Most pins one zone draws (the pool never grows beyond it). The data holds a few hundred per zone.
GM.MAX_PINS = 1500
-- Pins this share of the visible width and height beyond the visible part are drawn too, so a short
-- drag or key press needs no new plan.
GM.MARGIN = 0.25
-- Hit radius of a pin: half its edge plus this many px.
GM.HIT_PAD = 3
-- Edge of the grid cells the hit test sorts the pins into, in px at least.
GM.MIN_CELL = 8

-- Hook for own finds (a later step): a list of { x, y, itemId, own = true } of a zone, or nil. They
-- join the known points of the items that are switched on.
function GM.ExtraPoints()
  return nil
end

-- Size ------------------------------------------------------------------------------------------------

-- Edge of a spot symbol in px: derived from the place symbol (MapPins.PinSize with the symbol size
-- setting in percent), smaller than it, not below MIN_SIZE unless the place symbol itself is smaller.
-- canvasWidth is the width of the visible map, so the size does not grow with the magnification.
function GM.PinSize(canvasWidth, scale)
  local place = ns.MapPins.PinSize(canvasWidth, scale)
  return math.min(place, math.max(GM.MIN_SIZE, math.floor(place * GM.SIZE_SHARE + 0.5)))
end

-- unit: canvas units per screen px (default 1), for a canvas that is scaled by the client.
function GM.HitRadius(size, unit)
  return size / 2 + GM.HIT_PAD * (tonumber(unit) or 1)
end

local COLUMN = 100000

local function cellKey(cx, cy)
  return cx * COLUMN + cy
end

-- Points ------------------------------------------------------------------------------------------------

local cache = setmetatable({}, { __mode = "k" })
local spotCache = setmetatable({}, { __mode = "k" })

-- Decoded points of one item in one zone. Decoded once per data table, the list is shared: do not change it.
function GM.ItemPoints(data, mapId, itemId)
  if type(data) ~= "table" then
    return {}
  end
  local zones = cache[data]
  if not zones then
    zones = {}
    cache[data] = zones
  end
  local items = zones[mapId]
  if not items then
    items = {}
    zones[mapId] = items
  end
  local list = items[itemId]
  if not list then
    list = ns.GatheringLogic.Points(data, mapId, { [itemId] = true })
    items[itemId] = list
  end
  return list
end

-- Forgets the decoded points and spots (tests).
function GM.ResetCache()
  cache = setmetatable({}, { __mode = "k" })
  spotCache = setmetatable({}, { __mode = "k" })
end

local function sortedIds(set)
  local ids = {}
  for id, on in pairs(type(set) == "table" and set or {}) do
    if on == true and type(id) == "number" then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

-- Two points of different items at most this far apart (fraction of the map, euclidean, x and y alike) are one
-- spot. The data build merges the points of one item with the same distance.
GM.SPOT_DIST = 0.0015

local function zoneItemIds(data, mapId)
  local zone = type(data.zones) == "table" and data.zones[mapId]
  local ids = {}
  for id, chain in pairs(type(zone) == "table" and type(zone.items) == "table" and zone.items or {}) do
    if type(id) == "number" and type(chain) == "string" then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

-- All spots of a zone, independent of the selection: { { x, y, prof, ids = { sorted item ids }, itemId = ids[1],
-- items = ids, selected = 1, multi = false } }. Items of one profession are grouped through a grid with the
-- cell edge SPOT_DIST (only the 3 x 3 cells around a point are looked at); a point joins the first spot within
-- the distance that does not hold the item yet (close points of one item stay separate spots), so the position
-- of a spot is its first point and nothing chains. Computed once per data table
-- and zone, the list and its tables are shared: do not change them.
function GM.Spots(data, mapId)
  if type(data) ~= "table" then
    return {}
  end
  local zones = spotCache[data]
  if not zones then
    zones = {}
    spotCache[data] = zones
  end
  local list = zones[mapId]
  if list then
    return list
  end
  list = {}
  zones[mapId] = list
  local items = type(data.items) == "table" and data.items or {}
  local cell, limit = GM.SPOT_DIST, GM.SPOT_DIST * GM.SPOT_DIST
  local grids = {}
  for _, id in ipairs(zoneItemIds(data, mapId)) do
    local prof = type(items[id]) == "table" and items[id].prof or ""
    local grid = grids[prof]
    if not grid then
      grid = {}
      grids[prof] = grid
    end
    for _, p in ipairs(GM.ItemPoints(data, mapId, id)) do
      local cx, cy = math.floor(p.x / cell), math.floor(p.y / cell)
      local found
      for gx = cx - 1, cx + 1 do
        for gy = cy - 1, cy + 1 do
          for _, spot in ipairs(grid[cellKey(gx, gy)] or {}) do
            if
              not found
              and spot.ids[#spot.ids] ~= id
              and (spot.x - p.x) ^ 2 + (spot.y - p.y) ^ 2 <= limit
            then
              found = spot
            end
          end
        end
      end
      if found then
        found.ids[#found.ids + 1] = id
        found.multi = true
      else
        found = { x = p.x, y = p.y, prof = prof, ids = { id }, itemId = id, selected = 1, multi = false }
        found.items = found.ids
        list[#list + 1] = found
        local key = cellKey(cx, cy)
        grid[key] = grid[key] or {}
        table.insert(grid[key], found)
      end
    end
  end
  return list
end

-- The skill an item needs, 0 when unknown.
local function skillOf(data, id)
  local item = type(data.items) == "table" and data.items[id]
  return type(item) == "table" and tonumber(item.skill) or 0
end

-- The point a spot becomes for the items of set: items lists the possible ids with the selected ones first
-- (id order inside both parts), selected counts them, itemId (the icon) is the selected item with the highest
-- skill, the lowest id on a tie. A spot with one item is returned as it is.
local function spotFor(data, spot, set)
  local chosen, rest = {}, {}
  for _, id in ipairs(spot.ids) do
    table.insert(set[id] == true and chosen or rest, id)
  end
  if #chosen == 0 then
    return nil
  end
  if not spot.multi then
    return spot
  end
  local icon, best
  for _, id in ipairs(chosen) do
    local skill = skillOf(data, id)
    if not best or skill > best then
      icon, best = id, skill
    end
  end
  local all = {}
  for _, id in ipairs(chosen) do
    all[#all + 1] = id
  end
  for _, id in ipairs(rest) do
    all[#all + 1] = id
  end
  return { x = spot.x, y = spot.y, prof = spot.prof, itemId = icon, items = all, selected = #chosen, multi = true }
end

-- The points of a zone for the items of set ({ [itemId] = true }): the spots that hold at least one of them
-- in the order of GM.Spots (items in id order), then the own finds of GM.ExtraPoints for the same items. The
-- own finds stay single points and do not join spots. A new list, the point tables of single spots are shared.
function GM.Points(data, mapId, set)
  local out = {}
  if type(data) == "table" and #sortedIds(set) > 0 then
    for _, spot in ipairs(GM.Spots(data, mapId)) do
      out[#out + 1] = spotFor(data, spot, set)
    end
  end
  for _, p in ipairs(GM.ExtraPoints(mapId) or {}) do
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" and set and set[p.itemId] == true then
      out[#out + 1] = p
    end
  end
  return out
end

-- Marker ------------------------------------------------------------------------------------------------

-- Icon edge in screen px from which a spot with several items gets colored arcs on its rim; below it the
-- marker is the count alone (arcs of 2 px would be mush on a 12 px symbol).
GM.ARC_MIN_SIZE = 16
-- Most arcs drawn; further items only count in the number.
GM.MAX_ARCS = 4

-- Rim colors per item id (relative luminance at least 0.2, so each has 3:1 against the dark backing the arcs
-- sit on), other items take a color of the palette by id.
GM.ITEM_COLORS = {
  [2770] = { 0.85, 0.54, 0.29 }, -- Copper Ore
  [2771] = { 0.62, 0.74, 0.86 }, -- Tin Ore
  [2775] = { 0.75, 0.80, 0.88 }, -- Silver Ore
  [2772] = { 0.86, 0.35, 0.28 }, -- Iron Ore
  [2776] = { 1.00, 0.82, 0.10 }, -- Gold Ore
  [3858] = { 0.30, 0.80, 0.35 }, -- Mithril Ore
  [7911] = { 1.00, 1.00, 1.00 }, -- Truesilver Ore
  [10620] = { 0.25, 0.65, 1.00 }, -- Thorium Ore
  [12365] = { 0.70, 0.45, 0.90 }, -- Dense Stone
  [11370] = { 0.80, 0.40, 0.70 }, -- Dark Iron Ore
}
GM.PALETTE = {
  { 0.95, 0.60, 0.25 },
  { 0.35, 0.85, 0.80 },
  { 0.90, 0.45, 0.60 },
  { 0.60, 0.80, 0.30 },
  { 0.55, 0.60, 1.00 },
  { 0.95, 0.85, 0.45 },
}

function GM.ItemColor(itemId)
  local c = GM.ITEM_COLORS[itemId] or GM.PALETTE[(tonumber(itemId) or 0) % #GM.PALETTE + 1]
  return c[1], c[2], c[3]
end

-- Alpha of the arc of an item that is not selected.
GM.DIM_ARC_ALPHA = 0.35

-- Rim quadrants (1 top right, 2 bottom right, 3 bottom left, 4 top left) per arc, by the number of arcs.
local ARC_QUADS = {
  [2] = { { 1, 2 }, { 3, 4 } },
  [3] = { { 1, 2 }, { 3 }, { 4 } },
  [4] = { { 1 }, { 2 }, { 3 }, { 4 } },
}

-- Arcs for the items of a spot (selected first): { { id, quads, dim } } for the first MAX_ARCS items.
function GM.Segments(items, selected)
  local n = math.min(#items, GM.MAX_ARCS)
  local out = {}
  for i = 1, n do
    out[i] = { id = items[i], quads = ARC_QUADS[n][i], dim = i > (selected or 0) }
  end
  return out
end

-- Switch of the marker (setting gather.spotMarker, default on).
function GM.MarkerEnabled()
  return ns.Store.get("settings.gather.spotMarker") ~= false
end

-- What to draw on a spot of the given symbol edge (screen px): nil (one item or marker off) or
-- { count = possible items, segments = arcs, nil below ARC_MIN_SIZE }.
function GM.Marker(spot, px, enabled)
  if enabled == false or type(spot) ~= "table" or not spot.multi or type(spot.items) ~= "table" then
    return nil
  end
  local marker = { count = #spot.items }
  if px >= GM.ARC_MIN_SIZE then
    marker.segments = GM.Segments(spot.items, spot.selected)
  end
  return marker
end

-- Number of points and of items with points the set has in a zone, read from the chain lengths without
-- decoding. Items the data does not know do not count.
function GM.Summary(data, mapId, set)
  local zone = type(data) == "table" and type(data.zones) == "table" and data.zones[mapId]
  local items = type(data) == "table" and type(data.items) == "table" and data.items or {}
  local points, count = 0, 0
  if type(zone) ~= "table" or type(zone.items) ~= "table" then
    return 0, 0
  end
  for _, id in ipairs(sortedIds(set)) do
    local chain = zone.items[id]
    if items[id] and type(chain) == "string" then
      local n = math.floor(#chain / ns.GatherCodec.POINT_CHARS)
      if n > 0 then
        points, count = points + n, count + 1
      end
    end
  end
  return points, count
end

-- Plan ----------------------------------------------------------------------------------------------

-- The pins to draw: the points that lie in the visible part of the map plus a margin, in canvas px.
-- geo = { cw, ch (canvas size), l, t, w, h (visible part in canvas px, nil: the whole canvas) }.
-- Returns { pins, extent = { l, t, r, b } (what the plan covers), total (points in the extent before the
-- cap), truncated }. Order and the cap follow the order of the points.
function GM.Plan(points, geo, max)
  local cw, ch = tonumber(geo.cw) or 0, tonumber(geo.ch) or 0
  local wl, wt = tonumber(geo.l) or 0, tonumber(geo.t) or 0
  local ww, wh = tonumber(geo.w) or cw, tonumber(geo.h) or ch
  local mx, my = ww * GM.MARGIN, wh * GM.MARGIN
  local extent = { l = wl - mx, t = wt - my, r = wl + ww + mx, b = wt + wh + my }
  local cap = max or GM.MAX_PINS
  local pins, total = {}, 0
  for _, p in ipairs(points or {}) do
    local x, y = p.x * cw, p.y * ch
    if x >= extent.l and x <= extent.r and y >= extent.t and y <= extent.b then
      total = total + 1
      if total <= cap then
        pins[total] = {
          x = x,
          y = y,
          itemId = p.itemId,
          own = p.own,
          kind = p.kind,
          kinds = p.kinds,
          items = p.items,
          selected = p.selected,
          multi = p.multi,
        }
      end
    end
  end
  return { pins = pins, extent = extent, total = total, truncated = total > cap }
end

-- True when the visible part (l, t, w, h in canvas px) lies inside what a plan covered.
function GM.Covers(extent, l, t, w, h)
  return extent ~= nil and l >= extent.l and t >= extent.t and l + w <= extent.r and t + h <= extent.b
end

-- Hit test --------------------------------------------------------------------------------------------

-- Sorts the pins into a grid so a hit test only looks at the cells around the cursor.
function GM.Index(pins, radius)
  local cell = math.max(GM.MIN_CELL, 2 * (tonumber(radius) or 0))
  local index = { pins = pins, cell = cell, buckets = {} }
  for i, p in ipairs(pins) do
    local key = cellKey(math.floor(p.x / cell), math.floor(p.y / cell))
    local bucket = index.buckets[key]
    if not bucket then
      bucket = {}
      index.buckets[key] = bucket
    end
    bucket[#bucket + 1] = i
  end
  return index
end

-- The pin whose center is nearest to (x, y) within radius px; the one drawn last wins a tie. Returns the
-- pin and its number, or nil.
function GM.Hit(index, x, y, radius)
  if not (index and tonumber(x) and tonumber(y)) then
    return nil
  end
  local cell = index.cell
  local cx, cy = math.floor(x / cell), math.floor(y / cell)
  local span = math.ceil(radius / cell)
  local limit = radius * radius
  local best, bestAt, bestD
  for gx = cx - span, cx + span do
    for gy = cy - span, cy + span do
      for _, i in ipairs(index.buckets[cellKey(gx, gy)] or {}) do
        local p = index.pins[i]
        local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
        if d <= limit and (best == nil or d < bestD or (d == bestD and i > bestAt)) then
          best, bestAt, bestD = p, i, d
        end
      end
    end
  end
  return best, bestAt
end

-- The cursor as canvas px: (fx, fy) are fractions of the visible part of the map (0..1), the visible
-- part is l, t, w, h in canvas px (zoom and pan are in it). nil when the cursor is off the map.
function GM.CursorToCanvas(fx, fy, l, t, w, h)
  if not (tonumber(fx) and tonumber(fy) and fx >= 0 and fx <= 1 and fy >= 0 and fy <= 1) then
    return nil
  end
  return l + fx * w, t + fy * h
end
