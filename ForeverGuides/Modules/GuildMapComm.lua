-- Guild map, data part: sends the own position to the guild and receives the positions of guild
-- members into GuildMapStore. No frame, no map display. Opt-in through ns.Consent ("guildMap", audience
-- guild, send and receive are separate), the line is ns.Comm (function GM, payloads of GuildSyncCodec).
--   Sending    only with the send consent, in a guild, not hidden (settings.guildMapInvisible), not in
--              combat, not in an instance or battleground, not AFK, with a readable position. A message
--              goes out when GuildSyncLogic.SendReason says so: the first one, a new map, a move of
--              enough yards after the gap, or the heartbeat. The gap and the heartbeat grow with the
--              number of senders heard lately; whoever only receives stays silent. The pace is checked
--              once a second by a timer that runs only while sending is possible at all.
--              settings.guildMapAccuracy: "exact", "grid" (rounded to 5 percent of the map) or "zone".
--   Receiving  intake gate (flood, rate per sender), sender must be on the guild roster, plausible map,
--              then GuildMapStore. Receiving never sends anything.
--   Withdrawal one end message X after the last position: when the player turns invisible, enters an
--              instance or goes AFK, when send is switched off and when the consent is withdrawn. After
--              that nothing is sent. X goes out as a farewell of ns.Comm, which needs no send consent but
--              a position that really went out before (Comm.lua, head).
local _, ns = ...
local Comm, Consent, PN, L, G = ns.Comm, ns.Consent, ns.PlayerName, ns.GuildSyncLogic, ns.GuildSyncCodec

local GM = {}
ns.GuildMapComm = GM

GM.FN = "guildMap"
-- Seconds between two looks at the pace, and the extra random wait (1 to n) before the first message
-- after login, a switch or an area change, so a guild does not speak in one second.
GM.TICK = 1
GM.SPREAD = 4
-- Maps of these types are no place: Cosmic and World (UIMapType 0 and 1).
GM.MAX_NO_PLACE_TYPE = 1
-- Replaceable in tests: random number from 0 to 1.
function GM.random()
  return math.random()
end

local MODES = { exact = true, grid = true, zone = true }
local REASON_PAUSE = "i"

local heard = L.NewHeard(function()
  return Comm.clock()
end)
local grid = assert(L.NewSendGrid(function()
  return Comm.clock()
end, GM.FN))
local intake = assert(L.NewIntake(function()
  return Comm.clock()
end))

-- last: the position of the last message { map, x, y, at, beatIn }. announced: a position went out and
-- no end message since. resumeAt: no message before this time. paused: why sending stands still.
local last, announced, resumeAt, paused = nil, false, 0, nil
local ticking, depth = false, 0

local function g(name)
  return rawget(_G, name)
end

local function clock()
  return Comm.clock()
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

local function settings()
  return ns.db and ns.db.settings or {}
end

local function inGuild()
  return try(g("IsInGuild")) == true
end

-- Settings ---------------------------------------------------------------------------------------------

function GM.Hidden()
  return settings().guildMapInvisible == true
end

-- Missing value: exact (the default). Anything damaged: the coarsest mode, never the finest.
function GM.Accuracy()
  local mode = settings().guildMapAccuracy
  if mode == nil then
    return "exact"
  end
  return MODES[mode] and mode or "zone"
end

-- True while sending is possible at all: consent, a guild, not hidden.
function GM.Active()
  return Consent.Allows(GM.FN, "send", "guild") and not GM.Hidden() and inGuild()
end

-- Why nothing is read or sent right now: "combat", "instance", "afk", or nil.
local function pauseReason()
  local guard = ns.AutoGuard
  if (guard and guard.Blocked()) or ns.InCombat() then
    return "combat"
  end
  if try(g("IsInInstance")) == true then
    return "instance"
  end
  if try(g("UnitIsAFK"), "player") == true then
    return "afk"
  end
end

-- Position ---------------------------------------------------------------------------------------------

