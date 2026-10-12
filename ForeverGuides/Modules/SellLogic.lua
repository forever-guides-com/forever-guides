-- Merchant sell helper, the pure side: which bag items the rules select and which protections keep
-- an item. No game access, Modules/SellHelper.lua reads the bags and sells.
--
-- item = {
--   bag, slot, itemID, link, count, quality, price (copper per piece, nil = unknown), class,
--   equipLoc, level (item level, nil = unknown), bound (nil = unknown), locked, noValue, reagent,
--   name, icon
-- }
-- ctx = {
--   setIds = { [itemId] = true } items of the equipment sets, worn = { [itemId] = true },
--   equippedLevel = { [slotId] = item level, 0 for an empty slot, nil when the level is unknown }
-- }
local _, ns = ...

local Logic = {}
ns.SellLogic = Logic

ns.AddLocale("enUS", {
  ["sell.reason.gray"] = "Gray",
  ["sell.reason.white"] = "White < %d",
  ["sell.reason.green"] = "Green < %d",
  ["sell.reason.blue"] = "Blue < %d",
  ["sell.reason.epic"] = "Epic < %d",
  ["sell.reason.whiteAll"] = "White (all)",
  ["sell.reason.greenAll"] = "Green (all)",
  ["sell.reason.blueAll"] = "Blue (all)",
  ["sell.reason.epicAll"] = "Epic (all)",
})
ns.AddLocale("deDE", {
  ["sell.reason.gray"] = "Grau",
  ["sell.reason.white"] = "Weiß < %d",
  ["sell.reason.green"] = "Grün < %d",
  ["sell.reason.blue"] = "Blau < %d",
  ["sell.reason.epic"] = "Episch < %d",
  ["sell.reason.whiteAll"] = "Weiß (alle)",
  ["sell.reason.greenAll"] = "Grün (alle)",
  ["sell.reason.blueAll"] = "Blau (alle)",
  ["sell.reason.epicAll"] = "Episch (alle)",
})

-- The merchant keeps this many sold stacks for the buyback.
Logic.MAX_BUYBACK = 12
Logic.MAX_PROTECT = 200
Logic.MAX_LEVEL = 9999
Logic.MAX_ITEM_ID = 1e8
Logic.BIND_MODES = { "all", "unbound", "bound" }

local QUALITY_POOR = 0
-- The rules by item quality: rule name, the key of the item level limit and the key of the "all"
-- switch in the rules.
local GEAR_RULES = {
  [1] = { name = "white", limit = "whiteBelow", all = "whiteAll" },
  [2] = { name = "green", limit = "greenBelow", all = "greenAll" },
  [3] = { name = "blue", limit = "blueBelow", all = "blueAll" },
  [4] = { name = "epic", limit = "epicBelow", all = "epicAll" },
}
local CLASS_CONSUMABLE, CLASS_TRADEGOODS = 0, 7

-- Equipment slots an item type competes with. Shirts, tabards and bags have no entry: the item
-- level rules never touch them.
Logic.SLOTS = {
  INVTYPE_HEAD = { 1 },
  INVTYPE_NECK = { 2 },
  INVTYPE_SHOULDER = { 3 },
  INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 },
  INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_2HWEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_SHIELD = { 17 },
  INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 16 },
  INVTYPE_RANGEDRIGHT = { 16 },
  INVTYPE_THROWN = { 18 },
  INVTYPE_RELIC = { 18 },
}

