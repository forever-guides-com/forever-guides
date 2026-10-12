-- Flight time at the flight points of the classic flight window (TaxiFrame): a small label with the
-- duration under every destination button and a line in the button tooltip. Read only. Blizzard's
-- frames are only hooked (HookScript), the labels are child frames of the buttons, and everything
-- we remember lives in weak tables here, nothing is written into a Blizzard table.
local _, ns = ...
local FL, FR, L = ns.FlightLogic, ns.FlightRoute, ns.L

local FB = {}
ns.FlightLabels = FB

ns.AddLocale("enUS", {
  ["flightlabel.heading"] = "Flight master",
  ["flightlabel.enable"] = "Time at flight point",
  ["flightlabel.tooltip"] = "Tooltip",
  ["flightlabel.size"] = "Font size",
  ["flightlabel.tip"] = "Flight time %s",
})
ns.AddLocale("deDE", {
  ["flightlabel.heading"] = "Flugmeister",
  ["flightlabel.enable"] = "Zeit am Flugpunkt",
  ["flightlabel.tooltip"] = "Tooltip",
  ["flightlabel.size"] = "Schrift",
  ["flightlabel.tip"] = "Flugdauer %s",
})

FB.SIZE_MIN, FB.SIZE_MAX, FB.SIZE_DEFAULT = 8, 18, 10
local LABEL_PAD = 6
local weak = { __mode = "k" }
local labels = setmetatable({}, weak) -- button -> { frame, fs }
local hooked = setmetatable({}, weak) -- button -> true
local info = {} -- slot -> { full } of the open window
local frameHooked = false

local function option(key)
  local settings = ns.db and ns.db.settings
  local value = settings and settings[key]
  if value == nil then
    value = ns.Store.defaults.settings[key]
  end
  return value ~= false
end

-- Shared by the settings page and the panel at the flight window.
function FB.Option(key)
  return option(key)
end

function FB.FontSize()
  local settings = ns.db and ns.db.settings
  local n = tonumber(settings and settings.flightFontSize) or FB.SIZE_DEFAULT
  return math.max(FB.SIZE_MIN, math.min(FB.SIZE_MAX, math.floor(n)))
end

local function hideLabels()
  for _, rec in pairs(labels) do
    rec.frame:Hide()
  end
end

local function build(button)
  local frame = CreateFrame("Frame", nil, button)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(frame)
  bg:SetColorTexture(0, 0, 0, 0.85)
  local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER", frame, "CENTER", 0, 0)
  frame:SetPoint("TOP", button, "BOTTOM", 0, -1)
  local rec = { frame = frame, fs = fs }
  labels[button] = rec
  return rec
end

local function paint(button, text)
  local rec = labels[button] or build(button)
  local size = FB.FontSize()
  local path, _, flags = rec.fs:GetFont()
  rec.fs:SetFont(path or rawget(_G, "STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF", size, flags or "")
  rec.fs:SetText(text)
  rec.frame:SetSize((tonumber(rec.fs:GetStringWidth()) or 30) + LABEL_PAD, size + 4)
  rec.frame:Show()
end

-- The tooltip of a destination gets its line after Blizzard's own OnEnter has filled it.
function FB.OnEnter(button)
  local tooltip = rawget(_G, "GameTooltip")
  if not option("flightTooltip") or type(tooltip) ~= "table" then
    return
  end
  local ok, slot = pcall(button.GetID, button)
  local entry = ok and info[slot]
  if not entry then
    return
  end
  tooltip:AddLine(L["flightlabel.tip"]:format(entry.full), 1, 1, 1)
  tooltip:Show()
end

local function hookButton(button)
  if hooked[button] or type(button.HookScript) ~= "function" then
    return
  end
  -- HookScript instead of hooksecurefunc: the XML binds TaxiNodeOnButtonEnter by value.
  hooked[button] = pcall(button.HookScript, button, "OnEnter", function(self)
    ns.Safe("flightlabels", FB.OnEnter, self)
  end)
end

local function windowShown()
  local frame = rawget(_G, "TaxiFrame")
  if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then
    return false
  end
  local ok, shown = pcall(frame.IsShown, frame)
  return ok and shown == true
end

-- Rebuilds the labels from the open window; hides them when it is closed or the settings are off.
function FB.Refresh()
  hideLabels()
  info = {}
  if not (option("flightLabels") or option("flightTooltip")) or not windowShown() then
    return
  end
  local nodes = FR.Nodes()
  if not nodes then
    return
  end
  for _, node in ipairs(nodes.list) do
    if node.state == "REACHABLE" or node.state == "DISTANT" then
      local route = FR.Route(node.slot, nodes)
      local button = rawget(_G, "TaxiButton" .. node.slot)
      if route and type(button) == "table" then
        local total = route.total
        info[node.slot] = { full = FL.format(total) }
        hookButton(button)
        if option("flightLabels") then
          paint(button, FL.shortText(total))
        end
      end
    end
  end
end

-- Hooks the window once it exists (it can be created after this file loads).
function FB.Install()
  local frame = rawget(_G, "TaxiFrame")
  if frameHooked or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then
    return frameHooked
  end
  frameHooked = pcall(frame.HookScript, frame, "OnShow", function()
    ns.Safe("flightlabels", FB.Refresh)
  end)
  pcall(frame.HookScript, frame, "OnHide", function()
    ns.Safe("flightlabels", FB.Refresh)
  end)
  if frameHooked then
    FB.Refresh()
  end
  return frameHooked
end

ns.On("PLAYER_LOGIN", FB.Install)
ns.On("ADDON_LOADED", FB.Install)
ns.On("TAXIMAP_OPENED", FB.Install)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.flightLabels" or path == "settings.flightTooltip" or path == "settings.flightFontSize" then
    FB.Refresh()
  end
end)
