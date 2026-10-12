-- WYSIWYG note editor. The player types into the finished, formatted text; the markup
-- stays the stored format (RichModel converts both ways). Nothing here is an EditBox
-- the player sees:
--   * RichLayout draws the document (a pooled view, only the visible lines), the caret
--     and the selection are our own textures.
--   * One hidden EditBox (1x1, alpha 0) owns the keyboard focus. Navigation, deleting,
--     Enter and the Ctrl shortcuts arrive through its OnKeyDown and are handled here.
--     Everything the client turns into text (letters, umlauts, dead keys, pasted text)
--     arrives through OnTextChanged: the box is kept empty, so its whole text is the new
--     input, which is inserted with the style at the caret and wiped again.
--   * Copy and cut put the selected plain text into the hidden box and highlight it, so
--     the client's own Ctrl+C picks it up. A right-click menu offers "copy as text"
--     (opens the copy dialog) as the way around that.
--
--   local ed = RE.New(parent, { getNote, onChange(ed), onState(state, ed), onSave(),
--                               onFocus(ed), onBroken(ed) })
--   ed.frame   ed:SetValue(markup, caret)   ed:GetValue() -> markup   ed:Handlers()
--   ed:Focus() ed:Blur() ed:HasFocus() ed:Restyle() ed:InsertLink(link) ed:InsertObject(obj)
--   zoom: ed:SetZoom(percent) scales the text (RE.ZOOM_MIN..RE.ZOOM_MAX), Ctrl+wheel and
--   Ctrl +, -, 0 reach it through opts.onCommand("zoomIn" | "zoomOut" | "zoomReset");
--   Ctrl+N asks for opts.onCommand("new").
-- RE.NewNoteEditor wraps the editor, the code editor and the toolbar into the control
-- the note window and the Notes page use (mode toggle "Normal" / "Code"). The menu bar
-- and the status bar around it live in Modules/NoteChrome.lua.
local _, ns = ...
local W, L, Theme, U, N, M, C = ns.W, ns.L, ns.Theme, ns.U, ns.Notes, ns.Markup, ns.MacroCore
local RM, RL, RT = ns.RichModel, ns.RichLayout, ns.RichToolbar

local RE = {
  PAD = 4, -- inner margin of the text area
  MARGIN_X = 12, -- space between the frame and the text area
  MARGIN_Y = 8,
  CARET_W = 2,
  BLINK = 0.53, -- seconds per caret phase
  CLICK_GAP = 0.4, -- seconds between the clicks of a double or triple click
  CLICK_DIST = 4, -- pixels the pointer may move between them
  HINT_SECONDS = 3,
  MAX_FAILURES = 3, -- errors in the input handlers before the owner falls back to code
  HOVER_STEP = 0.06, -- seconds between link hit tests
  BLIND_INPUTS = 3, -- text inputs without any key event before the editor gives up
  ZOOM_MIN = 50, -- percent
  ZOOM_MAX = 300,
  ZOOM_STEP = 10,
  ZOOM_DEFAULT = 100,
}
ns.RichEditor = RE

ns.AddLocale("enUS", {
  ["notes.edit.limit"] = "Limit of %d characters reached, nothing added.",
  ["notes.rich.copyTitle"] = "Copy text",
  ["notes.rich.copyHint"] = "Plain text, Ctrl+C copies it.",
  ["notes.rich.menuCopy"] = "Copy as text",
  ["notes.rich.menuAll"] = "Select all",
  ["notes.rich.fallback"] = "Formatted editor unavailable, code view in use.",
})

ns.AddLocale("deDE", {
  ["notes.edit.limit"] = "Limit von %d Zeichen erreicht, nichts hinzugefügt.",
  ["notes.rich.copyTitle"] = "Text kopieren",
  ["notes.rich.copyHint"] = "Reiner Text, Strg+C kopiert ihn.",
  ["notes.rich.menuCopy"] = "Text kopieren",
  ["notes.rich.menuAll"] = "Alles markieren",
  ["notes.rich.fallback"] = "Formatierter Editor nicht verfügbar, Code-Ansicht aktiv.",
})

local clamp = U.clamp
local MARKER = "\238\128\128" -- U+E000, marks the caret while converting to markup

-- Text helpers ------------------------------------------------------------------------

-- Keeps well-formed UTF-8 characters and line breaks, drops control characters and
-- broken byte sequences.
local function cleanInput(text)
  text = tostring(text or ""):gsub("\r\n?", "\n")
  local out = {}
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local b = ch:byte(1)
    local need = b < 128 and 1 or (b < 224 and 2 or (b < 240 and 3 or 4))
    if #ch == need and (b >= 128 or b == 10 or (b >= 32 and b ~= 127)) then
      out[#out + 1] = ch
    end
  end
  return table.concat(out)
end
RE.cleanInput = cleanInput

-- Character classes for double click and Ctrl+arrow word jumps.
local function charClass(ch)
  if ch == nil then
    return nil
  elseif type(ch) == "table" then
    return "word"
  elseif ch == "\n" then
    return "break"
  elseif ch == " " then
    return "space"
  elseif #ch > 1 or ch:match("^[%w_]$") then
    return "word"
  end
  return "punct"
end

-- Caret position after the next word (like Ctrl+Right in a text editor).
local function wordRight(doc, pos)
  local chars, n = doc.chars, doc:length()
  local i = pos + 1
  local c = charClass(chars[i])
  if c == "break" then
    return pos + 1
  end
  if c and c ~= "space" then
    while i <= n and charClass(chars[i]) == c do
      i = i + 1
    end
  end
  while i <= n and charClass(chars[i]) == "space" do
    i = i + 1
  end
  return i - 1
end

-- Caret position at the start of the word in front of the caret.
local function wordLeft(doc, pos)
  local chars = doc.chars
  local i = pos
  while i >= 1 and charClass(chars[i]) == "space" do
    i = i - 1
  end
  if i >= 1 and charClass(chars[i]) == "break" then
    return i - 1
  end
  local c = charClass(chars[i])
  if c then
    while i >= 1 and charClass(chars[i]) == c do
      i = i - 1
    end
  end
  return i
end
RE.wordLeft, RE.wordRight = wordLeft, wordRight

local MODIFIER_KEYS = {
  LSHIFT = true,
  RSHIFT = true,
  LCTRL = true,
  RCTRL = true,
  LALT = true,
  RALT = true,
  LMETA = true,
  RMETA = true,
  CAPSLOCK = true,
  ESCAPE = true,
}

-- Ctrl (Cmd on a Mac), Shift, Alt as booleans.
local function modifiers()
  local ctrl = IsControlKeyDown() and true or false
  local meta = rawget(_G, "IsMetaKeyDown")
  if not ctrl and meta then
    ctrl = meta() and true or false
  end
  return ctrl, IsShiftKeyDown() and true or false, IsAltKeyDown() and true or false
end

-- Context menu ------------------------------------------------------------------------

local menu

function RE.CloseMenu()
  if menu and menu.frame:IsShown() then
    menu.frame:Hide()
    menu.blocker:Hide()
    menu.owner = nil
    return true
  end
  return false
end

local function buildMenu()
  local m = {}
  m.blocker = CreateFrame("Button", nil, UIParent)
  m.blocker:SetAllPoints(UIParent)
  m.blocker:SetFrameStrata("FULLSCREEN")
  m.blocker:SetScript("OnClick", RE.CloseMenu)
  m.blocker:Hide()
  m.frame = CreateFrame("Frame", "FGRichMenu", UIParent)
  m.frame:SetFrameStrata("FULLSCREEN_DIALOG")
  m.frame:SetClampedToScreen(true)
  m.frame:SetSize(170, 46)
  m.frame:EnableMouse(true)
  W.Fill(m.frame, "surface", 1)
  W.Border(m.frame, "accentDim", 1)
  m.rows = {}
  local function row(i, key, onClick)
    local r = CreateFrame("Button", nil, m.frame)
    r:SetHeight(22)
    r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 22)
    r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 22)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0)
    r.text = W.Text(r, { role = "ui" })
    r.text:SetPoint("LEFT", 8, 0)
    r.key = key
    r:SetScript("OnEnter", function()
      r.hl:SetColorTexture(1, 1, 1, 0.08)
    end)
    r:SetScript("OnLeave", function()
      r.hl:SetColorTexture(1, 1, 1, 0)
    end)
    r:SetScript(
      "OnClick",
      ns.Wrap("rich-menu", function()
        local owner = m.owner
        RE.CloseMenu()
        if owner then
          onClick(owner)
        end
      end)
    )
    ns.Focus.register(r, function(self)
      self:Click()
    end)
    m.rows[i] = r
  end
  row(1, "notes.rich.menuCopy", function(ed)
    ed:OpenCopyDialog()
  end)
  row(2, "notes.rich.menuAll", function(ed)
    ed:Focus()
    ed:SelectAll()
  end)
  m.frame:Hide()
  return m
