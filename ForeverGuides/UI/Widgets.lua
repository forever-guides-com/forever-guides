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

-- Selected mark of a toggle (same show() as W.Border): a 2 px accent bar along the bottom edge, a cue that is
-- not a color. An outline box looks heavy, the bar matches the selected tab.
function W.ActiveMark(frame)
  local bar = frame:CreateTexture(nil, "ARTWORK")
  bar:SetPoint("BOTTOMLEFT")
  bar:SetPoint("BOTTOMRIGHT")
  bar:SetHeight(2)
  bar:Hide()
  local m = { bar = bar }
  function m.show(shown)
    bar:SetShown(shown == true)
  end
  ns.Bind(frame, function()
    bar:SetColorTexture(Theme.color("accent2"))
  end)
  return m
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
      f:SetText(f.fgCount and string.format("%s (%d)", L[f.fgKey], f.fgCount) or L[f.fgKey])
    elseif f.fgText then
      f:SetText(f.fgText)
    end
  end)
  return fs
end

-- Wraps a label at `width` and answers its height. The explicit height is dropped first: a client
-- FontString with a height clips to it and then measures the clipped text, so a label that once
-- fitted in fewer lines would never grow again.
function W.FitLabel(fs, width)
  fs:SetWordWrap(true)
  fs:SetWidth(math.max(1, width))
  fs:SetHeight(0)
  return math.ceil(fs:GetStringHeight() or 0)
end

-- Meta line that carries a decision (level, count, data state): role small in textSecondary.
-- Footnotes stay role micro in textMuted.
function W.Meta(parent, opts)
  opts = opts or {}
  return W.Text(parent, {
    key = opts.key,
    text = opts.text,
    role = opts.role or "small",
    color = opts.color or "textSecondary",
    wrap = opts.wrap,
    justify = opts.justify,
    family = opts.family,
  })
end

function W.SetText(fs, keyOrNil, literal)
  fs.fgKey, fs.fgText = keyOrNil, literal
  fs:SetText(keyOrNil and L[keyOrNil] or literal or "")
end

-- Appends the count to the keyed text of a section heading: "Zones (25)"; nil removes it.
function W.SetCount(fs, count)
  fs.fgCount = count
  if fs.fgKey then
    fs:SetText(count and string.format("%s (%d)", L[fs.fgKey], count) or L[fs.fgKey])
  end
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
--   lines may be a function(tip) that returns the list after the head is filled (to read what the client wrote).
--   icon (texture path or fileID) goes in front of the first line, e.g. the item icon in front of its name.
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
  if spec.icon and (filled or spec.title) then
    local name = type(tip.GetName) == "function" and tip:GetName()
    local first = name and rawget(_G, name .. "TextLeft1")
    local text = first and first:GetText()
    if text then
      first:SetText("|T" .. tostring(spec.icon) .. ":18:18:0:0:64:64:5:59:5:59|t " .. text)
    end
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

-- Puts the shared tooltip over its owner's window: another add-on may have moved it out of the top strata, and a
-- popup in the TOOLTIP strata would otherwise sit above the tooltip of its own entries. Every code path
-- that fills GameTooltip itself calls this after SetOwner (tests/test_strata.lua).
-- In the TOOLTIP strata the level is the engine maximum (TopLayer.LEVEL_CAP): window borders, edge frames and
-- the overlays of TopLayer (pinned window around 9000 plus up to five layers) all lie below it.
Tooltip.TOP_LEVEL = 10000

function Tooltip.Lift(tip, owner)
  if not tip then
    return
  end
  if tip.SetFrameStrata and tip.GetFrameStrata and tip:GetFrameStrata() ~= "TOOLTIP" then
    tip:SetFrameStrata("TOOLTIP")
  end
  if owner and owner.GetFrameStrata and owner:GetFrameStrata() == "TOOLTIP" and tip.SetFrameLevel then
    tip:SetFrameLevel(Tooltip.TOP_LEVEL)
  end
end

function Tooltip.Show(owner, spec)
  local tip = rawget(_G, "GameTooltip")
  if not (tip and owner) then
    return false
  end
  tip:SetOwner(owner, spec.anchor or "ANCHOR_RIGHT")
  Tooltip.Lift(tip, owner)
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
  local lines = spec.lines
  if type(lines) == "function" then
    local ok, list = pcall(lines, tip)
    lines = ok and list or nil
  end
  for _, line in ipairs(lines or {}) do
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
  tip:Show()
  tip.fgCompare = nil
  if item and ns.ItemActions then
    ns.ItemActions.Compare(tip)
  end
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

-- True while a single-line text is cut short by its width.
function W.IsCut(fs)
  if type(fs.IsTruncated) == "function" then
    local ok, cut = pcall(fs.IsTruncated, fs)
    if ok and type(cut) == "boolean" then
      return cut
    end
  end
  local room = fs:GetWidth()
  return type(room) == "number" and room > 0 and fs:GetStringWidth() > room + 0.5
end

-- A single-line text that may be cut with an ellipsis names itself in full in a tooltip on `frame`.
function W.TipWhenCut(frame, fs)
  frame:HookScript("OnEnter", function(self)
    if fs:IsShown() and W.IsCut(fs) then
      ns.ShowTooltip(self, fs:GetText() or "")
    end
  end)
  frame:HookScript("OnLeave", ns.HideTooltip)
end

-- Keyboard focus ----------------------------------------------------------
-- Tab/Shift+Tab walk visible focusables of the main window in creation
-- order, Enter/Space activates. The ring is one shared frame.

-- A window pinned to the top strata (the setup wizard, or the main window raised there over a Blizzard
-- view) hides everything that only sits in the same strata at a lower level. While one is shown, the
-- overlays (confirm dialogs, dropdown lists, popup menus, the focus ring) are put above it by level.
local TopLayer = {}
ns.TopLayer = TopLayer

local LEVEL_CAP, LAYER_STEP = 10000, 50
-- Overlay order from the bottom: click blocker, list or menu, nested menu, dialog, focus ring.
TopLayer.BLOCKER, TopLayer.LIST, TopLayer.SUB, TopLayer.DIALOG, TopLayer.RING = 1, 2, 3, 4, 5

