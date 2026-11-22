-- Cast bars (settings area "Spells", Modules/SpellSettings.lua): a timer text and the spell icon on the
-- player's and the target's cast bar, a larger target cast bar, and the game's own option for numbers on
-- cooldowns (its console variable). The timer and icon are regions of our own on the game's bars, driven
-- by a frame of ours (no hook on the bars). The larger target bar changes the scale of a bar that hangs on
-- the protected target frame, so it is refused in combat and never queued.
local _, ns = ...
local UF = ns.UnitFrameTweaks

local CB = {}
ns.CastBarTweaks = CB

-- How much larger the target cast bar gets.
CB.TARGET_FACTOR = 1.4
CB.COOLDOWN_CVAR = "countdownForCooldowns"

local INTERVAL = 0.05

local function option(key)
  return ns.TooltipTweaks.Option(key) == true
end

-- The bars: the player's under the screen center, the target's under the target frame.
local function bars()
  return {
    { frame = rawget(_G, "CastingBarFrame") or rawget(_G, "PlayerCastingBarFrame"), unit = "player" },
    { frame = rawget(_G, "TargetFrameSpellBar"), unit = "target" },
  }
end

-- bar -> { timer, icon }; created when first needed.
local parts = setmetatable({}, { __mode = "k" })
local baseScale = setmetatable({}, { __mode = "k" })

local function partsOf(bar)
  local p = parts[bar]
  if not p and type(bar.CreateFontString) == "function" and type(bar.CreateTexture) == "function" then
    p = {
      timer = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
      icon = bar:CreateTexture(nil, "OVERLAY"),
    }
    p.timer:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    p.icon:SetSize(20, 20)
    p.icon:SetPoint("RIGHT", bar, "LEFT", -4, 0)
    parts[bar] = p
  end
  return p
end

local function readable(v, kind)
  if type(v) ~= kind then
    return false
  end
  local guard = rawget(_G, "canaccessvalue")
  if type(guard) == "function" then
    local ok, can = pcall(guard, v)
    return ok and can ~= false
  end
  return true
end

-- The cast or channel of a unit: icon texture and seconds left, nil when it casts nothing.
function CB.Cast(unit)
  for _, name in ipairs({ "UnitCastingInfo", "UnitChannelInfo" }) do
    local f = rawget(_G, name)
    if type(f) == "function" then
      local ok, spell, _, texture, _, endMs = pcall(f, unit)
      if ok and readable(spell, "string") and readable(endMs, "number") then
        local now = type(GetTime) == "function" and GetTime() or 0
        return texture, math.max(0, endMs / 1000 - now)
      end
    end
  end
end

local function paint(entry)
  local bar = entry.frame
  local p = type(bar) == "table" and parts[bar]
  if not p then
    return
  end
  local texture, left
  if bar:IsShown() then
    texture, left = CB.Cast(entry.unit)
  end
  if option("castTimer") and left then
    p.timer:SetText(string.format("%.1f", left))
    p.timer:Show()
  else
    p.timer:Hide()
  end
  if option("castIcon") and texture then
    p.icon:SetTexture(texture)
    p.icon:Show()
  else
    p.icon:Hide()
  end
end

-- Paints the timer and icon of every bar (the driver calls it every INTERVAL seconds).
function CB.Update()
  for _, entry in ipairs(bars()) do
    ns.Safe("castbar", paint, entry)
  end
end

local driver = CreateFrame("Frame")
driver:Hide()
local elapsed = 0
driver:SetScript("OnUpdate", function(_, step)
  elapsed = elapsed + step
  if elapsed >= INTERVAL then
    elapsed = 0
    CB.Update()
  end
end)

-- Creates the regions when a switch is on, hides them when both are off, runs the driver only when needed.
function CB.Refresh()
  local wanted = option("castTimer") or option("castIcon")
  for _, entry in ipairs(bars()) do
    if type(entry.frame) == "table" then
      if wanted then
        partsOf(entry.frame)
      end
      paint(entry)
    end
  end
  driver:SetShown(wanted)
end

-- The target cast bar at its size or the larger one. False when combat refused the change.
function CB.ApplyTargetSize(silent)
  local bar = rawget(_G, "TargetFrameSpellBar")
  if type(bar) ~= "table" or type(bar.SetScale) ~= "function" then
    return true
  end
  local big = option("castTargetBig")
  if not big and baseScale[bar] == nil then
    return true
  end
  if ns.InCombat() then
    if not silent then
      UF.Blocked()
    end
    return false
  end
  baseScale[bar] = baseScale[bar] or bar:GetScale() or 1
  bar:SetScale(big and baseScale[bar] * CB.TARGET_FACTOR or baseScale[bar])
  if not big then
    baseScale[bar] = nil
  end
  return true
end

-- Cooldown numbers: the game's switch is the one source, nothing of ours is stored.
function CB.CooldownNumbers()
  return ns.GetCVar(CB.COOLDOWN_CVAR) == "1"
end

-- False when combat refused it or this game has no such variable.
function CB.SetCooldownNumbers(value)
  if UF.Blocked() then
    return false
  end
  if ns.GetCVar(CB.COOLDOWN_CVAR) == nil or not ns.SetCVar(CB.COOLDOWN_CVAR, value and "1" or "0") then
    ns.Notify(ns.L["spells.cvarMissing"], "warning")
    return false
  end
  return true
end

ns.On("PLAYER_ENTERING_WORLD", function()
  CB.Refresh()
  CB.ApplyTargetSize(true)
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.castTimer" or path == "settings.castIcon" then
    CB.Refresh()
  end
end)
