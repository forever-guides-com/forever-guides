-- Entry points besides slash: minimap button (the shared minimap library when
-- another addon already loaded it, otherwise our own), Addon Compartment,
-- Blizzard Settings panel link.
local _, ns = ...
local L = ns.L

local ICON = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png"
local Minimap_ = {}
ns.MinimapButton = Minimap_

local button, usingDBIcon

local function onClick(_, mouse)
  if mouse == "RightButton" then
    ns.Main.Show("settings")
  else
    ns.Main.Toggle()
  end
end

local function tooltip(tt)
  tt:AddLine("Forever Guides")
  tt:AddLine(L["minimap.tooltip"], 1, 1, 1, true)
end

local function placeOwn()
  local angle = math.rad(ns.db.settings.minimap.angle or 200)
  local radius = (Minimap:GetWidth() / 2) + 8
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function createOwn()
  button = CreateFrame("Button", "ForeverGuidesMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")
  icon:SetTexture(ICON)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  button:SetScript("OnClick", ns.Wrap("minimap", onClick))
  button:SetScript("OnEnter", function(self)
    ns.W.Tooltip.Show(self, { title = "Forever Guides", text = L["minimap.tooltip"], anchor = "ANCHOR_LEFT" })
  end)
  button:SetScript("OnLeave", ns.HideTooltip)
  -- OnUpdate only while dragging.
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      ns.db.settings.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
      placeOwn()
    end)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  placeOwn()
end

function Minimap_.Init()
  if ns.can.libDBIcon and ns.can.ldb then
    local ok = pcall(function()
      local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
      local dbicon = LibStub:GetLibrary("LibDBIcon-1.0")
      local obj = ldb:NewDataObject("ForeverGuides", {
        type = "launcher",
        text = "Forever Guides",
        icon = ICON,
        OnClick = onClick,
        OnTooltipShow = tooltip,
      })
      dbicon:Register("ForeverGuides", obj, ns.db.settings.minimap)
    end)
    usingDBIcon = ok
  end
  if not usingDBIcon and Minimap then
    createOwn()
  end
  Minimap_.Apply()

  if ns.can.addonCompartment then
    pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
      text = "Forever Guides",
      icon = ICON,
      notCheckable = true,
      func = function()
        ns.Main.Toggle()
      end,
    })
  end

  if ns.can.settingsCanvas and ns.can.settingsAddCategory then
    pcall(function()
      local panel = CreateFrame("Frame")
      local open = ns.W.Action(panel, {
        label = "act.open",
        icon = "open",
        tooltip = "settings.openAddon",
        variant = "primary",
        width = 220,
        onClick = function()
          if SettingsPanel and SettingsPanel.Close then
            SettingsPanel:Close(true)
          end
          ns.Main.Show("settings")
        end,
      })
      open:SetPoint("TOPLEFT", 16, -16)
      local category = Settings.RegisterCanvasLayoutCategory(panel, "Forever Guides")
      Settings.RegisterAddOnCategory(category)
    end)
  end
end

function Minimap_.Apply()
  local hide = ns.db.settings.minimap.hide
  if usingDBIcon then
    local dbicon = LibStub:GetLibrary("LibDBIcon-1.0")
    if hide then
      dbicon:Hide("ForeverGuides")
    else
      dbicon:Show("ForeverGuides")
    end
  elseif button then
    button:SetShown(not hide)
  end
end
