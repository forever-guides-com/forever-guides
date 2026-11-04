-- Chat and whisper history, the pure side: bounded buffers per chat window and per whisper conversation,
-- the compact line format, trimming (age, per buffer, per store, memory) and deleting. Trimming only
-- removes lines; a conversation that runs empty disappears with its last line. No game access,
-- the caller passes every clock value.
--
-- line   = { time, typeId, sender, text }  (whisper lines add [5] own character, [6] direction)
-- windows (per character) = { v = 1, windows = { [windowId] = { name, lines = { line, ... } } } }
-- whispers (account)      = { v = 1, contacts = { [key] = { name, last, lines = { line, ... } } } }
-- Lines are stored oldest first. `settings` is the normalized settings.chat table
-- (ChatHistoryLimits.Normalize); every limit read from it is clamped again.
local _, ns = ...

local Logic = {}
ns.ChatHistoryLogic = Logic

local Limits = ns.ChatHistoryLimits
local PN = ns.PlayerName

Logic.VERSION = 1

local TIME, TYPE, SENDER, TEXT, CHAR, DIR = 1, 2, 3, 4, 5, 6
Logic.FIELDS = { TIME = TIME, TYPE = TYPE, SENDER = SENDER, TEXT = TEXT, CHAR = CHAR, DIR = DIR }

Logic.TYPES = {
  say = 1,
  yell = 2,
  party = 3,
  raid = 4,
  guild = 5,
  officer = 6,
  channel = 7,
  emote = 8,
  system = 9,
  whisper = 10,
}
Logic.TYPE_NAMES = {}
for name, id in pairs(Logic.TYPES) do
  Logic.TYPE_NAMES[id] = name
end

Logic.DIR_IN, Logic.DIR_OUT = 1, 2

Logic.SECONDS_PER_DAY = 86400
-- Size estimate: bytes the SavedVariables file and the table take besides the strings.
Logic.LINE_OVERHEAD = 64
Logic.BUFFER_OVERHEAD = 96
Logic.WARN_RATIO = 0.8

local function isCount(value)
  return type(value) == "number" and value >= 0 and value % 1 == 0
end

