-- Per-character scope of HUD windows and the mouse cursor ring (ns.CharScopeLogic), without WoW API: the key of a
-- character, the register of the characters of the account, the layout and the on/off switch a character may
-- override, and the start value of "shown" for a window a character has no entry for yet.
--
-- Storage: ns.db.characters[key] = { name, realm, class, seen } with key = "Name-Realm" (account wide, at most
-- MAX_CHARACTERS entries). The ring overrides sit in the character store: ForeverGuidesCharDB.cursorRing =
-- { layoutId, enabled }. A field that is missing means "like the account"; the layout library stays account
-- wide. Everything is additive: an older add-on ignores the new fields. A HUD window has no layout override
-- (a layout is the window); an old ForeverGuidesCharDB.areas[id].layoutId stays in the data and is not read.
local _, ns = ...

local CS = {
  MAX_CHARACTERS = 60,
  MAX_KEY = 80,
  MAX_PART = 40,
}
ns.CharScopeLogic = CS

local function plain(v, max)
  if type(v) ~= "string" then
    return nil
  end
  v = v:match("^%s*(.-)%s*$")
  if v == "" or #v > max or v:find("%c") then
    return nil
  end
  return v
end

-- Register ---------------------------------------------------------------------------------------------------

-- The realm as it goes into a key: no spaces and no hyphens, so GetRealmName ("Forever WoW") and the realm of
-- UnitFullName ("ForeverWoW") give the same key. nil when nothing is left.
function CS.CleanRealm(realm)
  local clean = plain(realm, CS.MAX_PART)
  clean = clean and clean:gsub(" ", ""):gsub("%-", "") or nil
  return clean ~= "" and clean or nil
end

-- A key as the register and the "when active" lists accept it.
function CS.ValidKey(key)
  return type(key) == "string" and plain(key, CS.MAX_KEY) == key and key:find("%-") ~= nil
end

-- "Name-Realm" of a character; `fallbackRealm` serves when the first realm is missing or empty (UnitFullName
-- leaves it out for a character of the own realm). nil when the name or the realm is not usable.
function CS.Key(name, realm, fallbackRealm)
  local clean = plain(name, CS.MAX_PART)
  local home = CS.CleanRealm(realm) or CS.CleanRealm(fallbackRealm)
  if clean and home and not clean:find("%-") then
    local key = clean .. "-" .. home
    return CS.ValidKey(key) and key or nil
  end
end

-- The entry of a character for the register, every field plain text or nil; nil without a usable key.
local function entryOf(info, key, now)
  info = type(info) == "table" and info or {}
  local class = plain(info.class, 20)
  return {
    name = plain(info.name, CS.MAX_PART) or key:match("^(.-)%-"),
    realm = plain(info.realm, CS.MAX_PART) or key:match("%-(.-)$"),
    class = class and class:find("^[%u_]+$") and class or nil,
    seen = type(now) == "number" and now == now and now or 0,
  }
end

-- Writes or refreshes the entry of `key` in the register `chars` (edited in place) and keeps at most `max`
-- entries: the oldest go first (by `seen`, then by key), the character being refreshed never. Entries that are
-- not a table or have no usable key leave. Returns the number of entries that were removed.
function CS.Touch(chars, key, info, now, max)
  if type(chars) ~= "table" or not CS.ValidKey(key) then
    return 0
  end
  max = type(max) == "number" and max >= 1 and math.floor(max) or CS.MAX_CHARACTERS
  local removed = 0
  for k, v in pairs(chars) do
    if type(v) ~= "table" or not CS.ValidKey(k) then
      chars[k] = nil
      removed = removed + 1
    end
  end
  chars[key] = entryOf(info, key, now)
  local keys = {}
  for k in pairs(chars) do
    if k ~= key then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys, function(a, b)
    local x, y = tonumber(chars[a].seen) or 0, tonumber(chars[b].seen) or 0
    if x ~= y then
      return x < y
    end
    return a < b
  end)
  local excess = #keys + 1 - max
  for i = 1, excess do
    chars[keys[i]] = nil
    removed = removed + 1
  end
  return removed
