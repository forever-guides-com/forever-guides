-- Page "Inspect" (/fg untersuchen): equipment of the inspected player as a paper doll (slot cells
-- in the order of the character window, the item tooltip on hover or focus) with item level,
-- enchant and sockets per slot, a list of the same slots and the totals of the gear stats
-- (Modules/GearStatsLogic.lua). Blizzard hands
-- out no stats for other players, so every number is computed from the worn items. Next to the
-- inspect window a short view shows the main facts (item level, enchants, sockets, talents, guild
-- and the main totals); it is ours (a child of InspectFrame, anchored to it) and
-- never written while in combat. The data is read once per refresh for both.
local _, ns = ...
local W, L, Theme, K, Store = ns.W, ns.L, ns.Theme, ns.PageKit, ns.Store
local I = ns.ItemInfo
local G = ns.GearStatsLogic
local V = ns.InspectOverlay
local E = ns.ItemEnchantOverlay
local O = ns.ItemLevelOverlay

local P = {}
ns.InspectPage = P

local SLOT_NAMES = {
  "Head",
  "Neck",
  "Shoulders",
  "Shirt",
  "Chest",
  "Waist",
  "Legs",
  "Feet",
  "Wrists",
  "Hands",
  "Ring 1",
  "Ring 2",
  "Trinket 1",
  "Trinket 2",
  "Back",
  "Main hand",
  "Off hand",
  "Ranged",
  "Tabard",
}
local SLOT_NAMES_DE = {
  "Kopf",
  "Hals",
  "Schultern",
  "Hemd",
  "Brust",
  "Taille",
  "Beine",
  "Füße",
  "Handgelenke",
  "Hände",
  "Ring 1",
  "Ring 2",
  "Schmuck 1",
  "Schmuck 2",
  "Rücken",
  "Waffenhand",
  "Schildhand",
  "Fernkampf",
  "Wappenrock",
}

-- Stat labels, German then English, in the order of GearStatsLogic.STATS.
local STAT_LABELS = {
  { "strength", "Stärke", "Strength" },
  { "agility", "Beweglichkeit", "Agility" },
  { "intellect", "Intelligenz", "Intellect" },
  { "spirit", "Willenskraft", "Spirit" },
  { "stamina", "Ausdauer", "Stamina" },
  { "attackPower", "Angriffskraft", "Attack power" },
  { "hit", "Trefferchance", "Hit chance" },
  { "hitRating", "Trefferwertung", "Hit rating" },
  { "crit", "Kritische Trefferchance", "Crit chance" },
  { "critRating", "Kritische Trefferwertung", "Crit rating" },
  { "hasteRating", "Tempowertung", "Haste rating" },
  { "expertiseRating", "Waffenkundewertung", "Expertise rating" },
  { "spellPower", "Zauberschaden und Heilung", "Spell damage and healing" },
  { "spellDamage", "Zauberschaden", "Spell damage" },
  { "healing", "Heilung", "Healing" },
  { "spellPenetration", "Zauberdurchschlag", "Spell penetration" },
  { "armor", "Rüstung", "Armor" },
  { "defense", "Verteidigung", "Defense" },
  { "defenseRating", "Verteidigungswertung", "Defense rating" },
  { "dodge", "Ausweichchance", "Dodge chance" },
  { "dodgeRating", "Ausweichwertung", "Dodge rating" },
  { "parry", "Parierchance", "Parry chance" },
  { "parryRating", "Parierwertung", "Parry rating" },
  { "block", "Blockchance", "Block chance" },
  { "blockRating", "Blockwertung", "Block rating" },
  { "blockValue", "Blockwert", "Block value" },
  { "resilienceRating", "Abhärtungswertung", "Resilience rating" },
  { "mp5", "Mana pro 5 Sek.", "Mana per 5 sec" },
  { "hp5", "Gesundheit pro 5 Sek.", "Health per 5 sec" },
  { "resHoly", "Heiligresistenz", "Holy resistance" },
  { "resFire", "Feuerresistenz", "Fire resistance" },
  { "resNature", "Naturresistenz", "Nature resistance" },
  { "resFrost", "Frostresistenz", "Frost resistance" },
  { "resShadow", "Schattenresistenz", "Shadow resistance" },
  { "resArcane", "Arkanresistenz", "Arcane resistance" },
  { "dmgArcane", "Arkanschaden", "Arcane damage" },
  { "dmgFire", "Feuerschaden", "Fire damage" },
  { "dmgFrost", "Frostschaden", "Frost damage" },
  { "dmgNature", "Naturschaden", "Nature damage" },
  { "dmgShadow", "Schattenschaden", "Shadow damage" },
  { "dmgHoly", "Heiligschaden", "Holy damage" },
}

local en, de = {}, {}
for index, name in ipairs(SLOT_NAMES) do
  en["gs.slot." .. index] = name
  de["gs.slot." .. index] = SLOT_NAMES_DE[index]
end
for _, entry in ipairs(STAT_LABELS) do
  en["gs.stat." .. entry[1]] = entry[3]
  de["gs.stat." .. entry[1]] = entry[2]
end
local function merge(target, source)
  for key, value in pairs(source) do
    target[key] = value
  end
  return target
