-- Forever Chat, the add-on extras between two chat partners: "typing ..", "seen" and reactions, plus the logo at
-- the name. They are real add-on messages and so strictly opt-in: function chatPeer of ns.Consent (audience
-- chat, a whisper, send and receive separate, off by default) and one option per extra (off by default).
-- The normal chat (text) never needs any of this and is not touched.
--   Sending     only with chatPeer.send AND the option of the extra AND a whisper chat that is open right now
--               (the window shows it, or its mini window) AND proof that the partner uses the add-on: he sent us
--               a chatPeer message in this session, or Presence knows him while we ourselves agreed to be
--               recognized (presenceMark.send). There is no hello and no request: without proof nothing goes out.
--               Never in combat. Typing at most every 4 s, seen bundled, reactions one per second. A goodbye
--               (type X, no data) goes only to partners we sent something to, when the send consent goes off.
--   Receiving   only with chatPeer.receive (the line drops everything else before it reaches this file), only
--               from a name that has a chat with us, and only what the option of the extra shows. Nothing is
--               stored beyond memory; withdrawing the consent or switching the option off clears the display.
--   Logo        Peer.Badge(name) is the mark of ChatBadge (setting chatBadge*) for a player Presence knows; it is
--               independent of chatPeer. The window draws it in front of names.
-- Hooks for the window files (all nil safe): Peer.OnTyping(key, active) from the input line, Peer.OnRead(conv, seq)
-- from the thread view, Peer.React(key, seq, symbol), Peer.Decor(key, line), Peer.TypingText(key),
-- Peer.CanReact(key). The display is repainted through FG_CHAT_UPDATE({ [key] = true }).
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local PL, Conv, Comm, Consent, PN = chat.PeerLogic, chat.Conversations, FG.Comm, FG.Consent, FG.PlayerName
local L = FG.L

local Peer = {}
chat.Peer = Peer

Peer.FN = "chatPeer"
local FN = Peer.FN

local OPTIONS = {
  { id = "peerTypingShow" },
  { id = "peerTypingSend" },
  { id = "peerSeenShow" },
  { id = "peerSeenSend" },
  { id = "peerReact" },
}
for _, o in ipairs(OPTIONS) do
  local def = {
    id = o.id,
    group = "extras",
    type = "toggle",
    default = false,
    label = "chat.set." .. o.id,
    hint = "chat.set." .. o.id .. ".hint",
  }
  if chat.Settings and chat.Settings.AddOption then
    chat.Settings.AddOption(def)
  end
end

local function g(name)
  return rawget(_G, name)
end

local function clock()
  return Comm.clock()
end

local sender = PL.NewSender(clock)
local view = PL.NewView(clock)
-- Partners (key of the name) that sent us a chatPeer message in this session, and names we sent to.
local heard, sentTo = {}, {}
local registered = false

local function opt(id)
  return chat.Settings ~= nil and chat.Settings.Value(id) == true
end

local function homeRealm()
  for _, name in ipairs({ "GetNormalizedRealmName", "GetRealmName" }) do
    local fn = g(name)
    if type(fn) == "function" then
      local ok, realm = pcall(fn)
      if ok and type(realm) == "string" and realm ~= "" then
        return realm
      end
    end
  end
  return ""
end

local function keyOf(name)
  return Conv.Key("whisper", name, homeRealm())
end

local function dirOut()
  return FG.ChatHistoryLogic.DIR_OUT
end

local function announce(key)
  FG.Emit("FG_CHAT_UPDATE", { [key] = true }, chat.Unread.Total(chat.convs))
end

local function announceAll()
  FG.Emit("FG_CHAT_UPDATE", {}, chat.Unread.Total(chat.convs))
end

local function locked()
  local guard = FG.AutoGuard
  return FG.InCombat() or (guard ~= nil and guard.Blocked())
end

-- Switches -------------------------------------------------------------------------------------------------------

