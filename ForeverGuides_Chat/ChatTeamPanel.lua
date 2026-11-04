-- Forever Chat, the panel of a team (game access): the members with their role and an online dot, and the actions
-- the rules allow (ChatTeamsUILogic.lua): admins add players, remove them, hand out and take back the admin
-- role, rename the team, change its symbol and dissolve it; everybody can leave. Leaving, dissolving and
-- removing ask first. Actions that are not allowed do not show; the one that is blocked for a reason (the
-- only admin giving up the role) shows grey with the reason. Every change goes through chat.Teams. The panel
-- takes the place of the thread (the window hides the thread while it is open).
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, Theme = FG.W, FG.L, FG.Theme
local UL, TLG = chat.TeamsUILogic, chat.TeamsLogic

local Panel = {}
chat.TeamPanel = Panel

local PAD, GAP, HEAD = 8, 6, 28

local panel

local function api()
  return chat.Teams
end

local function safe(value)
  local v = FG.AutoGuard.Safe(value)
  return type(v) == "string" and v or ""
end

-- The question before leaving, dissolving or removing: a dialog of the main add-on (replaced in tests).
function Panel.Confirm(titleKey, text, yesKey, onYes)
  FG.Dialogs.Confirm(nil, nil, onYes, nil, { title = L[titleKey], text = text, yesKey = yesKey })
end

local function enabled(frame, on)
  if frame.SetEnabled then
    frame:SetEnabled(on)
  end
  frame:SetAlpha(on and 1 or 0.5)
end

local function newMemberRow(index)
  local row = CreateFrame("Frame", nil, panel.content)
  row.dot = row:CreateTexture(nil, "ARTWORK")
  row.dot:SetSize(8, 8)
  row.dot:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -5)
  row.name = W.Text(row, { role = "ui", color = "text" })
  row.name:SetWordWrap(false)
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 16, 0)
  row.role = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
  row.role:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
  row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -80, 0)
  row.buttons = {}
  for slot = 1, 2 do
    row.buttons[slot] =
      W.Action(row, { text = "?", variant = "ghost", height = 22, wrap = "chat-team-member-" .. slot })
    row.buttons[slot]:Hide()
  end
  row.index = index
  row:Hide()
  return row
end

local function memberAction(row, action)
  local name = row.data.name
  local tid = panel.tid
  local label = "chat.teams.act." .. action.id
  if action.id == "remove" then
    Panel.Confirm(
      "chat.teams.confirm.remove.title",
      string.format(L["chat.teams.confirm.remove.text"], UL.Short(name), safe(panel.info.name)),
      label,
      function()
        panel:Result(api().Remove(tid, name))
      end
    )
  else
    panel:Result(api().SetAdmin(tid, name, action.id == "makeAdmin"))
  end
end

