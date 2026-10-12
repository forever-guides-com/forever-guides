-- Loot capture: Forever has no adventure journal loot, so the addon writes down what bosses
-- really drop while the player loots them, and the player exports it (page "Loot",
-- /fg loot). The data goes back to the addon through the website database.
-- Stored in ns.db.lootCapture = { v, sinceBuild, npcs = { [npcId] = entry }, objects = { [objectId] = entry } },
-- entry = { name, eid, instance, instanceId, kills, t, items = { [itemId] = { n = corpses that dropped it,
-- qty = total quantity, q = quality, name, link } } }. No player names, only NPC ids and items.
-- Names are stored in the client language. eid is the encounter id paired with the NPC id, when known.
-- A boss name comes from, in this order: its unit (target, mouseover, boss1-5), the unit tooltip,
-- the seed table (confirmed pairs), the last ENCOUNTER_START (only when exactly one nameless NPC is
-- in the loot window). The combat log is never read: the client reserves its events for Blizzard.
--
-- Export (BuildExport), one header line then one line per boss and item, "|" separated:
--   FGLOOT v1 <build> <date>
--   instanceId|instance|npcId|npcName|kills|itemId|itemName|drops|qty|quality
-- npcId is "o<id>" for a game object (chest). A boss without a recorded item has no line.
-- The observed rate of an item is drops / kills. kills counts looted corpses, so
-- a corpse nobody looted is missing from both numbers. Text fields never contain "|" or quotes.
-- The website import reads exactly these columns.
local _, ns = ...
local L, U = ns.L, ns.U

local LC = {}
ns.LootCapture = LC

local MAX_NPCS = 400
local MAX_OBJECTS = 100
local MAX_ITEMS = 200 -- per boss
local MAX_TOTAL = 20000 -- items over all bosses
local MAX_SEEN = 200 -- corpses remembered per session
local MAX_COUNT = 1000000
local MAX_NAME = 60
local MAX_SLOTS = 120
local MAX_ITEM_NAME = 80
local MAX_LINK = 120
local ENCOUNTER_WINDOW = 30 * 60 -- seconds an ENCOUNTER_START can still name a looted boss
local MIN_KILLS = 5 -- below this the rate is too noisy to show
local ITEM_SLOT = 1 -- Enum.LootSlotType.Item
LC.MAX_NPCS, LC.MAX_OBJECTS, LC.MAX_ITEMS, LC.MAX_TOTAL = MAX_NPCS, MAX_OBJECTS, MAX_ITEMS, MAX_TOTAL
LC.MAX_SEEN, LC.MIN_KILLS = MAX_SEEN, MIN_KILLS

ns.AddLocale("enUS", {
  ["loot.intro"] = "Records what bosses drop when you loot them.\nCopy the list and send it for the website data.",
  ["loot.heading"] = "Loot capture",
  ["loot.enabled"] = "Record loot",
  ["loot.enabledTip"] = "Records boss loot.\nOnly items and NPC ids, no player names.",
  ["loot.outside"] = "Also record outside instances",
  ["loot.outsideTip"] = "Also loot outside instances, e.g. world bosses.\nDefault: off.",
  ["loot.minQuality"] = "Lowest quality recorded",
  ["loot.quality.1"] = "Common (white)",
  ["loot.quality.2"] = "Uncommon (green)",
  ["loot.quality.3"] = "Rare (blue)",
  ["loot.quality.4"] = "Epic (purple)",
  ["loot.summary"] = "%d bosses, %d items recorded",
  ["loot.fewKills"] = "Below %d kills: grey ? instead of rate",
  ["loot.empty"] = "Nothing recorded yet, loot a dungeon boss",
  ["loot.allInstances"] = "All instances",
  ["loot.instance"] = "Instance",
  ["loot.search"] = "Search boss or item",
  ["loot.boss.title"] = "%s (NPC %d)",
  ["loot.object.title"] = "%s (Object %d)",
  ["loot.boss.sub"] = "%d items",
  ["loot.boss.kills"] = "Kills: %d",
  ["loot.items.pick"] = "Pick a boss to see its items.",
  ["loot.items.none"] = "No items recorded for this boss yet.",
  ["loot.items.heading"] = "%s: %d items",
  ["loot.item.sub"] = "%d drops in %d kills · quantity %d",
  ["loot.item.unknown"] = "Item %d",
  ["loot.item.rate"] = "Drop rate: %d %%",
  ["loot.copy"] = "Copy as text",
  ["loot.copyTip"] = "All recorded bosses and items, one line each.",
  ["loot.clear"] = "Delete all",
  ["loot.clear.title"] = "Delete recorded loot",
  ["loot.clear.text"] = "Delete all recorded loot permanently?",
  ["loot.cleared"] = "Recorded loot deleted",
  ["loot.export.title"] = "Recorded loot",
  ["loot.export.hint"] = "One line per boss and item, for the website data",
  ["loot.full"] = "Record full: least seen entries are dropped, copy and delete the list",
})

