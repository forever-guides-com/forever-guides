-- The one line for add-on messages: the only module that registers a prefix, sends a message or
-- listens to CHAT_MSG_ADDON. Functions (PeerComm, later others) register here and never see the
-- game API. Rules, in this order:
--   Sending   consent for the function and audience (asked when queued and again when sent), then the
--             queue (click, answer, background; at most MAX_QUEUE, background waits at most TTL
--             seconds), the lock in combat and under addon restrictions, a token bucket per channel
--             kind, and the result code of the game is always read.
--   Receiving every argument through Guard.Safe, length, prefix, the envelope (CommLogic), consent
--             for receiving BEFORE anything else is done with the message (no consent: dropped
--             silently, never answered, never stored), the sender (not self, in the own group or
--             guild), a token bucket per sender, reassembly of blocks, then the handler.
-- Channel kinds: group (INSTANCE_CHAT, RAID or PARTY), guild, officer (the OFFICER channel, consent
-- audience "guild", only officers hear it), whisper (consent audience "chat") and channel (consent
-- audience "world", reserved, nothing uses it yet).
-- Farewell  One exception to the send consent: a function declares one farewell type (Register
--             def.farewell = "X") and may send it after its consent was taken back, because
--             FG_CONSENT_CHANGED comes after the switch. Rules: only this type, at most FAREWELL_MAX
--             characters, only into an audience this function really sent to in this session (never sent:
--             never a farewell, reason consent), one per audience until it sends again. Every other lock
--             still holds (combat, restrictions, bucket, API). It waits at reply priority (never before a
--             click, before background), at most TTL seconds, and survives Purge.
-- Whisper   Strangers can whisper, so a whisper is taken in only in two cases: (a) the answer to an own
--             open request (same function, same id, same sender; Register def.request names the request
--             type, sending it needs the receive consent, the window closes after OPEN_WAIT idle seconds
--             or Close), (b) a request to a function with a service (def.service(value) -> content id)
--             when the send consent holds, the content id was really shared in this session (ring of
--             the last SHARED_MAX ids, NoteShared) and the requester is inside the answer bucket. Every
--             other whisper is dropped without an answer, an unknown id is never refused out loud.
-- Ask       A function may declare one guild-wide question (Register def.ask = "W", channel kind guild): it is a
--             receive action when sent (it asks for what others share), a service when heard (needs the send
--             consent). The answers come back as whispers with the id of the question; they are welcome from
--             anybody for OPEN_WAIT idle seconds (one shared window per question, at most OPEN_MAX answers).
-- Whisper peers: a function that talks to chat partners (def.whisperPeer(name) -> true for a name that has an
--             open chat with us) takes unrequested whispers from exactly those names, inside the receive
--             bucket; everything else stays dropped. Its farewell goes to one whisper target at a time: it needs
--             a message that really went to that target before.
-- Whisper audience: def.whisperAud names the consent audience of the whispers of a function that is
--             consented per guild only (default "chat").
-- Result    The answer of SendAddonMessage (a number of Enum.SendAddonMessageResult, a boolean on older clients, nothing on
--             the oldest) is normalized by Comm.Result into { ok, code, name }. A sender that wants it passes opts.report
--             (see Send); a function may pace itself with def.gate (see Register) and then skips the bucket of its channel.
-- Counters  Comm.FnStats() counts packets and bytes per function in memory (never sent anywhere).
-- Events: FG_COMM_RECEIVED(fn, type, sender, payload, channel), FG_COMM_SENT(fn, type, channel, size,
-- farewell) with farewell true only for a farewell, FG_COMM_BLOCKED(fn, reason) with reason consent,
-- combat, restricted, throttle, queue-full or no-api.
local _, ns = ...
local CL, PN, Consent = ns.CommLogic, ns.PlayerName, ns.Consent

local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "FGCOMM"
Comm.MAX_QUEUE = 40
-- Seconds a message may wait in the queue (combat, empty bucket) before it is dropped.
Comm.TTL = 60
-- Seconds before the second try of a message the game refused as too fast.
Comm.RETRY_WAIT = 2
Comm.MAX_LENGTH = 255
-- Longest payload of a farewell (near data free).
Comm.FAREWELL_MAX = 8
Comm.MAX_SENDER_BUCKETS = 200
-- Seconds an answer window of an own request stays open without a new answer, and the most answers
-- one window takes.
Comm.OPEN_WAIT = 30
Comm.OPEN_MAX = 220
Comm.MAX_WINDOWS = 50
-- Ids a function shared in this session (ring), for the whisper service.
Comm.SHARED_MAX = 100
Comm.PRIORITY = { click = 1, reply = 2, background = 3 }
-- Token bucket per channel kind (size, tokens per second), the defaults of CommLogic. Change before the
-- first message of the kind or call ResetBuckets().
Comm.LIMITS = {
  group = { burst = CL.LIMITS.BURST, refill = CL.LIMITS.REFILL },
  guild = { burst = CL.LIMITS.BURST, refill = CL.LIMITS.REFILL },
  officer = { burst = CL.LIMITS.BURST, refill = CL.LIMITS.REFILL },
  whisper = { burst = CL.LIMITS.BURST, refill = CL.LIMITS.REFILL },
  channel = { burst = CL.LIMITS.BURST, refill = CL.LIMITS.REFILL },
  -- Incoming, per sender.
  receive = { burst = CL.LIMITS.BURST, refill = CL.LIMITS.REFILL },
  -- Answers of a whisper service, per requester: three at once, then one per 20 seconds.
  answer = { burst = 3, refill = 0.05 },
}
-- Replaceable in tests: seconds, and a random integer from 1 to n.
function Comm.clock()
  local get = rawget(_G, "GetTime")
  local ok, t = pcall(type(get) == "function" and get or function() end)
  return ok and tonumber(t) or 0
