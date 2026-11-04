-- Forever Chat, the symbol choice (game access): a grid of the macro icons of the game, shown page by page (the
-- icons have no names to search for). One building block for the form "new team" and the panel of a team:
-- Picker.Create(parent, { onPick(icon), onBack() }) gives a frame with Open(current), Fit(width) -> height.
-- A click or Enter on a symbol picks it; the buttons "Back" and the arrows leave or turn the page.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, Theme, K = FG.W, FG.L, FG.Theme, FG.PageKit
local IP, UL = chat.IconPickerLogic, chat.TeamsUILogic

local Picker = {}
chat.IconPicker = Picker

Picker.CELL, Picker.GAP, Picker.ROWS = 30, 4, 5
local HEAD = 22

local cache

-- The symbols of the game, read once (the list is long); the add-on's own catalog stands in when the game has none.
function Picker.List()
  if not cache then
    cache = IP.Gather(function(name)
      local fn = rawget(_G, name)
      return type(fn) == "function" and fn or nil
    end, function()
      local spells = FG.MacroSpells
      return spells and type(spells.catalogIcons) == "function" and spells.catalogIcons() or {}
    end)
  end
  return cache
end

function Picker.Reset()
  cache = nil
end

local function enabled(frame, on)
  if frame.SetEnabled then
    frame:SetEnabled(on)
  end
end

local function cellSize()
  return K.scaledHeight(Picker.CELL)
end

local function newCell(picker, index)
  local cell = CreateFrame("Button", nil, picker.frame)
  cell.tex = cell:CreateTexture(nil, "ARTWORK")
  cell.tex:SetPoint("TOPLEFT", 2, -2)
  cell.tex:SetPoint("BOTTOMRIGHT", -2, 2)
  cell.mark = cell:CreateTexture(nil, "OVERLAY")
  cell.mark:SetAllPoints()
  cell:SetScript("OnEnter", function()
    picker.cursor = index
    picker:Paint()
  end)
  cell:SetScript(
    "OnClick",
    FG.Wrap("chat-icon-pick", function()
      if cell.icon and picker.opts.onPick then
        picker.opts.onPick(cell.icon)
      end
    end)
  )
  FG.Focus.register(cell, function(self)
    self:Click()
  end)
  cell:Hide()
  return cell
end

