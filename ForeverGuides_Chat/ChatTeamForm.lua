-- Forever Chat, the form "new team" (game access): the second half of the panel "New message" (ChatNew.lua). A
-- name (24 characters), a symbol (the macro icons, ChatIconPicker.lua), players from the guild list, the friend
-- list and the group (the same suggestions as for a whisper, each name checked for this client by
-- PlayerName.CheckWhisper) and the button "Create team". Create goes through chat.Teams.Create and shows the
-- reason of a refusal. Keys: Enter in the name goes on to the players, Enter adds the picked suggestion, Up and
-- Down pick one, Tab takes it into the box, Esc closes the panel.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, K = FG.W, FG.L, FG.PageKit
local PN = FG.PlayerName
local UL, TLG = chat.TeamsUILogic, chat.TeamsLogic

local Form = {}
chat.TeamForm = Form

Form.MAX_SUGGESTIONS = 4
local PAD, GAP, ROW, SCROLL = 8, 6, 24, 14

local function rowHeight()
  return K.scaledHeight(ROW)
end

-- Rules (no frames) -----------------------------------------------------------------------------------------------

-- The text of a reason of the form: the checks of the form, the names (chat.new.error.*) and the interface.
function Form.ErrorText(reason)
  if reason == "name" or reason == "member" or reason == "double" or reason == "full" then
    local text = FG.L["chat.teams.form.error." .. reason]
    if reason == "full" then
      return chat.Teams.ReasonText("full")
    end
    return text
  end
  if reason == "missing" or reason == "extra" or reason == "invalid" or reason == "self" then
    return chat.New.ErrorText(reason)
  end
  return chat.Teams.ReasonText(reason)
end

-- Frames ----------------------------------------------------------------------------------------------------------

local function newSuggestion(form, index)
  local row = CreateFrame("Button", nil, form.content)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints()
  row.name = W.Text(row, { role = "ui", color = "text" })
  row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
  row.name:SetWordWrap(false)
  row.tag = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
  row.tag:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.name:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
  row:SetScript("OnEnter", function()
    form.index = index
    form:PaintSuggestions()
  end)
  row:SetScript(
    "OnClick",
    FG.Wrap("chat-team-suggest", function()
      form.index = index
      form:AddFromBox()
    end)
  )
  FG.Focus.register(row, function(self)
    self:Click()
  end)
  row:Hide()
  return row
end

local function newMemberRow(form, index)
  local row = CreateFrame("Frame", nil, form.content)
  row.name = W.Text(row, { role = "ui", color = "text" })
  row.name:SetWordWrap(false)
  row.remove = W.Action(row, {
    icon = "close",
    size = 20,
    tooltip = "chat.teams.form.remove",
    wrap = "chat-team-unlist",
    onClick = function()
      form.members = UL.RemoveMember(form.members, index)
      form:Layout()
    end,
  })
  row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.name:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
  row:Hide()
  return row
end

