-- The group "Fishing" in the tab "Gather" of the panel on Blizzard's world map (WorldMapGatherTab.lua): a
-- section that lists the fish of the zone the window shows with chance per cast (bar and percent), the
-- lowest skill to cast and the skill without failed casts, plus a button that opens the window of all
-- fishing places. The switch for the fishing schools on the map is in the category row of the tab
-- (ns.GatherFilterUI), the same one as in the settings. The data and the rows come from the
-- fishing helper (ForeverGuides_Fishing, only through ns.FishingLauncher while it runs); without it the
-- section offers to switch it on. The numbers are in WorldMapFishingLogic.lua.
local _, ns = ...
local W, L, Theme = ns.W, ns.L, ns.Theme
local B = ns.BlizzardLinks
local FL = ns.WorldMapFishingLogic

local F = {}
ns.WorldMapFishing = F

ns.AddLocale("enUS", {
  ["wm.fish.head"] = "Fishing",
  ["wm.fish.show"] = "Show fishing places of this zone",
  ["wm.fish.hide"] = "Hide fishing places of this zone",
  ["wm.fish.showTip"] = "Lists the fish of the zone this map shows with their chance per cast, the lowest skill to cast and the skill without failed casts. Values of the base game, they can differ in the Forever client.",
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
  ["wm.fish.show"] = "Angelplätze dieser Zone zeigen",
  ["wm.fish.hide"] = "Angelplätze dieser Zone ausblenden",
  ["wm.fish.showTip"] = "Listet die Fische der Zone, die diese Karte zeigt, mit Chance pro Wurf, Mindest-Skill zum Auswerfen und Skill ohne Fehlwürfe. Werte des Basisspiels, im Forever-Client können sie abweichen.",
  ["wm.fish.all"] = "Alle Angelplätze",
  ["wm.fish.allTip"] = "Öffnet das Fenster mit allen Angelplätzen und ihren Fischen.",
  ["wm.fish.detail"] = "%s: Auswerfen ab Skill %d, ohne Fehlwürfe ab Skill %d",
  ["wm.fish.noZone"] = "Öffne eine Zonenkarte, um ihre Fische zu sehen.",
  ["wm.fish.none"] = "Für diese Zone ist kein Angelplatz bekannt.",
  ["wm.fish.chance"] = "Chance pro Wurf: %s",
  ["wm.fish.enable"] = "Angelhilfe einschalten",
  ["wm.fish.enableTip"] = "Die Angelplätze gehören zur Angelhilfe. Schaltet sie für diesen Charakter ein.",
  ["wm.fish.copy"] = "Download-Link kopieren",
  ["wm.fish.copyTip"] = "Die Angelhilfe ist nicht installiert. Kopiert den Download-Link.",
  ["wm.fish.noteTip"] = "Die Angelplätze gehören zur Angelhilfe. Siehe Einstellungen > Addons.",
})

local BTN_H, GAP, ROW_H, ICON, BAR_H = 24, 4, 26, 18, 3
local PERCENT_W = 52

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

function F.IsOpen()
  return ns.Store.get("settings.gather.placesOpen") == true
end

-- Opens the map on a zone for the fishing places: Blizzard's world map with the panel on the tab Gather and
-- the section "Fishing places of this zone" open, which lists the fish there; without Blizzard's map the map
-- page of the add-on. Blizzard's map is never touched in combat (docs/TAINT-AUDIT.md). Returns "opened",
-- "page" or "combat".
function F.ShowZone(mapId)
  if ns.InCombat() then
    return "combat"
  end
  local blizzard = rawget(_G, "OpenWorldMap") or rawget(_G, "WorldMapFrame")
  if not blizzard or not (ns.WorldMapLinks and ns.WorldMapLinks.Map()) then
    ns.MapRequest.Open({ map = mapId })
    return "page"
  end
  ns.Store.set("settings.worldMapPanelOpen", true)
  ns.Store.set("settings.worldMapPanelTab", "gather")
  ns.Store.set("settings.gather.placesOpen", true)
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
  return "opened"
end

-- The map a fishing area belongs to (names: its English name and the name in the client language), or nil.
function F.MapFor(names)
  return ns.GatheringLogic.MapIdForName(names)
end

-- The button of the fishing places window: shows the area on the map. Returns "opened", "page", "combat" or
-- "nomap" (no zone map carries the name of the area).
function F.ShowArea(names)
  local mapId = F.MapFor(names)
  if not mapId then
    return "nomap"
  end
  return F.ShowZone(mapId)
end

