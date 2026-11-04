-- Forever Chat, the join with the chat of the game (game access): the answer action, the hint about other chat
-- add-ons, the entries of the settings page and the hand over of new lines to the automatic opening
-- (ChatAutoOpen.lua). Everything is a switch that is off by default (see HooksLogic.DEFAULTS), nothing here
-- changes the chat of the game: no hook, no filter (those are in ChatFilters.lua) and the edit box of the game
-- is never touched. Opening reacts to FG_CHAT_UPDATE of the input, not to raw events, and never takes the
-- keyboard focus. Only the answer action (a key press of the player) puts the focus into the input line.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local HL = chat.HooksLogic
local L = FG.L

local Hooks = {}
chat.Hooks = Hooks

local track = HL.NewState()
local hinted = false

local function global(name)
  return rawget(_G, name)
end

local function options()
  local db = chat.db
  return type(db) == "table" and type(db.options) == "table" and db.options or {}
end

-- Other chat add-ons ------------------------------------------------------------------------------------

local function parentOf(frame)
  if type(frame) ~= "table" or type(frame.GetParent) ~= "function" then
    return nil
  end
  local ok, parent = pcall(frame.GetParent, frame)
  return ok and parent or nil
end

-- What the standard chat windows look like now. A value that cannot be told stays nil.
function Hooks.Facts()
  local facts = {}
  local first, second, root = global("ChatFrame1"), global("ChatFrame2"), global("UIParent")
  local parent = parentOf(first)
  if parent and root then
    facts.parentIsRoot = parent == root
  end
  local edit = type(first) == "table" and (first.editBox or global("ChatFrame1EditBox")) or nil
  local editParent = parentOf(edit)
  if editParent then
    facts.editInFrame = editParent == first
  end
  local badge = FG.ChatBadge
  local ours = badge and badge.Wrapped
  if
    type(first) == "table"
    and type(second) == "table"
    and type(first.AddMessage) == "function"
    and type(second.AddMessage) == "function"
    and not (ours and (ours(first) or ours(second)))
  then
    facts.differs = first.AddMessage ~= second.AddMessage
  end
  return facts
end

-- Reasons (see HooksLogic.Foreign) why another add-on seems to have rebuilt the chat windows, empty for none.
function Hooks.Foreign()
  return HL.Foreign(Hooks.Facts())
end

-- One hint per session, only while a switch that touches the game chat is on. Nothing is switched off.
function Hooks.MaybeHint()
  if hinted or not HL.HintWanted(options()) then
    return false
  end
  hinted = true
  if #Hooks.Foreign() == 0 then
    return false
  end
  FG.Notify(L["chat.hooks.otherAddons"], "warning")
  return true
end

-- Opening and answering ---------------------------------------------------------------------------------

-- Shows the window on the conversation without moving the focus. False when the window did not open.
function Hooks.OpenFor(key)
  local frame = chat.Open()
  if not frame then
    return false
  end
  chat.SelectConversation(key)
  return true
end

-- The input told that conversations changed: remembers the whisper to answer and lets the automatic opening
-- (ChatAutoOpen.lua) look at the new lines. True when the window opened.
function Hooks.OnUpdate(keys)
  HL.Track(track, chat.convs, keys, FG.ChatHistoryLogic.DIR_IN)
  Hooks.MaybeHint()
  return chat.AutoOpen ~= nil and chat.AutoOpen.OnUpdate(keys) or false
end

-- The key of the whisper to answer, nil while none came in.
function Hooks.ReplyKey()
  return HL.ReplyKey(track, chat.convs)
end

-- The answer action (key or command): the window on the last whisper, the focus in the input line. Without a
-- whisper the window opens as it is and a line says so. Returns true and the key, or false.
function Hooks.Reply()
  local key = Hooks.ReplyKey()
  local frame = chat.Open()
  if not frame then
    return false
  end
  if not key then
    FG.Notify.chat(L["chat.hooks.noReply"])
    return false
  end
  chat.SelectConversation(key)
  chat.Window.inputFocus()
  return true, key
end
chat.Reply = Hooks.Reply

-- The main add-on's launcher calls the answer action through the handlers the window registered.
local api = chat.hook.Api and chat.hook.Api()
if type(api) == "table" then
  api.Reply = Hooks.Reply
  api.Hooks = Hooks
  api.HooksLogic = HL
end

-- Settings page --------------------------------------------------------------------------------------------

-- Gives the switches to the settings registry when the page exists. Returns the number registered.
function Hooks.RegisterOptions()
  local settings = chat.Settings
  if type(settings) ~= "table" or type(settings.AddOption) ~= "function" then
    return 0
  end
  local count = 0
  for _, def in ipairs(HL.OPTIONS) do
    local copy = {}
    for k, v in pairs(def) do
      copy[k] = v
    end
    if pcall(settings.AddOption, copy) then
      count = count + 1
    end
  end
  return count
end

FG.On("FG_CHAT_UPDATE", function(_, keys)
  FG.Safe("chathooks", Hooks.OnUpdate, keys)
end)

HL.Seed(track, chat.convs)
Hooks.RegisterOptions()
