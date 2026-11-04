-- Forever Chat, the filter of the game chat (pure, no game access): which events are filtered, what a filter
-- may read from the arguments of an event and when errors switch it off. The decision whether a line goes
-- is HooksLogic.ShouldHide, the game access is in ChatFilters.lua.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local FL = {}
chat.FiltersLogic = FL

-- The events of whispers the messenger takes in: incoming and the echo of an outgoing one.
FL.EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" }
-- Errors in the filter after which it stays off for the session.
FL.MAX_ERRORS = 3

-- What a filter may read: text (argument 1) and partner (argument 2). safe is AutoGuard.Safe, so a secret
-- value never gets compared. Returns readable (both are plain, non-empty strings) and the partner name.
function FL.Read(safe, args)
  if type(safe) ~= "function" or type(args) ~= "table" then
    return false, nil
  end
  local text, sender = safe(args[1]), safe(args[2])
  if type(text) ~= "string" or text == "" or type(sender) ~= "string" or sender == "" then
    return false, nil
  end
  return true, sender
end

-- Counts one error. Returns the new count and true once the filter has to go off.
function FL.Failed(count)
  count = (type(count) == "number" and count or 0) + 1
  return count, count >= FL.MAX_ERRORS
end
