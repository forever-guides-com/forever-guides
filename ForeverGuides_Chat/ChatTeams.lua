-- Forever Chat, the teams (game access): group chats between add-on users, made by the players themselves. Every
-- message is one hidden add-on whisper to each member (function teamChat of ns.Consent, audience chat, send and
-- receive separate, off by default). The rules, the wire format and the store live in ChatTeamsLogic.lua.
--   Sending     only with teamChat.send, never in combat or under a restriction (the message waits in the outbox).
--               The outbox hands packets to the line (Comm) in the order messages, roster and changes, sync requests
--               (ChatTeamsPacerLogic), the members of one message in random order. The line asks the pacer (a bucket
--               of bytes) before every block, so a team of 80 gets its message in some tens of seconds and the game
--               never sees a burst. The game's answer to each block (Comm.Result) decides what happens next: sent,
--               offline (the member is skipped for OFFLINE_SECONDS), too fast or locked (back into the outbox, the
--               pace slows down), anything else is dropped and counted. Nobody gets a hello: a packet goes to members
--               of a team and to the players the user invites by hand.
--   Receiving   only with teamChat.receive (the line drops everything else before it reaches this file). A packet
--               counts only from a member of the local state of the team; the exceptions are an invitation (it
--               lands in a list and joins nothing), the answer to an invitation of ours, and the roster that
--               follows an Accept. Changes only from admins. The sender is the name of the game, never a field.
--   Offline     A member who is not online makes the game print "No player named .." for each packet. The
--               message is noticed (the sender is skipped for OFFLINE_SECONDS) and kept out of the chat frame, for
--               our own packets only.
--   Catching up At login and when a member comes back, at most SYNC_TARGETS members get a request with the last
--               counter per sender (once per SYNC_GAP per team). The answer holds the missing messages.
-- Interface (all changes emit FG_CHAT_TEAMS(teamId or nil, what)): Create, Invite, Accept, Decline, Block,
-- Unblock, Leave, Remove, SetAdmin, Rename, SetIcon, Dissolve, Send, List, Get, Messages, Invites, Online,
-- Unread. The messages of a team are mirrored into chat.convs as conversations of the kind "team".
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local TL, Conv, Comm, Consent, PN = chat.TeamsLogic, chat.Conversations, FG.Comm, FG.Consent, FG.PlayerName
local SL, PL = chat.SendLogic, chat.TeamsPacerLogic

local Teams = {}
chat.Teams = Teams

Teams.FN = "teamChat"
local FN = Teams.FN
local T = TL.TYPES

-- Seconds a player who was "not found" is skipped.
Teams.OFFLINE_SECONDS = 300
-- Seconds after a packet of ours in which a "not found" message of the game is taken for its answer.
Teams.NOT_FOUND_WINDOW = 40
-- Seconds without a packet after which a member counts as away, and as back with the next one.
Teams.ONLINE_WINDOW = 900
Teams.SYNC_GAP = 600
Teams.SYNC_TARGETS = 2
Teams.SYNC_ATTEMPTS = 5
Teams.SYNC_CHAIN = 4
Teams.SYNC_PENDING = 300
Teams.SYNC_DELAY = 20
Teams.ANSWER_GAP = 30
Teams.ROSTER_GAP = 60
Teams.ACCEPT_TTL = 3600
Teams.INVITE_TTL = TL.LIMITS.INVITE_TTL
-- Packets that may wait in the outbox (a message of 1600 bytes to 79 members is 632), the blocks the outbox keeps in
-- the line at most, and the share of the line (Comm.MAX_QUEUE) kept free for others.
Teams.MAX_OUTBOX = 800
Teams.LINE_FILL = 12
Teams.LINE_RESERVE = 8
-- Seconds before a packet the game refused as too fast goes again, and how often it may.
Teams.THROTTLE_WAIT = 1.5
Teams.MAX_TRIES = 8
-- Seconds the outbox holds still after the game said add-on messages are locked.
Teams.LOCKDOWN_WAIT = 15
-- Seconds a packet may be in the line without an answer before it counts as lost.
Teams.INFLIGHT_TTL = 90
-- Teams with more other members than this get the roster of a new member in one go after ROSTER_DELAY seconds.
Teams.ROSTER_SMALL = 8
Teams.ROSTER_DELAY = 10
Teams.PAGE = 100
Teams.COUNTER_JUMP = 5000

local function g(name)
  return rawget(_G, name)
end

local function clock()
  return FG.U.now()
end

local registered, filterOn = false, false
local outbox = {}
-- Memory only, keyed by name key (and team id where it says so).
local offline, heard, recentSend, silent = {}, {}, {}, {}
local pendingOut, accepted, syncPending, rounds = {}, {}, {}, {}
local lastSync, answeredAt, rosterAt, rate = {}, {}, {}, {}
local mirrorSeq = 0
-- Memory only: the pace, the delivery count of own messages, packets handed to the line and not answered yet.
local function mono()
  return Comm.clock()
end
local pacer, tally, inflight = PL.New(mono), PL.NewTally(), {}
local lockdownUntil, armedAt, pumping = 0, nil, false
local recentDone, rosterFresh, rosterTimer = {}, {}, {}
local counters = { sent = 0, throttled = 0, lockdown = 0, offline = 0, errors = 0, dropped = {} }

-- Switches ---------------------------------------------------------------------------------------------------------

local function switchedOn()
  return FG.SubAddons == nil or FG.SubAddons.State("chat") == "active"
end

local function maySend()
  return switchedOn() and Consent.Allows(FN, "send", "chat")
end

local function mayReceive()
  return switchedOn() and Consent.Allows(FN, "receive", "chat")
end

local function locked()
  local guard = FG.AutoGuard
  if FG.InCombat() or (guard ~= nil and guard.Blocked()) then
    return true
  end
  local ok, value = pcall(chat.Send and chat.Send.Restricted or function() end)
  return ok and value == true
end

-- State -----------------------------------------------------------------------------------------------------------

local function realm()
  for _, name in ipairs({ "GetNormalizedRealmName", "GetRealmName" }) do
    local fn = g(name)
    if type(fn) == "function" then
      local ok, value = pcall(fn)
      if ok and type(value) == "string" and value ~= "" then
        return value:lower()
      end
    end
  end
  return ""
end

local function selfName()
  local name = PN.Self()
  return name ~= "" and name or nil
end

