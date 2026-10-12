-- Exact arithmetic for the calculator, pure Lua 5.1, no floating point in the value itself.
-- Decimals come first (parsing, printing, single operations), the exact rationals D.Q at the
-- end of the file evaluate whole expressions. A decimal is { s = sign (-1, 0, 1), m = magnitude
-- limbs, e = exponent } and stands for s * m * 10^e. Limbs are base 10^7, little endian, so a
-- limb product plus carries stays below 2^53. Values are canonical (no trailing decimal zero
-- in m, zero has e = 0) and immutable. Failing operations return nil plus an error code,
-- never error().
local _, ns = ...

local D = {
  PRECISION = 30, -- significant digits of a division or square root
  MAX_DIGITS = 400, -- printed digits of any result
  MAX_INPUT = 200, -- characters accepted by fromString
  MAX_POW = 1000, -- largest absolute integer exponent
}
ns.CalcDecimal = D

local BASE, BD = 10000000, 7
local floor = math.floor
local byte = string.byte

local POW10 = { [0] = 1 }
for i = 1, BD do
  POW10[i] = POW10[i - 1] * 10
end

-- Magnitude helpers. Arrays are never mutated after they have been returned.

local function trim(m)
  local n = #m
  while n > 0 and m[n] == 0 do
    m[n] = nil
    n = n - 1
  end
  return m
end

local function magCmp(a, b)
  local na, nb = #a, #b
  if na ~= nb then
    return na < nb and -1 or 1
  end
  for i = na, 1, -1 do
    if a[i] ~= b[i] then
      return a[i] < b[i] and -1 or 1
    end
  end
  return 0
end

