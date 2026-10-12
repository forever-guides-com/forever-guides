-- Side panel of the calculator (Modules/CalcView.lua): the tabs "History" and "Memory" with the
-- saved calculations and the memory entries. It only shows what ns.CalcView keeps in ns.db.calc and
-- hands clicks back to the view.
local _, ns = ...
local W, L, Theme, FL = ns.W, ns.L, ns.Theme, ns.FlowLayout

local S = {}
ns.CalcSide = S

local TAB_H, FOOT_GAP = 28, 6
local HISTORY_ROW_H, MEMORY_ROW_H, ROW_GAP = 44, 50, 2
local SCROLL_INSET = 12

local function scaledHeight(base)
  return Theme.lineHeight(base)
end

-- Rows ------------------------------------------------------------------------------------------------

-- One saved calculation: the expression small on top, the result large below. A click loads the
-- result into the input, a right click or the small button takes the expression.
local function newHistoryRow(list, view)
  local row = CreateFrame("Frame", nil, list)
  local main = CreateFrame("Button", nil, row)
  main:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- Next to the take button, not under it: two buttons must not overlap.
  main:SetPoint("TOPLEFT", row, "TOPLEFT", 24, 0)
  main:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  local hover = main:CreateTexture(nil, "BACKGROUND")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0)
  row.result = W.Text(main, { role = "h3", color = "text", justify = "RIGHT" })
  row.result:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -6, 4)
  row.result:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 6, 4)
  row.expr = W.Text(main, { role = "micro", color = "textMuted", justify = "RIGHT" })
  row.expr:SetPoint("TOPRIGHT", main, "TOPRIGHT", -6, -4)
  row.expr:SetPoint("TOPLEFT", main, "TOPLEFT", 6, -4)
  main:SetScript("OnEnter", function(self)
    hover:SetColorTexture(1, 1, 1, 0.08)
    ns.ShowTooltip(self, L["calcui.history"], L["calcui.history.rowTip"])
  end)
  main:SetScript("OnLeave", function()
    hover:SetColorTexture(1, 1, 1, 0)
    ns.HideTooltip()
  end)
  main:SetScript(
    "OnClick",
    ns.Wrap("calc-history-row", function(_, button)
      if not row.entry then
        return
      end
      if button == "RightButton" then
        view:SetInput(row.entry.expr)
      else
        view:SetInput(ns.CalcView.EntryInput(row.entry.result))
      end
    end)
  )
  ns.Focus.register(main, function(self)
    self:Click()
  end)
  row.take = W.Action(row, {
    icon = "chevron-left",
    size = 20,
    tooltip = "calcui.history.take",
    tooltipText = "calcui.history.takeTip",
    onClick = function()
      if row.entry then
        view:SetInput(row.entry.expr)
      end
    end,
  })
  row.take:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
  row.main = main
  return row
end

-- One memory entry: the value (a click inserts it) and its MC, M+ and M- keys.
local function newMemoryRow(list, view)
  local row = CreateFrame("Frame", nil, list)
  local main = CreateFrame("Button", nil, row)
  main:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  main:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
  local hover = main:CreateTexture(nil, "BACKGROUND")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0)
  row.value = W.Text(main, { role = "h3", color = "text", justify = "RIGHT" })
  row.value:SetPoint("RIGHT", main, "RIGHT", -6, 0)
  row.value:SetPoint("LEFT", main, "LEFT", 6, 0)
  main:SetScript("OnEnter", function(self)
    hover:SetColorTexture(1, 1, 1, 0.08)
    ns.ShowTooltip(self, L["calcui.memory"], L["calcui.memory.rowTip"])
  end)
  main:SetScript("OnLeave", function()
    hover:SetColorTexture(1, 1, 1, 0)
    ns.HideTooltip()
  end)
  main:SetScript(
    "OnClick",
    ns.Wrap("calc-memory-row", function()
      if row.index then
        view:Insert(ns.CalcView.MemoryText(row.index))
      end
    end)
  )
  ns.Focus.register(main, function(self)
    self:Click()
  end)
  local function key(id, text, tip, tipText, onClick)
    local b = W.Button(row, {
      text = text,
      variant = "ghost",
      width = 40,
      height = 20,
      tooltip = tip,
      tooltipText = tipText,
      onClick = function()
        if row.index then
          onClick(row.index)
        end
      end,
    })
    row[id] = b
    return b
  end
  key("clear", "MC", "calcui.key.mc", "calcui.memory.rowClearTip", function(i)
    ns.CalcView.MemoryRemove(i)
  end)
  key("plus", "M+", "calcui.key.mplus", "calcui.memory.rowPlusTip", function(i)
    view:MemoryAddCurrent(1, i)
  end)
  key("minus", "M-", "calcui.key.mminus", "calcui.memory.rowMinusTip", function(i)
    view:MemoryAddCurrent(-1, i)
  end)
  row.main = main
  return row
