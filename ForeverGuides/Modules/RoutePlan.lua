-- The route plan of this character, shared by the world map (WorldMapRoute, WorldMapRoutePanel) and the
-- Map & Route page: one state, one computed plan, one change message. The state is the list of
-- WorldMapRouteLogic (points, start, switches) kept in the character store (ForeverGuidesCharDB.routePlan);
-- the plan is TravelPlan.Plan over it, computed once per change and once per request for a new start.
--   RP.State() / RP.Plan() / RP.Rows() / RP.Summary()
--   RP.AddPoint(map, x, y) / RP.AddPlace(slug) / RP.Insert(slug) / RP.Remove(i) / RP.Move(i, d) /
--   RP.SetGoal(i) / RP.Replace(i, slug) / RP.SetStart(slug) / RP.SetOption(key, on) / RP.Clear()
--   RP.Swap()           start and goal change places (your position is the start only with "start at my position")
--   RP.AddWaypoint()    the active waypoint becomes the last point of the route
--   RP.Ends()           the explicit start and the goal slug (nil when not set)
--   RP.Hearth()         the hearthstone link for the plan: { to, ready }, or nil and a reason
--   RP.Start()          starts the journey (Journey.Start)
--   RP.AsWaypoints()    one waypoint per stop and the goal
-- Every change emits FG_ROUTEPLAN_CHANGED.
local _, ns = ...
local L, WRL, TL, TP = ns.L, ns.WorldMapRouteLogic, ns.TravelLogic, ns.TravelPlan

ns.AddLocale("enUS", {
  ["wmr.full"] = "The route has room for %d points at most.",
  ["wmr.noStart"] = "Your position is not known here. Set a start or step outside.",
  ["wmr.noData"] = "The travel data is not available.",
  ["wmr.journey.none"] = "There is no route to start yet.",
  ["wmr.journey.started"] = "Journey started: the arrow leads you step by step.",
  ["wmr.wp.none"] = "No point of this route has a position for a waypoint.",
  ["wmr.hearth.unknown"] = "Your hearthstone place is not on the map.",
  ["wmr.addwp"] = "Add waypoint",
  ["wmr.addwp.tip"] = "Appends the active waypoint as a route point.",
  ["wmr.addwp.none"] = "There is no active waypoint to add.",
  ["wmr.swap.none"] = "Set a goal first, then start and goal can swap.",
})

ns.AddLocale("deDE", {
  ["wmr.full"] = "In der Route ist Platz für höchstens %d Punkte.",
  ["wmr.noStart"] = "Deine Position ist hier nicht bekannt. Lege einen Start fest oder geh nach draußen.",
  ["wmr.noData"] = "Die Reisedaten sind nicht verfügbar.",
  ["wmr.journey.none"] = "Es gibt noch keine Route zum Starten.",
  ["wmr.journey.started"] = "Reise gestartet: Der Pfeil führt dich Schritt für Schritt.",
  ["wmr.wp.none"] = "Kein Punkt dieser Route hat eine Position für einen Wegpunkt.",
  ["wmr.hearth.unknown"] = "Der Ort deines Ruhesteins ist nicht auf der Karte.",
  ["wmr.addwp"] = "Wegpunkt anfügen",
  ["wmr.addwp.tip"] = "Hängt den aktiven Wegpunkt als Routenpunkt an.",
  ["wmr.addwp.none"] = "Es gibt keinen aktiven Wegpunkt zum Anfügen.",
  ["wmr.swap.none"] = "Lege zuerst ein Ziel fest, dann können Start und Ziel tauschen.",
})

local RP = {}
ns.RoutePlan = RP

local state, plan, nodes

-- The setting "Routenplanung auf der Weltkarte" (default on).
function RP.Enabled()
  local s = ns.db and ns.db.settings
  return not s or s.worldMapRoute ~= false
end

function RP.State()
  if not state then
    state = WRL.Clean(ns.charDB and ns.charDB.routePlan)
  end
  return state
end

local function changed()
  plan = nil
  WRL.Normalize(state)
  if ns.Store and ns.Store.setChar then
    ns.Store.setChar("routePlan", WRL.Persist(state))
  end
  ns.Emit("FG_ROUTEPLAN_CHANGED")
end

-- Own UI only (class a): changes wait for the end of combat when the player locks in combat.
local function locked()
  return ns.CombatLocked and ns.CombatLocked() or false
end

-- Names ------------------------------------------------------------------------------------------------

