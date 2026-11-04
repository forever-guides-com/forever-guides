-- Rules of the add-on message line, no game calls: the envelope around every message, its checksum,
-- splitting of long payloads into blocks and putting them back together, and the token bucket that
-- paces sending. The part that touches the game (prefix, channels, events) comes on top of this.
-- Envelope, plain printable ASCII, at most LIMITS.MAX_LENGTH characters:
--   <v><fn>|<type>|<id>|<i>/<n>|<payload>[~<crc>]
-- v one digit, fn two letters (FUNCTIONS), type one capital letter, id 3 to 4 characters of 0-9a-z,
-- block i of n, crc = CRC32 of the whole payload as 8 lowercase hex digits, only in the last block.
local _, ns = ...

local CL = {}
ns.CommLogic = CL

CL.LIMITS = {
  VERSION = 1,
  MAX_LENGTH = 250,
  MAX_PAYLOAD = 220,
  MAX_BLOCKS = 110,
  MAX_BYTES = 20480,
  -- Seconds without a new block until an open transfer is dropped.
  TIMEOUT = 15,
  -- Senders with an open transfer at the same time.
  MAX_SENDERS = 64,
  -- Token bucket of one channel kind: size and tokens per second.
  BURST = 6,
  REFILL = 1,
}
local L = CL.LIMITS

-- Function code to function. The codes are part of the protocol: never renumber, only add.
CL.FUNCTIONS = {
  PS = "peerStats",
  PR = "professions",
  PM = "presenceMark",
  LK = "linkShare",
  GM = "guildMap",
  CR = "crafting",
  GS = "gmShare",
  CP = "chatPeer",
  LY = "layer",
  CM = "crestMark",
  TC = "teamChat",
}
local CODES = {}
for code, name in pairs(CL.FUNCTIONS) do
  CODES[name] = code
end

function CL.CodeOf(fn)
  return type(fn) == "string" and CODES[fn] or nil
end

function CL.NameOf(code)
  return type(code) == "string" and CL.FUNCTIONS[code] or nil
end

-- CRC32 (IEEE, as in zip) with plain arithmetic: the client's Lua has no operators for bits.
local XOR4 = {}
for a = 0, 15 do
  for b = 0, 15 do
    local r, weight, x, y = 0, 1, a, b
    for _ = 1, 4 do
      if x % 2 ~= y % 2 then
        r = r + weight
      end
      x, y, weight = (x - x % 2) / 2, (y - y % 2) / 2, weight * 2
    end
    XOR4[a * 16 + b] = r
  end
end

local function xor32(a, b)
  local r, weight = 0, 1
  for _ = 1, 8 do
    r = r + XOR4[(a % 16) * 16 + b % 16] * weight
    a, b, weight = (a - a % 16) / 16, (b - b % 16) / 16, weight * 16
  end
  return r
end

local CRC_TABLE = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do
    if c % 2 == 1 then
      c = xor32((c - 1) / 2, 0xEDB88320)
    else
      c = c / 2
    end
  end
  CRC_TABLE[i] = c
end

-- CRC32 of a string as a number from 0 to 2^32 - 1.
function CL.Crc32(s)
  local crc = 0xFFFFFFFF
  for i = 1, #s do
    local index = xor32(crc % 256, s:byte(i))
    crc = xor32((crc - crc % 256) / 256, CRC_TABLE[index])
  end
  return xor32(crc, 0xFFFFFFFF)
end

local HEX = "0123456789abcdef"

-- CRC32 as 8 lowercase hex digits.
function CL.Crc32Hex(s)
  local crc, out = CL.Crc32(s), {}
  for i = 8, 1, -1 do
    local digit = crc % 16
    out[i] = HEX:sub(digit + 1, digit + 1)
    crc = (crc - digit) / 16
  end
  return table.concat(out)
end

local HEX8 = ("[0-9a-f]"):rep(8)
local CRC_FIELD = "^" .. HEX8 .. "$"
local CRC_TAIL = "~" .. HEX8 .. "$"

local function whole(v, lo, hi)
  return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

