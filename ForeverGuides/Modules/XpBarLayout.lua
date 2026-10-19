-- Element types of the experience bar for the canvas renderer (Modules/CanvasRender.lua) and the
-- canvas editor: "bar" (layers XP, completed quests, rested), "text" (a template with placeholders
-- of Modules/XpLogic.lua) and "shape" (a rectangle). Also the presets, sample values for the editor
-- and the context the types draw with: ctx.values() returns the value table of XpLogic.Compute.
-- Saved props are repaired on every draw, so a broken layout never raises.
local _, ns = ...
local W, U, L, XL, CL = ns.W, ns.U, ns.L, ns.XpLogic, ns.CanvasLogic

local XB = {}
ns.XpBarLayout = XB

XB.OUTLINES = { "none", "outline", "thick" }
XB.JUSTIFY = { "LEFT", "CENTER", "RIGHT" }
XB.ORIENT = { "horizontal", "vertical" }
XB.TEXTURES = { "solid", "statusbar", "raid" }
XB.TEXTURE_PATH = {
  statusbar = "Interface\\TargetingFrame\\UI-StatusBar",
  raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
XB.SIZE_MIN, XB.SIZE_MAX = 8, 48
XB.MAX_BORDER = 8
-- Padding of the background behind a text, in px.
XB.MAX_BG_PAD = 12
-- Text colors on the bar need this contrast against every layer color (WCAG AA for normal text).
XB.MIN_CONTRAST = 4.5
-- Level of the editor sample values, also the one a "level N" placeholder is inserted with.
XB.SAMPLE_LEVEL = 30

local FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local SPARK_W = 14
local TEMPLATE_KEY = "^@(xpbar%.tpl%.[%w_]+)$"

ns.AddLocale("enUS", {
  ["xpbar.type.bar"] = "Bar",
  ["xpbar.type.text"] = "Text",
  ["xpbar.type.shape"] = "Rectangle",
  ["xpbar.type.bar.desc"] = "The experience bar itself. It fills with your progress to the next level. There is only one.",
  ["xpbar.type.text.desc"] = "A line of text with placeholders such as your level or experience, for example a percentage.",
  ["xpbar.type.shape.desc"] = "A plain colored rectangle, for a divider, a frame or a background behind other elements.",
  ["xpbar.preset.classic"] = "Classic",
  ["xpbar.preset.compact"] = "Compact",
  ["xpbar.preset.narrow"] = "Narrow",
  ["xpbar.preset.detailed"] = "Detailed",
  ["xpbar.tpl.levelTime"] = "This level: {level_time}",
  ["xpbar.tpl.sessionTime"] = "Session: {session_time}",
  ["xpbar.tpl.level"] = "Level {level}",
  ["xpbar.tpl.xp"] = "{xp} / {max} ({remaining})",
  ["xpbar.tpl.pct"] = "{pct}% ({total_pct}%)",
  ["xpbar.tpl.eta"] = "Level up in {eta} ({xph} XP/h)",
  ["xpbar.tpl.quests"] = "Quests {done_pct}%, rested {rested_pct}%",
  ["xpbar.tpl.compact"] = "Level {level}: {xp} / {max} ({pct}%)",
  ["xpbar.tpl.narrow"] = "{pct}%",
  ["xpbar.tpl.sessionXp"] = "Session XP: {session_gain} ({state})",
  ["xpbar.tpl.xph"] = "XP per hour: {xph}",
  ["xpbar.tpl.rested"] = "Rested: {rested} ({rested_pct}%)",
  ["xpbar.tpl.todo"] = "Quests done {done}, open {todo} {overflow}",
  ["xpbar.el.levelTime"] = "Time on level",
  ["xpbar.el.sessionTime"] = "Session time",
  ["xpbar.el.level"] = "Level",
  ["xpbar.el.xp"] = "XP",
  ["xpbar.el.pct"] = "Percent",
  ["xpbar.el.eta"] = "Time to level",
  ["xpbar.el.quests"] = "Quests and rested",
  ["xpbar.el.sessionXp"] = "Session XP",
  ["xpbar.el.xph"] = "XP per hour",
  ["xpbar.el.rested"] = "Rested",
  ["xpbar.el.todo"] = "Open quests",
  ["xpbar.panel.orient"] = "Direction",
  ["xpbar.panel.orient.horizontal"] = "Horizontal",
  ["xpbar.panel.orient.vertical"] = "Vertical",
  ["xpbar.panel.fill"] = "Experience color",
  ["xpbar.panel.quest"] = "Completed quests color",
  ["xpbar.panel.rested"] = "Rested color",
  ["xpbar.panel.bg"] = "Background",
  ["xpbar.panel.border"] = "Border color",
  ["xpbar.panel.borderWidth"] = "Border",
  ["xpbar.panel.texture"] = "Texture",
  ["xpbar.panel.texture.solid"] = "Solid",
  ["xpbar.panel.texture.statusbar"] = "Status bar",
  ["xpbar.panel.texture.raid"] = "Raid bar",
  ["xpbar.panel.spark"] = "Spark at the edge",
  ["xpbar.panel.template"] = "Text with placeholders",
  ["xpbar.panel.insert"] = "Insert placeholder",
  ["xpbar.panel.pick"] = "Choose a placeholder",
  ["xpbar.panel.hint"] = "A placeholder in curly braces shows a value. An unknown name stays visible as typed.",
  ["xpbar.panel.font"] = "Font",
  ["xpbar.panel.size"] = "Size",
  ["xpbar.panel.outline"] = "Outline",
  ["xpbar.panel.outline.none"] = "None",
  ["xpbar.panel.outline.outline"] = "Thin",
  ["xpbar.panel.outline.thick"] = "Thick",
  ["xpbar.panel.color"] = "Text color",
  ["xpbar.panel.justify"] = "Alignment",
  ["xpbar.panel.justify.LEFT"] = "Left",
  ["xpbar.panel.justify.CENTER"] = "Center",
  ["xpbar.panel.justify.RIGHT"] = "Right",
  ["xpbar.panel.shadow"] = "Shadow",
  ["xpbar.panel.shapeColor"] = "Color",
  ["xpbar.panel.alpha"] = "Opacity",
  ["xpbar.panel.contrast"] = "Text and bar background reach only %s:1, 4.5:1 is needed.",
  ["xpbar.panel.textBg"] = "Background",
  ["xpbar.panel.textBgColor"] = "Background color",
  ["xpbar.panel.bgPad"] = "Padding",
})
ns.AddLocale("deDE", {
  ["xpbar.type.bar"] = "Balken",
  ["xpbar.type.text"] = "Text",
  ["xpbar.type.shape"] = "Rechteck",
  ["xpbar.type.bar.desc"] = "Die Erfahrungsleiste selbst. Sie füllt sich mit deinem Fortschritt bis zur nächsten Stufe. Es gibt nur eine.",
  ["xpbar.type.text.desc"] = "Eine Textzeile mit Platzhaltern wie deiner Stufe oder deiner Erfahrung, zum Beispiel ein Prozentwert.",
  ["xpbar.type.shape.desc"] = "Ein einfaches farbiges Rechteck, für eine Trennlinie, einen Rahmen oder einen Hintergrund hinter anderen Elementen.",
  ["xpbar.preset.classic"] = "Klassisch",
  ["xpbar.preset.compact"] = "Kompakt",
  ["xpbar.preset.narrow"] = "Schmal",
  ["xpbar.preset.detailed"] = "Ausführlich",
  ["xpbar.tpl.levelTime"] = "Diese Stufe: {level_time}",
  ["xpbar.tpl.sessionTime"] = "Sitzung: {session_time}",
  ["xpbar.tpl.level"] = "Stufe {level}",
  ["xpbar.tpl.xp"] = "{xp} / {max} ({remaining})",
  ["xpbar.tpl.pct"] = "{pct}% ({total_pct}%)",
  ["xpbar.tpl.eta"] = "Level-Up in {eta} ({xph} EP/h)",
  ["xpbar.tpl.quests"] = "Quests {done_pct}%, ausgeruht {rested_pct}%",
  ["xpbar.tpl.compact"] = "Stufe {level}: {xp} / {max} ({pct}%)",
  ["xpbar.tpl.narrow"] = "{pct}%",
  ["xpbar.tpl.sessionXp"] = "Sitzungs-EP: {session_gain} ({state})",
  ["xpbar.tpl.xph"] = "EP pro Stunde: {xph}",
  ["xpbar.tpl.rested"] = "Ausgeruht: {rested} ({rested_pct}%)",
  ["xpbar.tpl.todo"] = "Quests fertig {done}, offen {todo} {overflow}",
  ["xpbar.el.levelTime"] = "Zeit der Stufe",
  ["xpbar.el.sessionTime"] = "Sitzungszeit",
  ["xpbar.el.level"] = "Stufe",
  ["xpbar.el.xp"] = "Erfahrung",
  ["xpbar.el.pct"] = "Prozent",
  ["xpbar.el.eta"] = "Zeit bis zur Stufe",
  ["xpbar.el.quests"] = "Quests und Ausgeruht",
  ["xpbar.el.sessionXp"] = "Sitzungs-EP",
  ["xpbar.el.xph"] = "EP pro Stunde",
  ["xpbar.el.rested"] = "Ausgeruht",
  ["xpbar.el.todo"] = "Offene Quests",
  ["xpbar.panel.orient"] = "Richtung",
  ["xpbar.panel.orient.horizontal"] = "Waagerecht",
  ["xpbar.panel.orient.vertical"] = "Senkrecht",
  ["xpbar.panel.fill"] = "Farbe Erfahrung",
  ["xpbar.panel.quest"] = "Farbe abgeschlossene Quests",
  ["xpbar.panel.rested"] = "Farbe Ausgeruht",
  ["xpbar.panel.bg"] = "Hintergrund",
  ["xpbar.panel.border"] = "Randfarbe",
  ["xpbar.panel.borderWidth"] = "Rand",
  ["xpbar.panel.texture"] = "Textur",
  ["xpbar.panel.texture.solid"] = "Einfarbig",
  ["xpbar.panel.texture.statusbar"] = "Statusleiste",
  ["xpbar.panel.texture.raid"] = "Schlachtzugsleiste",
  ["xpbar.panel.spark"] = "Funke an der Kante",
  ["xpbar.panel.template"] = "Text mit Platzhaltern",
  ["xpbar.panel.insert"] = "Platzhalter einfügen",
  ["xpbar.panel.pick"] = "Platzhalter wählen",
  ["xpbar.panel.hint"] = "Ein Platzhalter in geschweiften Klammern zeigt einen Wert. Ein unbekannter Name bleibt so sichtbar, wie du ihn getippt hast.",
  ["xpbar.panel.font"] = "Schrift",
  ["xpbar.panel.size"] = "Größe",
  ["xpbar.panel.outline"] = "Umriss",
  ["xpbar.panel.outline.none"] = "Keiner",
  ["xpbar.panel.outline.outline"] = "Dünn",
  ["xpbar.panel.outline.thick"] = "Dick",
  ["xpbar.panel.color"] = "Textfarbe",
  ["xpbar.panel.justify"] = "Ausrichtung",
  ["xpbar.panel.justify.LEFT"] = "Links",
  ["xpbar.panel.justify.CENTER"] = "Mitte",
  ["xpbar.panel.justify.RIGHT"] = "Rechts",
  ["xpbar.panel.shadow"] = "Schatten",
  ["xpbar.panel.shapeColor"] = "Farbe",
  ["xpbar.panel.alpha"] = "Deckkraft",
  ["xpbar.panel.contrast"] = "Text und Leistenhintergrund erreichen nur %s:1, nötig sind 4,5:1.",
  ["xpbar.panel.textBg"] = "Hintergrund",
  ["xpbar.panel.textBgColor"] = "Hintergrundfarbe",
  ["xpbar.panel.bgPad"] = "Abstand",
})

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function hex(v, default)
  local raw = type(v) == "string" and v:match("^#?(%x%x%x%x%x%x)$")
  return raw and raw:lower() or default
end

local function oneOf(v, list, default)
  for _, item in ipairs(list) do
    if v == item then
      return v
    end
  end
  return default
end

local function whole(v, default, lo, hi)
  return finite(v) and U.clamp(math.floor(v + 0.5), lo, hi) or default
end

-- Contrast ratio of two colors ("rrggbb"), 1 to 21.
local function luminance(color)
  local r, g, b = U.hex(color)
  local function channel(c)
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end

function XB.Contrast(a, b)
  local la, lb = luminance(a), luminance(b)
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

-- Props -------------------------------------------------------------------------------------------

local DEFAULTS = {
  bar = {
    orient = "horizontal",
    fill = "1f5fa8",
    quest = "2e7d32",
    rested = "6b3fa0",
    bg = "202020",
    border = "4a4a4a",
    borderWidth = 1,
    texture = "solid",
    spark = false,
  },
  text = {
    template = "{level}",
    font = "frizqt",
    size = 12,
    outline = "none",
    color = "ffffff",
    justify = "LEFT",
    shadow = true,
    -- `bg` (absent = none) is the colour behind the text.
    bgAlpha = 0.6,
    bgPad = 2,
  },
  shape = { color = "ffffff", alpha = 1, border = false, borderWidth = 1 },
}

local CLEAN = {
  bar = function(raw, d)
    return {
      orient = oneOf(raw.orient, XB.ORIENT, d.orient),
      fill = hex(raw.fill, d.fill),
      quest = hex(raw.quest, d.quest),
      rested = hex(raw.rested, d.rested),
      bg = hex(raw.bg, d.bg),
      border = hex(raw.border, d.border),
      borderWidth = whole(raw.borderWidth, d.borderWidth, 0, XB.MAX_BORDER),
      texture = oneOf(raw.texture, XB.TEXTURES, d.texture),
      spark = raw.spark == true,
    }
  end,
  text = function(raw, d)
    local font = type(raw.font) == "string" and #raw.font <= 44 and raw.font or d.font
    return {
      template = type(raw.template) == "string" and raw.template or d.template,
      font = font,
      size = whole(raw.size, d.size, XB.SIZE_MIN, XB.SIZE_MAX),
      outline = oneOf(raw.outline, XB.OUTLINES, d.outline),
      color = hex(raw.color, d.color),
      justify = oneOf(raw.justify, XB.JUSTIFY, d.justify),
      shadow = raw.shadow ~= false,
      bg = hex(raw.bg, nil),
      bgAlpha = finite(raw.bgAlpha) and U.clamp(raw.bgAlpha, 0, 1) or d.bgAlpha,
      bgPad = whole(raw.bgPad, d.bgPad, 0, XB.MAX_BG_PAD),
    }
  end,
  shape = function(raw, d)
    return {
      color = hex(raw.color, d.color),
      alpha = finite(raw.alpha) and U.clamp(raw.alpha, 0, 1) or d.alpha,
      border = hex(raw.border, false),
      borderWidth = whole(raw.borderWidth, d.borderWidth, 0, XB.MAX_BORDER),
    }
  end,
}

-- The props of an element of `kind` with every field valid (defaults for missing or broken ones).
function XB.Props(kind, props)
  local d = DEFAULTS[kind]
  return CLEAN[kind](type(props) == "table" and props or {}, d)
end

local function newProps(kind)
  return U.copy(DEFAULTS[kind])
end

-- Template text: "@xpbar.tpl.<name>" stands for the text of the current language, anything else is
-- the template as typed. The presets use the keys, so a language change reaches them.
function XB.Template(template)
  local key = type(template) == "string" and template:match(TEMPLATE_KEY)
  if key then
    local text = L[key]
    if text ~= key then
      return text
    end
  end
  return template
end

-- Drawing helpers -----------------------------------------------------------------------------------

local function valuesOf(ctx)
  local v = type(ctx) == "table" and type(ctx.values) == "function" and ctx.values() or nil
  return type(v) == "table" and v or XB.SampleValues()
end

local function fraction(v)
  return finite(v) and U.clamp(v, 0, 1) or 0
end

local function paint(tex, color, alpha)
  local r, g, b = U.hex(color)
  tex:SetColorTexture(r, g, b, alpha or 1)
end

-- Four lines on the inside of the edge of `frame`; hidden for no color or width 0.
local function setBorder(frame, state, color, width, layer)
  state.edges = state.edges or {}
  for i = 1, 4 do
    local line = state.edges[i]
    if color and width > 0 and not line then
      line = frame:CreateTexture(nil, layer)
      state.edges[i] = line
    end
    if line then
      if color and width > 0 then
        line:ClearAllPoints()
        if i == 1 then
          line:SetPoint("TOPLEFT")
          line:SetPoint("TOPRIGHT")
          line:SetHeight(width)
        elseif i == 2 then
          line:SetPoint("BOTTOMLEFT")
          line:SetPoint("BOTTOMRIGHT")
          line:SetHeight(width)
        elseif i == 3 then
          line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -width)
          line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, width)
          line:SetWidth(width)
        else
          line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -width)
          line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, width)
          line:SetWidth(width)
        end
        paint(line, color)
        line:Show()
      else
        line:Hide()
      end
    end
  end
