-- Table pieces of the page kit (extends ns.PageKit): shared column math, a column header strip, a collapsible
-- group header with counter and fill, a status dot with a shape per state and the legend for the dots.
--
--   local cols = K.Columns({ { id = "name", key = "x.name", flex = 1, min = 120, sortable = true },
--                            { id = "state", key = "x.state", width = 90, align = "center", priority = 2 } })
--   local lay = cols:Layout(width)         -- lay.cols[id] = { x, w, shown, align }, lay.order = visible ids
--   K.ColumnHeader(parent, { columns = cols, sort = { get = function() return id, "asc" end, set = function(id, dir) end } })
--   K.GroupHeader(parent, { id, title|key, counter, fill, open, onToggle })
--   K.StatusDot(parent, { state = "done" })      K.StatusLegend(parent, { states = { "done", "todo", "bad" } })
local _, ns = ...
local W, Theme, L = ns.W, ns.Theme, ns.L
local K = ns.PageKit

ns.AddLocale("enUS", {
  ["kit.table.sortBy"] = "Sort by %s",
  ["kit.table.sortNone"] = "Not sorted by this column. Click to sort ascending.",
  ["kit.table.sortAsc"] = "Sorted ascending. Click to sort descending.",
  ["kit.table.sortDesc"] = "Sorted descending. Click to sort ascending.",
  ["kit.group.open"] = "expanded",
  ["kit.group.closed"] = "collapsed",
  ["kit.status.ok"] = "OK",
  ["kit.status.warn"] = "Warning",
  ["kit.status.bad"] = "Unavailable",
  ["kit.status.todo"] = "Open",
  ["kit.status.info"] = "Info",
  ["kit.status.done"] = "Done",
})
ns.AddLocale("deDE", {
  ["kit.table.sortBy"] = "Sortieren nach %s",
  ["kit.table.sortNone"] = "Nicht nach dieser Spalte sortiert. Klick sortiert aufsteigend.",
  ["kit.table.sortAsc"] = "Aufsteigend sortiert. Klick sortiert absteigend.",
  ["kit.table.sortDesc"] = "Absteigend sortiert. Klick sortiert aufsteigend.",
  ["kit.group.open"] = "aufgeklappt",
  ["kit.group.closed"] = "zugeklappt",
  ["kit.status.ok"] = "In Ordnung",
  ["kit.status.warn"] = "Warnung",
  ["kit.status.bad"] = "Nicht verfügbar",
  ["kit.status.todo"] = "Offen",
  ["kit.status.info"] = "Info",
  ["kit.status.done"] = "Erledigt",
})

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-- K.Caps comes with the card package. Until both are merged, a plain upper case keeps the header readable.
local function caps(text)
  return K.Caps and K.Caps(text) or string.upper(text)
end

local function scaled(px)
  return K.scaledHeight and K.scaledHeight(px) or px
end

-- Columns -----------------------------------------------------------------------------------------------

