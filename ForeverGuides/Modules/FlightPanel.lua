-- Settings panel at the classic flight window (TaxiFrame): a side tab outside the right edge (opens the map page) and a
-- button with logo and text in the top right corner of the map open a small panel below the button
-- with the font size of the flight times, the two switches and a link to the settings page. The values are the ones of the settings page (Store, settings.flight*).
-- Button, panel and the key listener are our own child frames of TaxiFrame, nothing is written into
-- a Blizzard table. Tab (pointer over the window), Enter or Space and Esc work without the mouse.
local _, ns = ...
local W, Store = ns.W, ns.Store
local FB = ns.FlightLabels

local P = {}
ns.FlightPanel = P

ns.AddLocale("enUS", {
  ["flightpanel.open"] = "Forever Guides: Settings",
  ["flightpanel.tab"] = "Forever Guides: Map",
  ["flightpanel.tab.tip"] = "Opens the map area of the addon.",
  ["flightpanel.settings"] = "Settings",
  ["flightpanel.title"] = "Flight time",
  ["flightpanel.all"] = "All settings",
})
ns.AddLocale("deDE", {
  ["flightpanel.open"] = "Forever Guides: Einstellungen",
  ["flightpanel.tab"] = "Forever Guides: Karte",
  ["flightpanel.tab.tip"] = "Öffnet den Karten-Bereich des Addons.",
  ["flightpanel.settings"] = "Einstellungen",
  ["flightpanel.title"] = "Flugdauer",
  ["flightpanel.all"] = "Alle Einstellungen",
})

local LOGO = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png"
local TAB_INSET, TAB_DROP = 4, 36 -- side tab: outside the right edge, below the title bar
local BUTTON_WIDTH, BUTTON_HEIGHT, ICON_SIZE, MARGIN = 140, 26, 18, 8
local WIDTH, HEIGHT, PAD = 260, 182, 12
local LEVEL = 20

local built -- { taxi, button, panel, ring, controls, items }
local focus -- the frame the keyboard ring is on

local function setFocus(frame)
  focus = frame
  local ring = built.ring
  ring:ClearAllPoints()
  ring:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
  ring:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
  ring:Show()
end

local function clearFocus()
  focus = nil
  if built then
    built.ring:Hide()
  end
end

function P.Close()
  if not built then
    return
  end
  built.panel:Hide()
  if focus and focus ~= built.button then
    setFocus(built.button)
  end
end

function P.Toggle()
  if not built then
    return
  end
  if built.panel:IsShown() then
    P.Close()
  else
    built.panel:Show()
  end
end

-- The side tab opens the map page of the addon; the settings panel stays with the button.
function P.OpenMap()
  if built and ns.Main and ns.Main.Show then
    ns.Main.Show("map")
    ns.BlizzardLinks.RaiseMain(built.taxi)
  end
end

-- The frames of the panel for the tests: { tab, button, panel, ring, slider, labels, tooltip, all, items }.
function P.Parts()
  return built
end

function P.IsOpen()
  return built ~= nil and built.panel:IsShown() == true
end

