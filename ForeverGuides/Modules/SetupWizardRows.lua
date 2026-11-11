-- Window blocks of the setup wizard that list features (Modules/SetupWizard.lua builds the window around them).
-- One feature row = switch, name, one sentence, an "Options" button with the new-window mark and, while the
-- feature is on, at most two options below. The rules (what a row reads and writes) are in
-- Modules/SetupFeatureLogic.lua, the rows come from Modules/SetupFeatureData.lua.
--
--   R.Row(parent, spec)       the generic row: optional switch, name, sentence, note, badge, button and
--                             options that show or hide with the switch (the menu step builds its group rows
--                             from it too). Lays itself out through fgGridLayout(width) like a W.Stack item.
--   R.Features(view, step)    block "features": the rows of step.id
--   R.Restart(view)           block "restart": the line "Restart needed" with a reload button, only while a
--                             sub-add-on that was switched off is still running
--   R.MenuLines(old, new)     summary lines of a change of the menu step (hidden and shown entries)
--   R.Factor()                the font scale the window grows with
local _, ns = ...
local W, L, SW = ns.W, ns.L, ns.SetupWizard
local FL = ns.SetupFeatureLogic

local R = {}
ns.SetupWizardRows = R

-- Left edge of the label of a switch (track, state text, gap), where the sentence under it lines up.
R.HINT_INDENT = 76
-- Indent of the options under their row, a toggle there starts left of the name of the row above.
R.OPTION_INDENT = 24
R.BUTTON_W, R.GAP, R.ROW_H = 110, 8, 26
-- Decorative icon in front of a name: its size at font 100 and the gap to the name.
R.ICON, R.ICON_GAP = 18, 6

ns.AddLocale("enUS", {
  ["setup.row.optionsTip"] = "Opens every setting of this area in a new window.",
  ["setup.restart.text"] = "Switched-off add-ons end only after a reload of the interface.",
  ["setup.restart.button"] = "Reload now",
  ["setup.restart.tip"] = "Reloads the interface. Your settings stay.",
  ["setup.collapse.resume"] = "Continue setup",
  ["setup.collapse.tip"] = "Shows the setup again at the step where you left it.",
  ["setup.pencil.line"] = "Change the menu with the pencil above it: hide and show areas.",
  ["setup.summary.menuHidden"] = "Menu hidden: %s",
  ["setup.summary.menuShown"] = "Menu shown: %s",
})
ns.AddLocale("deDE", {
  ["setup.row.optionsTip"] = "Öffnet alle Einstellungen dieses Bereichs in einem neuen Fenster.",
  ["setup.restart.text"] = "Ausgeschaltete Zusatzaddons enden erst mit einem Neustart der Oberfläche.",
  ["setup.restart.button"] = "Jetzt neu laden",
  ["setup.restart.tip"] = "Lädt die Oberfläche neu. Deine Einstellungen bleiben.",
  ["setup.collapse.resume"] = "Weiter einrichten",
  ["setup.collapse.tip"] = "Zeigt die Einrichtung wieder bei dem Schritt, an dem du warst.",
  ["setup.pencil.line"] = "Das Menü änderst du mit dem Stift darüber: Bereiche aus- und einblenden.",
  ["setup.summary.menuHidden"] = "Menü ausgeblendet: %s",
  ["setup.summary.menuShown"] = "Menü eingeblendet: %s",
})

-- Buttons and text grow with the font scale, so the rows do too.
function R.Factor()
  local v = ns.db and tonumber(ns.db.settings.fontScale) or 1
  return math.max(1, v or 1)
end

local function ui()
  return ns.SetupWizardUI
end

-- Asks the window to lay the step out again (a row showed or hid its options, a line appeared).
local function refreshWindow()
  local window = ui()
  if window and window.Refresh then
    window.Refresh()
  end
end

local function pixels(n)
  return math.floor(n * R.Factor() + 0.5)
end

-- Lines below a row ---------------------------------------------------------------------------------

