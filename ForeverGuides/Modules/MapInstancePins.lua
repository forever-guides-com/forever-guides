-- Instance entrance markers on the map page canvas, from Modules/MapMarkerLogic.lua. A marker
-- sits where its entrance lies inside its zone, converted to the current view (world, new regions
-- or one opened zone) with MapWorld.ZoneToPoint. The flat canvas has no zone rectangles, so it
-- gets no markers. Pins come from their own pool (canvas.instPins); a click opens the instance
-- page like the pins of the world map do. Keyboard: every pin takes part in the focus ring, the
-- instance list is the other way in.
local _, ns = ...
local L, MML, MI, MP, MW = ns.L, ns.MapMarkerLogic, ns.MapIcons, ns.MapPins, ns.MapWorld

local MIP = {}
ns.MapInstancePins = MIP

local ICON = { dungeon = "instanceEntrance", raid = "raidEntrance" }
local LIFT = 3 -- above the place pins (2), below a city (4) and the selection
local GLOW = 0.4

local current

-- Router path of the instance page: the map tab when the instance has a dungeon map.
local function route(marker)
  return "instances/" .. marker.slug .. (marker.hasDungeonMap and "/map" or "")
end

local function showTip(pin)
  local title, lines = MML.TooltipLines(pin.marker, L)
  ns.ShowTooltip(pin, title, table.concat(lines, "\n"))
end

local function enter(pin)
  pin.badge:Highlight(GLOW)
  showTip(pin)
end

local function leave(pin)
  pin.badge:Highlight(0)
  ns.HideTooltip()
end

local function newPin(canvas)
  local pin = CreateFrame("Button", nil, canvas)
  pin:SetSize(MP.HIT, MP.HIT)
  pin:RegisterForClicks("LeftButtonUp")
  pin.badge = MI.NewBadge(pin)
  pin.badge.box:SetPoint("CENTER")
  pin:SetScript("OnEnter", enter)
  pin:SetScript("OnLeave", leave)
  pin:SetScript(
    "OnClick",
    ns.Wrap("map-instance-pin", function(self)
      ns.Main.Show(route(self.marker))
    end)
  )
  ns.Focus.register(pin, function(self)
    self:Click()
  end)
  pin.fgOnFocus, pin.fgOnBlur = enter, leave
  return pin
end

-- All markers the settings and the player's faction allow, and the set of UiMapIDs that have an
-- entrance of any type (the places of those zones give way to the markers, see Covers).
local function collect()
  local s = ns.db and ns.db.settings or {}
  local all = MML.Build(ns.Data.Instances, ns.db and ns.db.mapMarkers)
  local covered = {}
  for _, m in ipairs(all) do
    covered[m.map] = true
  end
  return MML.Filter(all, {
    dungeons = s.mapMarkerDungeons,
    raids = s.mapMarkerRaids,
    faction = ns.PageKit.PlayerFaction(),
  }),
    covered
end

-- ctx = {
--   canvas                      the pins are its children
--   view()                      the view under the canvas (layout, island view or zone view), nil
--                               on the flat canvas
--   maps()                      zone slug -> UiMapID, nil without a layout
--   width()                     width of the visible map part in canvas px (pin size)
--   scale()                     symbol size in percent
--   symbols()                   false hides every symbol of the page
--   blocked()                   true while a click on the map means something else (marker mode,
--                               Start/Goal mode)
--   picking()                   optional, true in the Start/Goal mode: the markers give way so the
--                               instance entrances can be picked as places again
--   repaint()                   paints the page canvas again (settings changed)
-- }
-- Returns the controller: pins (the pool), Paint, Covers.
function MIP.Attach(ctx)
  local canvas = ctx.canvas
  local ctl = { pins = {} }
  local covered = {}
  current = { canvas = canvas, repaint = ctx.repaint }

  local function enabled()
    return ns.Store.get("settings.mapMarkersAddonMap") ~= false and ctx.symbols() and ctx.view() ~= nil
  end

  -- True when the markers speak for the instance entrances of the zone (as of the last Paint):
  -- the places of that kind are not drawn then.
  function ctl.Covers(zone)
    local maps = ctx.maps()
    return maps ~= nil and covered[maps[zone]] == true
  end

  function ctl.Paint()
    local view, items = ctx.view(), {}
    covered = {}
    if enabled() and not (ctx.picking and ctx.picking()) then
      local list, all = collect()
      covered = all
      local rev = {}
      for slug, id in pairs(ctx.maps() or {}) do
        rev[id] = slug
      end
      local cw, ch = canvas:GetWidth(), canvas:GetHeight()
      for _, m in ipairs(list) do
        local nx, ny = MW.ZoneToPoint(view, rev[m.map], m.x, m.y)
        if nx then
          items[#items + 1] = { marker = m, x = nx * cw, y = ny * ch }
        end
      end
    end
    local size = MP.PinSize(ctx.width(), ctx.scale())
    local level = canvas:GetFrameLevel() + LIFT
    local mouse = not ctx.blocked()
    for i, it in ipairs(items) do
      local pin = ctl.pins[i]
      if not pin then
        pin = newPin(canvas)
        ctl.pins[i] = pin
      end
      pin.marker = it.marker
      pin.badge:Set(ICON[it.marker.kind], it.marker.faction, size)
      pin:EnableMouse(mouse)
      pin:SetFrameLevel(level)
      pin:ClearAllPoints()
      pin:SetPoint("CENTER", canvas, "TOPLEFT", it.x, -it.y)
      pin:Show()
    end
    for i = #items + 1, #ctl.pins do
      local pin = ctl.pins[i]
      pin.marker = nil
      pin.badge:Highlight(0)
      pin:Hide()
    end
  end

  return ctl
end

-- Settings changed: paint the map page again when it is on screen (it paints itself when opened).
function MIP.Refresh()
  if current and current.canvas:IsVisible() then
    ns.Safe("map-instance-refresh", current.repaint)
  end
end
