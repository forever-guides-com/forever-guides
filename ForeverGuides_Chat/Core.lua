-- Forever Guides: Forever Chat (messenger). Core: the join with the main add-on, the check of the hook
-- version and the store of the add-on (ForeverGuidesChatDB). The add-on only exists while its switch is
-- on; everything it keeps stays on this PC and nothing is sent.
local ADDON_NAME, chat = ...

local FG = _G.ForeverGuides
local hook = FG and FG.ChatLauncher
-- A hook version this build does not know: stay silent, the main add-on keeps working.
if not (hook and hook.version == 1) then
  return
end
-- Not ours to run (switched off, built for another version): register nothing.
if not (FG.SubAddons and FG.SubAddons.Join("chat", ADDON_NAME)) then
  return
end
chat.FG, chat.hook, chat.name = FG, hook, ADDON_NAME

-- Store ---------------------------------------------------------------------------------------------
--   ForeverGuidesChatDB = { v = 2,
--     pins = { [key] = true },        conversations kept at the top of the list
--     muted = { [key] = true|time },  true: until the player ends it, a time (epoch seconds): until then
--     nicknames = { [key] = text },   own name for a conversation
--     notes = { [key] = text },       own note for a conversation
--     drafts = { [key] = text },      unsent input of a conversation
--     options = { mentionBreaksMute, channelMentionOnly, intake, localChat, keywords = { text, ... }, <id> = value },
--       intake: read the chat into the conversations (default on, the add-on itself is off by default)
--       localChat: also take say, yell and the emotes into the "local" conversation (default on)
--       <id>: the options of the settings registry (ChatSettingsLogic.lua), plain values only; the reader of
--       an option clamps it, Clean only keeps what is a boolean, a number or a short text
--     view = { mode, chats = { [key] = mode } },
--     sendWays = { build, ways = { [chat type] = { direct|secure|securekey = "ok"|"blocked" } } },
--       what the client allowed this add-on to send, per chat type, for one build (WayLogic.lua). A new build
--       starts empty.
--     teams = { v = 1, chars = { [character key] = { teams, history, counters, invites, blocked } } },
--     archive = { v = 1, legacy, chars = { [character "Name-Realm"] = section }, acct = section }
--       archive: the saved conversations (ChatArchiveLogic.lua has the format, ChatArchive.lua reads and writes it).
--       Whispers, groups, raid, guild, channels and "local" per character, Battle.net per account.
--       archive (default on), archiveDays (7, 30 or 90, default 30) and archivePublic (default on) are options. }
--       teams: the group chats of ChatTeams.lua, kept per character (a packet goes to one character). The
--       shape, the limits and the cleaning are in ChatTeamsLogic.lua (CleanStore).
-- The store is read at ADDON_LOADED (the game fills the SavedVariables only then); before that chat.db holds the
-- defaults, and it is filled in place, so references into it stay valid. FG_CHAT_STORE_READY announces it.
-- A key names one conversation ("whisper:" and the name in lower case, "party", "guild:<name>", see
-- ChatConversations.lua). Messages never land here, only these settings. Every list has a hard cap and every
-- text a length limit, so a hand edited file cannot grow the store.
-- Schema 2 added drafts, options and the times of muted. Schema 3 added teams. Schema 4 added archive and turns
-- the switches archive, intake and localChat on once (the add-on was not released with them off). Older data
-- stays valid, Clean lifts it.
local Store = {}
chat.Store = Store

Store.SCHEMA = 4
Store.KEY_BYTES = 96
Store.NICKNAME_BYTES = 48
Store.NOTE_BYTES = 1000
Store.DRAFT_BYTES = 1024
Store.KEYWORD_BYTES = 48
Store.MAX_KEYS = 200
Store.MAX_KEYWORDS = 20
Store.MAX_MUTE_TIME = 4102444800 -- the year 2100
Store.MAX_EXTRA_OPTIONS = 40
Store.EXTRA_KEY_BYTES = 32
Store.EXTRA_TEXT_BYTES = 64
Store.MODES = { "messenger", "compact", "mini" }
Store.DEFAULT_MODE = "messenger"

local function validMode(value)
  for _, mode in ipairs(Store.MODES) do
    if value == mode then
      return true
    end
  end
  return false
end

local function cutText(text, limit)
  return FG.ChatHistoryLimits.CutUtf8(text, limit)
end

function Store.New()
  return {
    v = Store.SCHEMA,
    pins = {},
    muted = {},
    nicknames = {},
    notes = {},
    drafts = {},
    options = { mentionBreaksMute = true, channelMentionOnly = true, intake = true, localChat = true, keywords = {} },
    view = { mode = Store.DEFAULT_MODE, chats = {} },
    teams = { v = 1, chars = {} },
    archive = { v = 1, chars = {} },
    sendWays = { ways = {} },
  }
end

local function validKey(key)
  return type(key) == "string" and key ~= "" and #key <= Store.KEY_BYTES
end

