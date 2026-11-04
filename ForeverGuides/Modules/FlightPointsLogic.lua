-- Flight points for the map icons and the list of the nearest ones: build from Data.FlightPoints,
-- the set a character has learned, its state, ordering by distance and the distance text. Pure logic,
-- no WoW API; the distance comes in as a function.
-- A set is { [slug] = true } over the slugs of Data.FlightPoints. A faction pair of the data (same Travel node,
-- two entries) is told apart by the faction of the player, see Resolver.
local _, ns = ...

ns.AddLocale("enUS", {
  ["fp.dist"] = "%s yards",
  ["fp.thousands"] = ",",
  ["fp.kind"] = "Flight point",
  ["fp.state.known"] = "Discovered",
  ["fp.state.unknown"] = "Not yet discovered",
  ["fp.hint"] = "Click: set waypoint",
  ["fp.legend.dim"] = "Dimmed: flight point not yet discovered",
  ["fp.set.world"] = "Flight points in the world map",
  ["fp.set.addon"] = "Dim undiscovered flight points on the add-on map",
  ["fp.set.listCount"] = "Flight points in the list",
  ["fp.set.onlyKnown"] = "List only discovered flight points",
  ["fp.tab"] = "Flights",
  ["fp.list.title"] = "Nearest flight points",
  ["fp.list.unknown"] = "not discovered",
  ["fp.list.nodist"] = "no data",
  ["fp.list.noPosition"] = "Position unknown, no distances here.",
  ["fp.list.empty"] = "No flight points to show.",
  ["fp.list.active"] = "Waypoint set",
  ["fp.slash.usage"] = "Usage: /fg flights [3-10]",
})
ns.AddLocale("deDE", {
  ["fp.dist"] = "%s Yards",
  ["fp.thousands"] = ".",
  ["fp.kind"] = "Flugpunkt",
  ["fp.state.known"] = "Entdeckt",
  ["fp.state.unknown"] = "Noch nicht entdeckt",
  ["fp.hint"] = "Klicken: Wegpunkt setzen",
  ["fp.legend.dim"] = "Ausgegraut: noch nicht entdeckter Flugpunkt",
  ["fp.set.world"] = "Flugpunkte in der Weltkarte",
  ["fp.set.addon"] = "Nicht entdeckte Flugpunkte auf der Addon-Karte ausgrauen",
  ["fp.set.listCount"] = "Flugpunkte in der Liste",
  ["fp.set.onlyKnown"] = "Nur entdeckte Flugpunkte in der Liste",
  ["fp.tab"] = "Flug",
  ["fp.list.title"] = "Nächste Flugpunkte",
  ["fp.list.unknown"] = "nicht entdeckt",
  ["fp.list.nodist"] = "keine Angabe",
  ["fp.list.noPosition"] = "Position unbekannt, hier gibt es keine Entfernung.",
  ["fp.list.empty"] = "Keine Flugpunkte zum Anzeigen.",
  ["fp.list.active"] = "Wegpunkt gesetzt",
  ["fp.slash.usage"] = "Benutzung: /fg flugpunkte [3-10]",
})

local FP = {}
ns.FlightPointsLogic = FP

local FACTIONS = { A = true, H = true }

FP.COUNT_MIN, FP.COUNT_MAX, FP.COUNT_DEFAULT = 3, 10, 5

-- Build ---------------------------------------------------------------------------------------

-- One entry per flight point: { slug, name, faction, map, x, y, travel } with the name in the active
-- language. opts.faction "A" or "H" drops the points of the other faction, "B" points always stay.
function FP.Build(points, opts)
  local faction = opts and FACTIONS[opts.faction] and opts.faction
  local out = {}
  for _, p in ipairs(points or {}) do
    if not faction or p.f == "B" or p.f == faction then
      out[#out + 1] = {
        slug = p.s,
        name = ns.T(p.n),
        faction = p.f,
        map = p.um,
        x = p.ux,
        y = p.uy,
        travel = p.t or p.s,
      }
    end
  end
  return out
end

-- Known set -----------------------------------------------------------------------------------

-- function(travelSlug) -> slug of the flight point of that Travel node for a player of this faction.
-- A node with one entry always gives it, a faction pair gives the entry of the faction (nil without one).
function FP.Resolver(points, faction)
  local byTravel = {}
  for _, p in ipairs(points or {}) do
    local key = p.t or p.s
    byTravel[key] = byTravel[key] or {}
    table.insert(byTravel[key], p)
  end
  return function(travelSlug)
    local list = byTravel[travelSlug]
    if list and #list == 1 then
      return list[1].s
    end
    for _, p in ipairs(list or {}) do
      if p.f == faction then
        return p.s
      end
    end
  end
end

-- New set: knownSet plus the slugs matchFn(name) gives for the names seen. Nothing is ever removed, a
-- flight path a character learned stays learned.
function FP.Merge(knownSet, namesSeen, matchFn)
  local out = {}
  for slug in pairs(knownSet or {}) do
    out[slug] = true
  end
  for _, name in ipairs(namesSeen or {}) do
    local slug = matchFn(name)
    if slug then
      out[slug] = true
    end
  end
  return out
end

