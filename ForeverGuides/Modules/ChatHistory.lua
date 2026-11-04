-- Chat history on the native chat windows: records the chat events into the history buffers
-- (ChatHistoryRecord), puts the history back into the windows after login (ChatHistoryFormat) and
-- answers /fg chatverlauf. The decisions live in the pure modules; this file only reads the game.
-- Restored lines go straight into the window with AddMessage, never through a chat event, so no
-- other addon and not the recorder takes them for new messages.
local _, ns = ...
local L, U = ns.L, ns.U
local Logic, Rec, Route, Format, PN =
  ns.ChatHistoryLogic, ns.ChatHistoryRecord, ns.ChatHistoryRoute, ns.ChatHistoryFormat, ns.PlayerName

local CH = {}
ns.ChatHistory = CH

ns.AddLocale("enUS", {
  ["chathistory.menu"] = "Chat history",
  ["chathistory.state.on"] = "on",
  ["chathistory.state.disabled"] = "off",
  ["chathistory.state.conflict"] = "off, other chat addon loaded: %s",
  ["chathistory.state.errors"] = "stopped after errors",
  ["chathistory.windows"] = "Window lines: %s",
  ["chathistory.windowsNone"] = "none",
  ["chathistory.windowEntry"] = "%s: %d",
  ["chathistory.whispers"] = "Whisper conversations: %d, lines: %d",
  ["chathistory.size"] = "Size: about %d KB of %d KB (%s)",
  ["chathistory.level.ok"] = "ok",
  ["chathistory.level.warn"] = "almost full",
  ["chathistory.level.over"] = "over the limit",
  ["chathistory.clear.title"] = "Delete chat history",
  ["chathistory.clear.text"] = "Delete the whole chat history? This covers all windows of this character and all whisper conversations of the account. Contacts stay.",
  ["chathistory.cleared"] = "Chat history deleted: %d window lines, %d whisper lines",
})
ns.AddLocale("deDE", {
  ["chathistory.menu"] = "Chat-Verlauf",
  ["chathistory.state.on"] = "an",
  ["chathistory.state.disabled"] = "aus",
  ["chathistory.state.conflict"] = "aus, anderes Chat-Addon geladen: %s",
  ["chathistory.state.errors"] = "nach Fehlern gestoppt",
  ["chathistory.windows"] = "Fensterzeilen: %s",
  ["chathistory.windowsNone"] = "keine",
  ["chathistory.windowEntry"] = "%s: %d",
  ["chathistory.whispers"] = "Flüster-Gespräche: %d, Zeilen: %d",
  ["chathistory.size"] = "Größe: etwa %d KB von %d KB (%s)",
  ["chathistory.level.ok"] = "ok",
  ["chathistory.level.warn"] = "fast voll",
  ["chathistory.level.over"] = "Limit überschritten",
  ["chathistory.clear.title"] = "Chat-Verlauf löschen",
  ["chathistory.clear.text"] = "Den gesamten Chat-Verlauf löschen? Das betrifft alle Fenster dieses Charakters und alle Flüster-Gespräche des Accounts. Kontakte bleiben erhalten.",
  ["chathistory.cleared"] = "Chat-Verlauf gelöscht: %d Fensterzeilen, %d Flüsterzeilen",
})

local DEFAULT_WINDOW_COUNT = 10
local RESTORE_TRIES = 3
local RESTORE_RETRY_SECONDS = 1

local state = Rec.NewState()

-- Game access ------------------------------------------------------------------------------------

local function addOnLoaded(name)
  local addons = rawget(_G, "C_AddOns")
  local fn = type(addons) == "table" and addons.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
  if type(fn) ~= "function" then
    return false
  end
  local ok, loaded = pcall(fn, name)
  return ok and loaded and true or false
end

