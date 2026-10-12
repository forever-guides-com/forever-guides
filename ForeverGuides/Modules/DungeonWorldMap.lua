-- M inside a dungeon: our dungeon map (Modules/DungeonMapView.lua) in an opaque panel over Blizzard's
-- world map. Inside instances the client gives no position and no map ID (addon restriction "map"), and
-- there are no dungeon UiMaps, so WorldMapFrame:SetMapID is never called here; Blizzard's map just stays
-- underneath and a button (or a right click on the dungeon map) switches back to it.
--
-- The area follows the sub-zone text (ZONE_CHANGED, ZONE_CHANGED_INDOORS, ZONE_CHANGED_NEW_AREA, matching in
-- Modules/DungeonAreaLogic.lua), also while the map is open. An empty or unknown text keeps the map. Which
-- floor an area belongs to is learned from the player's own floor picks (ns.db.dungeonAreas), a click "I am
-- here" adds a rough centre of the area that the map shows as a marker (an approximate marker, no position).
--
-- Two tabs: the map and the bosses of the instance (Modules/DungeonBossTab.lua), the same list on every floor
-- and also when the instance has no map yet. The tab stays while the floors change and starts on the map again
-- with the next dungeon visit.
--
-- Nothing is written into Blizzard tables: HookScript on the map, our own frames as children of it. The
-- panel is built out of combat only. Every entry point runs protected; an error removes the panel, the
-- world map stays as it is and the error is reported once.
local _, ns = ...
local W, L, A, DMV, FL = ns.W, ns.L, ns.DungeonAreaLogic, ns.DungeonMapView, ns.FlowLayout
local DBT, BP = ns.DungeonBossTab, ns.BossProgress

