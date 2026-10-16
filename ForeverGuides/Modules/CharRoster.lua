-- Character roster: every character that logged in with the addon, kept in the
-- account-wide SavedVariables (ns.db.roster, never sent anywhere). The start
-- page lists it (Dashboard.lua). Each field is read through pcall, so a client
-- without one of the APIs only leaves that field empty.
--
-- ns.db.roster["Name-Realm"] = {
--   name (first name), surname (nil without one), realm, class (token), race (token), raceSlug (Data.Races slug),
--   faction ("A"|"H"), sex (2 male, 3 female), level, money (copper; nil = never read, not 0),
--   zone, subzone, guild, ilvl (average item level; nil = never read),
--   at = { money, ilvl, zone, guild, level } (server time of the reading of each field),
--   schema (2), played (seconds, total), levelPlayed (seconds on
--   the current level), playedAt (server time of that reading),
--   professions = { { name, skill, max, id, kind } } (ProfessionLogic, written by Professions.lua),
--   professionsAt (server time of that reading), seen (time()), build, addon,
--   pvp, rep, stats = blocks of RosterStatsLogic (written by RosterStats.lua through SetStats),
--   raids = { lock } (RaidLockLogic), raidsAt (server time of that reading), todos = { values = { [todoId] = { done, at } } },
--   order (position in the custom sort), hidden (true: not shown in the overview),
--   kills = { [raidKey] = { week, ends, bosses } } (raid boss kills of the week, RaidWeekLogic),
--   access = { [instanceKey] = { done, total, at } } (last instance access state, AccessView)
-- }
local _, ns = ...
local U = ns.U

local Roster = {}
ns.CharRoster = Roster

Roster.CAP = 60
local UPDATE_DELAY = 1
local ITEM_READ_GAP = 1
local MAX_PROFESSIONS = 8

-- UnitRace's token to the race slug of Data.Races. Skyborne is one token for both
-- races, the faction tells them apart (SKYBORNE_SLUG).
local RACE_SLUG = {
  Human = "human",
  Dwarf = "dwarf",
  NightElf = "night-elf",
  Gnome = "gnome",
  Orc = "orc",
  Scourge = "undead",
  Tauren = "tauren",
  Troll = "troll",
}
local SKYBORNE_SLUG = { A = "high-order-skyborne", H = "windshaper-skyborne" }

local function raceSlug(token, name, faction)
  if RACE_SLUG[token] then
    return RACE_SLUG[token]
  end
  local flat = type(token) == "string" and token:lower() or nil
  if flat == "skyborne" and SKYBORNE_SLUG[faction] then
    return SKYBORNE_SLUG[faction]
  end
  for _, r in ipairs((ns.Data and ns.Data.Races) or {}) do
    local slugFlat = r.slug:gsub("%-", "")
    if (flat and flat == slugFlat) or (name and (name == r.n.en or name == r.n.de)) then
      return r.slug
    end
  end
end
Roster.RaceSlug = raceSlug

-- Validation -------------------------------------------------------------------

local function text(v, max)
  if type(v) ~= "string" or v == "" then
    return nil
  end
  return v:sub(1, max or 80)
end

-- Characters of Forever have a first name and an optional surname; the full
-- name is both parts joined by the client's separator (a space). ns.PlayerName
-- (loaded later, so looked up on use) owns that rule, the inline form is the
-- same without it.
local function joinName(name, surname)
  if not name then
    return nil
  end
  local PN = ns.PlayerName
  if PN then
    local full = PN.Join(name, surname)
    return full ~= "" and full or nil
  end
  if not surname then
    return name
  end
  local c = Constants and Constants.CharacterNameSeparatorConsts
  return name .. ((c and c.CHARACTERNAME_SURNAME_SEPARATOR) or " ") .. surname
end
Roster.JoinName = joinName

local function number(v, lo, hi)
  if type(v) ~= "number" or v ~= v or v < lo or v > hi then
    return nil
  end
  return v
