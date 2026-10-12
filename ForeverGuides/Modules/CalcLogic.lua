-- Calculator core, pure data: evaluation of an expression text, number formatting, the
-- history list (pure functions, the caller owns the storage) and the help text keys.
--
-- Percent follows the Windows calculator: as the direct right operand of + or - it is a
-- share of the left side (X op Y% = X op X*Y/100, folded left to right), everywhere else
-- Y% = Y/100. A coin literal (12g 50s 3c) turns the whole result into copper.
--
-- Values are exact rationals (D.Q) while an expression is evaluated, so 1/3*3 is 1. Rounding
-- happens once, when the result is turned into a decimal.
local _, ns = ...
local D = ns.CalcDecimal
local Q = D.Q
local Parser = ns.CalcParser

local C = { HISTORY_MAX = 50, MAX_ENTRY_TEXT = 500 }
ns.CalcLogic = C

-- Locale keys of the rule texts, in display order.
C.HELP_KEYS = {
  "calc.help.precedence",
  "calc.help.percent",
  "calc.help.coins",
  "calc.help.rounding",
  "calc.help.separators",
  "calc.help.functions",
  "calc.help.limits",
}

-- Evaluation

-- Records the first failure in st and passes the value of a rational operation through.
local function finish(st, node, v, code)
  if v == nil then
    st.err = { code = code, pos = node.pos }
    return nil
  end
  return v
end

local eval

local function percentStep(st, node, a, op)
  local y = eval(node.b.a, st)
  if not y then
    return nil
  end
  local prod, code = Q.mul(a, y)
  if not prod then
    return finish(st, node, nil, code)
  end
  local delta = finish(st, node, Q.shift10(prod, -2))
  if not delta then
    return nil
  end
  -- No "and/or" here: a failed add returns nil plus a code, which "or" would swallow.
  if op == "+" then
    return finish(st, node, Q.add(a, delta))
  end
  return finish(st, node, Q.sub(a, delta))
end

local BINARY = {
  ["+"] = Q.add,
  ["-"] = Q.sub,
  ["*"] = Q.mul,
  ["/"] = Q.div,
  ["^"] = Q.pow,
}

local function call(st, node)
  local args = {}
  for i, arg in ipairs(node.args) do
    local v = eval(arg, st)
    if not v then
      return nil
    end
    args[i] = v
  end
  local name, x = node.name, args[1]
  if name == "sqrt" then
    return finish(st, node, Q.sqrt(x))
  elseif name == "abs" then
    return Q.abs(x)
  elseif name == "floor" then
    return finish(st, node, Q.floor(x))
  elseif name == "ceil" then
    return finish(st, node, Q.ceil(x))
  elseif name == "round" then
    local places = 0
    if args[2] then
      local n, code = Q.toInt(args[2])
      if not n or math.abs(n) > D.MAX_POW then
        return finish(st, node, nil, code or "toolarge")
      end
      places = n
    end
    return finish(st, node, Q.round(x, places))
  end
  -- min / max
  local best = x
  for i = 2, #args do
    local c = Q.cmp(args[i], best)
    if (name == "min" and c < 0) or (name == "max" and c > 0) then
      best = args[i]
    end
  end
  return best
end

eval = function(node, st)
  local t = node.t
  if t == "num" or t == "coin" then
    return Q.fromDecimal(node.v)
  elseif t == "ans" then
    if not st.ans then
      st.err = { code = "noans", pos = node.pos }
    end
    return st.ans
  elseif t == "group" then
    return eval(node.a, st)
  elseif t == "unary" then
    local v = eval(node.a, st)
    if not v then
      return nil
    end
    return node.op == "-" and Q.neg(v) or v
  elseif t == "pct" then
    local y = eval(node.a, st)
    if not y then
      return nil
    end
    return finish(st, node, Q.shift10(y, -2))
  elseif t == "call" then
    return call(st, node)
  end
  local a = eval(node.a, st)
  if not a then
    return nil
  end
  local op = node.op
  if (op == "+" or op == "-") and node.b.t == "pct" then
    return percentStep(st, node, a, op)
  end
  local b = eval(node.b, st)
  if not b then
    return nil
  end
  return finish(st, node, BINARY[op](a, b))
end