ns.AddLocale("deDE", {
  ["loot.intro"] = "Zeichnet auf, was Bosse beim Plündern fallen lassen.\nKopiere die Liste für die Website-Daten.",
  ["loot.heading"] = "Beute-Erfassung",
  ["loot.enabled"] = "Beute erfassen",
  ["loot.enabledTip"] = "Erfasst Boss-Beute.\nNur Items und NPC-IDs, keine Spielernamen.",
  ["loot.outside"] = "Auch außerhalb von Instanzen erfassen",
  ["loot.outsideTip"] = "Auch Beute außerhalb von Instanzen, z. B. Weltbosse.\nStandard: aus.",
  ["loot.minQuality"] = "Niedrigste erfasste Qualität",
  ["loot.quality.1"] = "Gewöhnlich (weiß)",
  ["loot.quality.2"] = "Ungewöhnlich (grün)",
  ["loot.quality.3"] = "Selten (blau)",
  ["loot.quality.4"] = "Episch (lila)",
  ["loot.summary"] = "%d Bosse, %d Items erfasst",
  ["loot.fewKills"] = "Unter %d Kills: graues ? statt Rate",
  ["loot.empty"] = "Noch nichts erfasst, plündere einen Dungeon-Boss",
  ["loot.allInstances"] = "Alle Instanzen",
  ["loot.instance"] = "Instanz",
  ["loot.search"] = "Boss oder Item suchen",
  ["loot.boss.title"] = "%s (NPC %d)",
  ["loot.object.title"] = "%s (Objekt %d)",
  ["loot.boss.sub"] = "%d Items",
  ["loot.boss.kills"] = "Kills: %d",
  ["loot.items.pick"] = "Wähle einen Boss, um seine Items zu sehen.",
  ["loot.items.none"] = "Für diesen Boss ist noch kein Item erfasst.",
  ["loot.items.heading"] = "%s: %d Items",
  ["loot.item.sub"] = "%d Drops bei %d Kills · Menge %d",
  ["loot.item.unknown"] = "Item %d",
  ["loot.item.rate"] = "Drop-Chance: %d %%",
  ["loot.copy"] = "Als Text kopieren",
  ["loot.copyTip"] = "Alle erfassten Bosse und Items, eine Zeile pro Eintrag.",
  ["loot.clear"] = "Alles löschen",
  ["loot.clear.title"] = "Erfasste Beute löschen",
  ["loot.clear.text"] = "Alle erfasste Beute endgültig löschen?",
  ["loot.cleared"] = "Erfasste Beute gelöscht",
  ["loot.export.title"] = "Erfasste Beute",
  ["loot.export.hint"] = "Eine Zeile pro Boss und Item, für die Website-Daten",
  ["loot.full"] = "Erfassung voll: seltenste Einträge fallen weg, Liste kopieren und löschen",
})

