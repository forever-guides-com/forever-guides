-- Forever Chat, the rules of the add-on extras between two chat partners (pure, no frames, no game access):
-- the payloads of function chatPeer (code CP, inside the envelope of ns.Comm, whisper only), strict decoders,
-- the marks that name a chat line without sending its text, the send limits and the memory of what the other
-- side told us. ChatPeer.lua wires it to the line and to the window.
-- Payloads, printable ASCII, never a message text:
--   T  "1" typing starts or goes on, "0" typing stopped
--   S  <mark>                   the other side has seen our lines up to the line with this mark
--   E  <side>|<mark>|<symbol>|<on>   reaction: side "m" (the line is the sender's own) or "y" (the line is the
--                               receiver's), symbol 1 to #SYMBOLS, on "1" or "0"
--   X  (empty)                  goodbye: forget everything about me
-- A mark is 5 characters (0-9a-z): 3 from a hash of the line text, 2 from the time in steps of 4 seconds. Both
-- sides see the same text, the time may differ by a few seconds, so Resolve accepts MARK_TOLERANCE steps.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local PL = {}
chat.PeerLogic = PL

-- Seconds: typing messages per partner at most this often, seen bundled to one per this, reactions per second.
PL.TYPING_GAP = 4
PL.TYPING_TTL = 7
PL.SEEN_GAP = 5
PL.REACT_GAP = 1
PL.MAX_PARTNERS = 64
PL.MAX_REACTIONS = 60
-- Steps of 4 seconds a mark may be off when it is matched to a line.
PL.MARK_TOLERANCE = 3
PL.SCAN_LINES = 400

-- Fixed list of reaction symbols, plain text so every client font shows them.
PL.SYMBOLS = { "+1", "<3", ":)", ":o", ":(", "!!" }

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local MOD_HASH, MOD_TIME = 46656, 1296

local function finite(v)
  return type(v) == "number" and v == v and v > -1e12 and v < 1e12
end

local function base36(n, width)
  local out = {}
  for i = width, 1, -1 do
    local d = n % 36
    out[i] = DIGITS:sub(d + 1, d + 1)
    n = (n - d) / 36
  end
  return table.concat(out)
end

local function unbase36(s)
  local n = 0
  for i = 1, #s do
    local at = DIGITS:find(s:sub(i, i), 1, true)
    if not at then
      return nil
    end
    n = n * 36 + (at - 1)
  end
  return n
end

-- Marks ------------------------------------------------------------------------------------------------------

local function trimmed(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function hashOf(text)
  return FG.CommLogic.Crc32(trimmed(text)) % MOD_HASH
end

local function step(time)
  return math.floor(time / 4) % MOD_TIME
end

-- The mark of a line, nil for a line without readable text or time (a secret line has no mark).
function PL.Mark(text, time)
  if type(text) ~= "string" or not trimmed(text):find("%S") or not finite(time) then
    return nil
  end
  return base36(hashOf(text), 3) .. base36(step(time), 2)
end

function PL.ValidMark(mark)
  return type(mark) == "string" and #mark == 5 and not mark:find("[^0-9a-z]")
end

local function ringDistance(a, b)
  local d = math.abs(a - b) % MOD_TIME
  return math.min(d, MOD_TIME - d)
end

-- The seq of the line of `lines` that carries the mark, nil when none does. Only lines of the wanted
-- direction (out == true: our own lines) count; of several the nearest in time wins, the later one on a tie.
function PL.Resolve(lines, mark, out, dirOut)
  if type(lines) ~= "table" or not PL.ValidMark(mark) then
    return nil
  end
  local hash, at = unbase36(mark:sub(1, 3)), unbase36(mark:sub(4, 5))
  local best, bestDist
  local first = math.max(1, #lines - PL.SCAN_LINES + 1)
  for i = #lines, first, -1 do
    local line = lines[i]
    if
      type(line) == "table"
      and not line.hidden
      and type(line.text) == "string"
      and finite(line.time)
      and ((line.dir == dirOut) == (out == true))
      and hashOf(line.text) == hash
    then
      local dist = ringDistance(step(line.time), at)
      if dist <= PL.MARK_TOLERANCE and (not bestDist or dist < bestDist) then
        best, bestDist = line.seq, dist
      end
    end
  end
  return best
end

-- Payloads -----------------------------------------------------------------------------------------------------

function PL.EncodeTyping(on)
  return on and "1" or "0"
end

function PL.EncodeSeen(mark)
  return PL.ValidMark(mark) and mark or nil
end

function PL.EncodeReaction(side, mark, symbol, on)
  if (side ~= "m" and side ~= "y") or not PL.ValidMark(mark) or not PL.SymbolText(symbol) then
    return nil
  end
  return string.format("%s%s|%d|%d", side, mark, symbol, on and 1 or 0)
end

function PL.EncodeFarewell()
  return ""
end

function PL.SymbolText(id)
  return type(id) == "number" and PL.SYMBOLS[id] or nil
end

-- The value of a payload of type typ, nil for anything that is not exactly the format. Never raises.
function PL.Decode(typ, payload)
  if type(payload) ~= "string" or type(typ) ~= "string" or #payload > 24 or payload:find("[^ -~]") then
    return nil
  end
  if typ == "T" then
    if payload == "1" or payload == "0" then
      return { on = payload == "1" }
    end
  elseif typ == "S" then
    if PL.ValidMark(payload) then
      return { mark = payload }
    end
  elseif typ == "E" then
    local side, mark, symbol, on = payload:match("^([my])([0-9a-z]+)|(%d)|([01])$")
    symbol = tonumber(symbol)
    if side and PL.ValidMark(mark) and PL.SymbolText(symbol) then
      return { side = side, mark = mark, symbol = symbol, on = on == "1" }
    end
  elseif typ == "X" then
    if payload == "" then
      return { gone = true }
    end
  end
  return nil
end

-- Send limits ------------------------------------------------------------------------------------------------------

-- clock() returns seconds. State per partner key (any short string), memory only.
function PL.NewSender(clock)
  local S, partners, count = {}, {}, 0

  local function entry(key)
    local e = partners[key]
    if not e then
      if count >= PL.MAX_PARTNERS then
        partners, count = {}, 0
      end
      e = {}
      partners[key], count = e, count + 1
    end
    return e
  end

  -- The payload of T to send now, or nil: a start at most every TYPING_GAP seconds, a stop only after a start
  -- and only when the gap allows it (the other side lets the sign run out by itself).
  function S.Typing(key, active)
    local e, now = entry(key), clock()
    if active then
      if not e.typing or now - (e.typingAt or -math.huge) >= PL.TYPING_GAP then
        e.typing, e.typingAt = true, now
        return PL.EncodeTyping(true)
      end
      return nil
    end
    local was = e.typing
    e.typing = false
    if was and now - (e.typingAt or -math.huge) >= PL.TYPING_GAP then
      e.typingAt = now
      return PL.EncodeTyping(false)
    end
    return nil
  end

  -- Notes the newest line seen; TakeSeen hands it out bundled.
  function S.NoteSeen(key, mark)
    local e = entry(key)
    if PL.ValidMark(mark) and mark ~= e.seenSent then
      e.seenPending = mark
    end
  end

  -- The mark to send now, or nil and the seconds to wait (nil when nothing is pending).
  function S.TakeSeen(key)
    local e, now = entry(key), clock()
    if not e.seenPending then
      return nil
    end
    local wait = PL.SEEN_GAP - (now - (e.seenAt or -math.huge))
    if wait > 0 then
      return nil, wait
    end
    local mark = e.seenPending
    e.seenPending, e.seenSent, e.seenAt = nil, mark, now
    return mark
  end

  -- True when a reaction may go out now (one per REACT_GAP seconds and partner).
  function S.Reaction(key)
    local e, now = entry(key), clock()
    if now - (e.reactAt or -math.huge) >= PL.REACT_GAP then
      e.reactAt = now
      return true
    end
    return false
  end

  function S.Forget(key)
    if partners[key] then
      partners[key], count = nil, count - 1
    end
  end

  function S.Reset()
    partners, count = {}, 0
  end

  return S
end

-- What the other side told us ------------------------------------------------------------------------------------

-- State per partner key: typing (until a time), seen (seq of our own last line seen), reactions per line seq.
function PL.NewView(clock)
  local V, partners, count = {}, {}, 0

  local function entry(key, create)
    local e = partners[key]
    if not e and create then
      if count >= PL.MAX_PARTNERS then
        partners, count = {}, 0
      end
      e = { reactions = {}, lines = 0 }
      partners[key], count = e, count + 1
    end
    return e
  end

  function V.SetTyping(key, on)
    local e = entry(key, on)
    if e then
      e.typingUntil = on and clock() + PL.TYPING_TTL or nil
    end
  end

  function V.Typing(key)
    local e = entry(key)
    return e ~= nil and e.typingUntil ~= nil and clock() < e.typingUntil
  end

  function V.SetSeen(key, seq)
    local e = entry(key, finite(seq))
    if e and finite(seq) and seq > (e.seen or 0) then
      e.seen = seq
    end
  end

  function V.Seen(key)
    local e = entry(key)
    return e and e.seen or nil
  end

  -- who: "theirs" (the other side reacted) or "mine" (we did).
  function V.SetReaction(key, seq, symbol, who, on)
    if not finite(seq) or not PL.SymbolText(symbol) or (who ~= "theirs" and who ~= "mine") then
      return false
    end
    local e = entry(key, on)
    if not e then
      return true
    end
    local line = e.reactions[seq]
    if not line then
      if not on then
        return true
      end
      if e.lines >= PL.MAX_REACTIONS then
        local lowest
        for s in pairs(e.reactions) do
          lowest = (not lowest or s < lowest) and s or lowest
        end
        e.reactions[lowest], e.lines = nil, e.lines - 1
      end
      line = {}
      e.reactions[seq], e.lines = line, e.lines + 1
    end
    line[symbol] = line[symbol] or {}
    line[symbol][who] = on and true or nil
    if next(line[symbol]) == nil then
      line[symbol] = nil
      if next(line) == nil then
        e.reactions[seq], e.lines = nil, e.lines - 1
      end
    end
    return true
  end

  -- Symbol ids on a line in list order, and whether we set each ({ id, mine }).
  function V.Reactions(key, seq)
    local e = entry(key)
    local line = e and e.reactions[seq]
    local out = {}
    if line then
      for id = 1, #PL.SYMBOLS do
        if line[id] then
          out[#out + 1] = { id = id, mine = line[id].mine == true, theirs = line[id].theirs == true }
        end
      end
    end
    return out
  end

  function V.Clear(key)
    if partners[key] then
      partners[key], count = nil, count - 1
    end
  end

  function V.ClearAll()
    partners, count = {}, 0
  end

  -- Forgets one kind: "typing", "seen" or "reactions" (theirs only) for every partner.
  function V.ClearKind(kind)
    for _, e in pairs(partners) do
      if kind == "typing" then
        e.typingUntil = nil
      elseif kind == "seen" then
        e.seen = nil
      elseif kind == "reactions" then
        for seq, line in pairs(e.reactions) do
          for id, who in pairs(line) do
            who.theirs = nil
            if next(who) == nil then
              line[id] = nil
            end
          end
          if next(line) == nil then
            e.reactions[seq], e.lines = nil, e.lines - 1
          end
        end
      end
    end
  end

  return V
end
