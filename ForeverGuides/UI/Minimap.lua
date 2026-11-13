-- Entry points besides slash: minimap button (the shared minimap library when
-- another addon already loaded it, otherwise our own), Addon Compartment,
-- Blizzard Settings panel link.
local _, ns = ...
local L = ns.L

local ICON = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png"
local Minimap_ = {}
ns.MinimapButton = Minimap_

local button, usingDBIcon
-- Every round button made here, and whether the farm HUD asked for them to be hidden: the HUD enlarges the
-- minimap and moves it to the screen center, so a button anchored to it would sit on top of the player.
local buttons, suspended = {}, false
-- Width of the minimap as the player has it. Positions are only ever computed from this, never from the
-- enlarged minimap of the HUD, whose size would leave the buttons far from the edge once it is back.
local DEFAULT_WIDTH, RING_OFFSET, MARGIN = 140, 8, 24
local realWidth = DEFAULT_WIDTH

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A stored angle in [0, 360), nil when it is not a usable number.
function Minimap_.CleanAngle(angle)
  return finite(angle) and angle % 360 or nil
end

-- Offset from the minimap center of a button on the ring.
function Minimap_.RingOffset(angle, width)
  local radius = (finite(width) and width > 0 and width or DEFAULT_WIDTH) / 2 + RING_OFFSET
  local rad = math.rad(Minimap_.CleanAngle(angle) or 200)
  return math.cos(rad) * radius, math.sin(rad) * radius
end

-- Is a button at (dx, dy) from the minimap center (in minimap units) and at (x, y) on a screen of
-- screenW x screenH where a button on the ring belongs? Anything unreadable counts as wrong.
function Minimap_.Plausible(dx, dy, width, x, y, screenW, screenH)
  if not (finite(dx) and finite(dy) and finite(x) and finite(y)) then
    return false
  end
  local radius = (finite(width) and width > 0 and width or DEFAULT_WIDTH) / 2 + RING_OFFSET + MARGIN
  if math.sqrt(dx * dx + dy * dy) > radius then
    return false
  end
  return not (finite(screenW) and finite(screenH)) or (x >= 0 and x <= screenW and y >= 0 and y <= screenH)
end

-- Where the button really sits, measured against the real minimap. nil while a frame has no position yet.
local function misplaced(btn)
  local bx, by = btn:GetCenter()
  local mx, my = Minimap:GetCenter()
  if not (bx and mx) then
    return false
  end
  local bs, ms = btn:GetEffectiveScale() or 1, Minimap:GetEffectiveScale() or 1
  local ui = rawget(_G, "UIParent")
  local us = ui and ui:GetEffectiveScale() or 1
  local w, h = ui and ui:GetWidth(), ui and ui:GetHeight()
  return not Minimap_.Plausible((bx * bs - mx * ms) / ms, (by * bs - my * ms) / ms, realWidth, bx * bs / us, by * bs / us, w, h)
end

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
  -- Not while the HUD holds the minimap: its size is not the one the player has. Resume places every button.
  local function put(useCache)
    if suspended and not useCache then
      return
    end
    if not (useCache or suspended) then
      local w = Minimap:GetWidth()
      if finite(w) and w > 0 then
        realWidth = w
      end
    end
    local x, y = Minimap_.RingOffset(spec.getAngle(), realWidth)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    if misplaced(btn) then
      spec.setAngle(nil)
      x, y = Minimap_.RingOffset(spec.getAngle(), realWidth)
      btn:ClearAllPoints()
      btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
  end
  function btn.Place()
    put(false)
  end
  btn.Resume = function()
    put(true)
  end
  btn:SetScript("OnShow", function(self)
    if suspended then
      self.wasShown = true
      self:Hide()
    end
  end)
  buttons[#buttons + 1] = btn
  btn:SetScript("OnClick", ns.Wrap("minimap", spec.onClick))
  btn:SetScript("OnEnter", spec.onEnter)
  btn:SetScript("OnLeave", ns.HideTooltip)
  -- OnUpdate only while dragging.
  btn:SetScript("OnDragStart", function(self)
    if suspended then
      return
    end
    self:SetScript("OnUpdate", function(frame)
      if suspended then
        frame:SetScript("OnUpdate", nil)
        return
      end
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      local angle = Minimap_.CleanAngle(math.deg(math.atan2(cy / scale - my, cx / scale - mx)))
      if angle then
        spec.setAngle(angle)
        btn.Place()
      end
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
  local db = ns.db.settings.minimap
  for _, key in ipairs({ "angle", "minimapPos" }) do
    if db[key] ~= nil and not finite(db[key]) then
      db[key] = nil
    end
  end
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
  if suspended then
    return
  end
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

-- Hides every minimap button while the farm HUD holds the minimap, and brings back the ones that were shown.
function Minimap_.Suspend(on)
  on = on == true
  if on == suspended then
    return
  end
  if on and Minimap then
    local w = Minimap:GetWidth()
    if finite(w) and w > 0 then
      realWidth = w
    end
  end
  suspended = on
  local dbicon = usingDBIcon and LibStub:GetLibrary("LibDBIcon-1.0")
  if on then
    for _, btn in ipairs(buttons) do
      btn.wasShown = btn:IsShown()
      btn:Hide()
    end
    if dbicon then
      dbicon:Hide("ForeverGuides")
    end
    return
  end
  -- The caller has put the minimap back by now: place from the cached real width, then show.
  for _, btn in ipairs(buttons) do
    btn.Resume()
    if btn.wasShown then
      btn:Show()
    end
    btn.wasShown = nil
  end
  if dbicon then
    pcall(function()
      local db = ns.db.settings.minimap
      local frame = dbicon:GetMinimapButton("ForeverGuides")
      if frame and misplaced(frame) then
        db.minimapPos = nil
      end
      dbicon:Refresh("ForeverGuides", db)
    end)
  end
  Minimap_.Apply()
end
