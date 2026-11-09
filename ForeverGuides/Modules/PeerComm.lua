-- Data exchange between users of this add-on: item level and professions of other players over
-- addon messages, shown on the guild page through Peers (source "addon"). Everything is opt-in and
-- runs through ns.Comm (the only module that touches the game's message API) and ns.Consent:
-- two functions, "peerStats" (item level) and "professions", each with its own send and receive
-- switch for the audiences group and guild (settings tab "Share"). Nothing is sent, answered or stored
-- without them. The old keys settings.peerShare and settings.peerShareGuild only feed the migration.
-- Protocol version 2, prefix "FGCOMM", envelope and checksum by CommLogic. Payload of type D:
--   PS  <ilvl>                          item level as a number
--   PR  <id>:<skill>:<max>,...          at most 6 professions as skill line ids, "" for none
-- There is no request and no hello any more. Whoever may send announces the own data: when joining
-- a group, when the group grows, when the data changes and after the guild login, 2 to 8 seconds
-- late (random, so a raid does not speak in one second), at most once per ANNOUNCE_GAP seconds and
-- channel, the guild at most every GUILD_GAP seconds. Whoever only receives stays silent.
-- Protocol version 1 (prefix "FGUIDES", for users of older versions, kept for a transition):
--   H|1   hello, Q|1   request: both are dropped without a trace and never answered
--   D|1|<ilvl>|<id>:<skill>:<max>,...   data; sent and read only for the functions with consent,
--                                        the rest is left empty (ilvl 0, no professions)
local _, ns = ...
local PN, Comm, Consent, R = ns.PlayerName, ns.Comm, ns.Consent, ns.ProfessionRouteLogic

local C = {}
ns.PeerComm = C

C.PREFIX = "FGUIDES"
C.VERSION = 1
C.MAX_LENGTH = 255
C.MAX_ILVL = 2000
C.MAX_SKILL = 1000
C.MAX_JOBS = 6
C.DATA_GAP = 2
C.GUILD_GAP = 1800
C.ANNOUNCE_GAP = 60
C.ASK_WINDOW = 15
C.DELAY_MIN = 2
C.DELAY_MAX = 8
-- After the player switched sending on: 1 to 3 seconds, and the guild gap shrinks to SWITCH_GAP seconds (the
-- bucket of the line still paces the messages).
C.SWITCH_MIN = 1
C.SWITCH_MAX = 3
C.SWITCH_GAP = 10
-- A sender whose v2 message came in the last seconds is not read a second time in the old format.
C.V1_QUIET = 30
-- Replaceable in tests: random integer from lo to hi.
function C.random(lo, hi)
  return math.random(lo, hi)
end

local FUNCS = { "peerStats", "professions" }
local AUDIENCES = { "group", "guild" }
local STORE_FIELD = { peerStats = "ilvl", professions = "professions" }

-- Skill line id -> route slug, the professions the add-on can name in both languages.
local JOB_BY_ID = {}
for slug, def in pairs(R.PROFESSIONS) do
  JOB_BY_ID[def.id] = slug
end

local lastData, heard, heardV2 = {}, {}, {}
local lastAt, lastText, due, pending = {}, {}, {}, {}
local joinedAt
local members = 0
local depth = 0

local function g(name)
  return rawget(_G, name)
end

-- First value of a protected call, nil when the function is missing or raises an error.
local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if ok then
    return value
  end
  return nil
end

local function clock()
  return tonumber(try(g("GetTime"))) or 0
end

local function whole(v, max)
  v = tonumber(v)
  if not v or v ~= v then
    return 0
  end
  return math.max(0, math.min(max, math.floor(v + 0.5)))
end

-- Protocol -------------------------------------------------------------------------------------

-- "id:skill:max,..." for a profession list. Professions the add-on has no id for are left out.
local function jobsText(jobs)
  local parts = {}
  for _, p in ipairs(type(jobs) == "table" and jobs or {}) do
    local slug = R.SlugOf(p)
    if slug and #parts < C.MAX_JOBS then
      local skill = whole(p.skill, C.MAX_SKILL)
      parts[#parts + 1] =
        string.format("%d:%d:%d", R.PROFESSIONS[slug].id, skill, math.max(skill, whole(p.max, C.MAX_SKILL)))
    end
  end
  return table.concat(parts, ",")
end

-- A profession list from "id:skill:max,..." (empty text is an empty list), nil for anything that is not
-- exactly the format. A profession id the add-on does not know is skipped.
local function parseJobs(jobs)
  local list, count = {}, 0
  if jobs ~= "" then
    for token in (jobs .. ","):gmatch("([^,]*),") do
      local id, skill, max = token:match("^(%d%d?%d?%d?%d?%d?):(%d%d?%d?%d?):(%d%d?%d?%d?)$")
      count = count + 1
      if not id or count > C.MAX_JOBS then
        return nil
      end
      skill, max = tonumber(skill), tonumber(max)
      if skill > C.MAX_SKILL or max > C.MAX_SKILL or skill > max then
        return nil
      end
      local slug = JOB_BY_ID[tonumber(id)]
      if slug then
        list[#list + 1] = { id = tonumber(id), name = R.Name(slug), skill = skill, max = max }
      end
    end
  end
  return list
end

-- Payload of PS and PR (version 2).
function C.EncodeStats(ilvl)
  return tostring(whole(ilvl, C.MAX_ILVL))
end

function C.EncodeJobs(jobs)
  return jobsText(jobs)
end

function C.DecodeStats(payload)
  local text = type(payload) == "string" and payload:match("^(%d%d?%d?%d?)$")
  local ilvl = text and tonumber(text)
  return ilvl and ilvl <= C.MAX_ILVL and ilvl or nil
end

function C.DecodeJobs(payload)
  return type(payload) == "string" and #payload <= C.MAX_LENGTH and parseJobs(payload) or nil
end

-- Version 1: "D|1|ilvl|id:skill:max,..." for the own data.
function C.Encode(ilvl, jobs)
  return string.format("D|%d|%d|%s", C.VERSION, whole(ilvl, C.MAX_ILVL), jobsText(jobs))
end

-- { kind = "H" | "Q" } or { kind = "D", ilvl, professions = { { id, name, skill, max } } }; nil for
-- anything that is not exactly the format.
function C.Decode(text)
  if type(text) ~= "string" or #text < 3 or #text > C.MAX_LENGTH then
    return nil
  end
  local kind, version, rest = text:match("^([HQD])|(%d%d?%d?)(.*)$")
  if not kind or tonumber(version) ~= C.VERSION then
    return nil
  end
  if kind ~= "D" then
    return rest == "" and { kind = kind } or nil
  end
  local ilvl, jobs = rest:match("^|(%d%d?%d?%d?)|([%d:,]*)$")
  if not ilvl or tonumber(ilvl) > C.MAX_ILVL then
    return nil
  end
  local list = parseJobs(jobs)
  if not list then
    return nil
  end
  return { kind = "D", ilvl = tonumber(ilvl), professions = list }
end

-- Sending ---------------------------------------------------------------------------------------

-- Channel of the current group, nil when there is none (or the client cannot tell).
function C.GroupChannel()
  local inGroup = g("IsInGroup")
  if type(inGroup) ~= "function" or try(inGroup) ~= true then
    return nil
  end
  local instance = g("LE_PARTY_CATEGORY_INSTANCE")
  if instance and try(inGroup, instance) == true then
    return "INSTANCE_CHAT"
  end
  return try(g("IsInRaid")) == true and "RAID" or "PARTY"
end

-- Own item level (equipped) and professions, as far as the client and the roster know them.
local function ownData()
  local own = ns.Peers.Get(PN.Self())
  local get = g("GetAverageItemLevel")
  local ok, overall, equipped = pcall(type(get) == "function" and get or function() end)
  local ilvl = ok and (tonumber(equipped) or tonumber(overall)) or nil
  if not (ilvl and ilvl > 0) then
    ilvl = own and own.ilvl
  end
  return ilvl, own and own.professions
end

local function channelOf(aud)
  if aud == "group" then
    return C.GroupChannel()
  end
  return try(g("IsInGuild")) == true and "GUILD" or nil
end

-- The own data to one audience: what each function may send, v2 first, then the old format for
-- users of older versions. Unchanged data is not repeated unless `force`. `only` names one function: the answer
-- to its probe sends that one alone and no old format. Returns true when something was queued, else false,
-- the reason and for "wait" the seconds left.
local function announce(aud, force, priority, gap, only)
  local channel = channelOf(aud)
  if not channel then
    return false, "no-channel"
  end
  local now = clock()
  gap = gap or (aud == "guild" and C.GUILD_GAP or C.ANNOUNCE_GAP)
  local last = lastAt[channel]
  if last and last <= now and now - last < gap then
    return false, "wait", gap - (now - last)
  end
  local ilvl, jobs = ownData()
  local payload = {}
  if ilvl and ilvl > 0 then
    payload.peerStats = C.EncodeStats(ilvl)
  end
  local text = jobsText(jobs)
  if text ~= "" then
    payload.professions = text
  end
  local queued = false
  for _, fn in ipairs(FUNCS) do
    local data, key = payload[fn], channel .. fn
    if data and (only == nil or only == fn) and Consent.Allows(fn, "send", aud) and (force or lastText[key] ~= data) then
      if Comm.Send(fn, "D", data, aud, nil, { priority = priority }) then
        lastText[key], queued = data, true
      end
    end
  end
  if not queued then
    return false, "nothing"
  end
  lastAt[channel] = now
  if only then
    return true
  end
  Comm.SendLegacy(C.PREFIX, aud, FUNCS, function(allowed)
    local oldIlvl, oldJobs = ownData()
    return C.Encode(allowed.peerStats and oldIlvl or nil, allowed.professions and oldJobs or nil)
  end, { priority = priority })
  return true
end

-- The answer to a probe of one function: its data to the guild now. Returns true, or false and why.
function C.Answer(fn)
  if not Consent.Allows(fn, "send", "guild") then
    return false, "consent"
  end
  return announce("guild", true, "reply", 0, fn)
end

local arm

local function fire(aud)
  local mode = due[aud]
  due[aud] = nil
  if not mode then
    return
  end
  local ok, why, left = announce(aud, mode ~= "change", "background", mode == "switch" and C.SWITCH_GAP or nil)
  if not ok and why == "wait" and left then
    due[aud] = mode
    arm(aud, left + 1)
  end
end

-- One timer per audience; a trigger while it runs only raises the mode ("force" beats "change").
arm = function(aud, delay)
  if pending[aud] then
    return
  end
  local timer = g("C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  pending[aud] = true
  local ok = pcall(timer.After, delay, function()
    pending[aud] = nil
    -- A client that runs the timer at once must not loop on the "wait" answer.
    depth = depth + 1
    if depth <= 2 then
      ns.Safe("peercomm", fire, aud)
    end
    depth = depth - 1
  end)
  if not ok then
    pending[aud] = nil
  end
end

-- Modes by weight: "change" (only what differs), "force" (everything, long gap), "switch" (everything, short gap,
-- after the player switched sending on).
local WEIGHT = { change = 1, force = 2, switch = 3 }

local function schedule(aud, mode)
  if (WEIGHT[due[aud]] or 0) < WEIGHT[mode] then
    due[aud] = mode
  end
  if mode == "switch" then
    arm(aud, C.random(C.SWITCH_MIN, C.SWITCH_MAX))
  else
    arm(aud, C.random(C.DELAY_MIN, C.DELAY_MAX))
  end
end

-- Button "Refresh": announces the own data again, only with the presence switch for the audience.
-- Returns true when something was queued, else false and the reason (consent, wait, nothing, ...).
function C.Refresh(aud)
  local reason = "consent"
  local list = aud and { aud } or AUDIENCES
  local sent = false
  for _, a in ipairs(list) do
    if (a == "group" or a == "guild") and Consent.Allows("presenceMark", "send", a) then
      local ok, why = announce(a, true, "click", C.ANNOUNCE_GAP)
      sent, reason = sent or ok, ok and reason or why
    end
  end
  return sent, not sent and reason or nil
end

-- Receiving -------------------------------------------------------------------------------------

local function store(name, fn, patch)
  local key, now = PN.Key(name), clock()
  heard[key] = now
  if fn == "v1" then
    if heardV2[key] and now - heardV2[key] < C.V1_QUIET then
      return
    end
  else
    heardV2[key] = now
  end
  local gapKey = fn .. key
  if lastData[gapKey] and now - lastData[gapKey] < C.DATA_GAP then
    return
  end
  lastData[gapKey] = now
  if ns.SeenPlayers.Enabled() and ns.Peers.Receive(name, patch) then
    ns.Emit("FG_SEEN_UPDATE")
  end
end

-- Comm has asked for the receive consent of the function before any of this runs.
local function onStats(name, ilvl)
  if ilvl > 0 then
    store(name, "peerStats", { ilvl = ilvl })
  end
end

local function onJobs(name, list)
  if #list > 0 then
    store(name, "professions", { professions = list })
  end
end

-- Old format: H and Q never lead to anything, D is read for the functions that may be received.
local function onLegacy(text, name, info)
  local msg = C.Decode(text)
  if not msg or msg.kind ~= "D" then
    return
  end
  local patch = {}
  if info.allowed.peerStats and msg.ilvl > 0 then
    patch.ilvl = msg.ilvl
  end
  if info.allowed.professions and #msg.professions > 0 then
    patch.professions = msg.professions
  end
  if next(patch) then
    store(name, "v1", patch)
  end
end

-- true for a few seconds after joining a group while a member has not announced yet and the
-- player listens at all.
function C.Waiting(name)
  return joinedAt ~= nil
    and members >= 2
    and clock() - joinedAt < C.ASK_WINDOW
    and heard[PN.Key(name)] == nil
    and (Consent.Allows("peerStats", "receive", "group") or Consent.Allows("professions", "receive", "group"))
end

-- Forgets what other users of the add-on delivered for one function.
local function purge(fn)
  local field = STORE_FIELD[fn]
  if field and ns.Peers.PurgeSource("addon", { field }) > 0 then
    ns.Emit("FG_SEEN_UPDATE")
  end
  heard, heardV2, lastData = {}, {}, {}
end

local function joined()
  joinedAt = clock()
  if C.Waiting("") then
    local timer = g("C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
      -- The page shows "reading" while we wait; it needs a push when the wait is over.
      pcall(timer.After, C.ASK_WINDOW + 1, function()
        ns.Emit("FG_SEEN_UPDATE")
      end)
    end
  end
  schedule("group", "force")
end

-- Group size changes: the step from alone to grouped is the join, a bigger group is told again.
function C.OnRoster()
  local before = members
  members = tonumber(try(g("GetNumGroupMembers"))) or 0
  if members < 2 then
    members, joinedAt = 0, nil
    heard, lastData, due.group = {}, {}, nil
  elseif before < 2 then
    joined()
  elseif members > before then
    schedule("group", "force")
  end
end

-- Own data may have changed: tell the audiences that exist, but only what really differs.
local function onDataChanged()
  if members >= 2 then
    schedule("group", "change")
  end
  if try(g("IsInGuild")) == true then
    schedule("guild", "change")
  end
end

ns.On("GROUP_ROSTER_UPDATE", C.OnRoster)
ns.On("PLAYER_LOGIN", C.OnRoster)
ns.On("PLAYER_ENTERING_WORLD", function(_, initial, reloading)
  C.OnRoster()
  if (initial == true or reloading == true) and try(g("IsInGuild")) == true then
    schedule("guild", "force")
  end
end)
-- The guild showed up after login (late status, join): the data that the login could not send goes out now.
ns.On("FG_SHARE_GUILD_READY", function()
  if lastAt.GUILD == nil and not due.guild then
    schedule("guild", "force")
  end
end)
ns.On("PLAYER_EQUIPMENT_CHANGED", onDataChanged)
ns.On("SKILL_LINES_CHANGED", onDataChanged)
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if not STORE_FIELD[fn] then
    return
  end
  if dir == "send" and value == true and (aud == "group" or aud == "guild") then
    if channelOf(aud) then
      schedule(aud, "switch")
    end
  elseif dir == "receive" and value ~= true then
    purge(fn)
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if STORE_FIELD[fn] then
    purge(fn)
  end
end)

-- Registration ----------------------------------------------------------------------------------

Comm.Register(
  "peerStats",
  ns.ShareSync.Attach("peerStats", {
    version = 1,
    audiences = AUDIENCES,
    on = { D = onStats },
    decode = C.DecodeStats,
  }, {
    answer = function()
      return C.Answer("peerStats")
    end,
  })
)
Comm.Register(
  "professions",
  ns.ShareSync.Attach("professions", {
    version = 1,
    audiences = AUDIENCES,
    on = { D = onJobs },
    decode = C.DecodeJobs,
  }, {
    answer = function()
      return C.Answer("professions")
    end,
  })
)
Comm.RegisterLegacy(C.PREFIX, { audiences = AUDIENCES, functions = FUNCS, handler = onLegacy })
-- The settings tab "Share" lists these two functions from now on.
for _, fn in ipairs(FUNCS) do
  Consent.MarkAvailable(fn)
end
