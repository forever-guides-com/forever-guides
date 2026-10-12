-- The waypoint arrow: a small movable window with the title of the active waypoint, an
-- arrow that turns to the target, the distance and the walking time. Esc does not close
-- it. Look (background, opacity, auto-hiding title bar) comes from Modules/WindowStyle.lua,
-- plus two switches of this window: title bar and background can be turned off (then the
-- window is a HUD: the name moves small above the distance, text keeps a shadow). A gear
-- shows on hover and opens the appearance panel. Position and scale are saved in
-- ns.db.frames.waypointArrow and the waypoint settings.
-- The arrow is drawn with three Line objects, so it needs no texture file and rotates by
-- recomputing the end points (WaypointLogic.arrowSegments). Without lines, position or
-- facing the window shows the title and what it can, plus a hint.
local _, ns = ...
local W, L, Theme, U, WL, WP, WS = ns.W, ns.L, ns.Theme, ns.U, ns.WaypointLogic, ns.Waypoints, ns.WindowStyle

local WA = {}
ns.WaypointArrow = WA

local WIDTH, HEIGHT, HEAD_H = 170, 128, 18
local GFX, ARROW_SIZE = 56, 46
local UPDATE_EVERY = 0.1
local MENU_W, MENU_ROW = 196, 24
local GEAR_SIZE, GEAR_HIT = 16, 24
local GEAR_HIDE_DELAY = 0.15

-- Look defaults of this window kind: settings waypointWindowBg / Alpha / AutoHide / Title /
-- Background.
WS.PREFIX.waypoint = "waypointWindow"

ns.AddLocale("enUS", {
  ["wparrow.next"] = "Next waypoint",
  ["wparrow.prev"] = "Previous waypoint",
  ["wparrow.remove"] = "Remove this waypoint",
  ["wparrow.clear"] = "Remove all waypoints...",
  ["wparrow.list"] = "Open waypoint list",
  ["wparrow.settings"] = "Waypoint settings",
  ["wparrow.look"] = "Window appearance...",
  ["wparrow.lock"] = "Lock position",
  ["wparrow.unlock"] = "Unlock position",
  ["wparrow.hide"] = "Hide arrow",
  ["wparrow.gear"] = "Window settings",
  ["wparrow.showTitle"] = "Show title bar",
  ["wparrow.showTitleTip"] = "Without the title bar the name shows above the distance.",
  ["wparrow.showBackground"] = "Show background",
  ["wparrow.showBackgroundTip"] = "Hides background and frame.\nDrag anywhere to move.",
  ["wparrow.noPosition"] = "Your position cannot be read here.",
  ["wparrow.noDirection"] = "Direction not available here.",
  ["wparrow.farAway"] = "Other area: %s",
  ["wparrow.eta"] = "about %s",
  ["wparrow.tip"] = "Right click for the menu, drag to move.",
})
ns.AddLocale("deDE", {
  ["wparrow.next"] = "Nächster Wegpunkt",
  ["wparrow.prev"] = "Vorheriger Wegpunkt",
  ["wparrow.remove"] = "Diesen Wegpunkt entfernen",
  ["wparrow.clear"] = "Alle Wegpunkte entfernen...",
  ["wparrow.list"] = "Wegpunkt-Liste öffnen",
  ["wparrow.settings"] = "Wegpunkt-Einstellungen",
  ["wparrow.look"] = "Fenster-Aussehen...",
  ["wparrow.lock"] = "Position sperren",
  ["wparrow.unlock"] = "Position entsperren",
  ["wparrow.hide"] = "Pfeil ausblenden",
  ["wparrow.gear"] = "Fenster-Einstellungen",
  ["wparrow.showTitle"] = "Titelzeile anzeigen",
  ["wparrow.showTitleTip"] = "Ohne Titelzeile steht der Name klein über der Entfernung.",
  ["wparrow.showBackground"] = "Hintergrund anzeigen",
  ["wparrow.showBackgroundTip"] = "Blendet Fläche und Rahmen aus.\nFenster überall ziehbar.",
  ["wparrow.noPosition"] = "Deine Position lässt sich hier nicht lesen.",
  ["wparrow.noDirection"] = "Die Richtung ist hier nicht verfügbar.",
  ["wparrow.farAway"] = "Anderes Gebiet: %s",
  ["wparrow.eta"] = "etwa %s",
  ["wparrow.tip"] = "Rechtsklick öffnet das Menü, Ziehen verschiebt.",
})