end

-- Editor ------------------------------------------------------------------------------------

local Editor = {}
Editor.__index = Editor

local function newTexture(layer, parent)
  local t = parent:CreateTexture(nil, layer)
  t:SetTexture("Interface\\Buttons\\WHITE8X8")
  return t
end

function RE.New(parent, opts)
  opts = opts or {}
  local ed = setmetatable({
    opts = opts,
    caret = 0,
    anchor = 0,
    serial = 0,
    failures = 0,
    keyEvents = 0,
    textInputs = 0,
    selTex = {},
    blink = 0,
    zoom = RE.ZOOM_DEFAULT,
  }, Editor)
  local PAD = RE.PAD

  local frame = CreateFrame("Frame", nil, parent)
  ed.frame = frame
  ed.bg = frame:CreateTexture(nil, "BACKGROUND")
  ed.bg:SetAllPoints()
  ed.border = W.Border(frame, "white", 0.25)

  local area = W.ScrollArea(frame)
  area:SetPoint("TOPLEFT", RE.MARGIN_X, -RE.MARGIN_Y)
  area:SetPoint("BOTTOMRIGHT", -4, RE.MARGIN_Y)
  ed.area = area
  local content = area.content
  ed.content = content

  -- Layers by frame level: selection under the text, caret over it.
  local base = content:GetFrameLevel()
  ed.selLayer = CreateFrame("Frame", nil, content)
  ed.selLayer:SetAllPoints(content)
  ed.selLayer:SetFrameLevel(base + 1)
  ed.view = RL.NewView(content, nil)
  ed.view.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD)
  ed.view.frame:SetFrameLevel(base + 2)
  ed.caretLayer = CreateFrame("Frame", nil, content)
  ed.caretLayer:SetAllPoints(content)
  ed.caretLayer:SetFrameLevel(base + 3)
  ed.caretTex = newTexture("OVERLAY", ed.caretLayer)
  ed.caretTex:Hide()

  -- The hint sits on its own frame so it is drawn over the text.
  local overlay = CreateFrame("Frame", nil, frame)
  overlay:SetAllPoints(frame)
  overlay:SetFrameLevel(frame:GetFrameLevel() + 20)
  ed.hintBg = newTexture("OVERLAY", overlay)
  ed.hintBg:SetColorTexture(0, 0, 0, 0.75)
  ed.hint = W.Text(overlay, { role = "micro", color = "accent2", justify = "RIGHT" })
  ed.hint:SetPoint("BOTTOMRIGHT", -8, 6)
  ed.hintBg:SetPoint("TOPLEFT", ed.hint, "TOPLEFT", -4, 2)
  ed.hintBg:SetPoint("BOTTOMRIGHT", ed.hint, "BOTTOMRIGHT", 4, -2)
  ed.hint:Hide()
  ed.hintBg:Hide()

  -- The hidden input box. Mouse off: clicks reach the text area behind it.
  local hb = CreateFrame("EditBox", nil, frame)
  ed.hb = hb
  hb:SetSize(1, 1)
  hb:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  hb:SetAlpha(0)
  hb:SetAutoFocus(false)
  hb:SetMultiLine(true)
  hb:SetMaxLetters(N.MAX_TEXT)
  hb:EnableMouse(false)
  ns.Bind(hb, function()
    Theme.applyFont(hb, "ui", "body")
  end)

  ed:BindScripts()
  ed:SetValue("")

  ns.Focus.register(frame, function()
    ed:Focus()
  end)
  return ed
end

-- Appearance --------------------------------------------------------------------------

function Editor:Note()
  local note = self.opts.getNote and self.opts.getNote()
  return note or { style = N.DEFAULT_STYLE }
end

function Editor:LayoutWidth()
  return math.max(40, math.floor(self.area:GetWidth() - 12 - 2 * RE.PAD))
end

-- The note's colors and font settings as the renderer takes them.
function Editor:Appearance()
  local note = self:Note()
  local st = note.style
  local opts = RL.noteOptions(note, self:LayoutWidth())
  opts.scale = opts.scale * self.zoom / 100
  local key = table.concat({ opts.width, opts.fontKey, opts.baseSize, opts.scale, st.fg, st.bg }, "|")
  if self.styleKey ~= key then
    self.styleKey = key
    self.ctx = RL.noteContext(note)
    local r, g, b = U.hex(st.bg)
    self.bg:SetColorTexture(r, g, b, 1)
    local fr, fg, fb = U.hex(st.fg)
    self.caretTex:SetColorTexture(fr, fg, fb, 1)
  end
  return opts, note, key
end

-- Re-reads the note's style (font, size, colors) and redraws. The view stays where
-- the player scrolled it.
function Editor:Restyle()
  self.styleKey = nil
  self:Paint()
  self:SyncState()
end

-- Text zoom in percent (the layout scale option). Returns false when nothing changed.
function Editor:SetZoom(percent)
  percent = clamp(math.floor((tonumber(percent) or RE.ZOOM_DEFAULT) + 0.5), RE.ZOOM_MIN, RE.ZOOM_MAX)
  if percent == self.zoom then
    return false
  end
  self.zoom = percent
  self:Refresh()
  return true
end

-- Caret line and column, both 1-based; lines are the stored lines (a wrapped line is
-- still one line) and the column counts characters from the start of its line.
function Editor:Position()
  local doc = self.doc
  local line = doc:lineOf(self.caret)
  return line, self.caret - doc:lineStarts()[line] + 1
end

-- Characters in the text (line breaks and symbols count as one) and in the selection.
function Editor:Counts()
  local a, b = self:Range()
  return self.doc:length(), b - a
end

function Editor:Layout()
  local opts, _, key = self:Appearance()
  local layoutKey = self.serial .. ":" .. self.doc.rev .. ":" .. key
  if self.layoutKey ~= layoutKey then
    self.layout = RL.layout(self.doc, opts)
    self.layoutKey = layoutKey
  end
  return self.layout
end

-- Content height follows the layout, never below the visible height so a click under
-- the last line still lands in the text area.
function Editor:Fit()
  local layout = self:Layout()
  local h = math.max(layout.height + 2 * RE.PAD, self.area:GetHeight() or 0)
  if self.fitHeight ~= h or self.fitKey ~= self.layoutKey then
    self.fitHeight, self.fitKey = h, self.layoutKey
    self.area:SetContentHeight(h)
  end
  return layout
