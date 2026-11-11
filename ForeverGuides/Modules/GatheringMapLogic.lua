-- Ore and herb spots on the Forever map, pure side (no frames): which points a zone shows, how big the
-- symbols are, which of them lie in the visible part of the map and which one is under the cursor.
-- The frames are Modules/GatheringMap.lua. Points are { x, y, itemId } with x, y as fractions of the zone
-- map (GatheringLogic.Points); pins are the same points in canvas pixels, y down.
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

-- Points ------------------------------------------------------------------------------------------------

local cache = setmetatable({}, { __mode = "k" })

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

-- Forgets the decoded points (tests).
function GM.ResetCache()
  cache = setmetatable({}, { __mode = "k" })
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

-- The points of a zone for the items of set ({ [itemId] = true }): the items in id order, then the own
-- finds of GM.ExtraPoints for the same items. A new list, the point tables are shared.
function GM.Points(data, mapId, set)
  local out = {}
  for _, id in ipairs(sortedIds(set)) do
    for _, p in ipairs(GM.ItemPoints(data, mapId, id)) do
      out[#out + 1] = p
    end
  end
  for _, p in ipairs(GM.ExtraPoints(mapId) or {}) do
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" and set and set[p.itemId] == true then
      out[#out + 1] = p
    end
  end
  return out
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
        pins[total] = { x = x, y = y, itemId = p.itemId, own = p.own, kind = p.kind, kinds = p.kinds }
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

local COLUMN = 100000

local function cellKey(cx, cy)
  return cx * COLUMN + cy
end

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
