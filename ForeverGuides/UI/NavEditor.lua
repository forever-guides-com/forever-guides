-- Window that customizes the left navigation: a preview of the whole menu on the left (every group as its
-- box with all its entries, hidden ones marked), the settings of the selected group or entry on the right.
-- The layout data and its rules are Modules/NavLayoutLogic.lua, the list itself is UI/Sidebar.lua; every
-- change goes through NL.Apply, so the real sidebar follows at once (FG_NAV_CHANGED) and so does the preview.
--
-- The sidebar uses no protected frame, so the window works in combat as well. It sits beside the main
-- window and closes with it.
local _, ns = ...
local W, Theme, L, NL = ns.W, ns.Theme, ns.L, ns.NavLayout

local NE = {}
ns.NavEditor = NE

ns.AddLocale("enUS", {
  ["nav.edit.toggle"] = "Customize menu",
  ["nav.edit.toggleHint"] = "Opens a window to reorder, recolor, rename and hide menu entries. Entries that are hidden can be shown again there.",
  ["nav.edit.hideHint"] = "A hidden entry stays reachable through search and commands.",
  ["nav.edit.lockedPage"] = "This entry always stays in the menu.",
  ["nav.edit.lockedGroup"] = "This group holds an entry that always stays in the menu.",
  ["nav.edit.rename"] = "Rename",
  ["nav.edit.scope"] = "Only this character",
  ["nav.edit.scopeHint"] = "Off: your changes apply to all characters. On: you change only this character. Everything it does not change keeps following the account menu.",
  ["nav.edit.resetAccount"] = "Reset account menu",
  ["nav.edit.resetChar"] = "Remove own changes for %s",
  ["nav.reset.title"] = "Reset navigation",
  ["nav.reset.textAccount"] = "All entries and groups return to their default place, name and visibility for all characters.",
  ["nav.reset.textChar"] = "%s stops using own changes and follows the account menu again.",
  ["nav.editor.title"] = "Customize menu",
  ["nav.editor.hint"] = "Click a group or entry to change it. Changes apply at once. Shift+Up and Shift+Down move the selection.",
  ["nav.editor.scopeAll"] = "All characters",
  ["nav.editor.scopeChar"] = "Only %s",
  ["nav.editor.statusAccount"] = "You are editing the menu for all characters.",
  ["nav.editor.statusOwnOne"] = "%s has 1 own change.",
  ["nav.editor.statusOwnMany"] = "%s has %d own changes.",
  ["nav.editor.statusChar"] = "You are editing only %s. Everything without an own change comes from the account menu.",
  ["nav.editor.markChar"] = "Own setting for %s",
  ["nav.editor.markAccount"] = "Overridden for %s",
  ["nav.editor.fromAccount"] = "From the account",
  ["nav.editor.useAccount"] = "Use account setting",
  ["nav.editor.useAccountHint"] = "Removes the own setting. It follows the account menu again.",
  ["nav.layer.account"] = "Account menu",
  ["nav.layer.ownOne"] = "Account menu + 1 own change for %s",
  ["nav.layer.ownMany"] = "Account menu + %d own changes for %s",
  ["nav.editor.group"] = "Group",
  ["nav.editor.page"] = "Entry",
  ["nav.editor.name"] = "Name",
  ["nav.editor.resetName"] = "Restore default name",
  ["nav.editor.renameHint"] = "Leave the name empty to restore the default.",
  ["nav.editor.color"] = "Color",
  ["nav.editor.colorCustom"] = "Custom color",
  ["nav.editor.colorNone"] = "No color",
  ["nav.editor.visible"] = "Visible",
  ["nav.editor.hidden"] = "Hidden in the menu",
  ["nav.editor.up"] = "Move up",
  ["nav.editor.down"] = "Move down",
  ["nav.editor.moveTo"] = "Move to group",
  ["nav.editor.tone.1"] = "Blue",
  ["nav.editor.tone.2"] = "Teal",
  ["nav.editor.tone.3"] = "Green",
  ["nav.editor.tone.4"] = "Ochre",
  ["nav.editor.tone.5"] = "Copper",
  ["nav.editor.tone.6"] = "Red",
  ["nav.editor.tone.7"] = "Purple",
  ["nav.editor.tone.8"] = "Slate",
})
ns.AddLocale("deDE", {
  ["nav.edit.toggle"] = "Menü anpassen",
  ["nav.edit.toggleHint"] = "Öffnet ein Fenster, um Menüeinträge zu ordnen, einzufärben, umzubenennen und auszublenden. Ausgeblendete Bereiche lassen sich dort wieder einblenden.",
  ["nav.edit.hideHint"] = "Ein ausgeblendeter Eintrag bleibt über Suche und Befehle erreichbar.",
  ["nav.edit.lockedPage"] = "Dieser Eintrag bleibt immer im Menü.",
  ["nav.edit.lockedGroup"] = "Diese Gruppe enthält einen Eintrag, der immer im Menü bleibt.",
  ["nav.edit.rename"] = "Umbenennen",
  ["nav.edit.scope"] = "Nur dieser Charakter",
  ["nav.edit.scopeHint"] = "Aus: Deine Änderungen gelten für alle Charaktere. An: Du änderst nur diesen Charakter. Alles, was er nicht ändert, folgt weiter dem Konto-Menü.",
  ["nav.edit.resetAccount"] = "Konto-Menü zurücksetzen",
  ["nav.edit.resetChar"] = "Eigene Änderungen für %s entfernen",
  ["nav.reset.title"] = "Navigation zurücksetzen",
  ["nav.reset.textAccount"] = "Alle Einträge und Gruppen kehren für alle Charaktere zu Standardplatz, Standardname und Standardsichtbarkeit zurück.",
  ["nav.reset.textChar"] = "%s nutzt keine eigenen Änderungen mehr und folgt wieder dem Konto-Menü.",
  ["nav.editor.title"] = "Menü anpassen",
  ["nav.editor.hint"] = "Klicke eine Gruppe oder einen Eintrag an, um sie zu ändern. Änderungen gelten sofort. Umschalt+Hoch und Umschalt+Runter verschieben die Auswahl.",
  ["nav.editor.scopeAll"] = "Alle Charaktere",
  ["nav.editor.scopeChar"] = "Nur %s",
  ["nav.editor.statusAccount"] = "Du bearbeitest das Menü für alle Charaktere.",
  ["nav.editor.statusOwnOne"] = "%s hat 1 eigene Änderung.",
  ["nav.editor.statusOwnMany"] = "%s hat %d eigene Änderungen.",
  ["nav.editor.statusChar"] = "Du bearbeitest nur %s. Alles ohne eigene Änderung kommt vom Konto-Menü.",
  ["nav.editor.markChar"] = "Eigene Einstellung für %s",
  ["nav.editor.markAccount"] = "Für %s überschrieben",
  ["nav.editor.fromAccount"] = "Vom Konto",
  ["nav.editor.useAccount"] = "Vom Konto übernehmen",
  ["nav.editor.useAccountHint"] = "Entfernt die eigene Einstellung. Sie folgt wieder dem Konto-Menü.",
  ["nav.layer.account"] = "Konto-Menü",
  ["nav.layer.ownOne"] = "Konto-Menü + 1 eigene Änderung für %s",
  ["nav.layer.ownMany"] = "Konto-Menü + %d eigene Änderungen für %s",
  ["nav.editor.group"] = "Gruppe",
  ["nav.editor.page"] = "Eintrag",
  ["nav.editor.name"] = "Name",
  ["nav.editor.resetName"] = "Standardnamen wiederherstellen",
  ["nav.editor.renameHint"] = "Ein leerer Name stellt den Standard wieder her.",
  ["nav.editor.color"] = "Farbe",
  ["nav.editor.colorCustom"] = "Eigene Farbe",
  ["nav.editor.colorNone"] = "Keine Farbe",
  ["nav.editor.visible"] = "Sichtbar",
  ["nav.editor.hidden"] = "Im Menü ausgeblendet",
  ["nav.editor.up"] = "Nach oben",
  ["nav.editor.down"] = "Nach unten",
  ["nav.editor.moveTo"] = "In Bereich verschieben",
  ["nav.editor.tone.1"] = "Blau",
  ["nav.editor.tone.2"] = "Petrol",
  ["nav.editor.tone.3"] = "Grün",
  ["nav.editor.tone.4"] = "Ocker",
  ["nav.editor.tone.5"] = "Kupfer",
  ["nav.editor.tone.6"] = "Rot",
  ["nav.editor.tone.7"] = "Violett",
  ["nav.editor.tone.8"] = "Schiefer",
})