-- Confirmed encounters (Forever Guides database) and the NPC ids seen to drop their loot.
-- Only pairs seen in the game belong in SEED; the other encounters just give their names.
local ENCOUNTERS = {
  [3353] = { de = "Welkzahn", en = "Witherfang" },
  [3354] = { de = "Rath'mael", en = "Rath'mael" },
  [3355] = { de = "Der Schlächter", en = "The Butcher" },
  [3357] = { de = "Der Verlassene", en = "The Abandoned" },
  [3408] = { de = "Hauptmann von Lordaeron", en = "Lordaeron Captain" },
  [3411] = { de = "Viktor der Üble", en = "Viktor the Vile" },
  [3412] = { de = "Bjork", en = "Bjork" },
}
local SEED = {
  [250657] = { instanceId = 2999, eid = 3354 }, -- Ruins of Lordaeron, Rath'mael
}

-- Game access ----------------------------------------------------------------------------

local function global(name)
  local f = rawget(_G, name)
  return type(f) == "function" and f or nil
end

-- Results of a protected call of a game function as a list with the count in n, nil when it
-- is missing or fails.
local function pack(name, ...)
  local f = global(name)
  if not f then
    return nil
  end
  local function results(ok, ...)
    if not ok then
      return nil
    end
    return { n = select("#", ...), ... }
  end
  return results(pcall(f, ...))
end

local function call(name, ...)
  local res = pack(name, ...)
  return res and res[1]
end

-- False for a secret value (restricted clients) that must not be compared or stored.
local function usable(v)
  local can, secret = global("canaccessvalue"), global("issecretvalue")
  if can then
    local ok, res = pcall(can, v)
    if not ok or res == false then
      return false
    end
  end
  if secret then
    local ok, res = pcall(secret, v)
    if not ok or res == true then
      return false
    end
  end
  return true
end

local function num(v, min)
  return usable(v) and type(v) == "number" and v == v and v >= (min or 0) and v < math.huge and v or nil
end

local function whole(v, min)
  v = num(v, min)
  return v and v == math.floor(v) and v or nil
end

-- Control characters, pipes and quotes would break the export lines.
local function text(v, max)
  if not (usable(v) and type(v) == "string") then
    return nil
  end
  return ns.TrainerLog.CleanText(v, max or MAX_NAME)
end

-- Settings ----------------------------------------------------------------------------------

local function setting(key)
  local s = ns.db and ns.db.settings
  return s and s[key]
end

function LC.Enabled()
  return setting("lootEnabled") ~= false
end

function LC.Outside()
  return setting("lootOutside") == true
end

function LC.MinQuality()
  local q = whole(setting("lootMinQuality"), 1)
  return q and math.min(q, 4) or 2
end

-- Storage ------------------------------------------------------------------------------------

-- Name of a confirmed encounter in the client language, nil for an unknown id.
local function encounterName(eid)
  local names = ENCOUNTERS[eid]
  if not names then
    return nil
  end
  return call("GetLocale") == "deDE" and names.de or names.en
end

-- Names { de, en } of a confirmed encounter id, nil for an unknown one.
function LC.EncounterNames(eid)
  return ENCOUNTERS[eid]
end

-- Names and pairs the seed table knows for NPCs already stored without them.
local function applySeed(d)
  for npcId, s in pairs(SEED) do
    local e = d.npcs[npcId]
    if e and e.instanceId == s.instanceId then
      e.name = e.name or encounterName(s.eid)
      e.eid = e.eid or s.eid
    end
  end
end

local function fresh()
  return { v = 1, sinceBuild = "", npcs = {}, objects = {} }
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

