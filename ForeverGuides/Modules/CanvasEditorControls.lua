-- Property controls for the panels of the canvas editor (ns.CanvasEditor.Controls). A host builds the
-- panel of its element types from these, so every type looks and behaves the same. Each call returns
-- a frame with :Refresh() (read the value again); the caller anchors it and, where the frame has no
-- fixed size, gives it a width. Heights are in Controls.HEIGHT. Labels are locale keys.
--
--   Controls.Color(parent, { label, get() -> "rrggbb"|nil, set(hex|nil), default?, allowNil?, owner? })
--   Controls.Font(parent, { label, get() -> key, set(key), width? })
--   Controls.Slider(parent, { label, min, max, step, get, set, format? })
--   Controls.Number(parent, { label, min, max, step?, get, set, labelWidth?, tooltip? })
--   Controls.Toggle(parent, { label, get, set, tooltip? })
--   Controls.Choice(parent, { label, options = { { value, key|text } }, get, set, width? })
--   Controls.Text(parent, { label, get, set(text), maxLetters?, inline?, commit? })
--     Every typed character goes to set, with commit only Enter and leaving the field do (Escape puts the old
--     text back) and the field then shows what get() returns, so the owner may clean the text.
--   Controls.ColorAlpha(parent, { label, get() -> "rrggbb", alpha(0..1), set(hex, alpha), default?, owner?, allowNil? })
--     A color row and an opacity slider (HEIGHT.colorAlpha in all); a change of either calls set with both values.
--   Controls.Gallery(parent, { label, items = { { value, texture, label } }, get, set(value), columns?, size?, resolve? })
--     Small previews to choose from, `label` a locale key (name and tooltip of the cell), `texture` a texture
--     path or file id, or a stem that `resolve(stem)` turns into one. The chosen cell has a ring and a check
--     mark and its name shows beside the heading. Height: gallery:GetHeight().
--   Controls.Section(parent, key)           heading of a group of rows (HEIGHT.section)
--
-- Panel scaffolding for the element types of a host (rows stacked top down, one write path):
--   Controls.NewPanel(parent, { element, onChange, props = function(raw) -> repaired props, build(state, add) })
--     build adds rows with add(frame, height, shown?) (height a number or a function that measures it)
--     and uses state.get(key) / state.write(key, value);
--     the panel is built once per type and told the element in edit by :Refresh(element).
--   Controls.TextRow(state, add, key, color?) a wrapped muted text row, its height measured at the panel width.
--   Controls.ColorRow(state, add, label, key, default), ChoiceRow(state, add, label, key, list, prefix),
--   ToggleRow(state, add, label, key), Choices(list, prefix) -> options { value, key }
local _, ns = ...
local W, L, U, WS = ns.W, ns.L, ns.U, ns.WindowStyle

local CE = ns.CanvasEditor or {}
ns.CanvasEditor = CE
local C = {}
CE.Controls = C

C.HEIGHT = {
  color = 26,
  number = 26,
  slider = 42,
  toggle = 24,
  choice = 46,
  text = 46,
  textInline = 26,
  section = 18,
  colorAlpha = 26 + 42,
}
C.CHOICE_WIDTH = 250
C.PANEL_GAP = 6
C.GALLERY_CELL, C.GALLERY_GAP, C.GALLERY_COLUMNS = 40, 4, 6
-- Font entries in the dropdown: a long list of shared media fonts would not fit on the screen.
C.MAX_FONTS = 24

ns.AddLocale("enUS", {
  ["canvas.color.pick"] = "Opens a color palette.",
  ["canvas.color.none"] = "Default",
  ["canvas.opacity"] = "Opacity",
})
ns.AddLocale("deDE", {
  ["canvas.color.pick"] = "Öffnet eine Farbpalette.",
  ["canvas.color.none"] = "Standard",
  ["canvas.opacity"] = "Deckkraft",
})

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function hexOf(v)
  return type(v) == "string" and v:match("^#?(%x%x%x%x%x%x)$") and v:gsub("^#", ""):lower() or nil
end

