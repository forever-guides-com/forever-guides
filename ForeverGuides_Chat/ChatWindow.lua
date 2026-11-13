-- The window of Forever Chat: a frame in the window system of the main add-on (WindowShell, kind "chat" of
-- WindowStyle) that holds the conversation list (ChatList.lua) and the thread view (ChatThread.lua). From 560 px
-- on both sit side by side, below that one pane shows at a time (the list, or the thread with a way back).
-- It is movable, resizable by the grip, remembers size, place and tab, takes size and text scale from the
-- settings and closes on Esc. Keys work while the mouse is over the window or after a click in it: Up, Down,
-- Home, End pick a chat, Left and Right change the tab, Tab searches, Enter goes on to the input line
-- (ChatInput.lua), Shift+F10 or the menu key opens the menu of the chat (ChatMenu.lua), PageUp and PageDown
-- scroll, Ctrl+R opens the reactions of the last line (add-on extras, opt-in), Ctrl+M switches the look, Ctrl+N writes a new message (ChatNew.lua), Esc closes unless "keepOpenOnEsc" is on (or clears the
-- search first). The gear in the title bar swaps the panes for the options (ChatSettings.lua).
-- Nothing is built in combat; the window opens after it.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, Theme, U, Shell, WS = FG.W, FG.L, FG.Theme, FG.U, FG.WindowShell, FG.WindowStyle
local LL, List, Thread = chat.ListLogic, chat.List, chat.Thread

local Window = {}
chat.Window = Window

Window.DEFAULT_W, Window.DEFAULT_H = 760, 480
Window.MIN_W, Window.MIN_H, Window.MAX_W, Window.MAX_H = 320, 300, 1400, 1000
-- From this width on the list and the thread sit side by side.
Window.WIDE = 560
Window.LIST_MIN, Window.LIST_MAX, Window.LIST_SHARE = 200, 300, 0.34
-- STRIP_H is the title strip of the flat look; in the skin "forever" the metal bar replaces it (Shell.HeadHeight).
-- PAD is the space between the content and the frame on every side, under the title area too.
local STRIP_H, PAD, GAP = 24, 8, 8
local LOGO = 16

local frame
-- tabKey: the chat picked last in each tab (memory only), what a tab shows again when it is picked.
local state = { key = nil, seq = nil, page = "list", active = false, pendingKey = nil, settings = false, tabKey = {} }
local roster
local emitting = false

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function frameDb()
  local frames = FG.db.frames
  if type(frames.chatWindow) ~= "table" then
    frames.chatWindow = {}
  end
  return frames.chatWindow
end

-- Guild members by name key, for the class, the level and the zone of a whisper partner (built once, dropped on
-- every update of the guild list).
local function members()
  if roster == nil then
    roster = {}
    local snap = FG.GuildData and FG.GuildData.Get()
    for _, member in ipairs(snap and snap.members or {}) do
      local key = FG.PlayerName.Key(member.name)
      if key ~= "" then
        roster[key] = member
      end
    end
  end
  return roster
end

local function memberOfName(name)
  if type(name) ~= "string" then
    return nil
  end
  return members()[FG.PlayerName.Key(name)]
end

local function memberOfKey(key)
  local conv = chat.convs and chat.convs.convs[key]
  return conv and conv.kind == "whisper" and memberOfName(conv.name) or nil
end

local function classOf(member)
  return member and FG.GuildKit.KNOWN_CLASS[member.class] and member.class or nil
end

-- Class and guild data of a name or a chat for the other windows of the add-on (the mini windows).
function Window.ClassOfName(name)
  return classOf(memberOfName(name)) or (chat.Class and chat.Class.Cached(name)) or nil
end

function Window.ClassOfKey(key)
  return classOf(memberOfKey(key))
end

Window.MemberOfKey = memberOfKey

local function wide(f)
  return (f:GetWidth() or 0) >= Window.WIDE
end

-- True while lines in view count as read: the window shows the thread.
local function reading()
  return frame ~= nil and frame:IsShown() and not state.settings and (wide(frame) or state.page == "thread")
