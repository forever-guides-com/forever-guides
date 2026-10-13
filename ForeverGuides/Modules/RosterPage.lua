-- Character overview page: a grid with one column per character. The label column on the
-- left and the header line on top stay put while the body scrolls in both directions.
-- Only the visible cells exist (pooled frames); the data comes from RosterView.lua.
local _, ns = ...
local W, L, Theme, U, K = ns.W, ns.L, ns.Theme, ns.U, ns.PageKit
local V, Roster, Panels = ns.RosterView, ns.CharRoster, ns.RosterPanels

ns.AddLocale("enUS", {
  ["page.chars"] = "Characters",
  ["chars.sort"] = "Sort",
  ["chars.sort.recent"] = "Recent",
  ["chars.sort.name"] = "Name",
  ["chars.sort.class"] = "Class",
  ["chars.sort.level"] = "Level",
  ["chars.sort.ilvl"] = "Item level",
  ["chars.sort.gold"] = "Gold",
  ["chars.sort.custom"] = "Custom",
  ["chars.rows"] = "Rows",
  ["chars.rows.all"] = "All on",
  ["chars.rows.none"] = "All off",
  ["chars.hint"] = "Drag names to sort. Wheel scrolls, Shift+wheel sideways",
  ["chars.hide"] = "Hide",
  ["chars.move.left"] = "Move left",
  ["chars.move.right"] = "Move right",
  ["chars.empty"] = "No characters. Log in with each once.",
  ["chars.off"] = "List is off. Switch it on in the settings.",
})

ns.AddLocale("deDE", {
  ["page.chars"] = "Charaktere",
  ["chars.sort"] = "Sortierung",
  ["chars.sort.recent"] = "Zuletzt",
  ["chars.sort.name"] = "Name",
  ["chars.sort.class"] = "Klasse",
  ["chars.sort.level"] = "Stufe",
  ["chars.sort.ilvl"] = "Itemlevel",
  ["chars.sort.gold"] = "Gold",
  ["chars.sort.custom"] = "Eigene",
  ["chars.rows"] = "Zeilen",
  ["chars.rows.all"] = "Alle an",
  ["chars.rows.none"] = "Alle aus",
  ["chars.hint"] = "Namen ziehen sortiert. Rad scrollt, Umschalt+Rad seitlich",
  ["chars.hide"] = "Ausblenden",
  ["chars.move.left"] = "Nach links",
  ["chars.move.right"] = "Nach rechts",
  ["chars.empty"] = "Keine Charaktere. Jeden einmal anmelden.",
  ["chars.off"] = "Liste aus. Einschalten in den Einstellungen.",
})

local LABEL_W, COL_W = 150, 130
local LINE_H = 15
local SB = 10
local BAR_H = 50
local BAR_H_WRAPPED = 78
local SORT_W = 170
local PANEL_W = 250
local PANEL_ROW = 24
local BTN_GAP = 6
local CTRL = 18
local CTRL_ROOM = 3 * CTRL + 10
local DRAG_EDGE = 28
local DRAG_SPEED = 450
local WHEEL_X = 60
local REDRAW_BUCKET = 2
local KEY_STRIDE = 1024
local SORTS = { "recent", "name", "class", "level", "ilvl", "gold", "custom" }