end
Comm.random = math.random
-- Seconds since the session started are what FnStats reports; GetTime counts from the boot of the machine.
local startedAt = Comm.clock()
-- Bytes the game counts on top of the text of one add-on message (prefix excluded), the assumption of ChatThrottleLib.
Comm.PACE_OVERHEAD = 40

-- Enum.SendAddonMessageResult as of Retail 12, used when the client has no Enum (older clients answer a boolean).
local RESULT_NAMES = {
  [0] = "Success",
  "InvalidPrefix",
  "InvalidMessage",
  "AddonMessageThrottle",
  "InvalidChatType",
  "NotInGroup",
  "TargetRequired",
  "InvalidChannel",
  "ChannelThrottle",
  "GeneralError",
  "NotInGuild",
  "AddOnMessageLockdown",
  "TargetOffline",
}
Comm.RESULT = {
  Success = 0,
  InvalidPrefix = 1,
  InvalidMessage = 2,
  AddonMessageThrottle = 3,
  InvalidChatType = 4,
  NotInGroup = 5,
  TargetRequired = 6,
  InvalidChannel = 7,
  ChannelThrottle = 8,
  GeneralError = 9,
  NotInGuild = 10,
  AddOnMessageLockdown = 11,
  TargetOffline = 12,
}

-- The answer of SendAddonMessage as { ok, code, name }: a number (the name from the Enum of the client, else from
-- the table above), a boolean (true is a success, false the old "too fast"), nil (the oldest clients: a success).
function Comm.Result(raw)
  if type(raw) == "number" and raw == raw and raw >= 0 and raw == math.floor(raw) then
    local name
    local enum = rawget(_G, "Enum")
    local codes = type(enum) == "table" and enum.SendAddonMessageResult
    if type(codes) == "table" then
      for key, value in pairs(codes) do
        if value == raw then
          name = tostring(key)
        end
      end
    end
    name = name or RESULT_NAMES[raw] or ("Code" .. raw)
    return { ok = raw == 0, code = raw, name = name }
  elseif raw == false then
    return { ok = false, code = 3, name = "AddonMessageThrottle" }
  elseif raw == nil or raw == true then
    return { ok = true, code = 0, name = "Success" }
  end
  return { ok = false, code = 9, name = "GeneralError" }
end

local CONSENT_AUD = { group = "group", guild = "guild", officer = "guild", whisper = "chat", channel = "world" }
local KIND_OF_CHANNEL = {
  PARTY = "group",
  RAID = "group",
  INSTANCE_CHAT = "group",
  GUILD = "guild",
  OFFICER = "officer",
  WHISPER = "whisper",
  CHANNEL = "channel",
}
local RESTRICTIONS = { "Chat", "Combat", "Encounter", "ChallengeMode", "PvPMatch" }

local functions, legacy, prefixes = {}, {}, {}
-- Consent audience of a channel kind for a function: a function may name its own one for whispers.
local function audOf(fn, kind)
  local reg = functions[fn]
  if kind == "whisper" and reg and reg.whisperAud then
    return reg.whisperAud
  end
  return CONSENT_AUD[kind]
end
local queue, seq = {}, 0
-- sentTo[fn][kind]: this function really sent into that audience in this session and has not said goodbye.
-- For whispers also one entry per target (sentKey).
local sentTo = {}
local function sentKey(kind, target)
  if kind == "whisper" and type(target) == "string" and target ~= "" then
    return "whisper:" .. PN.Key(target)
  end
  return kind
end
-- windows[fn][name key + id] = { at, left }: answers of a whisper request we sent, still welcome.
-- shared[fn] = { list, set }: ring of the content ids this session shared.
local windows, shared = {}, {}
local armed, pumping, depth = false, false, 0
local buckets = {}
-- Token buckets per remote name: incoming messages ("receive") and answers to requesters ("answer").
local stores = { receive = { map = {}, count = 0 }, answer = { map = {}, count = 0 } }
-- echo: the game hands the own message back on the guild and group channels; it is no drop.
local stats = { sent = 0, received = 0, delivered = 0, echo = 0, retries = 0, blocked = {}, dropped = {} }

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

local assembler = CL.NewAssembler(function()
  return Comm.clock()
end)

local function bump(map, key)
  map[key] = (map[key] or 0) + 1
end

-- Per function (FnStats): only names of the protocol and of registered functions get an entry.
local FN_CAP = 1e12
local fnStats = {}
local function fnEntry(fn)
  if type(fn) ~= "string" or not (CL.CodeOf(fn) or functions[fn]) then
    return nil
  end
  local e = fnStats[fn]
  if not e then
    e = { sent = 0, received = 0, dropped = 0, bytesOut = 0, bytesIn = 0, lastSent = 0, lastReceived = 0 }
    fnStats[fn] = e
  end
  return e
end

local function fnAdd(fn, field, n)
  local e = fnEntry(fn)
  if e then
    e[field] = math.min(FN_CAP, e[field] + (n or 1))
  end
  return e
end

local function sessionTime(now)
  return math.max(0, math.floor((now - startedAt) * 10 + 0.5) / 10)
end

-- Seconds since the session started, the base of the last* fields of FnStats.
function Comm.SessionTime()
  return sessionTime(Comm.clock())
end

local function blocked(fn, reason)
  bump(stats.blocked, reason)
  fnAdd(fn, "dropped")
  ns.Emit("FG_COMM_BLOCKED", fn, reason)
end

local function chatApi()
  local api = g("C_ChatInfo")
  return type(api) == "table" and api or nil
end

