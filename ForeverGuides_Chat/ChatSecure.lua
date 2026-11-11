-- Forever Chat, the secure "Send now" button. The Forever client lets a message out of the add-on through the chat
-- function most of the time and refuses it now and then. For such a message the row offers "Send now": a secure action
-- button that runs the macro line ("/g text") for the player's own mouse click. This file makes that button and keeps
-- it honest; what is sent, when and how the outcome is judged is ChatSend.lua (Plan, Committed) and ChatWayLogic.lua.
--
-- NEVER clicked by code. Measured in the Forever client (build 70862): a real mouse click on the button runs the
-- macro and the own line comes back, Button:Click from add-on code raises RunMacroText forbidden (ADDON_ACTION_FORBIDDEN)
-- and a dialog of the game that offers to disable the add-on. So there is no Enter path and no keyboard path here: the
-- keyboard keeps "Waiting for Enter" in the chat box of the game. The button is no standard fallback: it is offered
-- for a held message only, never while the client restricts the add-on (Secure.State), and a refusal that names
-- RunMacroText ends the offer for every chat type in that build (WayLogic, key ANY). Such a refusal is expected: the
-- sender turns it into "Not sent" with the text in the chat box and the error list does not record it.
--
-- An overlay is a secure button that hangs on UIParent and lies over a visible button of the messenger (the "Send now"
-- button of a message). It is never anchored to a window: a protected frame anchored to a window would make that
-- window protected in combat. Attributes of a secure button only change out of combat, so an overlay armed before
-- combat would send the text of an earlier moment. Three guards keep that from happening. A state driver hides every
-- overlay in combat ("[combat] hide; show"), so the plain button below takes the click. The macro starts with
-- "/stopmacro [combat]". And every click arms the button again in PreClick from the text of that moment
-- (opts.plan). PostClick makes the job (Send.Committed) and tells the owner (opts.done).
--
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local Send = chat.Send

local Secure = {}
chat.Secure = Secure

local TEMPLATE = "SecureActionButtonTemplate"
-- Hidden in combat by the secure state driver, shown again afterwards (the owner hides what is not wanted).
local DRIVER = "[combat] hide; show"
local LEVEL_STEP = 10

local function global(name)
  return rawget(_G, name)
end

-- Everything taken from the game, replaceable for tests (Secure.Env.field = ..., Secure.ResetEnv()).
local function defaultEnv()
  return {
    combat = function()
      local fn = global("InCombatLockdown")
      if type(fn) ~= "function" then
        return false
      end
      local ok, fighting = pcall(fn)
      return not ok or fighting == true
    end,
    -- A new secure button on UIParent with the state driver, nil when the client cannot make one.
    create = function()
      local make, driver, parent = global("CreateFrame"), global("RegisterStateDriver"), global("UIParent")
      if type(make) ~= "function" or type(driver) ~= "function" or type(parent) ~= "table" then
        return nil
      end
      local ok, frame = pcall(make, "Button", nil, parent, TEMPLATE)
      if not (ok and type(frame) == "table") then
        return nil
      end
      if not pcall(driver, frame, "visibility", DRIVER) then
        return nil
      end
      return frame
    end,
    -- Runs fn on every frame while the owner list is not empty: a plain frame with OnUpdate.
    ticker = function(fn)
      local make, parent = global("CreateFrame"), global("UIParent")
      if type(make) ~= "function" then
        return nil
      end
      local frame = make("Frame", nil, parent)
      frame:SetScript("OnUpdate", fn)
      frame:Hide()
      return frame
    end,
    -- Whether the client lets this add-on use protected functions on the frame right now (the silent check, it
    -- raises no refusal itself). True when the client cannot tell.
    allowed = function(frame)
      if type(FG.ProtectedAllowed) == "function" then
        return FG.ProtectedAllowed(frame) ~= false
      end
      return true
    end,
    -- The click of the player may end in a refusal of the macro function: the game reports it, this add-on handles it
    -- (Send.OnBlocked), so the error list does not record it.
    expectRefusal = function(seconds, word)
      local catcher = FG.ErrorCatcher
      if type(catcher) == "table" and type(catcher.ExpectRefusal) == "function" then
        pcall(catcher.ExpectRefusal, seconds, word)
      end
    end,
    wrap = function(name, fn)
      return FG.Wrap and FG.Wrap(name, fn) or fn
    end,
  }
end

Secure.Env = defaultEnv()

function Secure.ResetEnv()
  Secure.Env = defaultEnv()
end

local overlays, tracker, failed, probed = {}, nil, false, false

