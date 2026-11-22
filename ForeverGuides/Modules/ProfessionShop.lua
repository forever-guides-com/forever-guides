-- Game side of the profession route and its shopping list: which professions the character has,
-- the saved choices (profession, target, surcharge, stock) and ticks per character and profession,
-- the stock from the inventory snapshots, the price resolution (own price data first, then the price
-- add-on, see PriceSourceAddon.lua), the shopping list connection and the two copy texts. The pure side is Modules/ProfessionRouteLogic.lua, the windows
-- are ProfessionShopWindow.lua and ProfessionRoutePage.lua.
--
-- ns.db.profRoute = {
--   v = 2,
--   opts = { surcharge, view, autoOpen },        -- the account-wide preferences
--   opts.slug/target/from/stock/all, craft, recipes -- legacy account-wide choices, taken over once (S.MigrateChar)
--   checked / list = { [characterKey] = ... },   -- legacy account-wide storage, read only once by the migration
--   optsTaken = true,                            -- the first character took the legacy choices
-- }
-- ns.charDB.profList = {                         -- the shopping list of this character
--   chr = { ... },                               -- own positions and edits, see ProfessionListLogic.lua
--   checked = { [slug] = { [itemId] = true } },
--   opts = { slug, target, from, stock, all },   -- the route choices of this character
--   craft = { [itemId] = "craft" | "auction" },  -- how a craftable item is got, shared by the lists of this character
--   recipes = { slug, skill, sel },              -- what the professions page showed last
--   optsDone = true,                             -- the legacy choices were handled for this character
--   migrated = true,                             -- the legacy entries were taken over (see S.MigrateChar)
--   notice = true,                               -- the one-time notice is still to be shown
-- }
local _, ns = ...
local R = ns.ProfessionRouteLogic
local PL = ns.ProfessionListLogic
local Data = ns.ProfessionRouteData

local S = {}
ns.ProfessionShop = S

ns.AddLocale("enUS", {
  ["profshop.perChar"] = "Each character now has its own shopping list",
  ["profshop.sent"] = "Shopping list created: %d items",
  ["profshop.noApi"] = "No shopping list connection. The text opens.",
  ["profshop.failed"] = "Shopping list failed. The text opens instead.",
  ["profshop.nothing"] = "Nothing to send.",
  ["profshop.group.vendor"] = "Vendor",
  ["profshop.group.auction"] = "Auction house",
  ["profshop.group.gather"] = "Gather yourself",
  ["profshop.group.craft"] = "Craft yourself",
  ["profshop.openAuction"] = "Open the auction house: %s",
  ["profshop.searchFailed"] = "Search not possible: %s",
  ["profshop.offerShort"] = "Only %d of %d on offer",
  ["profshop.rowSearch"] = "Click: search in auction house",
  ["profshop.rowMore"] = "Right click: copy name, Shift click: link",
  ["profshop.nameTitle"] = "Item name",
  ["profshop.hint"] = "Click an item to search for it in the auction house.",
  ["profshop.rowHave"] = "Have %d of %d, still to buy: %d",
  ["profshop.rowBuy"] = "Still to buy: %d",
  ["profshop.rowHaveOf"] = "Have %d of %d",
  ["profshop.rowHaveInfo"] = "Have %d of %d (stock is not subtracted)",
  ["profshop.rowVendor"] = "Vendor item: buy it at a vendor.",
  ["price.header"] = "Price:",
  ["item.craftCost"] = "Crafting cost",
  ["item.craftCostPart"] = "%s (%d without price)",
  ["item.vendorSell"] = "Vendor",
  ["price.min"] = "Lowest",
  ["price.median"] = "Median",
  ["price.max"] = "Highest",
  ["price.line"] = "%s: %s",
  ["price.asOf"] = "(as of %s)",
  ["price.dateFormat"] = "%Y-%m-%d",
  ["price.hint"] = "Median and highest come from a full scan.",
  ["price.addon"] = "Price addon: %s",
  ["price.old"] = "Old data: %d days",
  ["price.stack"] = "AH stack value (%d items): %s",
  ["price.one"] = "AH: %s",
  ["price.other"] = "Other auction houses",
  ["price.otherLine"] = "%s %s",
  ["price.ageToday"] = "today",
  ["price.ageDays"] = "%dd",
  ["price.neutralOnly"] = "Only neutral auction house data",
  ["price.legacyOnly"] = "Older scan",
})
ns.AddLocale("deDE", {
  ["profshop.perChar"] = "Jeder Charakter hat jetzt eine eigene Einkaufsliste",
  ["profshop.sent"] = "Einkaufsliste erstellt: %d Items",
  ["profshop.noApi"] = "Keine Einkaufslisten-Anbindung. Der Text öffnet sich.",
  ["profshop.failed"] = "Einkaufsliste fehlgeschlagen. Der Text öffnet sich.",
  ["profshop.nothing"] = "Nichts zu senden.",
  ["profshop.group.vendor"] = "Händler",
  ["profshop.group.auction"] = "Auktionshaus",
  ["profshop.group.gather"] = "Selbst sammeln",
  ["profshop.group.craft"] = "Selbst herstellen",
  ["profshop.openAuction"] = "Öffne das Auktionshaus: %s",
  ["profshop.searchFailed"] = "Suche nicht möglich: %s",
  ["profshop.offerShort"] = "Nur %d von %d im Angebot",
  ["profshop.rowSearch"] = "Klick: im Auktionshaus suchen",
  ["profshop.rowMore"] = "Rechtsklick: Name kopieren, Umschalt-Klick: Link",
  ["profshop.nameTitle"] = "Itemname",
  ["profshop.hint"] = "Klicke ein Item an, um es im Auktionshaus zu suchen.",
  ["profshop.rowHave"] = "Vorhanden %d von %d, noch zu kaufen: %d",
  ["profshop.rowBuy"] = "Noch zu kaufen: %d",
  ["profshop.rowHaveOf"] = "Vorhanden %d von %d",
  ["profshop.rowHaveInfo"] = "Vorhanden %d von %d (Bestand nicht abgezogen)",
  ["profshop.rowVendor"] = "Händlerware: beim Händler kaufen.",
  ["price.header"] = "Preis:",
  ["item.craftCost"] = "Herstellungskosten",
  ["item.craftCostPart"] = "%s (%d ohne Preis)",
  ["item.vendorSell"] = "Händler",
  ["price.min"] = "Niedrigster",
  ["price.median"] = "Median",
  ["price.max"] = "Höchster",
  ["price.line"] = "%s: %s",
  ["price.asOf"] = "(Stand: %s)",
  ["price.dateFormat"] = "%d.%m.%Y",
  ["price.hint"] = "Median und Höchster kommen aus einem vollständigen Scan.",
  ["price.addon"] = "Preisaddon: %s",
  ["price.old"] = "Alte Daten: %d Tage",
  ["price.stack"] = "Stapelwert im AH (%d Stück): %s",
  ["price.one"] = "AH: %s",
  ["price.other"] = "Andere Auktionshäuser",
  ["price.otherLine"] = "%s %s",
  ["price.ageToday"] = "heute",
  ["price.ageDays"] = "%d T.",
  ["price.neutralOnly"] = "Nur Daten des neutralen Auktionshauses",
  ["price.legacyOnly"] = "Älterer Scan",
})

