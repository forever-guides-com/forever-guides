-- Auto resurrect (settings.autoResurrect, off by default). Accepts a resurrection one second after the
-- request, only from my group, guild or friends, never in combat. By default a resurrection cast
-- while the caster is in combat (a battle resurrection) is left to the player. The override key
-- stops it.
local _, ns = ...
local Guard, L = ns.AutoGuard, ns.L

local R = {}
ns.AutoResurrect = R

ns.AddLocale("enUS", {
  ["auto.resurrect.say"] = "Resurrection from %s accepted (%s stops it)",
})
ns.AddLocale("deDE", {
  ["auto.resurrect.say"] = "Wiederbelebung von %s wird angenommen (%s hält an)",
})

local ID = "autoResurrect"
local DELAY = 1

local token = 0

local function casterInCombat(name)
  local found, fighting = Guard.Call("UnitAffectingCombat", name)
  return found and fighting == true
end

function R.OnRequest(name)
  name = Guard.Safe(name)
  if Guard.Paused() or type(name) ~= "string" or name == "" or not Guard.Trusted(name) then
    return
  end
  if ns.db.settings.autoResurrectNoCombat ~= false and casterInCombat(name) then
    return
  end
  token = token + 1
  local mine = token
  if
    not Guard.After(ID, DELAY, function()
      if mine == token and not Guard.Paused() then
        Guard.Call("AcceptResurrect")
      end
    end)
  then
    return
  end
  Guard.Say(ID, string.format(L["auto.resurrect.say"], name, Guard.KeyName()))
end

ns.On("RESURRECT_REQUEST", function(_, name)
  Guard.Run(ID, R.OnRequest, name)
end)
