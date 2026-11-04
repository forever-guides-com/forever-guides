-- Forever Chat, the filter of the game chat (game access): takes whispers out of the game chat once the
-- messenger shows them. Off by default (switch hideWhispers): until the player turns it on, no filter is
-- registered and the chat of the game stays as it is.
-- The filter runs on CHAT_MSG_WHISPER and CHAT_MSG_WHISPER_INFORM and decides at run time (HooksLogic.ShouldHide):
-- only while the input runs, the window exists (and by default is open), no combat, no chat restriction and
-- only for lines it can read. Secret values, ignored players and anything unclear go through. Once
-- registered it stays registered while the input runs, so a switch needs no new registration.
-- A filter that raises lets the line through; three errors take it off for the session.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local HL, FL = chat.HooksLogic, chat.FiltersLogic

local Filters = {}
chat.Filters = Filters

local errors, off, registered = 0, false, false

local function global(name)
  return rawget(_G, name)
end

local function options()
  local db = chat.db
  return type(db) == "table" and type(db.options) == "table" and db.options or {}
end

-- The game's functions to add and remove an event filter (the older global names, else the utility table).
local function filterApi(kind)
  local legacy = global("ChatFrame_" .. kind .. "MessageEventFilter")
  if type(legacy) == "function" then
    return legacy
  end
  local util = global("ChatFrameUtil")
  local fn = type(util) == "table" and util[kind .. "MessageEventFilter"]
  return type(fn) == "function" and fn or nil
end

local function restricted()
  local ok, value = pcall(chat.Send.Restricted)
  return ok and value == true
end

local function ignored(sender, args)
  local ingest = chat.Ingest
  if not (ingest and ingest.IsIgnored) then
    return false
  end
  local guid = FG.AutoGuard.Safe(args[12])
  local ok, value = pcall(ingest.IsIgnored, sender, type(guid) == "string" and guid or nil)
  return ok and value == true
end

-- args are the event arguments after the event name (1 text, 2 partner, 12 guid).
local function decide(args)
  local opts = options()
  if not HL.Option(opts, "hideWhispers") then
    return false
  end
  local readable, sender = FL.Read(FG.AutoGuard.Safe, args)
  local window = chat.Window
  local st = {
    running = chat.Ingest.IsRunning(),
    exists = window.Frame() ~= nil,
    shown = window.IsShown(),
    combat = FG.InCombat(),
    restricted = restricted(),
    readable = readable,
  }
  st.ignored = readable and HL.Option(opts, "ignoreIgnored") and ignored(sender, args) or false
  return HL.ShouldHide(opts, st)
end

local function fail(err)
  local count, stop = FL.Failed(errors)
  errors = count
  FG.Log.warn("chatfilters: %s", tostring(err))
  if not stop or off then
    return
  end
  off = true
  Filters.Sync()
  local text = string.format(FG.L["chat.hooks.filterOff"], count)
  FG.Errors.add({ msg = text, kind = "warning", ctx = "chatfilters" })
  FG.Notify(text, "warning")
end

-- The filter of the game: true takes the line out of the chat, false lets it through. Never raises.
local function filter(_, _, ...)
  if off then
    return false
  end
  local ok, hide = pcall(decide, { ... })
  if not ok then
    pcall(fail, hide)
    return false
  end
  return hide == true
end

-- Registration ------------------------------------------------------------------------------------------

-- True while the filter may be in the game: the input runs, the switch is on once and no error took it off.
function Filters.Wanted()
  return not off and chat.Ingest ~= nil and chat.Ingest.IsRunning() and HL.Option(options(), "hideWhispers")
end

-- Registers when wanted. Takes the filter off when the input stopped or errors switched it off. Safe to call
-- often.
function Filters.Sync()
  if Filters.Wanted() and not registered then
    local add = filterApi("Add")
    if add then
      for _, event in ipairs(FL.EVENTS) do
        pcall(add, event, filter)
      end
      registered = true
    end
  elseif registered and (off or not (chat.Ingest and chat.Ingest.IsRunning())) then
    local remove = filterApi("Remove")
    if remove then
      for _, event in ipairs(FL.EVENTS) do
        pcall(remove, event, filter)
      end
    end
    registered = false
  end
end

function Filters.IsRegistered()
  return registered
end

-- The filter function the game calls (for tests).
Filters.Filter = filter

-- Errors of this session and whether they switched the filter off.
function Filters.Errors()
  return errors, off
end

local api = chat.hook.Api and chat.hook.Api()
if type(api) == "table" then
  api.Filters = Filters
end

local function sync()
  FG.Safe("chatfilters", Filters.Sync)
end

FG.On("FG_CHAT_UPDATE", sync)
FG.On("FG_SUBADDON_CHANGED", function(_, id)
  if id == "chat" then
    sync()
  end
end)
-- The settings page tells which switch changed: turning hideWhispers on starts afresh after errors.
local function optionChanged(_, id, value)
  if id == "hideWhispers" and value == true then
    errors, off = 0, false
  end
  sync()
end
FG.On("FG_CHAT_SETTING", optionChanged)
FG.On("FG_CHAT_STORE_READY", sync)
FG.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^chat") then
    sync()
  end
end)

sync()
