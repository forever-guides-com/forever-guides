-- The shopping list window of the profession route: one movable, resizable window (also without the
-- main window) with the reagents of the chosen skill range, tick boxes saved per character and
-- profession, the switches "stock" and "surcharge", and the buttons for the shopping list and the copy
-- texts. Look (background, opacity, auto-hiding title bar) comes from Modules/WindowStyle.lua (kind
-- "profshop"); position, size, scale, look and open state live in ns.db.frames.profShop. Nothing here
-- touches protected frames, so it works in combat.
local _, ns = ...
local W, L, Theme, U, WS, K = ns.W, ns.L, ns.Theme, ns.U, ns.WindowStyle, ns.PageKit
local R, S = ns.ProfessionRouteLogic, ns.ProfessionShop

local SW = {}
ns.ProfessionShopWindow = SW

local HEAD_H = 22
local MIN_W, MIN_H, MAX_W, MAX_H = 480, 320, 800, 900
local DEFAULT_W, DEFAULT_H = 520, 480
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 2, 0.1
local ROW_H = 22
local PAD = 8
-- Column widths from the right edge: total, price, source, quantity.
local COL_TOTAL, COL_PRICE, COL_SOURCE, COL_QTY = 72, 72, 96, 44
local BOX = 16

WS.PREFIX.profshop = "profShopWindow"

ns.AddLocale("enUS", {
  ["profshop.title"] = "Shopping list",
  ["profshop.close"] = "Close shopping list",
  ["profshop.openPage"] = "Open the route page",
  ["profshop.grip"] = "Drag to resize",
  ["profshop.scaleTip"] = "Drag to move, {key:windowScale} zooms.",
  ["profshop.summary"] = "%s %d-%d, surcharge %d %%",
  ["profshop.stock"] = "Subtract stock",
  ["profshop.allChars"] = "All characters",
  ["profshop.surcharge"] = "Surcharge",
  ["profshop.surchargeTip"] = "Extra amount for crafts that need more tries.",
  ["profshop.send"] = "Send to shopping list",
  ["profshop.sendTip"] = "Creates a shopping list, vendor items stay out.",
  ["profshop.copy"] = "Copy as text",
  ["profshop.clear"] = "Clear ticks",
  ["profshop.col.item"] = "Item",
  ["profshop.col.qty"] = "Qty",
  ["profshop.col.source"] = "Source",
  ["profshop.col.price"] = "Price",
  ["profshop.col.total"] = "Total",
  ["profshop.empty"] = "Nothing to buy for this range.",
  ["profshop.footer"] = "Open: %s",
  ["profshop.footerUnpriced"] = "Open: %s (%d without price)",
  ["profshop.ticked"] = "%d of %d ticked",
  ["profshop.noPrice"] = "-",
  ["profshop.rowTip"] = "Click to tick off.",
  ["profshop.copy.title"] = "Shopping list",
  ["profshop.copy.hintImport"] = "Shopping list: paste this line into the import box.",
  ["profshop.copy.hintPlain"] = "Plain list.",
  ["profshop.copy.asPlain"] = "Plain list",
  ["profshop.copy.asImport"] = "Import line",
  ["profshop.copy.none"] = "Nothing to copy.",
})
ns.AddLocale("deDE", {
  ["profshop.title"] = "Einkaufsliste",
  ["profshop.close"] = "Einkaufsliste schließen",
  ["profshop.openPage"] = "Routen-Seite öffnen",
  ["profshop.grip"] = "Zum Ändern der Größe ziehen",
  ["profshop.scaleTip"] = "Ziehen verschiebt, {key:windowScale} zoomt.",
  ["profshop.summary"] = "%s %d-%d, Aufschlag %d %%",
  ["profshop.stock"] = "Bestand abziehen",
  ["profshop.allChars"] = "Alle Charaktere",
  ["profshop.surcharge"] = "Aufschlag",
  ["profshop.surchargeTip"] = "Zuschlag für Herstellungen mit mehr Versuchen.",
  ["profshop.send"] = "An Einkaufsliste senden",
  ["profshop.sendTip"] = "Erzeugt eine Einkaufsliste, ohne Händlerware.",
  ["profshop.copy"] = "Als Text kopieren",
  ["profshop.clear"] = "Haken löschen",
  ["profshop.col.item"] = "Item",
  ["profshop.col.qty"] = "Menge",
  ["profshop.col.source"] = "Beschaffung",
  ["profshop.col.price"] = "Preis",
  ["profshop.col.total"] = "Summe",
  ["profshop.empty"] = "Für diesen Bereich nichts zu kaufen.",
  ["profshop.footer"] = "Offen: %s",
  ["profshop.footerUnpriced"] = "Offen: %s (%d ohne Preis)",
  ["profshop.ticked"] = "%d von %d abgehakt",
  ["profshop.noPrice"] = "-",
  ["profshop.rowTip"] = "Klicken zum Abhaken.",
  ["profshop.copy.title"] = "Einkaufsliste",
  ["profshop.copy.hintImport"] = "Einkaufsliste: Zeile in das Import-Feld einfügen.",
  ["profshop.copy.hintPlain"] = "Einfache Liste.",
  ["profshop.copy.asPlain"] = "Textliste",
  ["profshop.copy.asImport"] = "Import-Zeile",
  ["profshop.copy.none"] = "Nichts zu kopieren.",
})

