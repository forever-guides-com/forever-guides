-- The fishing helper at work: reads the game through Game.lua, asks the pure rules what to do (Conditions,
-- BindMachine, DoubleClick, Loans, Trustee, LootLogic) and carries it out. Nothing happens unless the player
-- switched an option on. Everything that is protected or can change a setting happens outside of combat,
-- in combat the wish waits and runs when the fight ends. A call the game blocks (ADDON_ACTION_BLOCKED)
-- switches the helper off and says so on the status line, it never fails silently.
local ADDON_NAME, fish = ...
if not fish.FG then
  return
end

local FG = fish.FG
local Options, Conditions, Trustee = fish.Options, fish.Conditions, fish.Trustee
local BindMachine, DoubleClick, Loans = fish.BindMachine, fish.DoubleClick, fish.Loans
local Recast = fish.Recast
local Blockade, Status, LootLogic = fish.Blockade, fish.Status, fish.LootLogic
local MarkLogic, Mark = fish.MarkLogic, fish.Mark

local C = {}
fish.Controller = C

-- The binding the player sets, the secure button and the two frames that own the override bindings.
C.BINDING = "FOREVERGUIDES_FISHING_CAST"
C.BUTTON = "ForeverGuidesFishingCastButton"
C.KEY_OWNER = "ForeverGuidesFishingKeys"
C.MOUSE_OWNER = "ForeverGuidesFishingMouse"
C.MOUSE_KEY = "BUTTON2"
-- Seconds between two looks at the situation while the key option is on.
C.INTERVAL = 0.25
-- A mouse binding that was never released (the button up got lost) is dropped after this time.
C.WATCHDOG = 2

local db, trustee, detector, watch, recast, keyWatcher, lastStopAt, lastStartAt, lastLootAt, pressAt, pressPos, firstPos
-- The options while the saved data is not there (the start did not run yet): a switch the player flips
-- is kept here and written into the saved data at the start, so a click is never lost.
local memory, touched = Options.Clean(nil), {}
local keyOwner, mouseOwner, button
local keyMachine, mouseMachine
local state = { channeling = false, allowed = false, reason = "spell", keys = {}, started = false }
local blocked
local loansSignature, mouseArmed, buttonSpell, recovered
-- True while the mouse binding rests on "cast" because a throw after the reel in is offered.
local restBound, armedWatched
local applyRest, look
local eventFrame
local acc = 0
-- The session was ended with C.Stop: nothing starts it again until C.Reset.
local stopped = false

local function game()
  return fish.Game
end

-- Options -------------------------------------------------------------------------------------------------------------

-- Starts the helper on the saved data of the game when nothing started it yet (a client that does not
-- tell the add-on its own ADDON_LOADED). Only after the files ran, never before the game filled the
-- saved variables. Returns true when the helper runs.
function C.Bootstrap()
  if state.started then
    return true
  end
  if stopped or not fish.ready then
    return false
  end
  local saved = rawget(_G, "ForeverGuidesFishingDB")
  _G.ForeverGuidesFishingDB = type(saved) == "table" and saved or {}
  FG.Safe("fishing start", C.Start, _G.ForeverGuidesFishingDB)
  return state.started
end

-- The saved variables table of the helper (the journal view stores its window there).
function C.Saved()
  if not db then
    C.Bootstrap()
  end
  return db
end

function C.Options()
  if not db then
    C.Bootstrap()
  end
  return db and db.options or memory
end

-- Stores one option (cleaned) and applies it. Returns the stored value, nil for an unknown option. A
-- switch always takes the click: without saved data the value waits in memory, in combat the bindings
-- follow when the fight ends (the machines hold the wish until then).
function C.Set(id, value)
  if not db then
    C.Bootstrap()
  end
  local clean = Options.CleanValue(id, value)
  if clean == nil then
    return nil
  end
  if not db then
    memory[id], touched[id] = clean, true
    FG.Emit("FG_FISHING_CHANGED", id, clean)
    return clean
  end
  db.options[id] = clean
  if id == "recast" or id == "recastInvert" or id == "oneKey" or id == "doubleClick" then
    if recast and not Options.RecastOn(db.options) then
      recast:Cancel()
    end
    -- The keys that carry the binding depend on these switches: write them again.
    if keyMachine then
      keyMachine:Forget()
    end
  end
  C.SyncEvents()
  C.Refresh()
  FG.Emit("FG_FISHING_CHANGED", id, clean)
  return clean
