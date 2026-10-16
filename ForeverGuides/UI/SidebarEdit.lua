-- Edit mode of the left navigation: hide and show entries and groups, rename them, move them by
-- dragging or with Shift+Up and Shift+Down, and go back to the default. The layout data and its rules
-- are Modules/NavLayoutLogic.lua, the list itself is UI/Sidebar.lua; this file adds the controls on the
-- rows, the banner and the bottom bar of the edit mode, and the drag and drop.
--
-- The sidebar uses no protected frame, so the mode works in combat as well. The icon rail has no room
-- for the controls: while the mode is on, the window shows the full sidebar (Layout.compute, forceFull).
local _, ns = ...
local W, Theme, L, NL = ns.W, ns.Theme, ns.L, ns.NavLayout

local SE = {}
ns.SidebarEdit = SE

ns.AddLocale("enUS", {
  ["nav.edit.toggle"] = "Edit navigation",
  ["nav.edit.title"] = "Editing the navigation",
  ["nav.edit.hint"] = "Drag entries and groups to move them. With the keyboard: select one and press Shift+Up or Shift+Down.",
  ["nav.edit.dragHint"] = "Drag to move. Shift+Up or Shift+Down moves it with the keyboard.",
  ["nav.edit.hide"] = "Hide in menu",
  ["nav.edit.show"] = "Show in menu",
  ["nav.edit.hideHint"] = "A hidden entry stays reachable through search and commands.",
  ["nav.edit.lockedPage"] = "This entry always stays in the menu.",
  ["nav.edit.lockedGroup"] = "This group holds an entry that always stays in the menu.",
  ["nav.edit.rename"] = "Rename",
  ["nav.edit.renameHint"] = "Leave the name empty to restore the default.",
  ["nav.edit.scope"] = "Only this character",
  ["nav.edit.scopeHint"] = "Off: the layout applies to all your characters. On: this character gets its own layout.",
  ["nav.edit.scopeNotice"] = "This character has its own layout, which wins over this one.",
  ["nav.edit.reset"] = "Reset to default",
  ["nav.edit.done"] = "Finish editing",
  ["nav.reset.title"] = "Reset navigation",
  ["nav.reset.textAccount"] = "All entries and groups return to their default place, name and visibility for all characters.",
  ["nav.reset.textChar"] = "This character stops using its own layout and follows the layout of all characters again.",
})
ns.AddLocale("deDE", {
  ["nav.edit.toggle"] = "Navigation bearbeiten",
  ["nav.edit.title"] = "Navigation wird bearbeitet",
  ["nav.edit.hint"] = "Einträge und Gruppen ziehen, um sie zu verschieben. Mit der Tastatur: einen auswählen und Umschalt+Hoch oder Umschalt+Runter drücken.",
  ["nav.edit.dragHint"] = "Ziehen zum Verschieben. Umschalt+Hoch oder Umschalt+Runter verschiebt per Tastatur.",
  ["nav.edit.hide"] = "Im Menü ausblenden",
  ["nav.edit.show"] = "Im Menü einblenden",
  ["nav.edit.hideHint"] = "Ein ausgeblendeter Eintrag bleibt über Suche und Befehle erreichbar.",
  ["nav.edit.lockedPage"] = "Dieser Eintrag bleibt immer im Menü.",
  ["nav.edit.lockedGroup"] = "Diese Gruppe enthält einen Eintrag, der immer im Menü bleibt.",
  ["nav.edit.rename"] = "Umbenennen",
  ["nav.edit.renameHint"] = "Ein leerer Name stellt den Standard wieder her.",
  ["nav.edit.scope"] = "Nur dieser Charakter",
  ["nav.edit.scopeHint"] = "Aus: Die Anordnung gilt für alle deine Charaktere. An: Dieser Charakter bekommt eine eigene Anordnung.",
  ["nav.edit.scopeNotice"] = "Dieser Charakter hat eine eigene Anordnung, sie geht dieser vor.",
  ["nav.edit.reset"] = "Auf Standard zurücksetzen",
  ["nav.edit.done"] = "Bearbeiten beenden",
  ["nav.reset.title"] = "Navigation zurücksetzen",
  ["nav.reset.textAccount"] = "Alle Einträge und Gruppen kehren für alle Charaktere zu Standardplatz, Standardname und Standardsichtbarkeit zurück.",
  ["nav.reset.textChar"] = "Dieser Charakter nutzt seine eigene Anordnung nicht mehr und folgt wieder der Anordnung für alle Charaktere.",
})

