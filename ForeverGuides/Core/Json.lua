-- Minimal JSON for the web exchange strings. Object keys are sorted so the
-- same data always yields the same string.
local _, ns = ...

local Json = {}
ns.Json = Json

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ESCAPES[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function isArray(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then
      return false
    end
  end
  return true
end

local encodeValue

local function encodeNumber(v)
  if v ~= v or v == math.huge or v == -math.huge then
    return "null"
  end
  if v == math.floor(v) and math.abs(v) < 2 ^ 53 then
    return string.format("%.0f", v)
  end
  return string.format("%.14g", v)
end

encodeValue = function(v)
  local kind = type(v)
  if kind == "string" then
    return encodeString(v)
  elseif kind == "number" then
    return encodeNumber(v)
  elseif kind == "boolean" then
    return tostring(v)
  elseif kind == "nil" then
    return "null"
  elseif kind == "table" then
    local parts = {}
    if isArray(v) then
      for i = 1, #v do
        parts[i] = encodeValue(v[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for _, k in ipairs(ns.U.sortedKeys(v)) do
      parts[#parts + 1] = encodeString(tostring(k)) .. ":" .. encodeValue(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("json: cannot encode " .. kind)
end

Json.encode = encodeValue

local function utf8char(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  end
  return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local function skip(str, pos)
  local _, stop = str:find("^%s*", pos)
  return stop + 1
end

local decodeValue
local SIMPLE = { n = "\n", r = "\r", t = "\t", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }

local function decodeString(str, pos)
  pos = pos + 1
  local parts = {}
  while true do
    local c = str:sub(pos, pos)
    if c == "" then
      error("json: unterminated string")
    elseif c == '"' then
      return table.concat(parts), pos + 1
    elseif c == "\\" then
      local n = str:sub(pos + 1, pos + 1)
      if n == "u" then
        local cp = tonumber(str:sub(pos + 2, pos + 5), 16)
        if not cp then
          error("json: bad unicode escape")
        end
        parts[#parts + 1] = utf8char(cp)
        pos = pos + 6
      else
        parts[#parts + 1] = SIMPLE[n] or n
        pos = pos + 2
      end
    else
      local stop = str:find('["\\]', pos) or (#str + 1)
      parts[#parts + 1] = str:sub(pos, stop - 1)
      pos = stop
    end
  end
end

local MAX_DEPTH = 32

local function decodeContainer(str, pos, closer, isObject, depth)
  if depth > MAX_DEPTH then
    error("json: nested too deep")
  end
  local result = {}
  pos = skip(str, pos + 1)
  if str:sub(pos, pos) == closer then
    return result, pos + 1
  end
  while true do
    local key
    if isObject then
      if str:sub(pos, pos) ~= '"' then
        error("json: expected key")
      end
      key, pos = decodeString(str, pos)
      pos = skip(str, pos)
      if str:sub(pos, pos) ~= ":" then
        error("json: expected ':'")
      end
      pos = skip(str, pos + 1)
    end
    local value
    value, pos = decodeValue(str, pos, depth)
    if isObject then
      result[key] = value
    else
      result[#result + 1] = value
    end
    pos = skip(str, pos)
    local c = str:sub(pos, pos)
    if c == "," then
      pos = skip(str, pos + 1)
    elseif c == closer then
      return result, pos + 1
    else
      error("json: malformed container")
    end
  end
end

decodeValue = function(str, pos, depth)
  pos = skip(str, pos)
  local c = str:sub(pos, pos)
  if c == '"' then
    return decodeString(str, pos)
  elseif c == "{" then
    return decodeContainer(str, pos, "}", true, depth + 1)
  elseif c == "[" then
    return decodeContainer(str, pos, "]", false, depth + 1)
  elseif str:sub(pos, pos + 3) == "true" then
    return true, pos + 4
  elseif str:sub(pos, pos + 4) == "false" then
    return false, pos + 5
  elseif str:sub(pos, pos + 3) == "null" then
    return nil, pos + 4
  end
  local num = str:match("^-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
  if not num or not tonumber(num) then
    error("json: malformed value at " .. pos)
  end
  return tonumber(num), pos + #num
end

function Json.decode(str)
  local value, pos = decodeValue(str, 1, 0)
  if skip(str, pos) <= #str then
    error("json: trailing data")
  end
  return value
end
