-- Location screenshots, pure data part: entries in ForeverGuidesDB.shots, hash
-- chain, limit, status, exchange strings (type "shots") and the file name the
-- game gives the screenshot. The checksum only detects accidental or manual
-- changes. It is not a security feature, anyone can recompute it.
local _, ns = ...
local U = ns.U

local S = { MAX = 200, MAX_PER_STRING = 100, MAX_ZONE = 60, unsaved = 0 }
ns.ShotLogic = S

local HEX = "0123456789abcdef"

local function xor8(a, b)
  local r, bit = 0, 1
  for _ = 1, 8 do
    local x, y = a % 2, b % 2
    if x ~= y then
      r = r + bit
    end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return r
end

-- FNV-1a, 32 bit, without a bit library (multiplier 2^24 + 403, split to stay below 2^53).
local function fnv(str, basis)
  local h = basis
  for i = 1, #str do
    local low = h % 256
    h = h - low + xor8(low, str:byte(i))
    h = ((h % 256) * 16777216 + h * 403) % 4294967296
  end
  return h
end

local function hex8(n)
  local out = {}
  for i = 8, 1, -1 do
    local d = n % 16
    out[i] = HEX:sub(d + 1, d + 1)
    n = math.floor(n / 16)
  end
  return table.concat(out)
end

