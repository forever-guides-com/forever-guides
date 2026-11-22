-- Settings profiles, pure logic without WoW API. A profile is a named copy of the option keys of
-- ForeverGuidesDB.settings; the account keeps all profiles in ForeverGuidesDB.profiles, each character
-- picks one in ForeverGuidesCharDB.profile (absent = "Standard").
--
-- Storage model
--   ns.db.settings stays the one live table every module reads. It holds the keys of the ACTIVE profile and
--   the keys that never belong to a profile. Switching copies the stored profile into it (Apply), and the
--   live values go back into the stored profile before every switch, every copy or export and at logout
--   (Flush). So an existing account needs no conversion: its settings become the profile "Standard".
--   book = { v = 1, list = { [name] = { key = value, .. } }, working = name of the profile that lives in
--   ns.db.settings right now, accept = receiving profiles from other players (default false) }
--
-- In a profile (every top-level key of ForeverGuidesDB.settings except the list below, so a new option is
--   part of it without a change here): switches, scales, fonts, theme and skin, density, accessibility,
--   language, the options of the display modules, map and gathering options, selling and automation rules,
--   invite rules, logo and badge options, and the menu layout "nav" (hidden, moved and renamed entries).
-- Not in a profile (EXCLUDED), they stay as they are when a profile is applied, copied, imported or reset:
--   state and one-time flags   startHintSeen, skinDefault, saveHintDefault, instancesViewDefault, sellProtectSeeded, skinNotice,
--                              navCollapseDefault, navCollapsePrompt
--   window and layout state    sidebarCollapsed, sidebarOpen, mapTab, worldMapPanelOpen, worldMapPanelTab,
--                              instancesClosed, minimap (button angle), areas (HUD window positions), frames
--                              (saved positions and opacity of game windows), guildCols
--   own data and lists         instanceFavorites, shareWhisper (last whisper target), plateNamesSaved
--   install specific           subaddons (needs a reload and the folders), clientOverride
--   identity and history       chatName (own name in chat, may differ per character), chat (history
--                              recording and its limits)
--   sharing and privacy        peerShare, peerShareGuild, guildMapInvisible, guildMapAccuracy,
--                              presenceChatOnly, instanceResetAnnounce: a profile from another player must
--                              never switch a data exchange or an announcement on (consent: Core/Consent.lua)
-- Never in a profile either: ForeverGuidesDB outside settings (notes, waypoints, routes, history, guild data,
--   wishlist, caches, consent register, window frames) and ForeverGuidesCharDB (including a character's own
--   menu layout override).
local _, ns = ...

local PL = {
  VERSION = 1,
  KIND = "profile",
  DEFAULT = "Standard",
  MAX_NAME = 24,
  MAX_PROFILES = 30,
  -- Largest exchange string that goes into a chat link (the limit of NoteLink for transferred content).
  MAX_CODE = 20 * 1024,
  -- Largest inflated size of a received string.
  MAX_JSON = 262144,
  MAX_DEPTH = 6,
  MAX_NODES = 4000,
  MAX_STRING = 512,
  LETTER = "R",
}
ns.ProfileLogic = PL

PL.EXCLUDED = {
  startHintSeen = true,
  skinDefault = true,
  saveHintDefault = true,
  instancesViewDefault = true,
  sellProtectSeeded = true,
  skinNotice = true,
  navCollapseDefault = true,
  navCollapsePrompt = true,
  sidebarCollapsed = true,
  sidebarOpen = true,
  mapTab = true,
  worldMapPanelOpen = true,
  worldMapPanelTab = true,
  instancesClosed = true,
  minimap = true,
  areas = true,
  frames = true,
  guildCols = true,
  instanceFavorites = true,
  shareWhisper = true,
  plateNamesSaved = true,
  subaddons = true,
  clientOverride = true,
  chatName = true,
  chat = true,
  peerShare = true,
  peerShareGuild = true,
  guildMapInvisible = true,
  guildMapAccuracy = true,
  presenceChatOnly = true,
  instanceResetAnnounce = true,
}

-- Keys a profile may carry although Store.defaults has no entry for them (an absent key is the default).
PL.EXTRA = { nav = true, frameBarMode = true }

