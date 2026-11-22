-- Friends that are online right now, read from the game: the character friends list and the Battle.net friends
-- who play this game on the same faction. Memory only, nothing is sent or saved. Feeds FriendMapComm (who may be
-- written to and believed), the world map pins (class, level, the zone a friend stands in) and Comm (which
-- character a Battle.net game account id belongs to).
-- Event FG_FRIENDS_UPDATE (no arguments) after every scan, FG_FRIEND_ONLINE(key) for each friend that came online.
local _, ns = ...
local PN = ns.PlayerName

local R = {}
ns.FriendRoster = R

-- Most friends read per list, and the delay that merges a burst of game events into one scan.
R.MAX = 200
R.DELAY = 1

-- key -> { key, name, whisper, bn, class, level, area }; byAccount: game account id -> key.
local online, byAccount = {}, {}
local seen = false

local function g(name)
  return rawget(_G, name)
end

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
  return nil
end

-- A value the client hides (secret values) reads as nil.
local function safe(v)
  local guard = ns.AutoGuard
  if guard then
    return guard.Safe(v)
  end
  return v
end

local function text(v)
  v = safe(v)
  return type(v) == "string" and v ~= "" and #v <= 64 and v or nil
end

local function number(v)
  v = safe(v)
  return type(v) == "number" and v == v and v >= 0 and v < math.huge and v or 0
end

-- Class file name (MAGE) from the guid, else from the localized class name the friends list gives.
local byLocalName
local function classOf(className, guid)
  local known = ns.GuildKit and ns.GuildKit.KNOWN_CLASS or {}
  guid = text(guid)
  if guid then
    local _, file = call(g("GetPlayerInfoByGUID"), guid)
    if type(file) == "string" and known[file] then
      return file
    end
  end
  className = text(className)
  if not className then
    return ""
  end
  if not byLocalName then
    byLocalName = {}
    for _, list in ipairs({ g("LOCALIZED_CLASS_NAMES_MALE"), g("LOCALIZED_CLASS_NAMES_FEMALE") }) do
      for file, name in pairs(type(list) == "table" and list or {}) do
        byLocalName[name] = file
      end
    end
  end
  local file = byLocalName[className]
  return known[file] and file or ""
end

local function add(out, entry)
  entry.key = PN.Key(entry.name)
  if entry.key == "" or PN.Equal(entry.name, PN.Self()) then
    return
  end
  local old = out[entry.key]
  if old then
    -- Both lists know the friend: keep every way to reach it.
    old.whisper, old.bn = old.whisper or entry.whisper, old.bn or entry.bn
    return
  end
  out[entry.key] = entry
end

local function characterFriends(out)
  local api = g("C_FriendList")
  if type(api) ~= "table" then
    return
  end
  local n = math.min(R.MAX, number(call(api.GetNumFriends)))
  for i = 1, n do
    local f = call(api.GetFriendInfoByIndex, i)
    local name = type(f) == "table" and safe(f.connected) == true and text(f.name)
    if name then
      add(out, {
        name = name,
        whisper = name,
        class = classOf(f.className, f.guid),
        level = number(f.level),
        area = text(f.area) or "",
      })
    end
  end
end

-- Battle.net reaches across realms and factions in the game itself; a position of the other faction means nothing
-- on this map, so only the own faction counts.
local function sameFaction(info)
  local mine, mineLocal = call(g("UnitFactionGroup"), "player")
  local theirs = text(info.factionName)
  return theirs ~= nil and (theirs == mine or theirs == mineLocal)
end

local function battleNetFriends(out, accounts)
  local api = g("C_BattleNet")
  if type(g("BNGetNumFriends")) ~= "function" or type(api) ~= "table" then
    return
  end
  local n = math.min(R.MAX, number(call(g("BNGetNumFriends"))))
  for i = 1, n do
    local a = call(api.GetFriendAccountInfo, i)
    local info = type(a) == "table" and a.gameAccountInfo
    if
      type(info) == "table"
      and safe(info.isOnline) == true
      and safe(info.clientProgram) == (g("BNET_CLIENT_WOW") or "WoW")
      and (g("WOW_PROJECT_ID") == nil or safe(info.wowProjectID) == g("WOW_PROJECT_ID"))
      and sameFaction(info)
    then
      local name, realm, id = text(info.characterName), text(info.realmName), safe(info.gameAccountID)
      if name and type(id) == "number" then
        add(out, {
          name = realm and (name .. "-" .. realm) or name,
          bn = id,
          class = classOf(info.className, info.playerGuid),
          level = number(info.characterLevel),
          area = text(info.areaName) or "",
        })
        accounts[id] = PN.Key(realm and (name .. "-" .. realm) or name)
      end
    end
  end
