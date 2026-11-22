-- The realm of the logged-in character. The client can answer an empty string for both realm calls
-- (seen at login), which would leave every per-character key without a realm. Realm.Get() then falls
-- back to the realm of the last session that could read it, else to the one realm the roster knows for
-- this character. Nothing of the fallback is cached: the live value wins again as soon as it is readable.
local _, ns = ...

local Realm = {}
ns.Realm = Realm

local MAX_LEN = 80
local REFRESH_SECONDS = 3600

-- A plain, non-empty string, nil for anything else (secret values fail the pcall).
local function readable(v)
  if type(v) ~= "string" then
    return nil
  end
  local ok, out = pcall(function()
    if v == "" then
      return nil
    end
    return v:sub(1, MAX_LEN)
  end)
  return ok and out or nil
end

local function ask(name)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn)
  return ok and readable(value) or nil
end

local function now()
  local ok, t = pcall(function()
    return GetServerTime()
  end)
  return ok and type(t) == "number" and t or 0
end

-- The key form of a realm: no spaces and no hyphens (same rule as CharRoster.KeyFor).
local function flat(realm)
  return (realm:gsub(" ", ""):gsub("%-", ""))
end

-- Remembers the readable realm account-wide for sessions that cannot read it.
local function remember(realm)
  local db = ns.db
  if type(db) ~= "table" then
    return
  end
  local last = db.lastRealm
  local at = now()
  if type(last) == "table" and last.realm == realm and type(last.at) == "number" and at - last.at < REFRESH_SECONDS then
    return
  end
  db.lastRealm = { realm = realm, at = at }
end

-- The realm the client reports now, nil while it reports none.
function Realm.Live()
  local realm = ask("GetNormalizedRealmName") or ask("GetRealmName")
  if realm then
    remember(realm)
  end
  return realm
end

local function fullName()
  local ok, name, surname = pcall(UnitName, "player")
  name, surname = ok and readable(name), ok and readable(surname) or nil
  if not name then
    return nil
  end
  local R = ns.CharRoster
  return R and R.JoinName(name, surname) or name
end

-- The realms of the roster entries of this full name, as a list of the key form.
local function rosterRealms(full)
  local roster = type(ns.db) == "table" and ns.db.roster
  local out = {}
  if type(roster) ~= "table" then
    return out
  end
  local prefix = full .. "-"
  for key in pairs(roster) do
    if type(key) == "string" and key:sub(1, #prefix) == prefix and #key > #prefix then
      out[#out + 1] = key:sub(#prefix + 1)
    end
  end
  return out
end

-- The remembered realm, else the only realm of this character in the roster, else nil.
function Realm.Fallback()
  local full = fullName()
  if not full then
    return nil
  end
  local known = rosterRealms(full)
  local last = type(ns.db) == "table" and type(ns.db.lastRealm) == "table" and readable(ns.db.lastRealm.realm)
  if last then
    local key = flat(last)
    for _, r in ipairs(known) do
      if r == key then
        return last
      end
    end
    if #known == 0 then
      return last
    end
  end
  if #known == 1 then
    return known[1]
  end
end

-- The realm to build keys from: live, else the fallback, nil when neither knows.
function Realm.Get()
  return Realm.Live() or Realm.Fallback()
end
