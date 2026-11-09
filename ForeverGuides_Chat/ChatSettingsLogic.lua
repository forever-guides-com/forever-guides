-- Forever Chat, the rules of the options (pure, no frames, no game access): the registry of options (id,
-- group, type, default, bounds, label keys, place in the store), every read clamped, every write checked, the
-- clock format, the key words and the sound rule. ChatSettings.lua builds the page from the registry; other
-- files add their options with chat.Settings.AddOption(def) (the same as SL.Add).
--
-- def = { id, group, type = "toggle"|"slider"|"dropdown", default, label (locale key), hint (locale key,
--   optional), tip (locale key, optional), min, max, step (slider), choices = { { value, key }, ... } (dropdown),
--   unit (slider, short text after the number), group_label (locale key of the group heading, optional),
--   path = { section, field } (default { "options", id }; section "options" or "view"),
--   apply = function(value) (runs after a change) }
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local SL = {}
chat.SettingsLogic = SL

-- The store keeps this many plain options (Store.MAX_EXTRA_OPTIONS), so the registry never holds more.
SL.MAX_OPTIONS = chat.Store.MAX_EXTRA_OPTIONS
SL.TYPES = { toggle = true, slider = true, dropdown = true }
-- Groups in page order; a group not listed here comes after these, in the order of its first option.
SL.GROUPS =
  { "intake", "history", "open", "launch", "view", "time", "mentions", "sound", "window", "integration", "extras" }
-- Game sounds the choice offers (names in SOUNDKIT). A name the client lacks plays nothing.
SL.SOUNDS =
  { "TELL_MESSAGE", "UI_BNET_TOAST", "IG_QUEST_LIST_OPEN", "IG_MAINMENU_OPTION_CHECKBOX_ON", "ALARM_CLOCK_WARNING_2" }
-- Percent. 0 clears only the window background: texts, cards and controls keep their own fills (ChatSettings.Style).
SL.OPACITY_MIN, SL.OPACITY_MAX, SL.OPACITY_DEFAULT = 0, 100, 92
SL.CLOCKS = { ["24h"] = { "%H:%M", "%H:%M:%S" }, ["12h"] = { "%I:%M %p", "%I:%M:%S %p" } }

local defs, order = {}, {}