local function realmName()
  for _, name in ipairs({ "GetNormalizedRealmName", "GetRealmName" }) do
    local fn = rawget(_G, name)
    if type(fn) == "function" then
      local ok, realm = pcall(fn)
      if ok and type(realm) == "string" and realm ~= "" then
        return realm
      end
    end
  end
  return nil
end

-- Own character as "Name-Realm" (a name that is not known yet gives "").
local function ownName(realm)
  local name = PN.Self()
  return name ~= "" and PN.ForWhisper(name, nil, realm) or ""
end

local function frameName(index)
  return "ChatFrame" .. index
end

local function chatFrame(index)
  local frame = rawget(_G, frameName(index))
  return type(frame) == "table" and type(frame.AddMessage) == "function" and frame or nil
end

local function windowCount()
  return tonumber(rawget(_G, "NUM_CHAT_WINDOWS")) or DEFAULT_WINDOW_COUNT
end

-- The combat log and temporary windows (whisper tabs) take no history.
local function isExcluded(frame)
  return frame == rawget(_G, "COMBATLOG") or frame.isTemporary == true
end

-- A window that is shown or docked gets messages; a closed one does not.
local function isActive(frame)
  if frame.isDocked then
    return true
  end
  return type(frame.IsShown) == "function" and frame:IsShown() and true or false
end

-- Descriptions of the chat windows for ChatHistoryRoute. The tables are reused, one message costs no
-- new table per window.
local descriptions = {}
local function describeWindows()
  local count = 0
  for index = 1, windowCount() do
    local frame = chatFrame(index)
    if frame then
      count = count + 1
      local window = descriptions[count] or {}
      descriptions[count] = window
      window.id = index
      window.name = type(frame.name) == "string" and frame.name or ""
      window.active = isActive(frame)
      window.excluded = isExcluded(frame)
      window.messageTypes = frame.messageTypeList
      window.channelList = frame.channelList
      window.zoneChannelList = frame.zoneChannelList
    end
  end
  for index = #descriptions, count + 1, -1 do
    descriptions[index] = nil
  end
  return descriptions
end

-- Context of the recorder; one table whose fields are refreshed per call.
local context = {
  state = state,
  conflicts = {},
  own = "",
  windows = describeWindows,
  safe = function(value)
    return ns.AutoGuard.Safe(value)
  end,
}

-- The messenger (ForeverGuides_Chat) saves the whispers itself while it runs; the recorder then leaves them out,
-- or every line would be stored twice.
function CH.SetMessengerStore(on)
  context.messengerStore = on == true
end

local function refreshContext()
  local db, charDB = ns.db, ns.charDB
  context.settings = db and db.settings and db.settings.chat or nil
  context.whisperHistory = db and db.chatWhispers or nil
  context.windowHistory = charDB and charDB.chatWindows or nil
  context.groups = rawget(_G, "ChatTypeGroupInverted")
  if context.own == "" then
    context.homeRealm = realmName()
    context.own = ownName(context.homeRealm)
  end
  return context
end

-- Recording ---------------------------------------------------------------------------------------

local function record(event, text, sender, _, _, _, _, zoneChannelId, _, channelName)
  Rec.Handle(refreshContext(), event, U.now(), text, sender, channelName, zoneChannelId)
end

local function onChat(event, ...)
  if not ns.Safe("chathistory", record, event, ...) then
    Rec.NoteError(state)
  end
end

for _, event in ipairs(Route.ORDER) do
  ns.On(event, onChat)
end

-- Restoring ---------------------------------------------------------------------------------------

