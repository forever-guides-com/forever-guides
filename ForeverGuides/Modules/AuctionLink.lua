-- Side tab at the auction house window (AuctionHouseFrame, load on demand with Blizzard_AuctionHouseUI;
-- AuctionFrame on the classic layout) with a small docked window of two tabs. "Shopping list": the list of
-- the chosen profession route with tick boxes and the buttons "Send to shopping list" and "Copy as text".
-- "Settings": price data, the full scan and the options of the price database (AuctionSettings.lua).
-- Without a chosen route the list tab only says so and offers the route page. The list tab shows the same rows as the
-- shopping window (S.View, ProfessionShop.lua): icon and quality colored name, have/need per row, the
-- view (combined or by reason) and the craft or buy choice. A click on a row searches the item in this window (RowClick), the box
-- ticks it, "Details" in the title opens the shopping window. The panel opens by itself with the
-- auction house while the list has open positions (setting autoOpen, default on), on the list tab;
-- closing it by hand keeps it closed until the next visit. The tab chosen last is kept for the session.
-- Like every control here it is not on the Tab ring of the main window (the ring must not reach a
-- Blizzard window); the panel has a small keyboard walk of its own that only listens while a control
-- of it has the focus (or Tab is pressed over it) and passes every other key on.
--
-- The window does not exist before the first visit, so it is looked up on AUCTION_HOUSE_SHOW and on
-- the interaction manager event for the auctioneer; whichever fires first builds, the other finds
-- it built. Nothing is built in combat (the window may be protected), PLAYER_REGEN_ENABLED builds
-- it afterwards. The connected addon starts its search itself when a list is created while the
-- auction house is open, so the existing S.Send is all that is needed.
local _, ns = ...
local W, L, K = ns.W, ns.L, ns.PageKit
local S, SW = ns.ProfessionShop, ns.ProfessionShopWindow

local A = {}
ns.AuctionLink = A

ns.AddLocale("enUS", {
  ["auctionlink.tab"] = "Forever Guides: Auction house",
  ["auctionlink.tab.tip"] = "Shopping list, price data and the full scan.",
  ["auctionlink.title"] = "Auction house",
  ["auctionlink.tabShop"] = "Shopping list",
  ["auctionlink.tabShop.tip"] = "The shopping list of your profession route.",
  ["auctionlink.tabSettings"] = "Settings",
  ["auctionlink.tabSettings.tip"] = "Price data, full scan and options.",
  ["auctionlink.pick"] = "Pick a profession route first",
  ["auctionlink.open"] = "Open profession route",
  ["auctionlink.noApi"] = "No list add-on found.",
  ["auctionlink.details"] = "Details",
  ["auctionlink.detailsTip"] = "Opens the shopping list window.",
})
ns.AddLocale("deDE", {
  ["auctionlink.tab"] = "Forever Guides: Auktionshaus",
  ["auctionlink.tab.tip"] = "Einkaufsliste, Preisdaten und kompletter Scan.",
  ["auctionlink.title"] = "Auktionshaus",
  ["auctionlink.tabShop"] = "Einkaufsliste",
  ["auctionlink.tabShop.tip"] = "Die Einkaufsliste deiner Berufsroute.",
  ["auctionlink.tabSettings"] = "Einstellungen",
  ["auctionlink.tabSettings.tip"] = "Preisdaten, kompletter Scan und Optionen.",
  ["auctionlink.pick"] = "Wähle zuerst eine Berufsroute",
  ["auctionlink.open"] = "Berufsroute öffnen",
  ["auctionlink.noApi"] = "Kein Listen-Addon gefunden.",
  ["auctionlink.details"] = "Details",
  ["auctionlink.detailsTip"] = "Öffnet das Einkaufslisten-Fenster.",
})

local HOSTS = { "AuctionHouseFrame", "AuctionFrame" }
local TAB_INSET, TAB_DROP, TAB_SIZE = 4, 40, 52 -- as the side tabs of the other windows
local PANEL_W, PANEL_H = 460, 546
local PAGE_TOP, TABS_TOP = 70, 38 -- the pages start below the title and the tab row
local PANEL_GAP = 4 -- between the tab and the panel
local PAD, ROW_H, BOX, ICON = 8, 22, 16, 18
local PROG_W, CRAFT_W, MAG = 62, 40, 12
local SEP_GAP = 8 -- space above a group of the by reason view, narrower than in the window
local INDENT = 12 -- per level of a material under a crafted item
local BUTTON_H = 26
local LEVEL, LEVEL_CAP, RING_BOOST = 45, 9990, 30
local REFRESH_DELAY, LAYOUT_DELAY = 0.5, 0.05
local RETRY_DELAY = 0.3