-- Registers a prefix with the game once. Returns whether the client knows it.
local function ensurePrefix(prefix)
  if prefixes[prefix] then
    return true
  end
  local api = chatApi()
  if api and type(api.RegisterAddonMessagePrefix) == "function" and pcall(api.RegisterAddonMessagePrefix, prefix) then
    prefixes[prefix] = true
    return true
  end
  return false
end

-- Registering ----------------------------------------------------------------------------------------

local function kindSet(list)
  if type(list) ~= "table" or #list == 0 then
    return nil
  end
  local out = {}
  for _, kind in ipairs(list) do
    if not CONSENT_AUD[kind] then
      return nil
    end
    out[kind] = true
  end
  return out
end

local prefixOwner = {}

local function claim(prefix, owner)
  if type(prefix) ~= "string" or not prefix:find("^[%w_]+$") or #prefix > 16 then
    return false
  end
  if prefixOwner[prefix] and prefixOwner[prefix] ~= owner then
    return false
  end
  prefixOwner[prefix] = owner
  return true
end

-- def: version (the protocol version of CommLogic, 1), audiences (channel kinds), on = { type = handler },
-- decode(payload) -> value or nil (optional), prefix (default FGCOMM), farewell (optional type letter
-- of a message that withdraws the sender: it carries at most FAREWELL_MAX characters and may still be
-- sent after the send consent went off, to say goodbye to a channel that was told something before,
-- see the head of this file), ask (optional type letter of a guild-wide question), whisperAud (optional
-- consent audience of the whispers), request (optional type letter of a whisper request: sent with the receive
-- consent, opens the answer window), service (optional, needs request, on[request] and decode:
-- service(value) -> the content id a whisper request asks for, see the head of this file), whisperPeer (optional
-- name -> boolean, see "Whisper peers" above), gate (optional gate(cost, now, target) -> true, or false, the seconds to wait
-- and optionally "item": called before every message of the function with its cost in bytes; while it says no, the
-- function waits as a whole ("item": only this message waits) and the bucket of the channel kind is not used). decode(payload, typ)
-- gets the envelope type as second argument. A handler is called as
-- handler(sender, value, { fn, typ, id, aud, channel }). Returns true, or false and the refused field.
function Comm.Register(fn, def)
  if not CL.CodeOf(fn) or functions[fn] then
    return false, "fn"
  end
  if type(def) ~= "table" or def.version ~= CL.LIMITS.VERSION then
    return false, "version"
  end
  local kinds = kindSet(def.audiences)
  if not kinds then
    return false, "audiences"
  end
  local on = {}
  for typ, handler in pairs(type(def.on) == "table" and def.on or {}) do
    if type(typ) ~= "string" or not typ:find("^%u$") or type(handler) ~= "function" then
      return false, "on"
    end
    on[typ] = handler
  end
  if next(on) == nil or (def.decode ~= nil and type(def.decode) ~= "function") then
    return false, "on"
  end
  if def.farewell ~= nil and (type(def.farewell) ~= "string" or not on[def.farewell]) then
    return false, "farewell"
  end
  if
    def.ask ~= nil
    and (
      type(def.ask) ~= "string"
      or not def.ask:find("^%u$")
      or not on[def.ask]
      or def.ask == def.farewell
      or def.ask == def.request
      or not kinds.guild
    )
  then
    return false, "ask"
  end
  local whisperAud = def.whisperAud
  if whisperAud ~= nil then
    local known = false
    for _, aud in pairs(CONSENT_AUD) do
      known = known or aud == whisperAud
    end
    if not known or not kinds.whisper then
      return false, "whisperAud"
    end
  end
  if
    def.request ~= nil
    and (type(def.request) ~= "string" or not def.request:find("^%u$") or def.request == def.farewell)
  then
    return false, "request"
  end
  if
    def.service ~= nil
    and (type(def.service) ~= "function" or not def.request or not on[def.request] or not def.decode)
  then
    return false, "service"
  end
  if def.whisperPeer ~= nil and (type(def.whisperPeer) ~= "function" or not kinds.whisper) then
    return false, "whisperPeer"
  end
  if def.gate ~= nil and type(def.gate) ~= "function" then
    return false, "gate"
  end
  local prefix = def.prefix == nil and Comm.PREFIX or def.prefix
  if not claim(prefix, "v2") then
    return false, "prefix"
  end
  functions[fn] = {
    fn = fn,
    prefix = prefix,
    kinds = kinds,
    on = on,
    decode = def.decode,
    farewell = def.farewell,
    request = def.request,
    service = def.service,
    ask = def.ask,
    whisperAud = whisperAud,
    whisperPeer = def.whisperPeer,
    gate = def.gate,
  }
  ensurePrefix(prefix)
  return true
end

-- Takes a function out again (tests, a sub-addon that unloads); its owner hears FG_COMM_UNREGISTERED(fn).
-- The prefix stays claimed.
function Comm.Unregister(fn)
  if functions[fn] then
    functions[fn], sentTo[fn], windows[fn], shared[fn] = nil, nil, nil, nil
    Comm.Purge(fn)
    ns.Emit("FG_COMM_UNREGISTERED", fn)
    return true
  end
  return false
end

-- Old format without envelope (PeerComm v1, NoteLink FGNOTE). def: audiences, functions (the consent
-- functions the message may carry), direction ("receive" by default; "send" for a prefix whose incoming
-- messages are requests this client answers: a whisper then needs no known sender, the handler asks
-- TakeAnswer before it answers),
-- handler(text, sender, { aud, channel, allowed = { fn = true } }). The handler runs only after consent
-- for at least one of the functions, it decodes and keeps only what `allowed` says.
function Comm.RegisterLegacy(prefix, def)
  if type(def) ~= "table" or type(def.handler) ~= "function" or not claim(prefix, "legacy") then
    return false, "def"
  end
  local kinds = kindSet(def.audiences)
  if not kinds or type(def.functions) ~= "table" or #def.functions == 0 then
    return false, "audiences"
  end
  for _, fn in ipairs(def.functions) do
    if type(fn) ~= "string" then
      return false, "functions"
    end
  end
  legacy[prefix] = {
    prefix = prefix,
    kinds = kinds,
    functions = def.functions,
    handler = def.handler,
    direction = def.direction == "send" and "send" or "receive",
  }
  ensurePrefix(prefix)
  return true
