-- Ore and herb spots on the zone map of the map page: one round symbol per known spot of the items the
-- page "Ores and herbs" switched on for the zone (every item of the zone until the player narrows it). The symbols come from a texture pool on one frame
-- that takes no mouse, so clicks go to the map below; one throttled poll of the cursor finds the symbol
-- under it for the tooltip. The numbers (sizes, plan, hit test) are in GatheringMapLogic.lua, MapPage.lua
-- hands in the zone, the switches and the visible part of the map through the Attach context.
local _, ns = ...
local L, Theme, MI = ns.L, ns.Theme, ns.MapIcons
local GM = ns.GatheringMapLogic

local GMap = {}
ns.GatheringMap = GMap

GMap.HOVER_INTERVAL = 0.05
GMap.RING = 1 -- width of the dark edge around a symbol
GMap.GLOW = 3 -- the hover ring reaches this far past the symbol

ns.AddLocale("enUS", {
  ["map.gather"] = "Show ores and herbs",
  ["map.gather.tip"] = "Shows the spots of all ores and herbs of the zone on the zone map. The page Ores and herbs narrows it down per zone.\nHover a symbol for its name.",
  ["map.gather.spots"] = "Spots: %d (items: %d)",
  ["map.gather.noZone"] = "Open a zone to see ore and herb spots.",
  ["map.gather.none"] = "All items of this zone are switched off. Choose them on the page Ores and herbs.",
  ["map.gather.empty"] = "The data has no ore or herb spots for this zone.",
  ["map.gather.hide"] = "Hide spots",
  ["map.gather.hideTip"] = "Clears the choice of items for this zone.",
  ["map.gather.choose"] = "Choose items",
  ["map.gather.chooseTip"] = "Opens the page Ores and herbs.",
  ["map.gather.known"] = "Known spot",
  ["map.gather.own"] = "Own find",
})

ns.AddLocale("deDE", {
  ["map.gather"] = "Erze und Kräuter zeigen",
  ["map.gather.tip"] = "Zeigt die Fundorte aller Erze und Kräuter des Gebiets auf der Gebietskarte. Die Seite Erze und Kräuter schränkt sie je Gebiet ein.\nSymbol anfahren zeigt den Namen.",
  ["map.gather.spots"] = "Fundorte: %d (Items: %d)",
  ["map.gather.noZone"] = "Öffne ein Gebiet, um Fundorte von Erzen und Kräutern zu sehen.",
  ["map.gather.none"] = "Alle Items dieses Gebiets sind ausgeschaltet. Wähle sie auf der Seite Erze und Kräuter.",
  ["map.gather.empty"] = "Für dieses Gebiet kennen die Daten keine Fundorte von Erzen oder Kräutern.",
  ["map.gather.hide"] = "Fundorte ausblenden",
  ["map.gather.hideTip"] = "Leert die Auswahl der Items für dieses Gebiet.",
  ["map.gather.choose"] = "Items wählen",
  ["map.gather.chooseTip"] = "Öffnet die Seite Erze und Kräuter.",
  ["map.gather.known"] = "Bekannter Fundort",
  ["map.gather.own"] = "Eigener Fund",
})