-- Host window -> { tab, panel, ... }, false after a failed build (no retry on every event).
local parts = {}

local function usable(frame)
  return type(frame) == "table" and type(frame.GetFrameLevel) == "function" and type(frame.IsShown) == "function"
end

-- The auction house window of this client: the shown one, else the first that exists.
local function hostFrame()
  local first
  for _, name in ipairs(HOSTS) do
    local frame = rawget(_G, name)
    if usable(frame) then
      local ok, shown = pcall(frame.IsShown, frame)
      if ok and shown then
        return frame
      end
      first = first or frame
    end
  end
  return first
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- Rows -------------------------------------------------------------------------------------------

local PARTS = { "box", "icon", "name", "mag", "prog" }

local function newRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_H)
  row.hover = row:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(1, 1, 1, 0)
  -- Section header of the by reason view.
  SW.NewSeparator(row, SEP_GAP, PAD)
  row.headBg = W.Fill(row, "surface2", 0.9)
  row.headTotal = W.Text(row, { role = "micro", color = "accent2", justify = "RIGHT" })
  row.headTotal:SetPoint("RIGHT", -PAD, 0)
  row.headTotal:SetWidth(PROG_W + CRAFT_W)
  row.head = W.Text(row, { role = "ui", color = "accent2" })
  row.head:SetPoint("LEFT", PAD, 0)
  row.head:SetPoint("RIGHT", row.headTotal, "LEFT", -4, 0)
  row.head:SetMaxLines(1)
  row.box = CreateFrame("Button", nil, row)
  row.box:SetSize(BOX, BOX)
  row.box:SetPoint("LEFT", PAD, 0)
  row.box:SetHitRectInsets(-4, -4, -3, -3)
  W.Fill(row.box, "surface2")
  row.boxOn = W.Fill(row.box, "action", 1)
  row.boxBorder = W.Border(row.box, "white", 0.4)
  row.mark = W.CheckMark(row.box, 12, "text")
  row.mark:SetPoint("CENTER")
  row.prog = W.Text(row, { role = "micro", justify = "RIGHT" })
  row.prog:SetPoint("RIGHT", -PAD, 0)
  row.prog:SetWidth(PROG_W)
  -- Craft yourself or buy at the auction house (only on items that can be crafted).
  row.craft = CreateFrame("Button", nil, row)
  row.craft:SetSize(CRAFT_W, 16)
  row.craft:SetPoint("RIGHT", row.prog, "LEFT", -4, 0)
  row.craft.hl = row.craft:CreateTexture(nil, "BACKGROUND")
  row.craft.hl:SetAllPoints()
  row.craft.hl:SetColorTexture(1, 1, 1, 0)
  W.Border(row.craft, "accent2", 0.5)
  row.craft.text = W.Text(row.craft, { role = "micro", color = "accent2", justify = "CENTER" })
  row.craft.text:SetPoint("CENTER")
  -- A magnifier behind the name: a click on the row searches the item.
  row.mag = W.Glyph(row, "search", MAG, "textMuted")
  row.mag:SetPoint("RIGHT", row.craft, "LEFT", -2, 0)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.name = W.Text(row, { role = "ui" })
  row.name:SetMaxLines(1)
  -- The box ticks, the rest of the row searches (left), copies the name (right) or links it (Shift).
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnEnter", function(self)
    self.hover:SetColorTexture(1, 1, 1, 0.1)
    if self.line then
      self.mag:SetColorToken("accent2")
      S.RowTooltip(self, self.line)
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.hover:SetColorTexture(1, 1, 1, 0)
    self.mag:SetColorToken("textMuted")
    ns.HideTooltip()
  end)
  row:SetScript(
    "OnClick",
    ns.Wrap("auctionlink-row", function(self, button)
      S.RowClick(self.line, button)
    end)
  )
  row.box:SetScript(
    "OnClick",
    ns.Wrap("auctionlink-tick", function()
      SW.Tick(row)
    end)
  )
  row.box:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, SW.TickTip(row))
  end)
  row.box:SetScript("OnLeave", ns.HideTooltip)
  row.craft:SetScript(
    "OnClick",
    ns.Wrap("auctionlink-craft", function()
      SW.ToggleCraft(row.line)
    end)
  )
  row.craft:SetScript("OnEnter", function(self)
    self.hl:SetColorTexture(1, 1, 1, 0.12)
    if row.line then
      SW.CraftTooltip(self, row.line)
    end
  end)
  row.craft:SetScript("OnLeave", function(self)
    self.hl:SetColorTexture(1, 1, 1, 0)
    ns.HideTooltip()
  end)
  function row:fgLayout()
    return ROW_H
  end
  return row