end

-- Bar --------------------------------------------------------------------------------------------------

local function barState(frame)
  local state = frame.fgXpBar
  if not state then
    state = { layers = {} }
    state.bg = frame:CreateTexture(nil, "BACKGROUND")
    state.bg:SetAllPoints(frame)
    for _, name in ipairs({ "rested", "quest", "fill" }) do
      state.layers[name] = frame:CreateTexture(nil, "ARTWORK")
    end
    state.spark = frame:CreateTexture(nil, "OVERLAY")
    state.spark:SetTexture(SPARK)
    state.spark:SetBlendMode("ADD")
    frame.fgXpBar = state
  end
  return state
end

local function layerFractions(v)
  if v.atMax then
    return { fill = 1, quest = 0, rested = 0 }
  end
  local bar = type(v.bar) == "table" and v.bar or {}
  return { fill = fraction(bar.xp), quest = fraction(bar.done), rested = fraction(bar.rested) }
end

-- Longest layer at the back, so every layer stays visible whatever its length; on a tie XP lies in
-- front of the quests and those in front of the rested layer.
local ORDER = { "fill", "quest", "rested" }
local PRIORITY = { fill = 1, quest = 2, rested = 3 }

local function paintLayer(tex, p, color, frac, innerW, innerH, bw, sub)
  if frac <= 0 then
    tex:Hide()
    return
  end
  tex:SetDrawLayer("ARTWORK", sub)
  tex:ClearAllPoints()
  if p.orient == "vertical" then
    tex:SetPoint("BOTTOMLEFT", bw, bw)
    tex:SetSize(innerW, math.max(1, innerH * frac))
  else
    tex:SetPoint("BOTTOMLEFT", bw, bw)
    tex:SetSize(math.max(1, innerW * frac), innerH)
  end
  local path = XB.TEXTURE_PATH[p.texture]
  if path then
    tex:SetTexture(path)
    tex:SetVertexColor(U.hex(color))
  else
    paint(tex, color)
  end
  tex:Show()
