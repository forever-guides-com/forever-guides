-- Item facts read from a link, an item location or the game's item APIs. Pure functions, no
-- frames and no consumers: ItemLevelOverlay and the item test build on them.
-- Every game API is looked up when called and wrapped in pcall, so a client without it gives nil, never an error.
local _, ns = ...

local I = {}
ns.ItemInfo = I

-- Equipment slots 1..19 of the paper doll (inventory slot id, frame name is "Character" .. name).
-- overlay = false: shirt and tabard carry no item level worth showing.
I.SLOTS = {
  { id = 1, name = "HeadSlot" },
  { id = 2, name = "NeckSlot" },
  { id = 3, name = "ShoulderSlot" },
  { id = 4, name = "ShirtSlot", overlay = false },
  { id = 5, name = "ChestSlot" },
  { id = 6, name = "WaistSlot" },
  { id = 7, name = "LegsSlot" },
  { id = 8, name = "FeetSlot" },
  { id = 9, name = "WristSlot" },
  { id = 10, name = "HandsSlot" },
  { id = 11, name = "Finger0Slot" },
  { id = 12, name = "Finger1Slot" },
  { id = 13, name = "Trinket0Slot" },
  { id = 14, name = "Trinket1Slot" },
  { id = 15, name = "BackSlot" },
  { id = 16, name = "MainHandSlot" },
  { id = 17, name = "SecondaryHandSlot" },
  { id = 18, name = "RangedSlot" },
  { id = 19, name = "TabardSlot", overlay = false },
}

-- A finite number the addon may compare (restricted clients hand out secret values).
function I.readable(v)
  if type(v) ~= "number" then
    return false
  end
  local guard = rawget(_G, "canaccessvalue")
  if type(guard) == "function" then
    local ok, can = pcall(guard, v)
    if not (ok and can ~= false) then
      return false
    end
  end
  return v == v and v > -math.huge and v < math.huge
end
local readable = I.readable

local function global(name)
  local f = rawget(_G, name)
  return type(f) == "function" and f or nil
end

local function method(tableName, name)
  local t = rawget(_G, tableName)
  return type(t) == "table" and type(t[name]) == "function" and t[name] or nil
end

-- Item level sources in the order they are tried. fn(location, link) returns a number or nothing.
-- label is the short name the probe prints.
I.SOURCES = {
  {
    label = "location",
    name = "C_Item.GetCurrentItemLevel",
    fn = function(location)
      local f = method("C_Item", "GetCurrentItemLevel")
      if f and type(location) == "table" then
        return (f(location))
      end
    end,
  },
  {
    label = "detailed",
    name = "C_Item.GetDetailedItemLevelInfo",
    fn = function(_, link)
      local f = method("C_Item", "GetDetailedItemLevelInfo")
      if f and link ~= nil then
        return (f(link))
      end
    end,
  },
  {
    label = "info",
    name = "GetItemInfo",
    fn = function(_, link)
      local f = method("C_Item", "GetItemInfo") or global("GetItemInfo")
      if f and link ~= nil then
        return (select(4, f(link)))
      end
    end,
  },
}

-- itemLevel(location [, link]) or itemLevel(link): the level and the label of the source that
-- answered, or nil when no source knows the item.
function I.itemLevel(first, link)
  local location
  if type(first) == "table" then
    location = first
  elseif link == nil then
    link = first
  end
  for _, source in ipairs(I.SOURCES) do
    local ok, value = pcall(source.fn, location, link)
    if ok and readable(value) and value > 0 then
      return value, source.label
    end
  end
end

-- Weapons (2) and armor (4) carry the item level; armor includes rings, necks, trinkets and cloaks.
local GEAR_CLASSES = { [2] = true, [4] = true }
local NOT_GEAR_SLOT = { INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true }

function I.isGear(link)
  local f = method("C_Item", "GetItemInfoInstant") or global("GetItemInfoInstant")
  if not f or link == nil then
    return false
  end
  -- itemID, type, subType, equipLoc, icon, classID, subClassID
  local ok, _, _, _, equipLoc, _, classID = pcall(f, link)
  if not ok then
    return false
  end
  if readable(classID) then
    return GEAR_CLASSES[classID] == true
  end
  return type(equipLoc) == "string" and equipLoc ~= "" and not NOT_GEAR_SLOT[equipLoc]
