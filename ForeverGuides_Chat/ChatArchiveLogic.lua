-- Forever Chat, the rules of the saved conversations (pure, no game access, the caller passes every clock value).
-- The messenger keeps its conversations in ForeverGuidesChatDB.archive so they survive a reload and a restart.
--
-- history = { v = 1, legacy = bool, chars = { [character "Name-Realm"] = section }, acct = section }
-- section = { s = time of the last write, c = { [conversation key] = entry } }
-- entry   = { n = display name, t = time of the last line, p = true for a public channel, g = BattleTag,
--             w = Battle.net character, l = { time, code, sender, text, time, code, sender, text, ... } }
-- code = type * 4 + direction. The lines of an entry are flat (four values each, oldest first), so the
-- file the game writes at logout holds one table per conversation and none per line.
--
-- Battle.net conversations live in the account section (friends belong to the account), everything else in
-- the section of the character. Teams keep their own history (ChatTeamsLogic) and never come here.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local Logic = FG.ChatHistoryLogic

local AL = {}
chat.ArchiveLogic = AL

AL.VERSION = 1
AL.STRIDE = 4
AL.TEXT_CHARS = 255
AL.DAYS = { 7, 30, 90 }
AL.DEFAULT_DAYS = 30
-- Lines per conversation: the default, the kinds with a lower limit and public channels (very noisy).
AL.LINES = 500
AL.KIND_LINES = { channel = 200, ["local"] = 200 }
AL.PUBLIC_LINES = 100
-- Lines in all conversations of one section.
AL.CAP = { char = 8000, acct = 3000 }
-- Lines above a limit that wait for the next cleaning, so a single line never shifts a whole table.
AL.SLACK = 20
AL.CAP_SLACK = 200
AL.MAX_CONVS = 200
AL.MAX_CHARS = 20
AL.KEY_BYTES = 96
AL.NAME_BYTES = 64

local IN, OUT = Logic.DIR_IN, Logic.DIR_OUT
local STRIDE = AL.STRIDE
local SYSTEM = Logic.TYPES.system
local DAY = Logic.SECONDS_PER_DAY

local function isTime(value)
  return type(value) == "number" and value == value and value > 0 and value < 4102444800
end

-- "acct" for Battle.net, "char" for the rest, nil for the kinds that are not saved here (teams).
function AL.Scope(kind)
  if kind == "bnet" then
    return "acct"
  end
  if
    kind == "whisper"
    or kind == "party"
    or kind == "raid"
    or kind == "instance"
    or kind == "guild"
    or kind == "officer"
    or kind == "channel"
    or kind == "local"
  then
    return "char"
  end
  return nil
end

function AL.LineLimit(kind, public)
  if public == true then
    return AL.PUBLIC_LINES
  end
  return AL.KIND_LINES[kind] or AL.LINES
end

-- The options of the store with their defaults (everything on, 30 days). A wrong type gives the default.
function AL.Options(db)
  local opts = type(db) == "table" and type(db.options) == "table" and db.options or {}
  local days = AL.DEFAULT_DAYS
  for _, value in ipairs(AL.DAYS) do
    if opts.archiveDays == value then
      days = value
    end
  end
  return {
    enabled = opts.archive ~= false,
    days = days,
    public = opts.archivePublic ~= false,
    intake = opts.intake ~= false,
  }
end

-- Lines ----------------------------------------------------------------------------------------------------

-- The four values of a line for the file, or nil when the line is never saved: an unreadable line (secret
-- value), an empty text, a placeholder text, a system line. placeholders: set of texts that stand for
-- "not readable".
function AL.Pack(line, placeholders)
  if type(line) ~= "table" or line.hidden or type(line.text) ~= "string" or line.text == "" then
    return nil
  end
  if type(line.sender) ~= "string" or not isTime(line.time) then
    return nil
  end
  local kind = line.type
  if not Logic.TYPE_NAMES[kind] or kind == SYSTEM or (line.dir ~= IN and line.dir ~= OUT) then
    return nil
  end
  if placeholders and (placeholders[line.text] or placeholders[line.sender]) then
    return nil
  end
  return math.floor(line.time), kind * STRIDE + line.dir, line.sender, Logic.TruncateText(line.text, AL.TEXT_CHARS)
end

function AL.Unpack(code)
  local kind = math.floor(code / STRIDE)
  return kind, code - kind * STRIDE
end

