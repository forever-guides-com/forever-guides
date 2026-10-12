-- Note links: a shared note never goes into the chat as text, only as one short
-- link ("[Note - Title]"). The receiving addon turns it into a clickable local
-- link and opens a read-only viewer. Nothing is saved without a click on
-- "save to my notes".
--
-- The protocol is shared with other content kinds (drawings, see
-- DrawingLink.lua): a kind is a letter ("N" note, "D" drawing) with its own
-- chat token and link name, registered through NL.RegisterKind. Everything
-- below (payloads, transfer, limits, chat rewriting) is the same for all kinds.
--
-- Wire payload (one string, no colon, no pipe):
--   i<code>            the whole content, printable string (small content)
--   r<id8><hash8>      reference: the receiver whispers the sender for the data
-- Player names (senders, whisper targets) are full names with an optional
-- surname ("First Surname") and realm ("-Realm"), see PlayerName.lua. A sender
-- is used exactly as the chat event gave it.
-- Transfer (addon prefix FGNOTE, always WHISPER, every message <= 255 bytes):
--   Q <nonce> <id> <hash> [kind]   request (receiver -> sender), kind "N" or "D",
--                                  left out for notes
--   D <nonce> <seq> <total> <data> one chunk (sender -> receiver)
--   N <nonce> <reason>             refusal ("gone")
local _, ns = ...
local W, L, U, N, M, C = ns.W, ns.L, ns.U, ns.Notes, ns.Markup, ns.MacroCore

local NL = { PREFIX = "FGNOTE", LINK = "FGNote", TOKEN = "FGN" }
ns.NoteLink = NL

-- The client accepts 255 bytes per chat message, stay clear of it.
local LIMIT = 240
local TITLE_CHARS = 40
local CHUNK = 200
-- Receiver limits for everything that arrives from another player.
local MAX_BYTES = 20 * 1024
local MAX_CHUNKS = 110
local MAX_RAW = 40000
local MAX_INLINE = 400
local TIMEOUT = 15
local SEND_GAP = 0.2
local SHARED_MAX = 20
local SERVE_MAX = 3
-- Read by the size verdict of the drawings (DrawingLink.ShareInfo).
NL.CHUNK, NL.CHUNK_GAP = CHUNK, SEND_GAP
local ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"
local GOLD = "ffd24a"
local BODY_W = 462

local ID_PAT = string.rep("[a-z0-9]", 8)
local HASH_PAT = string.rep("[0-9a-f]", 8)

ns.AddLocale("enUS", {
  ["notelink.label"] = "Note",
  ["notelink.viewTitle"] = "Shared note",
  ["notelink.from"] = "From %s",
  ["notelink.save"] = "Save to my notes",
  ["notelink.saveDone"] = "Saved",
  ["notelink.saved"] = "Note saved to your notes.",
  ["notelink.loading"] = "Requesting the note from %s ...",
  ["notelink.timeout"] = "No answer from %s (offline, other faction, no addon).",
  ["notelink.gone"] = "%s no longer shares this note (only until /reload or logout).",
  ["notelink.badData"] = "The note from %s could not be read.",
  ["notelink.tooLarge"] = "The note from %s is too large.",
  ["notelink.noApi"] = "Addon messages are not available in this client.",
  ["notelink.sendFailed"] = "The request to %s could not be sent.",
  ["notelink.err.tooLarge"] = "This note is too large to share in chat.",
  ["notelink.err.unavailable"] = "Sharing unavailable (compression library missing).",
})
ns.AddLocale("deDE", {
  ["notelink.label"] = "Notiz",
  ["notelink.viewTitle"] = "Geteilte Notiz",
  ["notelink.from"] = "Von %s",
  ["notelink.save"] = "In meine Notizen übernehmen",
  ["notelink.saveDone"] = "Übernommen",
  ["notelink.saved"] = "Notiz in deine Notizen übernommen.",
  ["notelink.loading"] = "Frage die Notiz bei %s an ...",
  ["notelink.timeout"] = "Keine Antwort von %s (offline, andere Fraktion, ohne Addon).",
  ["notelink.gone"] = "%s teilt die Notiz nicht mehr (nur bis /reload oder Logout).",
  ["notelink.badData"] = "Die Notiz von %s konnte nicht gelesen werden.",
  ["notelink.tooLarge"] = "Die Notiz von %s ist zu groß.",
  ["notelink.noApi"] = "Addon-Nachrichten sind in diesem Client nicht verfügbar.",
  ["notelink.sendFailed"] = "Die Anfrage an %s konnte nicht gesendet werden.",
  ["notelink.err.tooLarge"] = "Diese Notiz ist zu groß, um sie im Chat zu teilen.",
  ["notelink.err.unavailable"] = "Teilen nicht verfügbar (Kompressionsbibliothek fehlt).",
})