-- map, x, y (fractions 0..1) of the player, or nil. A value the client hides (secret values of retail 12)
-- or anything out of range ends the read: values are never guessed.
local function readPosition()
  local wp, guard = ns.Waypoints, ns.AutoGuard
  if not (wp and guard and type(wp.PlayerPosition) == "function") then
    return nil
  end
  local ok, map, x, y = pcall(wp.PlayerPosition)
  if not ok then
    return nil
  end
  map, x, y = guard.Safe(map), guard.Safe(x), guard.Safe(y)
  local WL = ns.WaypointLogic
  if not (WL.finite(map) and WL.finite(x) and WL.finite(y)) then
    return nil
  end
  if map ~= math.floor(map) or map < 1 or map > G.LIMITS.MAX_MAP or x < 0 or x > 1 or y < 0 or y > 1 then
    return nil
  end
  return map, x, y
end

-- Yards between two records { map, x, y }, nil when the game cannot tell.
local function dist(a, b)
  local WL = ns.WaypointLogic
  return WL.distanceYards(a.map, a.x, a.y, b.map, b.x, b.y)
end

-- The payload for the position in the chosen accuracy and the record of what it says. The pace is judged
-- on that record, so a coarse mode does not send more often than its picture changes.
local function prepare(map, x, y)
  local msg = { typ = "P", map = map, x = G.Promille(x), y = G.Promille(y), mode = GM.Accuracy() }
  local payload = G.Encode(GM.FN, msg)
  if not payload then
    return nil
  end
  local back = G.Decode(GM.FN, "P", payload)
  if not back then
    return nil
  end
  return payload, { map = back.map, x = (back.x or 0) / 1000, y = (back.y or 0) / 1000 }
end

-- Sending ----------------------------------------------------------------------------------------------

local function nextBeat()
  return L.NextBeat(heard.Count(), GM.random)
end

-- One end message with reason w (withdrawn), h (hidden) or i (pause). Nothing goes out when no position
-- was announced. `final`: the state is cleared whatever the line answers (no later try).
-- Returns true when the message was queued.
function GM.Retract(reason, final)
  if not announced then
    return false, "quiet"
  end
  local payload = G.Encode(GM.FN, { typ = "X", reason = reason })
  local sent, why = false, "payload"
  if payload then
    if grid.Allow("X") then
      sent, why = Comm.Send(GM.FN, "X", payload, "guild")
    else
      why = "throttle"
    end
  end
  if sent or final then
    announced, last = false, nil
  end
  return sent == true, why
end

local function sendPosition(t)
  local map, x, y = readPosition()
  if not map then
    return
  end
  local payload, cur = prepare(map, x, y)
  if not payload then
    return
  end
  local reason = L.SendReason(last, cur, t, heard.Count(), dist)
  if not reason or not grid.Allow("P") then
    return
  end
  if Comm.Send(GM.FN, "P", payload, "guild", nil, { priority = "background" }) then
    cur.at, cur.beatIn = t, nextBeat()
    last, announced = cur, true
  else
    resumeAt = t + L.CONFIG.move.resume
  end
end

-- One look at the pace.
local function step()
  local t = clock()
  local why = pauseReason()
  if why then
    paused = why
    -- A fight cannot send anything; instance and AFK say goodbye once.
    if why ~= "combat" then
      GM.Retract(REASON_PAUSE)
    end
    resumeAt = t + L.CONFIG.move.resume
    return
  end
  paused = nil
  if t >= resumeAt then
    sendPosition(t)
  end
end

local arm

local function tick()
  ticking = false
  if not GM.Active() then
    return
  end
  step()
  arm()
end