end
ns.AddLocale(
  "enUS",
  merge(en, {
    ["page.inspect"] = "Inspect",
    ["gs.none"] = "Inspect a player first",
    ["gs.head"] = "Level %d %s",
    ["gs.slots"] = "Equipment",
    ["gs.totals"] = "Totals (calculated from gear)",
    ["gs.info"] = "Calculated from gear",
    ["gs.info.text"] = "Gear only: no talents, buffs, set bonuses or base stats\nStat: value of the item\nText: read from a tooltip line",
    ["gs.note.gear"] = "Gear only: no talents, buffs, set bonuses or base stats",
    ["gs.note.uncached"] = "%d items not loaded yet",
    ["gs.group.primary"] = "Primary stats",
    ["gs.group.stamina"] = "Stamina",
    ["gs.group.attack"] = "Attack",
    ["gs.group.spell"] = "Spell",
    ["gs.group.defense"] = "Defense",
    ["gs.group.regen"] = "Regeneration",
    ["gs.group.resist"] = "Resistances",
    ["gs.group.other"] = "Other (not recognized)",
    ["gs.noStats"] = "No stats found",
    ["gs.ench.yes"] = "Ench.",
    ["gs.ench.no"] = "No ench.",
    ["gs.sockets"] = "%d empty sockets",
    ["gs.missing"] = "Missing",
    ["gs.empty"] = "Empty",
    ["gs.hint.chat"] = "Shift-click: link to chat",
    ["gs.hint.dress"] = "Ctrl-click: try on",
    ["gs.quick.title"] = "From gear",
    ["gs.more"] = "More",
    ["gs.more.tip"] = "Opens the inspect page.",
    ["gs.quick.level"] = "Item level",
    ["gs.quick.enchants"] = "Enchants",
    ["gs.quick.sockets"] = "Empty sockets",
    ["gs.quick.talents"] = "Talents",
    ["gs.quick.guild"] = "Guild",
    ["gs.setting.heading"] = "Inspect",
    ["gs.setting.panel"] = "Short view at the inspect window",
    ["gs.setting.panel.tip"] = "Main totals next to the window.",
  })
)
ns.AddLocale(
  "deDE",
  merge(de, {
    ["page.inspect"] = "Betrachten",
    ["gs.none"] = "Erst einen Spieler betrachten",
    ["gs.head"] = "Stufe %d %s",
    ["gs.slots"] = "Ausrüstung",
    ["gs.totals"] = "Summen (aus Ausrüstung berechnet)",
    ["gs.info"] = "Aus Ausrüstung berechnet",
    ["gs.info.text"] = "Nur Ausrüstung: ohne Talente, Buffs, Setboni und Basiswerte\nStat: Wert vom Item\nText: aus Tooltip-Zeile gelesen",
    ["gs.note.gear"] = "Nur Ausrüstung: ohne Talente, Buffs, Setboni und Basiswerte",
    ["gs.note.uncached"] = "%d Items noch nicht geladen",
    ["gs.group.primary"] = "Primärwerte",
    ["gs.group.stamina"] = "Ausdauer",
    ["gs.group.attack"] = "Angriff",
    ["gs.group.spell"] = "Zauber",
    ["gs.group.defense"] = "Verteidigung",
    ["gs.group.regen"] = "Regeneration",
    ["gs.group.resist"] = "Resistenzen",
    ["gs.group.other"] = "Sonstiges (nicht erkannt)",
    ["gs.noStats"] = "Keine Werte gefunden",
    ["gs.ench.yes"] = "Verz.",
    ["gs.ench.no"] = "Verz. fehlt",
    ["gs.sockets"] = "%d Sockel leer",
    ["gs.missing"] = "Fehlt",
    ["gs.empty"] = "Leer",
    ["gs.hint.chat"] = "Shift-Klick: Link in Chat",
    ["gs.hint.dress"] = "Strg-Klick: Anprobe",
    ["gs.quick.title"] = "Aus Ausrüstung",
    ["gs.more"] = "Mehr",
    ["gs.more.tip"] = "Öffnet die Betrachten-Seite.",
    ["gs.quick.level"] = "Itemlevel",
    ["gs.quick.enchants"] = "Verzauberungen",
    ["gs.quick.sockets"] = "Sockel leer",
    ["gs.quick.talents"] = "Talente",
    ["gs.quick.guild"] = "Gilde",
    ["gs.setting.heading"] = "Betrachten",
    ["gs.setting.panel"] = "Kurzansicht am Betrachten-Fenster",
    ["gs.setting.panel.tip"] = "Wichtigste Summen neben dem Fenster.",
  })
)

local TWO_COLUMNS = 560 -- page width from which slots and totals sit side by side
local COLUMN_GAP, ROW_GAP, LEAD_WIDTH = 16, 6, 84
local ROW_HEIGHT, HEAD_HEIGHT = 18, 24
local PANEL_WIDTH, PANEL_PAD, PANEL_GAP, QUICK_ROW = 190, 8, 8, 16
local MORE_WIDTH, MORE_HEIGHT = 70, 22
local PANEL_TOP, WINDOW_HEIGHT = 40, 424 -- drop below the window's upper edge; height when unknown
local VALUE_SHARE, LABEL_GAP = 0.6, 6 -- most of a row the value may take; space between the two

-- Paper doll: the groups of the character window (PaperDollItemSlotButton Left, Right and Bottom
-- templates), as inventory slot ids.
local DOLL_LEFT = { 1, 2, 3, 15, 5, 4, 19, 9 }
local DOLL_RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 }
local DOLL_BOTTOM = { 16, 17, 18 }
local RANGED = 18
local CELL_MIN, CELL_FLOOR, CELL_GAP, DOLL_GAP, DOLL_MAX, MID_MIN = 36, 24, 4, 8, 420, 140
local SECTION_GAP, ICON_INSET, EMPTY_ALPHA = 14, 2, 0.35
local FALLBACK_ICON = 134400 -- question mark, for an item whose icon is not known yet
local SLOT_BY_ID = {}
for _, slot in ipairs(I.SLOTS) do
  SLOT_BY_ID[slot.id] = slot
end

P.PANEL_WIDTH = PANEL_WIDTH
P.stats = { reads = 0 }
local panel, hooked

local function frame()
  local f = rawget(_G, "InspectFrame")
  return type(f) == "table" and f or nil
end

local function shown(f)
  return type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() == true
end

-- "ready": the data of the inspected unit is there, "loading": the window is open and waits for
-- it, "none": nothing is inspected.
function P.State()
  if not shown(frame()) then
    return "none"
  end
  return V.Ready(V.Unit()) and "ready" or "loading"
