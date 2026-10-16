-- Game side of the editable shopping list: the saved entry of the current character, adding items
-- (from the recipe page and from a shared list), changing the amount and the tick of a position,
-- removing one, removing the done ones and emptying the list. Route lines are computed from the
-- route, so their changes are stored as edits per item (ProfessionListLogic.lua); own positions are
-- stored as they are, the ticks of material rows (derived from a crafted item) per occurrence in
-- chr.ticks (PL.TickKey). Every change emits FG_PROFROUTE_CHANGED, the window and the panels repaint.
local _, ns = ...
local R, S, PL = ns.ProfessionRouteLogic, ns.ProfessionShop, ns.ProfessionListLogic

local M = {}
ns.ProfessionList = M

ns.AddLocale("enUS", {
  ["proflist.added"] = "Added to the shopping list: %s",
  ["proflist.raised"] = "%s: amount raised to %d",
  ["proflist.limit"] = "The shopping list is full (%d positions).",
  ["proflist.removed"] = "Removed: %s",
  ["proflist.removedDone"] = "Removed %d done positions.",
  ["proflist.cleared"] = "Shopping list emptied.",
  ["proflist.imported"] = "Shopping list: %d positions taken over.",
  ["proflist.itemName"] = "Item %d",
})
ns.AddLocale("deDE", {
  ["proflist.added"] = "Zur Einkaufsliste hinzugefügt: %s",
  ["proflist.raised"] = "%s: Menge auf %d erhöht",
  ["proflist.limit"] = "Die Einkaufsliste ist voll (%d Positionen).",
  ["proflist.removed"] = "Entfernt: %s",
  ["proflist.removedDone"] = "%d erledigte Positionen entfernt.",
  ["proflist.cleared"] = "Einkaufsliste geleert.",
  ["proflist.imported"] = "Einkaufsliste: %d Positionen übernommen.",
  ["proflist.itemName"] = "Item %d",
})

local function characterKey()
  local roster = ns.CharRoster
  return roster and roster.CurrentKey() or "?"
end

-- The saved entry of the current character, created clean when it is missing or damaged.
function M.Char()
  local list = S.Root().list
  local key = characterKey()
  local chr = list[key]
  if
    type(chr) ~= "table"
    or type(chr.items) ~= "table"
    or type(chr.edits) ~= "table"
    or type(chr.seq) ~= "number"
    or type(chr.ticks) ~= "table"
  then
    list[key] = PL.CleanChar(chr)
  end
  return list[key]
end

-- The saved ticks of the material rows of the current character, { [key] = true }.
function M.Ticks()
  return M.Char().ticks
end

local function changed(what)
  ns.Emit("FG_PROFROUTE_CHANGED", what)
end

-- Lines ---------------------------------------------------------------------------------------------

-- The data of the route of a profession when it is loaded, nil otherwise (nothing is loaded here).
local function routeItem(slug, id)
  local all = rawget(ns, "ProfessionData")
  local data = type(all) == "table" and slug and all[slug] or nil
  local items = type(data) == "table" and data.items or nil
  return type(items) == "table" and type(items[id]) == "table" and items[id] or nil
end

local function itemName(item)
  local fallback = string.format(ns.L["proflist.itemName"], item.id)
  return S.ClientName({ id = item.id, de = item.de, en = item.en, name = fallback })
end

local function itemSource(item)
  local info = routeItem(item.slug, item.id)
  local buy = info and info.buy
  for _, source in ipairs(R.GROUPS) do
    if source == buy then
      return source
    end
  end
  return R.DEFAULT_SOURCE
end

local function itemPrice(item, source)
  if source == "vendor" then
    local info = routeItem(item.slug, item.id)
    local price = info and tonumber(info.price)
    return price and price > 0 and price or nil
  elseif source == "auction" then
    return S.AuctionPrice(item.id)
  end
end

