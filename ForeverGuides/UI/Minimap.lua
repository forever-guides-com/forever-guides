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

-- A round button on the ring around the minimap that the player drags along the edge. spec = { name (global
-- frame name), icon (texture path), getAngle() (degrees), setAngle(degrees) (called while dragging),
-- onClick(button, mouse), onEnter(button) }. Returns the button, which has Place() to put it at the saved
-- angle. nil without a minimap. The minimap button of this add-on and the one of Forever Chat both use it.
function Minimap_.NewButton(spec)
  if not (Minimap and type(spec) == "table") then
    return nil
  end
  local btn = CreateFrame("Button", spec.name, Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn.icon = btn:CreateTexture(nil, "BACKGROUND")
  btn.icon:SetSize(20, 20)
  btn.icon:SetPoint("CENTER")
  btn.icon:SetTexture(spec.icon)
  local border = btn:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  function btn.Place()
    local angle = math.rad(spec.getAngle() or 200)
    local radius = (Minimap:GetWidth() / 2) + 8
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
  end
  btn:SetScript("OnClick", ns.Wrap("minimap", spec.onClick))
  btn:SetScript("OnEnter", spec.onEnter)
  btn:SetScript("OnLeave", ns.HideTooltip)
  -- OnUpdate only while dragging.
  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      spec.setAngle(math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360)
      btn.Place()
    end)
  end)
  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  btn.Place()
  return btn
end

local function createOwn()
  button = Minimap_.NewButton({
    name = "ForeverGuidesMinimapButton",
    icon = ICON,
    getAngle = function()
      return ns.db.settings.minimap.angle
    end,
    setAngle = function(angle)
      ns.db.settings.minimap.angle = angle
    end,
    onClick = onClick,
    onEnter = function(self)
      ns.W.Tooltip.Show(self, { title = "Forever Guides", text = L["minimap.tooltip"], anchor = "ANCHOR_LEFT" })
    end,
  })
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