local DIM_ALPHA = 0.6
local BUTTON = 20
local EDGE_SCROLL, SCROLL_SPEED = 28, 260
local CLICK_AFTER_DRAG = 0.25

local scope -- "account" or "char"; nil until chosen, then it follows whether this character has a layout
local drag -- the running drag: { f, row, kind, id, ghost, target }
local lastDragEnd = -10
local renaming -- { f, row, kind, id }
local renameBox

local function sidebar()
  return ns.Anchors["FG.Sidebar"]
end

local function kindOf(row)
  return row.page and "page" or "group"
end

local function idOf(row)
  return row.page and row.page.id or row.group
end

-- Which layer an edit writes to: "account" (all characters) or "char" (this character only).
function SE.Scope()
  return scope or (NL.HasCharLayout() and "char" or "account")
end

function SE.SetScope(value)
  scope = value == "char" and "char" or "account"
  local f = sidebar()
  if f and f.editing then
    f:Rebuild()
  end
  ns.Emit("FG_NAV_SCOPE", scope)
end

function SE.IsEditing()
  local f = sidebar()
  return f ~= nil and f.editing == true
end

-- True right after a drop: the click the client may still send to the row that was dragged.
function SE.JustDragged()
  return GetTime() - lastDragEnd < CLICK_AFTER_DRAG
end

-- Rows ------------------------------------------------------------------------------------------

local function showDefault(row)
  return row.page and L[row.page.title] or L["nav.group." .. row.group]
end

local function anchorLabel(row, editing)
  row.label:ClearAllPoints()
  if row.page then
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
  else
    row.label:SetPoint("LEFT", row.arrow, "RIGHT", 4, 0)
  end
  if editing then
    row.label:SetPoint("RIGHT", row.fgEdit.rename, "LEFT", -4, 0)
  else
    row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  end
end

local function lockedKey(row)
  local entry = row.entry
  if row.page then
    return entry.protected and "nav.edit.lockedPage" or nil
  end
  return entry.locked and "nav.edit.lockedGroup" or nil
end

local function toggleHidden(row)
  NL.Apply(SE.Scope(), "SetHidden", kindOf(row), idOf(row), not row.entry.hidden)
end

-- The grip (three short bars), the rename button and the eye button of a row; built the first time
-- the edit mode shows the row.
local function newControls(f, row)
  local c = { grip = {} }
  for i = 1, 3 do
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetSize(row.page and 6 or 4, 1)
    bar:SetPoint("LEFT", row.page and 4 or 2, (i - 2) * 4)
    c.grip[i] = bar
  end
  ns.Bind(row, function()
    for _, bar in ipairs(c.grip) do
      bar:SetColorTexture(Theme.color("textMuted"))
    end
  end)
  c.rename = W.Action(row, {
    icon = "pencil",
    size = BUTTON,
    tooltip = "nav.edit.rename",
    tooltipText = "nav.edit.renameHint",
    onClick = function()
      SE.StartRename(f, row)
    end,
  })
  c.rename:SetPoint("RIGHT", row, "RIGHT", -(BUTTON + 6), 0)
  c.eye = W.Action(row, {
    icon = "eye",
    size = BUTTON,
    tooltip = "nav.edit.hide",
    manual = true,
    onClick = function()
      toggleHidden(row)
    end,
  })
  c.eye:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  c.eye:HookScript("OnEnter", function(self)
    local locked = lockedKey(row)
    ns.ShowTooltip(
      self,
      L[self.fgNameKey],
      locked and L[locked] or (not row.entry.hidden and L["nav.edit.hideHint"]) or nil
    )
  end)
  c.eye:HookScript("OnLeave", ns.HideTooltip)
  row:SetScript("OnDragStart", function(self)
    if f.editing then
      SE.BeginDrag(f, self)
    end
  end)
  row:SetScript("OnDragStop", function()
    SE.EndDrag(f, true)
  end)
  return c
