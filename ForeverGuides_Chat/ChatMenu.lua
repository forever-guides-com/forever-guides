-- Forever Chat, the context menu of a conversation: own frames, no game popup (those are protected). It opens
-- on a right click on a row of the list, on the menu button next to the input line and on the menu key or
-- Shift+F10 in the window. Up, Down, Home and End move, Enter or Space choose, Esc closes. What each entry
-- does is ChatMenuLogic.lua. The frames are built with the window, never while the menu opens.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, Theme, K = FG.W, FG.L, FG.Theme, FG.PageKit
local ML, Unread, Conv = chat.MenuLogic, chat.Unread, chat.Conversations

local Menu = {}
chat.Menu = Menu

Menu.ROW = 26
-- Rows built up front: the longest menu has 14 entries.
Menu.PREBUILD = 15
local PAD, GROUP_GAP, MIN_W, MAX_W = 4, 6, 220, 380

local pop, blocker, prompt
local rows = {}
local state = { key = nil, items = {}, index = 1 }

local function rowHeight()
  return K.scaledHeight(Menu.ROW)
end

local function homeRealm()
  for _, name in ipairs({ "GetNormalizedRealmName", "GetRealmName" }) do
    local fn = rawget(_G, name)
    if type(fn) == "function" then
      local ok, realm = pcall(fn)
      if ok and type(realm) == "string" and realm ~= "" then
        return realm
      end
    end
  end
  return ""
end

local function now()
  return FG.U.now()
end

local function announce(key)
  FG.Emit("FG_CHAT_UPDATE", { [key] = true }, Unread.Total(chat.convs))
end

-- Removes the saved whisper history of a conversation when the history is on (through its own rules).
local function clearHistory(conv)
  if chat.Archive then
    chat.Archive.Forget(conv.key)
  end
  local main = FG.db and FG.db.settings
  local logic = FG.ChatHistoryLogic
  if conv.kind == "whisper" and logic and Conv.HistoryAllowed(main) and type(FG.db.chatWhispers) == "table" then
    logic.ClearContact(FG.db.chatWhispers, conv.name, homeRealm())
  end
end

-- Text dialog for a nickname or a note ------------------------------------------------------------------------

local function buildPrompt()
  local d = FG.Dialogs.Create("FGChatPromptDialog", 420, 190)
  d.text = W.Text(d, { role = "text", wrap = true })
  d.text:SetPoint("TOPLEFT", 16, -48)
  d.text:SetWidth(388)
  d.box = W.EditBox(d, { height = 30 })
  d.box:SetPoint("TOPLEFT", d.text, "BOTTOMLEFT", 0, -10)
  d.box:SetWidth(388)
  d.edit = d.box.edit
  d.ok =
    W.Action(d, { label = "act.confirm", icon = "check", tooltip = "common.confirm", variant = "primary", width = 110 })
  d.ok:SetPoint("BOTTOMRIGHT", -16, 14)
  d.cancel = W.Action(d, { label = "act.cancel", icon = "close", tooltip = "common.cancel", width = 110 })
  d.cancel:SetPoint("RIGHT", d.ok, "LEFT", -8, 0)
  local function save()
    if d.field and d.key then
      ML.SetText(chat.db, d.field, d.key, d.edit:GetText())
      announce(d.key)
    end
    d:Hide()
  end
  d.ok:SetScript("OnClick", FG.Wrap("chat-prompt-ok", save))
  d.cancel:SetScript(
    "OnClick",
    FG.Wrap("chat-prompt-cancel", function()
      d:Hide()
    end)
  )
  d.edit:SetScript("OnEnterPressed", FG.Wrap("chat-prompt-enter", save))
  return d
end

-- Opens the dialog for "nicknames" or "notes" of a conversation.
function Menu.Ask(field, key)
  local d = prompt
  if not d then
    return false
  end
  local limit = field == "nicknames" and chat.Store.NICKNAME_BYTES or chat.Store.NOTE_BYTES
  d.field, d.key = field, key
  local name = field == "nicknames" and "nickname" or "note"
  W.SetText(d.title, "chat.dialog." .. name .. ".title")
  W.SetText(d.text, "chat.dialog." .. name .. ".text")
  d.edit:SetMaxLetters(limit)
  d.edit:SetText(chat.db[field][key] or "")
  d:SetHeight(math.max(190, 48 + math.ceil(d.text:GetStringHeight()) + 10 + 30 + 64))
  d:Show()
  C_Timer.After(0.05, function()
    if d:IsShown() then
      d.edit:SetFocus()
      d.edit:HighlightText()
    end
  end)
  return true
end

