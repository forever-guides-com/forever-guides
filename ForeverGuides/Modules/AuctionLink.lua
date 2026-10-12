-- Side tab at the auction house window (AuctionHouseFrame, load on demand with Blizzard_AuctionHouseUI;
-- AuctionFrame on the classic layout) with a small docked panel: the shopping list of the chosen
-- profession route with tick boxes and the buttons "Send to shopping list" and "Copy as text". Without
-- a chosen route the panel only says so and offers the route page. A click on a row searches the
-- item in this window (ProfessionShop.lua, RowClick), the box ticks it. The shopping window of
-- ProfessionShopWindow.lua never opens by itself here.
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
  ["auctionlink.tab"] = "Forever Guides: Shopping list",
  ["auctionlink.tab.tip"] = "Shopping list of your profession route.",
  ["auctionlink.pick"] = "Pick a profession route first",
  ["auctionlink.open"] = "Open profession route",
  ["auctionlink.noApi"] = "No shopping list connection found.",
})
ns.AddLocale("deDE", {
  ["auctionlink.tab"] = "Forever Guides: Einkaufsliste",
  ["auctionlink.tab.tip"] = "Einkaufsliste deiner Berufsroute.",
  ["auctionlink.pick"] = "Wähle zuerst eine Berufsroute",
  ["auctionlink.open"] = "Berufsroute öffnen",
  ["auctionlink.noApi"] = "Keine Einkaufslisten-Anbindung gefunden.",
})

local HOSTS = { "AuctionHouseFrame", "AuctionFrame" }
local TAB_INSET, TAB_DROP, TAB_SIZE = 4, 40, 52 -- as the side tabs of the other windows
local PANEL_W, PANEL_H = 300, 340
local PANEL_GAP = 4 -- between the tab and the panel
local PAD, ROW_H, BOX = 8, 22, 16
local BUTTON_H = 26
local LEVEL, LEVEL_CAP = 45, 9990
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

local function newRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_H)
  row.hover = row:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(1, 1, 1, 0)
  row.box = CreateFrame("Button", nil, row)
  row.box:SetSize(BOX, BOX)
  row.box:SetPoint("LEFT", PAD, 0)
  row.box:SetHitRectInsets(-4, -4, -3, -3)
  W.Fill(row.box, "surface2")
  row.boxOn = W.Fill(row.box, "action", 1)
  row.boxBorder = W.Border(row.box, "white", 0.4)
  row.mark = W.CheckMark(row.box, 12, "text")
  row.mark:SetPoint("CENTER")
  row.qty = W.Text(row, { role = "ui", justify = "RIGHT" })
  row.qty:SetPoint("RIGHT", -PAD, 0)
  row.qty:SetWidth(44)
  row.name = W.Text(row, { role = "ui" })
  row.name:SetPoint("LEFT", PAD + BOX + 6, 0)
  row.name:SetPoint("RIGHT", row.qty, "LEFT", -4, 0)
  row.name:SetMaxLines(1)
  -- The box ticks, the rest of the row searches (left), copies the name (right) or links it (Shift).
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnEnter", function(self)
    self.hover:SetColorTexture(1, 1, 1, 0.06)
    if self.line then
      S.RowTooltip(self, self.line)
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.hover:SetColorTexture(1, 1, 1, 0)
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
      if row.line then
        S.SetChecked(row.slug, row.line.id, not row.ticked)
      end
    end)
  )
  row.box:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["profshop.rowTip"])
  end)
  row.box:SetScript("OnLeave", ns.HideTooltip)
  function row:fgLayout()
    return ROW_H
  end
  return row
end

local function paintRow(row, item)
  local line, ticked = item.line, item.ticked
  row.line, row.slug, row.ticked = line, item.slug, ticked
  row.mark:SetShown(ticked)
  row.boxOn:SetShown(ticked)
  row.boxBorder.set(ticked and "actionHi" or "white", ticked and 1 or 0.4)
  local color = ticked and "textMuted" or "text"
  row.name:SetText(line.name)
  W.SetColor(row.name, color)
  row.qty:SetText(tostring(line.qty))
  W.SetColor(row.qty, color)
end

