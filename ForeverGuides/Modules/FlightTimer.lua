-- The flight timer: a small movable window with the remaining flight time, shown from the moment a
-- flight starts until the landing. The flight is seen through a post-hook on TakeTaxiNode (nothing
-- of Blizzard's is replaced), its end through UnitOnTaxi. Look and behaviour sit in
-- settings.flightTimerWindow (title, background, bar, "approx.", lock, font size, scale, bar), the
-- position in ns.db.frames.flightTimer. A gear shows on hover and opens the settings panel.
-- The state machine and the measurement of the route live in Modules/FlightTimerLogic.lua.
local _, ns = ...
local W, L, Theme, U, WS = ns.W, ns.L, ns.Theme, ns.U, ns.WindowStyle
local FL, FR, FT = ns.FlightLogic, ns.FlightRoute, ns.FlightTimerLogic

local FTI = {}
ns.FlightTimer = FTI

ns.AddLocale("enUS", {
  ["flighttimer.enable"] = "Show flight timer during flights",
  ["flighttimer.gear"] = "Timer settings",
  ["flighttimer.panelTitle"] = "Flight timer",
  ["flighttimer.showTitle"] = "Show destination",
  ["flighttimer.showBackground"] = "Show background",
  ["flighttimer.showBar"] = "Show progress bar",
  ["flighttimer.approx"] = 'Show "approx."',
  ["flighttimer.lock"] = "Lock position",
  ["flighttimer.fontSize"] = "Font size",
  ["flighttimer.scale"] = "Scale",
  ["flighttimer.barHeight"] = "Bar height",
  ["flighttimer.barColor"] = "Bar color",
  ["flighttimer.example"] = "Example flight",
  ["flighttimer.previewOn"] = "Example flight (every 60 s). End: /fg flighttimer",
  ["flighttimer.previewOff"] = "Example flight ended.",
  ["flighttimer.busy"] = "A real flight is running right now.",
})
ns.AddLocale("deDE", {
  ["flighttimer.enable"] = "Flug-Timer während des Fluges anzeigen",
  ["flighttimer.gear"] = "Timer-Einstellungen",
  ["flighttimer.panelTitle"] = "Flug-Timer",
  ["flighttimer.showTitle"] = "Ziel anzeigen",
  ["flighttimer.showBackground"] = "Hintergrund anzeigen",
  ["flighttimer.showBar"] = "Fortschrittsbalken anzeigen",
  ["flighttimer.approx"] = 'Zeiten mit "ca."',
  ["flighttimer.lock"] = "Position sperren",
  ["flighttimer.fontSize"] = "Schriftgröße",
  ["flighttimer.scale"] = "Skalierung",
  ["flighttimer.barHeight"] = "Balkenhöhe",
  ["flighttimer.barColor"] = "Balkenfarbe",
  ["flighttimer.example"] = "Beispielflug",
  ["flighttimer.previewOn"] = "Beispielflug (alle 60 s). Beenden: /fg flugtimer",
  ["flighttimer.previewOff"] = "Beispielflug beendet.",
  ["flighttimer.busy"] = "Gerade läuft ein echter Flug.",
})

local HEAD_H, PAD = 18, 8
local MIN_WIDTH, INFO_H = 170, 14
local UPDATE_EVERY = 0.1
local PREVIEW_SECONDS = 60
local BG_HEX, BG_ALPHA = "1a1a1a", 0.92
local GEAR_SIZE, GEAR_HIT = 16, 24
local GEAR_HIDE_DELAY = 0.15
local PANEL_W, ROW_GAP = 296, 6
local LIMITS = { fontSize = { 14, 64 }, scale = { 0.5, 2 }, barHeight = { 4, 24 } }

local state = FT.new()
local frame, panel, tracker
local hooked = false

local function nowSeconds()
  return type(GetTime) == "function" and GetTime() or 0
end

local function onTaxi()
  local fn = rawget(_G, "UnitOnTaxi")
  if type(fn) ~= "function" then
    return false
  end
  local ok, value = pcall(fn, "player")
  return ok and value and true or false
end

-- Settings -----------------------------------------------------------------------------------------

local function enabled()
  return not ns.db or ns.db.settings.flightTimer ~= false
end

-- The window settings, every field validated against the defaults.
function FTI.Config()
  local defaults = ns.Store.defaults.settings.flightTimerWindow
  local raw = ns.db and ns.db.settings.flightTimerWindow
  raw = type(raw) == "table" and raw or {}
  local cfg = {}
  for _, key in ipairs({ "title", "background", "bar", "approx", "locked" }) do
    local v = raw[key]
    if type(v) ~= "boolean" then
      v = defaults[key]
    end
    cfg[key] = v
  end
  for key, range in pairs(LIMITS) do
    local v = tonumber(raw[key])
    cfg[key] = U.clamp((v and v == v) and v or defaults[key], range[1], range[2])
  end
  cfg.barColor = WS.cleanHex(raw.barColor, defaults.barColor)
  return cfg
end

local function setConfig(key, value)
  ns.Store.set("settings.flightTimerWindow." .. key, value)
end

-- Position ---------------------------------------------------------------------------------------------

local function frameDb()
  local frames = ns.db.frames
  if type(frames.flightTimer) ~= "table" then
    frames.flightTimer = {}
  end
  return frames.flightTimer
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function place(f)
  local db = frameDb()
  f:ClearAllPoints()
  local s = f:GetScale()
  if finite(db.x) and finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -230)
  end
