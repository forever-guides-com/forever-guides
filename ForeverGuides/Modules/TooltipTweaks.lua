-- Extra lines and behaviour of the game's tooltips (settings area "Tooltips", Modules/TooltipSettings.lua):
-- item level, sell price and ids, the target and class color of units, the guild rank, anchor at the
-- cursor, hiding unit tooltips in combat and a scale. Only post calls (TooltipDataProcessor), script hooks
-- and a post hook of GameTooltip_SetDefaultAnchor, nothing of Blizzard's is replaced. Tooltips are not
-- protected, so nothing here waits for the end of combat. Every option is read at the moment a tooltip
-- is built (the scale is applied at once), so switching one off needs no cleanup.
local _, ns = ...
local I = ns.ItemInfo

local TT = {}
ns.TooltipTweaks = TT

ns.AddLocale("enUS", {
  ["tip.line.itemLevel"] = "Item level: %d",
  ["tip.line.sellPrice"] = "Vendor (each): %s",
  ["tip.line.itemId"] = "Item ID: %d",
  ["tip.line.spellId"] = "Spell ID: %d",
  ["tip.line.target"] = "Target: %s",
  ["tip.line.guildRank"] = "%s - %s",
})
ns.AddLocale("deDE", {
  ["tip.line.itemLevel"] = "Itemlevel: %d",
  ["tip.line.sellPrice"] = "Händler (pro Stück): %s",
  ["tip.line.itemId"] = "Item-ID: %d",
  ["tip.line.spellId"] = "Zauber-ID: %d",
  ["tip.line.target"] = "Ziel: %s",
  ["tip.line.guildRank"] = "%s - %s",
})

TT.SCALE_MIN, TT.SCALE_MAX, TT.SCALE_STEP = 70, 150, 5

local FRAMES = {
  "GameTooltip",
  "ItemRefTooltip",
  "ShoppingTooltip1",
  "ShoppingTooltip2",
  "ItemRefShoppingTooltip1",
  "ItemRefShoppingTooltip2",
}

function TT.Option(key)
  local settings = ns.db and ns.db.settings
  local value = settings and settings[key]
  if value == nil then
    value = ns.Store.defaults.settings[key]
  end
  return value
end

local function on(key)
  return TT.Option(key) == true
end

-- A value the addon may use: restricted clients hand out secret values for some unit data.
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

local function forbidden(tooltip)
  if type(tooltip.IsForbidden) ~= "function" then
    return false
  end
  local ok, value = pcall(tooltip.IsForbidden, tooltip)
  return ok and value == true
end

-- The class color the game uses, the theme's table when the client has none.
function TT.ClassRGB(class)
  local colors = rawget(_G, "RAID_CLASS_COLORS")
  local c = type(colors) == "table" and type(class) == "string" and colors[class] or nil
  if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
    return c.r, c.g, c.b
  end
  if type(class) == "string" and ns.Theme.classColors[class] then
    return ns.Theme.rgb(class)
  end
end

-- Items ---------------------------------------------------------------------------------------------------

local function sellPrice(link)
  local api = rawget(_G, "C_Item")
  local f = type(api) == "table" and api.GetItemInfo or rawget(_G, "GetItemInfo")
  if type(f) ~= "function" then
    return nil
  end
  local ok, price = pcall(function()
    return (select(11, f(link)))
  end)
  return ok and price or nil
end