end

-- Drawing -----------------------------------------------------------------------------

function Editor:PaintText(layout)
  local area = self.area
  local vh = math.max(area:GetHeight() or 0, 1)
  local top = area:GetVerticalScroll() - RE.PAD
  local bottom = top + vh
  if self.drawKey ~= self.layoutKey or not self.drawFrom or top < self.drawFrom or bottom > self.drawTo then
    self.drawKey, self.drawFrom, self.drawTo = self.layoutKey, top - vh, bottom + vh
    local _, note = self:Appearance()
    self.view:Draw(layout, {
      ctx = self.ctx,
      fg = note.style.fg,
      interactive = false,
      from = self.drawFrom,
      to = self.drawTo,
    })
  end
  return top, bottom
end

function Editor:PaintSelection(layout, top, bottom)
  local a, b = self:Range()
  local key = self.layoutKey .. ":" .. a .. ":" .. b
  if self.selKey ~= key then
    self.selKey = key
    self.selRects = a < b and layout:selectionRects(a, b) or {}
  end
  local used = 0
  local alpha = self.focused and 0.5 or 0.28
  for _, r in ipairs(self.selRects) do
    if r.y + r.h >= top and r.y <= bottom then
      used = used + 1
      local t = self.selTex[used]
      if not t then
        t = newTexture("ARTWORK", self.selLayer)
        self.selTex[used] = t
      end
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self.selLayer, "TOPLEFT", RE.PAD + r.x, -(RE.PAD + r.y))
      t:SetSize(r.w, r.h)
      t:SetVertexColor(0.25, 0.5, 0.95, alpha)
      t:Show()
    end
  end
  for i = used + 1, #self.selTex do
    self.selTex[i]:Hide()
  end
  self.selShown = used
end

function Editor:PaintCaret(layout)
  local x, y, h = layout:positionToPoint(self.caret)
  self.caretTex:ClearAllPoints()
  self.caretTex:SetPoint("TOPLEFT", self.caretLayer, "TOPLEFT", RE.PAD + x, -(RE.PAD + y))
  self.caretTex:SetSize(RE.CARET_W, h)
  self.blink, self.blinkOn = 0, true
  self.caretTex:SetShown(self.focused == true)
end

-- Scrolls just far enough to show the caret.
function Editor:Reveal()
  local layout = self:Fit()
  local _, y, h = layout:positionToPoint(self.caret)
  local area = self.area
  local v, vh = area:GetVerticalScroll(), area:GetHeight()
  local top, bottom = y + RE.PAD, y + h + RE.PAD
  if top < v then
    area:ScrollTo(math.max(0, top - RE.PAD))
  elseif bottom > v + vh then
    area:ScrollTo(bottom - vh + RE.PAD)
  end
end

-- Redraws everything that depends on text, scroll position, selection and caret.
function Editor:Paint()
  if self.painting then
    return
  end
  self.painting = true
  local ok, err = pcall(function()
    local layout = self:Fit()
    local top, bottom = self:PaintText(layout)
    self:PaintSelection(layout, top, bottom)
    self:PaintCaret(layout)
  end)
  self.painting = false
  if not ok then
    error(err, 0)
  end
end

-- Text changed, caret moved or the view needs a refresh.
function Editor:Refresh()
  self:Reveal()
  self:Paint()
  self:SyncState()
end

-- A model edit happened: refresh and tell the owner.
function Editor:Changed()
  self.markupRev = nil
  self:Refresh()
  if self.opts.onChange then
    self.opts.onChange(self)
  end
end

-- Document and selection ---------------------------------------------------------------

-- markup: stored note text. caret: character position in the formatted text.
function Editor:SetValue(markup, caret)
  self.doc = RM.fromMarkup(M.sanitize(markup or ""), { maxLength = N.MAX_TEXT })
  self.serial = self.serial + 1
  self.markupRev, self.layoutKey, self.selKey, self.drawKey = nil, nil, nil, nil
  self.caret = clamp(caret or 0, 0, self.doc:length())
  self.anchor = self.caret
  self.pending, self.goalX = nil, nil
  self.area:ScrollTo(0)
  self:Refresh()
end

function Editor:GetValue()
  if self.markupRev ~= self.serial .. ":" .. self.doc.rev then
    self.markup = RM.toMarkup(self.doc)
    self.markupRev = self.serial .. ":" .. self.doc.rev
  end
  return self.markup
end

function Editor:Range()
  if self.anchor > self.caret then
    return self.caret, self.anchor
  end
  return self.anchor, self.caret
end

function Editor:HasSelection()
  return self.anchor ~= self.caret
end

function Editor:SelectedText()
  local a, b = self:Range()
  return self.doc:rangeText(a, b)
end

-- Moves the caret (and with `extend` only the caret, so the anchor stays). A move
-- ends the typing run for undo and drops a pending style.
function Editor:Move(pos, extend, keepGoal)
  pos = clamp(math.floor(pos), 0, self.doc:length())
  local moved = pos ~= self.caret or (not extend and self.anchor ~= self.caret)
  self.caret = pos
  if not extend then
    self.anchor = pos
  end
  if not keepGoal then
    self.goalX = nil
  end
  if moved then
    self.pending = nil
    self.doc:breakUndo()
  end
  self:Refresh()
end

function Editor:SelectAll()
  self.anchor = 0
  self:Move(self.doc:length(), true)
end

-- After an edit: caret (and no selection) at `pos`.
function Editor:Edited(pos, keepPending)
  if pos then
    self.caret = clamp(pos, 0, self.doc:length())
    self.anchor = self.caret
  else
    self.caret = clamp(self.caret, 0, self.doc:length())
    self.anchor = clamp(self.anchor, 0, self.doc:length())
  end
  self.goalX = nil
  if not keepPending then
    self.pending = nil
  end
  self:Changed()
end

-- Runs a model edit. A refusal because of the length limit shows a hint (the model
-- restores itself and bumps the revision, an edit that changes nothing does not).
function Editor:Run(fn, ...)
  local doc = self.doc
  local before = doc.rev
  local result = fn(...)
  if result == false and doc.rev ~= before then
    self:Hint("notes.edit.limit", N.MAX_TEXT)
  end
  return result
end

function Editor:Hint(key, ...)
  local text = string.format(L[key], ...)
  self.lastHint = key
  self.hint:SetText(text)
  self.hint:Show()
  self.hintBg:Show()
  self.hintToken = (self.hintToken or 0) + 1
  local token = self.hintToken
  C_Timer.After(RE.HINT_SECONDS, function()
    if self.hintToken == token then
      self.hint:Hide()
      self.hintBg:Hide()
    end
  end)
end

-- Typing and pasting -----------------------------------------------------------------

-- Inserts typed or pasted text at the caret with the pending style (default: the style
-- at the caret); a selection is replaced. Short typed input goes in character by
-- character so a typing run is one undo step.
function Editor:TypeText(text)
  text = cleanInput(text)
  if text == "" then
    return false
  end
  local doc = self.doc
  local a, b = self:Range()
  local style = self.pending
  local pos = a
  if a < b then
    style = style or doc:getStyleAt(a + 1)
    local r = self:Run(doc.replace, doc, a, b, text, style)
    if r == false then
      return false
    end
    pos = r
  else
    local chars = RM.splitChars(text)
    if #chars <= 3 and not text:find("\n", 1, true) then
      for _, ch in ipairs(chars) do
        local r = self:Run(doc.insertText, doc, pos, ch, style)
        if r == false then
          break
        end
        pos = r
      end
    else
      local r = self:Run(doc.insertText, doc, pos, text, style)
      if r ~= false then
        pos = r
      end
    end
  end
  if pos == a and a == b then
    return false
  end
  self:Edited(pos, true)
  return true
