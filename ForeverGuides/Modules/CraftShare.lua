-- Crafting, sending side: announces the professions and known recipes of the logged-in character to the
-- guild and answers the questions "who can make recipe X" and "send me your recipes of profession Y".
-- Opt-in through ns.Consent ("crafting", audience guild, send and receive are separate), the line is
-- ns.Comm (function CR, payloads of GuildSyncCodec). Receiving, cache and display are other modules.
--   Data       only the character that is logged in (RecipeKnown.Own*), never another character of the
--              account. Professions and skill from Professions.Read, recipes of a profession are the known
--              ids inside RecipeUniverse. A profession without a known recipe (its window was never opened)
--              is not announced: an empty list would claim "knows nothing".
--   J          summary of the professions (skill, maximum, count, checksum) on the guild channel. Goes out
--              after login (15-75 s, random), 3-13 s after the consent is switched on, 60 s after the
--              known recipes changed and every 30 minutes (+-20 percent). Never in combat.
--   W          "who can make spell S", asked on the guild channel. Answered with K by whisper to the asker
--              only, after a random 0.3-3 s, only when this character knows the recipe, in no combat and
--              no instance, at most one per asker and 10 s, at most 20 per minute. Needs the send consent.
--   R          "send your set of profession P", a whisper. Answered with C (one or more blocks) by whisper,
--              only for professions announced in this session (the line checks that) and only to guild
--              members. A mask when both sides share the universe, an id list otherwise, nothing when the
--              asker's copy is current.
--   X          one goodbye on the guild channel after the send consent went off, and only when a J really
--              went out before (farewell of the line).
--   Registration happens with the first consent (send or receive, audience guild), not at load. Switching
--   the send consent off drops the waiting answers and timers.
-- For the receiving side (module that handles J, K, C and X):
--   CraftShare.Register()                 idempotent, also called by this module with the first consent
--   CraftShare.SetReceiver(typ, handler)  typ J, K, C or X; handler(sender, msg, ctx) with the decoded
--                                         message table. The line has already checked the receive consent;
--                                         for K and C the sender is NOT yet known to be a guild member
--                                         (whispers come from anybody), check it
--   CraftShare.Allow(typ, cost)           the send grid (GuildSyncLogic CONFIG.send.crafting): use it for the
--                                         own W (one per 10 s, 20 per hour) and R before Comm.Send
--   Send W with Comm.Send("crafting", "W", payload, "guild", nil, { id = nonce }) and R with
--   Comm.Send("crafting", "R", payload, "whisper", target, { id = nonce }): the envelope id must equal the
--   nonce, because K and C come back under it. Own W limit per hour and the 30 s nonce memory belong to
--   the receiving side.
local _, ns = ...
local Comm, Consent, PN, L, G = ns.Comm, ns.Consent, ns.PlayerName, ns.GuildSyncLogic, ns.GuildSyncCodec
local RecipeKnown, RecipeUniverse = ns.RecipeKnown, ns.RecipeUniverse

local CS = {}
ns.CraftShare = CS

CS.FN = "crafting"
-- Seconds: { lowest, highest } of the random wait before the first J, and the fixed wait after a change.
CS.DELAY = { login = { 15, 75 }, consent = { 3, 13 }, change = 60 }
-- Seconds between two J without a change, the spread around it, and the wait after a lock or a refusal.
CS.REFRESH = 1800
CS.JITTER = 0.2
CS.RETRY = 20
-- Wait before a K (seconds), the most answers waiting at the same time, and the seconds between two blocks
-- of one C. One asker gets at most one answer per 10 s: the intake gate allows one W per sender in that time.
CS.ANSWER_DELAY = { 0.3, 3 }
CS.MAX_WAITING = 20
CS.BLOCK_GAP = 1.1
-- Replaceable in tests: random number from 0 to 1.
function CS.random()
  return math.random()
end

local TYPES = { J = true, K = true, C = true, X = true }

local function clock()
  return Comm.clock()
end

