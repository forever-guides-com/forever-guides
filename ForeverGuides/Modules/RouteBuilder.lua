-- Route recorder: a small free-floating window to record your own route as a
-- list of waypoints (current player position), reorder them, mark them on the
-- world map and export them as text. Waypoints live in ns.db.routeBuilder,
-- window geometry in ns.db.frames.routeBuilder (same scheme as the notes).
local _, ns = ...
local W, L, Theme, U, K = ns.W, ns.L, ns.Theme, ns.U, ns.PageKit

local RB = {}
ns.RouteBuilder = RB

local HEAD_H = 22
local MIN_W, MIN_H, MAX_W, MAX_H = 320, 280, 640, 800
local DEFAULT_W, DEFAULT_H = 340, 400
local MAX_POINTS = 100
local MAX_NAME = 40

ns.AddLocale("enUS", {
  ["rb.title"] = "Route recorder",
  ["rb.close"] = "Close route window",
  ["rb.namePlaceholder"] = "Waypoint name (optional)",
  ["rb.save"] = "Save position",
  ["rb.saveTip"] = "Saves your position as a waypoint.\nEnter in the name field works too.",
  ["rb.done"] = "Done",
  ["rb.doneTip"] = "Finishes the route and opens the export text.",
  ["rb.clear"] = "Clear",
  ["rb.clear.title"] = "Clear route",
  ["rb.clear.text"] = "Delete all waypoints of this route?\nThis is permanent.",
  ["rb.noPosition"] = "No position here (instance or no map data).",
  ["rb.full"] = "Route full (%d waypoints), delete some first.",
  ["rb.saved"] = "Waypoint %d saved: %s",
  ["rb.doneEmpty"] = "Save at least one waypoint first.",
  ["rb.summary.recording"] = "Recording: %d waypoint(s) in %d zone(s)",
  ["rb.summary.done"] = "Finished: %d waypoint(s) in %d zone(s)",
  ["rb.hint"] = "Click a waypoint to mark it on the world map.",
  ["rb.empty"] = "No waypoints: stand somewhere, then Save position.",
  ["rb.up"] = "Move up",
  ["rb.down"] = "Move down",
  ["rb.delete"] = "Delete waypoint",
  ["rb.grip"] = "Drag to resize",
  ["rb.export.title"] = "Route export",
  ["rb.export.hint"] = "One line per waypoint, then /way commands.",
})

ns.AddLocale("deDE", {
  ["rb.title"] = "Routen-Aufzeichnung",
  ["rb.close"] = "Routenfenster schließen",
  ["rb.namePlaceholder"] = "Wegpunkt-Name (optional)",
  ["rb.save"] = "Position speichern",
  ["rb.saveTip"] = "Speichert deine Position als Wegpunkt.\nEnter im Namensfeld geht auch.",
  ["rb.done"] = "Fertig",
  ["rb.doneTip"] = "Schließt die Route ab und öffnet den Exporttext.",
  ["rb.clear"] = "Leeren",
  ["rb.clear.title"] = "Route leeren",
  ["rb.clear.text"] = "Alle Wegpunkte dieser Route löschen?\nDas ist endgültig.",
  ["rb.noPosition"] = "Keine Position hier (Instanz oder keine Kartendaten).",
  ["rb.full"] = "Route voll (%d Wegpunkte), lösche zuerst einige.",
  ["rb.saved"] = "Wegpunkt %d gespeichert: %s",
  ["rb.doneEmpty"] = "Speichere zuerst mindestens einen Wegpunkt.",
  ["rb.summary.recording"] = "Aufzeichnung läuft: %d Wegpunkt(e) in %d Zone(n)",
  ["rb.summary.done"] = "Fertig: %d Wegpunkt(e) in %d Zone(n)",
  ["rb.hint"] = "Wegpunkt anklicken: auf der Weltkarte markieren.",
  ["rb.empty"] = "Keine Wegpunkte: stell dich hin, dann Position speichern.",
  ["rb.up"] = "Nach oben",
  ["rb.down"] = "Nach unten",
  ["rb.delete"] = "Wegpunkt löschen",
  ["rb.grip"] = "Ziehen, um die Größe zu ändern",
  ["rb.export.title"] = "Route exportieren",
  ["rb.export.hint"] = "Eine Zeile je Wegpunkt, danach /way-Befehle.",
})

