-- Waffenmeister: Rassen-Startfertigkeiten und Bestaetigungsstatus.
-- Abgeleitet aus der Live-Seite forever-guides.com/de/wow-forever/waffenmeister
-- (Stand 2026-10-06), bis der Web-Generator diese Datei selbst ausgibt.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.WeaponRaces = {
  -- Reihenfolge wie auf der Website: Allianz zuerst, dann Horde.
  races = {
    {f="A",n={de="Mensch",en="Human"},s="human"},
    {f="A",n={de="Zwerg",en="Dwarf"},s="dwarf"},
    {f="A",n={de="Nachtelf",en="Night Elf"},s="night-elf"},
    {f="A",n={de="Gnom",en="Gnome"},s="gnome"},
    {f="A",n={de="Himmelsgeborener des Hohen Ordens",en="High Order Skyborne"},s="high-order-skyborne"},
    {f="H",n={de="Orc",en="Orc"},s="orc"},
    {f="H",n={de="Untoter",en="Undead"},s="undead"},
    {f="H",n={de="Tauren",en="Tauren"},s="tauren"},
    {f="H",n={de="Troll",en="Troll"},s="troll"},
    {f="H",n={de="Himmelsgeborener der Windformer",en="Windshaper Skyborne"},s="windshaper-skyborne"},
  },
  -- Klasse -> Fertigkeit -> Rassen, die sie von Anfang an kennen (kein Lehrer noetig).
  start = {
    WARRIOR = {
      bow = {"high-order-skyborne","windshaper-skyborne"},
      dagger = {"night-elf","gnome","high-order-skyborne","undead","troll","windshaper-skyborne"},
      axe1h = {"human","dwarf","orc","tauren","troll"},
      sword1h = {"human","night-elf","gnome","high-order-skyborne","orc","undead","windshaper-skyborne"},
      mace1h = {"human","dwarf","night-elf","gnome","high-order-skyborne","tauren","windshaper-skyborne"},
      thrown = {"high-order-skyborne","troll","windshaper-skyborne"},
      axe2h = {"dwarf","orc"},
      sword2h = {"high-order-skyborne","undead","windshaper-skyborne"},
      mace2h = {"high-order-skyborne","tauren","windshaper-skyborne"},
      mail = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      leather = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      shield = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
    },
    PALADIN = {
      mace1h = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      mace2h = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      mail = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      leather = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      shield = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
    },
    HUNTER = {
      bow = {"human","night-elf","high-order-skyborne","orc","troll","windshaper-skyborne"},
      dagger = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      axe1h = {"dwarf","orc","tauren","troll"},
      sword1h = {"high-order-skyborne","windshaper-skyborne"},
      gun = {"dwarf","tauren"},
      sword2h = {"high-order-skyborne","windshaper-skyborne"},
      leather = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
    },
    ROGUE = {
      bow = {"high-order-skyborne","windshaper-skyborne"},
      dagger = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      sword1h = {"high-order-skyborne","windshaper-skyborne"},
      mace1h = {"high-order-skyborne","windshaper-skyborne"},
      thrown = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      leather = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
    },
    PRIEST = {
      mace1h = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      wand = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
    },
    SHAMAN = {
      dagger = {"high-order-skyborne","windshaper-skyborne"},
      mace1h = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      staff = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      mace2h = {"high-order-skyborne","windshaper-skyborne"},
      leather = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      shield = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
    },
    MAGE = {
      dagger = {"high-order-skyborne","windshaper-skyborne"},
      staff = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      wand = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
    },
    WARLOCK = {
      dagger = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      wand = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
    },
    DRUID = {
      dagger = {"night-elf","high-order-skyborne","windshaper-skyborne"},
      mace1h = {"high-order-skyborne","tauren","windshaper-skyborne"},
      staff = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
      mace2h = {"high-order-skyborne","windshaper-skyborne"},
      leather = {"human","dwarf","night-elf","gnome","high-order-skyborne","orc","undead","tauren","troll","windshaper-skyborne"},
    },
  },
  -- Fertigkeiten, die die Website noch als unbestaetigt fuehrt: Klasse -> Fertigkeit.
  unconfirmedSkills = {
    WARRIOR = {polearm=true,parry=true},
    PALADIN = {polearm=true,parry=true},
    HUNTER = {polearm=true,thrown=true,parry=true},
    ROGUE = {thrown=true,parry=true},
    DRUID = {polearm=true},
  },
  -- Lehrer, deren Ort die Website als nicht bestaetigt markiert.
  unconfirmedTrainers = {
    ["woo-ping"] = true,
    ["buliwyf-stonehand"] = true,
    ["bixi-wobblebonk"] = true,
    ["ilyenia-moonfire"] = true,
    ["sayoc"] = true,
    ["hanashi"] = true,
    ["ansekhwa"] = true,
    ["archibald"] = true,
  },
}
