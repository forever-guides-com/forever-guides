-- Page "HUD windows" of the main window (area tools). An action bar on top (new window) and one compact card per
-- window: name, edit, duplicate, delete, visible and locked per character, the "when active" conditions folded
-- away. A window is its layout, so there is nothing to assign. Every change goes through Store or the library
-- (Modules/AreaLayouts.lua), the windows follow through FG_SETTING_CHANGED. The cards are made on demand and
-- hidden when they are not needed (a frame cannot be freed). The list places its cards from the width the
-- page stack hands it (fgGridLayout), so the layout follows the window width and the font size.
local _, ns = ...
local W, L, Store, AL, Theme, CS = ns.W, ns.L, ns.Store, ns.AreaLogic, ns.Theme, ns.CharScopeLogic
-- The controls table of the editor, taken at load (a host may replace ns.CanvasEditor later).
local Controls = ns.CanvasEditor.Controls

local S = {}
ns.AreaSettings = S

ns.AddLocale(
  "enUS",
  ns.AreaTerms.Apply("enUS", {
    ["page.areas"] = "{tracker}",
    ["areas.set.hint"] = "{windows} are windows of your own on the screen, filled in the layout editor with cooldowns, auras and more. Every window has a layout of its own. /fg {cmd} lists the commands.",
    ["areas.set.new"] = "New window",
    ["areas.set.newTip"] = "Creates a {window} with an empty layout of its own. You can rename it at once.",
    ["areas.set.newChars"] = "New characters: show {windows}",
    ["areas.set.newCharsShow"] = "Show",
    ["areas.set.newCharsTip"] = "Whether a {window} shows on a character that has no entry for it yet. A character that already knows the window keeps its choice.",
    ["areas.set.shown"] = "Show window",
    ["areas.set.shownTip"] = "Shows or hides the window on this character. The window itself and its layout belong to the account.",
    ["areas.set.locked"] = "Lock position",
    ["areas.set.lockedTip"] = "Fixes the position of the window on this character and hides its scale grip. The mouse and the camera pass through it, hold {mod:windowGear} to show the gear. A pinned window is unlocked in the layout editor or in the gear menu of the window.",
    ["areas.page.empty"] = "No {window} yet. A {window} shows cooldowns, auras and more anywhere on the screen. New window creates one with an empty layout, you fill it in the editor.",
    ["areas.page.visible"] = "Visible",
    ["areas.page.locked"] = "Locked",
    ["areas.page.edit"] = "Edit window",
    ["areas.page.editTip"] = "Opens the editor for this window. There you can also switch to another window, save under a name and import layouts.",
    ["areas.page.duplicate"] = "Duplicate window",
    ["areas.page.duplicateTip"] = "Creates a copy of this window with a copy of its layout.",
    ["areas.page.delete"] = "Delete window",
    ["areas.page.deleteTip"] = "Deletes the window and its layout after asking.",
    ["areas.page.rules"] = "When active",
    ["areas.page.rulesTip"] = "Conditions under which this window is there: combat, instance, group, mount, vehicle, target, class, specialization, character.",
  })
)
ns.AddLocale(
  "deDE",
  ns.AreaTerms.Apply("deDE", {
    ["page.areas"] = "{tracker}",
    ["areas.set.hint"] = "{windows} sind eigene Fenster auf dem Bildschirm, im Layout-Editor mit Abklingzeiten, Auren und mehr gefüllt. Jedes Fenster hat ein eigenes Layout. /fg {cmd} zeigt die Befehle.",
    ["areas.set.new"] = "Neues Fenster",
    ["areas.set.newTip"] = "Legt ein {window} mit einem eigenen, leeren Layout an. Du kannst es gleich umbenennen.",
    ["areas.set.newChars"] = "Neue Charaktere: {windows} anzeigen",
    ["areas.set.newCharsShow"] = "Anzeigen",
    ["areas.set.newCharsTip"] = "Ob ein {window} auf einem Charakter erscheint, der noch keinen Eintrag dafür hat. Ein Charakter, der das Fenster schon kennt, behält seine Wahl.",
    ["areas.set.shown"] = "Fenster anzeigen",
    ["areas.set.shownTip"] = "Zeigt oder versteckt das Fenster auf diesem Charakter. Das Fenster selbst und sein Layout gehören zum Account.",
    ["areas.set.locked"] = "Position sperren",
    ["areas.set.lockedTip"] = "Fixiert die Position des Fensters auf diesem Charakter und blendet den Skalierungsgriff aus. Maus und Kamera gehen durch das Fenster, mit {mod:windowGear} erscheint das Zahnrad. Ein angepinntes Fenster wird im Layout-Editor oder im Zahnrad-Menü des Fensters entsperrt.",
    ["areas.page.empty"] = "Noch kein {window}. Ein {window} zeigt Abklingzeiten, Auren und mehr irgendwo auf dem Bildschirm. Neues Fenster legt eines mit leerem Layout an, du füllst es im Editor.",
    ["areas.page.visible"] = "Sichtbar",
    ["areas.page.locked"] = "Gesperrt",
    ["areas.page.edit"] = "Fenster bearbeiten",
    ["areas.page.editTip"] = "Öffnet den Editor für dieses Fenster. Dort wechselst du auch zu einem anderen Fenster, speicherst unter einem Namen und importierst Layouts.",
    ["areas.page.duplicate"] = "Fenster duplizieren",
    ["areas.page.duplicateTip"] = "Legt eine Kopie dieses Fensters mit einer Kopie seines Layouts an.",
    ["areas.page.delete"] = "Fenster löschen",
    ["areas.page.deleteTip"] = "Löscht das Fenster und sein Layout nach einer Rückfrage.",
    ["areas.page.rules"] = "Wann aktiv",
    ["areas.page.rulesTip"] = "Bedingungen, unter denen dieses Fenster da ist: Kampf, Instanz, Gruppe, Reittier, Fahrzeug, Ziel, Klasse, Spezialisierung, Charakter.",
  })
)