local function combat()
  return Secure.Env.combat()
end

-- Whether secure buttons can be made and used right now: true, or false and why ("combat", "nosecure", "restricted").
-- A client without the template or the state driver never gets a secure button. The first call (out of combat) makes
-- one frame to find out, and keeps it for the first owner; later calls make nothing. While the client keeps the
-- add-on from protected functions ("restricted") nothing is offered: the macro function would be refused.
function Secure.State()
  if failed then
    return false, "nosecure"
  end
  if combat() then
    -- Nothing is made in combat: a refusal there would say nothing about the client.
    return false, "combat"
  end
  if not probed then
    probed = true
    Secure.spare = Secure.Env.create() or false
    if not Secure.spare then
      failed = true
      return false, "nosecure"
    end
    Secure.probe = Secure.spare
  end
  if Secure.probe and not Secure.Env.allowed(Secure.probe) then
    return false, "restricted"
  end
  return true
end

-- Forgets every overlay (tests).
function Secure.Reset()
  overlays, tracker, failed, probed, Secure.spare, Secure.probe = {}, nil, false, false, nil, nil
end

----------------------------------------------------------------------------------------------------
-- Overlay
----------------------------------------------------------------------------------------------------

local Overlay = {}
Overlay.__index = Overlay

local function inert(frame)
  frame:SetAttribute("type", nil)
  frame:SetAttribute("macrotext", nil)
  frame:EnableMouse(false)
  frame:ClearAllPoints()
  frame:Hide()
end

local function rectOf(anchor)
  local scale = (anchor:GetEffectiveScale() or 1)
    / ((global("UIParent") and global("UIParent"):GetEffectiveScale()) or 1)
  return anchor:GetLeft(), anchor:GetBottom(), anchor:GetWidth(), anchor:GetHeight(), scale
end

-- Lays the button over its anchor (the screen rectangle of the anchor, no anchoring to it). Only out of combat.
function Overlay:Place()
  local anchor, frame = self.anchor, self.frame
  if not anchor or combat() then
    return false
  end
  local left, bottom, width, height, scale = rectOf(anchor)
  if not (left and bottom and width and height) then
    return false
  end
  local strata, level = anchor:GetFrameStrata(), anchor:GetFrameLevel() + LEVEL_STEP
  local key = table.concat({ left, bottom, width, height, scale, strata, level }, ":")
  if self.placed == key then
    return true
  end
  self.placed = key
  frame:ClearAllPoints()
  frame:SetParent(global("UIParent"))
  frame:SetFrameStrata(strata)
  frame:SetFrameLevel(level)
  frame:SetSize(width * scale, height * scale)
  frame:SetPoint("BOTTOMLEFT", global("UIParent"), "BOTTOMLEFT", left * scale, bottom * scale)
  return true
end

-- Sets the attributes from a plan (a plan the button may be offered for only). Out of combat only. Returns whether the button is armed.
function Overlay:Arm(plan)
  local frame = self.frame
  if combat() then
    return false
  end
  if not (plan and plan.secure and plan.macro) then
    frame:SetAttribute("type", nil)
    frame:SetAttribute("macrotext", nil)
    self.macro, self.plan = nil, nil
    return false
  end
  if self.macro ~= plan.macro then
    frame:SetAttribute("type", "macro")
    frame:SetAttribute("macrotext", plan.macro)
    self.macro = plan.macro
  end
  self.plan = plan
  return true
end

-- The plan of this moment, armed. Out of combat the answer is current; in combat nothing is armed.
function Overlay:Sync()
  return self:Arm(self.opts.plan and self.opts.plan() or nil)
end

-- The next frame arms the button again (the text, the conversation or the memory changed).
function Overlay:Refresh()
  self.dirty = true
end

-- Whether the overlay is over its anchor and armed with a secure plan.
function Overlay:Armed()
  return self.macro ~= nil and self.anchor ~= nil and self.frame:IsShown() == true
end

-- Puts the overlay over a visible button. The owner calls it when the button is wanted as a secure one; the
-- tracker keeps it on the button while that moves and takes it away when the button hides.
function Overlay:Aim(anchor)
  if self.anchor ~= anchor then
    self.placed = nil
  end
  self.anchor = anchor
  self.dirty = true
  overlays[self] = true
  Secure.Wake()
end

-- Takes the overlay off the button. Out of combat at once, in combat the state driver has hidden it already and
-- the tracker finishes the job after the combat.
function Overlay:Release()
  self.anchor, self.placed, self.dirty = nil, nil, false
  self.macro, self.plan = nil, nil
  if not combat() then
    inert(self.frame)
    overlays[self] = nil
  else
    self.pendingRelease = true
  end