function Panel.Build(parent, win)
  if panel then
    return panel
  end
  panel = CreateFrame("Frame", "FGChatTeamPanel", parent)
  panel.win = win
  panel:SetAllPoints(parent)
  panel:SetFrameLevel(parent:GetFrameLevel() + 20)
  panel:EnableMouse(true)
  W.Fill(panel, "bg", 1)
  panel.back = W.Action(panel, {
    icon = "chevron-left",
    size = 24,
    tooltip = "chat.teams.back",
    wrap = "chat-team-panel-back",
    onClick = function()
      Panel.Close()
    end,
  })
  panel.back:SetPoint("TOPLEFT", 0, 0)
  panel.symbol = CreateFrame("Frame", nil, panel)
  panel.symbol:SetSize(24, 24)
  panel.symbolTex = panel.symbol:CreateTexture(nil, "ARTWORK")
  panel.symbolTex:SetAllPoints()
  panel.symbolTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  panel.symbol:SetPoint("TOPLEFT", panel, "TOPLEFT", 24 + GAP, 0)
  panel.title = W.Text(panel, { role = "h3", color = "text" })
  panel.title:SetWordWrap(false)
  panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 2 * (24 + GAP), -3)
  panel.title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -3)
  panel.area = W.ScrollArea(panel)
  panel.content = panel.area.content
  local c = panel.content
  panel.warn = W.Text(c, { key = "chat.teams.panel.lastadmin", role = "micro", color = "warning", wrap = true })
  panel.membersLabel = W.Text(c, { key = "chat.teams.panel.members", role = "micro", color = "textSecondary" })
  panel.rows = {}
  for i = 1, TLG.LIMITS.MAX_MEMBERS do
    panel.rows[i] = newMemberRow(i)
  end
  panel.addBox = W.EditBox(c, { placeholder = chat.FG.PlayerName.TextKey("chat.new.placeholder"), height = 28 })
  chat.List.FitPlaceholder(panel.addBox)
  panel.addEdit = panel.addBox.edit
  panel.addEdit:SetMaxLetters(80)
  panel.addGo = W.Action(c, { key = "chat.teams.act.addGo", wrap = "chat-team-invite" })
  panel.renameBox = W.EditBox(c, { placeholder = "chat.teams.act.renamePlaceholder", height = 28 })
  chat.List.FitPlaceholder(panel.renameBox)
  panel.renameEdit = panel.renameBox.edit
  panel.renameEdit:SetMaxLetters(TLG.LIMITS.NAME_CHARS)
  panel.renameGo = W.Action(c, { key = "chat.teams.act.renameGo", wrap = "chat-team-rename" })
  panel.iconButton = W.Action(c, { key = "chat.teams.act.icon", wrap = "chat-team-icon" })
  panel.leave = W.Action(c, { key = "chat.teams.act.leave", wrap = "chat-team-leave", variant = "danger" })
  panel.dissolve = W.Action(c, { key = "chat.teams.act.dissolve", wrap = "chat-team-dissolve", variant = "danger" })
  panel.message = W.Text(c, { role = "micro", color = "danger", wrap = true })
  panel.picker = chat.IconPicker.Create(c, {
    onPick = function(icon)
      panel.picking = false
      panel:Result(api().SetIcon(panel.tid, icon))
    end,
    onBack = function()
      panel.picking = false
      panel:Layout()
    end,
  })

  -- Shows the outcome of an action of the interface: nothing on success, the reason otherwise.
  function panel:Result(ok, why, success)
    if ok then
      panel.message:SetText(success or "")
      W.SetColor(panel.message, "success")
    else
      panel.message:SetText(api().ReasonText(why))
      W.SetColor(panel.message, "danger")
    end
    panel:Layout()
    return ok
  end

  panel.addGo:SetScript(
    "OnClick",
    FG.Wrap("chat-team-invite", function()
      local text = panel.addEdit:GetText()
      local ok, why = api().Invite(panel.tid, text)
      if ok then
        panel.addEdit:SetText("")
      end
      panel:Result(ok, why, L["chat.teams.act.invited"])
    end)
  )
  panel.addEdit:SetScript(
    "OnEnterPressed",
    FG.Wrap("chat-team-invite-enter", function()
      panel.addGo:Click()
    end)
  )
  panel.renameGo:SetScript(
    "OnClick",
    FG.Wrap("chat-team-rename", function()
      local ok, why = api().Rename(panel.tid, panel.renameEdit:GetText())
      panel:Result(ok, why)
    end)
  )
  panel.renameEdit:SetScript(
    "OnEnterPressed",
    FG.Wrap("chat-team-rename-enter", function()
      panel.renameGo:Click()
    end)
  )
  for _, edit in ipairs({ panel.addEdit, panel.renameEdit }) do
    edit:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
    end)
  end
  panel.iconButton:SetScript(
    "OnClick",
    FG.Wrap("chat-team-icon", function()
      panel.picking = true
      panel.picker:Open(panel.info and panel.info.icon)
      panel:Layout()
    end)
  )
  panel.leave:SetScript(
    "OnClick",
    FG.Wrap("chat-team-leave", function()
      Panel.ConfirmLeave(panel.tid)
    end)
  )
  panel.dissolve:SetScript(
    "OnClick",
    FG.Wrap("chat-team-dissolve", function()
      local name = safe(panel.info and panel.info.name)
      Panel.Confirm(
        "chat.teams.confirm.dissolve.title",
        string.format(L["chat.teams.confirm.dissolve.text"], name),
        "chat.teams.act.dissolve",
        function()
          local ok, why = api().Dissolve(panel.tid)
          if ok then
            Panel.Close()
          else
            panel:Result(false, why)
          end
        end
      )
    end)
  )

  -- Fills and places everything for the box the window gave the panel.
  function panel:Layout()
    if not panel:IsShown() then
      return
    end
    local info = api().Get(panel.tid)
    panel.info = info
    if not info then
      Panel.Close()
      return
    end
    local width, height = panel:GetWidth() or 300, panel:GetHeight() or 300
    local top = HEAD + GAP
    panel.area:ClearAllPoints()
    panel.area:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -top)
    panel.area:SetSize(width, math.max(40, height - top))
    local inner = math.max(80, width - 14 - PAD)
    c:SetWidth(width - 12)
    panel.symbolTex:SetTexture(TLG.CleanIcon(info.icon) or TLG.LIMITS.DEFAULT_ICON)
    panel.title:SetText(string.format(L["chat.teams.panel.title"], safe(info.name)))
    local x0, y = PAD / 2, PAD
    local function at(part, extra)
      part:ClearAllPoints()
      part:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
      return extra
    end
    local parts = {
      panel.warn,
      panel.membersLabel,
      panel.addBox,
      panel.addGo,
      panel.renameBox,
      panel.renameGo,
      panel.iconButton,
      panel.leave,
      panel.dissolve,
      panel.message,
    }
    for _, part in ipairs(parts) do
      part:SetShown(not panel.picking)
    end
    for _, row in ipairs(panel.rows) do
      row:SetShown(not panel.picking and row.data ~= nil)
    end
    if panel.picking then
      panel.picker.frame:Show()
      panel.picker.frame:ClearAllPoints()
      panel.picker.frame:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -PAD)
      panel.area:SetContentHeight(PAD * 2 + panel.picker:Fit(inner))
      return
    end
    panel.picker.frame:Hide()
    local actions = {}
    for _, action in ipairs(UL.TeamActions(info)) do
      actions[action.id] = action
    end
    -- Hint for an only admin.
    panel.warn:SetShown(UL.LeaveWarn(info))
    if panel.warn:IsShown() then
      at(panel.warn)
      panel.warn:SetWidth(inner)
      y = y + math.ceil(panel.warn:GetStringHeight()) + GAP
    end
    -- Members.
    local all, online = UL.Counts(info)
    panel.membersLabel:SetText(
      L["chat.teams.panel.members"]
        .. ": "
        .. string.format(L["chat.teams.head"], chat.TeamsView.MemberText(all), online)
    )
    at(panel.membersLabel)
    y = y + math.ceil(panel.membersLabel:GetStringHeight()) + 4
    local rows = UL.MemberRows(info)
    for i, row in ipairs(panel.rows) do
      local data = rows[i]
      row.data = data
      row:SetShown(data ~= nil)
      for _, b in ipairs(row.buttons) do
        b:Hide()
      end
      if data then
        row.name:SetText(UL.Short(safe(data.name)) .. (data.me and (" (" .. L["chat.teams.you"] .. ")") or ""))
        row.role:SetText(L[data.admin and "chat.teams.role.admin" or "chat.teams.role.member"])
        local r, g, b = Theme.rgb(data.online and "success" or "textMuted")
        row.dot:SetColorTexture(r, g, b, 1)
        row.fgName = row.name:GetText()
          .. ", "
          .. row.role:GetText()
          .. ", "
          .. (data.online and L["chat.teams.online"] or L["chat.teams.state.offline"])
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
        row:SetWidth(inner)
        local h = math.max(18, math.ceil(row.name:GetStringHeight()))
        local x = 16
        local slot = 0
        for _, action in ipairs(UL.MemberActions(info, data)) do
          slot = slot + 1
          local button = row.buttons[slot]
          if button then
            W.SetText(button.label, "chat.teams.act." .. action.id)
            button.fgNameKey = "chat.teams.act." .. action.id
            button:ClearAllPoints()
            local w = math.min(button:FullWidth(), inner - x)
            if x > 16 and x + w > inner then
              x = 16
              h = h + 24
            end
            button:SetPoint("TOPLEFT", row, "TOPLEFT", x, -h - 2)
            button:SetWidth(w)
            enabled(button, action.enabled)
            button:SetScript(
              "OnClick",
              FG.Wrap("chat-team-member-action", function()
                if action.enabled then
                  memberAction(row, action)
                else
                  panel:Result(false, action.why)
                end
              end)
            )
            button:Show()
            x = x + w + 4
          end
        end
        if slot > 0 then
          h = h + 26
        end
        row:SetHeight(h)
        y = y + h + 2
      end
    end
    y = y + GAP
    -- Actions on the team.
    if actions.add then
      panel.addGo:ClearAllPoints()
      panel.addGo:SetWidth(math.min(panel.addGo:FullWidth(), math.floor(inner / 2)))
      panel.addGo:SetPoint("TOPRIGHT", c, "TOPLEFT", x0 + inner, -y - 2)
      panel.addBox:ClearAllPoints()
      panel.addBox:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
      panel.addBox:SetWidth(inner - panel.addGo:GetWidth() - GAP)
      y = y + 28 + GAP
      panel.renameGo:ClearAllPoints()
      panel.renameGo:SetWidth(math.min(panel.renameGo:FullWidth(), math.floor(inner / 2)))
      panel.renameGo:SetPoint("TOPRIGHT", c, "TOPLEFT", x0 + inner, -y - 2)
      panel.renameBox:ClearAllPoints()
      panel.renameBox:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
      panel.renameBox:SetWidth(inner - panel.renameGo:GetWidth() - GAP)
      y = y + 28 + GAP
      at(panel.iconButton)
      panel.iconButton:SetWidth(math.min(panel.iconButton:FullWidth(), inner))
      y = y + 28 + GAP
    end
    for _, part in ipairs({ panel.addBox, panel.addGo, panel.renameBox, panel.renameGo, panel.iconButton }) do
      part:SetShown(actions.add ~= nil)
    end
    at(panel.leave)
    panel.leave:SetWidth(math.min(panel.leave:FullWidth(), inner))
    y = y + 28 + GAP
    panel.dissolve:SetShown(actions.dissolve ~= nil)
    if actions.dissolve then
      at(panel.dissolve)
      panel.dissolve:SetWidth(math.min(panel.dissolve:FullWidth(), inner))
      y = y + 28 + GAP
    end
    panel.message:SetShown((panel.message:GetText() or "") ~= "")
    if panel.message:IsShown() then
      at(panel.message)
      panel.message:SetWidth(inner)
      y = y + math.ceil(panel.message:GetStringHeight()) + GAP
    end
    panel.area:SetContentHeight(y + PAD)
  end

  panel:Hide()
  return panel
