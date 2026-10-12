-- The inventory block under an item in every item tooltip: one line per character that owns it
-- (Modules/InventoryLogic.lua). Only a post call (TooltipDataProcessor) or a script hook on the
-- tooltip frames, nothing of Blizzard's is replaced, so no taint. Tooltips are not protected,
-- the block is added in combat as well.
local _, ns = ...
local Logic, Inv, Roster = ns.InventoryLogic, ns.Inventory, ns.CharRoster

local T = {}
ns.InventoryTooltip = T

-- Tooltip frames of the script fallback (clients without TooltipDataProcessor).
local FRAMES = {
  "GameTooltip",
  "ItemRefTooltip",
  "ShoppingTooltip1",
  "ShoppingTooltip2",
  "ItemRefShoppingTooltip1",
  "ItemRefShoppingTooltip2",
}

-- tooltip -> the data table (post call) or true (script) of the build that got its block.
local marked = setmetatable({}, { __mode = "k" })
local hooked = {}
local cache

-- All characters with their key, hidden flag and faction; the current one is always in.
local function characters()
  if cache then
    return cache
  end
  local list, current = Roster.List(), Roster.CurrentKey()
  local found = false
  for _, c in ipairs(list) do
    found = found or c.current
  end
  if current and not found then
    local ok, name, surname = pcall(UnitName, "player")
    local _, _, class = pcall(UnitClass, "player")
    list[#list + 1] = {
      key = current,
      display = (ok and Roster.JoinName(name, surname)) or current,
      class = class,
      current = true,
    }
  end
  cache = list
  return list
end

ns.On("FG_ROSTER_CHANGED", function()
  cache = nil
end)

-- The characters the tooltip knows (also used by the check command).
T.Characters = characters

-- The lines for an item id ({ text, kind, old }), nil when there is nothing to show.
function T.Lines(itemId)
  if not Inv.Enabled() then
    return nil
  end
  Inv.Fresh()
  local chars = characters()
  local faction
  if Inv.Option("inventoryFaction") == true then
    for _, c in ipairs(chars) do
      if c.current then
        faction = c.faction
      end
    end
  end
  local stored = ns.db and ns.db.inventory
  local rows = Logic.Rows(chars, type(stored) == "table" and stored or {}, itemId, {
    faction = faction,
    currentFirst = Inv.Option("inventoryCurrentFirst") ~= false,
    now = Roster.Now(),
  })
  local model = Logic.Model(rows, Logic.MAX_LINES)
  return model and Logic.Lines(model, Inv.Option("inventoryColors") ~= false)
end

local GREY = { total = 0.8, more = 0.7 }

local function lineColor(line)
  if line.kind == "header" then
    return ns.Theme.rgb("accent")
  end
  local v = line.old and 0.6 or GREY[line.kind] or 1
  return v, v, v
end

-- Adds a blank line and the block to the tooltip. Returns true when it added something.
function T.Append(tooltip, itemId)
  local lines = T.Lines(itemId)
  if not lines or type(tooltip.AddLine) ~= "function" then
    return false
  end
  tooltip:AddLine(" ")
  for _, line in ipairs(lines) do
    local r, g, b = lineColor(line)
    tooltip:AddLine(line.text, r, g, b, false)
  end
  return true
end

local function forbidden(tooltip)
  if type(tooltip.IsForbidden) ~= "function" then
    return false
  end
  local ok, value = pcall(tooltip.IsForbidden, tooltip)
  return ok and value == true
end

-- An item id from a number or link; nil for anything else, secret values and errors included.
local function plainId(v)
  if v == nil then
    return nil
  end
  local guard = rawget(_G, "canaccessvalue")
  if type(guard) == "function" then
    local ok, can = pcall(guard, v)
    if not (ok and can ~= false) then
      return nil
    end
  end
  local ok, id = pcall(Logic.ItemId, v)
  return ok and id or nil
end