ns.AddLocale("enUS", {
  ["dwm.btn.world"] = "World map",
  ["dwm.btn.dungeon"] = "Dungeon map",
  ["dwm.btn.tipTitle"] = "Dungeon map",
  ["dwm.btn.tip"] = "Switches between the dungeon map and the world map of the game. A right click on the dungeon map does the same.",
  ["dwm.area"] = "Area: %s",
  ["dwm.area.keep"] = "Area: %s (no map stored for it, the map stays)",
  ["dwm.area.none"] = "Area: between two areas, the map stays",
  ["dwm.learned"] = "Learned: %s belongs to floor %d.",
  ["dwm.marker.title"] = "You are roughly here",
  ["dwm.marker.text"] = "Rough centre of the area %s. The game gives no position inside dungeons, this is not your location.",
  ["dwm.marker.status"] = "The marker shows the rough centre of the area, not your position.",
  ["dwm.here"] = "I am here",
  ["dwm.here.cancel"] = "Cancel",
  ["dwm.here.tip"] = "Marks the rough centre of your current area on the map and remembers the floor. Needs a named area and a map with a click on it.",
  ["dwm.here.hint"] = "Click the map where you are. The marker is only roughly right.",
  ["dwm.export"] = "Learned areas",
  ["dwm.export.tip"] = "Shows everything learned about the areas as text you can copy.",
  ["dwm.export.title"] = "Learned dungeon areas",
  ["dwm.export.hint"] = "One line per area: ID | dungeon | area | floor | x | y. Copy it for the data upkeep.",
  ["dwm.export.none"] = "Nothing learned yet.",
  ["dwm.reset"] = "Reset",
  ["dwm.reset.tip"] = "Forgets what was learned about the areas of this dungeon.",
  ["dwm.reset.title"] = "Reset learned areas",
  ["dwm.reset.text"] = "Delete everything the addon learned about the areas of this dungeon?",
  ["dwm.error"] = "The dungeon map was switched off after an error. The world map works as usual.",
  ["dwm.set"] = "Dungeon map in the world map inside dungeons",
  ["dwm.tab.map"] = "Map",
  ["dwm.tab.bosses"] = "Bosses",
  ["dwm.bosses.reset"] = "Reset boss progress",
  ["dwm.bosses.resetTip"] = "Forgets the saved boss progress of this instance, a new run starts without defeated bosses. Not possible while a lockout of the game lists defeated bosses.",
})
ns.AddLocale("deDE", {
  ["dwm.btn.world"] = "Weltkarte",
  ["dwm.btn.dungeon"] = "Dungeonkarte",
  ["dwm.btn.tipTitle"] = "Dungeonkarte",
  ["dwm.btn.tip"] = "Wechselt zwischen der Dungeonkarte und der Weltkarte des Spiels. Ein Rechtsklick auf die Dungeonkarte tut dasselbe.",
  ["dwm.area"] = "Gebiet: %s",
  ["dwm.area.keep"] = "Gebiet: %s (keine Karte hinterlegt, die Karte bleibt)",
  ["dwm.area.none"] = "Gebiet: zwischen zwei Gebieten, die Karte bleibt",
  ["dwm.learned"] = "Gelernt: %s gehört zu Ebene %d.",
  ["dwm.marker.title"] = "Du bist ungefähr hier",
  ["dwm.marker.text"] = "Ungefähre Mitte des Gebiets %s. Das Spiel liefert in Dungeons keine Position, das ist nicht dein Standort.",
  ["dwm.marker.status"] = "Der Marker zeigt die ungefähre Mitte des Gebiets, nicht deine Position.",
  ["dwm.here"] = "Ich bin hier",
  ["dwm.here.cancel"] = "Abbrechen",
  ["dwm.here.tip"] = "Markiert die ungefähre Mitte deines aktuellen Gebiets auf der Karte und merkt sich die Ebene. Braucht ein benanntes Gebiet und einen Klick auf die Karte.",
  ["dwm.here.hint"] = "Klicke auf die Karte, wo du bist. Der Marker stimmt nur ungefähr.",
  ["dwm.export"] = "Gelernte Gebiete",
  ["dwm.export.tip"] = "Zeigt alles, was über die Gebiete gelernt wurde, als Text zum Kopieren.",
  ["dwm.export.title"] = "Gelernte Dungeon-Gebiete",
  ["dwm.export.hint"] = "Eine Zeile je Gebiet: ID | Dungeon | Gebiet | Ebene | x | y. Kopiere sie für die Daten-Pflege.",
  ["dwm.export.none"] = "Noch nichts gelernt.",
  ["dwm.reset"] = "Zurücksetzen",
  ["dwm.reset.tip"] = "Vergisst, was über die Gebiete dieses Dungeons gelernt wurde.",
  ["dwm.reset.title"] = "Gelernte Gebiete zurücksetzen",
  ["dwm.reset.text"] = "Alles löschen, was das Addon über die Gebiete dieses Dungeons gelernt hat?",
  ["dwm.error"] = "Die Dungeonkarte wurde nach einem Fehler abgeschaltet. Die Weltkarte funktioniert wie gewohnt.",
  ["dwm.set"] = "Dungeonkarte in der Weltkarte innerhalb von Dungeons",
  ["dwm.tab.map"] = "Karte",
  ["dwm.tab.bosses"] = "Bosse",
  ["dwm.bosses.reset"] = "Boss-Fortschritt zurücksetzen",
  ["dwm.bosses.resetTip"] = "Vergisst den gespeicherten Boss-Fortschritt dieser Instanz, ein neuer Durchlauf beginnt ohne besiegte Bosse. Nicht möglich, solange eine Sperre des Spiels besiegte Bosse führt.",
})

local DWM = {}
ns.DungeonWorldMap = DWM

local PAD, GAP = 10, 8
-- Blizzard's round map icon sits over the top left corner of the panel, the title starts right of it.
local TITLE_INSET = 28
local LEVEL, LEVEL_TOGGLE, LEVEL_CAP = 3000, 3010, 9990 -- above Blizzard's overlay frames and our world map controls
local TOGGLE_MIN_W = 110

