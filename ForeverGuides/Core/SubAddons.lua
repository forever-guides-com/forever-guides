-- Optional LoadOnDemand sub-addons that the main add-on switches on and off. The manifest below is
-- static so settings and wizard can list a sub-addon that is not installed or not loaded. A switch
-- resolves character override, then account default, then manifest default; the add-on list of the
-- game follows it in both directions (check mark removed when off, set when on). Main code reaches sub-addon features only through registries or the
-- Enabled / State guards of this file, so a missing, disabled or outdated sub-addon never raises.
--
-- A sub-addon joins at the top of its first file:
--   local FG = _G.ForeverGuides
--   if not (FG and FG.SubAddons and FG.SubAddons.Join("<id>", ...)) then return end
local _, ns = ...

local M = { version = 1 }
ns.SubAddons = M

ns.AddLocale("enUS", {
  ["subaddon.guildmanager.title"] = "GildenManager",
  ["subaddon.guildmanager.desc"] = "Guild tools for officers: main and alt links, inactivity list and guild actions with preview.",
})
ns.AddLocale("deDE", {
  ["subaddon.guildmanager.title"] = "GildenManager",
  ["subaddon.guildmanager.desc"] = "Gildenwerkzeuge für Offiziere: Main und Alt, Inaktivitätsliste und Gildenaktionen mit Vorschau.",
})

-- id: switch key and value of the TOC field X-Forever-Guides-Addon. addon: folder name.
-- loadWhen: name of a condition in CONDITIONS, the add-on loads once it holds (nil = at once).
-- seedFromList: a character that already switched the add-on on in the game list keeps it on.
local MANIFEST = {
  {
    id = "guildmanager",
    addon = "ForeverGuides_GildenManager",
    titleKey = "subaddon.guildmanager.title",
    descKey = "subaddon.guildmanager.desc",
    defaultOn = false,
    loadWhen = "inGuild",
    seedFromList = true,
  },
}

local CONDITIONS = {
  -- An unknown API counts as met, so a client without the call never locks the add-on out.
  inGuild = function()
    if type(IsInGuild) ~= "function" then
      return true
    end
    local ok, inGuild = pcall(IsInGuild)
    return not ok or inGuild == true
  end,
}

-- State per id: joined (Join accepted), problem ("outdated", "failed", "off": Join refused),
-- reason (answer of the client for a failed load), deferred (waits for combat or loadWhen),
-- explicit (the waiting load follows a switch the player flipped).
local byId, rec = {}, {}
for _, entry in ipairs(MANIFEST) do
  byId[entry.id] = entry
  rec[entry.id] = {}
end

local function copy(entry)
  local out = {}
  for k, v in pairs(entry) do
    out[k] = v
  end
  return out
end

function M.List()
  local out = {}
  for i, entry in ipairs(MANIFEST) do
    out[i] = copy(entry)
  end
  return out
end

function M.Get(id)
  local entry = byId[id]
  return entry and copy(entry) or nil
end

-- Resolution ------------------------------------------------------------------------------------

local function valueOf(owner, key, id)
  local t = type(owner) == "table" and owner[key]
  if type(t) == "table" then
    return t[id]
  end
end

local function charOverride(id)
  return valueOf(ns.charDB, "subaddons", id)
end

local function accountValue(id)
  return valueOf(ns.db and ns.db.settings, "subaddons", id)
end

-- Pure: the character override decides, then the account default, then the manifest default.
-- Returns the switch and the level that decided it ("char", "account" or "default").
function M.Resolve(defaultOn, override, account)
  if type(override) == "boolean" then
    return override, "char"
  elseif type(account) == "boolean" then
    return account, "account"
  end
  return defaultOn == true, "default"
end

local function resolved(id)
  local entry = byId[id]
  if not entry then
    return false, "default"
  end
  return M.Resolve(entry.defaultOn, charOverride(id), accountValue(id))
end

function M.Enabled(id)
  return (resolved(id))
end

-- "char" | "account" | "default": which level decides the switch.
function M.Source(id)
  return select(2, resolved(id))
end

-- True when the loadWhen condition of the add-on holds (always for an add-on without one).
function M.Ready(id)
  local entry = byId[id]
  if not entry then
    return false
  end
  local condition = entry.loadWhen and CONDITIONS[entry.loadWhen]
  return condition == nil or condition() == true
end

-- Client calls ---------------------------------------------------------------------------------

local function clientCall(modern, legacy, ...)
  local addons = rawget(_G, "C_AddOns")
  local fn = type(addons) == "table" and addons[modern] or (legacy and rawget(_G, legacy))
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a = pcall(fn, ...)
  if ok then
    return a
  end
end

local function isLoaded(addon)
  return clientCall("IsAddOnLoaded", "IsAddOnLoaded", addon) == true
end

local function inCombat()
  return (InCombatLockdown and InCombatLockdown() or false) or ns.AddonRestricted("Combat")
end

