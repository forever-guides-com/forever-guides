-- Fishing helper, the window "Fishing places": the areas with the lowest skill to cast, on the right the fish of
-- the chosen area with icon, name and chance. Built from the same parts as the catch journal (list, rows, item
-- tooltip). Data: fish.PlacesData, rows: fish.PlacesLogic.
local _, fish = ...
if not fish.FG then
  return
end

local FG = fish.FG
local W, L, Theme, WS = FG.W, FG.L, FG.Theme, FG.WindowStyle
local Logic, Detail, Game = fish.PlacesLogic, fish.JournalDetail, fish.Game

local V = {}
fish.PlacesView = V

local HEAD_H, ROW_H, ICON_W, DETAIL_W = 22, 26, 20, 280
local WIDTH, HEIGHT = 640, 420
local state = { query = "", selected = nil }
local frame

FG.AddLocale("enUS", {
  ["fishp.title"] = "Fishing places",
  ["fishp.close"] = "Close the fishing places",
  ["fishp.open"] = "Fishing places",
  ["fishp.openTip"] = "Areas with the lowest skill to cast and the fish you can catch there",
  ["fishp.search"] = "Search area",
  ["fishp.skill"] = "From skill %d",
  ["fishp.detail"] = "Cast from skill %d, no failed casts from skill %d",
  ["fishp.areas"] = "%d areas",
  ["fishp.empty"] = "Choose an area on the left.",
  ["fishp.none"] = "No area matches.",
  ["fishp.note"] = "Values of the base game, they can differ in the Forever client. Chance per cast.",
  ["fishp.map"] = "On the map",
  ["fishp.mapTip"] = "Opens the map on this area. The panel of the map lists the fish there with their chance (tab Gather, Fishing places of this zone). Not in combat.",
  ["fishp.mapNone"] = "No zone map belongs to this area.",
  ["fishp.mapCombat"] = "Not in combat.",
})
FG.AddLocale("deDE", {
  ["fishp.title"] = "Angelplätze",
  ["fishp.close"] = "Angelplätze schließen",
  ["fishp.open"] = "Angelplätze",
  ["fishp.openTip"] = "Gebiete mit dem Mindest-Skill zum Auswerfen und den Fischen, die dort anbeißen",
  ["fishp.search"] = "Gebiet suchen",
  ["fishp.skill"] = "Ab Skill %d",
  ["fishp.detail"] = "Auswerfen ab Skill %d, ohne Fehlwürfe ab Skill %d",
  ["fishp.areas"] = "%d Gebiete",
  ["fishp.empty"] = "Wähle links ein Gebiet.",
  ["fishp.none"] = "Kein Gebiet passt.",
  ["fishp.note"] = "Werte des Basisspiels, im Forever-Client können sie abweichen. Chance pro Wurf.",
  ["fishp.map"] = "Auf der Karte",
  ["fishp.mapTip"] = "Öffnet die Karte in diesem Gebiet. Das Panel der Karte listet dort die Fische mit ihrer Chance (Reiter Sammeln, Angelplätze dieser Zone). Nicht im Kampf.",
  ["fishp.mapNone"] = "Zu diesem Gebiet gehört keine Zonenkarte.",
  ["fishp.mapCombat"] = "Nicht im Kampf.",
})

local function data()
  return fish.PlacesData
end

local function createAreaRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  local r, g, b = Theme.color("accent")
  row.sel:SetColorTexture(r, g, b, 0.22)
  row.extra = W.Text(row, { role = "ui", color = "textMuted", justify = "RIGHT" })
  row.extra:SetPoint("RIGHT", -6, 0)
  row.extra:SetWidth(90)
  row.name = W.Text(row, { role = "ui", color = "text" })
  row.name:SetPoint("LEFT", 8, 0)
  row.name:SetPoint("RIGHT", row.extra, "LEFT", -6, 0)
  row:SetScript(
    "OnClick",
    FG.Wrap("fishp-area", function(self)
      if self.item then
        V.Select(self.item.key)
      end
    end)
  )
  return row
end

local function bindAreaRow(row, item)
  row.item = item
  row.name:SetText(item.name)
  row.extra:SetText(string.format(L["fishp.skill"], item.cast))
  row.sel:SetShown(item.key == state.selected)
end

local function createFishRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON_W, ICON_W)
  row.icon:SetPoint("LEFT", 4, 0)
  row.chance = W.Text(row, { role = "ui", color = "accent2", justify = "RIGHT" })
  row.chance:SetPoint("RIGHT", -6, 0)
  row.chance:SetWidth(60)
  row.name = W.Text(row, { role = "ui", color = "text" })
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row.chance, "LEFT", -6, 0)
  row:SetScript("OnEnter", function(self)
    if self.item then
      Detail.ShowItem(self, self.item.id, self.item.name, nil, nil)
    end
  end)
  row:SetScript("OnLeave", FG.HideTooltip)
  return row
end

local function bindFishRow(row, item)
  row.item = item
  local icon = Game.ItemIcon(item.id)
  if icon then
    row.icon:SetTexture(icon)
  end
  local name = item.name or L["fishing.fish.unknown"]
  row.name:SetText(Detail.ColorName(name, Game.ItemQuality(item.id)))
  row.chance:SetText(Logic.Percent(item.chance))
end

