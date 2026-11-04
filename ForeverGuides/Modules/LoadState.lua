-- The reader of the game state behind "when active" (ns.LoadState): combat, instance, group, mount, vehicle,
-- target, class, specialization and the character (its key "Name-Realm"), kept up to date by one event frame for every window and for the cursor
-- ring. Subscribers get called with the state after every change; the frame only lives while somebody is
-- subscribed. Every game call goes through pcall and a presence check: a reading that is missing or fails is
-- nil ("unknown"), which Modules/LoadLogic.lua counts as a condition that is not met. Nothing here writes to a
-- frame of the game, reads a secret value or compares one. The same reading of the character feeds the
-- register of the account (ns.db.characters, Modules/CharScopeLogic.lua), refreshed at every login.
local _, ns = ...
local CS = ns.CharScopeLogic

local LS = {
  -- Events that change a reading; the vehicle events come as unit events of the player.
  EVENTS = {
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "PLAYER_TARGET_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED",
  },
  UNIT_EVENTS = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "PLAYER_SPECIALIZATION_CHANGED" },
  -- The readings, in the order of LoadLogic.
  KEYS = { "combat", "instance", "grouped", "mounted", "vehicle", "target", "class", "spec", "character" },
}
ns.LoadState = LS

-- Game calls ---------------------------------------------------------------------------------------------------

-- The answer of a game function as a boolean; nil when the function is missing or fails.
local function flag(name, arg)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(function()
    return fn(arg) and true or false
  end)
  if ok then
    return value
  end
  return nil
end

-- The values of a game function, nil when it is missing or fails.
local function call(name, ...)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
  return nil
end

local function readClass()
  local _, token = call("UnitClass", "player")
  return type(token) == "string" and token or nil
end

-- Who the player is: { key, name, realm, class } with the key "Name-Realm", nil when the client does not tell a
-- usable name and realm. UnitFullName leaves the realm out for the own realm, GetRealmName fills it in.
function LS.Identity()
  local name, realm = call("UnitFullName", "player")
  local home = call("GetRealmName")
  local key = CS.Key(name, realm, home)
  if not key then
    return nil
  end
  return { key = key, name = name, realm = CS.CleanRealm(realm) and realm or home, class = readClass() }
end

-- The key of the character, nil when unknown.
local function readCharacter()
  local id = LS.Identity()
  return id and id.key or nil
end

-- Enters this character in the register of the account (or refreshes it) and keeps the register at its limit.
-- Returns the key, nil when the character is not known or there is no database.
function LS.Register()
  local id = LS.Identity()
  if not (id and ns.db) then
    return nil
  end
  if type(ns.db.characters) ~= "table" then
    ns.db.characters = {}
  end
  CS.Touch(ns.db.characters, id.key, id, ns.U.now(), CS.MAX_CHARACTERS)
  return id.key
end

-- The id of the active specialization, nil when the client has no such function or no specialization is chosen.
local function readSpec()
  local index = call("GetSpecialization")
  if type(index) ~= "number" or index < 1 then
    return nil
  end
  local id = call("GetSpecializationInfo", index)
  return type(id) == "number" and id or nil
end

-- True when the client has the specialization functions at all (the settings offer the topic only then).
function LS.HasSpec()
  return type(rawget(_G, "GetSpecialization")) == "function" and type(rawget(_G, "GetSpecializationInfo")) == "function"
end

-- { { id, name } } of the specializations of the current class, empty when the client does not tell.
function LS.SpecList()
  local out = {}
  if not LS.HasSpec() then
    return out
  end
  local count = call("GetNumSpecializations")
  for i = 1, type(count) == "number" and math.min(count, 4) or 0 do
    local id, name = call("GetSpecializationInfo", i)
    if type(id) == "number" and type(name) == "string" then
      out[#out + 1] = { id = id, name = name }
    end
  end
  return out
end

-- State -----------------------------------------------------------------------------------------------------------

local state = {}
local subscribers, order = {}, {}
local frame
local running = false

local function readAll()
  state.combat = flag("InCombatLockdown")
  state.instance = flag("IsInInstance")
  state.grouped = flag("IsInGroup")
  state.mounted = flag("IsMounted")
  state.vehicle = flag("UnitInVehicle", "player")
  state.target = flag("UnitExists", "target")
  state.class = readClass()
  state.spec = readSpec()
  state.character = readCharacter()
end

local function notify(event)
  for _, fn in ipairs(order) do
    fn(state, event)
  end
end

local function onEvent(_, event, unit)
  if event == "PLAYER_REGEN_DISABLED" then
    state.combat = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    state.combat = false
  elseif event == "PLAYER_ENTERING_WORLD" then
    readAll()
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    state.instance = flag("IsInInstance")
  elseif event == "GROUP_ROSTER_UPDATE" then
    state.grouped = flag("IsInGroup")
  elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
    state.mounted = flag("IsMounted")
  elseif event == "PLAYER_TARGET_CHANGED" then
    state.target = flag("UnitExists", "target")
  elseif event == "UNIT_ENTERED_VEHICLE" then
    if unit == "player" then
      state.vehicle = true
    end
  elseif event == "UNIT_EXITED_VEHICLE" then
    if unit == "player" then
      state.vehicle = false
    end
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
    state.spec = readSpec()
  end
  notify(event)
end

local function start()
  if running then
    return
  end
  if not frame then
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", ns.Wrap("loadstate-event", onEvent))
  end
  -- A client may not know an event: that one is left out, the others still work.
  for _, event in ipairs(LS.EVENTS) do
    pcall(frame.RegisterEvent, frame, event)
  end
  for _, event in ipairs(LS.UNIT_EVENTS) do
    pcall(frame.RegisterUnitEvent, frame, event, "player")
  end
  running = true
  readAll()
end

local function stop()
  if frame and running then
    frame:UnregisterAllEvents()
  end
  running = false
end

-- The current state. The table is shared and read only; a topic that could not be read is nil. Without a
-- subscriber nothing keeps it up to date, so it is read afresh then.
function LS.Get()
  if not running then
    readAll()
  end
  return state
end

-- Reads everything again and tells the subscribers (a host calls this after a loading screen).
function LS.Resync()
  readAll()
  notify("resync")
end

-- Calls fn(state, event) after every change of the state. The first subscriber starts the event frame, the
-- last Unsubscribe stops it. Subscribing the same function twice counts once. Returns fn.
function LS.Subscribe(fn)
  if type(fn) ~= "function" or subscribers[fn] then
    return fn
  end
  local safe = ns.Wrap("loadstate-subscriber", fn)
  subscribers[fn] = safe
  order[#order + 1] = safe
  start()
  return fn
end

function LS.Unsubscribe(fn)
  local safe = subscribers[fn]
  if not safe then
    return
  end
  subscribers[fn] = nil
  for i, entry in ipairs(order) do
    if entry == safe then
      table.remove(order, i)
      break
    end
  end
  if #order == 0 then
    stop()
  end
end

-- The frame that holds the event registrations, nil until the first subscriber (for the diagnosis and tests).
function LS.Frame()
  return frame
end

function LS.IsRunning()
  return running
end

ns.On("PLAYER_LOGIN", function()
  LS.Register()
end)
