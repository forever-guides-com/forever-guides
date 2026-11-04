-- Chat history, recording: turns one chat event into stored lines, decides when the history is
-- compacted and builds the status report. Pure apart from the secret value check the caller injects
-- (ctx.safe), the caller passes every clock value. One message costs a constant amount of work:
-- compacting runs at login, at logout and at most every COMPACT_INTERVAL seconds on activity.
--
-- ctx = {
--   settings       normalized settings.chat
--   windowHistory  per character, ChatHistoryLogic window history
--   whisperHistory account wide, ChatHistoryLogic whisper history
--   own            own character as "Name-Realm", homeRealm the realm of the own server
--   windows        function() -> window descriptions (ChatHistoryRoute), optional
--   groups         client table event -> message group, optional
--   safe           function(value) -> value, or nil for a secret or unreadable one
--   conflicts      names of loaded chat addons (FindConflicts), state = NewState()
-- }
local _, ns = ...

local Logic, Limits, Route = ns.ChatHistoryLogic, ns.ChatHistoryLimits, ns.ChatHistoryRoute
local PN = ns.PlayerName

local Rec = {}
ns.ChatHistoryRecord = Rec

Rec.COMPACT_INTERVAL = 300
-- Errors in the recording handler after which it stops for the session.
Rec.MAX_ERRORS = 3
-- Chat addons that own the chat windows themselves. With one of them loaded nothing is recorded or
-- restored.
Rec.CONFLICTS = { "ElvUI", "Prat-3.0", "Chatter", "Glass" }