function V.Refresh()
  if not frame then
    return
  end
  local list = Logic.Rows(data(), Game.AreaName, state.query)
  frame.rows = list
  frame.list:SetData(list)
  frame.summary:SetText(#list > 0 and string.format(L["fishp.areas"], #list) or L["fishp.none"])
  local entry = state.selected and data() and data().areas[state.selected]
  frame.fishRows = Logic.Fish(data(), state.selected, Game.FishName)
  frame.fishList:SetData(frame.fishRows)
  if entry then
    frame.detail:SetText(string.format(L["fishp.detail"], entry[1], entry[2]))
    frame.empty:SetText("")
  else
    frame.detail:SetText("")
    frame.empty:SetText(L["fishp.empty"])
  end
end

-- The names of the selected area for the lookup of its map: the English name of the data and the client's name.
local function areaNames(key)
  local entry = key and data() and data().areas[key]
  if not entry then
    return nil
  end
  return { entry[3], Game.AreaName(key) }
end

-- The button "On the map": the map shows the area and its panel lists the fish. The main add-on does the work.
function V.ShowOnMap()
  local names = areaNames(state.selected)
  if not names then
    return FG.Notify(L["fishp.empty"], "warning")
  end
  local shower = FG.WorldMapFishing
  local result = shower and shower.ShowArea(names) or "nomap"
  if result == "nomap" then
    FG.Notify(L["fishp.mapNone"], "warning")
  elseif result == "combat" then
    FG.Notify(L["fishp.mapCombat"], "warning")
  end
  return result
end

function V.Select(key)
  state.selected = key
  V.Refresh()
end

function V.SetQuery(text)
  state.query = text or ""
  V.Refresh()
end

local function create()
  local f = CreateFrame("Frame", "FGFishPlacesWindow", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER")
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.shell = FG.WindowShell.Attach(f, { title = "fishp.title", titleHeight = HEAD_H, shadow = true })
  f.bar = f.shell.titleBar
  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "fishp.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    FG.Wrap("fishp-close", function()
      f:Hide()
    end)
  )
  f.shell.titleText:ClearAllPoints()
  f.shell.titleText:SetPoint("LEFT", 8, 0)
  f.shell.titleText:SetPoint("RIGHT", f.close, "LEFT", -4, 0)

  f.search = W.EditBox(f, { placeholder = "fishp.search", clear = true, onChange = V.SetQuery })
  f.search:SetPoint("TOPLEFT", 10, -(HEAD_H + 8))
  f.search:SetPoint("RIGHT", f, "RIGHT", -(DETAIL_W + 18), 0)
  f.mapButton = W.Action(f, {
    key = "fishp.map",
    icon = "map",
    variant = "secondary",
    size = 24,
    tooltip = "fishp.map",
    tooltipText = "fishp.mapTip",
    onClick = FG.Wrap("fishp-map", V.ShowOnMap),
  })
  f.mapButton:SetPoint("TOPLEFT", f.search, "TOPRIGHT", 8, 0)
  f.mapButton:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  f.summary = W.Text(f, { role = "ui", color = "textSecondary" })
  f.summary:SetPoint("TOPLEFT", f.search, "BOTTOMLEFT", 0, -6)
  f.hint = W.Text(f, { role = "micro", color = "textMuted", wrap = true })
  f.hint:SetPoint("BOTTOMLEFT", 10, 8)
  f.hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
  f.hint:SetText(L["fishp.note"])
  f.list = W.ScrollList(f, { rowHeight = ROW_H, createRow = createAreaRow, bindRow = bindAreaRow })
  f.list:SetPoint("TOPLEFT", f.summary, "BOTTOMLEFT", 0, -6)
  f.list:SetPoint("BOTTOM", f.hint, "TOP", 0, 6)
  f.list:SetPoint("RIGHT", f, "RIGHT", -(DETAIL_W + 18), 0)

  f.detail = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  f.detail:SetPoint("TOPLEFT", f.list, "TOPRIGHT", 8, 0)
  f.detail:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  f.fishList = W.ScrollList(f, { rowHeight = ROW_H, createRow = createFishRow, bindRow = bindFishRow })
  f.fishList:SetPoint("TOPLEFT", f.detail, "BOTTOMLEFT", 0, -6)
  f.fishList:SetPoint("BOTTOMRIGHT", f.list, "BOTTOMRIGHT", DETAIL_W + 8, 0)
  f.empty = W.Text(f, { role = "ui", color = "textMuted", wrap = true })
  f.empty:SetPoint("TOPLEFT", f.detail, "TOPLEFT", 0, 0)
  f.empty:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  f.rows, f.fishRows = {}, {}

  f.styleParts = {
    bg = { f.bg },
    bars = { f.shell.barFill },
    border = f.shell.border,
    shadow = f.shell.shadow,
    chrome = { f.bar },
  }
  f.bar:EnableMouse(true)
  f.bar:RegisterForDrag("LeftButton")
  f.bar:SetScript("OnDragStart", function()
    f:StartMoving()
  end)
  f.bar:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
  end)
  FG.WindowShell.RegisterEsc(f, function()
    f:Hide()
  end)
  f:SetScript("OnShow", V.Refresh)
  f:SetScript("OnHide", Game.StopNameWatch)
  f:Hide()
  return f
end

function V.IsShown()
  return frame ~= nil and frame:IsShown()
end

function V.Frame()
  return frame
end

function V.Open()
  if not frame then
    frame = create()
  end
  WS.Apply(frame, WS.Resolve("fishjournal", nil), frame.styleParts)
  frame:Show()
  frame:Raise()
  V.Refresh()
  return frame
end

function V.Hide()
  if frame then
    frame:Hide()
  end
end

function V.Toggle()
  if V.IsShown() then
    V.Hide()
  else
    V.Open()
  end
end

-- The client delivered names that were missing: the open window draws them.
FG.On("FG_FISHING_NAMES", function()
  if V.IsShown() then
    V.Refresh()
  end
end)

FG.On("FG_LOCALE_CHANGED", function()
  if frame then
    frame.hint:SetText(L["fishp.note"])
    if V.IsShown() then
      V.Refresh()
    end
  end
end)
