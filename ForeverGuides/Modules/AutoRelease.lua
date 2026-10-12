-- Auto release in PvP (settings.autoRelease, off by default). After a death in a battleground or
-- other PvP map the spirit is released after a delay (0 to 3000 ms). Nothing happens with a
-- soulstone or another self resurrection, nor while a resurrection with sickness is offered; the
-- override key cancels it, also while the delay runs.
local _, ns = ...
local Guard, L = ns.AutoGuard, ns.L

local R = {}
ns.AutoRelease = R

ns.AddLocale("enUS", {
  ["auto.release.say"] = "Spirit released (%s cancels)",
})
ns.AddLocale("deDE", {
  ["auto.release.say"] = "Geist freigelassen (%s bricht ab)",
})

local ID = "autoRelease"
R.DELAY_MAX = 3000
R.DELAY_DEFAULT = 1000
-- Instance types of PvP places for the fallback when C_PvP does not know the map.
local PVP_TYPES = { pvp = true, arena = true }

local RETRIES, RETRY_DELAY = 4, 0.5

local token = 0

-- Milliseconds, clamped to 0 .. 3000.
function R.Delay()
  local value = tonumber(ns.db.settings.autoReleaseDelay)
  if not value then
    return R.DELAY_DEFAULT
  end
  return ns.U.clamp(math.floor(value + 0.5), 0, R.DELAY_MAX)
end

local function inPvp()
  local found, pvp = Guard.Call("C_PvP.IsPVPMap")
  if found and pvp == true then
    return true
  end
  local foundType, _, kind = Guard.Call("IsInInstance")
  return foundType and PVP_TYPES[Guard.Safe(kind)] == true
end

-- A soulstone or a self resurrection is on offer, or one with sickness: the player decides.
local function selfResurrection()
  local _, option = Guard.Call("HasSoulstone")
  local _, sickness = Guard.Call("ResurrectHasSickness")
  return (option ~= nil and option ~= false) or sickness == true
end

-- The combat flag can outlast the death by a moment, so a blocked release tries again a few times.
local function release(mine, tries)
  if mine ~= token or Guard.Override() or not inPvp() or selfResurrection() then
    return
  end
  if Guard.Blocked() then
    if tries < RETRIES then
      Guard.After(ID, RETRY_DELAY, function()
        release(mine, tries + 1)
      end)
    end
    return
  end
  Guard.Call("RepopMe")
  Guard.Say(ID, string.format(L["auto.release.say"], Guard.KeyName()))
end

function R.OnDeath()
  if Guard.Override() or not inPvp() then
    return
  end
  token = token + 1
  local mine, delay = token, R.Delay()
  if delay == 0 then
    release(mine, 0)
  else
    Guard.After(ID, delay / 1000, function()
      release(mine, 0)
    end)
  end
end

ns.On("PLAYER_DEAD", function()
  Guard.Run(ID, R.OnDeath)
end)