-- Sizes in px at font factor 1: padding in a card, gap between controls, icon buttons, the rows of controls.
local PAD, GAP, ICON, CARD_GAP = 10, 6, 24, 8
local NAME_H, CHECK_H, TOGGLE_H, BAR_H = 26, 22, 24, 28
-- A page that reports no usable width yet must not squeeze the cards below what their controls need.
local MIN_CARD_W = 2 * PAD + 160

-- The views that were built (weak): a change anywhere repaints every one of them.
S.views = setmetatable({}, { __mode = "k" })

-- Session state of the page: the windows whose rules are open.
local open = {}

local function items()
  local node = ns.db and ns.db.settings and ns.db.settings.areas
  return node and node.items or {}
end

local function scaled(base)
  return Theme.lineHeight(base)
end

local function refreshAll()
  for view in pairs(S.views) do
    view.refresh()
  end
end

-- A name field that renames in place: Enter and leaving the field both store it, an empty or refused name puts
-- the old one back. commit(id, text) returns true when it stored the name.
local function nameBox(parent, max, owner, commit)
  local box = W.EditBox(parent, {
    onEnter = function(text)
      owner.commit(text)
    end,
  })
  box.edit:SetMaxLetters(max)
  box.edit:HookScript("OnEditFocusLost", function()
    owner.commit(box.edit:GetText())
  end)
  function owner.commit(text)
    if not owner.id then
      return
    end
    if not commit(owner.id, text) then
      box.edit:SetText(owner.shownName or "")
    end
  end
  return box
end

local function iconButton(row, icon, tip, tipText, onClick)
  return W.Action(row, {
    icon = icon,
    size = ICON,
    tooltip = tip,
    tooltipText = tipText,
    onClick = onClick,
  })
end

-- Places icon buttons from the right edge of a card, the first one rightmost; y is the offset from the top.
local function placeIcons(row, buttons, y)
  for i, button in ipairs(buttons) do
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(PAD + (i - 1) * (ICON + GAP)), -(y + 1))
  end
  return #buttons * ICON + (#buttons - 1) * GAP
end

-- Window cards ----------------------------------------------------------------------------------------------

local function checkWidth(box)
  return math.ceil(box.label:GetStringWidth()) + 16 + 8 + 4
end

