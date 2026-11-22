-- The route panel docked to Blizzard's world map: the shared side panel (Modules/SidePanel.lua) at the right
-- edge of the map window over its whole height, outside the canvas. Opened it holds the route card
-- (RouteStopList) and the list of the legs of the route in one scroll area, collapsed it is a thin strip with
-- the title turned 90 degrees. The map is never covered. It is a child of the map under our own name, anchored to
-- the map and never the other way round; building and showing wait while the client holds the map protected
-- (combat), a toggle in combat is refused with a hint. On a maximised map, or when the panel would leave the
-- screen, it sits on the inside of the right edge as an overlay instead, below the buttons of the canvas
-- (our own logo button included, the insets apply there only). The side tab of the add-on hangs on the outer edge of the panel. The open
-- state is saved per character (charDB.routeDrawerOpen, closed by default); the card shows the shared plan of
-- RoutePlan, so the page Map & Route lists the same route.
local _, ns = ...
local W, WML, RP, L, TL, SP, Theme = ns.W, ns.WorldMapLinks, ns.RoutePlan, ns.L, ns.TravelLogic, ns.SidePanel, ns.Theme

ns.AddLocale("enUS", {
  ["wmr.panel.title"] = "Route",
  ["wmr.toggle"] = "Route",
  ["wmr.toggle.tip"] = "Opens or closes the route panel at the map edge.",
  ["wmr.panel.page"] = "Open in Map & Route",
  ["wmr.steps"] = "Legs",
})

ns.AddLocale("deDE", {
  ["wmr.panel.title"] = "Route",
  ["wmr.toggle"] = "Route",
  ["wmr.toggle.tip"] = "Öffnet oder schließt das Routenpanel am Kartenrand.",
  ["wmr.panel.page"] = "In Karte & Route öffnen",
  ["wmr.steps"] = "Etappen",
})

local PanelUI = {}
ns.WorldMapRoutePanel = PanelUI

-- Overlay inside only: TOP keeps the panel clear of the buttons Blizzard hangs at the right edge of the
-- canvas, CORNER leaves the lower right corner of the map to the gear handle of the window.
local WIDTH, TOP, CORNER = 300, 124, 22
local PAD, GUTTER, GAP, LEG_PAD = 8, 12, 4, 5
local CARD_W = WIDTH - 2 * PAD - GUTTER

local panel, scroll, card, legsTitle
local legs = {}

local function open()
  return panel ~= nil and panel:IsOpen()
end

local function paintLeg(row)
  row.line:SetColorTexture(Theme.fillColor("line"))
end

local function legRow(i)
  local row = legs[i]
  if not row then
    row = CreateFrame("Frame", nil, scroll.content)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.text = W.Text(row, { role = "micro", color = "text", wrap = true })
    row.text:SetPoint("TOPLEFT", 0, -LEG_PAD)
    ns.Bind(row, function()
      paintLeg(row)
    end)
    legs[i] = row
  end
  return row
end

-- The legs of the plan below the card: "k. From A to B, time", wrapped, one compact row each, inside the
-- scroll content.
local function paintLegs(y)
  local plan = RP.Plan()
  local steps = plan and plan.status == "ok" and plan.steps or {}
  legsTitle:SetShown(#steps > 0)
  if #steps > 0 then
    legsTitle:ClearAllPoints()
    legsTitle:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
    y = y + 18
  end
  for i, step in ipairs(steps) do
    local row = legRow(i)
    W.SetText(
      row.text,
      nil,
      string.format(
        "%s, %s",
        string.format(L["map.route.leg"], i, RP.Name(step.from), RP.Name(step.to)),
        TL.FormatDuration(step.sec or 0)
      )
    )
    local h = W.FitLabel(row.text, CARD_W) + 2 * LEG_PAD
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
    row:SetSize(CARD_W, h)
    paintLeg(row)
    row:Show()
    y = y + h
  end
  for i = #steps + 1, #legs do
    legs[i]:Hide()
  end
  return y
end

-- The card has its height; the legs follow and the scroll area learns the whole height.
local function fit(h)
  if open() and panel:IsShown() then
    scroll:SetContentHeight(paintLegs(h + 2 * GAP))
  end
end

-- Where the panel goes: outside the right edge while panel and the room for the side tab fit on the screen
-- and the map is not maximised, else inside as an overlay (SidePanel.Placement).
PanelUI.Placement = SP.Placement

-- How far the overlay inside stays below the top edge of the map: clear of the buttons Blizzard hangs at the
-- right edge and of our logo button.
local function topInset(map)
  local drop = TOP
  local button = WML.Parts().button
  local top, bottom = map:GetTop(), button and button:IsShown() and button:GetBottom()
  if type(top) == "number" and type(bottom) == "number" then
    drop = math.max(drop, top - bottom + GAP)
  end
  return drop
end

local function build(map)
  panel = SP.Attach(map, {
    key = "routepanel",
    title = function()
      return L["wmr.panel.title"]
    end,
    tip = "wmr.toggle.tip",
    width = WIDTH,
    store = "routeDrawerOpen",
    insetBottom = CORNER,
    insetTop = function()
      return topInset(map)
    end,
    lift = WML.Lift,
    build = function(body)
      scroll = W.ScrollArea(body, { gutter = GUTTER })
      scroll:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -PAD)
      scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -PAD, PAD)
      card = ns.RouteStopList.Create(scroll.content, CARD_W)
      card:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, 0)
      card.onResize = fit
      legsTitle = W.Text(scroll.content, { key = "wmr.steps", role = "ui", color = "accent2" })
    end,
    onLayout = function(p, isOpen)
      if isOpen and card then
        fit(card:Refresh())
      end
      WML.SetTabHost(p.mode == "right" and p:IsShown() and p or nil, 0)
    end,
  })
end

function PanelUI.Layout()
  local map = WML.Map()
  if panel and map and ns.ProtectedAllowed(map) then
    panel:Refresh()
  end
end

function PanelUI.Apply()
  local map = WML.Map()
  if not (map and ns.ProtectedAllowed(map)) then
    return
  end
  if not RP.Enabled() then
    if panel then
      panel:Hide()
      WML.SetTabHost(nil)
    end
    return
  end
  if not panel then
    build(map)
  end
  panel:Show()
  panel:Refresh()
end

function PanelUI.IsOpen()
  return open()
end

function PanelUI.SetOpen(on)
  if panel then
    panel:SetOpen(on == true)
  else
    ns.Store.setChar("routeDrawerOpen", on == true)
    PanelUI.Apply()
  end
end

function PanelUI.Parts()
  return { toggle = panel and panel.header, panel = panel, card = card, scroll = scroll }
end

ns.On("FG_WORLDMAP_VIEW", function(_, kind)
  if kind == "size" or kind == "map" then
    PanelUI.Layout()
  end
end)

ns.On("PLAYER_LOGIN", PanelUI.Apply)

ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_WorldMap" then
    PanelUI.Apply()
  end
end)

ns.On("PLAYER_REGEN_ENABLED", PanelUI.Apply)
