-- Guild roster for the overview page: asks the game for the list (C_GuildInfo.GuildRoster, at most
-- every 10 seconds, never in combat), marks the cache dirty on the roster events and reads it
-- lazily when the page needs it. Reads only: nothing here changes the guild. Every game call is
-- wrapped in pcall, a missing function answers nil.
local _, ns = ...
local GL = ns.GuildLogic

local D = {}
ns.GuildData = D

D.MIN_ASK = 10
D.MAX_MEMBERS = 2000
-- Seconds a request may stay unanswered by an event before the cache counts as the answer: a client that
-- has nothing new to say may skip GUILD_ROSTER_UPDATE, and the age of the list must not stay behind.
D.ANSWER_WAIT = 4
-- An empty roster is read again at most this often, unless a roster event marks it dirty.
D.RETRY = 1
local UPDATE_DELAY = 0.5

local state = { dirty = true, asked = -1e9, events = 0, requests = 0, reads = 0, silent = 0 }
-- A stand-in source (an extension showing sample data) instead of the game's roster: see D.SetSource.
local source

local function g(name)
  return rawget(_G, name)
end

-- Values of a protected call as a table, nil when the function is missing or raises an error.
local function pack(ok, ...)
  if ok then
    return { ... }
  end
end

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  return pack(pcall(fn, ...))
end

local function inCombat()
  local r = call(g("InCombatLockdown"))
  return r ~= nil and r[1] == true
end

local function clock()
  local r = call(g("GetTime"))
  return r and tonumber(r[1]) or 0
end

local function empty()
  return { inGuild = false, loaded = false, name = "", rankName = "", motd = "", members = {}, ranks = {}, online = 0 }
end

state.snap = empty()

-- C_GuildInfo first (the Forever client has no global GuildRoster), then the global.
local function api(name)
  local info = g("C_GuildInfo")
  if type(info) == "table" and type(info[name]) == "function" then
    return info[name]
  end
  return g(name)
end

