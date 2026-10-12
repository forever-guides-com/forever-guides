-- The route in the side column of the map page: total time, one tab per alternative with its
-- time difference, compact steps that light up the leg on the map (and the other way round), and
-- the buttons that turn the route into waypoints. Pure helpers first (routes, texts, waypoint
-- planning), then Attach, which builds the frames. MapPage.lua hands in what only it knows.
local _, ns = ...
local W, L, Theme, TL, MR = ns.W, ns.L, ns.Theme, ns.TravelLogic, ns.MapRoute

local MRL = {}
ns.MapRouteList = MRL

local SWATCH_W, DUR_W, TAB_H = 30, 52, 28
local ROW_MIN = 30
local ICON_BTN, ICON_GAP = 28, 2 -- boxed icon button, space between buttons
local MAX_STOPS_TITLE = 8 -- room for " 99/100" behind the goal name in a title

ns.AddLocale("enUS", {
  ["map.route.leg"] = "%d. From %s to %s",
  ["map.route.legs"] = "%d leg(s)",
  ["map.route.tab.best"] = "Fastest",
  ["map.route.tab.alt"] = "Alternative %d (%s)",
  ["map.route.plus.min"] = "+%d min",
  ["map.route.plus.sec"] = "+%d s",
  ["map.route.capped"] = "Route too long to draw, the list shows every leg.",
  ["map.route.copy"] = "Copy as text",
  ["map.route.adopt"] = "Take route as waypoints",
  ["map.route.adopt.tip"] = "Adds a waypoint per stop with a position.\nExisting waypoints of this route are replaced.",
  ["map.route.adopt.title"] = "Route as waypoints",
  ["map.route.adopt.text"] = "Add %d waypoints for the route to %s?\nExisting ones of this route are replaced.",
  ["map.route.adopt.ask"] = "Add waypoints for the route?\nExisting ones of this route are replaced.",
  ["map.route.adopt.done"] = "%d waypoints added for the route to %s.",
  ["map.route.adopt.limit"] = "Waypoint list full: only %d of %d stops added.",
  ["map.route.adopt.skipped"] = "No real position, skipped: %s.",
  ["map.route.adopt.none"] = "No stop has a real position, no waypoint added.",
  ["map.route.next"] = "Next stop to arrow",
  ["map.route.next.tip"] = "Points the arrow at the first stop not yet reached.",
  ["map.route.next.done"] = "All stops of this route are reached.",
  ["map.route.next.none"] = "No stop of this route has a real position.",
  ["map.route.wpName"] = "Route: %s",
  ["map.route.pickStart"] = "Click a start. Esc or Done ends.",
  ["map.route.pickDest"] = "Click a goal. Esc or Done ends.",
  ["map.plan"] = "Start and goal",
  ["map.resetRoute"] = "Reset route",
  ["map.resetRoute.tip"] = "Clears start, goal and stops.",
  ["map.addStop"] = "+ Stop",
  ["map.addStop.tip"] = "Adds the selected place as a stop. Up to 5 stops, in the order shown.",
  ["map.stop"] = "Stop %d: %s",
  ["map.stop.up"] = "Move stop up",
  ["map.stop.down"] = "Move stop down",
  ["map.stop.remove"] = "Remove stop",
  ["map.route.part"] = "Part %d: %s to %s",
  ["map.route.part.stop"] = "%s (stop %d)",
  ["map.route.noneLeg"] = "No connection for part %d (%s to %s), change filters or faction.",
  ["map.route.share"] = "Route text for pasting:",
  ["map.route.paste"] = "Paste a route",
  ["map.route.paste.done"] = "Route taken over.",
  ["map.route.paste.bad"] = "This text is not a Forever Guides route.",
  ["map.route.paste.unknown"] = "Place not known for this faction: %s.",
})

