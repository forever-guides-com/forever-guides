-- Rules of the chat name (ChatName.lua): the name a player puts in front of their own chat messages, written
-- as "(Name): " into the text before the game sends it. No game calls here.
-- Everything in this file decides on plain strings and tables: what a name may contain, how the prefix looks,
-- which texts never get one, in which chat the prefix is set, when the add-on has to keep its hands off the
-- text (restrictions of the client) and how the prefix of a received line is colored.
local _, ns = ...

local CNL = {}
ns.ChatNameLogic = CNL

-- "none" writes "Name: " without brackets. It is last so the older choices keep their place in the list.
CNL.STYLES = { "round", "square", "angle", "none" }
CNL.MATCH_MODES = { "off", "starts", "contains", "ends" }
-- The switches of the profile, in the order of the settings card.
CNL.GROUPS = { "guild", "party", "dungeon", "raid", "battleground", "arena", "world", "community" }

-- Braces stay out of the choice: the game reads {rt1} style tokens in chat text as raid markers.
local PAIRS = {
  round = { "(", ")" },
  square = { "[", "]" },
  angle = { "<", ">" },
  none = { "", "" },
}

CNL.MAX_CHARS = 24
CNL.MAX_BYTES = 48
-- Longest message the game accepts, in bytes.
CNL.MAX_MESSAGE_BYTES = 255
-- Names that stay in the profile after a change, so a prefix in the input history can still be recognized.
CNL.MAX_RECENT = 4
CNL.MAX_CUSTOM_BYTES = 200
CNL.MAX_CUSTOM_ENTRIES = 12
-- A text that starts with one of these (after blanks) is a command, a macro line or a marker of another add-on.
CNL.COMMAND_LEADS = "/!#@?"
-- Community channels carry this word in front of their name (measure M9 of the specification confirms it).
CNL.COMMUNITY_PREFIX = "community:"
-- Folder names of add-ons that set a name in front of chat text as well (two prefixes in a row would look wrong).
-- Empty until a measurement in the game shows a clash.
CNL.CONFLICT_ADDONS = {}

-- Text ------------------------------------------------------------------------------------------------

-- One UTF-8 character at byte i: its code point and the index after it, nil for a malformed sequence.
local function decode(s, i)
  local b = s:byte(i)
  if b < 0x80 then
    return b, i + 1
  end
  local extra, cp
  if b >= 0xC2 and b <= 0xDF then
    extra, cp = 1, b - 0xC0
  elseif b >= 0xE0 and b <= 0xEF then
    extra, cp = 2, b - 0xE0
  elseif b >= 0xF0 and b <= 0xF4 then
    extra, cp = 3, b - 0xF0
  else
    return nil
  end
  for k = 1, extra do
    local c = s:byte(i + k)
    if not c or c < 0x80 or c > 0xBF then
      return nil
    end
    cp = cp * 64 + (c - 0x80)
  end
  if (extra == 2 and cp < 0x800) or (extra == 3 and (cp < 0x10000 or cp > 0x10FFFF)) then
    return nil
  end
  if cp >= 0xD800 and cp <= 0xDFFF then
    return nil
  end
  return cp, i + extra + 1
end

-- Control characters, blanks other than the plain space and characters that draw nothing.
local function invisible(cp)
  return cp < 0x20
    or (cp >= 0x7F and cp <= 0xA0)
    or cp == 0xAD
    or cp == 0x1680
    or (cp >= 0x2000 and cp <= 0x200F)
    or (cp >= 0x2028 and cp <= 0x202F)
    or (cp >= 0x205F and cp <= 0x206F)
    or cp == 0x3000
    or (cp >= 0xFE00 and cp <= 0xFE0F)
    or cp == 0xFEFF
    or (cp >= 0xFFF0 and cp <= 0xFFFF)
    or (cp >= 0xE0000 and cp <= 0xE007F)
end

-- ASCII symbols a name may keep next to letters, digits and the blank.
local SYMBOLS = ".-_'+~*^"

