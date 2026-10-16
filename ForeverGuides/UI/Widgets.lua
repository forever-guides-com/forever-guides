-- Widget library. No feature logic here; everything is themed through
-- ns.Bind so font scale, contrast and language apply without /reload.
local _, ns = ...
local Theme, L = ns.Theme, ns.L

local W = {}
ns.W = W

-- Basics ------------------------------------------------------------------

function W.Fill(frame, colorName, alpha, layer)
  local tex = frame:CreateTexture(nil, layer or "BACKGROUND")
  tex:SetAllPoints()
  ns.Bind(tex, function(t)
    t:SetColorTexture(Theme.color(colorName, alpha))
  end)
  -- First fill of a frame is its background; the main window fades it (UI/MainFrame.lua).
  frame.fgBack = frame.fgBack or tex
  return tex
end

-- Fills that follow the main window opacity (settings.mainAlpha): the window, sidebar, footer,
-- title bar and the page cards. Controls keep their own surface and edge.
local windowFills = setmetatable({}, { __mode = "k" })

function W.FadeWithWindow(tex)
  windowFills[tex] = true
  tex:SetAlpha(Theme.mainAlpha())
  return tex
end

function W.ApplyWindowAlpha()
  local a = Theme.mainAlpha()
  for tex in pairs(windowFills) do
    tex:SetAlpha(a)
  end
end

-- 1px (or `size`) border made of four textures; color can change later.
function W.Border(frame, colorName, alpha, size)
  size = size or 1
  local b = { colorName = colorName, alpha = alpha }
  local function edge(p1, p2, horizontal)
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetPoint(p1)
    t:SetPoint(p2)
    if horizontal then
      t:SetHeight(size)
    else
      t:SetWidth(size)
    end
    return t
  end
  b.edges = {
    edge("TOPLEFT", "TOPRIGHT", true),
    edge("BOTTOMLEFT", "BOTTOMRIGHT", true),
    edge("TOPLEFT", "BOTTOMLEFT", false),
    edge("TOPRIGHT", "BOTTOMRIGHT", false),
  }
  function b.apply()
    local a = b.alpha or (b.colorName == "white" and Theme.lineAlpha()) or 1
    local r, g, bl = 1, 1, 1
    if b.colorName ~= "white" then
      r, g, bl = Theme.rgb(b.colorName)
    end
    for _, t in ipairs(b.edges) do
      t:SetColorTexture(r, g, bl, a)
    end
  end
  function b.set(name, a)
    b.colorName, b.alpha = name, a
    b.apply()
  end
  function b.show(shown)
    for _, t in ipairs(b.edges) do
      t:SetShown(shown)
    end
  end
  ns.Bind(frame, b.apply)
  return b
end

-- opts: role, family, color, key (locale) or text, wrap, justify
function W.Text(parent, opts)
  opts = opts or {}
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetJustifyH(opts.justify or "LEFT")
  fs:SetJustifyV("TOP")
  if fs.SetWordWrap then
    fs:SetWordWrap(opts.wrap == true)
  end
  fs.fgKey, fs.fgText, fs.fgColor = opts.key, opts.text, opts.color or "text"
  ns.Bind(fs, function(f)
    Theme.applyFont(f, opts.role or "ui", opts.family or "body")
    f:SetTextColor(Theme.color(f.fgColor))
    if f.fgKey then
      f:SetText(L[f.fgKey])
    elseif f.fgText then
      f:SetText(f.fgText)
    end
  end)
  return fs
end

function W.SetText(fs, keyOrNil, literal)
  fs.fgKey, fs.fgText = keyOrNil, literal
  fs:SetText(keyOrNil and L[keyOrNil] or literal or "")
end

function W.SetColor(fs, colorName)
  fs.fgColor = colorName
  fs:SetTextColor(Theme.color(colorName))
end

-- Tooltips ----------------------------------------------------------------

-- Every tooltip of the addon is the client's GameTooltip (look, font, wrapping, placement and
-- screen clamping are Blizzard's); this is the only place that fills it. Frames of the addon
-- never draw a tooltip of their own.
-- spec: title (white), text (wrapped), hint (wrapped, muted), lines (list of "text",
--   { text, color = theme name } or { left, right, color, rightColor }), anchor (default
--   ANCHOR_RIGHT), link (item/spell/... hyperlink) or spell (id) as the head of the tooltip
--   (a link to an item also gets the owned-by-character block at the end, Modules/InventoryTooltip.lua).
--   A line { separator = true } is a thin rule across the full width of the tooltip.
local Tooltip = {}
W.Tooltip = Tooltip

local WHITE = { 1, 1, 1 }
local hookedOwners = setmetatable({}, { __mode = "k" })

local function rgb(color)
  if type(color) == "string" then
    return Theme.color(color)
  end
  color = color or WHITE
  return color[1], color[2], color[3]
end

-- A separator is a double line of two blanks (its right text sits on the right edge, so the rule
-- spans from the left to the right text) in a tiny font; a pooled texture of the tooltip is drawn
-- between both. The fonts of the lines go back when the tooltip is cleared, the client reuses them.
local SEPARATOR_FONT_SIZE = 4

local function clearSeparators(tip)
  for _, tex in ipairs(tip.fgSeparators or {}) do
    tex:Hide()
  end
  local restore = tip.fgShrunk or {}
  for i = #restore, 1, -1 do
    restore[i]()
    restore[i] = nil
  end
end

local function shrink(tip, fs)
  local back = Theme.shrinkFont(fs, SEPARATOR_FONT_SIZE)
  if back then
    tip.fgShrunk[#tip.fgShrunk + 1] = back
  end
end

local function addSeparator(tip)
  if not tip.fgSeparators then
    tip.fgSeparators, tip.fgShrunk = {}, {}
    tip:HookScript("OnTooltipCleared", clearSeparators)
    tip:HookScript("OnHide", clearSeparators)
  end
  tip:AddDoubleLine(" ", " ")
  local n = tip:NumLines()
  local left, right = rawget(_G, "GameTooltipTextLeft" .. n), rawget(_G, "GameTooltipTextRight" .. n)
  if not (left and right) then
    return
  end
  shrink(tip, left)
  shrink(tip, right)
  local used = 0
  for _, tex in ipairs(tip.fgSeparators) do
    used = used + (tex:IsShown() and 1 or 0)
  end
  local tex = tip.fgSeparators[used + 1]
  if not tex then
    tex = tip:CreateTexture(nil, "OVERLAY")
    tex:SetHeight(1)
    tip.fgSeparators[used + 1] = tex
  end
  tex:ClearAllPoints()
  tex:SetPoint("LEFT", left, "LEFT", 0, 0)
  tex:SetPoint("RIGHT", right, "RIGHT", 0, 0)
  tex:SetColorTexture(Theme.color("accentDim", 0.9))
  tex:Show()
end

function Tooltip.Hide(owner)
  local tip = rawget(_G, "GameTooltip")
  if not tip or (owner and tip:GetOwner() ~= owner) then
    return
  end
  tip:Hide()
end

local function head(tip, spec)
  local filled = false
  if spec.link then
    filled = pcall(tip.SetHyperlink, tip, spec.link) and tip:NumLines() > 0
  elseif spec.spell then
    filled = pcall(tip.SetSpellByID, tip, spec.spell) and tip:NumLines() > 0
  end
  if not filled and spec.title then
    tip:SetText(spec.title, 1, 1, 1, 1, true)
  end
  return filled or spec.title ~= nil
end

-- The item link of a tooltip spec; nil for spells and other links.
local function specItem(spec)
  local link = spec.link
  if type(link) == "string" and link:find("item:", 1, true) then
    return link
  end
end

function Tooltip.Show(owner, spec)
  local tip = rawget(_G, "GameTooltip")
  if not (tip and owner) then
    return false
  end
  tip:SetOwner(owner, spec.anchor or "ANCHOR_RIGHT")
  clearSeparators(tip)
  -- The inventory block comes last (before the hint), so the client's hooks wait until it is added.
  local item, inventory = specItem(spec), ns.InventoryTooltip
  if inventory then
    inventory.Hold(tip, item ~= nil)
  end
  if not head(tip, spec) then
    if inventory then
      inventory.Hold(tip, false)
    end
    tip:Hide()
    return false
  end
  if spec.text and spec.text ~= "" then
    tip:AddLine(spec.text, nil, nil, nil, true)
  end
  for _, line in ipairs(spec.lines or {}) do
    if type(line) == "string" then
      tip:AddLine(line, nil, nil, nil, true)
    elseif line.separator then
      addSeparator(tip)
    elseif line.right then
      local lr, lg, lb = rgb(line.color)
      local rr, rg, rb = rgb(line.rightColor or line.color)
      tip:AddDoubleLine(line.left or line.text or "", line.right, lr, lg, lb, rr, rg, rb)
    else
      local r, g, b = rgb(line.color or "text")
      tip:AddLine(line.left or line.text, r, g, b, true)
    end
  end
  if inventory and item then
    ns.Safe("inventory-tooltip", inventory.AddForItem, tip, item)
  end
  if spec.hint and spec.hint ~= "" then
    local r, g, b = Theme.color("textMuted")
    tip:AddLine(spec.hint, r, g, b, true)
  end
  -- A popup in the TOOLTIP strata would sit above the tooltip of its own entries.
  if owner.GetFrameStrata and owner:GetFrameStrata() == "TOOLTIP" then
    tip:SetFrameLevel(owner:GetFrameLevel() + 10)
  end
  tip:Show()
  -- The tooltip follows its owner into hiding (a panel closed under the mouse).
  if not hookedOwners[owner] and owner.HookScript then
    hookedOwners[owner] = true
    owner:HookScript("OnHide", Tooltip.Hide)
  end
  return true
end

-- Short form for the many callers; extra carries anchor, hint, lines.
function ns.ShowTooltip(owner, title, text, extra)
  local spec = { title = title or "", text = text }
  for k, v in pairs(extra or {}) do
    spec[k] = v
  end
  return Tooltip.Show(owner, spec)
end

-- Also used directly as an OnLeave handler.
function ns.HideTooltip()
  Tooltip.Hide()
end

local function attachTooltip(frame, titleKey, textKey)
  if not titleKey then
    return
  end
  frame:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, L[titleKey], textKey and L[textKey])
  end)
  frame:HookScript("OnLeave", ns.HideTooltip)
