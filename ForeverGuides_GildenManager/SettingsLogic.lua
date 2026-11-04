-- The options of the add-on, no UI and no game calls: every option with its page, kind, limits and
-- default, the clamping of a value, reading and writing in the settings of the guild record (or in the
-- account preferences for the date format) and the bridge to the plan (PlanLogic context).
-- Nothing here changes the guild: all values live in ForeverGuidesGMDB.
local _, gm = ...
if not gm.ext then
  return
end
local FG, GS = gm.FG, gm.GuildStore
local PN, U = FG.PlayerName, FG.U

local SL = {}
gm.SettingsLogic = SL

-- Pages of the tab in display order; "share" holds the categories and limits of sharing (Share.lua).
SL.PAGES = { "general", "protect", "actions", "capture", "display", "share" }
-- From this many removals the player types the number; the name check before a removal is fixed on.
SL.CONFIRM_COUNT = 3
SL.MAX_TEXT = 60
SL.MAX_WORDS = 10

local DEFAULTS, LIMITS = GS.DEFAULTS, GS.LIMITS
local IL = gm.InactivityLogic

-- kind: "bool", "int" (min, max, step, unit), "enum" (values) or "text" (maxLen).
-- scope: "guild" (settings of the guild record) or "prefs" (account preferences).
-- zero: what a 0 stands for, shown instead of the number ("off" or "client").
-- unset: the enum value that is stored as no value at all.
-- danger: a value that needs a clear warning (the dangerous value for an enum is named by `risky`).
SL.OPTIONS = {
  {
    id = "inactiveDays",
    page = "general",
    kind = "int",
    min = IL and IL.MIN_DAYS or 1,
    max = IL and IL.MAX_DAYS or 365,
    step = 1,
    unit = "days",
    default = DEFAULTS.inactiveDays,
  },
  {
    id = "maxLevel",
    page = "general",
    kind = "int",
    min = 0,
    max = 120,
    step = 1,
    unit = "level",
    zero = "client",
    default = 0,
  },
  {
    id = "newbieDays",
    page = "protect",
    kind = "int",
    min = 0,
    max = 365,
    step = 1,
    unit = "days",
    zero = "off",
    default = 7,
  },
  {
    id = "graceDays",
    page = "protect",
    kind = "int",
    min = 0,
    max = 365,
    step = 1,
    unit = "days",
    zero = "off",
    default = 14,
  },
  {
    id = "activeGroupDays",
    page = "protect",
    kind = "int",
    min = 0,
    max = 365,
    step = 1,
    unit = "days",
    zero = "off",
    default = 14,
  },
  { id = "protectWords", page = "protect", kind = "text", maxLen = SL.MAX_TEXT, default = "urlaub" },
  { id = "dryRun", page = "actions", kind = "bool", default = DEFAULTS.dryRun },
  { id = "removeNoPreview", page = "actions", kind = "bool", default = false, danger = true },
  {
    id = "actionBackend",
    page = "actions",
    kind = "enum",
    values = { "auto", "macro", "copy", "direct" },
    default = "auto",
    risky = "direct",
  },
  {
    id = "runMode",
    page = "actions",
    kind = "enum",
    values = { "single", "series" },
    default = "single",
    risky = "series",
  },
  { id = "pauseSec", page = "actions", kind = "int", min = 2, max = 10, step = 1, unit = "sec", default = 3 },
  {
    id = "longPauseSec",
    page = "actions",
    kind = "int",
    min = 0,
    max = 60,
    step = 5,
    unit = "sec",
    zero = "off",
    default = 10,
  },
  { id = "maxTotal", page = "actions", kind = "int", min = 1, max = 25, step = 1, unit = "count", default = 10 },
  { id = "undoDays", page = "actions", kind = "int", min = 1, max = 30, step = 1, unit = "days", default = 7 },
  { id = "notifyDone", page = "actions", kind = "bool", default = true },
  { id = "history", page = "capture", kind = "bool", default = true },
  {
    id = "maxEvents",
    page = "capture",
    kind = "int",
    min = LIMITS.maxEvents[1],
    max = LIMITS.maxEvents[2],
    step = 100,
    unit = "count",
    default = DEFAULTS.maxEvents,
  },
  {
    id = "maxActions",
    page = "capture",
    kind = "int",
    min = LIMITS.maxActions[1],
    max = LIMITS.maxActions[2],
    step = 100,
    unit = "count",
    default = DEFAULTS.maxActions,
  },
  {
    id = "dateFormat",
    page = "display",
    kind = "enum",
    scope = "prefs",
    values = { "auto", "dmy", "iso", "mdy" },
    default = "auto",
    unset = "auto",
  },
  -- Reminders of the overview: how far ahead, the chat line at login (off), where the counted week starts.
  { id = "reminderDays", page = "general", kind = "int", min = 1, max = 60, step = 1, unit = "days", default = 14 },
  { id = "reminderChat", page = "general", kind = "bool", default = false },
  { id = "weekStart", page = "general", kind = "enum", values = { "rolling", "mon", "sun" }, default = "rolling" },
  -- Sharing with other officers: every category starts off, the channel is the officer channel.
  { id = "shareJoins", page = "share", kind = "bool", default = false },
  { id = "shareMarks", page = "share", kind = "bool", default = false },
  { id = "shareNotes", page = "share", kind = "bool", default = false, danger = true },
  {
    id = "shareChannel",
    page = "share",
    kind = "enum",
    values = { "officer", "guild" },
    default = "officer",
    risky = "guild",
  },
  -- Accepted senders: this rank index and every better one (0 is the guild master).
  { id = "shareMinRank", page = "share", kind = "int", min = 0, max = 9, step = 1, unit = "rank", default = 1 },
}

