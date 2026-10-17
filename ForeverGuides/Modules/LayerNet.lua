-- The layer network: a hidden channel (FGLayer) and addon messages (prefix FGLAYER) between users of this
-- add-on, so a player can find hosts on other layers of the zone. Everything here is opt-in. Without
-- settings.layerShare nothing is joined, sent or read; settings.layerHost (only with layerShare) lets this
-- player invite others who ask for a switch. What goes out: zone map, layer, class, free group places and
-- the character name (the sender of every message), to every user of the channel, nothing else. The
-- format and the rules of the pure part are in LayerNetLogic.lua and docs/LAYER-PROTOKOLL.md.
-- Heartbeat: when joined, every 60 s, 1.5 s after a change (layer, zone, group, host switch) and never in
-- combat or in an instance. Requests of other players arrive as whispers; a host answers only those, with
-- an invite or a reason. Every game call is protected; the receiving and the invite run through
-- AutoGuard (switches layerShare and layerHost, three errors switch them off, the stop key holds the invite).
local _, ns = ...
local Guard, NL, PN, Layer = ns.AutoGuard, ns.LayerNetLogic, ns.PlayerName, ns.Layer

local N = {}
ns.LayerNet = N

ns.AddLocale("enUS", {
  ["layer.net.share"] = "Share with other layer users",
  ["layer.net.host"] = "Help others switch layers",
  ["layer.net.shareTip"] = "Joins the hidden channel FGLayer. Sends zone, layer, class, free group places and your character name to all users of the channel, nothing else. Switch it off at any time.",
  ["layer.net.hostTip"] = "Invites players who ask you for a layer switch. Needs sharing. Not in combat, not in instances.",
  ["layer.net.privacy"] = "Sent to all users of the channel: zone, layer, class, free group places and your character name. Nothing else. Off at any time.",
  ["layer.net.needShare"] = "Switch on sharing first.",
  ["layer.net.invited"] = "Invited %s for a layer switch",
})
ns.AddLocale("deDE", {
  ["layer.net.share"] = "Mit anderen Layer-Nutzern teilen",
  ["layer.net.host"] = "Anderen beim Layer-Wechsel helfen",
  ["layer.net.shareTip"] = "Tritt dem versteckten Kanal FGLayer bei. Sendet Zone, Layer, Klasse, freie Gruppenplätze und deinen Charakternamen an alle Nutzer des Kanals, nichts anderes. Jederzeit abschaltbar.",
  ["layer.net.hostTip"] = "Lädt Spieler ein, die dich nach einem Layer-Wechsel fragen. Braucht das Teilen. Nicht im Kampf, nicht in Instanzen.",
  ["layer.net.privacy"] = "An alle Nutzer des Kanals gesendet: Zone, Layer, Klasse, freie Gruppenplätze und dein Charaktername. Sonst nichts. Jederzeit abschaltbar.",
  ["layer.net.needShare"] = "Schalte zuerst das Teilen ein.",
  ["layer.net.invited"] = "%s für einen Layer-Wechsel eingeladen",
})

-- Seconds between two looks at the clock; a party has this many places.
local TICK = 0.5
-- Seconds before a failed heartbeat is tried again, and while the map or class is not known.
local RETRY, NO_MAP_RETRY = 2, 5
local MAX_CHAT_WINDOWS = 10

local peers = NL.NewPeers()
local limiter = NL.NewLimiter()
local sent = {}
-- Clock of the join that waits for its delay, of the next heartbeat, of the last one and its text.
local joinDue, beatDue, lastAt, lastText
local stripped, prefixAsked = false, false
local driver

local function g(name)
  return rawget(_G, name)
end

local function settings()
  return (ns.db and ns.db.settings) or {}
end

-- First two answers of a game function by its path, hidden values dropped; nil when it is missing or raises.
local function call(path, ...)
  local ok, found, a, b = pcall(Guard.Call, path, ...)
  if ok and found then
    return Guard.Safe(a), Guard.Safe(b)
  end
  return nil
end

function N.Sharing()
  return settings().layerShare == true
end

function N.Hosting()
  return N.Sharing() and settings().layerHost == true
end

-- True in a dungeon, raid, battleground or arena.
local function inInstance()
  local inside, kind = call("IsInInstance")
  return inside == true or inside == 1 or (type(kind) == "string" and kind ~= "none")
end

N.InInstance = inInstance

-- Places the host offers a switcher right now: one while alone, none otherwise. The switcher leaves only a
-- group that holds nobody but the host, so a second invite at the same time would make both switches fail.
local function freePlaces()
  return call("IsInGroup") == true and 0 or 1
end

local function playerClass()
  local _, token = call("UnitClass", "player")
  return type(token) == "string" and NL.CLASSES[token] and token or nil
end

-- The peers table, for the add-on parts that show it and the developer tools.
function N.Peers()
  return peers
end

-- Hosts of the zone the player is in, in the order of the window.
function N.Hosts()
  local now = Guard.Now()
  NL.Expire(peers, now)
  local map = Layer.Map()
  return map and NL.Hosts(peers, map, now, PN.Key(PN.Self())) or {}
