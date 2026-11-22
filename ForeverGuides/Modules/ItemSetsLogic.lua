-- Pure logic of the page "Item sets" (ItemSetsPage.lua): which class a set is for, the filters, the progress
-- of the player (equipped, owned, missing), the active set bonuses and the descriptors of piece sources.
-- Free of game API: the page hands in what the client knows. Data shape: docs/ITEMSETS-FORMAT.md.
local _, ns = ...

local IL = {}
ns.ItemSetsLogic = IL

IL.CATEGORIES = { "raid", "dungeon", "pvp", "crafted", "world" }
IL.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
-- Armor class a class wears at the maximum level: a set without a class restriction is listed for it.
IL.ARMOR_OF = {
  WARRIOR = "plate",
  PALADIN = "plate",
  HUNTER = "mail",
  SHAMAN = "mail",
  ROGUE = "leather",
  DRUID = "leather",
  PRIEST = "cloth",
  MAGE = "cloth",
  WARLOCK = "cloth",
}
-- INVTYPE global of the inventory type numbers of the item tables (the client names the slot).
IL.SLOT_GLOBAL = {
  [1] = "INVTYPE_HEAD",
  [2] = "INVTYPE_NECK",
  [3] = "INVTYPE_SHOULDER",
  [4] = "INVTYPE_BODY",
  [5] = "INVTYPE_CHEST",
  [6] = "INVTYPE_WAIST",
  [7] = "INVTYPE_LEGS",
  [8] = "INVTYPE_FEET",
  [9] = "INVTYPE_WRIST",
  [10] = "INVTYPE_HAND",
  [11] = "INVTYPE_FINGER",
  [12] = "INVTYPE_TRINKET",
  [13] = "INVTYPE_WEAPON",
  [14] = "INVTYPE_SHIELD",
  [15] = "INVTYPE_RANGED",
  [16] = "INVTYPE_CLOAK",
  [17] = "INVTYPE_2HWEAPON",
  [19] = "INVTYPE_TABARD",
  [20] = "INVTYPE_ROBE",
  [21] = "INVTYPE_WEAPONMAINHAND",
  [22] = "INVTYPE_WEAPONOFFHAND",
  [23] = "INVTYPE_HOLDABLE",
  [25] = "INVTYPE_THROWN",
  [26] = "INVTYPE_RANGEDRIGHT",
}
-- Display order of the slots in a piece list: head down to the weapons.
local SLOT_ORDER = { 1, 2, 3, 16, 5, 20, 4, 9, 10, 6, 7, 8, 11, 12, 21, 13, 17, 22, 14, 23, 15, 26, 25, 19 }
local SLOT_RANK = {}
for rank, slot in ipairs(SLOT_ORDER) do
  SLOT_RANK[slot] = rank
end

-- Data check: a loaded table of the current schema with at least one set.
function IL.IsValid(data)
  return type(data) == "table" and data.v == 1 and type(data.sections) == "table"
end

function IL.IsForever(section)
  return section.fv == true
end

-- True when the class belongs to the set: it is named by the set, or the set has no restriction and the class
-- wears its armor class. Sets without an armor class (weapons, jewelry) belong to every class.
function IL.ForClass(section, class)
  if class == nil or class == "all" then
    return true
  end
  if type(section.cls) == "table" and #section.cls > 0 then
    for _, token in ipairs(section.cls) do
      if token == class then
        return true
      end
    end
    return false
  end
  return section.at == nil or section.at == IL.ARMOR_OF[class]
end

-- Category filter: "all", a category of IL.CATEGORIES, or "forever" (sets that only exist in Forever).
function IL.InCategory(section, category)
  if category == nil or category == "all" then
    return true
  end
  if category == "forever" then
    return IL.IsForever(section)
  end
  return section.cat == category
end