-- Entries -------------------------------------------------------------------------------------------------------

local function invitable(conv)
  if conv.kind ~= "whisper" or not (FG.Invites and FG.Invites.GroupInviteBlock) then
    return false
  end
  local name = FG.PlayerName.Clean(conv.name or "")
  return name ~= "" and FG.Invites.GroupInviteBlock(name) == nil
end

local function context(conv)
  local db = chat.db
  return {
    unread = Unread.Count(conv) > 0,
    pinned = db.pins[conv.key] == true,
    muted = Unread.IsMuted(db.muted[conv.key], now()) == true,
    invite = invitable(conv),
    team = conv.kind == "team",
  }
end

-- Entries of the views (ChatMini.lua) behind the ones of the rules.
local function withViews(items, conv)
  local Mini = chat.Mini
  if not Mini then
    return items
  end
  local view = chat.db.view.chats[conv.key]
  for _, entry in ipairs(Mini.MenuItems(conv, view or chat.db.view.mode, Mini.IsOpen(conv.key))) do
    items[#items + 1] = entry
  end
  return items
end

-- Sets the view of a chat. The window that shows it follows: a mini window for "mini", the big window for the
-- others (a chat that was in a mini window moves back).
local function setView(conv, mode)
  if not chat.Store.Set(chat.db, "modes", conv.key, mode) then
    return false
  end
  local Mini, Window = chat.Mini, chat.Window
  if mode == "mini" then
    if Mini.Open(conv.key) then
      Window.Deselect(conv.key)
    end
  elseif Mini.IsOpen(conv.key) then
    Mini.Close(conv.key)
    if Window.Open() then
      Window.SelectConversation(conv.key)
    end
  end
  return true
end

local function choose(item)
  local key = state.key
  Menu.Close()
  local conv = key and chat.convs.convs[key]
  if not conv then
    return
  end
  local id = item.id
  if id == "viewMessenger" or id == "viewCompact" or id == "viewMini" then
    if setView(conv, id == "viewMessenger" and "messenger" or id == "viewCompact" and "compact" or "mini") then
      announce(key)
    end
    return
  elseif id == "openMini" then
    local frame, why = chat.Mini.Open(key, { focus = true })
    if frame then
      chat.Window.Deselect(key)
    else
      FG.Notify(string.format(L["chat.mini." .. (why == "combat" and "combat" or "full")], chat.Mini.MAX), "warning")
    end
    return
  end
  if id == "teamPanel" or id == "teamLeave" then
    local tid = chat.TeamsUILogic.TeamId(key)
    if id == "teamPanel" then
      chat.Window.TeamPanel(key)
    elseif tid then
      chat.TeamPanel.ConfirmLeave(tid)
    end
    return
  end
  if id == "invite" then
    FG.Invites.InviteToGroup(FG.PlayerName.Clean(conv.name))
    return
  end
  local ok, why = ML.Run(id, { db = chat.db, key = key, conv = conv, now = now() })
  if ok and id == "markUnread" then
    chat.Window.Deselect(key)
  end
  if why == "copyAll" then
    chat.LineActions.CopyAll(conv)
  elseif why == "prompt" then
    Menu.Ask(id == "nickname" and "nicknames" or "notes", key)
  elseif why == "confirm" then
    FG.Dialogs.Confirm("chat.menu.clear.title", "chat.menu.clear.text", function()
      if ML.Clear({ state = chat.convs, key = key, history = clearHistory }) then
        announce(key)
        FG.Notify(L["chat.menu.cleared"], "success")
      end
    end, nil, { yesKey = "chat.menu.clear.yes" })
  elseif ok then
    announce(key)
  end
end

-- The frames -----------------------------------------------------------------------------------------------------

local function paintRow(row)
  local on = row.index == state.index and pop:IsShown()
  row.hl:SetColorTexture(1, 1, 1, on and 0.1 or 0)
  row.bar:SetShown(on)
end

local function newRow(index)
  local row = CreateFrame("Button", nil, pop)
  row.index = index
  row.hl = row:CreateTexture(nil, "BACKGROUND")
  row.hl:SetAllPoints()
  row.bar = row:CreateTexture(nil, "ARTWORK")
  row.bar:SetPoint("TOPLEFT")
  row.bar:SetPoint("BOTTOMLEFT")
  row.bar:SetWidth(3)
  row.text = W.Text(row, { role = "ui", color = "text" })
  row.text:SetPoint("LEFT", row, "LEFT", 12, 0)
  row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.text:SetWordWrap(false)
  FG.Bind(row, function()
    row.bar:SetColorTexture(Theme.color("accent2"))
  end)
  row:SetScript("OnEnter", function(self)
    state.index = self.index
    for _, other in ipairs(rows) do
      paintRow(other)
    end
  end)
  row:SetScript(
    "OnClick",
    FG.Wrap("chat-menu-choose", function(self)
      if state.items[self.index] then
        choose(state.items[self.index])
      end
    end)
  )
  return row
end

local function move(step)
  state.index = ML.Move(state.items, state.index, step)
  for _, row in ipairs(rows) do
    paintRow(row)
  end
end

local function onKey(self, key)
  if key == "ESCAPE" then
    Menu.Close()
  elseif key == "UP" then
    move(-1)
  elseif key == "DOWN" then
    move(1)
  elseif key == "HOME" then
    state.index = 1
    move(0)
  elseif key == "END" then
    state.index = #state.items
    move(0)
  elseif key == "ENTER" or key == "NUMPADENTER" or key == "SPACE" then
    local item = state.items[state.index]
    if item then
      choose(item)
    end
  end
  -- Every other key stays here while the menu is open: the frame never passes keys on.
  FG.PropagateKeys(self, false)
end

-- Builds the menu frames and the text dialog. Called once with the window, out of combat.
function Menu.Create()
  if pop then
    return
  end
  blocker = CreateFrame("Button", nil, UIParent)
  blocker:SetAllPoints(UIParent)
  blocker:SetFrameStrata("TOOLTIP")
  blocker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  blocker:SetScript("OnClick", Menu.Close)
  blocker:Hide()
  pop = CreateFrame("Frame", "FGChatMenu", UIParent)
  pop:SetFrameStrata("TOOLTIP")
  pop:SetFrameLevel(blocker:GetFrameLevel() + 5)
  pop:SetClampedToScreen(true)
  pop:EnableKeyboard(true)
  pop:SetScript("OnKeyDown", function(self, key)
    FG.Safe("chat-menu-key", onKey, self, key)
  end)
  W.Fill(pop, "surface", 1)
  W.Border(pop, "accentDim", 1)
  pop:Hide()
  for i = 1, Menu.PREBUILD do
    rows[i] = newRow(i)
    rows[i]:Hide()
  end
  prompt = buildPrompt()
end

function Menu.IsOpen()
  return pop ~= nil and pop:IsShown()
end

function Menu.Close()
  if pop and pop:IsShown() then
    pop:Hide()
    blocker:Hide()
    state.key = nil
    return true
  end
  return false
end

-- Fills the rows for the entries and sizes the frame. Returns false when there are more entries than rows.
local function fill(items)
  if #items > #rows then
    return false
  end
  local height, width, previous = PAD, MIN_W, nil
  for i, row in ipairs(rows) do
    local item = items[i]
    if not item then
      row:Hide()
    else
      if previous and previous.group ~= item.group then
        height = height + GROUP_GAP
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", pop, "TOPLEFT", 1, -height)
      row:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -1, -height)
      row:SetHeight(rowHeight())
      W.SetText(row.text, item.key)
      row.fgName = L[item.key]
      row:Show()
      width = math.max(width, math.ceil(row.text:GetStringWidth()) + 24)
      height = height + rowHeight()
      previous = item
    end
  end
  pop:SetSize(math.min(width, MAX_W), height + PAD)
  return true
