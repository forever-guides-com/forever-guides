-- Forever Chat, opening the window by itself (game access): a new line of a kind whose switch is on (whisper,
-- group, raid, guild, channel; all off by default) shows the window on that chat. The rules are in
-- ChatOpenLogic.lua. It never takes the keyboard focus (the input line stays as it is, Enter stays with the
-- game chat) and never opens over an open window. It opens in combat too (the window is made of plain frames).
-- A window the player closed stays closed until a chat begins. Nothing here sends anything or touches the chat of the game.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local OL = chat.OpenLogic

local AutoOpen = {}
chat.AutoOpen = AutoOpen

local state = OL.NewState()
local watching = {}

local function options()
  local db = chat.db
  return type(db) == "table" and type(db.options) == "table" and db.options or {}
end

local function restricted()
  local ok, value = pcall(chat.Send.Restricted)
  return ok and value == true
end

-- The facts of the game for OpenLogic.
local function gameState()
  return {
    running = chat.Ingest ~= nil and chat.Ingest.IsRunning(),
    restricted = restricted(),
    shown = chat.Window.IsShown(),
    dismissed = state.dismissed,
  }
end

-- Called when the window is built: a hide of the window is the player's decision (Esc, the close button, the key).
function AutoOpen.Watch(frame)
  if type(frame) ~= "table" or watching[frame] or type(frame.HookScript) ~= "function" then
    return
  end
  watching[frame] = true
  frame:HookScript("OnHide", function()
    state.dismissed = true
  end)
end

-- Opens the window on the chat of a candidate without moving the focus. True when it opened.
local function open(cand)
  if not chat.Hooks.OpenFor(cand.key) then
    return false
  end
  state.dismissed = false
  return true
end

-- Decides for a candidate { key, kind, fresh }. True when the window opened.
function AutoOpen.Consider(cand)
  if OL.ShouldOpen(options(), cand, gameState()) then
    return open(cand)
  end
  return false
end

-- New lines in the conversations of the set keys (FG_CHAT_UPDATE, through ChatHooks.lua).
function AutoOpen.OnUpdate(keys)
  AutoOpen.Watch(chat.Window.Frame())
  local cand = OL.Track(state, chat.convs, keys, FG.ChatHistoryLogic.DIR_IN)
  if cand then
    return AutoOpen.Consider(cand)
  end
  return false
end

OL.Seed(state, chat.convs)

-- The main add-on and the tests reach the parts through the handlers the window registered.
local api = chat.hook.Api and chat.hook.Api()
if type(api) == "table" then
  api.AutoOpen, api.OpenLogic = AutoOpen, OL
end
local settings = chat.Settings
if type(settings) == "table" and type(settings.AddOption) == "function" then
  for _, def in ipairs(OL.OPTIONS) do
    local copy = {}
    for k, v in pairs(def) do
      copy[k] = v
    end
    pcall(settings.AddOption, copy)
  end
end
