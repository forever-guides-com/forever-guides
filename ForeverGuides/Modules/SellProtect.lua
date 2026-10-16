-- Protect list of the sell helper (settings.sellProtect, comma separated item ids): adding and
-- removing, the suggestions for the input field and the management window built on
-- UI/ManageWindow.lua. Item names and icons come from the client, nothing is guessed: suggestions are
-- the bag and worn items, the profession tools of Data/ProfessionTools.lua, the item the client knows
-- by the exact name and a typed id (named when the client knows it).
local _, ns = ...
local Store, L, Logic = ns.Store, ns.L, ns.SellLogic
local Items, Info = ns.MacroItems, ns.ItemInfo

local P = {}
ns.SellProtect = P

ns.AddLocale("enUS", {
  ["sell.protect.title"] = "Protect list",
  ["sell.protect.desc"] = "Protected items are never sold, neither by the preview nor by the automatic sale.\nAdd items by name, ID or shift-click while the field has the focus.",
  ["sell.protect.placeholder"] = "Item name, ID or link",
  ["sell.protect.empty"] = "No protected items",
  ["sell.protect.count"] = "Protected items: %d",
  ["sell.protect.remove"] = "Remove from the list",
  ["sell.protect.id"] = "ID %d",
  ["sell.protect.full"] = "The protect list is full (%d items).",
})
ns.AddLocale("deDE", {
  ["sell.protect.title"] = "Schutzliste",
  ["sell.protect.desc"] = "Geschützte Items werden nie verkauft, weder von der Vorschau noch vom automatischen Verkauf.\nItems per Name, ID oder Shift-Klick hinzufügen, solange das Feld den Fokus hat.",
  ["sell.protect.placeholder"] = "Itemname, ID oder Link",
  ["sell.protect.empty"] = "Keine geschützten Items",
  ["sell.protect.count"] = "Geschützte Items: %d",
  ["sell.protect.remove"] = "Aus der Liste entfernen",
  ["sell.protect.id"] = "ID %d",
  ["sell.protect.full"] = "Die Schutzliste ist voll (%d Items).",
})

local MIN_NAME_CHARS = 2
local normalize = ns.MacroSpells.normalize

local function stored()
  return ns.db.settings.sellProtect or ""
end

function P.Ids()
  return Logic.ParseIds(stored())
end

function P.Count()
  return #P.Ids()
end

local function contains(list, id)
  for _, known in ipairs(list) do
    if known == id then
      return true
    end
  end
  return false
end

-- "added", "listed" (already on the list), "full" or "invalid" (no item id in `source`: a number,
-- an item link or "item:id").
function P.Add(source)
  local id = Logic.ItemId(source)
  if not Logic.ValidId(id) then
    return "invalid"
  end
  local list = P.Ids()
  if contains(list, id) then
    return "listed"
  end
  if #list >= Logic.MAX_PROTECT then
    ns.Notify(string.format(L["sell.protect.full"], Logic.MAX_PROTECT), "warning")
    return "full"
  end
  Store.set("settings.sellProtect", Logic.AddId(stored(), id))
  return "added"
end

function P.Remove(id)
  Store.set("settings.sellProtect", Logic.RemoveId(stored(), id))
end

-- Items ---------------------------------------------------------------------------------------

-- Asks the client for an item it has not cached yet, GET_ITEM_INFO_RECEIVED repaints the window.
local function request(id)
  local api = rawget(_G, "C_Item")
  if type(api) == "table" and type(api.RequestLoadItemDataByID) == "function" then
    pcall(api.RequestLoadItemDataByID, id)
  end
end

-- The quality colored name, "#id" while the client does not know the item.
local function title(id, name)
  name = name or Items.clientName(id)
  if not name then
    request(id)
    return "#" .. id
  end
  return Info.ColorName(name, Info.quality(id) or Items.quality(id))
end

local function describe(id, name)
  return { id = id, title = title(id, name), sub = string.format(L["sell.protect.id"], id), icon = Items.icon(id) }
end

-- A row of the list: the item tooltip shows on hover.
function P.Row(id)
  local row = describe(id)
  row.tooltipSpec = { link = "item:" .. id, title = row.title }
  return row
end