local function buildWindowCard(list)
  local row = W.Card(list, {})
  -- The name of the window is the name of its layout: renaming changes both.
  row.name = nameBox(row, AL.MAX_NAME, row, function(id, text)
    local ok, reason = ns.Areas.Rename(id, text)
    if not ok and reason ~= "name" then
      ns.Areas.Explain(reason)
    end
    return ok == true
  end)
  row.edit = iconButton(row, "pencil", "areas.page.edit", "areas.page.editTip", function()
    if row.id then
      ns.Areas.Edit(row.id)
    end
  end)
  row.duplicate = iconButton(row, "copy", "areas.page.duplicate", "areas.page.duplicateTip", function()
    if row.id then
      S.duplicate(row.id)
    end
  end)
  row.delete = iconButton(row, "trash", "areas.page.delete", "areas.page.deleteTip", function()
    if row.id then
      ns.Areas.ConfirmDelete(row.id)
    end
  end)
  row.shown = W.Checkbox(row, {
    key = "areas.page.visible",
    tooltip = "areas.set.shown",
    tooltipText = "areas.set.shownTip",
    get = function()
      return row.id ~= nil and ns.Areas.Placement(row.id).shown
    end,
    set = function(on)
      if row.id then
        ns.Areas.SetShown(row.id, on)
      end
    end,
  })
  row.locked = W.Checkbox(row, {
    key = "areas.page.locked",
    tooltip = "areas.set.locked",
    tooltipText = "areas.set.lockedTip",
    get = function()
      return row.id ~= nil and ns.Areas.Placement(row.id).locked
    end,
    set = function(on)
      if not row.id then
        return
      end
      if on then
        ns.Areas.SetLocked(row.id, true)
      else
        -- Refused here on purpose: the tick goes back and a line names the two ways that unlock.
        ns.Notify.send(L["areas.unlock.editor"], "warning")
        row.locked.Refresh()
      end
    end,
  })
  row.rulesToggle = W.Action(row, {
    key = "areas.page.rules",
    icon = "chevron-right",
    variant = "ghost",
    height = TOGGLE_H,
    tooltip = "areas.page.rules",
    tooltipText = "areas.page.rulesTip",
    onClick = function()
      if row.id then
        open[row.id] = not open[row.id] or nil
        refreshAll()
      end
    end,
  })
  row.load = Controls.LoadPanel(row, {
    get = function()
      return row.id ~= nil and AL.Load(items()[row.id]) or nil
    end,
    set = function(load)
      if row.id then
        Store.set(AL.ItemPath(row.id) .. ".load", load)
      end
    end,
    onResize = refreshAll,
  })
  return row
end

-- Fills the controls of a window card with the data of `entry`.
local function bindWindowCard(row, entry)
  row.id = entry.id
  row.shownName = entry.name
  if not row.name.edit:HasFocus() then
    row.name.edit:SetText(entry.name)
  end
  row.shown.Refresh()
  row.locked.Refresh()
  row.load:Refresh()
  row.rulesToggle:SetIcon(open[entry.id] and "chevron-down" or "chevron-right")
end

-- Places the controls for a card `width` wide and returns its height.
local function layoutWindowCard(row, width)
  local inner = width - 2 * PAD
  local y = PAD
  local rowH = scaled(NAME_H)
  local icons = placeIcons(row, { row.delete, row.duplicate, row.edit }, y + math.floor((rowH - ICON) / 2))
  row.name:ClearAllPoints()
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -y)
  row.name:SetSize(inner - icons - GAP, rowH)
  y = y + rowH + GAP
  -- Row 2: the two ticks and the fold button, wrapped when the width runs out.
  local checkH = scaled(CHECK_H)
  local parts = {
    { row.shown, checkWidth(row.shown), checkH },
    { row.locked, checkWidth(row.locked), checkH },
    { row.rulesToggle, math.min(row.rulesToggle:FullWidth(), inner), scaled(TOGGLE_H) },
  }
  local x, lineH = 0, 0
  for _, part in ipairs(parts) do
    local frame, w, h = part[1], math.min(part[2], inner), part[3]
    if x > 0 and x + w > inner then
      y = y + lineH + GAP
      x, lineH = 0, 0
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", row, "TOPLEFT", PAD + x, -y)
    frame:SetSize(w, h)
    x = x + w + 14
    lineH = math.max(lineH, h)
  end
  y = y + lineH
  -- The conditions under it.
  local expanded = open[row.id] == true
  row.load:SetShown(expanded)
  if expanded then
    y = y + GAP
    row.load:ClearAllPoints()
    row.load:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -y)
    y = y + row.load:fgGridLayout(inner)
  end
  return y + PAD
end

-- Lists ----------------------------------------------------------------------------------------------------------

-- A frame that holds the cards of one list, built on demand and stacked by the page stack, which hands it the
-- width in fgGridLayout. `build(list)` makes a card, `layout(card, width)` places its controls and returns the
-- height.
local function cardList(view, build, layout)
  local list = CreateFrame("Frame", nil, view.content)
  local self = { frame = list, rows = {}, count = 0 }
  function self.row(i)
    if not self.rows[i] then
      self.rows[i] = build(list)
    end
    return self.rows[i]
  end
  function self.hideFrom(i)
    self.count = i - 1
    for n = i, #self.rows do
      self.rows[n].id = nil
      self.rows[n]:Hide()
    end
  end
  function list.fgGridLayout(_, width)
    width = math.max(width, MIN_CARD_W)
    local y = 0
    for i = 1, self.count do
      local row = self.rows[i]
      local h = layout(row, width)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
      row:SetSize(width, h)
      row:Show()
      y = y + h + CARD_GAP
    end
    y = math.max(y - CARD_GAP, 1)
    list:SetHeight(y)
    return y
  end
  return self
