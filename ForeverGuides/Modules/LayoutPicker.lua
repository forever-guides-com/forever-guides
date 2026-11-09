-- The layout picker of the layout editor (ns.LayoutPicker): a field that shows the open layout and opens a
-- popup with a search box over a scrolling list of layouts. Typing narrows the list, Up, Down, Home, End, Page up
-- and Page down move the highlight, Enter picks it, Esc closes. The open layout is marked with a check mark and
-- its name in the accent color. The popup grows with the editor window (rows follow `maxRows`) and scrolls when
-- there are more layouts than rows.
--   LayoutPicker.New(parent, {
--     height = 24,
--     entries = function() -> { { id, name, badge? }, ... },   all layouts (badge: short muted text on the right)
--     current = function() -> id,                              the open layout
--     onPick = function(id),
--     maxRows = function() -> number,                          rows the popup may show (optional)
--     tooltip = locale key or text, tooltipText = locale key } ) -> button
--   button.Refresh() repaints the name, button:Open() opens the popup, button.fgName() is the accessible name.
local _, ns = ...
local W, L, LA = ns.W, ns.L, ns.LayoutAssign

local LP = {}
ns.LayoutPicker = LP

ns.AddLocale("enUS", {
  ["picker.search"] = "Search layouts",
  ["picker.none"] = "No layout matches.",
  ["picker.title"] = "Layout",
  ["picker.tip"] = "Pick the layout to edit. Type to search, Up and Down to move, Enter to pick.",
})
ns.AddLocale("deDE", {
  ["picker.search"] = "Layouts suchen",
  ["picker.none"] = "Kein Layout passt.",
  ["picker.title"] = "Layout",
  ["picker.tip"] = "Wähle das Layout, das du bearbeitest. Tippen sucht, Pfeil hoch und runter bewegt, Enter wählt.",
})

local ROW_H, SEARCH_H, GAP = 24, 26, 6
local MIN_ROWS, MAX_ROWS, DEFAULT_ROWS = 4, 14, 8

-- One popup for every picker, like the dropdown popup: only one list is open at a time.
local popup, blocker

local function close()
  if popup and popup:IsShown() then
    popup:Hide()
    blocker:Hide()
    return true
  end
  return false
end

-- Esc and a click elsewhere go through the shared popup entry points.
local closeOther, otherOpen = ns.Popups.close, ns.Popups.isOpen
function ns.Popups.close()
  return close() or closeOther()
end

function ns.Popups.isOpen()
  return (popup ~= nil and popup:IsShown()) or otherOpen()
end

LP.Close = close

function LP.IsOpen()
  return popup ~= nil and popup:IsShown()
end

function LP.Popup()
  return popup
end

local function rowsFor(owner, count)
  local max = owner.opts.maxRows and owner.opts.maxRows() or DEFAULT_ROWS
  max = math.max(MIN_ROWS, math.min(MAX_ROWS, math.floor(tonumber(max) or DEFAULT_ROWS)))
  return math.max(1, math.min(count, max))
end

local function pick(entry)
  local owner = popup and popup.owner
  close()
  if owner and entry then
    ns.Safe("layout-picker-pick", owner.opts.onPick, entry.id)
  end
end

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints()
  row.hl:SetColorTexture(1, 1, 1, 0)
  row.mark = W.Glyph(row, "check", 12, "accent")
  row.mark:SetPoint("LEFT", 6, 0)
  row.badge = W.Text(row, { role = "small", color = "textMuted", justify = "RIGHT" })
  row.badge:SetPoint("RIGHT", -6, 0)
  row.text = W.Text(row, { role = "ui" })
  row.text:SetPoint("LEFT", 24, 0)
  row.text:SetPoint("RIGHT", row.badge, "LEFT", -6, 0)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)
  row:SetScript("OnEnter", function()
    row.hl:SetColorTexture(1, 1, 1, 0.08)
  end)
  row:SetScript("OnLeave", function()
    row.hl:SetColorTexture(1, 1, 1, row.active and 0.14 or 0)
  end)
  row:SetScript(
    "OnClick",
    ns.Wrap("layout-picker-row", function()
      pick(row.entry)
    end)
  )
  ns.Focus.register(row, function(self)
    self:Click()
  end)
  -- The accessible name is the layout's name.
  row.fgName = function()
    return row.entry and row.entry.name or ""
  end
  return row
end

local function bindRow(row, entry, index)
  local owner = popup.owner
  row.entry = entry
  row.active = index == popup.active
  row.hl:SetColorTexture(1, 1, 1, row.active and 0.14 or 0)
  local current = owner and entry.id == popup.currentId
  row.mark:SetShown(current == true)
  W.SetText(row.text, nil, entry.name)
  W.SetColor(row.text, current and "accent" or "text")
  W.SetText(row.badge, nil, entry.badge or "")
end

