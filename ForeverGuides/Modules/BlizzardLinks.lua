-- Buttons next to Blizzard's spellbook, talent and professions windows that open
-- the addon's learn list, talent editor and professions area, and at the side of
-- the character window to open the character and export page.
--
-- Spellbook and talents: side tabs (B.CreateSideTab, like the world map and the
-- flight window) hang at the right edge of PlayerSpellsFrame, one below the other,
-- parented to the sub-view so they show only with it. They never touch the
-- header strip, which Blizzard rebuilds on every spell update. The "L" tab is a
-- real tab: it shows ns.SpellbookPanel (the learn list on the book's parchment),
-- Blizzard's own tabs deselect it again. It sits in the category row of the book
-- (behind the last tab of CategoryTabSystem, same size and gap, anchored to that
-- frame); only without that row it stays a side tab. The "T" tab stays at the edge. Professions: one side tab in the column
-- of the professions window, made from Blizzard's LargeSideTabButtonTemplate when
-- it exists. Character window: a side tab behind the last of its mode tabs
-- (CharacterFrame.ModeTabs), the same way; a right click opens a small menu.
-- When a window lacks the expected structure, the geometry of its side column is
-- measured instead, and fixed offsets from the window corner are used when even
-- that finds nothing.
--
-- Our side tabs always sit at the END of the column, whichever addon loaded first:
-- they move behind the last foreign tab only when one overlaps them, so two
-- addons that both want the last slot never fight. Near the screen edge the
-- engine clamps them back onto the screen.
-- Frames are looked up by name (they are load-on-demand), then by structure
-- (ns.BlizzardScan); B.Report() says how each was found. Nothing here writes
-- fields onto Blizzard frames or calls secure code: only method calls, HookScript
-- and hooksecurefunc.
local _, ns = ...
local W, L = ns.W, ns.L
local Scan = ns.BlizzardScan

ns.AddLocale("enUS", {
  ["blizz.learn"] = "Forever Guides: Learn list",
  ["blizz.learn.tip"] = "Opens the learn list: what you can learn right now.",
  ["blizz.talents"] = "Forever Guides: Talent editor",
  ["blizz.talents.tip"] = "Opens the talent editor with import, loading from the game and applying.",
  ["blizz.professions"] = "Forever Guides: Professions",
  ["blizz.professions.tip"] = "Opens the professions area of the addon.",
  ["blizz.character"] = "Forever Guides: Open character & export",
  ["blizz.character.tip"] = "Right click: item level settings and settings.",
  ["blizz.character.menu.itemlevel"] = "Item level settings",
  ["blizz.character.menu.settings"] = "Settings",
  ["blizz.set.character"] = "Button in the character window",
  ["blizz.lfg"] = "Filter",
  ["blizz.lfg.tip"] = "Group finder filter by Forever Guides.",
})

ns.AddLocale("deDE", {
  ["blizz.learn"] = "Forever Guides: Lernliste",
  ["blizz.learn.tip"] = "Öffnet die Lernliste: was du jetzt lernen kannst.",
  ["blizz.talents"] = "Forever Guides: Talent-Editor",
  ["blizz.talents.tip"] = "Öffnet den Talent-Editor mit Import, Laden aus dem Spiel und Anwenden.",
  ["blizz.professions"] = "Forever Guides: Berufe",
  ["blizz.professions.tip"] = "Öffnet den Berufe-Bereich des Addons.",
  ["blizz.character"] = "Forever Guides: Charakter & Export öffnen",
  ["blizz.character.tip"] = "Rechtsklick: Itemlevel-Einstellungen und Einstellungen.",
  ["blizz.character.menu.itemlevel"] = "Itemlevel-Einstellungen",
  ["blizz.character.menu.settings"] = "Einstellungen",
  ["blizz.set.character"] = "Knopf im Charakterfenster",
  ["blizz.lfg"] = "Filter",
  ["blizz.lfg.tip"] = "Gruppensuche-Filter von Forever Guides.",
})

local B = {}
ns.BlizzardLinks = B

local LOGO = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png"
local TAB_SIZE = 52 -- every addon side tab, as big as the professions tabs
local LOGO_SIZE = TAB_SIZE - 8 -- logo of the drawn tab
local TAB_TEMPLATE = "LargeSideTabButtonTemplate"
local SIDE_INSET = 4 -- side tab: outside the right edge
local SIDE_DROP = 40 -- below the title bar
local SIDE_GAP = 2 -- between stacked side tabs, as in the professions window
local LEVEL_BOOST = 50 -- above the view; also lifted over the busiest sibling frame
local LEVEL_CAP = 9990
local SIBLING_LEAD = 10
local OPEN_STRATA = "FULLSCREEN_DIALOG"
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local OPEN_RANK = 7
local DEFAULT_GAP = 6
local GAP_MIN, GAP_MAX = -8, 40
local STRIP_DEPTH = 110 -- header strip: tab top lies at most this far below the window top
local ROW_TOLERANCE = 3 -- tabs of one row or column differ at most this much in centre
local COLUMN_INSET = 20 -- side tabs start at most this far inside the right window edge
local COLUMN_REACH = 80 -- and at most this far outside it
local SCAN_DEPTH = 2
local SCAN_LIMIT = 400
local PANEL_DROP = 5 -- the spellbook panel sits this far below the buttons, above Blizzard's content
local TOUCH = 0.5 -- edges closer than this count as touching
local DEPENDENCY_DEPTH = 8
local LATE_DELAY = 0.5 -- other addons add their tabs shortly after a view shows
local RETRY_DELAY = 0.1 -- Blizzard fires "show" before it has rebuilt its tabs
local ENUMERATE_RUNS = 3 -- how often the last-resort frame walk may run
local TAB_GLOW = "Interface\\Buttons\\CheckButtonHilight"
local TEMPLATE_TAB = "ForeverGuidesProfessionsTab"
local MENU_NAME = "ForeverGuidesCharacterMenu"
local MENU_WIDTH, MENU_ROW = 190, 22
local MENU_STRATA = "TOOLTIP"
local BLOCKER_STRATA = "FULLSCREEN"
local IDS = { "spellbook", "talents", "professions", "character", "lfg" }
-- Fields of the views that may hold the tabs (frame with children or plain array).
local TAB_FIELDS = { "TabSystem", "CategoryTabSystem", "SpecTabs", "ProfessionTabs", "tabs" }

-- tag names the button in the diagnostic report (L = learn list, T = talents). action: a click runs this
-- function instead of opening a page.
local LINKS = {
  levels = { key = "blizz.learn", tip = "blizz.learn.tip", route = "levels", tag = "L", panel = true },
  talents = { key = "blizz.talents", tip = "blizz.talents.tip", route = "talents", tag = "T" },
  professions = { key = "blizz.professions", tip = "blizz.professions.tip", route = "professions", tag = "B" },
  -- menu: a right click opens the small menu instead of the page.
  character = {
    key = "blizz.character",
    tip = "blizz.character.tip",
    route = "character",
    tag = "C",
    menu = true,
    frameName = "ForeverGuidesCharacterTab",
  },
  lfg = {
    key = "blizz.lfg",
    tip = "blizz.lfg.tip",
    tag = "F",
    action = function()
      if ns.LfgFilterPanel then
        ns.LfgFilterPanel.Toggle()
      end
    end,
  },
}

local BOTTOM_SIDES = { BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

-- Spellbook and talent views: the buttons of one view are stacked at the right
-- edge of the window (layoutSide). min/max bound the size of a foreign side tab.
local SIDE_VIEW = { side = true, flow = "column", min = { 30, 30 }, max = { 64, 64 } }

-- Look of the other views. min/max bound the size of a Blizzard tab, fallback is
-- the button size without a discovered column. Offsets reproduce the measured spot
-- of the next tab slot from the TOPLEFT of root: point is the button anchor, x/y
-- its position, step the distance to the next slot. chain describes the structural
-- anchoring: the tab fields of the window, the buttons sit at point/relPoint with
-- the offset dx/dy, sides are the points of a member that count as "behind it".
-- Side tabs hang at the right edge of the professions window, one below the other.
local PROFESSION_VIEW = {
  style = "icon",
  flow = "column",
  min = { 30, 30 },
  max = { 64, 64 },
  fallback = { TAB_SIZE, TAB_SIZE },
  point = "CENTER",
  origin = "TOPRIGHT",
  x = 31,
  y = -373,
  step = 0,
  chain = {
    firstField = "ProfessionsOverviewTab",
    listField = "rightProfessionTabs",
    refresh = "RefreshRightTabs",
    deselect = "RightTabSelected",
    template = TAB_TEMPLATE,
    sides = BOTTOM_SIDES,
    size = { TAB_SIZE, TAB_SIZE },
    point = "TOPLEFT",
    relPoint = "BOTTOMLEFT",
    dx = 0,
    dy = -2,
    flow = "column",
  },
}

-- The character window keeps its mode tabs in CharacterFrame.ModeTabs.Tabs (the
-- same side tabs as the professions window, hanging at its right edge). Without
-- them the button sits at the top of the right edge, outside the window: the
-- sidebar tabs of the paper doll lie inside it and are never taken for side tabs.
local CHARACTER_VIEW = {
  style = "icon",
  flow = "column",
  min = { 30, 30 },
  max = { 64, 64 },
  fallback = { TAB_SIZE, TAB_SIZE },
  point = "CENTER",
  origin = "TOPRIGHT",
  x = 31,
  y = -56,
  step = 0,
  skip = { "PaperDollSidebarTabs" },
  chain = {
    firstField = "ModeTabs.CharacterTab",
    listField = "ModeTabs.Tabs",
    refresh = "UpdateTabLayout",
    template = TAB_TEMPLATE,
    sides = BOTTOM_SIDES,
    size = { TAB_SIZE, TAB_SIZE },
    point = "TOPLEFT",
    relPoint = "BOTTOMLEFT",
    dx = 0,
    dy = -2,
    flow = "column",
  },
}

-- Per area the first candidate that exists wins. parent is the sub-view that
-- hosts the buttons (they follow its visibility, so the spellbook buttons never
-- show on the talent tab). root is the window the header belongs to. links run
-- from left to right. Retail 11.x keeps both areas inside PlayerSpellsFrame,
-- older clients use separate frames.
local TARGETS = {
  {
    id = "spellbook",
    parent = "PlayerSpellsFrame.SpellBookFrame",
    root = "PlayerSpellsFrame",
    view = SIDE_VIEW,
    links = { "levels", "talents" },
  },
  { id = "spellbook", parent = "SpellBookFrame", view = SIDE_VIEW, links = { "levels", "talents" } },
  {
    id = "talents",
    parent = "PlayerSpellsFrame.TalentsFrame",
    root = "PlayerSpellsFrame",
    view = SIDE_VIEW,
    links = { "talents" },
  },
  { id = "talents", parent = "ClassTalentFrame", view = SIDE_VIEW, links = { "talents" } },
  { id = "talents", parent = "PlayerTalentFrame", view = SIDE_VIEW, links = { "talents" } },
  { id = "talents", parent = "TalentFrame", view = SIDE_VIEW, links = { "talents" } },
  { id = "professions", parent = "ProfessionsFrame", view = PROFESSION_VIEW, links = { "professions" } },
  { id = "professions", parent = "ProfessionsBookFrame", view = PROFESSION_VIEW, links = { "professions" } },
  { id = "professions", parent = "SpellBookProfessionFrame", view = PROFESSION_VIEW, links = { "professions" } },
  {
    id = "character",
    parent = "CharacterFrame",
    view = CHARACTER_VIEW,
    links = { "character" },
    setting = "characterButton",
  },
  -- Blizzard's three tabs hang at the right edge; ours joins the column behind them (reflowSide).
  {
    id = "lfg",
    parent = "LFGParentFrame",
    view = SIDE_VIEW,
    links = { "lfg" },
    setting = "lfgPanel",
    -- The docked filter panel carries the column of side tabs at its right edge.
    edge = function()
      local dock = ns.LfgPanelDock
      return dock and dock.DockFrame()
    end,
  },
}

-- Structural fallback: kind -> what to attach when found by ns.BlizzardScan.
local STRUCTURAL = {
  spellbook = { view = SIDE_VIEW, links = { "levels", "talents" } },
  professions = { view = PROFESSION_VIEW, links = { "professions" } },
}
local STRUCTURAL_ORDER = { "spellbook", "professions" }

-- Callbacks of Blizzard's EventRegistry (language independent, they fire before
-- the load-on-demand addon is even known by name). kind: how B.OnEvent reacts.
local EVENTS = {
  ["PlayerSpellsFrame.SpellBookFrame.Show"] = "show",
  ["PlayerSpellsFrame.SpellBookFrame.Hide"] = "hide",
  ["PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged"] = "changed",
  ["PlayerSpellsFrame.TalentTab.Show"] = "show",
  ["ProfessionsFrame.Show"] = "show",
}

local attached = {}
local hooked = {}
local tabHooked = setmetatable({}, { __mode = "k" })
local methodHooked = setmetatable({}, { __mode = "k" })
local ours = {}
local pending = false
-- Windows found by structure, by kind; only used when no known name matches.
local scanned = {}
local enumerations = 0
local eventsRegistered = 0
local eventOwner = {}
-- What reached our buttons, shown by B.Report() to tell "mouse never arrives"
-- from "click arrives but the window opens out of sight".
local stats = { hover = 0, down = 0, click = 0, moved = 0, last = "none" }
-- Main window strata raised for a Blizzard view, restored when that view hides.
local raised
local restoreHooked = {}

-- Global or dotted path to a frame, nil when any step is missing.
local function resolve(path)
  local node = _G
  for part in path:gmatch("[^.]+") do
    if type(node) ~= "table" then
      return nil
    end
    local ok, value = pcall(function()
      return node[part]
    end)
    node = ok and value or nil
  end
  if type(node) == "table" and type(node.HookScript) == "function" then
    return node
  end
  return nil
end

local function isFrame(value)
  return type(value) == "table" and type(value.GetChildren) == "function" and type(value.GetWidth) == "function"
end

local function childrenOf(frame)
  local ok, list = pcall(function()
    return { frame:GetChildren() }
  end)
  return ok and list or {}
end

-- name may be a dotted path ("ModeTabs.Tabs"); any missing step gives nil.
local function field(frame, name)
  local node = frame
  for part in name:gmatch("[^.]+") do
    local ok, value = pcall(function()
      return node[part]
    end)
    if not ok or not value then
      return nil
    end
    node = value
  end
  return node
end

local function enabled(key)
  local s = ns.db and ns.db.settings
  return not s or s[key] ~= false
end

local function number(frame, method)
  local ok, value = pcall(frame[method], frame)
  return ok and type(value) == "number" and value or nil
end

local function visible(frame)
  local ok, value = pcall(frame.IsVisible, frame)
  return ok and value == true
end

local function shown(frame)
  local ok, value = pcall(frame.IsShown, frame)
  return ok and value == true
end

local function nameOf(frame)
  return Scan.Call(frame, "GetName") or "(unnamed)"
end

-- Marks a frame and everything below it as ours, so the tab scan never takes
-- our panel or its widgets for foreign tabs.
local function markOurs(frame)
  if ours[frame] then
    return
  end
  ours[frame] = true
  for _, child in ipairs(childrenOf(frame)) do
    markOurs(child)
  end
end

-- These buttons live on Blizzard frames, so Tab inside our window must not reach them.
local function leaveFocusRing(button)
  local list = ns.Focus and ns.Focus.items
  for i = #(list or {}), 1, -1 do
    if list[i] == button then
      table.remove(list, i)
    end
  end
end

-- hooksecurefunc on a method of a Blizzard frame, once per object and method.
local function hookMethod(object, method, fn)
  if type(hooksecurefunc) ~= "function" or type(object) ~= "table" or type(field(object, method)) ~= "function" then
    return
  end
  local done = methodHooked[object]
  if not done then
    done = {}
    methodHooked[object] = done
  end
  if not done[method] then
    done[method] = true
    pcall(hooksecurefunc, object, method, fn)
  end
end

local function strataRank(frame)
  local ok, name = pcall(frame.GetFrameStrata, frame)
  for i, candidate in ipairs(STRATA) do
    if ok and candidate == name then
      return i
    end
  end
  return nil
end

local function restoreStrata()
  if raised then
    pcall(raised.frame.SetFrameStrata, raised.frame, raised.strata)
    raised = nil
  end
end

-- Our window must not open behind the Blizzard view it was opened from: lift it
-- above that view's strata and give it back when the view hides.
local function raiseMain(window)
  local frame = ns.Main and ns.Main.frame
  if not frame then
    return
  end
  pcall(frame.Raise, frame)
  local windowRank, mainRank = strataRank(window), strataRank(frame)
  if not (windowRank and mainRank) or mainRank > windowRank then
    return
  end
  raised = { frame = frame, strata = STRATA[mainRank] }
  frame:SetFrameStrata(windowRank < OPEN_RANK and OPEN_STRATA or "TOOLTIP")
  pcall(frame.Raise, frame)
  if not restoreHooked[window] then
    restoreHooked[window] = true
    pcall(window.HookScript, window, "OnHide", restoreStrata)
  end
end

-- Shared with the world map integration (WorldMapLinks.lua).
B.RaiseMain = raiseMain
B.LeaveFocusRing = leaveFocusRing

local function openPage(link, window)
  stats.click = stats.click + 1
  stats.last = link.route
  if ns.Main and ns.Main.Show then
    ns.Main.Show(link.route)
    raiseMain(window)
  end
end

-- Small menu of the character button (right click): each row opens a page of
-- the addon. Only our own frames; Esc closes it like any other panel.
local menu

local function closeMenu()
  if menu then
    menu.frame:Hide()
    menu.blocker:Hide()
  end
end

local function buildMenu()
  local blocker = CreateFrame("Button", nil, UIParent)
  blocker:SetAllPoints(UIParent)
  blocker:SetFrameStrata(BLOCKER_STRATA)
  blocker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  blocker:SetScript("OnClick", closeMenu)
  blocker:Hide()
  local frame = CreateFrame("Frame", MENU_NAME, UIParent)
  frame:SetFrameStrata(MENU_STRATA)
  frame:SetClampedToScreen(true)
  W.Fill(frame, "surface", 1)
  W.Border(frame, "accentDim", 1)
  frame:SetScript("OnHide", closeMenu)
  frame:Hide()
  ns.WindowShell.RegisterEsc(frame)
  menu = { frame = frame, blocker = blocker, rows = {} }
end

local function menuRow(index)
  local row = menu.rows[index]
  if row then
    return row
  end
  row = CreateFrame("Button", nil, menu.frame)
  row:SetHeight(MENU_ROW)
  row:EnableMouse(true)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints()
  row.hl:SetColorTexture(1, 1, 1, 0)
  row.text = W.Text(row, { role = "ui" })
  row.text:SetPoint("LEFT", 8, 0)
  row:SetScript("OnEnter", function()
    row.hl:SetColorTexture(1, 1, 1, 0.08)
  end)
  row:SetScript("OnLeave", function()
    row.hl:SetColorTexture(1, 1, 1, 0)
  end)
  menu.rows[index] = row
  return row
end

local function openMenu(anchor, window)
  stats.click = stats.click + 1
  stats.last = "character menu"
  if not menu then
    buildMenu()
  end
  if menu.frame:IsShown() then
    return closeMenu()
  end
  local entries = {}
  if ns.ItemLevelOverlay then
    entries[#entries + 1] = "blizz.character.menu.itemlevel"
  end
  entries[#entries + 1] = "blizz.character.menu.settings"
  for _, row in ipairs(menu.rows) do
    row:Hide()
  end
  for i, key in ipairs(entries) do
    local row = menuRow(i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * MENU_ROW)
    row:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * MENU_ROW)
    row.text:SetText(L[key])
    row:SetScript("OnClick", function()
      closeMenu()
      if ns.Main and ns.Main.Show then
        ns.Main.Show("settings")
        raiseMain(window)
      end
    end)
    row:Show()
  end
  menu.frame:SetSize(MENU_WIDTH, #entries * MENU_ROW + 2)
  menu.frame:ClearAllPoints()
  menu.frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 0)
  menu.blocker:Show()
  menu.frame:Show()
  if not menu.hooked then
    menu.hooked = true
    pcall(window.HookScript, window, "OnHide", closeMenu)
  end
end

local function onClick(link, window)
  return function()
    openPage(link, window)
  end
end

-- Buttons -----------------------------------------------------------------

local function finishButton(parent, button)
  ours[button] = true
  leaveFocusRing(button)
  button:SetFrameLevel(math.min(parent:GetFrameLevel() + LEVEL_BOOST, LEVEL_CAP))
  button:EnableMouse(true)
  button:SetHitRectInsets(0, 0, 0, 0)
  button:RegisterForClicks("LeftButtonUp")
  button:HookScript("OnEnter", function()
    stats.hover = stats.hover + 1
  end)
  button:HookScript("OnMouseDown", function()
    stats.down = stats.down + 1
  end)
end

-- Selected look of a tab button through fgSetSelected(on): a gold border and the
-- stock glow texture.
local function decorateTab(button)
  local selected, hovering = false, false
  local border = W.Border(button, "accent2", 1, 2)
  local glow = button:CreateTexture(nil, "OVERLAY")
  glow:SetAllPoints()
  glow:SetTexture(TAB_GLOW)
  glow:SetBlendMode("ADD")
  local function paint()
    border.show(selected)
    glow:SetAlpha(selected and 1 or (hovering and 0.5 or 0))
  end
  function button:fgSetSelected(on)
    selected = on == true
    self.fgSelected = selected
    paint()
  end
  button:HookScript("OnEnter", function()
    hovering = true
    paint()
  end)
  button:HookScript("OnLeave", function()
    hovering = false
    paint()
  end)
  paint()
end

-- Drawn stand-in of the template tab: same size, dark tile, logo on it, gold frame when selected.
local function makeIconButton(parent, link, window, handler)
  local button = W.Action(parent, {
    texture = LOGO,
    size = TAB_SIZE,
    tooltip = link.key,
    tooltipText = link.tip,
    onClick = handler or onClick(link, window),
  })
  finishButton(parent, button)
  W.Fill(button, "bg", 0.85)
  -- A lone CENTER anchor leaves the texture at the native file size: set the size explicitly.
  button.icon:ClearAllPoints()
  button.icon:SetSize(LOGO_SIZE, LOGO_SIZE)
  button.icon:SetPoint("CENTER")
  button.icon:SetTexCoord(0, 1, 0, 1)
  return button
end

-- Side tab made from Blizzard's own template (look and size of the real ones).
-- Returns nil when the template or one of its methods is missing, the caller
-- then uses a plain button. handler(tab, mouse) replaces the default page opening;
-- name nil makes an anonymous frame.
local function makeTemplateTab(parent, link, window, template, handler, name)
  local ok, tab = pcall(CreateFrame, "Frame", name, parent, template)
  if not ok or type(tab) ~= "table" then
    return nil
  end
  ours[tab] = true
  if type(tab.Icon) ~= "table" or type(tab.SetCustomOnMouseUpHandler) ~= "function" then
    pcall(tab.Hide, tab)
    return nil
  end
  if type(tab.SetFillToInterior) == "function" then
    tab:SetFillToInterior(true)
  end
  tab.Icon:SetTexture(LOGO)
  tab:SetCustomOnMouseUpHandler(function(_, mouse, upInside)
    if upInside and handler then
      handler(tab, mouse)
    elseif upInside and link.menu and mouse == "RightButton" then
      openMenu(tab, window)
    elseif upInside then
      openPage(link, window)
    end
    -- Stays checked only while its panel is open (fgSetSelected).
    if type(tab.SetChecked) == "function" then
      tab:SetChecked(tab.fgSelected == true)
    end
  end)
  function tab:fgSetSelected(on)
    self.fgSelected = on == true
    if type(self.SetChecked) == "function" then
      self:SetChecked(self.fgSelected)
    end
  end
  tab:HookScript("OnEnter", function(self)
    stats.hover = stats.hover + 1
    ns.ShowTooltip(self, L[link.key], L[link.tip])
  end)
  tab:HookScript("OnMouseDown", function()
    stats.down = stats.down + 1
  end)
  tab:HookScript("OnLeave", ns.HideTooltip)
  tab.fgTemplate = true
  return tab
end

-- The one side tab of the addon for windows we do not own (world map, flight window, spellbook,
-- talents): the same Blizzard template and logo as the professions tab, a drawn copy of it without
-- the template. Tooltip "Forever Guides: <area>" plus a short line. opts: key, tip (locale keys),
-- onClick, and the anchor (point, rel, relPoint, x, y). fgSetSelected(on) marks it as selected.
function B.CreateSideTab(parent, opts)
  local link = { key = opts.key, tip = opts.tip }
  local button = makeTemplateTab(parent, link, parent, TAB_TEMPLATE, opts.onClick)
  if button then
    button:SetFrameLevel(math.min(parent:GetFrameLevel() + LEVEL_BOOST, LEVEL_CAP))
  else
    button = makeIconButton(parent, link, parent, opts.onClick)
    decorateTab(button)
  end
  button:SetPoint(opts.point or "TOPLEFT", opts.rel or parent, opts.relPoint or "TOPRIGHT", opts.x or 0, opts.y or 0)
  return button
end

-- Tab discovery (geometry) ---------------------------------------------------

local function gather(frame, depth, out, seen)
  if depth < 1 then
    return
  end
  for _, child in ipairs(childrenOf(frame)) do
    if #out >= SCAN_LIMIT then
      return
    end
    if isFrame(child) and not seen[child] then
      seen[child] = true
      out[#out + 1] = child
      gather(child, depth - 1, out, seen)
    end
  end
end

local function candidates(bases)
  local out, seen = {}, {}
  for _, base in ipairs(bases) do
    gather(base, SCAN_DEPTH, out, seen)
    for _, name in ipairs(TAB_FIELDS) do
      local value = field(base, name)
      if isFrame(value) then
        if not seen[value] then
          seen[value] = true
          out[#out + 1] = value
        end
        gather(value, 1, out, seen)
      elseif type(value) == "table" then
        for _, item in pairs(value) do
          if isFrame(item) and not seen[item] then
            seen[item] = true
            out[#out + 1] = item
          end
        end
      end
    end
  end
  return out
end

-- True for the frames of a view's skip list (by global name) and what lies
-- directly below them: they sit inside the window and are no side tabs.
local function skipped(view, frame)
  for _, name in ipairs(view.skip or {}) do
    local area = resolve(name)
    local node = frame
    for _ = 1, 3 do
      if not node then
        break
      elseif node == area then
        return true
      end
      local ok, parent = pcall(node.GetParent, node)
      node = ok and parent or nil
    end
  end
  return false
end

-- Geometry of a visible frame of tab size, or nil. A row lies in the header strip
-- of the window, a column at its right edge (side tabs hang outside the border).
local function measure(frame, view, bounds)
  if ours[frame] or not frame:IsVisible() or skipped(view, frame) then
    return nil
  end
  local w, h = frame:GetWidth(), frame:GetHeight()
  local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  if not (w and h and left and right and top and bottom) then
    return nil
  end
  if w < view.min[1] or w > view.max[1] or h < view.min[2] or h > view.max[2] then
    return nil
  end
  local tab = { frame = frame, w = w, h = h, top = top, l = left, r = right, t = top, b = bottom }
  if view.flow == "column" then
    local edge = bounds.right
    if edge and (left < edge - COLUMN_INSET or left > edge + COLUMN_REACH) then
      return nil
    end
    tab.mid, tab.pos, tab.size, tab.edge, tab.rank = (left + right) / 2, -top, h, -bottom, -left
  else
    local windowTop = bounds.top
    if windowTop and (top > windowTop + 2 or top < windowTop - STRIP_DEPTH) then
      return nil
    end
    tab.mid, tab.pos, tab.size, tab.edge, tab.rank = (top + bottom) / 2, left, w, right, top
  end
  return tab
end

-- The last tab (right-most of a row, lowest of a column) of the largest group
-- sharing one centre line, plus the gap to its neighbour (DEFAULT_GAP when it
-- has none or the value is odd), the whole group and every tab-sized frame
-- that is not ours.
local function findTabs(view, frames, root)
  local bounds = { top = number(root, "GetTop"), right = number(root, "GetRight") }
  local tabs = {}
  for _, frame in ipairs(frames) do
    local ok, tab = pcall(measure, frame, view, bounds)
    if ok and tab then
      tabs[#tabs + 1] = tab
    end
  end
  local best
  for _, anchor in ipairs(tabs) do
    local group = {}
    for _, tab in ipairs(tabs) do
      if math.abs(tab.mid - anchor.mid) <= ROW_TOLERANCE then
        group[#group + 1] = tab
      end
    end
    if not best or #group > #best or (#group == #best and anchor.rank > best[1].rank) then
      best = group
    end
  end
  if not best then
    return nil
  end
  table.sort(best, function(a, b)
    return a.edge < b.edge
  end)
  local last, prev = best[#best], best[#best - 1]
  local gap = DEFAULT_GAP
  if prev then
    local measured = (last.pos - prev.pos) - last.size
    if measured >= GAP_MIN and measured <= GAP_MAX then
      gap = measured
    end
  end
  return last, gap, best, tabs
end

-- Look of the side tabs of a window we only measure (the inspect window, see InspectLink).
local FOREIGN_COLUMN = { flow = "column", min = { 30, 30 }, max = { 64, 64 } }

-- The column of tab-sized frames at the right edge of `root`: visible, not ours and not
-- rejected by exclude(frame). Empty when there is none.
function B.FindSideTabs(root, exclude)
  if not isFrame(root) then
    return {}
  end
  local frames = {}
  for _, frame in ipairs(candidates({ root })) do
    if not (exclude and exclude(frame)) then
      frames[#frames + 1] = frame
    end
  end
  local _, _, group = findTabs(FOREIGN_COLUMN, frames, root)
  local out = {}
  for _, tab in ipairs(group or {}) do
    out[#out + 1] = tab.frame
  end
  return out
end

-- Placement -------------------------------------------------------------------

local function fmt(n)
  return string.format("%g", math.floor(n * 10 + 0.5) / 10)
end

local function sizeButton(button, style, w, h)
  if button.fgTemplate then
    return
  end
  button:SetSize(w, h)
  if style == "icon" then
    local logo = math.min(w, h) - (TAB_SIZE - LOGO_SIZE)
    button.icon:SetSize(logo, logo)
  end
end

-- Frame levels count across the whole strata, not per parent: sit well above the
-- view and above every sibling, so no Blizzard header frame catches the mouse first.
local function topLevel(frames, parent)
  local level = parent:GetFrameLevel() + LEVEL_BOOST
  for _, frame in ipairs(frames) do
    local ok, other = pcall(frame.GetFrameLevel, frame)
    if ok and not ours[frame] and type(other) == "number" and other + SIBLING_LEAD > level then
      level = other + SIBLING_LEAD
    end
  end
  return math.min(level, LEVEL_CAP)
end

local function bases(entry)
  local list = { entry.parent }
  if entry.root ~= entry.parent then
    list[#list + 1] = entry.root
  end
  return list
end

local function applyLevel(entry, level)
  for _, button in ipairs(entry.buttons) do
    button:SetFrameLevel(level)
  end
  if entry.rowTab then
    entry.rowTab:SetFrameLevel(level)
  end
  if entry.panel then
    entry.panel.SetLevel(level - PANEL_DROP)
  end
end

-- Blizzard's own tabs end our panel: a click on one of them deselects our tab.
-- Tab buttons are rebuilt by Blizzard, every new frame is hooked once.
local function hookTabs(entry, frames)
  if not entry.panel then
    return
  end
  for _, frame in ipairs(frames or {}) do
    if not tabHooked[frame] and not ours[frame] then
      tabHooked[frame] = true
      pcall(frame.HookScript, frame, "OnClick", function()
        if entry.panel then
          entry.panel.Hide()
        end
      end)
    end
  end
end

-- Left, right, top, bottom around all given frames, nil while a rect is unknown.
local function rectOf(frames)
  local l, r, t, b
  for _, frame in ipairs(frames) do
    local fl, fr, ft, fb =
      number(frame, "GetLeft"), number(frame, "GetRight"), number(frame, "GetTop"), number(frame, "GetBottom")
    if not (fl and fr and ft and fb) then
      return nil
    end
    l, r = math.min(l or fl, fl), math.max(r or fr, fr)
    t, b = math.max(t or ft, ft), math.min(b or fb, fb)
  end
  return l, r, t, b
end

-- A tab that is anchored (directly or through others) to one of our frames
-- already sits behind us; moving behind it would be a circular anchor.
local function dependsOnOurs(frame, seen, depth)
  if ours[frame] then
    return true
  end
  if depth > DEPENDENCY_DEPTH or seen[frame] then
    return false
  end
  seen[frame] = true
  for i = 1, number(frame, "GetNumPoints") or 0 do
    local ok, _, rel = pcall(frame.GetPoint, frame, i)
    if ok and type(rel) == "table" and dependsOnOurs(rel, seen, depth + 1) then
      return true
    end
  end
  return false
end

-- Chain of tabs behind Blizzard's last tab -------------------------------------

-- Frame our first button continues from, or nil without Blizzard's structure
-- (or a side view): the last shown side tab of the window.
local function chainBase(entry)
  local chain = entry.target.view.chain
  if not chain then
    return nil
  end
  local base = field(entry.parent, chain.firstField)
  base = isFrame(base) and base or nil
  local list = field(entry.parent, chain.listField)
  if type(list) == "table" then
    for _, tab in ipairs(list) do
      if isFrame(tab) and shown(tab) then
        base = tab
      end
    end
  end
  return base
end

local function anchoredTo(frame, members, sides, base)
  for i = 1, number(frame, "GetNumPoints") or 0 do
    local ok, _, rel, relPoint = pcall(frame.GetPoint, frame, i)
    if ok and type(rel) == "table" and members[rel] and (rel ~= base or sides[relPoint]) then
      return true
    end
  end
  return false
end

local function edgeOf(frame, flow)
  if flow == "column" then
    return -(number(frame, "GetBottom") or 0)
  end
  return number(frame, "GetRight") or 0
end

-- Visible children of the view that other addons anchored behind `base`, directly
-- or behind each other. Returns the last of them (farthest along the row, later
-- found wins a tie), the member set and the members in the order found.
local function chainTail(entry, base)
  local chain = entry.target.view.chain
  local members, added = { [base] = true }, {}
  local pool = childrenOf(entry.parent)
  local grown = true
  while grown do
    grown = false
    for _, child in ipairs(pool) do
      if
        not members[child]
        and not ours[child]
        and visible(child)
        and anchoredTo(child, members, chain.sides, base)
        and not dependsOnOurs(child, {}, 0)
      then
        members[child] = true
        added[#added + 1] = child
        grown = true
      end
    end
  end
  local tail
  for _, frame in ipairs(added) do
    if not tail or edgeOf(frame, chain.flow) >= edgeOf(tail, chain.flow) then
      tail = frame
    end
  end
  return tail, members, added
end

local function anchorChainFirst(entry, rel)
  local chain = entry.target.view.chain
  local button = entry.buttons[1]
  button:ClearAllPoints()
  button:SetPoint(chain.point, rel, chain.relPoint, chain.dx, chain.dy)
  entry.anchor = rel
end

-- Puts our first button behind the last tab of the chain. An anchor that is still
-- a link of the chain stays unless a foreign tab overlaps our buttons (or the
-- rects are unknown), so addons that also want the last slot never ping-pong.
local function anchorChain(entry, base)
  local chain = entry.target.view.chain
  local tail, members, added = chainTail(entry, base)
  local current = entry.anchor
  local target = tail or base
  if current and current ~= target and (current == base or members[current]) and visible(current) then
    local l, r, t, b = rectOf(entry.buttons)
    local hit
    for _, member in ipairs(added) do
      if member ~= current then
        local ml, mr, mt, mb = rectOf({ member })
        local overlaps = not (l and ml) or (ml <= r + TOUCH and mr >= l - TOUCH and mb <= t + TOUCH and mt >= b - TOUCH)
        if overlaps and (not hit or edgeOf(member, chain.flow) >= edgeOf(hit, chain.flow)) then
          hit = member
        end
      end
    end
    target = hit or current
  end
  if target ~= current then
    if current then
      stats.moved = stats.moved + 1
    end
    anchorChainFirst(entry, target)
  end
  local names = { nameOf(base) }
  for _, member in ipairs(added) do
    names[#names + 1] = nameOf(member)
  end
  names[#names + 1] = "ours (behind " .. nameOf(entry.anchor) .. ")"
  entry.chain = table.concat(names, " > ")
end

-- Side tabs of the spellbook and talent views ---------------------------------------

-- Look of Blizzard's row of category tabs: tab-sized buttons side by side.
local ROW_VIEW = { flow = "row", min = { 16, 16 }, max = { 80, 80 } }

local function toggle(frame, on)
  if on ~= shown(frame) then
    pcall(on and frame.Show or frame.Hide, frame)
  end
end

-- The last visible tab of the spellbook's category row (CategoryTabSystem) with the gap to its
-- neighbour. Without it: nil and the reason, for the diag report.
local function findRow(entry)
  local system = field(entry.parent, "CategoryTabSystem")
  if not isFrame(system) then
    return nil, "no CategoryTabSystem"
  end
  local tabs = {}
  for _, child in ipairs(childrenOf(system)) do
    if isFrame(child) then
      tabs[#tabs + 1] = child
    end
  end
  local last, gap, group = findTabs(ROW_VIEW, tabs, entry.root)
  if not last then
    return nil, nameOf(system) .. " has no visible tab below the window top"
  end
  local index = 0
  for i, tab in ipairs(tabs) do
    if tab == last.frame then
      index = i
    end
  end
  return { last = last, gap = gap, system = system },
    string.format(
      "%s, %d tabs, last %s #%d %sx%s, gap %s",
      nameOf(system),
      #group,
      nameOf(last.frame),
      index,
      fmt(last.w),
      fmt(last.h),
      fmt(gap)
    )
end

-- The learn list tab sits behind the last tab of the category row, same size and gap, anchored to
-- that frame. It is a drawn button of its own (the side tab keeps the template look and takes over
-- again when the row is gone). Returns whether the row tab is in use.
local function placeRow(entry)
  local level = entry.level
  if not level then
    return false
  end
  local row, info = findRow(entry)
  local tab = entry.rowTab
  if not row then
    if tab then
      toggle(tab, false)
    end
    toggle(level.button, true)
    entry.rowInfo = "tab row: not found (" .. info .. "), side tab at the window edge"
    return false
  end
  if not tab then
    tab = makeIconButton(entry.parent, level.link, entry.root, level.handler)
    decorateTab(tab)
    tab:fgSetSelected(entry.panel and entry.panel.IsShown() or false)
    entry.rowTab = tab
  end
  tab:ClearAllPoints()
  tab:SetPoint("LEFT", row.last.frame, "RIGHT", row.gap, 0)
  sizeButton(tab, "icon", row.last.w, row.last.h)
  toggle(tab, true)
  toggle(level.button, false)
  entry.rowInfo = "tab row: " .. info
  return true
end

-- The frame whose right edge the column of side tabs hangs on: the window, or what a target names (the group
-- finder: the docked filter panel).
local function columnBase(entry)
  local edge = entry.target.edge
  return edge and edge() or entry.root
end

-- The first tab of the stack: at the right edge of the column base, or behind the foreign tab `rel`.
local function anchorSide(entry, rel)
  local first = entry.stack[1]
  if not first then
    return
  end
  local base = columnBase(entry)
  first:ClearAllPoints()
  if rel then
    first:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -SIDE_GAP)
  else
    first:SetPoint("TOPLEFT", base, "TOPRIGHT", SIDE_INSET, -SIDE_DROP)
  end
  entry.anchor, entry.base = rel, base
end

-- Lowest tab of the list that does not hang behind ours (that would be a loop).
local function lowestIndependent(list)
  for i = #list, 1, -1 do
    if not dependsOnOurs(list[i].frame, {}, 0) then
      return list[i]
    end
  end
end

local layoutSide

-- Keeps the stack at the end of the column: it only moves behind the last foreign
-- side tab when one overlaps it, or when the tab it hangs behind is gone.
local function reflowSide(entry)
  if placeRow(entry) ~= (entry.inRow == true) then
    return layoutSide(entry)
  end
  local frames = candidates(bases(entry))
  local base = columnBase(entry)
  if not entry.anchor and entry.base ~= base then
    -- The column moved to another frame (the panel docked or undocked): hang on its new edge.
    anchorSide(entry, nil)
  end
  local _, _, group, tabs = findTabs(entry.target.view, frames, base)
  applyLevel(entry, topLevel(frames, entry.parent))
  local system = field(entry.parent, "CategoryTabSystem")
  if isFrame(system) then
    hookTabs(entry, childrenOf(system))
  end
  if entry.anchor and not visible(entry.anchor) then
    anchorSide(entry, nil)
  end
  local l, r, t, b = rectOf(entry.stack)
  if not l then
    return
  end
  local hit
  for _, tab in ipairs(tabs or {}) do
    if
      tab.frame ~= entry.anchor
      and tab.l <= r + TOUCH
      and tab.r >= l - TOUCH
      and tab.b <= t + TOUCH
      and tab.t >= b - TOUCH
      and (not hit or tab.edge > hit.edge)
      and not dependsOnOurs(tab.frame, {}, 0)
    then
      hit = tab
    end
  end
  if not hit then
    return
  end
  local inColumn = false
  for _, tab in ipairs(group or {}) do
    inColumn = inColumn or tab == hit
  end
  stats.moved = stats.moved + 1
  anchorSide(entry, (inColumn and lowestIndependent(group) or hit).frame)
end

-- Stacks the buttons below each other at the right edge of the window, except the learn list tab
-- while it sits in the category row. The engine keeps them on the screen when the window sits at
-- the screen edge.
function layoutSide(entry)
  local inRow, stack, modes = placeRow(entry), {}, {}
  for i, button in ipairs(entry.buttons) do
    local rowButton = inRow and entry.level.button == button
    local sized = rowButton and entry.rowTab or button
    if not rowButton then
      if #stack > 0 then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", stack[#stack], "BOTTOMLEFT", 0, -SIDE_GAP)
      end
      button:SetClampedToScreen(true)
      stack[#stack + 1] = button
    end
    modes[i] = LINKS[entry.target.links[i]].tag
      .. (rowButton and " row " or " side ")
      .. fmt(sized:GetWidth())
      .. "x"
      .. fmt(sized:GetHeight())
  end
  entry.stack, entry.inRow = stack, inRow
  anchorSide(entry, nil)
  entry.gap, entry.mode, entry.offsets, entry.modes = nil, "side", false, modes
  reflowSide(entry)
end

-- Sets size, anchors and entry.modes for the buttons of one area.
local function layout(entry)
  local target, buttons, view = entry.target, entry.buttons, entry.target.view
  if view.side then
    return layoutSide(entry)
  end
  local frames = candidates(bases(entry))
  local level = topLevel(frames, entry.parent)
  local base = chainBase(entry)
  local modes = {}
  entry.anchor, entry.gap = nil, nil
  if base then
    local chain = view.chain
    for i, button in ipairs(buttons) do
      button:SetFrameLevel(level)
      if i > 1 then
        button:ClearAllPoints()
        button:SetPoint(chain.point, buttons[i - 1], chain.relPoint, chain.dx, chain.dy)
      end
      sizeButton(button, view.style, chain.size[1], chain.size[2])
      modes[i] = LINKS[target.links[i]].tag .. " chain " .. fmt(chain.size[1]) .. "x" .. fmt(chain.size[2])
    end
    anchorChain(entry, base)
    entry.mode = "chain"
    entry.offsets = false
  else
    local last, gap = findTabs(view, frames, entry.root)
    for i, button in ipairs(buttons) do
      button:ClearAllPoints()
      button:SetFrameLevel(level)
      local w, h = view.fallback[1], view.fallback[2]
      if last then
        w, h = last.w, last.h
        if i == 1 then
          button:SetPoint(
            view.flow == "column" and "TOP" or "LEFT",
            last.frame,
            view.flow == "column" and "BOTTOM" or "RIGHT",
            view.flow == "column" and 0 or gap,
            view.flow == "column" and -gap or 0
          )
          entry.anchor, entry.gap = last.frame, gap
        elseif view.flow == "column" then
          button:SetPoint("TOP", buttons[i - 1], "BOTTOM", 0, -gap)
        else
          button:SetPoint("LEFT", buttons[i - 1], "RIGHT", gap, 0)
        end
      else
        button:SetPoint(view.point, entry.root, view.origin or "TOPLEFT", view.x + (i - 1) * view.step, view.y)
      end
      sizeButton(button, view.style, w, h)
      local found = view.flow == "column" and "tab column " or "tab row "
      modes[i] = LINKS[target.links[i]].tag .. " " .. (last and found or "offsets ") .. fmt(w) .. "x" .. fmt(h)
    end
    entry.mode = last and "geometry" or "offsets"
    entry.offsets = not last
  end
  if entry.panel then
    entry.panel.SetLevel(level - PANEL_DROP)
  end
  entry.modes = modes
end

-- Geometry mode: moves our first button behind a foreign tab that overlaps it.
local function reflowGeometry(entry)
  local view = entry.target.view
  local frames = candidates(bases(entry))
  local last, gap, _, tabs = findTabs(view, frames, entry.root)
  applyLevel(entry, topLevel(frames, entry.parent))
  if not last then
    return
  end
  local first = entry.buttons[1]
  local function anchor(rel)
    first:ClearAllPoints()
    if view.flow == "column" then
      first:SetPoint("TOP", rel, "BOTTOM", 0, -gap)
    else
      first:SetPoint("LEFT", rel, "RIGHT", gap, 0)
    end
    entry.anchor, entry.gap = rel, gap
  end
  if entry.anchor and not visible(entry.anchor) then
    return anchor(last.frame)
  end
  local l, r, t, b = rectOf(entry.buttons)
  if not l then
    return
  end
  local hit
  for _, tab in ipairs(tabs) do
    if
      tab.frame ~= entry.anchor
      and tab.l <= r + TOUCH
      and tab.r >= l - TOUCH
      and tab.b <= t + TOUCH
      and tab.t >= b - TOUCH
      and (not hit or tab.edge > hit.edge)
      and not dependsOnOurs(tab.frame, {}, 0)
    then
      hit = tab
    end
  end
  if hit then
    stats.moved = stats.moved + 1
    anchor(hit.frame)
  end
end

-- Re-checks a placed area: tabs may have appeared since, also from other addons
-- and in any load order.
local function reflow(entry)
  if entry.target.view.side then
    return reflowSide(entry)
  end
  local base = chainBase(entry)
  if (base ~= nil) ~= (entry.mode == "chain") or (not base and entry.offsets) then
    return layout(entry)
  end
  if not base then
    return reflowGeometry(entry)
  end
  applyLevel(entry, topLevel(candidates(bases(entry)), entry.parent))
  anchorChain(entry, base)
end

-- Attaching -------------------------------------------------------------------

local function onBookTab(entry)
  local panel = entry.panel
  local tab = Scan.Call(entry.parent, "GetTab")
  if panel and panel.IsShown() and entry.lastTab ~= nil and tab ~= entry.lastTab then
    panel.Hide()
  end
  entry.lastTab = tab
end

-- Hooks of the structural views: Blizzard rebuilds its tabs and switches
-- categories on its own. The spellbook panel ends with a category switch.
local function hookView(entry)
  local parent, chain = entry.parent, entry.target.view.chain
  if entry.panel then
    hookMethod(parent, "SetTab", function()
      onBookTab(entry)
    end)
    hookMethod(field(parent, "CategoryTabSystem"), "AddTab", function()
      ns.Debounce("blizz-links-tabs", RETRY_DELAY / 2, function()
        B.Discover("AddTab")
      end)
    end)
  end
  if not chain then
    return
  end
  if chain.refresh then
    hookMethod(parent, chain.refresh, function()
      B.Discover(chain.refresh)
    end)
  end
  if chain.deselect then
    hookMethod(parent, chain.deselect, function()
      for _, button in ipairs(entry.buttons) do
        if type(button.SetChecked) == "function" then
          pcall(button.SetChecked, button, false)
        end
      end
    end)
  end
end

local function attach(target, parent, root)
  local buttons = {}
  local entry = { target = target, parent = parent, root = root, buttons = buttons }
  local chain = target.view.chain
  local structural = chainBase(entry) ~= nil
  for _, name in ipairs(target.links) do
    local link = LINKS[name]
    local handler
    if link.menu then
      handler = function(self, mouse)
        if mouse == "RightButton" then
          openMenu(self, root)
        else
          openPage(link, root)
        end
      end
    elseif link.action then
      handler = function()
        stats.click = stats.click + 1
        stats.last = link.tag .. " action"
        link.action()
      end
    elseif link.panel then
      handler = function()
        stats.click = stats.click + 1
        stats.last = "spellbook tab"
        if entry.panel then
          if not entry.panel.IsShown() then
            entry.lastTab = Scan.Call(parent, "GetTab")
          end
          entry.panel.Toggle()
        else
          openPage(link, root)
        end
      end
    end
    local button
    if target.view.side then
      button = B.CreateSideTab(parent, {
        key = link.key,
        tip = link.tip,
        onClick = handler or onClick(link, root),
      })
    elseif structural and chain.template then
      button = makeTemplateTab(parent, link, root, chain.template, handler, link.frameName or TEMPLATE_TAB)
    end
    button = button or makeIconButton(parent, link, root, handler)
    if link.menu and not button.fgTemplate then
      button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    buttons[#buttons + 1] = button
    if link.panel and target.view.side then
      entry.level = { button = button, link = link, handler = handler }
    end
    if link.panel and ns.SpellbookPanel then
      local ok, panel = pcall(ns.SpellbookPanel.Create, parent, {
        onOpen = function()
          openPage(link, root)
        end,
        onSelect = function(on)
          if button.fgSetSelected then
            button:fgSetSelected(on)
          end
          if entry.rowTab then
            entry.rowTab:fgSetSelected(on)
          end
        end,
      })
      if ok then
        entry.panel = panel
        markOurs(panel.frame)
      else
        ns.Log.warn("blizz links spellbook panel: %s", tostring(panel))
      end
    end
  end
  attached[target.id] = entry
  layout(entry)
  hookView(entry)
end

-- Re-checked on every show of a found frame: tab content can be created late,
-- other addons add their tabs a moment after the view shows.
local function hookShow(frame)
  if hooked[frame] then
    return
  end
  hooked[frame] = true
  pcall(frame.HookScript, frame, "OnShow", function()
    B.Discover("OnShow")
    ns.Debounce("blizz-links-late", LATE_DELAY, function()
      B.Discover("late")
    end)
  end)
end

local function targets()
  local list = { unpack(TARGETS) }
  for _, kind in ipairs(STRUCTURAL_ORDER) do
    if scanned[kind] then
      list[#list + 1] = scanned[kind]
    end
  end
  return list
end

local function frameOf(target)
  return target.frame or resolve(target.parent)
end

-- Windows no known name led to, found by their structure.
local function findStructural(allowEnumerate)
  local wanted = {}
  for _, kind in ipairs(STRUCTURAL_ORDER) do
    if not attached[kind] and not scanned[kind] then
      wanted[#wanted + 1] = kind
    end
  end
  if #wanted == 0 then
    return
  end
  local found = Scan.Find(wanted, allowEnumerate)
  for kind, hit in pairs(found) do
    local plan = STRUCTURAL[kind]
    scanned[kind] = {
      id = kind,
      parent = hit.name or ("structure:" .. kind),
      frame = hit.frame,
      rootFrame = hit.root,
      via = hit.via,
      view = plan.view,
      links = plan.links,
    }
  end
end

-- Shows or hides the buttons of an area whose setting changed (own frames only).
local function setShown(entry, on)
  for _, button in ipairs(entry and entry.buttons or {}) do
    if on ~= shown(button) then
      pcall(on and button.Show or button.Hide, button)
    end
  end
  if not on then
    closeMenu()
  end
end

-- Attaches the buttons to every area whose frame exists now and re-checks the
-- placed ones. reason says what triggered it (diag report). Safe to call at any
-- time, in combat it waits for PLAYER_REGEN_ENABLED. enumerate allows the
-- last-resort walk over all frames (a few runs per session).
function B.Discover(reason, enumerate)
  if type(reason) ~= "string" then
    reason, enumerate = "call", nil
  end
  if InCombatLockdown and InCombatLockdown() then
    pending = true
    return
  end
  if enumerate then
    enumerations = enumerations + 1
    if enumerations > ENUMERATE_RUNS then
      enumerate = false
    end
  end
  pcall(findStructural, enumerate)
  for _, target in ipairs(targets()) do
    local parent = frameOf(target)
    if parent and target.setting and not enabled(target.setting) then
      setShown(attached[target.id], false)
    elseif parent then
      local root = target.rootFrame or (target.root and resolve(target.root)) or parent
      hookShow(root)
      hookShow(parent)
      local entry = attached[target.id]
      local ok, err = true, nil
      if not entry then
        ok, err = pcall(attach, target, parent, root)
        entry = attached[target.id]
      elseif entry.target == target and visible(parent) then
        ok, err = pcall(reflow, entry)
      end
      if entry and entry.target == target then
        entry.trigger = reason
        if target.setting then
          setShown(entry, true)
        end
      end
      if not ok then
        ns.Log.warn("blizz links %s: %s", target.parent, tostring(err))
      end
    end
  end
end

-- The buttons of an area (a copy), empty while it is not attached.
function B.Buttons(id)
  local entry = attached[id]
  return entry and { unpack(entry.buttons) } or {}
end

-- Marks the buttons of an area as selected or not (panels opened from a tab).
function B.SetSelected(id, on)
  for _, button in ipairs(B.Buttons(id)) do
    if type(button.fgSetSelected) == "function" then
      button:fgSetSelected(on == true)
    end
  end
end

-- The spellbook panel of the attached spellbook view, or nil.
function B.Panel()
  local entry = attached.spellbook
  return entry and entry.panel
end

-- Reaction to Blizzard's EventRegistry callbacks.
function B.OnEvent(name)
  local kind = EVENTS[name]
  stats.events = (stats.events or 0) + 1
  stats.lastEvent = name
  if kind == "hide" then
    local panel = B.Panel()
    if panel then
      panel.Hide()
    end
    return
  end
  if kind == "changed" then
    ns.Debounce("blizz-links-changed", RETRY_DELAY, function()
      B.Discover("event " .. name)
    end)
    return
  end
  B.Discover("event " .. name)
  if kind == "show" then
    -- Blizzard fires "show" before it has rebuilt its tabs.
    if C_Timer and C_Timer.After then
      C_Timer.After(RETRY_DELAY, function()
        B.Discover("event " .. name .. " (retry)")
      end)
    end
  end
end

local function registerEvents()
  local registry = EventRegistry
  if eventsRegistered > 0 or type(registry) ~= "table" or type(registry.RegisterCallback) ~= "function" then
    return
  end
  for name in pairs(EVENTS) do
    if pcall(registry.RegisterCallback, registry, name, function()
      B.OnEvent(name)
    end, eventOwner) then
      eventsRegistered = eventsRegistered + 1
    end
  end
end

-- Applies the setting "Button in the character window": hides at once, even in
-- combat (our own frame); showing and placing wait for the next check.
function B.Apply()
  if not enabled("characterButton") then
    setShown(attached.character, false)
  end
  B.Discover("settings")
end

-- Diag report. First line: which frames exist and how each button was placed.
-- Then per window how it was found, what triggered the last check and the anchor
-- chain, the panel windows of the game, the structure of the spellbook view and
-- the panel geometry.
function B.Report()
  local seen, found, where = {}, {}, {}
  for _, target in ipairs(targets()) do
    for _, path in ipairs({ target.parent, target.root }) do
      if not seen[path] then
        seen[path] = true
        found[#found + 1] = path .. "=" .. ((target.frame or resolve(path)) and "yes" or "no")
      end
    end
  end
  for _, id in ipairs(IDS) do
    local a = attached[id]
    where[#where + 1] = id
      .. "="
      .. (
        a and (a.target.parent .. " (" .. #a.buttons .. " buttons: " .. table.concat(a.modes or {}, ", ") .. ")")
        or "none"
      )
  end
  local main = ns.Main and ns.Main.frame
  local mainState = "not created"
  if main then
    local _, strata = pcall(main.GetFrameStrata, main)
    mainState = (main:IsShown() and "shown" or "hidden") .. ", strata " .. tostring(strata)
  end
  local clicks = string.format(
    "hover %d, mouse down %d, clicks %d, last page %s, main window %s, tabs moved %d",
    stats.hover,
    stats.down,
    stats.click,
    stats.last,
    mainState,
    stats.moved
  )
  local out = {
    "blizzard links: " .. table.concat(where, ", ") .. " | " .. clicks .. " | frames: " .. table.concat(found, " "),
  }
  for _, id in ipairs(IDS) do
    local a = attached[id]
    if a then
      local via = a.target.via and ("structure (" .. a.target.via .. ")") or "name"
      out[#out + 1] = string.format(
        "%s: found by %s, mode %s, last check: %s%s",
        id,
        via,
        a.mode or "?",
        a.trigger or "-",
        a.chain and (", chain " .. a.chain) or ""
      )
    else
      out[#out + 1] = id .. ": not found (names and structure)"
    end
  end
  out[#out + 1] = string.format(
    "events: %d EventRegistry callbacks, %d fired, last %s | frame walks %d of %d",
    eventsRegistered,
    stats.events or 0,
    tostring(stats.lastEvent),
    enumerations,
    ENUMERATE_RUNS
  )
  out[#out + 1] = Scan.PanelLine()
  if ns.InspectLink and ns.InspectLink.Info then
    out[#out + 1] = ns.InspectLink.Info()
  end
  local book = attached.spellbook
  if book then
    out[#out + 1] = book.rowInfo or "tab row: not checked"
    out[#out + 1] = "spellbook view " .. book.target.parent .. ":"
    for _, text in ipairs(ns.SpellbookPanel and ns.SpellbookPanel.Structure(book.parent) or {}) do
      out[#out + 1] = text
    end
    out[#out + 1] = book.panel and book.panel.Info() or "panel: not created"
  end
  return table.concat(out, "\n")
end

ns.On("PLAYER_LOGIN", function()
  registerEvents()
  B.Discover("PLAYER_LOGIN")
end)

ns.On("PLAYER_ENTERING_WORLD", function()
  registerEvents()
  B.Discover("PLAYER_ENTERING_WORLD")
end)

-- Any addon may add tabs while loading: look again shortly after, whatever the load order.
ns.On("ADDON_LOADED", function(_, name)
  if type(name) == "string" and name:find("^Blizzard_") then
    B.Discover("ADDON_LOADED " .. name)
    -- The new window may exist only a moment later: one structural walk for what is still missing.
    if C_Timer and C_Timer.After then
      C_Timer.After(LATE_DELAY, function()
        B.Discover("ADDON_LOADED " .. name .. " (late)", true)
      end)
    end
  else
    ns.Debounce("blizz-links-late", LATE_DELAY, function()
      B.Discover("ADDON_LOADED")
    end)
  end
end)

-- The switch "offer filter panel" of the group finder card.
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.lfgPanel" then
    B.Discover("settings")
  end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  if pending then
    pending = false
    B.Discover("combat ended")
  end
end)
