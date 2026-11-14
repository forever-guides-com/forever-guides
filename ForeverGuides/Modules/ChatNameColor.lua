-- Colored display of a received chat name: a line that starts with "(Name): " shows the name in the class color of
-- the sender. With the style "none" (prefix "Name: ") a line is only colored when the word before the colon is the
-- name of a player the client knows (group, guild roster, friends), in the class color of that player.
-- Only the display on this screen changes, nothing is sent and the sender needs no add-on.
-- Opt-in per profile (classColor). The message filters of the game are registered only while it is on. A line or
-- a sender that is a secret value is left alone, and so is a line without the shape or a sender whose class is
-- unknown. Only the chats in which the chat name can be set are filtered, whispers, say and yell never.
-- Three errors take the filters out again.
local _, ns = ...
local CNL, Guard, CN = ns.ChatNameLogic, ns.AutoGuard, ns.ChatName

local CC = {}
ns.ChatNameColor = CC

CC.MAX_ERRORS = 3
CC.EVENTS = {
  "CHAT_MSG_GUILD",
  "CHAT_MSG_OFFICER",
  "CHAT_MSG_PARTY",
  "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_CHANNEL",
  "CHAT_MSG_COMMUNITIES_CHANNEL",
}
-- Position of the player GUID among the arguments after the sender (the twelfth of the event).
CC.GUID_AT = 10

local errors, installed = 0, false

local function g(name)
  return rawget(_G, name)
end

-- The GUID of the sender: the expected position first, then the last argument that looks like a player GUID.
local function guidOf(...)
  local guid = Guard.Safe((select(CC.GUID_AT, ...)))
  if type(guid) == "string" and guid:find("^Player%-") then
    return guid
  end
  for i = select("#", ...), 1, -1 do
    local value = Guard.Safe((select(i, ...)))
    if type(value) == "string" and value:find("^Player%-") then
      return value
    end
  end
end

-- English class token of the sender: through the GUID, else through the name when the sender is a unit the
-- client can resolve (group, nearby).
local function classOf(author, ...)
  local guid = guidOf(...)
  local info = g("GetPlayerInfoByGUID")
  if guid and type(info) == "function" then
    local ok, _, class = pcall(info, guid)
    class = ok and Guard.Safe(class) or nil
    if type(class) == "string" then
      return class
    end
  end
  local short, unitClass = g("Ambiguate"), g("UnitClass")
  if type(short) == "function" and type(unitClass) == "function" then
    local ok, name = pcall(short, author, "none")
    if ok and type(name) == "string" then
      local okClass, _, class = pcall(unitClass, name)
      class = okClass and Guard.Safe(class) or nil
      if type(class) == "string" then
        return class
      end
    end
  end
end

-- Hex color of a class token: a class color add-on first, then the colors of the game, lightened for the chat.
function CC.HexFor(class)
  local custom, stock = g("CUSTOM_CLASS_COLORS"), g("RAID_CLASS_COLORS")
  local color = (type(custom) == "table" and custom[class]) or (type(stock) == "table" and stock[class]) or nil
  if type(color) ~= "table" then
    return nil
  end
  return CNL.ReadableHex(color.r, color.g, color.b)
end

-- Lower-case short name of a player name ("Ana-Realm" gives "ana"), "" when it is not a string.
local function shortKey(name)
  if type(name) ~= "string" then
    return ""
  end
  return CNL.Fold((name:gsub("%-.*$", "")))
end

-- Guild roster by short name, rebuilt whenever the cached snapshot of the roster is a new table.
local rosterOf, rosterMap
-- The snapshot is read once per frame: the filter runs for every line and every chat window of the game.
local snapTime, snapOk, snapValue

local function snapshot()
  local now = g("GetTime")
  now = type(now) == "function" and now() or nil
  if now == nil or now ~= snapTime then
    local data = ns.GuildData
    snapOk, snapValue = pcall(function()
      return data and data.Get()
    end)
    snapTime = now
  end
  return snapOk, snapValue
end

local function guildClass(key)
  local ok, snap = snapshot()
  if not ok or type(snap) ~= "table" or type(snap.members) ~= "table" then
    return nil
  end
  if rosterOf ~= snap then
    rosterOf, rosterMap = snap, {}
    for _, m in ipairs(snap.members) do
      local k = shortKey(m.name)
      if k ~= "" and type(m.class) == "string" and m.class ~= "" then
        rosterMap[k] = rosterMap[k] or m.class
      end
    end
  end
  return rosterMap[key]