local DEFAULTS = { stock = true, all = false, autoOpen = true }
local VIEWS = { combined = true, reason = true }

-- Saved state ---------------------------------------------------------------------------------

local scratch = { opts = {}, checked = {} }
local charScratch = { checked = {}, opts = {}, craft = {} }

-- A skill value above 0, nil for empty or invalid input (= automatic).
local function skillValue(v)
  local n = R.Whole(v)
  return n and n > 0 and n or nil
end

local charStore

local function store()
  local t = scratch
  if type(ns.db) == "table" then
    if type(ns.db.profRoute) ~= "table" then
      ns.db.profRoute = {}
    end
    t = ns.db.profRoute
  end
  if type(t.opts) ~= "table" then
    t.opts = {}
  end
  if type(t.checked) ~= "table" then
    t.checked = {}
  end
  if type(t.craft) ~= "table" then
    t.craft = {}
  end
  if (tonumber(t.v) or 1) < PL.SCHEMA or type(t.list) ~= "table" then
    PL.Migrate(t)
  end
  return t
end
-- The saved table (the scratch one without a database), migrated to the current schema.
S.Root = store

-- Upper bound for a stored spell id (signed 32 bit).
local SPELL_MAX = 2147483647

-- The profession, skill and selected recipe (spell id) the professions page showed last, so it opens
-- there again: { slug, skill, selected }, each nil when unknown or not set.
function S.RecipeView()
  local v = charStore().recipes
  if type(v) ~= "table" then
    return {}
  end
  return { slug = R.PROFESSIONS[v.slug] and v.slug or nil, skill = R.Whole(v.skill), selected = R.Whole(v.sel, SPELL_MAX) }
end

function S.SetRecipeView(slug, skill, selected)
  charStore().recipes = { slug = R.PROFESSIONS[slug] and slug or nil, skill = R.Whole(skill), sel = R.Whole(selected, SPELL_MAX) }
end

-- Per character: slug (a known slug), target and from (whole skill, nil = automatic), stock (take the
-- stock off), all (stock of all characters). Account-wide preferences: surcharge (percent), view ("combined" | "reason", one choice
-- for every list window), autoOpen (the list opens by itself at the auction house).
local CHAR_OPTS = { slug = true, target = true, from = true, stock = true, all = true }

local function optsOf(key)
  return CHAR_OPTS[key] and charStore().opts or store().opts
end

function S.Option(key)
  local v = optsOf(key)[key]
  if key == "slug" then
    return R.PROFESSIONS[v] and v or nil
  elseif key == "target" or key == "from" then
    return skillValue(v)
  elseif key == "surcharge" then
    return R.Surcharge(v)
  elseif key == "view" then
    return VIEWS[v] and v or "combined"
  end
  if type(v) == "boolean" then
    return v
  end
  return DEFAULTS[key] == true
end

-- Validates and stores; nil (or "") clears target and from. Returns the stored value.
function S.SetOption(key, value)
  local opts = optsOf(key)
  if key == "slug" then
    opts.slug = R.PROFESSIONS[value] and value or nil
  elseif key == "target" or key == "from" then
    opts[key] = skillValue(value)
  elseif key == "surcharge" then
    opts.surcharge = R.Surcharge(value)
  elseif key == "view" then
    opts.view = VIEWS[value] and value or nil
  elseif key == "stock" or key == "all" or key == "autoOpen" then
    opts[key] = value == true
  else
    return nil
  end
  ns.Emit("FG_PROFROUTE_CHANGED", key)
  return S.Option(key)
end

local function characterKey()
  local roster = ns.CharRoster
  return roster and roster.CurrentKey() or "?"
end

-- The shopping list store of the current character (ns.charDB.profList), scratch without a database. The
-- legacy account-wide entries are taken over first.
function charStore()
  local cdb = ns.charDB
  if type(cdb) ~= "table" then
    return charScratch
  end
  if type(cdb.profList) ~= "table" then
    cdb.profList = {}
  end
  local t = cdb.profList
  if type(t.checked) ~= "table" then
    t.checked = {}
  end
  if type(t.opts) ~= "table" then
    t.opts = {}
  end
  if type(t.craft) ~= "table" then
    t.craft = {}
  end
  if not t.migrated or not t.optsDone then
    S.MigrateChar()
  end
  return t
end
S.CharRoot = charStore