local byId = {}
for _, option in ipairs(SL.OPTIONS) do
  option.scope = option.scope or "guild"
  byId[option.id] = option
end

function SL.Option(id)
  return byId[id]
end

-- The options of one page in definition order.
function SL.OfPage(page)
  local out = {}
  for _, option in ipairs(SL.OPTIONS) do
    if option.page == page then
      out[#out + 1] = option
    end
  end
  return out
end

function SL.Default(id)
  local option = byId[id]
  return option and option.default
end

local function number(v)
  v = tonumber(v)
  return v and v == v and v ~= math.huge and v ~= -math.huge and v or nil
end

-- One line of plain text: no control characters, no "|" (escape sequences), cut by characters.
local function plain(s, maxLen)
  s = s:gsub("%c", " "):gsub("|", ""):gsub("%s+", " ")
  return PN.Cut(U.trim(s), maxLen)
end

-- The value inside the definition of the option; the default for anything unusable or unknown.
function SL.Clamp(id, v)
  local option = byId[id]
  if not option then
    return nil
  end
  if option.kind == "bool" then
    if type(v) == "boolean" then
      return v
    end
    return option.default
  elseif option.kind == "int" then
    local n = number(v)
    return n and U.clamp(math.floor(n + 0.5), option.min, option.max) or option.default
  elseif option.kind == "enum" then
    for _, allowed in ipairs(option.values) do
      if v == allowed then
        return v
      end
    end
    return option.default
  end
  return type(v) == "string" and plain(v, option.maxLen) or option.default
end

-- ctx = { guild = guild record, prefs = account preferences }.
local function store(ctx, option)
  local t = option.scope == "prefs" and ctx.prefs or ctx.guild and ctx.guild.settings
  return type(t) == "table" and t or nil
end

function SL.Get(ctx, id)
  local option = byId[id]
  local t = option and store(ctx, option)
  return SL.Clamp(id, t and t[id])
end

-- Writes the clamped value and answers it; nil for an unknown option or a missing store.
function SL.Set(ctx, id, v)
  local option = byId[id]
  local t = option and store(ctx, option)
  if not t then
    return nil
  end
  local value = SL.Clamp(id, v)
  if value == option.unset then
    t[id] = nil
  else
    t[id] = value
  end
  return value
end

-- True when the value is the dangerous one (series, removal without preview) and needs a warning.
function SL.IsRisky(id, v)
  local option = byId[id]
  if not option then
    return false
  end
  if option.kind == "enum" then
    return option.risky ~= nil and v == option.risky
  end
  return option.danger == true and v == true
end

-- Back to the defaults of one page.
function SL.Reset(ctx, page)
  for _, option in ipairs(SL.OfPage(page)) do
    SL.Set(ctx, option.id, option.default)
  end
end

-- Brings the stored values of the guild record inside their limits, in place. A value that is not
-- there stays absent (the default applies on reading), unknown fields stay as they are.
function SL.Clean(guild)
  local t = guild.settings
  if type(t) ~= "table" then
    return
  end
  for _, option in ipairs(SL.OPTIONS) do
    if option.scope == "guild" and t[option.id] ~= nil then
      t[option.id] = SL.Clamp(option.id, t[option.id])
    end
  end
end

-- "Urlaub, Pause" -> { "urlaub", "pause" }: lower case, no empty entries, at most MAX_WORDS.
function SL.Words(text)
  local out = {}
  if type(text) ~= "string" then
    return out
  end
  for word in text:gmatch("[^,;]+") do
    word = PN.Lower(U.trim(word))
    if word ~= "" and #out < SL.MAX_WORDS then
      out[#out + 1] = word
    end
  end
  return out
end

-- The level cap: the chosen one, else the one the game names, nil when neither is known.
function SL.MaxLevel(ctx)
  local chosen = SL.Get(ctx, "maxLevel")
  if chosen > 0 then
    return chosen
  end
  local fn = rawget(_G, "GetMaxPlayerLevel")
  if type(fn) == "function" then
    local ok, level = pcall(fn)
    level = ok and number(level)
    if level and level > 0 then
      return math.floor(level)
    end
  end
end

-- The fields of the plan context (PlanLogic.Build) that the settings decide.
function SL.PlanContext(ctx)
  return {
    maxTotal = SL.Get(ctx, "maxTotal"),
    maxLevel = SL.MaxLevel(ctx),
    protect = {
      newbieDays = SL.Get(ctx, "newbieDays"),
      graceDays = SL.Get(ctx, "graceDays"),
      activeGroupDays = SL.Get(ctx, "activeGroupDays"),
      words = SL.Words(SL.Get(ctx, "protectWords")),
    },
  }
end

-- The values of the guild record stay inside their limits whenever a record is opened or loaded:
-- joins the cleaning of GuildStore.lua (which is loaded before this file).
local clean = gm.CleanGuild
if clean then
  function gm.CleanGuild(guild)
    clean(guild)
    SL.Clean(guild)
  end
end