end

-- Called by the sidebar for every row it lists: shows or hides the controls for the current mode and
-- dims what the menu hides.
function SE.Decorate(f, row)
  local editing = f.editing
  if editing and not row.fgEdit then
    row.fgEdit = newControls(f, row)
  end
  local c = row.fgEdit
  if c then
    for _, bar in ipairs(c.grip) do
      bar:SetShown(editing)
    end
    c.rename:SetShown(editing)
    c.eye:SetShown(editing)
    if row.fgEditing ~= editing then
      anchorLabel(row, editing)
      row.fgEditing = editing
    end
  end
  if editing then
    row:RegisterForDrag("LeftButton")
  else
    row:RegisterForDrag()
  end
  local entry = row.entry
  local hidden = editing and entry.hidden == true
  local dim = hidden or (editing and row.parentEntry ~= nil and row.parentEntry.hidden == true)
  local alpha = dim and DIM_ALPHA or 1
  row.label:SetAlpha(alpha)
  if row.icon then
    row.icon:SetAlpha(alpha)
  else
    row.arrow:SetAlpha(alpha)
  end
  row.fgReorder = editing and function(self, delta)
    SE.Step(self, delta)
  end or nil
  if c and editing then
    c.eye:SetIcon(entry.hidden and "eye-off" or "eye")
    c.eye.fgNameKey = entry.hidden and "nav.edit.show" or "nav.edit.hide"
    c.eye:SetSelected(entry.hidden == true)
    c.eye:SetEnabled(lockedKey(row) == nil)
  end
end

