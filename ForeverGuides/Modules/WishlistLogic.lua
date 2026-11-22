-- Wishlist of one character: the items the player wants (ForeverGuidesCharDB.wishlist = { v = 1, seq = n,
-- items = { [itemId] = order of adding } }). Pure rules: add, remove, toggle, "obtained" (in bags, bank or worn),
-- where an item comes from (instance loot, recipes, vendors) and the grouping of the page. The stars on the item
-- rows are Modules/WishlistStar.lua, the page is Modules/WishlistPage.lua.
local _, ns = ...

local WL = {}
ns.Wishlist = WL

WL.MAX = 300
WL.MODES = { "instance", "slot" }
local MAX_ID = 1e8
local RECIPE_CLASS = 9

ns.AddLocale("enUS", {
  ["wish.star"] = "Wishlist",
  ["wish.star.tip"] = "Adds this item to your wishlist or takes it off again.",
  ["wish.add"] = "Add to wishlist",
  ["wish.remove"] = "Remove from wishlist",
  ["wish.onList"] = "On your wishlist",
  ["wish.full"] = "Your wishlist is full (%d items).",
  ["wish.group.none"] = "Source not known",
  ["wish.group.vendor"] = "Vendors",
  ["wish.slot.other"] = "Other",
  ["wish.src.boss"] = "%s in %s",
  ["wish.src.craft"] = "Crafted with %s",
  ["wish.src.craftSkill"] = "Crafted with %s (skill %d)",
  ["wish.src.vendor"] = "Sold by %s",
  ["wish.src.none"] = "Source not known",
})
ns.AddLocale("deDE", {
  ["wish.star"] = "Wunschliste",
  ["wish.star.tip"] = "Setzt diesen Gegenstand auf deine Wunschliste oder nimmt ihn wieder herunter.",
  ["wish.add"] = "Auf die Wunschliste",
  ["wish.remove"] = "Von der Wunschliste nehmen",
  ["wish.onList"] = "Auf deiner Wunschliste",
  ["wish.full"] = "Deine Wunschliste ist voll (%d Gegenstände).",
  ["wish.group.none"] = "Quelle unbekannt",
  ["wish.group.vendor"] = "Händler",
  ["wish.slot.other"] = "Sonstiges",
  ["wish.src.boss"] = "%s in %s",
  ["wish.src.craft"] = "Herstellbar mit %s",
  ["wish.src.craftSkill"] = "Herstellbar mit %s (Skill %d)",
  ["wish.src.vendor"] = "Verkauft von %s",
  ["wish.src.none"] = "Quelle unbekannt",
})

local function whole(v)
  return type(v) == "number" and v >= 1 and v <= MAX_ID and v == math.floor(v) and v or nil
end

-- The stored table; create = true makes it (and repairs a wrong type), else nil when there is none.
local function store(create)
  local db = ns.charDB
  if type(db) ~= "table" then
    return nil
  end
  local w = db.wishlist
  if type(w) ~= "table" then
    if not create then
      return nil
    end
    w = { v = 1, seq = 0, items = {} }
    db.wishlist = w
  end
  if type(w.items) ~= "table" then
    if not create then
      return nil
    end
    w.items = {}
  end
  return w
end

function WL.Has(id)
  id = whole(tonumber(id))
  local w = id and store(false)
  return w ~= nil and w.items[id] ~= nil
end

function WL.Count()
  local w = store(false)
  local n = 0
  for _ in pairs(w and w.items or {}) do
    n = n + 1
  end
  return n
end

local function changed(id, on)
  if ns.Emit then
    ns.Emit("FG_WISHLIST_CHANGED", id, on)
  end
end

-- true when the item is on the list afterwards; false and "full" / "id" when it could not be added.
function WL.Add(id)
  id = whole(tonumber(id))
  if not id then
    return false, "id"
  end
  local w = store(true)
  if w.items[id] then
    return true
  end
  if WL.Count() >= WL.MAX then
    return false, "full"
  end
  w.seq = (tonumber(w.seq) or 0) + 1
  w.items[id] = w.seq
  changed(id, true)
  return true
end

function WL.Remove(id)
  id = whole(tonumber(id))
  local w = id and store(false)
  if w and w.items[id] then
    w.items[id] = nil
    changed(id, false)
    return true
  end
  return false
end

