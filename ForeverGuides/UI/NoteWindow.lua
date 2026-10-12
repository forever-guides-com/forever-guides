-- Note windows: one small movable, scalable window per open note (pool, never
-- UIPanel templates). Free notes close with Esc, sticky notes keep their
-- position and ignore Esc (only the X or "sticky off" closes them).
-- The view renders the markup; the editor is the formatted editor (Modules/RichEditor.lua)
-- or, switched with the "Code" button, a plain text field with the raw markup.
-- A note window shows nothing but the title bar and the text until it is switched to
-- edit mode: then the title field, menu bar, toolbar, text area and status bar appear
-- (Modules/NoteChrome.lua) and the window keeps a larger minimum size.
-- Rendering: the rich renderer (Modules/RichLayout.lua) by default, SimpleHTML and a
-- plain block renderer stay as fallbacks the setting "Darstellung" can select.
-- Look: background color, opacity, auto-hiding title bar and buttons and the text shadow
-- come from Modules/WindowStyle.lua (per-window overrides in note.window, else the
-- global defaults of the settings page).
local _, ns = ...
local W, L, Theme, U, N, M, WS = ns.W, ns.L, ns.Theme, ns.U, ns.Notes, ns.Markup, ns.WindowStyle

local NW = { byId = {}, pool = {}, made = 0 }
ns.NoteWindow = NW

local HEAD_H = 22
local EDIT_MIN_W, EDIT_MIN_H = 380, 320

ns.AddLocale("enUS", {
  ["notes.untitled"] = "Untitled note",
  ["notes.win.edit"] = "Edit text",
  ["notes.win.openAddon"] = "Open in addon",
  ["notes.win.done"] = "Done (save)",
  ["notes.win.sticky"] = "Sticky",
  ["notes.win.stickyTip"] = "Fixes position and size, Esc does not close.",
  ["notes.win.fold"] = "Fold / unfold",
  ["notes.win.close"] = "Close note",
  ["notes.win.scaleTip"] = "{key:windowScale} on the title bar scales the note.",
  ["notes.win.grip"] = "Drag to resize",
  ["notes.tb.heading"] = "Heading",
  ["notes.tb.headingTip"] = "# Large, ## Medium, ### Small at the start of a line.",
  ["notes.tb.list"] = "List item",
  ["notes.tb.check"] = "Checkbox",
  ["notes.tb.checkTip"] = "[ ] open, [x] done, click to tick.",
  ["notes.tb.icons"] = "Raid symbol",
  ["notes.tb.undo"] = "Undo (Ctrl+Z)",
  ["notes.tb.redo"] = "Redo (Ctrl+Y)",
  ["notes.col.red"] = "red",
  ["notes.col.yellow"] = "yellow",
  ["notes.col.green"] = "green",
  ["notes.col.blue"] = "blue",
  ["notes.col.gray"] = "gray",
  ["notes.col.class"] = "class",
  ["notes.edit.title"] = "Title",
  ["notes.slash.none"] = "No note with that title (/fg notes lists them).",
  ["notes.slash.limit"] = "Note limit reached (%d), delete some first.",
  ["notes.slash.closed"] = "Closed %d note window(s).",
  ["notes.slash.usage"] = "/fg note new [title] | <title> | stick <title> | unstick <title> | close <title|all>",
  ["notes.font.fallback"] = "Font missing in this client, using default.",
})

ns.AddLocale("deDE", {
  ["notes.untitled"] = "Notiz ohne Titel",
  ["notes.win.edit"] = "Text bearbeiten",
  ["notes.win.openAddon"] = "Im Addon öffnen",
  ["notes.win.done"] = "Fertig (speichern)",
  ["notes.win.sticky"] = "Anheften",
  ["notes.win.stickyTip"] = "Fixiert Position und Größe, Esc schließt nicht.",
  ["notes.win.fold"] = "Ein-/ausklappen",
  ["notes.win.close"] = "Notiz schließen",
  ["notes.win.scaleTip"] = "{key:windowScale} auf der Titelleiste skaliert die Notiz.",
  ["notes.win.grip"] = "Ziehen zum Skalieren",
  ["notes.tb.heading"] = "Überschrift",
  ["notes.tb.headingTip"] = "# Groß, ## Mittel, ### Klein am Zeilenanfang.",
  ["notes.tb.list"] = "Listenpunkt",
  ["notes.tb.check"] = "Checkbox",
  ["notes.tb.checkTip"] = "[ ] offen, [x] erledigt, Klick hakt ab.",
  ["notes.tb.icons"] = "Schlachtzugssymbol",
  ["notes.tb.undo"] = "Rückgängig (Strg+Z)",
  ["notes.tb.redo"] = "Wiederholen (Strg+Y)",
  ["notes.col.red"] = "rot",
  ["notes.col.yellow"] = "gelb",
  ["notes.col.green"] = "gruen",
  ["notes.col.blue"] = "blau",
  ["notes.col.gray"] = "grau",
  ["notes.col.class"] = "klasse",
  ["notes.edit.title"] = "Titel",
  ["notes.slash.none"] = "Keine Notiz mit diesem Titel (/fg notizen zeigt sie).",
  ["notes.slash.limit"] = "Notiz-Limit erreicht (%d), zuerst löschen.",
  ["notes.slash.closed"] = "%d Notizfenster geschlossen.",
  ["notes.slash.usage"] = "/fg note new [Titel] | <Titel> | stick <Titel> | unstick <Titel> | close <Titel|all>",
  ["notes.font.fallback"] = "Schrift fehlt im Client, Standardschrift aktiv.",
})

-- Fonts ------------------------------------------------------------------------

