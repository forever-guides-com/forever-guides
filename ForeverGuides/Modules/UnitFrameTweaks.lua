-- The game's player, target and party frames (settings area "Unit frames", Modules/UnitFrameSettings.lua):
-- class colored health bars, class icons as portraits, frame scales, the status text (the game's own
-- console variables) and the target of target frame (its console variable). The bars and portraits are
-- repainted by post hooks of the game's update functions, which only touch regions (a color, a texture).
-- The frames themselves are protected: a scale or a console variable that shows or hides a frame is
-- refused in combat, never queued (UF.Blocked tells the settings card to skip and ask for a retry).
local _, ns = ...

local UF = {}
ns.UnitFrameTweaks = UF

UF.SCALE_MIN, UF.SCALE_MAX, UF.SCALE_STEP = 70, 150, 5

-- Frame names by scale group; the party frames follow one setting.
UF.GROUPS = {
  player = { option = "ufScalePlayer", frames = { "PlayerFrame" } },
  target = { option = "ufScaleTarget", frames = { "TargetFrame" } },
  party = {
    option = "ufScaleParty",
    frames = { "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" },
  },
}

-- Frames whose health bar and portrait get the class look.
local LOOK_FRAMES = {
  "PlayerFrame",
  "TargetFrame",
  "TargetFrameToT",
  "PartyMemberFrame1",
  "PartyMemberFrame2",
  "PartyMemberFrame3",
  "PartyMemberFrame4",
}

local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local function option(key)
  return ns.TooltipTweaks.Option(key)
end

local function frameOf(name)
  local frame = rawget(_G, name)
  return type(frame) == "table" and frame or nil
end

local function partOf(frame, name, field, suffix)
  local part = frame[field]
  if type(part) ~= "table" then
    part = rawget(_G, name .. suffix)
  end
  return type(part) == "table" and part or nil
end

-- What we changed, kept beside the frames: nothing of ours is written into a game frame (taint).
local painted = setmetatable({}, { __mode = "k" }) -- health bar -> its color before the first repaint
local iconed = setmetatable({}, { __mode = "k" }) -- portrait texture -> true while it shows a class icon
local baseScale = setmetatable({}, { __mode = "k" }) -- frame -> its scale before the first change

local function playerClass(unit)
  if type(unit) ~= "string" then
    return nil
  end
  local isPlayer = rawget(_G, "UnitIsPlayer")
  local classOf = rawget(_G, "UnitClass")
  if type(isPlayer) ~= "function" or type(classOf) ~= "function" then
    return nil
  end
  local ok, player = pcall(isPlayer, unit)
  if not (ok and player == true) then
    return nil
  end
  local ok2, _, class = pcall(classOf, unit)
  return ok2 and type(class) == "string" and class or nil
end

-- Health bars ---------------------------------------------------------------------------------------------

local function paintBar(bar, unit)
  if type(bar) ~= "table" or type(bar.SetStatusBarColor) ~= "function" or option("ufClassBars") ~= true then
    return
  end
  local r, g, b = ns.TooltipTweaks.ClassRGB(playerClass(unit or bar.unit))
  if r then
    painted[bar] = painted[bar] or { bar:GetStatusBarColor() }
    bar:SetStatusBarColor(r, g, b)
  end
end

local function restoreBar(bar)
  local color = painted[bar]
  if color then
    bar:SetStatusBarColor(unpack(color))
    painted[bar] = nil
  end
end

-- Portraits -----------------------------------------------------------------------------------------------

local function portraitOf(frame)
  local name = type(frame) == "table" and type(frame.GetName) == "function" and frame:GetName()
  return type(frame) == "table" and partOf(frame, name or "", "portrait", "Portrait") or nil
end

local function paintPortrait(frame)
  local portrait = portraitOf(frame)
  if not portrait or type(portrait.SetTexCoord) ~= "function" then
    return
  end
  local coords = rawget(_G, "CLASS_ICON_TCOORDS")
  local class = option("ufClassIcons") == true and playerClass(frame.unit)
  local c = class and type(coords) == "table" and coords[class]
  if type(c) == "table" then
    portrait:SetTexture(CLASS_ICONS)
    portrait:SetTexCoord(c[1], c[2], c[3], c[4])
    iconed[portrait] = true
  elseif iconed[portrait] then
    portrait:SetTexCoord(0, 1, 0, 1)
    iconed[portrait] = nil
  end
end

