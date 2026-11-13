-- Forever Chat, the input line under the thread: one line, Enter sends to the picked conversation through
-- Send.Send (never on its own: the only caller is the Enter key and the Send button). Under it sit the reason
-- a message was refused, a strip for held messages (a click sends, retries or discards them) and the length
-- counter. A conversation that cannot be written to (no group, no guild) locks the line and says why. The
-- text of every conversation is kept as a draft (Store, "drafts") and comes back when it is picked again;
-- Up and Down walk through the last sent inputs (memory only). The rules are ChatInputLogic.lua. This is
-- the add-on's own line: the game's chat line is never touched; shift-clicked links reach it through a
-- secure post-hook of ChatEdit_InsertLink while the line has focus.
--
-- Enter and the Send button send through Send.Send (the chat function of the game, in the key or the click of the
-- player); nothing here clicks a secure button, code must never do that (ChatSecure.lua).
--
-- win = { Conv() -> conversation or nil, Sent(conv), Layout(), Menu(), Leave(), Draw(keys) }. The window has one
-- line; every mini window (ChatMini.lua) has its own (opts.mini), they all follow the same events.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, K = FG.W, FG.L, FG.PageKit
local IL, Send, Queue, Store, TX = chat.InputLogic, chat.Send, chat.Queue, chat.Store, chat.TextLogic

local Input = {}
chat.Input = Input

local GAP, ROW, BUTTON = 6, 30, 28

-- Text heights come back from the client as 32 bit floats: 12.000001 must not become 13 and a line that did not
-- change must not look taller than before, or every key would lay out the whole window again.
local function ceil(height)
  return math.ceil(height - 0.01)
end

local function sameHeight(a, b)
  return math.abs(a - b) < 0.01
end

-- The typing mark goes to the partner at most once a second (the sender keeps its own, longer gap).
local TYPING_POLL = 1

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

local STEAL_WINDOW = 0.25

local function clock()
  local fn = global("GetTime")
  return type(fn) == "function" and fn() or 0
end

-- The chat box of the game that has the focus now, nil when none (the first function the client has).
local function gameBox()
  local util = global("ChatFrameUtil")
  local fn = global("ChatEdit_GetActiveWindow") or (type(util) == "table" and util.GetActiveWindow) or nil
  if type(fn) ~= "function" then
    return nil
  end
  local ok, box = pcall(fn)
  return ok and type(box) == "table" and box or nil
end

-- The link of an item the game knows by its name, nil when it does not (a [Name] typed by hand becomes this link).
local function itemLink(name)
  local items = global("C_Item")
  local fn = type(items) == "table" and items.GetItemInfo or global("GetItemInfo")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, found, link = pcall(fn, name)
  found, link = FG.AutoGuard.Safe(found), FG.AutoGuard.Safe(link)
  if ok and type(found) == "string" and type(link) == "string" and found:lower() == name:lower() then
    return link
  end
  return nil
end

local function replyHeadOn()
  local settings = chat.Settings
  return not (settings and settings.Value) or settings.Value("replyHead") ~= false
end

local lastLink, lastAt

-- A link that the game puts into a chat box (Shift+click on an item in a bag, the bank, the character window, a
-- vendor, the loot window, a search result or a link in a chat). Called after the game function through
-- hooksecurefunc, which never replaces or delays it. When the input line has the focus the link goes into it. The
-- game opens its own chat box for a link that no active chat box takes, and that takes the focus from the line in
-- the same moment: then the line (whose focus was lost a moment ago) takes the link back and the box of the game,
-- which holds nothing but this link, is closed again. Returns whether a line took the link.
function Input.OnInsertLink(link)
  local text = FG.AutoGuard.Safe(link)
  if type(text) ~= "string" or text == "" then
    return false
  end
  -- ChatEdit_InsertLink and ChatFrameUtil.InsertLink call each other on some clients: one link, one insert.
  local now = clock()
  if lastLink == text and lastAt == now then
    return false
  end
  for _, line in ipairs(all) do
    if line.edit:HasFocus() then
      pcall(line.edit.Insert, line.edit, text)
      lastLink, lastAt = text, now
      return true
    end
  end
  for _, line in ipairs(all) do
    if line.lostAt and now - line.lostAt <= STEAL_WINDOW and line.key and not line.locked and line.host:IsVisible() then
      local box = gameBox()
      if box then
        local ok, held = pcall(box.GetText, box)
        if ok and held == text then
          Send.Touch("game box SetText and ClearFocus")
          pcall(box.SetText, box, "")
          pcall(box.ClearFocus, box)
        end
      end
      pcall(line.edit.Insert, line.edit, text)
      line.edit:SetFocus()
      line.lostAt = nil
      lastLink, lastAt = text, now
      return true
    end
  end
  return false
