-- Game side of the profession route and its shopping list: which professions the character has,
-- the saved choices (profession, target, surcharge, stock) and ticks per character and profession,
-- the stock from the inventory snapshots, the price resolution (own price data first, then the price
-- add-on, see PriceSourceAddon.lua), the shopping list connection and the two copy texts. The pure side is Modules/ProfessionRouteLogic.lua, the windows
-- are ProfessionShopWindow.lua and ProfessionRoutePage.lua.
--
-- ns.db.profRoute = {
--   v = 2,
--   opts = { slug, target, from, surcharge, stock, all, view, autoOpen },
--   craft = { [itemId] = "craft" | "auction" },   -- how a craftable item is got, shared by all lists
--   checked = { [characterKey] = { [slug] = { [itemId] = true } } },
--   list = { [characterKey] = { ... } },   -- own positions and edits, see ProfessionListLogic.lua
-- }
local _, ns = ...
local R = ns.ProfessionRouteLogic
local PL = ns.ProfessionListLogic
local Data = ns.ProfessionRouteData

local S = {}
ns.ProfessionShop = S

ns.AddLocale("enUS", {
  ["profshop.sent"] = "Shopping list created: %d items",
  ["profshop.noApi"] = "No shopping list connection, text opens.",
  ["profshop.failed"] = "Shopping list failed, text opens.",
  ["profshop.nothing"] = "Nothing to send.",
  ["profshop.group.vendor"] = "Vendor",
  ["profshop.group.auction"] = "Auction house",
  ["profshop.group.gather"] = "Gather yourself",
  ["profshop.group.craft"] = "Craft yourself",
  ["profshop.openAuction"] = "Open the auction house: %s",
  ["profshop.searchFailed"] = "Search not possible: %s",
  ["profshop.rowSearch"] = "Click: search in auction house",
  ["profshop.rowMore"] = "Right click: copy name, Shift click: link",
  ["profshop.nameTitle"] = "Item name",
  ["profshop.hint"] = "Click an item to search it in the Auction House.",
  ["profshop.rowHave"] = "Have %d of %d, still to buy: %d",
  ["profshop.rowHaveInfo"] = "Have %d of %d (stock is not subtracted)",
  ["profshop.rowVendor"] = "Vendor item: buy it at a vendor.",
  ["price.header"] = "Price:",
  ["price.min"] = "Lowest",
  ["price.median"] = "Median",
  ["price.max"] = "Highest",
  ["price.line"] = "%s: %s",
  ["price.asOf"] = "(as of %s)",
  ["price.dateFormat"] = "%Y-%m-%d",
  ["price.hint"] = "Median and highest come from a full scan.",
  ["price.addon"] = "Price add-on: %s",
  ["price.old"] = "Old data: %d days old",
  ["price.stack"] = "Stack of %d: %s",
  ["price.neutral"] = "Neutral auction house",
  ["price.neutralOnly"] = "Only neutral auction house data",
})
ns.AddLocale("deDE", {
  ["profshop.sent"] = "Einkaufsliste erstellt: %d Artikel",
  ["profshop.noApi"] = "Keine Einkaufslisten-Anbindung, Text wird gezeigt.",
  ["profshop.failed"] = "Einkaufsliste fehlgeschlagen, Text wird gezeigt.",
  ["profshop.nothing"] = "Nichts zu senden.",
  ["profshop.group.vendor"] = "Händler",
  ["profshop.group.auction"] = "Auktionshaus",
  ["profshop.group.gather"] = "Selbst sammeln",
  ["profshop.group.craft"] = "Selbst herstellen",
  ["profshop.openAuction"] = "Öffne das Auktionshaus: %s",
  ["profshop.searchFailed"] = "Suche nicht möglich: %s",
  ["profshop.rowSearch"] = "Klick: im Auktionshaus suchen",
  ["profshop.rowMore"] = "Rechtsklick: Name kopieren, Umschalt-Klick: Link",
  ["profshop.nameTitle"] = "Item-Name",
  ["profshop.hint"] = "Klicke ein Item, um es im Auktionshaus zu suchen.",
  ["profshop.rowHave"] = "Vorhanden %d von %d, noch zu kaufen: %d",
  ["profshop.rowHaveInfo"] = "Vorhanden %d von %d (Bestand nicht abgezogen)",
  ["profshop.rowVendor"] = "Händlerware: beim Händler kaufen.",
  ["price.header"] = "Preis:",
  ["price.min"] = "Niedrigster",
  ["price.median"] = "Median",
  ["price.max"] = "Höchster",
  ["price.line"] = "%s: %s",
  ["price.asOf"] = "(Stand: %s)",
  ["price.dateFormat"] = "%d.%m.%Y",
  ["price.hint"] = "Median und Höchster kommen aus einem vollständigen Scan.",
  ["price.addon"] = "Preis-Addon: %s",
  ["price.old"] = "Alte Daten: %d Tage alt",
  ["price.stack"] = "Stapel (%d): %s",
  ["price.neutral"] = "Neutrales Auktionshaus",
  ["price.neutralOnly"] = "Nur Daten des neutralen Auktionshauses",
})

