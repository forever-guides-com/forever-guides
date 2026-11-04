-- Zone transition arrows without WoW API: where a zone borders its neighbours and which way an
-- arrow there points. Works on a zone view (MapWorld.ZoneView: the open zone and the outlines of
-- the zones around it in zone coordinates, 0..1 is the visible map). The outlines of neighbours
-- follow each other closely but do not match to the pixel, so a border is every stretch of the
-- open zone's outline that lies within a tolerance of the neighbour's outline.
-- That arrow sits in the middle of such a stretch, not at a road or pass, so it is only an estimate and
-- only drawn between zones that a walk link of the travel data joins. The real crossings (shipped,
-- recorded, set by hand, see ZoneCrossingLogic) replace the estimate of their zone pair; they reach
-- Arrows as opts.crossings[zone][neighbour] = { { x, y, state = , id = }, ... } in zone coordinates.
local _, ns = ...
local MP = ns.MapPoly

ns.AddLocale("enUS", {
  ["zb.levels"] = "Levels %d-%d",
  ["zb.hint"] = "Click: switch map",
  ["zb.hint.addon"] = "Click: open add-on map",
  ["zb.legend"] = "Zone transition",
  ["zb.legend.guess"] = "Zone transition, estimated",
  ["zb.failed"] = "The map could not be switched.",
  ["zb.set.world"] = "Show zone transitions in the world map",
  ["zb.set.addon"] = "Show zone transitions on the add-on map",
  ["zb.set.guess"] = "Show estimated zone transitions",
  ["zb.set.guessHint"] = "An estimated arrow sits in the middle of a shared border, not at a road, and only between zones that a walking path joins in the travel data. Dashed on the map. A real crossing replaces the estimates of its zone pair.",
  ["zb.state.estimated"] = "Estimated, no confirmed path",
  ["zb.state.recorded"] = "Recorded while walking",
  ["zb.state.user"] = "Set by hand",
  ["zb.state.shipped"] = "Checked",
})
ns.AddLocale("deDE", {
  ["zb.levels"] = "Stufen %d-%d",
  ["zb.hint"] = "Klicken: Karte wechseln",
  ["zb.hint.addon"] = "Klicken: Addon-Karte öffnen",
  ["zb.legend"] = "Zonenübergang",
  ["zb.legend.guess"] = "Zonenübergang, geschätzt",
  ["zb.failed"] = "Die Karte ließ sich nicht wechseln.",
  ["zb.set.world"] = "Zonenübergänge in der Weltkarte anzeigen",
  ["zb.set.addon"] = "Zonenübergänge auf der Addon-Karte anzeigen",
  ["zb.set.guess"] = "Geschätzte Zonenübergänge zeigen",
  ["zb.set.guessHint"] = "Ein geschätzter Pfeil sitzt in der Mitte einer gemeinsamen Grenze, nicht an einer Straße, und nur zwischen Zonen, die in den Reisedaten ein Laufweg verbindet. Auf der Karte gestrichelt. Ein echter Übergang ersetzt die geschätzten Pfeile seines Zonenpaars.",
  ["zb.state.estimated"] = "geschätzt, kein bestätigter Weg",
  ["zb.state.recorded"] = "aufgenommen",
  ["zb.state.user"] = "von Hand gesetzt",
  ["zb.state.shipped"] = "geprüft",
})

local ZBL = {}
ns.ZoneBorderLogic = ZBL

-- Shares of the continent width; capitals and cities sit in rough outlines inside their
-- surroundings and need more room.
ZBL.LAND_TOLERANCE = 0.002
ZBL.CITY_TOLERANCE = 0.015
-- Shortest border that gets an arrow of its own, as a share of the zone width, and how far an
-- arrow sits inside the zone so it is not cut off at the map edge. A stretch shorter than
-- TOUCH tolerances is two outlines meeting in a corner, not a border.
ZBL.MIN_LENGTH = 0.03
ZBL.TOUCH = 3
ZBL.INSET = 0.02
ZBL.PER_NEIGHBOR = 2
-- How far from a border (zone widths) a click still picks that neighbour.
ZBL.PICK_REACH = 0.08
-- Chains of one neighbour whose gap is smaller than this (zone widths) are one border and get one arrow.
ZBL.NEAR = 1 / 3