local WIDTH, HEIGHT, PAD = 640, 580, 16
local LIST_W, COLUMN_GAP = 270, 16
local CONFIG_W = WIDTH - 2 * PAD - LIST_W - COLUMN_GAP
local ROW_H, BOX_PAD, BOX_GAP = 24, 3, 6
local TOP_Y = 48
-- Dark tones: the sidebar box fill (Sidebar.BoxFill) keeps the menu text readable on each of them.
local PALETTE = { "#2d4a6b", "#2f5d50", "#3f6b34", "#6b5b2a", "#7a4a2a", "#7a3a3a", "#5a3a6e", "#4a4f58" }

local scope -- "account" or "char"; nil until chosen, then it follows whether this character has a layout
local sel = { kind = "group", id = nil }
local d -- the window, built on first use

-- Which layer an edit writes to: "account" (all characters) or "char" (this character only).
function NE.Scope()
  return scope or (NL.HasCharLayout() and "char" or "account")
end

function NE.SetScope(value)
  scope = value == "char" and "char" or "account"
  ns.Emit("FG_NAV_SCOPE", scope)
end

local function charName()
  return UnitName("player") or "?"
end

-- Texts that name the character and the layer in use (the window, the pencil tooltips and the tests read them).
function NE.StatusText(layer)
  layer = layer or NE.Scope()
  local name = charName()
  if layer == "char" then
    return string.format(L["nav.editor.statusChar"], name)
  end
  local n = NL.OverrideCount()
  if n == 0 then
    return L["nav.editor.statusAccount"]
  end
  local own = n == 1 and string.format(L["nav.editor.statusOwnOne"], name) or string.format(L["nav.editor.statusOwnMany"], name, n)
  return L["nav.editor.statusAccount"] .. " " .. own