local DEFAULTS = { stock = true, all = false, autoOpen = true }
local VIEWS = { combined = true, reason = true }

-- Saved state ---------------------------------------------------------------------------------

local scratch = { opts = {}, checked = {} }

-- A skill value above 0, nil for empty or invalid input (= automatic).
local function skillValue(v)
  local n = R.Whole(v)
  return n and n > 0 and n or nil
end

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

-- key: slug (a known slug), target and from (whole skill, nil = automatic), surcharge (percent),
-- stock (take the stock off), all (stock of all characters), view ("combined" | "reason", one choice
-- for every list window), autoOpen (the list opens by itself at the auction house).
function S.Option(key)
  local v = store().opts[key]
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
  local opts = store().opts
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

-- The ticks of the current character for one profession, { [itemId] = true }; changes to the table
-- are saved.
function S.Checked(slug)
  local byChar = store().checked
  local key = characterKey()
  if type(byChar[key]) ~= "table" then
    byChar[key] = {}
  end
  if type(byChar[key][slug]) ~= "table" then
    byChar[key][slug] = {}
  end
  return byChar[key][slug]
end

function S.SetChecked(slug, itemId, on)
  S.Checked(slug)[itemId] = on and true or nil
  ns.Emit("FG_PROFROUTE_CHANGED", "checked")
end

function S.ClearChecked(slug)
  local byChar = store().checked
  local key = characterKey()
  if type(byChar[key]) == "table" then
    byChar[key][slug] = nil
  end
  ns.Emit("FG_PROFROUTE_CHANGED", "checked")
end

-- Craft or buy -------------------------------------------------------------------------------------

local MAX_CHOICES = 500

-- How a craftable item is got: "craft" (its materials are on the list instead of the item, the
-- default) or "auction" (the item itself is bought). One choice per item for every list window.
function S.CraftChoice(id)
  return store().craft[id] == "auction" and "auction" or "craft"
end

function S.SetCraftChoice(id, choice)
  id = PL.Id(id)
  local craft = store().craft
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

-- An own price entry (the price database) of a house ("Neutral", nil = the house of the player's
-- faction), nil when the database is not loaded, switched off or has no usable minimum. Any error is
-- the same as no entry.
local function ownEntry(itemId, house)
  local db = ns.PriceDb
  if type(db) ~= "table" or type(db.Get) ~= "function" or type(db.Enabled) ~= "function" then
    return nil
  end
  local ok, entry = pcall(function()
    return db.Enabled() and db.Get(itemId, house) or nil
  end)
  if ok and type(entry) == "table" and type(entry.min) == "number" and entry.min > 0 then
    return entry
  end
end

-- Where the unit price of an item comes from: { unit (copper), source = "own" | "addon", house =
-- "faction" | "neutral" (own data: the neutral house only when the faction house has no price), age
-- (whole days, own data only), old (own data older than the age limit), info (the own entry, nil for
-- the price add-on), neutral (the entry of the neutral house when there is one next to the faction
-- house) }, nil without any price. Fresh own data wins, then the price add-on, then old own data
-- (flagged old).
function S.PriceInfo(itemId)
  local faction, neutral = ownEntry(itemId), ownEntry(itemId, "Neutral")
  local entry = faction or neutral
  local house = faction and "faction" or "neutral"
  local age
  if entry then
    local t = tonumber(entry.minAt)
    age = t and t > 0 and math.max(0, math.floor((now() - t) / DAY)) or nil
    local old = age ~= nil and age > maxAgeDays()
    if not old then
      return {
        unit = entry.min,
        source = "own",
        house = house,
        age = age,
        old = false,
        info = entry,
        neutral = faction and neutral or nil,
      }
    end
  end
  local unit = ns.PriceSourceAddon.Unit(itemId)
  if unit then
    return { unit = unit, source = "addon", old = false }
  end
  if entry then
    return {
      unit = entry.min,
      source = "own",
      house = house,
      age = age,
      old = true,
      info = entry,
      neutral = faction and neutral or nil,
    }
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