local frame

local function frameDb()
  local frames = ns.db.frames
  if type(frames.profShop) ~= "table" then
    frames.profShop = {}
  end
  return frames.profShop
end

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function scaleOf(db)
  return finite(db.scale) and U.clamp(db.scale, SCALE_MIN, SCALE_MAX) or 1
end

local function setBounds(f)
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  elseif f.SetMinResize then
    f:SetMinResize(MIN_W, MIN_H)
  end
end

local function place(f)
  local db = frameDb()
  setBounds(f)
  f:SetSize(
    U.clamp(finite(db.w) and db.w or DEFAULT_W, MIN_W, MAX_W),
    U.clamp(finite(db.h) and db.h or DEFAULT_H, MIN_H, MAX_H)
  )
  f:ClearAllPoints()
  local s = f:GetScale()
  if finite(db.x) and finite(db.y) then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
  end
end

local function savePosition(f)
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s, db = f:GetScale(), frameDb()
    db.x, db.y = left * s, top * s
  end
end

local function saveSize(f)
  local db = frameDb()
  db.w, db.h = f:GetWidth(), f:GetHeight()
end

-- Look -------------------------------------------------------------------------------------------

function SW.Style()
  return WS.Resolve("profshop", frameDb().style)
end

local function applyLook(f)
  local style = SW.Style()
  WS.Apply(f, style, f.styleParts)
  WS.ApplyShadow(f.title, WS.TextShadow(style), Theme.rgb("accent2"))
  return style
end

local function patchStyle(patch)
  local style = U.copy(frameDb().style or {})
  if patch.bg ~= nil then
    style.bg = patch.bg or nil
  end
  if patch.alpha ~= nil then
    style.alpha = patch.alpha
  end
  if patch.autoHide ~= nil then
    style.autoHide = patch.autoHide
  end
  frameDb().style = style
  if frame then
    applyLook(frame)
  end
end

function SW.OpenLook()
  if not frame then
    return nil
  end
  return WS.OpenPanel(frame.look, {
    frame = frame,
    kind = "profshop",
    get = SW.Style,
    set = patchStyle,
    onSaveDefault = function()
      WS.SaveDefault("profshop", SW.Style())
    end,
    onReset = function()
      frameDb().style = {}
      applyLook(frame)
    end,
  })
end

-- Scale: mouse wheel with the windowScale key (default Ctrl) on the title bar, the top left corner stays where it is.
local function changeScale(f, delta)
  local db = frameDb()
  savePosition(f)
  db.scale = U.clamp(math.floor(scaleOf(db) * 100 + delta * SCALE_STEP * 100 + 0.5) / 100, SCALE_MIN, SCALE_MAX)
  f:SetScale(db.scale)
  place(f)
end

-- Rows -------------------------------------------------------------------------------------------

local function plainMoney(copper)
  return copper and ns.CostLogic.Format(copper, { plain = true }) or L["profshop.noPrice"]
end

local function iconPath(icon)
  return type(icon) == "string" and icon ~= "" and ("Interface\\Icons\\" .. icon)
    or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Places the cells of a row (or of the header, which has the same cells) for a width.
