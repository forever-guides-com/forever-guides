-- The sleeping bag display: a small movable bar with the aura icon, one line of text and a progress bar, shown
-- from the cast of "Sack ausrollen" until the player stands up. It follows the steps of the bag: the cast
-- (with the time left when the game lets the add-on read it), the walk to the bag, lying down, the countdown
-- per stack (every 60 seconds of lying the aura "Gut erholt" gains a stack, up to 3: "stack 1/3, next in 0:42";
-- at 3/3 the same countdown runs to the renewal of the duration) and the time the aura still lasts. The bar stays
-- while the aura lasts: standing up keeps the stack and the time on it, lying down again after a new cast
-- restarts the countdown. A run that is lying is saved in ns.charDB.sleepBagRun and comes back after a /reload.
-- Off by default (settings.sleepBag). A tooltip on the bar explains the numbers.
-- The game calls live here, the state machine and the texts in Modules/SleepBagLogic.lua. Nothing runs while
-- the setting is off or no run is on: the cast events and PLAYER_UPDATE_RESTING (the lying down after the walk starts
-- the run) are registered while the setting is on, the events of moving, fights and auras and the one second timer
-- only while a run (or the wait for a late aura) lasts. The window is no protected frame,
-- so it shows and moves in combat. Position: ns.db.frames.sleepBag, runs: ns.db.sleepBagTimes.
local _, ns = ...
local W, L, U = ns.W, ns.L, ns.U
local SL = ns.SleepBagLogic

local SB = {}
ns.SleepBag = SB

ns.AddLocale("enUS", {
  ["sleepbag.casting"] = "Unrolling the sleeping bag",
  ["sleepbag.castingLeft"] = "Unrolling the sleeping bag, %s left",
  ["sleepbag.walking"] = "Walking to the sleeping bag",
  ["sleepbag.settling"] = "Lying down",
  ["sleepbag.lying"] = "Lying for %s, stack 1 in %s",
  ["sleepbag.lyingLate"] = "Lying for %s, Well Rested is due",
  ["sleepbag.lyingStack"] = "Stack %s, next in %s",
  ["sleepbag.lyingStackLeft"] = "Stack %s, next in %s, %s left",
  ["sleepbag.lyingRenew"] = "Well Rested x%s, renewal in %s",
  ["sleepbag.lyingRenewLeft"] = "Well Rested x%s, renewal in %s, %s left",
  ["sleepbag.stackLate"] = "Stack %s, the next one is due",
  ["sleepbag.renewLate"] = "Well Rested x%s, the renewal is due",
  ["sleepbag.rested"] = "Well Rested x%s, %s left",
  ["sleepbag.restedPlain"] = "Well Rested x%s is active",
  ["sleepbag.tip.title"] = "Sleeping bag",
  ["sleepbag.close"] = "Hide the bar until the next run",
  ["sleepbag.tip.rule"] = "Every minute of lying adds one stack of Well Rested, up to 3. At 3 every minute of lying renews the duration.",
  ["sleepbag.tip.stacks"] = "Stacks: %s",
  ["sleepbag.tip.counted"] = "The game hides the number, so the add-on counts one stack per minute of lying (~).",
  ["sleepbag.tip.next"] = "Next stack in %s",
  ["sleepbag.tip.nextRenew"] = "Next renewal in %s",
  ["sleepbag.tip.left"] = "Well Rested lasts %s more",
  ["sleepbag.tip.full"] = "All stacks are there, lying only renews the duration.",
  ["sleepbag.endedStood"] = "You stand up again. Lying time: %s.",
  ["sleepbag.endedEarly"] = "Got up too early: %s of about %s.",
  ["sleepbag.endedNoLie"] = "You did not lie down, the sleeping bag display ends.",
  ["sleepbag.endedAborted"] = "The sleeping bag was interrupted.",
  ["sleepbag.endedRested"] = "Well Rested x%s is active.",
})
ns.AddLocale("deDE", {
  ["sleepbag.casting"] = "Sack wird ausgerollt",
  ["sleepbag.castingLeft"] = "Sack wird ausgerollt, noch %s",
  ["sleepbag.walking"] = "Weg zum Schlafsack",
  ["sleepbag.settling"] = "Hinlegen",
  ["sleepbag.lying"] = "Liegt seit %s, Stapel 1 in %s",
  ["sleepbag.lyingLate"] = "Liegt seit %s, Gut erholt kommt gleich",
  ["sleepbag.lyingStack"] = "Stapel %s, nächster in %s",
  ["sleepbag.lyingStackLeft"] = "Stapel %s, nächster in %s, Rest %s",
  ["sleepbag.lyingRenew"] = "Gut erholt x%s, Erneuerung in %s",
  ["sleepbag.lyingRenewLeft"] = "Gut erholt x%s, Erneuerung in %s, Rest %s",
  ["sleepbag.stackLate"] = "Stapel %s, der nächste kommt gleich",
  ["sleepbag.renewLate"] = "Gut erholt x%s, die Erneuerung kommt gleich",
  ["sleepbag.rested"] = "Gut erholt x%s, noch %s",
  ["sleepbag.restedPlain"] = "Gut erholt x%s ist aktiv",
  ["sleepbag.tip.title"] = "Schlafsack",
  ["sleepbag.close"] = "Leiste bis zum nächsten Durchlauf ausblenden",
  ["sleepbag.tip.rule"] = "Jede Minute im Liegen bringt einen Stapel Gut erholt, höchstens 3. Bei 3 erneuert jede Minute im Liegen die Dauer.",
  ["sleepbag.tip.stacks"] = "Stapel: %s",
  ["sleepbag.tip.counted"] = "Das Spiel verbirgt die Zahl, deshalb zählt das Addon einen Stapel pro Minute im Liegen (~).",
  ["sleepbag.tip.next"] = "Nächster Stapel in %s",
  ["sleepbag.tip.nextRenew"] = "Nächste Erneuerung in %s",
  ["sleepbag.tip.left"] = "Gut erholt hält noch %s",
  ["sleepbag.tip.full"] = "Alle Stapel sind da, Liegen erneuert nur die Dauer.",
  ["sleepbag.endedStood"] = "Du stehst wieder auf. Liegedauer: %s.",
  ["sleepbag.endedEarly"] = "Zu früh aufgestanden: %s von etwa %s.",
  ["sleepbag.endedNoLie"] = "Du hast dich nicht hingelegt, die Schlafsack-Anzeige endet.",
  ["sleepbag.endedAborted"] = "Der Schlafsack wurde unterbrochen.",
  ["sleepbag.endedRested"] = "Gut erholt x%s ist aktiv.",
})

