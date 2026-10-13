-- Trainer capture: remembers class trainers the player opens in game, because
-- the shipped data has no Forever trainer for some class and faction pairs.
-- Sightings live in ns.db.trainerLog and feed ns.RefLogic.Trainers. The
-- position is where the player stood at the trainer window, so approximate.
-- A sighting carries a role: "pet" for a pet trainer (teaches the hunter's pet
-- only, see ns.TrainerRoles), "profession" for a profession trainer (no class,
-- carries prof = route slug or nil and ranks), else "class". Class sightings are
-- unique per NPC and class, profession sightings per NPC.
local _, ns = ...
local L, U = ns.L, ns.U

local TL = {}
ns.TrainerLog = TL

local MAX_ENTRIES = 100
local MAX_PROFESSIONS = 300
local MAX_NAME = 60
local MAX_ZONE = 60
TL.MAX_ENTRIES = MAX_ENTRIES
TL.MAX_PROFESSIONS = MAX_PROFESSIONS

-- Rank ids of the profession data in learning order, with the rank words of the
-- client (lower case, English and German).
local RANKS = { "apprentice", "journeyman", "expert", "artisan" }
local RANK_INDEX = {}
for i, rank in ipairs(RANKS) do
  RANK_INDEX[rank] = i
end
local RANK_WORDS = {
  apprentice = { "apprentice", "lehrling" },
  journeyman = { "journeyman", "geselle" },
  expert = { "expert", "experte" },
  artisan = { "artisan", "fachmann", "master", "meister" },
}
local RANK_OF = {}
for rank, words in pairs(RANK_WORDS) do
  for _, word in ipairs(words) do
    RANK_OF[word] = rank
  end
end

ns.AddLocale("enUS", {
  ["tl.saved"] = "Trainer recorded: %s",
  ["tl.savedPet"] = "Pet trainer recorded: %s",
  ["tl.savedProf"] = "Profession trainer recorded: %s (%s)",
  ["tl.profUnknown"] = "unknown",
  ["tl.full"] = "Trainer log full (%d entries): copy and clear it first",
  ["tl.note"] = "Recorded by you in game, position approximate",
  ["tl.copy"] = "Copy recorded trainers",
  ["tl.copyTip"] = "All recorded trainers, one line each",
  ["tl.clear"] = "Delete recorded trainers",
  ["tl.clear.title"] = "Delete recorded trainers",
  ["tl.clear.text"] = "Delete all recorded trainers (cannot be undone)?",
  ["tl.export.title"] = "Recorded trainers",
  ["tl.export.hint"] = "One line per trainer, for the website data",
  ["tl.export.header"] = "# Forever Guides: trainers recorded in game, for the website data. Position is where the player stood at the trainer, approximate.",
})