end

-- Geometry --------------------------------------------------------------------------------------------------

local function setBounds(f)
  if f.SetResizeBounds then
    f:SetResizeBounds(Window.MIN_W, Window.MIN_H, Window.MAX_W, Window.MAX_H)
  elseif f.SetMinResize then
    f:SetMinResize(Window.MIN_W, Window.MIN_H)
  end
end

-- Places what depends on the title area: the content under it, the logo and the buttons centered in it. Runs again
-- when the title area changes (flat to forever and back).
local function fitHead(f)
  if not f.content then
    return
  end
  local head = Shell.HeadHeight(f)
  f.content:ClearAllPoints()
  f.content:SetPoint("TOPLEFT", PAD, -(head + PAD))
  f.content:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  local logo = Shell.BarControlSize(f, LOGO)
  f.emblem:SetSize(logo, logo)
  local side = Shell.BarControlSize(f, 18)
  f.close:SetSize(side, side)
  f.gear:SetSize(side, side)
end

local function place(f)
  local db = frameDb()
  setBounds(f)
  f:SetScale(Theme.windowScale())
  f:SetSize(
    U.clamp(finite(db.w) and db.w or Window.DEFAULT_W, Window.MIN_W, Window.MAX_W),
    U.clamp(finite(db.h) and db.h or Window.DEFAULT_H, Window.MIN_H, Window.MAX_H)
  )
  f:ClearAllPoints()
  if finite(db.x) and finite(db.y) then
    local s = f:GetScale() or 1
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x / s, db.y / s)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

local function save(f)
  if not f.ready then
    return
  end
  local db = frameDb()
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s = f:GetScale() or 1
    db.x, db.y = left * s, top * s
  end
  db.w, db.h = f:GetWidth(), f:GetHeight()
  db.tab = f.list and f.list.tab or db.tab
  db.last = state.key or db.last
end

-- Places the panes for the window size. The thread is redrawn at once when sync is true, else after the
-- window stopped changing (a drag on the grip calls this on every step).
function Window.Layout(sync)
  local f = frame
  if not f then
    return
  end
  local w, h = f:GetWidth() or Window.MIN_W, f:GetHeight() or Window.MIN_H
  local cw, ch = w - 2 * PAD, h - Shell.HeadHeight(f) - 2 * PAD
  local list, thread = f.list, f.thread
  if f.settings then
    f.settings.frame:SetShown(state.settings)
  end
  if state.settings and f.settings then
    list.frame:Hide()
    f.pane:Hide()
    f.settings.frame:ClearAllPoints()
    f.settings.frame:SetAllPoints(f.content)
    f.settings.view:Layout()
    return
  end
  local side = wide(f)
  local listW = cw
  local threadW = cw
  f.pane:ClearAllPoints()
  list.frame:ClearAllPoints()
  if side then
    listW = math.floor(U.clamp(cw * Window.LIST_SHARE, Window.LIST_MIN, Window.LIST_MAX))
    threadW = cw - listW - GAP
    list.frame:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
    list.frame:SetPoint("BOTTOMLEFT", f.content, "BOTTOMLEFT", 0, 0)
    list.frame:SetWidth(listW)
    f.pane:SetPoint("TOPLEFT", f.content, "TOPLEFT", listW + GAP, 0)
    f.pane:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMRIGHT", 0, 0)
    list.frame:Show()
    f.pane:Show()
  else
    local showThread = state.page == "thread" and state.key ~= nil
    list.frame:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
    list.frame:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMRIGHT", 0, 0)
    f.pane:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
    f.pane:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMRIGHT", 0, 0)
    list.frame:SetShown(not showThread)
    f.pane:SetShown(showThread)
  end
  f.inputHost:SetWidth(threadW)
  if f.input then
    f.input:Fit(threadW)
  end
  local input = f.inputHost:GetHeight() or 0
  thread.frame:ClearAllPoints()
  thread.frame:SetPoint("TOPLEFT", f.pane, "TOPLEFT", 0, 0)
  thread.frame:SetPoint("BOTTOMRIGHT", f.inputHost, "TOPRIGHT", 0, input > 0 and GAP or 0)
  local teamPanel = chat.TeamPanel and chat.TeamPanel.IsOpen()
  thread.frame:SetShown(not teamPanel)
  thread:SetBack(not side and state.page == "thread")
  thread:SetViewSize(threadW, ch - input - (input > 0 and GAP or 0))
  list:Layout(listW)
  -- The panel for a new message takes the place of the list while it is open.
  if chat.New.IsOpen() then
    list.frame:Hide()
    if not side then
      f.pane:Hide()
    end
    chat.New.Place(side and listW or cw)
  end
  local function heavy()
    if frame and frame:IsShown() then
      thread:Refresh()
    end
  end
  if sync then
    heavy()
  else
    FG.Debounce("chat-window-size", 0.05, heavy)
  end
