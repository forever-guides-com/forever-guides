-- Payloads of the guild sync functions (guild map and crafting), no game calls. CommLogic wraps each
-- payload in its envelope (version, function, type, id, i/n, checksum), so a payload carries no type or
-- version of its own: the type comes from the envelope. Plain printable ASCII, fields split by "|".
-- Every decoder is strict and never raises: anything outside the format or the ranges gives nil and a
-- reason. Fields after the last known one are ignored, so a later version can append.
--   guildMap  P  <map>|<x>|<y>[|<layer>]   position, x and y in per mille (0-999), "-|-" is zone only
--             X  <reason>                  end of display: w withdrawn, h hidden, i pause, o logout
--   crafting  J  <job>:<skill>:<max>:<n>:<h>[,...]          summary, at most 6 jobs
--             W  <nonce>|<spell>                            who can make this recipe
--             K  <nonce>|<spell>|<job>|<skill>|<max>        answer to W, only from the maker
--             R  <nonce>|<job>|<u>|<h>                      fetch the recipe set of a job
--             C  <nonce>|<job>|<art>|<u>|<n>|<h>|<data>     recipe set; art B bit mask, I id list,
--                                                           = unchanged (no data)
--             X  <reason>                                   same as above, drops the job data
-- Numbers are decimal without leading zeros, checksums and nonces base 36. A recipe set is the sorted
-- spell ids of one job (the universe): bit k of the mask is the k-th id, 6 bits per character, lowest
-- bit first. u is the checksum of the universe, h the checksum of the set, n its size.
local _, ns = ...

local G = {}
ns.GuildSyncCodec = G

G.LIMITS = {
  -- Same as CommLogic.LIMITS.MAX_PAYLOAD: with the envelope a block stays below 250 characters.
  MAX_PAYLOAD = 220,
  -- C is the one type CommLogic splits into blocks (at most 12 of 220 characters).
  MAX_C_PAYLOAD = 2640,
  MAX_MAP = 999999,
  MAX_PROMILLE = 999,
  GRID = 50,
  MAX_LAYER = 999,
  MAX_JOBS = 6,
  MAX_JOB_ID = 9999,
  MAX_SKILL = 1000,
  MAX_KNOWN = 1500,
  MAX_UNIVERSE = 1500,
  MAX_MASK = 250,
  MAX_SPELL = 99999999,
  MODULUS = 2147483647,
  -- Largest checksum, 6 characters in base 36.
  MAX_SUM = 2147483646,
}
local L = G.LIMITS

-- Message types per function name (the names of CommLogic.FUNCTIONS).
G.TYPES = {
  guildMap = { P = true, X = true },
  crafting = { J = true, W = true, K = true, R = true, C = true, X = true },
}

G.REASONS = { w = true, h = true, i = true, o = true }
G.ARTS = { B = true, I = true, ["="] = true }

-- 6 bits per character; no "|" and no "~".
G.ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
-- Id lists: a gap is written in 5-bit digits, the last digit from END, all before from MORE. The two
-- alphabets do not overlap, so no separator is needed.
local END_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
local MORE_DIGITS = "abcdefghijklmnopqrstuvwxyzWXYZ-_"

local function valuesOf(alphabet)
  local out = {}
  for i = 1, #alphabet do
    out[alphabet:sub(i, i)] = i - 1
  end
  return out
end
local MASK_VALUE, B36_VALUE = valuesOf(G.ALPHABET), valuesOf(B36)
local END_VALUE, MORE_VALUE = valuesOf(END_DIGITS), valuesOf(MORE_DIGITS)
local POW2 = { 1, 2, 4, 8, 16, 32 }

local floor = math.floor

-- Helpers ---------------------------------------------------------------------------------------

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function whole(v, lo, hi)
  return finite(v) and v == floor(v) and v >= lo and v <= hi
end

-- A real string the client does not hide; nothing else is ever inspected.
local function readable(v)
  if type(v) ~= "string" then
    return false
  end
  local secret = rawget(_G, "issecretvalue")
  if type(secret) == "function" then
    local ok, hidden = pcall(secret, v)
    if not ok or hidden then
      return false
    end
  end
  return true
end

-- Public functions take outside data; a misbehaving object must end as nil, not as an error.
local function guarded(fn)
  return function(...)
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then
      return a, b, c, d
    end
    return nil, "invalid"
  end
end

