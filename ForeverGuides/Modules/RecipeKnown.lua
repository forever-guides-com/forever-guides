-- Known recipes of the own characters. When the profession window opens, the learned recipes are read
-- (C_TradeSkillUI, every call behind an existence check and pcall) and added to the saved list of the
-- character. A reading only ever adds: the client may deliver the filtered view or nothing at all, so
-- an empty or partial answer must not wipe what an earlier visit found.
--
-- ns.db.recipes = { v = 1, chars = { ["Name-Realm"] = { ids = { sorted spell ids }, at = server time } } }
local _, ns = ...
local R = ns.RecipeLogic
local Roster = ns.CharRoster

local K = {}
ns.RecipeKnown = K

local DELAY = 0.5
local MAX_SCAN = 5000
local VERSION = 1
-- Both calls are tried and their answers joined: either may be missing or show the filtered view only.
local LISTS = { "GetAllRecipeIDs", "GetFilteredRecipeIDs" }

-- Last reading for /dump ForeverGuides.RecipeKnown.Last: how many recipes the client listed and how
-- many of them were learned.
K.Last = nil

-- Storage -------------------------------------------------------------------------------------------

local scratch = { v = VERSION, chars = {} }
-- The table that was checked this session, so the cleanup runs once per saved table.
local checked
-- Sets of spell ids per character, rebuilt when the saved list is replaced.
local setCache = {}

local function number(v)
  return type(v) == "number" and v == v and v >= 0 and v <= 1e11 and v or 0
end

-- Repairs a saved value of any shape: bad keys and entries go, id lists are cleaned and capped,
-- the oldest characters above the cap go.
local function normalize(raw)
  local t = type(raw) == "table" and raw or {}
  local chars = {}
  local old = type(t.chars) == "table" and t.chars or {}
  local keys = {}
  for key, e in pairs(old) do
    if type(key) == "string" and key ~= "" and #key <= 80 and type(e) == "table" then
      local ids = R.CleanIds(e.ids, R.MAX_KNOWN)
      if #ids > 0 then
        chars[key] = { ids = ids, at = number(e.at) }
        keys[#keys + 1] = key
      end
    end
  end
  table.sort(keys, function(a, b)
    if chars[a].at ~= chars[b].at then
      return chars[a].at > chars[b].at
    end
    return a < b
  end)
  for i = R.MAX_CHARS + 1, #keys do
    chars[keys[i]] = nil
  end
  return { v = VERSION, chars = chars }
end

local function store()
  local db = ns.db
  if type(db) ~= "table" then
    return scratch
  end
  if db.recipes ~= checked or type(db.recipes) ~= "table" then
    db.recipes = normalize(db.recipes)
    checked = db.recipes
  end
  return db.recipes
end

-- Forgets the checked state (tests).
function K.Reset()
  checked, setCache, K.Last = nil, {}, nil
  scratch = { v = VERSION, chars = {} }
end

-- Sorted spell ids the character knows (a copy), empty for an unknown key.
function K.Ids(key)
  local e = store().chars[key]
  local out = {}
  for i, id in ipairs(e and e.ids or {}) do
    out[i] = id
  end
  return out
end

-- Server time of the last reading, nil for an unknown key.
function K.At(key)
  local e = store().chars[key]
  return e and e.at or nil
end

-- Set of spell ids of one character.
function K.Set(key)
  local e = store().chars[key]
  if not e then
    return {}
  end
  local cached = setCache[key]
  if not cached or cached.ids ~= e.ids then
    cached = { ids = e.ids, set = R.IdSet(e.ids) }
    setCache[key] = cached
  end
  return cached.set
end

-- { [characterKey] = set } of every saved character.
function K.Sets()
  local out = {}
  for key in pairs(store().chars) do
    out[key] = K.Set(key)
  end
  return out
end

function K.Has(key, spell)
  return K.Set(key)[spell] == true
end

-- Name of a character key for display: the roster name, else the key without its realm.
local function displayName(key, names)
  return names[key] or key:match("^(.-)%-[^%-]*$") or key
end

-- The characters that know the spell as { key, name, current }, the current one first, then by name.
function K.Owners(spell)
  local names = {}
  for _, e in ipairs(Roster.List({ all = true })) do
    names[e.key] = e.display
  end
  local current = Roster.CurrentKey()
  local out = {}
  for _, key in ipairs(R.Owners(K.Sets(), spell)) do
    out[#out + 1] = { key = key, name = displayName(key, names), current = key == current }
  end
  table.sort(out, function(a, b)
    if a.current ~= b.current then
      return a.current
    end
    return a.name:lower() < b.name:lower()
  end)
  return out
end

-- Drops the saved lists of characters that left the roster (never the current one). Without a roster
-- nothing is dropped.
local function prune(keep)
  local roster = ns.db and ns.db.roster
  if type(roster) ~= "table" or next(roster) == nil then
    return
  end
  local chars = store().chars
  for key in pairs(chars) do
    if key ~= keep and roster[key] == nil then
      chars[key] = nil
      setCache[key] = nil
    end
  end
end

-- Reading ----------------------------------------------------------------------------------------------

-- The learned recipe ids of the open profession window: { ids, listed } or nil without the API.
local function read()
  local api = rawget(_G, "C_TradeSkillUI")
  if type(api) ~= "table" or type(api.GetRecipeInfo) ~= "function" then
    return nil
  end
  local ids, seen, listed = {}, {}, 0
  for _, name in ipairs(LISTS) do
    local fn = api[name]
    if type(fn) == "function" then
      local ok, list = pcall(fn)
      if ok and type(list) == "table" then
        for i, id in ipairs(list) do
          if i > MAX_SCAN then
            break
          end
          if type(id) == "number" and not seen[id] then
            seen[id] = true
            listed = listed + 1
            local okInfo, info = pcall(api.GetRecipeInfo, id)
            if okInfo and type(info) == "table" and info.learned == true then
              ids[#ids + 1] = id
            end
          end
        end
      end
    end
  end
  return ids, listed
end

-- Reads the profession window and adds the learned recipes to the current character. Returns true when
-- the saved list changed.
function K.Capture()
  if not Roster.Enabled() then
    return false
  end
  local key = Roster.CurrentKey()
  if not key then
    return false
  end
  local ids, listed = read()
  if not ids then
    return false
  end
  K.Last = { listed = listed, learned = #ids }
  if #ids == 0 then
    return false
  end
  local chars = store().chars
  local old = chars[key]
  local merged, changed = R.MergeIds(old and old.ids, ids, R.MAX_KNOWN)
  chars[key] = { ids = changed and merged or (old and old.ids or merged), at = Roster.Now() }
  prune(key)
  if changed then
    ns.Emit("FG_RECIPES_CHANGED", key)
  end
  return changed
end

local function schedule()
  ns.Debounce("recipes-known", DELAY, K.Capture)
end
K.Schedule = schedule

-- The window opens with what the client has at hand; the list updates that follow come in bursts and
-- are bundled. Reading right away keeps the open event free of timers.
ns.On("TRADE_SKILL_SHOW", function()
  K.Capture()
end)
ns.On("TRADE_SKILL_LIST_UPDATE", schedule)
