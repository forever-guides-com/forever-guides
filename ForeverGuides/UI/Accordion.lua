-- Collapsible section "More settings" for a settings card: the important controls stay visible, the rest
-- sits behind one header. The state (open or closed) is kept per card in the character store, closed is the
-- default. The header is a button for the keyboard (Enter, Space, Right opens, Left closes) and shows the
-- state as text next to the chevron, so color or shape alone never carry it.
--
--   local more = W.Accordion(view, { id = "gathering.pins" })
--   toggle(more, ...)               -- more has content and stack like a card, fill it with the same helpers
--   more:ControlIds()               -- the fgId of every control inside, for the search and for jumps
--   more:Open() / more:Close()
local _, ns = ...
local W, L = ns.W, ns.L

local HEADER_H, GAP = 28, 4
-- Left edge of the label (chevron and its gaps), right padding, gap between label and state, padding above and below
-- the two lines of a narrow header.
local LABEL_LEFT, PAD, TEXT_GAP, LINES_PAD = 26, 8, 8, 6

ns.AddLocale("enUS", {
  ["settings.more"] = "More settings",
  ["settings.more.open"] = "expanded",
  ["settings.more.closed"] = "collapsed",
  ["settings.more.tip"] = "Enter or Space expands or collapses this section. Right arrow expands, left arrow collapses.",
})
ns.AddLocale("deDE", {
  ["settings.more"] = "Weitere Einstellungen",
  ["settings.more.open"] = "aufgeklappt",
  ["settings.more.closed"] = "zugeklappt",
  ["settings.more.tip"] = "Enter oder Leertaste klappt den Abschnitt auf oder zu. Pfeil rechts klappt auf, Pfeil links klappt zu.",
})

local function store()
  local char = ns.charDB
  if not char then
    return nil
  end
  if type(char.settingsMore) ~= "table" then
    char.settingsMore = {}
  end
  return char.settingsMore
end

