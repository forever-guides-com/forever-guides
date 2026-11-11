-- Forever Chat, the actions on a line of the thread: copy the text, forward it to another chat, reply to it, and
-- the copy dialog of a web address. One shared bar of three icons follows the line under the mouse (and the
-- newest line for the keyboard). Nothing here sends: a forward only puts the text into the chat box of the game for
-- the player to check, a reply fills the reply bar of the input line. Frames are built with the window.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L = FG.W, FG.L
local TX, SL = chat.TextLogic, chat.SendLogic

local LA = {}
chat.LineActions = LA

local ICON, GAP = 18, 4

local function global(name)
  return rawget(_G, name)
end

-- The name of the writer of a line as the thread shows it.
local function writerOf(line)
  if line.dir == FG.ChatHistoryLogic.DIR_OUT then
    return FG.PlayerName.Self()
  end
  return line.sender or "?"
end

-- Copy -------------------------------------------------------------------------------------------------------

-- The copy dialog of a text (plain, links readable). Returns the plain text that was offered.
function LA.CopyText(titleKey, text, hintKey)
  local plain = TX.Plain(text)
  if FG.Dialogs and FG.Dialogs.Copy then
    FG.Dialogs.Copy(titleKey, plain, hintKey)
  end
  return plain
end

function LA.Url(url)
  if type(url) ~= "string" or url == "" then
    return false
  end
  LA.CopyText("chat.url.title", url, "chat.url.hint")
  return true
end

function LA.Copy(item)
  if not (item and item.line) or item.line.hidden then
    return false
  end
  LA.CopyText("chat.line.copyTitle", item.line.text, "chat.line.copyHint")
  return true
end

-- The whole history of a conversation as plain text, one line each: "[time] Name: text".
function LA.AllText(conv)
  local out = {}
  local stamp = rawget(_G, "date") or os.date
  for _, line in ipairs(conv and conv.lines or {}) do
    if not line.hidden then
      local when = type(line.time) == "number" and stamp("%H:%M", line.time) or "--:--"
      out[#out + 1] = string.format("[%s] %s: %s", when, writerOf(line), TX.Plain(line.text))
    end
  end
  return table.concat(out, "\n")
end

function LA.CopyAll(conv)
  if not conv then
    return false
  end
  local text = LA.AllText(conv)
  if FG.Dialogs and FG.Dialogs.Copy then
    FG.Dialogs.Copy("chat.line.copyAllTitle", text, "chat.line.copyHint")
  end
  return true
end

-- Reply ------------------------------------------------------------------------------------------------------

function LA.Reply(conv, item)
  if not (conv and item and item.line) or item.line.hidden or not chat.Input then
    return false
  end
  local ok, why = chat.Input.Reply(conv.key, item.line, writerOf(item.line))
  if not ok and why and why ~= "noinput" then
    chat.Input.Refuse(conv.key, why)
  end
  return ok
end

-- Forward ----------------------------------------------------------------------------------------------------

-- The text of a forward as it goes into the chat box and the box line for a target. Pure helper for the dialog.
function LA.ForwardLine(target, name, line, withHead)
  local text = TX.ForwardText(writerOf(line), line.text, withHead)
  local to = target.kind == "whisper" and name or target.channel
  local parts = SL.Split(text, (SL.Limit(target.chatType)))
  local first = parts and parts[1] or text
  local box = SL.BoxLine(target.chatType, to, first)
  return box, parts
end

-- Which targets the player may use now (the rules of SendLogic.Available with the facts of the game).
function LA.Targets()
  local Send = chat.Send
  local facts = Send and Send.Env and Send.Env.facts
  local function available(kind)
    local f = {}
    if facts then
      local ok, got = pcall(facts, kind)
      f = ok and type(got) == "table" and got or {}
    end
    return SL.Available({ kind = kind, name = f.guildName or "" }, f)
  end
  local channels = {}
  local list = global("GetChannelList")
  local ok, values = pcall(function()
    return { list() }
  end)
  if ok and type(list) == "function" then
    for i = 1, #values - 2, 3 do
      local id, name = FG.AutoGuard.Safe(values[i]), FG.AutoGuard.Safe(values[i + 1])
      if type(id) == "number" and type(name) == "string" and #channels < 8 then
        channels[#channels + 1] = { id = id, name = name }
      end
    end
  end
  return TX.ForwardTargets(available, channels)
end

local dialog

local function buildDialog()
  local d = FG.Dialogs.Create("FGChatForwardDialog", 420, 400)
  W.SetText(d.title, "chat.fwd.title")
  d.rows = {}
  d.head = true
  d.check = W.Checkbox(d, {
    key = "chat.fwd.head",
    get = function()
      return d.head
    end,
    set = function(on)
      d.head = on
    end,
  })
  d.check:SetPoint("BOTTOMLEFT", 16, 46)
  d.check:SetPoint("BOTTOMRIGHT", -16, 46)
  d.status = W.Text(d, { role = "micro", color = "textSecondary", wrap = true })
  d.status:SetPoint("BOTTOMLEFT", 16, 74)
  d.status:SetPoint("BOTTOMRIGHT", -16, 74)
  d.name = W.EditBox(d, { placeholder = "chat.fwd.name", height = 28 })
  d.name:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 16, 100)
  d.name:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -16, 100)
  d.name:Hide()
  d.close = W.Action(d, { key = "chat.fwd.close", width = 110 })
  d.close:SetPoint("BOTTOMRIGHT", -16, 12)
  d.close:SetScript("OnClick", function()
    d:Hide()
  end)
  return d
