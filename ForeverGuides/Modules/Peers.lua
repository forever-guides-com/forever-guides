-- What is known about other players beyond the guild roster: item level, professions, race, with
-- the time and the source. Stored in ns.db.peers[guid or name key] on this computer only, at most
-- GuildLogic.MAX_PEERS entries. Sources: own characters (read from CharRoster, never copied),
-- the inspect window and group inspect (item level only) and data from other players with this
-- add-on (PeerComm.lua).
local _, ns = ...
local GL, PN, U = ns.GuildLogic, ns.PlayerName, ns.U

local P = {}
ns.Peers = P

local INSPECT_TRIES = 20
local MAX_ILVL = 2000
local byName, indexFor
local pending = 0

local function key(info)
  return type(info.guid) == "string" and info.guid ~= "" and info.guid or PN.Key(info.name or "")
end

local function list()
  if type(ns.db.peers) ~= "table" then
    ns.db.peers = {}
  end
  return ns.db.peers
end

-- name key -> entry, rebuilt when the stored table is another one.
local function names()
  local all = list()
  if indexFor ~= all then
    byName, indexFor = {}, all
    for _, e in pairs(all) do
      if type(e) == "table" and type(e.name) == "string" then
        byName[PN.Key(e.name)] = e
      end
    end
  end
  return byName
end

-- Own characters: the roster knows item level and, once another module stores them, professions.
local function ownEntry(name)
  local roster = ns.CharRoster
  for _, e in ipairs(roster and roster.List() or {}) do
    if PN.Equal(PN.Join(e.name, e.surname), name) then
      local ilvl = tonumber(e.ilvl)
      return {
        name = name,
        ilvl = ilvl and ilvl > 0 and ilvl or nil,
        professions = GL.CleanProfessions(e.professions),
        at = tonumber(e.seen),
        source = "game",
      }
    end
  end
end

-- Stored or own data of a player, nil when nothing is known. Do not write to the result.
function P.Get(name, guid)
  local all = list()
  local e = (type(guid) == "string" and all[guid]) or (name and names()[PN.Key(name)])
  if e then
    return e
  end
  return name and ownEntry(name) or nil
end

local function prune(all)
  local count, oldest, oldestAt = 0, nil, math.huge
  for k, e in pairs(all) do
    count = count + 1
    if type(e) ~= "table" or (tonumber(e.at) or 0) < oldestAt then
      oldest, oldestAt = k, type(e) == "table" and (tonumber(e.at) or 0) or -1
    end
  end
  if count > GL.MAX_PEERS and oldest then
    all[oldest] = nil
    indexFor = nil
  end
end

-- info: name (or guid), guid, ilvl, professions, race, source ("game", "inspect", "addon", "manual").
-- Fields that are nil keep their stored value. Returns the entry, nil for no name and no guid.
function P.Set(info)
  local k = key(info)
  if k == "" then
    return nil
  end
  local all = list()
  local e = all[k] or (info.name and names()[PN.Key(info.name)])
  if not e then
    e = {}
    all[k] = e
    indexFor = nil
  end
  if type(info.name) == "string" and info.name ~= "" then
    e.name = PN.Normalize(info.name)
  end
  local ilvl = tonumber(info.ilvl)
  if ilvl and ilvl > 0 and ilvl <= MAX_ILVL then
    e.ilvl = math.floor(ilvl + 0.5)
  end
  if type(info.professions) == "table" then
    e.professions = GL.CleanProfessions(info.professions)
  end
  if type(info.race) == "string" and info.race ~= "" then
    e.race = info.race
  end
  if GL.PEER_SOURCES[info.source] or not e.source then
    e.source = GL.PEER_SOURCES[info.source] and info.source or "game"
  end
  e.at = U.now()
  prune(all)
  return e
end

-- Data from another player with this add-on (already validated by PeerComm): payload is
-- { ilvl, professions = { { id, name, skill, max } } }. An empty profession list keeps what is stored.
function P.Receive(sender, payload)
  if type(sender) ~= "string" or sender == "" or type(payload) ~= "table" then
    return false
  end
  local jobs = type(payload.professions) == "table" and #payload.professions > 0 and payload.professions or nil
  return P.Set({ name = sender, ilvl = payload.ilvl, professions = jobs, source = "addon" }) ~= nil
end

function P.Clear()
  ns.db.peers = {}
  indexFor = nil
end

-- Inspect window: the item level of the inspected player, nothing else. Needs the saving switch.
-- Items arrive late from the client, so a few later item events try again; no timer of our own.
local function readInspect()
  if pending <= 0 then
    return
  end
  pending = pending - 1
  local seen, overlay = ns.SeenPlayers, ns.InspectOverlay
  if not (overlay and seen and seen.Enabled()) then
    return
  end
  local ok, unit = pcall(overlay.Unit)
  if not ok then
    return
  end
  local okCollect, facts = pcall(overlay.Collect, unit)
  local name = PN.Display(unit)
  if okCollect and type(facts) == "table" and facts.average and name and not PN.Equal(name, PN.Self()) then
    local okGuid, g = pcall(rawget(_G, "UnitGUID"), unit)
    P.Set({ name = name, guid = okGuid and g or nil, ilvl = facts.average, source = "game" })
    pending = 0
    ns.Emit("FG_SEEN_UPDATE")
  end
end

ns.On("INSPECT_READY", function(_, guid)
  -- GroupInspect asks on its own; that data belongs to the unit it asked for, not to the window.
  local group = ns.GroupInspect
  if group and group.Owns(guid) then
    return
  end
  pending = INSPECT_TRIES
  readInspect()
end)
ns.On("GET_ITEM_INFO_RECEIVED", readInspect)
