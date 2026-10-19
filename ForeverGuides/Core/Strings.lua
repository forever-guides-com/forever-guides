-- Exchange strings with forever-guides.com. Format as accepted today by
-- POST /api/account/import:
-- LibDeflate EncodeForPrint(raw DEFLATE(JSON { v, type, exportedAt, data })),
-- no prefix. Known types there: character, talents, itemsSeen.
local _, ns = ...

local Strings = { VERSION = 1, MAX_INPUT = 64 * 1024, MAX_JSON = 2000000 }
ns.Strings = Strings

local function lib()
  return ns.LibDeflate
end

-- `host` (optional) names the display a layout string belongs to, for types that more than one display reads.
function Strings.envelope(kind, data, exportedAt, host)
  return { v = Strings.VERSION, type = kind, exportedAt = exportedAt or ns.U.now(), data = data, host = host }
end

function Strings.encode(kind, data, exportedAt, host)
  local LD = lib()
  if not LD then
    return nil, "LibDeflate missing"
  end
  local ok, json = pcall(ns.Json.encode, Strings.envelope(kind, data, exportedAt, host))
  if not ok then
    return nil, json
  end
  local compressed = LD:CompressDeflate(json)
  return LD:EncodeForPrint(compressed)
end

-- Returns envelope or nil, reason ("empty" | "too-large" | "decode" | "json" | "shape").
function Strings.decode(text)
  local LD = lib()
  text = ns.U.trim(text)
  if text == "" then
    return nil, "empty"
  end
  if #text > Strings.MAX_INPUT then
    return nil, "too-large"
  end
  -- Only the addon's own LibDeflate copy can stop inflating at MAX_JSON.
  if not (LD and LD._FG_MAX_OUTPUT) then
    return nil, "decode"
  end
  local okDecode, compressed = pcall(LD.DecodeForPrint, LD, text)
  if not okDecode or not compressed then
    return nil, "decode"
  end
  local okInflate, json, status = pcall(LD.DecompressDeflate, LD, compressed, Strings.MAX_JSON)
  if not okInflate or not json then
    return nil, status == -20 and "too-large" or "decode"
  end
  if #json > Strings.MAX_JSON then
    return nil, "too-large"
  end
  local ok, env = pcall(ns.Json.decode, json)
  if not ok then
    return nil, "json"
  end
  if type(env) ~= "table" or type(env.type) ~= "string" or type(env.data) ~= "table" or type(env.v) ~= "number" then
    return nil, "shape"
  end
  return env
end