-- The lines of a symbol's tooltip: title (item name) and text (profession and skill, then where the spot
-- comes from). item is the data entry of the item.
function GMap.TipText(data, pin)
  local item = data.items and data.items[pin.itemId] or {}
  local title = ns.GatheringLogic.ItemName(pin.itemId, item)
  local lines = {}
  if item.prof then
    lines[#lines + 1] =
      string.format(L["gather.itemSub"], ns.ProfessionRouteLogic.Name(item.prof), tonumber(item.skill) or 0)
  end
  lines[#lines + 1] = Theme.hexText("textMuted", L[pin.own and "map.gather.own" or "map.gather.known"])
  return title, table.concat(lines, "\n")
end

-- ctx = {
--   canvas                the map canvas the symbols sit on
--   mapId()               UiMapID of the open zone, nil on the world view
--   enabled()             the switch of the map page
--   scale()               symbol size setting in percent
--   window()              left, top, width, height of the visible part of the canvas in canvas px
--   cursor()              the cursor as fractions (0..1) of the visible part, nil when it is off the map
-- Optional, for a canvas the client scales (the Blizzard world map):
--   unit()                canvas units per screen px (default 1): the edge ring, the hover ring and the
--                         hit padding stay the same on screen
--   pinSize(width)        symbol edge in canvas units for the visible width (default: GM.PinSize)
--   items(mapId)          the set { [itemId] = true } to draw (default: GatherFilter.ZoneItems)
--   onMap(target)         true when the frame under the cursor belongs to the map (default: the
--                         canvas and the symbol layer)
-- }
-- Returns the controller: Paint(force), Clear, Info, Poll, layer, plan, hover.
function GMap.Attach(ctx)
  local canvas = ctx.canvas
  local ctl = { stamp = 0 }
  local function itemsOf(mapId)
    local data = ns.GatherDataAccess.Get()
    return data and ns.GatherFilter.ZoneItems(data, mapId) or nil
  end
  local function unit()
    return ctx.unit and ctx.unit() or 1
  end

  -- A frame without mouse over the canvas: it only carries the symbols and the poll.
  local layer = CreateFrame("Frame", nil, canvas)
  layer:SetAllPoints(canvas)
  layer:SetFrameLevel(canvas:GetFrameLevel() + 1)
  layer:EnableMouse(false)
  layer:Hide()
  ctl.layer = layer

  local disc = MI.DiscKnown()
  local canMask = disc and layer.CreateMaskTexture ~= nil
  local pool, used = {}, 0
  ctl.pool = pool

  local glow = layer:CreateTexture(nil, "OVERLAY")
  glow:SetTexture(MI.DISC)
  glow:SetBlendMode("ADD")
  glow:SetVertexColor(1, 1, 1, 0.45)
  glow:Hide()

  local function newSymbol()
    local s = {
      ring = layer:CreateTexture(nil, "BACKGROUND"),
      icon = layer:CreateTexture(nil, "ARTWORK"),
    }
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.ring:SetPoint("CENTER", s.icon, "CENTER")
    if disc then
      s.ring:SetTexture(MI.DISC)
    end
    if canMask then
      s.mask = layer:CreateMaskTexture()
      s.mask:SetTexture(MI.DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      s.mask:SetAllPoints(s.icon)
      s.icon:AddMaskTexture(s.mask)
    end
    return s
  end

  local function paintRing(s)
    if disc then
      s.ring:SetVertexColor(Theme.color("bg", 0.9))
    else
      s.ring:SetColorTexture(Theme.color("bg", 0.9))
    end
  end
  ns.Bind(layer, function()
    for i = 1, #pool do
      paintRing(pool[i])
    end
  end)

  -- Tooltip and hover ------------------------------------------------------------------------------
  local function hideTip()
    local tip = rawget(_G, "GameTooltip")
    if tip and tip:GetOwner() == layer then
      tip:Hide()
    end
  end

  local function setHover(pin)
    if pin == ctl.hover then
      return
    end
    ctl.hover = pin
    if not pin then
      glow:Hide()
      hideTip()
      return
    end
    local size = ctl.plan.size
    glow:ClearAllPoints()
    glow:SetPoint("CENTER", canvas, "TOPLEFT", pin.x, -pin.y)
    local reach = 2 * GMap.GLOW * (ctl.plan.unit or 1)
    glow:SetSize(size + reach, size + reach)
    glow:Show()
    local data = ns.GatherDataAccess.Get()
    if data then
      local title, text = GMap.TipText(data, pin)
      ns.ShowTooltip(layer, title, text, { anchor = "ANCHOR_CURSOR" })
    end
  end

  -- True when nothing else (a place symbol, the zoom bar, a window) has the mouse: only then the cursor is
  -- on the map itself. A client without the call gives no answer, the map is assumed.
  local function mouseOnMap()
    local foci, legacy = rawget(_G, "GetMouseFoci"), rawget(_G, "GetMouseFocus")
    local target
    if foci then
      target = foci()[1]
    elseif legacy then
      target = legacy()
    end
    if ctx.onMap then
      return target == nil or target == layer or ctx.onMap(target) == true
    end
    return target == nil or target == canvas or target == layer
  end

  -- One test per tick: the symbol under the cursor, looked up in the grid of the plan. Nothing happens
  -- while the cursor, the plan and the visible part stay as they were.
  function ctl.Poll()
    local plan = ctl.plan
    local pin
    if plan then
      local fx, fy = ctx.cursor()
      if fx and mouseOnMap() then
        local l, t, w, h = ctx.window()
        local x, y = GM.CursorToCanvas(fx, fy, l, t, w, h)
        if x then
          if x == ctl.lastX and y == ctl.lastY and ctl.lastStamp == ctl.stamp then
            return
          end
          ctl.lastX, ctl.lastY, ctl.lastStamp = x, y, ctl.stamp
          pin = GM.Hit(plan.index, x, y, plan.radius)
        end
      end
    end
    if not pin then
      ctl.lastX, ctl.lastY = nil, nil
    end
    setHover(pin)
  end

  local elapsed = 0
  layer:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed >= GMap.HOVER_INTERVAL then
      elapsed = 0
      ns.Safe("gather-map-hover", ctl.Poll)
    end
  end)
  layer:SetScript("OnHide", function()
    ctl.hover = nil
    glow:Hide()
    hideTip()
  end)

  -- Painting -----------------------------------------------------------------------------------------

  function ctl.Clear()
    ctl.plan, ctl.hover = nil, nil
    ctl.stamp = ctl.stamp + 1
    glow:Hide()
    hideTip()
    for i = 1, used do
      pool[i].icon:Hide()
      pool[i].ring:Hide()
    end
    used = 0
    layer:Hide()
  end

  local function place(i, pin, size, path, ring)
    local s = pool[i]
    if not s then
      s = newSymbol()
      pool[i] = s
      paintRing(s)
    end
    s.icon:ClearAllPoints()
    s.icon:SetPoint("CENTER", canvas, "TOPLEFT", pin.x, -pin.y)
    s.icon:SetSize(size, size)
    if s.path ~= path then
      s.path = path
      s.icon:SetTexture(path)
    end
    s.ring:SetSize(size + 2 * ring, size + 2 * ring)
    s.icon:Show()
    s.ring:Show()
  end

  -- Lays the symbols out for the open zone. force = false (the map was only dragged) keeps the symbols
  -- while the visible part still lies inside what the last plan covered.
  function ctl.Paint(force)
    local mapId = ctx.mapId()
    local set = mapId and ctx.enabled() and (ctx.items or itemsOf)(mapId) or nil
    if not (set and next(set)) then
      if ctl.plan then
        ctl.Clear()
      end
      return
    end
    local data = ns.GatherDataAccess.Get()
    if not data then
      if ctl.plan then
        ctl.Clear()
      end
      return
    end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local wl, wt, ww, wh = ctx.window()
    local size = ctx.pinSize and ctx.pinSize(ww) or GM.PinSize(ww, ctx.scale())
    local u = unit()
    local old = ctl.plan
    if
      not force
      and old
      and old.mapId == mapId
      and old.cw == cw
      and old.ch == ch
      and old.size == size
      and old.unit == u
      and GM.Covers(old.extent, wl, wt, ww, wh)
    then
      return
    end
    local plan = GM.Plan(GM.Points(data, mapId, set), { cw = cw, ch = ch, l = wl, t = wt, w = ww, h = wh })
    plan.mapId, plan.cw, plan.ch, plan.size, plan.unit = mapId, cw, ch, size, u
    plan.radius = GM.HitRadius(size, u)
    plan.index = GM.Index(plan.pins, plan.radius)
    local icons = {}
    for i, pin in ipairs(plan.pins) do
      local path = icons[pin.itemId]
      if not path then
        path = ns.GatheringLogic.IconPath(pin.itemId, data.items[pin.itemId])
        icons[pin.itemId] = path
      end
      place(i, pin, size, path, GMap.RING * u)
    end
    for i = #plan.pins + 1, used do
      pool[i].icon:Hide()
      pool[i].ring:Hide()
    end
    used = #plan.pins
    ctl.plan = plan
    ctl.stamp = ctl.stamp + 1
    ctl.hover = nil
    glow:Hide()
    hideTip()
    layer:SetShown(used > 0)
  end

  -- What the map page tells under the switch: { state = "noZone" | "data" | "empty" | "none" | "shown",
  -- mapId, points, items, status }. "empty": the data has no spots in the zone, "none": every item of the
  -- zone is switched off.
  function ctl.Info()
    local mapId = ctx.mapId()
    if not mapId then
      return { state = "noZone" }
    end
    local data, status = ns.GatherDataAccess.Get()
    if not data then
      return { state = "data", mapId = mapId, status = status }
    end
    local set = (ctx.items or itemsOf)(mapId) or {}
    if not next(set) then
      local zone = data.zones and data.zones[mapId]
      return { state = zone and next(zone.items or {}) and "none" or "empty", mapId = mapId }
    end
    local points, items = GM.Summary(data, mapId, set)
    return { state = "shown", mapId = mapId, points = points, items = items }
  end

  return ctl
end
