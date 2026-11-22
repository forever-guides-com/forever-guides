-- Level ranges of the zones on Blizzard's world map (WorldMapFrame), from Modules/ZoneLevelLogic.lua. Two
-- parts: the line "Level 30-40" under the zone name that the client writes at the top while the mouse is over
-- a zone, always on, and a small label with the range in the middle of every zone of a continent map, off
-- until switched on (settings.mapZoneLevels). Both only hook Blizzard's map: the hover line is our own
-- FontString under the client's label, filled from a post-hook of the label's SetLabel, and nothing of
-- Blizzard's texts is written. The labels are children of the canvas like the other pins of the map.
local _, ns = ...
local L, WML, ZL, MW = ns.L, ns.WorldMapLinks, ns.ZoneLevelLogic, ns.MapWorld

ns.AddLocale("enUS", {
  ["zl.level"] = "Level %s",
  ["zl.set.labels"] = "Show zone levels on the map",
  ["zl.set.labelsTip"] = "Writes the level range into the middle of every zone on the continent maps of this window. The range under the zone name while you hover a zone is always shown.",
})
ns.AddLocale("deDE", {
  ["zl.level"] = "Stufe %s",
  ["zl.set.labels"] = "Gebietsstufen auf der Karte anzeigen",
  ["zl.set.labelsTip"] = "Schreibt die Stufenspanne in die Mitte jedes Gebiets auf den Kontinentkarten dieses Fensters. Die Spanne unter dem Gebietsnamen beim Überfahren eines Gebiets ist immer zu sehen.",
})

local WZL = {}
ns.WorldMapZoneLevels = WZL

local CONTINENT = 2 -- Enum.UIMapType.Continent
local SIZE = 12
local FALLBACK_TOP = -60

local map
local index, indexZones
local views = {}
local pins = {}
local playerLevel
local hoverText
local hoverHooked = false
local hooked = {}

local function level()
  if not playerLevel then
    local api = rawget(_G, "UnitLevel")
    playerLevel = type(api) == "function" and api("player") or nil
  end
  return playerLevel
end

-- Zone entries of the travel data. Rebuilt when the data table is another one.
local function lookup()
  local zones = ns.Data.Travel and ns.Data.Travel.zones
  if not (index and indexZones == zones) then
    indexZones = zones
    index = ZL.Index(zones, function(um)
      local info = WML.CApi("GetMapInfo", um)
      return type(info) == "table" and type(info.name) == "string" and info.name or nil
    end)
    views = {}
  end
  return index
end

-- Entry texts by player level: the colored range and the hover line, dropped when the level changes.
local function texts(entry)
  local current = level()
  if entry.forLevel ~= current then
    local range = ZL.Colored(entry.lmin, entry.lmax, current)
    entry.forLevel, entry.label, entry.hover = current, range, string.format(L["zl.level"], range)
  end
  return entry
end

-- Hover ------------------------------------------------------------------------------------

-- The client's label frame and the text our line hangs under, nil when the provider has none.
local function labelParts(provider)
  local label = type(provider) == "table" and provider.Label
  if type(label) == "table" and type(label.CreateFontString) == "function" then
    return label, type(label.Name) == "table" and label.Name or label
  end
end

local function hoverLine(provider)
  if hoverText then
    return hoverText
  end
  local parent, anchor = labelParts(provider)
  if not parent then
    -- No label frame found: a frame of ours over the map, the line sits at its top.
    parent = CreateFrame("Frame", nil, WML.Container())
    parent:SetAllPoints(WML.Container())
  end
  hoverText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ns.Theme.applyFont(hoverText, "h3", "body", "OUTLINE")
  if anchor then
    hoverText:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
  else
    hoverText:SetPoint("TOP", parent, "TOP", 0, FALLBACK_TOP)
  end
  return hoverText
end

-- Post-hook of SetLabel(type, name, description): the first text argument that names a zone with a range
-- gets the line, every other call takes it away.
local function onLabel(provider, ...)
  local entry
  for i = 1, select("#", ...) do
    local arg = select(i, ...)
    entry = type(arg) == "string" and lookup().byName[arg] or nil
    if entry then
      break
    end
  end
  if entry then
    local line = hoverLine(provider)
    line:SetText(texts(entry).hover)
    line:Show()
  elseif hoverText then
    hoverText:Hide()
  end
end

