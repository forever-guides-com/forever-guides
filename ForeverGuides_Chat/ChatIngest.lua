-- Forever Chat, the input side (game access): listens to the chat events and puts every line into the
-- conversations (ChatConversations.lua, counted by ChatUnread.lua). The mapping lives in ChatIngestLogic.lua.
--
-- The events are registered on one frame of this add-on only while the add-on is loaded and switched on,
-- and taken off again the moment it is switched off. Nothing is hooked, filtered or hidden: the chat of the
-- game stays as it is. The lines go to memory and, with the option "archive" (default on), into the saved
-- conversations (ChatArchive.lua, the only writer, which restores them at the next start). The old local
-- whisper history of the main add-on (settings.chat.enabled) is read once into the archive, then the
-- recorder of the main add-on leaves whispers to the archive.
--
-- FG_CHAT_UPDATE(keys, unreadTotal) tells the windows that conversations changed: keys is a set of
-- conversation keys. It comes at most once per DEBOUNCE seconds.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local IL, Conv, Unread, Store = chat.IngestLogic, chat.Conversations, chat.Unread, chat.Store
local PN = FG.PlayerName

local Ingest = {}
chat.Ingest = Ingest

Ingest.DEBOUNCE = 0.25
-- Errors in the event handler after which the input stops for the session.
Ingest.MAX_ERRORS = 3

local frame
local registered = {}
local running, halted, historyLoaded = false, false, false
local errors = 0
local stats = { lines = 0, skipped = 0 }
local dirty = {}

-- Game access -----------------------------------------------------------------------------------------

local function realmName()
  for _, name in ipairs({ "GetNormalizedRealmName", "GetRealmName" }) do
    local fn = rawget(_G, name)
    if type(fn) == "function" then
      local ok, realm = pcall(fn)
      if ok and type(realm) == "string" and realm ~= "" then
        return realm
      end
    end
  end
  return nil
end

local function guildName()
  local fn = rawget(_G, "GetGuildInfo")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, name = pcall(fn, "player")
  return ok and type(name) == "string" and name ~= "" and name or nil
end

-- True for a player on the ignore list of the game. The functions are asked only when they exist.
local function isIgnored(name, guid)
  local list = rawget(_G, "C_FriendList")
  if type(list) ~= "table" then
    return false
  end
  local guard = FG.AutoGuard
  if guid and type(list.IsIgnoredByGuid) == "function" then
    local ok, ignored = pcall(list.IsIgnoredByGuid, guid)
    if ok and guard.Safe(ignored) == true then
      return true
    end
  end
  if type(list.IsIgnored) == "function" then
    local ok, ignored = pcall(list.IsIgnored, name)
    return ok and guard.Safe(ignored) == true
  end
  return false
end

-- What the game knows of the Battle.net partner of a CHAT_MSG_BN_* line, looked up by the account id of the line
-- (argument 13, bnSenderID): { id, name, tag, character }. Secret values are dropped (nil). The account name of
-- Retail is often an escape form ("|Ks17|k") that only the game chat resolves: it stays in name and the logic
-- discards it. character: the WoW character of the partner while the partner plays WoW. Nil without the API.
local function bnetAccount(args)
  local info = rawget(_G, "C_BattleNet")
  local guard = FG.AutoGuard
  local accountId = guard.Safe(args[IL.ARG.BN_ID])
  if type(accountId) ~= "number" then
    return nil
  end
  local out = { id = accountId }
  if type(info) ~= "table" or type(info.GetAccountInfoByID) ~= "function" then
    return out
  end
  local ok, account = pcall(info.GetAccountInfoByID, accountId)
  if not ok or type(account) ~= "table" then
    return out
  end
  out.name, out.tag = guard.Safe(account.accountName), guard.Safe(account.battleTag)
  local game = type(account.gameAccountInfo) == "table" and account.gameAccountInfo or {}
  if guard.Safe(game.isOnline) == true and guard.Safe(game.clientProgram) == "WoW" then
    out.character = guard.Safe(game.characterName)
  end
  return out
end

-- The name of a community channel ("Community:<club id>:<stream id>"): the community, then its channel.
local function communityName(channel)
  local clubId, streamId = tostring(channel or ""):match("^Community:(%d+):(%d+)$")
  local club = rawget(_G, "C_Club")
  if not clubId or type(club) ~= "table" or type(club.GetClubInfo) ~= "function" then
    return nil
  end
  local guard = FG.AutoGuard
  local ok, info = pcall(club.GetClubInfo, clubId)
  local name = ok and type(info) == "table" and guard.Safe(info.name) or nil
  if type(name) ~= "string" or name == "" then
    return nil
  end
  if type(club.GetStreamInfo) == "function" then
    local okStream, stream = pcall(club.GetStreamInfo, clubId, streamId)
    local streamName = okStream and type(stream) == "table" and guard.Safe(stream.name) or nil
    if type(streamName) == "string" and streamName ~= "" then
      return name .. IL.ZONE_SEPARATOR .. streamName
    end
  end
  return name
end

