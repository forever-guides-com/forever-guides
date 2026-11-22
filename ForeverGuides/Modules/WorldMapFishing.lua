-- The group "Fishing" in the tab "Gather" of the panel on Blizzard's world map (WorldMapGatherTab.lua): one
-- row with a button that opens a small window with the fish of the zone the map shows (chance per cast as
-- bar and percent, the lowest skill to cast and the skill without failed casts), plus a button that opens
-- the window of all fishing places. The switch for the fishing schools on the map is in the category row of the tab
-- (ns.GatherFilterUI), the same one as in the settings. The data and the rows come from the
-- fishing helper (ForeverGuides_Fishing, only through ns.FishingLauncher while it runs); without it the
-- section offers to switch it on. The numbers are in WorldMapFishingLogic.lua.
local _, ns = ...
local W, L, Theme = ns.W, ns.L, ns.Theme
local B = ns.BlizzardLinks
local FL = ns.WorldMapFishingLogic
local K = ns.PageKit

local F = {}
ns.WorldMapFishing = F

ns.AddLocale("enUS", {
  ["wm.fish.head"] = "Fishing",
  ["wm.fish.zone"] = "Fish of this zone",
  ["wm.fish.count"] = "%d fish",
  ["wm.fish.countNone"] = "none",
  ["wm.fish.win"] = "Fish of this zone",
  ["wm.fish.showTip"] = "Opens a small window with the fish of the zone this map shows, with their chance per cast, the lowest skill to cast and the skill without failed casts. Values of the base game. They can differ in the Forever client.",
  ["wm.fish.all"] = "All fishing places",
  ["wm.fish.allTip"] = "Opens the window with every fishing place and its fish.",
  ["wm.fish.detail"] = "%s: cast from skill %d, no failed casts from skill %d",
  ["wm.fish.noZone"] = "Open a zone map to see its fish.",
  ["wm.fish.none"] = "No fishing place is known for this zone.",
  ["wm.fish.chance"] = "Chance per cast: %s",
  ["wm.fish.enable"] = "Switch on fishing helper",
  ["wm.fish.enableTip"] = "The fishing places come with the fishing helper. Switches it on for this character.",
  ["wm.fish.copy"] = "Copy download link",
  ["wm.fish.copyTip"] = "The fishing helper is not installed. Copies the download link.",
  ["wm.fish.noteTip"] = "The fishing places come with the fishing helper. See Settings > Addons.",
})
ns.AddLocale("deDE", {
  ["wm.fish.head"] = "Angeln",
  ["wm.fish.zone"] = "Fische dieser Zone",
  ["wm.fish.count"] = "%d Fische",
  ["wm.fish.countNone"] = "keine",
  ["wm.fish.win"] = "Fische dieser Zone",
  ["wm.fish.showTip"] = "Öffnet ein kleines Fenster mit den Fischen der Zone, die diese Karte zeigt, mit Chance pro Wurf, Mindest-Skill zum Auswerfen und Skill ohne Fehlwürfe. Werte des Basisspiels. Im Forever-Client können sie abweichen.",
  ["wm.fish.all"] = "Alle Angelplätze",
  ["wm.fish.allTip"] = "Öffnet das Fenster mit allen Angelplätzen und ihren Fischen.",
  ["wm.fish.detail"] = "%s: Auswerfen ab Skill %d, ohne Fehlwürfe ab Skill %d",
  ["wm.fish.noZone"] = "Öffne eine Zonenkarte, um ihre Fische zu sehen.",
  ["wm.fish.none"] = "Für diese Zone ist kein Angelplatz bekannt.",
  ["wm.fish.chance"] = "Chance pro Wurf: %s",
  ["wm.fish.enable"] = "Angelhilfe einschalten",
  ["wm.fish.enableTip"] = "Die Angelplätze gehören zur Angelhilfe. Schaltet sie für diesen Charakter ein.",
  ["wm.fish.copy"] = "Downloadlink kopieren",
  ["wm.fish.copyTip"] = "Die Angelhilfe ist nicht installiert. Kopiert den Downloadlink.",
  ["wm.fish.noteTip"] = "Die Angelplätze gehören zur Angelhilfe. Siehe Einstellungen > Addons.",
})

local BTN_H, GAP, ROW_H, ICON, BAR_H = 24, 4, 26, 18, 3
local PERCENT_W = 52
local WIN_W, SIDE, TITLE_H = 380, 16, 48
local WIN_H = 400
local BAR_MAX = WIN_W - 2 * SIDE - 24 - ICON - 10

