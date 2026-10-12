-- Waypoint state, persistence and behavior. The list and the active waypoint live in
-- ns.db.waypoints = { v, list = { waypoint }, active = id | nil, settings = { ... } }
-- (defaults in Core/Store.lua, waypoint fields in Modules/WaypointLogic.lua). Changes
-- are announced with ns.Emit("FG_WAYPOINTS_CHANGED", kind, id), kind = add | remove |
-- clear | update | active | settings; the arrow, the list and later map pages listen.
-- The arrival check runs on a slow OnUpdate that exists only while a waypoint is active.
local _, ns = ...
local L, U, WL = ns.L, ns.U, ns.WaypointLogic

local WP = {}
ns.Waypoints = WP

WP.SCHEMA = 1
-- migrations[n] upgrades the saved table from schema n - 1 to n (schema 1 is the first layout).
WP.migrations = {}

local TICK = 0.5
local MAX_ZONE_HITS = 5

ns.AddLocale("enUS", {
  ["wp.set"] = "Waypoint set: %s (%s) in %s",
  ["wp.duplicate"] = "There is already a waypoint here: %s",
  ["wp.full"] = "Waypoint list full (%d), remove some first.",
  ["wp.noPosition"] = "No position (instance, loading screen or no map data).",
  ["wp.err.empty"] = "Nothing to read, example: 45.2 63.1",
  ["wp.err.format"] = "Unreadable, e.g. 45.2 63.1 or Zone name 45.2 63.1",
  ["wp.err.range"] = "Coordinates: 0 to 100 (percent) or 0 to 1.",
  ["wp.err.noMap"] = "No map here, use #number or a zone name.",
  ["wp.err.unknownZone"] = 'No zone named "%s" was found.',
  ["wp.err.ambiguous"] = "Several matches: %s. Use #number or a longer name.",
  ["wp.err.link"] = "This map link could not be read.",
  ["wp.err.unknownMap"] = "There is no map with that number.",
  ["wp.err.invalid"] = "These coordinates are not valid.",
  ["wp.activated"] = "Active waypoint: %s",
  ["wp.removed"] = "Removed: %s",
  ["wp.cleared"] = "%d waypoint(s) removed.",
  ["wp.clearedKept"] = "%d waypoint(s) removed, %d pinned kept.",
  ["wp.none"] = "There are no waypoints yet.",
  ["wp.arrived"] = "Arrived: %s",
  ["wp.imported"] = "%d waypoint(s) imported, %d skipped.",
  ["wp.arrowOn"] = "Waypoint arrow shown.",
  ["wp.arrowOff"] = "Waypoint arrow hidden.",
  ["wp.slash.badNumber"] = "No waypoint %s, see /fg way list.",
  ["binding.wpNext"] = "Next waypoint",
  ["binding.wpArrow"] = "Waypoint arrow on or off",
  ["binding.wpHere"] = "Set waypoint here",
})
ns.AddLocale("deDE", {
  ["wp.set"] = "Wegpunkt gesetzt: %s (%s) in %s",
  ["wp.duplicate"] = "Hier gibt es schon einen Wegpunkt: %s",
  ["wp.full"] = "Wegpunkt-Liste voll (%d), entferne zuerst einige.",
  ["wp.noPosition"] = "Keine Position (Instanz, Ladebildschirm oder keine Karte).",
  ["wp.err.empty"] = "Nichts zu lesen, Beispiel: 45,2 63,1",
  ["wp.err.format"] = "Nicht lesbar, z. B. 45,2 63,1 oder Zonenname 45,2 63,1",
  ["wp.err.range"] = "Koordinaten: 0 bis 100 (Prozent) oder 0 bis 1.",
  ["wp.err.noMap"] = "Keine Karte hier, nutze #Nummer oder einen Zonennamen.",
  ["wp.err.unknownZone"] = 'Eine Zone namens "%s" wurde nicht gefunden.',
  ["wp.err.ambiguous"] = "Mehrere Treffer: %s. Nimm #Nummer oder einen längeren Namen.",
  ["wp.err.link"] = "Dieser Kartenlink ließ sich nicht lesen.",
  ["wp.err.unknownMap"] = "Es gibt keine Karte mit dieser Nummer.",
  ["wp.err.invalid"] = "Diese Koordinaten sind nicht gültig.",
  ["wp.activated"] = "Aktiver Wegpunkt: %s",
  ["wp.removed"] = "Entfernt: %s",
  ["wp.cleared"] = "%d Wegpunkt(e) entfernt.",
  ["wp.clearedKept"] = "%d Wegpunkt(e) entfernt, %d angeheftete bleiben.",
  ["wp.none"] = "Es gibt noch keine Wegpunkte.",
  ["wp.arrived"] = "Angekommen: %s",
  ["wp.imported"] = "%d Wegpunkt(e) importiert, %d übersprungen.",
  ["wp.arrowOn"] = "Wegpunkt-Pfeil eingeblendet.",
  ["wp.arrowOff"] = "Wegpunkt-Pfeil ausgeblendet.",
  ["wp.slash.badNumber"] = "Kein Wegpunkt Nr. %s, siehe /fg way list.",
  ["binding.wpNext"] = "Nächster Wegpunkt",
  ["binding.wpArrow"] = "Wegpunkt-Pfeil ein oder aus",
  ["binding.wpHere"] = "Wegpunkt hier setzen",
})