local function node(slug)
  if not nodes then
    nodes = {}
    for _, n in ipairs(ns.Data and ns.Data.Travel and ns.Data.Travel.nodes or {}) do
      nodes[n.s] = n
    end
  end
  return nodes[slug]
end

-- Zone and coordinates of a free point, the place name of a place.
function RP.Name(slug)
  if TL.IsPoint(slug) then
    local p = TL.ParsePoint(slug)
    if not p then
      return tostring(slug)
    end
    local zone = ns.Waypoints and ns.Waypoints.MapName and ns.Waypoints.MapName(p.map)
    return ns.MapRouteList.PointName(p, zone and zone:sub(1, 1) ~= "#" and zone or nil)
  end
  local n = node(slug)
  return n and ns.T(n.n) or tostring(slug or "?")
end

function RP.PositionOf(slug)
  local data = ns.Data and ns.Data.Travel
  return data and data.nodes and TP.PositionOf(data, slug) or nil
end

-- Plan --------------------------------------------------------------------------------------------------

-- The start the player set and the goal (the last point), as place or point slugs.
function RP.Ends()
  local st = RP.State()
  return st.start, st.points[#st.points]
end

local HEARTH_ITEM = 6948

local MIN_FUZZY = 4
local NOT_A_STOP = { placeholder = true, instanceEntrance = true }

local function contains(a, b)
  return #a >= MIN_FUZZY and #b >= MIN_FUZZY and (a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil)
end

-- The node for the name GetBindLocation answers (the subzone or town of the inn, never the inn itself):
-- the node of that exact name, else a node whose name and the subzone contain each other (longest name
-- wins), else the node of the matching zone that lies nearest to the middle of the zone's nodes.
local function bindNode(data, bound)
  local want = bound:lower()
  local fuzzy, fuzzyLen
  for _, n in ipairs(data.nodes) do
    local name = ns.T(n.n)
    if type(name) == "string" then
      name = name:lower()
      if name == want then
        return n
      end
      if not NOT_A_STOP[n.k] and contains(name, want) and (not fuzzy or #name > fuzzyLen) then
        fuzzy, fuzzyLen = n, #name
      end
    end
  end
  if fuzzy then
    return fuzzy
  end
  local zone, zoneLen
  for _, z in ipairs(data.zones or {}) do
    local name = ns.T(z.n)
    if type(name) == "string" and contains(name:lower(), want) and (not zone or #name > zoneLen) then
      zone, zoneLen = z.s, #name
    end
  end
  if not zone then
    return nil
  end
  local inZone, cx, cy = {}, 0, 0
  for _, n in ipairs(data.nodes) do
    if n.z == zone and not NOT_A_STOP[n.k] and type(n.x) == "number" and type(n.y) == "number" then
      inZone[#inZone + 1] = n
      cx, cy = cx + n.x, cy + n.y
    end
  end
  local best, bestD
  for _, n in ipairs(inZone) do
    local d = (n.x - cx / #inZone) ^ 2 + (n.y - cy / #inZone) ^ 2
    if not best or d < bestD or (d == bestD and n.s < best.s) then
      best, bestD = n, d
    end
  end
  return best
end

-- The hearthstone as a link of the plan: the place it is bound to (see bindNode) and whether the stone is
-- in the bags and off cooldown. nil and "unbound" when the bind place is no place of the travel data.
function RP.Hearth()
  local getBind = rawget(_G, "GetBindLocation")
  local bound = getBind and getBind() or nil
  local data = ns.Data and ns.Data.Travel
  if type(bound) ~= "string" or bound == "" or not (data and data.nodes) then
    return nil, "unbound"
  end
  local n = bindNode(data, bound)
  if not n then
    return nil, "unbound"
  end
  local count, cooldown = rawget(_G, "GetItemCount"), rawget(_G, "GetItemCooldown")
  local ready = not (count and count(HEARTH_ITEM) == 0)
  if ready and cooldown then
    local start, duration = cooldown(HEARTH_ITEM)
    local now = rawget(_G, "GetTime")
    ready = not (start and duration and duration > 0 and start + duration > (now and now() or 0))
  end
  return { to = n.s, ready = ready }
end

local function here()
  local WP = ns.Waypoints
  local map, x, y
  if WP and WP.PlayerPosition then
    map, x, y = WP.PlayerPosition()
  end
  if map then
    return { map = map, x = x, y = y }
  end
end

-- The plan of the current state: a TravelPlan result, false when there is nothing to plan (no goal, no
-- start, no data), nil is never returned. Cached until the state changes; `force` plans again (new
-- position, changed transport options).
function RP.Plan(force)
  local st = RP.State()
  if plan ~= nil and not force then
    return plan or nil
  end
  plan = false
  local data = ns.Data and ns.Data.Travel
  if not (data and data.nodes) or #st.points == 0 then
    return nil
  end
  local req = WRL.Request(st, here())
  if not req then
    return nil
  end
  local o = ns.MapRouteList.Options(ns.MapRequest and ns.MapRequest.shared or {})
  o.from, o.to = RP.Ends()
  if st.hearth then
    o.hearth = RP.Hearth()
  end
  local ok, result = ns.Safe("route-plan", TP.Plan, data, o, req)
  plan = ok and result or false
  return plan or nil
end

-- Why there is no plan: "empty" (no goal yet), "start" (no position and no start), "data".
function RP.Why()
  local st = RP.State()
  if not (ns.Data and ns.Data.Travel and ns.Data.Travel.nodes) then
    return "data"
  end
  if #st.points == 0 then
    return "empty"
  end
  if not (st.start or (st.fromHere and here())) then
    return "start"
  end
end

function RP.Rows()
  return WRL.Rows(RP.State(), RP.Plan(), RP.Name, ns.L["map.pin.goal"])
end

function RP.Summary()
  return WRL.Summary(RP.Plan())
end

-- The slug of the start for the numbered pins: the set start or the player position as a free point.
function RP.StartSlug()
  local st = RP.State()
  if st.start then
    return st.start
  end
  local h = st.fromHere and here()
  return h and TL.PointSlug(h.map, h.x, h.y) or nil
end

-- Changes ------------------------------------------------------------------------------------------------

local function apply(ok, reason)
  if ok then
    changed()
  elseif reason == "full" then
    ns.Notify(string.format(L["wmr.full"], WRL.MAX_POINTS), "warning")
  end
  return ok, reason
end

function RP.AddPoint(map, x, y)
  if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" or map < 1 then
    return false, "invalid"
  end
  return apply(WRL.Add(RP.State(), TL.PointSlug(map, math.max(0, math.min(1, x)), math.max(0, math.min(1, y)))))
end

function RP.AddPlace(slug)
  return apply(WRL.Add(RP.State(), slug))
end

function RP.Insert(slug)
  return apply(WRL.Insert(RP.State(), slug))
end

-- The place becomes the goal: the first point of an empty route, else the old goal's place.
function RP.SetGoalPlace(slug)
  local st = RP.State()
  if #st.points == 0 then
    return apply(WRL.Add(st, slug))
  end
  if st.points[#st.points] == slug then
    return false, "same"
  end
  return apply(WRL.Replace(st, #st.points, slug))
end

-- Takes a whole plan in one step ({ start, points, optimize, returnToStart }, validated). Emits the change
-- message only when something differs, so two views that mirror each other cannot loop.
function RP.Assign(raw)
  local old, new = WRL.Persist(RP.State()), WRL.Persist(WRL.Clean(raw))
  for _, key in ipairs({ "optimize", "returnToStart", "hearth", "fromHere" }) do
    if raw[key] == nil then
      new[key] = old[key]
    end
  end
  if
    table.concat(old.points, ",") == table.concat(new.points, ",")
    and old.start == new.start
    and old.optimize == new.optimize
    and old.returnToStart == new.returnToStart
    and old.hearth == new.hearth
    and old.fromHere == new.fromHere
  then
    return false
  end
  state = WRL.Clean(new)
  changed()
  return true
end

function RP.Remove(i)
  return apply(WRL.Remove(RP.State(), i))
end

-- Whether the order of the stops is the player's: false while the plan picks it (optimized order).
function RP.CanReorder()
  local st = RP.State()
  return not (st.optimize and RP.Plan() and RP.Plan().optimized)
end

-- Moves the point i one row up (-1) or down (1) in the list as shown (the visiting order).
function RP.Move(i, delta)
  if not RP.CanReorder() then
    return false, "auto"
  end
  local other = WRL.NeighborIndex(RP.Rows(), i, delta)
  if not other then
    return false, "none"
  end
  return apply(WRL.Reorder(RP.State(), i, other))
end

-- Drag and drop: point `from` goes to where point `to` stands.
function RP.Reorder(from, to)
  if not RP.CanReorder() then
    return false, "auto"
  end
  return apply(WRL.Reorder(RP.State(), from, to))
end

function RP.SetGoal(i)
  return apply(WRL.SetGoal(RP.State(), i))
end

function RP.Replace(i, slug)
  return apply(WRL.Replace(RP.State(), i, slug))
end

function RP.SetStart(slug)
  return apply(WRL.SetStart(RP.State(), slug))
end

-- Start and goal change places; stops stay. Without a start the player position becomes the goal.
function RP.Swap()
  local st = RP.State()
  local goal, from = st.points[#st.points], RP.StartSlug()
  if not (goal and from) then
    ns.Notify(L["wmr.swap.none"], "info")
    return false, "none"
  end
  if goal == from then
    return false, "same"
  end
  local points = { unpack(st.points) }
  points[#points] = from
  return RP.Assign({ start = goal, points = points })
end

-- The active waypoint is appended as a free point, the new goal.
function RP.AddWaypoint()
  local WP = ns.Waypoints
  local wp = WP and WP.Active and WP.Active()
  if not (wp and wp.map) then
    ns.Notify(L["wmr.addwp.none"], "info")
    return false, "none"
  end
  return RP.AddPoint(wp.map, wp.x, wp.y)
end

-- key: "optimize", "returnToStart", "hearth" or "fromHere" (start at the player position).
function RP.SetOption(key, on)
  local st = RP.State()
  if key ~= "optimize" and key ~= "returnToStart" and key ~= "hearth" and key ~= "fromHere" then
    return false, "invalid"
  end
  if key == "fromHere" then
    WRL.SetFromHere(st, on)
  else
    st[key] = on == true
  end
  changed()
  return true
end

function RP.Clear()
  WRL.Clear(RP.State())
  changed()
  return true
end

-- The plan is computed again on the next read, without a message (the page's own options changed).
function RP.Invalidate()
  plan = nil
end

-- The transport options changed (page options): plan again.
function RP.Replan()
  plan = nil
  ns.Emit("FG_ROUTEPLAN_CHANGED")
end

-- Actions ------------------------------------------------------------------------------------------------

function RP.Start()
  local p = RP.Plan()
  if not (p and p.targets and #p.targets > 0 and ns.Journey) then
    ns.Notify(L["wmr.journey.none"], "info")
    return false
  end
  local ok = ns.Journey.Start(p, RP.Name)
  if ok then
    ns.Notify(L["wmr.journey.started"], "success")
  end
  return ok and true or false
end

-- One waypoint per reachable stop and the goal that has a position, titled like the waypoints of the page's
-- route ("Route: <goal> k/n"); the old ones of the same goal are replaced.
function RP.AsWaypoints()
  local st, WP = RP.State(), ns.Waypoints
  if not (WP and #st.points > 0) then
    return 0
  end
  local rows = {}
  for _, row in ipairs(RP.Rows()) do
    if row.number or row.goal then
      rows[#rows + 1] = row
    end
  end
  local goalName = RP.Name(st.points[#st.points])
  for _, wp in pairs(ns.MapRouteList.RouteWaypoints(WP.List(), goalName)) do
    WP.Remove(wp.id, true)
  end
  local added = 0
  for k, row in ipairs(rows) do
    local pos = RP.PositionOf(st.points[row.index])
    if pos then
      local wp, status = WP.Add({
        map = pos.map,
        x = pos.x,
        y = pos.y,
        title = ns.MapRouteList.Title(goalName, k, #rows),
        source = "map",
        pinned = false,
      })
      if wp and status == "added" then
        added = added + 1
      end
    end
  end
  if added == 0 then
    ns.Notify(L["wmr.wp.none"], "warning")
  else
    ns.Notify(string.format(L["map.route.adopt.done"], added, goalName), "success")
  end
  return added
end

-- Every change and every action waits while the player locks in combat (settings.combatLock); nothing is
-- queued for later.
for _, name in ipairs({
  "AddPoint",
  "AddPlace",
  "Insert",
  "SetGoalPlace",
  "Assign",
  "Remove",
  "Move",
  "Reorder",
  "SetGoal",
  "Replace",
  "SetStart",
  "Swap",
  "AddWaypoint",
  "SetOption",
  "Clear",
  "Replan",
  "Start",
  "AsWaypoints",
}) do
  local fn = RP[name]
  RP[name] = function(...)
    if locked() then
      return false, "combat"
    end
    return fn(...)
  end
end
