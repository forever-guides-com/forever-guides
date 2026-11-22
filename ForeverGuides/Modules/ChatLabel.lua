-- Readable chat labels, game side. Players without the add-on must not read codes in the chat, so a share goes out as
--   "[Addon Forever Guides: Instances > Gnomeregan > Quests]" / "[Addon Forever Guides: Note "Title"]"
-- and its data travels as ONE add-on message (function linkShare, type P) to the audience of that very line,
-- sent when the text is put into the chat, seconds before the player presses Enter.
--   Receiver  Comm hands the payload over (consent, group or guild membership, throttle are Comm's); it waits per sender
--             for CLL.TTL seconds. The chat filter matches a line of that sender by the key (a hash of the visible
--             text) and turns it into the usual local link, once: the payload belongs to the first line that matches per chat event (a whisper to oneself shows two lines). No match (late, edited, a sender without this version):
--             the readable text stays. A payload that comes after its line changes nothing.
--   Fallback  Say, Yell, emotes, no add-on channel for the exact audience, no consent, combat: the token of
--             NoteLink / PageShare goes out instead (with the readable lead). Receivers parse both.
local _, ns = ...
local L, PN, Comm, Consent = ns.L, ns.PlayerName, ns.Comm, ns.Consent
local CLL, PSL = ns.ChatLabelLogic, ns.PageShareLogic

local CLab = { FN = "linkShare" }
ns.ChatLabel = CLab

ns.AddLocale("enUS", { ["chatlabel.quoted"] = '%s "%s"' })
ns.AddLocale("deDE", { ["chatlabel.quoted"] = "%s „%s“" })

local cache = CLL.NewCache(function()
  return Comm.clock()
end)
CLab.cache = cache

local function g(name)
  return rawget(_G, name)
end

local function selfKey()
  return PN.Key(PN.Normalize(PN.Self()))
end

-- Text -------------------------------------------------------------------------------------------------------

-- "[Addon Forever Guides: Note "Title"]" in the language of this client.
function CLab.KindText(kindLabel, title)
  return CLL.Text(string.format(L["chatlabel.quoted"], kindLabel, title))
end

-- "[Addon Forever Guides: <label>]" (pages: the names of the view).
function CLab.PageText(label)
  return CLL.Text(label)
end

-- Sending ----------------------------------------------------------------------------------------------------

-- The audience of a chat type when the data can go there now: { kind, target } or nil (then the token is the way).
function CLab.Plan(chatType, target)
  local route = CLL.Route(chatType, target)
  if not route or not Comm.IsRegistered(CLab.FN) or not Consent.OnUnlessOff(CLab.FN, "send", "chat") then
    return nil
  end
  if route.kind == "group" then
    local peer = ns.PeerComm
    if not (peer and peer.GroupChannel() == route.channel) then
      return nil
    end
  elseif route.kind == "guild" or route.kind == "officer" then
    local inGuild = g("IsInGuild")
    if type(inGuild) ~= "function" or not inGuild() then
      return nil
    end
  end
  return route
end

-- Sends the data of `share` ({ letter, payload, text }) to the audience of the chat type. True when it was queued, then
-- the readable text is the line to send; false means: send the token. The own line gets its link too.
function CLab.Send(share, chatType, target)
  local route = type(share) == "table" and CLab.Plan(chatType, target)
  if not route then
    return false
  end
  local key = CLL.Key(share.text)
  local wire = CLL.Wire(key, share.letter, share.payload)
  if not wire then
    return false
  end
  local ok = Comm.Send(CLab.FN, "P", wire, route.kind, route.target, { priority = "click" })
  if ok then
    cache.Add(selfKey(), key, { letter = share.letter, payload = share.payload })
  end
  return ok == true
end

-- The function that tells the open edit box (nil on a client that has none).
local function boxGetter()
  local util = g("ChatFrameUtil")
  local get = type(util) == "table" and util.GetActiveWindow or g("ChatEdit_GetActiveWindow")
  return type(get) == "function" and get or nil
end

-- The edit box that is open, nil without one.
local function activeBox(get)
  local ok, box = pcall(get)
  return ok and type(box) == "table" and box or nil
end

-- Chat type and target of the open edit box.
local function boxRoute(box)
  local ok, chatType = pcall(box.GetAttribute, box, "chatType")
  if not ok or type(chatType) ~= "string" then
    return nil
  end
  local attr = chatType == "WHISPER" and "tellTarget" or chatType == "CHANNEL" and "channelTarget" or nil
  local target
  if attr then
    local okTarget, value = pcall(box.GetAttribute, box, attr)
    target = okTarget and value or nil
  end
  return chatType, target
end

-- Puts a share into the chat box: the readable text when the data could go to the audience of the box, else the token.
-- The box is opened first when none is, so the audience is known before the text is chosen.
function CLab.ToChat(share, token)
  local util = g("ChatFrameUtil")
  util = type(util) == "table" and util or {}
  local insert = util.InsertLink or g("ChatEdit_InsertLink")
  local open = util.OpenChat or g("ChatFrame_OpenChat")
  local get = boxGetter()
  local box = get and activeBox(get)
  if get and not box and type(open) == "function" then
    pcall(open, "")
    box = activeBox(get)
  end
  local text = token
  if box then
    local chatType, target = boxRoute(box)
    if chatType and CLab.Send(share, chatType, target) then
      text = share.text
    end
  end
  local ok, done = false, false
  if type(insert) == "function" then
    ok, done = pcall(insert, text)
  end
  if not (ok and done) and type(open) == "function" then
    pcall(open, text)
  end
  return text
end

-- Receiving --------------------------------------------------------------------------------------------------

-- Whispers are taken in from people we talk to only (Comm drops the rest unanswered).
local partners, partnerOrder = {}, {}
local MAX_PARTNERS = 60

local function notePartner(name)
  local key = PN.Key(PN.Normalize(name))
  if key == "" or partners[key] then
    return
  end
  if #partnerOrder >= MAX_PARTNERS then
    partners[table.remove(partnerOrder, 1)] = nil
  end
  partners[key] = true
  partnerOrder[#partnerOrder + 1] = key
end

function CLab.IsPartner(name, typ)
  return typ == "P" and partners[PN.Key(PN.Normalize(name))] == true
end

-- decode of type P (Comm): the wire text as a table, nil refuses it.
function CLab.Decode(wire)
  return CLL.ParseWire(wire)
end

-- Handler of type P: only what the receiver could turn into a link is kept.
function CLab.OnPayload(sender, value)
  if type(value) ~= "table" then
    return
  end
  local NL = ns.NoteLink
  local valid
  if value.letter == CLL.PAGE then
    valid = ns.PageShare ~= nil and ns.PageShare.IsKnown(value.payload)
  else
    valid = NL ~= nil and NL.kinds[value.letter] ~= nil and NL.ParsePayload(value.payload) ~= nil
  end
  if valid then
    cache.Add(PN.Key(PN.Normalize(sender)), value.key, { letter = value.letter, payload = value.payload })
  end
end

-- The line with its readable text turned into the token of the kind, then through the usual rewriting. nil when
-- nothing matches.
function CLab.Expand(msg, who, lineId, slot)
  local s, e, text = CLL.Find(msg)
  if not s then
    return nil
  end
  local entry = cache.Find(PN.Key(PN.Normalize(who)), CLL.Key(text), lineId, slot)
  if not entry then
    return nil
  end
  if entry.letter == CLL.PAGE then
    local token = "[" .. PSL.TOKEN .. ":" .. entry.payload .. ":x]"
    return ns.PageShare.Rewrite(msg:sub(1, s - 1) .. token .. msg:sub(e + 1))
  end
  local NL = ns.NoteLink
  local spec = NL and NL.kinds[entry.letter]
  if not spec then
    return nil
  end
  local title = NL.ChatTitle(CLL.TitleOf(text) or "")
  local token = string.format("[%s:%s:%s]", spec.token, entry.payload, title)
  return NL.Rewrite(msg:sub(1, s - 1) .. token .. msg:sub(e + 1), who, true)
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
  local guard = ns.AutoGuard
  local text, name = guard and guard.Safe(msg), guard and guard.Safe(sender)
  if type(text) ~= "string" or type(name) ~= "string" then
    return false
  end
  if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
    notePartner(name)
  end
  -- For an outgoing whisper the event names the recipient, the author is us.
  local who = event == "CHAT_MSG_WHISPER_INFORM" and PN.Self() or name
  local lineId = select(9, ...)
  lineId = type(lineId) == "number" and lineId or nil
  local ok, out = pcall(CLab.Expand, text, who, lineId, event)
  if ok and out then
    return false, out, sender, ...
  end
  return false
end
CLab.Filter = chatFilter

if ChatFrame_AddMessageEventFilter then
  for _, name in ipairs(CHAT_EVENTS) do
    pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_" .. name, chatFilter)
  end
end
