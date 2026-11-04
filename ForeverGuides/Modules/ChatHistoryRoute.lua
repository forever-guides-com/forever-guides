-- Chat history, routing: which chat event is which stored type, and which chat windows show a message.
-- Pure: the game side describes the windows, this module decides. No game access.
--
-- A window description is { id, name, active, excluded, messageTypes, channelList, zoneChannelList }:
-- the lists are the ones of the chat frame (messageTypeList, channelList, zoneChannelList), excluded
-- marks the combat log and temporary windows, active is false for a closed window.
local _, ns = ...

local Logic = ns.ChatHistoryLogic

local Route = {}
ns.ChatHistoryRoute = Route

-- type: key of ChatHistoryLogic.TYPES. group: the message group a chat window lists the event under.
-- plain: no sender in the stored line (the text names the player itself). dir: whisper direction.
Route.EVENTS = {
  CHAT_MSG_SAY = { type = "say", group = "SAY" },
  CHAT_MSG_YELL = { type = "yell", group = "YELL" },
  CHAT_MSG_PARTY = { type = "party", group = "PARTY" },
  CHAT_MSG_PARTY_LEADER = { type = "party", group = "PARTY_LEADER" },
  CHAT_MSG_RAID = { type = "raid", group = "RAID" },
  CHAT_MSG_RAID_LEADER = { type = "raid", group = "RAID_LEADER" },
  CHAT_MSG_RAID_WARNING = { type = "raid", group = "RAID_WARNING" },
  CHAT_MSG_GUILD = { type = "guild", group = "GUILD" },
  CHAT_MSG_OFFICER = { type = "officer", group = "OFFICER" },
  CHAT_MSG_CHANNEL = { type = "channel", group = "CHANNEL" },
  CHAT_MSG_EMOTE = { type = "emote", group = "EMOTE" },
  CHAT_MSG_TEXT_EMOTE = { type = "emote", group = "EMOTE", plain = true },
  CHAT_MSG_SYSTEM = { type = "system", group = "SYSTEM", plain = true },
  CHAT_MSG_WHISPER = { type = "whisper", dir = Logic.DIR_IN },
  CHAT_MSG_WHISPER_INFORM = { type = "whisper", dir = Logic.DIR_OUT },
}

-- Registration order, fixed so the event list is the same in every session.
Route.ORDER = {}
for event in pairs(Route.EVENTS) do
  Route.ORDER[#Route.ORDER + 1] = event
end
table.sort(Route.ORDER)

-- Window that takes a message when the windows cannot be told apart.
Route.DEFAULT_WINDOW = 1

-- The stored type id of an event, nil for an event that is not recorded.
function Route.TypeId(event)
  local entry = Route.EVENTS[event]
  return entry and Logic.TYPES[entry.type] or nil
end

local function listed(list, value)
  for i = 1, #list do
    if list[i] == value then
      return true
    end
  end
  return false
end

-- Same rule as the client's chat frame: a channel message belongs to a window that lists the channel
-- by its base name (case blind) or by its zone channel id.
local function showsChannel(window, channelName, zoneChannelId)
  local names, zones = window.channelList, window.zoneChannelList
  if type(names) ~= "table" then
    return nil
  end
  local wanted = type(channelName) == "string" and channelName:lower() or nil
  for index, name in pairs(names) do
    if type(name) == "string" and wanted and name:lower() == wanted then
      return true
    end
    if type(zones) == "table" and type(zoneChannelId) == "number" and zoneChannelId > 0 then
      if zones[index] == zoneChannelId then
        return true
      end
    end
  end
  return false
end

local function fallbackWindows()
  return { { id = Route.DEFAULT_WINDOW, name = "" } }
end

-- true, false, or nil when the window does not say.
local function shows(window, entry, group, channelName, zoneChannelId)
  if entry.group == "CHANNEL" then
    return showsChannel(window, channelName, zoneChannelId)
  end
  if type(window.messageTypes) ~= "table" then
    return nil
  end
  return listed(window.messageTypes, group)
end

-- The windows that show the event: { { id, name }, ... }. A window the client shows the message in is
-- in the list; combat log, temporary and closed windows never are. groups (optional) is the client's
-- event to group table. When a window cannot say what it shows, the default window takes the message;
-- the same when there is no window description at all. Whisper events belong to no window.
function Route.Windows(event, windows, channelName, zoneChannelId, groups)
  local entry = Route.EVENTS[event]
  if not entry or entry.dir then
    return {}
  end
  if type(windows) ~= "table" or #windows == 0 then
    return fallbackWindows()
  end
  local group = type(groups) == "table" and type(groups[event]) == "string" and groups[event] or entry.group
  local out = {}
  for i = 1, #windows do
    local window = windows[i]
    if type(window) == "table" and not window.excluded and window.active ~= false then
      local answer = shows(window, entry, group, channelName, zoneChannelId)
      if answer == nil then
        return fallbackWindows()
      elseif answer then
        out[#out + 1] = { id = window.id, name = window.name or "" }
      end
    end
  end
  return out
end
