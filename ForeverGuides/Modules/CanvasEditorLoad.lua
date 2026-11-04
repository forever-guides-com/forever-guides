-- The controls of "when active" (ns.CanvasEditor.Controls.LoadPanel): one row per topic with a three-way
-- switch On, Any, Off (a button each, so every choice is its own stop of the keyboard focus and its accessible
-- name says topic and state, "Combat: any"), the class, the specialization and the character as "Any, Is, Is
-- not" with a tick list, the summary sentence on top and a note under it for each set topic the Forever client does not verify
-- in combat yet. It lives in its own file so Modules/CanvasEditorControls.lua stays free. The logic is
-- Modules/LoadLogic.lua, the game state Modules/LoadState.lua; the panel builds on any parent (the settings of
-- a HUD window, of the ring, later the panels of the editor).
--
--   Controls.LoadPanel(parent, { get() -> load|nil, set(load|nil), onResize? })
--     The frame has :Refresh() (read the value again) and :fgGridLayout(width) -> height (places every control
--     for that width, so it fits a page stack as well as a card). onResize() is called when a change of the
--     value shows or hides rows, so the owner lays out again. Fields: rows[topic] = { on, any, off } and
--     rows.class / rows.spec / rows.character = { any, is, isnot } (the buttons), classBoxes[token], specBoxes[i],
--     charBoxes[key] (the known characters of the account, the current one first and marked, and the ids of
--     characters nobody knows any more, so they can be unticked).
local _, ns = ...
local W, L, Theme = ns.W, ns.L, ns.Theme
local LL, LS, CS = ns.LoadLogic, ns.LoadState, ns.CharScopeLogic

local C = ns.CanvasEditor.Controls

local GAP, ROW_H, BUTTON_H, MIN_BUTTON_W, LABEL_MIN_W, BOX_H, BOX_W = 6, 26, 24, 56, 150, 22, 130
local MAX_SPECS = 4
-- The value a yes/no button stands for; "any" is nil (a table cannot hold it, the lookup gives it).
local WANT = { on = true, off = false }

ns.AddLocale("enUS", {
  ["load.topic.combat"] = "Combat",
  ["load.topic.instance"] = "Instance",
  ["load.topic.grouped"] = "In a group",
  ["load.topic.mounted"] = "On a mount",
  ["load.topic.vehicle"] = "In a vehicle",
  ["load.topic.target"] = "Has a target",
  ["load.topic.class"] = "Class",
  ["load.topic.spec"] = "Specialization",
  ["load.topic.character"] = "Character",
  ["load.char.current"] = "%s (current)",
  ["load.char.unknown"] = "%s (unknown character)",
  ["load.char.unavailable"] = "The game does not name this character. Without an answer the condition counts as not met.",
  ["load.state.on"] = "On",
  ["load.state.any"] = "Any",
  ["load.state.off"] = "Off",
  ["load.mode.is"] = "Is",
  ["load.mode.isnot"] = "Is not",
  ["load.tip.state"] = "On: active only while this applies. Any: this does not matter. Off: active only while this does not apply.",
  ["load.tip.mode"] = "Is: active only for the ones you tick. Is not: active for all but the ones you tick. Any: this does not matter.",
  ["load.access"] = "%s: %s",
  ["load.spec.unavailable"] = "Not available in the Forever client.",
  ["load.spec.empty"] = "The game names no specialization for this character.",
  ["load.note.unverified"] = "%s: whether the game answers this in combat is not verified on the Forever client yet. Without an answer the condition counts as not met.",
})
ns.AddLocale("deDE", {
  ["load.topic.combat"] = "Kampf",
  ["load.topic.instance"] = "Instanz",
  ["load.topic.grouped"] = "In einer Gruppe",
  ["load.topic.mounted"] = "Auf dem Reittier",
  ["load.topic.vehicle"] = "Im Fahrzeug",
  ["load.topic.target"] = "Ziel vorhanden",
  ["load.topic.class"] = "Klasse",
  ["load.topic.spec"] = "Spezialisierung",
  ["load.topic.character"] = "Charakter",
  ["load.char.current"] = "%s (aktuell)",
  ["load.char.unknown"] = "%s (unbekannter Charakter)",
  ["load.char.unavailable"] = "Das Spiel nennt diesen Charakter nicht. Ohne Antwort gilt die Bedingung als nicht erfüllt.",
  ["load.state.on"] = "An",
  ["load.state.any"] = "Egal",
  ["load.state.off"] = "Aus",
  ["load.mode.is"] = "Ist",
  ["load.mode.isnot"] = "Ist nicht",
  ["load.tip.state"] = "An: aktiv nur, solange es zutrifft. Egal: spielt keine Rolle. Aus: aktiv nur, solange es nicht zutrifft.",
  ["load.tip.mode"] = "Ist: aktiv nur für die Angehakten. Ist nicht: aktiv für alle außer den Angehakten. Egal: spielt keine Rolle.",
  ["load.access"] = "%s: %s",
  ["load.spec.unavailable"] = "Im Forever-Client nicht verfügbar.",
  ["load.spec.empty"] = "Das Spiel nennt für diesen Charakter keine Spezialisierung.",
  ["load.note.unverified"] = "%s: Ob das Spiel das im Kampf beantwortet, ist auf dem Forever-Client noch nicht geprüft. Ohne Antwort gilt die Bedingung als nicht erfüllt.",
})