-- Builds the form inside parent (the panel). hooks: Created(key) after a team was made, Close() for Esc.
function Form.Build(parent, hooks)
  local form =
    { hooks = hooks or {}, members = {}, icon = nil, index = 0, shown = {}, sources = {}, suggestions = {}, rows = {} }
  local area = W.ScrollArea(parent)
  form.area, form.content = area, area.content
  local c = form.content
  form.nameBox = W.EditBox(c, { placeholder = "chat.teams.form.name", height = 28 })
  chat.List.FitPlaceholder(form.nameBox)
  form.nameEdit = form.nameBox.edit
  form.nameEdit:SetMaxLetters(TLG.LIMITS.NAME_CHARS)
  form.symbolLabel = W.Text(c, { key = "chat.teams.form.symbol", role = "micro", color = "textSecondary" })
  form.preview = CreateFrame("Frame", nil, c)
  form.preview:SetSize(28, 28)
  form.previewTex = form.preview:CreateTexture(nil, "ARTWORK")
  form.previewTex:SetAllPoints()
  form.choose = W.Action(c, {
    key = "chat.teams.form.choose",
    wrap = "chat-team-choose",
    onClick = function()
      form:ShowPicker(true)
    end,
  })
  form.memberBox = W.EditBox(c, { placeholder = PN.TextKey("chat.new.placeholder"), height = 28 })
  chat.List.FitPlaceholder(form.memberBox)
  form.memberEdit = form.memberBox.edit
  form.memberEdit:SetMaxLetters(80)
  form.add = W.Action(c, {
    key = "chat.teams.form.add",
    wrap = "chat-team-add",
    onClick = function()
      form:AddFromBox()
    end,
  })
  for i = 1, Form.MAX_SUGGESTIONS do
    form.suggestions[i] = newSuggestion(form, i)
  end
  form.membersLabel = W.Text(c, { role = "micro", color = "textSecondary" })
  for i = 1, UL.MAX_LISTED do
    form.rows[i] = newMemberRow(form, i)
  end
  form.more = W.Text(c, { role = "micro", color = "textMuted" })
  form.none = W.Text(c, { key = "chat.teams.form.none", role = "micro", color = "textMuted", wrap = true })
  form.error = W.Text(c, { role = "micro", color = "danger", wrap = true })
  form.error:Hide()
  form.create = W.Action(c, {
    key = "chat.teams.form.create",
    variant = "primary",
    wrap = "chat-team-create",
    onClick = function()
      form:Submit()
    end,
  })
  form.note = W.Text(c, { key = "chat.teams.form.invitations", role = "micro", color = "textMuted", wrap = true })
  form.picker = chat.IconPicker.Create(c, {
    onPick = function(icon)
      form.icon = icon
      form:ShowPicker(false)
    end,
    onBack = function()
      form:ShowPicker(false)
    end,
  })

  function form:SetError(reason)
    if reason then
      form.error:SetText(Form.ErrorText(reason))
    end
    form.error:SetShown(reason ~= nil)
  end

  function form:PaintSuggestions()
    for i, row in ipairs(form.suggestions) do
      local on = i == form.index and row:IsShown()
      row.hl:SetColorTexture(1, 1, 1, on and 0.1 or 0)
    end
  end

  function form:Suggest()
    form.shown = chat.New.Suggest(form.sources, form.memberEdit:GetText(), Form.MAX_SUGGESTIONS)
    for i, row in ipairs(form.suggestions) do
      local entry = form.shown[i]
      row.entry = entry
      if entry then
        row.name:SetText(entry.name)
        row.tag:SetText(L["chat.new.tag." .. (entry.tag or "guild")])
        row:Show()
      else
        row:Hide()
      end
    end
    form.index = #form.shown > 0 and 1 or 0
    form:Layout()
  end

  -- Enter or Add: the picked suggestion when the box holds only part of its name, else the text of the box.
  function form:AddFromBox()
    local text = form.memberEdit:GetText()
    local entry = form.shown[form.index]
    local fold = FG.LfgBrowseFilterLogic.Fold
    if entry and fold(PN.Clean(text)) ~= fold(entry.name) then
      text = entry.name
    end
    local list, why = UL.AddMember(form.members, text, PN.Self())
    if not list then
      form:SetError(why)
      form:Layout()
      return false
    end
    form.members = list
    form:SetError(nil)
    form.memberEdit:SetText("")
    form:Layout()
    return true
  end

  -- Checks the form and makes the team. The team is picked afterwards (hooks.Created).
  function form:Submit()
    -- A name typed in the box but not added yet counts: Enter on the button should not lose it.
    local typed = form.memberEdit:GetText()
    if typed:find("%S") then
      local _, why = UL.AddMember(form.members, typed, PN.Self())
      if why == "double" then
        form.memberEdit:SetText("")
      elseif not form:AddFromBox() then
        return false
      end
    end
    local ok, why = UL.CheckForm(form.nameEdit:GetText(), form.members)
    if not ok then
      form:SetError(why)
      form:Layout()
      return false
    end
    local id, info = chat.Teams.Create(form.nameEdit:GetText(), form.icon, form.members)
    if not id then
      form:SetError(info)
      form:Layout()
      return false
    end
    local key = chat.Conversations.Key("team", id)
    form:Reset()
    if form.hooks.Created then
      form.hooks.Created(key)
    end
    return true
  end

  function form:ShowPicker(on)
    form.picking = on
    if on then
      form.picker:Open(form.icon)
    end
    form:Layout()
  end

  function form:Reset()
    form.members, form.icon, form.picking = {}, nil, false
    form.nameEdit:SetText("")
    form.memberEdit:SetText("")
    form:SetError(nil)
  end

  function form:Open()
    form:Reset()
    form.sources = chat.New.Sources()
    form:Suggest()
    form.nameEdit:SetFocus()
  end

  -- Places every part for the size the panel gave (width, height) and sizes the scrolled content.
  function form:Layout()
    local width, height = form.width or 200, form.height or 200
    local inner = math.max(80, width - SCROLL - PAD)
    local x0 = PAD / 2
    c:SetWidth(width - 12)
    local picking = form.picking == true
    for _, part in ipairs({
      form.nameBox,
      form.symbolLabel,
      form.preview,
      form.choose,
      form.memberBox,
      form.add,
      form.membersLabel,
      form.more,
      form.none,
      form.create,
      form.note,
    }) do
      part:SetShown(not picking)
    end
    for _, row in ipairs(form.suggestions) do
      row:SetShown(not picking and row.entry ~= nil)
    end
    if picking then
      form.error:Hide()
      for _, row in ipairs(form.rows) do
        row:Hide()
      end
      form.picker.frame:Show()
      form.picker.frame:ClearAllPoints()
      form.picker.frame:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -PAD)
      local h = form.picker:Fit(inner)
      area:SetContentHeight(PAD + h + PAD)
      return
    end
    form.picker.frame:Hide()
    local y = PAD
    local function place(part, h, left, right)
      part:ClearAllPoints()
      part:SetPoint("TOPLEFT", c, "TOPLEFT", left or x0, -y)
      part:SetWidth(right and (right - (left or x0)) or inner)
      return h
    end
    y = y + place(form.nameBox, 28) + GAP
    -- Symbol: label, then the preview tile and the button.
    form.symbolLabel:ClearAllPoints()
    form.symbolLabel:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
    y = y + math.ceil(form.symbolLabel:GetStringHeight()) + 2
    form.preview:ClearAllPoints()
    form.preview:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
    form.previewTex:SetTexture(TLG.CleanIcon(form.icon) or TLG.LIMITS.DEFAULT_ICON)
    form.choose:ClearAllPoints()
    form.choose:SetPoint("LEFT", form.preview, "RIGHT", GAP, 0)
    form.choose:SetWidth(math.min(form.choose:FullWidth(), inner - 28 - GAP))
    y = y + 28 + GAP
    -- Players: the box with its button.
    form.add:ClearAllPoints()
    form.add:SetWidth(math.min(form.add:FullWidth(), math.floor(inner / 2)))
    form.add:SetPoint("TOPRIGHT", c, "TOPLEFT", x0 + inner, -y - 2)
    form.memberBox:ClearAllPoints()
    form.memberBox:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
    form.memberBox:SetWidth(inner - form.add:GetWidth() - GAP)
    y = y + 28 + 2
    for _, row in ipairs(form.suggestions) do
      if row:IsShown() then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
        row:SetSize(inner, rowHeight())
        y = y + rowHeight()
      end
    end
    y = y + GAP
    -- The list of players added so far.
    form.membersLabel:SetText(string.format(L["chat.teams.form.members"], #form.members))
    form.membersLabel:ClearAllPoints()
    form.membersLabel:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
    y = y + math.ceil(form.membersLabel:GetStringHeight()) + 2
    form.none:SetShown(#form.members == 0)
    if #form.members == 0 then
      form.none:ClearAllPoints()
      form.none:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
      form.none:SetWidth(inner)
      y = y + math.ceil(form.none:GetStringHeight()) + 2
    end
    -- The last names added show; the rest is counted.
    local first = math.max(1, #form.members - UL.MAX_LISTED + 1)
    for i, row in ipairs(form.rows) do
      local at = first + i - 1
      local name = form.members[at]
      row:SetShown(name ~= nil)
      if name then
        row.name:SetText(name)
        row.remove.fgNameKey = "chat.teams.form.remove"
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
        row:SetSize(inner, rowHeight())
        row.remove:SetScript(
          "OnClick",
          FG.Wrap("chat-team-unlist", function()
            form.members = UL.RemoveMember(form.members, at)
            form:Layout()
          end)
        )
        y = y + rowHeight()
      end
    end
    form.more:SetShown(first > 1)
    if first > 1 then
      form.more:SetText(string.format(L["chat.teams.form.more"], first - 1))
      form.more:ClearAllPoints()
      form.more:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
      y = y + math.ceil(form.more:GetStringHeight()) + 2
    end
    y = y + GAP
    if form.error:IsShown() then
      form.error:ClearAllPoints()
      form.error:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
      form.error:SetWidth(inner)
      y = y + math.ceil(form.error:GetStringHeight()) + GAP
    end
    form.create:ClearAllPoints()
    form.create:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
    form.create:SetWidth(math.min(form.create:FullWidth(), inner))
    y = y + 28 + GAP
    form.note:ClearAllPoints()
    form.note:SetPoint("TOPLEFT", c, "TOPLEFT", x0, -y)
    form.note:SetWidth(inner)
    y = y + math.ceil(form.note:GetStringHeight()) + PAD
    area:SetContentHeight(math.max(y, height - 2))
  end

  -- The panel gives the form its box (below the mode switch) and it places itself.
  function form:Fit(width, height)
    form.width, form.height = width, height
    area:SetSize(width, height)
    form:Layout()
  end

  -- Edit boxes -----------------------------------------------------------------------------------------------------
  form.nameEdit:SetScript(
    "OnEnterPressed",
    FG.Wrap("chat-team-name-enter", function()
      form.memberEdit:SetFocus()
    end)
  )
  form.nameEdit:SetScript(
    "OnEscapePressed",
    FG.Wrap("chat-team-name-esc", function()
      if form.hooks.Close then
        form.hooks.Close()
      end
    end)
  )
  form.nameEdit:HookScript(
    "OnTextChanged",
    FG.Wrap("chat-team-name-text", function()
      if form.error:IsShown() then
        form:SetError(nil)
        form:Layout()
      end
    end)
  )
  local edit = form.memberEdit
  edit:HookScript(
    "OnTextChanged",
    FG.Wrap("chat-team-member-text", function()
      form:SetError(nil)
      form:Suggest()
    end)
  )
  edit:SetScript(
    "OnEnterPressed",
    FG.Wrap("chat-team-member-enter", function()
      if edit:GetText():find("%S") then
        form:AddFromBox()
      else
        form:Submit()
      end
    end)
  )
  edit:SetScript(
    "OnEscapePressed",
    FG.Wrap("chat-team-member-esc", function()
      if form.hooks.Close then
        form.hooks.Close()
      end
    end)
  )
  edit:SetScript("OnTabPressed", function()
    local entry = form.shown[form.index]
    if entry then
      edit:SetText(entry.name)
      edit:SetCursorPosition(#entry.name)
    end
  end)
  edit:SetScript(
    "OnArrowPressed",
    FG.Wrap("chat-team-member-arrow", function(_, key)
      local n = #form.shown
      if n > 0 and (key == "UP" or key == "DOWN") then
        form.index = ((form.index - 1 + (key == "DOWN" and 1 or -1)) % n) + 1
        form:PaintSuggestions()
      end
    end)
  )
  FG.Bind(form.preview, function()
    form.previewTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end)
  area:Hide()
  return form
end
