-- Error catcher: records Lua errors of every addon and of Blizzard code in the shared list
-- (ns.Errors) and, if switched on, tells the player once per new error (chat line, sound). The global error
-- handler is only chained, never replaced for good or locked: the previous handler runs
-- after our recording, so other error displays and the default error frame keep working.
local _, ns = ...
local Logic, L = ns.ErrorCatcherLogic, ns.L

ns.AddLocale("enUS", {
  ["errcatch.heading"] = "Error catcher",
  ["errcatch.enable"] = "Catch Lua errors",
  ["errcatch.chat"] = "Message in chat",
  ["errcatch.sound"] = "Sound",
  ["errcatch.foreign"] = "Include other addons",
  ["errcatch.hideBlizzard"] = "Hide Blizzard error window",
  ["errcatch.hideHint"] = "Only while the catcher is on. The errors are in the error list.",
  ["errcatch.hint"] = "Errors are collected silently. Chat and sound announce each new error once. Off for other addons: only Forever Guides errors are listed.",
  ["errcatch.openList"] = "Open error list",
  ["errcatch.chat.error"] = "Error in %s: %s",
  ["errcatch.chat.blocked"] = "Blocked action in %s: %s",
  ["errcatch.chat.forbidden"] = "Forbidden action in %s: %s",
  ["errcatch.chat.warning"] = "Warning in %s: %s",
  ["errcatch.chatLink"] = "[List]",
  ["errcatch.chatHint"] = "(/fg errors)",
  ["errcatch.kind.error"] = "Error",
  ["errcatch.kind.blocked"] = "Blocked",
  ["errcatch.kind.forbidden"] = "Forbidden",
  ["errcatch.kind.warning"] = "Warning",
  ["errcatch.detail.count"] = "%d time(s)",
  ["errcatch.detail.times"] = "First: %s | Last: %s | Session: %s",
  ["errcatch.session.now"] = "this start",
  ["errcatch.session.ago.one"] = "1 start ago",
  ["errcatch.session.ago.other"] = "%d starts ago",
  ["errcatch.script"] = "Script",
})
ns.AddLocale("deDE", {
  ["errcatch.heading"] = "Fehlerfänger",
  ["errcatch.enable"] = "Lua-Fehler abfangen",
  ["errcatch.chat"] = "Meldung im Chat",
  ["errcatch.sound"] = "Ton",
  ["errcatch.foreign"] = "Fremde Addons einbeziehen",
  ["errcatch.hideBlizzard"] = "Blizzard-Fehlerfenster ausblenden",
  ["errcatch.hideHint"] = "Nur bei aktivem Fehlerfänger. Die Fehler stehen in der Fehlerliste.",
  ["errcatch.hint"] = "Fehler werden still gesammelt. Chat und Ton melden jeden neuen Fehler einmal. Aus bei fremden Addons: nur Fehler von Forever Guides stehen in der Liste.",
  ["errcatch.openList"] = "Fehlerliste öffnen",
  ["errcatch.chat.error"] = "Fehler in %s: %s",
  ["errcatch.chat.blocked"] = "Blockierte Aktion in %s: %s",
  ["errcatch.chat.forbidden"] = "Verbotene Aktion in %s: %s",
  ["errcatch.chat.warning"] = "Warnung in %s: %s",
  ["errcatch.chatLink"] = "[Liste]",
  ["errcatch.chatHint"] = "(/fg fehler)",
  ["errcatch.kind.error"] = "Fehler",
  ["errcatch.kind.blocked"] = "Blockiert",
  ["errcatch.kind.forbidden"] = "Verboten",
  ["errcatch.kind.warning"] = "Warnung",
  ["errcatch.detail.count"] = "%dx",
  ["errcatch.detail.times"] = "Erstes: %s | Letztes: %s | Sitzung: %s",
  ["errcatch.session.now"] = "dieser Start",
  ["errcatch.session.ago.one"] = "vor 1 Start",
  ["errcatch.session.ago.other"] = "vor %d Starts",
  ["errcatch.script"] = "Skript",
})

local EC = {}
ns.ErrorCatcher = EC

