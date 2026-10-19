-- Setup wizard window: one step at a time, every control writes to the Store at once.
-- Opens by itself on a fresh install (2 s after entering the world, never in combat), by
-- /fg setup and by the buttons in Settings and Help. Logic: Modules/SetupWizardLogic.lua.
local _, ns = ...
local W, Theme, L, SW = ns.W, ns.Theme, ns.L, ns.SetupWizard

local UI = {}
ns.SetupWizardUI = UI

UI.WIDTH, UI.MIN_HEIGHT, UI.MAX_HEIGHT = 540, 380, 640
UI.OPEN_DELAY = 2

local TITLE_H, PROGRESS_H, FOOT_H, PAD = 40, 40, 56, 16
-- Left edge of the label of a toggle, where its hint text lines up.
local HINT_INDENT = 76

UI.LOGO = "Interface\\AddOns\\ForeverGuides\\Media\\Logo.png"
local LOGO_SIZE, ROW_BUTTON_W, ROW_MIN_H = 64, 100, 26

local frame, body, session
local views = {}
local keysReady = false

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- Text and buttons grow with the font scale, so the window does too.
local function factor()
  local v = ns.db and tonumber(ns.db.settings.fontScale) or 1
  return math.max(1, v or 1)
end

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
    local line = "- " .. L[c.labelKey] .. ": " .. valueText(c, change.new)
    if c.tab then
      located = true
      line = line .. " (" .. L["settings.tab." .. c.tab] .. ")"
    end
    lines[#lines + 1] = line
  end
  if located then
    lines[#lines + 1] = L["setup.changeWhere"]
  end
  return table.concat(lines, "\n")
end

-- Step views -------------------------------------------------------------------------------------

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
    stack:Add(widget, { height = 42, width = 320, gap = 10 })
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
-- extra (optional): { variant = button variant, link = address shown under the text }.
local function addRow(view, textOpts, buttonKey, onClick, tooltipKey, extra)
  extra = extra or {}
  local row = CreateFrame("Frame", nil, view.area.content)
  local buttonWidth = math.floor(ROW_BUTTON_W * factor() + 0.5)
  local button = W.Button(
    row,
    { key = buttonKey, width = buttonWidth, onClick = onClick, tooltip = tooltipKey, variant = extra.variant }
  )
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
      end)
    end
  end,
  controls = function(view, step)
    for _, c in ipairs(SW.ActiveControls(step)) do
      addControl(view, c)
    end
  end,
  summary = function(view)
    view.summary = W.Text(view.area.content, { role = "text", color = "text", wrap = true })
    view.stack:Add(view.summary, { gap = 12 })
    ns.Bind(view.summary, function(fs)
      fs:SetText(summaryText())
    end)
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
      end, invite.title, { variant = invite.variant, link = invite.shown })
    end
  end,
  info = function(view)
    for _, info in ipairs({ { "tutorials", "setup.info.tutorials" }, { "help", "setup.info.help" } }) do
      addRow(view, { key = info[2] }, "setup.open", function()
        ns.Main.Show(info[1])
      end)
    end
  end,
}
local DEFAULT_LAYOUT = { "title", "text", "controls" }

local function newView(step)
  local area = W.ScrollArea(body)
  area:SetAllPoints(body)
  local view = { step = step, area = area, stack = W.Stack(area, 4), widgets = {}, rows = {} }
  for _, name in ipairs(step.layout or DEFAULT_LAYOUT) do
    if BLOCKS[name] then
      BLOCKS[name](view, step)
    end
  end
  area:Hide()
  views[step.id] = view
  return view
end

local function refreshView(view)
  for _, widget in ipairs(view.widgets) do
    if widget.Refresh then
      widget:Refresh()
    end
  end
  if view.summary then
    view.summary:SetText(summaryText())
  end
end

local function layoutView(view)
  view.area.content:SetWidth(math.max(1, frameWidth() - 2 * PAD - 12))
  view.stack:Layout()
end

local function currentView()
  return session and views[session:Current().id]
end

