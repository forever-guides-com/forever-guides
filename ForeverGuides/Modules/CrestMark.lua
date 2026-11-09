-- Guild and community logos: which logos other addon users show next to their name, and which of them this
-- player lets others see. Everything is opt-in and runs through ns.Comm and ns.Consent, function "crestMark"
-- (code CM), independent of the presence mark: whoever shows the add-on logo does not show a guild by that.
--   send     "show my guild and communities" per audience (group, guild): only ids of the directory
--            (CrestLogic) go out, never a name or a picture, and only when a logo is chosen. Timing and limits
--            are those of the presence mark: 2 to 8 seconds late, never in combat, a renewal now and then
--   receive  "see logos of others" per audience: the ids are read into a register in memory
-- One message for both: to an audience the presence mark may send to, the logos ride in that message (see
-- Presence: MergedBody gives the tail, only while the send consent of this function holds) and this function
-- sends nothing of its own there. It sends its own message (C) only to an audience the presence mark may not send
-- to. Both consents stay separate: a tail is read here only with the receive consent of this function, whatever
-- Presence does with the same message. A tail "|" or the farewell of the presence mark removes the logos.
-- Receiving never answers: no hello, no request. The receive consent is checked before a message is decoded.
-- Withdrawing the send consent, or choosing nothing any more, sends one empty farewell and only to the
-- audiences the logos were really delivered to (a presence mark without the tail tells those that heard them in
-- the presence mark); withdrawing the receive consent empties the register.
-- Event FG_CREST_UPDATE (debounced) when the register changed.
local _, ns = ...
local CRL, PL, PN, Comm, Consent = ns.CrestLogic, ns.PresenceLogic, ns.PlayerName, ns.Comm, ns.Consent

local CM = {}
ns.CrestMark = CM

CM.FN = "crestMark"
-- Seconds until a locked (combat, restriction) message is tried again.
CM.LOCKED_RETRY = 30
-- Replaceable in tests: random integer from lo to hi.
function CM.random(lo, hi)
  return math.random(lo, hi)
end

local FN = CM.FN
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

-- The value, or nil when the client calls it secret.
local function safe(value)
  local guard = ns.AutoGuard
  if guard then
    return guard.Safe(value)
  end
  return value
end

local function settings()
  return ns.db and ns.db.settings or {}
end

-- The own logos -------------------------------------------------------------------------------------------

-- "US", "EU", "KR", "TW" or "CN"; nil when the client does not say.
function CM.Region()
  local name = CRL.RegionName(safe(try(g("GetCurrentRegion"))))
  return name
    or CRL.RegionName(safe(try(g("GetCurrentRegionName"))))
    or CRL.RegionName(safe(try(g("GetCVar"), "portal")))
end

-- The name of the own guild, nil without a guild or when the game does not say it.
function CM.GuildName()
  local name = safe(try(g("GetGuildInfo"), "player"))
  return type(name) == "string" and name ~= "" and name or nil
end

-- The directory entry of the own guild, nil without a guild, a readable name, a region or an entry.
function CM.GuildEntry()
  local name, region = CM.GuildName(), CM.Region()
  return name and region and CRL.Directory.FindGuild(region, name) or nil
end

-- Entries of the directory the player can pick as communities: those of the own region (all without a region).
function CM.CommunityChoices()
  return CRL.Directory.List("community", CM.Region())
end

-- Ids of the chosen communities that the directory knows for this region, without doubles, at most 8.
function CM.OwnCommunities()
  local chosen, out, seen = settings().crestCommunities, {}, {}
  if type(chosen) ~= "table" then
    return out
  end
  local allowed = {}
  for _, entry in ipairs(CM.CommunityChoices()) do
    allowed[entry.id] = true
  end
  for _, id in ipairs(chosen) do
    if allowed[id] and not seen[id] and #out < CRL.LIMITS.MAX_COMMUNITIES then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  return out
end

-- The id of the own guild when the player wants it shown and the guild has a logo.
function CM.OwnGuild()
  if settings().crestGuild ~= true then
    return nil
  end
  local entry = CM.GuildEntry()
  return entry and entry.id or nil
