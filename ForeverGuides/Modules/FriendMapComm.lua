-- Friends map, data part: sends the own position to online friends who run the add-on and receives theirs into
-- GuildMapStore. No frame, no map display. Opt-in through ns.Consent ("friendMap") with one audience per route:
-- "friends" for character friends (add-on whispers, store source "friends") and "bnfriends" for Battle.net friends
-- (kind bnet, source "bnfriends"), send and receive separate for each. The line is ns.Comm (function FM, kinds
-- whisper and bnet, the payloads of GuildSyncCodec for P and X).
--   Finding    friends are read by FriendRoster. A hello H (one letter: s sends, r receives, b both) goes to each friend
--              that comes online and to all friends when a switch changes, a few per tick; the answer A carries the same
--              letter. Both need the send or the receive consent. Nothing goes to a friend that never answered.
--   Sending    only with the send consent, not hidden (settings.guildMapInvisible), not in combat, not in an instance,
--              raid or battleground, not AFK, to friends that said they receive. The pace is the one of the guild map
--              (GuildSyncLogic.SendReason): a new map, a move, the heartbeat. Battle.net first (BNSendGameData, when the
--              client has it and Battle.net sending is on), else an add-on whisper when friends sending is on.
--   Receiving  receive consent of the route the message came on, the sender must be an online friend of that list
--              (Comm checks it again through whisperPeer), the intake gate of the guild map (flood, rate per sender), a known map, then the store.
--   Withdrawal one end message X to every friend that got a position, when the player turns invisible, enters an
--              instance, goes AFK or switches sending off.
local _, ns = ...
local Comm, Consent, PN, L, G = ns.Comm, ns.Consent, ns.PlayerName, ns.GuildSyncLogic, ns.GuildSyncCodec
local GM, FR = ns.GuildMapComm, ns.FriendRoster

local F = {}
ns.FriendMapComm = F

F.FN = "friendMap"
-- Consent audience (and store source) per route; the order is the preference.
F.AUDS = { bnet = "bnfriends", whisper = "friends" }
local ROUTES = { "bnet", "whisper" }
-- Seconds between two looks at the pace, hellos sent per look, and the most friends one position goes to.
F.TICK = 2
F.HELLOS = 2
F.MAX_TARGETS = 20
-- Seconds before the same friend gets another hello, and before the same friend may make us answer or be heard again.
F.HELLO_GAP = 120
F.HEAR_GAP = 10
-- Replaceable in tests: random number from 0 to 1.
function F.random()
  return math.random()
end

local grid = assert(L.NewSendGrid(function()
  return Comm.clock()
end, F.FN))
local intake = assert(L.NewIntake(function()
  return Comm.clock()
end))

-- peers[key] = { via, bnet = { listens, sends }, whisper = { ... } }: friends that answered, per route. sentTo[key] = kind: got a position since the last end
-- message. helloAt / heardAt: last hello sent to / heard from a friend. pending: keys waiting for a hello.
local peers, sentTo, helloAt, heardAt, pending, queued = {}, {}, {}, {}, {}, {}
local last, announced, resumeAt, paused = nil, false, 0, nil
local ticking, depth = false, 0

local function g(name)
  return rawget(_G, name)
end

local function clock()
  return Comm.clock()
end

-- Switches of one route ("bnet" or "whisper").
local function sending(kind)
  return Consent.Allows(F.FN, "send", F.AUDS[kind])
end

local function listening(kind)
  return Consent.Allows(F.FN, "receive", F.AUDS[kind])
end

-- True while anything runs: a hello is worth sending as soon as one direction of one route is on.
function F.Enabled()
  for _, kind in ipairs(ROUTES) do
    if sending(kind) or listening(kind) then
      return true
    end
  end
  return false
end

-- True while positions may go out at all: the send consent of a route and not invisible.
function F.Active()
  return (sending("bnet") or sending("whisper")) and not GM.Hidden()
end

local function letter(kind)
  if sending(kind) and listening(kind) then
    return "b"
  end
  return sending(kind) and "s" or "r"
end

local function reach(f, kind)
  if kind == "bnet" then
    return f.bn
  end
  return f.whisper
end