local function magAdd(a, b)
  local r, carry = {}, 0
  local n = math.max(#a, #b)
  for i = 1, n do
    local s = (a[i] or 0) + (b[i] or 0) + carry
    if s >= BASE then
      r[i], carry = s - BASE, 1
    else
      r[i], carry = s, 0
    end
  end
  if carry > 0 then
    r[n + 1] = carry
  end
  return r
end

-- Requires a >= b.
local function magSub(a, b)
  local r, borrow = {}, 0
  for i = 1, #a do
    local s = a[i] - (b[i] or 0) - borrow
    if s < 0 then
      r[i], borrow = s + BASE, 1
    else
      r[i], borrow = s, 0
    end
  end
  return trim(r)
end

local function magMulSmall(a, k)
  if k == 0 or #a == 0 then
    return {}
  end
  local r, carry = {}, 0
  for i = 1, #a do
    local cur = a[i] * k + carry
    local rem = cur % BASE
    r[i] = rem
    carry = (cur - rem) / BASE
  end
  local n = #a
  while carry > 0 do
    n = n + 1
    local rem = carry % BASE
    r[n] = rem
    carry = (carry - rem) / BASE
  end
  return r
end

local function magMul(a, b)
  local na, nb = #a, #b
  if na == 0 or nb == 0 then
    return {}
  end
  local r = {}
  for i = 1, na + nb do
    r[i] = 0
  end
  for i = 1, na do
    local ai, carry = a[i], 0
    if ai ~= 0 then
      for j = 1, nb do
        local cur = r[i + j - 1] + ai * b[j] + carry
        local rem = cur % BASE
        r[i + j - 1] = rem
        carry = (cur - rem) / BASE
      end
      local k = i + nb
      while carry > 0 do
        local cur = r[k] + carry
        local rem = cur % BASE
        r[k] = rem
        carry = (cur - rem) / BASE
        k = k + 1
      end
    end
  end
  return trim(r)
end

-- Quotient and remainder by a number below 10^7.
local function magDivSmall(a, k)
  local q, rem = {}, 0
  for i = 1, #a do
    q[i] = 0
  end
  for i = #a, 1, -1 do
    local cur = rem * BASE + a[i]
    local r = cur % k
    q[i] = (cur - r) / k
    rem = r
  end
  return trim(q), rem
end

-- a * 10^k
local function magShift(a, k)
  if #a == 0 or k == 0 then
    return a
  end
  local r = {}
  for i = 1, floor(k / BD) do
    r[i] = 0
  end
  local part = magMulSmall(a, POW10[k % BD])
  local off = #r
  for i = 1, #part do
    r[off + i] = part[i]
  end
  return r
end

local function magDigits(a)
  local n = #a
  if n == 0 then
    return 0
  end
  local top, d = a[n], 0
  while top > 0 do
    d = d + 1
    top = floor(top / 10)
  end
  return (n - 1) * BD + d
end

-- Removes the k lowest digits. Returns the quotient, the most significant removed digit
-- and whether any lower removed digit is nonzero.
local function magDrop(a, k)
  if k <= 0 then
    return a, 0, false
  end
  local li = floor((k - 1) / BD) + 1
  local off = (k - 1) % BD
  local limb = a[li] or 0
  local first = floor(limb / POW10[off]) % 10
  local rest = limb % POW10[off] ~= 0
  if not rest then
    for i = 1, li - 1 do
      if a[i] ~= 0 then
        rest = true
        break
      end
    end
  end
  local q = {}
  for i = floor(k / BD) + 1, #a do
    q[#q + 1] = a[i]
  end
  if k % BD > 0 then
    q = magDivSmall(q, POW10[k % BD])
  end
  return q, first, rest
end

-- Long division after Knuth (algorithm D) in base 10^7. The quotient limb is estimated
-- from the two leading limbs of the running remainder and the leading divisor limb.
local function magDivmod(a, b)
  if magCmp(a, b) < 0 then
    return {}, a
  end
  if #b == 1 then
    local q, r = magDivSmall(a, b[1])
    return q, r > 0 and { r } or {}
  end
  local n = #b
  -- Scaling by f makes the leading divisor limb at least BASE / 2, so the estimate is off by at most 2.
  local f = floor(BASE / (b[n] + 1))
  local u, v = magMulSmall(a, f), b
  if f > 1 then
    v = magMulSmall(b, f)
  end
  local na = #a
  for i = #u + 1, na + 1 do
    u[i] = 0
  end
  local vt, vs = v[n], v[n - 1]
  local q = {}
  for j = na - n, 0, -1 do
    local top = u[j + n + 1] * BASE + u[j + n]
    local qhat = floor(top / vt)
    local rhat = top - qhat * vt
    if rhat < 0 then
      qhat, rhat = qhat - 1, rhat + vt
    end
    while qhat >= BASE or qhat * vs > rhat * BASE + u[j + n - 1] do
      qhat, rhat = qhat - 1, rhat + vt
      if rhat >= BASE then
        break
      end
    end
    local carry, borrow = 0, 0
    for i = 1, n do
      local p = qhat * v[i] + carry
      local lo = p % BASE
      carry = (p - lo) / BASE
      local cur = u[i + j] - lo - borrow
      if cur < 0 then
        u[i + j], borrow = cur + BASE, 1
      else
        u[i + j], borrow = cur, 0
      end
    end
    local cur = u[j + n + 1] - carry - borrow
    if cur < 0 then
      -- The estimate was one too large: add the divisor back once.
      qhat = qhat - 1
      local c = 0
      for i = 1, n do
        local sum = u[i + j] + v[i] + c
        if sum >= BASE then
          u[i + j], c = sum - BASE, 1
        else
          u[i + j], c = sum, 0
        end
      end
      cur = 0
    end
    u[j + n + 1] = cur
    q[j + 1] = qhat
  end
  for i = n + 1, #u do
    u[i] = nil
  end
  local r = trim(u)
  if f > 1 then
    r = magDivSmall(r, f)
  end
  return trim(q), r
end

-- floor(sqrt(n)) by Newton iteration from an upper bound, n > 0.
local function magIsqrt(n)
  local x = magShift({ 1 }, math.ceil(magDigits(n) / 2))
  while true do
    local q = magDivmod(n, x)
    local y = magDivSmall(magAdd(x, q), 2)
    if magCmp(y, x) >= 0 then
      return x
    end
    x = y
  end
end

-- Values

local ZERO = { s = 0, m = {}, e = 0 }
D.ZERO = ZERO

-- m must be trimmed. Strips trailing zero digits into the exponent.
local function make(sign, m, e)
  if #m == 0 then
    return ZERO
  end
  local lo = 1
  while m[lo] == 0 do
    lo = lo + 1
  end
  if lo > 1 then
    local t = {}
    for i = lo, #m do
      t[#t + 1] = m[i]
    end
    m, e = t, e + (lo - 1) * BD
  end
  local low, z = m[1], 0
  while low % 10 == 0 do
    low = low / 10
    z = z + 1
  end
  if z > 0 then
    m, e = magDivSmall(m, POW10[z]), e + z
  end
  return { s = sign, m = m, e = e }
end

local function isDigit(b)
  return b ~= nil and b >= 48 and b <= 57
end

local function fromDigits(sign, digits, e)
  local start = 1
  while byte(digits, start) == 48 do
    start = start + 1
  end
  if start > #digits then
    return ZERO
  end
  local m, i = {}, #digits
  while i >= start do
    local from = math.max(start, i - BD + 1)
    local v = 0
    for p = from, i do
      v = v * 10 + (byte(digits, p) - 48)
    end
    m[#m + 1] = v
    i = from - 1
  end
  return make(sign, m, e)
end

-- Digits a printed value has (integer part, zeros and fraction).
local function printedSize(x)
  if x.s == 0 then
    return 1
  end
  local nd = magDigits(x.m)
  if x.e >= 0 then
    return nd + x.e
  end
  return nd + x.e > 0 and nd or 1 - x.e
end

local function limit(x)
  if printedSize(x) > D.MAX_DIGITS then
    return nil, "toolarge"
  end
  return x
end

local ONE = fromDigits(1, "1", 0)
local HALF = fromDigits(1, "5", -1)
D.ONE = ONE

-- Parses [+-]digits[.digits] (also .5), nothing else. Returns nil plus "syntax" or "toolarge".
function D.fromString(str)
  if type(str) ~= "string" then
    return nil, "syntax"
  end
  local n = #str
  if n > D.MAX_INPUT then
    return nil, "toolarge"
  end
  local i, sign = 1, 1
  local c = byte(str, 1)
  if c == 45 then
    sign, i = -1, 2
  elseif c == 43 then
    i = 2
  end
  local j = i
  while isDigit(byte(str, j)) do
    j = j + 1
  end
  local ip, fp = str:sub(i, j - 1), ""
  if byte(str, j) == 46 then
    local k = j + 1
    while isDigit(byte(str, k)) do
      k = k + 1
    end
    fp, j = str:sub(j + 1, k - 1), k
  end
  if j ~= n + 1 or (ip == "" and fp == "") then
    return nil, "syntax"
  end
  return fromDigits(sign, ip .. fp, -#fp)
end

-- Whole numbers below 2^53 (constants, tests).
function D.fromInt(n)
  return (D.fromString(string.format("%.0f", n)))
end

-- Integer values below 10^4 in magnitude as a Lua number (exponents, decimal places).
function D.toInt(x)
  if x.s == 0 then
    return 0
  end
  if x.e < 0 then
    return nil, "badprecision"
  end
  if magDigits(x.m) + x.e > 4 then
    return nil, "toolarge"
  end
  return x.s * x.m[1] * POW10[x.e]
end

function D.sign(x)
  return x.s
end

function D.isZero(x)
  return x.s == 0
end

function D.isInteger(x)
  return x.s == 0 or x.e >= 0
end

function D.neg(x)
  if x.s == 0 then
    return x
  end
  return { s = -x.s, m = x.m, e = x.e }
end

function D.abs(x)
  if x.s >= 0 then
    return x
  end
  return { s = 1, m = x.m, e = x.e }
end

local function magToString(m)
  local n = #m
  local parts = { string.format("%d", m[n]) }
  for i = n - 1, 1, -1 do
    parts[#parts + 1] = string.format("%07d", m[i])
  end
  return table.concat(parts)
end

-- Plain notation, never an exponent.
function D.toString(x)
  if x.s == 0 then
    return "0"
  end
  local ds, e = magToString(x.m), x.e
  local out
  if e >= 0 then
    out = ds .. string.rep("0", e)
  elseif #ds > -e then
    out = ds:sub(1, #ds + e) .. "." .. ds:sub(#ds + e + 1)
  else
    out = "0." .. string.rep("0", -e - #ds) .. ds
  end
  return x.s < 0 and "-" .. out or out
end

-- For display heuristics only, never for calculation.
function D.toNumber(x)
  return tonumber(D.toString(x)) or 0
end

local function align(a, b)
  if a.e == b.e then
    return a.m, b.m, a.e
  elseif a.e > b.e then
    return magShift(a.m, a.e - b.e), b.m, b.e
  end
  return a.m, magShift(b.m, b.e - a.e), a.e
end

function D.cmp(a, b)
  if a.s ~= b.s then
    return a.s < b.s and -1 or 1
  end
  if a.s == 0 then
    return 0
  end
  local pa, pb = magDigits(a.m) + a.e, magDigits(b.m) + b.e
  local c
  if pa ~= pb then
    c = pa < pb and -1 or 1
  else
    local ma, mb = align(a, b)
    c = magCmp(ma, mb)
  end
  return c == 0 and 0 or c * a.s
end

function D.add(a, b)
  if a.s == 0 then
    return b
  elseif b.s == 0 then
    return a
  end
  local ma, mb, e = align(a, b)
  if a.s == b.s then
    return limit(make(a.s, magAdd(ma, mb), e))
  end
  local c = magCmp(ma, mb)
  if c == 0 then
    return ZERO
  elseif c > 0 then
    return limit(make(a.s, magSub(ma, mb), e))
  end
  return limit(make(b.s, magSub(mb, ma), e))
end

function D.sub(a, b)
  return D.add(a, D.neg(b))
end

function D.mul(a, b)
  if a.s == 0 or b.s == 0 then
    return ZERO
  end
  return limit(make(a.s * b.s, magMul(a.m, b.m), a.e + b.e))
end

-- x * 10^k, exact.
function D.shift10(x, k)
  if x.s == 0 then
    return x
  end
  return limit(make(x.s, x.m, x.e + k))
end

-- Rounds the integer q (magnitude of a truncated result) up when the first dropped digit is 5 or more.
local function roundHalfUp(q, first)
  return first >= 5 and magAdd(q, { 1 }) or q
end

-- Quotient to 30 significant digits, half away from zero. The second result is true when
-- the returned value differs from the exact quotient.
function D.div(a, b)
  if b.s == 0 then
    return nil, "divzero"
  end
  if a.s == 0 then
    return ZERO, false
  end
  -- Scale so the integer quotient has at least PRECISION + 1 digits.
  local k = D.PRECISION + 1 - (magDigits(a.m) - magDigits(b.m))
  if k < 0 then
    k = 0
  end
  local q, r = magDivmod(magShift(a.m, k), b.m)
  local e = a.e - b.e - k
  local inexact = #r > 0
  local drop = magDigits(q) - D.PRECISION
  if drop > 0 then
    local first, rest
    q, first, rest = magDrop(q, drop)
    inexact = inexact or first ~= 0 or rest
    q = roundHalfUp(q, first)
    e = e + drop
  end
  local res, code = limit(make(a.s * b.s, q, e))
  if not res then
    return nil, code
  end
  return res, inexact
end

-- Exact for perfect squares, otherwise 30 significant digits.
function D.sqrt(x)
  if x.s < 0 then
    return nil, "negsqrt"
  end
  if x.s == 0 then
    return ZERO, false
  end
  local m, e = x.m, x.e
  if e % 2 ~= 0 then
    m, e = magShift(m, 1), e - 1
  end
  local s = magIsqrt(m)
  if magCmp(magMul(s, s), m) == 0 then
    local res, code = limit(make(1, s, e / 2))
    if not res then
      return nil, code
    end
    return res, false
  end
  -- Not a perfect square, so the root is irrational: take at least PRECISION + 1 digits.
  local extra = 2 * math.max(0, math.ceil((2 * (D.PRECISION + 1) - magDigits(m)) / 2))
  s = magIsqrt(magShift(m, extra))
  local drop = magDigits(s) - D.PRECISION
  local q, first = magDrop(s, drop)
  local res, code = limit(make(1, roundHalfUp(q, first), (e - extra) / 2 + drop))
  if not res then
    return nil, code
  end
  return res, true
end

-- Whole-number exponents are exact (up to MAX_POW and MAX_DIGITS). A negative exponent is
-- 1 / x^n. The exponent 0.5 is the square root. 0^0 is 1.
function D.pow(a, b)
  if not D.isInteger(b) then
    if D.cmp(b, HALF) == 0 then
      return D.sqrt(a)
    end
    return nil, "badexp"
  end
  if b.s == 0 then
    return ONE, false
  end
  local n = D.toInt(b)
  if not n or math.abs(n) > D.MAX_POW then
    return nil, "toolarge"
  end
  local neg = n < 0
  n = math.abs(n)
  if a.s == 0 then
    if neg then
      return nil, "zeropow"
    end
    return ZERO, false
  end
  -- x^n has at least (digits - 1) * n + 1 digits.
  if (magDigits(a.m) - 1) * n + 1 > D.MAX_DIGITS then
    return nil, "toolarge"
  end
  local result, base, k = nil, a.m, n
  while true do
    if k % 2 == 1 then
      result = result and magMul(result, base) or base
      if magDigits(result) > D.MAX_DIGITS then
        return nil, "toolarge"
      end
    end
    k = floor(k / 2)
    if k == 0 then
      break
    end
    base = magMul(base, base)
    if magDigits(base) > D.MAX_DIGITS then
      return nil, "toolarge"
    end
  end
  local res, code = limit(make(a.s < 0 and n % 2 == 1 and -1 or 1, result, a.e * n))
  if not res then
    return nil, code
  end
  if neg then
    return D.div(ONE, res)
  end
  return res, false
end

-- Rounds to n decimal places (n may be negative), half away from zero. The second result
-- tells whether the value changed.
function D.round(x, n)
  local target = -(n or 0)
  if x.s == 0 or x.e >= target then
    return x, false
  end
  local q, first = magDrop(x.m, target - x.e)
  local res, code = limit(make(x.s, roundHalfUp(q, first), target))
  if not res then
    return nil, code
  end
  return res, true
end

local function toInteger(x, up)
  if x.s == 0 or x.e >= 0 then
    return x
  end
  local q = magDrop(x.m, -x.e)
  if up then
    q = magAdd(q, { 1 })
  end
  return make(x.s, q, 0)
end

function D.floor(x)
  return toInteger(x, x.s < 0)
end

function D.ceil(x)
  return toInteger(x, x.s > 0)
end

-- Exact rational values for the calculator. { s = sign, n = numerator limbs, d = denominator
-- limbs (never zero), approx, red }. Nothing is rounded while an expression is evaluated, the
-- result is rounded once in Q.toDecimal. approx marks a value that went through the square
-- root approximation and travels through every later operation. red means n / d is known to
-- be in lowest terms. Values are immutable except for that cache flag.
local Q = {}
D.Q = Q

D.MAX_RATIONAL_DIGITS = 1200 -- digits of a numerator or denominator, above this: toolarge
D.REDUCE_DIGITS = 150 -- a larger numerator or denominator is cancelled by the gcd
D.SQRT_DIGITS = 40 -- significant digits of an irrational square root

local ONEM = { 1 }

local function isOne(m)
  return #m == 1 and m[1] == 1
end

local function mulMag(a, b)
  if isOne(a) then
    return b
  elseif isOne(b) then
    return a
  end
  return magMul(a, b)
end

local function pow10Mag(k)
  return magShift(ONEM, k)
end

-- k when m is 10^k, else nil.
local function pow10Exp(m)
  local n = #m
  for i = 1, n - 1 do
    if m[i] ~= 0 then
      return nil
    end
  end
  for i = 0, BD - 1 do
    if m[n] == POW10[i] then
      return (n - 1) * BD + i
    end
  end
  return nil
end

local function magGcd(a, b)
  while #b > 0 do
    if #a <= 2 and #b <= 2 then
      -- Both below 10^14: plain doubles are exact.
      local x, y = (a[2] or 0) * BASE + (a[1] or 0), (b[2] or 0) * BASE + (b[1] or 0)
      while y > 0 do
        x, y = y, x % y
      end
      return trim({ x % BASE, floor(x / BASE) })
    end
    local _, r = magDivmod(a, b)
    a, b = b, r
  end
  return a
end

local function reduceMags(n, d)
  if isOne(d) then
    return n, d
  end
  local g = magGcd(n, d)
  if isOne(g) then
    return n, d
  end
  return (magDivmod(n, g)), (magDivmod(d, g))
end

-- Builds a value from fresh magnitudes. Cancels large fractions and enforces the size limit.
local function normalize(s, n, d, approx, red)
  if #n == 0 then
    return { s = 0, n = {}, d = ONEM, approx = approx or nil, red = true }
  end
  if not red and (magDigits(n) > D.REDUCE_DIGITS or magDigits(d) > D.REDUCE_DIGITS) then
    n, d = reduceMags(n, d)
    red = true
  end
  if magDigits(n) > D.MAX_RATIONAL_DIGITS or magDigits(d) > D.MAX_RATIONAL_DIGITS then
    return nil, "toolarge"
  end
  return { s = s, n = n, d = d, approx = approx or nil, red = (red or isOne(d)) or nil }
end

-- The same value with the approx flag set when flag is true.
local function tag(q, flag)
  if flag and not q.approx then
    return { s = q.s, n = q.n, d = q.d, approx = true, red = q.red }
  end
  return q
end

Q.ZERO = { s = 0, n = {}, d = ONEM, red = true }
Q.ONE = { s = 1, n = ONEM, d = ONEM, red = true }

function Q.fromDecimal(x)
  if x.s == 0 then
    return Q.ZERO
  end
  if x.e >= 0 then
    return { s = x.s, n = magShift(x.m, x.e), d = ONEM, red = true }
  end
  return { s = x.s, n = x.m, d = pow10Mag(-x.e) }
end

-- Shape check for values that came from outside (the previous answer).
function Q.isValue(q)
  return type(q) == "table"
    and (q.s == -1 or q.s == 0 or q.s == 1)
    and type(q.n) == "table"
    and type(q.d) == "table"
    and #q.d > 0
    and (q.s == 0) == (#q.n == 0)
end

function Q.reduce(q)
  if q.red or isOne(q.d) then
    return q
  end
  local n, d = reduceMags(q.n, q.d)
  q.red = true
  if n == q.n then
    return q
  end
  return { s = q.s, n = n, d = d, approx = q.approx, red = true }
end

function Q.neg(q)
  if q.s == 0 then
    return q
  end
  return { s = -q.s, n = q.n, d = q.d, approx = q.approx, red = q.red }
end

function Q.abs(q)
  if q.s >= 0 then
    return q
  end
  return { s = 1, n = q.n, d = q.d, approx = q.approx, red = q.red }
end

function Q.add(a, b)
  if a.s == 0 then
    return tag(b, a.approx)
  elseif b.s == 0 then
    return tag(a, b.approx)
  end
  local n1, n2, d
  if magCmp(a.d, b.d) == 0 then
    n1, n2, d = a.n, b.n, a.d
  else
    n1, n2, d = mulMag(a.n, b.d), mulMag(b.n, a.d), mulMag(a.d, b.d)
  end
  local approx = a.approx or b.approx
  if a.s == b.s then
    return normalize(a.s, magAdd(n1, n2), d, approx)
  end
  local c = magCmp(n1, n2)
  if c == 0 then
    return normalize(0, {}, d, approx)
  elseif c > 0 then
    return normalize(a.s, magSub(n1, n2), d, approx)
  end
  return normalize(b.s, magSub(n2, n1), d, approx)
end

function Q.sub(a, b)
  return Q.add(a, Q.neg(b))
end

function Q.mul(a, b)
  local approx = a.approx or b.approx
  if a.s == 0 or b.s == 0 then
    return normalize(0, {}, ONEM, approx)
  end
  return normalize(a.s * b.s, mulMag(a.n, b.n), mulMag(a.d, b.d), approx)
end

function Q.div(a, b)
  if b.s == 0 then
    return nil, "divzero"
  end
  local approx = a.approx or b.approx
  if a.s == 0 then
    return normalize(0, {}, ONEM, approx)
  end
  return normalize(a.s * b.s, mulMag(a.n, b.d), mulMag(a.d, b.n), approx)
end

-- x * 10^k, exact.
function Q.shift10(q, k)
  if q.s == 0 or k == 0 then
    return q
  end
  if k > 0 then
    return normalize(q.s, magShift(q.n, k), q.d, q.approx)
  end
  return normalize(q.s, q.n, magShift(q.d, -k), q.approx)
end

-- Cross multiplication is exact for any representation, no cancelling needed.
function Q.cmp(a, b)
  if a.s ~= b.s then
    return a.s < b.s and -1 or 1
  end
  if a.s == 0 then
    return 0
  end
  local c = magCmp(mulMag(a.n, b.d), mulMag(b.n, a.d))
  return c == 0 and 0 or c * a.s
end

-- Integer quotient of n / d, half up, and whether a remainder was dropped.
local function roundDiv(n, d)
  local q, r = magDivmod(n, d)
  if #r == 0 then
    return q, false
  end
  if magCmp(magMulSmall(r, 2), d) >= 0 then
    q = magAdd(q, ONEM)
  end
  return q, true
end

local function toIntegerQ(q, up)
  if q.s == 0 or isOne(q.d) then
    return q
  end
  local m, r = magDivmod(q.n, q.d)
  if #r > 0 and up then
    m = magAdd(m, ONEM)
  end
  return normalize(q.s, m, ONEM, q.approx, true)
end

function Q.floor(q)
  return toIntegerQ(q, q.s < 0)
end

function Q.ceil(q)
  return toIntegerQ(q, q.s > 0)
end

-- Rounds to n decimal places (n may be negative), half away from zero. The result is exact.
function Q.round(q, places)
  if q.s == 0 or (places >= 0 and isOne(q.d)) then
    return q
  end
  if places >= 0 then
    return normalize(q.s, (roundDiv(magShift(q.n, places), q.d)), pow10Mag(places), q.approx)
  end
  local m = roundDiv(q.n, magShift(q.d, -places))
  return normalize(q.s, magShift(m, -places), ONEM, q.approx, true)
end

-- Whole values below 10^4 in magnitude as a Lua number, like D.toInt.
function Q.toInt(q)
  q = Q.reduce(q)
  if q.s == 0 then
    return 0
  end
  if not isOne(q.d) then
    return nil, "badprecision"
  end
  if magDigits(q.n) > 4 then
    return nil, "toolarge"
  end
  return q.s * q.n[1]
end

-- m^k for k >= 1, nil when the result gets larger than the rational size limit.
local function magPow(m, k)
  local result, base = nil, m
  while true do
    if k % 2 == 1 then
      result = result and magMul(result, base) or base
      if magDigits(result) > D.MAX_RATIONAL_DIGITS then
        return nil
      end
    end
    k = floor(k / 2)
    if k == 0 then
      return result
    end
    base = magMul(base, base)
    if magDigits(base) > D.MAX_RATIONAL_DIGITS then
      return nil
    end
  end
end

-- Exact for perfect squares (also of fractions), otherwise an approximation with SQRT_DIGITS
-- significant digits, flagged approx.
function Q.sqrt(a)
  if a.s < 0 then
    return nil, "negsqrt"
  end
  if a.s == 0 then
    return a
  end
  a = Q.reduce(a)
  local sn = magIsqrt(a.n)
  if magCmp(magMul(sn, sn), a.n) == 0 then
    local sd = magIsqrt(a.d)
    if magCmp(magMul(sd, sd), a.d) == 0 then
      return normalize(1, sn, sd, a.approx, true)
    end
  end
  -- floor(sqrt(x)) = floor(sqrt(floor(x))), so scaling by 10^2k and truncating loses no digit.
  -- The root gets at least SQRT_DIGITS + 2 digits, which makes the rounding digit exact.
  local gap = magDigits(a.n) - magDigits(a.d)
  local k = math.max(0, math.ceil((2 * (D.SQRT_DIGITS + 1) + 1 - gap) / 2))
  local s = magIsqrt((magDivmod(magShift(a.n, 2 * k), a.d)))
  local drop = magDigits(s) - D.SQRT_DIGITS
  local m, first = magDrop(s, drop)
  m = roundHalfUp(m, first)
  local e = drop - k
  if e >= 0 then
    return normalize(1, magShift(m, e), ONEM, true, true)
  end
  return normalize(1, m, pow10Mag(-e), true)
end

-- Whole exponents are exact (up to MAX_POW), a negative one inverts. The exponent 1/2 is the
-- square root. 0^0 is 1.
function Q.pow(a, b)
  b = Q.reduce(b)
  local flag = a.approx or b.approx
  if not isOne(b.d) then
    if b.s > 0 and isOne(b.n) and #b.d == 1 and b.d[1] == 2 then
      return Q.sqrt(tag(a, flag))
    end
    return nil, "badexp"
  end
  if b.s == 0 then
    return tag(Q.ONE, flag)
  end
  if #b.n > 1 or b.n[1] > D.MAX_POW then
    return nil, "toolarge"
  end
  local k, neg = b.n[1], b.s < 0
  if a.s == 0 then
    if neg then
      return nil, "zeropow"
    end
    return tag(Q.ZERO, flag)
  end
  a = Q.reduce(a)
  -- x^k has at least (digits - 1) * k + 1 digits.
  local cap = D.MAX_RATIONAL_DIGITS
  if (magDigits(a.n) - 1) * k + 1 > cap or (magDigits(a.d) - 1) * k + 1 > cap then
    return nil, "toolarge"
  end
  local n, d = magPow(a.n, k), magPow(a.d, k)
  if not n or not d then
    return nil, "toolarge"
  end
  if neg then
    n, d = d, n
  end
  return normalize(a.s < 0 and k % 2 == 1 and -1 or 1, n, d, flag, true)
end

-- Removes the factor p from m as often as it divides, first in chunks of p^chunk (below 10^7).
local function stripFactor(m, p, chunk)
  local big, count = 1, 0
  for _ = 1, chunk do
    big = big * p
  end
  for _, step in ipairs({ { big, chunk }, { p, 1 } }) do
    while true do
      local q, r = magDivSmall(m, step[1])
      if r ~= 0 then
        break
      end
      m, count = q, count + step[2]
    end
  end
  return m, count
end

local function mulFactor(m, p, chunk, times)
  local big = 1
  for _ = 1, chunk do
    big = big * p
  end
  while times >= chunk do
    m, times = magMulSmall(m, big), times - chunk
  end
  for _ = 1, times do
    m = magMulSmall(m, p)
  end
  return m
end

-- The exact decimal when the value has a finite one (denominator 2^a * 5^b), false when it
-- has none. A finite decimal above the print limit is a failure: nil plus "toolarge".
local function exactDecimal(q)
  local k = pow10Exp(q.d)
  if k then
    return limit(make(q.s, q.n, -k))
  end
  local rest, twos = stripFactor(q.d, 2, 23)
  local fives
  rest, fives = stripFactor(rest, 5, 9)
  if not isOne(rest) then
    return false
  end
  k = math.max(twos, fives)
  if k >= D.MAX_DIGITS then
    return nil, "toolarge"
  end
  local n = mulFactor(q.n, 2, 23, k - twos)
  n = mulFactor(n, 5, 9, k - fives)
  return limit(make(q.s, n, -k))
end

-- PRECISION significant digits, half away from zero.
local function roundedDecimal(q)
  local k = math.max(0, D.PRECISION + 1 - (magDigits(q.n) - magDigits(q.d)))
  local m = magDivmod(magShift(q.n, k), q.d)
  local drop = magDigits(m) - D.PRECISION
  local first
  m, first = magDrop(m, drop)
  return limit(make(q.s, roundHalfUp(m, first), drop - k))
end

-- The only place where an expression result gets rounded. Returns the decimal and whether it
-- differs from the exact value (a non-terminating fraction or a square root approximation).
-- Failure: nil plus "toolarge".
function Q.toDecimal(q)
  if q.s == 0 then
    return ZERO, q.approx == true
  end
  if not q.approx then
    local exact, code = exactDecimal(pow10Exp(q.d) and q or Q.reduce(q))
    if exact then
      return exact, false
    elseif exact == nil then
      return nil, code
    end
  end
  local x, code = roundedDecimal(q)
  if not x then
    return nil, code
  end
  return x, true
end

-- Whole copper amount, half away from zero. The second result tells whether it differs.
function Q.toCopper(q)
  if q.s == 0 then
    return ZERO, q.approx == true
  end
  local m, inexact = roundDiv(q.n, q.d)
  local x, code = limit(make(q.s, m, 0))
  if not x then
    return nil, code
  end
  return x, inexact or q.approx == true
end
