-- Trainer capture: remembers class trainers the player opens in game, because
-- the shipped data has no Forever trainer for some class and faction pairs.
-- Sightings live in ns.db.trainerLog and feed ns.RefLogic.Trainers. The
-- position is where the player stood at the trainer window, so approximate.
local _, ns = ...
local L, U = ns.L, ns.U

local TL = {}
ns.TrainerLog = TL

local MAX_ENTRIES = 100
local MAX_NAME = 60
local MAX_ZONE = 60
TL.MAX_ENTRIES = MAX_ENTRIES

ns.AddLocale("enUS", {
  ["tl.saved"] = "Trainer recorded: %s",
  ["tl.full"] = "Trainer log full (%d entries): copy and clear it first",
  ["tl.note"] = "Recorded by you in game, position approximate",
  ["tl.copy"] = "Copy recorded trainers",
  ["tl.copyTip"] = "All recorded trainers, one line each",
  ["tl.clear"] = "Delete recorded trainers",
  ["tl.clear.title"] = "Delete recorded trainers",
  ["tl.clear.text"] = "Delete all recorded trainers (cannot be undone)?",
  ["tl.export.title"] = "Recorded trainers",
  ["tl.export.hint"] = "One line per trainer, for the website data",
  ["tl.export.header"] = "# Forever Guides: class trainers recorded in game, for the website data. Position is where the player stood at the trainer, approximate.",
})

ns.AddLocale("deDE", {
  ["tl.saved"] = "Lehrer erfasst: %s",
  ["tl.full"] = "Lehrer-Log voll (%d Einträge): erst kopieren und löschen",
  ["tl.note"] = "Von dir im Spiel erfasst, Position ungefähr",
  ["tl.copy"] = "Erfasste Lehrer kopieren",
  ["tl.copyTip"] = "Alle erfassten Lehrer, eine Zeile je Lehrer",
  ["tl.clear"] = "Erfasste Lehrer löschen",
  ["tl.clear.title"] = "Erfasste Lehrer löschen",
  ["tl.clear.text"] = "Alle erfassten Lehrer löschen (nicht rückgängig)?",
  ["tl.export.title"] = "Erfasste Lehrer",
  ["tl.export.hint"] = "Eine Zeile pro Lehrer, für die Website-Daten",
  ["tl.export.header"] = "# Forever Guides: im Spiel erfasste Klassenlehrer, für die Website-Daten. Die Position ist der Standort des Spielers am Lehrer, ungefähr.",
})

-- Sanitizing ---------------------------------------------------------------------

-- Control characters, pipes and quotes would break chat/UI escapes and the
-- export lines. Truncation never leaves half a UTF-8 character behind.
local function cleanText(text, max)
  if type(text) ~= "string" then
    return nil
  end
  text = U.trim((text:gsub('[%c|"]', " ")))
  if text == "" then
    return nil
  end
  if #text > max then
    text = text:sub(1, max):gsub("[\192-\255][\128-\191]*$", "")
    text = U.trim(text)
  end
  return text ~= "" and text or nil
end
TL.CleanText = cleanText

-- "Creature-0-server-instance-zone-npcId-spawn" -> npcId, or nil for anything else.
function TL.ParseGuid(guid)
  if type(guid) ~= "string" then
    return nil
  end
  local parts = U.split(guid, "-")
  if parts[1] ~= "Creature" then
    return nil
  end
  local id = tonumber(parts[6])
  if id and id > 0 and id == math.floor(id) then
    return id
  end
  return nil
end

local function round3(v)
  return math.floor(v * 1000 + 0.5) / 1000
end

-- SavedVariables are untrusted: keep only well-formed, de-duplicated entries.
local function cleanEntry(raw)
  if type(raw) ~= "table" or type(raw.npc) ~= "number" or raw.npc <= 0 then
    return nil
  end
  local class = type(raw.class) == "string" and raw.class:match("^%u+$") and raw.class:sub(1, 12) or nil
  local name = cleanText(raw.name, MAX_NAME)
  if not (class and name and (raw.faction == "A" or raw.faction == "H")) then
    return nil
  end
  local e = {
    npc = raw.npc,
    name = name,
    class = class,
    faction = raw.faction,
    zone = cleanText(raw.zone, MAX_ZONE) or "?",
    mapId = type(raw.mapId) == "number" and raw.mapId or nil,
    t = type(raw.t) == "number" and raw.t or 0,
    build = cleanText(type(raw.build) == "string" and raw.build or tostring(raw.build or ""), 20),
  }
  if type(raw.x) == "number" and type(raw.y) == "number" then
    e.x, e.y = round3(U.clamp(raw.x, 0, 1)), round3(U.clamp(raw.y, 0, 1))
  end
  return e
end

local function key(e)
  return e.npc .. ":" .. e.class
end