-- One-time takeover of the account-wide lists (before: ns.db.profRoute.list and .checked per character
-- key). The current character takes the entries under its own key; the "?" entry, written while the key was
-- unknown, goes to the first character that logs in. Taken entries are removed from the account store;
-- the entries of other characters stay there until they log in themselves.
function S.MigrateChar()
  local cdb = ns.charDB
  local key = characterKey()
  if type(cdb) ~= "table" or key == "?" then
    return
  end
  if type(cdb.profList) ~= "table" then
    cdb.profList = {}
  end
  local t = cdb.profList
  if type(t.checked) ~= "table" then
    t.checked = {}
  end
  if type(t.opts) ~= "table" then
    t.opts = {}
  end
  if type(t.craft) ~= "table" then
    t.craft = {}
  end
  local root = store()
  local moved = false
  if not t.migrated then
    t.migrated = true
    for _, from in ipairs({ key, "?" }) do
      local entry = root.list[from]
      if entry ~= nil and type(t.chr) ~= "table" then
        t.chr = entry
        root.list[from] = nil
        moved = true
      end
      local ticks = root.checked[from]
      if type(ticks) == "table" and next(t.checked) == nil then
        t.checked = ticks
        root.checked[from] = nil
        moved = moved or next(ticks) ~= nil
      end
    end
  end
  -- The route choices and craft choices: the first character to log in takes the account-wide ones,
  -- every other character starts empty (profession = its first own one, skill = its current one).
  if not t.optsDone then
    t.optsDone = true
    if not root.optsTaken then
      root.optsTaken = true
      for k in pairs(CHAR_OPTS) do
        if root.opts[k] ~= nil then
          t.opts[k] = root.opts[k]
          root.opts[k] = nil
          moved = true
        end
      end
      if next(root.craft) ~= nil then
        t.craft = root.craft
        root.craft = {}
        moved = true
      end
      if type(root.recipes) == "table" then
        t.recipes = root.recipes
        root.recipes = nil
      end
    end
  end
  if moved then
    t.notice = true
  end
end

-- Shows the one-time notice after the migration took lists over.
function S.ShowMigrationNotice()
  local t = type(ns.charDB) == "table" and ns.charDB.profList
  if type(t) == "table" and t.notice then
    t.notice = nil
    ns.Notify(ns.L["profshop.perChar"], "info")
  end
end
ns.On("PLAYER_LOGIN", function()
  charStore()
  S.ShowMigrationNotice()
end)

-- The ticks of the current character for one profession, { [itemId] = true }; changes to the table
-- are saved.
function S.Checked(slug)
  local byslug = charStore().checked
  if type(byslug[slug]) ~= "table" then
    byslug[slug] = {}
  end
  return byslug[slug]
end

function S.SetChecked(slug, itemId, on)
  S.Checked(slug)[itemId] = on and true or nil
  ns.Emit("FG_PROFROUTE_CHANGED", "checked")
end

function S.ClearChecked(slug)
  charStore().checked[slug] = nil
  ns.Emit("FG_PROFROUTE_CHANGED", "checked")
end

-- Craft or buy -------------------------------------------------------------------------------------

local MAX_CHOICES = 500

-- How a craftable item is got: "craft" (its materials are on the list instead of the item, the
-- default) or "auction" (the item itself is bought). One choice per item for every list window.
function S.CraftChoice(id)
  return charStore().craft[id] == "auction" and "auction" or "craft"
end

function S.SetCraftChoice(id, choice)
  id = PL.Id(id)
  local craft = charStore().craft
  if not id then
    return nil
  end
  if craft[id] == nil and choice ~= "auction" then
    return "craft"
  end
  if choice == "auction" then
    local n = 0
    for _ in pairs(craft) do
      n = n + 1
    end
    if craft[id] == nil and n >= MAX_CHOICES then
      return nil
    end
    craft[id] = "auction"
  else
    craft[id] = nil
  end
  ns.Emit("FG_PROFROUTE_CHANGED", "craft")
  return S.CraftChoice(id)
end

-- Own professions ------------------------------------------------------------------------------

-- The professions with a route { slug, name, skill, max }: read live, else from the saved entry of
-- the character.
function S.Own()
  local list = ns.Professions and ns.Professions.Read()
  if not list and ns.CharRoster then
    for _, entry in ipairs(ns.CharRoster.List()) do
      if entry.current then
        list = entry.professions
      end
    end
  end
  return R.OwnRoutes(list)
end

-- The profession shown: the saved choice, else the first own one, else the first slug.
function S.Slug()
  return S.Option("slug") or (S.Own()[1] or {}).slug or R.SLUGS[1]
end

-- skill and maximum of an own profession, nil when the character does not have it.
function S.Skill(slug)
  for _, p in ipairs(S.Own()) do
    if p.slug == slug then
      return p.skill, p.max
    end
  end
  return nil
end

-- Stock ----------------------------------------------------------------------------------------