ns.AddLocale("deDE", {
  ["map.route.leg"] = "%d. Von %s nach %s",
  ["map.route.legs"] = "%d Etappe(n)",
  ["map.route.tab.best"] = "Schnellste",
  ["map.route.tab.alt"] = "Alternative %d (%s)",
  ["map.route.plus.min"] = "+%d Min.",
  ["map.route.plus.sec"] = "+%d Sek.",
  ["map.route.capped"] = "Route zu lang für die Karte, die Liste zeigt alle Etappen.",
  ["map.route.copy"] = "Als Text kopieren",
  ["map.route.adopt"] = "Route als Wegpunkte übernehmen",
  ["map.route.adopt.tip"] = "Legt für jeden Halt mit Position einen Wegpunkt an.\nBestehende Wegpunkte dieser Route werden ersetzt.",
  ["map.route.adopt.title"] = "Route als Wegpunkte",
  ["map.route.adopt.text"] = "%d Wegpunkte für die Route nach %s anlegen?\nBestehende dieser Route werden ersetzt.",
  ["map.route.adopt.ask"] = "Wegpunkte für die Route anlegen?\nBestehende dieser Route werden ersetzt.",
  ["map.route.adopt.done"] = "%d Wegpunkte für die Route nach %s angelegt.",
  ["map.route.adopt.limit"] = "Wegpunkt-Liste voll: nur %d von %d Halten angelegt.",
  ["map.route.adopt.skipped"] = "Keine echte Position, übersprungen: %s.",
  ["map.route.adopt.none"] = "Kein Halt mit echter Position, kein Wegpunkt angelegt.",
  ["map.route.next"] = "Nächster Halt zum Pfeil",
  ["map.route.next.tip"] = "Richtet den Pfeil auf den ersten noch nicht erreichten Halt.",
  ["map.route.next.done"] = "Alle Halte dieser Route sind erreicht.",
  ["map.route.next.none"] = "Kein Halt dieser Route hat eine echte Position.",
  ["map.route.wpName"] = "Route: %s",
  ["map.route.pickStart"] = "Start anklicken. Esc oder Beenden schließt.",
  ["map.route.pickDest"] = "Ziel anklicken. Esc oder Beenden schließt.",
  ["map.plan"] = "Start und Ziel",
  ["map.resetRoute"] = "Route zurücksetzen",
  ["map.resetRoute.tip"] = "Leert Start, Ziel und Zwischenstopps.",
  ["map.addStop"] = "+ Zwischenstopp",
  ["map.addStop.tip"] = "Fügt den gewählten Ort als Zwischenstopp hinzu. Bis zu 5 Stopps, in der gezeigten Reihenfolge.",
  ["map.stop"] = "Stopp %d: %s",
  ["map.stop.up"] = "Stopp nach oben",
  ["map.stop.down"] = "Stopp nach unten",
  ["map.stop.remove"] = "Stopp entfernen",
  ["map.route.part"] = "Teilstrecke %d: %s nach %s",
  ["map.route.part.stop"] = "%s (Stopp %d)",
  ["map.route.noneLeg"] = "Keine Verbindung für Teilstrecke %d (%s nach %s), ändere Filter oder Fraktion.",
  ["map.route.share"] = "Routentext zum Einfügen:",
  ["map.route.paste"] = "Route einfügen",
  ["map.route.paste.done"] = "Route übernommen.",
  ["map.route.paste.bad"] = "Dieser Text ist keine Route von Forever Guides.",
  ["map.route.paste.unknown"] = "Ort für diese Fraktion unbekannt: %s.",
})

-- Pure logic ---------------------------------------------------------------------------

