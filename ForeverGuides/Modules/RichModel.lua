-- Rich note model: the document behind the formatted note view and editor.
-- Pure Lua, no frames. A document is parallel arrays over characters:
--   chars[i]  one UTF-8 character ("\n" ends a line), or a table for an inline
--             object { icon = 1..8 } | { link = "|H...|h[..]|h", label = "..." }
--   styles[i] interned style { bold, italic, size, color, key } of that character
--   lines[n]  block attributes of line n: { heading = 0..3, list = bool, check = nil|bool,
--             align = "left"|"center"|"right" }
-- Positions are caret positions: 0 is in front of the first character, n is
-- behind the n-th. A range (a, b) with a < b covers characters a + 1 .. b.
-- Markup <-> model: RM.fromMarkup / RM.toMarkup. The markup stays the stored
-- format, the model is only the working copy while a note is shown or edited.
local _, ns = ...
local M = ns.Markup

local RM = {
  OBJ = "\239\191\188", -- U+FFFC, stands for an inline object in Doc:getText()
  HISTORY_LIMIT = 100,
  TYPE_GAP = 1.0, -- seconds: typing/deleting within this gap is one undo step
}
ns.RichModel = RM

function RM.clock()
  return rawget(_G, "GetTime") and GetTime() or os.clock()
end

-- Styles ----------------------------------------------------------------------

local styleCache, styleCount = {}, 0

-- Interned immutable style. size nil = the line's default size, color nil =
-- the default color. Compare styles by `.key`, not by identity.
function RM.style(bold, italic, size, color)
  local key = (bold and "b" or "-") .. (italic and "i" or "-") .. "|" .. (size or "") .. "|" .. (color or "")
  local s = styleCache[key]
  if not s then
    if styleCount > 2000 then
      styleCache, styleCount = {}, 0
    end
    s = { bold = bold and true or false, italic = italic and true or false, size = size, color = color, key = key }
    styleCache[key], styleCount = s, styleCount + 1
  end
  return s
end

RM.DEFAULT_STYLE = RM.style(false, false, nil, nil)

local function clampSize(n)
  return math.max(M.SIZE_MIN, math.min(M.SIZE_MAX, math.floor(n + 0.5)))
end

-- key: "bold" | "italic" | "size" | "color".
function RM.withStyle(style, key, value)
  local b, i, size, color = style.bold, style.italic, style.size, style.color
  if key == "bold" then
    b = value and true or false
  elseif key == "italic" then
    i = value and true or false
  elseif key == "size" then
    size = value and clampSize(value) or nil
  elseif key == "color" then
    color = value or nil
  end
  return RM.style(b, i, size, color)
end

local STYLE_KEYS = { bold = true, italic = true, size = true, color = true }

-- Characters ------------------------------------------------------------------

local CHAR_PATTERN = "[%z\1-\127\194-\244][\128-\191]*"

