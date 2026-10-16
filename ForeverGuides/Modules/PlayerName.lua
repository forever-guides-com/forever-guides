-- Player names of Forever have a first name and an optional surname. The full
-- name is "<first><surname separator><surname>" (a space), a realm is appended
-- with "-". Everything that stores, compares, shows or sends a player name goes
-- through here, so a name is never treated as one whitespace-free token.
local _, ns = ...

local PN = {}
ns.PlayerName = PN

-- Per part (first name, surname, realm), in characters.
local MAX_PART = 24
PN.MAX_PART = MAX_PART

-- Pieces of a name that must survive the link encoding of chat links.
local ENCODED = { [" "] = "%20", [":"] = "%3A", ["|"] = "%7C", ["%"] = "%25" }

local function separators()
  local c = _G.Constants and _G.Constants.CharacterNameSeparatorConsts
  local surname = c and c.CHARACTERNAME_SURNAME_SEPARATOR
  local realm = c and c.CHARACTERNAME_REALMNAME_SEPARATOR
  return type(surname) == "string" and surname ~= "" and surname or " ",
    type(realm) == "string" and realm ~= "" and realm or "-"
end

-- Cuts `s` to at most `n` UTF-8 characters.
local function cutChars(s, n)
  local count = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then
      count = count + 1
      if count > n then
        return s:sub(1, i - 1)
      end
    end
  end
  return s
end

-- Letters of any script count (every byte of a multi-byte character is >= 0x80).
local function hasLetter(s)
  return s:find("[%a\128-\255]") ~= nil
end

