-- Share dialog: the only way out of the game is the chat, so text (notes,
-- later macros and routes) can be sent to a chat the player picks. Callers
-- pass plain text (no addon markup). Nothing is sent without a click on the
-- send button.
local _, ns = ...
local W, L = ns.W, ns.L
local PN = ns.PlayerName

local Share = {}
ns.Share = Share

-- The client accepts 255 bytes per chat message, stay clear of it.
local LIMIT = 240
local MAX_MESSAGES = 15
-- Spacing between messages, the chat throttle drops bursts.
local DELAY = 0.4
-- Seconds after a whisper in which "no player named ..." still belongs to it.
local NOT_FOUND_WINDOW = 5
-- Client text of ERR_CHAT_PLAYER_NOT_FOUND_S, used when the global is missing.
local NOT_FOUND_FALLBACK = "No player named '%s' is currently playing."
-- Dialog size and the extra height of the whisper name row.
local DIALOG_W, DIALOG_H, WHISPER_ROW = 560, 460, 34

ns.AddLocale("enUS", {
  ["share.title"] = "Share in chat",
  ["share.note"] = "Goes to real chat, others see it. Check channel and text first.",
  ["share.channel"] = "Channel",
  ["share.ch.say"] = "Say",
  ["share.ch.party"] = "Party",
  ["share.ch.raid"] = "Raid",
  ["share.ch.instance"] = "Instance",
  ["share.ch.guild"] = "Guild",
  ["share.ch.whisper"] = "Whisper",
  ["share.whisperFirst"] = "First name",
  ["share.whisperSurname"] = "Surname (optional)",
  ["share.whisperNotFound"] = "Player not found: %s. Check first and last name and online status.",
  ["share.preview"] = "Preview (exactly what is sent)",
  ["share.input"] = "Text (is split into chat messages)",
  ["share.count.one"] = "%d message",
  ["share.count.many"] = "%d messages",
  ["share.gated"] = "One message per click in Say and numbered channels. Click again for the next.",
  ["share.truncated"] = "Too long: only the first %d of %d messages are sent.",
  ["share.send"] = "Send",
  ["share.sendNext"] = "Send next (%d/%d)",
  ["share.sent"] = "Sent: %s.",
  ["share.failed"] = "Sending stopped at message %d of %d: %s",
  ["share.noNote"] = "No note found for: %s",
  ["share.noteLink"] = "Sends only a link, not the note text.\nWith Forever Guides one click opens it, others see a short code.",
  ["share.drawingLink"] = "Sends only a link, not the picture.\nWith Forever Guides one click opens it, others see a short code.",
  ["share.noDrawing"] = "No drawing found for: %s",
})
ns.AddLocale("deDE", {
  ["share.title"] = "Im Chat teilen",
  ["share.note"] = "Geht in den echten Chat, andere sehen es. Prüfe Kanal und Text.",
  ["share.channel"] = "Kanal",
  ["share.ch.say"] = "Sagen",
  ["share.ch.party"] = "Gruppe",
  ["share.ch.raid"] = "Schlachtzug",
  ["share.ch.instance"] = "Instanz",
  ["share.ch.guild"] = "Gilde",
  ["share.ch.whisper"] = "Flüstern",
  ["share.whisperFirst"] = "Vorname",
  ["share.whisperSurname"] = "Nachname (optional)",
  ["share.whisperNotFound"] = "Spieler nicht gefunden: %s. Prüfe Vor- und Nachname und Online-Status.",
  ["share.preview"] = "Vorschau (genau das wird gesendet)",
  ["share.input"] = "Text (wird in Chat-Nachrichten aufgeteilt)",
  ["share.count.one"] = "%d Nachricht",
  ["share.count.many"] = "%d Nachrichten",
  ["share.gated"] = "Eine Nachricht pro Klick im Sagen-Chat und in nummerierten Kanälen. Klicke erneut für die nächste.",
  ["share.truncated"] = "Zu lang: nur die ersten %d von %d Nachrichten werden gesendet.",
  ["share.send"] = "Senden",
  ["share.sendNext"] = "Nächste senden (%d/%d)",
  ["share.sent"] = "Gesendet: %s.",
  ["share.failed"] = "Senden bei Nachricht %d von %d abgebrochen: %s",
  ["share.noNote"] = "Keine Notiz gefunden für: %s",
  ["share.noteLink"] = "Sendet nur einen Link, nicht den Notiztext.\nMit Forever Guides öffnet ein Klick die Notiz, andere sehen einen kurzen Code.",
  ["share.drawingLink"] = "Sendet nur einen Link, nicht das Bild.\nMit Forever Guides öffnet ein Klick die Zeichnung, andere sehen einen kurzen Code.",
  ["share.noDrawing"] = "Keine Zeichnung gefunden für: %s",
})

