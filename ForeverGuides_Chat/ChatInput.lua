-- Forever Chat, the input line under the thread: one line, Enter sends to the picked conversation through
-- Send.Send (never on its own: the only caller is the Enter key and the Send button). Under it sit the reason
-- a message was refused, a strip for held messages (a click sends, retries or discards them) and the length
-- counter. A conversation that cannot be written to (no group, no guild) locks the line and says why. The
-- text of every conversation is kept as a draft (Store, "drafts") and comes back when it is picked again;
-- Up and Down walk through the last sent inputs (memory only). The rules are ChatInputLogic.lua. This is
-- the add-on's own line: the game's chat line is never touched; shift-clicked links reach it through a
-- secure post-hook of ChatEdit_InsertLink while the line has focus.
--
-- win = { Conv() -> conversation or nil, Sent(conv), Layout(), Menu(), Leave(), Draw(keys) }. The window has one
-- line; every mini window (ChatMini.lua) has its own (opts.mini), they all follow the same events.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, K = FG.W, FG.L, FG.PageKit
local IL, Send, Queue, Store = chat.InputLogic, chat.Send, chat.Queue, chat.Store

local Input = {}
chat.Input = Input

local GAP, ROW, BUTTON = 6, 30, 28

-- The one line of the window (tests find it here) and every line that exists (the events reach them all).
local current
local all = {}

local function global(name)
  return rawget(_G, name)
end

local function enabled(frame, on)
  if frame.SetEnabled then
    frame:SetEnabled(on)
  end
end

local function hookLinks()
  if Input.linkHooked then
    return
  end
  local hook, target = global("hooksecurefunc"), global("ChatEdit_InsertLink")
  if type(hook) ~= "function" or type(target) ~= "function" then
    return
  end
  Input.linkHooked = true
  hook("ChatEdit_InsertLink", function(link)
    local text = FG.AutoGuard.Safe(link)
    if type(text) ~= "string" then
      return
    end
    for _, line in ipairs(all) do
      if line.edit:HasFocus() then
        pcall(line.edit.Insert, line.edit, text)
        return
      end
    end
  end)
end

