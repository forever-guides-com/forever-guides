-- Forever Chat, sending. One gateway for every kind of conversation: the text is cut into parts (SendLogic),
-- every part goes through the game's chat function (SendChatMessage, or C_ChatInfo.SendChatMessage when it
-- exists) in a pcall with a pause between the parts, and every outcome becomes a delivery state. Own lines
-- appear in the conversation with line.delivery (queued, sent, waiting, failed).
--
-- Send runs only for an explicit action of the player (Enter in the input line). Nothing here registers an
-- event or sends on its own. While the client restricts chat, a message waits in ChatQueue and only a click
-- (Queue.Release) sends it. The restriction calls are not measured in the client yet: Restricted answers
-- "not restricted" whenever a function is missing, secret or raises an error.
--
-- Events (FG.Emit): FG_CHAT_SEND_STATE (key, job) on every state change, FG_CHAT_SENT (key, job) when every
-- part went out.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local SL, Queue, Conv, PN = chat.SendLogic, chat.Queue, chat.Conversations, FG.PlayerName

local Send = {}
chat.Send = Send

local function global(name)
  return rawget(_G, name)
end

-- The value, or nil when it is secret or the client says the add-on may not read it.
local function safe(value)
  local guard = FG.AutoGuard
  if guard and guard.Safe then
    return guard.Safe(value)
  end
  return value
end

-- First result of a game function, nil when it is missing or raises an error.
local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if ok then
    return value
  end
end

-- true, false, or nil for a missing, secret or non-boolean answer.
local function flag(value)
  value = safe(value)
  if type(value) == "boolean" then
    return value
  end
end

local function isTrue(value)
  value = safe(value)
  if value == nil then
    return false
  end
  local ok, hit = pcall(function()
    return value == true
  end)
  return ok and hit
end

-- What the game says about the player's groups and guild. Unknown stays nil and never blocks.
local function gameFacts()
  local info = global("C_GuildInfo")
  local guildName = safe(call(global("GetGuildInfo"), "player"))
  return {
    inHomeGroup = flag(call(global("IsInGroup"), global("LE_PARTY_CATEGORY_HOME") or 1)),
    inInstanceGroup = flag(call(global("IsInGroup"), global("LE_PARTY_CATEGORY_INSTANCE") or 2)),
    inRaid = flag(call(global("IsInRaid"))),
    inGuild = flag(call(global("IsInGuild"))),
    guildName = type(guildName) == "string" and guildName or nil,
    canOfficer = type(info) == "table" and flag(call(info.IsGuildOfficer)) or nil,
  }
end

-- Everything the gateway takes from the game, replaceable for tests (Send.Env.field = ..., Send.ResetEnv()).
local function defaultEnv()
  return {
    delay = SL.DELAY,
    time = function()
      local fn = global("time")
      return type(fn) == "function" and fn() or 0
    end,
    -- Runs fn after delay seconds, false when the client has no timer.
    after = function(delay, fn)
      local timer = global("C_Timer")
      if type(timer) ~= "table" or type(timer.After) ~= "function" then
        return false
      end
      timer.After(delay, fn)
      return true
    end,
    send = function(text, chatType, target)
      local api = global("C_ChatInfo")
      local fn = type(api) == "table" and type(api.SendChatMessage) == "function" and api.SendChatMessage
        or global("SendChatMessage")
      if type(fn) ~= "function" then
        error("no chat function", 0)
      end
      return fn(text, chatType, nil, target)
    end,
    facts = gameFacts,
    -- The number of a joined channel (given its name or number), nil otherwise.
    channel = function(ref)
      local id = safe(call(global("GetChannelName"), ref))
      return type(id) == "number" and id > 0 and id or nil
    end,
    inInstance = function()
      return flag(call(global("IsInInstance"))) == true
    end,
    homeRealm = function()
      local realm = safe(call(global("GetNormalizedRealmName")))
      return type(realm) == "string" and realm or nil
    end,
    own = function()
      return call(PN.Self) or ""
    end,
    emit = function(...)
      if FG.Emit then
        FG.Emit(...)
      end
    end,
    wrap = function(fn)
      return FG.Wrap and FG.Wrap("chat-send", fn) or fn
    end,
    convs = function()
      return chat.convs
    end,
  }
end

Send.Env = defaultEnv()

function Send.ResetEnv()
  Send.Env = defaultEnv()
end

local pipeline, recent, timerPending, nextId, generation = {}, {}, false, 0, 0