-- Keys of a table in a fixed order, so the cap keeps the same entries every time.
local function sortedKeys(raw)
  local keys = {}
  if type(raw) == "table" then
    for key in pairs(raw) do
      if validKey(key) then
        keys[#keys + 1] = key
      end
    end
  end
  table.sort(keys)
  return keys
end

-- accept(value, now) returns the cleaned value or nil to drop the entry.
local function cleanMap(raw, accept, now)
  local out, count = {}, 0
  for _, key in ipairs(sortedKeys(raw)) do
    if count >= Store.MAX_KEYS then
      break
    end
    local value = accept(raw[key], now)
    if value ~= nil then
      out[key] = value
      count = count + 1
    end
  end
  return out
end

local function acceptFlag(value)
  return value == true or nil
end

local function acceptText(limit)
  return function(value)
    if type(value) ~= "string" then
      return nil
    end
    value = cutText(value, limit)
    return value ~= "" and value or nil
  end
end

local function acceptMode(value)
  return validMode(value) and value or nil
end

-- true (no end) or a future time. A time that has passed is dropped when the clock is known.
local function acceptMute(value, now)
  if value == true then
    return true
  end
  if type(value) ~= "number" or value ~= value or value <= 0 then
    return nil
  end
  value = math.floor(math.min(value, Store.MAX_MUTE_TIME))
  if type(now) == "number" and value <= now then
    return nil
  end
  return value
end

local function trim(text)
  return (text:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", ""))
end

-- Words of the mention list: trimmed, cut, no empty or double entry (letter case blind), at most
-- MAX_KEYWORDS. The first entries win.
local function cleanKeywords(raw)
  local out, seen = {}, {}
  if type(raw) ~= "table" then
    return out
  end
  local fold = FG.LfgBrowseFilterLogic.Fold
  for i = 1, Store.MAX_KEYWORDS * 5 do
    if #out >= Store.MAX_KEYWORDS then
      break
    end
    local word = raw[i]
    if type(word) == "string" then
      word = trim(cutText(trim(word), Store.KEYWORD_BYTES))
      local folded = fold(word)
      if word ~= "" and not seen[folded] then
        seen[folded] = true
        out[#out + 1] = word
      end
    end
  end
  return out
end

local OWN_OPTIONS =
  { mentionBreaksMute = true, channelMentionOnly = true, intake = true, localChat = true, keywords = true }

-- The shape of the history only; the sections are cleaned when they are used (ChatArchiveLogic.lua), a full
-- copy of up to thousands of lines at every load would cost time for nothing.
local function shapeHistory(raw)
  if type(raw) ~= "table" or (type(raw.v) == "number" and raw.v > 1) then
    return { v = 1, chars = {} }
  end
  return {
    v = 1,
    legacy = raw.legacy == true or nil,
    chars = type(raw.chars) == "table" and raw.chars or {},
    acct = type(raw.acct) == "table" and raw.acct or nil,
  }
end

-- Plain values of options this file does not know (the registry of ChatSettingsLogic reads them clamped).
local function keepExtraOptions(raw, out)
  local count = 0
  for _, key in ipairs(sortedKeys(raw)) do
    local value = raw[key]
    local kind = type(value)
    if
      count < Store.MAX_EXTRA_OPTIONS
      and not OWN_OPTIONS[key]
      and #key <= Store.EXTRA_KEY_BYTES
      and key:find("^%a[%w_]*$")
      and (
        kind == "boolean"
        or (kind == "number" and value == value and value > -1e9 and value < 1e9)
        or (kind == "string" and #value <= Store.EXTRA_TEXT_BYTES)
      )
    then
      out[key] = value
      count = count + 1
    end
  end
end

local function flag(value, default)
  if type(value) == "boolean" then
    return value
  end
  return default
end

-- The teams section: the full check of ChatTeamsLogic (loaded before the store is read), the outer shape only
-- when that file is missing.
function Store.CleanTeams(raw, now)
  local logic = chat.TeamsLogic
  if logic then
    return logic.CleanStore(raw, now)
  end
  if type(raw) == "table" and type(raw.chars) == "table" then
    return { v = 1, chars = raw.chars }
  end
  return { v = 1, chars = {} }
end

-- A complete store from whatever SavedVariables hold: unknown keys dropped, wrong types gone, lists capped,
-- a schema 1 store lifted to the current one. now (epoch seconds, optional) drops mutes that have ended.
-- Never changes raw.
function Store.Clean(raw, now)
  local out = Store.New()
  if type(raw) ~= "table" then
    return out
  end
  out.pins = cleanMap(raw.pins, acceptFlag)
  out.muted = cleanMap(raw.muted, acceptMute, now)
  out.nicknames = cleanMap(raw.nicknames, acceptText(Store.NICKNAME_BYTES))
  out.notes = cleanMap(raw.notes, acceptText(Store.NOTE_BYTES))
  out.drafts = cleanMap(raw.drafts, acceptText(Store.DRAFT_BYTES))
  local options = type(raw.options) == "table" and raw.options or {}
  out.options.mentionBreaksMute = flag(options.mentionBreaksMute, true)
  out.options.channelMentionOnly = flag(options.channelMentionOnly, true)
  -- Before schema 4 nothing was saved; the switches of the messenger start on once for an existing store.
  local lift = type(raw.v) == "number" and raw.v < 4
  out.options.intake = lift or flag(options.intake, true)
  out.options.localChat = lift or flag(options.localChat, true)
  out.options.keywords = cleanKeywords(options.keywords)
  keepExtraOptions(options, out.options)
  local view = type(raw.view) == "table" and raw.view or {}
  out.view.mode = validMode(view.mode) and view.mode or Store.DEFAULT_MODE
  out.view.chats = cleanMap(view.chats, acceptMode)
  out.teams = Store.CleanTeams(raw.teams, now)
  out.archive = shapeHistory(raw.archive)
  out.sendWays = chat.WayLogic and chat.WayLogic.CleanMemory(raw.sendWays) or { ways = {} }
  if lift then
    out.options.archive = nil -- the default is on
  end
  return out
end

-- The store for the SavedVariables value: a store of a newer schema is not touched (status "future", the
-- add-on works on an empty copy that is never saved), anything else is replaced by a cleaned copy.
function Store.Load(raw, now)
  if type(raw) == "table" and type(raw.v) == "number" and raw.v > Store.SCHEMA then
    return Store.New(), "future"
  end
  return Store.Clean(raw, now), "ok"
end

-- The settings of one conversation by field. "modes" is the view of a single conversation (view.chats).
local ACCEPT = {
  pins = acceptFlag,
  muted = acceptMute,
  nicknames = acceptText(Store.NICKNAME_BYTES),
  notes = acceptText(Store.NOTE_BYTES),
  drafts = acceptText(Store.DRAFT_BYTES),
  modes = acceptMode,
}

local function container(db, field)
  if field == "modes" then
    return type(db.view) == "table" and db.view.chats or nil
  end
  return db[field]
end

local function countKeys(map)
  local count = 0
  for _ in pairs(map) do
    count = count + 1
  end
  return count
end

-- Sets (or with nil, false or "" removes) one setting of one conversation: Store.Set(db, "nicknames", key,
-- "Annie"). False for an unknown field, a bad key or value, or a full list; nothing changes then.
function Store.Set(db, field, key, value, now)
  local accept, map = ACCEPT[field], type(db) == "table" and container(db, field)
  if not accept or type(map) ~= "table" or not validKey(key) then
    return false
  end
  if value == nil or value == false or value == "" then
    map[key] = nil
    return true
  end
  local clean = accept(value, now)
  if clean == nil or (map[key] == nil and countKeys(map) >= Store.MAX_KEYS) then
    return false
  end
  map[key] = clean
  return true
end

-- Moves the settings of conversation from to conversation to (for merged conversations). What to has
-- stays, what only from has moves over, then from is gone.
function Store.Move(db, from, to)
  if type(db) ~= "table" or from == to then
    return
  end
  for field in pairs(ACCEPT) do
    local map = container(db, field)
    if type(map) == "table" then
      if map[from] ~= nil and map[to] == nil then
        Store.Set(db, field, to, map[from])
      end
      map[from] = nil
    end
  end
end

local function clock()
  local fn = rawget(_G, "time")
  return type(fn) == "function" and fn() or nil
end

-- Turns dst into a copy of src without replacing any table that dst already holds: a module that keeps a
-- sub-table of the store (the pins of the conversation state) keeps the live one.
function Store.Fill(dst, src)
  for key in pairs(dst) do
    if src[key] == nil then
      dst[key] = nil
    end
  end
  for key, value in pairs(src) do
    if type(value) == "table" and type(dst[key]) == "table" then
      Store.Fill(dst[key], value)
    else
      dst[key] = value
    end
  end
end

-- The game fills the SavedVariables after the files of an add-on ran and before its ADDON_LOADED, over whatever
-- a file put there. Until then the modules work on this store of defaults; ADDON_LOADED fills it with the saved
-- data in place (see loadStore).
chat.db, chat.status, chat.ready = Store.New(), "ok", false

-- Reads the saved data once. Anything that depends on the store follows FG_CHAT_STORE_READY.
local function loadStore()
  if chat.ready then
    return
  end
  chat.ready = true
  local loaded, status = Store.Load(rawget(_G, "ForeverGuidesChatDB"), clock())
  chat.status = status
  Store.Fill(chat.db, loaded)
  if status == "ok" then
    _G.ForeverGuidesChatDB = chat.db
  end
  FG.Emit("FG_CHAT_STORE_READY", status)
end

FG.On("ADDON_LOADED", function(_, name)
  if name == ADDON_NAME then
    FG.Safe("chat-store", loadStore)
  end
end)
-- A client that does not deliver the event of an add-on loaded late still has the saved data by the login.
FG.On("PLAYER_LOGIN", function()
  FG.Safe("chat-store", loadStore)
end)
