-- Price capture: while a class trainer or weapon master window is open, reads
-- what the client shows for each service and remembers it account-wide in
-- ns.db.trainerCosts. Observed prices win over the shipped Classic data
-- (ns.CostLogic), so the player sees what he really pays, reputation discounts
-- included. Entries are keyed "SCOPE:spellId", scope = class token of the
-- player or "WM" for known weapon masters (a few skills like Plate cost
-- differently per class).
local _, ns = ...
local L, U = ns.L, ns.U

local CC = {}
ns.CostCapture = CC

local MAX_ENTRIES = 4000
local MAX_COST = 100000000 -- 10000 gold, far above any trainer price
local MAX_NAME = 60
local DEBOUNCE = 0.3
CC.MAX_ENTRIES = MAX_ENTRIES

ns.AddLocale("enUS", {
  ["cc.saved"] = "%d trainer prices recorded",
  ["cc.copy"] = "Copy recorded prices",
  ["cc.copyTip"] = "All recorded prices, one line each",
  ["cc.clear"] = "Delete recorded prices",
  ["cc.clear.title"] = "Delete recorded prices",
  ["cc.clear.text"] = "Delete recorded prices?\nClassic prices apply until you visit the trainers (cannot be undone).",
  ["cc.export.title"] = "Recorded prices",
  ["cc.export.hint"] = "One line per price, for the website data",
  ["cc.export.header"] = '# Forever Guides: trainer prices seen in game. Fields: spellId copper requiredLevel npc "name" rank class build shippedCopper (the price of the shipped data, - = none). Copper: 10000 = 1 gold, 100 = 1 silver.',
})

ns.AddLocale("deDE", {
  ["cc.saved"] = "%d Lehrerpreise erfasst",
  ["cc.copy"] = "Erfasste Preise kopieren",
  ["cc.copyTip"] = "Alle erfassten Preise, eine Zeile je Preis",
  ["cc.clear"] = "Erfasste Preise löschen",
  ["cc.clear.title"] = "Erfasste Preise löschen",
  ["cc.clear.text"] = "Erfasste Preise löschen?\nBis zum nächsten Lehrerbesuch gelten Classic-Preise (nicht rückgängig).",
  ["cc.export.title"] = "Erfasste Preise",
  ["cc.export.hint"] = "Eine Zeile pro Preis, für die Website-Daten",
  ["cc.export.header"] = '# Forever Guides: im Spiel gesehene Lehrerpreise. Felder: spellId Kupfer Mindeststufe npc "Name" Rang Klasse Build Daten-Kupfer (Preis der mitgelieferten Daten, - = keiner). Kupfer: 10000 = 1 Gold, 100 = 1 Silber.',
})

local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local res = { pcall(fn, ...) }
  if not res[1] then
    return nil
  end
  return unpack(res, 2, 8)
end

local function key(scope, id)
  return scope .. ":" .. id
end

-- Storage ----------------------------------------------------------------------------

local function cleanEntry(raw)
  if type(raw) ~= "table" or type(raw.cost) ~= "number" or raw.cost < 1 then
    return nil
  end
  local e = {
    cost = math.floor(math.min(raw.cost, MAX_COST)),
    lvl = type(raw.lvl) == "number" and math.floor(U.clamp(raw.lvl, 0, 80)) or 0,
    t = type(raw.t) == "number" and raw.t or 0,
    build = ns.TrainerLog.CleanText(type(raw.build) == "string" and raw.build or tostring(raw.build or ""), 20),
    npc = type(raw.npc) == "number" and raw.npc > 0 and math.floor(raw.npc) or nil,
    n = ns.TrainerLog.CleanText(raw.n, MAX_NAME),
    rk = type(raw.rk) == "number" and raw.rk >= 1 and raw.rk <= 30 and math.floor(raw.rk) or nil,
    s = type(raw.s) == "number" and raw.s >= 1 and math.floor(math.min(raw.s, MAX_COST)) or nil,
  }
  e.disc = (e.s and e.cost < e.s) and true or nil
  return e
end