local frame
local menu

local function frameDb()
  local frames = ns.db.frames
  if type(frames.waypointArrow) ~= "table" then
    frames.waypointArrow = {}
  end
  return frames.waypointArrow
end

local function place(f)
  local db = frameDb()
  f:ClearAllPoints()
  local s = f:GetScale()
  if WL.finite(db.x) and WL.finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
  end
end

local function savePosition(f)
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s, db = f:GetScale(), frameDb()
    db.x, db.y = left * s, top * s
  end
end

-- Look ---------------------------------------------------------------------------------------

-- A switch of this window: its own value, else the saved default, else off.
local function flag(own, default)
  if type(own) == "boolean" then
    return own
  end
  return default == true
end

function WA.Style()
  local per = WP.Settings().style
  local style = WS.Resolve("waypoint", per)
  local settings, prefix = ns.db.settings, WS.PREFIX.waypoint
  style.title = flag(per.title, settings[prefix .. "Title"])
  style.background = flag(per.background, settings[prefix .. "Background"])
  return style
end

-- Without the title bar the name sits small above the distance and the arrow moves up.
local function layout(f, title)
  f.bar:SetShown(title)
  f.name:SetShown(not title)
  f.gfx:ClearAllPoints()
  if title then
    f.gfx:SetPoint("TOP", f.bar, "BOTTOM", 0, -4)
  else
    f.gfx:SetPoint("TOP", f, "TOP", 0, -6)
  end
  f.dist:ClearAllPoints()
  f.dist:SetPoint("TOP", title and f.gfx or f.name, "BOTTOM", 0, -2)
end

local function applyLook(f)
  local style = WA.Style()
  -- Without a background the shared applier gets a fully transparent look: fill, title strip
  -- and (via WS.TextShadow) the text shadow follow, and the frame is taken out of its parts.
  local look = U.copy(style)
  if not style.background then
    look.alpha = 0
  end
  look.autoHide = style.autoHide and style.title
  WS.Apply(f, look, style.background and f.styleParts or f.hudParts)
  f.border.show(style.background)
  layout(f, style.title)
  local on = WS.TextShadow(look)
  local r, g, b = Theme.rgb("text")
  for _, fs in ipairs({ f.title, f.name, f.dist, f.info }) do
    WS.ApplyShadow(fs, on, r, g, b)
  end
  return style
end

-- patch: { bg = "rrggbb" | false, alpha = 0..1, autoHide = bool } from the appearance panel.
local function patchStyle(patch)
  local style = U.copy(WP.Settings().style)
  if patch.bg ~= nil then
    style.bg = patch.bg or nil
  end
  if patch.alpha ~= nil then
    style.alpha = patch.alpha
  end
  if patch.autoHide ~= nil then
    style.autoHide = patch.autoHide
  end
  WP.SetSetting("style", style)
end

-- The title and background switches of the appearance panel (WindowStyleUI opts.toggles).
local function flagToggle(key, labelKey)
  return {
    key = key,
    labelKey = labelKey,
    tipKey = labelKey .. "Tip",
    get = function()
      return WA.Style()[key]
    end,
    set = function(v)
      local style = U.copy(WP.Settings().style)
      style[key] = v
      WP.SetSetting("style", style)
    end,
  }
end

function WA.OpenLook()
  if not frame then
    return nil
  end
  return WS.OpenPanel(frame, {
    frame = frame,
    kind = "waypoint",
    get = WA.Style,
    set = patchStyle,
    toggles = { flagToggle("title", "wparrow.showTitle"), flagToggle("background", "wparrow.showBackground") },
    onSaveDefault = function()
      local style, prefix = WA.Style(), WS.PREFIX.waypoint
      WS.SaveDefault("waypoint", style)
      ns.Store.set("settings." .. prefix .. "Title", style.title)
      ns.Store.set("settings." .. prefix .. "Background", style.background)
    end,
    onReset = function()
      WP.SetSetting("style", {})
    end,
  })