local function formatCoins(copper)
  local a = D.abs(copper)
  local g = D.floor(D.shift10(a, -4))
  local rest = D.sub(a, D.shift10(g, 4))
  local s = D.floor(D.shift10(rest, -2))
  local c = D.sub(rest, D.shift10(s, 2))
  local parts = {}
  for _, p in ipairs({ { g, "g" }, { s, "s" }, { c, "c" } }) do
    if not D.isZero(p[1]) then
      parts[#parts + 1] = D.toString(p[1]) .. p[2]
    end
  end
  if #parts == 0 then
    return "0c"
  end
  return (D.sign(copper) < 0 and "-" or "") .. table.concat(parts, " ")
end

local ERROR_ARGS = { badchar = 1, unexpected = 1, badunit = 1, unknown = 1, argcount = 2 }

local function failure(err)
  local L = ns.L
  local a1, a2 = tostring(err.arg or ""), tostring(err.arg2 or "")
  local n = ERROR_ARGS[err.code]
  local msg
  if n == 2 then
    msg = string.format(L["calc.err." .. err.code], a1, a2)
  elseif n == 1 then
    msg = string.format(L["calc.err." .. err.code], a1)
  else
    msg = L["calc.err." .. err.code]
  end
  return { ok = false, code = err.code, pos = err.pos, message = msg .. " " .. string.format(L["calc.err.at"], err.pos) }
end

local function answerValue(ans)
  if type(ans) == "string" then
    local x = D.fromString(ans)
    return x and Q.fromDecimal(x)
  elseif type(ans) == "table" and type(ans.m) == "table" and type(ans.s) == "number" and type(ans.e) == "number" then
    return Q.fromDecimal(ans)
  elseif Q.isValue(ans) then
    return ans
  end
  return nil
end

-- text: the expression. ctx: { ans = previous result: plain text, a decimal or the exact field of
-- a result }. Never throws.
-- Success: { ok, value, text, money, copper, coins, rounded, canonical, exact }. value is the
-- decimal that is shown, exact the unrounded rational (pass it as ans to keep 1/3 exact).
-- Failure: { ok = false, code, pos, message }
function C.Evaluate(text, ctx)
  local ast, info = Parser.Parse(text)
  if not ast then
    return failure(info)
  end
  local st = { ans = answerValue(ctx and ctx.ans) }
  local v = eval(ast, st)
  if not v then
    return failure(st.err)
  end
  local res = { ok = true, money = info.money, canonical = Parser.Canonical(ast) }
  local dec, rounded
  if info.money then
    dec, rounded = Q.toCopper(v)
    if dec then
      v = Q.fromDecimal(dec)
      res.copper = D.toString(dec)
      res.coins = formatCoins(dec)
    end
  else
    dec, rounded = Q.toDecimal(v)
  end
  if not dec then
    return failure({ code = rounded, pos = ast.pos or 1 })
  end
  res.value, res.exact = dec, v
  res.text = D.toString(dec)
  res.rounded = rounded
  return res
end

-- Formatting

-- opts: { group = bool (thousands separator), groupSep = " ", decimalSep = "." }
function C.FormatNumber(x, opts)
  opts = opts or {}
  local s = D.toString(x)
  local sign = ""
  if s:sub(1, 1) == "-" then
    sign, s = "-", s:sub(2)
  end
  local int, frac = s:match("^(%d+)%.?(%d*)$")
  if opts.group then
    local sep, out = opts.groupSep or " ", {}
    local first = #int % 3
    if first > 0 then
      out[1] = int:sub(1, first)
    end
    for i = first + 1, #int, 3 do
      out[#out + 1] = int:sub(i, i + 2)
    end
    int = table.concat(out, sep)
  end
  if frac ~= "" then
    int = int .. (opts.decimalSep or ".") .. frac
  end
  return sign .. int
end

-- Display options for a locale code ("deDE" uses 1.234,5, everything else 1 234.5).
function C.DisplayOptions(locale, group)
  if locale == "deDE" then
    return { group = group, groupSep = ".", decimalSep = "," }
  end
  return { group = group, groupSep = " ", decimalSep = "." }
end

-- History: newest first, at most HISTORY_MAX entries { expr, result } (both text).

local function cleanEntry(e)
  if type(e) ~= "table" or type(e.expr) ~= "string" or type(e.result) ~= "string" then
    return nil
  end
  return { expr = e.expr:sub(1, C.MAX_ENTRY_TEXT), result = e.result:sub(1, C.MAX_ENTRY_TEXT) }
end

-- Validates data that came from saved variables.
function C.HistorySanitize(raw)
  local out = {}
  if type(raw) == "table" then
    for _, e in ipairs(raw) do
      local c = cleanEntry(e)
      if c then
        out[#out + 1] = c
        if #out >= C.HISTORY_MAX then
          break
        end
      end
    end
  end
  return out
end

-- Returns a new list and whether the entry was added. The input list stays untouched.
-- An entry equal to the newest one is skipped.
function C.HistoryAdd(list, expr, result)
  local out = C.HistorySanitize(list)
  local entry = cleanEntry({ expr = expr, result = result })
  if not entry then
    return out, false
  end
  local top = out[1]
  if top and top.expr == entry.expr and top.result == entry.result then
    return out, false
  end
  table.insert(out, 1, entry)
  out[C.HISTORY_MAX + 1] = nil
  return out, true
end
