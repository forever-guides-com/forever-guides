-- "Settings" tab of the auction house panel (Modules/AuctionLink.lua): the state of the price data
-- (open house, saved items, date of the last full scan), the button for the full scan with its progress
-- and the options of the price database. Everything is read from ns.PriceDb at the time it is shown and
-- again on its messages (FG_PRICES_SCAN, FG_PRICES_UPDATED); nothing runs per frame except a one second
-- tick while a cooldown or a scan is on screen.
local _, ns = ...
local W, L, Store = ns.W, ns.L, ns.Store

local AS = {}
ns.AuctionSettings = AS

ns.AddLocale("enUS", {
  ["auctionset.heading.data"] = "Price data",
  ["auctionset.house"] = "Auction house: %s",
  ["auctionset.house.Horde"] = "Horde",
  ["auctionset.house.Alliance"] = "Alliance",
  ["auctionset.house.Neutral"] = "Neutral",
  ["auctionset.house.unknown"] = "Auction house: unknown, stand at the auctioneer",
  ["auctionset.items"] = "Saved prices (%s): %d items",
  ["auctionset.last"] = "Last scan: %s (%d items, %d auctions, %d s)",
  ["auctionset.lastNone"] = "No scan yet",
  ["auctionset.neutral"] = "Neutral: %d items. %s",
  ["auctionset.dateFormat"] = "%Y-%m-%d %H:%M",
  ["auctionset.heading.scan"] = "Full scan",
  ["auctionset.scan.start"] = "Start full scan",
  ["auctionset.scan.cancel"] = "Cancel scan",
  ["auctionset.scan.retry"] = "Try again",
  ["auctionset.scan.tip"] = "Reads the whole auction list once and saves the lowest, the median and the highest price.",
  ["auctionset.cooldown"] = "Possible again in %d:%02d",
  ["auctionset.phase.waiting"] = "Waiting for the list...",
  ["auctionset.phase.reading"] = "Reading auctions %d of %d",
  ["auctionset.phase.aggregating"] = "Calculating prices...",
  ["auctionset.phase.done"] = "Done",
  ["auctionset.elapsed"] = "%d s",
  ["auctionset.percent"] = "%d%%",
  ["auctionset.scan.note"] = "The scan reads the whole auction list once (about 10 to 20 seconds, the game may stutter briefly). The game allows it only every 15 minutes.",
  ["auctionset.scan.passive"] = "Normal searches in the auction house update the prices automatically as well.",
  ["auctionset.heading.options"] = "Options",
  ["auctionset.autoOpen"] = "Open the shopping list at the auction house",
  ["auctionset.tooltip"] = "Show auction house price in tooltips",
  ["auctionset.days"] = "Mark data as old after (days, 1 to 90)",
  ["auctionset.clear"] = "Delete price data",
  ["auctionset.clearTitle"] = "Delete price data",
  ["auctionset.clearText"] = "Delete all saved auction house prices of every house? A new scan or normal searches fill them again.",
  ["auctionset.cleared"] = "Price data deleted",
  ["auctionset.addon"] = "Price add-on found: used as a fallback.",
})
ns.AddLocale("deDE", {
  ["auctionset.heading.data"] = "Preisdaten",
  ["auctionset.house"] = "Auktionshaus: %s",
  ["auctionset.house.Horde"] = "Horde",
  ["auctionset.house.Alliance"] = "Allianz",
  ["auctionset.house.Neutral"] = "Neutral",
  ["auctionset.house.unknown"] = "Auktionshaus: unbekannt, stelle dich zum Auktionator",
  ["auctionset.items"] = "Gespeicherte Preise (%s): %d Items",
  ["auctionset.last"] = "Letzter Scan: %s (%d Items, %d Auktionen, %d s)",
  ["auctionset.lastNone"] = "Noch kein Scan",
  ["auctionset.neutral"] = "Neutral: %d Items. %s",
  ["auctionset.dateFormat"] = "%d.%m.%Y %H:%M",
  ["auctionset.heading.scan"] = "Kompletter Scan",
  ["auctionset.scan.start"] = "Kompletten Scan starten",
  ["auctionset.scan.cancel"] = "Scan abbrechen",
  ["auctionset.scan.retry"] = "Erneut versuchen",
  ["auctionset.scan.tip"] = "Liest die ganze Auktionsliste einmal und speichert den niedrigsten Preis, den Median und den höchsten Preis.",
  ["auctionset.cooldown"] = "Wieder möglich in %d:%02d",
  ["auctionset.phase.waiting"] = "Warten auf die Liste...",
  ["auctionset.phase.reading"] = "Lese Auktionen %d von %d",
  ["auctionset.phase.aggregating"] = "Berechne Preise...",
  ["auctionset.phase.done"] = "Fertig",
  ["auctionset.elapsed"] = "%d s",
  ["auctionset.percent"] = "%d %%",
  ["auctionset.scan.note"] = "Der Scan liest die ganze Auktionsliste einmal (etwa 10 bis 20 Sekunden, das Spiel kann kurz ruckeln). Das Spiel erlaubt ihn nur alle 15 Minuten.",
  ["auctionset.scan.passive"] = "Normale Suchen im Auktionshaus aktualisieren die Preise ebenfalls automatisch.",
  ["auctionset.heading.options"] = "Optionen",
  ["auctionset.autoOpen"] = "Einkaufsliste im Auktionshaus öffnen",
  ["auctionset.tooltip"] = "Auktionshaus-Preis in Tooltips anzeigen",
  ["auctionset.days"] = "Daten als alt markieren nach (Tage, 1 bis 90)",
  ["auctionset.clear"] = "Preisdaten löschen",
  ["auctionset.clearTitle"] = "Preisdaten löschen",
  ["auctionset.clearText"] = "Alle gespeicherten Auktionshaus-Preise aller Häuser löschen? Ein neuer Scan oder normale Suchen füllen sie wieder.",
  ["auctionset.cleared"] = "Preisdaten gelöscht",
  ["auctionset.addon"] = "Preis-Addon gefunden: wird als Rückfall genutzt.",
})