end

-- Sending ----------------------------------------------------------------------------------------------

local function bucketFor(kind)
  local b = buckets[kind]
  if not b then
    local limit = Comm.LIMITS[kind]
    b = CL.NewBucket(limit.burst, limit.refill, function()
      return Comm.clock()
    end)
    buckets[kind] = b
  end
  return b
end

function Comm.ResetBuckets()
  buckets = {}
  stores = { receive = { map = {}, count = 0 }, answer = { map = {}, count = 0 } }
end

-- Combat and addon restrictions: nothing is sent (the API may raise errors nobody can catch).
local function lockReason()
  local guard = ns.AutoGuard
  if (guard and guard.Blocked()) or ns.InCombat() then
    return "combat"
  end
  if ns.AddonRestricted(unpack(RESTRICTIONS)) then
    return "restricted"
  end
end

local function channelOf(item)
  if item.kind == "group" then
    local peer = ns.PeerComm
    return peer and peer.GroupChannel() or nil
  elseif item.kind == "guild" or item.kind == "officer" then
    return try(g("IsInGuild")) == true and (item.kind == "guild" and "GUILD" or "OFFICER") or nil
  elseif item.kind == "whisper" then
    return item.target and "WHISPER" or nil
  end
end

-- Functions of the list that may send to this audience right now.
local function allowedSet(list, aud)
  local set, any = {}, false
  for _, fn in ipairs(list) do
    if Consent.Allows(fn, "send", aud) then
      set[fn], any = true, true
    end
  end
  return set, any
end

local function before(a, b)
  if a.prio ~= b.prio then
    return a.prio < b.prio
  end
  return a.seq < b.seq
end

-- How the line treats a normalized result: "ok", "throttle" (try again later), "restricted" (the game locked add-on
-- messages, try again later) or "refused".
local function sendCode(res)
  if res.ok then
    return "ok"
  elseif res.code == 3 or res.code == 8 then
    return "throttle"
  elseif res.code == 11 or tostring(res.name):find("Restrict") then
    return "restricted"
  end
  return "refused"
end

local function remove(item)
  for i = #queue, 1, -1 do
    if queue[i] == item then
      table.remove(queue, i)
      return
    end
  end
end

-- Tells the owner of a transfer (opts.report) how it went; never raises.
local function report(item, res)
  if item.report then
    pcall(item.report, res, { i = item.i, n = item.n, target = item.target, typ = item.typ, fn = item.fn })
  end
end

-- A transfer of an owner that listens failed: its other blocks leave the queue and the owner hears it once.
local function abort(item, res)
  local xfer = item.xfer
  if xfer and xfer.dead then
    return
  end
  if xfer then
    xfer.dead = true
    for i = #queue, 1, -1 do
      if queue[i].xfer == xfer then
        table.remove(queue, i)
      end
    end
  end
  report(item, res)
end

