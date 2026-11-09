-- Presence mark: who else uses this add-on and wants to be recognized, the base for the badge in chat
-- and on nameplates (those come in their own modules and only ask Presence.Has, Flags and Badge).
-- Everything is opt-in and runs through ns.Comm and ns.Consent, function "presenceMark" (code PM):
--   send     "I am recognizable" per audience (group, guild): the own mark goes out when joining a group,
--            when the group grows, after the guild login, when the number of guild members online rises
--            (a late player learns the others), when switched on, when the flags change and now and then
--            as a renewal, always seconds late and never in combat
--   receive  "show badges of others" per audience: marks are read into a register in memory
-- Receiving never answers: there is no hello and no request, whoever may send announces itself. The rise of
-- the online count is read from the game (GetNumGuildMembers), never from a mark that was heard. A mark
-- is believed only from the own group or guild (checked by Comm) and only with the receive consent of
-- the audience it came in on. Withdrawing the send consent sends one empty farewell, and only to the
-- audiences the mark was really delivered to; withdrawing the receive consent empties the register.
-- Stage 1 is group and guild. Stage 2 (hidden world channel, own consent) and stage 3 (say, after the
-- probe) add an entry to AUDIENCES with their channel and a consent audience of their own.
-- One message for the mark and the logos: while this function may send to an audience, the guild and community
-- logos of CrestMark ride in the same message (an optional tail, see PresenceLogic), as far as the send consent
-- of crestMark allows. CrestMark sends its own message (code CM) only to an audience this function may not
-- send to. On the way in, the tail goes to CrestMark, which reads it only with its own receive consent; this
-- function keeps its register whether or not the tail is read.
-- Event FG_PRESENCE_UPDATE (debounced) when the register changed.
local _, ns = ...
local PL, PN, Comm, Consent = ns.PresenceLogic, ns.PlayerName, ns.Comm, ns.Consent

local P = {}
ns.Presence = P

P.FN = "presenceMark"
-- Seconds until a locked (combat, restriction) message is tried again.
P.LOCKED_RETRY = 30
-- Replaceable in tests: random integer from lo to hi.
function P.random(lo, hi)
  return math.random(lo, hi)
end

local FN = P.FN
local RESTRICTIONS = { "Chat", "Combat", "Encounter", "ChallengeMode", "PvPMatch" }
local KIND_OF_CHANNEL = { PARTY = "group", RAID = "group", INSTANCE_CHAT = "group", GUILD = "guild" }

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

-- Audience (also the consent audience) -> the game channel to send to, nil when there is none.
local AUDIENCES = {
  group = {
    channel = function()
      return ns.PeerComm.GroupChannel()
    end,
  },
  guild = {
    channel = function()
      return try(g("IsInGuild")) == true and "GUILD" or nil
    end,
  },
}
local ORDER = { "group", "guild" }

local function clock()
  return Comm.clock()
end

local registry = PL.NewRegistry(clock)
local plan = PL.NewPlan(clock)
local due, pending, delivered = {}, {}, {}
-- audience -> true while the last mark sent there carried logos (a later mark without them says "none").
local carries = {}
local schedule
local members, depth, renewArmed = 0, 0, false
-- Counters of this session for the status report (no names): marks stored, farewells, and why a mark was refused.
local heardCount, farewells, refused = 0, 0, {}
-- Guild online trigger: roster events read, rises of the online count seen, messages planned because of one, and
-- the last count (nil until the first read). quietUntil: the roster of the own login is still loading.
local online = { events = 0, rises = 0, planned = 0, last = nil }
local quietUntil = nil
-- audience -> { why, at } of the last try to send, "sent" or the reason it did not go out.
local attempts = {}
-- False once the function left the line: nothing is planned or sent any more.
local active = false

local function notify()
  ns.Debounce("presence-update", 1, function()
    ns.Emit("FG_PRESENCE_UPDATE")
  end)
end

-- Combat and addon restrictions: nothing is planned to go out.
local function locked()
  local guard = ns.AutoGuard
  return (guard ~= nil and guard.Blocked()) or ns.InCombat() or ns.AddonRestricted(unpack(RESTRICTIONS))
end

local function chatOnly()
  local s = ns.db and ns.db.settings
  return s ~= nil and s.presenceChatOnly == true
end

-- Reading the register -----------------------------------------------------------------------------------

local function lookup(name)
  local key = type(name) == "string" and PN.Key(name) or ""
  if key == "" then
    return nil
  end
  local entry = registry.Get(key)
  -- The receive switch may have gone off since the entry was stored.
  if entry and Consent.Allows(FN, "receive", entry.src) then
    return entry
  end
  return nil
