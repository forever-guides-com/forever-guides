-- Pure macro editor logic (strings and tables only, no WoW API, no UI) so it
-- can be unit tested outside the game. Format follows the website's macro
-- library: {s:ID}, {s:ID:base}, {i:ID}, {slot:N}.
local _, ns = ...
local ML = ns.MacroLogic

local C = {
  MAX_BODY = 255,
  MAX_SOURCE = 1024,
  MAX_NAME = 16,
  MAX_ACCOUNT = 120,
  MAX_CHARACTER = 30,
  NEAR = 230,
}
ns.MacroCore = C

-- Strings --------------------------------------------------------------------

function C.charCount(s)
  return select(2, s:gsub("[^\128-\191]", ""))
end

function C.truncateChars(s, n)
  local count, i = 0, 1
  while i <= #s do
    local b = s:byte(i)
    if b < 128 or b >= 192 then
      count = count + 1
      if count > n then
        return s:sub(1, i - 1)
      end
    end
    i = i + 1
  end
  return s
end

-- Removes control characters (newlines optional) and lone `|` escapes; `||` stays.
function C.sanitize(s, keepNewlines)
  s = s:gsub("\r\n?", "\n")
  s = s:gsub("[%z\1-\8\11\12\14-\31\127]", "")
  if not keepNewlines then
    s = s:gsub("\n", " ")
  end
  s = s:gsub("||", "\1"):gsub("|", ""):gsub("\1", "||")
  return s
end

-- Tokens ---------------------------------------------------------------------