end

-- Lists ---------------------------------------------------------------------------------------------

-- A column of rows below each other; make(list, view) builds one row, fill(row, item, index) shows an item.
local function newList(parent, view, make, fill, rowHeight)
  local list = CreateFrame("Frame", nil, parent)
  list.rows, list.items = {}, {}

  function list:SetData(items)
    list.items = items
    for i, item in ipairs(items) do
      local row = list.rows[i]
      if not row then
        row = make(list, view)
        list.rows[i] = row
      end
      fill(row, item, i)
      row:Show()
    end
    for i = #items + 1, #list.rows do
      list.rows[i].entry, list.rows[i].index = nil, nil
      list.rows[i]:Hide()
    end
  end

  function list:fgGridLayout(width)
    local h = scaledHeight(rowHeight)
    for i = 1, #list.items do
      local row = list.rows[i]
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * (h + ROW_GAP))
      row:SetSize(width, h)
      -- The memory keys sit in the lower half of their row.
      if row.clear then
        local half = math.floor(h / 2)
        row.main:SetHeight(half)
        row.minus:ClearAllPoints()
        row.minus:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
        row.plus:ClearAllPoints()
        row.plus:SetPoint("RIGHT", row.minus, "LEFT", -2, 0)
        row.clear:ClearAllPoints()
        row.clear:SetPoint("RIGHT", row.plus, "LEFT", -2, 0)
      end
    end
    local total = math.max(1, #list.items * (h + ROW_GAP) - ROW_GAP)
    list:SetHeight(total)
    return total
  end
  return list
end

-- Panel -------------------------------------------------------------------------------------------------

-- Builds the panel into parent. Returns the frame with:
--   side.tabs, side.list (history rows), side.historyEmpty, side.historyButtons,
--   side.memoryList, side.memoryEmpty, side.memoryButtons,
--   side:Arrange(width, height), side:Refresh(), side:SelectTab(id).
function S.build(parent, view)
  local V = ns.CalcView
  local side = CreateFrame("Frame", nil, parent)
  W.Fill(side, "surface", 0.55)
  W.Border(side, "white", 0.12)

  side.tabs = W.Tabs(side, {
    tabs = { { id = "history", key = "calcui.history" }, { id = "memory", key = "calcui.memory" } },
    onSelect = function(id)
      V.Data().sideTab = id
      side:ShowTab(id)
    end,
  })
  side.tabs:SetPoint("TOPLEFT", side, "TOPLEFT", 4, -2)
  side.tabs:SetPoint("TOPRIGHT", side, "TOPRIGHT", -4, -2)

  -- History tab
  side.historyArea = W.ScrollArea(side)
  side.list = newList(side.historyArea.content, view, newHistoryRow, function(row, entry)
    row.entry = entry
    row.expr:SetText(entry.expr)
    row.result:SetText(V.HistoryResult(entry.result))
  end, HISTORY_ROW_H)
  side.list:SetPoint("TOPLEFT", side.historyArea.content, "TOPLEFT", 0, 0)
  side.historyEmpty = W.Text(side.historyArea.content, {
    key = "calcui.history.empty",
    role = "ui",
    color = "textMuted",
    wrap = true,
  })
  side.historyEmpty:SetPoint("TOPLEFT", side.historyArea.content, "TOPLEFT", 6, -6)
  side.historyButtons = FL.ButtonRow(side, {
    {
      id = "clear",
      label = "act.clear",
      icon = "trash",
      tooltip = "calcui.history.clear",
      onClick = function()
        view:ConfirmClear()
      end,
    },
  })

  -- Memory tab
  side.memoryArea = W.ScrollArea(side)
  side.memoryList = newList(side.memoryArea.content, view, newMemoryRow, function(row, text, index)
    row.index = index
    local dec = ns.CalcDecimal.fromString(text)
    row.value:SetText(dec and V.Format(dec, V.Data().group) or text)
  end, MEMORY_ROW_H)
  side.memoryList:SetPoint("TOPLEFT", side.memoryArea.content, "TOPLEFT", 0, 0)
  side.memoryEmpty = W.Text(side.memoryArea.content, {
    key = "calcui.memory.empty",
    role = "ui",
    color = "textMuted",
    wrap = true,
  })
  side.memoryEmpty:SetPoint("TOPLEFT", side.memoryArea.content, "TOPLEFT", 6, -6)
  side.memoryButtons = FL.ButtonRow(side, {
    {
      id = "clear",
      label = "act.clear",
      icon = "trash",
      tooltip = "calcui.memory.clear",
      onClick = function()
        V.MemoryClear()
      end,
    },
  })

  function side:ShowTab(id)
    local history = id ~= "memory"
    side.historyArea:SetShown(history)
    side.historyButtons:SetShown(history)
    side.memoryArea:SetShown(not history)
    side.memoryButtons:SetShown(not history)
    side:Arrange()
  end

  -- Places the panes for the size; without arguments it repeats the last one.
  function side:Arrange(width, height)
    width, height = width or side.width, height or side.height
    if not width or not height or width < 40 or height < 60 then
      return
    end
    side.width, side.height = width, height
    side:SetSize(width, height)
    local innerW = width - 8
    local foot = side.historyButtons:SetWidthAvailable(innerW)
    side.memoryButtons:SetWidthAvailable(innerW)
    local top = TAB_H + 4
    local areaH = math.max(1, height - top - foot - FOOT_GAP - 4)
    for _, pair in ipairs({
      { side.historyArea, side.historyButtons, side.list, side.historyEmpty },
      { side.memoryArea, side.memoryButtons, side.memoryList, side.memoryEmpty },
    }) do
      local area, buttons, list, empty = pair[1], pair[2], pair[3], pair[4]
      area:ClearAllPoints()
      area:SetPoint("TOPLEFT", side, "TOPLEFT", 4, -top)
      area:SetSize(innerW, areaH)
      buttons:ClearAllPoints()
      buttons:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 4, 4)
      buttons:SetWidth(innerW)
      local cw = math.max(1, innerW - SCROLL_INSET)
      area.content:SetWidth(cw)
      empty:SetWidth(math.max(1, cw - 12))
      local h = list:fgGridLayout(cw)
      list:SetWidth(cw)
      if empty:IsShown() then
        h = math.max(h, math.ceil(empty:GetStringHeight()) + 12)
      end
      area:SetContentHeight(h)
    end
  end

  function side:Refresh()
    local store = V.Data()
    side.list:SetData(store.history)
    side.historyEmpty:SetShown(#store.history == 0)
    side.historyButtons:SetItemEnabled("clear", #store.history > 0)
    side.memoryList:SetData(store.memory)
    side.memoryEmpty:SetShown(#store.memory == 0)
    side.memoryButtons:SetItemEnabled("clear", #store.memory > 0)
    side:Arrange()
  end

  side:ShowTab(V.Data().sideTab)
  side.tabs:Select(V.Data().sideTab)
  return side
end
