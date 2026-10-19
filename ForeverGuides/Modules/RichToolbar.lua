-- Toolbar widgets for the note editor, laid out like a desktop editor's formatting
-- bar: a heading dropdown, a list dropdown (bullets, checkboxes), toggle buttons with
-- a visible on/mixed state (bold, italic, align left / center / right), a size popup,
-- one color button with a palette popup, one class button with a class icon popup,
-- symbols, undo, redo and the Code toggle. The buttons sit centered; when the bar is too narrow the least important ones move
-- into a "..." menu. Shared by the floating note window and the Notes page.
--
--   local tb = RT.Build(parent, handlers)
--   tb:SetState({ bold = true|false|"mixed", italic = ..., size = n|"mixed",
--                 color = id|"mixed"|nil, heading = 0..3|"mixed", list = bool|"mixed",
--                 checkbox = bool|"mixed", align = "left"|"center"|"right"|"mixed",
--                 canUndo = bool, canRedo = bool })
--                                                  repaints the active states
--   tb:SetHandlers(handlers)  tb:SetContext({ fg, bg, classHex, classColors })
--   tb:Layout(width)  centers the buttons, collapses the rest (tb.hiddenIds)
--
-- handlers: heading(level), list(), check(), bold(), italic(), align(value), size(n),
-- color(value, kind), icon(i), undo(), redo(), mode(). align gets "left", "center" or
-- "right"; pressing the active one again clears it (the handler decides).
-- tb:SetMode("normal"|"code") shows the state of the Code toggle at the right end. color: value is an old color id ("red"), "#rrggbb" or
-- "class:TOKEN", or nil for "default color"; kind is "color", "class" or "reset".
-- Missing handlers do nothing. Popups hand the picked value to their callback after
-- they closed (Hide() clears the callback, so it is copied first).
local _, ns = ...
local W, L, Theme, U, M = ns.W, ns.L, ns.Theme, ns.U, ns.Markup
local IconDraw = ns.IconDraw

local RT = {}
ns.RichToolbar = RT

RT.SIZES = { 10, 12, 14, 16, 18, 20, 24, 28, 32, 40 }

-- The six old colors first (theme aware), then 24 picked colors in four rows:
-- bright, saturated, soft, neutral and purple tones.
-- stylua: ignore
RT.PALETTE = {
  "red", "yellow", "green", "blue", "gray", "class",
  "#ff5a52", "#ff9f43", "#ffd75e", "#7fdc8a", "#5fd3d8", "#7db8ff",
  "#e03131", "#f08c00", "#f2c200", "#2f9e44", "#1098ad", "#1c7ed6",
  "#ffa8a8", "#ffc078", "#ffec99", "#b2f2bb", "#99e9f2", "#a5d8ff",
  "#da77f2", "#a569ff", "#f06595", "#ffffff", "#868e96", "#343a40",
}

ns.AddLocale("enUS", {
  ["notes.tb.bold"] = "Bold",
  ["notes.tb.italic"] = "Italic",
  ["notes.tb.boldTip"] = "Ctrl+B. A thick outline in the game.\nApplies to selection or next text.",
  ["notes.tb.italicTip"] = "Ctrl+I. Skurri decorative font in the game.\nApplies to selection or next text.",
  ["notes.tb.alignLeft"] = "Align left",
  ["notes.tb.alignCenter"] = "Align center",
  ["notes.tb.alignRight"] = "Align right",
  ["notes.tb.alignLeftTip"] = "Ctrl+L, lines of the selection.",
  ["notes.tb.alignCenterTip"] = "Ctrl+E, lines of the selection.",
  ["notes.tb.alignRightTip"] = "Ctrl+R, lines of the selection.",
  ["notes.tb.size"] = "Text size",
  ["notes.tb.sizeTip"] = "Size for the selection or the next text.",
  ["notes.tb.color"] = "Text color",
  ["notes.tb.colorTip"] = "Opens the palette, the bar shows the color at the cursor.",
  ["notes.tb.colorDefault"] = "Default color",
  ["notes.tb.class"] = "Class color",
  ["notes.tb.classTip"] = "Colors the text in the color of a class.",
  ["notes.tb.mode"] = "Code view",
  ["notes.tb.modeTip"] = "Raw text with tags instead of finished text.\nSame button switches back.",
  ["notes.tb.stateOn"] = "on",
  ["notes.tb.stateOff"] = "off",
  ["notes.tb.stateMixed"] = "mixed",
  ["notes.tb.h0"] = "Normal text",
  ["notes.tb.h1"] = "Heading 1",
  ["notes.tb.h2"] = "Heading 2",
  ["notes.tb.h3"] = "Heading 3",
  ["notes.tb.lists"] = "Lists",
  ["notes.tb.listsTip"] = "Turns the lines of the selection into a list.",
  ["notes.tb.listBullet"] = "Bulleted list",
  ["notes.tb.listCheck"] = "Checkboxes",
  ["notes.tb.more"] = "More",
  ["notes.pal.red"] = "Red",
  ["notes.pal.yellow"] = "Yellow",
  ["notes.pal.green"] = "Green",
  ["notes.pal.blue"] = "Blue",
  ["notes.pal.gray"] = "Gray",
  ["notes.pal.class"] = "Your class",
})