end

-- The action bar: new window.
local function actionBar(view, onNewWindow)
  local bar = CreateFrame("Frame", nil, view.content)
  bar.window = W.Action(bar, {
    key = "areas.set.new",
    icon = "plus",
    variant = "primary",
    height = BAR_H,
    tooltip = "areas.set.new",
    tooltipText = "areas.set.newTip",
    onClick = onNewWindow,
  })
  function bar:fgGridLayout(width)
    local h = scaled(BAR_H)
    bar.window:ClearAllPoints()
    bar.window:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.window:SetSize(math.min(bar.window:FullWidth(), width), h)
    bar:SetHeight(h)
    return h
  end
  return bar
end

-- Page ------------------------------------------------------------------------------------------------------------

-- Focuses the name field of the card of window `id` after the page was repainted, so a new window can be
-- named at once.
local function focusName(view, id)
  for i = 1, view.windowList.count do
    local row = view.windowList.rows[i]
    if row.id == id then
      row.name.edit:SetFocus()
      row.name.edit:HighlightText()
      return
    end
  end
end

-- Duplicates window `id` and puts the cursor into the name of the copy.
function S.duplicate(id)
  local newId, reason = ns.Areas.Duplicate(id)
  if not newId then
    ns.Areas.Explain(reason)
    return
  end
  refreshAll()
  for view in pairs(S.views) do
    focusName(view, newId)
  end
end

function S.Add(view)
  local function newWindow()
    local id, reason = ns.Areas.Create(nil)
    if not id then
      ns.Areas.Explain(reason)
      return
    end
    refreshAll()
    focusName(view, id)
  end

  ns.AddParagraph(view, "areas.set.hint", { role = "micro", color = "textMuted" })
  -- The setting is named by a wrapped line, so the name never gets cut at a narrow page or a large font.
  ns.AddParagraph(view, "areas.set.newChars", { role = "ui", color = "text", gap = 4 })
  local newChars = W.Toggle(view.content, {
    key = "areas.set.newCharsShow",
    get = function()
      return CS.StartShown(ns.db and ns.db.settings and ns.db.settings.areas)
    end,
    set = function(on)
      Store.set("settings.areas.newCharShown", on == true)
    end,
    tooltip = "areas.set.newChars",
    tooltipText = "areas.set.newCharsTip",
  })
  -- The accessible name carries the setting, the label of the switch only says what it does.
  newChars.fgName = function()
    return L["areas.set.newChars"]
  end
  view.stack:Add(newChars, { height = 24, gap = 10 })
  view.newChars = newChars

  local bar = actionBar(view, newWindow)
  view.stack:Add(bar, { gap = 14 })
  view.bar = bar

  local empty = ns.AddParagraph(view, "areas.page.empty", { role = "small", color = "textMuted" })
  local windowList = cardList(view, buildWindowCard, layoutWindowCard)
  view.stack:Add(windowList.frame, { gap = 8 })
  view.windowList = windowList

  function view.refresh()
    newChars.Refresh()
    local areas = AL.List(items())
    for i, entry in ipairs(areas) do
      bindWindowCard(windowList.row(i), entry)
    end
    windowList.hideFrom(#areas + 1)
    empty:SetShown(#areas == 0)
    windowList.frame:SetShown(#areas > 0)
    view:Layout()
  end
  S.views[view] = true
  view.refresh()
end

ns.On("FG_SETTING_CHANGED", function(_, path, _, scope)
  if scope == "char" then
    if type(path) == "string" and path:find("^areas%.") then
      refreshAll()
    end
  elseif type(path) == "string" and path:find("^settings%.areas") then
    refreshAll()
  end
end)

ns.RegisterPage({
  id = "areas",
  order = 680,
  group = "tools",
  title = "page.areas",
  icon = ns.ICONS.areas,
  aliases = { "hudfenster", "hudwindow", "tracker", "bereiche", "bereich", "areas", "area", "fenster" },
  build = function(container)
    local view = ns.NewPageView(container)
    function view:Show()
      view.refresh()
    end
    S.Add(view)
    return view
  end,
})