-- The route lines of one profession with the edits applied plus the own positions (S.Plan calls
-- this). Returns the lines and the number of removed route lines.
function M.Apply(slug, lines)
  local chr = M.Char()
  return PL.Apply(lines, {
    slug = slug,
    edits = chr.edits[slug],
    items = chr.items,
    name = itemName,
    source = itemSource,
    price = itemPrice,
  })
end

-- The icon of a line: the data icon (name), else the one the client knows.
function M.Icon(line)
  local icon = line.icon
  if type(icon) == "string" and icon ~= "" then
    return "Interface\\Icons\\" .. icon
  end
  local item = rawget(_G, "C_Item")
  local get = type(item) == "table" and item.GetItemIconByID or rawget(_G, "GetItemIcon")
  if type(get) == "function" then
    local ok, found = pcall(get, line.id)
    if ok and (type(found) == "number" or type(found) == "string") then
      return found
    end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Changes -----------------------------------------------------------------------------------------------

-- The line of a route in the plan of the chosen profession, nil when the item is not one of them.
local function routeLine(id)
  for _, line in ipairs(S.Plan().all or {}) do
    if line.id == id and not line.own and not line.derived then
      return line
    end
  end
end

-- Adds an item. entry: { id, slug, de, en, icon }. An own position of the same item is raised, so is
-- the route line of it, anything else becomes a new own position. Returns "added" | "raised", the new
-- amount and the name, or nil and "limit" | "invalid". With buy = true the item is bought finished at
-- the auction house instead of crafted (the choice of the item, shared by every list window).
function M.Add(entry, qty, buy)
  local id = type(entry) == "table" and PL.Id(entry.id)
  if not id then
    return nil, "invalid"
  end
  qty = PL.Qty(qty) or 1
  local chr = M.Char()
  local line = not PL.Find(chr, id) and routeLine(id)
  if line then
    local edit = PL.Edit(chr, line.slug, id)
    edit.qty = math.min(line.need + qty, PL.MAX_QTY)
    changed("add")
    if buy then
      S.SetCraftChoice(id, "auction")
    end
    return "raised", edit.qty, line.name
  end
  local item, status = PL.AddItem(chr, entry, qty)
  if not item then
    return nil, status
  end
  changed("add")
  if buy then
    S.SetCraftChoice(id, "auction")
  end
  return status, item.qty, itemName(item)
end

-- Add from a page: the same, and the answer as a notification. Returns what Add returned.
function M.AddFromPage(entry, qty, buy)
  local status, amount, name = M.Add(entry, qty, buy)
  if status == "added" then
    ns.Notify(string.format(ns.L["proflist.added"], name), "success")
  elseif status == "raised" then
    ns.Notify(string.format(ns.L["proflist.raised"], name, amount), "success")
  elseif amount == "limit" then
    ns.Notify(string.format(ns.L["proflist.limit"], PL.MAX_ITEMS), "warning")
  end
  return status, amount, name
end

-- Calls fn for every position behind a line: the parts of a merged line, else the line itself.
local function eachPart(line, fn)
  for _, part in ipairs(line.parts or { line }) do
    fn(part)
  end
end

-- The amount to buy of a line (a whole number PL.MinQty..MAX_QTY, anything else changes nothing). What is
-- saved is the target: with the stock subtracted it is what is there plus the amount, so the need of the
-- row (the denominator) follows the amount by exactly the step and buying brings the row closer to its
-- target instead of moving it. A merged line (the same item from several origins) has no single amount to
-- change, the "by reason" view edits the positions, nor has a derived one (the materials of an item crafted
-- yourself). Returns the amount now in effect.
function M.SetQty(line, qty)
  if type(line) ~= "table" then
    return nil
  end
  local deduct = S.Option("stock") and true or false
  qty = PL.BuyQty(qty, PL.MinQty(line, deduct))
  if not qty or line.parts or line.derived then
    return line.qty
  end
  local have = deduct and line.have or 0
  local need = math.min(have + qty, PL.MAX_QTY)
  local chr = M.Char()
  if line.own then
    local item = PL.Find(chr, line.id)
    if item then
      item.qty = need
    end
  else
    PL.Edit(chr, line.slug, line.id).qty = need ~= line.base and need or nil
    PL.Tidy(chr, line.slug, line.id)
  end
  changed("qty")
  return need - have