end

local function savePosition(f)
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s, db = f:GetScale(), frameDb()
    db.x, db.y = left * s, top * s
  end
end

-- Painting -------------------------------------------------------------------------------------------

local function setText(fs, text)
  if fs.fgShown ~= text then
    fs.fgShown = text
    fs:SetText(text)
  end
end

local function timeFont(fs)
  for _, file in ipairs(Theme.fontFiles.heading) do
    if fs:SetFont(file, FTI.Config().fontSize, "") then
      break
    end
  end
  fs:SetTextColor(Theme.color("text"))
end

-- The part before the comma: "Orgrimmar, Durotar" shows as "Orgrimmar".
local function destination(name)
  return type(name) == "string" and (name:match("^%s*([^,]-)%s*,") or name) or ""
end

-- Size and anchors follow the switches and the font size; the hint row only exists while it has text.
local function layout(f, cfg, hasHint)
  local width = math.max(MIN_WIDTH, math.floor(cfg.fontSize * 6) + 2 * PAD)
  local y = cfg.title and (HEAD_H + 4) or 6
  f.bar:SetShown(cfg.title)
  f.time:ClearAllPoints()
  f.time:SetPoint("TOP", f, "TOP", 0, -y)
  f.time:SetSize(width - 2 * PAD, cfg.fontSize + 6)
  y = y + cfg.fontSize + 6
  f.info:ClearAllPoints()
  f.info:SetPoint("TOP", f, "TOP", 0, -y)
  f.info:SetSize(width - 2 * PAD, INFO_H)
  f.info:SetShown(hasHint)
  if hasHint then
    y = y + INFO_H
  end
  f.status:SetShown(cfg.bar)
  if cfg.bar then
    f.status:ClearAllPoints()
    f.status:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(y + 2))
    f.status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(y + 2))
    f.status:SetHeight(cfg.barHeight)
    y = y + 2 + cfg.barHeight
  end
  f:SetSize(width, y + PAD)
end

local function applyLook(f, cfg)
  f.cfg = cfg
  f.bg:SetShown(cfg.background)
  f.barBg:SetShown(cfg.background)
  f.border.show(cfg.background)
  layout(f, cfg, f.hasHint == true)
  timeFont(f.time)
  -- Without a background the text keeps a shadow, so it stays readable on any scene.
  local r, g, b = Theme.rgb("text")
  for _, fs in ipairs({ f.title, f.time, f.info }) do
    WS.ApplyShadow(fs, not cfg.background, r, g, b)
  end
  f.fill:SetColorTexture(U.hex(cfg.barColor))