local function arm(delay)
  if armed then
    return
  end
  local timer = g("C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  armed = true
  local ok = pcall(timer.After, math.max(0.1, delay), function()
    armed = false
    -- A client that runs the timer at once must not loop: the next call of Send or Pump goes on.
    depth = depth + 1
    if depth <= 2 then
      ns.Safe("comm", Comm.Pump)
    end
    depth = depth - 1
  end)
  if not ok then
    armed = false
  end
end

-- Target name of the shared window of a guild-wide question (no player name looks like it).
local ASK_KEY = "*"
Comm.ASK_TARGET = ASK_KEY

local function windowKey(target, id)
  return (target == ASK_KEY and ASK_KEY or PN.Key(target)) .. "\n" .. id
end

-- A request of ours went out: its answers are welcome from the target for a while.
local function openWindow(fn, target, id, now)
  local set = windows[fn]
  if not set then
    set = { count = 0 }
    windows[fn] = set
  end
  if set.count >= Comm.MAX_WINDOWS then
    for key, w in pairs(set) do
      if key ~= "count" and now - w.at >= Comm.OPEN_WAIT then
        set[key], set.count = nil, set.count - 1
      end
    end
    if set.count >= Comm.MAX_WINDOWS then
      windows[fn] = { count = 0 }
      set = windows[fn]
    end
  end
  local key = windowKey(target, id)
  if not set[key] then
    set.count = set.count + 1
  end
  set[key] = { at = now, left = Comm.OPEN_MAX }
end

-- Takes one answer out of the window (true), refreshes it; false when there is none (or it ran dry).
local function useWindow(fn, key, id)
  local set = windows[fn]
  local w = set and set[key .. "\n" .. id]
  if not w then
    return false
  end
  local now = Comm.clock()
  if now - w.at >= Comm.OPEN_WAIT or w.left <= 0 then
    set[key .. "\n" .. id], set.count = nil, set.count - 1
    return false
  end
  w.at, w.left = now, w.left - 1
  return true
end

-- The owner is done with a request (answer complete, failed, timed out): late answers are dropped.
function Comm.Close(fn, target, id)
  local set = windows[fn]
  if set and type(target) == "string" and type(id) == "string" then
    local key = windowKey(target, id)
    if set[key] then
      set[key], set.count = nil, set.count - 1
    end
  end
end

-- One queued message to the game. Returns "sent", "wait" (stays queued), or "drop".
local function deliver(item, now)
  local fn = item.fn
  local text, aud = item.text, audOf(fn, item.kind)
  if item.legacy then
    local set, any = allowedSet(item.legacy.fns, aud)
    text = any and item.legacy.build(set) or nil
    if not any then
      blocked(fn, "consent")
      return "drop"
    end
    if type(text) ~= "string" or text == "" or #text > Comm.MAX_LENGTH then
      return "drop"
    end
  elseif not item.farewell and not Consent.Allows(fn, item.dir or "send", aud) then
    blocked(fn, "consent")
    return "drop"
  end
  local channel = channelOf(item)
  local api = chatApi()
  if not channel then
    bump(stats.dropped, "no-channel")
    return "drop"
  end
  if not api or type(api.SendAddonMessage) ~= "function" then
    blocked(fn, "no-api")
    return "drop"
  end
  local reg = functions[fn]
  local cost = #text + #item.prefix + Comm.PACE_OVERHEAD
  if reg and reg.gate and not item.legacy then
    -- A function that paces itself by bytes: its gate replaces the bucket of the channel kind.
    local called, allowed, wait, scope = pcall(reg.gate, cost, now, item.target)
    if not (called and allowed == true) then
      item.why = "throttle"
      return "wait", math.max(0.05, type(wait) == "number" and wait or 1), scope == "item" and "item" or "gate"
    end
  elseif not bucketFor(item.kind).Take() then
    item.why = "throttle"
    return "wait", 1 / math.max(0.01, Comm.LIMITS[item.kind].refill)
  end
  ensurePrefix(item.prefix)
  local ok, result = pcall(api.SendAddonMessage, item.prefix, text, channel, item.target)
  local res = ok and Comm.Result(result) or Comm.Result(9)
  local code = sendCode(res)
  if code == "ok" then
    stats.sent = stats.sent + 1
    local e = fnAdd(fn, "sent")
    if e then
      e.bytesOut = math.min(FN_CAP, e.bytesOut + #text)
      e.lastSent = sessionTime(now)
    end
    if item.request then
      openWindow(fn, item.target, item.id, now)
    elseif item.ask then
      openWindow(fn, ASK_KEY, item.id, now)
    elseif not item.legacy and not item.farewell then
      sentTo[fn] = sentTo[fn] or {}
      sentTo[fn][item.kind] = true
      sentTo[fn][sentKey(item.kind, item.target)] = true
    end
    ns.Emit("FG_COMM_SENT", fn, item.typ, channel, #text, item.farewell)
    report(item, res)
    return "sent"
  end
  if item.report then
    -- The owner decides what a refusal means (try again, skip the target, give up).
    blocked(fn, code == "throttle" and "throttle" or code == "restricted" and "restricted" or "refused")
    abort(item, res)
    return "drop"
  end
  if code == "throttle" and item.tries < 1 then
    item.tries, item.notBefore, item.why = item.tries + 1, now + Comm.RETRY_WAIT, "throttle"
    stats.retries = stats.retries + 1
    return "wait", Comm.RETRY_WAIT
  end
  blocked(fn, code == "throttle" and "throttle" or code == "restricted" and "restricted" or "no-api")
  return "drop"
end

-- Sends what is due. Runs after every Send, from a timer while something waits and when combat ends.
function Comm.Pump()
  if pumping then
    return
  end
  pumping = true
  local ok, err = pcall(function()
    local now = Comm.clock()
    local expired = {}
    for i = #queue, 1, -1 do
      local item = queue[i]
      if now - item.at >= Comm.TTL then
        table.remove(queue, i)
        blocked(item.fn, item.why or "throttle")
        expired[#expired + 1] = item
      end
    end
    for _, item in ipairs(expired) do
      abort(item, { ok = false, code = nil, name = "Expired" })
    end
    local wait, skip, skipFn = nil, {}, {}
    while true do
      local best
      for _, item in ipairs(queue) do
        if
          not skip[item]
          and not skipFn[item.fn]
          and (item.notBefore or 0) <= now
          and (not best or before(item, best))
        then
          best = item
        end
      end
      if not best then
        break
      end
      local why = lockReason()
      if why then
        for _, item in ipairs(queue) do
          item.why = why
        end
        wait = 2
        break
      end
      local result, delay, why2 = deliver(best, now)
      if result == "wait" then
        skip[best] = true
        -- A gate that is dry holds the whole function back, so a small packet never overtakes the one before it.
        if why2 == "gate" then
          skipFn[best.fn] = true
        end
        wait = math.min(wait or math.huge, delay)
      else
        remove(best)
      end
    end
    for _, item in ipairs(queue) do
      if (item.notBefore or 0) > now then
        wait = math.min(wait or math.huge, item.notBefore - now)
      end
    end
    if wait and #queue > 0 then
      pumping = false
      arm(wait)
    end
  end)
  pumping = false
  if not ok then
    ns.Log.warn("comm pump: %s", tostring(err))
  end
end

-- Makes room for n messages of priority `prio`: the oldest of the lowest priority go first, never
-- one of the same or a higher priority.
local function makeRoom(n, prio)
  while #queue + n > Comm.MAX_QUEUE do
    local victim
    for _, item in ipairs(queue) do
      if
        item.prio > prio
        and (not victim or item.prio > victim.prio or (item.prio == victim.prio and item.seq < victim.seq))
      then
        victim = item
      end
    end
    if not victim then
      return false
    end
    remove(victim)
    blocked(victim.fn, "queue-full")
  end
  return true
end

local function enqueue(items, prio)
  if not makeRoom(#items, prio) then
    return false
  end
  for _, item in ipairs(items) do
    queue[#queue + 1] = item
  end
  Comm.Pump()
  return true
end

local function newItem(fn, prefix, kind, typ, text, target, prio)
  seq = seq + 1
  local now = Comm.clock()
  return {
    fn = fn,
    prefix = prefix,
    kind = kind,
    typ = typ,
    text = text,
    target = target,
    prio = prio,
    seq = seq,
    at = now,
    tries = 0,
  }
end

-- Checks shared by Send and SendLegacy. Returns the priority, or nil and the reason.
local function admit(fn, kind, target, opts, allowed)
  local prio = Comm.PRIORITY[type(opts) == "table" and opts.priority or "background"]
  if not prio then
    return nil, "priority"
  end
  if not allowed then
    blocked(fn, "consent")
    return nil, "consent"
  end
  local api = chatApi()
  if not api or type(api.SendAddonMessage) ~= "function" then
    blocked(fn, "no-api")
    return nil, "no-api"
  end
  if kind == "whisper" and (type(target) ~= "string" or target == "" or #target > 64) then
    return nil, "target"
  end
  -- A click gets its answer now; the rest waits for the end of the lock.
  local why = prio == Comm.PRIORITY.click and lockReason()
  if why then
    blocked(fn, why)
    return nil, why
  end
  return prio
end

-- Queues a message of a registered function. payload: printable ASCII, longer than one block is cut
-- into blocks. opts.priority: "click", "reply" or "background" (default). opts.id: transfer id (tests).
-- opts.gap: seconds between two blocks of the payload (0 to 5, default none).
-- opts.report(res, info): the owner hears how the game answered, res = { ok, code, name } (Comm.Result), info =
-- { i, n, target, typ, fn } of the block. A success is reported for every block. A refusal of the game (or the
-- end of the waiting time, name "Expired") is reported once for the whole transfer: the line makes no second try
-- and drops the rest of the transfer, the owner decides.
-- Returns true, or false and the reason (consent, combat, restricted, no-api, queue-full, unregistered,
-- audience, priority, target, or the field CommLogic refused: payload, typ, id, length).
function Comm.Send(fn, typ, payload, aud, target, opts)
  local reg = functions[fn]
  if not reg then
    return false, "unregistered"
  end
  if not reg.kinds[aud] then
    return false, "audience"
  end
  local farewell = reg.farewell ~= nil and typ == reg.farewell
  -- A request asks for what somebody else shares: it is a receive action and goes to a whisper target.
  local request = reg.request ~= nil and typ == reg.request
  if request and aud ~= "whisper" then
    return false, "audience"
  end
  -- A guild-wide question is a receive action as well, and goes to the guild only.
  local ask = reg.ask ~= nil and typ == reg.ask
  if ask and aud ~= "guild" then
    return false, "audience"
  end
  local allowed
  if farewell then
    if type(payload) ~= "string" or #payload > Comm.FAREWELL_MAX then
      return false, "payload"
    end
    allowed = sentTo[fn] ~= nil and sentTo[fn][sentKey(aud, target)] == true
    opts = { priority = "reply", id = type(opts) == "table" and opts.id or nil }
  else
    allowed = Consent.Allows(fn, (request or ask) and "receive" or "send", audOf(fn, aud))
  end
  local prio, why = admit(fn, aud, target, opts, allowed)
  if not prio then
    return false, why
  end
  local id = type(opts) == "table" and opts.id or CL.NewId(Comm.random)
  local texts, reason = CL.Split(fn, typ, payload, id)
  if not texts then
    return false, reason
  end
  local items, xfer = {}, {}
  local gap = type(opts) == "table" and tonumber(opts.gap) or 0
  gap = gap == gap and math.max(0, math.min(5, gap)) or 0
  for i, text in ipairs(texts) do
    items[i] = newItem(fn, reg.prefix, aud, typ, text, target, prio)
    if gap > 0 and i > 1 then
      items[i].notBefore = items[i].at + (i - 1) * gap
    end
    items[i].farewell = farewell or nil
    items[i].i, items[i].n = i, #texts
    if type(opts) == "table" and type(opts.report) == "function" then
      items[i].report, items[i].xfer = opts.report, xfer
    end
    if request then
      items[i].dir, items[i].request, items[i].id = "receive", true, id
    elseif ask then
      items[i].dir, items[i].ask, items[i].id = "receive", true, id
    end
  end
  if farewell then
    -- A position that still waits must not follow its own goodbye.
    Comm.Purge(fn, audOf(fn, aud))
  end
  if not enqueue(items, prio) then
    blocked(fn, "queue-full")
    return false, "queue-full"
  end
  if farewell then
    sentTo[fn][sentKey(aud, target)] = nil
  end
  return true
end

-- Old format (see RegisterLegacy): build(allowed) is called when the message really goes out and
-- returns the text from what `allowed` ({ fn = true }) still permits, nil to send nothing.
-- opts.target is the whisper target.
function Comm.SendLegacy(prefix, aud, fns, build, opts)
  local reg = legacy[prefix]
  if not reg or type(build) ~= "function" or type(fns) ~= "table" or #fns == 0 then
    return false, "unregistered"
  end
  if not reg.kinds[aud] then
    return false, "audience"
  end
  local _, any = allowedSet(fns, CONSENT_AUD[aud])
  local target = type(opts) == "table" and opts.target or nil
  local prio, why = admit(fns[1], aud, target, opts, any)
  if not prio then
    return false, why
  end
  local item = newItem(fns[1], prefix, aud, "L", nil, target, prio)
  item.legacy = { fns = fns, build = build }
  if not enqueue({ item }, prio) then
    blocked(fns[1], "queue-full")
    return false, "queue-full"
  end
  return true
end

function Comm.Busy()
  return #queue > 0 or assembler.Pending() > 0
end

-- Messages waiting in the queue (a sender that pushes many blocks paces itself with this).
function Comm.Queued()
  return #queue
end

-- The function really shared content with this id in this session (a click on Send went out). Only the
-- last SHARED_MAX ids count; the ids are what the whisper service of def.service looks up.
function Comm.NoteShared(fn, id)
  if not functions[fn] or type(id) ~= "string" or id == "" or #id > 32 then
    return false
  end
  local ring = shared[fn]
  if not ring then
    ring = { list = {}, set = {} }
    shared[fn] = ring
  end
  if not ring.set[id] then
    ring.list[#ring.list + 1] = id
    ring.set[id] = true
    while #ring.list > Comm.SHARED_MAX do
      ring.set[table.remove(ring.list, 1)] = nil
    end
  end
  return true
end

function Comm.WasShared(fn, id)
  local ring = shared[fn]
  return ring ~= nil and type(id) == "string" and ring.set[id] == true
end

local function copy(map)
  local out = {}
  for k, v in pairs(map) do
    out[k] = v
  end
  return out
end

-- Counters, no names: sent (taken by the client), received (right prefix, own echoes included), delivered (to a
-- handler), echo (the own message the game gave back), retries, blocked and dropped by reason, queued and open
-- transfers.
function Comm.Stats()
  return {
    sent = stats.sent,
    received = stats.received,
    delivered = stats.delivered,
    echo = stats.echo,
    retries = stats.retries,
    blocked = copy(stats.blocked),
    dropped = copy(stats.dropped),
    queued = #queue,
    pending = assembler.Pending(),
  }
end

-- Packets and bytes per function since the session started, in memory only: { [function] = { sent, received,
-- dropped, bytesOut, bytesIn, lastSent, lastReceived } }. sent: messages the game took; received: messages of
-- others with a valid envelope for the function (before any rule); dropped: messages that were not sent or not
-- delivered, any reason; bytes count the text of the message without the prefix; last* are seconds since the
-- session started (0 while nothing happened, read it together with the count). Every known function has an entry.
function Comm.FnStats()
  local out = {}
  local function put(fn)
    local e = fnEntry(fn)
    if e then
      out[fn] = {
        sent = e.sent,
        received = e.received,
        dropped = e.dropped,
        bytesOut = e.bytesOut,
        bytesIn = e.bytesIn,
        lastSent = e.lastSent,
        lastReceived = e.lastReceived,
      }
    end
  end
  for _, fn in pairs(CL.FUNCTIONS) do
    put(fn)
  end
  for fn in pairs(functions) do
    put(fn)
  end
  return out
end

-- Drops what waits for a function (all of it, or one audience, or one direction of it: "send", or
-- "receive" for requests). A farewell stays: it carries no data and is queued on purpose after the
-- switch went off.
function Comm.Purge(fn, aud, dir)
  for i = #queue, 1, -1 do
    local item = queue[i]
    local fns = item.legacy and item.legacy.fns or { item.fn }
    for _, name in ipairs(fns) do
      if
        name == fn
        and not item.farewell
        and (aud == nil or audOf(item.fn, item.kind) == aud)
        and (dir == nil or (item.dir or "send") == dir)
      then
        table.remove(queue, i)
        break
      end
    end
  end
end

-- Receiving ----------------------------------------------------------------------------------------------

local function inMyGroup(name)
  return try(g("UnitInParty"), name) == true or try(g("UnitInRaid"), name) ~= nil
end

-- Only people of the own group (group channels) or the own guild (guild and officer channel) are believed.
local function trusted(kind, sender, name)
  if kind == "guild" or kind == "officer" then
    return ns.Invites ~= nil and ns.Invites.IsGuildMember(sender, nil) == true
  elseif kind == "group" then
    return inMyGroup(sender) or inMyGroup(name)
  end
  return false
end

local function drop(reason, fn)
  bump(stats.dropped, reason)
  fnAdd(fn, "dropped")
end

-- A packet of a known function from somebody else arrived (before any rule is applied to it).
local function noteReceived(fn, text)
  local e = fnAdd(fn, "received")
  if e then
    e.bytesIn = math.min(FN_CAP, e.bytesIn + #text)
    e.lastReceived = sessionTime(Comm.clock())
  end
end

-- True while the name stays inside its bucket of the store ("receive" or "answer").
local function within(which, key)
  local store, limit = stores[which], Comm.LIMITS[which]
  local b = store.map[key]
  if not b then
    if store.count >= Comm.MAX_SENDER_BUCKETS then
      for k, other in pairs(store.map) do
        if other.Level() >= limit.burst then
          store.map[k], store.count = nil, store.count - 1
        end
      end
      if store.count >= Comm.MAX_SENDER_BUCKETS then
        store.map, store.count = {}, 0
      end
    end
    b = CL.NewBucket(limit.burst, limit.refill, function()
      return Comm.clock()
    end)
    store.map[key], store.count = b, store.count + 1
  end
  return b.Take()
end

local function senderOk(key)
  return within("receive", key)
end

-- The sender as a normalized name; nil for ourselves (second value "echo"), for strangers and for anything unusable.
local function knownSender(kind, sender)
  if type(sender) ~= "string" or sender == "" or #sender > 64 then
    return nil
  end
  local name = PN.Normalize(sender)
  if name == "" then
    return nil
  end
  if PN.Equal(name, PN.Self()) then
    return nil, "echo"
  end
  if not trusted(kind, sender, name) then
    return nil
  end
  return name
end

-- A message without a usable sender: the own echo is counted on its own, everything else is a drop.
local function noSender(why, fn)
  if why == "echo" then
    stats.echo = stats.echo + 1
  else
    drop("sender", fn)
  end
end

-- Old-format service (RegisterLegacy direction "send"): the handler asks this once it decided to answer.
-- True while the requester stays inside its answer bucket.
function Comm.TakeAnswer(sender)
  local name = type(sender) == "string" and PN.Normalize(sender) or ""
  return name ~= "" and within("answer", PN.Key(name))
end

-- A whisper may come from anybody: the name only has to be usable and not our own.
local function whisperSender(sender)
  if type(sender) ~= "string" or sender == "" or #sender > 64 then
    return nil
  end
  local name = PN.Normalize(sender)
  if name == "" then
    return nil
  end
  if PN.Equal(name, PN.Self()) then
    return nil, "echo"
  end
  return name
end

local function receiveLegacy(reg, kind, text, channel, sender)
  local aud, allowed, any = CONSENT_AUD[kind], {}, false
  local fnName = reg.functions[1]
  noteReceived(fnName, text)
  for _, fn in ipairs(reg.functions) do
    if Consent.Allows(fn, reg.direction, aud) then
      allowed[fn], any = true, true
    end
  end
  if not any then
    return drop("consent", fnName)
  end
  local asked = kind == "whisper" and reg.direction == "send"
  local name, why
  if asked then
    name, why = whisperSender(sender)
  else
    name, why = knownSender(kind, sender)
  end
  if not name then
    return noSender(why, fnName)
  end
  if not senderOk(PN.Key(name)) then
    return drop("throttle", fnName)
  end
  stats.delivered = stats.delivered + 1
  ns.Emit("FG_COMM_RECEIVED", reg.prefix, "L", name, text, channel)
  pcall(reg.handler, text, name, { aud = kind, channel = channel, allowed = allowed })
end

-- CHAT_MSG_ADDON. Never raises, anything unexpected is ignored.
function Comm.OnAddon(prefix, text, channel, sender)
  local guard = ns.AutoGuard
  if not guard then
    return
  end
  prefix, text, channel, sender = guard.Safe(prefix), guard.Safe(text), guard.Safe(channel), guard.Safe(sender)
  if type(prefix) ~= "string" or type(text) ~= "string" or type(channel) ~= "string" or type(sender) ~= "string" then
    return
  end
  if #text > Comm.MAX_LENGTH then
    return drop("length")
  end
  local old, kind = legacy[prefix], KIND_OF_CHANNEL[channel]
  if not prefixOwner[prefix] or not kind then
    return
  end
  stats.received = stats.received + 1
  if kind ~= "whisper" and PN.Equal(PN.Normalize(sender), PN.Self()) then
    stats.echo = stats.echo + 1
    return
  end
  if old then
    if old.kinds[kind] then
      receiveLegacy(old, kind, text, channel, sender)
    end
    return
  end
  local block, why = CL.Decode(text)
  if not block then
    -- A message of another protocol version or of a function this version does not know is counted apart.
    return drop((why == "version" or why == "fn") and why or "envelope")
  end
  local reg = functions[block.fn]
  if not reg or reg.prefix ~= prefix or not reg.kinds[kind] or not reg.on[block.typ] then
    return drop("unknown")
  end
  local fnName = block.fn
  noteReceived(fnName, text)
  local asked = kind == "whisper" and reg.service ~= nil and block.typ == reg.request
  -- The guild-wide question is a service: heard with the send consent.
  local asking = kind ~= "whisper" and reg.ask ~= nil and block.typ == reg.ask
  local dir = (asked or asking) and "send" or "receive"
  if not Consent.Allows(block.fn, dir, audOf(block.fn, kind)) then
    return drop("consent", fnName)
  end
  local name, noName
  if kind == "whisper" then
    name, noName = whisperSender(sender)
  else
    name, noName = knownSender(kind, sender)
  end
  if not name then
    return noSender(noName, fnName)
  end
  local key = PN.Key(name)
  if kind == "whisper" and not asked then
    local peer = reg.whisperPeer ~= nil and block.typ ~= reg.request and try(reg.whisperPeer, name) == true
    if peer then
      if not senderOk(key) then
        return drop("throttle", fnName)
      end
    elseif
      -- Only the answer to a request of our own, and not the request type itself.
      block.typ == reg.request or not (useWindow(block.fn, key, block.id) or useWindow(block.fn, ASK_KEY, block.id))
    then
      return drop("unsolicited", fnName)
    end
  elseif not senderOk(key) then
    return drop("throttle", fnName)
  end
  local status, done = assembler.Add(key, block)
  if status == "rejected" then
    return drop(tostring(done), fnName)
  elseif status ~= "complete" then
    return
  end
  local value = done.payload
  if reg.decode then
    local ok, decoded = pcall(reg.decode, value, block.typ)
    if not ok or decoded == nil then
      return drop("decode", fnName)
    end
    value = decoded
  end
  if asked then
    -- Only what this session shared is answered; anything else gets silence.
    local ok, id = pcall(reg.service, value)
    if not ok or not Comm.WasShared(block.fn, id) then
      return drop("unknown-id", fnName)
    end
    if not within("answer", key) then
      return drop("throttle", fnName)
    end
  end
  stats.delivered = stats.delivered + 1
  ns.Emit("FG_COMM_RECEIVED", block.fn, block.typ, name, done.payload, channel)
  pcall(reg.on[block.typ], name, value, { fn = block.fn, typ = block.typ, id = done.id, aud = kind, channel = channel })
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
  Comm.OnAddon(prefix, text, channel, sender)
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if #queue > 0 then
    Comm.Pump()
  end
end)
ns.On("PLAYER_LOGIN", function()
  for prefix in pairs(prefixOwner) do
    ensurePrefix(prefix)
  end
end)
-- A switch that goes off stops what waits for it at once.
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if dir == "send" and value ~= true then
    Comm.Purge(fn, aud, "send")
  elseif dir == "receive" and value ~= true then
    -- Requests wait for the receive consent; their answers are no longer welcome.
    Comm.Purge(fn, aud, "receive")
    windows[fn] = nil
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  Comm.Purge(fn)
  windows[fn] = nil
end)