local function split(s, sep)
  local out, from = {}, 1
  while true do
    local at = s:find(sep, from, true)
    if not at then
      out[#out + 1] = s:sub(from)
      return out
    end
    out[#out + 1] = s:sub(from, at - 1)
    from = at + 1
  end
end

-- Decimal text without sign and leading zeros, value from lo to hi.
local function decimal(s, lo, hi)
  if type(s) ~= "string" or #s > 9 or not (s == "0" or s:find("^[1-9]%d*$")) then
    return nil
  end
  local n = tonumber(s)
  if n < lo or n > hi then
    return nil
  end
  return n
end

local function base36(s)
  if type(s) ~= "string" or #s > 6 or not (s == "0" or s:find("^[1-9a-z][0-9a-z]*$")) then
    return nil
  end
  local n = 0
  for i = 1, #s do
    n = n * 36 + B36_VALUE[s:sub(i, i)]
  end
  if n > L.MAX_SUM then
    return nil
  end
  return n
end

local function toBase36(n)
  if n == 0 then
    return "0"
  end
  local out = ""
  while n > 0 do
    local d = n % 36
    out = B36:sub(d + 1, d + 1) .. out
    n = (n - d) / 36
  end
  return out
end

local function isNonce(s)
  return type(s) == "string" and s:find("^[0-9a-z][0-9a-z][0-9a-z]$") ~= nil
end

-- "name1", text1, "name2", text2, ...: the texts joined by sep, or nil and the name of the first
-- missing text.
local function join(sep, ...)
  local out = {}
  for i = 1, select("#", ...), 2 do
    local name, text = select(i, ...)
    if text == nil then
      return nil, name
    end
    out[#out + 1] = text
  end
  return table.concat(out, sep)
end

local function dec(v, lo, hi)
  if whole(v, lo, hi) then
    return string.format("%d", v)
  end
end

local function sum36(v)
  if whole(v, 0, L.MAX_SUM) then
    return toBase36(v)
  end
end

-- Public helpers ----------------------------------------------------------------------------------

-- Random 3 character nonce. `random(n)` returns an integer from 1 to n (default math.random).
function G.NewNonce(random)
  random = random or math.random
  local out = {}
  for k = 1, 3 do
    local r = tonumber(random(#B36))
    if not r or r ~= r then
      r = 1
    end
    r = math.min(#B36, math.max(1, floor(r)))
    out[k] = B36:sub(r, r)
  end
  return table.concat(out)
end

-- Map fraction 0..1 to per mille 0..999, nil for anything else.
function G.Promille(fraction)
  if not finite(fraction) or fraction < 0 or fraction > 1 then
    return nil
  end
  return math.min(L.MAX_PROMILLE, floor(fraction * 1000))
end

-- Checksum of a list of ids in ascending order. Cache and validity check only, no security.
function G.Checksum(ids)
  local h = 0
  for i = 1, #ids do
    h = (h * 31 + ids[i]) % L.MODULUS
  end
  return h
end

-- Universe of one job from its spell ids (any order). Invalid ids and repeats are dropped.
-- Returns { ids, size, rank, sum } with rank[id] = 1-based position, or nil and a reason.
G.NewUniverse = guarded(function(ids)
  if type(ids) ~= "table" then
    return nil, "ids"
  end
  local seen, list = {}, {}
  for i = 1, #ids do
    local id = ids[i]
    if whole(id, 1, L.MAX_SPELL) and not seen[id] then
      seen[id] = true
      list[#list + 1] = id
    end
  end
  if #list > L.MAX_UNIVERSE then
    return nil, "size"
  end
  table.sort(list)
  local rank = {}
  for k, id in ipairs(list) do
    rank[id] = k
  end
  return { ids = list, size = #list, rank = rank, sum = G.Checksum(list) }
end)

-- Bit mask of the known ids that are in the universe. Returns mask, count, checksum of that set and the
-- set as ascending ids. Ids outside the universe cannot be carried and are skipped.
G.EncodeMask = guarded(function(universe, known)
  if type(universe) ~= "table" or type(universe.rank) ~= "table" or type(known) ~= "table" then
    return nil, "args"
  end
  local size, set, count = universe.size, {}, 0
  for i = 1, #known do
    local k = universe.rank[known[i]]
    if k and not set[k] then
      set[k] = true
      count = count + 1
    end
  end
  local chars, ids = {}, {}
  for c = 0, math.ceil(size / 6) - 1 do
    local v = 0
    for b = 0, 5 do
      if set[c * 6 + b + 1] then
        v = v + POW2[b + 1]
      end
    end
    chars[c + 1] = G.ALPHABET:sub(v + 1, v + 1)
  end
  for k = 1, size do
    if set[k] then
      ids[#ids + 1] = universe.ids[k]
    end
  end
  return table.concat(chars), count, G.Checksum(ids), ids
end)

-- Ranks of the set bits in ascending order. The mask must have exactly ceil(size / 6) characters and no
-- bit beyond the universe.
G.DecodeMask = guarded(function(mask, size)
  if not readable(mask) then
    return nil, "type"
  end
  if not whole(size, 0, L.MAX_UNIVERSE) then
    return nil, "size"
  end
  if #mask ~= math.ceil(size / 6) then
    return nil, "length"
  end
  local ranks = {}
  for c = 1, #mask do
    local v = MASK_VALUE[mask:sub(c, c)]
    if not v then
      return nil, "characters"
    end
    for b = 0, 5 do
      if v % 2 == 1 then
        local k = (c - 1) * 6 + b + 1
        if k > size then
          return nil, "range"
        end
        ranks[#ranks + 1] = k
      end
      v = (v - v % 2) / 2
    end
  end
  return ranks
end)

-- True or false for the bit of one rank, nil when the mask or the rank does not fit.
G.MaskHas = guarded(function(mask, size, rank)
  if not readable(mask) or not whole(size, 0, L.MAX_UNIVERSE) or #mask ~= math.ceil(size / 6) then
    return nil
  end
  if not whole(rank, 1, size) then
    return nil
  end
  local c, b = floor((rank - 1) / 6) + 1, (rank - 1) % 6
  local v = MASK_VALUE[mask:sub(c, c)]
  if not v then
    return nil
  end
  return floor(v / POW2[b + 1]) % 2 == 1
end)

-- Id list for the fallback: ids strictly ascending, written as gaps to the predecessor.
G.EncodeIdList = guarded(function(ids)
  if type(ids) ~= "table" or #ids > L.MAX_KNOWN then
    return nil, "ids"
  end
  local out, prev = {}, 0
  for i = 1, #ids do
    local id = ids[i]
    if not whole(id, prev + 1, L.MAX_SPELL) then
      return nil, "ids"
    end
    local gap, digits = id - prev, {}
    repeat
      local d = gap % 32
      digits[#digits + 1] = d
      gap = (gap - d) / 32
    until gap == 0
    for j = #digits, 2, -1 do
      out[#out + 1] = MORE_DIGITS:sub(digits[j] + 1, digits[j] + 1)
    end
    out[#out + 1] = END_DIGITS:sub(digits[1] + 1, digits[1] + 1)
    prev = id
  end
  return table.concat(out)
end)

-- The ids of an id list, or nil and a reason. Only the canonical form is accepted: no leading zero
-- digit, no gap of 0, nothing cut off.
G.DecodeIdList = guarded(function(text)
  if not readable(text) then
    return nil, "type"
  end
  local ids, prev, value, digits = {}, 0, 0, 0
  for i = 1, #text do
    local ch = text:sub(i, i)
    local more, final = MORE_VALUE[ch], END_VALUE[ch]
    local d = more or final
    if not d then
      return nil, "characters"
    end
    if digits == 0 and more == 0 then
      return nil, "digits"
    end
    digits = digits + 1
    if digits > 6 then
      return nil, "digits"
    end
    value = value * 32 + d
    if final then
      if value == 0 then
        return nil, "gap"
      end
      prev = prev + value
      if prev > L.MAX_SPELL then
        return nil, "range"
      end
      ids[#ids + 1] = prev
      if #ids > L.MAX_KNOWN then
        return nil, "count"
      end
      value, digits = 0, 0
    end
  end
  if digits ~= 0 then
    return nil, "truncated"
  end
  return ids
end)

-- Encoders: message table to payload, or nil and the name of the refused field. Decode runs over the
-- result in Encode, so what comes out always passes the decoder.
local ENCODE = {}

local function snap(v)
  return math.min(L.MAX_PROMILLE - L.MAX_PROMILLE % L.GRID, floor(v / L.GRID + 0.5) * L.GRID)
end

-- mode "exact" or "point" (default), "grid" (rounded to 5 percent of the map, so no fine position leaves the
-- client) or "zone" (map only).
function ENCODE.P(m)
  local mode = m.mode == nil and "exact" or m.mode
  local x, y = "-", "-"
  if mode == "exact" or mode == "point" or mode == "grid" then
    if not (finite(m.x) and finite(m.y) and m.x >= 0 and m.y >= 0 and m.x < 1000 and m.y < 1000) then
      return nil, "position"
    end
    local px, py = floor(m.x), floor(m.y)
    if mode == "grid" then
      px, py = snap(px), snap(py)
    end
    x, y = string.format("%d", px), string.format("%d", py)
  elseif mode ~= "zone" then
    return nil, "mode"
  end
  local payload, why = join("|", "map", dec(m.map, 1, L.MAX_MAP), "x", x, "y", y)
  if payload and m.layer ~= nil then
    local layer = dec(m.layer, 1, L.MAX_LAYER)
    if not layer then
      return nil, "layer"
    end
    payload = payload .. "|" .. layer
  end
  return payload, why
end

function ENCODE.X(m)
  if type(m.reason) ~= "string" or not G.REASONS[m.reason] then
    return nil, "reason"
  end
  return m.reason
end

function ENCODE.J(m)
  local jobs = m.jobs
  if type(jobs) ~= "table" or #jobs < 1 or #jobs > L.MAX_JOBS then
    return nil, "jobs"
  end
  local out = {}
  for i = 1, #jobs do
    local j = jobs[i]
    if type(j) ~= "table" then
      return nil, "jobs"
    end
    local text, why = join(
      ":",
      "id",
      dec(j.id, 1, L.MAX_JOB_ID),
      "skill",
      dec(j.skill, 0, L.MAX_SKILL),
      "max",
      dec(j.max, 0, L.MAX_SKILL),
      "n",
      dec(j.n, 0, L.MAX_KNOWN),
      "h",
      sum36(j.h)
    )
    if not text then
      return nil, why
    end
    out[i] = text
  end
  return table.concat(out, ",")
end

function ENCODE.W(m)
  return join("|", "nonce", isNonce(m.nonce) and m.nonce or nil, "spell", dec(m.spell, 1, L.MAX_SPELL))
end

function ENCODE.K(m)
  return join(
    "|",
    "nonce",
    isNonce(m.nonce) and m.nonce or nil,
    "spell",
    dec(m.spell, 1, L.MAX_SPELL),
    "job",
    dec(m.job, 1, L.MAX_JOB_ID),
    "skill",
    dec(m.skill, 0, L.MAX_SKILL),
    "max",
    dec(m.max, 0, L.MAX_SKILL)
  )
end

function ENCODE.R(m)
  return join(
    "|",
    "nonce",
    isNonce(m.nonce) and m.nonce or nil,
    "job",
    dec(m.job, 1, L.MAX_JOB_ID),
    "u",
    sum36(m.u),
    "h",
    sum36(m.h)
  )
end

function ENCODE.C(m)
  if type(m.art) ~= "string" or not G.ARTS[m.art] then
    return nil, "art"
  end
  local payload, why = join(
    "|",
    "nonce",
    isNonce(m.nonce) and m.nonce or nil,
    "job",
    dec(m.job, 1, L.MAX_JOB_ID),
    "art",
    m.art,
    "u",
    sum36(m.u),
    "n",
    dec(m.n, 0, L.MAX_KNOWN),
    "h",
    sum36(m.h)
  )
  if not payload or m.art == "=" then
    return payload, why
  end
  if type(m.data) ~= "string" or m.data:find("[^0-9A-Za-z_%-]") then
    return nil, "data"
  end
  return payload .. "|" .. m.data
end

-- Decoders: the fields after the type, or nil and a reason ---------------------------------------------
local DECODE = {}

function DECODE.P(f)
  local map = decimal(f[1], 1, L.MAX_MAP)
  if not map then
    return nil, "map"
  end
  local msg = { map = map, mode = "point" }
  if f[2] == "-" and f[3] == "-" then
    msg.mode = "zone"
  else
    msg.x, msg.y = decimal(f[2], 0, L.MAX_PROMILLE), decimal(f[3], 0, L.MAX_PROMILLE)
    if not msg.x or not msg.y then
      return nil, "position"
    end
  end
  -- A trailing field that is not understood yet is left out, the position stays valid.
  msg.layer = decimal(f[4], 1, L.MAX_LAYER)
  return msg
end

function DECODE.X(f)
  if not G.REASONS[f[1]] then
    return nil, "reason"
  end
  return { reason = f[1] }
end

function DECODE.J(f)
  if not f[1] or f[1] == "" then
    return nil, "jobs"
  end
  local entries = split(f[1], ",")
  if #entries > L.MAX_JOBS then
    return nil, "jobs"
  end
  local jobs, seen = {}, {}
  for i, entry in ipairs(entries) do
    local p = split(entry, ":")
    local job = {
      id = decimal(p[1], 1, L.MAX_JOB_ID),
      skill = decimal(p[2], 0, L.MAX_SKILL),
      max = decimal(p[3], 0, L.MAX_SKILL),
      n = decimal(p[4], 0, L.MAX_KNOWN),
      h = base36(p[5]),
    }
    if not (job.id and job.skill and job.max and job.n and job.h) then
      return nil, "job"
    end
    if seen[job.id] then
      return nil, "duplicate"
    end
    seen[job.id] = true
    jobs[i] = job
  end
  return { jobs = jobs }
end

function DECODE.W(f)
  local spell = decimal(f[2], 1, L.MAX_SPELL)
  if not isNonce(f[1]) or not spell then
    return nil, "field"
  end
  return { nonce = f[1], spell = spell }
end

function DECODE.K(f)
  local msg = {
    nonce = f[1],
    spell = decimal(f[2], 1, L.MAX_SPELL),
    job = decimal(f[3], 1, L.MAX_JOB_ID),
    skill = decimal(f[4], 0, L.MAX_SKILL),
    max = decimal(f[5], 0, L.MAX_SKILL),
  }
  if not (isNonce(msg.nonce) and msg.spell and msg.job and msg.skill and msg.max) then
    return nil, "field"
  end
  return msg
end

function DECODE.R(f)
  local msg = { nonce = f[1], job = decimal(f[2], 1, L.MAX_JOB_ID), u = base36(f[3]), h = base36(f[4]) }
  if not (isNonce(msg.nonce) and msg.job and msg.u and msg.h) then
    return nil, "field"
  end
  return msg
end

function DECODE.C(f)
  local msg = {
    nonce = f[1],
    job = decimal(f[2], 1, L.MAX_JOB_ID),
    art = f[3],
    u = base36(f[4]),
    n = decimal(f[5], 0, L.MAX_KNOWN),
    h = base36(f[6]),
  }
  if not (isNonce(msg.nonce) and msg.job and G.ARTS[msg.art] and msg.u and msg.n and msg.h) then
    return nil, "field"
  end
  if msg.art == "=" then
    return msg
  end
  local data = f[7]
  if type(data) ~= "string" or data:find("[^0-9A-Za-z_%-]") then
    return nil, "data"
  end
  msg.data = data
  if msg.art == "B" then
    if data == "" or #data > L.MAX_MASK then
      return nil, "data"
    end
    return msg
  end
  -- An id list is read completely here: cut off or non-canonical data ends the message.
  local ids = G.DecodeIdList(data)
  if not ids or #ids ~= msg.n then
    return nil, "data"
  end
  msg.ids = ids
  return msg
end

-- Reads the payload of a message of the function `fn` ("guildMap" or "crafting") with the envelope type
-- `typ`. Returns the fields as a table with typ, or nil and a reason. Never raises.
G.Decode = guarded(function(fn, typ, payload)
  if not (readable(fn) and readable(typ) and readable(payload)) then
    return nil, "type"
  end
  local allowed = G.TYPES[fn]
  if not allowed or not allowed[typ] then
    return nil, "type"
  end
  if #payload > (typ == "C" and L.MAX_C_PAYLOAD or L.MAX_PAYLOAD) then
    return nil, "length"
  end
  if payload:find("[^ -~]") then
    return nil, "characters"
  end
  local msg, why = DECODE[typ](split(payload, "|"))
  if not msg then
    return nil, why
  end
  msg.typ = typ
  return msg
end)

-- Builds the payload of `msg` ({ typ = "P", ... }) for the function `fn`. Returns payload and type, or
-- nil and the name of the refused field. Never raises.
G.Encode = guarded(function(fn, msg)
  if not readable(fn) or type(msg) ~= "table" then
    return nil, "message"
  end
  local typ = msg.typ
  local allowed = G.TYPES[fn]
  if not allowed or not readable(typ) or not allowed[typ] then
    return nil, "type"
  end
  local payload, why = ENCODE[typ](msg)
  if not payload then
    return nil, why
  end
  if #payload > (typ == "C" and L.MAX_C_PAYLOAD or L.MAX_PAYLOAD) then
    return nil, "length"
  end
  local back, reason = G.Decode(fn, typ, payload)
  if not back then
    return nil, reason
  end
  return payload, typ
end)