end
W.AttachTooltip = attachTooltip

-- Keyboard focus ----------------------------------------------------------
-- Tab/Shift+Tab walk visible focusables of the main window in creation
-- order, Enter/Space activates. The ring is one shared frame.

local Focus = { items = {}, current = nil }
ns.Focus = Focus

local ring
local function getRing()
  if not ring then
    ring = CreateFrame("Frame", nil, UIParent)
    ring:SetFrameStrata("TOOLTIP")
    ring.border = W.Border(ring, "actionHi", 1, 3)
    ring:Hide()
  end
  return ring
end

function Focus.register(frame, activate)
  frame.fgActivate = activate
  Focus.items[#Focus.items + 1] = frame
  frame:HookScript("OnHide", function(self)
    if Focus.current == self then
      Focus.clear()
    end
  end)
end

local function visible(frame)
  return frame:IsVisible() and (not frame.IsEnabled or frame:IsEnabled())
end

-- Scrolls the nearest W.ScrollArea above `frame` just far enough to show it.
local function revealInScroll(frame)
  local area = frame:GetParent()
  while area and not (area.ScrollTo and area.content) do
    area = area:GetParent()
  end
  local top, bottom, areaTop, areaBottom =
    frame:GetTop(), frame:GetBottom(), area and area:GetTop(), area and area:GetBottom()
  if not (top and bottom and areaTop and areaBottom) then
    return
  end
  if top > areaTop then
    area:ScrollTo(area:GetVerticalScroll() - (top - areaTop) - 4)
  elseif bottom < areaBottom then
    area:ScrollTo(area:GetVerticalScroll() + (areaBottom - bottom) + 4)
  end
end

function Focus.set(frame)
  local previous = Focus.current
  if previous and previous ~= frame and previous.fgOnBlur then
    previous:fgOnBlur()
  end
  Focus.current = frame
  local r = getRing()
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
  r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
  r:Show()
  if frame.fgScrollIntoView then
    frame:fgScrollIntoView()
  else
    revealInScroll(frame)
  end
  if frame.fgOnFocus then
    frame:fgOnFocus()
  end
end

function Focus.clear()
  local previous = Focus.current
  Focus.current = nil
  if ring then
    ring:Hide()
  end
  if previous and previous.fgOnBlur then
    previous:fgOnBlur()
  end
end

function Focus.move(step)
  local list = {}
  local index = 0
  for _, f in ipairs(Focus.items) do
    if visible(f) then
      list[#list + 1] = f
      if f == Focus.current then
        index = #list
      end
    end
  end
  if #list == 0 then
    return
  end
  index = index + step
  if index < 1 then
    index = #list
  elseif index > #list then
    index = 1
  end
  Focus.set(list[index])
end

function Focus.activate()
  local f = Focus.current
  if f and visible(f) and f.fgActivate then
    ns.Safe("focus-activate", f.fgActivate, f)
    return true
  end
  return false
end

-- Buttons -----------------------------------------------------------------

ns.AddLocale("enUS", {
  ["act.shortcut"] = "Shortcut: %s",
  ["act.new"] = "New",
  ["act.add"] = "Add",
  ["act.remove"] = "Remove",
  ["act.delete"] = "Delete",
  ["act.duplicate"] = "Duplicate",
  ["act.copy"] = "Copy",
  ["act.export"] = "Export",
  ["act.import"] = "Import",
  ["act.share"] = "Share",
  ["act.save"] = "Save",
  ["act.apply"] = "Apply",
  ["act.reset"] = "Reset",
  ["act.refresh"] = "Refresh",
  ["act.edit"] = "Edit",
  ["act.search"] = "Search",
  ["act.info"] = "Info",
  ["act.close"] = "Close",
  ["act.back"] = "Back",
  ["act.forward"] = "Forward",
  ["act.up"] = "Up",
  ["act.down"] = "Down",
  ["act.play"] = "To game",
  ["act.fromGame"] = "From game",
  ["act.map"] = "Map",
  ["act.marker"] = "Marker",
  ["act.undo"] = "Undo",
  ["act.redo"] = "Redo",
  ["act.merge"] = "Merge",
  ["act.sequence"] = "Sequence",
  ["act.compact"] = "Compact",
  ["act.text"] = "As text",
  ["act.spell"] = "Spell",
  ["act.favorite"] = "Favorite",
  ["act.commands"] = "Commands",
  ["act.options"] = "Options",
  ["act.look"] = "Look",
  ["act.show"] = "Show",
  ["act.keys"] = "Keys",
  ["act.move"] = "Move",
  ["act.test"] = "Test",
  ["act.report"] = "Report",
  ["act.code"] = "Code",
  ["act.link"] = "Link",
  ["act.send"] = "Send",
  ["act.shot"] = "Capture",
  ["act.confirm"] = "OK",
  ["act.cancel"] = "Cancel",
  ["act.whisper"] = "Whisper",
  ["act.insert"] = "Insert",
  ["act.load"] = "Load",
  ["act.world"] = "World",
  ["act.done"] = "Done",
  ["act.tour"] = "Tour",
  ["act.replace"] = "Replace",
  ["act.rename"] = "Rename",
  ["act.here"] = "Here",
  ["act.next"] = "Next",
  ["act.swap"] = "Swap",
  ["act.stop"] = "Stop",
  ["act.goal"] = "Goal",
  ["act.start"] = "Start",
  ["act.none"] = "None",
  ["act.all"] = "All",
  ["act.pick"] = "Pick",
  ["act.enable"] = "Enable",
  ["act.fit"] = "Fit",
  ["act.open"] = "Open",
  ["act.clear"] = "Clear",
  ["act.restore"] = "Restore",
  ["act.closeAll"] = "Close all",
  ["act.backup"] = "Backup",
})

ns.AddLocale("deDE", {
  ["act.shortcut"] = "Tastenkürzel: %s",
  ["act.new"] = "Neu",
  ["act.add"] = "Hinzufügen",
  ["act.remove"] = "Entfernen",
  ["act.delete"] = "Löschen",
  ["act.duplicate"] = "Duplizieren",
  ["act.copy"] = "Kopieren",
  ["act.export"] = "Export",
  ["act.import"] = "Import",
  ["act.share"] = "Teilen",
  ["act.save"] = "Speichern",
  ["act.apply"] = "Anwenden",
  ["act.reset"] = "Zurücksetzen",
  ["act.refresh"] = "Neu laden",
  ["act.edit"] = "Bearbeiten",
  ["act.search"] = "Suchen",
  ["act.info"] = "Info",
  ["act.close"] = "Schließen",
  ["act.back"] = "Zurück",
  ["act.forward"] = "Vor",
  ["act.up"] = "Hoch",
  ["act.down"] = "Runter",
  ["act.play"] = "Ins Spiel",
  ["act.fromGame"] = "Aus Spiel",
  ["act.map"] = "Karte",
  ["act.marker"] = "Marker",
  ["act.undo"] = "Rückgängig",
  ["act.redo"] = "Wiederholen",
  ["act.merge"] = "Verbinden",
  ["act.sequence"] = "Sequenz",
  ["act.compact"] = "Kompakt",
  ["act.text"] = "Als Text",
  ["act.spell"] = "Zauber",
  ["act.favorite"] = "Favorit",
  ["act.commands"] = "Befehle",
  ["act.options"] = "Optionen",
  ["act.look"] = "Aussehen",
  ["act.show"] = "Zeigen",
  ["act.keys"] = "Tasten",
  ["act.move"] = "Verschieben",
  ["act.test"] = "Test",
  ["act.report"] = "Bericht",
  ["act.code"] = "Code",
  ["act.link"] = "Link",
  ["act.send"] = "Senden",
  ["act.shot"] = "Aufnehmen",
  ["act.confirm"] = "OK",
  ["act.cancel"] = "Abbrechen",
  ["act.whisper"] = "Flüstern",
  ["act.insert"] = "Einfügen",
  ["act.load"] = "Laden",
  ["act.world"] = "Welt",
  ["act.done"] = "Fertig",
  ["act.tour"] = "Tour",
  ["act.replace"] = "Ersetzen",
  ["act.rename"] = "Umbenennen",
  ["act.here"] = "Hier",
  ["act.next"] = "Weiter",
  ["act.swap"] = "Tauschen",
  ["act.stop"] = "Stopp",
  ["act.goal"] = "Ziel",
  ["act.start"] = "Start",
  ["act.none"] = "Keine",
  ["act.all"] = "Alle",
  ["act.pick"] = "Wählen",
  ["act.enable"] = "Einschalten",
  ["act.fit"] = "Anpassen",
  ["act.open"] = "Öffnen",
  ["act.clear"] = "Leeren",
  ["act.restore"] = "Zurückholen",
  ["act.closeAll"] = "Alle zu",
  ["act.backup"] = "Sicherung",
})

-- Palette per variant. Only theme tokens, so every skin, color theme and contrast mode applies.
-- bgHover/hoverAlpha: hover fill; border (+ borderHover): the edge, nil = no edge until hover.
local VARIANTS = {
  primary = {
    bg = "action",
    bgHover = "actionHi",
    text = "text",
    textHover = "bg",
    border = "actionHi",
    borderAlpha = 0.8,
  },
  secondary = {
    bg = "surface2",
    bgHover = "surface3",
    text = "text",
    textHover = "text",
    border = "white",
    borderHover = "accentDim",
  },
  ghost = { bgHover = "surface2", text = "textSecondary", textHover = "text", borderHover = "accentDim" },
  icon = {
    bgHover = "text",
    hoverAlpha = 0.08,
    text = "textSecondary",
    textHover = "accent",
    borderHover = "accentDim",
  },
  danger = {
    bg = "surface2",
    bgHover = "danger",
    hoverAlpha = 0.3,
    text = "danger",
    textHover = "text",
    border = "danger",
    borderAlpha = 0.6,
    borderHover = "danger",
  },
  gold = {
    bg = "surface2",
    bgHover = "surface3",
    text = "accent2",
    textHover = "accent",
    border = "accentDim",
    borderAlpha = 0.8,
    borderHover = "accent2",
  },
  -- The footer Save button: a filled accent button at rest, a warning fill while data is unsaved
  -- (UI/SaveUI.lua). Text on both fills passes AA in every theme (tests/test_savestate.lua).
  save = {
    bg = "action",
    bgHover = "actionHi",
    text = "text",
    textHover = "bg",
    border = "actionHi",
    borderAlpha = 0.6,
  },
  saveDirty = {
    bg = "warning",
    bgHover = "accent",
    text = "bg",
    textHover = "bg",
    border = "text",
    borderAlpha = 0.9,
  },
  -- An icon button with surface and edge like a secondary button ("boxed").
  boxed = {
    bg = "surface2",
    bgHover = "surface3",
    text = "textSecondary",
    textHover = "accent",
    border = "white",
    borderHover = "accentDim",
  },
}
W.ACTION_VARIANTS = VARIANTS
W.ACTION_SIZES = { 24, 28, 32 }
W.ACTION_ICON_SIZE = 24 -- icon buttons without a label are square
local ACTION_PAD, ACTION_GAP, ACTION_SLACK = 8, 4, 4

local function labelsOn()
  local settings = ns.db and ns.db.settings
  return not (settings and settings.buttonLabels == false)
end

-- Icon edge for a button height: 24 -> 14, 28 -> 16, 32 -> 18.
local function iconPixels(height)
  return math.max(14, math.min(18, math.floor(height * 0.58 + 0.5)))
end

local function paintAction(b)
  local v = b.fgPalette
  local enabled = b:IsEnabled()
  local hover, pressed = b.fgHover and enabled, b.fgPressed and enabled
  local bgName, bgAlpha, text = v.bg, 1, v.text
  local edge, edgeAlpha = v.border, v.borderAlpha
  if not enabled then
    -- Disabled steps down the palette (flat fill, faint edge, muted content), never text color alone.
    bgName = v.bg and "surface" or nil
    text, edge, edgeAlpha = "textMuted", v.border and "white" or nil, nil
  elseif hover then
    bgName, bgAlpha, text = v.bgHover or v.bg, v.hoverAlpha or 1, v.textHover or v.text
    if v.borderHover then
      -- Light edge on hover (also for variants without a resting edge): the focus ring of the mouse.
      edge, edgeAlpha = v.borderHover, v.border and 0.9 or 0.6
    end
  end
  if b.fgSelected and enabled then
    -- A toggle that is on: filled, accent content and a 2 px ring (b.ring), never color alone.
    bgName, bgAlpha, text = hover and "surface3" or "surface2", 1, "accent"
    edge, edgeAlpha = nil, nil
  end
  if b.ring then
    b.ring.show(b.fgSelected == true and enabled)
  end
  if pressed then
    if v.bg then
      local r, g, bl = Theme.rgb(bgName)
      b.bg:SetColorTexture(r * 0.7, g * 0.7, bl * 0.7, bgAlpha)
    else
      b.bg:SetColorTexture(Theme.color("bg", 0.5))
    end
  elseif bgName then
    b.bg:SetColorTexture(Theme.color(bgName, bgAlpha))
  else
    b.bg:SetColorTexture(0, 0, 0, 0)
  end
  if edge then
    b.border.set(edge, edgeAlpha)
  end
  b.border.show(edge ~= nil)
  local dx, dy = pressed and 1 or 0, pressed and -1 or 0
  if dx ~= b.fgDx then
    b.fgDx, b.fgDy = dx, dy
    b.fgPlace(b)
  end
  if b.label then
    W.SetColor(b.label, text)
    if not enabled then
      b.label:SetTextColor(Theme.color("textMuted", 0.6))
    end
  end
  if b.glyph then
    W.SetColor(b.glyph, text)
  end
  if b.icon then
    if b.icon.SetColorToken then
      b.icon:SetColorToken(text)
      b.icon:SetAlpha(enabled and 1 or 0.5)
    else
      b.icon:SetAlpha(enabled and 1 or 0.4)
    end
  end
end

-- Puts icon and label where the current state wants them: icon alone centered, icon plus label
-- as a row (icon left), label alone filling the button. A pressed button moves them 1 px.
local function placeContent(b)
  local dx, dy = b.fgDx or 0, b.fgDy or 0
  local labelShown = b.label ~= nil and b.fgLabelOn
  if b.label then
    b.label:SetShown(labelShown)
  end
  local mark = b.glyph or b.icon
  if b.fgTexture then
    mark:ClearAllPoints()
    mark:SetPoint("TOPLEFT", b, "TOPLEFT", 3 + dx, -3 + dy)
    mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3 + dx, 3 + dy)
  elseif mark and labelShown then
    mark:ClearAllPoints()
    mark:SetPoint("LEFT", b, "LEFT", ACTION_PAD + dx, dy)
  elseif mark then
    mark:ClearAllPoints()
    mark:SetPoint("CENTER", b, "CENTER", dx, dy)
  end
  if labelShown then
    local inset = mark and (ACTION_PAD + (b.fgIconPx or 0) + ACTION_GAP) or ACTION_PAD
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b, "LEFT", inset + dx, dy)
    b.label:SetPoint("RIGHT", b, "RIGHT", -ACTION_PAD + dx, dy)
  end