end

-- Drawing ---------------------------------------------------------------------------------------------------

local function inCombatNeedsFrames(f)
  return FG.InCombat() and (f.list:NeedsFrames() or f.thread:NeedsFrames())
end

-- Draws list and thread again. keys (optional): the set of changed conversations; the thread follows only
-- when its conversation is in it.
function Window.Refresh(keys)
  local f = frame
  if not (f and f:IsShown()) then
    return
  end
  if inCombatNeedsFrames(f) then
    state.pending = true
    return
  end
  f.list:Refresh()
  if state.key and (keys == nil or keys[state.key] or next(keys) == nil) then
    f.thread:Refresh()
    if not f.thread.conv then
      state.key, state.page = nil, "list"
      f.list:SetSelected(nil)
      f.input:SetConversation(nil, true)
      Window.Layout(true)
    end
  elseif not state.key then
    -- The text without a chat names the tab, and a chat that came in changes it to the plain request.
    f.thread:Refresh()
  end
end

-- Moves the unread state to the others (badge, list): the list is redrawn here, the event carries the total.
local function readChanged(key)
  emitting = true
  FG.Emit("FG_CHAT_UPDATE", { [key] = true }, chat.Unread.Total(chat.convs))
  emitting = false
  if frame and frame:IsShown() then
    frame.list:Refresh()
  end
end

-- Selection -------------------------------------------------------------------------------------------------

-- Shows a conversation in the thread and marks it in the list. opts.seq scrolls to that line. opts.browse
-- keeps a narrow window on the list (arrow keys). False for an unknown key.
function Window.SelectConversation(key, opts)
  opts = opts or {}
  local conv = chat.convs and chat.convs.convs[key]
  if not conv then
    return false
  end
  if not frame then
    state.pendingKey = key
    return true
  end
  if state.settings then
    Window.ShowSettings(false)
  end
  if chat.Mini and chat.Mini.IsOpen(key) then
    chat.Mini.Close(key)
  end
  if chat.TeamPanel and chat.TeamPanel.IsOpen() and chat.TeamPanel.TeamId() ~= chat.TeamsUILogic.TeamId(key) then
    chat.TeamPanel.Close()
  end
  state.key, state.seq = key, opts.seq
  if not opts.browse then
    state.page = "thread"
  end
  local tab = LL.TabOf(conv.kind)
  state.tabKey[tab] = key
  frame.list:SetTab(tab, true)
  frame.list:SetSelected(key, opts.seq)
  frame.input:SetConversation(key, true)
  Window.Layout(true)
  frame.thread:Show(conv, { seq = opts.seq })
  return true
end

-- Lets go of the picked chat when it is key (marking it unread: a chat that stays in view counts as read).
function Window.Deselect(key)
  if not (frame and state.key == key) then
    return
  end
  state.key, state.page = nil, "list"
  local conv = chat.convs.convs[key]
  if conv then
    state.tabKey[LL.TabOf(conv.kind)] = nil
  end
  frame.list:SetSelected(nil)
  frame.input:SetConversation(nil, true)
  frame.thread:Clear()
  Window.Layout(true)