end

-- Pastes what the last copy or cut inside a note editor kept (with its formatting).
function Editor:PasteClip()
  local clip = RE.clip
  return clip ~= nil and clip.markup ~= "" and self:PasteMarkup(clip.markup)
end

function Editor:PasteMarkup(markup)
  local a, b = self:Range()
  local r = self:Run(self.doc.insertMarkup, self.doc, a, markup, b)
  if r == false then
    return false
  end
  self:Edited(r)
  return true
end

-- Enter: replaces a selection, continues lists and checkboxes (the model decides).
function Editor:Enter()
  local doc = self.doc
  local a, b = self:Range()
  local pos = a
  if a < b then
    if self:Run(doc.deleteRange, doc, a, b) == false then
      return false
    end
  end
  local r = self:Run(doc.enter, doc, pos)
  if r == false then
    if a < b then
      self:Edited(pos)
    end
    return false
  end
  self:Edited(r, true)
  return true
end

-- The text of the hidden box is the input (see the header). OnTextChanged(user) is
-- true for typing and pasting, false for our own SetText calls.
function Editor:OnHiddenText(user)
  if self.silent or not user then
    return
  end
  local text = self.hb:GetText()
  self:Neutral()
  if text == "" then
    return
  end
  self:Input(text)
  -- Typing arrives but no key down ever did: arrows, Backspace and the shortcuts cannot
  -- reach us, so this editor is no use. Hand over to the code view.
  self.textInputs = self.textInputs + 1
  if self.keyEvents == 0 and self.textInputs >= RE.BLIND_INPUTS and not self.broken then
    self.broken = true
    ns.Log.warn("rich editor receives text but no key events, falling back to the code view")
    if self.opts.onBroken then
      self.opts.onBroken(self)
    end
  end
end

-- One non-empty input from the hidden box: Enter, a paste of our own copy, or text.
function Editor:Input(text)
  if text == "\n" then
    -- The key down handler already did the Enter; without it (no OnKeyDown for Enter) this does.
    local now = RM.clock()
    local seen = self.enterAt and now - self.enterAt < 0.5
    self.enterAt = nil
    if not seen then
      self.enterFallbackAt = now
      self:Enter()
    end
    return
  end
  if text == "||" then
    -- [Probe] some clients hand a typed pipe over escaped.
    text = "|"
  end
  local clip = RE.clip
  if clip and clip.text ~= "" and clip.text == cleanInput(text) then
    self:PasteMarkup(clip.markup)
  else
    self:TypeText(text)
  end
end

-- Back to the empty box that every input is diffed against.
function Editor:Neutral()
  self.copyArmed = false
  self.silent = true
  self.hb:SetText("")
  self.silent = false
end

-- Clipboard -------------------------------------------------------------------------------

-- [Probe] Puts the text into the hidden box and highlights it inside OnKeyDown, so the
-- client's own Ctrl+C / Ctrl+X copies it right after the handler returns.
function Editor:ArmCopy(text)
  self.silent = true
  self.hb:SetText(text)
  self.hb:HighlightText()
  self.silent = false
  self.copyArmed = true
  C_Timer.After(0.6, function()
    if self.copyArmed then
      self:Neutral()
    end
  end)
end

