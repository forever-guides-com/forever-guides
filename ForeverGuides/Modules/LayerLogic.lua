-- Pure part of the layer display (Layer.lua, LayerLabel.lua, LayerWindow.lua): reading the layer id out of a creature GUID,
-- the state of the layer last seen with the rule that a layer only counts for the zone it was read in,
-- the read debounce and the texts. No game calls, so every shape of answer is testable.
local _, ns = ...

local M = {}
ns.LayerLogic = M

-- Seconds. Reads of the same source closer together than this are skipped (name plate events come in bursts).
M.READ_GAP = 0.25

-- Only these GUID kinds carry the server, instance and zone fields in this order.
local KINDS = { Creature = true, Vehicle = true }
local PATTERN = "^(%a+)%-%d+%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-(%x+)$"

-- Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID. zoneUID is the layer id. nil for anything else:
-- not a string, a player or item GUID, a missing or non-numeric field. The match runs in pcall because a
-- secret string value raises on string functions.
function M.ParseGUID(guid)
  if type(guid) ~= "string" then
    return nil
  end
  local ok, kind, server, instance, zone, npc, spawn = pcall(string.match, guid, PATTERN)
  if not (ok and kind and KINDS[kind]) then
    return nil
  end
  return {
    kind = kind,
    serverID = tonumber(server),
    instanceID = tonumber(instance),
    zoneUID = tonumber(zone),
    npcID = tonumber(npc),
    spawnUID = spawn,
  }
end

local function isLayerId(value)
  return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

-- State ------------------------------------------------------------------------------------------------

-- layer, mapId (the zone it was read in), at (clock of the last confirmation), source, previous (the layer
-- before the last change in the same zone), reads (clock of the last read per source).
function M.New()
  return { reads = {} }
end

-- The layer is unknown after a zone change: the next observation counts as a first one.
function M.Reset(state)
  state.layer, state.mapId, state.at, state.source, state.previous = nil, nil, nil, nil, nil
end

-- True when source may read again. A clock that went backwards counts as due.
function M.Due(state, source, now)
  local last = state.reads[source]
  if last and now >= last and now - last < M.READ_GAP then
    return false
  end
  state.reads[source] = now
  return true
end

-- One layer seen at time now in the zone mapId from source. Returns "first" (no layer yet or another zone,
-- the old layer is dropped), "changed" (another layer in the same zone, then the old layer as second value),
-- "same" (confirmed again) or nil for a value that is no layer id.
function M.Observe(state, layer, mapId, now, source)
  if not (isLayerId(layer) and type(now) == "number") then
    return nil
  end
  local result, old = "same", nil
  if state.layer == nil or state.mapId ~= mapId then
    result, state.previous = "first", nil
  elseif state.layer ~= layer then
    result, old = "changed", state.layer
    state.previous = old
  end
  state.layer, state.mapId, state.at, state.source = layer, mapId, now, source
  return result, old
end

-- A layer id of another zone says nothing about this one.
function M.Valid(state, mapId)
  return state.layer ~= nil and state.mapId == mapId
end

-- UIMapType of a zone; dungeon, micro and orphan maps (caves, buildings) have higher values.
M.ZONE_MAP_TYPE = 3
local MAX_CLIMB = 8

-- The zone-level map of a map id. info(id) answers { mapType, parentMapID } or nil. Layers belong to a zone,
-- so a cave or building inside it must not look like another place. An unknown map stays as it is.
function M.ZoneOf(id, info)
  if type(id) ~= "number" or type(info) ~= "function" then
    return id
  end
  for _ = 1, MAX_CLIMB do
    local map = info(id)
    if type(map) ~= "table" or type(map.mapType) ~= "number" or map.mapType <= M.ZONE_MAP_TYPE then
      return id
    end
    local parent = map.parentMapID
    if type(parent) ~= "number" or parent == 0 then
      return id
    end
    id = parent
  end
  return id
end

-- Texts ------------------------------------------------------------------------------------------------

-- "Layer 4812", "Layer ?" without a layer for the zone mapId (nil is the unknown map). L is the locale table.
function M.Text(state, mapId, L)
  if not M.Valid(state, mapId) then
    return L["layer.unknown"]
  end
  return string.format(L["layer.label"], state.layer)
end

-- "12 s ago", "3 min ago", "2 h ago"; nil without a layer.
function M.Age(state, now, L)
  if state.layer == nil or type(state.at) ~= "number" or type(now) ~= "number" then
    return nil
  end
  local seconds = math.max(0, math.floor(now - state.at))
  if seconds < 60 then
    return string.format(L["layer.age.sec"], seconds)
  elseif seconds < 3600 then
    return string.format(L["layer.age.min"], math.floor(seconds / 60))
  end
  return string.format(L["layer.age.hour"], math.floor(seconds / 3600))
end

-- Entries of the layer window ---------------------------------------------------------------------------

-- Most rows the window takes; more entries are dropped.
M.MAX_ENTRIES = 100
M.MAX_NAME = 64

local function isCount(value)
  return type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

-- The name cut to MAX_NAME bytes without splitting a UTF-8 character.
local function clip(name)
  local cut = M.MAX_NAME
  if #name <= cut then
    return name
  end
  while cut > 0 and name:byte(cut + 1) >= 0x80 and name:byte(cut + 1) < 0xC0 do
    cut = cut - 1
  end
  return name:sub(1, cut)
end

-- The entries a caller hands to the window, cleaned: { name, class, layer, free, blocked, onClick }. blocked is
-- the text that says why the button cannot be used now (the button is then disabled). Entries without a
-- name are dropped, a field of the wrong type becomes nil. Pipes in the name are doubled so a name can never
-- carry a color or link code into the list.
function M.CleanEntries(list)
  local out = {}
  if type(list) ~= "table" then
    return out
  end
  for _, entry in ipairs(list) do
    if #out >= M.MAX_ENTRIES then
      break
    end
    if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
      out[#out + 1] = {
        name = (clip(entry.name):gsub("|", "||")),
        class = type(entry.class) == "string" and entry.class or nil,
        layer = isLayerId(entry.layer) and entry.layer or nil,
        free = isCount(entry.free) and entry.free or nil,
        blocked = type(entry.blocked) == "string" and entry.blocked ~= "" and (entry.blocked:gsub("|", "||")) or nil,
        onClick = type(entry.onClick) == "function" and entry.onClick or nil,
      }
    end
  end
  return out
end

-- "Layer 3", "Layer ?" for an entry without a layer.
function M.EntryLayerText(entry, L)
  return entry.layer and string.format(L["layer.label"], entry.layer) or L["layer.unknown"]
end

-- "2 free", empty when the entry does not say.
function M.EntryFreeText(entry, L)
  return entry.free and string.format(L["layer.win.free"], entry.free) or ""
end