end

function FTI.Paint(snap)
  local f = frame
  snap = snap or FT.snapshot(state, nowSeconds())
  if not (f and f.cfg and snap) then
    return
  end
  setText(f.title, destination(snap.name))
  setText(f.time, FT.timeText(snap, f.cfg.approx))
  local hint = FT.hint(snap)
  if (hint ~= nil) ~= f.hasHint then
    f.hasHint = hint ~= nil
    layout(f, f.cfg, f.hasHint)
  end
  setText(f.info, hint or "")
  -- The bar runs empty; without a known duration there is nothing to run down.
  f.status:SetValue(snap.known and (1 - snap.progress) or 0)
end

-- Settings panel ---------------------------------------------------------------------------------------

local function panelOpen()
  return panel ~= nil and panel:IsShown() == true
end

local function closePanel()
  if panelOpen() then
    ns.Desktop.Layer.close("api")
  end
end

local function buildPanel()
  local p = ns.Desktop.Layer.newPopup("surface2")
  p.widgets = {}
  local title = W.Text(p, { key = "flighttimer.panelTitle", role = "h3", family = "heading", color = "accent2" })
  title:SetPoint("TOPLEFT", 12, -12)
  p.close = W.CloseButton(p)
  local last = CreateFrame("Frame", nil, p)
  last:SetHeight(1)
  last:SetPoint("TOPLEFT", 12, -(12 + 18 + 8))
  last:SetPoint("TOPRIGHT", -12, -(12 + 18 + 8))
  local height = 12 + 18 + 8 + 1
  local function add(widget, rowHeight)
    widget:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -ROW_GAP)
    widget:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -ROW_GAP)
    last = widget
    height = height + rowHeight + ROW_GAP
    p.widgets[#p.widgets + 1] = widget
  end
  for _, def in ipairs({
    { "title", "flighttimer.showTitle" },
    { "background", "flighttimer.showBackground" },
    { "bar", "flighttimer.showBar" },
    { "approx", "flighttimer.approx" },
    { "locked", "flighttimer.lock" },
  }) do
    add(
      W.Toggle(p, {
        key = def[2],
        get = function()
          return FTI.Config()[def[1]]
        end,
        set = function(v)
          setConfig(def[1], v)
        end,
      }),
      24
    )
  end
  for _, def in ipairs({
    { "fontSize", "flighttimer.fontSize", 2, tostring },
    {
      "scale",
      "flighttimer.scale",
      0.05,
      function(v)
        return string.format("%d %%", math.floor(v * 100 + 0.5))
      end,
      "release",
    },
    { "barHeight", "flighttimer.barHeight", 1, tostring },
  }) do
    add(
      W.Slider(p, {
        key = def[2],
        min = LIMITS[def[1]][1],
        max = LIMITS[def[1]][2],
        step = def[3],
        applyOn = def[5],
        get = function()
          return FTI.Config()[def[1]]
        end,
        set = function(v)
          setConfig(def[1], v)
        end,
        format = def[4],
      }),
      42
    )
  end
  local color = W.Action(p, {
    label = "act.pick",
    icon = "palette",
    tooltip = "flighttimer.barColor",
    variant = "ghost",
    height = 26,
    onClick = function()
      WS.OpenPalette(p.color, FTI.Config().barColor, function(hex)
        setConfig("barColor", WS.cleanHex(hex, ns.Store.defaults.settings.flightTimerWindow.barColor))
        p.color:Refresh()
      end, frame)
    end,
  })
  color.label:ClearAllPoints()
  color.label:SetPoint("LEFT", 0, 0)
  local chip = CreateFrame("Frame", nil, color)
  chip:SetSize(22, 18)
  chip:SetPoint("RIGHT", 0, 0)
  chip.tex = chip:CreateTexture(nil, "ARTWORK")
  chip.tex:SetAllPoints()
  W.Border(chip, "white", 0.4)
  function color:Refresh()
    chip.tex:SetColorTexture(U.hex(FTI.Config().barColor))
  end
  p.color = color
  add(color, 26)
  p:SetSize(PANEL_W, height + 12)
  return p
end

function FTI.OpenSettings()
  if not frame then
    return nil
  end
  local layer = ns.Desktop.Layer
  if panelOpen() then
    closePanel()
    return nil
  end
  panel = panel or buildPanel()
  layer.open({ frames = { panel }, owner = frame })
  layer.place(panel, frame, "TOPRIGHT", "BOTTOMRIGHT", 0, -2)
  panel:Show()
  for _, widget in ipairs(panel.widgets) do
    widget:Refresh()
  end
  return panel
end

-- Window -------------------------------------------------------------------------------------------------

local function mouseOver(o)
  if o.IsMouseOver then
    return o:IsMouseOver() == true
  end
  local legacy = rawget(_G, "MouseIsOver")
  return legacy ~= nil and legacy(o) == true
end

-- Same hover rule as the waypoint arrow: the gear stays a moment so crossing onto it never flickers.
local function gearTick(f, dt)
  local gear = f.gear
  if mouseOver(f) or mouseOver(gear) or panelOpen() then
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
  local f = CreateFrame("Frame", "FGFlightTimer", UIParent)
  f:SetSize(MIN_WIDTH, 60)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  local r, g, b = U.hex(BG_HEX)
  f.bg:SetColorTexture(r, g, b, BG_ALPHA)
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

  f.time = f:CreateFontString(nil, "OVERLAY")
  f.time:SetJustifyH("CENTER")
  f.time:SetJustifyV("MIDDLE")
  ns.Bind(f.time, timeFont)
  f.info = W.Text(f, { role = "micro", color = "textSecondary", justify = "CENTER" })

  f.status = CreateFrame("StatusBar", nil, f)
  f.status:SetMinMaxValues(0, 1)
  f.status:SetValue(0)
  f.statusBack = f.status:CreateTexture(nil, "BACKGROUND")
  f.statusBack:SetAllPoints()
  f.statusBack:SetColorTexture(0, 0, 0, 0.45)
  f.fill = f.status:CreateTexture(nil, "ARTWORK")
  f.fill:SetColorTexture(1, 1, 1, 1)
  f.status:SetStatusBarTexture(f.fill)

  f.gear = W.Action(f, {
    icon = "gear",
    size = GEAR_HIT,
    iconSize = GEAR_SIZE,
    tooltip = "flighttimer.gear",
    onClick = function()
      FTI.OpenSettings()
    end,
  })
  f.gear:SetPoint("TOPRIGHT", -2, -2)
  f.gear:SetFrameLevel(f:GetFrameLevel() + 10)
  f.gear:Hide()

  f:SetScript("OnDragStart", function()
    if not FTI.Config().locked then
      f:StartMoving()
    end
  end)
  f:SetScript(
    "OnDragStop",
    ns.Wrap("flight-timer-move", function()
      f:StopMovingOrSizing()
      savePosition(f)
    end)
  )
  f:SetScript("OnEnter", function(self)
    self.gearIdle = 0
    self.gear:Show()
  end)
  f:SetScript("OnShow", function()
    f:SetScript("OnUpdate", function(_, elapsed)
      gearTick(f, elapsed)
    end)
  end)
  f:SetScript("OnHide", function()
    f:SetScript("OnUpdate", nil)
    f.gear:Hide()
    closePanel()
  end)
  f:Hide()
  return f
end

function FTI.Frame()
  return frame
end

function FTI.IsShown()
  return frame ~= nil and frame:IsShown() == true
end

function FTI.State()
  return state
end

function FTI.Tracker()
  return tracker
end

-- Shows the window while a confirmed flight (or the example) runs and the setting allows it.
function FTI.Refresh()
  if not ns.db then
    return
  end
  local snap = FT.snapshot(state, nowSeconds())
  local show = snap ~= nil and snap.confirmed and (enabled() or snap.preview)
  if show and not frame then
    frame = create()
  end
  if not frame then
    return
  end
  if show then
    local cfg = FTI.Config()
    frame:SetScale(cfg.scale)
    place(frame)
    applyLook(frame, cfg)
    frame:Show()
    FTI.Paint(snap)
  else
    frame:Hide()
  end
end

-- Flight ---------------------------------------------------------------------------------------------------

local function stopTracking()
  if tracker then
    tracker:SetScript("OnUpdate", nil)
  end
end

local function startTracking()
  tracker = tracker or CreateFrame("Frame", nil, UIParent)
  local acc = 0
  tracker:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc >= UPDATE_EVERY then
      acc = 0
      ns.Safe("flight-timer", FTI.Tick)
    end
  end)