-- A toggle of its own with an optional sentence under it. c: a step control of type "toggle".
local function toggleLine(parent, c, id)
  local line = CreateFrame("Frame", nil, parent)
  line.toggle = W.Toggle(line, {
    key = c.labelKey,
    get = function()
      return SW.Get(c)
    end,
    set = function(value)
      SW.Put(c, value)
      refreshWindow()
    end,
    tooltip = c.labelKey,
    tooltipText = c.hintKey,
  })
  line.fgId = id
  line.toggle.fgId = id .. "-toggle"
  line.toggle:SetPoint("TOPLEFT")
  if c.hintKey then
    line.hint = W.Text(line, { key = c.hintKey, role = "micro", color = c.hintColor or "textMuted", wrap = true })
  end
  function line:Refresh()
    self.toggle.Refresh()
  end
  function line:fgGridLayout(width)
    self.toggle:SetWidth(width)
    local h = 24
    if self.hint then
      self.hint:ClearAllPoints()
      self.hint:SetPoint("TOPLEFT", R.HINT_INDENT, -h)
      self.hint:SetWidth(math.max(40, width - R.HINT_INDENT))
      h = h + self.hint:GetStringHeight() + 2
    end
    self:SetHeight(h)
    return h
  end
  return line
end

local function cleanWords(text)
  local IL = ns.InviteLogic
  return IL.JoinWords(IL.ParseWords(text))
end

-- A list of key words as one line of text (the invite words). What is typed is stored cleaned up, the line
-- under the field says what is used now.
local function wordsLine(parent, option, id)
  local IL, path = ns.InviteLogic, option.key
  local line = CreateFrame("Frame", nil, parent)
  line.label = W.Text(line, { key = option.labelKey, role = "ui", color = "textSecondary", wrap = true })
  local function paint()
    local words = ns.Store.get(path)
    local used = type(words) == "string" and words or ""
    W.SetColor(line.status, used == "" and "warning" or "textMuted")
    line.status:SetText(
      used == "" and L["setup.ctl.inviteWordsNone"] or string.format(L["setup.ctl.inviteWordsUsed"], used)
    )
  end
  line.box = W.EditBox(line, {
    placeholder = "setup.ctl.inviteWordsExample",
    maxLetters = IL.MAX_WORDS * (IL.MAX_WORD + 2),
    live = true,
    get = function()
      return ns.Store.get(path) or ""
    end,
    set = function(text)
      ns.Store.set(path, cleanWords(text))
      paint()
    end,
  })
  line.fgId = id
  line.box.fgId = id .. "-field"
  line.status = W.Text(line, { role = "micro", wrap = true })
  ns.Bind(line.status, paint)
  function line:Refresh()
    self.box:Refresh()
    paint()
  end
  function line:fgGridLayout(width)
    self.label:ClearAllPoints()
    self.label:SetPoint("TOPLEFT")
    self.label:SetWidth(width)
    local y = self.label:GetStringHeight() + 4
    self.box:ClearAllPoints()
    self.box:SetPoint("TOPLEFT", 0, -y)
    self.box:SetSize(math.min(pixels(320), width), 26)
    y = y + 26 + 4
    self.status:ClearAllPoints()
    self.status:SetPoint("TOPLEFT", 0, -y)
    self.status:SetWidth(width)
    y = y + self.status:GetStringHeight() + 2
    self:SetHeight(y)
    return y
  end
  line:Refresh()
  return line
end

-- Generic row ---------------------------------------------------------------------------------------