local memo = setmetatable({}, { __mode = "k" })

local function number(v, default)
  return type(v) == "number" and v == v and v > 0 and v < math.huge and v or default
end

-- Geometry -------------------------------------------------------------------------------

-- The part of t in 0..1 where the point A + t * (B - A) lies within r of the segment CD, as t0, t1
-- (the set is convex, the capsule around CD cut by a line). Union of the two end discs and the
-- band beside the segment; nil when the segment stays away.
local function nearInterval(ax, ay, bx, by, cx, cy, dx, dy, r)
  local ex, ey = bx - ax, by - ay
  local lo, hi = math.huge, -math.huge
  local function take(t0, t1)
    t0, t1 = math.max(t0, 0), math.min(t1, 1)
    if t0 <= t1 then
      lo, hi = math.min(lo, t0), math.max(hi, t1)
    end
  end
  local qa = ex * ex + ey * ey
  for _, corner in ipairs({ { cx, cy }, { dx, dy } }) do
    local fx, fy = ax - corner[1], ay - corner[2]
    local qb, qc = 2 * (fx * ex + fy * ey), fx * fx + fy * fy - r * r
    local disc = qb * qb - 4 * qa * qc
    if disc >= 0 then
      local root = math.sqrt(disc)
      take((-qb - root) / (2 * qa), (-qb + root) / (2 * qa))
    end
  end
  local len = math.sqrt((dx - cx) ^ 2 + (dy - cy) ^ 2)
  if len > 0 then
    local ux, uy = (dx - cx) / len, (dy - cy) / len
    local px, py = ax - cx, ay - cy
    -- Along the segment 0..len, across it -r..r; both are linear in t.
    local t0, t1, inside = 0, 1, true
    for _, c in ipairs({
      { px * ux + py * uy, ex * ux + ey * uy, 0, len },
      { py * ux - px * uy, ey * ux - ex * uy, -r, r },
    }) do
      local from, step, minV, maxV = c[1], c[2], c[3], c[4]
      if step == 0 then
        inside = inside and from >= minV and from <= maxV
      else
        local ta, tb = (minV - from) / step, (maxV - from) / step
        t0, t1 = math.max(t0, math.min(ta, tb)), math.min(t1, math.max(ta, tb))
      end
    end
    if inside then
      take(t0, t1)
    end
  end
  if lo <= hi then
    return lo, hi
  end
end

local function segmentDistance2(px, py, x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local t = math.max(0, math.min(1, ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)))
  return (px - x1 - t * dx) ^ 2 + (py - y1 - t * dy) ^ 2
end