local function read()
  local snap = empty()
  local inGuild = call(g("IsInGuild"))
  snap.inGuild = inGuild ~= nil and inGuild[1] == true
  if not snap.inGuild then
    state.snap, state.dirty = snap, false
    return
  end
  local info = call(g("GetGuildInfo"), "player")
  if info then
    snap.name = type(info[1]) == "string" and info[1] or ""
    snap.rankName = type(info[2]) == "string" and info[2] or ""
  end
  local count = call(g("GetNumGuildMembers"))
  count = count and tonumber(count[1]) or 0
  -- Rows can be fewer than the total (filter "online only", unreadable rows): a reader that finds
  -- departures must compare both.
  snap.total, snap.takenAt = count, clock()
  state.reads = state.reads + 1
  local ranks = {}
  for i = 1, math.min(count, D.MAX_MEMBERS) do
    local raw = call(g("GetGuildRosterInfo"), i)
    local m
    if raw then
      local online = raw[GL.FIELD.online]
      m = GL.Normalize(i, raw, not (online == true or online == 1) and call(g("GetGuildRosterLastOnline"), i) or nil)
    end
    if m then
      snap.members[#snap.members + 1] = m
      if m.online then
        snap.online = snap.online + 1
      end
      ranks[m.rank] = ranks[m.rank] or m.rankName
    end
  end
  for index, name in pairs(ranks) do
    snap.ranks[#snap.ranks + 1] = { index = index, name = name }
  end
  table.sort(snap.ranks, function(a, b)
    return a.index < b.index
  end)
  local guildInfo = g("C_GuildInfo")
  local motd = call(type(guildInfo) == "table" and guildInfo.GetMOTD or nil) or call(g("GetGuildRosterMOTD"))
  snap.motd = motd and type(motd[1]) == "string" and motd[1] or ""
  snap.loaded = #snap.members > 0
  state.snap = snap
  -- An empty roster means the server has not answered yet, read again soon.
  state.dirty = not snap.loaded
  state.retryAt = state.dirty and clock() + D.RETRY or nil
end

-- The cached roster. Read from the game when the events marked it dirty, never in combat.
function D.Get()
  if source then
    return source.snapshot()
  end
  if state.pending and clock() - state.pending >= D.ANSWER_WAIT then
    state.pending, state.silent, state.dirty, state.retryAt = nil, state.silent + 1, true, nil
  end
  if state.dirty and not inCombat() and not (state.retryAt and clock() < state.retryAt) then
    read()
  end
  return state.snap
end

-- Asks the server for the roster. false when not in a guild, in combat or asked less than
-- D.MIN_ASK seconds ago.
function D.Request()
  if source then
    return false
  end
  local inGuild = call(g("IsInGuild"))
  if not (inGuild and inGuild[1] == true) or inCombat() then
    return false
  end
  local now = clock()
  if now - state.asked < D.MIN_ASK then
    return false
  end
  local fn = api("GuildRoster")
  if type(fn) ~= "function" then
    return false
  end
  state.asked = now
  state.requests = state.requests + 1
  state.askOk = pcall(fn)
  state.pending = state.askOk and now or nil
  return true
end

-- What the age of the list is made of, for the support report: seconds since the last read, the last
-- roster event and the last request, how many of each happened, whether the call raised and how often a
-- request went unanswered by an event. Plain numbers and booleans only.
function D.Diag()
  local now = clock()
  local function ago(t)
    return type(t) == "number" and now - t or nil
  end
  local snap = state.snap
  return {
    takenAge = ago(snap.takenAt),
    eventAge = ago(state.lastEvent),
    askAge = state.requests > 0 and ago(state.asked) or nil,
    events = state.events,
    requests = state.requests,
    reads = state.reads,
    silent = state.silent,
    askOk = state.askOk,
    hasCall = type(api("GuildRoster")) == "function",
    dirty = state.dirty,
    loaded = snap.loaded == true,
    members = #snap.members,
  }
end

-- One right as the game answers it (api name such as "CanEditPublicNote"); nil for a function the
-- client does not have.
function D.Can(name)
  if source then
    return source.can(name)
  end
  local r = call(api(name))
  return r and r[1] == true
end

-- The rights the page needs (notes), as the game answers them.
function D.Rights()
  return GL.Rights(D.Can)
end

local function onUpdate()
  state.dirty, state.pending, state.retryAt = true, nil, nil
  state.events, state.lastEvent = state.events + 1, clock()
  ns.Debounce("guild-update", UPDATE_DELAY, function()
    ns.Emit("FG_GUILD_UPDATE")
  end)
end

ns.On("GUILD_ROSTER_UPDATE", onUpdate)
ns.On("PLAYER_GUILD_UPDATE", onUpdate)
ns.On("GUILD_RANKS_UPDATE", onUpdate)

-- Stand-in source ---------------------------------------------------------------------------------

-- The source that stands in for the game, nil while the game answers. A source is a table with
--   snapshot(): the roster (same shape as D.Get), can(name): one right, peer(name): item level and
--   jobs of a member, seen(): the contact list of the tab "Social", seenNote: locale key of its note,
--   why: { invite, update } locale keys of the reason a row button is dimmed,
--   hint, done: locale keys of the lines the GildenManager shows, apply(action, memberKey, value): a
--   confirmed GildenManager action on the roster of the source (true when something changed).
-- It stays in memory and the game is not asked while it is set.
function D.Source()
  return source
end

-- Sets or clears (nil) the source and tells the page; calling it again redraws after a change.
function D.SetSource(value)
  source = value
  ns.Emit("FG_GUILD_SOURCE")
end

-- Test hook: forget the cache and the request time.
function D.Reset()
  source = nil
  state.dirty, state.asked, state.snap = true, -1e9, empty()
  state.events, state.requests, state.reads, state.silent = 0, 0, 0, 0
  state.pending, state.lastEvent, state.askOk, state.retryAt = nil, nil, nil, nil
end