-- Names of the set and its pieces in both languages, as one search text.
function IL.Haystack(section)
  local parts = { section.title and section.title.de, section.title and section.title.en }
  for _, piece in ipairs(section.i or {}) do
    if piece.n then
      parts[#parts + 1] = piece.n.de
      parts[#parts + 1] = piece.n.en
    end
  end
  return table.concat(parts, " ")
end

-- f: class, category, query, words(query) and match(text, word) (the folded search of the add-on, plain by
-- default), progress (true: only sets of which the player owns a piece), counts[section.id] = Progress(...).
function IL.Filter(sections, f)
  local words = f.words and f.words(f.query)
  if not words then
    words = {}
    for word in tostring(f.query or ""):gmatch("%S+") do
      words[#words + 1] = word
    end
  end
  local match = f.match or function(text, word)
    return text:lower():find(word:lower(), 1, true) ~= nil
  end
  local out = {}
  for _, s in ipairs(sections) do
    local ok = IL.ForClass(s, f.class) and IL.InCategory(s, f.category)
    if ok and f.progress then
      local c = f.counts and f.counts[s.id]
      ok = c ~= nil and c.owned > 0
    end
    if ok and #words > 0 then
      local text = IL.Haystack(s)
      for _, word in ipairs(words) do
        if not match(text, word) then
          ok = false
          break
        end
      end
    end
    if ok then
      out[#out + 1] = s
    end
  end
  return out
end

-- Sets with progress first (most pieces first), then by required level and name. nameOf(section) is the name
-- in the language of the player.
function IL.Sort(sections, counts, nameOf)
  local list = {}
  for i, s in ipairs(sections) do
    list[i] = s
  end
  local function owned(s)
    local c = counts and counts[s.id]
    return c and c.owned or 0
  end
  table.sort(list, function(a, b)
    local oa, ob = owned(a), owned(b)
    if oa ~= ob then
      return oa > ob
    end
    local la, lb = a.lv or 0, b.lv or 0
    if la ~= lb then
      return la < lb
    end
    local na, nb = nameOf(a), nameOf(b)
    if na ~= nb then
      return na < nb
    end
    return a.sid < b.sid
  end)
  return list
end

-- Pieces in slot order (head first), the data order within a slot.
function IL.SortedPieces(section)
  local list = {}
  for i, p in ipairs(section.i or {}) do
    list[i] = { piece = p, index = i }
  end
  table.sort(list, function(a, b)
    local ra, rb = SLOT_RANK[a.piece.sl] or 99, SLOT_RANK[b.piece.sl] or 99
    if ra ~= rb then
      return ra < rb
    end
    return a.index < b.index
  end)
  local out = {}
  for i, e in ipairs(list) do
    out[i] = e.piece
  end
  return out
end

-- Progress of the player. stateOf(itemId) is "equipped", "owned" (bags or bank) or nil. Returns
-- { total, owned, equipped, states = { [itemId] = state } } with owned counting the equipped pieces too.
function IL.Progress(section, stateOf)
  local p = { total = #(section.i or {}), owned = 0, equipped = 0, states = {} }
  for _, piece in ipairs(section.i or {}) do
    local state = stateOf(piece.id)
    if state == "equipped" or state == "owned" then
      p.states[piece.id] = state
      p.owned = p.owned + 1
      if state == "equipped" then
        p.equipped = p.equipped + 1
      end
    end
  end
  return p
end

-- The bonuses of a set with their state: active while enough pieces are worn, reachable while enough are owned.
function IL.Bonuses(section, progress)
  local out = {}
  for i, b in ipairs(section.b or {}) do
    out[i] = {
      n = b.n,
      spell = b.s,
      active = progress ~= nil and progress.equipped >= b.n,
      reachable = progress ~= nil and progress.owned >= b.n,
    }
  end
  return out
end

-- Number of bonuses that are active, for the card.
function IL.ActiveCount(section, progress)
  local n = 0
  for _, b in ipairs(IL.Bonuses(section, progress)) do
    if b.active then
      n = n + 1
    end
  end
  return n
end

-- Text of a bonus: the static text of the data in the language of the player ("de" or "en"), else nil (the
-- page then asks the client for the spell description).
function IL.BonusText(data, spell, lang)
  local t = type(data) == "table" and type(data.texts) == "table" and data.texts[spell]
  return t and (t[lang] or t.en) or nil
end

-- Descriptor of one source of a piece. kind: boss, trash, quest, craft, standing. Returns { kind, place,
-- boss, quest, faction, vendor, skill, level, tier, rate, map, x, y, key } where `place` is { de, en } and the
-- position is the point a waypoint button goes to (nil when the data knows none).
function IL.Describe(src, data)
  local places = type(data) == "table" and data.places or {}
  local place = src.p and places[src.p]
  local d = { key = src.k .. tostring(src.p or src.f and src.f.en or src.sk or "") .. tostring(src.q or "") }
  if src.k == "b" or src.k == "t" then
    d.kind = src.k == "b" and "boss" or "trash"
    d.place, d.boss, d.rate = place and place.n or { de = src.p, en = src.p }, src.b, src.r
    if src.b then
      d.key = d.key .. src.b.en
    end
    if place then
      d.map, d.x, d.y = place.m, place.x, place.y
    end
  elseif src.k == "q" then
    d.kind = "quest"
    d.place, d.quest, d.side = place and place.n or { de = src.p, en = src.p }, src.n, src.f
    d.map, d.x, d.y = src.m, src.x, src.y
    if not d.map and place then
      d.map, d.x, d.y = place.m, place.x, place.y
    end
  elseif src.k == "c" then
    d.kind = "craft"
    d.skill, d.level = src.sk, src.lv
  elseif src.k == "r" then
    d.kind = "standing"
    d.faction, d.tier, d.vendor = src.f, src.t, src.v
    d.map, d.x, d.y = src.m, src.x, src.y
  else
    return nil
  end
  return d
end

-- Position of a descriptor as a waypoint place for the map buttons, nil without a usable one.
function IL.Place(d, label)
  local gl = ns.GuideKitLogic
  return gl and gl.Place({ map = d.map, x = d.x, y = d.y }, label) or nil
end

-- Descriptors of a piece, the first `limit` with a position first. Returns the list and the number left out.
function IL.PieceSources(piece, data, limit)
  local all = {}
  for _, src in ipairs(piece.s or {}) do
    local d = IL.Describe(src, data)
    if d then
      all[#all + 1] = d
    end
  end
  for i, d in ipairs(all) do
    d.order = i
  end
  table.sort(all, function(a, b)
    local pa, pb = a.map and 0 or 1, b.map and 0 or 1
    if pa ~= pb then
      return pa < pb
    end
    return a.order < b.order
  end)
  if limit and #all > limit then
    local cut = {}
    for i = 1, limit do
      cut[i] = all[i]
    end
    return cut, #all - limit
  end
  return all, 0
end