end

-- Status ----------------------------------------------------------------------------------------------------------------

-- The situation as the status line needs it. With fresh the facts are read again.
function C.Snapshot(fresh, diagnosis, keyPress)
  if not db then
    C.Bootstrap()
  end
  if fresh and db and not blocked then
    if diagnosis then
      game().ForgetSpell()
    end
    C.Look()
  end
  local options = C.Options()
  local spell = game().Detection()
  return {
    spell = spell,
    searched = spell and spell.searched or {},
    diagnosis = diagnosis == true,
    keyPress = keyPress == true,
    blocked = blocked,
    anyOn = Options.AnyOn(options),
    oneKey = options.oneKey == true,
    keys = #state.keys,
    allowed = state.allowed,
    reason = state.reason,
    channeling = state.channeling,
  }
end

-- The status lines as text; with diagnosis the line of the spell search comes last ("/fg angeln status").
function C.StatusText(diagnosis)
  return Status.Text(FG.L, C.Snapshot(true, diagnosis == true))
end

-- The text for a press of the key while no binding of the helper is in place.
function C.KeyText()
  return Status.Text(FG.L, C.Snapshot(true, false, true))
end

local function signature()
  local snap = C.Snapshot(false)
  return table.concat({
    tostring(snap.allowed),
    tostring(snap.reason),
    tostring(snap.keys),
    tostring(snap.blocked and snap.blocked.func),
    tostring(snap.anyOn),
  }, "|")
end

local lastSignature
local function announce()
  local now = signature()
  if now ~= lastSignature then
    lastSignature = now
    FG.Emit("FG_FISHING_STATUS")
  end
end

-- A blocked call ----------------------------------------------------------------------------------------------------

-- Switches the helper off for good (until the player tries again) and tells them why.
local function trip(func)
  blocked = { func = func, time = game().Epoch() }
  if db then
    db.blocked = { func = blocked.func, time = blocked.time }
  end
  for _, machine in ipairs({ keyMachine, mouseMachine }) do
    if machine then
      machine:Disable("blocked")
      machine:Forget()
    end
  end
  -- Give back what is on loan and drop the bindings, as far as the game still lets us.
  pcall(function()
    if keyOwner then
      game().Write(keyOwner, "off", {}, C.BUTTON)
    end
    if mouseOwner then
      game().Write(mouseOwner, "off", {}, C.BUTTON)
    end
    if trustee then
      trustee:Release()
    end
    Mark.Hide()
  end)
  mouseArmed, restBound = nil, nil
  if recast then
    recast:Cancel()
  end
  C.SyncEvents()
  local text = Status.Format(FG.L, { key = "fishing.status.blocked", func = func })
  FG.Errors.add({ msg = text, kind = "warning", ctx = "fishing" })
  FG.Notify(text, "warning")
  announce()
end

-- The result of a machine's Want: a failed write counts like a blocked call.
local function judge(result, err, func)
  if result == "failed" then
    FG.Log.warn("fishing: %s failed: %s", func, tostring(err))
    trip(func)
  end
end

-- The player wants to try again after a blocked call.
function C.Retry()
  blocked = nil
  if db then
    db.blocked = nil
  end
  if watch then
    watch:Reset()
  end
  for _, machine in ipairs({ keyMachine, mouseMachine }) do
    if machine then
      machine:Forget()
      machine:Enable()
    end
  end
  loansSignature = nil
  lastSignature = nil
  game().ForgetSpell()
  C.SyncEvents()
  C.Refresh()
  announce()
end

-- Looking at the game -----------------------------------------------------------------------------------------------