end

local function targetLabel(target)
  if target.kind == "channel" then
    return string.format(L["chat.fwd.channel"], target.channel, target.name or "")
  elseif target.kind == "say" then
    return L["chat.fwd.say"]
  elseif target.kind == "yell" then
    return L["chat.fwd.yell"]
  elseif target.kind == "whisper" then
    return L["chat.fwd.whisper"]
  end
  return L["chat.kind." .. target.kind]
end

-- Puts the forwarded text into the chat box of the game (nothing is sent) and says so in the dialog.
local function put(d, target, name)
  local box = LA.ForwardLine(target, name, d.line, d.head)
  local ok = box and chat.Send.Env.openChat(box) == true
  d.status:SetText(L[ok and "chat.fwd.done" or "chat.fwd.failed"])
  return ok
end

function LA.Forward(conv, item)
  if not (item and item.line) or item.line.hidden or not chat.Send then
    return false
  end
  dialog = dialog or buildDialog()
  local d = dialog
  d.line, d.conv = item.line, conv
  d.status:SetText("")
  d.name:Hide()
  d.check:Refresh()
  local y = -46
  for _, row in ipairs(d.rows) do
    row:Hide()
  end
  for i, target in ipairs(LA.Targets()) do
    local row = d.rows[i]
    if not row then
      row = W.Action(d, { text = " ", height = 26, width = 388 })
      d.rows[i] = row
    end
    local label = targetLabel(target)
    if not target.ok and target.why then
      label = label .. " (" .. (L["chat.reason." .. target.why] or target.why) .. ")"
    end
    row.label:SetText(label)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", d, "TOPLEFT", 16, y)
    y = y - 28
    row.target = target
    if target.ok then
      row:Enable()
      row:SetScript("OnClick", function()
        if target.kind == "whisper" then
          d.name:Show()
          d.name.edit:SetFocus()
          d.name.edit:SetScript("OnTabPressed", function()
            local found = LA.Complete(d.name.edit:GetText())
            if found then
              d.name.edit:SetText(found)
              d.name.edit:SetCursorPosition(#found)
            end
          end)
          d.name.edit:SetScript("OnEnterPressed", function()
            local who = FG.PlayerName.Clean(d.name.edit:GetText())
            if who ~= "" then
              put(d, target, who)
            end
          end)
          d.status:SetText(L["chat.fwd.name"])
          return
        end
        put(d, target)
      end)
      row:SetAlpha(1)
    else
      -- Not allowed now: greyed out, the reason is the tooltip text and the status line.
      row:Disable()
      row:SetAlpha(0.5)
      row:SetScript("OnClick", nil)
    end
    row:Show()
  end
  d:Show()
  return true
end

-- Completes a typed name from the names seen in this session (Tab in the whisper box).
function LA.Complete(prefix)
  return chat.Class and chat.Class.Names(prefix)[1] or nil
end

-- The shared bar --------------------------------------------------------------------------------------------

-- A bar of three icons on the thread. host: the frame the rows live in. get(): the conversation. Returns the bar:
-- bar:Aim(row, item) moves it onto a row, bar:Release() hides it.
function LA.NewBar(host, get)
  local bar = CreateFrame("Frame", nil, host)
  bar:SetFrameLevel(host:GetFrameLevel() + 20)
  bar:SetSize(3 * ICON + 2 * GAP, ICON)
  bar:Hide()
  local function make(icon, key, tip, fn)
    return W.Action(bar, {
      icon = icon,
      size = ICON,
      tooltip = key,
      tooltipText = tip,
      wrap = "chat-line-" .. icon,
      onClick = function()
        if bar.item then
          fn(get(), bar.item, bar)
        end
      end,
    })
  end
  bar.copy = make("copy", "chat.line.copy", "chat.line.copyTip", LA.Copy)
  bar.forward = make("export", "chat.line.forward", "chat.line.forwardTip", LA.Forward)
  bar.reply = make("undo", "chat.line.reply", "chat.line.replyTip", LA.Reply)
  bar.reply:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
  bar.forward:SetPoint("RIGHT", bar.reply, "LEFT", -GAP, 0)
  bar.copy:SetPoint("RIGHT", bar.forward, "LEFT", -GAP, 0)
  function bar:Aim(row, item, rightInset, top)
    if not (item and item.type == "line") or item.line.hidden then
      return self:Release()
    end
    self.item = item
    self:ClearAllPoints()
    self:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(rightInset or 6), -(top or 3))
    self:Show()
  end
  function bar:Release()
    self.item = nil
    self:Hide()
  end
  return bar
end