end

-- Whether a conversation belongs to a tab.
local function inTab(conv, tab)
  return conv ~= nil and chat.Conversations.TAB_KINDS[tab][conv.kind] == true
end

-- A chat a tab may show by itself: not one marked unread by the player and not one that has a mini window.
local function pickable(conv)
  return not conv.marked and not (chat.Mini and chat.Mini.IsOpen(conv.key))
end

-- The chat a tab shows: the one picked there last, else the first of its list (pinned, then the latest).
local function tabChat(tab)
  local remembered = state.tabKey[tab] and chat.convs.convs[state.tabKey[tab]]
  if inTab(remembered, tab) and pickable(remembered) then
    return remembered.key
  end
  for _, conv in ipairs(chat.Conversations.Sorted(chat.convs, tab)) do
    if pickable(conv) then
      return conv.key
    end
  end
  return nil
end

-- The pane shows a chat of the tab that the list shows, or the empty state of that tab.
function Window.TabChanged(tab)
  local f = frame
  if not (f and chat.convs) then
    return
  end
  if state.key and inTab(chat.convs.convs[state.key], tab) then
    return
  end
  local key = tabChat(tab)
  if key then
    Window.SelectConversation(key, { browse = true })
    return
  end
  if chat.TeamPanel and chat.TeamPanel.IsOpen() then
    chat.TeamPanel.Close()
  end
  state.key, state.seq, state.page = nil, nil, "list"
  f.list:SetSelected(nil)
  f.input:SetConversation(nil, true)
  f.thread:Clear()
  Window.Layout(true)
end

-- The text of the pane while no chat is picked: it names the tab when the tab has no chat at all.
local function emptyKey()
  local tab = frame and frame.list and frame.list.tab
  if not tab then
    return "chat.empty.thread"
  end
  for _, conv in pairs(chat.convs and chat.convs.convs or {}) do
    if inTab(conv, tab) then
      return "chat.empty.thread"
    end
  end
  return "chat.empty.thread." .. tab
end

local function pick(key, seq, browse)
  Window.SelectConversation(key, { seq = seq, browse = browse })
end

local function back()
  state.page = "list"
  Window.Layout(true)
end

-- Shows the options pane (on), the chats (off) or the other of the two (nil).
function Window.ShowSettings(on)
  local f = frame
  if not (f and f.settings) then
    return false
  end
  if on == nil then
    on = not state.settings
  end
  state.settings = on == true
  if state.settings then
    f.input.edit:ClearFocus()
    chat.New.Close()
  end
  f.gear:SetSelected(state.settings)
  Window.Layout(true)
  if not state.settings then
    f.list:Refresh()
    f.thread:Refresh()
  end
  return true
end

-- Opens the panel for a new message (leaves the options first).
function Window.NewMessage()
  if not (frame and chat.New.Panel()) then
    return false
  end
  if state.settings then
    Window.ShowSettings(false)
  end
  return chat.New.Open(frame.list.tab == "teams" and "team" or nil)
end

-- Opens the panel of a team (members and actions) over the thread of its conversation.
function Window.TeamPanel(key)
  local tid = chat.TeamsUILogic.TeamId(key)
  if not (frame and tid and chat.TeamPanel) then
    return false
  end
  Window.SelectConversation(key)
  return chat.TeamPanel.Open(tid)
end

-- The panel of the team follows a change of the teams.
function Window.RefreshTeams()
  if chat.TeamPanel then
    chat.TeamPanel.Refresh()
  end
end

-- Keys ------------------------------------------------------------------------------------------------------

local function ctrlDown()
  local fn = rawget(_G, "IsControlKeyDown")
  return type(fn) == "function" and fn() == true
end

local function shiftDown()
  local fn = rawget(_G, "IsShiftKeyDown")
  return type(fn) == "function" and fn() == true
end

-- The menu of the picked chat, under the menu button (or the title bar while the line is out of sight).
function Window.OpenMenu(anchor)
  local f = frame
  if not (f and state.key) then
    return false
  end
  return chat.Menu.Open(state.key, anchor or (f.input.menu:IsVisible() and f.input.menu or f.bar))
