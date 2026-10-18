-- Filter rules for the browse list of the group finder (pure logic, no game calls and no UI;
-- Modules/LfgBrowseFilter.lua reads the game, Modules/LfgFilterPanel.lua is the panel). Input: the result ids
-- of the search, one record of readable fields per id and the filter state (ns.db.lfgFilter). Output: the ids
-- that stay, in the original order, and the counters. All filters combine with AND.
--
-- Every checkbox group works the same way: a missing entry counts as on, and the filter acts only when something
-- is switched off, so the default state hides nothing. A value the addon may not read (secret or inaccessible) or
-- that is missing never hides an entry: the filter fails open. Titles and comments of the listings are protected
-- and never part of a record.
--
-- Record fields (all optional): numMembers, maxPlayers (largest maxNumPlayers of the activities), age (seconds),
-- playstyle (generalPlaystyle, 0 = none given), leaderName, leaderClass (classFilename), leaderLevel, counts (member
-- counts: TANK_REMAINING, HEALER_REMAINING, DAMAGER_REMAINING and one number per class token), activityNames.
--
-- Groups and players (state.show). A listing with more than one member is a group, with one member (or fewer) a
-- single player. state.show is one of "all" (default), "groups" and "players": the mode names the kind that is
-- seen. Older files hold a table { groups, players } of two switches, LB.ShowMode reads both (both on or both off
-- is "all"). A group is always hidden when it has no free slot, the sum of the three *_REMAINING counts being
-- above 0 keeps it, a single player is never hidden by that. Unreadable member numbers or counts keep the entry
-- like everywhere else. So do counters that say nothing: all three missing, or all three 0 in a group with fewer
-- members than maxPlayers (a raid whose counters the game does not fill).
--
-- Matching groups (state.matchRoles, state.seek). state.seek is the set of roles the player searches as (tank,
-- healer, damage; true = chosen). With the switch on and a role chosen, a group stays only when a chosen role has
-- a free slot, the rule of Blizzard's HasRemainingSlotsForLocalPlayerRole. Single players are not touched, and an
-- unreadable counter of a chosen role keeps the entry.
--
-- The dungeon choice (state.categoryID, state.activities) is no result filter: it is the input of the search
-- (panel and Modules/LfgBrowseSearch.lua). Helpers for it live here because they need no game call.
local _, ns = ...

local LB = {}
ns.LfgBrowseFilterLogic = LB

LB.ROLES = { "tank", "healer", "damage" }
-- Key of the remaining slots per role in the member counts, and of the role in the game's role tables.
LB.ROLE_COUNTS = { tank = "TANK_REMAINING", healer = "HEALER_REMAINING", damage = "DAMAGER_REMAINING" }
LB.ROLE_FLAGS = { tank = "tank", healer = "healer", damage = "dps" }
-- Group sizes 1 to 4, and 5 for "5 and more".
LB.SIZES = { 1, 2, 3, 4, 5 }
-- General playstyle: 1 standard, 2 relaxed, 3 serious, 4 expert. 0 (none given) always stays visible.
LB.PLAYSTYLES = { 1, 2, 3, 4 }
-- Entry age limits in seconds, 0 = off.
LB.AGES = { 0, 30, 60, 120, 300 }
-- Most languages kept in the stored choice.
LB.MAX_LANGUAGES = 40
-- Used when the client names no classes.
LB.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
LB.MAX_LEVEL = 100
LB.TEXT_LIMIT = 200
-- Modes of the kind of listing, in panel order.
LB.SHOW = { "groups", "players", "all" }
LB.MAX_ACTIVITIES = 200
-- Panel width in pixels at 100 % font: default, smallest, largest, and the one column mode.
LB.WIDTH = { base = 600, min = 480, max = 900, single = 280 }
LB.SPLIT = 0.5 -- share of the dungeon column in the two column mode

-- Readability check; replaced in tests. The addon's guard answers nil for a secret or inaccessible value.
function LB.safe(value)
  local guard = ns.AutoGuard
  if guard and guard.Safe then
    return guard.Safe(value)
  end
  return value
end

