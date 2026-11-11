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
-- A call the game refuses is no Lua error: pcall answers true and the game raises ADDON_ACTION_BLOCKED instead.
-- The input line passes that event to OnBlocked, which marks the call that is running. A refused call never
-- counts as sent. Every message tries the chat function of the game first, in the Enter key or the click of the
-- player, and nothing about a refusal is remembered: it touches that one message. That message goes into the chat
-- box of the game (the job waits with the reason "enter", shown as "Waiting for Enter") and its row offers "Send now".
--
-- "Send now" is a secure action button (ChatSecure.lua) over the plain button, with the macro line of exactly that
-- message. It runs for a real mouse click of the player only. Code never clicks it: Button:Click on it raises
-- RunMacroText forbidden and a dialog of the game that offers to disable the add-on. Plan tells whether the button
-- may be offered; a click runs the macro and calls Committed afterwards, which makes (or continues) the job and
-- waits for the own line the game echoes back (OnOwnLine). A refusal reported meanwhile (OnBlocked) turns the job
-- into a box job and the verdict "blocked" ends the offer for this chat type in this build. Without a refusal and
-- without an echo after WayLogic.ECHO_WAIT seconds the job counts as sent with the note "noecho".
--
-- Every mark says why (job.detail: the function the game named, the shortened error, the seconds without an echo). A
-- refusal counts only when ForeverGuides_Chat is named (SendLogic.OwnBlock), never one of another add-on. A guild message
-- whose own line does not come back stays "sent" with the note "noecho". The chat name goes in front of the text before
-- it is cut (Send.Decorate). The last sends are kept for /fg diag chat (TraceLines).
--
-- Events (FG.Emit): FG_CHAT_SEND_STATE (key, job) on every state change, FG_CHAT_SENT (key, job) when every
-- part went out.
local addonName, chat = ...
local FG = chat.FG
if not FG then
  return
end

local SL, Queue, Conv, PN, WL = chat.SendLogic, chat.Queue, chat.Conversations, FG.PlayerName, chat.WayLogic

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

-- What the game says about the player's groups and guild, only the facts the kind of conversation needs (a guild
-- message asks no group function and a party message no guild function). Unknown stays nil and never blocks.
local function gameFacts(kind)
  local facts = {}
  if kind == "party" then
    facts.inHomeGroup = flag(call(global("IsInGroup"), global("LE_PARTY_CATEGORY_HOME") or 1))
    facts.inRaid = flag(call(global("IsInRaid")))
  elseif kind == "raid" then
    facts.inRaid = flag(call(global("IsInRaid")))
  elseif kind == "instance" then
    facts.inInstanceGroup = flag(call(global("IsInGroup"), global("LE_PARTY_CATEGORY_INSTANCE") or 2))
  elseif kind == "guild" or kind == "officer" then
    local guildName = safe(call(global("GetGuildInfo"), "player"))
    facts.inGuild = flag(call(global("IsInGuild")))
    facts.guildName = type(guildName) == "string" and guildName or nil
    if kind == "officer" then
      local info = global("C_GuildInfo")
      facts.canOfficer = type(info) == "table" and flag(call(info.IsGuildOfficer)) or nil
    end
  end
  return facts
end