local function fmt(key, ...)
  return string.format(L[key], ...)
end

-- Kinds -------------------------------------------------------------------------------

-- spec = { token, link, label (locale key), prefix (locale key prefix for
-- "<prefix>.gone|badData|tooLarge|timeout|loading"), untitled (locale key),
-- decode(code, hash) -> result | nil, reason, show(sender, result) }.
local KINDS, BY_LINK = {}, {}
NL.kinds = KINDS

function NL.RegisterKind(letter, spec)
  spec.letter = letter
  KINDS[letter] = spec
  BY_LINK[spec.link] = spec
end

local function lib()
  return ns.LibDeflate
end

-- Names ----------------------------------------------------------------------------

-- A player name is "<first> <surname>" with an optional "-<realm>" (see PlayerName).
-- Senders are kept exactly as the chat event gave them and compared with Equal.
local PN = ns.PlayerName

local function isSelf(name)
  return PN.Equal(name, PN.Self())
end

-- Link format ------------------------------------------------------------------------

-- Link mode: "token" (plain text, always accepted by the client) or "link" (a real |Haddon: hyperlink).
-- Addon links are local-only and cannot be sent, so messages go out as "token".
local SEND_MODE = "token"

-- The single place that knows the outgoing message format.
function NL.Format(mode, payload, title, spec)
  spec = spec or KINDS.N
  if mode == "link" then
    return string.format("|Haddon:%s:%s|h[%s - %s]|h", spec.link, payload, L[spec.label], title)
  end
  return string.format("[%s:%s:%s]", spec.token, payload, title)
end

-- One line, no brackets, pipes or control characters, short.
local function chatTitle(title)
  local t = tostring(title or ""):gsub("[%c|%[%]]", " "):gsub("%s+", " ")
  return U.trim(C.truncateChars(U.trim(t), TITLE_CHARS))
end
NL.ChatTitle = chatTitle

local function shownTitle(title, spec)
  title = chatTitle(title)
  return title ~= "" and title or L[(spec or KINDS.N).untitled]
end

-- Content, hash, payload ---------------------------------------------------------------

local function hashOf(raw)
  local LD = lib()
  local n = LD and LD:Adler32(raw) or 0
  return string.format("%04x%04x", math.floor(n / 65536) % 65536, n % 65536)
end
NL.Hash = hashOf

local function pack(title, text)
  return (tostring(title or ""):gsub("[%c]", " ")) .. "\n" .. (text or "")
end

local function encode(raw)
  local LD = lib()
  if not LD then
    return nil
  end
  return LD:EncodeForPrint(LD:CompressDeflate(raw))
end

-- Returns cleaned title, text or nil, reason ("unavailable" | "too-large" | "decode" | "hash").
-- `hash` (optional) is checked against the unpacked content.
function NL.Decode(code, hash)
  local LD = lib()
  if not (LD and LD._FG_MAX_OUTPUT) then
    return nil, "unavailable"
  end
  if type(code) ~= "string" or code == "" or #code > MAX_BYTES then
    return nil, "too-large"
  end
  local okDecode, compressed = pcall(LD.DecodeForPrint, LD, code)
  if not okDecode or not compressed then
    return nil, "decode"
  end
  local okInflate, raw, status = pcall(LD.DecompressDeflate, LD, compressed, MAX_RAW)
  if not okInflate or not raw then
    return nil, status == -20 and "too-large" or "decode"
  end
  if #raw > MAX_RAW then
    return nil, "too-large"
  end
  if hash and hashOf(raw) ~= hash then
    return nil, "hash"
  end
  local title, text = raw:match("^([^\n]*)\n(.*)$")
  if not title then
    return nil, "decode"
  end
  return (N.cleanTitle(title)), M.sanitize(text)
end

