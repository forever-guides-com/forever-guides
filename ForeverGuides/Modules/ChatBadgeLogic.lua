-- Rules of the chat badge (ChatBadge.lua): which chat lines get the badge, where it is set and the sizes.
-- The text of a message is never touched: the badge goes in front of the player link of the sender, once.
-- No game calls here. A secret value (Retail 12) is handed back as nothing, so the line stays as it is.
local _, ns = ...

local CBL = {}
ns.ChatBadgeLogic = CBL

-- Chat groups of the settings, in the order of the settings page.
CBL.CHANNELS = { "guild", "party", "raid", "instance", "whisper", "say", "channel" }
-- Whispers stay off until chosen: they are private and often the only line of a window.
CBL.DEFAULT_CHANNELS = {
  guild = true,
  party = true,
  raid = true,
  instance = true,
  whisper = false,
  say = true,
  channel = true,
}

-- Third field of the player link (the chat group the game wrote) to the group of the settings.
local GROUP_OF = {
  GUILD = "guild",
  OFFICER = "guild",
  PARTY = "party",
  PARTY_LEADER = "party",
  PARTY_GUIDE = "party",
  RAID = "raid",
  RAID_LEADER = "raid",
  RAID_WARNING = "raid",
  INSTANCE_CHAT = "instance",
  INSTANCE_CHAT_LEADER = "instance",
  WHISPER = "whisper",
  WHISPER_INFORM = "whisper",
  SAY = "say",
  YELL = "say",
  EMOTE = "say",
  TEXT_EMOTE = "say",
  CHANNEL = "channel",
  COMMUNITIES_CHANNEL = "channel",
}

-- Spellings that mark a line that already carries a badge: texture path of BadgeAssets, text tag, and the
-- guild and community logos (texture folder, hover link).
local MARKS = {
  "AddOns\\ForeverGuides\\Media\\Badge",
  "AddOns\\ForeverGuides\\Media\\Crests",
  "|Haddon:ForeverGuides:crest:",
  "[FG]",
}

CBL.MIN_HEIGHT = 10
CBL.MAX_HEIGHT = 24
CBL.DEFAULT_HEIGHT = 14

-- Settings --------------------------------------------------------------------------------------------

function CBL.CleanStyle(style)
  if style == "text" or style == "both" then
    return style
  end
  return "icon"
end

-- 0 = follow the font size of the chat window, else the pixel height from 10 to 24.
function CBL.CleanSize(size)
  size = tonumber(size)
  if not size or size ~= size or size < 1 then
    return 0
  end
  return math.max(CBL.MIN_HEIGHT, math.min(CBL.MAX_HEIGHT, math.floor(size + 0.5)))
end

-- Pixel height of the badge: the setting, else the font size of the window, else the default.
function CBL.Height(size, fontSize)
  local fixed = CBL.CleanSize(size)
  if fixed > 0 then
    return fixed
  end
  fontSize = tonumber(fontSize)
  if not fontSize or fontSize ~= fontSize or fontSize < 1 then
    return CBL.DEFAULT_HEIGHT
  end
  return math.max(CBL.MIN_HEIGHT, math.min(CBL.MAX_HEIGHT, math.floor(fontSize + 0.5)))
end

-- A group that the table does not mention counts as its default.
function CBL.ChannelOn(channels, group)
  local default = CBL.DEFAULT_CHANNELS[group]
  if default == nil then
    return false
  end
  if type(channels) == "table" and type(channels[group]) == "boolean" then
    return channels[group]
  end
  return default
end

-- Lines -----------------------------------------------------------------------------------------------

-- The first player link of a line: { at, name, group } (at: where the link starts, group: the chat group of
-- the settings or nil for a link of a system line, a loot line and the like), nil without a link.
function CBL.Parse(text)
  if type(text) ~= "string" then
    return nil
  end
  local at, _, data = text:find("|Hplayer:([^|]*)|h")
  if not at then
    return nil
  end
  local fields, n = {}, 0
  for field in (data .. ":"):gmatch("([^:]*):") do
    n = n + 1
    fields[n] = field
  end
  if fields[1] == "" then
    return nil
  end
  return { at = at, name = fields[1], group = GROUP_OF[(fields[3] or ""):upper()] }
end

-- True when the text before the link already shows a badge.
function CBL.HasBadge(before)
  for _, mark in ipairs(MARKS) do
    if before:find(mark, 1, true) then
      return true
    end
  end
  return false