local checked
local function data()
  if type(ns.db) ~= "table" then
    return nil
  end
  local d = ns.db.trainerLog
  if type(d) ~= "table" then
    d = { v = 1, items = {} }
    ns.Store.set("trainerLog", d)
  end
  if checked ~= d then
    local clean, seen = {}, {}
    for _, raw in ipairs(type(d.items) == "table" and d.items or {}) do
      local e = cleanEntry(raw)
      if e and not seen[key(e)] and #clean < MAX_ENTRIES then
        seen[key(e)] = true
        clean[#clean + 1] = e
      end
    end
    d.v, d.items = 1, clean
    checked = d
  end
  return d
end

-- Capture ---------------------------------------------------------------------------

-- True when the NPC is known to be something other than a class trainer of
-- this class: a class trainer of another class or a weapon master.
local function knownOther(npc, class)
  local D = ns.Data or {}
  for _, t in ipairs((D.Trainers and D.Trainers.trainers) or {}) do
    if t.npc == npc and t.c ~= class then
      return true
    end
  end
  for _, t in ipairs((D.Weapons and D.Weapons.trainers) or {}) do
    if t.npc == npc then
      return true
    end
  end
  return false
end

local function playerPosition()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
    return nil
  end
  local okMap, mapId = pcall(C_Map.GetBestMapForUnit, "player")
  if not (okMap and type(mapId) == "number") then
    return nil
  end
  local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapId, "player")
  if not (okPos and type(pos) == "table" and pos.GetXY) then
    return mapId
  end
  local okXY, x, y = pcall(pos.GetXY, pos)
  if okXY and type(x) == "number" and type(y) == "number" and not (x == 0 and y == 0) then
    return mapId, x, y
  end
  return mapId
end

-- The NPC the trainer window belongs to: unit "npc" while the window is open,
-- the target as fallback.
local function trainerUnit()
  for _, unit in ipairs({ "npc", "target" }) do
    local guid = UnitGUID and UnitGUID(unit)
    if guid then
      -- A resolved "npc" that is no creature must not fall back to the target.
      return unit, TL.ParseGuid(guid)
    end
  end
end

-- Adds a sighting. Returns the entry, or nil plus a reason ("known", "full", "invalid").
function TL.Add(raw)
  local e = cleanEntry(raw)
  local d = data()
  if not (e and d) then
    return nil, "invalid"
  end
  for _, old in ipairs(d.items) do
    if key(old) == key(e) then
      return nil, "known"
    end
  end
  if #d.items >= MAX_ENTRIES then
    return nil, "full"
  end
  d.items[#d.items + 1] = e
  ns.Store.set("trainerLog.items", d.items)
  return e
end

local function onTrainerShow()
  local _, class = UnitClass("player")
  local f = UnitFactionGroup and UnitFactionGroup("player")
  local faction = f == "Alliance" and "A" or f == "Horde" and "H" or nil
  local unit, npc = trainerUnit()
  if not (class and faction and npc) then
    return
  end
  -- Profession trainers open the same window. When the client cannot tell,
  -- the sighting is accepted and filtered by knownOther and on the website.
  if IsTradeskillTrainer and IsTradeskillTrainer() == true then
    return
  end
  if knownOther(npc, class) then
    return
  end
  local mapId, x, y = playerPosition()
  local _, build = GetBuildInfo()
  local e, reason = TL.Add({
    npc = npc,
    name = UnitName(unit),
    class = class,
    faction = faction,
    zone = GetZoneText and GetZoneText() or nil,
    mapId = mapId,
    x = x,
    y = y,
    t = time and time() or 0,
    build = build,
  })
  if e then
    ns.Notify(string.format(L["tl.saved"], e.name), "success")
  elseif reason == "full" then
    ns.Notify(string.format(L["tl.full"], MAX_ENTRIES), "warning")
  end
end

ns.On("TRAINER_SHOW", function()
  pcall(onTrainerShow)
end)

-- Reading ---------------------------------------------------------------------------

-- All sightings (class/faction optional) as copies in the shape of the trainer data.
function TL.Raw(class, faction)
  local d = data()
  local out = {}
  for _, e in ipairs(d and d.items or {}) do
    if (not class or e.class == class) and (not faction or faction == "all" or e.faction == faction) then
      out[#out + 1] = e
    end
  end
  return out
end

function TL.Count()
  local d = data()
  return d and #d.items or 0
end

-- Entries shaped like Data trainers (x, y are 0..1 as there). k = "own" makes
-- the page show the "recorded by you" tag, cf = 1 marks the position as an estimate.
function TL.Entries(class, faction)
  local out = {}
  for _, e in ipairs(TL.Raw(class, faction)) do
    out[#out + 1] = {
      id = "log:" .. e.npc,
      c = e.class,
      f = e.faction,
      k = "own",
      own = true,
      n = { de = e.name, en = e.name },
      npc = e.npc,
      p = e.zone,
      m = e.mapId,
      x = e.x,
      y = e.y,
      cf = 1,
      nt = { de = L["tl.note"], en = L["tl.note"] },
    }
  end
  return out
end

-- Export ------------------------------------------------------------------------------

-- One locale-independent line per sighting after a header line.
function TL.BuildExport()
  local lines = { L["tl.export.header"] }
  for _, e in ipairs(TL.Raw()) do
    local pos = e.x and e.y and string.format("%.1f %.1f", e.x * 100, e.y * 100) or "-"
    lines[#lines + 1] = string.format(
      'class=%s faction=%s name="%s" npc=%d zone="%s" map=%s pos=%s build=%s',
      e.class,
      e.faction,
      e.name,
      e.npc,
      e.zone,
      e.mapId or "-",
      pos,
      e.build or "-"
    )
  end
  return table.concat(lines, "\n")
end

function TL.Clear()
  if data() then
    ns.Store.set("trainerLog.items", {})
  end
end
