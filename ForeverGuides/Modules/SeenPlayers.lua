-- Recently seen players (the contacts): group and raid members, trade partners and (if switched on)
-- players you target, with class, level, place and what a visible unit tells passively. An entry
-- keeps its first contact (e.first = { t, src, zone }, e.src is the same source) unchanged; e.t and
-- e.zone are the time and place of the last sighting, which group scans and NearbyContacts refresh.
-- Stored only in ns.db.seenPlayers on this computer, at most ContactsLogic.MAX_SEEN entries, never sent
-- anywhere and never exported. Off with settings.seenSave. S.Find(guid) is the one table lookup that
-- tells a contact from a stranger.
local _, ns = ...
local CL, PN, L, Guard = ns.ContactsLogic, ns.PlayerName, ns.L, ns.AutoGuard

local S = {}
ns.SeenPlayers = S

local SCAN_DELAY = 2
local MAX_UNITS = 40
local index, guids, indexFor

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

function S.Enabled()
  return ns.db ~= nil and ns.db.settings.seenSave ~= false
end

function S.Targets()
  return ns.db ~= nil and ns.db.settings.seenTargets == true
end

-- The stored list, cleaned once per list object.
function S.List()
  if type(ns.db.seenPlayers) ~= "table" then
    ns.db.seenPlayers = {}
  end
  local list = ns.db.seenPlayers
  if indexFor ~= list then
    CL.CleanSeen(list)
    index, guids, indexFor = CL.SeenIndex(list), CL.SeenGuidIndex(list), list
  end
  return list
end

-- Adds or refreshes a player of the list (name, guid, class, level, zone, race, src ...), see
-- ContactsLogic.SeenAdd. Returns the entry.
function S.Add(info, now)
  local list = S.List()
  return CL.SeenAdd(list, index, info, now or ns.U.now(), guids)
end

-- The contact with this GUID in one table lookup, nil for a stranger (or an entry stored without a GUID).
function S.Find(guid)
  if type(guid) ~= "string" then
    return nil
  end
  S.List()
  return guids[guid]
end

function S.FindName(name)
  S.List()
  return index[PN.Key(name)]
end

-- A known contact seen as a visible unit: time and place of the sighting and the current values are
-- refreshed, the first contact and the source stay.
function S.Touch(e, unit)
  local info = S.ReadUnit(unit)
  info.zone = try(g("GetRealZoneText"))
  CL.SeenUpdate(e, info, ns.U.now())
  ns.Emit("FG_SEEN_UPDATE")
  return info
end

function S.Count()
  return #S.List()
end

-- try() plus the secret-value check: nil for a value the add-on may not read.
local function safe(fn, ...)
  return Guard.Safe(try(fn, ...))
end

-- A string, "" for any other answer (also a secret one).
local function str(v)
  v = Guard.Safe(v)
  return type(v) == "string" and v or ""
end

-- Passive facts of a visible unit, the same data the game shows in its tooltip. Every call is
-- protected, a function the client lacks answers nothing. Fields that are nil are unknown: the guild
-- fields are "" for a player without a guild or title (a reading), pvp is a boolean.
function S.ReadUnit(unit)
  local facts = {}
  local okClass, _, class = pcall(g("UnitClass"), unit)
  facts.class = okClass and str(class) or ""
  local _, raceName, race = pcall(g("UnitRace"), unit)
  facts.race, facts.raceName = str(race), str(raceName)
  facts.level = tonumber(safe(g("UnitLevel"), unit))
  facts.guid = safe(g("UnitGUID"), unit)
  if type(g("GetGuildInfo")) == "function" then
    local ok, guildName, guildRank = pcall(g("GetGuildInfo"), unit)
    if ok then
      facts.guildName, facts.guildRank = str(guildName), str(guildRank)
    end
  end
  local pvpName = safe(g("UnitPVPName"), unit)
  if type(pvpName) == "string" then
    local first = Guard.Safe(try(g("UnitName"), unit))
    facts.title = CL.TitleOf(pvpName, PN.Display(unit), first)
  end
  local pvp = safe(g("UnitIsPVP"), unit)
  if type(pvp) == "boolean" then
    facts.pvp = pvp
  end
  facts.honor = tonumber(safe(g("UnitHonorLevel"), unit))
  return facts
end

-- Players only, never yourself.
local function record(unit, src)
  if try(g("UnitIsPlayer"), unit) ~= true then
    return false
  end
  local name = Guard.Safe(PN.Display(unit))
  if type(name) ~= "string" or PN.Equal(name, PN.Self()) then
    return false
  end
  if (src == "group" or src == "raid" or src == "dungeon") and try(g("UnitIsInMyGuild"), unit) == true then
    src = "guild"
  end
  local info = S.ReadUnit(unit)
  info.name, info.zone, info.src = name, try(g("GetRealZoneText")), src
  S.Add(info)
  return true