-- Puts the stored lines back into the windows that still exist. Returns the number of lines written,
-- or nil while the chat windows are not built yet.
function CH.Restore()
  local c = refreshContext()
  local settings = c.settings
  -- Switched off (the default): nothing to wait for, no retry timer.
  if type(settings) ~= "table" or settings.restoreEnabled ~= true or not Rec.Active(c) then
    return 0
  end
  if not chatFrame(1) then
    return nil
  end
  local count = Logic.RestoreLines(settings)
  local windows = type(c.windowHistory) == "table" and c.windowHistory.windows or nil
  if count <= 0 or type(windows) ~= "table" then
    return 0
  end
  local opts = {
    colors = rawget(_G, "ChatTypeInfo"),
    now = U.now(),
    marker = settings.restoreMarker == true,
    L = L,
  }
  local ids = {}
  for id in pairs(windows) do
    if type(id) == "number" then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  local written = 0
  state.restoring = true
  local ok, err = pcall(function()
    for _, id in ipairs(ids) do
      local frame = chatFrame(id)
      if frame and not isExcluded(frame) then
        for _, text in ipairs(Format.WindowLines(windows[id], count, opts)) do
          frame:AddMessage(text)
          written = written + 1
        end
      end
    end
  end)
  state.restoring = false
  if not ok then
    error(err, 0)
  end
  return written
end

local restoreStarted, restoreTries = false, 0

local function tryRestore()
  if CH.Restore() == nil and restoreTries < RESTORE_TRIES then
    restoreTries = restoreTries + 1
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
      timer.After(RESTORE_RETRY_SECONDS, function()
        ns.Safe("chathistory-restore", tryRestore)
      end)
    end
  end
end

-- Report ------------------------------------------------------------------------------------------

-- The lines /fg chatverlauf prints: state, lines per window, whispers, size.
function CH.StatusLines()
  local c = refreshContext()
  local active, reason = Rec.Active(c)
  local stateText = L["chathistory.state.on"]
  if not active then
    stateText = L["chathistory.state." .. reason]
    if reason == "conflict" then
      stateText = string.format(stateText, table.concat(c.conflicts, ", "))
    end
  end
  local report = Rec.Report(c.windowHistory, c.whisperHistory, c.settings)
  local entries = {}
  for _, window in ipairs(report.windows) do
    local label = window.name ~= "" and (window.id .. " " .. window.name) or tostring(window.id)
    entries[#entries + 1] = string.format(L["chathistory.windowEntry"], label, window.lines)
  end
  return {
    L["chathistory.menu"] .. ": " .. stateText,
    string.format(
      L["chathistory.windows"],
      #entries > 0 and table.concat(entries, ", ") or L["chathistory.windowsNone"]
    ),
    string.format(L["chathistory.whispers"], report.contacts, report.whisperLines),
    string.format(
      L["chathistory.size"],
      math.floor(report.bytes / 1024 + 0.5),
      math.floor(report.maxBytes / 1024 + 0.5),
      L["chathistory.level." .. report.level]
    ),
  }
end

function CH.ShowStatus()
  for _, text in ipairs(CH.StatusLines()) do
    ns.Notify.chat(text)
  end
end

-- Asks first, then deletes the lines of both histories. Contacts are not touched.
function CH.ConfirmClear()
  ns.Dialogs.Confirm("chathistory.clear.title", "chathistory.clear.text", function()
    local c = refreshContext()
    local windowLines, whisperLines = Logic.ClearAll(c.windowHistory, c.whisperHistory)
    ns.Notify(string.format(L["chathistory.cleared"], windowLines, whisperLines), "success")
  end)
end

local CLEAR_WORDS = { loeschen = true, ["löschen"] = true, clear = true, delete = true }

-- /fg chatverlauf [loeschen|clear]
function CH.Slash(rest)
  if CLEAR_WORDS[(rest or ""):lower()] then
    CH.ConfirmClear()
  else
    CH.ShowStatus()
  end
end

-- Lifecycle ---------------------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
  local c = refreshContext()
  c.conflicts = Rec.FindConflicts(addOnLoaded)
  if type(c.settings) == "table" and c.settings.enabled == true then
    Rec.Compact(c, U.now())
  end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
  if not restoreStarted then
    restoreStarted = true
    tryRestore()
  end
end)

ns.On("PLAYER_LOGOUT", function()
  Rec.Logout(refreshContext(), U.now())
end)