end

-- Public ----------------------------------------------------------------------------------------------------------

function Panel.Frame()
  return panel
end

function Panel.IsOpen()
  return panel ~= nil and panel:IsShown()
end

function Panel.TeamId()
  return panel and panel:IsShown() and panel.tid or nil
end

function Panel.Open(tid)
  if not (panel and tid and api().Get(tid)) then
    return false
  end
  panel.tid, panel.picking = tid, false
  panel.message:SetText("")
  panel.renameEdit:SetText("")
  panel.addEdit:SetText("")
  panel:Show()
  if panel.win.Layout then
    panel.win.Layout()
  end
  panel:Layout()
  return true
end

function Panel.Close()
  if panel and panel:IsShown() then
    panel.addEdit:ClearFocus()
    panel.renameEdit:ClearFocus()
    panel:Hide()
    panel.tid = nil
    if panel.win.Layout then
      panel.win.Layout()
    end
    return true
  end
  return false
end

-- Redraws after a change of the teams.
function Panel.Refresh()
  if panel and panel:IsShown() then
    panel:Layout()
  end
end

-- The question before the user leaves a team (the menu of the list asks the same).
function Panel.ConfirmLeave(tid)
  local info = api().Get(tid)
  if not info then
    return false
  end
  local text = string.format(L["chat.teams.confirm.leave.text"], safe(info.name))
  if UL.LeaveWarn(info) then
    text = text .. "\n\n" .. L["chat.teams.panel.lastadmin"]
  end
  Panel.Confirm("chat.teams.confirm.leave.title", text, "chat.teams.act.leave", function()
    local ok, why = api().Leave(tid)
    if ok then
      Panel.Close()
    elseif panel then
      panel:Result(false, why)
    end
  end)
  return true
end

FG.On("FG_UI_REFRESHED", Panel.Refresh)