ns.AddLocale("deDE", {
  ["tl.saved"] = "Lehrer erfasst: %s",
  ["tl.savedPet"] = "Begleiter-Lehrer erfasst: %s",
  ["tl.savedProf"] = "Berufslehrer erfasst: %s (%s)",
  ["tl.profUnknown"] = "unbekannt",
  ["tl.full"] = "Lehrer-Log voll (%d Einträge): erst kopieren und löschen",
  ["tl.note"] = "Von dir im Spiel erfasst, Position ungefähr",
  ["tl.copy"] = "Erfasste Lehrer kopieren",
  ["tl.copyTip"] = "Alle erfassten Lehrer, eine Zeile je Lehrer",
  ["tl.clear"] = "Erfasste Lehrer löschen",
  ["tl.clear.title"] = "Erfasste Lehrer löschen",
  ["tl.clear.text"] = "Alle erfassten Lehrer löschen (nicht rückgängig)?",
  ["tl.export.title"] = "Erfasste Lehrer",
  ["tl.export.hint"] = "Eine Zeile pro Lehrer, für die Website-Daten",
  ["tl.export.header"] = "# Forever Guides: im Spiel erfasste Lehrer, für die Website-Daten. Die Position ist der Standort des Spielers am Lehrer, ungefähr.",
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

-- The role of a sighting: pet when it says so or the overlay knows the NPC id or name
-- (that also moves sightings recorded before roles existed).
local function roleOf(raw, name)
  if raw.role == "profession" then
    return "profession"
  end
  if raw.role == "pet" or ns.TrainerRoles.Of({ npc = raw.npc, name = name }) == "pet" then
    return "pet"
  end
  return "class"
end

-- A route slug ("alchemy", "first-aid") or nil. The slug lands in export lines,
-- so only lower case letters and hyphens pass.
local function cleanSlug(slug)
  if type(slug) == "string" and #slug <= 20 and slug:match("^%l[%l%-]*$") then
    return slug
  end
  return nil
end

-- Known rank ids only, each once, in learning order.
local function cleanRanks(ranks)
  local seen, out = {}, {}
  for _, rank in ipairs(type(ranks) == "table" and ranks or {}) do
    if RANK_INDEX[rank] then
      seen[rank] = true
    end
  end
  for _, rank in ipairs(RANKS) do
    if seen[rank] then
      out[#out + 1] = rank
    end
  end
  return out
end

-- SavedVariables are untrusted: keep only well-formed, de-duplicated entries.
local function cleanEntry(raw)
  if type(raw) ~= "table" or type(raw.npc) ~= "number" or raw.npc <= 0 then
    return nil
  end
  local name = cleanText(raw.name, MAX_NAME)
  local role = name and roleOf(raw, name)
  local class = type(raw.class) == "string" and raw.class:match("^%u+$") and raw.class:sub(1, 12) or nil
  local valid = name and (raw.faction == "A" or raw.faction == "H" or (role == "profession" and raw.faction == "N"))
  if not (valid and (class or role == "profession")) then
    return nil
  end
  local e = {
    npc = raw.npc,
    name = name,
    class = role ~= "profession" and class or nil,
    faction = raw.faction,
    role = role,
    zone = cleanText(raw.zone, MAX_ZONE) or "?",
    mapId = type(raw.mapId) == "number" and raw.mapId or nil,
    t = type(raw.t) == "number" and raw.t or 0,
    build = cleanText(type(raw.build) == "string" and raw.build or tostring(raw.build or ""), 20),
  }
  if role == "profession" then
    e.prof, e.ranks = cleanSlug(raw.prof), cleanRanks(raw.ranks)
  end
  if type(raw.x) == "number" and type(raw.y) == "number" then
    e.x, e.y = round3(U.clamp(raw.x, 0, 1)), round3(U.clamp(raw.y, 0, 1))
  end
  return e
end

local function key(e)
  return e.npc .. ":" .. (e.class or "profession")
end

local function limitOf(e)
  return e.role == "profession" and MAX_PROFESSIONS or MAX_ENTRIES
end

local function countRole(items, profession)
  local n = 0
  for _, e in ipairs(items) do
    if (e.role == "profession") == profession then
      n = n + 1
    end
  end
  return n
end

local checked
local function data()
  if type(ns.db) ~= "table" then
    return nil
  end
  local d = ns.db.trainerLog
  if type(d) ~= "table" then
    d = { v = 2, items = {} }
    ns.Store.set("trainerLog", d)
  end
  if checked ~= d then
    -- v1 held class sightings only and loads unchanged, v2 adds profession sightings.
    local clean, seen = {}, {}
    local classes, professions = 0, 0
    for _, raw in ipairs(type(d.items) == "table" and d.items or {}) do
      local e = cleanEntry(raw)
      local isProfession = e and e.role == "profession"
      local room = classes < MAX_ENTRIES
      if isProfession then
        room = professions < MAX_PROFESSIONS
      end
      if e and not seen[key(e)] and room then
        seen[key(e)] = true
        clean[#clean + 1] = e
        if isProfession then
          professions = professions + 1
        else
          classes = classes + 1
        end
      end
    end
    d.v, d.items = 2, clean
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

-- A repeated visit of a profession trainer: the newest position, zone and time
-- win (never replaced by a missing value), ranks only grow, a known profession
-- replaces an unknown one. Returns true when the profession was resolved.
local function updateProfession(old, e)
  local resolved = old.prof == nil and e.prof ~= nil
  old.name = e.name
  if e.faction ~= "N" then
    old.faction = e.faction
  end
  if e.zone ~= "?" then
    old.zone = e.zone
  end
  if e.x then
    old.mapId, old.x, old.y = e.mapId, e.x, e.y
  elseif e.mapId and not old.x then
    old.mapId = e.mapId
  end
  if e.prof then
    old.prof = e.prof
  end
  local ranks = {}
  for _, list in ipairs({ old.ranks, e.ranks }) do
    for _, rank in ipairs(list) do
      ranks[#ranks + 1] = rank
    end
  end
  old.ranks = cleanRanks(ranks)
  if e.t > 0 then
    old.t = e.t
  end
  old.build = e.build or old.build
  return resolved
end

-- Adds a sighting. Returns the entry, or nil plus a reason ("known", "full", "invalid").
-- A known profession trainer is updated; the third value says whether that resolved
-- its profession.
function TL.Add(raw)
  local e = cleanEntry(raw)
  local d = data()
  if not (e and d) then
    return nil, "invalid"
  end
  for _, old in ipairs(d.items) do
    if key(old) == key(e) then
      if e.role == "profession" then
        local resolved = updateProfession(old, e)
        ns.Store.set("trainerLog.items", d.items)
        return nil, "known", resolved
      end
      -- A sighting recorded as class trainer turns out to be a pet trainer.
      if e.role == "pet" and old.role ~= "pet" then
        old.role = "pet"
        ns.Store.set("trainerLog.items", d.items)
      end
      return nil, "known"
    end
  end
  if countRole(d.items, e.role == "profession") >= limitOf(e) then
    return nil, "full"
  end
  d.items[#d.items + 1] = e
  ns.Store.set("trainerLog.items", d.items)
  return e
end

-- Role detection, strongest signal first, each one only when the client has the
-- API. Without a signal the trainer stays a class trainer (the overlay names
-- are applied by cleanEntry).

-- The trainer window of a pet trainer reports the pet trainer type.
local function windowIsPetTrainer()
  if not (type(C_Trainer) == "table" and type(C_Trainer.GetTrainerType) == "function") then
    return false
  end
  if not (type(Enum) == "table" and type(Enum.TrainerType) == "table" and Enum.TrainerType.Pet ~= nil) then
    return false
  end
  local ok, kind = pcall(C_Trainer.GetTrainerType)
  return ok and kind == Enum.TrainerType.Pet
end

-- The NPC subtitle ("Pet Trainer") from the unit tooltip, else from the guild
-- line the client fills for NPCs.
local function subtitleIsPet(unit)
  if type(C_TooltipInfo) == "table" and type(C_TooltipInfo.GetUnit) == "function" then
    local ok, info = pcall(C_TooltipInfo.GetUnit, unit)
    if ok and type(info) == "table" and type(info.lines) == "table" then
      for i = 2, 3 do
        local line = info.lines[i]
        if type(line) == "table" and ns.TrainerRoles.IsPetSubtitle(line.leftText) then
          return true
        end
      end
    end
  end
  if type(GetGuildInfo) == "function" then
    local ok, guild = pcall(GetGuildInfo, unit)
    if ok and ns.TrainerRoles.IsPetSubtitle(guild) then
      return true
    end
  end
  return false
end

-- Every service of the open window is a pet ability. Names that are not loaded
-- yet count as no evidence.
local function offerIsPet()
  if not (type(GetNumTrainerServices) == "function" and type(GetTrainerServiceInfo) == "function") then
    return false
  end
  local okTotal, total = pcall(GetNumTrainerServices)
  if not (okTotal and type(total) == "number" and total > 0) then
    return false
  end
  local names = {}
  for i = 1, math.min(total, 400) do
    local ok, name = pcall(GetTrainerServiceInfo, i)
    names[#names + 1] = ok and name or false
  end
  return ns.TrainerRoles.OfferIsPet(names)
end

local function detectRole(unit)
  if windowIsPetTrainer() or subtitleIsPet(unit) or offerIsPet() then
    return "pet"
  end
  return "class"
end

-- Profession trainers -----------------------------------------------------------------
-- Same window as the class trainers. Evidence, strongest first: the client says
-- "tradeskill" (IsTradeskillTrainer, trainer type), or the services are rank
-- spells of a profession. The profession itself only comes from the services.

-- true or false when the client says whether this is a profession trainer, nil
-- without such an API. One positive answer wins.
local function tradeskillKind()
  local answer
  if type(IsTradeskillTrainer) == "function" then
    local ok, value = pcall(IsTradeskillTrainer)
    if ok and (value == true or value == false) then
      answer = value
    end
  end
  local hasType = type(C_Trainer) == "table" and type(C_Trainer.GetTrainerType) == "function"
  if hasType and type(Enum) == "table" and type(Enum.TrainerType) == "table" and Enum.TrainerType.Tradeskill ~= nil then
    local ok, kind = pcall(C_Trainer.GetTrainerType)
    if ok and kind ~= nil then
      answer = answer or kind == Enum.TrainerType.Tradeskill
    end
  end
  return answer
end

-- Lower case, no brackets or control characters, single spaces.
local function norm(text)
  if type(text) ~= "string" then
    return nil
  end
  text = U.trim((text:lower():gsub("[%c%(%)]", " "):gsub("%s+", " ")))
  return text ~= "" and text or nil
end

local professionNames
-- Lower case profession names in both languages to the route slug, from the
-- route table and the profession spells of the data (their German spelling varies).
local function nameIndex()
  if professionNames then
    return professionNames
  end
  professionNames = {}
  local professions = (ns.ProfessionRouteLogic and ns.ProfessionRouteLogic.PROFESSIONS) or {}
  local byEnglish = {}
  for slug, p in pairs(professions) do
    professionNames[norm(p.en)] = slug
    professionNames[norm(p.de)] = slug
    byEnglish[norm(p.en)] = slug
  end
  for _, s in ipairs((ns.Data and ns.Data.Spells and ns.Data.Spells.GENERAL) or {}) do
    local slug = s.k == "profession" and type(s.n) == "table" and byEnglish[norm(s.n.en)]
    if slug and norm(s.n.de) then
      professionNames[norm(s.n.de)] = slug
    end
  end
  return professionNames
end

-- Profession slug and rank id of a service name: "Alchemy", or "Journeyman Alchemy".
local function professionOfService(name)
  name = norm(name)
  if not name then
    return nil
  end
  local names = nameIndex()
  if names[name] then
    return names[name]
  end
  -- Rank word in front of the profession name.
  local space = name:find(" ", 1, true)
  local rank = space and RANK_OF[name:sub(1, space - 1)]
  local slug = rank and names[name:sub(space + 1)]
  if slug then
    return slug, rank
  end
  return nil
end

-- The profession and ranks the open window offers: { prof = slug|nil, ranks = {...} }.
-- The profession needs exactly one hit, two professions in one window are no
-- evidence. The rank comes from the name or from the sub text of the service.
local function readOffer()
  local out = { ranks = {} }
  if not (type(GetNumTrainerServices) == "function" and type(GetTrainerServiceInfo) == "function") then
    return out
  end
  local okTotal, total = pcall(GetNumTrainerServices)
  if not (okTotal and type(total) == "number" and total > 0) then
    return out
  end
  local ranksOf, slugs = {}, {}
  for i = 1, math.min(total, 400) do
    local res = { pcall(GetTrainerServiceInfo, i) }
    local slug, rank
    if res[1] then
      slug, rank = professionOfService(res[2])
    end
    if slug then
      if not ranksOf[slug] then
        ranksOf[slug] = {}
        slugs[#slugs + 1] = slug
      end
      for k = 3, 8 do
        local word = rank == nil and norm(res[k])
        rank = word and RANK_OF[word] or rank
      end
      if rank then
        table.insert(ranksOf[slug], rank)
      end
    end
  end
  if #slugs == 1 then
    out.prof, out.ranks = slugs[1], cleanRanks(ranksOf[slugs[1]])
  end
  return out
end

local function inCombat()
  return type(InCombatLockdown) == "function" and select(2, pcall(InCombatLockdown)) == true
end

-- "A" or "H" for a trainer of one faction, "N" for one that serves both (the
-- client reports no faction group then).
local function npcFaction(unit)
  local ok, group = pcall(function()
    return UnitFactionGroup(unit)
  end)
  return ok and (group == "Alliance" and "A" or group == "Horde" and "H") or "N"
end

local function professionLabel(prof)
  if prof and ns.ProfessionRouteLogic then
    return ns.ProfessionRouteLogic.Name(prof)
  end
  return L["tl.profUnknown"]
end

-- Stores the profession trainer of the open window. refresh = the window updated
-- (names load lazily): only a profession found now matters, silently.
local function recordProfession(unit, npc, offer, refresh)
  if (refresh and not offer.prof) or inCombat() then
    return
  end
  local name = cleanText(UnitName(unit), MAX_NAME)
  local mapId, x, y = playerPosition()
  local _, build = GetBuildInfo()
  local e, reason, resolved = TL.Add({
    role = "profession",
    npc = npc,
    name = name,
    faction = npcFaction(unit),
    prof = offer.prof,
    ranks = offer.ranks,
    zone = GetZoneText and GetZoneText() or nil,
    mapId = mapId,
    x = x,
    y = y,
    t = time and time() or 0,
    build = build,
  })
  if e or resolved then
    ns.Notify(string.format(L["tl.savedProf"], name, professionLabel(e and e.prof or offer.prof)), "success")
  elseif reason == "full" and not refresh then
    ns.Notify(string.format(L["tl.full"], MAX_PROFESSIONS), "warning")
  end
end

local function onTrainerShow(refresh)
  local unit, npc = trainerUnit()
  if not npc then
    return
  end
  local role = refresh and "class" or detectRole(unit)
  local kind = tradeskillKind()
  if kind ~= false and role ~= "pet" then
    local offer = readOffer()
    if kind == true or offer.prof then
      recordProfession(unit, npc, offer, refresh)
      return
    end
  end
  if refresh then
    return
  end
  local _, class = UnitClass("player")
  local f = UnitFactionGroup and UnitFactionGroup("player")
  local faction = f == "Alliance" and "A" or f == "Horde" and "H" or nil
  if not (class and faction) or knownOther(npc, class) then
    return
  end
  local mapId, x, y = playerPosition()
  local _, build = GetBuildInfo()
  local e, reason = TL.Add({
    npc = npc,
    name = UnitName(unit),
    class = class,
    faction = faction,
    role = role,
    zone = GetZoneText and GetZoneText() or nil,
    mapId = mapId,
    x = x,
    y = y,
    t = time and time() or 0,
    build = build,
  })
  if e then
    ns.Notify(string.format(L[e.role == "pet" and "tl.savedPet" or "tl.saved"], e.name), "success")
  elseif reason == "full" then
    ns.Notify(string.format(L["tl.full"], MAX_ENTRIES), "warning")
  end
end

ns.On("TRAINER_SHOW", function()
  pcall(onTrainerShow)
end)

-- The service names load after the window opens: a profession trainer seen with an
-- unreadable offer gets its profession and ranks from the following updates.
for _, event in ipairs({ "TRAINER_UPDATE", "TRAINER_SERVICE_INFO_NAME_UPDATE" }) do
  ns.On(event, function()
    pcall(onTrainerShow, true)
  end)
end

-- Reading ---------------------------------------------------------------------------

-- All sightings (class/faction optional) as copies in the shape of the trainer data.
-- Without a class the profession sightings are in it too (they have no class).
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

-- The profession trainer sightings: { npc, name, faction (A, H, N), prof = slug|nil,
-- ranks = rank ids in learning order, zone, mapId, x, y (0..1, nil without position),
-- t, build }.
function TL.Professions()
  local d = data()
  local out = {}
  for _, e in ipairs(d and d.items or {}) do
    if e.role == "profession" then
      out[#out + 1] = e
    end
  end
  return out
end

-- Class trainer entries shaped like Data trainers (x, y are 0..1 as there). k = "own" makes
-- the page show the "recorded by you" tag, cf = 1 marks the position as an estimate.
function TL.Entries(class, faction)
  local out = {}
  for _, e in ipairs(TL.Raw(class, faction)) do
    local note = { de = L["tl.note"], en = L["tl.note"] }
    if e.role == "pet" then
      local pet = ns.TrainerRoles.NOTE_PET
      note = { de = pet.de .. " " .. L["tl.note"], en = pet.en .. " " .. L["tl.note"] }
    end
    if e.role ~= "profession" then
      out[#out + 1] = {
        id = "log:" .. e.npc,
        c = e.class,
        f = e.faction,
        k = "own",
        own = true,
        role = e.role,
        n = { de = e.name, en = e.name },
        npc = e.npc,
        p = e.zone,
        m = e.mapId,
        x = e.x,
        y = e.y,
        cf = 1,
        nt = note,
      }
    end
  end
  return out
end

-- Export ------------------------------------------------------------------------------

-- One locale-independent line per sighting after a header line. A pet trainer ends
-- with " role=pet", a profession trainer (class=-) with " role=profession prof=<slug|->
-- ranks=<rank,rank|->": the lines of class trainers stay as they were.
function TL.BuildExport()
  local lines = { L["tl.export.header"] }
  for _, e in ipairs(TL.Raw()) do
    local pos = e.x and e.y and string.format("%.1f %.1f", e.x * 100, e.y * 100) or "-"
    local suffix = e.role == "pet" and " role=pet" or ""
    if e.role == "profession" then
      suffix = string.format(
        " role=profession prof=%s ranks=%s",
        e.prof or "-",
        #e.ranks > 0 and table.concat(e.ranks, ",") or "-"
      )
    end
    lines[#lines + 1] = string.format(
      'class=%s faction=%s name="%s" npc=%d zone="%s" map=%s pos=%s build=%s%s',
      e.class or "-",
      e.faction,
      e.name,
      e.npc,
      e.zone,
      e.mapId or "-",
      pos,
      e.build or "-",
      suffix
    )
  end
  return table.concat(lines, "\n")
end

function TL.Clear()
  if data() then
    ns.Store.set("trainerLog.items", {})
  end
end
