-- Steps "menu" and "menu2" of the setup wizard: show or hide the groups and pages of the left menu (ns.NavLayout).
-- One row per group (a switch, a short sentence, a counter "3 of 4" and an arrow) folds out into its pages, each
-- with a switch, in two columns and without a sentence (it is the tooltip). The first three groups are in the step
-- "menu", the rest in "menu2". One group is open at a time and the block always keeps the room of the largest
-- group, so folding a group out never changes the height of the step. The steps register themselves, their block
-- "menu" is built into the window of Modules/SetupWizard.lua.
--
-- Reads and writes go through Modules/SetupFeatureLogic.lua: the control { type = "menu" } of the step holds
-- the hidden ids of the menu as one text for the summary, and a write is a list of edits that
-- NavLayout.SetHiddenMany applies as one batch (one save, one FG_NAV_CHANGED, one rebuild of the menu).
-- Switching a group off keeps the marks of its pages, so switching it on again brings the old picture back.
-- Groups that hold a protected page (Start, Settings) have no row: the wizard never changes them.
-- The state of a fold is kept while the window lives, nothing of it is stored.
local _, ns = ...
local W, L, SW, NL = ns.W, ns.L, ns.SetupWizard, ns.NavLayout
local FL, R, UI = ns.SetupFeatureLogic, ns.SetupWizardRows, ns.SetupWizardUI

local M = {}
ns.SetupWizardMenu = M

-- The release that brings the step, and its place: after the sharing step and before the closing one.
M.SINCE, M.ORDER = "0.7.0", 77
M.STEP_ID, M.STEP2_ID = "menu", "menu2"
-- The groups of the first step; the others are in the second.
M.FIRST_STEP_GROUPS = 3

local GROUP_GAP, PAGE_INDENT, PAGE_COLUMNS = 6, 24, 2