end

-- The text a character shows under in a list: "Name (Realm)", the key when the entry has no parts.
function CS.Label(key, entry)
  entry = type(entry) == "table" and entry or {}
  local name, realm = plain(entry.name, CS.MAX_PART), plain(entry.realm, CS.MAX_PART)
  if name and realm then
    return name .. " (" .. realm .. ")"
  end
  return key
end

-- The characters a list of the panel shows: { { key, label, class, current, known } }. The current character
-- comes first (it is listed even when the register does not hold it yet), then the other known ones by label,
-- then the keys of `picked` that nobody knows (known = false), by key, so an id of a character that is gone
-- stays visible and can be unticked.
function CS.List(chars, currentKey, picked)
  chars = type(chars) == "table" and chars or {}
  local out, seen = {}, {}
  if CS.ValidKey(currentKey) then
    local entry = type(chars[currentKey]) == "table" and chars[currentKey] or nil
    out[1] = {
      key = currentKey,
      label = CS.Label(currentKey, entry),
      class = entry and entry.class or nil,
      current = true,
      known = true,
    }
    seen[currentKey] = true
  end
  local others = {}
  for key, entry in pairs(chars) do
    if not seen[key] and type(entry) == "table" and CS.ValidKey(key) then
      seen[key] = true
      others[#others + 1] = { key = key, label = CS.Label(key, entry), class = entry.class, known = true }
    end
  end
  table.sort(others, function(a, b)
    local x, y = a.label:lower(), b.label:lower()
    if x ~= y then
      return x < y
    end
    return a.key < b.key
  end)
  for _, item in ipairs(others) do
    out[#out + 1] = item
  end
  local gone = {}
  for _, key in ipairs(type(picked) == "table" and picked or {}) do
    if type(key) == "string" and not seen[key] then
      seen[key] = true
      gone[#gone + 1] = { key = key, label = key, known = false }
    end
  end
  table.sort(gone, function(a, b)
    return a.key < b.key
  end)
  for _, item in ipairs(gone) do
    out[#out + 1] = item
  end
  return out
end

-- Overrides ------------------------------------------------------------------------------------------------------

-- The layout a display shows: the override of this character when it names a layout that exists, else the
-- account's. Returns the id (nil when neither names an existing layout), where it comes from ("char" or
-- "account"; nil without an id) and whether an override exists that points at a layout that is gone (the
-- player is told, the account value applies). `has(id)` tells whether a layout exists.
function CS.Layout(accountId, overrideId, has)
  local function exists(id)
    return type(id) == "string" and id ~= "" and has(id) == true
  end
  if exists(overrideId) then
    return overrideId, "char", false
  end
  local stale = type(overrideId) == "string" and overrideId ~= ""
  if exists(accountId) then
    return accountId, "account", stale
  end
  return nil, nil, stale
end

-- An override of the on/off switch as stored: true, false or nil (like the account).
function CS.CleanEnabled(v)
  if type(v) == "boolean" then
    return v
  end
end

-- Whether the ring is on for this character and where the answer comes from ("char" or "account").
function CS.Enabled(accountEnabled, override)
  override = CS.CleanEnabled(override)
  if override ~= nil then
    return override, "char"
  end
  return accountEnabled == true, "account"
end

-- Start value of `shown` for a window this character has no entry for yet: the field `startShown` of the window
-- (`item`, optional; a window made from a leftover layout starts hidden everywhere), else the account setting
-- `newCharShown` of the windows node, on unless it is false.
function CS.StartShown(node, item)
  if type(item) == "table" and type(item.startShown) == "boolean" then
    return item.startShown
  end
  return type(node) ~= "table" or node.newCharShown ~= false
end

-- Gives a window entry of this character that holds nothing yet its start value of `shown`; an entry with any
-- field (a position, a scale, a choice) is a character that already knows the window and stays as it is.
-- Edits `entry` in place, returns whether it did.
function CS.SeedShown(entry, node, item)
  if type(entry) == "table" and next(entry) == nil then
    entry.shown = CS.StartShown(node, item)
    return true
  end
  return false
end
