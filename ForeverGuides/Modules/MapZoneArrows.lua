-- Zone transition arrows on the map page canvas, from Modules/ZoneBorderLogic.lua. In the zone view
-- an arrow sits at every crossing to a neighbouring zone and points into it (a dashed one is an estimate);
-- hover names the zone and says how sure the place is, a click opens its map like a click on the area does.
-- The world view and the flat canvas have no zone borders, so they get none. Pins come from their own pool
-- (canvas.arrowPins). Keyboard: every pin takes part in the focus ring, the list of nearby areas in the path
-- bar is the other way in. The editor for the crossings (a separate tool) works on these pins (ZoneCrossingEdit).
local _, ns = ...
local L, ZBL, MI, MP, ZE = ns.L, ns.ZoneBorderLogic, ns.MapIcons, ns.MapPins, ns.ZoneCrossingEdit

local MZA = {}
ns.MapZoneArrows = MZA

local LIFT = 3 -- as the instance pins: above the places (2), below a city (4) and the selection
local ARROW_SCALE = 1.2 -- of the symbol size, so the direction reads at the symbol scale of the places

local current

local function showTip(pin)
  local title, lines = ZBL.TooltipLines(pin.arrow, L, nil, ZE.HintKey("zb.hint"))
  ns.ShowTooltip(pin, title, table.concat(lines, "\n"))
end

local function enter(pin)
  pin.badge:Highlight(1)
  showTip(pin)
end

local function leave(pin)
  pin.badge:Highlight(0)
  ns.HideTooltip()
end

-- ctx = {
--   canvas                      the pins are its children
--   zone()                      the zone view (MapWorld.ZoneView) under the canvas, nil in the world
--                               view and on the flat canvas
--   zones()                     the zone records of the travel data (names, levels, kind)
--   open(slug)                  opens the map of a neighbouring zone
--   width()                     width of the visible map part in canvas px (pin size)
--   scale()                     symbol size in percent
--   symbols()                   false hides every symbol of the page
--   blocked()                   true while a click on the map means something else (marker mode,
--                               Start/Goal mode)
-- }
-- Returns the controller: pins (the pool), Paint, Arrows (the arrows of the open zone).
function MZA.Attach(ctx)
  local canvas = ctx.canvas
  local ctl = { pins = {} }
  local byslug, indexed
  current = ctl

  local function zoneOf()
    if indexed ~= ctx.zones() then
      indexed, byslug = ctx.zones(), {}
      for _, z in ipairs(indexed or {}) do
        byslug[z.s] = z
      end
    end
    return byslug
  end

  local function newPin()
    local pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(MP.HIT, MP.HIT)
    pin:RegisterForClicks("LeftButtonUp")
    pin.badge = MI.NewArrow(pin)
    pin.badge.box:SetPoint("CENTER")
    pin:SetScript("OnEnter", enter)
    pin:SetScript("OnLeave", leave)
    pin:SetScript(
      "OnClick",
      ns.Wrap("map-zone-arrow", function(self, button)
        if button ~= "LeftButton" or ZE.Active() then
          return
        end
        ns.HideTooltip()
        ctx.open(self.arrow.slug)
      end)
    )
    ns.Focus.register(pin, function(self)
      self:Click()
    end)
    pin.fgOnFocus, pin.fgOnBlur = enter, leave
    ZE.Decorate(pin, ctl.host)
    return pin
  end

  -- Moves a pin to a zone position; the editor uses it while it drags.
  local function place(pin, x, y)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth(), -y * canvas:GetHeight())
  end

  ctl.host = {
    id = "addon",
    canvas = function()
      return canvas
    end,
    view = ctx.zone,
    zones = zoneOf,
    aspect = function()
      local w = canvas:GetWidth()
      return w > 0 and canvas:GetHeight() / w or 1
    end,
    place = place,
    level = function()
      return canvas:GetFrameLevel() + LIFT
    end,
    refresh = function()
      ctl.Paint()
    end,
    pins = function()
      return ctl.pins
    end,
  }
  ZE.Register(ctl.host)

  -- The arrows of the open zone, empty while the setting or the page's symbol switch is off.
  function ctl.Arrows()
    local zv = ctx.zone()
    if not (zv and ns.Store.get("settings.mapZoneArrowsAddonMap") ~= false and ctx.symbols()) then
      return {}
    end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    return ZBL.ForView(zv, zoneOf(), w > 0 and h / w or 1)
  end

  function ctl.Paint()
    local items = ctl.Arrows()
    local size = MP.PinSize(ctx.width(), ctx.scale()) * ARROW_SCALE * ZE.Scale()
    local level = canvas:GetFrameLevel() + LIFT
    local mouse = not ctx.blocked()
    for i, arrow in ipairs(items) do
      local pin = ctl.pins[i]
      if not pin then
        pin = newPin()
        ctl.pins[i] = pin
      end
      pin.arrow = arrow
      pin.badge:Set(size, arrow.angle, arrow.state == "estimated")
      pin:EnableMouse(mouse)
      pin:SetFrameLevel(level)
      place(pin, arrow.x, arrow.y)
      pin:Show()
    end
    for i = #items + 1, #ctl.pins do
      local pin = ctl.pins[i]
      pin.arrow = nil
      pin.badge:Highlight(0)
      pin:Hide()
    end
  end

  return ctl
end

-- The crossings or the editor changed: the arrows of the page that is shown are drawn again.
local function refresh()
  if current and current.host.canvas():IsVisible() then
    ns.Safe("map-zone-arrows-refresh", current.Paint)
  end
end

MZA.Refresh = refresh
ns.On("FG_ZONECROSS_CHANGED", refresh)
ns.On("FG_ZONECROSS_EDIT", refresh)