-- Frames that take part in the keyboard walk, the panel ones only while it is open.
local function walk()
  local list = {}
  for _, frame in ipairs(built.items) do
    if frame:IsVisible() then
      list[#list + 1] = frame
    end
  end
  return list
end

local function move(step)
  local list = walk()
  local index = 0
  for i, frame in ipairs(list) do
    if frame == focus then
      index = i
    end
  end
  index = index + step
  if index < 1 then
    index = #list
  elseif index > #list then
    index = 1
  end
  setFocus(list[index])
end

local function onKey(self, key)
  local handled = false
  if key == "ESCAPE" then
    if built.panel:IsShown() or focus then
      P.Close()
      clearFocus()
      handled = true
    end
  elseif focus or (key == "TAB" and built.taxi:IsMouseOver()) then
    if key == "TAB" then
      move(IsShiftKeyDown and IsShiftKeyDown() and -1 or 1)
      handled = true
    elseif focus and (key == "UP" or key == "DOWN") then
      move(key == "UP" and -1 or 1)
      handled = true
    elseif focus and (key == "ENTER" or key == "SPACE") then
      if focus == built.tab then
        P.OpenMap()
      elseif focus.Click and focus ~= built.slider then
        focus:Click()
      end
      handled = true
    elseif focus and (key == "LEFT" or key == "RIGHT") and focus.fgArrow then
      focus:fgArrow(key == "LEFT" and -1 or 1)
      handled = true
    end
  end
  pcall(self.SetPropagateKeyboardInput, self, not handled)
end

local function toggleRow(panel, key, labelKey, y)
  local row = W.Toggle(panel, {
    key = labelKey,
    get = function()
      return FB.Option(key)
    end,
    set = function(v)
      Store.set("settings." .. key, v)
    end,
  })
  row:SetPoint("TOPLEFT", PAD, y)
  row:SetPoint("TOPRIGHT", -PAD, y)
  return row
end

local function build(taxi)
  local level = taxi:GetFrameLevel() + LEVEL
  local tab = ns.BlizzardLinks.CreateSideTab(taxi, {
    key = "flightpanel.tab",
    tip = "flightpanel.tab.tip",
    onClick = P.OpenMap,
    x = TAB_INSET,
    y = -TAB_DROP,
  })

  local button = W.Button(taxi, {
    key = "flightpanel.settings",
    variant = "gold",
    width = BUTTON_WIDTH,
    height = BUTTON_HEIGHT,
    tooltip = "flightpanel.open",
    onClick = P.Toggle,
  })
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetSize(ICON_SIZE, ICON_SIZE)
  button.icon:SetPoint("LEFT", 6, 0)
  button.icon:SetTexture(LOGO)
  button.label:SetJustifyH("LEFT")
  button.label:SetMaxLines(1)
  button.label:ClearAllPoints()
  button.label:SetPoint("LEFT", button.icon, "RIGHT", 6, 0)
  button.label:SetPoint("RIGHT", -6, 0)
  -- The width follows the word, so "Einstellungen" is never cut off in either language.
  ns.Bind(button, function(self)
    local need = ICON_SIZE + 6 * 3 + math.ceil(self.label:GetStringWidth()) + 2
    self:SetWidth(math.max(BUTTON_WIDTH, need))
  end)
  button:SetFrameLevel(level)
  -- The map texture is the anchor when the client has it (Blizzard's InsetBg), else the window.
  local inset = taxi.InsetBg
  local anchor = type(inset) == "table" and inset or taxi
  button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -MARGIN, -MARGIN)

  local panel = CreateFrame("Frame", nil, taxi)
  panel:SetSize(WIDTH, HEIGHT)
  panel:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
  panel:SetFrameLevel(level)
  panel:EnableMouse(true)
  W.Fill(panel, "surface", 1)
  W.Border(panel, "white")
  panel:Hide()
  local title = W.Text(panel, { key = "flightpanel.title", role = "h3", family = "heading", color = "accent2" })
  title:SetPoint("TOPLEFT", PAD, -10)
  title:SetPoint("TOPRIGHT", -(PAD + W.CLOSE_SIZE), -10)
  local close = W.CloseButton(panel, { onClick = P.Close })

  local size = W.Slider(panel, {
    key = "flightlabel.size",
    min = FB.SIZE_MIN,
    max = FB.SIZE_MAX,
    step = 1,
    get = FB.FontSize,
    set = function(v)
      Store.set("settings.flightFontSize", v)
    end,
    format = function(v)
      return string.format("%d px", math.floor(v + 0.5))
    end,
  })
  size:SetPoint("TOPLEFT", PAD, -36)
  size:SetPoint("TOPRIGHT", -PAD, -36)
  local labels = toggleRow(panel, "flightLabels", "flightlabel.enable", -86)
  local tooltip = toggleRow(panel, "flightTooltip", "flightlabel.tooltip", -114)
  local all = W.Action(panel, {
    label = "act.options",
    icon = "gear",
    tooltip = "flightpanel.all",
    width = WIDTH - 2 * PAD,
    onClick = function()
      P.Close()
      if ns.Main and ns.Main.Show then
        ns.Main.Show("settings")
      end
    end,
  })
  all:SetPoint("TOPLEFT", PAD, -146)

  local ring = CreateFrame("Frame", nil, taxi)
  ring:SetFrameLevel(level + 5)
  W.Border(ring, "actionHi", 1, 3)
  ring:Hide()

  local rec = {
    taxi = taxi,
    button = button,
    tab = tab,
    panel = panel,
    ring = ring,
    slider = size.slider,
    labels = labels,
    tooltip = tooltip,
    all = all,
    close = close,
    controls = { size, labels, tooltip },
    items = { tab, button, size.slider, labels, tooltip, all, close },
  }
  -- Their Tab ring belongs to the main window, which must not reach buttons on a Blizzard window.
  for _, frame in ipairs(rec.items) do
    ns.BlizzardLinks.LeaveFocusRing(frame)
  end
  return rec
end

local function setupKeys(taxi)
  local keys = CreateFrame("Frame", nil, taxi)
  if type(keys.SetPropagateKeyboardInput) ~= "function" then
    return
  end
  pcall(keys.SetPropagateKeyboardInput, keys, true)
  keys:EnableKeyboard(true)
  keys:SetScript("OnKeyDown", ns.Wrap("flightpanel-keys", onKey))
end

-- Builds the button once TaxiFrame exists (it can be created after this file loads).
function P.Install()
  local taxi = rawget(_G, "TaxiFrame")
  if built then
    return true
  end
  if type(taxi) ~= "table" or type(taxi.HookScript) ~= "function" then
    return false
  end
  built = build(taxi)
  setupKeys(taxi)
  taxi:HookScript("OnHide", function()
    P.Close()
    clearFocus()
  end)
  built.panel:HookScript("OnHide", function()
    if focus and focus ~= built.button then
      setFocus(built.button)
    end
  end)
  return true
end

function P.Refresh()
  if built then
    for _, control in ipairs(built.controls) do
      control:Refresh()
    end
  end
end

ns.On("PLAYER_LOGIN", P.Install)
ns.On("ADDON_LOADED", P.Install)
ns.On("TAXIMAP_OPENED", P.Install)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.flight") then
    P.Refresh()
  end
end)