AS.DAYS_MIN, AS.DAYS_MAX, AS.DAYS_DEFAULT = 1, 90, 14
-- Share of the bar the row reading takes; the aggregation and the writing of the items take the rest.
AS.READ_SHARE = 0.7
-- Seconds the finished bar stays on screen.
AS.DONE_HOLD = 4

local PAD = 8
local DAYS_W = 72
local BAR_H, PCT_W = 14, 60
local TICK = 1
local ACTIVE = { waiting = true, reading = true, aggregating = true }

local function clock()
  local f = rawget(_G, "GetTime")
  local t = type(f) == "function" and f() or nil
  return type(t) == "number" and t or 0
end

local function whole(n)
  return math.floor((tonumber(n) or 0) + 0.5)
end

-- Pure helpers ---------------------------------------------------------------------------------------

-- Date and time of a server time stamp in the local time zone, in the order of the language.
function AS.DateText(at)
  local ok, text = pcall(date, L["auctionset.dateFormat"], at)
  return ok and text or tostring(at)
end

-- "Last scan: ..." of a PriceDb.LastScan record, or the line for a house without one.
function AS.LastScanText(scan)
  if not scan then
    return L["auctionset.lastNone"]
  end
  return string.format(
    L["auctionset.last"],
    AS.DateText(scan.at),
    whole(scan.items),
    whole(scan.rows),
    whole(scan.secs)
  )
end

-- The days of a text field: a whole number inside the limits, nil for anything that is no number.
function AS.ParseDays(text)
  local n = type(text) == "string" and text:match("^%s*(%d+)%s*$") and tonumber(text)
  if not n then
    return nil
  end
  return math.max(AS.DAYS_MIN, math.min(AS.DAYS_MAX, n))
end

-- The saved age limit, 14 when missing or damaged.
function AS.MaxAgeDays()
  local n = tonumber(Store.get("settings.priceDb.maxAgeDays"))
  if not n then
    return AS.DAYS_DEFAULT
  end
  return math.max(AS.DAYS_MIN, math.min(AS.DAYS_MAX, math.floor(n)))
end

-- 0 to 1 over the whole scan: the rows count 70 %, the calculation and writing the rest.
function AS.Fraction(scan)
  if scan.phase == "done" then
    return 1
  end
  local part = scan.total > 0 and math.min(1, scan.done / scan.total) or 0
  if scan.phase == "reading" then
    return part * AS.READ_SHARE
  elseif scan.phase == "aggregating" then
    return AS.READ_SHARE + part * (1 - AS.READ_SHARE)
  end
  return 0