end

-- The payload of the own logos, nil when there is nothing to show.
function CM.OwnPayload()
  return CRL.Encode(CM.OwnGuild(), CM.OwnCommunities())
end

-- Directory entries of the own logos, in the order of a chat line.
function CM.OwnEntries()
  return CRL.Entries({ guild = CM.OwnGuild(), communities = CM.OwnCommunities() })
end

-- State --------------------------------------------------------------------------------------------------

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

-- The logos for the presence mark to carry to an audience: the body of the payload, nil while the send consent of
-- this function does not hold, there is no channel or nothing is chosen.
function CM.MergedBody(kind)
  local def = AUDIENCES[kind]
  if not def or not Consent.Allows(FN, "send", kind) or not def.channel() then
    return nil
  end
  return CRL.Body(CM.OwnGuild(), CM.OwnCommunities())
end

-- True when the presence mark sends the message of this audience (and carries the logos in it).
local function merged(kind)
  local presence = ns.Presence
  return presence ~= nil and type(presence.Merges) == "function" and presence.Merges(kind) == true
end

local function clock()
  return Comm.clock()
end

local registry = CRL.NewRegistry(clock)
local plan = PL.NewPlan(clock)
local due, pending, delivered = {}, {}, {}
-- Members online when the last guild member came online, sizes the gap between two such messages.
local onlineCount
local members, depth, renewArmed = 0, 0, false
-- False once the function left the line: nothing is planned or sent any more.
local active = false

local function notify()
  ns.Debounce("crest-update", 1, function()
    ns.Emit("FG_CREST_UPDATE")
  end)
end

local function locked()
  local guard = ns.AutoGuard
  return (guard ~= nil and guard.Blocked()) or ns.InCombat() or ns.AddonRestricted(unpack(RESTRICTIONS))
end

-- Reading the register -----------------------------------------------------------------------------------

-- Receiving is allowed for at least one audience.
function CM.Listening()
  return Consent.Allows(FN, "receive", "group") or Consent.Allows(FN, "receive", "guild")
end

-- Directory entries of the logos a player shows, guild first, in the order of the sender; empty for everybody
-- else and while the receive switch is off. The own name answers with the own choice.
function CM.Entries(name)
  if type(name) ~= "string" or not CM.Listening() then
    return {}
  end
  if PN.Equal(name, PN.Self()) then
    return CM.OwnEntries()
  end
  local key = PN.Key(name)
  local entry = key ~= "" and registry.Get(key) or nil
  -- The receive switch may have gone off for this audience since the entry was stored.
  if entry and Consent.Allows(FN, "receive", entry.src) then
    return CRL.Entries(entry)
  end
  return {}
end

-- True when the player sent logos that are still valid: an add-on user who decides for himself what is shown.
function CM.Known(name)
  local key = type(name) == "string" and PN.Key(name) or ""
  local entry = key ~= "" and registry.Get(key) or nil
  return entry ~= nil and Consent.Allows(FN, "receive", entry.src)
end

function CM.Count()
  return registry.Count()
end

-- Sending -------------------------------------------------------------------------------------------------

-- The own logos to one audience. Returns true when they were queued, else false, the reason and for "wait" the
-- seconds left.
local function announce(kind, trigger)
  local def = AUDIENCES[kind]
  if not active then
    return false, "unregistered"
  end
  if not def or not Consent.Allows(FN, "send", kind) then
    return false, "consent"
  end
  if merged(kind) then
    return false, "merged"
  end
  if not def.channel() then
    return false, "no-channel"
  end
  local payload = CM.OwnPayload()
  if not payload then
    return false, "empty"
  end
  local decision, left = plan.Check(kind, trigger, locked(), trigger == "online" and PL.OnlineGap(onlineCount) or nil)
  if decision ~= "send" then
    return false, decision, left
  end
  if not Comm.Send(FN, "C", payload, kind, nil, { priority = "background" }) then
    return false, "refused"
  end
  plan.Sent(kind)
  return true
