-- The layer switch, the game side of LayerSwitchLogic.lua: a click asks a host of the zone by whisper, the
-- host invites, the invite of exactly that host is accepted, the layer is read again every 3 s until it
-- changed, and the group is left again. One switch at a time; the state lives in the machine of the pure
-- part, this file asks the game for the facts and does what the machine says.
-- This is automation, so it runs under AutoGuard (switch layerShare): protected calls, three errors switch
-- the sharing off, nothing happens in combat or while the stop key is held (the invite then stays with the
-- player), and an invite is never accepted while queued. The only automatic accept is the invite of the
-- host that was asked, not older than 15 s; the only automatic leave is a group this switch made with that
-- host as its only other member. AutoSocial leaves the invite of the asked host alone (Expects).
local _, ns = ...
local Guard, NL, SL, PN, Layer, L = ns.AutoGuard, ns.LayerNetLogic, ns.LayerSwitchLogic, ns.PlayerName, ns.Layer, ns.L

local Sw = {}
ns.LayerSwitch = Sw

ns.AddLocale("enUS", {
  ["layer.net.asking"] = "Asking %s (%d of %d)",
  ["layer.net.joined"] = "In the group of %s, waiting for the new layer (%d s)",
  ["layer.net.done"] = "Layer %d → %d",
  ["layer.net.failed"] = "Switch failed: %s",
  ["layer.net.failedMore"] = "Switch failed: %s Another host is left.",
  ["layer.net.why.off"] = "The host does not help right now.",
  ["layer.net.why.busy"] = "The host is busy.",
  ["layer.net.why.full"] = "The group of the host is full.",
  ["layer.net.why.otherzone"] = "The host is in another zone.",
  ["layer.net.why.cooldown"] = "The host has invited too often just now.",
  ["layer.net.why.combat"] = "The host is in combat.",
  ["layer.net.why.timeout"] = "The host did not answer.",
  ["layer.net.why.noinvite"] = "The invite did not arrive.",
  ["layer.net.why.hostgone"] = "The host left the group.",
  ["layer.net.why.nochange"] = "The layer did not change.",
  ["layer.net.why.group"] = "Your group changed.",
  ["layer.net.why.zone"] = "You changed zones.",
  ["layer.net.why.mycombat"] = "You are in combat.",
  ["layer.net.why.cancel"] = "Cancelled.",
  ["layer.net.why.send"] = "The request could not be sent.",
  ["layer.net.why.nohost"] = "No host to ask.",
  ["layer.net.block.share"] = "Switch on sharing first.",
  ["layer.net.block.busy"] = "A switch is running.",
  ["layer.net.block.combat"] = "Not possible in combat.",
  ["layer.net.block.instance"] = "Not possible in an instance.",
  ["layer.net.block.group"] = "Leave your group first.",
  ["layer.net.block.queued"] = "Leave the queue first.",
  ["layer.net.block.layer"] = "Layer unknown: target an NPC.",
  ["layer.net.block.nohost"] = "No host in this zone.",
  ["layer.net.block.samelayer"] = "The host is on your layer.",
  ["layer.net.block.full"] = "The group of the host is full.",
})
ns.AddLocale("deDE", {
  ["layer.net.asking"] = "Frage %s (%d von %d)",
  ["layer.net.joined"] = "In der Gruppe von %s, warte auf den neuen Layer (%d s)",
  ["layer.net.done"] = "Layer %d → %d",
  ["layer.net.failed"] = "Wechsel fehlgeschlagen: %s",
  ["layer.net.failedMore"] = "Wechsel fehlgeschlagen: %s Ein weiterer Host ist übrig.",
  ["layer.net.why.off"] = "Der Host hilft gerade nicht.",
  ["layer.net.why.busy"] = "Der Host ist beschäftigt.",
  ["layer.net.why.full"] = "Die Gruppe des Hosts ist voll.",
  ["layer.net.why.otherzone"] = "Der Host ist in einer anderen Zone.",
  ["layer.net.why.cooldown"] = "Der Host hat gerade zu oft eingeladen.",
  ["layer.net.why.combat"] = "Der Host ist im Kampf.",
  ["layer.net.why.timeout"] = "Der Host hat nicht geantwortet.",
  ["layer.net.why.noinvite"] = "Die Einladung kam nicht an.",
  ["layer.net.why.hostgone"] = "Der Host hat die Gruppe verlassen.",
  ["layer.net.why.nochange"] = "Der Layer hat sich nicht geändert.",
  ["layer.net.why.group"] = "Deine Gruppe hat sich geändert.",
  ["layer.net.why.zone"] = "Du hast die Zone gewechselt.",
  ["layer.net.why.mycombat"] = "Du bist im Kampf.",
  ["layer.net.why.cancel"] = "Abgebrochen.",
  ["layer.net.why.send"] = "Die Anfrage konnte nicht gesendet werden.",
  ["layer.net.why.nohost"] = "Kein Host zum Fragen.",
  ["layer.net.block.share"] = "Schalte zuerst das Teilen ein.",
  ["layer.net.block.busy"] = "Ein Wechsel läuft.",
  ["layer.net.block.combat"] = "Im Kampf nicht möglich.",
  ["layer.net.block.instance"] = "In einer Instanz nicht möglich.",
  ["layer.net.block.group"] = "Verlasse zuerst deine Gruppe.",
  ["layer.net.block.queued"] = "Verlasse zuerst die Warteschlange.",
  ["layer.net.block.layer"] = "Layer unbekannt: NPC anvisieren.",
  ["layer.net.block.nohost"] = "Kein Host in dieser Zone.",
  ["layer.net.block.samelayer"] = "Der Host ist auf deinem Layer.",
  ["layer.net.block.full"] = "Die Gruppe des Hosts ist voll.",
})