local WIDTH, HEIGHT, PAD, ICON = 340, 46, 6, 32
local BAR_H = 8
local CLOSE = 18
local BG_HEX, BG_ALPHA = "1a1a1a", 0.92
local BAR_HEX = "c9a670"
-- Unit events of the cast, registered while the setting is on; the other events only during a run.
local CAST_EVENTS = {
  "UNIT_SPELLCAST_START",
  "UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_SPELLCAST_STOP",
  "UNIT_SPELLCAST_CHANNEL_STOP",
  "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_FAILED",
}
-- PLAYER_UPDATE_RESTING is registered while the setting is on: lying down with the aura on starts a run.
local REST_EVENTS = { "PLAYER_UPDATE_RESTING" }
local RUN_EVENTS = { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_REGEN_DISABLED" }
-- The resting flag can lag behind the loading screen after a /reload: the saved run is tried again after these delays.
local RESTORE_DELAYS = { 1, 4 }

local state = SL.new(nil)
local frame, driver, runEvents, castEvents
-- The close button hides the bar for the run that is on; the next run shows it again.
local dismissed = false

-- Game access ------------------------------------------------------------------------------------------------

local function nowSeconds()
  return type(GetTime) == "function" and GetTime() or 0
end

local function isSecret(value)
  local fn = rawget(_G, "issecretvalue")
  if type(fn) ~= "function" then
    return false
  end
  local ok, hidden = pcall(fn, value)
  return not ok or hidden == true
end

local function serverNow()
  local fn = rawget(_G, "GetServerTime")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn)
  return ok and value or nil
end

local function resting()
  local fn = rawget(_G, "IsResting")
  if type(fn) ~= "function" then
    return false
  end
  local ok, value = pcall(fn)
  return ok and value == true
end

-- Clients without C_UnitAuras: UnitAura lists name, icon, count, type, duration, expiration, source, stealable,
-- nameplate flag and the spell id.
local function readLegacyAura()
  local fn = rawget(_G, "UnitAura")
  if type(fn) ~= "function" then
    return { present = false }
  end
  for i = 1, 40 do
    local values = { pcall(fn, "player", i, "HELPFUL") }
    if not values[1] or values[2] == nil then
      break
    end
    local id = values[11]
    if not isSecret(id) and id == SL.RESTED_AURA then
      return SL.AuraInfo({ applications = values[4], duration = values[6], expirationTime = values[7] }, isSecret)
    end
  end
  return { present = false }
end

