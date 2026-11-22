-- Hunter pets, pure side (no frames): the families, abilities, tameable beasts and rare tames of
-- Data/HunterPets.lua with search filters, lookups and the place of a beast for the Map and Waypoint
-- buttons. The page is Modules/PetsPage.lua, the data file is generated.
local _, ns = ...

local P = {}
ns.PetsLogic = P

P.TABS = { "families", "abilities", "rares" }

local function data()
  return ns.Data and ns.Data.HunterPets or { families = {}, abilities = {}, beasts = {}, rares = {}, zones = {} }
end

local indexed
local function index()
  local d = data()
  if indexed and indexed.source == d then
    return indexed
  end
  local ix = { source = d, family = {}, ability = {}, byFamily = {}, rareByFamily = {} }
  for _, f in ipairs(d.families) do
    ix.family[f.id] = f
    ix.byFamily[f.id] = {}
  end
  for _, a in ipairs(d.abilities) do
    ix.ability[a.id] = a
  end
  for _, b in ipairs(d.beasts) do
    local list = ix.byFamily[b.fam]
    if list then
      list[#list + 1] = b
    end
  end
  ix.rareById = {}
  for _, b in ipairs(d.rares) do
    ix.rareById[b.id] = true
    local list = ix.rareByFamily[b.fam] or {}
    ix.rareByFamily[b.fam] = list
    list[#list + 1] = b
  end
  for _, list in pairs(ix.byFamily) do
    table.sort(list, function(a, b)
      if a.l[1] ~= b.l[1] then
        return a.l[1] < b.l[1]
      end
      return a.id < b.id
    end)
  end
  indexed = ix
  return ix
end

function P.Reset()
  indexed = nil
end

function P.Basis()
  return data().basis
end

function P.Family(id)
  return index().family[id]
end

function P.Ability(id)
  return index().ability[id]
end

function P.Families()
  return data().families
end

function P.Abilities()
  return data().abilities
end

function P.Rares()
  return data().rares
end

function P.Zone(z)
  return data().zones[z]
end

function P.ZoneName(entry)
  local zone = P.Zone(entry.z)
  return zone and ns.T(zone) or "?"
end

-- Both languages of a { de, en } name, so a German query finds an English client and the other way round.
local function names(n)
  return type(n) == "table" and { n.de, n.en } or { n }
end

local function hit(match, query, n)
  for _, text in ipairs(names(n)) do
    if text and match(text, query) then
      return true
    end
  end
  return false
end

-- Beasts of one family, lowest level first.
function P.BeastsOfFamily(id)
  return index().byFamily[id] or {}
end

function P.IsRare(entry)
  return index().rareById[entry.id] == true
end

-- Tameable beasts of a family and its rare tames, lowest level first.
function P.TamesOfFamily(id)
  local out = {}
  for _, b in ipairs(index().byFamily[id] or {}) do
    out[#out + 1] = b
  end
  for _, b in ipairs(index().rareByFamily[id] or {}) do
    out[#out + 1] = b
  end
  table.sort(out, function(a, b)
    if a.l[1] ~= b.l[1] then
      return a.l[1] < b.l[1]
    end
    return a.id < b.id
  end)
  return out
end

-- Count and level span of the tameable beasts of a family (rare tames included): count, lowest, highest.
function P.TameSpan(id)
  local list = P.TamesOfFamily(id)
  local lo, hi
  for _, b in ipairs(list) do
    lo = lo and math.min(lo, b.l[1]) or b.l[1]
    hi = hi and math.max(hi, b.l[2]) or b.l[2]
  end
  return #list, lo, hi
end

-- Beasts that can teach an ability: those of its families that reach the level of the first rank. An ability
-- of every family (Cower, Growl, resistances) has no list of its own.
function P.BeastsOfAbility(ability)
  if not ability or ability.all then
    return {}
  end
  local from = ability.ranks[1] and ability.ranks[1].l or 1
  local out = {}
  for _, fam in ipairs(ability.fam) do
    for _, b in ipairs(P.BeastsOfFamily(fam)) do
      if b.l[2] >= from then
        out[#out + 1] = b
      end
    end
  end
  table.sort(out, function(a, b)
    if a.l[1] ~= b.l[1] then
      return a.l[1] < b.l[1]
    end
    return a.id < b.id
  end)
  return out
end

local function familyHit(f, match, query)
  if hit(match, query, f.n) then
    return true
  end
  for _, id in ipairs(f.ab) do
    local a = P.Ability(id)
    if a and hit(match, query, a.n) then
      return true
    end
  end
  for _, b in ipairs(P.BeastsOfFamily(f.id)) do
    if hit(match, query, b.n) then
      return true
    end
  end
  for _, b in ipairs(data().rares) do
    if b.fam == f.id and hit(match, query, b.n) then
      return true
    end
  end
  return false
end

-- Families whose name, ability names or beast names (also the rare ones) contain the query; all for an empty query.
function P.FilterFamilies(query, match)
  local out = {}
  for _, f in ipairs(data().families) do
    if query == "" or familyHit(f, match, query) then
      out[#out + 1] = f
    end
  end
  return out
end

-- Abilities whose name or description, the name of one of their families or one of the beasts that teach it matches.
function P.FilterAbilities(query, match)
  local out = {}
  for _, a in ipairs(data().abilities) do
    local ok = query == ""
    ok = ok or hit(match, query, a.n) or (a.d ~= nil and hit(match, query, a.d))
    for _, id in ipairs(ok and {} or a.fam) do
      local f = P.Family(id)
      ok = ok or (f ~= nil and hit(match, query, f.n))
    end
    if not ok then
      for _, b in ipairs(P.BeastsOfAbility(a)) do
        if hit(match, query, b.n) then
          ok = true
          break
        end
      end
    end
    if ok then
      out[#out + 1] = a
    end
  end
  return out
end

-- Rare tames by beast, family or zone name.
function P.FilterRares(query, match)
  local out = {}
  for _, b in ipairs(data().rares) do
    local f = P.Family(b.fam)
    if
      query == ""
      or hit(match, query, b.n)
      or (f ~= nil and hit(match, query, f.n))
      or hit(match, query, P.Zone(b.z) or "")
    then
      out[#out + 1] = b
    end
  end
  return out
end

-- The beasts whose zone name (German or English) contains the query; all for an empty query.
function P.FilterBeastsByZone(beasts, query, match)
  if query == "" then
    return beasts
  end
  local out = {}
  for _, b in ipairs(beasts) do
    if hit(match, query, P.Zone(b.z) or "") then
      out[#out + 1] = b
    end
  end
  return out
end

-- "12" or "12-14".
function P.LevelText(b)
  local lo, hi = b.l[1], b.l[2]
  return lo == hi and tostring(lo) or (lo .. "-" .. hi)
end

-- The place the Map and Waypoint buttons act on: { map, x, y, label, zone } or nil without a zone.
function P.Place(b)
  local zone = P.Zone(b.z)
  return {
    map = zone and zone.m or nil,
    x = b.x,
    y = b.y,
    label = ns.T(b.n),
    zone = zone and ns.T(zone) or "?",
  }
end

-- Number of ranks and the lowest and highest rank level of an ability.
function P.RankSpan(ability)
  local ranks = ability.ranks
  return #ranks, ranks[1] and ranks[1].l or 1, ranks[#ranks] and ranks[#ranks].l or 1
end

-- Abilities every family has; the others of a family are its special trait.
P.COMMON = { bite = true, claw = true, dash = true }

-- Ids of the abilities of a family beyond bite, claw and dash.
function P.SpecialAbilities(f)
  local out = {}
  for _, id in ipairs(f.ab) do
    if not P.COMMON[id] then
      out[#out + 1] = id
    end
  end
  return out
end

-- Health, armor and damage of a family as { id, value } in display order; value is the multiplier of the data (1.08).
function P.Modifiers(f)
  return { { id = "health", value = f.h }, { id = "armor", value = f.a }, { id = "damage", value = f.d } }
end

-- A common item of each food type; the page asks the client for its icon.
P.DIET_ITEM = { meat = 117, fish = 6291, cheese = 414, bread = 4540, fungus = 4605, fruit = 4536 }

-- Food types of a family as { diet, item } in data order.
function P.DietIcons(f)
  local out = {}
  for _, diet in ipairs(f.diet) do
    out[#out + 1] = { diet = diet, item = P.DIET_ITEM[diet] }
  end
  return out
end

-- The first limit rows, or all of them when expanded or when they are not clearly more than the limit.
function P.Limit(rows, limit, expanded)
  if expanded or #rows <= limit then
    return rows
  end
  local out = {}
  for i = 1, limit do
    out[i] = rows[i]
  end
  return out
end

-- Search (Ctrl+K): families, abilities, rare tames and the beasts by name, each leading to its place on the page.
ns.AddLocale("enUS", { ["search.kind.pet"] = "Hunter pet" })
ns.AddLocale("deDE", { ["search.kind.pet"] = "Jäger-Begleiter" })

ns.SearchLogic.RegisterSource("pet", function(add)
  for _, f in ipairs(data().families) do
    add(f.n, nil, "pets/" .. f.id)
  end
  for _, a in ipairs(data().abilities) do
    add(a.n, nil, "pets/" .. a.id)
  end
  for _, b in ipairs(data().rares) do
    local f = P.Family(b.fam)
    add(b.n, f and ns.T(f.n) or nil, "pets/rares")
  end
  local seen = {}
  for _, b in ipairs(data().beasts) do
    if not seen[b.n.en] then
      seen[b.n.en] = true
      local f = P.Family(b.fam)
      add(b.n, f and ns.T(f.n) or nil, "pets/" .. b.fam)
    end
  end
end)

return P