-- Builds one message from { fn, typ, id, i, n, payload, crc }; fn is the name of the function. Returns
-- the text, or nil and the name of the refused field. Every limit is checked here, so what this
-- returns always passes Decode.
function CL.Encode(msg)
  if type(msg) ~= "table" then
    return nil, "message"
  end
  local code = CL.CodeOf(msg.fn)
  if not code then
    return nil, "fn"
  end
  if type(msg.typ) ~= "string" or not msg.typ:find("^%u$") then
    return nil, "typ"
  end
  local id = msg.id
  if type(id) ~= "string" or #id < 3 or #id > 4 or id:find("[^0-9a-z]") then
    return nil, "id"
  end
  if not whole(msg.n, 1, L.MAX_BLOCKS) or not whole(msg.i, 1, msg.n) then
    return nil, "block"
  end
  local payload, crc = msg.payload, msg.crc
  if type(payload) ~= "string" or #payload > L.MAX_PAYLOAD or payload:find("[^ -~]") then
    return nil, "payload"
  end
  if crc ~= nil and (msg.i ~= msg.n or type(crc) ~= "string" or not crc:find(CRC_FIELD)) then
    return nil, "crc"
  end
  -- A last block without checksum must not end in something that reads as one.
  if crc == nil and msg.i == msg.n and payload:find(CRC_TAIL) then
    return nil, "payload"
  end
  local text = string.format(
    "%d%s|%s|%s|%d/%d|%s%s",
    L.VERSION,
    code,
    msg.typ,
    id,
    msg.i,
    msg.n,
    payload,
    crc and "~" .. crc or ""
  )
  if #text > L.MAX_LENGTH then
    return nil, "length"
  end
  return text
end

-- Reads one message strictly. Returns { fn, code, typ, id, i, n, payload, crc } or nil and the reason.
-- Anything that is not exactly the envelope is refused; the payload is left to the function.
function CL.Decode(text)
  if type(text) ~= "string" then
    return nil, "type"
  end
  if #text > L.MAX_LENGTH then
    return nil, "length"
  end
  if text:find("[^ -~]") then
    return nil, "characters"
  end
  local v, code, typ, id, i, n, rest = text:match("^(%d)(%u%u)|(%u)|([0-9a-z]+)|(%d+)/(%d+)|(.*)$")
  if not v then
    return nil, "format"
  end
  if tonumber(v) ~= L.VERSION then
    return nil, "version"
  end
  local fn = CL.NameOf(code)
  if not fn then
    return nil, "fn"
  end
  if #id < 3 or #id > 4 then
    return nil, "id"
  end
  if not i:find("^[1-9]%d?%d?$") or not n:find("^[1-9]%d?%d?$") then
    return nil, "block"
  end
  i, n = tonumber(i), tonumber(n)
  if n > L.MAX_BLOCKS or i > n then
    return nil, "block"
  end
  local crc
  if i == n then
    local body, sum = rest:match("^(.*)~(" .. HEX8 .. ")$")
    if sum then
      rest, crc = body, sum
    end
  end
  if #rest > L.MAX_PAYLOAD then
    return nil, "payload"
  end
  return { fn = fn, code = code, typ = typ, id = id, i = i, n = n, payload = rest, crc = crc }
end

local ID_CHARS = "0123456789abcdefghijklmnopqrstuvwxyz"