-- 16 hex characters: two FNV-1a runs with different bases, the second over length plus text.
function S.checksum(str)
  return hex8(fnv(str, 2166136261)) .. hex8(fnv(#str .. ":" .. str, 2654435769))
end

local function fx(v, digits)
  return type(v) == "number" and string.format("%." .. digits .. "f", v) or ""
end

local function cleanText(s)
  s = tostring(s or ""):gsub("[%c|]", " ")
  return (U.trim(s):sub(1, S.MAX_ZONE))
end

-- Everything except id, status and the hash itself goes into the checksum.
function S.canon(e)
  return table.concat({
    tostring(e.n),
    tostring(e.t),
    tostring(e.zone),
    tostring(e.sub),
    tostring(e.map or ""),
    fx(e.x, 4),
    fx(e.y, 4),
    fx(e.face, 3),
    tostring(e.build),
    tostring(e.ver),
    tostring(e.prev),
  }, "|")
end

function S.hashOf(e)
  return S.checksum(e.prev .. "|" .. S.canon(e))
end

local function dateFn()
  return rawget(_G, "date") or (os and os.date)
end

function S.stamp(t)
  local d = dateFn()
  return d and d("%Y-%m-%d %H:%M:%S", t) or tostring(t)
end

-- Name the game gives screenshots: WoWScrnShot_MMDDYY_HHMMSS (+ .jpg/.png/.tga), local time.
function S.fileName(t)
  local d = dateFn()
  return "WoWScrnShot_" .. (d and d("%m%d%y_%H%M%S", t) or tostring(t))
end

-- Parses the time out of a screenshot file name (as the web page does); nil if it does not match.
function S.parseFileName(name)
  local mm, dd, yy, hh, mi, ss = tostring(name):match("WoWScrnShot_(%d%d)(%d%d)(%d%d)_(%d%d)(%d%d)(%d%d)")
  if not mm then
    return nil
  end
  local t = os
    and os.time
    and os.time({
      year = 2000 + tonumber(yy),
      month = tonumber(mm),
      day = tonumber(dd),
      hour = tonumber(hh),
      min = tonumber(mi),
      sec = tonumber(ss),
    })
  return t
end

-- File names within +-2 seconds of entry.t (what the web page uses to pair).
function S.matches(entry, fileName, tolerance)
  local t = S.parseFileName(fileName)
  return t ~= nil and math.abs(t - entry.t) <= (tolerance or 2)
end

-- Formats the game can write (CVar screenshotFormat: "jpeg", "png", "tga"; the file ends in .jpg for jpeg).
S.EXTS = { "jpg", "png", "tga" }
-- Seconds around entry.t to try: the file is named when the game writes it, a frame or two later.
S.DRIFT = { 0, 1, -1, 2, -2 }

-- "jpeg"/"jpg" -> "jpg", "png", "tga"; nil for anything else.
function S.formatExt(value)
  local v = tostring(value or ""):lower()
  if v == "jpeg" then
    return "jpg"
  end
  for _, ext in ipairs(S.EXTS) do
    if v == ext then
      return ext
    end
  end
  return nil
end

-- File name stem of an entry (no extension), also for imported entries without one.
function S.fileStem(e)
  if type(e.file) == "string" and e.file ~= "" then
    return e.file
  end
  return S.fileName(type(e.t) == "number" and e.t or 0)
end

-- The name to look for, e.g. WoWScrnShot_100526_140309.jpg. ext: CVar value or extension, default jpg.
function S.expectedName(e, ext)
  return S.fileStem(e) .. "." .. (S.formatExt(ext) or "jpg")
end

-- All names worth trying for a preview: the current format first, each with +-2 s drift.
function S.candidateNames(e, ext)
  local first = S.formatExt(ext) or "jpg"
  local exts = { first }
  for _, x in ipairs(S.EXTS) do
    if x ~= first then
      exts[#exts + 1] = x
    end
  end
  local out = {}
  if type(e.t) ~= "number" then
    return out
  end
  for _, x in ipairs(exts) do
    for _, d in ipairs(S.DRIFT) do
      out[#out + 1] = S.fileName(e.t + d) .. "." .. x
    end
  end
  return out
end

-- Store ------------------------------------------------------------------------------

function S.items()
  if type(ns.db.shots) ~= "table" then
    ns.db.shots = {}
  end
  return ns.db.shots
end

function S.meta()
  local m = ns.db.shotMeta
  if type(m) ~= "table" then
    m = {}
    ns.db.shotMeta = m
  end
  if type(m.seq) ~= "number" or type(m.last) ~= "string" then
    local seq, last = 0, ""
    for _, e in ipairs(S.items()) do
      if type(e) == "table" and type(e.n) == "number" and e.n >= seq then
        seq, last = e.n, tostring(e.h or "")
      end
    end
    m.seq, m.last = seq, last
  end
  return m
end

S.random = function(n)
  return math.random(n)
end

local ID_CHARS = "abcdefghjkmnpqrstuvwxyz23456789"

function S.newId()
  local taken = {}
  for _, e in ipairs(S.items()) do
    taken[tostring(e.id)] = true
  end
  for _ = 1, 20 do
    local out = {}
    for i = 1, 8 do
      local k = S.random(#ID_CHARS)
      out[i] = ID_CHARS:sub(k, k)
    end
    local id = table.concat(out)
    if not taken[id] then
      return id
    end
  end
  return nil
end

function S.count()
  local new, up = 0, 0
  for _, e in ipairs(S.items()) do
    if e.st == "up" then
      up = up + 1
    else
      new = new + 1
    end
  end
  return new, up
end

function S.get(id)
  for i, e in ipairs(S.items()) do
    if e.id == id then
      return e, i
    end
  end
end

-- true, or false + "limit" when full and nothing uploaded can make room.
function S.canAdd()
  local new, up = S.count()
  if new + up < S.MAX or up > 0 then
    return true
  end
  return false, "limit"
end

local function dropOldestUploaded()
  local items = S.items()
  for i, e in ipairs(items) do
    if e.st == "up" then
      table.remove(items, i)
      return true
    end
  end
  return false
end

-- info: { zone, sub, map, x, y, face, build, ver }. Returns the entry, or nil + "limit"/"id".
function S.add(info, now)
  local ok, why = S.canAdd()
  if not ok then
    return nil, why
  end
  local id = S.newId()
  if not id then
    return nil, "id"
  end
  local items = S.items()
  while #items >= S.MAX do
    if not dropOldestUploaded() then
      return nil, "limit"
    end
  end
  local meta = S.meta()
  local t = now or U.now()
  local e = {
    id = id,
    n = meta.seq + 1,
    t = t,
    lt = S.stamp(t),
    file = S.fileName(t),
    zone = cleanText(info.zone),
    sub = cleanText(info.sub),
    map = type(info.map) == "number" and info.map or nil,
    x = type(info.x) == "number" and tonumber(fx(U.clamp(info.x, 0, 1), 4)) or nil,
    y = type(info.y) == "number" and tonumber(fx(U.clamp(info.y, 0, 1), 4)) or nil,
    face = type(info.face) == "number" and tonumber(fx(info.face, 3)) or nil,
    build = cleanText(info.build),
    ver = cleanText(info.ver),
    st = "new",
    prev = meta.last,
  }
  e.h = S.hashOf(e)
  items[#items + 1] = e
  meta.seq, meta.last = e.n, e.h
  S.unsaved = S.unsaved + 1
  return e
end

-- Undo for a capture the game reported as failed (only the newest entry).
function S.removeLast(e)
  local items = S.items()
  if items[#items] ~= e then
    return false
  end
  items[#items] = nil
  local meta = S.meta()
  meta.seq, meta.last = e.n - 1, e.prev
  S.unsaved = math.max(0, S.unsaved - 1)
  return true
end

function S.remove(id)
  local e, i = S.get(id)
  if e then
    table.remove(S.items(), i)
  end
  return e ~= nil
end

function S.removeUploaded()
  local items, kept, removed = S.items(), {}, 0
  for _, e in ipairs(items) do
    if e.st == "up" then
      removed = removed + 1
    else
      kept[#kept + 1] = e
    end
  end
  for i = #items, 1, -1 do
    items[i] = nil
  end
  for i, e in ipairs(kept) do
    items[i] = e
  end
  return removed
end

function S.setStatus(id, st)
  local e = S.get(id)
  if e and (st == "new" or st == "up") then
    e.st = st
    return true
  end
  return false
end

function S.markAllUploaded()
  local n = 0
  for _, e in ipairs(S.items()) do
    if e.st ~= "up" then
      e.st = "up"
      n = n + 1
    end
  end
  return n
end

-- Newest first.
function S.list()
  local out = {}
  for _, e in ipairs(S.items()) do
    if type(e) == "table" then
      out[#out + 1] = e
    end
  end
  local function key(e)
    return type(e.n) == "number" and e.n or 0
  end
  table.sort(out, function(a, b)
    return key(a) > key(b)
  end)
  return out
end

-- Checks entries in order. bad: own hash does not match the fields (changed by hand);
-- gaps: prev differs from the hash before it (entries were deleted, or something was inserted).
function S.verify(items)
  items = items or S.items()
  local res = { ok = 0, bad = 0, gaps = 0, badIds = {} }
  local last
  for _, e in ipairs(items) do
    local good = type(e) == "table" and type(e.prev) == "string" and e.h == S.hashOf(e)
    if good then
      res.ok = res.ok + 1
    else
      res.bad = res.bad + 1
      res.badIds[type(e) == "table" and tostring(e.id) or "?"] = true
    end
    if last ~= nil and type(e) == "table" and e.prev ~= last then
      res.gaps = res.gaps + 1
    end
    last = type(e) == "table" and e.h or last
  end
  return res
end

-- Exchange ---------------------------------------------------------------------------

local FIELDS =
  { "id", "n", "t", "lt", "file", "zone", "sub", "map", "x", "y", "face", "build", "ver", "st", "prev", "h" }

function S.pack(e)
  local out = {}
  for _, k in ipairs(FIELDS) do
    out[k] = e[k]
  end
  return out
end

-- Returns a list of strings, each within the input limit and MAX_PER_STRING, or nil, reason.
function S.exportStrings(items)
  local strings = {}
  local function emit(from, to)
    local packed = {}
    for i = from, to do
      packed[#packed + 1] = S.pack(items[i])
    end
    local s, why = ns.Strings.encode("shots", { items = packed })
    if not s then
      return false, why
    end
    if #s > ns.Strings.MAX_INPUT * 0.9 and to > from then
      local mid = math.floor((from + to) / 2)
      local ok, err = emit(from, mid)
      if not ok then
        return false, err
      end
      return emit(mid + 1, to)
    end
    strings[#strings + 1] = s
    return true
  end
  local from = 1
  while from <= #items do
    local ok, why = emit(from, math.min(from + S.MAX_PER_STRING - 1, #items))
    if not ok then
      return nil, why
    end
    from = from + S.MAX_PER_STRING
  end
  return strings
end

local function num(v)
  return type(v) == "number" and v == v and v > -1e12 and v < 1e12 and v or nil
end

local function str(v, max)
  return type(v) == "string" and v:sub(1, max or 80) or nil
end

-- One imported entry: whitelist and types, nothing else survives. The checksum is not
-- recomputed here, S.verify reports it.
function S.clean(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local e = {
    id = str(raw.id, 16),
    n = num(raw.n),
    t = num(raw.t),
    lt = str(raw.lt, 19),
    file = str(raw.file, 40),
    zone = str(raw.zone, S.MAX_ZONE),
    sub = str(raw.sub, S.MAX_ZONE),
    map = num(raw.map),
    x = num(raw.x),
    y = num(raw.y),
    face = num(raw.face),
    build = str(raw.build, S.MAX_ZONE),
    ver = str(raw.ver, S.MAX_ZONE),
    st = raw.st == "up" and "up" or "new",
    prev = str(raw.prev, 16),
    h = str(raw.h, 16),
  }
  if not (e.id and e.n and e.t and e.zone and e.sub and e.build and e.ver and e.prev and e.h) then
    return nil
  end
  return e
end

-- Upload code: one entry as a "shots" string with the extra keys file (expected name with
-- extension) and tok. tok covers the entry fields, its id and the file name stem, so a web
-- page can check that code and file belong together. The addon cannot read picture bytes,
-- the token says nothing about the image content.
function S.token(e, stem)
  return S.checksum("shot|" .. tostring(e.id) .. "|" .. S.canon(e) .. "|" .. (stem or S.fileStem(e)))
end

function S.encodeCode(e, ext)
  return ns.Strings.encode("shots", {
    items = { S.pack(e) },
    file = S.expectedName(e, ext),
    tok = S.token(e),
  })
end

-- One code per line, in the order given. Returns the text and the number of codes, or nil, reason.
function S.encodeCodes(items, ext)
  local lines = {}
  for _, e in ipairs(items) do
    local s, why = S.encodeCode(e, ext)
    if not s then
      return nil, why
    end
    lines[#lines + 1] = s
  end
  return table.concat(lines, "\n"), #lines
end

-- Reads one upload code. Returns { entry, file, tok, hashOk, tokOk } or nil, reason.
function S.parseCode(text)
  local block = tostring(text or ""):match("%S+")
  if not block then
    return nil, "empty"
  end
  local env, why = ns.Strings.decode(block)
  if not env then
    return nil, why
  end
  local d = env.data
  if env.type ~= "shots" or type(d.items) ~= "table" or #d.items ~= 1 then
    return nil, "type"
  end
  if type(d.file) ~= "string" or type(d.tok) ~= "string" then
    return nil, "code"
  end
  local e = S.clean(d.items[1])
  if not e then
    return nil, "items"
  end
  local stem = d.file:match("^(.-)%.%w+$") or d.file
  return { entry = e, file = d.file, tok = d.tok, hashOk = e.h == S.hashOf(e), tokOk = d.tok == S.token(e, stem) }
end

-- text: one or several strings (blank-line separated). Returns { items, verify } or nil, reason.
function S.parse(text)
  local items, count = {}, 0
  for block in tostring(text or ""):gmatch("%S+") do
    count = count + 1
    if count > 8 then
      return nil, "too-many"
    end
    local env, why = ns.Strings.decode(block)
    if not env then
      return nil, why
    end
    if env.type ~= "shots" then
      return nil, "type"
    end
    if type(env.data.items) ~= "table" or #env.data.items > S.MAX then
      return nil, "items"
    end
    for i, raw in ipairs(env.data.items) do
      local e = S.clean(raw)
      if not e then
        return nil, "items", i
      end
      items[#items + 1] = e
    end
  end
  if count == 0 then
    return nil, "empty"
  end
  return { items = items, verify = S.verify(items) }
end