local function number(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Settings ------------------------------------------------------------------------------------

-- A stored value, else the default of Core/Store.lua.
local function pick(settings, key)
  local value
  if type(settings) == "table" then
    value = settings[key]
  end
  if value == nil then
    value = ns.Store.defaults.settings[key]
  end
  return value
end

-- Whole item level between 0 (rule off) and MAX_LEVEL.
function Logic.CleanLevel(value)
  value = tonumber(value)
  if not number(value) then
    return 0
  end
  return math.max(0, math.min(Logic.MAX_LEVEL, math.floor(value + 0.5)))
end

function Logic.CleanBind(value)
  for _, mode in ipairs(Logic.BIND_MODES) do
    if value == mode then
      return mode
    end
  end
  return "all"
end

-- Item ids from free text: plain numbers and pasted item links, any separator. Order kept,
-- duplicates and values outside 1..MAX_ITEM_ID dropped.
function Logic.ParseIds(text)
  local list, seen = {}, {}
  if type(text) ~= "string" then
    return list
  end
  text = text:gsub("|Hitem:(%d+)[^|]*|h%[[^%]]*%]|h", " %1 ")
  for token in text:gmatch("[^,;%s]+") do
    local id = token:match("^%d+$") and tonumber(token)
    if id and id >= 1 and id <= Logic.MAX_ITEM_ID and not seen[id] and #list < Logic.MAX_PROTECT then
      seen[id] = true
      list[#list + 1] = id
    end
  end
  return list
end

function Logic.JoinIds(list)
  return table.concat(list, ", ")
end

-- Item id of a link or of a plain number, nil otherwise.
function Logic.ItemId(link)
  if number(link) then
    return link
  end
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- The stored text with one more id, unchanged when it is no id or already in the list.
function Logic.AddId(text, link)
  local id = Logic.ItemId(link)
  local list = Logic.ParseIds(text)
  if not id then
    return Logic.JoinIds(list)
  end
  for _, known in ipairs(list) do
    if known == id then
      return Logic.JoinIds(list)
    end
  end
  if #list < Logic.MAX_PROTECT then
    list[#list + 1] = id
  end
  return Logic.JoinIds(list)
end

-- The rules of the settings table. Safety switches read as on when the value is missing.
function Logic.Rules(settings)
  local protect = {}
  for _, id in ipairs(Logic.ParseIds(pick(settings, "sellProtect"))) do
    protect[id] = true
  end
  return {
    gray = pick(settings, "sellGray") ~= false,
    whiteBelow = Logic.CleanLevel(pick(settings, "sellWhiteBelow")),
    greenBelow = Logic.CleanLevel(pick(settings, "sellGreenBelow")),
    blueBelow = Logic.CleanLevel(pick(settings, "sellBlueBelow")),
    epicBelow = Logic.CleanLevel(pick(settings, "sellEpicBelow")),
    whiteAll = pick(settings, "sellWhiteAll") == true,
    greenAll = pick(settings, "sellGreenAll") == true,
    blueAll = pick(settings, "sellBlueAll") == true,
    epicAll = pick(settings, "sellEpicAll") == true,
    bind = Logic.CleanBind(pick(settings, "sellBind")),
    keepConsumables = pick(settings, "sellKeepConsumables") ~= false,
    keepReagents = pick(settings, "sellKeepReagents") ~= false,
    keepUpgrades = pick(settings, "sellKeepUpgrades") ~= false,
    native = pick(settings, "sellNative") ~= false,
    auto = pick(settings, "sellAuto") == true,
    protect = protect,
  }
end

-- Rules ---------------------------------------------------------------------------------------

function Logic.Key(item)
  return item.bag .. ":" .. item.slot
end

-- The item level limit of the gear rule of a quality, 0 when the quality has none or the rule is off.
function Logic.Limit(quality, rules)
  local def = GEAR_RULES[quality]
  return def and rules[def.limit] or 0
end

-- The rule that selects an item by quality ("gray", "white", "green", "blue", "epic") and its item
-- level limit. The "all" switch of a quality ("whiteAll" ...) selects every item of it, gear or
-- not, without a limit: like gray it ignores the item level, so the upgrade check does not apply.
local function ruleOf(item, rules)
  local quality = item.quality
  if quality == QUALITY_POOR then
    return rules.gray and "gray" or nil
  end
  local def = GEAR_RULES[quality]
  if def and rules[def.all] then
    return def.name .. "All"
  end
  local limit = Logic.Limit(quality, rules)
  if limit <= 0 or not Logic.SLOTS[item.equipLoc] then
    return nil
  end
  return GEAR_RULES[quality].name, limit
end

-- True when the item is at least as good as what the slots hold now. An unknown level counts as
-- an upgrade: when in doubt the item stays.
local function isUpgrade(item, ctx)
  local lowest
  for _, slot in ipairs(Logic.SLOTS[item.equipLoc]) do
    local worn = ctx.equippedLevel and ctx.equippedLevel[slot]
    if not number(worn) then
      return true
    end
    lowest = lowest and math.min(lowest, worn) or worn
  end
  return item.level >= lowest
end

-- The reason an item that a rule selects stays anyway, nil when it may be sold.
local function protection(item, rules, ctx, limited)
  local id = item.itemID
  if rules.protect[id] then
    return "protected"
  end
  if ctx.setIds and ctx.setIds[id] then
    return "set"
  end
  if ctx.worn and ctx.worn[id] then
    return "worn"
  end
  if item.locked then
    return "locked"
  end
  if item.noValue or not number(item.price) or item.price <= 0 then
    return "price"
  end
  if rules.bind == "unbound" and item.bound ~= false then
    return "bind"
  end
  if rules.bind == "bound" and item.bound ~= true then
    return "bind"
  end
  if rules.keepConsumables and item.class == CLASS_CONSUMABLE then
    return "consumable"
  end
  if rules.keepReagents and (item.reagent == true or item.class == CLASS_TRADEGOODS) then
    return "reagent"
  end
  if limited and rules.keepUpgrades and isUpgrade(item, ctx) then
    return "upgrade"
  end
end

-- items: list of item tables in bag order. Returns
--   { list = { { bag, slot, itemID, link, count, price (stack total), unit, reason, limit } },
--     total = copper, kept = { [why] = count } }
-- kept counts the items a rule selected and a protection held back.
function Logic.Evaluate(items, rules, ctx)
  ctx = ctx or {}
  local out = { list = {}, total = 0, kept = {} }
  for _, item in ipairs(items) do
    local reason, limit = ruleOf(item, rules)
    if reason and limit and not number(item.level) then
      out.kept.level = (out.kept.level or 0) + 1
    elseif reason and not (limit and item.level >= limit) then
      local why = protection(item, rules, ctx, limit ~= nil)
      if why then
        out.kept[why] = (out.kept[why] or 0) + 1
      else
        local count = number(item.count) and item.count >= 1 and math.floor(item.count) or 1
        local entry = {
          bag = item.bag,
          slot = item.slot,
          itemID = item.itemID,
          link = item.link,
          count = count,
          unit = item.price,
          price = item.price * count,
          reason = reason,
          limit = limit,
          quality = item.quality,
          name = item.name,
          icon = item.icon,
        }
        out.list[#out.list + 1] = entry
        out.total = out.total + entry.price
      end
    end
  end
  return out
end

function Logic.Total(list)
  local sum = 0
  for _, entry in ipairs(list) do
    sum = sum + entry.price
  end
  return sum
end

-- The entries whose key is not in `off`.
function Logic.Choose(list, off)
  local out = {}
  for _, entry in ipairs(list) do
    if not (off and off[Logic.Key(entry)]) then
      out[#out + 1] = entry
    end
  end
  return out
end

function Logic.KeptCount(kept)
  local n = 0
  for _, count in pairs(kept or {}) do
    n = n + count
  end
  return n
end

-- More stacks than the buyback list holds: the oldest ones cannot be bought back any more.
function Logic.OverBuyback(list)
  return #list > Logic.MAX_BUYBACK
end

-- The game's own "sell all junk" may replace the loop only when it sells exactly what the rules
-- selected: only the gray rule is on and every gray item that has a value is in the chosen list.
function Logic.NativeFits(items, list, rules)
  if not (rules.native and rules.gray) or #list == 0 then
    return false
  end
  for _, def in pairs(GEAR_RULES) do
    if (rules[def.limit] or 0) ~= 0 or rules[def.all] then
      return false
    end
  end
  local chosen = {}
  for _, entry in ipairs(list) do
    chosen[Logic.Key(entry)] = true
  end
  for _, item in ipairs(items) do
    if item.quality == QUALITY_POOR and not item.noValue and not chosen[Logic.Key(item)] then
      return false
    end
  end
  return true
end

-- Coin text for a copper amount, "0" for nothing.
function Logic.Money(copper, plain)
  return ns.CostLogic.Format(copper, { plain = plain }) or "0"
end

-- Text of the reason column.
function Logic.ReasonText(entry)
  local text = ns.L["sell.reason." .. entry.reason]
  return entry.limit and string.format(text, entry.limit) or text
end