end

-- Width the button wants with its label shown (a button without a hideable label is as wide as
-- its icon or text needs).
local function fullWidth(b)
  local text = 0
  if b.label then
    text = math.ceil(b.label:GetStringWidth())
    if text > 0 then
      b.fgTextW = text
    else
      text = b.fgTextW or 0
    end
  end
  if b.label and b.fgIconPx then
    return ACTION_PAD * 2 + b.fgIconPx + ACTION_GAP + text + ACTION_SLACK
  end
  if b.label then
    return text + 24
  end
  return b.fgSide
end

-- Decides whether the short label shows (setting "buttonLabels" on and the label fits maxWidth)
-- and returns the width the button should get: its content width with the label, the square side
-- without. Layouts call this with the width they can give and apply the result with SetSize.
local function fitAction(b, maxWidth)
  b.fgMax = maxWidth
  if b.fgHasLabel then
    local on = labelsOn()
    if on and maxWidth and fullWidth(b) > maxWidth then
      on = false
    end
    b.fgLabelOn = on
    placeContent(b)
    return on and fullWidth(b) or b.fgSide
  end
  return fullWidth(b)
end

-- opts: key|text (fixed text), label (short locale key, hidden by the setting "buttonLabels" and
-- when there is no room), icon (name of ns.UI_ICONS), variant (primary, secondary, ghost, icon,
-- danger, gold; default secondary, icon without text), size (height 24, 28 or 32; icon-only buttons
-- are square), height/width (exact, for the adapters), tooltip + tooltipText (locale keys, the
-- label is the tooltip title when none is given), shortcut (text for the tooltip), onClick,
-- boxed (icon button with surface and edge), texture (raw texture path or fileID instead of an
-- icon), glyph (text stand-in, no caller in the addon uses it), wrap (name for ns.Wrap), manual (the owner sets tooltip and
-- b.fgName itself, for pooled buttons whose text changes per use).
-- Fields: b.label, b.icon (Glyph frame or texture), b.glyph, b.border, b.fgNameKey (the
-- accessible name), b:Fit(maxWidth), b:FullWidth(), b:SetSelected(on), b:SetIcon(name),
-- b:SetVariant(name).
function W.Action(parent, opts)
  if opts.icon == "close" and ns.WindowShell and ns.WindowShell.IsTitleBar(parent) then
    -- The close button of a window shell has one size in every window.
    local own = {}
    for k, v in pairs(opts) do
      own[k] = v
    end
    own.size, own.height, own.width = W.CLOSE_SIZE, nil, nil
    opts = own
  end
  local hasText = opts.key ~= nil or opts.text ~= nil
  local iconOnly = not hasText and opts.label == nil
  local variantName = opts.variant or (opts.boxed and "boxed") or (iconOnly and "icon") or "secondary"
  local v = VARIANTS[variantName] or VARIANTS.secondary
  local b = CreateFrame("Button", nil, parent)
  local height = opts.height or opts.size or (iconOnly and W.ACTION_ICON_SIZE or 28)
  b.fgAction, b.fgPalette, b.fgSide = true, v, opts.size or opts.height or W.ACTION_ICON_SIZE
  b.fgHasLabel = opts.label ~= nil and not hasText
  b.fgLabelOn = hasText or opts.label ~= nil
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.border = W.Border(b, v.border or "accentDim", v.borderAlpha)
  b.fgTexture = opts.texture ~= nil
  if opts.icon or opts.texture then
    b.fgIconPx = opts.iconSize or iconPixels(height)
  end
  if opts.icon then
    b.icon = W.Glyph(b, opts.icon, b.fgIconPx, v.text)
  elseif opts.texture then
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(opts.texture)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  if opts.glyph then
    b.glyph = W.Text(b, { text = opts.glyph, role = "h3", color = v.text, justify = "CENTER" })
  elseif hasText or opts.label then
    b.label = W.Text(b, {
      key = hasText and opts.key or opts.label,
      text = opts.text,
      role = "ui",
      color = v.text,
      justify = "CENTER",
    })
  end
  b.fgPlace = placeContent
  placeContent(b)
  b:SetSize(opts.width or height, height)
  b.Fit, b.FullWidth = fitAction, fullWidth
  -- Toggle state: filled, accent content and a 2 px ring instead of the resting edge.
  function b:SetSelected(on)
    on = on and true or false
    if on == self.fgSelected then
      return
    end
    self.fgSelected = on
    if on and not self.ring then
      self.ring = W.Border(self, "accent2", 1, 2)
    end
    paintAction(self)
  end
  -- Swaps the icon (a name of ns.UI_ICONS) of a button made with an icon.
  function b:SetIcon(name)
    if self.fgTexture then
      self.icon:SetTexture(name)
    elseif self.icon and self.icon.SetIcon then
      self.icon:SetIcon(name)
    end
  end
  -- Switches the palette (pooled buttons that change between plain and boxed).
  function b:SetVariant(name)
    self.fgPalette = VARIANTS[name] or VARIANTS.secondary
    paintAction(self)
  end
  b.fgNameKey = opts.tooltip or opts.label or opts.key
  -- The accessible name as text (tests and audits read it).
  function b.fgName()
    return b.fgNameKey and L[b.fgNameKey] or nil
  end
  if opts.icon and iconOnly and not b.fgNameKey and not opts.manual then
    ns.Log.warn("icon button %s has no tooltip, so no accessible name", opts.icon)
  end

  ns.Bind(b, function()
    paintAction(b)
    if b.fgHasLabel then
      local width = b:Fit(b.fgMax)
      if not b.fgManaged then
        b:SetWidth(width)
      end
    end
  end)
  b:SetScript("OnEnter", function()
    b.fgHover = true
    paintAction(b)
  end)
  b:SetScript("OnLeave", function()
    b.fgHover, b.fgPressed = false, false
    paintAction(b)
  end)
  b:SetScript("OnMouseDown", function()
    b.fgPressed = true
    paintAction(b)
  end)
  b:SetScript("OnMouseUp", function()
    b.fgPressed = false
    paintAction(b)
  end)
  b:HookScript("OnEnable", function()
    paintAction(b)
  end)
  b:HookScript("OnDisable", function()
    b.fgHover, b.fgPressed = false, false
    paintAction(b)
  end)
  if opts.onClick then
    b:SetScript("OnClick", ns.Wrap(opts.wrap or "action", opts.onClick))
  end
  local tip = opts.tooltip or (opts.label and not hasText and opts.label) or nil
  if tip then
    b:HookScript("OnEnter", function(self)
      local extra = opts.shortcut and { hint = string.format(L["act.shortcut"], opts.shortcut) } or nil
      ns.ShowTooltip(self, L[tip], opts.tooltipText and L[opts.tooltipText], extra)
    end)
    b:HookScript("OnLeave", ns.HideTooltip)
  end
  Focus.register(b, function(self)
    self:Click()
  end)
  -- The close icon in the title strip of a window shell is the window close button: the skin dresses it.
  if (opts.icon == "close" or opts.glyph == "x") and ns.WindowShell and ns.WindowShell.IsTitleBar(parent) then
    ns.Skins.Close(b)
  end
  if b.fgHasLabel then
    b:SetWidth(b:Fit(opts.width))
  end
  return b