-- Drops the oldest lines so that keep lines stay. Returns the number of dropped lines.
local function cutFront(l, keep)
  local size = math.floor(#l / STRIDE)
  local drop = size - keep
  if drop <= 0 then
    return 0
  end
  local shift, total = drop * STRIDE, #l
  for i = 1, total - shift do
    l[i] = l[i + shift]
  end
  for i = total - shift + 1, total do
    l[i] = nil
  end
  return drop
end
AL.CutFront = cutFront

local function dropBefore(l, cutoff, inclusive)
  local size = math.floor(#l / STRIDE)
  local gone = 0
  for i = 1, size do
    local time = l[(i - 1) * STRIDE + 1]
    if time < cutoff or (inclusive and time == cutoff) then
      gone = i
    else
      break
    end
  end
  return cutFront(l, size - gone)
end

-- Sections ---------------------------------------------------------------------------------------------------

function AL.NewHistory()
  return { v = AL.VERSION, chars = {} }
end

-- The shape of the history that comes out of the SavedVariables: tables where tables belong, nothing else
-- is read at load time. The sections are checked when they are used.
function AL.ShapeHistory(raw)
  local out = AL.NewHistory()
  if type(raw) ~= "table" or (type(raw.v) == "number" and raw.v > AL.VERSION) then
    return out
  end
  out.legacy = raw.legacy == true or nil
  if type(raw.chars) == "table" then
    out.chars = raw.chars
  end
  if type(raw.acct) == "table" then
    out.acct = raw.acct
  end
  return out
end

local function newSection()
  return { s = 0, c = {} }
end

-- The section of a scope, made when missing. A damaged one is replaced. char: the key of the character.
function AL.Section(history, scope, char)
  if type(history) ~= "table" then
    return nil
  end
  local section
  if scope == "acct" then
    section = history.acct
    if type(section) ~= "table" then
      section = newSection()
      history.acct = section
    end
  else
    if type(char) ~= "string" or char == "" then
      return nil
    end
    section = history.chars[char]
    if type(section) ~= "table" then
      section = newSection()
      history.chars[char] = section
    end
  end
  if type(section.c) ~= "table" then
    section.c = {}
  end
  section.s = type(section.s) == "number" and section.s or 0
  return section
end

local function validKey(key)
  return type(key) == "string" and key ~= "" and #key <= AL.KEY_BYTES
end

local function validEntry(entry)
  return type(entry) == "table" and type(entry.l) == "table"
end

-- Number of lines of an entry (the array may end in a half line, which is never counted).
function AL.EntryLines(entry)
  return validEntry(entry) and math.floor(#entry.l / STRIDE) or 0
end

function AL.Total(section)
  local total = 0
  if type(section) == "table" and type(section.c) == "table" then
    for _, entry in pairs(section.c) do
      total = total + AL.EntryLines(entry)
    end
  end
  return total
end

-- Adds one packed line. meta = { name, public, tag, character } describes the conversation. Returns the change
-- in the number of lines (one more, minus the lines the limit dropped).
function AL.Append(section, key, meta, time, code, sender, text, now)
  local entry = section.c[key]
  if not validEntry(entry) then
    entry = { n = "", t = 0, l = {} }
    section.c[key] = entry
  end
  local l = entry.l
  -- A line that was cut in half by a damaged file is cleaned away first.
  local extra = #l % STRIDE
  if extra > 0 then
    for i = #l - extra + 1, #l do
      l[i] = nil
    end
  end
  local at = #l
  l[at + 1], l[at + 2], l[at + 3], l[at + 4] = time, code, sender, text
  if type(meta) == "table" then
    if type(meta.name) == "string" and meta.name ~= "" then
      entry.n = FG.ChatHistoryLimits.CutUtf8(meta.name, AL.NAME_BYTES)
    end
    entry.p = meta.public == true or nil
    entry.g = type(meta.tag) == "string" and FG.ChatHistoryLimits.CutUtf8(meta.tag, AL.NAME_BYTES) or nil
    entry.w = type(meta.character) == "string" and FG.ChatHistoryLimits.CutUtf8(meta.character, AL.NAME_BYTES) or nil
  end
  entry.t = math.max(type(entry.t) == "number" and entry.t or 0, time)
  section.s = now
  local delta = 1
  local limit = AL.LineLimit(meta and meta.kind, meta and meta.public)
  if #l > (limit + AL.SLACK) * STRIDE then
    delta = delta - cutFront(l, limit)
  end
  return delta
end

-- Takes the lines of a conversation in memory as the new content of its entry (after a merge).
function AL.Rewrite(section, key, meta, lines, placeholders, now)
  section.c[key] = nil
  local added = 0
  for _, line in ipairs(lines) do
    local time, code, sender, text = AL.Pack(line, placeholders)
    if time then
      added = added + AL.Append(section, key, meta, time, code, sender, text, now)
    end
  end
  return added
end

-- The lines of an entry as { time, dir, sender, text, type } tables, oldest first, damaged groups left out.
-- Lines out of order are put in order of their time. nil when the entry is not usable.
function AL.Read(entry)
  if not validEntry(entry) then
    return nil
  end
  local l, out, sorted, last = entry.l, {}, true, 0
  for i = 1, #l - STRIDE + 1, STRIDE do
    local time, code, sender, text = l[i], l[i + 1], l[i + 2], l[i + 3]
    if
      isTime(time)
      and type(code) == "number"
      and type(sender) == "string"
      and type(text) == "string"
      and text ~= ""
    then
      local kind, dir = AL.Unpack(code)
      if Logic.TYPE_NAMES[kind] and (dir == IN or dir == OUT) then
        if time < last then
          sorted = false
        end
        last = time
        out[#out + 1] = { time = time, dir = dir, sender = sender, text = text, type = kind, order = #out }
      end
    end
  end
  if not sorted then
    table.sort(out, function(a, b)
      if a.time ~= b.time then
        return a.time < b.time
      end
      return a.order < b.order
    end)
  end
  return out
end

-- Cleaning --------------------------------------------------------------------------------------------------

local function dropEmpty(section)
  for key, entry in pairs(section.c) do
    if not validKey(key) or not validEntry(entry) or #entry.l < STRIDE then
      section.c[key] = nil
    end
  end
end

local function sortedByQuiet(section, pins)
  local list = {}
  for key, entry in pairs(section.c) do
    list[#list + 1] = { key = key, t = type(entry.t) == "number" and entry.t or 0, pinned = pins[key] == true }
  end
  table.sort(list, function(a, b)
    if a.pinned ~= b.pinned then
      return not a.pinned
    end
    if a.t ~= b.t then
      return a.t < b.t
    end
    return a.key < b.key
  end)
  return list
end

-- Removes the oldest lines until the section holds cap lines. Unpinned conversations lose their lines first, in
-- the order of their time (the quietest conversations are the ones with the oldest lines); pinned ones only
-- when that is not enough. Lines of the same second as the cut go together, so the result may be a little
-- under the cap, never over it.
local function enforceCap(section, cap, pins)
  local total = AL.Total(section)
  for pass = 1, 2 do
    if total <= cap then
      return total
    end
    local times = {}
    for key, entry in pairs(section.c) do
      if pass == 2 or pins[key] ~= true then
        local l = entry.l
        for i = 1, #l - STRIDE + 1, STRIDE do
          times[#times + 1] = l[i]
        end
      end
    end
    if #times > 0 then
      table.sort(times)
      local cut = times[math.min(total - cap, #times)]
      for key, entry in pairs(section.c) do
        if pass == 2 or pins[key] ~= true then
          dropBefore(entry.l, cut, true)
        end
      end
    end
    dropEmpty(section)
    total = AL.Total(section)
  end
  return total
end

-- Cleaning of one section: lines older than the retention time go, every conversation is cut to its limit,
-- at most MAX_CONVS conversations stay (the quietest unpinned ones go first), the section is cut to its cap.
-- opts = { now, days, pins, cap }. Returns the number of lines left.
function AL.Trim(section, opts)
  local pins = opts.pins or {}
  dropEmpty(section)
  local cutoff = opts.now - opts.days * DAY
  for key, entry in pairs(section.c) do
    local l = entry.l
    local extra = #l % STRIDE
    for i = #l, #l - extra + 1, -1 do
      l[i] = nil
    end
    if isTime(l[1]) then
      dropBefore(l, cutoff, false)
    end
    cutFront(l, AL.LineLimit(AL.kindOf(key), entry.p))
  end
  dropEmpty(section)
  local list = sortedByQuiet(section, pins)
  for i = 1, #list - AL.MAX_CONVS do
    section.c[list[i].key] = nil
  end
  return enforceCap(section, opts.cap, pins)
end

function AL.kindOf(key)
  return type(key) == "string" and key:match("^(%a+)") or nil
end

-- Removes the sections of characters that wrote nothing for the retention time, and the oldest ones beyond
-- MAX_CHARS. keep: the key of the character in use, which always stays.
function AL.TrimChars(history, now, days, keep)
  local cutoff = now - days * DAY
  local list = {}
  for char, section in pairs(history.chars) do
    if type(char) ~= "string" or type(section) ~= "table" then
      history.chars[char] = nil
    elseif char ~= keep then
      if type(section.s) ~= "number" or section.s < cutoff then
        history.chars[char] = nil
      else
        list[#list + 1] = { char = char, s = section.s }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.s ~= b.s then
      return a.s > b.s
    end
    return a.char < b.char
  end)
  for i = AL.MAX_CHARS, #list do
    history.chars[list[i].char] = nil
  end
end

-- Removes the entries whose kind is in kinds (a set), all entries when kinds is nil. Returns the lines removed.
function AL.Clear(section, kinds)
  local removed = 0
  if type(section) ~= "table" or type(section.c) ~= "table" then
    return removed
  end
  for key, entry in pairs(section.c) do
    if kinds == nil or kinds[AL.kindOf(key)] then
      removed = removed + AL.EntryLines(entry)
      section.c[key] = nil
    end
  end
  return removed
end

-- Approximate size in the SavedVariables file of a section: the strings plus the markup the game writes for
-- every value (indent, comma, index comment).
function AL.EstimateBytes(section)
  local bytes = 0
  if type(section) ~= "table" or type(section.c) ~= "table" then
    return bytes
  end
  for _, entry in pairs(section.c) do
    bytes = bytes + 80 + #(entry.n or "")
    for i, value in ipairs(entry.l or {}) do
      bytes = bytes + 16 + (type(value) == "string" and #value + 2 or 10) + (i > 9999 and 1 or 0)
    end
  end
  return bytes
end