end

-- "Account menu" or "Account menu + 3 own changes for <character>".
function NE.LayerText()
  local n = NL.OverrideCount()
  if n == 0 then
    return L["nav.layer.account"]
  end
  return n == 1 and string.format(L["nav.layer.ownOne"], charName()) or string.format(L["nav.layer.ownMany"], n, charName())
end

function NE.ScopeCharText()
  return string.format(L["nav.editor.scopeChar"], charName())
end

function NE.ResetText(layer)
  return layer == "char" and string.format(L["nav.edit.resetChar"], charName()) or L["nav.edit.resetAccount"]
end

function NE.RequestReset(layer)
  layer = layer or NE.Scope()
  local opts = layer == "char" and { text = string.format(L["nav.reset.textChar"], charName()) } or nil
  ns.Dialogs.Confirm("nav.reset.title", layer ~= "char" and "nav.reset.textAccount" or nil, function()
    NL.ResetLayer(layer)
  end, nil, opts)
end

-- Tooltip of a pencil: the title, an optional hint, and the layer in use as the last line. Hooked after the
-- button's own tooltip, so it replaces it.
function NE.PencilTip(button, titleKey, hintKey)
  button:HookScript("OnEnter", function(self)
    local lines = {}
    if hintKey then
      lines[1] = L[hintKey]
    end
    lines[#lines + 1] = NE.LayerText()
    ns.ShowTooltip(self, L[titleKey], table.concat(lines, "\n"), { hint = L["action.opensWindow"] })
  end)
end

-- The menu as the edited layer lists it: every group and entry, hidden ones included.
local function currentView()
  local base = NL.Base()
  return NL.Resolve(base.groups, base.pages, NL.EditLayout(NE.Scope()), true)
end

local function defaultName(kind, id, entry)
  if kind == "group" then
    return L["nav.group." .. id]
  end
  return L[ns.Sidebar.NavKey(entry.page)]
end

local function shownName(kind, id, entry)
  return entry.name or defaultName(kind, id, entry)
end

-- The selected entry, its group entry and its place, nil when the layout no longer has it.
local function find(view, kind, id)
  for gi, g in ipairs(view.groups) do
    if kind == "group" and g.id == id then
      return g, g, gi
    end
    if kind == "page" then
      for pi, p in ipairs(g.pages) do
        if p.id == id then
          return p, g, gi, pi
        end
      end
    end
  end
end

-- Whether a step of delta (-1 or 1) would change anything.
local function canStep(kind, id, delta)
  local _, ok = NL.Step(NL.EditLayout(NE.Scope()), NL.Base(), kind, id, delta)
  return ok == true
end

local function apply(op, ...)
  return NL.Apply(NE.Scope(), op, ...)
end

-- Preview ------------------------------------------------------------------------------------------

local rows, boxes = {}, {}

local function paintRow(r)
  local selected = sel.kind == r.kind and sel.id == r.id
  r.bar:SetShown(selected)
  r.bg:SetColorTexture(Theme.fillColor(selected and "selected" or r.hover and "hover" or nil))
  local token = selected and "accent" or (r.kind == "group" or r.hidden) and "textMuted" or "textSecondary"
  W.SetColor(r.label, token)
  if r.icon then
    r.icon:SetAlpha(r.hidden and 0.6 or 1)
  end
end

function NE.Select(kind, id)
  sel.kind, sel.id = kind, id
  NE.Refresh()
end

local function newRow(kind, id, page)
  local r = CreateFrame("Button", nil, d.list.content)
  r.kind, r.id = kind, id
  r:SetHeight(ROW_H)
  r.bg = r:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bar = r:CreateTexture(nil, "ARTWORK")
  r.bar:SetPoint("TOPLEFT")
  r.bar:SetPoint("BOTTOMLEFT")
  r.bar:SetWidth(3)
  ns.Bind(r.bar, function(t)
    t:SetColorTexture(Theme.color("accent2"))
  end)
  if page then
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", 12, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.icon:SetTexture(ns.ResolveIcon(page.icon, ns.ICONS_FALLBACK[page.id]))
  end
  -- A hidden entry keeps its text color (contrast) and wears this marker.
  r.eye = W.Glyph(r, "eye-off", 12, "textMuted")
  r.eye:SetPoint("RIGHT", -8, 0)
  -- An own setting of this character: a pin (accent in the character scope, muted in the account scope).
  r.mark = W.Glyph(r, "pin", 12, "accent")
  r.mark:SetPoint("RIGHT", r.eye, "LEFT", -4, 0)
  r.label = W.Text(r, { role = page and "ui" or "micro", color = "textSecondary" })
  r.label:SetPoint("LEFT", r.icon or r, r.icon and "RIGHT" or "LEFT", r.icon and 8 or 10, 0)
  r.label:SetPoint("RIGHT", r.mark, "LEFT", -4, 0)
  ns.Bind(r, paintRow)
  r:SetScript(
    "OnClick",
    ns.Wrap("naveditor-select", function(self)
      NE.Select(self.kind, self.id)
    end)
  )
  r:SetScript("OnEnter", function(self)
    self.hover = true
    paintRow(self)
    local lines = {}
    if self.hidden then
      lines[#lines + 1] = L["nav.editor.hidden"]
    end
    if self.markText then
      lines[#lines + 1] = self.markText
    end
    ns.ShowTooltip(self, self.label:GetText(), #lines > 0 and table.concat(lines, "\n") or nil)
  end)
  r:SetScript("OnLeave", function(self)
    self.hover = false
    paintRow(self)
    ns.HideTooltip()
  end)
  r.fgOnFocus = function(self)
    self.hover = true
    paintRow(self)
  end
  r.fgOnBlur = function(self)
    self.hover = false
    paintRow(self)
  end
  r.fgReorder = function(self, delta)
    NE.Step(self.kind, self.id, delta)
  end
  ns.Focus.register(r, function(self)
    self:Click()
  end)
  return r
end

local function rowFor(kind, id, page)
  local key = kind .. ":" .. id
  rows[key] = rows[key] or newRow(kind, id, page)
  return rows[key]
end

local function paintBox(box)
  if box.color then
    box.fill:SetColorTexture(ns.Sidebar.BoxFill(box.color))
  else
    box.fill:SetColorTexture(Theme.fillColor("rowRest"))
  end
end

local function boxFor(id)
  if not boxes[id] then
    local box = CreateFrame("Frame", nil, d.list.content)
    box:SetFrameLevel(d.list.content:GetFrameLevel())
    box.fill = box:CreateTexture(nil, "BACKGROUND")
    box.fill:SetAllPoints()
    W.Border(box, "white")
    ns.Bind(box, paintBox)
    boxes[id] = box
  end
  return boxes[id]
end

local MARK_FIELDS = { group = { "color", "name", "hidden" }, page = { "name", "hidden", "group" } }

-- The tooltip text of the character marker of one entry, nil when this character does not override it.
local function markText(kind, id)
  for _, field in ipairs(MARK_FIELDS[kind]) do
    if NL.IsOverridden(kind, id, field) then
      return string.format(L[NE.Scope() == "char" and "nav.editor.markChar" or "nav.editor.markAccount"], charName())
    end
  end
end

local function setMark(r)
  r.markText = NL.OverrideCount() > 0 and markText(r.kind, r.id) or nil
  r.mark:SetShown(r.markText ~= nil)
  r.mark:SetColorToken(NE.Scope() == "char" and "accent" or "textMuted")
end

local function refreshList(view)
  for _, r in pairs(rows) do
    r:Hide()
  end
  for _, b in pairs(boxes) do
    b:Hide()
  end
  local content = d.list.content
  local order = {}
  local y = -BOX_GAP
  for _, g in ipairs(view.groups) do
    local box = boxFor(g.id)
    box.color = g.color
    local top = y
    y = y - BOX_PAD
    local h = rowFor("group", g.id)
    h.entry, h.hidden = g, g.hidden
    W.SetText(h.label, nil, shownName("group", g.id, g))
    h.eye:SetShown(g.hidden)
    setMark(h)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", content, "TOPLEFT", BOX_PAD + 2, y)
    h:SetPoint("RIGHT", content, "RIGHT", -(BOX_PAD + 2), 0)
    h:Show()
    order[#order + 1] = h
    paintRow(h)
    y = y - ROW_H
    for _, p in ipairs(g.pages) do
      local r = rowFor("page", p.id, p.page)
      r.entry, r.hidden = p, p.hidden
      W.SetText(r.label, nil, shownName("page", p.id, p))
      r.eye:SetShown(p.hidden)
      setMark(r)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", content, "TOPLEFT", BOX_PAD + 2, y)
      r:SetPoint("RIGHT", content, "RIGHT", -(BOX_PAD + 2), 0)
      r:Show()
      order[#order + 1] = r
      paintRow(r)
      y = y - ROW_H
    end
    y = y - BOX_PAD
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", content, "TOPLEFT", 0, top)
    box:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", 0, y)
    box:Show()
    paintBox(box)
    y = y - BOX_GAP
  end
  d.list:SetContentHeight(-y + BOX_GAP)
  ns.Sidebar.SyncFocusOrder(order)
end

-- Settings of the selection ------------------------------------------------------------------------

local function hexOf(r, g, b)
  local function byte(v)
    return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5)
  end
  return string.format("%02x%02x%02x", byte(r), byte(g), byte(b))
end

-- Opens the game's color picker. The picker reports every step while it is open, so the choice is applied once
-- when it closes (not when it was cancelled).
local pending, hooked
local function openPicker(groupId, current)
  local picker = rawget(_G, "ColorPickerFrame")
  if not picker then
    return
  end
  pending = nil
  if not hooked and type(picker.HookScript) == "function" then
    hooked = true
    picker:HookScript(
      "OnHide",
      ns.Wrap("naveditor-color", function()
        if picker.fgStrata then
          picker:SetFrameStrata(picker.fgStrata)
          picker.fgStrata = nil
        end
        local done = pending
        pending = nil
        if done then
          apply("SetColor", done.id, done.hex)
        end
      end)
    )
  end
  local r, g, b = ns.U.hex("#" .. (current or "4a4f58"))
  local function onChange()
    local nr, ng, nb = picker:GetColorRGB()
    pending = { id = groupId, hex = hexOf(nr, ng, nb) }
  end
  local function onCancel()
    pending = nil
  end
  if picker.SetupColorPickerAndShow then
    picker:SetupColorPickerAndShow({
      r = r,
      g = g,
      b = b,
      hasOpacity = false,
      swatchFunc = onChange,
      cancelFunc = onCancel,
    })
  else
    picker:SetColorRGB(r, g, b)
    picker.hasOpacity = false
    picker.func = onChange
    picker.cancelFunc = onCancel
    picker:Show()
  end
  -- The editor is a dialog (FULLSCREEN_DIALOG or higher); the game's picker sits on DIALOG and would open behind
  -- it. Lift it above while it is open, the OnHide hook restores its own strata.
  if type(picker.SetFrameStrata) == "function" then
    picker.fgStrata = picker.fgStrata or picker:GetFrameStrata()
    picker:SetFrameStrata("TOOLTIP")
    if picker.Raise then
      picker:Raise()
    end
  end
end

local function commitName(box)
  local target = box.target
  if not target then
    return
  end
  box.target = nil
  local view = currentView()
  local entry = find(view, target.kind, target.id)
  if not entry then
    return
  end
  local text = NL.CleanName(box.edit:GetText()) or ""
  -- The default title typed in full is the default, not a custom name.
  if text == defaultName(target.kind, target.id, entry) then
    text = ""
  end
  if text ~= shownName(target.kind, target.id, entry) and not (text == "" and entry.name == nil) then
    apply("Rename", target.kind, target.id, text)
  end
end

function NE.Step(kind, id, delta)
  return apply("Step", kind, id, delta)
end

local function setVisible(kind, id, entry)
  apply("SetHidden", kind, id, not entry.hidden)
end

-- The line under a field in the character scope: "From the account", or the action that drops the own setting.
local NOTE_FIELDS = { "name", "color", "hidden", "place" }
local PLACE_FIELD = { group = "order", page = "group" }

local function newNote(c, field)
  local n = { field = field }
  n.inherit = W.Text(c, { key = "nav.editor.fromAccount", role = "micro", color = "textMuted" })
  n.use = W.Action(c, {
    key = "nav.editor.useAccount",
    icon = "reset",
    height = 24,
    width = 170,
    tooltip = "nav.editor.useAccount",
    tooltipText = "nav.editor.useAccountHint",
    onClick = function()
      local t = d.target
      if t then
        NL.ClearOverride(t.kind, t.id, n.target)
      end
    end,
  })
  return n
end

local function newConfig()
  local area = W.ScrollArea(d)
  local c = area.content
  d.config = area
  local cfg = {}
  d.cfg = cfg
  cfg.heading = W.Text(c, { role = "ui", color = "accent2" })

  cfg.nameLabel = W.Text(c, { key = "nav.editor.name", role = "micro", color = "textMuted" })
  cfg.nameBox = W.EditBox(c, { height = 26 })
  cfg.nameBox.edit:SetMaxLetters(NL.MAX_NAME)
  cfg.nameBox.edit:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  cfg.nameBox.edit:SetScript("OnEscapePressed", function(self)
    cfg.nameBox.target = nil
    self:ClearFocus()
    NE.Refresh()
  end)
  cfg.nameBox.edit:HookScript("OnEditFocusLost", function()
    commitName(cfg.nameBox)
  end)
  cfg.resetName = W.Action(c, {
    icon = "reset",
    size = 26,
    tooltip = "nav.editor.resetName",
    tooltipText = "nav.editor.renameHint",
    onClick = function()
      local box = cfg.nameBox
      box.edit:ClearFocus()
      box.target = nil
      if d.target then
        apply("Rename", d.target.kind, d.target.id, "")
      end
    end,
  })

  cfg.colorLabel = W.Text(c, { key = "nav.editor.color", role = "micro", color = "textMuted" })
  cfg.grid = W.ColorSwatchGrid(c, {
    colors = PALETTE,
    columns = 4,
    swatchSize = 24,
    get = function()
      local color = d.target and d.target.kind == "group" and NL.GroupColor(d.target.id)
      return color and ("#" .. color) or nil
    end,
    onPick = function(color)
      if d.target then
        apply("SetColor", d.target.id, (color:gsub("^#", "")))
      end
    end,
    tooltipFor = function(_, index)
      return L["nav.editor.tone." .. index]
    end,
  })
  cfg.custom = W.Action(c, {
    key = "nav.editor.colorCustom",
    icon = "palette",
    width = 140,
    height = 28,
    tooltip = "nav.editor.colorCustom",
    opens = true,
    onClick = function()
      if d.target then
        openPicker(d.target.id, NL.GroupColor(d.target.id))
      end
    end,
  })
  cfg.none = W.Action(c, {
    key = "nav.editor.colorNone",
    icon = "close",
    width = 140,
    height = 28,
    tooltip = "nav.editor.colorNone",
    onClick = function()
      if d.target then
        apply("SetColor", d.target.id, nil)
      end
    end,
  })

  cfg.visible = W.Action(c, {
    key = "nav.editor.visible",
    icon = "eye",
    width = 140,
    height = 28,
    manual = true,
    onClick = function()
      local view = currentView()
      local entry = d.target and find(view, d.target.kind, d.target.id)
      if entry then
        setVisible(d.target.kind, d.target.id, entry)
      end
    end,
  })
  cfg.visible:HookScript("OnEnter", function(self)
    local t = d.target
    local entry = t and find(currentView(), t.kind, t.id)
    local locked = entry and (t.kind == "page" and entry.protected and "nav.edit.lockedPage" or t.kind == "group" and entry.locked and "nav.edit.lockedGroup")
    ns.ShowTooltip(self, L["nav.editor.visible"], locked and L[locked] or L["nav.edit.hideHint"])
  end)
  cfg.visible:HookScript("OnLeave", ns.HideTooltip)

  cfg.up = W.Action(c, {
    key = "nav.editor.up",
    icon = "chevron-up",
    width = 140,
    height = 28,
    tooltip = "nav.editor.up",
    onClick = function()
      if d.target then
        NE.Step(d.target.kind, d.target.id, -1)
      end
    end,
  })
  cfg.down = W.Action(c, {
    key = "nav.editor.down",
    icon = "chevron-down",
    width = 140,
    height = 28,
    tooltip = "nav.editor.down",
    onClick = function()
      if d.target then
        NE.Step(d.target.kind, d.target.id, 1)
      end
    end,
  })

  cfg.notes = {}
  for _, field in ipairs(NOTE_FIELDS) do
    cfg.notes[field] = newNote(c, field)
  end

  cfg.options = {}
  cfg.moveTo = W.Dropdown(c, {
    key = "nav.editor.moveTo",
    width = 250,
    options = cfg.options,
    get = function()
      return d.target and d.target.group
    end,
    set = function(groupId)
      local t = d.target
      if not t or groupId == t.group then
        return
      end
      local view = currentView()
      local _, target = find(view, "group", groupId)
      apply("Move", "page", t.id, (target and #target.pages or 0) + 1, groupId)
    end,
  })
  return area
end

local function refreshConfig(view)
  local cfg = d.cfg
  local entry, group = find(view, sel.kind, sel.id)
  d.target = entry and { kind = sel.kind, id = sel.id, group = group.id } or nil
  local isGroup = sel.kind == "group"
  local width = CONFIG_W - 12
  local y = 0
  local function put(frame, x, h, gap)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", d.config.content, "TOPLEFT", x, -y)
    y = y + h + (gap or 0)
  end
  -- Character scope only: the inheritance line of a field. `field` is the NOTE_FIELDS name.
  local function note(field, gap)
    local n = cfg.notes[field]
    local own = NE.Scope() == "char"
    n.target = field == "place" and PLACE_FIELD[sel.kind] or field
    local overridden = own and NL.IsOverridden(sel.kind, sel.id, n.target)
    n.use:SetShown(overridden)
    n.inherit:SetShown(own and not overridden)
    if overridden then
      put(n.use, 0, 24, gap)
    elseif own then
      put(n.inherit, 2, 14, gap)
    end
  end
  if not entry then
    for _, name in ipairs({ "heading", "nameLabel", "nameBox", "resetName", "colorLabel", "grid", "custom", "none", "visible", "up", "down", "moveTo" }) do
      cfg[name]:Hide()
    end
    for _, n in pairs(cfg.notes) do
      n.inherit:Hide()
      n.use:Hide()
    end
    return
  end
  cfg.heading:Show()
  W.SetText(cfg.heading, isGroup and "nav.editor.group" or "nav.editor.page")
  cfg.heading:SetWidth(width)
  put(cfg.heading, 0, 22, 4)

  cfg.nameLabel:Show()
  put(cfg.nameLabel, 0, 14, 2)
  cfg.nameBox:Show()
  cfg.nameBox:SetWidth(width - 26 - 6)
  put(cfg.nameBox, 0, 0)
  cfg.resetName:Show()
  cfg.resetName:ClearAllPoints()
  cfg.resetName:SetPoint("TOPLEFT", d.config.content, "TOPLEFT", width - 26, -y)
  y = y + 26 + 4
  note("name", 10)
  if not cfg.nameBox.edit:HasFocus() then
    cfg.nameBox.target = nil
    cfg.nameBox.edit:SetText(shownName(sel.kind, sel.id, entry))
  end
  cfg.nameBox.target = { kind = sel.kind, id = sel.id }

  cfg.colorLabel:SetShown(isGroup)
  cfg.grid:SetShown(isGroup)
  cfg.custom:SetShown(isGroup)
  cfg.none:SetShown(isGroup)
  if isGroup then
    put(cfg.colorLabel, 0, 14, 2)
    cfg.grid:Refresh()
    put(cfg.grid, 0, cfg.grid:GetHeight(), 6)
    cfg.custom:ClearAllPoints()
    cfg.custom:SetPoint("TOPLEFT", d.config.content, "TOPLEFT", 0, -y)
    cfg.none:ClearAllPoints()
    cfg.none:SetPoint("LEFT", cfg.custom, "RIGHT", 8, 0)
    y = y + 28 + 4
    note("color", 10)
  else
    note("color")
  end

  local locked = isGroup and entry.locked or entry.protected
  cfg.visible:Show()
  cfg.visible:SetIcon(entry.hidden and "eye-off" or "eye")
  cfg.visible:SetSelected(not entry.hidden)
  cfg.visible:SetEnabled(not locked)
  put(cfg.visible, 0, 28, 4)
  note("hidden", 10)

  cfg.up:Show()
  cfg.down:Show()
  cfg.up:SetEnabled(canStep(sel.kind, sel.id, -1))
  cfg.down:SetEnabled(canStep(sel.kind, sel.id, 1))
  cfg.up:ClearAllPoints()
  cfg.up:SetPoint("TOPLEFT", d.config.content, "TOPLEFT", 0, -y)
  cfg.down:ClearAllPoints()
  cfg.down:SetPoint("LEFT", cfg.up, "RIGHT", 8, 0)
  y = y + 28 + 10

  cfg.moveTo:SetShown(not isGroup)
  if not isGroup then
    for i = #cfg.options, 1, -1 do
      cfg.options[i] = nil
    end
    for _, g in ipairs(view.groups) do
      cfg.options[#cfg.options + 1] = { value = g.id, text = shownName("group", g.id, g) }
    end
    cfg.moveTo:Refresh()
    put(cfg.moveTo, 0, cfg.moveTo:GetHeight(), 4)
  end
  note("place")
  d.config:SetContentHeight(y + 8)
end

-- Window -------------------------------------------------------------------------------------------

local function fitButton(button, text, min, max)
  W.SetText(button.label, nil, text)
  button.fgName = function()
    return text
  end
  button:SetWidth(math.max(min, math.min(max, button:FullWidth())))
end

local function layout()
  local scopeNow = NE.Scope()
  local inner = WIDTH - 2 * PAD
  d.scopeAll:SetSelected(scopeNow == "account")
  d.scopeChar:SetSelected(scopeNow == "char")
  fitButton(d.scopeChar, NE.ScopeCharText(), 120, 260)
  fitButton(d.reset, NE.ResetText(scopeNow), 130, inner)
  W.SetText(d.status, nil, NE.StatusText(scopeNow))
  d.status:SetWidth(inner)
  d.hint:SetWidth(inner)
  local top = TOP_Y + math.ceil(d.status:GetStringHeight()) + 8
  d.scopeAll:ClearAllPoints()
  d.scopeAll:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -top)
  top = top + 26 + 6
  d.reset:ClearAllPoints()
  d.reset:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -top)
  top = top + 26 + 8
  d.hint:ClearAllPoints()
  d.hint:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -top)
  top = top + math.ceil(d.hint:GetStringHeight()) + 10
  d.list:ClearAllPoints()
  d.list:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -top)
  d.list:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", PAD, PAD)
  d.list:SetWidth(LIST_W)
  d.config:ClearAllPoints()
  d.config:SetPoint("TOPLEFT", d, "TOPLEFT", PAD + LIST_W + COLUMN_GAP, -top)
  d.config:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -PAD, PAD)
end

function NE.Refresh()
  if not d or not d:IsShown() then
    return
  end
  local view = currentView()
  if not find(view, sel.kind, sel.id) then
    sel.kind, sel.id = "group", view.groups[1] and view.groups[1].id
  end
  layout()
  refreshList(view)
  refreshConfig(view)
  d.toggleSync()
end

-- Beside the main window: right of it when there is room, else left of it, else over its edge. Always inside
-- the screen, and never taller than 95% of it (the lists scroll).
function NE.Place()
  local main = ns.Main and ns.Main.frame
  local UI = ns.SetupWizardUI
  local screenH = UIParent:GetHeight() * (UIParent:GetEffectiveScale() or 1)
  local screenW = UIParent:GetWidth() * (UIParent:GetEffectiveScale() or 1)
  local scale = d:GetEffectiveScale() or 1
  if screenH > 0 and scale > 0 then
    d:SetHeight(math.max(240, math.min(HEIGHT, math.floor(screenH * 0.95 / scale))))
  end
  if not (main and main:IsShown() and UI and UI.ScreenRect and screenW > 0) then
    return
  end
  local rect = UI.ScreenRect(main)
  if not rect then
    return
  end
  local width, height = d:GetWidth() * scale, d:GetHeight() * scale
  local gap = ns.SetupWizard and ns.SetupWizard.PLACE.gap or 8
  local left
  if rect.r + gap + width <= screenW then
    left = rect.r + gap
  elseif rect.l - gap - width >= 0 then
    left = rect.l - gap - width
  else
    left = screenW - width
  end
  left = math.max(0, math.min(left, screenW - width))
  local top = math.max(math.min(rect.t, screenH), math.min(height, screenH))
  UI.MoveTo(d, left, { t = top })
end

local function build()
  d = ns.Dialogs.Create("ForeverGuidesNavEditor", WIDTH, HEIGHT)
  W.SetText(d.title, "nav.editor.title")
  d.status = W.Text(d, { text = " ", role = "ui", color = "text", wrap = true })
  d.status:SetPoint("TOPLEFT", PAD, -TOP_Y)
  d.scopeAll = W.Action(d, {
    key = "nav.editor.scopeAll",
    width = 150,
    height = 26,
    tooltip = "nav.editor.scopeAll",
    tooltipText = "nav.edit.scopeHint",
    onClick = function()
      NE.SetScope("account")
    end,
  })
  d.scopeAll:SetPoint("TOPLEFT", PAD, -TOP_Y - 24)
  -- The label names the character, so it is set on every layout.
  d.scopeChar = W.Action(d, {
    text = " ",
    manual = true,
    width = 190,
    height = 26,
    onClick = function()
      NE.SetScope("char")
    end,
  })
  d.scopeChar:SetPoint("LEFT", d.scopeAll, "RIGHT", 8, 0)
  d.reset = W.Action(d, {
    text = " ",
    manual = true,
    icon = "reset",
    width = 200,
    height = 26,
    onClick = function()
      NE.RequestReset()
    end,
  })
  d.reset:SetPoint("TOPLEFT", PAD, -TOP_Y - 56)
  d.hint = W.Text(d, { key = "nav.editor.hint", role = "micro", color = "textSecondary", wrap = true })
  d.hint:SetPoint("TOPLEFT", PAD, -TOP_Y - 90)
  for _, button in ipairs({ d.scopeChar, d.reset }) do
    button:HookScript("OnEnter", function(self)
      ns.ShowTooltip(self, self.fgName(), L["nav.edit.scopeHint"])
    end)
    button:HookScript("OnLeave", ns.HideTooltip)
  end
  d.list = W.ScrollArea(d)
  newConfig()
  d:HookScript("OnShow", function()
    NE.Place()
    NE.Refresh()
  end)
  d:HookScript("OnHide", function()
    d.toggleSync()
  end)
  d.toggleSync = function()
    local f = ns.Anchors["FG.Sidebar"]
    local button = f and f.fgEdit and f.fgEdit.toggle
    if button then
      button:SetSelected(d:IsShown())
    end
  end
  return d
end

-- The window, the controls of its settings column and the preview row of an entry (tests read them).
function NE.Window()
  return d
end

function NE.Controls()
  return d and d.cfg
end

function NE.Row(kind, id)
  return rows[kind .. ":" .. id]
end

function NE.Selection()
  return sel.kind, sel.id
end

function NE.IsOpen()
  return d ~= nil and d:IsShown()
end

-- Opens the window; groupId (optional) selects that group.
function NE.Open(groupId)
  ns.Main.Show()
  d = d or build()
  if groupId then
    sel.kind, sel.id = "group", groupId
  end
  if d:IsShown() then
    NE.Place()
    NE.Refresh()
  else
    d:Show()
  end
  return true
end

function NE.Close()
  if d and d:IsShown() then
    d:Hide()
    return true
  end
  return false
end

function NE.Toggle()
  if NE.IsOpen() then
    NE.Close()
  else
    NE.Open()
  end
end

ns.On("FG_NAV_CHANGED", NE.Refresh)
ns.On("FG_NAV_SCOPE", NE.Refresh)
ns.On("FG_MAIN_HIDDEN", NE.Close)

-- Pencil hint: a soft glow around the pencil while the setup wizard points at it (steps start, menu, done). It
-- pulses, and stands still with "Reduce motion". Only textures and an animation group of our own button, no
-- protected frame is touched.
local hintOn = false

function NE.PaintHint(button)
  if not button then
    local f = ns.Anchors["FG.Sidebar"]
    button = f and f.fgEdit and f.fgEdit.toggle
  end
  if not button then
    return
  end
  if not button.fgHint then
    local glow = button:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", -9, 9)
    glow:SetPoint("BOTTOMRIGHT", 9, -9)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(ns.Theme.rgb("accent2"))
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.3)
    alpha:SetToAlpha(0.95)
    alpha:SetDuration(1.1)
    button.fgHint = { glow = glow, pulse = pulse }
  end
  local hint = button.fgHint
  hint.glow:SetShown(hintOn)
  if hintOn and not ns.Theme.reduceMotion() then
    hint.glow:SetAlpha(0.3)
    hint.pulse:Play()
  else
    hint.pulse:Stop()
    hint.glow:SetAlpha(hintOn and 0.85 or 0)
  end
end

function NE.SetHint(on)
  hintOn = on == true
  NE.PaintHint()
end

function NE.HintActive()
  return hintOn
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if hintOn and path == "settings.reduceMotion" then
    NE.PaintHint()
  end
end)

-- The pencil in the header strip of the sidebar.
function NE.Attach(f)
  local e = {}
  f.fgEdit = e
  -- Boxed (surface and edge) and a 16 px symbol: the plain arrow next to it is easy to read as the
  -- only control, the pencil has to stand out as a button of its own.
  e.toggle = W.Action(f, {
    icon = "pencil",
    size = 24,
    iconSize = 16,
    boxed = true,
    tooltip = "nav.edit.toggle",
    tooltipText = "nav.edit.toggleHint",
    opens = true,
    onClick = function()
      NE.Toggle()
    end,
  })
  NE.PencilTip(e.toggle, "nav.edit.toggle", "nav.edit.toggleHint")
  e.toggle.fgId = "nav-edit-toggle"
  e.toggle:SetPoint("TOPRIGHT", -38, -6)
  NE.PaintHint(e.toggle)
  -- Target of the start tour; hidden on the icon rail, where the tour skips the step.
  ns.Anchors["FG.Sidebar.Edit"] = e.toggle
end
