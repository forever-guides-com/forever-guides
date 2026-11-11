-- Setup wizard window: one step at a time, every control writes to the Store at once.
-- Opens by itself on a fresh install (5 s after entering the world, never in combat), by
-- /fg setup and by the buttons in Settings and Help. The window sits in the highest strata and a
-- guard keeps it there, /fg setup close and /fg setup skip close it without the mouse.
-- A button that opens a window of the add-on (settings, help, tutorials) leaves the wizard open and visible: UI.Reveal
-- puts the two windows next to each other. Only a screen too narrow for that folds the wizard to a bar at the top
-- of the screen (UI.Collapse, called by UI.Reveal alone), its button "Continue setup" (or /fg setup) brings the
-- step back (UI.Expand).
-- Size: one height for every step, so the buttons never move. It is the tallest step (with the options of every
-- row shown, see measureView) at the current font size, language and window zoom. Does that not fit the screen
-- (UI.SCREEN_SHARE of it), the window shrinks by its scale, down to UI.MIN_SHRINK. Only below that the step scrolls
-- (last resort, with a visible bar and a fade "more below").
-- Logic: Modules/SetupWizardLogic.lua, feature rows: Modules/SetupWizardRows.lua.
local _, ns = ...
local W, Theme, L, SW = ns.W, ns.Theme, ns.L, ns.SetupWizard
local R = ns.SetupWizardRows

local UI = {}
ns.SetupWizardUI = UI

UI.WIDTH, UI.MIN_HEIGHT = 540, 380
-- Share of the screen height the window may take, and how far its scale may shrink for that (1 = not at all).
UI.SCREEN_SHARE, UI.MIN_SHRINK = 0.85, 0.8
UI.OPEN_DELAY = 5

local TITLE_H, PROGRESS_H, FOOT_H, PAD = 40, 40, 56, 16
-- Height of the fade "more below" at the foot of a step that scrolls, and the room a focused control keeps from it.
local MORE_H = 34
-- What the summary of the closing step is measured with: a title line and four changes.
local SUMMARY_RESERVE = "-\n-\n-\n-\n-"
-- Room the "Step n of m" text keeps at the left of the progress line, the hint uses the rest.
local PROGRESS_W = 130
-- Left edge of the label of a toggle, where its hint text lines up.
local HINT_INDENT = R.HINT_INDENT
-- The folded window: a bar of this height, this far below the top edge of the screen. It stays in the
-- strata and at the level of the window (SW.GUARD), so it lies over the settings and the guard keeps it there.
local BAR_H, BAR_TOP = 44, 4

UI.LOGO = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png"
local LOGO_SIZE, ROW_BUTTON_W, ROW_MIN_H = 64, 100, 26

local frame, body, session
local views = {}
-- Folded to the bar; the point and size of the open window are kept for UI.Expand.
local collapsed, restore = false, nil
local keysReady = false
-- True while UI.Close hides the window; a hide without it is undone (restoreAfterHide).
local closing = false
-- Guard state: the corrections made, whether UIParent was hidden at the last check, the level the
-- window was raised to, the event frame and the ticker that exist while the window is open.
local guardCounts, uiHidden, baseLevel = {}, false, SW.GUARD.level
local watcher, ticker
local startGuard, stopGuard
local hintToken = 0
-- The tallest content of the session's steps, kept for the width, font size and steps it was measured for.
local measured
-- The step the window showed last (a new step starts at the top).
local shownId

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- Text and buttons grow with the font scale, so the window does too.
local factor = R.Factor

local function frameWidth()
  local width = math.floor(UI.WIDTH * factor() + 0.5)
  local screen = UIParent:GetWidth()
  if screen and screen > 0 then
    width = math.min(width, math.floor(screen * 0.9))
  end
  return width
end

local function inside(f, ancestor)
  local node = f
  for _ = 1, 40 do
    if not node then
      return false
    end
    if node == ancestor then
      return true
    end
    node = node.GetParent and node:GetParent() or nil
  end
  return false
end

-- Values ---------------------------------------------------------------------------------------