-- The spell of the secure button follows the fishing spell the character knows. Never in combat.
local function syncButton()
  if not button or game().InCombat() then
    return
  end
  local id = game().KnownSpell()
  local spell = id and (game().SpellName(id) or id) or nil
  if spell ~= buttonSpell then
    if game().SetSpell(button, spell) then
      buttonSpell = spell
    end
  end
end

-- Reads the game: facts, conditions, keys, the line.
function C.Look()
  local g = game()
  local facts = g.Facts()
  state.facts = facts
  state.allowed, state.reason = Conditions.Evaluate(facts, { mountedOk = false })
  state.keys = g.Keys(C.BINDING)
  return state
end

local function wantedMode()
  local options = C.Options()
  local mode = BindMachine.Desired({
    enabled = options.oneKey == true,
    keys = #state.keys,
    allowed = state.allowed,
    channeling = state.channeling,
  })
  -- A throw after the reel in waits for the loot: the key does not throw before it is offered.
  if mode == "cast" and recast and recast:Holding() then
    return "off"
  end
  -- An open loot window takes the press for itself: a throw would close it before the loot is taken.
  if mode ~= "off" and game().LootOpen() then
    return "off"
  end
  -- A second press right after a throw would cut the fresh line short.
  if mode ~= "off" and recast and recast:CastGuarded() then
    return "off"
  end
  return mode
end

local MODIFIERS = { "SHIFT-", "CTRL-", "ALT-" }

