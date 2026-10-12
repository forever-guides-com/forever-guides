-- Shared safety net of the automatic helpers (AutoRepair, AutoSummon, AutoResurrect, AutoQuest,
-- AutoSocial, AutoRoleCheck, AutoRelease, HideErrors). Every helper is off by default, runs through Guard.Run
-- (protected call, three errors switch the helper off), stays quiet in combat and while the
-- override key is held (HideErrors only filters text, so it ignores both), and reads names and
-- GUIDs only after the secret-value check.
local _, ns = ...
local Store, L = ns.Store, ns.L

local Guard = {}
ns.AutoGuard = Guard

Guard.MAX_ERRORS = 3
Guard.FEATURES = {
  "autoRepair",
  "autoSummon",
  "autoResurrect",
  "autoQuest",
  "autoSocial",
  "autoRelease",
  "hideErrors",
  "autoSocialAcceptFriends",
  "autoSocialAcceptGuild",
  "autoSocialAcceptContacts",
  "autoRoleCheck",
}
-- One helper with several switches: it runs while any of them is on and switches all of them off
-- after repeated errors.
Guard.GROUPS = {
  autoInvite = { "autoSocialAcceptFriends", "autoSocialAcceptGuild", "autoSocialAcceptContacts" },
}
Guard.KEYS = { "shift", "alt", "ctrl" }

local KEY_FUNCTIONS = { shift = "IsShiftKeyDown", alt = "IsAltKeyDown", ctrl = "IsControlKeyDown" }
local IS_FEATURE = {}
for _, id in ipairs(Guard.FEATURES) do
  IS_FEATURE[id] = true
end