local function lsm()
  local stub = rawget(_G, "LibStub")
  return stub and stub:GetLibrary("LibSharedMedia-3.0", true)
end

local function fontPath(key)
  if N.FONT_FILES[key] then
    return N.FONT_FILES[key]
  end
  local name = type(key) == "string" and key:match("^lsm:(.+)$")
  local lib = name and lsm()
  if lib then
    local ok, path = pcall(lib.Fetch, lib, "font", name, true)
    if ok and path then
      return path
    end
  end
end
NW.fontPath = fontPath

-- Returns true when the requested font was applied, false when a fallback was used.
function NW.ApplyFont(fs, key, size, flags)
  local path = fontPath(key) or N.FONT_FILES.frizqt
  if fs:SetFont(path, size, flags or "") then
    return path == fontPath(key)
  end
  if not fs:SetFont(N.FONT_FILES.frizqt, size, flags or "") then
    fs:SetFont(rawget(_G, "STANDARD_TEXT_FONT") or N.FONT_FILES.frizqt, size, flags or "")
  end
  return false
end

local probeFs
local fontCache = {}
function NW.FontAvailable(key)
  if fontCache[key] ~= nil then
    return fontCache[key]
  end
  probeFs = probeFs or UIParent:CreateFontString(nil, "OVERLAY")
  local path = fontPath(key)
  local ok = path ~= nil and probeFs:SetFont(path, 12, "") and true or false
  fontCache[key] = ok
  return ok
end