-- The keys of the binding. With the throw after the reel in on, the key counts with Shift, Ctrl or Alt held
-- too, so the game does the same for both whether or not it tells a held modifier from the plain key.
local function bindingKeys()
  local keys = state.keys
  if not (Options.RecastOn(C.Options()) and C.Options().oneKey == true) then
    return keys
  end
  local out = {}
  for _, key in ipairs(keys) do
    out[#out + 1] = key
  end
  for _, key in ipairs(keys) do
    if not key:find("%-.") then
      for _, prefix in ipairs(MODIFIERS) do
        out[#out + 1] = prefix .. key
      end
    end
  end
  return out
end

-- The key the game reports for a press, without modifiers: the keys of the binding are compared this way.
local function baseKey(key)
  return (tostring(key):gsub("^.*%-(.+)$", "%1"))
end

-- True when the mouse binding should rest on "cast": a throw after a double click is offered now.
local function wantsRestCast()
  local options = C.Options()
  if blocked or not recast or options.doubleClick ~= true or not recast:Armed("mouse") then
    return false
  end
  return (Conditions.Evaluate(game().Facts(), { mountedOk = options.doubleClickMounted == true }))
end

local function applyLoans()
  if not trustee then
    return
  end
  local wanted = Loans.Wanted(C.Options(), state.channeling and not blocked)
  local parts = {}
  for name, value in pairs(wanted) do
    parts[#parts + 1] = name .. "=" .. value
  end
  table.sort(parts)
  local now = table.concat(parts, ";")
  if now == loansSignature or game().InCombat() then
    return
  end
  loansSignature = now
  local result = trustee:Borrow(wanted)
  for name, value in pairs(result.capped) do
    FG.Log.info("fishing: %s is held at %s by the client", name, value)
  end
  for _, name in ipairs(result.failed) do
    FG.Log.warn("fishing: could not write %s", name)
  end
end

-- Shows or hides the own icon at the bobber. force hangs it on the plate anew (the soft target changed).
local function applyMark(force)
  local options = C.Options()
  Mark.Update(MarkLogic.Wanted(options, state.channeling, blocked ~= nil), options.markOffset, force)
end

-- Brings the bindings and the borrowed settings in line with the situation.
function C.Refresh()
  if not state.started then
    return
  end
  if blocked then
    Mark.Hide()
    announce()
    return
  end
  if recast then
    recast:Tick()
    -- The offer ends by itself: look again when its time is up.
    if recast:Armed() and not armedWatched then
      FG.Log.info("fishing: recast armed: pause over and loot taken")
      look(Recast.ARM_TIMEOUT)
    end
    armedWatched = recast:Armed()
  end
  C.Look()
  local g = game()
  if not g.InCombat() then
    syncButton()
  end
  local mode = wantedMode()
  local result, err = keyMachine:Want(mode)
  judge(result, err, "SetOverrideBinding")
  if not blocked then
    applyRest(false)
    applyLoans()
    applyMark()
  end
  announce()
end

-- The line goes out or comes in.
local function setChanneling(on)
  if state.channeling == on then
    return
  end
  state.channeling = on
  loansSignature = nil
  C.Refresh()
end

-- Events ------------------------------------------------------------------------------------------------------------------

local ALWAYS = {
  "PLAYER_LOGIN",
  "PLAYER_LOGOUT",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_CHANNEL_STOP",
  "ADDON_ACTION_BLOCKED",
}
local FOR_KEY = {
  "UPDATE_BINDINGS",
  "PLAYER_EQUIPMENT_CHANGED",
  "SPELLS_CHANGED",
  "PLAYER_MOUNT_DISPLAY_CHANGED",
  "PLAYER_CONTROL_LOST",
  "PLAYER_CONTROL_GAINED",
}
local FOR_CLICK = { "GLOBAL_MOUSE_DOWN", "GLOBAL_MOUSE_UP" }
-- The own icon at the bobber follows the soft target and its name plate.
local FOR_MARK = { "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }
local LOOT_OPENED, LOOT_CLOSED, LOOT_CONFIRM = { "LOOT_OPENED" }, { "LOOT_CLOSED" }, { "LOOT_BIND_CONFIRM" }

local registered = {}

local function setRegistered(list, on)
  for _, event in ipairs(list) do
    if on and not registered[event] then
      registered[event] = pcall(eventFrame.RegisterEvent, eventFrame, event) or nil
    elseif not on and registered[event] then
      pcall(eventFrame.UnregisterEvent, eventFrame, event)
      registered[event] = nil
    end
  end
end

-- Listens only to what the switched-on options need. A blocked helper only listens for the combat
-- end and the blocked calls.
function C.SyncEvents()
  if not eventFrame then
    return
  end
  local options = C.Options()
  local live = not blocked
  setRegistered(ALWAYS, true)
  setRegistered(FOR_KEY, live and (options.oneKey or options.doubleClick or options.improveSound or options.hideNames))
  setRegistered(FOR_CLICK, live and options.doubleClick)
  local recasting = live and Options.RecastOn(options)
  setRegistered(FOR_MARK, live and Options.MarkOn(options))
  setRegistered(LOOT_OPENED, live and (options.autoLoot or recasting))
  setRegistered(LOOT_CLOSED, recasting)
  setRegistered(LOOT_CONFIRM, live and options.autoLoot)
  -- The press of the key is only listened to for the throw after the reel in.
  if keyWatcher then
    game().WatchKeys(keyWatcher, recasting and options.oneKey == true)
  end
  local poll = live and options.oneKey
  eventFrame:SetScript("OnUpdate", poll and C.OnUpdate or nil)
end

function C.OnUpdate(_, elapsed)
  acc = acc + (elapsed or 0)
  if acc < C.INTERVAL then
    return
  end
  acc = 0
  if not game().InCombat() then
    C.Refresh()
  end
end

-- The double click -----------------------------------------------------------------------------------------------------

-- Puts the mouse binding where it belongs when no click is in flight: on "cast" while a throw after the
-- reel in is offered, else off. force writes even when nothing was bound before.
function applyRest(force)
  if blocked or not mouseMachine or mouseArmed then
    return
  end
  local wanted = wantsRestCast()
  if not force and not wanted and not restBound then
    return
  end
  if wanted then
    syncButton()
  end
  restBound = wanted
  local result, err = mouseMachine:Want(wanted and "cast" or "off")
  judge(result, err, "SetOverrideBinding")
end

-- Hands the right mouse button back to the game.
local function releaseMouse()
  mouseArmed = nil
  applyRest(true)
end

-- Looks at the clock again after a while (the throw is offered when the pause is over, the offer ends after
-- its time). Without a timer the next event or the poll does it.
function look(delay)
  game().After(delay + 0.05, function()
    if state.started and not blocked then
      FG.Safe("fishing recast", C.Refresh)
    end
  end)
end

local function modifierHeld()
  return FG.Keys ~= nil and FG.Keys.Current ~= nil and FG.Keys.Current() ~= "none"
end

-- The click that throws a line that was offered after the reel in.
local function onOfferedClick(g)
  if g.InCombat() or g.MouseDown("LeftButton") or g.LootOpen() or not g.OverWorld() then
    if g.LootOpen() then
      FG.Log.info("fishing: recast blocked: loot window open")
    end
    return
  end
  if not recast:Consume() then
    FG.Log.info("fishing: recast blocked: %s", tostring(recast:Why() or recast:State()))
    return
  end
  FG.Log.info("fishing: recast fired: plain click after loot")
  detector:Cast()
  mouseArmed = "cast"
  -- The binding stays until the button comes up: the throw is the click itself.
  g.After(C.WATCHDOG, function()
    if mouseArmed == "cast" then
      releaseMouse()
    end
  end)
end

local function onMouseDown(buttonName)
  local options = C.Options()
  if options.doubleClick == true and not blocked and buttonName == "LeftButton" then
    -- Another button in between ends a begun pair.
    detector:Reset()
  end
  if options.doubleClick ~= true or blocked or buttonName ~= "RightButton" then
    return
  end
  local g = game()
  pressAt, pressPos = g.Now(), g.CursorPosition()
  if recast:Tick() == "armed" and restBound then
    onOfferedClick(g)
    return
  end
  if g.InCombat() or g.MouseDown("LeftButton") or g.LootOpen() or not g.OverWorld() then
    if not g.OverWorld() then
      FG.Log.info("fishing: click ignored: not on the world")
    end
    detector:Reset()
    return
  end
  local doubled, firstAt = detector:Click()
  if not doubled then
    firstPos = pressPos
    return
  end
  if DoubleClick.TooFar(firstPos, pressPos) then
    -- Two clicks in different places are no pair: this one starts a new pair.
    FG.Log.info("fishing: click ignored: pair too far apart")
    detector:Click()
    firstPos = pressPos
    return
  end
  local channeling = state.channeling or g.Channeling()
  local action, again = DoubleClick.Action(channeling, options, modifierHeld())
  if action == "cast" and lastStopAt and firstAt and lastStopAt >= firstAt then
    -- The first click reeled in natively and the loot is on its way: this click must not throw over it.
    FG.Log.info("fishing: double click blocked: the first click reeled in, waiting for the loot")
    if DoubleClick.WantsRecast(options, modifierHeld()) and recast:Request("mouse", lastStopAt) then
      FG.Log.info("fishing: recast armed: wish kept after the double click")
      look(C.Options().recastPause)
    end
    return
  end
  if action == "cast" and recast:Holding() then
    FG.Log.info("fishing: double click blocked: recast %s", tostring(recast:Why()))
    if DoubleClick.WantsRecast(options, modifierHeld()) then
      recast:Request("mouse")
    end
    return
  end
  if action == "cast" then
    local facts = g.Facts()
    if not Conditions.Evaluate(facts, { mountedOk = options.doubleClickMounted == true }) then
      return
    end
    syncButton()
  end
  local result, err = mouseMachine:Want(action)
  judge(result, err, "SetOverrideBinding")
  if result == "applied" then
    mouseArmed = action
    restBound = false
    if action == "cast" then
      detector:Cast()
    elseif again then
      -- The line is reeled in now, the throw comes with the next click after the loot.
      recast:Request("mouse")
      FG.Log.info("fishing: recast armed: wish kept after the double click")
    elseif action == "reel" and Options.RecastOn(options) then
      recast:Reeling()
    end
    -- The release of the button normally ends it, this catches a release that never arrives.
    g.After(C.WATCHDOG, function()
      if mouseArmed == action then
        releaseMouse()
      end
    end)
  end
end

-- The release decides whether the press was a click or the camera. A first click that was none ends the
-- pair. The second click already acted at its press, only the binding is given back (its action can not
-- be taken back, so a long second click that already threw stays thrown).
local function onMouseUp(buttonName)
  if buttonName ~= "RightButton" then
    return
  end
  if pressAt and C.Options().doubleClick == true then
    local g = game()
    local ok, why = DoubleClick.JudgeClick(g.Now() - pressAt, pressPos, g.CursorPosition())
    if not ok then
      FG.Log.info("fishing: click ignored: %s", why)
      if not mouseArmed then
        detector:Reset()
      end
    end
  end
  pressAt = nil
  if mouseArmed then
    releaseMouse()
  end
end

-- What a press of the key does right now: idle throws, channel interacts (reel in), loot window, guard and
-- the pause do nothing. The line names the state and the seconds since the last events, to be read in the game.
local function keyState()
  local g = game()
  if g.LootOpen() then
    return "loot", "none"
  end
  if recast:CastGuarded() or recast:Holding() then
    return "guard", "none"
  end
  if state.channeling then
    return "channel", "interact"
  end
  return "idle", state.allowed and "cast" or "none"
end

local function since(t)
  return t and string.format("%+.2fs", game().Now() - t) or "-"
end

local function logKeyState()
  local st, action = keyState()
  FG.Log.info(
    "fishing: key state=%s action=%s t=%s since channel stop, %s since cast, %s since loot open",
    st, action, since(lastStopAt), since(lastStartAt), since(lastLootAt)
  )
end

-- The press of a key while the throw after the reel in is on. The press itself does its work through the
-- override binding (reel in while the line is out, throw otherwise), this only keeps the wish.
function C.OnKey(key)
  local options = C.Options()
  if blocked or not state.started or options.oneKey ~= true or not Options.RecastOn(options) then
    return
  end
  if game().InCombat() then
    return
  end
  local base = baseKey(key)
  local ours = false
  for _, bound in ipairs(state.keys) do
    if baseKey(bound) == base then
      ours = true
    end
  end
  if not ours then
    return
  end
  logKeyState()
  if state.channeling and recast:CastGuarded() then
    FG.Log.info("fishing: key press blocked: cast guard")
  elseif state.channeling then
    FG.Log.info("fishing: key press: reel in")
    if DoubleClick.WantsRecast(options, modifierHeld()) then
      recast:Request("key")
    else
      recast:Reeling()
    end
  elseif recast:Consume() then
    FG.Log.info("fishing: key press fired: recast after pause and loot")
    C.Refresh()
  elseif recast:Holding() then
    -- The binding rests on "off" while held, so this press changes nothing in the game.
    FG.Log.info("fishing: key press blocked: %s", tostring(recast:Why()))
    if DoubleClick.WantsRecast(options, modifierHeld()) then
      recast:Request("key")
    end
  end
end

-- Loot ----------------------------------------------------------------------------------------------------------------------

local function onLoot()
  local g = game()
  lastLootAt = g.Now()
  if recast then
    recast:LootOpened()
  end
  if not LootLogic.Wanted(C.Options(), g.IsFishingLoot()) then
    return
  end
  for _, slot in ipairs(LootLogic.Order(g.LootCount())) do
    g.LootSlot(slot)
  end
end

local function onBindConfirm(slot)
  local flavor = FG.Client and FG.Client.Flavor and FG.Client.Flavor() or "unknown"
  if LootLogic.NeedsBindConfirm(flavor) and C.Options().autoLoot == true and game().IsFishingLoot() then
    game().ConfirmLoot(slot)
  end
end

-- Session ---------------------------------------------------------------------------------------------------------------------

-- Puts back what a session left on loan when it ended in the middle of a cast.
local function recover()
  if recovered or not trustee or not db then
    return
  end
  recovered = true
  local result, counts = trustee:Recover(db.ledger)
  if result == "recovered" and counts then
    FG.Log.info("fishing: gave back %d settings after the last session", counts.restored)
  end
end

local function logout()
  if blocked then
    return
  end
  pcall(function()
    Mark.Hide()
    if keyOwner and not game().InCombat() then
      game().Write(keyOwner, "off", {}, C.BUTTON)
    end
    if trustee then
      trustee:Release()
    end
  end)
end

local function combatStarted()
  keyMachine:CombatStarted()
  mouseMachine:CombatStarted()
  mouseArmed, restBound = nil, false
  recast:CombatStarted()
  detector:Reset()
end

local function combatEnded()
  if blocked then
    return
  end
  recast:CombatEnded()
  applyRest(true)
  loansSignature = nil
  C.SyncEvents()
  C.Refresh()
end

-- One entry for every event, also what the tests call.
function C.OnEvent(event, ...)
  if not state.started then
    return
  end
  if event == "ADDON_ACTION_BLOCKED" then
    local addon, func = ...
    if watch:Note(addon, func) and not blocked then
      trip(watch:Info().func)
    end
  elseif blocked then
    if event == "PLAYER_REGEN_ENABLED" then
      announce()
    end
  elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
    local unit, _, spellId = ...
    if unit == "player" then
      local g = game()
      local fishing = g.IsFishingSpell(spellId) or g.Channeling()
      if fishing then
        g.Learn(spellId)
      end
      if fishing then
        recast:ChannelStarted()
        lastStartAt = game().Now()
        FG.Log.info("fishing: cast guard: %.1f s", Recast.CAST_GUARD)
        look(Recast.CAST_GUARD)
      end
      setChanneling(fishing)
    end
  elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    if (...) == "player" then
      lastStopAt = game().Now()
      recast:ChannelStopped()
      if recast:Holding() then
        look(math.max(C.Options().recastPause, Recast.LOOT_GRACE))
      end
      setChanneling(false)
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    combatStarted()
  elseif event == "PLAYER_REGEN_ENABLED" then
    combatEnded()
  elseif event == "GLOBAL_MOUSE_DOWN" then
    onMouseDown((...))
  elseif event == "GLOBAL_MOUSE_UP" then
    onMouseUp((...))
  elseif event == "LOOT_OPENED" then
    onLoot()
    C.Refresh()
  elseif event == "LOOT_CLOSED" then
    recast:LootClosed()
    C.Refresh()
  elseif event == "LOOT_BIND_CONFIRM" then
    onBindConfirm((...))
  elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
    applyMark(true)
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    applyMark()
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    -- The client hands a plate on to the next unit: let go of it, the next look hangs the icon anew.
    Mark.Hide()
    applyMark()
  elseif event == "SPELLS_CHANGED" then
    game().ForgetSpell()
    C.Refresh()
  elseif event == "PLAYER_LOGOUT" then
    logout()
  elseif event == "PLAYER_LOGIN" then
    C.Refresh()
  else
    C.Refresh()
  end
end

-- Starts the helper with its SavedVariables (a table). Safe to call once per session.
function C.Start(saved)
  stopped = false
  db = type(saved) == "table" and saved or {}
  db.version = 1
  -- The default of the pause went from 1.0 to 0.3 s: stored old defaults move once.
  if not db.recastPauseMoved then
    db.recastPauseMoved = true
    if type(db.options) == "table" and db.options.recastPause == 1 then
      db.options.recastPause = 0.3
    end
  end
  db.options = Options.Clean(db.options)
  for id in pairs(touched) do
    db.options[id] = memory[id]
  end
  touched = {}
  local g = game()
  -- The spell ids this character was seen to fish with (the saved data belongs to the account).
  local charKey = g.CharKey()
  db.learned = type(db.learned) == "table" and db.learned or {}
  g.SetLearned(charKey and db.learned[charKey] or nil)
  g.OnLearn = function(ids)
    local key = g.CharKey()
    if key and db then
      db.learned[key] = ids
    end
  end
  trustee = Trustee.New({
    get = function(name)
      return game().GetCvar(name)
    end,
    set = function(name, value)
      return game().SetCvar(name, value)
    end,
    now = function()
      return game().Epoch()
    end,
    save = function(snapshot)
      db.ledger = snapshot
    end,
  })
  watch = Blockade.New({ ADDON_NAME })
  detector = DoubleClick.New({
    clock = g.Now,
    window = function()
      return C.Options().doubleClickTime
    end,
  })
  recast = Recast.New({
    clock = g.Now,
    pause = function()
      return C.Options().recastPause
    end,
  })
  armedWatched, restBound = false, false
  keyWatcher = g.NewKeyWatcher(function(key)
    FG.Safe("fishing:key", C.OnKey, key)
  end)
  keyOwner = g.NewOwner(C.KEY_OWNER)
  mouseOwner = g.NewOwner(C.MOUSE_OWNER)
  button = g.NewCastButton(C.BUTTON)
  keyMachine = BindMachine.New({
    inCombat = function()
      return game().InCombat()
    end,
    apply = function(mode)
      return game().Write(keyOwner, mode, bindingKeys(), C.BUTTON)
    end,
  })
  mouseMachine = BindMachine.New({
    inCombat = function()
      return game().InCombat()
    end,
    apply = function(mode)
      return game().Write(mouseOwner, mode, { C.MOUSE_KEY }, C.BUTTON)
    end,
  })
  state.started = true
  if type(db.blocked) == "table" and type(db.blocked.func) == "string" then
    blocked = { func = db.blocked.func, time = db.blocked.time }
    keyMachine:Disable("blocked")
    mouseMachine:Disable("blocked")
  elseif not (keyOwner and mouseOwner and button) then
    trip("CreateFrame")
  end
  eventFrame = eventFrame or CreateFrame("Frame")
  eventFrame:SetScript("OnEvent", function(_, event, ...)
    FG.Safe("fishing:" .. event, C.OnEvent, event, ...)
  end)
  C.SyncEvents()
  -- Before anything can write the ledger: the settings of the game exist when an add-on loads.
  recover()
  C.Refresh()
  -- The catch journal listens on its own, a blocked call of the helper does not stop it.
  if fish.Recorder then
    fish.Recorder.Start(db, C.Options)
  end
end

-- The session ended: tests start a new one.
function C.Stop()
  state.started = false
  if keyWatcher then
    game().WatchKeys(keyWatcher, false)
  end
  if fish.Recorder then
    fish.Recorder.Stop()
  end
  Mark.Hide()
  stopped = true
  db = nil
  recovered, blocked, loansSignature, lastSignature, mouseArmed = nil, nil, nil, nil, nil
  if eventFrame then
    setRegistered(ALWAYS, false)
    setRegistered(FOR_KEY, false)
    setRegistered(FOR_CLICK, false)
    setRegistered(FOR_MARK, false)
    setRegistered(LOOT_OPENED, false)
    setRegistered(LOOT_CLOSED, false)
    setRegistered(LOOT_CONFIRM, false)
    eventFrame:SetScript("OnUpdate", nil)
  end
end

-- Back to the state before the first start (tests): a later touch of a switch starts the helper again.
function C.Reset()
  C.Stop()
  stopped = false
  memory, touched = Options.Clean(nil), {}
end

-- What the tests look at.
function C.Parts()
  return {
    trustee = trustee,
    keyMachine = keyMachine,
    mouseMachine = mouseMachine,
    detector = detector,
    recast = recast,
    keyWatcher = keyWatcher,
    watch = watch,
    keyOwner = keyOwner,
    mouseOwner = mouseOwner,
    button = button,
    state = state,
    frame = eventFrame,
  }
end

-- Start when the add-on's own variables are there: at its ADDON_LOADED, else at the login, else when the
-- player first touches a switch (C.Bootstrap). The client of this build does not always deliver the first.
local starter = CreateFrame("Frame")
starter:RegisterEvent("ADDON_LOADED")
starter:RegisterEvent("PLAYER_LOGIN")
starter:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" then
    if name ~= ADDON_NAME then
      return
    end
    self:UnregisterEvent("ADDON_LOADED")
  else
    self:UnregisterEvent("PLAYER_LOGIN")
  end
  FG.Safe("fishing start", C.Bootstrap)
end)