-- spec: list of { id, key | text, width (px, fixed) | flex (weight, default 1), min (px, default width or 40),
-- align (left, center, right), priority (higher stays longer, default 1), sortable }. opts.gap: space between
-- columns (default Theme.space.sm, read at layout time).
function K.Columns(spec, opts)
  local cols = { list = {}, gap = opts and opts.gap }
  for i, c in ipairs(spec) do
    local entry = {
      id = c.id,
      key = c.key,
      text = c.text,
      width = c.width,
      flex = c.width and nil or (c.flex or 1),
      align = c.align or "left",
      priority = c.priority or 1,
      sortable = c.sortable == true,
      index = i,
    }
    entry.min = c.min or c.width or 40
    cols.list[i] = entry
  end

  -- Columns of the lowest priority drop first (the right-most of equal ones) until the rest fits at its
  -- minimum widths; the last column always stays. Flex columns share what the fixed ones leave, by weight.
  function cols:Layout(width)
    local list = self.list
    local gap = self.gap or Theme.space.sm
    width = max(1, floor(width))
    local shown, count = {}, #list
    for i = 1, count do
      shown[i] = true
    end
    while count > 1 do
      local total = gap * (count - 1)
      for i, c in ipairs(list) do
        total = total + (shown[i] and c.min or 0)
      end
      if total <= width then
        break
      end
      local victim
      for i, c in ipairs(list) do
        if shown[i] and (not victim or c.priority <= list[victim].priority) then
          victim = i
        end
      end
      shown[victim] = false
      count = count - 1
    end

    local w, free, open = {}, width - gap * max(0, count - 1), {}
    for i, c in ipairs(list) do
      if shown[i] then
        if c.width then
          w[i] = min(c.width, width)
          free = free - w[i]
        else
          open[#open + 1] = i
        end
      end
    end
    while #open > 0 do
      local weight = 0
      for _, i in ipairs(open) do
        weight = weight + list[i].flex
      end
      local clamped, rest = false, {}
      for _, i in ipairs(open) do
        if free * list[i].flex / weight < list[i].min then
          w[i] = list[i].min
          free = free - w[i]
          clamped = true
        else
          rest[#rest + 1] = i
        end
      end
      if not clamped then
        local given = 0
        for n, i in ipairs(rest) do
          w[i] = n == #rest and max(0, free - given) or floor(free * list[i].flex / weight)
          given = given + w[i]
        end
        break
      end
      open = rest
    end

    local out = { width = width, cols = {}, order = {} }
    local x = 0
    for i, c in ipairs(list) do
      if shown[i] then
        out.cols[c.id] = { x = x, w = w[i], shown = true, align = c.align }
        out.order[#out.order + 1] = c.id
        x = x + w[i] + gap
      else
        out.cols[c.id] = { x = 0, w = 0, shown = false, align = c.align }
      end
    end
    out.used = max(0, x - gap)
    return out
  end

  return cols
end

-- Column header ----------------------------------------------------------------------------------------

local HEADER_H, SORT_SIDE = 24, 24

local function sortState(sort, id)
  local current, dir = sort.get()
  if current ~= id then
    return "none"
  end
  return dir == "desc" and "desc" or "asc"
end

local function columnTitle(c)
  return c.key and L[c.key] or c.text or ""
end

-- opts: columns (K.Columns), sort = { get() -> id, dir ("asc" | "desc"); set(id, dir) } for columns with
-- sortable = true. A sortable column carries a ghost icon button that Tab reaches and Enter or Space presses.
-- h:Layout(width) (also fgGridLayout) places the titles with the same column math as the rows and answers the
-- height. h:Refresh() repaints the sort icons.
function K.ColumnHeader(parent, opts)
  local h = CreateFrame("Frame", nil, parent)
  h.columns, h.sort, h.cells = opts.columns, opts.sort, {}
  W.Fill(h, "surface2")
  local line = h:CreateTexture(nil, "BORDER")
  line:SetPoint("BOTTOMLEFT")
  line:SetPoint("BOTTOMRIGHT")
  line:SetHeight(1)
  ns.Bind(h, function()
    line:SetColorTexture(Theme.fillColor("line"))
  end)

  for _, c in ipairs(h.columns.list) do
    local cell = CreateFrame("Frame", nil, h)
    cell:EnableMouse(true)
    cell.column = c
    cell.label = W.Text(cell, { role = "small", color = "textSecondary", justify = c.align == "right" and "RIGHT" or c.align == "center" and "CENTER" or "LEFT" })
    cell.label:SetPoint("LEFT", cell, "LEFT", 0, 0)
    cell.label:SetWordWrap(false)
    -- The text is cased by the helper, so it is refreshed on a language change by hand.
    ns.Bind(cell, function()
      local text = columnTitle(c)
      cell.title = text
      cell.label.fgText, cell.label.fgKey = caps(text), nil
      cell.label:SetText(cell.label.fgText)
    end)
    W.TipWhenCut(cell, cell.label)
    if c.sortable and h.sort then
      local button
      button = W.Action(cell, {
        icon = "sort-up",
        variant = "ghost",
        size = SORT_SIDE,
        manual = true,
        onClick = function()
          local state = sortState(h.sort, c.id)
          h.sort.set(c.id, state == "asc" and "desc" or "asc")
          h:Refresh()
        end,
      })
      local function tip()
        local state = sortState(h.sort, c.id)
        return string.format(L["kit.table.sortBy"], cell.title or ""), L["kit.table.sort" .. state:gsub("^%l", string.upper)]
      end
      button.fgName = function()
        local title, state = tip()
        return title .. ". " .. state
      end
      local function showTip()
        local title, state = tip()
        ns.ShowTooltip(button, title, state)
      end
      button:HookScript("OnEnter", showTip)
      button:HookScript("OnLeave", ns.HideTooltip)
      button.fgOnFocus, button.fgOnBlur = showTip, ns.HideTooltip
      cell.sortButton = button
    end
    h.cells[c.id] = cell
  end

  function h:Refresh()
    for id, cell in pairs(self.cells) do
      local button = cell.sortButton
      if button then
        local state = sortState(self.sort, id)
        button:SetIcon(state == "desc" and "sort-down" or "sort-up")
        button:SetAlpha(state == "none" and 0.6 or 1)
      end
    end
  end

  function h:Layout(width)
    local lay = self.columns:Layout(width)
    local height = scaled(HEADER_H)
    for id, cell in pairs(self.cells) do
      local slot = lay.cols[id]
      cell:SetShown(slot.shown)
      if slot.shown then
        local side = cell.sortButton and SORT_SIDE or 0
        cell.label:SetWidth(min(max(1, slot.w - side), max(1, ceil(cell.label:GetStringWidth()))))
        height = max(height, ceil(cell.label:GetStringHeight()) + 8, side)
      end
    end
    for id, cell in pairs(self.cells) do
      local slot = lay.cols[id]
      if slot.shown then
        local button = cell.sortButton
        local side = button and SORT_SIDE or 0
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", self, "LEFT", slot.x, 0)
        cell:SetSize(slot.w, height)
        cell.label:ClearAllPoints()
        if slot.align == "right" then
          cell.label:SetPoint("RIGHT", cell, "RIGHT", -side, 0)
        elseif slot.align == "center" then
          cell.label:SetPoint("CENTER", cell, "CENTER", -side / 2, 0)
        else
          cell.label:SetPoint("LEFT", cell, "LEFT", 0, 0)
        end
        if button then
          button:ClearAllPoints()
          if slot.align == "right" then
            button:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
          else
            button:SetPoint("LEFT", cell.label, "RIGHT", 0, 0)
          end
        end
      end
    end
    self.layout = lay
    self:SetHeight(height)
    return height
  end
  h.fgGridLayout = h.Layout

  h:Refresh()
  return h
end

-- Group header --------------------------------------------------------------------------------------------

local GROUP_H, LABEL_LEFT, PAD, TEXT_GAP, LINES_PAD, FILL_H = 28, 26, 8, 8, 6, 3

local function openStore()
  local char = ns.charDB
  if not char then
    return nil
  end
  if type(char.settingsMore) ~= "table" then
    char.settingsMore = {}
  end
  return char.settingsMore
end

-- The group header is the button itself: one Tab stop, Enter or Space toggles, Right opens, Left closes (the
-- contract of W.Accordion). The owner shows and hides the rows below it in onToggle(open).
-- opts / h:Set(opts): id (persists the open state in the character store, closed or open), title | key,
-- counter (right text such as "0 / 16"), fill (0..1 progress strip at the bottom, nil = none), open (start
-- state without a stored one, default true), onToggle(open).
-- h:SetOpen(open, remember), h:Toggle(), h:IsOpen(), h:SetCounter(text), h:SetFill(f), h:SetTitle(text),
-- h:fgGridLayout(width) -> height (also fgLayout for pooled rows).
function K.GroupHeader(parent, opts)
  local h = CreateFrame("Button", nil, parent)
  h:SetHeight(scaled(GROUP_H))
  W.Fill(h, "surface2")
  h.hover = h:CreateTexture(nil, "BORDER")
  h.hover:SetAllPoints()
  h.hover:Hide()
  h.track = h:CreateTexture(nil, "ARTWORK")
  h.track:SetPoint("BOTTOMLEFT")
  h.track:SetPoint("BOTTOMRIGHT")
  h.track:SetHeight(FILL_H)
  h.bar = h:CreateTexture(nil, "OVERLAY")
  h.bar:SetPoint("BOTTOMLEFT")
  h.bar:SetHeight(FILL_H)
  h.chevron = W.Glyph(h, "chevron-right", 12, "textSecondary")
  h.chevron:SetPoint("LEFT", 8, 0)
  h.label = W.Text(h, { role = "ui", color = "text", wrap = true })
  h.counter = W.Text(h, { role = "small", color = "textSecondary" })
  ns.Bind(h, function()
    h.hover:SetColorTexture(Theme.fillColor("hover"))
    h.track:SetColorTexture(Theme.fillColor("lineStrong"))
    h.bar:SetColorTexture(Theme.color("accent2"))
  end)

  local function paint()
    h.chevron:SetIcon(h.fgOpen and "chevron-down" or "chevron-right")
  end

  function h:SetTitle(text)
    self.label.fgKey, self.label.fgText = nil, text
    self.label:SetText(text or "")
  end

  function h:SetCounter(text)
    self.counter.fgText = text
    self.counter:SetText(text or "")
    self.counter:SetShown(text ~= nil and text ~= "")
  end

  function h:SetFill(fraction)
    self.fill = fraction and max(0, min(1, fraction)) or nil
    self.track:SetShown(self.fill ~= nil)
    self.bar:SetShown(self.fill ~= nil and self.fill > 0)
    if self.fgWidth and self.fill then
      self.bar:SetWidth(max(1, floor(self.fgWidth * self.fill)))
    end
  end

  function h:IsOpen()
    return self.fgOpen == true
  end

  -- remember = false keeps the state out of the store.
  function h:SetOpen(open, remember)
    open = open == true
    if self.fgOpen == open then
      return
    end
    self.fgOpen = open
    local saved = openStore()
    if saved and remember ~= false and self.groupId then
      saved[self.groupId] = open
    end
    paint()
    if self.onToggle then
      self.onToggle(open)
    end
  end

  function h:Toggle()
    self:SetOpen(not self.fgOpen)
  end

  -- Sets or replaces everything (pooled headers are reused for another group).
  function h:Set(o)
    o = o or {}
    self.onToggle = nil
    self.groupId = o.id and ("group." .. o.id) or nil
    if o.key then
      self.label.fgKey, self.label.fgText = o.key, nil
      self.label:SetText(L[o.key])
    else
      self:SetTitle(o.title)
    end
    self:SetCounter(o.counter)
    local saved = openStore()
    local stored = saved and self.groupId and saved[self.groupId]
    if stored == nil then
      stored = o.open ~= false
    end
    self.fgOpen = stored == true
    paint()
    self:SetFill(o.fill)
    self.onToggle = o.onToggle
  end

  h:SetScript("OnClick", function()
    h:Toggle()
  end)
  h:SetScript("OnEnter", function()
    h.hover:Show()
  end)
  h:SetScript("OnLeave", function()
    h.hover:Hide()
  end)
  ns.Focus.register(h, function()
    h:Toggle()
  end)
  function h:fgArrow(step)
    self:SetOpen(step > 0)
  end
  -- Name and state as text for the screen reader: the chevron alone would be a shape cue only.
  function h.fgName()
    return h.label:GetText()
  end
  function h.fgDescription()
    return L[h.fgOpen and "kit.group.open" or "kit.group.closed"]
  end

  -- Title and counter share a row while both fit. A narrow header or a large text size puts the counter under
  -- the title, so the two never overlap.
  function h:fgGridLayout(width)
    self.fgWidth = width
    local base = scaled(GROUP_H)
    local counterW = self.counter:IsShown() and ceil(self.counter:GetStringWidth()) or 0
    self.label:SetWidth(0)
    self.label:ClearAllPoints()
    self.counter:ClearAllPoints()
    local height = base
    local need = LABEL_LEFT + ceil(self.label:GetStringWidth()) + (counterW > 0 and TEXT_GAP + counterW or 0) + PAD
    if need <= width then
      self.label:SetPoint("LEFT", self.chevron, "RIGHT", 6, 0)
      self.counter:SetPoint("RIGHT", -PAD, 0)
    else
      local labelH = W.FitLabel(self.label, width - LABEL_LEFT - PAD)
      self.label:SetPoint("TOPLEFT", LABEL_LEFT, -LINES_PAD)
      local counterH = 0
      if counterW > 0 then
        self.counter:SetPoint("TOPLEFT", self.label, "BOTTOMLEFT", 0, -2)
        counterH = ceil(self.counter:GetStringHeight()) + 2
      end
      height = max(base, labelH + counterH + 2 * LINES_PAD)
    end
    self:SetHeight(height)
    if self.fill and self.fill > 0 then
      self.bar:SetWidth(max(1, floor(width * self.fill)))
    end
    return height
  end
  h.fgLayout = h.fgGridLayout

  h:Set(opts)
  return h
end

-- Status dot ------------------------------------------------------------------------------------------------

local DOT = 10
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- Fallbacks when the theme has no Theme.status table (token names that exist in every theme).
local STATE_TOKEN = { ok = "success", warn = "warning", bad = "danger", todo = "textMuted", info = "info", done = "accent2" }
-- Shape per state, so the color is never the only cue: filled disc = done, ring = open, dash = unavailable.
local STATE_SHAPE = { ok = "filled", done = "filled", warn = "ring", info = "ring", todo = "ring", bad = "dash" }

local function stateToken(state)
  local status = Theme.status
  return status and status[state] or STATE_TOKEN[state] or "textMuted"
end

local function stateWord(state)
  return L["kit.status." .. tostring(state)]
end

-- opts: state (ok, warn, bad, todo, info, done), shape (filled, ring, dash: overrides the state's shape),
-- word (literal tooltip text instead of the state word), hole (token behind a ring, default surface).
-- d:SetState(state, word, shape), d.state, d.shape.
function K.StatusDot(parent, opts)
  opts = opts or {}
  local d = CreateFrame("Frame", nil, parent)
  d:SetSize(DOT, DOT)
  d:EnableMouse(true)
  d.disc = d:CreateTexture(nil, "ARTWORK")
  d.disc:SetAllPoints()
  d.disc:SetTexture(DISC)
  d.hole = d:CreateTexture(nil, "OVERLAY")
  d.hole:SetPoint("TOPLEFT", 2, -2)
  d.hole:SetPoint("BOTTOMRIGHT", -2, 2)
  d.hole:SetTexture(DISC)
  d.dash = d:CreateTexture(nil, "ARTWORK")
  d.dash:SetPoint("LEFT")
  d.dash:SetPoint("RIGHT")
  d.dash:SetHeight(3)

  local function paint()
    local token = stateToken(d.state)
    local shape = d.shape
    d.disc:SetShown(shape ~= "dash")
    d.hole:SetShown(shape == "ring")
    d.dash:SetShown(shape == "dash")
    d.disc:SetVertexColor(Theme.color(token))
    d.dash:SetColorTexture(Theme.color(token))
    d.hole:SetVertexColor(Theme.color(opts.hole or "surface"))
  end
  ns.Bind(d, paint)

  function d:SetState(state, word, shape)
    self.state = state
    self.shape = shape or opts.shape or STATE_SHAPE[state] or "ring"
    self.word = word or opts.word
    paint()
  end

  d:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, self.word or stateWord(self.state))
  end)
  d:SetScript("OnLeave", ns.HideTooltip)
  function d.fgName()
    return d.word or stateWord(d.state)
  end
  d:SetState(opts.state, opts.word)
  return d
end

-- Status legend ---------------------------------------------------------------------------------------------

local LEGEND_GAP = 4

-- opts: states = list of a state name ("done") or { state, key | text, shape } to name it differently.
-- l:SetStates(list), l:fgGridLayout(width) -> height. The dots wrap to rows, each with its word.
function K.StatusLegend(parent, opts)
  local l = CreateFrame("Frame", nil, parent)
  l.items = {}

  function l:SetStates(states)
    for i, entry in ipairs(states or {}) do
      local spec = type(entry) == "table" and entry or { state = entry }
      local item = self.items[i]
      if not item then
        item = { dot = K.StatusDot(self, {}), text = W.Text(self, { role = "small", color = "textSecondary" }) }
        item.dot:SetPoint("TOPLEFT", self, "TOPLEFT")
        item.text:SetPoint("TOPLEFT", item.dot, "TOPRIGHT", LEGEND_GAP, 0)
        self.items[i] = item
      end
      local key = spec.key or (spec.text == nil and ("kit.status." .. tostring(spec.state))) or nil
      item.text.fgKey, item.text.fgText = key, spec.text
      item.text:SetText(key and L[key] or spec.text or "")
      item.dot:SetState(spec.state, key and L[key] or spec.text, spec.shape)
      item.dot:Show()
      item.text:Show()
    end
    for i = #(states or {}) + 1, #self.items do
      self.items[i].dot:Hide()
      self.items[i].text:Hide()
    end
    self.count = #(states or {})
  end

  function l:fgGridLayout(width)
    local gap = Theme.space.md
    local x, y, rowH = 0, 0, 0
    for i = 1, self.count or 0 do
      local item = self.items[i]
      local textH = ceil(item.text:GetStringHeight())
      local cell = max(DOT, textH)
      local textW = min(ceil(item.text:GetStringWidth()), max(1, width - DOT - LEGEND_GAP))
      local need = DOT + LEGEND_GAP + textW
      if x > 0 and x + need > width then
        x, y = 0, y + rowH + LEGEND_GAP
        rowH = 0
      end
      item.text:SetWidth(textW)
      item.dot:ClearAllPoints()
      item.dot:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(y + floor((cell - DOT) / 2)))
      item.text:ClearAllPoints()
      item.text:SetPoint("TOPLEFT", self, "TOPLEFT", x + DOT + LEGEND_GAP, -(y + floor((cell - textH) / 2)))
      x = x + need + gap
      rowH = max(rowH, cell)
    end
    local height = (self.count or 0) > 0 and (y + rowH) or 0
    self:SetHeight(height)
    return height
  end

  l:SetStates(opts and opts.states)
  return l
end
