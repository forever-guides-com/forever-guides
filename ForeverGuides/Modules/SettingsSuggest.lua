-- The list of suggestions under the search field in the title bar: while the player types, the menu pages, the
-- tabs and the single settings that fit are offered (at most eight), then one row "Search" that opens the page of
-- results. A click on a hit goes straight to its place. The keyboard stays in the field: Up and Down move through
-- the rows, Enter opens the chosen row (without one it searches), Esc closes the list. Every row has a tooltip with
-- the full name, the place and the explanation. Hits and ranking: Modules/SettingsSearchLogic.lua.
local _, ns = ...
local W, Theme = ns.W, ns.Theme
local SL, SS = ns.SettingsSearchLogic, ns.SettingsSearch

local SG = {}
ns.SettingsSuggest = SG

-- Row and header heights, the width of the list (it grows with the field up to the maximum) and the pause
-- after the last key before the list updates.
SG.ROW, SG.HEAD, SG.PAD = 26, 20, 4
SG.MIN_WIDTH, SG.MAX_WIDTH = 360, 460
SG.DELAY = 0.1

local list, field, edit
local state = { rows = {}, shown = {}, selected = nil, query = "" }

local function newRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(SG.ROW)
  row.hover = row:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(1, 1, 1, 0)
  -- The chosen row has a bar at its left edge as well as a different text color: color never carries it alone.
  row.bar = row:CreateTexture(nil, "ARTWORK")
  row.bar:SetPoint("TOPLEFT")
  row.bar:SetPoint("BOTTOMLEFT")
  row.bar:SetWidth(3)
  ns.Bind(row.bar, function(t)
    t:SetColorTexture(Theme.color("accent2"))
  end)
  row.bar:Hide()
  row.right = W.Text(row, { role = "small", color = "textMuted", justify = "RIGHT" })
  row.right:SetPoint("RIGHT", -8, 0)
  row.label = W.Text(row, { role = "ui", color = "text" })
  row.label:SetPoint("LEFT", 10, 0)
  row.label:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
  return row
end

local function newHeader(parent)
  local h = CreateFrame("Frame", nil, parent)
  h:SetHeight(SG.HEAD)
  h.label = W.Text(h, { role = "small", color = "textMuted" })
  h.label:SetPoint("LEFT", 10, 0)
  return h
end

local function create()
  list = CreateFrame("Frame", nil, UIParent)
  list:SetFrameStrata("TOOLTIP")
  list:SetClampedToScreen(true)
  list:EnableMouse(true)
  W.Fill(list, "surface", 1)
  W.Border(list, "accentDim", 1)
  list:Hide()
  list.rows, list.headers = {}, {}
  -- The accessible name of the whole list, tests and audits read it.
  function list.fgName()
    return ns.L["settings.search.list"]
  end
  list:SetScript("OnLeave", function()
    if edit and not edit:HasFocus() and not list:IsMouseOver() then
      SG.Close()
    end
  end)
  return list
end

local function rowAt(index)
  local row = list.rows[index]
  if not row then
    row = newRow(list)
    list.rows[index] = row
    row:SetScript("OnEnter", function(self)
      SG.Select(self.fgIndex)
    end)
    row:SetScript("OnLeave", function()
      ns.HideTooltip()
    end)
    row:SetScript("OnClick", function(self)
      SG.Activate(self.fgIndex)
    end)
  end
  return row
end

local function headerAt(index)
  local h = list.headers[index]
  if not h then
    h = newHeader(list)
    list.headers[index] = h
  end
  return h
end

local function paintSelection()
  for i, row in ipairs(list and list.rows or {}) do
    local on = row:IsShown() and row.fgIndex == state.selected
    row.bar:SetShown(on)
    row.hover:SetColorTexture(1, 1, 1, on and 0.1 or 0)
    W.SetColor(row.label, on and "accent" or "text")
    if i > #state.shown then
      row.bar:Hide()
    end
  end
end

local function showTooltip(index)
  local item = state.shown[index]
  local row = list.rows[index]
  if not (item and row) then
    return
  end
  if item.search then
    ns.ShowTooltip(row, ns.L["settings.search.all"], string.format(ns.L["settings.search.allTip"], state.query), {
      anchor = "ANCHOR_LEFT",
    })
    return
  end
  if item.empty then
    return
  end
  local spec = SS.Tooltip(item.hit)
  ns.ShowTooltip(row, spec.title, spec.text, { lines = spec.lines, hint = spec.hint, anchor = spec.anchor })
end