-- The aura "Gut erholt" of the player as SleepBagLogic.AuraInfo describes it.
local function readAura()
  local api = rawget(_G, "C_UnitAuras")
  if type(api) ~= "table" then
    return readLegacyAura()
  end
  if type(api.GetPlayerAuraBySpellID) == "function" then
    local ok, aura = pcall(api.GetPlayerAuraBySpellID, SL.RESTED_AURA)
    return SL.AuraInfo(ok and aura or nil, isSecret)
  end
  if type(api.GetAuraDataByIndex) == "function" then
    for i = 1, 40 do
      local ok, aura = pcall(api.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok or aura == nil then
        break
      end
      local readOk, id = pcall(function()
        return aura.spellId
      end)
      if readOk and not isSecret(id) and id == SL.RESTED_AURA then
        return SL.AuraInfo(aura, isSecret)
      end
    end
  end
  return { present = false }
end

-- Start and end of the running cast or channel of the bag, the kind the event named first, then the other
-- one (the game says UnitCastingInfo for a cast and UnitChannelInfo for a channel).
local function castTimes(kind, now)
  local order = kind == "channel" and { "UnitChannelInfo", "UnitCastingInfo" }
    or { "UnitCastingInfo", "UnitChannelInfo" }
  for _, name in ipairs(order) do
    local fn = rawget(_G, name)
    if type(fn) == "function" then
      local values = { select(2, pcall(fn, "player")) }
      local start, stop = SL.CastTimes(values, name == "UnitCastingInfo" and 9 or 8, now, isSecret)
      if start then
        return start, stop
      end
    end
  end
end

-- Painting ---------------------------------------------------------------------------------------------------

local function frameDb()
  local frames = ns.db.frames
  if type(frames.sleepBag) ~= "table" then
    frames.sleepBag = {}
  end
  return frames.sleepBag
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function place(f)
  local db = frameDb()
  f:ClearAllPoints()
  local s = f:GetScale()
  if finite(db.x) and finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -280)
  end
end

local function savePosition(f)
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s, db = f:GetScale(), frameDb()
    db.x, db.y = left * s, top * s
  end
end

local function lookup(key)
  return L[key]
end

local function create()
  local f = CreateFrame("Frame", "FGSleepBag", UIParent)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  local r, g, b = U.hex(BG_HEX)
  f.bg:SetColorTexture(r, g, b, BG_ALPHA)
  f.border = W.Border(f, "white", 0.4)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(ICON, ICON)
  f.icon:SetPoint("LEFT", PAD, 0)
  f.icon:SetTexture(SL.ICON)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  f.text = W.Text(f, { role = "ui", color = "text" })
  f.text:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", PAD, -1)
  f.text:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD - CLOSE - 2, -1)
  f.text:SetHeight(18)

  f.status = CreateFrame("StatusBar", nil, f)
  f.status:SetMinMaxValues(0, 1)
  f.status:SetValue(0)
  f.status:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", PAD, 0)
  f.status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
  f.status:SetHeight(BAR_H)
  f.statusBack = f.status:CreateTexture(nil, "BACKGROUND")
  f.statusBack:SetAllPoints()
  f.statusBack:SetColorTexture(0, 0, 0, 0.45)
  f.fill = f.status:CreateTexture(nil, "ARTWORK")
  f.fill:SetColorTexture(U.hex(BAR_HEX))
  f.status:SetStatusBarTexture(f.fill)

  f.close = W.Action(f, { icon = "close", size = CLOSE, tooltip = "sleepbag.close" })
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  f.close:SetScript(
    "OnClick",
    ns.Wrap("sleepbag-close", function()
      dismissed = true
      f:Hide()
    end)
  )

  f:SetScript("OnDragStart", function()
    if not SB.Locked() then
      f:StartMoving()
    end
  end)
  f:SetScript(
    "OnDragStop",
    ns.Wrap("sleepbag-move", function()
      f:StopMovingOrSizing()
      savePosition(f)
    end)
  )
  f:SetScript("OnEnter", function(self)
    self.hover = true
    SB.ShowTip(self)
  end)
  f:SetScript("OnLeave", function(self)
    self.hover = nil
    W.Tooltip.Hide(self)
  end)
  f:Hide()
  return f
end

-- The tooltip of the bar: the rule of the stacks and the numbers of the run.
function SB.ShowTip(owner)
  W.Tooltip.Show(owner, {
    title = L["sleepbag.tip.title"],
    text = L["sleepbag.tip.rule"],
    lines = SL.TipLines(owner.snap, lookup),
    anchor = "ANCHOR_BOTTOM",
  })