function Picker.Create(parent, opts)
  local picker = { opts = opts or {}, page = 1, cursor = 1, cells = {}, shown = {}, cols = 6, current = nil }
  local f = CreateFrame("Frame", nil, parent)
  picker.frame = f
  picker.title = W.Text(f, { key = "chat.teams.icon.title", role = "h3", color = "accent2" })
  for i = 1, IP.PAGE_MAX do
    picker.cells[i] = newCell(picker, i)
  end
  picker.prev = W.Action(f, {
    icon = "chevron-left",
    size = 24,
    tooltip = "chat.teams.icon.prev",
    wrap = "chat-icon-prev",
    onClick = function()
      picker:Turn(-1)
    end,
  })
  picker.next = W.Action(f, {
    icon = "chevron-right",
    size = 24,
    tooltip = "chat.teams.icon.next",
    wrap = "chat-icon-next",
    onClick = function()
      picker:Turn(1)
    end,
  })
  picker.pageText = W.Text(f, { role = "micro", color = "textMuted", justify = "CENTER" })
  picker.back = W.Action(f, {
    key = "chat.teams.back",
    wrap = "chat-icon-back",
    onClick = function()
      if picker.opts.onBack then
        picker.opts.onBack()
      end
    end,
  })
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    picker:Turn(-delta)
  end)
  FG.Bind(f, function()
    for _, cell in ipairs(picker.cells) do
      cell.mark:SetColorTexture(1, 1, 1, 0)
    end
  end)

  function picker:Paint()
    local list = Picker.List()
    local ids, page, pages = IP.Page(list, self.page, self.per or IP.PAGE_MAX)
    self.page, self.shown = page, ids
    self.cursor = math.max(1, math.min(math.max(1, #ids), self.cursor))
    for i, cell in ipairs(self.cells) do
      local id = ids[i]
      cell.icon = id
      if id then
        cell.tex:SetTexture(id)
        local on = id == self.current
        local hot = i == self.cursor
        local r, g, b = Theme.rgb("accent2")
        cell.mark:SetColorTexture(r, g, b, on and 0.45 or (hot and 0.25 or 0))
        cell:Show()
      else
        cell:Hide()
      end
    end
    self.pageText:SetText(string.format(L["chat.teams.icon.page"], page, pages))
    enabled(self.prev, page > 1)
    enabled(self.next, page < pages)
  end

  function picker:Turn(step)
    local list = Picker.List()
    local pages = IP.Pages(#list, self.per or IP.PAGE_MAX)
    local page = math.max(1, math.min(pages, self.page + step))
    if page ~= self.page then
      self.page = page
      self:Paint()
    end
  end

  -- Shows the page of the symbol that is chosen now (current may be nil).
  function picker:Open(current)
    self.current = current
    self.page = IP.PageOf(Picker.List(), current, self.per or IP.PAGE_MAX)
    self.cursor = 1
    self:Paint()
  end

  -- Places the parts for the width and returns the height. Columns follow the width, rows are fixed, so a page
  -- never holds more than PAGE_MAX symbols.
  function picker:Fit(width)
    local cell, gap = cellSize(), Picker.GAP
    self.cols = IP.Columns(width, cell, gap)
    self.per = IP.PerPage(self.cols, Picker.ROWS)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    self.title:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    local top = math.ceil(self.title:GetStringHeight()) + 6
    for i, c in ipairs(self.cells) do
      local row, col = math.floor((i - 1) / self.cols), (i - 1) % self.cols
      c:ClearAllPoints()
      c:SetSize(cell, cell)
      c:SetPoint("TOPLEFT", f, "TOPLEFT", col * (cell + gap), -(top + row * (cell + gap)))
    end
    local rows = math.ceil(self.per / self.cols)
    top = top + rows * (cell + gap) + 2
    self.prev:ClearAllPoints()
    self.prev:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
    self.next:ClearAllPoints()
    self.next:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -top)
    self.pageText:ClearAllPoints()
    self.pageText:SetPoint("LEFT", self.prev, "RIGHT", 4, 0)
    self.pageText:SetPoint("RIGHT", self.next, "LEFT", -4, 0)
    top = top + math.max(24, K.scaledHeight(HEAD)) + 6
    self.back:ClearAllPoints()
    self.back:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
    self.back:SetWidth(math.min(self.back:FullWidth(), width))
    top = top + 24
    f:SetHeight(top)
    f:SetWidth(width)
    self:Paint()
    return top
  end

  -- Keys: arrows walk the grid, PageUp and PageDown turn the page, Enter picks, Esc goes back.
  function picker:Key(key)
    if key == "PAGEUP" or key == "PAGEDOWN" then
      self:Turn(key == "PAGEUP" and -1 or 1)
      return true
    elseif key == "ENTER" then
      local id = self.shown[self.cursor]
      if id and self.opts.onPick then
        self.opts.onPick(id)
      end
      return true
    elseif key == "ESCAPE" then
      if self.opts.onBack then
        self.opts.onBack()
      end
      return true
    end
    local cursor, step = IP.Move(self.cursor, key, self.cols, #self.shown)
    if cursor == self.cursor and step == 0 then
      return key == "HOME" or key == "END"
    end
    if step ~= 0 then
      self:Turn(step)
      self.cursor = step > 0 and 1 or #self.shown
    else
      self.cursor = cursor
    end
    self:Paint()
    return true
  end

  f:Hide()
  return picker
end

Picker.Symbol = function(icon, size)
  return UL.IconText(icon, size)
end
