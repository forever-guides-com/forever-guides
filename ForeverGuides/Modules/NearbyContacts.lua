-- Contacts in the neighbourhood: when a player of the contact list (SeenPlayers) shows up as a
-- visible unit, the entry gets its time and place of the last sighting and its current values (level,
-- class, guild, rank, title, PvP, honor level) refreshed. The first contact (source, time, place) never
-- changes. Detection is event driven and passive: NAME_PLATE_UNIT_ADDED, PLAYER_TARGET_CHANGED and
-- UPDATE_MOUSEOVER_UNIT (group members are covered by SeenPlayers.ScanGroup on GROUP_ROSTER_UPDATE).
-- A stranger costs one GUID and one table lookup: nothing is read, stored or asked for him, no
-- OnUpdate and no loop over players exist. Safety nets: one write per contact and 5 minutes, a time
-- budget per second, a pause in crowds, a protected call around everything and a switch-off after
-- three errors (reported to the error list like the automatic helpers). The game only sends the plate
-- events when friendly name plates are shown (Shift+V); the add-on changes that setting only when the
-- player clicks the button in the settings (EnablePlates).
-- A contact in reach of the inspect function is handed to GroupInspect, which keeps the global limit.
-- N.SetHook offers one hook point (nothing in this add-on sets it): a stand-in
-- contact that exists in memory only and a listener for every handled event.
-- Off with settings.nearbyDetect (or settings.seenSave).
local _, ns = ...
local NL, SP, Guard, L, Store = ns.NearbyLogic, ns.SeenPlayers, ns.AutoGuard, ns.L, ns.Store

local N = {}
ns.NearbyContacts = N

ns.AddLocale("enUS", {
  ["nearby.off"] = "Contact detection switched off after %d errors, see /fg errors",
})
ns.AddLocale("deDE", {
  ["nearby.off"] = "Kontakt-Erkennung ausgeschaltet nach %d Fehlern, siehe /fg fehler",
})

local gate = NL.NewGate()
local written = {} -- guid -> time of the last write, this session only
local failures = 0
local seen = { contacts = 0, strangers = 0 }

local function g(name)
  return rawget(_G, name)
end

-- Time in seconds for the windows and the throttles.
local function clock()
  local now = g("GetTime")
  return type(now) == "function" and tonumber(now()) or 0
end

-- Milliseconds with a fine resolution, nil when the client has no such clock.
local function profile()
  local fn = g("debugprofilestop")
  if type(fn) == "function" then
    return tonumber(fn())
  end
  fn = g("GetTimePreciseSec")
  if type(fn) == "function" then
    return (tonumber(fn()) or 0) * 1000
  end
  return nil
end