-- Frames, pooled per canvas. A pooled frame is hidden when it scrolls out and reused.
local function newPool(parent, create)
  local pool = { active = {}, free = {}, all = {} }
  function pool:Get(key)
    local f = self.active[key]
    if f then
      return f, false
    end
    f = table.remove(self.free)
    if not f then
      f = create(parent)
      self.all[#self.all + 1] = f
    end
    self.active[key] = f
    f:Show()
    return f, true
  end
  function pool:Trim(keep)
    for key, f in pairs(self.active) do
      if not keep(key) then
        self.active[key] = nil
        f:Hide()
        self.free[#self.free + 1] = f
      end
    end
  end
  -- Releases everything and lets go of the icon textures.
  function pool:Clear()
    self:Trim(function()
      return false
    end)
    for _, f in ipairs(self.all) do
      if f.icon then
        f.icon:SetTexture(nil)
      end
    end
  end
  return pool
end

-- Horizontal scrollbar, the counterpart of W.Scrollbar.
local function hScrollbar(parent, onScroll)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(6)
  bar:SetPoint("BOTTOMLEFT", 2, 2)
  bar:SetPoint("BOTTOMRIGHT", -2, 2)
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  thumb:SetHeight(6)
  ns.Bind(thumb, function(t)
    t:SetColorTexture(Theme.color("accentDim", 0.9))
  end)
  function bar:Update(visibleFrac, pos)
    if visibleFrac >= 1 then
      bar:Hide()
      return
    end
    bar:Show()
    local w = bar:GetWidth()
    local tw = math.max(20, w * visibleFrac)
    thumb:SetWidth(tw)
    thumb:ClearAllPoints()
    thumb:SetPoint("LEFT", bar, "LEFT", (w - tw) * pos, 0)
  end
  bar:EnableMouse(true)
  local function fracAtCursor(self)
    local cx = GetCursorPosition()
    return U.clamp((cx / self:GetEffectiveScale() - self:GetLeft()) / math.max(1, self:GetWidth()), 0, 1)
  end
  bar:SetScript("OnMouseDown", function(self)
    onScroll(fracAtCursor(self))
    self:SetScript("OnUpdate", function(bar2)
      if not IsMouseButtonDown("LeftButton") then
        bar2:SetScript("OnUpdate", nil)
        return
      end
      onScroll(fracAtCursor(bar2))
    end)
  end)
  bar:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  return bar
end

-- First and last index of the items of `step` pixels that show in [first, first + size).
local function visibleRange(first, size, step, count)
  local a = math.floor(first / step) + 1
  local b = math.min(count, math.ceil((first + size) / step))
  return a, b
end

local function paintBackground(tex, row, current, index)
  if row.kind == "section" then
    tex:SetColorTexture(Theme.color("surface3", 1))
  elseif current then
    tex:SetColorTexture(Theme.color("accent", 0.12))
  elseif index % 2 == 0 then
    tex:SetColorTexture(1, 1, 1, 0.04)
  else
    tex:SetColorTexture(0, 0, 0, 0)
  end
end

local function build(container)
  local S = {
    hiddenCount = 0,
    chars = {},
    rows = {},
    header = nil,
    ctx = nil,
    sx = 0,
    sy = 0,
    maxX = 0,
    maxY = 0,
    rowH = 22,
    tops = {},
    heights = {},
    total = 0,
    headH = 0,
    dirty = false,
  }
  local view = { state = S }
  local render, openNote, openAdd

  -- Toolbar ---------------------------------------------------------------------------
  local bar = CreateFrame("Frame", nil, container)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  bar:SetHeight(BAR_H)

  local sortOptions = {}
  for _, mode in ipairs(SORTS) do
    sortOptions[#sortOptions + 1] = { value = mode, key = "chars.sort." .. mode }
  end
  local dropdown = W.Dropdown(bar, {
    key = "chars.sort",
    options = sortOptions,
    width = SORT_W,
    get = Roster.SortMode,
    set = function(mode)
      Roster.SetSortMode(mode)
      render()
    end,
  })
  dropdown:SetWidth(SORT_W)
  dropdown:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -2)

  local rowsButton = W.Button(bar, { key = "chars.rows", width = 80, height = 24 })
  local todosButton = W.Button(bar, { key = "chars.todos", width = 80, height = 24 })
  local hiddenButton = W.Button(bar, { text = "", width = 110, height = 24 })

  local hint = W.Text(bar, { key = "chars.hint", role = "micro", color = "textMuted" })
  hint:SetPoint("RIGHT", bar, "RIGHT", -8, 0)

  -- The buttons sit next to the sort box, on a second line when the window is too narrow.
  -- The hint only shows when it has room and so never runs into a button.
  local fitPanels
  local function layoutBar()
    local buttons = { rowsButton, todosButton }
    if S.hiddenCount > 0 then
      buttons[#buttons + 1] = hiddenButton
    end
    hiddenButton:SetShown(S.hiddenCount > 0)
    local need = 4 + SORT_W + 10
    for _, b in ipairs(buttons) do
      need = need + b:GetWidth() + BTN_GAP
    end
    local w = bar:GetWidth()
    local wrapped = w > 0 and need > w
    local previous
    for _, b in ipairs(buttons) do
      b:ClearAllPoints()
      if previous then
        b:SetPoint("LEFT", previous, "RIGHT", BTN_GAP, 0)
      elseif wrapped then
        b:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -BAR_H)
      else
        b:SetPoint("TOPLEFT", dropdown, "TOPRIGHT", 10, -18)
      end
      previous = b
    end
    hint:ClearAllPoints()
    hint:SetPoint("LEFT", previous, "RIGHT", 12, 0)
    hint:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    hint:SetShown(not wrapped and w >= need + 240)
    local height = wrapped and BAR_H_WRAPPED or BAR_H
    if bar:GetHeight() ~= height then
      bar:SetHeight(height)
    end
    if fitPanels then
      fitPanels()
    end
  end
  bar:HookScript("OnSizeChanged", layoutBar)

  local empty = W.Text(container, { key = "chars.empty", role = "text", color = "textSecondary", wrap = true })
  empty:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 8, -8)
  empty:SetPoint("RIGHT", container, "RIGHT", -8, 0)

  -- Grid ------------------------------------------------------------------------------
  local grid = CreateFrame("Frame", nil, container)
  grid:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
  grid:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
  local base = container:GetFrameLevel()

  local function viewport(level)
    local f = CreateFrame("Frame", nil, grid)
    f:SetClipsChildren(true)
    f:SetFrameLevel(base + level)
    f.fgClip = true
    return f
  end
  local body = viewport(2)
  -- The sticky parts sit above the body, so a cell that scrolled half under them never takes the mouse.
  local labelView, headView = viewport(6), viewport(6)
  local corner = CreateFrame("Frame", nil, grid)
  corner:SetFrameLevel(base + 6)
  W.Fill(corner, "surface2", 1)
  local vhost, hhost = CreateFrame("Frame", nil, grid), CreateFrame("Frame", nil, grid)
  for _, host in ipairs({ vhost, hhost }) do
    host:SetFrameLevel(base + 6)
    local track = host:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.06)
  end
  local bodyCanvas = CreateFrame("Frame", nil, body)
  local labelCanvas = CreateFrame("Frame", nil, labelView)
  local headCanvas = CreateFrame("Frame", nil, headView)

  local anchoredHead
  local function anchor()
    local hh = S.headH
    if anchoredHead == hh then
      return
    end
    anchoredHead = hh
    corner:ClearAllPoints()
    corner:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, 0)
    corner:SetSize(LABEL_W, math.max(hh, 1))
    corner:SetShown(hh > 0)
    headView:ClearAllPoints()
    headView:SetPoint("TOPLEFT", grid, "TOPLEFT", LABEL_W, 0)
    headView:SetPoint("TOPRIGHT", grid, "TOPRIGHT", -SB, 0)
    headView:SetHeight(math.max(hh, 1))
    headView:SetShown(hh > 0)
    labelView:ClearAllPoints()
    labelView:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -hh)
    labelView:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", 0, SB)
    labelView:SetWidth(LABEL_W)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", grid, "TOPLEFT", LABEL_W, -hh)
    body:SetPoint("BOTTOMRIGHT", grid, "BOTTOMRIGHT", -SB, SB)
    vhost:ClearAllPoints()
    vhost:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 0, -hh)
    vhost:SetPoint("BOTTOMRIGHT", grid, "BOTTOMRIGHT", 0, SB)
    vhost:SetWidth(SB)
    hhost:ClearAllPoints()
    hhost:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", LABEL_W, 0)
    hhost:SetPoint("BOTTOMRIGHT", grid, "BOTTOMRIGHT", -SB, 0)
    hhost:SetHeight(SB)
  end

  -- Cells -----------------------------------------------------------------------------
  local function showTip(self)
    local title, text = V.Tip(self.fgRow, self.fgChar, S.ctx)
    if title then
      ns.ShowTooltip(self, title, text)
    end
  end

  local function newBodyCell(parent, interactive)
    local f = CreateFrame(interactive and "Button" or "Frame", nil, parent)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(14, 14)
    f.icon:SetPoint("LEFT", f, "LEFT", 6, 0)
    f.icon:Hide()
    f.text = W.Text(f, { role = "ui", justify = "CENTER" })
    f:EnableMouse(true)
    f:SetScript("OnEnter", showTip)
    f:SetScript("OnLeave", ns.HideTooltip)
    return f
  end

  local function newTextCell(parent, kind)
    local f = CreateFrame(kind or "Frame", nil, parent)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.text = W.Text(f, { role = "ui" })
    return f
  end

  local cellPool = newPool(bodyCanvas, function(parent)
    return newBodyCell(parent, false)
  end)
  local todoPool = newPool(bodyCanvas, function(parent)
    local f = newBodyCell(parent, true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript(
      "OnClick",
      ns.Wrap("roster-todo", function(self, button)
        if button == "RightButton" or ns.Keys.Matches("rosterNote") then
          openNote(self)
        elseif V.Activate(self.fgRow, self.fgChar) then
          view.PaintBody(self)
          showTip(self)
        end
      end)
    )
    -- Enter ticks, Shift+Enter opens the note (the keyboard way to the right click).
    ns.Focus.register(f, function(self)
      if IsShiftKeyDown() then
        openNote(self)
      else
        self:Click()
      end
    end)
    -- Tab onto a cell that is scrolled out shows it first.
    f.fgScrollIntoView = function(self)
      view.Reveal(self.fgR, self.fgC)
    end
    return f
  end)
  local labelPool = newPool(labelCanvas, newTextCell)
  -- The "add own todo" label is a button of its own, so the other labels stay out of the Tab order.
  local addPool = newPool(labelCanvas, function(parent)
    local f = newTextCell(parent, "Button")
    f:SetScript(
      "OnClick",
      ns.Wrap("roster-add", function(self)
        openAdd(self)
      end)
    )
    f:SetScript("OnEnter", function(self)
      self.bg:SetColorTexture(1, 1, 1, 0.1)
    end)
    f:SetScript("OnLeave", function(self)
      paintBackground(self.bg, self.fgRow, false, self.fgR)
    end)
    ns.Focus.register(f, function(self)
      self:Click()
    end)
    f.fgScrollIntoView = function(self)
      view.RevealRow(self.fgR)
    end
    return f
  end)
  -- Header cells: drag to sort, small buttons (move left, move right, hide) that show on
  -- hover and on keyboard focus. They stay shown at alpha 0 otherwise, so Tab reaches them.
  local beginDrag, endDrag, moveBy, hideChar
  local refreshControls

  local function focusedHere(f)
    local cur = ns.Focus.current
    return cur ~= nil and (cur == f.left or cur == f.right or cur == f.hide)
  end

  local function watchFocus(f)
    refreshControls(f)
  end

  function refreshControls(f)
    local on = (f.fgHover or focusedHere(f)) and not f.fgDragging
    if on ~= f.fgOn then
      f.fgOn = on
      for _, b in ipairs({ f.left, f.right, f.hide }) do
        b:SetAlpha(on and 1 or 0)
      end
      f.text:ClearAllPoints()
      f.text:SetPoint("LEFT", f, "LEFT", 4, 0)
      f.text:SetPoint("RIGHT", f, "RIGHT", on and -CTRL_ROOM or -4, 0)
    end
    -- Focus can leave without a message: watch until it did.
    local watching = on and not f.fgHover
    if watching ~= f.fgWatching then
      f.fgWatching = watching
      f:SetScript("OnUpdate", watching and watchFocus or nil)
    end
  end

  local function headButton(f, icon, tipKey, run)
    local b
    b = W.Action(f, {
      icon = icon,
      size = CTRL,
      tooltip = tipKey,
      onClick = function()
        run(f, b)
      end,
    })
    b:SetAlpha(0)
    b:HookScript("OnEnter", function()
      f.fgHover = true
      refreshControls(f)
    end)
    b:HookScript("OnLeave", function()
      f.fgHover = f:IsMouseOver() and true or false
      refreshControls(f)
    end)
    -- Tab onto a button shows its column and its buttons.
    b.fgScrollIntoView = function()
      view.RevealColumn(f.fgC)
      refreshControls(f)
    end
    return b
  end

  local headPool = newPool(headCanvas, function(parent)
    local f = newTextCell(parent)
    f.text:SetJustifyH("CENTER")
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnEnter", function(self)
      self.fgHover = true
      showTip(self)
      refreshControls(self)
    end)
    f:SetScript("OnLeave", function(self)
      self.fgHover = self:IsMouseOver() and true or false
      ns.HideTooltip()
      refreshControls(self)
    end)
    f:SetScript("OnDragStart", function(self)
      beginDrag(self)
    end)
    f:SetScript("OnDragStop", function()
      endDrag(true)
    end)
    f.hide = headButton(f, "eye-off", "chars.hide", function(self)
      hideChar(self.fgChar.key)
    end)
    f.hide:SetPoint("RIGHT", f, "RIGHT", -3, 0)
    f.right = headButton(f, "chevron-right", "chars.move.right", function(self, b)
      moveBy(self, 1, b)
    end)
    f.right:SetPoint("RIGHT", f.hide, "LEFT", -2, 0)
    f.left = headButton(f, "chevron-left", "chars.move.left", function(self, b)
      moveBy(self, -1, b)
    end)
    f.left:SetPoint("RIGHT", f.right, "LEFT", -2, 0)
    return f
  end)

  local function setText(f, text, color)
    f.text:SetText(text)
    W.SetColor(f.text, color)
  end

  -- Paints one body cell from its row and character (fgR, fgC are set by the caller).
  function view.PaintBody(f)
    local row, char = S.rows[f.fgR], S.chars[f.fgC]
    local cell = V.Cell(row, char, S.ctx)
    f.fgRow, f.fgChar = row, char
    paintBackground(f.bg, row, char.current, f.fgR)
    local pad = 4
    if cell.icon then
      f.icon:SetTexture(cell.icon)
      f.icon:Show()
      pad = 24
    else
      f.icon:Hide()
    end
    -- Struck text sits right of the check mark and starts at the left edge, so the line
    -- can start there too.
    if cell.strike then
      pad = 24
    end
    f.text:SetJustifyH(cell.strike and "LEFT" or "CENTER")
    f.text:ClearAllPoints()
    f.text:SetPoint("LEFT", f, "LEFT", pad, 0)
    f.text:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    setText(f, V.Format(cell), cell.color or "text")
    -- `plain` is one shorter form, or a list of them from long to short.
    for _, alt in ipairs(type(cell.plain) == "table" and cell.plain or { cell.plain }) do
      if f.text:GetStringWidth() > COL_W - pad - 4 then
        f.text:SetText(alt)
      end
    end
    if cell.check then
      f.mark = f.mark or W.CheckMark(f, 14)
      f.mark:ClearAllPoints()
      if cell.strike then
        f.mark:SetPoint("LEFT", f, "LEFT", 6, 0)
      else
        f.mark:SetPoint("CENTER", f, "CENTER", 0, 0)
      end
      f.mark:Tint(Theme.color(cell.tone or "success"))
      f.mark:Show()
    elseif f.mark then
      f.mark:Hide()
    end
    if cell.strike then
      if not f.line then
        f.line = f:CreateTexture(nil, "OVERLAY")
        f.line:SetHeight(1)
      end
      f.line:ClearAllPoints()
      f.line:SetPoint("LEFT", f.text, "LEFT", 0, 0)
      f.line:SetWidth(math.max(1, math.ceil(f.text:GetStringWidth())))
      f.line:SetColorTexture(Theme.color(cell.color or "text"))
      f.line:Show()
    elseif f.line then
      f.line:Hide()
    end
    -- A small square in the corner: the cell has a note (the tooltip shows it).
    if cell.note then
      if not f.noteMark then
        f.noteMark = f:CreateTexture(nil, "OVERLAY")
        f.noteMark:SetSize(6, 6)
        f.noteMark:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
      end
      f.noteMark:SetColorTexture(Theme.color("accent2"))
      f.noteMark:Show()
    elseif f.noteMark then
      f.noteMark:Hide()
    end
  end

  local LABEL_COLOR = { section = "accent2", add = "accent" }

  local function paintLabel(f, row, r)
    f.fgRow, f.fgR = row, r
    paintBackground(f.bg, row, false, r)
    f.text:ClearAllPoints()
    f.text:SetPoint("LEFT", f, "LEFT", 6, 0)
    f.text:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    setText(f, row.label, LABEL_COLOR[row.kind] or "text")
  end

  local function paintHead(f, char, c)
    f.fgRow, f.fgChar, f.fgC = S.headRow, char, c
    f.fgHover, f.fgOn, f.fgDragging = false, nil, false
    f.bg:SetColorTexture(Theme.color(char.current and "accent" or "surface2", char.current and 0.2 or 1))
    setText(f, V.Format(V.Cell(S.headRow, char, S.ctx)), "text")
    -- A button that cannot do anything is not there.
    f.left:SetShown(c > 1)
    f.right:SetShown(c < #S.chars)
    refreshControls(f)
  end

  -- First and last row that show in [first, first + size) (rows have different heights).
  local function rowRange(first, size)
    local a, b = #S.rows + 1, 0
    for r = 1, #S.rows do
      if S.tops[r] + S.heights[r] > first and S.tops[r] < first + size then
        a, b = math.min(a, r), r
      end
    end
    return math.min(a, b + 1), b
  end

  -- Scrolling -------------------------------------------------------------------------
  local function extent()
    S.maxX = math.max(0, #S.chars * COL_W - body:GetWidth())
    S.maxY = math.max(0, S.total - body:GetHeight())
    S.sx, S.sy = U.clamp(S.sx, 0, S.maxX), U.clamp(S.sy, 0, S.maxY)
  end

  local function place()
    bodyCanvas:ClearAllPoints()
    bodyCanvas:SetPoint("TOPLEFT", body, "TOPLEFT", -S.sx, S.sy)
    labelCanvas:ClearAllPoints()
    labelCanvas:SetPoint("TOPLEFT", labelView, "TOPLEFT", 0, S.sy)
    headCanvas:ClearAllPoints()
    headCanvas:SetPoint("TOPLEFT", headView, "TOPLEFT", -S.sx, 0)
  end

  local vbar, hbar
  local function updateBars()
    local ch, cw = S.total, #S.chars * COL_W
    vbar:Update(S.maxY > 0 and body:GetHeight() / ch or 1, S.maxY > 0 and S.sy / S.maxY or 0)
    hbar:Update(S.maxX > 0 and body:GetWidth() / cw or 1, S.maxX > 0 and S.sx / S.maxX or 0)
  end

  -- Creates the cells that came into view, releases the ones that left it.
  local function fill()
    local c1, c2 = visibleRange(S.sx, body:GetWidth(), COL_W, #S.chars)
    local r1, r2 = rowRange(S.sy, body:GetHeight())
    headPool:Trim(function(c)
      return S.header ~= nil and c >= c1 and c <= c2
    end)
    local function keepRow(r)
      return r >= r1 and r <= r2
    end
    labelPool:Trim(keepRow)
    addPool:Trim(keepRow)
    local function keepBody(key)
      local r, c = math.floor(key / KEY_STRIDE), key % KEY_STRIDE
      return r >= r1 and r <= r2 and c >= c1 and c <= c2
    end
    cellPool:Trim(keepBody)
    todoPool:Trim(keepBody)
    if S.header then
      for c = c1, c2 do
        local f, new = headPool:Get(c)
        if new then
          f:ClearAllPoints()
          f:SetPoint("TOPLEFT", headCanvas, "TOPLEFT", (c - 1) * COL_W, 0)
          f:SetSize(COL_W, S.headH)
          paintHead(f, S.chars[c], c)
        end
      end
    end
    for r = r1, r2 do
      local row = S.rows[r]
      local f, new = (row.kind == "add" and addPool or labelPool):Get(r)
      if new then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", labelCanvas, "TOPLEFT", 0, -S.tops[r])
        f:SetSize(LABEL_W, S.heights[r])
        paintLabel(f, row, r)
      end
      local pool = V.Interactive(row) and todoPool or cellPool
      for c = c1, c2 do
        local cell, isNew = pool:Get(r * KEY_STRIDE + c)
        if isNew then
          cell.fgR, cell.fgC = r, c
          cell:ClearAllPoints()
          cell:SetPoint("TOPLEFT", bodyCanvas, "TOPLEFT", (c - 1) * COL_W, -S.tops[r])
          cell:SetSize(COL_W, S.heights[r])
          view.PaintBody(cell)
        end
      end
    end
  end

  function view.ScrollTo(x, y)
    x, y = U.clamp(math.floor(x + 0.5), 0, S.maxX), U.clamp(math.floor(y + 0.5), 0, S.maxY)
    if x == S.sx and y == S.sy then
      return
    end
    S.sx, S.sy = x, y
    place()
    fill()
    updateBars()
  end

  -- Scrolls just far enough to show the cell of row r, column c.
  function view.Reveal(r, c)
    local x, y = S.sx, S.sy
    local left, top = (c - 1) * COL_W, S.tops[r]
    local bw, bh = body:GetWidth(), body:GetHeight()
    if left < x then
      x = left
    elseif left + COL_W > x + bw then
      x = left + COL_W - bw
    end
    if top < y then
      y = top
    elseif top + S.heights[r] > y + bh then
      y = top + S.heights[r] - bh
    end
    view.ScrollTo(x, y)
  end

  -- Scrolls just far enough to show row r.
  function view.RevealRow(r)
    local y, bh = S.sy, body:GetHeight()
    local top = S.tops[r]
    if top < y then
      y = top
    elseif top + S.heights[r] > y + bh then
      y = top + S.heights[r] - bh
    end
    view.ScrollTo(S.sx, y)
  end

  -- Scrolls just far enough to show column c.
  function view.RevealColumn(c)
    local x = S.sx
    local left, bw = (c - 1) * COL_W, body:GetWidth()
    if left < x then
      x = left
    elseif left + COL_W > x + bw then
      x = left + COL_W - bw
    end
    view.ScrollTo(x, S.sy)
  end

  function view.Scroll()
    return S.sx, S.sy
  end

  -- Size or content changed, the data stays.
  local function reflow()
    extent()
    bodyCanvas:SetSize(math.max(1, #S.chars * COL_W), math.max(1, S.total))
    labelCanvas:SetSize(LABEL_W, math.max(1, S.total))
    headCanvas:SetSize(math.max(1, #S.chars * COL_W), math.max(1, S.headH))
    place()
    fill()
    updateBars()
  end

  vbar = W.Scrollbar(vhost, function(frac)
    view.ScrollTo(S.sx, S.maxY * frac)
  end)
  hbar = hScrollbar(hhost, function(frac)
    view.ScrollTo(S.maxX * frac, S.sy)
  end)

  body:HookScript("OnSizeChanged", function()
    if container:IsShown() and S.ctx then
      reflow()
    end
  end)

  local function wheel(horizontalOnly)
    return function(_, delta)
      if horizontalOnly or IsShiftKeyDown() then
        view.ScrollTo(S.sx - delta * WHEEL_X, S.sy)
      else
        view.ScrollTo(S.sx, S.sy - delta * S.rowH * 3)
      end
    end
  end
  for _, f in ipairs({ body, labelView }) do
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", wheel(false))
  end
  headView:EnableMouseWheel(true)
  headView:SetScript("OnMouseWheel", wheel(true))

  -- Arrow keys scroll by a row or a column, Page keys by a screen. Returns true when handled.
  function view.OnKey(key)
    local page = math.max(S.rowH, body:GetHeight() - S.rowH)
    local dx, dy = 0, 0
    if key == "UP" then
      dy = -S.rowH
    elseif key == "DOWN" then
      dy = S.rowH
    elseif key == "LEFT" then
      dx = -COL_W
    elseif key == "RIGHT" then
      dx = COL_W
    elseif key == "PAGEUP" then
      dy = -page
    elseif key == "PAGEDOWN" then
      dy = page
    else
      return false
    end
    view.ScrollTo(S.sx + dx, S.sy + dy)
    return true
  end

  local keys = CreateFrame("Frame", nil, container)
  keys:SetPropagateKeyboardInput(true)
  keys:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then
      return
    end
    local handled = false
    if key == "ESCAPE" and view.DragState() then
      endDrag(false)
      handled = true
    elseif container:IsMouseOver() and not (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()) then
      handled = view.OnKey(key) == true
    end
    self:SetPropagateKeyboardInput(not handled)
  end)
  keys:EnableKeyboard(false)

  -- Order and visibility ----------------------------------------------------------------
  local drag = {}
  local ghost, marker

  local function useCustomOrder()
    if Roster.SortMode() ~= "custom" then
      Roster.SetSortMode("custom")
      dropdown.Refresh()
      ns.Notify(L["chars.sort"] .. ": " .. L["chars.sort.custom"], "info")
    end
  end

  -- The list is taken in the order on screen, then numbered from there.
  local function moveTo(key, to)
    if Roster.Move(key, to, Roster.SortMode()) then
      useCustomOrder()
    end
    render()
  end

  -- Keyboard focus follows the button to its new column.
  function moveBy(f, step, button)
    local key, c = f.fgChar.key, f.fgC
    local to = U.clamp(c + step, 1, #S.chars)
    if to == c then
      return
    end
    local focused = ns.Focus.current == button
    moveTo(key, to)
    for i, char in ipairs(S.chars) do
      if char.key == key then
        view.RevealColumn(i)
        local head = headPool.active[i]
        if focused and head then
          local target = step < 0 and head.left or head.right
          ns.Focus.set(target:IsShown() and target or head.hide)
        end
      end
    end
  end

  function hideChar(key)
    if Roster.Hide(key) then
      render()
    end
  end

  local function ensureGhost()
    if ghost then
      return
    end
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(COL_W, 28)
    W.Fill(ghost, "surface3", 0.92)
    W.Border(ghost, "accent", 1)
    ghost.text = W.Text(ghost, { role = "ui", justify = "CENTER" })
    ghost.text:SetPoint("LEFT", ghost, "LEFT", 4, 0)
    ghost.text:SetPoint("RIGHT", ghost, "RIGHT", -4, 0)
    ghost:Hide()
    marker = CreateFrame("Frame", nil, grid)
    marker:SetFrameLevel(base + 8)
    marker:SetWidth(3)
    W.Fill(marker, "accent", 1)
    marker:Hide()
  end

  local function placeMarker()
    local from, to = drag.from, drag.target
    if to == from then
      marker:Hide()
      return
    end
    local boundary = (to > from and to or to - 1) * COL_W - S.sx
    local x = LABEL_W + U.clamp(boundary, 0, body:GetWidth())
    marker:ClearAllPoints()
    marker:SetPoint("TOPLEFT", grid, "TOPLEFT", x - 1, 0)
    marker:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", x - 1, SB)
    marker:Show()
  end

  local function dragStep(_, elapsed)
    if not drag.key then
      return
    end
    -- The source cell can scroll out and be reused, so the release is polled too.
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
      endDrag(true)
      return
    end
    local cx, cy = GetCursorPosition()
    local x = cx / headView:GetEffectiveScale() - headView:GetLeft()
    local width = headView:GetWidth()
    local gs = ghost:GetEffectiveScale()
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / gs, cy / gs)
    if x < DRAG_EDGE then
      view.ScrollTo(S.sx - DRAG_SPEED * elapsed, S.sy)
    elseif x > width - DRAG_EDGE then
      view.ScrollTo(S.sx + DRAG_SPEED * elapsed, S.sy)
    end
    drag.target = U.clamp(math.floor((x + S.sx) / COL_W) + 1, 1, #S.chars)
    placeMarker()
  end

  function beginDrag(f)
    if #S.chars < 2 or drag.key then
      return
    end
    ensureGhost()
    ns.HideTooltip()
    f.fgDragging = true
    refreshControls(f)
    drag.key, drag.from, drag.target = f.fgChar.key, f.fgC, f.fgC
    ghost.text:SetText(V.Format(V.Cell(S.headRow, f.fgChar, S.ctx)))
    ghost:SetScale(container:GetEffectiveScale() / UIParent:GetEffectiveScale())
    ghost:Show()
    ghost:SetScript("OnUpdate", dragStep)
  end

  -- commit false drops the move (Esc, page left).
  function endDrag(commit)
    if not drag.key then
      return
    end
    local key, from, to = drag.key, drag.from, drag.target
    drag.key = nil
    ghost:SetScript("OnUpdate", nil)
    ghost:Hide()
    marker:Hide()
    for _, f in pairs(headPool.active) do
      f.fgDragging = false
      refreshControls(f)
    end
    if commit and to ~= from then
      moveTo(key, to)
    end
  end

  function view.DragState()
    return drag.key, drag.target
  end

  -- Test access: the shadow under the pointer and the insert mark.
  function view.DragParts()
    ensureGhost()
    return ghost, marker
  end

  -- Row panel -------------------------------------------------------------------------
  local panel, boxes, panelSig, hiddenPanel, todoPanel, addInput, noteInput

  -- The panels and the small input boxes that exist so far.
  local function allPanels()
    local out = {}
    for _, f in pairs({
      panel = panel,
      hiddenPanel = hiddenPanel,
      todoPanel = todoPanel,
      addInput = addInput,
      noteInput = noteInput,
    }) do
      out[#out + 1] = f
    end
    return out
  end

  function fitPanels()
    if panel then
      local avail = container:GetHeight() - bar:GetHeight() - 6
      panel:SetHeight(math.max(80, math.min(40 + #boxes * PANEL_ROW + 8, avail)))
    end
    for _, p in ipairs({ hiddenPanel, todoPanel }) do
      if p then
        p.fgFit()
      end
    end
  end

  local function setAll(on)
    for _, b in ipairs(boxes) do
      V.SetSwitch(b.fgSwitch, on)
      b:Refresh()
    end
    render()
  end

  local function buildBoxes()
    local switches = V.Switches(S.ctx)
    local ids = {}
    for i, s in ipairs(switches) do
      ids[i] = s.id .. "=" .. s.label
    end
    local sig = table.concat(ids, ",")
    if sig == panelSig then
      return
    end
    panelSig = sig
    for _, b in ipairs(boxes) do
      b:Hide()
    end
    boxes = {}
    local content = panel.scroll.content
    for i, s in ipairs(switches) do
      local b
      b = W.Checkbox(content, {
        text = s.label,
        get = function()
          return V.SwitchOn(s)
        end,
        set = function(on)
          V.SetSwitch(s, on)
          render()
        end,
      })
      b.fgSwitch = s
      local indent = (s.todo or s.sub) and 16 or 0
      b:SetPoint("TOPLEFT", content, "TOPLEFT", 6 + indent, -4 - (i - 1) * PANEL_ROW)
      b:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -4 - (i - 1) * PANEL_ROW)
      boxes[i] = b
    end
    panel.scroll:SetContentHeight(#boxes * PANEL_ROW + 8)
  end

  local function ensurePanel()
    if panel then
      return
    end
    boxes = {}
    panel = CreateFrame("Frame", nil, container)
    panel:SetFrameLevel(base + 30)
    panel:SetWidth(PANEL_W)
    panel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 4, 2)
    panel:EnableMouse(true)
    W.Fill(panel, "surface", 1)
    W.Border(panel, "accentDim", 1)
    local half = (PANEL_W - 18) / 2
    local on = W.Action(panel, {
      label = "act.all",
      icon = "check",
      tooltip = "chars.rows.all",
      width = half,
      height = 24,
      onClick = function()
        setAll(true)
      end,
    })
    on:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -6)
    local off = W.Action(panel, {
      label = "act.none",
      icon = "close",
      tooltip = "chars.rows.none",
      width = half,
      height = 24,
      onClick = function()
        setAll(false)
      end,
    })
    off:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
    panel.fgFirst = on
    panel.scroll = W.ScrollArea(panel)
    panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -36)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
    panel:Hide()
    Panels.Register(panel)
  end

  -- One panel at a time. A keyboard user lands inside the panel they opened.
  local function toggle(p, opener)
    if p:IsShown() then
      p:Hide()
      return
    end
    for _, other in ipairs(allPanels()) do
      if other ~= p then
        other:Hide()
      end
    end
    local focused = ns.Focus.current == opener
    fitPanels()
    p:Show()
    if focused then
      ns.Focus.set(p.fgFirst)
    end
  end

  function view.TogglePanel()
    ensurePanel()
    buildBoxes()
    for _, b in ipairs(boxes) do
      b:Refresh()
    end
    toggle(panel, rowsButton)
  end
  rowsButton:SetScript("OnClick", ns.Wrap("roster-rows", view.TogglePanel))

  local host = {
    container = container,
    bar = bar,
    level = base + 30,
    render = function()
      render()
    end,
  }

  function view.ToggleHidden()
    hiddenPanel = hiddenPanel or Panels.Hidden(host)
    if not hiddenPanel:IsShown() then
      hiddenPanel.Refresh()
    end
    toggle(hiddenPanel, hiddenButton)
  end
  hiddenButton:SetScript("OnClick", ns.Wrap("roster-hidden", view.ToggleHidden))

  function view.ToggleTodos()
    todoPanel = todoPanel or Panels.Todos(host)
    if not todoPanel:IsShown() then
      todoPanel.Refresh()
    end
    toggle(todoPanel, todosButton)
  end
  todosButton:SetScript("OnClick", ns.Wrap("roster-todos", view.ToggleTodos))

  function view.Panel()
    return panel
  end

  function view.HiddenPanel()
    return hiddenPanel
  end

  function view.TodoPanel()
    return todoPanel
  end

  -- Opens an input box and closes whatever else floats over the grid.
  local function openInput(input, ...)
    for _, other in ipairs(allPanels()) do
      other:Hide()
    end
    ns.HideTooltip()
    input.Open(...)
  end

  -- The "add own todo" label: a box for the name under it.
  function openAdd(label)
    addInput = addInput
      or Panels.Input(host, {
        placeholder = "chars.todo.new",
        max = ns.RosterTodos.NAME_MAX,
        onSubmit = function(text)
          return Panels.AddTodo(text, host)
        end,
      })
    openInput(addInput, label, "")
  end

  -- A todo cell: a box for its note (one per row and character).
  function openNote(cell)
    local RT = ns.RosterTodos
    noteInput = noteInput
      or Panels.Input(host, {
        placeholder = "chars.todo.note",
        max = RT.NOTE_MAX,
        onSubmit = function(text, target)
          RT.SetNote(target.key, target.id, text)
          render()
        end,
      })
    local key, id = cell.fgChar.key, cell.fgRow.def.id
    openInput(noteInput, cell, RT.Note(key, id) or "", { key = key, id = id })
  end

  function view.AddInput()
    return addInput
  end

  function view.NoteInput()
    return noteInput
  end

  function view.Boxes()
    return boxes or {}
  end

  container:HookScript("OnSizeChanged", function()
    fitPanels()
  end)

  -- Drawing ---------------------------------------------------------------------------
  function render()
    S.dirty = false
    S.ctx = V.Context()
    S.chars = Roster.List({ sort = Roster.SortMode() })
    S.hiddenCount = #Roster.ListHidden()
    local data = V.Rows(S.ctx)
    S.rows, S.header = data.rows, data.header
    S.headRow = S.header and { kind = "row", id = S.header.id, label = L[S.header.label], def = S.header } or nil
    S.rowH = K.scaledHeight(22)
    S.tops, S.heights, S.total = {}, {}, 0
    for r, row in ipairs(S.rows) do
      S.tops[r] = S.total
      S.heights[r] = S.rowH + (V.Lines(row, S.chars, S.ctx) - 1) * K.scaledHeight(LINE_H)
      S.total = S.total + S.heights[r]
    end
    S.headH = S.header and K.scaledHeight(28) or 0
    local has = #S.chars > 0
    grid:SetShown(has)
    empty:SetShown(not has)
    W.SetText(empty, Roster.Enabled() and "chars.empty" or "chars.off")
    anchor()
    W.SetText(hiddenButton.label, nil, string.format(L["chars.hidden"], S.hiddenCount))
    hiddenButton:SetWidth(math.max(110, math.ceil(hiddenButton.label:GetStringWidth()) + 24))
    layoutBar()
    if hiddenPanel and hiddenPanel:IsShown() then
      if hiddenPanel.Refresh() == 0 then
        hiddenPanel:Hide()
      end
    end
    if todoPanel and todoPanel:IsShown() then
      todoPanel.Refresh()
    end
    -- Everything is repainted: the data may have changed under the same cells.
    for _, pool in ipairs({ headPool, labelPool, addPool, cellPool, todoPool }) do
      pool:Trim(function()
        return false
      end)
    end
    reflow()
  end
  view.Render = render

  -- Gives the textures back while the page is away.
  local function release()
    for _, pool in ipairs({ headPool, labelPool, addPool, cellPool, todoPool }) do
      pool:Clear()
    end
    endDrag(false)
    for _, p in ipairs(allPanels()) do
      p:Hide()
    end
    keys:EnableKeyboard(false)
  end
  container:HookScript("OnHide", release)

  local function markDirty()
    S.dirty = true
    if container:IsShown() then
      ns.Debounce(view, REDRAW_BUCKET, function()
        if S.dirty and container:IsShown() then
          render()
        end
      end)
    end
  end
  ns.On("FG_ROSTER_CHANGED", markDirty)
  ns.On("FG_SETTING_CHANGED", function(_, path)
    if path == "rosterRows" or path == "rosterSort" or path == "rosterReset" then
      markDirty()
    end
  end)
  ns.On("FG_UI_REFRESHED", function()
    if container:IsShown() and S.ctx then
      render()
    end
  end)

  function view:Show()
    ns.RosterTodos.ApplyResets()
    keys:EnableKeyboard(true)
    dropdown.Refresh()
    render()
  end

  -- Test access.
  view.frames = {
    bar = bar,
    grid = grid,
    body = body,
    labels = labelView,
    header = headView,
    corner = corner,
    vbar = vbar,
    hbar = hbar,
    vhost = vhost,
    hhost = hhost,
    dropdown = dropdown,
    rowsButton = rowsButton,
    todosButton = todosButton,
    hiddenButton = hiddenButton,
    empty = empty,
    hint = hint,
    keys = keys,
  }
  view.pools = { head = headPool, label = labelPool, cell = cellPool, todo = todoPool, add = addPool }
  function view.CellAt(r, c)
    return cellPool.active[r * KEY_STRIDE + c] or todoPool.active[r * KEY_STRIDE + c]
  end
  function view.LabelAt(r)
    return labelPool.active[r] or addPool.active[r]
  end
  function view.HeaderAt(c)
    return headPool.active[c]
  end
  return view
end

ns.RegisterPage({
  id = "chars",
  order = 210,
  group = "character",
  title = "page.chars",
  icon = ns.ICONS.chars,
  aliases = { "chars", "charaktere", "uebersicht", "characters" },
  build = build,
})
