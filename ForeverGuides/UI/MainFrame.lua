-- Main window: title bar (drag, scale), sidebar, routed content area,
-- footer (data status, errors, resize grip), keyboard handling.
local _, ns = ...
local W, Theme, L, U, Layout = ns.W, ns.Theme, ns.L, ns.U, ns.Layout

local Main = {}
ns.Main = Main
ns.MainLayout = Layout.compute(Layout.DEFAULT_W, false)

local frame, sidebar, content, contentHost, header, footer, search
local views = {}
local currentView

-- Skin "forever": the title bar moves into the metal band above the window (see "Title bar" below), the page
-- header stays under it. band.on = true while the bar sits in the band, band.rect = Skins.BandRect, band.tier = how
-- many reductions the width needed (in both styles), band.state = what is still shown. parts = the controls of the
-- title bar, built once in buildTitleBar (tests and diagnostics read band and band.parts).
local band = { on = false, tier = 0 }
local parts = {}
band.parts = parts
Main.band = band
local layoutBar, applyHeaderMode

local ICON = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png"

-- The author's own channel, the second link field of the title bar (text and address for the copy dialog). The one
-- place of the address; the texts are added here, so this file is the only one of the release with the name
-- (tools/build_release.py ALLOWED_HITS).
local CHANNEL = { text = "twitch.tv/wosande", address = "https://twitch.tv/wosande" }
ns.AddLocale("enUS", { ["bar.channel"] = "Copy Twitch channel" })
ns.AddLocale("deDE", { ["bar.channel"] = "Twitch-Kanal kopieren" })

local function frameDB()
  return ns.db.frames.main
end

local function savePosition()
  if not frame then
    return
  end
  local point, _, rel, x, y = frame:GetPoint(1)
  local db = frameDB()
  db.point, db.rel, db.x, db.y = point, rel, x, y
end

-- The screen in UIParent units; a window of width w covers w * scale of it.
local function screenSize()
  return UIParent:GetWidth(), UIParent:GetHeight()
end

-- The window may grow to the full screen at its current zoom, so the limits follow the scale.
local function maxSize()
  local w, h = screenSize()
  return Layout.maxSize(w, h, frame:GetScale())
end

local function applyBounds()
  local maxW, maxH = maxSize()
  frame:SetResizable(true)
  if ns.can.resizeBounds then
    frame:SetResizeBounds(Layout.MIN_W, Layout.MIN_H, maxW, maxH)
  elseif frame.SetMinResize then
    frame:SetMinResize(Layout.MIN_W, Layout.MIN_H)
    frame:SetMaxResize(maxW, maxH)
  end
end

local function saveSize()
  local db = frameDB()
  db.w, db.h = Layout.clampSize(frame:GetWidth(), frame:GetHeight(), maxSize())
end

local function restoreGeometry()
  local db = frameDB()
  local function num(v, default)
    return type(v) == "number" and v == v and v or default
  end
  local function anchor(v)
    return type(v) == "string" and v or "CENTER"
  end
  frame:SetScale(U.clamp(num(ns.db.settings.scale, 1), 0.7, 1.5))
  applyBounds()
  frame:SetSize(Layout.clampSize(num(db.w, 960), num(db.h, 620), maxSize()))
  frame:ClearAllPoints()
  frame:SetPoint(anchor(db.point), UIParent, anchor(db.rel), num(db.x, 0), num(db.y, 0))
end

-- Below 100 percent zoom the font floor grows (Theme.fontFloor): repaint the fonts when it moved.
local function repaintOnFloor(before)
  if Theme.fontFloor() ~= before then
    ns.Debounce("zoom-font-floor", 0.2, function()
      ns.RefreshUI()
      Main.Relayout()
    end)
  end
end

-- Scale keeps the center of `anchor` (a control inside the window, the zoom control the user is
-- working with) at the same screen spot, so it never runs away from the mouse. Without an anchor
-- the window's own center stays. The window is cut to the screen at the new zoom and kept inside it.
function Main.SetScale(value, anchor)
  value = U.clamp(U.round(value, 0.05), 0.7, 1.5)
  local floor = Theme.fontFloor()
  ns.db.settings.scale = value
  if not frame then
    return
  end
  local old = frame:GetScale()
  local screenW, screenH = screenSize()
  local maxW, maxH = Layout.maxSize(screenW, screenH, value)
  local w, h = frame:GetWidth(), frame:GetHeight()
  if w > maxW or h > maxH then
    frame:SetSize(math.min(w, maxW), math.min(h, maxH))
  end
  -- Centers in screen units: GetCenter answers in the window's own units.
  local cx, cy = frame:GetCenter()
  local ax, ay
  if cx then
    cx, cy = cx * old, cy * old
    ax, ay = cx, cy
    local x, y
    if anchor then
      x, y = anchor:GetCenter()
    end
    if x then
      ax, ay = x * old, y * old
    end
  end
  frame:SetScale(value)
  applyBounds()
  if cx then
    local nx, ny = Layout.zoomCenter(cx, cy, ax, ay, old, value)
    nx = Layout.keepOnScreen(nx, frame:GetWidth() * value, screenW)
    ny = Layout.keepOnScreen(ny, frame:GetHeight() * value, screenH)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", nx / value, ny / value)
    savePosition()
  end
  ns.Emit("FG_SETTING_CHANGED", "settings.scale", value)
  repaintOnFloor(floor)
