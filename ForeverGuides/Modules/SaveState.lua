-- What is not on disk yet, and the one safe way to put it there. The client writes SavedVariables only at
-- logout or reload, so a crash loses everything since the last one. This module counts the changes that
-- matter (ns.SaveState.MarkDirty), decides when a reminder may show (SaveStateLogic) and reloads the
-- interface, but only from a click: Reload() refuses unless it runs inside a handler wrapped with
-- ns.SaveState.Click. Click reloads are allowed on Forever (confirmed in the client: C_UI.Reload and
-- ReloadUI both start the reload from a button click), timers and events never reload. The footer button
-- and the reminder bar are in UI/SaveUI.lua.
--
-- Tracked: price scans and passive price updates, the shopping list and route options
-- (FG_PROFROUTE_CHANGED), characters (FG_ROSTER_CHANGED), notes, drawings, waypoints, settings
-- (account and character scope) and the inventory snapshots (version counter, polled when asked).
-- Not tracked: macros, seen players, calculator history, window positions and sizes, tutorials, and
-- anything written without one of these messages.
local ADDON_NAME, ns = ...
local SL, U = ns.SaveStateLogic, ns.U

local S = {}
ns.SaveState = S

ns.AddLocale("enUS", {
  ["save.button"] = "Save",
  ["save.tipTitle"] = "Save",
  ["save.tip"] = "Saves your Forever Guides data (characters, inventory, prices, shopping list, settings) to disk. The game only writes saved data when you log out or reload the interface, so a crash can lose everything since then. This reloads the interface (a short loading screen), your windows and settings stay.",
  ["save.tipDirty"] = "Unsaved changes: %s (%s)",
  ["save.tipClean"] = "Nothing unsaved",
  ["save.tipCombat"] = "Not available during combat.",
  ["save.tipRestricted"] = "The game blocked the reload before. Type /reload yourself.",
  ["save.tipUnsupported"] = "This game version has no reload function for add-ons. Type /reload yourself.",
  ["save.minutes.none"] = "less than a minute",
  ["save.minutes.one"] = "1 minute",
  ["save.minutes.other"] = "%d minutes",
  ["save.reason.prices"] = "price scan",
  ["save.reason.list"] = "shopping list",
  ["save.reason.roster"] = "characters",
  ["save.reason.inventory"] = "inventory",
  ["save.reason.notes"] = "notes",
  ["save.reason.drawings"] = "drawings",
  ["save.reason.waypoints"] = "waypoints",
  ["save.reason.settings"] = "settings",
  ["save.confirmTitle"] = "Reload the interface?",
  ["save.confirm.scan"] = "A price scan is running and stops. The screen goes black for a few seconds.",
  ["save.confirm.merchant"] = "A vendor window is open, the Sell helper may be in use. The screen goes black for a few seconds.",
  ["save.confirm.instance"] = "You are in an instance. The screen goes black for a few seconds.",
  ["save.confirm.group"] = "You are in a group. The screen goes black for a few seconds while the others keep playing.",
  ["save.blockedTitle"] = "Reload blocked",
  ["save.blockedHint"] = "The game blocked the reload. Type /reload in the chat yourself, the command is ready to copy.",
  ["save.combatNotice"] = "Not available during combat. Try again afterwards.",
  ["save.hint"] = "Unsaved data: %s. Reload now?",
  ["save.hintType"] = "Unsaved data: %s. Type /reload to save.",
  ["save.hintNow"] = "Reload now",
  ["save.hintLater"] = "Later",
  ["save.set.heading"] = "Saving",
  ["save.set.intro"] = "The game writes your saved data only when you log out or reload the interface.",
  ["save.set.hint"] = "Remind me to save after scans",
  ["save.set.hintTip"] = "Shows a small reminder with a reload button after a price scan and at calm moments while data is unsaved. At most every 30 minutes.",
})
ns.AddLocale("deDE", {
  ["save.button"] = "Speichern",
  ["save.tipTitle"] = "Speichern",
  ["save.tip"] = "Speichert deine Forever-Guides-Daten (Charaktere, Bestand, Preise, Einkaufsliste, Einstellungen) auf der Festplatte. Das Spiel schreibt gespeicherte Daten nur beim Ausloggen oder beim Neuladen der Oberfläche, bei einem Absturz kann also alles seit dem letzten Mal verloren gehen. Dafür wird die Oberfläche neu geladen (kurzer Ladebildschirm), deine Fenster und Einstellungen bleiben erhalten.",
  ["save.tipDirty"] = "Ungesicherte Änderungen: %s (%s)",
  ["save.tipClean"] = "Nichts ungesichert",
  ["save.tipCombat"] = "Im Kampf nicht verfügbar.",
  ["save.tipRestricted"] = "Das Spiel hat das Neuladen schon einmal blockiert. Tippe selbst /reload.",
  ["save.tipUnsupported"] = "Diese Spielversion bietet Addons keine Neuladen-Funktion. Tippe selbst /reload.",
  ["save.minutes.none"] = "weniger als eine Minute",
  ["save.minutes.one"] = "1 Minute",
  ["save.minutes.other"] = "%d Minuten",
  ["save.reason.prices"] = "Preisscan",
  ["save.reason.list"] = "Einkaufsliste",
  ["save.reason.roster"] = "Charaktere",
  ["save.reason.inventory"] = "Bestand",
  ["save.reason.notes"] = "Notizen",
  ["save.reason.drawings"] = "Zeichnungen",
  ["save.reason.waypoints"] = "Wegpunkte",
  ["save.reason.settings"] = "Einstellungen",
  ["save.confirmTitle"] = "Oberfläche neu laden?",
  ["save.confirm.scan"] = "Ein Preisscan läuft und wird abgebrochen. Der Bildschirm wird für ein paar Sekunden schwarz.",
  ["save.confirm.merchant"] = "Ein Händlerfenster ist offen, der Verkaufshelfer ist vielleicht in Benutzung. Der Bildschirm wird für ein paar Sekunden schwarz.",
  ["save.confirm.instance"] = "Du bist in einer Instanz. Der Bildschirm wird für ein paar Sekunden schwarz.",
  ["save.confirm.group"] = "Du bist in einer Gruppe. Der Bildschirm wird für ein paar Sekunden schwarz, die anderen spielen weiter.",
  ["save.blockedTitle"] = "Neuladen blockiert",
  ["save.blockedHint"] = "Das Spiel hat das Neuladen blockiert. Tippe selbst /reload in den Chat, der Befehl steht zum Kopieren bereit.",
  ["save.combatNotice"] = "Im Kampf nicht verfügbar. Versuche es danach noch einmal.",
  ["save.hint"] = "Ungesicherte Daten: %s. Jetzt neu laden?",
  ["save.hintType"] = "Ungesicherte Daten: %s. Tippe /reload zum Speichern.",
  ["save.hintNow"] = "Jetzt neu laden",
  ["save.hintLater"] = "Später",
  ["save.set.heading"] = "Speichern",
  ["save.set.intro"] = "Das Spiel schreibt gespeicherte Daten nur beim Ausloggen oder Neuladen der Oberfläche.",
  ["save.set.hint"] = "Nach Scans ans Speichern erinnern",
  ["save.set.hintTip"] = "Zeigt nach einem Preisscan und in ruhigen Momenten eine kleine Erinnerung mit Neuladen-Knopf, solange Daten ungesichert sind. Höchstens alle 30 Minuten.",
})