local function stockOf()
  local Inv = ns.Inventory
  if Inv and Inv.Fresh then
    Inv.Fresh()
  end
  local inventory = type(ns.db) == "table" and ns.db.inventory or {}
  local keys = {}
  if S.Option("all") then
    for key in pairs(inventory) do
      if key ~= ns.InventoryLogic.ACCOUNT_KEY then
        keys[#keys + 1] = key
      end
    end
  else
    keys[1] = characterKey()
  end
  return R.Stock(inventory, keys, S.Option("all"))
end

-- Shopping list connection and prices --------------------------------------------------------------

function S.ListApiReady()
  return ns.PriceSourceAddon.ListReady()
end

local DAY = 86400

local function priceSettings()
  local db = type(ns.db) == "table" and ns.db.settings
  return type(db) == "table" and type(db.priceDb) == "table" and db.priceDb or {}
end

local function maxAgeDays()
  local n = tonumber(priceSettings().maxAgeDays)
  return n and n > 0 and n or 14
end

local function now()
  local get = rawget(_G, "GetServerTime")
  local ok, t = pcall(get or ns.U.now)
  return ok and type(t) == "number" and t or 0
end

local function priceDb(name, ...)
  local db = ns.PriceDb
  if type(db) ~= "table" or type(db[name]) ~= "function" then
    return nil
  end
  local ok, value = pcall(db[name], ...)
  return ok and value or nil
end

-- An own price entry (the price database) of a house (a house key, nil = the house of the player's
-- faction), nil when the database is not loaded, switched off or has no usable minimum. Any error is
-- the same as no entry.
local function ownEntry(itemId, house)
  local entry = priceDb("Enabled") and priceDb("Get", itemId, house) or nil
  if type(entry) == "table" and type(entry.min) == "number" and entry.min > 0 then
    return entry
  end
end

-- The newest time of an entry.
local function stampOf(e)
  return math.max(tonumber(e.minAt) or 0, tonumber(e.scanAt) or 0)
end

-- key, entry of the neutral house with the freshest price of the item, nil without one.
local function neutralEntry(itemId)
  local bestKey, best
  for _, key in ipairs(priceDb("NeutralHouses") or {}) do
    local e = ownEntry(itemId, key)
    if e and (not best or stampOf(e) > stampOf(best)) then
      bestKey, best = key, e
    end
  end
  return bestKey, best
end

-- Where the unit price of an item comes from: { unit (copper), source = "own" | "addon", house =
-- "faction" | "neutral" | "legacy" (own data: the faction house of the player, a neutral house only
-- when the faction house has no price, the legacy data of older versions last), houseKey, age
-- (whole days, own data only), old (own data older than the age limit), info (the own entry, nil for
-- the price add-on) }, nil without any price. Fresh own data wins, then the price add-on, then old own
-- data (flagged old).
function S.PriceInfo(itemId)
  local ownKey = priceDb("OwnHouse")
  local houseKey, entry = ownKey, ownEntry(itemId, ownKey)
  local house = "faction"
  if not entry then
    houseKey, entry = neutralEntry(itemId)
    house = "neutral"
  end
  if not entry then
    house = "legacy"
    for _, key in ipairs({ priceDb("LegacyHouse", ownKey) or "", priceDb("LegacyHouse") or "" }) do
      houseKey, entry = key, ownEntry(itemId, key)
      if entry then
        break
      end
    end
  end
  local age
  if entry then
    local t = tonumber(entry.minAt)
    age = t and t > 0 and math.max(0, math.floor((now() - t) / DAY)) or nil
    local old = age ~= nil and age > maxAgeDays()
    if not old then
      return { unit = entry.min, source = "own", house = house, houseKey = houseKey, age = age, old = false, info = entry }
    end
  end
  local unit = ns.PriceSourceAddon.Unit(itemId)
  if unit then
    return { unit = unit, source = "addon", old = false }
  end
  if entry then
    return { unit = entry.min, source = "own", house = house, houseKey = houseKey, age = age, old = true, info = entry }
  end
end

-- Unit price in copper, nil when no source knows the item.
function S.AuctionPrice(itemId)
  local info = S.PriceInfo(itemId)
  return info and info.unit or nil
end

local function dateText(t)
  local fmt = rawget(_G, "date")
  local ok, text = pcall(fmt or os.date, ns.L["price.dateFormat"], t)
  return ok and type(text) == "string" and text or tostring(t)
end

-- The price block only goes to tooltips, so it shows the coin icons.
local function money(copper)
  return ns.CostLogic.Format(copper) or ns.L["profshop.noPrice"]
end

-- Marker behind a price that is old, comes from the price add-on, from another auction house than the
-- own faction house or from an older scan (the tooltip says which).
function S.PriceMark(info)
  return info and (info.old or info.source == "addon" or info.house == "neutral" or info.house == "legacy") and " ~"
    or ""
end

-- Adds "Lowest" and, when the entry has them, "Median" and "Highest", each with its own date.
local function entryLines(lines, e, prefix)
  local L = ns.L
  local function add(key, label, copper, at)
    local text = string.format(L["price.line"], L[label], money(copper))
    if at then
      text = text .. " " .. string.format(L["price.asOf"], dateText(at))
    end
    lines[#lines + 1] = { key = prefix .. key, text = text }
  end
  add("min", "price.min", e.min, tonumber(e.minAt))
  local scanAt = tonumber(e.scanAt)
  if type(e.median) == "number" and e.median > 0 then
    add("median", "price.median", e.median, scanAt)
  end
  if type(e.max) == "number" and e.max > 0 then
    add("max", "price.max", e.max, scanAt)
  end
end

-- The age of an entry in the short form of the other-house lines: "today" or "3d".
local function ageText(e)
  local t = stampOf(e)
  if t <= 0 then
    return ""
  end
  local days = math.max(0, math.floor((now() - t) / DAY))
  return days == 0 and ns.L["price.ageToday"] or string.format(ns.L["price.ageDays"], days)
end

-- The lines of the other auction houses (neutral houses, then the other faction) that have a price for the
-- item, except the house the main block shows: { key, text, left, right } each, behind an "otherHeader"
-- line. left (house) and right (price and age) go to one two column tooltip line, text is both in one line.
local function otherLines(itemId, skipKey)
  local keys = {}
  for _, key in ipairs(priceDb("NeutralHouses") or {}) do
    keys[#keys + 1] = key
  end
  keys[#keys + 1] = priceDb("OtherHouse")
  local lines = {}
  for _, key in ipairs(keys) do
    local e = key ~= skipKey and ownEntry(itemId, key) or nil
    if e then
      local name = priceDb("HouseName", key) or key
      local right = money(e.min) .. "  " .. ageText(e)
      lines[#lines + 1] = { key = "other", text = name .. ": " .. right, left = name, right = right }
    end
  end
  if #lines > 0 then
    table.insert(lines, 1, { key = "otherHeader", text = ns.L["price.other"] })
  end
  return lines
end

-- The lines of the price block: { { key, text }, ... }, nil without a price. Keys: header, min, median,
-- max, hint (median and highest need a full scan), old (age of old data), neutralOnly (the only data
-- is a neutral house), legacyOnly (the only data is an older scan), addon (price add-on), stack, then
-- with the option "other houses" otherHeader and one "other" line per house (see otherLines). The
-- first line after the header is always the lowest unit price. stack: the number of items in the stack
-- of the tooltip; the stack line is "AH: price" for one item and "AH (stack x N): price" for more (the
-- unit price stands in the lines above).
function S.PriceLines(itemId, stack)
  local info = S.PriceInfo(itemId)
  if not info then
    return nil
  end
  local L = ns.L
  local lines = { { key = "header", text = L["price.header"] } }
  if info.source == "addon" then
    lines[#lines + 1] = { key = "addon", text = string.format(L["price.addon"], money(info.unit)) }
  else
    local e = info.info
    entryLines(lines, e, "")
    if not (e.median and e.max) then
      lines[#lines + 1] = { key = "hint", text = L["price.hint"] }
    end
    if info.old and info.age then
      lines[#lines + 1] = { key = "old", text = string.format(L["price.old"], info.age) }
    end
    if info.house == "neutral" then
      lines[#lines + 1] = { key = "neutralOnly", text = L["price.neutralOnly"] }
    elseif info.house == "legacy" then
      lines[#lines + 1] = { key = "legacyOnly", text = L["price.legacyOnly"] }
    end
  end
  if type(stack) == "number" and stack >= 1 then
    local count = math.floor(stack)
    local text = count == 1 and string.format(L["price.one"], money(info.unit))
      or string.format(L["price.stack"], count, money(count * info.unit))
    lines[#lines + 1] = { key = "stack", text = text, total = count > 1 }
  end
  if priceSettings().showOther == true then
    for _, line in ipairs(otherLines(itemId, info.houseKey)) do
      lines[#lines + 1] = line
    end
  end
  return lines
end

local MUTED_LINES = { hint = true, old = true, neutralOnly = true, legacyOnly = true }

-- Item tooltip helpers --------------------------------------------------------------------------------

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
  if ok then
    return a, b, c, d, e, f, g, h, i, j, k
  end
end

local function itemApi(name)
  local api = rawget(_G, "C_Item")
  return type(api) == "table" and api[name] or rawget(_G, name)
end

-- Icon of an item from the client, nil while it is not known.
function S.ItemIcon(itemId)
  return call(itemApi("GetItemIconByID"), itemId) or select(5, call(itemApi("GetItemInfoInstant"), itemId))
end

-- Cost of one craft of the item at auction prices: copper and the number of reagents without a price, nil
-- when no recipe makes it or no reagent has a price. Asks the recipe data (loads it on first use).
function S.CraftCost(itemId)
  local access = ns.RecipeAccess
  local made = access and access.Producers(itemId)
  local recipe = made and made[1] and made[1].recipe
  if not recipe or type(recipe.mats) ~= "table" then
    return nil
  end
  local total, unpriced = 0, 0
  for _, m in ipairs(recipe.mats) do
    local unit = S.AuctionPrice(m[1])
    if unit then
      total = total + unit * (m[2] or 1)
    else
      unpriced = unpriced + 1
    end
  end
  if total == 0 then
    return nil
  end
  return total, unpriced
end

-- The client's own tooltip shows the vendor price on some clients: then it is not repeated.
local function hasSellLine(tip)
  local label = rawget(_G, "SELL_PRICE")
  local name = type(tip.GetName) == "function" and tip:GetName()
  if type(label) ~= "string" or not name then
    return false
  end
  for i = 1, (tip:NumLines() or 0) do
    local fs = rawget(_G, name .. "TextLeft" .. i)
    local text = fs and fs:GetText()
    if type(text) == "string" and text:find(label, 1, true) then
      return true
    end
  end
  return false
end

-- Extra lines of an item tooltip on the profession pages: crafting cost and vendor sell price. The auction
-- prices (lowest, median, highest) and the vendors that sell the item come with every item tooltip
-- (InventoryTooltip.lua). before: lines that go first (e.g. "2 per craft").
function S.ItemLines(itemId, before)
  return function(tip)
    local L = ns.L
    local lines = {}
    for _, line in ipairs(before or {}) do
      lines[#lines + 1] = line
    end
    local cost, unpriced = S.CraftCost(itemId)
    if cost then
      local text = money(cost)
      if unpriced > 0 then
        text = string.format(L["item.craftCostPart"], text, unpriced)
      end
      lines[#lines + 1] = { left = L["item.craftCost"], right = text, color = "textSecondary", rightColor = "text" }
    end
    local sell = select(11, call(itemApi("GetItemInfo"), itemId))
    if type(sell) == "number" and sell > 0 and not hasSellLine(tip) then
      lines[#lines + 1] =
        { left = L["item.vendorSell"], right = money(sell), color = "textSecondary", rightColor = "text" }
    end
    return lines
  end
end

-- The item tooltip of the profession pages: icon and client tooltip, the extra lines above, then the
-- inventory, vendor and auction price blocks. before: lines that go first; hint: muted last line.
function S.ShowItemTooltip(owner, itemId, before, hint)
  return ns.W.Tooltip.Show(owner, {
    link = "item:" .. tostring(itemId),
    icon = S.ItemIcon(itemId),
    lines = S.ItemLines(itemId, before),
    hint = hint,
  })
end

-- Tooltip of the price cell of a list row (nothing without a price).
function S.PriceTooltip(owner, line)
  local lines = S.PriceLines(line.id)
  if not lines then
    return false
  end
  local title = table.remove(lines, 1).text
  local out = {}
  for _, l in ipairs(lines) do
    local color = MUTED_LINES[l.key] and "textMuted" or l.key == "otherHeader" and "accent" or nil
    out[#out + 1] = { text = l.text, color = color }
    if l.right then
      out[#out].left, out[#out].right, out[#out].text = l.left, l.right, nil
    end
  end
  return ns.W.Tooltip.Show(owner, { title = title, lines = out })
end

-- The converter of the connected addon for a search term, nil when it is not there (R.Search builds by hand).
local converter = ns.PriceSourceAddon.Converter

-- The name the list has to search for: the item name of the client, else the data name in the
-- client language.
local function clientName(line)
  return ns.ItemInfo.name(line.id, { de = line.de, en = line.en }, line.name)
end
S.ClientName = clientName

-- Row actions -------------------------------------------------------------------------------------
-- Shared by every list row (shopping window, auction house panel, tracker panel). Nothing here
-- buys or bids: the search only fills the search of the auction house, the player presses
-- Blizzard's buy button.

local AUCTION_HOSTS = { "AuctionHouseFrame", "AuctionFrame" }

-- The shown auction house window, nil while it is closed or not loaded.
local function shownAuctionHouse()
  for _, name in ipairs(AUCTION_HOSTS) do
    local frame = rawget(_G, name)
    if type(frame) == "table" and type(frame.IsShown) == "function" then
      local ok, shown = pcall(frame.IsShown, frame)
      if ok and shown then
        return frame
      end
    end
  end
end

-- Fills the search box of Blizzard's window on the "Buy" tab and starts the search. False when
-- the fields are not there (older layout, changed client).
local function blizzardSearch(host, name)
  local bar = host.SearchBar
  local box = type(bar) == "table" and bar.SearchBox or nil
  if type(box) ~= "table" or type(box.SetText) ~= "function" then
    return false
  end
  local ok = pcall(function()
    local modes = rawget(_G, "AuctionHouseFrameDisplayMode")
    if type(host.SetDisplayMode) == "function" and type(modes) == "table" and modes.Buy ~= nil then
      if type(host.GetDisplayMode) ~= "function" or host:GetDisplayMode() ~= modes.Buy then
        host:SetDisplayMode(modes.Buy)
      end
    end
    box:SetText(name)
    if type(bar.StartSearch) == "function" then
      bar:StartSearch()
    elseif type(bar.SearchButton) == "table" and type(bar.SearchButton.Click) == "function" then
      bar.SearchButton:Click()
    end
  end)
  return ok
end

-- Direct open (standard window) ---------------------------------------------------------------------
-- Selects the item of a row by its ID and, for a commodity, sets the open quantity once the offers are in.
-- Only selects and fills a field: the buy button stays the player's.

local COMMODITY_EVENT = "COMMODITY_SEARCH_RESULTS_UPDATED"
local WAIT_SECONDS = 4
local waiter -- { frame, id, qty, host } of the pending wait, nil when none

local function stopWait()
  if waiter then
    pcall(waiter.frame.UnregisterEvent, waiter.frame, COMMODITY_EVENT)
    waiter.frame:SetScript("OnEvent", nil)
    waiter = nil
  end
end

-- True for a commodity (sold by quantity). Unknown status falls back to the key info.
local function isCommodity(ah, itemId, key)
  if type(ah.GetItemCommodityStatus) == "function" then
    local enum = rawget(_G, "Enum")
    local states = type(enum) == "table" and enum.ItemCommodityStatus or nil
    local commodity = type(states) == "table" and states.Commodity or 2
    local unknown = type(states) == "table" and states.Unknown or 0
    local status = ah.GetItemCommodityStatus(itemId)
    if status ~= unknown then
      return status == commodity
    end
  end
  if type(ah.GetItemKeyInfo) == "function" then
    local info = ah.GetItemKeyInfo(key)
    return type(info) == "table" and info.isCommodity == true
  end
  return false
end

local function setQuantity(host, count)
  local buy = host.CommoditiesBuyFrame
  local display = type(buy) == "table" and buy.BuyDisplay or nil
  local input = type(display) == "table" and display.QuantityInput or nil
  if type(input) ~= "table" then
    return false
  end
  local function current()
    return type(input.GetQuantity) == "function" and input:GetQuantity() or nil
  end
  local function write()
    if type(input.SetQuantity) == "function" then
      input:SetQuantity(count)
    elseif type(input.InputBox) == "table" and type(input.InputBox.SetNumber) == "function" then
      input.InputBox:SetNumber(count)
    else
      return false
    end
    return true
  end
  local ok, written = pcall(write)
  if not (ok and written) then
    return false
  end
  -- The buy view may reset the field while it builds: one more write on the next frame, no loop.
  if type(C_Timer) == "table" and C_Timer.After then
    C_Timer.After(0, function()
      local read, value = pcall(current)
      if read and value ~= nil and value ~= count then
        pcall(write)
      end
    end)
  end
  return true
end

local function applyQuantity(host, itemId, wanted)
  local ah = rawget(_G, "C_AuctionHouse")
  local ok, offered = pcall(function()
    return ah.GetCommoditySearchResultsQuantity(itemId)
  end)
  if not (ok and type(offered) == "number") then
    return
  end
  if offered < wanted then
    ns.Notify(string.format(ns.L["profshop.offerShort"], offered, wanted), "info")
  end
  local count = math.min(wanted, offered)
  if count >= 1 then
    setQuantity(host, count)
  end
end

local function waitForOffers(host, itemId, wanted)
  stopWait()
  if type(C_Timer) ~= "table" or not C_Timer.After then
    return
  end
  local frame = CreateFrame("Frame")
  local token = { frame = frame, id = itemId }
  waiter = token
  frame:RegisterEvent(COMMODITY_EVENT)
  frame:SetScript("OnEvent", function(_, _, id)
    if waiter ~= token or id ~= itemId then
      return
    end
    stopWait()
    pcall(applyQuantity, host, itemId, wanted)
  end)
  C_Timer.After(WAIT_SECONDS, function()
    if waiter == token then
      stopWait()
    end
  end)
end

-- Opens the item in the standard window. False when the calls are not there or raise, the caller then
-- runs the name search.
local function openDirect(host, itemId, quantity)
  local ah = rawget(_G, "C_AuctionHouse")
  if
    type(ah) ~= "table"
    or type(ah.MakeItemKey) ~= "function"
    or type(host.SelectBrowseResult) ~= "function"
    or type(itemId) ~= "number"
  then
    return false
  end
  local ok, commodity = pcall(function()
    local key = ah.MakeItemKey(itemId)
    if type(key) ~= "table" then
      error("no item key")
    end
    host:SelectBrowseResult({ itemKey = key })
    return isCommodity(ah, itemId, key)
  end)
  if not ok then
    return false
  end
  if commodity and type(ah.GetCommoditySearchResultsQuantity) == "function" then
    waitForOffers(host, itemId, quantity)
  end
  return true
end

-- Searches an item name in the open auction house: through the connected addon when its search call
-- is there, else the search box of the standard window. Returns "addon", "blizzard", "closed" (window not
-- open), "combat" (nothing happens) or "failed" (no way to search). With an item ID and the open quantity
-- (item = { id, qty }) the item is opened directly first ("addon" or "direct"), every failure ends in the name search.
function S.SearchAuction(name, item)
  if ns.CombatLocked() then
    return "combat"
  end
  local host = shownAuctionHouse()
  if not host then
    return "closed"
  end
  if type(item) == "table" and type(item.id) == "number" then
    local quantity = math.max(1, math.floor(tonumber(item.qty) or 1))
    local mode = host.displayMode
    local found = ns.PriceSourceAddon.SearchItem(name, quantity)
    if found == "ok" then
      -- The connected addon may reset the mode of the window while it opens its view.
      if host.displayMode == nil and mode ~= nil then
        host.displayMode = mode
      end
      return "addon"
    elseif openDirect(host, item.id, quantity) then
      return "direct"
    end
  end
  local state, err = ns.PriceSourceAddon.Search(name)
  if state == "ok" then
    return "addon"
  elseif state == "failed" then
    ns.Log.warn("list search failed: %s", tostring(err))
  end
  return blizzardSearch(host, name) and "blizzard" or "failed"
end

local function itemLink(line, name)
  local item = rawget(_G, "C_Item")
  local get = type(item) == "table" and item.GetItemInfo or rawget(_G, "GetItemInfo")
  if type(get) == "function" then
    local ok, _, link = pcall(get, line.id)
    if ok and type(link) == "string" and link ~= "" then
      return link
    end
  end
  -- Plain name while the client has no link (a self-built link is refused in the chat).
  return "[" .. name .. "]"
end

-- Into the open chat edit box, else opens the chat with the link in it.
local function insertChatLink(link)
  local util = rawget(_G, "ChatFrameUtil")
  util = type(util) == "table" and util or {}
  local insert = util.InsertLink or rawget(_G, "ChatEdit_InsertLink")
  if type(insert) ~= "function" then
    return
  end
  local ok, done = pcall(insert, link)
  local open = util.OpenChat or rawget(_G, "ChatFrame_OpenChat")
  if not (ok and done) and type(open) == "function" then
    pcall(open, link)
  end
end

-- A click on a list row: left = search, right = copy the name, Shift + left = link in the chat, Ctrl + left = preview.
-- Returns what happened ("copy", "link" or the result of SearchAuction), nil without a line.
function S.RowClick(line, button)
  if type(line) ~= "table" then
    return nil
  end
  local name = clientName(line)
  if button == "RightButton" then
    ns.Dialogs.Copy("profshop.nameTitle", name)
    return "copy"
  elseif type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true then
    insertChatLink(itemLink(line, name))
    return "link"
  end
  if ns.ItemActions.Click(line.id, button) then
    return "preview"
  end
  -- An item only a vendor sells is not at the auction house: the click walks to the nearest vendor.
  local best = line.source == "vendor" and ns.VendorSource and ns.VendorSource.Best(line.id) or nil
  if best then
    ns.VendorSource.SetWaypoint(best.place)
    return "waypoint"
  end
  local result = S.SearchAuction(name, { id = line.id, qty = line.qty })
  if result == "closed" then
    ns.Notify(string.format(ns.L["profshop.openAuction"], name), "info")
  elseif result == "failed" then
    ns.Notify(string.format(ns.L["profshop.searchFailed"], name), "warning")
  end
  return result
end

-- Tooltip of a list row: the item, what the clicks do, how much of it is there and where it is bought.
function S.RowTooltip(owner, line)
  local L = ns.L
  local best = line.source == "vendor" and ns.VendorSource and ns.VendorSource.Best(line.id) or nil
  local lines = {}
  -- What is still to buy comes first and in white, the clicks follow.
  if line.need and line.have then
    if S.Option("stock") then
      lines[#lines + 1] = "|cffffffff" .. string.format(L["profshop.rowBuy"], line.qty or 0) .. "|r"
      lines[#lines + 1] = string.format(L["profshop.rowHaveOf"], line.have, line.need)
    else
      lines[#lines + 1] = string.format(L["profshop.rowHaveInfo"], line.have, line.need)
    end
  end
  lines[#lines + 1] = best and L["vendor.listTip"] or L["profshop.rowSearch"]
  lines[#lines + 1] = L["profshop.rowMore"]
  if line.source == "vendor" then
    lines[#lines + 1] = L["profshop.rowVendor"]
    if best then
      lines[#lines + 1] = string.format(L["vendor.where"], best.text)
    end
  elseif line.crafted then
    lines[#lines + 1] = L["shoplist.rowCrafted"]
  end
  ns.W.Tooltip.Show(owner, { link = "item:" .. line.id, title = line.name, lines = lines })
end

-- Text and color token of the progress of a row of the list view: "have/need". Green once the stock
-- covers the amount, orange when part of it is there.
local PROGRESS_COLOR = { none = "textSecondary", partial = "warning", complete = "success" }
function S.Progress(row)
  return string.format("%d/%d", row.have, row.need), PROGRESS_COLOR[row.state] or PROGRESS_COLOR.none
end

-- The name of a row as both list windows paint it: in the quality color of the item (a done row stays
-- plain), the head of a group with the progress of its materials behind it.
function S.RowLabel(row)
  local line = row.line
  local text = row.ticked and line.name or ns.ItemInfo.ColorName(line.name, ns.ItemInfo.quality(line.id))
  if row.head and row.kids > 0 then
    text = string.format("%s  (%d/%d)", text, row.kidsTicked, row.kids)
  end
  return text
end

-- Plan ------------------------------------------------------------------------------------------

-- Everything the page and the window show for one profession:
-- { slug, name, status, data, skill, from, to, all, deduct, lines, covered, groups, total, unpriced,
-- listName, hidden }. all: every position, the route lines with the edits of the list applied
-- (ProfessionList.lua) plus the own positions, with the stock taken over (need, have, qty, state,
-- complete, see PL.Allocate). lines: the positions that still have to be bought (what the texts, the
-- chat link and the auction list use), groups and the sums are made of them; covered counts the
-- positions the stock covers. hidden counts the route lines the player removed.
-- Without route data only slug, name and status are set, and the lines when there are own positions.
-- The windows do not read this directly but S.View, which adds options, grouping and order.
-- Recipes by the item they make: the profession of the list first, then the others in slug order. The
-- data names no output count, one craft makes one item. Nil for an item without a known recipe.
local recipeIndex = setmetatable({}, { __mode = "k" })

local function indexOf(list)
  local index = recipeIndex[list]
  if not index then
    index = {}
    for _, r in ipairs(list) do
      if type(r.i) == "number" and type(r.mats) == "table" and not r.rm and index[r.i] == nil then
        index[r.i] = r
      end
    end
    recipeIndex[list] = index
  end
  return index
end

local function findRecipe(id, slug)
  local Access = ns.RecipeAccess
  if not Access then
    return nil
  end
  local order = { slug }
  for _, other in ipairs(R.SLUGS) do
    if other ~= slug then
      order[#order + 1] = other
    end
  end
  for _, one in ipairs(order) do
    local data, list = Access.Get(one)
    local r = list and indexOf(list)[id]
    if r then
      return { mats = r.mats, out = 1, items = type(data.items) == "table" and data.items or nil }
    end
  end
end

-- The fields of a line for a material: the name, icon and source of the route when it knows the item,
-- else those of the recipe data, bought at the auction house. An item the route does not know but a
-- recipe makes is crafted by default (so the materials of a single item resolve down to the raw ones).
local function materialFields(plan, id, recipe, known)
  local info = plan.data and type(plan.data.items) == "table" and plan.data.items[id] or nil
  local extra = recipe and recipe.items and recipe.items[id] or nil
  local named = info or extra or {}
  local source = R.DEFAULT_SOURCE
  for _, group in ipairs(R.GROUPS) do
    if info and info.buy == group then
      source = group
    end
  end
  if not info and known then
    source = "craft"
  end
  local price
  if source == "vendor" then
    price = info and tonumber(info.price)
    price = price and price > 0 and price or nil
  elseif source == "auction" then
    price = S.AuctionPrice(id)
  end
  return {
    name = clientName({ id = id, de = named.de, en = named.en, name = string.format(ns.L["proflist.itemName"], id) }),
    de = named.de,
    en = named.en,
    icon = info and info.icon or extra and extra.ico,
    q = info and info.q,
    source = source,
    price = price,
  }
end

local function finishPlan(plan)
  plan.deduct = S.Option("stock")
  if #plan.lines > 0 then
    local memo = {}
    local function recipeOf(id)
      if memo[id] == nil then
        memo[id] = findRecipe(id, plan.slug) or false
      end
      return memo[id] or nil
    end
    plan.lines = PL.Resolve(plan.lines, {
      stock = stockOf(),
      deduct = plan.deduct,
      slug = plan.slug,
      recipe = recipeOf,
      ticks = ns.ProfessionList and ns.ProfessionList.Ticks() or nil,
      choice = S.CraftChoice,
      derive = function(id, recipe)
        return materialFields(plan, id, recipe, recipeOf(id) ~= nil)
      end,
      auctionPrice = S.AuctionPrice,
    })
  end
  plan.all = plan.lines
  plan.lines, plan.covered = PL.Open(plan.all, plan.deduct)
  plan.groups = R.Group(plan.lines)
  plan.total, plan.unpriced = R.Cost(plan.groups)
end

-- opts.fromStart: without a typed start the plan begins at the start of the route, not at the own skill.
function S.Plan(slug, opts)
  slug = slug or S.Slug()
  local plan = { slug = slug, name = R.Name(slug) }
  local data, status = Data.Get(slug)
  plan.status = status
  local List = ns.ProfessionList
  if not data then
    local lines = List and List.Apply(slug, {}) or {}
    if #lines > 0 then
      plan.lines, plan.hidden = lines, 0
      finishPlan(plan)
      plan.listName = R.ListName(plan.name)
    end
    return plan
  end
  local skill, max = S.Skill(slug)
  plan.data, plan.skill = data, skill
  local routeMax = tonumber(data.max) or max or 0
  -- A profession the character does not have plans from the start of the route, so any route can
  -- fill the list.
  plan.from = S.Option("from") or (not (opts and opts.fromStart) and skill) or R.StartSkill(data)
  plan.to = math.min(S.Option("target") or routeMax, routeMax)
  -- The route needs come without stock: the stock is allocated once over the whole list afterwards.
  plan.lines = R.Needs(data, plan.from, plan.to, {
    surcharge = S.Option("surcharge"),
    auctionPrice = S.AuctionPrice,
  })
  if List then
    plan.lines, plan.hidden = List.Apply(slug, plan.lines)
  end
  finishPlan(plan)
  plan.listName = R.ListName(plan.name, plan.from, plan.to)
  return plan
end

-- One choice for every craftable item of the list (the shortcut "craft all" / "buy all crafted at the
-- auction house"). Returns how many items it was set for.
function S.SetCraftAll(choice)
  local plan, n = S.Plan(), 0
  for _, line in ipairs(plan.all or {}) do
    if line.craftable and line.choice ~= choice then
      n = n + 1
      local craft = charStore().craft
      craft[line.id] = choice == "auction" and "auction" or nil
    end
  end
  if n > 0 then
    ns.Emit("FG_PROFROUTE_CHANGED", "craft")
  end
  return n
end

-- The list as every window shows it: the plan after the options (stock, all characters, surcharge,
-- own positions, edits), grouped and sorted by the chosen view (PL.View). The shopping window and the
-- auction house list both call this and nothing else, so they never differ. view.plan is the plan.
function S.View(slug)
  local plan = S.Plan(slug)
  local view = PL.View(plan.all or {}, {
    mode = S.Option("view"),
    checked = S.Checked(plan.slug),
    deduct = plan.deduct,
    label = function()
      return plan.data and string.format("%s %d-%d", plan.name, plan.from, plan.to) or plan.name
    end,
  })
  view.plan = plan
  return view
end

-- Texts ------------------------------------------------------------------------------------------

-- One line "<list name>^<search>^..." for the import box of the shopping list.
function S.ImportText(plan)
  local searches = R.Searches(plan.lines, S.Checked(plan.slug), converter(), clientName)
  return R.ImportText(plan.listName, searches), #searches
end

-- The plain list, ticked lines marked.
function S.PlainText(plan)
  local checked = S.Checked(plan.slug)
  return R.ListText(plan.groups, {
    title = plan.listName,
    checked = checked,
    groupTitle = function(source)
      return ns.L["profshop.group." .. source]
    end,
  })
end

-- Creates the list in the connected addon. Returns "sent" and the count, "nothing", "noApi" (the
-- addon or its list API is not there) or "failed" (the call raised an error). mode "append" adds the
-- searches to the list of that name instead of replacing it.
function S.Send(plan, mode)
  if not S.ListApiReady() then
    return "noApi"
  end
  local searches = R.Searches(plan.lines, S.Checked(plan.slug), converter(), clientName)
  if #searches == 0 then
    return "nothing"
  end
  local P = ns.PriceSourceAddon
  local state, err
  if mode == "append" then
    state, err = P.AppendToList(plan.listName, searches)
  else
    state, err = P.CreateList(plan.listName, searches)
  end
  if state ~= "ok" then
    ns.Log.warn("list creation failed: %s", tostring(err))
    return "failed"
  end
  return "sent", #searches
end
