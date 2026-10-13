-- Trainer roles: tells class trainers from pet trainers. A pet trainer opens the
-- same trainer window but only teaches the hunter's pet, so the trainer page
-- shows it apart. Pure logic over ns.Data.TrainerRoles (hand-made overlay) and
-- the zone list of ns.Data.Trainers, no WoW API.
local _, ns = ...

local TR = {}
ns.TrainerRoles = TR

-- Note texts shown with a pet trainer, { de, en } like all data names.
TR.NOTE_PET = {
  de = "Lehrt nur Begleiter-Fähigkeiten, keine Jäger-Zauber.",
  en = "Teaches pet abilities only, no hunter spells.",
}
TR.NOTE_LIST = { de = "Standort ohne Koordinaten", en = "Location without coordinates" }

-- Words of an NPC subtitle that mark a pet trainer (lower case, plain match).
local SUBTITLE_WORDS = { "pet trainer", "beast training", "begleiter" }

-- Pet abilities a pet trainer sells and a class trainer never does (English
-- names as in Spells_HUNTER). Beast Training is no signal: hunter class
-- trainers teach that spell too.
local PET_SKILLS = {
  "Bite",
  "Claw",
  "Cower",
  "Dash",
  "Dive",
  "Furious Howl",
  "Growl",
  "Lightning Breath",
  "Prowl",
  "Scorpid Poison",
  "Shell Shield",
  "Thunderstomp",
}

local function data()
  return (ns.Data and ns.Data.TrainerRoles) or {}
end

local function lower(s)
  return type(s) == "string" and s:lower() or nil
end

local function petByName(name)
  name = lower(name)
  if not name then
    return false
  end
  for _, p in ipairs(data().petNames or {}) do
    if p.en:lower() == name then
      return true
    end
  end
  return false
end

-- "pet" when the entry is a known pet trainer (its own role field, NPC id or
-- English/German name), else "class". Accepts a data trainer ({n = {de, en}}),
-- a recorded sighting ({name}) and a capture candidate ({npc, name}).
function TR.Of(entry)
  if type(entry) ~= "table" then
    return "class"
  end
  if entry.role == "pet" then
    return "pet"
  end
  if type(entry.npc) == "number" and (data().roles or {})[entry.npc] == "pet" then
    return "pet"
  end
  if petByName(entry.name) then
    return "pet"
  end
  if type(entry.n) == "table" and (petByName(entry.n.en) or petByName(entry.n.de)) then
    return "pet"
  end
  return "class"
end

-- True when an NPC subtitle ("Pet Trainer", "Beast Training") names a pet trainer.
function TR.IsPetSubtitle(text)
  text = lower(text)
  if not text then
    return false
  end
  for _, word in ipairs(SUBTITLE_WORDS) do
    if text:find(word, 1, true) then
      return true
    end
  end
  return false
end

local skillSet
-- Lower case names of the pet abilities in English and in the client language
-- of the spell data.
local function petSkillSet()
  if skillSet then
    return skillSet
  end
  skillSet = {}
  local wanted = {}
  for _, name in ipairs(PET_SKILLS) do
    wanted[name] = true
    skillSet[name:lower()] = true
  end
  for _, s in ipairs((ns.Data and ns.Data.Spells and ns.Data.Spells.HUNTER) or {}) do
    if type(s.n) == "table" and wanted[s.n.en] and s.n.de then
      skillSet[s.n.de:lower()] = true
    end
  end
  return skillSet
end

-- True when every offered service is a pet ability: names = { "Claw", ... }.
-- An empty list or one unreadable name gives false, the offer is no evidence then.
function TR.OfferIsPet(names)
  if type(names) ~= "table" or #names == 0 then
    return false
  end
  local set = petSkillSet()
  for _, name in ipairs(names) do
    if not (type(name) == "string" and set[name:lower()]) then
      return false
    end
  end
  return true
end

local function zoneIndex(en)
  for i, z in ipairs((ns.Data and ns.Data.Trainers and ns.Data.Trainers.zones) or {}) do
    if z.en == en then
      return i
    end
  end
end

local function slug(name)
  return (name:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

-- Pet trainers of the overlay whose zone is in the trainer zone list, shaped like
-- data trainers of class HUNTER. They carry no coordinates (nothing to put on a
-- map) and confidence 1. Names stay English, the overlay has no verified German ones.
function TR.Entries(class, faction)
  local out = {}
  if class and class ~= "HUNTER" then
    return out
  end
  local zones = (ns.Data and ns.Data.Trainers and ns.Data.Trainers.zones) or {}
  for _, p in ipairs(data().petNames or {}) do
    local z = zoneIndex(p.zone)
    if z and (not faction or faction == "all" or p.f == faction) then
      out[#out + 1] = {
        id = "pet-" .. slug(p.en),
        c = "HUNTER",
        f = p.f,
        k = zones[z].m and "capital" or "town",
        role = "pet",
        n = { de = p.en, en = p.en },
        p = p.p,
        z = z,
        cf = 1,
        nt = {
          de = TR.NOTE_PET.de .. " " .. TR.NOTE_LIST.de .. ".",
          en = TR.NOTE_PET.en .. " " .. TR.NOTE_LIST.en .. ".",
        },
      }
    end
  end
  return out
end
