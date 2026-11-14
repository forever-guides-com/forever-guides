-- Forever Chat, the class of a writer: from the GUID of the chat event (GetPlayerInfoByGUID), else from the group, else
-- from what was seen before in this session. Every answer of the game goes through pcall and the secret value guard;
-- an unknown class stays nil and the name keeps its plain color. The rules are ChatClassLogic.lua.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local CL, PN = chat.ClassLogic, FG.PlayerName

local Class = {}
chat.Class = Class

local cache = CL.NewCache()

local function global(name)
  return rawget(_G, name)
end

local function safe(value)
  local guard = FG.AutoGuard
  if guard and guard.Safe then
    return guard.Safe(value)
  end
  return value
end

local function known()
  return FG.GuildKit and FG.GuildKit.KNOWN_CLASS or {}
end

-- The values of a game function (pcall, secret values dropped), nil for a missing function or an error.
local function ask(name, ...)
  local fn = global(name)
  if type(fn) ~= "function" then
    return nil
  end
  local out = { pcall(fn, ...) }
  if not out[1] then
    return nil
  end
  -- A hole from a nil value is fine: the callers read single positions.
  for i = 2, 8 do
    out[i] = safe(out[i])
  end
  return unpack(out, 2, 8)
end

-- The class token of a player GUID, nil when the game does not know it.
function Class.FromGuid(guid)
  guid = safe(guid)
  if type(guid) ~= "string" or guid == "" then
    return nil
  end
  local _, token = ask("GetPlayerInfoByGUID", guid)
  return CL.Token(token, known())
end

local function unitClass(unit, key)
  local name, realm = ask("UnitName", unit)
  if type(name) ~= "string" then
    return nil
  end
  if PN.Key(name) ~= key and not (type(realm) == "string" and realm ~= "" and PN.Key(name .. "-" .. realm) == key) then
    return nil
  end
  local _, token = ask("UnitClass", unit)
  return CL.Token(token, known())
end

-- The class of a player in the own group (or the player), nil when the name is not there.
function Class.FromGroup(name)
  local key = PN.Key(name)
  if key == "" then
    return nil
  end
  local own = unitClass("player", key)
  if own then
    return own
  end
  if ask("IsInGroup") ~= true then
    return nil
  end
  local raid = ask("IsInRaid") == true
  local count = tonumber(ask("GetNumGroupMembers")) or 0
  for i = 1, math.min(count, 40) do
    local class = unitClass((raid and "raid" or "party") .. i, key)
    if class then
      return class
    end
  end
  return nil
end

-- The class seen for a name in this session, nil when none.
function Class.Cached(name)
  return type(name) == "string" and CL.Lookup(cache, PN.Key(name)) or nil
end

-- The display names seen with a class, for the name completion of the forward dialog.
local seen = {}

local version = 0

-- Counts the changes of what is known, for the caches of the windows that depend on it.
function Class.Version()
  return version
end

function Class.Remember(name, class)
  if type(name) == "string" and CL.Token(class, known()) then
    local key = PN.Key(name)
    if CL.Lookup(cache, key) ~= class then
      version = version + 1
    end
    CL.Remember(cache, key, class)
    seen[PN.Key(name)] = name
  end
end

-- Names seen in this session that start with the prefix (case does not matter), at most 8, sorted.
function Class.Names(prefix)
  local out = {}
  local want = type(prefix) == "string" and prefix:lower() or ""
  if want == "" then
    return out
  end
  for _, name in pairs(seen) do
    if name:lower():sub(1, #want) == want then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  while #out > 8 do
    table.remove(out)
  end
  return out
end

-- The class of the writer of a line: what was seen before, else the GUID, else the group. The answer is kept.
function Class.Of(name, guid)
  name = safe(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local class = Class.Cached(name) or Class.FromGuid(guid) or Class.FromGroup(name)
  if class then
    Class.Remember(name, class)
  end
  return class
end

function Class.Clear()
  version = version + 1
  seen = {}
  cache = CL.NewCache()
end