-- Visit state: mode is what the player chose during this dungeon visit ("dungeon" or "world"), tab the shown
-- tab of the panel ("map" or "bosses"); the visit ends when the instance ID changes or the player leaves.
local S = { mode = "dungeon", tab = "map", broken = false, reported = false }
local map, container, attached

-- Blizzard access ----------------------------------------------------------------------------------

local function worldMap()
  local frame = rawget(_G, "WorldMapFrame")
  if type(frame) == "table" and type(frame.HookScript) == "function" then
    return frame
  end
end

local function field(object, name)
  local ok, value = pcall(function()
    return object[name]
  end)
  return ok and value or nil
end

local function isShown(frame)
  local ok, value = pcall(frame.IsShown, frame)
  return ok and value == true
end

local function level(extra)
  local ok, base = pcall(map.GetFrameLevel, map)
  return math.min((ok and type(base) == "number" and base or 1) + extra, LEVEL_CAP)
end

local function text(fn)
  local ok, value = pcall(fn)
  return ok and type(value) == "string" and value or ""
end

local function subZone()
  return text(GetSubZoneText or function() end)
end

local function zoneText()
  return text(GetZoneText or function() end)
end

local function enabled()
  local s = ns.db and ns.db.settings
  return not s or s.dungeonWorldMap ~= false
end

-- Data --------------------------------------------------------------------------------------------

local function maps()
  return ns.Data.DungeonAssets and ns.Data.DungeonAssets.maps or {}
end

-- The Data.Instances entry and the instance ID of the dungeon the player is in, nil elsewhere (also when
-- the client refuses the call).
local function here()
  local ok, inst, id = pcall(function()
    local entry = DMV.Current()
    if not entry then
      return nil
    end
    local _, _, _, _, _, _, _, instanceId = GetInstanceInfo()
    return entry, type(instanceId) == "number" and instanceId or entry.id
  end)
  if ok and inst then
    return inst, id
  end
end

-- Number of floors of the map data, 0 when the instance has no map (the view then shows "coming soon").
local function floorsOf(inst)
  local entry = maps()[inst.n.en]
  return entry and entry.floors and #entry.floors or 0
end

local function store()
  local db = ns.db
  if type(db) ~= "table" then
    return { v = A.SCHEMA, items = {} }
  end
  if not S.cleaned then
    db.dungeonAreas = A.Clean(db.dungeonAreas)
    S.cleaned = true
  end
  return db.dungeonAreas
end

local function instanceName(id)
  for _, inst in ipairs(ns.Data.Instances or {}) do
    if inst.id == id then
      return inst.n and inst.n.en or tostring(id)
    end
  end
  return tostring(id)
end

-- Panel ---------------------------------------------------------------------------------------------

