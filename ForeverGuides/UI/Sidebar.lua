-- Left navigation: grouped page list, active state, collapses to an icon rail. The list follows the
-- default menu (page registry) plus the layout of the user (Modules/NavLayoutLogic.lua); the edit
-- window that changes that layout is UI/NavEditor.lua.
local _, ns = ...
local W, Theme, L, NL = ns.W, ns.Theme, ns.L, ns.NavLayout

-- Group ids are stable (saved accordion state, saved layouts); order and title key
-- "nav.group.<id>" follow from this list. A group without a listed page gets no header.
local GROUPS =
  { "main", "world", "character", "social", "learn", "professions", "guides", "inventory", "tools", "system" }
local HEADER_HEIGHT = 24
local ITEM_HEIGHT = 28
-- Box around a group: it starts BOX_X from the edge of the list, the rows sit ROW_X from it (so the box shows
-- as a frame of ROW_X - BOX_X px), BOX_PAD above the header and below the last row. A custom color fills at BOX_ALPHA.
local BOX_X, ROW_X, BOX_PAD, BOX_GAP, BOX_ALPHA = 3, 5, 2, 3, 0.3
local PENCIL_SIZE = 20

-- Short menu names for pages whose title is long (page.navTitle, a locale key, wins over this list). The page keeps
-- its full title in the page header, the crumbs and the search.
local NAV_TITLES = {
  shots = "nav.title.shots",
  proftrainers = "nav.title.proftrainers",
  cursor = "nav.title.cursor",
  weapons = "nav.title.weapons",
  instances = "nav.title.instances",
  gathering = "nav.title.gathering",
  professionroute = "nav.title.professionroute",
}

ns.AddLocale("enUS", {
  ["sidebar.groupHint"] = "Click to expand or collapse",
  ["nav.shareHint"] = "Right-click: share link",
  ["nav.customizeGroup"] = "Customize section",
  ["nav.title.shots"] = "Screenshots",
  ["nav.title.proftrainers"] = "Prof. trainers",
  ["nav.title.cursor"] = "Cursor ring",
  ["nav.title.weapons"] = "Weapon skills",
  ["nav.title.instances"] = "Dungeons & raids",
  ["nav.title.gathering"] = "Ores & herbs",
  ["nav.title.professionroute"] = "Prof. route",
})
ns.AddLocale("deDE", {
  ["sidebar.groupHint"] = "Klick zum Auf- oder Zuklappen",
  ["nav.shareHint"] = "Rechtsklick: Link teilen",
  ["nav.customizeGroup"] = "Bereich anpassen",
  ["nav.title.shots"] = "Screenshots",
  ["nav.title.proftrainers"] = "Berufslehrer",
  ["nav.title.cursor"] = "Mauszeiger",
  ["nav.title.weapons"] = "Waffen",
  ["nav.title.instances"] = "Instanzen",
  ["nav.title.gathering"] = "Sammeln",
  ["nav.title.professionroute"] = "Berufsroute",
})

-- Locale key of the menu entry of a page.
local function navKey(page)
  return page.navTitle or NAV_TITLES[page.id] or page.title
end

local function isOpen(group)
  local open = ns.db.settings.sidebarOpen
  if type(open) == "table" and open[group] ~= nil then
    return open[group] ~= false
  end
  return ns.Store.defaults.settings.sidebarOpen[group] == true
end

local Sidebar = {}
ns.Sidebar = Sidebar
Sidebar.GROUPS = GROUPS
Sidebar.HEADER_HEIGHT, Sidebar.ITEM_HEIGHT = HEADER_HEIGHT, ITEM_HEIGHT
Sidebar.NavKey = navKey

-- Room around a label: item = icon column left and the right pad, header = chevron column and the right pad, plus
-- the edge line and the scroll area inset.
local ITEM_ROOM, HEADER_ROOM, EDGE_ROOM = 45, 30 + PENCIL_SIZE + 2, 2 + 2 * ROW_X