end

-- Paints the display for the run at `now`; hides it when nothing runs. The text is the whole message, the bar
-- only repeats it (a text alternative for the bar is the same line, colors carry no information).
function SB.Paint()
  local snap = SL.Snapshot(state, nowSeconds(), (state.phase == "lying" or state.phase == "aura") and readAura() or nil)
  -- The bar belongs to the run: standing up with the aura still on shows nothing (a /reload brings that state back).
  if snap and snap.kind == "rested" then
    snap = nil
  end
  if not snap then
    dismissed = false
    if frame then
      frame:Hide()
    end
    return nil
  end
  if dismissed then
    return snap
  end
  frame = frame or create()
  local text = SL.Text(snap, lookup)
  if frame.shown ~= text then
    frame.shown = text
    frame.text:SetText(text)
  end
  frame.status:SetValue(snap.progress)
  frame.fgDescription = text
  frame.snap = snap
  if frame.hover then
    SB.ShowTip(frame)
  end
  if not frame:IsShown() then
    place(frame)
    frame:Show()
  end
  return snap
end

-- Events ---------------------------------------------------------------------------------------------------------

local function setEvents(on, list, unit)
  if not driver then
    return
  end
  for _, event in ipairs(list) do
    if on and unit and type(driver.RegisterUnitEvent) == "function" then
      pcall(driver.RegisterUnitEvent, driver, event, "player")
    elseif on then
      pcall(driver.RegisterEvent, driver, event)
    else
      pcall(driver.UnregisterEvent, driver, event)
    end
  end
end

local function stopTicking()
  if driver then
    driver:SetScript("OnUpdate", nil)
  end
end

local function startTicking()
  local acc = 0
  driver:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc >= SL.TICK then
      acc = 0
      ns.Safe("sleepbag-tick", SB.Tick)
    end
  end)
end

-- Run events and the timer follow the machine: on while a run is on, off otherwise.
local function syncRun()
  local on = SL.Running(state)
  if on ~= (runEvents == true) then
    runEvents = on
    setEvents(on, RUN_EVENTS)
    setEvents(on, { "UNIT_AURA" }, true)
    if on then
      startTicking()
    else
      stopTicking()
    end
  end
end

-- Keeps the saved run equal to the machine: written when it changes, removed when the run is over.
local function saveRun()
  local db = ns.charDB
  if not db then
    return
  end
  local rec = SL.Record(state, nowSeconds(), serverNow())
  local old = db.sleepBagRun
  if rec == nil then
    db.sleepBagRun = nil
  elseif
    type(old) ~= "table"
    or old.at ~= rec.at
    or old.stacks ~= rec.stacks
    or old.counted ~= rec.counted
    or old.hadAura ~= rec.hadAura
    or math.abs((old.stackAt or 0) - rec.stackAt) > 2
  then
    db.sleepBagRun = rec
  end
end

local function message(info)
  if not info or not SB.MessageOn() or info.reason == "idle" then
    return
  end
  local reason = info.reason
  local text
  if reason == "stood" then
    text = string.format(L["sleepbag.endedStood"], SL.Clock(info.elapsed) or "0:00")
  elseif reason == "early" then
    text = string.format(L["sleepbag.endedEarly"], SL.Clock(info.elapsed) or "0:00", SL.Clock(info.need, true) or "?")
  elseif reason == "noLie" then
    text = L["sleepbag.endedNoLie"]
  else
    text = L["sleepbag.endedAborted"]
  end
  if info.rested and info.stacks then
    text = text .. " " .. string.format(L["sleepbag.endedRested"], SL.StackLabel(info.stacks, info.counted))
  end
  ns.Notify(text, "info")
end

-- The result of a machine step: ended runs say goodbye, everything repaints and the events follow the phase.
local function settle(result, info)
  if result == "stacked" and info then
    ns.db.sleepBagTimes = state.measures
  end
  syncRun()
  saveRun()
  SB.Paint()
  if result == "ended" then
    message(info)
  end
end

local function plainId(value)
  return type(value) == "number" and not isSecret(value) and value or nil
end

local function onCast(event)
  local now = nowSeconds()
  if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
    local kind = event == "UNIT_SPELLCAST_START" and "cast" or "channel"
    local start, stop = castTimes(kind, now)
    return SL.Start(state, now, kind, start, stop, readAura())
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    return SL.Succeeded(state, now, resting(), readAura())
  elseif event == "UNIT_SPELLCAST_STOP" then
    return SL.Stopped(state, now)
  elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    return SL.ChannelStopped(state, now, resting())
  end
  return SL.Aborted(state, now)
