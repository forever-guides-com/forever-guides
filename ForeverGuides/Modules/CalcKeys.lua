-- Calculator key logic, pure text functions without frames: UTF-8 helpers, the filter for typed
-- characters, the operand search behind 1/x, x², sqrt and the sign key, and the font fit of
-- the display. Modules/CalcView.lua owns the frames and calls these with the input box text.
--
-- All positions are character counts (not bytes). A cursor of n sits behind the n-th character.
local _, ns = ...
local P = ns.CalcParser

local K = {}
ns.CalcKeys = K

local CHAR = "[\1-\127\194-\244][\128-\191]*"

-- Text helpers ----------------------------------------------------------------------------------

function K.Chars(s)
  local out = {}
  for ch in s:gmatch(CHAR) do
    out[#out + 1] = ch
  end
  return out
end

function K.CharCount(s)
  return select(2, s:gsub("[^\128-\191]", ""))
end

-- Byte length of the first n UTF-8 characters.
function K.CharBytes(s, n)
  local i = 1
  for _ = 1, n do
    local b = s:byte(i)
    if not b then
      break
    end
    i = i + (b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1)
  end
  return i - 1
end

-- Typed characters -------------------------------------------------------------------------------

local KEEP = {}
for ch in ("+-*/^,.%():;× ÷"):gmatch(CHAR) do
  KEEP[ch] = true
end

-- Letters make sense only as the coin units g s c or as (the start of) a word of the parser.
local WORDS = { "ans" }
for name in pairs(P.FUNCS) do
  WORDS[#WORDS + 1] = name
end

local function letterRun(run)
  if run == "g" or run == "s" or run == "c" then
    return true
  end
  for _, word in ipairs(WORDS) do
    if word:sub(1, #run) == run then
      return true
    end
  end
  return false
end

-- Filters what the client typed or pasted into the input: digits and operators stay, the
-- minus sign of the typographic kind becomes "-", letters stay only as part of g s c, ans and
-- the function names, everything else goes. "=" is dropped and reported (the caller evaluates).
-- Returns the clean text, the cursor behind the same character as before and whether "=" was seen.
function K.Sanitize(text, cursor)
  local out, run, equals, outCursor, index = {}, "", false, nil, 0
  if cursor == 0 then
    outCursor = 0
  end
  for ch in text:gmatch(CHAR) do
    index = index + 1
    local keep
    if ch:match("^%d$") or KEEP[ch] then
      keep, run = ch, ""
    elseif ch == "−" then
      keep, run = "-", ""
    elseif ch == "=" then
      equals, run = true, ""
    elseif ch:match("^%a$") then
      local low = ch:lower()
      if letterRun(run .. low) then
        run, keep = run .. low, low
      end
    else
      run = ""
    end
    out[#out + 1] = keep
    if index == cursor then
      outCursor = #out
    end
  end
  return table.concat(out), outCursor or #out, equals
end

local OPERATOR = {}
for ch in ("+-*/^%×÷:"):gmatch(CHAR) do
  OPERATOR[ch] = true
end

-- True when the text starts with an operator, so it continues the last result instead of
-- starting a new calculation.
function K.StartsWithOperator(text)
  local first = text:match("^" .. CHAR)
  return first ~= nil and OPERATOR[first] == true
end

-- Operands ---------------------------------------------------------------------------------------

local function isDigit(c)
  return c ~= nil and c:match("^%d$") ~= nil
end

local function isLetter(c)
  return c ~= nil and c:match("^%a$") ~= nil
end

local function isSeparator(c)
  return c == "." or c == ","
end

local function skipSpaces(chars, i)
  while i >= 1 and chars[i] == " " do
    i = i - 1
  end
  return i
end

local function isUnit(chars, i)
  local c = chars[i]
  return (c == "g" or c == "s" or c == "c") and isDigit(chars[i - 1])
end

-- Start index of the digits (with separator) that end at i, nil without a digit.
local function numberStart(chars, i)
  local j = i
  while j >= 1 and (isDigit(chars[j]) or isSeparator(chars[j])) do
    j = j - 1
  end
  return j < i and isDigit(chars[i]) and j + 1 or nil
end

-- Opening bracket that matches the closing one at i.
local function matchOpen(chars, i)
  local depth = 0
  for j = i, 1, -1 do
    if chars[j] == ")" then
      depth = depth + 1
    elseif chars[j] == "(" then
      depth = depth - 1
      if depth == 0 then
        return j
      end
    end
  end
  return nil
end

-- The operand that ends at (or, behind spaces, right before) the position `pos`: a number with
-- its unit and % sign, a coin literal (12g 50s), ans, or a bracket group with the function name in
-- front. Returns its first and last character index, or nil.
function K.Operand(chars, pos)
  local last = skipSpaces(chars, pos)
  local e = last
  if chars[e] == "%" then
    e = e - 1
  end
  local first
  if chars[e] == ")" then
    first = matchOpen(chars, e)
    if first then
      local j = first
      while isLetter(chars[j - 1]) do
        j = j - 1
      end
      if j < first and P.FUNCS[table.concat(chars, "", j, first - 1):lower()] then
        first = j
      end
    end
  elseif chars[e] == "s" and chars[e - 1] == "n" and chars[e - 2] == "a" and not isLetter(chars[e - 3]) then
    first = e - 2
  else
    local unit = isUnit(chars, e)
    first = numberStart(chars, unit and e - 1 or e)
    -- A coin literal spans several parts: 12g 50s 3c.
    while first and unit do
      local k = skipSpaces(chars, first - 1)
      local start = isUnit(chars, k) and numberStart(chars, k - 1)
      if not start then
        break
      end
      first = start
    end
  end
  if not first then
    return nil
  end
  return first, last
end

-- True when the minus sign at index i has no left operand (start, operator or open bracket).
local function unaryMinus(chars, i)
  if chars[i] ~= "-" then
    return false
  end
  local prev = skipSpaces(chars, i - 1)
  return prev < 1 or OPERATOR[chars[prev]] == true or chars[prev] == "(" or chars[prev] == ";"
end

-- True when chars[first..last] is one bracket group.
local function isGroup(chars, first, last)
  return chars[first] == "(" and chars[last] == ")" and matchOpen(chars, last) == first
end

-- The first character of the operand including a unary minus in front of it.
local function withSign(chars, first)
  if unaryMinus(chars, first - 1) then
    return first - 1
  end
  return first
end

local function replace(chars, pos, first, last, text)
  local head = table.concat(chars, "", 1, first - 1)
  local tail = table.concat(chars, "", last + 1)
  return head .. text .. tail, first - 1 + K.CharCount(text) + (pos - last)
end

-- 1/x, x², sqrt and the sign key on the operand before the cursor. kind: "inv", "sqr", "sqrt",
-- "neg". Returns the new text and cursor, or nil when there is no operand to work on.
function K.Transform(text, cursor, kind)
  local chars = K.Chars(text)
  local first, last = K.Operand(chars, cursor)
  if not first then
    if kind == "neg" then
      return text:sub(1, K.CharBytes(text, cursor)) .. "-" .. text:sub(K.CharBytes(text, cursor) + 1), cursor + 1
    end
    return nil
  end
  if kind == "neg" then
    -- "(-5)": take the sign and the brackets away again.
    if isGroup(chars, first, last) and chars[first + 1] == "-" then
      local inner = table.concat(chars, "", first + 2, last - 1)
      local rest = K.Chars(inner)
      local a, b = K.Operand(rest, #rest)
      if a == 1 and b == #rest then
        return replace(chars, cursor, first, last, inner)
      end
    end
    if unaryMinus(chars, first - 1) then
      return replace(chars, cursor, first - 1, last, table.concat(chars, "", first, last))
    end
    local operand = table.concat(chars, "", first, last)
    local prev = skipSpaces(chars, first - 1)
    if prev < 1 or chars[prev] == "(" then
      return replace(chars, cursor, first, last, "-" .. operand)
    end
    return replace(chars, cursor, first, last, "(-" .. operand .. ")")
  end
  first = withSign(chars, first)
  local operand = table.concat(chars, "", first, last)
  local group = isGroup(chars, first, last)
  local out
  if kind == "inv" then
    out = group and "1/" .. operand or "1/(" .. operand .. ")"
  elseif kind == "sqr" then
    out = group and operand .. "^2" or "(" .. operand .. ")^2"
  else
    out = group and "sqrt" .. operand or "sqrt(" .. operand .. ")"
  end
  return replace(chars, cursor, first, last, out)
end

-- CE: the last number of the input goes, the cursor to the end. Without a number at the end
-- (operator, bracket) one character goes. Returns the new text and cursor.
function K.ClearEntry(text)
  local chars = K.Chars(text)
  if #chars == 0 then
    return "", 0
  end
  local first = K.Operand(chars, #chars)
  if first and skipSpaces(chars, #chars) == #chars then
    first = withSign(chars, first)
    return table.concat(chars, "", 1, first - 1), first - 1
  end
  return table.concat(chars, "", 1, #chars - 1), #chars - 1
end

-- Display ------------------------------------------------------------------------------------------

-- The largest font size from maxSize down to minSize at which measure(size) stays within avail.
-- Returns the size and whether the text still overflows at the smallest size.
function K.FitSize(measure, maxSize, minSize, avail)
  local width = measure(maxSize)
  if width <= avail then
    return maxSize, false
  end
  local size = math.max(minSize, math.min(maxSize, math.floor(maxSize * avail / math.max(1, width))))
  while size > minSize and measure(size) > avail do
    size = size - 1
  end
  return size, measure(size) > avail
end

-- Preview of an unfinished input ------------------------------------------------------------------

-- The longest part of an input that can be calculated while typing goes on: operators, separators,
-- an open bracket (with its function name) and half-typed words at the end are dropped, open
-- brackets are closed. Returns nil when nothing is left.
function K.Complete(text)
  local chars = K.Chars(text)
  local n = #chars
  while n > 0 do
    local c = chars[n]
    if c == " " or c == "," or c == "." or c == ";" or (OPERATOR[c] and c ~= "%") then
      n = n - 1
    elseif c == "(" then
      n = n - 1
      while isLetter(chars[n]) do
        n = n - 1
      end
    elseif isLetter(c) then
      local j = n
      while isLetter(chars[j]) do
        j = j - 1
      end
      local word = table.concat(chars, "", j + 1, n)
      if word == "ans" or (#word == 1 and isUnit(chars, n)) then
        break
      end
      n = j
    else
      break
    end
  end
  if n == 0 then
    return nil
  end
  local out = table.concat(chars, "", 1, n)
  local balance = select(2, out:gsub("%(", "")) - select(2, out:gsub("%)", ""))
  return out .. (balance > 0 and (")"):rep(balance) or "")
end
