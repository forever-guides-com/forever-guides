-- Pure macro line logic (strings and tables only, no WoW API, no UI), ported from the macro
-- tools of forever-guides.com (parser, conditions, commands, line rules, validator, line builder and
-- compact form). The tables come from
-- Data/MacroSyntax.lua. Columns are byte columns, 1-based, as in the web (where they are UTF-16
-- units). Findings carry a code and a params table; the texts are the locale keys
-- "macros.f.<CODE>[.<variant>]" with {param} placeholders (X.text).
local _, ns = ...
local C = ns.MacroCore

local X = {
  MACRO_LIMIT = 255,
  NEAR_LIMIT = 230,
  NAME_LIMIT = 16,
  SOURCE_LIMIT = C.MAX_SOURCE,
  LINE_TEXT_LIMIT = 80,
}
ns.MacroLines = X

X.CODES = {
  "LEN_OVER",
  "LEN_NEAR",
  "LEN_BYTES",
  "NAME_LEN",
  "UNKNOWN_SPELL",
  "REMOVED_SPELL",
  "CLASS_MISMATCH",
  "UNKNOWN_ITEM",
  "BRACKET",
  "COND_UNKNOWN",
  "COND_CONTRADICTION",
  "CMD_UNKNOWN",
  "CMD_SCRIPT",
  "CMD_CONSENT",
  "GCD_MULTI",
  "CASTSEQ_RESET",
  "SHOWTOOLTIP_POS",
  "FOCUS_UNVERIFIED",
  "CHAR_INVALID",
}

local SEVERITY = {
  LEN_OVER = "error",
  LEN_NEAR = "warning",
  LEN_BYTES = "warning",
  NAME_LEN = "error",
  UNKNOWN_SPELL = "error",
  REMOVED_SPELL = "warning",
  CLASS_MISMATCH = "warning",
  UNKNOWN_ITEM = "warning",
  BRACKET = "error",
  COND_UNKNOWN = "error",
  COND_CONTRADICTION = "warning",
  CMD_UNKNOWN = "error",
  CMD_SCRIPT = "warning",
  CMD_CONSENT = "info",
  GCD_MULTI = "info",
  CASTSEQ_RESET = "error",
  SHOWTOOLTIP_POS = "warning",
  FOCUS_UNVERIFIED = "info",
  CHAR_INVALID = "error",
}
X.SEVERITY = SEVERITY

local SEVERITY_ORDER = { error = 0, warning = 1, info = 2 }

