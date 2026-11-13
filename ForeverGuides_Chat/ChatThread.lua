-- Forever Chat, the thread view (read only): a header with the symbol, name, the facts that are known and the
-- switch of the mode, and the lines of one conversation in a scrolling view that keeps a small pool of frames
-- (only the lines in view are frames, never one per line). Two looks, switchable per conversation:
--   "messenger": a card per line with a stripe in the color of the sender (class color where known), own
--   cards set off to the right in a teal tint, sender and time in a head, links clickable inside the text;
--   "compact": one wrapped line per message (time, name, text).
-- Day dividers and the divider "new messages" run through both. The rules are ChatThreadLogic; reading
-- moves the read position of the conversation (ChatUnread) as lines come into view.
--
-- Links: the text of a line is one wrapped FontString, the link text inside it is colored by the game. A
-- transparent button sits over each link (one per line the link touches); the position comes from measuring
-- the wrapped text (TL.LinkRects), so nothing is drawn twice. Hover shows the tooltip of the link, a click opens
-- it (SetItemRef), Shift+click puts it into the input line, and the buttons are part of the keyboard focus.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, Theme, K, U = FG.W, FG.L, FG.Theme, FG.PageKit, FG.U
local TL, LL, List, TX = chat.ThreadLogic, chat.ListLogic, chat.List, chat.TextLogic

local Thread = {}
chat.Thread = Thread

Thread.HEAD = 48
Thread.PREBUILD = 24
Thread.OVERSCAN = 40
local GAP, WHEEL_LINES = 6, 3
local PALETTE = { "actionHi", "accent", "success", "info", "warning", "accent2" }
local DELIVERY_TOKEN = {
  queued = "textMuted",
  sent = "textMuted",
  waiting = "warning",
  failed = "danger",
  partial = "warning",
  complete = "textMuted",
  nobody = "warning",
}
local TEAM_STATES = { waiting = true, partial = true, complete = true, nobody = true }
-- "Send again" and "Use text" sit in the status line of an own message (the head of its card, in the compact look at the
-- right end of the line while the mouse or the keyboard focus is on it).
local ACT, ACT_GAP = 16, 4

local function hexOf(r, g, b, text)
  return string.format("|cff%02x%02x%02x%s|r", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5, text)
end

local function isNumber(v)
  return type(v) == "number" and v == v
end

-- Colors as { r, g, b } so cards, voices and their contrast can be computed.
local function rgbOf(name)
  local r, g, b = Theme.rgb(name)
  return { r, g, b }
end