-- Random 4 character transfer id. `random(n)` returns an integer from 1 to n (default math.random).
function CL.NewId(random)
  random = random or math.random
  local out = {}
  for k = 1, 4 do
    local r = tonumber(random(#ID_CHARS))
    if not r or r ~= r then
      r = 1
    end
    r = math.min(#ID_CHARS, math.max(1, math.floor(r)))
    out[k] = ID_CHARS:sub(r, r)
  end
  return table.concat(out)
end

-- Cuts a payload into messages (blocks of at most MAX_PAYLOAD characters, the checksum of the whole
-- payload in the last one). Returns the list of texts, or nil and the name of the refused field.
function CL.Split(fn, typ, payload, id)
  if type(payload) ~= "string" or #payload > L.MAX_BYTES then
    return nil, "payload"
  end
  local count = math.max(1, math.ceil(#payload / L.MAX_PAYLOAD))
  if count > L.MAX_BLOCKS then
    return nil, "payload"
  end
  local crc, out = CL.Crc32Hex(payload), {}
  for k = 1, count do
    local text, why = CL.Encode({
      fn = fn,
      typ = typ,
      id = id,
      i = k,
      n = count,
      payload = payload:sub((k - 1) * L.MAX_PAYLOAD + 1, k * L.MAX_PAYLOAD),
      crc = k == count and crc or nil,
    })
    if not text then
      return nil, why
    end
    out[k] = text
  end
  return out
end

local function clockValue(clock)
  local t = clock()
  return type(t) == "number" and t == t and t or 0
end

-- Puts blocks back together, one open transfer per sender. `clock` returns seconds. Add(sender, block)
-- takes a result of Decode and answers with a status and details:
--   "complete", { fn, typ, id, payload }   the last block came, the checksum fits
--   "pending", { have, total }             stored, more to come (any order)
--   "duplicate"                            the same block again, ignored
--   "rejected", reason                     sender, block, busy, mismatch, conflict, limit, crc
-- A transfer that is rejected is dropped. A new id from the same sender replaces the open transfer.
-- Sweep() drops transfers that were silent for LIMITS.TIMEOUT seconds and lists them.
function CL.NewAssembler(clock)
  if type(clock) ~= "function" then
    return nil, "clock"
  end
  local open, count = {}, 0
  local A = {}

  local function drop(sender)
    if open[sender] then
      open[sender] = nil
      count = count - 1
    end
  end

  function A.Sweep()
    local t, lost = clockValue(clock), {}
    for sender, tr in pairs(open) do
      if t - tr.last >= L.TIMEOUT then
        lost[#lost + 1] = { sender = sender, fn = tr.fn, id = tr.id }
        drop(sender)
      end
    end
    return lost
  end

  function A.Pending()
    return count
  end

  function A.Add(sender, block)
    if type(sender) ~= "string" or sender == "" or #sender > 64 then
      return "rejected", "sender"
    end
    if type(block) ~= "table" or not CL.Encode(block) then
      return "rejected", "block"
    end
    A.Sweep()
    local t = clockValue(clock)
    local tr = open[sender]
    if tr and (tr.fn ~= block.fn or tr.id ~= block.id) then
      drop(sender)
      tr = nil
    end
    if not tr then
      if count >= L.MAX_SENDERS then
        return "rejected", "busy"
      end
      tr = { fn = block.fn, typ = block.typ, id = block.id, n = block.n, parts = {}, have = 0, bytes = 0, last = t }
      open[sender] = tr
      count = count + 1
    elseif tr.typ ~= block.typ or tr.n ~= block.n then
      drop(sender)
      return "rejected", "mismatch"
    end
    local known = tr.parts[block.i]
    if known then
      if known ~= block.payload or (block.crc ~= nil and tr.crc ~= block.crc) then
        drop(sender)
        return "rejected", "conflict"
      end
      return "duplicate"
    end
    if tr.bytes + #block.payload > L.MAX_BYTES then
      drop(sender)
      return "rejected", "limit"
    end
    tr.parts[block.i] = block.payload
    tr.have, tr.bytes, tr.last = tr.have + 1, tr.bytes + #block.payload, t
    tr.crc = block.crc or tr.crc
    if tr.have < tr.n then
      return "pending", { have = tr.have, total = tr.n }
    end
    local payload = table.concat(tr.parts, "", 1, tr.n)
    local done = { fn = tr.fn, typ = tr.typ, id = tr.id, payload = payload }
    local crc = tr.crc
    drop(sender)
    if (tr.n > 1 and not crc) or (crc and CL.Crc32Hex(payload) ~= crc) then
      return "rejected", "crc"
    end
    return "complete", done
  end

  return A
end

-- Token bucket: room for `capacity` messages at once, `refill` new tokens per second, time from
-- `clock`. Take(n) spends n tokens (default 1) and tells whether there were enough.
function CL.NewBucket(capacity, refill, clock)
  local finite = function(v, lo)
    return type(v) == "number" and v == v and v >= lo and v < math.huge
  end
  if not finite(capacity, 1) or not finite(refill, 0) or type(clock) ~= "function" then
    return nil, "args"
  end
  local tokens, at = capacity, nil
  local B = {}

  local function fill()
    local t = clockValue(clock)
    if at and t > at then
      tokens = math.min(capacity, tokens + (t - at) * refill)
    end
    at = t
  end

  function B.Take(n)
    n = n == nil and 1 or n
    if not finite(n, 0) or n > capacity then
      return false
    end
    fill()
    if tokens + 1e-9 >= n then
      tokens = math.max(0, tokens - n)
      return true
    end
    return false
  end

  function B.Level()
    fill()
    return tokens
  end

  function B.Reset()
    tokens, at = capacity, nil
  end

  return B
end