end

function Main.ResetGeometry()
  ns.db.frames.main = U.copy(ns.Store.defaults.frames.main)
  local floor = Theme.fontFloor()
  ns.db.settings.scale = 1
  if frame then
    restoreGeometry()
    Main.Relayout()
  end
  ns.Emit("FG_SETTING_CHANGED", "settings.scale", 1)
  repaintOnFloor(floor)
  -- Way back from a fully transparent window.
  Main.SetAlpha(Theme.ALPHA_DEFAULT)
end

-- Opacity ------------------------------------------------------------------------------------

-- Only the background fills fade (texture alpha), text, icons and control edges stay at full
-- strength. Fills register once; page cards register themselves (W.Card).
local function applyAlpha()
  if not frame then
    return
  end
  for _, tex in ipairs({ frame.fgBack, sidebar.fgBack, footer.fgBack, ns.WindowShell.Of(frame).barFill }) do
    W.FadeWithWindow(tex)
  end
  W.ApplyWindowAlpha()
end

-- percent: Theme.ALPHA_MIN to Theme.ALPHA_MAX
function Main.SetAlpha(percent)
  local v = tonumber(percent)
  if not v or v ~= v then
    v = Theme.ALPHA_DEFAULT
  end
  ns.Store.set("settings.mainAlpha", U.clamp(U.round(v), Theme.ALPHA_MIN, Theme.ALPHA_MAX))
  applyAlpha()
end

-- Layout -------------------------------------------------------------------

function Main.Relayout()
  if not frame then
    return
  end
  local lay = Layout.compute(frame:GetWidth(), ns.db.settings.sidebarCollapsed)
  ns.MainLayout = lay
  sidebar:SetWidth(lay.sidebarWidth)
  sidebar:Layout(lay.sidebar == "icons")
  layoutBar()
  if currentView and currentView.Layout then
    ns.Safe("view-layout", currentView.Layout, currentView, lay)
  end
  ns.Emit("FG_LAYOUT_CHANGED", lay)
end

-- Routing ------------------------------------------------------------------

local crumbButtons = {}
local crumbCount = 0
parts.crumbs = crumbButtons

-- Flat: the trail sits above the page title, each crumb right of the one before.
local function placeCrumbs()
  local prev
  for i, b in ipairs(crumbButtons) do
    local on = i <= crumbCount
    b:SetShown(on)
    if on then
      b:SetHeight(16)
      b:ClearAllPoints()
      b:SetPoint(
        "BOTTOMLEFT",
        prev or header.title,
        prev and "BOTTOMRIGHT" or "TOPLEFT",
        prev and 4 or 0,
        prev and 0 or 4
      )
      prev = b
    end
  end
end

local function renderCrumbs(path)
  local crumbs = ns.Router:crumbs(path)
  crumbCount = #crumbs
  for i, c in ipairs(crumbs) do
    local b = crumbButtons[i]
    if not b then
      b = CreateFrame("Button", nil, header)
      b:SetHeight(16)
      b.text = W.Text(b, { role = "micro", color = "textMuted" })
      b.text:SetPoint("LEFT")
      b:SetScript("OnEnter", function(self)
        W.SetColor(self.text, "accent")
      end)
      b:SetScript("OnLeave", function(self)
        W.SetColor(self.text, self.isLast and "textSecondary" or "textMuted")
      end)
      crumbButtons[i] = b
    end
    local label = c.isKey and L[c.label] or c.label
    b.text:SetText((i > 1 and "> " or "") .. label)
    b:SetWidth(b.text:GetStringWidth() + 6)
    b.isLast = i == #crumbs
    W.SetColor(b.text, b.isLast and "textSecondary" or "textMuted")
    b:SetScript("OnClick", function()
      ns.Router:navigate(c.path)
    end)
  end
  header.place()
end

local function getView(page)
  local view = views[page.id]
  if view then
    return view
  end
  local container = CreateFrame("Frame", nil, contentHost)
  container:SetAllPoints()
  container:Hide()
  view = page.build(container, page) or {}
  view.container = container
  views[page.id] = view
  return view
end

local function onRoute(path, page, params)
  if not frame then
    return
  end
  for _, v in pairs(views) do
    v.container:Hide()
  end
  local view = getView(page)
  currentView = view
  view.container:Show()
  W.SetText(header.title, page.title)
  header:SetTour(ns.Tutorials.ForPage(page.id))
  renderCrumbs(path)
  header.back:SetEnabled(ns.Router:canBack())
  header.fwd:SetEnabled(ns.Router:canForward())
  sidebar:SetActive(page.id)
  if view.Show then
    ns.Safe("view-show:" .. page.id, view.Show, view, params)
  end
  if view.Layout then
    ns.Safe("view-layout", view.Layout, view, ns.MainLayout)
  end
  ns.charDB.lastRoute = page.id
  ns.Emit("FG_ROUTE_CHANGED", path, page.id)
end

-- Locale change: rebuild page views so module texts are fresh.
local function invalidateViews()
  for id, v in pairs(views) do
    v.container:Hide()
    views[id] = nil
  end
  currentView = nil
  if ns.Router.current then
    local id, params = ns.RouterClass.parse(ns.Router.current)
    onRoute(ns.Router.current, ns.Router:get(id), params)
  end