local function plain(frame)
  B.LeaveFocusRing(frame)
  return frame
end

-- The places API of the running fishing helper, nil while it does not run or is too old.
local function places()
  local launcher = ns.FishingLauncher
  local api = launcher and launcher.Active() and launcher.Api()
  local p = api and api.Places
  return type(p) == "table" and type(p.ForNames) == "function" and p or nil
end

-- Opens the map on a zone for the fishing places: Blizzard's world map with the panel on the tab Gather and
-- the window of the fish of this zone open; without Blizzard's map, and in combat, the map
-- page of the add-on. Blizzard's map is never touched in combat (docs/TAINT-AUDIT.md). Returns "opened"
-- or "page".
function F.ShowZone(mapId)
  local blizzard = not ns.InCombat() and (rawget(_G, "OpenWorldMap") or rawget(_G, "WorldMapFrame"))
  if not blizzard or not (ns.WorldMapLinks and ns.WorldMapLinks.Map()) then
    ns.MapRequest.Open({ map = mapId })
    return "page"
  end
  ns.Store.set("settings.worldMapPanelOpen", true)
  ns.Store.set("settings.worldMapPanelTab", "gather")
  if rawget(_G, "OpenWorldMap") then
    ns.MapOps.Record("OpenWorldMap", mapId)
    pcall(OpenWorldMap, mapId)
  else
    ns.MapOps.Record("WorldMapFrame:SetMapID", mapId)
    pcall(function()
      WorldMapFrame:Show()
      if WorldMapFrame.SetMapID then
        WorldMapFrame:SetMapID(mapId)
      end
    end)
  end
  F.OpenWindow()
  return "opened"
end

-- The map a fishing area belongs to (names: its English name and the name in the client language), or nil.
function F.MapFor(names)
  return ns.GatheringLogic.MapIdForName(names)
end

-- The button of the fishing places window: shows the area on the map. Returns "opened", "page" or
-- "nomap" (no zone map carries the name of the area).
function F.ShowArea(names)
  local mapId = F.MapFor(names)
  if not mapId then
    return "nomap"
  end
  return F.ShowZone(mapId)
end

-- The fishing area of the zone the map shows. Returns the area, or nil and why: "helper" (it does not run),
-- "zone" (the map shows no zone) or "none" (no area is known for it).
function F.Area()
  local p = places()
  if not p then
    return nil, "helper"
  end
  local mapId = ns.WorldMapLinks and ns.WorldMapLinks.MapID()
  if type(mapId) ~= "number" or mapId <= 0 then
    return nil, "zone"
  end
  local area = p.ForNames(FL.Names(mapId))
  if area then
    return area
  end
  return nil, "none"
end

-- Text of the button of the zone row, "7 fish" or "none".
function F.CountText(area)
  local n = area and math.min(#area.fish, FL.MAX_ROWS) or 0
  return n > 0 and string.format(L["wm.fish.count"], n) or L["wm.fish.countNone"]
end

-- The window with the fish of the zone ----------------------------------------------------------------------

local win

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetClipsChildren(true)
  K.RowHover(row)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetPoint("LEFT", 4, 1)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.percent = W.Text(row, { role = "ui", color = "accent2", justify = "RIGHT" })
  row.percent:SetPoint("RIGHT", -4, 1)
  row.percent:SetWidth(PERCENT_W)
  row.name = W.Text(row, { role = "ui", color = "text" })
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row.percent, "LEFT", -6, 0)
  row.bar = row:CreateTexture(nil, "ARTWORK")
  row.bar:SetHeight(BAR_H)
  row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", ICON + 10, 1)
  ns.Bind(row, function()
    row.bar:SetColorTexture(Theme.color("accent"))
  end)
  row:SetScript("OnEnter", function(self)
    local p = places()
    if p and self.item then
      p.ShowItem(self, self.item.id, self.item.name)
    end
  end)
  row:SetScript("OnLeave", ns.HideTooltip)
  return row
end

local function bindRow(row, item)
  local p = places()
  row.item = item
  local icon = p and p.Icon and p.Icon(item.id)
  if icon then
    row.icon:SetTexture(icon)
  end
  local name = item.name or ("#" .. tostring(item.id))
  row.name:SetText(p and p.ColorName and p.ColorName(name, item.id) or name)
  row.percent:SetText(p and p.Percent and p.Percent(item.chance) or "")
  row.bar:SetWidth(math.max(1, FL.BarWidth(item.share, BAR_MAX)))
  row.paintHover()
