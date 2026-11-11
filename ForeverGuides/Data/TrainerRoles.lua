-- Trainer roles overlay, maintained by hand (not generated). Trainers.lua only
-- knows class trainers; the pet trainers of the hunter are listed here until the
-- web generator ships them. NPC ids and positions are checked against the
-- Classic NPC data.
-- Logic: Modules/TrainerRoles.lua.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.TrainerRoles = {
  -- roles[npcId] = "pet" for the pet trainers below with a known NPC id.
  -- Never put a spell id here: 5149 is the spell Beast Training, the
  -- NPC 5149 is the paladin trainer Brandur Ironhammer.
  roles = {
    [543] = "pet",
    [2878] = "pet",
    [2879] = "pet",
    [3306] = "pet",
    [3545] = "pet",
    [3620] = "pet",
    [3622] = "pet",
    [3624] = "pet",
    [3688] = "pet",
    [3698] = "pet",
    [4320] = "pet",
    [10086] = "pet",
    [10088] = "pet",
    [10089] = "pet",
    [10090] = "pet",
  },
  -- Pet trainers by English name. f = faction, zone = English zone name as in
  -- Trainers.zones (without a match the trainer is recognised by name but not
  -- listed), p = place inside the zone. npc, x and y (zone percent 0-100, x right,
  -- y down) are optional, entries without them have no coordinates.
  petNames = {
    { f = "A", en = "Peria Lamenur", zone = "Dun Morogh", p = "Kharanos", npc = 2878, x = 46.7, y = 54 },
    { f = "A", en = "Belia Thundergranite", zone = "Ironforge", p = "Ironforge", npc = 10090, x = 70.9, y = 85.8 },
    { f = "A", en = "Alma Deering", zone = "Stormwind City", p = "Stormwind" },
    { f = "A", en = "Karrina Mekenda", zone = "Stormwind City", p = "Stormwind", npc = 2879, x = 61.6, y = 16 },
    { f = "A", en = "Camille Taylor", zone = "Stormwind City", p = "Stormwind" },
    { f = "A", en = "Keldas", zone = "Teldrassil", p = "Dolanaar", npc = 3306, x = 56.8, y = 59.8 },
    { f = "A", en = "Silvaria", zone = "Darnassus", p = "Darnassus", npc = 10089, x = 42.5, y = 9.2 },
    { f = "A", en = "Clau" .. "de Erksine", zone = "The Hinterlands", p = "Farstrider Lodge", npc = 3545 },
    { f = "A", en = "Bolyun", zone = "Ashenvale", p = "Bolyun's Camp", npc = 3698, x = 18, y = 60 },
    { f = "A", en = "Caelyb", zone = "Ashenvale", p = "Ashenvale", npc = 4320, x = 49.7, y = 67 },
    { f = "A", en = "Nalesette Wildbringer", zone = "Felwood", p = "Felwood", npc = 543, x = 62.2, y = 24.4 },
    { f = "H", en = "Harruk", zone = "Durotar", p = "Razor Hill", npc = 3620, x = 52, y = 43.5 },
    { f = "H", en = "Drukma", zone = "Orgrimmar", p = "Orgrimmar" },
    { f = "H", en = "Nathoka Bloodfang", zone = "Orgrimmar", p = "Orgrimmar" },
    { f = "H", en = "Xao'tsu", zone = "Orgrimmar", p = "Orgrimmar", npc = 10088, x = 66.3, y = 14.8 },
    { f = "H", en = "Zudd", zone = "Stranglethorn Vale", p = "Grom'gol Base Camp", npc = 3624, x = 31.1, y = 28.9 },
    { f = "H", en = "Grokor", zone = "Swamp of Sorrows", p = "Stonard", npc = 3622, x = 47.4, y = 52.9 },
    { f = "H", en = "Reban Freerunner", zone = "Mulgore", p = "Bloodhoof Village", npc = 3688, x = 47.7, y = 55.7 },
    { f = "H", en = "Hesuwa Thunderhorn", zone = "Thunder Bluff", p = "Thunder Bluff", npc = 10086, x = 54.1, y = 84 },
  },
}