end

local function renderBar(frame, el, ctx)
  local p = XB.Props("bar", el.props)
  local state = barState(frame)
  local v = valuesOf(ctx)
  local width, height = math.max(1, frame:GetWidth()), math.max(1, frame:GetHeight())
  local bw = math.min(p.border and p.borderWidth or 0, math.floor(math.min(width, height) / 2))
  local innerW, innerH = math.max(1, width - 2 * bw), math.max(1, height - 2 * bw)
  paint(state.bg, p.bg)
  local fractions = layerFractions(v)
  local rank = { unpack(ORDER) }
  table.sort(rank, function(a, b)
    if fractions[a] ~= fractions[b] then
      return fractions[a] > fractions[b]
    end
    return PRIORITY[a] > PRIORITY[b]
  end)
  for sub, name in ipairs(rank) do
    paintLayer(state.layers[name], p, p[name], fractions[name], innerW, innerH, bw, sub)
  end
  if p.spark and fractions.fill > 0 and fractions.fill < 1 then
    state.spark:ClearAllPoints()
    if p.orient == "vertical" then
      state.spark:SetSize(innerW * 2, SPARK_W)
      state.spark:SetPoint("CENTER", frame, "BOTTOM", 0, bw + innerH * fractions.fill)
    else
      state.spark:SetSize(SPARK_W, innerH * 2)
      state.spark:SetPoint("CENTER", frame, "LEFT", bw + innerW * fractions.fill, 0)
    end
    state.spark:Show()
  else
    state.spark:Hide()
  end
  setBorder(frame, state, p.border, bw, "BORDER")