end
Main.InvalidateViews = invalidateViews

-- Keyboard -------------------------------------------------------------------

local function handleKey(key)
  if ns.TutorialUI and ns.TutorialUI.HandleKey(key) then
    return true
  end
  if key == "ESCAPE" then
    return ns.EscStack.Close(frame)
  end
  -- Other keys only while the pointer is over the window or keyboard
  -- navigation is active, so Tab/Space/arrows keep working in the game.
  if not ns.Focus.current and not frame:IsMouseOver() then
    return false
  end
  if key == "TAB" then
    ns.Focus.move(IsShiftKeyDown() and -1 or 1)
    return true
  elseif (key == "ENTER" or key == "SPACE") and ns.Focus.current then
    return ns.Focus.activate()
  elseif (key == "UP" or key == "DOWN") and ns.Focus.current then
    ns.Focus.move(key == "UP" and -1 or 1)
    return true
  elseif (key == "LEFT" or key == "RIGHT") and IsAltKeyDown() then
    if key == "LEFT" then
      ns.Router:goBack()
    else
      ns.Router:goForward()
    end
    return true
  elseif (key == "LEFT" or key == "RIGHT") and ns.Focus.current and ns.Focus.current.fgArrow then
    ns.Focus.current:fgArrow(key == "LEFT" and -1 or 1)
    return true
  elseif key == "BACKSPACE" then
    return ns.Router:goBack()
  elseif key == "F" and IsControlKeyDown() then
    search.edit:SetFocus()
    return true
  end
  return false
end

local function setupKeyboard()
  if not ns.can.propagateKeyboard then
    return
  end
  -- Propagation cannot be set in combat; without it the window would eat
  -- every game key, so keyboard support waits for combat to end.
  if InCombatLockdown() then
    ns.On("PLAYER_REGEN_ENABLED", function()
      if not Main.keyboardReady then
        setupKeyboard()
      end
    end)
    return
  end
  Main.keyboardReady = true
  frame:SetPropagateKeyboardInput(true)
  frame:EnableKeyboard(true)
  frame:SetScript("OnKeyDown", function(self, key)
    -- Propagation may not be changed in combat; the game then handles keys, Esc still closes.
    if InCombatLockdown() then
      if key == "ESCAPE" then
        ns.Safe("key", handleKey, key)
      end
      return
    end
    local _, handled = ns.Safe("key", handleKey, key)
    self:SetPropagateKeyboardInput(not handled)
  end)
  ns.On("PLAYER_REGEN_DISABLED", function()
    pcall(frame.SetPropagateKeyboardInput, frame, true)
  end)
end

-- Construction ---------------------------------------------------------------

local SEARCH_WIDTH, SEARCH_HEIGHT, LOGO_SIZE = 220, 26, 26

-- Anchors of a control, replaced as a whole.
local function put(f, ...)
  f:ClearAllPoints()
  f:SetPoint(...)
end