-- One timer at a time, only while sending is possible.
arm = function()
  if ticking or not GM.Active() then
    return
  end
  local timer = g("C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  ticking = true
  local ok = pcall(timer.After, GM.TICK, function()
    -- A client that runs the timer at once must not loop.
    depth = depth + 1
    if depth <= 2 then
      ns.Safe("guildmap", tick)
    else
      ticking = false
    end
    depth = depth - 1
  end)
  if not ok then
    ticking = false
  end
end

-- Silence for a few seconds with a random part, then the next position goes out.
local function delayed()
  resumeAt = clock() + L.CONFIG.move.resume + math.floor(GM.random() * GM.SPREAD)
end

-- Starts the pace (switched on, login, left the hidden state). The first message is spread.
local function start()
  if GM.Active() then
    last = nil
    delayed()
    arm()
  end
end

-- Stops what is running: the pace forgets the last position and the heard senders.
local function stop()
  last, paused = nil, nil
  heard.Clear()
end

-- Area change: the new map is announced at once (subject to the minimum gap of SendReason).
local function onArea()
  if GM.Active() then
    arm()
    if clock() >= resumeAt then
      ns.Safe("guildmap", step)
    end
  end
end

-- Receiving --------------------------------------------------------------------------------------------

-- A map the game knows and that is a place (zone or below), never the cosmos or the world map. A client
-- without the API cannot tell, the display decides then.
local function knownMap(map)
  local api = g("C_Map")
  if type(api) ~= "table" or type(api.GetMapInfo) ~= "function" then
    return true
  end
  local info = try(api.GetMapInfo, map)
  if type(info) ~= "table" or type(info.mapType) ~= "number" then
    return false
  end
  return info.mapType > GM.MAX_NO_PLACE_TYPE
end

-- Sender on the guild roster and consent to receive, the checks that stand in front of the store.
local function trusted(sender)
  local inv = ns.Invites
  return Consent.Allows(GM.FN, "receive", "guild") and inv ~= nil and inv.IsGuildMember(sender, nil) == true
end

-- Payload of P or X. The type tells which one it is, the handlers check it.
local function decode(payload)
  return G.Decode(GM.FN, "P", payload) or G.Decode(GM.FN, "X", payload)
end

local function onPosition(sender, msg)
  if type(msg) ~= "table" or msg.typ ~= "P" or not trusted(sender) then
    return
  end
  local key = PN.Key(sender)
  if not intake.Allow("P", key) or not knownMap(msg.map) then
    return
  end
  if ns.GuildMapStore.Put(sender, msg) then
    heard.Note(key)
  end
end

local function onEnd(sender, msg)
  if type(msg) ~= "table" or msg.typ ~= "X" or not trusted(sender) then
    return
  end
  if intake.Allow("X", PN.Key(sender)) then
    ns.GuildMapStore.Remove(sender)
  end
end

-- Pace and heard senders, for the status line and the tests.
function GM.Status()
  return {
    active = GM.Active(),
    paused = paused,
    announced = announced,
    heard = heard.Count(),
    gap = L.Gap(heard.Count()),
    lastAt = last and last.at or nil,
  }
end

-- Events ----------------------------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", start)
ns.On("PLAYER_ENTERING_WORLD", function()
  if not inGuild() then
    stop()
  elseif not ticking then
    -- Login before the guild was known. A loading screen needs no wait: the position is nil until it ends.
    start()
  end
end)
ns.On("ZONE_CHANGED_NEW_AREA", onArea)
-- Leaving the guild: there is nobody left to tell.
ns.On("PLAYER_GUILD_UPDATE", function()
  if not inGuild() then
    announced = false
    stop()
  end
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if fn ~= GM.FN or aud ~= "guild" then
    return
  end
  if dir == "send" then
    if value == true then
      start()
    else
      -- The consent is already false here: the end message goes out as a farewell of the line.
      GM.Retract("w", true)
      stop()
    end
  elseif value ~= true then
    heard.Clear()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == GM.FN then
    GM.Retract("w", true)
    stop()
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path, value, scope)
  if scope == "char" then
    return
  end
  if path == "settings.guildMapInvisible" then
    if value == true then
      GM.Retract("h")
      stop()
    else
      start()
    end
  elseif path == "settings.guildMapAccuracy" then
    -- The next position says the new accuracy at once.
    last = nil
    delayed()
  end
end)

-- Registration ----------------------------------------------------------------------------------------

Comm.Register(GM.FN, {
  version = 1,
  audiences = { "guild" },
  on = { P = onPosition, X = onEnd },
  decode = decode,
  farewell = "X",
})

if Consent.MarkAvailable then
  Consent.MarkAvailable(GM.FN)
end
