-- Forever Chat, the conversation list: search box, four tabs with their unread counts and one row per
-- conversation (symbol, name, preview, age, unread count, pin and mute marks). While the box holds text the
-- rows are the search over the conversations of the tab (chats by name, then messages). The rules are ChatListLogic;
-- this file only draws them. Mouse and keys (arrows, Home, End, Enter) pick a row, the window reacts through
-- win.Pick(key, seq).
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, Theme, K = FG.W, FG.L, FG.Theme, FG.PageKit
local LL, Conv = chat.ListLogic, chat.Conversations

local List = {}
chat.List = List

List.ROW = 50
-- Distance of the preview line from the bottom edge of a row.
List.SUB_GAP = 8
List.PREBUILD = 24
List.CHIP = 28
-- Share of the info color in the tile of a Battle.net chip (tested: the letter keeps 4.5 to 1).
List.BNET_TINT = 0.3
List.TAB_ORDER = Conv.TAB_ORDER
local PAD, GAP, HEX = 8, 6, 16
local TAB_GAP, TAB_PAD, TAB_H = 4, 8, 28

local dates, dateCount = {}, 0

-- Clock text of the game (the global date), os.date outside the game. The answer is kept per format and minute (per
-- second when the format shows seconds).
function List.DateOf(format, time)
  local fn = rawget(_G, "date") or (os and os.date)
  if type(format) ~= "string" or type(time) ~= "number" or time ~= time then
    return fn(format, time)
  end
  local at = format:find("%%[SscTX]") and time or time - time % 60
  local key = format .. "|" .. at
  local hit = dates[key]
  if hit == nil then
    if dateCount >= 512 then
      dates, dateCount = {}, 0
    end
    hit = fn(format, time)
    dates[key], dateCount = hit, dateCount + 1
  end
  return hit
end

-- The placeholder of an edit box (W.EditBox) is anchored on the left only and would run past the box and into
-- its neighbours: bound it on the right too, the client cuts a longer text.
function List.FitPlaceholder(box)
  for _, region in ipairs({ box:GetRegions() }) do
    if region.GetObjectType and region:GetObjectType() == "FontString" then
      region:SetPoint("RIGHT", box, "RIGHT", -8, 0)
      region:SetWordWrap(false)
    end
  end
end

-- Symbol chip: the class circle where the class is known, else a tile with the letter of the kind.
function List.NewChip(parent, size)
  local chip = CreateFrame("Frame", nil, parent)
  chip:SetSize(size, size)
  chip.tile = chip:CreateTexture(nil, "BACKGROUND")
  chip.tile:SetAllPoints()
  chip.letter = W.Text(chip, { role = "ui", color = "accent2", justify = "CENTER" })
  chip.letter:SetPoint("CENTER")
  chip.icon = chip:CreateTexture(nil, "ARTWORK")
  chip.icon:SetAllPoints()
  FG.Bind(chip, function()
    List.PaintTile(chip)
  end)
  return chip
end

-- The tile of a chip: the plain surface, tinted blue for a Battle.net partner (the letter B says it too).
function List.PaintTile(chip)
  if chip.bnet then
    local r1, g1, b1 = Theme.rgb("surface3")
    local r2, g2, b2 = Theme.rgb("info")
    local t = List.BNET_TINT
    chip.tile:SetColorTexture(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t, 1)
    W.SetColor(chip.letter, "text")
  else
    chip.tile:SetColorTexture(Theme.color("surface3", 1))
    W.SetColor(chip.letter, "accent2")
  end
end

-- bnet: the chip of a Battle.net partner, a tinted tile with the letter of the kind, never a class icon.
function List.PaintChip(chip, letter, class, symbol, bnet)
  chip.bnet = bnet == true
  List.PaintTile(chip)
  if symbol then
    chip.icon:SetTexture(symbol)
    chip.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    chip.icon:Show()
    chip.tile:Hide()
    chip.letter:Hide()
    return
  end
  local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if coords and FG.GuildKit.KNOWN_CLASS[class] then
    chip.icon:SetTexture(K.CLASS_ICON_SHEET)
    chip.icon:SetTexCoord(unpack(coords))
    chip.icon:Show()
    chip.tile:Hide()
    chip.letter:Hide()
  else
    chip.icon:Hide()
    chip.tile:Show()
    chip.letter:Show()
    chip.letter:SetText(letter or "")
  end
end

