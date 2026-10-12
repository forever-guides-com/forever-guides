-- Waypoint core logic without frames or saved state: the data model, parsing of every
-- coordinate input, list handling, distance and direction maths, text export and import.
-- WoW API access goes through WL.env so tests can swap it.
--
--   waypoint = { id, map (uiMapID), x, y (0..1), title, note, color (Theme color name),
--                source ("user" | "map" | "note" | "share"), created, arrivedAt?,
--                pinned }
--   pinned waypoints survive "clear" and are never removed on arrival.
local _, ns = ...
local U = ns.U

local WL = {}
ns.WaypointLogic = WL

WL.MAX = 100
WL.DUPLICATE_DISTANCE = 0.0005
WL.MAX_TITLE = 40
WL.MAX_NOTE = 200
WL.MAX_LINES = 300
WL.RADIUS_MIN, WL.RADIUS_MAX, WL.RADIUS_DEFAULT = 5, 40, 15
-- Running speed in yards per second for the walking time estimate.
WL.WALK_SPEED = 7
WL.PALETTE = { "accent2", "actionHi", "success", "warning", "danger", "info", "accent", "textSecondary" }
WL.DEFAULT_COLOR = "accent2"
WL.SOURCES = { user = true, map = true, note = true, share = true }

local TAU = math.pi * 2
local atan2 = math.atan2 or math.atan

-- Cleaning --------------------------------------------------------------------------

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end
WL.finite = finite

-- Secret values (restricted clients) must not be compared or calculated with.
function WL.readable(v)
  if not finite(v) then
    return false
  end
  local guard = rawget(_G, "canaccessvalue")
  if type(guard) == "function" then
    local ok, can = pcall(guard, v)
    return ok and can ~= false
  end
  return true
end

local function cutChars(text, max)
  local count, i = 0, 1
  while i <= #text do
    local c = text:byte(i)
    count = count + 1
    if count > max then
      return U.trim(text:sub(1, i - 1))
    end
    i = i + (c >= 240 and 4 or c >= 224 and 3 or c >= 192 and 2 or 1)
  end
  return text
end

-- Control characters and pipes would break chat and UI escape sequences.
local function cleanText(text, max)
  if type(text) ~= "string" then
    return ""
  end
  text = U.trim((text:gsub("[%c|]", " "):gsub("%s+", " ")))
  return cutChars(text, max)
end

function WL.cleanTitle(text)
  return cleanText(text, WL.MAX_TITLE)
end

function WL.cleanNote(text)
  return cleanText(text, WL.MAX_NOTE)
end

function WL.cleanColor(name)
  for _, color in ipairs(WL.PALETTE) do
    if color == name then
      return name
    end
  end
  return WL.DEFAULT_COLOR
end

function WL.clampRadius(v)
  v = tonumber(v)
  if not finite(v) then
    return WL.RADIUS_DEFAULT
  end
  return math.floor(U.clamp(v, WL.RADIUS_MIN, WL.RADIUS_MAX) + 0.5)
end

-- Coordinates keep four decimals of the fraction, which is two decimals of the percent.
local function round4(v)
  return math.floor(v * 10000 + 0.5) / 10000
end

-- Percent text without trailing zeros: 45.2, 63, 12.25.
function WL.fmtPercent(fraction)
  local s = string.format("%.2f", fraction * 100)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

function WL.coordText(x, y)
  return WL.fmtPercent(x) .. ", " .. WL.fmtPercent(y)
end

-- A validated waypoint from raw fields (a parse result, an API call, SavedVariables),
-- or nil when map or position are missing or implausible. The id is set by WL.add.
function WL.build(raw, opts)
  opts = opts or {}
  if type(raw) ~= "table" or not finite(raw.map) or raw.map <= 0 or raw.map ~= math.floor(raw.map) then
    return nil
  end
  if not (finite(raw.x) and finite(raw.y)) or raw.x < 0 or raw.x > 1 or raw.y < 0 or raw.y > 1 then
    return nil
  end
  local wp = {
    id = type(raw.id) == "string" and raw.id ~= "" and raw.id or nil,
    map = raw.map,
    x = round4(raw.x),
    y = round4(raw.y),
    note = WL.cleanNote(raw.note),
    color = WL.cleanColor(raw.color),
    source = WL.SOURCES[raw.source] and raw.source or opts.source or "user",
    created = finite(raw.created) and raw.created or opts.now or 0,
    arrivedAt = finite(raw.arrivedAt) and raw.arrivedAt or nil,
    pinned = raw.pinned == true,
  }
  wp.title = WL.cleanTitle(raw.title)
  if wp.title == "" then
    wp.title = WL.coordText(wp.x, wp.y)
  end
  return wp