ns.AddLocale("deDE", {
  ["notes.tb.bold"] = "Fett",
  ["notes.tb.italic"] = "Kursiv",
  ["notes.tb.boldTip"] = "Strg+B. Im Spiel als dicker Umriss.\nGilt für Auswahl oder nächsten Text.",
  ["notes.tb.italicTip"] = "Strg+I. Im Spiel in Zierschrift (Skurri).\nGilt für Auswahl oder nächsten Text.",
  ["notes.tb.alignLeft"] = "Linksbündig",
  ["notes.tb.alignCenter"] = "Zentriert",
  ["notes.tb.alignRight"] = "Rechtsbündig",
  ["notes.tb.alignLeftTip"] = "Strg+L, Zeilen der Auswahl.",
  ["notes.tb.alignCenterTip"] = "Strg+E, Zeilen der Auswahl.",
  ["notes.tb.alignRightTip"] = "Strg+R, Zeilen der Auswahl.",
  ["notes.tb.size"] = "Schriftgröße",
  ["notes.tb.sizeTip"] = "Größe für Auswahl oder nächsten Text.",
  ["notes.tb.color"] = "Textfarbe",
  ["notes.tb.colorTip"] = "Öffnet die Palette, der Balken zeigt die Farbe am Cursor.",
  ["notes.tb.colorDefault"] = "Standardfarbe",
  ["notes.tb.class"] = "Klassenfarbe",
  ["notes.tb.classTip"] = "Färbt den Text in der Farbe einer Klasse.",
  ["notes.tb.mode"] = "Code-Ansicht",
  ["notes.tb.modeTip"] = "Rohtext mit Tags statt fertigem Text.\nDerselbe Knopf schaltet zurück.",
  ["notes.tb.stateOn"] = "an",
  ["notes.tb.stateOff"] = "aus",
  ["notes.tb.stateMixed"] = "gemischt",
  ["notes.tb.h0"] = "Standardtext",
  ["notes.tb.h1"] = "Überschrift 1",
  ["notes.tb.h2"] = "Überschrift 2",
  ["notes.tb.h3"] = "Überschrift 3",
  ["notes.tb.lists"] = "Listen",
  ["notes.tb.listsTip"] = "Macht aus den Zeilen der Auswahl eine Liste.",
  ["notes.tb.listBullet"] = "Aufzählung",
  ["notes.tb.listCheck"] = "Kästchen",
  ["notes.tb.more"] = "Mehr",
  ["notes.pal.red"] = "Rot",
  ["notes.pal.yellow"] = "Gelb",
  ["notes.pal.green"] = "Grün",
  ["notes.pal.blue"] = "Blau",
  ["notes.pal.gray"] = "Grau",
  ["notes.pal.class"] = "Deine Klasse",
})

-- Colors ------------------------------------------------------------------------------

local DEFAULT_CTX = { fg = "f3eee2", bg = "1a1a1a" }

-- The color a swatch shows for a color id: a picked color as it is, the old
-- ids and the player's class the way the note shows them.
function RT.swatchHex(value, ctx)
  ctx = ctx or DEFAULT_CTX
  if type(value) ~= "string" then
    return ctx.fg
  end
  local raw = value:match("^#?(%x%x%x%x%x%x)$")
  if raw then
    return raw:lower()
  end
  local token = value:match("^class:(%u+)$")
  if token then
    return (ctx.classColors and ctx.classColors[token]) or M.CLASS_HEX[token] or ctx.fg
  end
  return M.colorHex(value, ctx)
end

local function playerClass()
  local ok, _, token = pcall(UnitClass, "player")
  return ok and token or nil
end

local function className(token)
  local R = ns.RefLogic
  return R and R.className and R.className(token) or token
end

-- Glyphs (12 x 12 grid, see UI/DesktopIcons.lua) ------------------------------------------

IconDraw.register("list-bullet", function(p)
  for row = 0, 2 do
    p:Rect(1, 2 + row * 3, 2, 2)
    p:Rect(5, 2 + row * 3, 6, 2)
  end
end)

IconDraw.register("list-check", function(p)
  p:Outline(1, 1, 4, 4)
  p:Rect(2, 2, 2, 2, "accent2")
  p:Rect(6, 2, 5, 2)
  p:Outline(1, 7, 4, 4)
  p:Rect(6, 8, 5, 2)
end)

-- Paragraph alignment: four bars of two lengths, flush left, centered, flush right.
local ALIGN_BARS = { 10, 6, 10, 6 }
for glyph, place in pairs({
  ["align-left"] = function()
    return 1
  end,
  ["align-center"] = function(len)
    return math.floor((12 - len) / 2)
  end,
  ["align-right"] = function(len)
    return 11 - len
  end,
}) do
  IconDraw.register(glyph, function(p)
    for row, len in ipairs(ALIGN_BARS) do
      p:Rect(place(len), 1 + (row - 1) * 3, len, 2)
    end
  end)
end

IconDraw.register("symbol", function(p)
  p:Rect(5, 1, 2, 10)
  p:Rect(1, 5, 10, 2)
  p:Line(2, 2, 9, 9)
  p:Line(2, 9, 9, 2)
end)

-- Toggle button ---------------------------------------------------------------------------