-- A game function by name, protected. A missing function answers nothing, an error of the function is
-- raised again so that the guard around the event counts it.
local function call(name, ...)
  local fn = g(name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if not ok then
    error(name .. ": " .. tostring(value), 0)
  end
  return value
end

function N.Switch()
  return ns.db ~= nil and ns.db.settings.nearbyDetect ~= false
end

function N.Enabled()
  return N.Switch() and SP.Enabled()
end

-- Friendly player name plates: the game sends plate events for other players only while this setting
-- is on. The Forever client reads it as nameplateShowFriendlyPlayers (nameplateShowFriends is not
-- readable there). It is read and written on request only, never at login and never in combat.
N.PLATES_CVAR = "nameplateShowFriendlyPlayers"

local function cvarFunction(kind)
  local api = g("C_CVar")
  local fn = type(api) == "table" and api[kind .. "CVar"] or g(kind .. "CVar")
  return type(fn) == "function" and fn or nil
end

-- "on", "off" or "unreadable" (no function, an error or no value).
function N.PlatesState()
  local get = cvarFunction("Get")
  if not get then
    return "unreadable"
  end
  local ok, value = pcall(get, N.PLATES_CVAR)
  if not ok or value == nil then
    return "unreadable"
  end
  return (value == "1" or value == 1 or value == true) and "on" or "off"
end

-- Switches the plates on. Returns true, or false and the reason: "combat", "unavailable" (no
-- function, or the setting cannot be read) or "failed" (the game did not keep the value).
function N.EnablePlates()
  local inCombat = g("InCombatLockdown")
  if type(inCombat) == "function" and inCombat() then
    return false, "combat"
  end
  local set = cvarFunction("Set")
  if not set or N.PlatesState() == "unreadable" then
    return false, "unavailable"
  end
  if not pcall(set, N.PLATES_CVAR, "1") or N.PlatesState() ~= "on" then
    return false, "failed"
  end
  return true
end

local function fail()
  failures = failures + 1
  if failures < NL.MAX_ERRORS then
    return
  end
  Store.set("settings.nearbyDetect", false)
  local msg = string.format(L["nearby.off"], failures)
  ns.Errors.add({ msg = msg, kind = "warning", ctx = "nearby" })
  ns.Notify(msg, "warning")
end

-- The work for one visible unit: only a known contact gets any further than the first lookup. `out`
-- is only set while a hook listens and receives what happened.
local function touch(unit, kind, now, out)
  local guid = Guard.Safe(call("UnitGUID", unit))
  if type(guid) ~= "string" then
    return
  end
  -- A stand-in contact of the hook has its own throttle key and is never handed to the inspect queue.
  local hook = N.hook
  local e, key
  if hook and hook.standIn then
    e, key = hook.standIn(guid, kind)
  end
  local standIn = e ~= nil
  if not standIn then
    e, key = SP.Find(guid), guid
  end
  if not e then
    seen.strangers = seen.strangers + 1
    return
  end
  if not standIn then
    seen.contacts = seen.contacts + 1
  end
  if out then
    out.standIn = standIn
  end
  if not NL.Due(written[key], now, NL.WRITE_EVERY) then
    if out then
      out.throttled = true
    end
    return
  end
  if call("UnitIsPlayer", unit) ~= true then
    return
  end
  written[key] = now
  local facts = SP.Touch(e, unit)
  if out then
    out.facts = facts
  end
  -- The token of a plate or the target stays valid for a while, the one of the mouse does not.
  local inspect = ns.GroupInspect
  if not standIn and kind ~= "mouseover" and inspect and inspect.RequestContact then
    inspect.RequestContact(guid, e.name, unit)
  end
end

-- hook = { standIn = function(guid, kind) -> entry, throttleKey, tap = function(out) } or nil. tap gets one
-- table per handled event { kind, off, dropped, standIn, throttled, facts, error, ms }, synchronously, while
-- the unit token is still valid.
function N.SetHook(hook)
  N.hook = hook
end

-- kind: "plate", "target" or "mouseover".
function N.OnUnit(unit, kind)
  local tap = N.hook and N.hook.tap
  if not N.Enabled() then
    if tap then
      pcall(tap, { kind = kind, unit = unit, off = true })
    end
    return
  end
  local now = clock()
  local admitted, why = gate:Admit(now)
  if not admitted then
    if tap then
      pcall(tap, { kind = kind, unit = unit, dropped = why })
    end
    return
  end
  local out = tap and { kind = kind, unit = unit } or nil
  local from = profile()
  local ok = ns.Safe("nearby", touch, unit, kind, now, out)
  if not ok then
    fail()
  end
  local to = profile()
  if from and to then
    gate:Charge(to - from)
  end
  if tap then
    out.error = not ok
    out.ms = from and to and (to - from) or nil
    pcall(tap, out)
  end
end

-- The handler of the three events, also the entry for the feed of an extension.
function N.Dispatch(event, unit)
  if event == "NAME_PLATE_UNIT_ADDED" then
    N.OnUnit(unit, "plate")
  elseif event == "PLAYER_TARGET_CHANGED" then
    N.OnUnit("target", "target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    N.OnUnit("mouseover", "mouseover")
  end
end

-- Counters for extensions and the tests: admitted and dropped events, strangers and contacts seen.
function N.Stats()
  local s = gate.stats
  return {
    admitted = s.admitted,
    pause = s.pause,
    crowd = s.crowd,
    crowds = s.crowds,
    budget = s.budget,
    contacts = seen.contacts,
    strangers = seen.strangers,
    errors = failures,
  }
end

-- Seconds of crowd pause left.
function N.Paused()
  return gate:Paused(clock())
end

function N.Reset()
  gate:Reset()
  gate.stats = { admitted = 0, pause = 0, crowd = 0, budget = 0, crowds = 0 }
  written, failures = {}, 0
  seen = { contacts = 0, strangers = 0 }
end

-- Events on a frame of their own: no dispatch through the shared event frame for a busy event.
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, unit)
  N.Dispatch(event, unit)
end)
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
  if not pcall(frame.RegisterEvent, frame, event) then
    ns.Log.warn("event %s not available", event)
  end
end

-- Switching it on again starts with a clean slate.
ns.On("FG_SETTING_CHANGED", function(_, path, value)
  if path == "settings.nearbyDetect" and value == true then
    failures = 0
    gate:Reset()
  end
end)