-- The ways to a friend, best first: Battle.net when the client has it, then a whisper. Only routes whose list holds
-- the friend and whose switch is on (`need` "send" for positions, "any" for a hello: send or receive).
local function routes(f, need)
  local out = {}
  for _, kind in ipairs(ROUTES) do
    local target = reach(f, kind)
    local on = sending(kind) or (need ~= "send" and listening(kind))
    if target and on and (kind ~= "bnet" or type(g("BNSendGameData")) == "function") then
      out[#out + 1] = { kind = kind, target = target }
    end
  end
  return out
end

-- Hello and answer ---------------------------------------------------------------------------------

local function queueHello(key)
  if not F.Enabled() or queued[key] then
    return
  end
  local t = clock()
  if helloAt[key] and t - helloAt[key] < F.HELLO_GAP then
    return
  end
  queued[key] = true
  pending[#pending + 1] = key
end

local function helloStep(t)
  for _ = 1, F.HELLOS do
    local key = table.remove(pending, 1)
    if not key then
      return
    end
    queued[key] = nil
    local f = FR.Get(key)
    for _, r in ipairs(f and routes(f, "any") or {}) do
      if Comm.Send(F.FN, "H", letter(r.kind), r.kind, r.target, { priority = "background" }) then
        helloAt[key] = t
      end
    end
  end
end

local function onHello(sender, msg, meta)
  if type(msg) ~= "table" or (msg.typ ~= "H" and msg.typ ~= "A") or not FR.IsFriend(sender) then
    return
  end
  local via = type(meta) == "table" and (meta.aud == "bnet" or meta.aud == "whisper") and meta.aud or nil
  if not via or not FR.InList(sender, via) then
    return
  end
  local key, t = PN.Key(sender), clock()
  local heard = key .. ":" .. via
  if heardAt[heard] and t - heardAt[heard] < F.HEAR_GAP then
    return
  end
  heardAt[heard] = t
  local peer = peers[key] or {}
  peers[key] = peer
  peer.via = via
  peer[via] = { listens = msg.flags == "r" or msg.flags == "b", sends = msg.flags == "s" or msg.flags == "b" }
  if peer[via].listens and sending(via) then
    -- The new listener gets the position with the next look.
    last = nil
  end
  if msg.typ == "H" then
    local f = FR.Get(key)
    local target = f and reach(f, via)
    if target and Comm.Send(F.FN, "A", letter(via), via, target, { priority = "reply" }) then
      helloAt[key] = t
    end
  end
end

-- Sending ------------------------------------------------------------------------------------------

-- Friends that said they receive, with the best way to them: a route with the send switch on that the friend
-- listens on.
local function listeners()
  local out = {}
  for _, f in ipairs(FR.List()) do
    local peer = peers[f.key]
    for _, r in ipairs(peer and routes(f, "send") or {}) do
      if peer[r.kind] and peer[r.kind].listens then
        out[#out + 1] = { key = f.key, kind = r.kind, target = r.target }
        break
      end
    end
    if #out >= F.MAX_TARGETS then
      break
    end
  end
  return out
end

-- One end message (reason w withdrawn, h hidden, i pause) to everybody who got a position, on the route the position
-- went. `only`: just that route (its send switch went off), the others keep their state. `final`: the state is
-- cleared whatever the line answers. Returns how many messages were queued.
function F.Retract(reason, final, only)
  if not announced then
    return 0
  end
  local payload, n = G.Encode(GM.FN, { typ = "X", reason = reason }), 0
  local done = {}
  if payload and grid.Allow("X") then
    for key, kind in pairs(sentTo) do
      local f = FR.Get(key)
      local target = f and reach(f, kind)
      if (only == nil or only == kind) and target and Comm.Send(F.FN, "X", payload, kind, target) then
        n = n + 1
        done[key] = true
      end
    end
  end
  for key, kind in pairs(sentTo) do
    if (only == nil or only == kind) and (done[key] or final) then
      sentTo[key] = nil
    end
  end
  if next(sentTo) == nil and (n > 0 or final) then
    announced, last = false, nil
  end
  return n
end

local function sendPosition(t)
  local map, x, y = GM.ReadPosition()
  if not map then
    return
  end
  local payload, cur = GM.Prepare(map, x, y)
  local targets = payload and listeners() or {}
  if #targets == 0 then
    return
  end
  local reason = L.SendReason(last, cur, t, 0, GM.Dist)
  if not reason or not grid.Allow("P") then
    return
  end
  -- A newer position replaces one that still waits.
  for _, kind in ipairs(ROUTES) do
    Comm.Purge(F.FN, F.AUDS[kind], "send")
  end
  local sent = false
  for _, target in ipairs(targets) do
    if Comm.Send(F.FN, "P", payload, target.kind, target.target, { priority = "background" }) then
      sentTo[target.key], sent = target.kind, true
    end
  end
  if sent then
    cur.at, cur.beatIn = t, L.NextBeat(0, F.random)
    last, announced = cur, true
  else
    resumeAt = t + L.CONFIG.move.resume
  end
end

local function step()
  local t = clock()
  helloStep(t)
  if not F.Active() then
    paused = nil
    return
  end
  local why = GM.PauseReason()
  if why then
    paused = why
    -- A fight sends nothing; an instance or AFK says goodbye once.
    if why ~= "combat" then
      F.Retract("i")
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
  if not F.Enabled() then
    return
  end
  step()
  arm()
end

-- One timer at a time, only while something is switched on.
arm = function()
  if ticking or not F.Enabled() then
    return
  end
  local timer = g("C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  ticking = true
  local ok = pcall(timer.After, F.TICK, function()
    -- A client that runs the timer at once must not loop.
    depth = depth + 1
    if depth <= 2 then
      ns.Safe("friendmap", tick)
    else
      ticking = false
    end
    depth = depth - 1
  end)
  if not ok then
    ticking = false
  end
end

-- Hello to every friend online; the pace of helloStep spreads them.
local function helloAll()
  helloAt = {}
  for _, f in ipairs(FR.List()) do
    queueHello(f.key)
  end
end

local function forget()
  peers, sentTo, helloAt, heardAt, pending, queued = {}, {}, {}, {}, {}, {}
  last, paused = nil, nil
end

-- Receiving ----------------------------------------------------------------------------------------

-- P and X carry the payloads of the guild map; H and A one letter.
local function decode(payload, typ)
  if typ == "H" or typ == "A" then
    if payload == "s" or payload == "r" or payload == "b" then
      return { typ = typ, flags = payload }
    end
    return nil
  end
  return G.Decode(GM.FN, typ, payload)
end

-- The route a message came on, when the list of that route holds the sender and its receive switch is on.
local function heardOn(sender, meta)
  local kind = type(meta) == "table" and meta.aud or nil
  if (kind == "bnet" or kind == "whisper") and listening(kind) and FR.InList(sender, kind) then
    return kind
  end
end

local function onPosition(sender, msg, meta)
  local kind = heardOn(sender, meta)
  if type(msg) ~= "table" or msg.typ ~= "P" or not kind then
    return
  end
  if not intake.Allow("P", PN.Key(sender)) or not GM.KnownMap(msg.map) then
    return
  end
  ns.GuildMapStore.Put(sender, msg, F.AUDS[kind])
end

local function onEnd(sender, msg, meta)
  local kind = type(meta) == "table" and meta.aud or nil
  if type(msg) ~= "table" or msg.typ ~= "X" or not F.AUDS[kind] or not FR.InList(sender, kind) then
    return
  end
  if intake.Allow("X", PN.Key(sender)) then
    ns.GuildMapStore.Remove(sender, F.AUDS[kind])
  end
end

-- Pace and friends, for the status line and the tests.
function F.Status()
  local n = 0
  for _ in pairs(peers) do
    n = n + 1
  end
  return { active = F.Active(), paused = paused, announced = announced, peers = n, listeners = #listeners() }
end

-- Events --------------------------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", arm)
ns.On("PLAYER_ENTERING_WORLD", arm)
ns.On("ZONE_CHANGED_NEW_AREA", function()
  if F.Active() then
    arm()
    if clock() >= resumeAt then
      ns.Safe("friendmap", step)
    end
  end
end)
ns.On("FG_FRIEND_ONLINE", function(_, key)
  queueHello(key)
  arm()
end)
ns.On("FG_FRIENDS_UPDATE", function()
  for key in pairs(peers) do
    if not FR.Get(key) then
      peers[key], sentTo[key], helloAt[key] = nil, nil, nil
      heardAt[key .. ":bnet"], heardAt[key .. ":whisper"] = nil, nil
    end
  end
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if fn ~= F.FN then
    return
  end
  local kind
  for _, k in ipairs(ROUTES) do
    if F.AUDS[k] == aud then
      kind = k
    end
  end
  if not kind then
    return
  end
  if dir == "send" and value ~= true then
    -- The consent is already false here: the end message goes out as a farewell of the line.
    F.Retract("w", true, kind)
  end
  if F.Enabled() then
    last = nil
    resumeAt = clock() + L.CONFIG.move.resume
    helloAll()
    arm()
  else
    forget()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == F.FN then
    F.Retract("w", true)
    forget()
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path, value, scope)
  if scope == "char" then
    return
  end
  if path == "settings.guildMapInvisible" then
    if value == true then
      F.Retract("h")
      last = nil
    else
      resumeAt = clock() + L.CONFIG.move.resume
    end
  elseif path == "settings.guildMapAccuracy" then
    last = nil
  end
end)

-- Registration --------------------------------------------------------------------------------------

Comm.Register(F.FN, {
  version = 1,
  audiences = { "whisper", "bnet" },
  whisperAud = F.AUDS.whisper,
  on = { P = onPosition, X = onEnd, H = onHello, A = onHello },
  decode = decode,
  farewell = "X",
  anyTyp = { H = true, A = true },
  whisperPeer = function(name)
    return FR.IsFriend(name)
  end,
})

if Consent.MarkAvailable then
  Consent.MarkAvailable(F.FN)
end