function PL.Included(key)
  return type(key) == "string" and not PL.EXCLUDED[key]
end

-- Copy ----------------------------------------------------------------------------------------------------------

local function copy(value, depth)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  if depth > 12 then
    return out
  end
  for k, v in pairs(value) do
    out[k] = copy(v, depth + 1)
  end
  return out
end

local function equal(a, b, depth)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" or depth > 12 then
    return false
  end
  for k, v in pairs(a) do
    if not equal(v, b[k], depth + 1) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function fill(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then
      target[k] = copy(v, 0)
    elseif type(v) == "table" and type(target[k]) == "table" then
      fill(target[k], v)
    end
  end
end

-- Profile data ------------------------------------------------------------------------------------------------

-- The profile keys of a settings table, as a deep copy.
function PL.Extract(settings)
  local out = {}
  for k, v in pairs(type(settings) == "table" and settings or {}) do
    if PL.Included(k) then
      out[k] = copy(v, 0)
    end
  end
  return out
end

-- The data of a fresh profile: the defaults of every profile key.
function PL.Defaults(defaults)
  return PL.Extract(defaults or (ns.Store and ns.Store.defaults.settings) or {})
end

-- Writes the profile `data` into the live table `settings`: profile keys the data does not have are removed,
-- missing ones come from `defaults` (default: Store.defaults.settings), keys outside a profile stay as they are.
-- A value that did not change keeps its table. Returns the list of the keys whose value changed.
function PL.Apply(settings, data, defaults)
  defaults = defaults or (ns.Store and ns.Store.defaults.settings) or {}
  local new = PL.Extract(data)
  fill(new, PL.Defaults(defaults))
  local changed, seen = {}, {}
  for k, v in pairs(new) do
    seen[k] = true
    if not equal(settings[k], v, 0) then
      settings[k] = v
      changed[#changed + 1] = k
    end
  end
  for k in pairs(settings) do
    if PL.Included(k) and not seen[k] then
      settings[k] = nil
      changed[#changed + 1] = k
    end
  end
  table.sort(changed)
  return changed
end

-- Number of keys of a profile, for the preview.
function PL.Count(data)
  local n = 0
  for _ in pairs(data or {}) do
    n = n + 1
  end
  return n
end

-- Names ---------------------------------------------------------------------------------------------------------

-- A name as typed: no escape codes or control characters, single spaces, at most MAX_NAME characters (UTF-8
-- aware). nil for an empty result.
function PL.CleanName(text)
  if type(text) ~= "string" then
    return nil
  end
  text = text:gsub("|", ""):gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  local count, i = 0, 1
  while i <= #text do
    if count == PL.MAX_NAME then
      text = text:sub(1, i - 1):gsub(" $", "")
      break
    end
    local c = text:byte(i)
    i = i + (c >= 240 and 4 or c >= 224 and 3 or c >= 192 and 2 or 1)
    count = count + 1
  end
  return text ~= "" and text or nil
end

-- Book ------------------------------------------------------------------------------------------------------------

function PL.NewBook(settings)
  return { v = PL.VERSION, list = { [PL.DEFAULT] = PL.Extract(settings) }, working = PL.DEFAULT, accept = false }
end

-- The stored name that equals `name` without regard to case, or nil.
function PL.Find(book, name)
  if type(name) ~= "string" then
    return nil
  end
  local lower = name:lower()
  for stored in pairs(book.list) do
    if stored:lower() == lower then
      return stored
    end
  end
end

-- Names, "Standard" first, the others sorted.
function PL.Names(book)
  local out = {}
  for name in pairs(book.list) do
    if name ~= PL.DEFAULT then
      out[#out + 1] = name
    end
  end
  table.sort(out, function(a, b)
    return a:lower() < b:lower()
  end)
  table.insert(out, 1, PL.DEFAULT)
  return out
end

function PL.Size(book)
  local n = 0
  for _ in pairs(book.list) do
    n = n + 1
  end
  return n
end

-- The text without its last character (UTF-8 aware).
local function dropLast(text)
  local n = #text
  while n > 0 and text:byte(n) >= 128 and text:byte(n) < 192 do
    n = n - 1
  end
  return text:sub(1, n - 1)
end

-- A name that is free: `name`, else "name (2)", "name (3)" ...
function PL.FreeName(book, name)
  name = PL.CleanName(name) or PL.DEFAULT
  if not PL.Find(book, name) then
    return name
  end
  local n = 2
  while true do
    local suffix = " (" .. n .. ")"
    -- The name gives way, never the number: cut whole characters until the result is a valid name.
    local base = name
    while base ~= "" and PL.CleanName(base .. suffix) ~= base .. suffix do
      base = dropLast(base)
    end
    local try = base .. suffix
    if not PL.Find(book, try) then
      return try
    end
    n = n + 1
  end
end

-- The usable book: a book from an older or damaged save becomes a valid one. `settings` feeds a missing
-- "Standard".
function PL.Repair(book, settings)
  if type(book) ~= "table" or type(book.list) ~= "table" then
    return PL.NewBook(settings)
  end
  for name, data in pairs(book.list) do
    if type(name) ~= "string" or PL.CleanName(name) ~= name or type(data) ~= "table" then
      book.list[name] = nil
    end
  end
  if book.list[PL.DEFAULT] == nil then
    book.list[PL.DEFAULT] = PL.Extract(settings)
  end
  if type(book.working) ~= "string" or book.list[book.working] == nil then
    book.working = PL.DEFAULT
  end
  book.v, book.accept = PL.VERSION, book.accept == true
  return book
end

-- Operations. Each returns the stored name (Create, Copy, Rename) or true, else nil and a reason: "name" (empty or
-- invalid), "exists", "limit", "missing", "default" (Standard cannot be renamed or deleted), "active".

function PL.Create(book, name, data)
  name = PL.CleanName(name)
  if not name then
    return nil, "name"
  elseif PL.Find(book, name) then
    return nil, "exists"
  elseif PL.Size(book) >= PL.MAX_PROFILES then
    return nil, "limit"
  end
  book.list[name] = data and PL.Extract(data) or PL.Defaults()
  return name
end

function PL.Copy(book, from, name)
  local source = PL.Find(book, from)
  if not source then
    return nil, "missing"
  end
  return PL.Create(book, name, book.list[source])
end

function PL.Rename(book, old, name)
  local stored = PL.Find(book, old)
  if not stored then
    return nil, "missing"
  elseif stored == PL.DEFAULT then
    return nil, "default"
  end
  name = PL.CleanName(name)
  if not name then
    return nil, "name"
  end
  local other = PL.Find(book, name)
  if other and other ~= stored then
    return nil, "exists"
  end
  book.list[name], book.list[stored] = book.list[stored], nil
  if book.working == stored then
    book.working = name
  end
  return name
end

-- `active` is the profile the caller uses right now; it cannot be deleted.
function PL.Delete(book, name, active)
  local stored = PL.Find(book, name)
  if not stored then
    return nil, "missing"
  elseif stored == PL.DEFAULT then
    return nil, "default"
  elseif stored == active then
    return nil, "active"
  end
  book.list[stored] = nil
  if book.working == stored then
    book.working = PL.DEFAULT
  end
  return true
end

function PL.Reset(book, name)
  local stored = PL.Find(book, name)
  if not stored then
    return nil, "missing"
  end
  book.list[stored] = PL.Defaults()
  return true
end

-- The profile a character uses: its stored choice when it still exists, else "Standard".
function PL.Resolve(book, wanted)
  return PL.Find(book, wanted) or PL.DEFAULT
end

-- Login. Creates the book on the first run (the live settings become "Standard"), keeps it consistent and
-- puts the profile of this character into the live settings. Returns the book, the active name and the keys
-- that changed.
function PL.Attach(account, char, defaults)
  local settings = account.settings
  local fresh = type(account.profiles) ~= "table"
  local book = PL.Repair(account.profiles, settings)
  if not fresh and book.list[book.working] then
    -- The live settings are the newest state of the profile that is in them.
    book.list[book.working] = PL.Extract(settings)
  end
  account.profiles = book
  local active = PL.Resolve(book, char.profile)
  char.profile = active ~= PL.DEFAULT and active or nil
  local changed = {}
  if active ~= book.working then
    changed = PL.Apply(settings, book.list[active], defaults)
    book.working = active
  end
  return book, active, changed
end

-- The live settings go back into the profile that lives in them.
function PL.Flush(book, settings)
  if type(book) == "table" and type(book.list) == "table" and book.list[book.working] ~= nil then
    book.list[book.working] = PL.Extract(settings)
  end
end

-- Exchange string -------------------------------------------------------------------------------------------

-- Exchange string of a profile (kind "profile" of ns.Strings), or nil and "unavailable" | "too-large".
function PL.Export(name, data)
  local code, why = ns.Strings.encode(PL.KIND, { pv = PL.VERSION, name = name, settings = PL.Extract(data) })
  if not code then
    return nil, why == "LibDeflate missing" and "unavailable" or "encode"
  end
  if #code > ns.Strings.MAX_INPUT then
    return nil, "too-large"
  end
  return code
end

local function cleanValue(v, def, depth, budget)
  local kind = type(v)
  if def ~= nil and type(def) ~= kind then
    return nil
  end
  if kind == "boolean" then
    return v
  elseif kind == "number" then
    return v == v and v ~= math.huge and v ~= -math.huge and v or nil
  elseif kind == "string" then
    return #v <= PL.MAX_STRING and v or nil
  elseif kind ~= "table" or depth > PL.MAX_DEPTH then
    return nil
  end
  local out = {}
  for k, x in pairs(v) do
    budget.n = budget.n + 1
    if budget.n > PL.MAX_NODES then
      return nil
    end
    -- JSON object keys are text: a key of digits was a number (item ids, quest ids).
    if type(k) == "string" and #k <= 15 and k:find("^%-?%d+$") then
      k = tonumber(k)
    end
    if type(k) == "number" or (type(k) == "string" and #k <= 64) then
      local child = cleanValue(x, type(def) == "table" and def[k] or nil, depth + 1, budget)
      if child ~= nil then
        out[k] = child
      end
    end
  end
  return out
end

-- The usable part of received profile data: only keys of the add-on that belong to a profile, values of the
-- type the default has, no function or odd key, limited depth and size. `navClean` (optional) repairs the menu
-- layout. Returns the clean data and the number of dropped keys.
function PL.Sanitize(raw, defaults, navClean)
  defaults = defaults or (ns.Store and ns.Store.defaults.settings) or {}
  local out, dropped, budget = {}, 0, { n = 0 }
  for k, v in pairs(type(raw) == "table" and raw or {}) do
    local known = type(k) == "string" and PL.Included(k) and (defaults[k] ~= nil or PL.EXTRA[k])
    local value
    if known then
      value = cleanValue(v, defaults[k], 0, budget)
    end
    if k == "nav" and value ~= nil then
      value = navClean and navClean(value) or nil
    end
    if value ~= nil then
      out[k] = value
    else
      dropped = dropped + 1
    end
  end
  return out, dropped
end

-- Reads an exchange string. Returns { name, data, dropped, count } or nil and "empty" | "too-large" | "decode" |
-- "json" | "shape" | "type" | "version" | "none" (nothing usable inside).
function PL.Import(text, maxJson)
  local env, why = ns.Strings.decode(text, maxJson or PL.MAX_JSON)
  if not env then
    return nil, why
  end
  if env.type ~= PL.KIND then
    return nil, "type"
  end
  local body = env.data
  if type(body) ~= "table" or type(body.settings) ~= "table" then
    return nil, "shape"
  end
  if env.v > ns.Strings.VERSION or (tonumber(body.pv) or 1) > PL.VERSION then
    return nil, "version"
  end
  local navClean = ns.NavLayout and ns.NavLayout.Sanitize
  local data, dropped = PL.Sanitize(body.settings, nil, navClean)
  if next(data) == nil then
    return nil, "none"
  end
  return {
    name = PL.CleanName(type(body.name) == "string" and body.name or "") or PL.DEFAULT,
    data = data,
    dropped = dropped,
    count = PL.Count(data),
  }
end