-- Grows with the content up to the screen, then the step scrolls.
local function fit()
  local view = currentView()
  if not view then
    return
  end
  frame:SetWidth(frameWidth())
  layoutView(view)
  local screen = UIParent:GetHeight()
  local limit = UI.MAX_HEIGHT
  if screen and screen > 0 then
    limit = math.min(limit, math.floor(screen / (frame:GetScale() or 1) * 0.9))
  end
  local want = TITLE_H + PROGRESS_H + FOOT_H + view.area.content:GetHeight() + 8
  frame:SetHeight(math.max(math.min(UI.MIN_HEIGHT, limit), math.min(want, limit)))
end

-- Window ---------------------------------------------------------------------------------------

local function paintProgress()
  if not (frame and session) then
    return
  end
  local n, m = session:Progress()
  frame.progress:SetText(string.format(L["setup.progress"], n, m))
  frame.fill:SetWidth(math.max(1, (frame:GetWidth() - 2 * PAD) * n / m))
end

local function paintButtons()
  local last = session:IsLast()
  W.SetText(frame.next.label, last and "setup.finish" or "setup.next")
  W.SetText(frame.skip.label, session.firstRun and "setup.skip" or "setup.close")
  frame.back:SetEnabled(not session:IsFirst())
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
  paintProgress()
end

function UI.View(id)
  return views[id]
end

function UI.IsOpen()
  return frame ~= nil and frame:IsShown()
end

function UI.Close()
  if frame then
    frame:Hide()
  end
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
  end)
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
end

local function handleKey(key)
  local current = ns.Focus.current
  -- A dropdown list lives outside the window: it keeps its own keys.
  local inPopup = current ~= nil and not inside(current, frame)
  if key == "ESCAPE" then
    if ns.Popups.close() then
      return true
    end
    -- A dialog on top closes itself with Esc.
    for _, name in ipairs({ "ForeverGuidesConfirmDialog", "ForeverGuidesCopyDialog" }) do
      local dialog = rawget(_G, name)
      if dialog and dialog:IsShown() then
        return false
      end
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

-- Construction ---------------------------------------------------------------------------------

local function build()
  frame = CreateFrame("Frame", "ForeverGuidesSetupWizard", UIParent)
  frame:SetSize(UI.WIDTH, UI.MIN_HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  W.Fill(frame, "bg", 0.97)
  local shell =
    ns.WindowShell.Attach(frame, { title = "setup.title", role = "h2", titleHeight = TITLE_H, shadow = true })
  local close =
    W.Action(shell.titleBar, { icon = "close", size = 22, tooltip = "common.close", onClick = UI.AskCancel })
  close:SetPoint("RIGHT", -8, 0)
  shell.titleText:ClearAllPoints()
  shell.titleText:SetPoint("LEFT", 16, 0)
  shell.titleText:SetPoint("RIGHT", close, "LEFT", -8, 0)

  frame.progress = W.Text(frame, { role = "ui", color = "textSecondary" })
  frame.progress:SetPoint("TOPLEFT", PAD, -(TITLE_H + 8))
  ns.Bind(frame.progress, paintProgress)
  local track = frame:CreateTexture(nil, "ARTWORK")
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

  frame:SetScript("OnShow", function()
    frame:SetScale(Theme.windowScale())
  end)
  -- Closed any other way than Done, Skip or Cancel counts as cancelled.
  frame:SetScript("OnHide", function()
    local open = session
    session = nil
    if open and not open.closed then
      open:Cancel()
    end
  end)
  frame:Hide()
end

-- opts.onlyNew: only the steps this user has not seen yet. Returns whether the window opened.
function UI.Open(opts)
  if not ns.db then
    return false
  end
  if frame and frame:IsShown() then
    frame:Raise()
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
  for _, view in pairs(views) do
    view.area:Hide()
  end
  frame:Show()
  setupKeys()
  render()
  return true
end

-- Events ---------------------------------------------------------------------------------------

ns.On("FG_UI_REFRESHED", function()
  if UI.IsOpen() and session then
    fit()
    paintProgress()
  end
end)

ns.On("FG_SETTING_CHANGED", function(_, path)
  if not (UI.IsOpen() and session) then
    return
  end
  if path == "settings.scale" then
    frame:SetScale(Theme.windowScale())
  end
  local view = currentView()
  if view then
    refreshView(view)
  end
end)

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
    UI.Open()
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
