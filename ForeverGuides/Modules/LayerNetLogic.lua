-- Pure part of the layer network (LayerNet.lua, LayerSwitch.lua): the message format of the FGLAYER prefix
-- with a strict decoder, the table of peers heard in the channel (they are forgotten after PEER_TTL), the
-- list of hosts of one zone in the order the window shows it, the checks a host makes before it invites,
-- and the rate limits. No game calls, so every shape of message and every clock value is testable.
-- Protocol version 1, plain ASCII, always below 255 characters (docs/LAYER-PROTOKOLL.md):
--   H|1|<map>|<layer>|<role>|<class>|<free>   heartbeat in the channel, role n (only there) or h (host)
--   R|1|<map>|<layer>                          whisper: please invite me (map and layer of the asker)
--   A|1                                        whisper: the invite is on its way
--   D|1|<reason>                               whisper: no (off, busy, full, otherzone, cooldown, combat)
local _, ns = ...
local PN = ns.PlayerName

local M = {}
ns.LayerNetLogic = M

M.PREFIX = "FGLAYER"
M.CHANNEL = "FGLayer"
M.VERSION = 1
M.MAX_LENGTH = 255
M.MAX_MAP = 999999
M.MAX_LAYER = 999999999
M.MAX_FREE = 40
-- Seconds. Peers that stay silent this long are forgotten; a heartbeat comes every HEARTBEAT_GAP seconds.
M.PEER_TTL = 180
M.HEARTBEAT_GAP = 60
-- Changes are announced at most once in this time, a login waits JOIN_DELAY before it joins the channel.
M.DEBOUNCE = 1.5
M.JOIN_DELAY = 6
-- Heartbeats of one sender closer together than this are skipped (a flood costs nothing but one table read).
M.PEER_MIN_GAP = 1
M.MAX_PEERS = 400
-- Host limits: one invite per sender and SENDER_GAP seconds, INVITES_PER_MINUTE in total.
M.SENDER_GAP = 30
M.INVITES_PER_MINUTE = 6
-- At most this many sends inside BURST_SPAN seconds, as in PeerComm.
M.BURST = 5
M.BURST_SPAN = 10

M.REASONS = { off = true, busy = true, full = true, otherzone = true, cooldown = true, combat = true }
M.CLASSES = {}
for _, token in ipairs({
  "WARRIOR",
  "PALADIN",
  "HUNTER",
  "ROGUE",
  "PRIEST",
  "DEATHKNIGHT",
  "SHAMAN",
  "MAGE",
  "WARLOCK",
  "MONK",
  "DRUID",
  "DEMONHUNTER",
  "EVOKER",
}) do
  M.CLASSES[token] = true
end

-- Values --------------------------------------------------------------------------------------------------

local function isInt(value, min, max)
  return type(value) == "number" and value == value and value % 1 == 0 and value >= min and value <= max
end

-- A layer id the add-on can use as a place to switch to: 1 or more. 0 stands for "unknown" on the wire.
function M.UsableLayer(value)
  return isInt(value, 1, M.MAX_LAYER)
end