-- Seconds after the login in which changes are not counted: the add-on reads the game state then.
local SETTLE_SECONDS = 20
-- Reminder reasons the tooltip names at most.
local TIP_REASONS = 3

local st = SL.New()
S.state = st
local settling = false
local restricted = false
local clickDepth = 0
local attempt = nil
local invBaseline = 0
local priceCount = 0
local merchantOpen = false

-- Server time in seconds; tests replace it.
function S.clock()
  local get = rawget(_G, "GetServerTime")
  if type(get) == "function" then
    local ok, t = pcall(get)
    if ok and type(t) == "number" then
      return t
    end
  end
  return U.now()
end

local function after(seconds, fn)
  local timer = rawget(_G, "C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After(seconds, fn)
  else
    fn()
  end
end

local function call(name)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then
    return false
  end
  local ok, value = pcall(fn)
  return ok and value or false
end

local function inCombat()
  return call("InCombatLockdown") == true
end

local function changed()
  ns.Emit("FG_SAVESTATE_CHANGED")
end

-- Dirty bookkeeping ----------------------------------------------------------------------------

local function inventoryVersion()
  local inv = rawget(ns, "Inventory")
  return type(inv) == "table" and tonumber(inv.version) or nil
end

-- Counts the inventory snapshots taken since the last look (the module has a version counter and no event).
local function pollInventory()
  local v = inventoryVersion()
  if not v or v <= invBaseline then
    return
  end
  local delta = v - invBaseline
  invBaseline = v
  if not settling then
    S.MarkDirty("inventory", math.min(5, delta))
  end
end

-- One unsaved change. reason: a key of SaveStateLogic.WEIGHTS or any short word, weight: optional.
function S.MarkDirty(reason, weight)
  if settling then
    return false
  end
  local was = SL.IsDirty(st)
  if not SL.Mark(st, reason, weight, S.clock()) then
    return false
  end
  if not was then
    changed()
  end
  return true
end

-- { since, reasons (set), minutes, weight, list (reasons, heaviest first) }; since is nil when all is saved.
function S.Dirty()
  pollInventory()
  local reasons = {}
  for reason in pairs(st.reasons) do
    reasons[reason] = true
  end
  return {
    since = st.since,
    reasons = reasons,
    minutes = SL.Minutes(st, S.clock()),
    weight = st.weight,
    list = SL.ReasonList(st),
  }
end

-- All on disk: a fresh load (the write was the logout or reload before it) or the logout itself.
function S.Clear()
  SL.Clear(st)
  invBaseline = inventoryVersion() or 0
  changed()
end

function S.Restricted()
  return restricted
end

-- Reload ----------------------------------------------------------------------------------------

local function reloadFunction()
  local ui = rawget(_G, "C_UI")
  if type(ui) == "table" and type(ui.Reload) == "function" then
    return ui.Reload, "C_UI.Reload"
  end
  local legacy = rawget(_G, "ReloadUI")
  if type(legacy) == "function" then
    return legacy, "ReloadUI"
  end
end

-- true, or false and why: "unsupported" (no reload function), "restricted" (the client refused an
-- earlier attempt in this session), "combat".
function S.CanReload()
  if not reloadFunction() then
    return false, "unsupported"
  end
  if restricted then
    return false, "restricted"
  end
  if inCombat() then
    return false, "combat"
  end
  return true
end

-- Wraps a click handler: Reload() only works inside one, because the client lets a reload through only for
-- a real click or key press, never for a timer or an event.
function S.Click(fn)
  return function(...)
    clickDepth = clickDepth + 1
    local ok = ns.Safe("save-click", fn, ...)
    clickDepth = clickDepth - 1
    return ok
  end
end

local function onRefused(_, addon, func)
  local a = attempt
  local ours = addon == nil or addon == "" or addon == ADDON_NAME
  if not (a and ours and SL.IsReloadCall(func)) then
    return
  end
  a.blocked = true
  a.event = tostring(addon) .. " " .. tostring(func)
  restricted = true
  S.last = a
  changed()
end
ns.On("ADDON_ACTION_FORBIDDEN", onRefused)
ns.On("ADDON_ACTION_BLOCKED", onRefused)

-- Reloads the interface. Returns true when the call went out and the client did not refuse it, else false
-- and why: "noclick" (not inside S.Click: the API is not called), "unsupported", "restricted", "combat",
-- "blocked" (the client raised a blocked-action event for the reload, named or not) or "error" (the call
-- raised, the message is the third result). The refusal events are watched while the call runs and for a
-- second after. A click reload is allowed on Forever: both C_UI.Reload and ReloadUI started the reload from
-- a button click, so a refusal here is a state of the client (group, restriction), not a missing right.
function S.Reload()
  if clickDepth == 0 then
    return false, "noclick"
  end
  local ok, why = S.CanReload()
  if not ok then
    return false, why
  end
  local fn, api = reloadFunction()
  local a = { api = api, at = S.clock() }
  attempt = a
  S.last = a
  local called, err = pcall(fn)
  a.ok, a.err = called, not called and tostring(err) or nil
  local blocked = a.blocked
  after(SL.ATTEMPT_SECONDS, function()
    if attempt == a then
      attempt = nil
    end
  end)
  if not called then
    return false, "error", a.err
  end
  if blocked then
    return false, "blocked"
  end
  return true
end

local function scanActive()
  local prices = rawget(ns, "PriceDb")
  if type(prices) ~= "table" or type(prices.ScanState) ~= "function" then
    return false
  end
  local ok, scan = pcall(prices.ScanState)
  return ok and type(scan) == "table" and SL.ScanActive(scan.phase) or false
end

-- The first reason the reload should ask before it runs, nil when it can go ahead. A running scan, an
-- open vendor window (the Sell helper works there), an instance and a group each want a confirmation.
function S.ConfirmReason()
  return SL.ConfirmReason({
    scanning = scanActive(),
    merchant = merchantOpen,
    instance = call("IsInInstance") == true,
    group = call("IsInGroup") == true,
  })
end

-- Texts ----------------------------------------------------------------------------------------

function S.MinutesText(minutes)
  local form, n = SL.MinutesForm(minutes)
  return string.format(ns.L["save.minutes." .. form], n)
end

-- The reasons as words, the heaviest first, at most TIP_REASONS.
function S.ReasonText(list)
  local words = {}
  for i = 1, math.min(#list, TIP_REASONS) do
    words[i] = ns.L["save.reason." .. list[i]] or list[i]
  end
  return table.concat(words, ", ")
end

-- The state line of the tooltip: unsaved changes with time and reasons, or "Nothing unsaved".
function S.StateText()
  local d = S.Dirty()
  if not d.since then
    return ns.L["save.tipClean"]
  end
  return string.format(ns.L["save.tipDirty"], S.MinutesText(d.minutes), S.ReasonText(d.list))
end

-- Reminder -------------------------------------------------------------------------------------

local function hintEnabled()
  local settings = ns.db and ns.db.settings
  return not (settings and settings.saveHint == false)
end

-- Shows the reminder when the rules allow it. trigger: "scan" or "pause". Returns true, or false and why.
function S.Evaluate(trigger)
  pollInventory()
  local now = S.clock()
  local ok, why = SL.Decide(st, {
    enabled = hintEnabled(),
    combat = inCombat(),
    restricted = ns.AddonRestricted("Combat", "Encounter", "ChallengeMode", "PvPMatch"),
    scanning = scanActive(),
    trigger = trigger,
  }, now)
  if not ok then
    return false, why
  end
  local ui = rawget(ns, "SaveUI")
  if not (ui and ui.ShowHint and ui.ShowHint()) then
    return false, "noui"
  end
  SL.Shown(st, now)
  return true, why
end

-- "Later": no reminder for SNOOZE_SECONDS.
function S.Snooze()
  SL.Snooze(st, S.clock())
end

-- Events ---------------------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
  S.Clear()
  settling = true
  after(SETTLE_SECONDS, function()
    settling = false
    invBaseline = inventoryVersion() or 0
  end)
end)
ns.On("PLAYER_LOGOUT", S.Clear)

ns.On("FG_PRICES_SCAN", function(_, phase)
  if phase == "done" then
    S.MarkDirty("prices", SL.SCAN_WEIGHT)
    S.Evaluate("scan")
  end
end)
ns.On("FG_PRICES_UPDATED", function()
  local prices = rawget(ns, "PriceDb")
  local count = 0
  if type(prices) == "table" and type(prices.Count) == "function" then
    local ok, n = pcall(prices.Count)
    count = ok and tonumber(n) or 0
  end
  local delta = count - priceCount
  priceCount = count
  S.MarkDirty("prices", SL.PriceWeight(delta))
end)
ns.On("FG_PROFROUTE_CHANGED", function()
  S.MarkDirty("list")
end)
ns.On("FG_ROSTER_CHANGED", function()
  S.MarkDirty("roster")
end)
ns.On("FG_NOTES_CHANGED", function()
  S.MarkDirty("notes")
end)
ns.On("FG_DRAWINGS_CHANGED", function()
  S.MarkDirty("drawings")
end)
ns.On("FG_WAYPOINTS_CHANGED", function()
  S.MarkDirty("waypoints")
end)
ns.On("FG_SETTING_CHANGED", function(_, path, _, scope)
  if scope == "char" or (type(path) == "string" and path:sub(1, 9) == "settings.") then
    S.MarkDirty("settings")
  end
end)

ns.On("MERCHANT_SHOW", function()
  merchantOpen = true
end)
ns.On("MERCHANT_CLOSED", function()
  merchantOpen = false
end)

-- Natural pauses: a window of the auction house or a bank closed, the end of a fight.
local PAUSE_INTERACTIONS = { 21 }
do
  local enum = rawget(_G, "Enum")
  local types = type(enum) == "table" and enum.PlayerInteractionType
  if type(types) == "table" then
    for _, name in ipairs({ "Auctioneer", "Banker", "GuildBanker" }) do
      if type(types[name]) == "number" then
        PAUSE_INTERACTIONS[#PAUSE_INTERACTIONS + 1] = types[name]
      end
    end
  end
end

local function pause()
  S.Evaluate("pause")
end
ns.On("AUCTION_HOUSE_CLOSED", pause)
ns.On("BANKFRAME_CLOSED", pause)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
  for _, known in ipairs(PAUSE_INTERACTIONS) do
    if kind == known then
      pause()
      return
    end
  end
end)
ns.On("PLAYER_REGEN_ENABLED", pause)

-- Settings card ---------------------------------------------------------------------------------

function S.AddSettings(view)
  ns.AddHeading(view, "save.set.heading")
  ns.AddParagraph(view, "save.set.intro", { role = "micro", color = "textMuted" })
  view.stack:Add(
    ns.W.Toggle(view.content, {
      key = "save.set.hint",
      tooltip = "save.set.hint",
      tooltipText = "save.set.hintTip",
      get = function()
        return hintEnabled()
      end,
      set = function(on)
        ns.Store.set("settings.saveHint", on and true or false)
      end,
    }),
    { height = 24, gap = 6 }
  )
end

ns.SettingsPage.Add(S.AddSettings, "general")
