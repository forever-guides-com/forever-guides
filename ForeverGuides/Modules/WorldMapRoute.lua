-- Route planning on Blizzard's world map (WorldMapFrame): {key:mapRoutePoint} + click adds a stop at the
-- clicked spot (the last point is the goal), the numbered pins and the route lines of the plan
-- (RoutePlan, shared with the side panel and the Map & Route page) sit on the canvas. A pin of a free
-- point can be dragged, a right click on any pin opens its menu (up, down, goal, remove). The lines and
-- pins are the controller of MapRoute.lua on a frame of ours that lies on the canvas and cancels the
-- canvas zoom, so lines and pins keep their size at every zoom. Only the steps with both ends on the
-- shown map are drawn: a zone map shows the legs inside the zone, a continent or world map the legs
-- between its zones. Like the other world map modules nothing is written into Blizzard tables except a
-- click use inside the one canvas handler of WorldMapLinks (true only for our click) and secure hooks; the
-- drawing only touches frames of ours and waits while the client holds the map protected.
local _, ns = ...
local W, L, TL, WML, WRL, RP, MR =
  ns.W, ns.L, ns.TravelLogic, ns.WorldMapLinks, ns.WorldMapRouteLogic, ns.RoutePlan, ns.MapRoute

ns.AddLocale("enUS", {
  ["wmr.menu.up"] = "Move up",
  ["wmr.menu.down"] = "Move down",
  ["wmr.menu.goal"] = "Make this the goal",
  ["wmr.menu.remove"] = "Remove from route",
  ["wmr.menu.start"] = "Start from my position",
  ["wmr.leg.tip"] = "%s, %s",
  ["wmr.set"] = "Route planning on the world map",
  ["wmr.set.tip"] = "{key:mapRoutePoint} + click adds a stop to the route, with numbered waypoints and lines on the map and a panel.",
})

ns.AddLocale("deDE", {
  ["wmr.menu.up"] = "Nach oben",
  ["wmr.menu.down"] = "Nach unten",
  ["wmr.menu.goal"] = "Als Ziel festlegen",
  ["wmr.menu.remove"] = "Aus der Route entfernen",
  ["wmr.menu.start"] = "Von meiner Position starten",
  ["wmr.leg.tip"] = "%s, %s",
  ["wmr.set"] = "Routenplanung auf der Weltkarte",
  ["wmr.set.tip"] = "{key:mapRoutePoint} + Klick fügt der Route einen Stopp hinzu, mit nummerierten Wegpunkten und Linien auf der Karte und einem Panel.",
})

local WMR = {}
ns.WorldMapRoute = WMR

local MENU_W, MENU_ROW = 190, 24
local LEVEL_ABOVE_WAYPOINTS = 520

local map, overlay, ctl
local steps, stepAt, planAt = {}, {}, {}
local shown = { map = nil, scale = nil }
local menu, menuIndex

-- Where a place is on the map that is shown, as fractions, or nil.
local function fractionOf(slug)
  local id = WML.MapID()
  local pos = id and RP.PositionOf(slug)
  if not pos then
    return nil
  end
  return WML.Project(pos.map, pos.x, pos.y, id, WML.MapType(id))
end

local function projector()
  local id = WML.MapID()
  local kind = id and WML.MapType(id)
  return function(from, x, y)
    return WML.Project(from, x, y, id, kind)
  end
end

-- Pin menu ---------------------------------------------------------------------------------------------

local function moveFocus(step)
  local list = menu.buttons
  local index = 0
  for i, b in ipairs(list) do
    if ns.Focus.current == b then
      index = i
    end
  end
  if index == 0 then
    index = step > 0 and 1 or #list
  else
    index = (index - 1 + step) % #list + 1
  end
  ns.Focus.set(list[index])
end

local function menuItems()
  return {
    {
      key = "wmr.menu.up",
      run = function(i)
        RP.Move(i, -1)
      end,
    },
    {
      key = "wmr.menu.down",
      run = function(i)
        RP.Move(i, 1)
      end,
    },
    {
      key = "wmr.menu.goal",
      run = function(i)
        RP.SetGoal(i)
      end,
    },
    {
      key = "wmr.menu.remove",
      run = function(i)
        RP.Remove(i)
      end,
    },
  }