-- "SCOPE:id" with an upper case scope and a positive integer id, else nil.
local function parseKey(k)
  if type(k) ~= "string" then
    return nil
  end
  local scope, id = k:match("^(%u+):(%d+)$")
  id = tonumber(id)
  if scope and #scope <= 12 and id and id > 0 then
    return scope, id
  end
  return nil
end

local checked
local function data()
  if type(ns.db) ~= "table" then
    return nil
  end
  local d = ns.db.trainerCosts
  if type(d) ~= "table" then
    d = { v = 1, items = {} }
    ns.Store.set("trainerCosts", d)
  end
  if checked ~= d then
    local clean, count = {}, 0
    local keys = {}
    for k in pairs(type(d.items) == "table" and d.items or {}) do
      keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do
      local e = parseKey(k) and cleanEntry(d.items[k])
      if e and count < MAX_ENTRIES then
        clean[k] = e
        count = count + 1
      end
    end
    d.v, d.items = 1, clean
    checked = d
  end
  return d
end

function CC.Count()
  local d = data()
  local n = 0
  for _ in pairs(d and d.items or {}) do
    n = n + 1
  end
  return n
end

-- The stored entry of a price, nil when never seen.
function CC.Get(scope, id)
  local d = data()
  return d and d.items[key(scope, id)] or nil
end

-- Stores or updates one price. Returns "new", "changed", "same", "full" or "invalid".
function CC.Set(scope, id, raw)
  local d = data()
  local e = cleanEntry(raw)
  if not (d and e and parseKey(key(tostring(scope), tostring(id)))) then
    return "invalid"
  end
  local k = key(scope, id)
  local old = d.items[k]
  if not old then
    local n = CC.Count()
    if n >= MAX_ENTRIES then
      return "full"
    end
  end
  d.items[k] = e
  if not old then
    return "new"
  end
  return (old.cost ~= e.cost or old.lvl ~= e.lvl) and "changed" or "same"
end

function CC.Clear()
  if data() then
    ns.Store.set("trainerCosts.items", {})
    checked = nil
  end
end

-- Spell id lookup -----------------------------------------------------------------------

local function rankOf(text)
  return type(text) == "string" and tonumber(text:match("(%d+)")) or nil
end