end

-- Parsing -----------------------------------------------------------------------------

local UMLAUTS = { ["\132"] = "\164", ["\150"] = "\182", ["\156"] = "\188" }

-- Comparison key of a zone name: lower case (umlauts too), single spaces.
function WL.fold(name)
  name = tostring(name or ""):gsub("\195([\132\150\156])", function(c)
    return "\195" .. UMLAUTS[c]
  end)
  return U.trim((name:lower():gsub("%s+", " ")))
end

-- index = list of { id, name, rank? }. Exact name first, then the start of a name, then a
-- part of it (three letters or more). Among several hits the lowest rank wins when it is
-- unique (a zone over its dungeon maps). Returns the list of candidates.
function WL.matchZones(index, name)
  local key = WL.fold(name)
  if key == "" or type(index) ~= "table" then
    return {}
  end
  local stages = { {}, {}, {} }
  local seen = {}
  for _, entry in ipairs(index) do
    local folded = WL.fold(entry.name)
    local stage = folded == key and 1
      or folded:sub(1, #key) == key and 2
      or (#key >= 3 and folded:find(key, 1, true)) and 3
    if stage and not seen[entry.id] then
      seen[entry.id] = true
      stages[stage][#stages[stage] + 1] = entry
    end
  end
  for _, hits in ipairs(stages) do
    if #hits > 0 then
      local best
      for _, hit in ipairs(hits) do
        best = math.min(best or hit.rank or 2, hit.rank or 2)
      end
      local ranked = {}
      for _, hit in ipairs(hits) do
        if (hit.rank or 2) == best then
          ranked[#ranked + 1] = hit
        end
      end
      table.sort(ranked, function(a, b)
        if a.name ~= b.name then
          return a.name < b.name
        end
        return a.id < b.id
      end)
      return ranked
    end
  end
  return {}
end

-- One number at position i: "45", "45.2" or "45,2", optionally followed by a percent sign.
-- Returns value, token, hasPercentSign, next position.
local function readNumber(s, i)
  local a, b = s:find("^%d+[.,]%d+", i)
  if not a then
    a, b = s:find("^%d+", i)
  end
  if not a then
    return nil
  end
  local token = s:sub(a, b)
  local sign = false
  if s:sub(b + 1, b + 1) == "%" then
    sign, b = true, b + 1
  end
  return tonumber((token:gsub(",", "."))), token, sign, b + 1
end

-- Two numbers separated by space, comma or semicolon at position i. A lone "45,63" is a
-- pair too (there is no second number to take the comma as a decimal sign).
local function readPair(s, i)
  local x, token, signX, nextPos = readNumber(s, i)
  if not x then
    return nil
  end
  local _, sepEnd = s:find("^[%s,;.]+", nextPos)
  if sepEnd then
    local y, _, signY, stop = readNumber(s, sepEnd + 1)
    if y then
      return x, y, signX or signY, stop
    end
  end
  local left, right = token:match("^(%d+),(%d+)$")
  if left then
    return tonumber(left), tonumber(right), signX, nextPos
  end
  return nil
end

-- The first position that starts a word and holds a coordinate pair.
local function findPair(s)
  for i = 1, #s do
    if s:find("^%d", i) and (i == 1 or s:find("^%s", i - 1)) then
      local x, y, sign, stop = readPair(s, i)
      if x then
        return i, x, y, sign, stop
      end
    end
  end
end

-- Percent (0-100) or fraction (0-1): one value above 1 or a percent sign makes the whole
-- pair percent. Returns x, y as fractions, or nil.
local function toFractions(x, y, sign)
  local percent = sign or x > 1 or y > 1
  if percent then
    if x > 100 or y > 100 then
      return nil
    end
    x, y = x / 100, y / 100
  end
  if x == 0 and y == 0 then
    return nil
  end
  return x, y
end

-- Text without a leading "/way" or "/tway", and whether there was one.
local function stripWay(s)
  local rest = s:match("^/[tT]?[wW][aA][yY](.*)$")
  if rest and (rest == "" or rest:find("^%s")) then
    return U.trim(rest), true
  end
  return s, false
end

local function stripLink(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h.-|h", "")
  return U.trim(s)
end

-- Reads one waypoint from text. Returns a spec { map, x, y, title, source? } or nil, code,
-- detail. Codes: empty, format, range, noMap, unknownZone, ambiguous (detail = candidates),
-- link, unknownMap.
-- ctx.map = the player's map, ctx.zones = index list or function returning it,
-- ctx.mapExists(id) = optional check for "#id" input.
-- Accepted: "45.2 63.1", "45,2 63,1", "45 63 Title", "#1234 45.2 63.1 Title",
-- "Zone name 45.2, 63.1 Title", "/way #1234 45.2 63.1 Title", "|Hworldmap:map:x:y|h[..]|h".
function WL.parse(text, ctx)
  ctx = ctx or {}
  if type(text) ~= "string" or #text > 400 then
    return nil, type(text) == "string" and "format" or "empty"
  end
  local s = U.trim(text)
  local linkMap, linkX, linkY = s:match("|Hworldmap:(%d+):(%d+):(%d+)|h")
  if linkMap then
    local x, y = tonumber(linkX) / 10000, tonumber(linkY) / 10000
    if x > 1 or y > 1 or tonumber(linkMap) <= 0 then
      return nil, "range"
    end
    return { map = tonumber(linkMap), x = x, y = y, title = stripLink(s), source = "map" }
  end
  if s:find("worldmap:", 1, true) then
    return nil, "link"
  end
  s = stripWay(s)
  if s == "" then
    return nil, "empty"
  end
  local mapId = s:match("^#(%d+)%f[%s]")
  if mapId then
    s = U.trim(s:sub(#mapId + 2))
  end
  local start, x, y, sign, stop = findPair(s)
  if not start then
    return nil, "format"
  end
  local zone = U.trim(s:sub(1, start - 1))
  if mapId and zone ~= "" then
    return nil, "format"
  end
  local fx, fy = toFractions(x, y, sign)
  if not fx then
    return nil, "range"
  end
  local title = U.trim((U.trim(s:sub(stop)):gsub("^[%-,:;]+%s*", "")))
  local map
  if mapId then
    map = tonumber(mapId)
    if map <= 0 or (ctx.mapExists and not ctx.mapExists(map)) then
      return nil, "unknownMap"
    end
  elseif zone ~= "" then
    local index = type(ctx.zones) == "function" and ctx.zones() or ctx.zones
    local hits = WL.matchZones(index, zone)
    if #hits == 0 then
      return nil, "unknownZone", zone
    elseif #hits > 1 then
      return nil, "ambiguous", hits
    end
    map = hits[1].id
  else
    map = ctx.map
    if not map then
      return nil, "noMap"
    end
  end
  return { map = map, x = fx, y = fy, title = title }
end

-- Export and import ---------------------------------------------------------------------

-- "/way #map x y title", coordinates in percent: the format of the route window export.
function WL.formatLine(wp)
  return string.format("/way #%d %s %s %s", wp.map, WL.fmtPercent(wp.x), WL.fmtPercent(wp.y), wp.title)
end

function WL.exportText(list)
  local lines = {}
  for _, wp in ipairs(list) do
    lines[#lines + 1] = WL.formatLine(wp)
  end
  return table.concat(lines, "\n")
end

-- Reads a block of text, one waypoint per line. When the text has /way lines only those
-- count (the route window export also holds a numbered summary). Returns
-- { specs = {...}, errors = { { line, code, detail, text } } }.
function WL.importText(text, ctx)
  local lines, ways = {}, {}
  for raw in tostring(text or ""):gmatch("[^\r\n]+") do
    local line = U.trim(raw)
    if line ~= "" and #lines < WL.MAX_LINES then
      lines[#lines + 1] = line
      if select(2, stripWay(line)) then
        ways[#ways + 1] = line
      end
    end
  end
  local source = #ways > 0 and ways or lines
  local result = { specs = {}, errors = {} }
  for i, line in ipairs(source) do
    local spec, code, detail = WL.parse(line, ctx)
    if spec then
      result.specs[#result.specs + 1] = spec
    else
      result.errors[#result.errors + 1] = { line = i, code = code, detail = detail, text = line }
    end
  end
  return result
end

-- List handling ------------------------------------------------------------------------------

function WL.indexOf(list, id)
  for i, wp in ipairs(list) do
    if wp.id == id then
      return i
    end
  end
end

function WL.find(list, id)
  local i = WL.indexOf(list, id)
  return i and list[i] or nil
end

function WL.nextId(list)
  local top = 0
  for _, wp in ipairs(list) do
    local n = tonumber(tostring(wp.id):match("^w(%d+)$"))
    if n and n > top then
      top = n
    end
  end
  return "w" .. (top + 1)
end

function WL.findDuplicate(list, map, x, y)
  for _, wp in ipairs(list) do
    if
      wp.map == map
      and math.abs(wp.x - x) <= WL.DUPLICATE_DISTANCE + 1e-9
      and math.abs(wp.y - y) <= WL.DUPLICATE_DISTANCE + 1e-9
    then
      return wp
    end
  end
end

-- Appends a waypoint. Returns wp, "added" | "duplicate" (the existing one) or nil,
-- "invalid" | "full". opts = { now, source }.
function WL.add(list, spec, opts)
  local wp = WL.build(spec, opts)
  if not wp then
    return nil, "invalid"
  end
  local dup = WL.findDuplicate(list, wp.map, wp.x, wp.y)
  if dup then
    return dup, "duplicate"
  end
  if #list >= WL.MAX then
    return nil, "full"
  end
  wp.id = WL.nextId(list)
  list[#list + 1] = wp
  return wp, "added"
end

function WL.remove(list, id)
  local i = WL.indexOf(list, id)
  if i then
    return table.remove(list, i), i
  end
end

-- Removes everything except pinned waypoints (all of them with force). Returns the count.
function WL.clear(list, force)
  local removed = 0
  for i = #list, 1, -1 do
    if force or not list[i].pinned then
      table.remove(list, i)
      removed = removed + 1
    end
  end
  return removed
end

function WL.rename(list, id, title)
  local wp = WL.find(list, id)
  if wp then
    wp.title = WL.cleanTitle(title)
    if wp.title == "" then
      wp.title = WL.coordText(wp.x, wp.y)
    end
  end
  return wp
end

function WL.setNote(list, id, note)
  local wp = WL.find(list, id)
  if wp then
    wp.note = WL.cleanNote(note)
  end
  return wp
end

function WL.setPinned(list, id, pinned)
  local wp = WL.find(list, id)
  if wp then
    wp.pinned = pinned == true
  end
  return wp
end

function WL.setColor(list, id, color)
  local wp = WL.find(list, id)
  if wp then
    wp.color = WL.cleanColor(color)
  end
  return wp
end

-- Moves a waypoint to a new position (map pages dragging a marker). Returns wp or nil
-- when the position is invalid.
function WL.move(list, id, map, x, y)
  local wp = WL.find(list, id)
  local moved = wp and WL.build({ map = map, x = x, y = y })
  if not moved then
    return nil
  end
  wp.map, wp.x, wp.y = moved.map, moved.x, moved.y
  wp.arrivedAt = nil
  return wp
end

-- The next (delta 1) or previous (delta -1) waypoint after id, wrapping around.
function WL.cycle(list, id, delta)
  local n = #list
  if n == 0 then
    return nil
  end
  local i = WL.indexOf(list, id)
  if not i then
    return list[delta >= 0 and 1 or n]
  end
  return list[(i - 1 + delta) % n + 1]
end

-- After an arrival: the next waypoint in list order that was not reached yet.
function WL.nextAfterArrival(list, id)
  local i = WL.indexOf(list, id) or 0
  for step = 1, #list do
    local wp = list[(i - 1 + step) % #list + 1]
    if wp.id ~= id and not wp.arrivedAt then
      return wp
    end
  end
end

-- The waypoint closest to the player: wp, yards. Waypoints without a computable distance
-- (other continent, no map data) are skipped.
function WL.nearest(list, playerMap, px, py)
  local best, bestDistance
  for _, wp in ipairs(list) do
    local d = WL.distanceYards(playerMap, px, py, wp.map, wp.x, wp.y)
    if d and (not bestDistance or d < bestDistance) then
      best, bestDistance = wp, d
    end
  end
  return best, bestDistance
end

-- A sorted copy. mode: "created" (default), "title", "distance" (needs distanceOf(wp) ->
-- yards or nil, unknown distances come last). Equal keys keep the list order.
function WL.sort(list, mode, distanceOf)
  local items = {}
  for i, wp in ipairs(list) do
    local key
    if mode == "title" then
      key = WL.fold(wp.title)
    elseif mode == "distance" then
      key = distanceOf and distanceOf(wp) or math.huge
    else
      key = wp.created or 0
    end
    items[i] = { wp = wp, key = key, index = i }
  end
  table.sort(items, function(a, b)
    if a.key ~= b.key then
      return a.key < b.key
    end
    return a.index < b.index
  end)
  local out = {}
  for i, item in ipairs(items) do
    out[i] = item.wp
  end
  return out
end

-- Distance and direction -----------------------------------------------------------------------

local function defaultWorldPos(map, x, y)
  local make = rawget(_G, "CreateVector2D")
  if not (C_Map and C_Map.GetWorldPosFromMapPos and make) then
    return nil
  end
  local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, map, make(x, y))
  if not (ok and continent ~= nil and type(pos) == "table") then
    return nil
  end
  local wx, wy = pos.x, pos.y
  if wx == nil and type(pos.GetXY) == "function" then
    wx, wy = pos:GetXY()
  end
  if WL.readable(wx) and WL.readable(wy) then
    return continent, wx, wy
  end
end

local function defaultMapSize(map)
  if not (C_Map and C_Map.GetMapWorldSize) then
    return nil
  end
  local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
  if ok and WL.readable(w) and WL.readable(h) and w > 0 and h > 0 then
    return w, h
  end
end

-- env.worldPos(map, x, y) -> continent, worldX, worldY (yards), env.mapSize(map) -> width,
-- height in yards. Both return nil when the client cannot tell.
WL.env = { worldPos = defaultWorldPos, mapSize = defaultMapSize }

local function hypot(a, b)
  return math.sqrt(a * a + b * b)
end

local function numbers(...)
  for i = 1, select("#", ...) do
    if not finite((select(i, ...))) then
      return false
    end
  end
  return true
end

-- Yards between two map positions, or nil when it cannot be told (different continents or
-- instances, no map data).
function WL.distanceYards(fromMap, fx, fy, toMap, tx, ty)
  if not (fromMap and toMap and numbers(fx, fy, tx, ty)) then
    return nil
  end
  local env = WL.env
  local c1, ax, ay = env.worldPos(fromMap, fx, fy)
  local c2, bx, by = env.worldPos(toMap, tx, ty)
  if c1 ~= nil and c2 ~= nil then
    if c1 == c2 and numbers(ax, ay, bx, by) then
      return hypot(ax - bx, ay - by)
    end
    return nil
  end
  if fromMap == toMap then
    local w, h = env.mapSize(fromMap)
    if w then
      return hypot((fx - tx) * w, (fy - ty) * h)
    end
  end
  return nil
end

-- The target as a step on the from-map in yards (east, south), or nil. Maps run north up,
-- so the step needs no knowledge of the game's own world axes: the map's own edges are
-- measured through the world positions of its corners.
local function mapStep(fromMap, fx, fy, toMap, tx, ty)
  local env = WL.env
  local c0, ox, oy = env.worldPos(fromMap, 0, 0)
  local c1, x1, y1 = env.worldPos(fromMap, 1, 0)
  local c2, x2, y2 = env.worldPos(fromMap, 0, 1)
  if c0 ~= nil and c0 == c1 and c0 == c2 and numbers(ox, oy, x1, y1, x2, y2) then
    local exx, exy, eyx, eyy = x1 - ox, y1 - oy, x2 - ox, y2 - oy
    local width, height = hypot(exx, exy), hypot(eyx, eyy)
    if fromMap == toMap then
      return (tx - fx) * width, (ty - fy) * height
    end
    local ct, wx, wy = env.worldPos(toMap, tx, ty)
    local det = exx * eyy - exy * eyx
    if ct ~= c0 or not numbers(wx, wy) or math.abs(det) < 1e-9 then
      return nil
    end
    local dx, dy = wx - ox, wy - oy
    local u = (dx * eyy - dy * eyx) / det
    local v = (exx * dy - exy * dx) / det
    return (u - fx) * width, (v - fy) * height
  end
  if fromMap == toMap then
    local w, h = env.mapSize(fromMap)
    if w then
      return (tx - fx) * w, (ty - fy) * h
    end
  end
  return nil
end

-- Compass bearing to the target in radians, clockwise from north (0 = north, pi/2 =
-- east), or nil.
function WL.bearing(fromMap, fx, fy, toMap, tx, ty)
  if not (fromMap and toMap and numbers(fx, fy, tx, ty)) then
    return nil
  end
  local east, south = mapStep(fromMap, fx, fy, toMap, tx, ty)
  if not east then
    return nil
  end
  return atan2(east, -south) % TAU
end

-- The game reports the facing counter-clockwise from north. The result is the angle
-- clockwise from straight ahead: 0 = ahead, pi/2 = right, pi = behind, 3 pi / 2 = left.
function WL.relativeAngle(bearing, facing)
  return (bearing + facing) % TAU
end

-- Line segments of the arrow for a relative angle: { { x1, y1, x2, y2 }, ... } as offsets
-- from the center (x right, y up), `size` = tip to tail length.
function WL.arrowSegments(angle, size)
  local dx, dy = math.sin(angle), math.cos(angle)
  local px, py = dy, -dx
  local half = size / 2
  local tipX, tipY = dx * half, dy * half
  local back, wing = size * 0.38, size * 0.26
  local baseX, baseY = tipX - dx * back, tipY - dy * back
  return {
    { -tipX, -tipY, tipX, tipY },
    { tipX, tipY, baseX + px * wing, baseY + py * wing },
    { tipX, tipY, baseX - px * wing, baseY - py * wing },
  }
end

function WL.arrived(yards, radius)
  return finite(yards) and yards <= radius
end

-- Display -------------------------------------------------------------------------------------

-- German shows meters (the client calls its yard values meters), kilometers from 1000;
-- everything else shows yards.
function WL.formatDistance(yards, locale)
  if not finite(yards) then
    return ""
  end
  yards = math.max(0, yards)
  if locale ~= "deDE" then
    return string.format("%d yd", math.floor(yards + 0.5))
  end
  if yards >= 1000 then
    return (string.format("%.1f km", yards / 1000):gsub("%.", ","))
  end
  return string.format("%d m", math.floor(yards + 0.5))
end

function WL.etaSeconds(yards, speed)
  if not finite(yards) then
    return nil
  end
  return yards / (speed or WL.WALK_SPEED)
end

function WL.formatEta(seconds)
  if not finite(seconds) then
    return ""
  end
  seconds = math.max(0, seconds)
  if seconds < 60 then
    return string.format("%d s", math.ceil(seconds))
  end
  local minutes = math.ceil(seconds / 60)
  if minutes < 60 then
    return string.format("%d min", minutes)
  end
  return string.format("%d h %d min", math.floor(minutes / 60), minutes % 60)
end
