-- Dungeon routes as pure logic (no frames): which route and rows belong to a floor, the numbering of the stops, the
-- style of a path kind and the canvas points of a path. Data: ForeverGuides_InstanceData/DungeonRoutes_<n>.lua
-- (docs/DUNGEONROUTES-FORMAT.md), drawn by Modules/DungeonMapView.lua with Modules/MapRouteStrokeLogic.lua.
local _, ns = ...

local R = {}
ns.DungeonRouteLogic = R

-- Per path kind: Theme token, stroke style (MapRouteStrokeLogic), width in px, alpha. Unknown kinds draw like main.
R.PATH_STYLES = {
  main = { token = "accent", style = "line", width = 3, alpha = 0.95 },
  boss = { token = "accent", style = "line", width = 3, alpha = 0.95 },
  side = { token = "textMuted", style = "dash", width = 2, alpha = 0.9 },
  optional = { token = "textMuted", style = "dash", width = 2, alpha = 0.9 },
  rare = { token = "warning", style = "dash", width = 2, alpha = 0.95 },
}
-- Plate color of a stop marker by stop kind.
R.STOP_TOKENS = { boss = "danger", optional = "textMuted", rare = "warning" }

function R.PathStyle(kind)
  return R.PATH_STYLES[kind] or R.PATH_STYLES.main
end

function R.StopToken(kind)
  return R.STOP_TOKENS[kind] or R.STOP_TOKENS.boss
end

local function fraction(v)
  return type(v) == "number" and v == v and v >= 0 and v <= 1
end

-- A usable list of routes: every route a table with a list of paths or stops. Anything else is dropped.
function R.Routes(list)
  local out = {}
  for _, route in ipairs(type(list) == "table" and list or {}) do
    if type(route) == "table" and (type(route.p) == "table" or type(route.s) == "table") then
      out[#out + 1] = route
    end
  end
  return #out > 0 and out or nil
end

-- The rows of one route on one floor. Stops are numbered in route order over all floors, so the number of a
-- stop does not change with the floor. Rows with a damaged position are left out.
-- Returns { paths = { path }, stops = { { stop, number } }, notes = { note } }.
function R.Visible(route, floor)
  local out = { paths = {}, stops = {}, notes = {} }
  if type(route) ~= "table" then
    return out
  end
  for _, p in ipairs(route.p or {}) do
    if p.f == floor and type(p.v) == "table" and #p.v >= 4 then
      out.paths[#out.paths + 1] = p
    end
  end
  for number, s in ipairs(route.s or {}) do
    if s.f == floor and fraction(s.x) and fraction(s.y) then
      out.stops[#out.stops + 1] = { stop = s, number = number }
    end
  end
  for _, w in ipairs(route.w or {}) do
    if w.f == floor and fraction(w.x) and fraction(w.y) then
      out.notes[#out.notes + 1] = w
    end
  end
  return out
end

-- Canvas px of the flat point list v (x, y, x, y, ...) in the arrays xs, ys. Returns the number of points.
function R.Points(v, width, height, xs, ys)
  local n = math.floor(#v / 2)
  for i = 1, n do
    xs[i], ys[i] = v[2 * i - 1] * width, v[2 * i] * height
  end
  return n
end

-- Index (BossList position) of the boss a stop belongs to, matched by encounter ID; nil when the data has none.
function R.BossIndex(stop, bosses)
  if type(stop) ~= "table" or not stop.e then
    return nil
  end
  for _, b in ipairs(bosses or {}) do
    if b.eid == stop.e then
      return b.idx
    end
  end
end

-- Room labels of one floor (ForeverGuides_InstanceData/DungeonRooms_<n>.lua, rows { f, x, y, n }) in data order, which
-- puts the larger rooms first. Rows without a name or with a damaged position are left out.
function R.RoomLabels(rooms, floor)
  local out = {}
  for _, row in ipairs(type(rooms) == "table" and rooms or {}) do
    if type(row) == "table" and row.f == floor and type(row.n) == "table" and fraction(row.x) and fraction(row.y) then
      out[#out + 1] = row
    end
  end
  return out
end

local function overlap(a, b)
  return math.abs(a.x - b.x) * 2 < a.w + b.w and math.abs(a.y - b.y) * 2 < a.h + b.h
end

-- Greedy choice of the labels that fit: items = { { x, y, w, h } } (centre and size in px, most important first),
-- blockers = rects of the same kind that must stay free (stop markers, pins). An item that would overlap a blocker or
-- an item chosen before is skipped; one that sticks out of the width x height canvas is moved inside. Returns an
-- array in item order: the placed rect { x, y, w, h } or false.
function R.PickLabels(items, blockers, width, height)
  local out, placed = {}, {}
  for i, item in ipairs(items) do
    local rect = {
      x = math.max(item.w / 2, math.min(item.x, width - item.w / 2)),
      y = math.max(item.h / 2, math.min(item.y, height - item.h / 2)),
      w = item.w,
      h = item.h,
    }
    local free = true
    for _, list in ipairs({ blockers, placed }) do
      for _, other in ipairs(list) do
        if overlap(rect, other) then
          free = false
          break
        end
      end
      if not free then
        break
      end
    end
    if free then
      placed[#placed + 1] = rect
    end
    out[i] = free and rect or false
  end
  return out
end
