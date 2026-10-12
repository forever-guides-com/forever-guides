-- Character overview, side panels: the characters taken out of the overview and the todo
-- manager. A panel sits under the toolbar over the grid. The page decides which one is open
-- (one at a time); every panel closes with Esc through ns.Popups.close. The small input boxes
-- (new todo, cell note) are registered the same way.
-- host = { container, bar, level, render() }.
local _, ns = ...
local W, L, K = ns.W, ns.L, ns.PageKit
local Roster, Todos = ns.CharRoster, ns.RosterTodos

ns.AddLocale("enUS", {
  ["chars.hidden"] = "Hidden (%d)",
  ["chars.hidden.title"] = "Hidden characters",
  ["chars.restore"] = "Restore",
  ["chars.purge"] = "Delete",
  ["chars.purge.current"] = "Current character stays",
  ["chars.purge.title"] = "Delete character",
  ["chars.purge.text"] = "Delete %s for good?",
  ["chars.todos"] = "Todos",
  ["chars.todo.new"] = "New todo",
  ["chars.todo.note"] = "Note (Enter saves)",
  ["chars.todo.add"] = "Add",
  ["chars.todo.show"] = "Show in list",
  ["chars.todo.up"] = "Up",
  ["chars.todo.down"] = "Down",
  ["chars.todo.del"] = "Delete",
  ["chars.todo.del.title"] = "Delete todo",
  ["chars.todo.del.text"] = "Delete %s? All ticks are lost.",
  ["chars.todo.reset"] = "Reset",
  ["chars.todo.resetTip"] = "Click to change",
  ["chars.todo.reset.never"] = "Never",
  ["chars.todo.reset.daily"] = "Daily",
  ["chars.todo.reset.weekly"] = "Weekly",
  ["chars.todo.time"] = "Reset time",
  ["chars.todo.day"] = "Weekly reset day",
  ["chars.todo.clock"] = "Daily and weekly, HH:MM",
  ["chars.todo.server"] = "Server time",
  ["chars.todo.empty"] = "No todos yet",
  ["chars.todo.err.empty"] = "Enter a name",
  ["chars.todo.err.long"] = "At most 40 characters",
  ["chars.todo.err.dup"] = "Name exists",
  ["chars.todo.err.full"] = "List is full",
  ["chars.todo.err.time"] = "Use HH:MM, e.g. 07:00",
})

ns.AddLocale("deDE", {
  ["chars.hidden"] = "Ausgeblendet (%d)",
  ["chars.hidden.title"] = "Ausgeblendete Charaktere",
  ["chars.restore"] = "Zurückholen",
  ["chars.purge"] = "Löschen",
  ["chars.purge.current"] = "Aktueller bleibt",
  ["chars.purge.title"] = "Charakter löschen",
  ["chars.purge.text"] = "%s endgültig löschen?",
  ["chars.todos"] = "Todos",
  ["chars.todo.new"] = "Neues Todo",
  ["chars.todo.note"] = "Notiz (Enter speichert)",
  ["chars.todo.add"] = "Hinzufügen",
  ["chars.todo.show"] = "In Liste zeigen",
  ["chars.todo.up"] = "Hoch",
  ["chars.todo.down"] = "Runter",
  ["chars.todo.del"] = "Löschen",
  ["chars.todo.del.title"] = "Todo löschen",
  ["chars.todo.del.text"] = "%s löschen? Alle Haken gehen verloren.",
  ["chars.todo.reset"] = "Reset",
  ["chars.todo.resetTip"] = "Klick zum Wechseln",
  ["chars.todo.reset.never"] = "Nie",
  ["chars.todo.reset.daily"] = "Täglich",
  ["chars.todo.reset.weekly"] = "Wöchentlich",
  ["chars.todo.time"] = "Reset-Zeit",
  ["chars.todo.day"] = "Reset-Tag (wöchentlich)",
  ["chars.todo.clock"] = "Täglich und wöchentlich, HH:MM",
  ["chars.todo.server"] = "Serverzeit",
  ["chars.todo.empty"] = "Noch keine Todos",
  ["chars.todo.err.empty"] = "Name eingeben",
  ["chars.todo.err.long"] = "Höchstens 40 Zeichen",
  ["chars.todo.err.dup"] = "Name existiert schon",
  ["chars.todo.err.full"] = "Liste ist voll",
  ["chars.todo.err.time"] = "Format HH:MM, z. B. 07:00",
})

