-- The route card: the ordered list of stops with numbers, names and leg times (move up, move down, remove per
-- row, drag to reorder), the switches "optimize the order", "back to the start" and "use hearthstone", the total time, one line
-- per error and the buttons to start the journey, take the route as waypoints, clear it, swap start and goal and add the
-- active waypoint. It shows and
-- changes the shared plan (RoutePlan), so the panel at the world map and the Map & Route page are the
-- same route. The owner places the frame and calls f:Refresh(), which answers the height it needs.
--   local card = ns.RouteStopList.Create(parent, width)
--   card:Refresh() -> height
local _, ns = ...
local W, L, Theme, TL, RP = ns.W, ns.L, ns.Theme, ns.TravelLogic, ns.RoutePlan

ns.AddLocale("enUS", {
  ["wmr.start.here"] = "Start: your position",
  ["wmr.start.place"] = "Start: %s",
  ["wmr.start.reset"] = "My position",
  ["wmr.start.reset.tip"] = "Plan from where you stand again.",
  ["wmr.empty"] = "Hold {key:mapRoutePoint} and click the map to add points. The first is the start, the last is the goal.",
  ["wmr.here"] = "Start at my position",
  ["wmr.here.tip"] = "On: start where you stand. Off: the first point is the start.",
  ["wmr.optimize"] = "Optimize order",
  ["wmr.optimize.tip"] = "Visits the stops in the fastest order. The goal stays last.",
  ["wmr.optimize.saved"] = "Saves %s against your order.",
  ["wmr.return"] = "Back to start",
  ["wmr.return.tip"] = "Adds a last leg from the goal back to the start.",
  ["wmr.total"] = "Total %s",
  ["wmr.total.wait"] = "Total %s, %s of it waiting",
  ["wmr.hearth"] = "Use hearthstone",
  ["wmr.hearth.tip"] = "Plans the hearthstone as a connection when it is ready.",
  ["wmr.calc"] = "Calculate route",
  ["wmr.calc.tip"] = "Plans the route again, for example after you moved.",
  ["wmr.go"] = "Start route",
  ["wmr.go.tip"] = "The arrow leads you to every stop, step by step.",
  ["wmr.waypoints"] = "As waypoints",
  ["wmr.waypoints.tip"] = "Adds a waypoint for every stop that has a position.",
  ["wmr.clear"] = "Clear",
  ["wmr.clear.tip"] = "Removes all stops of the route.",
  ["wmr.row.auto"] = 'The order is chosen automatically. Switch off "Optimize order" to move stops.',
  ["wmr.row.drag"] = "Drag to change the order.",
  ["wmr.err.unknown"] = "%s is not a known place.",
  ["wmr.err.invalid"] = "%s is not a valid point.",
  ["wmr.err.unreachable"] = "No way to %s found, the stop is skipped.",
  ["wmr.err.toomany"] = "Too many stops, %s was left out.",
  ["wmr.err.goal"] = "There is no goal yet.",
  ["wmr.err.noroute"] = "No connection to the goal found. Change the options or the goal.",
})