-- Does the tooltip already say the item level (the client's own line)?
local function hasLevelLine(tooltip)
  local format = rawget(_G, "ITEM_LEVEL")
  local prefix = type(format) == "string" and format:match("^(.-)%%d")
  local name = type(tooltip.GetName) == "function" and tooltip:GetName()
  if not prefix or prefix == "" or not name then
    return false
  end
  for line = 2, math.min(tooltip:NumLines(), 8) do
    local fs = rawget(_G, name .. "TextLeft" .. line)
    local text = fs and fs:GetText()
    if readable(text, "string") and text:find(prefix, 1, true) == 1 then
      return true
    end
  end
  return false
end

-- Lines for an item: { text, r, g, b }. The client's own money line (bag and merchant slots) is not repeated
-- for a single item; a stack gets the price of ONE item next to the client's total.
function TT.ItemLines(tooltip, itemId, stack)
  local out = {}
  local link
  if type(tooltip.GetItem) == "function" then
    local ok, _, found = pcall(tooltip.GetItem, tooltip)
    link = ok and readable(found, "string") and found or nil
  end
  link = link or ("item:" .. itemId)
  local r, g, b = ns.Theme.rgb("textMuted")
  if on("tipItemLevel") and I.isGear(link) and not hasLevelLine(tooltip) then
    local level = I.itemLevel(link)
    if level then
      out[#out + 1] = { string.format(ns.L["tip.line.itemLevel"], level), r, g, b }
    end
  end
  local stacked = type(stack) == "number" and stack > 1
  if on("tipSellPrice") and (stacked or (tonumber(tooltip.shownMoneyFrames) or 0) == 0) then
    local price = sellPrice(link)
    if readable(price, "number") and price > 0 then
      out[#out + 1] = { string.format(ns.L["tip.line.sellPrice"], ns.CostLogic.Format(price) or price), r, g, b }
    end
  end
  if on("tipItemId") then
    out[#out + 1] = { string.format(ns.L["tip.line.itemId"], itemId), r, g, b }
  end
  return out
end

-- Called by InventoryTooltip.Append for every item tooltip build, before the inventory block.
function TT.AddItemLines(tooltip, itemId, stack)
  local lines = TT.ItemLines(tooltip, itemId, stack)
  for _, line in ipairs(lines) do
    tooltip:AddLine(line[1], line[2], line[3], line[4], false)
  end
  return #lines > 0
end

-- Units ---------------------------------------------------------------------------------------------------

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  if ok and (a == nil or readable(a, type(a))) and (b == nil or readable(b, type(b))) then
    return a, b
  end
end

local function unitOf(tooltip)
  if type(tooltip.GetUnit) ~= "function" then
    return nil
  end
  local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
  return ok and readable(unit, "string") and unit or nil
end

local function leftLine(tooltip, index)
  local name = type(tooltip.GetName) == "function" and tooltip:GetName()
  return name and rawget(_G, name .. "TextLeft" .. index) or nil
end

local function guildRank(tooltip, unit)
  local guild, rank = call(rawget(_G, "GetGuildInfo"), unit)
  if not (readable(guild, "string") and readable(rank, "string") and rank ~= "") then
    return
  end
  for index = 2, math.min(tooltip:NumLines(), 3) do
    local fs = leftLine(tooltip, index)
    local text = fs and fs:GetText()
    if readable(text, "string") and text:find(guild, 1, true) and not text:find(rank, 1, true) then
      fs:SetText(string.format(ns.L["tip.line.guildRank"], text, rank))
      return
    end
  end
end

-- tooltip -> the post call data of the build that got its lines (a new table for every build), so a repeated
-- call for one build adds them once. The script hooks only run without post calls.
local marked = setmetatable({}, { __mode = "k" })

function TT.OnUnit(tooltip, data)
  if type(tooltip) ~= "table" or forbidden(tooltip) then
    return
  end
  if data ~= nil and marked[tooltip] == data then
    return
  end
  local unit = unitOf(tooltip)
  if not unit then
    return
  end
  marked[tooltip] = data
  if on("tipHideCombat") and ns.InCombat() then
    tooltip:Hide()
    return
  end
  local isPlayer = call(rawget(_G, "UnitIsPlayer"), unit) == true
  if isPlayer then
    if on("tipClassColor") then
      local _, class = call(rawget(_G, "UnitClass"), unit)
      local r, g, b = TT.ClassRGB(class)
      local title = leftLine(tooltip, 1)
      if r and title then
        title:SetTextColor(r, g, b)
      end
    end
    if on("tipGuildRank") then
      guildRank(tooltip, unit)
    end
  end
  if on("tipUnitTarget") then
    local name = call(rawget(_G, "UnitName"), unit .. "target")
    if readable(name, "string") and name ~= "" then
      local r, g, b = ns.Theme.rgb("text")
      if call(rawget(_G, "UnitIsPlayer"), unit .. "target") == true then
        local _, class = call(rawget(_G, "UnitClass"), unit .. "target")
        r, g, b = TT.ClassRGB(class)
      end
      tooltip:AddLine(string.format(ns.L["tip.line.target"], name), r, g, b, false)
    end
  end
  if type(tooltip.Show) == "function" then
    tooltip:Show()
  end
end

-- Spells --------------------------------------------------------------------------------------------------

local spellMarked = setmetatable({}, { __mode = "k" })

function TT.OnSpell(tooltip, data)
  if type(tooltip) ~= "table" or forbidden(tooltip) or not on("tipSpellId") then
    return
  end
  if data ~= nil and spellMarked[tooltip] == data then
    return
  end
  local id = type(data) == "table" and data.id or nil
  if id == nil and type(tooltip.GetSpell) == "function" then
    local ok, _, found = pcall(tooltip.GetSpell, tooltip)
    id = ok and found or nil
  end
  if readable(id, "number") and id > 0 then
    spellMarked[tooltip] = data
    local r, g, b = ns.Theme.rgb("textMuted")
    tooltip:AddLine(string.format(ns.L["tip.line.spellId"], id), r, g, b, false)
    if type(tooltip.Show) == "function" then
      tooltip:Show()
    end
  end
end

-- Position and scale --------------------------------------------------------------------------------------

local function onDefaultAnchor(tooltip, parent)
  if on("tipCursor") and type(tooltip) == "table" and not forbidden(tooltip) and type(parent) == "table" then
    pcall(tooltip.SetOwner, tooltip, parent, "ANCHOR_CURSOR")
  end
end

local baseScale = setmetatable({}, { __mode = "k" }) -- tooltip frame -> its scale before the first change

-- Scales every tooltip frame to the option; 100 gives the first scale of the frame back.
function TT.ApplyScale()
  local percent = tonumber(TT.Option("tipScale")) or 100
  percent = math.max(TT.SCALE_MIN, math.min(TT.SCALE_MAX, percent))
  for _, name in ipairs(FRAMES) do
    local frame = rawget(_G, name)
    if type(frame) == "table" and type(frame.SetScale) == "function" then
      if baseScale[frame] == nil and percent ~= 100 then
        baseScale[frame] = frame:GetScale() or 1
      end
      if baseScale[frame] ~= nil then
        frame:SetScale(baseScale[frame] * percent / 100)
        if percent == 100 then
          baseScale[frame] = nil
        end
      end
    end
  end
end

-- Hooks ---------------------------------------------------------------------------------------------------

TT.apis = { postcall = false, script = false, anchor = false }
local hooked = {}

local function hookScripts(name, frame)
  if hooked[name] or type(frame.HookScript) ~= "function" then
    return
  end
  local unit = pcall(frame.HookScript, frame, "OnTooltipSetUnit", function(tooltip)
    if not TT.apis.postcall then
      ns.Safe("tooltip-unit", TT.OnUnit, tooltip)
    end
  end)
  pcall(frame.HookScript, frame, "OnTooltipSetSpell", function(tooltip)
    if not TT.apis.postcall then
      ns.Safe("tooltip-spell", TT.OnSpell, tooltip)
    end
  end)
  hooked[name] = unit or nil
  TT.apis.script = TT.apis.script or hooked[name] == true
end

-- Safe to call again: every API is hooked once.
function TT.Install()
  local processor, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
  local types = type(enum) == "table" and type(enum.TooltipDataType) == "table" and enum.TooltipDataType
  if
    not TT.apis.postcall
    and ns.can.tooltipPostCall
    and type(processor) == "table"
    and types
    and types.Unit ~= nil
    and types.Spell ~= nil
  then
    local unit = pcall(processor.AddTooltipPostCall, types.Unit, function(tooltip, data)
      ns.Safe("tooltip-unit", TT.OnUnit, tooltip, data)
    end)
    local spell = pcall(processor.AddTooltipPostCall, types.Spell, function(tooltip, data)
      ns.Safe("tooltip-spell", TT.OnSpell, tooltip, data)
    end)
    TT.apis.postcall = unit and spell
  end
  for _, name in ipairs(FRAMES) do
    local frame = rawget(_G, name)
    if type(frame) == "table" then
      hookScripts(name, frame)
    end
  end
  local hook = rawget(_G, "hooksecurefunc")
  if
    not TT.apis.anchor
    and type(hook) == "function"
    and type(rawget(_G, "GameTooltip_SetDefaultAnchor")) == "function"
  then
    TT.apis.anchor = pcall(hook, "GameTooltip_SetDefaultAnchor", function(tooltip, parent)
      ns.Safe("tooltip-anchor", onDefaultAnchor, tooltip, parent)
    end)
  end
  TT.ApplyScale()
end

ns.On("PLAYER_LOGIN", TT.Install)
ns.On("ADDON_LOADED", TT.Install)
ns.On("PLAYER_REGEN_DISABLED", function()
  local tooltip = rawget(_G, "GameTooltip")
  if on("tipHideCombat") and type(tooltip) == "table" and unitOf(tooltip) then
    tooltip:Hide()
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.tipScale" then
    TT.ApplyScale()
  end
end)