-- Markup of the characters a + 1 .. b (inline formatting, symbols, links, line breaks).
function Editor:Fragment(a, b)
  local doc = self.doc
  local chars, styles, lines = {}, {}, { { heading = 0, list = false } }
  for i = a + 1, b do
    chars[#chars + 1], styles[#styles + 1] = doc.chars[i], doc.styles[i]
    if doc.chars[i] == "\n" then
      lines[#lines + 1] = { heading = 0, list = false }
    end
  end
  local tmp = RM.new()
  tmp.chars, tmp.styles, tmp.lines = chars, styles, lines
  return RM.toMarkup(tmp)
end

function Editor:Copy(cut)
  local a, b = self:Range()
  if a == b then
    return false
  end
  local plain = self.doc:rangeText(a, b)
  -- What the client's clipboard carries is plain text. Pasting that same text back into
  -- an editor brings the formatting, symbols and links with it.
  RE.clip = { text = cleanInput(plain), markup = self:Fragment(a, b) }
  self:ArmCopy(plain)
  if cut then
    if self:Run(self.doc.deleteRange, self.doc, a, b) ~= false then
      self:Edited(a)
    end
  end
  return true
end

-- The fallback to the native copy: the copy dialog with the selection (or the whole
-- note) as plain text.
function Editor:OpenCopyDialog()
  local text = self:HasSelection() and self:SelectedText() or M.plain(self:GetValue())
  ns.Dialogs.Copy("notes.rich.copyTitle", text, "notes.rich.copyHint")
end

function Editor:OpenMenu()
  menu = menu or buildMenu()
  menu.owner = self
  for _, r in ipairs(menu.rows) do
    r.text:SetText(L[r.key])
  end
  local cx, cy = 0, 0
  if GetCursorPosition then
    cx, cy = GetCursorPosition()
  end
  local s = UIParent:GetEffectiveScale()
  menu.frame:ClearAllPoints()
  menu.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / s, cy / s)
  menu.blocker:Show()
  menu.frame:Show()
end

-- Formatting -----------------------------------------------------------------------------

-- Lines the selection touches (a selection that ends at the start of a line leaves
-- that line out, like the toolbar state does).
function Editor:LineSpan()
  local a, b = self:Range()
  local doc = self.doc
  local ln1, ln2 = doc:lineOf(a), doc:lineOf(b)
  if b > a and ln2 > ln1 and b == doc:lineStarts()[ln2] then
    ln2 = ln2 - 1
  end
  return ln1, ln2
end

-- Bold / italic: a selection toggles like Word, an empty selection sets a pending
-- style for what is typed next.
function Editor:ToggleFlag(key)
  local doc = self.doc
  local a, b = self:Range()
  if a < b then
    if self:Run(doc.toggleStyle, doc, a, b, key) then
      self:Changed()
    end
  else
    local cur = self.pending or doc:getStyleAt(self.caret)
    self.pending = RM.withStyle(cur, key, not cur[key])
    doc:breakUndo()
    self:Refresh()
  end
end

-- Size / color: value nil resets to the default.
function Editor:SetFormat(key, value)
  local doc = self.doc
  local a, b = self:Range()
  if a < b then
    if self:Run(doc.setStyle, doc, a, b, key, value) then
      self:Changed()
    end
  else
    self.pending = RM.withStyle(self.pending or doc:getStyleAt(self.caret), key, value)
    doc:breakUndo()
    self:Refresh()
  end
end

-- Heading: `level` (0 to 3) sets that level, without it the level cycles 1, 2, 3, off.
-- The other kinds toggle. For "align" `level` is "left", "center" or "right": the active
-- one goes back to left.
function Editor:SetBlock(kind, level)
  local doc = self.doc
  local ln1, ln2 = self:LineSpan()
  local ok
  if kind == "heading" then
    local cur = doc:getBlockForLines(ln1, ln2).heading
    cur = type(cur) == "number" and cur or 0
    ok = self:Run(doc.setBlock, doc, ln1, ln2, { heading = level or (cur + 1) % 4 }, self.caret)
  else
    ok = self:Run(doc.toggleBlock, doc, ln1, ln2, kind, level, self.caret)
  end
  if ok then
    self:Changed()
  end
end

function Editor:ToggleCheck(line)
  local l = self.doc.lines[line]
  if l and l.check ~= nil then
    if self:Run(self.doc.setBlock, self.doc, line, line, { check = not l.check }, self.caret) then
      self:Changed()
    end
  end
end

function Editor:InsertObject(obj)
  local doc = self.doc
  local a, b = self:Range()
  if a < b then
    if self:Run(doc.deleteRange, doc, a, b) == false then
      return false
    end
  end
  local r = self:Run(doc.insertObject, doc, a, obj, self.pending)
  if r == false then
    self:Edited(a)
    return false
  end
  self:Edited(r, true)
  return true
end

-- A shift-clicked item/spell link or a raid symbol string.
function Editor:InsertLink(link)
  local obj = RM.parseObject(link)
  return obj ~= nil and self:InsertObject(obj)
end

function Editor:Undo(redo)
  local doc = self.doc
  local caret
  if redo then
    caret = doc:redo(self.caret)
  else
    caret = doc:undo(self.caret)
  end
  if not caret then
    return false
  end
  self:Edited(caret)
  return true
end

-- Toolbar ----------------------------------------------------------------------------------

-- What the toolbar shows at the caret or over the selection. A pending style counts as
-- the style of the caret.
function Editor:State()
  local doc = self.doc
  local a, b = self:Range()
  local _, note = self:Appearance()
  local base = note.style.size
  local heading = doc.lines[doc:lineOf(a)].heading
  if heading > 0 then
    base = base + RL.HEADING_EXTRA[heading]
  end
  local st = RM.toolbarState(doc, a, b, base)
  local p = self.pending
  if a == b and p then
    st.bold, st.italic, st.size, st.color = p.bold, p.italic, p.size or base, p.color
  end
  st.canUndo, st.canRedo = doc:canUndo(), doc:canRedo()
  return st
end

function Editor:SyncState()
  if self.opts.onState then
    self.opts.onState(self:State(), self)
  end
end

-- Toolbar handlers: every action keeps (or returns) the keyboard focus here.
function Editor:Handlers()
  local function act(fn)
    return function(...)
      fn(...)
      self:Focus()
    end
  end
  return {
    bold = act(function()
      self:ToggleFlag("bold")
    end),
    italic = act(function()
      self:ToggleFlag("italic")
    end),
    size = act(function(n)
      self:SetFormat("size", n)
    end),
    color = act(function(value)
      self:SetFormat("color", value)
    end),
    heading = act(function(level)
      self:SetBlock("heading", level)
    end),
    list = act(function()
      self:SetBlock("list")
    end),
    check = act(function()
      self:SetBlock("check")
    end),
    align = act(function(value)
      self:SetBlock("align", value)
    end),
    icon = act(function(i)
      self:InsertObject({ icon = i })
    end),
    undo = act(function()
      self:Undo(false)
    end),
    redo = act(function()
      self:Undo(true)
    end),
  }
end

-- Keyboard -------------------------------------------------------------------------------------

-- Caret one visual line up or down, keeping the column (goalX) like a text editor.
function Editor:Vertical(step)
  local layout = self:Layout()
  local x, _, _, idx = layout:positionToPoint(self.caret)
  self.goalX = self.goalX or x
  local target = idx + step
  if target < 1 then
    return 0
  elseif target > #layout.lines then
    return self.doc:length()
  end
  local line = layout.lines[target]
  return layout:pointToPosition(self.goalX, line.top + line.height / 2)
end

function Editor:DeleteBack(ctrl)
  local doc = self.doc
  local a, b = self:Range()
  if a < b then
    return self:DeleteRange(a, b)
  end
  local caret = self.caret
  if caret == 0 then
    return false
  end
  if ctrl then
    return self:DeleteRange(wordLeft(doc, caret), caret)
  end
  -- Backspace at the start of a heading, list item or checkbox first removes the block.
  local ln = doc:lineOf(caret)
  local l = doc.lines[ln]
  if caret == doc:lineRange(ln) and (l.list or l.check ~= nil or l.heading > 0) then
    if self:Run(doc.setBlock, doc, ln, ln, { heading = 0 }, caret) then
      self:Changed()
    end
    return true
  end
  return self:DeleteRange(caret - 1, caret)
end

function Editor:DeleteForward(ctrl)
  local doc = self.doc
  local a, b = self:Range()
  if a < b then
    return self:DeleteRange(a, b)
  end
  local caret = self.caret
  if caret >= doc:length() then
    return false
  end
  return self:DeleteRange(caret, ctrl and wordRight(doc, caret) or caret + 1)
end

function Editor:DeleteRange(a, b)
  if a >= b then
    return false
  end
  if self:Run(self.doc.deleteRange, self.doc, a, b) == false then
    return false
  end
  self:Edited(a)
  return true
end

function Editor:Navigate(key, ctrl, shift)
  local doc = self.doc
  local a, b = self:Range()
  local pos, keepGoal
  if key == "LEFT" then
    pos = (not shift and a < b) and a or (ctrl and wordLeft(doc, self.caret) or self.caret - 1)
  elseif key == "RIGHT" then
    pos = (not shift and a < b) and b or (ctrl and wordRight(doc, self.caret) or self.caret + 1)
  elseif key == "UP" or key == "DOWN" then
    pos, keepGoal = self:Vertical(key == "UP" and -1 or 1), true
  elseif key == "HOME" or key == "END" then
    if ctrl then
      pos = key == "HOME" and 0 or doc:length()
    else
      local layout = self:Layout()
      local _, _, _, idx = layout:positionToPoint(self.caret)
      local line = layout.lines[idx]
      if key == "HOME" then
        pos = line.startPos
      else
        pos = line.final and line.endPos or math.max(line.startPos, line.endPos - 1)
      end
    end
  else -- PAGEUP, PAGEDOWN
    local layout = self:Layout()
    local x, y = layout:positionToPoint(self.caret)
    self.goalX = self.goalX or x
    local delta = (key == "PAGEUP" and -1 or 1) * math.max(20, self.area:GetHeight() - 20)
    pos, keepGoal = layout:pointToPosition(self.goalX, math.max(0, y + delta)), true
    self.area:ScrollTo(self.area:GetVerticalScroll() + delta)
  end
  self:Move(pos, shift, keepGoal)
end

-- Ctrl + key combinations for the text zoom. [Probe] the client's names for the plus and
-- minus keys differ between layouts, so the usual spellings are all accepted.
RE.ZOOM_KEYS = {
  ["+"] = "zoomIn",
  ["="] = "zoomIn",
  PLUS = "zoomIn",
  NUMPADPLUS = "zoomIn",
  ["-"] = "zoomOut",
  MINUS = "zoomOut",
  NUMPADMINUS = "zoomOut",
  ["0"] = "zoomReset",
  NUMPAD0 = "zoomReset",
}

-- Ctrl + key for the paragraph alignment (as in common word processors).
RE.ALIGN_KEYS = { L = "left", E = "center", R = "right" }

local NAVIGATION = { LEFT = 1, RIGHT = 1, UP = 1, DOWN = 1, HOME = 1, END = 1, PAGEUP = 1, PAGEDOWN = 1 }

-- Handles one key. Returns true when the editor used it. Text keys are not handled
-- here, they arrive through the hidden box (OnHiddenText).
function Editor:OnKey(key, ctrl, shift, alt)
  self.keyEvents = self.keyEvents + 1
  if ctrl == nil then
    ctrl, shift, alt = modifiers()
  end
  if ctrl and alt then
    ctrl = false -- AltGr on a German keyboard reports Ctrl+Alt
  end
  if self.copyArmed and not (ctrl and (key == "C" or key == "X")) then
    self:Neutral()
  end
  if MODIFIER_KEYS[key] then
    return false
  end
  if NAVIGATION[key] then
    self:Navigate(key, ctrl, shift)
    return true
  elseif key == "BACKSPACE" then
    self:DeleteBack(ctrl)
    return true
  elseif key == "DELETE" then
    self:DeleteForward(ctrl)
    return true
  elseif key == "ENTER" or key == "NUMPADENTER" then
    local now = RM.clock()
    if self.enterFallbackAt and now - self.enterFallbackAt < 0.05 then
      self.enterFallbackAt = nil -- the text event came first and already did this Enter
      return true
    end
    self.enterAt = now
    self:Enter()
    return true
  elseif key == "TAB" then
    return true
  elseif ctrl then
    if key == "A" then
      self:SelectAll()
    elseif key == "Z" then
      self:Undo(shift)
    elseif key == "Y" then
      self:Undo(true)
    elseif key == "B" then
      self:ToggleFlag("bold")
    elseif key == "I" then
      self:ToggleFlag("italic")
    elseif RE.ALIGN_KEYS[key] then
      self:SetBlock("align", RE.ALIGN_KEYS[key])
    elseif key == "S" then
      if self.opts.onSave then
        self.opts.onSave(self)
      end
    elseif key == "N" or RE.ZOOM_KEYS[key] then
      local command = key == "N" and "new" or RE.ZOOM_KEYS[key]
      if not self.opts.onCommand then
        return false
      end
      self.opts.onCommand(command)
    elseif key == "C" then
      self:Copy(false)
    elseif key == "X" then
      self:Copy(true)
    elseif key ~= "V" then
      return false
    end
    return true
  end
  return false
end

-- Mouse -------------------------------------------------------------------------------------

-- Pointer position in layout coordinates (relative to the first line's top left).
function Editor:Pointer()
  local cx, cy = 0, 0
  if GetCursorPosition then
    cx, cy = GetCursorPosition()
  end
  local content = self.content
  local s = content:GetEffectiveScale()
  return cx / s - content:GetLeft() - RE.PAD, content:GetTop() - cy / s - RE.PAD
end

-- Word around a caret position: the run of same-class characters next to it.
function Editor:WordRange(pos)
  local doc = self.doc
  local chars, n = doc.chars, doc:length()
  local i = pos + 1
  if chars[i] == nil or chars[i] == "\n" then
    i = pos
  end
  if i < 1 or chars[i] == "\n" then
    return pos, pos
  end
  local c = charClass(chars[i])
  local a, b = i - 1, i
  while a >= 1 and charClass(chars[a]) == c do
    a = a - 1
  end
  while b < n and charClass(chars[b + 1]) == c do
    b = b + 1
  end
  return a, b
end

function Editor:PointerDown(x, y, button, shift)
  if button == "RightButton" then
    self:Focus()
    self:OpenMenu()
    return
  end
  RE.CloseMenu()
  self:Focus()
  local layout = self:Layout()
  local line = layout:checkAt(x, y)
  if line then
    self:ToggleCheck(line)
    return
  end
  local pos = layout:pointToPosition(x, y)
  local now = RM.clock()
  local last = self.lastClick
  local count = 1
  if
    last
    and now - last.t < RE.CLICK_GAP
    and math.abs(x - last.x) <= RE.CLICK_DIST
    and math.abs(y - last.y) <= RE.CLICK_DIST
  then
    count = last.count % 3 + 1
  end
  self.lastClick = { t = now, x = x, y = y, count = count }
  if shift then
    self:Move(pos, true)
    self.dragging = true
  elseif count == 2 then
    local a, b = self:WordRange(pos)
    self.anchor = a
    self:Move(b, true)
  elseif count == 3 then
    local first, last2 = self.doc:lineRange(self.doc:lineOf(pos))
    self.anchor = first
    self:Move(last2, true)
  else
    self:Move(pos, false)
    self.dragging = true
  end
end

function Editor:PointerUp()
  self.dragging = false
end

function Editor:DragTo(x, y)
  local pos = self:Layout():pointToPosition(x, y)
  if pos ~= self.caret then
    self:Move(pos, true)
  end
end

-- The link run under a point, or nil.
function Editor:LinkAt(x, y)
  local lines = self:Layout().lines
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
  if line and y >= line.top and y < line.top + line.height then
    for _, run in ipairs(line.runs) do
      if run.kind == "link" and x >= run.x and x < run.x + run.width then
        return run
      end
    end
  end
end

-- Item and spell links keep their tooltip while editing.
function Editor:Hover(x, y)
  local run = self:LinkAt(x, y)
  local link = run and run.link
  if link == self.hoverLink then
    return
  end
  self.hoverLink = link
  local payload = link and link:match("|H([^|]+)|h")
  if payload and M.LINK_TYPES[payload:match("^(%a+):") or ""] then
    ns.W.Tooltip.Show(self.content, { link = payload, anchor = "ANCHOR_CURSOR" })
  else
    ns.HideTooltip()
  end
end

-- Focus --------------------------------------------------------------------------------------

function Editor:Focus()
  self.hb:SetFocus()
end

function Editor:Blur()
  self.hb:ClearFocus()
end

function Editor:HasFocus()
  return self.focused == true
end

-- Counts an error of an input handler; after a few the owner is asked to switch to the
-- code view.
function Editor:Failed()
  self.failures = self.failures + 1
  if self.failures >= RE.MAX_FAILURES and not self.broken then
    self.broken = true
    ns.Log.warn("rich editor input failed %d times, falling back to the code view", self.failures)
    if self.opts.onBroken then
      self.opts.onBroken(self)
    end
  end
end

function Editor:BindScripts()
  local hb, content, frame = self.hb, self.content, self.frame
  local function guard(context, fn)
    return function(...)
      if not ns.Safe("rich-" .. context, fn, ...) then
        self:Failed()
      end
    end
  end

  hb:SetScript(
    "OnKeyDown",
    guard("key", function(_, key)
      self:OnKey(key)
    end)
  )
  hb:SetScript(
    "OnKeyUp",
    guard("keyup", function()
      if self.copyArmed then
        self:Neutral()
      end
    end)
  )
  hb:SetScript(
    "OnTextChanged",
    guard("text", function(_, user)
      self:OnHiddenText(user)
    end)
  )
  hb:SetScript("OnEscapePressed", function()
    -- Esc closes what is open on top (menu, toolbar popups) before it leaves the field.
    local closed = RE.CloseMenu()
    closed = RT.ClosePopups() or closed
    closed = ns.NoteWindow.CloseIconPicker() or closed
    closed = ns.Desktop.Layer.close("escape") or closed
    if not closed then
      hb:ClearFocus()
    end
  end)
  hb:SetScript(
    "OnTabPressed",
    guard("tab", function()
      -- Never a keyboard trap: Tab leaves the editor for the next control.
      hb:ClearFocus()
      ns.Focus.set(frame)
      ns.Focus.move(IsShiftKeyDown and IsShiftKeyDown() and -1 or 1)
    end)
  )
  hb:SetScript(
    "OnEditFocusGained",
    guard("focus", function()
      self.focused = true
      self.border.set("actionHi", 1)
      self:Neutral()
      self:Paint()
      if self.opts.onFocus then
        self.opts.onFocus(self)
      end
    end)
  )
  hb:SetScript(
    "OnEditFocusLost",
    guard("blur", function()
      self.focused = false
      self.border.set("white", 0.25)
      self:Neutral()
      self.caretTex:Hide()
      self:Paint()
    end)
  )

  content:EnableMouse(true)
  content:SetScript(
    "OnMouseDown",
    guard("mouse", function(_, button)
      local x, y = self:Pointer()
      self:PointerDown(x, y, button, IsShiftKeyDown and IsShiftKeyDown() or false)
    end)
  )
  content:SetScript("OnMouseUp", function()
    self:PointerUp()
  end)
  content:SetScript("OnEnter", function()
    self.hovering = true
  end)
  content:SetScript("OnLeave", function()
    self.hovering = false
    if self.hoverLink then
      self.hoverLink = nil
      ns.HideTooltip()
    end
  end)
  content:SetScript(
    "OnUpdate",
    guard("tick", function(_, elapsed)
      if self.dragging then
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
          self.dragging = false
          return
        end
        self:DragTo(self:Pointer())
      elseif self.hovering then
        self.hoverWait = (self.hoverWait or 0) + elapsed
        if self.hoverWait >= RE.HOVER_STEP then
          self.hoverWait = 0
          self:Hover(self:Pointer())
        end
      end
    end)
  )

  -- Caret blink.
  self.caretLayer:SetScript("OnUpdate", function(_, elapsed)
    if not self.focused then
      return
    end
    self.blink = self.blink + elapsed
    if self.blink >= RE.BLINK then
      self.blink = 0
      self.blinkOn = not self.blinkOn
      self.caretTex:SetShown(self.blinkOn)
    end
  end)

  -- Ctrl + wheel zooms, the plain wheel keeps scrolling.
  local scroll = self.area:GetScript("OnMouseWheel")
  self.area:SetScript("OnMouseWheel", function(area, delta)
    if modifiers() and self.opts.onCommand then
      self.opts.onCommand(delta > 0 and "zoomIn" or "zoomOut")
    elseif scroll then
      scroll(area, delta)
    end
  end)

  -- Scrolling redraws the visible lines, a new width wraps the text again.
  self.area:HookScript("OnVerticalScroll", function()
    self:Paint()
  end)
  self.area:HookScript("OnSizeChanged", function()
    ns.Debounce(self, 0.05, function()
      self:Paint()
    end)
  end)
  frame:HookScript("OnHide", function()
    self.focused = false
    self.dragging = false
    hb:ClearFocus()
    if self.hoverLink then
      self.hoverLink = nil
      ns.HideTooltip()
    end
    if menu and menu.owner == self then
      RE.CloseMenu()
    end
  end)
end

-- Conversion to and from the code view ------------------------------------------------------

-- Cursor position (in characters) of the caret inside RichModel.toMarkup(doc), for
-- switching to the code view without losing the place.
function Editor:MarkupCursor()
  local doc = self.doc
  local pos = self.caret
  local chars, styles, lines = {}, {}, {}
  for i = 1, pos do
    chars[i], styles[i] = doc.chars[i], doc.styles[i]
  end
  chars[pos + 1], styles[pos + 1] = MARKER, doc:getStyleAt(pos)
  for i = pos + 1, doc:length() do
    chars[i + 1], styles[i + 1] = doc.chars[i], doc.styles[i]
  end
  for i, l in ipairs(doc.lines) do
    lines[i] = { heading = l.heading, list = l.list, check = l.check }
  end
  local tmp = RM.new()
  tmp.chars, tmp.styles, tmp.lines = chars, styles, lines
  local text = RM.toMarkup(tmp)
  local at = text:find(MARKER, 1, true)
  return at and C.charCount(text:sub(1, at - 1)) or C.charCount(text)
end

-- Caret position in the formatted text for a cursor (characters) inside markup.
function RE.CaretFromMarkup(text, cursor)
  local prefix = text:sub(1, M.byteOffset(text, cursor))
  prefix = M.sanitize((prefix:gsub("{[^{}]*$", "")))
  return RM.fromMarkup(prefix):length()
end

-- Note editor: toolbar, code editor and formatted editor ---------------------------------------

local editors = setmetatable({}, { __mode = "k" })
RE.editors = editors
local Note = {}
Note.__index = Note

local function storedMode()
  local s = ns.db and ns.db.settings
  return (s and s.noteEditor == "code") and "code" or "normal"
end

-- The zoom is one account-wide setting (percent), every editor follows it.
function RE.zoom()
  local z = ns.db and ns.db.settings and ns.db.settings.noteZoom
  if type(z) ~= "number" then
    return RE.ZOOM_DEFAULT
  end
  return clamp(math.floor(z + 0.5), RE.ZOOM_MIN, RE.ZOOM_MAX)
end

function RE.setZoom(percent)
  ns.Store.set(
    "settings.noteZoom",
    clamp(math.floor((tonumber(percent) or RE.ZOOM_DEFAULT) + 0.5), RE.ZOOM_MIN, RE.ZOOM_MAX)
  )
end

-- Line and column (1-based, in characters) of a cursor inside plain text such as the
-- code view's markup.
function RE.textPosition(text, cursor)
  local prefix = text:sub(1, M.byteOffset(text, cursor))
  local _, breaks = prefix:gsub("\n", "")
  return breaks + 1, M.length(prefix:match("([^\n]*)$")) + 1
end

-- opts: height, getNote() -> note, onChange(editor) after every edit, onSave() for
-- Ctrl+S, onFocus(editor), onMode(mode), onNew() for Ctrl+N. Returns an object with
-- .toolbar and .body (the text area, the owner anchors both), .code (the code editor),
-- .rich. NoteChrome adds the menu and the status bar and sets .onStatus(editor), which
-- runs whenever caret, selection, text, mode or zoom changed.
function RE.NewNoteEditor(parent, opts)
  local self = setmetatable({ opts = opts, mode = "normal", edited = false, baseline = "" }, Note)
  local body = CreateFrame("Frame", nil, parent)
  if opts.height then
    body:SetHeight(opts.height)
  end
  self.body = body

  self.code = ns.MacroUI.CodeEdit(body, {
    colored = false,
    height = opts.height,
    onChange = function()
      self.edited = true
      if opts.onChange then
        opts.onChange(self)
      end
      self:Touch()
    end,
    onSave = opts.onSave,
  })
  self.code:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  self.code:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  self.code.edit:SetMaxLetters(N.MAX_TEXT)
  self.code.edit:HookScript("OnEditFocusGained", function()
    if opts.onFocus then
      opts.onFocus(self)
    end
  end)
  self.code.edit:HookScript("OnCursorChanged", function()
    self:Touch()
  end)
  -- The code field is a plain EditBox: Ctrl+N and the zoom keys reach it here.
  self.code.edit:HookScript(
    "OnKeyDown",
    ns.Wrap("note-code-key", function(_, key)
      if modifiers() and (key == "N" or RE.ZOOM_KEYS[key]) then
        self:Command(key == "N" and "new" or RE.ZOOM_KEYS[key])
      end
    end)
  )

  self.toolbar = RT.Build(parent, {})

  local ok, rich = pcall(RE.New, body, {
    getNote = opts.getNote,
    onChange = function()
      self.edited = true
      if opts.onChange then
        opts.onChange(self)
      end
    end,
    onState = function(state)
      if self.mode == "normal" then
        self.toolbar:SetState(state)
        self:Touch()
      end
    end,
    onCommand = function(name)
      self:Command(name)
    end,
    onSave = opts.onSave,
    onFocus = function()
      if opts.onFocus then
        opts.onFocus(self)
      end
    end,
    onBroken = function()
      self:Fallback()
    end,
  })
  if ok then
    self.rich = rich
    rich.frame:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    rich.frame:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    rich.zoom = RE.zoom()
  else
    ns.Log.warn("rich editor could not be built: %s", tostring(rich))
  end

  editors[self] = true
  self:Apply(self.rich and storedMode() or "code", true)
  return self
end

local function merge(handlers, extra)
  for k, v in pairs(extra) do
    handlers[k] = v
  end
  return handlers
end

-- Shows the editor of `mode` and wires the toolbar to it. The caller has converted the
-- value already (SetMode) or there is nothing to convert yet (first call).
function Note:Apply(mode, first)
  self.mode = mode
  local normal = mode == "normal"
  if self.rich then
    self.rich.frame:SetShown(normal)
  end
  self.code:SetShown(not normal)
  local toggle = function()
    self:Toggle()
  end
  if normal then
    self.toolbar:SetHandlers(merge(self.rich:Handlers(), { mode = toggle }))
  else
    self.toolbar:SetHandlers(merge(
      ns.NoteWindow.CodeHandlers(self.code, function()
        self.edited = true
        if self.opts.onChange then
          self.opts.onChange(self)
        end
      end),
      { mode = toggle }
    ))
    self.toolbar:SetState({})
  end
  self.toolbar:SetMode(mode)
  self:Restyle()
  if not first and self.opts.onMode then
    self.opts.onMode(mode)
  end
  self:Touch()
end

-- Alignment of the lines at the caret or selection ("left", "center", "right", "mixed"),
-- nil in the code view, which shows tags instead of states.
function Note:AlignState()
  if self.mode == "normal" and self.rich then
    return self.rich:State().align
  end
end

-- The toolbar's alignment action for either view.
function Note:Align(value)
  local handler = self.toolbar.handlers.align
  if handler then
    handler(value)
  end
end

function Note:Touch()
  if self.onStatus then
    self.onStatus(self)
  end
end

-- What the status bar shows: caret line and column, characters in the text, characters
-- selected. The code view counts the markup text and cannot tell a selection.
function Note:Stats()
  if self.mode == "normal" and self.rich then
    local line, col = self.rich:Position()
    local chars, selected = self.rich:Counts()
    return { line = line, col = col, chars = chars, selected = selected, mode = "normal" }
  end
  local text = self.code:GetValue()
  local line, col = RE.textPosition(text, self.code:Cursor())
  return { line = line, col = col, chars = M.length(text), selected = 0, mode = "code" }
end

-- Menu commands. The clipboard of the client is out of reach for a click, so copy and
-- cut keep the text (with formatting) in the editors' own clipboard and paste takes it
-- from there; Ctrl+C, Ctrl+X and Ctrl+V still go through the client.
function Note:HasSelection()
  return self.mode == "normal" and self.rich:HasSelection()
end

function Note:CanUndo(redo)
  if self.mode == "normal" then
    return redo and self.rich.doc:canRedo() or (not redo and self.rich.doc:canUndo())
  end
  return redo and self.code:CanRedo() or (not redo and self.code:CanUndo())
end

function Note:Undo(redo)
  if self.mode == "normal" then
    self.rich:Undo(redo)
  elseif redo then
    self.code:Redo()
  else
    self.code:Undo()
  end
  self:Focus()
end

function Note:Copy(cut)
  if self.mode ~= "normal" or not self.rich:Copy(cut) then
    return false
  end
  self.rich:Hint("notes.menu.copied")
  self:Focus()
  return true
end

function Note:CanPaste()
  return RE.clip ~= nil and RE.clip.markup ~= ""
end

function Note:Paste()
  if not self:CanPaste() then
    return false
  end
  self:Focus()
  if self.mode == "normal" then
    return self.rich:PasteClip()
  end
  self.code:Insert(RE.clip.text)
  return true
end

function Note:SelectAll()
  self:Focus()
  if self.mode == "normal" then
    self.rich:SelectAll()
  else
    self.code.edit:HighlightText()
  end
end

function Note:Command(name)
  if name == "zoomIn" then
    RE.setZoom(RE.zoom() + RE.ZOOM_STEP)
  elseif name == "zoomOut" then
    RE.setZoom(RE.zoom() - RE.ZOOM_STEP)
  elseif name == "zoomReset" then
    RE.setZoom(RE.ZOOM_DEFAULT)
  elseif name == "new" and self.opts.onNew then
    self.opts.onNew()
  end
end

-- Takes the stored zoom (the setting changed, here or in another editor).
function Note:ApplyZoom()
  if self.rich then
    self.rich:SetZoom(RE.zoom())
  end
  self:Touch()
end

function Note:Restyle()
  local note = self.opts.getNote and self.opts.getNote()
  if note then
    self.toolbar:SetContext(RL.noteContext(note))
  end
  if self.rich and self.mode == "normal" then
    self.rich:Restyle()
  end
end

-- Switches between the formatted editor and the code view, keeping the text and, as
-- far as possible, the place of the caret. `focus` moves the keyboard focus along.
function Note:SetMode(mode)
  if mode ~= "code" then
    mode = "normal"
  end
  if mode == "normal" and not self.rich then
    mode = "code"
  end
  if mode == self.mode then
    return
  end
  local hadFocus = self:HasFocus()
  if mode == "code" then
    local markup = self.rich:GetValue()
    local cursor = self.rich:MarkupCursor()
    self.code:SetValue(markup)
    self.code.edit:SetCursorPosition(cursor)
    self.rich:Blur()
    self:Apply(mode)
    if hadFocus then
      self.code:Focus()
    end
  else
    local text = self.code:GetValue()
    local cursor = self.code:Cursor()
    self.code.edit:ClearFocus()
    self.rich.failures, self.rich.broken = 0, false
    self.rich:SetValue(text, RE.CaretFromMarkup(text, cursor))
    self:Apply(mode)
    if hadFocus then
      self.rich:Focus()
    end
  end
end

-- The toolbar button: switch and remember the choice (other open editors follow).
function Note:Toggle()
  local mode = self.mode == "code" and "normal" or "code"
  if mode == "normal" and not self.rich then
    return
  end
  ns.Store.set("settings.noteEditor", mode)
  self:SetMode(mode)
end

-- Input in the formatted editor fails: use the code view for this session.
function Note:Fallback()
  if self.mode == "normal" then
    ns.Notify(L["notes.rich.fallback"], "warning")
    self:SetMode("code")
  end
end

function Note:SetValue(text)
  self.edited = false
  self.baseline = M.sanitize(text or "")
  if self.mode == "normal" then
    self.rich:SetValue(text, 0)
  else
    self.code:SetValue(text or "")
  end
  self:Touch()
end

function Note:GetValue()
  if self.mode == "normal" then
    return self.rich:GetValue()
  end
  return self.code:GetValue()
end

-- Is the stored text different from what this editor was given or has produced? (An
-- edit made elsewhere, in the other window.)
function Note:IsStale(noteText)
  local mine = self.edited and M.sanitize(self:GetValue()) or self.baseline
  return mine ~= noteText
end

function Note:HasFocus()
  if self.mode == "normal" then
    return self.rich:HasFocus()
  end
  return self.code.edit:HasFocus() and true or false
end

function Note:Focus()
  if self.mode == "normal" then
    self.rich:Focus()
  else
    self.code:Focus()
  end
end

function Note:Blur()
  if self.rich then
    self.rich:Blur()
  end
  self.code.edit:ClearFocus()
end

function Note:InsertLink(link)
  if self.mode == "normal" then
    return self.rich:InsertLink(link)
  end
  self.code:Insert(link)
  return true
end

ns.On("FG_SETTING_CHANGED", function(_, path, value)
  if path == "settings.noteEditor" then
    for e in pairs(editors) do
      e:SetMode(value)
    end
  elseif path == "settings.noteZoom" then
    for e in pairs(editors) do
      e:ApplyZoom()
    end
  end
end)