-- The new state (true = on the list); a full list says so in a notification.
function WL.Toggle(id)
  if WL.Has(id) then
    WL.Remove(id)
    return false
  end
  local ok, why = WL.Add(id)
  if not ok and why == "full" and ns.Notify then
    ns.Notify(string.format(ns.L["wish.full"], WL.MAX), "warning")
  end
  return ok
end

-- { { id, order } } in the order the items were added.
function WL.List()
  local w = store(false)
  local out = {}
  for id, order in pairs(w and w.items or {}) do
    if whole(id) then
      out[#out + 1] = { id = id, order = tonumber(order) or 0 }
    end
  end
  table.sort(out, function(a, b)
    if a.order ~= b.order then
      return a.order < b.order
    end
    return a.id < b.id
  end)
  return out
end

-- Obtained: in the bags or the bank, or worn. Both APIs are read through pcall; unknown API = not obtained.
function WL.Obtained(id)
  id = whole(tonumber(id))
  if not id then
    return false
  end
  local item = rawget(_G, "C_Item")
  item = type(item) == "table" and item or {}
  local count = rawget(_G, "GetItemCount") or item.GetItemCount
  if type(count) == "function" then
    local ok, n = pcall(count, id, true)
    if ok and type(n) == "number" and n > 0 then
      return true
    end
  end
  local worn = item.IsEquippedItem or rawget(_G, "IsEquippedItem")
  if type(worn) == "function" then
    local ok, on = pcall(worn, id)
    return ok and on == true
  end
  return false
end

-- Slot, type and the recipe class of an item from the client's static item data, nil while it is not known.
function WL.Info(id)
  local item = rawget(_G, "C_Item")
  local api = type(item) == "table" and item.GetItemInfoInstant or rawget(_G, "GetItemInfoInstant")
  if type(api) ~= "function" then
    return nil
  end
  local ok, _, itemType, _, equipLoc, _, classId = pcall(api, id)
  if not ok then
    return nil
  end
  local slot = type(equipLoc) == "string" and equipLoc ~= "" and rawget(_G, equipLoc) or nil
  return {
    slot = type(slot) == "string" and slot ~= "" and slot or nil,
    type = type(itemType) == "string" and itemType ~= "" and itemType or nil,
    class = classId,
  }
end

-- The label an item is grouped under when grouping by slot.
function WL.SlotLabel(id)
  local info = WL.Info(id)
  return info and (info.slot or info.type) or ns.L["wish.slot.other"]
end

-- Recipe patterns, plans and formulas. The recipe data names the pattern items of every recipe (r.pat); it is
-- read when it is loaded already (loading it here would cost a data package for a view of loot). The item class
-- of the client covers the rest.
local patterns, patternsFrom
local function patternSet()
  local all = rawget(ns, "RecipeData")
  if type(all) ~= "table" then
    return nil
  end
  if patterns and patternsFrom == all then
    return patterns
  end
  local set = {}
  for _, data in pairs(all) do
    for _, r in ipairs(type(data) == "table" and type(data.list) == "table" and data.list or {}) do
      for _, id in ipairs(type(r) == "table" and type(r.pat) == "table" and r.pat or {}) do
        if type(id) == "number" then
          set[id] = true
        end
      end
    end
  end
  patterns, patternsFrom = set, all
  return set
end

function WL.IsRecipe(id)
  local set = patternSet()
  if set and set[id] then
    return true
  end
  local info = WL.Info(id)
  return info ~= nil and info.class == RECIPE_CLASS
end

-- Sources -----------------------------------------------------------------------------------------------

local function bossNames(row)
  local names = {}
  for _, b in ipairs(row.bosses) do
    names[#names + 1] = b.name
  end
  return table.concat(names, ", ")
end

-- Where an item comes from: { kind, group, text, route, place }. instance: boss loot of the instance data;
-- craft: a recipe of a profession; vendor: the best seller. Every lookup is optional and read through pcall, a
-- missing data package leaves the kind out.
function WL.Sources(id)
  local out = {}
  local R = ns.RefLogic
  local ok, rows = pcall(function()
    return ns.ItemSource and ns.ItemSource.Rows(id)
  end)
  for _, row in ipairs(ok and rows or {}) do
    local slug = row.inst and R and R.InstanceSlug(row.inst)
    out[#out + 1] = {
      kind = "instance",
      group = row.instance,
      text = row.noBoss and row.instance or string.format(ns.L["wish.src.boss"], bossNames(row), row.instance),
      route = slug and ("instances/" .. slug .. "/items") or nil,
    }
  end
  local made
  ok, made = pcall(function()
    return ns.RecipeAccess and ns.RecipeAccess.Producers(id)
  end)
  local first = ok and made and made[1]
  if first then
    local profession = ns.ProfessionRouteLogic and ns.ProfessionRouteLogic.Name(first.slug) or first.slug
    local level = ns.RecipeLogic and ns.RecipeLogic.Level(first.recipe)
    out[#out + 1] = {
      kind = "craft",
      group = profession,
      text = level and level < math.huge and string.format(ns.L["wish.src.craftSkill"], profession, level)
        or string.format(ns.L["wish.src.craft"], profession),
      route = "professions/" .. first.slug .. "/" .. first.recipe.s,
    }
  end
  local best
  ok, best = pcall(function()
    return ns.VendorSource and ns.VendorSource.Best(id, true)
  end)
  if ok and best and best.seller and best.seller.vendor then
    out[#out + 1] = {
      kind = "vendor",
      group = ns.L["wish.group.vendor"],
      text = string.format(ns.L["wish.src.vendor"], best.seller.vendor.name),
      place = best.place,
      npc = best.seller.vendor.npc,
    }
  end
  return out
end

-- The entries of the page: the list with name, quality, icon, slot, sources and the obtained flag.
function WL.Entries()
  local IV = ns.InstanceView
  local out = {}
  for _, row in ipairs(WL.List()) do
    local id = row.id
    local sources = WL.Sources(id)
    out[#out + 1] = {
      id = id,
      order = row.order,
      name = IV and IV.ItemName({ id = id }) or ("#" .. id),
      quality = IV and IV.ItemQuality(id),
      icon = IV and IV.ItemIcon(id),
      kind = ns.InstanceLootRow and ns.InstanceLootRow.Kind(id),
      slotLabel = WL.SlotLabel(id),
      sources = sources,
      group = sources[1] and sources[1].group or nil,
      obtained = WL.Obtained(id),
    }
  end
  return out
end

-- Groups for the page. mode "instance": by the first source (instance, profession or vendors), items without a
-- source last; mode "slot": by equipment slot or item type, "Other" last. Not obtained items come first in a
-- group, then by name.
function WL.Group(entries, mode)
  local bySlot = mode == "slot"
  local none = bySlot and ns.L["wish.slot.other"] or ns.L["wish.group.none"]
  local fold = ns.SearchLogic and ns.SearchLogic.fold or string.lower
  local groups, map = {}, {}
  for _, e in ipairs(entries) do
    local label = bySlot and e.slotLabel or (not bySlot and e.group) or none
    local g = map[label]
    if not g then
      g = { label = label, entries = {} }
      map[label] = g
      groups[#groups + 1] = g
    end
    g.entries[#g.entries + 1] = e
  end
  for _, g in ipairs(groups) do
    table.sort(g.entries, function(a, b)
      if a.obtained ~= b.obtained then
        return not a.obtained
      end
      local na, nb = fold(a.name or ""), fold(b.name or "")
      if na ~= nb then
        return na < nb
      end
      return a.id < b.id
    end)
  end
  table.sort(groups, function(a, b)
    if (a.label == none) ~= (b.label == none) then
      return b.label == none
    end
    return fold(a.label) < fold(b.label)
  end)
  return groups
end

-- The tooltip line of an item on the list, nil otherwise.
function WL.TooltipLine(id)
  return WL.Has(id) and ns.L["wish.onList"] or nil
end

-- Search entries: the items of the list under their names (a name the client does not know yet is skipped).
ns.AddLocale("enUS", { ["search.kind.wishitem"] = "Wishlist item" })
ns.AddLocale("deDE", { ["search.kind.wishitem"] = "Wunschlisten-Gegenstand" })

ns.SearchLogic.RegisterSource("wishitem", function(add)
  local IV = ns.InstanceView
  for _, row in ipairs(WL.List()) do
    local name = IV and IV.ItemName({ id = row.id })
    if name and name ~= "#" .. row.id then
      add(name, ns.L["wish.onList"], "wishlist")
    end
  end
end)

ns.On("FG_WISHLIST_CHANGED", function()
  ns.SearchLogic.ResetIndex()
end)

return WL