end

-- True when the player named `name` sent a mark that is still valid.
function P.Has(name)
  return lookup(name) ~= nil
end

-- { flags, chatOnly, src } of a recognized player (src: the audience the mark came in on), else nil.
function P.Flags(name)
  local entry = lookup(name)
  if not entry then
    return nil
  end
  return { flags = entry.flags, chatOnly = entry.flags >= PL.FLAG_CHAT_ONLY, src = entry.src }
end

function P.Count()
  return registry.Count()
end

-- True when this function sends the message of an audience, with the logos if they are allowed: it is on the line
-- and the send consent holds. CrestMark then sends nothing of its own there.
function P.Merges(kind)
  return active and AUDIENCES[kind] ~= nil and Consent.Allows(FN, "send", kind)
end

-- True while the last mark sent to an audience carried logos.
function P.Carries(kind)
  return carries[kind] == true
end

-- Asks for a mark to an audience (CrestMark calls it when its logos changed or were switched on or off).
function P.Schedule(kind, trigger, delay)
  schedule(kind, trigger, delay)
end

-- True while the logos of CrestMark ride in this function's messages.
function P.Merged()
  local crest = ns.CrestMark
  return active and crest ~= nil and type(crest.MergedBody) == "function"
end

-- What this session did, for the status report: { registered, sent, heard (marks stored), farewells,
-- refused (reason -> count), register = { total, group, guild }, last = audience -> { why, ago } }. Reads only
-- memory, asks nobody.
function P.Info()
  local now, last = clock(), {}
  for _, kind in ipairs(ORDER) do
    local at, attempt = plan.LastAt(kind), attempts[kind]
    last[kind] = {
      sentAgo = at and math.max(0, now - at) or nil,
      why = attempt and attempt.why or nil,
      tryAgo = attempt and math.max(0, now - attempt.at) or nil,
    }
  end
  local by = registry.CountBySource()
  local copy = {}
  for why, n in pairs(refused) do
    copy[why] = n
  end
  return {
    registered = active,
    sent = plan.Count(),
    heard = heardCount,
    farewells = farewells,
    refused = copy,
    register = { total = registry.Count(), group = by.group or 0, guild = by.guild or 0 },
    last = last,
    online = { events = online.events, rises = online.rises, planned = online.planned, last = online.last },
  }
end

-- Badge text of a recognized player ("" for everybody else and while the receive switch is off).
-- style: "icon" (default), "text" or "both"; size: pixel height.
function P.Badge(name, style, size)
  if not lookup(name) then
    return ""
  end
  return PL.Badge(name, style, size)
end

-- Sending ------------------------------------------------------------------------------------------------

-- The own mark to one audience. Returns true when it was queued, else false, the reason and for "wait"
-- the seconds left.
local function announce(kind, trigger)
  local function result(ok, why, left)
    attempts[kind] = { why = ok and "sent" or why, at = clock() }
    return ok, why, left
  end
  local def = AUDIENCES[kind]
  if not active then
    return result(false, "unregistered")
  end
  if not def or not Consent.Allows(FN, "send", kind) then
    return result(false, "consent")
  end
  if not def.channel() then
    return result(false, "no-channel")
  end
  local decision, left = plan.Check(kind, trigger, locked(), trigger == "online" and PL.OnlineGap(online.last) or nil)
  if decision ~= "send" then
    return result(false, decision, left)
  end
  -- The logos of CrestMark ride along when it may send them; a mark that stops carrying them says so once.
  local crest = ns.CrestMark
  local body = crest and type(crest.MergedBody) == "function" and crest.MergedBody(kind) or nil
  local tail = body or (carries[kind] and PL.NO_LOGOS or nil)
  if not Comm.Send(FN, "P", PL.Encode(chatOnly(), tail), kind, nil, { priority = "background" }) then
    return result(false, "refused")
  end
  carries[kind] = body ~= nil or nil
  plan.Sent(kind)
  return result(true)
end

local arm, armRenew

local function fire(kind)
  local trigger = due[kind]
  due[kind] = nil
  if not trigger then
    return
  end
  local moved = plan.Moved(kind)
  local ok, why, left = announce(kind, trigger)
  if ok then
    armRenew(PL.RenewIn(moved, P.random))
  elseif why == "wait" and left then
    due[kind] = trigger
    arm(kind, left + 1)
  elseif why == "combat" then
    due[kind] = trigger
    arm(kind, P.LOCKED_RETRY)
  end