local function options()
  local db = chat.db
  return type(db) == "table" and type(db.options) == "table" and db.options or {}
end

-- The switch "ignoreIgnored" (default on): lines of ignored players stay out of the messenger.
local function skipsIgnored()
  return chat.HooksLogic == nil or chat.HooksLogic.Option(options(), "ignoreIgnored")
end

local function settings()
  local db = FG.db
  return type(db) == "table" and db.settings or nil
end

-- Context --------------------------------------------------------------------------------------------

local ctx = { blocked = isIgnored, guild = guildName, bnetAccount = bnetAccount, community = communityName, own = "" }
local unreadCtx, unreadSig

-- The own name as "Name-Realm", looked up again while the client has not told it yet.
local function refreshOwn()
  if ctx.own ~= "" then
    return
  end
  ctx.homeRealm = realmName()
  local name = PN.Self()
  ctx.own = name ~= "" and PN.ForWhisper(name, nil, ctx.homeRealm) or ""
  Conv.SetOwn(chat.convs, ctx.own)
end

-- The context of Unread.Note. Built again when the own name, the key words or a switch changed.
local function unreadContext(now)
  local db, opts = chat.db, options()
  local words = type(opts.keywords) == "table" and opts.keywords or {}
  local sig = table.concat(
    { ctx.own, tostring(opts.mentionBreaksMute), tostring(opts.channelMentionOnly), table.concat(words, "\31") },
    "\30"
  )
  if not unreadCtx or sig ~= unreadSig or unreadCtx.muted ~= db.muted then
    unreadCtx, unreadSig = Unread.Context(db, ctx.own, now), sig
  end
  unreadCtx.now = now
  return unreadCtx
end

-- Updates for the windows ----------------------------------------------------------------------------

local function flush()
  local keys = dirty
  dirty = {}
  if next(keys) ~= nil then
    FG.Emit("FG_CHAT_UPDATE", keys, Unread.Total(chat.convs))
  end
end

local function markDirty(key)
  dirty[key] = true
  FG.Debounce("chat-update", Ingest.DEBOUNCE, flush)
end

-- Handling -------------------------------------------------------------------------------------------

-- Before the account keys, a Battle.net partner was keyed by the name shown for it ("bnet:lempard"). What was
-- stored under that key (pin, nickname, mute, lines of this session) moves to the key of the account. Returns the
-- old key when there was something to move.
local function adoptLegacyBnet(target, conv)
  local old = Conv.Key("bnet", target.name)
  if not old or old == conv.key then
    return nil
  end
  local had = Conv.Get(chat.convs, old) ~= nil
  Conv.Merge(chat.convs, conv.key, old)
  Store.Move(chat.db, old, conv.key)
  if chat.Archive then
    chat.Archive.Merged(conv, old)
  end
  return had and old or nil
end

-- The system message of the game ("No player named X is currently playing") reaches the sender of the messenger,
-- which turns a whisper that went to nobody into a failed one. It makes no conversation and no line.
local SYSTEM = "CHAT_MSG_SYSTEM"

-- One chat event. Returns true when a line was taken, else false and the reason (see IngestLogic.Build, and
-- the reasons of Conversations.AddLine: "time", "text", "duplicate", "full").
local function handle(event, ...)
  if event == SYSTEM then
    if chat.Send then
      chat.Send.OnSystemMessage((...))
    end
    return true
  end
  refreshOwn()
  local now = FG.U.now()
  ctx.now, ctx.localChat = now, options().localChat ~= false
  ctx.restrictedName = FG.L["chat.restricted.name"]
  ctx.bnetUnknownName = FG.L["chat.bnet.unknown"]
  ctx.blocked = skipsIgnored() and isIgnored or nil
  local target, input, extra = IL.Build(ctx, event, { ... })
  if not target then
    stats.skipped = stats.skipped + 1
    return false, input
  end
  local line, conv = Conv.AddLine(chat.convs, target, input)
  if not line then
    stats.skipped = stats.skipped + 1
    return false, conv
  end
  local legacy = target.id and adoptLegacyBnet(target, conv)
  if legacy then
    markDirty(legacy)
  end
  if extra and extra.number then
    conv.number = extra.number
  end
  Unread.Note(unreadContext(now), conv, line)
  stats.lines = stats.lines + 1
  markDirty(conv.key)
  return true
end

local function onEvent(_, event, ...)
  if not FG.Safe("chat-ingest", handle, event, ...) then
    errors = errors + 1
    if errors >= Ingest.MAX_ERRORS then
      halted = true
      Ingest.Stop()
    end
  end
end

-- Events ---------------------------------------------------------------------------------------------

local function unregisterAll()
  if frame then
    for event in pairs(registered) do
      pcall(frame.UnregisterEvent, frame, event)
    end
  end
  registered = {}
end

