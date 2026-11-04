-- Forever Chat, "New message": a small panel in the place of the list where the player types the name of a player
-- (Forever: "First Last", never cut to one word; Retail: one name, optionally "Name-Realm"; checked by
-- PlayerName.CheckWhisper for the client in use). Enter makes the whisper chat
-- (an empty conversation, nothing is sent) and picks it; the input line takes the focus, so the first message
-- is the player's own Enter. Suggestions come from the guild list the main add-on already holds, the friend
-- list and the group, read only while not in combat and never more than MAX_SOURCE names each.
-- Keys: Up and Down pick a suggestion, Tab takes it into the box, Enter opens, Esc closes the panel.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, Theme, K = FG.W, FG.L, FG.Theme, FG.PageKit
local PN = FG.PlayerName
local Conv = chat.Conversations

local New = {}
chat.New = New

New.MAX_SUGGESTIONS = 6
New.MAX_SOURCE = 200
local PAD, ROW = 8, 24

local function global(name)
  return rawget(_G, name)
end

local function try(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  return ok and FG.AutoGuard.Safe(a) or nil, ok and b or nil
end

local function homeRealm()
  for _, name in ipairs({ "GetNormalizedRealmName", "GetRealmName" }) do
    local realm = try(global(name))
    if type(realm) == "string" and realm ~= "" then
      return realm
    end
  end
  return nil
end

-- Rules (no frames) ---------------------------------------------------------------------------------------------

-- The target of a whisper from the text of the box. Returns the target { kind, name, homeRealm }, or false
-- and why: "missing" (Forever: one word, Retail: nothing), "extra" (Forever: more than two words, Retail: more
-- than one), "invalid" or "self".
function New.Resolve(input, realm)
  local name = PN.Clean(type(input) == "string" and input or "")
  local ok, why = PN.CheckWhisper(name)
  if not ok then
    return false, why
  end
  local own = PN.Self()
  if own ~= "" and PN.Equal(name, own) then
    return false, "self"
  end
  return { kind = "whisper", name = name, homeRealm = realm }
end

-- Names for the box: from sources = { { name, tag }, ... } (tag "friend", "guild" or "group"), the ones that
-- can be whispered, without double names, those that start with the query first, then the rest that contain it,
-- each part in order of the name; at most limit. An empty query lists nothing.
function New.Suggest(sources, query, limit)
  local fold = FG.LfgBrowseFilterLogic.Fold
  local q = fold(PN.Clean(type(query) == "string" and query or ""))
  local out = {}
  if q == "" then
    return out
  end
  local starts, within, seen = {}, {}, {}
  for _, entry in ipairs(sources or {}) do
    local name = type(entry) == "table" and PN.Clean(entry.name or "") or ""
    local key = PN.Key(name)
    if name ~= "" and not seen[key] and PN.CheckWhisper(name) then
      seen[key] = true
      local at = fold(name):find(q, 1, true)
      if at == 1 then
        starts[#starts + 1] = { name = name, tag = entry.tag }
      elseif at then
        within[#within + 1] = { name = name, tag = entry.tag }
      end
    end
  end
  local function byName(a, b)
    return a.name < b.name
  end
  table.sort(starts, byName)
  table.sort(within, byName)
  for _, list in ipairs({ starts, within }) do
    for _, entry in ipairs(list) do
      if #out >= (limit or New.MAX_SUGGESTIONS) then
        return out
      end
      out[#out + 1] = entry
    end
  end
  return out
end

-- Game access -----------------------------------------------------------------------------------------------

local function guildNames(out)
  local data = FG.GuildData
  local snap = data and data.Get and data.Get()
  for _, member in ipairs(snap and snap.members or {}) do
    if #out >= New.MAX_SOURCE then
      return
    end
    if type(member.name) == "string" then
      out[#out + 1] = { name = member.name, tag = "guild" }
    end
  end
end

local function friendNames(out)
  local list = global("C_FriendList")
  if type(list) ~= "table" then
    return
  end
  local count = try(list.GetNumFriends)
  for i = 1, math.min(type(count) == "number" and count or 0, New.MAX_SOURCE) do
    local info = try(list.GetFriendInfoByIndex, i)
    if type(info) == "table" and type(info.name) == "string" then
      out[#out + 1] = { name = info.name, tag = "friend" }
    end
  end
end

local function groupNames(out)
  local count = try(global("GetNumGroupMembers"))
  if type(count) ~= "number" or count < 1 then
    return
  end
  local raid = try(global("IsInRaid")) == true
  for i = 1, math.min(count, 40) do
    local unit = raid and ("raid" .. i) or ("party" .. i)
    local name = PN.Display(unit)
    if type(name) == "string" and name ~= "" then
      out[#out + 1] = { name = name, tag = "group" }
    end
  end
end

-- The names the suggestions draw from (empty in combat).
function New.Sources()
  local out = {}
  if FG.InCombat() then
    return out
  end
  for _, read in ipairs({ friendNames, guildNames, groupNames }) do
    FG.Safe("chat-new-sources", read, out)
  end
  return out
end

-- Makes the whisper chat for the text and says so to the windows. Returns the key, or nil and why (see Resolve,
-- and "full" when the list of chats has no room). Never sends anything.
function New.Create(input)
  local target, why = New.Resolve(input, homeRealm())
  if not target then
    return nil, why
  end
  local conv, reason = Conv.Ensure(chat.convs, target, FG.U.now())
  if not conv then
    return nil, reason
  end
  FG.Emit("FG_CHAT_UPDATE", { [conv.key] = true }, chat.Unread.Total(chat.convs))
  return conv.key
end

-- Panel -----------------------------------------------------------------------------------------------------------

local panel

local function rowHeight()
  return K.scaledHeight(ROW)
end

local function paintRows()
  for i, row in ipairs(panel.rows) do
    local on = i == panel.index and row:IsShown()
    row.hl:SetColorTexture(1, 1, 1, on and 0.1 or 0)
    row.bar:SetShown(on)
  end
end

local function whisperParts(on)
  panel.box:SetShown(on)
  panel.hint:SetShown(on)
  if not on then
    panel.error:Hide()
    for _, row in ipairs(panel.rows) do
      row:Hide()
    end
  end
end

local function fit()
  local top = PAD
  panel.title:ClearAllPoints()
  panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
  panel.title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -top)
  top = top + math.ceil(panel.title:GetStringHeight()) + 4
  panel.modes:ClearAllPoints()
  panel.modes:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
  panel.modes:SetWidth(math.max(40, (panel:GetWidth() or 240) - 2 * PAD))
  top = top + panel.modes:GetHeight() + 6
  if panel.mode == "team" then
    whisperParts(false)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", panel:GetParent(), "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMLEFT", panel:GetParent(), "BOTTOMLEFT", 0, 0)
    local width = panel:GetWidth() or 240
    local height = math.max(60, (panel:GetParent():GetHeight() or 300) - top - 4)
    panel.form.area:ClearAllPoints()
    panel.form.area:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -top)
    panel.form:Fit(width - 2, height)
    panel.form.area:Show()
    return
  end
  panel.form.area:Hide()
  whisperParts(true)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", panel:GetParent(), "TOPLEFT", 0, 0)
  panel.box:ClearAllPoints()
  panel.box:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
  panel.box:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -top)
  top = top + panel.box:GetHeight() + 4
  if panel.error:IsShown() then
    panel.error:ClearAllPoints()
    panel.error:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
    panel.error:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -top)
    top = top + math.ceil(panel.error:GetStringHeight()) + 4
  end
  for _, row in ipairs(panel.rows) do
    if row:IsShown() then
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -top)
      row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -top)
      row:SetHeight(rowHeight())
      top = top + rowHeight()
    end
  end
  panel.hint:ClearAllPoints()
  panel.hint:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(top + 4))
  panel.hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -(top + 4))
  panel:SetHeight(top + 4 + math.ceil(panel.hint:GetStringHeight()) + PAD)