-- The number of a field written the one way Encode writes it: digits, no leading zero, within the range.
local function number(field, max)
  if not field:find("^%d+$") or (#field > 1 and field:sub(1, 1) == "0") or #field > #tostring(max) then
    return nil
  end
  local value = tonumber(field)
  return value <= max and value or nil
end

-- Protocol ------------------------------------------------------------------------------------------------

-- The heartbeat for the zone map, the own layer (nil or 0: unknown), host or not, class token, free places.
-- nil when a value is outside its range, so a broken value never goes out.
function M.EncodeHeartbeat(map, layer, host, class, free)
  layer = layer or 0
  if not (isInt(map, 1, M.MAX_MAP) and isInt(layer, 0, M.MAX_LAYER) and isInt(free, 0, M.MAX_FREE)) then
    return nil
  end
  if type(class) ~= "string" or not M.CLASSES[class] then
    return nil
  end
  return string.format("H|%d|%d|%d|%s|%s|%d", M.VERSION, map, layer, host and "h" or "n", class, free)
end

function M.EncodeRequest(map, layer)
  if not (isInt(map, 1, M.MAX_MAP) and M.UsableLayer(layer)) then
    return nil
  end
  return string.format("R|%d|%d|%d", M.VERSION, map, layer)
end

function M.EncodeInvite()
  return string.format("A|%d", M.VERSION)
end

function M.EncodeDecline(reason)
  if not M.REASONS[reason] then
    return nil
  end
  return string.format("D|%d|%s", M.VERSION, reason)
end

local function fields(text)
  local out = {}
  for field in (text .. "|"):gmatch("([^|]*)|") do
    out[#out + 1] = field
  end
  return out
end

-- { kind = "H", map, layer, host, class, free }, { kind = "R", map, layer }, { kind = "A" } or
-- { kind = "D", reason }; nil for anything that is not exactly the format: other version, other type,
-- wrong number of fields, a number with a leading zero or out of range, a class or reason that is not
-- in the lists, a character outside printable ASCII.
function M.Decode(text)
  if type(text) ~= "string" or #text < 3 or #text > M.MAX_LENGTH or text:find("[^\32-\126]") then
    return nil
  end
  local f = fields(text)
  if f[2] ~= tostring(M.VERSION) then
    return nil
  end
  local kind, count = f[1], #f
  if kind == "H" and count == 7 then
    local map, layer, free = number(f[3], M.MAX_MAP), number(f[4], M.MAX_LAYER), number(f[7], M.MAX_FREE)
    if map and map >= 1 and layer and free and (f[5] == "n" or f[5] == "h") and M.CLASSES[f[6]] then
      return { kind = "H", map = map, layer = layer, host = f[5] == "h", class = f[6], free = free }
    end
  elseif kind == "R" and count == 4 then
    local map, layer = number(f[3], M.MAX_MAP), number(f[4], M.MAX_LAYER)
    if map and map >= 1 and layer and layer >= 1 then
      return { kind = "R", map = map, layer = layer }
    end
  elseif kind == "A" and count == 2 then
    return { kind = "A" }
  elseif kind == "D" and count == 3 and M.REASONS[f[3]] then
    return { kind = "D", reason = f[3] }
  end
  return nil
end

-- Peers --------------------------------------------------------------------------------------------------

-- Peers are kept by name key (PlayerName.Key); name is the sender exactly as the client delivered it,
-- the one spelling a whisper and an invite may use.
function M.NewPeers()
  return { byKey = {}, count = 0 }
end

local function fresh(peer, now)
  return peer.seen <= now and now - peer.seen < M.PEER_TTL
end

-- Forgets the peers that stayed silent too long (or whose time lies in the future). Returns how many.
function M.Expire(peers, now)
  local removed = 0
  for key, peer in pairs(peers.byKey) do
    if not fresh(peer, now) then
      peers.byKey[key] = nil
      peers.count = peers.count - 1
      removed = removed + 1
    end
  end
  return removed
end

local function evictOldest(peers)
  local oldestKey, oldest
  for key, peer in pairs(peers.byKey) do
    if not oldest or peer.seen < oldest then
      oldestKey, oldest = key, peer.seen
    end
  end
  if oldestKey then
    peers.byKey[oldestKey] = nil
    peers.count = peers.count - 1
  end
end

-- Stores a decoded heartbeat. False for anything else, for an empty key and for a sender that is too
-- quick. A full table drops its oldest peer, so a flood of made-up names cannot grow it.
function M.Update(peers, key, name, msg, now)
  if type(key) ~= "string" or key == "" or type(name) ~= "string" or type(msg) ~= "table" or msg.kind ~= "H" then
    return false
  end
  local known = peers.byKey[key]
  if known and known.seen <= now and now - known.seen < M.PEER_MIN_GAP then
    return false
  end
  if not known then
    if peers.count >= M.MAX_PEERS then
      M.Expire(peers, now)
    end
    if peers.count >= M.MAX_PEERS then
      evictOldest(peers)
    end
    peers.count = peers.count + 1
  end
  peers.byKey[key] = {
    key = key,
    name = name,
    map = msg.map,
    layer = msg.layer,
    host = msg.host,
    class = msg.class,
    free = msg.free,
    seen = now,
  }
  return true
end

function M.Forget(peers, key)
  if peers.byKey[key] then
    peers.byKey[key] = nil
    peers.count = peers.count - 1
  end
end

-- The peer of a key while it is fresh, else nil.
function M.Get(peers, key, now)
  local peer = peers.byKey[key]
  if peer and fresh(peer, now) then
    return peer
  end
  return nil
end

-- The hosts of the zone map with a usable layer: most free places first, then the one heard last.
-- selfKey is left out. A host without free places stays in (the window says why it cannot be used).
function M.Hosts(peers, map, now, selfKey)
  local out = {}
  for key, peer in pairs(peers.byKey) do
    if peer.host and peer.map == map and key ~= selfKey and M.UsableLayer(peer.layer) and fresh(peer, now) then
      out[#out + 1] = peer
    end
  end
  table.sort(out, function(a, b)
    if a.free ~= b.free then
      return a.free > b.free
    end
    if a.seen ~= b.seen then
      return a.seen > b.seen
    end
    return a.key < b.key
  end)
  return out
end

-- Why a host is no target for a player on ownLayer: "samelayer" or "full"; nil when it is one.
function M.TargetBlock(host, ownLayer)
  if host.layer == ownLayer then
    return "samelayer"
  elseif host.free < 1 then
    return "full"
  end
  return nil
end

-- The hosts worth asking, in the order they were given.
function M.Targets(hosts, ownLayer)
  local out = {}
  for _, host in ipairs(hosts) do
    if not M.TargetBlock(host, ownLayer) then
      out[#out + 1] = host
    end
  end
  return out
end

-- Rate limits ---------------------------------------------------------------------------------------------

function M.NewLimiter()
  return { senders = {}, log = {} }
end

local function prune(limiter, now)
  for key, at in pairs(limiter.senders) do
    if at > now or now - at >= M.SENDER_GAP then
      limiter.senders[key] = nil
    end
  end
  for i = #limiter.log, 1, -1 do
    local at = limiter.log[i]
    if at > now or now - at >= 60 then
      table.remove(limiter.log, i)
    end
  end
end

-- True when an invite for this sender is allowed at time now (nothing is recorded).
function M.LimiterCheck(limiter, key, now)
  prune(limiter, now)
  return limiter.senders[key] == nil and #limiter.log < M.INVITES_PER_MINUTE
end

-- Records an invite and says whether it was allowed.
function M.LimiterTake(limiter, key, now)
  if not M.LimiterCheck(limiter, key, now) then
    return false
  end
  limiter.senders[key] = now
  limiter.log[#limiter.log + 1] = now
  return true
end

-- Burst limit of the sends: true and the time is recorded, or false when BURST sends are inside BURST_SPAN.
function M.BurstTake(sent, now)
  for i = #sent, 1, -1 do
    if now - sent[i] >= M.BURST_SPAN or sent[i] > now then
      table.remove(sent, i)
    end
  end
  if #sent >= M.BURST then
    return false
  end
  sent[#sent + 1] = now
  return true
end

-- Host checks -----------------------------------------------------------------------------------------------

-- The reason (a key of M.REASONS) why a host does not invite for a request, nil when it may. env:
-- enabled (layerShare and layerHost on), combat, instance, ownMap, ownLayer (nil or 0 unknown), free
-- (places left), askerMap (map the asker's heartbeat says, nil for an asker nobody heard), limiter, key,
-- now; request is the decoded R. Nothing is recorded: the caller takes the limit right before it invites.
function M.HostCheck(env, request)
  if not env.enabled then
    return "off"
  elseif env.combat then
    return "combat"
  elseif env.instance or not M.UsableLayer(env.ownLayer) then
    return "busy"
  elseif request.map ~= env.ownMap or env.askerMap ~= env.ownMap then
    return "otherzone"
  elseif (env.free or 0) < 1 then
    return "full"
  elseif request.layer == env.ownLayer then
    return "busy"
  elseif not M.LimiterCheck(env.limiter, env.key, env.now) then
    return "cooldown"
  end
  return nil
end

-- A sender name as the client delivers it, usable as the target of a whisper and an invite: not empty,
-- no control characters, no pipes, one blank at most between the parts (PlayerName.Clean leaves it as it is).
function M.CleanSender(name)
  if type(name) ~= "string" or name == "" or #name > 64 then
    return nil
  end
  return PN.Clean(name) == name and name or nil
end