end

-- Live values of a current group member, read from the unit and never stored: zone, role, afk,
-- range ("in" or "out"), online (false when disconnected). nil for anybody who is not in the group.
function S.Live(guid, name)
  local members = tonumber(try(g("GetNumGroupMembers"))) or 0
  if members < 2 then
    return nil
  end
  local raid = try(g("IsInRaid")) == true
  local prefix, last = raid and "raid" or "party", raid and members or members - 1
  for i = 1, math.min(last, MAX_UNITS) do
    local unit = prefix .. i
    local theirs = safe(g("UnitGUID"), unit)
    local same = type(guid) == "string" and theirs == guid
    if not same and not (type(guid) == "string" and type(theirs) == "string") then
      local their = Guard.Safe(PN.Display(unit))
      same = type(their) == "string" and PN.Equal(their, name)
    end
    if same then
      local live = {}
      if safe(g("UnitIsConnected"), unit) == false then
        live.online = false
      end
      if safe(g("UnitIsAFK"), unit) == true then
        live.afk = true
      end
      local role = safe(g("UnitGroupRolesAssigned"), unit)
      if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        live.role = role
      end
      local okRange, inRange, checked = pcall(g("UnitInRange"), unit)
      if okRange and Guard.Safe(checked) == true then
        live.range = Guard.Safe(inRange) == true and "in" or "out"
      end
      local zone
      if raid then
        local okRoster, _, _, _, _, _, _, rosterZone = pcall(g("GetRaidRosterInfo"), i)
        zone = okRoster and str(rosterZone) or ""
      else
        local map = g("C_Map")
        local mapId = type(map) == "table" and safe(map.GetBestMapForUnit, unit)
        local mapInfo = mapId and safe(map.GetMapInfo, mapId)
        zone = type(mapInfo) == "table" and str(mapInfo.name) or ""
      end
      live.zone = zone ~= "" and zone or nil
      return live
    end
  end
  return nil
end

function S.ScanGroup()
  if not S.Enabled() then
    return
  end
  local members = tonumber(try(g("GetNumGroupMembers"))) or 0
  if members < 2 then
    return
  end
  local raid = try(g("IsInRaid")) == true
  local _, _, instanceType = pcall(g("IsInInstance"))
  local src = raid and "raid" or (instanceType == "party" and "dungeon" or "group")
  local prefix, last = raid and "raid" or "party", raid and members or members - 1
  for i = 1, math.min(last, MAX_UNITS) do
    record(prefix .. i, src)
  end
  ns.Emit("FG_SEEN_UPDATE")
end

function S.RecordTarget()
  if S.Enabled() and S.Targets() and record("target", "target") then
    ns.Emit("FG_SEEN_UPDATE")
  end
end

function S.Clear()
  local list = S.List()
  ns.Peers.Clear()
  for i = #list, 1, -1 do
    list[i] = nil
  end
  index, guids = {}, {}
  ns.Emit("FG_SEEN_UPDATE")
end

-- Asks first, then deletes everything.
function S.ConfirmClear(after)
  ns.Dialogs.Confirm("guild.set.clearTitle", "guild.set.clearText", function()
    S.Clear()
    ns.Notify(L["guild.set.cleared"], "success")
    if after then
      after()
    end
  end)
end

ns.On("GROUP_ROSTER_UPDATE", function()
  if S.Enabled() then
    ns.Debounce("seen-group", SCAN_DELAY, S.ScanGroup)
  end
end)
ns.On("PLAYER_TARGET_CHANGED", function()
  S.RecordTarget()
end)

-- Trade partner: the "npc" unit during a trade, else the name in the trade window.
function S.RecordTrade()
  if not S.Enabled() then
    return
  end
  local done = record("npc", "trade")
  if not done then
    local label = rawget(_G, "TradeFrameRecipientNameText")
    local ok, name = pcall(function()
      return label:GetText()
    end)
    name = ok and type(name) == "string" and PN.Clean(name) or ""
    if name ~= "" and not PN.Equal(name, PN.Self()) then
      S.Add({ name = name, zone = try(g("GetRealZoneText")), src = "trade" })
      done = true
    end
  end
  if done then
    ns.Emit("FG_SEEN_UPDATE")
  end
end

ns.On("TRADE_SHOW", S.RecordTrade)
ns.On("TRADE_ACCEPT_UPDATE", S.RecordTrade)