-- The row and the controls that belong to it, left to right, for the keyboard order.
function SE.AppendFrames(frames, row)
  frames[#frames + 1] = row
  local c = row.fgEdit
  if c and row.fgEditing then
    frames[#frames + 1] = c.rename
    frames[#frames + 1] = c.eye
  end
end

-- Edits ------------------------------------------------------------------------------------------

function SE.Step(row, delta)
  return NL.Apply(SE.Scope(), "Step", kindOf(row), idOf(row), delta)
end

local function endRename(commit)
  local r = renaming
  if not r then
    return
  end
  renaming = nil
  local text = NL.CleanName(renameBox.edit:GetText()) or ""
  renameBox:Hide()
  renameBox.edit:ClearFocus()
  r.row.label:Show()
  SE.Decorate(r.f, r.row)
  if commit then
    -- The default title typed in full is the default, not a custom name.
    if text == showDefault(r.row) then
      text = ""
    end
    local shown = r.row.entry.name or showDefault(r.row)
    if text ~= shown and not (text == "" and r.row.entry.name == nil) then
      NL.Apply(SE.Scope(), "Rename", r.kind, r.id, text)
    end
  end
end

local function getRenameBox(f)
  if not renameBox then
    renameBox = W.EditBox(f.area.content, {
      height = 22,
      onEnter = function()
        endRename(true)
      end,
    })
    renameBox.edit:SetMaxLetters(NL.MAX_NAME)
    renameBox.edit:SetScript("OnEscapePressed", function()
      endRename(false)
    end)
    renameBox.edit:HookScript("OnEditFocusLost", function()
      endRename(true)
    end)
    renameBox:Hide()
  end
  return renameBox
end

-- Puts a text field over the label of the row; Enter or leaving the field saves, Esc cancels, an
-- empty text restores the default name.
function SE.StartRename(f, row)
  endRename(true)
  local box = getRenameBox(f)
  renaming = { f = f, row = row, kind = kindOf(row), id = idOf(row) }
  box:SetParent(row)
  box:ClearAllPoints()
  if row.page then
    box:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  else
    box:SetPoint("LEFT", row.arrow, "RIGHT", 0, 0)
  end
  box:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.label:Hide()
  row.fgEdit.rename:Hide()
  row.fgEdit.eye:Hide()
  box:Show()
  box.edit:SetText(row.entry.name or showDefault(row))
  box.edit:SetFocus()
  box.edit:HighlightText()
end

function SE.RequestReset(layer)
  layer = layer or SE.Scope()
  ns.Dialogs.Confirm("nav.reset.title", layer == "char" and "nav.reset.textChar" or "nav.reset.textAccount", function()
    NL.ResetLayer(layer)
  end)
end

-- Drag and drop -----------------------------------------------------------------------------------

-- Where a drop at y (distance below the top of the list) would land: the nearest line between two
-- shown rows. A page lands in the group above the line at the slot below it, a group among the groups.
-- Returns { kind, group, slot, y } with y the line to draw, nil when nothing is shown.
function SE.Target(f, kind, y)
  local best
  local function consider(line, group, slot)
    if not best or math.abs(y - line) < math.abs(y - best.y) then
      best = { kind = kind, group = group, slot = slot, y = line }
    end
  end
  local lastBottom
  for k, h in ipairs(f.headers) do
    if h.navTop then
      if kind == "group" then
        consider(h.navTop - 1, h.group, k)
      else
        consider(h.navTop + h.navHeight, h.group, 1)
      end
      lastBottom = h.navTop + h.navHeight
      for _, b in ipairs(h.items) do
        if b.navTop then
          if kind == "page" then
            consider(b.navTop + b.navHeight, b.navGroup, b.navIndex + 1)
          end
          lastBottom = b.navTop + b.navHeight
        end
      end
    end
  end
  if kind == "group" and lastBottom then
    consider(lastBottom, nil, #f.headers + 1)
  end
  return best
end

-- The cursor as a distance below the top of the list content, and the cursor below the top of the
-- visible area (for scrolling at the edges).
local function cursorOffsets(f)
  local _, cy = GetCursorPosition()
  local scale = f.area:GetEffectiveScale()
  if not scale or scale <= 0 then
    scale = 1
  end
  local viewY = f.area:GetTop() - (cy or 0) / scale
  return viewY + f.area:GetVerticalScroll(), viewY
end

local function getGhost(f)
  local e = f.fgEdit
  if not e.ghost then
    local ghost = CreateFrame("Frame", nil, f)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetHeight(28)
    W.Fill(ghost, "surface2", 0.95)
    W.Border(ghost, "accent2", 1)
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetSize(18, 18)
    ghost.icon:SetPoint("LEFT", 13, 0)
    ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ghost.label = W.Text(ghost, { role = "ui", color = "text" })
    ghost.label:SetPoint("LEFT", 36, 0)
    ghost.label:SetPoint("RIGHT", -6, 0)
    ghost:Hide()
    e.ghost = ghost
    local line = f.area.content:CreateTexture(nil, "OVERLAY")
    line:SetHeight(2)
    ns.Bind(line, function(t)
      t:SetColorTexture(Theme.color("accent2"))
    end)
    line:Hide()
    e.line = line
    e.driver = CreateFrame("Frame", nil, f)
    e.driver:Hide()
  end
  return e
end

local function placeGhost(f, e, row)
  local _, viewY = cursorOffsets(f)
  local height = row.navHeight or 28
  e.ghost:SetHeight(height)
  e.ghost:ClearAllPoints()
  e.ghost:SetPoint("TOPLEFT", f.area, "TOPLEFT", 4, -(viewY - height / 2))
  e.ghost:SetPoint("RIGHT", f.area, "RIGHT", -6, 0)
end

-- Ghost, scrolling at the edges of the list and the drop line for the current cursor position.
local function follow(f, elapsed)
  local d = drag
  local e = f.fgEdit
  local _, viewY = cursorOffsets(f)
  placeGhost(f, e, d.row)
  local height = f.area:GetHeight()
  if viewY < EDGE_SCROLL then
    local push = math.min(1, (EDGE_SCROLL - viewY) / EDGE_SCROLL)
    f.area:ScrollTo(f.area:GetVerticalScroll() - SCROLL_SPEED * elapsed * push)
  elseif height > 0 and viewY > height - EDGE_SCROLL then
    local push = math.min(1, (viewY - (height - EDGE_SCROLL)) / EDGE_SCROLL)
    f.area:ScrollTo(f.area:GetVerticalScroll() + SCROLL_SPEED * elapsed * push)
  end
  d.target = SE.Target(f, d.kind, (cursorOffsets(f)))
  if d.target then
    e.line:ClearAllPoints()
    e.line:SetPoint("TOPLEFT", f.area.content, "TOPLEFT", 4, -d.target.y)
    e.line:SetPoint("RIGHT", f.area.content, "RIGHT", -4, 0)
    e.line:Show()
  else
    e.line:Hide()
  end
end

local function tick(f, elapsed)
  if not drag or drag.f ~= f then
    return
  end
  if IsMouseButtonDown("LeftButton") then
    follow(f, elapsed)
  else
    SE.EndDrag(f, true)
  end
end

function SE.BeginDrag(f, row)
  if drag or not f.editing or not row.navTop then
    return false
  end
  endRename(true)
  local e = getGhost(f)
  drag = { f = f, row = row, kind = kindOf(row), id = idOf(row) }
  e.ghost.label:SetText(row.label:GetText())
  if row.icon then
    e.ghost.icon:SetTexture(row.icon:GetTexture())
  end
  e.ghost.icon:SetShown(row.icon ~= nil)
  e.ghost:Show()
  row:SetAlpha(0.5)
  e.driver:SetScript("OnUpdate", function(_, elapsed)
    ns.Safe("nav-drag", tick, f, elapsed)
  end)
  e.driver:Show()
  follow(f, 0)
  return true
end

-- drop = true applies the move to the line the cursor is on, false cancels.
function SE.EndDrag(f, drop)
  local d = drag
  if not d then
    return false
  end
  drag = nil
  lastDragEnd = GetTime()
  local e = f.fgEdit
  e.driver:Hide()
  e.driver:SetScript("OnUpdate", nil)
  e.ghost:Hide()
  e.line:Hide()
  d.row:SetAlpha(1)
  local t = d.target
  if drop and t then
    if d.kind == "group" then
      NL.Apply(SE.Scope(), "Move", "group", d.id, t.slot)
    else
      NL.Apply(SE.Scope(), "Move", "page", d.id, t.slot, t.group)
    end
  end
  return true
end

function SE.IsDragging()
  return drag ~= nil
end

-- The line the running drag would drop on (tests read it), nil without a drag.
function SE.DropTarget()
  return drag and drag.target or nil
end

-- The shared text field of the rename (tests type into it), nil before the first rename.
function SE.RenameField()
  return renameBox
end

-- Banner, bottom bar and the pencil ---------------------------------------------------------------

local function newChrome(f)
  local e = f.fgEdit
  local banner = CreateFrame("Frame", nil, f)
  W.Fill(banner, "surface2", 1)
  local edge = banner:CreateTexture(nil, "ARTWORK")
  edge:SetPoint("TOPLEFT")
  edge:SetPoint("BOTTOMLEFT")
  edge:SetWidth(3)
  ns.Bind(edge, function(t)
    t:SetColorTexture(Theme.color("accent2"))
  end)
  banner.title = W.Text(banner, { key = "nav.edit.title", role = "ui", color = "accent2", wrap = true })
  banner.title:SetPoint("TOPLEFT", 10, -6)
  banner.hint = W.Text(banner, { key = "nav.edit.hint", role = "micro", color = "textSecondary", wrap = true })
  banner:Hide()
  e.banner = banner

  local bar = CreateFrame("Frame", nil, f)
  W.Fill(bar, "surface2", 1)
  bar.scope = W.Checkbox(bar, {
    key = "nav.edit.scope",
    tooltip = "nav.edit.scope",
    tooltipText = "nav.edit.scopeHint",
    get = function()
      return SE.Scope() == "char"
    end,
    set = function(on)
      SE.SetScope(on and "char" or "account")
    end,
  })
  bar.scope.fgId = "nav-edit-scope"
  bar.scope:SetPoint("TOPLEFT", 8, -8)
  bar.scope:SetPoint("RIGHT", -8, 0)
  bar.notice = W.Text(bar, { key = "nav.edit.scopeNotice", role = "micro", color = "warning", wrap = true })
  bar.reset = W.Action(bar, {
    label = "act.reset",
    icon = "reset",
    tooltip = "nav.edit.reset",
    height = 26,
    width = 84,
    onClick = function()
      SE.RequestReset()
    end,
  })
  bar.reset:SetPoint("BOTTOMLEFT", 8, 8)
  bar.done = W.Action(bar, {
    label = "act.done",
    icon = "check",
    tooltip = "nav.edit.done",
    variant = "primary",
    height = 26,
    width = 84,
    onClick = function()
      SE.Leave()
    end,
  })
  bar.done:SetPoint("BOTTOMRIGHT", -8, 8)
  bar:Hide()
  e.bar = bar
end

-- Called by every layout of the sidebar. Returns the height the banner takes below the header strip
-- and the bar takes at the bottom (0, 0 outside the edit mode).
function SE.Place(f, collapsed)
  local e = f.fgEdit
  if not e then
    return 0, 0
  end
  e.toggle:SetShown(not collapsed)
  e.toggle:SetSelected(f.editing)
  if not f.editing then
    if e.banner then
      e.banner:Hide()
      e.bar:Hide()
    end
    return 0, 0
  end
  if not e.banner then
    newChrome(f)
  end
  local width = f:GetWidth()
  if not width or width <= 0 then
    width = ns.Layout.SIDEBAR_FULL
  end
  local banner, bar = e.banner, e.bar
  banner.title:SetWidth(width - 20)
  banner.hint:ClearAllPoints()
  banner.hint:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -2)
  banner.hint:SetWidth(width - 20)
  local bannerHeight = 6 + banner.title:GetStringHeight() + 2 + banner.hint:GetStringHeight() + 8
  banner:ClearAllPoints()
  banner:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -34)
  banner:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -34)
  banner:SetHeight(bannerHeight)
  banner:Show()

  local showNotice = SE.Scope() == "account" and NL.HasCharLayout()
  bar.notice:ClearAllPoints()
  bar.notice:SetPoint("TOPLEFT", bar.scope, "BOTTOMLEFT", 0, -4)
  bar.notice:SetWidth(width - 16)
  bar.notice:SetShown(showNotice)
  bar.scope.Refresh()
  local barHeight = 8 + 22 + 6 + (showNotice and bar.notice:GetStringHeight() + 4 or 0) + 26 + 8
  bar:ClearAllPoints()
  bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 0)
  bar:SetHeight(barHeight)
  bar:Show()
  return bannerHeight, barHeight
