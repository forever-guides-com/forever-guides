-- Plate badge: the add-on logo at the nameplate of players who want to be recognized (Presence). Only the
-- local display changes, nothing is sent. Everything is opt-in:
--   settings.plateBadge on AND the receive consent of "presenceMark" for the group or the guild
-- and per plate: a player, a register entry without the chat-only wish (the own plate only with
-- settings.plateBadgeSelf).
-- Safety: a pool of own frames (built outside combat, never destroyed), each one child of the plate it marks
-- and set with SetParent and SetPoint only. Nothing of a foreign plate is read (width, height, shown state,
-- alpha and anchors can be secret in Retail 12), no OnUpdate, no hook on the game. Every call that touches a
-- plate runs in pcall, a refused anchor leaves the plate without a logo, and three errors switch the feature
-- off for the session. The plate events are registered only while the feature is on.
-- A plate that cannot be reached, a secret or unknown name, a locked encounter: no logo, silently.
local _, ns = ...
local PBL, PN, Guard, Consent, NL = ns.PlateBadgeLogic, ns.PlayerName, ns.AutoGuard, ns.Consent, ns.NearbyLogic

local PB = {}
ns.PlateBadge = PB

PB.FN = "presenceMark"
PB.EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }
-- Restrictions in which the game may lock plates of other players: nothing is set while one is active.
PB.LOCKED = { "Encounter", "ChallengeMode", "PvPMatch" }

local pool = PBL.NewPool()
local errors = PBL.NewErrors()
local gate = NL.NewGate()
local free = {} -- hidden frames that wait for a plate
local bound = {} -- unit token -> the frame that marks its plate
local registered = false
local events = CreateFrame("Frame")

local function g(name)
  return rawget(_G, name)
end

local function settings()
  return ns.db and ns.db.settings or {}
end