-- parent: the tab, width: inner width, opts.relayout(): the tab lays out again.
-- Returns the frame with Layout(width) -> height, Update() and the parts.
function F.Build(parent, width, opts)
  opts = opts or {}
  local relayout = opts.relayout or function() end
  local f = CreateFrame("Frame", nil, parent)

  local head = W.Text(f, { key = "wm.fish.head", role = "ui", family = "heading", color = "accent2" })
  local zone = plain(W.Button(f, {
    key = "wm.fish.show",
    height = BTN_H,
    tooltip = "wm.fish.show",
    tooltipText = "wm.fish.showTip",
    onClick = function()
      ns.Store.set("settings.gather.placesOpen", not F.IsOpen())
      relayout()
    end,
  }))
  zone.fgId = "wm-fish-zone"

  -- The body of the section while the helper runs: the line of the area, the fish, the button for all places.
  local detail = W.Text(f, { role = "micro", color = "textSecondary", wrap = true })
  local empty = W.Text(f, { role = "micro", color = "textMuted", wrap = true })
  local rows = {}
  local function createRow(i)
    local row = CreateFrame("Button", nil, f)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("TOPLEFT", 0, -2)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.percent = W.Text(row, { role = "ui", color = "accent2", justify = "RIGHT" })
    row.percent:SetPoint("TOPRIGHT", 0, -3)
    row.percent:SetWidth(PERCENT_W)
    row.name = W.Text(row, { role = "ui", color = "text" })
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.name:SetPoint("RIGHT", row.percent, "LEFT", -6, 0)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetHeight(BAR_H)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", ICON + 6, 1)
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
    row.fgId = "wm-fish-row-" .. i
    return plain(row)
  end
  for i = 1, FL.MAX_ROWS do
    rows[i] = createRow(i)
    rows[i]:Hide()
  end
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

  local mode, area, shown = "ready", nil, 0

  local function hideBody()
    for _, part in ipairs({ detail, empty, all, enable, copy, note }) do
      part:Hide()
    end
    for _, row in ipairs(rows) do
      row:Hide()
    end
  end

  -- Reads the state of the helper and the map again and fills the parts. Returns nothing, Layout places them.
  function f:Update()
    local open = F.IsOpen()
    W.SetText(zone.label, open and "wm.fish.hide" or "wm.fish.show")
    hideBody()
    area, shown = nil, 0
    mode = FL.Mode(ns.SubAddons.State(FL.ID))
    if not open then
      return
    end
    if mode == "enable" then
      enable:Show()
    elseif mode == "download" then
      copy:Show()
    elseif mode == "note" then
      note.text:SetText((ns.AddonSettings.StatusText(FL.ID)))
      note:Show()
    else
      local p = places()
      if not p then
        mode = "note"
        note.text:SetText(L["addons.state.outdated"])
        note:Show()
        return
      end
      local mapId = ns.WorldMapLinks and ns.WorldMapLinks.MapID()
      if type(mapId) ~= "number" or mapId <= 0 then
        empty:SetText(L["wm.fish.noZone"])
        empty:Show()
      else
        area = p.ForNames(FL.Names(mapId))
        if area then
          detail:SetText(string.format(L["wm.fish.detail"], area.name, area.cast, area.clean))
          detail:Show()
          shown = math.min(#area.fish, FL.MAX_ROWS)
        else
          empty:SetText(L["wm.fish.none"])
          empty:Show()
        end
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
    put(zone, BTN_H)
    if F.IsOpen() then
      if mode == "enable" then
        put(enable, BTN_H)
      elseif mode == "download" then
        put(copy, BTN_H)
      elseif mode == "note" then
        note.text:SetWidth(w)
        put(note, math.max(1, math.ceil(note.text:GetStringHeight())))
        note:SetHeight(math.max(1, math.ceil(note.text:GetStringHeight())))
      else
        if detail:IsShown() then
          put(detail, math.ceil(detail:GetStringHeight()))
        end
        if empty:IsShown() then
          put(empty, math.ceil(empty:GetStringHeight()))
        end
        for i, row in ipairs(rows) do
          if i <= shown then
            local item = area.fish[i]
            row.item = item
            row:Show()
            local p = places()
            local icon = p and p.Icon and p.Icon(item.id)
            if icon then
              row.icon:SetTexture(icon)
            end
            local name = item.name or ("#" .. tostring(item.id))
            row.name:SetText(p and p.ColorName and p.ColorName(name, item.id) or name)
            row.percent:SetText(p and p.Percent and p.Percent(item.chance) or "")
            row:SetHeight(ROW_H)
            put(row, ROW_H, 0)
            row.bar:SetWidth(math.max(1, FL.BarWidth(item.share, w - ICON - 6)))
          end
        end
        if shown > 0 then
          y = y + GAP
        end
        put(all, BTN_H)
      end
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
    if kind == "map" and f:IsVisible() and F.IsOpen() then
      f:Update()
      relayout()
    end
  end)

  f.parts = {
    head = head,
    zone = zone,
    detail = detail,
    empty = empty,
    rows = rows,
    all = all,
    enable = enable,
    copy = copy,
    note = note,
  }
  return f
end