local function isNumber(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function validPath(path)
  return type(path) == "table" and (path[1] == "options" or path[1] == "view") and type(path[2]) == "string"
end

local function hasChoice(def, value)
  for _, choice in ipairs(def.choices) do
    if choice.value == value then
      return true
    end
  end
  return false
end

-- The value a definition accepts: toggles a boolean, sliders a number inside the bounds on the step, dropdowns
-- one of the choices. Anything else gives the default.
local function clamp(def, value)
  if def.type == "toggle" then
    if type(value) == "boolean" then
      return value
    end
    return def.default
  elseif def.type == "slider" then
    if not isNumber(value) then
      return def.default
    end
    local step = def.step or 1
    value = math.floor((value - def.min) / step + 0.5) * step + def.min
    return math.max(def.min, math.min(def.max, value))
  end
  return hasChoice(def, value) and value or def.default
end

-- Adds an option. Returns true, or false and why: "def", "id", "type", "default", "bounds", "choices", "path",
-- "duplicate" or "full". A refused definition changes nothing.
function SL.Add(def)
  if type(def) ~= "table" then
    return false, "def"
  end
  if type(def.id) ~= "string" or not def.id:find("^%a[%w_]*$") or #def.id > 32 then
    return false, "id"
  end
  if not SL.TYPES[def.type] or type(def.label) ~= "string" then
    return false, "type"
  end
  if defs[def.id] then
    return false, "duplicate"
  end
  if #order >= SL.MAX_OPTIONS then
    return false, "full"
  end
  local path = def.path or { "options", def.id }
  if not validPath(path) then
    return false, "path"
  end
  local out = {
    id = def.id,
    group = type(def.group) == "string" and def.group or "misc",
    type = def.type,
    default = def.default,
    label = def.label,
    hint = type(def.hint) == "string" and def.hint or nil,
    tip = type(def.tip) == "string" and def.tip or nil,
    path = { path[1], path[2] },
    unit = type(def.unit) == "string" and def.unit:sub(1, 8) or nil,
    groupLabel = type(def.group_label) == "string" and def.group_label or nil,
    apply = type(def.apply) == "function" and def.apply or nil,
  }
  if def.type == "toggle" then
    if type(def.default) ~= "boolean" then
      return false, "default"
    end
  elseif def.type == "slider" then
    if
      not (
        isNumber(def.min)
        and isNumber(def.max)
        and def.min < def.max
        and (def.step == nil or (isNumber(def.step) and def.step > 0))
      )
    then
      return false, "bounds"
    end
    out.min, out.max, out.step = def.min, def.max, def.step or 1
    if not isNumber(def.default) or def.default < def.min or def.default > def.max then
      return false, "default"
    end
  else
    if type(def.choices) ~= "table" or #def.choices == 0 then
      return false, "choices"
    end
    out.choices = {}
    for _, choice in ipairs(def.choices) do
      if type(choice) ~= "table" or choice.value == nil or type(choice.key) ~= "string" then
        return false, "choices"
      end
      out.choices[#out.choices + 1] = { value = choice.value, key = choice.key }
    end
    if not hasChoice(out, def.default) then
      return false, "default"
    end
  end
  defs[out.id] = out
  order[#order + 1] = out.id
  return true
end

function SL.Get(id)
  return defs[id]
end

-- Definitions in page order: the groups of SL.GROUPS first, then the rest, each in the order they were added.
function SL.List()
  local rank = {}
  for i, group in ipairs(SL.GROUPS) do
    rank[group] = i
  end
  local out = {}
  for i, id in ipairs(order) do
    out[i] = defs[id]
  end
  local index = {}
  for i, def in ipairs(out) do
    index[def] = i
  end
  table.sort(out, function(a, b)
    local ra, rb = rank[a.group] or (#SL.GROUPS + 1), rank[b.group] or (#SL.GROUPS + 1)
    if ra ~= rb then
      return ra < rb
    end
    return index[a] < index[b]
  end)
  return out
end

-- The groups that hold options, in page order.
function SL.UsedGroups()
  local out, seen = {}, {}
  for _, def in ipairs(SL.List()) do
    if not seen[def.group] then
      seen[def.group] = true
      out[#out + 1] = def.group
    end
  end
  return out
end

local function container(db, def)
  local map = type(db) == "table" and db[def.path[1]] or nil
  return type(map) == "table" and map or nil
end

-- The value of an option from the store db, clamped (the default for an unknown id or a damaged store).
function SL.Value(db, id)
  local def = defs[id]
  if not def then
    return nil
  end
  local map = container(db, def)
  return clamp(def, map and map[def.path[2]])
end

-- Writes a value (clamped; a wrong type becomes the default). Returns true and the value now stored, or false
-- for an unknown id or a store without room.
function SL.Write(db, id, value)
  local def = defs[id]
  local map = def and container(db, def)
  if not map then
    return false
  end
  local clean = clamp(def, value)
  map[def.path[2]] = clean
  return true, clean
end

-- Every option as id = value, clamped.
function SL.Snapshot(db)
  local out = {}
  for _, id in ipairs(order) do
    out[id] = SL.Value(db, id)
  end
  return out
end

-- Clock ---------------------------------------------------------------------------------------------------------

-- The date format of a time stamp for the options (a store or its options table): 24 hours or 12 hours, with
-- or without seconds.
function SL.ClockFormat(db)
  local opts = type(db) == "table" and (type(db.options) == "table" and db.options or db) or {}
  local kind = SL.CLOCKS[opts.timeFormat] and opts.timeFormat or "24h"
  return SL.CLOCKS[kind][opts.timeSeconds == true and 2 or 1]
end

-- Key words ----------------------------------------------------------------------------------------------------

-- The words of the input line: separated by commas or semicolons, trimmed, cleaned and capped by the store.
function SL.ParseKeywords(text)
  local list = {}
  if type(text) == "string" then
    for word in (text .. ","):gmatch("([^,;]*)[,;]") do
      list[#list + 1] = word
    end
  end
  return chat.Store.Clean({ options = { keywords = list } }).options.keywords
end

function SL.KeywordText(list)
  return type(list) == "table" and table.concat(list, ", ") or ""
end

-- Sound --------------------------------------------------------------------------------------------------------

-- True when a rise of the unread total should ring: the sound is on, not in combat, and the total went up.
function SL.ShouldPlay(before, total, on, inCombat)
  return on == true and not inCombat and isNumber(before) and isNumber(total) and total > before
end

-- Window opacity from the options as a share (0 to 1), nil while the player never set one (the window then
-- follows the window style of the main add-on).
function SL.Opacity(db)
  local opts = type(db) == "table" and type(db.options) == "table" and db.options or {}
  if not isNumber(opts.opacity) then
    return nil
  end
  return math.max(SL.OPACITY_MIN, math.min(SL.OPACITY_MAX, opts.opacity)) / 100
end

-- Built-in options ---------------------------------------------------------------------------------------------

local function modeChoices()
  local out = {}
  for _, mode in ipairs(chat.Store.MODES) do
    out[#out + 1] = { value = mode, key = "chat.mode." .. mode }
  end
  return out
end

local function soundChoices()
  local out = {}
  for _, name in ipairs(SL.SOUNDS) do
    out[#out + 1] = { value = name, key = "chat.set.sound." .. name }
  end
  return out
end

local function syncIntake()
  if chat.Ingest and chat.Ingest.Sync then
    chat.Ingest.Sync()
  end
end

local function syncArchive()
  if chat.Ingest and chat.Ingest.SyncArchive then
    chat.Ingest.SyncArchive()
  end
end

local function archiveDaysChoices()
  local out = {}
  for _, days in ipairs(chat.ArchiveLogic.DAYS) do
    out[#out + 1] = { value = days, key = "chat.set.archiveDays." .. days }
  end
  return out
end

local builtin = {
  { id = "intake", group = "intake", type = "toggle", default = true, apply = syncIntake },
  { id = "localChat", group = "intake", type = "toggle", default = true, apply = syncIntake },
  { id = "archive", group = "history", type = "toggle", default = true, apply = syncArchive },
  {
    id = "archiveDays",
    group = "history",
    type = "dropdown",
    default = chat.ArchiveLogic.DEFAULT_DAYS,
    choices = archiveDaysChoices(),
    apply = syncArchive,
  },
  { id = "archivePublic", group = "history", type = "toggle", default = true, apply = syncArchive },
  {
    id = "defaultMode",
    group = "view",
    type = "dropdown",
    default = chat.Store.DEFAULT_MODE,
    choices = modeChoices(),
    path = { "view", "mode" },
  },
  {
    id = "timeFormat",
    group = "time",
    type = "dropdown",
    default = "24h",
    choices = { { value = "24h", key = "chat.set.timeFormat.24h" }, { value = "12h", key = "chat.set.timeFormat.12h" } },
  },
  { id = "timeSeconds", group = "time", type = "toggle", default = false },
  { id = "mentionBreaksMute", group = "mentions", type = "toggle", default = true },
  { id = "channelMentionOnly", group = "mentions", type = "toggle", default = true },
  { id = "sound", group = "sound", type = "toggle", default = false },
  { id = "soundId", group = "sound", type = "dropdown", default = SL.SOUNDS[1], choices = soundChoices() },
  {
    id = "opacity",
    group = "window",
    type = "slider",
    default = SL.OPACITY_DEFAULT,
    min = SL.OPACITY_MIN,
    max = SL.OPACITY_MAX,
    step = 5,
    unit = "%",
  },
}
-- Options that carry a tooltip text besides the hint.
local TIP = { intake = true, localChat = true, archive = true, archivePublic = true, sound = true, opacity = true }
for _, def in ipairs(builtin) do
  def.label = "chat.set." .. def.id
  def.hint = "chat.set." .. def.id .. ".hint"
  def.tip = TIP[def.id] and ("chat.set." .. def.id .. ".tip") or nil
  assert(SL.Add(def))
end