end

-- Reads both lists. Returns the keys that were not online before.
function R.Scan()
  local out, accounts, came = {}, {}, {}
  characterFriends(out)
  battleNetFriends(out, accounts)
  for key in pairs(out) do
    if not online[key] then
      came[#came + 1] = key
    end
  end
  online, byAccount = out, accounts
  seen = true
  table.sort(came)
  ns.Emit("FG_FRIENDS_UPDATE")
  for _, key in ipairs(came) do
    ns.Emit("FG_FRIEND_ONLINE", key)
  end
  return came
end

-- Queries ----------------------------------------------------------------------------------------------

-- True for a character on the friends list that is online (character name or Battle.net character).
function R.IsFriend(name)
  return type(name) == "string" and online[PN.Key(name)] ~= nil
end

-- True when the list of the route holds the online friend: "whisper" the character friends, "bnet" Battle.net.
function R.InList(name, kind)
  local f = R.Get(name)
  if not f then
    return false
  end
  if kind == "bnet" then
    return f.bn ~= nil
  end
  return kind == "whisper" and f.whisper ~= nil
end

function R.Get(name)
  return type(name) == "string" and online[PN.Key(name)] or nil
end

-- The friend behind a Battle.net game account id, as a normalized character name.
function R.NameOfGameAccount(id)
  local key = byAccount[id]
  return key and online[key] and online[key].name or nil
end

-- Online friends sorted by key.
function R.List()
  local out = {}
  for _, f in pairs(online) do
    out[#out + 1] = f
  end
  table.sort(out, function(a, b)
    return a.key < b.key
  end)
  return out
end

-- The friends as rows of the guild list shape (key, name, class, level, rank, zone, online), so the map pins
-- color and filter them like members. A friend has no rank.
function R.Members()
  local out = {}
  for i, f in ipairs(R.List()) do
    out[i] = {
      key = f.key,
      name = f.name,
      class = f.class,
      className = "",
      level = f.level,
      rank = -1,
      rankName = "",
      zone = f.area,
      online = true,
    }
  end
  return out
end

-- Zone name -> the map of the zone. The index is built once the client lists maps; a name shared by several maps
-- takes the one ranked as a zone. A name that only a dungeon or a micro map carries is no zone (instances).
local zoneByName, zoneRank
local MAX_ZONE_RANK = 2
local function zoneMap(area)
  if area == "" then
    return nil
  end
  if not zoneByName then
    local wp = ns.Waypoints
    local list = wp and wp.ZoneIndex and call(wp.ZoneIndex) or {}
    if #list == 0 then
      return nil
    end
    zoneByName, zoneRank = {}, {}
    for _, z in ipairs(list) do
      if zoneByName[z.name] == nil or z.rank < zoneRank[z.name] then
        zoneByName[z.name], zoneRank[z.name] = z.id, z.rank
      end
    end
  end
  local map = zoneByName[area]
  return map and zoneRank[area] <= MAX_ZONE_RANK and map or nil
end
R.ZoneMap = zoneMap

-- Friends with the map of the zone they stand in as the friends list tells it, those the map does not know left out.
function R.ZonePlaces()
  local out = {}
  for _, f in ipairs(R.List()) do
    local map = zoneMap(f.area)
    if map then
      out[#out + 1] = { key = f.key, name = f.name, class = f.class, level = f.level, zone = f.area, map = map }
    end
  end
  return out
end

-- True once a scan ran.
function R.Ready()
  return seen
end

local function queue()
  ns.Debounce("friends-scan", R.DELAY, R.Scan)
end

ns.On("PLAYER_LOGIN", queue)
ns.On("PLAYER_ENTERING_WORLD", queue)
ns.On("FRIENDLIST_UPDATE", queue)
ns.On("BN_FRIEND_INFO_CHANGED", queue)
ns.On("BN_FRIEND_ACCOUNT_ONLINE", queue)
ns.On("BN_FRIEND_ACCOUNT_OFFLINE", queue)