-- Trims, turns every whitespace run into ONE surname separator, drops control
-- characters and pipes and caps every part. Realm "-" stays inside its part.
function PN.Clean(s)
  if type(s) ~= "string" then
    return ""
  end
  local sep, realmSep = separators()
  s = s:gsub("[%z\1-\8\14-\31\127|]", ""):gsub("%s+", " ")
  local parts = {}
  for token in s:gmatch("[^ ]+") do
    local name, realm = token, nil
    local at = token:find(realmSep, 1, true)
    if at then
      name, realm = token:sub(1, at - 1), token:sub(at + #realmSep)
    end
    name = cutChars(name, MAX_PART)
    if realm then
      name = name .. realmSep .. cutChars(realm, MAX_PART)
    end
    parts[#parts + 1] = name
  end
  return table.concat(parts, sep)
end

-- Full name from first name and optional surname.
function PN.Join(first, surname)
  first = PN.Clean(first)
  surname = PN.Clean(surname)
  if first == "" then
    return ""
  end
  if surname == "" then
    return first
  end
  local sep = separators()
  return first .. sep .. surname
end

-- first, surname (nil without one). Splits at the FIRST separator, and only
-- when both sides are plausible: letters on both sides and no realm in the
-- first part (so "Name-Realm" stays one first name with its realm).
function PN.Split(full)
  full = PN.Clean(full)
  if full == "" then
    return ""
  end
  local sep, realmSep = separators()
  local at = full:find(sep, 1, true)
  if not at then
    return full
  end
  local first, surname = full:sub(1, at - 1), full:sub(at + #sep)
  if first == "" or surname == "" or first:find(realmSep, 1, true) or not (hasLetter(first) and hasLetter(surname)) then
    return full
  end
  return first, surname
end

-- Own full name. Empty when the client does not know it yet.
function PN.Self()
  local ok, name, surname = pcall(UnitName, "player")
  if not ok or type(name) ~= "string" then
    return ""
  end
  return PN.Join(name, type(surname) == "string" and surname or nil)
end

-- Full name of a unit token, nil when the unit has no name.
function PN.Display(unit)
  local ok, name, surname = pcall(UnitName, unit)
  if not ok or type(name) ~= "string" or name == "" then
    return nil
  end
  return PN.Join(name, type(surname) == "string" and surname or nil)
end

-- First name and surname of the current target when it is a player, else nil.
function PN.Target()
  local exists, isPlayer = _G.UnitExists, _G.UnitIsPlayer
  if not (exists and isPlayer) then
    return nil
  end
  local okE, there = pcall(exists, "target")
  local okP, player = pcall(isPlayer, "target")
  if not (okE and okP and there and player) then
    return nil
  end
  local ok, name, surname = pcall(UnitName, "target")
  if not ok or type(name) ~= "string" or name == "" then
    return nil
  end
  local first, rest = PN.Split(PN.Join(name, type(surname) == "string" and surname or nil))
  return first, rest
end

-- Own realm is dropped, chat names carry a realm only for other realms.
function PN.Normalize(full)
  full = PN.Clean(full)
  local ok, realm = pcall(GetNormalizedRealmName)
  local _, realmSep = separators()
  if ok and type(realm) == "string" and realm ~= "" then
    local tail = realmSep .. realm
    if #full > #tail and full:sub(-#tail) == tail then
      return full:sub(1, -#tail - 1)
    end
  end
  return full
end

-- Lowercase for the ASCII range and the Latin-1 letters (a Lua lower() only knows ASCII).
local function lower(s)
  s = s:lower()
  return (
    s:gsub("\195([\128-\158])", function(b)
      if b == "\151" then
        return nil
      end
      return "\195" .. string.char(b:byte() + 32)
    end)
  )
end

PN.Lower = lower
PN.Cut = cutChars

-- Case-insensitive comparison key, "" for an empty name.
function PN.Key(full)
  return lower(PN.Normalize(full))
end

function PN.Equal(a, b)
  local ka = PN.Key(a)
  return ka ~= "" and ka == PN.Key(b)
end

-- The string for SendChatMessage / SendAddonMessage as the target of a whisper:
-- the full name with the surname separator, the realm appended with "-".
function PN.ForWhisper(first, surname, realm)
  local full = PN.Join(first, surname)
  if full == "" then
    return ""
  end
  local _, realmSep = separators()
  realm = type(realm) == "string" and realm:gsub("[%c|%s]", "") or ""
  if realm ~= "" and not full:find(realmSep, 1, true) then
    full = full .. realmSep .. cutChars(realm, MAX_PART)
  end
  return full
end

-- Letters per part of a name that can be whispered.
PN.MIN_LETTERS = 2

-- Characters (not bytes) of a string of letters.
local function charCount(s)
  return select(2, s:gsub("[^\128-\191]", ""))
end

-- A name part: letters with an apostrophe or hyphen only between letters.
local function plausiblePart(part)
  if part:find("^[%-']") or part:find("[%-']$") or part:find("[%-'][%-']") then
    return false
  end
  local letters = part:gsub("[%-']", "")
  return letters:find("^[%a\128-\255]+$") ~= nil and charCount(letters) >= PN.MIN_LETTERS
end

-- Whether `full` can be the target of a whisper: exactly "<first> <surname>", each
-- part with at least two letters, the surname with an optional "-<realm>" behind it.
-- Returns true, or false and why: "missing" (one part only), "extra" (more than two
-- parts) or "invalid" (too short or a character that is no letter). Nothing is
-- completed or guessed here.
function PN.CheckWhisper(full)
  full = PN.Clean(full)
  local sep, realmSep = separators()
  local parts = {}
  local from = 1
  while true do
    local at = full:find(sep, from, true)
    parts[#parts + 1] = full:sub(from, (at or #full + 1) - 1)
    if not at then
      break
    end
    from = at + #sep
  end
  if full == "" or #parts < 2 then
    return false, "missing"
  elseif #parts > 2 then
    return false, "extra"
  end
  local surname, realm = parts[2], nil
  local at = surname:find(realmSep, 1, true)
  if at then
    surname, realm = surname:sub(1, at - 1), parts[2]:sub(at + #realmSep)
  end
  if realm and not realm:find("^[%w\128-\255'%-]+$") then
    return false, "invalid"
  end
  if not (plausiblePart(parts[1]) and plausiblePart(surname)) then
    return false, "invalid"
  end
  return true
end

-- Link payload field: spaces, colons, pipes and percent signs become %XX, so a
-- name with a surname cannot break the colon separated link parsing.
function PN.Encode(name)
  name = type(name) == "string" and name:gsub("%c", "") or ""
  return (name:gsub("[ :|%%]", ENCODED))
end

-- Reverse of Encode. Only the four escapes Encode makes are decoded, so links
-- written before the encoding existed (plain names) read back unchanged.
function PN.Decode(field)
  if type(field) ~= "string" then
    return ""
  end
  return (
    field:gsub("%%(%x%x)", function(hex)
      local c = string.char(tonumber(hex, 16))
      if ENCODED[c] and ENCODED[c]:upper() == "%" .. hex:upper() then
        return c
      end
    end)
  )
end