end

-- opts: key|text, variant (primary, secondary, ghost, gold), width, height, onClick, tooltip
-- (locale key), tooltipText (locale key). Thin adapter on W.Action.
function W.Button(parent, opts)
  return W.Action(parent, {
    key = opts.key,
    text = opts.text,
    variant = opts.variant or "secondary",
    width = opts.width or 120,
    height = opts.height or 26,
    onClick = opts.onClick,
    tooltip = opts.tooltip,
    tooltipText = opts.tooltipText,
    wrap = "button",
  })
end

-- opts: icon (texture path or fileID, or the name of an icon of ns.UI_ICONS), size, tooltip,
-- onClick, glyph (text instead of icon), boxed (surface and edge like a secondary button, for
-- actions that must read as buttons). Thin adapter on W.Action. The "x" in the title strip of a
-- window shell becomes the close icon at the common close size.
function W.IconButton(parent, opts)
  local spec = {
    size = opts.size or 24,
    boxed = opts.boxed,
    glyph = opts.glyph,
    tooltip = opts.tooltip,
    tooltipText = opts.tooltipText,
    onClick = opts.onClick,
    wrap = "icon-button",
  }
  if type(opts.icon) == "string" and ns.UI_ICONS[opts.icon] then
    spec.icon = opts.icon
  else
    spec.texture = opts.icon
  end
  if opts.glyph == "x" and ns.WindowShell and ns.WindowShell.IsTitleBar(parent) then
    spec.glyph, spec.icon, spec.size = nil, "close", W.CLOSE_SIZE
  end
  return W.Action(parent, spec)
