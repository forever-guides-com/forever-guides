-- The inventory block under an item in every item tooltip: one line per character that owns it
-- (Modules/InventoryLogic.lua), then the price block (lowest, median and highest auction house price
-- with their dates, ProfessionShop.lua PriceLines). Only a post call (TooltipDataProcessor) or a script hook on the
-- tooltip frames, nothing of Blizzard's is replaced, so no taint. Tooltips are not protected,
-- the block is added in combat as well. The post call reaches every tooltip the client builds from
-- item data (bag, bank, merchant, auction, loot, bars, character and inspect frames, chat links,
-- compare tooltips, tooltips of other addons that use the client's tooltip frames). The addon's own
-- tooltips (W.Tooltip.Show) call T.AddForItem after they are built, so the block ends the tooltip.
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

-- tooltip -> the data table (post call) or true (script, AddForItem) of the build that got its block.
local marked = setmetatable({}, { __mode = "k" })
-- Tooltips the addon is still filling: the hooks leave them alone until T.AddForItem adds the block.
local held = setmetatable({}, { __mode = "k" })
local hooked = {}
local cache

-- Lines per item (and per guild, the guild bank row depends on it) for CACHE_SECONDS, valid for one
-- snapshot version.
local CACHE_SECONDS = 30
local CACHE_MAX = 200
local lineCache, lineCount, lineVersion = {}, 0, nil

local function dropLines()
  lineCache, lineCount, lineVersion = {}, 0, nil
end

-- Price blocks per item and stack size, same lifetime rules.
local priceCache, priceCount = {}, 0

local function dropPrices()
  priceCache, priceCount = {}, 0
end

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
  dropLines()
end)

ns.On("FG_PRICES_UPDATED", dropPrices)

-- The options that shape the text and the language.
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and (path:find("^settings%.inventory") or path == "settings.locale") then
    dropLines()
  end
  if type(path) == "string" and (path:find("^settings%.priceDb") or path == "settings.locale") then
    dropPrices()
  end
end)

-- The characters the tooltip knows (also used by the check command).
T.Characters = characters

-- The lines for an item id ({ text, kind, old }), nil when nobody owns it. The table is cached,
-- callers must not change it.
function T.Lines(itemId)
  if not Inv.Enabled() then
    return nil
  end
  Inv.Fresh()
  local now = Roster.Now()
  if lineVersion ~= Inv.version then
    dropLines()
    lineVersion = Inv.version
  end
  -- Only the bank of the guild the current character is in gets a row; the banks of other guilds
  -- stay stored and show again when a character of that guild is played.
  local guild
  if Inv.Option("inventoryGuildBank") ~= false then
    local guildKey, guildName = Inv.GuildKey()
    guild = guildKey and { key = guildKey, name = guildName } or nil
  end
  local key = guild and (guild.key .. "#" .. itemId) or itemId
  local hit = lineCache[key]
  if hit and now >= hit.at and now - hit.at < CACHE_SECONDS then
    return hit.lines or nil
  end
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
    now = now,
    guild = guild,
  })
  local model = Logic.Model(rows, Logic.MAX_LINES)
  local lines = model and Logic.Lines(model, Inv.Option("inventoryColors") ~= false)
  if lineCount >= CACHE_MAX then
    dropLines()
    lineVersion = Inv.version
  end
  if not lineCache[key] then
    lineCount = lineCount + 1
  end
  lineCache[key] = { at = now, lines = lines or false }
  return lines
end

local GREY = { total = 0.8, more = 0.7 }

local function lineColor(line)
  if line.kind == "header" then
    return ns.Theme.rgb("accent")
  end
  local v = line.old and 0.6 or GREY[line.kind] or 1
  return v, v, v
end

-- The number of items in the stack the tooltip shows, nil when unknown (then only the unit price is
-- shown). The place to extend once the tooltip data of a bag slot, bank slot or link is known to carry
-- the count reliably; read through T so a test can inject a count.
function T.StackCountOf()
  return nil
end