ns.AddLocale("enUS", {
  ["auto.key.shift"] = "Shift",
  ["auto.key.alt"] = "Alt",
  ["auto.key.ctrl"] = "Ctrl",
  ["auto.name.autoRepair"] = "Auto repair",
  ["auto.name.autoSummon"] = "Auto summon",
  ["auto.name.autoResurrect"] = "Auto resurrect",
  ["auto.name.autoQuest"] = "Auto quests",
  ["auto.name.autoSocial"] = "Duels and invites",
  ["auto.name.autoRelease"] = "Auto release",
  ["auto.name.hideErrors"] = "Hide red errors",
  ["auto.name.autoSocialAcceptFriends"] = "Friends may invite me",
  ["auto.name.autoSocialAcceptGuild"] = "Guild may invite me",
  ["auto.name.autoSocialAcceptContacts"] = "Contacts may invite me",
  ["auto.name.autoInvite"] = "Accepting invites",
  ["auto.name.autoRoleCheck"] = "Auto role check",
  ["auto.hint.autoRepair"] = "Repairs at the merchant by itself.\nHold %s to stop it.",
  ["auto.hint.autoSummon"] = "Accepts summons after a delay.\nHold %s to stop it.",
  ["auto.hint.autoResurrect"] = "Accepts resurrections of friends.\nHold %s to stop it.",
  ["auto.hint.autoQuest"] = "Accepts and turns in quests.\nNo reward choice, no gold.\nHold %s to stop it.",
  ["auto.hint.autoSocial"] = "Blocks duels of strangers.\nHold %s to stop it.",
  ["auto.hint.autoRelease"] = "Releases your spirit in PvP after death.\nHold %s to cancel.",
  ["auto.hint.hideErrors"] = "Hides red error text on screen.\nImportant ones can stay.",
  ["auto.hint.autoSocialAcceptFriends"] = "Accepts group invites of friends.\nNot while you are queued.\nHold %s to stop it.",
  ["auto.hint.autoSocialAcceptGuild"] = "Accepts group invites of guild members.\nNot while you are queued.\nHold %s to stop it.",
  ["auto.hint.autoSocialAcceptContacts"] = "Accepts group invites of your contacts.\nThe list also holds strangers from trade and groups.\nNot while you are queued.\nHold %s to stop it.",
  ["auto.hint.autoRoleCheck"] = "Confirms role checks with your saved roles.\nNothing happens without a saved role.\nHold %s to stop it.",
  ["auto.off"] = "%s switched off after %d errors, see /fg errors",
})
ns.AddLocale("deDE", {
  ["auto.key.shift"] = "Umschalt",
  ["auto.key.alt"] = "Alt",
  ["auto.key.ctrl"] = "Strg",
  ["auto.name.autoRepair"] = "Auto-Reparatur",
  ["auto.name.autoSummon"] = "Auto-Beschwörung",
  ["auto.name.autoResurrect"] = "Auto-Wiederbelebung",
  ["auto.name.autoQuest"] = "Auto-Quests",
  ["auto.name.autoSocial"] = "Duelle und Einladungen",
  ["auto.name.autoRelease"] = "Auto-Freilassen",
  ["auto.name.hideErrors"] = "Rote Fehler ausblenden",
  ["auto.name.autoSocialAcceptFriends"] = "Freunde dürfen einladen",
  ["auto.name.autoSocialAcceptGuild"] = "Gilde darf einladen",
  ["auto.name.autoSocialAcceptContacts"] = "Kontakte dürfen einladen",
  ["auto.name.autoInvite"] = "Einladungen annehmen",
  ["auto.name.autoRoleCheck"] = "Auto-Rollenabfrage",
  ["auto.hint.autoRepair"] = "Repariert beim Händler von selbst.\nHalte %s gedrückt, um es zu stoppen.",
  ["auto.hint.autoSummon"] = "Nimmt Beschwörungen nach einer Pause an.\nHalte %s gedrückt, um es zu stoppen.",
  ["auto.hint.autoResurrect"] = "Nimmt Wiederbelebungen von Freunden an.\nHalte %s gedrückt, um es zu stoppen.",
  ["auto.hint.autoQuest"] = "Nimmt Quests an und gibt sie ab.\nKeine Belohnungswahl, kein Gold.\nHalte %s gedrückt, um es zu stoppen.",
  ["auto.hint.autoSocial"] = "Blockt Duelle von Fremden.\nHalte %s gedrückt, um es zu stoppen.",
  ["auto.hint.autoRelease"] = "Lässt im PvP nach dem Tod den Geist frei.\nHalte %s gedrückt, um abzubrechen.",
  ["auto.hint.hideErrors"] = "Blendet roten Fehlertext im Bild aus.\nWichtige können bleiben.",
  ["auto.hint.autoSocialAcceptFriends"] = "Nimmt Gruppeneinladungen von Freunden an.\nNicht während einer Warteschlange.\nHalte %s gedrückt, um es zu stoppen.",
  ["auto.hint.autoSocialAcceptGuild"] = "Nimmt Einladungen von Gildenmitgliedern an.\nNicht während einer Warteschlange.\nHalte %s gedrückt, um es zu stoppen.",
  ["auto.hint.autoSocialAcceptContacts"] = "Nimmt Einladungen deiner Kontakte an.\nDie Liste enthält auch Fremde aus Handel und Gruppen.\nNicht während einer Warteschlange.\nHalte %s gedrückt, um es zu stoppen.",
  ["auto.hint.autoRoleCheck"] = "Bestätigt Rollenabfragen mit deinen gespeicherten Rollen.\nOhne gespeicherte Rolle passiert nichts.\nHalte %s gedrückt, um es zu stoppen.",
  ["auto.off"] = "%s ausgeschaltet nach %d Fehlern, siehe /fg fehler",
})

local failures = {}