-- A game function by name, protected: nil when it is missing or raises an error.
local function call(name, ...)
  local fn = g(name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if ok then
    return value
  end
  return nil
end

local function clock()
  return tonumber(call("GetTime")) or 0
end

-- Milliseconds with a fine resolution, nil when the client has no such clock.
local function profile()
  local fn = g("debugprofilestop")
  if type(fn) == "function" then
    return tonumber(fn())
  end
  return nil
end

-- Switches -------------------------------------------------------------------------------------------

-- Receiving is allowed for at least one audience.
function PB.Allowed()
  return Consent.Allows(PB.FN, "receive", "group") or Consent.Allows(PB.FN, "receive", "guild")
end

-- Switch on, consent given and not off for this session: logos may be shown.
function PB.On()
  return not errors:IsOff() and settings().plateBadge == true and PB.Allowed()
end

-- Errors and the switch-off of this session; switching the feature on again starts afresh.
function PB.Errors()
  return errors:Count(), errors:IsOff()
end

-- True while the plate events are registered.
function PB.Registered()
  return registered
end

function PB.Stats()
  local stats = pool:Stats()
  local n = 0
  for _ in pairs(bound) do
    n = n + 1
  end
  stats.bound = n
  return stats
end

-- The frame that marks the plate of this unit token, nil when there is none.
function PB.FrameOf(unit)
  return bound[unit]
end

local function inCombat()
  return ns.InCombat() or Guard.Blocked()
end

local function restricted()
  return ns.AddonRestricted(unpack(PB.LOCKED))
end

-- Frames --------------------------------------------------------------------------------------------

-- A new pool frame. Never in combat (the caller checks), never more than the cap.
local function build()
  local make = g("CreateFrame")
  if type(make) ~= "function" then
    return nil
  end
  local ok, frame = pcall(make, "Frame", nil, g("UIParent"))
  if not ok or type(frame) ~= "table" then
    return nil
  end
  local made = pcall(function()
    frame:SetSize(PBL.DEFAULT_SIZE, PBL.DEFAULT_SIZE)
    frame:Hide()
    frame:SetIgnoreParentAlpha(true)
    frame.tex = frame:CreateTexture(nil, "OVERLAY")
    frame.tex:SetAllPoints()
  end)
  if not made then
    return nil
  end
  pool:Built()
  free[#free + 1] = frame
  return frame
end

-- Builds the missing pool frames, only outside combat.
local function fill()
  if inCombat() then
    return
  end
  for _ = 1, pool:Missing() do
    if not build() then
      break
    end
  end
end

-- A frame for a new logo: from the pool, or a new one outside combat, or nil.
local function acquire()
  local plan = pool:Plan(inCombat())
  if plan == "build" and not build() then
    return nil
  end
  if plan == nil or not pool:Take() then
    return nil
  end
  return table.remove(free)
end

local function release(unit)
  local frame = bound[unit]
  if not frame then
    return
  end
  bound[unit] = nil
  -- Only our own frame is touched here.
  pcall(function()
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(g("UIParent"))
  end)
  free[#free + 1] = frame
  pool:Put()
end

local function clear()
  for unit in pairs(bound) do
    release(unit)
  end
end

-- Hangs the frame on the plate as its child (it takes the scale the game gives the plate with the distance).
-- Raises an error when the game refuses the anchor.
local function place(frame, plate)
  local s = settings()
  local size = PBL.CleanSize(s.plateBadgeSize)
  local pos = PBL.Position(s.plateBadgeSide)
  local path = ns.BadgeAssets.Path(size)
  frame:SetSize(size, size)
  if frame.path ~= path then
    frame.tex:SetTexture(path)
    frame.path = path
  end
  frame:ClearAllPoints()
  frame:SetParent(plate)
  frame:SetPoint(pos.point, plate, pos.relPoint, pos.x, pos.y)
  frame:Show()
end

local function plateOfUnit(unit)
  local api = g("C_NamePlate")
  if type(api) ~= "table" or type(api.GetNamePlateForUnit) ~= "function" then
    return nil
  end
  local ok, plate = pcall(api.GetNamePlateForUnit, unit)
  return ok and type(plate) == "table" and plate or nil
end

-- Full name of a unit: nil when the name or the surname is secret or missing.
local function nameOf(unit)
  local ok, name, surname = pcall(g("UnitName") or function() end, unit)
  if not ok then
    return nil
  end
  name = Guard.Safe(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  if surname ~= nil then
    surname = Guard.Safe(surname)
    if surname == nil then
      return nil
    end
  end
  local full = PN.FromUnit(name, surname)
  return full ~= "" and full or nil
end

local function factsOf(unit)
  local facts = {
    enabled = PB.On(),
    listening = PB.Allowed(),
    player = Guard.Safe(call("UnitIsPlayer", unit)),
    selfOn = settings().plateBadgeSelf == true,
  }
  if facts.player ~= true then
    return facts
  end
  facts.name = nameOf(unit)
  if facts.name then
    facts.self = PN.Equal(facts.name, PN.Self())
    facts.present = ns.Presence.Flags(facts.name)
  end
  return facts
end

-- Sets, moves or removes the logo of one unit. Raises an error when the game refuses the anchor.
local function apply(unit)
  if type(unit) ~= "string" then
    return
  end
  if not PB.On() then
    release(unit)
    return
  end
  if restricted() then
    return
  end
  if not PBL.Decide(factsOf(unit)) then
    release(unit)
    return
  end
  local plate = plateOfUnit(unit)
  if not plate then
    release(unit)
    return
  end
  local frame = bound[unit] or acquire()
  if not frame then
    return
  end
  bound[unit] = frame
  local ok, err = pcall(place, frame, plate)
  if not ok then
    release(unit)
    error(err, 0)
  end
end

local function listen(on)
  if registered == on then
    return
  end
  registered = on
  for _, event in ipairs(PB.EVENTS) do
    pcall(on and events.RegisterEvent or events.UnregisterEvent, events, event)
  end
end

local function fail(err)
  ns.Log.warn("platebadge: %s", tostring(err))
  if not errors:Hit() then
    return
  end
  -- Off first: the notice below is itself a chat line.
  listen(false)
  clear()
  local text = string.format(ns.L["platebadge.off"], errors:Count())
  ns.Errors.add({ msg = text, kind = "warning", ctx = "platebadge" })
  ns.Notify(text, "warning")
end

-- Runs a step protected: an error counts against the feature and never reaches the game.
local function guarded(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    fail(err)
  end
end

-- Sets the logos of all plates that exist and removes the ones of plates that are gone. Also picks up what
-- an earlier lock or a full pool left out.
function PB.Rescan()
  if not PB.On() then
    return
  end
  local api = g("C_NamePlate")
  local ok, plates = pcall(type(api) == "table" and api.GetNamePlates or function() end)
  if not ok or type(plates) ~= "table" then
    return
  end
  local seen = {}
  for _, plate in ipairs(plates) do
    local read, token = pcall(function()
      return plate.namePlateUnitToken
    end)
    token = read and Guard.Safe(token) or nil
    if type(token) == "string" then
      seen[token] = true
      guarded(apply, token)
    end
  end
  if restricted() then
    return
  end
  for unit in pairs(bound) do
    if not seen[unit] then
      release(unit)
    end
  end
end

-- Applies the switches: on registers the events, fills the pool and marks the plates, off removes every
-- logo and unregisters the events.
function PB.Refresh()
  if PB.On() then
    listen(true)
    guarded(fill)
    PB.Rescan()
  else
    listen(false)
    clear()
  end
end

-- A plate appeared. The gate keeps a crowd (cities, battlegrounds) from costing time.
function PB.Added(unit)
  if not PB.On() or not gate:Admit(clock()) then
    return
  end
  local started = profile()
  guarded(apply, unit)
  local stopped = profile()
  if started and stopped then
    gate:Charge(stopped - started)
  end
end

-- A plate went away: the frame goes back to the pool at once.
function PB.Removed(unit)
  if type(unit) == "string" then
    release(unit)
  end
end

events:SetScript("OnEvent", function(_, event, unit)
  if event == "NAME_PLATE_UNIT_ADDED" then
    PB.Added(unit)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    PB.Removed(unit)
  end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
  PB.Refresh()
end)
-- Combat is over: build what the pool missed and set what was left out.
ns.On("PLAYER_REGEN_ENABLED", function()
  if PB.On() then
    guarded(fill)
    PB.Rescan()
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path, value)
  if type(path) ~= "string" or not path:find("^settings%.plateBadge") then
    return
  end
  if path == "settings.plateBadge" and value == true then
    errors:Reset()
  end
  PB.Refresh()
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn)
  if fn == PB.FN then
    PB.Refresh()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == PB.FN then
    PB.Refresh()
  end
end)
ns.On("FG_PRESENCE_UPDATE", function()
  PB.Rescan()
end)