-- The sub-addon is switched on: switched off, nothing is sent and nothing is taken (it may still be loaded).
local function switchedOn()
  return FG.SubAddons == nil or FG.SubAddons.State("chat") == "active"
end

local function mayReceive(id)
  return switchedOn() and Consent.Allows(FN, "receive", "chat") and opt(id)
end

local function maySend(id)
  return switchedOn() and Consent.Allows(FN, "send", "chat") and opt(id)
end

-- The whisper conversation that is open now (window or mini window), nil for anything else.
local function openConv(key)
  local conv = key and chat.convs and chat.convs.convs[key]
  if not conv or conv.kind ~= "whisper" then
    return nil
  end
  local win = chat.Window
  local shown = win and win.IsShown() and win.State().key == key and not win.State().settings
  local mini = chat.Mini and chat.Mini.IsOpen and chat.Mini.IsOpen(key)
  if shown or mini then
    return conv
  end
  return nil
end

-- True when the partner is known to use the add-on (see the head of this file).
local function proven(name)
  if heard[PN.Key(name)] then
    return true
  end
  local presence = FG.Presence
  if not presence or not presence.Has(name) then
    return false
  end
  return Consent.Allows("presenceMark", "send", "group") or Consent.Allows("presenceMark", "send", "guild")
end

-- A name that has a chat with us (the line asks this before it takes an unrequested whisper).
local function knownChat(name)
  if not switchedOn() then
    return false
  end
  local key = keyOf(name)
  local conv = key and chat.convs and chat.convs.convs[key]
  return conv ~= nil and conv.kind == "whisper"
end

-- Receiving --------------------------------------------------------------------------------------------------------

local function convOf(name)
  local key = keyOf(name)
  return key, key and chat.convs.convs[key]
end

local function expireLater(key)
  local timer = g("C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    pcall(timer.After, PL.TYPING_TTL + 0.2, function()
      announce(key)
    end)
  end
end

local function onTyping(name, value)
  local key = convOf(name)
  heard[PN.Key(name)] = true
  if not key or not mayReceive("peerTypingShow") then
    return
  end
  view.SetTyping(key, value.on)
  if value.on then
    expireLater(key)
  end
  announce(key)
end

local function onSeen(name, value)
  local key, conv = convOf(name)
  heard[PN.Key(name)] = true
  if not conv or not mayReceive("peerSeenShow") then
    return
  end
  -- The mark names one of our own lines.
  local seq = PL.Resolve(conv.lines, value.mark, true, dirOut())
  if seq then
    view.SetSeen(key, seq)
    announce(key)
  end
end

local function onReaction(name, value)
  local key, conv = convOf(name)
  heard[PN.Key(name)] = true
  if not conv or not mayReceive("peerReact") then
    return
  end
  -- Side "m": the line is the sender's, so one of the incoming lines for us. Side "y": one of ours.
  local seq = PL.Resolve(conv.lines, value.mark, value.side == "y", dirOut())
  if seq and view.SetReaction(key, seq, value.symbol, "theirs", value.on) then
    announce(key)
  end
end

local function onFarewell(name)
  local key = keyOf(name)
  heard[PN.Key(name)] = nil
  if key then
    view.Clear(key)
    announce(key)
  end
end

-- The line ---------------------------------------------------------------------------------------------------------

-- Registers with the first consent, never at load.
function Peer.Register()
  if not registered then
    registered = Comm.Register(FN, {
      version = 1,
      audiences = { "whisper" },
      on = { T = onTyping, S = onSeen, E = onReaction, X = onFarewell },
      decode = function(payload, typ)
        return PL.Decode(typ, payload)
      end,
      farewell = "X",
      whisperPeer = knownChat,
    }) == true
  end
  return registered
end

function Peer.Registered()
  return registered
end

