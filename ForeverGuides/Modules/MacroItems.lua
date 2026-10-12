-- Item search for the macro editor. It only reads what the addon holds already: the bags and worn items
-- of the character (game API, every call in pcall), the loot the player recorded (ns.LootCapture) and
-- the items of the recipe data (reagents and crafted items). Nothing is downloaded or guessed: an
-- item that is in none of them can still be chosen by its ID. Rows: { id, name, quality, sources }.
local _, ns = ...
local S = ns.MacroSpells

local I = {}
ns.MacroItems = I

I.SOURCES = { "bags", "loot", "recipes" }
I.LIMIT = 200
I.MAX_ID = 9999999
local EQUIP_SLOTS = 19
local BAGS = { 0, 1, 2, 3, 4 }

local function readable(v)
  return ns.ItemInfo.readable(v)
end

local function nonEmpty(v)
  return type(v) == "string" and v ~= "" and v or nil
end

-- Client side ------------------------------------------------------------------------------------

-- Name of an item in the client language, nil while the client has not loaded the item.
function I.clientName(id)
  if C_Item and C_Item.GetItemNameByID then
    local ok, name = pcall(C_Item.GetItemNameByID, id)
    if ok and nonEmpty(name) then
      return name
    end
  end
  if GetItemInfo then
    local ok, name = pcall(GetItemInfo, id)
    if ok and nonEmpty(name) then
      return name
    end
  end
end

function I.quality(id)
  if C_Item and C_Item.GetItemQualityByID then
    local ok, quality = pcall(C_Item.GetItemQualityByID, id)
    if ok and readable(quality) then
      return quality
    end
  end
end

function I.icon(id)
  if C_Item and C_Item.GetItemIconByID then
    local ok, icon = pcall(C_Item.GetItemIconByID, id)
    if ok and icon then
      return icon
    end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Readers: each gives a list of { id, name = text or { de, en }, quality }. Tests replace them.
I.readers = {}

