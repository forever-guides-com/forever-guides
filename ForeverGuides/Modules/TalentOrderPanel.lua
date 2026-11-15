-- Skill order panel of the talent editor: a collapsible box with one row per talent point (number,
-- level, icon, name, rank). A row moves by drag and drop, by its two arrow buttons or by Shift+Up and
-- Shift+Down while it has the keyboard focus. The panel only shows and reports: the editor owns the
-- order and decides whether a move is allowed (TalentOrder.MoveTo); a refused move comes back as a
-- short reason (Say). Hovering or focusing a row reports its spell id (opts.onHover), the editor
-- reports a hovered talent back through panel:Highlight.
-- Open state and the step numbers on the talents are stored per character (talentOrderUi).
local _, ns = ...
local W, L, Theme, K, TO = ns.W, ns.L, ns.Theme, ns.PageKit, ns.TalentOrder

local P = {}
ns.TalentOrderPanel = P

local HEADER_H, PAD, ROW_BASE, ICON, BUTTON = 28, 8, 40, 22, 22
P.WIDTH = 300
local ICON_DIR = "Interface\\Icons\\"

ns.AddLocale("enUS", {
  ["talents.order.title"] = "Skill order",
  ["talents.order.tip"] = "The order in which the talent points are spent. Enter or Space expands or collapses this section.",
  ["talents.order.open"] = "expanded",
  ["talents.order.closed"] = "collapsed",
  ["talents.order.hint"] = "Drag a step, use its arrow buttons or press Shift+Up and Shift+Down on a focused step.",
  ["talents.order.blocked"] = "Not possible: %s",
  ["talents.order.empty"] = "No points yet. Every point you spend adds a step here.",
  ["talents.order.level"] = "Level %d",
  ["talents.order.row"] = "Step %d, level %d, %s, rank %d of %d",
  ["talents.order.rowTip"] = "Level %d, rank %d/%d\nDrag it, use the arrow buttons or press Shift+Up and Shift+Down.",
  ["talents.order.up"] = "Move step %d up",
  ["talents.order.down"] = "Move step %d down",
  ["talents.order.first"] = "This is already the first step.",
  ["talents.order.last"] = "This is already the last step.",
  ["talents.order.numbers"] = "Step numbers on the talents",
  ["talents.order.numbersTip"] = "Shows the number of the first step on every talent in the editor. The tooltip lists all steps.",
  ["talents.order.steps"] = "Steps: %s",
})
ns.AddLocale("deDE", {
  ["talents.order.title"] = "Skillreihenfolge",
  ["talents.order.tip"] = "Die Reihenfolge, in der die Talentpunkte vergeben werden. Enter oder Leertaste klappt den Bereich auf oder zu.",
  ["talents.order.open"] = "aufgeklappt",
  ["talents.order.closed"] = "zugeklappt",
  ["talents.order.hint"] = "Schritt ziehen, die Pfeilknöpfe nutzen oder auf einem markierten Schritt Umschalt+Hoch und Umschalt+Runter drücken.",
  ["talents.order.blocked"] = "Nicht möglich: %s",
  ["talents.order.empty"] = "Noch keine Punkte. Jeder Punkt, den du vergibst, ergibt hier einen Schritt.",
  ["talents.order.level"] = "Stufe %d",
  ["talents.order.row"] = "Schritt %d, Stufe %d, %s, Rang %d von %d",
  ["talents.order.rowTip"] = "Stufe %d, Rang %d/%d\nZiehen, die Pfeilknöpfe nutzen oder Umschalt+Hoch und Umschalt+Runter drücken.",
  ["talents.order.up"] = "Schritt %d nach oben verschieben",
  ["talents.order.down"] = "Schritt %d nach unten verschieben",
  ["talents.order.first"] = "Das ist schon der erste Schritt.",
  ["talents.order.last"] = "Das ist schon der letzte Schritt.",
  ["talents.order.numbers"] = "Schrittnummern an den Talenten",
  ["talents.order.numbersTip"] = "Zeigt an jedem Talent im Editor die Nummer des ersten Schritts. Der Tooltip nennt alle Schritte.",
  ["talents.order.steps"] = "Schritte: %s",
})