local function buildTitleBar()
  local shell = ns.WindowShell.Of(frame)
  local bar = shell.titleBar
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  bar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    savePosition()
  end)
  bar:EnableMouseWheel(true)
  bar:SetScript("OnMouseWheel", function(_, delta)
    if ns.Keys.Matches("windowScale") then
      Main.SetScale(frame:GetScale() + delta * 0.05)
    end
  end)
  parts.bar = bar

  local logo = bar:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(ICON)
  parts.logo = logo
  ns.Anchors["FG.Title"] = bar

  -- The two link fields in the middle of the bar (both styles): a text and the address its copy dialog shows, the
  -- same mechanism as the Help page's own website button (ns.Website, set in Modules/Help.lua). WoW addons can't
  -- write to the OS clipboard directly, clicking opens the usual pre-selected copy box instead.
  -- Main.SetBarLink changes the text and the address of the website field.
  -- When the text has no room, a symbol with the same action takes its place, the name in its tooltip.
  local function linkField(titleKey, icon, text, copy)
    local field = W.Button(bar, { text = text, variant = "ghost", width = 160, height = 22, onClick = copy })
    local symbol = W.Action(bar, { icon = icon, size = 24, tooltip = titleKey, onClick = copy })
    return field, symbol
  end
  parts.link = { text = "forever-guides.com" }
  parts.website, parts.websiteIcon = linkField("help.websiteButton", "share", parts.link.text, function()
    ns.Dialogs.Copy("help.websiteButton", parts.link.address or ns.Website)
  end)
  parts.channel, parts.channelIcon = linkField("bar.channel", "play", CHANNEL.text, function()
    ns.Dialogs.Copy("bar.channel", CHANNEL.address)
  end)

  local close = W.Action(bar, { icon = "close", size = W.CLOSE_SIZE, tooltip = "common.close" })
  close:SetScript("OnClick", function()
    frame:Hide()
  end)
  parts.close = close
  local settings = W.Action(bar, { icon = "gear", size = 24, tooltip = "page.settings" })
  settings:SetScript("OnClick", function()
    ns.Router:navigate("settings")
  end)
  parts.gear = settings

  -- Quick language toggle next to the gear icon: shows which language is
  -- currently active (the "auto" setting in Settings still resolves to one
  -- of these two, ns.GetActiveLocale() always returns the resolved value)
  -- and switches it with one click instead of a trip through the Settings
  -- page. Selection ring on the active side mirrors K.ClassSwitcher,
  -- deliberately not color-only (see that widget for the same reasoning).
  local function setLocale(loc)
    ns.Store.set("settings.locale", loc)
    ns.SetLocale(loc)
    ns.RefreshUI()
    ns.Main.InvalidateViews()
  end
  local langToggle = CreateFrame("Frame", nil, bar)
  langToggle:SetSize(64, 22)
  local langDE = W.Button(langToggle, {
    text = "DE",
    variant = "ghost",
    width = 32,
    height = 22,
    tooltip = "settings.languageLabel",
    onClick = function()
      setLocale("deDE")
    end,
  })
  langDE:SetPoint("LEFT")
  local langEN = W.Button(langToggle, {
    text = "EN",
    variant = "ghost",
    width = 32,
    height = 22,
    tooltip = "settings.languageLabel",
    onClick = function()
      setLocale("enUS")
    end,
  })
  langEN:SetPoint("LEFT", langDE, "RIGHT", 4, 0)
  -- The default 8 px label padding leaves 12 px in a 28 px button, too little
  -- for two letters, so the text was cut to "...". Size to the widest label.
  -- Bound on the label so it runs after the label's own font refresh.
  local function fitLangButtons()
    local width = 32
    for _, b in ipairs({ langDE, langEN }) do
      b.label:ClearAllPoints()
      b.label:SetPoint("LEFT", 3, 0)
      b.label:SetPoint("RIGHT", -3, 0)
      width = math.max(width, math.ceil(b.label:GetStringWidth()) + 10)
    end
    langDE:SetWidth(width)
    langEN:SetWidth(width)
    langToggle:SetWidth(2 * width + 4)
  end
  ns.Bind(langEN.label, fitLangButtons)
  local langDERing = W.Border(langDE, "accent2", 1, 2)
  local langENRing = W.Border(langEN, "accent2", 1, 2)
  local function refreshLangToggle()
    local active = ns.GetActiveLocale()
    langDERing.show(active == "deDE")
    langENRing.show(active == "enUS")
  end
  refreshLangToggle()
  ns.On("FG_SETTING_CHANGED", function(_, path)
    if path == "settings.locale" then
      refreshLangToggle()
    end
  end)
  parts.lang, parts.langDE, parts.langEN = langToggle, langDE, langEN

  local help = W.Action(bar, { icon = "help", size = 26, tooltip = "page.help" })
  help:SetScript("OnClick", function()
    ns.Router:navigate("help")
  end)
  ns.Anchors["FG.Help"] = help
  parts.help = help
  local dock = W.Action(bar, { icon = "open", size = 26, tooltip = "dock.toggle" })
  dock:SetScript("OnClick", function()
    ns.Dock.Toggle()
  end)
  parts.dock = dock

  search = W.EditBox(bar, {
    placeholder = "search.placeholder",
    clear = true,
    height = SEARCH_HEIGHT,
    onEnter = function(text)
      text = U.trim(text):gsub("/", " ")
      if text ~= "" then
        ns.Router:navigate("search/" .. text)
      end
    end,
  })
  parts.search = search
  ns.Anchors["FG.Search"] = search
  Main.search = search
  return bar
end

-- Page header: room left of the title (back, forward), least title width before the buttons shrink to
-- their icons, size and gap of the buttons on the right.
local HEADER_LEFT, HEADER_TITLE_MIN = 74, 140
local HEADER_BUTTON_MAX, HEADER_BUTTON_HEIGHT, HEADER_BUTTON_GAP = 96, 24, 6

