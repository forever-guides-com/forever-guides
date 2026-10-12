-- Game side of the profession route and its shopping list: which professions the character has,
-- the saved choices (profession, target, surcharge, stock) and ticks per character and profession,
-- the stock from the inventory snapshots, the shopping list connection (public API only, every call
-- in pcall) and the two copy texts. The pure side is Modules/ProfessionRouteLogic.lua, the windows
-- are ProfessionShopWindow.lua and ProfessionRoutePage.lua.
--
-- ns.db.profRoute = {
--   opts = { slug, target, from, surcharge, stock, all },
--   checked = { [characterKey] = { [slug] = { [itemId] = true } } },
-- }
local _, ns = ...
local R = ns.ProfessionRouteLogic
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
})

local DEFAULTS = { stock = true, all = false }

-- Saved state ---------------------------------------------------------------------------------

local scratch = { opts = {}, checked = {} }

-- A skill value above 0, nil for empty or invalid input (= automatic).
local function skillValue(v)
  local n = R.Whole(v)
  return n and n > 0 and n or nil
end

local function store()
  local db = ns.db
  if type(db) ~= "table" then
    return scratch
  end
  if type(db.profRoute) ~= "table" then
    db.profRoute = {}
  end
  local t = db.profRoute
  if type(t.opts) ~= "table" then
    t.opts = {}
  end
  if type(t.checked) ~= "table" then
    t.checked = {}
  end
  return t
end

-- key: slug (a known slug), target and from (whole skill, nil = automatic), surcharge (percent),
-- stock (take the stock off), all (stock of all characters).
function S.Option(key)
  local v = store().opts[key]
  if key == "slug" then
    return R.PROFESSIONS[v] and v or nil
  elseif key == "target" or key == "from" then
    return skillValue(v)
  elseif key == "surcharge" then
    return R.Surcharge(v)
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
  elseif key == "stock" or key == "all" then
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

-- Shopping list connection -----------------------------------------------------------------------------------

local function api()
  local a = rawget(_G, "Auctionator")
  local v1 = type(a) == "table" and type(a.API) == "table" and a.API.v1 or nil
  return type(v1) == "table" and v1 or nil
end

function S.ListApiReady()
  local v1 = api()
  return v1 ~= nil and type(v1.CreateShoppingList) == "function"
end

-- Last scanned auction price in copper, nil without the connection, without a scan or on any error.
function S.AuctionPrice(itemId)
  local v1 = api()
  if not (v1 and type(v1.GetAuctionPriceByItemID) == "function") then
    return nil
  end
  local ok, price = pcall(v1.GetAuctionPriceByItemID, R.CALLER, itemId)
  return ok and type(price) == "number" and price > 0 and price or nil
end

-- The converter of the connected addon for a search term, nil when it is not there (R.Search builds by hand).
local function converter()
  local v1 = api()
  if v1 and type(v1.ConvertToSearchString) == "function" then
    return function(term)
      return v1.ConvertToSearchString(R.CALLER, term)
    end
  end
end

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
-- is there, else the search box of the standard window. Returns "auctionator", "blizzard", "closed" (window not
-- open), "combat" (nothing happens) or "failed" (no way to search).
function S.SearchAuction(name)
  if inCombat() then
    return "combat"
  end
  local host = shownAuctionHouse()
  if not host then
    return "closed"
  end
  local v1 = api()
  -- The exact variant keeps similar names out of the result; older versions only know MultiSearch.
  local multi = v1 and (v1.MultiSearchExact or v1.MultiSearch)
  if type(multi) == "function" then
    local ok, err = pcall(multi, R.CALLER, { name })
    if ok then
      return "auctionator"
    end
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

-- Tooltip of a list row: the item, then what the clicks do.
function S.RowTooltip(owner, line)
  ns.W.Tooltip.Show(owner, {
    link = "item:" .. line.id,
    title = line.name,
    lines = { ns.L["profshop.rowSearch"], ns.L["profshop.rowMore"] },
  })
end

-- Plan ------------------------------------------------------------------------------------------

-- Everything the page and the window show for one profession:
-- { slug, name, status, data, skill, from, to, lines, covered, groups, total, unpriced, listName }.
-- Without route data only slug, name and status are set.
function S.Plan(slug)
  slug = slug or S.Slug()
  local plan = { slug = slug, name = R.Name(slug) }
  local data, status = Data.Get(slug)
  plan.status = status
  if not data then
    return plan
  end
  local skill, max = S.Skill(slug)
  plan.data, plan.skill = data, skill
  local routeMax = tonumber(data.max) or max or 0
  plan.from = S.Option("from") or skill or 0
  plan.to = math.min(S.Option("target") or routeMax, routeMax)
  local stock = S.Option("stock") and stockOf() or nil
  plan.lines, plan.covered = R.Needs(data, plan.from, plan.to, {
    surcharge = S.Option("surcharge"),
    stock = stock,
    auctionPrice = S.AuctionPrice,
  })
  plan.groups = R.Group(plan.lines)
  plan.total, plan.unpriced = R.Cost(plan.groups)
  plan.listName = R.ListName(plan.name, plan.from, plan.to)
  return plan
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
  local v1 = api()
  if not (v1 and type(v1.CreateShoppingList) == "function") then
    return "noApi"
  end
  local searches = R.Searches(plan.lines, S.Checked(plan.slug), converter(), clientName)
  if #searches == 0 then
    return "nothing"
  end
  local ok, err = pcall(v1.CreateShoppingList, R.CALLER, plan.listName, searches)
  if not ok then
    ns.Log.warn("list creation failed: %s", tostring(err))
    return "failed"
  end
  return "sent", #searches
end
