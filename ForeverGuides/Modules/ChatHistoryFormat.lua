-- Chat history, display: turns stored lines back into chat window text, dimmed in the color of their
-- chat type, plus the "history until" divider. Pure: colors, clock and strings come in as parameters.
--
-- opts = {
--   colors  table type key (ChatTypeInfo: "SAY", "GUILD", ...) -> { r, g, b }, optional
--   date    function(format, time) like the game's date(), default date or os.date
--   now     clock value of today, for the divider
--   L       strings (ns.L), keys chathistory.marker and chathistory.formatDate
-- }
local _, ns = ...

local Logic = ns.ChatHistoryLogic

local Format = {}
ns.ChatHistoryFormat = Format

local TIME, TYPE, SENDER, TEXT = Logic.FIELDS.TIME, Logic.FIELDS.TYPE, Logic.FIELDS.SENDER, Logic.FIELDS.TEXT

-- Share of the chat type color that stays; grey when the type has no color.
Format.DIM = 0.6
Format.GREY = { r = 0.6, g = 0.6, b = 0.6 }

-- ChatTypeInfo key of every stored type.
Format.COLOR_KEYS = {
  say = "SAY",
  yell = "YELL",
  party = "PARTY",
  raid = "RAID",
  guild = "GUILD",
  officer = "OFFICER",
  channel = "CHANNEL",
  emote = "EMOTE",
  system = "SYSTEM",
  whisper = "WHISPER",
}

ns.AddLocale("enUS", {
  ["chathistory.marker"] = "History until %s",
  ["chathistory.formatDate"] = "%m/%d %H:%M",
})
ns.AddLocale("deDE", {
  ["chathistory.marker"] = "Verlauf bis %s",
  ["chathistory.formatDate"] = "%d.%m. %H:%M",
})

local function isUnit(value)
  return type(value) == "number" and value >= 0 and value <= 1
end

local function hex(value)
  return math.floor(value * 255 + 0.5)
end

local function colorCode(color)
  return string.format("|cff%02x%02x%02x", hex(color.r), hex(color.g), hex(color.b))
end

-- "|cffrrggbb" of the dimmed color of a stored type, grey for an unknown type or a damaged color.
function Format.DimColor(typeId, colors)
  local key = Format.COLOR_KEYS[Logic.TYPE_NAMES[typeId]]
  local color = type(colors) == "table" and key and colors[key] or nil
  if type(color) ~= "table" or not (isUnit(color.r) and isUnit(color.g) and isUnit(color.b)) then
    return colorCode(Format.GREY)
  end
  return colorCode({ r = color.r * Format.DIM, g = color.g * Format.DIM, b = color.b * Format.DIM })
end

local function dateFunction(opts)
  local fn = opts and opts.date or rawget(_G, "date") or (os and os.date)
  return function(pattern, time)
    local ok, text = pcall(fn, pattern, time)
    return ok and type(text) == "string" and text or "--:--"
  end
end

local function strings(opts)
  return opts and opts.L or ns.L
end

-- "HH:MM" of a line time.
function Format.Stamp(time, opts)
  return dateFunction(opts)("%H:%M", time)
end

-- A player name as a chat link; plain text when the name could break the link.
function Format.PlayerName(name)
  if name == "" or name:find("[|:%c]") then
    return name
  end
  return "|Hplayer:" .. name .. "|h[" .. name .. "]|h"
end

-- Every color end inside the text is followed by the dim color again, so the rest of the line stays dim.
local function keepColor(text, color)
  return (text:gsub("(|+)r", function(bars)
    if #bars % 2 == 1 then
      return bars .. "r" .. color
    end
  end))
end

-- One stored line as window text, nil for a line of an unknown type. Say, yell, group, guild and
-- channel lines read "[HH:MM] Sender: Text", emotes "[HH:MM] Sender Text", system lines and text
-- emotes (no stored sender) "[HH:MM] Text".
function Format.Line(line, opts)
  local typeName = Logic.TYPE_NAMES[line[TYPE]]
  if not typeName then
    return nil
  end
  local sender, text = line[SENDER], line[TEXT]
  local body
  if sender == "" then
    body = text
  elseif typeName == "emote" then
    body = Format.PlayerName(sender) .. " " .. text
  else
    body = Format.PlayerName(sender) .. ": " .. text
  end
  local color = Format.DimColor(line[TYPE], opts and opts.colors)
  return color .. "[" .. Format.Stamp(line[TIME], opts) .. "] " .. keepColor(body, color) .. "|r"
end

-- The time behind "History until": the clock time of today's lines, date and time of older ones.
function Format.TimeLabel(time, opts)
  local date = dateFunction(opts)
  local now = opts and opts.now
  if type(now) == "number" and date("%Y%m%d", time) ~= date("%Y%m%d", now) then
    return date(strings(opts)["chathistory.formatDate"], time)
  end
  return date("%H:%M", time)
end

-- "----- History until 18:42 -----" in grey.
function Format.Marker(time, opts)
  local text = string.format(strings(opts)["chathistory.marker"], Format.TimeLabel(time, opts))
  return colorCode(Format.GREY) .. "----- " .. text .. " -----|r"
end

-- The window text for a buffer: its last `count` lines oldest first, then the divider (opts.marker)
-- when there was at least one line. An empty list when count is 0 or the buffer holds nothing.
function Format.WindowLines(buffer, count, opts)
  local out = {}
  local lines = type(buffer) == "table" and buffer.lines or nil
  if type(lines) ~= "table" or type(count) ~= "number" or count <= 0 then
    return out
  end
  local last
  for i = math.max(1, #lines - count + 1), #lines do
    local text = Format.Line(lines[i], opts)
    if text then
      out[#out + 1] = text
      last = lines[i]
    end
  end
  if last and opts and opts.marker then
    out[#out + 1] = Format.Marker(last[TIME], opts)
  end
  return out
end