local function buildHeader(parent)
  local h = CreateFrame("Frame", nil, parent)
  h:SetHeight(Theme.size.contentHeader + 8)
  h.back = W.Action(h, { icon = "chevron-left", size = 24, tooltip = "nav.back" })
  h.back:SetScript("OnClick", function()
    ns.Router:goBack()
  end)
  h.fwd = W.Action(h, { icon = "chevron-right", size = 24, tooltip = "nav.forward" })
  h.fwd:SetScript("OnClick", function()
    ns.Router:goForward()
  end)
  -- The tour of the page (Tutorials.ForPage), shown left of the commands link on pages that have
  -- one. Made first so the keyboard reaches it before the commands, in screen order.
  h.tour = W.Action(h, {
    label = "act.tour",
    icon = "play",
    variant = "ghost",
    width = HEADER_BUTTON_MAX,
    height = HEADER_BUTTON_HEIGHT,
    tooltip = "nav.tour",
    tooltipText = "kit.tourTip",
    onClick = function()
      if h.tourId then
        ns.TutorialUI.Start(h.tourId)
      end
    end,
  })
  h.tour:Hide()
  ns.Anchors["FG.Header.Tour"] = h.tour
  -- One link for every page: the commands of the page's help area in chat and as a copy dialog.
  h.commands = W.Action(h, {
    label = "act.commands",
    icon = "info",
    variant = "ghost",
    width = HEADER_BUTTON_MAX,
    height = HEADER_BUTTON_HEIGHT,
    tooltip = "pagecmd.tip",
    onClick = function()
      ns.CommandHelp.OpenForPage((ns.RouterClass.parse(ns.Router.current)))
    end,
  })
  ns.Anchors["FG.Header.Commands"] = h.commands
  h.title = W.Text(h, { role = "h2", family = "heading", color = "text" })

  -- The labels of both buttons stay while the title keeps its room, else only the icons remain.
  local function fitButtons()
    local width = h:GetWidth()
    if not width or width <= 0 then
      return
    end
    local want = h.commands:FullWidth() + (h.tour:IsShown() and h.tour:FullWidth() + HEADER_BUTTON_GAP or 0)
    local room = width - HEADER_LEFT - 12 - HEADER_TITLE_MIN - 8
    local cap = want <= room and HEADER_BUTTON_MAX or 0
    h.commands:SetWidth(h.commands:Fit(cap))
    h.tour:SetWidth(h.tour:Fit(cap))
  end
  -- Arrows and title in the row under the title bar (the metal band in the skin "forever"), the links at its
  -- right edge. Both styles use this row as it is.
  local function placeRow()
    h.back:SetSize(24, 24)
    put(h.back, "LEFT", 12, -6)
    h.fwd:SetSize(24, 24)
    put(h.fwd, "LEFT", h.back, "RIGHT", 2, 0)
    h.commands:SetHeight(HEADER_BUTTON_HEIGHT)
    put(h.commands, "RIGHT", -12, -6)
    h.commands:Show()
    h.tour:SetHeight(HEADER_BUTTON_HEIGHT)
    put(h.tour, "RIGHT", h.commands, "LEFT", -HEADER_BUTTON_GAP, 0)
    h.tour:SetShown(h.tourId ~= nil)
    put(h.title, "LEFT", h.fwd, "RIGHT", 12, -2)
    h.title:SetPoint("RIGHT", h.tourId and h.tour or h.commands, "LEFT", -8, 0)
  end
  function h.place()
    placeRow()
    placeCrumbs()
    fitButtons()
  end
  function h:SetTour(tour)
    h.tourId = tour and tour.id or nil
    h.place()
  end
  h:SetTour(nil)
  h:SetScript("OnSizeChanged", fitButtons)
  ns.Bind(h, fitButtons)
  h.line = h:CreateTexture(nil, "BORDER")
  h.line:SetPoint("BOTTOMLEFT", 12, 0)
  h.line:SetPoint("BOTTOMRIGHT", -12, 0)
  h.line:SetHeight(1)
  ns.Bind(h.line, function(t)
    t:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)
  return h
end

-- Title bar: responsive in both styles ------------------------------------------------------------------------------

-- The title bar holds the logo and the name on the left, the link field in the middle, the search and the symbols
-- on the right. In the skin "forever" it sits in the metal band above the window (UI/WindowShell.lua) and replaces
-- the dark bar; the page header (arrows, title, tour and commands) is not part of it, it stays in the content
-- area under the bar like in the flat look. Nothing is built twice, layoutBar only anchors the controls again, for
-- the style in force and for the width of the window.

-- Gaps between symbols and between groups.
local BAR_GAP, BAR_GROUP = 4, 10
-- Sizes per style: the flat title bar keeps its larger symbols, the band takes smaller ones with room above and below
-- (pad = bar edge to logo, edge = bar edge to the close button).
local BAR_FLAT = { pad = 10, edge = 8, gear = 24, help = 26, dock = 26, web = 24, search = 26 }
local BAR_BAND = { pad = 6, edge = 4, gear = 20, help = 20, dock = 20, web = 20, search = 24 }
-- The link text of each middle field is at least this wide, the search box shrinks in two steps.
local LINK_MIN = 160
local SEARCH_NARROW, SEARCH_LEAST = 140, 120

-- What gives way when the width is short, first to last: the search box, both link texts (their symbols take their
-- place), the channel symbol, the text of the name, the compact window, help, then the search and the website symbol
-- (only below Layout.MIN_W).
local BAR_STEPS = {
  function(s)
    s.search = SEARCH_NARROW
  end,
  function(s)
    s.search = SEARCH_LEAST
  end,
  function(s)
    s.link, s.web, s.chan = false, true, true
  end,
  function(s)
    s.chan = false
  end,
  function(s)
    s.text = false
  end,
  function(s)
    s.dock = false
  end,
  function(s)
    s.help = false
  end,
  function(s)
    s.search = 0
  end,
  function(s)
    s.web = false
  end,
}

-- The band of the metal frame, current at any point of a refresh: the order of the refresh callbacks of the
-- shell and of this window is not defined, so the frame is asked to match the skin first (as the shell does).
local function bandRect()
  local shell = frame and ns.WindowShell.Of(frame)
  if not shell then
    return nil
  end
  ns.Skins.Apply(shell.edge, "nine")
  return ns.Skins.BandRect(shell.edge)
end