end

-- Enter on a chat: a narrow window goes to the thread first, then the line takes the focus.
function Window.inputFocus()
  local f = frame
  if not (f and state.key) then
    return false
  end
  if not wide(f) and state.page == "list" then
    state.page = "thread"
    Window.Layout(true)
    f.input:Refresh()
  end
  return f.input:Focus()
end

-- Whether Esc leaves the window open (the option "keepOpenOnEsc", on by default).
local function keepOpenOnEsc()
  local settings = chat.Settings
  return not (settings and settings.Value) or settings.Value("keepOpenOnEsc") ~= false
end

-- The window keeps the keyboard (its keys) while shown; it takes part in the Esc stack only when Esc may close it.
local function applyEsc(f)
  Shell.SetEsc(f, true)
  if keepOpenOnEsc() then
    FG.EscStack.Remove(f)
  end
end

local function handleKey(f, key)
  if key == "ESCAPE" then
    -- The panel of a team or the form closes first, the window with the next press.
    if chat.TeamPanel.Close() or chat.New.Close() then
      return true
    end
    if keepOpenOnEsc() then
      return FG.Popups ~= nil and FG.Popups.close() == true
    end
    return FG.EscStack.Close(f)
  end
  -- Keys belong to the window only while it has the user's attention: the mouse is over it, or the last click
  -- was inside it (a click elsewhere clears that, so Enter opens the game chat again).
  if not ((state.clickEvent and state.active) or f:IsMouseOver()) then
    return false
  end
  local list, thread = f.list, f.thread
  local narrowThread = not wide(f) and state.page == "thread"
  local ctrl = ctrlDown()
  if ctrl and key == "N" then
    return Window.NewMessage()
  elseif state.settings then
    return false
  elseif ctrl and key == "M" then
    return thread:ToggleMode()
  elseif ctrl and key == "F" or key == "TAB" then
    if narrowThread then
      back()
    end
    list:FocusSearch()
    return true
  elseif key == "LEFT" and narrowThread then
    back()
    return true
  elseif key == "LEFT" or key == "RIGHT" then
    if not list.frame:IsShown() then
      return false
    end
    list:SetTab(LL.NextTab(list.tab, key == "LEFT" and -1 or 1))
    return true
  elseif ctrl and (key == "HOME" or key == "END" or key == "R") then
    return thread:Key(key, true)
  elseif key == "UP" or key == "DOWN" or key == "HOME" or key == "END" then
    return list.frame:IsShown() and list:Step(key) or false
  elseif key == "PAGEUP" or key == "PAGEDOWN" then
    if list.frame:IsShown() and not f.pane:IsShown() then
      return list:Step(key)
    end
    return thread:Key(key)
  elseif key == "APPLICATIONS" or (key == "F10" and shiftDown()) then
    return Window.OpenMenu()
  elseif key == "ENTER" or key == "NUMPADENTER" then
    if Window.inputFocus and state.key then
      Window.inputFocus()
      return true
    end
    if not wide(f) and state.page == "list" and state.key then
      state.page = "thread"
      Window.Layout(true)
      return true
    end
  end
  return false
end

-- Build -----------------------------------------------------------------------------------------------------

local function applyLook()
  local f = frame
  if not f then
    return
  end
  local style = chat.Settings.Style(frameDb().style)
  WS.Apply(f, style, f.styleParts)
  WS.ApplyShadow(f.shell.titleText, WS.TextShadow(style), Theme.rgb("accent2"))
end