-- Keeps the most seen entries when a table holds too many.
local function sortedIds(t, score)
  local ids = {}
  for id in pairs(t) do
    ids[#ids + 1] = id
  end
  table.sort(ids, function(a, b)
    local sa, sb = score(t[a]), score(t[b])
    if sa ~= sb then
      return sa > sb
    end
    return a < b
  end)
  return ids
end

-- The "item:..." part of an item link, nil for anything else.
local function cleanLink(v)
  v = type(v) == "string" and #v <= MAX_LINK and v or nil
  return v and v:match("^item:[%d:%-]+$") and v or nil
end

local function cleanItems(raw)
  local items = {}
  for id, it in pairs(type(raw) == "table" and raw or {}) do
    local n = whole(type(it) == "table" and it.n, 1)
    if whole(id, 1) and n then
      items[id] = {
        n = math.min(n, MAX_COUNT),
        qty = math.min(whole(it.qty, 1) or n, MAX_COUNT),
        q = whole(it.q, 0) and math.min(it.q, 7) or 1,
        name = text(it.name, MAX_ITEM_NAME),
        link = cleanLink(it.link),
      }
    end
  end
  local ids = sortedIds(items, function(it)
    return it.n
  end)
  for i = MAX_ITEMS + 1, #ids do
    items[ids[i]] = nil
  end
  return items
end

local function cleanEntries(raw, limit)
  local out = {}
  for id, e in pairs(type(raw) == "table" and raw or {}) do
    if whole(id, 1) and type(e) == "table" then
      out[id] = {
        name = text(e.name),
        eid = whole(e.eid, 1),
        instance = text(e.instance),
        instanceId = whole(e.instanceId, 0) or 0,
        kills = math.min(whole(e.kills, 0) or 0, MAX_COUNT),
        t = num(e.t, 0) or 0,
        items = cleanItems(e.items),
      }
    end
  end
  local ids = sortedIds(out, function(e)
    return e.kills
  end)
  for i = limit + 1, #ids do
    out[ids[i]] = nil
  end
  return out
end

local checked, total, unnamed
-- SavedVariables are untrusted: the table is cleaned once, when it is first read.
local function data()
  if type(ns.db) ~= "table" then
    return nil
  end
  local d = ns.db.lootCapture
  if type(d) ~= "table" then
    d = fresh()
    ns.Store.set("lootCapture", d)
  end
  if checked ~= d then
    d.v = 1
    d.sinceBuild = text(d.sinceBuild, 20) or ""
    d.npcs = cleanEntries(d.npcs, MAX_NPCS)
    d.objects = cleanEntries(d.objects, MAX_OBJECTS)
    applySeed(d)
    total, unnamed = 0, 0
    for _, group in ipairs({ d.npcs, d.objects }) do
      for _, e in pairs(group) do
        total = total + countKeys(e.items)
        if not e.name then
          unnamed = unnamed + 1
        end
      end
    end
    checked = d
  end
  return d
end

-- Counts of what is stored: bosses (NPCs and objects), distinct items.
function LC.Counts()
  local d = data()
  local bosses, seen, items = 0, {}, 0
  for _, group in ipairs({ d and d.npcs or {}, d and d.objects or {} }) do
    for _, e in pairs(group) do
      bosses = bosses + 1
      for id in pairs(e.items) do
        if not seen[id] then
          seen[id] = true
          items = items + 1
        end
      end
    end
  end
  return bosses, items
end

-- Instance name to show: the data's name in the interface language, found by the instance id.
-- The stored client name stays the fallback (and the one the export carries).
local function instanceName(e)
  if e.instanceId > 0 then
    for _, inst in ipairs(ns.Data and ns.Data.Instances or {}) do
      if inst.id == e.instanceId then
        return ns.T(inst.n) or e.instance
      end
    end
  end
  return e.instance
end

-- Every stored source as { kind = "n"|"o", id, e, instance = shown instance name }, sorted by
-- instance, then name.
function LC.Bosses()
  local d = data()
  local out, names = {}, {}
  for kind, group in pairs({ n = d and d.npcs or {}, o = d and d.objects or {} }) do
    for id, e in pairs(group) do
      local key = e.instanceId .. "|" .. (e.instance or "")
      if names[key] == nil then
        names[key] = instanceName(e) or false
      end
      out[#out + 1] = { kind = kind, id = id, e = e, instance = names[key] or nil }
    end
  end
  table.sort(out, function(a, b)
    local ia, ib = (a.instance or ""):lower(), (b.instance or ""):lower()
    if ia ~= ib then
      return ia < ib
    end
    local na, nb = (a.e.name or "~"):lower(), (b.e.name or "~"):lower()
    if na ~= nb then
      return na < nb
    end
    if a.kind ~= b.kind then
      return a.kind < b.kind
    end
    return a.id < b.id
  end)
  return out
end

-- Distinct instances as { id, name } sorted by name; one entry per instance id.
function LC.Instances()
  local seen, out = {}, {}
  for _, b in ipairs(LC.Bosses()) do
    local id = b.e.instanceId
    if not seen[id] then
      seen[id] = true
      out[#out + 1] = { id = id, name = b.instance or "?" }
    end
  end
  return out
end

-- Drops per kill in percent, nil while there are too few kills for a trustworthy value.
function LC.Rate(kills, drops)
  if type(kills) ~= "number" or type(drops) ~= "number" or kills < MIN_KILLS or drops < 0 then
    return nil
  end
  local pct = math.min(100, math.floor(drops / kills * 100 + 0.5))
  return drops > 0 and math.max(pct, 1) or pct
end

local seenList, seenSet = {}, {}
-- Forgets which corpses were counted this session (tests, after a reset).
function LC.ResetSession()
  seenList, seenSet = {}, {}
end

function LC.Clear()
  if data() then
    ns.Store.set("lootCapture", fresh())
    checked = nil
    LC.ResetSession()
    ns.Emit("FG_LOOT_CAPTURE")
  end
end

-- Asks first, then deletes everything.
function LC.ConfirmClear(after)
  ns.Dialogs.Confirm("loot.clear.title", "loot.clear.text", function()
    LC.Clear()
    ns.Notify(L["loot.cleared"], "success")
    if after then
      after()
    end
  end)
end

-- Making room ---------------------------------------------------------------------------------

local warned
local function warnFull()
  if not warned then
    warned = true
    ns.Notify(L["loot.full"], "warning")
  end
end

-- Drops the least seen entry of a table (fewest kills, then oldest). `keep` stays.
local function evict(group, keep)
  local worst, worstId
  for id, e in pairs(group) do
    if e ~= keep and (not worst or e.kills < worst.kills or (e.kills == worst.kills and e.t < worst.t)) then
      worst, worstId = e, id
    end
  end
  if not worst then
    return false
  end
  group[worstId] = nil
  total = total - countKeys(worst.items)
  if not worst.name then
    unnamed = unnamed - 1
  end
  warnFull()
  return true
end

local function evictItem(e)
  local worst, worstId
  for id, it in pairs(e.items) do
    if not worst or it.n < worst.n or (it.n == worst.n and (it.q < worst.q or (it.q == worst.q and id < worstId))) then
      worst, worstId = it, id
    end
  end
  e.items[worstId] = nil
  total = total - 1
  warnFull()
end

-- Capture ----------------------------------------------------------------------------------------

-- "Creature-0-server-instance-zone-npcId-spawn" -> "n", npcId; "GameObject-..." -> "o", objectId.
-- Pets, players, items and everything else give nil.
function LC.ParseGuid(guid)
  if not (usable(guid) and type(guid) == "string") then
    return nil
  end
  local parts = {}
  for part in (guid .. "-"):gmatch("([^-]*)-") do
    parts[#parts + 1] = part
  end
  local kind = parts[1]
  local id = whole(tonumber(parts[6]), 1)
  if not id then
    return nil
  end
  if kind == "Creature" or kind == "Vehicle" then
    return "n", id
  elseif kind == "GameObject" then
    return "o", id
  end
  return nil
end

-- Units that can tell the name or the state of a looted creature.
local UNITS = { "target", "mouseover", "boss1", "boss2", "boss3", "boss4", "boss5" }

-- The unit whose GUID is `guid`, nil when none is.
local function unitOf(guid)
  for _, unit in ipairs(UNITS) do
    local g = call("UnitGUID", unit)
    if usable(g) and g == guid then
      return unit
    end
  end
end

-- Where the loot window opened: name and id of the instance, or the zone outside when allowed.
local function context()
  local res = pack("GetInstanceInfo")
  local kind = res and usable(res[2]) and res[2]
  if kind == "party" or kind == "raid" then
    local name, id = text(res[1]), whole(res[8], 1)
    if name and id then
      return { name = name, id = id }
    end
    return nil
  end
  if LC.Outside() then
    return { name = text(call("GetZoneText")) or "?", id = 0 }
  end
  return nil
end

-- A loot slot that holds an item: itemId, quality, quantity, name, link (the "item:..." part),
-- nil for another kind of slot. The name is the slot's, else the text of the link.
local function readItem(slot, itemType)
  local slotType = call("GetLootSlotType", slot)
  local isItem
  if slotType ~= nil then
    isItem = slotType == itemType
  else
    isItem = call("LootSlotHasItem", slot) == true
  end
  if not isItem then
    return nil
  end
  local link = call("GetLootSlotLink", slot)
  local itemId = usable(link) and type(link) == "string" and whole(tonumber(link:match("item:(%d+)")), 1) or nil
  if not itemId then
    return nil
  end
  local info = pack("GetLootSlotInfo", slot) or {}
  local quality = whole(info[5], 0)
  if quality == nil then
    quality = whole((pack("GetItemInfo", itemId) or {})[3], 0)
  end
  local name = text(info[2], MAX_ITEM_NAME) or text(link:match("%[(.-)%]"), MAX_ITEM_NAME)
  return quality and itemId, quality, whole(info[3], 1) or 1, name, cleanLink(link:match("|H(item:[%d:%-]*)|h"))
end

-- Every source of the open loot window as list of { guid, kind, id, unit, items = { [itemId] = { qty, q, name, link } } }.
-- Money slots count too, so a corpse with only gold is still one kill.
local function readSlots(minQuality)
  local slots = whole(call("GetNumLootItems"), 1)
  local sources, byGuid = {}, {}
  if not slots then
    return sources
  end
  local itemType = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or ITEM_SLOT
  for slot = 1, math.min(slots, MAX_SLOTS) do
    local res = pack("GetLootSourceInfo", slot) or { n = 0 }
    local itemId, quality, quantity, itemName, itemLink = readItem(slot, itemType)
    if itemId and quality < minQuality then
      itemId = nil
    end
    for i = 1, res.n, 2 do
      local guid = res[i]
      local kind, id = LC.ParseGuid(guid)
      if kind then
        local src = byGuid[guid]
        if not src then
          src = { guid = guid, kind = kind, id = id, unit = unitOf(guid), items = {} }
          byGuid[guid] = src
          sources[#sources + 1] = src
        end
        if itemId then
          -- A slot of several corpses lists the share of each one.
          local share = whole(res[i + 1], 1) or quantity
          local it = src.items[itemId]
          if it then
            it.qty = it.qty + share
          else
            src.items[itemId] = { qty = share, q = quality, name = itemName, link = itemLink }
          end
        end
      end
    end
  end
  return sources
end

local function remember(guid)
  seenSet[guid] = true
  seenList[#seenList + 1] = guid
  if #seenList > MAX_SEEN then
    seenSet[table.remove(seenList, 1)] = nil
  end
end

-- `seen` is { qty, q, name, link } of one looted corpse. The newest known name and link win,
-- so a client language change renames the item.
local function addItem(e, id, seen)
  local it = e.items[id]
  if not it then
    if countKeys(e.items) >= MAX_ITEMS then
      evictItem(e)
    end
    it = { n = 0, qty = 0, q = seen.q }
    e.items[id] = it
    total = total + 1
  end
  it.n = math.min(it.n + 1, MAX_COUNT)
  it.qty = math.min(it.qty + seen.qty, MAX_COUNT)
  it.q = seen.q
  it.name = seen.name or it.name
  it.link = seen.link or it.link
end

-- Frees an item slot of the total budget by dropping the least seen other boss.
local function makeRoom(d, keep)
  return evict(d.npcs, keep) or evict(d.objects, keep)
end

-- First line of the unit tooltip of a GUID, nil when the API is missing or has no answer.
local function tooltipName(guid)
  local api = rawget(_G, "C_TooltipInfo")
  local get = type(api) == "table" and api.GetHyperlink
  if type(get) ~= "function" then
    return nil
  end
  local ok, tip = pcall(get, "unit:" .. guid)
  local line = ok and type(tip) == "table" and type(tip.lines) == "table" and tip.lines[1]
  return type(line) == "table" and text(line.leftText) or nil
end

-- Name of a looted creature or chest from what the client knows about this very corpse.
local function sourceName(src)
  local name = src.unit and text(call("UnitName", src.unit))
  if name or src.kind ~= "n" then
    return name
  end
  return tooltipName(src.guid)
end

-- The encounter that started last: { id, name, instanceId, t }.
local encounter

ns.On("ENCOUNTER_START", function(_, id, name)
  local ctx = LC.Enabled() and context()
  id = whole(id, 1)
  name = text(name) or (id and encounterName(id))
  if ctx and id and name then
    encounter = { id = id, name = name, instanceId = ctx.id, t = U.now() }
  end
end)

-- The remembered encounter when it started in this instance a short while ago.
local function recentEncounter(ctx)
  local e = encounter
  if e and e.instanceId == ctx.id and U.now() - e.t <= ENCOUNTER_WINDOW then
    return e
  end
end

-- Names the sources of one loot window that nothing else named. Returns nothing, sets src.name
-- and src.eid. The encounter is only a guess for a window with exactly one nameless NPC.
local function nameSources(d, sources, ctx)
  local nameless = {}
  for _, src in ipairs(sources) do
    local group = src.kind == "o" and d.objects or d.npcs
    local e = group[src.id]
    local seed = src.kind == "n" and SEED[src.id]
    seed = seed and seed.instanceId == ctx.id and seed or nil
    src.eid = seed and seed.eid
    if not (e and e.name) then
      src.name = sourceName(src) or (seed and encounterName(seed.eid))
      if not src.name and src.kind == "n" then
        nameless[#nameless + 1] = src
      end
    end
  end
  local guess = #nameless == 1 and recentEncounter(ctx)
  if guess then
    nameless[1].name, nameless[1].eid = guess.name, guess.id
    encounter = nil
  end
end

-- Counts one looted corpse (or chest) with its items. Returns false when nothing could be stored.
local function record(d, src, ctx, build)
  local group = src.kind == "o" and d.objects or d.npcs
  local e = group[src.id]
  if not e then
    if countKeys(group) >= (src.kind == "o" and MAX_OBJECTS or MAX_NPCS) and not evict(group) then
      return false
    end
    e = { kills = 0, t = 0, items = {} }
    group[src.id] = e
    unnamed = unnamed + 1
  end
  if src.name and not e.name then
    e.name = src.name
    unnamed = unnamed - 1
  end
  e.eid = e.eid or src.eid
  e.instance, e.instanceId = ctx.name, ctx.id
  e.kills = math.min(e.kills + 1, MAX_COUNT)
  e.t = U.now()
  for id, it in pairs(src.items) do
    if e.items[id] or total < MAX_TOTAL or makeRoom(d, e) then
      addItem(e, id, it)
    else
      -- No room anywhere: the corpse still counts as a kill, this item is left out.
      warnFull()
    end
  end
  if d.sinceBuild == "" then
    d.sinceBuild = text(tostring(build or ""), 20) or ""
  end
  return true
end

-- Reads the open loot window. Returns how many corpses or chests were counted.
function LC.Capture()
  if not LC.Enabled() then
    return 0
  end
  local d = data()
  local ctx = d and context()
  if not ctx or call("IsFishingLoot") == true then
    return 0
  end
  local counted = 0
  local build = (pack("GetBuildInfo") or {})[2]
  local looted = {}
  for _, src in ipairs(readSlots(math.max(LC.MinQuality(), 1))) do
    -- A living creature is pickpocketed, not killed: its real loot comes later.
    local alive = src.unit and call("UnitIsDead", src.unit) == false
    if not seenSet[src.guid] and not alive then
      looted[#looted + 1] = src
    end
  end
  nameSources(d, looted, ctx)
  for _, src in ipairs(looted) do
    remember(src.guid)
    if record(d, src, ctx, build) then
      counted = counted + 1
      if src.kind == "n" then
        local e = d.npcs[src.id]
        ns.Emit("FG_LOOT_SOURCE", ctx.id, src.id, e and e.name, e and e.eid)
      end
    end
  end
  if counted > 0 then
    ns.Emit("FG_LOOT_CAPTURE")
  end
  return counted
end

-- Looted corpses of an unknown name get it when the player later targets the same NPC.
function LC.FillNames()
  local d = unnamed and unnamed > 0 and data()
  if not d then
    return 0
  end
  local filled = 0
  for _, unit in ipairs(UNITS) do
    local kind, id = LC.ParseGuid(call("UnitGUID", unit))
    local e = kind and (kind == "o" and d.objects or d.npcs)[id]
    local name = e and not e.name and text(call("UnitName", unit))
    if name then
      e.name = name
      unnamed = unnamed - 1
      filled = filled + 1
    end
  end
  return filled
end

ns.On("LOOT_READY", function()
  LC.Capture()
end)
ns.On("LOOT_OPENED", function()
  LC.Capture()
end)
for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }) do
  ns.On(event, function()
    LC.FillNames()
  end)
end

-- Items -----------------------------------------------------------------------------------------

local requested = {}
-- Name of an item: the stored one, else the client's. An entry `it` stored without a name (older
-- versions) keeps the client's name once it is known. nil while the client has not loaded the
-- item; unless quiet, it is asked to load it once per session (a missing item would otherwise be
-- asked again after every answer).
function LC.ItemName(id, quiet, it)
  if it and it.name then
    return it.name
  end
  local res = pack("GetItemInfo", id)
  local name = res and text(res[1], MAX_ITEM_NAME)
  if name and it then
    it.name = name
  end
  if not (name or quiet or requested[id]) then
    requested[id] = true
    local C_Item = rawget(_G, "C_Item")
    local request = type(C_Item) == "table" and C_Item.RequestLoadItemDataByID
    if type(request) == "function" then
      pcall(request, id)
    end
  end
  return name
end

function LC.ItemIcon(id)
  local C_Item = rawget(_G, "C_Item")
  local byId = type(C_Item) == "table" and C_Item.GetItemIconByID
  local ok, icon = false, nil
  if type(byId) == "function" then
    ok, icon = pcall(byId, id)
  end
  if ok and icon then
    return icon
  end
  local res = pack("GetItemInfoInstant", id)
  return res and res[5] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Export ------------------------------------------------------------------------------------------

-- The items of a source sorted by id.
function LC.SortedItems(e)
  local ids = {}
  for id in pairs(e.items) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

-- Header line plus one line per boss and item (columns in the file header above).
function LC.BuildExport()
  local build = (pack("GetBuildInfo") or {})[2]
  local stamp = global("date")
  local lines = { string.format("FGLOOT v1 %s %s", tostring(build or "-"), stamp and stamp("%Y-%m-%d") or "-") }
  local bosses = LC.Bosses()
  table.sort(bosses, function(a, b)
    if a.e.instanceId ~= b.e.instanceId then
      return a.e.instanceId < b.e.instanceId
    end
    if a.kind ~= b.kind then
      return a.kind == "n"
    end
    return a.id < b.id
  end)
  for _, b in ipairs(bosses) do
    local e = b.e
    for _, id in ipairs(LC.SortedItems(e)) do
      local it = e.items[id]
      lines[#lines + 1] = string.format(
        "%d|%s|%s%d|%s|%d|%d|%s|%d|%d|%d",
        e.instanceId,
        e.instance or "?",
        b.kind == "o" and "o" or "",
        b.id,
        e.name or "?",
        e.kills,
        id,
        LC.ItemName(id, false, it) or "?",
        it.n,
        it.qty,
        it.q
      )
    end
  end
  return table.concat(lines, "\n")
end
