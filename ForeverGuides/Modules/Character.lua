-- Character page: export strings for forever-guides.com (character, items
-- seen, transmog) plus the background capture of looted item ids.
local _, ns = ...
local W, L = ns.W, ns.L

ns.AddLocale("enUS", {
  ["character.intro"] = "Export strings for forever-guides.com.\nThe addon sends nothing. Copy the string, then paste it under account > import.",
  ["character.hint"] = "The addon sends nothing. Paste on forever-guides.com > account > import.",
  ["character.char.title"] = "Character",
  ["character.char.desc"] = "Character info, equipment, bags and secondary stats.",
  ["character.char.info"] = "The website shows your name, class and level in your account and uses your item level for event signups.",
  ["character.char.button"] = "Export character",
  ["character.char.dialog"] = "Character export",
  ["character.seen.title"] = "Items seen",
  ["character.seen.desc"] = "Items looted or received since the addon was installed.",
  ["character.seen.info"] = "The collection page on the website marks every item you have already seen.",
  ["character.seen.button"] = "Export items seen",
  ["character.seen.dialog"] = "Items seen export",
  ["character.transmog.title"] = "Transmog",
  ["character.transmog.desc"] = "All unlocked transmog appearances.",
  ["character.transmog.info"] = "The website takes over your unlocked transmog appearances.",
  ["character.transmog.note"] = "The website cannot read this type yet. The string can already be created.",
  ["character.transmog.button"] = "Export transmog",
  ["character.transmog.dialog"] = "Transmog export",
  ["character.link.button"] = "More on the website",
  ["character.link.dialog"] = "Website link",
  ["character.link.hint"] = "Copy the link with Ctrl+C, then paste it in your browser.",
  ["character.err.nodata"] = "Character data is not available yet.",
  ["character.err.encode"] = "Export failed.",
})

ns.AddLocale("deDE", {
  ["character.intro"] = "Export-Strings für forever-guides.com.\nDas Addon sendet nichts. Kopiere den String und füge ihn unter Account > Import ein.",
  ["character.hint"] = "Das Addon sendet nichts. Einfügen auf forever-guides.com > Account > Import.",
  ["character.char.title"] = "Charakter",
  ["character.char.desc"] = "Charakterinfo, Ausrüstung, Taschen und Sekundärwerte.",
  ["character.char.info"] = "Die Webseite zeigt Name, Klasse und Level in deinem Konto und nutzt dein Item-Level bei Event-Anmeldungen.",
  ["character.char.button"] = "Charakter exportieren",
  ["character.char.dialog"] = "Charakter-Export",
  ["character.seen.title"] = "Gesehene Items",
  ["character.seen.desc"] = "Erbeutete oder erhaltene Items seit der Addon-Installation.",
  ["character.seen.info"] = "Das Sammelalbum auf der Webseite markiert jedes Item, das du schon gesehen hast.",
  ["character.seen.button"] = "Gesehene Items exportieren",
  ["character.seen.dialog"] = "Export gesehener Items",
  ["character.transmog.title"] = "Transmog",
  ["character.transmog.desc"] = "Alle freigeschalteten Transmog-Erscheinungen.",
  ["character.transmog.info"] = "Die Webseite übernimmt deine freigeschalteten Transmog-Erscheinungen.",
  ["character.transmog.note"] = "Die Webseite kann diesen Typ noch nicht lesen. Der String ist schon erzeugbar.",
  ["character.transmog.button"] = "Transmog exportieren",
  ["character.transmog.dialog"] = "Transmog-Export",
  ["character.link.button"] = "Mehr auf der Webseite",
  ["character.link.dialog"] = "Link zur Webseite",
  ["character.link.hint"] = "Mit Strg+C kopieren, dann im Browser einfügen.",
  ["character.err.nodata"] = "Charakterdaten sind noch nicht verfügbar.",
  ["character.err.encode"] = "Export fehlgeschlagen.",
})

local EQUIPMENT_SLOTS = {
  "HeadSlot",
  "NeckSlot",
  "ShoulderSlot",
  "BackSlot",
  "ChestSlot",
  "WaistSlot",
  "LegsSlot",
  "FeetSlot",
  "WristSlot",
  "HandsSlot",
  "Finger0Slot",
  "Finger1Slot",
  "Trinket0Slot",
  "Trinket1Slot",
  "MainHandSlot",
  "SecondaryHandSlot",
  "RangedSlot",
  "TabardSlot",
}