local function statusText()
  if S.placing then
    return L["dwm.here.hint"]
  end
  local lines, r = {}, S.res
  if S.text == nil or S.text == "" then
    lines[1] = L["dwm.area.none"]
  elseif r and r.floor then
    lines[1] = string.format(L["dwm.area"], S.text)
  else
    lines[1] = string.format(L["dwm.area.keep"], S.text)
  end
  if S.note then
    lines[#lines + 1] = S.note
  end
  if S.markerOn then
    lines[#lines + 1] = L["dwm.marker.status"]
  end
  return table.concat(lines, "\n")
end

local function paintStatus()
  if S.status then
    W.SetText(S.status, nil, statusText())
  end
end

local function paintTitle()
  if S.title and S.inst then
    W.SetText(S.title, nil, ns.T(S.inst.n))
  end
end

local function paintToggle()
  local t = S.toggle
  if not t then
    return
  end
  local dungeon = S.mode == "dungeon"
  W.SetText(t.label, dungeon and "dwm.btn.world" or "dwm.btn.dungeon")
  t:SetWidth(math.max(TOGGLE_MIN_W, math.ceil(t.label:GetStringWidth()) + 24))
  t:ClearAllPoints()
  if dungeon then
    t:SetPoint("TOPRIGHT", S.panel, "TOPRIGHT", -PAD, -PAD)
  else
    -- Blizzard's own buttons sit at the top and right edge of its map, the bottom middle is free.
    t:SetPoint("BOTTOM", container, "BOTTOM", 0, 12)
  end
end

local function placeableHere()
  return S.hasMap and S.inst ~= nil and not S.view.state.edit and A.CanLearn(subZone(), S.inst.n, zoneText())
end

local function refreshFoot()
  if not S.foot then
    return
  end
  S.foot:SetItemText("here", S.placing and "dwm.here.cancel" or "dwm.here")
  S.foot:Refresh()
end

-- Sets the width of a wrapping text and its height from the measured lines; returns the height.
local function fitText(fs, width)
  fs:SetWidth(width)
  local h = math.max(1, fs:GetStringHeight())
  fs:SetHeight(h)
  return h
end

-- Fits the dungeon map into the room the header and the foot leave: the widget is as wide as the room
-- allows (at most DMV.MAX_W) and takes the room as its height limit, the view fits its picture into it.
local function fitView(inner, avail)
  local view = S.view
  view.maxHeight = math.max(1, avail)
  local width = math.min(inner, DMV.MAX_W)
  view:fgGridLayout(width)
  view:SetWidth(width)
  return width
end

-- The boss tab takes the room between the tabs and its foot, as wide as the map gets at most.
local function layoutBosses(inner, top)
  local p = S.panel
  local footH = S.bossFoot:SetWidthAvailable(inner)
  S.bossFoot:SetHeight(math.max(1, footH))
  S.bossFoot:ClearAllPoints()
  S.bossFoot:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", PAD, PAD)
  S.bossFoot:SetWidth(inner)
  local width = math.min(inner, DMV.MAX_W)
  S.bosses:ClearAllPoints()
  S.bosses:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + math.floor((inner - width) / 2), -top)
  S.bosses:Layout(width, math.max(1, p:GetHeight() - top - footH - PAD - GAP))
end

function DWM.Layout()
  local p = S.panel
  if not (p and p:IsShown() and S.inst) then
    return
  end
  local w, h = p:GetWidth(), p:GetHeight()
  if not (w and h and w > 0 and h > 0) then
    return
  end
  local inner = math.max(1, w - PAD * 2)
  local toggleW = S.toggle:GetWidth()
  local titleH = fitText(S.title, math.max(1, inner - TITLE_INSET - toggleW - GAP))
  S.title:ClearAllPoints()
  S.title:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + TITLE_INSET, -PAD)
  local headH = math.max(titleH, S.toggle:GetHeight())
  S.tabs:ClearAllPoints()
  S.tabs:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(PAD + headH + 4))
  S.tabs:SetWidth(inner)
  local tabsBottom = PAD + headH + 4 + S.tabs:GetHeight() + GAP
  if S.tab == "bosses" then
    layoutBosses(inner, tabsBottom)
    return
  end
  local statusH = fitText(S.status, inner)
  S.status:ClearAllPoints()
  S.status:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -tabsBottom)
  local top = tabsBottom + statusH + GAP
  local footH = S.foot:SetWidthAvailable(inner)
  S.foot:SetHeight(math.max(1, footH))
  S.foot:ClearAllPoints()
  S.foot:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", PAD, PAD)
  S.foot:SetWidth(inner)
  local avail = h - top - footH - PAD - GAP
  local width = fitView(inner, avail)
  S.view:ClearAllPoints()
  S.view:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + math.floor((inner - width) / 2), -top)
end