end

-- Quality 0..7 from the item cache, nil while the item is not cached.
function I.quality(link)
  local f = method("C_Item", "GetItemInfo") or global("GetItemInfo")
  if not f or link == nil then
    return nil
  end
  local ok, _, _, quality = pcall(f, link)
  if ok and readable(quality) then
    return quality
  end
end

-- The client's color of a quality, nil when neither the item API nor ITEM_QUALITY_COLORS has one.
local function clientColor(quality)
  if not readable(quality) then
    return nil
  end
  local f = method("C_Item", "GetItemQualityColor")
  if f then
    local ok, r, g, b = pcall(f, quality)
    if ok and readable(r) and readable(g) and readable(b) then
      return r, g, b
    end
  end
  local colors = rawget(_G, "ITEM_QUALITY_COLORS")
  local c = type(colors) == "table" and colors[quality] or nil
  if type(c) == "table" and readable(c.r) and readable(c.g) and readable(c.b) then
    return c.r, c.g, c.b
  end
end

-- Raw client color (item level numbers on icons), the theme text color without data.
function I.qualityColor(quality)
  local r, g, b = clientColor(quality)
  if r then
    return r, g, b
  end
  return ns.Theme.rgb("text")
end

-- The client's default colors, poor to heirloom: the fixed fallback when the client gives none.
I.QUALITY_FALLBACK = {
  [0] = "#9d9d9d",
  "#ffffff",
  "#1eff00",
  "#0070dd",
  "#a335ee",
  "#ff8000",
  "#e6cc80",
  "#00ccff",
}

local function hexOf(r, g, b)
  local function byte(v)
    return math.floor(math.min(1, math.max(0, v)) * 255 + 0.5)
  end
  return string.format("#%02x%02x%02x", byte(r), byte(g), byte(b))
end

local SURFACES = { "bg", "surface", "surface2", "surface3" }
local lifted, liftedFor = {}, nil

-- Lightened results are cached per palette of the active skin, theme and contrast mode.
local function palette()
  local out = {}
  for i, name in ipairs(SURFACES) do
    out[i] = hexOf(ns.Theme.rgb(name))
  end
  return out
end

-- "rrggbb" of a quality for text: the client color (else the fixed fallback), lightened only as far
-- as needed to reach 4.5:1 on every surface of the active palette. nil for an unknown quality.
function I.qualityHex(quality)
  if not (readable(quality) and quality >= 0) then
    return nil
  end
  quality = math.floor(quality)
  local r, g, b = clientColor(quality)
  local base = r and hexOf(r, g, b) or I.QUALITY_FALLBACK[quality]
  if not base then
    return nil
  end
  local surfaces = palette()
  local key = table.concat(surfaces, ",")
  if key ~= liftedFor then
    lifted, liftedFor = {}, key
  end
  if not lifted[base] then
    local out = base
    for _, surface in ipairs(surfaces) do
      out = (ns.Theme.readable(out, surface))
    end
    lifted[base] = out:gsub("#", "")
  end
  return lifted[base]
end

-- r, g, b (0..1) for SetTextColor, nil for an unknown quality.
function I.qualityTextColor(quality)
  local hex = I.qualityHex(quality)
  if hex then
    return ns.U.hex(hex)
  end
end

-- The name in the color of its quality. An unknown quality or name stays as it is. The quality
-- name itself is never replaced by the color: callers keep a text for it (WCAG 1.4.1).
function I.ColorName(name, quality)
  local hex = type(name) == "string" and name ~= "" and I.qualityHex(quality) or nil
  return hex and ("|cff" .. hex .. name .. "|r") or name
end

-- An item link without its own color code gets the color of the item's quality, a colored link
-- or one of an unknown quality stays as it is.
function I.ColorLink(link)
  if type(link) ~= "string" or link:find("|c", 1, true) then
    return link
  end
  local id = link:match("^|Hitem:(%d+)")
  local hex = id and I.qualityHex(I.quality(tonumber(id)))
  return hex and ("|cff" .. hex .. link .. "|r") or link
end