end

local function cleanProfessions(raw)
  local out = {}
  if type(raw) ~= "table" then
    return out
  end
  for _, p in ipairs(raw) do
    local name = type(p) == "table" and text(p.name, 40)
    if name and #out < MAX_PROFESSIONS then
      -- Entries of the first version stored `rank` and no kind.
      local id = number(p.id, 1, 1e8)
      out[#out + 1] = {
        name = name,
        skill = math.floor(number(p.skill, 0, 1000) or number(p.rank, 0, 1000) or 0),
        max = math.floor(number(p.max, 0, 1000) or 0),
        id = id and math.floor(id) or nil,
        kind = p.kind == "secondary" and "secondary" or "primary",
      }
    end
  end
  return out
end

local function professionsSig(list)
  local parts = {}
  for _, p in ipairs(cleanProfessions(list)) do
    parts[#parts + 1] = table.concat({ p.name, p.skill, p.max, p.id or "", p.kind }, ":")
  end
  return table.concat(parts, "|")
end

local MAX_TODO_VALUES = 100

local function cleanTodos(raw)
  local values, count = {}, 0
  for id, v in pairs(type(raw) == "table" and type(raw.values) == "table" and raw.values or {}) do
    if type(id) == "string" and id ~= "" and #id <= 40 and type(v) == "table" and count < MAX_TODO_VALUES then
      values[id] = { done = v.done == true, at = number(v.at, 0, 1e11) or 0 }
      count = count + 1
    end
  end
  return { values = values }
end

-- Fields with a reading time in `at` (server time of the reading that stored the value).
local AT_FIELDS = { "money", "ilvl", "zone", "guild", "level" }

local function cleanAt(raw)
  local out = {}
  if type(raw) == "table" then
    for _, field in ipairs(AT_FIELDS) do
      out[field] = number(raw[field], 1, 1e11)
    end
  end
  return out
end

-- A clean copy of a stored entry, nil when it cannot be a character (no name or
-- realm). Damaged single fields are dropped, the rest stays usable. Entries of the
-- first versions stored a failed reading as 0 gold or item level 0 without a reading
-- time: that 0 means "never read" and becomes nil. The race slug is derived from race
-- and faction when it is missing.
function Roster.Clean(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local name, realm = text(raw.name, 40), text(raw.realm, 60)
  if not (name and realm) then
    return nil
  end
  local surname = text(raw.surname, 40)
  local class = text(raw.class, 20)
  local level = number(raw.level, 1, 200)
  local money = number(raw.money, 0, 1e13)
  local ilvl = number(raw.ilvl, 0, 2000)
  local at = cleanAt(raw.at)
  if money == 0 and not at.money then
    money = nil
  end
  if ilvl == 0 and not at.ilvl then
    ilvl = nil
  end
  local race = text(raw.race, 30)
  local faction = (raw.faction == "A" or raw.faction == "H") and raw.faction or nil
  local zone = text(raw.zone)
  -- A reading time without its value says nothing.
  at.money = money and at.money or nil
  at.ilvl = ilvl and at.ilvl or nil
  at.zone = zone and at.zone or nil
  at.level = level and at.level or nil
  return {
    schema = 2,
    name = name,
    surname = surname,
    display = joinName(name, surname) or name,
    realm = realm,
    class = class and class:match("^%u[%u_]*$") and class or nil,
    race = race,
    raceSlug = text(raw.raceSlug, 40) or raceSlug(race, nil, faction),
    faction = faction,
    sex = (raw.sex == 2 or raw.sex == 3) and raw.sex or nil,
    level = level and math.floor(level) or nil,
    money = money and math.floor(money) or nil,
    zone = zone,
    subzone = text(raw.subzone),
    guild = text(raw.guild),
    ilvl = ilvl,
    at = at,
    played = number(raw.played, 0, 1e9),
    levelPlayed = number(raw.levelPlayed, 0, 1e9),
    playedAt = number(raw.playedAt, 0, 1e11),
    pvp = ns.RosterStatsLogic.CleanPvp(raw.pvp),
    rep = ns.RosterStatsLogic.CleanRep(raw.rep),
    stats = ns.RosterStatsLogic.CleanStats(raw.stats),
    professions = cleanProfessions(raw.professions),
    professionsAt = number(raw.professionsAt, 0, 1e11),
    seen = number(raw.seen, 0, 1e11) or 0,
    build = text(raw.build, 40),
    addon = text(raw.addon, 20),
    raids = ns.RaidLockLogic.CleanLocks(raw.raids),
    raidsAt = number(raw.raidsAt, 0, 1e11),
    todos = cleanTodos(raw.todos),
    kills = ns.RaidWeekLogic.CleanKills(raw.kills),
    access = ns.AccessLogic.CleanSaved(raw.access),
    order = number(raw.order, 1, 1e4),
    hidden = raw.hidden == true or nil,
  }
end

-- Storage -----------------------------------------------------------------------

-- The roster table, created on first write; a damaged value is replaced then.
local function store(create)
  local db = ns.db
  if type(db) ~= "table" then
    return nil
  end
  if type(db.roster) ~= "table" then
    if not create then
      return nil
    end
    db.roster = {}
  end
  return db.roster
end

-- Off only when the setting is explicitly false (on by default).
function Roster.Enabled()
  local s = ns.db and ns.db.settings
  return not (type(s) == "table" and s.saveRoster == false)
end

function Roster.SetEnabled(on)
  ns.Store.set("settings.saveRoster", on and true or false)
  if on then
    Roster.Schedule()
  end
end

-- Drops damaged entries and the oldest ones above the cap, never `keep`.
local function prune(t, keep)
  local count = 0
  for key, raw in pairs(t) do
    if type(key) ~= "string" or not Roster.Clean(raw) then
      t[key] = nil
    else
      count = count + 1
    end
  end
  while count > Roster.CAP do
    local oldest, oldestSeen
    for key, raw in pairs(t) do
      local seen = Roster.Clean(raw).seen
      if key ~= keep and (not oldestSeen or seen < oldestSeen) then
        oldest, oldestSeen = key, seen
      end
    end
    if not oldest then
      return
    end
    t[oldest] = nil
    count = count - 1
  end
end

-- Duplicates ---------------------------------------------------------------------

local function sameOrUnknown(a, b)
  return a == nil or b == nil or a == b
end

local function nameId(e)
  local PN = ns.PlayerName
  return PN and PN.Key(e.display) or e.display:lower()
end

-- Copies what `into` lacks from `from`, with the reading time of the field. A stored 0
-- for money or item level is a stale capture and gives way to a real value.
local function fillGaps(into, from)
  for k, v in pairs(from) do
    if k == "professions" then
      if #into.professions == 0 then
        into.professions = v
        into.professionsAt = from.professionsAt
      end
    elseif k == "played" then
      -- The level time and the reading time belong to the total they were read with.
      if into.played == nil then
        into.played, into.levelPlayed, into.playedAt = v, from.levelPlayed, from.playedAt
      end
    elseif k == "raids" then
      if #into.raids == 0 then
        into.raids = v
      end
    elseif k == "kills" then
      ns.RaidWeekLogic.MergeKills(into.kills, v)
    elseif k == "todos" then
      for id, value in pairs(v.values) do
        if into.todos.values[id] == nil then
          into.todos.values[id] = value
        end
      end
    elseif
      k ~= "seen"
      and k ~= "key"
      and k ~= "professionsAt"
      and k ~= "levelPlayed"
      and k ~= "playedAt"
      and k ~= "at"
      and k ~= "schema"
    then
      if into[k] == nil or ((k == "money" or k == "ilvl") and into[k] == 0 and type(v) == "number" and v > 0) then
        into[k] = v
        into.at[k] = from.at[k]
      end
    end
  end
end

-- Folds entries of one character (same full name, compatible class and faction)
-- into one. The newest entry wins and keeps `preferKey` when it is one of the
-- group, else the key from KeyFor. Single entries are left alone. Idempotent.
-- Returns the number of removed entries.
function Roster.Merge(t, preferKey)
  local list = {}
  for key, raw in pairs(t) do
    local e = type(key) == "string" and Roster.Clean(raw)
    if e then
      list[#list + 1] = { key = key, e = e }
    end
  end
  table.sort(list, function(a, b)
    if a.e.seen ~= b.e.seen then
      return a.e.seen > b.e.seen
    end
    if (a.key == preferKey) ~= (b.key == preferKey) then
      return a.key == preferKey
    end
    return a.key < b.key
  end)
  local groups, byName = {}, {}
  for _, item in ipairs(list) do
    local id = nameId(item.e)
    local home
    for _, g in ipairs(byName[id] or {}) do
      if sameOrUnknown(g.e.class, item.e.class) and sameOrUnknown(g.e.faction, item.e.faction) then
        home = g
        break
      end
    end
    if home then
      fillGaps(home.e, item.e)
      home.keys[#home.keys + 1] = item.key
    else
      local g = { e = item.e, keys = { item.key } }
      groups[#groups + 1] = g
      byName[id] = byName[id] or {}
      table.insert(byName[id], g)
    end
  end
  local removed = 0
  for _, g in ipairs(groups) do
    if #g.keys > 1 then
      local target = Roster.KeyFor(g.e.name, g.e.surname, g.e.realm) or g.keys[1]
      for _, key in ipairs(g.keys) do
        t[key] = nil
        if key == preferKey then
          target = key
        end
      end
      t[target] = g.e
      removed = removed + #g.keys - 1
    end
  end
  return removed
end

-- Reading the game -------------------------------------------------------------

local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
end

local function realmName()
  return text(try(GetNormalizedRealmName)) or text(try(GetRealmName))
end

local function playerName()
  local name, surname = try(UnitName, "player")
  name = text(name, 40)
  return name, name and text(surname, 40) or nil
end

-- The only place that builds a roster key: "<full name>-<realm>", the surname is
-- part of the full name. The realm loses spaces and hyphens, so GetRealmName
-- ("Forever WoW") and GetNormalizedRealmName ("ForeverWoW") give the same key.
function Roster.KeyFor(name, surname, realm)
  local full = joinName(name, surname)
  realm = type(realm) == "string" and realm:gsub(" ", ""):gsub("%-", "") or nil
  if full and realm and realm ~= "" then
    return full .. "-" .. realm
  end
end

function Roster.CurrentKey()
  local name, surname = playerName()
  return Roster.KeyFor(name, surname, realmName())
end

local function raceFaction(slug)
  for _, r in ipairs((ns.Data and ns.Data.Races) or {}) do
    if r.slug == slug then
      return r.f
    end
  end
end

-- Last readings of the logged-in character, kept in memory. The events feed it (Refresh), Capture
-- and Flush write it to the entry. { [field] = { v = value, at = server time of the reading } } for
-- the fields of AT_FIELDS (guild: v = false when the character has none), subzone is a plain string.
local cache = {}

-- A number replaces an earlier one only when it is above 0, or when there is none yet or the earlier
-- one is 0 itself. The client answers 0 for gold and item level while it is not ready (login, logout,
-- item data still loading), which must not wipe a good value.
local function usable(new, old)
  return type(new) == "number" and new == new and (new > 0 or old == nil or old == 0)
end

local function firstPositive(a, b)
  if type(a) == "number" and a > 0 then
    return a
  elseif type(b) == "number" and b > 0 then
    return b
  end
  return type(a) == "number" and a or b
end

local function remember(field, value, at)
  local old = cache[field]
  if usable(value, old and old.v) then
    cache[field] = { v = value, at = at }
  end
end

local function readMoney(at)
  remember("money", try(GetMoney), at)
end

local function readItemLevel(at)
  local average, equipped = try(GetAverageItemLevel)
  remember("ilvl", firstPositive(equipped, average), at)
end

local function readGuild(at)
  if try(IsInGuild) == false then
    cache.guild = { v = false, at = at }
    return
  end
  -- GetGuildInfo also returns the rank name; only the guild name is wanted, text() takes a length second.
  local guild = text((try(GetGuildInfo, "player")))
  if guild then
    cache.guild = { v = guild, at = at }
  end
end

-- Reads the volatile fields into the cache. Called by the events and before every Capture, never at
-- logout: the client no longer answers reliably then, the last good readings are in the cache.
function Roster.Refresh()
  local at = Roster.Now()
  readMoney(at)
  readItemLevel(at)
  remember("level", try(UnitLevel, "player"), at)
  local zone = text(try(GetZoneText))
  if zone then
    cache.zone = { v = zone, at = at }
  end
  cache.subzone = text(try(GetSubZoneText))
  readGuild(at)
end

-- Writes the current character's entry from the cache. Returns the key, nil when nothing was
-- written (setting off, no SavedVariables, character not known yet). The played time, PvP,
-- reputation and statistics are not read here (RosterStats.lua).
local function write()
  if not Roster.Enabled() then
    return nil
  end
  local key = Roster.CurrentKey()
  local t = key and store(true)
  if not t then
    return nil
  end
  local old = Roster.Clean(t[key]) or {}
  local name, surname = playerName()
  local _, class = try(UnitClass, "player")
  local raceName, raceToken = try(UnitRace, "player")
  local factionGroup = try(UnitFactionGroup, "player")
  local factionLetter = factionGroup == "Alliance" and "A" or factionGroup == "Horde" and "H" or nil
  local slug = raceSlug(raceToken, raceName, factionLetter or old.faction) or old.raceSlug
  local faction = factionLetter or raceFaction(slug) or old.faction
  local sex = try(UnitSex, "player")
  local version, buildNo = try(GetBuildInfo)
  local at = {}
  for _, field in ipairs(AT_FIELDS) do
    at[field] = old.at and old.at[field]
  end
  -- The cached reading when it is usable, else the stored value with its reading time.
  local function adopt(field)
    local c = cache[field]
    if c and (type(c.v) ~= "number" or usable(c.v, old[field])) then
      at[field] = c.at
      return c.v
    end
    return old[field]
  end
  local entry = {
    name = name,
    surname = surname,
    realm = text(try(GetRealmName)) or realmName(),
    class = class or old.class,
    race = text(raceToken) or old.race,
    raceSlug = slug,
    faction = faction,
    sex = (sex == 2 or sex == 3) and sex or old.sex,
    level = adopt("level"),
    money = adopt("money"),
    zone = adopt("zone"),
    subzone = cache.subzone,
    guild = adopt("guild"),
    ilvl = adopt("ilvl"),
    at = at,
    played = old.played,
    levelPlayed = old.levelPlayed,
    playedAt = old.playedAt,
    pvp = old.pvp,
    rep = old.rep,
    stats = old.stats,
    professions = old.professions,
    professionsAt = old.professionsAt,
    seen = U.now(),
    build = version and (version .. (buildNo and (" (" .. buildNo .. ")") or "")) or old.build,
    addon = ns.version,
    raids = old.raids,
    raidsAt = old.raidsAt,
    todos = old.todos,
    kills = old.kills,
    access = old.access,
    order = old.order,
    hidden = old.hidden,
  }
  t[key] = Roster.Clean(entry)
  Roster.Merge(t, key)
  prune(t, key)
  ns.Emit("FG_ROSTER_CHANGED")
  return key
end

-- Reads the game into the cache, then writes the entry.
function Roster.Capture()
  if not Roster.Enabled() then
    return nil
  end
  Roster.Refresh()
  return write()
end

-- Writes the entry from the cache alone, no new reading. For logout.
function Roster.Flush()
  return write()
end

-- Stores the professions (ProfessionLogic shape) with the time of the reading in the existing
-- entry of `key`. False without that entry or without professions. Only a changed list
-- is announced.
function Roster.SetProfessions(key, list, at)
  local t = store(false)
  local raw = t and t[key]
  local clean = cleanProfessions(list)
  if type(raw) ~= "table" or #clean == 0 then
    return false
  end
  local same = professionsSig(raw.professions) == professionsSig(clean)
  raw.professions = clean
  raw.professionsAt = number(at, 0, 1e11)
  if not same then
    ns.Emit("FG_ROSTER_CHANGED")
  end
  return true
end

-- Stores readings of RosterStats in the existing entry of `key`: part = { played, levelPlayed, pvp,
-- rep (list), stats (list) }, every field optional, only the ones with data are written. `at` is the
-- server time of the reading. Reputation and statistics merge into the stored lists. False without
-- that entry or without data; a repeated reading is stored but not announced.
function Roster.SetStats(key, part, at)
  local t = store(false)
  local raw = t and t[key]
  if type(raw) ~= "table" or type(part) ~= "table" then
    return false
  end
  local Logic = ns.RosterStatsLogic
  at = number(at, 0, 1e11)
  local wrote, changed = false, false

  local played = number(part.played, 0, 1e9)
  if played then
    local level = number(part.levelPlayed, 0, 1e9)
    changed = raw.played ~= played or raw.levelPlayed ~= level
    raw.played, raw.levelPlayed, raw.playedAt = played, level, at
    wrote = true
  end

  local function put(field, block, before)
    if block then
      block.at = at
      changed = changed or Logic.Sig(before) ~= Logic.Sig(block)
      raw[field] = block
      wrote = true
    end
  end
  local oldPvp = Logic.CleanPvp(raw.pvp)
  put("pvp", Logic.MergePvp(oldPvp, Logic.CleanPvp(part.pvp)), oldPvp)
  local oldRep, oldStats = Logic.CleanRep(raw.rep), Logic.CleanStats(raw.stats)
  local function filled(list)
    return type(list) == "table" and list[1] ~= nil
  end
  -- Without a new reading the stored list keeps its reading time.
  local rep = filled(part.rep) and Logic.MergeReputation(oldRep and oldRep.list, part.rep)
  local stats = filled(part.stats) and Logic.MergeStatistics(oldStats and oldStats.list, part.stats)
  put("rep", rep and { list = rep }, oldRep)
  put("stats", stats and { list = stats }, oldStats)

  if changed then
    ns.Emit("FG_ROSTER_CHANGED")
  end
  return wrote
end

-- Reading for the UI ----------------------------------------------------------

-- Clean entries (with .key and .current). Without opts: all, unsorted. With opts:
-- the shown ones (hidden ones only with opts.all), sorted by opts.sort or the saved
-- sort mode.
function Roster.List(opts)
  local out = {}
  local current = Roster.CurrentKey()
  local t = store(false)
  if t then
    Roster.Merge(t, current)
  end
  for key, raw in pairs(t or {}) do
    local entry = type(key) == "string" and Roster.Clean(raw)
    if entry then
      entry.key = key
      entry.current = key == current
      if not opts or opts.all or not entry.hidden then
        out[#out + 1] = entry
      end
    end
  end
  if opts then
    Roster.Sort(out, opts.sort or Roster.SortMode())
  end
  return out
end

local function byRecent(a, b)
  return a.seen > b.seen
end

local SORTS = {
  name = function(a, b)
    return a.display:lower() < b.display:lower()
  end,
  level = function(a, b)
    return (a.level or 0) > (b.level or 0)
  end,
  gold = function(a, b)
    return (a.money or 0) > (b.money or 0)
  end,
  seen = function(a, b)
    if a.current ~= b.current then
      return a.current
    end
    return byRecent(a, b)
  end,
  class = function(a, b)
    return (a.class or "~") < (b.class or "~")
  end,
  ilvl = function(a, b)
    return (a.ilvl or 0) > (b.ilvl or 0)
  end,
  -- Characters without a position (never moved) follow the placed ones, newest first.
  custom = function(a, b)
    if a.order and b.order then
      return a.order < b.order
    elseif a.order or b.order then
      return a.order ~= nil
    end
    return byRecent(a, b)
  end,
}
SORTS.recent = SORTS.seen

local SORT_MODES = { "recent", "name", "class", "level", "ilvl", "gold", "custom" }

-- mode: "seen" or "recent" (default, current character first), "name", "class", "level",
-- "ilvl", "gold" or "custom" (the saved order). Ties fall back to name and key, so the
-- order is stable.
function Roster.Sort(list, mode)
  local primary = SORTS[mode] or SORTS.seen
  table.sort(list, function(a, b)
    if primary(a, b) then
      return true
    elseif primary(b, a) then
      return false
    end
    local an, bn = a.display:lower(), b.display:lower()
    if an ~= bn then
      return an < bn
    end
    return a.key < b.key
  end)
  return list
end

-- Saved sort mode and row switches (account-wide, ns.db.rosterSort / rosterRows).
function Roster.SortMode()
  local mode = ns.db and ns.db.rosterSort
  for _, m in ipairs(SORT_MODES) do
    if m == mode then
      return mode
    end
  end
  return "recent"
end

function Roster.SetSortMode(mode)
  for _, m in ipairs(SORT_MODES) do
    if m == mode then
      ns.Store.set("rosterSort", mode)
      return true
    end
  end
  return false
end

-- A row without a saved switch uses `default` (on unless false).
function Roster.RowEnabled(id, default)
  local rows = ns.db and ns.db.rosterRows
  local v
  if type(rows) == "table" then
    v = rows[id]
  end
  if type(v) == "boolean" then
    return v
  end
  return default ~= false
end

function Roster.SetRow(id, on)
  if type(id) ~= "string" or id == "" or type(ns.db) ~= "table" then
    return
  end
  if type(ns.db.rosterRows) ~= "table" then
    ns.db.rosterRows = {}
  end
  ns.db.rosterRows[id] = on and true or false
  ns.Emit("FG_SETTING_CHANGED", "rosterRows", ns.db.rosterRows)
end

-- Position changes -------------------------------------------------------------------

-- Writes order 1..n in list order.
local function renumber(t, list)
  for i, e in ipairs(list) do
    t[e.key].order = i
  end
end

-- Puts the character at newIndex (clamped) among the shown ones and numbers them
-- 1..n without gaps. `mode` is the order the list is taken in first (default "custom";
-- pass the visible sort mode so a drag starts from what the user sees).
function Roster.Move(key, newIndex, mode)
  local t = store(false)
  local list = t and Roster.List({ sort = mode or "custom" }) or {}
  local from
  for i, e in ipairs(list) do
    if e.key == key then
      from = i
    end
  end
  if not from or type(newIndex) ~= "number" then
    return false
  end
  local moved = table.remove(list, from)
  table.insert(list, math.max(1, math.min(#list + 1, math.floor(newIndex))), moved)
  renumber(t, list)
  ns.Emit("FG_ROSTER_CHANGED")
  return true
end

-- Takes the character out of the overview. The data stays, the others close the gap.
function Roster.Hide(key)
  local t = store(false)
  if not (t and type(t[key]) == "table") then
    return false
  end
  local clean = Roster.Clean(t[key])
  local had = clean and clean.order
  t[key].hidden = true
  t[key].order = nil
  if had then
    renumber(t, Roster.List({ sort = "custom" }))
  end
  ns.Emit("FG_ROSTER_CHANGED")
  return true
end

-- Brings a hidden character back, last in the saved order.
function Roster.Restore(key)
  local t = store(false)
  if not (t and type(t[key]) == "table") then
    return false
  end
  local list = Roster.List({ sort = "custom" })
  t[key].hidden = nil
  if list[1] and list[1].order then
    renumber(t, list)
    t[key].order = #list + 1
  else
    t[key].order = nil
  end
  ns.Emit("FG_ROSTER_CHANGED")
  return true
end

-- The characters taken out of the overview, by name.
function Roster.ListHidden()
  local out = {}
  for _, e in ipairs(Roster.List({ all = true, sort = "name" })) do
    if e.hidden then
      out[#out + 1] = e
    end
  end
  return out
end

-- Deletes a character for good. The caller asks first. The current character is
-- refused: it would be written again at the next capture.
function Roster.Purge(key)
  if key == Roster.CurrentKey() then
    return false
  end
  return Roster.Forget(key)
end

-- Number of characters and the sum of their money in copper.
function Roster.Totals(list)
  local gold = 0
  for _, e in ipairs(list) do
    gold = gold + (e.money or 0)
  end
  return #list, gold
end

function Roster.Forget(key)
  local t = store(false)
  if t and t[key] ~= nil then
    t[key] = nil
    -- The item counts of the character go with it.
    if type(ns.db.inventory) == "table" then
      ns.db.inventory[key] = nil
    end
    ns.Emit("FG_ROSTER_CHANGED")
    return true
  end
  return false
end

-- Server time (UTC seconds) when the client has it, else the local clock.
function Roster.Now()
  local t = try(GetServerTime)
  return type(t) == "number" and t or U.now()
end

-- Whole days since `seen`, nil without a time.
function Roster.DaysSince(seen, now)
  if type(seen) ~= "number" or seen <= 0 then
    return nil
  end
  return math.max(0, math.floor(((now or U.now()) - seen) / 86400))
end

-- Server time of the oldest reading among the fields with a reading time, nil without one.
function Roster.AsOf(e)
  local oldest
  for _, field in ipairs(AT_FIELDS) do
    local at = e.at and e.at[field]
    if at and (not oldest or at < oldest) then
      oldest = at
    end
  end
  return oldest
end

-- Updates ------------------------------------------------------------------------

local function schedule()
  ns.Debounce("roster-update", UPDATE_DELAY, function()
    Roster.Capture()
  end)
end
Roster.Schedule = schedule

-- These events only schedule the capture, which reads the cache and writes the entry.
for _, event in ipairs({
  "PLAYER_LOGIN",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_LEVEL_UP",
  "ZONE_CHANGED_NEW_AREA",
  "PLAYER_EQUIPMENT_CHANGED",
}) do
  ns.On(event, schedule)
end

-- Gold, item level and guild take their reading into the cache at once, so the logout finds the
-- last one. The entry is written by the capture or at logout (the game saves the file then).
ns.On("PLAYER_MONEY", function()
  readMoney(Roster.Now())
  schedule()
end)

ns.On("PLAYER_AVG_ITEM_LEVEL_UPDATE", function()
  readItemLevel(Roster.Now())
end)

ns.On("PLAYER_GUILD_UPDATE", function()
  readGuild(Roster.Now())
end)

-- Item data arrives in bursts and finishes the item level: read it while there is no usable one
-- yet, at most once per ITEM_READ_GAP seconds. Afterwards the item level events keep it current.
local lastItemRead
ns.On("GET_ITEM_INFO_RECEIVED", function()
  local known = cache.ilvl
  if known and known.v > 0 then
    return
  end
  local now = try(GetTime)
  if now and lastItemRead and now - lastItemRead < ITEM_READ_GAP then
    return
  end
  lastItemRead = now
  readItemLevel(Roster.Now())
end)

-- The last write happens right away from the cache, a timer would not run any more and the client
-- no longer answers reliably.
ns.On("PLAYER_LOGOUT", function()
  Roster.Flush()
end)
