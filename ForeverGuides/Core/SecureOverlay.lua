-- A secure action button that lies over an insecure window: the window shows, hides, moves and repaints in
-- combat, only the macro of the button waits for the end of combat. The button hangs on UIParent and never
-- anchors to the window (a protected frame in the anchor chain would make the window protected). A state driver
-- hides it in combat, so a button armed for an earlier moment cannot be clicked for content that changed in the
-- fight. Everything here that touches the button (attributes, size, points, mouse, show/hide) runs out of combat.
--
-- API (ns.SecureOverlay):
--   New(name)                  overlay or nil (no secure button, or in combat); overlay.frame is the button, name
--                              is its optional global name (a key binding clicks it by name)
--   overlay:Sync(anchor, macro, level)
--                              arms with the macro and lays it over the anchor (level above the anchor frame by
--                              `level`, default 2); no macro or no visible anchor makes it inert. Out of combat
--                              only. Returns whether it is armed.
local _, ns = ...

local SO = {}
ns.SecureOverlay = SO

local TEMPLATE = "SecureActionButtonTemplate"
local DRIVER = "[combat] hide; show"
local LEVEL = 2

function SO.New(name)
  local make, driver, parent = rawget(_G, "CreateFrame"), rawget(_G, "RegisterStateDriver"), rawget(_G, "UIParent")
  if type(make) ~= "function" or type(driver) ~= "function" or type(parent) ~= "table" or ns.InCombat() then
    return nil
  end
  local ok, frame = pcall(make, "Button", name, parent, TEMPLATE)
  if not (ok and type(frame) == "table") then
    return nil
  end
  if not pcall(driver, frame, "visibility", DRIVER) then
    return nil
  end
  frame:RegisterForClicks("AnyUp", "AnyDown")
  frame:EnableMouse(false)
  frame:Hide()
  return setmetatable({ frame = frame }, { __index = SO.Overlay })
end

SO.Overlay = {}
local Overlay = SO.Overlay

local function inert(self)
  local f = self.frame
  f:SetAttribute("type", nil)
  f:SetAttribute("macrotext", nil)
  f:EnableMouse(false)
  f:ClearAllPoints()
  f:Hide()
  self.macro, self.key = nil, nil
end

local function place(self, anchor, level)
  local ui = rawget(_G, "UIParent")
  local ratio = (anchor:GetEffectiveScale() or 1) / (ui:GetEffectiveScale() or 1)
  local left, bottom, width, height = anchor:GetLeft(), anchor:GetBottom(), anchor:GetWidth(), anchor:GetHeight()
  if not (left and bottom and width and height) then
    return false
  end
  local strata, lvl = anchor:GetFrameStrata(), anchor:GetFrameLevel() + level
  local key = table.concat({ left, bottom, width, height, ratio, strata, lvl }, ":")
  if self.key == key then
    return true
  end
  self.key = key
  local f = self.frame
  f:ClearAllPoints()
  f:SetFrameStrata(strata)
  f:SetFrameLevel(lvl)
  f:SetSize(width * ratio, height * ratio)
  f:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT", left * ratio, bottom * ratio)
  return true
end

function Overlay:Sync(anchor, macro, level)
  if ns.InCombat() then
    return false
  end
  local f = self.frame
  if not (anchor and macro and anchor:IsVisible()) then
    inert(self)
    return false
  end
  if self.macro ~= macro then
    f:SetAttribute("type", "macro")
    f:SetAttribute("macrotext", macro)
    self.macro = macro
  end
  if not place(self, anchor, level or LEVEL) then
    inert(self)
    return false
  end
  f:EnableMouse(true)
  f:Show()
  return true
end