-- Saved data --------------------------------------------------------------------------------

-- Upgrades a saved table step by step, like Store.migrate. Pure: returns the table and the
-- list of applied steps. Tables from a later schema stay untouched.
function WP.migrate(db, target, migrations)
  target = target or WP.SCHEMA
  migrations = migrations or WP.migrations
  local applied = {}
  local current = type(db.v) == "number" and db.v or 0
  if current > target then
    return db, applied
  end
  for step = current + 1, target do
    local fn = migrations[step]
    if fn then
      fn(db)
    end
    applied[#applied + 1] = step
    db.v = step
  end
  return db, applied
end

local function bool(v)
  if type(v) == "boolean" then
    return v
  end
end

-- setting -> function(raw) returning a valid value or nil (then the default is used).
local CLEANERS = {
  arrow = bool,
  autoClear = bool,
  nativeMarker = bool,
  locked = bool,
  arrivalRadius = function(v)
    return type(v) == "number" and WL.clampRadius(v) or nil
  end,
  scale = function(v)
    if type(v) == "number" and WL.finite(v) then
      return U.round(U.clamp(v, 0.5, 2), 0.05)
    end
  end,
  -- Per-window look overrides (Modules/WindowStyle.lua); missing fields inherit the defaults.
  style = function(v)
    local WS = ns.WindowStyle
    local out = {}
    if type(v) == "table" then
      out.bg = WS.cleanHex(v.bg, nil)
      out.alpha = WS.cleanAlpha(v.alpha, nil)
      if type(v.autoHide) == "boolean" then
        out.autoHide = v.autoHide
      end
      -- Arrow window only: show the title bar / the background (missing = inherit, default on).
      if type(v.title) == "boolean" then
        out.title = v.title
      end
      if type(v.background) == "boolean" then
        out.background = v.background
      end
    end
    return out
  end,
}

local checked
-- The saved table, migrated and repaired once per database table (SavedVariables are
-- untrusted): only well-formed waypoints stay, the active id must exist.
function WP.data()
  local d = ns.db.waypoints
  if type(d) ~= "table" then
    d = {}
    ns.db.waypoints = d
  end
  if checked ~= d then
    checked = d
    WP.migrate(d)
    local list, seen = {}, {}
    for _, raw in ipairs(type(d.list) == "table" and d.list or {}) do
      local wp = WL.build(raw)
      if wp and wp.id and not seen[wp.id] and #list < WL.MAX then
        seen[wp.id] = true
        list[#list + 1] = wp
      end
    end
    d.list = list
    if not (type(d.active) == "string" and seen[d.active]) then
      d.active = nil
    end
    local defaults = ns.Store.defaults.waypoints.settings
    local raw = type(d.settings) == "table" and d.settings or {}
    local settings = {}
    for key, default in pairs(defaults) do
      local value = CLEANERS[key](raw[key])
      if value == nil then
        value = U.copy(default)
      end
      settings[key] = value
    end
    d.settings = settings
  end
  return d
end

function WP.List()
  return WP.data().list
end

function WP.Get(id)
  return WL.find(WP.data().list, id)
end

function WP.Active()
  local d = WP.data()
  return d.active and WL.find(d.list, d.active) or nil
end

function WP.Settings()
  return WP.data().settings
end

local function emit(kind, id)
  ns.Emit("FG_WAYPOINTS_CHANGED", kind, id)
end

-- Map, position and facing ----------------------------------------------------------------------

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
end

-- The player's map id, or nil when the client has none (loading screen, instance).
function WP.CurrentMap()
  local id = C_Map and call(C_Map.GetBestMapForUnit, "player")
  if WL.readable(id) and id > 0 then
    return id
  end
end

-- map, x, y of the player (x, y as fractions), or nil, reason ("api" | "map" | "position").
-- Instances and combat can hide the position: that is a plain nil, never an error.
function WP.PlayerPosition()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
    return nil, "api"
  end
  local map = WP.CurrentMap()
  if not map then
    return nil, "map"
  end
  local pos = call(C_Map.GetPlayerMapPosition, map, "player")
  if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then
    return nil, "position"
  end
  local okXY, x, y = pcall(pos.GetXY, pos)
  if not (okXY and WL.readable(x) and WL.readable(y)) or (x == 0 and y == 0) then
    return nil, "position"
  end
  return map, U.clamp(x, 0, 1), U.clamp(y, 0, 1)
end

-- The facing in radians (0 = north, counter-clockwise), or nil.
function WP.Facing()
  local facing = call(GetPlayerFacing)
  if WL.readable(facing) then
    return facing
  end
end

-- Yards from the player to a waypoint, or nil when it cannot be told.
function WP.Distance(wp)
  local map, x, y = WP.PlayerPosition()
  if not (map and wp) then
    return nil
  end
  return WL.distanceYards(map, x, y, wp.map, wp.x, wp.y)
end

-- Bearing relative to the player's facing (0 = ahead, clockwise), or nil.
function WP.RelativeAngle(wp)
  local map, x, y = WP.PlayerPosition()
  local facing = WP.Facing()
  if not (map and wp and facing) then
    return nil
  end
  local bearing = WL.bearing(map, x, y, wp.map, wp.x, wp.y)
  return bearing and WL.relativeAngle(bearing, facing) or nil
end

function WP.MapName(map)
  local info = C_Map and call(C_Map.GetMapInfo, map)
  if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
    return info.name
  end
  return "#" .. tostring(map)
end

-- Name -> map lookup -----------------------------------------------------------------------------

local zoneIndex

local function rankOf(info)
  local types = Enum and Enum.UIMapType
  if types and info.mapType == types.Zone then
    return 1
  elseif types and (info.mapType == types.Dungeon or info.mapType == types.Micro) then
    return 3
  end
  return 2
end

-- Every map the client knows below the cosmic and world maps, plus the player's own chain
-- (the Forever island may hang elsewhere). Built once on the first zone name. Data/Travel
-- holds no map ids, so it cannot feed this index.
function WP.ZoneIndex()
  if zoneIndex then
    return zoneIndex
  end
  zoneIndex = {}
  if not (C_Map and C_Map.GetMapChildrenInfo) then
    return zoneIndex
  end
  local seen = {}
  local function add(info)
    if
      type(info) == "table"
      and type(info.mapID) == "number"
      and type(info.name) == "string"
      and not seen[info.mapID]
    then
      seen[info.mapID] = true
      zoneIndex[#zoneIndex + 1] = { id = info.mapID, name = info.name, rank = rankOf(info) }
    end
  end
  local roots = { 946, 947 }
  roots[#roots + 1] = C_Map.GetFallbackWorldMapID and call(C_Map.GetFallbackWorldMapID) or nil
  for _, root in ipairs(roots) do
    for _, info in ipairs(call(C_Map.GetMapChildrenInfo, root, nil, true) or {}) do
      add(info)
    end
  end
  local id = WP.CurrentMap()
  for _ = 1, 8 do
    local info = id and call(C_Map.GetMapInfo, id)
    if type(info) ~= "table" then
      break
    end
    add(info)
    id = info.parentMapID
  end
  return zoneIndex
end

function WP.ParseContext()
  return {
    map = WP.CurrentMap(),
    zones = WP.ZoneIndex,
    mapExists = function(id)
      if not (C_Map and C_Map.GetMapInfo) then
        return true
      end
      return call(C_Map.GetMapInfo, id) ~= nil
    end,
  }
end

function WP.Parse(text)
  return WL.parse(text, WP.ParseContext())
end

function WP.ErrorText(code, detail)
  if code == "ambiguous" and type(detail) == "table" then
    local names = {}
    for i, hit in ipairs(detail) do
      if i > MAX_ZONE_HITS then
        names[#names + 1] = "..."
        break
      end
      names[#names + 1] = string.format("%s (#%d)", hit.name, hit.id)
    end
    return string.format(L["wp.err.ambiguous"], table.concat(names, ", "))
  elseif code == "unknownZone" then
    return string.format(L["wp.err.unknownZone"], tostring(detail or ""))
  end
  local key = "wp.err." .. tostring(code)
  return ns.Locales.enUS[key] and L[key] or L["wp.err.invalid"]
end

-- Blizzard marker ---------------------------------------------------------------------------------

-- Sets the game's own map pin. Never errors: the map may not allow a pin, or the API may be
-- missing on this client. The pin is not super-tracked (the client blocks that).
function WP.SetNative(map, x, y)
  if not (ns.can.userWaypoint and ns.can.uiMapPoint) then
    return false
  end
  if ns.can.canSetWaypoint then
    local ok, allowed = pcall(C_Map.CanSetUserWaypointOnMap, map)
    if not (ok and allowed) then
      return false
    end
  end
  return pcall(function()
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
  end)
end

function WP.ClearNative()
  if C_Map and C_Map.ClearUserWaypoint then
    pcall(C_Map.ClearUserWaypoint)
  end
end

-- Id of the waypoint our pin stands for: only that pin is cleared again, never one the
-- player placed by hand in the meantime.
local nativeFor

local function syncNative(force)
  local wp = WP.Active()
  if wp and WP.Settings().nativeMarker then
    if force or nativeFor ~= wp.id then
      if WP.SetNative(wp.map, wp.x, wp.y) then
        nativeFor = wp.id
      elseif nativeFor then
        WP.ClearNative()
        nativeFor = nil
      end
    end
  elseif nativeFor then
    WP.ClearNative()
    nativeFor = nil
  end
end

-- Arrival ------------------------------------------------------------------------------------------

local driver, tickAcc, armed = nil, 0, false

local function updateDriver()
  local want = WP.Active() ~= nil
  if want and not driver then
    driver = CreateFrame("Frame")
  end
  if driver then
    driver:SetScript("OnUpdate", want and function(_, elapsed)
      tickAcc = tickAcc + elapsed
      if tickAcc >= TICK then
        tickAcc = 0
        ns.Safe("waypoint-arrival", WP.CheckArrival)
      end
    end or nil)
  end
end

-- True when the active waypoint was reached. A waypoint only counts as reached after the
-- player has been farther away than the radius once, so setting one on the spot does not
-- remove it at once.
function WP.CheckArrival()
  local wp = WP.Active()
  if not wp then
    return false
  end
  local yards = WP.Distance(wp)
  if not yards then
    return false
  end
  if yards > WP.Settings().arrivalRadius then
    armed = true
    return false
  end
  if not armed then
    return false
  end
  WP.Arrive(wp)
  return true
end

-- Marks a waypoint as reached: toast, then it is removed (autoClear, not pinned) or kept,
-- and the next waypoint that was not reached yet becomes the active one.
function WP.Arrive(wp)
  local d = WP.data()
  wp.arrivedAt = U.now()
  ns.Notify(string.format(L["wp.arrived"], wp.title), "success")
  local nextWp = WL.nextAfterArrival(d.list, wp.id)
  local removed = d.settings.autoClear and not wp.pinned
  if removed then
    WP.Remove(wp.id, true)
  else
    emit("update", wp.id)
  end
  if nextWp then
    WP.Activate(nextWp.id)
  elseif not removed then
    WP.Deactivate()
  end
end

-- Changes ----------------------------------------------------------------------------------------------

function WP.Activate(id)
  local d = WP.data()
  local wp = WL.find(d.list, id)
  if not wp then
    return nil
  end
  d.active = wp.id
  wp.arrivedAt = nil
  armed = false
  tickAcc = 0
  syncNative()
  updateDriver()
  emit("active", wp.id)
  return wp
end

function WP.Deactivate()
  local d = WP.data()
  if d.active then
    d.active = nil
    armed = false
    syncNative()
    updateDriver()
    emit("active", nil)
  end
end

-- Adds a waypoint without making it active. spec = { map?, x, y, title?, note?, color?,
-- source?, pinned? } with x, y as fractions; map defaults to the player's map. Returns wp,
-- "added" | "duplicate", or nil, "invalid" | "full" | "noMap".
function WP.Add(spec)
  if type(spec) ~= "table" then
    return nil, "invalid"
  end
  if spec.map == nil then
    local map = WP.CurrentMap()
    if not map then
      return nil, "noMap"
    end
    local copy = U.copy(spec)
    copy.map = map
    spec = copy
  end
  local wp, status = WL.add(WP.data().list, spec, { now = U.now() })
  if status == "added" then
    emit("add", wp.id)
  end
  return wp, status
end

-- Adds (or finds) a waypoint and makes it the active one. input = spec table or text.
-- Returns wp, status or nil, error code, detail.
function WP.Set(input)
  local spec = input
  if type(input) == "string" then
    local code, detail
    spec, code, detail = WP.Parse(input)
    if not spec then
      return nil, code, detail
    end
  end
  local wp, status = WP.Add(spec)
  if not wp then
    return nil, status
  end
  WP.Activate(wp.id)
  return wp, status
end

-- Like Set, with the toast the player sees. Used by the slash command and the list window.
function WP.Command(input)
  local wp, status, detail = WP.Set(input)
  if not wp then
    if status == "full" then
      ns.Notify(string.format(L["wp.full"], WL.MAX), "warning")
    else
      ns.Notify(WP.ErrorText(status, detail), "warning")
    end
    return nil
  end
  if status == "duplicate" then
    ns.Notify(string.format(L["wp.duplicate"], wp.title), "info")
  else
    ns.Notify(string.format(L["wp.set"], wp.title, WL.coordText(wp.x, wp.y), WP.MapName(wp.map)), "success")
  end
  return wp
end

-- The player's own position as the active waypoint.
function WP.SetHere(title)
  local map, x, y = WP.PlayerPosition()
  if not map then
    ns.Notify(L["wp.noPosition"], "warning")
    return nil
  end
  return WP.Command({ map = map, x = x, y = y, title = title, source = "user" })
end

function WP.Remove(id, silent)
  local d = WP.data()
  local wp = WL.remove(d.list, id)
  if not wp then
    return nil
  end
  if d.active == wp.id then
    d.active = nil
    armed = false
    syncNative()
    updateDriver()
  end
  if not silent then
    ns.Notify(string.format(L["wp.removed"], wp.title), "info")
  end
  emit("remove", wp.id)
  return wp
end

-- Removes every waypoint that is not pinned (all with force). Returns removed, kept.
function WP.Clear(force)
  local d = WP.data()
  local removed = WL.clear(d.list, force)
  if d.active and not WL.find(d.list, d.active) then
    d.active = nil
    armed = false
    syncNative()
    updateDriver()
  end
  if removed > 0 then
    emit("clear")
  end
  return removed, #d.list
end

function WP.Step(delta)
  local d = WP.data()
  local wp = WL.cycle(d.list, d.active, delta)
  if not wp then
    ns.Notify(L["wp.none"], "info")
    return nil
  end
  WP.Activate(wp.id)
  ns.Notify(string.format(L["wp.activated"], wp.title), "info")
  return wp
end

function WP.Next()
  return WP.Step(1)
end

function WP.Previous()
  return WP.Step(-1)
end

-- The waypoint closest to the player: wp, yards.
function WP.Closest()
  local map, x, y = WP.PlayerPosition()
  if not map then
    return nil
  end
  return WL.nearest(WP.data().list, map, x, y)
end

local function update(id, fn, ...)
  local wp = fn(WP.data().list, id, ...)
  if wp then
    emit("update", id)
  end
  return wp
end

function WP.Rename(id, title)
  return update(id, WL.rename, title)
end

function WP.SetNote(id, note)
  return update(id, WL.setNote, note)
end

function WP.SetPinned(id, pinned)
  return update(id, WL.setPinned, pinned)
end

function WP.SetColor(id, color)
  return update(id, WL.setColor, color)
end

function WP.Move(id, map, x, y)
  local wp = update(id, WL.move, map, x, y)
  if wp and WP.data().active == id then
    armed = false
    syncNative(true)
  end
  return wp
end

-- Text export (one /way line per waypoint) and import. Returns added, skipped, errors.
function WP.Export()
  return WL.exportText(WP.data().list)
end

function WP.Import(text)
  local result = WL.importText(text, WP.ParseContext())
  local list = WP.data().list
  local added, skipped = 0, #result.errors
  for _, spec in ipairs(result.specs) do
    spec.source = "share"
    local _, status = WL.add(list, spec, { now = U.now() })
    if status == "added" then
      added = added + 1
    else
      skipped = skipped + 1
    end
  end
  if added > 0 then
    emit("add")
  end
  return added, skipped, result.errors
end

-- Validated setting change. Returns false for an unknown key or an invalid value.
function WP.SetSetting(key, value)
  local clean = CLEANERS[key] and CLEANERS[key](value)
  if clean == nil then
    return false
  end
  WP.Settings()[key] = clean
  if key == "nativeMarker" then
    syncNative()
  end
  emit("settings", key)
  return true
end

function WP.ToggleArrow()
  local on = not WP.Settings().arrow
  WP.SetSetting("arrow", on)
  ns.Notify(L[on and "wp.arrowOn" or "wp.arrowOff"], "info")
  return on
end

-- Slash command ---------------------------------------------------------------------------------------------

local SUBCOMMANDS = {
  list = "list",
  liste = "list",
  clear = "clear",
  leeren = "clear",
  next = "next",
  weiter = "next",
  naechster = "next",
  ["nächster"] = "next",
  prev = "prev",
  previous = "prev",
  zurueck = "prev",
  ["zurück"] = "prev",
  vorheriger = "prev",
  here = "here",
  hier = "here",
  arrow = "arrow",
  pfeil = "arrow",
  remove = "remove",
  entfernen = "remove",
  loeschen = "remove",
  ["löschen"] = "remove",
}

-- /fg way <coordinates | subcommand>
function WP.Slash(rest)
  rest = U.trim(rest or "")
  if rest == "" then
    ns.Notify(L["way.usage"], "info")
    return
  end
  local word, arg = rest:match("^([^%s]+)%s*(.-)$")
  local sub = SUBCOMMANDS[word:lower()]
  if sub == "list" then
    ns.WaypointList.Open()
  elseif sub == "clear" then
    local removed, kept = WP.Clear()
    ns.Notify(string.format(kept > 0 and L["wp.clearedKept"] or L["wp.cleared"], removed, kept), "info")
  elseif sub == "next" then
    WP.Next()
  elseif sub == "prev" then
    WP.Previous()
  elseif sub == "here" then
    WP.SetHere(arg)
  elseif sub == "arrow" then
    WP.ToggleArrow()
  elseif sub == "remove" then
    local wp = arg == "" and WP.Active() or WP.List()[tonumber(arg) or 0]
    if wp then
      WP.Remove(wp.id)
    else
      ns.Notify(arg == "" and L["wp.none"] or string.format(L["wp.slash.badNumber"], arg), "warning")
    end
  else
    WP.Command(rest)
  end
end

-- Key bindings (appended to the list of Modules/KeyBindings.lua, Bindings.xml calls
-- ns.KeyBindings.<Name>(); the handlers only touch unprotected frames, so they are safe in
-- combat).
local KB = ns.KeyBindings
local function binding(name, label, fn, run)
  KB.list[#KB.list + 1] = { name = name, label = label, fn = fn }
  KB[fn] = function()
    ns.Safe("binding:" .. fn, run)
  end
end
binding("FOREVERGUIDES_WAYPOINT_NEXT", "binding.wpNext", "WaypointNext", function()
  WP.Next()
end)
binding("FOREVERGUIDES_WAYPOINT_ARROW", "binding.wpArrow", "WaypointArrow", function()
  WP.ToggleArrow()
end)
binding("FOREVERGUIDES_WAYPOINT_HERE", "binding.wpHere", "WaypointHere", function()
  WP.SetHere("")
end)

ns.On("PLAYER_LOGIN", function()
  if ns.db then
    syncNative(true)
    updateDriver()
  end
end)