local function send(typ, payload, name)
  if payload == nil or not Peer.Register() then
    return false
  end
  local ok = Comm.Send(FN, typ, payload, "whisper", name, { priority = "click" })
  if ok then
    sentTo[PN.Key(name)] = name
  end
  return ok == true
end

-- The partner of an open whisper chat that may be sent an extra now, else nil.
local function target(key, id)
  local conv = openConv(key)
  if not conv or locked() or not maySend(id) or not proven(conv.name) then
    return nil
  end
  return conv
end

-- Sending -----------------------------------------------------------------------------------------------------------

-- The input line of chat `key` has text (active) or has not (any more).
function Peer.OnTyping(key, active)
  local conv = active and target(key, "peerTypingSend") or (not active and openConv(key)) or nil
  if not conv or (not active and (locked() or not maySend("peerTypingSend"))) then
    return
  end
  send("T", sender.Typing(key, active), conv.name)
end

-- Sends the bundled "seen" mark of chat `key` now or when the gap is over.
local timers = {}
local function flushSeen(key)
  local conv = target(key, "peerSeenSend")
  if not conv then
    return
  end
  local mark, wait = sender.TakeSeen(key)
  if mark then
    send("S", PL.EncodeSeen(mark), conv.name)
  elseif wait and not timers[key] then
    local timer = g("C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
      timers[key] = true
      pcall(timer.After, wait + 0.05, function()
        timers[key] = nil
        flushSeen(key)
      end)
    end
  end
end

-- The thread shows the lines of `conv` up to seq: the partner's last line up to there counts as seen.
function Peer.OnRead(conv, seq)
  if type(conv) ~= "table" or conv.kind ~= "whisper" or not target(conv.key, "peerSeenSend") then
    return
  end
  local DIR_IN = FG.ChatHistoryLogic.DIR_IN
  for i = #conv.lines, 1, -1 do
    local line = conv.lines[i]
    if line.seq <= seq and line.dir == DIR_IN and not line.hidden then
      sender.NoteSeen(conv.key, PL.Mark(line.text, line.time))
      flushSeen(conv.key)
      return
    end
  end
end

-- True when a reaction on a line of chat `key` could go out right now.
function Peer.CanReact(key)
  return target(key, "peerReact") ~= nil
end

-- Toggles our reaction `symbol` on the line `seq` of chat `key`. Returns true, or false and why.
function Peer.React(key, seq, symbol)
  local conv = target(key, "peerReact")
  if not conv then
    return false, "off"
  end
  local line
  for i = #conv.lines, 1, -1 do
    if conv.lines[i].seq == seq then
      line = conv.lines[i]
      break
    end
  end
  local mark = line and not line.hidden and PL.Mark(line.text, line.time)
  if not mark then
    return false, "line"
  end
  local on = true
  for _, r in ipairs(view.Reactions(key, seq)) do
    if r.id == symbol and r.mine then
      on = false
    end
  end
  if not sender.Reaction(key) then
    return false, "rate"
  end
  -- Side "m": the line is ours, "y": the line is the partner's (seen from the sender of this message).
  local payload = PL.EncodeReaction(line.dir == dirOut() and "m" or "y", mark, symbol, on)
  if not send("E", payload, conv.name) then
    return false, "send"
  end
  view.SetReaction(key, seq, symbol, "mine", on)
  announce(key)
  return true
end

-- Display ---------------------------------------------------------------------------------------------------------

-- The text behind the lines of a card: the reactions, and "seen" on our last seen line. "" for none.
function Peer.Decor(key, line)
  if type(line) ~= "table" then
    return ""
  end
  local parts = {}
  if mayReceive("peerReact") or opt("peerReact") then
    for _, r in ipairs(view.Reactions(key, line.seq)) do
      if (r.theirs and mayReceive("peerReact")) or (r.mine and maySend("peerReact")) then
        parts[#parts + 1] = PL.SymbolText(r.id)
      end
    end
  end
  if mayReceive("peerSeenShow") and view.Seen(key) == line.seq then
    parts[#parts + 1] = L["chat.peer.seen"]
  end
  return table.concat(parts, " ")
end

-- "typing .." for the header of the chat, "" while the partner does not type or the display is off.
function Peer.TypingText(key)
  if mayReceive("peerTypingShow") and view.Typing(key) then
    return L["chat.peer.typing"]
  end
  return ""
end

-- The logo of ChatBadge in front of a name ("" unless the logo setting and Presence say so), with a space.
function Peer.Badge(name)
  local badge = FG.ChatBadge
  if not badge or type(name) ~= "string" then
    return ""
  end
  local ok, markup = pcall(badge.Prefix, name)
  if ok and type(markup) == "string" and markup ~= "" then
    return markup .. " "
  end
  return ""
end

-- Everything that was shown goes with the consent or the option.
local function clearAll()
  view.ClearAll()
  announceAll()
end

local function goodbye()
  local names = sentTo
  sentTo = {}
  sender.Reset()
  for _, name in pairs(names) do
    if registered then
      Comm.Send(FN, "X", PL.EncodeFarewell(), "whisper", name)
    end
  end
end

FG.On("FG_CONSENT_CHANGED", function(_, fn, dir, aud, value)
  if fn ~= FN or aud ~= "chat" then
    return
  end
  if value == true then
    Peer.Register()
  elseif dir == "send" then
    -- The consent is off already: the goodbye goes as a farewell of the line.
    goodbye()
  else
    heard = {}
    clearAll()
  end
end)
-- Switched off: the line is taken out, the display goes. Switched on again: it comes back with the consent.
FG.On("FG_SUBADDON_CHANGED", function(_, id)
  if id ~= "chat" then
    return
  end
  if not switchedOn() then
    goodbye()
    heard = {}
    clearAll()
    if registered then
      Comm.Unregister(FN)
      registered = false
    end
  elseif Consent.Allows(FN, "send", "chat") or Consent.Allows(FN, "receive", "chat") then
    Peer.Register()
  end
end)
FG.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == FN then
    goodbye()
    heard = {}
    clearAll()
  end
end)
FG.On("FG_CHAT_SETTING", function(_, id)
  if id == "peerTypingShow" and not opt(id) then
    view.ClearKind("typing")
  elseif id == "peerSeenShow" and not opt(id) then
    view.ClearKind("seen")
  elseif id == "peerReact" and not opt(id) then
    view.ClearKind("reactions")
  elseif id == "peerTypingSend" and not opt(id) then
    sender.Reset()
  else
    return
  end
  announceAll()
end)

-- The opt-in banners under the heading of the group "extras" of the options: the consent itself is given
-- here or in the tab "Share" (two steps, with the full information text).
if chat.Settings and chat.Settings.AddNotice and FG.OptInNotice then
  chat.Settings.AddNotice("extras", function(page)
    FG.AddParagraph(page, "chat.set.extras.hint", { role = "micro", color = "textMuted", gap = 4 })
    for _, dir in ipairs({ "receive", "send" }) do
      local banner = FG.OptInNotice.Banner(page.content, {
        fn = FN,
        dir = dir,
        aud = "chat",
        textKey = "chat.set.extras.notice." .. dir,
      })
      banner.fgId = "chat-extras-notice-" .. dir
      page.stack:Add(banner, { gap = 4 })
    end
  end)
end

local function consented()
  return Consent.Allows(FN, "send", "chat") or Consent.Allows(FN, "receive", "chat")
end
if consented() then
  Peer.Register()
end
-- The sub-addon is there: the tab "Share" lists the function.
if Consent.MarkAvailable then
  Consent.MarkAvailable(FN)
end

-- Test and state access: counts only, no names.
function Peer.Status()
  local n = 0
  for _ in pairs(heard) do
    n = n + 1
  end
  return { registered = registered, heard = n }
end