-- The character as the add-on list calls know it. The client reads a character name here as an
-- unknown character (state always 0, changes without effect), the GUID is recognized. Without a GUID
-- the name stays as the last resort.
local function listCharacter()
  for _, api in ipairs({ "UnitGUID", "UnitName" }) do
    local fn = rawget(_G, api)
    if type(fn) == "function" then
      local ok, value = pcall(fn, "player")
      if ok and type(value) == "string" and value ~= "" then
        return value
      end
    end
  end
  return nil
end

ns.ListCharacter = listCharacter

-- State ------------------------------------------------------------------------------------------

-- "active", "off", "pending-off" (switched off, still loaded this session), "missing" (folder not
-- installed), "disabled" (off in the add-on list for this character, the client kept it so), "failed" (load error or a
-- wrong TOC id), "outdated" (version or API differs from the main add-on), "waiting" (switched on,
-- not loaded yet: loadWhen not met, combat, or a restart is needed).
function M.State(id)
  local entry = byId[id]
  if not entry then
    return "missing"
  end
  local r, enabled = rec[id], M.Enabled(id)
  if r.problem and r.problem ~= "off" then
    return enabled and r.problem or "off"
  end
  if r.joined or (isLoaded(entry.addon) and not r.problem) then
    return enabled and "active" or "pending-off"
  end
  local base = ns.PackageState(entry.addon)
  if r.reason == "MISSING" or base == "missing" then
    return "missing"
  end
  if not enabled then
    return "off"
  end
  -- The check mark is set before the load: what is left of a refused attempt is the hint for the player.
  if r.reason == "DISABLED" or (base == "disabled" and r.reason and r.reason ~= "COMBAT") then
    return "disabled"
  end
  if r.reason and r.reason ~= "COMBAT" then
    return "failed"
  end
  return "waiting"
end

-- True when the client reports the sub-addon folder as loaded in this session.
function M.IsLoaded(id)
  local entry = byId[id]
  return entry ~= nil and isLoaded(entry.addon)
end

-- The entry of the add-on in the game's add-on list for this character: "enabled" (a check mark,
-- the client still loads a LoadOnDemand add-on only on request), "disabled", or nil when the client
-- cannot say. Only the C_AddOns order (name, character) is used, the old global takes them the other
-- way round.
function M.ListState(id)
  local entry = byId[id]
  if not entry then
    return nil
  end
  local state = clientCall("GetAddOnEnableState", nil, entry.addon, listCharacter())
  if type(state) ~= "number" then
    return nil
  end
  return state > 0 and "enabled" or "disabled"
end

-- KB of the loaded sub-addon, nil without the API or while it is not loaded.
function M.Memory(id)
  local entry = byId[id]
  local fn = rawget(_G, "GetAddOnMemoryUsage")
  if not entry or type(fn) ~= "function" or not isLoaded(entry.addon) then
    return nil
  end
  local ok, kb = pcall(fn, entry.addon)
  return ok and type(kb) == "number" and kb or nil
end

-- Loading -----------------------------------------------------------------------------------------

-- Loads one sub-addon that is switched on and ready. Our switch is the truth: while the entry in the
-- game list is unchecked for this character, the load goes through PackageUI.Enable (check mark,
-- save, load), at the start as well as for a switch the player just flipped. A client that keeps the
-- entry unchecked ends in the "disabled" state and is not asked again before the next trigger.
-- Never raises.
local function attempt(entry, explicit)
  local r = rec[entry.id]
  -- Loaded by someone else (the add-on list): its first file has run, a join is not possible now.
  if r.joined or isLoaded(entry.addon) then
    return
  end
  if not M.Ready(entry.id) or inCombat() then
    r.deferred = true
    r.explicit = r.explicit or explicit or nil
    return
  end
  explicit = explicit or r.explicit
  r.deferred, r.problem, r.reason, r.explicit = nil, nil, nil, nil
  local viaList = explicit or M.ListState(entry.id) == "disabled"
  local call = viaList and ns.PackageUI and ns.PackageUI.Enable or ns.LoadPackage
  local ok, loaded, reason = pcall(call, entry.addon)
  if not ok then
    r.reason = "ERROR"
    ns.Log.warn("sub-addon %s: %s", entry.id, tostring(loaded))
    return
  end
  if not loaded then
    r.reason = reason or "ERROR"
    r.deferred = r.reason == "COMBAT" or nil
    r.explicit = r.deferred and explicit or nil
  end
end

-- Takes the check mark of a switched-off sub-addon out of the game's add-on list for this character
-- (other characters follow at their next start). Never in combat, never raises. The result is read
-- back because the argument order of DisableAddOn is not verified on this client: a refused call
-- stays at a log line.
local function unlist(entry)
  if M.Enabled(entry.id) or inCombat() then
    return
  end
  local state = M.ListState(entry.id)
  if not state then
    return
  end
  if state == "enabled" then
    clientCall("DisableAddOn", "DisableAddOn", entry.addon, listCharacter())
  end
  -- The client keeps a change pending, also across /reload, until it is saved: the file of the list
  -- and the list window stay on the old state otherwise. Saved at every start while the switch is off.
  clientCall("SaveAddOns", "SaveAddOns")
  if M.ListState(entry.id) == "enabled" then
    ns.Log.info("sub-addon %s: the add-on list kept its check mark", entry.id)
  end