local function create()
  local f = CreateFrame("Frame", "FGChatWindow", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  setBounds(f)
  f.bg = W.Fill(f, "bg", 0.97)
  f.shell = Shell.Attach(f, {
    title = "chat.win.title",
    titleHeight = STRIP_H,
    shadow = true,
    esc = false,
    onHead = function()
      fitHead(f)
      if f.ready then
        Window.Layout(false)
      end
    end,
  })
  f.bar, f.title = f.shell.titleBar, f.shell.titleText
  f.bar:HookScript(
    "OnDragStop",
    FG.Wrap("chat-move", function()
      f:StopMovingOrSizing()
      save(f)
    end)
  )
  f.emblem = f.bar:CreateTexture(nil, "ARTWORK")
  f.emblem:SetSize(16, 16)
  f.emblem:SetPoint("LEFT", 6, 0)
  f.emblem:SetTexture(FG.BadgeAssets.Path(16))
  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "common.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    FG.Wrap("chat-close", function()
      f:Hide()
    end)
  )
  f.gear = W.Action(f.bar, {
    icon = "gear",
    size = 18,
    tooltip = "chat.set.open",
    tooltipText = "chat.set.openTip",
    wrap = "chat-settings",
    opens = true,
    onClick = function()
      Window.ShowSettings()
    end,
  })
  f.gear:SetPoint("RIGHT", f.close, "LEFT", -4, 0)
  f.title:ClearAllPoints()
  f.title:SetPoint("LEFT", f.emblem, "RIGHT", 6, 0)
  f.title:SetPoint("RIGHT", f.gear, "LEFT", -4, 0)

  f.content = CreateFrame("Frame", nil, f)
  fitHead(f)

  f.list = List.Create(f.content, {
    Pick = pick,
    Menu = function(key)
      chat.Menu.Open(key, nil, { cursor = true })
    end,
    ClassOf = function(key)
      return classOf(memberOfKey(key))
    end,
    New = Window.NewMessage,
    TabChanged = Window.TabChanged,
    Settings = function()
      Window.ShowSettings(true)
    end,
  })
  f.pane = CreateFrame("Frame", nil, f.content)
  -- The input line lives in this host, under the thread.
  f.inputHost = CreateFrame("Frame", nil, f.pane)
  f.inputHost:SetPoint("BOTTOMLEFT", 0, 0)
  f.inputHost:SetHeight(0)
  f.thread = Thread.Create(f.pane, {
    ClassOfName = function(name)
      return Window.ClassOfName(name)
    end,
    ClassOf = function(key)
      return classOf(memberOfKey(key))
    end,
    MemberOf = memberOfKey,
    Reading = reading,
    ReadChanged = readChanged,
    Back = back,
    EmptyKey = emptyKey,
  })

  f.input = chat.Input.Create(f.inputHost, {
    Conv = function()
      return state.key and chat.convs and chat.convs.convs[state.key] or nil
    end,
    Sent = function()
      f.thread:Refresh(true)
    end,
    Layout = function()
      Window.Layout(true)
    end,
    Menu = Window.OpenMenu,
    Leave = function()
      f.list:FocusSearch()
    end,
    Draw = Window.Refresh,
  })
  chat.Menu.Create()
  chat.TeamPanel.Build(f.pane, {
    Layout = function()
      Window.Layout(true)
    end,
  })
  f.settings = chat.Settings.CreatePane(f.content)
  f.settings.frame:Hide()
  chat.New.Build(f.content, {
    Select = function(key)
      Window.SelectConversation(key)
      Window.inputFocus()
    end,
    Layout = function()
      Window.Layout(true)
    end,
  })

  -- The grip stays inside the padding at the corner (its mark is the lower right triangle); the hit area reaches
  -- a little further out over the frame edge, so it is easy to take.
  local grip = CreateFrame("Frame", nil, f)
  grip:SetSize(PAD + 2, PAD + 2)
  grip:EnableMouse(true)
  if type(grip.SetHitRectInsets) == "function" then
    grip:SetHitRectInsets(0, -4, 0, -4)
  end
  grip:SetPoint("BOTTOMRIGHT", 0, 0)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  local tex = grip:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function()
    WS.Hold(f, "size", true)
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript(
    "OnMouseUp",
    FG.Wrap("chat-size", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "size", false)
      save(f)
      Window.Layout(true)
    end)
  )
  grip:SetScript("OnEnter", function(self)
    FG.ShowTooltip(self, L["chat.win.grip"])
  end)
  grip:SetScript("OnLeave", FG.HideTooltip)
  f.grip = grip

  f.styleParts = {
    bg = { f.bg },
    bars = f.shell.bars,
    border = f.shell.border,
    shadow = f.shell.shadow,
    chrome = { f.bar, grip },
    focus = { f.list.search.edit },
    busy = function()
      return false
    end,
  }

  f:SetScript("OnSizeChanged", function()
    if f:IsShown() then
      Window.Layout(false)
    end
  end)
  f:HookScript("OnMouseDown", function()
    state.active = true
  end)
  -- A click anywhere else takes the attention away; the event does not exist in every client, then only the
  -- mouse position counts (Window.Focused).
  state.clickEvent = pcall(f.RegisterEvent, f, "GLOBAL_MOUSE_DOWN")
  f:SetScript("OnEvent", function(self)
    state.active = self:IsMouseOver() == true
  end)
  f:SetScript("OnKeyDown", function(self, key)
    local _, handled = FG.Safe("chat-key", handleKey, self, key)
    FG.PropagateKeys(self, not handled)
  end)
  f:SetScript(
    "OnShow",
    FG.Wrap("chat-show", function()
      applyEsc(f)
      roster = nil
      applyLook()
      Window.Layout(true)
      f.input:Refresh()
      f.list:Refresh()
      f.thread:Refresh()
    end)
  )
  f:SetScript(
    "OnHide",
    FG.Wrap("chat-hide", function()
      Shell.SetEsc(f, false)
      f.list.search.edit:ClearFocus()
      f.input:SaveDraft()
      f.input.edit:ClearFocus()
      chat.Menu.Close()
      chat.New.Close()
      chat.TeamPanel.Close()
      state.active = false
      save(f)
    end)
  )
  f:Hide()
  f.ready = true
  if chat.AutoOpen then
    chat.AutoOpen.Watch(f)
  end
  return f