end

-- Text -------------------------------------------------------------------------------------------------

local function applyFont(fs, p)
  local flags = FLAGS[p.outline]
  local NW = ns.NoteWindow
  if NW and NW.ApplyFont then
    NW.ApplyFont(fs, p.font, p.size, flags)
  else
    ns.Theme.applyFont(fs, "ui", "body", flags)
  end
end

-- Shared with the other canvas hosts that draw text: p holds font, size and outline.
XB.ApplyFont = applyFont

local function textState(frame, p)
  local state = frame.fgXpText
  if not state then
    state = { fs = frame:CreateFontString(nil, "OVERLAY") }
    -- A font string needs a font before its first SetText.
    applyFont(state.fs, p)
    state.fontKey = p.font .. "|" .. p.size .. "|" .. p.outline
    frame.fgXpText = state
  end
  return state
end

local function renderText(frame, el, ctx)
  local p = XB.Props("text", el.props)
  local state = textState(frame, p)
  local fs = state.fs
  local fontKey = p.font .. "|" .. p.size .. "|" .. p.outline
  if fontKey ~= state.fontKey then
    state.fontKey = fontKey
    applyFont(fs, p)
  end
  local r, g, b = U.hex(p.color)
  fs:SetTextColor(r, g, b, 1)
  ns.WindowStyle.ApplyShadow(fs, p.shadow, r, g, b)
  fs:SetJustifyH(p.justify)
  fs:SetJustifyV("MIDDLE")
  fs:SetWordWrap(false)
  local auto = not (finite(el.w) and el.w > 0)
  fs:ClearAllPoints()
  if auto then
    fs:SetPoint(p.justify, frame, p.justify)
  else
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT")
    fs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
  end
  fs:SetText(XL.Render(XB.Template(p.template), valuesOf(ctx)))
  if p.bg then
    if not state.bg then
      state.bg = frame:CreateTexture(nil, "BACKGROUND")
    end
    state.bg:ClearAllPoints()
    state.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -p.bgPad, p.bgPad)
    state.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", p.bgPad, -p.bgPad)
    paint(state.bg, p.bg, p.bgAlpha)
    state.bg:Show()
  elseif state.bg then
    state.bg:Hide()
  end
  if auto then
    frame:SetWidth(math.max(1, math.ceil(fs:GetStringWidth()) + 1))
  end