-- The entries newest first, so an added item shows at the top of the window.
function P.Display()
  local ids, out = P.Ids(), {}
  for i = #ids, 1, -1 do
    out[#out + 1] = ids[i]
  end
  return out
end

-- Suggestions ---------------------------------------------------------------------------------

-- The item id a text names: only digits, an item link or "item:id".
local function typedId(text)
  local id = text:match("^%d+$") and tonumber(text) or Logic.ItemId(text)
  return Logic.ValidId(id) and id or nil
end

-- The id of the item the client knows by exactly this name (when cached).
local function exactId(text)
  local api = rawget(_G, "C_Item")
  local get = type(api) == "table" and api.GetItemInfo or rawget(_G, "GetItemInfo")
  if type(get) ~= "function" then
    return nil
  end
  local ok, name, link = pcall(get, text)
  local id = ok and type(name) == "string" and Logic.ItemId(link) or nil
  return Logic.ValidId(id) and id or nil
end

-- 1 when a name starts with the needle, 2 when it only contains it, nil otherwise.
local function match(needle, ...)
  local best
  for i = 1, select("#", ...) do
    local name = select(i, ...)
    local at = type(name) == "string" and normalize(name):find(needle, 1, true)
    if at then
      best = math.min(best or 2, at == 1 and 1 or 2)
    end
  end
  return best
end

-- Up to `limit` entries { id, title, sub, icon } for the text of the input field, none for items that
-- are on the list already. A typed id or link names exactly that item; a name matches case
-- insensitive anywhere in the names of the client.
function P.Suggest(text, limit)
  local listed = {}
  for _, id in ipairs(P.Ids()) do
    listed[id] = true
  end
  local found, seen = {}, {}
  local function add(id, name, rank)
    if not (listed[id] or seen[id]) then
      seen[id] = true
      found[#found + 1] = { id = id, name = name, rank = rank, sort = normalize(name or "") }
    end
  end
  local id = typedId(text)
  if id then
    add(id, Items.clientName(id), 0)
  else
    local needle = normalize(text)
    if #needle >= MIN_NAME_CHARS then
      local exact = exactId(text)
      if exact then
        add(exact, Items.clientName(exact), 0)
      end
      for _, e in ipairs(Items.readers.bags()) do
        local rank = match(needle, e.name)
        if rank then
          add(e.id, e.name, rank)
        end
      end
      for _, tool in ipairs(ns.Data.ProfessionTools) do
        local own = Items.clientName(tool.id)
        local rank = match(needle, own, tool.name)
        if rank then
          add(tool.id, own or tool.name, rank)
        end
      end
    end
  end
  table.sort(found, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    elseif a.sort ~= b.sort then
      return a.sort < b.sort
    end
    return a.id < b.id
  end)
  local out = {}
  for i = 1, math.min(#found, limit or ns.ManageWindow.MAX_SUGGESTIONS) do
    out[i] = describe(found[i].id, found[i].name)
  end
  return out
end

-- Enter in the field: an id or a link is added, a name when it leaves exactly one suggestion. True
-- when the entry was dealt with.
function P.Submit(text)
  local id = typedId(text)
  if not id then
    local list = P.Suggest(text, 2)
    id = #list == 1 and list[1].id or nil
  end
  local status = id and P.Add(id)
  return status == "added" or status == "listed"
end

-- Window ---------------------------------------------------------------------------------------

local window

function P.Window()
  if not window then
    window = ns.ManageWindow.Create({
      name = "ForeverGuidesSellProtect",
      title = "sell.protect.title",
      description = "sell.protect.desc",
      placeholder = "sell.protect.placeholder",
      empty = "sell.protect.empty",
      count = "sell.protect.count",
      removeTip = "sell.protect.remove",
      items = P.Display,
      row = P.Row,
      suggest = P.Suggest,
      onPick = function(suggestion)
        P.Add(suggestion.id)
      end,
      onSubmit = P.Submit,
      onRemove = P.Remove,
    })
  end
  return window
end

function P.Open()
  P.Window():Open()
end

-- A shift-clicked item goes onto the list while the field of the window has the focus.
function P.InsertLink(link)
  if not (window and window:HasFocus()) then
    return false
  end
  P.Add(link)
  window:Settle()
  return true
end

-- Names arrive late: repaint the rows that showed "#id".
ns.On("GET_ITEM_INFO_RECEIVED", function()
  if window and window:IsShown() then
    ns.Debounce("sell-protect-names", 0.2, function()
      window:Refresh()
    end)
  end
end)