end

-- One position to ticked or not: a route line has its tick per item and profession, an own position its
-- flag, a material row the tick of its own occurrence (so the same material under another reason is not
-- touched).
local function setPart(part, on)
  if part.own then
    local item = PL.Find(M.Char(), part.id)
    if item then
      item.done = on
    end
  elseif part.derived then
    PL.SetTick(M.Char(), part.key, on)
  else
    S.Checked(part.slug)[part.id] = on or nil
  end
end

-- Done or not done. members: the lines below a group head (PL.View head.members, all levels, also the ones
-- a search hides): they follow the head, ticked and unticked alike. A single row never changes the row
-- above it, so a head stays as it is when its materials are ticked one by one.
function M.SetDone(line, on, members)
  if type(line) ~= "table" then
    return
  end
  on = on == true
  eachPart(line, function(part)
    setPart(part, on)
  end)
  for _, member in ipairs(members or {}) do
    eachPart(member, function(part)
      setPart(part, on)
    end)
  end
  changed("done")
end

-- True when something was removed or hidden. A material row goes away with the item it comes from.
local function drop(chr, line)
  if line.derived then
    return false
  end
  if line.own then
    local _, index = PL.Find(chr, line.id)
    if not index then
      return false
    end
    table.remove(chr.items, index)
    PL.DropTicks(chr, line.id)
    return true
  end
  PL.Edit(chr, line.slug, line.id).hidden = true
  return true
end

-- Removes a position: an own one is deleted, a route line is hidden.
function M.Remove(line)
  if type(line) ~= "table" then
    return false
  end
  local chr = M.Char()
  eachPart(line, function(part)
    drop(chr, part)
  end)
  changed("remove")
  ns.Notify(string.format(ns.L["proflist.removed"], line.name or tostring(line.id)), "info")
  return true
end

-- Removes every position that is done: ticked, or covered by the stock while it is subtracted.
-- Returns how many went.
function M.RemoveDone(plan)
  local chr, checked, count = M.Char(), S.Checked(plan.slug), 0
  for _, line in ipairs(plan.all or plan.lines or {}) do
    if PL.Done(line, checked, plan.deduct) and drop(chr, line) then
      count = count + 1
    end
  end
  if count > 0 then
    changed("remove")
    ns.Notify(string.format(ns.L["proflist.removedDone"], count), "info")
  end
  return count
end

-- Empties the list: every own position goes, the route lines of the plan are hidden.
function M.Clear(plan)
  local chr = M.Char()
  for _, item in ipairs(chr.items) do
    PL.DropTicks(chr, item.id)
  end
  chr.items = {}
  for _, line in ipairs(plan and (plan.all or plan.lines) or {}) do
    if not line.own then
      drop(chr, line)
    end
  end
  changed("clear")
  ns.Notify(ns.L["proflist.cleared"], "info")
end

-- Takes every tick back: the ticks of the route lines of a profession, the flags of the own positions and
-- the ticks of their materials.
function M.ClearTicks(slug)
  local chr = M.Char()
  for _, item in ipairs(chr.items) do
    item.done = false
  end
  PL.ClearTicks(chr, slug)
  S.ClearChecked(slug)
end

-- How many route lines of a profession are removed or changed.
function M.EditCount(slug)
  local n = 0
  for _ in pairs(M.Char().edits[slug] or {}) do
    n = n + 1
  end
  return n
end

-- Takes back every change to the route lines of a profession (removed, amount).
function M.ResetEdits(slug)
  M.Char().edits[slug] = nil
  changed("reset")
end

-- Takes over positions of a shared list as own positions (all open). Returns the number taken over.
function M.Import(positions)
  local chr, count = M.Char(), 0
  for _, p in ipairs(positions or {}) do
    if PL.AddItem(chr, { id = p.id, slug = p.slug }, p.qty) then
      count = count + 1
    end
  end
  if count > 0 then
    changed("import")
  end
  return count
end