local function restorePortrait(frame)
  local portrait = portraitOf(frame)
  if portrait and iconed[portrait] then
    portrait:SetTexCoord(0, 1, 0, 1)
    iconed[portrait] = nil
    local set, exists = rawget(_G, "SetPortraitTexture"), rawget(_G, "UnitExists")
    if type(set) == "function" and type(exists) == "function" and type(frame.unit) == "string" then
      local ok, there = pcall(exists, frame.unit)
      if ok and there then
        pcall(set, portrait, frame.unit)
      end
    end
  end
end

-- Paints (or restores) every bar and portrait now, after a switch changed.
function UF.ApplyLook()
  for _, name in ipairs(LOOK_FRAMES) do
    local frame = frameOf(name)
    if frame then
      local bar = partOf(frame, name, "healthbar", "HealthBar")
      if bar then
        if option("ufClassBars") == true then
          paintBar(bar, frame.unit or bar.unit)
        else
          restoreBar(bar)
        end
      end
      if option("ufClassIcons") == true then
        paintPortrait(frame)
      else
        restorePortrait(frame)
      end
    end
  end
end

-- Scale ---------------------------------------------------------------------------------------------------

-- In combat the protected frames refuse a new scale. True when the caller must stop (a throttled notice
-- tells the player to retry after combat); nothing is kept for later.
function UF.Blocked()
  return ns.InCombat() and ns.CombatBlocked("unit frames")
end

-- Scales the frames of a group to its option; 100 gives the first scale of each frame back. False in
-- combat (silent: without the notice, for the automatic call at login).
function UF.ApplyScale(group, silent)
  local def = UF.GROUPS[group]
  if not def then
    return true
  end
  local percent = math.max(UF.SCALE_MIN, math.min(UF.SCALE_MAX, tonumber(option(def.option)) or 100))
  for _, name in ipairs(def.frames) do
    local frame = frameOf(name)
    if frame and type(frame.SetScale) == "function" and (baseScale[frame] ~= nil or percent ~= 100) then
      if ns.InCombat() then
        if not silent then
          UF.Blocked()
        end
        return false
      end
      baseScale[frame] = baseScale[frame] or frame:GetScale() or 1
      frame:SetScale(baseScale[frame] * percent / 100)
      if percent == 100 then
        baseScale[frame] = nil
      end
    end
  end
  return true
end

function UF.ApplyAll(silent)
  for group in pairs(UF.GROUPS) do
    UF.ApplyScale(group, silent)
  end
  UF.ApplyLook()
end

-- Console variables ---------------------------------------------------------------------------------------

UF.STATUS_MODES = { "NONE", "NUMERIC", "PERCENT", "BOTH" }

-- Status text of the unit frames as the game's own options say it: NONE, NUMERIC, PERCENT or BOTH.
function UF.StatusMode()
  if ns.GetCVar("statusText") ~= "1" then
    return "NONE"
  end
  local display = ns.GetCVar("statusTextDisplay")
  return (display == "PERCENT" or display == "BOTH") and display or "NUMERIC"
end

function UF.SetStatusMode(mode)
  if UF.Blocked() then
    return false
  end
  if mode == "NONE" then
    return ns.SetCVar("statusText", "0")
  end
  return ns.SetCVar("statusTextDisplay", mode) and ns.SetCVar("statusText", "1")
end

function UF.TargetOfTarget()
  return ns.GetCVar("showTargetOfTarget") == "1"
end

function UF.SetTargetOfTarget(value)
  if UF.Blocked() then
    return false
  end
  return ns.SetCVar("showTargetOfTarget", value and "1" or "0")
end

-- Hooks ---------------------------------------------------------------------------------------------------

UF.hooked = {}

local function hook(name, fn)
  local target = rawget(_G, name)
  local secure = rawget(_G, "hooksecurefunc")
  if UF.hooked[name] or type(target) ~= "function" or type(secure) ~= "function" then
    return
  end
  UF.hooked[name] = pcall(secure, name, function(...)
    ns.Safe("unitframes", fn, ...)
  end)
end

-- Safe to call again: each game function is hooked once.
function UF.Install()
  hook("UnitFrameHealthBar_Update", paintBar)
  hook("HealthBar_OnValueChanged", paintBar)
  hook("UnitFramePortrait_Update", paintPortrait)
end

ns.On("PLAYER_LOGIN", UF.Install)
ns.On("PLAYER_ENTERING_WORLD", function()
  UF.Install()
  UF.ApplyAll(true)
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.ufClassBars" or path == "settings.ufClassIcons" then
    UF.ApplyLook()
  end
end)
