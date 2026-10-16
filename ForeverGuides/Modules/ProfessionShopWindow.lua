-- The shopping list window of the profession route: one movable, resizable window (also without the
-- main window) with the reagents of the chosen skill range, tick boxes saved per character and
-- profession, the switches "stock" and "surcharge", per position the amount to buy (field and buttons),
-- how much of it is there ("have/need"), a remove button, and the buttons for the chat link, the
-- auction list, the copy texts and cleaning the list up (ProfessionList.lua holds the changes). The
-- rows come from S.View, the same list the auction house panel (AuctionLink.lua) shows, in the view
-- the player chose (combined or by reason). Look (background, opacity, auto-hiding title bar) comes
-- from Modules/WindowStyle.lua (kind "profshop"); position, size, scale, look and open state live in
-- ns.db.frames.profShop. Nothing here touches protected frames, so it works in combat.
local _, ns = ...
local W, L, Theme, U, WS, K = ns.W, ns.L, ns.Theme, ns.U, ns.WindowStyle, ns.PageKit
local R, S, PL, CL = ns.ProfessionRouteLogic, ns.ProfessionShop, ns.ProfessionListLogic, ns.CostLogic

local SW = {}
ns.ProfessionShopWindow = SW

local HEAD_H = 22
local MIN_W, MIN_H, MAX_W, MAX_H = 620, 440, 900, 900
local DEFAULT_W, DEFAULT_H = 680, 560
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 2, 0.1
local ROW_H = 22
local PAD = 8
-- Column slots from the right edge: remove button, total, price, source, amount controls, have/need.
-- SW.Columns turns them into the spans the header and every row share. Total and price are the least
-- widths; they grow to hold the coin icons of the widest amount (see measureMoney).
local COL_DEL, COL_TOTAL, COL_PRICE, COL_SOURCE, COL_PROG = 22, 64, 64, 88, 84
local NAME_ROOM = 100 -- the least width the item name keeps when the window grows for the amounts
local GAP = 4 -- empty space at the left of a slot
local MAG = 12 -- the magnifier that says "a click searches"
local INDENT = 12 -- per level of a material under a crafted item
local STEP = 16
-- The amount field must show four digits at any font size: width of a digit as a share of the font size
-- (the widest digit of the font with some air), inset of the text, smallest width.
local FIELD_DIGIT, FIELD_INSET, FIELD_MIN = 0.6, 2, 34
local BOX = 16
-- The rows sit in a W.ScrollArea stack: it starts LIST_INSET in and keeps LIST_RESERVE at the right for its
-- scroll bar (shown or not), the header takes the same span.
local LIST_INSET, LIST_RESERVE = 2, 12
local NAME_X = PAD + BOX + 6 + 18 + 6 -- the item name, behind the tick box and the icon
local JUSTIFY = { name = "LEFT", prog = "RIGHT", qty = "CENTER", source = "LEFT", price = "RIGHT", total = "RIGHT" }
local SEARCH_H = 22
local SEP_GAP = 12 -- space above a group of the by reason view, a thin rule sits in the middle of it

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
  ["profshop.link"] = "Send as link in chat",
  ["profshop.linkTip"] = "Puts the list into the chat as one clickable link.",
  ["profshop.btn.auction"] = "Auction list",
  ["profshop.btn.removeDone"] = "Remove done",
  ["profshop.removeDone"] = "Remove done positions",
  ["profshop.removeDoneTip"] = "Ticked positions leave the list.",
  ["profshop.btn.clearAll"] = "Empty list",
  ["profshop.clearAll"] = "Empty the shopping list",
  ["profshop.clearAllText"] = "Remove every position from the shopping list?",
  ["profshop.btn.restore"] = "Restore",
  ["profshop.restore"] = "Restore removed lines",
  ["profshop.restoreTip"] = "Brings back removed route lines and their amounts.",
  ["profshop.qtyUp"] = "More",
  ["profshop.qtyDown"] = "Less",
  ["profshop.remove"] = "Remove position",
  ["profshop.qtyInvalid"] = "Enter a whole amount from %d to 9999.",
  ["shoplist.col.sourceShort"] = "Source",
  ["shoplist.col.itemTip"] = "The item. Indented rows are materials of an item you craft yourself.",
  ["shoplist.col.qtyTip"] = "Amount to buy: needed minus stock. Click - or + for one, or type a number.",
  ["shoplist.col.sourceTip"] = "Where the item comes from. On craftable items a click switches between crafting and the auction house.",
  ["shoplist.col.priceTip"] = "Price per item, from the vendor or the auction house data. ~ marks old data or data of the price add-on.",
  ["shoplist.col.totalTip"] = "Price times the amount to buy.",
  ["shoplist.col.progress"] = "Have/Need",
  ["shoplist.col.progressShort"] = "Stock",
  ["shoplist.col.progressTip"] = "Owned / needed. Green: covered, orange: partly, grey: none.",
  ["shoplist.view.combined"] = "Combined",
  ["shoplist.view.combinedTip"] = "The same item from every reason in one row. Items you craft yourself are shown under By reason, their materials are in the rows.",
  ["shoplist.view.reason"] = "By reason",
  ["shoplist.view.reasonTip"] = "One block per reason, the stock goes to the first reason in the list first.",
  ["shoplist.search"] = "Search list",
  ["shoplist.noMatches"] = "No matches",
  ["shoplist.hits"] = "Hits: %d",
  ["shoplist.rowGroupTip"] = "Ticks or unticks the item and all of its materials, also those a search hides.",
  ["shoplist.autoOpen"] = "Open at auction house",
  ["shoplist.autoOpenTip"] = "Opens this list by itself next to the auction house.",
  ["shoplist.craftAll"] = "Craft all",
  ["shoplist.craftAllTip"] = "Every craftable item is crafted, its materials are listed.",
  ["shoplist.auctionAll"] = "All at AH",
  ["shoplist.auctionAllTip"] = "Every craftable item is bought at the auction house.",
  ["shoplist.craft.short"] = "Craft",
  ["shoplist.ah.short"] = "AH",
  ["shoplist.craft.title"] = "Craft or buy",
  ["shoplist.craft.on"] = "Crafting it yourself, its materials are on the list. Click to buy it at the auction house.",
  ["shoplist.craft.off"] = "Buying it at the auction house. Click to craft it yourself, its materials join the list.",
  ["shoplist.rowCrafted"] = "Crafted by you, its materials are on the list.",
  ["shoplist.rowComplete"] = "The stock covers it, nothing to buy.",
  ["shoplist.rowMerged"] = "The amount is a sum, change it in the by reason view.",
  ["shoplist.rowDerived"] = "Derived from the recipe, change the quantity of the item that needs it.",
  ["shoplist.total"] = "Total",
  ["shoplist.totalUnpriced"] = "Total (%d without price)",
  ["shoplist.totalTitle"] = "Total cost of the list",
  ["shoplist.totalTip"] = "Everything still to buy: the lowest price of each item times the amount to buy. The stock is subtracted when Subtract stock is on, the surcharge is included. Ticked rows are not counted.",
  ["shoplist.totalUnpricedTip"] = "%d items have no price yet and are not in the sum. Scan the prices in the auction house, tab Settings.",
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
  ["profshop.link"] = "Link in den Chat senden",
  ["profshop.linkTip"] = "Setzt die Liste als einen klickbaren Link in den Chat.",
  ["profshop.btn.auction"] = "Auktionsliste",
  ["profshop.btn.removeDone"] = "Erledigte entfernen",
  ["profshop.removeDone"] = "Erledigte Positionen entfernen",
  ["profshop.removeDoneTip"] = "Abgehakte Positionen verlassen die Liste.",
  ["profshop.btn.clearAll"] = "Liste leeren",
  ["profshop.clearAll"] = "Einkaufsliste leeren",
  ["profshop.clearAllText"] = "Alle Positionen aus der Einkaufsliste entfernen?",
  ["profshop.btn.restore"] = "Zurücksetzen",
  ["profshop.restore"] = "Entfernte Zeilen zurückholen",
  ["profshop.restoreTip"] = "Holt entfernte Routenzeilen und ihre Mengen zurück.",
  ["profshop.qtyUp"] = "Mehr",
  ["profshop.qtyDown"] = "Weniger",
  ["profshop.remove"] = "Position entfernen",
  ["profshop.qtyInvalid"] = "Gib eine ganze Menge von %d bis 9999 ein.",
  ["shoplist.col.sourceShort"] = "Quelle",
  ["shoplist.col.itemTip"] = "Das Item. Eingerückte Zeilen sind Materialien eines Items, das du selbst herstellst.",
  ["shoplist.col.qtyTip"] = "Zu kaufende Menge: Bedarf minus Bestand. Mit - oder + um eins ändern oder eine Zahl tippen.",
  ["shoplist.col.sourceTip"] = "Woher das Item kommt. Bei herstellbaren Items wechselt ein Klick zwischen Herstellen und Auktionshaus.",
  ["shoplist.col.priceTip"] = "Preis pro Item, vom Händler oder aus den Auktionshaus-Daten. ~ markiert alte Daten oder Daten des Preis-Addons.",
  ["shoplist.col.totalTip"] = "Preis mal zu kaufende Menge.",
  ["shoplist.col.progress"] = "Bestand/Bedarf",
  ["shoplist.col.progressShort"] = "Bestand",
  ["shoplist.col.progressTip"] = "Vorhanden / benötigt. Grün: gedeckt, orange: teilweise, grau: nichts.",
  ["shoplist.view.combined"] = "Zusammen",
  ["shoplist.view.combinedTip"] = "Dasselbe Item aus allen Gründen in einer Zeile. Selbst hergestellte Items stehen unter Nach Grund, ihre Materialien in den Zeilen.",
  ["shoplist.view.reason"] = "Nach Grund",
  ["shoplist.view.reasonTip"] = "Ein Block je Grund, der Bestand geht zuerst an den ersten Grund der Liste.",
  ["shoplist.search"] = "Liste durchsuchen",
  ["shoplist.noMatches"] = "Keine Treffer",
  ["shoplist.hits"] = "Treffer: %d",
  ["shoplist.rowGroupTip"] = "Hakt das Item und alle seine Materialien ab oder wieder ab, auch die von der Suche ausgeblendeten.",
  ["shoplist.autoOpen"] = "Im Auktionshaus öffnen",
  ["shoplist.autoOpenTip"] = "Öffnet diese Liste von selbst neben dem Auktionshaus.",
  ["shoplist.craftAll"] = "Alles herstellen",
  ["shoplist.craftAllTip"] = "Jedes herstellbare Item wird selbst hergestellt, die Materialien stehen in der Liste.",
  ["shoplist.auctionAll"] = "Alles im AH",
  ["shoplist.auctionAllTip"] = "Jedes herstellbare Item wird im Auktionshaus gekauft.",
  ["shoplist.craft.short"] = "Herst.",
  ["shoplist.ah.short"] = "AH",
  ["shoplist.craft.title"] = "Herstellen oder kaufen",
  ["shoplist.craft.on"] = "Wird selbst hergestellt, die Materialien stehen in der Liste. Klick: im Auktionshaus kaufen.",
  ["shoplist.craft.off"] = "Wird im Auktionshaus gekauft. Klick: selbst herstellen, die Materialien kommen in die Liste.",
  ["shoplist.rowCrafted"] = "Selbst hergestellt, die Materialien stehen in der Liste.",
  ["shoplist.rowComplete"] = "Der Bestand deckt es, nichts zu kaufen.",
  ["shoplist.rowMerged"] = "Die Menge ist eine Summe, änderbar in der Ansicht Nach Grund.",
  ["shoplist.rowDerived"] = "Ergibt sich aus dem Rezept, ändere die Menge des Items, das es braucht.",
  ["shoplist.total"] = "Gesamt",
  ["shoplist.totalUnpriced"] = "Gesamt (%d ohne Preis)",
  ["shoplist.totalTitle"] = "Gesamtkosten der Liste",
  ["shoplist.totalTip"] = "Alles, was noch zu kaufen ist: der niedrigste Preis jedes Items mal die zu kaufende Menge. Der Bestand ist abgezogen, wenn Bestand abziehen an ist, der Aufschlag ist eingerechnet. Abgehakte Zeilen zählen nicht.",
  ["shoplist.totalUnpricedTip"] = "%d Items haben noch keinen Preis und fehlen in der Summe. Preise scannen im Auktionshaus, Tab Einstellungen.",
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
  local minW = SW.MinWidth()
  if f.SetResizeBounds then
    f:SetResizeBounds(minW, MIN_H, MAX_W, MAX_H)
  elseif f.SetMinResize then
    f:SetMinResize(minW, MIN_H)
  end
