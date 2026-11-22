-- Version check: players of the own guild and group tell each other which version they run, so a newer release
-- becomes known without any server. Function "versionCheck" (code VC), on until the player switches it off.
--   send     message V = "<own version>|<newest important version or ->" to guild and group: once shortly after
--            login, when the group grows and now and then (never in combat). No query, no answer, no register.
--   receive  a newer version is stored in ns.db.meta.newestSeen once two different senders reported it (one is
--            enough from the own group). The value stays over the session and is dropped when the own version
--            catches up. Event FG_UPDATE_KNOWN when it changed.
-- Sending is blocked by three locks, each alone is enough (receiving stays allowed):
--   1. no release marker (TOC field of the release build, see tools/build_release.py): a development tree is silent
--   2. the developer add-on is loaded (ns.DevTools.active)
--   3. meta.versionCheckSendBlocked, an account wide switch that only the developer add-on sets
local _, ns = ...
local VL, PN, Comm, Consent = ns.VersionCheckLogic, ns.PlayerName, ns.Comm, ns.Consent

local VC = {}
ns.VersionCheck = VC

VC.FN = "versionCheck"
-- Seconds after the login (plus up to LOGIN_SPREAD), between two messages of an audience, after a growing group
-- (plus up to GROW_SPREAD) and until a locked message is tried again.
VC.LOGIN_DELAY, VC.LOGIN_SPREAD = 15, 5
VC.RENEW, VC.RENEW_SPREAD = 1800, 300
VC.GROW_GAP, VC.GROW_DELAY, VC.GROW_SPREAD = 120, 5, 5
VC.LOCKED_RETRY = 30
-- Replaceable in tests: random integer from lo to hi.
function VC.random(lo, hi)
  return math.random(lo, hi)
end

local FN = VC.FN
local RESTRICTIONS = { "Chat", "Combat", "Encounter", "ChallengeMode", "PvPMatch" }

local function g(name)
  return rawget(_G, name)
end

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

local ledgerV, ledgerI = VL.NewLedger(), VL.NewLedger()
local lastAt, due, pending = {}, {}, {}
local members, renewArmed, depth, active = 0, false, 0, false

-- The locks -----------------------------------------------------------------------------------------------

-- Why this client may not send its version, or nil when it may. Without SavedVariables nothing is known: locked.
function VC.SendLock()
  if not VL.ReleaseMarked(ns.releaseMark, ns.version) then
    return "unmarked"
  end
  if ns.DevTools and ns.DevTools.active == true then
    return "dev"
  end
  local meta = ns.db and ns.db.meta
  if type(meta) ~= "table" or meta.versionCheckSendBlocked == true then
    return "blocked"
  end
  return nil
end

-- The version this client may tell others (here and in the presence mark), nil under any lock.
function VC.SendVersion()
  return VC.SendLock() == nil and ns.version or nil
end

-- Knowledge -----------------------------------------------------------------------------------------------

local function stored()
  return ns.db and ns.db.meta and ns.db.meta.newestSeen
end

-- { version, important } of the newest version known to be out, while it is newer than the own one.
function VC.Newest()
  return VL.Valid(stored(), ns.version)
end

-- True while the player listens at all: the footer hint and the notice need the receive switch of an audience.
local function listening()
  for _, kind in ipairs(ORDER) do
    if Consent.Effective(FN, "receive", kind) then
      return true
    end
  end
  return false
end

-- Newest(), but only while receiving is on.
function VC.Known()
  return listening() and VC.Newest() or nil
end

-- The important version this client can name to others: its own when the changelog marks it, else the newest
-- known one while that update counts as important.
function VC.ImportantVersion()
  local data = ns.Data and ns.Data.Changelog
  for _, entry in ipairs(data and data.versions or {}) do
    if entry.version == ns.version and entry.important == true then
      return ns.version
    end
  end
  local newest = VC.Newest()
  return newest and newest.important and newest.version or nil
end

local function remember(value)
  local old = stored()
  if old and value and old.version == value.version and old.important == value.important then
    return false
  end
  if not old and not value then
    return false
  end
  ns.Store.set("meta.newestSeen", value)
  ns.Emit("FG_UPDATE_KNOWN")
  return true
end

-- Drops a stored version the own one has reached.
function VC.Prune()
  local old = stored()
  if old ~= nil and VL.Valid(old, ns.version) == nil then
    return remember(nil)
  end
  return false
end

-- One report of another player. key: the sender's key, fromGroup: it came in on the group channel. Returns true
-- when the stored knowledge changed.
function VC.Hear(key, fromGroup, version, important)
  local own = ns.version
  local believedV, believedI
  if VL.Plausible(own, version) and ledgerV.Add(version, key, fromGroup) then
    believedV = version
  end
  if important and VL.Plausible(own, important) and ledgerI.Add(important, key, fromGroup) then
    believedI = important
  end
  if not believedV and not believedI then
    return false
  end
  return remember(VL.Merge(own, stored(), believedV, believedI))
end

-- Sending ------------------------------------------------------------------------------------------------