end

local function buildMenu()
  local layer = ns.Desktop.Layer
  local p = layer.newPopup("surface2")
  local items = menuItems()
  p.buttons = {}
  for i, item in ipairs(items) do
    local b = W.Button(p, {
      key = item.key,
      variant = "ghost",
      width = MENU_W,
      height = MENU_ROW,
      onClick = function()
        local at = menuIndex
        layer.close("select")
        if at then
          item.run(at)
        end
      end,
    })
    b.label:SetJustifyH("LEFT")
    b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * MENU_ROW)
    p.buttons[i] = b
  end
  p:SetSize(MENU_W + 4, #items * MENU_ROW + 4)
  p:EnableKeyboard(true)
  p:SetScript("OnKeyDown", function(self, key)
    local handled = true
    if key == "ESCAPE" then
      layer.close("escape")
    elseif key == "UP" or key == "DOWN" then
      moveFocus(key == "DOWN" and 1 or -1)
    elseif key == "ENTER" or key == "SPACE" then
      ns.Focus.activate()
    else
      handled = false
    end
    ns.PropagateKeys(self, not handled)
  end)
  return p
end

-- Opens the menu of the point number `index` of the plan below `anchor`.
function WMR.OpenMenu(index, anchor)
  if not (index and ns.Desktop and ns.Desktop.Layer) then
    return
  end
  menu = menu or buildMenu()
  menuIndex = index
  local layer = ns.Desktop.Layer
  layer.open({ frames = { menu }, owner = anchor, move = moveFocus })
  layer.place(menu, anchor, "TOPLEFT", "BOTTOMLEFT", 0, -2)
  menu:Show()
  ns.Focus.set(menu.buttons[1])
end

-- Drawing -----------------------------------------------------------------------------------------------

local function legTip(i)
  local step = steps[i]
  if not step then
    return nil
  end
  local title = string.format(L["map.route.leg"], stepAt[i] or i, RP.Name(step.from), RP.Name(step.to))
  return title,
    string.format(L["wmr.leg.tip"], L["map.mode." .. step.mode] or step.mode, TL.FormatDuration(step.sec or 0))
end

local function build(canvas)
  overlay = CreateFrame("Frame", "ForeverGuidesWorldMapRoute", canvas)
  overlay:SetPoint("TOPLEFT", canvas, "TOPLEFT")
  WML.TrackLevel(overlay, canvas, "waypoints", LEVEL_ABOVE_WAYPOINTS)
  ctl = MR.Attach({
    canvas = overlay,
    point = function(slug)
      local fx, fy = fractionOf(slug)
      if fx then
        return fx * overlay:GetWidth(), fy * overlay:GetHeight()
      end
    end,
    zone = function()
      return nil
    end,
    inZone = function()
      return true
    end,
    outside = function()
      return nil
    end,
    pathPoint = function(pt)
      local id = WML.MapID()
      local fx, fy = MR.MapPos(pt.uiMap, pt.x, pt.y, id)
      if fx then
        return fx * overlay:GetWidth(), fy * overlay:GetHeight()
      end
    end,
    redraw = function()
      WMR.Refresh()
    end,
    name = RP.Name,
    viewKey = function()
      return table.concat({ tostring(shown.map), tostring(shown.scale), tostring(WMR.rev or 0) }, ":")
    end,
    picking = function()
      return false
    end,
    legTip = legTip,
    hoverChanged = function() end,
    drop = function(_, fx, fy, i)
      local id = WML.MapID()
      local at = planAt[i]
      if not id then
        return false
      end
      local slug = TL.PointSlug(id, math.max(0, math.min(1, fx)), math.max(0, math.min(1, fy)))
      WMR.rev = (WMR.rev or 0) + 1
      local ok
      if at then
        ok = RP.Replace(at, slug)
      else
        ok = RP.SetStart(slug)
      end
      return ok == true
    end,
    pinClick = function(_, i, _, pin)
      if planAt[i] then
        WMR.OpenMenu(planAt[i], pin)
      elseif i == 1 and RP.State().start then
        RP.SetStart(nil)
      end
    end,
  })
end

local function clear()
  if ctl then
    ctl.SetRoute(nil)
    ctl.SetPlan(nil)
    ctl.Release()
  end
  if overlay then
    overlay:Hide()
  end
end

-- Draws the plan on the shown map.
function WMR.Draw()
  if not map or not ns.ProtectedAllowed(map) then
    return
  end
  local canvas = RP.Enabled() and map:IsShown() and WML.Canvas()
  local id = canvas and WML.MapID()
  local plan = id and RP.Plan()
  local st = RP.State()
  if not (id and #st.points > 0) then
    clear()
    return
  end
  if not overlay then
    build(canvas)
  end
  local scale = WML.CanvasScale()
  shown.map, shown.scale = id, math.floor(scale * 1000)
  overlay:SetScale(1 / scale)
  overlay:SetSize(canvas:GetWidth() * scale, canvas:GetHeight() * scale)
  overlay:Show()
  steps, stepAt = {}, {}
  if plan and plan.steps then
    steps, stepAt = WRL.StepsOnMap(plan.steps, RP.PositionOf, projector())
  end
  local slugs, at = WRL.PlanSlugs(st, plan, RP.StartSlug())
  planAt = at
  ctl.SetRoute(steps)
  ctl.SetPlan(slugs)
  ctl.Paint()
end

WMR.Refresh = ns.Wrap("wmr-refresh", function()
  WMR.rev = (WMR.rev or 0) + 1
  WMR.Draw()
end)

-- Click -------------------------------------------------------------------------------------------------

local function onCanvasClick(mouse, nx, ny)
  if
    not map
    or mouse ~= "LeftButton"
    or not RP.Enabled()
    or ns.CombatLocked()
    or not ns.Keys.Matches("mapRoutePoint")
  then
    return false
  end
  local id = WML.MapID()
  if not id then
    return false
  end
  if not (ns.WaypointLogic.readable(nx) and ns.WaypointLogic.readable(ny)) then
    local ok, cx, cy = pcall(map.GetNormalizedCursorPosition, map)
    nx, ny = ok and cx or nil, ok and cy or nil
  end
  if not (ns.WaypointLogic.readable(nx) and ns.WaypointLogic.readable(ny)) then
    return false
  end
  if RP.AddPoint(id, nx, ny) and ns.WorldMapRoutePanel then
    ns.WorldMapRoutePanel.SetOpen(true)
  end
  return true
end

WML.AddClickUse(onCanvasClick)

-- Switch of the setting.
function WMR.Apply()
  if RP.Enabled() then
    WMR.Refresh()
  else
    clear()
  end
  ns.Emit("FG_ROUTEPLAN_VIEW")
end

-- Debug and tests: the pins and lines drawn right now.
function WMR.Debug()
  return {
    overlay = overlay,
    ctl = ctl,
    steps = #steps,
    pins = planAt,
  }
end

function WMR.Attach()
  if map then
    return
  end
  map = WML.Map()
  if not map then
    return
  end
  WML.HookScript("route", "OnShow", WMR.Refresh)
  WML.HookScript("route", "OnHide", clear)
  WMR.Refresh()
end

ns.On("PLAYER_LOGIN", WMR.Attach)

ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_WorldMap" then
    WMR.Attach()
  end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  if map then
    WMR.Refresh()
  end
end)

ns.On("FG_WORLDMAP_VIEW", function(_, kind)
  if map and kind ~= "hide" then
    WMR.Refresh()
  end
end)

ns.On("FG_ROUTEPLAN_CHANGED", function()
  if map then
    WMR.Refresh()
  end
end)

ns.On("ZONE_CHANGED_NEW_AREA", function()
  if #RP.State().points > 0 and not RP.State().start then
    RP.Replan()
  end
end)
