-- Records what happens in the guild: roster changes, system messages in the chat, join markers in
-- notes and (where the client has it) the server guild log. Reads only. Nothing is sent to the
-- guild and no guild function that changes something is called; the data goes into the record of the
-- guild (see HistoryLogic.lua for the rules). Never raises in combat: a snapshot waits until it ends.
local _, gm = ...
if not gm.ext then
  return
end
local FG, HL, DL = gm.FG, gm.HistoryLogic, gm.DatesLogic
local GD = FG.GuildData

local H = {}
gm.History = H

-- A roster burst is read this many seconds after its last update; a burst that keeps going is
-- looked at again at most this many times (the next update starts over).
local MAX_RETRY = 3

local lastUpdate, candidate, logAsked, patterns
local retries = 0

local function clock()
  local ok, now = pcall(GetTime)
  return ok and tonumber(now) or 0
end

local function inCombat()
  local ok, fighting = pcall(InCombatLockdown)
  return ok and fighting == true
end

local function debug(fmt, ...)
  if FG.Log and FG.Log.debug then
    FG.Log.debug(fmt, ...)
  end
end

-- Seconds the clock of the add-on runs ahead of the game: only the sample guild (time lapse) sets it.
local shift = 0

function H.SetShift(seconds)
  shift = type(seconds) == "number" and seconds == seconds and math.abs(seconds) < 1e9 and seconds or 0
end

-- Today as a day number in local time, the time stamp and the offset to UTC; nil without a clock.
function H.Clock()
  local clockFn, dateFn = rawget(_G, "time"), rawget(_G, "date")
  if type(clockFn) ~= "function" or type(dateFn) ~= "function" then
    return nil
  end
  local ok, now = pcall(clockFn)
  if not ok or type(now) ~= "number" then
    return nil
  end
  now = now + shift
  local okLocal, localT = pcall(dateFn, "*t", now)
  local okUtc, utcT = pcall(dateFn, "!*t", now)
  if not (okLocal and okUtc and type(localT) == "table" and type(utcT) == "table") then
    return nil
  end
  local offset = DL.OffsetOf(localT, utcT)
  return DL.DayOf(now, offset), now, offset
end

-- The time stamp the log entries and the undo window use: the same clock as H.Clock.
function H.Epoch()
  local _, now = H.Clock()
  return now or FG.U.now()
end

-- Format of dates the player reads: the stored choice, else by language.
function H.DateFormat()
  local chosen = gm.db.prefs.dateFormat
  for _, f in ipairs(DL.FORMATS) do
    if f == chosen then
      return f
    end
  end
  local getLocale = rawget(_G, "GetLocale")
  return getLocale and getLocale() == "deDE" and "dmy" or "iso"
end

-- Order for slash dates: only a player who chose a format has one.
function H.SlashOrder()
  local f = H.DateFormat()
  return gm.db.prefs.dateFormat and (f == "mdy" and "mdy" or "dmy") or nil
end

-- True while the guild record may be written and the player has not switched the recording off.
local function active()
  return not gm.WriteBlock() and not GD.Source() and gm.Guild().settings.history ~= false
end

-- Server log -------------------------------------------------------------------------------------------

local function logApi()
  local info = rawget(_G, "C_GuildInfo")
  local function find(name)
    local fn = type(info) == "table" and info[name] or rawget(_G, name)
    return type(fn) == "function" and fn or nil
  end
  local query, count, entry = find("QueryGuildEventLog"), find("GetNumGuildEvents"), find("GetGuildEventInfo")
  if query and count and entry then
    return query, count, entry
  end
end

-- True when the client has all three functions of the guild log (not measured in the Forever client yet).
function H.LogAvailable()
  return logApi() ~= nil
end

-- Asks the server for the guild log once per session. Answers true when asked.
function H.RequestLog()
  local query = logApi()
  if not query or logAsked or inCombat() or not active() then
    return false
  end
  logAsked = true
  return (pcall(query))
end

local function text(v)
  return FG.ItemInfo.accessible(v) and type(v) == "string" and v or nil
end

local function number(v)
  return FG.ItemInfo.accessible(v) and type(v) == "number" and v or nil
end