-- opts: glyph (text label), icon (a name of ns.UI_ICONS, else an IconDraw glyph, shown instead of
-- a label), level (the label sits right of the icon and shows a short value), chevron (small arrow
-- for a dropdown), tooltip / tooltipText (locale keys), onClick, size (height, base px), width.
-- b:SetState(true|false|"mixed", glyph?, icon?). The state shows as fill, border and a
-- bar along the bottom edge (full width = on, short = mixed), not only as color.
function RT.Toggle(parent, opts)
  local size = opts.size or 24
  local width = opts.width or size
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, ns.Desktop.scaled(size))
  b.fgState = false
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  local shift = opts.chevron and -4 or 0
  b.label = b:CreateFontString(nil, "OVERLAY")
  b.label:SetPoint("CENTER", shift + (opts.level and 9 or 0), 1)
  if opts.icon then
    if ns.UI_ICONS[opts.icon] then
      b.icon = W.Glyph(b, opts.icon, 14, "textSecondary")
    else
      b.icon = IconDraw.new(b, 14)
      b.icon:Draw(opts.icon)
    end
    b.icon:SetPoint("CENTER", shift + (opts.level and -6 or 0), 1)
  end
  if opts.chevron then
    b.chevron = IconDraw.new(b, 8)
    b.chevron:SetPoint("RIGHT", -4, -1)
    b.chevron:Draw("chevron-down")
  end
  b.ringOn = W.Border(b, "accent2", 1, 2)
  b.ringMixed = W.Border(b, "accentDim", 1, 1)
  b.bar = b:CreateTexture(nil, "OVERLAY")
  b.bar:SetHeight(2)
  b.bar:SetPoint("BOTTOMLEFT", 3, 2)
  b.bar:SetPoint("BOTTOMRIGHT", -3, 2)
  b.dash = b:CreateTexture(nil, "OVERLAY")
  b.dash:SetSize(math.max(4, math.floor(width / 3)), 2)
  b.dash:SetPoint("BOTTOM", 0, 2)
  local hover = false
  local function paint()
    local state = b.fgState
    local ar, ag, ab = Theme.rgb("accent2")
    local tint = "textSecondary"
    if state == true then
      b.bg:SetColorTexture(Theme.color("surface3"))
      tint = "accent"
    elseif state == "mixed" then
      b.bg:SetColorTexture(Theme.color("surface2"))
    elseif hover then
      b.bg:SetColorTexture(Theme.color("surface2"))
      tint = "text"
    else
      b.bg:SetColorTexture(0, 0, 0, 0)
    end
    b.label:SetTextColor(Theme.color(tint))
    if b.icon then
      if b.icon.SetColorToken then
        b.icon:SetColorToken(tint)
      else
        b.icon:SetTint(tint)
      end
    end
    if b.chevron then
      b.chevron:SetTint(tint)
    end
    b.ringOn.show(state == true)
    b.ringMixed.show(state == "mixed")
    b.bar:SetColorTexture(ar, ag, ab, 1)
    b.bar:SetShown(state == true)
    b.dash:SetColorTexture(ar, ag, ab, 1)
    b.dash:SetShown(state == "mixed")
  end
  ns.Bind(b, function()
    b:SetHeight(ns.Desktop.scaled(size))
    Theme.applyFont(b.label, "ui", "body")
    paint()
  end)
  -- Only after the bind: a FontString without a font cannot take text in the client.
  b.label:SetText(opts.glyph or "")
  function b:SetState(state, glyph, icon)
    if state ~= true and state ~= "mixed" then
      state = false
    end
    self.fgState = state
    if glyph then
      self.label:SetText(glyph)
    end
    if icon and self.icon and self.icon.glyph ~= icon then
      self.icon:Draw(icon)
    end
    paint()
  end
  b:SetScript("OnEnter", function(self)
    hover = true
    paint()
    if opts.tooltip then
      local key = self.fgState == true and "notes.tb.stateOn"
        or (self.fgState == "mixed" and "notes.tb.stateMixed" or "notes.tb.stateOff")
      local tip = opts.tooltipText and (L[opts.tooltipText] .. " ") or ""
      ns.ShowTooltip(self, L[opts.tooltip] .. " (" .. L[key] .. ")", tip ~= "" and tip or nil)
    end
  end)
  b:SetScript("OnLeave", function()
    hover = false
    paint()
    ns.HideTooltip()
  end)
  b:SetScript(
    "OnClick",
    ns.Wrap("note-toggle", function()
      if opts.onClick then
        opts.onClick()
      end
    end)
  )
  ns.Focus.register(b, function(self)
    self:Click()
  end)
  return b
end

-- Popups ------------------------------------------------------------------------------------

local popups, blocker = {}, nil

function RT.ClosePopups()
  local closed = false
  for _, p in pairs(popups) do
    if p:IsShown() then
      p:Hide()
      closed = true
    end
  end
  if blocker then
    blocker:Hide()
  end
  return closed
end

local function getBlocker()
  if not blocker then
    blocker = CreateFrame("Button", nil, UIParent)
    blocker:SetAllPoints(UIParent)
    blocker:SetFrameStrata("FULLSCREEN")
    blocker:SetScript("OnClick", RT.ClosePopups)
    blocker:Hide()
  end
  return blocker
end

local function moveFocus(p, step)
  local n = #p.items
  if n == 0 then
    return
  end
  local index = 0
  for i, item in ipairs(p.items) do
    if item == ns.Focus.current then
      index = i
    end
  end
  index = ((index - 1 + step) % n) + 1
  ns.Focus.set(p.items[index])
end

