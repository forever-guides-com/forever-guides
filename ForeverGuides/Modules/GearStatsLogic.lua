-- Totals of the gear stats of one player, computed from the worn items only (no game API, no
-- frames). The input is plain data per slot, see G.Compute. Two sources are read per item: the
-- stat table of the item (keys like ITEM_MOD_STAMINA_SHORT) and the lines of its tooltip
-- ("Equip: ..." lines, "+12 Stamina", enchant and gem lines). Per slot and stat the larger of both
-- counts, so a value the game shows twice is not added twice; enchant lines always add on top.
local _, ns = ...

local G = {}
ns.GearStatsLogic = G

G.GROUPS = { "primary", "stamina", "attack", "spell", "defense", "regen", "resist" }

-- id, group, unit ("flat", "percent" or "rating") and the stat keys that carry the value.
local SCHOOLS = {
  { "Arcane", "arcane", "arkan" },
  { "Fire", "fire", "feuer" },
  { "Frost", "frost", "frost" },
  { "Nature", "nature", "natur" },
  { "Shadow", "shadow", "schatten" },
  { "Holy", "holy", "heilig" },
}
G.STATS = {
  { id = "strength", group = "primary", keys = { "ITEM_MOD_STRENGTH_SHORT" } },
  { id = "agility", group = "primary", keys = { "ITEM_MOD_AGILITY_SHORT" } },
  { id = "intellect", group = "primary", keys = { "ITEM_MOD_INTELLECT_SHORT" } },
  { id = "spirit", group = "primary", keys = { "ITEM_MOD_SPIRIT_SHORT" } },
  { id = "stamina", group = "stamina", keys = { "ITEM_MOD_STAMINA_SHORT" } },
  {
    id = "attackPower",
    group = "attack",
    keys = { "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", "ITEM_MOD_FERAL_ATTACK_POWER_SHORT" },
  },
  { id = "hit", group = "attack", unit = "percent", keys = {} },
  { id = "hitRating", group = "attack", unit = "rating", keys = { "ITEM_MOD_HIT_RATING_SHORT" } },
  { id = "crit", group = "attack", unit = "percent", keys = {} },
  { id = "critRating", group = "attack", unit = "rating", keys = { "ITEM_MOD_CRIT_RATING_SHORT" } },
  { id = "hasteRating", group = "attack", unit = "rating", keys = { "ITEM_MOD_HASTE_RATING_SHORT" } },
  { id = "expertiseRating", group = "attack", unit = "rating", keys = { "ITEM_MOD_EXPERTISE_RATING_SHORT" } },
  { id = "spellPower", group = "spell", keys = { "ITEM_MOD_SPELL_POWER_SHORT" } },
  { id = "spellDamage", group = "spell", keys = { "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" } },
  { id = "healing", group = "spell", keys = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" } },
  { id = "spellPenetration", group = "spell", keys = { "ITEM_MOD_SPELL_PENETRATION_SHORT" } },
  { id = "armor", group = "defense", keys = { "RESISTANCE0_NAME" } },
  { id = "defense", group = "defense", keys = {} },
  { id = "defenseRating", group = "defense", unit = "rating", keys = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" } },
  { id = "dodge", group = "defense", unit = "percent", keys = {} },
  { id = "dodgeRating", group = "defense", unit = "rating", keys = { "ITEM_MOD_DODGE_RATING_SHORT" } },
  { id = "parry", group = "defense", unit = "percent", keys = {} },
  { id = "parryRating", group = "defense", unit = "rating", keys = { "ITEM_MOD_PARRY_RATING_SHORT" } },
  { id = "block", group = "defense", unit = "percent", keys = {} },
  { id = "blockRating", group = "defense", unit = "rating", keys = { "ITEM_MOD_BLOCK_RATING_SHORT" } },
  { id = "blockValue", group = "defense", keys = { "ITEM_MOD_BLOCK_VALUE_SHORT" } },
  { id = "resilienceRating", group = "defense", unit = "rating", keys = { "ITEM_MOD_RESILIENCE_RATING_SHORT" } },
  { id = "mp5", group = "regen", keys = { "ITEM_MOD_MANA_REGENERATION_SHORT" } },
  { id = "hp5", group = "regen", keys = { "ITEM_MOD_HEALTH_REGEN_SHORT" } },
  { id = "resHoly", group = "resist", keys = { "RESISTANCE1_NAME" } },
  { id = "resFire", group = "resist", keys = { "RESISTANCE2_NAME" } },
  { id = "resNature", group = "resist", keys = { "RESISTANCE3_NAME" } },
  { id = "resFrost", group = "resist", keys = { "RESISTANCE4_NAME" } },
  { id = "resShadow", group = "resist", keys = { "RESISTANCE5_NAME" } },
  { id = "resArcane", group = "resist", keys = { "RESISTANCE6_NAME" } },
}
for _, school in ipairs(SCHOOLS) do
  G.STATS[#G.STATS + 1] = {
    id = "dmg" .. school[1],
    group = "spell",
    keys = { "ITEM_MOD_" .. school[1]:upper() .. "_DAMAGE_DONE_SHORT" },
  }
end

local BY_ID, BY_KEY = {}, {}
for _, stat in ipairs(G.STATS) do
  stat.unit = stat.unit or "flat"
  BY_ID[stat.id] = stat
  for _, key in ipairs(stat.keys) do
    BY_KEY[key] = stat.id
  end
end

-- Stat keys not in the table by name: a hit or crit key without "rating" would be a percentage.
-- Checked in this order, anything left over is listed as "other".
local KEY_RULES = {
  { "^ITEM_MOD_HIT_.*RATING", "hitRating" },
  { "^ITEM_MOD_HIT_", "hit" },
  { "^ITEM_MOD_CRIT_.*RATING", "critRating" },
  { "^ITEM_MOD_CRIT_", "crit" },
}
local IGNORED_KEYS = { "^EMPTY_SOCKET", "DAMAGE_PER_SECOND" }

local function statId(key)
  if BY_KEY[key] then
    return BY_KEY[key]
  end
  for _, rule in ipairs(KEY_RULES) do
    if key:find(rule[1]) then
      return rule[2]
    end
  end
end

local function ignoredKey(key)
  for _, pattern in ipairs(IGNORED_KEYS) do
    if key:find(pattern) then
      return true
    end
  end
  return false
end

-- Text patterns (lower case, German and English side by side, "#" is the number). The first
-- entry that matches a line wins, so the specific ones stand before the general ones.
local NUM = "(%d+[%.,]?%d*)"
local EQUIP = {
  {
    "spellPower",
    "damage and healing done by magical spells and effects by up to #",
    "schaden und heilung um bis zu #",
  },
  { "spellDamage", "damage done by magical spells and effects by up to #", "verursachten schaden um bis zu #" },
  { "healing", "healing done by spells and effects by up to #", "verursachte heilung um bis zu #" },
  { "mp5", "restores # mana per 5 sec", "stellt alle 5 sek%.? # mana wieder her" },
  { "hp5", "restores # health per 5 sec", "stellt alle 5 sek%.? # gesundheit wieder her" },
  { "critRating", "critical strike rating by #", "kritische trefferwertung um #" },
  { "hitRating", "hit rating by #", "trefferwertung um #" },
  { "hasteRating", "haste rating by #", "tempowertung um #", "hastewertung um #" },
  { "crit", "critical strike by #%%", "critical strike chance by #%%", "kritischen treffer zu erzielen, um #%%" },
  { "hit", "to hit[%w%s]* by #%%", "zu treffen, um #%%" },
  { "attackPower", "attack power by #", "angriffskraft um #" },
  { "defenseRating", "defense rating by #", "verteidigungswertung um #" },
  { "defense", "defense skill by #", "increased defense %+#", "verteidigungsfertigkeit um #" },
  { "dodgeRating", "dodge rating by #", "ausweichwertung um #" },
  { "dodge", "chance to dodge an attack by #%%", "angriffen auszuweichen, um #%%" },
  { "parryRating", "parry rating by #", "parierwertung um #" },
  { "parry", "chance to parry an attack by #%%", "angriffe zu parieren, um #%%" },
  { "blockRating", "block rating by #", "blockwertung um #" },
  { "block", "chance to block attacks with your shield by #%%", "schild zu blocken, um #%%" },
  { "blockValue", "block value of your shield by #", "blockwert eures schildes um #" },
  { "resilienceRating", "resilience rating by #", "abh[^ ]*rtungswertung um #" },
  { "expertiseRating", "expertise rating by #", "waffenkundewertung um #" },
  { "spellPenetration", "spell penetration by #", "zauberdurchschlagskraft um #" },
}
for _, school in ipairs(SCHOOLS) do
  table.insert(EQUIP, 1, {
    "dmg" .. school[1],
    "damage done by " .. school[2] .. " spells and effects by up to #",
  })
end

-- Names after "+12 " (flat) and after "+1 % " (percent), matched against the whole rest of the line.
local FLAT_NAMES = {
  { "strength", "strength", "st[^ ]*rke" },
  { "agility", "agility", "beweglichkeit" },
  { "stamina", "stamina", "ausdauer" },
  { "intellect", "intellect", "intelligenz" },
  { "spirit", "spirit", "willenskraft", "geist" },
  { "armor", "armor", "r[^ ]*stung" },
  { "attackPower", "attack power", "angriffskraft" },
  { "spellPower", "spell power", "spell damage and healing", "zaubermacht", "zauberschaden und heilung" },
  { "spellDamage", "spell damage", "zauberschaden" },
  { "healing", "healing", "heilung" },
  { "mp5", "mana per 5 sec", "mana every 5 sec", "mana alle 5 sek", "mana pro 5 sek" },
  { "hp5", "health per 5 sec", "health every 5 sec", "gesundheit alle 5 sek", "gesundheit pro 5 sek" },
  { "hitRating", "hit rating", "trefferwertung" },
  { "critRating", "critical strike rating", "crit rating", "kritische trefferwertung" },
  { "hasteRating", "haste rating", "tempowertung", "hastewertung" },
  { "expertiseRating", "expertise rating", "waffenkundewertung" },
  { "defenseRating", "defense rating", "verteidigungswertung" },
  { "defense", "defense", "defense skill", "verteidigung", "verteidigungsfertigkeit" },
  { "dodgeRating", "dodge rating", "ausweichwertung" },
  { "parryRating", "parry rating", "parierwertung" },
  { "blockRating", "block rating", "blockwertung" },
  { "blockValue", "block", "block value", "blocken", "blockwert" },
  { "resilienceRating", "resilience rating", "abh[^ ]*rtungswertung" },
  { "spellPenetration", "spell penetration", "zauberdurchschlagskraft" },
}
for _, school in ipairs(SCHOOLS) do
  FLAT_NAMES[#FLAT_NAMES + 1] = { "dmg" .. school[1], school[2] .. " damage", school[3] .. "schaden" }
end
local PERCENT_NAMES = {
  { "hit", "hit", "hit chance", "chance to hit", "trefferchance" },
  {
    "crit",
    "crit",
    "crit chance",
    "critical strike",
    "critical strike chance",
    "kritische trefferchance",
    "kritische treffer",
  },
  { "dodge", "dodge", "dodge chance", "ausweichchance", "ausweichen" },
  { "parry", "parry", "parry chance", "parierchance", "parieren" },
  { "block", "block", "block chance", "blockchance", "blocken" },
}

-- Lines that carry numbers and are no gear stat: ignored, never listed as "other".
local IGNORE = {
  "^use:",
  "^benutzen:",
  "^chance on hit:",
  "^chance bei treffer:",
  "^set:",
  "^socket bonus:",
  "^sockelbonus:",
  "^requires",
  "^ben[^ ]*tigt",
  "^item level",
  "^gegenstandsstufe",
  "^durability",
  "^haltbarkeit",
  "^<",
  "gebunden",
  "^binds ",
  "^bindet",
  "soulbound",
  "^%d+ ?gold",
  "^%d+ ?silber",
  "^%d+ ?kupfer",
  "^%d+ ?silver",
  "^%d+ ?copper",
  "^unique",
  "^einzigartig",
  "^classes:",
  "^klassen:",
  "^sell",
  "^verkaufspreis",
  "^level %d",
  "^stufe %d",
  "^speed",
  "^geschwindigkeit",
  "damage per second",
  "schaden pro sekunde",
  "^%d+ ?%- ?%d+ ",
  "^%(",
}
local PREFIXES = { "^anlegen:%s*", "^equip:%s*", "^verzaubert:%s*", "^enchanted:%s*" }

local function compile(entries)
  local out = {}
  for _, entry in ipairs(entries) do
    local patterns = {}
    for i = 2, #entry do
      patterns[#patterns + 1] = (entry[i]:gsub("#", function()
        return NUM
      end))
    end
    out[#out + 1] = { id = entry[1], patterns = patterns }
  end
  return out
end
local EQUIP_PATTERNS = compile(EQUIP)
local FLAT_PATTERNS = compile(FLAT_NAMES)
local PERCENT_PATTERNS = compile(PERCENT_NAMES)

local function number(text)
  return tonumber((text:gsub(",", "."):gsub("%.$", "")))
end

-- The line without color codes and textures, single spaces, trimmed.
local function clean(text)
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", "")
  text = text:gsub("|r", "")
  text = text:gsub("|T.-|t", "")
  text = text:gsub("%s+", " ")
  return (text:gsub("^ ", ""):gsub(" $", ""))
end

local function normalize(text)
  return clean(text):lower()
end

local function byName(list, name)
  for _, entry in ipairs(list) do
    for _, pattern in ipairs(entry.patterns) do
      if name:find("^" .. pattern .. "$") then
        return entry.id
      end
    end
  end
end

-- One "+12 Stamina" or "+1 % Hit chance" part; the plus sign is optional.
local function plainPart(part)
  local num, percent, name = part:match("^%+?" .. NUM .. "%s*(%%?)%s*(.-)%s*%.?$")
  if not num then
    return nil
  end
  local id = byName(percent == "%" and PERCENT_PATTERNS or FLAT_PATTERNS, name)
  return id and { id = id, value = number(num) } or nil
end

-- Reads one tooltip line. Returns the hits { id, value } (empty when the line says nothing about
-- gear stats) and true when the line carries numbers or a percent sign and nothing was read.
function G.ParseLine(text)
  if type(text) ~= "string" then
    return {}, false
  end
  local line = normalize(text)
  if line == "" then
    return {}, false
  end
  for _, pattern in ipairs(IGNORE) do
    if line:find(pattern) then
      return {}, false
    end
  end
  for _, prefix in ipairs(PREFIXES) do
    line = line:gsub(prefix, "")
  end
  local hits = {}
  if line:find("^%+?%d") then
    local whole = plainPart(line)
    if whole then
      hits[1] = whole
    else
      local source = line:gsub(" and ", "\n"):gsub(" und ", "\n")
      for part in source:gmatch("[^\n]+") do
        local hit = plainPart(part)
        if hit then
          hits[#hits + 1] = hit
        end
      end
    end
  end
  if #hits == 0 then
    for _, entry in ipairs(EQUIP_PATTERNS) do
      for _, pattern in ipairs(entry.patterns) do
        local captured = line:match(pattern)
        if captured then
          hits[1] = { id = entry.id, value = number(captured) }
          break
        end
      end
      if #hits > 0 then
        break
      end
    end
  end
  return hits, #hits == 0 and (line:find("%d") ~= nil or line:find("%%") ~= nil)
end

local OPTIONAL = { [4] = true, [17] = true, [18] = true, [19] = true } -- shirt, off hand, ranged, tabard
local NOT_AVERAGED = { [4] = true, [18] = true, [19] = true }
local AVERAGE_SLOTS = 16 -- 14 armor slots plus two weapon slots, a two-hander counts twice
local MAIN_HAND, OFF_HAND = 16, 17

local function add(map, id, value)
  map[id] = (map[id] or 0) + value
end

-- Stat table, tooltip lines and enchant lines of one item as three maps id -> value; unknown
-- stat keys and unread lines go to `other` as { slot, text, source }.
local function readItem(slotId, item, other)
  local fromStats, fromText, fromEnchant = {}, {}, {}
  for key, value in pairs(item.stats or {}) do
    local id = type(key) == "string" and type(value) == "number" and statId(key)
    if id then
      add(fromStats, id, value)
    elseif type(key) == "string" and type(value) == "number" and not ignoredKey(key) then
      local name = key:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):lower()
      other[#other + 1] = { slot = slotId, text = string.format("%s %s", name, G.Format(value)), source = "Stat" }
    end
  end
  for _, entry in ipairs(item.lines or {}) do
    local hits, unknown = G.ParseLine(entry.text)
    for _, hit in ipairs(hits) do
      add(entry.kind == "enchant" and fromEnchant or fromText, hit.id, hit.value)
    end
    if unknown then
      other[#other + 1] = { slot = slotId, text = clean(entry.text), source = "Text" }
    end
  end
  return fromStats, fromText, fromEnchant
end

-- Whole number without decimals, else one decimal.
function G.Format(value)
  if math.abs(value - math.floor(value + 0.5)) < 0.05 then
    return string.format("%d", math.floor(value + 0.5))
  end
  return string.format("%.1f", value)
end

-- input.items[slotId] (1..19) = {
--   name, quality, level (nil while uncached), stats (item stat table), lines (tooltip lines
--   { text, kind = "enchant" | nil }, nil when the tooltip is not there yet), enchantable,
--   enchanted, sockets, gems (number of gems in the sockets), twoHand }
-- input.gameAverage: the game's own average item level when it has one.
-- Returns { groups = { { id, rows = { { id, value, unit, source } } } }, slots = { ... one entry
-- per slot ... }, notes = { { key, n } }, facts = { ... } }. The last group has the id "other" and
-- rows { slot, text, source }; "source" is "Stat" when every part came from the item stats and
-- "Text" when a tooltip line contributed.
function G.Compute(input)
  local items = input and input.items or {}
  local other, totals = {}, {}
  local slots = {}
  local facts = { enchanted = 0, possible = 0, emptySockets = 0, missing = 0, uncached = 0 }
  local sum, complete = 0, true
  local mainLevel, mainTwoHand

  for slotId = 1, 19 do
    local item = items[slotId]
    local slot = { id = slotId, empty = item == nil }
    slots[slotId] = slot
    if item then
      slot.name, slot.quality, slot.level, slot.link = item.name, item.quality, item.level, item.link
      slot.twoHand = item.twoHand == true
      local fromStats, fromText, fromEnchant = readItem(slotId, item, other)
      local ids = {}
      for _, map in ipairs({ fromStats, fromText, fromEnchant }) do
        for id in pairs(map) do
          ids[id] = true
        end
      end
      for id in pairs(ids) do
        local stat, text, enchant = fromStats[id] or 0, fromText[id] or 0, fromEnchant[id] or 0
        local entry = totals[id] or { value = 0, text = false }
        entry.value = entry.value + math.max(stat, text) + enchant
        entry.text = entry.text or text > stat or enchant > 0
        totals[id] = entry
      end
      if item.enchantable == true then
        slot.enchant = item.enchanted == true
        facts.possible = facts.possible + 1
        if slot.enchant then
          facts.enchanted = facts.enchanted + 1
        end
      end
      slot.emptySockets = math.max(0, (item.sockets or 0) - (item.gems or 0))
      facts.emptySockets = facts.emptySockets + slot.emptySockets
      if item.lines == nil or item.level == nil then
        facts.uncached = facts.uncached + 1
      end
      if not NOT_AVERAGED[slotId] then
        if item.level then
          sum = sum + item.level
          if slotId == MAIN_HAND then
            mainLevel = item.level
          end
        else
          complete = false
        end
      end
      if slotId == MAIN_HAND then
        mainTwoHand = item.twoHand == true
      end
    else
      slot.missing = not OPTIONAL[slotId]
    end
  end
  for _, slot in ipairs(slots) do
    if slot.missing then
      facts.missing = facts.missing + 1
    end
  end
  if mainLevel and mainTwoHand and items[OFF_HAND] == nil then
    sum = sum + mainLevel
  end
  facts.calculated = complete and sum > 0 and math.floor(sum / AVERAGE_SLOTS) or nil
  facts.average = input and input.gameAverage or facts.calculated

  local groups = {}
  for _, groupId in ipairs(G.GROUPS) do
    local rows = {}
    for _, stat in ipairs(G.STATS) do
      local entry = totals[stat.id]
      if stat.group == groupId and entry and entry.value ~= 0 then
        rows[#rows + 1] = {
          id = stat.id,
          value = entry.value,
          unit = stat.unit,
          source = entry.text and "Text" or "Stat",
        }
      end
    end
    if #rows > 0 then
      groups[#groups + 1] = { id = groupId, rows = rows }
    end
  end
  if #other > 0 then
    groups[#groups + 1] = { id = "other", rows = other }
  end

  local notes = { { key = "gs.note.gear" } }
  if facts.uncached > 0 then
    notes[#notes + 1] = { key = "gs.note.uncached", n = facts.uncached }
  end
  return { groups = groups, slots = slots, notes = notes, facts = facts }
end

-- { id, value, unit, source } of one stat, nil when the gear has none of it.
function G.Lookup(result, id)
  for _, group in ipairs(result.groups) do
    for _, row in ipairs(group.rows) do
      if row.id == id then
        return row
      end
    end
  end
end

G.QUICK = {
  "hit",
  "hitRating",
  "crit",
  "critRating",
  "spellPower",
  "attackPower",
  "armor",
  "defense",
  "defenseRating",
  "stamina",
}

-- The rows of the short view in the order of G.QUICK.
function G.Quick(result)
  local out = {}
  for _, id in ipairs(G.QUICK) do
    local row = G.Lookup(result, id)
    if row then
      out[#out + 1] = row
    end
  end
  return out
end

function G.Stat(id)
  return BY_ID[id]
end
