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
PB.EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_NAME_UPDATE" }
-- Restrictions in which the game may lock plates of other players: nothing is set while one is active.
PB.LOCKED = { "Encounter", "ChallengeMode", "PvPMatch" }
-- Seconds until a known player that the gate turned away is looked at again (the gate counts per second).
PB.RETRY_DELAY = 1.2
-- A plate whose player cannot be read yet (the name arrives after the plate) is looked at again this many seconds after
-- it appeared, at most once per entry, and when the game says the name changed. Never a loop: three looks at most.
PB.RETRY_AT = { 0.2, 0.6, 1.5 }
PB.TICK = 0.2

local pool = PBL.NewPool()
local errors = PBL.NewErrors()
local gate = NL.NewGate()
local free = {} -- hidden frames that wait for a plate
local bound = {} -- unit token -> the frame that marks its plate
local anchored = {} -- unit token -> what its logo is anchored to ("name" or "plate")
local outcome = {} -- unit token -> what the last pass decided ("ok", a reason or an error), for the dev probe
local kind = {} -- unit token -> what the last pass found: "known", "unknown", "unreadable name", ...
local waiting = {} -- unit token -> { at, n }: plates whose player could not be read yet
local counts =
  { added = 0, known = 0, unknown = 0, unreadable = 0, notplayer = 0, gateKnown = 0, retries = 0, recovered = 0 }
local tickArmed = false
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

-- The last plate events with their decision, newest last in a ring (memory only, no names): time, event, unit
-- token and a short text. The dev probe prints them, they show why a logo came and went.
local LOG_SIZE = 30
local log, logAt = {}, 0
local refusals = 0

local function record(event, unit, detail)
  logAt = logAt % LOG_SIZE + 1
  log[logAt] = { t = clock(), event = event, unit = unit, detail = detail }
end