end

local function build()
  local f = ns.Dialogs.Create("ForeverGuidesFishZoneWindow", WIN_W, WIN_H)
  win = { frame = f }
  win.detail = W.Text(f, { role = "micro", color = "textSecondary", wrap = true })
  win.detail:SetWidth(WIN_W - 2 * SIDE)
  local host = CreateFrame("Frame", nil, f)
  W.Fill(host, "surface", 1)
  win.host = host
  win.list = W.ScrollList(host, { rowHeight = K.scaledHeight(ROW_H), createRow = createRow, bindRow = bindRow })
  win.list:SetAllPoints(host)
  win.empty = W.Text(host, { role = "ui", color = "textMuted", wrap = true })
  win.empty:SetPoint("TOPLEFT", 8, -8)
  win.empty:SetPoint("TOPRIGHT", -8, -8)
  local done = W.Action(f, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    variant = "primary",
    width = 110,
    onClick = function()
      f:Hide()
    end,
  })
  done:SetPoint("BOTTOMRIGHT", -SIDE, 14)

  -- Reads the zone of the map again: the window follows it while it is open.
  function win.Refresh()
    local area, why = F.Area()
    if why == "helper" then
      f:Hide()
      return
    end
    W.SetText(f.title, "wm.fish.win")
    local top = TITLE_H
    win.detail:ClearAllPoints()
    local shown = {}
    if area then
      win.detail:SetText(string.format(L["wm.fish.detail"], area.name, area.cast, area.clean))
      win.detail:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -TITLE_H)
      top = top + math.ceil(win.detail:GetStringHeight()) + GAP * 2
      for i = 1, math.min(#area.fish, FL.MAX_ROWS) do
        shown[i] = area.fish[i]
      end
    else
      win.detail:SetText("")
      win.empty:SetText(L[why == "zone" and "wm.fish.noZone" or "wm.fish.none"])
    end
    win.empty:SetShown(#shown == 0)
    win.host:ClearAllPoints()
    win.host:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -top)
    win.host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SIDE, 52)
    win.list:SetData(shown)
  end

  ns.On("FG_WORLDMAP_VIEW", function(_, kind)
    if kind == "map" and f:IsShown() then
      win.Refresh()
    end
  end)
  ns.On("FG_SUBADDON_CHANGED", function(_, id)
    if id == FL.ID and f:IsShown() then
      win.Refresh()
    end
  end)
  return win
end

-- Opens the window of the fish of the zone the map shows (nothing while the fishing helper does not run).
function F.OpenWindow()
  if not places() then
    return
  end
  if not win then
    build()
  end
  win.frame:Show()
  win.Refresh()
end

function F.CloseWindow()
  if win then
    win.frame:Hide()
  end
end

function F.WindowShown()
  return win ~= nil and win.frame:IsShown()
end

-- The window object (tests).
function F.Window()
  return win
end

-- The section in the panel ----------------------------------------------------------------------------------