-- The conflicting addons that isLoaded(name) reports, in list order.
function Rec.FindConflicts(isLoaded)
  local out = {}
  if type(isLoaded) ~= "function" then
    return out
  end
  for _, name in ipairs(Rec.CONFLICTS) do
    local ok, loaded = pcall(isLoaded, name)
    if ok and loaded then
      out[#out + 1] = name
    end
  end
  return out
end

function Rec.NewState()
  return { lastCompact = nil, restoring = false, errors = 0 }
end

-- Counts one failed handler run; true once the handler has to stop.
function Rec.NoteError(state)
  state.errors = (state.errors or 0) + 1
  return state.errors >= Rec.MAX_ERRORS
end

-- Whether recording and restoring are on, else the reason: "disabled", "conflict", "errors".
function Rec.Active(ctx)
  local settings = ctx.settings
  if type(settings) ~= "table" or settings.enabled ~= true then
    return false, "disabled"
  end
  if ctx.conflicts and #ctx.conflicts > 0 then
    return false, "conflict"
  end
  if ctx.state and (ctx.state.errors or 0) >= Rec.MAX_ERRORS then
    return false, "errors"
  end
  return true
end

----------------------------------------------------------------------------------------------------
-- Compacting
----------------------------------------------------------------------------------------------------

-- Compacts both histories now and starts the next interval. Returns the Logic.Compact report.
function Rec.Compact(ctx, now)
  ctx.state.lastCompact = now
  return Logic.Compact(ctx.windowHistory, ctx.whisperHistory, ctx.settings, now)
end

-- Compacts when the interval has passed since the last time. The first call only starts the clock, so
-- a message right after login does not compact twice.
function Rec.MaybeCompact(ctx, now)
  local state = ctx.state
  if state.lastCompact == nil or now < state.lastCompact then
    state.lastCompact = now
    return nil
  end
  if now - state.lastCompact >= Rec.COMPACT_INTERVAL then
    return Rec.Compact(ctx, now)
  end
  return nil
end

-- At logout: clearOnLogout deletes the lines of both histories (whatever the other switches say, it is
-- a privacy switch), otherwise a feature that is on compacts. Returns "cleared", "compacted" or nil.
function Rec.Logout(ctx, now)
  local settings = ctx.settings
  if type(settings) ~= "table" then
    return nil
  end
  if settings.clearOnLogout == true then
    Logic.ClearAll(ctx.windowHistory, ctx.whisperHistory)
    return "cleared"
  end
  if settings.enabled == true then
    Rec.Compact(ctx, now)
    return "compacted"
  end
  return nil
end

----------------------------------------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------------------------------------

-- A secret or unreadable value is nil, so is a value that is no string.
local function readString(ctx, value, allowEmpty)
  local safe = ctx.safe(value)
  if type(safe) ~= "string" or (safe == "" and not allowEmpty) then
    return nil
  end
  return safe
end

local function copyLine(line)
  return { line[1], line[2], line[3], line[4] }
end

local function recordWindows(ctx, event, entry, now, text, sender, channelName, zoneChannelId)
  local settings = ctx.settings
  local line = Logic.MakeLine(now, Logic.TYPES[entry.type], entry.plain and "" or sender, text, settings.maxChars)
  if not line then
    return false, "line"
  end
  local windows = ctx.windows and ctx.windows() or nil
  if entry.group == "CHANNEL" then
    channelName, zoneChannelId = ctx.safe(channelName), ctx.safe(zoneChannelId)
  end
  local targets = Route.Windows(event, windows, channelName, zoneChannelId, ctx.groups)
  if #targets == 0 then
    return false, "window"
  end
  for i, target in ipairs(targets) do
    Logic.AppendWindow(ctx.windowHistory, target.id, target.name, i == 1 and line or copyLine(line), settings)
  end
  return true
end

local function recordWhisper(ctx, entry, now, text, sender)
  if ctx.messengerStore then
    return false, "messenger"
  end
  local settings = ctx.settings
  local own = ctx.own
  if type(own) ~= "string" or own == "" then
    return false, "own"
  end
  if not Logic.WhisperStored(settings, sender, ctx.homeRealm) then
    return false, "whisper"
  end
  local from = entry.dir == Logic.DIR_IN and sender or own
  local line = Logic.MakeWhisperLine(now, entry.dir, from, text, own, settings.maxChars)
  if not line then
    return false, "line"
  end
  if not Logic.AppendWhisper(ctx.whisperHistory, sender, line, settings, ctx.homeRealm) then
    return false, "line"
  end
  return true
end

-- One chat event: text and sender as the event delivers them (they may be secret), now the clock
-- value. channelName and zoneChannelId are the event's channel arguments. Returns true when a line was
-- stored, else false and the reason: "event", "disabled", "conflict", "errors", "restoring", "secret",
-- "type", "whisper", "messenger" (the messenger saves whispers), "own", "window", "line", "history".
function Rec.Handle(ctx, event, now, text, sender, channelName, zoneChannelId)
  local entry = Route.EVENTS[event]
  if not entry then
    return false, "event"
  end
  local active, reason = Rec.Active(ctx)
  if not active then
    return false, reason
  end
  if ctx.state.restoring then
    return false, "restoring"
  end
  -- A type that is switched off costs no secret check.
  if not entry.dir and not Logic.WindowTypeStored(ctx.settings, Logic.TYPES[entry.type]) then
    return false, "type"
  end
  if type(ctx.safe) ~= "function" then
    return false, "secret"
  end
  text = readString(ctx, text, false)
  sender = readString(ctx, sender, entry.plain == true)
  if not text or not sender then
    return false, "secret"
  end
  sender = PN.Clean(sender)
  local ok, why
  if entry.dir then
    if type(ctx.whisperHistory) ~= "table" then
      return false, "history"
    end
    ok, why = recordWhisper(ctx, entry, now, text, sender)
  else
    if type(ctx.windowHistory) ~= "table" then
      return false, "history"
    end
    ok, why = recordWindows(ctx, event, entry, now, text, sender, channelName, zoneChannelId)
  end
  if ok then
    Rec.MaybeCompact(ctx, now)
  end
  return ok, why
end

----------------------------------------------------------------------------------------------------
-- Report
----------------------------------------------------------------------------------------------------

local function windowOrder(a, b)
  local na, nb = tonumber(a.id), tonumber(b.id)
  if na and nb and na ~= nb then
    return na < nb
  end
  return tostring(a.id) < tostring(b.id)
end

-- What /fg chatverlauf shows: lines per window (ordered by id), whisper conversations and lines,
-- estimated bytes, the limit and the level ("ok", "warn", "over"). Walks every line, so it belongs
-- to a command, not to a message.
function Rec.Report(windowHistory, whisperHistory, settings)
  local windows = {}
  local map = type(windowHistory) == "table" and windowHistory.windows or nil
  for id, buffer in pairs(type(map) == "table" and map or {}) do
    if type(buffer) == "table" and type(buffer.lines) == "table" and #buffer.lines > 0 then
      windows[#windows + 1] =
        { id = id, name = type(buffer.name) == "string" and buffer.name or "", lines = #buffer.lines }
    end
  end
  table.sort(windows, windowOrder)
  local maxBytes = Limits.Clamp("maxBytes", type(settings) == "table" and settings.maxBytes or nil)
  local bytes = Logic.EstimateBytes(windowHistory, whisperHistory)
  local level, ratio = Logic.MemoryLevel(bytes, maxBytes)
  return {
    windows = windows,
    windowLines = Logic.CountWindowLines(windowHistory),
    contacts = Logic.CountContacts(whisperHistory),
    whisperLines = Logic.CountWhisperLines(whisperHistory),
    bytes = bytes,
    maxBytes = maxBytes,
    level = level,
    ratio = ratio,
  }
end