end

-- Map and Marker buttons for one place (trainer, weapon master, access condition): two boxed icon
-- buttons, left to right. The actions are K.PlaceOnMap (addon map page) and K.PlaceMarker
-- (waypoint), so every page does the same. bar:SetPlace(place) takes the place table or a
-- function returning it (see PageKit), nil hides the bar. The name of each button is its tooltip,
-- shown on hover and on keyboard focus.
W.MAP_ACTION_SIZE = 24
W.MAP_ACTION_GAP = 4
W.MARKER_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7"
function W.MapActionButtons(parent, opts)
  opts = opts or {}
  local size = opts.size or W.MAP_ACTION_SIZE
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetSize(size * 2 + W.MAP_ACTION_GAP, size)
  local function make(icon, action, titleKey, tipKey)
    local b = W.Action(bar, {
      icon = icon,
      size = size,
      boxed = true,
      tooltip = titleKey,
      tooltipText = tipKey,
      onClick = function()
        if bar.place then
          ns.PageKit[action](bar.place)
        end
      end,
    })
    b.fgOnFocus = function()
      ns.ShowTooltip(b, L[titleKey], L[tipKey])
    end
    b.fgOnBlur = ns.HideTooltip
    return b
  end
  bar.map = make("map", "PlaceOnMap", "kit.placeMap", opts.mapTip or "kit.placeMapTip")
  bar.map:SetPoint("LEFT")
  bar.marker = make("marker", "PlaceMarker", "kit.placeMarker", opts.markerTip or "kit.placeMarkerTip")
  bar.marker:SetPoint("LEFT", bar.map, "RIGHT", W.MAP_ACTION_GAP, 0)
  function bar:SetPlace(place)
    self.place = place
    self:SetShown(place ~= nil)
  end
  return bar
end

-- The "x" in the top right corner of every settings panel of a floating window. opts.onClick
-- defaults to closing the open popup group; the caller anchors the title left of it.
W.CLOSE_SIZE = 20
function W.CloseButton(parent, opts)
  opts = opts or {}
  local b = W.Action(parent, {
    icon = "close",
    size = W.CLOSE_SIZE,
    boxed = true,
    tooltip = "common.close",
    onClick = opts.onClick or function()
      ns.Desktop.Layer.close("button")
    end,
  })
  b:SetPoint("TOPRIGHT", -4, -4)
  return b
end

function W.HelpIcon(parent, titleKey, textKey)
  return W.Action(parent, { icon = "help", size = 20, tooltip = titleKey, tooltipText = textKey })
end