local P = {}
ns.RosterPanels = P

local HIDDEN_W, TODO_W = 320, 400
local TODO_ROW, HIDDEN_ROW = 30, 44
local HEAD_H, FOOT_H = 30, 76
local NEXT_RESET = { never = "daily", daily = "weekly", weekly = "never" }

-- Esc ---------------------------------------------------------------------------------------

local registered = setmetatable({}, { __mode = "k" })

function P.Register(panel)
  registered[panel] = true
end

-- Dropdown popups and dialogs go first: they sit on top of a panel.
local closePopup = ns.Popups.close
function ns.Popups.close()
  if closePopup() then
    return true
  end
  if ns.Dialogs and next(ns.Dialogs.open) then
    return false
  end
  for panel in pairs(registered) do
    if panel:IsVisible() then
      panel:Hide()
      return true
    end
  end
  return false
end

-- Shared parts -----------------------------------------------------------------------------

local function notify(key)
  ns.Notify(L[key], "warning")
end

-- The confirm dialog takes locale keys only, the name goes in afterwards.
local function confirm(titleKey, textKey, name, onYes)
  ns.Dialogs.Confirm(titleKey, textKey, onYes)
  local dialog = _G.ForeverGuidesConfirmDialog
  if dialog and dialog.text then
    W.SetText(dialog.text, nil, string.format(L[textKey], name))
  end
end

local function newPanel(host, width, titleKey)
  local panel = CreateFrame("Frame", nil, host.container)
  panel:SetFrameLevel(host.level)
  panel:EnableMouse(true)
  panel:SetPoint("TOPLEFT", host.bar, "BOTTOMLEFT", 4, 2)
  W.Fill(panel, "surface", 1)
  W.Border(panel, "accentDim", 1)
  panel.fgWidth = width
  panel.title = W.Text(panel, { key = titleKey, role = "ui", color = "accent2" })
  panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
  panel.close = W.Action(panel, {
    icon = "close",
    size = W.CLOSE_SIZE,
    tooltip = "common.close",
    onClick = function()
      panel:Hide()
    end,
  })
  panel.close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
  panel.title:SetPoint("RIGHT", panel.close, "LEFT", -4, 0)
  panel.fgFirst = panel.close
  -- Width and height follow the window, the content scrolls.
  function panel.fgFit(wanted)
    local c = host.container
    panel:SetWidth(math.max(200, math.min(width, c:GetWidth() - 8)))
    panel:SetHeight(math.max(100, math.min(wanted or panel.fgWanted or 100, c:GetHeight() - host.bar:GetHeight() - 6)))
  end
  panel:Hide()
  P.Register(panel)
  return panel
end

-- Checks the name and adds a todo without reset, then redraws. After a refusal a short
-- note tells why and the result is false.
function P.AddTodo(text, host)
  local name, why = Todos.CheckName(text)
  if not name then
    notify("chars.todo.err." .. why)
    return false
  end
  local id, err = Todos.Add(name)
  if not id then
    notify(err == "full" and "chars.todo.err.full" or "chars.todo.err.empty")
    return false
  end
  host.render()
  return true
end

-- A small input box under an anchor frame: Enter hands the text to opts.onSubmit(text,
-- target) and closes unless that returns false (the box stays for correcting), Esc and a
-- click elsewhere close it. opts: placeholder (locale key), max (letters), onSubmit.
-- It is placed once at open, so a redraw of the grid under it does not move it.
local INPUT_W, INPUT_H = 260, 32