end

local function paintRow(row, item)
  if item.kind == "header" then
    row.line, row.item, row.ticked, row.auto = nil, item, false, false
    SW.PaintSeparator(row, item)
    for _, key in ipairs(PARTS) do
      row[key]:Hide()
    end
    row.craft:Hide()
    row.headBg:Show()
    row.head:Show()
    row.headTotal:Show()
    row:SetEnabled(false)
    row.head:SetText(string.format("%s  (%d/%d)", item.label, item.ticked, item.count))
    -- The coin icons make the sum wider than the two small columns it sits above: the width follows it.
    row.headTotal:SetWidth(math.max(PROG_W + CRAFT_W, ns.CostLogic.Width(ns.Theme.fontSize("micro"), item.open) + 2))
    row.headTotal:SetText(item.open > 0 and ns.CostLogic.Format(item.open) or "")
    return
  end
  -- The item of a single position heads its materials, on the band of a section header.
  SW.PaintSeparator(row, item)
  row.headBg:SetShown(item.head == true)
  row.head:Hide()
  row.headTotal:Hide()
  for _, key in ipairs(PARTS) do
    row[key]:Show()
  end
  row:SetEnabled(true)
  local line, ticked = item.line, item.ticked
  row.line, row.item, row.slug, row.ticked, row.auto = line, item, item.slug, ticked, item.auto
  row.mark:SetShown(ticked)
  row.boxOn:SetShown(ticked)
  row.boxBorder.set(ticked and "actionHi" or "white", ticked and 1 or 0.4)
  local color = ticked and "textMuted" or "text"
  row.indent = item.depth * INDENT
  row.icon:ClearAllPoints()
  row.icon:SetPoint("LEFT", PAD + BOX + 4 + row.indent, 0)
  row.icon:SetTexture(ns.ProfessionList.Icon(line))
  row.icon:SetDesaturated(ticked)
  row.icon:SetAlpha(ticked and 0.5 or 1)
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.name:SetPoint("RIGHT", row.mag, "LEFT", -2, 0)
  row.name:SetText(S.RowLabel(item))
  W.SetColor(row.name, color)
  local progress, progressColor = S.Progress(item)
  row.prog:SetText(progress)
  W.SetColor(row.prog, progressColor)
  row.craft:SetShown(item.craftable)
  row.craft.text:SetText(L[item.choice == "craft" and "shoplist.craft.short" or "shoplist.ah.short"])
end

-- Panel -------------------------------------------------------------------------------------------

local function openRoutePage(host)
  if ns.Main and ns.Main.Show then
    ns.Main.Show("professionroute")
    ns.BlizzardLinks.RaiseMain(host)
  end
end

-- Buttons share the width; without the list connection the copy button takes all of it.
local function placeButtons(panel, withSend)
  local full = PANEL_W - 2 * PAD
  panel.copy:ClearAllPoints()
  if withSend then
    local half = math.floor((full - 6) / 2)
    panel.send:SetWidth(half)
    panel.copy:SetWidth(half)
    panel.copy:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  else
    panel.copy:SetWidth(full)
    panel.copy:SetPoint("BOTTOMLEFT", PAD, PAD)
  end
end