-- Reads the log the client holds and writes what it says. Answers the number of rows read.
function H.ReadLog()
  local _, count, entry = logApi()
  local today, now, offset = H.Clock()
  if not count or not today or inCombat() or not active() then
    return 0
  end
  local okCount, n = pcall(count)
  n = okCount and number(n) or 0
  local rows = {}
  for i = 1, math.min(n, HL.MAX_LOG) do
    local ok, kind, p1, p2, rank, y, mo, d, h = pcall(entry, i)
    if ok and text(kind) then
      rows[#rows + 1] = {
        type = kind,
        player1 = text(p1),
        player2 = text(p2),
        rank = number(rank),
        years = number(y),
        months = number(mo),
        days = number(d),
        hours = number(h),
      }
    end
  end
  local events, joined = HL.ServerEvents(rows, today, now, offset)
  HL.ApplyLog(gm.Guild(), events, joined, today)
  return #rows
end

-- Roster -----------------------------------------------------------------------------------------------

-- Compares the roster with the last valid snapshot and records the difference. Answers the result, or
-- nil and the reason nothing was recorded.
function H.Process()
  if not active() then
    return nil, "blocked"
  end
  local today = H.Clock()
  if not today then
    return nil, "noClock"
  end
  local snap = GD.Get()
  local guild = gm.Guild()
  local rights = GD.Rights()
  local ctx = {
    today = today,
    quiet = lastUpdate and clock() - lastUpdate or 0,
    combat = inCombat(),
    officerRead = rights.officerNote == true,
    candidate = candidate,
  }
  local state = {
    seen = guild.seen,
    idByGuid = guild.idByGuid,
    firstScanDay = guild.firstScanDay,
    lastScanDay = guild.lastScanDay,
    lastScanCount = guild.lastScanCount,
  }
  local res, why, count = HL.Diff(state, snap, ctx)
  candidate = why == "jump" and count or nil
  if not res then
    debug("gm history: no snapshot (%s)", tostring(why))
    return nil, why
  end
  HL.Apply(guild, res, today)
  HL.ApplyNotes(guild, snap.members, { today = today, order = H.SlashOrder(), officerRead = ctx.officerRead })
  H.RequestLog()
  return res
end

-- Reads the join markers of the notes in the roster now (the scan does it too). Answers the number of
-- dates that changed, or nil and the reason nothing was read.
function H.ReadNotes()
  if not active() then
    return nil, "blocked"
  end
  local today = H.Clock()
  if not today then
    return nil, "noClock"
  end
  local snap = GD.Get()
  local officerRead = GD.Rights().officerNote == true
  return HL.ApplyNotes(
    gm.Guild(),
    snap.members or {},
    { today = today, order = H.SlashOrder(), officerRead = officerRead }
  )
end

local function schedule(delay)
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, function()
      local quiet = lastUpdate and clock() - lastUpdate or HL.MIN_QUIET
      if quiet < HL.MIN_QUIET and retries < MAX_RETRY then
        retries = retries + 1
        schedule(HL.MIN_QUIET - quiet + 0.5)
        return
      end
      FG.Safe("gm-history", H.Process)
    end)
  end
end

local function onRoster()
  if not active() then
    return
  end
  lastUpdate, retries = clock(), 0
  schedule(HL.MIN_QUIET + 0.5)
end

-- Chat ---------------------------------------------------------------------------------------------------

local function chatPatterns()
  if not patterns then
    patterns = HL.ChatPatterns({
      join = rawget(_G, "ERR_GUILD_JOIN_S"),
      leave = rawget(_G, "ERR_GUILD_LEAVE_S"),
      remove = rawget(_G, "ERR_GUILD_REMOVE_SS"),
      promote = rawget(_G, "ERR_GUILD_PROMOTE_SSS"),
      demote = rawget(_G, "ERR_GUILD_DEMOTE_SSS"),
    })
  end
  return patterns
end

-- Parses one system message and records it. A message the client hides from add-ons is skipped; the
-- roster comparison finds the same change later.
function H.OnChat(msg)
  if not FG.ItemInfo.accessible(msg) or type(msg) ~= "string" or not active() then
    return false
  end
  local parsed = HL.ParseChat(msg, chatPatterns())
  local today = parsed and H.Clock()
  if not today then
    return false
  end
  HL.ApplyChat(gm.Guild(), parsed, today)
  return true
end

FG.On("GUILD_ROSTER_UPDATE", onRoster)
FG.On("CHAT_MSG_SYSTEM", function(_, msg)
  H.OnChat(msg)
end)
FG.On("GUILD_EVENT_LOG_UPDATE", function()
  if H.LogAvailable() then
    H.ReadLog()
  end
end)
-- A new guild: its log may be asked again, a rejected jump says nothing about it.
FG.On("PLAYER_GUILD_UPDATE", function()
  logAsked, candidate = false, nil
end)