local function fmt(key, ...)
  return string.format(L[key], ...)
end

local function countText(n)
  return fmt(n == 1 and "share.count.one" or "share.count.many", n)
end

-- Text preparation -----------------------------------------------------------------

-- Color escapes and hyperlinks must reach the chat whole, so they are never
-- split. Every other pipe is a literal one and has to be doubled.
local function stripEscapes(raw)
  raw = raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
  return (raw:gsub("|", "||"))
end

-- Splits a line into words. Each word has `safe` (escapes kept) and `plain`
-- (escapes removed, for words that are too long to keep whole).
local function words(line)
  local out, cur = {}, nil
  local function add(safe, plain)
    cur = cur or { safe = "", plain = "" }
    cur.safe, cur.plain = cur.safe .. safe, cur.plain .. plain
  end
  local i, n = 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if c == " " or c == "\t" then
      if cur then
        out[#out + 1] = cur
        cur = nil
      end
      i = i + 1
    elseif c == "|" then
      local raw = line:match("^|c%x%x%x%x%x%x%x%x.-|r", i) or line:match("^|H.-|h.-|h", i)
      if raw then
        add(raw, stripEscapes(raw))
        i = i + #raw
      else
        add("||", "||")
        i = i + 1
      end
    else
      local run = line:match("^[^ \t|]+", i)
      add(run, run)
      i = i + #run
    end
  end
  if cur then
    out[#out + 1] = cur
  end
  return out
end

-- Cuts `s` after at most `max` bytes without splitting a UTF-8 character or
-- a doubled pipe. Returns head, rest.
local function cut(s, max)
  local at = max
  while at > 1 do
    local b = s:byte(at + 1)
    if b and b >= 0x80 and b < 0xC0 then
      at = at - 1
    else
      break
    end
  end
  if #s:sub(1, at):match("|*$") % 2 == 1 then
    at = at - 1
  end
  return s:sub(1, at), s:sub(at + 1)
end

-- One message per line (chat has no line breaks), long lines wrap at spaces.
-- A single word longer than the limit is cut hard, escapes dropped.
function Share.Split(text, limit)
  limit = limit or LIMIT
  local msgs = {}
  for line in ((text or ""):gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
    local cur = ""
    local function flush()
      if cur ~= "" then
        msgs[#msgs + 1] = cur
        cur = ""
      end
    end
    for _, w in ipairs(words(line)) do
      local safe = w.safe
      if #safe > limit then
        flush()
        safe = w.plain
        while #safe > limit do
          local head
          head, safe = cut(safe, limit)
          msgs[#msgs + 1] = head
        end
      end
      if cur == "" then
        cur = safe
      elseif #cur + 1 + #safe <= limit then
        cur = cur .. " " .. safe
      else
        flush()
        cur = safe
      end
    end
    flush()
  end
  return msgs
end

-- Messages for title + text, cut to MAX_MESSAGES. Returns messages and the
-- uncut count so the dialog can warn.
function Share.Prepare(title, text)
  local body = text or ""
  if title and title ~= "" then
    body = "[" .. title .. "] " .. body
  end
  local msgs = Share.Split(body)
  local total = #msgs
  for i = total, MAX_MESSAGES + 1, -1 do
    msgs[i] = nil
  end
  return msgs, total
end

-- Channels ---------------------------------------------------------------------------

local function ask(fn, ...)
  if not fn then
    return false
  end
  local ok, v = pcall(fn, ...)
  return ok and v and true or false
end

local function addChannels(opts, ...)
  for i = 1, select("#", ...), 3 do
    local id, name, disabled = select(i, ...)
    if type(id) == "number" and type(name) == "string" and not disabled then
      opts[#opts + 1] = { value = "CHANNEL:" .. id, text = id .. ". " .. name }
    end
  end
end

-- Only channels that make sense right now, rebuilt on every open.
local function fillOptions(opts)
  for i = #opts, 1, -1 do
    opts[i] = nil
  end
  opts[#opts + 1] = { value = "SAY", key = "share.ch.say" }
  if ask(IsInGroup) then
    opts[#opts + 1] = { value = "PARTY", key = "share.ch.party" }
  end
  if ask(IsInRaid) then
    opts[#opts + 1] = { value = "RAID", key = "share.ch.raid" }
  end
  if LE_PARTY_CATEGORY_INSTANCE and ask(IsInGroup, LE_PARTY_CATEGORY_INSTANCE) then
    opts[#opts + 1] = { value = "INSTANCE_CHAT", key = "share.ch.instance" }
  end
  if ask(IsInGuild) then
    opts[#opts + 1] = { value = "GUILD", key = "share.ch.guild" }
  end
  opts[#opts + 1] = { value = "WHISPER", key = "share.ch.whisper" }
  if GetChannelList then
    addChannels(opts, GetChannelList())
  end
end

local function hasOption(opts, value)
  for _, o in ipairs(opts) do
    if o.value == value then
      return true
    end
  end
  return false
end

local function defaultChannel(opts)
  local saved = ns.db and ns.db.settings.shareChannel
  if saved and hasOption(opts, saved) then
    return saved
  end
  return hasOption(opts, "PARTY") and "PARTY" or "SAY"
end

-- Dialog -------------------------------------------------------------------------------

local dlg

-- Last whisper target of this session (diagnostics) and whether the client said
-- the player does not exist.
local lastTarget, lastMissing

local function now()
  return GetTime and GetTime() or 0
end

-- First name left in the field, "" while it is empty. The send button depends on it.
local function firstName(d)
  return PN.Clean(d.first.edit:GetText())
end

-- Full whisper target of the two fields: "<first> <surname>", never one token.
-- A realm typed behind the first name moves to the end ("First Surname-Realm").
local function whisperTarget(d)
  local first, surname = firstName(d), PN.Clean(d.surname.edit:GetText())
  local name, realm = first:match("^([^%-]+)%-(.+)$")
  if name and surname ~= "" then
    return PN.ForWhisper(name, surname, realm)
  end
  return PN.ForWhisper(first, surname)
end

-- Fills the empty (or still auto-filled) name fields: the current player target,
-- else the name last whispered to.
local function fillWhisper(d)
  if not (d.autoFilled or (d.first.edit:GetText() == "" and d.surname.edit:GetText() == "")) then
    return
  end
  local first, surname = PN.Target()
  if not first then
    local saved = ns.db and ns.db.settings.shareWhisper
    if type(saved) == "table" then
      first, surname = PN.Clean(saved.first), PN.Clean(saved.surname)
    end
  end
  if first and first ~= "" then
    d.first.edit:SetText(first)
    d.surname.edit:SetText(surname or "")
    d.autoFilled = true
  end
end

-- Pattern of the client's "no player named" system message.
local function notFoundPattern()
  local text = type(_G.ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and _G.ERR_CHAT_PLAYER_NOT_FOUND_S or NOT_FOUND_FALLBACK
  local escaped = text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  return "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
end

-- Chat type and the fourth SendChatMessage argument (channel number or
-- whisper target) for the selected channel.
local function route(d)
  local id = d.channel:match("^CHANNEL:(%d+)$")
  if id then
    return "CHANNEL", tonumber(id)
  end
  if d.channel == "WHISPER" then
    return "WHISPER", whisperTarget(d)
  end
  return d.channel
end

-- Outside instances the game only lets Say and numbered channels send
-- inside a click, so a timer chain would lose every message after the first.
local function clickGated(chatType)
  if chatType ~= "SAY" and chatType ~= "CHANNEL" then
    return false
  end
  local ok, inInstance = pcall(IsInInstance)
  return not (ok and inInstance)
end

local function paintSend(d)
  local job = d.job
  if job and job.gated then
    W.SetText(d.go.label, nil, fmt("share.sendNext", job.i, #job.msgs))
  else
    W.SetText(d.go.label, "share.send")
  end
  local ready = #d.msgs > 0 and (d.channel ~= "WHISPER" or firstName(d) ~= "")
  if ready and not (job and not job.gated) then
    d.go:Enable()
  else
    d.go:Disable()
  end
end

-- The name row of a whisper pushes the text areas down and grows the dialog.
local function placeBody(d, whisper)
  d.whisperRow = whisper
  local shift = whisper and WHISPER_ROW or 0
  d:SetHeight(DIALOG_H + shift)
  d.bodyLabel:ClearAllPoints()
  d.bodyLabel:SetPoint("TOPLEFT", 16, -138 - shift)
  for _, area in ipairs({ d.preview, d.input }) do
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", 16, -158 - shift)
    area:SetPoint("RIGHT", -16, 0)
  end
end

local function refresh(d)
  d.job = nil
  local msgs, total
  if d.link then
    -- A note goes out as exactly one link message, built by NoteLink.
    msgs, total = d.link.msg and { d.link.msg } or {}, d.link.msg and 1 or 0
  else
    msgs, total = Share.Prepare(d.shareTitle, d.editable and d.input:GetValue() or d.source)
  end
  d.msgs = msgs
  if not d.editable then
    d.preview:SetValue(table.concat(msgs, "\n"))
  end
  local line = countText(#msgs)
  if #msgs > 1 and clickGated((route(d))) then
    line = line .. ". " .. L["share.gated"]
  end
  if d.link and d.link.sizeLine then
    line = line .. ". " .. d.link.sizeLine
  end
  W.SetText(d.count, nil, line)
  if d.status then
    W.SetText(d.warn, nil, d.status)
  elseif d.link and d.link.errText then
    W.SetText(d.warn, nil, d.link.errText)
  elseif d.link and d.link.err then
    W.SetText(d.warn, (d.link.errPrefix or "notelink.err.") .. d.link.err)
  else
    W.SetText(d.warn, nil, total > #msgs and fmt("share.truncated", #msgs, total) or "")
  end
  local whisper = d.channel == "WHISPER"
  if d.whisperRow ~= whisper then
    placeBody(d, whisper)
  end
  d.first:SetShown(whisper)
  d.surname:SetShown(whisper)
  paintSend(d)
end

-- Remembers the target for the next opening and listens for the client's
-- "player not found" answer (see Share.OnSystem).
local function watchWhisper(d, job)
  lastTarget, lastMissing = job.target, false
  if job.i == 1 then
    local first, surname = PN.Split(job.target)
    job.previous = ns.db and ns.db.settings.shareWhisper
    ns.Store.set("settings.shareWhisper", { first = first, surname = surname or "" })
  end
  d.listen = { target = job.target, at = now(), previous = job.previous }
end

local function step(d, job)
  if d.job ~= job then
    return
  end
  local ok, err = pcall(SendChatMessage, job.msgs[job.i], job.chatType, nil, job.target)
  if not ok then
    ns.Notify(fmt("share.failed", job.i, #job.msgs, tostring(err)), "error")
    d.job = nil
    paintSend(d)
    return
  end
  -- A large note is only served to requesters once it really went out.
  if job.i == 1 and d.link and d.link.entry then
    ns.NoteLink.Register(d.link.entry)
  end
  if job.chatType == "WHISPER" then
    watchWhisper(d, job)
  end
  job.i = job.i + 1
  if job.i > #job.msgs then
    ns.Notify(fmt("share.sent", countText(#job.msgs)), "success")
    d.job = nil
  elseif not job.gated then
    C_Timer.After(
      DELAY,
      ns.Wrap("share-send", function()
        step(d, job)
      end)
    )
  end
  paintSend(d)
end

local function send(d)
  local job = d.job
  if job then
    -- Click-gated jobs advance by one message per click.
    if job.gated then
      step(d, job)
    end
    return
  end
  if #d.msgs == 0 or (d.channel == "WHISPER" and firstName(d) == "") then
    return
  end
  local chatType, target = route(d)
  d.job = { msgs = d.msgs, i = 1, chatType = chatType, target = target, gated = clickGated(chatType) }
  step(d, d.job)
end

local function build()
  if dlg then
    return dlg
  end
  local d = ns.Dialogs.Create("ForeverGuidesShareDialog", DIALOG_W, DIALOG_H)
  dlg = d
  d.options = {}
  d.msgs = {}
  W.SetText(d.title, "share.title")

  d.note = W.Text(d, { key = "share.note", role = "ui", color = "textSecondary", wrap = true })
  d.note:SetPoint("TOPLEFT", 16, -44)
  d.note:SetPoint("RIGHT", -16, 0)

  d.dropdown = W.Dropdown(d, {
    key = "share.channel",
    width = 220,
    options = d.options,
    get = function()
      return d.channel
    end,
    set = function(v)
      d.channel, d.status = v, nil
      if v == "WHISPER" then
        fillWhisper(d)
      end
      -- Channel numbers change between sessions, so only fixed channels are remembered.
      if not v:find("^CHANNEL:") then
        ns.Store.set("settings.shareChannel", v)
      end
      refresh(d)
    end,
  })
  d.dropdown:SetWidth(220)
  d.dropdown:SetPoint("TOPLEFT", 16, -84)

  -- Two fields side by side in their own row, each one half of the dialog width.
  local function nameBox(key)
    return W.EditBox(d, {
      placeholder = key,
      height = 24,
      onChange = function()
        d.autoFilled, d.status = false, nil
        refresh(d)
      end,
    })
  end
  d.first = nameBox("share.whisperFirst")
  d.first:SetPoint("TOPLEFT", 16, -136)
  d.first:SetPoint("TOPRIGHT", d, "TOP", -4, -136)
  d.surname = nameBox("share.whisperSurname")
  d.surname:SetPoint("TOPLEFT", d, "TOP", 4, -136)
  d.surname:SetPoint("TOPRIGHT", -16, -136)

  d.bodyLabel = W.Text(d, { key = "share.preview", role = "ui" })
  d.bodyLabel:SetPoint("TOPLEFT", 16, -138)
  d.preview = W.TextArea(d, { height = 186, readOnly = true })
  d.preview:SetPoint("TOPLEFT", 16, -158)
  d.preview:SetPoint("RIGHT", -16, 0)
  d.input = W.TextArea(d, {
    height = 186,
    onChange = function()
      refresh(d)
    end,
  })
  d.input:SetPoint("TOPLEFT", 16, -158)
  d.input:SetPoint("RIGHT", -16, 0)
  d.input.edit:SetMaxLetters(0)

  d.count = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
  d.count:SetPoint("BOTTOMLEFT", 16, 92)
  d.count:SetPoint("RIGHT", -16, 0)
  d.warn = W.Text(d, { role = "ui", color = "warning", wrap = true })
  d.warn:SetPoint("BOTTOMLEFT", 16, 56)
  d.warn:SetPoint("RIGHT", -16, 0)

  d.go = W.Button(d, {
    key = "share.send",
    variant = "primary",
    width = 150,
    onClick = function()
      send(d)
    end,
  })
  d.go:SetPoint("BOTTOMRIGHT", -16, 14)
  d.close = W.Action(d, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    width = 110,
    onClick = function()
      d:Hide()
    end,
  })
  d.close:SetPoint("RIGHT", d.go, "LEFT", -8, 0)
  d:HookScript("OnHide", function()
    d.job = nil
  end)
  return d
end

-- link: nil for free text, else the NoteLink.Build result ({ msg, entry } or { err }).
local function show(title, text, link)
  local d = build()
  d.shareTitle = title or ""
  d.editable = text == nil and link == nil
  d.source = text or ""
  d.link = link
  W.SetText(d.note, link and (link.hint or "share.noteLink") or "share.note")
  fillOptions(d.options)
  d.channel, d.status = defaultChannel(d.options), nil
  fillWhisper(d)
  d.dropdown.Refresh()
  d.input:SetShown(d.editable)
  d.preview:SetShown(not d.editable)
  W.SetText(d.bodyLabel, d.editable and "share.input" or "share.preview")
  if d.editable then
    d.input:SetValue("")
  end
  d:Show()
  refresh(d)
  if d.editable then
    d.input.edit:SetFocus()
  end
  return d
end

-- Handles CHAT_MSG_SYSTEM: the client answers a whisper to an unknown or offline
-- player with ERR_CHAT_PLAYER_NOT_FOUND_S. The send stops and the dialog says so.
function Share.OnSystem(msg)
  local listen = dlg and dlg.listen
  if not listen or type(msg) ~= "string" or now() - listen.at > NOT_FOUND_WINDOW then
    return false
  end
  local who = msg:match(notFoundPattern())
  if not who or not PN.Equal(who, listen.target) then
    return false
  end
  lastMissing = true
  dlg.listen, dlg.job = nil, nil
  -- A name that does not exist is not worth remembering.
  ns.Store.set("settings.shareWhisper", listen.previous)
  dlg.status = fmt("share.whisperNotFound", listen.target)
  refresh(dlg)
  return true
end

ns.On("CHAT_MSG_SYSTEM", function(_, msg)
  Share.OnSystem(msg)
end)

-- Last whisper target with every letter and digit masked, for the diagnostics
-- report (no player names there): shows the separator and the part lengths only.
function Share.LastTargetShape()
  if not lastTarget then
    return nil, false
  end
  local shape = lastTarget:gsub("[\192-\255][\128-\191]*", "x"):gsub("%w", "x")
  return shape, lastMissing == true
end

-- title: prefixed to the first message. text: plain text to send; nil opens
-- the dialog with an empty, editable text box instead of a fixed preview.
function Share.Open(title, text)
  return show(title, text)
end

-- A note is shared as one link message (see NoteLink), never as text.
function Share.OpenNote(note)
  local built, why = ns.NoteLink.Build(note)
  return show("", "", built or { err = why })
end

-- A talent build is shared as one link message too (see TalentLink). `build`
-- is what TalentEditor.Current returns.
function Share.OpenTalent(talents)
  local built, why = ns.TalentLink.Build(talents)
  built = built or { err = why }
  built.hint, built.errPrefix = "talentlink.shareHint", "talentlink.err."
  return show("", "", built)
end

-- A drawing is shared the same way, as one link message (see DrawingLink).
-- Returns the dialog, or nil when there is no drawing with that id.
function Share.OpenDrawing(id)
  local item = ns.Drawings.get(id)
  if not item then
    ns.Notify(fmt("share.noDrawing", tostring(id)), "info")
    return nil
  end
  local DL = ns.DrawingLink
  local built, why, size = DL.Build(item)
  built = built or { err = why }
  built.hint, built.errPrefix = "share.drawingLink", "drawlink.err."
  -- The packed size and how the picture travels, as one line under the preview.
  local bytes = size or #item.data
  built.sizeLine = DL.SizeText(bytes) .. ", " .. DL.ShareLine(DL.ShareInfo(bytes, item.name))
  if why == "tooLarge" then
    built.errText = string.format(L["drawlink.err.tooLarge"], DL.Kilobytes(bytes))
  end
  return show("", "", built)
end
