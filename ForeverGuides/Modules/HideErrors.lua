-- Hides Blizzard's red error text on screen (settings.hideErrors, off by default), for example "Out of
-- range". Route with the least taint: UIErrorsFrame stops listening to UI_ERROR_MESSAGE and our own
-- listener shows the messages that stay (settings.hideErrorsKeep: bag full, quest log full, not
-- enough gold) through UIErrorsFrame:AddMessage. No Blizzard function or table is replaced, hooked or
-- written, so no taint reaches the frame's code; alpha or a hook would also catch the yellow info
-- lines. Switching off, or three errors, listen again.
local _, ns = ...
local Guard = ns.AutoGuard

local H = {}
ns.HideErrors = H

local ID = "hideErrors"
local EVENT = "UI_ERROR_MESSAGE"
-- Blizzard's color of an error line.
local RED = { 1, 0.1, 0.1, 1 }
-- Global strings of the messages that stay visible.
local KEEP_NAMES = { "ERR_INV_FULL", "ERR_QUEST_LOG_FULL", "ERR_ITEM_MAX_COUNT", "ERR_NOT_ENOUGH_MONEY" }

local state = { detached = false }

local function frame()
  local f = rawget(_G, "UIErrorsFrame")
  if type(f) == "table" and type(f.UnregisterEvent) == "function" and type(f.RegisterEvent) == "function" then
    return f
  end
end

-- Messages that stay, by exact text of the client language.
local function kept(message)
  for _, name in ipairs(KEEP_NAMES) do
    if rawget(_G, name) == message then
      return true
    end
  end
  return false
end

-- Moves the event between Blizzard's frame and us, as the setting says.
function H.Apply()
  local f = frame()
  if not f then
    return false
  end
  local wanted = Guard.On(ID)
  if wanted == state.detached then
    return wanted
  end
  local ok = pcall(wanted and f.UnregisterEvent or f.RegisterEvent, f, EVENT)
  if ok then
    state.detached = wanted
  end
  return state.detached
end

function H.Detached()
  return state.detached
end

-- The message is the first string among the arguments, the error type is a number.
local function messageOf(...)
  for i = 1, select("#", ...) do
    local value = Guard.Safe((select(i, ...)))
    if type(value) == "string" then
      return value
    end
  end
end

function H.OnError(...)
  local f = frame()
  if not (state.detached and f and ns.db.settings.hideErrorsKeep ~= false) then
    return
  end
  local message = messageOf(...)
  if message and kept(message) and type(f.AddMessage) == "function" then
    f:AddMessage(message, unpack(RED))
  end
end

ns.On(EVENT, function(_, ...)
  if state.detached then
    Guard.Run(ID, H.OnError, ...)
  end
end)

ns.On("PLAYER_LOGIN", function()
  ns.Safe(ID, H.Apply)
end)

ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings." .. ID then
    ns.Safe(ID, H.Apply)
  end
end)