end

-- Loads the sub-addon when it is switched on, ready and not loaded yet. Returns its State.
function M.Ensure(id)
  local entry = byId[id]
  if entry and M.Enabled(id) then
    attempt(entry, false)
  end
  return M.State(id)
end

-- A character that already runs the add-on from the game list keeps it: once per character, a
-- missing override is set to true when the list says so. The order of the arguments of the call
-- is not verified on this client, an error or a missing API counts as not enabled.
local function seed()
  local char = ns.charDB
  if type(char) ~= "table" or char.subaddonsSeeded then
    return
  end
  char.subaddonsSeeded = true
  if type(char.subaddons) ~= "table" then
    char.subaddons = {}
  end
  for _, entry in ipairs(MANIFEST) do
    if entry.seedFromList and char.subaddons[entry.id] == nil then
      local state = clientCall("GetAddOnEnableState", nil, entry.addon, listCharacter())
      if type(state) == "number" and state > 0 then
        char.subaddons[entry.id] = true
      end
    end
  end
end

-- Once after Store.init: seeds old switches, then loads every sub-addon that is on, in manifest order
-- and unchecks the list entry of every one that is off.
function M.LoadAll()
  ns.Safe("subaddons seed", seed)
  for _, entry in ipairs(MANIFEST) do
    ns.Safe("subaddons load", M.Ensure, entry.id)
    ns.Safe("subaddons list", unlist, entry)
  end
end

-- Switches ---------------------------------------------------------------------------------------

-- scope "account" sets the default for all characters, "char" the override of this one. Switching on
-- loads at once when the add-on is ready, switching off acts after the next start (pending-off) and
-- unchecks the entry in the game's add-on list for this character.
function M.SetEnabled(id, on, scope)
  local entry = byId[id]
  if not entry or type(on) ~= "boolean" or (scope ~= "account" and scope ~= "char") then
    return false
  end
  local path = "subaddons." .. id
  if scope == "char" then
    ns.Store.setChar(path, on)
  else
    ns.Store.set("settings." .. path, on)
  end
  if M.Enabled(id) then
    attempt(entry, true)
  else
    ns.Safe("subaddons list", unlist, entry)
  end
  ns.Emit("FG_SUBADDON_CHANGED", id)
  return true
end

-- Back to following the account default.
function M.ClearOverride(id)
  local entry = byId[id]
  if not entry then
    return false
  end
  ns.Store.setChar("subaddons." .. id, nil)
  M.Ensure(id)
  ns.Safe("subaddons list", unlist, entry)
  ns.Emit("FG_SUBADDON_CHANGED", id)
  return true
end

-- Join -------------------------------------------------------------------------------------------

local function metadata(addon, field)
  local addons = rawget(_G, "C_AddOns")
  local getter = type(addons) == "table" and addons.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
  if type(getter) ~= "function" then
    return nil, false
  end
  local ok, value = pcall(getter, addon, field)
  return ok and value or nil, true
end

local function join(id, addon)
  local entry = byId[id]
  if not entry then
    return false
  end
  local r = rec[id]
  if addon ~= entry.addon then
    r.problem, r.reason = "failed", "NAME"
    return false
  end
  if not M.Enabled(id) then
    r.problem = "off"
    return false
  end
  local declared, available = metadata(addon, "X-Forever-Guides-Addon")
  if available and declared ~= id then
    r.problem, r.reason = "failed", "ID"
    return false
  end
  local api = metadata(addon, "X-Forever-Guides-Api")
  local version = metadata(addon, "Version")
  if (api ~= nil and tostring(api) ~= tostring(M.version)) or (version ~= nil and version ~= ns.version) then
    r.problem, r.reason = "outdated", nil
    return false
  end
  r.joined, r.problem, r.reason = true, nil, nil
  return true
end

-- Called by the sub-addon at the top of its first file. False (never an error) when the add-on does
-- not belong, is switched off, or was built for another version: it then registers nothing.
function M.Join(id, addon)
  local ok, joined = pcall(join, id, addon)
  return ok and joined == true
end

-- Waiting add-ons (loadWhen, combat) are tried again when the condition can have changed.
local function retry()
  for _, entry in ipairs(MANIFEST) do
    if rec[entry.id].deferred then
      M.Ensure(entry.id)
      -- A load that follows a switch registers while the load runs: pages wait for this event.
      if not rec[entry.id].deferred then
        ns.Emit("FG_SUBADDON_CHANGED", entry.id)
      end
    end
  end
end
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_GUILD_UPDATE", "PLAYER_REGEN_ENABLED" }) do
  ns.On(event, retry)
end