local LINK = "addon:fgerr:open"
-- Quiet sounds, first one the client knows wins.
local SOUNDS = { "IG_QUEST_FAILED", "ALARM_CLOCK_WARNING_2", "IG_QUEST_LOG_ABANDON_QUEST" }

local flood = Logic.NewFlood()
local dedupe = Logic.NewDedupe()
local chatGate = Logic.NewGate()
local soundGate = Logic.NewGate()
local busy = false
local current
local bugGrabber
local worldDone = false

EC.flood = flood
EC.linkReady = false

-- Only an explicit false switches a setting off.
local function flag(key)
  local settings = ns.db and ns.db.settings
  return not settings or settings[key] ~= false
end

function EC.Enabled()
  return flag("errorCatcher")
end

local function clock()
  return type(GetTime) == "function" and GetTime() or 0
end

-- Recording ------------------------------------------------------------------------------

-- source tells the handler chain from the error callback of another addon so one error seen by both is
-- counted once. Returns the entry or nil when the error is not recorded.
function EC.Capture(kind, msg, stack, addon, source)
  if not EC.Enabled() then
    return nil
  end
  msg = tostring(msg == nil and "" or msg)
  local now = clock()
  if dedupe:isDuplicate(msg, source, now) or not flood:allow(now) then
    return nil
  end
  stack = Logic.CleanStack(stack)
  addon = addon or Logic.AddonOf(msg, stack)
  if not Logic.IsOwn(addon) and not flag("errorForeign") then
    return nil
  end
  return (ns.Errors.add({ msg = msg, kind = kind, addon = addon, stack = stack, ctx = addon }))
end

local function currentStack()
  if type(debugstack) ~= "function" then
    return ""
  end
  local ok, stack = pcall(debugstack)
  return ok and stack or ""
end

local function onError(msg)
  EC.Capture("error", msg, currentStack(), nil, "handler")
end

-- Puts our wrapper in front of the current handler. Safe to call again: nothing happens
-- while the wrapper is already the active handler.
function EC.Install()
  if not EC.Enabled() or type(geterrorhandler) ~= "function" or type(seterrorhandler) ~= "function" then
    return false
  end
  local okGet, prev = pcall(geterrorhandler)
  if not okGet then
    return false
  end
  if prev == current then
    return true
  end
  if type(prev) ~= "function" then
    prev = function() end
  end
  local handler
  handler = function(msg, ...)
    if busy then
      return prev(msg, ...)
    end
    -- busy also covers prev: a wrapper of ours further down the chain stays quiet.
    busy = true
    pcall(onError, msg)
    local ok, a, b = pcall(prev, msg, ...)
    busy = false
    if not ok then
      error(a, 0)
    end
    return a, b
  end
  pcall(seterrorhandler, handler)
  local okNow, now = pcall(geterrorhandler)
  if okNow and now == handler then
    current = handler
    return true
  end
  return false
end

-- Listens to the error callback of another addon without touching its state. Its handler is locked, so errors reach
-- it after our wrapper or not at all when it was installed last.
function EC.HookBugGrabber()
  if bugGrabber then
    return true
  end
  local bg = rawget(_G, "BugGrabber") or rawget(_G, "!BugGrabber")
  if type(bg) ~= "table" or type(bg.RegisterCallback) ~= "function" then
    return false
  end
  local ok = pcall(bg.RegisterCallback, EC, "BugGrabber_BugGrabbed", function(...)
    EC.OnBugGrabbed(...)
  end)
  if ok then
    bugGrabber = bg
  end
  return ok
end

function EC.OnBugGrabbed(...)
  local obj
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "table" then
      obj = v
      break
    end
  end
  if not obj and bugGrabber and type(bugGrabber.GetDB) == "function" then
    local ok, db = pcall(bugGrabber.GetDB, bugGrabber)
    obj = ok and type(db) == "table" and db[#db] or nil
  end
  if type(obj) == "table" and obj.message ~= nil then
    pcall(EC.Capture, "error", obj.message, obj.stack, nil, "bugger")
  end
end

local RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }

local function gameFlag(name)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then
    return false
  end
  local ok, value = pcall(fn)
  return ok and value == true
end

-- The game state a blocked call happened in.
local function gameState()
  local state = { combat = gameFlag("InCombatLockdown"), group = gameFlag("IsInGroup"), restricted = {} }
  local inInstance = rawget(_G, "IsInInstance")
  if type(inInstance) == "function" then
    local ok, value = pcall(inInstance)
    state.instance = ok and value == true
  end
  for _, name in ipairs(RESTRICTIONS) do
    if ns.AddonRestricted(name) then
      state.restricted[#state.restricted + 1] = name
    end
  end
  return state
end

-- State line and the short Lua stack of the moment. The client raises the blocked-action event inside the
-- blocked call and does not always name the function, so the stack is the only trace of the code path.
function EC.ActionStack()
  local raw = ""
  if type(debugstack) == "function" then
    local ok, text = pcall(debugstack, 1, 20, 0)
    raw = ok and text or ""
  end
  local stack = Logic.ActionStack(raw)
  local head = Logic.StateLine(gameState())
  return stack ~= "" and head .. "\n" .. stack or head
end

local function onAction(kind, text)
  return function(_, addon, func)
    if addon == nil or addon == "" then
      addon = "?"
    end
    local okStack, stack = pcall(EC.ActionStack)
    pcall(EC.Capture, kind, text .. tostring(func), okStack and stack or "", tostring(addon), "event")
  end
end
ns.On("ADDON_ACTION_BLOCKED", onAction("blocked", "Blocked call to protected function "))
ns.On("ADDON_ACTION_FORBIDDEN", onAction("forbidden", "Forbidden call to protected function "))
ns.On("LUA_WARNING", function(_, _, text)
  pcall(EC.Capture, "warning", text, "", nil, "event")
end)

-- Notification ---------------------------------------------------------------------------

local function playSound()
  local kit = rawget(_G, "SOUNDKIT")
  if type(kit) ~= "table" or type(PlaySound) ~= "function" then
    return
  end
  for _, name in ipairs(SOUNDS) do
    if kit[name] then
      pcall(PlaySound, kit[name], "SFX")
      return
    end
  end
end

function EC.ChatLine(e)
  local kind = Logic.Kind(e)
  local addon = Logic.AddonLabel(Logic.Addon(e), L):gsub("|", "||")
  local text = string.format(L["errcatch.chat." .. kind] or L["errcatch.chat.error"], addon, Logic.ChatMessage(e.msg))
  if EC.linkReady then
    return string.format("%s |cff71d5ff|H%s|h%s|h|r", text, LINK, L["errcatch.chatLink"])
  end
  return text .. " " .. L["errcatch.chatHint"]
end

-- Once per new error; chat and sound each at most every few seconds. Never opens a window.
function EC.Notify(e)
  if not EC.Enabled() or e.kind == "warning" then
    return
  end
  local now = clock()
  if flag("errorChat") and chatGate:take(now) then
    ns.Notify.chat(EC.ChatLine(e))
  end
  if flag("errorSound") and soundGate:take(now) then
    playSound()
  end
end
ns.On("FG_ERROR_NEW", function(_, e)
  pcall(EC.Notify, e)
end)

function EC.OnLink(link)
  if link == LINK and ns.Main then
    ns.Main.Show("errors")
  end
end
-- Must load before NoteLink in the toc: test doubles keep only the last SetItemRef hook.
if type(hooksecurefunc) == "function" then
  EC.linkReady = pcall(hooksecurefunc, "SetItemRef", ns.Wrap("errcatch-click", EC.OnLink))
end

-- Blizzard's error window ----------------------------------------------------------------

-- Hidden through the scriptErrors CVar (nothing of Blizzard's is replaced, the error handler
-- chain is untouched, so other error displays still get every error). What the CVar was is kept
-- in the SavedVariables (meta, which survives the per-version error reset).
local CVAR = "scriptErrors"

local function cvarGet()
  local get = (C_CVar and C_CVar.GetCVar) or GetCVar
  if type(get) ~= "function" then
    return nil
  end
  local ok, value = pcall(get, CVAR)
  return ok and value ~= nil and tostring(value) or nil
end

local function cvarSet(value)
  local set = (C_CVar and C_CVar.SetCVar) or SetCVar
  if type(set) == "function" then
    pcall(set, CVAR, value)
  end
end

function EC.HidesBlizzardWindow()
  return EC.Enabled() and flag("errorHideBlizzard")
end

-- Safety net for any other way the window opens: it is closed right after it shows.
function EC.HookBlizzardWindow()
  if EC.windowHooked or type(hooksecurefunc) ~= "function" then
    return
  end
  local frame = rawget(_G, "ScriptErrorsFrame")
  if type(frame) ~= "table" then
    return
  end
  local function hide()
    if EC.HidesBlizzardWindow() and frame:IsShown() then
      pcall(frame.Hide, frame)
    end
  end
  for _, name in ipairs({ "Show", "DisplayMessageInternal" }) do
    if type(frame[name]) == "function" and pcall(hooksecurefunc, frame, name, hide) then
      EC.windowHooked = true
    end
  end
end

-- Call after login and whenever the catcher or the option changes. A value the player set
-- since we changed the CVar is never overwritten.
function EC.ApplyBlizzardWindow()
  local meta = ns.db and ns.db.meta
  if not meta then
    return
  end
  local value = cvarGet()
  if EC.HidesBlizzardWindow() then
    if value ~= nil and value ~= "0" then
      meta.prevScriptErrors = value
      cvarSet("0")
    end
    EC.HookBlizzardWindow()
  elseif meta.prevScriptErrors ~= nil then
    if value == "0" then
      cvarSet(meta.prevScriptErrors)
    end
    meta.prevScriptErrors = nil
  end
end

ns.On("PLAYER_LOGIN", function()
  EC.Install()
  EC.HookBugGrabber()
  EC.ApplyBlizzardWindow()
end)
-- A second try after loading, for addons that replaced the handler late. Later loading
-- screens do not repeat it.
ns.On("PLAYER_ENTERING_WORLD", function()
  if worldDone then
    return
  end
  worldDone = true
  EC.Install()
  EC.HookBugGrabber()
  EC.ApplyBlizzardWindow()
end)

function EC.Report()
  return string.format(
    "error catcher: on=%s handler=%s collector=%s floodDropped=%d repeatsDropped=%d",
    tostring(EC.Enabled()),
    tostring(current ~= nil),
    tostring(bugGrabber ~= nil),
    flood.dropped,
    ns.Errors.dropped
  )
end

-- Settings section ------------------------------------------------------------------------

function EC.AddSettings(view)
  local W, Store = ns.W, ns.Store
  local s = view.stack
  ns.AddHeading(view, "errcatch.heading")
  for _, def in ipairs({
    { "errorCatcher", "errcatch.enable", "errors-enable" },
    { "errorChat", "errcatch.chat", "errors-chat" },
    { "errorSound", "errcatch.sound", "errors-sound" },
    { "errorForeign", "errcatch.foreign", "errors-foreign" },
    { "errorHideBlizzard", "errcatch.hideBlizzard", "errors-hide" },
  }) do
    local key = def[1]
    local toggle = W.Toggle(view.content, {
      key = def[2],
      get = function()
        return flag(key)
      end,
      set = function(v)
        Store.set("settings." .. key, v)
        if key == "errorCatcher" and v then
          EC.Install()
        end
        if key == "errorCatcher" or key == "errorHideBlizzard" then
          EC.ApplyBlizzardWindow()
        end
      end,
    })
    toggle.fgId = def[3]
    s:Add(toggle, { height = 24, gap = 6 })
  end
  ns.AddParagraph(view, "errcatch.hint", { role = "micro", color = "textMuted" })
  ns.AddParagraph(view, "errcatch.hideHint", { role = "micro", color = "textMuted" })
  s:Add(
    W.Action(view.content, {
      label = "act.open",
      icon = "open",
      tooltip = "errcatch.openList",
      width = 220,
      onClick = function()
        ns.Main.Show("errors")
      end,
    }),
    { height = 26, width = 220 }
  )
end
