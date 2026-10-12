-- Auto repair at the merchant (settings.autoRepair, off by default). Repairs when the merchant
-- opens, only with a cost above 0 and enough gold. With settings.autoRepairGuild the guild bank
-- pays first when the player may withdraw that much; if the cost is still there a moment later,
-- the own gold pays. The override key holds everything back.
local _, ns = ...
local Guard, L = ns.AutoGuard, ns.L

local R = {}
ns.AutoRepair = R

ns.AddLocale("enUS", {
  ["auto.repair.guild"] = "Repaired for %s (guild bank)",
  ["auto.repair.own"] = "Repaired for %s",
})
ns.AddLocale("deDE", {
  ["auto.repair.guild"] = "Repariert für %s (Gildenkasse)",
  ["auto.repair.own"] = "Repariert für %s",
})

local ID = "autoRepair"
-- Seconds until the server has answered the guild repair.
local SETTLE = 0.6
local UNLIMITED = -1

local state = { open = false, gen = 0 }

local function money(copper)
  return ns.SellLogic.Money(copper, true)
end

local function number(value)
  value = Guard.Safe(value)
  return type(value) == "number" and value == value and value or nil
end

-- The cost of repairing everything (nil when it cannot be read) and whether anything can be repaired.
local function repairState()
  local found, cost, repairable = Guard.Call("GetRepairAllCost")
  if not found then
    return nil
  end
  return number(cost), repairable
end

local function guildMayPay(cost)
  if ns.db.settings.autoRepairGuild ~= true then
    return false
  end
  local _, can = Guard.Call("CanGuildBankRepair")
  if can ~= true then
    return false
  end
  local found, allowance = Guard.Call("GetGuildBankWithdrawMoney")
  allowance = found and number(allowance) or nil
  return allowance ~= nil and (allowance == UNLIMITED or allowance >= cost)
end

local function payOwn(cost)
  local found, gold = Guard.Call("GetMoney")
  gold = found and number(gold) or nil
  if gold == nil or gold < cost then
    return
  end
  Guard.Call("RepairAllItems")
  Guard.Say(ID, string.format(L["auto.repair.own"], money(cost)))
end

-- A moment after the guild repair: done, or the own gold pays the rest.
local function settle(cost, gen)
  if gen ~= state.gen or not state.open or Guard.Paused() then
    return
  end
  local left, repairable = repairState()
  if left == nil then
    return
  end
  if left <= 0 or repairable == false then
    Guard.Say(ID, string.format(L["auto.repair.guild"], money(cost)))
  else
    payOwn(left)
  end
end

function R.Try()
  if Guard.Paused() then
    return
  end
  local _, can = Guard.Call("CanMerchantRepair")
  if can ~= true then
    return
  end
  local cost, repairable = repairState()
  if cost == nil or cost <= 0 or repairable == false then
    return
  end
  if guildMayPay(cost) then
    Guard.Call("RepairAllItems", true)
    local gen = state.gen
    Guard.After(ID, SETTLE, function()
      settle(cost, gen)
    end)
    return
  end
  payOwn(cost)
end

ns.On("MERCHANT_SHOW", function()
  state.open = true
  state.gen = state.gen + 1
  Guard.Run(ID, R.Try)
end)

ns.On("MERCHANT_CLOSED", function()
  state.open = false
  state.gen = state.gen + 1
end)
