-- Share codes: a view of the add-on (page, tab, selection) as one short code "FG-7K2Q9XMA", the same for the game and
-- the website. The code is the compact binary form of the payload "page[/part[/part...]]" of PageShareLogic,
-- written in Crockford base32 with a check symbol, and it decodes without a server. Pure functions, no game access.
-- The layout, the tables and the rules for changing them are in docs/SHARE-CODE.md.
local _, ns = ...

local SCL = {}
ns.ShareCodeLogic = SCL

SCL.VERSION = 1
SCL.PREFIX = "FG-"
-- Crockford base32 without I, L, O and U. Decoding reads O as 0 and I and L as 1.
SCL.ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
-- A code is never longer (a page outside the table carries its path as text, at most 100 characters).
SCL.MAX_CODE = 200
SCL.MAX_PARAMS = 3
SCL.MAX_NUMBER = 4294967295
SCL.MAX_STRING = 40

-- Append only: the position is part of every code ever shared. Position 0 is reserved for "path as text".
SCL.PAGES = {
  "instances",
  "professions",
  "reputation",
  "itemsets",
  "settings",
  "classes",
  "trainers",
  "weapons",
  "levels",
  "gathering",
  "professionroute",
  "proftrainers",
  "legacy",
  "map",
  "waypoints",
  "notes",
  "drawings",
  "dashboard",
  "search",
  "help",
  "tutorials",
  "changelog",
  "character",
  "chars",
  "guild",
  "inspect",
  "talents",
  "vendors",
  "loot",
  "macros",
  "shots",
  "contacts",
  "calc",
  "durability",
  "xpbar",
  "cursor",
  "areas",
  "windows",
  "errors",
  "items",
  "lockpicking",
  "comprehension",
  "console",
  "pets",
  "librarybooks",
  "wishlist",
  "mounts",
  "legendaries",
}

-- Append only as well: tabs, classes and professions that appear as a part of a route.
SCL.WORDS = {
  "bosses",
  "quests",
  "items",
  "access",
  "map",
  "info",
  "classes",
  "races",
  "overview",
  "WARRIOR",
  "PALADIN",
  "HUNTER",
  "ROGUE",
  "PRIEST",
  "SHAMAN",
  "MAGE",
  "WARLOCK",
  "DRUID",
  "alchemy",
  "blacksmithing",
  "cooking",
  "enchanting",
  "engineering",
  "first-aid",
  "fishing",
  "herbalism",
  "leatherworking",
  "mining",
  "skinning",
  "tailoring",
}

-- What the parts after the page mean, per page and position. Without an entry a part is a plain value:
-- "instance" is the numeric id of the instance (the caller resolves slug and id), "setid" is "s<number>".
SCL.SCHEMA = {
  instances = { "instance", "value" },
  itemsets = { "setid" },
}

local PAGE_INDEX, WORD_INDEX = {}, {}
for i, id in ipairs(SCL.PAGES) do
  PAGE_INDEX[id] = i
end
for i, word in ipairs(SCL.WORDS) do
  WORD_INDEX[word] = i
end

local NUMBER, WORD, STRING = 0, 1, 2

local floor = math.floor

-- Writing and reading -----------------------------------------------------------------------------------------