-- The colon separated fields behind "item:" in a link, empty fields kept: itemID, enchantID,
-- gem1..gem4, ...
local function fields(link)
  if type(link) ~= "string" then
    return nil
  end
  local payload = link:match("item:([^|]*)")
  if not payload then
    return nil
  end
  local out = {}
  for field in (payload .. ":"):gmatch("([^:]*):") do
    out[#out + 1] = field
  end
  return out
end

local function idAt(list, index)
  local n = list and tonumber(list[index])
  return n and n > 0 and n or nil
end

function I.enchantId(link)
  return idAt(fields(link), 2)
end

-- Gem item ids in socket order, without the empty sockets.
function I.gemIds(link)
  local list, out = fields(link), {}
  for index = 3, 6 do
    out[#out + 1] = idAt(list, index)
  end
  return out
end

-- Which slots can carry an enchant (assumed, not verified for every item type).
--   sure  = a missing enchant is flagged ("not enchanted"); slots 17 and 18 only for the item
--           types of ENCHANTABLE_OFFHAND and ENCHANTABLE_RANGED
--   show  = an existing enchant is shown, a missing one is never flagged
--   never = no enchant exists (neck, shirt, belt, trinkets, tabard)
I.ENCHANT_SLOTS = {
  [1] = "show",
  [2] = "never",
  [3] = "show",
  [4] = "never",
  [5] = "sure",
  [6] = "never",
  [7] = "show",
  [8] = "sure",
  [9] = "sure",
  [10] = "sure",
  [11] = "show",
  [12] = "show",
  [13] = "never",
  [14] = "never",
  [15] = "sure",
  [16] = "sure",
  [17] = "sure",
  [18] = "sure",
  [19] = "never",
}
-- Setting "enchantSlots" (comma separated slot ids) replaces the "sure" set when it is a string.
I.DEFAULT_FLAGGED = "5,8,9,10,15,16,17,18"

local OFFHAND_EQUIP = { INVTYPE_SHIELD = true, INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }
local RANGED_SUBCLASS = { [2] = true, [3] = true, [18] = true } -- bow, gun, crossbow

-- The set of flagged slot ids from the setting text, the table default for anything else.
function I.flaggedSlots(spec)
  local set = {}
  if type(spec) ~= "string" then
    spec = I.DEFAULT_FLAGGED
  end
  for token in spec:gmatch("%d+") do
    local id = tonumber(token)
    if id >= 1 and id <= 19 then
      set[id] = true
    end
  end
  return set
end

-- Link of the item a unit wears in a slot ("player" or an inspected unit), nil when none is known.
local function inventoryLink(slotId, unit)
  local f = global("GetInventoryItemLink")
  if not f then
    return nil
  end
  local ok, link = pcall(f, unit or "player", slotId)
  return ok and link or nil
end
I.inventoryLink = inventoryLink

-- Two-handed weapons and bows count twice in the average item level.
local TWO_HAND = { INVTYPE_2HWEAPON = true, INVTYPE_RANGED = true }

function I.isTwoHand(link)
  local f = method("C_Item", "GetItemInfoInstant") or global("GetItemInfoInstant")
  if not f or link == nil then
    return false
  end
  local ok, _, _, _, equipLoc = pcall(f, link)
  return ok and type(equipLoc) == "string" and TWO_HAND[equipLoc] == true
end

-- true: a missing enchant is worth flagging, false: it is not, nil: not decidable (no item, or
-- the item type is not known yet). slots: optional set from I.flaggedSlots.
function I.enchantable(slotId, link, slots)
  if link == nil then
    return nil
  end
  if not (slots or I.flaggedSlots())[slotId] then
    return false
  end
  if slotId ~= 17 and slotId ~= 18 then
    return true
  end
  local f = method("C_Item", "GetItemInfoInstant") or global("GetItemInfoInstant")
  if not f then
    return nil
  end
  local ok, _, _, _, equipLoc, _, classID, subClassID = pcall(f, link)
  if not ok then
    return nil
  end
  if slotId == 18 then
    if readable(classID) then
      return classID == 2 and RANGED_SUBCLASS[subClassID] == true
    end
    return nil
  end
  if readable(classID) then
    return classID == 2 or (classID == 4 and equipLoc == "INVTYPE_SHIELD")
  end
  if type(equipLoc) == "string" and equipLoc ~= "" then
    return OFFHAND_EQUIP[equipLoc] == true
  end
  return nil
end

-- Not a secret value: restricted clients hand those out and comparing them raises.
local function accessible(v)
  local guard = rawget(_G, "canaccessvalue")
  if type(guard) == "function" then
    local ok, can = pcall(guard, v)
    if not (ok and can ~= false) then
      return false
    end
  end
  local secret = rawget(_G, "issecretvalue")
  if type(secret) == "function" then
    local ok, is = pcall(secret, v)
    if ok and is then
      return false
    end
  end
  return true
end

I.accessible = accessible

-- Text of the "permanent enchantment" line in the tooltip of an equipped item, nil when absent.
local function tooltipEnchantText(slotId, unit)
  local api = method("C_TooltipInfo", "GetInventoryItem")
  local enum = rawget(_G, "Enum")
  local types = type(enum) == "table" and enum.TooltipDataLineType or nil
  local lineType = type(types) == "table" and types.ItemEnchantmentPermanent or nil
  if not api or lineType == nil then
    return nil
  end
  local ok, text = pcall(function()
    local data = api(unit or "player", slotId)
    for _, entry in ipairs(type(data) == "table" and data.lines or {}) do
      if type(entry) == "table" and accessible(entry.type) and entry.type == lineType then
        local left = entry.leftText
        if accessible(left) and type(left) == "string" and left ~= "" then
          return left
        end
      end
    end
  end)
  return ok and text or nil
end

-- { id = enchant id from the link, text = tooltip line } of the item in a worn slot; nil when the
-- slot is empty. Either field is nil when unknown. unit: "player" unless another unit is inspected.
function I.enchantInfo(slotId, link, unit)
  link = link or inventoryLink(slotId, unit)
  if link == nil then
    return nil
  end
  return { id = I.enchantId(link), text = tooltipEnchantText(slotId, unit) }
end

-- "Enchanted: Crusader" -> "Crusader" with the client's own format string.
function I.enchantName(text)
  local format = rawget(_G, "ENCHANTED_TOOLTIP_LINE")
  if type(text) ~= "string" or type(format) ~= "string" or not format:find("%s", 1, true) then
    return text
  end
  local pattern = "^" .. (format:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")):gsub("%%%%s", "(.+)") .. "$"
  return text:match(pattern) or text
end

local function gemFromApi(link, index)
  local f = method("C_Item", "GetItemGem")
  if not f then
    return nil
  end
  local ok, _, gemLink = pcall(f, link, index)
  if ok and type(gemLink) == "string" then
    return tonumber(gemLink:match("item:(%d+)"))
  end
end

local function iconOf(itemId)
  local byId = method("C_Item", "GetItemIconByID")
  if byId then
    local ok, icon = pcall(byId, itemId)
    if ok and icon ~= nil then
      return icon
    end
  end
  local instant = method("C_Item", "GetItemInfoInstant") or global("GetItemInfoInstant")
  if instant then
    local ok, _, _, _, _, icon = pcall(instant, itemId)
    if ok then
      return icon
    end
  end
end

-- Gems in socket order as { itemId, icon }. The link names them; C_Item.GetItemGem fills the
-- sockets the link leaves empty.
function I.gems(slotId, link, unit)
  link = link or inventoryLink(slotId, unit)
  local list, out = fields(link), {}
  if link == nil then
    return out
  end
  for index = 1, 4 do
    local id = idAt(list, index + 2) or gemFromApi(link, index)
    if id then
      out[#out + 1] = { itemId = id, icon = iconOf(id) }
    end
  end
  return out
end

-- Number of sockets of an item, nil when this client has no function for it.
function I.numSockets(link)
  local f = method("C_Item", "GetItemNumSockets")
  if not f or link == nil then
    return nil
  end
  local ok, n = pcall(f, link)
  if ok and readable(n) then
    return n
  end
end

-- Whole number without a thousands separator.
function I.format(level)
  if not readable(level) then
    return ""
  end
  return string.format("%d", math.floor(level + 0.5))
end