-- List of { s, e, kind = "s"|"i"|"slot", id, base }.
function C.tokens(text)
  local out, pos = {}, 1
  while true do
    local s = text:find("{", pos, true)
    if not s then
      return out
    end
    local kind, id, suffix, after = text:match("^{(%a+):(%d+)(:?%a*)}()", s)
    local valid = kind == "s" and (suffix == "" or suffix == ":base")
      or (kind == "i" or kind == "slot") and suffix == ""
    if valid then
      out[#out + 1] = { s = s, e = after - 1, kind = kind, id = tonumber(id), base = suffix == ":base" }
      pos = after
    else
      pos = s + 1
    end
  end
end

function C.spellToken(id, base)
  return base and ("{s:" .. id .. ":base}") or ("{s:" .. id .. "}")
end

function C.itemToken(id)
  return "{i:" .. id .. "}"
end

-- ctx: mode "ids"|"names", spellName(id), rankText(id), highest(id), itemName(id).
function C.render(text, ctx)
  ctx = ctx or {}
  local names = ctx.mode == "names"
  return (
    text:gsub("{(%a+):(%d+)(:?%a*)}", function(kind, raw, suffix)
      local id = tonumber(raw)
      if kind == "s" and (suffix == "" or suffix == ":base") then
        local base = suffix == ":base"
        if not names then
          return tostring(base and ctx.highest and ctx.highest(id) or id)
        end
        local name = ctx.spellName and ctx.spellName(id)
        if not name then
          return tostring(id)
        end
        local rank = not base and ctx.rankText and ctx.rankText(id)
        return rank and (name .. "(" .. rank .. ")") or name
      elseif kind == "i" and suffix == "" then
        local name = names and ctx.itemName and ctx.itemName(id)
        return name or ("item:" .. id)
      elseif kind == "slot" and suffix == "" then
        return tostring(id)
      end
    end)
  )
end

-- Counter level for the 255 limit: "success" | "warning" | "danger".
function C.level(n, max)
  max = max or C.MAX_BODY
  if n > max then
    return "danger"
  elseif n >= C.NEAR then
    return "warning"
  end
  return "success"
end

function C.measure(rendered)
  return { chars = C.charCount(rendered), bytes = #rendered }
end

-- Script commands ------------------------------------------------------------

local CATEGORY_ORDER = { "script", "session", "guild", "group", "social", "chat" }

local COMMAND_CATEGORY = {}

local function register(cat, names)
  for name in names:gmatch("%S+") do
    COMMAND_CATEGORY[name] = cat
  end
end

register("script", "run script scr console click dump dumpt etrace eventtrace tinspect fstack")
register("session", "logout camp quit exit reload reloadui rl")
register("guild", "gquit guildquit guildleave gdisband guilddisband gremove guildremove gkick gpromote guildpromote")
register("guild", "gdemote guilddemote gleader guildleader ginvite guildinvite")
register("group", "invite inv uninvite kick")
register("social", "ignore squelch")
register(
  "chat",
  "s say y yell g guild o officer p party raid rw i instance w whisper t tell r reply e em emote 1 2 3 4 5 6 7 8 9"
)
-- deDE client aliases, not yet confirmed in game (TESTPLAN [Probe]).
register("chat", "sagen schreien gruppe gilde offizier fluestern flüstern antworten schlachtzug instanz")
register("session", "abmelden")

function C.commandCategory(cmd)
  return cmd and COMMAND_CATEGORY[cmd:lower()] or nil
end

function C.isScriptCommand(cmd)
  return C.commandCategory(cmd) ~= nil
end

-- Lines with script or consequential commands: { { line = n, text = "...", cat = "script"|... } }.
function C.scriptLines(text)
  local out = {}
  for n, line in ipairs(ML.splitLines(text)) do
    local cat = C.commandCategory(line:match("^%s*/([%w_\128-\255]+)"))
    if cat then
      out[#out + 1] = { line = n, text = line, cat = cat }
    end
  end
  return out
end

-- Categories present in `lines`, in a fixed order.
function C.categories(lines)
  local seen, out = {}, {}
  for _, entry in ipairs(lines) do
    seen[entry.cat] = true
  end
  for _, cat in ipairs(CATEGORY_ORDER) do
    if seen[cat] then
      out[#out + 1] = cat
    end
  end
  return out
end

-- Consent is remembered per action and exact text, for this session only.
function C.newConsent()
  return { granted = {} }
end

function C.hash(text, action)
  local h = 5381
  for i = 1, #text do
    h = (h * 33 + text:byte(i)) % 4294967296
  end
  return (action or "") .. ":" .. h .. ":" .. #text
end

-- Returns needed (bool), lines. Needed = scripts present and not yet agreed.
function C.needsConsent(state, text, action)
  local lines = C.scriptLines(text)
  if #lines == 0 or state.granted[C.hash(text, action)] then
    return false, lines
  end
  return true, lines
end

function C.grant(state, text, action)
  state.granted[C.hash(text, action)] = true
end

-- Runs `proceed` only when no consent is needed or the player agrees.
-- ask(lines, accept, decline) shows the warning; nothing happens without accept().
function C.guard(state, text, action, ask, proceed)
  local needed, lines = C.needsConsent(state, text, action)
  if not needed then
    return proceed(), false
  end
  ask(lines, function()
    C.grant(state, text, action)
    proceed()
  end, function() end)
  return nil, true
end

-- Line scanning --------------------------------------------------------------

-- Commands whose arguments are spell names/IDs. Value: true = also split on ",".
local CAST =
  { cast = false, castsequence = true, castrandom = true, showtooltip = false, show = false, cancelaura = false }

function C.castCommand(line)
  local cmd = line:match("^%s*[/#](%a+)")
  cmd = cmd and cmd:lower()
  if cmd and CAST[cmd] ~= nil then
    return cmd
  end
end

-- Action chunks of a cast-like line (after the command, outside [..] groups):
-- { { s, e, text } } with absolute positions, `!` and spaces trimmed.
function C.actionChunks(line)
  local cmd = C.castCommand(line)
  if not cmd then
    return nil
  end
  local from = select(2, line:find("^%s*[/#]%a+")) + 1
  if CAST[cmd] then
    local _, e = line:find("^%s*reset=%S+", from)
    from = e and e + 1 or from
  end
  local comma = CAST[cmd]
  local chunks, start, i = {}, from, from
  local function flush(stop)
    local seg = line:sub(start, stop)
    local lead = #seg:match("^[%s!]*")
    -- A castsequence option after the conditions ("[@player] reset=15 A, B") is no spell.
    local reset = comma and seg:sub(lead + 1):match("^reset=%S+")
    if reset then
      lead = lead + #reset + #seg:sub(lead + #reset + 1):match("^[%s!]*")
    end
    local core = seg:sub(lead + 1):gsub("%s+$", "")
    if core ~= "" then
      chunks[#chunks + 1] = { s = start + lead, e = start + lead + #core - 1, text = core }
    end
  end
  while i <= #line do
    local c = line:sub(i, i)
    if c == "[" then
      flush(i - 1)
      local close = line:find("]", i, true)
      i = (close or #line) + 1
      start = i
    elseif c == ";" or (comma and c == ",") then
      flush(i - 1)
      i = i + 1
      start = i
    else
      i = i + 1
    end
  end
  flush(#line)
  return chunks, cmd
end

-- "Feuerball(Rang 3)" -> "Feuerball", 3; no rank -> name, nil.
function C.splitRank(core)
  local name, word, rank = core:match("^(.-)%s*%(%s*(%a+)%s*(%d+)%s*%)$")
  if name and (word:lower() == "rang" or word:lower() == "rank") then
    return name, tonumber(rank)
  end
  return core, nil
end

-- Line-wise references: { line, kind = "spell"|"item", id, base, source = "token"|"number"|"name", ambiguous }.
-- ctx.lookup(name, rank, class) -> { id, base, rankAmbiguous } or nil, reason.
function C.references(text, ctx)
  ctx = ctx or {}
  local refs = {}
  for n, line in ipairs(ML.splitLines(text)) do
    for _, t in ipairs(C.tokens(line)) do
      if t.kind == "s" or t.kind == "i" then
        refs[#refs + 1] =
          { line = n, kind = t.kind == "s" and "spell" or "item", id = t.id, base = t.base, source = "token" }
      end
    end
    for _, ch in ipairs(C.actionChunks(line) or {}) do
      local core = ch.text
      if core:find("^%d+$") then
        refs[#refs + 1] = { line = n, kind = "spell", id = tonumber(core), source = "number" }
      elseif not core:find("[{}]") and ctx.lookup then
        local name, rank = C.splitRank(core)
        local hit = ctx.lookup(name, rank, ctx.class)
        if hit then
          refs[#refs + 1] = {
            line = n,
            kind = "spell",
            id = hit.id,
            base = hit.base,
            source = "name",
            ambiguous = hit.rankAmbiguous,
          }
        end
      end
    end
  end
  return refs
end

-- Plain text (names, IDs) -> token form. Returns body, { unresolved = { {line, text} }, converted = n }.
function C.importText(text, ctx)
  ctx = ctx or {}
  local out, unresolved, converted = {}, {}, 0
  for n, line in ipairs(ML.splitLines(text)) do
    if C.castCommand(line) or line:find("^%s*/use") or line:find("^%s*/equip") then
      line = line:gsub("item:(%d+)", function(id)
        converted = converted + 1
        return "{i:" .. id .. "}"
      end)
    end
    local chunks = C.actionChunks(line)
    for k = #(chunks or {}), 1, -1 do
      local ch = chunks[k]
      local token
      if not ch.text:find("[{}]") then
        if ch.text:find("^%d+$") then
          local id = tonumber(ch.text)
          if ctx.isSpell and ctx.isSpell(id) then
            token = C.spellToken(id)
          end
        elseif ctx.lookup then
          local name, rank = C.splitRank(ch.text)
          local hit = ctx.lookup(name, rank, ctx.class)
          if hit then
            token = C.spellToken(hit.id, hit.base)
          end
        end
        if token then
          converted = converted + 1
          line = line:sub(1, ch.s - 1) .. token .. line:sub(ch.e + 1)
        elseif not ch.text:find("^%d+$") or (ctx.isSpell and not ctx.isSpell(tonumber(ch.text))) then
          unresolved[#unresolved + 1] = { line = n, text = ch.text }
        end
      end
    end
    out[#out + 1] = line
  end
  return table.concat(out, "\n"), { unresolved = unresolved, converted = converted }
end

-- Highlighting ---------------------------------------------------------------

C.COLORS = {
  command = "c9a670",
  condition = "7cc4f0",
  spell = "6fae7c",
  item = "4da3ff",
  target = "c67bff",
  comment = "9d9d9d",
  error = "e05c4a",
  script = "e0954a",
}

local function esc(s)
  return (s:gsub("|", "||"))
end

local function paint(colors, kind, s)
  if s == "" then
    return ""
  end
  return "|cff" .. (colors[kind] or C.COLORS[kind]) .. esc(s) .. "|r"
end

local function paintCondition(colors, group)
  local out, pos = {}, 1
  while true do
    local s, e = group:find("[@]%S-[,%]]", pos)
    if not s then
      break
    end
    e = e - 1
    out[#out + 1] = paint(colors, "condition", group:sub(pos, s - 1))
    out[#out + 1] = paint(colors, "target", group:sub(s, e))
    pos = e + 1
  end
  out[#out + 1] = paint(colors, "condition", group:sub(pos))
  return table.concat(out)
end

-- Plain segment of a cast line: numbers are spell IDs.
local function plainSegment(colors, seg, isCast, ctx)
  if not isCast then
    return esc(seg)
  end
  local out, pos = {}, 1
  while true do
    local s, e = seg:find("%f[%d]%d+%f[%D]", pos)
    if not s then
      break
    end
    out[#out + 1] = esc(seg:sub(pos, s - 1))
    local id = tonumber(seg:sub(s, e))
    local bad = ctx and ctx.unknownSpell and ctx.unknownSpell(id)
    out[#out + 1] = paint(colors, bad and "error" or "spell", seg:sub(s, e))
    pos = e + 1
  end
  out[#out + 1] = esc(seg:sub(pos))
  return table.concat(out)
end

local function highlightLine(colors, line, ctx)
  if line == "" then
    return ""
  end
  local cmdPart = line:match("^%s*/[%w_]+") or line:match("^%s*#%a*")
  if not cmdPart then
    return esc(line)
  end
  local isHash = cmdPart:find("#", 1, true)
  local cmdName = cmdPart:match("[/#](.*)$"):lower()
  if isHash and cmdName ~= "show" and cmdName ~= "showtooltip" then
    return paint(colors, "comment", line)
  end
  local out = { paint(colors, isHash and "comment" or C.isScriptCommand(cmdName) and "script" or "command", cmdPart) }
  local isCast = CAST[cmdName] ~= nil
  local i, plainStart = #cmdPart + 1, #cmdPart + 1
  local function flushPlain(stop)
    if stop >= plainStart then
      out[#out + 1] = plainSegment(colors, line:sub(plainStart, stop), isCast, ctx)
    end
  end
  while i <= #line do
    local c = line:sub(i, i)
    if c == "[" then
      flushPlain(i - 1)
      local close = line:find("]", i, true)
      if close then
        out[#out + 1] = paintCondition(colors, line:sub(i, close))
        i = close + 1
      else
        out[#out + 1] = paint(colors, "error", line:sub(i))
        return table.concat(out)
      end
      plainStart = i
    elseif c == "]" then
      flushPlain(i - 1)
      out[#out + 1] = paint(colors, "error", "]")
      i = i + 1
      plainStart = i
    elseif c == "{" then
      local kind, raw, suffix, after = line:match("^{(%a+):(%d+)(:?%a*)}()", i)
      if
        kind
        and (
          (kind == "s" and (suffix == "" or suffix == ":base")) or ((kind == "i" or kind == "slot") and suffix == "")
        )
      then
        flushPlain(i - 1)
        local bad = kind == "s" and ctx and ctx.unknownSpell and ctx.unknownSpell(tonumber(raw))
        local color = bad and "error" or kind == "i" and "item" or kind == "slot" and "command" or "spell"
        out[#out + 1] = paint(colors, color, line:sub(i, after - 1))
        i = after
        plainStart = i
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  flushPlain(#line)
  return table.concat(out)
end

-- Colored copy of `text` for the overlay behind the edit box. Only color
-- escapes are added (and `|` doubled), so line breaks match the real text.
function C.highlight(text, ctx, colors)
  colors = colors or C.COLORS
  local lines = ML.splitLines(text)
  for i, line in ipairs(lines) do
    lines[i] = highlightLine(colors, line, ctx)
  end
  return table.concat(lines, "\n")
end

-- Inserting -------------------------------------------------------------------

-- Text for the picker: mode "token" | "base" | "name" | "known" | "id".
function C.insertion(body, cursor, mode, id, name)
  if mode == "token" then
    return ML.withSeparator(body, cursor or 0, C.spellToken(id))
  elseif mode == "base" then
    return ML.withSeparator(body, cursor or 0, C.spellToken(id, true))
  elseif mode == "item" then
    return ML.withSeparator(body, cursor or 0, C.itemToken(id))
  elseif mode == "known" then
    return ML.insertionText(body, cursor, "known", name, id)
  elseif mode == "id" then
    return ML.insertionText(body, cursor, "id", name, id)
  end
  return ML.insertionText(body, cursor, "name", name, id)
end

-- Spell labels -----------------------------------------------------------------

-- "Feuerball (133)" or "Feuerball, Rang 3 (145)".
function C.formatSpell(name, rank, id)
  if rank and rank ~= "" then
    return string.format("%s, %s (%d)", name, rank, id)
  end
  return string.format("%s (%d)", name, id)
end

-- Highest rank of `chain` (ascending list of { id }) for which known(id) is true.
function C.highestKnown(chain, known)
  for i = #chain, 1, -1 do
    if known and known(chain[i].id) then
      return chain[i].id
    end
  end
  return chain[#chain] and chain[#chain].id
end

-- Presets ----------------------------------------------------------------------

-- Default selections from the preset's example values.
function C.exampleSelections(preset)
  local sel = {}
  for _, slot in ipairs(preset.sl or {}) do
    if slot.t == "spell" then
      sel[slot.k] = { id = slot.ex, base = slot.eb == true }
    else
      sel[slot.k] = slot.ex
    end
  end
  return sel
end

-- Returns body (token form), missing slot keys.
function C.buildPreset(preset, sel)
  local missing, slots = {}, {}
  for _, slot in ipairs(preset.sl or {}) do
    slots[slot.k] = slot
  end
  local lines = {}
  for i, ln in ipairs(preset.ln) do
    lines[i] = ln:gsub("%$(%a*%d+)", function(key)
      local slot, value = slots[key], sel[key]
      if not slot then
        return nil
      end
      if value == nil or value == "" or (type(value) == "table" and not value.id) then
        missing[#missing + 1] = key
        return ""
      end
      if slot.t == "spell" then
        return C.spellToken(value.id, value.base and slot.ab ~= false)
      elseif slot.t == "item" then
        return C.itemToken(tonumber(value) or 0)
      elseif slot.t == "number" then
        return tostring(tonumber(value) or 0)
      end
      return C.sanitize(tostring(value)):gsub("[{}]", ""):sub(1, 80)
    end)
  end
  return table.concat(lines, "\n"), missing
end

-- Applying to the game -------------------------------------------------------

-- Pure decision before CreateMacro/EditMacro. in: { name, rendered, perChar,
-- combat, game = { { index, name, perChar } }, counts = { account, character } }.
-- Returns { action = "create"|"edit"|"confirm", index } or { error = code, ... }.
function C.planApply(a)
  if a.combat then
    return { error = "combat" }
  end
  if not a.name or a.name:gsub("%s", "") == "" then
    return { error = "noname" }
  end
  if C.charCount(a.name) > C.MAX_NAME then
    return { error = "namelen" }
  end
  if C.charCount(a.rendered) > C.MAX_BODY then
    return { error = "length", chars = C.charCount(a.rendered) }
  end
  for _, g in ipairs(a.game or {}) do
    if g.name == a.name and g.perChar == a.perChar then
      return { action = a.linked == g.index and "edit" or "confirm", index = g.index }
    end
  end
  local used = a.perChar and a.counts.character or a.counts.account
  local max = a.perChar and (a.maxCharacter or C.MAX_CHARACTER) or (a.maxAccount or C.MAX_ACCOUNT)
  if used >= max then
    return { error = "full", used = used, max = max, perChar = a.perChar }
  end
  return { action = "create" }
end

-- Undo ---------------------------------------------------------------------------

-- Snapshot stack. kind "type" entries within `gap` seconds merge into one step.
function C.newUndo(limit, gap)
  local u = { stack = {}, pos = 0, limit = limit or 50, gap = gap or 0.5 }
  function u:reset(text, cursor)
    self.stack = { { text = text, cursor = cursor or 0, kind = "reset", t = 0 } }
    self.pos = 1
    self.sealed = true
  end
  function u:record(text, cursor, kind, now)
    local top = self.stack[self.pos]
    if top and top.text == text then
      return
    end
    for i = #self.stack, self.pos + 1, -1 do
      self.stack[i] = nil
    end
    if top and not self.sealed and kind == "type" and top.kind == "type" and now - top.t < self.gap then
      top.text, top.cursor, top.t = text, cursor, now
    else
      self.stack[#self.stack + 1] = { text = text, cursor = cursor or 0, kind = kind, t = now }
      if #self.stack > self.limit then
        table.remove(self.stack, 1)
      end
      self.pos = #self.stack
    end
    self.sealed = false
  end
  function u:undo()
    if self.pos > 1 then
      self.pos = self.pos - 1
      self.sealed = true
      return self.stack[self.pos]
    end
  end
  function u:redo()
    if self.pos < #self.stack then
      self.pos = self.pos + 1
      self.sealed = true
      return self.stack[self.pos]
    end
  end
  return u
end