-- Text of the age of a time ("now", "5 min", "3 h", "2 d", "11/02").
function List.AgeText(now, time)
  local unit, n = LL.Age(now, time)
  if unit == "now" then
    return L["chat.time.now"]
  elseif unit == "date" then
    return type(time) == "number" and List.DateOf(L["chat.time.date"], time) or ""
  end
  return string.format(L["chat.time." .. unit], n)
end

local function rowHeight()
  return K.scaledHeight(List.ROW)
end

-- Rows ------------------------------------------------------------------------------------------------------

-- Anchors that depend on the texts: the title stops before the age and the pin, the preview before the count.
local function layoutRow(row)
  local data = row.data
  local unread = data and data.label and data.label ~= ""
  local left = 2 * PAD + List.CHIP
  local ageW = math.ceil(row.age:GetStringWidth())
  row.age:ClearAllPoints()
  row.age:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PAD, -7)
  row.pin:ClearAllPoints()
  row.pin:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(PAD + ageW + 4), -6)
  row.title:ClearAllPoints()
  row.title:SetPoint("TOPLEFT", row, "TOPLEFT", left, -7)
  row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(PAD + ageW + 24), -7)
  local reserve = unread and (HEX + 8 + math.ceil(row.count:GetStringWidth())) or 0
  row.sub:ClearAllPoints()
  row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, List.SUB_GAP)
  row.sub:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -(PAD + reserve + (unread and GAP or 0)), List.SUB_GAP)
end