-- Saved data -------------------------------------------------------------------

local function cleanName(text)
  if type(text) ~= "string" then
    return nil
  end
  -- Control characters and pipes would break chat/UI escape sequences.
  text = U.trim((text:gsub("[%c|]", " ")))
  if text == "" then
    return nil
  end
  return text:sub(1, MAX_NAME)
end

local function defaultName(p)
  return string.format("%s %.1f,%.1f", p.zone, p.x * 100, p.y * 100)
end

-- SavedVariables are untrusted: keep only well-formed waypoints.
local function cleanPoint(raw)
  if type(raw) ~= "table" or type(raw.x) ~= "number" or type(raw.y) ~= "number" then
    return nil
  end
  local p = {
    x = U.clamp(raw.x, 0, 1),
    y = U.clamp(raw.y, 0, 1),
    mapId = type(raw.mapId) == "number" and raw.mapId or nil,
    zone = type(raw.zone) == "string" and raw.zone:sub(1, 60) or "?",
  }
  p.name = cleanName(raw.name) or defaultName(p)
  return p
end

local checked
local function data()
  local d = ns.db.routeBuilder
  if type(d) ~= "table" then
    d = {}
    ns.db.routeBuilder = d
  end
  if checked ~= d then
    local clean = {}
    for _, raw in ipairs(type(d.points) == "table" and d.points or {}) do
      local p = cleanPoint(raw)
      if p and #clean < MAX_POINTS then
        clean[#clean + 1] = p
      end
    end
    d.points = clean
    d.done = d.done == true
    checked = d
  end
  return d
end

local function frameDb()
  local frames = ns.db.frames
  if type(frames.routeBuilder) ~= "table" then
    frames.routeBuilder = {}
  end
  return frames.routeBuilder
end

local function numberOr(value, fallback)
  return type(value) == "number" and value or fallback
end

-- Position capture ---------------------------------------------------------------

-- Returns a waypoint table or nil when the client has no position (instances,
-- loading screens, missing map API).
local function capture()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
    return nil
  end
  local okMap, mapId = pcall(C_Map.GetBestMapForUnit, "player")
  if not (okMap and type(mapId) == "number") then
    return nil
  end
  local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapId, "player")
  if not (okPos and pos and pos.GetXY) then
    return nil
  end
  local okXY, x, y = pcall(pos.GetXY, pos)
  if not (okXY and type(x) == "number" and type(y) == "number") or (x == 0 and y == 0) then
    return nil
  end
  local zone
  if C_Map.GetMapInfo then
    local okInfo, info = pcall(C_Map.GetMapInfo, mapId)
    zone = okInfo and type(info) == "table" and info.name or nil
  end
  if type(zone) ~= "string" or zone == "" then
    zone = GetZoneText and GetZoneText() or ""
  end
  if zone == "" then
    zone = "?"
  end
  return { x = U.clamp(x, 0, 1), y = U.clamp(y, 0, 1), mapId = mapId, zone = zone:sub(1, 60) }
end

-- Export ---------------------------------------------------------------------------