local function blend(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- Fill of a card as color and alpha. A card of a yell leans to red and a card of a Battle.net partner to blue,
-- in small amounts so every text color of the card keeps its contrast (tested). own: the card of the player.
function Thread.CardTone(kind, voice, own)
  if own then
    return rgbOf("action"), 0.28
  end
  local base = rgbOf("surface2")
  if voice == "yell" then
    base = blend(base, rgbOf("danger"), 0.12)
  elseif kind == "bnet" then
    base = blend(base, rgbOf("info"), 0.1)
  end
  return base, 0.85
end

-- The card as seen over the window background.
function Thread.CardSeen(kind, voice, own)
  local base, alpha = Thread.CardTone(kind, voice, own)
  return blend(rgbOf("bg"), base, alpha)
end

-- Color of the voice (say, yell, emote) on its card: the color of the game's chat type, readable on the card.
function Thread.VoiceRgb(kind, voice, own)
  return TL.VoiceColor(voice, rawget(_G, "ChatTypeInfo"), Thread.CardSeen(kind, voice, own))
end

-- "» says" in the color of the voice: a symbol and a word, so the voice never rests on color alone.
function Thread.VoiceMark(kind, voice, own)
  local r, g, b = Thread.VoiceRgb(kind, voice, own)
  return hexOf(r, g, b, LL.VOICE_SYMBOL[voice] .. " " .. L["chat.voice." .. voice])
end

local function scaled(base)
  return K.scaledHeight(base)
end

-- Whether names show in their class color (the option "classColors", on by default).
local function classColors()
  local settings = chat.Settings
  return not (settings and settings.Value) or settings.Value("classColors") ~= false
end

-- The class token for the name of a line: the class stored with the line (from the GUID of the event), else what is
-- known about the name (guild list, group, players seen before). A Battle.net partner has the class of the character
-- that plays. nil when the option is off or the class is unknown.
function Thread.ClassOf(view, line)
  if not classColors() then
    return nil
  end
  if view.conv and view.conv.kind == "bnet" then
    return view.conv.character and view.win.ClassOfName(view.conv.character) or nil
  end
  return line.class or view.win.ClassOfName(line.sender)
end

-- Sender: r, g, b of the stripe and the name, and the name as shown.
local function look(view, item)
  if item.own then
    local r, g, b = Theme.rgb("accent2")
    return r, g, b, L["chat.you"]
  end
  local short = LL.ShortName(item.line.sender)
  if view.conv and view.conv.kind == "bnet" and not item.line.hidden then
    short = LL.BnetName(view.conv)
  end
  if item.line.hidden or short == "" then
    local r, g, b = Theme.rgb("textMuted")
    return r, g, b, "?"
  end
  local class = Thread.ClassOf(view, item.line)
  if class then
    local r, g, b = U.hex(K.ClassColorHex(class))
    return r, g, b, short
  end
  local sum = 0
  for i = 1, #short do
    sum = sum + short:byte(i)
  end
  local r, g, b = Theme.rgb(PALETTE[sum % #PALETTE + 1])
  return r, g, b, short
end

-- Time stamp in the format of the options (24 or 12 hours, seconds on request).
local function clockOf(line)
  return isNumber(line.time) and List.DateOf(chat.SettingsLogic.ClockFormat(chat.db), line.time) or "--:--"
end

-- The text of a line, with the reactions and "seen" of the add-on extras behind it (opt-in, ChatPeer.lua).
-- The quote head of a reply: the quoted line in short, a link that jumps to it. "" when the line quotes nothing or the
-- quoted line is gone from the history.
local function quoteHead(view, line)
  if not (line.reply and view.conv) then
    return ""
  end
  local original
  for _, candidate in ipairs(view.conv.lines) do
    if candidate.seq == line.reply then
      original = candidate
      break
    end
  end
  if not original or original.hidden then
    return ""
  end
  local name = original.dir == FG.ChatHistoryLogic.DIR_OUT and FG.PlayerName.Self() or original.sender or "?"
  local r, g, b = Theme.rgb("textMuted")
  local text = string.format(L["chat.reply.quote"], name, TX.Excerpt(original.text))
  return "|Hfgjump:" .. original.seq .. "|h" .. hexOf(r, g, b, text) .. "|h" .. "\n"
end

local function bodyText(view, item)
  if item.line.hidden then
    return L["chat.thread.hidden"]
  end
  local r, g, b = Theme.rgb("accent2")
  local text = TX.ColorUrls(item.line.text, string.format("%02x%02x%02x", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5))
  text = quoteHead(view, item.line) .. text
  local decor = chat.Peer and view.conv and chat.Peer.Decor(view.conv.key, item.line) or ""
  if decor == "" then
    return text
  end
  return text .. "  " .. hexOf(r, g, b, "[" .. decor .. "]")
end

-- The logo in front of a name, "" unless the logo setting and Presence say so (ChatPeer.Badge).
local function badgeOf(item)
  if not chat.Peer or item.line.hidden then
    return ""
  end
  return chat.Peer.Badge(item.own and FG.PlayerName.Self() or item.line.sender)
end

-- The text of a delivery mark: a team line that waits says what it waits for.
local function deliveryText(view, item)
  if view.conv and view.conv.kind == "team" and chat.Teams and TEAM_STATES[item.delivery] then
    local line = item.line
    local entry = view.teamSet and view.teamSet[tostring(line.time) .. "\n" .. tostring(line.text)]
    return chat.Teams.DeliveryText(type(entry) == "table" and entry or { state = item.delivery })
  end
  local text = L[TL.DeliveryKey(item.delivery, item.line.reason)]
  local short = TL.ReasonShortKey(item.delivery, item.line.reason)
  return short and (text .. ": " .. L[short]) or text
end

local function compactText(view, item)
  local line = item.line
  local r, g, b, name = look(view, item)
  local mark = ""
  if item.delivery and (item.delivery ~= "sent" or item.line.reason == "noecho") then
    mark = " [" .. deliveryText(view, item) .. "]"
  end
  local mr, mg, mb = Theme.rgb("textMuted")
  if item.voice then
    mark = " " .. Thread.VoiceMark(view.conv and view.conv.kind, item.voice, item.own) .. mark
  end
  return string.format(
    "%s %s%s%s: %s",
    hexOf(mr, mg, mb, clockOf(line)),
    badgeOf(item),
    hexOf(r, g, b, name),
    mark,
    bodyText(view, item)
  )
end

local function restricted()
  local send = chat.Send
  if not (send and send.Restricted) then
    return false
  end
  local ok, locked = pcall(send.Restricted)
  return ok and locked == true
end

-- Links: buttons over the link text, working only while chat is not restricted -------------------------------

local function hitTip(hit)
  local span = hit.span
  if not span then
    return
  end
  hit.hl:Show()
  if span.kind == "url" then
    FG.ShowTooltip(hit, span.label, L["chat.url.tip"], { anchor = "ANCHOR_RIGHT" })
    return
  elseif span.kind == "fgjump" then
    FG.ShowTooltip(hit, L["chat.reply.jump"], nil, { anchor = "ANCHOR_RIGHT" })
    return
  end
  if restricted() then
    FG.ShowTooltip(hit, span.label, L["chat.link.locked"], { anchor = "ANCHOR_RIGHT" })
    return
  end
  FG.ShowTooltip(hit, span.label, nil, { link = span.payload, hint = L["chat.link.open"], anchor = "ANCHOR_RIGHT" })
end

local function hitLeave(hit)
  hit.hl:Hide()
  FG.HideTooltip()
end

-- Shift+click (the chat link modifier of the game) puts the link into the input line of the window.
local function wantsInsert()
  local modified, shift = rawget(_G, "IsModifiedClick"), rawget(_G, "IsShiftKeyDown")
  if type(modified) == "function" then
    local ok, on = pcall(modified, "CHATLINK")
    if ok then
      return on == true
    end
  end
  return type(shift) == "function" and shift() == true
end

local function hitOpen(hit)
  local span = hit.span
  local open = rawget(_G, "SetItemRef")
  if span and span.kind == "url" then
    return chat.LineActions.Url(span.payload)
  elseif span and span.kind == "fgjump" then
    local view = hit.view
    return view and view:JumpTo(tonumber(span.payload:match("(%d+)$")))
  end
  if not span or restricted() then
    return
  end
  if wantsInsert() and chat.Input and chat.Input.Insert(span.raw) then
    return
  end
  if type(open) == "function" then
    pcall(open, span.payload, span.raw, "LeftButton")
  end
end

local function newHit(row)
  local hit = CreateFrame("Button", nil, row)
  hit:RegisterForClicks("LeftButtonUp")
  hit.hl = hit:CreateTexture(nil, "ARTWORK")
  hit.hl:SetAllPoints()
  FG.Bind(hit, function()
    hit.hl:SetColorTexture(Theme.color("accent2", 0.22))
  end)
  hit.hl:Hide()
  hit:SetScript("OnEnter", hitTip)
  hit:SetScript("OnLeave", hitLeave)
  hit:SetScript("OnClick", FG.Wrap("chat-link", hitOpen))
  hit.fgOnFocus, hit.fgOnBlur = hitTip, hitLeave
  FG.Focus.register(hit, hitOpen)
  hit:Hide()
  return hit
end

-- Battle.net partners ---------------------------------------------------------------------------------------

Thread.BNET_TTL = 3
Thread.MAX_FRIENDS = 300

-- The facts (ChatThreadLogic.BnetFacts) of the friend a conversation belongs to: matched by session account id
-- or BattleTag of the conversation, else by the name it shows. Nil when there is none or the client has no
-- friend list call. Secret values are dropped, nothing here sends or writes anything.
function Thread.FindBnet(conv)
  local api, count = rawget(_G, "C_BattleNet"), rawget(_G, "BNGetNumFriends")
  if type(conv) ~= "table" or type(api) ~= "table" then
    return nil
  end
  if type(conv.accountId) == "number" and type(api.GetAccountInfoByID) == "function" then
    local read, account = pcall(api.GetAccountInfoByID, conv.accountId)
    if read and type(account) == "table" then
      return TL.BnetFacts(account, FG.AutoGuard.Safe)
    end
  end
  if type(api.GetFriendAccountInfo) ~= "function" then
    return nil
  end
  if type(count) ~= "function" then
    return nil
  end
  local ok, total = pcall(count)
  if not ok or type(total) ~= "number" then
    return nil
  end
  local safe = FG.AutoGuard.Safe
  for i = 1, math.min(total, Thread.MAX_FRIENDS) do
    local read, account = pcall(api.GetFriendAccountInfo, i)
    if read and type(account) == "table" then
      local accountName, tag, id = safe(account.accountName), safe(account.battleTag), safe(account.bnetAccountID)
      if
        (conv.accountId ~= nil and id == conv.accountId)
        or (conv.tag ~= nil and tag == conv.tag)
        or (type(accountName) == "string" and accountName == conv.name)
        or (type(tag) == "string" and TL.TagName(tag) == conv.name)
      then
        return TL.BnetFacts(account, safe)
      end
    end
  end
  return nil
end

-- Send again and Use text -----------------------------------------------------------------------------------

-- One secure button serves every "Send again" icon: it lies over the icon under the mouse (resend.overlay), armed with
-- that message, and leaves when the mouse does. The keyboard and the fallback go through Overlay:Click.
local resend = { target = nil, overlay = nil }

local function planOf(target)
  local send = chat.Send
  if not (target and send and send.Plan) then
    return nil
  end
  local held = send.HeldJobOf(target.line)
  local plan = send.Plan(target.conv, target.line.text, held)
  if plan then
    plan.held = held
  end
  return plan
end

local function resendOverlay()
  if resend.overlay == nil and chat.Secure then
    local overlay, why = chat.Secure.New({
      plan = function()
        return planOf(resend.target)
      end,
      release = true,
    })
    if overlay then
      resend.overlay = overlay
    elseif why == "nosecure" or why == "forbidden" then
      resend.overlay = false
    end
  end
  return resend.overlay or nil
end

-- The mouse is on the icon of a message: the secure button goes over it when it may be offered for that message.
local function aimResend(view, row, button)
  local item, overlay = row.item, resendOverlay()
  if not (overlay and item and item.actions and view.conv) then
    return
  end
  local target = { conv = view.conv, line = item.line }
  local plan = planOf(target)
  if plan and plan.secure then
    resend.target = target
    overlay:Aim(button)
  else
    overlay:Release()
  end
end

-- The row shows another message or is hidden: the secure button must not stay over its icon with the old text.
local function dropAim(row, item)
  local overlay = resend.overlay
  if overlay and overlay.anchor and overlay.anchor == row.actResend then
    if not (item and item.actions and resend.target and resend.target.line == item.line) then
      overlay:Release()
    end
  end
end

-- "Send again" by the plain icon (keyboard, or a click the secure button did not take). Code never clicks the secure
-- button, so this is the normal send: the chat function first, the chat box when the game refuses it. A refusal that
-- has a text is named under the input line.
function Thread.Resend(view, row)
  local item, conv = row.item, view.conv
  if not (item and item.actions and conv and chat.Send) then
    return nil
  end
  local job, why = chat.Send.Resend(conv, item.line)
  if not job and chat.Input then
    chat.Input.Refuse(conv.key, why)
  end
  return job
end

-- "Use text": the text of the message goes into the input line.
function Thread.Take(view, row)
  local item, conv = row.item, view.conv
  if not (item and item.actions and conv and chat.Input) then
    return false
  end
  local ok, why = chat.Input.Take(conv.key, item.line.text)
  if not ok then
    chat.Input.Refuse(conv.key, why)
  end
  return ok
end

-- The two icons show in the card look always; in the compact look only on the row under the mouse or the focus.
local function showActions(view, row, on)
  if not row.actResend then
    return
  end
  local alpha = (view.mode == "messenger" or on) and 1 or 0
  row.actResend:SetAlpha(alpha)
  row.actTake:SetAlpha(alpha)
end

local function leaveActions(view, row)
  if view.mode == "messenger" or not row.actResend then
    return
  end
  local focus = FG.Focus and FG.Focus.current
  if not row:IsMouseOver() and focus ~= row.actResend and focus ~= row.actTake then
    showActions(view, row, false)
  end
end

local function ensureActions(view, row)
  if row.actResend then
    return
  end
  row.actResend = W.Action(row, {
    icon = "refresh",
    size = ACT,
    tooltip = "chat.act.resend",
    tooltipText = "chat.act.resendTip",
    wrap = "chat-resend",
    onClick = function()
      Thread.Resend(view, row)
    end,
  })
  row.actTake = W.Action(row, {
    icon = "pencil",
    size = ACT,
    tooltip = "chat.act.take",
    tooltipText = "chat.act.takeTip",
    wrap = "chat-take",
    onClick = function()
      Thread.Take(view, row)
    end,
  })
  row.actResend:HookScript("OnEnter", function(button)
    showActions(view, row, true)
    aimResend(view, row, button)
  end)
  row.actTake:HookScript("OnEnter", function()
    showActions(view, row, true)
  end)
  for _, button in ipairs({ row.actResend, row.actTake }) do
    button:HookScript("OnLeave", function()
      leaveActions(view, row)
    end)
    button.fgOnFocus = function()
      showActions(view, row, true)
    end
    button.fgOnBlur = function()
      leaveActions(view, row)
    end
  end
end

-- Rows ------------------------------------------------------------------------------------------------------

local function newRow(view)
  local row = CreateFrame("Frame", nil, view.host)
  view.built = view.built + 1
  row:EnableMouse(true)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.hl = row:CreateTexture(nil, "BORDER")
  row.hl:SetAllPoints()
  row.stripe = row:CreateTexture(nil, "ARTWORK")
  row.stripe:SetPoint("TOPLEFT")
  row.stripe:SetPoint("BOTTOMLEFT")
  row.stripe:SetWidth(TL.SPEC.stripe)
  row.head = W.Text(row, { role = "ui", color = "text" })
  row.head:SetWordWrap(false)
  row.time = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
  row.time:SetWordWrap(false)
  row.body = W.Text(row, { role = "ui", color = "text", wrap = true })
  row.shout = W.Text(row, { role = "h3", color = "text", wrap = true })
  row.label = W.Text(row, { role = "micro", color = "textMuted", justify = "CENTER" })
  row.ruleL = row:CreateTexture(nil, "ARTWORK")
  row.ruleR = row:CreateTexture(nil, "ARTWORK")
  row.ruleL:SetHeight(1)
  row.ruleR:SetHeight(1)
  row.hits = {}
  row:SetScript("OnEnter", function(self)
    local item = self.item
    if view.lineBar and item and item.type == "line" then
      local inset = item.actions and 2 * ACT + ACT_GAP + 16 or 6
      local top = view.mode == "messenger" and item.first and TL.SPEC.padV - 1 or 0
      if view.mode == "messenger" and item.first then
        inset = inset + math.ceil(self.time:GetStringWidth()) + 8 + TL.SPEC.pad
      end
      view.lineBar:Aim(self, item, inset, top)
    end
    if item and item.actions then
      showActions(view, self, true)
    end
    if item and item.type == "line" and item.delivery and item.line.reason then
      FG.ShowTooltip(
        self,
        L[TL.DeliveryKey(item.delivery, item.line.reason)],
        TL.ReasonText(L, item.line),
        { anchor = "ANCHOR_TOP" }
      )
    end
  end)
  row:SetScript("OnLeave", function(self)
    FG.HideTooltip()
    leaveActions(view, self)
  end)
  row:SetScript("OnMouseUp", function(self, button)
    local item = self.item
    if button == "LeftButton" and item and item.type == "line" and view.OpenReact then
      view:OpenReact(item.line.seq, self)
    elseif button == "RightButton" and item and item.type == "line" then
      chat.LineActions.Copy(item)
    end
  end)
  -- Built with the row, never in combat: a card needs its icons the moment its message appears.
  ensureActions(view, row)
  row.actResend:Hide()
  row.actTake:Hide()
  row:Hide()
  return row
end

local function hideParts(row)
  for _, part in ipairs({
    row.bg,
    row.hl,
    row.stripe,
    row.head,
    row.time,
    row.body,
    row.shout,
    row.label,
    row.ruleL,
    row.ruleR,
  }) do
    part:Hide()
  end
  for _, hit in ipairs(row.hits) do
    hit.span = nil
    hit:Hide()
  end
  if row.actResend then
    dropAim(row, nil)
    row.actResend:Hide()
    row.actTake:Hide()
  end
end

local function paintDivider(row, item, text, token, width)
  row:SetSize(width, item.h)
  row.label:ClearAllPoints()
  row.label:SetPoint("CENTER", row, "CENTER", 0, 0)
  row.label:SetText(text)
  W.SetColor(row.label, token)
  row.label:Show()
  local r, g, b = Theme.rgb(token)
  for _, rule in ipairs({ row.ruleL, row.ruleR }) do
    rule:SetColorTexture(r, g, b, 0.45)
    rule:Show()
  end
  row.ruleL:ClearAllPoints()
  row.ruleL:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.ruleL:SetPoint("RIGHT", row.label, "LEFT", -8, 0)
  row.ruleR:ClearAllPoints()
  row.ruleR:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
  row.ruleR:SetPoint("RIGHT", row, "RIGHT", 0, 0)
end

local function dayText(item)
  local kind = TL.DayKind(item.key, FG.U.now(), List.DateOf)
  if kind == "date" then
    return isNumber(item.time) and List.DateOf(L["chat.day.date"], item.time) or item.key
  end
  return L["chat.day." .. kind]
end

-- What the game measures for the text of a line: how many lines a text takes at the text width, how wide it is on
-- one line, and how high one line is. The probes have the font of the body (a yell is set larger).
local function hitMeasure(view, item, textW)
  local big = item.voice == "yell" and view.mode == "messenger"
  local wrap, single = big and view.measBig or view.meas, big and view.measWBig or view.measW
  wrap:SetWidth(10000)
  wrap:SetText("Ag")
  local lineH = math.max(1, wrap:GetStringHeight())
  wrap:SetWidth(textW)
  return {
    lineHeight = lineH,
    lines = function(text)
      wrap:SetText(text)
      return math.max(1, math.floor(wrap:GetStringHeight() / lineH + 0.5))
    end,
    width = function(text)
      single:SetText(text)
      return single:GetStringWidth()
    end,
  }
end

-- Puts the buttons over the links of the text a line shows. x, y: top left of the text in the row. The result
-- of the measuring is kept on the item for the same text and width.
local function paintHits(view, row, item, shown, x, y, textW)
  local rects, spans = nil, nil
  if not item.line.hidden then
    local key = textW .. "\30" .. shown
    if item.hitKey ~= key then
      local plain, found = TL.Spans(shown)
      item.hitKey, item.hitSpans = key, found
      item.hitRects = #found > 0 and TL.LinkRects(plain, found, hitMeasure(view, item, textW)) or {}
    end
    rects, spans = item.hitRects, item.hitSpans
  end
  local used = 0
  for _, rect in ipairs(rects or {}) do
    used = used + 1
    local hit = row.hits[used]
    if not hit then
      hit = newHit(row)
      row.hits[used] = hit
    end
    hit.span = spans[rect.span]
    hit.view = view
    hit:ClearAllPoints()
    hit:SetPoint("TOPLEFT", row, "TOPLEFT", x + rect.x, -(y + rect.y))
    hit:SetSize(rect.w, rect.h)
    hit:Show()
  end
  for i = used + 1, #row.hits do
    row.hits[i].span = nil
    row.hits[i]:Hide()
  end
end

local function paintLine(view, row, item, width)
  local spec = TL.SPEC
  local r, g, b = look(view, item)
  row.hl:SetShown(false)
  dropAim(row, item)
  if view.highlight and item.seq == view.highlight then
    local hr, hg, hb = Theme.rgb("accent")
    row.hl:SetColorTexture(hr, hg, hb, 0.25)
    row.hl:Show()
  end
  -- A yell is set larger (the h3 font), an emote takes the color of the game's emotes; a say stays plain.
  local kind = view.conv and view.conv.kind
  local body = item.voice == "yell" and view.mode == "messenger" and row.shout or row.body
  body:ClearAllPoints()
  body:SetText(bodyText(view, item))
  W.SetColor(body, item.line.hidden and "textMuted" or "text")
  if item.voice and item.voice ~= "say" and not item.line.hidden and view.mode == "messenger" then
    body:SetTextColor(Thread.VoiceRgb(kind, item.voice, item.own))
  end
  body:Show()
  if view.mode == "messenger" then
    local card = TL.CardWidth(width, "messenger")
    local x = item.own and (width - card) or 0
    row:SetSize(card, item.h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", view.host, "TOPLEFT", x, -(item.top - view.offset))
    local fill, alpha = Thread.CardTone(kind, item.voice, item.own)
    row.bg:SetColorTexture(fill[1], fill[2], fill[3], alpha)
    row.bg:Show()
    row.stripe:SetWidth(spec.stripe)
    row.stripe:SetColorTexture(r, g, b, 1)
    row.stripe:Show()
    local left = spec.stripe + spec.pad
    local headH = item.first and scaled(spec.head) or 0
    if item.first then
      local _, _, _, name = look(view, item)
      row.head:SetText(badgeOf(item) .. hexOf(r, g, b, name))
      row.head:ClearAllPoints()
      row.time:ClearAllPoints()
      row.time:SetPoint("TOPRIGHT", row, "TOPRIGHT", -spec.pad, -spec.padV)
      local stamp = clockOf(item.line)
      if item.voice then
        stamp = Thread.VoiceMark(kind, item.voice, item.own) .. "  " .. stamp
      end
      if item.delivery then
        local token = DELIVERY_TOKEN[item.delivery]
        stamp = Theme.hexText(token, deliveryText(view, item)) .. "  " .. stamp
      end
      row.time:SetText(stamp)
      local timeW = math.ceil(row.time:GetStringWidth())
      local actionsW = 0
      if item.actions then
        ensureActions(view, row)
        actionsW = 2 * ACT + ACT_GAP + 8
        row.actResend:SetSize(ACT, ACT)
        row.actTake:SetSize(ACT, ACT)
        row.actResend:ClearAllPoints()
        row.actResend:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(spec.pad + timeW + 8), -(spec.padV - 1))
        row.actTake:ClearAllPoints()
        row.actTake:SetPoint("RIGHT", row.actResend, "LEFT", -ACT_GAP, 0)
        -- A card whose head has scrolled out of the view shows no icons (they would hang over the header).
        row.actResend:SetShown(item.top >= view.offset)
        row.actTake:SetShown(item.top >= view.offset)
        showActions(view, row, false)
      end
      row.head:SetPoint("TOPLEFT", row, "TOPLEFT", left, -spec.padV)
      row.head:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(spec.pad + timeW + 8 + actionsW), -spec.padV)
      row.head:Show()
      row.time:Show()
    end
    body:SetPoint("TOPLEFT", row, "TOPLEFT", left, -(spec.padV + headH))
    body:SetWidth(TL.TextWidth(width, "messenger"))
    paintHits(view, row, item, bodyText(view, item), left, spec.padV + headH, TL.TextWidth(width, "messenger"))
  else
    row:SetSize(width, item.h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", view.host, "TOPLEFT", 0, -(item.top - view.offset))
    body:SetText(compactText(view, item))
    -- A thin stripe in the color of the sender: the sender shows without relying on the name color alone.
    row.stripe:SetWidth(item.voice == "yell" and 4 or 2)
    row.stripe:SetColorTexture(r, g, b, item.own and 1 or 0.7)
    row.stripe:Show()
    body:SetPoint("TOPLEFT", row, "TOPLEFT", spec.pad - 2, 0)
    body:SetWidth(TL.TextWidth(width, "compact"))
    W.SetColor(body, item.line.hidden and "textMuted" or "text")
    paintHits(view, row, item, compactText(view, item), spec.pad - 2, 0, TL.TextWidth(width, "compact"))
    if item.actions then
      ensureActions(view, row)
      -- A compact row is one line high: the icons fit into it, never into the row above or below.
      local size = math.max(10, math.min(ACT, math.floor(item.h) - 1))
      row.actResend:SetSize(size, size)
      row.actTake:SetSize(size, size)
      row.actResend:ClearAllPoints()
      row.actResend:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, 0)
      row.actTake:ClearAllPoints()
      row.actTake:SetPoint("RIGHT", row.actResend, "LEFT", -ACT_GAP, 0)
      row.actResend:SetShown(item.top >= view.offset)
      row.actTake:SetShown(item.top >= view.offset)
      showActions(view, row, row:IsMouseOver())
    end
  end
end

local function paintRow(view, row, item, width)
  row.item = item
  hideParts(row)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", view.host, "TOPLEFT", 0, -(item.top - view.offset))
  if item.type == "day" then
    paintDivider(row, item, dayText(item), "textMuted", width)
  elseif item.type == "new" then
    local text = L["chat.thread.new"]
    if item.count and item.count > 0 then
      text = text .. " (" .. chat.Unread.Label(item.count) .. ")"
    end
    paintDivider(row, item, text, "accent2", width)
  else
    paintLine(view, row, item, width)
  end
  row:Show()
end

-- View ------------------------------------------------------------------------------------------------------

-- win: { ClassOfName(name) -> class token or nil, MemberOf(key) -> guild member or nil, Reading() -> true while
-- the lines count as read, ReadChanged(key), Back(), EmptyKey() -> locale key of the text without a chat
-- (optional) }. shape.headless: no header (the mini window has its own
-- title); shape.mode: always this shape, whatever the store says.
function Thread.Create(parent, win, shape)
  shape = shape or {}
  local view = {
    win = win,
    pool = {},
    items = {},
    offset = 0,
    contentH = 0,
    viewH = 0,
    width = 0,
    built = 0,
    mode = shape.mode or "messenger",
    headless = shape.headless == true,
    forceMode = shape.mode,
  }
  local f = CreateFrame("Frame", nil, parent)
  view.frame = f

  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT")
  head:SetPoint("TOPRIGHT")
  head:SetHeight(view.headless and 0 or scaled(Thread.HEAD))
  view.head = head
  view.back = W.Action(head, {
    icon = "chevron-left",
    size = 24,
    tooltip = "chat.thread.back",
    wrap = "chat-back",
    onClick = function()
      win.Back()
    end,
  })
  view.back:SetPoint("LEFT", 0, 0)
  view.back:Hide()
  view.chip = List.NewChip(head, List.CHIP)
  view.chip:SetPoint("LEFT", head, "LEFT", 0, 0)
  view.modeButton = W.Action(head, {
    text = "",
    variant = "ghost",
    height = 24,
    width = 96,
    tooltip = "chat.mode.tip",
    tooltipText = "chat.mode.tipText",
    wrap = "chat-mode",
    onClick = function()
      view:ToggleMode()
    end,
  })
  view.modeButton:SetPoint("RIGHT", head, "RIGHT", 0, 0)
  view.teamButton = W.Action(head, {
    key = "chat.teams.panel.open",
    variant = "ghost",
    height = 24,
    width = 64,
    tooltip = "chat.teams.panel.open",
    tooltipText = "chat.teams.panel.tip",
    wrap = "chat-team-panel",
    onClick = function()
      if view.conv and win.TeamPanel then
        win.TeamPanel(view.conv.key)
      end
    end,
  })
  view.teamButton:SetPoint("RIGHT", view.modeButton, "LEFT", -GAP, 0)
  view.teamButton:Hide()
  -- The control left of the others: the title and the button "Latest" keep clear of it.
  function view:Leftmost()
    return view.teamButton:IsShown() and view.teamButton or view.modeButton
  end
  view.latest = W.Action(head, {
    key = "chat.thread.latest",
    variant = "primary",
    height = 24,
    width = 90,
    wrap = "chat-latest",
    onClick = function()
      view:ScrollTo(math.huge)
    end,
  })
  view.latest:SetPoint("RIGHT", view.teamButton, "LEFT", -GAP, 0)
  view.latest:Hide()
  view.titleBox = CreateFrame("Frame", nil, head)
  view.titleBox:SetHeight(scaled(List.CHIP + 8))
  function view:AnchorTitle(rightOf)
    view.titleBox:ClearAllPoints()
    view.titleBox:SetPoint("LEFT", view.chip, "RIGHT", 8, 0)
    view.titleBox:SetPoint("RIGHT", rightOf, "LEFT", -GAP, 0)
  end
  view:AnchorTitle(view.modeButton)
  view.title = W.Text(view.titleBox, { role = "h3", color = "text" })
  view.title:SetWordWrap(false)
  view.title:SetPoint("TOPLEFT", 0, 0)
  view.title:SetPoint("TOPRIGHT", 0, 0)
  view.info = W.Text(view.titleBox, { role = "micro", color = "textSecondary" })
  view.info:SetWordWrap(false)
  view.info:SetPoint("BOTTOMLEFT", 0, 0)
  view.info:SetPoint("BOTTOMRIGHT", 0, 0)

  view.host = CreateFrame("Frame", nil, f)
  view.lineBar = chat.LineActions.NewBar(view.host, function()
    return view.conv
  end)
  view.host:SetClipsChildren(true)
  view.host:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, view.headless and 0 or -GAP)
  view.host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  view.host:EnableMouseWheel(true)
  view.host:SetScript(
    "OnMouseWheel",
    FG.Wrap("chat-wheel", function(_, delta)
      view:ScrollBy(-delta * WHEEL_LINES * scaled(TL.SPEC.minLine))
    end)
  )
  view.thumb = view.host:CreateTexture(nil, "OVERLAY")
  view.thumb:SetWidth(3)
  view.thumb:Hide()
  FG.Bind(view.thumb, function(t)
    t:SetColorTexture(Theme.color("accentDim", 0.9))
  end)
  view.empty = W.Text(view.host, { role = "ui", color = "textMuted", justify = "CENTER", wrap = true })
  view.empty:SetPoint("TOPLEFT", 12, -16)
  view.empty:SetPoint("TOPRIGHT", -12, -16)
  view.meas = W.Text(view.host, { role = "ui", color = "text", wrap = true })
  view.meas:SetPoint("TOPLEFT", 0, 0)
  view.meas:SetAlpha(0)
  view.measBig = W.Text(view.host, { role = "h3", color = "text", wrap = true })
  view.measBig:SetPoint("TOPLEFT", 0, 0)
  view.measBig:SetAlpha(0)
  view.measW = W.Text(view.host, { role = "ui", color = "text" })
  view.measW:SetPoint("TOPLEFT", 0, 0)
  view.measW:SetAlpha(0)
  view.measWBig = W.Text(view.host, { role = "h3", color = "text" })
  view.measWBig:SetPoint("TOPLEFT", 0, 0)
  view.measWBig:SetAlpha(0)

  for _ = 1, Thread.PREBUILD do
    view.pool[#view.pool + 1] = newRow(view)
  end

  -- Height of the header plus the gap below it; 0 without a header. The head is scaled with the text size, so this
  -- is read again on every layout and never taken from the unscaled base value.
  function view:HeadSpace()
    if view.headless then
      return 0
    end
    return scaled(Thread.HEAD) + GAP
  end

  -- Size of the thread frame in pixels (header included); the window computes it from its own size. The part
  -- the lines get is what the host really covers, whole pixels so the newest line is never cut.
  function view:SetViewSize(width, height)
    head:SetHeight(view.headless and 0 or scaled(Thread.HEAD))
    view.width, view.viewH = math.max(20, width), math.max(0, math.floor(height - view:HeadSpace()))
  end

  function view:NeedsFrames()
    return TL.PoolSize(view.viewH, scaled(TL.SPEC.minLine)) > #view.pool
  end

  function view:Reading()
    return view.conv ~= nil and win.Reading()
  end

  function view:SetBack(on)
    view.back:SetShown(on)
    view.chip:ClearAllPoints()
    view.chip:SetPoint("LEFT", head, "LEFT", on and 30 or 0, 0)
  end

  -- Header ----------------------------------------------------------------------------------------------

  -- "5 members, 2 online" of a team; the symbol of its chip.
  local function teamHead(conv)
    local tid = chat.TeamsUILogic.TeamId(conv.key)
    local info = tid and chat.Teams and chat.Teams.Get(tid) or nil
    if not info then
      return nil, ""
    end
    local all, online = chat.TeamsUILogic.Counts(info)
    return info.icon, string.format(L["chat.teams.head"], chat.TeamsView.MemberText(all), online)
  end

  -- What the game knows of the Battle.net partner (BattleTag, character, in game); nil in combat, for a name
  -- the friend list does not know or without the API. Read again after a few seconds, not on every paint.
  local function bnetFacts(conv)
    if conv.kind ~= "bnet" or FG.InCombat() then
      return nil
    end
    local now = FG.U.now()
    local cache = view.bnetCache
    if cache and cache.key == conv.key and now - cache.at < Thread.BNET_TTL then
      return cache.facts
    end
    local facts = Thread.FindBnet(conv)
    view.bnetCache = { key = conv.key, at = now, facts = facts }
    return facts
  end

  local function infoText(conv)
    local out = {}
    for _, part in ipairs(TL.InfoParts(conv, win.MemberOf(conv.key), bnetFacts(conv))) do
      local key, value = part[1], part[2]
      if key == "tag" then
        out[#out + 1] = value
      elseif key == "character" then
        out[#out + 1] = string.format(L["chat.head.character"], value)
      elseif key == "game" then
        out[#out + 1] = L[value and "chat.head.ingame" or "chat.head.notingame"]
      elseif key == "kind" then
        out[#out + 1] = L["chat.kind." .. value]
      elseif key == "status" then
        out[#out + 1] = L["chat.head." .. value]
      elseif key == "class" then
        out[#out + 1] = FG.GuildKit.ClassName(value, value)
      elseif key == "level" then
        out[#out + 1] = string.format(L["chat.head.level"], value)
      elseif key == "zone" then
        out[#out + 1] = value
      elseif key == "lines" then
        out[#out + 1] = string.format(L["chat.head.lines"], value)
      end
    end
    return table.concat(out, " · ")
  end

  function view:PaintHead()
    local conv = view.conv
    view.head:SetShown(conv ~= nil and not view.headless)
    if not conv then
      return
    end
    local ctx = {
      kindLabel = function(kind)
        return L["chat.kind." .. kind]
      end,
    }
    local title = LL.Title(conv, chat.db.nicknames[conv.key], ctx.kindLabel(conv.kind))
    local isTeam = conv.kind == "team"
    local symbol, teamInfo
    if isTeam then
      symbol, teamInfo = teamHead(conv)
      symbol = symbol or chat.TeamsLogic.LIMITS.DEFAULT_ICON
    end
    view.teamButton:SetShown(isTeam and not view.headless)
    view.latest:ClearAllPoints()
    view.latest:SetPoint("RIGHT", view:Leftmost(), "LEFT", -GAP, 0)
    local bnet = conv.kind == "bnet"
    List.PaintChip(view.chip, LL.KIND_LETTER[conv.kind], not bnet and win.ClassOf(conv.key) or nil, symbol, bnet)
    local peer = chat.Peer
    view.title:SetText((peer and conv.kind == "whisper" and peer.Badge(conv.name) or "") .. title)
    local typing = peer and peer.TypingText(conv.key) or ""
    local info = isTeam and teamInfo or infoText(conv)
    view.info:SetText(typing ~= "" and (typing .. (info ~= "" and " · " .. info or "")) or info)
    W.SetText(view.modeButton.label, nil, L["chat.mode." .. view.mode])
  end

  -- Layout and drawing ---------------------------------------------------------------------------------

  local function measure(text, width, item)
    local meas = item and item.voice == "yell" and view.mode == "messenger" and view.measBig or view.meas
    meas:SetWidth(width)
    meas:SetText(text)
    return meas:GetStringHeight()
  end

  -- Items and heights for the width now. The line at the top of the view keeps its place.
  function view:Rebuild()
    local conv = view.conv
    local anchor, delta
    if view.first and view.items[view.first] then
      local item = view.items[view.first]
      anchor, delta = item.seq, view.offset - item.top
    end
    local deliveryOf
    if conv.kind == "team" and chat.Teams then
      local tid = chat.TeamsUILogic.TeamId(conv.key)
      local set = tid and chat.TeamsUILogic.WaitingSet((chat.Teams.Messages(tid, nil, chat.Teams.PAGE))) or {}
      view.teamSet = set
      deliveryOf = function(line)
        return chat.TeamsUILogic.Delivery(set, line) or TL.Delivery(line)
      end
    end
    view.items = TL.Build(conv, {
      date = List.DateOf,
      dividerSeq = view.dividerSeq,
      unread = view.dividerCount,
      deliveryOf = deliveryOf,
      resend = function(line)
        return chat.WayLogic.Resendable(conv.kind, line)
      end,
    })
    local mode = view.mode
    view.contentH = TL.Layout(view.items, view.width, {
      mode = mode,
      scale = scaled,
      measure = measure,
      text = function(item)
        return mode == "messenger" and bodyText(view, item) or compactText(view, item)
      end,
    })
    if anchor then
      local at = TL.IndexOfSeq(view.items, anchor)
      if at then
        view.offset = view.items[at].top + delta
      end
    end
    view.offset = TL.ClampOffset(view.offset, view.contentH, view.viewH)
  end

  function view:MarkSeen()
    local conv = view.conv
    if not (conv and view:Reading()) then
      return
    end
    local first, last = TL.Visible(view.items, view.offset, view.viewH, 0)
    local seq = TL.LastSeq(view.items, first, last)
    if seq and (seq > conv.readSeq or conv.marked) then
      chat.Unread.MarkReadTo(conv, seq)
      win.ReadChanged(conv.key)
      if chat.Peer then
        FG.Safe("chat-peer-read", chat.Peer.OnRead, conv, seq)
      end
    end
  end

  function view:Render()
    if view.lineBar then
      view.lineBar:Release()
    end
    local conv = view.conv
    local width = view.width
    for _, row in ipairs(view.pool) do
      row:Hide()
    end
    view.empty:SetShown(false)
    view.thumb:Hide()
    view.latest:SetShown(false)
    if not conv then
      view.empty:SetText(L[win.EmptyKey and win.EmptyKey() or "chat.empty.thread"])
      view.empty:Show()
      return
    end
    if #view.items == 0 then
      view.empty:SetText(L["chat.empty.lines"])
      view.empty:Show()
      return
    end
    local first, last = TL.Visible(view.items, view.offset, view.viewH, Thread.OVERSCAN)
    view.first = TL.Visible(view.items, view.offset, view.viewH, 0)
    local slot = 0
    for i = first, last do
      slot = slot + 1
      local row = view.pool[slot]
      if not row and slot <= TL.POOL_MAX and not FG.InCombat() then
        row = newRow(view)
        view.pool[slot] = row
      end
      if not row then
        view.pending = true
        break
      end
      paintRow(view, row, view.items[i], width)
    end
    local max = TL.MaxOffset(view.contentH, view.viewH)
    local atEnd = TL.AtEnd(view.offset, view.contentH, view.viewH)
    view.latest:SetShown(not atEnd)
    view:AnchorTitle(atEnd and view:Leftmost() or view.latest)
    if max > 0 and view.viewH > 0 then
      local h = math.max(16, view.viewH * view.viewH / view.contentH)
      view.thumb:ClearAllPoints()
      view.thumb:SetHeight(h)
      view.thumb:SetPoint("TOPRIGHT", view.host, "TOPRIGHT", 0, -((view.viewH - h) * view.offset / max))
      view.thumb:Show()
    end
    view:MarkSeen()
  end

  function view:AtEnd()
    return TL.AtEnd(view.offset, view.contentH, view.viewH)
  end

  function view:ScrollTo(offset)
    local clamped = TL.ClampOffset(offset == math.huge and view.contentH or offset, view.contentH, view.viewH)
    if clamped ~= view.offset or offset == math.huge then
      view.offset = clamped
      view:Render()
    end
  end

  -- Scrolls to a line and marks it (the jump of a quote head). Returns whether the line is still there.
  function view:JumpTo(seq)
    local index = seq and TL.IndexOfSeq(view.items, seq)
    if not index then
      return false
    end
    view.highlight = seq
    view:ScrollTo(view.items[index].top - scaled(TL.SPEC.day))
    view:Render()
    return true
  end

  function view:ScrollBy(delta)
    view:ScrollTo(view.offset + delta)
  end

  -- Reactions (opt-in, ChatPeer.lua): a small row of symbols near a line. A click on the line, or Ctrl+R for the last
  -- line of the partner, opens it; a click on a symbol sends or takes back the reaction and closes it.
  local picker
  local function closePicker()
    if picker then
      picker:Hide()
    end
  end
  local function buildPicker()
    local box = CreateFrame("Frame", nil, view.host)
    box:SetFrameLevel(view.host:GetFrameLevel() + 20)
    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    FG.Bind(box.bg, function()
      box.bg:SetColorTexture(Theme.color("surface3", 0.97))
    end)
    box.border = W.Border(box, "accent2", 0.6)
    box.buttons = {}
    local x = 4
    for id, symbol in ipairs(chat.PeerLogic.SYMBOLS) do
      local b = CreateFrame("Button", nil, box)
      b:SetSize(34, 24)
      b:SetPoint("LEFT", box, "LEFT", x, 0)
      b.label = W.Text(b, { role = "ui", color = "text", justify = "CENTER" })
      b.label:SetPoint("CENTER")
      b.label:SetText(symbol)
      local function choose()
        if picker.seq and chat.Peer and view.conv then
          FG.Safe("chat-peer-react", chat.Peer.React, view.conv.key, picker.seq, id)
        end
        closePicker()
      end
      b:SetScript("OnClick", FG.Wrap("chat-react", choose))
      b:SetScript("OnEnter", function(self)
        FG.ShowTooltip(self, L["chat.peer.react.tip"], nil, { anchor = "ANCHOR_TOP" })
      end)
      b:SetScript("OnLeave", FG.HideTooltip)
      FG.Focus.register(b, choose)
      box.buttons[id] = b
      x = x + 36
    end
    box:SetSize(x + 2, 32)
    box:Hide()
    return box
  end

  function view:OpenReact(seq, row)
    local conv = view.conv
    if not (conv and chat.Peer and chat.Peer.CanReact(conv.key)) or FG.InCombat() then
      closePicker()
      return false
    end
    picker = picker or buildPicker()
    if picker:IsShown() and picker.seq == seq then
      closePicker()
      return true
    end
    picker.seq = seq
    picker:ClearAllPoints()
    if row then
      picker:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, 2)
    else
      picker:SetPoint("BOTTOMRIGHT", view.host, "BOTTOMRIGHT", -8, 8)
    end
    picker:Show()
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
      local mine = seq
      pcall(timer.After, 8, function()
        if picker and picker.seq == mine then
          picker:Hide()
        end
      end)
    end
    return true
  end

  -- The last line of the partner (the one a reaction usually answers).
  function view:ReactLast()
    local conv = view.conv
    if not conv then
      return false
    end
    local DIR_IN = FG.ChatHistoryLogic.DIR_IN
    for i = #conv.lines, 1, -1 do
      if conv.lines[i].dir == DIR_IN and not conv.lines[i].hidden then
        return view:OpenReact(conv.lines[i].seq, nil)
      end
    end
    return false
  end

  -- PageUp, PageDown and Ctrl+Home/End of the window.
  function view:Key(key, ctrl)
    local page = math.max(scaled(TL.SPEC.minLine), view.viewH - 2 * scaled(TL.SPEC.minLine))
    if key == "PAGEUP" then
      view:ScrollBy(-page)
    elseif key == "PAGEDOWN" then
      view:ScrollBy(page)
    elseif ctrl and key == "HOME" then
      view:ScrollTo(0)
    elseif ctrl and key == "END" then
      view:ScrollTo(math.huge)
    elseif ctrl and key == "R" then
      return view:ReactLast()
    elseif ctrl and key == "C" then
      -- Ctrl+C copies the newest line (the keyboard way to the copy dialog).
      for i = #view.items, 1, -1 do
        if view.items[i].type == "line" then
          return chat.LineActions.Copy(view.items[i])
        end
      end
      return false
    else
      return false
    end
    return true
  end

  -- Draws again after new lines, a resize or a font change. toEnd: jump to the end whatever the position.
  function view:Refresh(toEnd)
    local conv = view.conv and chat.convs.convs[view.conv.key]
    if view.conv and not conv then
      view:Clear()
      return
    end
    view.conv = conv
    if not conv then
      view:PaintHead()
      view:Render()
      return
    end
    local wasAtEnd = view:AtEnd()
    view.mode = view.forceMode or TL.Mode(chat.db, conv.key)
    if not view.dividerSeq and not wasAtEnd then
      local at = chat.Unread.DividerIndex(conv)
      view.dividerSeq = at and conv.lines[at].seq or nil
      view.dividerCount = chat.Unread.Count(conv)
    end
    view:PaintHead()
    view:Rebuild()
    if toEnd or wasAtEnd then
      view.offset = TL.MaxOffset(view.contentH, view.viewH)
    end
    view:Render()
  end

  -- Shows a conversation. opts.seq: scroll to that line and mark it. Otherwise to the first unread line (the
  -- divider) or the end.
  function view:Show(conv, opts)
    opts = opts or {}
    closePicker()
    view.conv, view.items, view.first = conv, {}, nil
    view.offset, view.highlight = 0, opts.seq
    view.dividerSeq, view.dividerCount = nil, nil
    if not conv then
      view:PaintHead()
      view:Render()
      return
    end
    local at = chat.Unread.DividerIndex(conv)
    if at then
      view.dividerSeq, view.dividerCount = conv.lines[at].seq, chat.Unread.Count(conv)
    end
    view.mode = view.forceMode or TL.Mode(chat.db, conv.key)
    view:PaintHead()
    view:Rebuild()
    local target = math.huge
    if opts.seq then
      local index = TL.IndexOfSeq(view.items, opts.seq)
      if index then
        target = view.items[index].top - scaled(TL.SPEC.day)
      end
    elseif view.dividerSeq then
      local index = TL.IndexOfSeq(view.items, view.dividerSeq, true)
      target = index and view.items[index].top - GAP or math.huge
    end
    view.offset = TL.ClampOffset(target == math.huge and view.contentH or target, view.contentH, view.viewH)
    view:Render()
  end

  function view:Clear()
    view:Show(nil)
  end

  function view:ToggleMode()
    local conv = view.conv
    if not conv or view.forceMode then
      return false
    end
    local nextMode = TL.NextMode(view.mode)
    if not chat.Store.Set(chat.db, "modes", conv.key, nextMode) then
      return false
    end
    view:Refresh()
    return true
  end

  return view
end
