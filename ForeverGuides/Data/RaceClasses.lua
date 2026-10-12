-- Rassen-Klassen-Zuordnung von WoW Forever: welche Klasse welche Rasse spielen darf.
-- Abgeleitet aus der Live-Seite forever-guides.com/de/wow-forever/races
-- (availableClassIds und newClassIds, Stand 2026-10-06), bis der Web-Generator
-- diese Datei selbst ausgibt. Schluessel sind die Rassen-Slugs aus Meta.lua.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.RaceClasses = {
  -- Rasse -> Klassen-Token -> true, wenn die Klasse in Forever auf dieser Rasse spielbar ist.
  byRace = {
    ["human"] = {WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,MAGE=true,WARLOCK=true},
    ["dwarf"] = {WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,SHAMAN=true},
    ["night-elf"] = {WARRIOR=true,HUNTER=true,ROGUE=true,PRIEST=true,DRUID=true},
    ["gnome"] = {WARRIOR=true,ROGUE=true,PRIEST=true,MAGE=true,WARLOCK=true},
    ["high-order-skyborne"] = {WARRIOR=true,HUNTER=true,ROGUE=true,MAGE=true,DRUID=true},
    ["orc"] = {WARRIOR=true,HUNTER=true,ROGUE=true,SHAMAN=true,MAGE=true,WARLOCK=true},
    ["undead"] = {WARRIOR=true,PALADIN=true,ROGUE=true,PRIEST=true,MAGE=true,WARLOCK=true},
    ["tauren"] = {WARRIOR=true,HUNTER=true,SHAMAN=true,DRUID=true},
    ["troll"] = {WARRIOR=true,HUNTER=true,ROGUE=true,PRIEST=true,SHAMAN=true,MAGE=true,WARLOCK=true},
    ["windshaper-skyborne"] = {WARRIOR=true,HUNTER=true,ROGUE=true,SHAMAN=true,MAGE=true,DRUID=true},
  },
  -- Davon die Kombinationen, die in Forever neu sind (nicht im klassischen WoW).
  new = {
    ["human"] = {HUNTER=true},
    ["dwarf"] = {SHAMAN=true},
    ["night-elf"] = {},
    ["gnome"] = {PRIEST=true},
    ["high-order-skyborne"] = {WARRIOR=true,HUNTER=true,ROGUE=true,MAGE=true,DRUID=true},
    ["orc"] = {MAGE=true},
    ["undead"] = {PALADIN=true},
    ["tauren"] = {},
    ["troll"] = {WARLOCK=true},
    ["windshaper-skyborne"] = {WARRIOR=true,HUNTER=true,ROGUE=true,SHAMAN=true,MAGE=true,DRUID=true},
  },
}