end

-- The one farewell: only to an audience the logos were delivered to, nothing for anybody else.
local function farewell(kind)
  due[kind] = nil
  plan.Forget(kind)
  if delivered[kind] then
    delivered[kind] = nil
    Comm.Send(FN, "R", CRL.EncodeFarewell(), kind, nil, { priority = "reply" })
  end
  -- Logos that went out inside the presence mark are taken back by the next mark, which then has no tail.
  local presence = ns.Presence
  if merged(kind) and presence.Carries(kind) then
    presence.Schedule(kind, "enable")
  end
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
    armRenew(PL.RenewIn(moved, CM.random))
  elseif why == "wait" and left then
    due[kind] = trigger
    arm(kind, left + 1)
  elseif why == "combat" then
    due[kind] = trigger
    arm(kind, CM.LOCKED_RETRY)
  elseif why == "empty" then
    -- Nothing chosen any more: whoever was told hears that the logos are gone.
    farewell(kind)
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
      ns.Safe("crestmark", fire, kind)
    end
    depth = depth - 1
  end)
  if not ok then
    pending[kind] = nil
  end
end

local function schedule(kind, trigger, delay)
  if not active or not AUDIENCES[kind] then
    return
  end
  if merged(kind) then
    -- The presence mark plans its own message for every other cause; only a change of the logos is ours.
    if
      (trigger == "change" or trigger == "enable") and (Consent.Allows(FN, "send", kind) or ns.Presence.Carries(kind))
    then
      ns.Presence.Schedule(kind, trigger, delay)
    end
    return
  end
  if not Consent.Allows(FN, "send", kind) then
    return
  end
  local old = due[kind]
  if not old or PL.GAPS[trigger] < PL.GAPS[old] then
    due[kind] = trigger
  end
  arm(kind, delay or (trigger == "enable" and PL.SwitchDelay(CM.random) or PL.Delay(CM.random)))
end

local function renew()
  renewArmed = false
  local any, moved, soonest = false, false, nil
  for _, kind in ipairs(ORDER) do
    if Consent.Allows(FN, "send", kind) and AUDIENCES[kind].channel() then
      moved = moved or plan.Moved(kind)
      local ok, why, left = announce(kind, "renew")
      if ok or why == "wait" then
        any = true
      end
      if why == "wait" and left then
        soonest = math.min(soonest or math.huge, left + 1)
      end
    end
  end
  if any then
    armRenew(soonest or PL.RenewIn(moved, CM.random))
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
      ns.Safe("crestmark", renew)
    else
      renewArmed = false
    end
    depth = depth - 1
  end)
  if not ok then
    renewArmed = false
  end
end

-- The answer to a probe. With the presence mark on the line the logos ride in its message, so that one is the
-- answer (it may have gone out for a probe of its own a moment ago); else the logos go out in a message of their own.
-- Returns true, or false and why.
function CM.Answer()
  local kind = "guild"
  if not active or not Consent.Allows(FN, "send", kind) then
    return false, "consent"
  end
  if merged(kind) then
    if not CM.MergedBody(kind) then
      return false, "empty"
    end
    if ns.ShareSync.AnsweredWithin("presenceMark", 30) then
      return true
    end
    return ns.Presence.Answer(kind)
  end
  local moved = plan.Moved(kind)
  local ok, why = announce(kind, "ask")
  if ok then
    armRenew(PL.RenewIn(moved, CM.random))
  end
  return ok, why
end

-- Receiving -----------------------------------------------------------------------------------------------

-- Comm has checked the receive consent, the sender and the rate before these run; the register is only filled
-- for a message that decodes exactly and only while the audience may still be heard.
local function heard(info)
  local aud = type(info) == "table" and info.aud
  return AUDIENCES[aud] and Consent.Allows(FN, "receive", aud) and aud or nil
end