-- Round "i" button that shows a bulleted tooltip on hover and on keyboard focus. textKeys is
-- a locale key or a list of keys, every line of their texts becomes one bullet.
W.INFO_SIZE = 20
function W.InfoButton(parent, titleKey, textKeys)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(W.INFO_SIZE, W.INFO_SIZE)
  local icon = W.Glyph(b, "info", W.INFO_SIZE - 4, "textSecondary")
  icon:SetPoint("CENTER", 0, 0)
  b.icon = icon
  local keys = type(textKeys) == "table" and textKeys or { textKeys }
  local shown = false
  local function show()
    local lines = {}
    for _, key in ipairs(keys) do
      for line in L[key]:gmatch("[^\n]+") do
        lines[#lines + 1] = "- " .. line
      end
    end
    shown = true
    icon:SetColorToken("accent")
    ns.ShowTooltip(b, L[titleKey], table.concat(lines, "\n"))
  end
  local function hide()
    if shown then
      shown = false
      icon:SetColorToken("textSecondary")
      ns.HideTooltip()
    end
  end
  b:SetScript("OnEnter", show)
  b:SetScript("OnLeave", hide)
  b:SetScript("OnHide", hide)
  b:SetScript("OnClick", show)
  b.fgOnFocus, b.fgOnBlur = show, hide
  Focus.register(b, function(self)
    self:Click()
  end)
  return b
end

function W.Badge(parent, key, colorName)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(18)
  f.colorName = colorName or "accent2"
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  local text = W.Text(f, { key = key, role = "micro", color = f.colorName, justify = "CENTER" })
  text:SetPoint("CENTER")
  local border = W.Border(f, f.colorName, 0.6)
  local function paint()
    bg:SetColorTexture(Theme.color(f.colorName, 0.15))
    f:SetWidth(text:GetStringWidth() + 14)
  end
  ns.Bind(f, paint)
  f.text = text
  -- Repaints a pooled badge for a new locale key/color without leaking a
  -- new frame, used by card grids that reuse badge frames across refreshes.
  function f:SetKey(newKey, newColorName)
    f.colorName = newColorName or f.colorName
    W.SetText(text, newKey)
    W.SetColor(text, f.colorName)
    border.set(f.colorName, 0.6)
    paint()
  end
  return f
end

-- Empty state: a centered message for a page or pane without content. opts: text (locale key),
-- hint (optional second line, locale key), icon (optional name of ns.UI_ICONS, shown 32 px above
-- the text, gray). The text is h3 in textSecondary, wraps and takes at most 70 percent of the width.
-- In a W.Stack the widget takes all the room the page has left (viewport height minus what lies
-- above it, so the page does not scroll); add it with { gap = 0 }. Standalone, f:Fill() anchors it
-- to the whole parent and it follows the parent's size. f:SetTexts(text, hint) changes the lines.
W.EMPTY_ICON_SIZE = 32
local EMPTY_MAX_SHARE, EMPTY_ICON_GAP, EMPTY_HINT_GAP, EMPTY_MARGIN = 0.7, 10, 6, 16

function W.EmptyState(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  local group = CreateFrame("Frame", nil, f)
  f.group = group
  if opts.icon then
    f.icon = W.Glyph(group, opts.icon, W.EMPTY_ICON_SIZE, "textMuted")
  end
  f.text = W.Text(group, { key = opts.text, role = "h3", color = "textSecondary", wrap = true, justify = "CENTER" })
  f.hint = W.Text(group, { key = opts.hint, role = "ui", color = "textMuted", wrap = true, justify = "CENTER" })
  f.hint:SetShown(opts.hint ~= nil)

  -- Places icon, text and hint as one block in the middle of the widget.
  function f:Relayout(width)
    local w = math.max(1, math.floor(width * EMPTY_MAX_SHARE))
    local y = 0
    if f.icon then
      f.icon:ClearAllPoints()
      f.icon:SetPoint("TOP", group, "TOP", 0, 0)
      y = W.EMPTY_ICON_SIZE + EMPTY_ICON_GAP
    end
    f.text:SetWidth(w)
    f.text:ClearAllPoints()
    f.text:SetPoint("TOP", group, "TOP", 0, -y)
    y = y + f.text:GetStringHeight()
    if f.hint:IsShown() then
      f.hint:SetWidth(w)
      f.hint:ClearAllPoints()
      f.hint:SetPoint("TOP", group, "TOP", 0, -(y + EMPTY_HINT_GAP))
      y = y + EMPTY_HINT_GAP + f.hint:GetStringHeight()
    end
    group:SetSize(w, y)
    group:ClearAllPoints()
    group:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.minHeight = y + EMPTY_MARGIN * 2
  end

  function f:SetTexts(textKey, hintKey)
    W.SetText(f.text, textKey)
    W.SetText(f.hint, hintKey)
    f.hint:SetShown(hintKey ~= nil)
    if f.fgWidth then
      f:Relayout(f.fgWidth)
    end
  end

  -- Stack hook: width of the page column, ctx = room left (see W.Stack).
  function f:fgGridLayout(width, ctx)
    f.fgWidth = width
    f:Relayout(width)
    local h = f.minHeight
    if ctx and ctx.viewHeight and ctx.viewHeight > 0 then
      h = math.max(h, ctx.viewHeight - ctx.top - ctx.gap - ctx.pad)
    end
    f:SetHeight(h)
    return h
  end

  function f:Fill()
    f:ClearAllPoints()
    f:SetAllPoints(parent)
    f:SetScript("OnSizeChanged", function(_, width)
      if width and width > 0 then
        f.fgWidth = width
        f:Relayout(width)
      end
    end)
    f.fgWidth = parent:GetWidth()
    f:Relayout(f.fgWidth)
    return f
  end

  ns.Bind(f, function()
    if f.fgWidth then
      f:Relayout(f.fgWidth)
    end
  end)
  f:Relayout(math.max(1, parent:GetWidth() or 1))
  return f
end

-- Card: surface panel with optional title, content anchored below it.
function W.Card(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  W.FadeWithWindow(W.Fill(f, "surface", 1))
  W.Border(f, "white")
  local top = -12
  if opts.key or opts.text then
    f.title = W.Text(f, { key = opts.key, text = opts.text, role = "h3", family = "heading", color = "accent2" })
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetPoint("RIGHT", -12, 0)
    top = -34
  end
  f.contentTop = top
  return f
end

-- Toggle and checkbox -----------------------------------------------------

-- Check mark drawn from two line strokes, so no client texture or font glyph is
-- needed (the Blizzard check texture is missing in the Forever client and left
-- only its backing chip visible). Without line objects a solid square stands in.
-- Returns a frame of `size` px; show and hide it like any frame. colorName is a
-- Theme token that follows theme changes. Without it the owner sets the color
-- with mark:Tint(r, g, b) and the size with mark:Fit(size), so a pooled mark can
-- be reused at another size and color.
function W.CheckMark(parent, size, colorName)
  local mark = CreateFrame("Frame", nil, parent)
  mark.strokes = {}
  local lines = ns.can.lineObject
  local pts = { { 0.14, 0.50, 0.40, 0.22 }, { 0.40, 0.22, 0.86, 0.80 } }
  for i = 1, lines and #pts or 1 do
    mark.strokes[i] = lines and mark:CreateLine(nil, "OVERLAY") or mark:CreateTexture(nil, "OVERLAY")
  end
  function mark:Fit(px)
    self:SetSize(px, px)
    if lines then
      for i, line in ipairs(self.strokes) do
        local p = pts[i]
        line:SetThickness(math.max(2, math.floor(px / 6 + 0.5)))
        line:SetStartPoint("BOTTOMLEFT", self, p[1] * px, p[2] * px)
        line:SetEndPoint("BOTTOMLEFT", self, p[3] * px, p[4] * px)
      end
    else
      self.strokes[1]:ClearAllPoints()
      self.strokes[1]:SetPoint("CENTER")
      self.strokes[1]:SetSize(math.floor(px / 2), math.floor(px / 2))
    end
  end
  function mark:Tint(r, g, b)
    for _, stroke in ipairs(self.strokes) do
      stroke:SetColorTexture(r, g, b, 1)
    end
  end
  mark:Fit(size)
  if colorName then
    ns.Bind(mark, function()
      mark:Tint(Theme.color(colorName))
    end)
  end
  return mark
end

-- opts: key (label), get(), set(value), tooltip
function W.Toggle(parent, opts)
  local f = CreateFrame("Button", nil, parent)
  f:SetHeight(24)
  local track = CreateFrame("Frame", nil, f)
  track:SetSize(36, 18)
  track:SetPoint("LEFT")
  local trackBg = track:CreateTexture(nil, "BACKGROUND")
  trackBg:SetAllPoints()
  local trackBorder = W.Border(track, "white")
  local knob = track:CreateTexture(nil, "ARTWORK")
  knob:SetSize(14, 14)
  local state = W.Text(f, { role = "micro", color = "textMuted" })
  state:SetPoint("LEFT", track, "RIGHT", 6, 0)
  state:SetWidth(30)
  local label = W.Text(f, { key = opts.key, role = "ui" })
  label:SetPoint("LEFT", state, "RIGHT", 4, 0)
  label:SetPoint("RIGHT")
  if opts.quality then
    -- A quality name in its item color; the name stays in the text.
    ns.Bind(label, function(fs)
      fs:SetText(ns.ItemInfo.ColorName(L[opts.key], opts.quality))
    end)
  end
  local function paint()
    local on = opts.get() and true or false
    trackBg:SetColorTexture(Theme.color(on and "action" or "surface3"))
    trackBorder.set(on and "actionHi" or "white", on and 1 or nil)
    knob:ClearAllPoints()
    knob:SetPoint(on and "RIGHT" or "LEFT", on and -2 or 2, 0)
    knob:SetColorTexture(Theme.color(on and "text" or "textMuted"))
    -- State as text too, never color alone.
    state:SetText(on and L["common.on"] or L["common.off"])
  end
  ns.Bind(f, paint)
  f:SetScript(
    "OnClick",
    ns.Wrap("toggle", function()
      opts.set(not opts.get())
      paint()
    end)
  )
  attachTooltip(f, opts.tooltip, opts.tooltipText)
  Focus.register(f, function(self)
    self:Click()
  end)
  f.Refresh = paint
  return f
end

function W.Checkbox(parent, opts)
  local f = CreateFrame("Button", nil, parent)
  f:SetHeight(22)
  local box = CreateFrame("Frame", nil, f)
  box:SetSize(16, 16)
  box:SetPoint("LEFT")
  W.Fill(box, "surface2")
  local boxOn = W.Fill(box, "action", 1)
  local border = W.Border(box, "white", 0.4)
  local check = W.CheckMark(box, 12, "text")
  check:SetPoint("CENTER")
  local label = W.Text(f, { key = opts.key, text = opts.text, role = "ui" })
  label:SetPoint("LEFT", box, "RIGHT", 8, 0)
  label:SetPoint("RIGHT")
  local function paint()
    local on = opts.get() and true or false
    check:SetShown(on)
    boxOn:SetShown(on)
    border.set(on and "actionHi" or "white", on and 1 or 0.4)
  end
  ns.Bind(f, paint)
  f:SetScript(
    "OnClick",
    ns.Wrap("checkbox", function()
      opts.set(not opts.get())
      paint()
    end)
  )
  attachTooltip(f, opts.tooltip, opts.tooltipText)
  Focus.register(f, function(self)
    self:Click()
  end)
  f.Refresh = paint
  return f
end

-- Slider ------------------------------------------------------------------

-- The thumb of a slider, the spot a window zoom scales around so it stays under the mouse.
function W.ThumbAnchor(s)
  return s.GetThumbTexture and s:GetThumbTexture() or s
end

-- Sliders that change the size or zoom of a window apply on release: while the thumb is held only
-- the number follows (opts.preview), letting go applies the last value once (opts.commit). Wheel and
-- arrow keys are single steps: gate.flush() first, so they apply at once. Slider s.fgHeld is true
-- while the thumb is held. Returns gate.change(v) for every value the player produces.
function W.ReleaseGate(s, opts)
  local pending
  local gate = {}
  function gate.flush()
    s.fgHeld = false
    if pending ~= nil then
      local v = pending
      pending = nil
      opts.commit(v)
    end
  end
  function gate.change(v)
    if s.fgHeld and type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
      gate.flush()
    end
    if s.fgHeld then
      pending = v
      opts.preview(v)
    else
      pending = nil
      opts.commit(v)
    end
  end
  s:HookScript("OnMouseDown", function()
    s.fgHeld = true
  end)
  s:HookScript("OnMouseUp", gate.flush)
  s:HookScript("OnHide", gate.flush)
  return gate
end

-- opts: key, min, max, step, get(), set(v, anchor), format(v) -> string
-- applyOn = "release": set runs once when the thumb is let go (anchor: the thumb), see W.ReleaseGate.
function W.Slider(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(42)
  local label = W.Text(f, { key = opts.key, role = "ui" })
  label:SetPoint("TOPLEFT")
  local value = W.Text(f, { role = "ui", color = "accent2", justify = "RIGHT" })
  value:SetPoint("TOPRIGHT")
  local s = CreateFrame("Slider", nil, f)
  s:SetOrientation("HORIZONTAL")
  s:EnableMouse(true)
  s:SetHeight(16)
  s:SetPoint("TOPLEFT", 0, -20)
  s:SetPoint("TOPRIGHT", 0, -20)
  s:SetMinMaxValues(opts.min, opts.max)
  s:SetValueStep(opts.step)
  if s.SetObeyStepOnDrag then
    s:SetObeyStepOnDrag(true)
  end
  -- Light outline behind the track: stays visible on a see-through window.
  local rim = s:CreateTexture(nil, "BACKGROUND")
  rim:SetDrawLayer("BACKGROUND", -1)
  rim:SetPoint("LEFT", -1, 0)
  rim:SetPoint("RIGHT", 1, 0)
  rim:SetHeight(6)
  rim:SetColorTexture(1, 1, 1, 0.35)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetHeight(4)
  local thumb = s:CreateTexture(nil, "ARTWORK")
  thumb:SetSize(10, 16)
  s:SetThumbTexture(thumb)
  ns.Bind(s, function()
    track:SetColorTexture(Theme.color("surface3"))
    thumb:SetColorTexture(Theme.color("accent2"))
  end)
  local fmt = opts.format or tostring
  local syncing = false
  local function sync()
    if s.fgHeld then
      return
    end
    syncing = true
    s:SetValue(opts.get())
    value:SetText(fmt(opts.get()))
    syncing = false
  end
  local gate = opts.applyOn == "release"
    and W.ReleaseGate(s, {
      preview = function(v)
        value:SetText(fmt(v))
      end,
      commit = function(v)
        value:SetText(fmt(v))
        opts.set(v, W.ThumbAnchor(s))
      end,
    })
  s:SetScript(
    "OnValueChanged",
    ns.Wrap("slider", function(_, v)
      if syncing then
        return
      end
      v = ns.U.round(v, opts.step)
      if gate then
        gate.change(v)
        return
      end
      value:SetText(fmt(v))
      opts.set(v)
    end)
  )
  local function move(delta)
    if gate then
      gate.flush()
    end
    s:SetValue(ns.U.clamp(s:GetValue() + delta * opts.step, opts.min, opts.max))
  end
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(_, delta)
    move(delta)
  end)
  Focus.register(s, nil)
  function s.fgArrow(_, delta)
    move(delta)
  end
  f.slider, f.valueText = s, value
  f.Refresh = sync
  sync()
  return f
end

-- Compact controls (footer, bars) ----------------------------------------------------------

-- Tooltip above the widget. textKey: a locale key, or a function that answers the final text.
local function hoverTip(widget, titleKey, textKey)
  widget:HookScript("OnEnter", function(self)
    local text = type(textKey) == "function" and textKey() or textKey and L[textKey]
    Tooltip.Show(self, { title = L[titleKey], text = text, anchor = "ANCHOR_TOP" })
  end)
  widget:HookScript("OnLeave", function(self)
    Tooltip.Hide(self)
  end)
end

-- The number between a "-" and a "+" button; a click runs onClick (typically "back to default").
-- opts: width, height, onClick, tooltip (locale key), tooltipText (key or function -> text)
function W.ValueButton(parent, opts)
  local b = W.Action(parent, {
    text = "",
    variant = "ghost",
    width = opts.width or 32,
    height = opts.height or 18,
    onClick = opts.onClick,
    manual = true,
    wrap = "value-button",
  })
  b.text = b.label
  b.fgNameKey = opts.tooltip
  if opts.tooltip then
    hoverTip(b, opts.tooltip, opts.tooltipText)
  end
  return b
end

-- A short slider without label (drag, mouse wheel, arrow keys when focused). set(v) only runs for
-- changes of the player; s:Sync(v) moves the thumb without calling it.
-- opts: min, max, step, width, height, set(v), tooltip (locale key), tooltipText (key or function)
-- applyOn = "release": set(v) runs once when the thumb is let go, preview(v) while it is held.
function W.CompactSlider(parent, opts)
  local height = opts.height or 14
  local s = CreateFrame("Slider", nil, parent)
  s:SetOrientation("HORIZONTAL")
  s:EnableMouse(true)
  s:SetSize(opts.width or 76, height)
  s:SetMinMaxValues(opts.min, opts.max)
  s:SetValueStep(opts.step)
  if s.SetObeyStepOnDrag then
    s:SetObeyStepOnDrag(true)
  end
  local rim = s:CreateTexture(nil, "BACKGROUND")
  rim:SetDrawLayer("BACKGROUND", -1)
  rim:SetPoint("LEFT", 0, 0)
  rim:SetPoint("RIGHT", 0, 0)
  rim:SetHeight(6)
  rim:SetColorTexture(1, 1, 1, 0.35)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT", 1, 0)
  track:SetPoint("RIGHT", -1, 0)
  track:SetHeight(4)
  local thumb = s:CreateTexture(nil, "ARTWORK")
  thumb:SetSize(8, height)
  s:SetThumbTexture(thumb)
  ns.Bind(s, function()
    track:SetColorTexture(Theme.color("surface3"))
    thumb:SetColorTexture(Theme.color("accent2"))
  end)
  local syncing = false
  local gate = opts.applyOn == "release" and W.ReleaseGate(s, { preview = opts.preview, commit = opts.set })
  local function move(delta)
    if s:IsEnabled() then
      if gate then
        gate.flush()
      end
      s:SetValue(ns.U.clamp(s:GetValue() + delta * opts.step, opts.min, opts.max))
    end
  end
  s:SetScript(
    "OnValueChanged",
    ns.Wrap("compact-slider", function(self, v)
      if syncing or not self:IsEnabled() then
        return
      end
      self.fgValue = ns.U.round(v, opts.step)
      if gate then
        gate.change(self.fgValue)
        return
      end
      opts.set(self.fgValue)
    end)
  )
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(_, delta)
    move(delta)
  end)
  function s.fgArrow(_, delta)
    move(delta)
  end
  function s.Sync(self, v)
    if self.fgValue ~= v and not self.fgHeld then
      self.fgValue = v
      syncing = true
      self:SetValue(v)
      syncing = false
    end
  end
  if opts.tooltip then
    hoverTip(s, opts.tooltip, opts.tooltipText)
  end
  Focus.register(s, nil)
  return s
end

-- Tabs --------------------------------------------------------------------

-- opts: tabs = { { id, key } }, onSelect(id)
function W.Tabs(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(28)
  local line = f:CreateTexture(nil, "BACKGROUND")
  line:SetPoint("BOTTOMLEFT")
  line:SetPoint("BOTTOMRIGHT")
  line:SetHeight(1)
  ns.Bind(line, function(t)
    t:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)
  f.buttons = {}
  local prev
  for _, tab in ipairs(opts.tabs) do
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(28)
    b.label = W.Text(b, { key = tab.key, role = "ui", color = "textSecondary", justify = "CENTER" })
    b.label:SetPoint("CENTER")
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetPoint("BOTTOMRIGHT")
    b.bar:SetHeight(2)
    ns.Bind(b, function()
      b:SetWidth(b.label:GetStringWidth() + 24)
      b.bar:SetColorTexture(Theme.color("accent2"))
    end)
    b:SetPoint("BOTTOMLEFT", prev or f, prev and "BOTTOMRIGHT" or "BOTTOMLEFT", prev and 4 or 0, 0)
    b:SetScript(
      "OnClick",
      ns.Wrap("tab", function()
        f:Select(tab.id)
      end)
    )
    Focus.register(b, function(self)
      self:Click()
    end)
    f.buttons[tab.id] = b
    prev = b
  end
  function f:Select(id)
    f.selected = id
    for tid, b in pairs(f.buttons) do
      local on = tid == id
      b.bar:SetShown(on)
      W.SetColor(b.label, on and "accent" or "textSecondary")
    end
    if opts.onSelect then
      opts.onSelect(id)
    end
  end
  return f
end

-- Edit box ----------------------------------------------------------------

-- opts: placeholder (locale key), onEnter(text), onChange(text), clear (bool), inset (text margin, 8)
function W.EditBox(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(opts.height or 26)
  W.Fill(f, "bg", 0.9)
  local border = W.Border(f, "white", 0.25)
  local eb = CreateFrame("EditBox", nil, f)
  local inset = opts.inset or 8
  eb:SetPoint("TOPLEFT", inset, 0)
  eb:SetPoint("BOTTOMRIGHT", opts.clear and -24 or -inset, 0)
  eb:SetAutoFocus(false)
  ns.Bind(eb, function()
    Theme.applyFont(eb, "ui", "body")
    eb:SetTextColor(Theme.color("text"))
  end)
  local ph = W.Text(f, { key = opts.placeholder, role = "ui", color = "textMuted" })
  ph:SetPoint("LEFT", inset, 0)
  local clearBtn
  if opts.clear then
    clearBtn = W.Action(f, { icon = "close", size = 18, tooltip = "common.clear" })
    clearBtn:SetPoint("RIGHT", -4, 0)
    clearBtn:SetScript("OnClick", function()
      eb:SetText("")
      eb:ClearFocus()
    end)
  end
  local function update()
    local empty = eb:GetText() == ""
    ph:SetShown(empty and not eb:HasFocus())
    if clearBtn then
      clearBtn:SetShown(not empty)
    end
  end
  eb:SetScript(
    "OnTextChanged",
    ns.Wrap("editbox", function(_, user)
      update()
      if user and opts.onChange then
        opts.onChange(eb:GetText())
      end
    end)
  )
  eb:SetScript("OnEditFocusGained", function()
    border.set("actionHi", 1)
    update()
  end)
  eb:SetScript("OnEditFocusLost", function()
    border.set("white", 0.25)
    update()
  end)
  eb:SetScript("OnEscapePressed", function()
    eb:ClearFocus()
  end)
  eb:SetScript(
    "OnEnterPressed",
    ns.Wrap("editbox-enter", function()
      if opts.onEnter then
        opts.onEnter(eb:GetText())
      end
      eb:ClearFocus()
    end)
  )
  Focus.register(f, function()
    eb:SetFocus()
  end)
  f.edit = eb
  f.clearButton = clearBtn
  update()
  return f
end

-- Dropdown ----------------------------------------------------------------
-- Only one popup is open at a time; Esc (main window key handler) and a
-- click anywhere else close it.

local popup, blocker
ns.Popups = {}

function ns.Popups.close()
  if popup and popup:IsShown() then
    popup:Hide()
    blocker:Hide()
    return true
  end
  return false
end

local function getPopup()
  if popup then
    return popup
  end
  blocker = CreateFrame("Button", nil, UIParent)
  blocker:SetAllPoints(UIParent)
  -- Same strata as the popup (below it by level): dialogs in FULLSCREEN_DIALOG lie under the blocker too.
  blocker:SetFrameStrata("TOOLTIP")
  blocker:SetScript("OnClick", ns.Popups.close)
  blocker:Hide()
  popup = CreateFrame("Frame", nil, UIParent)
  popup:SetFrameStrata("TOOLTIP")
  popup:SetFrameLevel(blocker:GetFrameLevel() + 5)
  popup:SetClampedToScreen(true)
  W.Fill(popup, "surface", 1)
  W.Border(popup, "accentDim", 1)
  popup.rows = {}
  popup:Hide()
  return popup
end

-- opts: key (label), options = { { value, key|text, quality } }, get(), set(v), width, tooltip and tooltipText
-- (locale keys). An option with a quality shows its text in the item color of that quality.
function W.Dropdown(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(46)
  local label = W.Text(f, { key = opts.key, role = "ui" })
  label:SetPoint("TOPLEFT")
  f.label = label
  local b = CreateFrame("Button", nil, f)
  b:SetHeight(24)
  b:SetPoint("TOPLEFT", 0, -18)
  b:SetWidth(opts.width or 220)
  W.Fill(b, "surface2")
  W.Border(b, "white", 0.25)
  local current = W.Text(b, { role = "ui" })
  current:SetPoint("LEFT", 8, 0)
  local arrow = W.Glyph(b, "chevron-down", 12, "textMuted")
  arrow:SetPoint("RIGHT", -8, 0)
  local function optionText(o)
    local text = o.key and L[o.key] or o.text
    return o.quality and ns.ItemInfo.ColorName(text, o.quality) or text
  end
  local function textOf(value)
    for _, o in ipairs(opts.options) do
      if o.value == value then
        return optionText(o)
      end
    end
    return tostring(value)
  end
  local function paint()
    current:SetText(textOf(opts.get()))
  end
  ns.Bind(f, paint)
  local function open()
    local p = getPopup()
    for _, r in ipairs(p.rows) do
      r:Hide()
    end
    for i, o in ipairs(opts.options) do
      local r = p.rows[i]
      if not r then
        r = CreateFrame("Button", nil, p)
        r:SetHeight(22)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0)
        r.text = W.Text(r, { role = "ui" })
        r.text:SetPoint("LEFT", 8, 0)
        r:SetScript("OnEnter", function()
          r.hl:SetColorTexture(1, 1, 1, 0.08)
        end)
        r:SetScript("OnLeave", function()
          r.hl:SetColorTexture(1, 1, 1, 0)
        end)
        Focus.register(r, function(self)
          self:Click()
        end)
        p.rows[i] = r
      end
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 22)
      r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 22)
      r.text:SetText(optionText(o))
      W.SetColor(r.text, o.value == opts.get() and "accent" or "text")
      r:SetScript(
        "OnClick",
        ns.Wrap("dropdown", function()
          ns.Popups.close()
          opts.set(o.value)
          paint()
        end)
      )
      r:Show()
    end
    p:SetSize(b:GetWidth(), #opts.options * 22 + 2)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    p:SetScale(b:GetEffectiveScale() / UIParent:GetEffectiveScale())
    blocker:Show()
    p:Show()
    for i, o in ipairs(opts.options) do
      if o.value == opts.get() then
        Focus.set(p.rows[i])
      end
    end
  end
  b:SetScript(
    "OnClick",
    ns.Wrap("dropdown-open", function()
      if popup and popup:IsShown() then
        ns.Popups.close()
      else
        open()
      end
    end)
  )
  Focus.register(b, function()
    open()
  end)
  attachTooltip(b, opts.tooltip, opts.tooltipText)
  f.Refresh = paint
  return f
end