end

-- Public ----------------------------------------------------------------------------------------------------

function Window.Frame()
  return frame
end

function Window.IsShown()
  return frame ~= nil and frame:IsShown()
end

function Window.State()
  return state
end

-- Parts of the window: host (the frame of the input line under the thread), pane, content, thread, list and the
-- input line itself. Window.inputFocus (a function) is called on Enter while a conversation is picked.
function Window.Parts()
  return frame
      and {
        frame = frame,
        host = frame.inputHost,
        pane = frame.pane,
        thread = frame.thread,
        list = frame.list,
        input = frame.input,
      }
    or nil
end

-- Shows the window, built on first use (not in combat). Returns the frame, or nil in combat before the first
-- build.
function Window.Open()
  if not FG.db then
    return nil
  end
  if not frame then
    if FG.InCombat() then
      FG.Notify(L["chat.win.combat"], "warning")
      return nil
    end
    frame = create()
    local tab = frameDb().tab
    if tab then
      frame.list:SetTab(tab, true)
    end
  end
  place(frame)
  state.active = true
  if frame:IsShown() then
    Window.Layout(true)
    Window.Refresh()
  else
    frame:Show()
  end
  if state.pendingKey then
    local key = state.pendingKey
    state.pendingKey = nil
    Window.SelectConversation(key)
  elseif not state.key then
    -- The tab of the last session stays. Its chat comes back when it belongs to that tab (the list marks it, a
    -- narrow window stays on the list); without a saved tab the chat sets the tab. Opening never reads a chat
    -- the player did not pick.
    local db = frameDb()
    local conv = type(db.last) == "string" and chat.convs.convs[db.last] or nil
    if conv and (db.tab == nil or inTab(conv, frame.list.tab)) then
      Window.SelectConversation(db.last, { browse = true })
    end
  end
  frame:Raise()
  return frame
end

function Window.Close()
  if frame then
    frame:Hide()
  end
end

function Window.Toggle()
  if Window.IsShown() then
    Window.Close()
  else
    Window.Open()
  end