local MAX_SEEN = 5000

-- Single switch for the transmog hint: set true once the website accepts the type "transmog".
local Page = { TRANSMOG_IMPORT_READY = false }
ns.CharacterPage = Page

-- Website targets per section, same pattern as ns.FeedbackUrl (/de/... or /en/...).
local SITE_PATHS = {
  char = { de = "/de/konto/import", en = "/en/account/import" },
  seen = { de = "/de/sammelalbum", en = "/en/collection" },
  transmog = { de = "/de/konto/import", en = "/en/account/import" },
}

function Page.Url(name)
  return ns.Website .. SITE_PATHS[name][ns.GetActiveLocale() == "deDE" and "de" or "en"]
end

local function try(fn, ...)
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
end

local function realmName()
  return try(GetNormalizedRealmName) or try(GetRealmName)
end

-- Fields every envelope needs for the website: name, class token, level, realm.
local function identity()
  local ok, _, token = pcall(UnitClass, "player")
  return {
    name = try(UnitName, "player"),
    class = ok and token or nil,
    level = try(UnitLevel, "player"),
    realm = realmName(),
  }
end

local function charKey(id)
  if id.name and id.realm then
    return id.name .. "-" .. id.realm
  end
end

local function gatherEquipment()
  local items = {}
  for _, slotName in ipairs(EQUIPMENT_SLOTS) do
    local slotId = try(GetInventorySlotInfo, slotName)
    local link = slotId and try(GetInventoryItemLink, "player", slotId)
    if link then
      local ok, name, _, level = pcall(function()
        return C_Item.GetItemInfo(link)
      end)
      items[#items + 1] = { slot = slotName, link = link, name = ok and name or nil, itemLevel = ok and level or nil }
    end
  end
  return items
end

local function gatherBags()
  local out = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local slots = try(function()
      return C_Container.GetContainerNumSlots(bag)
    end)
    for slot = 1, slots or 0 do
      local info = try(function()
        return C_Container.GetContainerItemInfo(bag, slot)
      end)
      if info and info.itemID then
        out[#out + 1] = { bag = bag, slot = slot, itemId = info.itemID, count = info.stackCount }
      end
    end
  end
  return out
end

local function gatherStats()
  return {
    critChance = try(GetCritChance),
    hasteChance = try(GetMeleeHaste),
    mastery = try(GetMastery),
    versatility = try(function()
      return GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
    end),
  }
end

local function resolveItemId(visualID, categoryID, location)
  local sources = try(function()
    return C_TransmogCollection.GetAppearanceSources(visualID, categoryID, location)
  end)
  if type(sources) ~= "table" then
    return nil
  end
  local fallback
  for _, source in ipairs(sources) do
    if source.isCollected then
      return source.itemID
    end
    fallback = fallback or source.itemID
  end
  return fallback
end

local function gatherTransmog()
  try(function()
    C_AddOns.LoadAddOn("Blizzard_TransmogShared")
  end)
  try(function()
    C_AddOns.LoadAddOn("Blizzard_Collections")
  end)
  local appearances, seen = {}, {}
  local slots = try(function()
    return C_TransmogOutfitInfo.GetAllSlotLocationInfo()
  end)
  if type(slots) ~= "table" then
    return appearances
  end
  for _, slot in ipairs(slots) do
    local category = slot.collectionType
    if category and category ~= Enum.TransmogCollectionType.None then
      local location = try(function()
        return TransmogUtil.CreateTransmogLocation(slot.slotName, slot.type, slot.isSecondary)
      end)
      local list = location
        and try(function()
          return C_TransmogCollection.GetCategoryAppearances(category, location)
        end)
      if type(list) == "table" then
        for _, a in ipairs(list) do
          if a.isCollected and not seen[a.visualID] then
            seen[a.visualID] = true
            appearances[#appearances + 1] = {
              categoryID = category,
              visualID = a.visualID,
              itemID = resolveItemId(a.visualID, category, location),
            }
          end
        end
      end
    end
  end
  return appearances
end

-- Exports --------------------------------------------------------------------

local function merge(base, extra)
  for k, v in pairs(extra) do
    base[k] = v
  end
  return base
end

local function characterData()
  local id = identity()
  id.info = { name = id.name, class = id.class, level = id.level, realm = id.realm }
  id.equipment = gatherEquipment()
  id.bags = gatherBags()
  id.stats = gatherStats()
  return id
end

local function itemsSeenData()
  local id = identity()
  local key = charKey(id)
  local chars = ns.db and ns.db.chars
  local entry = key and chars and chars[key]
  id.characterKey = key
  id.itemsSeen = entry and entry.itemsSeen or {}
  return id
end

local function transmogData()
  return merge(identity(), { appearances = gatherTransmog() })
end

local function export(kind, dataFn, dialogKey)
  local data = dataFn()
  if not data.name then
    ns.Notify(L["character.err.nodata"], "warning")
    return
  end
  local s = ns.Strings.encode(kind, data)
  if not s then
    ns.Notify(L["character.err.encode"], "error")
    return
  end
  ns.Dialogs.Copy(dialogKey, s, "character.hint")
end

-- Loot capture --------------------------------------------------------------

local seenCount = {}

ns.On("CHAT_MSG_LOOT", function(_, message, ...)
  -- Group members' loot fires this too; only count our own (arg12 = GUID).
  local guid = select(11, ...)
  if guid and UnitGUID and guid ~= UnitGUID("player") then
    return
  end
  local chars = ns.db and ns.db.chars
  local itemId = type(message) == "string" and tonumber(message:match("item:(%d+)"))
  if not chars or not itemId then
    return
  end
  local key = charKey({ name = try(UnitName, "player"), realm = realmName() })
  if not key then
    return
  end
  local entry = chars[key]
  if not entry then
    entry = {}
    chars[key] = entry
  end
  local seen = entry.itemsSeen
  if not seen then
    seen = {}
    entry.itemsSeen = seen
  end
  if seen[itemId] then
    return
  end
  local n = seenCount[key]
  if not n then
    n = 0
    for _ in pairs(seen) do
      n = n + 1
    end
  end
  if n >= MAX_SEEN then
    seenCount[key] = n
    return
  end
  seen[itemId] = ns.U.now()
  seenCount[key] = n + 1
end)

-- Page -----------------------------------------------------------------------

local function section(view, name, dataFn, infoKey, infoColor)
  ns.AddHeading(view, "character." .. name .. ".title", { gap = 4 })
  ns.AddParagraph(view, "character." .. name .. ".desc", { color = "textSecondary", gap = 6 })
  ns.AddParagraph(view, infoKey, { color = infoColor or "textSecondary", role = "ui", gap = 6 })
  local btn = W.Action(view.content, {
    label = "act.export",
    icon = "export",
    variant = "primary",
    width = 220,
    height = 28,
    tooltip = "character." .. name .. ".title",
    tooltipText = infoKey,
    onClick = function()
      export(
        name == "char" and "character" or name == "seen" and "itemsSeen" or "transmog",
        dataFn,
        "character." .. name .. ".dialog"
      )
    end,
  })
  view.stack:Add(btn, { height = 28, width = 220, gap = 6 })
  local link = W.Action(view.content, {
    label = "act.open",
    icon = "open",
    variant = "ghost",
    width = 220,
    height = 28,
    tooltip = "character.link.button",
    tooltipText = "character.link.hint",
    onClick = function()
      ns.Dialogs.Copy("character.link.dialog", Page.Url(name), "character.link.hint")
    end,
  })
  view.stack:Add(link, { height = 28, width = 220, gap = 20 })
end

local function build(container)
  local view = ns.NewPageView(container)
  ns.AddParagraph(view, "character.intro", { color = "text" })
  section(view, "char", characterData, "character.char.info")
  section(view, "seen", itemsSeenData, "character.seen.info")
  if Page.TRANSMOG_IMPORT_READY then
    section(view, "transmog", transmogData, "character.transmog.info")
  else
    section(view, "transmog", transmogData, "character.transmog.note", "warning")
  end
  return view
end

ns.RegisterPage({
  id = "character",
  order = 705,
  group = "system",
  title = "page.character",
  icon = ns.ICONS.character,
  aliases = { "charakter", "character", "export" },
  build = build,
})