-- The wizard sets owner; the main window counts only while it sits in the top strata.
local function pinnedWindows()
  local list = {}
  local owner = TopLayer.owner
  if owner and owner:IsShown() then
    list[#list + 1] = owner
  end
  local main = ns.Main and ns.Main.frame
  if main and main ~= owner and main:IsShown() and main:GetFrameStrata() == "TOOLTIP" then
    list[#list + 1] = main
  end
  return list
end

function TopLayer.Active()
  return #pinnedWindows() > 0
end

-- Highest frame level in a frame and its children.
local function treeTop(frame)
  local top = frame:GetFrameLevel()
  for _, child in ipairs({ frame:GetChildren() }) do
    top = math.max(top, treeTop(child))
  end
  return top
end

local function collectOffsets(frame, rootLevel, out)
  for _, child in ipairs({ frame:GetChildren() }) do
    out[#out + 1] = { child, child:GetFrameLevel() - rootLevel }
    collectOffsets(child, rootLevel, out)
  end
  return out
end

-- Puts an overlay frame (strata TOOLTIP) over every pinned window by frame level; layer orders overlays among
-- themselves (the TopLayer constants). The levels are set explicitly: Raise alone does not
-- keep a list above a window that is raised later. Children keep their offset. Returns whether it moved.
function TopLayer.Over(frame, layer)
  local windows = pinnedWindows()
  if #windows == 0 then
    return false
  end
  local base = 0
  for _, window in ipairs(windows) do
    base = math.max(base, treeTop(window))
  end
  local rootLevel = frame:GetFrameLevel()
  local children = collectOffsets(frame, rootLevel, {})
  local level = math.min(base + (layer or 1) * LAYER_STEP, LEVEL_CAP)
  frame:SetFrameLevel(level)
  for _, entry in ipairs(children) do
    entry[1]:SetFrameLevel(math.min(level + entry[2], LEVEL_CAP))
  end
  return true
end

-- Layers of our frames next to Blizzard windows ----------------------------------------------------------
-- A frame of ours that is a child of a Blizzard window sits at the window's strata, and frame levels count
-- across the whole strata: the window's own art (border frame, title, side panel) can lie above a level that
-- was only guessed as "window level plus N". Layer.Panel measures the levels of the window's own parts and
-- puts the panel above them. Rules (docs/notes/strata-audit.md): panels over Blizzard frame parts but never
-- above FULLSCREEN_DIALOG; dropdown lists, popup menus and tooltips in TOOLTIP above every panel.
local Layer = {}
ns.Layer = Layer

Layer.STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
Layer.CAP = 9990
Layer.GAP = 5 -- levels between the highest part of the window and our panel
Layer.MAX_PANEL = "FULLSCREEN_DIALOG"
local SCAN_DEPTH, SCAN_LIMIT, RESCAN = 3, 600, 1

function Layer.Rank(strata)
  for i, name in ipairs(Layer.STRATA) do
    if name == strata then
      return i
    end
  end
end

local function readNumber(frame, method)
  local ok, value = pcall(function()
    return frame[method](frame)
  end)
  return ok and type(value) == "number" and value == value and value or nil
end

-- Our own frames never count as a part of the window (the panel would chase itself upwards).
function Layer.Own(frame)
  frame.fgLayerOwn = true
  return frame
end

local function ownFrame(frame)
  local ok, name = pcall(function()
    return frame.fgLayerOwn or frame:GetName()
  end)
  return ok and (name == true or (type(name) == "string" and name:find("^ForeverGuides") ~= nil))
end

-- Highest level and strata rank over the parts of `host`: its children and theirs, down to SCAN_DEPTH.
-- `skip` is a set of frames (keys) left out with everything below them, like the map canvas whose pins have
-- their own levels.
local function scan(frame, depth, skip, acc)
  if depth < 1 or acc.count >= SCAN_LIMIT or type(frame.GetChildren) ~= "function" then
    return
  end
  local ok, children = pcall(function()
    return { frame:GetChildren() }
  end)
  if not ok then
    return
  end
  for _, child in ipairs(children) do
    if acc.count >= SCAN_LIMIT then
      return
    end
    if not (skip and skip[child]) and not ownFrame(child) then
      acc.count = acc.count + 1
      acc.level = math.max(acc.level, readNumber(child, "GetFrameLevel") or 0)
      local ok2, strata = pcall(child.GetFrameStrata, child)
      acc.rank = math.max(acc.rank, ok2 and Layer.Rank(strata) or 0)
      scan(child, depth - 1, skip, acc)
    end
  end
end

-- Returns the highest frame level of the parts of `host` (nil when none can be read) and the highest
-- strata rank among them (0 when none). `skip`: a set of children left out with everything below them.
function Layer.PartsTop(host, skip)
  local acc = { level = 0, rank = 0, count = 0 }
  scan(host, SCAN_DEPTH, skip, acc)
  if acc.count == 0 then
    return nil, 0
  end
  return acc.level, acc.rank
end

-- Sets the level of `frame` and moves its descendants by the same distance (the client may or may not do
-- that on its own, so it is set explicitly, like TopLayer.Over).
function Layer.SetTreeLevel(frame, level)
  local rootLevel = frame:GetFrameLevel()
  if rootLevel == level then
    return false
  end
  local children = collectOffsets(frame, rootLevel, {})
  frame:SetFrameLevel(level)
  for _, entry in ipairs(children) do
    entry[1]:SetFrameLevel(math.min(math.max(level + entry[2], 0), LEVEL_CAP))
  end
  return true
end

local lastScan = setmetatable({}, { __mode = "k" })

-- Puts `panel` (a child of `host`) above the parts of the host window: level at least `minLevel` and
-- GAP above the highest part, strata at least the host's own and the highest of its parts (never above
-- MAX_PANEL). `skip` leaves the canvas out. Cheap to call often: the host is measured once per second.
-- Returns the level now set.
function Layer.Panel(panel, host, minLevel, skip)
  local now = type(GetTime) == "function" and GetTime() or 0
  local cached = lastScan[panel]
  local top, rank
  if cached and cached.host == host and now > 0 and now - cached.at < RESCAN then
    top, rank = cached.top, cached.rank
  else
    top, rank = Layer.PartsTop(host, { [panel] = true, [skip or panel] = true })
    lastScan[panel] = { host = host, at = now, top = top, rank = rank }
  end
  local level = math.min(math.max(minLevel or 0, top and top + Layer.GAP or 0), Layer.CAP)
  local want = math.max(Layer.Rank(host:GetFrameStrata()) or 0, rank or 0, Layer.Rank(panel:GetFrameStrata()) or 0)
  want = math.min(want, Layer.Rank(Layer.MAX_PANEL))
  if want > 0 and Layer.Rank(panel:GetFrameStrata()) ~= want then
    panel:SetFrameStrata(Layer.STRATA[want])
  end
  Layer.SetTreeLevel(panel, level)
  return level
end

-- Enter and Space only act on a focus that keyboard navigation touched a moment ago (Focus.recent). An old focus
-- ring left on a window never takes the jump or the chat key away from the game.
local Focus = { items = {}, current = nil }
Focus.RECENT = 8
ns.Focus = Focus

function Focus.touch()
  Focus.keyAt = GetTime()
end

function Focus.recent()
  return Focus.keyAt ~= nil and GetTime() - Focus.keyAt <= Focus.RECENT
end

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

-- A row share icon (PageShare.RowButton) is invisible until its row is hovered or focused: keyboard navigation
-- reaches it only then, so a long list does not get a second stop per row.
local function visible(frame)
  return frame:IsVisible() and (not frame.IsEnabled or frame:IsEnabled()) and not (frame.fgRowIcon and frame:GetAlpha() < 0.01)
end

local function repaintShare(frame)
  local icon = frame and frame.fgRowShare
  if icon then
    icon.fgPaint()
  end
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

-- The ring is drawn over whatever the focused control sits in, also over a top-pinned window.
function Focus.Lift()
  if ring and ring:IsShown() then
    TopLayer.Over(ring, TopLayer.RING)
  end
end

function Focus.set(frame)
  Focus.touch()
  local previous = Focus.current
  if previous and previous ~= frame and previous.fgOnBlur then
    previous:fgOnBlur()
  end
  Focus.current = frame
  repaintShare(previous)
  repaintShare(frame)
  local r = getRing()
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
  r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
  r:Show()
  Focus.Lift()
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
  repaintShare(previous)
  Focus.keyAt = nil
  if ring then
    ring:Hide()
  end
  if previous and previous.fgOnBlur then
    previous:fgOnBlur()
  end
end

function Focus.move(step)
  -- Controls flagged fgFocusLast (the footer of the main window) come after everything else.
  local list, tail = {}, {}
  for _, f in ipairs(Focus.items) do
    if visible(f) then
      local into = f.fgFocusLast and tail or list
      into[#into + 1] = f
    end
  end
  for _, f in ipairs(tail) do
    list[#list + 1] = f
  end
  local index = 0
  for i, f in ipairs(list) do
    if f == Focus.current then
      index = i
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
  ["action.opensWindow"] = "Opens a new window",
  ["action.markerRightClick"] = "Right-click: set marker",
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
  ["act.enable"] = "Switch on",
  ["act.fit"] = "Fit",
  ["act.open"] = "Open",
  ["act.clear"] = "Clear",
  ["empty.loading"] = "Loading ...",
  ["empty.resetFilters"] = "Reset filters",
  ["act.restore"] = "Restore",
  ["act.closeAll"] = "Close all",
  ["act.backup"] = "Backup",
})

ns.AddLocale("deDE", {
  ["act.shortcut"] = "Tastenkürzel: %s",
  ["action.opensWindow"] = "Öffnet ein neues Fenster",
  ["action.markerRightClick"] = "Rechtsklick: Marker setzen",
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
  ["act.show"] = "Anzeigen",
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
  ["empty.loading"] = "Lädt ...",
  ["empty.resetFilters"] = "Filter zurücksetzen",
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
  confirm = {
    bg = "confirm",
    bgHover = "confirmHover",
    text = "text",
    textHover = "text",
    border = "success",
    borderAlpha = 0.8,
    ring = true,
  },
  secondary = {
    bg = "surface2",
    bgHover = "surface3",
    text = "text",
    textHover = "text",
    border = "accentDim",
    borderAlpha = 0.7,
    borderHover = "accent2",
  },
  -- Segment of a tab row (settings navigation): same face as W.Tabs.
  tab = {
    bg = "surface2",
    bgHover = "surface3",
    text = "textSecondary",
    textHover = "text",
    border = "accentDim",
    borderAlpha = 0.7,
    borderHover = "accent2",
  },
  ghost = { bgHover = "surface2", text = "textSecondary", textHover = "text", borderHover = "accentDim" },
  icon = {
    bgHover = "hover",
    hoverAlpha = Theme.fillAlpha.hover,
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
  -- Filled in the fixed purple of the channel link (white text, AA on both fills).
  stream = {
    bg = "stream",
    bgHover = "streamHi",
    text = "streamText",
    textHover = "streamText",
    border = "streamHi",
    borderAlpha = 1,
  },
  -- The footer Save button: a quiet button at rest (like a secondary one), a warning fill while data is unsaved
  -- (UI/SaveUI.lua). Text on both fills passes AA in every theme (tests/test_savestate.lua).
  save = {
    bg = "surface2",
    bgHover = "surface3",
    text = "text",
    textHover = "text",
    border = "accentDim",
    borderAlpha = 0.7,
    borderHover = "accent2",
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
    border = "accentDim",
    borderAlpha = 0.7,
    borderHover = "accent2",
  },
}
-- Forever look: the art family a variant takes in the skin "forever" (Skins.ART.slices: "redButton*" = the red
-- gold-rimmed button of the game for the few main actions). The dark quiet buttons keep the flat fill and hairline
-- of the theme: the game's dark button art has round end caps that do not survive slicing at every size (black
-- blobs in the corners). Variants of their own meaning (confirm, danger, gold, stream) and the bare ones (ghost,
-- icon) keep their fills as well.
local SKIN_FAMILY = {
  [VARIANTS.primary] = "redButton",
  [VARIANTS.saveDirty] = "redButton",
}
W.ACTION_VARIANTS = VARIANTS
W.ACTION_SIZES = { 24, 28, 32 }
W.ACTION_ICON_SIZE = 24 -- icon buttons without a label are square
local ACTION_PAD, ACTION_GAP, ACTION_SLACK = 8, 4, 4
W.ACTION_PAD = ACTION_PAD -- inset of a button label on each side

local function labelsOn()
  local settings = ns.db and ns.db.settings
  return not (settings and settings.buttonLabels == false)
end

-- Icon edge for a button height: 24 -> 14, 28 -> 16, 32 -> 18.
local function iconPixels(height)
  return math.max(14, math.min(18, math.floor(height * 0.58 + 0.5)))
end

-- Shows the art of the state of a button face (family "redButton") and hides the others; returns true
-- while the face is the game's art. The family has no hover art for red (the text answers), kinds the table lacks
-- are skipped.
local function paintFace(b, family, enabled, hover, pressed)
  local Skins = ns.Skins
  local slices = Skins.ART.slices
  local base = Skins.Apply(b, family)
  local function state(suffix, want)
    local kind = family .. suffix
    if slices[kind] then
      Skins.Apply(b, kind, want and base ~= nil)
    end
  end
  state("Hover", enabled and hover and not pressed)
  state("Pressed", enabled and pressed)
  state("Disabled", not enabled)
  return base ~= nil
end

local function hideFace(b, family)
  for _, suffix in ipairs({ "", "Hover", "Pressed", "Disabled" }) do
    local kind = family .. suffix
    if ns.Skins.ART.slices[kind] then
      ns.Skins.Apply(b, kind, false)
    end
  end
end

local function paintAction(b)
  local v = b.fgPalette
  local enabled = b:IsEnabled()
  local hover, pressed = b.fgHover and enabled, b.fgPressed and enabled
  local bgName, bgAlpha, text = v.bg, 1, v.text
  local edge, edgeAlpha = v.border, v.borderAlpha
  local family = ns.Skins.isForever() and SKIN_FAMILY[v] or nil
  local face = false
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
  if b.fgFaceFamily and b.fgFaceFamily ~= family then
    hideFace(b, b.fgFaceFamily)
  end
  if family then
    face = paintFace(b, family, enabled, hover, pressed)
  end
  b.fgFaceFamily = face and family or nil
  if face then
    -- Light text on the art in every state (the dark hover text of the flat fill would sit on red or dark brown).
    bgName, bgAlpha, edge = nil, 1, nil
    if enabled then
      text = (family == "redButton") and "text" or (hover and v.textHover or v.text)
    end
  end
  if b.fgSelected and enabled then
    -- A toggle that is on: filled, accent content and the accent bar (b.mark), never color alone.
    bgName, bgAlpha, text = "accent2", hover and 0.32 or 0.22, "accent"
    edge, edgeAlpha = "accent2", 1
  end
  -- A variant with a ring (v.ring) shows it in high contrast and colorblind mode: a cue that is not a color.
  local wantRing = v.ring == true and Theme.accessibleMode()
  if wantRing and not b.ring then
    b.ring = W.Border(b, "accent2", 1, 2)
  end
  if b.ring then
    b.ring.show(enabled and wantRing)
  end
  -- Selected: the accent bar, no outline box.
  if b.fgSelected and not b.mark then
    b.mark = W.ActiveMark(b)
  end
  if b.mark then
    b.mark.show(enabled and b.fgSelected == true)
  end
  if pressed and not face then
    if v.bg then
      local r, g, bl = Theme.rgb(bgName)
      b.bg:SetColorTexture(r * 0.7, g * 0.7, bl * 0.7, bgAlpha)
    else
      b.bg:SetColorTexture(Theme.color("bg", 0.5))
    end
  elseif bgName then
    b.bg:SetColorTexture(Theme.color(bgName, bgAlpha))
  else
    b.bg:SetColorTexture(ns.Theme.fillColor())
  end
  if edge then
    b.border.set(edge, edgeAlpha)
  end
  b.border.show(edge ~= nil)
  local dx, dy = pressed and 1 or 0, pressed and -1 or 0
  -- fgPlace exists only after the button is built; the first placement follows the build.
  if dx ~= b.fgDx and b.fgPlace then
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
  if b.opensMark then
    b.opensMark:SetColorToken(text)
    b.opensMark:SetAlpha(enabled and 1 or 0.5)
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
  local markShown = b.opensMark ~= nil and b.fgOpens and labelShown
  if b.opensMark then
    b.opensMark:SetShown(markShown)
    b.opensMark:ClearAllPoints()
    b.opensMark:SetPoint("RIGHT", b, "RIGHT", -ACTION_PAD + dx, dy)
  end
  if labelShown then
    -- b.fgPad: a layout that has no room for the usual inset (a tab row) narrows it for this button.
    local pad = b.fgPad or ACTION_PAD
    local inset = mark and (ACTION_PAD + (b.fgIconPx or 0) + ACTION_GAP) or pad
    local tail = pad + (markShown and b.fgOpensPx + ACTION_GAP or 0)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b, "LEFT", inset + dx, dy)
    b.label:SetPoint("RIGHT", b, "RIGHT", -tail + dx, dy)
  end
end

-- Width the "opens a new window" mark adds to a button that shows its label.
local function opensExtra(b)
  return b.opensMark and b.fgOpens and (b.fgOpensPx + ACTION_GAP) or 0
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
    return ACTION_PAD * 2 + b.fgIconPx + ACTION_GAP + text + ACTION_SLACK + opensExtra(b)
  end
  if b.label then
    return text + 24 + opensExtra(b)
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

-- Marks a control with what the settings search needs to know about it: its kind, the locale key of its
-- name, the key of an extra explanation (the tooltip text) and, for a button, the key of its short label (the
-- search takes it as the name when the tooltip is a whole sentence). Plain data on the frame, nothing is built.
local function describe(frame, kind, key, tipKey, labelKey)
  if key then
    frame.fgSetting = { kind = kind, key = key, tip = tipKey, label = labelKey ~= key and labelKey or nil }
  end
end

-- opts: key|text (fixed text), labelRole (font role of the text, default ui), label (short locale key, hidden by the setting "buttonLabels" and
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
-- opens: the button opens a window, dialog or page of its own (see docs/UI-FRAMEWORK.md). A button with
-- a label gets the "open" icon at its right edge (b.opensMark, the button grows by its width, the mark
-- is hidden together with a short label); every opens button adds "Opens a new window" to the tooltip
-- and to the accessible description (b.fgDescription()). opens = false makes b:SetOpens(on) available for buttons whose action
-- changes (the width stays as the owner set it).
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
  b.fgOpens = opts.opens == true
  if opts.opens ~= nil and (hasText or opts.label) and opts.icon ~= "open" then
    b.fgOpensPx = math.max(12, iconPixels(height) - 2)
    b.opensMark = W.Glyph(b, "open", b.fgOpensPx, v.text)
  end
  if opts.glyph then
    b.glyph = W.Text(b, { text = opts.glyph, role = "h3", color = v.text, justify = "CENTER" })
  elseif hasText or opts.label then
    b.label = W.Text(b, {
      key = hasText and opts.key or opts.label,
      text = opts.text,
      role = opts.labelRole or "ui",
      color = v.text,
      justify = "CENTER",
    })
  end
  b.fgPlace = placeContent
  placeContent(b)
  b:SetSize((opts.width or height) + (hasText and opensExtra(b) or 0), height)
  b.Fit, b.FullWidth = fitAction, fullWidth
  -- Toggle state: gold tint, gold edge, accent content and the accent bar.
  function b:SetSelected(on)
    on = on and true or false
    if on == self.fgSelected then
      return
    end
    self.fgSelected = on
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
  -- Turns the "opens a new window" mark and tooltip line on or off (needs opens = false at creation).
  function b:SetOpens(on)
    self.fgOpens = on == true
    placeContent(self)
  end
  -- Switches the palette (pooled buttons that change between plain and boxed).
  function b:SetVariant(name)
    self.fgPalette = VARIANTS[name] or VARIANTS.secondary
    paintAction(self)
  end
  b.fgNameKey = opts.tooltip or opts.label or opts.key
  describe(b, "action", opts.tooltip or opts.key or opts.label, opts.tooltipText, opts.key or opts.label)
  -- The accessible name as text (tests and audits read it).
  function b.fgName()
    return b.fgNameKey and L[b.fgNameKey] or nil
  end
  -- The accessible description: what the action does beyond its name.
  function b.fgDescription()
    return b.fgOpens and L["action.opensWindow"] or nil
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
  -- An opens button always has a tooltip, titled with its visible text when it names none.
  if tip or opts.opens ~= nil then
    b:HookScript("OnEnter", function(self)
      if not tip and not self.fgOpens then
        return
      end
      local hints = {}
      if opts.shortcut then
        hints[#hints + 1] = string.format(L["act.shortcut"], opts.shortcut)
      end
      if self.fgOpens then
        hints[#hints + 1] = L["action.opensWindow"]
      end
      local extra = #hints > 0 and { hint = table.concat(hints, "\n") } or nil
      local title = tip and L[tip] or (self.label and self.label:GetText()) or ""
      ns.ShowTooltip(self, title, opts.tooltipText and L[opts.tooltipText], extra)
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
-- (locale key), tooltipText (locale key), opens. Thin adapter on W.Action.
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
    opens = opts.opens,
    wrap = "button",
  })
end

-- State button ----------------------------------------------------------------------------------
-- One look for every on/off or selected button: idle face, lighter face on hover or focus, and when
-- on a raised face, an accent edge and a bar along the bottom (never color alone). "mixed" (part of a
-- selection is on) shows a short dash instead of the full bar.

-- Adds the state chrome (face, edge, bar, dash) to a button that has none; a button that owns b.bg
-- or b.border keeps them.
function W.StateChrome(b)
  if not b.bg then
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
  end
  if not b.border then
    b.border = W.Border(b, "accent2", 1)
    b.border.show(false)
  end
  b.fgBar = b:CreateTexture(nil, "OVERLAY")
  b.fgBar:SetHeight(2)
  b.fgBar:SetPoint("BOTTOMLEFT", 3, 2)
  b.fgBar:SetPoint("BOTTOMRIGHT", -3, 2)
  b.fgDash = b:CreateTexture(nil, "OVERLAY")
  b.fgDash:SetSize(10, 2)
  b.fgDash:SetPoint("BOTTOM", 0, 2)
end

-- Paints the chrome for state (true, false or "mixed"); returns the Theme token for the content.
function W.PaintState(b, state, hover, enabled)
  local tint = "textSecondary"
  local edge, edgeAlpha = nil, 1
  if not enabled then
    b.bg:SetColorTexture(Theme.fillColor())
    tint = "textMuted"
  elseif state == true then
    local r, g, bl = Theme.rgb("surface3")
    local lift = hover and 0.04 or 0
    b.bg:SetColorTexture(r + lift, g + lift, bl + lift, 1)
    edge, tint = "accent2", "accent"
  elseif state == "mixed" then
    b.bg:SetColorTexture(Theme.color("surface2"))
  elseif hover then
    b.bg:SetColorTexture(Theme.color("surface2"))
    edge, edgeAlpha, tint = "accentDim", 0.8, "text"
  else
    b.bg:SetColorTexture(Theme.fillColor())
  end
  if edge then
    b.border.set(edge, edgeAlpha)
  end
  b.border.show(edge ~= nil)
  local ar, ag, ab = Theme.rgb("accent2")
  b.fgBar:SetColorTexture(ar, ag, ab, 1)
  b.fgBar:SetShown(enabled and state == true)
  b.fgDash:SetColorTexture(ar, ag, ab, 1)
  b.fgDash:SetShown(enabled and state == "mixed")
  return tint
end

local stateGroups = setmetatable({}, { __mode = "k" })

-- opts: key|text (label), icon (name of ns.UI_ICONS or of a drawn symbol), chevron (small arrow for a
-- dropdown), level (the label sits right of the icon and shows a short value), tooltip + tooltipText
-- (locale keys), stateKeys = { on, off, mixed } (locale keys appended to the tooltip title as
-- "(state)"), checked, disabled, onChange(btn, checked), onClick(btn) (runs on every click, after the
-- state change), manual (a click does not change the state, the owner sets it with SetChecked: a
-- button that opens a popup or runs a command), group (any table or string; checking one button of a
-- group unchecks the others, a click on the checked one keeps it), height (26), width, scaled
-- (height follows the desktop scale), wrap (name for ns.Wrap).
-- b:SetChecked(true|false|"mixed") and b:GetChecked() never call onChange; b.fgState holds the state.
-- b:SetIcon(name), b:SetLabel(text) (literal), b:Paint().
function W.StateButton(parent, opts)
  local height = opts.height or 26
  local function px()
    return opts.scaled and ns.Desktop.scaled(height) or height
  end
  local b = CreateFrame("Button", nil, parent)
  b.fgState = false
  b:SetHeight(px())
  W.StateChrome(b)
  local shift = opts.chevron and -4 or 0
  local hasLabel = opts.key ~= nil or opts.text ~= nil
  -- Own content only: a caller may hang its own content on the button (b.icon, b.text, ...).
  local icon, label, chevron
  local drawn = opts.icon ~= nil and not ns.UI_ICONS[opts.icon]
  if opts.icon then
    if not drawn then
      icon = W.Glyph(b, opts.icon, 14, "textSecondary")
    else
      icon = ns.IconDraw.new(b, 14)
      icon:Draw(opts.icon)
    end
    icon:SetPoint("CENTER", shift + (opts.level and -6 or 0), 1)
  end
  if hasLabel or opts.level then
    label = W.Text(b, { key = opts.key, text = opts.text or "", role = "ui", color = "textSecondary", justify = "CENTER" })
    label:SetPoint("CENTER", shift + (opts.level and 9 or 0), 1)
  end
  if opts.chevron then
    chevron = ns.IconDraw.new(b, 8)
    chevron:SetPoint("RIGHT", -4, -1)
    chevron:Draw("chevron-down")
  end
  b.icon, b.label, b.chevron = icon, label, chevron
  b.fgNameKey = opts.tooltip or opts.key
  function b.fgName()
    return b.fgNameKey and L[b.fgNameKey] or nil
  end

  function b:Paint()
    local enabled = self:IsEnabled()
    local tint = W.PaintState(self, self.fgState, (self.fgHover or self.fgFocused) and enabled, enabled)
    if label then
      W.SetColor(label, tint)
    end
    if icon then
      if drawn then
        icon:SetTint(tint)
      else
        icon:SetColorToken(tint)
      end
      icon:SetAlpha(enabled and 1 or 0.45)
    end
    if chevron then
      chevron:SetTint(tint)
    end
  end
  ns.Bind(b, function()
    b:SetHeight(px())
    if opts.width then
      b:SetWidth(opts.width)
    elseif label and not icon then
      b:SetWidth(math.ceil(label:GetStringWidth()) + 32)
    elseif not label then
      b:SetWidth(height)
    end
    b:Paint()
  end)

  local group = opts.group
  if group ~= nil then
    stateGroups[group] = stateGroups[group] or {}
    table.insert(stateGroups[group], b)
  end
  function b:SetChecked(state)
    if state ~= true and state ~= "mixed" then
      state = false
    end
    self.fgState = state
    if state == true and group ~= nil then
      for _, other in ipairs(stateGroups[group]) do
        if other ~= self and other.fgState ~= false then
          other.fgState = false
          other:Paint()
        end
      end
    end
    self:Paint()
  end
  function b:GetChecked()
    return self.fgState == true
  end
  function b:SetIcon(name)
    if not icon then
      return
    end
    if drawn then
      if icon.glyph ~= name then
        icon:Draw(name)
      end
    else
      icon:SetIcon(name)
    end
  end
  function b:SetLabel(text)
    if label then
      W.SetText(label, nil, text)
    end
  end
  if opts.checked then
    b:SetChecked(true)
  end

  b:SetScript("OnEnter", function(self)
    self.fgHover = true
    self:Paint()
    if opts.tooltip then
      local title = L[opts.tooltip]
      local keys = opts.stateKeys
      if keys then
        local key = self.fgState == true and keys.on or (self.fgState == "mixed" and keys.mixed or keys.off)
        title = title .. " (" .. L[key] .. ")"
      end
      ns.ShowTooltip(self, title, opts.tooltipText and L[opts.tooltipText] or nil)
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.fgHover = false
    self:Paint()
    ns.HideTooltip()
  end)
  b.fgOnFocus = function(self)
    self.fgFocused = true
    self:Paint()
  end
  b.fgOnBlur = function(self)
    self.fgFocused = false
    self:Paint()
  end
  b:HookScript("OnEnable", b.Paint)
  b:HookScript("OnDisable", function(self)
    self.fgHover = false
    self:Paint()
  end)
  b:SetScript(
    "OnClick",
    ns.Wrap(opts.wrap or "state-button", function(self)
      if not opts.manual then
        local was = self.fgState == true
        if group ~= nil and was then
          return
        end
        self:SetChecked(not was)
        if opts.onChange then
          opts.onChange(self, not was)
        end
      end
      if opts.onClick then
        opts.onClick(self)
      end
    end)
  )
  Focus.register(b, function(self)
    self:Click()
  end)
  if opts.disabled then
    b:Disable()
    b:Paint()
  end
  return b
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
-- shown on hover and on keyboard focus. opts.compact: a single 24 px map button, the marker moves to the right
-- click (hint in the tooltip, bar.marker is nil); it works with opts.share. Opt-in, no page uses it by default.
W.MAP_ACTION_SIZE = 24
W.MAP_ACTION_GAP = 4
W.MARKER_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7"
function W.MapActionButtons(parent, opts)
  opts = opts or {}
  local size = opts.size or W.MAP_ACTION_SIZE
  local compact = opts.compact == true
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetSize(compact and size or (size * 2 + W.MAP_ACTION_GAP), size)
  local function make(icon, action, titleKey, tipKey, opens)
    local b = W.Action(bar, {
      icon = icon,
      size = size,
      boxed = true,
      tooltip = titleKey,
      tooltipText = tipKey,
      opens = opens,
      onClick = function()
        if bar.place then
          ns.PageKit[action](bar.place)
        end
      end,
    })
    b.fgOnFocus = function()
      ns.ShowTooltip(b, L[titleKey], L[tipKey], opens and { hint = L["action.opensWindow"] } or nil)
    end
    b.fgOnBlur = ns.HideTooltip
    return b
  end
  bar.map = make("map", "PlaceOnMap", "kit.placeMap", opts.mapTip or "kit.placeMapTip", true)
  if compact then
    -- One map button: left click opens the map, right click (Right arrow on the keyboard) sets the marker.
    local function marker()
      if bar.place then
        ns.PageKit.PlaceMarker(bar.place)
      end
    end
    local function showTip(b)
      local hint = table.concat({ L["action.opensWindow"], L["action.markerRightClick"] }, "\n")
      ns.ShowTooltip(b, L["kit.placeMap"], L[opts.mapTip or "kit.placeMapTip"], { hint = hint })
    end
    local map = bar.map
    map:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    map:SetScript(
      "OnClick",
      ns.Wrap("action", function(_, button)
        if button == "RightButton" then
          marker()
        elseif bar.place then
          ns.PageKit.PlaceOnMap(bar.place)
        end
      end)
    )
    map:HookScript("OnEnter", showTip)
    map.fgOnFocus = showTip
    -- Keyboard: Right arrow on the focused button sets the marker (Enter and Space open the map).
    function map.fgArrow(_, step)
      if step > 0 then
        marker()
      end
    end
    local plain = map.fgDescription
    function map.fgDescription()
      return (plain() and (plain() .. ". ") or "") .. L["action.markerRightClick"]
    end
  else
    bar.marker = make("marker", "PlaceMarker", "kit.placeMarker", opts.markerTip or "kit.placeMarkerTip")
  end
  -- opts.share: a third, rightmost icon that shares a page link (bar:SetShare). Without it the bar keeps
  -- its two-icon layout and the old show/hide rule.
  if opts.share then
    bar.share = ns.PageShare.Button(bar, { size = size })
  end
  local managed = opts.share or compact
  -- Buttons left to right: map and marker while a place is set, share while a payload is set.
  local function layout(self)
    local x, count = 0, 0
    for _, b in ipairs({ self.map, self.marker or false, self.share or false }) do
      if b and b:IsShown() then
        b:ClearAllPoints()
        b:SetPoint("LEFT", self, "LEFT", x, 0)
        x = x + size + W.MAP_ACTION_GAP
        count = count + 1
      end
    end
    local empty = compact and size or size * 2 + W.MAP_ACTION_GAP
    self:SetWidth(count > 0 and (x - W.MAP_ACTION_GAP) or empty)
    self:SetShown(count > 0)
  end
  function bar:SetPlace(place)
    self.place = place
    if not managed then
      self.map:SetPoint("LEFT")
      self.marker:SetPoint("LEFT", self.map, "RIGHT", W.MAP_ACTION_GAP, 0)
      self:SetShown(place ~= nil)
      return
    end
    self.map:SetShown(place ~= nil)
    if self.marker then
      self.marker:SetShown(place ~= nil)
    end
    layout(self)
  end
  -- Payload of the share icon (string or function), nil hides it. Needs opts.share.
  function bar:SetShare(payload)
    self.share:SetTarget(payload)
    layout(self)
  end
  if not managed then
    bar.map:SetPoint("LEFT")
    bar.marker:SetPoint("LEFT", bar.map, "RIGHT", W.MAP_ACTION_GAP, 0)
  else
    bar.map:SetPoint("LEFT")
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

-- True when s names a string of the locale tables, so a caller can hand over a key or a literal text.
local function isLocaleKey(s)
  return type(s) == "string" and ns.Locales.enUS[s] ~= nil
end

-- A small tinted label (NEW, soon). textOrKey is a locale key or a literal text, colorName a Theme token
-- (default accent2). The look is K.Tag, so contrast and size follow the page kit. Sizes itself on every
-- text or locale change; f:SetKey(textOrKey, colorName) repaints a pooled badge.
function W.Badge(parent, textOrKey, colorName)
  local f = ns.PageKit.Tag(parent)
  f.colorName = colorName or "accent2"
  f.text = f.label
  local function set(value, color)
    f.colorName = color or f.colorName
    local tag = { color = f.colorName }
    if isLocaleKey(value) then
      tag.key = value
    else
      tag.text = value
    end
    f:SetTag(tag)
    f:Fit()
  end
  function f:SetKey(value, color)
    set(value, color)
  end
  set(textOrKey)
  ns.Bind(f, function()
    f:Fit()
  end)
  return f
end

-- Empty state: a centered message for a page or pane without content. opts: text (locale key),
-- hint (optional second line, locale key), icon (optional name of ns.UI_ICONS, shown 32 px above
-- the text, gray). The text is h3 in textSecondary, wraps and takes at most 70 percent of the width.
-- In a W.Stack the widget takes all the room the page has left (viewport height minus what lies
-- above it, so the page does not scroll); add it with { gap = 0 }. Standalone, f:Fill() anchors it
-- to the whole parent and it follows the parent's size. f:SetTexts(text, hint) changes the lines.
-- action = { label (locale key), onClick } adds a button below the lines (f:SetAction(label, onClick)
-- sets or, with nil, removes it; W.EMPTY_RESET is the label for "reset filters"). compact = true keeps
-- the block at its own height inside a W.Stack instead of taking the room left, for result areas
-- that have other content below. f:SetLoading(true) shows the loading line (opts.loading starts so)
-- instead of text, hint and action; false returns to them.
W.EMPTY_ICON_SIZE = 32
W.EMPTY_RESET = "empty.resetFilters"
local EMPTY_MAX_SHARE, EMPTY_ICON_GAP, EMPTY_HINT_GAP, EMPTY_MARGIN, EMPTY_ACTION_GAP = 0.7, 10, 6, 16, 12

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
  f.textKey, f.hintKey, f.compact = opts.text, opts.hint, opts.compact
  local actions = {}

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
    if f.actionBtn and f.actionBtn:IsShown() then
      f.actionBtn:ClearAllPoints()
      f.actionBtn:SetPoint("TOP", group, "TOP", 0, -(y + EMPTY_ACTION_GAP))
      y = y + EMPTY_ACTION_GAP + f.actionBtn:GetHeight()
    end
    group:SetSize(w, y)
    group:ClearAllPoints()
    group:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.minHeight = y + EMPTY_MARGIN * 2
  end

  local function relayout()
    f:Relayout(f.fgWidth or math.max(1, parent:GetWidth() or 1))
  end

  function f:SetTexts(textKey, hintKey)
    f.textKey, f.hintKey = textKey, hintKey
    if not f.loading then
      W.SetText(f.text, textKey)
      W.SetText(f.hint, hintKey)
      f.hint:SetShown(hintKey ~= nil)
    end
    relayout()
  end

  function f:SetAction(labelKey, onClick)
    if f.actionBtn then
      f.actionBtn:Hide()
    end
    f.actionBtn = nil
    f.action = labelKey and { label = labelKey, onClick = onClick } or nil
    if labelKey and not f.loading then
      local btn = actions[labelKey]
      if not btn then
        btn = W.Button(group, {
          key = labelKey,
          onClick = function()
            if f.action and f.action.onClick then
              f.action.onClick()
            end
          end,
        })
        actions[labelKey] = btn
      end
      btn:Show()
      f.actionBtn = btn
    end
    relayout()
  end

  function f:SetLoading(on)
    on = on and true or false
    if on == (f.loading or false) then
      return
    end
    f.loading = on
    if on then
      W.SetText(f.text, "empty.loading")
      f.hint:Hide()
      if f.actionBtn then
        f.actionBtn:Hide()
        f.actionBtn = nil
      end
    else
      local action = f.action
      f:SetTexts(f.textKey, f.hintKey)
      if action then
        f:SetAction(action.label, action.onClick)
      end
    end
    relayout()
  end

  -- Stack hook: width of the page column, ctx = room left (see W.Stack).
  function f:fgGridLayout(width, ctx)
    f.fgWidth = width
    f:Relayout(width)
    local h = f.minHeight
    if not f.compact and ctx and ctx.viewHeight and ctx.viewHeight > 0 then
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
  if opts.action then
    f:SetAction(opts.action.label, opts.action.onClick)
  end
  if opts.loading then
    f:SetLoading(true)
  end
  return f
end

-- Panel: the one card and section building block. A surface that follows the window opacity with a
-- hairline border (opts.edge = token or "#rrggbb", opts.edgeAlpha: own rest border, for example a class
-- color), an optional header and the padding from Theme.space. opts: key|text (header title, heading
-- font in accent2), count (number after the title, key titles only), selected, frameType ("Button" for a
-- card that is clicked), capsTitle (locale key or text: instead of the title a header band like K.SectionCard,
-- gold capitals in the heading color with a rule below; default off). The frame offers:
--   f.pad            inner padding on all four sides (Theme.space.inset)
--   f.contentTop     y offset for the first content line (below the header when there is one)
--   f:SetCount(n)    number behind the title, nil removes it
--   f:SetActions(w)  puts a widget (button, row of buttons) at the right end of the header
--   f:SetHover(on)   accent edge and hover fill, set by the owner (the mouse belongs to the owner's script)
--   f:SetSelected(on) accent edge and selected fill
-- f.rim is the rest border and f.ring the accent border (2 px), only one of them shows. In the skin "forever" the
-- card art (Skins.Apply "card") takes the place of fill and rest border.
-- Line of the title of a box: a little above the padding (the text has leading), content 24 px below that line.
local function panelHeader(pad)
  return pad - 2, pad + 22
end

function W.Panel(parent, opts)
  opts = opts or {}
  local f = CreateFrame(opts.frameType or "Frame", nil, parent)
  local pad = Theme.space.inset
  local titleTop, headerBottom = panelHeader(pad)
  f.pad = pad
  local fill = W.FadeWithWindow(W.Fill(f, "surface", 1))
  f.rim = W.Border(f, opts.edge or "white", opts.edgeAlpha)
  f.ring = W.Border(f, "accent2", 1, 2)
  f.ring.show(false)
  f.wash = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  f.wash:SetAllPoints()
  f.wash:Hide()
  local top = -pad
  if opts.capsTitle then
    -- Header band like K.SectionCard: gold capitals, a rule below, content under the rule.
    local K = ns.PageKit
    local band = CreateFrame("Frame", nil, f)
    band.fgFlushTop = true -- the band starts at the card's top edge on purpose (see tests/pagematrix.lua)
    local headH = K.scaledHeight(Theme.size.sectionHeader)
    band:SetPoint("TOPLEFT", f, "TOPLEFT", pad, 0)
    band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, 0)
    band:SetHeight(headH)
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -headH)
    rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -headH)
    ns.Bind(f, function()
      rule:SetColorTexture(Theme.fillColor("line"))
    end)
    f.head = band
    f.title = W.Text(f, { role = "small", family = "heading", color = "heading" })
    f.title:SetPoint("LEFT", band, "LEFT", 0, 0)
    f.title:SetPoint("RIGHT", band, "RIGHT", 0, 0)
    local capsKey = isLocaleKey(opts.capsTitle) and opts.capsTitle or nil
    local function paintCaps()
      local text = K.Caps(capsKey and L[capsKey] or opts.capsTitle)
      f.title:SetText(f.capsCount and string.format("%s (%d)", text, f.capsCount) or text)
    end
    f.fgPaintCaps = paintCaps
    ns.Bind(f, paintCaps)
    top = -(headH + 1 + Theme.space.md)
  elseif opts.key or opts.text then
    f.title = W.Text(f, { key = opts.key, text = opts.text, role = "h3", family = "heading", color = "accent2" })
    f.title:SetPoint("TOPLEFT", pad, -titleTop)
    f.title:SetPoint("RIGHT", -pad, 0)
    top = -headerBottom
  end
  f.contentTop = top

  local hover, selected = false, false
  local function paint()
    local lit = hover or selected
    -- Forever: the card art of the game replaces fill and hairline. A rim of its own color (class color) stays.
    local art = ns.Skins.Apply(f, "card")
    fill:SetShown(art == nil)
    if art then
      W.FadeWithWindow(art)
    end
    f.ring.show(lit)
    f.rim.show(not lit and (art == nil or opts.edge ~= nil))
    f.wash:SetShown(lit)
    if lit then
      f.wash:SetColorTexture(Theme.fillColor(selected and "selected" or "hover"))
    end
  end
  ns.Bind(f, paint)
  function f:SetHover(on)
    hover = on == true
    paint()
  end
  function f:SetSelected(on)
    selected = on == true
    paint()
  end

  function f:SetCount(n)
    if f.fgPaintCaps then
      f.capsCount = n
      f.fgPaintCaps()
      return
    end
    local title = f.title
    if not (title and title.fgKey) then
      return
    end
    title.fgCount = n
    title:SetText(n and string.format("%s (%d)", L[title.fgKey], n) or L[title.fgKey])
  end

  function f:SetActions(widget)
    widget:ClearAllPoints()
    if f.head then
      widget:SetPoint("RIGHT", f.head, "RIGHT", 0, 0)
      f.title:ClearAllPoints()
      f.title:SetPoint("LEFT", f.head, "LEFT", 0, 0)
      f.title:SetPoint("RIGHT", widget, "LEFT", -Theme.space.sm, 0)
      f.actions = widget
      return
    end
    widget:SetPoint("TOPRIGHT", f, "TOPRIGHT", -pad, -(titleTop - 4))
    if f.title then
      f.title:ClearAllPoints()
      f.title:SetPoint("TOPLEFT", pad, -titleTop)
      f.title:SetPoint("RIGHT", widget, "LEFT", -Theme.space.sm, 0)
    end
    f.actions = widget
  end

  if opts.count then
    f:SetCount(opts.count)
  end
  if opts.selected then
    f:SetSelected(true)
  end
  return f
end

-- Card: Panel with an optional title, content anchored below it (f.contentTop).
function W.Card(parent, opts)
  return W.Panel(parent, opts)
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
  describe(f, "toggle", opts.key, opts.tooltipText)
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
  -- compact: track and state only, the name stays the accessible name and the tooltip (a row says the rest).
  label:SetShown(not opts.compact)
  -- labelInset: room between the state text and the name (a decorative icon of the caller sits there).
  label:SetPoint("LEFT", state, "RIGHT", 4 + (opts.labelInset or 0), 0)
  label:SetPoint("RIGHT")
  -- Outside a Stack the label stays one line (ellipsis, full name in the tooltip).
  if not opts.tooltip and not opts.compact then
    W.TipWhenCut(f, label)
  end
  -- In a Stack the label wraps and the row grows with it.
  function f:fgGridLayout(width)
    local h = 24
    if not opts.compact then
      local inset = 36 + 6 + 30 + 4 + (opts.labelInset or 0)
      label:ClearAllPoints()
      label:SetPoint("LEFT", state, "RIGHT", 4 + (opts.labelInset or 0), 0)
      h = math.max(h, W.FitLabel(label, width - inset) + 6)
    end
    self:SetHeight(h)
    return h
  end
  f.state = state
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
  describe(f, "toggle", opts.key, opts.tooltipText)
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
  if not opts.tooltip then
    W.TipWhenCut(f, label)
  end
  -- In a Stack the label wraps and the row grows with it.
  function f:fgGridLayout(width)
    label:ClearAllPoints()
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    local h = math.max(22, W.FitLabel(label, width - 24) + 6)
    self:SetHeight(h)
    return h
  end
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
  f.label, f.box = label, box
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
    -- The engine sets the value of a click before our OnMouseDown hook runs: a pressed button over the
    -- slider counts as held, so the write waits for the release and never runs inside the engine's handler.
    local down = type(IsMouseButtonDown) == "function" and IsMouseButtonDown("LeftButton")
    if not s.fgHeld and down and s:IsMouseOver() then
      s.fgHeld = true
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

-- The nearest ancestor of `frame` that scrolls with the mouse wheel: that frame and its handler, or nil.
local function wheelParent(frame)
  local p = frame:GetParent()
  while p do
    local handler = p.GetScript and p:GetScript("OnMouseWheel")
    if handler then
      return p, handler
    end
    p = p:GetParent()
  end
  return nil
end

-- The wheel over a slider scrolls the page it sits in. It adjusts the slider only after the slider was pressed
-- (until the pointer leaves it), while it has the keyboard focus, or when nothing around it scrolls.
local function wheelOnSlider(s, delta, move)
  if not (s.fgActive or Focus.current == s) then
    local parent, handler = wheelParent(s)
    if handler then
      handler(parent, delta)
      return
    end
  end
  move(delta)
end

-- While the thumb is held the value follows the pointer from here too: the engine's own drag did not follow
-- in the add-on windows (a click set the value, a drag did not), so the position of the pointer is read every
-- frame until the button is let go. The values it sets go through the normal OnValueChanged path.
local function followPointer(s)
  local function stop()
    s:SetScript("OnUpdate", nil)
  end
  local function step()
    local down, cursor = rawget(_G, "IsMouseButtonDown"), rawget(_G, "GetCursorPosition")
    if type(down) ~= "function" or type(cursor) ~= "function" or not down("LeftButton") then
      stop()
      return
    end
    local left, width, scale = s:GetLeft(), s:GetWidth(), s:GetEffectiveScale()
    local thumb = s.GetThumbTexture and s:GetThumbTexture()
    local thumbWidth = thumb and thumb:GetWidth() or 0
    local x = cursor()
    if not (type(left) == "number" and type(width) == "number" and type(scale) == "number" and type(x) == "number") then
      return
    end
    local usable = width - thumbWidth
    local lo, hi = s:GetMinMaxValues()
    if usable <= 0 or type(lo) ~= "number" or type(hi) ~= "number" or scale <= 0 then
      return
    end
    local v = lo + ns.U.clamp((x / scale - left - thumbWidth / 2) / usable, 0, 1) * (hi - lo)
    local unit = s:GetValueStep()
    if type(unit) == "number" and unit > 0 then
      v = lo + math.floor((v - lo) / unit + 0.5) * unit
    end
    v = ns.U.clamp(v, lo, hi)
    if v ~= s:GetValue() then
      s:SetValue(v)
    end
  end
  s:HookScript("OnMouseDown", function()
    s:SetScript("OnUpdate", step)
  end)
  s:HookScript("OnMouseUp", stop)
  s:HookScript("OnHide", stop)
end

-- Marks a slider as active while it is pressed and the pointer stays on it.
local function trackActive(s)
  s:HookScript("OnMouseDown", function()
    s.fgActive = true
  end)
  s:HookScript("OnLeave", function()
    s.fgActive = false
  end)
  s:HookScript("OnHide", function()
    s.fgActive = false
  end)
  followPointer(s)
end

-- opts: key, min, max, step, get(), set(v, anchor), format(v) -> string
-- applyOn = "release": set runs once when the thumb is let go (anchor: the thumb), see W.ReleaseGate.
-- tooltip + tooltipText (locale keys) show on the label row and on the track.
function W.Slider(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(42)
  describe(f, "slider", opts.key, opts.tooltipText)
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
  -- In a Stack the label wraps left of the value and the track moves below it.
  function f:fgGridLayout(width)
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT")
    local textH = W.FitLabel(label, width - math.ceil(value:GetStringWidth() or 0) - 8)
    local trackY = math.max(20, textH + 4)
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", 0, -trackY)
    s:SetPoint("TOPRIGHT", 0, -trackY)
    local h = trackY + 22
    self:SetHeight(h)
    return h
  end
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
  rim:SetColorTexture(Theme.fillColor("lineStrong"))
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
  -- A refresh while the thumb is held would pull it back from under the mouse and the drag would stick;
  -- a slider with a release gate marks the hold in the gate.
  if not gate then
    s:HookScript("OnMouseDown", function()
      s.fgHeld = true
    end)
    s:HookScript("OnMouseUp", function()
      s.fgHeld = false
      sync()
    end)
    s:HookScript("OnHide", function()
      s.fgHeld = false
    end)
  end
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
  trackActive(s)
  s:SetScript("OnMouseWheel", function(_, delta)
    wheelOnSlider(s, delta, move)
  end)
  Focus.register(s, nil)
  function s.fgArrow(_, delta)
    move(delta)
  end
  f.slider, f.valueText = s, value
  f.Refresh = sync
  -- The label row and the track both explain the slider.
  if opts.tooltip then
    f:EnableMouse(true)
    attachTooltip(f, opts.tooltip, opts.tooltipText)
    attachTooltip(s, opts.tooltip, opts.tooltipText)
  end
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
  rim:SetColorTexture(Theme.fillColor("lineStrong"))
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
  trackActive(s)
  if not gate then
    s:HookScript("OnMouseDown", function()
      s.fgHeld = true
    end)
    s:HookScript("OnMouseUp", function()
      s.fgHeld = false
    end)
  end
  s:SetScript("OnMouseWheel", function(_, delta)
    wheelOnSlider(s, delta, move)
  end)
  function s.fgArrow(_, delta)
    move(delta)
  end
  -- Moves the range (the client may hold a value outside the planned one); the value is not touched.
  function s.SetRange(self, lo, hi)
    opts.min, opts.max = lo, hi
    syncing = true
    self:SetMinMaxValues(lo, hi)
    syncing = false
  end
  function s.Sync(self, v)
    -- The thumb is compared too: the engine may have moved it while fgValue stayed.
    if (self.fgValue ~= v or self:GetValue() ~= v) and not self.fgHeld then
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

-- opts: tabs = { { id, key } }, onSelect(id), wrap (the buttons break into rows: the owner calls
-- f:fgGridLayout(width), which places them and answers the height; without wrap the bar is one row
-- of 28 px and wider than a narrow page).
function W.Tabs(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(28)
  f.buttons = {}
  -- Segment look shared with W.Action "tab" and the choice buttons: dark face and accentDim edge at rest, a
  -- lighter face on hover or focus, the chosen one gold edge + gold tint + bright text (never color alone).
  function f:fgPaintTab(b)
    local on = b.fgTabId == f.selected
    local lit = b.fgOver or b.fgFocused
    b.hl:SetColorTexture(Theme.color(lit and "surface3" or "surface2"))
    b.tint:SetShown(on)
    b.border.set(on and "accent2" or lit and "accent2" or "accentDim", on and 1 or lit and 0.7 or 0.7)
    W.SetColor(b.label, on and "accent" or (lit and "text" or "textSecondary"))
  end
  local prev
  for _, tab in ipairs(opts.tabs) do
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(28)
    b.fgTabId = tab.id
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.label = W.Text(b, { key = tab.key, role = "ui", color = "textSecondary", justify = "CENTER" })
    b.label:SetPoint("CENTER")
    b.tint = b:CreateTexture(nil, "BORDER")
    b.tint:SetAllPoints()
    b.border = W.Border(b, "accentDim", 0.7)
    ns.Bind(b, function()
      b:SetWidth(b.label:GetStringWidth() + 32)
      b.tint:SetColorTexture(Theme.color("accent2", 0.22))
      f:fgPaintTab(b)
    end)
    b:HookScript("OnEnter", function()
      b.fgOver = true
      f:fgPaintTab(b)
    end)
    b:HookScript("OnLeave", function()
      b.fgOver = false
      f:fgPaintTab(b)
    end)
    b.fgOnFocus = function()
      b.fgFocused = true
      f:fgPaintTab(b)
    end
    b.fgOnBlur = function()
      b.fgFocused = false
      f:fgPaintTab(b)
    end
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
  if opts.wrap then
    f.order = {}
    for _, tab in ipairs(opts.tabs) do
      f.order[#f.order + 1] = f.buttons[tab.id]
    end
    function f:fgGridLayout(width)
      local x, row = 0, 0
      for _, b in ipairs(self.order) do
        local w = math.min(width, math.ceil(b.label:GetStringWidth()) + 32)
        if x > 0 and x + w > width then
          x, row = 0, row + 1
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -row * 28)
        b:SetWidth(w)
        x = x + w + 4
      end
      local h = (row + 1) * 28
      self:SetHeight(h)
      return h
    end
  end
  -- Marks a tab without calling onSelect (the owner follows a state it holds itself).
  function f:SetSelected(id)
    f.selected = id
    for _, b in pairs(f.buttons) do
      f:fgPaintTab(b)
    end
  end
  function f:Select(id)
    f:SetSelected(id)
    if opts.onSelect then
      opts.onSelect(id)
    end
  end
  return f
end

-- Edit box ----------------------------------------------------------------

-- opts: placeholder (locale key), onEnter(text), onChange(text), clear (bool), inset (text margin, 8),
-- maxLetters (set before the first text goes in), tooltip + tooltipText (locale keys, shown over the field).
-- Stored value (the one place every settings text field goes through): get() returns the saved text, set(text)
-- stores what was typed. The box shows get() when it is created, whenever it is shown again and on every
-- f:Refresh(); Enter or leaving the box stores once and shows get() again (so a refused text puts the saved
-- one back), Escape drops the typed text. live: set runs on every change instead (a step that shows the effect
-- while typing); Enter and leaving then only show the cleaned stored value. With get the box owns the text: no caller writes it with SetText.
function W.EditBox(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(opts.height or 26)
  describe(f, "text", opts.placeholder)
  local fill = W.Fill(f, "bg", 0.9)
  local border = W.Border(f, "white", 0.25)
  -- Forever: the search box art of the game. The edge stays as the focus ring while the box has the focus.
  local focused = false
  ns.Bind(f, function()
    local art = ns.Skins.Apply(f, "search")
    fill:SetShown(art == nil)
    border.show(art == nil or focused)
  end)
  local eb = CreateFrame("EditBox", nil, f)
  local inset = opts.inset or 8
  eb:SetPoint("TOPLEFT", inset, 0)
  eb:SetPoint("BOTTOMRIGHT", opts.clear and -24 or -inset, 0)
  eb:SetAutoFocus(false)
  if opts.maxLetters then
    eb:SetMaxLetters(opts.maxLetters)
  end
  ns.Bind(eb, function()
    Theme.applyFont(eb, "ui", "body")
    eb:SetTextColor(Theme.color("text"))
  end)
  local ph = W.Text(f, { key = opts.placeholder, role = "ui", color = "textMuted", justify = "LEFT" })
  -- Both edges: a placeholder longer than the field ends in "..." inside it instead of running over the edge.
  ph:SetPoint("LEFT", inset, 0)
  ph:SetPoint("RIGHT", opts.clear and -24 or -inset, 0)
  ph:SetWordWrap(false)
  ph.fgEllipsis = true
  local clearBtn, bound, send, store
  if opts.clear then
    clearBtn = W.Action(f, { icon = "close", size = 18, tooltip = "common.clear" })
    clearBtn:SetPoint("RIGHT", -4, 0)
    clearBtn:SetScript("OnClick", function()
      local had = eb:GetText() ~= ""
      -- SetText reports userInput=false, so the clear is passed on here (once) instead of in OnTextChanged.
      eb:SetText("")
      if bound then
        if opts.live then
          send()
        else
          store()
        end
      end
      if had and opts.onChange then
        ns.Safe("editbox-change", opts.onChange, "")
      end
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
  bound = type(opts.get) == "function"
  -- shown: the text the box was given last; a different text at the end of an edit is what gets stored.
  local shown, sent, discard, storing = "", "", false, false
  -- The saved text goes into the box and the view starts at its beginning: a text set while the box has no
  -- width yet (before the first layout) would otherwise stay scrolled to its end and look empty. A box that
  -- is being typed in keeps its text unless force is set.
  local function show(force)
    if not bound or (eb:HasFocus() and not force) then
      return
    end
    local ok, value = ns.Safe("editbox-get", opts.get)
    shown = ok and value ~= nil and tostring(value) or ""
    sent = shown
    eb:SetText(shown)
    if eb.SetCursorPosition then
      eb:SetCursorPosition(0)
    end
  end
  -- A live box sends each text once: what Enter or leaving finds already sent is not written again.
  function send()
    local text = eb:GetText()
    if opts.live and text == sent then
      return
    end
    sent = text
    ns.Safe("editbox-set", opts.set, text)
  end
  function store()
    if not bound or storing then
      return
    end
    storing = true
    send()
    show(true)
    storing = false
  end
  eb:SetScript(
    "OnTextChanged",
    ns.Wrap("editbox", function(_, user)
      update()
      if user and bound and opts.live then
        send()
      end
      if user and opts.onChange then
        opts.onChange(eb:GetText())
      end
    end)
  )
  eb:SetScript("OnEditFocusGained", function()
    focused = true
    border.set("actionHi", 1)
    border.show(true)
    update()
  end)
  eb:SetScript("OnEditFocusLost", function()
    focused = false
    border.set("white", 0.25)
    border.show(ns.Skins.Apply(f, "search") == nil)
    if discard then
      discard = false
      show(true)
    elseif bound and eb:GetText() ~= shown then
      store()
    end
    update()
  end)
  eb:SetScript("OnEscapePressed", function()
    discard = true
    eb:ClearFocus()
    if discard then
      discard = false
      show(true)
    end
  end)
  eb:SetScript(
    "OnEnterPressed",
    ns.Wrap("editbox-enter", function()
      store()
      if opts.onEnter then
        opts.onEnter(eb:GetText())
      end
      eb:ClearFocus()
    end)
  )
  if bound then
    eb:SetScript("OnShow", function()
      show()
    end)
    eb:SetScript("OnHide", function()
      if eb:GetText() ~= shown then
        store()
      end
    end)
    eb:SetScript("OnSizeChanged", function()
      if not eb:HasFocus() and eb.SetCursorPosition then
        eb:SetCursorPosition(0)
      end
    end)
  end
  Focus.register(f, function()
    eb:SetFocus()
  end)
  attachTooltip(eb, opts.tooltip, opts.tooltipText)
  f.edit = eb
  f.clearButton = clearBtn
  if bound then
    f.Refresh = function()
      show()
    end
    -- Puts the saved text back whatever the box holds (the owner changed it from outside).
    f.Revert = function()
      show(true)
    end
  end
  show()
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

function ns.Popups.isOpen()
  return popup ~= nil and popup:IsShown()
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
  -- Solid on purpose: the list lies over page text and must never follow a window opacity.
  W.Fill(popup, "surface", 1)
  W.Border(popup, "accentDim", 1)
  popup.rows = {}
  popup:Hide()
  return popup
end

-- Distance from the top of a dropdown to its field: the label line plus a clear gap.
W.DROPDOWN_FIELD_Y = 20

-- opts: key (label), options = { { value, key|text, quality, tooltip|tooltipKey } }, get(), set(v), width, tooltip
-- and tooltipText (locale keys). An option with a quality shows its text in the item color of that quality,
-- one with an icon (texture markup) shows it in front of the text.
-- compact: no label line, the frame is the 24 px field only (rows of a card); f.button:SetWidth resizes it.
-- The frame has a height only: the owner gives it a width (SetWidth, or anchors on both sides) when it
-- places the dropdown itself, otherwise its width is undefined and the client may draw nothing.
-- f.button is the clickable button, f.arrow its chevron frame (a frame level change of the wrapper does not
-- move them), f:Open([anchor]) opens the list.
-- Typeahead for a list: the index of the entry whose text starts with the typed letters, searching from
-- the entry after `from` and wrapping around. The same letter typed again steps to the next entry with
-- that letter. Nil when nothing matches.
function W.TypeaheadFind(texts, typed, from)
  typed = typed:lower()
  local count = #texts
  if count == 0 or typed == "" then
    return nil
  end
  local repeated = typed == typed:sub(1, 1):rep(#typed)
  local needle = repeated and typed:sub(1, 1) or typed
  -- A growing word ("sel") keeps the current entry, a repeated letter moves on.
  local first = (from or 1) + (repeated and 1 or 0)
  for step = 0, count - 1 do
    local index = (first - 1 + step) % count + 1
    local text = (texts[index] or ""):gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
    if text:sub(1, #needle) == needle then
      return index
    end
  end
  return nil
end

local typeaheadText, typeaheadAt = "", 0

-- Accumulates the letters of one typing burst (a second without a key starts a new word).
function W.TypeaheadAdd(char, now)
  if now - typeaheadAt > 1 then
    typeaheadText = ""
  end
  typeaheadAt = now
  typeaheadText = typeaheadText .. char
  return typeaheadText
end

function W.Dropdown(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(opts.compact and 24 or Theme.size.control)
  describe(f, "choice", opts.key, opts.tooltipText)
  local label = W.Text(f, { key = opts.key, role = "ui", color = "textMuted" })
  label:SetPoint("TOPLEFT")
  label:SetShown(not opts.compact)
  f.label = label
  local b = CreateFrame("Button", nil, f)
  b:SetHeight(24)
  b:SetPoint("TOPLEFT", 0, opts.compact and 0 or -W.DROPDOWN_FIELD_Y)
  b:SetWidth(opts.width or 220)
  -- Forever: a dark field with a gold edge; the stretched game art put the text on a bright gradient.
  local fill = b:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  b.fgBack = fill
  local rim = W.Border(b, "white", 0.25)
  local over = false
  local function paintField()
    local forever = ns.Skins.isForever()
    fill:SetColorTexture(Theme.color(forever and "bg" or "surface2"))
    if forever then
      rim.set(over and "accent2" or "accentDim", 1)
    else
      rim.set("white", 0.25)
    end
  end
  b:HookScript("OnEnter", function()
    over = true
    paintField()
  end)
  b:HookScript("OnLeave", function()
    over = false
    paintField()
  end)
  ns.Bind(b, paintField)
  local current = W.Text(b, { role = "ui", color = "text" })
  current:SetPoint("LEFT", 8, 0)
  current:SetPoint("RIGHT", -26, 0)
  local arrow = W.Glyph(b, "chevron-down", 12, "accent")
  arrow:SetPoint("RIGHT", -8, 0)
  local function optionText(o)
    local text = o.key and L[o.key] or o.text
    if o.icon then
      text = o.icon .. " " .. text
    end
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
  local function open(anchor)
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
        r.hl:SetColorTexture(ns.Theme.fillColor())
        r.text = W.Text(r, { role = "ui" })
        r.text:SetPoint("LEFT", 8, 0)
        -- An option may carry a tooltip text (o.tooltip), shown on hover and on keyboard focus.
        local function showTip()
          if r.fgTip then
            ns.ShowTooltip(r, r.fgTipTitle, r.fgTip)
          end
        end
        local function hideTip()
          if r.fgTip then
            ns.HideTooltip()
          end
        end
        r:SetScript("OnEnter", function()
          r.hl:SetColorTexture(Theme.fillColor("hover"))
          showTip()
        end)
        r:SetScript("OnLeave", function()
          r.hl:SetColorTexture(ns.Theme.fillColor())
          hideTip()
        end)
        r.fgOnFocus, r.fgOnBlur = showTip, hideTip
        Focus.register(r, function(self)
          self:Click()
        end)
        -- Letters typed in the open list jump to the matching option.
        r.fgTypeahead = function(_, char)
          local texts, at = {}, 1
          for index, option in ipairs(opts.options) do
            texts[index] = optionText(option)
            if p.rows[index] == r then
              at = index
            end
          end
          local typed = W.TypeaheadAdd(char, GetTime())
          local hit = W.TypeaheadFind(texts, typed, at)
          if hit and p.rows[hit] then
            Focus.set(p.rows[hit])
          end
          return true
        end
        p.rows[i] = r
      end
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 22)
      r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 22)
      r.text:SetText(optionText(o))
      r.fgTip, r.fgTipTitle = o.tooltipKey and L[o.tooltipKey] or o.tooltip, optionText(o)
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
    if anchor then
      p:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    else
      p:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
    end
    p:SetScale((anchor or b):GetEffectiveScale() / UIParent:GetEffectiveScale())
    blocker:Show()
    p:Show()
    TopLayer.Over(blocker, TopLayer.BLOCKER)
    TopLayer.Over(p, TopLayer.LIST)
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
  f.button, f.arrow = b, arrow
  -- Opens the option list like a click on the button. With an anchor frame the list drops from its
  -- bottom right edge instead, for another control that offers the same choice.
  function f:Open(anchor)
    open(anchor)
  end
  return f
end
