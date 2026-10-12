-- Sample guild for the guild page (/fg guild demo): about 40 members, the rights of three roles and
-- a list of players for the tab "Social". No game calls and nothing is stored: GuildData keeps the
-- one demo table in memory, it is gone after the demo ends or /reload. Rows go through
-- GuildLogic.Normalize like real roster rows, so the page cannot tell the difference.
local _, ns = ...
local GL, PN, L = ns.GuildLogic, ns.PlayerName, ns.L

local G = {}
ns.GuildDemo = G

G.ROLES = { "leader", "officer", "member" }
G.DEFAULT_ROLE = "leader"
local LAST_RANK = 5
-- Rank of the demo character per role.
local ROLE_RANK = { leader = 0, officer = 2, member = 4 }

local ALL_RIGHTS = {
  "CanGuildInvite",
  "CanGuildPromote",
  "CanGuildDemote",
  "CanGuildRemove",
  "CanEditPublicNote",
  "CanViewOfficerNote",
  "CanEditOfficerNote",
  "CanEditMOTD",
  "CanEditGuildInfo",
}
-- The officer may rank and write notes but neither remove nor change the guild text.
local OFFICER_RIGHTS = {
  CanGuildInvite = true,
  CanGuildPromote = true,
  CanGuildDemote = true,
  CanEditPublicNote = true,
  CanViewOfficerNote = true,
  CanEditOfficerNote = true,
}

ns.AddLocale("enUS", {
  ["guild.demo.name"] = "Sample Guild",
  ["guild.demo.motd"] = "Raid on Tuesday at 8 pm, sign up in the forum.",
  ["guild.demo.rank.0"] = "Guild master",
  ["guild.demo.rank.1"] = "Deputy",
  ["guild.demo.rank.2"] = "Officer",
  ["guild.demo.rank.3"] = "Veteran",
  ["guild.demo.rank.4"] = "Member",
  ["guild.demo.rank.5"] = "Recruit",
  ["guild.demo.zone.1"] = "Stormwind City",
  ["guild.demo.zone.2"] = "Orgrimmar",
  ["guild.demo.zone.3"] = "Ironforge",
  ["guild.demo.zone.4"] = "Thunder Bluff",
  ["guild.demo.zone.5"] = "Darnassus",
  ["guild.demo.zone.6"] = "Undercity",
  ["guild.demo.zone.7"] = "Stranglethorn Vale",
  ["guild.demo.zone.8"] = "Tanaris",
  ["guild.demo.zone.9"] = "Winterspring",
  ["guild.demo.zone.10"] = "Blackrock Depths",
  ["guild.demo.job.1"] = "Blacksmithing",
  ["guild.demo.job.2"] = "Mining",
  ["guild.demo.job.3"] = "Alchemy",
  ["guild.demo.job.4"] = "Herbalism",
  ["guild.demo.job.5"] = "Tailoring",
  ["guild.demo.job.6"] = "Enchanting",
  ["guild.demo.race.Human"] = "Human",
  ["guild.demo.race.Orc"] = "Orc",
  ["guild.demo.race.NightElf"] = "Night Elf",
  ["guild.demo.race.Dwarf"] = "Dwarf",
  ["guild.demo.race.Scourge"] = "Undead",
  ["guild.demo.race.Tauren"] = "Tauren",
  ["guild.demo.note.1"] = "Raid on Tuesday",
  ["guild.demo.note.2"] = "Tank",
  ["guild.demo.note.3"] = "Healer",
  ["guild.demo.note.4"] = "Smith, orders by whisper",
  ["guild.demo.note.5"] = "Away until the end of the month",
  ["guild.demo.note.6"] = "New, just joined",
  ["guild.demo.officer.1"] = "Warned about loot",
  ["guild.demo.officer.2"] = "Has guild bank access",
  ["guild.demo.officer.3"] = "Candidate for officer",
  ["guild.demo.officer.4"] = "Inactive for weeks",
  ["guild.demo.own.1"] = "Plans the Saturday raid",
  ["guild.demo.own.2"] = "Donates to the guild bank",
  ["guild.demo.own.3"] = "Wants to try tanking",
})
ns.AddLocale("deDE", {
  ["guild.demo.name"] = "Beispielgilde",
  ["guild.demo.motd"] = "Raid am Dienstag um 20 Uhr, Anmeldung im Forum.",
  ["guild.demo.rank.0"] = "Gildenleiter",
  ["guild.demo.rank.1"] = "Stellvertreter",
  ["guild.demo.rank.2"] = "Offizier",
  ["guild.demo.rank.3"] = "Veteran",
  ["guild.demo.rank.4"] = "Mitglied",
  ["guild.demo.rank.5"] = "Neuling",
  ["guild.demo.zone.1"] = "Sturmwind",
  ["guild.demo.zone.2"] = "Orgrimmar",
  ["guild.demo.zone.3"] = "Eisenschmiede",
  ["guild.demo.zone.4"] = "Donnerfels",
  ["guild.demo.zone.5"] = "Darnassus",
  ["guild.demo.zone.6"] = "Unterstadt",
  ["guild.demo.zone.7"] = "Schlingendorntal",
  ["guild.demo.zone.8"] = "Tanaris",
  ["guild.demo.zone.9"] = "Winterquell",
  ["guild.demo.zone.10"] = "Schwarzfelstiefen",
  ["guild.demo.job.1"] = "Schmiedekunst",
  ["guild.demo.job.2"] = "Bergbau",
  ["guild.demo.job.3"] = "Alchemie",
  ["guild.demo.job.4"] = "Kräuterkunde",
  ["guild.demo.job.5"] = "Schneiderei",
  ["guild.demo.job.6"] = "Verzauberkunst",
  ["guild.demo.race.Human"] = "Mensch",
  ["guild.demo.race.Orc"] = "Orc",
  ["guild.demo.race.NightElf"] = "Nachtelf",
  ["guild.demo.race.Dwarf"] = "Zwerg",
  ["guild.demo.race.Scourge"] = "Untoter",
  ["guild.demo.race.Tauren"] = "Tauren",
  ["guild.demo.note.1"] = "Raid am Dienstag",
  ["guild.demo.note.2"] = "Tank",
  ["guild.demo.note.3"] = "Heiler",
  ["guild.demo.note.4"] = "Schmied, Aufträge per Flüstern",
  ["guild.demo.note.5"] = "Weg bis Monatsende",
  ["guild.demo.note.6"] = "Neu, gerade beigetreten",
  ["guild.demo.officer.1"] = "Verwarnt wegen Beute",
  ["guild.demo.officer.2"] = "Hat Zugriff auf die Gildenbank",
  ["guild.demo.officer.3"] = "Kandidat für Offizier",
  ["guild.demo.officer.4"] = "Seit Wochen inaktiv",
  ["guild.demo.own.1"] = "Plant den Raid am Samstag",
  ["guild.demo.own.2"] = "Spendet an die Gildenbank",
  ["guild.demo.own.3"] = "Will Tanken ausprobieren",
})