-- The footer sits above the note (when there is one) and the note above the buttons, so a note that
-- wraps pushes nothing out of the panel.
local function placeFooter(panel, withNote)
  panel.footer:ClearAllPoints()
  if withNote then
    panel.footer:SetPoint("BOTTOMLEFT", panel.note, "TOPLEFT", 0, 4)
    panel.footer:SetPoint("BOTTOMRIGHT", panel.note, "TOPRIGHT", 0, 4)
  else
    panel.footer:SetPoint("BOTTOMLEFT", PAD, PAD + BUTTON_H + 6)
    panel.footer:SetPoint("BOTTOMRIGHT", -PAD, PAD + BUTTON_H + 6)
  end
end

local function refreshList(rec)
  local panel = rec.panel
  local picked = S.Option("slug") ~= nil
  panel.pick:SetShown(not picked)
  panel.open:SetShown(not picked)
  panel.summary:SetShown(picked)
  panel.host:SetShown(picked)
  panel.footer:SetShown(picked)
  panel.total:Hide()
  local whole = picked and S.View() or nil
  -- The search only picks what is shown: counters stay those of the whole list.
  local view = whole and SW.Shown(whole, panel.search.filter) or nil
  local plan = whole and whole.plan
  local ready = S.ListApiReady()
  local hasData = plan ~= nil and plan.data ~= nil
  panel.send:SetShown(hasData and ready)
  panel.copy:SetShown(hasData)
  panel.note:SetShown(hasData and not ready)
  panel.hint:SetShown(hasData)
  panel.views.combined:SetShown(hasData)
  panel.views.reason:SetShown(hasData)
  panel.search:SetShown(hasData)
  local offered =
    panel.banner:Update(picked and plan.data == nil and plan.status == ns.ProfessionRouteData.STATUS.missing)
  if hasData then
    placeButtons(panel, ready)
    placeFooter(panel, not ready)
  end
  if not picked then
    rec.list = {}
    panel.pool:Sync({}, paintRow)
    return
  end
  if not hasData then
    panel.summary:SetText(offered and "" or ns.ProfessionRouteData.Hint(plan.status))
    panel.footer:SetText("")
    rec.list = {}
    panel.pool:Sync({}, paintRow)
    panel.empty:Hide()
    panel.view:Layout()
    return
  end
  panel.views.Refresh()
  panel.total:SetShown(whole.count > 0)
  panel.total:Paint(whole)
  panel.summary:SetText(string.format(L["profshop.summary"], plan.name, plan.from, plan.to, S.Option("surcharge")))
  rec.list = view.lines
  panel.pool:Sync(view.rows, paintRow)
  local noMatch = view.filtered and #view.rows == 0
  panel.empty:SetShown(noMatch == true)
  local footer = view.count > 0 and string.format(L["profshop.ticked"], view.ticked, view.count) or L["profshop.empty"]
  panel.footer:SetText(
    view.filtered and view.count > 0 and (footer .. "  ·  " .. string.format(L["shoplist.hits"], view.matches))
      or footer
  )
  panel.view:Layout()
end

-- The tab shown, kept for the session (a panel built later for another host window starts on it too).
local lastTab = "list"
local TAB_IDS = {
  { id = "list", key = "auctionlink.tabShop", tip = "auctionlink.tabShop.tip" },
  { id = "settings", key = "auctionlink.tabSettings", tip = "auctionlink.tabSettings.tip" },
}

local function refresh(rec)
  if rec.tabId == "settings" then
    rec.panel.settings.Refresh()
  else
    refreshList(rec)
  end
end

-- Keyboard walk ----------------------------------------------------------------------------------------

local function usableControl(frame)
  return frame:IsVisible() and (not frame.IsEnabled or frame:IsEnabled())
end

