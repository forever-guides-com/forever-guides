-- Filters and lookups over the generated reference data (trainers, weapons,
-- classes, races, instances). Pure logic, no WoW API.
local _, ns = ...

local R = {}
ns.RefLogic = R

R.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local KIND_ORDER = { start = 1, town = 2, capital = 3, own = 4 }
local ACQUIRE_ORDER = { start = 1, weaponMaster = 2, classTrainer = 3 }

local function data()
  return ns.Data or {}
end

local function factionOk(f, faction)
  return not faction or faction == "all" or f == nil or f == "B" or f == "all" or f == faction
end
R.factionOk = factionOk

function R.slug(name)
  return (tostring(name or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

function R.className(token)
  for _, c in ipairs(data().Classes or {}) do
    if c.id == token then
      return ns.T(c.n)
    end
  end
  return token
end

function R.classColor(token)
  for _, c in ipairs(data().Classes or {}) do
    if c.id == token then
      return c.tc or c.color
    end
  end
end

function R.zoneName(i)
  local z = data().Trainers and data().Trainers.zones and data().Trainers.zones[i]
  return z and ns.T(z) or nil
end

-- "pet" for a pet trainer (teaches the hunter's pet only), else "class".
local function roleOf(t)
  local roles = ns.TrainerRoles
  return roles and roles.Of(t) or "class"
end
R.roleOf = roleOf

-- Class trainers for a class token and faction ("A"/"H"/nil = all), sorted by role (pet trainers
-- last), kind, zone, name. Trainers the player recorded in game (ns.TrainerLog) are merged in,
-- flagged own = true. A data trainer wins over a recorded one with the same NPC id. The pet
-- trainers of the overlay (ns.TrainerRoles, no coordinates) join unless a recorded pet trainer of
-- the same name already has a position.
function R.Trainers(class, faction)
  local out, known = {}, {}
  for _, t in ipairs((data().Trainers and data().Trainers.trainers) or {}) do
    if t.c == class and factionOk(t.f, faction) then
      out[#out + 1] = t
    end
    if t.npc then
      known[t.npc] = true
    end
  end
  local log = ns.TrainerLog
  local okLog, own = false, nil
  if log and log.Entries then
    okLog, own = pcall(log.Entries, class, faction)
  end
  local ownPets = {}
  for _, t in ipairs(okLog and type(own) == "table" and own or {}) do
    if not known[t.npc] then
      out[#out + 1] = t
      if roleOf(t) == "pet" and t.n and t.n.en then
        ownPets[t.n.en:lower()] = true
      end
    end
  end
  if ns.TrainerRoles then
    for _, t in ipairs(ns.TrainerRoles.Entries(class, faction)) do
      if not ownPets[t.n.en:lower()] then
        out[#out + 1] = t
      end
    end
  end
  local rank = {}
  for _, t in ipairs(out) do
    rank[t] = roleOf(t) == "pet" and 1 or 0
  end
  table.sort(out, function(a, b)
    if rank[a] ~= rank[b] then
      return rank[a] < rank[b]
    end
    local ka, kb = KIND_ORDER[a.k] or 9, KIND_ORDER[b.k] or 9
    if ka ~= kb then
      return ka < kb
    end
    local za, zb = R.zoneName(a.z) or "", R.zoneName(b.z) or ""
    if za ~= zb then
      return za < zb
    end
    return a.id < b.id
  end)
  return out
end

-- Known data gaps for the class/faction (entries with "ALL" apply everywhere).
function R.TrainerGaps(class, faction)
  local out = {}
  for _, g in ipairs((data().Trainers and data().Trainers.gaps) or {}) do
    if (g.c == class or g.c == "ALL") and factionOk(g.f, faction) then
      out[#out + 1] = g
    end
  end
  return out
end

-- Races that can play a class and faction combination the trainer data does
-- not cover. Source: the races page of forever-guides.com, not a trainer fact.
local COMBO_RACES = { PALADIN = { H = { "undead" } }, SHAMAN = { A = { "dwarf" } } }

local function raceNames(class, side)
  local out = {}
  for _, slug in ipairs((COMBO_RACES[class] and COMBO_RACES[class][side]) or {}) do
    local name = slug
    for _, r in ipairs(data().Races or {}) do
      if r.slug == slug then
        name = ns.T(r.n) or slug
      end
    end
    out[#out + 1] = name
  end
  return out
end

-- Trainer groups for the page: one per faction ("A"/"H") or both when faction
-- is nil. { faction, trainers, pets, empty, gaps, races }. trainers lists the
-- class trainers first, then the pet trainers, which pets repeats on its own.
-- gaps are the class specific data gaps of that faction, races is only filled
-- for empty groups.
function R.TrainerGroups(class, faction)
  local out = {}
  for _, side in ipairs(faction and { faction } or { "A", "H" }) do
    local g = { faction = side, trainers = R.Trainers(class, side), pets = {}, gaps = {}, races = {} }
    g.empty = #g.trainers == 0
    for _, t in ipairs(g.trainers) do
      if roleOf(t) == "pet" then
        g.pets[#g.pets + 1] = t
      end
    end
    for _, gap in ipairs(R.TrainerGaps(class, side)) do
      if gap.c == class then
        g.gaps[#g.gaps + 1] = gap
      end
    end
    if g.empty then
      g.races = raceNames(class, side)
    end
    out[#out + 1] = g
  end
  return out
end

-- Learning list of one class: { n, l, ... } sorted by level (generator order).
function R.LearnList(class)
  return (data().Abilities and data().Abilities[class]) or {}
end

function R.SkillName(id)
  local s = data().Weapons and data().Weapons.skills and data().Weapons.skills[id]
  return s and ns.T(s) or id
end

function R.WeaponTrainer(id)
  for _, t in ipairs((data().Weapons and data().Weapons.trainers) or {}) do
    if t.id == id then
      return t
    end
  end
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

-- Weapon skill rows for a class:
-- { skill, name, a, l, h, cf, unconfirmed, raceStart, trainers = { trainer.. }, hidden }.
-- hidden counts weapon masters dropped by the faction filter. race (slug or
-- nil) sets raceStart on skills that race knows from the start. Trainers are
-- shallow copies carrying an unconfirmed flag, the shared data stays untouched.
function R.Weapons(class, faction, race)
  local out = {}
  local extra = data().WeaponRaces or {}
  local startRaces = (extra.start and extra.start[class]) or {}
  local skillFlags = (extra.unconfirmedSkills and extra.unconfirmedSkills[class]) or {}
  local trainerFlags = extra.unconfirmedTrainers or {}
  for _, m in ipairs((data().Weapons and data().Weapons.matrix and data().Weapons.matrix[class]) or {}) do
    local row = {
      skill = m.s,
      name = R.SkillName(m.s),
      a = m.a,
      l = m.l,
      h = m.h,
      cf = m.cf,
      unconfirmed = skillFlags[m.s] == true,
      raceStart = race ~= nil and contains(startRaces[m.s] or {}, race),
      trainers = {},
      hidden = 0,
    }
    for _, id in ipairs(m.t or {}) do
      local t = R.WeaponTrainer(id)
      if t then
        if factionOk(t.f, faction) then
          local entry = {}
          for k, v in pairs(t) do
            entry[k] = v
          end
          entry.unconfirmed = trainerFlags[id] == true
          row.trainers[#row.trainers + 1] = entry
        else
          row.hidden = row.hidden + 1
        end
      end
    end
    out[#out + 1] = row
  end
  table.sort(out, function(a, b)
    local oa, ob = ACQUIRE_ORDER[a.a] or 9, ACQUIRE_ORDER[b.a] or 9
    if oa ~= ob then
      return oa < ob
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.skill < b.skill
  end)
  return out
end

-- Races (WeaponRaces entries, website order) that can be the given class in
-- Forever, limited to faction "A"/"H" (nil or "all" = both). A race without an
-- ns.Data.RaceClasses entry stays allowed so missing data never hides a race.
function R.RacesForClass(class, faction)
  local out = {}
  local byRace = data().RaceClasses and data().RaceClasses.byRace or {}
  for _, race in ipairs(data().WeaponRaces and data().WeaponRaces.races or {}) do
    local classes = byRace[race.s]
    if factionOk(race.f, faction) and (not classes or classes[class]) then
      out[#out + 1] = race
    end
  end
  return out
end

-- Class abilities that exist as race-specific variants (Abilities `r` lists race slugs).
function R.RaceAbilities(slug)
  local out = {}
  for _, class in ipairs(R.CLASSES) do
    for _, a in ipairs(R.LearnList(class)) do
      for _, r in ipairs(a.r or {}) do
        if r == slug then
          out[#out + 1] = { class = class, ability = a }
        end
      end
    end
  end
  return out
end

function R.Races(faction)
  local out = {}
  for _, r in ipairs(data().Races or {}) do
    if factionOk(r.f, faction) then
      out[#out + 1] = r
    end
  end
  return out
end

function R.ClassStats(class)
  local spells, kinds = 0, {}
  for _, s in ipairs((data().Spells and data().Spells[class]) or {}) do
    spells = spells + 1
    kinds[s.k or "other"] = (kinds[s.k or "other"] or 0) + 1
  end
  local weapons = 0
  for _, m in ipairs((data().Weapons and data().Weapons.matrix and data().Weapons.matrix[class]) or {}) do
    if m.a ~= "start" then
      weapons = weapons + 1
    end
  end
  return {
    trainers = #R.Trainers(class),
    abilities = #R.LearnList(class),
    spells = spells,
    passives = kinds.passive or 0,
    talents = kinds.talent or 0,
    weapons = weapons,
  }
end

-- Name in the active language plus the other language when it exists and differs.
function R.Names(field)
  if type(field) ~= "table" then
    return field
  end
  local main = ns.T(field)
  local other = ns.GetActiveLocale() == "deDE" and field.en or field.de
  return main, other ~= main and other or nil
end

-- Lowest level of an instance for sorting: start of the level range, else the
-- recommended level, else nil.
function R.InstanceLevel(inst)
  return tonumber(tostring(inst.lv or ""):match("^%d+")) or tonumber(inst.rl)
end

local function instanceMatches(inst, query, match)
  local function hit(field)
    return type(field) == "table" and ((field.de and match(field.de, query)) or (field.en and match(field.en, query)))
  end
  if hit(inst.n) then
    return true
  end
  for _, b in ipairs(inst.bo or {}) do
    if hit(b.n) then
      return true
    end
  end
  return false
end

-- Instances of a kind ("dungeon"/"raid"/nil), faction-filtered, sorted by display name
-- or, with sort == "level", by lowest level (unknown levels last), then name.
-- match(text, query) is applied to the German and English names of the instance and its
-- bosses when a query is given.
function R.Instances(kind, faction, query, match, sort)
  local out = {}
  for _, i in ipairs(data().Instances or {}) do
    if (not kind or i.t == kind) and factionOk(i.f, faction) then
      if not query or query == "" or instanceMatches(i, query, match) then
        out[#out + 1] = i
      end
    end
  end
  local byLevel = sort == "level"
  table.sort(out, function(a, b)
    if byLevel then
      local la, lb = R.InstanceLevel(a), R.InstanceLevel(b)
      if la ~= lb then
        return (la or math.huge) < (lb or math.huge)
      end
    end
    local na, nb = ns.T(a.n) or "", ns.T(b.n) or ""
    if na ~= nb then
      return na < nb
    end
    return (a.id or 0) < (b.id or 0)
  end)
  return out
end

function R.InstanceSlug(inst)
  return R.slug(inst.n and inst.n.en or "")
end

function R.FindInstance(slug)
  for _, i in ipairs(data().Instances or {}) do
    if R.InstanceSlug(i) == slug then
      return i
    end
  end
end

-- Comparison key of a quest without its ID and faction: an ID-free chain (names of the quests it links to) and the
-- fields the player sees. Two entries with the same key tell the player the same.
local function questKey(q, byId)
  local function chain(ids)
    local names = {}
    for _, id in ipairs(ids or {}) do
      names[#names + 1] = byId[id] and byId[id].n and byId[id].n.en or ("#" .. tostring(id))
    end
    return table.concat(names, "|")
  end
  local rewards = {}
  for _, r in ipairs(q.rw or {}) do
    rewards[#rewards + 1] = table.concat({ tostring(r.id), tostring(r.n), tostring(r.c), tostring(r.ch) }, ":")
  end
  local zone = q.sz or {}
  return table.concat({
    tostring(q.l),
    tostring(q.rq),
    tostring(q.xp),
    tostring(q.mo),
    tostring(q.en),
    tostring(q.sn),
    tostring(zone.en),
    tostring(zone.de),
    tostring(q.m),
    tostring(q.x),
    tostring(q.y),
    chain(q.pre),
    chain(q.nxt),
    table.concat(rewards, ","),
  }, "\t")
end

-- The quests of an instance with every pair of one Alliance and one Horde entry of the same name and the same
-- content (they differ at most in the quest ID) merged to one entry for both factions. The data stays as it is,
-- the merged entry is a copy of the Alliance entry with f = "B" and merged = true.
function R.MergedQuests(inst)
  local byId, byName = {}, {}
  for _, q in ipairs(inst.q or {}) do
    byId[q.id or 0] = q
    local name = q.n and (q.n.en or q.n.de) or ""
    byName[name] = byName[name] or {}
    table.insert(byName[name], q)
  end
  local drop, merged = {}, {}
  for _, group in pairs(byName) do
    local a, h
    if #group == 2 then
      a, h = group[1], group[2]
      if a.f == "H" and h.f == "A" then
        a, h = h, a
      end
    end
    if a and a.f == "A" and h.f == "H" and questKey(a, byId) == questKey(h, byId) then
      local copy = {}
      for k, v in pairs(a) do
        copy[k] = v
      end
      copy.f, copy.merged = "B", true
      merged[a], drop[h] = copy, true
    end
  end
  local out = {}
  for _, q in ipairs(inst.q or {}) do
    if merged[q] then
      out[#out + 1] = merged[q]
    elseif not drop[q] then
      out[#out + 1] = q
    end
  end
  return out
end

-- Quests of an instance for the faction (merged, see R.MergedQuests), sorted by level then name.
function R.Quests(inst, faction)
  local out = {}
  for _, q in ipairs(R.MergedQuests(inst)) do
    if factionOk(q.f, faction) then
      out[#out + 1] = q
    end
  end
  table.sort(out, function(a, b)
    if (a.l or 0) ~= (b.l or 0) then
      return (a.l or 0) < (b.l or 0)
    end
    return (ns.T(a.n) or "") < (ns.T(b.n) or "")
  end)
  return out
end
