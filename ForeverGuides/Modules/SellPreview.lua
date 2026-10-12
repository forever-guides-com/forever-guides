-- Preview window of the sell helper: every item the rules selected with icon, name, reason and
-- price, a check mark per item to leave it out, and "Sell" with a confirmation. Nothing is sold
-- before that confirmation (Modules/SellHelper.lua does the selling).
local _, ns = ...
local W = ns.W
local Logic, Helper = ns.SellLogic, ns.SellHelper

local P = {}
ns.SellPreview = P

ns.AddLocale("enUS", {
  ["sell.title"] = "Sell junk",
  ["sell.summary"] = "%d of %d items: %s",
  ["sell.kept"] = "Kept by protection: %d",
  ["sell.sell"] = "Sell",
  ["sell.confirmText"] = "Sell the checked items now?",
  ["sell.confirmMany"] = "Sell the checked items now?\nBuyback keeps only the last 12.",
  ["sell.empty"] = "Nothing to sell",
})
ns.AddLocale("deDE", {
  ["sell.title"] = "Plunder verkaufen",
  ["sell.summary"] = "%d von %d Items: %s",
  ["sell.kept"] = "Durch Schutz behalten: %d",
  ["sell.sell"] = "Verkaufen",
  ["sell.confirmText"] = "Markierte Items jetzt verkaufen?",
  ["sell.confirmMany"] = "Markierte Items jetzt verkaufen?\nRückkauf fasst nur die letzten 12.",
  ["sell.empty"] = "Nichts zu verkaufen",
})

local ROW = 26
local WIDTH, HEIGHT = 560, 440

local dialog
-- Rows that are switched off, by bag:slot.
P.off = {}

local function chosen()
  return Logic.Choose(dialog.entries, P.off)
end

local function paintSummary()
  local list = chosen()
  W.SetText(
    dialog.summary,
    nil,
    #dialog.entries == 0 and ns.L["sell.empty"]
      or string.format(ns.L["sell.summary"], #list, #dialog.entries, Logic.Money(Logic.Total(list)))
  )
  dialog.warn:SetShown(Logic.OverBuyback(list))
  dialog.sell:SetEnabled(#list > 0)
end

local function makeRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(ROW)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 28, 0)
  row.name = W.Text(row, { role = "ui" })
  row.name:SetPoint("LEFT", 56, 0)
  row.name:SetWidth(220)
  row.reason = W.Text(row, { role = "micro", color = "textSecondary" })
  row.reason:SetPoint("LEFT", 284, 0)
  row.reason:SetWidth(90)
  row.price = W.Text(row, { role = "ui", justify = "RIGHT" })
  row.price:SetPoint("RIGHT", -10, 0)
  row.price:SetWidth(130)
  -- The check box covers the whole row, so a click anywhere on it switches the row.
  row.check = W.Checkbox(row, {
    text = "",
    get = function()
      return row.entry ~= nil and not P.off[Logic.Key(row.entry)]
    end,
    set = function(on)
      P.off[Logic.Key(row.entry)] = (not on) or nil
      paintSummary()
    end,
  })
  row.check:SetAllPoints(row)
  row.check:HookScript("OnEnter", function(self)
    if row.entry and row.entry.link then
      ns.ShowTooltip(self, row.entry.name or "", nil, { link = row.entry.link })
    end
  end)
  row.check:HookScript("OnLeave", ns.HideTooltip)
  return row
end

local function build()
  dialog = ns.Dialogs.Create("ForeverGuidesSellDialog", WIDTH, HEIGHT)
  W.SetText(dialog.title, "sell.title")
  dialog.summary = W.Text(dialog, { role = "ui", color = "textSecondary" })
  dialog.summary:SetPoint("TOPLEFT", 16, -48)
  dialog.summary:SetPoint("RIGHT", -16, 0)
  dialog.warn = W.Text(dialog, { key = "sell.warn12", role = "micro", color = "warning" })
  dialog.warn:SetPoint("TOPLEFT", 16, -66)
  dialog.warn:SetPoint("RIGHT", -16, 0)
  dialog.kept = W.Text(dialog, { role = "micro", color = "textMuted" })
  dialog.kept:SetPoint("BOTTOMLEFT", 16, 24)
  dialog.area = W.ScrollArea(dialog)
  dialog.area:SetPoint("TOPLEFT", 16, -88)
  dialog.area:SetPoint("BOTTOMRIGHT", -16, 56)
  W.Fill(dialog.area, "surface", 1)
  dialog.rows = {}
  dialog.entries = {}
  dialog.sell = W.Button(dialog, {
    key = "sell.sell",
    variant = "primary",
    width = 120,
    onClick = function()
      local list = chosen()
      if #list == 0 then
        return
      end
      local text = Logic.OverBuyback(list) and "sell.confirmMany" or "sell.confirmText"
      ns.Dialogs.Confirm("sell.title", text, function()
        dialog:Hide()
        Helper.Sell(list)
      end)
    end,
  })
  dialog.sell:SetPoint("BOTTOMRIGHT", -16, 14)
  dialog.cancel = W.Action(dialog, {
    label = "act.cancel",
    icon = "close",
    tooltip = "common.cancel",
    width = 110,
    onClick = function()
      dialog:Hide()
    end,
  })
  dialog.cancel:SetPoint("RIGHT", dialog.sell, "LEFT", -8, 0)
end

local function fill(result)
  P.off = {}
  dialog.entries = result.list
  for i, entry in ipairs(result.list) do
    local row = dialog.rows[i]
    if not row then
      row = makeRow(dialog.area.content)
      dialog.rows[i] = row
    end
    row.entry = entry
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", dialog.area.content, "TOPLEFT", 0, -(i - 1) * ROW)
    row:SetPoint("TOPRIGHT", dialog.area.content, "TOPRIGHT", 0, -(i - 1) * ROW)
    row.icon:SetTexture(entry.icon)
    local r, g, b = ns.ItemInfo.qualityTextColor(entry.quality)
    if not r then
      r, g, b = ns.Theme.rgb("text")
    end
    row.name:SetText((entry.count > 1 and (entry.count .. "x ") or "") .. (entry.name or ("#" .. entry.itemID)))
    row.name:SetTextColor(r, g, b)
    row.reason:SetText(Logic.ReasonText(entry))
    row.price:SetText(Logic.Money(entry.price))
    row.check:Refresh()
    row:Show()
  end
  for i = #result.list + 1, #dialog.rows do
    dialog.rows[i].entry = nil
    dialog.rows[i]:Hide()
  end
  dialog.area:SetContentHeight(#result.list * ROW)
  local kept = Logic.KeptCount(result.kept)
  W.SetText(dialog.kept, nil, kept > 0 and string.format(ns.L["sell.kept"], kept) or "")
  paintSummary()
end

-- Opens the preview for what the rules select right now. False without a merchant or without items.
function P.Open()
  if not Helper.state.open then
    return false
  end
  local result = Helper.Evaluate()
  if not (result and #result.list > 0) then
    return false
  end
  if not dialog then
    build()
  end
  fill(result)
  dialog:Show()
  return true
end

function P.Close()
  if dialog and dialog:IsShown() then
    dialog:Hide()
  end
end
