-- Data exchange between users of this add-on: professions and item level of other players over
-- addon messages (prefix "FGUIDES"), shown on the guild page through Peers (source "addon").
-- Protocol version 1, plain ASCII, always below 255 characters:
--   H|1                          hello (the sender has the add-on)
--   Q|1                          request: please send your data
--   D|1|<ilvl>|<id>:<skill>:<max>,...   data, at most 6 professions as skill line ids
-- Receiving always works and is checked strictly: a message that does not fit the format or the
-- ranges is dropped without a trace, and only members of the own group (or the own guild for the
-- GUILD channel) count. Sending needs settings.peerShare (opt-in, off by default), except the
-- request "Q", which carries no personal data. Nothing is sent in combat, at most BURST messages
-- per BURST_SPAN seconds, and one reply per sender and REPLY_GAP seconds.
local _, ns = ...
local PN, Guard, R = ns.PlayerName, ns.AutoGuard, ns.ProfessionRouteLogic

local C = {}
ns.PeerComm = C

C.PREFIX = "FGUIDES"
C.VERSION = 1
C.MAX_LENGTH = 255
C.MAX_ILVL = 2000
C.MAX_SKILL = 1000
C.MAX_JOBS = 6
C.REPLY_GAP = 60
C.DATA_GAP = 2
C.BURST = 5
C.BURST_SPAN = 10
C.GUILD_GAP = 1800
C.ASK_WINDOW = 15
local GUILD_DELAY = 15
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- Skill line id -> route slug, the professions the add-on can name in both languages.
local JOB_BY_ID = {}
for slug, def in pairs(R.PROFESSIONS) do
  JOB_BY_ID[def.id] = slug
end

local sent = {} -- send times inside the burst window
local replied, lastData, heard = {}, {}, {}
local askedAt, guildAt
local members = 0

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