-- Tab order: the controls of the title bar are taken out of the list of the keyboard focus and put back as one
-- block where they were, in screen order (left to right) while the bar sits in the band. The rest of the list keeps
-- its order, and the way back puts every control to the place it had, so the flat look keeps its old order.
local function orderFocus(on)
  local items, flat, slots = ns.Focus.items, parts.focusFlat, parts.focusSlots
  if not (flat and slots) then
    return
  end
  local mine = {}
  for _, f in ipairs(flat) do
    mine[f] = true
  end
  local rest = {}
  for _, f in ipairs(items) do
    if not mine[f] then
      rest[#rest + 1] = f
    end
  end
  if #rest + #flat ~= #items then
    return
  end
  if on then
    for k, f in ipairs(parts.focusBand) do
      table.insert(rest, math.min(slots[1] + k - 1, #rest + 1), f)
    end
  else
    for k, f in ipairs(flat) do
      table.insert(rest, math.min(slots[k], #rest + 1), f)
    end
  end
  for i = 1, math.max(#items, #rest) do
    items[i] = rest[i]
  end
end

-- Sidebar and content. Flat: under the title bar. Forever: directly under the band, the dark bar is gone.
-- The content always hangs on the page header.
local function placeContent(rect)
  if rect then
    put(sidebar, "TOPLEFT", frame, "TOPLEFT", 0, math.min(0, rect.bottom))
  else
    put(sidebar, "TOPLEFT", parts.bar, "BOTTOMLEFT")
  end
  sidebar:SetPoint("BOTTOMLEFT", footer, "TOPLEFT")
  put(contentHost, "TOPLEFT", header, "BOTTOMLEFT")
  contentHost:SetPoint("BOTTOMRIGHT")
end

-- Lays out the title bar for the style and the width of the window: measures every part, lets parts give way in the
-- order of BAR_STEPS until the rest fits, then anchors everything (right edge leftwards, left edge rightwards, the
-- link field in the middle of the bar as far as the neighbours leave room).
layoutBar = function()
  local p = parts
  if not (frame and p.search) then
    return
  end
  local m = band.on and BAR_BAND or BAR_FLAT
  local metrics = ns.Skins.list.forever.metrics.bar
  local avail = frame:GetWidth() - (band.on and 2 * metrics.margin or 0)
  if not avail or avail <= 0 then
    return
  end
  local logoText = ns.WindowShell.Of(frame).titleText
  -- No control is taller than the bar minus the gap above and below it (everything is centered on the bar).
  local height = band.on and band.rect and band.rect.height or p.bar:GetHeight() or 0
  local cap = math.max(16, height - 2 * metrics.gap)
  local function square(f, natural)
    local side = math.min(natural, cap)
    f:SetSize(side, side)
    return side
  end
  for _, field in ipairs({ p.website, p.channel }) do
    field:SetWidth(math.max(LINK_MIN, math.ceil(field.label:GetStringWidth()) + 24))
  end
  local size = {
    logo = square(p.logo, LOGO_SIZE),
    gear = square(p.gear, m.gear),
    help = square(p.help, m.help),
    dock = square(p.dock, m.dock),
    web = square(p.websiteIcon, m.web),
    chan = square(p.channelIcon, m.web),
    lang = p.lang:GetWidth(),
    close = p.close:GetWidth(),
    link = p.website:GetWidth(),
    channel = p.channel:GetWidth(),
  }
  local textW = math.ceil(logoText:GetStringWidth())

  local state = { search = SEARCH_WIDTH, text = true, link = true, web = false, chan = false, dock = true, help = true }
  local function leftW(s)
    return m.pad + size.logo + (s.text and 8 + textW or 0)
  end
  local function rightW(s)
    local w = m.edge + size.close + BAR_GAP + size.gear + BAR_GROUP + size.lang
    w = w + (s.help and BAR_GAP + size.help or 0) + (s.dock and BAR_GAP + size.dock or 0)
    w = w + (s.web and BAR_GAP + size.web or 0) + (s.chan and BAR_GAP + size.chan or 0)
    return w + (s.search > 0 and BAR_GROUP + s.search or 0)
  end
  local function need(s)
    return leftW(s) + (s.link and BAR_GROUP + size.link + BAR_GAP + size.channel or 0) + BAR_GROUP + rightW(s)
  end
  local tier = 0
  while need(state) > avail and BAR_STEPS[tier + 1] do
    tier = tier + 1
    BAR_STEPS[tier](state)
  end
  band.tier, band.state = tier, state

  -- Right edge, leftwards.
  local prev
  local function right(f, gap, on)
    f:SetShown(on)
    if on then
      put(f, "RIGHT", prev or p.bar, prev and "LEFT" or "RIGHT", -gap, 0)
      prev = f
    end
  end
  right(p.close, m.edge, true)
  right(p.gear, BAR_GAP, true)
  right(p.lang, BAR_GROUP, true)
  right(p.help, BAR_GAP, state.help)
  right(p.dock, BAR_GAP, state.dock)
  right(p.channelIcon, BAR_GAP, state.chan)
  right(p.websiteIcon, BAR_GAP, state.web)
  p.search:SetSize(math.max(state.search, 1), math.min(m.search, cap))
  right(p.search, BAR_GROUP, state.search > 0)

  -- Left edge, rightwards: everything is placed by its offset from the bar.
  put(p.logo, "LEFT", p.bar, "LEFT", m.pad, 0)
  logoText:SetShown(state.text)
  if state.text then
    put(logoText, "LEFT", p.bar, "LEFT", m.pad + size.logo + 8, 0)
  end

  -- The link fields (website, then channel): centered as a pair on the bar, pushed aside only as far as the
  -- neighbours need.
  p.website:SetShown(state.link)
  p.channel:SetShown(state.link)
  if state.link then
    local pair = size.link + BAR_GAP + size.channel
    local lo = leftW(state) + BAR_GROUP
    local hi = avail - rightW(state) - BAR_GROUP - pair
    put(p.website, "LEFT", p.bar, "LEFT", math.max(lo, math.min(hi, (avail - pair) / 2)), 0)
    put(p.channel, "LEFT", p.website, "RIGHT", BAR_GAP, 0)
  end
end

-- Puts the title bar and the content where the style in force wants them. Runs on every ns.RefreshUI.
applyHeaderMode = function()
  if not (frame and header and content) then
    return
  end
  local rect = bandRect()
  if rect then
    band.rect = rect
    if not band.on then
      band.on = true
      orderFocus(true)
    end
  elseif band.on then
    band.on, band.rect = false, nil
    orderFocus(false)
  end
  placeContent(rect)
  layoutBar()
end

local function charLine()
  local _, classFile = UnitClass("player")
  local level = UnitLevel("player")
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  local className = classFile and L["class." .. classFile] or "?"
  local text = classFile and Theme.classColors[classFile] and Theme.hexText(classFile, className) or className
  local factionText = faction
      and (faction == "Alliance" and L["faction.alliance"] or faction == "Horde" and L["faction.horde"])
    or ""
  return string.format("%s %s%s", text, tostring(level or "?"), factionText ~= "" and (" · " .. factionText) or "")
end

-- Narrowest the data status of the footer is cut to.
local DATA_MIN = 24

local function buildFooter()
  local f = CreateFrame("Frame", nil, frame)
  f:SetPoint("BOTTOMLEFT")
  f:SetPoint("BOTTOMRIGHT")
  f:SetHeight(Theme.size.footer + 4)
  W.Fill(f, "surface", 1)
  local line = f:CreateTexture(nil, "BORDER")
  line:SetPoint("TOPLEFT")
  line:SetPoint("TOPRIGHT")
  line:SetHeight(1)
  ns.Bind(line, function(t)
    t:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)

  local data = CreateFrame("Button", nil, f)
  data:SetPoint("LEFT", 10, 0)
  data:SetHeight(18)
  data.text = W.Text(data, { role = "micro", color = "textMuted" })
  data.text:SetPoint("LEFT")
  data.text:SetPoint("RIGHT")
  local fitData
  ns.Bind(data, function()
    data.text:SetText(ns.DataStatusText())
    if fitData then
      fitData()
    else
      data:SetWidth(data.text:GetStringWidth() + 4)
    end
  end)
  data:SetScript("OnClick", function()
    ns.Router:navigate("help/data")
  end)
  W.AttachTooltip(data, "footer.dataTitle", "footer.dataText")
  ns.Anchors["FG.Footer.Data"] = data

  local char = W.Text(f, { role = "micro", color = "textSecondary", justify = "CENTER" })
  char:SetPoint("CENTER")
  ns.Bind(char, function(fs)
    fs:SetText(charLine())
  end)
  ns.On("PLAYER_LEVEL_UP", function()
    char:SetText(charLine())
  end)
  ns.Anchors["FG.Footer.Char"] = char

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function()
    frame:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    saveSize()
    savePosition()
    Main.Relayout()
  end)
  W.AttachTooltip(grip, "footer.resize")
  ns.Anchors["FG.Resize"] = grip

  local version = W.Text(f, { text = "v" .. ns.version, role = "micro", color = "textMuted" })
  version:SetPoint("RIGHT", grip, "LEFT", -8, 0)

  local controls = ns.FooterControls.Build(f)
  controls:SetPoint("RIGHT", version, "LEFT", -8, 0)
  ns.Anchors["FG.Footer.Controls"] = controls

  local errors = W.Button(f, {
    text = "",
    variant = "ghost",
    width = 80,
    height = 18,
    onClick = function()
      ns.Router:navigate("errors")
    end,
  })
  errors:SetPoint("RIGHT", controls, "LEFT", -8, 0)

  -- The data status gives way: the controls lose their sliders first (then their captions),
  -- the character line moves left when it would touch them, and the data status is cut to the
  -- room that is left. The controls themselves are never cut.
  function fitData()
    local width = f:GetWidth()
    local right = grip:GetWidth() + 10 + version:GetStringWidth() + 8
    local errorsWidth = errors:IsShown() and errors:GetWidth() + 8 or 0
    local charWidth = char:GetStringWidth()
    local dataWidth = data.text:GetStringWidth() + 4
    -- Space for data status, character line and the controls side by side (10, 8 and 12 are gaps).
    local shared = width - right - errorsWidth - 10 - charWidth - 12 - 8
    controls:Fit(shared - dataWidth, shared - DATA_MIN)
    local rightEdge = width - right - controls:GetWidth() - errorsWidth
    char:ClearAllPoints()
    if width / 2 + charWidth / 2 + 12 <= rightEdge then
      char:SetPoint("CENTER")
    else
      char:SetPoint("RIGHT", f, "RIGHT", -(width - rightEdge + 12), 0)
    end
    local charLeft = math.min(width / 2 - charWidth / 2, rightEdge - 12 - charWidth)
    data:SetWidth(U.clamp(dataWidth, DATA_MIN, math.max(DATA_MIN, math.min(charLeft - 18, rightEdge - 10))))
  end
  f:SetScript("OnSizeChanged", fitData)
  ns.On("FG_LAYOUT_CHANGED", fitData)
  ns.On("FG_UI_REFRESHED", fitData)
  local function paintErrors()
    local n = ns.Errors.sessionCount
    errors:SetShown(n > 0)
    errors.label:SetText(Theme.hexText("warning", "! " .. string.format(L["footer.errors"], n)))
    fitData()
  end
  ns.Bind(errors, paintErrors)
  ns.On("FG_ERRORS_CHANGED", paintErrors)
  return f
end

-- Blizzard panels live in strata "MEDIUM". Sharing it lets a click raise
-- either window, and a panel opened later lands above ours.
local function raiseOnPanelShow(panel)
  if type(panel) ~= "table" or InCombatLockdown() then
    return
  end
  pcall(panel.Raise, panel)
end

local function create()
  frame = CreateFrame("Frame", "ForeverGuidesMainFrame", UIParent)
  frame:SetFrameStrata("MEDIUM")
  frame:SetToplevel(true)
  if type(ShowUIPanel) == "function" and type(hooksecurefunc) == "function" then
    hooksecurefunc("ShowUIPanel", raiseOnPanelShow)
  end
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  applyBounds()
  W.Fill(frame, "bg", 0.96)
  ns.WindowShell.Attach(frame, {
    text = "FOREVER GUIDES",
    role = "h3",
    family = "display",
    titleHeight = Theme.size.titleBar,
    shadow = true,
    shadowScale = 0.6,
    fade = "main",
    band = true,
    bandSize = "main",
  })
  frame:Hide()

  buildTitleBar()
  footer = buildFooter()
  sidebar = ns.Sidebar.Create(frame)

  content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT")
  content:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT")
  header = buildHeader(content)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  contentHost = CreateFrame("Frame", nil, content)
  placeContent()
  ns.Anchors["FG.Content"] = contentHost
  ns.Anchors["FG.Main"] = frame

  frame:SetScript("OnSizeChanged", function()
    ns.Debounce("main-relayout", 0.1, Main.Relayout)
  end)
  frame:SetScript("OnMouseUp", function(_, button)
    if button == "Button4" then
      ns.Router:goBack()
    elseif button == "Button5" then
      ns.Router:goForward()
    end
  end)
  frame:SetScript("OnHide", function()
    ns.Popups.close()
    ns.Focus.clear()
    ns.Emit("FG_MAIN_HIDDEN")
  end)
  frame:SetScript("OnShow", function()
    ns.Emit("FG_MAIN_SHOWN")
  end)
  -- After the own OnShow/OnHide above, so no SetScript can replace the hooks of the Esc stack.
  -- Esc leaves a keyboard focus of the window first.
  ns.WindowShell.RegisterEsc(frame, function()
    if ns.Focus.current then
      ns.Focus.clear()
      return true
    end
  end)
  setupKeyboard()
  restoreGeometry()
  applyAlpha()
  parts.focusFlat = {
    parts.website,
    parts.websiteIcon,
    parts.channel,
    parts.channelIcon,
    parts.close,
    parts.gear,
    parts.langDE,
    parts.langEN,
    parts.help,
    parts.dock,
    parts.search,
  }
  parts.focusSlots = {}
  for k, f in ipairs(parts.focusFlat) do
    for i, item in ipairs(ns.Focus.items) do
      if item == f then
        parts.focusSlots[k] = i
      end
    end
  end
  -- Screen order of the title bar, left to right.
  parts.focusBand = {
    parts.website,
    parts.channel,
    parts.search,
    parts.websiteIcon,
    parts.channelIcon,
    parts.dock,
    parts.help,
    parts.langDE,
    parts.langEN,
    parts.gear,
    parts.close,
  }
  ns.Bind(header, applyHeaderMode)
  ns.On("FG_UI_REFRESHED", layoutBar)
  frame:HookScript("OnSizeChanged", layoutBar)
  ns.Router.onChange = onRoute
  Main.frame = frame
end

-- Public -----------------------------------------------------------------------

-- The link field in the middle of the title bar: the text and the address its copy dialog shows.
function Main.SetBarLink(text, address)
  parts.link.text, parts.link.address = text, address
  if parts.website then
    parts.website.label:SetText(text)
    layoutBar()
  end
end

function Main.Show(path)
  if not frame then
    create()
  end
  frame:Show()
  Main.Relayout()
  if path then
    ns.Router:navigate(path)
  elseif not ns.Router.current then
    ns.Router:navigate(ns.Router:get(ns.charDB.lastRoute or "") and ns.charDB.lastRoute or "dashboard")
  end
end

function Main.Hide()
  if frame then
    frame:Hide()
  end
end

function Main.Toggle()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    Main.Show()
  end
end

function Main.IsShown()
  return frame ~= nil and frame:IsShown()
end

ns.On("PLAYER_LOGOUT", function()
  if frame then
    savePosition()
  end
end)

ns.On("PLAYER_REGEN_DISABLED", function()
  if ns.db and ns.db.settings.combatHide and Main.IsShown() then
    Main.wasShownBeforeCombat = true
    frame:Hide()
  end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  if Main.wasShownBeforeCombat then
    Main.wasShownBeforeCombat = nil
    Main.Show()
  end
end)

local function reclamp()
  if frame then
    restoreGeometry()
  end
end
ns.On("UI_SCALE_CHANGED", reclamp)
ns.On("DISPLAY_SIZE_CHANGED", reclamp)