end

-- One step of the running flight: follows the taxi flag, then paints (or shows/hides the window when
-- the flight just got confirmed or ended). Returns what FlightTimerLogic.tick returned.
function FTI.Tick()
  local event, seconds, recorded = FT.tick(state, nowSeconds(), onTaxi())
  if not FT.flying(state) then
    stopTracking()
  end
  local snap = FT.snapshot(state, nowSeconds())
  local want = snap ~= nil and snap.confirmed and (enabled() or snap.preview) and true or false
  if want ~= FTI.IsShown() then
    FTI.Refresh()
  else
    FTI.Paint(snap)
  end
  return event, seconds, recorded
end

local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  return ok and value or nil
end

-- Called after the game took the flight to `slot`: destination name, route key and expected time.
function FTI.OnTake(slot)
  if type(rawget(_G, "UnitOnTaxi")) ~= "function" then
    return
  end
  local info = { name = try(rawget(_G, "TaxiNodeName"), slot) }
  local route = FR.Route(slot)
  if route then
    local pairsOfNodes = {}
    for i, hop in ipairs(route.hops) do
      pairsOfNodes[i] = { from = hop.fromNode, to = hop.toNode }
    end
    info.key = FL.routeKey(pairsOfNodes)
    info.expected, info.approx = FT.expected(route.total)
  end
  FT.start(state, nowSeconds(), info)
  startTracking()
  FTI.Refresh()
