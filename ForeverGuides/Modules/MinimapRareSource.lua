-- Rare enemies on the real minimap: source "rares" of the pin layer (MinimapLayer.lua). The places of the
-- rares of the zone the player stands in come from DataApi.RaresForMap, projected with the world frame of that
-- zone like the gathering spots. The source wants the layer only while the setting rareMinimapPins is on.
-- A rare pin is the main point of a rare (first pair of its points). It draws its own symbol (RareCard.SetIcon,
-- red with a "!" while the rare is not seen yet) and carries a small mouse-enabled button that opens the rare
-- card as a preview on hover and pins it on a left click. While a card of a minimap pin is open, the other points
-- of that rare come as smaller, dimmer pins without a button, appended after the main pins so the slots of the
-- main pins (and with them the owner of the card) do not move. The layer frame itself stays without mouse; only
-- the area of these buttons (the size of the symbol, at least HIT px) takes the mouse, the rest of the minimap
-- keeps its clicks and pings.
local _, ns = ...
local Layer, ML, RL = ns.MinimapLayer, ns.MinimapPinLogic, ns.RareLogic

local MR = {}
ns.MinimapRareSource = MR

local HIT = 16
-- The vignette atlases leave an empty margin, so the symbol is drawn a little larger than a plain pin.
local EXTRA = 4

function MR.Enabled()
  return RL.ShowsMap() and ns.Store.get("settings.rareMinimapPins") ~= false
end

-- The grid of a zone is built once per map, the places do not change while the client runs.
local indexes = {}

local function zoneIndex(mapId, frame)
  local index = indexes[mapId]
  if not index then
    index = ML.BuildIndex(RL.MainPins(ns.DataApi.RaresForMap(mapId)), frame)
    indexes[mapId] = index
  end
  return index
end

-- The other points of the rare the card shows, indexed like the zone, built once per rare and map.
local activeRare, activeOwner
local otherIndex = {}

local function otherPoints(mapId, frame)
  local rare = activeRare
  local cached = otherIndex[1]
  if not (cached and cached.rare == rare and cached.map == mapId) then
    local list = {}
    for _, pt in ipairs(RL.OtherPoints(rare, mapId)) do
      list[#list + 1] = { id = activeOwner.id, rare = rare, x = pt.x, y = pt.y }
    end
    cached = { rare = rare, map = mapId, index = ML.BuildIndex(list, frame) }
    otherIndex[1] = cached
  end
  return cached.index
end

-- The texture and the button of one pin slot, made once on the layer frame. nil in combat.
local function build(pin, host)
  if ns.InCombat() then
    return nil
  end
  local hit = CreateFrame("Button", nil, host)
  hit:RegisterForClicks("LeftButtonUp")
  hit.rareSource = "mini"
  hit:SetScript("OnEnter", function(self)
    ns.RareCard.Show(self, self.rare, self.id)
  end)
  hit:SetScript("OnClick", function(self)
    ns.RareCard.Pin(self, self.rare, self.id)
  end)
  local tex = host:CreateTexture(nil, "ARTWORK")
  local parts = { tex = tex, hit = hit, mark = ns.RareCard.NewMark(host, tex) }
  pin.rareParts = parts
  return parts
end

local function hideParts(pin)
  local parts = pin.rareParts
  if parts then
    parts.tex:Hide()
    parts.hit:Hide()
    parts.hit.rare, parts.hit.id = nil, nil
    -- The red disc of a new rare is a texture of its own on the layer frame: it has to go with the symbol.
    ns.RareCard.PaintMark(parts.mark, nil)
  end
end

-- The client draws the player arrow as part of the minimap, below every addon frame. A symbol that touches
-- it turns see-through so the arrow stays readable: ARROW_HALF is about half the arrow in px.
local ARROW_HALF, NEAR_ALPHA = 8, 0.3

function MR.NearPlayer(cx, cy, size)
  cx, cy = tonumber(cx), tonumber(cy)
  if not (cx and cy) then
    return false
  end
  local reach = size / 2 + ARROW_HALF
  return cx * cx + cy * cy < reach * reach
end

-- Called by the layer for every shown pin; false when the parts cannot be made now (combat).
local function paint(pin, host, anchor, alpha, scale)
  local parts = pin.rareParts or build(pin, host)
  if not parts then
    return false
  end
  local custom = pin.custom
  local minor = custom.minor
  local factor = minor and RL.OTHER_SCALE or 1
  local size = math.max(4, math.floor(custom.size * factor * scale + 0.5))
  local status = ns.RareCard.Standing(custom.id)
  ns.RareCard.SetIcon(parts.tex, custom.rare, status)
  parts.tex:ClearAllPoints()
  parts.tex:SetPoint("CENTER", anchor, "CENTER")
  parts.tex:SetSize(size, size)
  if MR.NearPlayer(pin.cx, pin.cy, size) then
    alpha = alpha * NEAR_ALPHA
  end
  parts.tex:SetAlpha(minor and alpha * RL.OTHER_ALPHA or alpha)
  parts.tex:Show()
  ns.RareCard.PaintMark(parts.mark, not minor and status or nil)
  parts.mark:SetAlpha(alpha)
  parts.mark.back:SetAlpha(alpha)
  parts.hit:ClearAllPoints()
  parts.hit:SetPoint("CENTER", anchor, "CENTER")
  parts.hit:SetSize(math.max(HIT, size), math.max(HIT, size))
  parts.hit.rare, parts.hit.id = custom.rare, custom.id
  parts.hit:SetShown(not minor)
  return true
end

local function source(view, add)
  local mapId = view.map
  if type(mapId) ~= "number" or #ns.DataApi.RaresForMap(mapId) == 0 then
    return
  end
  local frame = Layer.ZoneFrame(mapId)
  if not ML.Near(frame, view.cont, view.wx, view.wy, view.reach) then
    return
  end
  local size = (view.size or Layer.SIZE_DEFAULT) + EXTRA
  for _, e in ipairs(ML.Query(zoneIndex(mapId, frame), view.wx, view.wy, view.reach)) do
    local custom = { size = size, rare = e.rare, id = e.id, paint = paint, hide = hideParts }
    if add(e.wx, e.wy, nil, "rare", custom) == false then
      return
    end
  end
  if activeRare and activeOwner and activeOwner.rareSource == "mini" then
    for _, e in ipairs(ML.Query(otherPoints(mapId, frame), view.wx, view.wy, view.reach)) do
      local custom = { size = size, rare = e.rare, id = e.id, minor = true, paint = paint, hide = hideParts }
      if add(e.wx, e.wy, nil, "rare", custom) == false then
        return
      end
    end
  end
end

ns.RareCard.OnChange(function(rare, owner)
  activeRare, activeOwner = rare, owner
  Layer.Invalidate()
end)

ns.On("FG_RARE_STATUS", function()
  Layer.Invalidate()
end)

MR.Source = source
Layer.RegisterSource("rares", source, MR.Enabled)

-- The layer frame is only made outside of combat; PLAYER_REGEN_ENABLED applies what waited.
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.rareMinimapPins" or path == "settings.rares" or path == "settings.rareMapShow" then
    if not ns.InCombat() then
      Layer.Apply()
    end
    Layer.Invalidate()
  end
end)