local function key(prefix, n)
  return L[prefix .. n]
end

-- Members -------------------------------------------------------------------------------------------

-- last: nil while online, else { years, months, days, hours } as the game reports it.
-- extra: note, officer (index of the sample text), ilvl, jobs = { { job, skill } }, main (name of
-- the main), own (index of an own note of the GildenManager), leader. Sample texts are read when
-- the demo starts, in the language of that moment.
local function row(name, rank, level, class, zone, last, extra)
  extra = extra or {}
  return {
    name = name,
    rank = rank,
    level = level,
    class = class,
    zone = zone,
    last = last,
    note = extra.note and key("guild.demo.note.", extra.note) or "",
    officer = extra.officer and key("guild.demo.officer.", extra.officer) or "",
    ilvl = extra.ilvl,
    jobs = extra.jobs,
    main = extra.main,
    own = extra.own,
    leader = extra.leader,
  }
end

local function rows(selfName)
  local list = {
    row(
      "Thorwald Eisenfaust",
      0,
      60,
      "WARRIOR",
      1,
      nil,
      { leader = true, ilvl = 66, jobs = { { 1, 300 }, { 2, 300 } } }
    ),
    row("Mira Sonnental", 1, 60, "PRIEST", 1, nil, { note = 1, ilvl = 64, jobs = { { 6, 300 }, { 5, 285 } } }),
    row("Garrick Falkenhorst", 1, 60, "PALADIN", 3, { 0, 0, 1, 0 }, { officer = 2, ilvl = 63, own = 1 }),
    row("Lenya Nachtwind", 2, 60, "ROGUE", 7, nil, { ilvl = 61, jobs = { { 3, 300 }, { 4, 260 } }, own = 1 }),
    row("Brom Steinbrecher", 2, 59, "WARRIOR", 10, { 0, 0, 0, 5 }, { note = 2, ilvl = 60 }),
    row("Selene Mondlicht", 2, 58, "DRUID", 5, nil, { note = 3, ilvl = 58, jobs = { { 4, 300 }, { 3, 240 } } }),
    row("Ragnar Donnerhall", 2, 60, "SHAMAN", 4, { 0, 0, 3, 2 }, { officer = 3, ilvl = 59 }),
    row("Elara Wintersturm", 3, 57, "MAGE", 9, nil, { ilvl = 55, jobs = { { 6, 225 } } }),
    row("Doran Felsenherz", 3, 56, "HUNTER", 8, { 0, 0, 2, 0 }, { ilvl = 54 }),
    row("Isolde Rabenfeld", 3, 55, "WARLOCK", 6, nil, { ilvl = 52, jobs = { { 5, 300 } } }),
    row(
      "Kaspar Eisenhauer",
      3,
      54,
      "WARRIOR",
      1,
      { 0, 0, 6, 0 },
      { note = 2, ilvl = 53, jobs = { { 1, 250 }, { 2, 250 } } }
    ),
    row("Nora Silberquell", 3, 53, "PRIEST", 2, { 0, 0, 0, 12 }, { note = 3, ilvl = 50 }),
    row("Valdis Grauwolf", 3, 52, "HUNTER", 8, { 0, 1, 0, 0 }, { ilvl = 49 }),
    row("Tamsin Birkenfeld", 3, 51, "DRUID", 5, nil, { note = 5 }),
    row("Orik Schwarzbart", 3, 50, "PALADIN", 3, { 0, 0, 12, 0 }, { ilvl = 47 }),
    row("Fenja Aschenblatt", 3, 50, "ROGUE", 7, { 0, 0, 21, 0 }, { officer = 4 }),
    row("Jorin Weidenbach", 4, 48, "MAGE", 1, nil, { ilvl = 44 }),
    row("Liora Dornenstich", 4, 47, "ROGUE", 7, { 0, 0, 0, 3 }, { own = 2 }),
    row("Bastian Kupferkessel", 4, 46, "WARLOCK", 6, { 0, 0, 4, 0 }, { note = 4, jobs = { { 1, 180 } } }),
    row("Mathilda Wolkenbruch", 4, 45, "PRIEST", 5, { 0, 0, 9, 0 }),
    row("Cedric Nebelhain", 4, 44, "HUNTER", 8, nil, { ilvl = 41 }),
    row("Runa Frostauge", 4, 43, "SHAMAN", 4, { 0, 1, 3, 0 }),
    row("Anselm Brauneck", 4, 42, "WARRIOR", 2, { 0, 1, 15, 0 }, { officer = 1 }),
    row("Yara Sternfall", 4, 41, "DRUID", 9, { 0, 2, 0, 0 }, { note = 5 }),
    row("Hagen Lederstrumpf", 4, 40, "ROGUE", 1, { 0, 2, 15, 0 }),
    row("Wilma Tannenzapf", 4, 38, "MAGE", 3, { 0, 3, 0, 0 }),
    row("Konrad Eichenrinde", 4, 36, "PALADIN", 10, nil, { ilvl = 36 }),
    row("Sasha Morgentau", 4, 35, "PRIEST", 1, { 0, 0, 2, 18 }),
    row("Emil Kupferfeld", 4, 33, "WARRIOR", 6, { 0, 6, 0, 0 }),
    row("Ilka Birkenhain", 4, 31, "HUNTER", 8, { 1, 0, 0, 0 }, { main = "Valdis Grauwolf" }),
    row("Pelle Haselnuss", 5, 28, "ROGUE", 7, nil, { note = 6, main = "Lenya Nachtwind" }),
    row("Jonna Eichhorn", 5, 25, "DRUID", 5, { 0, 0, 0, 8 }, { note = 6 }),
    row("Tilo Brandt", 5, 22, "WARLOCK", 6, { 0, 0, 5, 0 }, { main = "Isolde Rabenfeld" }),
    row("Amira Seidenfaden", 5, 20, "MAGE", 1, { 0, 0, 14, 0 }, { own = 3 }),
    row("Finn Moorbach", 5, 18, "WARRIOR", 2, nil),
    row("Lotta Kieselstein", 5, 15, "PRIEST", 4, { 0, 1, 10, 0 }),
    row("Ben Wacholder", 5, 12, "HUNTER", 8, { 0, 4, 0, 0 }),
    row("Zora Pechmann", 5, 10, "SHAMAN", 4, { 0, 8, 0, 0 }, { main = "Ragnar Donnerhall" }),
    row("Kurt Nebelschwaden", 5, 8, "PALADIN", 3, { 1, 2, 0, 0 }),
  }
  -- The demo character: rank and rights follow the chosen role. A sample name of the same name goes.
  for i = #list, 1, -1 do
    if PN.Equal(list[i].name, selfName) then
      table.remove(list, i)
    end
  end
  local me = row(selfName, ROLE_RANK[G.DEFAULT_ROLE], 60, "WARRIOR", 1, nil, { ilvl = 57, jobs = { { 1, 225 } } })
  me.self = true
  list[#list + 1] = me
  for i, r in ipairs(list) do
    r.guid = "Demo-Player-" .. i
  end
  return list
end

local function raw(r, rank)
  local F = GL.FIELD
  local t = {}
  t[F.name], t[F.rankName], t[F.rankIndex] = r.name, key("guild.demo.rank.", rank), rank
  t[F.level], t[F.className] = r.level, ns.RefLogic.className(r.class)
  t[F.zone] = key("guild.demo.zone.", r.zone)
  t[F.note], t[F.officerNote] = r.note, r.officer
  t[F.online], t[F.classFile], t[F.guid] = r.last == nil, r.class, r.guid
  return t
end

-- The snapshot GuildData.Get answers, built again after every change of the rows.
local function build(demo)
  local snap = {
    inGuild = true,
    loaded = true,
    name = L["guild.demo.name"],
    rankName = key("guild.demo.rank.", ROLE_RANK[demo.role]),
    motd = L["guild.demo.motd"],
    members = {},
    ranks = {},
    online = 0,
  }
  for _, r in ipairs(demo.rows) do
    -- With the master role the demo character is the guild master, the sample master leaves.
    if not (r.leader and demo.role == "leader") then
      local m = GL.Normalize(#snap.members + 1, raw(r, r.rank), r.last)
      snap.members[#snap.members + 1] = m
      if m.online then
        snap.online = snap.online + 1
      end
    end
  end
  for rank = 0, LAST_RANK do
    snap.ranks[#snap.ranks + 1] = { index = rank, name = key("guild.demo.rank.", rank) }
  end
  demo.snap = snap
end

-- Peers --------------------------------------------------------------------------------------------

local SOURCES = { "game", "addon", "manual" }

local function peer(now, i, ilvl, jobs)
  local professions = {}
  for _, j in ipairs(jobs or {}) do
    professions[#professions + 1] = { name = key("guild.demo.job.", j[1]), skill = j[2], max = 300 }
  end
  return {
    ilvl = ilvl,
    professions = GL.CleanProfessions(professions),
    at = now - (i * 7 + 2) * 3600,
    source = SOURCES[i % #SOURCES + 1],
  }
end

-- Recently seen players ----------------------------------------------------------------------------

local HOUR, DAY = 3600, 86400

-- name, class, level, zone, source, race, age in seconds
local SEEN = {
  { "Alaric Dunkelwald", "MAGE", 60, 7, "group", "Human", 0.5 * HOUR },
  { "Brienne Tannhauser", "PRIEST", 58, 7, "group", "Human", 2 * HOUR },
  { "Corvin Aschgrau", "ROGUE", 60, 8, "group", "NightElf", 5 * HOUR },
  { "Dagny Eisenfuss", "WARRIOR", 55, 3, "group", "Dwarf", 1 * DAY },
  { "Eberhard Mohnblatt", "HUNTER", 52, 8, "group", "Dwarf", 2 * DAY },
  { "Freya Silberzunge", "DRUID", 49, 5, "group", "NightElf", 4 * DAY },
  { "Gunnar Blutaxt", "WARRIOR", 60, 10, "raid", "Orc", 3 * HOUR },
  { "Hilde Schattenstreif", "WARLOCK", 60, 10, "raid", "Scourge", 3 * HOUR },
  { "Ingvar Steinfaust", "SHAMAN", 59, 10, "raid", "Tauren", 4 * HOUR },
  { "Jasmin Nebelpfad", "PRIEST", 60, 10, "raid", "Human", 5 * HOUR },
  { "Karsten Funkenflug", "MAGE", 58, 10, "raid", "Human", 1 * DAY },
  { "Leona Rosenthal", "PALADIN", 60, 10, "raid", "Human", 1 * DAY },
  { "Magnus Tiefenbach", "WARRIOR", 34, 3, "dungeon", "Dwarf", 6 * HOUR },
  { "Nele Wiesengrund", "DRUID", 33, 4, "dungeon", "Tauren", 6 * HOUR },
  { "Olaf Kohlenbrand", "WARLOCK", 35, 6, "dungeon", "Scourge", 7 * HOUR },
  { "Paula Federkiel", "ROGUE", 34, 7, "dungeon", "Orc", 7 * HOUR },
  { "Quentin Lichtfang", "PRIEST", 36, 2, "dungeon", "Orc", 3 * DAY },
  { "Rosalind Tuchmacher", "MAGE", 41, 1, "trade", "Human", 12 * HOUR },
  { "Sigmund Erzgrube", "WARRIOR", 60, 3, "trade", "Dwarf", 2 * DAY },
  { "Thea Kräuterhain", "DRUID", 47, 4, "trade", "Tauren", 5 * DAY },
  { "Ulf Bergmann", "SHAMAN", 52, 2, "trade", "Orc", 9 * DAY },
  { "Elara Wintersturm", "MAGE", 57, 9, "guild", "Human", 1 * HOUR },
  { "Doran Felsenherz", "HUNTER", 56, 8, "guild", "Dwarf", 2 * DAY },
  { "Kaspar Eisenhauer", "WARRIOR", 54, 1, "guild", "Human", 6 * DAY },
  { "Vera Morgenrot", "PALADIN", 60, 1, "target", "Human", 8 * HOUR },
  { "Wotan Grimmbart", "HUNTER", 45, 8, "target", "Dwarf", 3 * DAY },
  { "Xenia Nachtschatten", "ROGUE", 38, 5, "target", "NightElf", 12 * DAY },
}

local function seenList(now)
  local list = {}
  for _, s in ipairs(SEEN) do
    list[#list + 1] = {
      name = s[1],
      class = s[2],
      level = s[3],
      zone = key("guild.demo.zone.", s[4]),
      src = s[5],
      race = s[6],
      raceName = L["guild.demo.race." .. s[6]],
      t = now - s[7],
    }
  end
  return GL.CleanSeen(list)
end

-- Public --------------------------------------------------------------------------------------------

-- A new demo: { role, rows, snap, seen, peers }. selfName: the own character, it takes part as a member.
function G.New(selfName, now)
  selfName = PN.Normalize(type(selfName) == "string" and selfName or "")
  if selfName == "" then
    selfName = "Demo"
  end
  local demo = { role = G.DEFAULT_ROLE, rows = rows(selfName), peers = {}, seen = seenList(now) }
  for i, r in ipairs(demo.rows) do
    if r.ilvl then
      demo.peers[PN.Key(r.name)] = peer(now, i, r.ilvl, r.jobs)
    end
  end
  for i, s in ipairs(demo.seen) do
    if not demo.peers[PN.Key(s.name)] and i % 3 == 0 then
      demo.peers[PN.Key(s.name)] = peer(now, i, 40 + i, { { 1 + i % 6, 100 + i * 5 } })
    end
  end
  build(demo)
  return demo
end

-- False for a role that does not exist. The rank of the demo character follows.
function G.SetRole(demo, role)
  if not ROLE_RANK[role] then
    return false
  end
  demo.role = role
  for _, r in ipairs(demo.rows) do
    if r.self then
      r.rank = ROLE_RANK[role]
    end
  end
  build(demo)
  return true
end

-- One right as the game names it (CanGuildPromote, ...) for the role of the demo.
function G.Can(demo, name)
  if demo.role == "leader" then
    for _, right in ipairs(ALL_RIGHTS) do
      if right == name then
        return true
      end
    end
    return false
  end
  return demo.role == "officer" and OFFICER_RIGHTS[name] == true
end

-- A confirmed action of the GildenManager on the sample rows. promote, demote, remove, editNote and
-- editOfficerNote change the rows (never the demo character); false when nothing changed.
function G.Apply(demo, action, memberKey, value)
  for i, r in ipairs(demo.rows) do
    if not r.self and PN.Key(r.name) == memberKey then
      if action == "promote" and r.rank > 1 then
        r.rank = r.rank - 1
      elseif action == "demote" and r.rank < LAST_RANK then
        r.rank = r.rank + 1
      elseif action == "remove" then
        table.remove(demo.rows, i)
      elseif action == "editNote" then
        r.note = tostring(value or "")
      elseif action == "editOfficerNote" then
        r.officer = tostring(value or "")
      else
        return false
      end
      build(demo)
      return true
    end
  end
  return false
end

-- Main and own note per sample member for the GildenManager: { { name, main, own } }.
function G.Extras(demo)
  local out = {}
  for _, r in ipairs(demo.rows) do
    if r.main or r.own then
      out[#out + 1] = { name = r.name, main = r.main, own = r.own and key("guild.demo.own.", r.own) or nil }
    end
  end
  return out
end

function G.Peer(demo, name)
  return demo.peers[PN.Key(name)]
end