end

-- Opens the menu for a conversation. anchor: a frame the menu hangs under (the menu button, or the window for
-- the keyboard); opts.cursor: at the mouse instead. False when the conversation is unknown or the frames
-- are not built.
function Menu.Open(key, anchor, opts)
  local conv = pop and chat.convs and chat.convs.convs[key]
  if not conv then
    return false
  end
  if FG.Popups then
    FG.Popups.close()
  end
  state.key, state.items, state.index = key, withViews(ML.Items(context(conv)), conv), 1
  if not fill(state.items) then
    state.key = nil
    return false
  end
  local ref = anchor or UIParent
  pop:SetScale(ref:GetEffectiveScale() / UIParent:GetEffectiveScale())
  pop:ClearAllPoints()
  if opts and opts.cursor then
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    pop:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s / pop:GetScale(), y / s / pop:GetScale())
  elseif anchor then
    pop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  else
    pop:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  blocker:Show()
  pop:Show()
  FG.PropagateKeys(pop, false)
  for _, row in ipairs(rows) do
    paintRow(row)
  end
  return true
end

-- The entries now on offer (tests, screen readers): { id, key, group }.
function Menu.Items()
  return state.items
end

-- A new look or scale changes the sizes the open menu was filled with: it closes instead.
FG.On("FG_UI_REFRESHED", Menu.Close)