end

-- Shape ------------------------------------------------------------------------------------------------

local function renderShape(frame, el)
  local p = XB.Props("shape", el.props)
  local state = frame.fgXpShape
  if not state then
    state = {}
    state.fill = frame:CreateTexture(nil, "BACKGROUND")
    state.fill:SetAllPoints(frame)
    frame.fgXpShape = state
  end
  paint(state.fill, p.color, p.alpha)
  setBorder(frame, state, p.border or nil, p.borderWidth, "BORDER")
end

-- Types ------------------------------------------------------------------------------------------------

-- Editor panels ---------------------------------------------------------------------------------------

local TEMPLATE_LETTERS = 300
local HINT_H, WARN_H = 44, 38

-- Contrast of the color of a text element against the background of the bar it lies on, nil when no
-- visible bar of `layout` is under it. Texts beside the bar are judged by the editor against the canvas.
-- A see-through canvas (background opacity below CONTRAST_MIN_ALPHA) shows the game world, whose colors
-- are unknown, so it gets no warning.
XB.CONTRAST_MIN_ALPHA = 0.5

-- A text with a background of its own (opacity from CONTRAST_MIN_ALPHA) is judged against that background.
function XB.TextBackground(element)
  local p = XB.Props("text", element.props)
  return p.bg ~= nil and p.bgAlpha >= XB.CONTRAST_MIN_ALPHA and p.bg or nil
end