local function priceEnabled()
  local settings = type(ns.db) == "table" and ns.db.settings
  local p = type(settings) == "table" and settings.priceDb
  return not (type(p) == "table" and p.tooltip == false)
end

-- The price lines for an item and stack size ({ key, text }, header first), nil without a price or
-- while the price block is switched off. The table is cached, callers must not change it.
function T.PriceLines(itemId, stack)
  local shop = ns.ProfessionShop
  if not priceEnabled() or not (shop and shop.PriceLines) then
    return nil
  end
  local now = Roster.Now()
  local key = itemId .. "#" .. (stack or 1)
  local hit = priceCache[key]
  if hit and now >= hit.at and now - hit.at < CACHE_SECONDS then
    return hit.lines or nil
  end
  local ok, lines = pcall(shop.PriceLines, itemId, stack)
  if not ok then
    ns.Log.warn("price lines failed: %s", tostring(lines))
    lines = nil
  end
  if priceCount >= CACHE_MAX then
    dropPrices()
  end
  if not priceCache[key] then
    priceCount = priceCount + 1
  end
  priceCache[key] = { at = now, lines = lines or false }
  return lines
end

local MUTED_PRICE = { hint = true, old = true, neutralOnly = true }

local function priceColor(line)
  if line.key == "header" or line.key == "neutralHeader" then
    return ns.Theme.rgb("accent")
  end
  local v = MUTED_PRICE[line.key] and 0.7 or 1
  return v, v, v
end

-- Adds a blank line and each block to the tooltip: the owners first, the price below. data is the
-- post call data of the build (for the stack count). Returns true when it added something.
function T.Append(tooltip, itemId, data)
  if type(tooltip.AddLine) ~= "function" then
    return false
  end
  local added = false
  local lines = T.Lines(itemId)
  if lines then
    tooltip:AddLine(" ")
    for _, line in ipairs(lines) do
      local r, g, b = lineColor(line)
      tooltip:AddLine(line.text, r, g, b, false)
    end
    added = true
  end
  local counted, stack = pcall(T.StackCountOf, tooltip, data)
  local prices = T.PriceLines(itemId, counted and tonumber(stack) or nil)
  if prices then
    tooltip:AddLine(" ")
    for _, line in ipairs(prices) do
      local r, g, b = priceColor(line)
      tooltip:AddLine(line.text, r, g, b, false)
    end
    added = true
  end
  return added
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
  if type(tooltip) ~= "table" or type(data) ~= "table" or held[tooltip] or forbidden(tooltip) then
    return
  end
  local seen = marked[tooltip]
  if seen == true or seen == data then
    return
  end
  local id = T.ItemIdOf(tooltip, data)
  if id then
    marked[tooltip] = data
    T.Append(tooltip, id, data)
  end
end

-- Script and method hooks: the block once per build, the tooltip says which item it shows.
local function onSetItem(tooltip)
  if type(tooltip) ~= "table" or marked[tooltip] ~= nil or held[tooltip] or forbidden(tooltip) then
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

-- The addon fills a tooltip itself (W.Tooltip.Show): the hooks skip it while held, so the block can
-- come after the addon's own lines. Holding starts a new build (the mark of the last one goes);
-- AddForItem lets go again, as does hiding the tooltip.
function T.Hold(tooltip, on)
  if type(tooltip) == "table" then
    held[tooltip] = on and true or nil
    if on then
      marked[tooltip] = nil
    end
  end
end

-- The one entry point for the addon's own tooltips: adds the block for an item id or link, once per
-- build of the tooltip (the hooks above share the same mark). Returns true when it added lines.
function T.AddForItem(tooltip, item)
  if type(tooltip) ~= "table" then
    return false
  end
  held[tooltip] = nil
  if marked[tooltip] ~= nil or forbidden(tooltip) then
    return false
  end
  local id = plainId(item)
  if not id then
    return false
  end
  marked[tooltip] = true
  return T.Append(tooltip, id)
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
  pcall(frame.HookScript, frame, "OnHide", function(tooltip)
    held[tooltip] = nil
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