end

-- Painting -------------------------------------------------------------------------------------

local function setArrow(f, angle, colorName)
  local lines = f.lines
  if not (lines and angle) then
    for _, line in ipairs(lines or {}) do
      line:Hide()
    end
    return
  end
  local r, g, b = Theme.rgb(colorName)
  for i, seg in ipairs(WL.arrowSegments(angle, ARROW_SIZE)) do
    local line = lines[i]
    line:SetColorTexture(r, g, b, 1)
    line:SetStartPoint("CENTER", f.gfx, seg[1], seg[2])
    line:SetEndPoint("CENTER", f.gfx, seg[3], seg[4])
    line:Show()
  end
end

local function setText(fs, text)
  if fs.fgShown ~= text then
    fs.fgShown = text
    fs:SetText(text)
  end
end

-- One refresh of title, distance, hint and arrow from the current position.
function WA.Update()
  local f = frame
  local wp = WP.Active()
  if not (f and wp) then
    return
  end
  setText(f.title, wp.title)
  setText(f.name, wp.title)
  local map, x, y = WP.PlayerPosition()
  local yards = map and WL.distanceYards(map, x, y, wp.map, wp.x, wp.y) or nil
  local facing = WP.Facing()
  local bearing = map and WL.bearing(map, x, y, wp.map, wp.x, wp.y) or nil
  local angle = bearing and facing and f.lines and WL.relativeAngle(bearing, facing) or nil
  setArrow(f, angle, wp.color)
  if yards then
    setText(f.dist, WL.formatDistance(yards, ns.GetActiveLocale()))
    local eta = string.format(L["wparrow.eta"], WL.formatEta(WL.etaSeconds(yards)))
    setText(f.info, angle and eta or (eta .. "\n" .. L["wparrow.noDirection"]))
  elseif not map then
    setText(f.dist, "")
    setText(f.info, L["wparrow.noPosition"])
  else
    setText(f.dist, "")
    setText(f.info, string.format(L["wparrow.farAway"], WP.MapName(wp.map)))
  end
end

-- Menu -----------------------------------------------------------------------------------------------

local function menuOpen()
  local layer = ns.Desktop.Layer
  return layer.current ~= nil and layer.current.owner == frame and menu ~= nil and menu:IsShown()
end

local function closeMenu()
  if menuOpen() then
    ns.Desktop.Layer.close("api")
  end
end

local function moveMenuFocus(step)
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
      key = "wparrow.next",
      run = function()
        WP.Next()
      end,
    },
    {
      key = "wparrow.prev",
      run = function()
        WP.Previous()
      end,
    },
    {
      key = "wparrow.remove",
      run = function()
        local wp = WP.Active()
        if wp then
          WP.Remove(wp.id)
        end
      end,
    },
    {
      key = "wparrow.clear",
      run = function()
        ns.WaypointList.ConfirmClear()
      end,
    },
    {
      key = "wparrow.list",
      run = function()
        ns.WaypointList.Open()
      end,
    },
    {
      key = "wparrow.settings",
      run = function()
        ns.WaypointList.Open("settings")
      end,
    },
    {
      key = "wparrow.look",
      run = function()
        WA.OpenLook()
      end,
    },
    {
      key = "wparrow.lock",
      lockToggle = true,
      run = function()
        WP.SetSetting("locked", not WP.Settings().locked)
      end,
    },
    {
      key = "wparrow.hide",
      run = function()
        WP.SetSetting("arrow", false)
      end,
    },
  }
end

