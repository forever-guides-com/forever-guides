-- Rare enemy pins on Blizzard's world map (WorldMapFrame), from DataApi.RaresForMap: a zone map shows one
-- symbol per rare (its main point). Hovering one opens the rare card as a preview, a left click pins it
-- (RareCard.lua); while a card is open, the other spawn points of that rare on the map appear as smaller, dimmer,
-- non-interactive symbols and vanish with the card. A rare not seen yet is tinted red and marked with "!".
-- Like WorldMapFlightPins it only hooks Blizzard's map and keeps its pins as children of the canvas.
-- The settings are rares (main switch) and rareMapPins; the list of places and the symbol are chosen in RareLogic.lua.
local _, ns = ...
local WML, RL = ns.WorldMapLinks, ns.RareLogic

local WRP = {}
ns.WorldMapRarePins = WRP

local SIZE = 16

local map
local pins = {}
-- Pool of the other spawn points, and what the card shows now (set by RareCard.OnChange).
local others = {}
local activeRare, activeOwner

local function hidePins(from)
  for i = from, #pins do
    pins[i].rare = nil
    pins[i]:Hide()
  end
end

local function hideOthers(from)
  for i = from, #others do
    others[i]:Hide()
  end
end

-- The other points of the rare the card shows, when the card belongs to a pin of this map.
local function drawOthers()
  local canvas = WML.Canvas()
  local id = canvas and activeRare and activeOwner and activeOwner.rareSource == "map" and WML.MapID()
  if not id then
    hideOthers(1)
    return
  end
  local points, scale = RL.OtherPoints(activeRare, id), WML.CanvasScale()
  local status = ns.RareCard.Standing(activeOwner.id)
  for i, pt in ipairs(points) do
    local dot = others[i]
    if not dot then
      dot = CreateFrame("Frame", nil, canvas)
      dot:SetSize(SIZE * RL.OTHER_SCALE, SIZE * RL.OTHER_SCALE)
      dot.back = dot:CreateTexture(nil, "BACKGROUND")
      dot.back:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
      dot.back:SetPoint("TOPLEFT", -2, 2)
      dot.back:SetPoint("BOTTOMRIGHT", 2, -2)
      dot.back:SetVertexColor(0, 0, 0, 0.7)
      dot.icon = dot:CreateTexture(nil, "ARTWORK")
      dot.icon:SetAllPoints()
      dot:SetAlpha(RL.OTHER_ALPHA)
      others[i] = dot
    end
    dot.nx, dot.ny = pt.x, pt.y
    ns.RareCard.SetIcon(dot.icon, activeRare, status)
    dot:SetFrameLevel(WML.CanvasLevel(canvas, "rares"))
    WML.PlacePin(dot, canvas, scale)
    dot:Show()
  end
  hideOthers(#points + 1)
end

local function onEnter(pin)
  ns.RareCard.Show(pin, pin.rare, pin.id)
end

local function onClick(pin)
  ns.RareCard.Pin(pin, pin.rare, pin.id)
end

local function newPin(canvas)
  local pin = CreateFrame("Button", nil, canvas)
  pin:SetSize(ns.MapPins.HIT, ns.MapPins.HIT)
  pin.icon = pin:CreateTexture(nil, "ARTWORK")
  pin.icon:SetPoint("CENTER")
  pin.icon:SetSize(SIZE, SIZE)
  pin.mark = ns.RareCard.NewMark(pin, pin.icon)
  pin.rareSource = "map"
  pin:RegisterForClicks("LeftButtonUp")
  pin:SetScript("OnEnter", onEnter)
  pin:SetScript("OnClick", onClick)
  return pin
end

local function draw()
  if not (map and ns.ProtectedAllowed(map)) then
    return
  end
  local canvas = RL.ShowsMap() and WML.Enabled("rareMapPins") and map:IsShown() and WML.Canvas()
  local id = canvas and WML.MapID()
  if not id then
    hidePins(1)
    ns.RareCard.Check()
    drawOthers()
    return
  end
  local items, scale = RL.MainPins(ns.DataApi.RaresForMap(id)), WML.CanvasScale()
  for i, it in ipairs(items) do
    local pin = pins[i]
    if not pin then
      pin = newPin(canvas)
      pins[i] = pin
    end
    pin.rare, pin.id, pin.nx, pin.ny = it.rare, it.id, it.x, it.y
    local status = ns.RareCard.Standing(it.id)
    ns.RareCard.SetIcon(pin.icon, it.rare, status)
    ns.RareCard.PaintMark(pin.mark, status)
    pin:SetFrameLevel(WML.CanvasLevel(canvas, "rares"))
    WML.PlacePin(pin, canvas, scale)
    pin:Show()
  end
  hidePins(#items + 1)
  ns.RareCard.Check()
  drawOthers()
end

-- Zoom and canvas size changes: only position and scale, no new data.
local function rescale()
  local canvas = WML.Canvas()
  if not canvas then
    return
  end
  local scale = WML.CanvasScale()
  for _, pin in ipairs(pins) do
    if pin.rare then
      WML.PlacePin(pin, canvas, scale)
    end
  end
  for _, dot in ipairs(others) do
    if dot:IsShown() then
      WML.PlacePin(dot, canvas, scale)
    end
  end
end

WRP.Refresh = ns.Wrap("wmrp-refresh", draw)

-- Number of shown pins.
function WRP.Count()
  local n = 0
  for _, pin in ipairs(pins) do
    if pin.rare then
      n = n + 1
    end
  end
  return n
end

-- Runs after WorldMapLinks has attached: it owns the lookup of the map frame.
function WRP.Attach()
  if map then
    return
  end
  map = WML.Map()
  if not map then
    return
  end
  WML.HookScript("rares", "OnShow", WRP.Refresh)
  WML.HookMethod("rares", "OnMapChanged", draw)
  WML.HookMethod("rares", "OnCanvasScaleChanged", rescale)
  WML.HookMethod("rares", "OnCanvasSizeChanged", rescale)
  WRP.Refresh()
end

ns.RareCard.OnChange(function(rare, owner)
  activeRare, activeOwner = rare, owner
  drawOthers()
end)

ns.On("FG_RARE_STATUS", function()
  WRP.Refresh()
end)

ns.On("PLAYER_LOGIN", WRP.Attach)

-- Blizzard_WorldMap is load-on-demand on some clients.
ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_WorldMap" then
    WRP.Attach()
  end
end)

ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.rareMapPins" or path == "settings.rares" or path == "settings.rareMapShow" then
    WRP.Refresh()
  end
end)