-- Keys offered in the font dropdown: client fonts that load, then shared media fonts.
function NW.FontList()
  local out = {}
  for _, key in ipairs(N.FONT_KEYS) do
    if NW.FontAvailable(key) then
      out[#out + 1] = key
    end
  end
  local lib = lsm()
  if lib then
    local ok, names = pcall(lib.List, lib, "font")
    if ok and type(names) == "table" then
      for i = 1, math.min(#names, 40) do
        local key = "lsm:" .. tostring(names[i])
        if N.FONT_FILES[key] == nil and #key <= 44 and key:match("^lsm:[%w _%-%.]+$") then
          out[#out + 1] = key
        end
      end
    end
  end
  if #out == 0 then
    out[1] = "frizqt"
  end
  return out
end

function NW.FontReport()
  local parts = {}
  for _, key in ipairs(N.FONT_KEYS) do
    parts[#parts + 1] = key .. "=" .. (NW.FontAvailable(key) and "yes" or "no")
  end
  parts[#parts + 1] = "lsm=" .. (lsm() and "yes" or "no")
  return table.concat(parts, " ")
end

local function fontSize(note, extra)
  local scale = (ns.db and ns.db.settings.fontScale) or 1
  return U.clamp(math.floor((note.style.size + (extra or 0)) * scale + 0.5), 9, 48)
end

local function render(note)
  local classHex
  local ok, _, class = pcall(UnitClass, "player")
  if ok and class and Theme.classColors[class] then
    classHex = Theme.classColors[class]:gsub("#", "")
  end
  return { fg = note.style.fg, bg = note.style.bg, classHex = classHex }
end

-- Renderers ----------------------------------------------------------------------
-- Both: r.frame, r:Set(note, width) -> content height. onToggle(line) ticks a checkbox.

local HEADING_EXTRA = { 6, 3, 1 }

local function newBlocks(parent, onToggle)
  local r = { kind = "blocks", rows = {} }
  r.frame = CreateFrame("Frame", nil, parent)
  local function row(i)
    local x = r.rows[i]
    if not x then
      x = CreateFrame("Frame", nil, r.frame)
      x.fs = x:CreateFontString(nil, "OVERLAY")
      x.fs:SetJustifyH("LEFT")
      x.fs:SetJustifyV("TOP")
      x.fs:SetWordWrap(true)
      x.box = CreateFrame("Button", nil, x)
      x.box.bg = x.box:CreateTexture(nil, "BACKGROUND")
      x.box.bg:SetAllPoints()
      x.box.check = W.CheckMark(x.box, 12)
      x.box.check:SetPoint("CENTER")
      x.box:SetScript(
        "OnClick",
        ns.Wrap("note-check", function(b)
          onToggle(b.line)
        end)
      )
      r.rows[i] = x
    end
    return x
  end
  function r:Set(note, width, look)
    local ctx = render(note)
    if look and look.bg then
      ctx.bg = look.bg
    end
    local fg = { U.hex(note.style.fg) }
    local base = fontSize(note)
    local y, blocks = 0, M.parse(note.text)
    for i, b in ipairs(blocks) do
      local x = row(i)
      local size, indent, color = base, 0, fg
      if b.kind == "h" then
        size = fontSize(note, HEADING_EXTRA[b.level])
        color = { U.hex(M.headingHex(ctx)) }
      elseif b.kind == "li" then
        indent = 14
      elseif b.kind == "check" then
        indent = size + 8
      end
      NW.ApplyFont(x.fs, note.style.font, size, b.kind == "h" and "OUTLINE" or "")
      x.fs:SetTextColor(color[1], color[2], color[3], 1)
      WS.ApplyShadow(x.fs, look and look.shadow, color[1], color[2], color[3])
      x.fs:ClearAllPoints()
      x.fs:SetPoint("TOPLEFT", indent, 0)
      x.fs:SetWidth(math.max(20, width - indent))
      x.fs:SetJustifyH(string.upper(b.align))
      local text = M.toWoW(b.spans, ctx)
      if b.kind == "li" then
        text = "- " .. text
      end
      x.fs:SetText(b.kind == "blank" and "" or text)
      local h = b.kind == "blank" and math.floor(size * 0.6) or math.max(x.fs:GetStringHeight(), size)
      x.box:SetShown(b.kind == "check")
      if b.kind == "check" then
        local box = size + 2
        x.box:SetSize(box, box)
        x.box:ClearAllPoints()
        x.box:SetPoint("TOPLEFT", 0, 0)
        x.box.bg:SetColorTexture(fg[1], fg[2], fg[3], 0.2)
        x.box.check:Fit(box + 6)
        x.box.check:Tint(fg[1], fg[2], fg[3])
        x.box.check:SetShown(b.checked)
        x.box.line = b.line
        h = math.max(h, box)
      end
      x:ClearAllPoints()
      x:SetPoint("TOPLEFT", r.frame, "TOPLEFT", 0, -y)
      x:SetSize(width, h)
      x:Show()
      y = y + h + math.floor(size * 0.25)
    end
    for i = #blocks + 1, #r.rows do
      r.rows[i]:Hide()
    end
    r.frame:SetSize(width, math.max(y, 1))
    return y
  end
  return r
end

local function newHtml(parent, onToggle)
  local r = { kind = "html" }
  r.frame = CreateFrame("SimpleHTML", nil, parent)
  r.frame:SetHyperlinksEnabled(true)
  r.frame:SetScript(
    "OnHyperlinkClick",
    ns.Wrap("note-link", function(_, link, text, button)
      local line = link:match("^fgchk:(%d+)$")
      if line then
        onToggle(tonumber(line))
      elseif M.LINK_TYPES[link:match("^(%a+):") or ""] and rawget(_G, "SetItemRef") then
        pcall(rawget(_G, "SetItemRef"), link, text, button)
      end
    end)
  )
  r.frame:SetScript(
    "OnHyperlinkEnter",
    ns.Wrap("note-link-enter", function(self, link)
      if M.LINK_TYPES[link:match("^(%a+):") or ""] then
        W.Tooltip.Show(self, { link = link, anchor = "ANCHOR_CURSOR" })
      end
    end)
  )
  r.frame:SetScript("OnHyperlinkLeave", ns.HideTooltip)
  function r:Set(note, width, look)
    local ctx = render(note)
    if look and look.bg then
      ctx.bg = look.bg
    end
    local f = self.frame
    local path = fontPath(note.style.font) or N.FONT_FILES.frizqt
    local fg = { U.hex(note.style.fg) }
    local head = { U.hex(M.headingHex(ctx)) }
    local base = fontSize(note)
    local function style(element, size, color, spacing)
      f:SetFont(element, path, size, element == "p" and "" or "OUTLINE")
      f:SetTextColor(element, color[1], color[2], color[3], 1)
      f:SetSpacing(element, spacing)
    end
    f:SetWidth(width)
    style("p", base, fg, 2)
    for level = 1, 3 do
      style("h" .. level, fontSize(note, HEADING_EXTRA[level]), head, 3)
    end
    local out = { "<html><body>" }
    for _, b in ipairs(M.parse(note.text)) do
      local inner = M.escapeXml(M.toWoW(b.spans, ctx))
      local align = b.align ~= "left" and (' align="' .. b.align .. '"') or ""
      if b.kind == "h" then
        out[#out + 1] = string.format("<h%d%s>%s</h%d>", b.level, align, inner, b.level)
      elseif b.kind == "li" then
        out[#out + 1] = "<p" .. align .. ">- " .. inner .. "</p>"
      elseif b.kind == "check" then
        out[#out + 1] = string.format("<p%s>|Hfgchk:%d|h[%s]|h %s</p>", align, b.line, b.checked and "x" or " ", inner)
      elseif b.kind == "blank" then
        out[#out + 1] = "<p" .. align .. "> </p>"
      else
        out[#out + 1] = "<p" .. align .. ">" .. inner .. "</p>"
      end
    end
    out[#out + 1] = "</body></html>"
    f:SetText(table.concat(out, "\n"))
    local h = math.max(f:GetContentHeight() or 0, base)
    f:SetSize(width, h)
    return h
  end
  return r
end

-- Renderer kinds: "rich" (default, the "auto" setting), "html" (SimpleHTML, links
-- clickable), "blocks" (plain FontStrings, always works). "auto" falls back from
-- rich to html to blocks when a renderer raised an error.
local function rendererKind()
  local choice = N.root().ui.renderer
  if (choice == nil or choice == "auto" or choice == "rich") and not NW.richBroken then
    return "rich"
  end
  if choice ~= "blocks" and ns.can.simpleHtml and not NW.htmlBroken then
    return "html"
  end
  return "blocks"
end

local function newRich(parent, onToggle)
  return ns.RichLayout.NewView(parent, onToggle)
end

local MAKERS = { rich = newRich, html = newHtml, blocks = newBlocks }

local function markBroken(kind, err)
  if kind == "rich" then
    NW.richBroken = true
  elseif kind == "html" then
    NW.htmlBroken = true
  end
  ns.Log.warn("note %s renderer failed: %s", kind, tostring(err))
end

-- Window pool ----------------------------------------------------------------------

local function flush(f)
  if f.dirty and f.noteId then
    f.dirty = false
    -- The text is only written back when it was edited: a title change must not
    -- rewrite an old note into the canonical form of the formatted editor.
    N.update(f.noteId, {
      title = f.titleBox.edit:GetText(),
      text = f.editor.edited and f.editor:GetValue() or nil,
    })
  end
end

local function savePosition(f)
  local s = f:GetScale()
  local left, top = f:GetLeft(), f:GetTop()
  if f.noteId and left and top then
    N.update(f.noteId, { window = { x = left * s, y = top * s } })
  end
end

local function saveSize(f)
  if f.noteId and not f.minimized then
    N.update(f.noteId, { window = { w = f:GetWidth(), h = f:GetHeight() } })
  end
end

local function place(f, w)
  f:ClearAllPoints()
  local s = f:GetScale()
  if w.x then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", w.x / s, w.y / s)
  else
    local offset = (NW.made % 6) * 24
    f:SetPoint("CENTER", UIParent, "CENTER", offset, -offset)
  end
end

-- The look of a note window: its own overrides over the global defaults.
function NW.Style(note)
  return WS.Resolve("note", note.window)
end

local function lookKey(style)
  return style.bg .. (WS.TextShadow(style) and "+" or "-")
end

-- What the renderers need to know about the window look (shadow, effective background).
local function lookOf(f, note)
  local style = NW.Style(note)
  f.drawnLook = lookKey(style)
  return { shadow = WS.TextShadow(style), bg = style.bg }
end

local function refreshBody(f)
  local note = N.get(f.noteId)
  if not note or f.editing or f.minimized then
    return
  end
  local kind = rendererKind()
  local r = f.renderers[kind]
  if not r then
    local ok, made = pcall(MAKERS[kind], f.area.content, function(line)
      local fresh = N.get(f.noteId)
      local text = fresh and M.toggleCheck(fresh.text, line)
      if text then
        N.update(f.noteId, { text = text })
      end
    end)
    if not ok then
      markBroken(kind, made)
      return refreshBody(f)
    end
    r = made
    f.renderers[kind] = r
    r.frame:SetPoint("TOPLEFT", f.area.content, "TOPLEFT", 2, -2)
  end
  for other, renderer in pairs(f.renderers) do
    renderer.frame:SetShown(other == kind)
  end
  local ok, height = pcall(r.Set, r, note, math.max(40, f:GetWidth() - 28), lookOf(f, note))
  if not ok then
    if kind ~= "blocks" then
      markBroken(kind, height)
      return refreshBody(f)
    end
    ns.Log.warn("note render failed: %s", tostring(height))
    return
  end
  f.area:SetContentHeight(height + 8)
end

-- Background, opacity, border and the auto-hiding chrome (WS.Apply), then the toggle glyph.
function NW.ApplyLook(f, note)
  local style = NW.Style(note)
  WS.Apply(f, style, f.styleParts)
  f.autoHide:SetSelected(style.autoHide)
  return style
end

local function applyChrome(f)
  local note = N.get(f.noteId)
  if not note then
    return
  end
  local w = note.window
  NW.ApplyLook(f, note)
  f:SetScale(w.scale)
  f.title:SetText(N.displayTitle(note))
  f.pin:SetSelected(w.sticky)
  f.grip:SetShown(not w.sticky and not f.minimized)
  f:SetMovable(not w.sticky)
  f:SetResizable(not w.sticky)
  ns.WindowShell.SetEsc(f, not w.sticky and f:IsShown())
end

function NW.Refresh(id)
  local f = NW.byId[id]
  if not f then
    return
  end
  applyChrome(f)
  if f.editing then
    local note = N.get(id)
    if note then
      f.title:SetText(N.displayTitle(note))
      -- An edit made elsewhere (the Notes page) reaches this editor while it is idle.
      if not f.dirty and not f.editor:HasFocus() and f.editor:IsStale(note.text) then
        f.editor:SetValue(note.text)
      else
        f.editor:Restyle()
      end
    end
  else
    refreshBody(f)
  end
end

-- A look change without a note change (global defaults): repaints the frame and only
-- re-renders the text when its colors or shadow depend on the change.
function NW.Restyle(id)
  local f, note = NW.byId[id], N.get(id)
  if not (f and note) then
    return
  end
  local style = NW.ApplyLook(f, note)
  if not f.editing and not f.minimized and f.drawnLook ~= lookKey(style) then
    refreshBody(f)
  end
end

function NW.RestyleAll()
  for id in pairs(NW.byId) do
    NW.Restyle(id)
  end
end

-- patch: { bg = "rrggbb" | false (default), alpha = 0..1, autoHide = bool }
function NW.SetLook(id, patch)
  if N.get(id) then
    N.update(id, { window = patch })
  end
end

function NW.ToggleAutoHide(id)
  local note = N.get(id)
  if note then
    NW.SetLook(id, { autoHide = not NW.Style(note).autoHide })
  end
end

-- "Save as default": this window's look becomes the default of all note windows.
function NW.SaveLookAsDefault(id)
  local note = N.get(id)
  if note then
    WS.SaveDefault("note", NW.Style(note))
  end
end

-- "Reset to default": drops the overrides of this window.
function NW.ResetLook(id)
  if N.get(id) then
    N.update(id, { window = { resetStyle = true } })
  end
end

local function scheduleSave(f)
  f.dirty = true
  ns.Debounce(f, 0.5, function()
    flush(f)
  end)
end

-- Raid-icon popup shared by every markup toolbar (floating window and the
-- docked Notes page); onPick(i) is called when symbol i is clicked.
local iconPicker
function NW.CloseIconPicker()
  if iconPicker and iconPicker:IsShown() then
    iconPicker:Hide()
    return true
  end
  return false
end

function NW.ShowIconPicker(anchor, onPick)
  ns.RichToolbar.ClosePopups()
  if not iconPicker then
    iconPicker = CreateFrame("Frame", "FGNoteIconPicker", UIParent)
    iconPicker:SetFrameStrata("FULLSCREEN_DIALOG")
    iconPicker:SetSize(8 * 24 + 8, 32)
    iconPicker:SetClampedToScreen(true)
    W.Fill(iconPicker, "surface", 1)
    W.Border(iconPicker, "accentDim", 1)
    for i = 1, 8 do
      local b = CreateFrame("Button", nil, iconPicker)
      b:SetSize(22, 22)
      b:SetPoint("LEFT", 4 + (i - 1) * 24, 0)
      local t = b:CreateTexture(nil, "ARTWORK")
      t:SetAllPoints()
      t:SetTexture(M.RAID_ICON .. i)
      b:SetScript(
        "OnClick",
        ns.Wrap("note-icon", function()
          -- Hide() runs OnHide, which clears onPick: take the callback first.
          local pick = iconPicker.onPick
          iconPicker:Hide()
          if pick then
            pick(i)
          end
        end)
      )
      ns.Focus.register(b, function(self)
        self:Click()
      end)
    end
    iconPicker:SetScript("OnHide", function()
      iconPicker.owner = nil
      iconPicker.onPick = nil
    end)
    iconPicker:Hide()
  end
  iconPicker.owner = anchor
  iconPicker.onPick = onPick
  iconPicker:ClearAllPoints()
  iconPicker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  iconPicker:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
  iconPicker:SetShown(not iconPicker:IsShown())
end

-- Toolbar handlers for the code view (RichEditor.NewNoteEditor wires them to the
-- toolbar of Modules/RichToolbar.lua): they wrap the selection (or the caret position)
-- of a CodeEdit widget with markup tags. onEdited() runs after every insert so the
-- caller can debounce its own save the same way it debounces typed changes.
function NW.CodeHandlers(codeEdit, onEdited)
  -- Formats the selection, or the caret position when nothing is selected, as one
  -- undo step. fn(text, a, b, ...) is a Markup.apply* helper working on byte offsets.
  local function format(fn, ...)
    local text = codeEdit:GetValue()
    local a, b = codeEdit:Selection()
    if not a then
      a = M.byteOffset(text, codeEdit:Cursor()) + 1
      b = a - 1
    end
    local new, newA, newB = fn(text, a, b, ...)
    if not new then
      return
    end
    if M.length(new) > N.MAX_TEXT then
      new, newA, newB = text, a, b
    end
    codeEdit:Edit(new, newA, newB)
    onEdited()
  end
  -- Old color ids are written as the tag word of the interface language.
  local function colorWord(value)
    if value:find("^#") or value:find("^class:") then
      return value
    end
    return L["notes.col." .. value]
  end
  return {
    -- level 0 (normal text) would have to remove a prefix, which the helpers cannot do.
    heading = function(level)
      if level ~= 0 then
        format(M.applyPrefix, string.rep("#", level or 1) .. " ")
      end
    end,
    list = function()
      format(M.applyPrefix, "- ")
    end,
    check = function()
      format(M.applyPrefix, "[ ] ")
    end,
    align = function(value)
      format(M.applyAlign, value)
    end,
    bold = function()
      format(M.applyStyle, "bold")
    end,
    italic = function()
      format(M.applyStyle, "italic")
    end,
    size = function(n)
      format(M.applyStyle, "size", n)
    end,
    color = function(value)
      if value then
        format(M.applyStyle, "color", colorWord(value))
      end
    end,
    icon = function(i)
      codeEdit:Insert("{rt" .. i .. "}")
      onEdited()
    end,
    undo = function()
      codeEdit:Undo()
    end,
    redo = function()
      codeEdit:Redo()
    end,
  }
end

-- Smallest size the player can drag the window to. Edit mode needs more room for the
-- menu bar, toolbar and status bar than the plain note does.
local function setBounds(f, minW, minH)
  f.minBounds = { minW, minH }
  if f.SetResizeBounds then
    f:SetResizeBounds(minW, minH, N.WINDOW_MAX_W, N.WINDOW_MAX_H)
  elseif f.SetMinResize then
    f:SetMinResize(minW, minH)
  end
end

-- File > New note and Ctrl+N: an empty note in its own window, ready to type.
function NW.NewNote()
  local note = N.create({})
  if not note then
    ns.Notify(string.format(L["notes.slash.limit"], N.MAX_NOTES), "warning")
    return nil
  end
  NW.Open(note.id, { edit = true })
  return note
end

function NW.SetEditing(id, on)
  local f = NW.byId[id]
  local note = N.get(id)
  if not (f and note) then
    return
  end
  if on and not f.editing then
    f.editing = true
    if f.minimized then
      NW.SetMinimized(id, false)
    end
    setBounds(f, EDIT_MIN_W, EDIT_MIN_H)
    local w, h = f:GetSize()
    if w < EDIT_MIN_W or h < EDIT_MIN_H then
      f:SetSize(math.max(w, EDIT_MIN_W), math.max(h, EDIT_MIN_H))
      saveSize(f)
    end
    f.titleBox.edit:SetText(note.title)
    f.editor:SetValue(note.text)
    f.area:Hide()
    f.editPane:Show()
    f.editor:Focus()
    f.edit:SetSelected(true)
  elseif not on and f.editing then
    flush(f)
    f.editing = false
    f.editPane:Hide()
    setBounds(f, N.WINDOW_MIN_W, N.WINDOW_MIN_H)
    if iconPicker and (iconPicker.owner == f.toolbar.btn.icons or iconPicker.owner == f.toolbar.more) then
      iconPicker:Hide()
    end
    f.chrome.menu:Close()
    ns.RichToolbar.ClosePopups()
    f.titleBox.edit:ClearFocus()
    f.editor:Blur()
    f.area:Show()
    f.edit:SetSelected(false)
  end
  NW.Refresh(id)
end

function NW.SetMinimized(id, on)
  local f = NW.byId[id]
  if not f then
    return
  end
  on = on and true or false
  if on and f.editing then
    NW.SetEditing(id, false)
  end
  f.minimized = on
  local note = N.get(id)
  local h = note and note.window.h or 200
  f:SetHeight(on and HEAD_H or h)
  f.area:SetShown(not on and not f.editing)
  N.update(id, { window = { minimized = on } })
  NW.Refresh(id)
end

function NW.SetSticky(id, on)
  if not N.get(id) then
    return
  end
  N.update(id, { window = { sticky = on and true or false } })
  NW.Refresh(id)
end

-- True while a menu, popup, the appearance panel or the color picker of this window is
-- open: the auto-hiding chrome stays visible then.
function NW.ChromeBusy(f)
  if f.chrome.menu:IsOpen() or (f.toolbar.more and f.toolbar.more:IsOpen()) then
    return true
  end
  for _, kind in ipairs({ "color", "class", "size", "heading", "list" }) do
    local p = ns.RichToolbar.GetPopup(kind)
    if p and p:IsShown() and WS.IsInside(p.owner, f) then
      return true
    end
  end
  if iconPicker and iconPicker:IsShown() and WS.IsInside(iconPicker.owner, f) then
    return true
  end
  return WS.PanelOpenFor(f) or WS.PickerOpenFor(f)
end

-- The appearance panel (color, opacity, auto-hide, default actions) below the title bar button.
function NW.OpenLookPanel(f)
  return WS.OpenPanel(f.look, {
    frame = f,
    kind = "note",
    get = function()
      local note = N.get(f.noteId)
      return note and NW.Style(note) or WS.Defaults("note")
    end,
    set = function(patch)
      NW.SetLook(f.noteId, patch)
    end,
    onSaveDefault = function()
      NW.SaveLookAsDefault(f.noteId)
    end,
    onReset = function()
      NW.ResetLook(f.noteId)
    end,
  })
end

local function newFrame()
  NW.made = NW.made + 1
  local f = CreateFrame("Frame", "FGNoteWindow" .. NW.made, UIParent)
  -- Must render above the main addon window (strata "MEDIUM", see
  -- UI/MainFrame.lua), otherwise this floating editor opens behind it.
  -- "DIALOG" matches the popups in UI/Dialogs.lua for the same reason.
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  setBounds(f, N.WINDOW_MIN_W, N.WINDOW_MIN_H)
  f.renderers = {}
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.shell = ns.WindowShell.Attach(f, { titleHeight = HEAD_H, shadow = true })
  f.border, f.bar, f.barBg, f.title = f.shell.border, f.shell.titleBar, f.shell.barFill, f.shell.titleText

  f.bar:EnableMouse(true)
  f.bar:RegisterForDrag("LeftButton")
  f.bar:SetScript("OnDragStart", function()
    local note = N.get(f.noteId)
    if note and not note.window.sticky then
      WS.Hold(f, "move", true)
      f:StartMoving()
    end
  end)
  f.bar:SetScript(
    "OnDragStop",
    ns.Wrap("note-move", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "move", false)
      savePosition(f)
    end)
  )
  f.bar:EnableMouseWheel(true)
  f.bar:SetScript(
    "OnMouseWheel",
    ns.Wrap("note-scale", function(_, delta)
      if ns.Keys.Matches("windowScale") and f.noteId then
        local note = N.get(f.noteId)
        if note then
          N.update(f.noteId, { window = { scale = note.window.scale + delta * 0.1 } })
          NW.Refresh(f.noteId)
          savePosition(f)
        end
      end
    end)
  )
  f.bar:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["notes.win.scaleTip"])
  end)
  f.bar:SetScript("OnLeave", ns.HideTooltip)

  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "notes.win.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    ns.Wrap("note-close", function()
      f:Hide()
    end)
  )
  f.fold = W.Action(f.bar, { icon = "minus", size = 18, tooltip = "notes.win.fold" })
  f.fold:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
  f.fold:SetScript(
    "OnClick",
    ns.Wrap("note-fold", function()
      NW.SetMinimized(f.noteId, not f.minimized)
    end)
  )
  f.pin =
    W.Action(f.bar, { icon = "pin", size = 18, tooltip = "notes.win.sticky", tooltipText = "notes.win.stickyTip" })
  f.pin:SetPoint("RIGHT", f.fold, "LEFT", -2, 0)
  f.pin:SetScript(
    "OnClick",
    ns.Wrap("note-pin", function()
      local note = N.get(f.noteId)
      if note then
        NW.SetSticky(f.noteId, not note.window.sticky)
      end
    end)
  )
  f.autoHide =
    W.Action(f.bar, { icon = "eye-off", size = 18, tooltip = "wstyle.autoHide", tooltipText = "wstyle.autoHideTip" })
  f.autoHide:SetPoint("RIGHT", f.pin, "LEFT", -2, 0)
  f.autoHide:SetScript(
    "OnClick",
    ns.Wrap("note-autohide", function()
      NW.ToggleAutoHide(f.noteId)
    end)
  )
  f.look = W.Action(f.bar, { icon = "palette", size = 18, tooltip = "wstyle.title" })
  f.look:SetPoint("RIGHT", f.autoHide, "LEFT", -2, 0)
  f.look:SetScript(
    "OnClick",
    ns.Wrap("note-look", function()
      NW.OpenLookPanel(f)
    end)
  )
  f.edit = W.Action(f.bar, { icon = "pencil", size = 18, tooltip = "notes.win.edit" })
  f.edit:SetPoint("RIGHT", f.look, "LEFT", -2, 0)
  f.edit:SetScript(
    "OnClick",
    ns.Wrap("note-edit", function()
      NW.SetEditing(f.noteId, not f.editing)
    end)
  )
  f.open = W.Action(f.bar, { icon = "open", size = 18, tooltip = "notes.win.openAddon" })
  f.open:SetPoint("RIGHT", f.edit, "LEFT", -2, 0)
  f.open:SetScript(
    "OnClick",
    ns.Wrap("note-open-addon", function()
      if f.noteId then
        ns.Main.Show("notes/" .. f.noteId)
      end
    end)
  )
  f.title:ClearAllPoints()
  f.title:SetPoint("LEFT", 6, 0)
  f.title:SetPoint("RIGHT", f.open, "LEFT", -4, 0)

  f.area = W.ScrollArea(f)
  f.area:SetPoint("TOPLEFT", 4, -(HEAD_H + 4))
  f.area:SetPoint("BOTTOMRIGHT", -4, 4)

  f.editPane = CreateFrame("Frame", nil, f)
  f.editPane:SetPoint("TOPLEFT", 6, -(HEAD_H + 6))
  f.editPane:SetPoint("BOTTOMRIGHT", -6, 6)
  f.editPane:Hide()
  f.titleBox = W.EditBox(f.editPane, {
    placeholder = "notes.edit.title",
    height = 24,
    onChange = function()
      scheduleSave(f)
    end,
    onEnter = function()
      flush(f)
    end,
  })
  f.titleBox.edit:SetMaxLetters(N.MAX_TITLE)
  f.editor = ns.RichEditor.NewNoteEditor(f.editPane, {
    getNote = function()
      return f.noteId and N.get(f.noteId)
    end,
    onChange = function()
      scheduleSave(f)
    end,
    onSave = function()
      flush(f)
    end,
    onFocus = function()
      NW.linkTarget = f
    end,
    onNew = NW.NewNote,
  })
  f.code = f.editor.code
  f.toolbar = f.editor.toolbar
  f.chrome = ns.NoteChrome.Build(f.editPane, f.editor, {
    titleBox = f.titleBox,
    getId = function()
      return f.noteId
    end,
    onNew = NW.NewNote,
    onClose = function()
      f:Hide()
    end,
    windowStyle = {
      openPanel = function()
        NW.OpenLookPanel(f)
      end,
      autoHide = function()
        local note = N.get(f.noteId)
        return note ~= nil and NW.Style(note).autoHide
      end,
      toggleAutoHide = function()
        NW.ToggleAutoHide(f.noteId)
      end,
      saveDefault = function()
        NW.SaveLookAsDefault(f.noteId)
      end,
      reset = function()
        NW.ResetLook(f.noteId)
      end,
    },
    extras = {
      {
        key = "notes.win.openAddon",
        onClick = function()
          if f.noteId then
            ns.Main.Show("notes/" .. f.noteId)
          end
        end,
      },
    },
  })

  f.grip = CreateFrame("Button", nil, f)
  f.grip:SetSize(14, 14)
  f.grip:SetPoint("BOTTOMRIGHT", -1, 1)
  f.grip:SetFrameLevel(f:GetFrameLevel() + 10)
  f.grip.tex = f.grip:CreateTexture(nil, "OVERLAY")
  f.grip.tex:SetAllPoints()
  f.grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  f.grip:SetScript("OnMouseDown", function()
    WS.Hold(f, "size", true)
    f:StartSizing("BOTTOMRIGHT")
  end)
  f.grip:SetScript(
    "OnMouseUp",
    ns.Wrap("note-size", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "size", false)
      saveSize(f)
      savePosition(f)
      NW.Refresh(f.noteId)
    end)
  )
  f.grip:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["notes.win.grip"])
  end)
  f.grip:SetScript("OnLeave", ns.HideTooltip)

  -- What WS.Apply restyles: the fills, the border and everything that auto-hides. The note
  -- text (f.area, the editor body) is content and never fades.
  f.styleParts = {
    bg = { f.bg },
    bars = { f.barBg },
    border = f.border,
    shadow = f.shell.shadow,
    chrome = { f.bar, f.grip, f.chrome.menu, f.toolbar, f.chrome.status, f.titleBox },
    focus = { f.titleBox.edit },
    busy = function()
      return NW.ChromeBusy(f)
    end,
  }

  f:SetScript("OnSizeChanged", function()
    if f.noteId and not f.editing then
      ns.Debounce(f.area, 0.1, function()
        if f.noteId then
          refreshBody(f)
        end
      end)
    end
  end)
  f:SetScript(
    "OnHide",
    ns.Wrap("note-hide", function()
      flush(f)
      f.editor:Blur()
      ns.WindowShell.SetEsc(f, false)
      ns.RichToolbar.ClosePopups()
      NW.CloseIconPicker()
      if WS.PanelOpenFor(f) then
        WS.ClosePanel()
      end
      local id = f.noteId
      if id then
        NW.byId[id] = nil
        f.noteId = nil
        f.editing = false
        f.minimized = false
        f.editPane:Hide()
        setBounds(f, N.WINDOW_MIN_W, N.WINDOW_MIN_H)
        f.area:Show()
        f.edit:SetSelected(false)
        if N.get(id) then
          N.update(id, { window = { open = false } })
        end
        NW.pool[#NW.pool + 1] = f
      end
    end)
  )
  f:Hide()
  return f
end

-- Public API ----------------------------------------------------------------------

function NW.IsOpen(id)
  return NW.byId[id] ~= nil
end

function NW.Open(id, opts)
  local note = N.get(id)
  if not note then
    return nil
  end
  if not (opts and opts.restore) then
    N.setLastOpened(id)
  end
  local f = NW.byId[id]
  local fresh = f == nil
  if not f then
    f = table.remove(NW.pool) or newFrame()
    f.noteId = id
    NW.byId[id] = f
    local w = note.window
    f.minimized = w.minimized
    f:SetScale(w.scale)
    f:SetSize(w.w, w.minimized and HEAD_H or w.h)
    place(f, w)
    f.area:SetShown(not w.minimized)
    f:Show()
    if not w.open then
      N.update(id, { window = { open = true } })
    end
  end
  f:Raise()
  NW.Refresh(id)
  if fresh then
    -- A pooled frame may still be faded from its last note: show the chrome, it hides again by itself.
    WS.Reveal(f)
  end
  if opts and opts.edit then
    NW.SetEditing(id, true)
  end
  return f
end

function NW.Close(id)
  local f = NW.byId[id]
  if f then
    f:Hide()
  end
end

function NW.Toggle(id)
  if NW.IsOpen(id) then
    NW.Close(id)
  else
    NW.Open(id)
  end
end

function NW.CloseAll()
  local n = 0
  for _, f in pairs(NW.byId) do
    f:Hide()
    n = n + 1
  end
  return n
end

function NW.OpenCount()
  local n = 0
  for _ in pairs(NW.byId) do
    n = n + 1
  end
  return n
end

-- Re-draws every open window (renderer or font setting changed).
function NW.RefreshAll()
  for id in pairs(NW.byId) do
    NW.Refresh(id)
  end
end

-- Opens windows that were open at logout, the first ten right away.
function NW.RestoreAll()
  local pending = {}
  for _, note in ipairs(N.root().items) do
    if type(note.window) == "table" and note.window.open then
      pending[#pending + 1] = note.id
    end
  end
  -- A restore is not "the player opened this note": lastOpened stays as it was.
  for i, id in ipairs(pending) do
    if i <= 10 then
      NW.Open(id, { restore = true })
    else
      C_Timer.After((i - 10) * 0.1, function()
        NW.Open(id, { restore = true })
      end)
    end
  end
end

-- Login: the windows that were open at logout come back only when the player asked for it
-- (settings.reopenNoteWindows). Otherwise the saved open flags are dropped, so the list
-- does not report windows that are not there.
function NW.RestoreOnLogin()
  if ns.db.settings.reopenNoteWindows == true then
    NW.RestoreAll()
    return
  end
  for _, note in ipairs(N.root().items) do
    if type(note.window) == "table" then
      note.window.open = false
    end
  end
end

function NW.FlushAll()
  for _, f in pairs(NW.byId) do
    flush(f)
  end
end

local function matches(rest)
  return N.findByTitle(rest)
end

-- /fg note ...
function NW.Slash(rest)
  rest = U.trim(rest)
  local cmd, arg = rest:match("^(%S+)%s*(.-)$")
  cmd = cmd and cmd:lower()
  if rest == "" then
    ns.Notify(L["notes.slash.usage"], "info")
    ns.Main.Show("notes")
  elseif cmd == "new" or cmd == "neu" then
    local note, why = N.create({ title = arg })
    if not note then
      ns.Notify(string.format(L["notes.slash.limit"], N.MAX_NOTES), "warning")
      return why
    end
    NW.Open(note.id, { edit = true })
  elseif cmd == "close" or cmd == "schliessen" then
    if arg:lower() == "all" or arg:lower() == "alle" then
      ns.Notify(string.format(L["notes.slash.closed"], NW.CloseAll()), "success")
    else
      local note = matches(arg)
      if note then
        NW.Close(note.id)
      else
        ns.Notify(L["notes.slash.none"], "warning")
      end
    end
  elseif cmd == "stick" or cmd == "unstick" or cmd == "anheften" or cmd == "loesen" then
    local note = matches(arg)
    if note then
      NW.SetSticky(note.id, cmd == "stick" or cmd == "anheften")
      NW.Open(note.id)
    else
      ns.Notify(L["notes.slash.none"], "warning")
    end
  else
    local note = matches(rest)
    if note then
      NW.Open(note.id)
    else
      ns.Notify(L["notes.slash.none"], "warning")
    end
  end
end

-- Shift-click on an item/spell/quest link while the editor has focus inserts the link.
function NW.InsertLink(link)
  local f = NW.linkTarget
  if type(link) == "string" and f and f.noteId and f.editing and f.editor:HasFocus() then
    f.editor:InsertLink(link)
  end
end

local function hookLinks()
  local hook, target = rawget(_G, "hooksecurefunc"), rawget(_G, "ChatEdit_InsertLink")
  if hook and target and not NW.linksHooked then
    NW.linksHooked = true
    hook("ChatEdit_InsertLink", function(link)
      ns.Safe("note-link-insert", NW.InsertLink, link)
    end)
  end
end

ns.On("FG_NOTES_CHANGED", function(_, kind, id)
  if kind == "delete" then
    NW.Close(id)
  elseif id and NW.byId[id] then
    NW.Refresh(id)
  elseif not id then
    NW.RefreshAll()
  end
end)
ns.On("FG_UI_REFRESHED", function()
  NW.RefreshAll()
end)
-- Defaults changed on the settings page (or by "Save as default"): windows follow at once.
ns.On("FG_SETTING_CHANGED", function(_, path)
  if WS.AffectsKind(path, "note") then
    NW.RestyleAll()
  end
end)
ns.On("PLAYER_LOGOUT", function()
  NW.FlushAll()
end)
ns.On("PLAYER_LOGIN", function()
  hookLinks()
  if ns.db and ns.db.notes then
    N.pruneTrash()
    -- Delayed so the windows do not compete with the rest of the login work.
    C_Timer.After(1, function()
      ns.Safe("note-restore", NW.RestoreOnLogin)
    end)
  end
end)