end

local function place(f)
  local db = frameDb()
  setBounds(f)
  f:SetSize(
    U.clamp(finite(db.w) and db.w or DEFAULT_W, SW.MinWidth(), MAX_W),
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

-- The amount with coin icons for a cell of the list, "-" without a price.
local function money(copper)
  return copper and CL.Format(copper) or L["profshop.noPrice"]
end

-- Width the amount columns need for the rows shown, at the current font size: the widest price (with
-- the marker of an old price), the widest total and the widest section total, which spans both columns.
-- The least widths of the slots hold the plain texts; the icons make the amounts wider than a letter.
local need = { price = 0, total = 0, head = 0 }

local function measureMoney(rows)
  local sizePrice, sizeTotal = Theme.fontSize("micro"), Theme.fontSize("ui")
  local mark = 2 * math.ceil(0.6 * sizePrice)
  need = { price = 0, total = 0, head = 0 }
  for _, item in ipairs(rows or {}) do
    if item.kind == "header" then
      need.head = math.max(need.head, CL.Width(sizeTotal, item.open))
    else
      local line = item.line
      local price = CL.Width(sizePrice, line.price)
      need.price = math.max(need.price, price > 0 and price + mark or 0)
      need.total = math.max(need.total, CL.Width(sizeTotal, line.total or (item.head and item.open) or nil))
    end
  end
end

-- Widths of the price and the total slot: the least width or what the widest amount needs, the section
-- total also fits across both.
local function moneySlots()
  local price = math.max(COL_PRICE, need.price + GAP + 2)
  local total = math.max(COL_TOTAL, need.total + GAP + 2)
  total = math.max(total, need.head + GAP + 2 - price)
  return price, total
end

-- Width of the amount field: four digits at the current font size, so "30" is never cut to "0".
local function fieldWidth()
  return math.max(FIELD_MIN, math.ceil(Theme.fontSize("body") * FIELD_DIGIT * 4) + 2 * FIELD_INSET + 2)
end

-- The one column table of the header and every row, for a row width: per column the left edge x (from the
-- left edge of the row), the width w and the justification. Numbers are right aligned under right aligned
-- headers, the amount group (minus, field, plus) is centered under its header, texts are left aligned. The
-- slot of a column starts GAP before its span. qty.field is the width of the amount field.
function SW.Columns(width)
  local field = fieldWidth()
  local pricePart, totalPart = moneySlots()
  local cols, edge = {}, width - PAD
  local function take(key, slot)
    edge = edge - slot
    cols[key] = { x = edge + GAP, w = slot - GAP, justify = JUSTIFY[key] }
  end
  edge = edge - COL_DEL
  cols.del = { x = edge, w = COL_DEL, justify = "CENTER" }
  take("total", totalPart)
  take("price", pricePart)
  take("source", COL_SOURCE)
  take("qty", GAP + 2 * STEP + 4 + field)
  cols.qty.field = field
  take("prog", COL_PROG)
  cols.name = { x = NAME_X, w = math.max(20, edge - GAP - NAME_X), justify = JUSTIFY.name }
  return cols
end

-- The least window width: the fixed columns, the amount columns for the rows shown and room for a name.
function SW.MinWidth()
  local price, total = moneySlots()
  local field = fieldWidth()
  local columns = COL_DEL + total + price + COL_SOURCE + (GAP + 2 * STEP + 4 + field) + COL_PROG
  local wanted = columns + NAME_X + GAP + NAME_ROOM + 3 * PAD + LIST_INSET + LIST_RESERVE
  return U.clamp(wanted, MIN_W, MAX_W)
end

local function placeCell(cell, c)
  cell:ClearAllPoints()
  cell:SetPoint("LEFT", cell:GetParent(), "LEFT", c.x, 0)
  cell:SetWidth(c.w)
  cell.fgJustify = c.justify
  cell:SetJustifyH(c.justify)
end

-- Places the cells of a row (or of the header, which has the same cells) for a width. A row has the
-- amount controls and the remove button, the header the "Qty" text over the controls.
local function layoutCells(row, width)
  local cols = SW.Columns(width)
  if row.del then
    row.del:ClearAllPoints()
    row.del:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
  end
  for _, key in ipairs({ "total", "price", "source", "prog" }) do
    placeCell(row[key], cols[key])
  end
  if row.headTotal then
    -- A section total sits across the price and the total column.
    row.headTotal:SetWidth(cols.price.w + cols.total.w + GAP)
  end
  local qty = cols.qty
  if row.plus then
    row.minus:ClearAllPoints()
    row.minus:SetPoint("LEFT", row, "LEFT", qty.x, 0)
    row.qtyBox:ClearAllPoints()
    row.qtyBox:SetPoint("LEFT", row.minus, "RIGHT", 2, 0)
    row.qtyBox:SetWidth(qty.field)
    row.plus:ClearAllPoints()
    row.plus:SetPoint("LEFT", row.qtyBox, "RIGHT", 2, 0)
  else
    placeCell(row.qty, qty)
  end
  local left = cols.name.x + (row.indent or 0)
  if row.icon then
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", PAD + BOX + 6 + (row.indent or 0), 0)
  end
  local room = math.max(20, cols.name.w - (row.indent or 0))
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", row, "LEFT", left, 0)
  row.name:SetJustifyH(cols.name.justify)
  row.name.fgJustify = cols.name.justify
  if row.mag then
    row.name:SetWidth(math.max(20, room - MAG - 4))
    row.mag:ClearAllPoints()
    row.mag:SetPoint("LEFT", row.name, "RIGHT", 2, 0)
  else
    row.name:SetWidth(room)
  end
  if row.craft then
    row.craft:ClearAllPoints()
    row.craft:SetPoint("TOPLEFT", row.source, "TOPLEFT", -2, 2)
    row.craft:SetPoint("BOTTOMRIGHT", row.source, "BOTTOMRIGHT", 2, -2)
  end
  if row.priceHit then
    row.priceHit:ClearAllPoints()
    row.priceHit:SetPoint("LEFT", row, "LEFT", cols.price.x, 0)
    row.priceHit:SetSize(cols.price.w, ROW_H)
  end
end

local function newCells(row)
  row.name = W.Text(row, { role = "ui" })
  row.source = W.Text(row, { role = "micro", color = "textSecondary" })
  row.price = W.Text(row, { role = "micro", color = "textSecondary" })
  row.total = W.Text(row, { role = "ui" })
  row.prog = W.Text(row, { role = "micro" })
end

local function leastQty(line)
  return PL.MinQty(line, S.Option("stock") and true or false)
end

-- The amount typed into the field: a whole number from the lowest amount of the row (see PL.MinQty) up
-- to 9999 goes to the list, anything else is refused and the field shows the amount again. The field
-- shows what the list holds afterwards (a target near the limit may cut the amount).
local function commitQty(row)
  local line = row.line
  if not line or row.skipCommit or not row.editable then
    return
  end
  local least = leastQty(line)
  local text = U.trim(row.qtyBox.edit:GetText() or "")
  local n = text:match("^%d+$") and tonumber(text)
  local qty = PL.BuyQty(n, least)
  if qty and qty == n then
    local shown = qty ~= line.qty and ns.ProfessionList.SetQty(line, qty) or line.qty
    row.qtyBox.edit:SetText(tostring(shown))
    return
  end
  row.qtyBox.edit:SetText(tostring(line.qty))
  ns.Notify(string.format(L["profshop.qtyInvalid"], least), "warning")
end

-- Confirms a typed amount (leaving the field commits it) before a button of the row acts. Returns the
-- line of the row as it is afterwards.
local function settle(row)
  row.qtyBox.edit:ClearFocus()
  return row.line
end

-- Shared by both list windows -------------------------------------------------------------------

-- The two buttons that switch between the combined and the by reason view. The choice is one account
-- setting (S.Option "view"), so both windows switch together. The caller places and sizes them and
-- calls set.Refresh() when the list repaints.
function SW.ViewButtons(parent)
  local set = {}
  local function make(view)
    return W.Action(parent, {
      key = "shoplist.view." .. view,
      tooltip = "shoplist.view." .. view,
      tooltipText = "shoplist.view." .. view .. "Tip",
      height = 24,
      onClick = function()
        S.SetOption("view", view)
      end,
    })
  end
  set.combined, set.reason = make("combined"), make("reason")
  function set.Refresh()
    local view = S.Option("view")
    set.combined:SetSelected(view == "combined")
    set.reason:SetSelected(view == "reason")
  end
  return set
end

-- Craft it yourself or buy it at the auction house: one choice per item, for every list window.
function SW.ToggleCraft(line)
  if line and line.craftable then
    S.SetCraftChoice(line.id, line.choice == "craft" and "auction" or "craft")
  end
end

function SW.CraftTooltip(owner, line)
  ns.ShowTooltip(
    owner,
    L["shoplist.craft.title"],
    L[line.choice == "craft" and "shoplist.craft.on" or "shoplist.craft.off"]
  )
end

-- The rule above a group of the by reason view. The gap is empty space the row pool leaves above the row
-- (row.fgGap), the rule is drawn in the middle of it; both belong to the rows with item.sep only.
function SW.NewSeparator(row, gap, pad)
  local line = row:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", row, "TOPLEFT", pad, math.floor(gap / 2))
  line:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", -pad, math.floor(gap / 2))
  ns.Bind(line, function(t)
    t:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)
  line:Hide()
  row.sepLine, row.sepGap = line, gap
end

function SW.PaintSeparator(row, item)
  local on = item.sep == true
  row.fgGap = on and row.sepGap or nil
  row.sepLine:SetShown(on)
end

-- The tip of the tick box of a row: a group head with materials ticks them all.
function SW.TickTip(row)
  if row.auto then
    return L["shoplist.rowComplete"]
  end
  local item = row.item
  return L[item and item.head and #(item.members or {}) > 0 and "shoplist.rowGroupTip" or "profshop.rowTip"]
end

-- A tick on a row. A group head also takes its materials along (all of them, the hidden ones too).
function SW.Tick(row)
  if row.line and not row.auto then
    ns.ProfessionList.SetDone(row.line, not row.ticked, row.item and row.item.members)
  end
end

-- The search box over a list: onChange(text) runs when the text changes, by typing, by the clear button or
-- by Escape (which also leaves the box). box.filter is the text now in effect, box.Reset() empties it
-- without calling onChange (for a window that closes).
function SW.SearchBox(parent, onChange)
  local box = W.EditBox(parent, { placeholder = "shoplist.search", clear = true, height = SEARCH_H })
  local edit = box.edit
  box.filter = ""
  local function changed()
    local text = edit:GetText() or ""
    if text ~= box.filter then
      box.filter = text
      onChange(text)
    end
  end
  edit:HookScript("OnTextChanged", ns.Wrap("shoplist-search", changed))
  edit:HookScript("OnEscapePressed", function()
    edit:SetText("")
    changed()
  end)
  function box.Reset()
    box.filter = ""
    edit:SetText("")
    edit:ClearFocus()
  end
  return box
end

-- What a list window shows of the view: all of it, or the rows that match the search text.
function SW.Shown(view, filter)
  return PL.Filter(view, filter)
end

-- The total of the list -----------------------------------------------------------------------------

-- Texts of the total band for a view (S.View or a search copy of it: view.open and view.unpriced are
-- always those of the whole list, so the band and the footer show the same sum): amount ("-" without
-- one), label, long (label with the number of items without a price) and the lines of the tooltip.
function SW.TotalTexts(view)
  local open, unpriced = view.open or 0, view.unpriced or 0
  local label = L["shoplist.total"]
  return {
    open = open,
    unpriced = unpriced,
    label = label,
    long = unpriced > 0 and string.format(L["shoplist.totalUnpriced"], unpriced) or label,
    money = money(open > 0 and open or nil),
    title = L["shoplist.totalTitle"],
    tip = L["shoplist.totalTip"],
    lines = unpriced > 0 and { string.format(L["shoplist.totalUnpricedTip"], unpriced) } or nil,
  }
end

-- One pinned line over the rows of a list window: "Total" at the left, the amount with coin icons at the
-- right, on the band of a section header. A hover and focus target with the tooltip. opts: pad (inset
-- from both edges), right (inset of the amount from the right edge, default pad), role (font role of
-- the amount). bar:Paint(view) fills it; the label drops the number of items without a price when it
-- would not fit next to the amount (the tooltip names it).
function SW.NewTotalBar(parent, opts)
  opts = opts or {}
  local pad = opts.pad or PAD
  local right = opts.right or pad
  local role = opts.role or "ui"
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(ROW_H)
  bar:EnableMouse(true)
  W.Fill(bar, "surface2", 0.9)
  bar.amount = W.Text(bar, { role = role, color = "accent2", justify = "RIGHT" })
  bar.amount:SetPoint("RIGHT", -right, 0)
  bar.label = W.Text(bar, { role = "ui", color = "accent2" })
  bar.label:SetPoint("LEFT", pad, 0)
  bar.label:SetPoint("RIGHT", bar.amount, "LEFT", -GAP, 0)
  bar.label:SetMaxLines(1)

  function bar:Fit()
    local t = self.texts
    if not t then
      return
    end
    self.label:SetText(t.long)
    -- The edges are known once the bar is laid out; before that its size is all there is.
    local left, edge = self:GetLeft(), self:GetRight()
    local width = left and edge and edge - left or self:GetWidth()
    local room = width - pad - right - self.amount:GetWidth() - GAP
    if t.long ~= t.label and room > 0 and self.label:GetStringWidth() > room then
      self.label:SetText(t.label)
    end
  end

  function bar:Paint(view)
    local t = SW.TotalTexts(view)
    self.texts = t
    local size = Theme.fontSize(role)
    self.amount:SetText(t.money)
    self.amount:SetWidth(t.open > 0 and CL.Width(size, t.open) + 2 or math.ceil(size))
    self:Fit()
  end

  local function showTip(self)
    local t = bar.texts
    if t then
      ns.ShowTooltip(self, t.title, t.tip, { lines = t.lines })
    end
  end
  bar:SetScript("OnEnter", showTip)
  bar:SetScript("OnLeave", ns.HideTooltip)
  bar.fgOnFocus, bar.fgOnBlur = showTip, ns.HideTooltip
  ns.Focus.register(bar, showTip)
  bar:HookScript("OnSizeChanged", function()
    bar:Fit()
  end)
  return bar
end

-- Row cells that exist for a position and not for a section header.
local PARTS = { "box", "icon", "mag", "name", "prog", "minus", "plus", "qtyBox", "source", "price", "total", "del" }

local function newRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_H)
  row.hover = row:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(1, 1, 1, 0)
  -- Section header of the by reason view.
  SW.NewSeparator(row, SEP_GAP, PAD)
  row.headBg = W.Fill(row, "surface2", 0.9)
  row.head = W.Text(row, { role = "ui", color = "accent2" })
  row.headTotal = W.Text(row, { role = "ui", color = "accent2", justify = "RIGHT" })
  row.headTotal:SetPoint("RIGHT", row, "RIGHT", -(PAD + COL_DEL), 0)
  row.headTotal:SetWidth(COL_TOTAL + COL_PRICE)
  row.head:SetPoint("LEFT", row, "LEFT", PAD, 0)
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
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", PAD + BOX + 6, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  newCells(row)
  -- A magnifier behind the name: a click on the row searches the item in the auction house.
  row.mag = W.Glyph(row, "search", MAG, "textMuted")
  -- Amount: less, the field, more. Remove sits at the right end.
  row.minus = W.Action(row, { icon = "minus", size = STEP, tooltip = "profshop.qtyDown" })
  row.plus = W.Action(row, { icon = "plus", size = STEP, tooltip = "profshop.qtyUp" })
  row.qtyBox = W.EditBox(row, {
    height = 20,
    inset = FIELD_INSET,
    onEnter = function()
      commitQty(row)
    end,
  })
  row.qtyBox:SetWidth(fieldWidth())
  row.qtyBox.edit:SetMaxLetters(4)
  row.qtyBox.edit:SetJustifyH("CENTER")
  row.qtyBox.edit:SetScript("OnEnter", function(self)
    local note = not row.editable and row.line and L[row.line.derived and "shoplist.rowDerived" or "shoplist.rowMerged"]
    ns.ShowTooltip(self, L["profshop.col.qty"], note or nil)
  end)
  row.qtyBox.edit:SetScript("OnLeave", ns.HideTooltip)
  row.qtyBox.edit:HookScript("OnEditFocusLost", function()
    commitQty(row)
  end)
  row.del = W.Action(row, { icon = "trash", size = 18, tooltip = "profshop.remove" })
  row.minus:SetScript(
    "OnClick",
    ns.Wrap("profshop-less", function()
      local line = settle(row)
      if line and line.qty > leastQty(line) then
        ns.ProfessionList.SetQty(line, line.qty - 1)
      end
    end)
  )
  row.plus:SetScript(
    "OnClick",
    ns.Wrap("profshop-more", function()
      local line = settle(row)
      if line and line.need < PL.MAX_QTY then
        ns.ProfessionList.SetQty(line, line.qty + 1)
      end
    end)
  )
  row.del:SetScript(
    "OnClick",
    ns.Wrap("profshop-remove", function()
      local line = settle(row)
      if line then
        ns.ProfessionList.Remove(line)
      end
    end)
  )
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
    ns.Wrap("profshop-row", function(self, button)
      S.RowClick(self.line, button)
    end)
  )
  row.box:SetScript(
    "OnClick",
    ns.Wrap("profshop-tick", function()
      SW.Tick(row)
    end)
  )
  row.box:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, SW.TickTip(row))
  end)
  row.box:SetScript("OnLeave", ns.HideTooltip)
  -- Craft yourself or buy at the auction house, over the cell of the source.
  row.craft = CreateFrame("Button", nil, row)
  row.craft.hl = row.craft:CreateTexture(nil, "BACKGROUND")
  row.craft.hl:SetAllPoints()
  row.craft.hl:SetColorTexture(1, 1, 1, 0)
  W.Border(row.craft, "accent2", 0.5)
  row.craft:SetScript(
    "OnClick",
    ns.Wrap("profshop-craft", function()
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
  ns.Focus.register(row, function(self)
    self:Click()
  end)
  row.fgOnFocus = function(self)
    if self.line then
      S.RowTooltip(self, self.line)
    end
  end
  row.fgOnBlur = ns.HideTooltip
  ns.Focus.register(row.box, function(self)
    self:Click()
  end)
  ns.Focus.register(row.craft, function(self)
    self:Click()
  end)
  -- The price cell tells where the price comes from; a click on it acts like a click on the row.
  row.priceHit = CreateFrame("Button", nil, row)
  row.priceHit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.priceHit:SetScript("OnEnter", function(self)
    row.hover:SetColorTexture(1, 1, 1, 0.1)
    if row.line then
      S.PriceTooltip(self, row.line)
    end
  end)
  row.priceHit:SetScript("OnLeave", function()
    row.hover:SetColorTexture(1, 1, 1, 0)
    ns.HideTooltip()
  end)
  row.priceHit:SetScript(
    "OnClick",
    ns.Wrap("profshop-row", function(_, button)
      S.RowClick(row.line, button)
    end)
  )
  ns.Focus.register(row.priceHit, function()
    row:Click()
  end)
  row.priceHit.fgOnFocus = function(self)
    if row.line then
      S.PriceTooltip(self, row.line)
    end
  end
  row.priceHit.fgOnBlur = ns.HideTooltip
  row.craft.fgOnFocus = function(self)
    if row.line then
      SW.CraftTooltip(self, row.line)
    end
  end
  row.craft.fgOnBlur = ns.HideTooltip
  function row:fgLayout(width)
    layoutCells(self, width)
    return ROW_H
  end
  return row
end

local function paintHeader(row, item)
  row.line, row.item, row.ticked, row.auto, row.editable, row.indent = nil, item, false, false, false, 0
  SW.PaintSeparator(row, item)
  for _, key in ipairs(PARTS) do
    row[key]:Hide()
  end
  row.craft:Hide()
  row.priceHit:Hide()
  row.headBg:Show()
  row.head:Show()
  row.headTotal:Show()
  row:SetEnabled(false)
  row.head:SetText(string.format("%s  (%d/%d)", item.label, item.ticked, item.count))
  row.headTotal:SetText(money(item.open > 0 and item.open or nil))
end

local function paintRow(row, item)
  if item.kind == "header" then
    paintHeader(row, item)
    return
  end
  -- The item of a single position heads its materials: same cells, on the band of a section header.
  SW.PaintSeparator(row, item)
  row.headBg:SetShown(item.head == true)
  row.head:Hide()
  row.headTotal:Hide()
  for _, key in ipairs(PARTS) do
    row[key]:Show()
  end
  row:SetEnabled(true)
  local line, ticked = item.line, item.ticked
  local previous = row.line
  row.line, row.item, row.slug, row.ticked, row.auto = line, item, item.slug, ticked, item.auto
  row.editable, row.indent = item.editable, item.depth * INDENT
  row.icon:SetTexture(ns.ProfessionList.Icon(line))
  row.icon:SetDesaturated(ticked)
  row.icon:SetAlpha(ticked and 0.5 or 1)
  row.mark:SetShown(ticked)
  row.boxOn:SetShown(ticked)
  row.boxBorder.set(ticked and "actionHi" or "white", ticked and 1 or 0.4)
  local color = ticked and "textMuted" or "text"
  -- A ticked line is done and stays muted, an open one shows the quality color of its item.
  row.name:SetText(S.RowLabel(item))
  W.SetColor(row.name, color)
  local progress, progressColor = S.Progress(item)
  row.prog:SetText(progress)
  W.SetColor(row.prog, progressColor)
  -- A repaint while the field is being typed in must not eat the input; a pooled row that now shows
  -- another position gives the focus up without committing.
  local field = row.qtyBox.edit
  if field:HasFocus() and previous and previous.id ~= line.id then
    row.skipCommit = true
    field:ClearFocus()
    row.skipCommit = false
  end
  if not field:HasFocus() then
    field:SetText(tostring(line.qty))
  end
  field:SetEnabled(item.editable)
  field:SetTextColor(Theme.color(item.editable and "text" or "textMuted"))
  row.minus:SetEnabled(item.editable and line.qty > leastQty(line))
  row.plus:SetEnabled(item.editable and line.need < PL.MAX_QTY)
  row.del:SetEnabled(item.removable)
  row.source:SetText(L["profshop.group." .. line.source])
  W.SetColor(row.source, item.craftable and "accent2" or "textSecondary")
  row.craft:SetShown(item.craftable)
  -- Prices of the auction house carry a marker when they are old or come from the price add-on.
  local priceInfo = line.price and line.source == "auction" and S.PriceInfo(line.id) or nil
  row.price:SetText(money(line.price) .. S.PriceMark(priceInfo))
  W.SetColor(row.price, priceInfo and S.PriceMark(priceInfo) ~= "" and "textMuted" or "textSecondary")
  row.priceHit:SetShown(priceInfo ~= nil)
  -- A crafted head has no price of its own, it shows what its open materials cost.
  row.total:SetText(money(line.total or (item.head and item.open > 0 and item.open or nil)))
  W.SetColor(row.total, color)
end

-- The header: one short text per column over the same spans as the cells of the rows. Every column is a
-- hover and focus target with the full name and a line of explanation (label is the short text of the
-- header, title the full name).
local HEADER = {
  { cell = "name", label = "profshop.col.item", title = "profshop.col.item", tip = "shoplist.col.itemTip" },
  {
    cell = "prog",
    label = "shoplist.col.progressShort",
    title = "shoplist.col.progress",
    tip = "shoplist.col.progressTip",
  },
  { cell = "qty", label = "profshop.col.qty", title = "profshop.col.qty", tip = "shoplist.col.qtyTip" },
  {
    cell = "source",
    label = "shoplist.col.sourceShort",
    title = "profshop.col.source",
    tip = "shoplist.col.sourceTip",
  },
  { cell = "price", label = "profshop.col.price", title = "profshop.col.price", tip = "shoplist.col.priceTip" },
  { cell = "total", label = "profshop.col.total", title = "profshop.col.total", tip = "shoplist.col.totalTip" },
}
SW.HEADER = HEADER

local function showHeaderTip(owner, spec)
  ns.ShowTooltip(owner, L[spec.title], L[spec.tip])
end

local function newHeader(parent)
  local head = CreateFrame("Frame", nil, parent)
  head:SetHeight(ROW_H)
  head.hit = {}
  for _, spec in ipairs(HEADER) do
    local text = W.Text(head, { key = spec.label, role = "micro", color = "accent2", justify = JUSTIFY[spec.cell] })
    head[spec.cell] = text
    local hit = CreateFrame("Button", nil, head)
    hit.hl = hit:CreateTexture(nil, "BACKGROUND")
    hit.hl:SetAllPoints()
    hit.hl:SetColorTexture(1, 1, 1, 0)
    hit:SetScript("OnEnter", function(self)
      self.hl:SetColorTexture(1, 1, 1, 0.1)
      showHeaderTip(self, spec)
    end)
    hit:SetScript("OnLeave", function(self)
      self.hl:SetColorTexture(1, 1, 1, 0)
      ns.HideTooltip()
    end)
    ns.Focus.register(hit, function() end)
    hit.fgOnFocus = function(self)
      showHeaderTip(self, spec)
    end
    hit.fgOnBlur = ns.HideTooltip
    head.hit[spec.cell] = hit
  end
  local function relayout(width)
    head.width = width
    layoutCells(head, width)
    local cols = SW.Columns(width)
    for cell, hit in pairs(head.hit) do
      local c = cols[cell]
      hit:ClearAllPoints()
      hit:SetPoint("TOPLEFT", head, "TOPLEFT", c.x, 0)
      hit:SetSize(c.w, ROW_H)
    end
  end
  head.relayout = function()
    relayout(head.width)
  end
  head:SetScript("OnSizeChanged", function(_, width)
    relayout(width)
  end)
  relayout(MIN_W - 2 * PAD - LIST_INSET - LIST_RESERVE)
  return head
end

-- Window ---------------------------------------------------------------------------------------

local function refresh(f)
  local whole = S.View()
  local plan = whole.plan
  -- The search only picks what is shown: counters and sums stay those of the whole list.
  local view = SW.Shown(whole, f.search.filter)
  f.plan, f.data = plan, view
  -- The amount columns follow the rows shown; a window narrower than they need grows.
  measureMoney(view.rows)
  setBounds(f)
  if f:GetWidth() < SW.MinWidth() then
    f:SetWidth(SW.MinWidth())
  end
  f.header.relayout()
  f.empty:SetShown(false)
  local offered = f.banner:Update(not plan.data and plan.status == ns.ProfessionRouteData.STATUS.missing)
  f.restore:SetShown(ns.ProfessionList.EditCount(plan.slug) > 0)
  local craftable = false
  for _, line in ipairs(plan.all or {}) do
    craftable = craftable or line.craftable == true
  end
  f.craftAll:SetShown(craftable)
  f.auctionAll:SetShown(craftable)
  f.split(nil, f.content:GetWidth())
  f.views.Refresh()
  f.cbAuto.Refresh()
  if not plan.data and not plan.lines then
    f.summary:SetText(offered and "" or ns.ProfessionRouteData.Hint(plan.status))
    f.pool:Sync({}, paintRow)
    f.footer:SetText("")
    f.total:Hide()
    f.view:Layout()
    f.cbStock.Refresh()
    f.cbAll.Refresh()
    f.cbSurcharge.Refresh()
    return
  end
  if plan.data then
    f.summary:SetText(string.format(L["profshop.summary"], plan.name, plan.from, plan.to, S.Option("surcharge")))
  else
    f.summary:SetText(offered and "" or ns.ProfessionRouteData.Hint(plan.status))
  end
  f.pool:Sync(view.rows, paintRow)
  f.total:SetShown(whole.count > 0)
  f.total:Paint(whole)
  local nothing, noMatch = whole.count == 0, whole.count > 0 and view.filtered and #view.rows == 0
  W.SetText(f.empty, nothing and "profshop.empty" or "shoplist.noMatches")
  f.empty:SetShown(nothing or noMatch == true)
  local open = money(view.open > 0 and view.open or nil)
  local footer = view.unpriced > 0 and string.format(L["profshop.footerUnpriced"], open, view.unpriced)
    or string.format(L["profshop.footer"], open)
  f.footer:SetText(
    footer
      .. (view.count > 0 and ("  ·  " .. string.format(L["profshop.ticked"], view.ticked, view.count)) or "")
      .. (view.filtered and ("  ·  " .. string.format(L["shoplist.hits"], view.matches)) or "")
  )
  f.cbStock.Refresh()
  f.cbAll.Refresh()
  f.cbSurcharge.Refresh()
  f.view:Layout()
end

-- Copy texts: the import line first, a button switches to the plain list and back.
local function showCopy(plain, given)
  local plan = given or frame and frame.plan or S.Plan()
  if #(plan.lines or {}) == 0 then
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
  if not plan.data and not plan.lines then
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

-- "Senden": the list as one link in the chat (ProfessionListLink.lua). The copy texts stay what they
-- were, the link only carries the positions.
function SW.Link(given)
  local plan = given or frame and frame.plan or S.Plan()
  if #(plan.lines or {}) == 0 then
    ns.Notify(plan.data and L["profshop.copy.none"] or ns.ProfessionRouteData.Hint(plan.status), "info")
    return nil
  end
  return ns.ProfessionListLink.Share(plan)
end

-- Cleaning up: the done positions go at once, emptying everything asks first.
function SW.RemoveDone(given)
  return ns.ProfessionList.RemoveDone(given or frame and frame.plan or S.Plan())
end

function SW.ClearAll(given)
  ns.Dialogs.Confirm("profshop.clearAll", "profshop.clearAllText", function()
    ns.ProfessionList.Clear(given or S.Plan())
  end)
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

  f.link = W.Action(content, {
    label = "act.send",
    icon = "share",
    tooltip = "profshop.link",
    tooltipText = "profshop.linkTip",
    variant = "primary",
    onClick = function()
      SW.Link()
    end,
  })
  f.send = W.Action(content, {
    label = "profshop.btn.auction",
    icon = "export",
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
      ns.ProfessionList.ClearTicks(S.Slug())
    end,
  })
  f.removeDone = W.Action(content, {
    label = "profshop.btn.removeDone",
    icon = "check",
    tooltip = "profshop.removeDone",
    tooltipText = "profshop.removeDoneTip",
    onClick = function()
      SW.RemoveDone()
    end,
  })
  f.clearAll = W.Action(content, {
    label = "profshop.btn.clearAll",
    icon = "trash",
    tooltip = "profshop.clearAll",
    variant = "danger",
    onClick = function()
      SW.ClearAll()
    end,
  })
  f.restore = W.Action(content, {
    label = "profshop.btn.restore",
    icon = "undo",
    tooltip = "profshop.restore",
    tooltipText = "profshop.restoreTip",
    onClick = function()
      ns.ProfessionList.ResetEdits(S.Slug())
    end,
  })
  f.restore:Hide()
  -- The view (combined or by reason, one choice for every list window) and the craft shortcuts.
  f.views = SW.ViewButtons(content)
  f.craftAll = W.Action(content, {
    key = "shoplist.craftAll",
    tooltip = "shoplist.craftAll",
    tooltipText = "shoplist.craftAllTip",
    height = 24,
    onClick = function()
      S.SetCraftAll("craft")
    end,
  })
  f.auctionAll = W.Action(content, {
    key = "shoplist.auctionAll",
    tooltip = "shoplist.auctionAll",
    tooltipText = "shoplist.auctionAllTip",
    height = 24,
    onClick = function()
      S.SetCraftAll("auction")
    end,
  })
  f.cbAuto = W.Checkbox(content, {
    key = "shoplist.autoOpen",
    tooltip = "shoplist.autoOpen",
    tooltipText = "shoplist.autoOpenTip",
    get = function()
      return S.Option("autoOpen")
    end,
    set = function(v)
      S.SetOption("autoOpen", v)
    end,
  })
  f.hint = W.Text(content, { key = "profshop.hint", role = "micro", color = "textSecondary", wrap = true })
  -- Next to the auction house switch, so the list keeps its height. View only, not saved, gone with the window.
  f.search = SW.SearchBox(content, function()
    refresh(f)
  end)
  f.link:SetPoint("TOPLEFT", f.cbStock, "BOTTOMLEFT", 0, -8)
  f.send:SetPoint("LEFT", f.link, "RIGHT", 6, 0)
  f.copy:SetPoint("LEFT", f.send, "RIGHT", 6, 0)
  f.clear:SetPoint("LEFT", f.copy, "RIGHT", 6, 0)
  f.removeDone:SetPoint("TOPLEFT", f.link, "BOTTOMLEFT", 0, -6)
  f.clearAll:SetPoint("LEFT", f.removeDone, "RIGHT", 6, 0)
  f.restore:SetPoint("LEFT", f.clearAll, "RIGHT", 6, 0)
  f.views.combined:SetPoint("TOPLEFT", f.removeDone, "BOTTOMLEFT", 0, -6)
  f.views.reason:SetPoint("LEFT", f.views.combined, "RIGHT", 6, 0)
  f.craftAll:SetPoint("LEFT", f.views.reason, "RIGHT", 6, 0)
  f.auctionAll:SetPoint("LEFT", f.craftAll, "RIGHT", 6, 0)
  f.cbAuto:SetPoint("TOPLEFT", f.views.combined, "BOTTOMLEFT", 0, -6)
  f.search:SetPoint("TOPLEFT", f.cbAuto, "TOPRIGHT", 8, 0)
  f.hint:SetPoint("TOPLEFT", f.cbAuto, "BOTTOMLEFT", 0, -4)
  f.hint:SetPoint("RIGHT", 0, 0)

  f.header = newHeader(content)
  f.header:SetPoint("TOPLEFT", f.hint, "BOTTOMLEFT", LIST_INSET, -8)
  f.header:SetPoint("RIGHT", content, "RIGHT", -LIST_RESERVE, 0)
  -- The total of the whole list stays in view while the rows scroll; the amount sits over the total column.
  f.total = SW.NewTotalBar(content, { pad = PAD, right = PAD + COL_DEL })
  f.total:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -2)
  f.total:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 0, -2)

  f.footer = W.Text(content, { role = "ui", color = "accent2", justify = "LEFT", wrap = true })
  f.footer:SetPoint("BOTTOMLEFT", 0, 0)
  f.footer:SetPoint("BOTTOMRIGHT", 0, 0)

  local host = CreateFrame("Frame", nil, content)
  host:SetPoint("TOPLEFT", f.total, "BOTTOMLEFT", -LIST_INSET, -2)
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

  -- Every row of buttons and the switches share the width equally; the restore button is only there
  -- while a route line is removed or changed.
  local function split(_, w)
    local function share(buttons)
      local shown = {}
      for _, b in ipairs(buttons) do
        if b:IsShown() then
          shown[#shown + 1] = b
        end
      end
      local each = math.floor((w - 6 * (#shown - 1)) / #shown)
      for _, b in ipairs(shown) do
        b:SetWidth(each)
      end
    end
    share({ f.link, f.send, f.copy, f.clear })
    share({ f.removeDone, f.clearAll, f.restore })
    share({ f.views.combined, f.views.reason, f.craftAll, f.auctionAll })
    f.cbAuto:SetWidth(math.floor(w / 2))
    f.search:SetWidth(w - math.floor(w / 2) - 8)
    local sw = math.floor((w - 16) / 3)
    for _, c in ipairs({ f.cbStock, f.cbAll, f.cbSurcharge }) do
      c:SetWidth(sw)
    end
  end
  content:SetScript("OnSizeChanged", split)
  split(nil, MIN_W - 2 * PAD)
  f.split = split

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
      f.search.Reset()
    end)
  )
  -- A change of the font size moves the digit width of the amount field and so the columns.
  ns.Bind(f, function()
    if f.header then
      f.header.relayout()
    end
    if frame == f and f:IsShown() then
      refresh(f)
    end
  end)
  f:Hide()
  return f
end

SW.MIN_W, SW.MIN_H = MIN_W, MIN_H

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