end

-- Where the badge goes: in front of a color start that directly precedes the link, so the color of the
-- name stays whole.
local function insertAt(text, at)
  if at > 10 and text:sub(at - 10, at - 1):find("^|c%x%x%x%x%x%x%x%x$") then
    return at - 10
  end
  return at
end

-- The line with the badge set in, nil when nothing changes. opts: safe(value) (the value or nil when it is
-- secret), channels (settings table), badge(name, group) (badge markup or "" for this player). On nil the second
-- result says why ("no link", "no group" for a link of a system line, "channel off", "has badge", "no logo") and
-- the third is the parsed link (name, group) when there was one.
function CBL.Rewrite(text, opts)
  if opts.safe then
    text = opts.safe(text)
  end
  local info = CBL.Parse(text)
  if not info then
    return nil, "no link"
  elseif not info.group then
    return nil, "no group", info
  elseif not CBL.ChannelOn(opts.channels, info.group) then
    return nil, "channel off", info
  end
  local at = insertAt(text, info.at)
  if CBL.HasBadge(text:sub(1, at - 1)) then
    return nil, "has badge", info
  end
  local badge = opts.badge(info.name, info.group)
  if type(badge) ~= "string" or badge == "" then
    return nil, "no logo", info
  end
  return text:sub(1, at - 1) .. badge .. " " .. text:sub(at)
end

-- The chat groups of the settings that are switched off, in the order of the settings page.
function CBL.ChannelsOff(channels)
  local out = {}
  for _, group in ipairs(CBL.CHANNELS) do
    if not CBL.ChannelOn(channels, group) then
      out[#out + 1] = group
    end
  end
  return out
end

-- Status ------------------------------------------------------------------------------------------------

-- Why the chat shows no logo or only some, as an ordered list of { key, argument } (the key is the end of
-- "chatbadge.status.<key>"; the settings card turns it into a line). facts: off (switched off after errors),
-- forever (the add-on logo is on), crests (the number of guild and community logos per line, 0 for none),
-- crestSource (receiving them or the local recognition is on), crestLocal, directory (entries of the logo list),
-- blockers (names of other chat add-ons that keep the logo away), heard (add-on users in the register), sending
-- (false while the own logo is shared with nobody, so nobody sees it; nil when unknown), switch (the display
-- switch settings.chatBadge) and listening (the receive consent of the presence mark): receiving with the switch
-- off is the one state that has to say so, the add-on logo is read and never shown. localState ("unread" while the
-- guild roster was not read yet, "noGuild" when the game names no guild, nil otherwise), channelsOff (the chat
-- groups of the settings that are switched off) and skins (chat add-ons that draw the chat in a window of their
-- own) add lines.
function CBL.Status(facts)
  if facts.off then
    return { { "off" } }
  end
  local crests = (tonumber(facts.crests) or 0) > 0
  local out = {}
  if facts.switch == false and facts.listening == true then
    out[1] = { "switchOff" }
  end
  if not facts.forever and not crests then
    out[#out + 1] = { facts.crestLocal and "noCount" or "idle" }
    return out
  elseif not facts.forever and not facts.crestSource then
    out[#out + 1] = { "noSource" }
    return out
  end
  if #(facts.blockers or {}) > 0 then
    out[#out + 1] = { "other", table.concat(facts.blockers, ", ") }
  end
  if facts.forever then
    out[#out + 1] = { "heard", tonumber(facts.heard) or 0 }
  end
  if facts.sending == false then
    out[#out + 1] = { "noSend" }
  end
  if not crests then
    out[#out + 1] = { "noCount" }
  elseif not facts.crestSource then
    out[#out + 1] = { "noSource" }
  else
    if (tonumber(facts.directory) or 0) == 0 then
      out[#out + 1] = { facts.crestLocal and "emptyLocal" or "emptyList" }
    end
    if facts.crestLocal and facts.localState then
      out[#out + 1] = { facts.localState == "unread" and "localUnread" or "localNoGuild" }
    end
  end
  if #(facts.channelsOff or {}) > 0 then
    out[#out + 1] = { "channelsOff", table.concat(facts.channelsOff, ",") }
  end
  if #(facts.skins or {}) > 0 then
    out[#out + 1] = { "skin", table.concat(facts.skins, ", ") }
  end
  return out
end