end

function AS.PhaseText(scan)
  local phase = scan.phase
  if phase == "reading" then
    return string.format(L["auctionset.phase.reading"], whole(scan.done), whole(scan.total))
  end
  return L["auctionset.phase." .. phase] or ""
end

-- Text of a scan that cannot start now (nil when it can): the short countdown for the cooldown, the
-- reason text of the price database for everything else.
function AS.BlockedText(ok, reason, seconds)
  if ok then
    return nil
  end
  if reason == "cooldown" then
    local s = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format(L["auctionset.cooldown"], math.floor(s / 60), s % 60)
  end
  return ns.PriceDb.ReasonText(reason, seconds)
end

local pages = {}

-- Page ----------------------------------------------------------------------------------------------

local function houseName(house)
  local key = "auctionset.house." .. tostring(house)
  local text = L[key]
  return text ~= key and text or tostring(house)
end

local function setShown(frame, on)
  on = on and true or false
  if frame:IsShown() ~= on then
    frame:SetShown(on)
  end
end

local function paintBar(bar)
  bar.fill:SetColorTexture(ns.Theme.color("accent"))
  bar.track:SetColorTexture(ns.Theme.color("surface3"))
end

-- Everything the page shows for the state of the price database. `ui` holds what the messages told
-- us: ack (a finished or failed scan was seen and the panel was closed since) and doneAt.
local function refresh(page)
  local db, ui = ns.PriceDb, page.ui
  local scan = db.ScanState()
  local running = ACTIVE[scan.phase] == true
  local terminal = not running and not ui.ack and (scan.phase == "done" or scan.phase == "failed")
  local failed = terminal and scan.phase == "failed"
  local holding = terminal and scan.phase == "done" and ui.doneAt ~= nil and clock() - ui.doneAt < AS.DONE_HOLD

  -- Price data.
  local house = db.House()
  local shown = house or db.OwnHouse()
  page.house:SetText(house and string.format(L["auctionset.house"], houseName(house)) or L["auctionset.house.unknown"])
  page.items:SetText(string.format(L["auctionset.items"], houseName(shown), whole(db.Count(shown))))
  page.last:SetText(AS.LastScanText(db.LastScan(shown)))
  W.SetColor(page.last, holding and "success" or "textSecondary")
  local neutralScan = shown ~= "Neutral" and db.LastScan("Neutral") or nil
  local neutralItems = shown ~= "Neutral" and whole(db.Count("Neutral")) or 0
  setShown(page.neutral, neutralScan ~= nil or neutralItems > 0)
  page.neutral:SetText(string.format(L["auctionset.neutral"], neutralItems, AS.LastScanText(neutralScan)))

  -- Scan: one button (start, cancel or try again), why it is off, the progress.
  local can, reason, seconds = db.CanScan()
  local blocked = AS.BlockedText(can, reason, seconds)
  local mode = running and "cancel" or (failed and "retry" or "start")
  page.mode = mode
  W.SetText(page.scan.label, "auctionset.scan." .. mode)
  page.scan.fgNameKey = "auctionset.scan." .. mode
  page.scan:SetIcon(mode == "cancel" and "close" or (mode == "retry" and "refresh" or "play"))
  page.scan:SetEnabled(running or can)
  setShown(page.blocked, not running and blocked ~= nil)
  page.blocked:SetText(blocked or "")
  local barOn = running or holding
  setShown(page.progress, barOn)
  setShown(page.phase, barOn)
  if barOn then
    local pct = math.floor(AS.Fraction(scan) * 100 + 0.5)
    page.bar:SetValue(pct)
    page.pct:SetText(string.format(L["auctionset.percent"], pct))
    page.phase:SetText(
      AS.PhaseText(scan) .. "  ·  " .. string.format(L["auctionset.elapsed"], math.floor(scan.elapsed))
    )
  end
  setShown(page.failure, failed)
  if failed then
    page.failure:SetText(db.ReasonText(scan.reason, seconds))
    W.SetColor(page.failure, scan.reason == "cancelled" and "warning" or "danger")
  end

  -- Options.
  page.autoOpen.Refresh()
  page.tooltip.Refresh()
  if not page.days.edit:HasFocus() then
    page.days.edit:SetText(tostring(AS.MaxAgeDays()))
  end
  setShown(page.addon, ns.PriceSourceAddon.Available())

  -- One tick a second while a countdown, a scan or the hold of the finished bar is on screen.
  local needTick = running or holding or reason == "cooldown"
  page.ticker:SetScript("OnUpdate", needTick and page.onTick or nil)
  page.view:Layout()
