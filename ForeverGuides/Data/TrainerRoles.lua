-- Trainer roles overlay, maintained by hand (not generated). Trainers.lua only
-- knows class trainers; the pet trainers of the hunter are listed here until the
-- web generator ships them.
-- Logic: Modules/TrainerRoles.lua.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.TrainerRoles = {
  -- roles[npcId] = "pet", filled as soon as NPC ids are verified in game.
  -- Never put a spell id here: 5149 is the spell Beast Training, the
  -- NPC 5149 is the paladin trainer Brandur Ironhammer.
  roles = {},
  -- Pet trainers by English name. f = faction, zone = English zone name as in
  -- Trainers.zones (without a match the trainer is recognised by name but not
  -- listed), p = place inside the zone. No coordinates are known.
  petNames = {
    { f = "A", en = "Peria Lamenur", zone = "Dun Morogh", p = "Kharanos" },
    { f = "A", en = "Belia Thundergranite", zone = "Ironforge", p = "Ironforge" },
    { f = "A", en = "Alma Deering", zone = "Stormwind City", p = "Stormwind" },
    { f = "A", en = "Karrina Mekenda", zone = "Stormwind City", p = "Stormwind" },
    { f = "A", en = "Camille Taylor", zone = "Stormwind City", p = "Stormwind" },
    { f = "A", en = "Keldas", zone = "Teldrassil", p = "Dolanaar" },
    { f = "A", en = "Silvaria", zone = "Darnassus", p = "Darnassus" },
    { f = "A", en = "Clau" .. "de Erksine", zone = "The Hinterlands", p = "Farstrider Lodge" },
    { f = "A", en = "Bolyun", zone = "Ashenvale", p = "Bolyun's Camp" },
    { f = "H", en = "Harruk", zone = "Durotar", p = "Razor Hill" },
    { f = "H", en = "Drukma", zone = "Orgrimmar", p = "Orgrimmar" },
    { f = "H", en = "Nathoka Bloodfang", zone = "Orgrimmar", p = "Orgrimmar" },
    { f = "H", en = "Zudd", zone = "Stranglethorn Vale", p = "Grom'gol Base Camp" },
    { f = "H", en = "Grokor", zone = "Swamp of Sorrows", p = "Stonard" },
    { f = "H", en = "Reban Freerunner", zone = "Mulgore", p = "Bloodhoof Village" },
    { f = "H", en = "Hesuwa Thunderhorn", zone = "Thunder Bluff", p = "Thunder Bluff" },
  },
}