-- Follows the sub-zone: the floor of the area, the marker of its centre. Empty or unknown text keeps both
-- the map and the floor, the marker goes (the player is not in a known area then).
function DWM.ApplyArea()
  if not S.inst then
    return
  end
  S.text = subZone()
  S.res = A.Resolve(S.instId, S.text, store())
  S.markerOn = false
  local r = S.res
  if S.hasMap then
    if r and r.floor and S.view.state.floor ~= r.floor then
      S.view:SetFloor(r.floor)
    end
    local point = r and r.point
    if point and (point.floor == nil or point.floor == S.view.state.floor) then
      S.markerOn = true
      S.view:SetMarker({
        x = point.x,
        y = point.y,
        floor = point.floor,
        title = L["dwm.marker.title"],
        text = string.format(L["dwm.marker.text"], r.name),
      })
    else
      S.view:SetMarker(nil)
    end
  end
  paintStatus()
  refreshFoot()
  DWM.Layout()
end

function DWM.SetMode(mode)
  S.mode = mode == "world" and "world" or "dungeon"
  S.placing = false
  if S.panel then
    S.panel:SetShown(S.mode == "dungeon")
  end
  paintToggle()
  paintStatus()
  refreshFoot()
  DWM.Layout()
end

-- Shows the parts of the chosen tab. The map widget and its foot belong to the map tab only.
local function paintTab()
  local bosses = S.tab == "bosses"
  S.view:SetShown(not bosses)
  S.status:SetShown(not bosses)
  S.foot:SetShown(not bosses)
  S.bosses:SetShown(bosses)
  S.bossFoot:SetShown(bosses)
end

function DWM.SetTab(id)
  S.tab, S.placing = id == "bosses" and "bosses" or "map", false
  if S.tabs and S.tabs.selected ~= S.tab then
    -- The tab strip calls back with the same id.
    S.tabs:Select(S.tab)
    return
  end
  paintTab()
  paintStatus()
  refreshFoot()
  DWM.Layout()
end

-- A floor the player picked by hand: the area they stand in belongs to it from now on.
local function onFloorPick(n)
  if not (S.inst and S.instId) then
    return
  end
  local name = subZone()
  if not A.CanLearn(name, S.inst.n, zoneText()) then
    return
  end
  if A.Learn(store(), S.instId, name, n) then
    S.res = A.Resolve(S.instId, name, store())
    S.note = string.format(L["dwm.learned"], name, n)
    paintStatus()
    refreshFoot()
    DWM.Layout()
  end
end

local function commitPoint(x, y)
  local name = subZone()
  if not (S.inst and A.CanLearn(name, S.inst.n, zoneText())) then
    return
  end
  local floor = S.view.state.floor
  if A.Learn(store(), S.instId, name, floor, x, y) then
    S.note = string.format(L["dwm.learned"], name, floor)
  end
  DWM.ApplyArea()
end

local function onMapClick(button, x, y)
  if button == "LeftButton" and S.placing then
    S.placing = false
    commitPoint(x, y)
    return true
  end
  if button == "RightButton" and not S.view.state.edit then
    DWM.SetMode("world")
    return true
  end
end

local function togglePlacing()
  S.placing = not S.placing and placeableHere() or false
  paintStatus()
  refreshFoot()
  DWM.Layout()
end

local function exportLearned()
  local out = A.Export(store(), instanceName)
  if out == "" then
    ns.Notify(L["dwm.export.none"], "info")
    return
  end
  ns.Dialogs.Copy("dwm.export.title", out, "dwm.export.hint")
end

local function resetLearned()
  ns.Dialogs.Confirm("dwm.reset.title", "dwm.reset.text", function()
    A.Forget(store(), S.instId)
    S.note = nil
    DWM.ApplyArea()
  end)
end

-- The reset button of the boss tab is for progress the player may reset: not while a lockout lists kills.
local function bossesResettable()
  local inst = S.inst
  local sum = inst and type(inst.id) == "number" and BP.Summary(inst.id) or nil
  return sum ~= nil and sum.killed > 0 and not BP.Locked(inst.id)