end

-- Hooks TakeTaxiNode once the game has it (a post-hook: the flight itself is never touched).
function FTI.Install()
  if not hooked and type(hooksecurefunc) == "function" and type(rawget(_G, "TakeTaxiNode")) == "function" then
    hooked = pcall(hooksecurefunc, "TakeTaxiNode", function(slot)
      ns.Safe("flight-timer-take", FTI.OnTake, slot)
    end)
  end
  return hooked
end

-- /fg flugtimer: an example flight of 60 seconds that repeats, to set up the look without flying.
function FTI.TogglePreview()
  if FT.flying(state) and state.preview then
    FT.cancel(state)
    stopTracking()
    FTI.Refresh()
    ns.Notify(L["flighttimer.previewOff"], "info")
    return false
  end
  if FT.flying(state) then
    ns.Notify(L["flighttimer.busy"], "info")
    return nil
  end
  FT.start(state, nowSeconds(), {
    name = L["flighttimer.example"],
    expected = PREVIEW_SECONDS,
    approx = true,
    preview = true,
  })
  startTracking()
  FTI.Refresh()
  ns.Notify(L["flighttimer.previewOn"], "info")
  return true
end

ns.On("PLAYER_LOGIN", function()
  FTI.Install()
end)
ns.On("TAXIMAP_OPENED", function()
  FTI.Install()
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.flightTimer") then
    FTI.Refresh()
  end
end)
ns.On("FG_UI_REFRESHED", function()
  if FTI.IsShown() then
    FTI.Refresh()
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if FTI.IsShown() then
    savePosition(frame)
  end
end)