-- Moves the entries of `frames` (rows and their edit controls, in display order) to the slots they
-- already hold in the focus list, so Tab and the arrow keys follow what is on screen.
local function syncFocusOrder(frames)
  local wanted = {}
  for _, frame in ipairs(frames) do
    wanted[frame] = true
  end
  local slots = {}
  for i, frame in ipairs(ns.Focus.items) do
    if wanted[frame] then
      slots[#slots + 1] = i
    end
  end
  if #slots ~= #frames then
    return
  end
  for k, i in ipairs(slots) do
    ns.Focus.items[i] = frames[k]
  end
end

Sidebar.SyncFocusOrder = syncFocusOrder

-- Fill of a group box with a user color ("rrggbb"): returns r, g, b, alpha of the texture. The color is darkened
-- toward black until the muted and the secondary text keep the minimum contrast on the fill as it shows on the surface.
function Sidebar.BoxFill(hex)
  local surface = Theme.hex("surface")
  local color = "#" .. hex
  for step = 0, 20 do
    color = step == 0 and "#" .. hex or Theme.mix("#" .. hex, "#000000", step * 0.05)
    local shown = Theme.mix(surface, color, BOX_ALPHA)
    if
      Theme.contrastRatio(Theme.hex("textMuted"), shown) >= Theme.MIN_CONTRAST
      and Theme.contrastRatio(Theme.hex("textSecondary"), shown) >= Theme.MIN_CONTRAST
    then
      break
    end
  end
  local r, g, b = ns.U.hex(color)
  return r, g, b, BOX_ALPHA
end

function Sidebar.Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  W.Fill(f, "surface", 1)
  local edge = f:CreateTexture(nil, "BORDER")
  edge:SetPoint("TOPRIGHT")
  edge:SetPoint("BOTTOMRIGHT")
  edge:SetWidth(1)
  ns.Bind(edge, function(t)
    t:SetColorTexture(Theme.fillColor("line"))
  end)

  -- Same logo asset as the title bar; the icon rail has no room next to the arrow.
  local logo = W.Action(f, {
    texture = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png",
    size = 28,
    tooltip = "page.dashboard",
  })
  logo:SetPoint("TOPLEFT", 8, -4)
  logo:SetScript(
    "OnClick",
    ns.Wrap("sidebar-logo", function()
      ns.Router:navigate("dashboard")
    end)
  )
  f.logo = logo

  local toggle = W.Action(f, { icon = "chevron-left", size = 24, tooltip = "sidebar.toggle" })
  toggle:SetPoint("TOPRIGHT", -10, -6)
  toggle:SetScript(
    "OnClick",
    ns.Wrap("sidebar-toggle", function()
      ns.Store.set("settings.sidebarCollapsed", not ns.db.settings.sidebarCollapsed)
      ns.Main.Relayout()
    end)
  )
  f.toggle = toggle
  -- Right behind the arrow, so the pencil sits there in the Tab order too.
  ns.NavEditor.Attach(f)

  local area = W.ScrollArea(f)
  area:SetPoint("TOPLEFT", 0, -34)
  area:SetPoint("BOTTOMRIGHT", -1, 4)
  f.area = area
  local content = area.content
  f.items = {}
  f.headers = {}

  -- Headers and buttons are made once per group and page and reused by Rebuild.
  local headerOf, buttonOf = {}, {}

  local function groupName(h)
    return h.entry and h.entry.name or L["nav.group." .. h.group]
  end

  local function pageName(b)
    return b.entry and b.entry.name or L[navKey(b.page)]
  end

  local function newHeader(group)
    local header = CreateFrame("Button", nil, content)
    header:SetHeight(HEADER_HEIGHT)
    header.group = group
    header.items = {}
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.arrow = W.Glyph(header, "chevron-down", 12, "textMuted")
    header.arrow:SetPoint("LEFT", 8, 0)
    header.label = W.Text(header, { key = "nav.group." .. group, role = "micro", color = "textMuted" })
    header.label:SetPoint("LEFT", header.arrow, "RIGHT", 4, 0)
    header:SetScript(
      "OnClick",
      ns.Wrap("sidebar-group", function()
        ns.Store.set("settings.sidebarOpen." .. group, not isOpen(group))
        f:Layout(f.collapsed)
      end)
    )
    -- Mouse and keyboard focus share one look: the hover fill and the bright label.
    local function paint(self)
      local hot = self.hover or self.focused
      self.bg:SetColorTexture(Theme.fillColor(hot and "hover" or nil))
      W.SetColor(self.label, hot and "text" or "textMuted")
      self.arrow:SetColorToken(hot and "text" or "textMuted")
      if self.pencil then
        self.pencil:SetAlpha((hot or self.pencil.hover) and 1 or 0)
      end
    end
    ns.Bind(header, function(self)
      paint(self)
    end)
    header:SetScript("OnEnter", function(self)
      self.hover = true
      paint(self)
      ns.ShowTooltip(self, groupName(self), L["sidebar.groupHint"])
    end)
    header:SetScript("OnLeave", function(self)
      self.hover = false
      paint(self)
      ns.HideTooltip()
    end)
    header.fgOnFocus = function(self)
      self.focused = true
      paint(self)
    end
    header.fgOnBlur = function(self)
      self.focused = false
      paint(self)
    end
    -- After the header's own OnEnter and OnLeave (a later SetScript would drop the hooks). It shows on hover and
    -- focus; a click opens the nav editor and does not reach the header, so the group stays as it is.
    local pencil = W.Action(header, {
      icon = "pencil",
      size = PENCIL_SIZE,
      tooltip = "nav.customizeGroup",
      opens = true,
      onClick = function()
        ns.NavEditor.Open(group)
      end,
    })
    pencil:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    pencil:SetAlpha(0)
    for _, script in ipairs({ "OnEnter", "OnLeave" }) do
      pencil:HookScript(script, function(self)
        self.hover = script == "OnEnter"
        paint(header)
      end)
    end
    header.pencil = pencil
    header.fgLabelStop = pencil
    header.label:SetPoint("RIGHT", pencil, "LEFT", -2, 0)
    header.sep = content:CreateTexture(nil, "ARTWORK")
    header.sep:SetHeight(1)
    ns.Bind(header.sep, function(t)
      t:SetColorTexture(Theme.fillColor("line"))
    end)
    header.sep:Hide()
    ns.Focus.register(header, function(self)
      self:Click()
    end)
    return header
  end

  local function newItem(page)
    local b = CreateFrame("Button", nil, content)
    b:SetHeight(ITEM_HEIGHT)
    b.page = page
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    b.bar:SetWidth(3)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 13, 0)
    b.icon:SetTexture(ns.ResolveIcon(page.icon, ns.ICONS_FALLBACK[page.id]))
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.label = W.Text(b, { key = navKey(page), role = "ui", color = "textSecondary" })
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    -- A page with page.badge shows a dot on its icon while the function returns true (a page with news).
    b.dot = b:CreateTexture(nil, "OVERLAY")
    b.dot:SetSize(8, 8)
    b.dot:SetPoint("CENTER", b.icon, "TOPRIGHT", -1, -1)
    ns.Bind(b.dot, function(t)
      t:SetColorTexture(Theme.color("warning"))
    end)
    b.dot:Hide()
    -- page.counter() -> text such as "5/9", right-aligned in the row (refreshed with the badges).
    if type(page.counter) == "function" then
      b.count = W.Text(b, { role = "ui", color = "textMuted", justify = "RIGHT" })
      b.count:SetPoint("RIGHT", -8, 0)
      b.label:ClearAllPoints()
      b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
      b.label:SetPoint("RIGHT", b.count, "LEFT", -4, 0)
    end
    if page.placeholder then
      -- A page that is not built yet: muted row with a small badge instead of a word.
      b.soon = W.Badge(b, "common.soonShort", "textMuted")
      b.soon:SetPoint("RIGHT", -8, 0)
      b.label:ClearAllPoints()
      b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
      b.label:SetPoint("RIGHT", b.soon, "LEFT", -4, 0)
    end
    -- The skin may change while the window is open: the row follows it on every refresh.
    ns.Bind(b, function(self)
      if f.paintItem then
        f.paintItem(self)
      end
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Share icon on hover and focus (the full sidebar only); the right click stays for the icon rail. A page with
    -- shareable = false has neither.
    local shareable = not page.placeholder and ns.PageShare.Shareable(page.id)
    b:SetScript(
      "OnClick",
      ns.Wrap("sidebar", function(_, button)
        if button ~= "RightButton" then
          ns.Router:navigate(b.page.id)
        elseif shareable then
          ns.PageShare.OpenPayload(b.page.id)
        end
      end)
    )
    b:SetScript("OnEnter", function(self)
      self.hover = true
      f.paintItem(self)
      local hint = self.page.placeholder and L["common.soon"] or nil
      if self.dot:IsShown() and self.page.badgeHint then
        hint = L[self.page.badgeHint]
      end
      if shareable then
        hint = hint and (hint .. "\n" .. L["nav.shareHint"]) or L["nav.shareHint"]
      end
      ns.ShowTooltip(self, pageName(self), hint)
    end)
    b:SetScript("OnLeave", function(self)
      self.hover = false
      f.paintItem(self)
      ns.HideTooltip()
    end)
    -- After the row's own OnEnter and OnLeave: a later SetScript would drop the hooks of the icon.
    if shareable then
      b.share = ns.PageShare.RowButton(b, { size = 20, target = page.id })
      b.share:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    end
    b.fgOnFocus = function(self)
      self.focused = true
      f.paintItem(self)
    end
    b.fgOnBlur = function(self)
      self.focused = false
      f.paintItem(self)
    end
    ns.Focus.register(b, function(self)
      self:Click()
    end)
    b.fgScrollIntoView = function(self)
      local top = -select(5, self:GetPoint(1))
      if top < area:GetVerticalScroll() or top + ITEM_HEIGHT > area:GetVerticalScroll() + area:GetHeight() then
        area:ScrollTo(top - 20)
      end
    end
    return b
  end

  -- One box per group (behind the rows, no mouse): theme fill by default, the user color when the layout has one.
  local boxOf = {}
  f.boxes = boxOf

  local function paintBox(box)
    if box.color then
      box.fill:SetColorTexture(Sidebar.BoxFill(box.color))
    else
      box.fill:SetColorTexture(Theme.fillColor("rowRest"))
    end
  end

  local function boxFor(group)
    local box = boxOf[group]
    if not box then
      box = CreateFrame("Frame", nil, content)
      box:SetFrameLevel(content:GetFrameLevel())
      box.fill = box:CreateTexture(nil, "BACKGROUND")
      box.fill:SetAllPoints()
      W.Border(box, "white")
      ns.Bind(box, paintBox)
      boxOf[group] = box
    end
    return box
  end

  local function defaultPages()
    local out = {}
    for _, page in ipairs(ns.Router:list()) do
      if page.sidebar ~= false then
        out[#out + 1] = page
      end
    end
    return out
  end

  -- Lists the menu: a group without a listed page gets no header and no gap in the icon rail, hidden
  -- entries and groups are left out.
  local function populate()
    f.items, f.headers = {}, {}
    local view = NL.Resolve(GROUPS, defaultPages(), (NL.Layout()), false)
    for _, group in ipairs(view.groups) do
      local h = headerOf[group.id] or newHeader(group.id)
      headerOf[group.id] = h
      h.entry, h.items = group, {}
      if group.name then
        W.SetText(h.label, nil, group.name)
      else
        W.SetText(h.label, "nav.group." .. group.id)
      end
      h.color = group.color
      f.headers[#f.headers + 1] = h
      for index, entry in ipairs(group.pages) do
        local b = buttonOf[entry.id] or newItem(entry.page)
        buttonOf[entry.id] = b
        b.page, b.entry, b.parentEntry, b.navGroup, b.navIndex = entry.page, entry, group, group.id, index
        if entry.name then
          W.SetText(b.label, nil, entry.name)
        else
          W.SetText(b.label, navKey(entry.page))
        end
        h.items[#h.items + 1] = b
        f.items[#f.items + 1] = b
      end
    end
  end
  populate()

  -- Shows or hides the dot of every entry whose page has a badge function.
  function f:RefreshBadges()
    for _, b in ipairs(f.items) do
      local on = false
      if type(b.page.badge) == "function" then
        local _, value = ns.Safe("nav-badge", b.page.badge)
        on = value == true
      end
      b.dot:SetShown(on)
      if b.count then
        local _, text = ns.Safe("nav-counter", b.page.counter)
        b.count:SetText(type(text) == "string" and text or "")
      end
    end
  end
  f:RefreshBadges()

  -- A file the client did not know at the last check is tried again each time the window opens.
  function f:RefreshIcons()
    ns.NextIconEpoch()
    for _, b in ipairs(f.items) do
      b.icon:SetTexture(ns.ResolveIcon(b.page.icon, ns.ICONS_FALLBACK[b.page.id]))
    end
  end
  -- The main window sets its own OnShow later, which would drop a hook on it: follow its open event instead.
  ns.On("FG_MAIN_SHOWN", function()
    f:RefreshIcons()
    f:RefreshBadges()
  end)

  -- One look per state: active = selected fill, accent bar and label; hover and keyboard focus = hover
  -- fill and bright label; a page that is not built yet stays muted.
  function f.paintItem(b)
    local hot = b.hover or b.focused
    b.bar:SetColorTexture(Theme.color("accent2"))
    b.bar:SetShown(b.active == true)
    b.bg:SetColorTexture(Theme.fillColor(b.active and "selected" or hot and "hover" or nil))
    local soon = b.page.placeholder
    W.SetColor(b.label, b.active and "accent" or hot and "text" or soon and "textMuted" or "textSecondary")
    b.icon:SetAlpha(soon and not hot and not b.active and 0.55 or 1)
  end

  -- True while the label of a row is cut short (the tooltip then names the page in full).
  function f.Truncated(b)
    local label = b.label
    if type(label.IsTruncated) == "function" then
      local ok, cut = pcall(label.IsTruncated, label)
      if ok and type(cut) == "boolean" then
        return cut
      end
    end
    local room = label:GetWidth()
    return type(room) == "number" and room > 0 and label:GetStringWidth() > room + 0.5
  end

  -- Width the full sidebar needs: the longest label of a page or group plus its room, in px (Layout.sidebarWidth
  -- bounds it to 184..220). The icon rail does not use it.
  function f:WantedWidth()
    local need = 0
    for _, b in ipairs(f.items) do
      local room = ITEM_ROOM + (b.soon and b.soon:GetWidth() + 6 or 0)
      need = math.max(need, math.ceil(b.label:GetStringWidth()) + room)
    end
    for _, h in ipairs(f.headers) do
      need = math.max(need, math.ceil(h.label:GetStringWidth()) + HEADER_ROOM)
    end
    return need + EDGE_ROOM
  end

  local function paintActive(b, id)
    b.active = b.page.id == id
    f.paintItem(b)
  end

  function f:SetActive(id)
    local reveal
    f.activeId = id
    for _, b in ipairs(f.items) do
      paintActive(b, id)
      if b.active and not isOpen(b.navGroup) then
        ns.Store.set("settings.sidebarOpen." .. b.navGroup, true)
        reveal = b
      end
    end
    if reveal then
      f:Layout(f.collapsed)
      reveal:fgScrollIntoView()
    end
  end

  -- Reads the registered pages and the layout again (a sub-addon was switched on or off, the layout
  -- changed). The open and closed groups live in the settings, the scroll position, the marked page
  -- and the keyboard focus are carried over.
  function f:Rebuild()
    local scroll = area:GetVerticalScroll()
    local focus = ns.Focus.current
    for _, h in pairs(headerOf) do
      h:Hide()
    end
    for _, box in pairs(boxOf) do
      box:Hide()
    end
    for _, b in pairs(buttonOf) do
      b:Hide()
    end
    populate()
    f:RefreshBadges()
    for _, b in ipairs(f.items) do
      paintActive(b, f.activeId)
    end
    f:Layout(f.collapsed)
    area:ScrollTo(scroll)
    local frames = {}
    for _, h in ipairs(f.headers) do
      frames[#frames + 1] = h
      for _, b in ipairs(h.items) do
        frames[#frames + 1] = b
      end
    end
    syncFocusOrder(frames)
    if focus and focus:IsVisible() then
      ns.Focus.set(focus)
    end
  end

  function f:Layout(collapsed)
    f.collapsed = collapsed
    toggle.icon:SetIcon(collapsed and "chevron-right" or "chevron-left")
    logo:SetShown(not collapsed)
    toggle:ClearAllPoints()
    if collapsed then
      toggle:SetPoint("TOP", 0, -6)
    else
      toggle:SetPoint("TOPRIGHT", -10, -6)
    end
    f.fgEdit.toggle:SetShown(not collapsed)
    local y = -4
    for _, h in ipairs(f.headers) do
      local open = isOpen(h.group)
      h:ClearAllPoints()
      h:SetShown(not collapsed)
      h.arrow:SetIcon(open and "chevron-down" or "chevron-right")
      if collapsed and h ~= f.headers[1] then
        h.sep:ClearAllPoints()
        h.sep:SetPoint("TOPLEFT", content, "TOPLEFT", 10, y - 3)
        h.sep:SetPoint("RIGHT", content, "RIGHT", -10, 0)
        h.sep:Show()
      else
        h.sep:Hide()
      end
      local box = boxFor(h.group)
      local boxTop = y - BOX_GAP
      h.pencil:SetShown(not collapsed)
      if not collapsed then
        y = boxTop - BOX_PAD
        h:SetPoint("TOPLEFT", content, "TOPLEFT", ROW_X, y)
        h:SetPoint("RIGHT", content, "RIGHT", -ROW_X, 0)
        h.navTop, h.navHeight = -y, HEADER_HEIGHT
        y = y - HEADER_HEIGHT
      else
        h.navTop = nil
        y = y - 8
      end
      -- The icon rail lists every page, the accordion only filters the full sidebar.
      local show = collapsed or isOpen(h.group)
      for _, b in ipairs(h.items) do
        b:ClearAllPoints()
        b:SetShown(show)
        b.label:SetShown(not collapsed)
        if b.soon then
          b.soon:SetShown(not collapsed)
        end
        if b.share then
          b.share:SetShown(not collapsed)
        end
        if show then
          b:SetPoint("TOPLEFT", content, "TOPLEFT", collapsed and 0 or ROW_X, y)
          b:SetPoint("RIGHT", content, "RIGHT", collapsed and 0 or -ROW_X, 0)
          b.navTop, b.navHeight = -y, ITEM_HEIGHT
          y = y - ITEM_HEIGHT
        else
          b.navTop = nil
        end
      end
      box.color = h.color
      box:ClearAllPoints()
      box:SetShown(not collapsed)
      if not collapsed then
        y = y - BOX_PAD
        box:SetPoint("TOPLEFT", content, "TOPLEFT", BOX_X, boxTop)
        box:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -BOX_X, y)
        paintBox(box)
      end
    end
    area:SetContentHeight(-y + 8)
  end

  ns.Anchors["FG.Sidebar"] = f
  return f
end

-- A page changed what its badge says (a page with news was opened).
ns.On("FG_NAV_BADGE", function()
  local f = ns.Anchors["FG.Sidebar"]
  if f then
    f:RefreshBadges()
  end
end)

-- The layout changed: the sidebar is built again.
ns.On("FG_NAV_CHANGED", function()
  local f = ns.Anchors["FG.Sidebar"]
  if f then
    f:Rebuild()
  end
end)
