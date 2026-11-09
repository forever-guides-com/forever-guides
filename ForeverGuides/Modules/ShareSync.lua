-- "Who is there?" for every guild function that shares between add-on users, and the picture of how each of them
-- is doing. Opt-in like the functions themselves: nothing here sends more than the player allowed.
--   Probe    Whoever receives a function (guildMap, presenceMark, crestMark, peerStats, professions, crafting) asks
--            the guild once when the receive switch goes on, after login, after the guild became known (late at
--            login or a join), after the client stood still and after a loading screen when the last probe is old.
--            The probe is a message of the function with the type Q and an empty payload (Comm "probe"): it carries
--            the function and the protocol version of the envelope, nothing about the player. At most one per
--            function and minute; a refusal (no guild yet, roster not loaded, lock, queue) is tried again with a
--            backoff, a silent guild is asked at most maxTries times per cause.
--   Answer   Whoever sends the function answers a probe with the current state, once per function and minute, after
--            a random wait that grows with the members online, and drops it when enough other messages of the
--            function arrived meanwhile. The answer is the normal message of the function to the whole guild (not a
--            whisper): one message serves every asker of that minute, nothing is addressed to the asker, and the
--            players who ask a second later hear it too. The probe is a service, so it is heard only with the send
--            switch of the function and only from guild members (the line checks both before it reaches here).
--   Guild    The guild status of the game can be late after login and the roster needs a request: this module
--            watches both (events and a poll with backoff), announces FG_SHARE_GUILD_READY(cause) when the guild
--            shows up and holds probes until the roster is there, because messages from members that are not on the
--            roster yet are dropped by the line.
--   Status   Status(fn) and Lines() for the Share tab and /fg diag share: switches, last sent, last heard, players
--            heard, counters, probe and answer ages, the last refusal of the game and the reason why nothing
--            happens. Memory only, never sent anywhere.
-- A function attaches with Attach(fn, def, hooks) before it registers with the line: hooks.ready() -> true, or
-- false and a reason; hooks.answer() -> true, or false and a reason ("wait" and "throttle" are tried again).
local _, ns = ...
local Comm, Consent, SL = ns.Comm, ns.Consent, ns.ShareSyncLogic

local S = {}
ns.ShareSync = S

S.PROBE = "Q"
-- Replaceable in tests: false asks nobody (answering stays on).
S.enabled = true
S.AUDIENCE = "guild"
-- Replaceable in tests: random number from 0 to 1.
function S.random()
  return math.random()
end

local C = SL.CONFIG
local function clock()
  return Comm.clock()
end

local asker = SL.NewAsker(clock, function()
  return S.random()
end)
local responder = SL.NewResponder(clock, function()
  return S.random()
end)

-- fns[fn] = { hooks, order, heardAt, peers, nPeers, askSentAt, lastSentAt, askHeard, askHeardAt, answers, answerAt,
-- skips, blocked, held }
local fns, order = {}, {}
local depth = 0
local known, rosterReady, loginAt, pollN = false, false, nil, 0
local lastTick, lastAnyAsk = nil, nil
local tickState = {}
local PEER_CAP = 1000

local function g(name)
  return rawget(_G, name)
end

local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
  return nil
end

local function safe(value)
  local guard = ns.AutoGuard
  if guard then
    return guard.Safe(value)
  end
  return value
end