-- view: a card or page view (content, stack, Layout). opts.id: stable key of the card, opts.open: start state
-- when nothing is stored (default closed).
function W.Accordion(view, opts)
  opts = opts or {}
  local acc = { id = opts.id }
  local frame = CreateFrame("Frame", nil, view.content)
  acc.frame = frame

  local header = CreateFrame("Button", nil, frame)
  header:SetHeight(HEADER_H)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  W.Fill(header, "surface2")
  acc.header = header
  header.chevron = W.Glyph(header, "chevron-right", 12, "textSecondary")
  header.chevron:SetPoint("LEFT", 8, 0)
  header.label = W.Text(header, { key = "settings.more", role = "ui", color = "text" })
  header.label:SetPoint("LEFT", header.chevron, "RIGHT", 6, 0)
  header.state = W.Text(header, { role = "small", color = "textSecondary" })
  header.state:SetPoint("RIGHT", -8, 0)
  W.AttachTooltip(header, "settings.more", "settings.more.tip")

  local body = CreateFrame("Frame", nil, frame)
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -GAP)
  acc.body = body
  -- The nested stack reads the viewport from the page and hands its height back, like a card does.
  local area = { content = body }
  function area.GetHeight()
    return view.area and view.area:GetHeight() or 0
  end
  function area.SetContentHeight(_, h)
    local changed = acc.inner ~= h
    acc.inner = h
    -- A change while the section stands (a banner appears) asks the page for a layout of its own.
    if changed and acc.opened and not acc.busy then
      view:Layout()
    end
  end
  function area.ScrollTo(_, y)
    if view.area and view.area.ScrollTo then
      view.area:ScrollTo(y)
    end
  end
  acc.area = area
  acc.content = body
  acc.stack = W.Stack(area, 0)

  function acc:Layout()
    view:Layout()
  end

  function acc:Refresh()
    for _, entry in ipairs(self.stack.items) do
      if entry.item.Refresh then
        entry.item:Refresh()
      end
    end
  end

  local function paint()
    local open = acc.opened
    header.chevron:SetIcon(open and "chevron-down" or "chevron-right")
    header.state:SetText(L[open and "settings.more.open" or "settings.more.closed"])
    body:SetShown(open)
  end

  function acc:IsOpen()
    return acc.opened == true
  end

  -- remember = false keeps the state out of the store (a jump to a control opens the section for now only).
  function acc:SetOpen(open, remember)
    open = open == true
    if acc.opened == open then
      return
    end
    acc.opened = open
    local saved = store()
    if saved and remember ~= false and acc.id then
      saved[acc.id] = open or nil
    end
    paint()
    view:Layout()
  end

  function acc:Open(remember)
    self:SetOpen(true, remember)
  end

  function acc:Close()
    self:SetOpen(false)
  end

  function acc:Toggle()
    self:SetOpen(not acc.opened)
  end

  -- Every control inside as { id, frame }, in order. A row without an id of its own (a field next to its
  -- status) lists its direct children. The frame is also there for a text line (a region, no child frame).
  local function controls()
    local out = {}
    for _, entry in ipairs(acc.stack.items) do
      local id = rawget(entry.item, "fgId")
      if id then
        out[#out + 1] = { id = id, frame = entry.item }
      else
        local kids = entry.item.GetChildren and { entry.item:GetChildren() } or {}
        for _, child in ipairs(kids) do
          id = rawget(child, "fgId")
          if id then
            out[#out + 1] = { id = id, frame = child }
          end
        end
      end
    end
    return out
  end

  -- The fgId of every control inside, in order.
  function acc:ControlIds()
    local out = {}
    for _, control in ipairs(controls()) do
      out[#out + 1] = control.id
    end
    return out
  end

  -- The frame (or text line) of the control with this id, nil when the section has none.
  function acc:FindControl(controlId)
    for _, control in ipairs(controls()) do
      if control.id == controlId then
        return control.frame
      end
    end
    return nil
  end

  function acc:Has(controlId)
    for _, id in ipairs(self:ControlIds()) do
      if id == controlId then
        return true
      end
    end
    return false
  end

  header:SetScript("OnClick", function()
    acc:Toggle()
  end)
  ns.Focus.register(header, function()
    acc:Toggle()
  end)
  function header:fgArrow(step)
    acc:SetOpen(step > 0)
  end
  header.fgId = opts.id and ("more-" .. opts.id) or nil
  ns.Bind(header, paint)

  local saved = store()
  local stored = saved and acc.id and saved[acc.id]
  acc.opened = stored == true or (stored == nil and opts.open == true)
  paint()

  -- Label and state share one row while both fit. A narrow card or a large text size puts the state under the
  -- label, so the two never overlap. Returns the header height.
  local function fitHeader(width)
    local need = LABEL_LEFT
      + math.ceil(header.label:GetStringWidth())
      + TEXT_GAP
      + math.ceil(header.state:GetStringWidth())
      + PAD
    header.label:ClearAllPoints()
    header.state:ClearAllPoints()
    local height = HEADER_H
    if need <= width then
      header.label:SetPoint("LEFT", header.chevron, "RIGHT", 6, 0)
      header.state:SetPoint("RIGHT", -PAD, 0)
    else
      header.label:SetPoint("TOPLEFT", LABEL_LEFT, -LINES_PAD)
      header.state:SetPoint("TOPLEFT", header.label, "BOTTOMLEFT", 0, -2)
      height = math.max(HEADER_H, math.ceil(header.label:GetHeight() + header.state:GetHeight()) + 2 + 2 * LINES_PAD)
    end
    header:SetHeight(height)
    return height
  end

  -- The outer stack asks for the height: the header, plus the body while open.
  function frame:fgGridLayout(width)
    acc.busy = true
    local headerH = fitHeader(width)
    local height = headerH
    if acc.opened then
      body:SetWidth(width)
      body:Show()
      acc.stack:Layout()
      local last = acc.stack.items[#acc.stack.items]
      local trailing = last and (last.opts.gap or 10) or 0
      local inner = math.max(0, (acc.inner or 0) - trailing)
      body:SetHeight(inner)
      height = headerH + GAP + inner
    else
      body:Hide()
    end
    acc.busy = false
    frame:SetHeight(height)
    return height
  end

  -- The card repaints its controls when a value changed elsewhere, also those behind the header.
  function frame:Refresh()
    acc:Refresh()
  end

  view.stack:Add(frame, { gap = 8 })
  if view.accordions then
    view.accordions[#view.accordions + 1] = acc
  end
  return acc
end