-- Strings --------------------------------------------------------------------------------

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitLines(text)
  local lines, start = {}, 1
  while true do
    local nl = text:find("\n", start, true)
    if not nl then
      lines[#lines + 1] = text:sub(start)
      return lines
    end
    lines[#lines + 1] = text:sub(start, nl - 1)
    start = nl + 1
  end
end

local function nonEmptyLines(source)
  local out = {}
  for _, line in ipairs(splitLines(source)) do
    if trim(line) ~= "" then
      out[#out + 1] = line
    end
  end
  return out
end

-- Line breaks to \n, control characters out (tab and the escape character included, as in the web).
function X.sanitize(text)
  return (text:gsub("\r\n?", "\n"):gsub("[%z\1-\9\11-\31\127]", ""))
end

local function splitOn(text, sep)
  local parts, pos = {}, 1
  while true do
    local at = text:find(sep, pos, true)
    if not at then
      parts[#parts + 1] = text:sub(pos)
      return parts
    end
    parts[#parts + 1] = text:sub(pos, at - 1)
    pos = at + #sep
  end
end

-- Tables ---------------------------------------------------------------------------------

local cache
local function data()
  if not cache then
    local syn = ns.Data.MacroSyntax
    cache = { syn = syn, byName = {}, raw = {} }
    for _, def in ipairs(syn.commands) do
      for _, name in ipairs(def.names) do
        cache.byName[name] = def
      end
    end
    for _, name in ipairs(syn.rawArg) do
      cache.raw[name] = true
    end
  end
  return cache
end

function X.findCommand(name)
  return data().byName[(name or ""):lower()]
end

function X.isScriptCommand(name)
  local def = X.findCommand(name)
  return def ~= nil and def.kind == "script"
end

function X.shortestAlias(name)
  local def = X.findCommand(name)
  if not def then
    return name
  end
  local best = name:lower()
  for _, candidate in ipairs(def.names) do
    if #candidate < #best then
      best = candidate
    end
  end
  return best
end

function X.isRawArgCommand(name)
  return data().raw[name] == true
end

-- Parser ---------------------------------------------------------------------------------

-- Parts of `text` between top-level separators (separators inside [..] do not split).
-- Returns { { text, start } } with start = 0-based offset of the part.
function X.splitTopLevel(text, sep)
  local parts, depth, start = {}, 0, 0
  for i = 1, #text do
    local c = text:sub(i, i)
    if c == "[" then
      depth = depth + 1
    elseif c == "]" then
      depth = math.max(0, depth - 1)
    elseif c == sep and depth == 0 then
      parts[#parts + 1] = { text = text:sub(start + 1, i - 1), start = start }
      start = i
    end
  end
  parts[#parts + 1] = { text = text:sub(start + 1), start = start }
  return parts
end

-- { raw, name, negated, value, target, col }. "@unit" and "target=unit" set target.
function X.parseCondition(raw, col)
  local text = trim(raw)
  local lead = raw:find("%S")
  local offset = col + (lead and lead - 1 or 0)
  if text:sub(1, 1) == "@" then
    return { raw = text, name = "@", negated = false, target = text:sub(2), col = offset }
  end
  if text:sub(1, 7):lower() == "target=" then
    return { raw = text, name = "target=", negated = false, target = text:sub(8), col = offset }
  end
  local colon = text:find(":", 1, true)
  local head = (colon and text:sub(1, colon - 1) or text):lower()
  local value = colon and text:sub(colon + 1) or nil
  local negated = head:sub(1, 2) == "no"
  return { raw = text, name = negated and head:sub(3) or head, negated = negated, value = value, col = offset }
end

local function parseGroup(inner, col)
  if trim(inner) == "" then
    return {}
  end
  local out = {}
  for i, part in ipairs(X.splitTopLevel(inner, ",")) do
    out[i] = X.parseCondition(part.text, col + part.start)
  end
  return out
end

-- Condition groups in front of the action: "[a,b] [c] Action" -> { groups, action, actionCol }.
function X.parseClause(text, col)
  local groups, p = {}, 1
  while true do
    while text:sub(p, p) == " " do
      p = p + 1
    end
    if text:sub(p, p) ~= "[" then
      break
    end
    local close = text:find("]", p, true)
    if not close then
      break
    end
    groups[#groups + 1] = parseGroup(text:sub(p + 1, close - 1), col + p)
    p = close + 1
  end
  local rest = text:sub(p)
  local lead = #rest:match("^%s*")
  return { groups = groups, action = trim(rest), actionCol = col + (p - 1) + lead }
end

-- Offset (0-based) and kind of the first bracket problem in `args`, or nil.
local function findBracketError(args)
  local open
  for i = 1, #args do
    local c = args:sub(i, i)
    if c == "[" then
      if open then
        return { col = i - 1, kind = "nested" }
      end
      open = i - 1
    elseif c == "]" then
      if not open then
        return { col = i - 1, kind = "unopened" }
      end
      open = nil
    end
  end
  return open and { col = open, kind = "unclosed" } or nil
end

local function parseCommand(text, line, lead)
  local name, space, args = text:match("^/(%S*)(%s*)(.*)$")
  local command = name:lower()
  local argsCol = lead + 1 + #name + #space + 1
  local parsed = { kind = "command", line = line, command = command, args = args, argsCol = argsCol, clauses = {} }
  if X.isRawArgCommand(command) then
    return parsed
  end
  parsed.bracketError = findBracketError(args)
  if not parsed.bracketError then
    for i, part in ipairs(X.splitTopLevel(args, ";")) do
      parsed.clauses[i] = X.parseClause(part.text, argsCol + part.start)
    end
  end
  return parsed
end

-- { kind = "empty"|"directive"|"comment"|"text"|"command", line, ... }.
function X.parseLine(text, line)
  local trimmed = text:gsub("^%s+", "")
  local lead = #text - #trimmed
  if trimmed == "" then
    return { kind = "empty", line = line }
  end
  if trimmed:sub(1, 1) == "/" then
    return parseCommand(trimmed, line, lead)
  end
  if trimmed:sub(1, 1) == "#" then
    local word, space, arg = trimmed:match("^#([%w_]+)(%s*)(.*)$")
    local lower = word and word:lower()
    if lower == "showtooltip" or lower == "show" then
      return { kind = "directive", line = line, name = lower, arg = arg, argCol = lead + 2 + #word + #space }
    end
    return { kind = "comment", line = line, text = text }
  end
  return { kind = "text", line = line, text = text }
end

function X.parseLines(source)
  local out = {}
  for i, text in ipairs(splitLines(source)) do
    out[i] = X.parseLine(text, i)
  end
  return out
end

-- Conditions -----------------------------------------------------------------------------

local function allParts(value, ok)
  for _, part in ipairs(splitOn(value, "/")) do
    if not ok(part) then
      return false
    end
  end
  return true
end

local BUTTON_NAMES = { leftbutton = true, rightbutton = true, middlebutton = true, button4 = true, button5 = true }

local VALUE_CHECKS = {
  digits = function(value)
    return allParts(value, function(part)
      return part:match("^%d+$") ~= nil
    end)
  end,
  modifiers = function(value)
    return allParts(value, function(part)
      part = part:lower()
      return part == "shift" or part == "ctrl" or part == "alt"
    end)
  end,
  buttons = function(value)
    return allParts(value, function(part)
      return part:match("^[1-5]$") ~= nil or BUTTON_NAMES[part:lower()] == true
    end)
  end,
  group = function(value)
    return allParts(value, function(part)
      part = part:lower()
      return part == "party" or part == "raid"
    end)
  end,
}

local BASE_UNITS = {
  player = true,
  target = true,
  focus = true,
  mouseover = true,
  pet = true,
  cursor = true,
  none = true,
  vehicle = true,
}

local function isBaseUnit(s)
  if BASE_UNITS[s] then
    return true
  end
  if s:match("^party[1-4]$") or s:match("^partypet[1-4]$") or s:match("^arena[1-5]$") or s:match("^boss[1-8]$") then
    return true
  end
  local digits = s:match("^raid(%d+)$") or s:match("^raidpet(%d+)$")
  return digits ~= nil and digits:sub(1, 1) ~= "0" and tonumber(digits) <= 40
end

-- player, target, party1, raid12, boss3 ... each optionally followed by "target"s.
function X.isUnit(unit)
  local s = unit:lower()
  while true do
    if isBaseUnit(s) then
      return true
    end
    if #s > 6 and s:sub(-6) == "target" then
      s = s:sub(1, -7)
    else
      return false
    end
  end
end

-- nil when the condition is fine, else "unknown", "value" or "unit".
function X.checkCondition(condition)
  if condition.target ~= nil then
    if X.isUnit(condition.target) then
      return nil
    end
    return "unit"
  end
  local def = data().syn.conditions[condition.name]
  if not def then
    return "unknown"
  end
  local value = condition.value
  if value == nil then
    return def.value == "required" and "value" or nil
  end
  if def.value == "none" or value == "" then
    return "value"
  end
  if def.check and not VALUE_CHECKS[def.check](value) then
    return "value"
  end
  return nil
end

-- The first contradicting pair of a group { a, b }, or nil: "x" with "nox" and the same value,
-- help with harm, two different units.
function X.findContradiction(group)
  local positive, targets = {}, {}
  for _, c in ipairs(group) do
    if c.target == nil then
      positive[#positive + 1] = c
    else
      targets[#targets + 1] = c
    end
  end
  for _, a in ipairs(positive) do
    for _, b in ipairs(positive) do
      if a ~= b then
        local opposite = a.name == b.name and a.negated ~= b.negated and (a.value or "") == (b.value or "")
        local pair = not a.negated and not b.negated and a.name == "help" and b.name == "harm"
        if opposite or pair then
          return { a, b }
        end
      end
    end
  end
  if #targets > 1 then
    local first, differs = targets[1].target:lower(), false
    for i = 2, #targets do
      differs = differs or targets[i].target:lower() ~= first
    end
    if differs then
      return { targets[1], targets[2] }
    end
  end
  return nil
end

-- Findings -------------------------------------------------------------------------------

-- { code, severity, line, col, params, requiresConsent }.
function X.finding(code, line, col, params, requiresConsent)
  return {
    code = code,
    severity = SEVERITY[code],
    line = line,
    col = col,
    params = params or {},
    requiresConsent = requiresConsent and true or nil,
  }
end

-- Locale key of a finding: macros.f.CODE, with the variant param appended when there is one.
function X.messageKey(f)
  local variant = f.params.variant
  return "macros.f." .. f.code .. (variant and ("." .. variant) or "")
end

-- Text of a finding from a locale table (ns.L); placeholders are {name}.
function X.text(f, L)
  local template = L[X.messageKey(f)] or L["macros.f." .. f.code] or f.code
  return (
    template:gsub("{(%w+)}", function(key)
      local value = f.params[key]
      return value ~= nil and tostring(value) or ""
    end)
  )
end

local RESET_WORDS = { target = true, combat = true, shift = true, alt = true, ctrl = true, mod = true }

local function validResetPart(part)
  return RESET_WORDS[part:lower()] == true or part:match("^%d+$") ~= nil or part:match("^%d+%.%d+$") ~= nil
end

local function checkReset(clause, line, add)
  if clause.action:sub(1, 6):lower() ~= "reset=" then
    return
  end
  local value = clause.action:sub(7):match("^(%S*)")
  local ok = value ~= ""
  for _, part in ipairs(splitOn(value, "/")) do
    ok = ok and validResetPart(part)
  end
  if not ok then
    add("CASTSEQ_RESET", line, clause.actionCol, { value = value })
  end
end

local function isFocus(condition)
  return condition.target ~= nil and condition.target:lower():sub(1, 5) == "focus"
end

local function checkGroup(group, line, add)
  for _, condition in ipairs(group) do
    local problem = X.checkCondition(condition)
    if problem then
      add("COND_UNKNOWN", line, condition.col, { condition = condition.raw, variant = problem })
    end
  end
  local pair = X.findContradiction(group)
  if pair then
    add("COND_CONTRADICTION", line, pair[2].col, { a = pair[1].raw, b = pair[2].raw })
  end
end

local function checkClauses(parsed, add)
  local def = X.findCommand(parsed.command)
  local focus = def ~= nil and def.focus == true
  for _, clause in ipairs(parsed.clauses) do
    for _, group in ipairs(clause.groups) do
      checkGroup(group, parsed.line, add)
      for _, condition in ipairs(group) do
        focus = focus or isFocus(condition)
      end
    end
    if parsed.command == "castsequence" then
      checkReset(clause, parsed.line, add)
    end
  end
  if focus then
    add("FOCUS_UNVERIFIED", parsed.line, 1)
  end
end

local function checkCommand(parsed, ctx, add)
  local def = X.findCommand(parsed.command)
  if not def then
    if not (ctx.extraCommands and ctx.extraCommands[parsed.command]) then
      add("CMD_UNKNOWN", parsed.line, 1, { command = parsed.command })
    end
    return
  end
  if def.kind == "script" then
    add("CMD_SCRIPT", parsed.line, 1, { command = parsed.command }, true)
  end
  if parsed.bracketError then
    add("BRACKET", parsed.line, parsed.argsCol + parsed.bracketError.col, { variant = parsed.bracketError.kind })
  end
  checkClauses(parsed, add)
end

-- True for a line that casts on the global cooldown (a gcd command with an action).
function X.castsSpell(parsed)
  if parsed.kind ~= "command" then
    return false
  end
  local def = X.findCommand(parsed.command)
  if not (def and def.gcd) then
    return false
  end
  for _, clause in ipairs(parsed.clauses) do
    if clause.action ~= "" then
      return true
    end
  end
  return false
end

local function checkLines(lines, ctx, add)
  local casting = {}
  for _, parsed in ipairs(lines) do
    if parsed.kind == "directive" and parsed.line ~= 1 then
      add("SHOWTOOLTIP_POS", parsed.line, 1)
    elseif parsed.kind == "text" then
      add("CMD_UNKNOWN", parsed.line, 1, { variant = "noSlash" })
    elseif parsed.kind == "command" then
      checkCommand(parsed, ctx, add)
      if X.castsSpell(parsed) then
        casting[#casting + 1] = parsed
      end
    end
  end
  if #casting > 1 then
    add("GCD_MULTI", casting[2].line, 1, { count = #casting })
  end
end

local function checkCharacters(source, add)
  for n, text in ipairs(splitLines((source:gsub("\r\n?", "\n")))) do
    local i = 1
    while i <= #text do
      local b = text:byte(i)
      if b == 124 then
        local j = i
        while text:byte(j + 1) == 124 do
          j = j + 1
        end
        if (j - i + 1) % 2 == 1 then
          add("CHAR_INVALID", n, i, { char = "|" })
        end
        i = j + 1
      else
        if b < 32 or b == 127 then
          add("CHAR_INVALID", n, i, { char = string.format("U+%04X", b) })
        end
        i = i + 1
      end
    end
  end
end

local function checkTokens(clean, ctx, add)
  for n, text in ipairs(splitLines(clean)) do
    for _, t in ipairs(C.tokens(text)) do
      if t.kind == "s" and ctx.spell then
        local info = ctx.spell(t.id)
        if not info then
          add("UNKNOWN_SPELL", n, t.s, { id = t.id })
        else
          if info.removed then
            add("REMOVED_SPELL", n, t.s, { id = t.id, name = info.name or "?" })
          end
          if ctx.class and info.classes and next(info.classes) and not info.classes[ctx.class] then
            add("CLASS_MISMATCH", n, t.s, { id = t.id, name = info.name or "?", class = ctx.class })
          end
        end
      elseif t.kind == "i" and ctx.item and not ctx.item(t.id) then
        add("UNKNOWN_ITEM", n, t.s, { id = t.id })
      end
    end
  end
end

local function checkLengths(source, rendered, ctx, add)
  local m = C.measure(rendered)
  local unit = ctx.lengthUnit == "chars" and "chars" or "bytes"
  local length = unit == "chars" and m.chars or m.bytes
  if #source > X.SOURCE_LIMIT then
    add("LEN_OVER", 0, 0, { variant = "source", length = #source, limit = X.SOURCE_LIMIT })
  end
  if length > X.MACRO_LIMIT then
    add("LEN_OVER", 0, 0, { variant = unit, length = length, limit = X.MACRO_LIMIT })
  elseif length > X.NEAR_LIMIT then
    add("LEN_NEAR", 0, 0, { variant = unit, length = length, limit = X.MACRO_LIMIT })
  end
  if unit == "chars" and m.bytes > X.MACRO_LIMIT and m.chars <= X.MACRO_LIMIT then
    add("LEN_BYTES", 0, 0, { bytes = m.bytes, chars = m.chars, limit = X.MACRO_LIMIT })
  end
  if ctx.macroName and C.charCount(ctx.macroName) > X.NAME_LIMIT then
    add("NAME_LEN", 0, 0, { length = C.charCount(ctx.macroName) })
  end
  return m
end

-- Validates macro source (tokens {s:ID} stay as typed). ctx, all optional:
--   render(source) -> text as it goes into the game (default: the source itself)
--   spell(id) -> nil (unknown) or { name, removed, classes = set }, item(id) -> bool
--   class (token), macroName, lengthUnit "bytes" (default, like the web) or "chars"
--   extraCommands (set of lowercase slash words the client knows), consent(source) -> script lines
-- Returns { findings, ok, requiresConsent, lengths = { chars, bytes } }.
function X.validate(source, ctx)
  ctx = ctx or {}
  source = source or ""
  local clean = X.sanitize(source)
  local findings = {}
  local function add(code, line, col, params, requiresConsent)
    local f = X.finding(code, line, col, params, requiresConsent)
    f.seq = #findings + 1
    findings[#findings + 1] = f
  end
  checkCharacters(source, add)
  local lengths = checkLengths(source, ctx.render and ctx.render(clean) or clean, ctx, add)
  local lines = X.parseLines(clean)
  checkLines(lines, ctx, add)
  checkTokens(clean, ctx, add)
  if ctx.consent then
    local flagged = {}
    for _, f in ipairs(findings) do
      if f.code == "CMD_SCRIPT" then
        flagged[f.line] = true
      end
    end
    for _, entry in ipairs(ctx.consent(clean)) do
      if not flagged[entry.line] then
        add("CMD_CONSENT", entry.line, 1, { category = entry.cat }, true)
      end
    end
  end
  table.sort(findings, function(a, b)
    if a.line ~= b.line then
      return a.line < b.line
    elseif a.col ~= b.col then
      return a.col < b.col
    elseif a.severity ~= b.severity then
      return SEVERITY_ORDER[a.severity] < SEVERITY_ORDER[b.severity]
    end
    return a.seq < b.seq
  end)
  local ok, consent = true, false
  for _, f in ipairs(findings) do
    ok = ok and f.severity ~= "error"
    consent = consent or f.requiresConsent == true
  end
  return { findings = findings, ok = ok, requiresConsent = consent, lengths = lengths }
end

-- Counts per severity { error, warning, info } and the worst one ("success" when none).
function X.summary(findings)
  local counts = { error = 0, warning = 0, info = 0 }
  for _, f in ipairs(findings) do
    counts[f.severity] = counts[f.severity] + 1
  end
  local worst = counts.error > 0 and "error" or counts.warning > 0 and "warning" or counts.info > 0 and "info" or "ok"
  return counts, worst
end

-- Line builder ---------------------------------------------------------------------------

function X.lineKinds()
  return data().syn.lineKinds
end

function X.lineKind(id)
  for _, kind in ipairs(data().syn.lineKinds) do
    if kind.id == id then
      return kind
    end
  end
end

function X.petCommands()
  return data().syn.petCommands
end

function X.chipGroups()
  return data().syn.chipGroups
end

function X.resetChips()
  return data().syn.resetChips
end

-- Text for the free field of /use: control characters and pipes become blanks, at most 80 characters.
local function clean(text)
  local s = text:gsub("[%z\1-\31\127|]", " "):gsub("%s+", " ")
  return C.truncateChars(trim(s), X.LINE_TEXT_LIMIT)
end

local function bracket(chips)
  return chips and #chips > 0 and ("[" .. table.concat(chips, ",") .. "] ") or ""
end

-- Index (1-based) of a catch-all clause that is not the last one: it hides every later clause.
function X.deadClauseIndex(clauses)
  for i, clause in ipairs(clauses) do
    if #clause.chips == 0 then
      return i < #clauses and i or nil
    end
  end
  return nil
end

-- "reset=target/6 " from { keys, seconds }, "" without one.
function X.resetText(reset)
  if not reset then
    return ""
  end
  local parts = {}
  for _, key in ipairs(reset.keys or {}) do
    parts[#parts + 1] = key
  end
  if reset.seconds and reset.seconds > 0 then
    parts[#parts + 1] = tostring(math.min(math.floor(reset.seconds + 0.5), 999))
  end
  return #parts > 0 and ("reset=" .. table.concat(parts, "/") .. " ") or ""
end

-- Rank styles: how a picked spell is written into a line. "picked" keeps the choice of the picker
-- (the default), "fixed" writes the picked rank, "highest" writes the highest rank the player knows,
-- "none" writes the name only (the game then takes its highest rank).
X.RANK_STYLES = { "picked", "fixed", "highest", "none" }
X.DEFAULT_RANK_STYLE = "picked"

function X.cleanRankStyle(style)
  for _, known in ipairs(X.RANK_STYLES) do
    if known == style then
      return style
    end
  end
  return X.DEFAULT_RANK_STYLE
end

-- The spell token `token` ("{s:ID}" or "{s:ID:base}") in the given style; anything else stays as it is.
-- highest(id) -> id of the highest known rank of the chain of `id` (nil keeps the picked rank).
function X.rankToken(token, style, highest)
  local t = C.tokens(token)[1]
  if not t or t.kind ~= "s" or t.s ~= 1 or t.e ~= #token then
    return token
  end
  if style == "fixed" then
    return C.spellToken(t.id)
  elseif style == "highest" then
    return C.spellToken(highest and highest(t.id) or t.id)
  elseif style == "none" then
    return C.spellToken(t.id, true)
  end
  return token
end

-- spec: { kind, clauses = { { chips, spell, bang } }, spells, reset, chips, command, text,
-- rankStyle, highest }. Returns the line, or nil while the spec is incomplete.
function X.buildLine(spec)
  local function styled(spell)
    return spec.rankStyle and X.rankToken(spell, spec.rankStyle, spec.highest) or spell
  end
  local clauses = {}
  for _, clause in ipairs(spec.clauses or {}) do
    if clause.spell and clause.spell ~= "" then
      clauses[#clauses + 1] = clause
    end
  end
  local kind = spec.kind
  if kind == "showtooltip" then
    return #clauses > 0 and ("#showtooltip " .. bracket(clauses[1].chips) .. styled(clauses[1].spell)) or "#showtooltip"
  elseif kind == "cast" or kind == "cancelaura" then
    if #clauses == 0 then
      return nil
    end
    local body = {}
    for i, clause in ipairs(clauses) do
      local spell = kind == "cast" and styled(clause.spell) or clause.spell
      body[i] = bracket(clause.chips) .. ((kind == "cast" and clause.bang) and "!" or "") .. spell
    end
    return "/" .. kind .. " " .. table.concat(body, "; ")
  elseif kind == "castsequence" then
    local spells = {}
    for _, spell in ipairs(spec.spells or {}) do
      if spell ~= "" then
        spells[#spells + 1] = styled(spell)
      end
    end
    if #spells < 2 then
      return nil
    end
    return "/castsequence " .. bracket(spec.chips) .. X.resetText(spec.reset) .. table.concat(spells, ", ")
  elseif kind == "use" then
    local text = clean(spec.text or "")
    return text ~= "" and ("/use " .. bracket(spec.chips) .. text) or nil
  elseif kind == "pet" then
    return (trim("/" .. (spec.command or "petattack") .. " " .. bracket(spec.chips)))
  end
  return (trim("/" .. kind .. " " .. bracket(spec.chips)))
end

local function isDirective(line)
  return X.parseLine(line, 1).kind == "directive"
end

-- Adds a line to the source: #showtooltip goes first (replacing a present #show/#showtooltip),
-- everything else goes last. Returns nil when the result is longer than `max`.
function X.addLine(source, line, max)
  local lines = nonEmptyLines(source)
  if line:sub(1, 12) == "#showtooltip" then
    if lines[1] and isDirective(lines[1]) then
      table.remove(lines, 1)
    end
    table.insert(lines, 1, line)
  else
    lines[#lines + 1] = line
  end
  local text = table.concat(lines, "\n")
  if #text > max then
    return nil
  end
  return text
end

-- The first line of `source` that casts on the global cooldown, when `line` casts too, else nil.
function X.findGcdConflict(source, line)
  if not X.castsSpell(X.parseLine(line, 1)) then
    return nil
  end
  for i, entry in ipairs(nonEmptyLines(source)) do
    if X.castsSpell(X.parseLine(entry, i)) then
      return entry
    end
  end
  return nil
end

local function castBody(line)
  return trim(line):match("^/[Cc][Aa][Ss][Tt]%s+(.+)$")
end

local function splitClauses(body)
  local out = {}
  for _, part in ipairs(splitOn(body, ";")) do
    part = trim(part)
    if part ~= "" then
      out[#out + 1] = part
    end
  end
  return out
end

-- Two /cast lines as one clause chain (conditional clauses first, the catch-all last), or nil
-- when both lines have a catch-all or one is no plain /cast.
function X.mergeCastLines(existing, added)
  local a, b = castBody(existing), castBody(added)
  if not a or not b then
    return nil
  end
  local with, without = {}, {}
  for _, body in ipairs({ a, b }) do
    for _, clause in ipairs(splitClauses(body)) do
      local list = clause:sub(1, 1) == "[" and with or without
      list[#list + 1] = clause
    end
  end
  if #without > 1 then
    return nil
  end
  for _, clause in ipairs(without) do
    with[#with + 1] = clause
  end
  return "/cast " .. table.concat(with, "; ")
end

local function singleSpell(line)
  local body = castBody(line)
  if not body or body:find(";", 1, true) then
    return nil
  end
  local s = trim(body)
  local condition = s:match("^(%[[^%]]*%])") or ""
  local spell = trim(s:sub(#condition + 1)):gsub("^!", "")
  spell = trim(spell)
  if spell == "" then
    return nil
  end
  return { condition = condition, spell = spell }
end

-- Two single-spell /cast lines as one /castsequence with reset=target, or nil.
function X.castsequenceFromLines(existing, added)
  local first, second = singleSpell(existing), singleSpell(added)
  if not first or not second then
    return nil
  end
  if first.condition ~= "" and second.condition ~= "" and first.condition ~= second.condition then
    return nil
  end
  local condition = first.condition ~= "" and first.condition or second.condition
  return "/castsequence "
    .. (condition ~= "" and (condition .. " ") or "")
    .. "reset=target "
    .. first.spell
    .. ", "
    .. second.spell
end

-- Replaces the existing line by `replacement` and drops the added one; nil when one is missing.
function X.replaceGcdLines(source, existing, added, replacement)
  local lines = nonEmptyLines(source)
  local addedAt, existingAt
  for i, entry in ipairs(lines) do
    if entry == added then
      addedAt = i
    end
    if entry == existing and not existingAt then
      existingAt = i
    end
  end
  if not addedAt or not existingAt or addedAt == existingAt then
    return nil
  end
  lines[existingAt] = replacement
  table.remove(lines, addedAt)
  return table.concat(lines, "\n")
end

-- Compact (the six lossless rules) ---------------------------------------------------------

X.COMPACT_RULES = { "targetAt", "commandAlias", "whitespace", "emptyLines", "comments", "showtooltipArg" }

local function structural(parsed)
  return parsed.kind == "directive" or (parsed.kind == "command" and not X.isRawArgCommand(parsed.command))
end

local function splitHead(line)
  local head, args = line:match("^(%s*[#/]%S*%s?)(.*)$")
  if head then
    return head, args
  end
  return "", line
end

local LINE_RULES = {
  targetAt = function(line, parsed)
    if not structural(parsed) then
      return line
    end
    local head, args = splitHead(line)
    return head .. args:gsub("([%[,]%s*)[Tt][Aa][Rr][Gg][Ee][Tt]=", "%1@")
  end,
  commandAlias = function(line, parsed)
    if parsed.kind ~= "command" or not X.findCommand(parsed.command) then
      return line
    end
    return (line:gsub("^(%s*/)(%S+)", function(slash, name)
      return slash .. X.shortestAlias(name)
    end))
  end,
  whitespace = function(line, parsed)
    if not structural(parsed) then
      return line
    end
    local head, args = splitHead(trim(line))
    local tidy = trim(args:gsub("  +", " "):gsub("%s*([%[%],;])%s*", "%1"))
    return (head:gsub("%s+$", "")) .. (tidy ~= "" and (" " .. tidy) or "")
  end,
}

local function firstCastingLine(lines)
  for _, p in ipairs(lines) do
    if p.kind == "command" then
      local def = X.findCommand(p.command)
      if def and (def.spell or def.item) then
        return p
      end
    end
  end
end

local function dropShowtooltipArg(lines)
  local parsed = {}
  for i, line in ipairs(lines) do
    parsed[i] = X.parseLine(line, i)
  end
  local first = parsed[1]
  if not first or first.kind ~= "directive" or trim(first.arg) == "" then
    return lines
  end
  local rest = {}
  for i = 2, #parsed do
    rest[#rest + 1] = parsed[i]
  end
  local cast = firstCastingLine(rest)
  if not cast or #cast.clauses ~= 1 then
    return lines
  end
  local clause = cast.clauses[1]
  if #clause.groups > 0 or clause.action ~= trim(first.arg) then
    return lines
  end
  local out = { "#" .. first.name }
  for i = 2, #lines do
    out[#out + 1] = lines[i]
  end
  return out
end

local function hasRule(rules, name)
  for _, rule in ipairs(rules) do
    if rule == name then
      return true
    end
  end
  return false
end

-- Applies the given rules (default: all six) to the source text.
function X.applyCompactRules(source, rules)
  rules = rules or X.COMPACT_RULES
  local lines = splitLines(X.sanitize(source))
  for _, rule in ipairs(rules) do
    local fn = LINE_RULES[rule]
    if fn then
      for i, line in ipairs(lines) do
        lines[i] = fn(line, X.parseLine(line, i))
      end
    end
  end
  if hasRule(rules, "comments") then
    local kept = {}
    for i, line in ipairs(lines) do
      if X.parseLine(line, i).kind ~= "comment" then
        kept[#kept + 1] = line
      end
    end
    lines = kept
  end
  if hasRule(rules, "emptyLines") then
    local kept = {}
    for _, line in ipairs(lines) do
      if trim(line) ~= "" then
        kept[#kept + 1] = line
      end
    end
    lines = kept
  end
  if hasRule(rules, "showtooltipArg") then
    lines = dropShowtooltipArg(lines)
  end
  return table.concat(lines, "\n")
end

-- Shortens a macro without changing what it does. ctx.render(source) -> game text for the
-- saved characters and bytes. Returns { source, applied = { rule }, saved = { chars, bytes } }.
function X.compact(source, rules, ctx)
  rules = rules or X.COMPACT_RULES
  local base = X.sanitize(source)
  local applied = {}
  for _, rule in ipairs(rules) do
    if X.applyCompactRules(source, { rule }) ~= base then
      applied[#applied + 1] = rule
    end
  end
  local result = X.applyCompactRules(source, rules)
  local render = ctx and ctx.render or function(text)
    return text
  end
  local before, after = C.measure(render(source)), C.measure(render(result))
  return {
    source = result,
    applied = applied,
    saved = { chars = before.chars - after.chars, bytes = before.bytes - after.bytes },
  }
end