-- The chat function of the game: C_ChatInfo.SendChatMessage when it exists, else the global one. alt asks for the
-- other one (nil when there is no other).
local function chatFunction(alt)
  local api = global("C_ChatInfo")
  local namespaced = type(api) == "table" and type(api.SendChatMessage) == "function" and api.SendChatMessage or nil
  local plain = type(global("SendChatMessage")) == "function" and global("SendChatMessage") or nil
  if alt then
    return namespaced and plain and plain ~= namespaced and plain or nil, "SendChatMessage"
  end
  if namespaced then
    return namespaced, "C_ChatInfo.SendChatMessage"
  end
  return plain, "SendChatMessage"
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
    send = function(text, chatType, target, alt)
      local fn, name = chatFunction(alt)
      if type(fn) ~= "function" then
        error("no chat function", 0)
      end
      Send.lastApi = name
      return fn(text, chatType, nil, target)
    end,
    -- Whether a refused call may be tried once with the other chat function (the default sender only).
    canRetry = function()
      return Send.Env.send == Send.DefaultSend and chatFunction(true) ~= nil
    end,
    -- Whether a message goes into the chat box of the game for the player's own Enter (the option "game input box"),
    -- never in combat: nothing of the game is touched then.
    gameInput = function()
      local settings = chat.Settings
      if not (settings and settings.Value and settings.Value("gameInput") == true) then
        return false
      end
      return flag(call(global("InCombatLockdown"))) ~= true
    end,
    clock = function()
      local fn = global("GetTime")
      return type(fn) == "function" and fn() or 0
    end,
    -- The clock time of a send for the report.
    stamp = function()
      local fn = global("date")
      return type(fn) == "function" and fn("%H:%M:%S") or "?"
    end,
    -- Whether the own line of a guild message comes back to this add-on (the intake listens), so its absence means
    -- something.
    echoExpected = function()
      local ingest = chat.Ingest
      return type(ingest) == "table" and type(ingest.IsRunning) == "function" and ingest.IsRunning() == true
    end,
    -- The text with the chat name in front (ChatName.Decorate), nil when the chat name stays out of this message.
    prefix = function(text, chatType, channel, quiet)
      local name = FG.ChatName
      if type(name) == "table" and type(name.Decorate) == "function" then
        return (name.Decorate(text, chatType, channel, quiet))
      end
    end,
    -- The name of a joined channel by its number.
    channelName = function(id)
      local _, name = call(global("GetChannelName"), id)
      return safe(name)
    end,
    -- Puts a part into the chat box of the game (SendLogic.BoxLine) and opens it. Nothing is sent. Returns whether
    -- the box took it.
    openChat = function(box)
      if box.tell then
        local tell, active = global("ChatFrame_SendTell"), global("ChatEdit_GetActiveWindow")
        local edit = type(tell) == "function" and pcall(tell, box.tell) and call(active)
        if type(edit) == "table" and type(edit.SetText) == "function" and pcall(edit.SetText, edit, box.text) then
          return true
        end
        box = { line = "/w " .. box.tell .. " " .. box.text }
      end
      local util = global("ChatFrameUtil")
      local open = type(util) == "table" and util.OpenChat or global("ChatFrame_OpenChat")
      return type(open) == "function" and pcall(open, box.line) == true
    end,
    facts = gameFacts,
    -- The build number as text ("unknown" when the client does not tell it; that memory lives for the session only,
    -- see memory).
    build = function()
      local client = FG.Client
      local info = type(client) == "table" and type(client.Info) == "function" and client.Info() or nil
      return WL.BuildText(info and info.build) or Send.UNKNOWN_BUILD
    end,
    -- The secure button: true when it works now, else false and why ("combat", "nosecure").
    secure = function()
      local secure = chat.Secure
      if secure and secure.State then
        return secure.State()
      end
      return false, "nosecure"
    end,
    -- The memory of the ways (saved with the store of the add-on).
    memory = function()
      local db = chat.db
      if type(db) ~= "table" or Send.Env.build() == Send.UNKNOWN_BUILD then
        return Send.Fallback
      end
      if type(db.sendWays) ~= "table" then
        db.sendWays = WL.NewMemory()
      end
      return db.sendWays
    end,
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

-- The memory of the ways when the store is not there (tests, before the store is read) or the build is unknown:
-- a verdict that cannot be tied to a build is not saved.
Send.Fallback = WL.NewMemory()
Send.UNKNOWN_BUILD = "unknown"

Send.Env = defaultEnv()
Send.DefaultSend = Send.Env.send

function Send.ResetEnv()
  Send.Env = defaultEnv()
  Send.DefaultSend = Send.Env.send
end

local pipeline, recent, timerPending, nextId, generation = {}, {}, false, 0, 0
-- inFlight: a call of the game (or a secure click) is running, hit: the game reported it as refused. verifying:
-- jobs of a secure click that wait for the own line of the game.
local inFlight, hit, verifying = false, false, {}
-- The function the game named in the last refusal that belonged to this add-on (nil when it named none), and the
-- direct sends of the guild that wait for their own line.
local blockFn, watching = nil, {}
-- Diagnosis state (see the section below).
local attempts, stats, writes, current, lastOk, lastBlocked = {}, {}, {}, nil, nil, nil
-- The last sends for the report: one entry per job, newest last.
local trail = {}
Send.MAX_TRAIL = 10

-- Forgets every job and pending timer (tests, logout).
function Send.Reset()
  pipeline, recent, timerPending, nextId = {}, {}, false, 0
  inFlight, hit, verifying = false, false, {}
  blockFn, watching, trail = nil, {}, {}
  attempts, stats, writes, current, lastOk, lastBlocked = {}, {}, {}, nil, nil, nil
  generation = generation + 1
  Queue.Clear()
end

----------------------------------------------------------------------------------------------------
-- Memory of the ways
----------------------------------------------------------------------------------------------------

-- Writes the verdict of the secure button for a chat type (and the target: a whisper to a name with a surname has its
-- own key). way: "secure"; verdict: ok or blocked. The memory belongs to the current build.
function Send.RecordWay(chatType, target, way, verdict)
  local env = Send.Env
  return WL.Record(env.memory(), env.build(), WL.Key(chatType, target), way, verdict)