function P.Input(host, opts)
  local f = CreateFrame("Frame", nil, host.container)
  f:SetFrameLevel(host.level + 10)
  f:SetSize(INPUT_W, INPUT_H)
  f:EnableMouse(true)
  W.Fill(f, "surface", 1)
  W.Border(f, "accentDim", 1)
  f.box = W.EditBox(f, { height = INPUT_H - 8, placeholder = opts.placeholder })
  f.box:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
  f.box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  local edit = f.box.edit
  edit:SetMaxLetters(opts.max)
  edit:SetScript(
    "OnEnterPressed",
    ns.Wrap("roster-input", function(self)
      if opts.onSubmit(self:GetText(), f.fgTarget) ~= false then
        self:ClearFocus()
        f:Hide()
      end
    end)
  )
  edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    f:Hide()
  end)
  edit:HookScript("OnEditFocusLost", function()
    f:Hide()
  end)
  f.fgFirst = f.box

  function f.Open(anchor, text, target)
    local c = host.container
    local x = (anchor:GetLeft() or 0) - (c:GetLeft() or 0)
    local y = (anchor:GetBottom() or 0) - (c:GetTop() or 0) - 2
    f.fgTarget = target
    f:ClearAllPoints()
    f:SetPoint(
      "TOPLEFT",
      c,
      "TOPLEFT",
      math.max(0, math.min(x, c:GetWidth() - INPUT_W)),
      math.min(0, math.max(y, INPUT_H - c:GetHeight()))
    )
    edit:SetText(text or "")
    f:Show()
    edit:SetFocus()
  end

  f:Hide()
  P.Register(f)
  return f
end

local function newIconRow(parent, icon, tipKey, onClick)
  return W.Action(parent, { icon = icon, size = 22, tooltip = tipKey, onClick = onClick })
end

-- Hidden characters -----------------------------------------------------------------------