end

local function itemStats(link)
  local api = rawget(_G, "C_Item")
  local f = type(api) == "table" and api.GetItemStats or rawget(_G, "GetItemStats")
  if type(f) ~= "function" then
    return nil
  end
  local ok, stats = pcall(f, link)
  if not (ok and type(stats) == "table") then
    return nil
  end
  local out = {}
  for key, value in pairs(stats) do
    if type(key) == "string" and I.readable(value) then
      out[key] = value
    end
  end
  return out
end

-- Tooltip lines of a worn item without the name line; the enchant line is marked.
local function tooltipLines(unit, slotId)
  local api = rawget(_G, "C_TooltipInfo")
  local f = type(api) == "table" and api.GetInventoryItem
  if type(f) ~= "function" then
    return nil
  end
  local ok, data = pcall(f, unit, slotId)
  if not (ok and type(data) == "table" and type(data.lines) == "table") then
    return nil
  end
  local enum = rawget(_G, "Enum")
  local types = type(enum) == "table" and enum.TooltipDataLineType or nil
  local enchantType = type(types) == "table" and types.ItemEnchantmentPermanent or nil
  local out = {}
  for index, entry in ipairs(data.lines) do
    local text = type(entry) == "table" and entry.leftText
    if index > 1 and I.accessible(text) and type(text) == "string" and text ~= "" then
      local kind = entry.type
      local enchant = enchantType ~= nil and I.accessible(kind) and kind == enchantType
        or text:lower():find("^verzaubert:") ~= nil
        or text:lower():find("^enchanted:") ~= nil
      out[#out + 1] = { text = text, kind = enchant and "enchant" or nil }
    end
  end
  return out
end

local function quality(link, slotId, unit)
  local q = I.quality(link)
  if q then
    return q
  end
  local f = rawget(_G, "GetInventoryItemQuality")
  if type(f) == "function" then
    local ok, value = pcall(f, unit, slotId)
    return ok and I.readable(value) and value or nil
  end
end

-- Icon of a worn item: from the link, else the texture the game has for the slot.
local function itemIcon(link, slotId, unit)
  local api = rawget(_G, "C_Item")
  local instant = type(api) == "table" and api.GetItemInfoInstant or rawget(_G, "GetItemInfoInstant")
  if type(instant) == "function" then
    local ok, _, _, _, _, icon = pcall(instant, link)
    if ok and icon ~= nil then
      return icon
    end
  end
  local texture = rawget(_G, "GetInventoryItemTexture")
  if type(texture) == "function" then
    local ok, icon = pcall(texture, unit, slotId)
    return ok and icon or nil
  end
end

-- Points spent in each talent tree of the inspected unit, nil when the client gives no talent data
-- (the functions are missing, nothing was delivered yet or no point is spent).
local function talentPoints()
  local count, info = rawget(_G, "GetNumTalentTabs"), rawget(_G, "GetTalentTabInfo")
  if type(count) ~= "function" or type(info) ~= "function" then
    return nil
  end
  local ok, trees = pcall(count, true)
  if not (ok and I.readable(trees) and trees > 0) then
    return nil
  end
  local points, sum = {}, 0
  for tree = 1, math.min(trees, 3) do
    -- Name, icon, points (Classic) or id, name, description, icon, points (later clients).
    local done, first, _, third, _, fifth = pcall(info, tree, true)
    local spent = done and (type(first) == "number" and fifth or third) or nil
    if not I.readable(spent) then
      return nil
    end
    points[tree] = spent
    sum = sum + spent
  end
  return sum > 0 and points or nil
end

local function unitFacts(unit)
  local function call(name)
    local f = rawget(_G, name)
    if type(f) == "function" then
      local ok, a, b = pcall(f, unit)
      return ok and a or nil, ok and b or nil
    end
  end
  local name = call("UnitName")
  local level = call("UnitLevel")
  local className, class = call("UnitClass")
  local guild = call("GetGuildInfo")
  return {
    name = type(name) == "string" and name or nil,
    level = I.readable(level) and level or nil,
    className = type(className) == "string" and className or nil,
    class = type(class) == "string" and class or nil,
    guild = type(guild) == "string" and guild ~= "" and guild or nil,
    talents = talentPoints(),
  }
end

-- The facts GearStatsLogic.Compute needs for the worn items of a unit.
function P.Collect(unit)
  P.stats.reads = P.stats.reads + 1
  local flagged = I.flaggedSlots(O.Option("enchantSlots"))
  local items = {}
  for _, slot in ipairs(I.SLOTS) do
    local link = I.inventoryLink(slot.id, unit)
    if link ~= nil then
      local info = I.enchantInfo(slot.id, link, unit)
      items[slot.id] = {
        link = link,
        name = type(link) == "string" and link:match("%[(.-)%]") or nil,
        quality = quality(link, slot.id, unit),
        icon = itemIcon(link, slot.id, unit),
        level = I.itemLevel(link),
        stats = itemStats(link),
        lines = tooltipLines(unit, slot.id),
        enchantable = I.enchantable(slot.id, link, flagged) == true,
        enchanted = info ~= nil and (info.id ~= nil or info.text ~= nil),
        sockets = I.numSockets(link) or 0,
        gems = #I.gems(slot.id, link, unit),
        twoHand = I.isTwoHand(link),
      }
    end
  end
  local result = G.Compute({ items = items, gameAverage = V.gameAverage(unit) })
  result.unit = unitFacts(unit)
  for id, item in pairs(items) do
    result.slots[id].icon = item.icon
  end
  return result
end

local function enabled()
  return O.Option("inspectPanel") ~= false
end

-- Display helpers ----------------------------------------------------------------------------

local function hex(r, g, b)
  return string.format(
    "|cff%02x%02x%02x",
    math.floor(r * 255 + 0.5),
    math.floor(g * 255 + 0.5),
    math.floor(b * 255 + 0.5)
  )
end

local function muted(text)
  return Theme.hexText("textMuted", text)
end

local function valueText(row)
  local text = G.Format(row.value)
  return row.unit == "percent" and text .. " %" or text
end

local function statLabel(id)
  return L["gs.stat." .. id]
end

local function slotLabel(slotId)
  return L["gs.slot." .. slotId]
end

-- Rows of the left column: heading, then one row per worn or missing slot.
local function slotRows(result)
  local rows = { { heading = L["gs.slots"] } }
  for _, slot in ipairs(result.slots) do
    if not slot.empty then
      local r, g, b = I.qualityTextColor(slot.quality)
      if not r then
        r, g, b = Theme.rgb("text")
      end
      local color = hex(r, g, b)
      local level = slot.level and I.format(slot.level) or "..."
      local state = {}
      if slot.enchant == true then
        state[#state + 1] = Theme.hexText("success", L["gs.ench.yes"])
      elseif slot.enchant == false then
        state[#state + 1] = Theme.hexText("danger", L["gs.ench.no"])
      end
      if slot.emptySockets > 0 then
        state[#state + 1] = Theme.hexText("danger", string.format(L["gs.sockets"], slot.emptySockets))
      end
      rows[#rows + 1] = {
        lead = slotLabel(slot.id),
        main = string.format("%s%s|r %s", color, slot.name or "?", muted(level)),
        tail = table.concat(state, "  "),
        link = slot.link,
      }
    elseif slot.missing then
      rows[#rows + 1] = { lead = slotLabel(slot.id), main = Theme.hexText("danger", L["gs.missing"]) }
    end
  end
  return rows
end

-- Rows of the right column: one block per group, the unread lines last.
local function totalRows(result)
  local rows = { { heading = L["gs.totals"], info = true } }
  if #result.groups == 0 then
    rows[#rows + 1] = { main = muted(L["gs.noStats"]) }
  end
  for _, group in ipairs(result.groups) do
    rows[#rows + 1] = { heading = L["gs.group." .. group.id], small = true }
    for _, row in ipairs(group.rows) do
      if group.id == "other" then
        rows[#rows + 1] = {
          main = string.format("%s: %s", slotLabel(row.slot), row.text),
          tail = muted(row.source),
        }
      else
        rows[#rows + 1] = { main = statLabel(row.id), tail = valueText(row) .. " " .. muted(row.source) }
      end
    end
  end
  return rows
end

-- Page ---------------------------------------------------------------------------------------

local function nameText(result)
  local unit = result.unit
  local name = unit.name or "?"
  if unit.class then
    name = "|cff" .. K.ClassColorHex(unit.class):sub(2) .. name .. "|r"
  end
  return name
end

local function detailText(result)
  local unit = result.unit
  return unit.level and string.format(L["gs.head"], unit.level, unit.className or "") or ""
end

local function noteText(result)
  local lines = {}
  for _, note in ipairs(result.notes) do
    lines[#lines + 1] = note.n and string.format(L[note.key], note.n) or L[note.key]
  end
  return table.concat(lines, "\n")
end

local function newRow(parent)
  -- A plain frame with the mouse on: rows are no buttons, so the info button may sit on one.
  local row = CreateFrame("Frame", nil, parent)
  row.lead = W.Text(row, { role = "ui", color = "textMuted" })
  row.main = W.Text(row, { role = "ui", color = "text" })
  row.tail = W.Text(row, { role = "ui", color = "text", justify = "RIGHT" })
  row:SetScript("OnEnter", function(self)
    if self.link then
      W.Tooltip.Show(self, { link = self.link })
    end
  end)
  row:SetScript("OnLeave", ns.HideTooltip)
  return row
end

local function setRow(row, spec)
  local lead = spec.lead ~= nil
  local main = spec.heading and Theme.hexText("accent2", spec.heading) or spec.main or ""
  row.link = spec.link
  row.lead:SetText(spec.lead or "")
  row.lead:SetShown(lead)
  row.main:SetText(main)
  row.tail:SetText(spec.tail or "")
  row.lead:ClearAllPoints()
  row.main:ClearAllPoints()
  row.tail:ClearAllPoints()
  row.tail:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  if lead then
    row.lead:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.lead:SetWidth(LEAD_WIDTH)
    row.main:SetPoint("LEFT", row, "LEFT", LEAD_WIDTH + 4, 0)
  else
    row.main:SetPoint("LEFT", row, "LEFT", 0, 0)
  end
  row.main:SetPoint("RIGHT", row.tail, "LEFT", -6, 0)
end

-- Paper doll ---------------------------------------------------------------------------------

local function held(name)
  local f = rawget(_G, name)
  return type(f) == "function" and f() == true
end

local function dressUpFunction()
  local f = rawget(_G, "DressUpLink") or rawget(_G, "DressUpItemLink")
  return type(f) == "function" and f or nil
end

-- Into the open chat edit box, else opens the chat with the link in it.
local function insertChatLink(link)
  local util = rawget(_G, "ChatFrameUtil")
  util = type(util) == "table" and util or {}
  local insert = util.InsertLink or rawget(_G, "ChatEdit_InsertLink")
  if type(insert) ~= "function" then
    return
  end
  local ok, done = pcall(insert, link)
  local open = util.OpenChat or rawget(_G, "ChatFrame_OpenChat")
  if not (ok and done) and type(open) == "function" then
    pcall(open, link)
  end
end

-- Shift: link into the chat. Ctrl: the try-on window, only where the client has one.
local function useCell(cell, shift, ctrl)
  local link = cell.link
  local try = dressUpFunction()
  if not link then
    return
  end
  if ctrl and try then
    pcall(try, link)
  elseif shift then
    insertChatLink(link)
  end
end

-- The game's item tooltip, then a text line for what a color alone would show (missing enchant,
-- empty sockets) and the click hints.
local function cellTip(cell)
  local slot = cell.slot
  if not slot then
    return
  end
  if slot.empty then
    local missing = slot.missing == true
    local line = { text = missing and L["gs.missing"] or L["gs.empty"], color = missing and "danger" or "textMuted" }
    ns.ShowTooltip(cell, slotLabel(slot.id), nil, { lines = { line } })
    return
  end
  local lines = {}
  if slot.enchant == false then
    lines[#lines + 1] = { text = L["ench.none"], color = "danger" }
  end
  if slot.emptySockets > 0 then
    lines[#lines + 1] = { text = string.format(L["gs.sockets"], slot.emptySockets), color = "danger" }
  end
  local hint = L["gs.hint.chat"]
  if dressUpFunction() then
    hint = hint .. "\n" .. L["gs.hint.dress"]
  end
  ns.ShowTooltip(cell, slot.name or slotLabel(slot.id), nil, { link = slot.link, lines = lines, hint = hint })
end

local function qualityHex(level)
  local r, g, b = I.qualityColor(level)
  return string.format("#%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- The texture the game keeps for an empty slot; nil when this client has none, then the cell stays
-- a plain dimmed box.
local function slotTexture(def)
  local f = rawget(_G, "GetInventorySlotInfo")
  if type(f) ~= "function" then
    return nil
  end
  local ok, _, texture = pcall(f, def.name)
  return ok and type(texture) == "string" and texture ~= "" and texture or nil
end

-- A slot the client has: it holds an item, or the inspect window has a frame for it. While that
-- window is not loaded only the ranged slot is left out, not every client has it.
local function slotExists(result, id)
  if not result.slots[id].empty then
    return true
  end
  if rawget(_G, "InspectHeadSlot") ~= nil then
    return rawget(_G, "Inspect" .. SLOT_BY_ID[id].name) ~= nil
  end
  return id ~= RANGED
end

-- Square slot cell: quality frame, icon, item level and sockets on a dark strip, a flag for a missing
-- enchant. Every mark is text, so no state rests on color alone; the tooltip spells them out.
local function newCell(parent, slotId)
  local cell = CreateFrame("Button", nil, parent)
  cell.slotId = slotId
  W.Fill(cell, "surface", 1)
  cell.icon = cell:CreateTexture(nil, "ARTWORK")
  cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", ICON_INSET, -ICON_INSET)
  cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
  cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  cell.strip = cell:CreateTexture(nil, "ARTWORK")
  cell.strip:SetColorTexture(0, 0, 0, 0.6)
  cell.flag = cell:CreateTexture(nil, "ARTWORK")
  cell.flag:SetColorTexture(0, 0, 0, 0.7)
  cell.border = W.Border(cell, "white", 0.25, 2)
  local hover = cell:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.12)
  cell.level = W.Text(cell, { role = "micro", color = "text" })
  cell.level:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", ICON_INSET + 1, ICON_INSET + 1)
  cell.sockets = W.Text(cell, { role = "micro", color = "danger", justify = "RIGHT" })
  cell.sockets:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -(ICON_INSET + 1), ICON_INSET + 1)
  cell.mark = W.Text(cell, { role = "micro", color = "danger", justify = "CENTER" })
  cell.mark:SetPoint("CENTER", cell.flag, "CENTER")
  cell.center = W.Text(cell, { role = "ui", color = "textMuted", justify = "CENTER" })
  cell.center:SetPoint("CENTER", cell, "CENTER")
  cell:SetScript("OnEnter", cellTip)
  cell:SetScript("OnLeave", function(self)
    W.Tooltip.Hide(self)
  end)
  cell:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
      useCell(self, held("IsShiftKeyDown"), held("IsControlKeyDown"))
    end
  end)
  -- Keyboard: Enter links the item, Ctrl+Enter tries it on. The tooltip follows the focus.
  cell.fgOnFocus = cellTip
  cell.fgOnBlur = function(self)
    W.Tooltip.Hide(self)
  end
  ns.Focus.register(cell, function(self)
    local ctrl = held("IsControlKeyDown")
    useCell(self, not ctrl, ctrl)
  end)
  return cell
end

local function setCell(cell, result, id)
  local slot = result.slots[id]
  cell.slot, cell.link = slot, slot.link
  cell.fgOn = slotExists(result, id)
  cell.level:SetText("")
  cell.sockets:SetText("")
  cell.mark:SetText("")
  cell.center:SetText("")
  cell.flag:Hide()
  if slot.empty then
    local texture = slotTexture(SLOT_BY_ID[id])
    if texture then
      cell.icon:SetTexture(texture)
    end
    cell.icon:SetShown(texture ~= nil)
    cell.icon:SetAlpha(EMPTY_ALPHA)
    cell.strip:Hide()
    cell.border.set("white", 0.15)
    W.SetColor(cell.center, slot.missing and "danger" or "textMuted")
    cell.center:SetText(slot.missing and "x" or "-")
    return
  end
  cell.icon:SetTexture(slot.icon or FALLBACK_ICON)
  cell.icon:SetAlpha(1)
  cell.icon:Show()
  cell.border.set(qualityHex(slot.quality), 1)
  local showLevel = SLOT_BY_ID[id].overlay ~= false
  if showLevel then
    cell.level:SetText(slot.level and I.format(slot.level) or "...")
  end
  if slot.emptySockets > 0 then
    cell.sockets:SetText(string.rep("o", math.min(slot.emptySockets, 4)))
  end
  if slot.enchant == false then
    cell.mark:SetText("!")
    cell.flag:Show()
  end
  cell.strip:SetShown(showLevel or slot.emptySockets > 0)
end

-- Centre of the doll: name, class, level, item level and the main totals that fit.
local function newMid(parent)
  local mid = CreateFrame("Frame", nil, parent)
  mid.name = W.Text(mid, { role = "h3", color = "text" })
  mid.detail = W.Text(mid, { role = "ui", color = "textSecondary" })
  mid.average = W.Text(mid, { role = "ui", color = "text" })
  mid.title = W.Text(mid, { key = "gs.quick.title", role = "ui", color = "accent2" })
  mid.rows = {}
  return mid
end

local function midRow(mid, index)
  local row = mid.rows[index]
  if not row then
    row = CreateFrame("Frame", nil, mid)
    row.label = W.Text(row, { role = "ui", color = "textSecondary" })
    row.value = W.Text(row, { role = "ui", color = "text", justify = "RIGHT" })
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    mid.rows[index] = row
  end
  return row
end

local function layoutMid(mid, result, width, height)
  local rowH = K.scaledHeight(ROW_HEIGHT)
  local y = 0
  local function line(fs, h)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", mid, "TOPLEFT", 0, -y)
    fs:SetWidth(width)
    y = y + h
  end
  mid.name:SetText(nameText(result))
  mid.detail:SetText(detailText(result))
  mid.average:SetText(string.format(L["insp.avg"], result.facts.average and I.format(result.facts.average) or "..."))
  line(mid.name, K.scaledHeight(HEAD_HEIGHT))
  line(mid.detail, rowH)
  line(mid.average, rowH)
  y = y + ROW_GAP
  local list = G.Quick(result)
  local capacity = math.max(0, math.floor((height - y) / rowH) - 1)
  mid.title:SetShown(#list > 0 and capacity > 0)
  if #list > 0 and capacity > 0 then
    line(mid.title, rowH)
  end
  for index, row in ipairs(list) do
    local entry = midRow(mid, index)
    entry:SetShown(index <= capacity)
    if index <= capacity then
      entry.label:SetText(statLabel(row.id))
      entry.value:SetText(valueText(row))
      entry:ClearAllPoints()
      entry:SetPoint("TOPLEFT", mid, "TOPLEFT", 0, -y)
      entry:SetSize(width, rowH)
      y = y + rowH
    end
  end
  for index = #list + 1, #mid.rows do
    mid.rows[index]:Hide()
  end
end

-- Side of a slot cell: grows with the font size, shrinks until the centre keeps MID_MIN.
local function cellSize(width)
  local want = math.max(CELL_MIN, math.ceil(Theme.fontSize("micro") * 2.6))
  local room = math.floor((math.min(width, DOLL_MAX) - 2 * DOLL_GAP - MID_MIN) / 2)
  return math.max(CELL_FLOOR, math.min(want, room))
end

local function newBody(parent)
  local body = CreateFrame("Frame", nil, parent)
  local info = W.InfoButton(body, "gs.info", "gs.info.text")
  local pool = {}
  local left, right = {}, {}
  -- Created in reading order, so Tab walks the doll column by column.
  local cells = {}
  for _, ids in ipairs({ DOLL_LEFT, DOLL_RIGHT, DOLL_BOTTOM }) do
    for _, id in ipairs(ids) do
      cells[id] = newCell(body, id)
      cells[id].fgOn = false
      cells[id]:Hide()
    end
  end
  local mid = newMid(body)
  body.cells, body.mid = cells, mid

  -- Places a column of rows below y0, from pool index used + 1 on; returns the last index used and
  -- the bottom edge.
  local function column(list, x, width, used, y0)
    local y = y0
    for _, spec in ipairs(list) do
      used = used + 1
      pool[used] = pool[used] or newRow(body)
      local row = pool[used]
      setRow(row, spec)
      if spec.heading and y > y0 then
        y = y + ROW_GAP
      end
      local h = K.scaledHeight(spec.heading and HEAD_HEIGHT or ROW_HEIGHT)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y)
      row:SetSize(width, h)
      row:EnableMouse(spec.link ~= nil)
      row:Show()
      if spec.info then
        info:ClearAllPoints()
        info:SetPoint("LEFT", row.main, "LEFT", row.main:GetStringWidth() + 6, 0)
        info:SetFrameLevel(row:GetFrameLevel() + 2)
        info:Show()
      end
      y = y + h
    end
    return used, y
  end

  -- The rows in use, in placement order. For the tests.
  function body:Rows()
    local out = {}
    for _, row in ipairs(pool) do
      if row:IsShown() then
        out[#out + 1] = row
      end
    end
    return out
  end

  function body:SetData(result)
    body.result = result
    left = result and slotRows(result) or {}
    right = result and totalRows(result) or {}
    for id, cell in pairs(cells) do
      if result then
        setCell(cell, result, id)
      else
        cell.slot, cell.link, cell.fgOn = nil, nil, false
      end
      cell:Hide()
    end
    mid:Hide()
    info:Hide()
  end

  -- The doll at the top, at most DOLL_MAX wide and centred: the two columns, the weapon row below
  -- them and the centre between. Returns its height, 0 without data.
  local function layoutDoll(width)
    local result = body.result
    if not result then
      return 0
    end
    local cell = cellSize(width)
    local dw = math.min(width, DOLL_MAX)
    local x0 = math.floor((width - dw) / 2)
    local stripH = Theme.fontSize("micro") + 2
    local function put(c, x, y)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y)
      c:SetSize(cell, cell)
      c.strip:ClearAllPoints()
      c.strip:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", ICON_INSET, ICON_INSET)
      c.strip:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
      c.strip:SetHeight(stripH)
      c.flag:ClearAllPoints()
      c.flag:SetPoint("TOPRIGHT", c, "TOPRIGHT", -ICON_INSET, -ICON_INSET)
      c.flag:SetSize(stripH, stripH)
      c:Show()
    end
    local function stack(ids, x)
      local y = 0
      for _, id in ipairs(ids) do
        if cells[id].fgOn then
          put(cells[id], x, y)
          y = y + cell + CELL_GAP
        end
      end
      return math.max(0, y - CELL_GAP)
    end
    local columnsH = math.max(stack(DOLL_LEFT, x0), stack(DOLL_RIGHT, x0 + dw - cell))
    local weapons = {}
    for _, id in ipairs(DOLL_BOTTOM) do
      if cells[id].fgOn then
        weapons[#weapons + 1] = cells[id]
      end
    end
    local bottom = columnsH
    if #weapons > 0 then
      local total = #weapons * cell + (#weapons - 1) * CELL_GAP
      local y = columnsH > 0 and columnsH + DOLL_GAP or 0
      for index, c in ipairs(weapons) do
        put(c, x0 + math.floor((dw - total) / 2) + (index - 1) * (cell + CELL_GAP), y)
      end
      bottom = y + cell
    end
    local midW = dw - 2 * cell - 2 * DOLL_GAP
    local midH = math.max(columnsH, K.scaledHeight(HEAD_HEIGHT + 2 * ROW_HEIGHT))
    mid:ClearAllPoints()
    mid:SetPoint("TOPLEFT", body, "TOPLEFT", x0 + cell + DOLL_GAP, 0)
    mid:SetSize(midW, midH)
    mid:Show()
    layoutMid(mid, result, midW, midH)
    return math.max(bottom, midH)
  end

  -- The doll first, then the lists: side by side from TWO_COLUMNS on, else the totals below the slots.
  function body:fgGridLayout(width)
    local used, bottom
    local doll = layoutDoll(width)
    local y0 = doll > 0 and doll + SECTION_GAP or 0
    if width >= TWO_COLUMNS then
      local col = math.floor((width - COLUMN_GAP) / 2)
      local n, h1 = column(left, 0, col, 0, y0)
      local m, h2 = column(right, col + COLUMN_GAP, width - col - COLUMN_GAP, n, y0)
      used, bottom = m, math.max(h1, h2)
    else
      local n, h1 = column(left, 0, width, 0, y0)
      used, bottom = column(right, 0, width, n, h1 + COLUMN_GAP)
    end
    for index = used + 1, #pool do
      pool[index]:Hide()
    end
    bottom = math.max(bottom, 1)
    body:SetHeight(bottom)
    return bottom
  end
  return body
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local note = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 12 })
  local none = W.EmptyState(view.content, { text = "gs.none", icon = "eye" })
  s:Add(none, { gap = 0 })
  local body = newBody(view.content)
  s:Add(body, { gap = 10 })

  local function refresh()
    local state = P.State()
    local result = state == "ready" and P.data or nil
    none:SetTexts(state == "loading" and "insp.loading" or "gs.none")
    none:SetShown(result == nil)
    note:SetShown(result ~= nil)
    body:SetShown(result ~= nil)
    if result then
      note:SetText(noteText(result))
    end
    body:SetData(result)
    view:Layout()
  end

  view.body = body
  function view:Show()
    P.Update()
  end
  P.page = {
    refresh = refresh,
    visible = function()
      return container:IsVisible()
    end,
  }
  refresh()
  return view
end

-- Short view at the inspect window ---------------------------------------------------------

-- Anchored to the window itself at the upper right, outside. The side tab (InspectLink) hangs at
-- the lower right, so the rows are capped to the room between the two instead of being anchored to
-- the tab.
local function windowHeight()
  local f = frame()
  local ok, height = pcall(f.GetHeight, f)
  return ok and I.readable(height) and height > 0 and height or WINDOW_HEIGHT
end

local function rowHeight()
  return Theme.lineHeight(QUICK_ROW, "micro")
end

-- How many rows fit between the top of the short view and the side tab at the current font size.
local function capacity()
  local row = rowHeight()
  local free = windowHeight() - PANEL_TOP - (ns.InspectLink.REACH + PANEL_GAP)
  local fixed = 2 * PANEL_PAD + row + 4 + PANEL_GAP + MORE_HEIGHT
  return math.max(1, math.floor((free - fixed) / row))
end

-- Built on first use and never in combat.
local function ensurePanel()
  if panel then
    return panel
  end
  local f = frame()
  if not f or O.InCombat() then
    return nil
  end
  local ok, holder = pcall(CreateFrame, "Frame", nil, f)
  if not (ok and holder) then
    return nil
  end
  W.FadeWithWindow(W.Fill(holder, "surface", 1))
  W.Border(holder, "white")
  local rec = { holder = holder, rows = {} }
  rec.title = W.Text(holder, { key = "gs.quick.title", role = "micro", color = "accent2" })
  rec.title:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_PAD)
  rec.more = W.Button(holder, {
    key = "gs.more",
    width = MORE_WIDTH,
    height = MORE_HEIGHT,
    tooltip = "gs.more",
    tooltipText = "gs.more.tip",
    onClick = function()
      ns.Main.Show(ns.InspectLink.Target())
    end,
  })
  holder:SetWidth(PANEL_WIDTH)
  holder:SetPoint("TOPLEFT", f, "TOPRIGHT", ns.InspectLink.TAB_INSET, -PANEL_TOP)
  holder:Hide()
  panel = rec
  return rec
end

local function quickRow(rec, index)
  local row = rec.rows[index]
  if not row then
    row = {
      label = W.Text(rec.holder, { role = "micro", color = "textSecondary" }),
      value = W.Text(rec.holder, { role = "micro", color = "text", justify = "RIGHT" }),
      hit = CreateFrame("Frame", nil, rec.holder),
    }
    -- Hover only, and only on a row whose text had to be cut: it carries the full text.
    row.hit:EnableMouse(true)
    row.hit:Hide()
    row.hit:SetScript("OnEnter", function(self)
      ns.ShowTooltip(self, row.label.fgFull, row.value.fgFull)
    end)
    row.hit:SetScript("OnLeave", ns.HideTooltip)
    rec.rows[index] = row
  end
  return row
end

-- Rows of the short view, most important first: item level, enchants, empty sockets, talents,
-- guild, then the stats of the gear. { label, value, color (theme name) }.
local function quickEntries(result)
  local facts, unit = result.facts, result.unit
  local entries = {
    { L["gs.quick.level"], facts.average and I.format(facts.average) or "..." },
  }
  if facts.possible > 0 then
    local done = facts.enchanted >= facts.possible
    entries[#entries + 1] = {
      L["gs.quick.enchants"],
      string.format("%d/%d", facts.enchanted, facts.possible),
      done and "success" or "danger",
    }
  end
  entries[#entries + 1] =
    { L["gs.quick.sockets"], tostring(facts.emptySockets), facts.emptySockets > 0 and "danger" or "success" }
  if unit.talents then
    entries[#entries + 1] = { L["gs.quick.talents"], table.concat(unit.talents, "/") }
  end
  if unit.guild then
    entries[#entries + 1] = { L["gs.quick.guild"], unit.guild }
  end
  local stats = G.Quick(result)
  for _, row in ipairs(stats) do
    entries[#entries + 1] = { statLabel(row.id), valueText(row) }
  end
  if #stats == 0 then
    entries[#entries + 1] = { L["gs.noStats"], "" }
  end
  return entries
end

-- Writes one row between the left and the right edge of the inner width. The value keeps its own
-- width up to VALUE_SHARE of the row, the label takes the rest; whichever is cut ends in "..." and
-- the row gets the hover tooltip with the full text.
local function paintRow(rec, row, entry, y, inner, height)
  local label, value = row.label, row.value
  label.fgFull, value.fgFull = entry[1], entry[2]
  W.SetColor(value, entry[3] or "text")
  value:ClearAllPoints()
  value:SetPoint("TOPRIGHT", rec.holder, "TOPRIGHT", -PANEL_PAD, y)
  value:SetHeight(height)
  local shownValue = E.Fit(value, entry[2], inner * VALUE_SHARE)
  local valueWidth = entry[2] == "" and 0 or value:GetStringWidth()
  value:SetWidth(math.max(1, valueWidth))
  label:ClearAllPoints()
  label:SetPoint("TOPLEFT", rec.holder, "TOPLEFT", PANEL_PAD, y)
  label:SetHeight(height)
  local labelRoom = inner - valueWidth - (valueWidth > 0 and LABEL_GAP or 0)
  local shownLabel = E.Fit(label, entry[1], labelRoom)
  label:SetWidth(math.max(1, label:GetStringWidth()))
  row.hit:ClearAllPoints()
  row.hit:SetPoint("TOPLEFT", rec.holder, "TOPLEFT", PANEL_PAD, y)
  row.hit:SetSize(inner, height)
  row.hit:SetShown(shownLabel ~= entry[1] or shownValue ~= entry[2])
  label:Show()
  value:SetShown(entry[2] ~= "")
end

function P.PaintPanel()
  local result = P.State() == "ready" and enabled() and P.data or nil
  if not result then
    if panel then
      panel.holder:Hide()
    end
    return
  end
  local rec = ensurePanel()
  if not rec then
    return
  end
  local height = rowHeight()
  local inner = PANEL_WIDTH - 2 * PANEL_PAD
  local entries = quickEntries(result)
  local count = math.min(#entries, capacity())
  rec.title:SetHeight(height)
  for index = 1, count do
    paintRow(rec, quickRow(rec, index), entries[index], -(PANEL_PAD + height * index + 4), inner, height)
  end
  for index = count + 1, #rec.rows do
    local row = rec.rows[index]
    row.label:Hide()
    row.value:Hide()
    row.hit:Hide()
  end
  local bottom = PANEL_PAD + 4 + height * (count + 1) -- title row plus the rows
  rec.more:ClearAllPoints()
  rec.more:SetPoint("TOPLEFT", rec.holder, "TOPLEFT", PANEL_PAD, -(bottom + PANEL_GAP))
  rec.holder:SetHeight(bottom + PANEL_GAP + MORE_HEIGHT + PANEL_PAD)
  rec.holder:Show()
end

-- Refresh ------------------------------------------------------------------------------------

-- Reads the gear once for the page and the short view and paints both.
function P.Update()
  local wantsPage = P.page and P.page.visible()
  local wantsPanel = enabled() and shown(frame())
  P.data = nil
  if P.State() == "ready" and (wantsPage or wantsPanel) then
    P.data = P.Collect(V.Unit())
  end
  ns.Safe("inspect-panel", P.PaintPanel)
  if wantsPage then
    ns.Safe("inspect-page", P.page.refresh)
  end
end

-- Closing the window ends the short view and the page data at once. Showing and new data come
-- through InspectOverlay, which already bundles the event bursts into one timer.
function P.Install()
  local f = frame()
  if hooked or not f or type(f.HookScript) ~= "function" then
    return hooked == true
  end
  hooked = pcall(f.HookScript, f, "OnHide", P.Update)
  return hooked == true
end

function P.Panel()
  return panel
end

-- The settings section: the short view on or off.
function P.AddSettings(view)
  ns.AddHeading(view, "gs.setting.heading")
  view.stack:Add(
    W.Toggle(view.content, {
      key = "gs.setting.panel",
      get = enabled,
      set = function(v)
        Store.set("settings.inspectPanel", v)
      end,
      tooltip = "gs.setting.panel",
      tooltipText = "gs.setting.panel.tip",
    }),
    { height = 24, gap = 10 }
  )
end

ns.On("PLAYER_LOGIN", P.Install)
ns.On("ADDON_LOADED", P.Install)
ns.On("FG_INSPECT_REFRESHED", P.Update)
ns.On("FG_UI_REFRESHED", P.Update)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and (path:find("^settings%.inspectPanel") or path:find("^settings%.enchant")) then
    P.Update()
  end
end)

ns.RegisterPage({
  id = "inspect",
  order = 70,
  group = "character",
  title = "page.inspect",
  icon = ns.ICONS.inspect,
  aliases = { "untersuchen", "inspect", "betrachten" },
  build = build,
})