-- The item of a tooltip build: the post call data (id, then hyperlink), else what the tooltip
-- itself says (GetItem gives name, link and in some clients the id).
function T.ItemIdOf(tooltip, data)
  local id
  if type(data) == "table" then
    local ok, found = pcall(function()
      return plainId(data.id) or plainId(data.hyperlink)
    end)
    id = ok and found or nil
  end
  if not id and type(tooltip) == "table" and type(tooltip.GetItem) == "function" then
    local ok, _, link, extra = pcall(tooltip.GetItem, tooltip)
    id = ok and (plainId(link) or plainId(extra)) or nil
  end
  return id
end

-- Post call: `data` is a new table for every build of the tooltip.
function T.OnItem(tooltip, data)
  if type(tooltip) ~= "table" or type(data) ~= "table" or forbidden(tooltip) then
    return
  end
  local seen = marked[tooltip]
  if seen == true or seen == data then
    return
  end
  local id = T.ItemIdOf(tooltip, data)
  if id then
    marked[tooltip] = data
    T.Append(tooltip, id)
  end
end

-- Script and method hooks: the block once per build, the tooltip says which item it shows.
local function onSetItem(tooltip)
  if type(tooltip) ~= "table" or marked[tooltip] ~= nil or forbidden(tooltip) then
    return
  end
  local id = T.ItemIdOf(tooltip)
  if id then
    marked[tooltip] = true
    if T.Append(tooltip, id) and type(tooltip.Show) == "function" then
      tooltip:Show()
    end
  end
end

-- Methods that fill a tooltip with an item, for clients where neither the post call nor the
-- script fires. The hook runs after the method, so GetItem already knows the item.
local METHODS = {
  "SetBagItem",
  "SetInventoryItem",
  "SetHyperlink",
  "SetMerchantItem",
  "SetLootItem",
  "SetAuctionItem",
  "SetGuildBankItem",
  "SetInboxItem",
  "SetSendMailItem",
  "SetTradePlayerItem",
  "SetTradeTargetItem",
  "SetQuestItem",
  "SetQuestLogItem",
}

-- Which tooltip APIs carry the block: { postcall, script, methods } (booleans).
T.apis = { postcall = false, script = false, methods = false }
local methodHooked = {}

local function hookScripts(name, frame)
  if hooked[name] or type(frame.HookScript) ~= "function" then
    return
  end
  local set = pcall(frame.HookScript, frame, "OnTooltipSetItem", function(tooltip)
    ns.Safe("inventory-tooltip", onSetItem, tooltip)
  end)
  local cleared = pcall(frame.HookScript, frame, "OnTooltipCleared", function(tooltip)
    marked[tooltip] = nil
  end)
  hooked[name] = set and cleared or nil
  T.apis.script = T.apis.script or hooked[name] == true
end

local function hookMethods(name, frame)
  local hook = rawget(_G, "hooksecurefunc")
  if type(hook) ~= "function" then
    return
  end
  for _, method in ipairs(METHODS) do
    local key = name .. "." .. method
    if not methodHooked[key] and type(frame[method]) == "function" then
      methodHooked[key] = pcall(hook, frame, method, function(tooltip)
        ns.Safe("inventory-tooltip", onSetItem, tooltip)
      end)
      T.apis.methods = T.apis.methods or methodHooked[key] == true
    end
  end
end

-- "postcall", "script", "methods" (the first that works, see T.apis for all) or nil. Every API
-- that exists is hooked, the block is added once per build whichever fires first. Safe to call again.
function T.Install()
  local processor, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
  local itemType = type(enum) == "table" and type(enum.TooltipDataType) == "table" and enum.TooltipDataType.Item
  if not T.apis.postcall and ns.can.tooltipPostCall and type(processor) == "table" and itemType ~= nil then
    T.apis.postcall = pcall(processor.AddTooltipPostCall, itemType, function(tooltip, data)
      ns.Safe("inventory-tooltip", T.OnItem, tooltip, data)
    end)
  end
  for _, name in ipairs(FRAMES) do
    local frame = rawget(_G, name)
    if type(frame) == "table" then
      hookScripts(name, frame)
      hookMethods(name, frame)
    end
  end
  T.mode = (T.apis.postcall and "postcall") or (T.apis.script and "script") or (T.apis.methods and "methods") or nil
  return T.mode
end

ns.On("PLAYER_LOGIN", T.Install)
ns.On("ADDON_LOADED", T.Install)
