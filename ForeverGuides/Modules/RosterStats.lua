-- Played time, PvP, reputation and statistics of the logged-in character, written into its roster
-- entry (CharRoster.SetStats) for the character overview. The client may lack any of these APIs, so
-- every call sits behind an existence check and pcall; an empty or missing answer writes nothing and
-- leaves the stored values as they are. Normalizing and display are in RosterStatsLogic.
local _, ns = ...
local Logic = ns.RosterStatsLogic

local M = {}
ns.RosterStats = M

local UPDATE_DELAY = 3
local PLAYED_EVERY = 1800
local PLAYED_MIN_GAP = 10
local PLAYED_TIMEOUT = 5
local PLAYED_EVENT = "TIME_PLAYED_MSG"
local DEFAULT_CHAT_WINDOWS = 10
local MAX_FACTIONS = 400
local MAX_BRACKETS = 4

-- Game access ---------------------------------------------------------------------------------

local function global(name)
  local fn = rawget(_G, name)
  return type(fn) == "function" and fn or nil
end

-- All return values of a protected call, nil values included; nothing when it fails.
local function call(fn, ...)
  if not fn then
    return nil
  end
  local ret = { pcall(fn, ...) }
  if ret[1] then
    return unpack(ret, 2, 21)
  end
end

local function flag(v)
  return v == true or v == 1
end

local function clock()
  local now = call(global("GetTime"))
  return type(now) == "number" and now or ns.U.now()
end

-- Played time -------------------------------------------------------------------------------------

-- The client prints the answer of RequestTimePlayed to chat because every chat frame listens to
-- TIME_PLAYED_MSG. For our own request the event is taken from the frames that have it and given
-- back to exactly those, after the answer or after PLAYED_TIMEOUT seconds. No global function is
-- replaced.
local pending = nil
local lastRequest = nil

