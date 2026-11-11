-- Profile of the chat name (ChatName.lua) without game calls: the shape of the saved table, its repair and the
-- choice between the profile of the account and the profile of one character.
-- The account profile lives in settings.chatName. A character that deviates has a full copy in its own table
-- (ForeverGuidesCharDB.chatName), taken from the account profile the moment the player asks for it; the other
-- characters keep following the account. Removing the copy returns the character to the account profile.
local _, ns = ...
local U, CNL = ns.U, ns.ChatNameLogic

local P = {}
ns.ChatNameProfile = P

P.VERSION = 1

local function oneOf(list, value, default)
  for _, item in ipairs(list) do
    if item == value then
      return value
    end
  end
  return default
end

-- A fresh default profile: everything off, nothing chosen.
function P.Defaults()
  local channels = {}
  for _, group in ipairs(CNL.GROUPS) do
    channels[group] = false
  end
  return {
    v = P.VERSION,
    enabled = false,
    name = "",
    style = "round",
    classColor = false,
    hideSame = true,
    match = "off",
    channels = channels,
    custom = "",
    recent = {},
  }
end

-- A saved profile repaired: every field has its type and a known value, the name is made safe, the lists are cut.
-- Unknown fields are dropped. Not a table gives the defaults.
function P.Clean(raw)
  local d = P.Defaults()
  if type(raw) ~= "table" then
    return d
  end
  local name = CNL.CheckName(raw.name)
  local channels = {}
  local saved = type(raw.channels) == "table" and raw.channels or {}
  for _, group in ipairs(CNL.GROUPS) do
    channels[group] = saved[group] == true
  end
  local recent = {}
  for _, old in ipairs(type(raw.recent) == "table" and raw.recent or {}) do
    local clean, bad = CNL.CheckName(old)
    if clean ~= "" and not bad and clean ~= name and #recent < CNL.MAX_RECENT then
      local dup = false
      for _, have in ipairs(recent) do
        dup = dup or have == clean
      end
      if not dup then
        recent[#recent + 1] = clean
      end
    end
  end
  return {
    v = P.VERSION,
    enabled = raw.enabled == true,
    name = name,
    style = oneOf(CNL.STYLES, raw.style, d.style),
    classColor = raw.classColor == true,
    hideSame = raw.hideSame ~= false,
    match = oneOf(CNL.MATCH_MODES, raw.match, d.match),
    channels = channels,
    custom = CNL.CleanChannels(raw.custom),
    recent = recent,
  }
end

-- Repairs both stores in place (account.settings.chatName, char.chatName). A missing character profile stays
-- missing: absence means "follow the account".
function P.CleanStores(account, char)
  if type(account) == "table" and type(account.settings) == "table" and account.settings.chatName ~= nil then
    account.settings.chatName = P.Clean(account.settings.chatName)
  end
  if type(char) == "table" and char.chatName ~= nil then
    char.chatName = P.Clean(char.chatName)
  end
end

-- The profile in use and where it lives: the table of the character when it has one, else the account profile.
-- Returns profile, scope ("character" or "account"). Nil when neither store has a table.
function P.Active(account, char)
  if type(char) == "table" and type(char.chatName) == "table" then
    return char.chatName, "character"
  end
  local settings = type(account) == "table" and account.settings
  if type(settings) == "table" and type(settings.chatName) == "table" then
    return settings.chatName, "account"
  end
  return nil
end

-- The character gets its own profile as a repaired copy of the account profile (or the defaults). Does nothing
-- when it has one. Returns the profile of the character.
function P.UseCharacter(account, char)
  if type(char.chatName) == "table" then
    return char.chatName
  end
  local settings = type(account) == "table" and account.settings
  local source = type(settings) == "table" and settings.chatName or nil
  char.chatName = P.Clean(U.copy(source))
  return char.chatName
end

-- The character follows the account profile again; its own copy is deleted.
function P.UseAccount(char)
  char.chatName = nil
end

-- A name change: the old name is remembered (newest first, doubles and the new name left out), so the prefix
-- it left in the input history can still be found and replaced. Returns the new list of recent names.
function P.Remember(recent, oldName, newName)
  local out = {}
  local function add(name)
    if type(name) == "string" and name ~= "" and name ~= newName then
      for _, have in ipairs(out) do
        if have == name then
          return
        end
      end
      out[#out + 1] = name
    end
  end
  add(oldName)
  for _, name in ipairs(recent or {}) do
    add(name)
  end
  while #out > CNL.MAX_RECENT do
    out[#out] = nil
  end
  return out
end
