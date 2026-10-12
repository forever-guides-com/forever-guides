-- Rules of the contact detection in the neighbourhood (NearbyContacts.lua) and of the "Update" button
-- (NearbyWho.lua), no game calls: how often one contact is written, the per-second time budget and
-- the crowd pause of the plate events, the who query and its answers. The caller passes the clock in,
-- so every case is testable.
local _, ns = ...
local PN = ns.PlayerName

local NL = {}
ns.NearbyLogic = NL

-- Seconds between two writes for one contact.
NL.WRITE_EVERY = 300
-- Seconds between two readings of one contact through the inspect function.
NL.INSPECT_EVERY = 600
-- Seconds between two who queries (one for all contacts together).
NL.WHO_EVERY = 10
-- Seconds the add-on waits for the answer of a who query.
NL.WHO_TIMEOUT = 15
-- Milliseconds of work the events may use in one second, then they are dropped until the next second.
NL.BUDGET_MS = 0.5
-- More events than this in one second count as a crowd: the detection pauses for NL.CROWD_PAUSE seconds.
NL.CROWD_EVENTS = 60
NL.CROWD_PAUSE = 10
-- Errors in a row of the detection until it switches itself off.
NL.MAX_ERRORS = 3
-- Rows of a who answer that are looked at (the game sends at most 50).
NL.MAX_WHO_ROWS = 50

-- true when `last` is nil, at least `every` seconds ago, or in the future (a clock that restarted).
function NL.Due(last, now, every)
  return last == nil or now - last >= every or now < last
end

-- Seconds still to wait until Due, 0 when it is due.
function NL.Wait(last, now, every)
  if NL.Due(last, now, every) then
    return 0
  end
  return math.ceil(every - (now - last))
end

-- Admission of the events: a tumbling window of one second with an event count and the time spent.
-- gate:Admit(now) -> true, or false and the reason ("pause", "crowd", "budget"); gate:Charge(ms) books
-- the time the admitted event used. gate.stats counts what happened, for the probe and the tests.
function NL.NewGate()
  local gate = { stats = { admitted = 0, pause = 0, crowd = 0, budget = 0, crowds = 0 } }
  local windowAt, count, spent, pausedUntil = nil, 0, 0, -math.huge

  function gate:Admit(now)
    local stats = self.stats
    if now < pausedUntil then
      stats.pause = stats.pause + 1
      return false, "pause"
    end
    if windowAt == nil or now - windowAt >= 1 or now < windowAt then
      windowAt, count, spent = now, 0, 0
    end
    count = count + 1
    if count > NL.CROWD_EVENTS then
      pausedUntil = now + NL.CROWD_PAUSE
      stats.crowd, stats.crowds = stats.crowd + 1, stats.crowds + 1
      return false, "crowd"
    end
    if spent >= NL.BUDGET_MS then
      stats.budget = stats.budget + 1
      return false, "budget"
    end
    stats.admitted = stats.admitted + 1
    return true
  end

  function gate:Charge(ms)
    if type(ms) == "number" and ms > 0 then
      spent = spent + ms
    end
  end

  -- Seconds of pause left at `now`, 0 while the detection runs.
  function gate:Paused(now)
    return math.max(0, pausedUntil - now)
  end

  function gate:Reset()
    windowAt, count, spent, pausedUntil = nil, 0, 0, -math.huge
  end

  return gate
end

-- Who -------------------------------------------------------------------------------------------------

-- The query for one exact name: n-"First Surname". nil without a usable name.
function NL.WhoQuery(name)
  name = PN.Clean(type(name) == "string" and name or "")
  name = (name:gsub('["|]', ""))
  if name == "" then
    return nil
  end
  return 'n-"' .. name .. '"'
end

-- One answer row in the shape the page works with, nil for a row without a name. info is the table of
-- C_FriendList.GetWhoInfo { fullName, fullGuildName, level, raceStr, classStr, area, filename }.
function NL.WhoRow(info)
  if type(info) ~= "table" or type(info.fullName) ~= "string" or info.fullName == "" then
    return nil
  end
  local level = tonumber(info.level)
  return {
    name = PN.Normalize(info.fullName),
    guild = type(info.fullGuildName) == "string" and info.fullGuildName or "",
    level = level and level > 0 and math.floor(level) or nil,
    class = type(info.filename) == "string" and info.filename:upper() or "",
    zone = type(info.area) == "string" and info.area or "",
  }
end

-- The row of the asked player; the answer may hold similar names, those are never taken.
function NL.WhoMatch(rows, name)
  for _, row in ipairs(rows) do
    if PN.Equal(row.name, name) then
      return row
    end
  end
  return nil
end

-- A who answer changes what is known about the player now (level, class, guild) and notes that he was
-- online. The time and the zone of the last sighting, the first contact and the source stay as they are.
function NL.ApplyWho(e, row, now)
  if row.level then
    e.level = row.level
  end
  if row.class ~= "" then
    e.class = row.class
  end
  e.guildName = row.guild
  if row.guild == "" then
    e.guildRank = ""
  end
  e.who = { t = now, zone = row.zone }
end