local function number(value)
  value = LB.safe(value)
  return type(value) == "number" and value == value and value or nil
end

local function text(value)
  value = LB.safe(value)
  return type(value) == "string" and value or nil
end

local function list(value)
  value = LB.safe(value)
  return type(value) == "table" and value or nil
end

-- Upper to lower case for the letters the game's string.lower leaves alone, keyed by their two UTF-8 bytes:
-- Latin-1 (without the multiplication sign), OE and the Cyrillic capitals.
local FOLD = { ["\197\146"] = "\197\147" }
local function fold(lead, from, to, targetLead, shift)
  for byte = from, to do
    FOLD[string.char(lead, byte)] = string.char(targetLead, byte + shift)
  end
end
fold(195, 128, 150, 195, 32)
fold(195, 152, 158, 195, 32)
fold(208, 128, 143, 209, 16)
fold(208, 144, 159, 208, 32)
fold(208, 160, 175, 209, -32)

-- ASCII letters only: string.lower follows the C locale of the process, and a locale that maps bytes above 127
-- turns the lead byte of a UTF-8 letter into another byte.
local LOWER = {}
for byte = 65, 90 do
  LOWER[string.char(byte)] = string.char(byte + 32)
end

-- Lower case that also folds those letters. Bytes of any other script pass through unchanged.
function LB.Fold(value)
  return (value:gsub("[A-Z]", LOWER):gsub("[\195\197\208][\128-\191]", FOLD))
end

-- Cuts text to at most max bytes without splitting a UTF-8 character.
function LB.Clip(value, max)
  if #value <= max then
    return value
  end
  local cut = max
  while cut > 0 do
    local byte = value:byte(cut + 1)
    if byte < 128 or byte > 191 then
      break
    end
    cut = cut - 1
  end
  return value:sub(1, cut)
end

-- Latin-1 letters with their plain base letter, as UTF-8 second bytes after \195, so names sort like a reader expects.
local BASE_LETTER = {}
for _, range in ipairs({
  { 160, 165, "a" },
  { 167, 167, "c" },
  { 168, 171, "e" },
  { 172, 175, "i" },
  { 177, 177, "n" },
  { 178, 182, "o" },
  { 184, 184, "o" },
  { 185, 188, "u" },
  { 189, 189, "y" },
  { 191, 191, "y" },
  { 159, 159, "ss" },
}) do
  for byte = range[1], range[2] do
    BASE_LETTER[byte] = range[3]
  end
end

-- Text as the filter compares it: folded, accents removed, umlauts as the usual two letters (a-umlaut becomes ae,
-- o-umlaut oe, u-umlaut ue, sharp s ss), so "Baerbel" finds "Bärbel" and "cafe" finds "café". Other scripts stay.
local PLAIN = { ["\197\147"] = "oe" }
for byte, letters in pairs(BASE_LETTER) do
  PLAIN[string.char(195, byte)] = letters
end
PLAIN["\195\164"], PLAIN["\195\182"], PLAIN["\195\188"], PLAIN["\195\166"] = "ae", "oe", "ue", "ae"

function LB.Plain(value)
  return (LB.Fold(value):gsub("[\195\197][\128-\191]", PLAIN))
end

