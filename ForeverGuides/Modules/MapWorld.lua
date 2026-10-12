-- World-map support for the map page. The travel data has no UiMapIDs, so the
-- world map showing both continents is discovered at runtime, places are
-- resolved to real zone rectangles by name, and regions that are not part of
-- the world art (the Forever island) get a schematic panel. Everything outside
-- the "WoW discovery" section is pure Lua without WoW API.
local _, ns = ...

local MW = {}
ns.MapWorld = MW

local ISLAND = "forever"
local WORLD_FALLBACK_ID = 947
local DEFAULT_ASPECT = 0.6
local MIN_FIT_ZONES = 3
local ZONE_MARGIN = 0.1
local BOX_INSET = 0.05
local MIN_SPAN = 60
local PANEL = { w = 0.34, h = 0.36 }
local PANEL_MARGIN = 0.02
local PANEL_PAD = 0.04
local TITLE_FRACTION = 0.2
local LABEL_FRACTION = 0.16
local CELL_PAD = 0.12

-- Pure logic ---------------------------------------------------------------------

-- Case-insensitive, trimmed, typographic apostrophes folded; nil for empty input.
function MW.NormalizeName(text)
  if type(text) ~= "string" then
    return nil
  end
  text = text:gsub("\226\128\153", "'"):lower():gsub("^%s+", ""):gsub("%s+$", "")
  return text ~= "" and text or nil
end

-- Validated rectangle from GetMapRectOnMap's (left, right, top, bottom).
function MW.Rect(left, right, top, bottom)
  for _, v in ipairs({ type(left), type(right), type(top), type(bottom) }) do
    if v ~= "number" then
      return nil
    end
  end
  if not (right > left and bottom > top) or right - left > 2 or bottom - top > 2 then
    return nil
  end
  return { left = left, right = right, top = top, bottom = bottom }
end

-- A point given as fractions of a rectangle, as fractions of the rectangle's map.
function MW.Place(rect, fx, fy)
  return rect.left + fx * (rect.right - rect.left), rect.top + fy * (rect.bottom - rect.top)
end

-- inner is given in the fractions of outer; the result is in outer's map fractions.
function MW.Compose(inner, outer)
  local x1, y1 = MW.Place(outer, inner.left, inner.top)
  local x2, y2 = MW.Place(outer, inner.right, inner.bottom)
  return { left = x1, right = x2, top = y1, bottom = y2 }
end

-- Least squares for to = offset + scale * from over samples { from, to }.
-- nil unless enough distinct samples define a rising line.
function MW.Fit(samples)
  local n = #samples
  if n < MIN_FIT_ZONES then
    return nil
  end
  local sx, sy, sxx, sxy = 0, 0, 0, 0
  for _, s in ipairs(samples) do
    sx, sy = sx + s[1], sy + s[2]
    sxx, sxy = sxx + s[1] * s[1], sxy + s[1] * s[2]
  end
  local denom = n * sxx - sx * sx
  if denom <= 1e-9 then
    return nil
  end
  local scale = (n * sxy - sx * sy) / denom
  if scale <= 0 then
    return nil
  end
  return { scale = scale, offset = (sy - scale * sx) / n }
end

-- Maps the range [minV, maxV] onto [lo, hi]; nil for an empty range.
function MW.BoxFit(minV, maxV, lo, hi)
  if maxV - minV < 1e-6 then
    return nil
  end
  local scale = (hi - lo) / (maxV - minV)
  return { scale = scale, offset = lo - scale * minV }
end