-- LEB128 style: seven bits per byte, the high bit says that more follow.
local function putVarint(bytes, n)
  while n >= 128 do
    bytes[#bytes + 1] = n % 128 + 128
    n = floor(n / 128)
  end
  bytes[#bytes + 1] = n
end

local function getVarint(bytes, pos)
  local n, scale = 0, 1
  for _ = 1, 6 do
    local b = bytes[pos]
    if not b then
      return nil
    end
    pos = pos + 1
    n = n + (b % 128) * scale
    if b < 128 then
      return n, pos
    end
    scale = scale * 128
  end
end

local function putText(bytes, text)
  for i = 1, #text do
    bytes[#bytes + 1] = text:byte(i)
  end
end

-- Symbols (0..31) of a list of bytes, the last one padded with zero bits.
local function toSymbols(bytes)
  local out, acc, bits = {}, 0, 0
  for _, b in ipairs(bytes) do
    acc, bits = acc * 256 + b, bits + 8
    while bits >= 5 do
      bits = bits - 5
      out[#out + 1] = floor(acc / 2 ^ bits)
      acc = acc % 2 ^ bits
    end
  end
  if bits > 0 then
    out[#out + 1] = acc * 2 ^ (5 - bits)
  end
  return out
end

-- Bytes of a list of symbols, nil when the padding is not the zero bits an encoder writes.
local function toBytes(symbols)
  local out, acc, bits = {}, 0, 0
  for _, v in ipairs(symbols) do
    acc, bits = acc * 32 + v, bits + 5
    if bits >= 8 then
      bits = bits - 8
      out[#out + 1] = floor(acc / 2 ^ bits)
      acc = acc % 2 ^ bits
    end
  end
  if acc ~= 0 or bits >= 5 then
    return nil
  end
  return out
end

-- The check symbol: every symbol counts with an odd weight, so a single wrong symbol always changes it.
local function checkSymbol(symbols)
  local sum = 0
  for i, v in ipairs(symbols) do
    sum = sum + (2 * i - 1) * v
  end
  return sum % 32
end

-- Encoding --------------------------------------------------------------------------------------------------

-- opts.instanceId(slug) -> number or nil. A part the table does not know is written as text.
local function putPart(bytes, part, kind, opts)
  local number
  if kind == "instance" then
    number = opts and opts.instanceId and opts.instanceId(part)
  elseif kind == "setid" then
    number = tonumber(part:match("^s([1-9]%d*)$"))
  elseif part:find("^[1-9]%d*$") or part == "0" then
    number = tonumber(part)
  end
  if number and number >= 0 and number <= SCL.MAX_NUMBER and number == floor(number) then
    putVarint(bytes, number * 4 + NUMBER)
  elseif WORD_INDEX[part] then
    putVarint(bytes, WORD_INDEX[part] * 4 + WORD)
  else
    putVarint(bytes, #part * 4 + STRING)
    putText(bytes, part)
  end
end

-- "FG-..." for a payload "page/part/..." of PageShareLogic (already validated by the caller), nil when it does
-- not fit.
function SCL.Encode(payload, opts)
  if type(payload) ~= "string" or payload == "" then
    return nil
  end
  local parts = {}
  for part in (payload .. "/"):gmatch("([^/]*)/") do
    parts[#parts + 1] = part
  end
  local bytes = { SCL.VERSION }
  local index = PAGE_INDEX[parts[1]]
  if index and #parts - 1 <= SCL.MAX_PARAMS then
    putVarint(bytes, index)
    local schema = SCL.SCHEMA[parts[1]] or {}
    for i = 2, #parts do
      if parts[i] == "" or #parts[i] > SCL.MAX_STRING then
        return nil
      end
      putPart(bytes, parts[i], schema[i - 1], opts)
    end
  else
    putVarint(bytes, 0)
    putText(bytes, payload)
  end
  local symbols = toSymbols(bytes)
  symbols[#symbols + 1] = checkSymbol(symbols)
  local chars = {}
  for i, v in ipairs(symbols) do
    chars[i] = SCL.ALPHABET:sub(v + 1, v + 1)
  end
  local code = SCL.PREFIX .. table.concat(chars)
  return #code <= SCL.MAX_CODE and code or nil
end

-- Decoding --------------------------------------------------------------------------------------------------

local VALUE = {}
for i = 1, #SCL.ALPHABET do
  VALUE[SCL.ALPHABET:sub(i, i)] = i - 1
end
VALUE.O, VALUE.I, VALUE.L = 0, 1, 1

-- The symbols of a typed or pasted code (any case, spaces and dashes inside are ignored), nil when it is not one.
local function symbolsOf(text)
  if type(text) ~= "string" or #text > SCL.MAX_CODE + 40 then
    return nil
  end
  local body = text:upper():gsub("[%s_]", "")
  body = body:match("^FG%-(.+)$")
  if not body then
    return nil
  end
  body = body:gsub("%-", "")
  if #body < 3 or #body > SCL.MAX_CODE then
    return nil
  end
  local symbols = {}
  for i = 1, #body do
    local v = VALUE[body:sub(i, i)]
    if not v then
      return nil
    end
    symbols[i] = v
  end
  return symbols
end

-- True for a text that looks like a code (starts with "FG-"), whether or not it is a valid one.
function SCL.LooksLikeCode(text)
  return type(text) == "string" and text:upper():match("^%s*FG%-[%w%-]+%s*$") ~= nil
end

-- The code inside what a player pasted: "fg-04ng5", "04NG5", or a chat line that ends in the code. The prefix is
-- optional, nil for an empty text. Whether the result is a valid code is up to SCL.Decode.
function SCL.Normalize(text)
  if type(text) ~= "string" then
    return nil
  end
  local upper = text:upper()
  local found
  for code in upper:gmatch("FG%-[%w%-]+") do
    found = code
  end
  if found then
    return found
  end
  local body = upper:match("^%s*([%w%-%s]+)%s*$")
  body = body and body:gsub("%s", "")
  if not body or body == "" then
    return nil
  end
  return SCL.PREFIX .. body
end

-- opts.instanceSlug(id) -> slug or nil. The payload of a code, else nil and a reason: "format" (not a code or
-- damaged), "check" (a typo), "version" (made by a newer add-on), "unknown" (a page or value this table lacks).
function SCL.Decode(text, opts)
  local symbols = symbolsOf(text)
  if not symbols then
    return nil, "format"
  end
  local check = table.remove(symbols)
  if checkSymbol(symbols) ~= check then
    return nil, "check"
  end
  local bytes = toBytes(symbols)
  if not bytes or #bytes < 2 then
    return nil, "format"
  end
  if bytes[1] > SCL.VERSION then
    return nil, "version"
  elseif bytes[1] ~= SCL.VERSION then
    return nil, "format"
  end
  local index, pos = getVarint(bytes, 2)
  if not index then
    return nil, "format"
  end
  if index == 0 then
    local chars = {}
    for i = pos, #bytes do
      if bytes[i] < 32 or bytes[i] > 126 then
        return nil, "format"
      end
      chars[#chars + 1] = string.char(bytes[i])
    end
    if #chars == 0 then
      return nil, "format"
    end
    return table.concat(chars)
  end
  local page = SCL.PAGES[index]
  if not page then
    return nil, "unknown"
  end
  local schema = SCL.SCHEMA[page] or {}
  local parts = { page }
  while pos <= #bytes do
    local tag
    tag, pos = getVarint(bytes, pos)
    if not tag or #parts > SCL.MAX_PARAMS then
      return nil, "format"
    end
    local kind, value = tag % 4, floor(tag / 4)
    local part
    if kind == NUMBER then
      local want = schema[#parts]
      if want == "instance" then
        part = opts and opts.instanceSlug and opts.instanceSlug(value)
      elseif want == "setid" then
        part = "s" .. string.format("%d", value)
      else
        part = string.format("%d", value)
      end
      if not part then
        return nil, "unknown"
      end
    elseif kind == WORD then
      part = SCL.WORDS[value]
      if not part then
        return nil, "unknown"
      end
    elseif kind == STRING and value > 0 and value <= SCL.MAX_STRING and pos + value - 1 <= #bytes then
      local chars = {}
      for i = pos, pos + value - 1 do
        chars[#chars + 1] = string.char(bytes[i])
      end
      part = table.concat(chars)
      pos = pos + value
    else
      return nil, "format"
    end
    parts[#parts + 1] = part
  end
  return table.concat(parts, "/")
end

-- Chat ------------------------------------------------------------------------------------------------------

-- The readable lead of a share in Say and Yell followed by the code: "[Addon Forever Guides (Page): ...] FG-...".
-- Replaces the first one convert(code) accepts (it returns the replacement text or nil). Returns the new message
-- or nil when nothing changed.
function SCL.Rewrite(msg, convert)
  if type(msg) ~= "string" or #msg > 1024 or not msg:find("%[Addon Forever Guides") then
    return nil
  end
  local done = false
  local out = msg:gsub("%[Addon Forever Guides[^%[%]|]*%]%s*([Ff][Gg]%-[%w%-]+)", function(code)
    if done then
      return nil
    end
    local replacement = convert(code)
    if replacement then
      done = true
    end
    return replacement
  end)
  return done and out or nil
end