-- The terms of the text box: one per line or comma separated, folded, empty ones dropped.
function LB.ParseTerms(value)
  local terms = {}
  if type(value) ~= "string" then
    return terms
  end
  for part in LB.Fold(value):gmatch("[^,\n\r]+") do
    -- Space and tab only: a locale dependent %s may count a continuation byte of a letter as white space.
    part = part:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
    if part ~= "" then
      terms[#terms + 1] = part
    end
  end
  return terms
end

local function on(set, key)
  return type(set) ~= "table" or set[key] ~= false
end

-- Whether anything is switched off in a group of checkboxes.
local function restricts(set, keys)
  if type(set) ~= "table" then
    return false
  end
  for _, key in ipairs(keys) do
    if set[key] == false then
      return true
    end
  end
  return false
end

local function hiddenClasses(state)
  local out = {}
  if type(state.classes) == "table" then
    for token, value in pairs(state.classes) do
      if value == false and type(token) == "string" then
        out[#out + 1] = token
      end
    end
  end
  table.sort(out)
  return out
end

local function limit(value)
  return type(value) == "number" and value > 0 and value or nil
end

-- The mode of a stored value: a mode name, an older table of two switches, anything else is "all".
function LB.ShowMode(value)
  for _, mode in ipairs(LB.SHOW) do
    if value == mode then
      return mode
    end
  end
  if type(value) == "table" then
    local groups, players = value.groups ~= false, value.players ~= false
    if groups and not players then
      return "groups"
    elseif players and not groups then
      return "players"
    end
  end
  return "all"
end

-- Ids of the filters that act with this state, in panel order. The free slot rule always acts.
function LB.Active(state)
  local out = {}
  if LB.ShowMode(state.show) ~= "all" then
    out[#out + 1] = "kind"
  end
  out[#out + 1] = "open"
  if state.matchRoles == true and #LB.ChosenRoles(state.seek) > 0 then
    out[#out + 1] = "match"
  end
  if #hiddenClasses(state) > 0 then
    out[#out + 1] = "class"
  end
  if restricts(state.sizes, LB.SIZES) then
    out[#out + 1] = "size"
  end
  if limit(state.levelMin) or limit(state.levelMax) then
    out[#out + 1] = "level"
  end
  if restricts(state.playstyles, LB.PLAYSTYLES) then
    out[#out + 1] = "playstyle"
  end
  if #LB.ParseTerms(state.text) > 0 then
    out[#out + 1] = "text"
  end
  if limit(state.maxAge) then
    out[#out + 1] = "age"
  end
  return out
end

-- What a record needs to carry for this state, so the reader asks the game only for that.
function LB.Needs(state)
  local active = {}
  for _, id in ipairs(LB.Active(state)) do
    active[id] = true
  end
  return {
    counts = true, -- the free slot rule always reads them
    leader = active.class or active.level or false,
    activities = active.text or false,
  }
end

-- The values every pass uses once: the terms in the form of LB.Plain and the classes that are off.
function LB.Context(state)
  local terms = {}
  for i, term in ipairs(LB.ParseTerms(state.text)) do
    terms[i] = LB.Plain(term)
  end
  return { terms = terms, classes = hiddenClasses(state), needs = LB.Needs(state) }
end

-- Predicates: true keeps the entry. An unknown value keeps it too.

-- Remaining slots per role of a group record, { tank, healer, damage } with nil for an unreadable number; nil
-- when the counters say nothing (see the header).
local function slots(rec)
  local counts = list(rec.counts)
  if not counts then
    return nil
  end
  local out, known, total = {}, false, 0
  for _, role in ipairs(LB.ROLES) do
    local free = number(counts[LB.ROLE_COUNTS[role]])
    out[role] = free
    if free then
      known, total = true, total + free
    end
  end
  if not known then
    return nil
  end
  local members, capacity = number(rec.numMembers), number(rec.maxPlayers)
  if total == 0 and members and capacity and capacity > 0 and members < capacity then
    return nil
  end
  return out
end

-- Roles of a stored set that are chosen, in LB.ROLES order.
function LB.ChosenRoles(set)
  local out = {}
  for _, role in ipairs(LB.ROLES) do
    if type(set) == "table" and set[role] == true then
      out[#out + 1] = role
    end
  end
  return out
end

-- A group needs a free slot for a chosen role. Without the switch, a chosen role or a usable counter it stays.
local function matching(rec, state)
  local chosen = LB.ChosenRoles(state.seek)
  if state.matchRoles ~= true or #chosen == 0 then
    return true
  end
  local members = number(rec.numMembers)
  if not members or members <= 1 then
    return true
  end
  local free = slots(rec)
  if not free then
    return true
  end
  for _, role in ipairs(chosen) do
    if free[role] == nil or free[role] > 0 then
      return true
    end
  end
  return false
end

local function classes(rec, _, ctx)
  if #ctx.classes == 0 then
    return true
  end
  local leader = text(rec.leaderClass)
  local counts = list(rec.counts)
  for _, token in ipairs(ctx.classes) do
    if leader == token then
      return false
    end
    local n = counts and number(counts[token])
    if n and n > 0 then
      return false
    end
  end
  return true
end

local function sizes(rec, state)
  local members = number(rec.numMembers)
  if not members then
    return true
  end
  return on(state.sizes, math.max(1, math.min(5, math.floor(members))))
end

local function leaderLevel(rec, state)
  local value = number(rec.leaderLevel)
  if not value then
    return true
  end
  local low, high = limit(state.levelMin), limit(state.levelMax)
  return not ((low and value < low) or (high and value > high))
end

local function playstyle(rec, state)
  local value = number(rec.playstyle)
  if not value or value == 0 then
    return true
  end
  return on(state.playstyles, value)
end

local function contains(value, terms)
  value = LB.Plain(value)
  for _, term in ipairs(terms) do
    if value:find(term, 1, true) then
      return true
    end
  end
  return false
end

-- Leader name or activity name holds one of the terms. With nothing readable the entry stays.
local function words(rec, _, ctx)
  if #ctx.terms == 0 then
    return true
  end
  local known = false
  local name = text(rec.leaderName)
  if name then
    known = true
    if contains(name, ctx.terms) then
      return true
    end
  end
  for _, activity in ipairs(list(rec.activityNames) or {}) do
    local label = text(activity)
    if label then
      known = true
      if contains(label, ctx.terms) then
        return true
      end
    end
  end
  return not known
end

local function age(rec, state)
  local maximum = limit(state.maxAge)
  local value = number(rec.age)
  if not maximum or not value then
    return true
  end
  return value < maximum
end

-- The mode, then the free slot rule for groups (see the header).
local function kind(rec, state)
  local members = number(rec.numMembers)
  if not members then
    return true
  end
  local group = members > 1
  local mode = LB.ShowMode(state.show)
  if mode ~= "all" and mode ~= (group and "groups" or "players") then
    return false
  end
  if not group then
    return true
  end
  local free = slots(rec)
  if not free then
    return true
  end
  local total = 0
  for _, role in ipairs(LB.ROLES) do
    if free[role] == nil then
      return true
    end
    total = total + free[role]
  end
  return total > 0
end

local PREDICATES = { kind, matching, classes, sizes, leaderLevel, playstyle, words, age }

-- True when the entry stays visible. A missing record, an unreadable one and a failing rule keep the entry.
function LB.Matches(rec, state, ctx)
  rec = list(rec)
  if not rec then
    return true
  end
  ctx = ctx or LB.Context(state)
  for _, predicate in ipairs(PREDICATES) do
    local ok, keep = pcall(predicate, rec, state, ctx)
    if ok and keep == false then
      return false
    end
  end
  return true
end

-- ids: result ids in list order. read: a function(id, needs) or a table id -> record. Returns the ids that
-- stay (same order) and { shown, total }.
function LB.Run(ids, read, state)
  local ctx = LB.Context(state)
  local out = {}
  for _, id in ipairs(ids) do
    local ok, rec
    if type(read) == "function" then
      ok, rec = pcall(read, id, ctx.needs)
    else
      ok, rec = true, read and read[id]
    end
    if not ok or LB.Matches(rec, state, ctx) then
      out[#out + 1] = id
    end
  end
  return out, { shown = #out, total = #ids }
end

-- Same ids in the same order.
function LB.Same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

-- State -----------------------------------------------------------------------------------------------------

local function cleanSet(set, keys)
  local out = {}
  for _, key in ipairs(keys) do
    out[key] = not (type(set) == "table" and set[key] == false)
  end
  return out
end

-- A set where only an explicit true counts as chosen.
local function cleanChosen(set, keys)
  local out = {}
  for _, key in ipairs(keys) do
    out[key] = type(set) == "table" and set[key] == true
  end
  return out
end

-- The languages of the search choice: a set of client codes ("deDE", "koKR"). Codes the client does not offer
-- stay stored (another client may), so only the shape is checked here.
function LB.CleanLanguages(set)
  local out, count = {}, 0
  if type(set) == "table" then
    for code, value in pairs(set) do
      if value == true and type(code) == "string" and code:find("^%l%l%u%u$") and count < LB.MAX_LANGUAGES then
        out[code] = true
        count = count + 1
      end
    end
  end
  return out
end

local function cleanLimit(value, max)
  value = tonumber(value)
  if not value or value ~= value or value < 1 then
    return 0
  end
  return math.min(math.floor(value), max)
end

-- Repairs a stored state in place (wrong types, unknown values) and returns it.
function LB.Clean(state)
  state.v = 1
  state.open = state.open == true
  -- The old role filter (a set of switches that hide) is gone: its values mean nothing for the new choice.
  state.roles = nil
  state.seek = cleanChosen(state.seek, LB.ROLES)
  state.matchRoles = state.matchRoles == true
  state.languages = LB.CleanLanguages(state.languages)
  state.sizes = cleanSet(state.sizes, LB.SIZES)
  state.playstyles = cleanSet(state.playstyles, LB.PLAYSTYLES)
  state.show = LB.ShowMode(state.show)
  -- The free slot rule is no setting any more: an old stored value is dropped.
  state.onlyOpen = nil
  state.categoryID = cleanLimit(state.categoryID, 1e9)
  state.width = cleanLimit(state.width, 4000)
  local chosen, count = {}, 0
  if type(state.activities) == "table" then
    for id, value in pairs(state.activities) do
      if value == true and type(id) == "number" and id >= 1 and id == math.floor(id) and count < LB.MAX_ACTIVITIES then
        chosen[id] = true
        count = count + 1
      end
    end
  end
  state.activities = chosen
  -- "None" is its own state and only holds while no activity is chosen.
  state.noActivities = state.noActivities == true and count == 0
  local kept = {}
  if type(state.classes) == "table" then
    for token, value in pairs(state.classes) do
      if value == false and type(token) == "string" and token:find("^%u+$") then
        kept[token] = false
      end
    end
  end
  state.classes = kept
  state.levelMin = cleanLimit(state.levelMin, LB.MAX_LEVEL)
  state.levelMax = cleanLimit(state.levelMax, LB.MAX_LEVEL)
  state.text = type(state.text) == "string" and LB.Clip(state.text, LB.TEXT_LIMIT) or ""
  local maxAge = tonumber(state.maxAge) or 0
  local valid = false
  for _, seconds in ipairs(LB.AGES) do
    valid = valid or seconds == maxAge
  end
  state.maxAge = valid and maxAge or 0
  return state
end

-- Keys of the state that are no result filter (search input, the roles the game also holds): they survive
-- "reset filters".
local KEPT = {
  open = true,
  v = true,
  categoryID = true,
  activities = true,
  noActivities = true,
  width = true,
  seek = true,
  languages = true,
}

-- Back to the default filters; the panel, its dungeon choice and its width stay.
function LB.Reset(state)
  local defaults = ns.Store.defaults.lfgFilter
  for key, value in pairs(defaults) do
    if not KEPT[key] then
      state[key] = ns.U.copy(value)
    end
  end
  return LB.Clean(state)
end

-- The line of the counter.
function LB.CountText(format, counts)
  return string.format(format, counts and counts.shown or 0, counts and counts.total or 0)
end

-- Presets and dungeon choice -----------------------------------------------------------------------------------

-- Sets the kind of listing ("groups", "players", "all"); false for an unknown id.
function LB.SetShow(state, id)
  if LB.ShowMode(id) ~= id then
    return false
  end
  state.show = id
  return true
end

local function levels(entry)
  return tonumber(entry.min) or 0, tonumber(entry.max) or 0
end

-- "Name (15-24)", "Name (60)", "Name (15+)", "Name (-24)" or the plain name. fallback names an entry without info.
function LB.ActivityLabel(entry, fallback)
  local name = LB.ActivityName(entry, fallback)
  local low, high = levels(entry)
  if low > 0 and high > 0 then
    return string.format(low == high and "%s (%d)" or "%s (%d-%d)", name, low, high)
  elseif low > 0 then
    return string.format("%s (%d+)", name, low)
  elseif high > 0 then
    return string.format("%s (-%d)", name, high)
  end
  return name
end

-- The level range alone: "15-24", "60", "15+" (no upper limit), "-24" (no lower limit) or "-" without any range, so
-- a column of ranges keeps its shape.
function LB.ActivityLevels(entry)
  local low, high = levels(entry)
  if low > 0 and high > 0 then
    return string.format(low == high and "%d" or "%d-%d", low, high)
  elseif low > 0 then
    return string.format("%d+", low)
  elseif high > 0 then
    return string.format("-%d", high)
  end
  return "-"
end

-- The name alone, without the range. fallback names an entry without info.
function LB.ActivityName(entry, fallback)
  return type(entry.name) == "string" and entry.name ~= "" and entry.name or fallback or tostring(entry.id)
end

-- Width of the level column: as wide as the widest measured text, whole pixels, never below one.
function LB.LevelColumnWidth(widths)
  local widest = 1
  for _, width in ipairs(widths) do
    widest = math.max(widest, math.ceil(width))
  end
  return widest
end

-- Whether the suggested level range of an entry holds the level. An entry without a range never does.
function LB.InRange(entry, level)
  local low, high = levels(entry)
  if type(level) ~= "number" or (low <= 0 and high <= 0) then
    return false
  end
  return (low <= 0 or level >= low) and (high <= 0 or level <= high)
end

-- Folded name without accents and umlauts, for sorting.
function LB.SortKey(name)
  return (LB.Fold(name or ""):gsub("\195([\128-\191])", function(byte)
    return BASE_LETTER[byte:byte()]
  end))
end

-- Entries { id, name, min, max } by minimum level, then name; entries without a name or a range come last.
function LB.SortActivities(entries)
  local function key(entry)
    local low = levels(entry)
    return low > 0 and low or (entry.name and 0 or 1e9)
  end
  table.sort(entries, function(a, b)
    local ka, kb = key(a), key(b)
    if ka ~= kb then
      return ka < kb
    end
    local na, nb = LB.SortKey(a.name), LB.SortKey(b.name)
    if na ~= nb then
      return na < nb
    end
    return a.id < b.id
  end)
  return entries
end

-- Set of the ids whose range holds the level.
function LB.LevelSet(entries, level)
  local out = {}
  for _, entry in ipairs(entries) do
    if LB.InRange(entry, level) then
      out[entry.id] = true
    end
  end
  return out
end

-- Categories { id, name, total, ranged }: the dungeon category is the one with the most activities that carry a
-- level range (no language involved), then the most activities, then the lowest id.
function LB.PickCategory(categories)
  local best
  for _, category in ipairs(categories) do
    if
      not best
      or category.ranged > best.ranged
      or (category.ranged == best.ranged and category.total > best.total)
      or (category.ranged == best.ranged and category.total == best.total and category.id < best.id)
    then
      best = category
    end
  end
  return best
end

-- The category to show: the stored one while it still exists, else the dungeon category, else 0.
function LB.ResolveCategory(stored, categories)
  for _, category in ipairs(categories) do
    if category.id == stored then
      return stored
    end
  end
  local best = LB.PickCategory(categories)
  return best and best.id or 0
end

-- The ids shown as checked, as a set over the entries of the category: the chosen ones, all of them for an empty
-- choice (the default) and none after an explicit "None". Stored ids outside the category count as no choice.
function LB.Chosen(state, entries)
  local out = {}
  if state.noActivities == true then
    return out
  end
  local set = type(state.activities) == "table" and state.activities or {}
  local any = false
  for _, entry in ipairs(entries) do
    if set[entry.id] == true then
      out[entry.id], any = true, true
    end
  end
  if not any then
    for _, entry in ipairs(entries) do
      out[entry.id] = true
    end
  end
  return out
end

-- Stores a checked set (ids of the entries): all of them is the default (empty set), nothing is "None".
function LB.SetChosen(state, set, entries)
  local picked, count = {}, 0
  for _, entry in ipairs(entries) do
    if set[entry.id] == true then
      picked[entry.id] = true
      count = count + 1
    end
  end
  if count == #entries then
    picked = {}
  end
  state.activities = picked
  state.noActivities = #entries > 0 and count == 0
end

-- Activity ids for the search: the chosen ones that exist in the category, all of them when none is chosen (an
-- empty list would search for nothing). none = the player chose "None": no ids, no search.
function LB.SearchIDs(chosen, available, none)
  local out = {}
  if none == true then
    return out
  end
  for _, id in ipairs(available) do
    if type(chosen) == "table" and chosen[id] == true then
      out[#out + 1] = id
    end
  end
  if #out == 0 then
    for i, id in ipairs(available) do
      out[i] = id
    end
  end
  return out
end

-- Languages of the search --------------------------------------------------------------------------------------------

-- Entries { code, name, locked } for the language choice: the codes the client offers plus the ones it always adds
-- (own, a set; locked), those first, then by name. name(code) is the display name. No offer, no entries.
function LB.LanguageEntries(offered, own, name)
  local out, seen = {}, {}
  if type(offered) ~= "table" or #offered == 0 then
    return out
  end
  local function add(code)
    if type(code) == "string" and code ~= "" and not seen[code] then
      seen[code] = true
      out[#out + 1] = { code = code, name = name(code), locked = type(own) == "table" and own[code] == true }
    end
  end
  for _, code in ipairs(offered) do
    add(code)
  end
  for _, code in ipairs(ns.U.sortedKeys(type(own) == "table" and own or {})) do
    add(code)
  end
  table.sort(out, function(a, b)
    if a.locked ~= b.locked then
      return a.locked
    end
    local ka, kb = LB.SortKey(a.name), LB.SortKey(b.name)
    if ka ~= kb then
      return ka < kb
    end
    return a.code < b.code
  end)
  return out
end

-- The language filter of the search: the locked languages plus the chosen ones among the entries (codes the client
-- does not offer are never sent). nil when that is only the locked language, the client then searches as before.
function LB.LanguageSearch(entries, chosen)
  local out, extra = {}, false
  for _, entry in ipairs(entries) do
    if entry.locked then
      out[entry.code] = true
    elseif type(chosen) == "table" and chosen[entry.code] == true then
      out[entry.code], extra = true, true
    end
  end
  return extra and out or nil
end

-- Panel size -------------------------------------------------------------------------------------------------------

local function round(value)
  return math.floor(value + 0.5)
end

-- The widest and narrowest width at a font ratio (1 = 100 %).
function LB.WidthLimits(ratio)
  ratio = type(ratio) == "number" and ratio > 0 and ratio or 1
  return round(LB.WIDTH.min * ratio), round(LB.WIDTH.max * ratio)
end

function LB.ClampWidth(width, ratio)
  local low, high = LB.WidthLimits(ratio)
  return math.max(low, math.min(high, round(tonumber(width) or low)))
end

-- Width and number of columns. stored: the width the player chose (0 = none), ratio: font ratio, room: pixels
-- between the panel's left edge and the screen edge (nil = unknown). The wide layout needs its smallest width: with
-- less room the panel narrows to the room, and below that it becomes one column of the single width, kept
-- on screen by the clamp of the frame.
function LB.Layout(stored, ratio, room)
  ratio = type(ratio) == "number" and ratio > 0 and ratio or 1
  local low = LB.WidthLimits(ratio)
  local want = LB.ClampWidth(type(stored) == "number" and stored > 0 and stored or round(LB.WIDTH.base * ratio), ratio)
  if type(room) ~= "number" or room >= low then
    return type(room) == "number" and math.min(want, round(room)) or want, 2
  end
  local single = round(LB.WIDTH.single * ratio)
  return math.max(round(160 * ratio), math.min(single, round(room))), 1
end

-- Widths of the two columns inside a panel of this width: the dungeon column and the filter column.
function LB.Columns(width, pad, gap)
  local inner = width - 2 * pad - gap
  local left = math.floor(inner * LB.SPLIT)
  return left, inner - left
end