local grid = assert(L.NewSendGrid(clock, CS.FN))
local intake = assert(L.NewIntake(clock))

-- registered: the line knows the function. announced: a J went out and no goodbye since.
local registered, announced = false, false
-- Timer state: one pending announcement { at, gen }; answers waiting for their delay.
local pending, gen, depth = nil, 0, 0
local waiting, answerGen = 0, 0
local receivers = {}

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

local function inGuild()
  return try(g("IsInGuild")) == true
end

-- True while sending is possible at all: consent and a guild.
function CS.Active()
  return Consent.Allows(CS.FN, "send", "guild") and inGuild()
end

-- Why nothing is answered or announced right now: "combat" or "instance" (whispers are throttled there).
local function pauseReason()
  local guard = ns.AutoGuard
  if (guard and guard.Blocked()) or ns.InCombat() then
    return "combat"
  end
  if try(g("IsInInstance")) == true then
    return "instance"
  end
end

-- Own data ------------------------------------------------------------------------------------------------

local function whole(v, hi)
  v = tonumber(v)
  if not v or v ~= v then
    return 0
  end
  return math.max(0, math.min(hi, math.floor(v)))
end

-- The professions of the logged-in character that can be announced: { slug, id, skill, max, universe, ids }
-- in list order, at most MAX_JOBS, only those with a universe and at least one known recipe.
local function ownJobs()
  local out = {}
  local list = ns.Professions and ns.Professions.Read()
  for _, p in ipairs(ns.ProfessionRouteLogic.OwnRoutes(list)) do
    local universe = RecipeUniverse.Get(p.slug)
    if universe and #out < G.LIMITS.MAX_JOBS then
      local ids = RecipeKnown.OwnJobIds(p.slug)
      if #ids > 0 then
        out[#out + 1] = {
          slug = p.slug,
          id = RecipeUniverse.JobId(p.slug),
          skill = whole(p.skill, G.LIMITS.MAX_SKILL),
          max = whole(p.max, G.LIMITS.MAX_SKILL),
          universe = universe,
          ids = ids,
        }
      end
    end
  end
  return out
end

local function jobOfSlug(jobs, slug)
  for _, job in ipairs(jobs) do
    if job.slug == slug then
      return job
    end
  end
end

-- The guild roster is the only source of believed senders.
local function trusted(sender)
  local inv = ns.Invites
  return inv ~= nil and inv.IsGuildMember(sender, nil) == true
end

-- Announcing (J) -------------------------------------------------------------------------------------------

-- The payload of J for the logged-in character and its jobs, nil when there is nothing to say.
function CS.Summary()
  local jobs = ownJobs()
  local entries = {}
  for i, job in ipairs(jobs) do
    local _, n, h = G.EncodeMask(job.universe, job.ids)
    entries[i] = { id = job.id, skill = job.skill, max = job.max, n = n, h = h }
  end
  if #entries == 0 then
    return nil
  end
  return G.Encode(CS.FN, { typ = "J", jobs = entries }), jobs
end

-- Sends J now. Returns true, or false and why: inactive, combat, instance, empty, throttle, or the reason of
-- the line.
function CS.Announce()
  if not CS.Active() then
    return false, "inactive"
  end
  if pauseReason() == "combat" then
    return false, "combat"
  end
  local payload, jobs = CS.Summary()
  if not payload then
    return false, "empty"
  end
  if not grid.Allow("J") then
    return false, "throttle"
  end
  local ok, why = Comm.Send(CS.FN, "J", payload, "guild", nil, { priority = "background" })
  if ok then
    announced = true
    -- R is served for these professions, this session, nothing else.
    for _, job in ipairs(jobs) do
      Comm.NoteShared(CS.FN, tostring(job.id))
    end
  end
  return ok, why
end

local function fire() end