-- parent: the tab, width: inner width, opts.relayout(): the tab lays out again.
-- Returns the frame with Layout(width) -> height, Update() and the parts.
function F.Build(parent, width, opts)
  opts = opts or {}
  local relayout = opts.relayout or function() end
  local f = CreateFrame("Frame", nil, parent)

  local head = W.Text(f, { key = "wm.fish.head", role = "ui", family = "heading", color = "accent2" })
  local zoneLabel = W.Text(f, { key = "wm.fish.zone", role = "ui", color = "text", wrap = true })
  local zone = plain(W.Button(f, {
    text = "",
    width = 64,
    height = BTN_H,
    tooltip = "wm.fish.zone",
    tooltipText = "wm.fish.showTip",
    opens = true,
    onClick = F.OpenWindow,
  }))
  zone.fgId = "wm-fish-zone"

  local empty = W.Text(f, { role = "micro", color = "textMuted", wrap = true })
  local all = plain(W.Button(f, {
    key = "wm.fish.all",
    height = BTN_H,
    tooltip = "wm.fish.all",
    tooltipText = "wm.fish.allTip",
    opens = true,
    onClick = function()
      local p = places()
      if p and p.Open then
        p.Open()
      end
    end,
  }))
  all.fgId = "wm-fish-all"

  -- The helper is off or missing: a button or one line.
  local enable = plain(W.Button(f, {
    key = "wm.fish.enable",
    height = BTN_H,
    tooltip = "wm.fish.enable",
    tooltipText = "wm.fish.enableTip",
    onClick = function()
      ns.SubAddons.SetEnabled(FL.ID, true, "char")
    end,
  }))
  enable.fgId = "wm-fish-enable"
  local copy = plain(W.Button(f, {
    key = "wm.fish.copy",
    height = BTN_H,
    tooltip = "wm.fish.copy",
    tooltipText = "wm.fish.copyTip",
    opens = true,
    onClick = function()
      ns.Dialogs.Copy("pkg.copy.title", ns.Website, "pkg.copy.hint")
    end,
  }))
  copy.fgId = "wm-fish-copy"
  local note = CreateFrame("Frame", nil, f)
  note:EnableMouse(true)
  note.text = W.Text(note, { role = "micro", color = "textMuted", wrap = true })
  note.text:SetPoint("TOPLEFT")
  note:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["wm.fish.head"], L["wm.fish.noteTip"])
  end)
  note:SetScript("OnLeave", ns.HideTooltip)
  note.fgId = "wm-fish-note"
  plain(note)

  local mode = "ready"

  local function hideBody()
    for _, part in ipairs({ zoneLabel, zone, empty, all, enable, copy, note }) do
      part:Hide()
    end
  end

  -- Reads the state of the helper and the map again and fills the parts. Returns nothing, Layout places them.
  function f:Update()
    hideBody()
    mode = FL.Mode(ns.SubAddons.State(FL.ID))
    if mode == "enable" then
      enable:Show()
    elseif mode == "download" then
      copy:Show()
    elseif mode == "note" then
      note.text:SetText((ns.AddonSettings.StatusText(FL.ID)))
      note:Show()
    else
      local area, why = F.Area()
      if why == "helper" then
        mode = "note"
        note.text:SetText(L["addons.state.outdated"])
        note:Show()
        return
      end
      W.SetText(zone.label, nil, F.CountText(area))
      zone:SetEnabled(area ~= nil)
      zoneLabel:Show()
      zone:Show()
      if why == "zone" then
        empty:SetText(L["wm.fish.noZone"])
        empty:Show()
      end
      all:Show()
    end
  end

  -- Places the parts inside `w` px, returns the height.
  function f:Layout(w)
    w = w or width
    local y = 0
    local function put(part, height, gap)
      part:ClearAllPoints()
      part:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      part:SetWidth(w)
      y = y + height + (gap or GAP)
    end
    put(head, 16)
    if mode == "enable" then
      put(enable, BTN_H)
    elseif mode == "download" then
      put(copy, BTN_H)
    elseif mode == "note" then
      note.text:SetWidth(w)
      put(note, math.max(1, math.ceil(note.text:GetStringHeight())))
      note:SetHeight(math.max(1, math.ceil(note.text:GetStringHeight())))
    else
      -- One row: the label takes what the button leaves and wraps instead of being cut.
      local buttonW = zone:Fit(math.floor(w * 0.6))
      zone:ClearAllPoints()
      zone:SetWidth(buttonW)
      zoneLabel:ClearAllPoints()
      zoneLabel:SetWidth(math.max(1, w - buttonW - GAP * 2))
      local rowH = math.max(BTN_H, math.ceil(zoneLabel:GetStringHeight()))
      zone:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(y + math.floor((rowH - BTN_H) / 2)))
      zoneLabel:SetPoint("LEFT", f, "TOPLEFT", 0, -(y + rowH / 2))
      y = y + rowH + GAP
      if empty:IsShown() then
        put(empty, math.ceil(empty:GetStringHeight()))
      end
      put(all, BTN_H)
    end
    local height = math.max(0, y - GAP)
    f:SetSize(w, height)
    return height
  end

  ns.On("FG_SUBADDON_CHANGED", function(_, id)
    if id == FL.ID and f:IsVisible() then
      f:Update()
      relayout()
    end
  end)
  ns.On("FG_WORLDMAP_VIEW", function(_, kind)
    if kind == "map" and f:IsVisible() then
      f:Update()
      relayout()
    end
  end)

  f.parts = {
    head = head,
    zoneLabel = zoneLabel,
    zone = zone,
    empty = empty,
    all = all,
    enable = enable,
    copy = copy,
    note = note,
  }
  return f
end