end

function AS.Refresh(page)
  refresh(page)
end

local function refreshVisible()
  for _, page in ipairs(pages) do
    if page:IsVisible() then
      ns.Safe("auctionset-refresh", refresh, page)
    end
  end
end

local function onScanMessage(_, phase)
  for _, page in ipairs(pages) do
    if ACTIVE[phase] then
      page.ui.ack, page.ui.doneAt = false, nil
    elseif phase == "done" then
      page.ui.ack, page.ui.doneAt = false, clock()
    elseif phase == "failed" then
      page.ui.ack = false
    end
  end
  refreshVisible()
end

ns.On("FG_PRICES_SCAN", onScanMessage)
ns.On("FG_PRICES_UPDATED", refreshVisible)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.priceDb") then
    refreshVisible()
  end
end)
ns.On("FG_PROFROUTE_CHANGED", function(_, key)
  if key == "autoOpen" then
    refreshVisible()
  end
end)
-- The house of the visit is told when the window opens.
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }) do
  ns.On(event, function()
    ns.Debounce("auctionset-visit", 0.2, refreshVisible)
  end)
end

-- A finished or failed scan was seen once the auction house closes: the next visit starts clean.
function AS.Acknowledge()
  for _, page in ipairs(pages) do
    page.ui.ack, page.ui.doneAt = true, nil
  end
end

ns.On("AUCTION_HOUSE_CLOSED", AS.Acknowledge)

