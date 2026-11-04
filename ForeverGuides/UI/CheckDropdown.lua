-- W.CheckDropdown: one button in the look of W.Dropdown that opens a list of switches. A click on a
-- row toggles it and keeps the list open, a click elsewhere or Esc closes it (popup layer of the
-- desktop, ns.Desktop.Layer). The button shows a short summary of how many entries are on.
local _, ns = ...
local W, L, Theme, Focus = ns.W, ns.L, ns.Theme, ns.Focus

local ROW_H = 24
local ICON = 18
local PAD = 8

-- opts:
--   items    = { { id, key | text, get(), set(v), tooltip, tooltipText (locale keys), glyph (name of the
--                  icon set) | icon(box) (paints into the ICON x ICON frame, called once) } }
--   summary  = function(on, total) -> the text of the button (default "on/total")
--   width    = width of the button (default 220, owners anchor it on both sides instead)
--   tooltip, tooltipText = locale keys of the button
-- Returns the button b with b:Item(id) (the row of an entry, a button that toggles it), b:Refresh(),
-- b:Open(), b:Close(), b:IsOpen(), b.popup and b.rows.
function W.CheckDropdown(parent, opts)
  local items = opts.items
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(24)
  b:SetWidth(opts.width or 220)
  W.Fill(b, "surface2")
  W.Border(b, "white", 0.25)
  local current = W.Text(b, { role = "ui", color = "text" })
  current:SetPoint("LEFT", PAD, 0)
  local arrow = W.Glyph(b, "chevron-down", 12, "textMuted")
  arrow:SetPoint("RIGHT", -PAD, 0)
  current:SetPoint("RIGHT", arrow, "LEFT", -6, 0)

  local layer = function()
    return ns.Desktop and ns.Desktop.Layer
  end
  local popup = CreateFrame("Frame", nil, UIParent)
  popup:SetFrameStrata("TOOLTIP")
  popup:SetClampedToScreen(true)
  popup:EnableMouse(true)
  -- Solid on purpose: the list lies over page text and must never follow a window opacity.
  W.Fill(popup, "surface", 1)
  W.Border(popup, "accentDim", 1)
  popup:Hide()
  local rows, byId = {}, {}
  b.popup, b.rows, b.current = popup, rows, current

  local function counts()
    local on = 0
    for _, item in ipairs(items) do
      if item.get() then
        on = on + 1
      end
    end
    return on, #items
  end

  local function paint()
    local on, total = counts()
    current:SetText(opts.summary and opts.summary(on, total) or (on .. "/" .. total))
    for _, row in ipairs(rows) do
      row:Refresh()
    end
  end

  for i, item in ipairs(items) do
    local row = W.Checkbox(popup, {
      key = item.key,
      text = item.text,
      get = item.get,
      set = function(v)
        item.set(v)
        paint()
      end,
    })
    row.fgItem = item
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0)
    row.iconBox = CreateFrame("Frame", nil, row)
    row.iconBox:SetSize(ICON, ICON)
    row.iconBox:SetPoint("LEFT", row.box, "RIGHT", PAD, 0)
    if item.icon then
      item.icon(row.iconBox)
    elseif item.glyph then
      local g = W.Glyph(row.iconBox, item.glyph, 14, "textSecondary")
      g:SetPoint("CENTER")
    end
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row.iconBox, "RIGHT", PAD, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
    row.box:ClearAllPoints()
    row.box:SetPoint("LEFT", row, "LEFT", PAD, 0)
    local function showTip()
      if item.tooltip then
        ns.ShowTooltip(row, L[item.tooltip], item.tooltipText and L[item.tooltipText])
      end
    end
    row:HookScript("OnEnter", function()
      row.hl:SetColorTexture(1, 1, 1, 0.08)
    end)
    row:HookScript("OnLeave", function()
      row.hl:SetColorTexture(1, 1, 1, 0)
    end)
    W.AttachTooltip(row, item.tooltip, item.tooltipText)
    row.fgOnFocus, row.fgOnBlur = showTip, ns.HideTooltip
    rows[i] = row
    byId[item.id] = row
  end

  -- Natural width of the list: the widest row, never narrower than the button.
  local function place()
    local widest = 0
    for _, row in ipairs(rows) do
      widest = math.max(widest, math.ceil(row.label:GetStringWidth()))
    end
    local width = math.max(b:GetWidth(), widest + 2 * PAD + 16 + ICON + 2 * PAD + 2)
    local rowH = Theme.lineHeight(ROW_H)
    for i, row in ipairs(rows) do
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -1 - (i - 1) * rowH)
      row:SetSize(width - 2, rowH)
    end
    popup:SetSize(width, #rows * rowH + 2)
  end

  local function moveFocus(step)
    local index = 0
    for i, row in ipairs(rows) do
      if Focus.current == row then
        index = i
      end
    end
    if #rows == 0 then
      return
    end
    index = index == 0 and (step > 0 and 1 or #rows) or (index - 1 + step) % #rows + 1
    Focus.set(rows[index])
  end

  popup:EnableKeyboard(true)
  popup:SetScript("OnKeyDown", function(self, key)
    local handled = true
    if key == "ESCAPE" then
      layer().close("escape")
    elseif key == "UP" or key == "DOWN" then
      moveFocus(key == "DOWN" and 1 or -1)
    elseif key == "ENTER" or key == "SPACE" then
      Focus.activate()
    else
      handled = false
    end
    ns.PropagateKeys(self, not handled)
  end)

  function b:IsOpen()
    return popup:IsShown()
  end

  function b:Close()
    local l = layer()
    if l and popup:IsShown() then
      l.close("api")
    end
  end

  function b:Open()
    local l = layer()
    if not l then
      return
    end
    paint()
    place()
    l.open({
      frames = { popup },
      owner = b,
      move = moveFocus,
      onClose = function()
        arrow:SetIcon("chevron-down")
        ns.HideTooltip()
      end,
    })
    l.place(popup, b, "TOPLEFT", "BOTTOMLEFT", 0, -2)
    popup:Show()
    arrow:SetIcon("chevron-up")
    Focus.set(rows[1])
  end

  b:SetScript(
    "OnClick",
    ns.Wrap("check-dropdown", function()
      if popup:IsShown() then
        b:Close()
      else
        b:Open()
      end
    end)
  )
  Focus.register(b, function()
    b:Open()
  end)
  W.AttachTooltip(b, opts.tooltip, opts.tooltipText)
  b:HookScript("OnHide", function()
    b:Close()
  end)

  function b:Item(id)
    return byId[id]
  end
  b.Refresh = paint
  ns.Bind(b, paint)
  return b
end
