-- Calculator expression parser: own lexer and Pratt parser, never loadstring or tonumber
-- on the input. Parse returns an AST or nil plus { code, pos, arg } where pos is the
-- character index (UTF-8 aware) of the problem. It never calls error().
--
-- Grammar, binding power from weak to strong:
--   + -  (10)   * / x × : ÷ and implicit multiplication before "(" (20)
--   unary + - (30)   ^ (40, right associative; the exponent may carry a sign)
-- Postfix % binds to the primary expression in front of it.
local _, ns = ...
local D = ns.CalcDecimal

local P = { MAX_INPUT = D.MAX_INPUT }
ns.CalcParser = P

local byte, lower = string.byte, string.lower

-- name -> { min args, max args }
local FUNCS = {
  sqrt = { 1, 1 },
  abs = { 1, 1 },
  floor = { 1, 1 },
  ceil = { 1, 1 },
  round = { 1, 2 },
  min = { 2, math.huge },
  max = { 2, math.huge },
}
P.FUNCS = FUNCS

local UNIT_RANK = { g = 1, s = 2, c = 3 }
local UNIT_COPPER = { g = 10000, s = 100, c = 1 }

local function isDigit(b)
  return b ~= nil and b >= 48 and b <= 57
end

local function isLetter(b)
  return b ~= nil and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

local function fail(code, pos, arg, arg2)
  return nil, { code = code, pos = pos, arg = arg, arg2 = arg2 }
end

-- Printable text of the character starting at byte i, for error messages.
local function charAt(s, i)
  local b = byte(s, i)
  local len = 1
  if b >= 0xC2 and b <= 0xDF then
    len = 2
  elseif b >= 0xE0 and b <= 0xEF then
    len = 3
  elseif b >= 0xF0 and b <= 0xF4 then
    len = 4
  elseif b < 32 or b >= 0x7F then
    return "?"
  end
  for k = 1, len - 1 do
    local c = byte(s, i + k)
    if c == nil or c < 0x80 or c > 0xBF then
      return "?"
    end
  end
  return s:sub(i, i + len - 1)
end

local SINGLE = {
  [43] = "+",
  [45] = "-",
  [42] = "*",
  [47] = "/",
  [94] = "^",
  [37] = "%",
  [40] = "(",
  [41] = ")",
  [58] = "/",
  [59] = ",",
  [44] = ",",
}