function XB.TextContrast(element, layout)
  local own = XB.TextBackground(element)
  if own then
    return XB.Contrast(XB.Props("text", element.props).color, own)
  end
  if type(layout) ~= "table" or type(layout.elements) ~= "table" or type(layout.canvas) ~= "table" then
    return nil
  end
  local alpha = finite(layout.canvas.bgAlpha) and layout.canvas.bgAlpha or 1
  if alpha < XB.CONTRAST_MIN_ALPHA then
    return nil
  end
  local left, top, w, h = CL.Rect(layout, element)
  for _, other in ipairs(layout.elements) do
    if other.type == "bar" and other.visible ~= false then
      local ol, ot, ow, oh = CL.Rect(layout, other)
      if left <= ol + ow and left + w >= ol and top <= ot + oh and top + h >= ot then
        return XB.Contrast(XB.Props("text", element.props).color, XB.Props("bar", other.props).bg)
      end
    end
  end
  return nil
end

-- The panel scaffolding is shared with the other hosts (CanvasEditorControls.lua); only the repair of
-- the props of a kind is ours.
local function newPanel(parent, kind, element, onChange, build)
  return ns.CanvasEditor.Controls.NewPanel(parent, {
    element = element,
    onChange = onChange,
    build = build,
    props = function(raw)
      return XB.Props(kind, raw)
    end,
  })
end

local function colorRow(...)
  return ns.CanvasEditor.Controls.ColorRow(...)
end

local function choiceRow(...)
  return ns.CanvasEditor.Controls.ChoiceRow(...)
end

local function toggleRow(...)
  return ns.CanvasEditor.Controls.ToggleRow(...)
end

local function borderWidthRow(state, add)
  return add(
    ns.CanvasEditor.Controls.Number(state.panel, {
      label = "xpbar.panel.borderWidth",
      min = 0,
      max = XB.MAX_BORDER,
      step = 1,
      labelWidth = 90,
      get = function()
        return state.get("borderWidth")
      end,
      set = function(v)
        state.write("borderWidth", v)
      end,
    }),
    ns.CanvasEditor.Controls.HEIGHT.number
  )
end

function XB.BarPanel(parent, element, onChange)
  return newPanel(parent, "bar", element, onChange, function(state, add)
    choiceRow(state, add, "xpbar.panel.orient", "orient", XB.ORIENT, "xpbar.panel.orient.")
    colorRow(state, add, "xpbar.panel.fill", "fill", DEFAULTS.bar.fill)
    colorRow(state, add, "xpbar.panel.quest", "quest", DEFAULTS.bar.quest)
    colorRow(state, add, "xpbar.panel.rested", "rested", DEFAULTS.bar.rested)
    colorRow(state, add, "xpbar.panel.bg", "bg", DEFAULTS.bar.bg)
    colorRow(state, add, "xpbar.panel.border", "border", DEFAULTS.bar.border)
    borderWidthRow(state, add)
    choiceRow(state, add, "xpbar.panel.texture", "texture", XB.TEXTURES, "xpbar.panel.texture.")
    toggleRow(state, add, "xpbar.panel.spark", "spark")
  end)
end

-- Name inserted for a placeholder with a parameter: the sample level makes it a working one.
local function insertName(name)
  return (name:gsub(":N$", ":" .. XB.SAMPLE_LEVEL))
end