ns.AddLocale("enUS", {
  ["setup.step.menu"] = "Menu areas",
  ["setup.step.menu.text"] = "Choose what the left menu shows. The arrow of an area opens its pages.",
  ["setup.step.menu2"] = "Menu areas, part 2",
  ["setup.step.menu2.text"] = "More areas of the left menu. What you switch off stays reachable through search.",
  ["setup.menu.count"] = "%d of %d",
  ["setup.menu.off"] = "off",
  ["setup.menu.pagesTip"] = "Show or hide the pages of this area.",
  ["setup.menu.expand"] = "Expand",
  ["setup.menu.collapse"] = "Collapse",
  ["setup.menu.pageCount"] = "Pages: %d",
  ["setup.menu.featureOff"] = "Feature off",
  ["setup.menu.fixed"] = "Not changed here: Start, Search and Settings.",
  ["setup.menu.scopeNotice"] = "This character has its own menu. Changes here apply to this character only.",
  ["setup.menu.pencilHint"] = "Hidden pages stay reachable through search and commands. The pencil at the top of the menu shows hidden areas again.",
  ["setup.menu.edit"] = "Edit menu",
  ["setup.menu.settingsHint"] = "More options for the menu are in the settings.",
  ["setup.menu.settings"] = "Settings",
  ["setup.menu.group.world"] = "Map, waypoints, dungeons and raids",
  ["setup.menu.group.character"] = "Your characters, gear and talents",
  ["setup.menu.group.social"] = "Guild and your contacts",
  ["setup.menu.group.learn"] = "Classes, trainers, levels, weapons",
  ["setup.menu.group.professions"] = "Recipes, routes, trainers, ores, vendors",
  ["setup.menu.group.inventory"] = "Loot and durability",
  ["setup.menu.group.tools"] = "Notes, macros, drawings and more",
  ["setup.menu.page.map"] = "Map with the route to any target",
  ["setup.menu.page.waypoints"] = "Your saved waypoints",
  ["setup.menu.page.instances"] = "Guides for dungeons and raids",
  ["setup.menu.page.chars"] = "List and sorting of your characters",
  ["setup.menu.page.inspect"] = "Look at the gear of other players",
  ["setup.menu.page.talents"] = "Talent trees and builds",
  ["setup.menu.page.legacy"] = "Planner for legacy points",
  ["setup.menu.page.guild"] = "Your guild at a glance",
  ["setup.menu.page.contacts"] = "Friends and players nearby",
  ["setup.menu.page.classes"] = "Overview of classes and races",
  ["setup.menu.page.trainers"] = "Where to learn your class spells",
  ["setup.menu.page.levels"] = "What each level brings",
  ["setup.menu.page.weapons"] = "Weapon skills and their trainers",
  ["setup.menu.page.professions"] = "Professions and their recipes",
  ["setup.menu.page.professionroute"] = "Route to level a profession",
  ["setup.menu.page.proftrainers"] = "Where to learn your professions",
  ["setup.menu.page.gathering"] = "Where ores and herbs grow",
  ["setup.menu.page.vendors"] = "Vendors for recipes and materials",
  ["setup.menu.page.loot"] = "Loot of bosses and dungeons",
  ["setup.menu.page.durability"] = "Wear of your equipment",
  ["setup.menu.page.macros"] = "Write and keep macros",
  ["setup.menu.page.notes"] = "Your notes in the game",
  ["setup.menu.page.drawings"] = "Your own drawings",
  ["setup.menu.page.shots"] = "Screenshots with their place",
  ["setup.menu.page.calc"] = "A calculator for game numbers",
  ["setup.menu.page.xpbar"] = "The window of the experience bar",
  ["setup.menu.page.cursor"] = "A ring around the mouse cursor",
  ["setup.menu.page.areas"] = "Your own HUD windows",
})
ns.AddLocale("deDE", {
  ["setup.step.menu"] = "Menü-Bereiche",
  ["setup.step.menu.text"] = "Wähle, was im linken Menü steht. Der Pfeil eines Bereichs öffnet seine Seiten.",
  ["setup.step.menu2"] = "Menü-Bereiche, Teil 2",
  ["setup.step.menu2.text"] = "Weitere Bereiche des linken Menüs. Was du ausschaltest, bleibt über die Suche erreichbar.",
  ["setup.menu.count"] = "%d von %d",
  ["setup.menu.off"] = "aus",
  ["setup.menu.pagesTip"] = "Seiten dieses Bereichs ein- oder ausklappen.",
  ["setup.menu.expand"] = "Aufklappen",
  ["setup.menu.collapse"] = "Zuklappen",
  ["setup.menu.pageCount"] = "Seiten: %d",
  ["setup.menu.featureOff"] = "Feature aus",
  ["setup.menu.fixed"] = "Hier nicht änderbar: Start, Suche und Einstellungen.",
  ["setup.menu.scopeNotice"] = "Dieser Charakter hat ein eigenes Menü. Änderungen gelten hier nur für ihn.",
  ["setup.menu.pencilHint"] = "Ausgeblendetes bleibt über Suche und Befehle erreichbar. Mit dem Stift oben im Menü blendest du Bereiche wieder ein.",
  ["setup.menu.edit"] = "Menü bearbeiten",
  ["setup.menu.settingsHint"] = "Weitere Einstellungen zum Menü findest du in den Einstellungen.",
  ["setup.menu.settings"] = "Einstellungen",
  ["setup.menu.group.world"] = "Karte, Wegpunkte, Instanzen und Raids",
  ["setup.menu.group.character"] = "Deine Charaktere, Ausrüstung, Talente",
  ["setup.menu.group.social"] = "Gilde und deine Kontakte",
  ["setup.menu.group.learn"] = "Klassen, Lehrer, Stufen, Waffen",
  ["setup.menu.group.professions"] = "Rezepte, Routen, Lehrer, Erze, Händler",
  ["setup.menu.group.inventory"] = "Beute und Haltbarkeit",
  ["setup.menu.group.tools"] = "Notizen, Makros, Zeichnungen und mehr",
  ["setup.menu.page.map"] = "Karte mit Route zu jedem Ziel",
  ["setup.menu.page.waypoints"] = "Deine gespeicherten Wegpunkte",
  ["setup.menu.page.instances"] = "Anleitungen für Instanzen und Raids",
  ["setup.menu.page.chars"] = "Liste und Sortierung deiner Charaktere",
  ["setup.menu.page.inspect"] = "Ausrüstung anderer Spieler ansehen",
  ["setup.menu.page.talents"] = "Talentbäume und Builds",
  ["setup.menu.page.legacy"] = "Planer für Vermächtnis-Punkte",
  ["setup.menu.page.guild"] = "Deine Gilde auf einen Blick",
  ["setup.menu.page.contacts"] = "Freunde und Spieler in der Nähe",
  ["setup.menu.page.classes"] = "Übersicht der Klassen und Rassen",
  ["setup.menu.page.trainers"] = "Wo du deine Klassenzauber lernst",
  ["setup.menu.page.levels"] = "Was jede Stufe bringt",
  ["setup.menu.page.weapons"] = "Waffenfertigkeiten und ihre Lehrer",
  ["setup.menu.page.professions"] = "Berufe und ihre Rezepte",
  ["setup.menu.page.professionroute"] = "Route zum Leveln eines Berufs",
  ["setup.menu.page.proftrainers"] = "Wo du Berufe lernst",
  ["setup.menu.page.gathering"] = "Wo Erze und Kräuter wachsen",
  ["setup.menu.page.vendors"] = "Händler für Rezepte und Material",
  ["setup.menu.page.loot"] = "Beute von Bossen und Dungeons",
  ["setup.menu.page.durability"] = "Haltbarkeit deiner Ausrüstung",
  ["setup.menu.page.macros"] = "Makros schreiben und aufbewahren",
  ["setup.menu.page.notes"] = "Deine Notizen im Spiel",
  ["setup.menu.page.drawings"] = "Deine eigenen Zeichnungen",
  ["setup.menu.page.shots"] = "Screenshots mit Ort",
  ["setup.menu.page.calc"] = "Ein Rechner für Spielwerte",
  ["setup.menu.page.xpbar"] = "Das Fenster der Erfahrungsleiste",
  ["setup.menu.page.cursor"] = "Ein Ring um den Mauszeiger",
  ["setup.menu.page.areas"] = "Deine eigenen HUD-Fenster",
})