local function layoutCells(row, width)
  row.total:ClearAllPoints()
  row.total:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
  row.total:SetWidth(COL_TOTAL - 4)
  row.price:ClearAllPoints()
  row.price:SetPoint("RIGHT", row, "RIGHT", -PAD - COL_TOTAL, 0)
  row.price:SetWidth(COL_PRICE - 4)
  row.source:ClearAllPoints()
  row.source:SetPoint("RIGHT", row, "RIGHT", -PAD - COL_TOTAL - COL_PRICE, 0)
  row.source:SetWidth(COL_SOURCE - 4)
  row.qty:ClearAllPoints()
  row.qty:SetPoint("RIGHT", row, "RIGHT", -PAD - COL_TOTAL - COL_PRICE - COL_SOURCE, 0)
  row.qty:SetWidth(COL_QTY - 4)
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", row, "LEFT", row.nameLeft, 0)
  row.name:SetWidth(math.max(20, width - row.nameLeft - PAD - COL_TOTAL - COL_PRICE - COL_SOURCE - COL_QTY - 4))
end

local function newCells(row)
  row.name = W.Text(row, { role = "ui" })
  row.qty = W.Text(row, { role = "ui", justify = "RIGHT" })
  row.source = W.Text(row, { role = "micro", color = "textSecondary" })
  row.price = W.Text(row, { role = "micro", color = "textSecondary", justify = "RIGHT" })
  row.total = W.Text(row, { role = "ui", justify = "RIGHT" })
end

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
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", PAD + BOX + 6, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.nameLeft = PAD + BOX + 6 + 18 + 6
  newCells(row)
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
    ns.Wrap("profshop-row", function(self, button)
      S.RowClick(self.line, button)
    end)
  )
  row.box:SetScript(
    "OnClick",
    ns.Wrap("profshop-tick", function()
      if row.line then
        S.SetChecked(row.slug, row.line.id, not row.ticked)
      end
    end)
  )
  row.box:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["profshop.rowTip"])
  end)
  row.box:SetScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(row, function(self)
    self:Click()
  end)
  ns.Focus.register(row.box, function(self)
    self:Click()
  end)
  function row:fgLayout(width)
    layoutCells(self, width)
    return ROW_H
  end
  return row
end

local function paintRow(row, item)
  local line, ticked = item.line, item.ticked
  row.line, row.slug, row.ticked = line, item.slug, ticked
  row.icon:SetTexture(iconPath(line.icon))
  row.icon:SetDesaturated(ticked)
  row.icon:SetAlpha(ticked and 0.5 or 1)
  row.mark:SetShown(ticked)
  row.boxOn:SetShown(ticked)
  row.boxBorder.set(ticked and "actionHi" or "white", ticked and 1 or 0.4)
  local color = ticked and "textMuted" or "text"
  -- A ticked line is done and stays muted, an open one shows the quality color of its item.
  row.name:SetText(ticked and line.name or ns.ItemInfo.ColorName(line.name, ns.ItemInfo.quality(line.id)))
  W.SetColor(row.name, color)
  row.qty:SetText(tostring(line.qty))
  W.SetColor(row.qty, color)
  row.source:SetText(L["profshop.group." .. line.source])
  row.price:SetText(plainMoney(line.price))
  row.total:SetText(plainMoney(line.total))
  W.SetColor(row.total, color)
end

local function newHeader(parent)
  local head = CreateFrame("Frame", nil, parent)
  head:SetHeight(ROW_H)
  head.nameLeft = PAD
  newCells(head)
  for cell, key in pairs({
    name = "profshop.col.item",
    qty = "profshop.col.qty",
    source = "profshop.col.source",
    price = "profshop.col.price",
    total = "profshop.col.total",
  }) do
    W.SetText(head[cell], key)
    W.SetColor(head[cell], "accent2")
  end
  head:SetScript("OnSizeChanged", function(_, width)
    layoutCells(head, width)
  end)
  layoutCells(head, MIN_W - 2 * PAD)
  return head
end

-- Window ---------------------------------------------------------------------------------------