function P.Hidden(host)
  local panel = newPanel(host, HIDDEN_W, "chars.hidden.title")
  panel.scroll = W.ScrollArea(panel)
  panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -HEAD_H)
  panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
  local content = panel.scroll.content
  local rows = {}

  local function newRow()
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(HIDDEN_ROW)
    r.line = r:CreateTexture(nil, "BACKGROUND")
    r.line:SetPoint("BOTTOMLEFT")
    r.line:SetPoint("BOTTOMRIGHT")
    r.line:SetHeight(1)
    r.line:SetColorTexture(1, 1, 1, 0.08)
    r.purge = W.Action(r, {
      label = "act.delete",
      icon = "trash",
      tooltip = "chars.purge",
      width = 72,
      height = 24,
      onClick = function()
        local e = r.fgChar
        if not e or e.current then
          return
        end
        confirm("chars.purge.title", "chars.purge.text", e.display, function()
          if Roster.Purge(e.key) then
            host.render()
          end
        end)
      end,
    })
    r.purge:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.purge:HookScript("OnEnter", function(self)
      if not self:IsEnabled() then
        ns.ShowTooltip(self, L["chars.purge.current"])
      end
    end)
    r.restore = W.Action(r, {
      label = "act.restore",
      icon = "undo",
      tooltip = "chars.restore",
      width = 104,
      height = 24,
      onClick = function()
        if r.fgChar and Roster.Restore(r.fgChar.key) then
          host.render()
        end
      end,
    })
    r.restore:SetPoint("RIGHT", r.purge, "LEFT", -4, 0)
    r.name = W.Text(r, { role = "ui" })
    r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -7)
    r.name:SetPoint("RIGHT", r.restore, "LEFT", -4, 0)
    r.sub = W.Text(r, { role = "micro", color = "textSecondary" })
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.sub:SetPoint("RIGHT", r.restore, "LEFT", -4, 0)
    return r
  end

  function panel.Refresh()
    local list = Roster.ListHidden()
    for i, e in ipairs(list) do
      local r = rows[i]
      if not r then
        r = newRow()
        rows[i] = r
      end
      r.fgChar = e
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * HIDDEN_ROW)
      r:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * HIDDEN_ROW)
      local name = e.display
      if e.class then
        name = "|cff" .. K.ClassColorHex(e.class):sub(2) .. name .. "|r"
      end
      r.name:SetText(name)
      r.sub:SetText(
        string.format(L["chars.tip.level"], e.class and ns.RefLogic.className(e.class) or "?", tostring(e.level or "?"))
      )
      r.purge:SetEnabled(not e.current)
      r:Show()
    end
    for i = #list + 1, #rows do
      rows[i]:Hide()
      rows[i].fgChar = nil
    end
    panel.scroll:SetContentHeight(#list * HIDDEN_ROW)
    panel.fgWanted = HEAD_H + #list * HIDDEN_ROW + 8
    panel.fgFit()
    return #list
  end

  function panel.Rows()
    return rows
  end
  return panel
end

-- Todo manager ----------------------------------------------------------------------------

function P.Todos(host)
  local panel = newPanel(host, TODO_W, "chars.todos")
  panel.scroll = W.ScrollArea(panel)
  panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -HEAD_H)
  panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, FOOT_H)
  local content = panel.scroll.content
  local rows = {}

  panel.empty = W.Text(panel, { key = "chars.todo.empty", role = "ui", color = "textMuted" })
  panel.empty:SetPoint("TOPLEFT", panel.scroll, "TOPLEFT", 8, -8)

  local function commitName(r, text)
    local def = Todos.Get(r.fgId)
    if not def then
      return
    end
    local clean, why = Todos.CheckName(text, def.id)
    if not clean then
      notify("chars.todo.err." .. why)
    elseif clean ~= def.name then
      Todos.Rename(def.id, clean)
      host.render()
    end
    r.name.edit:SetText(clean or def.name)
  end

  local function newRow()
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(TODO_ROW)
    r.on = W.Checkbox(r, {
      text = "",
      tooltip = "chars.todo.show",
      get = function()
        local def = Todos.Get(r.fgId)
        return def and def.enabled
      end,
      set = function(on)
        Todos.SetEnabled(r.fgId, on)
        host.render()
      end,
    })
    r.on:SetWidth(26)
    r.on:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.del = newIconRow(r, "trash", "chars.todo.del", function()
      local def = Todos.Get(r.fgId)
      if not def then
        return
      end
      confirm("chars.todo.del.title", "chars.todo.del.text", def.name, function()
        if Todos.Remove(def.id) then
          host.render()
        end
      end)
    end)
    r.del:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.down = newIconRow(r, "chevron-down", "chars.todo.down", function()
      Todos.Move(r.fgId, r.fgIndex + 1)
      host.render()
    end)
    r.down:SetPoint("RIGHT", r.del, "LEFT", -2, 0)
    r.up = newIconRow(r, "chevron-up", "chars.todo.up", function()
      Todos.Move(r.fgId, r.fgIndex - 1)
      host.render()
    end)
    r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
    r.reset = W.Button(r, {
      text = "",
      width = 88,
      height = 24,
      tooltip = "chars.todo.reset",
      tooltipText = "chars.todo.resetTip",
      onClick = function()
        local def = Todos.Get(r.fgId)
        if def and Todos.SetReset(def.id, NEXT_RESET[def.reset]) then
          host.render()
        end
      end,
    })
    r.reset:SetPoint("RIGHT", r.up, "LEFT", -6, 0)
    r.name = W.EditBox(r, {
      height = 24,
      onEnter = function(text)
        commitName(r, text)
      end,
    })
    r.name.edit:SetMaxLetters(Todos.NAME_MAX)
    r.name:SetPoint("LEFT", r.on, "RIGHT", 4, 0)
    r.name:SetPoint("RIGHT", r.reset, "LEFT", -6, 0)
    r.name.edit:HookScript("OnEditFocusLost", function(self)
      if not r.fgSkip then
        commitName(r, self:GetText())
      end
    end)
    -- Esc takes the typing back; the focus loss must not save it.
    r.name.edit:SetScript("OnEscapePressed", function(self)
      r.fgSkip = true
      local def = Todos.Get(r.fgId)
      self:SetText(def and def.name or "")
      self:ClearFocus()
      r.fgSkip = false
    end)
    return r
  end

  -- Reset time and new todo, at the bottom of the panel.
  local add
  panel.newBox = W.EditBox(panel, {
    height = 26,
    placeholder = "chars.todo.new",
    onEnter = function(text)
      add(text)
    end,
  })
  panel.newBox.edit:SetMaxLetters(Todos.NAME_MAX)
  panel.addButton = W.Action(panel, {
    label = "act.add",
    icon = "plus",
    tooltip = "chars.todo.add",
    width = 104,
    height = 26,
    onClick = function()
      add(panel.newBox.edit:GetText())
    end,
  })
  panel.addButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
  panel.newBox:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 6)
  panel.newBox:SetPoint("RIGHT", panel.addButton, "LEFT", -6, 0)

  function add(text)
    if P.AddTodo(text, host) then
      panel.newBox.edit:SetText("")
      panel.scroll:ScrollTo(1e6)
    end
  end

  local function clock()
    local spec = Todos.SpecFor()
    return spec, string.format("%02d:%02d", spec.hour, spec.min)
  end

  panel.timeLabel = W.Text(panel, { key = "chars.todo.time", role = "ui", color = "textSecondary" })
  panel.timeLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 42)
  panel.dayButton = W.Button(panel, {
    text = "",
    width = 64,
    height = 26,
    tooltip = "chars.todo.day",
    tooltipText = "chars.todo.server",
    onClick = function()
      local spec = clock()
      if Todos.SetDefaultTime(spec.weekday % 7 + 1, spec.hour, spec.min) then
        host.render()
      end
    end,
  })
  panel.dayButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 118, 38)
  panel.timeBox = W.EditBox(panel, { height = 26 })
  panel.timeBox:SetWidth(64)
  panel.timeBox:SetPoint("LEFT", panel.dayButton, "RIGHT", 6, 0)
  panel.timeBox.edit:SetMaxLetters(5)
  W.AttachTooltip(panel.timeBox.edit, "chars.todo.clock", "chars.todo.server")

  local function commitTime(text)
    local hour, min = text:match("^%s*(%d%d?):(%d%d)%s*$")
    if not hour then
      hour = text:match("^%s*(%d%d?)%s*$")
      min = hour and "0"
    end
    local spec = clock()
    if not hour then
      notify("chars.todo.err.time")
    elseif tonumber(hour) ~= spec.hour or tonumber(min) ~= spec.min then
      if Todos.SetDefaultTime(spec.weekday, tonumber(hour), tonumber(min)) then
        host.render()
      else
        notify("chars.todo.err.time")
      end
    end
    panel.timeBox.edit:SetText(select(2, clock()))
  end
  panel.timeBox.edit:SetScript("OnEnterPressed", function(self)
    commitTime(self:GetText())
    self:ClearFocus()
  end)
  panel.timeBox.edit:HookScript("OnEditFocusLost", function(self)
    if not panel.fgSkipTime then
      commitTime(self:GetText())
    end
  end)
  panel.timeBox.edit:SetScript("OnEscapePressed", function(self)
    panel.fgSkipTime = true
    self:SetText(select(2, clock()))
    self:ClearFocus()
    panel.fgSkipTime = false
  end)

  function panel.Refresh()
    local defs = Todos.Defs()
    for i, def in ipairs(defs) do
      local r = rows[i]
      if not r then
        r = newRow()
        rows[i] = r
      end
      r.fgId, r.fgIndex = def.id, i
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * TODO_ROW)
      r:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * TODO_ROW)
      if not r.name.edit:HasFocus() then
        r.name.edit:SetText(def.name)
      end
      r.on.Refresh()
      W.SetText(r.reset.label, "chars.todo.reset." .. def.reset)
      r.up:SetEnabled(i > 1)
      r.up:SetAlpha(i > 1 and 1 or 0.35)
      r.down:SetEnabled(i < #defs)
      r.down:SetAlpha(i < #defs and 1 or 0.35)
      r:Show()
    end
    for i = #defs + 1, #rows do
      rows[i]:Hide()
      rows[i].fgId = nil
    end
    panel.empty:SetShown(#defs == 0)
    panel.scroll:SetContentHeight(#defs * TODO_ROW + 4)
    local spec, text = clock()
    W.SetText(panel.dayButton.label, "time.day." .. spec.weekday)
    if not panel.timeBox.edit:HasFocus() then
      panel.timeBox.edit:SetText(text)
    end
    panel.fgWanted = HEAD_H + FOOT_H + math.max(60, #defs * TODO_ROW + 8)
    panel.fgFit()
  end

  function panel.Rows()
    return rows
  end
  return panel
end