local function lex(s, ci)
  local toks, n, i = {}, #s, 1
  local prevValue = false
  local function push(tok)
    toks[#toks + 1] = tok
  end
  while i <= n do
    local b = byte(s, i)
    local nxt = byte(s, i + 1)
    local sep = b == 46 or (b == 44 and not prevValue)
    if b == 32 or b == 9 or b == 10 or b == 13 then
      i = i + 1
    elseif b == 0xC2 and nxt == 0xA0 then
      i = i + 2
    elseif isDigit(b) or (sep and isDigit(nxt)) then
      local j = i
      while isDigit(byte(s, j)) do
        j = j + 1
      end
      local ip, fp = s:sub(i, j - 1), ""
      local sc = byte(s, j)
      if (sc == 46 or sc == 44) and isDigit(byte(s, j + 1)) then
        local k = j + 1
        while isDigit(byte(s, k)) do
          k = k + 1
        end
        fp, j = s:sub(j + 1, k - 1), k
      end
      -- A second separator ("1.2.3", and "1,2,3" typed as function arguments) is never a number.
      local s2 = byte(s, j)
      if (s2 == 46 or s2 == 44) and isDigit(byte(s, j + 1)) then
        return fail("badnumber", ci[j])
      end
      local text = (ip ~= "" and ip or "0") .. (fp ~= "" and "." .. fp or "")
      local value, vcode = D.fromString(text)
      if not value then
        return fail(vcode, ci[i])
      end
      local tok = { t = "num", v = value, pos = ci[i], text = s:sub(i, j - 1) }
      local k = j
      while isLetter(byte(s, k)) do
        k = k + 1
      end
      if k > j then
        local raw = s:sub(j, k - 1)
        local w = lower(raw)
        if UNIT_RANK[w] then
          tok.unit, j = w, k
          tok.text = s:sub(i, j - 1)
        elseif w == "e" then
          return fail("expnot", ci[j])
        elseif ip == "0" and fp == "" and w:sub(1, 1) == "x" and (#w > 1 or isDigit(byte(s, k))) then
          return fail("hexnot", ci[j])
        elseif w ~= "x" and w ~= "ans" and not FUNCS[w] then
          return fail("badunit", ci[j], raw)
        end
      end
      push(tok)
      prevValue = true
      i = j
    elseif isLetter(b) then
      local k = i
      while isLetter(byte(s, k)) do
        k = k + 1
      end
      local raw = s:sub(i, k - 1)
      local w = lower(raw)
      if w == "x" then
        push({ t = "*", pos = ci[i], text = raw })
        prevValue = false
      elseif UNIT_RANK[w] then
        return fail("coinalone", ci[i])
      elseif w == "ans" or FUNCS[w] then
        push({ t = "word", name = w, pos = ci[i], text = raw })
        prevValue = w == "ans"
      else
        return fail("unknown", ci[i], raw)
      end
      i = k
    elseif b == 0xC3 and (nxt == 0x97 or nxt == 0xB7) then
      push({ t = nxt == 0x97 and "*" or "/", pos = ci[i], text = s:sub(i, i + 1) })
      prevValue = false
      i = i + 2
    elseif SINGLE[b] then
      local t = SINGLE[b]
      push({ t = t, pos = ci[i], text = s:sub(i, i) })
      prevValue = t == ")" or t == "%"
      i = i + 1
    else
      return fail("badchar", ci[i], charAt(s, i))
    end
  end
  push({ t = "eof", pos = (ci[n] or 0) + 1, text = "" })
  return toks
end

local INFIX = {
  ["+"] = 10,
  ["-"] = 10,
  ["*"] = 20,
  ["/"] = 20,
  ["("] = 20,
  ["^"] = 40,
}
local UNARY_BP = 30

local parseExpr

local function unexpected(tok)
  if tok.t == "eof" then
    return fail("unexpectedend", tok.pos)
  end
  return fail("unexpected", tok.pos, tok.text)
end

local function postfix(st, node)
  while st.toks[st.i].t == "%" do
    node = { t = "pct", a = node, pos = st.toks[st.i].pos }
    st.i = st.i + 1
  end
  return node
end

local function parseCoin(st, tok)
  local total, parts, last = D.ZERO, {}, 0
  while tok.t == "num" and tok.unit do
    local rank = UNIT_RANK[tok.unit]
    if rank == last then
      return fail("coindup", tok.pos)
    elseif rank < last then
      return fail("coinorder", tok.pos)
    end
    last = rank
    local sum, code = D.add(total, (D.mul(tok.v, D.fromInt(UNIT_COPPER[tok.unit]))))
    if not sum then
      return fail(code, tok.pos)
    end
    total = sum
    parts[#parts + 1] = D.toString(tok.v) .. tok.unit
    st.i = st.i + 1
    tok = st.toks[st.i]
  end
  st.money = true
  return { t = "coin", v = total, canon = table.concat(parts, " ") }
end

local function parseCall(st, tok)
  local open = st.toks[st.i]
  if open.t ~= "(" then
    return unexpected(open)
  end
  st.i = st.i + 1
  local args = {}
  if st.toks[st.i].t ~= ")" then
    while true do
      local arg, err = parseExpr(st, 0)
      if not arg then
        return nil, err
      end
      args[#args + 1] = arg
      local nt = st.toks[st.i]
      st.i = st.i + 1
      if nt.t == ")" then
        break
      elseif nt.t ~= "," then
        if nt.t == "eof" then
          return fail("unclosed", open.pos)
        end
        return unexpected(nt)
      end
    end
  else
    st.i = st.i + 1
  end
  local spec = FUNCS[tok.name]
  if #args < spec[1] or #args > spec[2] then
    local need = spec[1] == spec[2] and tostring(spec[1])
      or (spec[2] == math.huge and spec[1] .. "+" or spec[1] .. "-" .. spec[2])
    return fail("argcount", tok.pos, tok.name, need)
  end
  return { t = "call", name = tok.name, args = args, pos = tok.pos }
end

local function parsePrefix(st)
  local tok = st.toks[st.i]
  st.i = st.i + 1
  local node, err
  if tok.t == "num" then
    if tok.unit then
      st.i = st.i - 1
      node, err = parseCoin(st, tok)
      if node then
        node.pos = tok.pos
      end
    else
      node = { t = "num", v = tok.v, pos = tok.pos }
    end
  elseif tok.t == "(" then
    local inner
    inner, err = parseExpr(st, 0)
    if inner then
      local close = st.toks[st.i]
      if close.t ~= ")" then
        if close.t == "eof" then
          return fail("unclosed", tok.pos)
        end
        return unexpected(close)
      end
      st.i = st.i + 1
      node = { t = "group", a = inner, pos = tok.pos }
    end
  elseif tok.t == "+" or tok.t == "-" then
    local operand
    operand, err = parseExpr(st, UNARY_BP)
    if operand then
      return { t = "unary", op = tok.t, a = operand, pos = tok.pos }
    end
  elseif tok.t == "word" then
    if tok.name == "ans" then
      node = { t = "ans", pos = tok.pos }
    else
      node, err = parseCall(st, tok)
    end
  else
    return unexpected(tok)
  end
  if not node then
    return nil, err
  end
  return postfix(st, node)
end

parseExpr = function(st, minbp)
  local left, err = parsePrefix(st)
  if not left then
    return nil, err
  end
  while true do
    local tok = st.toks[st.i]
    local bp = INFIX[tok.t]
    if not bp then
      if tok.t == "num" then
        return fail("numseq", tok.pos)
      elseif tok.t == "word" then
        return unexpected(tok)
      end
      break
    end
    if bp <= minbp then
      break
    end
    local implicit = tok.t == "("
    if not implicit then
      st.i = st.i + 1
    end
    -- ^ is right associative: its right operand may contain another ^.
    local right
    right, err = parseExpr(st, tok.t == "^" and bp - 1 or bp)
    if not right then
      return nil, err
    end
    left = { t = "bin", op = implicit and "*" or tok.t, a = left, b = right, pos = tok.pos }
  end
  return left
end

-- Returns ast, { money = bool } or nil, { code, pos, arg }.
function P.Parse(text)
  if type(text) ~= "string" then
    return fail("empty", 1)
  end
  if #text > P.MAX_INPUT then
    return fail("toolarge", P.MAX_INPUT + 1)
  end
  -- Character index of every byte. Continuation bytes belong to the lead byte in front of
  -- them, a stray one (no lead byte, or too many) counts as a character of its own.
  local ci, count, need = {}, 0, 0
  for i = 1, #text do
    local b = byte(text, i)
    if b >= 0x80 and b <= 0xBF and need > 0 then
      need = need - 1
    else
      count = count + 1
      need = (b >= 0xC2 and b <= 0xDF and 1) or (b >= 0xE0 and b <= 0xEF and 2) or (b >= 0xF0 and b <= 0xF4 and 3) or 0
    end
    ci[i] = count
  end
  local toks, err = lex(text, ci)
  if not toks then
    return nil, err
  end
  if #toks == 1 then
    return fail("empty", 1)
  end
  local st = { toks = toks, i = 1, money = false }
  local ast
  ast, err = parseExpr(st, 0)
  if not ast then
    return nil, err
  end
  local tok = st.toks[st.i]
  if tok.t ~= "eof" then
    return unexpected(tok)
  end
  return ast, { money = st.money }
end

-- Normalized text of an AST (history entries): ASCII operators, "." decimals, "; " between
-- arguments (a comma could read as a decimal comma).
local function render(n)
  local t = n.t
  if t == "num" then
    return D.toString(n.v)
  elseif t == "coin" then
    return n.canon
  elseif t == "ans" then
    return "ans"
  elseif t == "group" then
    return "(" .. render(n.a) .. ")"
  elseif t == "unary" then
    return n.op .. render(n.a)
  elseif t == "pct" then
    return render(n.a) .. "%"
  elseif t == "call" then
    local parts = {}
    for i, arg in ipairs(n.args) do
      parts[i] = render(arg)
    end
    return n.name .. "(" .. table.concat(parts, "; ") .. ")"
  end
  if n.op == "^" then
    return render(n.a) .. "^" .. render(n.b)
  end
  return render(n.a) .. " " .. n.op .. " " .. render(n.b)
end
P.Canonical = render