local function splitChars(text)
  local out = {}
  for ch in text:gmatch(CHAR_PATTERN) do
    out[#out + 1] = ch
  end
  return out
end
RM.splitChars = splitChars

-- Document --------------------------------------------------------------------

local Doc = {}
Doc.__index = Doc

local function newLine()
  return { heading = 0, list = false, check = nil, align = "left" }
end

local function copyLine(l)
  return { heading = l.heading, list = l.list, check = l.check, align = l.align }
end

-- opts.maxLength: edits that would make the markup longer are rejected (return false).
function RM.new(opts)
  local doc =
    setmetatable({ chars = {}, styles = {}, lines = { newLine() }, rev = 0, undoStack = {}, redoStack = {} }, Doc)
  doc.maxLength = opts and opts.maxLength
  return doc
end

function Doc:length()
  return #self.chars
end

-- Caret positions where each line starts.
function Doc:lineStarts()
  if self._startsRev ~= self.rev then
    local s = { 0 }
    for i = 1, #self.chars do
      if self.chars[i] == "\n" then
        s[#s + 1] = i
      end
    end
    self._starts, self._startsRev = s, self.rev
  end
  return self._starts
end

function Doc:lineCount()
  return #self.lines
end

-- Line (1-based) the caret position belongs to.
function Doc:lineOf(pos)
  local s = self:lineStarts()
  local lo, hi = 1, #s
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if s[mid] <= pos then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return lo
end

-- First and last caret position of line `ln` (last = in front of its line break).
function Doc:lineRange(ln)
  local s = self:lineStarts()
  local first = s[ln]
  local last = s[ln + 1] and (s[ln + 1] - 1) or #self.chars
  return first, last
end

-- Text with "\n" and one RM.OBJ per inline object.
function Doc:getText()
  if self._textRev ~= self.rev then
    local parts = {}
    for i = 1, #self.chars do
      local ch = self.chars[i]
      parts[i] = type(ch) == "table" and RM.OBJ or ch
    end
    self._text, self._textRev = table.concat(parts), self.rev
  end
  return self._text
end

function Doc:charAt(index)
  return self.chars[index]
end

-- Queries -----------------------------------------------------------------------

-- Style that typing at `pos` gets: the character in front of the caret, at the start of
-- a line the first character of the line, on an empty line the line break's style.
function Doc:getStyleAt(pos)
  local chars, styles = self.chars, self.styles
  pos = math.max(0, math.min(pos, #chars))
  if pos > 0 and chars[pos] ~= "\n" then
    return styles[pos]
  end
  if chars[pos + 1] ~= nil then
    return styles[pos + 1]
  end
  return pos > 0 and styles[pos] or RM.DEFAULT_STYLE
end

local MIXED = "mixed"

-- Per attribute: the shared value, or "mixed". Only characters count (line breaks
-- do not). An empty range answers like getStyleAt, so it serves the caret too.
-- baseSize (optional) is what a character without explicit size is shown at, so
-- "no size" and "the same size written out" do not count as mixed.
function Doc:getStyleForRange(a, b, baseSize)
  if a > b then
    a, b = b, a
  end
  local out, seen = {}, false
  for i = a + 1, math.min(b, #self.chars) do
    if self.chars[i] ~= "\n" then
      local st = self.styles[i]
      local size = st.size or baseSize
      if not seen then
        out.bold, out.italic, out.size, out.color = st.bold, st.italic, size, st.color
        seen = true
      else
        if out.bold ~= st.bold then
          out.bold = MIXED
        end
        if out.italic ~= st.italic then
          out.italic = MIXED
        end
        if out.size ~= size then
          out.size = MIXED
        end
        if out.color ~= st.color then
          out.color = MIXED
        end
      end
    end
  end
  if not seen then
    local st = self:getStyleAt(a)
    return { bold = st.bold, italic = st.italic, size = st.size or baseSize, color = st.color }
  end
  return out
end

-- Block attributes of lines ln1..ln2 as { heading, list, check, align } where a
-- differing value is "mixed". check is true/false for checkbox lines, nil when none is one.
function Doc:getBlockForLines(ln1, ln2)
  local out
  for ln = ln1, ln2 do
    local l = self.lines[ln]
    if not out then
      out = copyLine(l)
    else
      if out.heading ~= l.heading then
        out.heading = MIXED
      end
      if out.list ~= l.list then
        out.list = MIXED
      end
      if out.check ~= l.check then
        out.check = MIXED
      end
      if out.align ~= l.align then
        out.align = MIXED
      end
    end
  end
  return out or newLine()
end

-- History -----------------------------------------------------------------------

local function snapshot(doc, caret)
  local chars, styles, lines = {}, {}, {}
  for i = 1, #doc.chars do
    chars[i], styles[i] = doc.chars[i], doc.styles[i]
  end
  for i, l in ipairs(doc.lines) do
    lines[i] = copyLine(l)
  end
  return { chars = chars, styles = styles, lines = lines, caret = caret or 0 }
end

local function restore(doc, snap)
  doc.chars, doc.styles, doc.lines = snap.chars, snap.styles, snap.lines
  doc.rev = doc.rev + 1
end

local COALESCE = { type = true, delete = true }

local function pushUndo(doc, snap, kind)
  local now = RM.clock()
  local top = doc.undoStack[#doc.undoStack]
  doc.redoStack = {}
  if top and not doc.sealed and COALESCE[kind] and top.kind == kind and now - top.t < RM.TYPE_GAP then
    top.t = now
  else
    snap.kind, snap.t = kind, now
    doc.undoStack[#doc.undoStack + 1] = snap
    if #doc.undoStack > RM.HISTORY_LIMIT then
      table.remove(doc.undoStack, 1)
    end
  end
  doc.sealed = false
end

-- Ends the current typing run: the next edit starts a new undo step (call it when
-- the caret moves).
function Doc:breakUndo()
  self.sealed = true
end

function Doc:resetHistory()
  self.undoStack, self.redoStack, self.sealed = {}, {}, false
end

function Doc:canUndo()
  return #self.undoStack > 0
end

function Doc:canRedo()
  return #self.redoStack > 0
end

-- Returns the caret position to show afterwards, or nil when there is nothing to undo.
function Doc:undo(caret)
  local snap = table.remove(self.undoStack)
  if not snap then
    return nil
  end
  self.redoStack[#self.redoStack + 1] = snapshot(self, caret)
  restore(self, snap)
  self.sealed = true
  return snap.caret
end

function Doc:redo(caret)
  local snap = table.remove(self.redoStack)
  if not snap then
    return nil
  end
  self.undoStack[#self.undoStack + 1] = snapshot(self, caret)
  restore(self, snap)
  self.sealed = true
  return snap.caret
end

-- Editing core ------------------------------------------------------------------

-- Replaces arr[a + 1 .. b] with the list `new`.
local function splice(arr, a, b, new)
  local n, added, removed = #arr, #new, b - a
  local delta = added - removed
  if delta > 0 then
    for i = n, b + 1, -1 do
      arr[i + delta] = arr[i]
    end
  elseif delta < 0 then
    for i = b + 1, n do
      arr[i + delta] = arr[i]
    end
    for i = n + delta + 1, n do
      arr[i] = nil
    end
  end
  for i = 1, added do
    arr[a + i] = new[i]
  end
end

-- A line break after the end of a line keeps list/checkbox (the heading ends); in
-- the middle of a line the new line is a copy.
local function splitLine(l, atEnd)
  local out = copyLine(l)
  if atEnd then
    out.heading = 0
  end
  if out.check ~= nil then
    out.check = false
  end
  return out
end

-- items: { { ch, style }... }. Removes a..b and inserts the items; keeps `lines`
-- in step with the line breaks.
local function replaceRaw(doc, a, b, items)
  local la, lb = doc:lineOf(a), doc:lineOf(b)
  local starts = doc:lineStarts()
  local keep = copyLine(doc.lines[la])
  if a == starts[la] and lb > la then
    keep = copyLine(doc.lines[lb])
  end
  local newChars, newStyles, breaks = {}, {}, 0
  for i, item in ipairs(items) do
    newChars[i], newStyles[i] = item[1], item[2]
    if item[1] == "\n" then
      breaks = breaks + 1
    end
  end
  -- Is the insertion point at the end of its (merged) line? Look at what follows.
  local after = doc.chars[b + 1]
  local atEnd = after == nil or after == "\n"
  local lines = {}
  for i = 1, la - 1 do
    lines[#lines + 1] = doc.lines[i]
  end
  lines[#lines + 1] = keep
  for j = 1, breaks do
    lines[#lines + 1] = splitLine(keep, j < breaks or atEnd)
  end
  for i = lb + 1, #doc.lines do
    lines[#lines + 1] = doc.lines[i]
  end
  splice(doc.chars, a, b, newChars)
  splice(doc.styles, a, b, newStyles)
  doc.lines = lines
  doc.rev = doc.rev + 1
end

local function clean(text)
  text = tostring(text or ""):gsub("\r\n?", "\n"):gsub("\t", "  ")
  return (text:gsub("[%z\1-\9\11-\31\127]", ""))
end

local function checkPos(doc, pos)
  return math.max(0, math.min(math.floor(pos), #doc.chars))
end

-- Runs one edit as a history step: snapshot, mutate, enforce maxLength, record.
-- fn() returns the caret position after the edit.
function Doc:_edit(kind, caretBefore, fn)
  local snap = snapshot(self, caretBefore)
  local caret = fn()
  return self:_commit(snap, kind) and caret
end

-- Records the step, or puts the snapshot back when the markup would get too long.
function Doc:_commit(snap, kind)
  if self.maxLength and M.length(RM.toMarkup(self)) > self.maxLength then
    restore(self, snap)
    return false
  end
  pushUndo(self, snap, kind)
  return true
end

-- Public edits ----------------------------------------------------------------------

-- Inserts plain text (line breaks allowed) with `style` (default: getStyleAt(pos)).
-- Returns the caret position behind the text, or false when rejected.
function Doc:insertText(pos, text, style)
  pos = checkPos(self, pos)
  local chars = splitChars(clean(text))
  if #chars == 0 then
    return pos
  end
  style = style or self:getStyleAt(pos)
  local items = {}
  for i, ch in ipairs(chars) do
    items[i] = { ch, style }
  end
  return self:_edit(#chars == 1 and chars[1] ~= "\n" and "type" or "insert", pos, function()
    replaceRaw(self, pos, pos, items)
    return pos + #items
  end)
end

-- obj: { icon = 1..8 } or { link, label }. Counts as one character.
function Doc:insertObject(pos, obj, style)
  pos = checkPos(self, pos)
  if type(obj) ~= "table" or not (obj.icon or obj.link) then
    return false
  end
  style = style or self:getStyleAt(pos)
  return self:_edit("object", pos, function()
    replaceRaw(self, pos, pos, { { { icon = obj.icon, link = obj.link, label = obj.label }, style } })
    return pos + 1
  end)
end

-- Removes the characters a + 1 .. b. Returns the caret position (a), or false.
function Doc:deleteRange(a, b)
  a, b = checkPos(self, a), checkPos(self, b)
  if a > b then
    a, b = b, a
  end
  if a == b then
    return a
  end
  return self:_edit("delete", b, function()
    replaceRaw(self, a, b, {})
    return a
  end)
end

-- One undo step: replaces a..b with text.
function Doc:replace(a, b, text, style)
  a, b = checkPos(self, a), checkPos(self, b)
  if a > b then
    a, b = b, a
  end
  local chars = splitChars(clean(text))
  style = style or self:getStyleAt(a)
  local items = {}
  for i, ch in ipairs(chars) do
    items[i] = { ch, style }
  end
  return self:_edit("replace", b, function()
    replaceRaw(self, a, b, items)
    return a + #items
  end)
end

-- Pastes markup at `pos`: the inline content (styles, symbols, links, line breaks)
-- is inserted, block markers (#, -, [ ]) of the pasted text are ignored. The text goes
-- through Markup.sanitize first. `to` (optional) is the end of a range it replaces.
-- Returns the caret behind it, or false.
function Doc:insertMarkup(pos, markup, to)
  pos = checkPos(self, pos)
  to = to and checkPos(self, to) or pos
  if to < pos then
    pos, to = to, pos
  end
  local frag = RM.fromMarkup(M.sanitize(markup))
  local items = {}
  for i = 1, #frag.chars do
    items[i] = { frag.chars[i], frag.styles[i] }
  end
  if #items == 0 and to == pos then
    return pos
  end
  return self:_edit("insert", to, function()
    replaceRaw(self, pos, to, items)
    return pos + #items
  end)
end

-- Text of the characters a + 1 .. b for copying: symbols as {rtN}, links as [Name].
function Doc:rangeText(a, b)
  a, b = checkPos(self, a), checkPos(self, b)
  if a > b then
    a, b = b, a
  end
  local parts = {}
  for i = a + 1, b do
    local ch = self.chars[i]
    if type(ch) == "table" then
      parts[#parts + 1] = ch.icon and ("{rt" .. ch.icon .. "}") or ("[" .. (ch.label or "") .. "]")
    else
      parts[#parts + 1] = ch
    end
  end
  return table.concat(parts)
end

-- Enter key: a line break, except on an empty list/checkbox/heading line, where
-- it only ends the block (like Word).
function Doc:enter(pos)
  pos = checkPos(self, pos)
  local ln = self:lineOf(pos)
  local first, last = self:lineRange(ln)
  local l = self.lines[ln]
  if first == last and (l.list or l.check ~= nil or l.heading > 0) then
    self:setBlock(ln, ln, { heading = 0, list = false, check = nil })
    return pos
  end
  return self:insertText(pos, "\n")
end

local function applyToRange(doc, a, b, kind, fn)
  a, b = checkPos(doc, a), checkPos(doc, b)
  if a > b then
    a, b = b, a
  end
  if a == b then
    return false
  end
  local changed = false
  local snap = snapshot(doc, b)
  for i = a + 1, b do
    if doc.chars[i] ~= "\n" then
      local old = doc.styles[i]
      local new = fn(old)
      if new.key ~= old.key then
        doc.styles[i], changed = new, true
      end
    end
  end
  if not changed then
    return false
  end
  doc.rev = doc.rev + 1
  return doc:_commit(snap, kind)
end

-- Sets one style attribute on a range, always (value nil resets size/color).
function Doc:setStyle(a, b, key, value)
  if not STYLE_KEYS[key] then
    return false
  end
  return applyToRange(self, a, b, "format", function(st)
    return RM.withStyle(st, key, value)
  end)
end

function Doc:setColor(a, b, color)
  return self:setStyle(a, b, "color", color)
end

function Doc:setSize(a, b, size)
  return self:setStyle(a, b, "size", size)
end

-- Word-like toggle: bold/italic switch on unless every character already has it.
-- For size/color `value` is applied, or removed when the whole range already has it.
-- `value` may force the result for bold/italic (true on, false off).
function Doc:toggleStyle(a, b, key, value)
  if not STYLE_KEYS[key] then
    return false
  end
  local st = self:getStyleForRange(a, b)
  if key == "bold" or key == "italic" then
    local target = value
    if target == nil then
      target = st[key] ~= true
    end
    return self:setStyle(a, b, key, target)
  end
  if st[key] == value then
    return self:setStyle(a, b, key, nil)
  end
  return self:setStyle(a, b, key, value)
end

local ALIGNS = { left = true, center = true, right = true }

local function normalizeBlock(attrs)
  local out = {
    heading = attrs.heading or 0,
    list = attrs.list == true,
    check = attrs.check,
    align = ALIGNS[attrs.align] and attrs.align or "left",
  }
  if out.check ~= nil then
    out.check = out.check == true
  end
  if out.heading > 0 then
    out.list, out.check = false, nil
  elseif out.check ~= nil then
    out.list = false
  end
  out.heading = math.max(0, math.min(3, math.floor(out.heading)))
  return out
end

-- attrs: any of heading (0..3), list (bool), check (nil/false/true), align ("left",
-- "center", "right"), applied to lines ln1..ln2 as one undo step. `caret` (optional) is
-- the position undo shows afterwards. A heading, a list item and a checkbox exclude each
-- other: the attribute set last wins (pass them in one table with only one of them set).
-- The alignment is independent of them and kept when they change.
function Doc:setBlock(ln1, ln2, attrs, caret)
  ln1, ln2 = math.max(1, ln1), math.min(#self.lines, ln2)
  local snap = snapshot(self, caret or 0)
  local changed = false
  for ln = ln1, ln2 do
    local l = self.lines[ln]
    local merged = copyLine(l)
    if ALIGNS[attrs.align] then
      merged.align = attrs.align
    end
    if attrs.heading ~= nil then
      merged.heading, merged.list, merged.check = attrs.heading, false, nil
    end
    if attrs.list ~= nil then
      merged.list = attrs.list
      if attrs.list then
        merged.heading, merged.check = 0, nil
      end
    end
    if attrs.check ~= nil or attrs.checkOff then
      merged.check = attrs.check
      if attrs.check ~= nil then
        merged.heading, merged.list = 0, false
      end
    end
    merged = normalizeBlock(merged)
    if merged.heading ~= l.heading or merged.list ~= l.list or merged.check ~= l.check or merged.align ~= l.align then
      self.lines[ln], changed = merged, true
    end
  end
  if not changed then
    return false
  end
  self.rev = self.rev + 1
  return self:_commit(snap, "block")
end

-- Toggles heading level / list / checkbox / alignment on lines ln1..ln2: removed when
-- every line already has it, else set on all. For kind "align" `level` is the
-- alignment ("center" or "right"; "left" always sets left).
function Doc:toggleBlock(ln1, ln2, kind, level, caret)
  local blk = self:getBlockForLines(ln1, ln2)
  if kind == "heading" then
    level = level or 1
    return self:setBlock(ln1, ln2, { heading = blk.heading == level and 0 or level }, caret)
  elseif kind == "list" then
    return self:setBlock(ln1, ln2, { list = blk.list ~= true }, caret)
  elseif kind == "align" then
    level = ALIGNS[level] and level or "left"
    return self:setBlock(ln1, ln2, { align = blk.align == level and "left" or level }, caret)
  elseif kind == "check" then
    if blk.check == nil then
      return self:setBlock(ln1, ln2, { check = false }, caret)
    end
    return self:setBlock(ln1, ln2, { check = nil, checkOff = true }, caret)
  end
  return false
end

-- Ticks or clears the checkbox of line `ln` (no history step: ticking in the view is
-- written back through the note, like the other renderers do).
function Doc:setChecked(ln, checked)
  local l = self.lines[ln]
  if l and l.check ~= nil then
    l.check = checked and true or false
    self.rev = self.rev + 1
    return true
  end
  return false
end

-- Markup ----------------------------------------------------------------------------

-- Builds a document from note markup. Old notes load unchanged; text beyond the
-- markup limits was already cut by Markup.sanitize.
function RM.fromMarkup(text, opts)
  local doc = RM.new(opts)
  local chars, styles, lines = {}, {}, {}
  local blocks = M.parse(text or "")
  for n, block in ipairs(blocks) do
    local l = newLine()
    l.align = block.align
    if block.kind == "h" then
      l.heading = block.level
    elseif block.kind == "li" then
      l.list = true
    elseif block.kind == "check" then
      l.check = block.checked
    end
    lines[n] = l
    local last = RM.DEFAULT_STYLE
    for _, span in ipairs(block.spans) do
      local st = RM.style(span.bold, span.italic, span.size, span.color)
      last = st
      if span.icon then
        chars[#chars + 1], styles[#styles + 1] = { icon = span.icon }, st
      elseif span.link then
        chars[#chars + 1], styles[#styles + 1] = { link = span.link, label = span.text }, st
      else
        for _, ch in ipairs(splitChars((span.text:gsub("||", "|")))) do
          chars[#chars + 1], styles[#styles + 1] = ch, st
        end
      end
    end
    if n < #blocks then
      chars[#chars + 1], styles[#styles + 1] = "\n", last
    end
  end
  doc.chars, doc.styles, doc.lines = chars, styles, lines
  return doc
end

-- An inline object for a pasted "{rt3}" or an item/spell/quest link string
-- (e.g. from ChatEdit_InsertLink), as Doc:insertObject takes it. nil for anything else.
function RM.parseObject(str)
  local spans = M.parse(M.sanitize(tostring(str or "")))[1].spans
  local sp = spans[1]
  if #spans == 1 and sp then
    if sp.icon then
      return { icon = sp.icon }
    elseif sp.link then
      return { link = sp.link, label = sp.text }
    end
  end
end

-- Does a "{" in the plain text start something the parser would read as a tag?
local function braceNeedsEscape(chars, i)
  local parts = {}
  for j = i + 1, math.min(#chars, i + 16) do
    local ch = chars[j]
    if type(ch) ~= "string" or ch == "\n" or ch == "{" then
      return false
    end
    if ch == "}" then
      return M.readTag(table.concat(parts)) ~= nil
    end
    parts[#parts + 1] = ch
  end
  return false
end

-- Would the parser read a leading alignment tag in this text?
local function looksLikeAlign(line)
  return M.splitAlign(line) ~= "left"
end

local function looksLikeBlock(line)
  local hashes = line:match("^(#+)%s+")
  return (hashes and #hashes <= 3) or line:match("^%s*%[[ xX]%]") or line:match("^%s*%-%s+")
end

-- Tags between two neighbouring characters: closes what ends, opens what starts.
-- Attributes that stay the same keep their tag open.
local function transition(parts, cur, st)
  if cur.color and cur.color ~= st.color then
    parts[#parts + 1] = "{/}"
  end
  if cur.size and cur.size ~= st.size then
    parts[#parts + 1] = "{/size}"
  end
  if cur.italic and not st.italic then
    parts[#parts + 1] = "{/i}"
  end
  if cur.bold and not st.bold then
    parts[#parts + 1] = "{/b}"
  end
  if st.bold and not cur.bold then
    parts[#parts + 1] = "{b}"
  end
  if st.italic and not cur.italic then
    parts[#parts + 1] = "{i}"
  end
  if st.size and st.size ~= cur.size then
    parts[#parts + 1] = "{size:" .. st.size .. "}"
  end
  if st.color and st.color ~= cur.color then
    parts[#parts + 1] = "{" .. st.color .. "}"
  end
end

local function serializeLine(chars, styles, from, to)
  local parts = {}
  local cur = RM.DEFAULT_STYLE
  for i = from, to do
    local st = styles[i]
    if st.key ~= cur.key then
      transition(parts, cur, st)
      cur = st
    end
    local ch = chars[i]
    if type(ch) == "table" then
      parts[#parts + 1] = ch.icon and ("{rt" .. ch.icon .. "}") or ch.link
    elseif ch == "|" then
      parts[#parts + 1] = "||"
    elseif ch == "{" and braceNeedsEscape(chars, i) then
      parts[#parts + 1] = "{lb}"
    else
      parts[#parts + 1] = ch
    end
  end
  transition(parts, cur, RM.DEFAULT_STYLE)
  return table.concat(parts)
end

-- Canonical markup: every line is self-contained (styles are closed at the end of
-- the line and reopened on the next), tags only where the style changes.
function RM.toMarkup(doc)
  local out = {}
  local chars, styles = doc.chars, doc.styles
  local from = 1
  local n = #chars
  for ln, l in ipairs(doc.lines) do
    local to = from
    while to <= n and chars[to] ~= "\n" do
      to = to + 1
    end
    local inline = serializeLine(chars, styles, from, to - 1)
    local prefix = ""
    local tag = M.alignTag(l.align)
    if l.heading > 0 then
      prefix = string.rep("#", l.heading) .. " "
    elseif l.check ~= nil then
      prefix = l.check and "[x] " or "[ ] "
    elseif l.list then
      prefix = "- "
    end
    if prefix == "" then
      if inline:match("^%s*$") and inline ~= "" or looksLikeBlock(inline) or (tag == "" and looksLikeAlign(inline)) then
        inline = "{~}" .. inline
      end
    elseif (l.heading > 0 or l.list) and inline:match("^%s") then
      inline = "{~}" .. inline
    end
    out[ln] = tag .. prefix .. inline
    from = to + 1
  end
  return table.concat(out, "\n")
end

-- Plain structure check helper for tests and callers: same text, styles and blocks?
function RM.same(a, b)
  if #a.chars ~= #b.chars or #a.lines ~= #b.lines then
    return false
  end
  for i = 1, #a.chars do
    local x, y = a.chars[i], b.chars[i]
    if type(x) == "table" or type(y) == "table" then
      if type(x) ~= type(y) or x.icon ~= y.icon or x.link ~= y.link then
        return false
      end
    elseif x ~= y then
      return false
    end
    if a.chars[i] ~= "\n" and a.styles[i].key ~= b.styles[i].key then
      return false
    end
  end
  for i, l in ipairs(a.lines) do
    local o = b.lines[i]
    if l.heading ~= o.heading or l.list ~= o.list or l.check ~= o.check or l.align ~= o.align then
      return false
    end
  end
  return true
end

-- State for the toolbar over the selection a..b (a == b: the caret), the table
-- RichToolbar:SetState takes. baseSize is the note's text size, shown for text
-- without an explicit size. color is a model color id ("red", "#rrggbb", "class:X").
function RM.toolbarState(doc, a, b, baseSize)
  local st = doc:getStyleForRange(a, b, baseSize)
  local lo, hi = math.min(a, b), math.max(a, b)
  local ln1, ln2 = doc:lineOf(lo), doc:lineOf(hi)
  if hi > lo and ln2 > ln1 and hi == doc:lineStarts()[ln2] then
    ln2 = ln2 - 1
  end
  local blk = doc:getBlockForLines(ln1, ln2)
  local checkbox = blk.check
  if checkbox ~= MIXED then
    checkbox = checkbox ~= nil
  end
  return {
    bold = st.bold,
    italic = st.italic,
    size = st.size,
    color = st.color,
    heading = blk.heading,
    list = blk.list,
    checkbox = checkbox,
    align = blk.align,
  }
end
