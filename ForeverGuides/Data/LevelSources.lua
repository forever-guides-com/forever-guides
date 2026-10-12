-- Stufenliste: Fertigkeiten, die nicht beim Lehrer, sondern ueber eine Quest
-- kommen. Abgeleitet aus der Live-Seite forever-guides.com/de/wow-forever/faehigkeiten
-- (Ansicht Stufenliste, Stand 2026-10-06), bis der Web-Generator diese Datei
-- selbst ausgibt. Klasse -> englischer Faehigkeitsname (wie in Abilities_*.lua).
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.LevelSources = {
  quest = {
    WARRIOR = { ["Defensive Stance"] = true, ["Berserker Stance"] = true },
    PALADIN = { ["Summon Warhorse"] = true, ["Summon Charger"] = true },
    WARLOCK = { ["Summon Voidwalker"] = true, ["Summon Succubus"] = true, ["Summon Felhunter"] = true },
    DRUID = { ["Bear Form"] = true, ["Aquatic Form"] = true, ["Cat Form"] = true, ["Travel Form"] = true },
  },
}