-- The newest plate events first, copies: { t, event, unit, detail }.
function PB.Events()
  local out = {}
  for i = 0, LOG_SIZE - 1 do
    local item = log[(logAt - i - 1) % LOG_SIZE + 1]
    if not item then
      break
    end
    out[#out + 1] = { t = item.t, event = item.event, unit = item.unit, detail = item.detail }
  end
  return out
end

-- How often the game refused to anchor a logo to a plate in this session (a plate it keeps to itself).
function PB.Refusals()
  return refusals
end

-- An error text of the game that says "this plate may not be used", not a fault of this add-on.
local function refusedByGame(err)
  err = tostring(err)
  return err:find("disallowed", 1, true) ~= nil
    or err:find("forbidden", 1, true) ~= nil
    or err:find("ADDON_ACTION", 1, true) ~= nil
    or err:find("protected", 1, true) ~= nil
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

-- What the last pass decided for a unit token: "ok" or the reason there is no logo ("unknown" the register
-- does not know the name, "noname" the name is secret or missing, "notplayer", "chatonly", "consent", "off",
-- "locked", "no plate", "no pool frame", "anchor refused", "gate pause|crowd|budget"). nil when never seen.
function PB.Outcome(unit)
  return outcome[unit]
end

-- What the logo of a unit is anchored to: "name" (the name of the plate), "plate" (the plate itself) or nil.
function PB.Anchor(unit)
  return anchored[unit]
end

-- The pass counters of the gate that keeps a crowd of plates from costing time.
function PB.GateStats()
  local copy = {}
  for key, value in pairs(gate.stats) do
    copy[key] = value
  end
  return copy
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
    -- One picture per place in the row: the add-on logo, then the guild and the community symbols.
    frame.slots = {}
    for i = 1, PBL.MAX_CRESTS + 1 do
      local tex = frame:CreateTexture(nil, "OVERLAY")
      tex:Hide()
      frame.slots[i] = tex
    end
    frame.tex = frame.slots[1]
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
  anchored[unit] = nil
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
  for unit in pairs(waiting) do
    waiting[unit] = nil
  end
  for unit in pairs(bound) do
    release(unit)
  end
end

-- The pictures of one row, in order: { path } for the add-on logo, the entry of CrestLocal for a symbol.
local function rowItems(plan, size)
  local items = {}
  if plan.forever then
    items[1] = { path = ns.BadgeAssets.Path(size) }
  end
  for _, entry in ipairs(plan.crests) do
    items[#items + 1] = entry
  end
  return items
end

local function paint(tex, item)
  if item.path then
    tex:SetTexture(item.path)
    tex:SetVertexColor(1, 1, 1)
    return
  end
  local icon = item.icon
  tex:SetTexture(icon.file)
  if icon.r then
    tex:SetVertexColor(icon.r / 255, (icon.g or 255) / 255, (icon.b or 255) / 255)
  else
    tex:SetVertexColor(1, 1, 1)
  end
end

-- Lays the pictures of the row side by side inside the frame and sizes the frame to the row.
local function layout(frame, plan)
  local wanted = PBL.CleanSize(settings().plateBadgeSize)
  local items = rowItems(plan, wanted)
  local row = PBL.Layout(#items, wanted)
  frame:SetSize(row.width, row.size)
  for i, tex in ipairs(frame.slots) do
    local item = items[i]
    if item then
      tex:ClearAllPoints()
      tex:SetSize(row.size, row.size)
      tex:SetPoint("LEFT", frame, "LEFT", (i - 1) * (row.size + row.gap), 0)
      paint(tex, item)
      tex:Show()
    else
      tex:Hide()
    end
  end
end

-- The name of the plate (the text field of its unit frame) as the anchor target, nil when the game does not give
-- it. Only the field is read, never a size or a state. The Forever client keeps it in plate.UnitFrame.name.
local function nameRegion(plate)
  local ok, region = pcall(function()
    local unitFrame = plate.UnitFrame
    return unitFrame and unitFrame.name
  end)
  return ok and type(region) == "table" and region or nil
end

-- Hangs the frame on the plate as its child (it takes the scale the game gives the plate with the distance) and
-- anchors the row to the top of the name, so it sits on the name whatever the shape of the plate is (a bar
-- plate or a plate with the name only). When the name cannot be reached or the game refuses that anchor, the
-- plate itself is the target. Returns what it was anchored to, "name" or "plate". Raises an error when the game
-- refuses the anchor to the plate too.
local function place(frame, plate, plan)
  local pos = PBL.Position(settings().plateBadgeSide)
  layout(frame, plan)
  frame:ClearAllPoints()
  frame:SetParent(plate)
  local name = nameRegion(plate)
  if name and pcall(frame.SetPoint, frame, pos.point, name, pos.relPoint, pos.x, pos.y) then
    frame:Show()
    return "name"
  end
  frame:ClearAllPoints()
  frame:SetPoint(pos.point, plate, pos.relPoint, pos.x, pos.y)
  frame:Show()
  return "plate"
end

local function plateOfUnit(unit)
  local api = g("C_NamePlate")
  if type(api) ~= "table" or type(api.GetNamePlateForUnit) ~= "function" then
    return nil
  end
  local ok, plate = pcall(api.GetNamePlateForUnit, unit)
  return ok and type(plate) == "table" and plate or nil
end

-- The parts of a plate the anchor looks for, by their type only (nothing is asked of the plate): { unitFrame, name }.
function PB.Parts(unit)
  local plate = plateOfUnit(unit)
  if not plate then
    return nil
  end
  local ok, unitFrame = pcall(function()
    return plate.UnitFrame
  end)
  return { unitFrame = ok and type(unitFrame) or "nil", name = nameRegion(plate) and "table" or "nil" }
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
  -- A player whose name the client has not loaded yet is called "Unknown": no name to look up, try again later.
  if name == g("UNKNOWNOBJECT") or name == "Unknown" then
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

-- Further spellings of the same player for the register: the name with the realm the game reports (a player
-- of another realm is stored under "Name-Realm", the unit reader of the Forever client gives the surname as the
-- second result and no realm). Only strings that are readable and differ from the first name are returned.
local function altNames(unit, first)
  local out, seen = {}, { [PN.Key(first)] = true }
  local function add(name)
    name = Guard.Safe(name)
    if type(name) ~= "string" or name == "" then
      return
    end
    name = PN.Clean(name)
    local key = PN.Key(name)
    if key ~= "" and not seen[key] then
      seen[key] = true
      out[#out + 1] = name
    end
  end
  local okFull, _, realm = pcall(g("UnitFullName") or function() end, unit)
  realm = okFull and Guard.Safe(realm) or nil
  if type(realm) == "string" and realm ~= "" and not first:find("-", 1, true) then
    add(first .. "-" .. realm)
  end
  add(call("GetUnitName", unit, true))
  return out
end

-- Guild and community symbols of a player, the same sources as the chat: logos he sends and the local
-- recognition (CrestLocal). Empty without a source or with both kinds switched off.
local function crestsOf(unit, names, wanted)
  if wanted.guild == false and wanted.community == false then
    return {}
  end
  local mark, recognition = ns.CrestMark, ns.CrestLocal
  if not (mark and recognition and (mark.Listening() or recognition.On())) then
    return {}
  end
  for _, name in ipairs(names) do
    local ok, entries = pcall(recognition.ShownUnit, name, unit)
    if ok and type(entries) == "table" and entries[1] then
      return entries
    end
  end
  return {}
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
    local names = { facts.name }
    for _, alt in ipairs(altNames(unit, facts.name)) do
      names[#names + 1] = alt
    end
    for _, name in ipairs(names) do
      facts.self = facts.self or PN.Equal(name, PN.Self())
      facts.present = facts.present or ns.Presence.Flags(name)
    end
    facts.names = names
    facts.logoOn = settings().plateShowLogo ~= false
    facts.wanted = { guild = settings().plateCrestGuild ~= false, community = settings().plateCrestCommunity ~= false }
    facts.entries = crestsOf(unit, names, facts.wanted)
  end
  return facts
end

-- Sets, moves or removes the logo of one unit. Raises an error when the game refuses the anchor.
-- What a plate turned out to be, for the counters and the event log: "known" (register or symbols), "unknown" (a
-- readable player the register does not know), "unreadable player" or "unreadable name" (not readable yet, secret or
-- not loaded), "not a player".
local function classify(facts, plan)
  if facts.player == nil then
    return "unreadable player"
  elseif facts.player ~= true then
    return "not a player"
  elseif not facts.name then
    return "unreadable name"
  elseif facts.present then
    return "known"
  end
  return plan and "known" or "unknown"
end

local UNREADABLE = { ["unreadable player"] = true, ["unreadable name"] = true }

-- keep: the call is a later pass over a plate that already has its logo (not the event of a new plate), so a
-- value the game hides for a moment (a secret name in combat) leaves the logo where it is.
-- The cheap part (who is this, does the register know him) runs for every plate; the gate with its budget guards
-- only the expensive part, drawing a new logo, so strangers in a crowd cost nothing.
local function apply(unit, keep)
  if type(unit) ~= "string" then
    return
  end
  kind[unit] = nil
  if not PB.On() then
    outcome[unit] = "off"
    release(unit)
    return
  end
  if restricted() then
    outcome[unit] = "locked"
    return
  end
  local facts = factsOf(unit)
  local plan, why = PBL.Plan(facts)
  kind[unit] = classify(facts, plan)
  if not plan then
    if keep and bound[unit] and (why == "noname" or why == "notplayer") then
      outcome[unit] = "kept " .. why
      record("kept", unit, why)
      return
    end
    outcome[unit] = why
    release(unit)
    return
  end
  local plate = plateOfUnit(unit)
  if not plate then
    outcome[unit] = "no plate"
    release(unit)
    return
  end
  local frame = bound[unit]
  if not frame then
    local admitted, held = gate:Admit(clock())
    if not admitted then
      outcome[unit] = "gate " .. tostring(held)
      counts.gateKnown = counts.gateKnown + 1
      -- A known player the gate turned away is picked up by one pass a little later.
      ns.Debounce("platebadge-retry", PB.RETRY_DELAY, PB.Rescan)
      return
    end
    frame = acquire()
    if not frame then
      outcome[unit] = "no pool frame"
      return
    end
  end
  bound[unit] = frame
  local started = profile()
  local ok, err = pcall(place, frame, plate, plan)
  local stopped = profile()
  if started and stopped then
    gate:Charge(stopped - started)
  end
  if ok then
    anchored[unit] = err
  else
    outcome[unit] = "anchor refused"
    release(unit)
    if refusedByGame(err) then
      -- The game keeps this plate to itself (forbidden in some places): no logo, and no fault of ours.
      refusals = refusals + 1
      record("refused", unit, tostring(err):sub(1, 60))
      return
    end
    error(err, 0)
  end
  outcome[unit] = why == "crests" and "ok (symbols only)" or "ok"
end

-- The counters of this session: { added, known, unknown, unreadable, notplayer, gateKnown (known players the gate
-- turned away), retries, recovered (plates that were bound after a retry), waiting (plates still waiting) }.
function PB.Counts()
  local copy = {}
  for key, value in pairs(counts) do
    copy[key] = value
  end
  local n = 0
  for _ in pairs(waiting) do
    n = n + 1
  end
  copy.waiting = n
  return copy
end

-- What the last pass found for a unit token, see classify.
function PB.Kind(unit)
  return kind[unit]
end

-- The facts the logo decision of one plate unit works from, read the same way the real pass reads them (every game
-- call protected), for the dev probe: { player = "yes|no|secret|missing", name = "readable|secret|missing",
-- names = readable spellings tried for the register, guid = "readable|secret|missing", plate = bool,
-- known = register entry or nil, show = bool, why = reason, shown = bool, last = last pass outcome }.
function PB.Explain(unit)
  local info = { unit = unit, last = outcome[unit], shown = bound[unit] ~= nil, plate = plateOfUnit(unit) ~= nil }
  local function state(ok, value)
    if not ok or value == nil then
      return "missing"
    end
    return Guard.Safe(value) == nil and "secret" or "readable"
  end
  local okP, isPlayer = pcall(g("UnitIsPlayer") or function() end, unit)
  local playerState = state(okP, isPlayer)
  info.player = playerState == "readable" and (isPlayer == true and "yes" or "no") or playerState
  local okN, name = pcall(g("UnitName") or function() end, unit)
  info.name = state(okN, name)
  local okG, guid = pcall(g("UnitGUID") or function() end, unit)
  info.guid = state(okG, guid)
  local facts = factsOf(unit)
  info.names = facts.names or {}
  info.known = facts.present
  info.show, info.why = PBL.Decide(facts)
  return info
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
  record("error", nil, tostring(err):sub(1, 60))
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
  local seen, readable = {}, 0
  for _, plate in ipairs(plates) do
    local read, token = pcall(function()
      return plate.namePlateUnitToken
    end)
    token = read and Guard.Safe(token) or nil
    if type(token) == "string" then
      readable = readable + 1
      seen[token] = true
      guarded(apply, token, true)
    end
  end
  -- Plates whose token cannot be read prove nothing: releasing every logo on that basis would wipe them all.
  if restricted() or (readable == 0 and #plates > 0) then
    return
  end
  local gone = 0
  for unit in pairs(bound) do
    if not seen[unit] then
      gone = gone + 1
      release(unit)
    end
  end
  record("rescan", nil, string.format("plates %d, logos %d, released %d", #plates, PB.Stats().bound, gone))
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
local retry

local function armTick()
  local timer = g("C_Timer")
  if tickArmed or next(waiting) == nil or type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  tickArmed = true
  pcall(timer.After, PB.TICK, function()
    tickArmed = false
    local now = clock()
    for unit, item in pairs(waiting) do
      local due = PB.RETRY_AT[item.n + 1]
      if not due then
        waiting[unit] = nil
      elseif now - item.at >= due - 0.001 then
        retry(unit, item)
      end
    end
    armTick()
  end)
end

-- One more look at a plate whose player could not be read; ends after a result or after the last try.
retry = function(unit, item)
  item.n = item.n + 1
  counts.retries = counts.retries + 1
  guarded(apply, unit)
  local class = kind[unit]
  record("retry", unit, string.format("%d: %s: %s", item.n, tostring(class), tostring(outcome[unit])))
  if bound[unit] then
    counts.recovered = counts.recovered + 1
    waiting[unit] = nil
  elseif not UNREADABLE[class] or item.n >= #PB.RETRY_AT then
    waiting[unit] = nil
  end
end

-- A plate appeared. The cheap check runs at once; a plate whose player cannot be read yet is looked at again a
-- moment later and when the game reports a name change.
function PB.Added(unit)
  if not PB.On() or type(unit) ~= "string" then
    return
  end
  guarded(apply, unit)
  local class = kind[unit]
  counts.added = counts.added + 1
  if class == "known" then
    counts.known = counts.known + 1
  elseif class == "unknown" then
    counts.unknown = counts.unknown + 1
  elseif class == "not a player" then
    counts.notplayer = counts.notplayer + 1
  elseif class then
    counts.unreadable = counts.unreadable + 1
  end
  record("added", unit, string.format("%s: %s", tostring(class), tostring(outcome[unit])))
  if UNREADABLE[class] and not bound[unit] then
    waiting[unit] = { at = clock(), n = 0 }
    armTick()
  end
end

-- The game says a name was loaded or changed: a plate that waits for it is looked at now.
function PB.NameUpdated(unit)
  local item = type(unit) == "string" and waiting[unit] or nil
  if item and PB.On() then
    retry(unit, item)
  end
end

-- A plate went away: the frame goes back to the pool at once.
function PB.Removed(unit)
  if type(unit) == "string" then
    record("removed", unit, bound[unit] and "had a logo" or "no logo")
    outcome[unit], kind[unit], waiting[unit] = nil, nil, nil
    release(unit)
  end
end

events:SetScript("OnEvent", function(_, event, unit)
  if event == "NAME_PLATE_UNIT_ADDED" then
    PB.Added(unit)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    PB.Removed(unit)
  elseif event == "UNIT_NAME_UPDATE" then
    PB.NameUpdated(unit)
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
  if
    type(path) ~= "string"
    or not (
      path:find("^settings%.plateBadge")
      or path:find("^settings%.plateShowLogo")
      or path:find("^settings%.plateCrest")
    )
  then
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
  record("presence", nil, "register changed")
  PB.Rescan()
end)