-- Registers what the options ask for and takes off the rest. An event the client does not know stays out.
-- Nothing is registered while the messenger intake is switched off (options.intake, default on: the add-on
-- itself is off by default, so switching it on is the decision to read the chat).
function Ingest.Sync()
  if not running then
    return
  end
  frame = frame or CreateFrame("Frame")
  frame:SetScript("OnEvent", onEvent)
  local wanted = {}
  local opts = options()
  local list = opts.intake ~= false and IL.Events({ localChat = opts.localChat ~= false }) or {}
  if #list > 0 then
    list[#list + 1] = SYSTEM
  end
  for _, event in ipairs(list) do
    wanted[event] = true
    if not registered[event] and pcall(frame.RegisterEvent, frame, event) then
      registered[event] = true
    end
  end
  for event in pairs(registered) do
    if not wanted[event] then
      pcall(frame.UnregisterEvent, frame, event)
      registered[event] = nil
    end
  end
  Ingest.SyncArchive()
end

-- The own name as "Name-Realm" ("" while the client has not told it yet).
function Ingest.Own()
  refreshOwn()
  return ctx.own
end

-- Lets the archive follow the add-on, the intake and its own option.
function Ingest.SyncArchive()
  if chat.Archive then
    chat.Archive.Refresh(Ingest.Own())
  end
end

-- History -----------------------------------------------------------------------------------------------

-- Puts the whisper conversations of the local history back into memory, once, and only with the main
-- switch settings.chat.enabled on. The lines count as read. Returns the number of lines taken.
function Ingest.LoadHistory()
  local main = settings()
  if historyLoaded or not Conv.HistoryAllowed(main) then
    return 0
  end
  local archive = chat.Archive
  if archive and archive.Wanted() then
    -- The archive takes the old lines in (and writes them), once; before it is attached they wait.
    if not archive.Active() or archive.LegacyDone() then
      if archive.Active() then
        historyLoaded = true
      end
      return 0
    end
    archive.MarkLegacy()
  end
  historyLoaded = true
  local store = type(FG.db) == "table" and FG.db.chatWhispers or nil
  local contacts = type(store) == "table" and store.contacts
  if type(contacts) ~= "table" then
    return 0
  end
  refreshOwn()
  local keys = {}
  for key, contact in pairs(contacts) do
    if type(key) == "string" and type(contact) == "table" then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  local total = 0
  for _, key in ipairs(keys) do
    local contact = contacts[key]
    local target = { kind = "whisper", name = contact.name, homeRealm = ctx.homeRealm }
    local count = Conv.Import(chat.convs, target, contact.lines)
    if count > 0 then
      local conv = Conv.Get(chat.convs, Conv.Key("whisper", contact.name, ctx.homeRealm))
      if conv then
        Unread.MarkRead(conv)
      end
      total = total + count
    end
  end
  if total > 0 then
    FG.Emit("FG_CHAT_UPDATE", {}, Unread.Total(chat.convs))
  end
  return total
end

-- Switching ---------------------------------------------------------------------------------------------

-- The frame that holds the registrations, nil before the first start.
function Ingest.Frame()
  return frame
end

-- True for an ignored player of the game (the same check the intake uses).
Ingest.IsIgnored = isIgnored

function Ingest.IsRunning()
  return running
end

-- The add-on is loaded (this file runs) and switched on in the main add-on.
function Ingest.Wanted()
  local subs = FG.SubAddons
  return not halted and subs ~= nil and subs.State("chat") == "active"
end

-- Starts listening. False while the add-on is not active.
function Ingest.Start()
  if not Ingest.Wanted() then
    return false
  end
  if not running then
    running = true
    Ingest.Sync()
    Ingest.LoadHistory()
  end
  return true
end

-- Stops listening and takes every event off. With clear the memory is emptied too (history in the
-- SavedVariables stays untouched) and the next start reads the history again.
function Ingest.Stop(clear)
  running = false
  unregisterAll()
  dirty = {}
  if chat.Archive then
    if clear == true then
      chat.Archive.Reset()
    else
      chat.Archive.Refresh()
    end
  end
  if clear == true then
    Conv.Clear(chat.convs)
    historyLoaded, unreadCtx, unreadSig = false, nil, nil
    FG.Emit("FG_CHAT_UPDATE", {}, 0)
  end
end

-- Follows the switch of the main add-on: starts when it is on, stops when it went off.
function Ingest.Refresh()
  if Ingest.Wanted() then
    Ingest.Start()
  elseif running then
    Ingest.Stop()
  end
end

function Ingest.Status()
  local count = 0
  for _ in pairs(registered) do
    count = count + 1
  end
  return { running = running, halted = halted, events = count, lines = stats.lines, skipped = stats.skipped }
end

FG.On("FG_SUBADDON_CHANGED", function(_, id)
  if id == "chat" then
    Ingest.Refresh()
  end
end)

-- The history switch turned on while running: read the history once.
FG.On("FG_SETTING_CHANGED", function(_, path)
  if running and type(path) == "string" and path:find("^settings%.chat") then
    Ingest.LoadHistory()
  end
end)

-- The switches and the saved chats are in the store, which is read at ADDON_LOADED: the intake starts then.
FG.On("FG_CHAT_STORE_READY", function()
  if running then
    Ingest.Stop(true)
  end
  Ingest.Start()
end)