-- Matches zone entries ({ s, n = { de, en } }) to map infos ({ mapID, name })
-- by name; a zone's own UiMapID (um) wins over the name. rankOf(info) -> number
-- picks the better of equally named maps (lower wins). Returns resolved[slug] = info
-- and a list of unresolved zones.
function MW.Resolve(zones, infos, rankOf)
  local byName, byId = {}, {}
  for _, info in ipairs(infos) do
    if type(info) == "table" and type(info.mapID) == "number" then
      byId[info.mapID] = info
    end
    local key = type(info) == "table" and type(info.mapID) == "number" and MW.NormalizeName(info.name)
    if key then
      local rank = rankOf and rankOf(info) or 1
      local cur = byName[key]
      if not cur or rank < cur.rank or (rank == cur.rank and info.mapID < cur.info.mapID) then
        byName[key] = { info = info, rank = rank }
      end
    end
  end
  local resolved, missing = {}, {}
  for _, z in ipairs(zones) do
    local best
    for _, lang in ipairs({ "de", "en" }) do
      local hit = z.n and byName[MW.NormalizeName(z.n[lang]) or false]
      if hit and (not best or hit.rank < best.rank) then
        best = hit
      end
    end
    local byUm = z.um and byId[z.um]
    if byUm then
      resolved[z.s] = byUm
    elseif best then
      resolved[z.s] = best.info
    else
      missing[#missing + 1] = z
    end
  end
  return resolved, missing
end

local function clamp(v, lo, hi)
  return math.min(hi, math.max(lo, v))
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Picks the panel corner covering the fewest points (fractions of the canvas).
-- size = { w, h } as canvas fractions; ties keep the corner order bottom right,
-- bottom left, top right, top left.
function MW.PickPanel(points, size)
  local m = PANEL_MARGIN
  local candidates = {
    { l = 1 - size.w - m, t = 1 - size.h - m },
    { l = m, t = 1 - size.h - m },
    { l = 1 - size.w - m, t = m },
    { l = m, t = m },
  }
  local best, bestCount
  for _, c in ipairs(candidates) do
    local count = 0
    for _, p in ipairs(points) do
      if p.x >= c.l and p.x <= c.l + size.w and p.y >= c.t and p.y <= c.t + size.h then
        count = count + 1
      end
    end
    if not best or count < bestCount then
      best, bestCount = c, count
    end
  end
  return { l = best.l, t = best.t, w = size.w, h = size.h }, bestCount
end

-- Lays island items out in one cell per zone inside rect. Item fields ux/uy are
-- canvas units divided by the canvas width, so x and y share one scale. Sets
-- item.px/py (canvas fractions) and returns the cell list.
local function layoutIsland(items, rect, aspect, canvasW)
  local groups, order = {}, {}
  for _, it in ipairs(items) do
    local g = groups[it.zone.s]
    if not g then
      g = { zone = it.zone, items = {}, sum = 0 }
      groups[it.zone.s] = g
      order[#order + 1] = g
    end
    g.items[#g.items + 1] = it
    g.sum = g.sum + it.ux
  end
  table.sort(order, function(a, b)
    local ma, mb = a.sum / #a.items, b.sum / #b.items
    if ma ~= mb then
      return ma < mb
    end
    return a.zone.s < b.zone.s
  end)
  local hu = rect.h * aspect
  local padX = rect.w * PANEL_PAD
  local areaL, areaW = rect.l + padX, rect.w - 2 * padX
  local areaT = rect.t * aspect + hu * TITLE_FRACTION
  local areaH = hu * (1 - TITLE_FRACTION - LABEL_FRACTION)
  local cellW = areaW / #order
  local cells = {}
  for i, g in ipairs(order) do
    local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
    for _, it in ipairs(g.items) do
      minx, maxx = math.min(minx, it.ux), math.max(maxx, it.ux)
      miny, maxy = math.min(miny, it.uy), math.max(maxy, it.uy)
    end
    local spanX, spanY = math.max(maxx - minx, MIN_SPAN / canvasW), math.max(maxy - miny, MIN_SPAN / canvasW)
    local scale = math.min(cellW * (1 - 2 * CELL_PAD) / spanX, areaH * (1 - 2 * CELL_PAD) / spanY)
    local cx, cy = areaL + (i - 0.5) * cellW, areaT + areaH / 2
    for _, it in ipairs(g.items) do
      it.px = cx + (it.ux - (minx + maxx) / 2) * scale
      it.py = (cy + (it.uy - (miny + maxy) / 2) * scale) / aspect
    end
    cells[i] = {
      zone = g.zone.s,
      l = areaL + (i - 1) * cellW,
      w = cellW,
      labelT = (areaT + areaH) / aspect,
      labelH = hu * LABEL_FRACTION / aspect,
    }
  end
  return cells
end

-- Canvas-to-world fits per continent. Zone centroids against zone rectangles
-- give the fit; without enough zones the continent rectangle against the
-- continent's canvas extent is the fallback.
local function buildFits(items, rects, contRects)
  local zones, boxes = {}, {}
  for _, it in ipairs(items) do
    local cont = it.zone and it.zone.c
    if cont and it.fx then
      local b = boxes[cont]
      if not b then
        b = { minx = it.fx, maxx = it.fx, miny = it.fy, maxy = it.fy }
        boxes[cont] = b
      end
      b.minx, b.maxx = math.min(b.minx, it.fx), math.max(b.maxx, it.fx)
      b.miny, b.maxy = math.min(b.miny, it.fy), math.max(b.maxy, it.fy)
      local rect = rects[it.zone.s]
      if rect then
        zones[cont] = zones[cont] or {}
        local g = zones[cont][it.zone.s]
        if not g then
          g = { rect = rect, sx = 0, sy = 0, n = 0 }
          zones[cont][it.zone.s] = g
        end
        g.sx, g.sy, g.n = g.sx + it.fx, g.sy + it.fy, g.n + 1
      end
    end
  end
  local fits = {}
  for cont, b in pairs(boxes) do
    local xs, ys = {}, {}
    for _, g in pairs(zones[cont] or {}) do
      local cx, cy = MW.Place(g.rect, 0.5, 0.5)
      xs[#xs + 1] = { g.sx / g.n, cx }
      ys[#ys + 1] = { g.sy / g.n, cy }
    end
    local fx, fy = MW.Fit(xs), MW.Fit(ys)
    local cr = contRects and contRects[cont]
    if cr and not (fx and fy) then
      local w, h = cr.right - cr.left, cr.bottom - cr.top
      fx = MW.BoxFit(b.minx, b.maxx, cr.left + w * BOX_INSET, cr.right - w * BOX_INSET)
      fy = MW.BoxFit(b.miny, b.maxy, cr.top + h * BOX_INSET, cr.bottom - h * BOX_INSET)
    end
    if fx and fy then
      fits[cont] = { x = fx, y = fy }
    end
  end
  return fits
end

local function applyFit(fit, it)
  return fit.x.offset + fit.x.scale * it.fx, fit.y.offset + fit.y.scale * it.fy
end

-- Places every node of data on the world map (fractions 0..1 of the map).
-- rects: zone slug -> world rectangle of the resolved zones.
-- o: { panel = { [continentSlug] = true }, continentRects, aspect }.
-- o.maps (zone slug -> UiMapID) is passed through to layout.maps.
-- Returns { pos = { [nodeSlug] = { x, y, kind } }, stats, panel, aspect, zones, maps } where
-- zones = { [zoneSlug] = rectangle } and polySrc = { [zoneSlug] = { poly, canvas, rect } } for PointToZone and
-- kind is "real" (inside its resolved zone), "estimate" (derived from the canvas
-- layout) or "island" (schematic panel). Nodes without canvas data and without
-- a resolved zone get no position.
function MW.Layout(data, rects, o)
  o = o or {}
  rects = rects or {}
  local TL = ns.TravelLogic
  local aspect = (type(o.aspect) == "number" and o.aspect > 0) and o.aspect or DEFAULT_ASPECT
  local canvas = data.canvas
  local zoneOf = {}
  for _, z in ipairs(data.zones or {}) do
    zoneOf[z.s] = z
  end
  local layout = {
    pos = {},
    stats = { real = 0, estimate = 0, island = 0, total = 0 },
    aspect = aspect,
    zones = {},
    polySrc = {},
    maps = {},
  }
  -- Zone rectangles for PointToZone; zones on the schematic panel have none (see IslandView).
  for _, z in ipairs(data.zones or {}) do
    if rects[z.s] and not (o.panel and o.panel[z.c]) then
      layout.zones[z.s] = rects[z.s]
      if z.poly then
        layout.polySrc[z.s] = { poly = z.poly, canvas = z.pc == "canvas", rect = rects[z.s] }
      end
    end
    if o.maps and o.maps[z.s] then
      layout.maps[z.s] = o.maps[z.s]
    end
  end
  local items, islandItems = {}, {}
  for _, n in ipairs(data.nodes) do
    layout.stats.total = layout.stats.total + 1
    local fx, fy = TL.CanvasFraction(data, n)
    local it = { node = n, zone = zoneOf[n.z], fx = fx, fy = fy }
    if canvas and n.x and n.y then
      it.ux, it.uy = n.x / canvas.w, n.y / canvas.w
    end
    local cont = it.zone and it.zone.c
    if it.ux and cont and o.panel and o.panel[cont] then
      islandItems[#islandItems + 1] = it
    else
      items[#items + 1] = it
    end
  end

  local fits = buildFits(items, rects, o.continentRects)
  local points = {}
  local function put(it, x, y, kind)
    layout.pos[it.node.s] = { x = x, y = y, kind = kind }
    layout.stats[kind] = layout.stats[kind] + 1
    points[#points + 1] = { x = x, y = y }
  end
  for _, it in ipairs(items) do
    local rect = it.zone and rects[it.zone.s]
    local fit = it.zone and fits[it.zone.c]
    if rect then
      local x, y = MW.Place(rect, 0.5, 0.5)
      if fit and it.fx then
        local fx, fy = applyFit(fit, it)
        local mx, my = (rect.right - rect.left) * ZONE_MARGIN, (rect.bottom - rect.top) * ZONE_MARGIN
        x, y = clamp(fx, rect.left + mx, rect.right - mx), clamp(fy, rect.top + my, rect.bottom - my)
      end
      put(it, x, y, "real")
    elseif it.fx then
      if fit then
        local fx, fy = applyFit(fit, it)
        put(it, clamp(fx, 0, 1), clamp(fy, 0, 1), "estimate")
      else
        put(it, it.fx, it.fy, "estimate")
      end
    end
  end

  if #islandItems > 0 then
    local rect = MW.PickPanel(points, PANEL)
    local cells = layoutIsland(islandItems, rect, aspect, canvas.w)
    for _, it in ipairs(islandItems) do
      layout.pos[it.node.s] = { x = it.px, y = it.py, kind = "island" }
      layout.stats.island = layout.stats.island + 1
    end
    layout.panel = {
      l = rect.l,
      t = rect.t,
      w = rect.w,
      h = rect.h,
      titleH = rect.h * TITLE_FRACTION,
      cells = cells,
    }
  end
  return layout
end

-- Island view -----------------------------------------------------------------------

-- The schematic island panel stretched over a whole canvas (the "new regions" tab).
-- Returns { panel, pos, aspect } in the same shapes as a layout, with the panel at 0..1 and
-- only the island nodes placed; aspect = canvas height / width that keeps the panel
-- undistorted. nil when the layout has no panel.
function MW.IslandView(layout)
  local p = layout and layout.panel
  if not p then
    return nil
  end
  local pos, cells, zones = {}, {}, {}
  for slug, at in pairs(layout.pos) do
    if at.kind == "island" then
      pos[slug] = { x = (at.x - p.l) / p.w, y = (at.y - p.t) / p.h, kind = "island" }
    end
  end
  for i, c in ipairs(p.cells) do
    cells[i] =
      { zone = c.zone, l = (c.l - p.l) / p.w, w = c.w / p.w, labelT = (c.labelT - p.t) / p.h, labelH = c.labelH / p.h }
    -- A cell reaches from below the title to its label.
    zones[c.zone] =
      { left = cells[i].l, right = cells[i].l + cells[i].w, top = p.titleH / p.h, bottom = cells[i].labelT }
  end
  return {
    panel = { l = 0, t = 0, w = 1, h = 1, titleH = p.titleH / p.h, cells = cells },
    pos = pos,
    aspect = p.h * layout.aspect / p.w,
    zones = zones,
    maps = layout.maps,
  }
end

-- Map points <-> zone positions -----------------------------------------------------------

local function inside(r, nx, ny)
  return nx >= r.left and nx <= r.right and ny >= r.top and ny <= r.bottom
end

-- The zone under a point of a view (a layout or an IslandView result), the point given as
-- fractions of the map. Returns zone slug, x, y with x, y the position inside the zone's
-- rectangle (0..1), or nil when no zone is there. Zones with an outline (MapPoly) are hit by
-- the outline, the smallest first; rectangles only count for zones without one. Overlapping
-- rectangles: the smallest wins, then the smaller slug, so the answer never depends on table order.
function MW.PointToZone(view, nx, ny)
  local zones = view and view.zones
  if not (zones and finite(nx) and finite(ny)) then
    return nil
  end
  local best, bestArea
  local idx = ns.MapPoly.Index(view)
  if idx then
    for _, shape in ipairs(idx.order) do
      if ns.MapPoly.Contains(shape, nx, ny) then
        best = shape.slug
        break
      end
    end
  end
  if not best then
    for slug, r in pairs(zones) do
      if not (idx and idx.has[slug]) and inside(r, nx, ny) then
        local area = (r.right - r.left) * (r.bottom - r.top)
        if not best or area < bestArea or (area == bestArea and slug < best) then
          best, bestArea = slug, area
        end
      end
    end
  end
  if not best then
    return nil
  end
  local r = zones[best]
  return best, clamp((nx - r.left) / (r.right - r.left), 0, 1), clamp((ny - r.top) / (r.bottom - r.top), 0, 1)
end

-- Inverse of PointToZone: the point of a view for a position inside a zone (fractions 0..1),
-- or nil when the view does not show the zone.
function MW.ZoneToPoint(view, zoneId, x, y)
  local r = view and view.zones and view.zones[zoneId]
  if not (r and finite(x) and finite(y)) then
    return nil
  end
  return MW.Place(r, x, y)
end

-- One zone shown over the whole map, built from the view it is opened from (a layout or an
-- island view). Same shape as a view: the zone's rectangle is 0..1, so PointToZone and
-- ZoneToPoint give the zone position directly, and pos holds the places of the zone relative
-- to that rectangle. nil when the parent does not show the zone or the zone has no game map.
function MW.ZoneView(parent, data, slug)
  local r = parent and parent.zones and parent.zones[slug]
  local mapId = parent and parent.maps and parent.maps[slug]
  if not (r and mapId and r.right > r.left and r.bottom > r.top) then
    return nil
  end
  local pos = {}
  for _, n in ipairs(data and data.nodes or {}) do
    local p = n.z == slug and parent.pos and parent.pos[n.s]
    if p and (p.kind == "real" or p.kind == "island") then
      pos[n.s] = {
        x = clamp((p.x - r.left) / (r.right - r.left), 0, 1),
        y = clamp((p.y - r.top) / (r.bottom - r.top), 0, 1),
        kind = "zone",
      }
    end
  end
  return {
    zone = slug,
    mapId = mapId,
    zones = { [slug] = { left = 0, right = 1, top = 0, bottom = 1 } },
    maps = { [slug] = mapId },
    pos = pos,
    aspect = parent.aspect,
  }
end

-- WoW discovery --------------------------------------------------------------------
-- Every C_Map call goes through pcall; whatever is missing makes Discover
-- return world.ok = false and the page keeps its flat canvas.

local function call(name, ...)
  local fn = C_Map and C_Map[name]
  if type(fn) ~= "function" then
    return nil
  end
  local r = { pcall(fn, ...) }
  if not r[1] then
    return nil
  end
  return unpack(r, 2, 6)
end

local function uiType(name)
  return Enum and Enum.UIMapType and Enum.UIMapType[name]
end

local function mapInfo(id)
  local info = call("GetMapInfo", id)
  return type(info) == "table" and info or nil
end

-- Child maps of id (direct children unless all is set), optionally of one type.
local function children(id, mapType, all)
  local list = call("GetMapChildrenInfo", id, mapType, all)
  return type(list) == "table" and list or {}
end

local function descendants(id)
  local list = children(id, nil, true)
  if #list == 0 and uiType("Zone") then
    list = children(id, uiType("Zone"), true)
  end
  return list
end

local function rankOf(info)
  if info.mapType == uiType("Zone") then
    return 1
  end
  if info.mapType == uiType("Dungeon") or info.mapType == uiType("Micro") then
    return 3
  end
  return 2
end

-- The player's map and its parents: { id, name, mapType, parent }.
local function mapChain()
  local chain, seen = {}, {}
  local id = call("GetBestMapForUnit", "player") or call("GetFallbackWorldMapID")
  while type(id) == "number" and id ~= 0 and not seen[id] and #chain < 12 do
    seen[id] = true
    local info = mapInfo(id)
    if not info then
      break
    end
    chain[#chain + 1] = { id = id, name = info.name, mapType = info.mapType, parent = info.parentMapID }
    id = info.parentMapID
  end
  return chain
end

local function findContinent(entry, kids)
  local wanted = {}
  for _, lang in ipairs({ "de", "en" }) do
    local key = entry.n and MW.NormalizeName(entry.n[lang])
    if key then
      wanted[key] = true
    end
  end
  for _, info in ipairs(kids) do
    local key = type(info) == "table" and MW.NormalizeName(info.name)
    if key and wanted[key] then
      return info
    end
  end
end

-- The Forever island may carry its own name on the map.
local function findIsland(entry, kids)
  local hit = findContinent(entry, kids)
  if hit then
    return hit
  end
  for _, info in ipairs(kids) do
    local key = type(info) == "table" and MW.NormalizeName(info.name)
    if key and (key:find("skyborn", 1, true) or key:find("forever", 1, true)) then
      return info
    end
  end
end

-- Highest non-cosmic map on the player's chain (then the client's fallback and
-- the classic Azeroth id) whose children include every continent but the island.
local function pickWorld(data, d)
  local ids, seen = {}, {}
  local function add(id)
    if type(id) == "number" and id ~= 0 and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  for i = #d.chain, 1, -1 do
    if d.chain[i].mapType ~= uiType("Cosmic") then
      add(d.chain[i].id)
    end
  end
  add(call("GetFallbackWorldMapID"))
  add(WORLD_FALLBACK_ID)
  for _, id in ipairs(ids) do
    local info = mapInfo(id)
    local kids = children(id)
    local found, missing, required = {}, {}, 0
    for _, entry in ipairs(data.continents) do
      local hit = entry.s == ISLAND and findIsland(entry, kids) or findContinent(entry, kids)
      if entry.s ~= ISLAND then
        required = required + 1
      end
      if hit then
        found[entry.s] = hit
      elseif entry.s ~= ISLAND then
        missing[#missing + 1] = entry.s
      end
    end
    d.tried[#d.tried + 1] = { id = id, name = info and info.name, kids = #kids, missing = missing }
    if info and required > 0 and #missing == 0 then
      return id, info, kids, found
    end
  end
end

-- Corner fallback: project the zone's corners through world coordinates.
local function cornerRect(zoneId, worldId)
  local vec = _G.CreateVector2D
  if type(vec) ~= "function" then
    return nil
  end
  local xs, ys = {}, {}
  for _, corner in ipairs({ { 0, 0 }, { 1, 1 } }) do
    local cont, wp = call("GetWorldPosFromMapPos", zoneId, vec(corner[1], corner[2]))
    if not (cont and wp) then
      return nil
    end
    local _, mp = call("GetMapPosFromWorldPos", cont, wp, worldId)
    if type(mp) ~= "table" then
      return nil
    end
    local x, y = mp.x, mp.y
    if (not x) and mp.GetXY then
      x, y = mp:GetXY()
    end
    if type(x) ~= "number" or type(y) ~= "number" then
      return nil
    end
    xs[#xs + 1], ys[#ys + 1] = x, y
  end
  return MW.Rect(math.min(xs[1], xs[2]), math.max(xs[1], xs[2]), math.min(ys[1], ys[2]), math.max(ys[1], ys[2]))
end

-- Zone rectangle on the world map: direct, composed via the continent, or corners.
local function zoneRect(zoneId, contId, worldId, contRect)
  local rect = MW.Rect(call("GetMapRectOnMap", zoneId, worldId))
  if rect then
    return rect, "direct"
  end
  local inCont = MW.Rect(call("GetMapRectOnMap", zoneId, contId))
  if inCont and contRect then
    return MW.Compose(inCont, contRect), "composed"
  end
  rect = cornerRect(zoneId, worldId)
  if rect then
    return rect, "corners"
  end
end

-- First art layer of a map: tile grid geometry plus the tile file ids.
function MW.LoadArt(mapId)
  local layers = call("GetMapArtLayers", mapId)
  local layer = type(layers) == "table" and layers[1]
  local textures = call("GetMapArtLayerTextures", mapId, 1)
  if not (type(layer) == "table" and type(textures) == "table" and #textures > 0) then
    return nil
  end
  for _, key in ipairs({ "layerWidth", "layerHeight", "tileWidth", "tileHeight" }) do
    if type(layer[key]) ~= "number" or layer[key] <= 0 then
      return nil
    end
  end
  return { layer = layer, textures = textures }
end

-- Explored areas of a zone map: the client's list of overlay pieces the player has uncovered
-- (C_MapExplorationInfo). The art layer alone is the whole map; fog only exists as "everything
-- outside these pieces". nil when the client has no such call, {} when nothing is explored yet.
function MW.LoadExplored(mapId)
  local fn = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
  if type(fn) ~= "function" then
    return nil
  end
  local ok, list = pcall(fn, mapId)
  if not ok then
    return nil
  end
  return type(list) == "table" and list or {}
end

-- Cuts the explored overlays into draw commands in art layer pixels (the same space as the layer
-- tiles, see ns.MapRevealLogic.Cut): { id, x, y, w, h, u, v }. Entries the client reports in a
-- shape that cannot be drawn are left out.
function MW.ExploredTiles(list)
  local R = ns.MapRevealLogic
  local out = {}
  for _, info in ipairs(type(list) == "table" and list or {}) do
    local tw, th = type(info) == "table" and info.textureWidth, type(info) == "table" and info.textureHeight
    local ids = type(info) == "table" and info.fileDataIDs
    if type(tw) == "number" and type(th) == "number" and tw > 0 and th > 0 and type(ids) == "table" then
      -- The client lists the files row by row.
      local cols = R.Grid(tw, th)
      local tiles = {}
      for i, id in ipairs(ids) do
        tiles[i] = { math.floor((i - 1) / cols), (i - 1) % cols, id }
      end
      for _, piece in ipairs(R.Cut(tw, th, tonumber(info.offsetX) or 0, tonumber(info.offsetY) or 0, tiles)) do
        out[#out + 1] = piece
      end
    end
  end
  return out
end

-- The art id of a map (C_Map.GetMapArtID), the key of the overlay data; nil when the client has
-- no such call.
function MW.ArtId(mapId)
  local id = call("GetMapArtID", mapId)
  return type(id) == "number" and id or nil
end

local function zoneLabel(z)
  local en, de = z.n and z.n.en, z.n and z.n.de
  if en and de and en ~= de then
    return en .. " / " .. de
  end
  return en or de or tostring(z.s)
end

-- Cache of a successful discovery; failures are retried on the next call.
local cache

function MW.Reset()
  cache = nil
end

-- Returns world = { ok, mapID, name, art, aspect, rects, maps (zone slug -> UiMapID), contRects, panel, diag }.
-- diag always carries what was seen for bug reports.
function MW.Discover(data)
  if cache then
    return cache
  end
  local d =
    { tried = {}, chain = {}, continents = {}, unresolved = {}, methods = { direct = 0, composed = 0, corners = 0 } }
  local world = { ok = false, rects = {}, maps = {}, contRects = {}, panel = {}, diag = d }
  if not (type(data) == "table" and data.continents and C_Map and type(C_Map.GetMapInfo) == "function") then
    d.reason = "C_Map or travel data unavailable"
    return world
  end
  d.chain = mapChain()
  local id, info, kids, found = pickWorld(data, d)
  if not id then
    d.reason = "no map with both continents as children"
    d.topChildren = d.chain[#d.chain] and children(d.chain[#d.chain].id) or {}
    return world
  end
  world.mapID, world.name, world.mapType, d.worldChildren = id, info.name, info.mapType, kids
  local art = MW.LoadArt(id)
  if not art then
    d.reason = "world map has no usable art layers"
    return world
  end
  world.art = art
  world.aspect = clamp(art.layer.layerHeight / art.layer.layerWidth, 0.4, 1)

  local zonesOf = {}
  for _, z in ipairs(data.zones or {}) do
    zonesOf[z.c] = zonesOf[z.c] or {}
    table.insert(zonesOf[z.c], z)
  end
  for _, entry in ipairs(data.continents) do
    local cont = found[entry.s]
    local row = { slug = entry.s, zones = #(zonesOf[entry.s] or {}), resolved = 0 }
    d.continents[#d.continents + 1] = row
    if cont then
      row.mapID, row.name = cont.mapID, cont.name
      local contRect = MW.Rect(call("GetMapRectOnMap", cont.mapID, id))
      row.hasRect = contRect ~= nil
      world.contRects[entry.s] = contRect
      local resolved, missing = MW.Resolve(zonesOf[entry.s] or {}, descendants(cont.mapID), rankOf)
      for _, z in ipairs(missing) do
        d.unresolved[#d.unresolved + 1] = zoneLabel(z) .. " (no map name match)"
      end
      for _, z in ipairs(zonesOf[entry.s] or {}) do
        local zinfo = resolved[z.s]
        if zinfo then
          world.maps[z.s] = zinfo.mapID
          local rect, how = zoneRect(zinfo.mapID, cont.mapID, id, contRect)
          if rect then
            world.rects[z.s] = rect
            d.methods[how] = d.methods[how] + 1
            row.resolved = row.resolved + 1
          else
            d.unresolved[#d.unresolved + 1] = zoneLabel(z) .. " (map " .. zinfo.mapID .. ", no rectangle)"
          end
        end
      end
    end
    if not cont or (entry.s == ISLAND and row.resolved == 0) then
      world.panel[entry.s] = true
    end
  end
  world.ok = true
  cache = world
  return world
end

-- Layout for a discovered world, nil when the world is unusable.
function MW.LayoutWorld(data, world)
  if not (world and world.ok) then
    return nil
  end
  return MW.Layout(
    data,
    world.rects,
    { panel = world.panel, continentRects = world.contRects, aspect = world.aspect, maps = world.maps }
  )
end
