-- Note markup: headings (# ## ###), lists (- ), checkboxes ([ ] / [x]),
-- colors, raid symbols ({rt1}..{rt8}), item/spell/quest links and the inline
-- styles bold {b}, italic {i}, size {size:N}, hex color {#rrggbb} and class
-- color {class:HUNTER}. A line can start with an alignment tag ({center} or
-- {right}, see M.splitAlign). The full tag table is in docs/NOTIZEN-FORMAT.md.
-- Pure strings and tables, no WoW API. Everything that is stored or imported
-- goes through M.sanitize first, so the renderers only ever see safe text.
--
-- Style state rules (one state machine shared by parse and sanitize):
--  * {b} {i} switch on, {/b} {/i} off. {size:N}/{#rrggbb}/{class:X} push onto a
--    stack, {/size} and {/} pop it. The state carries across lines.
--  * The old named colors ({rot}, {gelb}, ...) keep their rule: they replace the
--    current old-style color and end at the end of the line or at {/}.
--  * Unclosed tags need no repair: every span carries its complete style, so the
--    end of the text closes everything. A stray closing tag is ignored.
--  * At most MAX_DEPTH nested sizes and MAX_DEPTH nested colors count, deeper
--    tags are dropped by M.sanitize and ignored by the parser.
local _, ns = ...
local C = ns.MacroCore

local M = { MAX_TEXT = 8000, MAX_LINK = 220, MAX_LABEL = 80, SIZE_MIN = 8, SIZE_MAX = 48, MAX_DEPTH = 8 }
ns.Markup = M

-- Player class colors (same values as ns.Theme.classColors, SHAMAN is the
-- lighter text variant). Used by {class:TOKEN}; ctx.classColors overrides them.
M.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
M.CLASS_HEX = {
  WARRIOR = "c79c6e",
  PALADIN = "f58cba",
  HUNTER = "abd473",
  ROGUE = "fff569",
  PRIEST = "ffffff",
  SHAMAN = "4fa8ff",
  MAGE = "69ccf0",
  WARLOCK = "9482c9",
  DRUID = "ff7d0a",
}

-- Alignment tag words at the very start of a line (German or English) -> align.
-- Left is the default and has no tag. Anywhere else these words stay plain text.
M.ALIGN_WORDS = { center = "center", mitte = "center", right = "right", rechts = "right" }

M.LINK_TYPES = { item = true, spell = true, quest = true, achievement = true, enchant = true }
M.RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

-- Tag word (German or English) -> color id. "class" is the player's class color.
M.ALIASES = {
  rot = "red",
  red = "red",
  gelb = "yellow",
  yellow = "yellow",
  gruen = "green",
  green = "green",
  blau = "blue",
  blue = "blue",
  grau = "gray",
  gray = "gray",
  grey = "gray",
  klasse = "class",
  class = "class",
}
M.COLOR_IDS = { "red", "yellow", "green", "blue", "gray", "class" }

-- Variant for dark backgrounds (light colors) and for light backgrounds.
M.COLORS = {
  red = { dark = "ff7b6b", light = "a3170a" },
  yellow = { dark = "ffd75e", light = "6e4f00" },
  green = { dark = "7fdc8a", light = "1b6b2a" },
  blue = { dark = "7db8ff", light = "0b4a9e" },
  gray = { dark = "b4b4b4", light = "555555" },
}

-- Colors --------------------------------------------------------------------

local function channel(v)
  v = v / 255
  return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
end

function M.luminance(hex)
  local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end

function M.contrast(a, b)
  local la, lb = M.luminance(a), M.luminance(b)
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

function M.isDark(bg)
  return M.luminance(bg) < 0.25
end

-- Moves a picked color towards white (dark background) or black (light
-- background) in 10% steps until it reaches a contrast of 3, so a deliberate
-- color stays recognizable. Falls back to the text color after 8 steps.
function M.readable(hex, ctx)
  local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
  local target = M.isDark(ctx.bg) and 255 or 0
  for step = 0, 8 do
    local t = step / 10
    local candidate = string.format(
      "%02x%02x%02x",
      math.floor(r + (target - r) * t + 0.5),
      math.floor(g + (target - g) * t + 0.5),
      math.floor(b + (target - b) * t + 0.5)
    )
    if M.contrast(candidate, ctx.bg) >= 3 then
      return candidate
    end
  end
  return ctx.fg
end

-- id: an old color id (red, ..., class), "#rrggbb" or "class:TOKEN".
-- ctx: { fg, bg, classHex, classColors }. The old ids fall back to the text color
-- when unreadable, picked colors (hex, class token) are adjusted by M.readable.
function M.colorHex(id, ctx)
  local hex
  if id == "class" then
    hex = ctx.classHex
  elseif M.COLORS[id] then
    hex = M.COLORS[id][M.isDark(ctx.bg) and "dark" or "light"]
  elseif type(id) == "string" then
    local raw = id:match("^#(%x%x%x%x%x%x)$")
    local token = id:match("^class:(%u+)$")
    raw = raw or (token and ((ctx.classColors and ctx.classColors[token]) or M.CLASS_HEX[token]))
    if raw then
      return M.readable(raw:lower(), ctx)
    end
  end
  if not hex or M.contrast(hex, ctx.bg) < 3 then
    return ctx.fg
  end
  return hex
end

function M.headingHex(ctx)
  return M.isDark(ctx.bg) and "e2c08a" or "6b4510"
end

-- Tags and style state -------------------------------------------------------

-- Reads the text between braces. Returns nil when it is no tag (the brace then
-- stays literal text), else { kind, close, value, canon }. `canon` is the
-- normalized spelling that M.sanitize writes back.
function M.readTag(inner)
  local low = inner:lower()
  if low == "/" then
    return { kind = "color", close = true }
  elseif low == "b" or low == "/b" then
    return { kind = "bold", close = low ~= "b" }
  elseif low == "i" or low == "/i" then
    return { kind = "italic", close = low ~= "i" }
  elseif low == "/size" then
    return { kind = "size", close = true }
  elseif low == "~" then
    return { kind = "noop" }
  elseif low == "lb" then
    return { kind = "brace" }
  end
  local n = low:match("^size:(%d+)$")
  if n then
    n = math.max(M.SIZE_MIN, math.min(M.SIZE_MAX, tonumber(n)))
    return { kind = "size", value = n, canon = "{size:" .. n .. "}" }
  end
  local hex = low:match("^#(%x%x%x%x%x%x)$")
  if hex then
    return { kind = "color", value = "#" .. hex, canon = "{#" .. hex .. "}" }
  end
  local token = low:match("^class:(%a+)$")
  token = token and token:upper()
  if token and M.CLASS_HEX[token] then
    return { kind = "color", value = "class:" .. token, canon = "{class:" .. token .. "}" }
  end
  if M.ALIASES[low] then
    return { kind = "legacy", value = M.ALIASES[low] }
  end
  local icon = low:match("^rt([1-8])$")
  if icon then
    return { kind = "icon", value = tonumber(icon) }
  end
end

local function newState()
  return { bold = false, italic = false, sizes = {}, colors = {}, skipSize = 0, skipColor = 0 }
end

-- Applies a style tag. Returns "skip" when the tag is dropped because of the
-- nesting limit (or closes such a dropped tag), else nil.
local function step(st, tag)
  local kind = tag.kind
  if kind == "bold" then
    st.bold = not tag.close
  elseif kind == "italic" then
    st.italic = not tag.close
  elseif kind == "size" or kind == "color" then
    local stack = kind == "size" and st.sizes or st.colors
    local skipKey = kind == "size" and "skipSize" or "skipColor"
    if tag.close then
      if st[skipKey] > 0 then
        st[skipKey] = st[skipKey] - 1
        return "skip"
      end
      stack[#stack] = nil
    elseif #stack >= M.MAX_DEPTH then
      st[skipKey] = st[skipKey] + 1
      return "skip"
    else
      stack[#stack + 1] = kind == "size" and tag.value or { id = tag.value }
    end
  elseif kind == "legacy" then
    local top = st.colors[#st.colors]
    if top and top.legacy then
      top.id = tag.value
    elseif #st.colors < M.MAX_DEPTH then
      st.colors[#st.colors + 1] = { id = tag.value, legacy = true }
    end
  end
end

-- The old named colors end with the line.
local function endLine(st)
  local kept = {}
  for _, c in ipairs(st.colors) do
    if not c.legacy then
      kept[#kept + 1] = c
    end
  end
  st.colors = kept
end

-- Text ----------------------------------------------------------------------

local function truncate(s, n)
  return C.truncateChars(s, n)
end

-- Sanitizer pass over text without pipes or links: normalizes size/hex/class
-- tags and drops tags beyond the nesting limit. `st` runs through the whole text.
local function normalizeTags(run, st)
  if not run:find("[{\n]") then
    return run
  end
  local out, i = {}, 1
  while i <= #run do
    local j = run:find("[{\n]", i)
    if not j then
      out[#out + 1] = run:sub(i)
      break
    end
    if j > i then
      out[#out + 1] = run:sub(i, j - 1)
    end
    if run:byte(j) == 10 then
      endLine(st)
      out[#out + 1] = "\n"
      i = j + 1
    else
      local inner = run:match("^{([^{}\n]*)}", j)
      local tag = inner and M.readTag(inner)
      if tag then
        if not step(st, tag) then
          out[#out + 1] = tag.canon or ("{" .. inner .. "}")
        end
        i = j + #inner + 2
      else
        out[#out + 1] = "{"
        i = j + 1
      end
    end
  end
  return table.concat(out)
end

local function matchLink(s, i)
  local a, b, kind, label = s:find("^|c%x%x%x%x%x%x%x%x|H(%a+):[%w:%-_]*|h%[([^|%]]*)%]|h|r", i)
  if not a then
    a, b, kind, label = s:find("^|H(%a+):[%w:%-_]*|h%[([^|%]]*)%]|h", i)
  end
  if a and M.LINK_TYPES[kind] and b - a + 1 <= M.MAX_LINK and #label <= M.MAX_LABEL then
    return a, b, label
  end
end

-- Idempotent. Drops control characters, keeps only complete item/spell/quest/
-- achievement/enchant links, doubles every other `|`, cuts at `max` characters.
function M.sanitize(text, max)
  max = max or M.MAX_TEXT
  text = tostring(text or ""):gsub("\r\n?", "\n"):gsub("\t", "  ")
  text = text:gsub("[%z\1-\9\11-\31\127]", "")
  local out, used, i = {}, 0, 1
  local st = newState()
  local function push(piece)
    local count = C.charCount(piece)
    if used + count > max then
      return false
    end
    out[#out + 1] = piece
    used = used + count
    return true
  end
  while i <= #text do
    local j = text:find("|", i, true) or (#text + 1)
    if j > i then
      local run = normalizeTags(text:sub(i, j - 1), st)
      if not push(run) then
        local rest = truncate(run, max - used)
        out[#out + 1] = rest
        break
      end
    end
    if j > #text then
      break
    end
    if text:sub(j, j + 1) == "||" then
      if not push("||") then
        break
      end
      i = j + 2
    else
      local a, b = matchLink(text, j)
      if a then
        if not push(text:sub(a, b)) then
          break
        end
        i = b + 1
      else
        if not push("||") then
          break
        end
        i = j + 1
      end
    end
  end
  return table.concat(out)
end

function M.length(text)
  return C.charCount(text or "")
end

-- Parsing -------------------------------------------------------------------

-- Spans: { text, color, bold, italic, size } | { icon = 1..8, ...style } |
-- { link, text = label, ...style }. Style fields are nil when not set, `color`
-- is an old color id, "#rrggbb" or "class:TOKEN". `st` is the style state that
-- carries over from line to line.
local function parseSpans(s, st)
  local out, i = {}, 1
  local function stamp(span)
    local top = st.colors[#st.colors]
    span.color = top and top.id or nil
    span.bold = st.bold or nil
    span.italic = st.italic or nil
    span.size = st.sizes[#st.sizes]
    return span
  end
  local function add(t)
    if t == "" then
      return
    end
    local last = out[#out]
    local probe = stamp({ text = t })
    if
      last
      and last.text
      and not last.link
      and last.color == probe.color
      and last.bold == probe.bold
      and last.italic == probe.italic
      and last.size == probe.size
    then
      last.text = last.text .. t
    else
      out[#out + 1] = probe
    end
  end
  while i <= #s do
    local j = s:find("[{|]", i)
    if not j then
      add(s:sub(i))
      break
    end
    if j > i then
      add(s:sub(i, j - 1))
    end
    if s:sub(j, j) == "{" then
      local inner = s:match("^{([^{}\n]*)}", j)
      local tag = inner and M.readTag(inner)
      if not tag then
        add("{")
        i = j + 1
      else
        if tag.kind == "icon" then
          out[#out + 1] = stamp({ icon = tag.value })
        elseif tag.kind == "brace" then
          add("{")
        elseif tag.kind ~= "noop" then
          step(st, tag)
        end
        i = j + #inner + 2
      end
    elseif s:sub(j, j + 1) == "||" then
      add("||")
      i = j + 2
    else
      local a, b, label = matchLink(s, j)
      if a then
        out[#out + 1] = stamp({ link = s:sub(a, b), text = label })
        i = b + 1
      else
        add("||")
        i = j + 1
      end
    end
  end
  return out
end

-- Splits an alignment tag off the start of one line. Returns "left" | "center" |
-- "right" and the rest of the line (the whole line when there is no tag).
function M.splitAlign(line)
  local word, rest = line:match("^{(%a+)}(.*)$")
  local align = word and M.ALIGN_WORDS[word:lower()]
  if align then
    return align, rest
  end
  return "left", line
end

-- The tag text of an alignment ("" for left).
function M.alignTag(align)
  return (align == "center" or align == "right") and ("{" .. align .. "}") or ""
end

-- Blocks: { kind = "h"|"li"|"check"|"p"|"blank", align, level, checked, spans, line }.
-- align is "left" (no tag), "center" or "right".
function M.parse(text)
  local blocks, n = {}, 0
  local st = newState()
  for raw in ((text or "") .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    local block
    local align, line = M.splitAlign(raw)
    local hashes, rest = line:match("^(#+)%s+(.*)$")
    if hashes and #hashes <= 3 then
      block = { kind = "h", level = #hashes }
    else
      local mark, body = line:match("^%s*%[([ xX])%]%s?(.*)$")
      if mark then
        block, rest = { kind = "check", checked = mark ~= " " }, body
      else
        local item = line:match("^%s*%-%s+(.*)$")
        if item then
          block, rest = { kind = "li" }, item
        elseif line:match("^%s*$") then
          block, rest = { kind = "blank" }, ""
        else
          block, rest = { kind = "p" }, line
        end
      end
    end
    block.line, block.align = n, align
    block.spans = parseSpans(rest, st)
    endLine(st)
    blocks[#blocks + 1] = block
  end
  return blocks
end

-- Flips the checkbox on 1-based `lineNo`; returns the new text or nil.
function M.toggleCheck(text, lineNo)
  local n, changed = 0, nil
  local lines = {}
  for raw in ((text or "") .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    local line = raw
    if n == lineNo then
      local _, rest = M.splitAlign(raw)
      local head, mark, tail = rest:match("^(%s*%[)([ xX])(%].*)$")
      if head then
        line = raw:sub(1, #raw - #rest) .. head .. (mark == " " and "x" or " ") .. tail
        changed = true
      end
    end
    lines[#lines + 1] = line
  end
  if changed then
    return table.concat(lines, "\n")
  end
end

-- Display string for the game: colors as |cff escapes, raid symbols as textures.
-- ctx: { fg, bg, classHex }. Base text color comes from the FontString itself.
function M.toWoW(spans, ctx)
  local out = {}
  for _, span in ipairs(spans) do
    if span.icon then
      out[#out + 1] = "|T" .. M.RAID_ICON .. span.icon .. ":0|t"
    elseif span.link then
      out[#out + 1] = span.link
    elseif span.color then
      out[#out + 1] = "|cff" .. M.colorHex(span.color, ctx) .. span.text .. "|r"
    else
      out[#out + 1] = span.text
    end
  end
  return table.concat(out)
end

-- Plain text for chat/forum: tags removed, links as [Name], `||` as `|`.
function M.plain(text)
  local lines = {}
  for _, b in ipairs(M.parse(text)) do
    local parts = {}
    for _, span in ipairs(b.spans) do
      if span.icon then
        parts[#parts + 1] = "{rt" .. span.icon .. "}"
      elseif span.link then
        parts[#parts + 1] = "[" .. span.text .. "]"
      else
        parts[#parts + 1] = (span.text:gsub("||", "|"))
      end
    end
    local body = table.concat(parts)
    if b.kind == "h" then
      body = string.rep("#", b.level) .. " " .. body
    elseif b.kind == "li" then
      body = "- " .. body
    elseif b.kind == "check" then
      body = (b.checked and "[x] " or "[ ] ") .. body
    end
    lines[#lines + 1] = body
  end
  return table.concat(lines, "\n")
end

-- Editing helpers for the toolbar ---------------------------------------------
-- Positions are 1-based byte offsets. A range (a, b) selects text:sub(a, b);
-- b = a - 1 is an empty range, the caret in front of byte a. Every helper returns
-- the new text and the range to select afterwards (empty = caret).

-- Bytes taken by the first `chars` characters (EditBox positions count characters).
function M.byteOffset(text, chars)
  local count = 0
  for i = 1, #text do
    local byte = text:byte(i)
    if byte < 128 or byte >= 192 then
      if count == chars then
        return i - 1
      end
      count = count + 1
    end
  end
  return #text
end

-- Length of the alignment tag plus the heading/checkbox/list marker that starts the
-- line at `pos`. `tagOnly` stops after the alignment tag.
local function blockPrefixLen(text, pos, tagOnly)
  local full = text:match("^[^\n]*", pos)
  local _, line = M.splitAlign(full)
  local lead = #full - #line
  if tagOnly then
    return lead
  end
  local hashes, space = line:match("^(#+)(%s+)")
  if hashes and #hashes <= 3 then
    return lead + #hashes + #space
  end
  local box = line:match("^%s*%[[ xX]%]%s?") or line:match("^%s*%-%s+")
  return lead + (box and #box or 0)
end

-- Byte offsets where the lines touched by the range (a, b) start.
local function touchedStarts(text, a, b)
  local starts = { (text:sub(1, a - 1):match(".*\n()")) or 1 }
  local pos = starts[1]
  while true do
    local nl = text:find("\n", pos, true)
    if not nl or nl >= b then
      break
    end
    pos = nl + 1
    starts[#starts + 1] = pos
  end
  return starts
end

-- Puts `prefix` ("# ", "- ", "[ ] ") in front of every line the range touches.
-- Blank lines of a multi-line range are skipped. An alignment tag at the start of a
-- line stays in front of the prefix.
function M.applyPrefix(text, a, b, prefix)
  local starts = touchedStarts(text, a, b)
  local out, last, newA, newB = {}, 1, a, b
  for _, s in ipairs(starts) do
    local at = s + blockPrefixLen(text, s, true)
    if #starts == 1 or (text:sub(at, at) ~= "\n" and at <= #text) then
      out[#out + 1] = text:sub(last, at - 1)
      out[#out + 1] = prefix
      last = at
      newA = newA + (at <= a and #prefix or 0)
      newB = newB + (at <= b and #prefix or 0)
    end
  end
  out[#out + 1] = text:sub(last)
  if b < a then
    newB = newA - 1
  end
  return table.concat(out), newA, newB
end

-- Sets the alignment of every line the range touches and replaces a tag that is
-- there. Like the toolbar buttons: when every touched line already has `align`
-- (center or right), they go back to left. Returns nil when nothing changes.
function M.applyAlign(text, a, b, align)
  local starts = touchedStarts(text, a, b)
  local same = align ~= "left"
  for _, s in ipairs(starts) do
    if M.splitAlign(text:match("^[^\n]*", s)) ~= align then
      same = false
    end
  end
  local tag = M.alignTag(same and "left" or align)
  local out, last, newA, newB = {}, 1, a, b
  for _, s in ipairs(starts) do
    local old = blockPrefixLen(text, s, true)
    out[#out + 1] = text:sub(last, s - 1)
    out[#out + 1] = tag
    last = s + old
    newA = newA + (s + old <= a and #tag - old or 0)
    newB = newB + (s + old <= b and #tag - old or 0)
  end
  out[#out + 1] = text:sub(last)
  local new = table.concat(out)
  if new == text then
    return nil
  end
  if b < a then
    newB = newA - 1
  end
  return new, math.min(newA, #new + 1), math.min(newB, #new)
end

-- Wraps the range in a tag pair. Every line of a multi-line range gets its own
-- pair and a marker in front of the text (heading, list, checkbox) stays outside
-- of it, so the old color tags that end at the line break keep working. An empty
-- range inserts an empty pair and puts the caret between the tags.
local function wrapRange(text, a, b, open, close)
  if b < a then
    return text:sub(1, a - 1) .. open .. close .. text:sub(a), a + #open, a + #open - 1
  end
  local out, last, added, newA, newB = {}, 1, 0, nil, nil
  local pos = a
  while pos <= b do
    local nl = text:find("\n", pos, true)
    local stop = (nl and nl <= b) and nl - 1 or b
    local from = pos
    if pos == 1 or text:byte(pos - 1) == 10 then
      from = pos + blockPrefixLen(text, pos)
    end
    if from <= stop then
      out[#out + 1] = text:sub(last, from - 1)
      out[#out + 1] = open
      out[#out + 1] = text:sub(from, stop)
      out[#out + 1] = close
      last = stop + 1
      newA = newA or (from + added + #open)
      newB = stop + added + #open
      added = added + #open + #close
    end
    pos = stop + 2
  end
  if not newA then
    return text, a, b
  end
  out[#out + 1] = text:sub(last)
  return table.concat(out), newA, newB
end

-- Old named color: `word` is the tag word as typed ("rot", "red", "class").
function M.applyColor(text, a, b, word)
  return wrapRange(text, a, b, "{" .. word .. "}", "{/}")
end

-- kind "bold" | "italic" | "size" | "color". `value` is the size in points, or for
-- colors "#rrggbb", "class:TOKEN" or an old tag word. Returns nil for bad input.
function M.applyStyle(text, a, b, kind, value)
  local open, close
  if kind == "bold" then
    open, close = "{b}", "{/b}"
  elseif kind == "italic" then
    open, close = "{i}", "{/i}"
  elseif kind == "size" and tonumber(value) then
    local n = math.max(M.SIZE_MIN, math.min(M.SIZE_MAX, math.floor(tonumber(value))))
    open, close = "{size:" .. n .. "}", "{/size}"
  elseif kind == "color" and type(value) == "string" and value:match("^[#:%w]+$") then
    open, close = "{" .. value .. "}", "{/}"
  end
  if open and (kind ~= "color" or M.readTag(open:sub(2, -2))) then
    return wrapRange(text, a, b, open, close)
  end
end

-- XML text for SimpleHTML (escape & < >; pipes and tags are left alone).
function M.escapeXml(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