end

local function build()
  local p = CreateFrame("Frame", nil, map)
  S.panel = p
  p:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  p:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
  p:SetFrameLevel(level(LEVEL))
  W.Fill(p, "bg", 1)
  -- The panel takes every mouse event so nothing reaches Blizzard's canvas underneath.
  p:EnableMouse(true)
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function() end)
  p:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
      DWM.SetMode("world")
    end
  end)
  p:SetScript("OnSizeChanged", function()
    DWM.Run("dwm-size", DWM.Layout)
  end)

  S.title = W.Text(p, { role = "h3", color = "text", wrap = true })
  S.status = W.Text(p, { role = "ui", color = "textSecondary", wrap = true })
  S.tabs = W.Tabs(p, {
    tabs = { { id = "map", key = "dwm.tab.map" }, { id = "bosses", key = "dwm.tab.bosses" } },
    onSelect = function(id)
      DWM.Run("dwm-tab", DWM.SetTab, id)
    end,
  })
  S.bosses = DBT.Create(p)
  S.bossFoot = FL.ButtonRow(p, {
    {
      id = "reset",
      label = "act.reset",
      icon = "reset",
      tooltip = "dwm.bosses.reset",
      tooltipText = "dwm.bosses.resetTip",
      enabled = bossesResettable,
      onClick = function()
        if S.inst and S.inst.id then
          ns.BossReset.ConfirmReset(S.inst.id)
        end
      end,
    },
  })
  S.view = DMV.Create(p)
  S.view.onFloorPick = onFloorPick
  S.view.onMapClick = onMapClick
  S.view.onChange = DWM.Layout
  S.foot = FL.ButtonRow(p, {
    {
      id = "here",
      label = "act.here",
      icon = "marker",
      tooltip = "dwm.here",
      tooltipText = "dwm.here.tip",
      enabled = function()
        return S.placing or placeableHere()
      end,
      onClick = togglePlacing,
    },
    {
      id = "export",
      label = "act.export",
      icon = "export",
      tooltip = "dwm.export",
      tooltipText = "dwm.export.tip",
      enabled = function()
        return A.Count(store()) > 0
      end,
      onClick = exportLearned,
    },
    {
      id = "reset",
      label = "act.reset",
      icon = "reset",
      tooltip = "dwm.reset",
      tooltipText = "dwm.reset.tip",
      enabled = function()
        return S.instId ~= nil and A.Count(store(), S.instId) > 0
      end,
      onClick = resetLearned,
    },
  })
  ns.Bind(p, function()
    paintTitle()
    paintStatus()
  end)
  S.tabs:Select(S.tab)

  S.toggle = W.Button(map, {
    key = "dwm.btn.world",
    width = TOGGLE_MIN_W,
    tooltip = "dwm.btn.tipTitle",
    tooltipText = "dwm.btn.tip",
    onClick = function()
      DWM.Run("dwm-toggle", function()
        DWM.SetMode(S.mode == "dungeon" and "world" or "dungeon")
      end)
    end,
  })
  S.toggle:SetFrameLevel(level(LEVEL_TOGGLE))
end

-- Shows the instance in the panel: the map when the data has floors, else the view's "coming soon" note.
local function setup(inst, id)
  S.inst, S.instId, S.note, S.placing = inst, id, nil, false
  S.hasMap = floorsOf(inst) > 0
  S.view:SetInstance(inst.n.en)
  S.view:Show()
  S.bosses:SetInstance(inst)
  paintTitle()
end

-- Entry points ------------------------------------------------------------------------------------

local function hideParts()
  if S.panel then
    S.panel:Hide()
  end
  if S.toggle then
    S.toggle:Hide()
  end
end