local index
-- name|rank -> list of { id, fid, class }, from every Spells table (both
-- languages of the name) plus the weapon skill spells.
local function buildIndex()
  index = {}
  local D = ns.Data or {}
  local function add(name, rank, entry)
    if type(name) == "string" and name ~= "" then
      local k = name:lower() .. "|" .. (rank or 0)
      index[k] = index[k] or {}
      index[k][#index[k] + 1] = entry
    end
  end
  for class, list in pairs(D.Spells or {}) do
    for _, s in ipairs(list) do
      if s.n then
        local entry = { id = s.id, fid = s.fid, class = class }
        add(s.n.en, s.rk, entry)
        add(s.n.de, s.rk, entry)
      end
    end
  end
  for skill, names in pairs((D.Weapons and D.Weapons.skills) or {}) do
    local id = ns.LevelLogic.SKILL_SPELLS[skill]
    if id then
      add(names.en, nil, { id = id, class = "GENERAL" })
      add(names.de, nil, { id = id, class = "GENERAL" })
    end
  end
end

function CC.ResetIndex()
  index = nil
end

-- Spell id by name, rank and icon: unique match, else the player's class, else
-- the icon decides. nil when it stays ambiguous.
local function idByName(name, rank, texture, class)
  if not index then
    buildIndex()
  end
  local list = type(name) == "string" and index[name:lower() .. "|" .. (rank or 0)]
  if not list then
    return nil
  end
  local ids, seen = {}, {}
  for _, c in ipairs(list) do
    if not seen[c.id] then
      seen[c.id] = true
      ids[#ids + 1] = c
    end
  end
  if #ids == 1 then
    return ids[1].id
  end
  for _, narrow in ipairs({
    function(c)
      return c.class == class
    end,
    function(c)
      return type(texture) == "number" and c.fid == texture
    end,
  }) do
    local hits = {}
    for _, c in ipairs(ids) do
      if narrow(c) then
        hits[#hits + 1] = c
      end
    end
    if #hits == 1 then
      return hits[1].id
    end
    if #hits > 1 then
      ids = hits
    end
  end
  return nil
end

local function idByTooltip(i)
  local info = type(C_TooltipInfo) == "table" and try(C_TooltipInfo.GetTrainerService, i)
  return type(info) == "table" and type(info.id) == "number" and info.id > 0 and info.id or nil
end

local function idByLink(i)
  local link = try(GetTrainerServiceItemLink, i)
  return type(link) == "string" and tonumber(link:match("|Hspell:(%d+)")) or nil
end

-- Capture ------------------------------------------------------------------------------

local function isWeaponMaster(npc)
  for _, t in ipairs((ns.Data and ns.Data.Weapons and ns.Data.Weapons.trainers) or {}) do
    if t.npc == npc then
      return true
    end
  end
  return false
end

local function trainerNpc()
  for _, unit in ipairs({ "npc", "target" }) do
    local guid = try(UnitGUID, unit)
    if guid then
      return ns.TrainerLog.ParseGuid(guid)
    end
  end
end

local function isPetTrainer()
  local kind = type(C_Trainer) == "table" and try(C_Trainer.GetTrainerType)
  return kind ~= nil and Enum and Enum.TrainerType ~= nil and kind == Enum.TrainerType.Pet
end

-- Reads the open trainer window. Returns how many prices were new or changed.
function CC.Capture()
  if isPetTrainer() or try(IsTradeskillTrainer) == true then
    return 0
  end
  local total = try(GetNumTrainerServices)
  local _, class = UnitClass("player")
  if not (type(total) == "number" and total > 0 and class) then
    return 0
  end
  local npc = trainerNpc()
  local scope = npc and isWeaponMaster(npc) and "WM" or class
  local _, build = GetBuildInfo()
  local recorded = 0
  for i = 1, math.min(total, 400) do
    local name, _, texture, reqLevel, subText = try(GetTrainerServiceInfo, i)
    local cost, isProfession = try(GetTrainerServiceCost, i)
    if type(name) == "string" and name ~= "" and type(cost) == "number" and cost > 0 and not isProfession then
      local rank = rankOf(subText)
      local id = idByTooltip(i) or idByName(name, rank, texture, class) or idByLink(i)
      if id then
        local classic = ns.CostLogic.Static(id, class)
        local result = CC.Set(scope, id, {
          cost = cost,
          lvl = reqLevel,
          t = time and time() or 0,
          build = build,
          npc = npc,
          n = name,
          rk = rank,
          s = classic,
        })
        if result == "new" or result == "changed" then
          recorded = recorded + 1
        end
      end
    end
  end
  return recorded
end

local function run()
  local recorded = CC.Capture()
  if recorded > 0 then
    ns.Notify(string.format(L["cc.saved"], recorded), "success")
    if ns.LevelView then
      ns.LevelView.RefreshLive()
    end
    ns.Emit("FG_TRAINER_COSTS")
  end
end

-- Names load lazily, so the window is read again whenever it updates.
for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_SERVICE_INFO_NAME_UPDATE" }) do
  ns.On(event, function()
    ns.Debounce("trainer-costs", DEBOUNCE, run)
  end)
end

-- Export -------------------------------------------------------------------------------

-- One locale-independent line per price after a header line, sorted by spell id.
function CC.BuildExport()
  local lines = { L["cc.export.header"] }
  local rows = {}
  local d = data()
  for k, e in pairs(d and d.items or {}) do
    local scope, id = parseKey(k)
    rows[#rows + 1] = { id = id, scope = scope, e = e }
  end
  table.sort(rows, function(a, b)
    if a.id ~= b.id then
      return a.id < b.id
    end
    return a.scope < b.scope
  end)
  for _, r in ipairs(rows) do
    local e = r.e
    lines[#lines + 1] = string.format(
      '%d %d %d %s "%s" %s %s %s %s',
      r.id,
      e.cost,
      e.lvl,
      e.npc or "-",
      e.n or "-",
      e.rk or "-",
      r.scope,
      e.build or "-",
      e.s or "-"
    )
  end
  return table.concat(lines, "\n")
end