-- State -----------------------------------------------------------------------------------------------

local function layout()
  return (NL.Layout())
end

-- The menu as the step offers it: the placeholder pages ("coming soon") are left out, so the counters and the
-- rows only speak of pages that exist.
local function offered()
  local base = NL.Base()
  local pages = {}
  for _, page in ipairs(base.pages) do
    if not page.placeholder then
      pages[#pages + 1] = page
    end
  end
  return { groups = base.groups, pages = pages }
end

-- The control of the step in the registry (the session compares it), a plain one when the step is not registered.
local function control()
  local step = SW.steps[M.STEP_ID]
  for _, c in ipairs(step and step.controls or {}) do
    if c.type == "menu" then
      return c
    end
  end
  return FL.MenuControl()
end

-- The groups with a row, in the order of the menu this character sees: { id, pages = { { id, page, hidden } } }.
-- A group that holds a protected page has no row. part 1 or 2: the groups of that step, nil: all.
function M.Groups(part)
  local base = offered()
  local out = {}
  for _, g in ipairs(NL.Resolve(base.groups, base.pages, layout(), true).groups) do
    if not g.locked and #g.pages > 0 then
      out[#out + 1] = g
    end
  end
  if part == nil then
    return out
  end
  local picked = {}
  for i, g in ipairs(out) do
    if (i <= M.FIRST_STEP_GROUPS) == (part == 1) then
      picked[#picked + 1] = g
    end
  end
  return picked
end

-- { total, visible, hidden, locked } of one group, counted over the pages the step offers.
function M.State(groupId)
  return NL.GroupState(layout(), offered(), groupId)
end

-- True while the group is in the menu: neither switched off nor without a page.
function M.GroupOn(groupId)
  local state = M.State(groupId)
  return state ~= nil and not state.hidden
end

-- The mark of the page itself, whatever its group does.
function M.PageOn(pageId)
  return not NL.PageHidden(layout(), pageId)
end

-- "3 of 4" while the group is in the menu, "off" otherwise.
function M.Counter(groupId)
  local state = M.State(groupId)
  if not state or state.hidden then
    return L["setup.menu.off"]
  end
  return string.format(L["setup.menu.count"], state.visible, state.total)
end

local function placeholderIds(groupId)
  local base = NL.Base()
  local out = {}
  for _, g in ipairs(NL.Resolve(base.groups, base.pages, layout(), true).groups) do
    if g.id == groupId then
      for _, e in ipairs(g.pages) do
        if e.page and e.page.placeholder then
          out[#out + 1] = e.id
        end
      end
    end
  end
  return out
end

local function followers(ops, groupId, hidden)
  for _, id in ipairs(placeholderIds(groupId)) do
    ops[#ops + 1] = { kind = "page", id = id, hidden = hidden }
  end
  return ops
end

local function write(ops)
  return SW.Put(control(), ops) == true
end

-- Switches a whole group. Off keeps the marks of its pages, on shows the group and, when every page was off,
-- all its pages. Returns whether the write was accepted (false for an unknown or protected group).
function M.SwitchGroup(groupId, on)
  local ops = NL.GroupSwitchOps(layout(), offered(), groupId, on == true)
  if not ops then
    return false
  end
  if on then
    followers(ops, groupId, false)
  end
  return write(ops)
end

local function groupOf(pageId)
  local base = offered()
  for _, g in ipairs(NL.Resolve(base.groups, base.pages, layout(), true).groups) do
    for _, e in ipairs(g.pages) do
      if e.id == pageId then
        return g, e
      end
    end
  end
end

-- Switches one page. A page switched on in a group that is off brings the group back. When the last page of a
-- group goes off, the placeholder pages of the group go with it, so the group leaves the menu.
function M.SwitchPage(pageId, on)
  local g, e = groupOf(pageId)
  if not g or e.protected or g.locked then
    return false
  end
  on = on == true
  local ops = { { kind = "page", id = pageId, hidden = not on } }
  local state = M.State(g.id)
  if on and state and state.flagged then
    ops[#ops + 1] = { kind = "group", id = g.id, hidden = false }
  end
  local delta = (on and not e.hidden and 0) or (on and 1) or (e.hidden and 0) or -1
  if state and state.visible + delta == 0 then
    followers(ops, g.id, true)
  else
    followers(ops, g.id, false)
  end
  return write(ops)
end

-- True when a feature of the earlier steps keeps this page out of the menu: the page is hidden and the switch of
-- that feature is off (a feature that is only a menu entry does not count, its row says "menu").
function M.FeatureOff(pageId)
  if NL.PageHidden(layout(), pageId) == false then
    return false
  end
  for _, id in ipairs(ns.SetupFeatureData.ORDER) do
    local def = FL.Row(id)
    if def.switch.kind ~= "menu" and FL.HasSwitch(id) and FL.Available(id) then
      for _, page in ipairs(def.pages) do
        if page == pageId then
          return not FL.IsOn(id)
        end
      end
    end
  end
  return false
end

-- The menu in the shape of the rows: a text that changes when the structure (groups, pages, their order) does.
local function signature(part)
  local parts = {}
  for _, g in ipairs(M.Groups(part)) do
    local ids = {}
    for _, e in ipairs(g.pages) do
      ids[#ids + 1] = e.id
    end
    parts[#parts + 1] = g.id .. "=" .. table.concat(ids, ",")
  end
  return table.concat(parts, ";")
end

-- Window ----------------------------------------------------------------------------------------------

local boxes = {}

local function refreshWindow()
  if UI and UI.Refresh then
    UI.Refresh()
  end
end

local function hasText(key)
  return ns.Locales.enUS[key] ~= nil
end

-- One line of text that can come and go (a frame, so the stack skips it while hidden).
local function noteLine(view, key, color, shownFn)
  local line = CreateFrame("Frame", nil, view.area.content)
  line.text = W.Text(line, { key = key, role = "micro", color = color, wrap = true })
  line.text:SetPoint("TOPLEFT")
  function line:Refresh()
    local on = shownFn == nil or shownFn()
    if on ~= self:IsShown() then
      self:SetShown(on)
      view.relayout = true
    end
  end
  function line:fgGridLayout(width)
    self.text:SetWidth(math.max(40, width))
    local h = self.text:GetStringHeight() + 2
    self:SetHeight(h)
    return h
  end
  line:SetShown(shownFn == nil or shownFn())
  view.stack:Add(line, { gap = 8 })
  view.widgets[#view.widgets + 1] = line
  view.rows[#view.rows + 1] = line
  return line
end

-- The icon the left menu shows for this page, nil when the page has none (the row keeps the room).
local function pageIcon(page)
  if not page.icon then
    return nil
  end
  return ns.ResolveIcon(page.icon, ns.ICONS_FALLBACK[page.id])
end

local function pageRow(parent, e)
  local id = e.id
  local spec = {
    iconSlot = true,
    icon = pageIcon(e.page),
    id = "menu-page-" .. id,
    nameKey = e.page.title,
    textKey = hasText("setup.menu.page." .. id) and ("setup.menu.page." .. id) or nil,
    compact = true,
    switch = {
      get = function()
        return M.PageOn(id)
      end,
      set = function(on)
        M.SwitchPage(id, on)
      end,
    },
    badge = function()
      return M.FeatureOff(id) and L["setup.menu.featureOff"] or ""
    end,
  }
  return R.Row(parent, spec)
end

local function groupRow(box, g)
  local id = g.id
  local row
  -- Same arrow language as the group headers of the left menu: ">" closed, "v" open.
  local function arrow()
    row.button:SetIcon(box.open[id] and "chevron-down" or "chevron-right")
  end
  local function tip()
    local open = box.open[id] == true
    local title = L[open and "setup.menu.collapse" or "setup.menu.expand"]
    local count = string.format(L["setup.menu.pageCount"], #g.pages)
    return title, count, L["nav.group." .. id] .. ": " .. title .. ", " .. count
  end
  row = R.Row(box, {
    id = "menu-" .. id,
    nameKey = "nav.group." .. id,
    textKey = hasText("setup.menu.group." .. id) and ("setup.menu.group." .. id) or nil,
    switch = {
      get = function()
        return M.GroupOn(id)
      end,
      set = function(on)
        M.SwitchGroup(id, on)
      end,
    },
    badge = function()
      return M.Counter(id)
    end,
    optionsShown = function()
      return box.open[id] == true
    end,
    columns = PAGE_COLUMNS,
    onRelayout = function()
      box.view.relayout = true
    end,
    button = {
      icon = "chevron-right",
      boxed = true,
      tooltip = "setup.menu.pagesTip",
      tip = tip,
      hitBadge = true,
      onClick = function()
        box:Toggle(id)
      end,
      arrow = function(step)
        box:SetOpen(id, step > 0)
      end,
    },
  })
  for _, e in ipairs(g.pages) do
    local page = pageRow(row, e)
    row:AddOption(page, PAGE_INDENT)
  end
  row.paintArrow = arrow
  arrow()
  return row
end

-- The container of all group rows: it lays them out itself and builds them again when the structure of the
-- menu changed (a page moved to another group in the pencil mode while the window was folded).
local function newBox(view, part)
  local box = CreateFrame("Frame", nil, view.area.content)
  box.fgId = "wizard-menu-" .. part
  box.view, box.part, box.open, box.rows = view, part, {}, {}

  function box:Build()
    self.signature = signature(part)
    for _, g in ipairs(M.Groups(part)) do
      self.rows[#self.rows + 1] = groupRow(self, g)
    end
    self.paint = nil
  end

  -- One group is open at a time: opening a group folds the open one in.
  function box:SetOpen(id, on)
    for key in pairs(self.open) do
      self.open[key] = nil
    end
    self.open[id] = on or nil
    for _, row in ipairs(self.rows) do
      row:Refresh()
      row.paintArrow()
    end
    view.relayout = true
    refreshWindow()
  end

  function box:Toggle(id)
    self:SetOpen(id, self.open[id] ~= true)
  end

  -- A comparable text of what the rows show, to tell whether the layout has to run again.
  local function painted(self)
    local parts = {}
    for _, row in ipairs(self.rows) do
      parts[#parts + 1] = row.badge:GetText() .. (row.optionsOn and "+" or "-")
      for _, option in ipairs(row.options) do
        parts[#parts + 1] = option.frame.badge:GetText()
      end
    end
    return table.concat(parts, "|")
  end

  function box:Refresh()
    if signature(part) ~= self.signature then
      for _, row in ipairs(self.rows) do
        row:Hide()
      end
      self.rows = {}
      self:Build()
      view.relayout = true
    end
    for _, row in ipairs(self.rows) do
      row:Refresh()
    end
    local now = painted(self)
    if now ~= self.paint then
      self.paint = now
      view.relayout = true
    end
  end

  -- The height is the height of the closed rows plus the largest group that can fold out, so the block stays as
  -- tall when a group opens or closes.
  function box:fgGridLayout(width)
    local closedTotal, extra = 0, 0
    for _, row in ipairs(self.rows) do
      row:SetWidth(width)
      row.reserve = true
      local open = row:fgGridLayout(width)
      row.reserve = false
      local closed = row:fgGridLayout(width)
      row.reserve = nil
      extra = math.max(extra, open - closed)
      closedTotal = closedTotal + closed + GROUP_GAP
    end
    local y = 0
    for _, row in ipairs(self.rows) do
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      y = y + row:fgGridLayout(width) + GROUP_GAP
    end
    local total = math.max(0, math.max(y, closedTotal + extra) - GROUP_GAP)
    self:SetHeight(math.max(1, total))
    return total
  end

  box:Build()
  box:Refresh()
  return box
end

local function editMenu()
  local SE = ns.SidebarEdit
  if SE and (SE.Enter() or SE.IsEditing()) then
    UI.Reveal()
  end
end

local function openSettings()
  if ns.SettingsPage.Select("menu", "menu.main") then
    ns.Main.Show("settings")
    UI.Reveal()
  end
end

-- Block "menu": the group rows of the step (step.menuPart, 1 or 2). The first step also has the pencil line, the
-- notice for a character with its own menu and the way back (the pencil in the menu, the settings), the second
-- the note about the entries that cannot be changed.
local function build(view, step)
  if not FL.MenuAvailable() then
    return
  end
  local part = step.menuPart or 1
  if part == 1 then
    R.PencilLine(view)
  end
  local box = newBox(view, part)
  view.menu = box
  view.stack:Add(box, { gap = 10 })
  view.widgets[#view.widgets + 1] = box
  view.rows[#view.rows + 1] = box
  boxes[part] = box
  if part == 2 then
    noteLine(view, "setup.menu.fixed", "textMuted")
    return
  end
  noteLine(view, "setup.menu.scopeNotice", "warning", function()
    return NL.HasCharLayout()
  end)
  UI.AddRow(view, { key = "setup.menu.pencilHint" }, "setup.menu.edit", editMenu, nil, { width = 130 })
  UI.AddRow(view, { key = "setup.menu.settingsHint" }, "setup.menu.settings", openSettings, nil, {
    width = 130,
    opens = true,
  })
end

UI.RegisterBlock("menu", build)

-- The menu changed elsewhere (the pencil mode, the settings): the rows follow.
ns.On("FG_NAV_CHANGED", function()
  local any = false
  for _, box in pairs(boxes) do
    box:Refresh()
    any = true
  end
  if any then
    refreshWindow()
  end
end)

SW.RegisterStep({
  id = M.STEP_ID,
  order = M.ORDER,
  titleKey = "setup.step.menu",
  textKey = "setup.step.menu.text",
  since = M.SINCE,
  when = FL.MenuAvailable,
  layout = { "title", "text", "menu" },
  menuPart = 1,
  controls = { FL.MenuControl() },
})

-- The second half has no control of its own (the control of the first step covers the whole menu).
SW.RegisterStep({
  id = M.STEP2_ID,
  order = M.ORDER + 1,
  titleKey = "setup.step.menu2",
  textKey = "setup.step.menu2.text",
  since = M.SINCE,
  when = function()
    return FL.MenuAvailable() and #M.Groups(2) > 0
  end,
  layout = { "title", "text", "menu" },
  menuPart = 2,
  controls = {},
})