-- The closed rings of a shape as lists of edges. Every edge knows its box, its length, its start
-- along the ring (s) and its outward normal in map pixels (y stretched by aspect, so the angle
-- looks right on a canvas that is not square). Edges of length 0 are dropped.
local function ringsOf(shape, aspect)
  local rings = {}
  for _, ring in ipairs(shape.rings) do
    local p, n = ring.p, ring.n
    local twice = 0
    for i = 1, n do
      local j = i % n + 1
      twice = twice + p[2 * i - 1] * p[2 * j] - p[2 * j - 1] * p[2 * i]
    end
    local side = twice >= 0 and 1 or -1
    local edges, s = {}, 0
    for i = 1, n do
      local j = i % n + 1
      local x1, y1, x2, y2 = p[2 * i - 1], p[2 * i], p[2 * j - 1], p[2 * j]
      local dx, dy = x2 - x1, y2 - y1
      local len = math.sqrt(dx * dx + dy * dy)
      if len > 0 then
        local px = math.sqrt(dx * dx + (dy * aspect) ^ 2)
        local tx, ty = dx / px, dy * aspect / px
        edges[#edges + 1] = {
          x1 = x1,
          y1 = y1,
          x2 = x2,
          y2 = y2,
          len = len,
          px = px,
          s = s,
          nx = side * ty,
          ny = -side * tx,
          minx = math.min(x1, x2),
          maxx = math.max(x1, x2),
          miny = math.min(y1, y2),
          maxy = math.max(y1, y2),
        }
        s = s + len
      end
    end
    if #edges > 0 then
      rings[#rings + 1] = { edges = edges, length = s }
    end
  end
  return rings
end

-- Stretches of a ring (start, end along the ring) that lie within tol of the other shape's
-- outline; gaps up to tol are bridged, also across the start of the ring.
local function stretches(ring, others, tol)
  local spans = {}
  for _, e in ipairs(ring.edges) do
    for _, other in ipairs(others) do
      for _, f in ipairs(other.edges) do
        if e.maxx + tol >= f.minx and f.maxx + tol >= e.minx and e.maxy + tol >= f.miny and f.maxy + tol >= e.miny then
          local t0, t1 = nearInterval(e.x1, e.y1, e.x2, e.y2, f.x1, f.y1, f.x2, f.y2, tol)
          if t0 then
            spans[#spans + 1] = { e.s + t0 * e.len, e.s + t1 * e.len }
          end
        end
      end
    end
  end
  table.sort(spans, function(a, b)
    if a[1] ~= b[1] then
      return a[1] < b[1]
    end
    return a[2] < b[2]
  end)
  local chains = {}
  for _, span in ipairs(spans) do
    local last = chains[#chains]
    if last and span[1] <= last[2] + tol then
      last[2] = math.max(last[2], span[2])
    else
      chains[#chains + 1] = { span[1], span[2] }
    end
  end
  if #chains > 1 and chains[1][1] + ring.length - chains[#chains][2] <= tol then
    chains[#chains][2] = chains[1][2] + ring.length
    table.remove(chains, 1)
  end
  return chains
end

-- The visible pieces of a chain (the part inside 0..1), each with its px length and normal.
local function pieces(ring, from, to, aspect)
  local out = {}
  for lap = 0, to > ring.length and 1 or 0 do
    local shift = lap * ring.length
    for _, e in ipairs(ring.edges) do
      local a, b = math.max(from, e.s + shift), math.min(to, e.s + e.len + shift)
      if b > a then
        local t0, t1 = (a - e.s - shift) / e.len, (b - e.s - shift) / e.len
        local dx, dy = e.x2 - e.x1, e.y2 - e.y1
        local x1, y1, x2, y2 = MP.ClipSegment(e.x1 + t0 * dx, e.y1 + t0 * dy, e.x1 + t1 * dx, e.y1 + t1 * dy)
        if x1 then
          local len = math.sqrt((x2 - x1) ^ 2 + ((y2 - y1) * aspect) ^ 2)
          if len > 0 then
            out[#out + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, len = len, nx = e.nx, ny = e.ny }
          end
        end
      end
    end
  end
  return out
end

-- Direction of an outward normal in map pixels (y down) as an angle counterclockwise from east, as
-- seen on the map, in (-pi, pi].
local function angleOf(nx, ny)
  local angle = math.atan2(-ny, nx)
  return angle < -math.pi + 1e-9 and math.pi or angle
end

-- Arrow place and direction of a chain: the middle of its visible length moved inset into the
-- zone, pointing along the length-weighted outward normal. nil when nothing of it is visible.
local function summarize(list, aspect, inset)
  local total, sx, sy = 0, 0, 0
  for _, piece in ipairs(list) do
    total, sx, sy = total + piece.len, sx + piece.nx * piece.len, sy + piece.ny * piece.len
  end
  if total <= 0 then
    return nil
  end
  local walked, x, y, nx, ny = 0, nil, nil, nil, nil
  for _, piece in ipairs(list) do
    if walked + piece.len >= total / 2 then
      local f = (total / 2 - walked) / piece.len
      x, y = piece.x1 + f * (piece.x2 - piece.x1), piece.y1 + f * (piece.y2 - piece.y1)
      nx, ny = piece.nx, piece.ny
      break
    end
    walked = walked + piece.len
  end
  local norm = math.sqrt(sx * sx + sy * sy)
  if norm > 1e-6 then
    nx, ny = sx / norm, sy / norm
  end
  x, y = x - nx * inset, y - ny * inset / aspect
  if x < 0 or x > 1 or y < 0 or y > 1 then
    return nil
  end
  return { len = total, x = x, y = y, angle = angleOf(nx, ny) }
end

local function byPlace(a, b)
  if a.ring ~= b.ring then
    return a.ring < b.ring
  end
  return a.at < b.at
end

local function within(ax, ay, bx, by, aspect)
  local dx, dy = ax - bx, (ay - by) * aspect
  return dx * dx + dy * dy < ZBL.NEAR * ZBL.NEAR
end

-- True when a visible piece of one chain ends nearer than ZBL.NEAR to a piece end of the other.
local function nearChains(a, b, aspect)
  for _, p in ipairs(a.pieces) do
    for _, q in ipairs(b.pieces) do
      if
        within(p.x1, p.y1, q.x1, q.y1, aspect)
        or within(p.x1, p.y1, q.x2, q.y2, aspect)
        or within(p.x2, p.y2, q.x1, q.y1, aspect)
        or within(p.x2, p.y2, q.x2, q.y2, aspect)
      then
        return true
      end
    end
  end
  return false
end

-- Chains that lie near each other, as lists (a chain that bridges two groups joins them).
local function groupNear(chains, aspect)
  local groups = {}
  for _, chain in ipairs(chains) do
    local joined
    for i = #groups, 1, -1 do
      local group = groups[i]
      local close = false
      for _, member in ipairs(group) do
        close = close or nearChains(member, chain, aspect)
      end
      if close then
        if joined then
          for _, member in ipairs(group) do
            joined[#joined + 1] = member
          end
          table.remove(groups, i)
        else
          group[#group + 1] = chain
          joined = group
        end
      end
    end
    if not joined then
      groups[#groups + 1] = { chain }
    end
  end
  return groups
end

-- One arrow for a group of near chains: the middle of their summed visible length. The longest member
-- stands in when that spot lies outside the map.
local function mergeChains(group, o)
  table.sort(group, byPlace)
  local list = {}
  for _, chain in ipairs(group) do
    for _, piece in ipairs(chain.pieces) do
      list[#list + 1] = piece
    end
  end
  local arrow = summarize(list, o.aspect, o.inset)
  if arrow then
    arrow.ring, arrow.at, arrow.pieces = group[1].ring, group[1].at, list
    return arrow
  end
  local longest = group[1]
  for _, chain in ipairs(group) do
    longest = chain.len > longest.len and chain or longest
  end
  return longest
end

-- The arrows of one neighbour from its border: chains that lie near each other count as one border, of
-- these borders the longest ones (at most PER_NEIGHBOR) that reach minLength, or the single longest chain
-- when none does.
local function borderArrows(rings, others, tol, o)
  local chains = {}
  for r, ring in ipairs(rings) do
    for _, span in ipairs(stretches(ring, others, tol)) do
      local list = pieces(ring, span[1], span[2], o.aspect)
      local arrow = summarize(list, o.aspect, o.inset)
      if arrow and arrow.len > ZBL.TOUCH * tol then
        arrow.ring, arrow.at, arrow.pieces = r, span[1], list
        chains[#chains + 1] = arrow
      end
    end
  end
  table.sort(chains, function(a, b)
    if a.len ~= b.len then
      return a.len > b.len
    end
    if a.ring ~= b.ring then
      return a.ring < b.ring
    end
    return a.at < b.at
  end)
  local long = {}
  for _, chain in ipairs(chains) do
    if chain.len >= o.minLength then
      long[#long + 1] = chain
    end
  end
  if #long == 0 and chains[1] then
    return { chains[1] }
  end
  local borders = {}
  for _, group in ipairs(groupNear(long, o.aspect)) do
    borders[#borders + 1] = #group == 1 and group[1] or mergeChains(group, o)
  end
  table.sort(borders, function(a, b)
    if a.len ~= b.len then
      return a.len > b.len
    end
    return byPlace(a, b)
  end)
  local keep = {}
  for i = 1, math.min(#borders, ZBL.PER_NEIGHBOR) do
    keep[i] = borders[i]
  end
  table.sort(keep, byPlace)
  return keep
end

-- An arrow at a known crossing: it points out of the zone at the nearest edge of its outline. The point is
-- { x, y, state = , id = }; a plain { x, y } counts as shipped.
local function crossingArrow(rings, point)
  local x, y = point[1], point[2]
  if not (type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
    return nil
  end
  local best, bestD
  for _, ring in ipairs(rings) do
    for _, e in ipairs(ring.edges) do
      local d = segmentDistance2(x, y, e.x1, e.y1, e.x2, e.y2)
      if not bestD or d < bestD then
        best, bestD = e, d
      end
    end
  end
  if best then
    return { x = x, y = y, angle = angleOf(best.nx, best.ny), state = point.state or "shipped", id = point.id }
  end
end

local function tolerance(zoneOf, zone, slug, land, city)
  local info = zoneOf[slug]
  return ((info and info.k == "capital") or (zoneOf[zone] or {}).k == "capital") and city or land
end

-- Arrows -------------------------------------------------------------------------------------

-- The arrows of a zone view: { slug, map, x, y, angle, state, id, n, name, lmin, lmax } with x, y in zone
-- coordinates (0..1), angle counterclockwise from east in radians as seen on the map, state "estimated"
-- (computed from the border, n its place among the estimates of that neighbour) or the state of the known
-- crossing (id), name the { de, en } table of the zone. zoneOf[slug] is the zone record of the travel data (name, levels,
-- kind). Neighbours without a map of their own get none. Ordered like zv.neighbors, then along
-- the outline.
-- opts: aspect (canvas height / width, 1), unit (continent width in zone widths, zv.unit or 1),
-- tolerance and cityTolerance (shares of unit), minLength, inset (zone widths), crossings (see above),
-- estimate(slug) (false: no estimated arrows toward that neighbour, default all).
function ZBL.Arrows(zv, zoneOf, opts)
  opts = opts or {}
  local around = zv and zv.around
  local own = around and zv.zone and MP.Shape(around, zv.zone)
  if not own then
    return {}
  end
  zoneOf = zoneOf or {}
  local o = {
    aspect = number(opts.aspect, 1),
    minLength = number(opts.minLength, ZBL.MIN_LENGTH),
    inset = number(opts.inset, ZBL.INSET),
  }
  local unit = number(opts.unit, number(zv.unit, 1))
  local land = number(opts.tolerance, ZBL.LAND_TOLERANCE) * unit
  local city = number(opts.cityTolerance, ZBL.CITY_TOLERANCE) * unit
  local rings = ringsOf(own, o.aspect)
  local fixed = opts.crossings and opts.crossings[zv.zone] or {}
  local out = {}
  for _, slug in ipairs(zv.neighbors or {}) do
    local shape = around.maps and around.maps[slug] and MP.Shape(around, slug)
    if shape then
      local info = zoneOf[slug]
      local list = {}
      if fixed[slug] then
        for _, point in ipairs(fixed[slug]) do
          list[#list + 1] = crossingArrow(rings, point)
        end
      elseif not opts.estimate or opts.estimate(slug) then
        list = borderArrows(rings, ringsOf(shape, o.aspect), tolerance(zoneOf, zv.zone, slug, land, city), o)
      end
      for i, arrow in ipairs(list) do
        out[#out + 1] = {
          slug = slug,
          map = around.maps[slug],
          x = arrow.x,
          y = arrow.y,
          angle = arrow.angle,
          state = arrow.state or "estimated",
          id = arrow.id,
          n = arrow.state == nil and i or nil,
          name = info and info.n,
          lmin = info and info.lmin,
          lmax = info and info.lmax,
        }
      end
    end
  end
  return out
end

-- The neighbour whose border lies nearest to a point of the zone view (zone coordinates) and how far (zone widths
-- on the canvas); nil when the zone has no outline or no neighbour has a border.
function ZBL.NearestBorder(zv, zoneOf, aspect, x, y)
  local around = zv and zv.around
  local own = around and zv.zone and MP.Shape(around, zv.zone)
  if not own then
    return nil
  end
  zoneOf = zoneOf or {}
  aspect = number(aspect, 1)
  local o = { aspect = aspect, minLength = ZBL.MIN_LENGTH, inset = ZBL.INSET }
  local unit = number(zv.unit, 1)
  local land, city = ZBL.LAND_TOLERANCE * unit, ZBL.CITY_TOLERANCE * unit
  local rings = ringsOf(own, aspect)
  local best, bestSlug
  for _, slug in ipairs(zv.neighbors or {}) do
    local shape = around.maps and around.maps[slug] and MP.Shape(around, slug)
    if shape then
      local tol = tolerance(zoneOf, zv.zone, slug, land, city)
      for _, arrow in ipairs(borderArrows(rings, ringsOf(shape, aspect), tol, o)) do
        for _, piece in ipairs(arrow.pieces) do
          local d = segmentDistance2(x, y * aspect, piece.x1, piece.y1 * aspect, piece.x2, piece.y2 * aspect)
          if not best or d < best then
            best, bestSlug = d, slug
          end
        end
      end
    end
  end
  return bestSlug, best and math.sqrt(best)
end

-- The neighbour a click on the zone map at (x, y) means for a crossing: the zone whose outline holds the
-- point, else the one whose border is nearest within PICK_REACH. nil when no neighbour qualifies.
function ZBL.PickNeighbor(zv, zoneOf, aspect, x, y)
  local maps = zv and zv.around and zv.around.maps or {}
  local slug = ns.MapWorld.NeighborAt(zv, x, y)
  if slug and maps[slug] then
    return slug
  end
  local near, d = ZBL.NearestBorder(zv, zoneOf, aspect, x, y)
  if near and d <= ZBL.PICK_REACH then
    return near
  end
end

-- Arrows of a zone view: the known crossings of its zone pairs and, where a pair has none and a walk link
-- joins it, the estimates (not while the setting mapZoneArrowsGuess is off), without the ones the player
-- deleted. Computed once per view, canvas shape, setting and state of the crossings.
function ZBL.ForView(zv, zoneOf, aspect)
  aspect = number(aspect, 1)
  local Z = ns.ZoneCrossingLogic
  local settings = ns.db and ns.db.settings
  local guess = not (settings and settings.mapZoneArrowsGuess == false)
  local hit = memo[zv]
  if not (hit and hit.rev == Z.revision and hit.guess == guess and math.abs(hit.aspect - aspect) < 1e-3) then
    local walk = guess and Z.WalkPairs(ns.Data.Travel) or {}
    local list = ZBL.Arrows(zv, zoneOf, {
      aspect = aspect,
      crossings = { [zv.zone] = Z.ForZone(zv) },
      estimate = function(slug)
        return walk[Z.PairKey(zv.zone, slug)] == true
      end,
    })
    hit = { aspect = aspect, rev = Z.revision, guess = guess, list = Z.Label(zv.zone, list) }
    memo[zv] = hit
  end
  return hit.list
end

-- The strokes of the arrow symbol for a direction (radians, counterclockwise from east): shaft and
-- two head lines as { x1, y1, x2, y2 } in px from the center of a plate of the given size (x right, y up),
-- and the stroke thickness. Everything stays inside the plate. dashed: the shaft is DASHES short pieces
-- (the first DASHES entries) instead of one stroke; the two head lines always come last.
local REACH, HEAD, WING = 0.32, 0.26, math.rad(38)
ZBL.DASHES = 3

function ZBL.ArrowLines(angle, size, dashed)
  local dx, dy = math.cos(angle), math.sin(angle)
  local tipX, tipY = dx * REACH * size, dy * REACH * size
  local lines = {}
  if dashed then
    -- Dash, gap, dash, gap, dash: 2 * DASHES - 1 equal parts along the shaft.
    local parts = 2 * ZBL.DASHES - 1
    for i = 0, ZBL.DASHES - 1 do
      local from, to = 2 * (2 * i / parts) - 1, 2 * ((2 * i + 1) / parts) - 1
      lines[#lines + 1] = { tipX * from, tipY * from, tipX * to, tipY * to }
    end
  else
    lines[1] = { -tipX, -tipY, tipX, tipY }
  end
  for _, turn in ipairs({ WING, -WING }) do
    local c, s = math.cos(turn), math.sin(turn)
    lines[#lines + 1] = {
      tipX,
      tipY,
      tipX - (dx * c - dy * s) * HEAD * size,
      tipY - (dx * s + dy * c) * HEAD * size,
    }
  end
  return lines, math.max(1.5, size * 0.1)
end

-- Tooltip of an arrow: the zone name as title, its level range, the state of the crossing and the click hint
-- (locale key hintKey, default "zb.hint").
function ZBL.TooltipLines(arrow, L, T, hintKey)
  local pick = T or ns.T
  local title = arrow.name and pick(arrow.name) or arrow.slug
  local lines = {}
  if arrow.lmin then
    lines[#lines + 1] = L["zb.levels"]:format(arrow.lmin, arrow.lmax or arrow.lmin)
  end
  if arrow.state then
    lines[#lines + 1] = L["zb.state." .. arrow.state]
  end
  lines[#lines + 1] = L[hintKey or "zb.hint"]
  return title, lines
end