local function newPopup(kind, name, w, h)
  local p = CreateFrame("Frame", name, UIParent)
  p.kind = kind
  p:SetFrameStrata("FULLSCREEN_DIALOG")
  p:SetSize(w, h)
  p:SetClampedToScreen(true)
  p:EnableMouse(true)
  W.Fill(p, "surface", 1)
  W.Border(p, "accentDim", 1)
  p.items = {}
  p:SetScript("OnHide", function(self)
    self.owner, self.onPick = nil, nil
    self:EnableKeyboard(false)
    if blocker then
      blocker:Hide()
    end
  end)
  p:SetScript(
    "OnKeyDown",
    ns.Wrap("note-popup-key", function(self, key)
      local used = true
      if key == "ESCAPE" then
        RT.ClosePopups()
      elseif key == "LEFT" or key == "UP" then
        moveFocus(self, -1)
      elseif key == "RIGHT" or key == "DOWN" then
        moveFocus(self, 1)
      elseif key == "TAB" then
        moveFocus(self, IsShiftKeyDown() and -1 or 1)
      elseif (key == "ENTER" or key == "SPACE") and ns.Focus.current and ns.Focus.current:GetParent() == self then
        ns.Focus.activate()
      else
        used = false
      end
      ns.PropagateKeys(self, not used)
    end)
  )
  p:Hide()
  popups[kind] = p
  return p
end

-- Picks `value`: closes the popup first, then calls the callback it held.
local function pick(p, value, kind)
  local callback = p.onPick
  RT.ClosePopups()
  if callback then
    callback(value, kind)
  end
end