-- "D|1|ilvl|id:skill:max,..." for the own data. Professions the add-on has no id for are left out.
function C.Encode(ilvl, jobs)
  local parts = {}
  for _, p in ipairs(type(jobs) == "table" and jobs or {}) do
    local slug = R.SlugOf(p)
    if slug and #parts < C.MAX_JOBS then
      local skill = whole(p.skill, C.MAX_SKILL)
      parts[#parts + 1] =
        string.format("%d:%d:%d", R.PROFESSIONS[slug].id, skill, math.max(skill, whole(p.max, C.MAX_SKILL)))
    end
  end
  return string.format("D|%d|%d|%s", C.VERSION, whole(ilvl, C.MAX_ILVL), table.concat(parts, ","))
end

-- { kind = "H" | "Q" } or { kind = "D", ilvl, professions = { { id, name, skill, max } } }; nil for
-- anything that is not exactly the format. A profession id the add-on does not know is skipped.
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
  return { kind = "D", ilvl = tonumber(ilvl), professions = list }
end

-- Sending ---------------------------------------------------------------------------------------

function C.Sharing()
  return ns.db ~= nil and ns.db.settings.peerShare == true
end

function C.SharingGuild()
  return ns.db ~= nil and ns.db.settings.peerShareGuild ~= false
end

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

-- One message out, false when the client has no API, we are in combat or the burst limit is reached.
local function post(text, channel)
  local api = g("C_ChatInfo")
  if type(api) ~= "table" or type(api.SendAddonMessage) ~= "function" or #text > C.MAX_LENGTH or Guard.Blocked() then
    return false
  end
  local now = clock()
  for i = #sent, 1, -1 do
    if now - sent[i] >= C.BURST_SPAN or sent[i] > now then
      table.remove(sent, i)
    end
  end
  if #sent >= C.BURST then
    return false
  end
  sent[#sent + 1] = now
  return (pcall(api.SendAddonMessage, C.PREFIX, text, channel))
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

local function sendData(channel)
  return post(C.Encode(ownData()), channel)
end

local function hello(channel)
  return post(string.format("H|%d", C.VERSION), channel)
end

-- Joined a group (or the sharing was switched on in one): ask the others, and with the opt-in say
-- hello and hand over the own data. Later joiners do the same on their side, nobody answers them.
function C.Join()
  local channel = C.GroupChannel()
  if not channel then
    return
  end
  askedAt = clock()
  local timer = g("C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    -- The page shows "reading" while we wait; it needs a push when the wait is over.
    pcall(timer.After, C.ASK_WINDOW + 1, function()
      ns.Emit("FG_SEEN_UPDATE")
    end)
  end
  post(string.format("Q|%d", C.VERSION), channel)
  if C.Sharing() then
    hello(channel)
    sendData(channel)
  end
end

-- The own data to the guild: once after the login and when the sharing is switched on, never more
-- often than every GUILD_GAP seconds. Nobody is asked, so a big guild does not answer in a crowd.
function C.AnnounceGuild()
  if not (C.Sharing() and C.SharingGuild()) or try(g("IsInGuild")) ~= true then
    return
  end
  local now = clock()
  if guildAt and now - guildAt < C.GUILD_GAP then
    return
  end
  if sendData("GUILD") then
    guildAt = now
  end
end

-- Receiving -------------------------------------------------------------------------------------

local function inMyGroup(name)
  return try(g("UnitInParty"), name) == true or try(g("UnitInRaid"), name) ~= nil
end

-- Only people of the own group (group channels) or the own guild (guild channel) are believed.
local function trusted(channel, sender, name)
  if channel == "GUILD" then
    return ns.Invites.IsGuildMember(sender, nil) == true
  end
  return inMyGroup(sender) or inMyGroup(name)
end

local function reply(name, channel)
  if not C.Sharing() then
    return
  end
  local key, now = PN.Key(name), clock()
  if replied[key] and now - replied[key] < C.REPLY_GAP then
    return
  end
  if sendData(channel) then
    replied[key] = now
  end
end

local function store(name, msg)
  local key, now = PN.Key(name), clock()
  heard[key] = now
  if lastData[key] and now - lastData[key] < C.DATA_GAP then
    return
  end
  lastData[key] = now
  if ns.SeenPlayers.Enabled() and ns.Peers.Receive(name, msg) then
    ns.Emit("FG_SEEN_UPDATE")
  end
end

-- CHAT_MSG_ADDON. Never raises, anything unexpected is ignored.
function C.OnAddon(prefix, text, channel, sender)
  if prefix ~= C.PREFIX or not (GROUP_CHANNELS[channel] or channel == "GUILD") then
    return
  end
  text, sender = Guard.Safe(text), Guard.Safe(sender)
  local msg = C.Decode(text)
  if not msg or type(sender) ~= "string" then
    return
  end
  local name = PN.Normalize(sender)
  if name == "" or PN.Equal(name, PN.Self()) or not trusted(channel, sender, name) then
    return
  end
  if msg.kind == "D" then
    store(name, msg)
  elseif channel ~= "GUILD" then
    reply(name, channel)
  end
end

-- true for a few seconds after joining a group while a member has not answered yet.
function C.Waiting(name)
  return askedAt ~= nil and members >= 2 and clock() - askedAt < C.ASK_WINDOW and heard[PN.Key(name)] == nil
end

-- Group size changes: the step from alone to grouped is the join.
function C.OnRoster()
  local before = members
  members = tonumber(try(g("GetNumGroupMembers"))) or 0
  if members < 2 then
    members, askedAt = 0, nil
    replied, lastData, heard = {}, {}, {}
  elseif before < 2 then
    C.Join()
  end
end

local api = g("C_ChatInfo")
if type(api) == "table" and type(api.RegisterAddonMessagePrefix) == "function" then
  pcall(api.RegisterAddonMessagePrefix, C.PREFIX)
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
  C.OnAddon(prefix, text, channel, sender)
end)
ns.On("GROUP_ROSTER_UPDATE", C.OnRoster)
ns.On("PLAYER_LOGIN", C.OnRoster)
ns.On("PLAYER_ENTERING_WORLD", function(_, initial, reloading)
  C.OnRoster()
  local timer = g("C_Timer")
  if (initial == true or reloading == true) and type(timer) == "table" and type(timer.After) == "function" then
    pcall(timer.After, GUILD_DELAY, function()
      ns.Safe("peercomm", C.AnnounceGuild)
    end)
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path, value)
  if value == true and (path == "settings.peerShare" or path == "settings.peerShareGuild") then
    C.AnnounceGuild()
    if path == "settings.peerShare" then
      C.Join()
    end
  end
end)