end

local function hookLinks()
  if Input.linkHooked then
    return
  end
  local hook = global("hooksecurefunc")
  if type(hook) ~= "function" then
    return
  end
  local util = global("ChatFrameUtil")
  if type(global("ChatEdit_InsertLink")) == "function" then
    Input.linkHooked = true
    hook("ChatEdit_InsertLink", function(link)
      FG.Safe("chat-insert-link", Input.OnInsertLink, link)
    end)
  end
  if type(util) == "table" and type(util.InsertLink) == "function" then
    Input.linkHooked = true
    hook(util, "InsertLink", function(link)
      FG.Safe("chat-insert-link", Input.OnInsertLink, link)
    end)
  end
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

  -- The reply bar: who and what the answer in the line quotes. Close or Escape drops it.
  local bar = CreateFrame("Frame", nil, host)
  bar:Hide()
  bar.text = W.Text(bar, { role = "micro", color = "textSecondary" })
  bar.text:SetWordWrap(false)
  bar.close = W.Action(bar, {
    icon = "close",
    size = 18,
    tooltip = "chat.reply.close",
    wrap = "chat-reply-close",
    onClick = function()
      line:ClearReply()
      line.edit:SetFocus()
    end,
  })
  line.replyBar = bar

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
      line:Submit("click")
    end,
  })
  line.send:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  -- The counter has its own line above the row, so a narrow window keeps room for the box.
  line.counter = W.Text(host, { role = "micro", color = "textMuted", justify = "RIGHT" })
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
      line:Submit("enter")
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
  edit:HookScript("OnEscapePressed", function()
    line:ClearReply()
  end)
  edit:HookScript("OnEditFocusLost", function()
    line.lostAt = clock()
  end)
  edit:HookScript("OnEditFocusGained", function()
    line.lostAt = nil
  end)
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
    if bar:IsShown() then
      bar:ClearAllPoints()
      bar:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
      bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
      local barH = math.max(18, ceil(bar.text:GetStringHeight()) + 4)
      bar:SetHeight(barH)
      bar.close:ClearAllPoints()
      bar.close:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
      bar.text:ClearAllPoints()
      bar.text:SetPoint("LEFT", bar, "LEFT", 0, 0)
      bar.text:SetPoint("RIGHT", bar.close, "LEFT", -GAP, 0)
      top = barH + GAP
    end
    local notice = self.notice
    if notice:IsShown() then
      notice:ClearAllPoints()
      notice:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
      notice:SetWidth(width)
      top = top + ceil(notice:GetStringHeight()) + GAP
    end
    if held:IsShown() then
      held:ClearAllPoints()
      held:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
      held:SetWidth(width)
      held.text:ClearAllPoints()
      held.text:SetPoint("TOPLEFT", held, "TOPLEFT", 0, 0)
      held.text:SetWidth(width)
      local textH = ceil(held.text:GetStringHeight())
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
    -- The counter line always holds its height, so the first typed character never moves the thread.
    local counter = self.counter
    counter:ClearAllPoints()
    counter:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
    counter:SetWidth(width)
    local counterH = ceil(counter:GetStringHeight())
    if counterH <= 0 then
      counter:SetText(" ")
      counterH = ceil(counter:GetStringHeight())
      counter:SetText(self.counterText or "")
    end
    top = top + counterH + 2
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
    local jobs = IL.Held(Queue.List(), conv.key)
    local single = #jobs.waiting + #jobs.failed == 1 and (jobs.waiting[1] or jobs.failed[1]) or nil
    local plan = single and Send.Plan(conv, single.parts[single.index] or single.parts[1], single) or nil
    local offered = plan ~= nil and plan.secure == true and #single.parts == 1
    local view = IL.HeldView(jobs, offered)
    self:SyncSecureHeld(offered and single or nil)
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
    if not sameHeight(height, before) and not quiet then
      win.Layout()
    end
  end

  -- The secure "Send now" button lies over the button of the strip while one held message may be sent by it. It only
  -- ever runs for a real mouse click; Enter and the keyboard keep the chat box.
  function line:SyncSecureHeld(job)
    local secure = chat.Secure
    if not secure then
      return
    end
    self.heldJob = job
    if not self.heldSecure then
      if not job then
        return
      end
      self.heldSecure = secure.New({
        plan = function()
          local heldNow = line.heldJob
          local conv = win.Conv()
          if not (heldNow and conv) then
            return nil
          end
          local plan = Send.Plan(conv, heldNow.parts[1], heldNow)
          if plan then
            plan.held = heldNow
          end
          return plan
        end,
        done = function()
          line:Refresh()
        end,
      })
      if not self.heldSecure then
        return
      end
    end
    if job then
      self.heldSecure:Aim(held.release)
    else
      self.heldSecure:Release()
    end
  end

  -- What goes out for the typed text: a [Name] of a known item becomes its link and a reply in a group chat gets its
  -- short head. The counter counts exactly this.
  function line:Outgoing(text)
    local out = TX.Linkify(text, itemLink)
    local conv = win.Conv()
    if
      self.reply
      and replyHeadOn()
      and conv
      and conv.kind ~= "whisper"
      and conv.kind ~= "bnet"
      and conv.kind ~= "team"
    then
      out = TX.ReplyHead(self.reply.sender) .. out
    end
    return conv and Send.Decorate(conv, out, true) or out
  end

  function line:SetReply(reply)
    self.reply = reply
    if reply then
      bar.text:SetText(string.format(L["chat.reply.bar"], reply.sender, reply.excerpt))
      bar:Show()
    else
      bar:Hide()
    end
    self:Refresh()
  end

  function line:ClearReply()
    if self.reply then
      self:SetReply(nil)
    end
  end

  function line:UpdateCounter()
    local conv = win.Conv()
    local counter = IL.Counter(self:Outgoing(edit:GetText()), conv and conv.kind or nil)
    if counter then
      local text = string.format(L[counter.key], IL.CounterArgs(counter))
      if not counter.measured then
        text = text .. L["chat.input.count.unmeasured"]
      end
      if self.counterText ~= text then
        self.counterText = text
        self.counter:SetText(text)
      end
      W.SetColor(self.counter, (counter.over or counter.parts > 1) and "warning" or "textMuted")
    else
      if self.counterText ~= "" then
        self.counterText = ""
        self.counter:SetText("")
      end
    end
  end

  -- Typing: the draft follows, an old refusal goes away.
  function line:Changed()
    if not self.key then
      return
    end
    local text = edit:GetText()
    Store.Set(chat.db, "drafts", self.key, not IL.IsBlank(text) and text or nil)
    local active = not IL.IsBlank(text)
    local now = clock()
    if chat.Peer and (active ~= self.typingActive or (active and now - (self.typingAt or -math.huge) >= TYPING_POLL)) then
      self.typingActive, self.typingAt = active, now
      if self.host:IsVisible() then
        FG.Safe("chat-peer-typing", chat.Peer.OnTyping, self.key, active)
      end
    end
    if self.refused then
      self.refused = nil
      self:Refresh()
      return
    end
    self:UpdateCounter()
    local before = host:GetHeight() or 0
    if not sameHeight(self:Fit(host:GetWidth() or 0), before) then
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
    self.key, self.refused, self.reply = key, nil, nil
    self.typingActive = nil
    bar:Hide()
    IL.Reset(self.history)
    edit:SetText(key and chat.db.drafts[key] or "")
    self:Refresh(quiet)
  end

  -- Sends the text of the line to the conversation. Only the Enter key and the Send button call it. Returns
  -- the job, or nil (blank text, nothing picked, or a refusal that the notice names).
  function line:Submit(trigger)
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
      job, why = Send.Send(conv, self:Outgoing(text), trigger or "enter", { reply = self.reply and self.reply.seq })
    end
    if not job then
      self.refused = why
      self:Refresh()
      return nil
    end
    IL.Remember(self.history, text)
    self.refused = nil
    self:ClearReply()
    edit:SetText("")
    -- The draft goes only when the message is out (state "sent": no block reported, or the own line came back). A
    -- message the game blocked keeps its text as the draft until it is sent, so it is never lost.
    if job.state == "sent" or conv.kind == "team" then
      Store.Set(chat.db, "drafts", self.key, nil)
    else
      job.draftText = text
      Store.Set(chat.db, "drafts", self.key, text)
    end
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