local function valueText(c, stored)
  if c.type == "toggle" then
    local on = stored and true or false
    if c.invert then
      on = not on
    end
    return L[on and "common.on" or "common.off"]
  elseif c.type == "feature" then
    -- stored: "on" or "off", see SW.Raw.
    return L[stored == "on" and "common.on" or "common.off"]
  elseif c.type == "consent" then
    -- stored: the letters of the flags that are on, see SW.Raw.
    local parts = {}
    for _, dir in ipairs({ "send", "receive" }) do
      if tostring(stored):find(dir == "send" and "S" or "R", 1, true) then
        parts[#parts + 1] = L["consent.flag." .. dir .. "." .. c.aud]
      end
    end
    return #parts > 0 and table.concat(parts, ", ") or L["common.off"]
  elseif c.type == "dropdown" then
    for _, o in ipairs(c.options) do
      if o.value == stored then
        return o.key and L[o.key] or o.text
      end
    end
  end
  return (c.format or tostring)(stored)
end

local function summaryText()
  if not session then
    return ""
  end
  local changes = session:Changes()
  if #changes == 0 then
    return L["setup.noChanges"]
  end
  local lines, located = { L["setup.changed"] }, false
  for _, change in ipairs(changes) do
    local c = change.control
    if c.type == "menu" then
      -- The menu is one control: its lines name the hidden and the shown entries.
      for _, line in ipairs(R.MenuLines(change.old, change.new)) do
        lines[#lines + 1] = "- " .. line
      end
    else
      local line = "- " .. L[c.labelKey] .. ": " .. valueText(c, change.new)
      if c.tab then
        located = true
        line = line .. " (" .. L["settings.feature." .. c.tab] .. ")"
      end
      lines[#lines + 1] = line
    end
  end
  if located then
    lines[#lines + 1] = L["setup.changeWhere"]
  end
  return table.concat(lines, "\n")
end

-- Step views -------------------------------------------------------------------------------------

local addConsent

local function addControl(view, c)
  local content, stack = view.area.content, view.stack
  local function get()
    return SW.Get(c)
  end
  local function set(value)
    SW.Put(c, value)
  end
  local widget
  if c.type == "custom" then
    widget = c.build({ stack = stack, content = content })
  elseif c.type == "consent" then
    widget = addConsent(view, c)
  elseif c.type == "toggle" then
    widget =
      W.Toggle(content, { key = c.labelKey, get = get, set = set, tooltip = c.labelKey, tooltipText = c.hintKey })
    stack:Add(widget, { height = 24, gap = c.hintKey and 0 or 8 })
    if c.hintKey then
      stack:Add(
        W.Text(content, { key = c.hintKey, role = "micro", color = c.hintColor or "textMuted", wrap = true }),
        { indent = HINT_INDENT, gap = 8 }
      )
    end
  elseif c.type == "slider" then
    widget = W.Slider(content, {
      key = c.labelKey,
      min = c.min,
      max = c.max,
      step = c.step,
      get = get,
      set = set,
      format = c.format,
      applyOn = c.applyOn,
    })
    stack:Add(widget, { height = 42, width = 320, gap = c.lowHintKey and 2 or 10 })
    if c.lowHintKey then
      -- Shown only while the value is very low (the opacity slider): a very transparent window is hard to read.
      local hint = W.Text(content, { key = c.lowHintKey, role = "micro", color = "warning", wrap = true })
      hint.fgId = "setup-low-hint"
      function hint:Refresh()
        local low = SW.IsVeryTransparent(get())
        if low ~= self:IsShown() then
          self:SetShown(low)
          view.relayout = true
        end
      end
      stack:Add(hint, { gap = 10, reserve = true })
      view.widgets[#view.widgets + 1] = hint
    end
  else
    widget = W.Dropdown(content, { key = c.labelKey, width = 240, options = c.options, get = get, set = set })
    stack:Add(widget, { height = 46, width = 240, gap = c.hintKey and 0 or 8 })
    if c.hintKey then
      stack:Add(W.Text(content, { key = c.hintKey, role = "micro", color = "textMuted", wrap = true }), { gap = 8 })
    end
  end
  if widget then
    view.widgets[#view.widgets + 1] = widget
  end
  return widget
end

-- Text on the left, one button on the right; grows with the wrapped text. tooltipKey names the button when its
-- label alone does not say what it acts on.
-- extra (optional): { variant = button variant, link = address shown under the text, width = button width,
-- opens = the button opens a window or page, see W.Action }.
local function addRow(view, textOpts, buttonKey, onClick, tooltipKey, extra)
  extra = extra or {}
  local row = CreateFrame("Frame", nil, view.area.content)
  local buttonWidth = math.floor((extra.width or ROW_BUTTON_W) * factor() + 0.5)
  local button = W.Button(row, {
    key = buttonKey,
    width = buttonWidth,
    onClick = onClick,
    tooltip = tooltipKey,
    variant = extra.variant,
    opens = extra.opens,
  })
  -- A button with the "opens" mark is wider than asked for: the text makes room for it.
  buttonWidth = math.max(buttonWidth, math.ceil(button:GetWidth()))
  button:SetPoint("TOPRIGHT")
  textOpts.role, textOpts.color, textOpts.wrap = "ui", "text", true
  row.text = W.Text(row, textOpts)
  row.text:SetPoint("TOPLEFT", 0, -6)
  if extra.link then
    row.link = W.Text(row, { text = extra.link, role = "ui", color = "accent2", wrap = true })
    row.link:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
  end
  row.button = button
  function row:fgGridLayout(width)
    row.text:SetWidth(math.max(40, width - buttonWidth - 12))
    local linkHeight = 0
    if row.link then
      row.link:SetWidth(math.max(40, width - buttonWidth - 12))
      linkHeight = row.link:GetStringHeight() + 2
    end
    local h = math.max(ROW_MIN_H, row.text:GetStringHeight() + linkHeight + 12)
    row:SetHeight(h)
    return h
  end
  view.stack:Add(row, { gap = 4 })
  view.rows[#view.rows + 1] = row
  return row
end

-- A sharing function: its name and audience on the left, a switch each for sending and receiving on
-- the right (below the name when the window is too narrow for both). Writes through SW.Put.
local SWITCH_W, NAME_MIN_W, COL_GAP = 160, 100, 8

-- The columns of a consent row at `width`: name and audience first, then the switch column of sending, then
-- that of receiving (x = left edge, w = column width). Too narrow for name and switches side by side:
-- the switches sit below the name, half the width each. The bulk buttons use the same columns.
local function consentColumns(width)
  local k = factor()
  local w, nameMin = math.floor(SWITCH_W * k + 0.5), math.floor(NAME_MIN_W * k + 0.5)
  local nameW = width - 2 * w - 2 * COL_GAP
  if nameW >= nameMin then
    return { beside = true, nameW = nameW, w = w, x = { nameW + COL_GAP, nameW + 2 * COL_GAP + w } }
  end
  local each = math.floor((width - COL_GAP) / 2)
  return { beside = false, nameW = width, w = each, x = { 0, each + COL_GAP } }
end

function addConsent(view, c)
  local row = CreateFrame("Frame", nil, view.area.content)
  row.fgId = "wizard-consent-" .. c.fn
  local name = W.Text(row, { key = c.labelKey, role = "ui", color = "text", wrap = true })
  local audience = W.Text(row, { key = "consent.aud." .. c.aud, role = "micro", color = "textMuted", wrap = true })
  row.switches = {}
  for _, dir in ipairs({ "send", "receive" }) do
    local switch = W.Toggle(row, {
      key = "consent." .. dir,
      get = function()
        return SW.Get(c, dir)
      end,
      set = function(value)
        SW.Put(c, value, dir)
      end,
      tooltip = "consent.flag." .. dir .. "." .. c.aud,
      tooltipText = c.hintKey,
    })
    switch.fgId = "wizard-consent-" .. c.fn .. "-" .. dir
    row.switches[#row.switches + 1] = switch
  end
  function row:Refresh()
    for _, switch in ipairs(self.switches) do
      switch.Refresh()
    end
  end
  function row:fgGridLayout(width)
    local cols = consentColumns(width)
    local beside, nameW = cols.beside, cols.nameW
    name:ClearAllPoints()
    name:SetPoint("TOPLEFT", 0, 0)
    name:SetWidth(nameW)
    audience:ClearAllPoints()
    audience:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    audience:SetWidth(nameW)
    local textH = name:GetStringHeight() + audience:GetStringHeight() + 1
    local top = beside and 0 or -(textH + 4)
    for i, switch in ipairs(self.switches) do
      switch:ClearAllPoints()
      switch:SetPoint("TOPLEFT", cols.x[i], top)
      switch:SetSize(cols.w, 24)
    end
    local h = math.max(ROW_MIN_H, beside and textH or textH + 4 + 24)
    row:SetHeight(h)
    return h
  end
  view.stack:Add(row, { gap = 8 })
  return row
end

-- "All on" and "all off" of sending and receiving, each pair over the switch column of its direction (the
-- columns of the consent rows). Too narrow for the columns: the pairs stack, each under its heading. "On" asks
-- first, "off" acts at once; only the functions shown in the step are touched (the same writes as the switches).
local DIRS = { "send", "receive" }

local function addBulk(view, step)
  local row = CreateFrame("Frame", nil, view.area.content)
  row.fgId = "wizard-bulk"
  row.heads, row.groups = {}, {}
  for i, dir in ipairs(DIRS) do
    row.heads[i] = W.Text(row, { key = "consent." .. dir, role = "micro", color = "textMuted" })
    row.groups[i] = ns.ConsentSettings.BulkButtons(row, dir, function(value)
      local targets = {}
      for _, c in ipairs(SW.ActiveControls(step)) do
        if c.type == "consent" then
          targets[#targets + 1] = c
        end
      end
      ns.ConsentSettings.BulkSwitch(targets, dir, value, function(c, v)
        SW.Put(c, v, dir)
      end)
    end, 28, true)
  end
  function row:fgGridLayout(width)
    local cols = consentColumns(width)
    local headH = math.ceil(math.max(self.heads[1]:GetStringHeight(), self.heads[2]:GetStringHeight()))
    local y, groupH = 0, 0
    for i = 1, #DIRS do
      local head, group = self.heads[i], self.groups[i]
      local x, w = cols.beside and cols.x[i] or 0, cols.beside and cols.w or width
      head:ClearAllPoints()
      head:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
      group:ClearAllPoints()
      group:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(y + headH + 2))
      group:SetWidth(w)
      local h = group:fgGridLayout(w)
      if cols.beside then
        groupH = math.max(groupH, h)
      else
        y = y + headH + 2 + h + 6
      end
    end
    local total = cols.beside and headH + 2 + groupH or y - 6
    self:SetHeight(total)
    return total
  end
  view.stack:Add(row, { gap = 8 })
  return row
end

-- Links go to the copy dialog: an addon cannot open a web page.
local LINKS = {
  {
    name = "Website",
    title = "help.websiteButton",
    url = function()
      return ns.Website
    end,
  },
}

-- What a step is made of, in the order its layout names them.
local BLOCKS = {
  logo = function(view)
    local holder = CreateFrame("Frame", nil, view.area.content)
    view.logo = holder:CreateTexture(nil, "ARTWORK")
    view.logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    view.logo:SetPoint("CENTER")
    view.logo:SetTexture(UI.LOGO)
    view.stack:Add(holder, { height = LOGO_SIZE + 8, gap = 8 })
  end,
  title = function(view, step)
    view.stack:Add(
      W.Text(
        view.area.content,
        { key = step.titleKey, role = "h3", family = "heading", color = "accent2", wrap = true }
      ),
      { gap = 6 }
    )
  end,
  text = function(view, step)
    if step.textKey then
      view.stack:Add(
        W.Text(view.area.content, { key = step.textKey, role = "text", color = "textSecondary", wrap = true }),
        { gap = 12 }
      )
    end
  end,
  links = function(view)
    for _, link in ipairs(LINKS) do
      local url = link.url() or ""
      local shown = (url:gsub("^https?://", ""))
      addRow(view, { text = link.name .. ": " .. shown }, "setup.copy", function()
        ns.Dialogs.Copy(link.title, link.url(), "help.copyHint")
      end, nil, { opens = true })
    end
  end,
  -- Feature rows, their options and the menu are drawn by their own blocks (features, menu).
  controls = function(view, step)
    for _, c in ipairs(SW.ActiveControls(step)) do
      if c.type ~= "feature" and c.type ~= "menu" and not c.owner then
        addControl(view, c)
      end
    end
  end,
  -- The privacy info of the Settings tab "Share" in the copy dialog.
  privacy = function(view)
    addRow(view, { key = "setup.sharing.privacy" }, "setup.sharing.more", function()
      ns.Dialogs.Copy("consent.privacy", ns.ConsentSettings.PrivacyText(), "consent.privacy.hint")
    end, "consent.privacy", { width = 120, opens = true })
  end,
  -- Send and receive of all functions of the step at once, over the switch columns.
  bulk = addBulk,
  -- The rest of the functions and the other audiences live in the Settings tab "Share".
  allSettings = function(view)
    addRow(view, { key = "setup.sharing.all.text" }, "setup.sharing.all", function()
      ns.SettingsPage.Select("privacy")
      ns.Main.Show("settings")
      UI.Reveal()
    end, nil, { width = 150, opens = true })
  end,
  summary = function(view)
    view.summary = W.Text(view.area.content, { role = "text", color = "text", wrap = true })
    view.stack:Add(view.summary, { gap = 12 })
    ns.Bind(view.summary, function(fs)
      fs:SetText(summaryText())
    end)
    view.reference[#view.reference + 1] = function(on)
      view.summary:SetText(on and SUMMARY_RESERVE or summaryText())
    end
  end,
  -- The livestream and the community server: texts, names and addresses come from ns.Channel and ns.Community
  -- (UI/MainFrame.lua, the one place of both), a button opens the copy dialog.
  community = function(view)
    local invites = {
      {
        text = "channel.row",
        title = "bar.channel",
        address = ns.Channel.address,
        shown = ns.Channel.text,
        variant = "stream",
      },
      {
        text = "community.row",
        title = "community.dialog",
        address = ns.Community.address,
        shown = ns.Community.text,
      },
    }
    for _, invite in ipairs(invites) do
      addRow(view, { key = invite.text }, "setup.copy", function()
        ns.Dialogs.Copy(invite.title, invite.address, "help.copyHint")
      end, invite.title, { variant = invite.variant, link = invite.shown, opens = true })
    end
  end,
  info = function(view)
    for _, info in ipairs({ { "tutorials", "setup.info.tutorials" }, { "help", "setup.info.help" } }) do
      addRow(view, { key = info[2] }, "setup.open", function()
        ns.Main.Show(info[1])
        UI.Reveal()
      end, nil, { opens = true })
    end
  end,
  -- One row per feature of the step (Modules/SetupFeatureData.lua), see Modules/SetupWizardRows.lua.
  features = R.Features,
  -- "Restart needed" with the reload button, only while a switched-off sub-add-on is still loaded.
  restart = R.Restart,
}
local DEFAULT_LAYOUT = { "title", "text", "controls" }

-- Lets a module of its own add a block (the menu step: UI.RegisterBlock("menu", function(view, step) .. end)).
-- A step names its blocks in step.layout; a block that is not known is skipped. Replaces a block of that name.
function UI.RegisterBlock(name, builder)
  if type(name) ~= "string" or type(builder) ~= "function" then
    return false
  end
  BLOCKS[name] = builder
  return true
end

-- The text and button row of the steps, for blocks of other modules: addRow(view, textOpts, buttonKey, onClick,
-- tooltipKey, extra) as described above.
UI.AddRow = addRow

-- The color of the window behind the fade; the fade follows the opacity of the window background.
local function setFade(texture, r, g, b, a)
  local ok = false
  if type(texture.SetGradient) == "function" then
    texture:SetColorTexture(1, 1, 1, 1)
    local color = rawget(_G, "CreateColor")
    if type(color) == "function" then
      ok = pcall(function()
        texture:SetGradient("VERTICAL", color(r, g, b, a), color(r, g, b, 0))
      end)
    end
  end
  if not ok and type(texture.SetGradientAlpha) == "function" then
    ok = pcall(texture.SetGradientAlpha, texture, "VERTICAL", r, g, b, a, r, g, b, 0)
  end
  if not ok then
    texture:SetColorTexture(r, g, b, a * 0.8)
  end
end

local function paintFade(more)
  local r, g, b = Theme.color("bg")
  local alpha = frame and frame.fgBack and frame.fgBack:GetAlpha() or 1
  setFade(more.fade, r, g, b, alpha)
end

-- "More below": a fade and a short text over the foot of a step that scrolls. It shows only while there is
-- more content below the visible part and never takes a click.
local function addMore(area)
  local more = CreateFrame("Frame", nil, area)
  more:SetPoint("BOTTOMLEFT")
  more:SetPoint("BOTTOMRIGHT")
  more:SetHeight(MORE_H)
  more:SetFrameLevel(area:GetFrameLevel() + 40)
  more.fade = more:CreateTexture(nil, "BACKGROUND")
  more.fade:SetAllPoints()
  more.label = W.Text(more, { key = "setup.moreBelow", role = "micro", color = "textSecondary" })
  more.label:SetPoint("BOTTOM", 8, 6)
  more.glyph = W.Glyph(more, "chevron-down", 12, "textSecondary")
  more.glyph:SetPoint("RIGHT", more.label, "LEFT", -4, 0)
  ns.Bind(more, paintFade)
  more:Hide()
  local update = area.bar.Update
  function area.bar.Update(bar, fraction, position)
    update(bar, fraction, position)
    local range = math.max(0, area.content:GetHeight() - area:GetHeight())
    more:SetShown(fraction < 1 and area:GetVerticalScroll() < range - 4)
  end
  area.more = more
end

local function newView(step)
  local area = W.ScrollArea(body)
  area:SetAllPoints(body)
  addMore(area)
  -- reference: functions that put the step in its tallest state while it is measured (fn(true)) and back (fn(false)).
  local view = { step = step, area = area, stack = W.Stack(area, 4), widgets = {}, rows = {}, reference = {} }
  for _, name in ipairs(step.layout or DEFAULT_LAYOUT) do
    if BLOCKS[name] then
      BLOCKS[name](view, step)
    end
  end
  area:Hide()
  views[step.id] = view
  return view
end

-- True when a control appeared or went away, so the step needs a new layout.
local function refreshView(view)
  for _, widget in ipairs(view.widgets) do
    if widget.Refresh then
      widget:Refresh()
    end
  end
  if view.summary then
    view.summary:SetText(summaryText())
  end
  local changed = view.relayout == true
  view.relayout = false
  return changed
end

local function layoutView(view)
  view.area.content:SetWidth(math.max(1, frameWidth() - 2 * PAD - 12))
  view.stack:Layout()
end

local function currentView()
  return session and views[session:Current().id]
end

-- The content height of a step in its tallest state: every feature row with its options shown, the lines that
-- come and go (a warning, "restart needed") present, the summary with a few changes. What the player does in the
-- step then never makes it taller than the window. The view is laid out again by the caller.
local function measureView(view)
  for _, entry in ipairs(view.stack.items) do
    if entry.opts.reserve then
      entry.opts.keepSpace = true
    end
  end
  for _, fn in ipairs(view.reference) do
    fn(true)
  end
  layoutView(view)
  local height = view.area.content:GetHeight()
  for _, fn in ipairs(view.reference) do
    fn(false)
  end
  for _, entry in ipairs(view.stack.items) do
    if entry.opts.reserve then
      entry.opts.keepSpace = nil
    end
  end
  return height
end

-- The tallest content of the steps of this session. All views are built here (once), so the first window
-- already has the size of the last step.
local function tallestContent()
  local ids = {}
  for _, step in ipairs(session.steps) do
    ids[#ids + 1] = step.id
  end
  local key = frameWidth() .. "|" .. factor() .. "|" .. table.concat(ids, ",")
  if measured and measured.key == key then
    return measured.height
  end
  local tallest = 0
  for _, step in ipairs(session.steps) do
    tallest = math.max(tallest, measureView(views[step.id] or newView(step)))
  end
  measured = { key = key, height = tallest }
  return tallest
end

-- One size for every step (see the head of the file). Returns the scale the window has now.
local function fit()
  local view = currentView()
  if not view then
    return
  end
  if collapsed then
    frame:SetSize(frameWidth(), BAR_H)
    return
  end
  frame:SetWidth(frameWidth())
  frame.hint:SetPoint("TOPLEFT", PAD + math.floor(PROGRESS_W * factor() + 0.5), -(TITLE_H + 8))
  local want = TITLE_H + PROGRESS_H + FOOT_H + tallestContent() + 8
  local base = Theme.windowScale()
  local scale, limit = base, nil
  local screen = UIParent:GetHeight()
  if screen and screen > 0 then
    local room = screen * UI.SCREEN_SHARE
    if want * base > room then
      scale = base * math.max(UI.MIN_SHRINK, room / (want * base))
    end
    limit = math.floor(room / scale)
  end
  if frame:GetScale() ~= scale then
    frame:SetScale(scale)
  end
  local height = limit and math.min(math.ceil(want), limit) or math.ceil(want)
  frame:SetHeight(math.max(math.min(UI.MIN_HEIGHT, limit or UI.MIN_HEIGHT), height))
  layoutView(view)
  return scale
end

-- Window ---------------------------------------------------------------------------------------

local function paintProgress()
  if not (frame and session) then
    return
  end
  local n, m = session:Progress()
  local progress = string.format(L["setup.progress"], n, m)
  frame.progress:SetText(progress)
  frame.barText:SetText(L["setup.title"] .. ", " .. progress)
  frame.fill:SetWidth(math.max(1, (frame:GetWidth() - 2 * PAD) * n / m))
end

local function paintButtons()
  local last = session:IsLast()
  W.SetText(frame.next.label, last and "setup.finish" or "setup.next")
  W.SetText(frame.skip.label, session.firstRun and "setup.skip" or "setup.close")
  frame.back:SetEnabled(not session:IsFirst())
end

-- The pencil in the menu glows while the window shows a step that talks about the menu.
local PENCIL_STEPS = { start = true, menu = true, menu2 = true, done = true }

local function paintPencilHint()
  local SE = ns.SidebarEdit
  if not (SE and SE.SetHint) then
    return
  end
  local step = frame and frame:IsShown() and session and session:Current()
  SE.SetHint(step ~= nil and step ~= false and PENCIL_STEPS[step.id] == true)
end

local function render()
  local step = session:Current()
  local view = views[step.id] or newView(step)
  for _, other in pairs(views) do
    other.area:SetShown(other == view)
  end
  refreshView(view)
  if ns.Focus.current and inside(ns.Focus.current, frame) then
    ns.Focus.clear()
  end
  paintButtons()
  fit()
  -- A new step starts at the top; the same step again (reset, back from the bar) keeps its place.
  if shownId ~= step.id then
    view.area:ScrollTo(0)
    shownId = step.id
  end
  paintProgress()
  paintPencilHint()
end

function UI.View(id)
  return views[id]
end

function UI.IsOpen()
  return frame ~= nil and frame:IsShown()
end

-- Every way out of the window ends here (Done, a confirmed close, Skip, /fg setup close): a hide from anywhere
-- else is not a decision of the player and is taken back, see the OnHide script.
function UI.Close()
  if frame then
    closing = true
    frame:Hide()
    closing = false
  end
end

-- Lays the current step out again after something changed outside a click on the step (a switch of a row).
function UI.Refresh()
  local view = currentView()
  if view and refreshView(view) then
    fit()
  end
end

-- The parts only the open window shows; the bar shows frame.barText and frame.resume instead.
local function openParts()
  return {
    body,
    frame.progress,
    frame.track,
    frame.fill,
    frame.footLine,
    frame.resetAll,
    frame.skip,
    frame.next,
    frame.back,
    frame.titleText,
  }
end

local function showBar(on)
  frame.barText:SetShown(on)
  frame.resume:SetShown(on)
  for _, part in ipairs(openParts()) do
    part:SetShown(not on)
  end
end

function UI.IsCollapsed()
  return collapsed
end

-- Folds the window to the bar at the top of the screen so the settings that were just opened are not covered.
-- The step, the session and the guard stay as they are. Returns whether it folded.
function UI.Collapse()
  if collapsed or not (frame and frame:IsShown() and session) then
    return false
  end
  local point, rel, relPoint, x, y = frame:GetPoint()
  restore = { point = point, rel = rel, relPoint = relPoint, x = x, y = y, hint = frame.hint:IsShown() }
  collapsed = true
  if ns.Focus.current and inside(ns.Focus.current, frame) then
    ns.Focus.clear()
  end
  showBar(true)
  frame.hint:Hide()
  frame:ClearAllPoints()
  frame:SetPoint("TOP", UIParent, "TOP", 0, -BAR_TOP)
  frame:SetSize(frameWidth(), BAR_H)
  paintProgress()
  UI.Front(true)
  return true
end

-- Puts the open window back where and as large as it was (no new layout, see UI.Expand).
local function unfold()
  collapsed = false
  showBar(false)
  frame:ClearAllPoints()
  local r = restore or {}
  frame:SetPoint(r.point or "CENTER", r.rel or UIParent, r.relPoint or r.point or "CENTER", r.x or 0, r.y or 0)
  frame.hint:SetShown(r.hint == true)
  restore = nil
end

-- The way back from the bar: the same step, size and position as before.
function UI.Expand()
  if not (collapsed and frame) then
    return false
  end
  unfold()
  if session then
    render()
  end
  UI.Front(true)
  return true
end

-- Next to the main window -------------------------------------------------------------------------------
-- A button of the wizard that opens a window of the add-on (settings, tutorials, help, the menu edit mode) calls
-- UI.Reveal afterwards. The wizard never closes, folds or hides for it: the two windows are put next to each other,
-- on a screen that is too narrow the main window lies over the wizard (raised to its strata, the wizard keeps its
-- place and stays visible). Only a screen too narrow even for that folds the wizard to its bar.

-- The main window before the wizard moved or raised it: { frame, point = { GetPoint }, strata, left, pinned }.
local placed

local function mainFrame()
  local main = ns.Main and ns.Main.frame
  return main and main:IsShown() and main or nil
end

-- Screen units: the frame's own units times its effective scale. nil while the client has no rectangle yet.
local function screenRect(f)
  local scale = f:GetEffectiveScale() or 1
  local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
  if not (l and r and t and b) then
    return nil
  end
  return { l = l * scale, r = r * scale, t = t * scale, b = b * scale }
end

local function moveTo(f, left, rect)
  local scale = f:GetEffectiveScale() or 1
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, rect.t / scale)
end

local function setStrata(f, strata)
  if f:GetFrameStrata() ~= strata then
    f:SetFrameStrata(strata)
  end
end

-- The main window back to its own strata (it no longer needs to lie over the wizard).
local function unpinMain()
  if placed and placed.pinned then
    placed.pinned = false
    pcall(setStrata, placed.frame, placed.strata)
  end
end

-- The main window as it was: strata and, when the player did not move it since, its position.
local function releaseMain()
  local p = placed
  if not p then
    return
  end
  unpinMain()
  placed = nil
  local now = screenRect(p.frame)
  if p.point and p.point[1] and now and math.abs(now.l - p.left) < 2 then
    p.frame:ClearAllPoints()
    p.frame:SetPoint(unpack(p.point))
  end
end

-- Returns whether the window of the add-on is placed next to the wizard (or needs no move).
function UI.Reveal()
  local main = mainFrame()
  if collapsed or not (frame and frame:IsShown() and session and main) then
    return false
  end
  local setup, rect = screenRect(frame), screenRect(main)
  local screenW = UIParent:GetWidth() * (UIParent:GetEffectiveScale() or 1)
  if not (setup and rect and screenW and screenW > 0) then
    return false
  end
  local plan = SW.Placement({ w = screenW }, setup, rect)
  if plan.mode == "apart" then
    unpinMain()
    return true
  elseif plan.mode == "bar" then
    unpinMain()
    return UI.Collapse()
  end
  if not placed or placed.frame ~= main then
    local point, rel, relPoint, x, y = main:GetPoint()
    placed = { frame = main, point = point and { point, rel, relPoint, x, y }, strata = main:GetFrameStrata() }
  end
  if plan.setupLeft then
    moveTo(frame, plan.setupLeft, setup)
  end
  moveTo(main, plan.mainLeft, rect)
  placed.left = plan.mainLeft
  if plan.mode == "over" then
    placed.pinned = true
    setStrata(main, SW.GUARD.strata)
    main:Raise()
  else
    unpinMain()
  end
  return true
end

function UI.Next()
  if not session then
    return
  end
  if session:IsLast() then
    session:Finish()
    UI.Close()
  elseif session:Next() then
    render()
  end
end

function UI.Back()
  if session and session:Back() then
    render()
  end
end

function UI.AskCancel()
  if not session then
    return
  end
  ns.Dialogs.Confirm("setup.cancelTitle", "setup.cancelText", function()
    if session then
      session:Cancel()
      UI.Close()
    end
  end, nil, { yesKey = "setup.close", noKey = "setup.collapse.resume" })
end

-- A first run loads the defaults for the wizard's keys. Later runs only close: the user's
-- own settings stay.
function UI.Skip()
  if not session then
    return
  end
  if not session.firstRun then
    UI.AskCancel()
    return
  end
  ns.Dialogs.Confirm("setup.skipTitle", "setup.skipText", function()
    if session then
      session:Skip()
      UI.Close()
    end
  end)
end

-- The way out without the mouse and without a dialog (/fg setup close, /fg setup skip). Skip
-- applies the defaults only on a first run, like the Skip button. Returns whether a window was open.
function UI.CloseNow()
  if not (session and UI.IsOpen()) then
    return false
  end
  session:Cancel()
  UI.Close()
  return true
end

function UI.SkipNow()
  if not (session and UI.IsOpen()) then
    return false
  end
  if session.firstRun then
    session:Skip()
  else
    session:Cancel()
  end
  UI.Close()
  return true
end

function UI.ResetAll()
  if not session then
    return
  end
  ns.Dialogs.Confirm("setup.resetTitle", "setup.resetText", function()
    SW.ResetToDefaults()
    if session then
      render()
    end
  end)
end

-- Keyboard ---------------------------------------------------------------------------------------

-- Controls of the step first, then the footer buttons.
local function focusList()
  local controls, footer = {}, {}
  for _, f in ipairs(ns.Focus.items) do
    if f:IsVisible() and (not f.IsEnabled or f:IsEnabled()) and inside(f, frame) then
      local list = inside(f, body) and controls or footer
      list[#list + 1] = f
    end
  end
  for _, f in ipairs(footer) do
    controls[#controls + 1] = f
  end
  return controls
end

-- Scrolls the step (when it scrolls at all) so a control that got the keyboard focus lies in the visible part.
local function scrollIntoView(f)
  local view = currentView()
  if not (view and f and inside(f, view.area.content)) then
    return
  end
  local area, content = view.area, view.area.content
  local contentTop, top, bottom = content:GetTop(), f:GetTop(), f:GetBottom()
  local visible = area:GetHeight()
  if not (contentTop and top and bottom and visible) then
    return
  end
  local from, to, scroll = contentTop - top, contentTop - bottom, area:GetVerticalScroll()
  if from < scroll + 4 then
    area:ScrollTo(from - 4)
  elseif to > scroll + visible - MORE_H then
    area:ScrollTo(to - visible + MORE_H)
  end
end

local function moveFocus(step)
  local list = focusList()
  if #list == 0 then
    return
  end
  local index = 0
  for i, f in ipairs(list) do
    if f == ns.Focus.current then
      index = i
    end
  end
  index = index + step
  if index < 1 then
    index = #list
  elseif index > #list then
    index = 1
  end
  ns.Focus.set(list[index])
  scrollIntoView(list[index])
end

local function handleKey(key)
  -- Folded to the bar: every key belongs to the settings below it.
  if collapsed then
    return false
  end
  local current = ns.Focus.current
  -- A dropdown list lives outside the window: it keeps its own keys.
  local inPopup = current ~= nil and not inside(current, frame)
  if key == "ESCAPE" then
    -- An open list, then the newest dialog or window next to the wizard (the settings, a note) closes; only
    -- when nothing else is open does Esc ask whether to cancel the setup.
    if ns.EscStack.Close(frame) then
      return true
    end
    UI.AskCancel()
    return true
  elseif key == "TAB" then
    moveFocus(IsShiftKeyDown() and -1 or 1)
    return true
  elseif key == "UP" or key == "DOWN" then
    if inPopup then
      ns.Focus.move(key == "UP" and -1 or 1)
    else
      moveFocus(key == "UP" and -1 or 1)
    end
    return true
  elseif key == "SPACE" then
    return current ~= nil and ns.Focus.activate()
  elseif key == "ENTER" then
    if current and (inPopup or not inside(current, body)) then
      return ns.Focus.activate()
    end
    UI.Next()
    return true
  elseif key == "LEFT" or key == "RIGHT" then
    if current and current.fgArrow and not inPopup then
      current:fgArrow(key == "LEFT" and -1 or 1)
    elseif key == "LEFT" then
      UI.Back()
    else
      UI.Next()
    end
    return true
  end
  return false
end

-- Propagation cannot change in combat, so the keys wait for combat to end.
local function setupKeys()
  if keysReady or not frame or not ns.can.propagateKeyboard or inCombat() then
    return
  end
  keysReady = true
  ns.PropagateKeys(frame, true)
  frame:EnableKeyboard(true)
  frame:SetScript("OnKeyDown", function(self, key)
    if inCombat() then
      return
    end
    local _, handled = ns.Safe("setup-key", handleKey, key)
    ns.PropagateKeys(self, not handled)
  end)
end

-- Guard ----------------------------------------------------------------------------------------

-- A dialog or dropdown list of the wizard is open: the window does not rise over it.
local function coverOpen()
  if next(ns.Dialogs.open) ~= nil then
    return true
  end
  return ns.Popups.isOpen()
end

-- The background is an exact preview of the window opacity of the Settings (0 = invisible). Only the background
-- fades: the frame itself, its text, buttons and the title strip stay at full alpha. The edge line and the
-- drop shadow stay (border = true), the text carries its own shadow (Theme.applyFont).
local function applyLook()
  if not frame then
    return
  end
  local alpha = SW.BackgroundAlpha(Theme.mainAlpha() * 100)
  frame.fgBack:SetAlpha(alpha)
  for _, view in pairs(views) do
    paintFade(view.area.more)
  end
  local shell = ns.WindowShell.Of(frame)
  ns.WindowStyle.Apply(frame, {
    bg = ns.WindowStyle.FALLBACK.bg,
    alpha = alpha,
    autoHide = false,
    textShadow = "off",
    border = true,
    solidBar = true,
  }, { border = shell.border, shadow = shell.shadow })
end

-- Puts back what the game or another add-on changed (strata, level, mouse, alpha) and counts it.
-- raise: also bring the window to the front (opening, events); the ticker only corrects.
function UI.Front(raise)
  if not frame or not frame:IsShown() or inCombat() then
    return
  end
  local fixes, hidden = SW.GuardCheck({
    strata = frame:GetFrameStrata(),
    level = frame:GetFrameLevel(),
    wantLevel = baseLevel,
    mouse = frame:IsMouseEnabled(),
    alpha = frame:GetAlpha(),
    uiShown = UIParent:IsShown(),
  })
  uiHidden = hidden
  local lifted = false
  for _, fix in ipairs(fixes) do
    if fix == "strata" then
      frame:SetFrameStrata(SW.GUARD.strata)
      lifted = true
    elseif fix == "level" then
      lifted = true
    elseif fix == "mouse" then
      frame:EnableMouse(true)
    elseif fix == "alpha" then
      frame:SetAlpha(1)
    end
  end
  SW.GuardRecord(guardCounts, fixes)
  if (raise or lifted) and not coverOpen() then
    frame:Raise()
    baseLevel = frame:GetFrameLevel()
    -- A main window that lies over the wizard on a narrow screen stays over it.
    if placed and placed.pinned and placed.frame:IsShown() then
      placed.frame:Raise()
    end
    ns.Focus.Lift()
  end
end

function UI.GuardInfo()
  return { counts = guardCounts, uiHidden = uiHidden, frame = frame, session = session ~= nil }
end

startGuard = function()
  if not watcher then
    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", function()
      ns.Safe("setup-guard-event", UI.Front, true)
    end)
  end
  for _, event in ipairs(SW.GUARD_EVENTS) do
    pcall(watcher.RegisterEvent, watcher, event)
  end
  local timer = rawget(_G, "C_Timer")
  if not ticker and type(timer) == "table" and type(timer.NewTicker) == "function" then
    ticker = timer.NewTicker(SW.GUARD.interval, function()
      ns.Safe("setup-guard", UI.Front, false)
    end)
  end
end

stopGuard = function()
  if watcher then
    for _, event in ipairs(SW.GUARD_EVENTS) do
      pcall(watcher.UnregisterEvent, watcher, event)
    end
  end
  if ticker then
    ticker:Cancel()
    ticker = nil
  end
end

-- Construction ---------------------------------------------------------------------------------

local function build()
  frame = CreateFrame("Frame", "ForeverGuidesSetupWizard", UIParent)
  frame:SetSize(UI.WIDTH, UI.MIN_HEIGHT)
  frame:SetPoint("CENTER")
  -- Strata and level come before the first child: SetFrameLevel moves only the frame itself, the
  -- children created below lie above it. Dialogs, dropdown lists and the focus ring lift over it (ns.TopLayer).
  -- No Toplevel: a click would raise the window over the focus ring and the confirm dialog.
  frame:SetFrameStrata(SW.GUARD.strata)
  pcall(frame.SetFrameLevel, frame, SW.GUARD.level)
  if frame.SetFixedFrameStrata then
    frame:SetFixedFrameStrata(true)
  end
  ns.TopLayer.owner = frame
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  W.Fill(frame, "bg", 0.97)
  -- esc = false: the wizard never closes on a plain Esc. Its own key handler closes a dialog or another window
  -- first and asks before it ends the setup (handleKey).
  local shell = ns.WindowShell.Attach(
    frame,
    { title = "setup.title", role = "h2", titleHeight = TITLE_H, shadow = true, esc = false }
  )
  local close =
    W.Action(shell.titleBar, { icon = "close", size = 22, tooltip = "common.close", onClick = UI.AskCancel })
  close:SetPoint("RIGHT", -8, 0)
  frame.titleText = shell.titleText
  shell.titleText:ClearAllPoints()
  shell.titleText:SetPoint("LEFT", 16, 0)
  shell.titleText:SetPoint("RIGHT", close, "LEFT", -8, 0)

  frame.progress = W.Text(frame, { role = "ui", color = "textSecondary" })
  frame.progress:SetPoint("TOPLEFT", PAD, -(TITLE_H + 8))
  ns.Bind(frame.progress, paintProgress)
  -- Shown for the first seconds of an automatic start: the way out when the mouse is blocked.
  frame.hint = W.Text(frame, { key = "setup.escapeHint", role = "ui", color = "textSecondary", justify = "RIGHT" })
  frame.hint:SetPoint("TOPLEFT", PAD + PROGRESS_W, -(TITLE_H + 8))
  frame.hint:SetPoint("TOPRIGHT", -PAD, -(TITLE_H + 8))
  frame.hint:Hide()
  local track = frame:CreateTexture(nil, "ARTWORK")
  frame.track = track
  track:SetPoint("TOPLEFT", PAD, -(TITLE_H + PROGRESS_H - 14))
  track:SetPoint("TOPRIGHT", -PAD, -(TITLE_H + PROGRESS_H - 14))
  track:SetHeight(4)
  frame.fill = frame:CreateTexture(nil, "OVERLAY")
  frame.fill:SetPoint("TOPLEFT", PAD, -(TITLE_H + PROGRESS_H - 14))
  frame.fill:SetHeight(4)
  ns.Bind(track, function()
    track:SetColorTexture(Theme.color("surface3"))
    frame.fill:SetColorTexture(Theme.color("accent2"))
  end)

  body = CreateFrame("Frame", nil, frame)
  body:SetPoint("TOPLEFT", PAD, -(TITLE_H + PROGRESS_H))
  body:SetPoint("BOTTOMRIGHT", -PAD, FOOT_H)

  -- A thin line over the footer: the buttons sit under it at the same place in every step.
  frame.footLine = frame:CreateTexture(nil, "ARTWORK")
  frame.footLine:SetPoint("BOTTOMLEFT", PAD, FOOT_H)
  frame.footLine:SetPoint("BOTTOMRIGHT", -PAD, FOOT_H)
  frame.footLine:SetHeight(1)
  ns.Bind(frame.footLine, function(line)
    line:SetColorTexture(Theme.color("surface3"))
  end)

  local k = factor()
  local function button(key, width, onClick, variant)
    return W.Button(frame, { key = key, width = math.floor(width * k + 0.5), onClick = onClick, variant = variant })
  end
  frame.resetAll = button("setup.resetAll", 150, UI.ResetAll)
  frame.resetAll:SetPoint("BOTTOMLEFT", PAD, 14)
  frame.skip = button("setup.skip", 120, UI.Skip)
  frame.skip:SetPoint("LEFT", frame.resetAll, "RIGHT", 8, 0)
  frame.next = button("setup.next", 100, UI.Next, "primary")
  frame.next:SetPoint("BOTTOMRIGHT", -PAD, 14)
  frame.back = button("setup.back", 90, UI.Back)
  frame.back:SetPoint("RIGHT", frame.next, "LEFT", -8, 0)

  -- The folded window: "Setup, Step n of m" and the way back. Hidden while the window is open.
  frame.resume = W.Button(shell.titleBar, {
    key = "setup.collapse.resume",
    width = math.floor(150 * k + 0.5),
    onClick = UI.Expand,
    variant = "primary",
    tooltip = "setup.collapse.resume",
    tooltipText = "setup.collapse.tip",
  })
  frame.resume:SetPoint("RIGHT", close, "LEFT", -8, 0)
  frame.barText = W.Text(shell.titleBar, { role = "ui", color = "text" })
  frame.barText:SetPoint("LEFT", 16, 0)
  frame.barText:SetPoint("RIGHT", frame.resume, "LEFT", -8, 0)
  frame.resume:Hide()
  frame.barText:Hide()

  applyLook()
  -- A click on the visible part of the wizard brings it over a main window that lies over it.
  frame:HookScript("OnMouseDown", function()
    if placed and placed.pinned and not coverOpen() then
      frame:Raise()
    end
  end)
  frame:SetScript("OnShow", function()
    frame:SetScale(Theme.windowScale())
    applyLook()
    UI.Front(true)
    startGuard()
  end)
  -- The window closes only through UI.Close (Done, a confirmed close, Skip). Anything else that hides it (a
  -- panel of the game, another add-on, the settings opening) is undone on the next frame with the session and
  -- the step intact. A hidden UIParent leaves the frame shown, that is no close.
  frame:SetScript("OnHide", function()
    if frame:IsShown() then
      return
    end
    if not closing and session and not session.closed then
      guardCounts.hidden = (guardCounts.hidden or 0) + 1
      C_Timer.After(0, function()
        if frame and session and not session.closed and not frame:IsShown() then
          frame:Show()
        end
      end)
      return
    end
    stopGuard()
    releaseMain()
    -- Closed as a bar: the next opening starts as the full window again.
    if collapsed then
      unfold()
    end
    local open = session
    session = nil
    paintPencilHint()
    if open and not open.closed then
      open:Cancel()
    end
  end)
  frame:Hide()
end

-- opts.onlyNew: only the steps this user has not seen yet; opts.auto: started by the addon, the window
-- shows the way out for the first seconds. Returns whether the window opened.
function UI.Open(opts)
  if not ns.db then
    return false
  end
  if frame and frame:IsShown() then
    if collapsed then
      UI.Expand()
    end
    frame:Raise()
    UI.Reveal()
    return true
  end
  local fresh = SW.Begin(opts)
  if not fresh then
    ns.Notify(L["setup.nothingNew"], "info")
    return false
  end
  if not frame then
    build()
  end
  session = fresh
  shownId = nil
  guardCounts, uiHidden, baseLevel = {}, false, SW.GUARD.level
  for _, view in pairs(views) do
    view.area:Hide()
  end
  hintToken = hintToken + 1
  frame.hint:SetShown(opts ~= nil and opts.auto == true)
  frame:Show()
  setupKeys()
  render()
  -- Started from the settings or the help: the main window that is open makes room.
  UI.Reveal()
  if opts and opts.auto then
    local token = hintToken
    C_Timer.After(SW.GUARD.hintSeconds, function()
      if token == hintToken and frame then
        frame.hint:Hide()
      end
    end)
  end
  return true
end

-- Events ---------------------------------------------------------------------------------------

ns.On("FG_UI_REFRESHED", function()
  -- Font size, language or theme changed: the texts have other sizes, the window is measured again.
  measured = nil
  if UI.IsOpen() and session then
    applyLook()
    fit()
    paintProgress()
  end
end)

ns.On("FG_SETTING_CHANGED", function(_, path)
  if not (UI.IsOpen() and session) then
    return
  end
  if path == "settings.scale" then
    fit()
  elseif path == "settings.mainAlpha" then
    applyLook()
  end
  local view = currentView()
  if view and refreshView(view) then
    fit()
  end
end)

-- The main window opened by any way while the wizard is open (a button, the minimap, /fg): it goes next to the wizard.
ns.On("FG_MAIN_SHOWN", function()
  if UI.IsOpen() then
    -- One frame later: the main window has its size and position by then.
    C_Timer.After(0, function()
      ns.Safe("setup-reveal", UI.Reveal)
    end)
  end
end)
ns.On("FG_MAIN_HIDDEN", function()
  releaseMain()
end)

-- A consent changed elsewhere while the window is open: the switches follow.
local function onConsentChanged()
  local view = UI.IsOpen() and session and currentView()
  if view then
    refreshView(view)
  end
end
ns.On("FG_CONSENT_CHANGED", onConsentChanged)
ns.On("FG_CONSENT_WITHDRAWN", onConsentChanged)

-- Automatic start ------------------------------------------------------------------------------

local inWorld, waiting, scheduled, handled = false, false, false, false

local function run()
  scheduled = false
  if handled or not ns.db then
    return
  end
  -- Loading screen or combat: the next entering-world or combat-end event tries again.
  if not inWorld or inCombat() then
    waiting = true
    return
  end
  waiting, handled = false, true
  SW.Baseline()
  if SW.ShouldAutoOpen() then
    if UI.Open({ auto = true }) then
      ns.Log.info("setup: opened automatically, strata=%s level=%s", frame:GetFrameStrata(), frame:GetFrameLevel())
    end
  elseif SW.NoticeDue() then
    -- New steps are reached with "new", which skips everything this user has seen.
    local text = #SW.Pending() > 0 and L["setup.noticeNew"] or L["setup.notice"]
    SW.MarkNotified()
    ns.Notify(text, "info")
  end
end

local function schedule()
  if handled or scheduled then
    return
  end
  scheduled = true
  C_Timer.After(UI.OPEN_DELAY, function()
    ns.Safe("setup-auto", run)
  end)
end

ns.On("PLAYER_ENTERING_WORLD", function()
  inWorld = true
  schedule()
end)
ns.On("PLAYER_LEAVING_WORLD", function()
  inWorld = false
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  setupKeys()
  if waiting then
    schedule()
  end
end)