end

-- The fresh peer of a name key, nil when it is gone or was never heard.
function N.Peer(key)
  return NL.Get(peers, key, Guard.Now())
end

-- The asked host is still heard as a host.
function N.HostAlive(key)
  local peer = N.Peer(key)
  return peer ~= nil and peer.host == true
end

local function peersChanged()
  ns.Debounce("layer-peers", 0.5, function()
    ns.Emit("FG_LAYER_PEERS")
  end)
end

-- Sending -------------------------------------------------------------------------------------------------

-- One message out. False when sharing is off, the client has no API or is restricted, the burst limit is
-- reached, or (not for a reply to a direct request) we are in combat or an instance.
local function post(text, kind, target, reply)
  local api = g("C_ChatInfo")
  if not N.Sharing() or type(text) ~= "string" or #text > NL.MAX_LENGTH then
    return false
  end
  if type(api) ~= "table" or type(api.SendAddonMessage) ~= "function" or ns.AddonRestricted("Chat") then
    return false
  end
  if not reply and (Guard.Blocked() or inInstance()) then
    return false
  end
  if not NL.BurstTake(sent, Guard.Now()) then
    return false
  end
  return (pcall(api.SendAddonMessage, NL.PREFIX, text, kind, target))
end

-- A whisper to a player, the name exactly as it came in. reply: an answer to a request that came in.
function N.Whisper(name, text, reply)
  if type(name) ~= "string" or name == "" then
    return false
  end
  return post(text, "WHISPER", name, reply)
end

-- Number of the channel when it is joined, nil otherwise (the number is 0 until the server confirms).
local function channelId()
  local id = call("GetChannelName", NL.CHANNEL)
  return type(id) == "number" and id > 0 and id or nil
end

function N.Joined()
  return channelId() ~= nil
end

local function heartbeat()
  local map, class = Layer.Map(), playerClass()
  if not (map and class) then
    return nil
  end
  local layer = Layer.Get()
  layer = NL.UsableLayer(layer) and layer or 0
  return NL.EncodeHeartbeat(map, layer, N.Hosting() and layer > 0, class, freePlaces())
end

-- A change of anything the heartbeat says: it goes out soon, not at once.
local function markChanged()
  if not N.Sharing() then
    return
  end
  local soon = Guard.Now() + NL.DEBOUNCE
  if not beatDue or beatDue > soon then
    beatDue = soon
  end
end

local function beat(now)
  local text = heartbeat()
  if not text then
    beatDue = now + NO_MAP_RETRY
    return
  end
  if text == lastText and lastAt and now - lastAt < NL.HEARTBEAT_GAP then
    beatDue = lastAt + NL.HEARTBEAT_GAP
    return
  end
  local id = channelId()
  if id and post(text, "CHANNEL", id) then
    lastText, lastAt, beatDue = text, now, now + NL.HEARTBEAT_GAP
  else
    beatDue = now + RETRY
  end
end

-- Channel -------------------------------------------------------------------------------------------------

local function ensurePrefix()
  local api = g("C_ChatInfo")
  if not prefixAsked and type(api) == "table" and type(api.RegisterAddonMessagePrefix) == "function" then
    prefixAsked = pcall(api.RegisterAddonMessagePrefix, NL.PREFIX)
  end
end

-- The channel is no business of the chat windows: it carries no text.
local function strip()
  local remove = g("ChatFrame_RemoveChannel")
  if type(remove) ~= "function" then
    return
  end
  for i = 1, tonumber(g("NUM_CHAT_WINDOWS")) or MAX_CHAT_WINDOWS do
    local frame = g("ChatFrame" .. i)
    if type(frame) == "table" then
      pcall(remove, frame, NL.CHANNEL)
    end
  end
end

-- Joins the channel (only with the opt-in, and not twice). True when the join was asked for.
function N.Join()
  if not N.Sharing() or channelId() then
    return false
  end
  local ok = Guard.Run("layerShare", function()
    ensurePrefix()
    Guard.Call("JoinTemporaryChannel", NL.CHANNEL)
  end)
  stripped = false
  return ok
end

-- Leaves the channel and forgets everything heard in it.
function N.Leave()
  pcall(Guard.Call, "LeaveChannelByName", NL.CHANNEL)
  peers = NL.NewPeers()
  limiter, sent = NL.NewLimiter(), {}
  joinDue, beatDue, lastAt, lastText, stripped = nil, nil, nil, nil, false
  peersChanged()
end

-- Receiving -----------------------------------------------------------------------------------------------

local function reply(name, text)
  return N.Whisper(name, text, true)
end

local function decline(name, reason)
  reply(name, NL.EncodeDecline(reason))
end

