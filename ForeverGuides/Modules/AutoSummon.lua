-- Auto summon (settings.autoSummon, off by default). Accepts a summon after a delay (5 to 30 s, default
-- 10), never in combat, only while summoner and place are still the ones announced, and by default
-- only from my group, guild or friends. Everyone else is left alone. The override key stops it.
local _, ns = ...
local Guard, L = ns.AutoGuard, ns.L

local S = {}
ns.AutoSummon = S

ns.AddLocale("enUS", {
  ["auto.summon.say"] = "Summon from %s to %s accepted in %d s (%s stops it)",
  ["auto.summon.noPlace"] = "unknown place",
})
ns.AddLocale("deDE", {
  ["auto.summon.say"] = "Beschwörung von %s in %s wird in %d Sekunden angenommen (%s hält an)",
  ["auto.summon.noPlace"] = "unbekannter Ort",
})

local ID = "autoSummon"
S.DELAY_MIN, S.DELAY_MAX, S.DELAY_DEFAULT = 5, 30, 10

local token = 0

function S.Delay()
  local value = tonumber(ns.db.settings.autoSummonDelay)
  if not value then
    return S.DELAY_DEFAULT
  end
  return ns.U.clamp(math.floor(value + 0.5), S.DELAY_MIN, S.DELAY_MAX)
end

-- Summoner and place as the game announces them right now, nil without a summoner.
local function announced()
  local found, name = Guard.Call("C_SummonInfo.GetSummonConfirmSummoner")
  name = found and Guard.Safe(name) or nil
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local _, area = Guard.Call("C_SummonInfo.GetSummonConfirmArea")
  area = Guard.Safe(area)
  return name, type(area) == "string" and area or ""
end

local function accept(name, area, mine)
  if mine ~= token or Guard.Paused() then
    return
  end
  local nowName, nowArea = announced()
  if nowName ~= name or nowArea ~= area then
    return
  end
  Guard.Call("C_SummonInfo.ConfirmSummon")
end

function S.OnSummon()
  if Guard.Paused() then
    return
  end
  local name, area = announced()
  if not name then
    return
  end
  if ns.db.settings.autoSummonTrusted ~= false and not Guard.Trusted(name) then
    return
  end
  token = token + 1
  local mine, delay = token, S.Delay()
  if not Guard.After(ID, delay, function()
    accept(name, area, mine)
  end) then
    return
  end
  Guard.Say(
    ID,
    string.format(L["auto.summon.say"], name, area ~= "" and area or L["auto.summon.noPlace"], delay, Guard.KeyName())
  )
end

ns.On("CONFIRM_SUMMON", function()
  Guard.Run(ID, S.OnSummon)
end)