local function isTime(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isKey(value)
  return type(value) == "number" and value == value or (type(value) == "string" and value ~= "")
end

local function cfg(settings, key)
  return Limits.Clamp(key, type(settings) == "table" and settings[key] or nil)
end

local function lineTime(line)
  return type(line) == "table" and isTime(line[TIME]) and line[TIME] or 0
end

local function isLine(line)
  return type(line) == "table"
    and isTime(line[TIME])
    and isCount(line[TYPE])
    and type(line[SENDER]) == "string"
    and type(line[TEXT]) == "string"
end

----------------------------------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------------------------------

-- Escape state of a string: start of an unfinished color, of an unfinished link or texture, or of a
-- half written escape at the end.
local function scanEscapes(text)
  local colorAt, spanAt, spanEnd, linkPhase, partialAt
  local i = 1
  while true do
    i = text:find("|", i, true)
    if not i then
      break
    end
    local code = text:sub(i + 1, i + 1)
    if code == "" then
      partialAt = i
      break
    elseif code == "|" then
      i = i + 2
    elseif code == "c" then
      local hex = text:sub(i + 2, i + 9)
      if #hex == 8 and hex:match("^%x+$") then
        colorAt = i
        i = i + 10
      elseif #hex < 8 and hex:match("^%x*$") then
        partialAt = i
        break
      else
        i = i + 2
      end
    elseif code == "r" then
      colorAt = nil
      i = i + 2
    elseif code == "H" then
      spanAt, spanEnd, linkPhase = i, "h", 0
      i = i + 2
    elseif code == "h" then
      -- First |h ends the link data, the second one ends the link text.
      if spanEnd == "h" then
        if linkPhase == 0 then
          linkPhase = 1
        else
          spanAt, spanEnd = nil, nil
        end
      end
      i = i + 2
    elseif code == "T" or code == "A" then
      spanAt, spanEnd, linkPhase = i, code:lower(), nil
      i = i + 2
    elseif code == spanEnd then
      spanAt, spanEnd = nil, nil
      i = i + 2
    else
      i = i + 2
    end
  end
  return colorAt, spanAt, partialAt
end

-- Position after the maxChars-th character (UTF-8 code point), or nil when the text is shorter.
local function utf8Boundary(text, maxChars)
  local count = 0
  for i = 1, #text do
    local byte = text:byte(i)
    if byte < 0x80 or byte >= 0xC0 then
      count = count + 1
      if count > maxChars then
        return i - 1
      end
    end
  end
  return nil
end

-- Shortens to maxChars characters. The cut never lands inside a multibyte character; a link, texture
-- or color escape the cut would split is removed with its start, an open color gets its |r.
function Logic.TruncateText(text, maxChars)
  local at = utf8Boundary(text, maxChars)
  if not at then
    return text
  end
  local cut = text:sub(1, at)
  local colorAt, spanAt, partialAt = scanEscapes(cut)
  local from = math.min(spanAt or math.huge, partialAt or math.huge)
  if from < math.huge then
    -- A color that opens right before the broken piece belongs to it.
    if colorAt and colorAt < from and cut:sub(colorAt + 10, from - 1) == "" then
      from = colorAt
    end
    cut = cut:sub(1, from - 1)
    colorAt = scanEscapes(cut)
  end
  if colorAt then
    -- A color without any text behind it is dropped, otherwise it is closed.
    cut = cut:sub(colorAt + 10) == "" and cut:sub(1, colorAt - 1) or (cut .. "|r")
  end
  return cut
end

-- A stored line, or nil for unusable input. The text is shortened to maxChars characters.
function Logic.MakeLine(time, typeId, sender, text, maxChars)
  if not isTime(time) or not Logic.TYPE_NAMES[typeId] or type(text) ~= "string" then
    return nil
  end
  if sender ~= nil and type(sender) ~= "string" then
    return nil
  end
  return {
    math.floor(time),
    typeId,
    Limits.CutUtf8(sender or "", Limits.NAME_MAX_BYTES),
    Logic.TruncateText(text, Limits.Clamp("maxChars", maxChars)),
  }
end

-- direction: Logic.DIR_IN or Logic.DIR_OUT, ownName the own character as "Name-Realm".
function Logic.MakeWhisperLine(time, direction, sender, text, ownName, maxChars)
  if (direction ~= Logic.DIR_IN and direction ~= Logic.DIR_OUT) or type(ownName) ~= "string" then
    return nil
  end
  local line = Logic.MakeLine(time, Logic.TYPES.whisper, sender, text, maxChars)
  if not line then
    return nil
  end
  line[CHAR] = Limits.CutUtf8(ownName, Limits.NAME_MAX_BYTES)
  line[DIR] = direction
  return line
end

----------------------------------------------------------------------------------------------------
-- Names, filters
----------------------------------------------------------------------------------------------------

local function normalizeRealm(realm)
  return (PN.Lower(realm):gsub(" ", ""):gsub("%-", ""))
end

-- "first name", "first name surname" or the same with "-realm", lower case, spaces and hyphens inside
-- the realm removed (the name itself goes through ns.PlayerName). The realm of the own server
-- (homeRealm, optional) is dropped, so "Anna" and "Anna-Home" share one key. nil for an empty or
-- oversized name.
function Logic.WhisperKey(name, homeRealm)
  if type(name) ~= "string" then
    return nil
  end
  local base, realm = PN.Clean(name):match("^([^%-]*)%-(.*)$")
  if not base then
    base, realm = PN.Clean(name), ""
  end
  base = PN.Lower(base:match("^(.-) *$"))
  realm = normalizeRealm(realm)
  if type(homeRealm) == "string" and realm == normalizeRealm(homeRealm) then
    realm = ""
  end
  if base == "" then
    return nil
  end
  local key = realm == "" and base or (base .. "-" .. realm)
  if #key > Limits.NAME_MAX_BYTES then
    return nil
  end
  return key
end

-- The name is on the "never store" list (compared by key).
function Logic.IsNeverSaved(neverList, name, homeRealm)
  local key = Logic.WhisperKey(name, homeRealm)
  if not key or type(neverList) ~= "table" then
    return false
  end
  for i = 1, math.min(#neverList, Limits.NEVER_MAX) do
    if Logic.WhisperKey(neverList[i], homeRealm) == key then
      return true
    end
  end
  return false
end

-- Master switch, window switch and the switch of the type.
function Logic.WindowTypeStored(settings, typeId)
  local name = Logic.TYPE_NAMES[typeId]
  if type(settings) ~= "table" or not name or name == "whisper" then
    return false
  end
  return settings.enabled == true
    and settings.windowsEnabled == true
    and type(settings.windowTypes) == "table"
    and settings.windowTypes[name] == true
end

-- Master switch, whisper switch and the "never store" list.
function Logic.WhisperStored(settings, name, homeRealm)
  if type(settings) ~= "table" or settings.enabled ~= true or settings.whispersEnabled ~= true then
    return false
  end
  return Logic.WhisperKey(name, homeRealm) ~= nil and not Logic.IsNeverSaved(settings.whisperNever, name, homeRealm)
end

-- Lines per window shown at login.
function Logic.RestoreLines(settings)
  local windowLines = cfg(settings, "windowLines")
  local value = type(settings) == "table" and settings.restoreLines or nil
  if type(value) ~= "number" or value ~= value then
    return windowLines
  end
  return math.floor(math.min(windowLines, math.max(0, value)) + 0.5)
end

----------------------------------------------------------------------------------------------------
-- Buffers
----------------------------------------------------------------------------------------------------

-- Removes the count oldest lines.
local function dropFront(lines, count)
  local total = #lines
  if count <= 0 then
    return
  end
  if count >= total then
    for i = total, 1, -1 do
      lines[i] = nil
    end
    return
  end
  for i = 1, total - count do
    lines[i] = lines[i + count]
  end
  for i = total, total - count + 1, -1 do
    lines[i] = nil
  end
end

-- Keeps the lines the predicate accepts, in order. Returns the number removed.
local function keepIf(lines, keep)
  local total, kept = #lines, 0
  for i = 1, total do
    local line = lines[i]
    if keep(line, i) then
      kept = kept + 1
      lines[kept] = line
    end
  end
  for i = total, kept + 1, -1 do
    lines[i] = nil
  end
  return total - kept
end

local function isBuffer(buffer)
  return type(buffer) == "table" and type(buffer.lines) == "table"
end

local function windowMap(history)
  return type(history) == "table" and type(history.windows) == "table" and history.windows or nil
end

local function contactMap(history)
  return type(history) == "table" and type(history.contacts) == "table" and history.contacts or nil
end

-- Calls fn(key, buffer) for every usable buffer of a map, keys in a fixed order.
local function eachBuffer(map, fn)
  if not map then
    return
  end
  local keys = {}
  for key, buffer in pairs(map) do
    if isBuffer(buffer) then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  for _, key in ipairs(keys) do
    fn(key, map[key])
  end
end

local function refreshLast(contact)
  local last = 0
  for _, line in ipairs(contact.lines) do
    last = math.max(last, lineTime(line))
  end
  contact.last = last
end

local function dropEmpty(map)
  for key, buffer in pairs(map) do
    if isBuffer(buffer) and #buffer.lines == 0 then
      map[key] = nil
    end
  end
end

local function countLines(map)
  local total = 0
  eachBuffer(map, function(_, buffer)
    total = total + #buffer.lines
  end)
  return total
end

function Logic.CountWindowLines(history)
  return countLines(windowMap(history))
end

function Logic.CountWhisperLines(history)
  return countLines(contactMap(history))
end

function Logic.CountContacts(history)
  local map, count = contactMap(history), 0
  eachBuffer(map, function()
    count = count + 1
  end)
  return count
end

-- Appends a line to a window and drops the oldest line when the window is full. The name is the title
-- shown for the id. Returns whether the line was stored.
function Logic.AppendWindow(history, windowId, windowName, line, settings)
  local map = windowMap(history)
  if not map or not isKey(windowId) or not isLine(line) then
    return false
  end
  local window = map[windowId]
  if not isBuffer(window) then
    window = { name = "", lines = {} }
    map[windowId] = window
  end
  if type(windowName) == "string" and windowName ~= "" then
    window.name = Limits.CutUtf8(windowName, Limits.NAME_MAX_BYTES)
  end
  window.lines[#window.lines + 1] = line
  dropFront(window.lines, #window.lines - cfg(settings, "windowLines"))
  return true
end

-- Appends a line to the conversation with the name. Returns its key, nil when nothing was stored.
function Logic.AppendWhisper(history, contactName, line, settings, homeRealm)
  local map = contactMap(history)
  local key = Logic.WhisperKey(contactName, homeRealm)
  if not map or not key or not isLine(line) then
    return nil
  end
  local contact = map[key]
  if not isBuffer(contact) then
    contact = { name = "", last = 0, lines = {} }
    map[key] = contact
  end
  contact.name = Limits.CutUtf8(PN.Clean(contactName), Limits.NAME_MAX_BYTES)
  contact.last = math.max(isTime(contact.last) and contact.last or 0, line[TIME])
  contact.lines[#contact.lines + 1] = line
  dropFront(contact.lines, #contact.lines - cfg(settings, "contactLines"))
  return key
end

----------------------------------------------------------------------------------------------------
-- Trimming. Every function returns the number of removed lines; the Preview functions count the
-- same without changing anything.
----------------------------------------------------------------------------------------------------

local function overLimit(map, limit)
  local removed = 0
  eachBuffer(map, function(_, buffer)
    removed = removed + math.max(0, #buffer.lines - limit)
  end)
  return removed
end

local function trimEach(map, limit)
  local removed = 0
  eachBuffer(map, function(_, buffer)
    local excess = #buffer.lines - limit
    if excess > 0 then
      dropFront(buffer.lines, excess)
      removed = removed + excess
    end
  end)
  return removed
end

-- Lines above the limit per window: the oldest of each window go.
function Logic.PreviewTrimWindowLines(history, limit)
  return overLimit(windowMap(history), Limits.Clamp("windowLines", limit))
end

function Logic.TrimWindowLines(history, limit)
  return trimEach(windowMap(history), Limits.Clamp("windowLines", limit))
end

function Logic.PreviewTrimContactLines(history, limit)
  return overLimit(contactMap(history), Limits.Clamp("contactLines", limit))
end

function Logic.TrimContactLines(history, limit)
  return trimEach(contactMap(history), Limits.Clamp("contactLines", limit))
end

-- Lines older than maxAgeDays at the clock value now are removed; empty buffers go with them.
local function pruneAge(map, maxAgeDays, now, isContact)
  if not map or not isTime(now) then
    return 0
  end
  local cutoff = now - maxAgeDays * Logic.SECONDS_PER_DAY
  local removed = 0
  eachBuffer(map, function(_, buffer)
    local gone = keepIf(buffer.lines, function(line)
      return lineTime(line) >= cutoff
    end)
    if gone > 0 and isContact and #buffer.lines > 0 then
      refreshLast(buffer)
    end
    removed = removed + gone
  end)
  dropEmpty(map)
  return removed
end

function Logic.PruneWindowAge(history, maxAgeDays, now)
  return pruneAge(windowMap(history), Limits.Clamp("windowDays", maxAgeDays), now, false)
end

function Logic.PruneWhisperAge(history, maxAgeDays, now)
  return pruneAge(contactMap(history), Limits.Clamp("whisperDays", maxAgeDays), now, true)
end

-- All lines of a buffer map, oldest first (ties by buffer key and position, so the order is fixed).
local function bufferEntries(map)
  local entries = {}
  eachBuffer(map, function(key, buffer)
    local tag = tostring(key)
    for index, line in ipairs(buffer.lines) do
      entries[#entries + 1] = { lineTime(line), tag, index, key }
    end
  end)
  table.sort(entries, function(a, b)
    if a[1] ~= b[1] then
      return a[1] < b[1]
    end
    if a[2] ~= b[2] then
      return a[2] < b[2]
    end
    return a[3] < b[3]
  end)
  return entries
end

-- Removes the marked lines, marks[bufferKey][index] = true; emptied buffers go too, `last` of the
-- others is recomputed when they are conversations.
local function sweepBuffers(map, marks, isContact)
  if not map then
    return
  end
  for key, set in pairs(marks) do
    local buffer = map[key]
    keepIf(buffer.lines, function(_, index)
      return not set[index]
    end)
    if isContact and #buffer.lines > 0 then
      refreshLast(buffer)
    end
  end
  dropEmpty(map)
end

local function markFirst(entries, count)
  local marks = {}
  for i = 1, count do
    local entry = entries[i]
    marks[entry[4]] = marks[entry[4]] or {}
    marks[entry[4]][entry[3]] = true
  end
  return marks
end

-- Total cap of all windows together: the oldest lines go, whatever the window.
function Logic.PreviewTrimWindowTotal(history, maxLines)
  return math.max(0, Logic.CountWindowLines(history) - Limits.Clamp("totalWindowLines", maxLines))
end

function Logic.TrimWindowTotal(history, maxLines)
  local map = windowMap(history)
  local excess = Logic.PreviewTrimWindowTotal(history, maxLines)
  if excess == 0 then
    return 0
  end
  sweepBuffers(map, markFirst(bufferEntries(map), excess), false)
  return excess
end

-- Total cap of all whispers: the oldest lines go, whatever the conversation. A conversation only
-- disappears when this empties it.
function Logic.PreviewTrimWhisperTotal(history, maxLines)
  return math.max(0, Logic.CountWhisperLines(history) - Limits.Clamp("totalWhisperLines", maxLines))
end

function Logic.TrimWhisperTotal(history, maxLines)
  local map = contactMap(history)
  local excess = Logic.PreviewTrimWhisperTotal(history, maxLines)
  if excess == 0 then
    return 0
  end
  sweepBuffers(map, markFirst(bufferEntries(map), excess), true)
  return excess
end

----------------------------------------------------------------------------------------------------
-- Size
----------------------------------------------------------------------------------------------------

local function lineBytes(line)
  if type(line) ~= "table" then
    return 0
  end
  local own = type(line[CHAR]) == "string" and #line[CHAR] or 0
  return Logic.LINE_OVERHEAD
    + (type(line[SENDER]) == "string" and #line[SENDER] or 0)
    + (type(line[TEXT]) == "string" and #line[TEXT] or 0)
    + own
end

local function bufferBytes(buffer)
  local total = Logic.BUFFER_OVERHEAD + (type(buffer.name) == "string" and #buffer.name or 0)
  for _, line in ipairs(buffer.lines) do
    total = total + lineBytes(line)
  end
  return total
end

local function mapBytes(map)
  local total = 0
  eachBuffer(map, function(_, buffer)
    total = total + bufferBytes(buffer)
  end)
  return total
end

-- Estimated bytes of the window history and the whisper history together (either may be nil). Walks
-- every line, so call it when writing or logging out, not per frame.
function Logic.EstimateBytes(windowHistory, whisperHistory)
  return mapBytes(windowMap(windowHistory)) + mapBytes(contactMap(whisperHistory))
end

-- "ok" below 80 percent of the limit, "warn" from 80 percent up to the limit, "over" above it.
function Logic.MemoryLevel(bytes, maxBytes)
  maxBytes = Limits.Clamp("maxBytes", maxBytes)
  local ratio = bytes / maxBytes
  if bytes > maxBytes then
    return "over", ratio
  elseif ratio >= Logic.WARN_RATIO then
    return "warn", ratio
  end
  return "ok", ratio
end

-- Marks one line for removal and returns the bytes it frees, the buffer overhead included when it
-- was the last line of its buffer.
local function evictLine(map, entry, left, marks)
  local buffer = map[entry[4]]
  local freed = lineBytes(buffer.lines[entry[3]])
  left[buffer] = (left[buffer] or #buffer.lines) - 1
  if left[buffer] == 0 then
    freed = freed + bufferBytes({ name = buffer.name, lines = {} })
  end
  marks[entry[4]] = marks[entry[4]] or {}
  marks[entry[4]][entry[3]] = true
  return freed
end

-- Over the memory limit the oldest lines go first, window and whisper lines alike (on a tie the window
-- line). Returns the removed window lines and whisper lines.
local function evictMemory(wmap, cmap, maxBytes)
  local total = mapBytes(wmap) + mapBytes(cmap)
  if total <= maxBytes then
    return 0, 0
  end
  local windows, whispers = bufferEntries(wmap), bufferEntries(cmap)
  local left, windowMarks, whisperMarks = {}, {}, {}
  local i, j = 1, 1
  while total > maxBytes and (i <= #windows or j <= #whispers) do
    local window, whisper = windows[i], whispers[j]
    if window and (not whisper or window[1] <= whisper[1]) then
      total = total - evictLine(wmap, window, left, windowMarks)
      i = i + 1
    else
      total = total - evictLine(cmap, whisper, left, whisperMarks)
      j = j + 1
    end
  end
  sweepBuffers(wmap, windowMarks, false)
  sweepBuffers(cmap, whisperMarks, true)
  return i - 1, j - 1
end

----------------------------------------------------------------------------------------------------
-- Compacting
----------------------------------------------------------------------------------------------------

-- Brings both histories (either may be nil) inside every limit of the settings: age, lines per
-- buffer, total caps, memory. now is the clock value (seconds) for the age rule.
-- Returns { windowLines, whisperLines } removed and the estimated bytes and level left.
function Logic.Compact(windowHistory, whisperHistory, settings, now)
  local report = { windowLines = 0, whisperLines = 0 }
  report.windowLines = Logic.PruneWindowAge(windowHistory, cfg(settings, "windowDays"), now)
    + Logic.TrimWindowLines(windowHistory, cfg(settings, "windowLines"))
    + Logic.TrimWindowTotal(windowHistory, cfg(settings, "totalWindowLines"))
  report.whisperLines = Logic.PruneWhisperAge(whisperHistory, cfg(settings, "whisperDays"), now)
    + Logic.TrimContactLines(whisperHistory, cfg(settings, "contactLines"))
    + Logic.TrimWhisperTotal(whisperHistory, cfg(settings, "totalWhisperLines"))
  local maxBytes = cfg(settings, "maxBytes")
  local windowLines, whisperLines = evictMemory(windowMap(windowHistory), contactMap(whisperHistory), maxBytes)
  report.windowLines = report.windowLines + windowLines
  report.whisperLines = report.whisperLines + whisperLines
  report.bytes = Logic.EstimateBytes(windowHistory, whisperHistory)
  report.level = Logic.MemoryLevel(report.bytes, maxBytes)
  return report
end

-- Copy of the buffers that shares the line tables, so trimming it leaves the original alone.
local function cloneMap(map)
  local out = {}
  for key, buffer in pairs(map or {}) do
    if isBuffer(buffer) then
      local lines = {}
      for index, line in ipairs(buffer.lines) do
        lines[index] = line
      end
      out[key] = { name = buffer.name, last = buffer.last, lines = lines }
    end
  end
  return out
end

-- The report Compact would give, nothing is changed. The caller asks "the oldest X lines will be
-- deleted" before it compacts after a limit was lowered.
function Logic.PreviewCompact(windowHistory, whisperHistory, settings, now)
  return Logic.Compact(
    { windows = cloneMap(windowMap(windowHistory)) },
    { contacts = cloneMap(contactMap(whisperHistory)) },
    settings,
    now
  )
end

----------------------------------------------------------------------------------------------------
-- Deleting
----------------------------------------------------------------------------------------------------

-- Each returns the number of deleted lines.
function Logic.ClearWindow(history, windowId)
  local map = windowMap(history)
  local window = map and map[windowId]
  if not isBuffer(window) then
    return 0
  end
  local count = #window.lines
  map[windowId] = nil
  return count
end

function Logic.ClearWindows(history)
  local count = Logic.CountWindowLines(history)
  if windowMap(history) then
    history.windows = {}
  end
  return count
end

-- Deletes the lines of one conversation (it disappears with them), nothing else. name: a key or any
-- spelling of the name.
function Logic.ClearContact(history, name, homeRealm)
  local map = contactMap(history)
  local key = Logic.WhisperKey(name, homeRealm)
  local contact = map and key and map[key]
  if not isBuffer(contact) then
    return 0
  end
  local count = #contact.lines
  map[key] = nil
  return count
end

function Logic.ClearWhispers(history)
  local count = Logic.CountWhisperLines(history)
  if contactMap(history) then
    history.contacts = {}
  end
  return count
end

-- Both histories; returns the deleted window lines and whisper lines.
function Logic.ClearAll(windowHistory, whisperHistory)
  return Logic.ClearWindows(windowHistory), Logic.ClearWhispers(whisperHistory)
end

----------------------------------------------------------------------------------------------------
-- Reading SavedVariables
----------------------------------------------------------------------------------------------------

local function cleanHistory(raw, field, isContact)
  if type(raw) ~= "table" then
    raw = {}
  end
  raw.v = Logic.VERSION
  if type(raw[field]) ~= "table" then
    raw[field] = {}
  end
  local map = raw[field]
  for key, buffer in pairs(map) do
    if not isKey(key) or not isBuffer(buffer) then
      map[key] = nil
    else
      keepIf(buffer.lines, isLine)
      if #buffer.lines == 0 then
        map[key] = nil
      else
        if type(buffer.name) ~= "string" then
          buffer.name = ""
        end
        if isContact then
          refreshLast(buffer)
        end
      end
    end
  end
  return raw
end

-- Makes the window history valid in place, so no line is copied at login: bad buffers and lines are
-- dropped. Returns the table, a new one when raw was no table.
function Logic.CleanWindowHistory(raw)
  return cleanHistory(raw, "windows", false)
end

-- The same for the whisper history; `last` of a contact is recomputed from its lines.
function Logic.CleanWhisperHistory(raw)
  return cleanHistory(raw, "contacts", true)
end