-- Lays the options of a row out below y in `columns` equal columns (one column: one line each, as wide as the
-- room). Returns the y below the last line.
local function layoutOptions(row, columns, width, y)
  local options = row.options
  local first = 1
  while first <= #options do
    local indent = options[first].indent
    local room = math.max(40, width - indent)
    local gap = columns > 1 and R.GAP or 0
    local colW = math.max(40, math.floor((room - (columns - 1) * gap) / columns))
    local lineH = 0
    for i = first, math.min(first + columns - 1, #options) do
      local frame = options[i].frame
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", indent + (i - first) * (colW + gap), -(y + 2))
      frame:SetWidth(colW)
      lineH = math.max(lineH, frame:fgGridLayout(colW))
    end
    y = y + 2 + lineH + 2
    first = first + columns
  end
  return y
end

-- spec: id (frame id of the row), nameKey, textKey (sentence), noteKey (fixed note under it),
--   switch = { get, set }  without it the name stands as plain text and the options are always shown,
--   badge = function() -> text   short text at the right, left of the button (a counter),
--   button = { key | icon, tooltip, tooltipText, onClick, opens, variant, width, boxed },
--     an icon button may also have tip = function() -> title, text, name  (a tooltip that follows its state,
--     name = the accessible name), hitBadge = true  (the badge is a second, mouse-only target of the button)
--     and arrow = function(step)  (Left/Right while the button has the keyboard focus),
--   iconSlot = true, icon = texture path   room for a decorative icon left of the name of the switch; without
--     an icon the room stays free, so the names of all rows line up,
--   optionsShown = function() -> bool   default: the switch is on (or there is no switch),
--   compact = true   no sentence under the name (it stays in the tooltip of the switch),
--   columns = n   the options stand in n equal columns, one line per n options,
--   onRelayout = function()   called when the options appeared or went away,
--   afterSet = function()     called after a click on the switch (default: the window lays out again).
-- row:AddOption(frame, indent) adds a line with fgGridLayout(width) under the row.
-- row.reserve (nil, true or false) lays the row out with its options shown (true) or hidden (false) whatever
-- it shows now; the window uses it to measure the tallest state of a step (SetupWizard.lua).
function R.Row(parent, spec)
  local row = CreateFrame("Frame", nil, parent)
  row.fgId = spec.id and ("wizard-row-" .. spec.id) or nil
  row.options = {}
  local function optionsOn()
    if spec.optionsShown then
      return spec.optionsShown() and true or false
    end
    return spec.switch == nil or spec.switch.get() == true
  end

  if spec.switch then
    row.switch = W.Toggle(row, {
      key = spec.nameKey,
      labelInset = spec.iconSlot and (pixels(R.ICON) + R.ICON_GAP) or nil,
      get = spec.switch.get,
      set = function(value)
        spec.switch.set(value)
        row:Refresh()
        if spec.afterSet then
          spec.afterSet()
        else
          refreshWindow()
        end
      end,
      tooltip = spec.nameKey,
      tooltipText = spec.textKey,
    })
    row.switch.fgId = row.fgId and (row.fgId .. "-switch")
    row.switch:SetPoint("TOPLEFT")
    if spec.iconSlot and spec.icon then
      -- Decoration only: the name carries the meaning. It sits on the switch, left of the name.
      row.icon = row.switch:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(pixels(R.ICON), pixels(R.ICON))
      row.icon:SetPoint("LEFT", row.switch.state, "RIGHT", 4, 0)
      row.icon:SetTexture(spec.icon)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
  else
    row.name = W.Text(row, { key = spec.nameKey, role = "ui", color = "text", wrap = true })
  end
  if spec.textKey and not spec.compact then
    row.text = W.Text(row, { key = spec.textKey, role = "micro", color = "textMuted", wrap = true })
  end
  if spec.noteKey then
    row.note = W.Text(row, { key = spec.noteKey, role = "micro", color = "textMuted", wrap = true })
  end
  if spec.badge then
    row.badge = W.Text(row, { text = spec.badge(), role = "micro", color = "textSecondary", justify = "RIGHT" })
  end
  local b = spec.button
  if b then
    local width = pixels(b.width or R.BUTTON_W)
    if b.key then
      row.button = W.Button(row, {
        key = b.key,
        width = width,
        onClick = b.onClick,
        tooltip = b.tooltip,
        tooltipText = b.tooltipText,
        variant = b.variant,
        opens = b.opens,
      })
    else
      row.button = W.Action(row, {
        icon = b.icon,
        size = R.ROW_H,
        tooltip = b.tooltip,
        tooltipText = b.tooltipText,
        onClick = b.onClick,
        opens = b.opens,
        boxed = b.boxed,
        manual = b.tip ~= nil,
      })
    end
    row.button.fgId = row.fgId and (row.fgId .. "-button")
    row.button:SetPoint("TOPRIGHT")
    if b.tip then
      row.button:HookScript("OnEnter", function(self)
        local title, text = b.tip()
        ns.ShowTooltip(self, title, text)
      end)
      row.button:HookScript("OnLeave", ns.HideTooltip)
      function row.button.fgName()
        local _, _, name = b.tip()
        return name
      end
    end
    if b.arrow then
      function row.button:fgArrow(step)
        b.arrow(step)
      end
    end
    if b.hitBadge and row.badge then
      -- The counter next to the arrow is part of the same target: it forwards click and hover.
      row.hit = CreateFrame("Frame", nil, row)
      row.hit:EnableMouse(true)
      row.hit:SetPoint("TOPRIGHT")
      row.hit:SetScript("OnMouseUp", function()
        row.button:Click()
      end)
      row.hit:SetScript("OnEnter", function()
        row.button:GetScript("OnEnter")(row.button)
      end)
      row.hit:SetScript("OnLeave", function()
        row.button:GetScript("OnLeave")(row.button)
      end)
    end
  end

  function row:AddOption(frame, indent)
    self.options[#self.options + 1] = { frame = frame, indent = indent or R.OPTION_INDENT }
    frame:SetShown(self.optionsOn == true)
    return frame
  end

  local function showOptions(on)
    row.optionsOn = on
    for _, option in ipairs(row.options) do
      option.frame:SetShown(on)
    end
  end

  function row:Refresh()
    if self.switch then
      self.switch.Refresh()
    end
    if self.badge then
      self.badge:SetText(spec.badge())
    end
    for _, option in ipairs(self.options) do
      if option.frame.Refresh then
        option.frame:Refresh()
      end
    end
    local on = optionsOn()
    if on ~= self.optionsOn then
      showOptions(on)
      if spec.onRelayout then
        spec.onRelayout()
      end
    end
  end

  function row:fgGridLayout(width)
    local buttonW = row.button and math.max(math.ceil(row.button:GetWidth()), 1) or 0
    local right = buttonW > 0 and buttonW + R.GAP or 0
    if row.badge then
      local badgeW = math.ceil(row.badge:GetStringWidth()) + 2
      row.badge:ClearAllPoints()
      row.badge:SetPoint("TOPRIGHT", -right, -5)
      row.badge:SetWidth(badgeW)
      right = right + badgeW + R.GAP
      if row.hit then
        row.hit:SetSize(right, R.ROW_H)
      end
    end
    local head = R.ROW_H
    local indent = 0
    if row.switch then
      row.switch:SetWidth(math.max(R.HINT_INDENT + 40, width - right))
      indent = R.HINT_INDENT
    else
      row.name:ClearAllPoints()
      row.name:SetPoint("TOPLEFT", 0, -5)
      row.name:SetWidth(math.max(40, width - right))
      head = math.max(head, row.name:GetStringHeight() + 8)
    end
    local y = head
    for _, text in ipairs({ row.text or false, row.note or false }) do
      if text then
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", indent, -y)
        text:SetWidth(math.max(40, width - indent))
        y = y + text:GetStringHeight() + 2
      end
    end
    local open = row.reserve
    if open == nil then
      open = row.optionsOn
    end
    if open then
      y = layoutOptions(row, spec.columns or 1, width, y)
    end
    row:SetHeight(y)
    return y
  end

  showOptions(optionsOn())
  return row
end

-- Feature rows --------------------------------------------------------------------------------------

-- True when the row can be built in this client: its switch and its options exist.
local function usable(def)
  if def.switch.kind == "none" then
    return #def.options > 0
  end
  return FL.Available(def.id)
end

local function addOptions(row, def, view)
  local count = 0
  for i, option in ipairs(FL.Options(def.id)) do
    local id = row.fgId .. "-option" .. i
    local frame
    if option.control then
      if SW.DefaultOf(option.key) ~= nil then
        frame = toggleLine(row, option.control, id)
      end
    elseif option.kind == "words" and ns.InviteLogic and SW.DefaultOf(option.key) ~= nil then
      frame = wordsLine(row, option, id)
    end
    if frame then
      row:AddOption(frame)
      view.widgets[#view.widgets + 1] = frame
      count = count + 1
    end
  end
  return count
end

-- Builds one feature row into the step view. The "Options" button opens the settings of the feature next to the
-- window (SetupWizardUI.Reveal), the wizard stays open. Returns the row.
function R.FeatureRow(view, id)
  local def = FL.Row(id)
  local control = FL.Control(id)
  local spec = {
    id = id,
    nameKey = FL.NameKey(id),
    textKey = def.textKey,
    noteKey = def.noteKey,
    onRelayout = function()
      view.relayout = true
    end,
    button = {
      key = "act.options",
      tooltip = FL.NameKey(id),
      tooltipText = "setup.row.optionsTip",
      opens = true,
      onClick = function()
        if FL.Open(id) and ui() then
          ui().Reveal()
        end
      end,
    },
  }
  if control then
    spec.switch = {
      get = function()
        return SW.Get(control)
      end,
      set = function(value)
        SW.Put(control, value)
      end,
    }
  end
  local row = R.Row(view.area.content, spec)
  addOptions(row, def, view)
  row:Refresh()
  -- The window measures a step with the options of every row shown.
  view.reference[#view.reference + 1] = function(on)
    row.reserve = on and true or nil
  end
  view.stack:Add(row, { gap = 10 })
  view.widgets[#view.widgets + 1] = row
  view.rows[#view.rows + 1] = row
  return row
end

-- Block "features": one row per feature of the step, in the order of the registry.
function R.Features(view, step)
  for _, def in ipairs(FL.Rows(step.rowsOf or step.id)) do
    if usable(def) then
      R.FeatureRow(view, def.id)
    end
  end
end

-- Pencil line ------------------------------------------------------------------------------------------

local PENCIL_ICON = 16

-- One line with the pencil of the menu (the same symbol as the button above the menu) and the sentence that says
-- what it does. The steps start, menu and done show it; while one of them is open the pencil in the menu glows
-- (SidebarEdit.SetHint). Returns the line.
function R.PencilLine(view)
  local holder = CreateFrame("Frame", nil, view.content or view.area.content)
  holder.fgId = "wizard-pencil-line"
  holder.icon = holder:CreateTexture(nil, "ARTWORK")
  holder.icon:SetSize(PENCIL_ICON, PENCIL_ICON)
  holder.icon:SetTexture(ns.UI_ICONS.pencil)
  holder.text = W.Text(holder, { key = "setup.pencil.line", role = "ui", color = "text", wrap = true })
  function holder:fgGridLayout(width)
    local indent = math.floor(PENCIL_ICON * 1.5)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("TOPLEFT", 0, -2)
    self.text:ClearAllPoints()
    self.text:SetPoint("TOPLEFT", indent, 0)
    self.text:SetWidth(math.max(40, width - indent))
    local h = math.max(PENCIL_ICON + 4, self.text:GetStringHeight())
    self:SetHeight(h)
    return h
  end
  view.stack:Add(holder, { gap = 10 })
  return holder
end

-- Restart line ----------------------------------------------------------------------------------------

local function reloadClick()
  ns.SaveUI.ConfirmedReload()
end

-- Block "restart": text and a reload button. It shows only while a sub-add-on that was switched off still
-- runs (it ends with the next reload). The reload starts from the click only, never from a timer.
function R.Restart(view)
  local row = CreateFrame("Frame", nil, view.area.content)
  row.fgId = "wizard-restart"
  row.text = W.Text(row, { key = "setup.restart.text", role = "ui", color = "warning", wrap = true })
  local width = pixels(150)
  row.button = W.Button(row, {
    key = "setup.restart.button",
    width = width,
    onClick = ns.SaveState.Click(reloadClick),
    tooltip = "setup.restart.button",
    tooltipText = "setup.restart.tip",
    variant = "primary",
  })
  row.button.fgId = "wizard-restart-button"
  row.button:SetPoint("TOPRIGHT")
  row.text:SetPoint("TOPLEFT", 0, -6)
  function row:fgGridLayout(w)
    local buttonW = math.max(width, math.ceil(self.button:GetWidth()))
    self.text:SetWidth(math.max(40, w - buttonW - R.GAP))
    local h = math.max(R.ROW_H, self.text:GetStringHeight() + 12)
    self:SetHeight(h)
    return h
  end
  function row:Refresh()
    local needed = #FL.PendingRestart() > 0
    if needed ~= self:IsShown() then
      self:SetShown(needed)
      view.relayout = true
    end
  end
  row:SetShown(#FL.PendingRestart() > 0)
  view.stack:Add(row, { gap = 8, reserve = true })
  view.widgets[#view.widgets + 1] = row
  view.rows[#view.rows + 1] = row
  return row
end

-- Summary of the menu ---------------------------------------------------------------------------------

local function names(list)
  return table.concat(list, ", ")
end

local function titleOf(kind, id)
  if kind == "g" then
    return L["nav.group." .. id]
  end
  local page = ns.Router and ns.Router:get(id)
  return page and page.title and L[page.title] or id
end

-- The entries of one raw menu text as a set { ["g:id"] = true, ["p:id"] = true }.
local function entrySet(raw)
  local set = {}
  for kind, id in tostring(raw or ""):gmatch("([gp]):([^,]+)") do
    set[kind .. ":" .. id] = true
  end
  return set
end

-- One side of the change: the entries in `now` that `before` did not have, as titles. A group comes by its
-- name alone, pages of a group that came along are not repeated; the other pages follow their group in
-- brackets ("Character (Inspect, Talents)").
local function side(before, now)
  local groups, pages, order = {}, {}, {}
  for entry in pairs(now) do
    if not before[entry] then
      local kind, id = entry:match("^([gp]):(.+)$")
      if kind == "g" then
        groups[id] = true
      else
        local page = ns.Router and ns.Router:get(id)
        local group = page and page.group or ""
        pages[group] = pages[group] or {}
        table.insert(pages[group], id)
      end
    end
  end
  local lines = {}
  for id in pairs(groups) do
    order[#order + 1] = id
  end
  table.sort(order)
  for _, id in ipairs(order) do
    lines[#lines + 1] = titleOf("g", id)
  end
  local groupIds = {}
  for group in pairs(pages) do
    if not groups[group] then
      groupIds[#groupIds + 1] = group
    end
  end
  table.sort(groupIds)
  for _, group in ipairs(groupIds) do
    local titles = {}
    table.sort(pages[group])
    for _, id in ipairs(pages[group]) do
      titles[#titles + 1] = titleOf("p", id)
    end
    local head = group ~= "" and titleOf("g", group) or nil
    lines[#lines + 1] = head and (head .. " (" .. names(titles) .. ")") or names(titles)
  end
  return lines
end

-- Lines for the summary of the wizard: what the menu step hid and what it showed again, from the raw texts of
-- SetupFeatureLogic.MenuRaw before and now.
function R.MenuLines(oldRaw, newRaw)
  local before, now = entrySet(oldRaw), entrySet(newRaw)
  local out = {}
  local hidden = side(before, now)
  if #hidden > 0 then
    out[#out + 1] = string.format(L["setup.summary.menuHidden"], names(hidden))
  end
  local shown = side(now, before)
  if #shown > 0 then
    out[#out + 1] = string.format(L["setup.summary.menuShown"], names(shown))
  end
  return out
end