-- Builds the page as a child of `parent`; the caller anchors it. Returns the page frame with
-- page.controls (the keyboard order) and page.Refresh().
function AS.Build(parent)
  local page = CreateFrame("Frame", nil, parent)
  page.ui = { ack = false }
  local area = W.ScrollArea(page)
  area:SetAllPoints()
  local stack = W.Stack(area, PAD)
  local view = { area = area, stack = stack, content = area.content }
  page.view = {
    Layout = function()
      stack:Layout()
    end,
  }
  area:HookScript("OnSizeChanged", function()
    ns.Debounce(page.view, 0.05, function()
      stack:Layout()
    end)
  end)
  local content = area.content

  local function text(role, color, key)
    local fs = W.Text(content, { key = key, role = role, color = color, wrap = true })
    return fs
  end

  -- Price data.
  ns.AddHeading(view, "auctionset.heading.data")
  page.house = text("ui", "text")
  stack:Add(page.house, { gap = 4 })
  page.items = text("ui", "textSecondary")
  stack:Add(page.items, { gap = 4 })
  page.last = text("ui", "textSecondary")
  stack:Add(page.last, { gap = 4 })
  page.neutral = text("ui", "textSecondary")
  stack:Add(page.neutral, { gap = 4 })

  -- Full scan.
  ns.AddHeading(view, "auctionset.heading.scan", { gap = 6 })
  page.scan = W.Action(content, {
    key = "auctionset.scan.start",
    icon = "play",
    tooltip = "auctionset.heading.scan",
    tooltipText = "auctionset.scan.tip",
    height = 28,
    wrap = "auctionset-scan",
    onClick = function()
      local db = ns.PriceDb
      if page.mode == "cancel" then
        db.CancelScan()
      else
        page.ui.ack = false
        db.StartScan()
      end
      refresh(page)
    end,
  })
  stack:Add(page.scan, { height = 28, gap = 6 })
  page.blocked = text("micro", "textMuted")
  stack:Add(page.blocked, { gap = 6 })
  page.progress = CreateFrame("Frame", nil, content)
  page.pct = W.Text(page.progress, { role = "micro", color = "text", justify = "RIGHT" })
  page.pct:SetPoint("RIGHT", 0, 0)
  page.pct:SetWidth(PCT_W)
  page.bar = CreateFrame("StatusBar", nil, page.progress)
  page.bar:SetHeight(BAR_H)
  page.bar:SetPoint("LEFT", 0, 0)
  page.bar:SetPoint("RIGHT", page.pct, "LEFT", -6, 0)
  page.bar:SetMinMaxValues(0, 100)
  page.bar:SetValue(0)
  page.bar.track = page.bar:CreateTexture(nil, "BACKGROUND")
  page.bar.track:SetAllPoints()
  page.bar.fill = page.bar:CreateTexture(nil, "ARTWORK")
  page.bar:SetStatusBarTexture(page.bar.fill)
  ns.Bind(page.bar, paintBar)
  stack:Add(page.progress, { height = 18, gap = 4 })
  page.phase = text("micro", "textSecondary")
  stack:Add(page.phase, { gap = 6 })
  page.failure = text("ui", "danger")
  stack:Add(page.failure, { gap = 6 })
  local note = text("micro", "textMuted", "auctionset.scan.note")
  stack:Add(note, { gap = 4 })
  local passive = text("micro", "textMuted", "auctionset.scan.passive")
  stack:Add(passive, { gap = 8 })

  -- Options.
  ns.AddHeading(view, "auctionset.heading.options", { gap = 6 })
  page.autoOpen = W.Checkbox(content, {
    key = "auctionset.autoOpen",
    tooltip = "auctionset.autoOpen",
    tooltipText = "shoplist.autoOpenTip",
    get = function()
      return ns.ProfessionShop.Option("autoOpen")
    end,
    set = function(v)
      ns.ProfessionShop.SetOption("autoOpen", v)
    end,
  })
  stack:Add(page.autoOpen, { height = 22, gap = 6 })
  page.tooltip = W.Checkbox(content, {
    key = "auctionset.tooltip",
    tooltip = "auctionset.tooltip",
    get = function()
      return Store.get("settings.priceDb.tooltip") ~= false
    end,
    set = function(v)
      Store.set("settings.priceDb.tooltip", v)
    end,
  })
  stack:Add(page.tooltip, { height = 22, gap = 8 })
  stack:Add(text("ui", "text", "auctionset.days"), { gap = 4 })
  local function commitDays(value)
    local days = AS.ParseDays(value)
    if days then
      Store.set("settings.priceDb.maxAgeDays", days)
    end
    page.days.edit:SetText(tostring(AS.MaxAgeDays()))
  end
  page.days = W.EditBox(content, { height = 26, inset = 6, onEnter = commitDays })
  if page.days.edit.SetNumeric then
    page.days.edit:SetNumeric(true)
  end
  page.days.edit:SetMaxLetters(2)
  page.days.edit:HookScript("OnEditFocusLost", function(self)
    commitDays(self:GetText())
  end)
  stack:Add(page.days, { height = 26, width = DAYS_W, gap = 8 })
  page.clear = W.Action(content, {
    key = "auctionset.clear",
    icon = "trash",
    variant = "danger",
    tooltip = "auctionset.clear",
    height = 28,
    wrap = "auctionset-clear",
    onClick = function()
      ns.Dialogs.Confirm("auctionset.clearTitle", "auctionset.clearText", function()
        ns.PriceDb.Clear()
        ns.Notify(L["auctionset.cleared"], "success")
      end)
    end,
  })
  stack:Add(page.clear, { height = 28, gap = 8 })
  page.addon = text("micro", "textMuted", "auctionset.addon")
  stack:Add(page.addon, { gap = 4 })

  -- The tick: texts of a countdown and of a running scan change by the second.
  page.ticker = CreateFrame("Frame", nil, page)
  local waited = 0
  page.onTick = function(_, elapsed)
    waited = waited + elapsed
    if waited >= TICK then
      waited = 0
      ns.Safe("auctionset-tick", refresh, page)
    end
  end

  page.controls = { page.scan, page.autoOpen, page.tooltip, page.days, page.clear }
  page.Refresh = function()
    refresh(page)
  end
  page:HookScript("OnShow", function()
    ns.Safe("auctionset-show", refresh, page)
  end)
  ns.Bind(page, function()
    if page:IsVisible() then
      refresh(page)
    end
  end)
  pages[#pages + 1] = page
  return page
end