-- Removes everything after an error: the map falls back to Blizzard's, a new dungeon visit tries again.
local function fail()
  S.broken = true
  hideParts()
  S.panel, S.toggle, S.view, S.title, S.status, S.foot = nil, nil, nil, nil, nil, nil
  S.tabs, S.bosses, S.bossFoot = nil, nil, nil
  S.inst, S.instId, S.placing = nil, nil, false
  if not S.reported then
    S.reported = true
    ns.Notify(L["dwm.error"], "warning")
  end
end

-- Runs fn protected; an error takes the panel down (Errors keeps the details).
function DWM.Run(context, fn, ...)
  local ok = ns.Safe(context, fn, ...)
  if not ok then
    fail()
  end
  return ok
end

local function present()
  -- Our frames hang on the map: while the client protects it, Show/Hide/SetPoint on them is blocked.
  if map and not ns.ProtectedAllowed(map) then
    return
  end
  if not (enabled() and attached and not S.broken) then
    hideParts()
    return
  end
  local inst, id = here()
  if not (inst and S.visit == id and isShown(map)) then
    hideParts()
    return
  end
  if not S.panel then
    -- Parenting new frames to the map is left for after the fight.
    if InCombatLockdown() then
      S.waiting = true
      return
    end
    build()
  end
  if S.instId ~= id or not S.inst then
    setup(inst, id)
  end
  S.toggle:Show()
  paintTab()
  DWM.ApplyArea()
  DWM.SetMode(S.mode)
end

function DWM.Refresh()
  DWM.Run("dwm-refresh", present)
end

-- The dungeon the player is in decides the visit: a new one starts on the dungeon map again.
local function sync()
  local inst, id = here()
  local visit = inst and id or nil
  if visit == S.visit then
    return
  end
  S.visit, S.mode, S.tab, S.placing, S.broken, S.note, S.waiting = visit, "dungeon", "map", false, false, nil, false
  S.instId, S.inst = nil, nil
  if S.view then
    S.view:SetInstance(nil)
  end
  hideParts()
  if S.tabs then
    S.tabs:Select("map")
  end
end

local function onWorld()
  sync()
  if attached and isShown(map) then
    DWM.Refresh()
  end
end

local function onZone()
  sync()
  if S.inst and S.panel then
    DWM.Run("dwm-zone", DWM.ApplyArea)
  end
end

-- Settings toggle: the map shows or drops the panel at once.
function DWM.Apply()
  if attached then
    DWM.Refresh()
  end
end

function DWM.Attach()
  if attached then
    return true
  end
  map = worldMap()
  if not map then
    return false
  end
  attached = true
  container = field(map, "ScrollContainer") or map
  pcall(map.HookScript, map, "OnShow", function()
    DWM.Run("dwm-show", function()
      sync()
      present()
    end)
  end)
  pcall(map.HookScript, map, "OnHide", function()
    S.placing = false
  end)
  return true
end

-- State for the tests.
function DWM.Parts()
  return S
end

ns.On("PLAYER_LOGIN", function()
  DWM.Attach()
  sync()
end)

-- Blizzard_WorldMap is load-on-demand on some clients.
ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_WorldMap" then
    DWM.Attach()
  end
end)

-- Progress changed (a kill, a reset): the boss tab and its button follow at once.
ns.On("FG_BOSS_PROGRESS", function()
  DWM.Run("dwm-boss", function()
    if S.bosses and S.inst then
      S.bosses:Refresh()
      S.bossFoot:Refresh()
      DWM.Layout()
    end
  end)
end)

ns.On("PLAYER_ENTERING_WORLD", onWorld)
ns.On("ZONE_CHANGED_NEW_AREA", function()
  onWorld()
  onZone()
end)
ns.On("ZONE_CHANGED", onZone)
ns.On("ZONE_CHANGED_INDOORS", onZone)
ns.On("PLAYER_REGEN_ENABLED", function()
  if S.waiting then
    S.waiting = false
    DWM.Refresh()
  end
end)