end

-- The text of a reason for this client: the "<key>.retail" variant where there is one.
local function errorText(reason)
  local base = "chat.new.error." .. reason
  local key = PN.TextKey(base)
  return L[key] ~= key and L[key] or L[base]
end
New.ErrorText = errorText

-- The placeholder of the box names the input of the client in use (it can change with the override).
local function retext()
  for _, region in ipairs({ panel.box:GetRegions() }) do
    if region.GetObjectType and region:GetObjectType() == "FontString" then
      W.SetText(region, PN.TextKey("chat.new.placeholder"))
    end
  end
end

local function setError(reason)
  if reason then
    panel.error:SetText(errorText(reason))
  end
  panel.error:SetShown(reason ~= nil)
end

-- The suggestions for the text now.
local function suggest()
  panel.shown = New.Suggest(panel.sources, panel.edit:GetText(), New.MAX_SUGGESTIONS)
  for i, row in ipairs(panel.rows) do
    local entry = panel.shown[i]
    row.entry = entry
    if entry then
      row.name:SetText(entry.name)
      row.tag:SetText(L["chat.new.tag." .. (entry.tag or "guild")])
      row:Show()
    else
      row:Hide()
    end
  end
  panel.index = #panel.shown > 0 and 1 or 0
  paintRows()
  fit()