-- Label left, color chip and hex button right. The hex text names the color, so the state is not
-- carried by the chip alone.
function C.Color(parent, o)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(C.HEIGHT.color)
  local button = W.Action(row, {
    text = " ",
    width = 84,
    height = 24,
    tooltip = o.label,
    tooltipText = "canvas.color.pick",
    wrap = "canvas-color",
  })
  button:SetPoint("RIGHT", 0, 0)
  local chip = CreateFrame("Frame", nil, row)
  chip:SetSize(22, 22)
  chip:SetPoint("RIGHT", button, "LEFT", -6, 0)
  chip.tex = chip:CreateTexture(nil, "ARTWORK")
  chip.tex:SetAllPoints()
  W.Border(chip, "white", 0.6)
  local label = W.Text(row, { key = o.label, role = "ui" })
  label:SetPoint("LEFT", 0, 0)
  label:SetPoint("RIGHT", chip, "LEFT", -6, 0)
  label:SetHeight(C.HEIGHT.color)
  label:SetJustifyV("MIDDLE")

  function row:Refresh()
    local hex = hexOf(o.get())
    if hex then
      chip.tex:SetColorTexture(U.hex(hex))
      W.SetText(button.label, nil, "#" .. hex:upper())
    else
      chip.tex:SetColorTexture(0, 0, 0, 0)
      W.SetText(button.label, "canvas.color.none")
    end
  end
  button:SetScript(
    "OnClick",
    ns.Wrap("canvas-color", function()
      WS.OpenPalette(button, hexOf(o.get()) or hexOf(o.default), function(hex)
        hex = hexOf(hex) or hexOf(o.default)
        if hex == nil and not o.allowNil then
          return
        end
        o.set(hex)
        row:Refresh()
      end, o.owner)
    end)
  )
  row.button, row.chip = button, chip
  row:Refresh()
  return row
end

local function fontLabel(key)
  local name = "notes.font." .. key
  if L[name] ~= name then
    return L[name]
  end
  return (tostring(key):gsub("^lsm:", ""))
end