-- Marker behind a price that is old or comes from the price add-on (the tooltip says which).
function S.PriceMark(info)
  return info and (info.old or info.source == "addon") and " ~" or ""
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

-- The lines of the price block: { { key, text }, ... }, nil without a price. Keys: header, min, median,
-- max, hint (median and highest need a full scan), old (age of old data), neutralOnly (the only data
-- is the neutral house), addon (price add-on), stack, then for a neutral house next to the faction
-- house neutralHeader, neutralmin, neutralmedian, neutralmax. The first line after the header is
-- always the lowest unit price. stack: the number of items in the stack of the tooltip (the price of
-- the stack is added for more than one).
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
    end
  end
  if type(stack) == "number" and stack > 1 then
    local total = math.floor(stack) * info.unit
    lines[#lines + 1] = { key = "stack", text = string.format(L["price.stack"], math.floor(stack), money(total)) }
  end
  if info.neutral then
    lines[#lines + 1] = { key = "neutralHeader", text = L["price.neutral"] }
    entryLines(lines, info.neutral, "neutral")
  end
  return lines
end

local MUTED_LINES = { hint = true, old = true, neutralOnly = true }

-- Tooltip of the price cell of a list row (nothing without a price).
function S.PriceTooltip(owner, line)
  local lines = S.PriceLines(line.id)
  if not lines then
    return false
  end
  local title = table.remove(lines, 1).text
  local out = {}
  for _, l in ipairs(lines) do
    local color = MUTED_LINES[l.key] and "textMuted" or l.key == "neutralHeader" and "accent" or nil
    out[#out + 1] = { text = l.text, color = color }
  end
  return ns.W.Tooltip.Show(owner, { title = title, lines = out })
end

-- The converter of the connected addon for a search term, nil when it is not there (R.Search builds by hand).
local converter = ns.PriceSourceAddon.Converter

-- The name the list has to search for: the item name of the client, else the data name in the
-- client language.
local function clientName(line)
  local item = rawget(_G, "C_Item")
  local byId = type(item) == "table" and item.GetItemNameByID or rawget(_G, "GetItemInfo")
  if type(byId) == "function" then
    local ok, name = pcall(byId, line.id)
    if ok and type(name) == "string" and name ~= "" then
      return name
    end
  end
  local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
  return (locale == "deDE" and line.de or line.en) or line.name
end
S.ClientName = clientName

-- Row actions -------------------------------------------------------------------------------------
-- Shared by every list row (shopping window, auction house panel, tracker panel). Nothing here
-- buys or bids: the search only fills the search of the auction house, the player presses
-- Blizzard's buy button.

local AUCTION_HOSTS = { "AuctionHouseFrame", "AuctionFrame" }

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

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

-- Searches an item name in the open auction house: through the connected addon when its search call
-- is there, else the search box of the standard window. Returns "addon", "blizzard", "closed" (window not
-- open), "combat" (nothing happens) or "failed" (no way to search).
function S.SearchAuction(name)
  if inCombat() then
    return "combat"
  end
  local host = shownAuctionHouse()
  if not host then
    return "closed"
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
  return string.format("|Hitem:%d|h[%s]|h", line.id, name)
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

-- A click on a list row: left = search, right = copy the name, Shift + left = link in the chat.
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
  local result = S.SearchAuction(name)
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
  local lines = { L["profshop.rowSearch"], L["profshop.rowMore"] }
  if line.need and line.have then
    local key = S.Option("stock") and "profshop.rowHave" or "profshop.rowHaveInfo"
    lines[#lines + 1] = string.format(L[key], line.have, line.need, line.qty)
  end
  if line.source == "vendor" then
    lines[#lines + 1] = L["profshop.rowVendor"]
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

function S.Plan(slug)
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
  plan.from = S.Option("from") or skill or 0
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
      local craft = store().craft
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
-- addon or its list API is not there) or "failed" (the call raised an error).
function S.Send(plan)
  if not S.ListApiReady() then
    return "noApi"
  end
  local searches = R.Searches(plan.lines, S.Checked(plan.slug), converter(), clientName)
  if #searches == 0 then
    return "nothing"
  end
  local state, err = ns.PriceSourceAddon.CreateList(plan.listName, searches)
  if state ~= "ok" then
    ns.Log.warn("list creation failed: %s", tostring(err))
    return "failed"
  end
  return "sent", #searches
end