local function makeItem(p, size)
  local b = CreateFrame("Button", nil, p)
  b:SetSize(size, size)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  b.ring = W.Border(b, "accent2", 1, 2)
  b.ring.show(false)
  b.edge = W.Border(b, "white", 0.3, 1)
  ns.Focus.register(b, function(self)
    self:Click()
  end)
  p.items[#p.items + 1] = b
  return b
end

local function buildColor()
  local cols, cell, pad = 6, 25, 6
  local rows = math.ceil(#RT.PALETTE / cols)
  local p = newPopup("color", "FGRichColorPopup", pad * 2 + cols * cell - 3, pad * 2 + rows * cell - 3 + 30)
  p.swatches = {}
  for i, value in ipairs(RT.PALETTE) do
    local b = makeItem(p, cell - 3)
    b:SetPoint("TOPLEFT", pad + ((i - 1) % cols) * cell, -(pad + math.floor((i - 1) / cols) * cell))
    b.value = value
    b:SetScript(
      "OnClick",
      ns.Wrap("note-color-pick", function()
        pick(p, value, "color")
      end)
    )
    b:SetScript("OnEnter", function(self)
      local legacy = value:sub(1, 1) ~= "#"
      ns.ShowTooltip(self, legacy and L["notes.pal." .. value] or value:upper())
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    p.swatches[i] = b
  end
  local reset = W.Button(p, {
    key = "notes.tb.colorDefault",
    width = cols * cell - 3,
    height = 22,
    onClick = function()
      pick(p, nil, "reset")
    end,
  })
  reset:SetPoint("BOTTOMLEFT", pad, pad)
  p.items[#p.items + 1] = reset
  p.reset = reset
  function p:Refresh(current, ctx)
    for _, b in ipairs(self.swatches) do
      b.tex:SetColorTexture(U.hex(RT.swatchHex(b.value, ctx)))
      b.ring.show(b.value == current)
    end
  end
  return p
end

local function buildClass()
  local size, gap, pad = 32, 4, 6
  local p = newPopup("class", "FGRichClassPopup", pad * 2 + 3 * size + 2 * gap, pad * 2 + 3 * size + 2 * gap)
  p.buttons = {}
  for i, token in ipairs(M.CLASS_ORDER) do
    local b = makeItem(p, size)
    b:SetPoint("TOPLEFT", pad + ((i - 1) % 3) * (size + gap), -(pad + math.floor((i - 1) / 3) * (size + gap)))
    b.value = "class:" .. token
    b.tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if coords then
      b.tex:SetTexCoord(unpack(coords))
    end
    b:SetScript(
      "OnClick",
      ns.Wrap("note-class-pick", function()
        pick(p, "class:" .. token, "class")
      end)
    )
    b:SetScript("OnEnter", function(self)
      ns.ShowTooltip(self, className(token))
    end)
    b:SetScript("OnLeave", ns.HideTooltip)
    p.buttons[i] = b
  end
  function p:Refresh(current)
    for _, b in ipairs(self.buttons) do
      b.ring.show(b.value == current)
    end
  end
  return p
end

local function buildSize()
  local rowH, pad = 22, 4
  local p = newPopup("size", "FGRichSizePopup", 56, pad * 2 + #RT.SIZES * rowH)
  p.rows = {}
  for i, n in ipairs(RT.SIZES) do
    local r = CreateFrame("Button", nil, p)
    r:SetHeight(rowH)
    r:SetPoint("TOPLEFT", pad, -(pad + (i - 1) * rowH))
    r:SetPoint("TOPRIGHT", -pad, -(pad + (i - 1) * rowH))
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0)
    r.text = W.Text(r, { text = tostring(n), role = "ui", justify = "CENTER" })
    r.text:SetPoint("CENTER")
    r.value = n
    r:SetScript("OnEnter", function()
      r.hl:SetColorTexture(1, 1, 1, 0.08)
    end)
    r:SetScript("OnLeave", function()
      r.hl:SetColorTexture(1, 1, 1, 0)
    end)
    r:SetScript(
      "OnClick",
      ns.Wrap("note-size-pick", function()
        pick(p, n, "size")
      end)
    )
    ns.Focus.register(r, function(self)
      self:Click()
    end)
    p.items[#p.items + 1] = r
    p.rows[i] = r
  end
  function p:Refresh(current)
    for _, r in ipairs(self.rows) do
      W.SetColor(r.text, r.value == current and "accent" or "text")
    end
  end
  return p
end

-- A list of labeled rows (heading levels, list kinds). The current row carries a bar
-- on its left edge next to the accent color.
local function buildChoice(kind, name, rows)
  local rowH, pad = 24, 4
  local p = newPopup(kind, name, 156, pad * 2 + #rows * rowH)
  p.rows = {}
  for i, def in ipairs(rows) do
    local r = CreateFrame("Button", nil, p)
    r:SetHeight(rowH)
    r:SetPoint("TOPLEFT", pad, -(pad + (i - 1) * rowH))
    r:SetPoint("TOPRIGHT", -pad, -(pad + (i - 1) * rowH))
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0)
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetPoint("TOPLEFT", 0, -3)
    r.mark:SetPoint("BOTTOMLEFT", 0, 3)
    r.mark:SetWidth(2)
    r.mark:Hide()
    r.text = W.Text(r, { key = def.key, role = "ui", justify = "LEFT" })
    r.text:SetPoint("LEFT", 10, 0)
    r.value = def.value
    r:SetScript("OnEnter", function()
      r.hl:SetColorTexture(1, 1, 1, 0.08)
    end)
    r:SetScript("OnLeave", function()
      r.hl:SetColorTexture(1, 1, 1, 0)
    end)
    r:SetScript(
      "OnClick",
      ns.Wrap("note-choice-pick", function()
        pick(p, def.value, kind)
      end)
    )
    ns.Focus.register(r, function(self)
      self:Click()
    end)
    p.items[#p.items + 1] = r
    p.rows[i] = r
  end
  function p:Refresh(current)
    for _, r in ipairs(self.rows) do
      local on = r.value == current
      W.SetColor(r.text, on and "accent" or "text")
      r.mark:SetColorTexture(Theme.color("accent2"))
      r.mark:SetShown(on)
    end
  end
  return p
end

local function buildHeading()
  return buildChoice("heading", "FGRichHeadingPopup", {
    { value = 0, key = "notes.tb.h0" },
    { value = 1, key = "notes.tb.h1" },
    { value = 2, key = "notes.tb.h2" },
    { value = 3, key = "notes.tb.h3" },
  })
end

local function buildList()
  return buildChoice("list", "FGRichListPopup", {
    { value = "list", key = "notes.tb.listBullet" },
    { value = "check", key = "notes.tb.listCheck" },
  })
end

local BUILDERS = { color = buildColor, class = buildClass, size = buildSize, heading = buildHeading, list = buildList }

-- Opens (or, when already open for this anchor, closes) a popup of kind "color",
-- "class", "size", "heading" or "list" below `anchor`. onPick(value, kind) gets the
-- choice after the popup closed. `current` marks the active value, ctx colors the palette.
function RT.OpenPopup(kind, anchor, onPick, current, ctx)
  local p = popups[kind] or BUILDERS[kind]()
  local wasOpen = p:IsShown() and p.owner == anchor
  RT.ClosePopups()
  if ns.NoteWindow and ns.NoteWindow.CloseIconPicker then
    ns.NoteWindow.CloseIconPicker()
  end
  if wasOpen then
    return nil
  end
  p.owner, p.onPick = anchor, onPick
  p:Refresh(current, ctx or DEFAULT_CTX)
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  p:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
  getBlocker():Show()
  p:Show()
  p:EnableKeyboard(true)
  for _, item in ipairs(p.items) do
    if item.value == current then
      ns.Focus.set(item)
    end
  end
  return p
end

function RT.GetPopup(kind)
  return popups[kind]
end

-- Toolbar ---------------------------------------------------------------------------------------

local GAP, GROUP_GAP = 2, 10 -- pixels between buttons / between groups
local TOOLBAR_HEIGHT = 28

-- A bordered button with a label or icon for the size, color and class popups.
-- b.fgState true / "mixed" outlines it like the toggle buttons.
local function arrowButton(parent, width, tooltipKey, tipTextKey)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, ns.Desktop.scaled(24))
  b.fgState = false
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.edge = W.Border(b, "accentDim", 1, 1)
  local hover = false
  function b:Paint()
    local on, mixed = self.fgState == true, self.fgState == "mixed"
    if on then
      self.bg:SetColorTexture(Theme.color("surface3"))
    elseif mixed or hover then
      self.bg:SetColorTexture(Theme.color("surface2"))
    else
      self.bg:SetColorTexture(0, 0, 0, 0)
    end
    self.edge.set(on and "accent2" or "accentDim", 1)
    self.edge.show(on or mixed or hover)
  end
  b:SetScript("OnEnter", function(self)
    hover = true
    self:Paint()
    ns.ShowTooltip(self, L[tooltipKey], tipTextKey and L[tipTextKey] or nil)
  end)
  b:SetScript("OnLeave", function(self)
    hover = false
    self:Paint()
    ns.HideTooltip()
  end)
  ns.Bind(b, function(self)
    self:SetHeight(ns.Desktop.scaled(24))
    self:Paint()
  end)
  ns.Focus.register(b, function(self)
    self:Click()
  end)
  return b
end

-- Items in toolbar order: group (a separator sits between groups) and rank (the item
-- with the highest rank moves into the "..." menu first; rank 0 never moves).
local ITEMS = {
  { id = "heading", group = 1, rank = 3 },
  { id = "list", group = 1, rank = 4 },
  { id = "bold", group = 2, rank = 0 },
  { id = "italic", group = 2, rank = 0 },
  { id = "alignLeft", group = 3, rank = 5 },
  { id = "alignCenter", group = 3, rank = 5 },
  { id = "alignRight", group = 3, rank = 5 },
  { id = "size", group = 4, rank = 6 },
  { id = "color", group = 4, rank = 7 },
  { id = "class", group = 4, rank = 8 },
  { id = "icons", group = 5, rank = 9 },
  { id = "undo", group = 6, rank = 10 },
  { id = "redo", group = 6, rank = 10 },
  { id = "mode", group = 7, rank = 11 },
}
local MAX_RANK = 11
-- Alignment buttons: toolbar id -> value handed to handlers.align.
local ALIGN_IDS = { alignLeft = "left", alignCenter = "center", alignRight = "right" }

function RT.Build(parent, handlers)
  local tb = CreateFrame("Frame", nil, parent)
  tb:SetHeight(ns.Desktop.scaled(TOOLBAR_HEIGHT))
  tb.handlers = handlers or {}
  tb.state = {}
  tb.btn = {}
  tb.seps = {}
  tb.hiddenIds = {}
  local function call(name, ...)
    local fn = tb.handlers[name]
    if fn then
      fn(...)
    end
  end
  function tb:SetHandlers(h)
    self.handlers = h or {}
  end
  function tb:SetContext(ctx)
    self.ctx = ctx
  end

  local function headingCurrent()
    return type(tb.state.heading) == "number" and tb.state.heading or nil
  end
  local function listCurrent()
    if tb.state.checkbox == true then
      return "check"
    end
    return tb.state.list == true and "list" or nil
  end
  local function colorCurrent()
    return type(tb.state.color) == "string" and tb.state.color or nil
  end
  -- Each opener takes the widget the popup hangs below (a button, or the "..." bar).
  local open = {}
  function open.heading(anchor)
    RT.OpenPopup("heading", anchor, function(value)
      call("heading", value)
    end, headingCurrent(), tb.ctx)
  end
  function open.list(anchor)
    RT.OpenPopup("list", anchor, function(value)
      call(value)
    end, listCurrent(), tb.ctx)
  end
  function open.size(anchor)
    RT.OpenPopup("size", anchor, function(value)
      call("size", value)
    end, type(tb.state.size) == "number" and tb.state.size or nil, tb.ctx)
  end
  function open.color(anchor)
    RT.OpenPopup("color", anchor, function(value, kind)
      call("color", value, kind)
    end, colorCurrent(), tb.ctx)
  end
  function open.class(anchor)
    RT.OpenPopup("class", anchor, function(value, kind)
      call("color", value, kind)
    end, colorCurrent(), tb.ctx)
  end
  function open.icons(anchor)
    ns.NoteWindow.ShowIconPicker(anchor, function(i)
      call("icon", i)
    end)
  end

  tb.btn.heading = RT.Toggle(tb, {
    icon = "heading",
    level = true,
    width = 46,
    chevron = true,
    tooltip = "notes.tb.heading",
    tooltipText = "notes.tb.headingTip",
    onClick = function()
      open.heading(tb.btn.heading)
    end,
  })
  tb.btn.list = RT.Toggle(tb, {
    icon = "list-bullet",
    width = 42,
    chevron = true,
    tooltip = "notes.tb.lists",
    tooltipText = "notes.tb.listsTip",
    onClick = function()
      open.list(tb.btn.list)
    end,
  })
  tb.btn.bold = RT.Toggle(tb, {
    icon = "bold",
    tooltip = "notes.tb.bold",
    tooltipText = "notes.tb.boldTip",
    onClick = function()
      call("bold")
    end,
  })
  tb.btn.italic = RT.Toggle(tb, {
    icon = "italic",
    tooltip = "notes.tb.italic",
    tooltipText = "notes.tb.italicTip",
    onClick = function()
      call("italic")
    end,
  })

  for _, def in ipairs({
    { id = "alignLeft", icon = "align-left" },
    { id = "alignCenter", icon = "align-center" },
    { id = "alignRight", icon = "align-right" },
  }) do
    tb.btn[def.id] = RT.Toggle(tb, {
      icon = def.icon,
      tooltip = "notes.tb." .. def.id,
      tooltipText = "notes.tb." .. def.id .. "Tip",
      onClick = function()
        call("align", ALIGN_IDS[def.id])
      end,
    })
  end

  local size = arrowButton(tb, 44, "notes.tb.size", "notes.tb.sizeTip")
  size.text = W.Text(size, { text = "", role = "ui", justify = "CENTER" })
  size.text:SetPoint("LEFT", 2, 0)
  size.text:SetPoint("RIGHT", -12, 0)
  size.chevron = IconDraw.new(size, 8)
  size.chevron:SetPoint("RIGHT", -4, -1)
  size.chevron:Draw("chevron-down")
  size.chevron:SetTint("textMuted")
  size:SetScript(
    "OnClick",
    ns.Wrap("note-size", function(self)
      open.size(self)
    end)
  )
  tb.btn.size = size

  local color = arrowButton(tb, 28, "notes.tb.color", "notes.tb.colorTip")
  color.letter = W.Text(color, { text = "A", role = "ui", justify = "CENTER" })
  color.letter:SetPoint("CENTER", 0, 2)
  color.bar = color:CreateTexture(nil, "OVERLAY")
  color.bar:SetHeight(4)
  color.bar:SetPoint("BOTTOMLEFT", 5, 4)
  color.bar:SetPoint("BOTTOMRIGHT", -5, 4)
  color:SetScript(
    "OnClick",
    ns.Wrap("note-color", function(self)
      open.color(self)
    end)
  )
  tb.btn.color = color

  local class = arrowButton(tb, 26, "notes.tb.class", "notes.tb.classTip")
  class.icon = class:CreateTexture(nil, "ARTWORK")
  class.icon:SetPoint("TOPLEFT", 3, -3)
  class.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  class.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
  local token = playerClass()
  local coords = token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
  if coords then
    class.icon:SetTexCoord(unpack(coords))
  end
  class:SetScript(
    "OnClick",
    ns.Wrap("note-class", function(self)
      open.class(self)
    end)
  )
  tb.btn.class = class

  tb.btn.icons = W.Action(tb, {
    icon = "star",
    size = 24,
    tooltip = "notes.tb.icons",
    onClick = function(self)
      open.icons(self)
    end,
  })
  -- Undo and redo follow the editor state in tb:SetState (Refresh).
  local function stepButton(icon, tooltip, can, run)
    local b
    b = W.Action(tb, {
      icon = icon,
      size = 24,
      tooltip = tooltip,
      onClick = function()
        if b:IsEnabled() then
          run()
        end
      end,
    })
    function b.Refresh()
      b:SetEnabled(can())
    end
    b.Refresh()
    return b
  end
  tb.btn.undo = stepButton("undo", "notes.tb.undo", function()
    return tb.state.canUndo ~= false
  end, function()
    call("undo")
  end)
  tb.btn.redo = stepButton("redo", "notes.tb.redo", function()
    return tb.state.canRedo ~= false
  end, function()
    call("redo")
  end)
  tb.btn.mode = RT.Toggle(tb, {
    icon = "code",
    tooltip = "notes.tb.mode",
    tooltipText = "notes.tb.modeTip",
    onClick = function()
      call("mode")
    end,
  })
  function tb:SetMode(mode)
    self.mode = mode
    self.btn.mode:SetState(mode == "code")
  end

  -- The "..." menu ----------------------------------------------------------------------
  -- One entry per collapsed button. The items table is refilled by Layout, the menu
  -- reads it when it opens.
  local moreItems = {}
  local function choice(key, checked, fn, extra)
    local item = { key = key, checked = checked, onClick = fn }
    for k, v in pairs(extra or {}) do
      item[k] = v
    end
    return item
  end
  local ENTRY = {}
  function ENTRY.heading()
    local items = {}
    for level = 0, 3 do
      items[#items + 1] = choice("notes.tb.h" .. level, function()
        return (headingCurrent() or 0) == level
      end, function()
        call("heading", level)
      end)
    end
    return { key = "notes.tb.heading", items = items }
  end
  function ENTRY.list()
    return {
      key = "notes.tb.lists",
      items = {
        choice("notes.tb.listBullet", function()
          return listCurrent() == "list"
        end, function()
          call("list")
        end),
        choice("notes.tb.listCheck", function()
          return listCurrent() == "check"
        end, function()
          call("check")
        end),
      },
    }
  end
  function ENTRY.bold()
    return choice("notes.tb.bold", function()
      return tb.state.bold == true
    end, function()
      call("bold")
    end)
  end
  function ENTRY.italic()
    return choice("notes.tb.italic", function()
      return tb.state.italic == true
    end, function()
      call("italic")
    end)
  end
  function ENTRY.size()
    local items = {}
    for _, n in ipairs(RT.SIZES) do
      items[#items + 1] = choice(nil, function()
        return tb.state.size == n
      end, function()
        call("size", n)
      end, { text = tostring(n) })
    end
    return { key = "notes.tb.size", items = items }
  end
  for id, value in pairs(ALIGN_IDS) do
    ENTRY[id] = function()
      return choice("notes.tb." .. id, function()
        return tb.state.align == value
      end, function()
        call("align", value)
      end)
    end
  end
  for _, id in ipairs({ "color", "class", "icons" }) do
    ENTRY[id] = function()
      return choice("notes.tb." .. id, nil, function()
        open[id](tb.more)
      end)
    end
  end
  function ENTRY.undo()
    return choice("notes.tb.undo", nil, function()
      call("undo")
    end, {
      enabled = function()
        return tb.state.canUndo ~= false
      end,
    })
  end
  function ENTRY.redo()
    return choice("notes.tb.redo", nil, function()
      call("redo")
    end, {
      enabled = function()
        return tb.state.canRedo ~= false
      end,
    })
  end
  function ENTRY.mode()
    return choice("notes.tb.mode", function()
      return tb.mode == "code"
    end, function()
      call("mode")
    end)
  end

  local function fillMore(hidden)
    for i = #moreItems, 1, -1 do
      moreItems[i] = nil
    end
    local lastGroup
    for _, it in ipairs(ITEMS) do
      if hidden[it.id] then
        local item = ENTRY[it.id]()
        item.separator = lastGroup ~= nil and lastGroup ~= it.group
        moreItems[#moreItems + 1] = item
        lastGroup = it.group
      end
    end
  end

  local function ensureMore()
    if not tb.more then
      tb.more = W.MenuBar(tb, { { text = "...", items = moreItems } }, { fill = false, height = 24 })
    end
    return tb.more
  end

  -- Layout --------------------------------------------------------------------------------

  local function separator(k)
    local t = tb.seps[k]
    if not t then
      t = tb:CreateTexture(nil, "ARTWORK")
      t:SetWidth(1)
      tb.seps[k] = t
    end
    return t
  end

  -- Centers the buttons in `width` (default: the bar's width). Buttons that do not fit
  -- are hidden, highest rank first, and reachable through the "..." menu.
  function tb:Layout(width)
    local avail = width or tb:GetWidth()
    if not avail or avail <= 0 then
      return
    end
    local more = ensureMore()
    more:Layout()
    local moreW = more.titles[1]:GetWidth()
    local function measure(cut)
      local total, prevGroup = 0, nil
      for _, it in ipairs(ITEMS) do
        if it.rank <= cut then
          if prevGroup then
            total = total + (it.group == prevGroup and GAP or GROUP_GAP)
          end
          total = total + tb.btn[it.id]:GetWidth()
          prevGroup = it.group
        end
      end
      if cut < MAX_RANK then
        total = total + GROUP_GAP + moreW
      end
      return total
    end
    local cut, total = MAX_RANK, measure(MAX_RANK)
    while total > avail and cut > 0 do
      cut = cut - 1
      total = measure(cut)
    end
    local hidden, hiddenIds = {}, {}
    local x, prevGroup, sepCount = math.max(0, math.floor((avail - total) / 2)), nil, 0
    for _, it in ipairs(ITEMS) do
      local b = tb.btn[it.id]
      if it.rank <= cut then
        if prevGroup then
          if it.group == prevGroup then
            x = x + GAP
          else
            sepCount = sepCount + 1
            local t = separator(sepCount)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", tb, "TOPLEFT", x + GROUP_GAP / 2, -5)
            t:SetPoint("BOTTOMLEFT", tb, "BOTTOMLEFT", x + GROUP_GAP / 2, 5)
            t:SetColorTexture(Theme.color("accentDim", 0.6))
            t:Show()
            x = x + GROUP_GAP
          end
        end
        b:ClearAllPoints()
        b:SetPoint("LEFT", tb, "LEFT", x, 0)
        b:Show()
        x = x + b:GetWidth()
        prevGroup = it.group
      else
        b:Hide()
        hidden[it.id] = true
        hiddenIds[#hiddenIds + 1] = it.id
      end
    end
    for k = sepCount + 1, #tb.seps do
      tb.seps[k]:Hide()
    end
    tb.cut, tb.hiddenIds = cut, hiddenIds
    if #hiddenIds > 0 then
      fillMore(hidden)
      more:ClearAllPoints()
      more:SetPoint("LEFT", tb, "LEFT", x + GROUP_GAP, 0)
      more:SetWidth(moreW)
      more:Show()
    else
      more:Close()
      more:Hide()
    end
  end

  tb:SetScript("OnSizeChanged", function(_, w)
    tb:Layout(w)
  end)
  -- Anchors of a hidden parent resolve when it shows; lay out once more then.
  tb:HookScript("OnShow", function()
    tb:Layout()
  end)
  ns.Bind(tb, function()
    tb:SetHeight(ns.Desktop.scaled(TOOLBAR_HEIGHT))
    tb:Layout()
  end)

  function tb:SetState(st)
    st = st or {}
    self.state = st
    local heading = st.heading
    local level = type(heading) == "number" and heading or 0
    self.btn.heading:SetState(heading == "mixed" and "mixed" or level > 0, level > 0 and tostring(level) or "")
    local listState = "mixed"
    if st.list == true or st.checkbox == true then
      listState = true
    elseif st.list ~= "mixed" and st.checkbox ~= "mixed" then
      listState = false
    end
    self.btn.list:SetState(listState, nil, st.checkbox == true and "list-check" or "list-bullet")
    self.btn.bold:SetState(st.bold)
    self.btn.italic:SetState(st.italic)
    for id, value in pairs(ALIGN_IDS) do
      self.btn[id]:SetState(st.align == "mixed" and "mixed" or st.align == value)
    end
    self.btn.size.text:SetText(type(st.size) == "number" and tostring(st.size) or "")
    local c = st.color
    local r, g, b
    if c == "mixed" then
      r, g, b = Theme.rgb("textMuted")
      self.btn.color.bar:SetAlpha(0.5)
    else
      r, g, b = U.hex(RT.swatchHex(c, self.ctx))
      self.btn.color.bar:SetAlpha(1)
    end
    self.btn.color.bar:SetColorTexture(r, g, b, 1)
    self.btn.color.fgState = c == "mixed" and "mixed" or (c and true or false)
    self.btn.class.fgState = type(c) == "string" and c:sub(1, 6) == "class:" or false
    self.btn.color:Paint()
    self.btn.class:Paint()
    self.btn.undo:Refresh()
    self.btn.redo:Refresh()
  end
  tb:SetState({})
  return tb
end