-- Why a code point is not allowed in a name, nil when it is.
local function refusal(cp)
  if cp == 0x7C then
    return "pipe"
  elseif cp < 0x80 then
    local ch = string.char(cp)
    if ch:find("[%(%)%[%]<>{}]") then
      return "brackets"
    elseif ch:find("[%w ]") or SYMBOLS:find(ch, 1, true) then
      return nil
    end
    return invisible(cp) and "control" or "symbol"
  elseif invisible(cp) then
    return "control"
  end
  return nil
end

-- The name made safe and the first reason it was changed ("pipe", "brackets", "control", "symbol", "invalid" for a
-- malformed byte sequence, "long"), nil when nothing was. The text is never longer than MAX_CHARS characters
-- and MAX_BYTES bytes, has no blank at the edges and no double blank. Not a string gives "".
function CNL.CheckName(raw)
  if type(raw) ~= "string" then
    return ""
  end
  local out, bytes, chars, err = {}, 0, 0, nil
  local i = 1
  while i <= #raw do
    local cp, nxt = decode(raw, i)
    if not cp then
      err = err or "invalid"
      i = i + 1
    else
      local piece = raw:sub(i, nxt - 1)
      local why = refusal(cp)
      if why then
        err = err or why
      elseif piece ~= " " or (#out > 0 and out[#out] ~= " ") then
        -- a leading or doubled blank is dropped without a message
        if chars + 1 > CNL.MAX_CHARS or bytes + #piece > CNL.MAX_BYTES then
          err = err or "long"
          break
        end
        out[#out + 1] = piece
        chars, bytes = chars + 1, bytes + #piece
      end
      i = nxt
    end
  end
  while out[#out] == " " do
    out[#out] = nil
  end
  return table.concat(out), err
end

-- The prefix for a name: "(Name): ", or "Name: " in the style "none". Empty for a name that is empty or not safe as it stands, so a hand edited
-- saved variable never puts a pipe or a bracket into a message.
function CNL.Prefix(name, style)
  local clean, err = CNL.CheckName(name)
  if clean == "" or err or clean ~= name then
    return ""
  end
  local pair = PAIRS[style] or PAIRS.round
  return pair[1] .. clean .. pair[2] .. ": "
end

-- Why a text never gets a prefix, nil when it may: "unreadable" (not a string), "empty", "command".
function CNL.SkipText(text)
  if type(text) ~= "string" then
    return "unreadable"
  end
  local lead = text:match("^%s*(%S)")
  if not lead then
    return "empty"
  end
  if CNL.COMMAND_LEADS:find(lead, 1, true) then
    return "command"
  end
  return nil
end

local function startsWith(text, head)
  return head ~= "" and text:sub(1, #head) == head
end

-- Every prefix the add-on may have written in front of a text: the current one first, then the recent names in
-- each style. Prefixes that cannot be built (unsafe name) are left out. The bracket-less form "Name: " is the one
-- case where a prefix looks like ordinary text, so it is only known for the exact name the player has chosen as the
-- style "none" or for a recent name (an earlier alias of the player). Any other "Word: " is never taken for a prefix.
function CNL.KnownPrefixes(name, style, recent)
  local out, seen = {}, {}
  local function add(prefix)
    if prefix ~= "" and not seen[prefix] then
      seen[prefix] = true
      out[#out + 1] = prefix
    end
  end
  add(CNL.Prefix(name, style))
  for _, old in ipairs(recent or {}) do
    for _, st in ipairs(CNL.STYLES) do
      add(CNL.Prefix(old, st))
    end
  end
  for _, st in ipairs(CNL.STYLES) do
    if st ~= "none" or style == "none" then
      add(CNL.Prefix(name, st))
    end
  end
  return out
end

-- The text with the prefix in front, without a check of the length, nil when nothing changes. Second result: "set" or
-- "replaced" (an older prefix of the same player, found in the input history, was swapped for the current one) on
-- success, else the reason: "no name", "unreadable", "empty", "command", "has prefix". known: result of
-- KnownPrefixes. A sender that cuts long texts into parts (Forever Chat) calls this one and counts the bytes itself.
function CNL.Build(text, prefix, known)
  if prefix == "" then
    return nil, "no name"
  end
  local skip = CNL.SkipText(text)
  if skip then
    return nil, skip
  end
  if startsWith(text, prefix) then
    return nil, "has prefix"
  end
  local body, how = text, "set"
  for _, old in ipairs(known or {}) do
    if old ~= prefix and startsWith(text, old) then
      body, how = text:sub(#old + 1), "replaced"
      break
    end
  end
  if CNL.SkipText(body) then
    return nil, CNL.SkipText(body)
  end
  return prefix .. body, how
end

-- Build for one message of at most MAX_MESSAGE_BYTES bytes (the chat input field of the game): the reason "too long"
-- when the prefix would push the text over the limit.
function CNL.Compose(text, prefix, known)
  local out, how = CNL.Build(text, prefix, known)
  if out and #out > CNL.MAX_MESSAGE_BYTES then
    return nil, "too long"
  end
  return out, how
end

-- The text without a prefix of the player at its start, nil when there is none or nothing would be left.
function CNL.Strip(text, known)
  if type(text) ~= "string" then
    return nil
  end
  for _, prefix in ipairs(known or {}) do
    if startsWith(text, prefix) and #text > #prefix then
      return text:sub(#prefix + 1)
    end
  end
  return nil
end

-- Names ---------------------------------------------------------------------------------------------------

-- Upper to lower case for the Latin-1 letters and the capitals of the game's other scripts that string.lower
-- leaves alone, keyed by their two UTF-8 bytes. ASCII goes through a table because string.lower follows the
-- locale of the process.
local FOLD = {}
local function fold(lead, from, to, targetLead, shift)
  for byte = from, to do
    FOLD[string.char(lead, byte)] = string.char(targetLead, byte + shift)
  end
end
fold(195, 128, 150, 195, 32)
fold(195, 152, 158, 195, 32)
fold(208, 128, 143, 209, 16)
fold(208, 144, 159, 208, 32)
fold(208, 160, 175, 209, -32)
local LOWER = {}
for byte = 65, 90 do
  LOWER[string.char(byte)] = string.char(byte + 32)
end

function CNL.Fold(value)
  return (value:gsub("[A-Z]", LOWER):gsub("[\195\208][\128-\191]", FOLD))
end

-- True when the chosen name makes the prefix pointless because it says what the character name already says.
-- mode: "off" (equal names only), "starts", "contains", "ends" (the character name begins with, contains or ends
-- on the chosen name). characters: the names of the own character (full name and first name).
function CNL.SameName(name, characters, mode)
  if type(name) ~= "string" or name == "" then
    return false
  end
  local mine = CNL.Fold(name)
  for _, character in ipairs(characters or {}) do
    if type(character) == "string" and character ~= "" then
      local other = CNL.Fold(character)
      if other == mine then
        return true
      elseif mode == "starts" and other:sub(1, #mine) == mine then
        return true
      elseif mode == "ends" and #other >= #mine and other:sub(-#mine) == mine then
        return true
      elseif mode == "contains" and other:find(mine, 1, true) then
        return true
      end
    end
  end
  return false
end

-- Places ------------------------------------------------------------------------------------------------

-- The entries of a comma list of channel names: trimmed, without empty and doubled entries, at most
-- MAX_CUSTOM_ENTRIES, in the order typed.
function CNL.ParseChannels(text)
  local out, seen = {}, {}
  if type(text) ~= "string" then
    return out
  end
  for entry in text:gmatch("[^,]+") do
    entry = entry:match("^%s*(.-)%s*$")
    local key = CNL.Fold(entry)
    if entry ~= "" and not seen[key] then
      seen[key] = true
      out[#out + 1] = entry
      if #out >= CNL.MAX_CUSTOM_ENTRIES then
        break
      end
    end
  end
  return out
end

-- The list text as it is kept: cleaned entries joined with ", ", cut to MAX_CUSTOM_BYTES at an entry.
function CNL.CleanChannels(text)
  local kept, size = {}, 0
  for _, entry in ipairs(CNL.ParseChannels(text)) do
    size = size + #entry + (#kept > 0 and 2 or 0)
    if size > CNL.MAX_CUSTOM_BYTES then
      break
    end
    kept[#kept + 1] = entry
  end
  return table.concat(kept, ", ")
end

function CNL.ChannelListed(text, channel)
  if type(channel) ~= "string" or channel == "" then
    return false
  end
  local key = CNL.Fold(channel)
  for _, entry in ipairs(CNL.ParseChannels(text)) do
    if CNL.Fold(entry) == key then
      return true
    end
  end
  return false
end

function CNL.IsCommunity(chatType, channel)
  if chatType == "COMMUNITIES_CHANNEL" then
    return true
  end
  return type(channel) == "string" and CNL.Fold(channel):sub(1, #CNL.COMMUNITY_PREFIX) == CNL.COMMUNITY_PREFIX
end

-- The switch that decides for one chat, nil when this chat never gets a prefix (second result: why).
-- ctx.chatType: the chat type of the input field, ctx.instance: kind of instance the player is in ("party",
-- "raid", "pvp", "arena", "scenario", "none"; unknown counts as "none"), ctx.channel: name of the channel.
function CNL.GroupFor(ctx)
  local t, where = ctx.chatType, ctx.instance
  if t == "GUILD" or t == "OFFICER" then
    return "guild"
  elseif t == "PARTY" then
    if where == "pvp" or where == "arena" then
      return nil, "pvp party"
    end
    return where == "party" and "dungeon" or "party"
  elseif t == "RAID" then
    return "raid"
  elseif t == "INSTANCE_CHAT" then
    if where == "party" then
      return "dungeon"
    elseif where == "raid" then
      return "raid"
    elseif where == "pvp" then
      return "battleground"
    elseif where == "arena" then
      return "arena"
    end
    return nil, "no instance group"
  elseif t == "CHANNEL" or t == "COMMUNITIES_CHANNEL" then
    if CNL.IsCommunity(t, ctx.channel) then
      return "community"
    end
    return "world"
  end
  return nil, "unsupported chat"
end

-- Whether a prefix is set in this chat. Returns true, the switch, or false and the reason.
-- profile.channels holds the switches by group, profile.custom the list of channel names.
function CNL.Allowed(profile, ctx)
  local group, why = CNL.GroupFor(ctx)
  if not group then
    return false, why
  end
  local channels = type(profile.channels) == "table" and profile.channels or {}
  if group == "world" and CNL.ChannelListed(profile.custom, ctx.channel) then
    return true, "custom"
  end
  if channels[group] == true then
    return true, group
  end
  return false, group .. " off"
end

-- Restrictions ------------------------------------------------------------------------------------------

-- Restriction kinds of the client by number (0, combat, is no chat restriction and is left out).
CNL.RESTRICTION_KINDS = { "encounter", "challenge", "pvp", "map", "chat" }

-- Why the add-on keeps its hands off the text right now, nil when it may work. facts: lockdown (the client locks
-- the chat messaging), kinds ([1] to [5]: that kind of restriction is active), hasKinds (the client can tell),
-- secret (an answer was a secret value), instance (kind of instance, used when the client cannot tell).
function CNL.PauseReason(facts)
  if facts.lockdown == true then
    return "lockdown"
  elseif facts.secret == true then
    return "unknown"
  end
  if facts.hasKinds then
    for kind, name in ipairs(CNL.RESTRICTION_KINDS) do
      if (facts.kinds or {})[kind] == true then
        return name
      end
    end
    return nil
  end
  if facts.instance == "pvp" or facts.instance == "arena" then
    return "pvp"
  end
  return nil
end

-- Received lines -------------------------------------------------------------------------------------------

local OPENERS = { ["("] = ")", ["["] = "]", ["<"] = ">" }

-- The start of a received text as { open, name, close, colon, rest } when it has the shape "(Name): ..." (the
-- same kind of bracket on both sides, no bracket or pipe inside the name), nil otherwise.
function CNL.ParseLead(text)
  if type(text) ~= "string" then
    return nil
  end
  local open, name, close, colon, rest = text:match("^([%(%[<])([^%(%)%[%]<>{}|:]+)([%)%]>])( ?:)( .*)$")
  if not open or OPENERS[open] ~= close or #name > CNL.MAX_BYTES then
    return nil
  end
  return { open = open, name = name, close = close, colon = colon, rest = rest }
end

-- The start of a received text as { name, rest } when it has the bracket-less shape "Name: ..." (one word without
-- blanks that is a valid name, a colon, a blank), nil otherwise. The shape alone proves nothing, ordinary text has
-- it too: the caller must know the name as a player before it colors anything.
function CNL.ParsePlainLead(text)
  if type(text) ~= "string" then
    return nil
  end
  local name, rest = text:match("^([^%s:]+):( .*)$")
  if not name or #name > CNL.MAX_BYTES then
    return nil
  end
  local clean, err = CNL.CheckName(name)
  if err or clean ~= name then
    return nil
  end
  return { name = name, rest = rest }
end

local function linear(c)
  return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end

-- Contrast of a color against black, the darkest chat background (1 to 21).
function CNL.Contrast(r, g, b)
  return (0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) + 0.05) / 0.05
end

CNL.MIN_CONTRAST = 4.5

-- The color as a hex text "rrggbb", mixed with white step by step until it reaches the contrast of the
-- guideline for text on a dark chat window.
function CNL.ReadableHex(r, g, b)
  local function clamp(v)
    v = tonumber(v) or 0
    return v ~= v and 0 or math.max(0, math.min(1, v))
  end
  r, g, b = clamp(r), clamp(g), clamp(b)
  local mix = 0
  while CNL.Contrast(r + (1 - r) * mix, g + (1 - g) * mix, b + (1 - b) * mix) < CNL.MIN_CONTRAST and mix < 1 do
    mix = mix + 0.05
  end
  local function byte(v)
    return math.floor((v + (1 - v) * mix) * 255 + 0.5)
  end
  return string.format("%02x%02x%02x", byte(r), byte(g), byte(b))
end

-- The received text with the name in the color, nil when the text has no prefix shape or the hex is not valid.
function CNL.Colorize(text, hex)
  local lead = CNL.ParseLead(text)
  if not lead or type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") then
    return nil
  end
  return lead.open .. "|cff" .. hex .. lead.name .. "|r" .. lead.close .. lead.colon .. lead.rest
end

-- The bracket-less text with the name in the color, nil when the text has no such shape or the hex is not valid.
function CNL.ColorizePlain(text, hex)
  local lead = CNL.ParsePlainLead(text)
  if not lead or type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") then
    return nil
  end
  return "|cff" .. hex .. lead.name .. "|r:" .. lead.rest
end

-- Status -------------------------------------------------------------------------------------------------

-- Why nothing happens or only some of it, as an ordered list of { key, argument } (the key is the end of
-- "chatname.status.<key>"; the settings card turns each into a line). facts: enabled, name (the saved name),
-- nameError (reason CheckName gave for the saved name, nil when it is fine), anyPlace (at least one chat is on),
-- hidden (the name equals the character name), pause (PauseReason), off (switched off after errors), conflicts
-- (names of other add-ons with the same purpose).
function CNL.Status(facts)
  local out = {}
  if facts.off then
    out[#out + 1] = { "off" }
    return out
  end
  if not facts.enabled then
    out[#out + 1] = { "disabled" }
    return out
  end
  if facts.name == nil or facts.name == "" then
    out[#out + 1] = { "noName" }
  elseif facts.nameError then
    out[#out + 1] = { "badName", facts.nameError }
  elseif facts.hidden then
    out[#out + 1] = { "hidden" }
  end
  if not facts.anyPlace then
    out[#out + 1] = { "noPlace" }
  end
  if facts.pause then
    out[#out + 1] = { "paused", facts.pause }
  end
  if #(facts.conflicts or {}) > 0 then
    out[#out + 1] = { "conflict", table.concat(facts.conflicts, ", ") }
  end
  if #out == 0 then
    out[1] = { "active" }
  end
  return out
end