-- The display rows of a result: headers and hits in order, the empty note, then the row "Search".
local function displayRows(result)
  local rows = {}
  local function add(kind, hit)
    rows[#rows + 1] = { kind = kind, hit = hit }
  end
  if #result.nav > 0 then
    add("header", { text = ns.L["settings.search.groupNav"] })
    for _, hit in ipairs(result.nav) do
      add("hit", hit)
    end
  end
  if #result.items > 0 then
    add("header", { text = ns.L["settings.search.groupSettings"] })
    for _, hit in ipairs(result.items) do
      add("hit", hit)
    end
  end
  if #result.nav == 0 and #result.items == 0 then
    add("empty")
  end
  add("search")
  return rows
end

local function labelOf(hit)
  local prefix = (hit.kind == "setting" or hit.kind == "card") and (hit.featureName .. ": ") or ""
  if prefix == "" then
    return hit.name
  end
  return Theme.hexText("textSecondary", prefix) .. hit.name
end

-- Fills and places the list under the field for a result.
local function render(result)
  if not list then
    create()
  end
  local rows = displayRows(result)
  for _, row in ipairs(list.rows) do
    row:Hide()
  end
  for _, h in ipairs(list.headers) do
    h:Hide()
  end
  state.shown, state.rows = {}, rows
  local y, headerCount, rowCount = SG.PAD, 0, 0
  for _, item in ipairs(rows) do
    if item.kind == "header" then
      headerCount = headerCount + 1
      local h = headerAt(headerCount)
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -y)
      h:SetPoint("TOPRIGHT", list, "TOPRIGHT", -1, -y)
      h.label:SetText(item.hit.text)
      h:Show()
      y = y + SG.HEAD
    else
      rowCount = rowCount + 1
      local row = rowAt(rowCount)
      row.fgIndex = rowCount
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -y)
      row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -1, -y)
      local hit = item.hit
      if item.kind == "hit" then
        row.label:SetText(labelOf(hit))
        row.right:SetText(hit.missing and ns.L["settings.search.pendingShort"] or SS.KindLabel(hit))
        row.fgName = function()
          return SS.Label(hit)
        end
        row.fgDescription = function()
          return hit.hint
        end
      elseif item.kind == "search" then
        local more = result.more
        row.label:SetText(
          more > 0 and string.format(ns.L["settings.search.allMore"], more) or ns.L["settings.search.all"]
        )
        row.right:SetText("")
        row.fgName = function()
          return ns.L["settings.search.all"]
        end
        row.fgDescription = function()
          return string.format(ns.L["settings.search.allTip"], state.query)
        end
        item.search = true
      else
        row.label:SetText(ns.L["settings.search.none"])
        row.right:SetText("")
        item.empty = true
      end
      state.shown[rowCount] = item
      row:Show()
      y = y + SG.ROW
    end
  end
  list:SetHeight(y + SG.PAD)
  local width = math.min(SG.MAX_WIDTH, math.max(SG.MIN_WIDTH, field and field:GetWidth() or SG.MIN_WIDTH))
  list:SetWidth(width)
  list:ClearAllPoints()
  list:SetPoint("TOPRIGHT", field, "BOTTOMRIGHT", 0, -2)
  list:SetScale(field:GetEffectiveScale() / UIParent:GetEffectiveScale())
  list:Show()
  if ns.TopLayer then
    ns.TopLayer.Over(list, ns.TopLayer.LIST)
  end
  state.selected = nil
  paintSelection()
end

function SG.IsOpen()
  return list ~= nil and list:IsShown()
end

function SG.Close()
  if not SG.IsOpen() then
    return false
  end
  ns.HideTooltip()
  list:Hide()
  state.selected = nil
  return true
end

-- Chooses a row (the mouse over it or the arrow keys) and shows its tooltip.
function SG.Select(index)
  if not SG.IsOpen() or not state.shown[index] then
    return
  end
  state.selected = index
  paintSelection()
  showTooltip(index)
end

local function step(delta)
  local count = #state.shown
  if count == 0 then
    return
  end
  local at = state.selected
  if not at then
    at = delta > 0 and 1 or count
  else
    at = (at - 1 + delta) % count + 1
  end
  SG.Select(at)
end

-- Opens a row: a hit goes to its place, "Search" opens the page of results for the typed text.
function SG.Activate(index)
  local item = state.shown[index]
  if not item or item.empty then
    return false
  end
  local query = state.query
  SG.Close()
  if item.search then
    ns.Main.Show("search/" .. (query:gsub("/", " ")))
  else
    SS.Go(item.hit)
  end
  if edit then
    edit:ClearFocus()
  end
  return true
end

local function onSearchPage()
  local current = ns.Router and ns.Router.current or ""
  return current == "search" or current:sub(1, 7) == "search/"
end

local function text()
  return ns.U.trim(edit:GetText() or "")
end

-- Shows the suggestions for what stands in the field. The search page has its own results, no list there.
function SG.Update()
  if not edit or not edit:HasFocus() or onSearchPage() then
    SG.Close()
    return
  end
  local query = text()
  if not SL.Long(query) then
    SG.Close()
    return
  end
  state.query = query
  render(SL.Suggest(query))
end

-- Hooks the field of the title bar once.
function SG.Attach(box)
  if field then
    return
  end
  field, edit = box, box.edit
  edit:HookScript("OnTextChanged", function(self, user)
    if user then
      ns.Debounce("settings-suggest", SG.DELAY, SG.Update)
    end
  end)
  edit:HookScript("OnEditFocusLost", function()
    if not (list and list:IsMouseOver()) then
      SG.Close()
    end
  end)
  edit:HookScript("OnEscapePressed", function()
    SG.Close()
  end)
  edit:SetScript("OnArrowPressed", function(_, key)
    if key ~= "UP" and key ~= "DOWN" then
      return
    end
    if not SG.IsOpen() then
      SG.Update()
    end
    if SG.IsOpen() then
      step(key == "DOWN" and 1 or -1)
    end
  end)
  -- Enter opens the chosen row, without one the old way applies (the search page for the typed text).
  local enter = edit:GetScript("OnEnterPressed")
  edit:SetScript("OnEnterPressed", function(self, ...)
    if SG.IsOpen() and state.selected and SG.Activate(state.selected) then
      return
    end
    SG.Close()
    if enter then
      enter(self, ...)
    end
  end)
end

-- Esc and a click elsewhere go through the shared popup entry points.
local closeOther, otherOpen = ns.Popups.close, ns.Popups.isOpen
function ns.Popups.close()
  return SG.Close() or closeOther()
end
function ns.Popups.isOpen()
  return SG.IsOpen() or otherOpen()
end

-- The title bar exists from the first show of the window on.
local function attach()
  if ns.Main and ns.Main.search then
    SG.Attach(ns.Main.search)
  end
end
ns.On("FG_MAIN_SHOWN", attach)
ns.On("FG_MAIN_HIDDEN", function()
  SG.Close()
end)
ns.On("FG_ROUTE_CHANGED", function()
  SG.Close()
end)