function Input.Create(host, win, opts)
  local line = { host = host, win = win, key = nil, refused = nil, locked = nil, history = IL.NewHistory() }
  if not (opts and opts.mini) then
    current = line
  end
  all[#all + 1] = line

  line.notice = W.Text(host, { role = "micro", color = "warning", wrap = true })
  line.notice:Hide()

  local held = CreateFrame("Frame", nil, host)
  held:Hide()
  held.text = W.Text(held, { role = "micro", color = "textSecondary", wrap = true })
  held.release = W.Action(held, {
    key = "chat.queue.release",
    variant = "primary",
    height = 24,
    wrap = "chat-release",
    onClick = function()
      line:ReleaseHeld()
    end,
  })
  held.discard = W.Action(held, {
    key = "chat.queue.discard",
    height = 24,
    wrap = "chat-discard",
    onClick = function()
      line:DiscardHeld()
    end,
  })
  line.held = held

  local row = CreateFrame("Frame", nil, host)
  line.row = row
  line.menu = W.Action(row, {
    icon = "gear",
    size = BUTTON,
    tooltip = "chat.input.menu",
    tooltipText = "chat.input.menuTip",
    wrap = "chat-input-menu",
    onClick = function()
      win.Menu(line.menu)
    end,
  })
  line.menu:SetPoint("LEFT", row, "LEFT", 0, 0)
  line.send = W.Action(row, {
    key = "chat.input.send",
    variant = "primary",
    height = BUTTON,
    tooltip = "chat.input.send",
    tooltipText = "chat.input.sendTip",
    wrap = "chat-send",
    onClick = function()
      line:Submit()
    end,
  })
  line.send:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  -- The counter has its own line above the row, so a narrow window keeps room for the box.
  line.counter = W.Text(host, { role = "micro", color = "textMuted", justify = "RIGHT" })
  line.counter:Hide()
  line.box = W.EditBox(row, { placeholder = "chat.input.placeholder", height = ROW })
  line.box:SetPoint("LEFT", line.menu, "RIGHT", GAP, 0)
  line.box:SetPoint("RIGHT", line.send, "LEFT", -GAP, 0)
  chat.List.FitPlaceholder(line.box)
  local edit = line.box.edit
  line.edit = edit
  edit:SetMaxLetters(IL.MAX_BYTES)
  -- Enter sends and keeps the focus (the stock box would drop it).
  edit:SetScript(
    "OnEnterPressed",
    FG.Wrap("chat-input-enter", function()
      line:Submit()
    end)
  )
  edit:SetScript("OnTabPressed", function()
    edit:ClearFocus()
    win.Leave()
  end)
  edit:SetScript(
    "OnArrowPressed",
    FG.Wrap("chat-input-arrow", function(_, key)
      local text = IL.Recall(line.history, key, edit:GetText())
      if text then
        edit:SetText(text)
        edit:SetCursorPosition(#text)
      end
    end)
  )
  edit:HookScript(
    "OnTextChanged",
    FG.Wrap("chat-input-text", function()
      line:Changed()
    end)
  )
  edit:HookScript("OnKeyDown", function(_, key)
    local shift = global("IsShiftKeyDown")
    if key == "APPLICATIONS" or (key == "F10" and type(shift) == "function" and shift()) then
      win.Menu(line.menu)
    end
  end)
  hookLinks()

  -- Layout: notice, held strip and the row stack from the top. Returns the height the host needs.
  function line:Fit(width)
    if not self.key then
      host:SetHeight(0)
      host:Hide()
      return 0
    end
    host:Show()
    local top = 0
    local notice = self.notice
    if notice:IsShown() then
      notice:ClearAllPoints()
      notice:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
      notice:SetWidth(width)
      top = math.ceil(notice:GetStringHeight()) + GAP
    end
    if held:IsShown() then
      held:ClearAllPoints()
      held:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
      held:SetWidth(width)
      held.text:ClearAllPoints()
      held.text:SetPoint("TOPLEFT", held, "TOPLEFT", 0, 0)
      held.text:SetWidth(width)
      local textH = math.ceil(held.text:GetStringHeight())
      local cap = math.floor((width - GAP) / 2)
      held.release:ClearAllPoints()
      held.release:SetPoint("TOPLEFT", held.text, "BOTTOMLEFT", 0, -4)
      held.release:SetWidth(math.min(held.release:FullWidth(), cap))
      held.discard:ClearAllPoints()
      held.discard:SetPoint("LEFT", held.release, "RIGHT", GAP, 0)
      held.discard:SetWidth(math.min(held.discard:FullWidth(), cap))
      local heldH = textH + 4 + 24
      held:SetHeight(heldH)
      top = top + heldH + GAP
    end
    local counter = self.counter
    if counter:IsShown() then
      counter:ClearAllPoints()
      counter:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
      counter:SetWidth(width)
      top = top + math.ceil(counter:GetStringHeight()) + 2
    end
    local rowH = math.max(K.scaledHeight(ROW), BUTTON)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
    row:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -top)
    row:SetHeight(rowH)
    line.send:SetWidth(line.send:FullWidth())
    local height = top + rowH
    host:SetHeight(height)
    return height
  end

  -- Draws the notice, the strip, the counter and the locks from the state; asks the window for a new layout
  -- when the height changed.
  function line:Refresh(quiet)
    local conv = win.Conv()
    local before = host:GetHeight() or 0
    if not (conv and self.key) then
      self.notice:Hide()
      held:Hide()
      line:Fit(host:GetWidth() or 0)
      if before ~= 0 and not quiet then
        win.Layout()
      end
      return
    end
    local ok, why = Input.Available(conv)
    self.locked = (not ok) and why or nil
    if ok and IL.AVAILABILITY[self.refused] then
      self.refused = nil
    end
    local lock = self.locked ~= nil
    enabled(edit, not lock)
    edit:EnableMouse(not lock)
    self.box:SetAlpha(lock and 0.5 or 1)
    if lock and edit:HasFocus() then
      edit:ClearFocus()
    end
    enabled(self.send, not lock)
    local key = IL.NoticeKey(self.locked, self.refused, conv.kind)
    if key then
      W.SetText(self.notice, key)
      self.notice:Show()
    else
      self.notice:Hide()
    end
    local view = IL.HeldView(IL.Held(Queue.List(), conv.key))
    if view then
      local text = view.count and string.format(L[view.key], view.count) or L[view.key]
      held.text:SetText(text)
      W.SetText(held.release.label, view.release)
      held.release.fgNameKey = view.release
      held:Show()
    else
      held:Hide()
    end
    self:UpdateCounter()
    local height = self:Fit(host:GetWidth() or 0)
    if height ~= before and not quiet then
      win.Layout()
    end
  end

  function line:UpdateCounter()
    local counter = IL.Counter(edit:GetText())
    if counter then
      self.counter:SetText(string.format(L[counter.key], IL.CounterArgs(counter)))
      W.SetColor(self.counter, counter.over and "danger" or "textMuted")
    else
      self.counter:SetText("")
    end
    self.counter:SetShown(counter ~= nil)
  end

  -- Typing: the draft follows, an old refusal goes away.
  function line:Changed()
    if not self.key then
      return
    end
    local text = edit:GetText()
    Store.Set(chat.db, "drafts", self.key, not IL.IsBlank(text) and text or nil)
    if chat.Peer and self.host:IsVisible() then
      FG.Safe("chat-peer-typing", chat.Peer.OnTyping, self.key, not IL.IsBlank(text))
    end
    if self.refused then
      self.refused = nil
      self:Refresh()
      return
    end
    self:UpdateCounter()
    local before = host:GetHeight() or 0
    if self:Fit(host:GetWidth() or 0) ~= before then
      win.Layout()
    end
  end

  function line:SaveDraft()
    if self.key then
      local text = edit:GetText()
      Store.Set(chat.db, "drafts", self.key, not IL.IsBlank(text) and text or nil)
    end
  end

  -- The window picked another conversation (nil: none). The draft of the old one is kept, the one of the new
  -- one comes back.
  function line:SetConversation(key, quiet)
    if self.key == key then
      self:Refresh(quiet)
      return
    end
    self:SaveDraft()
    self.key, self.refused = key, nil
    IL.Reset(self.history)
    edit:SetText(key and chat.db.drafts[key] or "")
    self:Refresh(quiet)
  end

  -- Sends the text of the line to the conversation. Only the Enter key and the Send button call it. Returns
  -- the job, or nil (blank text, nothing picked, or a refusal that the notice names).
  function line:Submit()
    local conv = win.Conv()
    local text = edit:GetText()
    if not (conv and self.key) or IL.IsBlank(text) then
      return nil
    end
    local job, why
    if conv.kind == "team" then
      -- A team message goes through the interface of the teams; the thread shows the mirrored line.
      local ok, info = chat.Teams.Send(chat.TeamsUILogic.TeamId(conv.key), text)
      job, why = ok and (type(info) == "table" and info or {}) or nil, info
    else
      job, why = Send.Send(conv, text)
    end
    if not job then
      self.refused = why
      self:Refresh()
      return nil
    end
    IL.Remember(self.history, text)
    self.refused = nil
    edit:SetText("")
    Store.Set(chat.db, "drafts", self.key, nil)
    self:Refresh()
    win.Sent(conv)
    return job
  end

  -- Focus goes to the line on the next frame, so the key that asked for it is not typed or sent into it.
  function line:Focus()
    if not self.key or self.locked then
      return false
    end
    C_Timer.After(0, function()
      if not line.locked and line.key and host:IsVisible() then
        edit:SetFocus()
      end
    end)
    return true
  end

  -- A click on "Send now" or "Try again": every waiting message of the conversation goes on; with none
  -- waiting the oldest failed one tries again.
  function line:ReleaseHeld()
    local conv = win.Conv()
    if not conv then
      return
    end
    local jobs = IL.Held(Queue.List(), conv.key)
    local refusal
    for _, job in ipairs(jobs.waiting) do
      local ok, why = Queue.Release(job.id)
      if not ok then
        refusal = why
        break
      end
    end
    if #jobs.waiting == 0 and jobs.failed[1] then
      local ok, why = Queue.Release(jobs.failed[1].id)
      refusal = not ok and why or nil
    end
    self.refused = refusal
    self:Refresh()
  end

  function line:DiscardHeld()
    local conv = win.Conv()
    if not conv then
      return
    end
    local jobs = IL.Held(Queue.List(), conv.key)
    for _, job in ipairs(jobs.waiting) do
      Queue.Discard(job.id)
    end
    for _, job in ipairs(jobs.failed) do
      Queue.Discard(job.id)
    end
    self.refused = nil
    self:Refresh()
  end

  return line
end

-- Whether the conversation can be written to now: a team needs the consent to send, the rest the game rules.
function Input.Available(conv)
  if conv.kind == "team" then
    local _, sendOn = chat.TeamsView.Consent()
    return sendOn, (not sendOn) and "consent" or nil
  end
  return Send.Available(conv)
end

function Input.Current()
  return current
end

-- A state change of a send (queued, sent, waiting, failed): the thread shows the new state and the line the strip.
FG.On("FG_CHAT_SEND_STATE", function(_, key)
  for _, line in ipairs(all) do
    if line.host:IsVisible() then
      line.win.Draw({ [key] = true })
      line:Refresh()
    end
  end
end)
-- The group or the guild changed: a line that was locked may be free now and the other way round.
for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "PLAYER_ENTERING_WORLD" }) do
  FG.On(event, function()
    for _, line in ipairs(all) do
      if line.host:IsVisible() then
        line:Refresh()
      end
    end
  end)
end