-- One "n. Zone (x, y)" line per waypoint (percent coordinates), then /way
-- commands. The #mapId form of /way targets the right zone for every waypoint.
function RB.BuildExport(points)
  local lines, ways = {}, {}
  for i, p in ipairs(points) do
    lines[#lines + 1] = string.format("%d. %s (%s)", i, p.zone, K.Coord(p.x, p.y))
    local target = p.mapId and ("#" .. p.mapId .. " ") or ""
    ways[#ways + 1] = string.format("/way %s%.1f %.1f %s", target, p.x * 100, p.y * 100, p.name)
  end
  return table.concat(lines, "\n") .. "\n\n" .. table.concat(ways, "\n")
end

local function zoneCount(points)
  local seen, n = {}, 0
  for _, p in ipairs(points) do
    local key = p.mapId or p.zone
    if not seen[key] then
      seen[key] = true
      n = n + 1
    end
  end
  return n
end

-- Window -----------------------------------------------------------------------------

local frame

local function applyScale(f)
  local scale = ns.db.settings and ns.db.settings.scale
  f:SetScale(U.clamp(numberOr(scale, 1), 0.5, 2))
end

local function place(f)
  local db = frameDb()
  f:SetSize(U.clamp(numberOr(db.w, DEFAULT_W), MIN_W, MAX_W), U.clamp(numberOr(db.h, DEFAULT_H), MIN_H, MAX_H))
  f:ClearAllPoints()
  local s = f:GetScale()
  if type(db.x) == "number" and type(db.y) == "number" then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
  end
end

local function savePosition(f)
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s, db = f:GetScale(), frameDb()
    db.x, db.y = left * s, top * s
  end
end

local function saveSize(f)
  local db = frameDb()
  db.w, db.h = f:GetWidth(), f:GetHeight()
end

local function refresh(scrollToEnd)
  if not frame then
    return
  end
  local d = data()
  local items = {}
  for i, p in ipairs(d.points) do
    items[i] = { index = i, point = p }
  end
  frame.list:SetData(items)
  if scrollToEnd then
    frame.list:ScrollBy(MAX_POINTS)
  end
  local count = #d.points
  if count == 0 then
    frame.status:SetText(Theme.hexText("textMuted", L["rb.empty"]))
  else
    local summary = string.format(L[d.done and "rb.summary.done" or "rb.summary.recording"], count, zoneCount(d.points))
    frame.status:SetText(Theme.hexText("accent2", summary) .. "\n" .. Theme.hexText("textMuted", L["rb.hint"]))
  end
  frame.done:SetEnabled(count > 0)
  frame.clear:SetEnabled(count > 0)
end

function RB.AddCurrent(name)
  local d = data()
  if #d.points >= MAX_POINTS then
    ns.Notify(string.format(L["rb.full"], MAX_POINTS), "warning")
    return false
  end
  local p = capture()
  if not p then
    ns.Notify(L["rb.noPosition"], "warning")
    return false
  end
  p.name = cleanName(name) or defaultName(p)
  d.points[#d.points + 1] = p
  d.done = false
  ns.Notify(string.format(L["rb.saved"], #d.points, p.name), "success")
  if frame then
    frame.name.edit:SetText("")
  end
  refresh(true)
  return true
end

local function move(index, delta)
  local pts = data().points
  local target = index + delta
  if pts[index] and pts[target] then
    pts[index], pts[target] = pts[target], pts[index]
    refresh()
  end
end

local function remove(index)
  table.remove(data().points, index)
  refresh()
end

function RB.Finish()
  local d = data()
  if #d.points == 0 then
    ns.Notify(L["rb.doneEmpty"], "info")
    return
  end
  d.done = true
  refresh()
  ns.Dialogs.Copy("rb.export.title", RB.BuildExport(d.points), "rb.export.hint")
end

function RB.Clear()
  if #data().points == 0 then
    return
  end
  ns.Dialogs.Confirm("rb.clear.title", "rb.clear.text", function()
    local d = data()
    d.points, d.done = {}, false
    refresh()
  end)
end

local function bindRow(item)
  local p, n = item.point, #data().points
  local actions = {
    {
      icon = "trash",
      tooltip = L["rb.delete"],
      onClick = function()
        remove(item.index)
      end,
    },
  }
  if item.index < n then
    actions[#actions + 1] = {
      icon = "chevron-down",
      tooltip = L["rb.down"],
      onClick = function()
        move(item.index, 1)
      end,
    }
  end
  if item.index > 1 then
    actions[#actions + 1] = {
      icon = "chevron-up",
      tooltip = L["rb.up"],
      onClick = function()
        move(item.index, -1)
      end,
    }
  end
  return {
    title = string.format("%d. %s", item.index, p.name),
    sub = string.format("%s · %s", p.zone, K.Coord(p.x, p.y)),
    actions = actions,
  }
end

local function create()
  local f = CreateFrame("Frame", "FGRouteBuilder", UIParent)
  -- Same strata as the note windows and popups so it opens above the main window.
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_W, MIN_H)
  end
  W.Fill(f, "bg", 0.95)
  local shell = ns.WindowShell.Attach(f, { title = "rb.title", titleHeight = HEAD_H, shadow = true })
  local bar = shell.titleBar
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function()
    f:StartMoving()
  end)
  bar:SetScript(
    "OnDragStop",
    ns.Wrap("route-move", function()
      f:StopMovingOrSizing()
      savePosition(f)
    end)
  )
  local close = W.Action(bar, { icon = "close", size = 18, tooltip = "rb.close" })
  close:SetPoint("RIGHT", -2, 0)
  close:SetScript(
    "OnClick",
    ns.Wrap("route-close", function()
      f:Hide()
    end)
  )
  local title = shell.titleText
  title:ClearAllPoints()
  title:SetPoint("LEFT", 8, 0)
  title:SetPoint("RIGHT", close, "LEFT", -4, 0)

  f.name = W.EditBox(f, {
    placeholder = "rb.namePlaceholder",
    height = 24,
    onEnter = function(text)
      RB.AddCurrent(text)
    end,
  })
  f.name:SetPoint("TOPLEFT", 8, -(HEAD_H + 6))
  f.name:SetPoint("TOPRIGHT", -8, -(HEAD_H + 6))
  f.name.edit:SetMaxLetters(MAX_NAME)

  f.save = W.Action(f, {
    label = "act.save",
    icon = "save",
    variant = "primary",
    width = 136,
    tooltip = "rb.save",
    tooltipText = "rb.saveTip",
    onClick = function()
      RB.AddCurrent(f.name.edit:GetText())
    end,
  })
  f.save:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -6)
  f.done = W.Action(f, {
    label = "act.done",
    icon = "check",
    width = 80,
    tooltip = "rb.done",
    tooltipText = "rb.doneTip",
    onClick = RB.Finish,
  })
  f.done:SetPoint("LEFT", f.save, "RIGHT", 4, 0)
  f.clear = W.Action(
    f,
    { label = "act.clear", icon = "trash", tooltip = "rb.clear", variant = "ghost", width = 80, onClick = RB.Clear }
  )
  f.clear:SetPoint("LEFT", f.done, "RIGHT", 4, 0)

  f.status = W.Text(f, { role = "micro", color = "textSecondary", wrap = true })
  f.status:SetPoint("TOPLEFT", f.save, "BOTTOMLEFT", 0, -6)
  f.status:SetPoint("RIGHT", f, "RIGHT", -8, 0)
  f.status:SetHeight(K.scaledHeight(40))

  f.list = K.NewList(f, {
    rowHeight = 38,
    bind = bindRow,
    onClick = function(item)
      K.ShowOnMap(item.point.mapId, item.point.x, item.point.y, item.point.name)
    end,
  })
  f.list:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 0, -4)
  f.list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 16)

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  local gripTex = grip:CreateTexture(nil, "OVERLAY")
  gripTex:SetAllPoints()
  gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript(
    "OnMouseUp",
    ns.Wrap("route-size", function()
      f:StopMovingOrSizing()
      saveSize(f)
      savePosition(f)
    end)
  )
  grip:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["rb.grip"])
  end)
  grip:SetScript("OnLeave", ns.HideTooltip)

  f:SetScript(
    "OnShow",
    ns.Wrap("route-show", function()
      frameDb().shown = true
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("route-hide", function()
      frameDb().shown = false
    end)
  )
  f:Hide()
  return f
end

-- Public API ---------------------------------------------------------------------------

function RB.IsShown()
  return frame ~= nil and frame:IsShown()
end

function RB.Show()
  if not ns.db then
    return
  end
  if not frame then
    frame = create()
  end
  applyScale(frame)
  place(frame)
  frame:Show()
  refresh()
end

function RB.Hide()
  if frame then
    frame:Hide()
  end
end

function RB.Toggle()
  if RB.IsShown() then
    RB.Hide()
  else
    RB.Show()
  end
end

ns.On("FG_UI_REFRESHED", function()
  if frame and frame:IsShown() then
    applyScale(frame)
    place(frame)
    refresh()
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    savePosition(frame)
    saveSize(frame)
  end
end)
ns.On("PLAYER_LOGIN", function()
  if ns.db and ns.db.frames and frameDb().shown == true then
    RB.Show()
  end
end)