end

-- The pencil in the header strip of the sidebar; the rest is built when the mode starts.
function SE.Attach(f)
  local e = {}
  f.fgEdit = e
  e.toggle = W.Action(f, {
    icon = "pencil",
    size = 24,
    tooltip = "nav.edit.toggle",
    onClick = function()
      SE.Toggle()
    end,
  })
  e.toggle.fgId = "nav-edit-toggle"
  e.toggle:SetPoint("TOPRIGHT", -38, -6)
end

-- Entering and leaving -----------------------------------------------------------------------------

function SE.Enter()
  ns.Main.Show()
  local f = sidebar()
  if not f or f.editing then
    return false
  end
  f.editing = true
  ns.Main.Relayout()
  f:Rebuild()
  return true
end

-- Leaves the mode, or first ends a running drag. Returns whether it did anything (Esc uses this).
function SE.Leave()
  local f = sidebar()
  if not f then
    return false
  end
  if drag then
    SE.EndDrag(f, false)
    return true
  end
  if not f.editing then
    return false
  end
  endRename(true)
  f.editing = false
  ns.Main.Relayout()
  f:Rebuild()
  return true
end

function SE.Toggle()
  if SE.IsEditing() then
    SE.Leave()
  else
    SE.Enter()
  end
end

-- A closed window ends the mode, so it never comes back as a surprise.
ns.On("FG_MAIN_HIDDEN", function()
  local f = sidebar()
  if f and (f.editing or drag) then
    if drag then
      SE.EndDrag(f, false)
    end
    SE.Leave()
  end
end)