ns.AddLocale("deDE", {
  ["wmr.start.here"] = "Start: deine Position",
  ["wmr.start.place"] = "Start: %s",
  ["wmr.start.reset"] = "Meine Position",
  ["wmr.start.reset.tip"] = "Wieder von deinem Standort aus planen.",
  ["wmr.empty"] = "Halte {key:mapRoutePoint} gedrückt und klicke auf die Karte, um Punkte zu setzen. Der erste ist der Start, der letzte das Ziel.",
  ["wmr.here"] = "Ab meiner Position",
  ["wmr.here.tip"] = "An: Start bei dir. Aus: der erste Punkt ist der Start.",
  ["wmr.optimize"] = "Reihenfolge optimieren",
  ["wmr.optimize.tip"] = "Besucht die Stopps in der schnellsten Reihenfolge. Das Ziel bleibt am Ende.",
  ["wmr.optimize.saved"] = "Spart %s gegenüber deiner Reihenfolge.",
  ["wmr.return"] = "Zurück zum Start",
  ["wmr.return.tip"] = "Fügt eine letzte Etappe vom Ziel zurück zum Start hinzu.",
  ["wmr.total"] = "Gesamt %s",
  ["wmr.total.wait"] = "Gesamt %s, davon %s Warten",
  ["wmr.hearth"] = "Ruhestein nutzen",
  ["wmr.hearth.tip"] = "Plant den Ruhestein als Verbindung ein, wenn er bereit ist.",
  ["wmr.calc"] = "Route berechnen",
  ["wmr.calc.tip"] = "Plant die Route neu, zum Beispiel nach einem Ortswechsel.",
  ["wmr.go"] = "Route starten",
  ["wmr.go.tip"] = "Der Pfeil führt dich Schritt für Schritt zu jedem Stopp.",
  ["wmr.waypoints"] = "Als Wegpunkte",
  ["wmr.waypoints.tip"] = "Legt für jeden Stopp mit Position einen Wegpunkt an.",
  ["wmr.clear"] = "Leeren",
  ["wmr.clear.tip"] = "Entfernt alle Stopps der Route.",
  ["wmr.row.auto"] = 'Die Reihenfolge wird automatisch gewählt. Schalte "Reihenfolge optimieren" aus, um Stopps zu verschieben.',
  ["wmr.row.drag"] = "Ziehen ändert die Reihenfolge.",
  ["wmr.err.unknown"] = "%s ist kein bekannter Ort.",
  ["wmr.err.invalid"] = "%s ist kein gültiger Punkt.",
  ["wmr.err.unreachable"] = "Kein Weg zu %s gefunden, der Stopp wird übersprungen.",
  ["wmr.err.toomany"] = "Zu viele Stopps, %s wurde weggelassen.",
  ["wmr.err.goal"] = "Es gibt noch kein Ziel.",
  ["wmr.err.noroute"] = "Keine Verbindung zum Ziel gefunden. Ändere die Optionen oder das Ziel.",
})

local RSL = {}
ns.RouteStopList = RSL

local ROW_H, BADGE, ICON, TIME_W, GAP = 28, 20, 24, 46, 4
local MAX_ERRORS = 4

local function badgeToken(row)
  if row.error and not row.goal then
    return "danger"
  end
  return row.goal and "danger" or "accent2"
end

-- The message of an error of the plan.
function RSL.ErrorText(e)
  local name = e.slug and RP.Name(e.slug) or "?"
  local key = "wmr.err." .. tostring(e.reason)
  if L[key] == key then
    key = "wmr.err.unreachable"
  end
  if e.reason == "goal" then
    return L[key]
  end
  return string.format(L[key], name)
end

