-- Rich note layout and renderer. RL.layout turns a RichModel document into wrapped
-- visual lines of runs with exact geometry (no frames besides the hidden measuring
-- FontStrings), RL.NewView draws such a layout with pooled FontStrings.
--
-- The client has no bold/italic flags and refuses font files from addon folders, so
-- every run is a FontString with its own font file, size and flags. Bold is the base
-- font with THICKOUTLINE, italic is always Skurri (also when the base font is another
-- one, a mix of two typefaces in one line is the price), bold italic is Skurri with
-- THICKOUTLINE. A font file that does not load falls back to the base font (logged
-- once) for measuring and drawing alike.
--
-- Geometry (x to the right, y downwards from the top of the content, in points):
--   layout.lines[i] = { top, height, ascent, startPos, endPos, logical, indent, final,
--                       heading, align, deco, runs = { run... } }
--   indent is the x where the text of the visual line starts: the hanging indent of a
--   list item for left alignment, the aligned start for center and right. Every visual
--   line is aligned on its own inside layout.width, so run.x and deco.x already contain
--   the offset and all geometry below needs no further alignment code.
--   run = { kind = "text"|"icon"|"link", startIndex, endIndex (character indexes of
--           the document, 1-based), x, width, height, ascent, fontKey, text, color,
--           icon, link, label }
--   startPos/endPos are the caret positions at the beginning and end of the line.
local _, ns = ...
local U, N, M, RM, C = ns.U, ns.Notes, ns.Markup, ns.RichModel, ns.MacroCore

local RL = {
  HEADING_EXTRA = { 6, 3, 1 },
  LIST_INDENT = 14,
  CHECK_GAP = 8,
  NEWLINE_WIDTH = 4, -- width of the selection mark at a line break
}
ns.RichLayout = RL

local function esc(s)
  return (s:gsub("|", "||"))
end

-- Fonts ------------------------------------------------------------------------------

function RL.variantOf(style)
  if style.bold then
    return style.italic and "bolditalic" or "bold"
  end
  return style.italic and "italic" or "base"
end

-- The file a variant should use (not checked for existence).
function RL.fontPath(baseKey, variant)
  if variant == "italic" or variant == "bolditalic" then
    return N.FONT_FILES.skurri
  end
  local NW = ns.NoteWindow
  return (NW and NW.fontPath(baseKey)) or N.FONT_FILES[baseKey] or N.FONT_FILES.frizqt
end

