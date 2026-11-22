-- Faster looting (settings.fastLoot, off by default): when the game auto loots, every slot is taken in
-- the frame the loot window opens and the window stays invisible meanwhile. Left to the client: master
-- loot, rolls, bind confirmations, a catch of the fishing helper, and a window that cannot be emptied
-- (bags full), which is shown again. LootCapture reads the window first. Nothing here is protected.
local _, ns = ...
local Logic, Guard = ns.FastLootLogic, ns.AutoGuard

local F = {}
ns.FastLoot = F

ns.AddLocale("enUS", {
  ["fastloot.card"] = "Looting",
  ["fastloot.toggle"] = "Faster looting",
  ["fastloot.tip"] = "Takes all items instantly\nwhen auto loot is active.",
})
ns.AddLocale("deDE", {
  ["fastloot.card"] = "Plündern",
  ["fastloot.toggle"] = "Schneller plündern",
  ["fastloot.tip"] = "Nimmt alle Gegenstände sofort,\nwenn Automatisch plündern aktiv ist.",
})

local state = { at = nil, hidden = false, stopped = false }

local function fn(name)
  local f = rawget(_G, name)
  return type(f) == "function" and f or nil
end

local function call(name, ...)
  local f = fn(name)
  if not f then
    return nil
  end
  local ok, value = pcall(f, ...)
  return ok and Guard.Safe(value) or nil
end

local function frameAlpha(alpha)
  local frame = rawget(_G, "LootFrame")
  if type(frame) == "table" and type(frame.SetAlpha) == "function" then
    pcall(frame.SetAlpha, frame, alpha)
  end
end

local function restore()
  if state.hidden then
    state.hidden = false
    frameAlpha(1)
  end
end

local function masterLoot()
  local method = call("GetLootMethod")
  if method == nil then
    local party = rawget(_G, "C_PartyInfo")
    method = type(party) == "table" and type(party.GetLootMethod) == "function" and select(2, pcall(party.GetLootMethod))
      or nil
    method = Guard.Safe(method)
  end
  local enum = rawget(_G, "Enum")
  local master = type(enum) == "table" and type(enum.LootMethod) == "table" and enum.LootMethod.Masterlooter
  return method == "master" or (master ~= nil and method == master)
end

local function wanted()
  if ns.db.settings.fastLoot ~= true or state.stopped then
    return false
  end
  if call("IsFishingLoot") == true or masterLoot() then
    return false
  end
  return Logic.AutoLootApplies(call("GetCVarBool", "autoLootDefault"), call("IsModifiedClick", "AUTOLOOTTOGGLE"))
end

-- The window as the client has it now; false when nothing was done.
function F.Run()
  if not wanted() then
    return false
  end
  local now = call("GetTime") or 0
  if Logic.IsRepeat(state.at, now) then
    return false
  end
  local count = call("GetNumLootItems")
  if type(count) ~= "number" or count < 1 then
    return false
  end
  state.at = now
  if ns.LootCapture then
    ns.LootCapture.Capture()
  end
  frameAlpha(0)
  state.hidden = true
  for _, slot in ipairs(Logic.Order(count)) do
    if state.stopped then
      break
    end
    call("LootSlot", slot)
  end
  -- Slots clear on the server answer: whatever is still there stays for the player to pick.
  C_Timer.After(0.3, restore)
  return true
end

ns.On("LOOT_READY", F.Run)
ns.On("LOOT_OPENED", F.Run)
ns.On("LOOT_CLOSED", function()
  state.at, state.stopped = nil, false
  restore()
end)
-- The window has to be seen for a confirmation and for a full bag.
ns.On("LOOT_BIND_CONFIRM", restore)
ns.On("UI_ERROR_MESSAGE", function(_, _, message)
  local full = rawget(_G, "ERR_INV_FULL")
  if state.hidden and full and Guard.Safe(message) == full then
    state.stopped = true
    restore()
  end
end)

function F.AddSettings(view)
  ns.AddHeading(view, "fastloot.card")
  view.stack:Add(
    ns.W.Toggle(view.content, {
      key = "fastloot.toggle",
      tooltip = "fastloot.toggle",
      tooltipText = "fastloot.tip",
      get = function()
        return ns.db.settings.fastLoot == true
      end,
      set = function(value)
        ns.Store.set("settings.fastLoot", value)
      end,
    }),
    { height = 24, gap = 6 }
  )
end
