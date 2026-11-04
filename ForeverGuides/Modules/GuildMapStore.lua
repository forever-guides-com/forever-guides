-- Positions of guild members received through the guild map function (GuildMapComm). Memory only:
-- nothing here is written to ns.db or ns.charDB, a reload starts empty. One entry per member
-- (map, x, y, time, mode), updated in place. An entry is current for GuildSyncLogic.CONFIG.store.fresh
-- seconds, older until store.old, then it is gone. The table is capped at store.positions entries,
-- the oldest one makes room. A withdrawal (X), leaving the guild, switching receiving off and
-- withdrawing the consent clear it. Nothing is stored without the receive consent.
-- Event FG_GUILDMAP_UPDATE (no arguments), debounced: something was added, changed, removed or expired.
local _, ns = ...
local PN, Consent, L, G = ns.PlayerName, ns.Consent, ns.GuildSyncLogic, ns.GuildSyncCodec

local S = {}
ns.GuildMapStore = S

-- Seconds between two cleanups while entries exist, and the debounce of the update event.
S.SWEEP = 15
S.DEBOUNCE = 1

local entries, count = {}, 0
local sweepArmed, depth = false, 0

local function clock()
  return ns.Comm.clock()
end

local function g(name)
  return rawget(_G, name)
end

local function whole(v, lo, hi)
  return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

local function allowed()
  return Consent.Allows("guildMap", "receive", "guild")
end

local function changed()
  ns.Debounce("guildmap-update", S.DEBOUNCE, function()
    ns.Emit("FG_GUILDMAP_UPDATE")
  end)
end

-- Yards between two records { map, x, y }, nil when the game cannot tell.
local function dist(a, b)
  local WL = ns.WaypointLogic
  return WL and WL.distanceYards(a.map, a.x, a.y, b.map, b.x, b.y) or nil
end

local function expired(entry, t)
  return L.PositionState(entry.at, t) == nil
end

local function removeOldest()
  local oldKey, oldAt
  for key, entry in pairs(entries) do
    if oldAt == nil or entry.at < oldAt then
      oldKey, oldAt = key, entry.at
    end
  end
  if oldKey then
    entries[oldKey], count = nil, count - 1
  end
end

-- Drops what has expired. Returns how many entries went.
function S.Sweep()
  local t, removed = clock(), 0
  for key, entry in pairs(entries) do
    if expired(entry, t) then
      entries[key], count = nil, count - 1
      removed = removed + 1
    end
  end
  if removed > 0 then
    changed()
  end
  return removed
end

local arm
arm = function()
  if sweepArmed or count == 0 then
    return
  end
  local timer = g("C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  sweepArmed = true
  local ok = pcall(timer.After, S.SWEEP, function()
    sweepArmed = false
    -- A client that runs the timer at once must not loop.
    depth = depth + 1
    if depth <= 2 then
      ns.Safe("guildmapstore", function()
        S.Sweep()
        arm()
      end)
    end
    depth = depth - 1
  end)
  if not ok then
    sweepArmed = false
  end
end

-- Stores the decoded position message `msg` ({ map, x, y in per mille, mode "point" or "zone" }) of
-- `name`. Returns true, or false and the reason (consent, args, range).
function S.Put(name, msg)
  if not allowed() then
    return false, "consent"
  end
  local key = type(name) == "string" and PN.Key(name) or ""
  if key == "" or type(msg) ~= "table" then
    return false, "args"
  end
  local zoneOnly = msg.mode == "zone"
  local max = G.LIMITS.MAX_PROMILLE
  if
    not whole(msg.map, 1, G.LIMITS.MAX_MAP)
    or (msg.mode ~= "point" and not zoneOnly)
    or (not zoneOnly and not (whole(msg.x, 0, max) and whole(msg.y, 0, max)))
  then
    return false, "range"
  end
  local t = clock()
  local cur =
    { map = msg.map, x = not zoneOnly and msg.x / 1000 or nil, y = not zoneOnly and msg.y / 1000 or nil, at = t }
  local entry = entries[key]
  if not entry then
    if count >= L.CONFIG.store.positions then
      S.Sweep()
    end
    if count >= L.CONFIG.store.positions then
      removeOldest()
    end
    entry = { key = key }
    entries[key], count = entry, count + 1
    entry.check = "zone"
  else
    entry.check = L.Plausible(entry, cur, dist)
  end
  entry.name, entry.map, entry.x, entry.y, entry.at = name, cur.map, cur.x, cur.y, t
  entry.mode = zoneOnly and "zone" or "point"
  changed()
  arm()
  return true
end

-- Removes one member (withdrawal). Returns whether there was an entry.
function S.Remove(name)
  local key = type(name) == "string" and PN.Key(name) or ""
  if entries[key] == nil then
    return false
  end
  entries[key], count = nil, count - 1
  changed()
  return true
end

-- Removes everything.
function S.Clear()
  if count == 0 then
    return
  end
  entries, count = {}, 0
  changed()
end

function S.Count()
  return count
end

-- A copy of an entry for the display: key, name, map, x and y (fractions 0..1, nil for zone only),
-- mode ("point" or "zone"), check ("ok", "zone" or "jump", for dimming only), at (clock seconds), age
-- (seconds) and state ("current" or "old").
local function view(entry, t)
  return {
    key = entry.key,
    name = entry.name,
    map = entry.map,
    x = entry.x,
    y = entry.y,
    mode = entry.mode,
    check = entry.check,
    at = entry.at,
    age = math.max(0, t - entry.at),
    state = L.PositionState(entry.at, t),
  }
end

-- Live entries (not expired) sorted by key, optionally of one map.
local function list(map)
  local t, out = clock(), {}
  for _, entry in pairs(entries) do
    if (map == nil or entry.map == map) and not expired(entry, t) then
      out[#out + 1] = view(entry, t)
    end
  end
  table.sort(out, function(a, b)
    return a.key < b.key
  end)
  return out
end

function S.All()
  return list(nil)
end

function S.ForMap(map)
  return list(map)
end

-- The entry of one member, nil when unknown or expired.
function S.Get(name)
  local key = type(name) == "string" and PN.Key(name) or ""
  local entry, t = entries[key], clock()
  if entry and not expired(entry, t) then
    return view(entry, t)
  end
end

local function inGuild()
  local fn = g("IsInGuild")
  if type(fn) ~= "function" then
    return false
  end
  local ok, value = pcall(fn)
  return ok and value == true
end

-- Leaving the guild, a login without one, switching receiving off, withdrawing the consent.
local function dropIfOut()
  if not inGuild() then
    S.Clear()
  end
end

ns.On("PLAYER_GUILD_UPDATE", dropIfOut)
ns.On("PLAYER_ENTERING_WORLD", dropIfOut)
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if fn == "guildMap" and dir == "receive" and aud == "guild" and value ~= true then
    S.Clear()
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == "guildMap" then
    S.Clear()
  end
end)
