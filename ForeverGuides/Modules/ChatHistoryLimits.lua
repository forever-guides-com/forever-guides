-- Chat and whisper history, limits and settings. One place for every default, minimum and maximum; the
-- settings table is clamped with it whenever SavedVariables are read, so a hand edited file cannot
-- exceed a hard cap. No game access.
local _, ns = ...

local Limits = {}
ns.ChatHistoryLimits = Limits

local MB = 1048576

-- Numeric settings by key. Whole numbers only.
Limits.NUMBERS = {
  totalWindowLines = { default = 5000, min = 500, max = 10000 },
  totalWhisperLines = { default = 20000, min = 1000, max = 50000 },
  maxBytes = { default = 4 * MB, min = 1 * MB, max = 10 * MB },
  maxChars = { default = 512, min = 255, max = 1024 },
  windowLines = { default = 250, min = 50, max = 1000 },
  windowDays = { default = 30, min = 1, max = 365 },
  contactLines = { default = 250, min = 25, max = 1000 },
  whisperDays = { default = 90, min = 7, max = 365 },
  whisperRestore = { default = 50, min = 0, max = 250 },
  autoCloseMinutes = { default = 15, min = 1, max = 120 },
  inputLines = { default = 250, min = 10, max = 500 },
}

-- enabled is the master switch and opt-in: nothing is recorded or restored until the player turns it on.
Limits.BOOLEANS = {
  enabled = false,
  clearOnLogout = false,
  windowsEnabled = true,
  whispersEnabled = true,
  autoClose = false,
  inputEnabled = true,
  inputPersist = true,
  inputSlash = false,
  inputTarget = true,
  inputSwitch = true,
  inputPlain = true,
  restoreEnabled = true,
  restoreMarker = true,
}

-- Chat types that can be switched one by one, in display order, with their default.
Limits.WINDOW_TYPES = {
  { name = "say", default = true },
  { name = "yell", default = true },
  { name = "party", default = true },
  { name = "raid", default = true },
  { name = "guild", default = true },
  { name = "officer", default = true },
  { name = "channel", default = true },
  { name = "emote", default = true },
  { name = "system", default = false },
}

Limits.WHISPER_MODES = { "inline", "tab", "window" }
Limits.WHISPER_MODE_DEFAULT = "tab"

-- restoreLines: number of lines per window shown at login, 0 up to windowLines, or this word for "as
-- many as the window keeps".
Limits.RESTORE_FOLLOW = "window"

-- Whispers that are never stored: at most this many entries of at most this many bytes.
Limits.NEVER_MAX = 100
Limits.NAME_MAX_BYTES = 96

local function isNumber(value)
  return type(value) == "number" and value == value
end

-- Clamps to min and max, rounds to a whole number. Anything but a number gives the default, +-inf the bound.
local function clampNumber(value, default, min, max)
  if not isNumber(value) then
    return default
  end
  return math.floor(math.min(max, math.max(min, value)) + 0.5)
end

function Limits.Clamp(key, value)
  local spec = Limits.NUMBERS[key]
  if not spec then
    return nil
  end
  return clampNumber(value, spec.default, spec.min, spec.max)
end

-- Cuts to at most maxBytes bytes without splitting a multibyte character.
function Limits.CutUtf8(text, maxBytes)
  if #text <= maxBytes then
    return text
  end
  local cut = maxBytes
  while cut > 0 do
    local byte = text:byte(cut + 1)
    -- 0x80 to 0xBF continue a character; anything else starts one.
    if byte < 0x80 or byte >= 0xC0 then
      break
    end
    cut = cut - 1
  end
  return text:sub(1, cut)
end

function Limits.Defaults()
  local out = {}
  for key, spec in pairs(Limits.NUMBERS) do
    out[key] = spec.default
  end
  for key, value in pairs(Limits.BOOLEANS) do
    out[key] = value
  end
  out.windowTypes = {}
  for _, entry in ipairs(Limits.WINDOW_TYPES) do
    out.windowTypes[entry.name] = entry.default
  end
  out.whisperMode = Limits.WHISPER_MODE_DEFAULT
  out.whisperNever = {}
  out.restoreLines = Limits.RESTORE_FOLLOW
  return out
end

local function cleanNever(raw)
  local out, seen = {}, {}
  if type(raw) ~= "table" then
    return out
  end
  for _, entry in ipairs(raw) do
    if #out >= Limits.NEVER_MAX then
      break
    end
    if type(entry) == "string" then
      entry = Limits.CutUtf8(entry:match("^%s*(.-)%s*$"), Limits.NAME_MAX_BYTES)
      if entry ~= "" and not seen[entry] then
        seen[entry] = true
        out[#out + 1] = entry
      end
    end
  end
  return out
end

-- A complete settings table from whatever SavedVariables hold: unknown keys dropped, wrong types back
-- to the default, numbers clamped and rounded, enums validated. Never modifies raw.
function Limits.Normalize(raw)
  local out = Limits.Defaults()
  if type(raw) ~= "table" then
    return out
  end
  for key, spec in pairs(Limits.NUMBERS) do
    out[key] = clampNumber(raw[key], spec.default, spec.min, spec.max)
  end
  for key, default in pairs(Limits.BOOLEANS) do
    if type(raw[key]) == "boolean" then
      out[key] = raw[key]
    else
      out[key] = default
    end
  end
  if type(raw.windowTypes) == "table" then
    for _, entry in ipairs(Limits.WINDOW_TYPES) do
      if type(raw.windowTypes[entry.name]) == "boolean" then
        out.windowTypes[entry.name] = raw.windowTypes[entry.name]
      end
    end
  end
  for _, mode in ipairs(Limits.WHISPER_MODES) do
    if raw.whisperMode == mode then
      out.whisperMode = mode
    end
  end
  out.whisperNever = cleanNever(raw.whisperNever)
  if isNumber(raw.restoreLines) then
    out.restoreLines = clampNumber(raw.restoreLines, 0, 0, out.windowLines)
  end
  return out
end
