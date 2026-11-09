-- Rules of the "who is there?" probe, no game calls and no access to saved data: when a probe may go out, how
-- an answer is spread and capped, the backoff after a refusal and the reason why a sharing function stands still.
-- Clock and random source are passed in; every number is in CONFIG.
--   Probe    sent by a player who receives a function (switch, login, guild join, wake up), at most once per
--            function and ASK_GAP seconds. It carries no data.
--   Answer   given by a player who sends the function: after a random wait that grows with the number of
--            members online, at most once per function and ANSWER_GAP seconds, dropped when CAP other
--            messages of the function came in since the probe (somebody else already answered the guild).
local _, ns = ...

local SL = {}
ns.ShareSyncLogic = SL

SL.CONFIG = {
  -- Seconds between two own probes of one function, and between two answers of one function.
  askGap = 60,
  answerGap = 60,
  -- Wait before a probe by cause, { lowest, highest } seconds. A switch asks at once (a short wait lets a bulk
  -- switch of many functions finish), a login waits for the roster and the crowd of other logins.
  askDelay = { switch = { 0.2, 0.8 }, login = { 4, 10 }, join = { 2, 5 }, wake = { 3, 9 }, load = { 5, 12 } },
  -- Seconds between the probes of two functions.
  askSlot = 0.5,
  -- Seconds before the next try after a refusal or a silent guild; the last value repeats. At most maxTries
  -- tries per cause.
  backoff = { 5, 10, 20, 40, 60 },
  maxTries = 4,
  -- Seconds after a probe in which an answer must have come in, else one more try (silent guild).
  verify = 30,
  -- Answer: spread = base + online * perOnline seconds (at most max), the wait starts at `min`; the answer is owed
  -- for `hold` seconds when the function is paused (combat), a retry every `retry` seconds; cap: messages of the
  -- function heard since the probe after which the own answer is dropped.
  answer = { min = 0.5, base = 2, perOnline = 0.1, max = 20, hold = 90, retry = 5, cap = 40 },
  -- Seconds between two looks at the guild while it is unknown after login (the last value repeats until the list
  -- ends), and the seconds after login in which a guild that shows up late still counts as the login.
  guildPoll = { 2, 5, 10, 20, 40, 60, 60, 60 },
  loginWindow = 300,
  -- Wake up: a timer that runs every `tick` seconds and finds `jump` seconds passed means the client stood still.
  wake = { tick = 20, jump = 90 },
  -- A loading screen asks again only when the last probe is older than this.
  reload = 900,
  -- A reason that sticks for this long after the game refused a message.
  errorAge = 120,
}
local C = SL.CONFIG

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function now(clock)
  local ok, t = pcall(clock)
  return ok and finite(t) and t or 0
end

local function unit(random)
  local ok, r = pcall(random or math.random)
  r = ok and tonumber(r) or 0.5
  if not finite(r) then
    r = 0.5
  end
  return clamp(r, 0, 1)
end

-- A value of the range { lo, hi } drawn with random() (0 to 1).
function SL.Between(range, random)
  return range[1] + unit(random) * (range[2] - range[1])
end

-- Seconds before a probe for a cause (switch, login, join, wake, load); unknown causes wait like a login.
function SL.AskDelay(cause, random)
  return SL.Between(C.askDelay[cause] or C.askDelay.login, random)
end