-- The controls of the shown page in reading order: title bar, tabs, then the page.
local function walk(rec)
  local panel = rec.panel
  local list = { panel.details, panel.close, panel.tabs.buttons.list, panel.tabs.buttons.settings }
  local page = rec.tabId == "settings" and panel.settings.controls
    or {
      panel.open,
      panel.banner.button,
      panel.views.combined,
      panel.views.reason,
      panel.search,
      panel.search.clearButton,
      panel.total,
      panel.send,
      panel.copy,
    }
  for _, frame in ipairs(page) do
    list[#list + 1] = frame
  end
  local out = {}
  for _, frame in ipairs(list) do
    if usableControl(frame) then
      out[#out + 1] = frame
    end
  end
  return out
end

local function clearFocus(rec)
  local frame = rec.focus
  rec.focus = nil
  rec.ring:Hide()
  if frame and frame.fgOnBlur then
    frame:fgOnBlur()
  end
end

local function setFocus(rec, frame)
  if rec.focus and rec.focus ~= frame and rec.focus.fgOnBlur then
    rec.focus:fgOnBlur()
  end
  rec.focus = frame
  rec.ring:ClearAllPoints()
  rec.ring:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
  rec.ring:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
  rec.ring:Show()
  if frame.fgOnFocus then
    frame:fgOnFocus()
  end
end

local function move(rec, step)
  local list = walk(rec)
  local index = 0
  for i, frame in ipairs(list) do
    if frame == rec.focus then
      index = i
    end
  end
  index = index + step
  if index < 1 then
    index = #list
  elseif index > #list then
    index = 1
  end
  if list[index] then
    setFocus(rec, list[index])
  end
end

local function isTabButton(rec, frame)
  for _, button in pairs(rec.panel.tabs.buttons) do
    if button == frame then
      return true
    end
  end
  return false
end

-- Left and right on a tab button select the neighbouring tab, as in a tab list.
local function arrowTab(rec, step)
  local index = 1
  for i, tab in ipairs(TAB_IDS) do
    if tab.id == rec.tabId then
      index = i
    end
  end
  local target = TAB_IDS[math.max(1, math.min(#TAB_IDS, index + step))]
  rec.panel.tabs:Select(target.id)
  setFocus(rec, rec.panel.tabs.buttons[target.id])
end

-- Takes the key only while a control of the panel has the focus (or Tab is pressed over the panel);
-- every other key, movement keys included, goes on to the game. True when the key was used.
local function onKey(rec, key)
  local focus = rec.focus
  if key == "ESCAPE" then
    if focus then
      clearFocus(rec)
      return true
    end
  elseif focus or (key == "TAB" and rec.panel:IsMouseOver()) then
    if key == "TAB" then
      -- Shift+Tab is the fixed convention for going back, not a gesture of the key registry.
      local shift = rawget(_G, "IsShiftKeyDown")
      move(rec, type(shift) == "function" and shift() and -1 or 1)
      return true
    elseif focus and (key == "UP" or key == "DOWN") then
      move(rec, key == "UP" and -1 or 1)
      return true
    elseif focus and (key == "LEFT" or key == "RIGHT") and isTabButton(rec, focus) then
      arrowTab(rec, key == "LEFT" and -1 or 1)
      return true
    elseif focus and (key == "ENTER" or key == "SPACE") then
      if focus.fgActivate then
        ns.Safe("auctionlink-key", focus.fgActivate, focus)
      end
      return true
    end
  end
  return false
end

local function setupKeys(rec)
  local keys = CreateFrame("Frame", nil, rec.panel)
  if not ns.can.propagateKeyboard then
    return
  end
  ns.PropagateKeys(keys, true)
  keys:EnableKeyboard(true)
  keys:SetScript(
    "OnKeyDown",
    ns.Wrap("auctionlink-keys", function(self, key)
      ns.PropagateKeys(self, not onKey(rec, key))
    end)
  )
  rec.keys = keys
end

-- Shows the page of a tab and keeps the choice. Called by the tab row (mouse, keyboard) and by SelectTab.
local function applyTab(rec, id)
  local panel = rec.panel
  rec.tabId, lastTab = id, id
  panel.page:SetShown(id == "list")
  panel.settings:SetShown(id == "settings")
  if panel:IsShown() then
    refresh(rec)
  end
  if rec.focus and not usableControl(rec.focus) then
    setFocus(rec, panel.tabs.buttons[id])
  end
end

local function buildPanel(host, level)
  local panel = CreateFrame("Frame", nil, host)
  panel:SetSize(PANEL_W, PANEL_H)
  panel:SetPoint("TOPLEFT", host, "TOPRIGHT", TAB_INSET + TAB_SIZE + PANEL_GAP, -TAB_DROP)
  panel:SetFrameLevel(level)
  panel:EnableMouse(true)
  W.Fill(panel, "surface", 1)
  W.Border(panel, "white")
  panel:Hide()

  panel.close = W.CloseButton(panel, {
    onClick = function()
      panel:Hide()
    end,
  })
  -- "Details" opens (or raises) the shopping list window, left of the close button.
  panel.details = W.Action(panel, {
    key = "auctionlink.details",
    icon = "open",
    tooltip = "auctionlink.details",
    tooltipText = "auctionlink.detailsTip",
    height = W.CLOSE_SIZE,
    onClick = function()
      SW.Open()
    end,
  })
  panel.details:SetWidth(panel.details:FullWidth())
  panel.details:SetPoint("TOPRIGHT", panel.close, "TOPLEFT", -4, 0)
  panel.title = W.Text(panel, { key = "auctionlink.title", role = "h3", family = "heading", color = "accent2" })
  panel.title:SetPoint("TOPLEFT", PAD, -10)
  panel.title:SetPoint("TOPRIGHT", panel.details, "TOPLEFT", -4, -6)

  -- The two tabs (a tooltip each) and their pages below: the list and the settings.
  panel.tabs = W.Tabs(panel, {
    tabs = TAB_IDS,
    onSelect = function(id)
      if panel.rec then
        applyTab(panel.rec, id)
      end
    end,
  })
  panel.tabs:SetPoint("TOPLEFT", PAD, -TABS_TOP)
  panel.tabs:SetPoint("TOPRIGHT", -PAD, -TABS_TOP)
  for _, tab in ipairs(TAB_IDS) do
    local button = panel.tabs.buttons[tab.id]
    W.AttachTooltip(button, tab.key, tab.tip)
    button.fgOnFocus = function()
      ns.ShowTooltip(button, L[tab.key], L[tab.tip])
    end
    button.fgOnBlur = ns.HideTooltip
  end
  panel.page = CreateFrame("Frame", nil, panel)
  panel.page:SetPoint("TOPLEFT", 0, -PAGE_TOP)
  panel.page:SetPoint("BOTTOMRIGHT", 0, 0)
  panel.settings = ns.AuctionSettings.Build(panel)
  panel.settings:SetPoint("TOPLEFT", 0, -PAGE_TOP)
  panel.settings:SetPoint("BOTTOMRIGHT", 0, 0)
  panel.settings:Hide()
  local page = panel.page

  -- Nothing chosen yet: a hint and the way to the route page.
  panel.pick = W.Text(page, { key = "auctionlink.pick", role = "ui", color = "textSecondary", wrap = true })
  panel.pick:SetPoint("TOPLEFT", PAD, -4)
  panel.pick:SetPoint("TOPRIGHT", -PAD, -4)
  panel.open = W.Action(page, {
    label = "act.open",
    icon = "open",
    tooltip = "auctionlink.open",
    width = PANEL_W - 2 * PAD,
    onClick = function()
      openRoutePage(host)
    end,
  })
  panel.open:SetPoint("TOPLEFT", panel.pick, "BOTTOMLEFT", 0, -10)

  panel.summary = W.Text(page, { role = "ui", color = "accent2", wrap = true })
  panel.summary:SetPoint("TOPLEFT", PAD, -4)
  panel.summary:SetPoint("TOPRIGHT", -PAD, -4)

  -- Takes the place of the summary while the data add-on is off or missing.
  panel.banner = ns.PackageUI.Banner(page, ns.ProfessionRouteData.ADDON, {
    onLoaded = function()
      if panel.rec then
        refresh(panel.rec)
      end
    end,
  })
  panel.banner:SetPoint("TOPLEFT", PAD, -4)
  panel.banner:SetPoint("TOPRIGHT", -PAD, -4)
  panel.banner:Fit(PANEL_W - 2 * PAD)

  panel.send = W.Action(page, {
    label = "act.send",
    icon = "share",
    tooltip = "profshop.send",
    tooltipText = "profshop.sendTip",
    onClick = function()
      SW.Send(S.Plan())
    end,
  })
  panel.send:SetPoint("BOTTOMLEFT", PAD, PAD)
  panel.hint = W.Text(page, { key = "profshop.hint", role = "micro", color = "textSecondary", wrap = true })
  panel.hint:SetPoint("TOPLEFT", panel.summary, "BOTTOMLEFT", 0, -4)
  panel.hint:SetPoint("TOPRIGHT", panel.summary, "BOTTOMRIGHT", 0, -4)
  panel.views = SW.ViewButtons(page)
  local half = math.floor((PANEL_W - 2 * PAD - 6) / 2)
  panel.views.combined:SetWidth(half)
  panel.views.reason:SetWidth(half)
  panel.views.combined:SetPoint("TOPLEFT", panel.hint, "BOTTOMLEFT", 0, -6)
  panel.views.reason:SetPoint("LEFT", panel.views.combined, "RIGHT", 6, 0)
  panel.copy = W.Action(page, {
    label = "act.text",
    icon = "copy",
    tooltip = "profshop.copy",
    onClick = function()
      SW.ShowCopy(false, S.Plan())
    end,
  })
  panel.note = W.Text(page, { key = "auctionlink.noApi", role = "micro", color = "textMuted", wrap = true })
  panel.note:SetPoint("BOTTOMLEFT", PAD, PAD + BUTTON_H + 6)
  panel.note:SetPoint("BOTTOMRIGHT", -PAD, PAD + BUTTON_H + 6)
  panel.footer = W.Text(page, { role = "micro", color = "textSecondary" })
  placeFooter(panel, false)

  -- View only, not saved, gone when the panel closes. The panel sits on a Blizzard window: the box only
  -- takes keys while it has the focus (it never grabs it by itself).
  panel.search = SW.SearchBox(page, function()
    if panel.rec then
      refresh(panel.rec)
    end
  end)
  panel.search:SetPoint("TOPLEFT", panel.views.combined, "BOTTOMLEFT", 0, -6)
  panel.search:SetWidth(PANEL_W - 2 * PAD)
  -- The sum of the whole list, pinned over the rows (the by reason view also shows one per section).
  panel.total = SW.NewTotalBar(page, { pad = PAD })
  panel.total:SetPoint("TOPLEFT", panel.search, "BOTTOMLEFT", 0, -6)
  panel.total:SetWidth(PANEL_W - 2 * PAD)
  panel.host = CreateFrame("Frame", nil, page)
  panel.host:SetPoint("TOPLEFT", panel.total, "BOTTOMLEFT", 0, -4)
  panel.host:SetPoint("BOTTOMRIGHT", panel.footer, "TOPRIGHT", 0, 6)
  local area = W.ScrollArea(panel.host)
  area:SetAllPoints()
  local stack = W.Stack(area, 0)
  panel.pool = K.RowPool(area.content, newRow)
  stack:Add(panel.pool, { gap = 0 })
  panel.view = {
    Layout = function()
      stack:Layout()
    end,
  }
  area:HookScript("OnSizeChanged", function()
    ns.Debounce(panel.view, LAYOUT_DELAY, function()
      stack:Layout()
    end)
  end)
  panel.empty = W.Text(panel.host, { key = "shoplist.noMatches", role = "ui", color = "textMuted", justify = "CENTER" })
  panel.empty:SetPoint("TOP", 0, -12)
  panel.empty:SetPoint("LEFT", 0, 0)
  panel.empty:SetPoint("RIGHT", 0, 0)
  panel.empty:Hide()

  -- The Tab ring belongs to the main window, which must not reach buttons on a Blizzard window.
  for _, frame in ipairs({
    panel.close,
    panel.details,
    panel.open,
    panel.send,
    panel.copy,
    panel.banner.button,
    panel.views.combined,
    panel.views.reason,
    panel.search,
    panel.search.clearButton,
    panel.total,
    panel.tabs.buttons.list,
    panel.tabs.buttons.settings,
    unpack(panel.settings.controls),
  }) do
    ns.BlizzardLinks.LeaveFocusRing(frame)
  end
  -- The keyboard ring of the panel's own walk, created last so it draws over the controls.
  panel.ring = CreateFrame("Frame", nil, panel)
  panel.ring:SetFrameLevel(math.min(level + RING_BOOST, LEVEL_CAP))
  W.Border(panel.ring, "actionHi", 1, 3)
  panel.ring:Hide()
  return panel
end

local function build(host)
  local level = math.min(host:GetFrameLevel() + LEVEL, LEVEL_CAP)
  local rec = {}
  rec.tab = ns.BlizzardLinks.CreateSideTab(host, {
    key = "auctionlink.tab",
    tip = "auctionlink.tab.tip",
    onClick = A.Toggle,
    point = "TOPLEFT",
    rel = host,
    relPoint = "TOPRIGHT",
    x = TAB_INSET,
    y = -TAB_DROP,
  })
  rec.panel = buildPanel(host, level)
  rec.ring = rec.panel.ring
  rec.panel.rec = rec
  rec.panel:SetScript(
    "OnShow",
    ns.Wrap("auctionlink-show", function()
      rec.tab:fgSetSelected(true)
      refresh(rec)
    end)
  )
  rec.panel:SetScript(
    "OnHide",
    ns.Wrap("auctionlink-hide", function()
      rec.tab:fgSetSelected(false)
      rec.panel.search.Reset()
      clearFocus(rec)
      ns.AuctionSettings.Acknowledge()
    end)
  )
  setupKeys(rec)
  rec.panel.tabs:Select(lastTab)
  return rec
end

-- Public ------------------------------------------------------------------------------------------

-- Builds tab and panel once for the auction house window. False while there is no window yet, in
-- combat, or after a failed build.
function A.Install()
  local host = hostFrame()
  if not host or not ns.db then
    return false
  end
  if parts[host] ~= nil then
    return parts[host] ~= false
  end
  if inCombat() then
    return false
  end
  local ok, rec = ns.Safe("auctionlink-build", build, host)
  parts[host] = ok and rec or false
  return ok == true
end

-- Tab and panel of the current auction house window, nil before the first build.
function A.Parts()
  local host = hostFrame()
  return host and parts[host] or nil
end

-- Switches to a tab ("list" or "settings"); the choice is kept for the session. False for any other id.
function A.SelectTab(id)
  if id ~= "list" and id ~= "settings" then
    return false
  end
  lastTab = id
  local rec = A.Parts()
  if rec then
    rec.panel.tabs:Select(id)
  end
  return true
end

-- The tab id the panel shows, or the one it opens on.
function A.Tab()
  local rec = A.Parts()
  return rec and rec.tabId or lastTab
end

function A.Toggle()
  local rec = A.Parts()
  if not rec or inCombat() then
    return
  end
  if rec.panel:IsShown() then
    rec.panel:Hide()
  else
    rec.panel:Show()
  end
end

-- The rows the panel lists, for the tests.
function A.Rows()
  local rec = A.Parts()
  return rec and rec.list or {}
end

-- The panel opens by itself once per visit while the list has open positions and the player did not
-- switch it off. The panel is ours, so there is nothing protected in it; like everything here it
-- waits for the end of combat. Closing it by hand sticks until the next visit (A.opened).
local visit = { opened = false }

local function hasOpenPositions()
  local view = S.Option("slug") ~= nil and S.View() or nil
  if not view then
    return false
  end
  return view.ticked < view.count
end

local function autoOpen()
  local rec = A.Parts()
  if not rec or visit.opened or inCombat() or not S.Option("autoOpen") then
    return
  end
  visit.opened = true
  if hasOpenPositions() and not rec.panel:IsShown() then
    A.SelectTab("list")
    rec.panel:Show()
  end
end

local function install()
  if A.Install() then
    local host = hostFrame()
    if host and host:IsShown() then
      autoOpen()
    end
    return true
  end
  return false
end

-- Either event may come first and the window may not exist yet when it does.
local function onOpen()
  if not install() then
    ns.Debounce("auctionlink-retry", RETRY_DELAY, install)
  end
end

local function onClose()
  visit.opened = false
end

local function auctioneer()
  local types = type(Enum) == "table" and Enum.PlayerInteractionType
  return type(types) == "table" and types.Auctioneer or nil
end

ns.On("AUCTION_HOUSE_SHOW", onOpen)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
  if kind ~= nil and kind == auctioneer() then
    onOpen()
  end
end)
ns.On("AUCTION_HOUSE_CLOSED", onClose)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
  if kind ~= nil and kind == auctioneer() then
    onClose()
  end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if hostFrame() then
    install()
  end
end)

-- The list follows route, bag and skill changes; the settings tab has messages of its own.
local function refreshOpen()
  local rec = A.Parts()
  if rec and rec.panel:IsShown() and rec.tabId == "list" then
    refresh(rec)
  end
end

ns.On("FG_PROFROUTE_CHANGED", refreshOpen)
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED" }) do
  ns.On(event, function()
    local rec = A.Parts()
    if rec and rec.panel:IsShown() and rec.tabId == "list" then
      ns.Debounce("auctionlink-refresh", REFRESH_DELAY, refreshOpen)
    end
  end)
end
