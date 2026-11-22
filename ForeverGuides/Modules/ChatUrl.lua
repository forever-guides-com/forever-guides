-- Clickable web addresses in chat. Display only: a chat filter turns every address of an incoming or shown
-- line into a local link, nothing is sent and nothing is opened. A click shows the copy window (W.OpenUrl):
-- the address is selected, Ctrl+C copies it, Esc closes.
--   Detection: ChatUrlLogic.lua. The link carries only a number "addon:FGUrl:<key>:<n>", the address sits in
--   a ring table of the last 200 (":" and "|" cannot travel inside a link). The key is per session, so a link
--   text pasted by another player does nothing.
--   Order: the filters are added at PLAYER_LOGIN, after every filter that rewrites a line (page links, notes,
--   drawings, talents), so those links are finished and protected when this one reads the line.
--   The guild message of the day: the client prints it from GUILD_MOTD straight into the chat frames, not as a
--   CHAT_MSG_* line, so the filters never see it (/fg dev chatprobe motd measures that on the live client). No
--   AddMessage hook (every chat line of every frame would pass our code, and a hook on that path can taint) and no
--   replaced Blizzard function: on GUILD_MOTD and at login the text is read and, when it holds addresses, one extra
--   local line lists them as links (display only).
-- Switch: settings.chatUrl (default on), card on the tab Chat name (ChatUrlSettings.lua).
local _, ns = ...
local CUL = ns.ChatUrlLogic

ns.AddLocale("enUS", { ["chaturl.motd"] = "Guild message of the day: addresses %s" })
ns.AddLocale("deDE", { ["chaturl.motd"] = "Gildennachricht: Adressen %s" })

local CU = {}
ns.ChatUrl = CU

local COLOR = "6cb8ff"
local LINK = "FGUrl"

local KEY = (function()
  local chars = {}
  for i = 1, 10 do
    chars[i] = string.char(96 + math.random(26))
  end
  return table.concat(chars)
end)()

local ring = CUL.NewRing(CUL.RING)
CU.ring = ring

function CU.Enabled()
  local settings = ns.db and ns.db.settings
  return not settings or settings.chatUrl ~= false
end

local function localLink(url)
  return string.format("|cff%s|Haddon:%s:%s:%d|h[%s]|h|r", COLOR, LINK, KEY, ring:Add(url), url)
end

-- The line with its addresses as local links, nil when there is nothing to change.
function CU.Rewrite(msg)
  if not CU.Enabled() then
    return nil
  end
  return CUL.Rewrite(msg, function(url)
    local guard = ns.AutoGuard
    local safe = guard and guard.Safe(url)
    return type(safe) == "string" and localLink(safe) or nil
  end)
end

-- Every line event we already filter elsewhere, plus system lines, emotes and Battle.net whispers.
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
  "SYSTEM",
  "EMOTE",
  "BN_WHISPER",
  "BN_WHISPER_INFORM",
}
CU.EVENTS = CHAT_EVENTS

local function chatFilter(_, _, msg, ...)
  local guard = ns.AutoGuard
  local text = guard and guard.Safe(msg)
  if type(text) ~= "string" then
    return false
  end
  local ok, out = pcall(CU.Rewrite, text)
  if ok and out then
    return false, out, ...
  end
  return false
end
CU.Filter = chatFilter

-- A click on a local link: "addon:FGUrl:<key>:<n>". Unknown numbers and foreign keys do nothing.
function CU.OnLink(link)
  local guard = ns.AutoGuard
  if guard then
    link = guard.Safe(link)
  end
  if type(link) ~= "string" then
    return
  end
  local key, n = link:match("^addon:" .. LINK .. ":([^:]+):(%d+)$")
  local url = key == KEY and ring:Get(tonumber(n)) or nil
  if url and ns.W and ns.W.OpenUrl then
    ns.W.OpenUrl(url)
  end
end

-- Before CommandHelp in the toc: test doubles keep only the last SetItemRef hook.
if hooksecurefunc then
  pcall(hooksecurefunc, "SetItemRef", ns.Wrap("chaturl-click", CU.OnLink))
end

-- Guild message of the day ------------------------------------------------------------------------------

local MOTD_REPEAT = 60
local lastMotd, lastMotdAt

local function safeText(value)
  local guard = ns.AutoGuard
  local text = guard and guard.Safe(value)
  return type(text) == "string" and text or nil
end

-- The text of the message of the day as the game holds it right now, nil when there is none.
function CU.ReadMotd()
  local info = rawget(_G, "C_GuildInfo")
  local read = type(info) == "table" and info.GetMOTD or rawget(_G, "GetGuildRosterMOTD")
  if type(read) ~= "function" then
    return nil
  end
  local ok, text = pcall(read)
  return ok and safeText(text) or nil
end

-- The extra chat line with the addresses of a message of the day, nil without an address or with the switch off.
function CU.MotdLine(text)
  text = safeText(text)
  if not (text and CU.Enabled()) then
    return nil
  end
  local links = {}
  for _, url in ipairs(CUL.Urls(text)) do
    local safe = safeText(url)
    if safe then
      links[#links + 1] = localLink(safe)
    end
  end
  if #links == 0 then
    return nil
  end
  return string.format(ns.L["chaturl.motd"], table.concat(links, " "))
end

-- The client may print the message at login and again on GUILD_MOTD, the same text counts once.
function CU.ShowMotd(text)
  local line = text and text ~= "" and CU.MotdLine(text)
  if not line then
    return false
  end
  local now = GetTime and GetTime() or 0
  if text == lastMotd and lastMotdAt and now - lastMotdAt < MOTD_REPEAT then
    return false
  end
  lastMotd, lastMotdAt = text, now
  ns.Notify.chat(line)
  return true
end

ns.On("GUILD_MOTD", function(_, text)
  CU.ShowMotd(safeText(text) or CU.ReadMotd())
end)

ns.On("PLAYER_LOGIN", function()
  CU.ShowMotd(CU.ReadMotd())
  if ChatFrame_AddMessageEventFilter then
    for _, name in ipairs(CHAT_EVENTS) do
      pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_" .. name, chatFilter)
    end
  end
end)