-- Stores what a sender shows; logos this directory does not know leave an empty entry out.
local function store(sender, msg, aud)
  local key = PN.Key(sender)
  if not msg or key == "" or PN.Equal(sender, PN.Self()) then
    return
  end
  if msg.guild == nil and #msg.communities == 0 then
    -- Logos this directory does not know: whatever was stored before is outdated.
    if registry.Remove(key) then
      notify()
    end
  elseif registry.Add(key, msg, aud) == "stored" then
    notify()
  end
end

local function onCrest(sender, payload, info)
  local aud = heard(info)
  if not aud or type(sender) ~= "string" then
    return
  end
  store(sender, CRL.Decode(payload), aud)
end

-- The tail of a presence mark (Presence hands it over undecoded). The receive consent of this function is checked
-- before anything is read, so a player who receives marks only does not store a logo.
function CM.OnMerged(sender, tail, info)
  local aud = heard(info)
  if not aud or type(sender) ~= "string" or type(tail) ~= "string" then
    return
  end
  if tail == PL.NO_LOGOS then
    local key = PN.Key(sender)
    if key ~= "" and not PN.Equal(sender, PN.Self()) and registry.Remove(key) then
      notify()
    end
    return
  end
  store(sender, CRL.DecodeBody(tail), aud)
end

-- The farewell of the presence mark: the logos that came in it are gone with it.
function CM.OnMergedFarewell(sender, info)
  if not heard(info) or type(sender) ~= "string" then
    return
  end
  if registry.Remove(PN.Key(sender)) then
    notify()
  end
end

local function onFarewell(sender, payload, info)
  if not CRL.DecodeFarewell(payload) or not heard(info) or type(sender) ~= "string" then
    return
  end
  if registry.Remove(PN.Key(sender)) then
    notify()
  end
end

-- Events -------------------------------------------------------------------------------------------------

local function changed()
  for _, kind in ipairs(ORDER) do
    schedule(kind, "change")
  end
end

-- Group size changes: the step from alone to grouped is the join, a bigger group is told again.
function CM.OnRoster()
  local before = members
  members = tonumber(try(g("GetNumGroupMembers"))) or 0
  if members < 2 then
    if before >= 2 then
      due.group, delivered.group = nil, nil
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

-- A guild member came online (local event of Presence, nothing heard): the late player learns the own logos too.
ns.On("FG_GUILD_ONLINE", function(_, count)
  onlineCount = count
  schedule("guild", "online", PL.OnlineDelay(CM.random, count))
end)

ns.On("GROUP_ROSTER_UPDATE", CM.OnRoster)
ns.On("PLAYER_LOGIN", CM.OnRoster)
ns.On("PLAYER_ENTERING_WORLD", function(_, initial, reloading)
  CM.OnRoster()
  if initial == true or reloading == true then
    schedule("guild", "login")
  end
end)
ns.On("PLAYER_GUILD_UPDATE", function(_, unit)
  if unit == nil or unit == "player" then
    changed()
  end
end)
-- The guild showed up after login (late status, join): the logos that the login could not send go out now.
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
    arm(kind, PL.Delay(CM.random))
  end
end)
ns.On("FG_COMM_SENT", function(_, fn, typ, channel)
  if fn == FN and typ == "C" and KIND_OF_CHANNEL[channel] then
    delivered[KIND_OF_CHANNEL[channel]] = true
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.crestGuild" or path == "settings.crestCommunities" then
    changed()
  end
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if fn == "presenceMark" and dir == "send" and value ~= true and AUDIENCES[aud] then
    -- The presence mark no longer speaks to this audience: the logos go out in a message of their own.
    schedule(aud, "enable")
    return
  end
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
  if fn == "presenceMark" then
    for _, kind in ipairs(ORDER) do
      schedule(kind, "enable")
    end
    return
  end
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
    on = { C = onCrest, R = onFarewell },
    farewell = "R",
  }, {
    ready = function()
      if not active then
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
    answer = CM.Answer,
  })
)
active = ok
if not ok then
  ns.Log.warn("crestmark: not registered (%s)", tostring(why))
end
ns.On("FG_COMM_UNREGISTERED", function(_, fn)
  if fn == FN then
    active, due = false, {}
  end
end)
Consent.MarkAvailable(FN)