local function scaled(base)
  return Theme.lineHeight(base)
end

local function has(list, value)
  for _, v in ipairs(list or {}) do
    if v == value then
      return true
    end
  end
  return false
end

-- Which button of a row is chosen for `load`: "on", "any" or "off" for a yes/no topic, "any", "is" or "isnot"
-- for a list.
-- A list whose mode is chosen and that has no member yet is stored as nothing (an empty list means any), so the
-- mode the player picked waits in `pending` until a member is ticked.
local function chosen(row, load, pending)
  if row.kind == "flag" then
    local v = load and load[row.topic]
    return v == true and "on" or v == false and "off" or "any"
  end
  local entry = load and load[row.topic]
  return entry and entry.mode or pending[row.topic] or "any"
end

function C.LoadPanel(parent, o)
  local panel = CreateFrame("Frame", nil, parent)
  panel.rows, panel.classBoxes, panel.specBoxes, panel.charBoxes = {}, {}, {}, {}
  local rows = {}
  panel.summary = W.Text(panel, { text = "", role = "small", color = "textSecondary", wrap = true })
  panel.notes = W.Text(panel, { text = "", role = "small", color = "textMuted", wrap = true })
  local structure
  local pending = {}

  local function current()
    return LL.Clean(o.get())
  end

  local function change(load)
    o.set(load)
    panel:Refresh()
  end

  local function addRow(topic, kind)
    local row = { topic = topic, kind = kind, buttons = {}, boxes = {} }
    local names = kind == "flag" and { "on", "any", "off" } or { "any", "is", "isnot" }
    row.label = W.Text(panel, { key = "load.topic." .. topic, role = "ui" })
    row.label:SetJustifyV("MIDDLE")
    for i, name in ipairs(names) do
      local value = name
      local stateKey = (name == "is" or name == "isnot") and "load.mode." .. name or "load.state." .. name
      local button = W.Action(panel, {
        key = stateKey,
        height = BUTTON_H,
        width = MIN_BUTTON_W,
        tooltip = "load.topic." .. topic,
        tooltipText = kind == "flag" and "load.tip.state" or "load.tip.mode",
        wrap = "load-switch",
        onClick = function()
          if kind == "flag" then
            change(LL.WithTopic(o.get(), topic, WANT[value]))
          else
            pending[topic] = value ~= "any" and value or nil
            change(LL.WithMode(o.get(), topic, pending[topic]))
          end
        end,
      })
      -- The accessible name carries the topic and the state, never the colour alone.
      button.fgName = function()
        return string.format(L["load.access"], L["load.topic." .. topic], L[stateKey])
      end
      row.buttons[name] = button
      row.buttons[i] = button
    end
    row.hint = W.Text(panel, { text = "", role = "small", color = "textMuted", wrap = true })
    row.hint:Hide()
    rows[#rows + 1] = row
    panel.rows[topic] = row.buttons
    return row
  end

  for _, topic in ipairs(LL.TOPICS) do
    addRow(topic, "flag")
  end
  local classRow, specRow, charRow = addRow("class", "list"), addRow("spec", "list"), addRow("character", "list")

  for _, token in ipairs(LL.CLASSES) do
    local box = W.Checkbox(panel, {
      key = "class." .. token,
      get = function()
        local entry = current() and current().class
        return entry ~= nil and has(entry.list, token)
      end,
      set = function(on)
        local entry = current() and current().class
        pending.class = entry and entry.mode or pending.class or "is"
        change(LL.WithMember(o.get(), "class", token, on))
      end,
    })
    classRow.boxes[#classRow.boxes + 1] = box
    panel.classBoxes[token] = box
  end
  for i = 1, MAX_SPECS do
    local box
    box = W.Checkbox(panel, {
      text = " ",
      get = function()
        local entry = current() and current().spec
        return box ~= nil and box.fgSpecId ~= nil and entry ~= nil and has(entry.list, box.fgSpecId)
      end,
      set = function(on)
        if box.fgSpecId then
          local entry = current() and current().spec
          pending.spec = entry and entry.mode or pending.spec or "is"
          change(LL.WithMember(o.get(), "spec", box.fgSpecId, on))
        end
      end,
    })
    specRow.boxes[i] = box
    panel.specBoxes[i] = box
  end

  -- The box number `i` of the character list, made when the list first needs it (the number of characters is
  -- not known up front).
  local function charBox(i)
    if not charRow.boxes[i] then
      local box
      box = W.Checkbox(panel, {
        text = " ",
        get = function()
          local entry = current() and current().character
          return box ~= nil and box.fgCharKey ~= nil and entry ~= nil and has(entry.list, box.fgCharKey)
        end,
        set = function(on)
          if box.fgCharKey then
            local entry = current() and current().character
            pending.character = entry and entry.mode or pending.character or "is"
            change(LL.WithMember(o.get(), "character", box.fgCharKey, on))
          end
        end,
      })
      charRow.boxes[i] = box
    end
    return charRow.boxes[i]
  end

  -- The text of a character of the list: the current one is marked, one nobody knows says so.
  local function charText(item)
    if item.current then
      return string.format(L["load.char.current"], item.label)
    end
    return item.known and item.label or string.format(L["load.char.unknown"], item.label)
  end

  -- Which boxes of a list row show, and what they say.
  local function paintBoxes(row, mode)
    local list = row.topic == "spec" and LS.SpecList() or nil
    if row.topic == "character" then
      local entry = current() and current().character
      local known = CS.List(ns.db and ns.db.characters, LS.Get().character, entry and entry.list)
      for i, item in ipairs(known) do
        local box = charBox(i)
        box.fgCharKey = item.key
        W.SetText(box.label, nil, charText(item))
        panel.charBoxes[item.key] = box
      end
      for i = #known + 1, #row.boxes do
        row.boxes[i].fgCharKey = nil
      end
      for key, box in pairs(panel.charBoxes) do
        if box.fgCharKey ~= key then
          panel.charBoxes[key] = nil
        end
      end
      row.fgCount = #known
    end
    for i, box in ipairs(row.boxes) do
      local show = mode ~= "any" and (row.topic ~= "character" or i <= row.fgCount)
      if list then
        local item = list[i]
        box.fgSpecId = item and item.id or nil
        show = show and item ~= nil
        if item then
          W.SetText(box.label, nil, item.name)
        end
      end
      box:SetShown(show)
      if show then
        box.Refresh()
      end
    end
    if row.topic == "character" then
      local text = (mode ~= "any" and LS.Get().character == nil) and L["load.char.unavailable"] or ""
      W.SetText(row.hint, nil, text)
      row.hint:SetShown(text ~= "")
    end
    if row.topic == "spec" then
      local available = LS.HasSpec()
      local text = not available and L["load.spec.unavailable"]
        or (mode ~= "any" and #list == 0) and L["load.spec.empty"]
        or ""
      W.SetText(row.hint, nil, text)
      row.hint:SetShown(text ~= "")
      row.buttons.is:SetEnabled(available)
      row.buttons.isnot:SetEnabled(available)
    end
  end

  function panel:Refresh()
    local load = current()
    W.SetText(panel.summary, nil, LL.Summary(load))
    local shown = {}
    for _, row in ipairs(rows) do
      if load and load[row.topic] then
        pending[row.topic] = nil
      end
      local pick = chosen(row, load, pending)
      for name, button in pairs(row.buttons) do
        if type(name) == "string" then
          button:SetSelected(name == pick)
        end
      end
      if row.kind == "list" then
        paintBoxes(row, pick)
        shown[#shown + 1] = row.topic .. pick .. (row.topic == "character" and pick ~= "any" and row.fgCount or "")
      end
    end
    local lines = {}
    for _, topic in ipairs(LL.Unverified(load)) do
      lines[#lines + 1] = string.format(L["load.note.unverified"], L["load.topic." .. topic])
    end
    W.SetText(panel.notes, nil, table.concat(lines, "\n"))
    panel.notes:SetShown(#lines > 0)
    -- Rows that appear or go change the height: the owner lays out again.
    local key = table.concat(shown, ",") .. "/" .. #lines .. "/" .. tostring(LS.HasSpec())
    local before = structure
    structure = key
    if before ~= nil and before ~= key and o.onResize then
      o.onResize()
    end
  end

  -- The common width of the three buttons of the rows: the widest text, at least MIN_BUTTON_W.
  local function buttonWidth()
    local w = MIN_BUTTON_W
    for _, row in ipairs(rows) do
      for i = 1, 3 do
        w = math.max(w, row.buttons[i]:FullWidth())
      end
    end
    return w
  end

  local function place(frame, x, y, w, h)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    if w then
      frame:SetSize(w, h)
    end
  end

  function panel:fgGridLayout(width)
    width = math.max(width or 0, 1)
    local y = 0
    place(panel.summary, 0, y, nil)
    panel.summary:SetWidth(width)
    y = y + math.ceil(panel.summary:GetStringHeight()) + GAP
    -- One common width for the three buttons while they fit in a line; below that each takes its own text
    -- width and they wrap, so no text is cut at a narrow page or a large font.
    local bw = buttonWidth()
    local bar = 3 * bw + 2 * GAP
    local fits = bar <= width
    local stacked = not fits or width < bar + LABEL_MIN_W + GAP
    local rowH, btnH = scaled(ROW_H), scaled(BUTTON_H)
    for _, row in ipairs(rows) do
      if stacked then
        place(row.label, 0, y, width, rowH)
        y = y + rowH
      else
        place(row.label, 0, y, width - bar - GAP, btnH)
      end
      if fits then
        local x0 = stacked and 0 or width - bar
        for i = 1, 3 do
          place(row.buttons[i], x0 + (i - 1) * (bw + GAP), y, bw, btnH)
        end
      else
        local x = 0
        for i = 1, 3 do
          local w = math.min(row.buttons[i]:FullWidth(), width)
          if x > 0 and x + w > width then
            x, y = 0, y + btnH + GAP
          end
          place(row.buttons[i], x, y, w, btnH)
          x = x + w + GAP
        end
      end
      y = y + btnH + GAP
      if row.hint:IsShown() then
        place(row.hint, 0, y, nil)
        row.hint:SetWidth(width)
        y = y + math.ceil(row.hint:GetStringHeight()) + GAP
      end
      local shownBoxes = {}
      for _, box in ipairs(row.boxes) do
        if box:IsShown() then
          shownBoxes[#shownBoxes + 1] = box
        end
      end
      if #shownBoxes > 0 then
        local cols = math.max(1, math.min(3, math.floor((width + GAP) / (BOX_W + GAP))))
        -- Names of characters are long: one to a line.
        if row.topic == "character" then
          cols = 1
        end
        local colW = (width - (cols - 1) * GAP) / cols
        local boxH = scaled(BOX_H)
        for i, box in ipairs(shownBoxes) do
          local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
          place(box, col * (colW + GAP), y + line * (boxH + 4), colW, boxH)
        end
        local lines = math.ceil(#shownBoxes / cols)
        y = y + lines * boxH + (lines - 1) * 4 + GAP
      end
    end
    if panel.notes:IsShown() then
      place(panel.notes, 0, y, nil)
      panel.notes:SetWidth(width)
      y = y + math.ceil(panel.notes:GetStringHeight()) + GAP
    end
    panel:SetSize(width, math.max(y - GAP, 1))
    return math.max(y - GAP, 1)
  end

  panel:Refresh()
  return panel
end