end

-- The window places the panel where the list sits while it is open (width: the width of that pane).
function New.Place(width)
  if not panel then
    return
  end
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", panel:GetParent(), "TOPLEFT", 0, 0)
  panel:SetWidth(math.max(120, width))
  fit()
end

-- Switches between the whisper and the form for a team.
local function setMode(mode)
  panel.mode = mode == "team" and "team" or "whisper"
  if panel.modes.selected ~= panel.mode then
    panel.modes.selected = panel.mode
  end
  if panel.mode == "team" then
    panel.edit:ClearFocus()
    panel.form:Open()
  else
    panel.edit:SetText("")
    setError(nil)
  end
  fit()
  if panel.mode == "whisper" then
    suggest()
    C_Timer.After(0, function()
      if panel:IsShown() and panel.mode == "whisper" then
        panel.edit:SetFocus()
      end
    end)
  end
  if panel.win.Layout then
    panel.win.Layout()
  end
end

function New.Mode()
  return panel and panel.mode
end

function New.Close()
  if panel and panel:IsShown() then
    panel.edit:ClearFocus()
    if panel.form and panel.form.nameEdit then
      panel.form.nameEdit:ClearFocus()
      panel.form.memberEdit:ClearFocus()
    end
    panel:Hide()
    if panel.win.Layout then
      panel.win.Layout()
    end
    return true
  end
  return false
end

function New.IsOpen()
  return panel ~= nil and panel:IsShown()
end

-- Opens the panel (built with the window, not now). False before the window exists.
function New.Open(mode)
  if not panel then
    return false
  end
  panel.sources = New.Sources()
  panel.edit:SetText("")
  retext()
  setError(nil)
  panel.mode = "whisper"
  panel:Show()
  panel.modes:Select(mode == "team" and "team" or "whisper")
  if panel.win.Layout then
    panel.win.Layout()
  end
  if panel.mode == "whisper" then
    suggest()
    C_Timer.After(0, function()
      if panel:IsShown() and panel.mode == "whisper" then
        panel.edit:SetFocus()
      end
    end)
  end
  return true
end

-- Enter: the picked suggestion when there is one and the box holds only part of its name, else the text.
local function submit()
  local text = panel.edit:GetText()
  local entry = panel.shown and panel.shown[panel.index]
  if entry and FG.LfgBrowseFilterLogic.Fold(PN.Clean(text)) ~= FG.LfgBrowseFilterLogic.Fold(entry.name) then
    text = entry.name
  end
  local key, why = New.Create(text)
  if not key then
    setError(why)
    fit()
    return
  end
  New.Close()
  panel.win.Select(key)
end