-- Returns { kind = "i", code } | { kind = "r", id, hash } or nil.
function NL.ParsePayload(payload)
  if type(payload) ~= "string" then
    return nil
  end
  local code = payload:match("^i([%w%(%)]+)$")
  if code then
    return #code <= MAX_INLINE and { kind = "i", code = code } or nil
  end
  local id, hash = payload:match("^r(" .. ID_PAT .. ")(" .. HASH_PAT .. ")$")
  if id then
    return { kind = "r", id = id, hash = hash }
  end
end

-- Shared notes (sender side) -----------------------------------------------------------

-- Only notes the player actively sent are ever served, and only until the next
-- reload: snapshots in memory, never SavedVariables.
local shared, sharedOrder = {}, {}

local function randomString(n)
  local chars = {}
  for i = 1, n do
    local k = N.random(#ALPHABET)
    chars[i] = ALPHABET:sub(k, k)
  end
  return table.concat(chars)
end

function NL.Register(entry)
  shared[entry.id] = entry
  sharedOrder[#sharedOrder + 1] = entry.id
  while #sharedOrder > SHARED_MAX do
    shared[table.remove(sharedOrder, 1)] = nil
  end
end

function NL.IsShared(id)
  return shared[id] ~= nil
end

-- Builds the one chat message for printable content `code` of kind `letter`.
-- `hash` is what the receiver checks a transferred code against. Returns
-- { msg, entry } or nil, "tooLarge". `entry` (large content only) must be
-- passed to NL.Register once the message was really sent.
function NL.BuildFor(letter, code, hash, title, mode)
  mode = mode or SEND_MODE
  local spec = KINDS[letter]
  title = shownTitle(title, spec)
  local msg = NL.Format(mode, "i" .. code, title, spec)
  if #msg <= LIMIT then
    return { msg = msg }
  end
  if #code > MAX_BYTES then
    return nil, "tooLarge"
  end
  local entry = { id = randomString(8), hash = hash, code = code, kind = letter }
  while shared[entry.id] do
    entry.id = randomString(8)
  end
  local payload = "r" .. entry.id .. entry.hash
  msg = NL.Format(mode, payload, title, spec)
  while #msg > LIMIT and title ~= "" do
    title = U.trim(C.truncateChars(title, math.max(0, C.charCount(title) - 5)))
    msg = NL.Format(mode, payload, title, spec)
  end
  if #msg > LIMIT then
    return nil, "tooLarge"
  end
  return { msg = msg, entry = entry }
end

-- Builds the one chat message for a note. Returns { msg, entry } or nil, reason
-- ("tooLarge" | "unavailable").
function NL.Build(note, mode)
  local raw = pack(note.title, note.text)
  local code = encode(raw)
  if not code then
    return nil, "unavailable"
  end
  return NL.BuildFor("N", code, hashOf(raw), note.title, mode)
end

-- Addon messages ----------------------------------------------------------------------

local function sendAddon(msg, target)
  local api = C_ChatInfo
  if not (api and api.SendAddonMessage) then
    return false
  end
  local ok, res = pcall(api.SendAddonMessage, NL.PREFIX, msg, "WHISPER", target)
  if not ok or res == false then
    return false
  end
  local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
  return not (type(res) == "number" and res ~= success)
end

local serving = {}

local function servingCount()
  local n = 0
  for _ in pairs(serving) do
    n = n + 1
  end
  return n
end

local function pump(job)
  local i = job.i
  local piece = job.code:sub((i - 1) * CHUNK + 1, i * CHUNK)
  local sent = sendAddon(string.format("D\t%s\t%d\t%d\t%s", job.nonce, i, job.total, piece), job.to)
  if not sent or i >= job.total then
    serving[job.key] = nil
    return
  end
  job.i = i + 1
  C_Timer.After(
    SEND_GAP,
    ns.Wrap("notelink-serve", function()
      pump(job)
    end)
  )
end

-- Sender side: answers a request for content of `kind` this player shared.
local function serve(requester, nonce, id, hash, kind)
  local key = PN.Key(requester)
  if key == "" or isSelf(requester) or serving[key] then
    return
  end
  local entry = shared[id]
  if not entry or entry.hash ~= hash or (entry.kind or "N") ~= kind then
    sendAddon(string.format("N\t%s\tgone", nonce), requester)
    return
  end
  if servingCount() >= SERVE_MAX then
    return
  end
  local job = {
    key = key,
    to = requester,
    nonce = nonce,
    code = entry.code,
    total = math.ceil(#entry.code / CHUNK),
    i = 1,
  }
  serving[key] = job
  pump(job)
end

-- Receiver side ------------------------------------------------------------------------

local pending

-- `key` is the part after the kind's locale prefix ("gone", "timeout", ...).
local function fail(p, key)
  if pending == p then
    pending = nil
    ns.Notify(fmt(KINDS[p.kind].prefix .. "." .. key, p.sender), "warning")
  end
end

-- Inactivity timeout: every accepted chunk restarts the wait.
local function arm(p)
  local mark = p.got
  C_Timer.After(
    TIMEOUT,
    ns.Wrap("notelink-timeout", function()
      if pending ~= p then
        return
      end
      if p.got ~= mark then
        arm(p)
      else
        fail(p, "timeout")
      end
    end)
  )
end

local function decodeFailure(spec, sender, why)
  ns.Notify(fmt(spec.prefix .. (why == "too-large" and ".tooLarge" or ".badData"), sender), "warning")
end

local function finish(p)
  pending = nil
  local spec = KINDS[p.kind]
  local result, why = spec.decode(table.concat(p.parts, "", 1, p.total), p.hash)
  if not result then
    decodeFailure(spec, p.sender, why)
    return
  end
  spec.show(p.sender, result, p.title)
end

local function receive(p, seq, total, data)
  if seq < 1 or seq > total or #data > CHUNK then
    return
  end
  if p.total and p.total ~= total then
    return fail(p, "badData")
  end
  if p.parts[seq] then
    return
  end
  p.total = total
  p.bytes = p.bytes + #data
  if p.bytes > MAX_BYTES then
    return fail(p, "tooLarge")
  end
  p.parts[seq] = data
  p.got = p.got + 1
  if p.got == p.total then
    finish(p)
  end
end

-- Handles CHAT_MSG_ADDON. Replies are only accepted for the one open request,
-- from the player asked, with the matching nonce.
function NL.OnAddon(prefix, text, channel, sender)
  if
    prefix ~= NL.PREFIX
    or channel ~= "WHISPER"
    or type(text) ~= "string"
    or type(sender) ~= "string"
    or #text > 255
  then
    return
  end
  local kind = text:sub(1, 2)
  if kind == "Q\t" then
    -- The kind is optional on the wire, a request without one is for a note.
    local nonce, id, hash, letter = text:match("^Q\t(%w+)\t([a-z0-9]+)\t([0-9a-f]+)\t(%u)$")
    if not nonce then
      nonce, id, hash = text:match("^Q\t(%w+)\t([a-z0-9]+)\t([0-9a-f]+)$")
      letter = "N"
    end
    if nonce and #nonce <= 12 and #id == 8 and #hash == 8 and KINDS[letter] then
      serve(sender, nonce, id, hash, letter)
    end
    return
  end
  local p = pending
  if not p or not PN.Equal(sender, p.sender) then
    return
  end
  if kind == "D\t" then
    local nonce, seq, total, data = text:match("^D\t(%w+)\t(%d+)\t(%d+)\t([%w%(%)]*)$")
    total = tonumber(total)
    if nonce == p.nonce and total and total >= 1 and total <= MAX_CHUNKS then
      receive(p, tonumber(seq), total, data)
    end
  elseif kind == "N\t" then
    local nonce, reason = text:match("^N\t(%w+)\t(%a+)$")
    if nonce == p.nonce then
      fail(p, reason == "gone" and "gone" or "badData")
    end
  end
end

-- Asks `sender` for shared content of `letter` (default a note). `title` is the
-- one from the chat link, for kinds that do not carry their own.
function NL.Request(sender, id, hash, letter, title)
  letter = letter or "N"
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
    ns.Notify(L["notelink.noApi"], "warning")
    return
  end
  local p = {
    sender = sender,
    hash = hash,
    kind = letter,
    title = title,
    nonce = randomString(6),
    parts = {},
    got = 0,
    bytes = 0,
  }
  pending = p
  local request = string.format("Q\t%s\t%s\t%s", p.nonce, id, hash)
  if letter ~= "N" then
    request = request .. "\t" .. letter
  end
  if not sendAddon(request, sender) then
    pending = nil
    ns.Notify(fmt("notelink.sendFailed", sender), "error")
    return
  end
  ns.Notify(fmt(KINDS[letter].prefix .. ".loading", sender), "info")
  arm(p)
end

-- Opens shared content from a chat payload. `sender` comes from the chat event,
-- `title` from the link text (only used by kinds without a title in the data).
function NL.Open(sender, payload, letter, title)
  letter = letter or "N"
  local spec = KINDS[letter]
  local p = NL.ParsePayload(payload)
  if not (spec and p) then
    return false
  end
  if p.kind == "i" then
    local result, why = spec.decode(p.code)
    if not result then
      decodeFailure(spec, sender, why)
      return false
    end
    spec.show(sender, result, title)
    return true
  end
  if isSelf(sender) then
    local entry = shared[p.id]
    local result
    if entry and entry.hash == p.hash and (entry.kind or "N") == letter then
      result = spec.decode(entry.code, p.hash)
    end
    if not result then
      ns.Notify(fmt(spec.prefix .. ".gone", sender), "warning")
      return false
    end
    spec.show(sender, result, title)
    return true
  end
  NL.Request(sender, p.id, p.hash, letter, title)
  return true
end

-- Chat rewriting -----------------------------------------------------------------------

-- Local links carry a per-session secret, so a link pasted by another player
-- (with a faked sender) is never accepted by the click handler.
local KEY = randomString(10)

-- `sender` is already encoded with PlayerName.Encode: the space of a name with a
-- surname (and any colon) would break the colon separated parsing in OnLink.
local function localLink(spec, sender, payload, title)
  return string.format(
    "|cff%s|Haddon:%s:%s:%s:%s|h[%s - %s]|h|r",
    GOLD,
    spec.link,
    KEY,
    sender,
    payload,
    L[spec.label],
    shownTitle(title, spec)
  )
end

local function labelTitle(label)
  label = label:match("^%[(.*)%]$") or label
  return label:match("^.-%s%-%s(.*)$") or label
end

-- Replaces the first valid link or token (of any kind) in a received chat
-- message with a local clickable link. Notes are looked at before other kinds,
-- so a message with both only converts the note. Returns the new message or
-- nil when unchanged.
function NL.Rewrite(msg, sender)
  if type(msg) ~= "string" or not msg:find("FG", 1, true) or type(sender) ~= "string" then
    return nil
  end
  local who = PN.Encode(sender)
  if who == "" then
    return nil
  end
  local done = 0
  local out = msg
  local others = {}
  for letter in pairs(KINDS) do
    if letter ~= "N" then
      others[#others + 1] = letter
    end
  end
  table.sort(others)
  local order = { "N", unpack(others) }
  for _, letter in ipairs(order) do
    local spec = KINDS[letter]
    local function convert(payload, title)
      if done > 0 or not NL.ParsePayload(payload) then
        return nil
      end
      done = done + 1
      return localLink(spec, who, payload, title)
    end
    out = out:gsub("|c%x%x%x%x%x%x%x%x(|Haddon:" .. spec.link .. ":[^|]*|h[^|]*|h)|r", "%1")
    out = out:gsub("|Haddon:" .. spec.link .. ":([^|]*)|h([^|]*)|h", function(payload, label)
      return convert(payload, labelTitle(label))
    end)
    out = out:gsub("%[" .. spec.token .. ":([^:%]|]+):([^%]|]*)%]", convert)
  end
  if done == 0 then
    return nil
  end
  return out
end

local CHAT_EVENTS = {
  "SAY",
  "YELL",
  "PARTY",
  "PARTY_LEADER",
  "RAID",
  "RAID_LEADER",
  "INSTANCE_CHAT",
  "INSTANCE_CHAT_LEADER",
  "GUILD",
  "OFFICER",
  "WHISPER",
  "WHISPER_INFORM",
  "CHANNEL",
}

local function chatFilter(_, event, msg, sender, ...)
  -- For an outgoing whisper the event names the recipient, the author is us.
  local who = event == "CHAT_MSG_WHISPER_INFORM" and PN.Self() or sender
  local ok, out = pcall(NL.Rewrite, msg, who)
  if ok and out then
    return false, out, sender, ...
  end
  return false
end

-- A click on a local link: "addon:<link name>:<key>:<sender>:<payload>", the
-- sender percent-encoded (links from before the encoding hold the plain name). `text`
-- (second SetItemRef argument) is the shown link text, it carries the title.
function NL.OnLink(link, text)
  if type(link) ~= "string" then
    return
  end
  local name, key, sender, payload = link:match("^addon:(%w+):([^:]+):([^:]+):([^:]+)$")
  local spec = name and BY_LINK[name]
  if spec and key == KEY then
    local label = type(text) == "string" and text:match("|h(%[.*%])|h") or nil
    NL.Open(PN.Decode(sender), payload, spec.letter, label and labelTitle(label) or nil)
  end
end

if ChatFrame_AddMessageEventFilter then
  for _, name in ipairs(CHAT_EVENTS) do
    pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_" .. name, chatFilter)
  end
end
if hooksecurefunc then
  pcall(hooksecurefunc, "SetItemRef", ns.Wrap("notelink-click", NL.OnLink))
end
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix, NL.PREFIX)
end
ns.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
  NL.OnAddon(prefix, text, channel, sender)
end)

-- Viewer -------------------------------------------------------------------------------

local function classHex()
  local ok, _, class = pcall(UnitClass, "player")
  if ok and class and ns.Theme.classColors[class] then
    return (ns.Theme.classColors[class]:gsub("#", ""))
  end
end

-- Display string for the sanitized note text, same markup rules as the note window.
function NL.Render(text)
  local ctx = { fg = N.DEFAULT_STYLE.fg, bg = N.DEFAULT_STYLE.bg, classHex = classHex() }
  local lines = {}
  for _, b in ipairs(M.parse(text)) do
    local body = M.toWoW(b.spans, ctx)
    if b.kind == "h" then
      body = "|cff" .. M.headingHex(ctx) .. body .. "|r"
    elseif b.kind == "li" then
      body = "- " .. body
    elseif b.kind == "check" then
      body = (b.checked and "[x] " or "[ ] ") .. body
    end
    lines[#lines + 1] = body
  end
  return table.concat(lines, "\n")
end

local view

local function saveCopy()
  local data = view and view.data
  if not data or data.saved then
    return
  end
  local note = N.create({ title = data.title, text = data.text }, { kind = "chat", at = U.now() })
  if not note then
    ns.Notify(fmt("notes.slash.limit", N.MAX_NOTES), "warning")
    return
  end
  data.saved = true
  view.save:Disable()
  W.SetText(view.save.label, "notelink.saveDone")
  ns.Notify(L["notelink.saved"], "success")
end

local function build()
  if view then
    return view
  end
  local d = ns.Dialogs.Create("ForeverGuidesNoteLinkView", 520, 440)
  view = d
  d.author = W.Text(d, { role = "ui", color = "textSecondary" })
  d.author:SetPoint("TOPLEFT", 16, -44)
  d.author:SetPoint("RIGHT", -16, 0)
  d.area = W.ScrollArea(d)
  d.area:SetPoint("TOPLEFT", 16, -72)
  d.area:SetPoint("BOTTOMRIGHT", -16, 56)
  W.Fill(d.area, "surface", 1)
  d.body = W.Text(d.area.content, { role = "text", wrap = true })
  d.body:SetPoint("TOPLEFT", 6, -6)
  d.save = W.Button(d, {
    key = "notelink.save",
    variant = "primary",
    width = 230,
    onClick = saveCopy,
  })
  d.save:SetPoint("BOTTOMRIGHT", -16, 14)
  d.close = W.Action(d, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    width = 110,
    onClick = function()
      d:Hide()
    end,
  })
  d.close:SetPoint("RIGHT", d.save, "LEFT", -8, 0)
  return d
end

-- title, text: already cleaned by NL.Decode.
function NL.Show(sender, title, text)
  local d = build()
  d.data = { sender = sender, title = title, text = text }
  W.SetText(d.title, nil, title ~= "" and title or L["notes.untitled"])
  W.SetText(d.author, nil, fmt("notelink.from", sender))
  -- Width first, the height of wrapped text depends on it.
  d.body:SetWidth(BODY_W)
  W.SetText(d.body, nil, NL.Render(text))
  d.area:SetContentHeight(d.body:GetStringHeight() + 16)
  d.area:ScrollTo(0)
  W.SetText(d.save.label, "notelink.save")
  d.save:Enable()
  d:Show()
  return d
end

NL.RegisterKind("N", {
  token = NL.TOKEN,
  link = NL.LINK,
  label = "notelink.label",
  prefix = "notelink",
  untitled = "notes.untitled",
  decode = function(code, hash)
    local title, text = NL.Decode(code, hash)
    if not title then
      return nil, text
    end
    return { title = title, text = text }
  end,
  show = function(sender, result)
    NL.Show(sender, result.title, result.text)
  end,
})
