-- Binary codec for drawings (extends ns.DrawingLogic): a compact byte string,
-- deflated with LibDeflate and printable via EncodeForPrint, so it fits
-- storage, exchange strings and chat transfer like a note.
--
-- Raw layout, version 2 (written without a background map): version, w (2 bytes,
-- little endian), h (2 bytes), paletteCount - 1, layout, auto-color bit mask
-- (ceil(count / 8) bytes, bit 0 of byte 0 is entry 1), palette (r,g,b per entry),
-- body. Cell values are stored as palette index - 1.
-- Version 3 (written when the drawing has a background map, see DrawingLogic
-- cleanMap) is version 2 with a map block between the layout byte and the auto
-- mask: kind 1 (zone) id (2 bytes) alpha, or kind 2 (instance) floor alpha
-- keyLength key. Only the key of the map is stored, never its pictures; a client
-- that does not know the map shows the sheet without it. Version 2 clients refuse
-- a version 3 string as "version". Version 1 (still read): version, w, h,
-- paletteCount, layout, palette, body, at most 160 x 125 cells and 64 colors,
-- no auto colors. Body layouts: 0 run-length rows (varint run, index byte),
-- 1 run-length columns (vertical strokes), 2 one byte per cell. The encoder
-- keeps whichever compresses smallest; it only deflates the layouts whose raw
-- size is within a factor of two of the smallest raw one (the others cannot win
-- and the pure Lua deflate is the expensive part on big canvases).
-- Decoding is strict: every limit is checked before data is trusted.
local _, ns = ...
local D = ns.DrawingLogic

D.CODEC_VERSION = 3
local V2, V3 = 2, 3
-- Local storage and exchange strings; chat sharing is limited to MAX_SHARE.
D.MAX_ENCODED = 64 * 1024
D.MAX_SHARE = 20 * 1024
-- Largest valid raw payload: header (7 + 32 + 3 * 256 bytes) and the map block (at
-- most 4 + D.MAP_MAX_KEY bytes) plus at most two bytes per cell (a run of one
-- cell: one varint byte and the index), with headroom.
D.MAX_RAW = 8 * 1024 + 2 * D.MAX_CELLS

-- Limits a version 1 payload was written under.
local V1_MAX_DIM, V1_MAX_CELLS, V1_MAX_PALETTE = 160, 20000, 64

local ROWS, COLS, RAW = 0, 1, 2
local char, byte, floor = string.char, string.byte, math.floor

local function lib()
  return ns.LibDeflate
end

-- Encoder ------------------------------------------------------------------------------