end

local function onEvent(_, event, unit, _, spellId)
  local now = nowSeconds()
  local result, info
  if event == "UNIT_AURA" then
    if unit == "player" then
      result, info = SL.Aura(state, now, readAura())
    end
  elseif event == "PLAYER_UPDATE_RESTING" then
    local lies = resting()
    result, info = SL.Resting(state, now, lies, lies and readAura() or nil)
  elseif event == "PLAYER_REGEN_DISABLED" then
    result, info = SL.Combat(state, now)
  elseif event == "PLAYER_STARTED_MOVING" then
    result, info = SL.Moved(state, now)
  elseif event == "PLAYER_STOPPED_MOVING" then
    result, info = SL.Arrived(state)
  elseif unit == "player" and plainId(spellId) == SL.UNROLL_SPELL then
    result, info = onCast(event)
  else
    return
  end
  if result then
    settle(result, info)
  end
end

-- One step of the timer: stale runs end, the display repaints.
function SB.Tick()
  local reads = state.phase == "lying" or state.phase == "aura" or state.watch ~= nil
  local result, info = SL.Tick(state, nowSeconds(), reads and readAura() or nil)
  settle(result, info)
end

-- Settings ---------------------------------------------------------------------------------------------------------

function SB.Enabled()
  return ns.db ~= nil and ns.db.settings.sleepBag == true
end

function SB.MessageOn()
  return not ns.db or ns.db.settings.sleepBagMessage ~= false
end

function SB.Locked()
  return ns.db ~= nil and ns.db.settings.sleepBagLocked == true
end

-- Follows the setting: the cast events and the machine are on while the setting is on.
function SB.Apply()
  if not ns.db then
    return
  end
  driver = driver or CreateFrame("Frame")
  if not driver.fgScripted then
    driver.fgScripted = true
    driver:SetScript("OnEvent", ns.Wrap("sleepbag", onEvent))
  end
  local on = SB.Enabled()
  if on ~= (castEvents == true) then
    castEvents = on
    setEvents(on, CAST_EVENTS, true)
    setEvents(on, REST_EVENTS)
  end
  SL.Enable(state, on)
  if not on and ns.charDB then
    ns.charDB.sleepBagRun = nil
  end
  syncRun()
  SB.Paint()
end

-- Puts the run saved before a /reload back (see SleepBagLogic.Restore). `final` drops a record that does not
-- fit (the player does not lie, too old, no aura) so it never lingers.
function SB.Restore(final)
  local db = ns.charDB
  if not db or db.sleepBagRun == nil or not SB.Enabled() or SL.Running(state) then
    return false
  end
  local restored = SL.Restore(state, nowSeconds(), db.sleepBagRun, serverNow(), resting(), readAura())
  if restored then
    settle("restored")
  elseif final then
    db.sleepBagRun = nil
  end
  return restored
end

-- A standing aura with no run behind it (login, /reload, the setting turned on) is kept as the phase "aura" (internal
-- state, the bar stays hidden while standing).
function SB.Adopt()
  if not SB.Enabled() then
    return false
  end
  local result = SL.Adopt(state, nowSeconds(), readAura())
  if result then
    settle(result)
  end
  return result ~= nil
end

function SB.State()
  return state
end

function SB.Frame()
  return frame
end

-- The event frame (tests read what is registered and whether the timer runs).
function SB.Driver()
  return driver
end

ns.On("PLAYER_LOGIN", function()
  state.measures = SL.CleanMeasures(ns.db and ns.db.sleepBagTimes)
  SB.Apply()
end)
-- Restores a saved run, otherwise adopts a standing aura (only after the last try, a late resting flag may still
-- bring the run back).
local function restoreOrAdopt(final)
  if SB.Restore(final) then
    return
  end
  if final then
    SB.Adopt()
  end
end

ns.On("PLAYER_ENTERING_WORLD", function()
  if SB.Restore(false) then
    return
  end
  local after = rawget(_G, "C_Timer") and C_Timer.After
  if type(after) ~= "function" or not (ns.charDB and ns.charDB.sleepBagRun ~= nil) then
    restoreOrAdopt(true)
    return
  end
  for i, delay in ipairs(RESTORE_DELAYS) do
    after(delay, function()
      ns.Safe("sleepbag-restore", restoreOrAdopt, i == #RESTORE_DELAYS)
    end)
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.sleepBag") then
    SB.Apply()
    if not (ns.charDB and ns.charDB.sleepBagRun ~= nil) then
      SB.Adopt()
    end
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    savePosition(frame)
  end
end)