end

-- One timer per audience; a trigger while it runs only keeps the more urgent cause (the smaller gap).
arm = function(kind, delay)
  if pending[kind] then
    return
  end
  local timer = g("C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  pending[kind] = true
  local ok = pcall(timer.After, delay, function()
    pending[kind] = nil
    -- A client that runs the timer at once must not loop on a "wait" answer.
    depth = depth + 1
    if depth <= 2 then
      ns.Safe("presence", fire, kind)
    end
    depth = depth - 1
  end)
  if not ok then
    pending[kind] = nil
  end
end

schedule = function(kind, trigger, delay)
  if not active or not AUDIENCES[kind] or not Consent.Allows(FN, "send", kind) then
    return
  end
  local old = due[kind]
  if not old or PL.GAPS[trigger] < PL.GAPS[old] then
    due[kind] = trigger
  end
  arm(kind, delay or (trigger == "enable" and PL.SwitchDelay(P.random) or PL.Delay(P.random)))
end

local function renew()
  renewArmed = false
  local any, moved, soonest = false, false, nil
  for _, kind in ipairs(ORDER) do
    if Consent.Allows(FN, "send", kind) and AUDIENCES[kind].channel() then
      any, moved = true, moved or plan.Moved(kind)
      local ok, why, left = announce(kind, "renew")
      if not ok and why == "wait" and left then
        soonest = math.min(soonest or math.huge, left + 1)
      end
    end
  end
  if any then
    armRenew(soonest or PL.RenewIn(moved, P.random))
  end
end

-- One renewal chain for all audiences; it ends by itself when nothing may be sent any more.
armRenew = function(delay)
  local timer = g("C_Timer")
  if renewArmed or type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  renewArmed = true
  local ok = pcall(timer.After, delay, function()
    depth = depth + 1
    if depth <= 2 then
      ns.Safe("presence", renew)
    else
      renewArmed = false
    end
    depth = depth - 1
  end)
  if not ok then
    renewArmed = false
  end
end

-- The one farewell: only to an audience the mark was delivered to, nothing for anybody else.
local function farewell(kind)
  due[kind] = nil
  plan.Forget(kind)
  carries[kind] = nil
  if delivered[kind] then
    delivered[kind] = nil
    Comm.Send(FN, "R", PL.EncodeFarewell(), kind, nil, { priority = "reply" })
  end
end

-- Receiving ----------------------------------------------------------------------------------------------

-- Comm has checked the receive consent, the sender and the rate before these run; the register of
-- others is only filled for a mark that decodes exactly and only while the audience may still be heard.
local function heard(info)
  local aud = type(info) == "table" and info.aud
  return AUDIENCES[aud] and Consent.Allows(FN, "receive", aud) and aud or nil
end

local function refuse(why)
  refused[why] = (refused[why] or 0) + 1
end

local function onMark(sender, payload, info)
  local msg, why = PL.Decode(payload)
  local aud = heard(info)
  if not msg or not aud or type(sender) ~= "string" then
    refuse(why or "audience")
    return
  end
  local key = PN.Key(sender)
  if key == "" or PN.Equal(sender, PN.Self()) then
    return
  end
  -- The tail is only handed on, never read here; CrestMark checks its own receive consent first.
  local crest = ns.CrestMark
  if msg.logos and crest and type(crest.OnMerged) == "function" then
    pcall(crest.OnMerged, sender, msg.logos, info)
  end
  local stored = registry.Add(key, msg.flags, aud)
  if stored == "stored" then
    heardCount = heardCount + 1
    notify()
  else
    refuse(stored)
  end
end

local function onFarewell(sender, payload, info)
  if not PL.DecodeFarewell(payload) or not heard(info) or type(sender) ~= "string" then
    return
  end
  farewells = farewells + 1
  -- Logos that rode in a mark of this sender go with it; a separate logo message (CM) is its own business.
  local crest = ns.CrestMark
  if crest and type(crest.OnMergedFarewell) == "function" then
    pcall(crest.OnMergedFarewell, sender, info)
  end
  if registry.Remove(PN.Key(sender)) then
    notify()
  end
end

-- The answer to a probe: the mark to one audience now (the plan keeps two messages apart), the renewal goes on from
-- there. Returns true, or false and why.
function P.Answer(kind)
  local moved = plan.Moved(kind)
  local ok, why = announce(kind, "ask")
  if ok then
    armRenew(PL.RenewIn(moved, P.random))
  end
  return ok, why
end

-- Events -------------------------------------------------------------------------------------------------

-- Group size changes: the step from alone to grouped is the join, a bigger group is told again.
function P.OnRoster()
  local before = members
  members = tonumber(try(g("GetNumGroupMembers"))) or 0
  if members < 2 then
    if before >= 2 then
      due.group, delivered.group, carries.group = nil, nil, nil
      plan.Forget("group")
    end
    members = 0
    return
  end
  plan.Touch("group")
  if before < 2 then
    schedule("group", "join")
  elseif members > before then
    schedule("group", "grow")
  end
end

-- A guild member came online: the online count of the game rose since the last read. Nothing that was heard is
-- involved, so this works the same for a player who receives and for one who does not. The first read, the
-- roster of the own login and a guild with a crowd online plan nothing.
function P.OnGuildRoster()
  local read = g("GetNumGuildMembers")
  if type(read) ~= "function" then
    return
  end
  -- Second result: the number of members online.
  local ok, _, value = pcall(read)
  local now = value
  if ns.AutoGuard then
    now = ns.AutoGuard.Safe(value)
  end
  if not ok or type(now) ~= "number" then
    return
  end
  online.events = online.events + 1
  local before = online.last
  online.last = now
  if before == nil or now <= before then
    return
  end
  online.rises = online.rises + 1
  if clock() < (quietUntil or 0) or not PL.OnlineOk(now) then
    return
  end
  -- The logo marks of other functions (CrestMark) listen to the same local event.
  ns.Emit("FG_GUILD_ONLINE", now)
end

ns.On("FG_GUILD_ONLINE", function(_, count)
  if Consent.Allows(FN, "send", "guild") then
    online.planned = online.planned + 1
    schedule("guild", "online", PL.OnlineDelay(P.random, count))
  end
end)

ns.On("GROUP_ROSTER_UPDATE", P.OnRoster)
ns.On("GUILD_ROSTER_UPDATE", P.OnGuildRoster)
ns.On("PLAYER_LOGIN", P.OnRoster)
ns.On("PLAYER_ENTERING_WORLD", function(_, initial, reloading)
  P.OnRoster()
  if initial == true or reloading == true then
    quietUntil = clock() + PL.LIMITS.ONLINE_QUIET
    schedule("guild", "login")
  end
end)
-- The guild showed up after login (late status, join): the mark that the login could not send goes out now.
ns.On("FG_SHARE_GUILD_READY", function()
  if plan.LastAt("guild") == nil and not due.guild then
    schedule("guild", "login")
  end
end)
ns.On("ZONE_CHANGED_NEW_AREA", function()
  for _, kind in ipairs(ORDER) do
    plan.Touch(kind)
  end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  for kind in pairs(due) do
    arm(kind, PL.Delay(P.random))
  end
end)
ns.On("FG_COMM_SENT", function(_, fn, typ, channel)
  if fn == FN and typ == "P" and KIND_OF_CHANNEL[channel] then
    delivered[KIND_OF_CHANNEL[channel]] = true
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.presenceChatOnly" then
    for _, kind in ipairs(ORDER) do
      schedule(kind, "change")
    end
  end
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if fn ~= FN or not AUDIENCES[aud] then
    return
  end
  if dir == "send" then
    if value == true then
      schedule(aud, "enable")
    else
      farewell(aud)
    end
  elseif value ~= true and registry.RemoveSource(aud) > 0 then
    notify()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn ~= FN then
    return
  end
  for _, kind in ipairs(ORDER) do
    farewell(kind)
  end
  if registry.Clear() > 0 then
    notify()
  end
end)

local ok, why = Comm.Register(
  FN,
  ns.ShareSync.Attach(FN, {
    version = 1,
    audiences = ORDER,
    on = { P = onMark, R = onFarewell },
    farewell = "R",
  }, {
    ready = function()
      if not (active and Consent.Allows(FN, "send", "guild")) then
        return false, "inactive"
      end
      if not AUDIENCES.guild.channel() then
        return false, "noguild"
      end
      if locked() then
        return false, "combat"
      end
      return true
    end,
    answer = function()
      return P.Answer("guild")
    end,
  })
)
active = ok
if not ok then
  ns.Log.warn("presence: not registered (%s)", tostring(why))
end
ns.On("FG_COMM_UNREGISTERED", function(_, fn)
  if fn == FN then
    active, due = false, {}
  end
end)
-- The settings tab (a later package) lists a function once it is available.
if Consent.MarkAvailable then
  Consent.MarkAvailable(FN)
end