function XB.TextPanel(parent, element, onChange)
  local template, warning
  local panel = newPanel(parent, "text", element, onChange, function(state, add)
    local Controls = ns.CanvasEditor.Controls
    local host = state.panel
    -- The template shows as readable text, also when the layout stores a language key.
    template = add(
      Controls.Text(host, {
        label = "xpbar.panel.template",
        maxLetters = TEMPLATE_LETTERS,
        get = function()
          return XB.Template(state.get("template"))
        end,
        set = function(text)
          state.write("template", text)
        end,
      }),
      Controls.HEIGHT.text
    )
    local options = { { value = "", key = "xpbar.panel.pick" } }
    for _, name in ipairs(XL.PlaceholderNames()) do
      options[#options + 1] = { value = name, text = "{" .. name .. "}" }
    end
    add(
      Controls.Choice(host, {
        label = "xpbar.panel.insert",
        options = options,
        get = function()
          return ""
        end,
        set = function(name)
          if name ~= "" then
            -- Appended: the text typed so far stays whole.
            state.write("template", XB.Template(state.get("template")) .. "{" .. insertName(name) .. "}")
            template:Refresh()
          end
        end,
      }),
      Controls.HEIGHT.choice
    )
    add(W.Text(host, { key = "xpbar.panel.hint", role = "small", color = "textMuted", wrap = true }), HINT_H)
    add(
      Controls.Font(host, {
        label = "xpbar.panel.font",
        get = function()
          return state.get("font")
        end,
        set = function(key)
          state.write("font", key)
        end,
      }),
      Controls.HEIGHT.choice
    )
    add(
      Controls.Slider(host, {
        label = "xpbar.panel.size",
        min = XB.SIZE_MIN,
        max = XB.SIZE_MAX,
        step = 1,
        get = function()
          return state.get("size")
        end,
        set = function(v)
          state.write("size", v)
        end,
      }),
      Controls.HEIGHT.slider
    )
    choiceRow(state, add, "xpbar.panel.outline", "outline", XB.OUTLINES, "xpbar.panel.outline.")
    colorRow(state, add, "xpbar.panel.color", "color", DEFAULTS.text.color)
    add(Controls.Section(host, "xpbar.panel.textBg"), Controls.HEIGHT.section)
    add(
      Controls.ColorAlpha(host, {
        label = "xpbar.panel.textBgColor",
        owner = state.owner(),
        allowNil = true,
        get = function()
          return state.get("bg")
        end,
        alpha = function()
          return state.get("bgAlpha")
        end,
        set = function(color, alpha)
          state.write("bg", color)
          state.write("bgAlpha", alpha)
        end,
      }),
      Controls.HEIGHT.colorAlpha
    )
    add(
      Controls.Slider(host, {
        label = "xpbar.panel.bgPad",
        min = 0,
        max = XB.MAX_BG_PAD,
        step = 1,
        get = function()
          return state.get("bgPad")
        end,
        set = function(v)
          state.write("bgPad", v)
        end,
        format = function(v)
          return v .. " px"
        end,
      }),
      Controls.HEIGHT.slider,
      function()
        return state.get("bg") ~= nil
      end
    )
    warning = W.Text(host, { role = "ui", color = "warning", wrap = true })
    add(warning, WARN_H, function()
      local editor = ns.CanvasEditor
      local ok, ratio = pcall(function()
        return XB.TextContrast(state.element, editor and editor.Layout and editor.Layout())
      end)
      if ok and ratio and ratio < XB.MIN_CONTRAST then
        -- The ratio in words as well: the warning never rests on color alone.
        W.SetText(warning, nil, string.format(L["xpbar.panel.contrast"], string.format("%.1f", ratio)))
        return true
      end
      return false
    end)
    choiceRow(state, add, "xpbar.panel.justify", "justify", XB.JUSTIFY, "xpbar.panel.justify.")
    toggleRow(state, add, "xpbar.panel.shadow", "shadow")
  end)
  panel.template, panel.warning = template, warning
  return panel
end

function XB.ShapePanel(parent, element, onChange)
  return newPanel(parent, "shape", element, onChange, function(state, add)
    local Controls = ns.CanvasEditor.Controls
    colorRow(state, add, "xpbar.panel.shapeColor", "color", DEFAULTS.shape.color)
    add(
      Controls.Slider(state.panel, {
        label = "xpbar.panel.alpha",
        min = 0,
        max = 100,
        step = 5,
        get = function()
          return math.floor(state.get("alpha") * 100 + 0.5)
        end,
        set = function(v)
          state.write("alpha", v / 100)
        end,
        format = function(v)
          return v .. "%"
        end,
      }),
      Controls.HEIGHT.slider
    )
    -- No border color: no border.
    add(
      Controls.Color(state.panel, {
        label = "xpbar.panel.border",
        allowNil = true,
        owner = state.owner(),
        get = function()
          return state.get("border") or nil
        end,
        set = function(color)
          state.write("border", color)
        end,
      }),
      Controls.HEIGHT.color
    )
    borderWidthRow(state, add)
  end)
end

-- Built on every call: the labels follow the language.
function XB.Types()
  return {
    bar = {
      label = L["xpbar.type.bar"],
      desc = "xpbar.type.bar.desc",
      new = function()
        return newProps("bar")
      end,
      size = { 200, 18 },
      max = 1,
      render = renderBar,
      panel = XB.BarPanel,
    },
    text = {
      label = L["xpbar.type.text"],
      desc = "xpbar.type.text.desc",
      new = function()
        return newProps("text")
      end,
      size = { 0, 16 },
      render = renderText,
      panel = XB.TextPanel,
      -- The editor warns when this color has too little contrast against the canvas. A text with a
      -- background of its own is judged by its panel against that background instead.
      textColor = function(element)
        if XB.TextBackground(element) then
          return nil
        end
        return XB.Props("text", element.props).color
      end,
    },
    shape = {
      label = L["xpbar.type.shape"],
      desc = "xpbar.type.shape.desc",
      new = function()
        return newProps("shape")
      end,
      size = { 40, 2 },
      render = renderShape,
      panel = XB.ShapePanel,
    },
  }
end

-- Values and context --------------------------------------------------------------------------------

-- A level in the middle of the table with a running session: every placeholder has a value.
function XB.SampleValues()
  local level = XB.SAMPLE_LEVEL
  local max = ns.XpTable.need[level] or 100000
  return XL.Compute({
    level = level,
    xp = math.floor(max * 0.42),
    max = max,
    rested = math.floor(max * 0.35),
    doneXp = math.floor(max * 0.18),
    todoXp = math.floor(max * 0.1),
    sizes = XL.Sizes(nil, level, max),
    session = { active = 2700, since = 0, running = true, gained = math.floor(max * 0.4), startedAt = 0, auto = false },
    played = { total = 7200, at = 0 },
    levelStart = { [level] = 1800 },
    now = 0,
  })
end

-- The context of a draw: values is a function so a host can swap the source (sample or live).
function XB.Context(values)
  return {
    values = function()
      return values
    end,
  }
end

-- Presets ---------------------------------------------------------------------------------------------

local function props(kind, over)
  local out = newProps(kind)
  for k, v in pairs(over or {}) do
    out[k] = v
  end
  return out
end

-- el(id, kind, point, x, y, w, h, props): the label of the element comes from "xpbar.el.<id>" or
-- the type name.
local function el(id, kind, point, x, y, w, h, over)
  local label = "xpbar.el." .. id
  return {
    id = id,
    type = kind,
    name = L[label] ~= label and L[label] or L["xpbar.type." .. kind],
    point = point,
    x = x,
    y = y,
    w = w,
    h = h,
    visible = true,
    props = props(kind, over),
  }
end

local function text(id, template, point, x, y, w, over)
  local p = { template = "@xpbar.tpl." .. template, size = 11 }
  for k, v in pairs(over or {}) do
    p[k] = v
  end
  return el(id, "text", point, x, y, w, 14, p)
end

local PRESET_BORDER_ALPHA = 0.8

-- A layout with ids in the order given and z rising with it (the bar first, so texts lie on it).
local function build(id, w, h, elements)
  for i, element in ipairs(elements) do
    element.z = i
  end
  local layout = CL.Validate({
    id = id,
    name = "",
    canvas = { w = w, h = h, bg = "000000", bgAlpha = 0.6, border = "444444" },
    elements = elements,
  })
  -- Only once the canvas knows a border opacity (Validate adds the default for it).
  if layout.canvas.borderAlpha ~= nil then
    layout.canvas.borderAlpha = PRESET_BORDER_ALPHA
  end
  return layout
end

local RIGHT = { justify = "RIGHT" }
local CENTER = { justify = "CENTER" }

local BUILDERS = {
  classic = function()
    return build("classic", 580, 62, {
      el("bar", "bar", "TOPLEFT", 6, -20, 568, 20),
      text("levelTime", "levelTime", "TOPLEFT", 6, -4, 280),
      text("sessionTime", "sessionTime", "TOPRIGHT", -6, -4, 280, RIGHT),
      text("level", "level", "TOPLEFT", 10, -23, 90),
      text("xp", "xp", "TOP", 0, -23, 200, CENTER),
      text("pct", "pct", "TOPRIGHT", -10, -23, 140, RIGHT),
      text("eta", "eta", "TOPLEFT", 6, -44, 292),
      text("quests", "quests", "TOPRIGHT", -6, -44, 260, RIGHT),
    })
  end,
  compact = function()
    return build("compact", 300, 24, {
      el("bar", "bar", "TOPLEFT", 2, -2, 296, 20),
      text("xp", "compact", "CENTER", 0, 0, 290, CENTER),
    })
  end,
  narrow = function()
    return build("narrow", 200, 18, {
      el("bar", "bar", "TOPLEFT", 1, -1, 198, 16),
      text("pct", "narrow", "CENTER", 0, 0, 190, CENTER),
    })
  end,
  detailed = function()
    return build("detailed", 580, 98, {
      el("bar", "bar", "TOPLEFT", 6, -38, 568, 22, { spark = true }),
      text("levelTime", "levelTime", "TOPLEFT", 6, -4, 280),
      text("sessionTime", "sessionTime", "TOPRIGHT", -6, -4, 280, RIGHT),
      text("sessionXp", "sessionXp", "TOPLEFT", 6, -20, 280),
      text("xph", "xph", "TOPRIGHT", -6, -20, 280, RIGHT),
      text("level", "level", "TOPLEFT", 10, -42, 90),
      text("xp", "xp", "TOP", 0, -42, 200, CENTER),
      text("pct", "pct", "TOPRIGHT", -10, -42, 140, RIGHT),
      text("eta", "eta", "TOPLEFT", 6, -64, 292),
      text("rested", "rested", "TOPRIGHT", -6, -64, 260, RIGHT),
      text("todo", "todo", "TOPLEFT", 6, -80, 0),
    })
  end,
}

XB.PRESET_IDS = { "classic", "compact", "narrow", "detailed" }

-- Fresh layout of a preset, nil for an unknown id.
function XB.Preset(id)
  local make = BUILDERS[id]
  return make and make() or nil
end

-- All presets as the editor lists them: { id, name (language of now), layout }.
function XB.Presets()
  local out = {}
  for _, id in ipairs(XB.PRESET_IDS) do
    local layout = XB.Preset(id)
    layout.name = L["xpbar.preset." .. id]
    out[#out + 1] = { id = id, name = layout.name, layout = layout }
  end
  return out
end