local function bagItemIds()
  local ids = {}
  local container = rawget(_G, "C_Container")
  if type(container) == "table" and container.GetContainerNumSlots and container.GetContainerItemInfo then
    for _, bag in ipairs(BAGS) do
      local okSlots, slots = pcall(container.GetContainerNumSlots, bag)
      for slot = 1, okSlots and readable(slots) and math.min(slots, 200) or 0 do
        local okInfo, info = pcall(container.GetContainerItemInfo, bag, slot)
        if okInfo and type(info) == "table" and readable(info.itemID) then
          ids[#ids + 1] = info.itemID
        end
      end
    end
  end
  local worn = rawget(_G, "GetInventoryItemID")
  if type(worn) == "function" then
    for slot = 1, EQUIP_SLOTS do
      local ok, id = pcall(worn, "player", slot)
      if ok and readable(id) then
        ids[#ids + 1] = id
      end
    end
  end
  return ids
end

function I.readers.bags()
  local out = {}
  for _, id in ipairs(bagItemIds()) do
    out[#out + 1] = { id = id, name = I.clientName(id), quality = I.quality(id) }
  end
  return out
end

function I.readers.loot()
  local out = {}
  local capture = rawget(ns, "LootCapture")
  if not capture then
    return out
  end
  for _, boss in ipairs(capture.Bosses()) do
    for id, it in pairs(boss.e.items) do
      out[#out + 1] = { id = id, name = nonEmpty(it.name) or I.clientName(id), quality = it.q }
    end
  end
  return out
end

-- Recipe items by id; a crafted item without a German name in the item list takes the one of the
-- recipe that makes it under the same English name. Read once per session.
local recipeCache

function I.readers.recipes()
  if recipeCache then
    return recipeCache
  end
  local out = {}
  local access, routes = rawget(ns, "RecipeAccess"), rawget(ns, "ProfessionRouteLogic")
  if not (access and routes) then
    return out
  end
  -- Loading the data package stops the client for a moment: not in combat.
  local inCombat = rawget(_G, "InCombatLockdown")
  if not rawget(ns, "RecipeData") and type(inCombat) == "function" and inCombat() then
    return out
  end
  local names = {}
  local function note(id, de, en)
    if type(id) ~= "number" then
      return
    end
    local n = names[id]
    if not n then
      n = {}
      names[id] = n
    end
    n.de, n.en = n.de or nonEmpty(de), n.en or nonEmpty(en)
  end
  local found = false
  for _, slug in ipairs(routes.SLUGS) do
    local data, list = access.Get(slug)
    if data then
      found = true
      for id, row in pairs(type(data.items) == "table" and data.items or {}) do
        note(id, type(row) == "table" and row.de, type(row) == "table" and row.en)
      end
      for _, r in ipairs(list) do
        if type(r.i) == "number" and not r.rm then
          local n = names[r.i]
          local de, en = r.n[1], r.n[2]
          if n and n.en and n.en == en and not n.de and de ~= en then
            n.de = nonEmpty(de)
          end
          note(r.i, de, en)
        end
      end
    end
  end
  for id, n in pairs(names) do
    if n.de or n.en then
      out[#out + 1] = { id = id, name = n }
    end
  end
  if found then
    recipeCache = out
  end
  return out
end

-- Catalog ----------------------------------------------------------------------------------------

local catalog

-- Forgets the catalog, so the next search reads the bags and the loot again. The recipe items stay
-- unless `recipes` is true (a changed data package, tests).
function I.Reset(recipes)
  catalog = nil
  if recipes then
    recipeCache = nil
  end
end

if ns.On then
  ns.On("FG_PACKAGE_CHANGED", function()
    I.Reset(true)
  end)
end

local function displayName(name)
  if type(name) == "table" then
    return nonEmpty(ns.T(name))
  end
  return nonEmpty(name)
end

local function build()
  local byId, list = {}, {}
  for _, source in ipairs(I.SOURCES) do
    for _, e in ipairs(I.readers[source]()) do
      if type(e.id) == "number" and e.id >= 1 and e.id <= I.MAX_ID and e.id == math.floor(e.id) then
        local row = byId[e.id]
        if not row then
          row = { id = e.id, keys = {}, sources = {} }
          byId[e.id] = row
          list[#list + 1] = row
        end
        row.sources[source] = true
        row.quality = row.quality or e.quality
        row.name = row.name or displayName(e.name)
        local texts = type(e.name) == "table" and { e.name.de or "", e.name.en or "" } or { e.name or "" }
        for _, text in ipairs(texts) do
          local key = S.normalize(text)
          if key ~= "" then
            row.keys[#row.keys + 1] = key
          end
        end
      end
    end
  end
  return { byId = byId, list = list }
end

local function catalogNow()
  if not catalog then
    catalog = build()
  end
  return catalog
end

-- The ID a query names: "6948", "item:6948" or an item link; nil for text.
function I.queryId(query)
  local digits = (query or ""):match("^%s*(%d+)%s*$") or (query or ""):match("[Ii]tem:(%d+)")
  local id = digits and tonumber(digits)
  return id and id >= 1 and id <= I.MAX_ID and id or nil
end

local function rowFor(entry)
  local sources = {}
  for _, source in ipairs(I.SOURCES) do
    if entry.sources[source] then
      sources[#sources + 1] = source
    end
  end
  return {
    id = entry.id,
    name = entry.name or ns.L["macros.items.unnamed"]:format(entry.id),
    quality = entry.quality,
    sources = sources,
  }
end

-- Rows for the picker. A name matches in both languages (accents and case do not matter), a number
-- matches the start of an ID. Exact hits come first, then what the character owns, then the name.
-- A whole ID that no source knows still gets a row (sources = {}), so any item can be chosen.
function I.search(query, opts)
  opts = opts or {}
  local limit = opts.limit or I.LIMIT
  local cat = catalogNow()
  local id = I.queryId(query)
  local text = S.normalize(query or "")
  local hits = {}
  for _, entry in ipairs(cat.list) do
    local ok = text == ""
    if id then
      ok = tostring(entry.id):find("^" .. id) ~= nil
    elseif not ok then
      for _, key in ipairs(entry.keys) do
        if key:find(text, 1, true) then
          ok = true
          break
        end
      end
    end
    if ok then
      local row = rowFor(entry)
      local exact = entry.id == id
      for _, key in ipairs(entry.keys) do
        exact = exact or key == text
      end
      row.rank = (exact and 0 or 4) + (entry.sources.bags and 0 or 2) + (entry.sources.loot and 0 or 1)
      row.sort = S.normalize(row.name)
      hits[#hits + 1] = row
    end
  end
  if id and not cat.byId[id] then
    hits[#hits + 1] = {
      id = id,
      name = I.clientName(id) or ns.L["macros.items.unnamed"]:format(id),
      quality = I.quality(id),
      sources = {},
      rank = -1,
      sort = "",
    }
  end
  table.sort(hits, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    elseif a.sort ~= b.sort then
      return a.sort < b.sort
    end
    return a.id < b.id
  end)
  for i = #hits, limit + 1, -1 do
    hits[i] = nil
  end
  return hits
end

-- Label of a row for buttons and lists: "Name (ID)".
function I.label(row)
  return string.format("%s (%d)", row.name, row.id)
end