-- Forgets every job and pending timer (tests, logout).
function Send.Reset()
  pipeline, recent, timerPending, nextId = {}, {}, false, 0
  generation = generation + 1
  Queue.Clear()
end

-- Whether parts are still on their way.
function Send.Busy()
  return #pipeline > 0
end

----------------------------------------------------------------------------------------------------
-- Restriction and availability
----------------------------------------------------------------------------------------------------

-- Whether the client keeps add-ons from sending chat right now: true and "lockdown" or "chat", else false.
function Send.Restricted()
  local info = global("C_ChatInfo")
  if type(info) == "table" and isTrue(call(info.InChatMessagingLockdown)) then
    return true, "lockdown"
  end
  local actions, enum = global("C_RestrictedActions"), global("Enum")
  local types = type(enum) == "table" and enum.AddOnRestrictionType
  if type(actions) == "table" and type(types) == "table" and types.Chat ~= nil then
    if isTrue(call(actions.IsAddOnRestrictionActive, types.Chat)) then
      return true, "chat"
    end
  end
  return false
end

-- Whether the player can write to the conversation (a table with key, kind, name, or a key): true, or false
-- and a reason (group, raid, instance, guild, officer, conversation).
function Send.Available(conv)
  return SL.Available(conv, Send.Env.facts())
end

----------------------------------------------------------------------------------------------------
-- Jobs
----------------------------------------------------------------------------------------------------

local LINE_STATE = { queued = "queued", sending = "queued", waiting = "waiting", failed = "failed", sent = "sent" }

-- Unsent parts show the state of the job.
local function paintLines(job)
  for i = job.index, #job.parts do
    local line = job.lines[i]
    if line then
      line.delivery, line.reason = LINE_STATE[job.state], job.reason
    end
  end
end

local function changed(job)
  paintLines(job)
  local emit = Send.Env.emit
  emit("FG_CHAT_SEND_STATE", job.conv.key, job)
  if job.state == "sent" then
    emit("FG_CHAT_SENT", job.conv.key, job)
  end
end

-- The own lines of a job, one per part. A line the model refuses (a copy within two seconds, no room) is
-- skipped, the part is sent all the same. The target is only used when it names the very conversation.
local function addLines(job)
  local env, state = Send.Env, Send.Env.convs()
  local conv = job.conv
  local target = { kind = conv.kind, name = conv.name, homeRealm = env.homeRealm() }
  if not state or Conv.Key(target.kind, target.name, target.homeRealm) ~= conv.key then
    for i = 1, #job.parts do
      job.lines[i] = false
    end
    return
  end
  local own = state.own ~= "" and state.own or env.own()
  for i, part in ipairs(job.parts) do
    local line = Conv.AddLine(state, target, {
      time = env.time(),
      text = part,
      sender = own,
      dir = FG.ChatHistoryLogic.DIR_OUT,
    })
    if line then
      line.sendId = job.id
    end
    job.lines[i] = line or false
  end
end

local function removeFromPipeline(job)
  for i, item in ipairs(pipeline) do
    if item == job then
      table.remove(pipeline, i)
      return
    end
  end
end

-- The job leaves the pipeline and waits for the player in the queue. A full queue ends it as failed.
local function park(job, to, reason)
  removeFromPipeline(job)
  SL.Move(job, to, reason)
  if not Queue.Add(job) and job.state == "waiting" then
    SL.Move(job, "failed", "queuefull")
  end
  changed(job)
end

-- Numbered channels outside instances take one message per click.
local function isGated(job)
  return job.chatType == "CHANNEL" and not Send.Env.inInstance()
end

local pump

-- Calls pump after the pause between two parts. Without a timer in the client it goes on at once.
local function later()
  if timerPending then
    return
  end
  timerPending = true
  local env, token = Send.Env, generation
  local function run()
    if token ~= generation then
      return
    end
    timerPending = false
    pump()
  end
  if not env.after(env.delay, env.wrap(run)) then
    timerPending = false
    pump()
  end
end