local ID = "layerShare"
-- At most this many hosts are tried one after the other.
local MAX_HOSTS = 8
local TICK = 0.5

local machine = SL.New(Guard.Now)
local announced
local driver

-- Facts ---------------------------------------------------------------------------------------------------

local function call(path, ...)
  local ok, found, value = pcall(Guard.Call, path, ...)
  if ok and found then
    return Guard.Safe(value)
  end
  return nil
end

-- Keys of the members of the group besides the player, and whether there is a group at all.
local function roster()
  local out = { grouped = call("IsInGroup") == true, others = {} }
  if not out.grouped then
    return out
  end
  local raid = call("IsInRaid") == true
  local count = tonumber(call("GetNumGroupMembers")) or 0
  for i = 1, raid and count or count - 1 do
    local unit = (raid and "raid" or "party") .. i
    if call("UnitIsUnit", unit, "player") ~= true then
      local name = PN.Display(unit)
      if name then
        out.others[#out.others + 1] = PN.Key(name)
      end
    end
  end
  return out
end

local function startEnv()
  local layer = Layer.Get()
  return {
    grouped = roster().grouped,
    instance = ns.LayerNet.InInstance(),
    combat = Guard.Blocked(),
    queued = ns.AutoSocial.Queued(),
    layer = layer,
    map = Layer.Map(),
  }
end

-- Public --------------------------------------------------------------------------------------------------

-- The machine of the switch, for the developer tools and tests (the simulation drives it without sending).
function Sw.Machine()
  return machine
end

-- Why no switch can start now (suffix of "layer.net.block.*"), nil when one can.
function Sw.CanStart()
  if not ns.LayerNet.Sharing() then
    return "share"
  end
  return SL.CanStart(machine, startEnv())
end

-- Is the player waiting for the invite of this name, or in the group it made? AutoSocial must leave that
-- invite alone.
function Sw.Expects(name)
  if not (SL.Active(machine) and machine.host) or type(name) ~= "string" then
    return false
  end
  return PN.Key(name) == machine.host.key
end

-- What the window shows: phase, host name, 1-based index and count of the hosts, seconds left in joined,
-- and the result of a finished switch.
function Sw.Status()
  local status = { phase = machine.phase, total = #machine.hosts, index = machine.index, result = machine.result }
  status.host = machine.host and machine.host.name
  if machine.phase == "joined" and machine.joinedAt then
    status.left = math.max(0, math.ceil(SL.CHANGE_TIMEOUT - (Guard.Now() - machine.joinedAt)))
  end
  return status
end

-- Machine to game ------------------------------------------------------------------------------------------

local function failedText(result)
  local why = L["layer.net.why." .. tostring(result.reason)] or tostring(result.reason)
  return string.format(L[(result.remaining or 0) > 0 and "layer.net.failedMore" or "layer.net.failed"], why)
end

-- The text of a finished switch, for the window and the message.
function Sw.ResultText(result)
  if result.kind == "done" then
    return string.format(L["layer.net.done"], result.from, result.to)
  end
  return failedText(result)
end

local perform

local function request(host)
  local text = NL.EncodeRequest(machine.origin.map, machine.origin.layer)
  if not (text and ns.LayerNet.Whisper(host.name, text)) then
    perform(SL.OnReply(machine, "D", host.key, "send"))
  end
end

local function leave()
  local found = Guard.Call("C_PartyInfo.LeaveParty")
  if not found then
    Guard.Call("LeaveParty")
  end
end

function perform(actions)
  for _, action in ipairs(actions) do
    if action.kind == "request" then
      request(action.host)
    elseif action.kind == "refresh" then
      Layer.Refresh()
    elseif action.kind == "leave" then
      leave()
    end
  end
end

-- The clock runs only while there is something to wait for.
local function apply()
  local busy = SL.Active(machine) or machine.pendingLeave ~= nil
  if busy and not driver then
    driver = CreateFrame("Frame")
  end
  if driver then
    driver:SetScript("OnUpdate", busy and Sw.OnUpdate or nil)
  end
end

-- A finished switch is told once; the window hears of every change.
local function settle()
  local result = machine.result
  if result and result ~= announced and not SL.Active(machine) then
    announced = result
    ns.Notify(Sw.ResultText(result), result.kind == "done" and "success" or "warning", { force = true })
  end
  apply()
  ns.Emit("FG_LAYER_SWITCH")
end

-- Brings window and clock in line with the machine, for the developer tools too.
Sw.Settle = settle

local function begin(hosts)
  local actions, reason = SL.Start(machine, hosts, startEnv())
  if not actions then
    return false, reason
  end
  announced = nil
  perform(actions)
  settle()
  return true
end

-- Asks one host (a peer of LayerNet.Hosts) first, nobody after it. Returns true, or false and the reason.
function Sw.StartWith(key)
  local reason = Sw.CanStart()
  if reason then
    return false, reason
  end
  local peer = ns.LayerNet.Peer(key)
  if not (peer and peer.host) then
    return false, "nohost"
  end
  local ok, why
  Guard.Run(ID, function()
    ok, why = begin({ peer })
  end)
  return ok == true, why
end

-- Asks the best hosts of the zone in the order of the list (most free places first). Returns true, or false
-- and the reason.
function Sw.Best()
  local reason = Sw.CanStart()
  if reason then
    return false, reason
  end
  local targets = NL.Targets(ns.LayerNet.Hosts(), Layer.Get())
  local hosts = {}
  for i = 1, math.min(MAX_HOSTS, #targets) do
    hosts[i] = targets[i]
  end
  local ok, why
  Guard.Run(ID, function()
    ok, why = begin(hosts)
  end)
  return ok == true, why
end

function Sw.Cancel()
  Guard.Run(ID, function()
    SL.Cancel(machine)
    settle()
  end)
end

-- An answer of a host, from LayerNet.
function Sw.OnReply(msg, key)
  Guard.Run(ID, function()
    perform(SL.OnReply(machine, msg.kind, key, msg.reason))
    settle()
  end)
end

-- The clock: asks the machine what is due and does it.
function Sw.Tick()
  Guard.Run(ID, function()
    local host = machine.host
    perform(SL.Tick(machine, {
      combat = Guard.Paused() ~= nil,
      hostAlive = host == nil or ns.LayerNet.HostAlive(host.key),
      roster = roster(),
    }))
    settle()
  end)
end

function Sw.OnUpdate(self, elapsed)
  self.waited = (self.waited or 0) + elapsed
  if self.waited >= TICK then
    self.waited = 0
    Sw.Tick()
  end
end

-- Events ----------------------------------------------------------------------------------------------------

-- A group invite. Accepted only from the host that was asked, never while queued, in combat or with the stop key held.
function Sw.OnInvite(inviter)
  inviter = Guard.Safe(inviter)
  if type(inviter) ~= "string" or inviter == "" or not SL.Active(machine) then
    return
  end
  if Guard.Paused() or ns.AutoSocial.Queued() or not Guard.Has("AcceptGroup") then
    return
  end
  if SL.OnInvite(machine, PN.Key(inviter)) then
    Guard.Call("AcceptGroup")
    if Guard.Has("StaticPopup_Hide") then
      Guard.Call("StaticPopup_Hide", "PARTY_INVITE")
    end
    Guard.Say(ID, string.format(L["auto.social.accepted"], inviter))
    settle()
  end
end

ns.On("PARTY_INVITE_REQUEST", function(_, inviter)
  Guard.Run(ID, Sw.OnInvite, inviter)
end)

ns.On("GROUP_ROSTER_UPDATE", function()
  if machine.phase ~= "idle" then
    Guard.Run(ID, function()
      SL.OnRoster(machine, roster())
      settle()
    end)
  end
end)

ns.On("FG_LAYER_CHANGED", function(_, layer)
  if machine.phase == "joined" then
    Guard.Run(ID, function()
      SL.OnLayer(machine, layer, Layer.Map())
      settle()
    end)
  end
end)

ns.On("PLAYER_REGEN_DISABLED", function()
  if SL.Active(machine) then
    Guard.Run(ID, function()
      SL.OnCombat(machine)
      settle()
    end)
  end
end)

local function onZone()
  if SL.Active(machine) then
    Guard.Run(ID, function()
      SL.OnZone(machine, Layer.Map())
      settle()
    end)
  end
end
ns.On("ZONE_CHANGED_NEW_AREA", onZone)
ns.On("PLAYER_ENTERING_WORLD", onZone)

-- Switching the sharing off ends a running switch and drops its leave: the player opted out of automatic actions.
ns.On("FG_SETTING_CHANGED", function(_, path, value)
  if path == "settings.layerShare" and value ~= true and machine.phase ~= "idle" then
    SL.Cancel(machine)
    machine.pendingLeave = nil
    settle()
  end
end)