end

-- One tracker step: arm when asked (never every frame: the plan cuts the text), follow the anchor, hide when the
-- anchor is not shown.
function Overlay:Step()
  if combat() then
    return
  end
  if self.pendingRelease then
    self.pendingRelease = nil
    inert(self.frame)
    overlays[self] = nil
    return
  end
  local anchor, frame = self.anchor, self.frame
  if not (anchor and anchor:IsVisible()) then
    if frame:IsShown() or self.macro then
      self.macro, self.plan, self.placed = nil, nil, nil
      inert(frame)
    end
    return
  end
  if self.dirty then
    self.dirty = false
    if not self:Sync() then
      inert(frame)
      self.placed = nil
      return
    end
    frame:EnableMouse(true)
    self:Place()
    frame:Show()
    return
  end
  self:Place()
end

-- PreClick: the macro of this click is the text of this moment.
function Overlay:OnPreClick()
  self.job = nil
  if combat() then
    self.plan = nil
    return
  end
  if not self:Sync() then
    self.plan = nil
    return
  end
  -- A refusal of the macro function during this click is handled (Send.OnBlocked), not an error of the add-on.
  Secure.Env.expectRefusal(chat.WayLogic.ECHO_WAIT, chat.WayLogic.MACRO_FUNCTION)
  Send.BeginSecure()
end

-- PostClick: the macro ran (or the game refused it). The job is made from the plan of PreClick.
function Overlay:OnPostClick()
  local plan = self.plan
  if not plan then
    return
  end
  local blocked = Send.EndSecure()
  if combat() then
    -- The macro stops itself in combat: nothing was sent.
    return
  end
  self.job = Send.Committed(plan, blocked, plan.held)
  if self.opts.done then
    self.opts.done(plan, self.job)
  end
end

-- Makes an overlay. opts:
--   plan()    the plan of this moment (Send.Plan of the text the owner would send), nil for none; with plan.held
--             set to the held job of the same message, when the click continues one
--   done(plan, job)  runs after the click made its job
--   release   true: the overlay leaves its anchor when the mouse leaves it (one shared overlay for many buttons)
-- Returns the overlay, or nil and a reason when there is none: "nosecure" (the client has no secure button)
-- or "combat" (try again later).
function Secure.New(opts)
  local ready, why = Secure.State()
  if not ready then
    return nil, why
  end
  local frame = Secure.spare
  Secure.spare = nil
  if not frame then
    frame = Secure.Env.create()
  end
  if not frame then
    failed = true
    return nil, "nosecure"
  end
  local self = setmetatable({ frame = frame, opts = opts or {} }, Overlay)
  frame:RegisterForClicks("LeftButtonUp")
  frame:SetAttribute("useOnKeyDown", false)
  inert(frame)
  frame:HookScript(
    "PreClick",
    Secure.Env.wrap("chat-secure-pre", function()
      self:OnPreClick()
    end)
  )
  frame:HookScript(
    "PostClick",
    Secure.Env.wrap("chat-secure-post", function()
      self:OnPostClick()
    end)
  )
  -- The hover look and the tooltip of the button below stay: the overlay passes the mouse events on.
  frame:HookScript("OnEnter", function()
    local anchor = self.anchor
    local enter = anchor and anchor:GetScript("OnEnter")
    if enter then
      pcall(enter, anchor)
    end
  end)
  frame:HookScript("OnLeave", function()
    local anchor = self.anchor
    local leave = anchor and anchor:GetScript("OnLeave")
    if leave then
      pcall(leave, anchor)
    end
    if self.opts.release then
      self:Release()
    end
  end)
  return self
end

----------------------------------------------------------------------------------------------------
-- Tracker
----------------------------------------------------------------------------------------------------

local function step()
  for overlay in pairs(overlays) do
    overlay:Step()
  end
  if next(overlays) == nil and tracker then
    tracker:Hide()
  end
end

-- Starts the per-frame step while an overlay is on a button.
function Secure.Wake()
  if not tracker then
    tracker = Secure.Env.ticker(function()
      FG.Safe("chat-secure-step", step)
    end)
  end
  if tracker then
    tracker:Show()
  end
end

-- The combat is over: what was released in combat goes now, the rest is armed again.
FG.On("PLAYER_REGEN_ENABLED", function()
  for overlay in pairs(overlays) do
    overlay.dirty = true
  end
  if next(overlays) ~= nil then
    Secure.Wake()
  end
end)