local function sendPart(job)
  local env = Send.Env
  if job.state == "queued" then
    SL.Move(job, "sending")
    changed(job)
  end
  local ok, ret = pcall(env.send, job.parts[job.index], job.chatType, job.target)
  local state, reason = SL.Outcome(ok, ret)
  if state == "failed" then
    park(job, "failed", reason)
    return
  end
  local line = job.lines[job.index]
  if line then
    line.delivery, line.reason = "sent", nil
  end
  job.index = job.index + 1
  if job.index > #job.parts then
    removeFromPipeline(job)
    SL.Move(job, "sent")
    recent[#recent + 1] = { job = job, at = env.time() }
    while #recent > 10 do
      table.remove(recent, 1)
    end
    changed(job)
  elseif job.gated then
    park(job, "waiting", "click")
  end
end

-- Sends the next part of the first job in line, then asks for the pause.
pump = function()
  local job = pipeline[1]
  if not job then
    return
  end
  if Send.Restricted() then
    for _, item in ipairs({ unpack(pipeline) }) do
      park(item, "waiting", "restricted")
    end
    return
  end
  local available, why = Send.Available(job.conv)
  if available then
    sendPart(job)
  else
    park(job, "failed", why)
  end
  if pipeline[1] then
    later()
  end
end

-- Sends a text to a conversation (a table with key, kind, name, or a key). Returns the job (state queued,
-- sending, sent or waiting, read it through job.state and the events) or nil and a refusal reason: the
-- ones of SendLogic.Split, Route and Available, or "queuefull". Nothing has been sent or kept then. Call it
-- from an explicit action of the player only.
function Send.Send(conv, text)
  local target = SL.Target(conv)
  if not target then
    return nil, "conversation"
  end
  local parts, why = SL.Split(text)
  if not parts then
    return nil, why
  end
  local env = Send.Env
  local available, reason = SL.Available(conv, env.facts())
  if not available then
    return nil, reason
  end
  local chatType, to = SL.Route(conv, env.channel)
  if not chatType then
    return nil, to
  end
  local restricted = Send.Restricted()
  if restricted and not Queue.CanAdd() then
    return nil, "queuefull"
  end
  local key = type(conv) == "table" and conv.key or conv
  nextId = nextId + 1
  local job = SL.NewJob(nextId, { key = key, kind = target.kind, name = target.name }, chatType, to, parts, env.time())
  job.gated = isGated(job)
  addLines(job)
  if restricted then
    park(job, "waiting", "restricted")
  else
    pipeline[#pipeline + 1] = job
    changed(job)
    if not timerPending then
      pump()
    end
  end
  return job
end

-- Sends a held job on a click (Queue.Release calls it): a waiting job goes on with its next part, a failed
-- one tries again from the part that failed. Returns true, or false and a reason.
function Send.Resume(job)
  if type(job) ~= "table" or (job.state ~= "waiting" and job.state ~= "failed") then
    return false, "state"
  end
  if Send.Restricted() then
    return false, "restricted"
  end
  local available, why = Send.Available(job.conv)
  if not available then
    return false, why
  end
  job.gated = isGated(job)
  local moved, reason = SL.Move(job, "queued", nil, true)
  if not moved then
    return false, reason
  end
  pipeline[#pipeline + 1] = job
  changed(job)
  if not timerPending then
    pump()
  end
  return true
end

-- A system message of the game. "No player named X" turns a whisper that went out a moment ago into a
-- failed one (a click can try again). The caller passes the text of the system message event; nothing here listens.
-- Returns whether a message was marked.
function Send.OnSystemMessage(text)
  text = safe(text)
  local name = SL.NotFoundName(text, global("ERR_CHAT_PLAYER_NOT_FOUND_S"))
  if not name then
    return false
  end
  local now = Send.Env.time()
  for i = #recent, 1, -1 do
    local job, at = recent[i].job, recent[i].at
    if job.state == "sent" and job.chatType == "WHISPER" and now - at <= SL.NOT_FOUND_WINDOW then
      if PN.Equal(name, job.target) then
        table.remove(recent, i)
        job.index = 1
        park(job, "failed", "notfound")
        return true
      end
    end
  end
  return false
end

-- True when a whisper of the messenger to this name went out a moment ago, so a "not found" line may be its answer.
function Send.RecentTo(name)
  local now = Send.Env.time()
  for _, entry in ipairs(recent) do
    local job = entry.job
    if job.chatType == "WHISPER" and now - entry.at <= SL.NOT_FOUND_WINDOW and PN.Equal(name, job.target) then
      return true
    end
  end
  return false
end

Queue.Now = function()
  return Send.Env.time()
end
Queue.Hooks.resume = Send.Resume
Queue.Hooks.drop = function(job, reason)
  if job.state == "waiting" then
    SL.Move(job, "failed", reason)
  end
  changed(job)
end