local function after(delay, fn)
  local timer = g("C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    return false
  end
  return pcall(timer.After, math.max(0, delay), function()
    -- A client that runs the timer at once must not loop.
    depth = depth + 1
    if depth <= 3 then
      ns.Safe("sharesync", fn)
    end
    depth = depth - 1
  end)
end

-- Runs fn after delay seconds unless the flag in `owner` is set; the flag is set before the timer is made, because
-- a client may run the timer at once.
local function once(owner, key, delay, fn)
  if owner[key] then
    return
  end
  owner[key] = true
  local ok = after(delay, function()
    owner[key] = false
    fn()
  end)
  if not ok then
    owner[key] = false
  end
end

local function notify()
  ns.Debounce("share-status", 1, function()
    ns.Emit("FG_SHARE_STATUS")
  end)
end

local function count(map, key)
  map[key] = (map[key] or 0) + 1
end

-- Facts from the game --------------------------------------------------------------------------------

local function inGuild()
  return try(g("IsInGuild")) == true
end

-- Members on the roster and members online, as far as the game tells (0, 0 while the list is not loaded).
local function rosterCounts()
  local read = g("GetNumGuildMembers")
  if type(read) ~= "function" then
    return 0, 0
  end
  local ok, total, online = pcall(read)
  total, online = safe(total), safe(online)
  if not ok or type(total) ~= "number" then
    return 0, 0
  end
  return total, type(online) == "number" and online or 0
end

local function askRoster()
  local info = g("C_GuildInfo")
  try(type(info) == "table" and info.GuildRoster or g("GuildRoster"))
end

-- A trial account cannot send add-on messages (no error, the messages are lost).
local function trial()
  for _, name in ipairs({ "IsTrialAccount", "IsVeteranTrialAccount", "GameLimitedMode_IsActive" }) do
    if try(g(name)) == true then
      return true
    end
  end
  return false
end

-- Guild and roster ------------------------------------------------------------------------------------

local release, wanted

-- Looks at the guild status; announces the step from "not in a guild" to "in a guild" and releases held probes when
-- the guild and its roster are there.
local function check()
  local now = inGuild()
  local total = rosterCounts()
  if now and not known then
    known = true
    local late = loginAt ~= nil and clock() - loginAt <= C.loginWindow
    pollN = 0
    for _, fn in ipairs(order) do
      asker.Forget(fn)
    end
    ns.Emit("FG_SHARE_GUILD_READY", late and "login" or "join")
  elseif not now and known then
    known, rosterReady = false, false
    ns.Emit("FG_SHARE_GUILD_LOST")
  end
  local ready = now and total > 0
  if ready and not rosterReady then
    rosterReady = true
    release()
  elseif not ready then
    rosterReady = false
  end
  return ready
end

local pollState = {}

local function poll()
  if check() then
    pollN = 0
    return
  end
  if inGuild() and wanted() then
    askRoster()
  end
  pollN = pollN + 1
  local wait = SL.GuildPoll(pollN)
  if wait then
    once(pollState, "on", wait, poll)
  end
end

-- One chain of looks with backoff while the guild or its roster is missing.
local function startPoll()
  if not pollState.on and wanted() then
    pollN = 0
    once(pollState, "on", SL.GuildPoll(1), poll)
  end
end

-- True while the player switched anything on for the guild: only then the guild is watched, the roster is asked for
-- and a timer runs. With everything off (the default) this module costs no game call and no timer.
wanted = function()
  for _, fn in ipairs(order) do
    if Consent.Allows(fn, "send", S.AUDIENCE) or Consent.Allows(fn, "receive", S.AUDIENCE) then
      return true
    end
  end
  return false
end

-- Asking ---------------------------------------------------------------------------------------------

local function receiving(fn)
  return Consent.Allows(fn, "receive", S.AUDIENCE)
end

local function sending(fn)
  return Consent.Allows(fn, "send", S.AUDIENCE)
end

local fireAsk, armAsk

armAsk = function(fn, delay)
  local f = fns[fn]
  if f then
    once(f, "timer", delay, function()
      fireAsk(fn)
    end)
  end
end

-- A probe is wanted for the function (a cause starts the tries over).
local function want(fn, cause, keepTries)
  local f = fns[fn]
  if not S.enabled or not f or not receiving(fn) then
    return
  end
  if not keepTries then
    asker.Reset(fn)
  end
  armAsk(fn, asker.Want(fn, cause))
end

function S.AskAll(cause)
  for _, fn in ipairs(order) do
    want(fn, cause)
  end
end

-- Probes that waited for the guild or the roster.
release = function()
  for _, fn in ipairs(order) do
    local f = fns[fn]
    if f.held then
      local cause = f.held
      f.held = nil
      want(fn, cause, true)
    end
  end
end

-- Seconds after the probe in which answers had to come in; silence asks once more (with backoff).
local function verify(fn, mark)
  local f = fns[fn]
  if not f or f.verifyMark ~= mark or not receiving(fn) then
    return
  end
  if (f.heardAt or 0) >= (f.askQueuedAt or 0) then
    asker.Reset(fn)
    return
  end
  local wait = asker.Failed(fn, "retry")
  if wait then
    armAsk(fn, wait)
  end
end

fireAsk = function(fn)
  local f = fns[fn]
  local verdict, left = asker.Take(fn)
  if verdict == "wait" then
    return armAsk(fn, left)
  elseif verdict ~= "go" then
    return
  end
  if not receiving(fn) then
    asker.Cancel(fn)
    return
  end
  if not (inGuild() and check()) then
    -- The guild or the roster is not there: wait for the event or the poll.
    f.held = f.held or "login"
    asker.Cancel(fn)
    count(f.skips, "noguild")
    startPoll()
    return
  end
  local ok, why = Comm.Send(fn, S.PROBE, "", S.AUDIENCE, nil, { priority = "reply" })
  if ok then
    asker.Sent(fn)
    f.askQueuedAt, lastAnyAsk = clock(), clock()
    f.verifyMark = (f.verifyMark or 0) + 1
    local mark = f.verifyMark
    after(C.verify, function()
      verify(fn, mark)
    end)
  elseif why == "consent" or why == "audience" or why == "payload" then
    asker.Cancel(fn)
    count(f.skips, why)
  else
    count(f.skips, why or "refused")
    local wait = asker.Failed(fn)
    if wait then
      armAsk(fn, wait)
    end
  end
  notify()
end

-- Answering ------------------------------------------------------------------------------------------

local fireAnswer

local function packets(fn)
  local f = fns[fn]
  return Comm.Received(fn) - (f and f.askHeard or 0)
end

local function armAnswer(fn, delay)
  local f = fns[fn]
  if f then
    once(f, "answerTimer", delay, function()
      fireAnswer(fn)
    end)
  end
end

-- True when the function (or the one whose message it rides in) answered in the last `seconds`.
function S.AnsweredWithin(fn, seconds)
  local at = responder.AnsweredAt(fn)
  return at ~= nil and clock() - at <= seconds
end

fireAnswer = function(fn)
  local f = fns[fn]
  local verdict, left = responder.Check(fn, packets(fn))
  if verdict == "wait" then
    return armAnswer(fn, left)
  elseif verdict == "enough" or verdict == "expired" then
    count(f.skips, verdict)
    return
  elseif verdict ~= "go" then
    return
  end
  if not sending(fn) then
    responder.Drop(fn)
    count(f.skips, "consent")
    return
  end
  local ready, why = true, nil
  if f.hooks.ready then
    ready, why = f.hooks.ready()
  end
  local ok = false
  if ready then
    ok, why = f.hooks.answer()
  end
  if ok then
    responder.Answered(fn)
    f.answers, f.answerAt = f.answers + 1, clock()
    notify()
    return
  end
  count(f.skips, why or "refused")
  if why ~= "consent" and why ~= "inactive" and why ~= "empty" then
    local retry = responder.Retry(fn)
    if retry then
      armAnswer(fn, retry)
    end
  else
    responder.Drop(fn)
  end
end

-- A probe came in: the line has checked the send switch and that the sender is a guild member.
local function onProbe(fn)
  local f = fns[fn]
  if not f then
    return
  end
  f.askHeard, f.askHeardAt = f.askHeard + 1, clock()
  local _, online = rosterCounts()
  local delay, merged = responder.Heard(fn, online, packets(fn))
  if merged then
    count(f.skips, "merged")
  else
    armAnswer(fn, delay)
  end
  notify()
end

-- Attaching ------------------------------------------------------------------------------------------

-- Makes the function known with its hooks (a function that registers with the line late declares at load, so the
-- Share tab and the diagnosis list it from the start). Without hooks an earlier declaration stays.
function S.Declare(fn, hooks)
  local f = fns[fn]
  if not f then
    order[#order + 1] = fn
    f = { fn = fn, hooks = {}, peers = {}, nPeers = 0, askHeard = 0, answers = 0, skips = {}, blocked = {} }
    fns[fn] = f
  end
  if hooks then
    f.hooks = hooks
  end
end

-- Adds the probe to the registration `def` of a function (Comm.Register) and keeps the hooks. Call it before
-- Comm.Register(fn, def). Returns def.
function S.Attach(fn, def, hooks)
  def.probe = S.PROBE
  def.on = def.on or {}
  def.on[S.PROBE] = function()
    onProbe(fn)
  end
  S.Declare(fn, hooks)
  return def
end

-- Statistics ------------------------------------------------------------------------------------------

local function age(at)
  if not at or at <= 0 then
    return nil
  end
  return math.max(0, clock() - at)
end

-- Everything the Share tab and /fg diag share say about one function; nil for an unknown function.
function S.Status(fn)
  local f = fns[fn]
  if not f then
    return nil
  end
  local stats = Comm.FnStats()[fn] or {}
  local now = clock()
  local last = Comm.LastError(fn)
  local pause
  if f.hooks.pause then
    pause = f.hooks.pause()
  end
  if not pause and Comm.Lock() == "restricted" then
    pause = "restricted"
  end
  local askAt = f.askSentAt and f.askSentAt > 0 and f.askSentAt or nil
  local out = {
    fn = fn,
    send = sending(fn),
    receive = receiving(fn),
    inGuild = inGuild(),
    roster = rosterReady,
    registered = Comm.IsRegistered(fn),
    lastSent = age(f.lastSentAt),
    lastHeard = age(f.heardAt),
    heard = f.nPeers,
    sent = stats.sent or 0,
    received = stats.received or 0,
    dropped = stats.dropped or 0,
    asks = asker.Count(fn),
    askAge = age(askAt),
    askQueuedAge = age(f.askQueuedAt),
    askTries = asker.Tries(fn),
    askPending = asker.Pending(fn),
    held = f.held,
    askHeard = f.askHeard,
    askHeardAge = age(f.askHeardAt),
    answers = f.answers,
    answerAge = age(f.answerAt),
    answerPending = responder.Pending(fn),
    skips = f.skips,
    blocked = f.blocked,
    error = last,
    pause = pause,
    trial = trial(),
  }
  out.reason = SL.Reason({
    send = out.send,
    receive = out.receive,
    trial = out.trial,
    inGuild = out.inGuild,
    roster = out.roster,
    registered = out.registered,
    pause = pause,
    error = last,
    heard = out.heard,
    askAgo = out.askAge,
  })
  out.now = now
  return out
end

function S.Functions()
  local list = {}
  for i, fn in ipairs(order) do
    list[i] = fn
  end
  return list
end

local function seconds(value)
  return value and string.format("%ds ago", math.floor(value + 0.5)) or "never"
end

local function pairsText(map)
  local out = {}
  for key, value in pairs(map or {}) do
    out[#out + 1] = tostring(key) .. "=" .. tostring(value)
  end
  table.sort(out)
  return #out > 0 and table.concat(out, " ") or "-"
end

-- Plain English lines for support, no names: the same numbers per function.
function S.Lines()
  local out = {}
  local prefix = Comm.PrefixState()
  local _, online = rosterCounts()
  out[1] = string.format(
    "share: guild=%s roster=%s online=%d trial=%s prefixes=%d open=%d",
    inGuild() and "yes" or "no",
    rosterReady and "yes" or "no",
    online,
    trial() and "yes" or "no",
    prefix.known,
    prefix.open
  )
  for prefixName, answer in pairs(prefix.failed) do
    out[#out + 1] = string.format("share: prefix %s refused (%s)", prefixName, tostring(answer))
  end
  for _, fn in ipairs(order) do
    local s = S.Status(fn)
    out[#out + 1] = string.format(
      "%s: send=%s receive=%s registered=%s sent=%s heard=%s (%d players) packets sent=%d received=%d dropped=%d",
      fn,
      s.send and "on" or "off",
      s.receive and "on" or "off",
      s.registered and "yes" or "no",
      seconds(s.lastSent),
      seconds(s.lastHeard),
      s.heard,
      s.sent,
      s.received,
      s.dropped
    )
    local err = s.error
    out[#out + 1] = string.format(
      "  probe: sent=%d last=%s tries=%d held=%s | heard=%d last=%s | answers=%d last=%s | skipped: %s | blocked: %s | game: %s | why: %s",
      s.asks,
      seconds(s.askAge),
      s.askTries,
      tostring(s.held or "-"),
      s.askHeard,
      seconds(s.askHeardAge),
      s.answers,
      seconds(s.answerAge),
      pairsText(s.skips),
      pairsText(s.blocked),
      err and (err.name .. " " .. seconds(err.ago) .. " " .. pairsText(err.names)) or "-",
      s.reason or "ok"
    )
  end
  return out
end

function S.Text()
  return table.concat(S.Lines(), "\n")
end

-- Straight to the chat: the answer to a typed command must show with the default feedback "off" too.
function S.Print()
  for _, line in ipairs(S.Lines()) do
    ns.Notify.chat(line)
  end
end

-- Events -------------------------------------------------------------------------------------------------

ns.On("FG_COMM_SENT", function(_, fn, typ, _, _, farewell)
  local f = fns[fn]
  if not f then
    return
  end
  if typ == S.PROBE then
    f.askSentAt = clock()
  elseif not farewell then
    f.lastSentAt = clock()
  end
  notify()
end)

ns.On("FG_COMM_RECEIVED", function(_, fn, typ, sender)
  local f = fns[fn]
  if not f or typ == S.PROBE or type(sender) ~= "string" then
    return
  end
  f.heardAt = clock()
  if not f.peers[sender] and f.nPeers < PEER_CAP then
    f.peers[sender], f.nPeers = true, f.nPeers + 1
  end
  notify()
end)

ns.On("FG_COMM_BLOCKED", function(_, fn, reason)
  local f = fns[fn]
  if f and type(reason) == "string" then
    count(f.blocked, reason)
    f.blockedAt = clock()
  end
end)

local function arm()
  -- One timer that finds out when the client stood still; it runs only while something is shared.
  local any = false
  for _, fn in ipairs(order) do
    any = any or sending(fn) or receiving(fn)
  end
  if not any then
    return
  end
  once(tickState, "on", C.wake.tick, function()
    local t = clock()
    if lastTick and t - lastTick >= C.wake.jump then
      S.AskAll("wake")
    end
    lastTick = t
    arm()
  end)
end

ns.On("PLAYER_LOGIN", function()
  loginAt, lastTick = clock(), clock()
  known = inGuild()
  rosterReady = known and rosterCounts() > 0
  if not rosterReady then
    startPoll()
  end
  S.AskAll("login")
  arm()
end)
ns.On("PLAYER_ENTERING_WORLD", function(_, initial, reloading)
  check()
  if initial == true or reloading == true then
    return
  end
  -- Loading screens ask again only when the last probe is old (a safety net, not a timer).
  if not lastAnyAsk or clock() - lastAnyAsk >= C.reload then
    S.AskAll("load")
  end
end)
ns.On("PLAYER_GUILD_UPDATE", function(_, unit)
  if unit == nil or unit == "player" then
    if not check() and inGuild() and wanted() then
      askRoster()
      startPoll()
    end
  end
end)
ns.On("GUILD_ROSTER_UPDATE", check)
ns.On("FG_SHARE_GUILD_READY", function(_, cause)
  S.AskAll(cause)
  arm()
end)
ns.On("FG_SHARE_GUILD_LOST", function()
  for _, fn in ipairs(order) do
    asker.Forget(fn)
    responder.Drop(fn)
    fns[fn].held = nil
  end
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  local f = fns[fn]
  if not f or aud ~= S.AUDIENCE then
    return
  end
  if dir == "receive" then
    if value == true then
      -- The player listens from now on: ask at once.
      want(fn, "switch")
    else
      asker.Cancel(fn)
      f.held = nil
      -- Who was heard is forgotten with the switch.
      f.peers, f.nPeers, f.heardAt = {}, 0, nil
    end
  elseif value ~= true then
    responder.Drop(fn)
  end
  if value == true and not rosterReady then
    startPoll()
  end
  arm()
  notify()
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  local f = fns[fn]
  if f then
    asker.Cancel(fn)
    responder.Drop(fn)
    f.held = nil
    f.peers, f.nPeers, f.heardAt = {}, 0, nil
    notify()
  end
end)