-- Puts a link (or any text) into the input line that is on screen and gives it the focus: the Shift+click on a
-- link of the thread. The main window's line first. Returns whether a line took it.
function Input.Insert(text)
  if type(text) ~= "string" or text == "" then
    return false
  end
  local order = { current }
  for _, line in ipairs(all) do
    order[#order + 1] = line
  end
  for _, line in ipairs(order) do
    if line.key and not line.locked and line.host:IsVisible() then
      line.edit:SetFocus()
      return pcall(line.edit.Insert, line.edit, text)
    end
  end
  return false
end

-- The input line of a conversation that is on screen, nil when there is none.
local function lineOf(key)
  for _, line in ipairs(all) do
    if line.key == key and line.host:IsVisible() then
      return line
    end
  end
end

-- "Use text": puts the text of a sent message into the input line of that conversation, behind what stands there
-- (a draft is never lost) and gives the line the focus. Returns true, or false and a reason.
function Input.Take(key, text)
  local line = lineOf(key)
  if not line then
    return false, "noinput"
  end
  if line.locked then
    return false, line.locked
  end
  if type(text) ~= "string" or text == "" then
    return false, "noinput"
  end
  local before = line.edit:GetText()
  local joined = IL.IsBlank(before) and text or (before:gsub("%s+$", "") .. " " .. text)
  line.edit:SetText(joined)
  line.edit:SetFocus()
  pcall(line.edit.SetCursorPosition, line.edit, #joined)
  return true
end

-- "Reply": the line is quoted by the answer typed next. sender: the name to show (the own name for an own line).
-- Returns true, or false and a reason.
function Input.Reply(key, quoted, sender)
  local line = lineOf(key)
  if not line then
    return false, "noinput"
  end
  if line.locked then
    return false, line.locked
  end
  if type(quoted) ~= "table" or type(quoted.seq) ~= "number" or quoted.hidden then
    return false, "noinput"
  end
  line:SetReply({
    seq = quoted.seq,
    sender = type(sender) == "string" and sender ~= "" and sender or "?",
    excerpt = TX.Excerpt(quoted.text),
  })
  line.edit:SetFocus()
  return true
end

-- Shows why a click on a message did not send it (the notice under the line of that conversation), the same
-- words as a refused send. Returns whether a line showed it.
function Input.Refuse(key, why)
  local line = lineOf(key)
  if not line then
    return false
  end
  line.refused = chat.WayLogic.RefusalReason(why)
  line:Refresh()
  return true
end

function Input.Current()
  return current
end

-- A state change of a send (queued, sent, waiting, failed): the thread shows the new state and the line the strip.
-- The message is out: its kept draft goes now.
FG.On("FG_CHAT_SENT", function(_, key, job)
  if type(job) == "table" and job.draftText and chat.db.drafts[key] == job.draftText then
    Store.Set(chat.db, "drafts", key, nil)
  end
end)
FG.On("FG_CHAT_SEND_STATE", function(_, key)
  for _, line in ipairs(all) do
    if line.host:IsVisible() then
      line.win.Draw({ [key] = true })
      line:Refresh()
    end
  end
end)
-- The game refuses a call of an add-on by event, not by error: the sender needs the report to know a send failed.
-- Nothing is read from the report except the name of the add-on.
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
  FG.On(event, function(_, who, func)
    Send.OnBlocked(who, func)
  end)
end
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