-- The state of this character in the store, nil while the own name is unknown or the store is full of others.
local function state()
  local db, name = chat.db, selfName()
  if type(db) ~= "table" or not name then
    return nil
  end
  if type(db.teams) ~= "table" or type(db.teams.chars) ~= "table" then
    db.teams = { v = 1, chars = {} }
  end
  local key = PN.Key(name) .. "-" .. realm()
  local st = db.teams.chars[key]
  if not st then
    local n = 0
    for _ in pairs(db.teams.chars) do
      n = n + 1
    end
    if n >= TL.LIMITS.MAX_CHARACTERS then
      return nil
    end
    st = TL.NewCharacter()
    db.teams.chars[key] = st
  end
  return st, name
end

local function announce(tid, what)
  FG.Emit("FG_CHAT_TEAMS", tid, what)
end

local function announceConv(tid)
  local key = Conv.Key("team", tid)
  FG.Emit("FG_CHAT_UPDATE", key and { [key] = true } or {}, chat.Unread.Total(chat.convs))
end

local function member(team, name)
  return TL.Find(team, name)
end

local function others(team, me)
  local list = {}
  for _, name in ipairs(TL.Names(team)) do
    if not PN.Equal(name, me) then
      list[#list + 1] = name
    end
  end
  return list
end

-- Conversation mirror ------------------------------------------------------------------------------------------------

local function ensureConv(team)
  local conv = Conv.Ensure(chat.convs, { kind = "team", name = team.id }, clock())
  if conv then
    conv.name = team.name
  end
  return conv
end

local function mirror(team, m, incoming, me)
  local conv = ensureConv(team)
  if not conv then
    return
  end
  mirrorSeq = mirrorSeq + 1
  local mine = PN.Equal(m.sender, me)
  local line = Conv.AddLine(chat.convs, { kind = "team", name = team.id }, {
    time = m.time,
    text = m.text,
    sender = m.sender,
    dir = mine and FG.ChatHistoryLogic.DIR_OUT or FG.ChatHistoryLogic.DIR_IN,
    type = FG.ChatHistoryLogic.TYPES.party,
    id = mirrorSeq,
  })
  -- AddLine names the conversation after its target (the id): the name of the team is what the list shows.
  conv.name = team.name
  if line then
    if incoming and not mine then
      chat.Unread.Note(chat.Unread.Context(chat.db, me, clock()), conv, line)
    else
      chat.Unread.MarkRead(conv)
    end
  end
end

local function unmirror(tid)
  local key = Conv.Key("team", tid)
  if key then
    Conv.Remove(chat.convs, key)
  end
end

local loadedFor
-- Puts the stored teams into the conversations (read). Runs again when the own name became known.
function Teams.Load()
  local st, me = state()
  if not st or loadedFor == me then
    return false
  end
  loadedFor = me
  for _, team in pairs(st.teams) do
    local conv = ensureConv(team)
    for _, m in ipairs(st.history[team.id].msgs) do
      mirror(team, m, false, me)
    end
    if conv then
      chat.Unread.MarkRead(conv)
    end
  end
  announce(nil, "load")
  return true
end

-- Removes a team and everything kept for it.
local function forget(st, tid)
  st.teams[tid], st.history[tid], st.counters[tid] = nil, nil, nil
  pendingOut[tid], accepted[tid], lastSync[tid], rounds[tid] = nil, nil, nil, nil
  for i = #outbox, 1, -1 do
    if outbox[i].tid == tid then
      table.remove(outbox, i)
    end
  end
  for p in pairs(inflight) do
    if p.tid == tid then
      inflight[p] = nil
    end
  end
  rosterFresh[tid], rosterTimer[tid] = nil, nil
  for key in pairs(syncPending) do
    if key:sub(1, #tid) == tid then
      syncPending[key] = nil
    end
  end
  unmirror(tid)
end

-- Sending -----------------------------------------------------------------------------------------------------------

-- Wakes the outbox in `delay` seconds; an earlier wish replaces a later one.
local function arm(delay)
  local timer = g("C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  local target = mono() + delay
  if armedAt and armedAt <= target + 0.01 then
    return
  end
  armedAt = target
  local ok = pcall(timer.After, delay, function()
    if armedAt and mono() >= armedAt - 0.05 then
      armedAt = nil
    end
    FG.Safe("chat-teams", Teams.Pump)
  end)
  if not ok then
    armedAt = nil
  end
end

-- The filter keeps our own "not found" lines out of the chat frame. It is registered with the first packet.
local function filterApi()
  local legacy = g("ChatFrame_AddMessageEventFilter")
  if type(legacy) == "function" then
    return legacy
  end
  local util = g("ChatFrameUtil")
  local fn = type(util) == "table" and util.AddMessageEventFilter
  return type(fn) == "function" and fn or nil
end

local function notFoundName(text)
  local guard = FG.AutoGuard
  local readable = guard and guard.Safe and guard.Safe(text) or text
  if type(readable) ~= "string" then
    return nil
  end
  return SL.NotFoundName(readable, g("ERR_CHAT_PLAYER_NOT_FOUND_S"))
end

-- True when a "not found" line is the answer to a packet of ours (and not to a whisper of the user).
function Teams.IsOurs(text)
  if next(recentSend) == nil then
    return false
  end
  local name = notFoundName(text)
  if not name then
    return false
  end
  local at = recentSend[PN.Key(name)]
  if not at or clock() - at > Teams.NOT_FOUND_WINDOW then
    return false
  end
  return not (chat.Send and chat.Send.RecentTo and chat.Send.RecentTo(name))
end

local function ensureFilter()
  if filterOn then
    return
  end
  local add = filterApi()
  if add then
    filterOn = pcall(add, "CHAT_MSG_SYSTEM", function(_, _, text)
      local ok, ours = pcall(Teams.IsOurs, text)
      return ok and ours == true
    end)
  end
end

local function skipTally(p)
  if p.mkey then
    tally.Skip(p.mkey)
  end
end

-- Reasons of the outbox itself next to the result names of the game.
local OWN_DROPS = { GiveUp = true, Lost = true, Refused = true }

local function countDrop(name)
  local key = (Comm.RESULT[name] ~= nil or OWN_DROPS[name]) and name or "Other"
  counters.dropped[key] = (counters.dropped[key] or 0) + 1
end

-- Takes a packet out of the outbox and out of the count of its message.
local function dropAt(i)
  skipTally(table.remove(outbox, i))
end

-- The packet goes back to the front of its class and waits `wait` seconds; after MAX_TRIES it is dropped.
local function requeue(p, wait)
  p.tries = (p.tries or 0) + 1
  if p.tries > Teams.MAX_TRIES then
    countDrop("GiveUp")
    skipTally(p)
    return
  end
  p.retryAt = mono() + wait
  table.insert(outbox, 1, p)
end

local function remember(key, mkey)
  local list = recentDone[key]
  if not list then
    list = {}
    recentDone[key] = list
  end
  list[#list + 1] = { mkey = mkey, at = clock() }
  while #list > 8 do
    table.remove(list, 1)
  end
end

local function blocksOf(payload)
  return math.max(1, math.ceil(#payload / FG.CommLogic.LIMITS.MAX_PAYLOAD))
end

-- Queues one packet. Returns false when the outbox is full. A roster replaces an older one for the same member:
-- only the latest state is worth sending.
local function enqueue(target, typ, payload, tid, prio)
  if payload == nil then
    return false
  end
  if typ == T.ROSTER then
    for i, q in ipairs(outbox) do
      if q.typ == typ and q.tid == tid and PN.Equal(q.target, target) then
        table.remove(outbox, i)
        break
      end
    end
  end
  if #outbox >= Teams.MAX_OUTBOX then
    return false
  end
  outbox[#outbox + 1] =
    { target = target, typ = typ, payload = payload, tid = tid, prio = prio or "reply", blocks = blocksOf(payload) }
  return true
end

local function shuffled(names)
  local copy = {}
  for i, name in ipairs(names) do
    copy[i] = name
  end
  return PL.Shuffle(copy, Comm.random)
end

local function fanout(names, typ, payload, tid, prio)
  local n = 0
  for _, name in ipairs(shuffled(names)) do
    if enqueue(name, typ, payload, tid, prio) then
      n = n + 1
    end
  end
  Teams.Pump()
  return n
end

local function sendRoster(team, names)
  return fanout(names, T.ROSTER, TL.EncodeRoster(team), team.id)
end

local function requestSync(st, team, name)
  local h = st.history[team.id]
  local vec = {}
  for _, item in pairs(TL.Vector(h, team)) do
    vec[#vec + 1] = item
  end
  table.sort(vec, function(a, b)
    return PN.Key(a.name) < PN.Key(b.name)
  end)
  local payload = TL.EncodeSync(team.id, team.epoch, vec)
  if payload and enqueue(name, T.SYNC, payload, team.id, "background") then
    syncPending[team.id .. "\n" .. PN.Key(name)] = { at = clock(), name = name }
    Teams.Pump()
    return true
  end
  return false
end

-- Members that could answer, the ones heard lately first.
local function candidates(team, me, tried)
  local list, now = {}, clock()
  for _, name in ipairs(others(team, me)) do
    local key = PN.Key(name)
    if (offline[key] or 0) <= now and not (tried and tried[key]) and not silent[key] then
      list[#list + 1] = name
    end
  end
  table.sort(list, function(a, b)
    local ha, hb = heard[PN.Key(a)] or 0, heard[PN.Key(b)] or 0
    if ha ~= hb then
      return ha > hb
    end
    return PN.Key(a) < PN.Key(b)
  end)
  return list
end

-- The player is not reachable: skipped for a while, what waits for him leaves the outbox (and the count of its
-- message), a sync request that went to him tries the next member.
local function unreachable(name)
  local key = PN.Key(name)
  offline[key], heard[key] = clock() + Teams.OFFLINE_SECONDS, nil
  for i = #outbox, 1, -1 do
    if PN.Key(outbox[i].target) == key then
      dropAt(i)
    end
  end
  local st, me = state()
  if st then
    for id in pairs(syncPending) do
      local tid = id:match("^(%w+)\n")
      local round = tid and rounds[tid]
      local team = tid and st.teams[tid]
      if team and round and id:sub(#tid + 2) == key then
        syncPending[id] = nil
        if round.attempts < Teams.SYNC_ATTEMPTS then
          local nextName = candidates(team, me, round.tried)[1]
          if nextName then
            round.tried[PN.Key(nextName)] = true
            round.attempts = round.attempts + 1
            requestSync(st, team, nextName)
          end
        end
      end
    end
  end
  announce(nil, "online")
end

-- What the game answered to a block of a packet (Comm.Result). Called for every block that went out and once for a
-- refusal (which ends the transfer).
local function onResult(p, res, info)
  if not inflight[p] then
    return
  end
  local code, R = res.code, Comm.RESULT
  if res.ok then
    if info.i < info.n then
      return
    end
    inflight[p] = nil
    counters.sent = counters.sent + 1
    if p.mkey then
      tally.Done(p.mkey)
      remember(PN.Key(p.target), p.mkey)
    end
    Teams.Pump()
    return
  end
  inflight[p] = nil
  if code == R.TargetOffline then
    counters.offline = counters.offline + 1
    skipTally(p)
    unreachable(p.target)
  elseif code == R.AddonMessageThrottle or code == R.ChannelThrottle then
    counters.throttled = counters.throttled + 1
    pacer.Slow()
    requeue(p, Teams.THROTTLE_WAIT)
  elseif code == R.AddOnMessageLockdown then
    counters.lockdown = counters.lockdown + 1
    lockdownUntil = mono() + Teams.LOCKDOWN_WAIT
    requeue(p, Teams.LOCKDOWN_WAIT)
  elseif res.name == "Expired" then
    requeue(p, 1)
  else
    if code == R.InvalidMessage then
      counters.errors = counters.errors + 1
    end
    countDrop(tostring(res.name))
    skipTally(p)
  end
  Teams.Pump()
end

local function pumpOnce()
  local now, at = clock(), mono()
  if lockdownUntil > at then
    arm(lockdownUntil - at)
    return
  end
  -- A packet the line lost without a word (a purge) must not stay in the books.
  for p in pairs(inflight) do
    if at - (p.at or at) > Teams.INFLIGHT_TTL then
      inflight[p] = nil
      countDrop("Lost")
      skipTally(p)
    end
  end
  for i = #outbox, 1, -1 do
    if (offline[PN.Key(outbox[i].target)] or 0) > now then
      dropAt(i)
    end
  end
  local function ready(p)
    return (p.retryAt or 0) <= at
  end
  while true do
    local index = PL.Pick(outbox, ready)
    if not index then
      break
    end
    local p = outbox[index]
    local queued = Comm.Queued()
    if
      (queued > 0 and queued + p.blocks > Teams.LINE_FILL) or queued + p.blocks > Comm.MAX_QUEUE - Teams.LINE_RESERVE
    then
      break
    end
    table.remove(outbox, index)
    ensureFilter()
    p.at, inflight[p] = at, true
    local ok, why = Comm.Send(FN, p.typ, p.payload, "whisper", p.target, {
      priority = p.prio,
      report = function(res, info)
        onResult(p, res, info)
      end,
    })
    if ok then
      recentSend[PN.Key(p.target)] = now
    else
      inflight[p] = nil
      if why == "combat" or why == "restricted" or why == "queue-full" then
        table.insert(outbox, index, p)
        arm(why == "queue-full" and 1 or 3)
        return
      end
      countDrop("Refused")
      skipTally(p)
    end
  end
  if #outbox > 0 then
    local wait = 0.5
    for _, p in ipairs(outbox) do
      if (p.retryAt or 0) > at then
        wait = math.min(wait, math.max(0.1, p.retryAt - at))
      end
    end
    arm(wait)
  end
end

-- Hands waiting packets to the line while it has room. Called after every send, from a timer and when the line
-- answered a block.
function Teams.Pump()
  if pumping or #outbox == 0 then
    return
  end
  if not maySend() then
    outbox, inflight = {}, {}
    return
  end
  if locked() then
    arm(3)
    return
  end
  pumping = true
  local ok, err = pcall(pumpOnce)
  pumping = false
  if not ok then
    error(err, 0)
  end
end

-- Asks up to SYNC_TARGETS members for what this client missed. Once per SYNC_GAP per team unless `force`.
-- Returns the number of requests.
function Teams.Resync(tid, force)
  local st, me = state()
  local team = st and st.teams[tid]
  if not team or not maySend() or not mayReceive() then
    return 0
  end
  local now = clock()
  if not force and lastSync[tid] and now - lastSync[tid] < Teams.SYNC_GAP then
    return 0
  end
  lastSync[tid] = now
  local round = { tried = {}, attempts = 0, chain = 0 }
  rounds[tid] = round
  local sent = 0
  for _, name in ipairs(candidates(team, me, round.tried)) do
    if sent >= Teams.SYNC_TARGETS then
      break
    end
    round.tried[PN.Key(name)] = true
    round.attempts = round.attempts + 1
    if requestSync(st, team, name) then
      sent = sent + 1
    end
  end
  return sent
end

function Teams.ResyncAll(force)
  local st = state()
  local total = 0
  if st then
    for tid in pairs(st.teams) do
      total = total + Teams.Resync(tid, force)
    end
  end
  return total
end

-- A "not found" answer of the game (clients without result codes): the player is skipped for a while. The packets
-- of the last seconds that counted as delivered to him did not arrive.
function Teams.OnSystemMessage(text)
  if next(recentSend) == nil then
    return false
  end
  if not Teams.IsOurs(text) then
    return false
  end
  local name = notFoundName(text)
  local key = PN.Key(name)
  local now = clock()
  for _, item in ipairs(recentDone[key] or {}) do
    if now - item.at <= Teams.NOT_FOUND_WINDOW then
      tally.Undo(item.mkey)
    end
  end
  recentDone[key] = nil
  unreachable(name)
  return true
end

-- Receiving ---------------------------------------------------------------------------------------------------------

local function noteHeard(st, name)
  local key, now = PN.Key(name), clock()
  local away = heard[key] == nil or now - heard[key] > Teams.ONLINE_WINDOW or (offline[key] or 0) > 0
  heard[key], offline[key], silent[key] = now, nil, nil
  if away then
    for tid, team in pairs(st.teams) do
      if member(team, name) then
        Teams.Resync(tid)
      end
    end
  end
end

-- A handler runs only while the receive consent holds and the own name is known.
local function guarded(handler)
  return function(name, value, info)
    if not mayReceive() then
      return
    end
    local st, me = state()
    if st then
      handler(st, me, name, value, info)
    end
  end
end

local function acceptWhisper(name)
  local st = state()
  return mayReceive() and st ~= nil and not st.blocked[PN.Key(name)]
end

local function removeInvites(st, tid)
  for i = #st.invites.list, 1, -1 do
    if st.invites.list[i].tid == tid then
      table.remove(st.invites.list, i)
    end
  end
end

local function onInvite(st, _, name, v)
  if st.teams[v.tid] then
    return
  end
  local id = TL.AddInvite(
    st.invites,
    rate,
    st.blocked,
    { tid = v.tid, name = v.name, icon = v.icon, count = v.count, from = name },
    clock()
  )
  if id then
    announce(v.tid, "invite")
  end
end

-- The roster to everybody but the members who got it just now, after ROSTER_DELAY seconds (once for many joins).
local function scheduleRoster(tid)
  if rosterTimer[tid] then
    return
  end
  local function fire()
    rosterTimer[tid] = nil
    local fresh = rosterFresh[tid] or {}
    rosterFresh[tid] = nil
    local st, me = state()
    local team = st and st.teams[tid]
    if team and maySend() then
      local names = {}
      for _, name in ipairs(others(team, me)) do
        if not fresh[PN.Key(name)] then
          names[#names + 1] = name
        end
      end
      sendRoster(team, names)
    end
  end
  local timer = g("C_Timer")
  rosterTimer[tid] = true
  if type(timer) ~= "table" or type(timer.After) ~= "function" or not pcall(timer.After, Teams.ROSTER_DELAY, fire) then
    fire()
  end
end

local function onAccept(st, me, name, v)
  local team = st.teams[v.tid]
  local pend = pendingOut[v.tid]
  local key = PN.Key(name)
  if not team or not pend or not pend[key] or not maySend() or not TL.IsAdmin(team, me) then
    return
  end
  local ok = TL.Apply(team, me, { kind = "add", name = name, joined = clock() })
  if not ok then
    return
  end
  pend[key] = nil
  local rest = others(team, me)
  if #rest <= Teams.ROSTER_SMALL then
    sendRoster(team, rest)
  else
    -- A big team gets the news of many joins in one roster, the new member gets his at once.
    sendRoster(team, { name })
    rosterFresh[team.id] = rosterFresh[team.id] or {}
    rosterFresh[team.id][key] = true
    scheduleRoster(team.id)
  end
  announce(v.tid, "members")
end

local function onDecline(_, _, name, v)
  local pend = pendingOut[v.tid]
  if pend and pend[PN.Key(name)] then
    pend[PN.Key(name)] = nil
    announce(v.tid, "invite")
  end
end

local function replyRoster(team, name)
  local id, now = team.id .. "\n" .. PN.Key(name), clock()
  if rosterAt[id] and now - rosterAt[id] < Teams.ROSTER_GAP then
    return
  end
  rosterAt[id] = now
  if maySend() then
    sendRoster(team, { name })
  end
end

local function onRoster(st, me, name, v)
  local remote = v.team
  local team = st.teams[remote.id]
  if not team then
    local ack = accepted[remote.id]
    local count = 0
    for _ in pairs(st.teams) do
      count = count + 1
    end
    if
      not ack
      or ack.key ~= PN.Key(name)
      or clock() - ack.at > Teams.ACCEPT_TTL
      or not TL.IsAdmin(remote, name)
      or not member(remote, me)
      or count >= TL.LIMITS.MAX_TEAMS
    then
      return
    end
    st.teams[remote.id], st.history[remote.id], st.counters[remote.id] = remote, TL.NewHistory(), 0
    accepted[remote.id] = nil
    removeInvites(st, remote.id)
    ensureConv(remote)
    announce(remote.id, "joined")
    Teams.Resync(remote.id, true)
    return
  end
  if not TL.IsAdmin(team, name) then
    return
  end
  local verdict = TL.Merge(team, remote)
  if verdict == "remote" then
    if not member(remote, me) then
      forget(st, team.id)
      announce(team.id, "removed")
      return
    end
    st.teams[team.id] = remote
    ensureConv(remote)
    announce(team.id, "team")
  elseif verdict == "local" then
    replyRoster(team, name)
  end
end

-- Adds a message to the history of a team and keeps the total of the character inside its limit.
local function addMessage(st, tid, m, now)
  local added = TL.Add(st.history[tid], m, now)
  if added then
    TL.PruneTotal(st.history)
  end
  return added
end

local function onMessage(st, me, name, v)
  local team = st.teams[v.tid]
  local sender = team and member(team, name)
  if not sender then
    return
  end
  noteHeard(st, name)
  local now = clock()
  local m = { sender = sender, counter = v.counter, time = TL.ClampTime(v.time, now), text = v.text }
  if addMessage(st, v.tid, m, now) then
    mirror(team, m, true, me)
    announce(v.tid, "message")
    announceConv(v.tid)
  end
end

-- What a change from somebody else leaves us to do.
local function afterRemote(st, me, name, team, result)
  if result == "applied" or result == "empty" then
    if not member(team, me) then
      forget(st, team.id)
      announce(team.id, "removed")
    else
      ensureConv(team)
      announce(team.id, "team")
    end
  elseif result == "gap" then
    if maySend() then
      requestSync(st, team, name)
    end
  elseif result == "conflict" then
    replyRoster(team, name)
  end
end

local function onLeave(st, _, name, v)
  local team = st.teams[v.tid]
  if not team or not member(team, name) then
    return
  end
  if TL.Apply(team, name, { kind = "leave" }) then
    heard[PN.Key(name)] = nil
    announce(v.tid, "members")
  end
end

local function onRemove(st, me, name, v)
  local team = st.teams[v.tid]
  if team then
    afterRemote(st, me, name, team, (TL.ApplyRemote(team, name, v.epoch, { kind = "remove", name = v.name })))
  end
end

local function onUpdate(st, me, name, v)
  local team = st.teams[v.tid]
  if not team then
    return
  end
  if v.op.kind == "dissolve" then
    if TL.IsAdmin(team, name) then
      forget(st, v.tid)
      announce(v.tid, "dissolved")
    end
    return
  end
  afterRemote(st, me, name, team, (TL.ApplyRemote(team, name, v.epoch, v.op)))
end

local function onSync(st, me, name, v)
  local team = st.teams[v.tid]
  if not team or not member(team, name) or not maySend() then
    return
  end
  noteHeard(st, name)
  local id, now = v.tid .. "\n" .. PN.Key(name), clock()
  if answeredAt[id] and now - answeredAt[id] < Teams.ANSWER_GAP then
    return
  end
  answeredAt[id] = now
  if team.epoch > v.epoch and TL.IsAdmin(team, me) then
    sendRoster(team, { name })
  end
  local missing, more = TL.Missing(st.history[v.tid], v.vector)
  if #missing > 0 then
    fanout({ name }, T.ANSWER, TL.EncodeAnswer(v.tid, more, missing), v.tid)
  end
end

local function onAnswer(st, me, name, v)
  local team = st.teams[v.tid]
  local id = v.tid .. "\n" .. PN.Key(name)
  local pend = syncPending[id]
  if not team or not pend or clock() - pend.at > Teams.SYNC_PENDING or not member(team, name) then
    return
  end
  syncPending[id] = nil
  noteHeard(st, name)
  local now, added = clock(), 0
  local recovering = (st.counters[v.tid] or 0) == 0
  for _, raw in ipairs(v.msgs) do
    local author = member(team, raw.sender)
    -- Our own lines come back only into a store that never sent in this team (a new install): they give the
    -- counter back, so new lines are not taken for duplicates. Otherwise our history is the truth.
    local ours = author ~= nil and PN.Equal(author, me)
    if ours and (not recovering or raw.counter > Teams.COUNTER_JUMP) then
      author = nil
    end
    if author then
      local m = { sender = author, counter = raw.counter, time = TL.ClampTime(raw.time, now), text = raw.text }
      if addMessage(st, v.tid, m, now) then
        if ours and raw.counter > (st.counters[v.tid] or 0) then
          st.counters[v.tid] = raw.counter
        end
        mirror(team, m, true, me)
        added = added + 1
      end
    end
  end
  if added > 0 then
    announce(v.tid, "message")
    announceConv(v.tid)
  end
  local round = rounds[v.tid]
  if v.more and added > 0 and round and round.chain < Teams.SYNC_CHAIN and maySend() then
    round.chain = round.chain + 1
    requestSync(st, team, name)
  end
end

local function onFarewell(_, _, name)
  silent[PN.Key(name)] = true
  announce(nil, "online")
end

-- The line -----------------------------------------------------------------------------------------------------------

-- The game's answer to a whisper to somebody who is not there. Registered once the user has a consent.
local listening = false
local function listen()
  if listening then
    return
  end
  listening = true
  FG.On("CHAT_MSG_SYSTEM", function(_, text)
    Teams.OnSystemMessage(text)
  end)
end

-- Registers with the first consent, never at load.
function Teams.Register()
  if not registered then
    registered = Comm.Register(FN, {
      version = 1,
      audiences = { "whisper" },
      on = {
        [T.INVITE] = guarded(onInvite),
        [T.ACCEPT] = guarded(onAccept),
        [T.DECLINE] = guarded(onDecline),
        [T.ROSTER] = guarded(onRoster),
        [T.MSG] = guarded(onMessage),
        [T.LEAVE] = guarded(onLeave),
        [T.REMOVE] = guarded(onRemove),
        [T.UPDATE] = guarded(onUpdate),
        [T.SYNC] = guarded(onSync),
        [T.ANSWER] = guarded(onAnswer),
        [T.FAREWELL] = guarded(onFarewell),
      },
      decode = function(payload, typ)
        return TL.Decode(typ, payload)
      end,
      farewell = T.FAREWELL,
      whisperPeer = acceptWhisper,
      -- The line asks before every block: the bucket of bytes replaces the bucket per message of the channel.
      gate = function(cost, now, target)
        return pacer.Take(cost, now, target and PN.Key(target) or nil)
      end,
    }) == true
    if registered then
      listen()
    end
  end
  return registered
end

-- The text of a refusal reason of the interface (consent, notadmin, toolong ..), the reason itself for an unknown one.
function Teams.ReasonText(reason)
  local text = FG.L["chat.teams.reason." .. tostring(reason)]
  if type(text) == "string" and text ~= "" and not text:find("^chat%.teams%.") then
    return text
  end
  return tostring(reason)
end

-- The text of a state of an own message ("waiting") or of a member ("offline").
function Teams.StateText(which)
  local text = FG.L["chat.teams.state." .. tostring(which)]
  if type(text) == "string" and text ~= "" and not text:find("^chat%.teams%.") then
    return text
  end
  return tostring(which)
end

-- The text of the delivery count of an own message ({ state, done, total, held } of Teams.Messages): waiting (for the
-- end of combat when held), "to N of M", "to everyone", "nobody is online".
function Teams.DeliveryText(delivery)
  local which = type(delivery) == "table" and delivery.state or "waiting"
  if which == "partial" then
    return string.format(Teams.StateText("partial"), delivery.done or 0, delivery.total or 0)
  elseif which == "waiting" then
    return Teams.StateText(type(delivery) == "table" and delivery.held and "waiting" or "queued")
  end
  return Teams.StateText(which)
end

function Teams.Registered()
  return registered
end

-- Interface: reading -------------------------------------------------------------------------------------------------

local function lastTime(st, tid)
  local msgs = st.history[tid].msgs
  return msgs[#msgs] and msgs[#msgs].time or st.teams[tid].created
end

function Teams.Unread(tid)
  local key = Conv.Key("team", tid)
  local conv = key and chat.convs.convs[key]
  return conv and chat.Unread.Count(conv) or 0
end

-- The teams of this character, the latest activity first: { id, name, icon, epoch, count, admin, unread, last }.
function Teams.List()
  local st, me = state()
  local out = {}
  if st then
    for tid, team in pairs(st.teams) do
      out[#out + 1] = {
        id = tid,
        name = team.name,
        icon = team.icon,
        epoch = team.epoch,
        count = TL.Count(team),
        admin = TL.IsAdmin(team, me),
        unread = Teams.Unread(tid),
        last = lastTime(st, tid),
      }
    end
  end
  table.sort(out, function(a, b)
    if a.last ~= b.last then
      return a.last > b.last
    end
    return a.id < b.id
  end)
  return out
end

-- Members that count as online: ourselves, and everybody who sent a packet lately and was not "not found".
function Teams.Online(tid)
  local st, me = state()
  local team = st and st.teams[tid]
  if not team then
    return {}
  end
  local out, now = {}, clock()
  for _, name in ipairs(TL.Names(team)) do
    local key = PN.Key(name)
    if
      PN.Equal(name, me) or (heard[key] and now - heard[key] <= Teams.ONLINE_WINDOW and (offline[key] or 0) <= now)
    then
      out[#out + 1] = name
    end
  end
  return out
end

-- One team with its members { name, role, joined, online, silent }, nil for an unknown team.
function Teams.Get(tid)
  local st, me = state()
  local team = st and st.teams[tid]
  if not team then
    return nil
  end
  local online = {}
  for _, name in ipairs(Teams.Online(tid)) do
    online[PN.Key(name)] = true
  end
  local members = {}
  for _, name in ipairs(TL.Names(team)) do
    local entry = team.members[name]
    members[#members + 1] = {
      name = name,
      role = entry.role,
      joined = entry.joined,
      online = online[PN.Key(name)] == true,
      silent = silent[PN.Key(name)] == true,
    }
  end
  return {
    id = tid,
    name = team.name,
    icon = team.icon,
    epoch = team.epoch,
    by = team.by,
    created = team.created,
    me = me,
    admin = TL.IsAdmin(team, me),
    members = members,
  }
end

local function waiting(tid, counter)
  for _, p in ipairs(outbox) do
    if p.tid == tid and p.typ == T.MSG and p.counter == counter then
      return true
    end
  end
  for p in pairs(inflight) do
    if p.tid == tid and p.typ == T.MSG and p.counter == counter then
      return true
    end
  end
  return false
end

-- Messages of a team, oldest first: `from` is the index of the first one (nil: the latest `count`), count at
-- most PAGE. Returns the list { sender, counter, time, text, mine, waiting, delivery } and the total. delivery is
-- { state, done, total, held } for an own message of this session (state waiting, partial, complete or nobody, total is
-- the number of members that count, held is true while combat or a restriction holds the first packet back), else nil.
function Teams.Messages(tid, from, count)
  local st, me = state()
  local h = st and st.history[tid]
  if not h then
    return {}, 0
  end
  local total = #h.msgs
  count = math.min(Teams.PAGE, math.max(1, math.floor(tonumber(count) or Teams.PAGE)))
  local first = tonumber(from) and math.max(1, math.floor(from)) or math.max(1, total - count + 1)
  local out, held = {}, locked()
  for i = first, math.min(total, first + count - 1) do
    local m = h.msgs[i]
    local mine = PN.Equal(m.sender, me)
    local delivery = mine and tally.State(tid .. ":" .. m.counter) or nil
    if delivery then
      delivery.held = held and delivery.state == "waiting"
    end
    out[#out + 1] = {
      sender = m.sender,
      counter = m.counter,
      time = m.time,
      text = m.text,
      mine = mine,
      waiting = mine and waiting(tid, m.counter) or false,
      delivery = delivery,
    }
  end
  return out, total
end

-- The open invitations { id, tid, name, icon, count, from, at, accepted }, expired ones removed first.
function Teams.Invites()
  local st = state()
  local out = {}
  if st then
    if TL.ExpireInvites(st.invites, clock()) > 0 then
      announce(nil, "invite")
    end
    for i, inv in ipairs(st.invites.list) do
      out[i] = {
        id = inv.id,
        tid = inv.tid,
        name = inv.name,
        icon = inv.icon,
        count = inv.count,
        from = inv.from,
        at = inv.at,
        accepted = inv.accepted == true,
      }
    end
  end
  return out
end

function Teams.Blocked()
  local st = state()
  local out = {}
  for _, name in pairs(st and st.blocked or {}) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

-- Interface: changes ------------------------------------------------------------------------------------------------

local function sendInvite(team, name)
  local payload = TL.EncodeInvite(team.id, team.name, team.icon, TL.Count(team))
  pendingOut[team.id] = pendingOut[team.id] or {}
  pendingOut[team.id][PN.Key(name)] = { name = name, at = clock() }
  return enqueue(name, T.INVITE, payload, team.id)
end

local function pendingCount(tid)
  local n, now = 0, clock()
  for key, pend in pairs(pendingOut[tid] or {}) do
    if now - pend.at > Teams.INVITE_TTL then
      pendingOut[tid][key] = nil
    else
      n = n + 1
    end
  end
  return n
end

-- A new team with the user as its only admin; each name gets an invitation. Returns the id, or nil and a
-- reason: consent, unavailable, full (30 teams), name, icon, member (a name that cannot be whispered), self.
function Teams.Create(name, icon, names)
  if not maySend() then
    return nil, "consent"
  end
  local st, me = state()
  if not st then
    return nil, "unavailable"
  end
  local count = 0
  for _ in pairs(st.teams) do
    count = count + 1
  end
  if count >= TL.LIMITS.MAX_TEAMS then
    return nil, "full"
  end
  local list, seen = {}, { [PN.Key(me)] = true }
  for _, raw in ipairs(type(names) == "table" and names or {}) do
    local who = TL.CleanMember(raw)
    if not who then
      return nil, "member"
    end
    if PN.Equal(who, me) then
      return nil, "self"
    end
    if not seen[PN.Key(who)] then
      seen[PN.Key(who)] = true
      list[#list + 1] = who
    end
  end
  if #list > TL.LIMITS.MAX_MEMBERS - 1 then
    return nil, "full"
  end
  local id
  repeat
    id = TL.NewId(Comm.random)
  until not st.teams[id]
  local team, why = TL.New(id, name, icon, me, clock())
  if not team then
    return nil, why
  end
  st.teams[id], st.history[id], st.counters[id] = team, TL.NewHistory(), 0
  ensureConv(team)
  for _, who in ipairs(list) do
    sendInvite(team, who)
  end
  Teams.Pump()
  announce(id, "created")
  return id, { invited = #list }
end

-- Common checks of the changes: a team, the user in it, the consent. Returns st, team, me or nil and a reason.
local function target(tid)
  if not maySend() then
    return nil, "consent"
  end
  local st, me = state()
  local team = st and st.teams[tid]
  if not team or not member(team, me) then
    return nil, "notmember"
  end
  return st, team, me
end

function Teams.Invite(tid, name)
  local st, team, me = target(tid)
  if not st then
    return false, team
  end
  if not TL.IsAdmin(team, me) then
    return false, "notadmin"
  end
  local who = TL.CleanMember(name)
  if not who then
    return false, "name"
  end
  if PN.Equal(who, me) then
    return false, "self"
  end
  if member(team, who) then
    return false, "member"
  end
  if TL.Count(team) + pendingCount(tid) >= TL.LIMITS.MAX_MEMBERS and not (pendingOut[tid] or {})[PN.Key(who)] then
    return false, "full"
  end
  if not sendInvite(team, who) then
    return false, "queuefull"
  end
  Teams.Pump()
  announce(tid, "invite")
  return true
end

local function inviteById(st, id)
  for i, inv in ipairs(st.invites.list) do
    if inv.id == id then
      return inv, i
    end
  end
end

-- Says yes to an invitation. The team appears when its admin answers with the roster. Returns true, or false
-- and a reason: consent (needs send and receive), unavailable, unknown, member.
function Teams.Accept(inviteId)
  if not maySend() or not mayReceive() then
    return false, "consent"
  end
  local st = state()
  if not st then
    return false, "unavailable"
  end
  TL.ExpireInvites(st.invites, clock())
  local inv = inviteById(st, inviteId)
  if not inv then
    return false, "unknown"
  end
  if st.teams[inv.tid] then
    removeInvites(st, inv.tid)
    return false, "member"
  end
  accepted[inv.tid] = { key = PN.Key(inv.from), at = clock() }
  inv.accepted = true
  enqueue(inv.from, T.ACCEPT, TL.EncodeTid(inv.tid), inv.tid)
  Teams.Pump()
  announce(inv.tid, "invite")
  return true
end

function Teams.Decline(inviteId)
  local st = state()
  if not st then
    return false, "unavailable"
  end
  local inv, index = inviteById(st, inviteId)
  if not inv then
    return false, "unknown"
  end
  table.remove(st.invites.list, index)
  if accepted[inv.tid] and accepted[inv.tid].key == PN.Key(inv.from) then
    accepted[inv.tid] = nil
  end
  if maySend() then
    enqueue(inv.from, T.DECLINE, TL.EncodeTid(inv.tid), inv.tid)
    Teams.Pump()
  end
  announce(inv.tid, "invite")
  return true
end

function Teams.Block(name)
  local st = state()
  if not st then
    return false, "unavailable"
  end
  local ok, why = TL.Block(st.blocked, name)
  if not ok then
    return false, why
  end
  local key = PN.Key(name)
  for i = #st.invites.list, 1, -1 do
    if PN.Key(st.invites.list[i].from) == key then
      table.remove(st.invites.list, i)
    end
  end
  announce(nil, "blocked")
  return true
end

function Teams.Unblock(name)
  local st = state()
  if not st then
    return false, "unavailable"
  end
  st.blocked[PN.Key(name)] = nil
  announce(nil, "blocked")
  return true
end

-- Leaves a team: deletes it and its history here and tells the others when sending is on. Always works locally.
function Teams.Leave(tid)
  local st, me = state()
  local team = st and st.teams[tid]
  if not team then
    return false, "notmember"
  end
  local told = false
  if maySend() then
    -- The goodbye carries no team id, so forgetting the team keeps it in the outbox.
    fanout(others(team, me), T.LEAVE, TL.EncodeTid(tid), nil)
    told = true
  end
  forget(st, tid)
  Teams.Pump()
  announce(tid, "left")
  return true, { told = told }
end

-- Applies a change of an admin and tells the members (the removed one too).
local function change(tid, op, encode)
  local st, team, me = target(tid)
  if not st then
    return false, team
  end
  local before = others(team, me)
  local ok, why = TL.Apply(team, me, op)
  if not ok then
    return false, why
  end
  local payload = encode(team)
  if payload == nil then
    return false, "payload"
  end
  fanout(before, op.kind == "remove" and T.REMOVE or T.UPDATE, payload, tid)
  ensureConv(team)
  announce(tid, "team")
  return true
end

function Teams.Remove(tid, name)
  return change(tid, { kind = "remove", name = name }, function(team)
    local who = TL.CleanMember(name)
    return who and TL.EncodeRemove(tid, team.epoch, who)
  end)
end

function Teams.SetAdmin(tid, name, admin)
  return change(tid, { kind = "role", name = name, admin = admin == true }, function(team)
    local who = TL.CleanMember(name)
    return who and TL.EncodeUpdate(tid, team.epoch, { kind = "role", name = who, admin = admin == true })
  end)
end

function Teams.Rename(tid, name)
  return change(tid, { kind = "name", name = name }, function(team)
    return TL.EncodeUpdate(tid, team.epoch, { kind = "name", name = team.name })
  end)
end

function Teams.SetIcon(tid, icon)
  return change(tid, { kind = "icon", icon = icon }, function(team)
    return TL.EncodeUpdate(tid, team.epoch, { kind = "icon", icon = team.icon })
  end)
end

-- Dissolves a team for everybody (admins only) and deletes it here.
function Teams.Dissolve(tid)
  local st, team, me = target(tid)
  if not st then
    return false, team
  end
  if not TL.IsAdmin(team, me) then
    return false, "notadmin"
  end
  fanout(others(team, me), T.UPDATE, TL.EncodeUpdate(tid, team.epoch + 1, { kind = "dissolve" }), nil)
  forget(st, tid)
  Teams.Pump()
  announce(tid, "dissolved")
  return true
end

-- Sends a text to the team: cut into parts of at most 200 bytes (never inside a character), each part is one
-- message to every other member. The text is plain text: pipe codes become a broken bar. Returns true and
-- { parts, counter, waiting } (waiting: held back by combat or a restriction), or false and a reason:
-- consent, unavailable, notmember, text, utf8, empty, toolong, queuefull, restricted (nothing more may wait).
function Teams.Send(tid, text)
  local st, team, me = target(tid)
  if not st then
    return false, team
  end
  local parts, why = TL.Split(text)
  if not parts then
    return false, why
  end
  -- Members known to be offline are not asked again for a while, they catch up when they come back.
  local names, soon = {}, clock()
  for _, name in ipairs(others(team, me)) do
    if (offline[PN.Key(name)] or 0) <= soon then
      names[#names + 1] = name
    end
  end
  names = shuffled(names)
  local isLocked = locked()
  if #outbox + #parts * #names > Teams.MAX_OUTBOX then
    return false, isLocked and "restricted" or "queuefull"
  end
  local author = member(team, me)
  local h, now = st.history[tid], clock()
  local counter = math.max(st.counters[tid] or 0, TL.Vector(h, team)[PN.Key(author)].counter)
  for _, part in ipairs(parts) do
    counter = counter + 1
    local m = { sender = author, counter = counter, time = now, text = part }
    if addMessage(st, tid, m, now) then
      mirror(team, m, false, me)
    end
    local payload = TL.EncodeMessage(tid, counter, now, part)
    local mkey, queued = tid .. ":" .. counter, 0
    for _, name in ipairs(names) do
      if enqueue(name, T.MSG, payload, tid) then
        outbox[#outbox].counter, outbox[#outbox].mkey = counter, mkey
        queued = queued + 1
      end
    end
    tally.Expect(mkey, queued)
  end
  st.counters[tid] = counter
  Teams.Pump()
  announce(tid, "message")
  announceConv(tid)
  return true, { parts = #parts, counter = counter, waiting = isLocked }
end

-- Consent and switches -----------------------------------------------------------------------------------------------

-- The goodbye of the line goes to every member we sent to; the outbox is emptied first (the send consent is off).
local function goodbye()
  outbox, inflight = {}, {}
  if not registered then
    return
  end
  local st = state()
  local done = {}
  for _, team in pairs(st and st.teams or {}) do
    for name in pairs(team.members) do
      local key = PN.Key(name)
      if not done[key] and not PN.Equal(name, selfName() or "") then
        done[key] = true
        Comm.Send(FN, T.FAREWELL, TL.FAREWELL_PAYLOAD, "whisper", name)
      end
    end
  end
end

local function clearReceived()
  local st = state()
  if st then
    st.invites = TL.NewInbox()
  end
  syncPending, accepted, heard, rate = {}, {}, {}, {}
  announce(nil, "invite")
end

FG.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if fn ~= FN or aud ~= "chat" then
    return
  end
  if value == true then
    Teams.Register()
  elseif dir == "send" then
    goodbye()
  else
    clearReceived()
  end
end)
FG.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == FN then
    goodbye()
    clearReceived()
  end
end)
FG.On("FG_SUBADDON_CHANGED", function(_, id)
  if id ~= "chat" then
    return
  end
  if not switchedOn() then
    goodbye()
    clearReceived()
    if registered then
      Comm.Unregister(FN)
      registered = false
    end
  elseif Consent.Allows(FN, "send", "chat") or Consent.Allows(FN, "receive", "chat") then
    Teams.Register()
  end
end)
FG.On("PLAYER_REGEN_ENABLED", function()
  if #outbox > 0 then
    Teams.Pump()
  end
end)
-- Login and every loading screen: the game counts less for a few seconds, so the pace drops to a tenth.
FG.On("PLAYER_ENTERING_WORLD", function()
  pacer.Zone()
end)
local function login()
  Teams.Load()
  if maySend() and mayReceive() then
    local timer = g("C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
      pcall(timer.After, Teams.SYNC_DELAY, function()
        FG.Safe("chat-teams", Teams.ResyncAll)
      end)
    end
  end
end
FG.On("PLAYER_LOGIN", function()
  FG.Safe("chat-teams", login)
end)

if Consent.Allows(FN, "send", "chat") or Consent.Allows(FN, "receive", "chat") then
  Teams.Register()
end
-- The sub-addon is there: the tab "Share" lists the function.
if Consent.MarkAvailable then
  Consent.MarkAvailable(FN)
end
-- The teams come from the store, which is read at ADDON_LOADED.
FG.On("FG_CHAT_STORE_READY", function()
  loadedFor = nil
  FG.Safe("chat-teams", Teams.Load)
end)

-- Test and state access: counts only, no names.
function Teams.Status()
  local pending = 0
  for _ in pairs(syncPending) do
    pending = pending + 1
  end
  local inflightCount, dropped = 0, {}
  for _ in pairs(inflight) do
    inflightCount = inflightCount + 1
  end
  for reason, n in pairs(counters.dropped) do
    dropped[reason] = n
  end
  local tokens, factor = pacer.Level()
  return {
    registered = registered,
    outbox = #outbox,
    inflight = inflightCount,
    syncPending = pending,
    filter = filterOn,
    sent = counters.sent,
    throttled = counters.throttled,
    lockdown = counters.lockdown,
    offline = counters.offline,
    errors = counters.errors,
    dropped = dropped,
    tokens = tokens,
    pace = factor,
  }
end

-- The state of a character for tests and diagnostics (the store itself, not a copy).
function Teams.Store()
  return (state())
end
