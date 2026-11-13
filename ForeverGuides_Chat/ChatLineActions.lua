-- Forever Chat, the actions on a line of the thread: copy the text, forward it to another chat, reply to it, and
-- the copy dialog of a web address. One shared bar of three icons follows the line under the mouse (and the
-- newest line for the keyboard). Nothing here sends: a forward opens the share window, a reply fills the reply bar
-- of the input line. Frames are built with the window.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L = FG.W, FG.L
local TX = chat.TextLogic

local LA = {}
chat.LineActions = LA

local ICON, GAP = 18, 4

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

-- Opens the shared share window of the main add-on with the text of the line, sender in front. Channel choice,
-- the whisper name fields and the splitting into messages are its job, it sends only on the click on "Send".
function LA.Forward(_, item)
  local Share = FG.Share
  if not (item and item.line) or item.line.hidden or not (Share and Share.Open) then
    return false
  end
  local text = TX.ForwardText(writerOf(item.line), item.line.text, true)
  Share.Open("", text, { windowTitle = L["chat.line.forward"] })
  return true
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