local function newSuggestionRow(index)
  local row = CreateFrame("Button", nil, panel)
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints()
  row.bar = row:CreateTexture(nil, "ARTWORK")
  row.bar:SetPoint("TOPLEFT")
  row.bar:SetPoint("BOTTOMLEFT")
  row.bar:SetWidth(3)
  row.name = W.Text(row, { role = "ui", color = "text" })
  row.name:SetPoint("LEFT", row, "LEFT", 10, 0)
  row.name:SetWordWrap(false)
  row.tag = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
  row.tag:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.name:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
  FG.Bind(row, function()
    row.bar:SetColorTexture(Theme.color("accent2"))
  end)
  row:SetScript("OnEnter", function()
    panel.index = index
    paintRows()
  end)
  row:SetScript(
    "OnClick",
    FG.Wrap("chat-new-pick", function()
      panel.index = index
      submit()
    end)
  )
  FG.Focus.register(row, function(self)
    self:Click()
  end)
  row:Hide()
  return row
end

-- Builds the panel inside parent (the content of the window). win: { Select(key) } picks the new chat, Layout()
-- asks the window to place the panels again.
function New.Build(parent, win)
  if panel then
    return panel
  end
  panel = CreateFrame("Frame", "FGChatNewPanel", parent)
  panel.win = win
  panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  panel:SetWidth(240)
  W.Fill(panel, "surface", 1)
  W.Border(panel, "accentDim", 1)
  panel.title = W.Text(panel, { key = "chat.new.title", role = "h3", color = "accent2" })
  panel.mode = "whisper"
  panel.modes = W.Tabs(panel, {
    tabs = {
      { id = "whisper", key = "chat.new.mode.whisper" },
      { id = "team", key = "chat.new.mode.team" },
    },
    onSelect = function(id)
      if panel.mode ~= id or not panel.modeInit then
        panel.modeInit = true
        setMode(id)
      end
    end,
  })
  panel.form = chat.TeamForm.Build(panel, {
    Created = function(key)
      New.Close()
      panel.win.Select(key)
    end,
    Close = New.Close,
  })
  panel.box = W.EditBox(panel, { placeholder = PN.TextKey("chat.new.placeholder"), height = 28 })
  chat.List.FitPlaceholder(panel.box)
  panel.edit = panel.box.edit
  panel.edit:SetMaxLetters(80)
  panel.error = W.Text(panel, { role = "micro", color = "danger", wrap = true })
  panel.error:Hide()
  panel.hint = W.Text(panel, { key = "chat.new.hint", role = "micro", color = "textMuted", wrap = true })
  panel.rows = {}
  for i = 1, New.MAX_SUGGESTIONS do
    panel.rows[i] = newSuggestionRow(i)
  end
  panel.shown, panel.index, panel.sources = {}, 0, {}
  local edit = panel.edit
  edit:HookScript(
    "OnTextChanged",
    FG.Wrap("chat-new-text", function()
      setError(nil)
      suggest()
    end)
  )
  edit:SetScript("OnEnterPressed", FG.Wrap("chat-new-enter", submit))
  edit:SetScript("OnEscapePressed", FG.Wrap("chat-new-esc", New.Close))
  edit:SetScript("OnTabPressed", function()
    local entry = panel.shown[panel.index]
    if entry then
      edit:SetText(entry.name)
      edit:SetCursorPosition(#entry.name)
    end
  end)
  edit:SetScript(
    "OnArrowPressed",
    FG.Wrap("chat-new-arrow", function(_, key)
      local n = #panel.shown
      if n > 0 and (key == "UP" or key == "DOWN") then
        panel.index = ((panel.index - 1 + (key == "DOWN" and 1 or -1)) % n) + 1
        paintRows()
      end
    end)
  )
  panel:Hide()
  return panel
end

function New.Panel()
  return panel
end

-- A new look or text size changes the measures the panel was fitted with.
FG.On("FG_UI_REFRESHED", function()
  if panel and panel:IsShown() then
    fit()
  end
end)