-- Seconds to wait after the nth refusal (1 based), nil when the tries are used up.
function SL.Backoff(tries)
  if not finite(tries) or tries < 1 or tries > C.maxTries then
    return nil
  end
  return C.backoff[math.min(tries, #C.backoff)]
end

-- The spread of the answers for `online` members online, in seconds.
function SL.AnswerSpread(online)
  local a = C.answer
  if not finite(online) or online < 0 then
    online = 0
  end
  return clamp(a.base + online * a.perOnline, a.base, a.max)
end

-- Wait before an answer: from `min` up to the spread.
function SL.AnswerDelay(online, random)
  local a = C.answer
  return SL.Between({ a.min, math.max(a.min, SL.AnswerSpread(online)) }, random)
end

-- Seconds between two looks at the guild after login: the nth look (1 based).
function SL.GuildPoll(n)
  if not finite(n) or n < 1 or n > #C.guildPoll then
    return nil
  end
  return C.guildPoll[n]
end

-- Asker -----------------------------------------------------------------------------------------------

-- Plan of the own probes. Want(fn, cause) says a probe is wanted; Take(fn) is asked when the timer ran out.
function SL.NewAsker(clock, random)
  local state = {}
  local A = {}

  local function entry(fn)
    local e = state[fn]
    if not e then
      e = { tries = 0 }
      state[fn] = e
    end
    return e
  end

  -- Wants a probe: it goes out after the wait of the cause, never closer than askGap to the last one and never
  -- closer than askSlot to the probe of another function. Returns the seconds to wait (the earlier due time wins).
  function A.Want(fn, cause, delay)
    local t, e = now(clock), entry(fn)
    local due = t + (delay or SL.AskDelay(cause, random))
    if e.lastAt then
      due = math.max(due, e.lastAt + C.askGap)
    end
    if e.due and e.due <= due then
      return e.due - t
    end
    -- Keep the probes of other functions askSlot seconds away.
    for _ = 1, 50 do
      local moved = false
      for other, o in pairs(state) do
        if other ~= fn and o.due and math.abs(o.due - due) < C.askSlot then
          due, moved = o.due + C.askSlot, true
        end
      end
      if not moved then
        break
      end
    end
    e.due, e.cause = due, cause
    return due - t
  end

  -- "go" when the probe is due, else "wait" and the seconds left, or "none" when nothing is wanted.
  function A.Take(fn)
    local e = state[fn]
    if not e or not e.due then
      return "none"
    end
    local left = e.due - now(clock)
    if left > 0.001 then
      return "wait", left
    end
    return "go"
  end

  -- The probe went out: the gap starts. The tries stay, so a guild that stays silent is not asked forever.
  function A.Sent(fn)
    local e = entry(fn)
    e.lastAt, e.due, e.sentCount = now(clock), nil, (e.sentCount or 0) + 1
  end

  -- A new cause (switch, login, join, wake up) or an answer: the tries start over.
  function A.Reset(fn)
    entry(fn).tries = 0
  end

  -- The probe could not go out or nobody answered: the next try after the backoff, nil when used up.
  function A.Failed(fn, cause)
    local e = entry(fn)
    e.tries = e.tries + 1
    local wait = SL.Backoff(e.tries)
    if not wait then
      e.due = nil
      return nil
    end
    return A.Want(fn, cause or e.cause or "login", wait)
  end

  function A.Cancel(fn)
    local e = state[fn]
    if e then
      e.due, e.tries = nil, 0
    end
  end

  -- Forgets the last probe (the player left the guild): the next one may go at once.
  function A.Forget(fn)
    state[fn] = nil
  end

  function A.LastAt(fn)
    return state[fn] and state[fn].lastAt or nil
  end

  function A.Tries(fn)
    return state[fn] and state[fn].tries or 0
  end

  function A.Pending(fn)
    return state[fn] ~= nil and state[fn].due ~= nil
  end

  function A.Count(fn)
    return state[fn] and state[fn].sentCount or 0
  end

  return A
end

-- Responder -------------------------------------------------------------------------------------------

-- Plan of the own answers. Heard(fn, online, packets) says a probe came in; Check(fn, packets) is asked when the
-- timer ran out. packets is the number of messages of the function that arrived so far (any sender).
function SL.NewResponder(clock, random)
  local state = {}
  local R = {}

  local function entry(fn)
    local e = state[fn]
    if not e then
      e = {}
      state[fn] = e
    end
    return e
  end

  -- A probe came in. Returns the seconds until the answer is due, and true when a probe was already waiting
  -- (one answer serves every asker of the same moment).
  function R.Heard(fn, online, packets)
    local t, e = now(clock), entry(fn)
    if e.due then
      e.merged = (e.merged or 0) + 1
      return math.max(0, e.due - t), true
    end
    local due = t + SL.AnswerDelay(online, random)
    if e.answeredAt then
      due = math.max(due, e.answeredAt + C.answerGap)
    end
    e.due, e.expires, e.base = due, t + C.answer.hold + math.max(0, due - t), tonumber(packets) or 0
    return due - t, false
  end

  -- "go", "wait" (and the seconds left), "enough" (others answered already), "expired" or "none".
  function R.Check(fn, packets)
    local e = state[fn]
    if not e or not e.due then
      return "none"
    end
    local t = now(clock)
    if t > e.expires then
      e.due = nil
      return "expired"
    end
    if (tonumber(packets) or 0) - e.base >= C.answer.cap then
      e.due = nil
      return "enough"
    end
    if t + 0.001 < e.due then
      return "wait", e.due - t
    end
    return "go"
  end

  -- The answer went out.
  function R.Answered(fn)
    local e = entry(fn)
    e.answeredAt, e.due = now(clock), nil
  end

  -- The function could not answer yet (paused): look again after the retry wait, until the hold runs out.
  function R.Retry(fn)
    local e = state[fn]
    if not e or not e.due then
      return nil
    end
    e.due = now(clock) + C.answer.retry
    return C.answer.retry
  end

  function R.Drop(fn)
    local e = state[fn]
    if e then
      e.due = nil
    end
  end

  function R.AnsweredAt(fn)
    return state[fn] and state[fn].answeredAt or nil
  end

  function R.Pending(fn)
    return state[fn] ~= nil and state[fn].due ~= nil
  end

  return R
end

-- Reason ----------------------------------------------------------------------------------------------

-- The reason why nothing can happen for a function, as a key (texts: share.why.<key>), or nil when all is well.
-- f: send, receive (booleans for the guild), trial, inGuild, roster (list loaded), registered, pause ("combat",
-- "instance", "afk", "restricted", "hidden", "empty"), error ({ name, ago }), heard (players), askAgo, silentAfter.
function SL.Reason(f)
  if f.trial then
    return "trial"
  end
  if not f.send and not f.receive then
    return "off"
  end
  if not f.inGuild then
    return "noguild"
  end
  if not f.registered then
    return "unregistered"
  end
  if f.receive and not f.roster then
    return "roster"
  end
  if f.send and f.pause then
    return f.pause
  end
  local e = f.error
  if type(e) == "table" and finite(e.ago) and e.ago <= C.errorAge then
    local name = tostring(e.name)
    if name:find("Throttle") then
      return "throttle"
    elseif name:find("Lockdown") or name:find("Restrict") then
      return "restricted"
    end
    return "refused"
  end
  if f.receive and (f.heard or 0) == 0 and finite(f.askAgo) and f.askAgo >= (f.silentAfter or C.verify) then
    return "silent"
  end
  return nil
end