end

-- The game refused the secure send of a job. A refusal that names the macro function (RunMacroText) says the client
-- forbids the function for the add-on, whatever the chat type: the button is not offered for any chat type then.
local function recordSecureRefusal(job, fn)
  Send.RecordWay(job.chatType, job.target, "secure", "blocked")
  if WL.IsMacroRefusal(fn) then
    WL.Record(Send.Env.memory(), Send.Env.build(), WL.ANY_KEY, "secure", "blocked")
  end
end

-- "ok", "blocked" or nil: what the memory says about the secure button for a chat type in this build.
function Send.WayState(chatType, target, way)
  local env = Send.Env
  return WL.Lookup(env.memory(), env.build(), WL.Key(chatType, target), way)
end

-- Whether parts are still on their way.
function Send.Busy()
  return #pipeline > 0
end

----------------------------------------------------------------------------------------------------
-- Diagnosis: what a refused call looked like
----------------------------------------------------------------------------------------------------

-- One entry per call of the chat function: { at, chatType, trigger, api, outcome ("sent", "blocked", "failed"),
-- retry }. The error page asks for the context of a refused call (Send.Diag); nothing here is sent anywhere.
Send.MAX_ATTEMPTS = 40
Send.MAX_WRITES = 8

-- Notes that this add-on wrote to an object of the game (a chat box, a frame): a refused call asks which writes came
-- shortly before it.
function Send.Touch(what)
  writes[#writes + 1] = { at = Send.Env.clock(), what = tostring(what) }
  while #writes > Send.MAX_WRITES do
    table.remove(writes, 1)
  end
end

-- Calls per chat type as { { chatType, sent, blocked, failed } } in name order, and the last calls.
function Send.Stats()
  local out = {}
  for chatType, item in pairs(stats) do
    out[#out + 1] = { chatType = chatType, sent = item.sent, blocked = item.blocked, failed = item.failed }
  end
  table.sort(out, function(a, b)
    return a.chatType < b.chatType
  end)
  return out
end

function Send.Attempts()
  return attempts
end

-- Forgets the counts and the list of calls (the series of the probe starts again).
function Send.ClearStats()
  attempts, stats = {}, {}
  lastOk, lastBlocked = nil, nil
end

-- An own line the game echoed back for a call that went out a moment ago: the call counts as echoed.
local function noteEcho(key, text)
  local now = Send.Env.clock()
  for i = #attempts, math.max(1, #attempts - 10), -1 do
    local item = attempts[i]
    if item.key == key and item.len == #text and item.outcome == "sent" and not item.echo and now - item.at <= 10 then
      item.echo = true
      return
    end
  end
end

local function secureState(name, ...)
  local fn = global("issecurevariable")
  if type(fn) ~= "function" then
    return { name = name }
  end
  local ok, secure, who = pcall(fn, ...)
  if not ok then
    return { name = name }
  end
  return { name = name, secure = secure == true, who = type(who) == "string" and who or nil }
end

-- The hooks and wrappers of this add-on that sit on chat functions or chat boxes of the game.
local function hooksOfAddon()
  local out = {}
  if chat.Input and chat.Input.linkHooked then
    out[#out + 1] = "post-hook InsertLink"
  end
  local name, badge = FG.ChatName, FG.ChatBadge
  if type(name) == "table" and type(name.Installed) == "function" and call(name.Installed) == true then
    out[#out + 1] = "chat name: script hooks on chat boxes"
  end
  if type(badge) == "table" and type(badge.Listening) == "function" and call(badge.Listening) == true then
    out[#out + 1] = "chat badge: AddMessage of chat windows replaced"
  end
  return out
end

local function recentWrites(now)
  local out = {}
  for _, item in ipairs(writes) do
    local age = now - item.at
    if age >= 0 and age <= 10 then
      out[#out + 1] = string.format("%s %.1fs before", item.what, age)
    end
  end
  return out
end

local function recentLine(text, key)
  local state = Send.Env.convs()
  local conv = state and state.convs and state.convs[key]
  local lines = conv and conv.lines
  if type(lines) ~= "table" then
    return false
  end
  for i = #lines, math.max(1, #lines - 2), -1 do
    if lines[i].text == text then
      return true
    end
  end
  return false
end

-- The context of the call that is running or ran last, as the text of the error page. who: the add-on the game names.
function Send.Diag(who)
  if type(who) == "string" and who ~= addonName then
    return nil
  end
  local env = Send.Env
  local now = env.clock()
  local item = current or attempts[#attempts] or {}
  local data = {
    chatType = item.chatType,
    trigger = item.trigger,
    api = item.api,
    retry = item.retry,
    len = item.len,
    links = item.links,
    same = item.same,
    sinceOk = lastOk and now - lastOk or nil,
    sinceBlocked = lastBlocked and now - lastBlocked or nil,
    secure = {
      secureState("SendChatMessage", "SendChatMessage"),
      secureState("C_ChatInfo.SendChatMessage", global("C_ChatInfo"), "SendChatMessage"),
    },
    hooks = hooksOfAddon(),
    writes = recentWrites(now),
    stats = Send.Stats(),
  }
  local active = global("ChatEdit_GetActiveWindow")
  data.gameBox = type(active) == "function" and call(active) ~= nil or nil
  return SL.DiagText(data)
end

local function diagBegin(job, part)
  local env = Send.Env
  current = {
    at = env.clock(),
    chatType = job.chatType,
    key = job.conv.key,
    trigger = job.trigger or "later",
    len = #part,
    links = SL.CountLinks(part),
    same = recentLine(part, job.conv.key),
    api = Send.lastApi,
  }
  return current
end

local function diagEnd(item, ok, blocked, retry)
  local env = Send.Env
  item.api, item.retry = Send.lastApi or item.api, retry
  item.outcome = blocked and "blocked" or (ok and "sent" or "failed")
  local entry = stats[item.chatType] or { sent = 0, blocked = 0, failed = 0 }
  stats[item.chatType] = entry
  entry[item.outcome] = entry[item.outcome] + 1
  if blocked then
    lastBlocked = env.clock()
  elseif ok then
    lastOk = env.clock()
  end
  attempts[#attempts + 1] = item
  while #attempts > Send.MAX_ATTEMPTS do
    table.remove(attempts, 1)
  end
  current = nil
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
  local target = SL.Target(conv)
  return SL.Available(conv, Send.Env.facts(target and target.kind))
end

----------------------------------------------------------------------------------------------------
-- Jobs
----------------------------------------------------------------------------------------------------

local LINE_STATE = { queued = "queued", sending = "queued", waiting = "waiting", failed = "failed", sent = "sent" }

-- Unsent parts show the state of the job. job.note says more about a state: "echo" (a secure click ran, the own
-- line of the game is still missing) and "noecho" (sent, no own line came back).
local function paintLines(job)
  for i = job.index, #job.parts do
    local line = job.lines[i]
    if line then
      line.delivery, line.reason, line.detail = LINE_STATE[job.state], job.reason or job.note, job.detail
    end
  end
end

-- How a job went (or goes) out, for the report.
local function wayOf(job)
  if job.how == "click" then
    return "secure"
  elseif job.boxMode == "input" then
    return "input"
  elseif job.state == "waiting" and job.reason == "enter" then
    return "box"
  end
  return "direct"
end

-- Keeps the state of a job in the list of the last sends (no text, no name).
local function trace(job)
  local entry = job.trail
  if not entry then
    entry = { stamp = Send.Env.stamp(), chatType = job.chatType }
    job.trail = entry
    trail[#trail + 1] = entry
    while #trail > Send.MAX_TRAIL do
      table.remove(trail, 1)
    end
  end
  entry.way, entry.state = wayOf(job), job.state
  entry.reason = job.reason or job.note
  entry.fn = job.detail and job.detail.fn or nil
end

-- The last sends as report lines, newest first.
function Send.TraceLines()
  local out = {}
  for i = #trail, 1, -1 do
    out[#out + 1] = SL.TraceLine(trail[i])
  end
  if #out == 0 then
    out[1] = "send: Forever Chat sent nothing yet"
  end
  return out
end

-- The way a message takes now, as the first line of the report.
function Send.PathLine()
  local env = Send.Env
  local ready, why = env.secure()
  local forbidden = WL.Lookup(env.memory(), env.build(), WL.ANY_KEY, "secure") == "blocked"
  return SL.PathLine({ ready = ready == true, why = why, forbidden = forbidden })
end

local function changed(job)
  trace(job)
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
      reply = i == 1 and job.reply or nil,
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
local function park(job, to, reason, detail)
  removeFromPipeline(job)
  SL.Move(job, to, reason)
  job.detail = detail
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

-- A job of the chat box that still waits for Enter, nil when there is none (the box holds one text).
local function enterJob(except)
  for _, job in ipairs(Queue.List()) do
    if job ~= except and job.state == "waiting" and job.reason == "enter" then
      return job
    end
  end
end

-- Puts the next part into the chat box of the game and parks the job until the player presses Enter there. The
-- job fails with a reason that names the way on when the box is taken or cannot open.
local function toChatBox(job, detail)
  local other = enterJob(job)
  if other and other.boxMode == "input" and job.boxMode == "input" then
    -- The player chose the game box for every message: a newer text takes the place of the older one in the box.
    Queue.Discard(other.id)
    other = nil
  end
  if other then
    return park(job, "failed", "enterpending")
  end
  local box = SL.BoxLine(job.chatType, job.target, job.parts[job.index])
  if box and Send.Env.openChat(box) then
    return park(job, "waiting", "enter", detail)
  end
  park(job, "failed", "blocked", detail)
end

-- What the game said about a refused call, for the tooltip: { key, arg, fn } with the locale key of the line.
local function blockDetail(fn)
  if fn then
    return { key = "chat.detail.blocked", arg = fn, fn = fn }
  end
  return { key = "chat.detail.blockedany" }
end

-- The detail of a failed call: the game's refusal names the function, a raised error its shortened text.
local function failDetail(reason, ret)
  if reason == "blocked" then
    return blockDetail(blockFn)
  elseif reason == "error" then
    local text = SL.ErrorBrief(ret)
    return text and { key = "chat.detail.error", arg = text } or nil
  end
end

-- A guild message went out without a refusal: its own line should come back. When it does not within ECHO_WAIT seconds
-- the message stays "sent" and says it is unconfirmed (the game may have dropped it, or the line is late).
local function watchEcho(job)
  local env = Send.Env
  if not (SL.ECHO_TYPES[job.chatType] and env.echoExpected()) then
    return
  end
  local entry = { job = job, text = job.parts[#job.parts] }
  watching[#watching + 1] = entry
  local token = generation
  env.after(
    WL.ECHO_WAIT,
    env.wrap(function()
      if token ~= generation then
        return
      end
      for i, item in ipairs(watching) do
        if item == entry then
          table.remove(watching, i)
          if job.state == "sent" and not job.note then
            job.note, job.detail = "noecho", { key = "chat.detail.noecho", arg = WL.ECHO_WAIT }
            for _, line in ipairs(job.lines) do
              if line then
                line.delivery, line.reason, line.detail = "sent", "noecho", job.detail
              end
            end
            trace(job)
            env.emit("FG_CHAT_SEND_STATE", job.conv.key, job)
          end
          return
        end
      end
    end)
  )
end

local function sendPart(job)
  local env = Send.Env
  if job.state == "queued" then
    SL.Move(job, "sending")
  end
  -- The call of the game comes first: the lines and the window follow once it returned.
  local part = job.parts[job.index]
  local item = diagBegin(job, part)
  inFlight, hit, blockFn = true, false, nil
  local ok, ret = pcall(env.send, part, job.chatType, job.target)
  local blocked = hit
  inFlight, hit = false, false
  local retry
  if blocked and type(env.canRetry) == "function" and env.canRetry() then
    -- The other chat function of the game takes the same message once (nothing went out, the first call was refused).
    inFlight, hit, blockFn = true, false, nil
    local okAlt, retAlt = pcall(env.send, part, job.chatType, job.target, true)
    local blockedAlt = hit
    inFlight, hit = false, false
    retry = blockedAlt and "blocked" or "ok"
    if not blockedAlt then
      ok, ret, blocked = okAlt, retAlt, false
    end
  end
  diagEnd(item, ok, blocked, retry)
  local state, reason = SL.Outcome(ok, ret, blocked)
  if reason == "blocked" then
    -- This message only: the text goes into the chat box, the next message tries the direct call again.
    return toChatBox(job, failDetail(reason))
  end
  if state == "failed" then
    park(job, "failed", reason, failDetail(reason, ret))
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
    watchEcho(job)
  elseif job.gated then
    park(job, "waiting", "click")
  else
    changed(job)
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

-- Starts a job: its first part (the only one of a short message) is sent right here, in the handler of the Enter key or
-- the click that asked for it, with no timer and no queue in front. Only the following parts of a long message wait
-- for the pause timer. A call of the game from a timer or an event may be refused where the call from the key is not.
local function startJob(job)
  pipeline[#pipeline + 1] = job
  sendPart(job)
  if pipeline[1] and not timerPending then
    later()
  end
end

-- Checks a text for a conversation and cuts it: { conv = { key, kind, name }, chatType, to, parts, restricted } or
-- nil and a refusal reason: the ones of SendLogic.Split, Route and Available and "queuefull". Nothing is sent or
-- kept.
-- The text with the chat name of the player in front when the chat name wants one here (ChatName.Decorate decides:
-- switched on, this chat type on, not paused, no command, never twice, never for whisper, say and yell). The text
-- unchanged otherwise. The input line asks for it too (quiet: no entry in the trace of the chat name), so its counter
-- counts what goes out.
function Send.Decorate(conv, text, quiet)
  local env = Send.Env
  if type(text) ~= "string" or type(env.prefix) ~= "function" then
    return text
  end
  local chatType, to = SL.Route(conv, env.channel)
  if not chatType then
    return text
  end
  local channel
  if chatType == "CHANNEL" then
    channel = env.channelName(to) or (type(conv) == "table" and conv.name) or nil
  end
  local ok, out = pcall(env.prefix, text, chatType, channel, quiet)
  return ok and type(out) == "string" and out or text
end

local function prepare(conv, text, quiet)
  local target = SL.Target(conv)
  if not target then
    return nil, "conversation"
  end
  local parts, why = SL.Split(text, (SL.Limit(target.kind)))
  if not parts then
    return nil, why
  end
  local env = Send.Env
  local available, reason = SL.Available(conv, env.facts(target.kind))
  if not available then
    return nil, reason
  end
  local chatType, to = SL.Route(conv, env.channel)
  if not chatType then
    return nil, to
  end
  -- The chat name goes in front of the whole text before it is cut: it counts into the limit of the first part and
  -- no later part carries it.
  local decorated = Send.Decorate(conv, text, quiet)
  if decorated ~= text then
    parts, why = SL.Split(decorated, (SL.Limit(target.kind)))
    if not parts then
      return nil, why
    end
  end
  local restricted = Send.Restricted()
  if restricted and not Queue.CanAdd() then
    return nil, "queuefull"
  end
  local key = type(conv) == "table" and conv.key or conv
  return {
    conv = { key = key, kind = target.kind, name = target.name },
    chatType = chatType,
    to = to,
    parts = parts,
    restricted = restricted == true,
  }
end

local function newJob(plan)
  nextId = nextId + 1
  local job = SL.NewJob(nextId, plan.conv, plan.chatType, plan.to, plan.parts, Send.Env.time())
  job.gated = isGated(job)
  return job
end

-- Sends a text to a conversation (a table with key, kind, name, or a key) through the chat function of the game
-- (every time, whatever an earlier message met) and puts the text into the chat box when the game refuses it. The
-- secure button has its own entry (Plan, Committed).
-- Returns the job (state queued, sending, sent or waiting, read it through job.state and the events) or nil and a
-- refusal reason: the ones of SendLogic.Split, Route and Available, "queuefull" or "enterpending". Nothing has been
-- sent or kept then. Call it from an explicit action of the player only. trigger ("enter" or "click") only labels the
-- diagnosis of a refused call.
local function sendText(conv, text, trigger, opts)
  local plan, why = prepare(conv, text)
  if not plan then
    return nil, why
  end
  local job = newJob(plan)
  job.trigger = trigger
  job.reply = type(opts) == "table" and opts.reply or nil
  if plan.restricted then
    addLines(job)
    park(job, "waiting", "restricted")
    return job
  end
  if #plan.parts >= 1 and Send.Env.gameInput() and SL.BoxLine(plan.chatType, plan.to, plan.parts[1]) then
    -- The game input box: the text goes into the chat box of the game and the game sends it on the Enter of the
    -- player. This code makes no call to the chat function.
    addLines(job)
    job.boxMode = "input"
    toChatBox(job)
    return job
  end
  -- The call of the game is the first thing that happens; the own lines are made behind it and show what it did.
  startJob(job)
  addLines(job)
  for i = 1, math.min(job.index - 1, #job.parts) do
    if job.lines[i] then
      job.lines[i].delivery, job.lines[i].reason = "sent", nil
    end
  end
  -- The state was announced when the call returned; the window learns of the new lines now (FG_CHAT_SENT came once).
  paintLines(job)
  Send.Env.emit("FG_CHAT_SEND_STATE", job.conv.key, job)
  return job
end

Send.Send = sendText

----------------------------------------------------------------------------------------------------
-- Secure button
----------------------------------------------------------------------------------------------------

-- What the secure button would do for this text: the plan of prepare plus macro (the text of the macro attribute, nil
-- when the part cannot go through a macro), key (the memory key), secure (whether the button may be offered,
-- WayLogic.CanOffer) and why (the reason it may not). nil and a reason when the text is refused. Nothing is sent.
-- The secure button asks for the plan before every click and arms itself with plan.macro only when plan.secure is
-- true. held: the held job of the same message.
function Send.Plan(conv, text)
  local plan, why = prepare(conv, text, true)
  if not plan then
    return nil, why
  end
  local env = Send.Env
  local ready, notReady = env.secure()
  plan.macro = #plan.parts == 1 and WL.Macro(plan.chatType, plan.to, plan.parts[1]) or nil
  plan.key = WL.Key(plan.chatType, plan.to)
  plan.secure, plan.why = WL.CanOffer({
    key = plan.key,
    memory = env.memory(),
    build = env.build(),
    secureReady = ready == true,
    secureWhy = notReady,
    parts = #plan.parts,
    macro = plan.macro ~= nil,
    restricted = plan.restricted,
  })
  return plan
end

-- The secure click starts: a refusal that the game reports from now until EndSecure belongs to it.
function Send.BeginSecure()
  inFlight, hit, blockFn = true, false, nil
end

-- The secure click is over. Returns whether the game reported a refusal meanwhile.
function Send.EndSecure()
  local blocked = hit
  inFlight, hit = false, false
  return blocked
end

local function removeVerifying(job)
  for i, item in ipairs(verifying) do
    if item == job then
      table.remove(verifying, i)
      return
    end
  end
end

-- The game refused the secure send. The way is remembered as blocked and the text goes into the chat box.
local function secureBlocked(job, fromEvent)
  removeVerifying(job)
  job.verify, job.note = nil, nil
  recordSecureRefusal(job, blockFn)
  if fromEvent then
    job.index = 1
    return park(job, "failed", "blocked", blockDetail(blockFn))
  end
  toChatBox(job, blockDetail(blockFn))
end

-- Nothing refused the send and no own line came back in time: it counts as sent, with the note.
local function secureNoEcho(job, token)
  if token ~= generation or not job.verify then
    return
  end
  removeVerifying(job)
  job.verify, job.note = nil, "noecho"
  SL.Move(job, "sent")
  job.detail = { key = "chat.detail.noecho", arg = WL.ECHO_WAIT }
  local line = job.lines[1]
  if line then
    line.delivery, line.reason, line.detail = "sent", "noecho", job.detail
  end
  recent[#recent + 1] = { job = job, at = Send.Env.time() }
  while #recent > 10 do
    table.remove(recent, 1)
  end
  changed(job)
end

-- The secure click ran (the macro line went to the game). plan: what Plan returned before the click, blocked: what
-- EndSecure said, held: a held job of the same message that this click continues (its line stays, no second one is
-- made). Makes the job and its line; the job waits
-- for the own line of the game. A refusal sends the text to the chat box at once. Returns the job.
function Send.Committed(plan, blocked, held)
  local env = Send.Env
  local job
  if held and (held.state == "waiting" or held.state == "failed") and #held.parts == 1 then
    Queue.Take(held.id)
    SL.Move(held, "queued", nil, true)
    held.chatType, held.target, held.index, held.how = plan.chatType, plan.to, 1, "click"
    job = held
  else
    job = newJob(plan)
    job.how, job.gated = "click", false
    addLines(job)
  end
  SL.Move(job, "sending")
  if blocked then
    secureBlocked(job)
    return job
  end
  job.verify, job.note = { at = env.time() }, "echo"
  verifying[#verifying + 1] = job
  changed(job)
  local token = generation
  env.after(
    WL.ECHO_WAIT,
    env.wrap(function()
      secureNoEcho(job, token)
    end)
  )
  return job
end

-- The held job of an own line (a message that waits for Enter or failed), nil when there is none.
function Send.HeldJobOf(line)
  if type(line) ~= "table" or not line.sendId then
    return nil
  end
  for _, job in ipairs(Queue.List()) do
    if job.id == line.sendId and #job.parts == 1 and job.lines[1] == line then
      return job
    end
  end
end

-- Sends the text of an own line again without the secure button (the click did not reach it: combat, no secure
-- button, another way is the choice). A held job of that line goes on (put in the chat box again or tried again),
-- anything else is sent as a new message. Returns the job, or nil and a reason. Call it from a click only.
function Send.Resend(conv, line)
  if type(line) ~= "table" or type(line.text) ~= "string" then
    return nil, "text"
  end
  local held = Send.HeldJobOf(line)
  if held then
    local heldAt = held.heldAt
    Queue.Take(held.id)
    local ok, why = Send.Resume(held)
    if not ok then
      Queue.Add(held)
      held.heldAt = heldAt
      return nil, why
    end
    return held
  end
  return sendText(conv, line.text, "click")
end

-- Sends a held job on a click (Queue.Release calls it): a waiting job goes on with its next part, a failed
-- one tries again from the part that failed. Returns true, or false and a reason.
function Send.Resume(job)
  if type(job) ~= "table" or (job.state ~= "waiting" and job.state ~= "failed") then
    return false, "state"
  end
  if job.state == "waiting" and job.reason == "enter" then
    -- The next part goes into the chat box again (the player closed it, or earlier parts went out). Still held.
    local box = SL.BoxLine(job.chatType, job.target, job.parts[job.index])
    if not (box and Send.Env.openChat(box)) then
      return false, "blocked"
    end
    Queue.Add(job)
    return true
  end
  if Send.Restricted() then
    return false, "restricted"
  end
  local available, why = Send.Available(job.conv)
  if not available then
    return false, why
  end
  job.gated, job.trigger = isGated(job), "click"
  local moved, reason = SL.Move(job, "queued", nil, true)
  if not moved then
    return false, reason
  end
  startJob(job)
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

-- The game reports a call of an add-on as refused (ADDON_ACTION_BLOCKED or ADDON_ACTION_FORBIDDEN, name of the
-- add-on first). The caller passes the event; nothing here listens. While a call of the sender or a secure click
-- runs the refusal belongs to it (see sendPart and EndSecure). A report that comes a moment later still turns the
-- send that just went out, or a secure send that waits for its own line, into a refused one: the way is remembered
-- as blocked and the text goes into the chat box. Returns whether a send was marked.
function Send.OnBlocked(who, fn)
  who = safe(who)
  if type(who) ~= "string" then
    return false
  end
  -- Only a refusal of this add-on counts (SendLogic.OwnBlock). Every other add-on sends chat too, and a
  -- refusal of theirs is no failure of this message.
  local mine = SL.OwnBlock(who, addonName, inFlight)
  if mine then
    fn = SL.Brief(safe(fn), 40)
    blockFn = fn or blockFn
  end
  if inFlight then
    hit = hit or mine
    return hit
  end
  if not mine then
    return false
  end
  local now = Send.Env.time()
  for i = #verifying, 1, -1 do
    local job = verifying[i]
    if job.verify and now - job.verify.at <= SL.BLOCK_WINDOW then
      secureBlocked(job, true)
      return true
    end
  end
  for i = #recent, 1, -1 do
    local job, at = recent[i].job, recent[i].at
    if job.state == "sent" and SL.LateBlock(who, addonName, at, now) then
      table.remove(recent, i)
      if job.how then
        recordSecureRefusal(job, blockFn)
      end
      job.index, job.note = 1, nil
      -- Evaluated only: an event handler touches no frame. The message shows "Not sent" and keeps its "Send now" and
      -- "Send again"; nothing is lost and the next message tries the chat function again.
      park(job, "failed", "blocked", blockDetail(blockFn))
      return true
    end
  end
  return false
end

-- A line of the own messages that the game echoed back. It confirms a secure send that waits for it, or the text
-- that waits in the chat box (the player pressed Enter there): the part counts as sent and the line the job
-- already made stands for it. Returns whether it matched; the caller then adds no second line.
function Send.OnOwnLine(key, text)
  text = safe(text)
  if type(text) ~= "string" then
    return false
  end
  noteEcho(key, text)
  for i, item in ipairs(watching) do
    if item.job.conv.key == key and item.text == text then
      table.remove(watching, i)
      break
    end
  end
  -- A late echo clears the note "unconfirmed".
  for _, entry in ipairs(recent) do
    local job = entry.job
    if job.note == "noecho" and job.conv.key == key and job.parts[#job.parts] == text then
      job.note, job.detail = nil, nil
      for _, line in ipairs(job.lines) do
        if line then
          line.reason, line.detail = nil, nil
        end
      end
      trace(job)
      Send.Env.emit("FG_CHAT_SEND_STATE", key, job)
      break
    end
  end
  for i, job in ipairs(verifying) do
    if job.conv.key == key and job.parts[1] == text then
      table.remove(verifying, i)
      job.verify, job.note = nil, nil
      SL.Move(job, "sent")
      Send.RecordWay(job.chatType, job.target, "secure", "ok")
      local line = job.lines[1]
      if line then
        line.delivery, line.reason, line.detail = "sent", nil, nil
      end
      recent[#recent + 1] = { job = job, at = Send.Env.time() }
      while #recent > 10 do
        table.remove(recent, 1)
      end
      changed(job)
      return true
    end
  end
  for _, job in ipairs(Queue.List()) do
    if SL.EchoMatches(job, key, text) then
      local line = job.lines[job.index]
      if line then
        line.delivery, line.reason, line.detail = "sent", nil, nil
      end
      job.index = job.index + 1
      if job.index > #job.parts then
        SL.Move(job, "sent")
        Queue.Discard(job.id)
      else
        changed(job)
      end
      return true
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

-- /fg diag chat of the main add-on lists the last sends.
FG.ChatSendTrace = function()
  local lines = Send.TraceLines()
  local ok, path = pcall(Send.PathLine)
  if ok then
    table.insert(lines, 1, path)
  end
  return lines
end

-- The error page of the main add-on asks for the context of a refused call of this add-on.
local catcher = FG.ErrorCatcher
if type(catcher) == "table" and type(catcher.AddContext) == "function" then
  catcher.AddContext(function(who)
    return Send.Diag(who)
  end)
end