local function buildMenu()
  local p = ns.Desktop.Layer.newPopup("surface2")
  local items = menuItems()
  p.buttons = {}
  for i, item in ipairs(items) do
    local b = W.Button(p, {
      key = item.key,
      variant = "ghost",
      width = MENU_W,
      height = MENU_ROW,
      onClick = function()
        ns.Desktop.Layer.close("select")
        item.run()
      end,
    })
    b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * MENU_ROW)
    b.item = item
    p.buttons[i] = b
  end
  p:SetSize(MENU_W + 4, #items * MENU_ROW + 4)
  p:EnableKeyboard(true)
  p:SetScript("OnKeyDown", function(self, key)
    local handled = true
    if key == "ESCAPE" then
      ns.Desktop.Layer.close("escape")
    elseif key == "UP" or key == "DOWN" then
      moveMenuFocus(key == "DOWN" and 1 or -1)
    elseif key == "ENTER" or key == "SPACE" then
      ns.Focus.activate()
    else
      handled = false
    end
    if self.SetPropagateKeyboardInput then
      pcall(self.SetPropagateKeyboardInput, self, not handled)
    end
  end)
  return p
end

function WA.OpenMenu()
  if not frame then
    return
  end
  if menuOpen() then
    closeMenu()
    return
  end
  menu = menu or buildMenu()
  for _, b in ipairs(menu.buttons) do
    if b.item.lockToggle then
      W.SetText(b.label, WP.Settings().locked and "wparrow.unlock" or "wparrow.lock")
    end
  end
  local layer = ns.Desktop.Layer
  layer.open({
    frames = { menu },
    owner = frame,
    move = moveMenuFocus,
  })
  layer.place(menu, frame, "TOPLEFT", "BOTTOMLEFT", 0, -2)
  menu:Show()
  ns.Focus.set(menu.buttons[1])
end

-- Window ------------------------------------------------------------------------------------------------

local function mouseOver(o)
  if o.IsMouseOver then
    return o:IsMouseOver() == true
  end
  local legacy = rawget(_G, "MouseIsOver")
  return legacy ~= nil and legacy(o) == true
end

-- The gear shows while the mouse is over the window (or its gear, or a panel of it is open)
-- and goes away after a short delay, so crossing from the window onto the gear never flickers.
local function gearTick(f, dt)
  local gear = f.gear
  if mouseOver(f) or mouseOver(gear) or WS.PanelOpenFor(f) or menuOpen() then
    f.gearIdle = 0
    gear:Show()
  elseif gear:IsShown() then
    f.gearIdle = (f.gearIdle or 0) + dt
    if f.gearIdle >= GEAR_HIDE_DELAY then
      gear:Hide()
    end
  end
end

local function create()
  local f = CreateFrame("Frame", "FGWaypointArrow", UIParent)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.border = W.Border(f, "white", 0.4)

  f.bar = CreateFrame("Frame", nil, f)
  f.bar:SetPoint("TOPLEFT")
  f.bar:SetPoint("TOPRIGHT")
  f.bar:SetHeight(HEAD_H)
  f.barBg = f.bar:CreateTexture(nil, "BACKGROUND")
  f.barBg:SetAllPoints()
  f.barBg:SetColorTexture(0.04, 0.04, 0.04, 0.88)
  f.title = W.Text(f.bar, { role = "micro", justify = "CENTER" })
  -- Room left and right of the title for the gear.
  f.title:SetPoint("LEFT", GEAR_HIT + 4, 0)
  f.title:SetPoint("RIGHT", -(GEAR_HIT + 4), 0)

  f.gfx = CreateFrame("Frame", nil, f)
  f.gfx:SetSize(GFX, GFX)
  f.gfx:SetPoint("TOP", f.bar, "BOTTOM", 0, -4)
  if ns.can.lineObject then
    f.lines = {}
    for i = 1, 3 do
      local line = f.gfx:CreateLine(nil, "ARTWORK")
      line:SetThickness(3)
      line:Hide()
      f.lines[i] = line
    end
  end

  f.name = W.Text(f, { role = "micro", color = "textSecondary", justify = "CENTER" })
  f.name:SetPoint("TOP", f.gfx, "BOTTOM", 0, -2)
  f.name:SetWidth(WIDTH - 12)
  f.name:Hide()
  f.dist = W.Text(f, { role = "h3", family = "heading", justify = "CENTER" })
  f.dist:SetPoint("TOP", f.gfx, "BOTTOM", 0, -2)
  f.dist:SetWidth(WIDTH - 12)
  f.info = W.Text(f, { role = "micro", color = "textSecondary", justify = "CENTER", wrap = true })
  f.info:SetPoint("TOP", f.dist, "BOTTOM", 0, -2)
  f.info:SetWidth(WIDTH - 12)

  f.styleParts = {
    bg = { f.bg },
    bars = { f.barBg },
    border = f.border,
    chrome = { f.bar },
    busy = function()
      return menuOpen() or WS.PanelOpenFor(f) or WS.PickerOpenFor(f)
    end,
  }
  -- Without a background the frame is not part of the look.
  f.hudParts = {}
  for key, value in pairs(f.styleParts) do
    f.hudParts[key] = value
  end
  f.hudParts.border = nil

  f.gear = W.Action(f, {
    icon = "gear",
    size = GEAR_HIT,
    iconSize = GEAR_SIZE,
    tooltip = "wparrow.gear",
    onClick = function()
      WA.OpenLook()
    end,
  })
  f.gear:SetPoint("TOPRIGHT", -2, -2)
  f.gear:SetFrameLevel(f:GetFrameLevel() + 10)
  f.gear:Hide()

  f:SetScript("OnDragStart", function()
    if not WP.Settings().locked then
      WS.Hold(f, "move", true)
      f:StartMoving()
    end
  end)
  f:SetScript(
    "OnDragStop",
    ns.Wrap("waypoint-arrow-move", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "move", false)
      savePosition(f)
    end)
  )
  f:SetScript(
    "OnMouseUp",
    ns.Wrap("waypoint-arrow-menu", function(_, button)
      if button == "RightButton" then
        WA.OpenMenu()
      end
    end)
  )
  f:SetScript("OnEnter", function(self)
    self.gearIdle = 0
    self.gear:Show()
    local wp = WP.Active()
    if wp then
      local text = string.format("%s (%s)", WP.MapName(wp.map), WL.coordText(wp.x, wp.y))
      if wp.note ~= "" then
        text = text .. "\n" .. wp.note
      end
      ns.ShowTooltip(self, wp.title, text .. "\n" .. L["wparrow.tip"])
    end
  end)
  f:SetScript("OnLeave", ns.HideTooltip)
  local acc = 0
  f:SetScript("OnShow", function()
    acc = UPDATE_EVERY
    f:SetScript("OnUpdate", function(_, elapsed)
      gearTick(f, elapsed)
      acc = acc + elapsed
      if acc >= UPDATE_EVERY then
        acc = 0
        ns.Safe("waypoint-arrow", WA.Update)
      end
    end)
  end)
  f:SetScript("OnHide", function()
    f:SetScript("OnUpdate", nil)
    f.gear:Hide()
    closeMenu()
  end)
  f:Hide()
  return f
end

function WA.IsShown()
  return frame ~= nil and frame:IsShown()
end

function WA.Frame()
  return frame
end

-- Shows the arrow while the setting is on and a waypoint is active, hides it otherwise.
function WA.Refresh()
  if not ns.db then
    return
  end
  local settings = WP.Settings()
  local show = settings.arrow and WP.Active() ~= nil
  if show and not frame then
    frame = create()
  end
  if not frame then
    return
  end
  if show then
    frame:SetScale(settings.scale)
    place(frame)
    applyLook(frame)
    frame:Show()
    WA.Update()
  else
    frame:Hide()
  end
end

ns.On("FG_WAYPOINTS_CHANGED", function()
  WA.Refresh()
end)
ns.On("FG_UI_REFRESHED", function()
  if frame and frame:IsShown() then
    WA.Refresh()
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if frame and frame:IsShown() and WS.AffectsKind(path, "waypoint") then
    applyLook(frame)
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    savePosition(frame)
  end
end)
ns.On("PLAYER_LOGIN", function()
  WA.Refresh()
end)