-- The invite of a host: the limit is taken right before it, so two quick requests cannot both pass.
local function invite(name, key)
  if not NL.LimiterTake(limiter, key, Guard.Now()) then
    return decline(name, "cooldown")
  end
  local found = Guard.Call("C_PartyInfo.InviteUnit", name)
  if not found then
    found = Guard.Call("InviteUnit", name)
  end
  if not found then
    return decline(name, "busy")
  end
  reply(name, NL.EncodeInvite())
  Guard.Say("layerHost", string.format(ns.L["layer.net.invited"], name))
end

-- A whisper "R": the host decides and answers, always with an invite or a reason.
local function onRequest(name, key, request)
  local now = Guard.Now()
  local asker = NL.Get(peers, key, now)
  local ownLayer = Layer.Get()
  local reason = NL.HostCheck({
    enabled = N.Hosting(),
    combat = Guard.Blocked(),
    instance = inInstance(),
    ownMap = Layer.Map(),
    ownLayer = ownLayer,
    free = freePlaces(),
    askerMap = asker and asker.map,
    limiter = limiter,
    key = key,
    now = now,
  }, request)
  -- The stop key holds the automatic invite back: the player decides.
  if not reason and Guard.Paused() then
    reason = "busy"
  end
  if reason then
    return decline(name, reason)
  end
  Guard.Run("layerHost", invite, name, key)
end

local function receive(text, channel, sender)
  text, channel, sender = Guard.Safe(text), Guard.Safe(channel), Guard.Safe(sender)
  local msg, name = NL.Decode(text), NL.CleanSender(sender)
  if not (msg and name) then
    return
  end
  local key = PN.Key(name)
  if key == "" or key == PN.Key(PN.Self()) then
    return
  end
  if channel == "CHANNEL" and msg.kind == "H" then
    if NL.Update(peers, key, name, msg, Guard.Now()) then
      peersChanged()
    end
  elseif channel == "WHISPER" then
    if msg.kind == "R" then
      onRequest(name, key, msg)
    elseif (msg.kind == "A" or msg.kind == "D") and ns.LayerSwitch then
      ns.LayerSwitch.OnReply(msg, key)
    end
  end
end

-- CHAT_MSG_ADDON. Never raises; without the opt-in nothing is read.
function N.OnAddon(prefix, text, channel, sender)
  if prefix == NL.PREFIX and N.Sharing() then
    Guard.Run("layerShare", receive, text, channel, sender)
  end
end

-- Clock -----------------------------------------------------------------------------------------------------

function N.Tick()
  if not N.Sharing() then
    return
  end
  Guard.Run("layerShare", function()
    local now = Guard.Now()
    if joinDue and now >= joinDue then
      joinDue = nil
      N.Join()
    end
    NL.Expire(peers, now)
    if not channelId() then
      return
    end
    if not stripped then
      stripped = true
      strip()
      beatDue = beatDue or now
    end
    if beatDue and now >= beatDue then
      beat(now)
    end
  end)
end

local function onUpdate(self, elapsed)
  self.waited = (self.waited or 0) + elapsed
  if self.waited >= TICK then
    self.waited = 0
    ns.Safe("layer-net", N.Tick)
  end
end

-- The clock runs while sharing is on and not otherwise. The prefix is registered here too: a channel that
-- survived a reload is adopted without a join, and the new session still has to ask for its messages.
function N.Apply()
  if N.Sharing() then
    ensurePrefix()
  end
  if not driver then
    if not N.Sharing() then
      return
    end
    driver = CreateFrame("Frame")
  end
  driver:SetScript("OnUpdate", N.Sharing() and onUpdate or nil)
end

-- The one way to switch hosting on: it needs sharing. False and a hint when it cannot be.
function N.SetHost(on)
  if on == true and not N.Sharing() then
    ns.Notify(ns.L["layer.net.needShare"], "warning")
    return false
  end
  ns.Store.set("settings.layerHost", on == true)
  return true
end

function N.SetShare(on)
  ns.Store.set("settings.layerShare", on == true)
end

-- Events ----------------------------------------------------------------------------------------------------

ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
  N.OnAddon(prefix, text, channel, sender)
end)

-- A login or a loading screen: the join waits a few seconds so the channels of the game are in place first.
ns.On("PLAYER_ENTERING_WORLD", function()
  if not N.Sharing() then
    return
  end
  if channelId() then
    markChanged()
  elseif not joinDue then
    joinDue = Guard.Now() + NL.JOIN_DELAY
  end
  N.Apply()
end)
ns.On("PLAYER_LOGIN", N.Apply)

for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do
  ns.On(event, markChanged)
end
ns.On("FG_LAYER_CHANGED", markChanged)

ns.On("FG_SETTING_CHANGED", function(_, path, value)
  if path == "settings.layerShare" then
    if value == true then
      N.Apply()
      N.Join()
      beatDue = Guard.Now()
    else
      N.Leave()
      N.Apply()
      -- Hosting without sharing would be an armed switch nobody can see.
      if settings().layerHost == true then
        ns.Store.set("settings.layerHost", false)
      end
    end
    peersChanged()
  elseif path == "settings.layerHost" then
    markChanged()
  end
end)