-- The map's data providers keep the area label: the one with a SetLabel is hooked, else the label's own.
local function hookLabel()
  local providers = map and type(hooksecurefunc) == "function" and not hoverHooked and rawget(map, "dataProviders")
  if type(providers) ~= "table" then
    return
  end
  for provider in pairs(providers) do
    local label = labelParts(provider)
    local owner = type(provider) == "table" and (type(provider.SetLabel) == "function" and provider or label)
    if owner and type(owner.SetLabel) == "function" then
      hoverHooked = pcall(hooksecurefunc, owner, "SetLabel", function(_, ...)
        onLabel(provider, ...)
      end)
      if hoverHooked then
        return
      end
    end
  end
end

-- Labels on the map ------------------------------------------------------------------------

-- The centers of the zones with a range on a continent map, kept per map: the rectangles do not change while
-- the game runs. Empty when the client reports none.
local function continentView(id)
  local view = views[id]
  if not view then
    view = {}
    for _, entry in ipairs(lookup().list) do
      local x, y = ZL.Center(MW.Rect(WML.CApi("GetMapRectOnMap", entry.um, id)))
      if x then
        view[#view + 1] = { entry = entry, x = x, y = y }
      end
    end
    views[id] = view
  end
  return view
end

local function newPin(canvas)
  local pin = CreateFrame("Frame", nil, canvas)
  pin:SetSize(48, SIZE + 4)
  pin.text = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  pin.text:SetPoint("CENTER")
  ns.Theme.applyFont(pin.text, "ui", "body", "OUTLINE")
  return pin
end

local function hidePins(from)
  for i = from, #pins do
    pins[i].zone = nil
    pins[i]:Hide()
  end
end

local function wanted()
  return ns.Store.get("settings.mapZoneLevels") == true
end

local function draw()
  if not (map and ns.ProtectedAllowed(map)) then
    return
  end
  local canvas = wanted() and map:IsShown() and WML.Canvas()
  local id = canvas and WML.MapID()
  local view = id and WML.MapType(id) == CONTINENT and continentView(id)
  if not view or #view == 0 then
    hidePins(1)
    return
  end
  local scale = WML.CanvasScale()
  for i, item in ipairs(view) do
    local pin = pins[i]
    if not pin then
      pin = newPin(canvas)
      pins[i] = pin
    end
    pin.zone, pin.nx, pin.ny = item.entry.slug, item.x, item.y
    pin.text:SetText(texts(item.entry).label)
    pin:SetFrameLevel(WML.CanvasLevel(canvas, "levels"))
    WML.PlacePin(pin, canvas, scale)
    pin:Show()
  end
  hidePins(#view + 1)
end

-- Zoom and canvas size changes: only position and scale.
local function rescale()
  local canvas = WML.Canvas()
  if not canvas then
    return
  end
  local scale = WML.CanvasScale()
  for _, pin in ipairs(pins) do
    if pin.zone then
      WML.PlacePin(pin, canvas, scale)
    end
  end
end

WZL.Refresh = ns.Wrap("wmzl-refresh", draw)

-- Number of shown labels.
function WZL.Count()
  local n = 0
  for _, pin in ipairs(pins) do
    if pin.zone then
      n = n + 1
    end
  end
  return n
end

-- Hooks of the map and of the label, for /fg mapdiag and the tests.
function WZL.Debug()
  local out = { count = WZL.Count(), hover = hoverHooked, hooks = {} }
  for name, on in pairs(hooked) do
    out.hooks[name] = on
  end
  return out
end

-- Runs after WorldMapLinks has attached: it owns the lookup of the map frame.
function WZL.Attach()
  if not map then
    map = WML.Map()
    if not map then
      return
    end
    hooked.OnMapChanged = WML.HookMethod("levels", "OnMapChanged", draw) or hooked.OnMapChanged
    hooked.OnCanvasScaleChanged = WML.HookMethod("levels", "OnCanvasScaleChanged", rescale)
      or hooked.OnCanvasScaleChanged
    hooked.OnCanvasSizeChanged = WML.HookMethod("levels", "OnCanvasSizeChanged", rescale)
      or hooked.OnCanvasSizeChanged
    WML.HookScript("levels", "OnShow", function()
      hookLabel()
      WZL.Refresh()
    end)
  end
  hookLabel()
  WZL.Refresh()
end

ns.On("PLAYER_LOGIN", WZL.Attach)
ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_WorldMap" then
    WZL.Attach()
  end
end)

ns.On("PLAYER_LEVEL_UP", function(_, newLevel)
  playerLevel = type(newLevel) == "number" and newLevel or nil
  if map then
    WZL.Refresh()
  end
end)

ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.mapZoneLevels" and map then
    WZL.Refresh()
  end
end)