-- One timer at a time: a later request keeps an earlier due time.
local function schedule(delay)
  local timer = g("C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  local at = clock() + delay
  if pending and pending.at <= at then
    return
  end
  gen = gen + 1
  local mine = gen
  pending = { at = at }
  local ok = pcall(timer.After, delay, function()
    if gen ~= mine then
      return
    end
    pending = nil
    -- A client that runs the timer at once must not loop.
    depth = depth + 1
    if depth <= 2 then
      ns.Safe("craftshare", fire)
    end
    depth = depth - 1
  end)
  if not ok then
    pending = nil
  end
end

local function spread(range)
  return range[1] + CS.random() * (range[2] - range[1])
end

fire = function()
  if not CS.Active() then
    return
  end
  if pauseReason() == "combat" then
    return schedule(CS.RETRY)
  end
  local ok, why = CS.Announce()
  if ok or why == "empty" then
    schedule(L.Jitter(CS.REFRESH, CS.JITTER, CS.random))
  else
    schedule(CS.RETRY * 3)
  end
end

-- Starts the announcements (login, consent): the first J waits a random while.
local function start(kind)
  if CS.Active() then
    schedule(spread(CS.DELAY[kind]))
  end
end

-- Stops what waits: the timers and the answers that were not sent yet.
local function stop()
  gen, pending = gen + 1, nil
  answerGen, waiting = answerGen + 1, 0
  Comm.Purge(CS.FN)
end

-- One goodbye with reason w. Nothing goes out when no J went out. Returns true when it was queued.
function CS.Retract(reason)
  if not announced then
    return false, "quiet"
  end
  announced = false
  local payload = G.Encode(CS.FN, { typ = "X", reason = reason or "w" })
  if not payload then
    return false, "payload"
  end
  if not grid.Allow("X") then
    return false, "throttle"
  end
  return Comm.Send(CS.FN, "X", payload, "guild")
end

-- Answering (W, R) ---------------------------------------------------------------------------------------

-- Sends K now when the logged-in character still knows the spell. Returns true, or false and why.
function CS.AnswerAsk(sender, msg)
  if not CS.Active() then
    return false, "inactive"
  end
  if pauseReason() then
    return false, "paused"
  end
  if not RecipeKnown.OwnHas(msg.spell) then
    return false, "unknown"
  end
  local slug = RecipeUniverse.JobOf(msg.spell)
  local job = slug and jobOfSlug(ownJobs(), slug)
  if not job then
    return false, "job"
  end
  if not grid.Allow("K") then
    return false, "throttle"
  end
  local payload =
    G.Encode(CS.FN, { typ = "K", nonce = msg.nonce, spell = msg.spell, job = job.id, skill = job.skill, max = job.max })
  if not payload then
    return false, "payload"
  end
  return Comm.Send(CS.FN, "K", payload, "whisper", sender, { priority = "reply", id = msg.nonce })
end

local function onAsk(sender, msg)
  if type(msg) ~= "table" or msg.typ ~= "W" or not CS.Active() or not trusted(sender) or pauseReason() then
    return
  end
  local key = PN.Key(sender)
  -- A recipe this character does not know costs one table lookup and nothing else.
  if not intake.Allow("W", key) or not RecipeKnown.OwnHas(msg.spell) then
    return
  end
  local timer = g("C_Timer")
  if waiting >= CS.MAX_WAITING or type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  waiting = waiting + 1
  local mine = answerGen
  local ok = pcall(timer.After, spread(CS.ANSWER_DELAY), function()
    if mine ~= answerGen then
      return
    end
    waiting = math.max(0, waiting - 1)
    ns.Safe("craftshare", function()
      CS.AnswerAsk(sender, msg)
    end)
  end)
  if not ok then
    waiting = math.max(0, waiting - 1)
  end
end

-- C for an R: one block with the mask, or several with an id list. Returns true, or false and why.
function CS.AnswerFetch(sender, msg)
  if not CS.Active() then
    return false, "inactive"
  end
  if pauseReason() then
    return false, "paused"
  end
  local slug = RecipeUniverse.SlugOfJob(msg.job)
  local job = slug and jobOfSlug(ownJobs(), slug)
  if not job then
    return false, "job"
  end
  local plan = L.PlanAnswer(job.universe, job.ids, { u = msg.u, h = msg.h })
  if not plan then
    return false, "plan"
  end
  local payload = G.Encode(CS.FN, {
    typ = "C",
    nonce = msg.nonce,
    job = job.id,
    art = plan.art,
    u = plan.u,
    n = plan.n,
    h = plan.h,
    data = plan.data,
  })
  if not payload then
    return false, "payload"
  end
  local blocks = math.max(1, math.ceil(#payload / ns.CommLogic.LIMITS.MAX_PAYLOAD))
  if not grid.Allow("C", blocks) then
    return false, "throttle"
  end
  return Comm.Send(CS.FN, "C", payload, "whisper", sender, { priority = "reply", id = msg.nonce, gap = CS.BLOCK_GAP })
end

local function onFetch(sender, msg)
  if type(msg) ~= "table" or msg.typ ~= "R" or not CS.Active() or not trusted(sender) or pauseReason() then
    return
  end
  if intake.Allow("R", PN.Key(sender)) then
    CS.AnswerFetch(sender, msg)
  end
end

-- Registration -------------------------------------------------------------------------------------------

local function dispatch(typ)
  return function(sender, msg, ctx)
    local handler = receivers[typ]
    if handler then
      handler(sender, msg, ctx)
    end
  end
end

-- The receiving module hands in its handler for J, K, C or X. nil takes it out again.
function CS.SetReceiver(typ, handler)
  if not TYPES[typ] or (handler ~= nil and type(handler) ~= "function") then
    return false
  end
  receivers[typ] = handler
  return true
end

function CS.Allow(typ, cost)
  return grid.Allow(typ, cost)
end

-- The line needs one registration for all types: the handlers of W and R are here, the others go to the
-- receiver.
function CS.Register()
  if not registered then
    registered = Comm.Register(CS.FN, {
      version = 1,
      audiences = { "guild", "whisper" },
      whisperAud = "guild",
      on = { J = dispatch("J"), W = onAsk, K = dispatch("K"), R = onFetch, C = dispatch("C"), X = dispatch("X") },
      decode = function(payload, typ)
        return G.Decode(CS.FN, typ, payload)
      end,
      farewell = "X",
      request = "R",
      ask = "W",
      -- R is answered for a profession announced in this session (Comm.NoteShared in Announce).
      service = function(msg)
        return tostring(msg.job)
      end,
    }) == true
  end
  return registered
end

function CS.Registered()
  return registered
end

function CS.Status()
  return {
    active = CS.Active(),
    registered = registered,
    announced = announced,
    waiting = waiting,
    due = pending and pending.at,
  }
end

-- Events ----------------------------------------------------------------------------------------------

local function consented()
  return Consent.Allows(CS.FN, "send", "guild") or Consent.Allows(CS.FN, "receive", "guild")
end

ns.On("PLAYER_LOGIN", function()
  if consented() then
    CS.Register()
  end
  start("login")
end)
ns.On("PLAYER_ENTERING_WORLD", function()
  if not inGuild() then
    stop()
  elseif not pending and not announced then
    start("login")
  end
end)
-- Leaving the guild: there is nobody left to tell.
ns.On("PLAYER_GUILD_UPDATE", function()
  if not inGuild() then
    announced = false
    stop()
  end
end)
ns.On("FG_RECIPES_CHANGED", function()
  if CS.Active() then
    schedule(CS.DELAY.change)
  end
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if fn ~= CS.FN or aud ~= "guild" then
    return
  end
  if value == true then
    CS.Register()
    if dir == "send" then
      start("consent")
    end
  elseif dir == "send" then
    -- The consent is already false here: the goodbye goes out as a farewell of the line.
    CS.Retract("w")
    stop()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == CS.FN then
    CS.Retract("w")
    stop()
  end
end)

if Consent.MarkAvailable then
  Consent.MarkAvailable(CS.FN)
end