end

-- Class token of a friend: the friend list gives the localized class name only.
local function friendClass(name)
  local list = g("C_FriendList")
  if type(list) ~= "table" or type(list.GetFriendInfo) ~= "function" then
    return nil
  end
  local ok, info = pcall(list.GetFriendInfo, name)
  local className = ok and type(info) == "table" and Guard.Safe(info.className) or nil
  if type(className) ~= "string" then
    return nil
  end
  for _, names in ipairs({ g("LOCALIZED_CLASS_NAMES_MALE"), g("LOCALIZED_CLASS_NAMES_FEMALE") }) do
    for token, localized in pairs(type(names) == "table" and names or {}) do
      if localized == className then
        return token
      end
    end
  end
end

-- English class token of a player the client knows by name: a unit it can resolve (group, target), the guild
-- roster or the friend list. nil for every other word, so ordinary text before a colon is never colored.
local function knownClass(name)
  local key = shortKey(name)
  if key == "" then
    return nil
  end
  local short, unitClass = g("Ambiguate"), g("UnitClass")
  if type(short) == "function" and type(unitClass) == "function" then
    local ok, unit = pcall(short, name, "none")
    if ok and type(unit) == "string" then
      local okClass, _, class = pcall(unitClass, unit)
      class = okClass and Guard.Safe(class) or nil
      if type(class) == "string" then
        return class
      end
    end
  end
  return guildClass(key) or friendClass(name)
end

-- The text with the name colored, nil when nothing changes. plain: the profile uses the style "none", so the
-- shape "Name: " counts too.
local function recolor(msg, author, plain, ...)
  msg, author = Guard.Safe(msg), Guard.Safe(author)
  if type(msg) ~= "string" or type(author) ~= "string" then
    return nil
  end
  if CNL.ParseLead(msg) then
    local class = classOf(author, ...)
    local hex = class and CC.HexFor(class)
    return hex and CNL.Colorize(msg, hex) or nil
  end
  local lead = plain and CNL.ParsePlainLead(msg)
  if not lead then
    return nil
  end
  local class = knownClass(lead.name)
  local hex = class and CC.HexFor(class)
  return hex and CNL.ColorizePlain(msg, hex) or nil
end

-- The filter of the game: (frame, event, text, sender, ...) gives false (show the line) and the changed text.
function CC.Filter(_, _, msg, author, ...)
  local profile = CN.Profile()
  if not profile or profile.classColor ~= true then
    return false
  end
  local ok, colored = pcall(recolor, msg, author, profile.style == "none", ...)
  if not ok then
    errors = errors + 1
    ns.Log.warn("chatname color: %s", tostring(colored))
    if errors >= CC.MAX_ERRORS then
      CC.Uninstall()
    end
    return false
  end
  if colored then
    return false, colored, author, ...
  end
  return false
end

function CC.Install()
  local add = g("ChatFrame_AddMessageEventFilter")
  if installed or type(add) ~= "function" then
    return
  end
  installed = true
  for _, event in ipairs(CC.EVENTS) do
    pcall(add, event, CC.Filter)
  end
end

function CC.Uninstall()
  local remove = g("ChatFrame_RemoveMessageEventFilter")
  if not installed then
    return
  end
  installed = false
  if type(remove) == "function" then
    for _, event in ipairs(CC.EVENTS) do
      pcall(remove, event, CC.Filter)
    end
  end
end

function CC.Installed()
  return installed
end

-- Installed exactly while the profile in use asks for the color and errors have not taken it out.
function CC.Refresh()
  local profile = CN.Profile()
  local on = profile ~= nil and profile.classColor == true and errors < CC.MAX_ERRORS
  if on then
    CC.Install()
  else
    CC.Uninstall()
  end
end

ns.On("PLAYER_LOGIN", CC.Refresh)
ns.On("FG_SETTING_CHANGED", function(_, path, value, scope)
  if type(path) ~= "string" then
    return
  end
  if (scope == "char" and path:find("^chatName")) or path:find("^settings%.chatName") then
    if value == true and path:find("classColor$") then
      errors = 0
    end
    CC.Refresh()
  end
end)