-- The lines the auction house tab offers: everything but vendor goods, in the order of the groups.
local function items(plan)
  local out, checked = {}, S.Checked(plan.slug)
  for _, g in ipairs(plan.groups or {}) do
    if g.source ~= "vendor" then
      for _, line in ipairs(g.lines) do
        out[#out + 1] = { line = line, slug = plan.slug, ticked = checked[line.id] == true }
      end
    end
  end
  return out
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

local function refresh(rec)
  local panel = rec.panel
  local picked = S.Option("slug") ~= nil
  panel.pick:SetShown(not picked)
  panel.open:SetShown(not picked)
  panel.summary:SetShown(picked)
  panel.host:SetShown(picked)
  panel.footer:SetShown(picked)
  local plan = picked and S.Plan() or nil
  local ready = S.ListApiReady()
  local hasData = plan ~= nil and plan.data ~= nil
  panel.send:SetShown(hasData and ready)
  panel.copy:SetShown(hasData)
  panel.note:SetShown(hasData and not ready)
  local offered =
    panel.banner:Update(picked and plan.data == nil and plan.status == ns.ProfessionRouteData.STATUS.missing)
  if hasData then
    placeButtons(panel, ready)
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
    panel.view:Layout()
    return
  end
  panel.summary:SetText(string.format(L["profshop.summary"], plan.name, plan.from, plan.to, S.Option("surcharge")))
  local list = items(plan)
  rec.list = list
  panel.pool:Sync(list, paintRow)
  local ticked = 0
  for _, item in ipairs(list) do
    if item.ticked then
      ticked = ticked + 1
    end
  end
  panel.footer:SetText(#list > 0 and string.format(L["profshop.ticked"], ticked, #list) or L["profshop.empty"])
  panel.view:Layout()
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
  panel.title = W.Text(panel, { key = "profshop.title", role = "h3", family = "heading", color = "accent2" })
  panel.title:SetPoint("TOPLEFT", PAD, -10)
  panel.title:SetPoint("TOPRIGHT", -(PAD + W.CLOSE_SIZE), -10)

  -- Nothing chosen yet: a hint and the way to the route page.
  panel.pick = W.Text(panel, { key = "auctionlink.pick", role = "ui", color = "textSecondary", wrap = true })
  panel.pick:SetPoint("TOPLEFT", PAD, -40)
  panel.pick:SetPoint("TOPRIGHT", -PAD, -40)
  panel.open = W.Action(panel, {
    label = "act.open",
    icon = "open",
    tooltip = "auctionlink.open",
    width = PANEL_W - 2 * PAD,
    onClick = function()
      openRoutePage(host)
    end,
  })
  panel.open:SetPoint("TOPLEFT", panel.pick, "BOTTOMLEFT", 0, -10)

  panel.summary = W.Text(panel, { role = "ui", color = "accent2", wrap = true })
  panel.summary:SetPoint("TOPLEFT", PAD, -36)
  panel.summary:SetPoint("TOPRIGHT", -PAD, -36)

  -- Takes the place of the summary while the data add-on is off or missing.
  panel.banner = ns.PackageUI.Banner(panel, ns.ProfessionRouteData.ADDON, {
    onLoaded = function()
      if panel.rec then
        refresh(panel.rec)
      end
    end,
  })
  panel.banner:SetPoint("TOPLEFT", PAD, -36)
  panel.banner:SetPoint("TOPRIGHT", -PAD, -36)
  panel.banner:Fit(PANEL_W - 2 * PAD)

  panel.send = W.Action(panel, {
    label = "act.send",
    icon = "share",
    tooltip = "profshop.send",
    tooltipText = "profshop.sendTip",
    onClick = function()
      SW.Send(S.Plan())
    end,
  })
  panel.send:SetPoint("BOTTOMLEFT", PAD, PAD)
  panel.copy = W.Action(panel, {
    label = "act.text",
    icon = "copy",
    tooltip = "profshop.copy",
    onClick = function()
      SW.ShowCopy(false, S.Plan())
    end,
  })
  panel.note = W.Text(panel, { key = "auctionlink.noApi", role = "micro", color = "textMuted" })
  panel.note:SetPoint("BOTTOMLEFT", PAD, PAD + BUTTON_H + 4)
  panel.footer = W.Text(panel, { role = "micro", color = "textSecondary" })
  panel.footer:SetPoint("BOTTOMLEFT", PAD, PAD + BUTTON_H + 20)
  panel.footer:SetPoint("BOTTOMRIGHT", -PAD, PAD + BUTTON_H + 20)

  panel.host = CreateFrame("Frame", nil, panel)
  panel.host:SetPoint("TOPLEFT", panel.summary, "BOTTOMLEFT", 0, -8)
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

  -- The Tab ring belongs to the main window, which must not reach buttons on a Blizzard window.
  for _, frame in ipairs({ panel.close, panel.open, panel.send, panel.copy, panel.banner.button }) do
    ns.BlizzardLinks.LeaveFocusRing(frame)
  end
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
    end)
  )
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

-- Either event may come first and the window may not exist yet when it does.
local function onOpen()
  if not A.Install() then
    ns.Debounce("auctionlink-retry", RETRY_DELAY, A.Install)
  end
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
ns.On("PLAYER_REGEN_ENABLED", function()
  if hostFrame() then
    A.Install()
  end
end)

local function refreshOpen()
  local rec = A.Parts()
  if rec and rec.panel:IsShown() then
    refresh(rec)
  end
end

ns.On("FG_PROFROUTE_CHANGED", refreshOpen)
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED" }) do
  ns.On(event, function()
    local rec = A.Parts()
    if rec and rec.panel:IsShown() then
      ns.Debounce("auctionlink-refresh", REFRESH_DELAY, refreshOpen)
    end
  end)
end