end

chat.Open, chat.Close, chat.Toggle = Window.Open, Window.Close, Window.Toggle
chat.SelectConversation = Window.SelectConversation

-- Events ----------------------------------------------------------------------------------------------------

FG.On("FG_CHAT_UPDATE", function(_, keys)
  if not emitting and Window.IsShown() then
    Window.Refresh(type(keys) == "table" and keys or nil)
  end
end)
FG.On("FG_GUILD_UPDATE", function()
  roster = nil
  if Window.IsShown() then
    Window.Refresh()
  end
end)
FG.On("FG_UI_REFRESHED", function()
  if Window.IsShown() then
    Window.Layout(true)
    frame.list:Refresh()
  end
end)
-- An option of the messenger changed: the look, the time stamps and the views redraw.
FG.On("FG_CHAT_SETTING", function(_, id)
  if not frame then
    return
  end
  if id == "opacity" then
    applyLook()
  elseif id == "keepOpenOnEsc" then
    if frame:IsShown() then
      applyEsc(frame)
    end
  elseif id == "timeFormat" or id == "timeSeconds" or id == "defaultMode" or id == "views" or id == "classColors" then
    if frame:IsShown() then
      frame.thread:Refresh()
      frame.list:Refresh()
    end
  end
end)
FG.On("FG_SETTING_CHANGED", function(_, path)
  if not frame then
    return
  end
  if WS.AffectsKind(path, "chat") then
    applyLook()
  elseif path == "settings.scale" then
    frame:SetScale(Theme.windowScale())
  end
end)
-- Switched off in the main add-on: no window of the messenger stays on screen.
FG.On("FG_SUBADDON_CHANGED", function(_, id)
  if id == "chat" and FG.SubAddons.State("chat") ~= "active" then
    chat.Menu.Close()
    chat.New.Close()
    chat.Mini.CloseAll()
    Window.Close()
  end
end)
FG.On("PLAYER_REGEN_ENABLED", function()
  if state.pending then
    state.pending = false
    Window.Refresh()
  end
end)
FG.On("PLAYER_LOGOUT", function()
  if frame and frame:IsShown() then
    save(frame)
  end
end)

-- The main add-on opens the window through its launcher.
chat.hook.Register({
  Open = Window.Open,
  Close = Window.Close,
  Toggle = Window.Toggle,
  IsShown = Window.IsShown,
  SelectConversation = Window.SelectConversation,
  Window = Window,
  Store = chat.Store,
  Db = function()
    return chat.db
  end,
  Status = function()
    return chat.status
  end,
  State = function()
    return chat.convs
  end,
  Conversations = chat.Conversations,
  Unread = chat.Unread,
  Search = chat.Search,
  Ingest = chat.Ingest,
  Class = chat.Class,
  TextLogic = chat.TextLogic,
  LineActions = chat.LineActions,
  ClassLogic = chat.ClassLogic,
  Archive = chat.Archive,
  ArchiveLogic = chat.ArchiveLogic,
  Send = chat.Send,
  SendLogic = chat.SendLogic,
  WayLogic = chat.WayLogic,
  Secure = chat.Secure,
  Queue = chat.Queue,
  Input = chat.Input,
  InputLogic = chat.InputLogic,
  Settings = chat.Settings,
  SettingsLogic = chat.SettingsLogic,
  New = chat.New,
  Mini = chat.Mini,
  Menu = chat.Menu,
  MenuLogic = chat.MenuLogic,
  Peer = chat.Peer,
  PeerLogic = chat.PeerLogic,
  Teams = chat.Teams,
  TeamsLogic = chat.TeamsLogic,
  TeamsUILogic = chat.TeamsUILogic,
  TeamsView = chat.TeamsView,
  TeamForm = chat.TeamForm,
  TeamPanel = chat.TeamPanel,
  IconPicker = chat.IconPicker,
  List = chat.List,
  ListLogic = chat.ListLogic,
  Thread = chat.Thread,
  ThreadLogic = chat.ThreadLogic,
})