-- Tooltip line of a state: "Discovered" / "Not yet discovered", nil for "neutral". L is ns.L.
local STATE_KEY = { known = "fp.state.known", unknown = "fp.state.unknown" }
function FP.StateText(state, L)
  return STATE_KEY[state] and L[STATE_KEY[state]]
end

-- "known", "unknown", or "neutral" while no flight map was ever read (hasData false): nothing is dimmed then.
function FP.State(point, knownSet, hasData)
  if not hasData then
    return "neutral"
  end
  return knownSet and knownSet[point.slug] and "known" or "unknown"
end

-- Nearest -------------------------------------------------------------------------------------

local function byName(a, b)
  if a.point.name ~= b.point.name then
    return a.point.name < b.point.name
  end
  return a.point.slug < b.point.slug
end

local function byDistance(a, b)
  if a.yards ~= b.yards then
    return a.yards < b.yards
  end
  return byName(a, b)
end

-- The n nearest points as { point, state, yards }, nearest first. from = { map, x, y } or nil.
-- opts.distanceFn(fromMap, fx, fy, toMap, tx, ty) -> yards or nil (default ns.WaypointLogic.distanceYards);
-- nil means another continent or unknown: such points have no yards, come after all others sorted by name
-- and only when opts.includeFar is set (also the only way to get any point without from).
-- opts.onlyKnown drops the points that are "unknown" (a character without data keeps all).
function FP.Nearest(points, knownSet, hasData, from, n, opts)
  opts = opts or {}
  local distance = opts.distanceFn or ns.WaypointLogic.distanceYards
  local near, far = {}, {}
  for _, point in ipairs(points or {}) do
    local state = FP.State(point, knownSet, hasData)
    if not (opts.onlyKnown and state == "unknown") then
      local yards = from and distance(from.map, from.x, from.y, point.map, point.x, point.y)
      table.insert(yards and near or far, { point = point, state = state, yards = yards })
    end
  end
  table.sort(near, byDistance)
  table.sort(far, byName)
  local out = near
  if opts.includeFar then
    for _, entry in ipairs(far) do
      out[#out + 1] = entry
    end
  end
  while n and #out > n do
    table.remove(out)
  end
  return out
end

-- Length of the list: a whole number from COUNT_MIN to COUNT_MAX, COUNT_DEFAULT for anything that is no number.
function FP.ClampCount(value)
  local n = tonumber(value)
  if not n or n ~= n then
    return FP.COUNT_DEFAULT
  end
  return math.max(FP.COUNT_MIN, math.min(FP.COUNT_MAX, math.floor(n + 0.5)))
end

-- The list of the nearest points: the reachable ones by distance, then (while room is left) the ones
-- without a distance. Without a position it is empty: an alphabetical cut would pass as "nearest".
-- opts as for Nearest, minus includeFar.
function FP.NearestList(points, knownSet, hasData, from, n, opts)
  if not from then
    return {}
  end
  opts = opts or {}
  return FP.Nearest(points, knownSet, hasData, from, FP.ClampCount(n), {
    distanceFn = opts.distanceFn,
    onlyKnown = opts.onlyKnown,
    includeFar = true,
  })
end

-- Text ----------------------------------------------------------------------------------------

-- "1,250 yards" / "1.250 Yards": whole yards with the thousands separator of the language. L is ns.L.
function FP.FormatDistance(yards, L)
  local whole = tostring(math.floor(yards + 0.5))
  local sep = L["fp.thousands"]
  local count
  repeat
    whole, count = whole:gsub("^(%d+)(%d%d%d)", "%1" .. sep .. "%2")
  until count == 0
  return L["fp.dist"]:format(whole)
end

-- Rows of the list from the entries of Nearest: { point, name, state, yards, distance (text, also for no
-- distance), undiscovered, active }. isActive(point) says whether the active waypoint is on that point.
function FP.Rows(entries, L, isActive)
  local rows = {}
  for i, entry in ipairs(entries) do
    rows[i] = {
      point = entry.point,
      name = entry.point.name,
      state = entry.state,
      yards = entry.yards,
      distance = entry.yards and FP.FormatDistance(entry.yards, L) or L["fp.list.nodist"],
      undiscovered = entry.state == "unknown",
      active = isActive ~= nil and isActive(entry.point) == true,
    }
  end
  return rows
end

-- "2. Auberdine, 1,250 yards, not discovered": one plain chat line of a row.
function FP.ChatLine(index, row, L)
  local parts = { row.name, row.distance }
  if row.undiscovered then
    parts[3] = L["fp.list.unknown"]
  end
  return string.format("%d. %s", index, table.concat(parts, ", "))
end

-- Body of the tooltip of a flight point (pin and list row): kind, state (not while no flight map was read),
-- the distance when known, a note while the active waypoint is on it, the hint.
function FP.TooltipText(state, yards, L, active)
  local lines = { L["fp.kind"] }
  local stateText = FP.StateText(state, L)
  if stateText then
    lines[#lines + 1] = stateText
  end
  if yards then
    lines[#lines + 1] = FP.FormatDistance(yards, L)
  end
  if active then
    lines[#lines + 1] = L["fp.list.active"]
  end
  lines[#lines + 1] = L["fp.hint"]
  return table.concat(lines, "\n")
end
