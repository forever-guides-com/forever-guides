-- Positions of guild members (GuildMapComm) and of friends (FriendMapComm) received through the map functions. One entry
-- per person with the sources that reported it ("guild", "friends", "bnfriends"), so someone who is both shows once. Memory only:
-- nothing here is written to ns.db or ns.charDB, a reload starts empty. One entry per member
-- (map, x, y, time, mode), updated in place. An entry is current for GuildSyncLogic.CONFIG.store.fresh
-- seconds, older until store.old, then it is gone. The table is capped at store.positions entries,
-- the oldest one makes room. A withdrawal (X), leaving the guild, switching receiving off and
-- withdrawing the consent clear the source concerned. Nothing is stored without the receive consent of its source.
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

-- Source -> consent function and audience.
local SOURCES = {
  guild = { "guildMap", "guild" },
  friends = { "friendMap", "friends" },
  bnfriends = { "friendMap", "bnfriends" },
}

local function allowed(src)
  local s = SOURCES[src]
  return s ~= nil and Consent.Allows(s[1], "receive", s[2])
end

-- True while the source ("guild", "friends" or "bnfriends") may store.
function S.Allowed(src)
  return allowed(src)
end

-- True while any source may store: the world and add-on map draw only then.
function S.Receiving()
  return allowed("guild") or allowed("friends") or allowed("bnfriends")
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
-- `name` reported by `src` ("guild" by default, "friends" or "bnfriends"). Returns true, or false and the reason (consent, args, range).
function S.Put(name, msg, src)
  src = src or "guild"
  if not SOURCES[src] then
    return false, "args"
  end
  if not allowed(src) then
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
    or (msg.fx ~= nil and not whole(msg.fx, 0, 9))
    or (msg.fy ~= nil and not whole(msg.fy, 0, 9))
  then
    return false, "range"
  end
  local t = clock()
  local cur = { map = msg.map, at = t }
  if not zoneOnly then
    local fine = msg.fx ~= nil and msg.fy ~= nil
    cur.x = G.Fraction(msg.x, fine and msg.fx or nil)
    cur.y = G.Fraction(msg.y, fine and msg.fy or nil)
  end
  local entry = entries[key]
  if not entry then
    if count >= L.CONFIG.store.positions then
      S.Sweep()
    end
    if count >= L.CONFIG.store.positions then
      removeOldest()
    end
    entry = { key = key, srcs = {} }
    entries[key], count = entry, count + 1
    entry.check = "zone"
  else
    entry.check = L.Plausible(entry, cur, dist)
  end
  entry.name, entry.map, entry.x, entry.y, entry.at = name, cur.map, cur.x, cur.y, t
  entry.mode = zoneOnly and "zone" or "point"
  entry.srcs[src] = true
  changed()
  arm()
  return true
end

-- Drops one source from an entry; the entry goes with its last source.
local function release(key, entry, src)
  entry.srcs[src] = nil
  if next(entry.srcs) == nil then
    entries[key], count = nil, count - 1
  end
end

-- Removes what `src` (default "guild") reported of one person (withdrawal). Returns whether there was something.
function S.Remove(name, src)
  src = src or "guild"
  local key = type(name) == "string" and PN.Key(name) or ""
  local entry = entries[key]
  if entry == nil or not entry.srcs[src] then
    return false
  end
  release(key, entry, src)
  changed()
  return true
end

-- Removes what `src` reported, everything without it.
function S.Clear(src)
  if count == 0 then
    return
  end
  if src == nil then
    entries, count = {}, 0
  else
    for key, entry in pairs(entries) do
      if entry.srcs[src] then
        release(key, entry, src)
      end
    end
  end
  changed()
end

function S.Count()
  return count
end

-- A copy of an entry for the display: key, name, map, x and y (fractions 0..1, nil for zone only),
-- mode ("point" or "zone"), check ("ok", "zone" or "jump", for dimming only), at (clock seconds), age
-- (seconds), state ("current" or "old") and the sources (guild, friends, bnfriends: true when that source reported it).
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
    guild = entry.srcs.guild == true,
    friends = entry.srcs.friends == true,
    bnfriends = entry.srcs.bnfriends == true,
  }
end

-- Live entries (not expired) sorted by key, optionally of one map and of one source.
local function list(map, src)
  local t, out = clock(), {}
  for _, entry in pairs(entries) do
    if (map == nil or entry.map == map) and (src == nil or entry.srcs[src]) and not expired(entry, t) then
      out[#out + 1] = view(entry, t)
    end
  end
  table.sort(out, function(a, b)
    return a.key < b.key
  end)
  return out
end

function S.All(src)
  return list(nil, src)
end

function S.ForMap(map, src)
  return list(map, src)
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
    S.Clear("guild")
  end
end

ns.On("PLAYER_GUILD_UPDATE", dropIfOut)
ns.On("PLAYER_ENTERING_WORLD", dropIfOut)
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  local s = SOURCES[aud]
  if dir == "receive" and value ~= true and s and s[1] == fn then
    S.Clear(aud)
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  for src, s in pairs(SOURCES) do
    if s[1] == fn then
      S.Clear(src)
    end
  end
end)