-- Font choice from the list the note windows offer (NW.FontList). The saved value shows even when the
-- font is not in the list any more (marked with a star).
function C.Font(parent, o)
  local options = {}
  local function fill()
    for i = #options, 1, -1 do
      options[i] = nil
    end
    local current, seen = o.get(), {}
    for i, key in ipairs(ns.NoteWindow.FontList()) do
      if i <= C.MAX_FONTS or key == current then
        options[#options + 1] = { value = key, text = fontLabel(key) }
        seen[key] = true
      end
    end
    if current and not seen[current] then
      options[#options + 1] = { value = current, text = fontLabel(current) .. " *" }
    end
  end
  fill()
  local dd = W.Dropdown(parent, {
    key = o.label,
    options = options,
    width = o.width or C.CHOICE_WIDTH,
    get = o.get,
    set = o.set,
  })
  local paint = dd.Refresh
  function dd:Refresh()
    fill()
    paint()
  end
  return dd
end

function C.Slider(parent, o)
  return W.Slider(parent, {
    key = o.label,
    min = o.min,
    max = o.max,
    step = o.step,
    get = o.get,
    set = o.set,
    format = o.format,
  })
end

function C.Toggle(parent, o)
  return W.Toggle(parent, {
    key = o.label,
    get = o.get,
    set = o.set,
    tooltip = o.tooltip,
    tooltipText = o.tooltipText,
  })
end

function C.Choice(parent, o)
  return W.Dropdown(parent, {
    key = o.label,
    options = o.options,
    width = o.width or C.CHOICE_WIDTH,
    get = o.get,
    set = o.set,
  })
end

-- A number field: Enter or leaving the field sets the value (clamped to min and max, rounded to
-- step); anything that is not a number puts the old value back.
function C.Number(parent, o)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(C.HEIGHT.number)
  local label = W.Text(row, { key = o.label, role = "ui" })
  label:SetPoint("LEFT", 0, 0)
  label:SetWidth(o.labelWidth or 70)
  label:SetHeight(C.HEIGHT.number)
  label:SetJustifyV("MIDDLE")
  local box = W.EditBox(row, { height = 24, inset = 6 })
  box:SetPoint("LEFT", label, "RIGHT", 4, 0)
  box:SetPoint("RIGHT", 0, 0)
  local eb = box.edit
  local function show()
    local v = o.get()
    eb:SetText(finite(v) and tostring(U.round(v, 0.01)) or "")
  end
  local function commit()
    local n = tonumber(eb:GetText())
    if finite(n) then
      n = U.clamp(n, o.min or -math.huge, o.max or math.huge)
      if o.step then
        n = U.round(n, o.step)
      end
      if n ~= o.get() then
        o.set(n)
      end
    end
    show()
  end
  eb:HookScript("OnEnterPressed", commit)
  eb:HookScript("OnEditFocusLost", commit)
  if o.tooltip then
    eb:HookScript("OnEnter", function(self)
      ns.ShowTooltip(self, L[o.label], L[o.tooltip])
    end)
    eb:HookScript("OnLeave", ns.HideTooltip)
  end
  function row:Refresh()
    if not eb:HasFocus() then
      show()
    end
  end
  row.box, row.edit = box, eb
  row:Refresh()
  return row
end

-- A line of text. Every typed character goes to set at once (the preview follows while you type).
function C.Text(parent, o)
  local row = CreateFrame("Frame", nil, parent)
  local inline = o.inline == true
  row:SetHeight(inline and C.HEIGHT.textInline or C.HEIGHT.text)
  local label = W.Text(row, { key = o.label, role = "ui" })
  label:SetPoint("TOPLEFT", 0, 0)
  local box = W.EditBox(row, {
    height = 24,
    inset = 6,
    onChange = not o.commit and function(text)
      o.set(text)
    end or nil,
  })
  if inline then
    label:SetWidth(o.labelWidth or 70)
    label:SetHeight(C.HEIGHT.textInline)
    label:SetJustifyV("MIDDLE")
    box:SetPoint("LEFT", label, "RIGHT", 4, 0)
  else
    box:SetPoint("TOPLEFT", 0, -20)
  end
  box:SetPoint("RIGHT", 0, 0)
  local eb = box.edit
  if o.maxLetters then
    eb:SetMaxLetters(o.maxLetters)
  end
  if o.commit then
    local function commit()
      local text = eb:GetText() or ""
      if text ~= (o.get() or "") then
        o.set(text)
      end
      eb:SetText(o.get() or "")
    end
    eb:HookScript("OnEnterPressed", commit)
    eb:HookScript("OnEditFocusLost", commit)
    eb:SetScript("OnEscapePressed", function()
      eb:SetText(o.get() or "")
      eb:ClearFocus()
    end)
  end
  function row:Refresh()
    if not eb:HasFocus() then
      eb:SetText(o.get() or "")
    end
  end
  row.box, row.edit = box, eb
  row:Refresh()
  return row
end

-- A heading above a group of rows.
function C.Section(parent, key)
  local text = W.Text(parent, { key = key, role = "ui", color = "accent2" })
  text:SetHeight(C.HEIGHT.section)
  return text
end

-- Color row with an opacity slider below it. Both write through o.set(hex, alpha).
function C.ColorAlpha(parent, o)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(C.HEIGHT.colorAlpha)
  local function alpha()
    local a = o.alpha()
    return finite(a) and U.clamp(a, 0, 1) or 1
  end
  row.color = C.Color(row, {
    label = o.label,
    default = o.default,
    allowNil = o.allowNil,
    owner = o.owner,
    get = o.get,
    set = function(hex)
      o.set(hex, alpha())
    end,
  })
  row.color:SetPoint("TOPLEFT", 0, 0)
  row.color:SetPoint("TOPRIGHT", 0, 0)
  row.slider = C.Slider(row, {
    label = "canvas.opacity",
    min = 0,
    max = 100,
    step = 5,
    get = function()
      return math.floor(alpha() * 100 + 0.5)
    end,
    set = function(v)
      o.set(hexOf(o.get()), v / 100)
    end,
    format = function(v)
      return v .. "%"
    end,
  })
  row.slider:SetPoint("TOPLEFT", 0, -C.HEIGHT.color)
  row.slider:SetPoint("TOPRIGHT", 0, -C.HEIGHT.color)
  function row:Refresh()
    self.color:Refresh()
    self.slider:Refresh()
  end
  return row
end

-- Previews to choose from. The chosen cell wears a ring and a check mark, so the choice does not rest on
-- color, and its name shows next to the heading.
function C.Gallery(parent, o)
  local row = CreateFrame("Frame", nil, parent)
  local size, gap = o.size or C.GALLERY_CELL, C.GALLERY_GAP
  local columns = math.max(1, math.floor(o.columns or C.GALLERY_COLUMNS))
  local items = type(o.items) == "table" and o.items or {}
  local head = C.HEIGHT.section + 4
  row:SetHeight(head + math.max(1, math.ceil(#items / columns)) * (size + gap))
  local title = W.Text(row, { key = o.label, role = "ui", color = "accent2" })
  title:SetPoint("TOPLEFT", 0, 0)
  local chosen = W.Text(row, { role = "ui", justify = "RIGHT" })
  chosen:SetPoint("TOPRIGHT", 0, 0)
  title:SetPoint("RIGHT", chosen, "LEFT", -6, 0)
  title:SetHeight(C.HEIGHT.section)
  chosen:SetHeight(C.HEIGHT.section)
  row.cells, row.title, row.chosen = {}, title, chosen
  for i, item in ipairs(items) do
    local texture = item[2]
    if type(texture) == "string" and type(o.resolve) == "function" then
      texture = o.resolve(texture) or texture
    end
    local cell = W.Action(row, {
      texture = texture,
      size = size,
      boxed = true,
      tooltip = item[3],
      wrap = "canvas-gallery",
      onClick = function()
        o.set(item[1])
        row:Refresh()
      end,
    })
    cell:SetPoint("TOPLEFT", ((i - 1) % columns) * (size + gap), -(head + math.floor((i - 1) / columns) * (size + gap)))
    cell.chip = cell:CreateTexture(nil, "OVERLAY")
    cell.chip:SetDrawLayer("OVERLAY", 1)
    cell.chip:SetSize(16, 16)
    cell.chip:SetPoint("BOTTOMRIGHT", -2, 2)
    cell.chip:SetColorTexture(0, 0, 0, 0.75)
    cell.check = W.CheckMark(cell, 12, "text")
    cell.check:SetPoint("CENTER", cell.chip, "CENTER")
    cell.check:Fit(12)
    cell.value = item[1]
    row.cells[i] = cell
  end
  function row:Refresh()
    local current = o.get()
    local name
    for i, cell in ipairs(self.cells) do
      local on = cell.value == current
      cell:SetSelected(on)
      cell.chip:SetShown(on)
      cell.check:SetShown(on)
      if on then
        name = items[i][3]
      end
    end
    W.SetText(chosen, name)
  end
  row:Refresh()
  return row
end

-- Panel scaffolding ------------------------------------------------------------------------------------

-- Options { value, key } for a list of values, the key being prefix .. value.
function C.Choices(list, prefix)
  local out = {}
  for i, value in ipairs(list) do
    out[i] = { value = value, key = prefix .. value }
  end
  return out
end

-- A panel stacked from control rows. Every change goes through state.write: the prop is set and the
-- whole table repaired by o.props before the editor hears about it. `o.build(state, add)` adds the rows;
-- add(frame, height, shown) returns the frame, `shown` (optional) decides whether the row takes room.
-- The panel is built once per type and told the element in edit by :Refresh(element).
function C.NewPanel(parent, o)
  local panel = CreateFrame("Frame", nil, parent)
  local state = { element = o.element, panel = panel }
  local rows = {}
  function state.get(key)
    return o.props(state.element.props, state.element)[key]
  end
  function state.write(key, value)
    local el = state.element
    local raw = type(el.props) == "table" and el.props or {}
    raw[key] = value
    el.props = o.props(raw, el)
    o.onChange()
  end
  function state.owner()
    local editor = ns.CanvasEditor
    return editor and editor.Frame and editor.Frame() or nil
  end
  o.build(state, function(frame, height, shown)
    rows[#rows + 1] = { frame = frame, height = height, shown = shown }
    return frame
  end)
  local function place()
    local y = 0
    for _, row in ipairs(rows) do
      local show = row.shown == nil or row.shown()
      row.frame:SetShown(show)
      if show then
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -y)
        row.frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -y)
        y = y + (type(row.height) == "function" and row.height() or row.height) + C.PANEL_GAP
      end
    end
    panel:SetHeight(math.max(1, y))
  end
  -- rawget: the control's own method, not a lookup in the client's frame methods.
  function panel:Refresh(el)
    if el then
      state.element = el
    end
    for _, row in ipairs(rows) do
      if type(rawget(row.frame, "Refresh")) == "function" then
        row.frame:Refresh()
      end
    end
    place()
  end
  panel:Refresh()
  return panel
end

-- A wrapped text row (a locale key, muted by default). Its height is measured at the width of the panel
-- (Controls.PANEL_WIDTH), so the next row never starts inside the text.
function C.TextRow(state, add, key, color)
  local row = CreateFrame("Frame", nil, state.panel)
  local text = W.Text(row, { key = key, role = "ui", color = color or "textMuted", wrap = true })
  text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  text:SetWidth(C.PANEL_WIDTH or 284)
  return add(row, function()
    local height = math.max(14, math.ceil(text:GetStringHeight() or 0) + 2)
    row:SetHeight(height)
    return height
  end)
end

function C.ColorRow(state, add, label, key, default)
  return add(
    C.Color(state.panel, {
      label = label,
      default = default,
      owner = state.owner(),
      get = function()
        return state.get(key)
      end,
      set = function(color)
        state.write(key, color)
      end,
    }),
    C.HEIGHT.color
  )
end

function C.ChoiceRow(state, add, label, key, list, prefix)
  return add(
    C.Choice(state.panel, {
      label = label,
      options = C.Choices(list, prefix),
      get = function()
        return state.get(key)
      end,
      set = function(value)
        state.write(key, value)
      end,
    }),
    C.HEIGHT.choice
  )
end

function C.ToggleRow(state, add, label, key)
  return add(
    C.Toggle(state.panel, {
      label = label,
      get = function()
        return state.get(key)
      end,
      set = function(on)
        state.write(key, on == true)
      end,
    }),
    C.HEIGHT.toggle
  )
end