function RSL.Create(parent, width)
  local f = CreateFrame("Frame", nil, parent)
  f:SetWidth(width)
  local rows = {}
  local drag

  local startText = W.Text(f, { role = "ui", color = "textSecondary" })
  local startReset = W.Action(f, {
    key = "wmr.start.reset",
    variant = "ghost",
    height = 24,
    width = 110,
    tooltip = "wmr.start.reset",
    tooltipText = "wmr.start.reset.tip",
    onClick = function()
      RP.SetStart(nil)
    end,
  })
  local empty = W.Text(f, { key = "wmr.empty", role = "ui", color = "textSecondary", wrap = true })
  local saved = W.Text(f, { role = "micro", color = "success", wrap = true })
  local total = W.Text(f, { role = "ui", color = "accent2", wrap = true })
  local errors = {}
  for i = 1, MAX_ERRORS do
    errors[i] = W.Text(f, { role = "micro", color = "danger", wrap = true })
  end

  local here = W.Checkbox(f, {
    key = "wmr.here",
    tooltip = "wmr.here",
    tooltipText = "wmr.here.tip",
    get = function()
      return RP.State().fromHere
    end,
    set = function(on)
      RP.SetOption("fromHere", on)
    end,
  })
  local optimize = W.Checkbox(f, {
    key = "wmr.optimize",
    tooltip = "wmr.optimize",
    tooltipText = "wmr.optimize.tip",
    get = function()
      return RP.State().optimize
    end,
    set = function(on)
      RP.SetOption("optimize", on)
    end,
  })
  local back = W.Checkbox(f, {
    key = "wmr.return",
    tooltip = "wmr.return",
    tooltipText = "wmr.return.tip",
    get = function()
      return RP.State().returnToStart
    end,
    set = function(on)
      RP.SetOption("returnToStart", on)
    end,
  })
  local hearth = W.Checkbox(f, {
    key = "wmr.hearth",
    tooltip = "wmr.hearth",
    tooltipText = "wmr.hearth.tip",
    get = function()
      return RP.State().hearth
    end,
    set = function(on)
      RP.SetOption("hearth", on)
    end,
  })
  local hearthNote = W.Text(f, { key = "wmr.hearth.unknown", role = "micro", color = "warning", wrap = true })
  local calc = W.Button(f, {
    key = "wmr.calc",
    width = width,
    height = 26,
    tooltip = "wmr.calc",
    tooltipText = "wmr.calc.tip",
    onClick = function()
      RP.Replan()
    end,
  })
  local go = W.Button(f, {
    key = "wmr.go",
    variant = "primary",
    width = width,
    height = 28,
    tooltip = "wmr.go",
    tooltipText = "wmr.go.tip",
    onClick = function()
      RP.Start()
    end,
  })
  local half = math.floor((width - GAP) / 2)
  local wps = W.Button(f, {
    key = "wmr.waypoints",
    width = half,
    height = 26,
    tooltip = "wmr.waypoints",
    tooltipText = "wmr.waypoints.tip",
    onClick = function()
      RP.AsWaypoints()
    end,
  })
  local clear = W.Button(f, {
    key = "wmr.clear",
    variant = "danger",
    width = half,
    height = 26,
    tooltip = "wmr.clear",
    tooltipText = "wmr.clear.tip",
    onClick = function()
      RP.Clear()
    end,
  })

  -- Rows -----------------------------------------------------------------------------------------------
  local swap = W.Button(f, {
    key = "wm.swap",
    width = half,
    height = 26,
    tooltip = "wm.swap",
    tooltipText = "wm.swap.tip",
    onClick = function()
      RP.Swap()
    end,
  })
  local addWaypoint = W.Button(f, {
    key = "wmr.addwp",
    width = half,
    height = 26,
    tooltip = "wmr.addwp",
    tooltipText = "wmr.addwp.tip",
    onClick = function()
      RP.AddWaypoint()
    end,
  })

  local function rowUnderCursor()
    local _, cy = GetCursorPosition()
    for _, row in ipairs(rows) do
      if row:IsShown() and row.index then
        local top, bottom = row:GetTop(), row:GetBottom()
        local s = row:GetEffectiveScale()
        if top and bottom and cy / s <= top and cy / s >= bottom then
          return row
        end
      end
    end
  end

  local function newRow()
    local row = CreateFrame("Frame", nil, f)
    row:EnableMouse(true)
    row:SetHeight(ROW_H)
    row:RegisterForDrag("LeftButton")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.badge = row:CreateTexture(nil, "ARTWORK")
    row.badge:SetSize(BADGE, BADGE)
    row.badge:SetPoint("LEFT", 2, 0)
    row.num = W.Text(row, { role = "micro", color = "bg", justify = "CENTER" })
    row.num:SetPoint("CENTER", row.badge, "CENTER")
    row.remove = W.Action(row, {
      icon = "close",
      size = ICON,
      tooltip = "wmr.menu.remove",
      onClick = function()
        RP.Remove(row.index)
      end,
    })
    row.remove:SetPoint("RIGHT", 0, 0)
    row.down = W.Action(row, {
      icon = "chevron-down",
      size = ICON,
      tooltip = "wmr.menu.down",
      onClick = function()
        RP.Move(row.index, 1)
      end,
    })
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -1, 0)
    row.up = W.Action(row, {
      icon = "chevron-up",
      size = ICON,
      tooltip = "wmr.menu.up",
      onClick = function()
        RP.Move(row.index, -1)
      end,
    })
    row.up:SetPoint("RIGHT", row.down, "LEFT", -1, 0)
    row.time = W.Text(row, { role = "micro", color = "textSecondary", justify = "RIGHT" })
    row.time:SetPoint("RIGHT", row.up, "LEFT", -GAP, 0)
    row.time:SetWidth(TIME_W)
    row.name = W.Text(row, { role = "ui", color = "text" })
    row.name:SetPoint("LEFT", row.badge, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.time, "LEFT", -GAP, 0)
    row:SetScript("OnDragStart", function(self)
      if RP.CanReorder() and #rows > 1 then
        drag = self.index
        self.bg:SetColorTexture(Theme.color("accent2", 0.25))
      end
    end)
    row:SetScript("OnDragStop", function(self)
      local from = drag
      drag = nil
      self.bg:SetColorTexture(Theme.color("surface2", 0.6))
      local target = rowUnderCursor()
      if from and target and target.index and target.index ~= from then
        RP.Reorder(from, target.index)
      end
    end)
    row:SetScript("OnEnter", function(self)
      if RP.CanReorder() then
        ns.ShowTooltip(self, self.fullName or "", L["wmr.row.drag"])
      else
        ns.ShowTooltip(self, self.fullName or "", L["wmr.row.auto"])
      end
    end)
    row:SetScript("OnLeave", ns.HideTooltip)
    ns.Bind(row, function(self)
      self.bg:SetColorTexture(Theme.color("surface2", 0.6))
    end)
    return row
  end

  local function paintRow(row, model, count, auto)
    row.index = model.index
    row.fullName = model.name
    row.badge:SetColorTexture(Theme.color(badgeToken(model)))
    W.SetText(row.num, nil, model.label)
    W.SetText(row.name, nil, model.name)
    W.SetText(row.time, nil, model.sec and TL.FormatDuration(model.sec) or "")
    local movable = not auto
    row.up:SetEnabled(movable and model.pos > 1)
    row.down:SetEnabled(movable and model.pos < count)
    row.up:SetAlpha(row.up:IsEnabled() and 1 or 0.35)
    row.down:SetAlpha(row.down:IsEnabled() and 1 or 0.35)
    row:Show()
  end

  -- Layout ---------------------------------------------------------------------------------------------
  -- A new width: the page column changes its width with the window.
  function f:Resize(w)
    w = math.max(120, math.floor(w))
    if w == width then
      return
    end
    width = w
    half = math.floor((width - GAP) / 2)
    f:SetWidth(width)
    go:SetWidth(width)
    calc:SetWidth(width)
    wps:SetWidth(half)
    clear:SetWidth(half)
    swap:SetWidth(half)
    addWaypoint:SetWidth(half)
  end

  function f:Refresh()
    local st = RP.State()
    local models = RP.Rows()
    local summary = RP.Summary()
    local y = 0
    local function place(frame, h, gap)
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      y = y + h + (gap or GAP)
    end

    local resettable = st.fromHere and st.start ~= nil
    if st.start then
      W.SetText(startText, nil, string.format(L["wmr.start.place"], RP.Name(st.start)))
    elseif st.fromHere then
      W.SetText(startText, "wmr.start.here")
    else
      W.SetText(startText, nil, string.format(L["wmr.start.place"], L["map.none"]))
    end
    startText:ClearAllPoints()
    startText:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y - 4)
    startText:SetPoint("RIGHT", f, "RIGHT", resettable and -114 or 0, 0)
    startReset:ClearAllPoints()
    startReset:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
    startReset:SetShown(resettable)
    y = y + 26

    local auto = not RP.CanReorder()
    for i, model in ipairs(models) do
      model.pos = i
      local row = rows[i]
      if not row then
        row = newRow()
        rows[i] = row
      end
      paintRow(row, model, #models, auto)
      row:SetWidth(width)
      place(row, ROW_H, 2)
    end
    for i = #models + 1, #rows do
      rows[i].index = nil
      rows[i]:Hide()
    end

    empty:SetShown(#models == 0)
    if #models == 0 then
      empty:ClearAllPoints()
      empty:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      y = y + W.FitLabel(empty, width) + 8
    end

    y = y + 4
    local hasStops = #models > 1
    optimize:SetShown(#models > 0)
    back:SetShown(#models > 0)
    hearth:SetShown(#models > 0)
    for _, box in ipairs({ here, optimize, back, hearth }) do
      if box:IsShown() or box == here then
        box:SetWidth(width)
        local h = math.max(24, box:fgGridLayout(width))
        box:SetHeight(h)
        place(box, h, 2)
        box.Refresh()
      end
    end
    hearthNote:SetShown(false)
    if #models > 0 and st.hearth and not RP.Hearth() then
      hearthNote:ClearAllPoints()
      hearthNote:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      hearthNote:Show()
      y = y + W.FitLabel(hearthNote, width) + GAP
    end
    saved:SetShown(false)
    if summary.optimized and summary.saved > 0 and hasStops then
      W.SetText(saved, nil, string.format(L["wmr.optimize.saved"], TL.FormatDuration(summary.saved)))
      saved:ClearAllPoints()
      saved:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      saved:Show()
      y = y + W.FitLabel(saved, width) + GAP
    end

    total:SetShown(false)
    local plan = RP.Plan()
    local ok = plan and plan.status ~= "unreachable" and summary.totalSec > 0
    if ok then
      local text = summary.waitSec > 0
          and string.format(
            L["wmr.total.wait"],
            TL.FormatDuration(summary.totalSec),
            TL.FormatDuration(summary.waitSec)
          )
        or string.format(L["wmr.total"], TL.FormatDuration(summary.totalSec))
      W.SetText(total, nil, text)
      total:ClearAllPoints()
      total:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      total:Show()
      y = y + W.FitLabel(total, width) + GAP
    end

    local lines = {}
    for _, e in ipairs(summary.errors) do
      lines[#lines + 1] = RSL.ErrorText(e)
    end
    local why = RP.Why()
    if why == "start" then
      lines[#lines + 1] = L["wmr.noStart"]
    elseif plan and plan.status == "unreachable" and #summary.errors == 0 then
      lines[#lines + 1] = L["wmr.err.noroute"]
    end
    for i = 1, MAX_ERRORS do
      local line = errors[i]
      if lines[i] then
        W.SetText(line, nil, lines[i])
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        line:Show()
        y = y + W.FitLabel(line, width) + 2
      else
        line:Hide()
      end
    end

    y = y + 4
    local canGo = ok and plan.targets and #plan.targets > 0
    calc:ClearAllPoints()
    calc:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    calc:SetEnabled(#models > 0)
    y = y + 26 + GAP
    place(go, 28, GAP)
    go:SetEnabled(canGo == true)
    go:SetAlpha(canGo and 1 or 0.5)
    wps:ClearAllPoints()
    wps:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    clear:ClearAllPoints()
    clear:SetPoint("TOPLEFT", f, "TOPLEFT", half + GAP, -y)
    wps:SetEnabled(#models > 0)
    clear:SetEnabled(#models > 0 or st.start ~= nil)
    y = y + 26 + GAP
    swap:ClearAllPoints()
    swap:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    addWaypoint:ClearAllPoints()
    addWaypoint:SetPoint("TOPLEFT", f, "TOPLEFT", half + GAP, -y)
    swap:SetEnabled(#models > 0)
    y = y + 26
    f:SetHeight(y)
    return y
  end

  f.rows = rows
  ns.On("FG_ROUTEPLAN_CHANGED", function()
    if f:IsVisible() then
      f:Refresh()
      if f.onResize then
        f.onResize(f:GetHeight())
      end
    end
  end)
  return f
end