-- The routes of a TL.Route result, fastest first: { { steps, totalSec, without? }, ... }.
function MRL.Routes(result)
  if not result or result.status ~= "ok" then
    return {}
  end
  local out = { { steps = result.best.steps, totalSec = result.best.totalSec, parts = result.best.parts } }
  for _, alt in ipairs(result.alternatives) do
    out[#out + 1] = { steps = alt.steps, totalSec = alt.totalSec, without = alt.without, parts = alt.parts }
  end
  return out
end

-- "+3 min" for a route that takes diff seconds longer, "+40 s" under a minute.
function MRL.Delta(diff)
  diff = math.max(0, diff or 0)
  if diff < 60 then
    return string.format(L["map.route.plus.sec"], math.floor(diff + 0.5))
  end
  return string.format(L["map.route.plus.min"], math.floor(diff / 60 + 0.5))
end

-- The tab label of route i (1 = the fastest). With "prefer flying" an alternative can be the shorter
-- one in real time, its difference then reads "-3 min".
function MRL.TabLabel(routes, i)
  if i == 1 then
    return L["map.route.tab.best"]
  end
  local diff = routes[i].totalSec - routes[1].totalSec
  local delta = MRL.Delta(math.abs(diff))
  if diff < 0 then
    delta = "-" .. delta:sub(2)
  end
  return string.format(L["map.route.tab.alt"], i, delta)
end

-- The extra facts of a step (requirement, source, cost, note); colored for the list, plain for
-- the copied text.
local function extras(step, colored)
  local function tint(token, text)
    return colored and Theme.hexText(token, text) or text
  end
  local out = {}
  if step.rq and L["map.rq." .. step.rq] ~= "map.rq." .. step.rq then
    out[#out + 1] = tint("warning", L["map.rq." .. step.rq])
  end
  if step.cf == "estimate" or step.cf == "reported" then
    out[#out + 1] = tint("textMuted", L["map.cf." .. step.cf])
  end
  if step.cost and step.cost > 0 then
    out[#out + 1] = string.format(L["map.route.cost"], ns.RefLogic.Money(step.cost))
  end
  if step.rn then
    out[#out + 1] = ns.T(step.rn) or step.rn
  end
  return out
end

-- The tooltip text of a step: second line, duration, and where a walk time comes from.
function MRL.LegDetail(step)
  local text = MRL.StepSub(step) .. " · " .. TL.FormatDuration(step.sec)
  if step.wc then
    text = text .. " · " .. L["map.cf.world"]
  end
  return text
end

-- The second line of a step: transport, then the extra facts.
function MRL.StepSub(step)
  local parts = { L["map.mode." .. step.mode] }
  for _, e in ipairs(extras(step, true)) do
    parts[#parts + 1] = e
  end
  return table.concat(parts, " · ")
end

-- "Part 2: A to B (stop 2)": the title of one part of a route over stops.
function MRL.PartTitle(part, nameOf)
  local to = nameOf(part.to)
  if part.stop then
    to = string.format(L["map.route.part.stop"], to, part.stop)
  end
  return string.format(L["map.route.part"], part.k, nameOf(part.from), to)
end

-- The whole result as plain text for "Copy as text", the same content the page showed before.
-- A route over stops gets one line per part; share (the string of MRL.Encode) ends the text.
function MRL.Text(result, nameOf, share)
  local routes = MRL.Routes(result)
  if #routes == 0 then
    return ""
  end
  local function stepLine(i, step)
    local parts = {
      string.format("%d. %s > %s", i, nameOf(step.from), nameOf(step.to)),
      L["map.mode." .. step.mode],
      TL.FormatDuration(step.sec),
    }
    for _, e in ipairs(extras(step, false)) do
      parts[#parts + 1] = e
    end
    return table.concat(parts, " · ")
  end
  local lines = {}
  for r, route in ipairs(routes) do
    if r > 1 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = string.format(
        L["map.route.alt"],
        L["map.mode." .. route.without],
        TL.FormatDuration(route.totalSec),
        #route.steps
      )
    else
      lines[#lines + 1] = string.format(L["map.route.total"], TL.FormatDuration(route.totalSec), #route.steps)
    end
    local parts = route.parts
    local nextPart = 1
    for i, step in ipairs(route.steps) do
      if parts and #parts > 1 and parts[nextPart] and parts[nextPart].first == i then
        local part = parts[nextPart]
        lines[#lines + 1] = MRL.PartTitle(part, nameOf) .. " · " .. TL.FormatDuration(part.totalSec)
        nextPart = nextPart + 1
      end
      lines[#lines + 1] = stepLine(i, step)
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = L["map.route.waitNote"]
  if share then
    lines[#lines + 1] = L["map.route.share"]
    lines[#lines + 1] = share
  end
  return table.concat(lines, "\n")
end

-- Which end a click on a place sets next in the Start/Goal mode.
function MRL.NextWhich(st)
  return st.pickNext or ((st.start and not st.dest) and "dest" or "start")
end

-- Sets the next end to the place and moves on; returns which end was set.
function MRL.Pick(st, slug)
  local which = MRL.NextWhich(st)
  st[which] = slug
  st.pickNext = which == "start" and "dest" or "start"
  return which
end

-- Start, the stops in order, goal (start and goal must be set).
function MRL.Chain(st)
  local out = { st.start }
  for _, slug in ipairs(st.stops or {}) do
    out[#out + 1] = slug
  end
  out[#out + 1] = st.dest
  return out
end

-- Adds slug as the last stop. Returns true, or false and the reason: "none" (no place), "full"
-- (TL.MAX_STOPS reached) or "same" (the place before or after it is the same one).
function MRL.AddStop(st, slug)
  if not slug then
    return false, "none"
  end
  st.stops = st.stops or {}
  if #st.stops >= TL.MAX_STOPS then
    return false, "full"
  end
  if slug == (st.stops[#st.stops] or st.start) or slug == st.dest then
    return false, "same"
  end
  st.stops[#st.stops + 1] = slug
  return true
end

-- Swaps stop i with its neighbor (delta -1 up, 1 down). Returns whether anything moved.
function MRL.MoveStop(st, i, delta)
  local stops = st.stops or {}
  local j = i + delta
  if not (stops[i] and stops[j]) then
    return false
  end
  stops[i], stops[j] = stops[j], stops[i]
  return true
end

function MRL.RemoveStop(st, i)
  if st.stops and st.stops[i] then
    table.remove(st.stops, i)
    return true
  end
  return false
end

-- "fgroute:v1:<faction>:<start>;<stop>;...;<goal>" with the place slugs, to share or paste.
function MRL.Encode(faction, list)
  return "fgroute:v1:" .. faction .. ":" .. table.concat(list, ";")
end

-- Reads such a string: { faction, start, stops, dest } or nil and "format". Only the shape is
-- checked here, whether the places exist is the caller's business.
function MRL.Decode(text)
  local faction, body = ns.U.trim(text or ""):match("^fgroute:v1:([AH]):([%w%-;]+)$")
  if not faction then
    return nil, "format"
  end
  local list = {}
  for slug in (body .. ";"):gmatch("([^;]*);") do
    if slug == "" then
      return nil, "format"
    end
    list[#list + 1] = slug
  end
  if #list < 2 or #list > TL.MAX_STOPS + 2 then
    return nil, "format"
  end
  local stops = {}
  for i = 2, #list - 1 do
    stops[#stops + 1] = list[i]
  end
  return { faction = faction, start = list[1], stops = stops, dest = list[#list] }
end

-- The planner options of a page state (or of the shared one the world map bar reads): faction,
-- transport switches, level, "prefer flying" and "with mount" (both on unless switched off).
-- from and to come from the state as well.
function MRL.Options(st)
  local K = ns.PageKit
  local modes = {}
  for _, m in ipairs(TL.MODES) do
    modes[m] = st.modes == nil or st.modes[m] or false
  end
  modes.teleport = true
  local okDate, today = pcall(date, "%Y-%m-%d")
  return {
    from = st.start,
    to = st.dest,
    faction = st.faction or K.PlayerFaction() or "A",
    level = st.useLevel ~= false and UnitLevel and UnitLevel("player") or 60,
    class = K.PlayerClass(),
    skyborne = st.skyborne == true,
    modes = modes,
    mount = st.mount ~= false,
    preferFlight = st.preferFlight ~= false,
    today = okDate and today or nil,
  }
end

-- The stops of a route: { { k, slug, spec = { map, x, y } or nil }, ... }, one more than steps.
-- specFor(slug) gives the waypoint position of a place, nil for an estimated one.
function MRL.Stops(steps, specFor)
  local out = {}
  if #steps == 0 then
    return out
  end
  for k = 1, #steps + 1 do
    local slug = k <= #steps and steps[k].from or steps[#steps].to
    out[k] = { k = k, slug = slug, spec = specFor(slug) }
  end
  return out
end

-- A name cut to maxBytes without splitting a UTF-8 character.
local function clip(text, maxBytes)
  if #text <= maxBytes then
    return text
  end
  local cut = maxBytes
  while cut > 0 do
    local b = text:byte(cut + 1)
    if b and b >= 0x80 and b < 0xC0 then
      cut = cut - 1
    else
      break
    end
  end
  return text:sub(1, cut)
end

-- "Route: <goal>" the way it starts the title of every stop's waypoint.
function MRL.TitlePrefix(goalName)
  local head = string.format(L["map.route.wpName"], "")
  local room = ns.WaypointLogic.MAX_TITLE - #head - MAX_STOPS_TITLE
  return string.format(L["map.route.wpName"], clip(goalName, room))
end

function MRL.Title(goalName, k, total)
  return string.format("%s %d/%d", MRL.TitlePrefix(goalName), k, total)
end

-- The waypoints of this route on the list as k -> wp: map source, not pinned, title
-- "<prefix> k/total".
function MRL.RouteWaypoints(list, goalName)
  local prefix = MRL.TitlePrefix(goalName) .. " "
  local out = {}
  for _, wp in ipairs(list) do
    if wp.source == "map" and not wp.pinned and wp.title:sub(1, #prefix) == prefix then
      local k = wp.title:sub(#prefix + 1):match("^(%d+)/%d+$")
      if k then
        out[tonumber(k)] = wp
      end
    end
  end
  return out
end

-- What taking the route as waypoints does: the stops with a position (as many as fit after the
-- old waypoints of this route are gone), the skipped ones and the waypoints to replace.
function MRL.PlanAdopt(stops, goalName, list, max)
  local existing = MRL.RouteWaypoints(list, goalName)
  local replaced = 0
  for _ in pairs(existing) do
    replaced = replaced + 1
  end
  -- A stop at the place of a waypoint that stays (or of an earlier stop) adds nothing new.
  local gone, kept = {}, {}
  for _, wp in pairs(existing) do
    gone[wp] = true
  end
  for _, wp in ipairs(list) do
    if not gone[wp] then
      kept[#kept + 1] = wp
    end
  end
  local WL = ns.WaypointLogic
  local items, skipped, merged = {}, {}, 0
  for _, s in ipairs(stops) do
    local built = s.spec and WL.build({ map = s.spec.map, x = s.spec.x, y = s.spec.y })
    if not built then
      skipped[#skipped + 1] = s
    elseif WL.findDuplicate(kept, built.map, built.x, built.y) then
      merged = merged + 1
    else
      items[#items + 1] = s
      kept[#kept + 1] = built
    end
  end
  local room = max - (#list - replaced)
  local wanted = #items
  local truncated = wanted > room
  if truncated then
    for i = #items, math.max(room, 0) + 1, -1 do
      items[i] = nil
    end
  end
  return {
    items = items,
    skipped = skipped,
    merged = merged,
    replace = existing,
    replaced = replaced,
    truncated = truncated,
    wanted = wanted,
  }
end

-- The first stop with a position that was not reached yet. byK = RouteWaypoints, done[k] = the
-- stop was added in this session (a missing waypoint then means it was reached and removed).
function MRL.NextStop(stops, byK, done)
  for _, s in ipairs(stops) do
    if s.spec then
      local wp = byK[s.k]
      if wp then
        if not wp.arrivedAt then
          return s
        end
      elseif not (done and done[s.k]) then
        return s
      end
    end
  end
end

-- Controls -----------------------------------------------------------------------------

-- The start, stop and goal lines of the side column. ctx = { side, state, nameOf(slug),
-- changed() }: the lines read state.start, state.stops and state.dest; a change of the stop list
-- (move, remove) calls changed(). Returns { box, startText, destText, rows, Update }; the page
-- sets the texts of start and goal itself.
function MRL.AttachStops(ctx)
  local st = ctx.state
  local box = CreateFrame("Frame", nil, ctx.side.content)
  local ctl = { box = box, rows = {} }
  ctl.startText = W.Text(box, { role = "text", color = "text", wrap = true })
  ctl.destText = W.Text(box, { role = "text", color = "text", wrap = true })

  local function newRow()
    local row = CreateFrame("Frame", nil, box)
    row.text = W.Text(row, { role = "text", color = "text", wrap = true })
    local function act(fn, delta)
      return function()
        if fn(st, row.index, delta) then
          ctx.changed()
        end
      end
    end
    row.remove = W.Action(row, {
      icon = "close",
      size = ICON_BTN,
      boxed = true,
      tooltip = "map.stop.remove",
      onClick = act(MRL.RemoveStop),
    })
    row.down = W.Action(row, {
      icon = "chevron-down",
      size = ICON_BTN,
      boxed = true,
      tooltip = "map.stop.down",
      onClick = act(MRL.MoveStop, 1),
    })
    row.up = W.Action(row, {
      icon = "chevron-up",
      size = ICON_BTN,
      boxed = true,
      tooltip = "map.stop.up",
      onClick = act(MRL.MoveStop, -1),
    })
    row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -ICON_GAP, 0)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -ICON_GAP, 0)
    return row
  end

  -- Texts and buttons of the stop rows from the state; rows beyond the list hide.
  function ctl.Update()
    local stops = st.stops or {}
    for i, slug in ipairs(stops) do
      local row = ctl.rows[i]
      if not row then
        row = newRow()
        ctl.rows[i] = row
      end
      row.index = i
      W.SetText(row.text, nil, string.format(L["map.stop"], i, ctx.nameOf(slug)))
      row.up:SetShown(i > 1)
      row.down:SetShown(i < #stops)
      row:Show()
    end
    for i = #stops + 1, #ctl.rows do
      ctl.rows[i].index = nil
      ctl.rows[i]:Hide()
    end
  end

  function box:fgGridLayout(width)
    ctl.startText:ClearAllPoints()
    ctl.startText:SetPoint("TOPLEFT", self, "TOPLEFT")
    ctl.startText:SetWidth(width)
    local y = math.ceil(ctl.startText:GetStringHeight()) + 6
    local textW = math.max(40, width - 3 * ICON_BTN - 2 * ICON_GAP - 8)
    for _, row in ipairs(ctl.rows) do
      if row.index then
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT")
        row.text:SetWidth(textW)
        local h = math.max(ICON_BTN + 2, math.ceil(row.text:GetStringHeight()) + 6)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        row:SetSize(width, h)
        y = y + h + 4
      end
    end
    ctl.destText:ClearAllPoints()
    ctl.destText:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    ctl.destText:SetWidth(width)
    y = y + math.ceil(ctl.destText:GetStringHeight())
    self:SetHeight(y)
    return y
  end

  return ctl
end

-- Attach -------------------------------------------------------------------------------
-- ctx = {
--   side                         the page's side column ({ content, stack })
--   state                        { start, dest, alt }
--   nameOf(slug)                 localized place name
--   route                        the MapRoute controller (SetRoute, SetHover, Capped)
--   specFor(slug)                { map, x, y } for a waypoint at the place, nil when estimated
--   showStep(step)               a click on a step: zoom into its zone
--   relayout()                   lays the page out again
--   share()                      optional, the route string (MRL.Encode) for "Copy as text"
-- }
-- Returns the controller: box, Set, Message, PaintHover, LegTip, Adopt, NextStop, plus the
-- frames tabs, rows and buttons for the tests.
function MRL.Attach(ctx)
  local FL = ns.FlowLayout
  local st = ctx.state
  local WL = ns.WaypointLogic
  local ctl = { routes = {}, tabs = {}, rows = {}, heads = {}, headAt = {}, adopted = {} }

  local box = CreateFrame("Frame", nil, ctx.side.content)
  ctl.box = box
  local msg = W.Text(box, { role = "ui", color = "textSecondary", wrap = true })
  local total = W.Text(box, { role = "h2", family = "heading", color = "accent2" })
  local meta = W.Text(box, { role = "ui", color = "textSecondary" })
  local note = W.Text(box, { role = "micro", color = "textMuted", wrap = true })
  local capped = W.Text(box, { key = "map.route.capped", role = "micro", color = "warning", wrap = true })
  ctl.msg, ctl.total, ctl.meta, ctl.note, ctl.capped = msg, total, meta, note, capped
  W.SetText(note, "map.route.waitNote")

  local function choose(i)
    st.alt = i
    ctl.Set(ctl.result, ctl.key)
    ctx.relayout()
  end

  local function newTab()
    local b = CreateFrame("Button", nil, box)
    b:SetHeight(TAB_H)
    b.label = W.Text(b, { role = "ui", color = "textSecondary", justify = "CENTER" })
    b.label:SetPoint("CENTER")
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetPoint("BOTTOMRIGHT")
    b.bar:SetHeight(2)
    ns.Bind(b, function(self)
      self.bar:SetColorTexture(Theme.color("accent2"))
    end)
    b:SetScript(
      "OnClick",
      ns.Wrap("map-route-tab", function(self)
        choose(self.index)
      end)
    )
    b:SetScript("OnEnter", function(self)
      local route = ctl.routes[self.index]
      if route and route.without then
        ns.ShowTooltip(
          self,
          string.format(
            L["map.route.alt"],
            L["map.mode." .. route.without],
            TL.FormatDuration(route.totalSec),
            #route.steps
          )
        )
      end
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    ns.Focus.register(b, function(self)
      self:Click()
    end)
    return b
  end

  local function newRow()
    local row = CreateFrame("Button", nil, box)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.stripe = row:CreateTexture(nil, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT")
    row.stripe:SetPoint("BOTTOMLEFT")
    row.stripe:SetWidth(3)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.swatch = {}
    for i = 1, 5 do
      row.swatch[i] = row:CreateTexture(nil, "ARTWORK")
    end
    row.title = W.Text(row, { role = "ui", color = "text", wrap = true })
    row.sub = W.Text(row, { role = "micro", color = "textSecondary", wrap = true })
    row.dur = W.Text(row, { role = "ui", color = "text", justify = "RIGHT" })
    row.dur:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
    row.dur:SetWidth(DUR_W)
    row:SetScript("OnEnter", function(self)
      ctx.route.SetHover(self.index)
    end)
    row:SetScript("OnLeave", function(self)
      if ctx.route.hover == self.index then
        ctx.route.SetHover(nil)
      end
    end)
    row:SetScript(
      "OnClick",
      ns.Wrap("map-route-step", function(self)
        if self.step then
          ctx.showStep(self.step)
        end
      end)
    )
    ns.Focus.register(row, function(self)
      self:Click()
    end)
    ns.Bind(row, function(self)
      self.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
      self.stripe:SetColorTexture(Theme.color("accent2"))
      if self.step then
        ctl.PaintRow(self)
      end
    end)
    return row
  end

  -- The title line of one part of a route over stops, above its steps.
  local function newHead()
    local head = CreateFrame("Frame", nil, box)
    head.title = W.Text(head, { role = "ui", color = "accent2", wrap = true })
    head.dur = W.Text(head, { role = "ui", color = "accent2", justify = "RIGHT" })
    head.dur:SetPoint("TOPRIGHT", head, "TOPRIGHT", -8, -6)
    head.dur:SetWidth(DUR_W)
    return head
  end

  -- Row styling that depends on state: swatch color and pattern, the hover tint and stripe.
  function ctl.PaintRow(row)
    local style = MR.Style(row.step.mode)
    local lit = ctx.route.hover == row.index
    row.bg:SetColorTexture(1, 1, 1, lit and 0.12 or 0)
    row.stripe:SetShown(lit)
    local segs = MR.Swatch(style, SWATCH_W)
    for i, tex in ipairs(row.swatch) do
      local seg = segs[i]
      tex:SetShown(seg ~= nil)
      if seg then
        tex:ClearAllPoints()
        tex:SetPoint("LEFT", row, "LEFT", 8 + seg[1], 0)
        tex:SetSize(math.max(1, seg[2]), style.thin and 2 or 3)
        tex:SetColorTexture(Theme.color(style.token))
      end
    end
  end

  -- The hovered leg (from the map or the list) tints its step.
  function ctl.PaintHover()
    for _, row in ipairs(ctl.rows) do
      if row:IsShown() and row.step then
        ctl.PaintRow(row)
      end
    end
  end

  -- The tooltip of a leg on the map.
  function ctl.LegTip(i)
    local route = ctl.routes[st.alt or 1]
    local step = route and route.steps[i]
    if not step then
      return nil
    end
    return string.format(L["map.route.leg"], i, ctx.nameOf(step.from), ctx.nameOf(step.to)), MRL.LegDetail(step)
  end

  -- Buttons --------------------------------------------------------------------------------
  local function goal()
    return ctx.nameOf(st.dest)
  end

  local function currentStops()
    local route = ctl.routes[st.alt or 1]
    return route and MRL.Stops(route.steps, ctx.specFor) or {}
  end

  -- Takes the stops of the shown route as waypoints (after the question); replaces the waypoints
  -- of this route that are already there instead of adding them twice.
  local function doAdopt(plan, stopCount)
    local WP = ns.Waypoints
    local name = goal()
    for _, wp in pairs(plan.replace) do
      WP.Remove(wp.id, true)
    end
    local added = 0
    ctl.adopted = { goal = name, ks = {} }
    for _, s in ipairs(plan.items) do
      local wp, status = WP.Add({
        map = s.spec.map,
        x = s.spec.x,
        y = s.spec.y,
        title = MRL.Title(name, s.k, stopCount),
        source = "map",
        pinned = false,
      })
      if wp and status == "added" then
        added = added + 1
        ctl.adopted.ks[s.k] = true
      end
    end
    ns.Notify(string.format(L["map.route.adopt.done"], added, name), "success")
    if plan.truncated then
      ns.Notify(string.format(L["map.route.adopt.limit"], added, plan.wanted), "warning")
    end
    if #plan.skipped > 0 then
      local names = {}
      for i, s in ipairs(plan.skipped) do
        names[i] = ctx.nameOf(s.slug)
      end
      ns.Notify(string.format(L["map.route.adopt.skipped"], table.concat(names, ", ")), "info")
    end
    return added
  end

  function ctl.Adopt()
    local stops = currentStops()
    if #stops == 0 or not st.dest then
      return
    end
    local plan = MRL.PlanAdopt(stops, goal(), ns.Waypoints.List(), WL.MAX)
    if plan.wanted == 0 then
      if #plan.skipped == #stops then
        ns.Notify(L["map.route.adopt.none"], "warning")
      else
        ns.Notify(string.format(L["map.route.adopt.done"], 0, goal()), "info")
      end
      return
    end
    if #plan.items == 0 then
      ns.Notify(string.format(L["wp.full"], WL.MAX), "warning")
      return
    end
    -- The question carries the count, so its text is a key filled for this one use.
    ns.AddLocale(ns.GetActiveLocale(), {
      ["map.route.adopt.ask"] = string.format(L["map.route.adopt.text"], #plan.items, goal()),
    })
    ns.Dialogs.Confirm("map.route.adopt.title", "map.route.adopt.ask", function()
      doAdopt(plan, #stops)
    end)
  end

  -- Points the arrow at the first stop that was not reached yet.
  function ctl.NextStop()
    local stops = currentStops()
    if #stops == 0 or not st.dest then
      return
    end
    local name = goal()
    local WP = ns.Waypoints
    local byK = MRL.RouteWaypoints(WP.List(), name)
    local done = ctl.adopted.goal == name and ctl.adopted.ks or nil
    local stop = MRL.NextStop(stops, byK, done)
    if not stop then
      local any = false
      for _, s in ipairs(stops) do
        any = any or s.spec ~= nil
      end
      ns.Notify(L[any and "map.route.next.done" or "map.route.next.none"], "info")
      return
    end
    local wp, status = WP.Set({
      map = stop.spec.map,
      x = stop.spec.x,
      y = stop.spec.y,
      title = MRL.Title(name, stop.k, #stops),
      source = "map",
    })
    if wp then
      ctl.adopted = ctl.adopted.goal == name and ctl.adopted or { goal = name, ks = {} }
      if status == "added" then
        ctl.adopted.ks[stop.k] = true
      end
      ns.Notify(string.format(L["wp.activated"], wp.title), "info")
    elseif status == "full" then
      ns.Notify(string.format(L["wp.full"], WL.MAX), "warning")
    end
  end

  ctl.buttons = FL.ButtonRow(box, {
    {
      id = "adopt",
      label = "act.apply",
      icon = "check",
      variant = "primary",
      width = 200,
      tooltip = "map.route.adopt",
      tooltipText = "map.route.adopt.tip",
      onClick = ctl.Adopt,
    },
    {
      id = "next",
      label = "act.next",
      icon = "chevron-right",
      width = 170,
      tooltip = "map.route.next",
      tooltipText = "map.route.next.tip",
      onClick = ctl.NextStop,
    },
    {
      id = "copy",
      label = "act.text",
      icon = "copy",
      tooltip = "map.route.copy",
      width = 130,
      onClick = function()
        ns.Dialogs.Copy("map.route", MRL.Text(ctl.result, ctx.nameOf, ctx.share and ctx.share()))
      end,
    },
  })

  -- State -> screen ----------------------------------------------------------------------
  -- Shows a plain message instead of a route (nothing chosen, same place, no connection).
  function ctl.Message(text)
    ctl.routes, ctl.result = {}, nil
    ctx.route.SetRoute(nil)
    W.SetText(msg, nil, text)
    ctl.fill()
  end

  -- Takes a TL.Route result (nil when start or goal is missing). key names the pair; another
  -- pair starts on the fastest route again.
  function ctl.Set(result, key)
    if key ~= ctl.key then
      ctl.key = key
      st.alt = 1
    end
    ctl.result = result
    ctl.routes = MRL.Routes(result)
    if #ctl.routes == 0 then
      local text = L["map.route.pick"]
      if result and result.status == "same" then
        text = L["map.route.same"]
      elseif result and result.leg and result.legs > 1 then
        text = string.format(L["map.route.noneLeg"], result.leg, ctx.nameOf(result.from), ctx.nameOf(result.to))
      elseif result then
        text = L["map.route.none"]
      end
      ctl.Message(text)
      return
    end
    st.alt = math.max(1, math.min(st.alt or 1, #ctl.routes))
    ctx.route.SetRoute(ctl.routes[st.alt].steps)
    ctl.fill()
  end

  function ctl.fill()
    local routes = ctl.routes
    local route = routes[st.alt or 1]
    for i = 1, #routes do
      local tab = ctl.tabs[i]
      if not tab then
        tab = newTab()
        ctl.tabs[i] = tab
      end
      tab.index = i
      W.SetText(tab.label, nil, MRL.TabLabel(routes, i))
      W.SetColor(tab.label, i == st.alt and "accent" or "textSecondary")
      tab.bar:SetShown(i == st.alt)
      tab:SetShown(#routes > 1)
    end
    for i = #routes + 1, #ctl.tabs do
      ctl.tabs[i]:Hide()
    end
    local steps = route and route.steps or {}
    for i, step in ipairs(steps) do
      local row = ctl.rows[i]
      if not row then
        row = newRow()
        ctl.rows[i] = row
      end
      row.index, row.step = i, step
      W.SetText(row.title, nil, string.format(L["map.route.leg"], i, ctx.nameOf(step.from), ctx.nameOf(step.to)))
      W.SetText(row.sub, nil, MRL.StepSub(step))
      W.SetText(row.dur, nil, TL.FormatDuration(step.sec))
      ctl.PaintRow(row)
    end
    for i = #steps + 1, #ctl.rows do
      ctl.rows[i].step = nil
      ctl.rows[i]:Hide()
    end
    ctl.headAt = {}
    local parts = route and route.parts
    local heads = parts and #parts > 1 and #parts or 0
    for n = 1, heads do
      local head = ctl.heads[n]
      if not head then
        head = newHead()
        ctl.heads[n] = head
      end
      head.part = parts[n]
      W.SetText(head.title, nil, MRL.PartTitle(parts[n], ctx.nameOf))
      W.SetText(head.dur, nil, TL.FormatDuration(parts[n].totalSec))
      ctl.headAt[parts[n].first] = head
    end
    for n = heads + 1, #ctl.heads do
      ctl.heads[n].part = nil
      ctl.heads[n]:Hide()
    end
    if route then
      W.SetText(total, nil, TL.FormatDuration(route.totalSec))
      W.SetText(meta, nil, string.format(L["map.route.legs"], #steps))
    end
    ctl.buttons:SetItemEnabled("adopt", route ~= nil)
    ctl.buttons:SetItemEnabled("next", route ~= nil)
    ctl.buttons:SetItemEnabled("copy", route ~= nil)
  end

  -- Layout -------------------------------------------------------------------------------
  function box:fgGridLayout(width)
    local routes = ctl.routes
    local has = #routes > 0
    msg:SetShown(not has)
    total:SetShown(has)
    meta:SetShown(has)
    note:SetShown(has)
    capped:SetShown(has and ctx.route.Capped())
    ctl.buttons:SetShown(has)
    for i = #routes + 1, #ctl.tabs do
      ctl.tabs[i]:Hide()
    end
    if not has then
      msg:ClearAllPoints()
      msg:SetPoint("TOPLEFT", self, "TOPLEFT")
      msg:SetWidth(width)
      for _, row in ipairs(ctl.rows) do
        row:Hide()
      end
      for _, head in ipairs(ctl.heads) do
        head:Hide()
      end
      local h = math.ceil(msg:GetStringHeight())
      self:SetHeight(h)
      return h
    end
    total:ClearAllPoints()
    total:SetPoint("TOPLEFT", self, "TOPLEFT")
    local y = math.ceil(total:GetStringHeight()) + 2
    meta:ClearAllPoints()
    meta:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    y = y + math.ceil(meta:GetStringHeight()) + 8
    -- Tabs wrap like a button row; with a single route there is nothing to choose.
    if #routes > 1 then
      local x = 0
      for i = 1, #routes do
        local tab = ctl.tabs[i]
        local w = math.min(width, math.ceil(tab.label:GetStringWidth()) + 24)
        if x > 0 and x + w > width then
          x, y = 0, y + TAB_H + 2
        end
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
        tab:SetSize(w, TAB_H)
        tab:Show()
        x = x + w + 4
      end
      y = y + TAB_H + 8
    end
    local textW = math.max(40, width - SWATCH_W - 12 - DUR_W - 14)
    for _, row in ipairs(ctl.rows) do
      local head = row.step and ctl.headAt[row.index]
      if head then
        head.title:ClearAllPoints()
        head.title:SetPoint("TOPLEFT", head, "TOPLEFT", 4, -6)
        head.title:SetWidth(math.max(40, width - DUR_W - 20))
        local hh = math.max(ROW_MIN - 4, 6 + math.ceil(head.title:GetStringHeight()) + 6)
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        head:SetSize(width, hh)
        head:Show()
        y = y + hh
      end
      if row.step then
        row.title:ClearAllPoints()
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", SWATCH_W + 14, -6)
        row.title:SetWidth(textW)
        row.sub:ClearAllPoints()
        row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
        row.sub:SetWidth(textW)
        local h =
          math.max(ROW_MIN, 6 + math.ceil(row.title:GetStringHeight()) + 2 + math.ceil(row.sub:GetStringHeight()) + 6)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        row:SetSize(width, h)
        row:Show()
        y = y + h
      end
    end
    y = y + 8
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    note:SetWidth(width)
    y = y + math.ceil(note:GetStringHeight()) + 6
    if capped:IsShown() then
      capped:ClearAllPoints()
      capped:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      capped:SetWidth(width)
      y = y + math.ceil(capped:GetStringHeight()) + 6
    end
    ctl.buttons:ClearAllPoints()
    ctl.buttons:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    ctl.buttons:SetWidth(width)
    y = y + ctl.buttons:fgGridLayout(width)
    self:SetHeight(y)
    return y
  end

  ns.On("FG_UI_REFRESHED", function()
    if ctl.result then
      ctl.fill()
    end
  end)
  return ctl
end
