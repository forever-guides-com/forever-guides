-- Learn list: what a class can learn at a class trainer at which level
-- (abilities and ranks). Weapon skills and the talents themselves are not listed,
-- weapons live on the weapon masters page. Of an ability that comes through a
-- talent only the ranks above the talent rank are taught.
-- Pure logic over the generated data (Abilities, Spells, LevelSources).
local _, ns = ...

local LV = {}
ns.LevelLogic = LV

LV.CAP = 60

local function fold(text)
  return ns.SearchLogic.fold(text)
end

local function data()
  return ns.Data or {}
end

local function rankIds(class)
  local out = {}
  for _, s in ipairs((data().Spells and data().Spells[class]) or {}) do
    local name = s.n and s.n.en and s.n.en:lower()
    if name and (s.c == nil or #s.c == 1) then
      out[name] = out[name] or {}
      out[name][s.rk or 0] = s.id
    end
  end
  return out
end

-- Lower case names of the class talents (talent trees data).
local function talentNames(class)
  local out = {}
  local trees = data().TalentTrees
  for _, tree in ipairs((trees and trees.classes and trees.classes[class]) or {}) do
    for _, t in ipairs(tree.talents or {}) do
      local name = t.n and t.n.en
      if name then
        out[name:lower()] = true
      end
    end
  end
  return out
end

-- True when the trainer price data knows the spell (it is taught by a class trainer).
local function priced(class, id)
  local costs = data().TrainerCosts
  if not costs then
    return false
  end
  local byClass = costs.byClass and costs.byClass[class]
  return (costs.costs ~= nil and costs.costs[id] ~= nil) or (byClass ~= nil and byClass[id] ~= nil)
end

-- Trainer spells of the class by lower case name: { key, n, i, ranks = { [rank] = { id, l } } },
-- rank 0 = no rank; agreed = the trainer level of every rank equals the spell level. Only spells with a trainer price count, talent rank 1 and weapon
-- skills are no trainer spells. named = every spell name of the class.
local function rankChains(class)
  local chains, named = {}, {}
  local skills = {}
  local req = data().TrainerCosts and data().TrainerCosts.req
  for _, id in pairs(LV.SKILL_SPELLS) do
    skills[id] = true
  end
  for _, s in ipairs((data().Spells and data().Spells[class]) or {}) do
    local name = s.n and s.n.en and s.n.en:lower()
    if name and (s.l or 0) > 0 and (s.c == nil or #s.c == 1) then
      named[name] = true
      local rank = s.rk or 0
      if s.k ~= "weapon" and (s.k ~= "talent" or rank >= 2) and not skills[s.id] and priced(class, s.id) then
        local chain = chains[name] or { key = name, n = s.n, i = s.i, ranks = {} }
        chains[name] = chain
        chain.ranks[rank] = chain.ranks[rank] or { id = s.id, l = s.l, ok = req ~= nil and req[s.id] == s.l }
      end
    end
  end
  for _, chain in pairs(chains) do
    chain.agreed = true
    for _, e in pairs(chain.ranks) do
      chain.agreed = chain.agreed and e.ok
    end
  end
  return chains, named
end

-- Ranks of a chain from minRank on, ascending: { { rank, id, l } }.
local function chainRanks(chain, minRank)
  local list = {}
  for rank, e in pairs(chain.ranks) do
    if rank >= minRank then
      list[#list + 1] = { rank = rank, id = e.id, l = e.l, ok = e.ok }
    end
  end
  table.sort(list, function(x, y)
    return x.rank < y.rank
  end)
  return list
end

local function signature(levels)
  local copy = {}
  for _, l in ipairs(levels) do
    if l > 0 then
      copy[#copy + 1] = l
    end
  end
  table.sort(copy)
  return table.concat(copy, ",")
end

-- Levels of an Abilities entry (above 0).
local function levelsOf(a)
  local out = {}
  for _, l in ipairs(#(a.rk or {}) > 0 and a.rk or { a.l or 0 }) do
    if l > 0 then
      out[#out + 1] = l
    end
  end
  return out
end

-- True when the chain replaces the Abilities entry: no other entry uses the same icon
-- (no sibling of a renamed family) and either the chain has every level of the entry
-- (a level twice needs two ranks) or spell level and trainer level agree for every
-- rank and the chain has at least as many ranks (the client changed the levels).
local function confirms(chain, a, icons)
  local levels = levelsOf(a)
  if #levels == 0 or not a.i or icons[a.i] ~= 1 then
    return false
  end
  local have, count = {}, 0
  for _, e in pairs(chain.ranks) do
    have[e.l] = (have[e.l] or 0) + 1
    count = count + 1
  end
  if chain.agreed and count >= #levels then
    return true
  end
  for _, l in ipairs(levels) do
    if (have[l] or 0) == 0 then
      return false
    end
    have[l] = have[l] - 1
  end
  return true
end

-- Name without rank wording: "Create Healthstone (Minor)" and "Detect Lesser Invisibility"
-- belong to "Create Healthstone" and "Detect Invisibility".
local function baseName(key)
  return (key:gsub(" %b()", ""):gsub(" lesser", ""):gsub(" greater", ""))
end

-- Plans how the trainer spells and the Abilities entries meet.
-- renamed: entry -> chain that replaces it. Either the client renamed the spell (the
-- entry has no spell of its name, same levels as exactly one chain nobody else
-- lists, at least two levels), or the entries named like the chain plus a rank wording
-- ("(Minor)", "Lesser") together have exactly the chain's levels (one spell, ranks listed under their own names;
-- the others go to skip).
-- extra: chains without any Abilities entry with levels. Ambiguous groups stay out.
local function chainPlan(abilities, chains, named)
  local listed, entries, groups, byBase, byKey = {}, {}, {}, {}, {}
  for _, a in ipairs(abilities) do
    local key = a.n and a.n.en and a.n.en:lower()
    local sig = signature(#(a.rk or {}) > 0 and a.rk or { a.l or 0 })
    -- Entries without a level are not shown, their name does not count as listed.
    if key and (a.ft or sig ~= "") then
      listed[key] = true
      byKey[key] = a
    end
    if key and not a.ft and sig ~= "" then
      local base = baseName(key)
      byBase[base] = byBase[base] or {}
      table.insert(byBase[base], a)
      if not named[key] then
        entries[sig] = entries[sig] or {}
        table.insert(entries[sig], a)
      end
    end
  end
  local renamed, extra, skip = {}, {}, {}
  for key, chain in pairs(chains) do
    local levels = {}
    for _, r in ipairs(chainRanks(chain, 0)) do
      levels[#levels + 1] = r.l
    end
    local sig = signature(levels)
    local head = byKey[key]
    if listed[key] then
      local family = head and not head.ft and byBase[key] or {}
      local union = {}
      for _, e in ipairs(family) do
        for _, l in ipairs(levelsOf(e)) do
          union[#union + 1] = l
        end
      end
      if #family > 1 and signature(union) == sig then
        renamed[head] = chain
        for _, e in ipairs(family) do
          skip[e] = e ~= head or nil
        end
      end
    else
      groups[sig] = groups[sig] or {}
      table.insert(groups[sig], chain)
    end
  end
  for sig, group in pairs(groups) do
    local entry = entries[sig]
    if not entry then
      for _, chain in ipairs(group) do
        extra[#extra + 1] = chain
      end
    elseif #entry == 1 and #group == 1 and sig:find(",", 1, true) then
      renamed[entry[1]] = group[1]
    end
  end
  return renamed, extra, skip
end

-- Trainer spells that only some races can learn, class -> lower case name -> race slugs.
-- The Abilities data has no entry for them, the client data binds them to the race.
local RACE_ONLY = {
  PRIEST = { ["dark sacrifice"] = { "undead" } },
}

-- Key of a learn list item in the trainer price data: CLASS:lower case name:rank (0 = no rank).
function LV.NameKey(class, name, rank)
  return class .. ":" .. name:lower() .. ":" .. (rank or 0)
end

-- Spell id the price data knows for an item that has none in the Spells data.
local function aliasId(class, name, rank)
  local costs = data().TrainerCosts
  return costs and costs.alias and name and costs.alias[LV.NameKey(class, name, rank)] or nil
end

local function clampLevel(level)
  return math.min(LV.CAP, math.max(1, level))
end

-- levels[1..CAP] = { level, items = { { kind = "ability", n, rank, sid, sp, i } } }.
function LV.Build(class)
  local levels = {}
  for i = 1, LV.CAP do
    levels[i] = { level = i, items = {} }
  end
  local ids = rankIds(class)
  local chains, named = rankChains(class)
  local talents = talentNames(class)
  local abilities = (data().Abilities and data().Abilities[class]) or {}
  local renamed, extra, skip = chainPlan(abilities, chains, named)
  local icons, byKey = {}, {}
  for _, a in ipairs(abilities) do
    icons[a.i or ""] = (icons[a.i or ""] or 0) + 1
    byKey[a.n and a.n.en and a.n.en:lower() or ""] = a
  end
  local function add(level, item)
    local items = levels[clampLevel(level)].items
    items[#items + 1] = item
  end
  local only = RACE_ONLY[class] or {}
  local function addChain(list, chain, n, sp, icon)
    for _, r in ipairs(list) do
      local rank = (#list > 1 or r.rank > 1) and r.rank or nil
      add(r.l, {
        kind = "ability",
        n = n,
        rank = rank,
        sid = r.id,
        sp = sp,
        i = icon,
        only = only[chain.key],
        confirmed = r.ok or nil,
      })
    end
  end
  local function addEntry(a)
    local name = a.n and a.n.en
    local key = name and name:lower()
    -- fromTalent also marks abilities that are no talent in Forever, those are taught from rank 1.
    -- Without trainer spells such an entry is not shown.
    local talent = a.ft and key ~= nil and talents[key] == true
    local chain = renamed[a] or (key and chains[key]) or nil
    -- The trainer spells are the authority for ranks and levels where they confirm the entry.
    local list = {}
    if chain and (renamed[a] or a.ft or confirms(chain, a, icons)) then
      list = chainRanks(chain, talent and 2 or 0)
    end
    if #list > 0 then
      addChain(list, chain, a.n, a.sp, a.i)
    elseif not a.ft then
      local byName = key and ids[key]
      local ranks = {}
      for _, l in ipairs(a.rk or {}) do
        if l > 0 then
          ranks[#ranks + 1] = l
        end
      end
      if #ranks == 0 then
        if (a.l or 0) > 0 then
          local sid = a.sid or aliasId(class, name, nil)
          add(a.l, { kind = "ability", n = a.n, sid = sid, sp = a.sp, i = a.i })
        end
      else
        for i, l in ipairs(ranks) do
          local rank = #ranks > 1 and i or nil
          local sid = byName and byName[rank or 0] or (i == 1 and a.sid or nil)
          sid = sid or aliasId(class, name, rank)
          add(l, { kind = "ability", n = a.n, rank = rank, sid = sid, sp = a.sp, i = a.i })
        end
      end
    end
  end
  for _, a in ipairs(abilities) do
    if not skip[a] then
      addEntry(a)
    end
  end
  for _, chain in ipairs(extra) do
    local a = byKey[chain.key]
    addChain(chainRanks(chain, 0), chain, chain.n, a and a.sp, (a and a.i) or chain.i)
  end
  for _, lv in ipairs(levels) do
    table.sort(lv.items, function(x, y)
      local nx, ny = (x.n and x.n.en) or "", (y.n and y.n.en) or ""
      if nx ~= ny then
        return nx < ny
      end
      return (x.rank or 0) < (y.rank or 0)
    end)
  end
  return levels
end

local cache = {}
function LV.Get(class)
  cache[class] = cache[class] or LV.Build(class)
  return cache[class]
end

function LV.ResetCache()
  cache = {}
end

-- nameOf(item) -> text (optional) adds one more searchable name, e.g. the live
-- localized spell name the data does not carry.
local function matches(item, query, nameOf)
  if query == "" then
    return true
  end
  for _, text in ipairs({ item.n and item.n.de or "", item.n and item.n.en or "", nameOf and nameOf(item) or "" }) do
    if fold(text):find(query, 1, true) then
      return true
    end
  end
  return false
end

-- Race-bound items (item.only) are hidden once the player's race (o.race, slug) is
-- known and not among them.
local function visible(item, o)
  if not item.only or not o.race then
    return true
  end
  for _, slug in ipairs(item.only) do
    if slug == o.race then
      return true
    end
  end
  return false
end

local function queryOf(o)
  return (fold(o.search or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Flat rows for the list. o: fromLevel (default 1), search, race (slug), isKnown(item) -> bool|nil.
-- A level appears when it has matching items; level rows: { header = true, level, count }.
function LV.Rows(class, o)
  o = o or {}
  local query = queryOf(o)
  local out = {}
  for _, lv in ipairs(LV.Get(class)) do
    if lv.level >= (o.fromLevel or 1) then
      local rows = {}
      for _, item in ipairs(lv.items) do
        if visible(item, o) and matches(item, query) then
          rows[#rows + 1] = {
            item = item,
            level = lv.level,
            known = o.isKnown and o.isKnown(item) or nil,
          }
        end
      end
      if #rows > 0 then
        out[#out + 1] = { header = true, level = lv.level, count = #rows }
        for _, r in ipairs(rows) do
          out[#out + 1] = r
        end
      end
    end
  end
  return out
end

-- Level cards for the page, same options and inclusion rule as LV.Rows:
-- { level, count, groups = { teacher } }.
-- Group items are copies of the cached items plus per-call meta: quest (comes
-- through a quest, still taught by the trainer) and known.
function LV.Levels(class, o)
  o = o or {}
  local query = queryOf(o)
  local sources = data().LevelSources
  local quest = sources and sources.quest and sources.quest[class] or {}
  local out = {}
  for _, lv in ipairs(LV.Get(class)) do
    if lv.level >= (o.fromLevel or 1) then
      local groups = { teacher = {} }
      local count = 0
      for _, item in ipairs(lv.items) do
        if visible(item, o) and matches(item, query, o.nameOf) then
          local entry = {}
          for k, v in pairs(item) do
            entry[k] = v
          end
          entry.quest = item.n and quest[item.n.en] == true or nil
          entry.known = o.isKnown and o.isKnown(item) or nil
          groups.teacher[#groups.teacher + 1] = entry
          count = count + 1
        end
      end
      if count > 0 then
        out[#out + 1] = { level = lv.level, groups = groups, count = count }
      end
    end
  end
  return out
end

-- Passive proficiency spell per skill key of Weapons.skills, for the weapon
-- masters page (prices and price capture); knowing the spell means the weapon,
-- armor or combat skill is learned.
LV.SKILL_SPELLS = {
  axe1h = 196,
  axe2h = 197,
  bow = 264,
  crossbow = 5011,
  dagger = 1180,
  dualwield = 674,
  fist = 15590,
  gun = 266,
  leather = 9077,
  mace1h = 198,
  mace2h = 199,
  mail = 8737,
  parry = 3127,
  plate = 750,
  polearm = 200,
  shield = 9116,
  staff = 227,
  sword1h = 201,
  sword2h = 202,
  thrown = 2567,
  wand = 5009,
}

local function spellKnown(id)
  return ns.MacroSpells and ns.MacroSpells.isKnown(id)
end

-- true/false, or nil when the game cannot tell. A learned higher rank counts as
-- known for the lower ones: the spellbook replaces a rank when the next is learned.
function LV.IsKnown(item)
  local id = item.sid
  if not id then
    return nil
  end
  local known = spellKnown(id)
  if known or not ns.DataApi then
    return known
  end
  for _, s in ipairs(ns.DataApi.RankChain(id)) do
    if (s.rk or 0) > (item.rank or 0) and spellKnown(s.id) then
      return true
    end
  end
  return known
end

local function emptyCard(card)
  return {
    level = card.level,
    count = 0,
    groups = { teacher = {} },
  }
end

-- Splits the level cards into the learn list's areas. o = LV.Levels options plus
-- playerLevel. With playerLevel and isKnown: sections learned, available (level
-- reached, not learned) and locked (above the player's level), in that order,
-- each { id, count, levels } with levels ascending and only cards that hold
-- entries. Without them (other class,
-- unknown level) one plain section "all" holds everything.
function LV.Sections(class, o)
  o = o or {}
  local own = o.playerLevel ~= nil and o.isKnown ~= nil
  local order = own and { "learned", "available", "locked" } or { "all" }
  local sections, byId = {}, {}
  for i, id in ipairs(order) do
    sections[i] = { id = id, count = 0, levels = {} }
    byId[id] = sections[i]
  end
  for _, card in ipairs(LV.Levels(class, o)) do
    local split = {}
    for _, entry in ipairs(card.groups.teacher) do
      local id = "all"
      if own then
        id = entry.known and "learned" or card.level <= o.playerLevel and "available" or "locked"
      end
      local part = split[id]
      if not part then
        part = emptyCard(card)
        split[id] = part
        local section = byId[id]
        section.levels[#section.levels + 1] = part
      end
      part.groups.teacher[#part.groups.teacher + 1] = entry
      part.count = part.count + 1
      byId[id].count = byId[id].count + 1
    end
  end
  return { plain = not own, sections = sections }
end