-- Stored state ---------------------------------------------------------------------------------

local function ui()
  local char = ns.charDB
  if type(char) ~= "table" then
    return {}
  end
  if type(char.talentOrderUi) ~= "table" then
    char.talentOrderUi = {}
  end
  return char.talentOrderUi
end

function P.IsOpen()
  return ui().open == true
end

function P.NumbersOn()
  return ui().numbers == true
end

local function save(key, value)
  ns.Store.setChar("talentOrderUi." .. key, value)
end

-- Where a dropped row ends up: `anchor` is the row it was dropped before (or behind, when `after`).
-- Returns the place the step takes in the list once it is taken out and put back.
function P.DropPlace(from, anchor, after)
  if from < anchor then
    return after and anchor or anchor - 1
  end
  return after and anchor + 1 or anchor
end

local function iconOf(talent)
  return talent and talent.i and (ICON_DIR .. talent.i) or nil
end

-- Panel --------------------------------------------------------------------------------------------

-- opts: specs() -> the specs of the editor's class, onMove(from, to) -> true | false, reason (the editor
-- changes the order), onHover(sid | nil), onLayout() (the panel changed its height), onNumbers() (the
-- step numbers were switched). Returns the panel frame with panel:SetOrder(order), panel:Highlight(sid),
-- panel:Say(text | nil), panel:Measure(width, avail) -> height, panel:Rows() and panel:Toggle(open).
function P.Create(parent, opts)
  local panel = CreateFrame("Frame", nil, parent)
  W.Fill(panel, "surface", 1)
  W.Border(panel, "white")

  local data, hot, rows = {}, nil, {}
  local list, note, empty, say

  -- Header ----------------------------------------------------------------------------------------
  local header = CreateFrame("Button", nil, panel)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  W.Fill(header, "surface2")
  header.chevron = W.Glyph(header, "chevron-right", 12, "textSecondary")
  header.chevron:SetPoint("LEFT", 8, 0)
  header.state = W.Text(header, { role = "small", color = "textSecondary" })
  header.state:SetPoint("RIGHT", -8, 0)
  header.label = W.Text(header, { key = "talents.order.title", role = "ui", color = "text" })
  header.label:SetPoint("LEFT", header.chevron, "RIGHT", 6, 0)
  header.label:SetPoint("RIGHT", header.state, "LEFT", -6, 0)
  header.fgName = function()
    return L["talents.order.title"]
  end
  W.AttachTooltip(header, "talents.order.title", "talents.order.tip")

  local body = CreateFrame("Frame", nil, panel)
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
  body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

  local function paintHeader()
    local open = P.IsOpen()
    header.chevron:SetIcon(open and "chevron-down" or "chevron-right")
    header.state:SetText(L[open and "talents.order.open" or "talents.order.closed"])
    body:SetShown(open)
  end
  ns.Bind(header, paintHeader)

  function panel:Toggle(open)
    if open == nil then
      open = not P.IsOpen()
    end
    save("open", open and true or false)
    paintHeader()
    opts.onLayout()
  end
  header:SetScript("OnClick", function()
    panel:Toggle()
  end)
  ns.Focus.register(header, function()
    panel:Toggle()
  end)
  function header:fgArrow(step)
    if (step > 0) ~= P.IsOpen() then
      panel:Toggle(step > 0)
    end
  end

  -- Rows ------------------------------------------------------------------------------------------
  local function reportHover(sid)
    if opts.onHover then
      opts.onHover(sid)
    end
  end

  local function focusInside()
    local current = ns.Focus.current
    if not current then
      return false
    end
    for _, row in ipairs(rows) do
      if current == row or current == row.up or current == row.down then
        return true
      end
    end
    return false
  end

  -- Moves a step by one place; `via` is "row", "up" or "down" (what the keyboard focus stays on).
  local function step(item, delta, via)
    local to = item.index + delta
    if to < 1 or to > #data then
      return panel:Say(L[delta < 0 and "talents.order.first" or "talents.order.last"])
    end
    local keep = focusInside()
    local ok = opts.onMove(item.index, to)
    if ok and keep then
      list:Reveal(to)
      for _, row in ipairs(rows) do
        if row:IsShown() and row.item and row.item.index == to then
          local button = via == "up" and row.up or via == "down" and row.down or nil
          ns.Focus.set(button and button:IsEnabled() and button or row)
          break
        end
      end
    end
  end

  local function nameOf(item)
    return item.talent and ns.T(item.talent.n) or ("#" .. tostring(item.sid))
  end

  local function paintRow(row)
    local item = row.item
    local isHot = item ~= nil and item.sid == hot
    row.bg:SetColorTexture(1, 1, 1, isHot and 0.14 or (row.hover and 0.06 or 0))
    row.mark:SetColorTexture(Theme.color("accent"))
    row.mark:SetShown(isHot)
    row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end

  local function showRowTip(row)
    local item = row.item
    if item and item.talent then
      ns.ShowTooltip(
        row,
        string.format("%d · %s", item.index, nameOf(item)),
        string.format(L["talents.order.rowTip"], item.level, item.rank, item.talent.mr)
      )
    end
  end

  local function stepButton(row, icon, delta, via, key)
    local b = W.Action(row, { icon = icon, variant = "boxed", size = BUTTON, manual = true })
    b.fgName = function()
      return row.item and string.format(L[key], row.item.index) or nil
    end
    local function tip()
      if row.item then
        ns.ShowTooltip(b, b.fgName(), nil)
      end
    end
    b:HookScript("OnEnter", tip)
    b:HookScript("OnLeave", ns.HideTooltip)
    b.fgOnFocus, b.fgOnBlur =
      function()
        tip()
        reportHover(row.item and row.item.sid)
      end, function()
        ns.HideTooltip()
        reportHover(nil)
      end
    b:SetScript(
      "OnClick",
      ns.Wrap("talent-order-step", function()
        if row.item then
          step(row.item, delta, via)
        end
      end)
    )
    return b
  end

  local function createRow(parent_)
    local row = CreateFrame("Button", nil, parent_)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetPoint("TOPLEFT")
    row.mark:SetPoint("BOTTOMLEFT")
    row.mark:SetWidth(3)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.num = W.Text(row, { role = "ui", color = "accent2", justify = "RIGHT" })
    row.num:SetPoint("LEFT", 6, 0)
    row.num:SetWidth(26)
    row.spell = row:CreateTexture(nil, "ARTWORK")
    row.spell:SetSize(ICON, ICON)
    row.spell:SetPoint("LEFT", 38, 0)
    row.spell:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.down = stepButton(row, "chevron-down", 1, "down", "talents.order.down")
    row.down:SetPoint("RIGHT", -4, 0)
    row.up = stepButton(row, "chevron-up", -1, "up", "talents.order.up")
    row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
    row.title = W.Text(row, { role = "ui" })
    row.title:SetPoint("TOPLEFT", row.spell, "TOPRIGHT", 8, 3)
    row.title:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
    row.sub = W.Text(row, { role = "small", color = "textSecondary" })
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
    ns.Bind(row, function()
      paintRow(row)
    end)
    row.fgName = function()
      local item = row.item
      return item
          and item.talent
          and string.format(L["talents.order.row"], item.index, item.level, nameOf(item), item.rank, item.talent.mr)
        or nil
    end
    function row:fgReorder(delta)
      if self.item then
        step(self.item, delta, "row")
      end
    end
    row:SetScript("OnEnter", function()
      row.hover = true
      paintRow(row)
      showRowTip(row)
      reportHover(row.item and row.item.sid)
    end)
    row:SetScript("OnLeave", function()
      row.hover = false
      paintRow(row)
      ns.HideTooltip()
      reportHover(nil)
    end)
    row.fgOnFocus = function()
      showRowTip(row)
      reportHover(row.item and row.item.sid)
    end
    row.fgOnBlur = function()
      ns.HideTooltip()
      reportHover(nil)
    end
    ns.Focus.register(row, function() end)
    rows[#rows + 1] = row
    return row
  end

  local function bindRow(row, item)
    row.item = item
    local icon = iconOf(item.talent)
    if icon then
      row.spell:SetTexture(icon)
    else
      row.spell:SetColorTexture(Theme.color("surface3"))
    end
    row.num:SetText(tostring(item.index))
    row.title:SetText(string.format("%s %d/%d", nameOf(item), item.rank, item.talent and item.talent.mr or item.rank))
    row.sub:SetText(string.format(L["talents.order.level"], item.level))
    row.up:SetEnabled(item.index > 1)
    row.down:SetEnabled(item.index < #data)
    row.up:SetAlpha(item.index > 1 and 1 or 0.4)
    row.down:SetAlpha(item.index < #data and 1 or 0.4)
    paintRow(row)
  end

  local scale = K.scaledHeight
  list = W.ScrollList(body, {
    rowHeight = scale(ROW_BASE),
    createRow = createRow,
    bindRow = bindRow,
    canReorder = function()
      return #data > 1
    end,
    onReorder = function(item, anchor, after)
      opts.onMove(item.index, P.DropPlace(item.index, anchor.index, after))
    end,
  })

  note = W.Text(body, { role = "small", color = "textSecondary", wrap = true })
  empty = W.Text(body, { key = "talents.order.empty", role = "ui", color = "textSecondary", wrap = true })
  local numbers = W.Checkbox(body, {
    key = "talents.order.numbers",
    tooltip = "talents.order.numbers",
    tooltipText = "talents.order.numbersTip",
    get = P.NumbersOn,
    set = function(on)
      save("numbers", on and true or false)
      if opts.onNumbers then
        opts.onNumbers()
      end
    end,
  })

  local function paintNote()
    if say then
      note:SetText(string.format(L["talents.order.blocked"], say))
      W.SetColor(note, "warning")
    else
      note:SetText(L["talents.order.hint"])
      W.SetColor(note, "textSecondary")
    end
  end
  paintNote()

  -- Public ------------------------------------------------------------------------------------------

  -- Replaces the rows with the steps of `order`.
  function panel:SetOrder(order)
    local specs = opts.specs()
    data = {}
    for i, entry in ipairs(order) do
      data[i] = {
        index = i,
        sid = entry.sid,
        rank = entry.rank,
        talent = TO.TalentOf(specs, entry),
        level = TO.StepLevel(i),
      }
    end
    empty:SetShown(#data == 0)
    list:SetData(data)
  end

  -- Marks the rows of a spell id (a hovered talent); nil clears the mark.
  function panel:Highlight(sid)
    if hot ~= sid then
      hot = sid
      list.Refresh()
    end
  end

  -- Shows why a move was refused (nil: the hint again). Lays the page out unless `quiet`.
  function panel:Say(text, quiet)
    say = text
    paintNote()
    if not quiet then
      opts.onLayout()
    end
  end

  function panel:Rows()
    return rows
  end

  function panel:List()
    return list
  end

  function panel:Data()
    return data
  end

  -- The line above the list: the hint, or why the last move was refused.
  function panel:NoteText()
    return note:GetText()
  end

  -- Sets the width and returns the height: the header alone while collapsed. `avail` (optional) is the
  -- height of the trees beside the panel, the list then fills it.
  function panel:Measure(width, avail)
    panel:SetWidth(width)
    local headerH = scale(HEADER_H)
    header:SetHeight(headerH)
    paintHeader()
    if not P.IsOpen() then
      panel:SetHeight(headerH)
      return headerH
    end
    local inner = width - PAD * 2
    note:SetWidth(inner)
    empty:SetWidth(inner - 4)
    local noteH = math.ceil(note:GetStringHeight())
    local toggleH = numbers:GetHeight()
    local rowH = scale(ROW_BASE)
    local fixed = PAD + noteH + PAD + PAD + toggleH + PAD
    local count = avail and math.max(5, math.min(12, math.floor((avail - headerH - fixed) / rowH))) or 8
    local listH = count * rowH
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -PAD)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -(PAD + noteH + PAD))
    list:SetSize(inner, listH)
    empty:ClearAllPoints()
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -8)
    numbers:ClearAllPoints()
    numbers:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -PAD)
    numbers:SetWidth(inner)
    local bodyH = fixed + listH
    body:SetHeight(bodyH)
    list.Refresh()
    local total = headerH + bodyH
    panel:SetHeight(total)
    return total
  end

  paintHeader()
  return panel
end