local function build()
  blocker = CreateFrame("Button", nil, UIParent)
  blocker:SetAllPoints(UIParent)
  blocker:SetFrameStrata("TOOLTIP")
  blocker:SetScript("OnClick", ns.Popups.close)
  blocker:Hide()
  popup = CreateFrame("Frame", nil, UIParent)
  popup:SetFrameStrata("TOOLTIP")
  popup:SetFrameLevel(blocker:GetFrameLevel() + 5)
  popup:SetClampedToScreen(true)
  popup:EnableMouse(true)
  W.Fill(popup, "surface", 1)
  W.Border(popup, "accentDim", 1)
  popup.search = W.EditBox(popup, {
    placeholder = "picker.search",
    clear = true,
    onChange = function(text)
      popup.refilter(text)
    end,
    onEnter = function()
      local entry = popup.shown[popup.active or 1]
      if entry then
        pick(entry)
      end
    end,
  })
  popup.search:SetPoint("TOPLEFT", 4, -4)
  popup.search:SetPoint("TOPRIGHT", -4, -4)
  popup.search:SetHeight(SEARCH_H)
  popup.none = W.Text(popup, { key = "picker.none", role = "ui", color = "textSecondary" })
  popup.none:SetPoint("TOPLEFT", popup.search, "BOTTOMLEFT", 8, -10)
  popup.list = W.ScrollList(popup, { rowHeight = ROW_H, createRow = createRow, bindRow = bindRow })
  popup.list:SetPoint("TOPLEFT", popup.search, "BOTTOMLEFT", 0, -GAP)
  popup.shown, popup.all = {}, {}

  local function move(key)
    local to = LA.Move(#popup.shown, popup.active, key, popup.rows)
    if to then
      popup.active = to
      popup.list:Reveal(to)
      popup.list:SetData(popup.shown)
    end
  end
  local eb = popup.search.edit
  -- The edit box keeps the keyboard while the popup is open: arrows move the highlight, not the caret.
  eb:SetScript("OnArrowPressed", function(_, key)
    move(tostring(key):upper())
  end)
  eb:SetScript("OnKeyDown", function(_, key)
    key = tostring(key):upper()
    if key == "HOME" or key == "END" or key == "PAGEUP" or key == "PAGEDOWN" then
      move(key)
    end
  end)
  eb:SetScript("OnEscapePressed", function()
    ns.Popups.close()
  end)

  function popup.refilter(text)
    popup.shown = LA.Filter(popup.all, text)
    popup.active = nil
    for i, entry in ipairs(popup.shown) do
      if entry.id == popup.currentId then
        popup.active = i
      end
    end
    popup.active = popup.active or (#popup.shown > 0 and 1 or nil)
    popup.none:SetShown(#popup.shown == 0)
    popup.list:SetData(popup.shown)
    if popup.active then
      popup.list:Reveal(popup.active)
    end
  end
  popup:Hide()
end

local function open(owner)
  if not popup then
    build()
  end
  popup.owner = owner
  popup.all = owner.opts.entries()
  popup.currentId = owner.opts.current()
  local count = #popup.all
  popup.rows = rowsFor(owner, count)
  local width = math.max(owner:GetWidth(), 280)
  popup:SetSize(width, SEARCH_H + 8 + GAP + popup.rows * ROW_H + 2)
  popup.list:SetSize(width - 8, popup.rows * ROW_H)
  popup:ClearAllPoints()
  popup:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  popup:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
  popup.search.edit:SetText("")
  blocker:Show()
  popup:Show()
  ns.TopLayer.Over(blocker, ns.TopLayer.BLOCKER)
  ns.TopLayer.Over(popup, ns.TopLayer.LIST)
  popup.refilter("")
  popup.search.edit:SetFocus()
end

-- opts: see the top of the file.
function LP.New(parent, opts)
  local b = CreateFrame("Button", nil, parent)
  b.opts = opts
  b:SetHeight(opts.height or 24)
  W.Fill(b, "surface2")
  W.Border(b, "white", 0.25)
  b.label = W.Text(b, { role = "ui", color = "text", justify = "LEFT" })
  b.label:SetWordWrap(false)
  b.arrow = W.Glyph(b, "chevron-down", 12, "textMuted")
  b.arrow:SetPoint("RIGHT", -8, 0)
  b.label:SetPoint("LEFT", 8, 0)
  b.label:SetPoint("RIGHT", b.arrow, "LEFT", -6, 0)
  function b.Refresh()
    local id = opts.current()
    local text = ""
    for _, entry in ipairs(opts.entries()) do
      if entry.id == id then
        text = entry.name
      end
    end
    b.shownName = text
    W.SetText(b.label, nil, text)
  end
  b.fgName = function()
    local key = type(opts.title) == "function" and opts.title() or opts.title or "picker.title"
    local title = L[key] ~= key and L[key] or key
    return title .. ": " .. (b.shownName or "")
  end
  b:SetScript(
    "OnClick",
    ns.Wrap("layout-picker-open", function()
      if LP.IsOpen() then
        close()
      else
        open(b)
      end
    end)
  )
  local function tip(self)
    ns.ShowTooltip(self, b.fgName(), L[opts.tooltipText or "picker.tip"])
  end
  b:HookScript("OnEnter", tip)
  b:HookScript("OnLeave", ns.HideTooltip)
  b.fgOnFocus, b.fgOnBlur = tip, ns.HideTooltip
  ns.Focus.register(b, function()
    open(b)
  end)
  function b:Open()
    open(b)
  end
  return b
end