-- The flat list behind the table: the lines of the plan in the order of their source groups.
local function items(plan)
  local out, checked = {}, S.Checked(plan.slug)
  for _, g in ipairs(plan.groups or {}) do
    for _, line in ipairs(g.lines) do
      out[#out + 1] = { line = line, slug = plan.slug, ticked = checked[line.id] == true }
    end
  end
  return out
end

local function refresh(f)
  local plan = S.Plan()
  f.plan = plan
  f.empty:SetShown(false)
  local offered = f.banner:Update(not plan.data and plan.status == ns.ProfessionRouteData.STATUS.missing)
  if not plan.data then
    f.summary:SetText(offered and "" or ns.ProfessionRouteData.Hint(plan.status))
    f.pool:Sync({}, paintRow)
    f.footer:SetText("")
    f.view:Layout()
    f.cbStock.Refresh()
    f.cbAll.Refresh()
    f.cbSurcharge.Refresh()
    return
  end
  f.summary:SetText(string.format(L["profshop.summary"], plan.name, plan.from, plan.to, S.Option("surcharge")))
  local list = items(plan)
  f.pool:Sync(list, paintRow)
  f.empty:SetShown(#list == 0)
  local ticked = 0
  for _, item in ipairs(list) do
    if item.ticked then
      ticked = ticked + 1
    end
  end
  local open, unpriced = R.Cost(R.Group(R.Pending(plan.lines, S.Checked(plan.slug))))
  local money = open > 0 and plainMoney(open) or L["profshop.noPrice"]
  local footer = unpriced > 0 and string.format(L["profshop.footerUnpriced"], money, unpriced)
    or string.format(L["profshop.footer"], money)
  f.footer:SetText(footer .. (#list > 0 and ("  ·  " .. string.format(L["profshop.ticked"], ticked, #list)) or ""))
  f.cbStock.Refresh()
  f.cbAll.Refresh()
  f.cbSurcharge.Refresh()
  f.view:Layout()
end

-- Copy texts: the import line first, a button switches to the plain list and back.
local function showCopy(plain, given)
  local plan = given or frame and frame.plan or S.Plan()
  if not plan.data or #(plan.lines or {}) == 0 then
    ns.Notify(L["profshop.copy.none"], "info")
    return
  end
  if plain then
    ns.Dialogs.Copy("profshop.copy.title", S.PlainText(plan), "profshop.copy.hintPlain", {
      {
        key = "profshop.copy.asImport",
        onClick = function()
          showCopy(false, plan)
        end,
      },
    })
  else
    ns.Dialogs.Copy("profshop.copy.title", (S.ImportText(plan)), "profshop.copy.hintImport", {
      {
        key = "profshop.copy.asPlain",
        onClick = function()
          showCopy(true, plan)
        end,
      },
    })
  end
end
SW.ShowCopy = showCopy

-- "An Einkaufsliste senden": a list in the connected addon when it can, the copy text otherwise. A caller
-- without the window (the auction house tab) passes its own fresh plan.
function SW.Send(given)
  local plan = given or frame and frame.plan or S.Plan()
  if not plan.data then
    ns.Notify(ns.ProfessionRouteData.Hint(plan.status), "warning")
    return "nodata"
  end
  local result, count = S.Send(plan)
  if result == "sent" then
    ns.Notify(string.format(L["profshop.sent"], count), "success")
  elseif result == "nothing" then
    ns.Notify(L["profshop.nothing"], "info")
  else
    ns.Notify(L["profshop." .. result], result == "failed" and "error" or "warning")
    showCopy(false, plan)
  end
  return result
end

local function create()
  local f = CreateFrame("Frame", "FGProfShopWindow", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  setBounds(f)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.shell = ns.WindowShell.Attach(f, { title = "profshop.title", titleHeight = HEAD_H, shadow = true })
  f.border, f.bar, f.barBg, f.title = f.shell.border, f.shell.titleBar, f.shell.barFill, f.shell.titleText

  f.bar:EnableMouse(true)
  f.bar:RegisterForDrag("LeftButton")
  f.bar:SetScript("OnDragStart", function()
    WS.Hold(f, "move", true)
    f:StartMoving()
  end)
  f.bar:SetScript(
    "OnDragStop",
    ns.Wrap("profshop-move", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "move", false)
      savePosition(f)
    end)
  )
  f.bar:EnableMouseWheel(true)
  f.bar:SetScript(
    "OnMouseWheel",
    ns.Wrap("profshop-scale", function(_, delta)
      if ns.Keys.Matches("windowScale") then
        changeScale(f, delta)
      end
    end)
  )
  f.bar:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["profshop.title"], L["profshop.scaleTip"])
  end)
  f.bar:SetScript("OnLeave", ns.HideTooltip)

  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "profshop.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    ns.Wrap("profshop-close", function()
      f:Hide()
    end)
  )
  f.look = W.Action(f.bar, { icon = "palette", size = 18, tooltip = "wstyle.title" })
  f.look:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
  f.look:SetScript(
    "OnClick",
    ns.Wrap("profshop-look", function()
      SW.OpenLook()
    end)
  )
  f.open = W.Action(f.bar, { icon = "open", size = 18, tooltip = "profshop.openPage" })
  f.open:SetPoint("RIGHT", f.look, "LEFT", -2, 0)
  f.open:SetScript(
    "OnClick",
    ns.Wrap("profshop-open-page", function()
      ns.Main.Show("professionroute")
    end)
  )
  f.title:ClearAllPoints()
  f.title:SetPoint("LEFT", 8, 0)
  f.title:SetPoint("RIGHT", f.open, "LEFT", -4, 0)

  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", PAD, -(HEAD_H + 6))
  content:SetPoint("BOTTOMRIGHT", -PAD, 18)
  f.content = content

  f.summary = W.Text(content, { role = "ui", color = "accent2", wrap = true })
  f.summary:SetPoint("TOPLEFT", 0, 0)
  f.summary:SetPoint("RIGHT", 0, 0)

  -- Switches: the surcharge toggles between none and the default.
  f.cbStock = W.Checkbox(content, {
    key = "profshop.stock",
    get = function()
      return S.Option("stock")
    end,
    set = function(v)
      S.SetOption("stock", v)
    end,
  })
  f.cbAll = W.Checkbox(content, {
    key = "profshop.allChars",
    get = function()
      return S.Option("all")
    end,
    set = function(v)
      S.SetOption("all", v)
    end,
  })
  f.cbSurcharge = W.Checkbox(content, {
    key = "profshop.surcharge",
    tooltip = "profshop.surcharge",
    tooltipText = "profshop.surchargeTip",
    get = function()
      return S.Option("surcharge") > 0
    end,
    set = function(v)
      S.SetOption("surcharge", v and R.DEFAULT_SURCHARGE or 0)
    end,
  })
  f.cbStock:SetPoint("TOPLEFT", f.summary, "BOTTOMLEFT", 0, -8)
  f.cbAll:SetPoint("LEFT", f.cbStock, "RIGHT", 8, 0)
  f.cbSurcharge:SetPoint("LEFT", f.cbAll, "RIGHT", 8, 0)

  f.send = W.Action(content, {
    label = "act.send",
    icon = "share",
    tooltip = "profshop.send",
    tooltipText = "profshop.sendTip",
    onClick = function()
      SW.Send()
    end,
  })
  f.copy = W.Action(content, {
    label = "act.text",
    icon = "copy",
    tooltip = "profshop.copy",
    onClick = function()
      showCopy(false)
    end,
  })
  f.clear = W.Action(content, {
    label = "act.clear",
    icon = "trash",
    tooltip = "profshop.clear",
    onClick = function()
      S.ClearChecked(S.Slug())
    end,
  })
  f.send:SetPoint("TOPLEFT", f.cbStock, "BOTTOMLEFT", 0, -8)
  f.copy:SetPoint("LEFT", f.send, "RIGHT", 6, 0)
  f.clear:SetPoint("LEFT", f.copy, "RIGHT", 6, 0)

  f.header = newHeader(content)
  f.header:SetPoint("TOPLEFT", f.send, "BOTTOMLEFT", 0, -10)
  f.header:SetPoint("RIGHT", 0, 0)

  f.footer = W.Text(content, { role = "ui", color = "accent2", justify = "LEFT" })
  f.footer:SetPoint("BOTTOMLEFT", 0, 0)
  f.footer:SetPoint("BOTTOMRIGHT", 0, 0)

  local host = CreateFrame("Frame", nil, content)
  host:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -2)
  host:SetPoint("BOTTOMRIGHT", f.footer, "TOPRIGHT", 0, 6)
  local area = W.ScrollArea(host)
  area:SetAllPoints()
  local stack = W.Stack(area, 0)
  f.pool = K.RowPool(area.content, newRow)
  stack:Add(f.pool, { gap = 0 })
  f.view = { area = area, stack = stack }
  function f.view:Layout()
    stack:Layout()
  end
  area:HookScript("OnSizeChanged", function()
    ns.Debounce(f.view, 0.05, function()
      stack:Layout()
    end)
  end)
  -- Takes the place of the empty list while the data add-on is off or missing.
  f.banner = ns.PackageUI.Banner(content, ns.ProfessionRouteData.ADDON, {
    onLoaded = function()
      refresh(f)
    end,
  })
  f.banner:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -4)
  f.banner:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -4)
  f.empty = W.Text(host, { key = "profshop.empty", role = "ui", color = "textMuted", justify = "CENTER" })
  f.empty:SetPoint("TOP", 0, -12)
  f.empty:SetPoint("LEFT", 0, 0)
  f.empty:SetPoint("RIGHT", 0, 0)
  f.empty:Hide()

  -- Buttons and switches share the width in thirds.
  local function split(_, w)
    local third = math.floor((w - 12) / 3)
    for _, b in ipairs({ f.send, f.copy, f.clear }) do
      b:SetWidth(third)
    end
    local sw = math.floor((w - 16) / 3)
    for _, c in ipairs({ f.cbStock, f.cbAll, f.cbSurcharge }) do
      c:SetWidth(sw)
    end
  end
  content:SetScript("OnSizeChanged", split)
  split(nil, MIN_W - 2 * PAD)

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  local gripTex = grip:CreateTexture(nil, "OVERLAY")
  gripTex:SetAllPoints()
  gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function()
    WS.Hold(f, "size", true)
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript(
    "OnMouseUp",
    ns.Wrap("profshop-size", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "size", false)
      saveSize(f)
      savePosition(f)
      split(nil, content:GetWidth())
    end)
  )
  grip:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["profshop.grip"])
  end)
  grip:SetScript("OnLeave", ns.HideTooltip)
  f.grip = grip

  f.styleParts = {
    bg = { f.bg },
    bars = { f.barBg },
    border = f.border,
    shadow = f.shell.shadow,
    chrome = { f.bar, grip },
    busy = function()
      return WS.PanelOpenFor(f) or WS.PickerOpenFor(f)
    end,
  }

  f:SetScript(
    "OnShow",
    ns.Wrap("profshop-show", function()
      frameDb().shown = true
      ns.WindowShell.SetEsc(f, true)
      refresh(f)
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("profshop-hide", function()
      frameDb().shown = false
      ns.WindowShell.SetEsc(f, false)
    end)
  )
  f:Hide()
  return f
end

function SW.IsShown()
  return frame ~= nil and frame:IsShown()
end

function SW.Frame()
  return frame
end

function SW.Open()
  if not ns.db then
    return
  end
  if not frame then
    frame = create()
  end
  frame:SetScale(scaleOf(frameDb()))
  place(frame)
  applyLook(frame)
  if frame:IsShown() then
    refresh(frame)
  else
    frame:Show()
  end
  frame:Raise()
end

function SW.Hide()
  if frame then
    frame:Hide()
  end
end

function SW.Toggle()
  if SW.IsShown() then
    SW.Hide()
  else
    SW.Open()
  end
end

-- /fg einkauf: without text the window toggles, with a profession name it shows that profession.
function SW.Slash(rest)
  rest = U.trim(rest or "")
  if rest == "" then
    SW.Toggle()
    return
  end
  local slug = R.SlugFromText(rest)
  if slug then
    S.SetOption("slug", slug)
  end
  SW.Open()
end

ns.On("FG_PROFROUTE_CHANGED", function()
  if frame and frame:IsShown() then
    refresh(frame)
  end
end)
-- The stock and the skill change while the window is open.
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED" }) do
  ns.On(event, function()
    if frame and frame:IsShown() then
      ns.Debounce("profshop-refresh", 0.5, function()
        if frame:IsShown() then
          refresh(frame)
        end
      end)
    end
  end)
end
ns.On("FG_SETTING_CHANGED", function(_, path)
  if frame and frame:IsShown() and WS.AffectsKind(path, "profshop") then
    applyLook(frame)
  end
end)
ns.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    savePosition(frame)
    saveSize(frame)
  end
end)
ns.On("PLAYER_LOGIN", function()
  if ns.db and frameDb().shown == true then
    SW.Open()
  end
end)