local function locked()
  local guard = ns.AutoGuard
  return (guard ~= nil and guard.Blocked()) or ns.InCombat() or ns.AddonRestricted(unpack(RESTRICTIONS))
end

-- Returns true when the message was queued, else false, the reason and for "wait" the seconds left.
local function announce(kind, trigger)
  local def = AUDIENCES[kind]
  local version = VC.SendVersion()
  if not active or not def or not version then
    return false, "locked"
  end
  if not Consent.Effective(FN, "send", kind) then
    return false, "consent"
  end
  if not def.channel() then
    return false, "no-channel"
  end
  if locked() then
    return false, "combat"
  end
  local gap = trigger == "grow" and VC.GROW_GAP or VC.RENEW
  local left = lastAt[kind] and gap - (clock() - lastAt[kind]) or 0
  if left > 0 then
    return false, "wait", left
  end
  local text = VL.Encode(version, VC.ImportantVersion())
  if not text or not Comm.Send(FN, "V", text, kind, nil, { priority = "background" }) then
    return false, "refused"
  end
  lastAt[kind] = clock()
  return true
end

local arm, armRenew

local function fire(kind)
  local trigger = due[kind]
  due[kind] = nil
  if not trigger then
    return
  end
  local ok, why, left = announce(kind, trigger)
  if ok then
    armRenew()
  elseif why == "wait" and left then
    due[kind] = trigger
    arm(kind, left + 1)
  elseif why == "combat" then
    due[kind] = trigger
    arm(kind, VC.LOCKED_RETRY)
  end
end

arm = function(kind, delay)
  local timer = g("C_Timer")
  if pending[kind] or type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  pending[kind] = true
  local ok = pcall(timer.After, delay, function()
    pending[kind] = nil
    depth = depth + 1
    if depth <= 2 then
      ns.Safe("versioncheck", fire, kind)
    end
    depth = depth - 1
  end)
  if not ok then
    pending[kind] = nil
  end
end

local function schedule(kind, trigger, delay)
  if not active or not AUDIENCES[kind] or not VC.SendVersion() then
    return
  end
  due[kind] = due[kind] or trigger
  arm(kind, delay)
end

local function renew()
  renewArmed = false
  for _, kind in ipairs(ORDER) do
    if AUDIENCES[kind].channel() then
      local ok, why, left = announce(kind, "renew")
      if not ok and why == "combat" then
        schedule(kind, "renew", VC.LOCKED_RETRY)
      elseif not ok and why == "wait" then
        schedule(kind, "renew", left + 1)
      end
    end
  end
  armRenew()
end

-- One renewal chain, it ends by itself when this client may not send.
armRenew = function()
  local timer = g("C_Timer")
  if renewArmed or not VC.SendVersion() or type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  renewArmed = true
  local ok = pcall(timer.After, VC.RENEW + VC.random(0, VC.RENEW_SPREAD), function()
    depth = depth + 1
    if depth <= 2 then
      ns.Safe("versioncheck", renew)
    else
      renewArmed = false
    end
    depth = depth - 1
  end)
  if not ok then
    renewArmed = false
  end
end

-- Receiving ----------------------------------------------------------------------------------------------

-- Comm has checked the receive consent, the sender and the rate before this runs.
local function onVersion(sender, payload, info)
  local msg = VL.Decode(payload)
  local aud = type(info) == "table" and info.aud
  if not msg or not AUDIENCES[aud] or type(sender) ~= "string" or not Consent.Effective(FN, "receive", aud) then
    return
  end
  local key = PN.Key(sender)
  if key == "" or PN.Equal(sender, PN.Self()) then
    return
  end
  VC.Hear(key, aud == "group", msg.version, msg.important)
end

-- Events -------------------------------------------------------------------------------------------------

local function spread(base, extra)
  return base + VC.random(0, extra)
end

local function onRoster()
  local before = members
  members = tonumber(try(g("GetNumGroupMembers"))) or 0
  if members < 2 then
    members = 0
  elseif members > before then
    schedule("group", "grow", spread(VC.GROW_DELAY, VC.GROW_SPREAD))
  end
end

ns.On("GROUP_ROSTER_UPDATE", onRoster)
ns.On("PLAYER_LOGIN", function()
  members = tonumber(try(g("GetNumGroupMembers"))) or 0
  VC.Prune()
end)
ns.On("PLAYER_ENTERING_WORLD", function(_, initial, reloading)
  if initial == true or reloading == true then
    for _, kind in ipairs(ORDER) do
      schedule(kind, "login", spread(VC.LOGIN_DELAY, VC.LOGIN_SPREAD))
    end
    armRenew()
  end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  for kind in pairs(due) do
    arm(kind, spread(VC.GROW_DELAY, VC.GROW_SPREAD))
  end
end)

local ok, why = Comm.Register(FN, {
  version = 1,
  audiences = ORDER,
  on = { V = onVersion },
  defaultOn = true,
})
active = ok
if not ok then
  ns.Log.warn("versioncheck: not registered (%s)", tostring(why))
end
ns.On("FG_COMM_UNREGISTERED", function(_, fn)
  if fn == FN then
    active, due = false, {}
  end
end)
Consent.MarkAvailable(FN)