local function showTip(row)
  local d = row.data
  if not d or d.kind == "head" then
    return
  end
  local lines = {}
  if d.pinned then
    lines[#lines + 1] = L["chat.row.pinned"]
  end
  if d.muted then
    lines[#lines + 1] = L["chat.row.muted"]
  end
  if d.count and d.count > 0 then
    lines[#lines + 1] = string.format(L["chat.row.unread"], d.count)
  end
  if d.mentions and d.mentions > 0 then
    lines[#lines + 1] = string.format(L["chat.row.mentions"], d.mentions)
  end
  local kind = d.kindOf or "whisper"
  local second = L["chat.kind." .. kind]
  -- A conversation named like its kind ("Nearby") says what it holds instead of repeating the title.
  if second == d.title and LL.HINTS[kind] then
    second = L[LL.HINTS[kind]]
  end
  FG.ShowTooltip(row, d.title, second, { lines = lines, anchor = "ANCHOR_RIGHT" })
end

local function newRow(list)
  return function(parent)
    local row = CreateFrame("Button", nil, parent)
    list.built = list.built + 1
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(3)
    row.chip = List.NewChip(row, List.CHIP)
    row.chip:SetPoint("LEFT", row, "LEFT", PAD, 0)
    row.title = W.Text(row, { role = "ui", color = "text" })
    row.title:SetWordWrap(false)
    row.sub = W.Text(row, { role = "micro", color = "textSecondary" })
    row.sub:SetWordWrap(false)
    row.age = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
    row.pin = W.Glyph(row, "pin", 12, "accent2")
    row.pin:Hide()
    row.hex = row:CreateTexture(nil, "ARTWORK")
    row.hex:SetSize(HEX, HEX)
    row.hex:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -PAD, List.SUB_GAP)
    row.count = W.Text(row, { role = "micro", color = "text", justify = "RIGHT" })
    row.count:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -(PAD + HEX + 4), List.SUB_GAP)
    row.head = W.Text(row, { role = "micro", color = "accent2" })
    row.head:SetPoint("LEFT", PAD, 0)
    FG.Bind(row, function()
      row.bar:SetColorTexture(Theme.color("accent2"))
      row.hex:SetTexture(FG.BadgeAssets.Path(HEX))
    end)
    row:SetScript("OnEnter", function(self)
      if self.data and self.data.kind ~= "head" and not self.fgSelected then
        self.bg:SetColorTexture(Theme.color("surface2", 0.8))
      end
      showTip(self)
    end)
    row:SetScript("OnLeave", function(self)
      List.PaintRowBg(self)
      FG.HideTooltip()
    end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript(
      "OnClick",
      FG.Wrap("chat-list-click", function(self, button)
        if self.data and self.data.kind ~= "head" then
          if button == "RightButton" then
            list.win.Menu(self.data.key)
          else
            list.win.Pick(self.data.key, self.data.seq)
          end
        end
      end)
    )
    FG.Focus.register(row, function(self)
      self:Click()
    end)
    return row
  end
end

function List.PaintRowBg(row)
  if row.fgSelected then
    row.bg:SetColorTexture(Theme.color("surface3", 0.95))
  else
    row.bg:SetColorTexture(0, 0, 0, 0)
  end
  row.bar:SetShown(row.fgSelected == true)
end

local function bindRow(list)
  return function(row, data)
    row.data = data
    row.fgSelected = data.kind ~= "head"
      and data.key == list.selected
      and (data.seq == nil or data.seq == list.selectedSeq)
    local isHead = data.kind == "head"
    for _, part in ipairs({ row.chip, row.title, row.sub, row.age }) do
      part:SetShown(not isHead)
    end
    row.head:SetShown(isHead)
    row:EnableMouse(not isHead)
    if isHead then
      row.head:SetText(L[data.textKey])
      row.pin:Hide()
      row.hex:Hide()
      row.count:SetText("")
      List.PaintRowBg(row)
      return
    end
    row.chip:SetShown(true)
    local bnet = data.kindOf == "bnet"
    List.PaintChip(row.chip, data.letter, not bnet and list.win.ClassOf(data.key) or nil, data.icon, bnet)
    local marks = (data.muted and " (" .. L["chat.row.muted"] .. ")" or "")
    row.title:SetText(data.title .. marks)
    row.sub:SetText(data.sub or "")
    row.age:SetText(List.AgeText(FG.U.now(), data.time))
    row.pin:SetShown(data.pinned == true)
    local unread = data.label ~= nil and data.label ~= ""
    row.hex:SetShown(unread)
    row.count:SetText(unread and data.label or "")
    row.count:SetShown(unread)
    layoutRow(row)
    List.PaintRowBg(row)
  end
end

-- List ------------------------------------------------------------------------------------------------------

-- win: { Pick(key, seq, fromList), ClassOf(key) -> class token or nil, Menu(key) (right click), New() (the
-- button "New message", optional), TabChanged(tab) (optional: a tab was picked, the window picks its chat) }.
function List.Create(parent, win)
  local list = { win = win, tab = Conv.TAB_ORDER[1], query = "", rows = {}, built = 0, shown = 0, spare = {} }
  list.makeRow = newRow(list)
  local f = CreateFrame("Frame", nil, parent)
  list.frame = f

  list.newButton = W.Action(f, {
    icon = "plus",
    size = 26,
    tooltip = "chat.new.button",
    tooltipText = "chat.new.tip",
    wrap = "chat-list-new",
    onClick = function()
      if win.New then
        win.New()
      end
    end,
  })
  list.newButton:SetPoint("TOPRIGHT", 0, 0)
  list.search = W.EditBox(f, { placeholder = "chat.search", clear = true, height = 26 })
  list.search:SetPoint("TOPLEFT", 0, 0)
  list.search:SetPoint("TOPRIGHT", list.newButton, "TOPLEFT", -GAP, 0)
  List.FitPlaceholder(list.search)
  local edit = list.search.edit
  edit:HookScript("OnEnter", function()
    FG.ShowTooltip(edit, L["chat.search"], L["chat.search.tip"])
  end)
  edit:HookScript("OnLeave", FG.HideTooltip)
  edit:HookScript(
    "OnTextChanged",
    FG.Wrap("chat-search", function()
      local text = edit:GetText() or ""
      if text ~= list.query then
        list.query = text
        list:Refresh()
      end
    end)
  )
  edit:HookScript("OnEscapePressed", function()
    if (edit:GetText() or "") ~= "" then
      edit:SetText("")
      list.query = ""
      list:Refresh()
    end
    edit:ClearFocus()
  end)
  local function leave()
    edit:ClearFocus()
    list:Step("DOWN", true)
  end
  edit:HookScript("OnEnterPressed", leave)
  edit:HookScript("OnTabPressed", leave)
  edit:HookScript("OnKeyDown", function(_, key)
    if key == "DOWN" then
      leave()
    end
  end)

  local tabs = {}
  for _, id in ipairs(Conv.TAB_ORDER) do
    tabs[#tabs + 1] = { id = id, key = "chat.tab." .. id }
  end
  list.tabs = W.Tabs(f, {
    tabs = tabs,
    onSelect = function(id)
      if list.tab ~= id then
        list.tab = id
        -- The new tab starts at its top; the rows of the old one are gone.
        if list.view then
          list.view:Reveal(1)
        end
        list:Refresh()
      end
      -- A click on the tab that is open too: an empty pane gets the chat of the tab.
      if not list.silent and win.TabChanged then
        win.TabChanged(id)
      end
    end,
  })
  list.unread, list.unreadLines, list.invites = {}, {}, 0
  for _, id in ipairs(Conv.TAB_ORDER) do
    local button = list.tabs.buttons[id]
    -- The label fills the button and is cut there, so a long name never runs into the next tab.
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", 2, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -2, 0)
    button.label:SetWordWrap(false)
    button:HookScript("OnEnter", function(self)
      local count = list.unreadLines[id] or 0
      local lines = count > 0 and { string.format(L["chat.row.unread"], count) } or {}
      local invites = id == "teams" and list.invites or 0
      if invites > 0 then
        lines[#lines + 1] = chat.TeamsView.InviteLine(invites)
      end
      lines = #lines > 0 and lines or nil
      FG.ShowTooltip(self, L["chat.tab." .. id], nil, { lines = lines })
    end)
    button:HookScript("OnLeave", FG.HideTooltip)
  end
  list.tabs:Select(list.tab)

  list.host = CreateFrame("Frame", nil, f)
  list.view = W.ScrollList(list.host, {
    rowHeight = rowHeight(),
    createRow = function(host)
      return table.remove(list.spare) or list.makeRow(host)
    end,
    bindRow = bindRow(list),
  })
  list.view:SetAllPoints()
  -- Rows before they are needed: a taller window in combat finds them ready (the window is at most 1000 px high).
  for _ = 1, List.PREBUILD do
    local row = list.makeRow(list.view)
    row:Hide()
    list.spare[#list.spare + 1] = row
  end
  list.empty = W.Text(list.host, { role = "ui", color = "textMuted", justify = "CENTER", wrap = true })
  list.empty:SetPoint("TOPLEFT", 8, -12)
  list.empty:SetPoint("TOPRIGHT", -8, -12)
  list.empty:Hide()
  list.open = W.Action(list.host, {
    key = "chat.empty.open",
    wrap = "chat-empty-open",
    opens = true,
    onClick = function()
      if win.Settings then
        win.Settings()
      end
    end,
  })
  list.open:SetPoint("TOP", list.empty, "BOTTOM", 0, -8)
  list.open:Hide()
  list.more = W.Text(f, { role = "micro", color = "textMuted", wrap = true, key = "chat.search.more" })
  list.more:Hide()
  list.teamsView = chat.TeamsView.Attach(list, f)
  list.hint = W.Text(f, { role = "micro", color = "textMuted", wrap = true, key = "chat.win.hint" })
  list.hint:SetPoint("BOTTOMLEFT", 0, 0)
  list.hint:SetPoint("BOTTOMRIGHT", 0, 0)

  -- One row of tabs: each gets its text plus an even share of what is left. When the full names do not fit,
  -- the short names show, then the shortest marks (the tooltip names the tab in full); the client cuts what still does not fit and the tooltip names the tab in full.
  local function layoutTabs(width)
    local ids = Conv.TAB_ORDER
    local labels = {}
    local function measure(level)
      local sum = 0
      for i, id in ipairs(ids) do
        local label = L["chat.tab." .. id .. (level and ("." .. level) or "")]
        if (list.unread[id] or 0) > 0 then
          label = string.format(L["chat.tab.unread"], label, chat.Unread.Label(list.unread[id]))
        end
        local fs = list.tabs.buttons[id].label
        W.SetText(fs, nil, label)
        labels[i] = math.ceil(fs:GetStringWidth())
        sum = sum + labels[i]
      end
      return sum
    end
    local room = width - (#ids - 1) * TAB_GAP
    local sum = measure(nil)
    if sum + #ids * TAB_PAD > room then
      sum = measure("short")
    end
    if sum + #ids * TAB_PAD > room then
      sum = measure("tiny")
    end
    -- Text plus an even share of the room left, or squeezed when even the short names do not fit.
    local pad = (room - sum) / #ids
    local x = 0
    for i, id in ipairs(ids) do
      local button = list.tabs.buttons[id]
      local w = math.floor(pad >= 0 and labels[i] + pad or labels[i] * room / sum)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", list.tabs, "TOPLEFT", x, 0)
      button:SetSize(w, TAB_H)
      x = x + w + TAB_GAP
    end
  end

  function list:Layout(width)
    list.tabs:ClearAllPoints()
    list.tabs:SetPoint("TOPLEFT", list.search, "BOTTOMLEFT", 0, -GAP)
    list.tabs:SetSize(width, TAB_H)
    layoutTabs(width)
    local above = list.tabs
    local head = list.teamsView:Layout(width)
    if head > 0 then
      list.teamsView.frame:ClearAllPoints()
      list.teamsView.frame:SetPoint("TOPLEFT", list.tabs, "BOTTOMLEFT", 0, -GAP)
      above = list.teamsView.frame
    end
    list.host:ClearAllPoints()
    list.host:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -GAP)
    list.host:SetPoint("BOTTOMRIGHT", list.hint, "TOPRIGHT", 0, GAP)
    list.view:SetRowHeight(rowHeight())
    list.open:SetWidth(math.min(list.open:FullWidth(), math.max(20, width - 2 * PAD)))
    list.more:ClearAllPoints()
    list.more:SetPoint("BOTTOMLEFT", list.hint, "TOPLEFT", 0, 2)
    list.more:SetPoint("BOTTOMRIGHT", list.hint, "TOPRIGHT", 0, 2)
  end

  -- True while the list would have to build row frames it does not have (not done in combat).
  function list:NeedsFrames()
    local h = list.host:GetHeight()
    return type(h) == "number" and math.floor(h / rowHeight()) > list.built
  end

  function list:Context()
    local icons = chat.TeamsView.Icons()
    return {
      iconOf = function(conv)
        local id = chat.TeamsUILogic.TeamId(conv.key)
        return id and (icons[id] or chat.TeamsLogic.LIMITS.DEFAULT_ICON) or nil
      end,
      now = FG.U.now(),
      db = chat.db,
      kindLabel = function(kind)
        return L["chat.kind." .. kind]
      end,
      you = L["chat.you"],
      hidden = L["chat.hidden.preview"],
    }
  end

  function list:Selectable()
    local n = 0
    for _, row in ipairs(list.rows) do
      n = n + (row.kind ~= "head" and 1 or 0)
    end
    return n
  end

  -- Builds the rows for the tab or the query and draws them; keeps the scroll position.
  function list:Refresh()
    local ctx = list:Context()
    local query = list.query
    local cut = false
    if query:find("%S") then
      list.rows, cut = LL.SearchRows(chat.convs, query, ctx, list.tab)
    else
      list.rows = LL.Rows(chat.convs, list.tab, ctx)
    end
    list.shown = list:Selectable()
    list.view:SetData(list.rows)
    local reason = LL.EmptyReason(Conv.Count(chat.convs), list.shown, query)
    -- No chats because the intake is off: say where to switch it on.
    if reason == "none" and chat.Settings and not chat.Settings.Value("intake") then
      reason = "intakeOff"
    end
    local teamsEmpty = reason ~= nil and reason ~= "search" and list.tab == "teams"
    list.empty:SetText(reason and L[teamsEmpty and "chat.teams.empty" or ("chat.empty." .. reason)] or "")
    list.empty:SetShown(reason ~= nil)
    list.open:SetShown(reason == "intakeOff" and not teamsEmpty)
    list.more:SetShown(cut)
    list.unreadLines = LL.TabUnread(chat.convs)
    list.invites = chat.TeamsView.OpenInvites()
    list.unread = {}
    for id, n in pairs(list.unreadLines) do
      list.unread[id] = id == "teams" and chat.TeamsUILogic.TabCount(n, list.invites) or n
    end
    list:Layout(list.frame:GetWidth() or 0)
  end

  -- quiet: the window is not told (it picks the chat itself, e.g. while it opens).
  function list:SetTab(id, quiet)
    if list.tabs.buttons[id] then
      list.silent = quiet == true
      list.tabs:Select(id)
      list.silent = false
    end
  end

  function list:SetSelected(key, seq)
    list.selected, list.selectedSeq = key, seq
    list.view:SetData(list.rows)
  end

  -- Index of the selected row in list.rows, nil when it is not in the list.
  function list:IndexOf(key, seq)
    for i, row in ipairs(list.rows) do
      if row.kind ~= "head" and row.key == key and (seq == nil or row.seq == seq) then
        return i
      end
    end
    return nil
  end

  -- Moves the selection by a key (UP, DOWN, HOME, END, PAGEUP, PAGEDOWN). first: from the top when
  -- nothing is selected. True when the key moved.
  function list:Step(key, first)
    local at = list:IndexOf(list.selected, list.selectedSeq)
    local target = LL.Navigate(list.rows, first and 0 or at, first and "DOWN" or key)
    local row = target and list.rows[target]
    if not row then
      return false
    end
    list.view:Reveal(target)
    win.Pick(row.key, row.seq, true)
    return true
  end

  function list:FocusSearch()
    edit:SetFocus()
  end

  return list
end