-- Joins font flags without duplicates; THICKOUTLINE replaces OUTLINE.
local function mergeFlags(...)
  local set = {}
  for i = 1, select("#", ...) do
    for flag in tostring((select(i, ...)) or ""):gmatch("[^,%s]+") do
      set[flag] = true
    end
  end
  if set.THICKOUTLINE then
    set.OUTLINE = nil
  end
  local out = {}
  for flag in pairs(set) do
    out[#out + 1] = flag
  end
  table.sort(out)
  return table.concat(out, ",")
end
RL.mergeFlags = mergeFlags

-- Path and flags for a base font and variant ("base"|"bold"|"italic"|"bolditalic"),
-- lineFlags (e.g. the heading outline) are merged in. Not checked for existence.
function RL.variantFont(baseKey, variant, lineFlags)
  local thick = variant == "bold" or variant == "bolditalic"
  return RL.fontPath(baseKey, variant), mergeFlags(lineFlags, thick and "THICKOUTLINE" or "")
end

local effective, warned = {}, {}
local probe

local function probeFs()
  probe = probe or UIParent:CreateFontString(nil, "OVERLAY")
  return probe
end

-- The file that really loads for this base font and variant: the wanted file,
-- else the base font, else Friz Quadrata, else the client's standard font.
function RL.effectivePath(baseKey, variant)
  local ck = tostring(baseKey) .. "|" .. variant
  local hit = effective[ck]
  if hit then
    return hit
  end
  local fs = probeFs()
  local want = RL.fontPath(baseKey, variant)
  local path = want
  if not fs:SetFont(want, 12, "") then
    if not warned[want] then
      warned[want] = true
      ns.Log.warn("note font file did not load, using the base font: %s", tostring(want))
    end
    path = variant ~= "base" and RL.fontPath(baseKey, "base") or N.FONT_FILES.frizqt
    if not fs:SetFont(path, 12, "") then
      path = N.FONT_FILES.frizqt
      if not fs:SetFont(path, 12, "") then
        path = rawget(_G, "STANDARD_TEXT_FONT") or path
      end
    end
  end
  effective[ck] = path
  return path
end

-- Sets font file, size and flags on a FontString. The effective path was probed,
-- the fallback chain only runs when the client refuses it anyway.
local function setFont(fs, path, size, flags)
  if fs:SetFont(path, size, flags) then
    return true
  end
  local NW = ns.NoteWindow
  if NW and NW.ApplyFont then
    NW.ApplyFont(fs, "frizqt", size, flags)
  else
    fs:SetFont(N.FONT_FILES.frizqt, size, flags)
  end
  return false
end
RL.setFont = setFont

-- Measuring ----------------------------------------------------------------------------

local env = { cache = {}, count = 0, measurers = {}, heights = {} }
RL.env = env

function RL.resetCaches()
  effective, warned = {}, {}
  env.cache, env.count, env.measurers, env.heights = {}, 0, {}, {}
end

local function measurer(path, size, flags)
  local key = path .. "@" .. size .. "@" .. flags
  local fs = env.measurers[key]
  if not fs then
    fs = UIParent:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
    fs:SetAlpha(0)
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    setFont(fs, path, size, flags)
    env.measurers[key] = fs
  end
  return fs
end

-- Width of the text as drawn at this font. Measured with a trailing sentinel so
-- trailing spaces count whatever the client does with them. Cached per font.
function env:measure(path, size, flags, raw)
  if raw == "" then
    return 0
  end
  local key = path .. "@" .. size .. "@" .. flags
  local bucket = self.cache[key]
  if not bucket then
    bucket = {}
    self.cache[key] = bucket
  end
  local w = bucket[raw]
  if w then
    return w
  end
  local fs = measurer(path, size, flags)
  if not bucket["."] then
    fs:SetText(".")
    bucket["."] = fs:GetStringWidth() or 0
  end
  fs:SetText(esc(raw) .. ".")
  w = (fs:GetStringWidth() or 0) - bucket["."]
  if w <= 0 then
    w = C.charCount(raw) * size * 0.5 -- the client did not measure: estimate
  end
  bucket[raw] = w
  self.count = self.count + 1
  if self.count > 8000 then
    self.cache, self.count = {}, 0
  end
  return w
end

function env:height(path, size, flags)
  local key = path .. "@" .. size .. "@" .. flags
  local h = self.heights[key]
  if not h then
    local fs = measurer(path, size, flags)
    fs:SetText("Ag")
    h = fs:GetStringHeight() or 0
    if h <= 0 then
      h = math.ceil(size * 1.2)
    end
    self.heights[key] = h
  end
  return h
end

-- Layout -----------------------------------------------------------------------------------

local function scaled(px, scale, lo)
  return U.clamp(math.floor(px * scale + 0.5), lo or 8, 48)
end

-- Base size of normal lines and of heading level 1..3 for a note (same rule as the
-- other renderers: scaled by the font scale setting and clamped to 9..48).
function RL.lineSize(baseSize, scale, heading)
  return scaled(baseSize + (heading > 0 and RL.HEADING_EXTRA[heading] or 0), scale, 9)
end

local Layout = {}
Layout.__index = Layout

-- opts: width, fontKey (base font key), baseSize (note text size, unscaled), scale
-- (font scale setting, default 1). Returns the layout object.
function RL.layout(doc, opts)
  local width = math.max(20, opts.width or 300)
  local scale = opts.scale or 1
  local fontKey = opts.fontKey or "frizqt"
  local baseSize = opts.baseSize or N.DEFAULT_STYLE.size
  local chars, styles = doc.chars, doc.styles
  local layout = setmetatable({
    doc = doc,
    rev = doc.rev,
    width = width,
    lines = {},
    logical = {},
    opts = opts,
  }, Layout)
  local gap = math.floor(RL.lineSize(baseSize, scale, 0) * 0.25)
  local y = 0

  for L = 1, doc:lineCount() do
    local attrs = doc.lines[L]
    local heading, align = attrs.heading, attrs.align or "left"
    local lineSize = RL.lineSize(baseSize, scale, heading)
    local flags = heading > 0 and "OUTLINE" or ""
    local firstPos, lastPos = doc:lineRange(L)
    local cs, ce = firstPos + 1, lastPos

    local function specFor(style)
      local variant = RL.variantOf(style)
      local size = style.size and scaled(style.size, scale) or lineSize
      local path = RL.effectivePath(fontKey, variant)
      local _, runFlags = RL.variantFont(fontKey, variant, flags)
      return {
        path = path,
        size = size,
        flags = runFlags,
        fkey = variant .. ":" .. size .. ":" .. runFlags,
        variant = variant,
      }
    end
    local function widthOf(piece, from, to)
      return env:measure(piece.path, piece.size, piece.flags, table.concat(chars, "", from, to))
    end

    local indent, deco = 0, nil
    if attrs.list then
      indent = math.max(RL.LIST_INDENT, math.floor(lineSize * 1.1) + 4)
      deco = { kind = "bullet", x = 2, size = math.max(3, math.floor(lineSize * 0.3)) }
    elseif attrs.check ~= nil then
      local box = lineSize + 2
      indent = lineSize + RL.CHECK_GAP
      deco = { kind = "check", x = 0, size = box, checked = attrs.check, logical = L }
    end
    local avail = math.max(20, width - indent)

    -- Pieces: maximal runs of characters with one style, objects on their own.
    local pieces, i = {}, cs
    while i <= ce do
      local style = styles[i]
      local piece = specFor(style)
      piece.style, piece.from = style, i
      local ch = chars[i]
      if type(ch) == "table" then
        piece.obj, piece.to = ch, i
        piece.h = env:height(piece.path, piece.size, piece.flags)
        if ch.icon then
          piece.w = piece.h
        else
          piece.w = env:measure(piece.path, piece.size, piece.flags, "[" .. (ch.label or "") .. "]")
        end
        i = i + 1
      else
        local j = i
        while j < ce and type(chars[j + 1]) == "string" and styles[j + 1].key == style.key do
          j = j + 1
        end
        piece.to = j
        piece.h = env:height(piece.path, piece.size, piece.flags)
        piece.w = widthOf(piece, i, j)
        i = j + 1
      end
      piece.ascent = math.floor(piece.h * 0.8 + 0.5)
      pieces[#pieces + 1] = piece
    end

    -- Greedy word wrap into visual lines of segments.
    local visuals = {}
    local total = 0
    for _, p in ipairs(pieces) do
      total = total + p.w
    end
    if total <= avail then
      local segs = {}
      for _, p in ipairs(pieces) do
        segs[#segs + 1] = { piece = p, from = p.from, to = p.to, w = p.w, obj = p.obj }
      end
      visuals[1] = { segs = segs }
    else
      local tokens, word = {}, nil
      for _, p in ipairs(pieces) do
        if p.obj then
          word = word or { segs = {}, w = 0 }
          if #word.segs == 0 then
            tokens[#tokens + 1] = word
          end
          word.segs[#word.segs + 1] = { piece = p, from = p.from, to = p.to, w = p.w, obj = p.obj }
          word.w = word.w + p.w
        else
          local k = p.from
          while k <= p.to do
            local isSpace = chars[k] == " "
            local e = k
            while e < p.to and (chars[e + 1] == " ") == isSpace do
              e = e + 1
            end
            local seg = { piece = p, from = k, to = e, w = (k == p.from and e == p.to) and p.w or widthOf(p, k, e) }
            if isSpace then
              word = nil
              tokens[#tokens + 1] = { space = true, segs = { seg }, w = seg.w }
            else
              if not word then
                word = { segs = {}, w = 0 }
                tokens[#tokens + 1] = word
              end
              word.segs[#word.segs + 1] = seg
              word.w = word.w + seg.w
            end
            k = e + 1
          end
        end
      end
      local cur = { segs = {}, x = 0, hasWord = false }
      local function breakLine()
        visuals[#visuals + 1] = cur
        cur = { segs = {}, x = 0, hasWord = false }
      end
      local function put(seg)
        cur.segs[#cur.segs + 1] = seg
        cur.x = cur.x + seg.w
      end
      -- Most characters of seg.from..seg.to that fit into `room`.
      local function fit(piece, from, to, room)
        local lo, hi = 0, to - from + 1
        while lo < hi do
          local mid = math.floor((lo + hi + 1) / 2)
          if widthOf(piece, from, from + mid - 1) <= room then
            lo = mid
          else
            hi = mid - 1
          end
        end
        return lo
      end
      for _, tok in ipairs(tokens) do
        if tok.space then
          put(tok.segs[1])
        else
          if cur.hasWord and cur.x + tok.w > avail then
            breakLine()
          end
          if cur.x + tok.w <= avail then
            for _, sg in ipairs(tok.segs) do
              put(sg)
            end
            cur.hasWord = true
          else
            -- A word wider than the line: cut it by characters.
            for _, sg in ipairs(tok.segs) do
              if sg.obj then
                if cur.hasWord and cur.x + sg.w > avail then
                  breakLine()
                end
                put(sg)
                cur.hasWord = true
              else
                local from = sg.from
                while from <= sg.to do
                  local n = fit(sg.piece, from, sg.to, avail - cur.x)
                  if n == 0 and cur.hasWord then
                    breakLine()
                  else
                    n = math.max(n, 1)
                    local to = from + n - 1
                    put({ piece = sg.piece, from = from, to = to, w = widthOf(sg.piece, from, to) })
                    cur.hasWord = true
                    from = to + 1
                    if from <= sg.to then
                      breakLine()
                    end
                  end
                end
              end
            end
          end
        end
      end
      visuals[#visuals + 1] = cur
    end

    -- Width a visual line takes for alignment: the trailing spaces of a soft-wrapped
    -- line hang over the edge instead of pushing the text off center.
    local function alignedWidth(v, final)
      local w = 0
      for _, sg in ipairs(v.segs) do
        w = w + sg.w
      end
      if not final then
        for k = #v.segs, 1, -1 do
          local sg = v.segs[k]
          if sg.obj or chars[sg.from] ~= " " then
            break
          end
          w = w - sg.w
        end
      end
      return w
    end

    -- Visual lines: merge segments into runs, measure heights, stack vertically.
    local emptyH = env:height(RL.effectivePath(fontKey, "base"), lineSize, flags)
    local firstVisual = #layout.lines + 1
    for vi, v in ipairs(visuals) do
      -- Start of the text (x0) and of the bullet or box (decoX). With center or right
      -- alignment the bullet stays attached to the text of the first visual line and
      -- the hanging indent of the following lines is dropped.
      local x0, decoX = indent, deco and deco.x
      if align ~= "left" then
        local lead = vi == 1 and indent or 0
        local free = math.max(0, width - lead - alignedWidth(v, vi == #visuals))
        local left = align == "center" and math.floor(free / 2) or free
        x0 = left + lead
        decoX = deco and left + deco.x
      end
      local runs, x = {}, x0
      local ascent, descent = 0, 0
      for _, sg in ipairs(v.segs) do
        local p = sg.piece
        local prev = runs[#runs]
        if
          not sg.obj
          and prev
          and prev.kind == "text"
          and prev.fkey == p.fkey
          and prev.color == p.style.color
          and prev.endIndex + 1 == sg.from
        then
          prev.endIndex = sg.to
          prev.width = prev.width + sg.w
        else
          local run = {
            kind = sg.obj and (sg.obj.icon and "icon" or "link") or "text",
            startIndex = sg.from,
            endIndex = sg.to,
            x = x,
            width = sg.w,
            height = p.h,
            ascent = p.ascent,
            fkey = p.fkey,
            path = p.path,
            size = p.size,
            flags = p.flags,
            variant = p.variant,
            color = p.style.color,
          }
          if sg.obj then
            run.icon, run.link, run.label = sg.obj.icon, sg.obj.link, sg.obj.label
          end
          runs[#runs + 1] = run
        end
        x = x + sg.w
        ascent = math.max(ascent, p.ascent)
        descent = math.max(descent, p.h - p.ascent)
      end
      for _, run in ipairs(runs) do
        if run.kind == "text" then
          run.text = table.concat(chars, "", run.startIndex, run.endIndex)
        end
      end
      local height = ascent + descent
      if #runs == 0 then
        ascent = math.floor(emptyH * 0.8 + 0.5)
        height = emptyH
      end
      local line = {
        top = y,
        height = height,
        ascent = ascent,
        logical = L,
        indent = x0,
        heading = heading,
        align = align,
        runs = runs,
        final = vi == #visuals,
        first = vi == 1,
        lineSize = lineSize,
      }
      if #runs > 0 then
        line.startPos, line.endPos = runs[1].startIndex - 1, runs[#runs].endIndex
      else
        line.startPos, line.endPos = firstPos, firstPos
      end
      if vi == 1 and deco then
        local d = { kind = deco.kind, x = decoX, size = deco.size, checked = deco.checked, logical = deco.logical }
        if d.kind == "check" and d.size > line.height then
          local extra = d.size - line.height
          line.ascent = line.ascent + math.floor(extra / 2)
          line.height = d.size
        end
        if d.kind == "check" then
          d.y = math.floor((line.height - d.size) / 2)
        else
          d.y = line.ascent - math.floor(lineSize * 0.35) - math.floor(d.size / 2)
        end
        line.deco = d
      end
      layout.lines[#layout.lines + 1] = line
      y = y + line.height
    end
    layout.logical[L] = { first = firstVisual, last = #layout.lines }
    y = y + gap
  end
  layout.height = y
  return layout
end

-- Geometry ---------------------------------------------------------------------------------

-- Index of the visual line a caret position belongs to. A position on a soft wrap
-- belongs to the line that starts there.
function Layout:lineAt(pos)
  local lines = self.lines
  local lo, hi = 1, #lines
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if lines[mid].startPos <= pos then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return lo
end

local function prefixWidth(self, run, k)
  if k <= 0 then
    return 0
  end
  local n = run.endIndex - run.startIndex + 1
  if k >= n then
    return run.width
  end
  return RL.env:measure(
    run.path,
    run.size,
    run.flags,
    table.concat(self.doc.chars, "", run.startIndex, run.startIndex + k - 1)
  )
end

local function xAt(self, line, pos)
  local runs = line.runs
  if #runs == 0 then
    return line.indent
  end
  for _, r in ipairs(runs) do
    if pos <= r.endIndex then
      if pos <= r.startIndex - 1 then
        return r.x
      end
      local k = pos - (r.startIndex - 1)
      if r.kind == "text" then
        return r.x + prefixWidth(self, r, k)
      end
      return r.x + r.width
    end
  end
  local last = runs[#runs]
  return last.x + last.width
end

-- Caret position -> x, y (top of its line), line height, visual line index.
function Layout:positionToPoint(pos)
  pos = math.max(0, math.min(pos, self.doc:length()))
  local idx = self:lineAt(pos)
  local line = self.lines[idx]
  return xAt(self, line, pos), line.top, line.height, idx
end

-- Point -> nearest caret position.
function Layout:pointToPosition(x, y)
  local lines = self.lines
  local lo, hi = 1, #lines
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if lines[mid].top <= y then
      lo = mid
    else
      hi = mid - 1
    end
  end
  local line = lines[lo]
  local runs = line.runs
  if #runs == 0 or x <= runs[1].x then
    return line.startPos
  end
  for _, r in ipairs(runs) do
    if x < r.x + r.width then
      local rel = x - r.x
      if r.kind ~= "text" then
        return rel < r.width / 2 and r.startIndex - 1 or r.startIndex
      end
      local n = r.endIndex - r.startIndex + 1
      local a, b = 0, n
      while a < b do
        local mid = math.floor((a + b + 1) / 2)
        if prefixWidth(self, r, mid) <= rel then
          a = mid
        else
          b = mid - 1
        end
      end
      if a < n then
        local w0, w1 = prefixWidth(self, r, a), prefixWidth(self, r, a + 1)
        if rel - w0 > (w1 - w0) / 2 then
          a = a + 1
        end
      end
      return r.startIndex - 1 + a
    end
  end
  -- Behind the last run. The end of a soft-wrapped line belongs to the next line.
  if line.final then
    return line.endPos
  end
  return math.max(line.startPos, line.endPos - 1)
end

-- Markup line number of the checkbox at this point, or nil (hit test for the editing
-- surface, where the boxes are not buttons).
function Layout:checkAt(x, y)
  for _, line in ipairs(self.lines) do
    local d = line.deco
    if d and d.kind == "check" then
      local top = line.top + d.y
      if y >= top and y <= top + d.size and x >= d.x and x <= d.x + d.size then
        return d.logical
      end
    end
  end
end

-- Rectangles { x, y, w, h, line } that cover the characters a + 1 .. b, one per
-- visual line. A selected line break adds a short mark at the end of its line.
function Layout:selectionRects(a, b)
  if a > b then
    a, b = b, a
  end
  local out = {}
  if a == b then
    return out
  end
  local first, last = self:lineAt(a), self:lineAt(b)
  for idx = first, last do
    local line = self.lines[idx]
    local lo, hi = math.max(a, line.startPos), math.min(b, line.endPos)
    local x1 = xAt(self, line, lo)
    local x2 = hi > lo and xAt(self, line, hi) or x1
    local mark = line.final and b > line.endPos
    if mark then
      x2 = x2 + RL.NEWLINE_WIDTH
    end
    if x2 > x1 then
      out[#out + 1] = { x = x1, y = line.top, w = x2 - x1, h = line.height, line = idx }
    end
  end
  return out
end

-- Note options -----------------------------------------------------------------------------

local function classColorMap()
  local out = {}
  for token, hex in pairs(ns.Theme.classColors) do
    out[token] = (hex:gsub("#", ""))
  end
  return out
end

-- { fg, bg, classHex, classColors } for Markup.colorHex.
function RL.noteContext(note)
  local classHex
  local ok, _, class = pcall(UnitClass, "player")
  if ok and class and ns.Theme.classColors[class] then
    classHex = (ns.Theme.classColors[class]:gsub("#", ""))
  end
  return { fg = note.style.fg, bg = note.style.bg, classHex = classHex, classColors = classColorMap() }
end

-- Layout options for a note and a content width.
function RL.noteOptions(note, width)
  return {
    width = width,
    fontKey = note.style.font,
    baseSize = note.style.size,
    scale = (ns.db and ns.db.settings and ns.db.settings.fontScale) or 1,
  }
end

-- Renderer ---------------------------------------------------------------------------------

local View = {}
View.__index = View

local function acquire(view, kind, create)
  local list = view.pool[kind]
  local i = view.used[kind] + 1
  view.used[kind] = i
  local obj = list[i]
  if not obj then
    obj = create(view)
    list[i] = obj
  end
  return obj
end

local function createText(view)
  local fs = view.frame:CreateFontString(nil, "OVERLAY")
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetWordWrap(false)
  return fs
end

local function createTexture(view)
  return view.frame:CreateTexture(nil, "ARTWORK")
end

local function createCheck(view)
  local b = CreateFrame("Button", nil, view.frame)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.check = ns.W.CheckMark(b, 12)
  b.check:SetPoint("CENTER")
  b:SetScript(
    "OnClick",
    ns.Wrap("note-check", function(self)
      if view.onToggle then
        view.onToggle(self.line)
      end
    end)
  )
  return b
end

local function createLink(view)
  local b = CreateFrame("Button", nil, view.frame)
  b:SetScript(
    "OnClick",
    ns.Wrap("note-link", function(self, button)
      if self.payload and rawget(_G, "SetItemRef") then
        pcall(rawget(_G, "SetItemRef"), self.payload, self.shown, button)
      end
    end)
  )
  b:SetScript(
    "OnEnter",
    ns.Wrap("note-link-enter", function(self)
      if self.payload then
        ns.W.Tooltip.Show(self, { link = self.payload, anchor = "ANCHOR_CURSOR" })
      end
    end)
  )
  b:SetScript("OnLeave", ns.HideTooltip)
  return b
end

-- Tick drawn on a box that is plain textures (not clickable); a Blizzard check
-- texture is missing in the Forever client.
local function createMark(view)
  return ns.W.CheckMark(view.frame, 12)
end

local KINDS = { text = createText, tex = createTexture, check = createCheck, mark = createMark, link = createLink }

-- Creates the renderer inside `parent`. onToggle(line) is called when a checkbox
-- is clicked (the caller writes the new state back to the note text).
function RL.NewView(parent, onToggle)
  local view = setmetatable({ kind = "rich", onToggle = onToggle, pool = {}, used = {} }, View)
  view.frame = CreateFrame("Frame", nil, parent)
  for kind in pairs(KINDS) do
    view.pool[kind], view.used[kind] = {}, 0
  end
  return view
end

local function rgb(hex)
  return U.hex(hex)
end

-- Draws `layout` (from RL.layout). o: { ctx, fg (hex), interactive (default true), from, to,
-- shadow (a shadow under every text run, for notes on a transparent window) }.
-- Pools are per view: FontStrings, textures and buttons are reused, the ones that
-- are not needed any more are hidden.
function View:Draw(layout, o)
  o = o or {}
  local ctx = o.ctx
  local interactive = o.interactive ~= false
  for kind in pairs(KINDS) do
    self.used[kind] = 0
  end
  local frame = self.frame
  local fr, fg, fb = rgb(o.fg or ctx.fg)
  local hr, hg, hb = rgb(M.headingHex(ctx))
  -- o.from / o.to (content y) draw only the lines in that window, so a long note in a
  -- scrolling editor keeps a small, constant number of FontStrings.
  local lines, first = layout.lines, 1
  if o.from then
    local lo, hi = 1, #lines
    while lo < hi do
      local mid = math.floor((lo + hi) / 2)
      if lines[mid].top + lines[mid].height >= o.from then
        hi = mid
      else
        lo = mid + 1
      end
    end
    first = lo
  end
  for idx = first, #lines do
    local line = lines[idx]
    if o.to and line.top > o.to then
      break
    end
    local top = line.top
    local d = line.deco
    if d and d.kind == "bullet" then
      local t = acquire(self, "tex", KINDS.tex)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", frame, "TOPLEFT", d.x, -(top + d.y))
      t:SetSize(d.size, d.size)
      t:SetTexture("Interface\\Buttons\\WHITE8X8")
      t:SetTexCoord(0, 1, 0, 1)
      t:SetVertexColor(fr, fg, fb, 1)
      t:Show()
    elseif d and d.kind == "check" and interactive then
      local b = acquire(self, "check", createCheck)
      b:SetSize(d.size, d.size)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", frame, "TOPLEFT", d.x, -(top + d.y))
      b.bg:SetColorTexture(fr, fg, fb, 0.2)
      b.check:Fit(d.size + 6)
      b.check:Tint(fr, fg, fb)
      b.check:SetShown(d.checked)
      b.line = d.logical
      b:Show()
    elseif d and d.kind == "check" then
      -- Not clickable (editing surface): the same box as plain textures.
      local bg = acquire(self, "tex", KINDS.tex)
      bg:ClearAllPoints()
      bg:SetPoint("TOPLEFT", frame, "TOPLEFT", d.x, -(top + d.y))
      bg:SetSize(d.size, d.size)
      bg:SetTexture("Interface\\Buttons\\WHITE8X8")
      bg:SetTexCoord(0, 1, 0, 1)
      bg:SetVertexColor(fr, fg, fb, 0.2)
      bg:Show()
      if d.checked then
        local mark = acquire(self, "mark", KINDS.mark)
        mark:Fit(d.size + 6)
        mark:Tint(fr, fg, fb)
        mark:ClearAllPoints()
        mark:SetPoint("TOPLEFT", frame, "TOPLEFT", d.x - 3, -(top + d.y) + 3)
        mark:Show()
      end
    end
    for _, run in ipairs(line.runs) do
      local yoff = top + (line.ascent - run.ascent)
      if run.kind == "icon" then
        local t = acquire(self, "tex", KINDS.tex)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", run.x, -yoff)
        t:SetSize(run.width, run.height)
        t:SetTexture(M.RAID_ICON .. run.icon)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetVertexColor(1, 1, 1, 1)
        t:Show()
      else
        local fs = acquire(self, "text", KINDS.text)
        setFont(fs, run.path, run.size, run.flags)
        local r, g, b = fr, fg, fb
        if run.color then
          r, g, b = rgb(M.colorHex(run.color, ctx))
        elseif line.heading > 0 then
          r, g, b = hr, hg, hb
        end
        fs:SetTextColor(r, g, b, 1)
        -- Pooled FontStrings: always set, so a switched-off shadow does not linger.
        ns.WindowStyle.ApplyShadow(fs, o.shadow, r, g, b)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", run.x, -yoff)
        if run.kind == "link" then
          -- A link without its own color gets the quality color of its item.
          fs:SetText(ns.ItemInfo.ColorLink(run.link))
        else
          fs:SetText(esc(run.text))
        end
        fs:Show()
        if run.kind == "link" and interactive then
          local payload = run.link:match("|H([^|]+)|h")
          if payload and M.LINK_TYPES[payload:match("^(%a+):") or ""] then
            local btn = acquire(self, "link", createLink)
            btn.payload, btn.shown = payload, "[" .. (run.label or "") .. "]"
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", run.x, -top)
            btn:SetSize(math.max(1, run.width), math.max(1, line.height))
            btn:Show()
          end
        end
      end
    end
  end
  for kind, list in pairs(self.pool) do
    for i = self.used[kind] + 1, #list do
      list[i]:Hide()
    end
  end
  frame:SetSize(layout.width, math.max(layout.height, 1))
  self.layout = layout
  return layout.height
end

-- Same call as the other note renderers: draws the note at `width`, returns the
-- content height. The parsed document and the layout are cached while text, width
-- and font settings stay the same. look = { shadow = bool, bg = hex } is how the
-- window shows the note (shadow policy, effective background for the color contrast);
-- neither changes the layout.
function View:Set(note, width, look)
  local opts = RL.noteOptions(note, width)
  local key = table.concat({ note.text, width, opts.fontKey, opts.baseSize, opts.scale }, "\1")
  if self.cacheKey ~= key then
    if self.docText ~= note.text then
      self.doc, self.docText = RM.fromMarkup(note.text), note.text
    end
    opts.width = width
    self.cached = RL.layout(self.doc, opts)
    self.cacheKey = key
  end
  local ctx = RL.noteContext(note)
  if look and look.bg then
    ctx.bg = look.bg
  end
  return self:Draw(self.cached, { ctx = ctx, fg = note.style.fg, shadow = look and look.shadow })
end

-- Number of FontStrings, textures and buttons this view has created (for tests and
-- performance notes).
function View:Counts()
  local out = {}
  for kind, list in pairs(self.pool) do
    out[kind] = #list
  end
  return out
end