local function varint(n, out)
  while n >= 128 do
    out[#out + 1] = char(n % 128 + 128)
    n = floor(n / 128)
  end
  out[#out + 1] = char(n)
end

-- Cell index of the k-th sample in row-major or column-major order.
local function cellAt(k, w, h, cols)
  if not cols then
    return k
  end
  local y = (k - 1) % h
  return y * w + (k - 1 - y) / h + 1
end

local function body(d, layout)
  local cells, total, out = d.cells, d.w * d.h, {}
  if layout == RAW then
    for i = 1, total do
      out[i] = char(cells[i] - 1)
    end
    return table.concat(out)
  end
  local prev, run
  for k = 1, total do
    local v = cells[cellAt(k, d.w, d.h, layout == COLS)] - 1
    if v == prev then
      run = run + 1
    else
      if prev then
        varint(run, out)
        out[#out + 1] = char(prev)
      end
      prev, run = v, 1
    end
  end
  varint(run, out)
  out[#out + 1] = char(prev)
  return table.concat(out)
end

local function mapBlock(m)
  if m.kind == "zone" then
    return char(1, m.id % 256, floor(m.id / 256), m.alpha)
  end
  return char(2, m.floor, m.alpha, #m.key) .. m.key
end

local function header(d, layout)
  local count = #d.palette
  local map = D.cleanMap(d.map)
  local out = { char(map and V3 or V2, d.w % 256, floor(d.w / 256), d.h % 256, floor(d.h / 256), count - 1, layout) }
  if map then
    out[#out + 1] = mapBlock(map)
  end
  local mask = {}
  for i = 1, math.ceil(count / 8) do
    mask[i] = 0
  end
  for i in pairs(d.auto or {}) do
    local k = floor((i - 1) / 8) + 1
    mask[k] = mask[k] + 2 ^ ((i - 1) % 8)
  end
  for i, v in ipairs(mask) do
    mask[i] = char(v)
  end
  out[#out + 1] = table.concat(mask)
  for _, c in ipairs(d.palette) do
    out[#out + 1] = char(c[1], c[2], c[3])
  end
  return table.concat(out)
end

-- Printable string for a valid drawing, or nil, reason ("shape" | "dims" |
-- "map" | "palette" | "cells" | "unavailable" | "too-large"). "too-large" also returns
-- the length the string would have had.
function D.Encode(drawing)
  local ok, why = D.validate(drawing)
  if not ok then
    return nil, why
  end
  local LD = lib()
  if not LD then
    return nil, "unavailable"
  end
  local bodies, smallest = {}, drawing.w * drawing.h
  for _, layout in ipairs({ ROWS, COLS }) do
    bodies[layout] = body(drawing, layout)
    smallest = math.min(smallest, #bodies[layout])
  end
  local best
  for _, layout in ipairs({ ROWS, COLS, RAW }) do
    local size = bodies[layout] and #bodies[layout] or drawing.w * drawing.h
    if size < 2 * smallest then
      local packed = LD:CompressDeflate(header(drawing, layout) .. (bodies[layout] or body(drawing, layout)))
      if not best or #packed < #best then
        best = packed
      end
    end
  end
  local code = LD:EncodeForPrint(best)
  if #code > D.MAX_ENCODED then
    return nil, "too-large", #code
  end
  return code
end

-- Length of the encoded string (what a save or share would cost), or nil, reason
-- ("too-large" adds the length the string would have had).
-- Compresses up to three candidates, so call it on demand, not per mouse move.
function D.EncodedSize(drawing)
  local code, why, length = D.Encode(drawing)
  return code and #code, why, length
end

-- Decoder ------------------------------------------------------------------------------

local function validV1Dims(w, h)
  return w >= D.MIN_DIM and w <= V1_MAX_DIM and h >= D.MIN_DIM and h <= V1_MAX_DIM and w * h <= V1_MAX_CELLS
end

-- Reads the run-length or raw body from `pos` on. Returns the cells or nil, reason.
local function parseBody(raw, pos, w, h, count, layout)
  local total, cells = w * h, {}
  if layout == RAW then
    local left = #raw - pos + 1
    if left ~= total then
      return nil, left < total and "truncated" or "trailing"
    end
    for i = 1, total do
      local v = byte(raw, pos + i - 1)
      if v >= count then
        return nil, "palette"
      end
      cells[i] = v + 1
    end
    return cells
  end
  local filled = 0
  while filled < total do
    local run, mult, done = 0, 1, false
    for _ = 1, 3 do
      local b = byte(raw, pos)
      if not b then
        return nil, "truncated"
      end
      pos = pos + 1
      run = run + (b % 128) * mult
      if b < 128 then
        -- A last byte of 0 would be a non-minimal encoding.
        if b == 0 and mult > 1 then
          return nil, "runs"
        end
        done = true
        break
      end
      mult = mult * 128
    end
    if not done or run < 1 or filled + run > total then
      return nil, "runs"
    end
    local v = byte(raw, pos)
    if not v then
      return nil, "truncated"
    end
    if v >= count then
      return nil, "palette"
    end
    pos = pos + 1
    for k = filled + 1, filled + run do
      cells[cellAt(k, w, h, layout == COLS)] = v + 1
    end
    filled = filled + run
  end
  if pos <= #raw then
    return nil, "trailing"
  end
  return cells
end

-- Reads the map block of a version 3 payload at `pos`. Returns the map and the
-- position behind it, or nil, nil, reason ("truncated" | "map").
local function parseMap(raw, pos)
  local kind = byte(raw, pos)
  local map
  if kind == 1 then
    local lo, hi, alpha = byte(raw, pos + 1, pos + 3)
    if not alpha then
      return nil, nil, "truncated"
    end
    map, pos = { kind = "zone", id = lo + 256 * hi, alpha = alpha }, pos + 4
  elseif kind == 2 then
    local fl, alpha, len = byte(raw, pos + 1, pos + 3)
    if not len then
      return nil, nil, "truncated"
    end
    if len < 1 or len > D.MAP_MAX_KEY then
      return nil, nil, "map"
    end
    local key = raw:sub(pos + 4, pos + 3 + len)
    if #key < len then
      return nil, nil, "truncated"
    end
    map, pos = { kind = "instance", key = key, floor = fl, alpha = alpha }, pos + 4 + len
  elseif kind then
    return nil, nil, "map"
  else
    return nil, nil, "truncated"
  end
  map = D.cleanMap(map)
  if not map then
    return nil, nil, "map"
  end
  return map, pos
end

-- Returns a drawing or nil, reason ("truncated" | "version" | "dims" |
-- "palette" | "layout" | "map" | "runs" | "trailing").
local function parse(raw)
  if #raw < 5 then
    return nil, "truncated"
  end
  local version = byte(raw, 1)
  local w, h, count, layout, pos, map
  if version == 1 then
    w, h, count, layout = byte(raw, 2, 5)
    if not validV1Dims(w, h) then
      return nil, "dims"
    end
    if count < 1 or count > V1_MAX_PALETTE then
      return nil, "palette"
    end
    pos = 6
  elseif version == V2 or version == V3 then
    if #raw < 7 then
      return nil, "truncated"
    end
    local w1, w2, h1, h2
    w1, w2, h1, h2, count, layout = byte(raw, 2, 7)
    w, h, count = w1 + 256 * w2, h1 + 256 * h2, count + 1
    if not D.validDims(w, h) then
      return nil, "dims"
    end
    if count > D.MAX_PALETTE then
      return nil, "palette"
    end
    pos = 8
    if version == V3 then
      local why
      map, pos, why = parseMap(raw, pos)
      if not map then
        return nil, why
      end
    end
  else
    return nil, "version"
  end
  if layout > RAW then
    return nil, "layout"
  end
  local maskBytes = version == 1 and 0 or math.ceil(count / 8)
  if #raw < pos + maskBytes + 3 * count - 1 then
    return nil, "truncated"
  end
  local auto
  for i = 1, count do
    local flags = maskBytes > 0 and byte(raw, pos + floor((i - 1) / 8)) or 0
    if floor(flags / 2 ^ ((i - 1) % 8)) % 2 == 1 then
      if i == 1 then
        return nil, "palette"
      end
      auto = auto or {}
      auto[i] = true
    end
  end
  pos = pos + maskBytes
  local palette = {}
  for i = 1, count do
    palette[i] = { byte(raw, pos, pos + 2) }
    pos = pos + 3
  end
  local cells, why = parseBody(raw, pos, w, h, count, layout)
  if not cells then
    return nil, why
  end
  return { w = w, h = h, palette = palette, cells = cells, auto = auto, map = map }
end

-- Drawing from an encoded string, or nil, reason ("empty" | "too-large" |
-- "unavailable" | "decode" plus the parse reasons above). `maxBytes` is the
-- longest string accepted (default MAX_ENCODED, chat links pass MAX_SHARE).
function D.Decode(code, maxBytes)
  if type(code) ~= "string" then
    return nil, "decode"
  end
  code = ns.U.trim(code)
  if code == "" then
    return nil, "empty"
  end
  if #code > (maxBytes or D.MAX_ENCODED) then
    return nil, "too-large"
  end
  local LD = lib()
  -- Only the addon's own LibDeflate copy can stop inflating at a limit.
  if not (LD and LD._FG_MAX_OUTPUT) then
    return nil, "unavailable"
  end
  local okDecode, packed = pcall(LD.DecodeForPrint, LD, code)
  if not okDecode or not packed then
    return nil, "decode"
  end
  local okInflate, raw, status = pcall(LD.DecompressDeflate, LD, packed, D.MAX_RAW)
  if not okInflate or not raw then
    return nil, status == -20 and "too-large" or "decode"
  end
  if #raw > D.MAX_RAW then
    return nil, "too-large"
  end
  local ok, drawing, why = pcall(parse, raw)
  if not ok then
    return nil, "decode"
  end
  return drawing, why
end