local function resolve(path)
  local node = _G
  for part in path:gmatch("[^.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = rawget(node, part)
  end
  return node
end

-- Calls a game function by its global path. Returns false when it does not exist, else true and the
-- results. An error of the game function is raised again, so Guard.Run counts it.
function Guard.Call(path, ...)
  local fn = resolve(path)
  if type(fn) ~= "function" then
    return false
  end
  local out = { pcall(fn, ...) }
  if not out[1] then
    error(path .. ": " .. tostring(out[2]), 0)
  end
  return true, unpack(out, 2)
end

function Guard.Has(path)
  return type(resolve(path)) == "function"
end

function Guard.Now()
  local found, now = Guard.Call("GetTime")
  return found and type(now) == "number" and now or 0
end

local function settings()
  return (ns.db and ns.db.settings) or {}
end

-- A helper runs only while its own switch is on.
function Guard.On(id)
  local group = Guard.GROUPS[id]
  if group then
    for _, key in ipairs(group) do
      if settings()[key] == true then
        return true
      end
    end
    return false
  end
  return settings()[id] == true
end

-- The value, or nil when it is secret or the client says the addon may not read it.
function Guard.Safe(value)
  if value == nil then
    return nil
  end
  local secret = rawget(_G, "issecretvalue")
  if type(secret) == "function" then
    local ok, hidden = pcall(secret, value)
    if not ok or hidden then
      return nil
    end
  end
  local access = rawget(_G, "canaccessvalue")
  if type(access) == "function" then
    local ok, allowed = pcall(access, value)
    if not ok or allowed == false then
      return nil
    end
  end
  return value
end

-- In combat: nothing automatic happens.
function Guard.Blocked()
  for _, name in ipairs({ "UnitAffectingCombat", "InCombatLockdown" }) do
    local fn = rawget(_G, name)
    if type(fn) == "function" then
      local ok, value = pcall(fn, "player")
      if ok and value == true then
        return true
      end
    end
  end
  return false
end

function Guard.KeyId()
  local key = settings().autoKey
  return KEY_FUNCTIONS[key] and key or "shift"
end

function Guard.KeyName()
  return L["auto.key." .. Guard.KeyId()]
end

-- The override key is held right now.
function Guard.Override()
  local fn = rawget(_G, KEY_FUNCTIONS[Guard.KeyId()])
  if type(fn) ~= "function" then
    return false
  end
  local ok, held = pcall(fn)
  return ok and held == true
end

-- Why nothing should happen right now: "combat", "key" or nil.
function Guard.Paused()
  if Guard.Blocked() then
    return "combat"
  end
  if Guard.Override() then
    return "key"
  end
end

-- One chat line, only while the helper is on and "messages in chat" is not switched off.
function Guard.Say(id, text)
  if Guard.On(id) and settings().autoChat ~= false then
    ns.Notify.chat(text)
  end
end

local function fail(id)
  local n = (failures[id] or 0) + 1
  failures[id] = n
  if n < Guard.MAX_ERRORS then
    return
  end
  for _, key in ipairs(Guard.GROUPS[id] or { id }) do
    Store.set("settings." .. key, false)
  end
  local name = L["auto.name." .. id]
  ns.Errors.add({ msg = string.format(L["auto.off"], name, n), kind = "warning", ctx = id })
  ns.Notify(string.format(L["auto.off"], name, n), "warning")
end

-- Runs fn(...) for a helper that is on. A failure is recorded in the error list; the third one
-- switches the helper off. Returns true and the results, or false.
function Guard.Run(id, fn, ...)
  if not Guard.On(id) then
    return false
  end
  local ok, a, b, c = ns.Safe(id, fn, ...)
  if not ok then
    fail(id)
    return false
  end
  return true, a, b, c
end

-- Runs fn after a delay under Guard.Run. Without a timer nothing runs: a delayed action must never
-- happen at once.
function Guard.After(id, delay, fn)
  local timer = rawget(_G, "C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    return false
  end
  return (pcall(timer.After, delay, function()
    Guard.Run(id, fn)
  end))
end

-- Name and GUID from an event, nil for a name that is secret or not a string.
local function identity(name, guid)
  name, guid = Guard.Safe(name), Guard.Safe(guid)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  return name, type(guid) == "string" and guid or nil
end

-- Friend, guild member and contact (recently seen player) apart. Names and GUIDs from events may be
-- secret, then the answer is no.
function Guard.IsFriend(name, guid)
  name, guid = identity(name, guid)
  return name ~= nil and ns.Invites.IsFriend(name, guid)
end

function Guard.IsGuildMember(name, guid)
  name, guid = identity(name, guid)
  return name ~= nil and ns.Invites.IsGuildMember(name, guid)
end

function Guard.IsContact(name, guid)
  name, guid = identity(name, guid)
  local seen = ns.SeenPlayers
  if not name or not seen then
    return false
  end
  return (guid ~= nil and seen.Find(guid) ~= nil) or seen.FindName(name) ~= nil
end

-- Friend or guild member.
function Guard.Related(name, guid)
  return Guard.IsGuildMember(name, guid) or Guard.IsFriend(name, guid)
end

-- Member of my group, my guild or a friend.
function Guard.Trusted(name, guid)
  name = Guard.Safe(name)
  if type(name) ~= "string" or name == "" then
    return false
  end
  local _, party = Guard.Call("UnitInParty", name)
  local _, raid = Guard.Call("UnitInRaid", name)
  return party == true or raid ~= nil or Guard.Related(name, guid)
end

-- The explanation shows once whenever the player switches a helper on.
ns.On("FG_SETTING_CHANGED", function(_, path, value)
  local id = type(path) == "string" and path:match("^settings%.(.+)$")
  if not IS_FEATURE[id or ""] then
    return
  end
  failures[id] = nil
  for group, keys in pairs(Guard.GROUPS) do
    for _, key in ipairs(keys) do
      if key == id then
        failures[group] = nil
      end
    end
  end
  if value == true then
    ns.Notify(string.format(L["auto.hint." .. id], Guard.KeyName()), "warning")
  end
end)