-- Takes the event from every chat frame that has it and returns those frames.
local function unregisterChat()
  local muted = {}
  local count = rawget(_G, "NUM_CHAT_WINDOWS")
  for i = 1, type(count) == "number" and count or DEFAULT_CHAT_WINDOWS do
    local frame = rawget(_G, "ChatFrame" .. i)
    if
      type(frame) == "table"
      and type(frame.IsEventRegistered) == "function"
      and type(frame.UnregisterEvent) == "function"
      and type(frame.RegisterEvent) == "function"
    then
      local ok, registered = pcall(frame.IsEventRegistered, frame, PLAYED_EVENT)
      if ok and registered and pcall(frame.UnregisterEvent, frame, PLAYED_EVENT) then
        muted[#muted + 1] = frame
      end
    end
  end
  return muted
end

-- Ends a request (answer, timeout or failure): gives the event back and allows the next request.
local function release(state)
  if state.done then
    return
  end
  state.done = true
  if pending == state then
    pending = nil
  end
  for _, frame in ipairs(state.muted) do
    pcall(frame.RegisterEvent, frame, PLAYED_EVENT)
  end
end

local function after(delay, fn)
  local timer = rawget(_G, "C_Timer")
  return type(timer) == "table" and type(timer.After) == "function" and pcall(timer.After, delay, fn)
end

-- True while a request waits for its answer. Test seam.
function M.PlayedPending()
  return pending ~= nil and not pending.answered
end

-- Asks for the played time at the first call and then at most every PLAYED_EVERY seconds. `force`
-- skips that wait but keeps PLAYED_MIN_GAP seconds between two requests. Never two requests at
-- once. Returns true when the request went out; the answer arrives as TIME_PLAYED_MSG.
function M.RequestPlayed(force)
  local request = global("RequestTimePlayed")
  local now = clock()
  if not request or pending then
    return false
  end
  if lastRequest and now - lastRequest < (force and PLAYED_MIN_GAP or PLAYED_EVERY) then
    return false
  end
  lastRequest = now
  local state = { muted = {} }
  -- Without a timer the event could stay away from the chat for good, so nothing is taken away.
  if type(rawget(_G, "C_Timer")) == "table" then
    state.muted = unregisterChat()
    pending = state
    if not after(PLAYED_TIMEOUT, function()
      release(state)
    end) then
      release(state)
    end
  end
  if not pcall(request) then
    release(state)
    return false
  end
  return true
end

-- PvP -------------------------------------------------------------------------------------------------

local function ratedInfo()
  local direct = global("GetPersonalRatedInfo")
  if direct then
    return direct
  end
  local pvp = rawget(_G, "C_PvP")
  local fn = type(pvp) == "table" and pvp.GetPersonalRatedInfo
  return type(fn) == "function" and fn or nil
end

local function readPvp()
  local part = { ratings = {} }
  local kills, _, highest = call(global("GetPVPLifetimeStats"))
  part.kills, part.highestRank = kills, highest
  part.honor = call(global("UnitHonor"), "player") or call(global("GetHonorCurrency"))
  part.level = call(global("UnitHonorLevel"), "player")
  local rank = call(global("UnitPVPRank"), "player")
  if type(rank) == "number" and rank > 0 then
    local name, number = call(global("GetPVPRankInfo"), rank)
    part.rankName = name
    if not part.level or part.level == 0 then
      part.level = number
    end
  end
  local rated = ratedInfo()
  for bracket = 1, MAX_BRACKETS do
    local rating, best = call(rated, bracket)
    if type(rating) == "number" and rating > 0 then
      part.ratings[#part.ratings + 1] = { bracket = bracket, rating = rating, best = best }
    end
  end
  return Logic.CleanPvp(part)
end

-- Reputation --------------------------------------------------------------------------------------------

local function standingLabel(standing)
  local label = type(standing) == "number" and rawget(_G, "FACTION_STANDING_LABEL" .. standing) or nil
  return type(label) == "string" and label or nil
end

-- Way 1: GetNumFactions + GetFactionInfo.
local function viaGlobals()
  local count, info = global("GetNumFactions"), global("GetFactionInfo")
  local total = count and info and call(count)
  if type(total) ~= "number" then
    return nil
  end
  local rows = {}
  for i = 1, math.min(total, MAX_FACTIONS) do
    local name, _, standing, min, max, current, _, _, header, _, hasRep, _, _, id = call(info, i)
    if name then
      rows[#rows + 1] = {
        id = id,
        name = name,
        standing = standing,
        label = standingLabel(standing),
        min = min,
        max = max,
        current = current,
        header = flag(header),
        hasRep = flag(hasRep),
      }
    end
  end
  return Logic.FromReputation(rows)
end

-- Way 2: C_Reputation.
local function viaReputationApi()
  local api = rawget(_G, "C_Reputation")
  if
    type(api) ~= "table"
    or type(api.GetNumFactions) ~= "function"
    or type(api.GetFactionDataByIndex) ~= "function"
  then
    return nil
  end
  local total = call(api.GetNumFactions)
  if type(total) ~= "number" then
    return nil
  end
  local rows = {}
  for i = 1, math.min(total, MAX_FACTIONS) do
    local data = call(api.GetFactionDataByIndex, i)
    if type(data) == "table" and data.name then
      rows[#rows + 1] = {
        id = data.factionID,
        name = data.name,
        standing = data.reaction,
        label = standingLabel(data.reaction),
        min = data.currentReactionThreshold,
        max = data.nextReactionThreshold,
        current = data.currentStanding,
        header = flag(data.isHeader),
        hasRep = flag(data.isHeaderWithRep),
      }
    end
  end
  return Logic.FromReputation(rows)
end

local function readReputation()
  return viaGlobals() or viaReputationApi()
end

-- Statistics ----------------------------------------------------------------------------------------------

local function readStatistics()
  local statistic = global("GetStatistic")
  if not statistic then
    return nil
  end
  local info = global("GetAchievementInfo")
  local rows = {}
  for _, id in ipairs(Logic.STAT_IDS) do
    local value = call(statistic, id)
    if value ~= nil and value ~= "" then
      local _, name = call(info, id)
      rows[#rows + 1] = { id = id, name = name, value = value }
    end
  end
  return Logic.FromStatistics(rows)
end

-- Storing -----------------------------------------------------------------------------------------------------

-- Writes `part` (CharRoster.SetStats) into the current character's entry. Returns true when it was
-- stored; an empty part touches nothing, not even the entry.
local function store(part)
  local Roster = ns.CharRoster
  if not Roster.Enabled() or not (part.played or part.pvp or part.rep or part.stats) then
    return false
  end
  local key = Roster.CurrentKey()
  if not key then
    return false
  end
  local now = Roster.Now()
  if Roster.SetStats(key, part, now) then
    return true
  end
  -- The entry does not exist yet (first login): create it, then write.
  return Roster.Capture() ~= nil and Roster.SetStats(key, part, now)
end

-- Reads PvP, reputation and statistics and stores what the client delivered.
function M.Capture()
  return store({ pvp = readPvp(), rep = readReputation(), stats = readStatistics() })
end

local function schedule()
  ns.Debounce("rosterstats-update", UPDATE_DELAY, function()
    M.RequestPlayed()
    M.Capture()
  end)
end
M.Schedule = schedule

for _, event in ipairs({
  "PLAYER_LOGIN",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_LEVEL_UP",
  "UPDATE_FACTION",
  "PLAYER_PVP_KILLS_CHANGED",
  "PLAYER_PVP_RANK_CHANGED",
  "HONOR_XP_UPDATE",
  "ACHIEVEMENT_EARNED",
}) do
  ns.On(event, schedule)
end

-- The answer to RequestTimePlayed, also to a /played typed by hand.
-- The chat frames get the event back one step later, so none of them sees it twice.
ns.On(PLAYED_EVENT, function(_, total, level)
  local state = pending
  if state then
    state.answered = true
  end
  if state and not after(0, function()
    release(state)
  end) then
    release(state)
  end
  if type(total) == "number" then
    store({ played = total, levelPlayed = level })
  end
end)

-- The last reading happens right away, a timer would not run any more.
ns.On("PLAYER_LOGOUT", function()
  M.Capture()
end)
