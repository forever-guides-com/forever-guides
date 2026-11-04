-- Pure rules of the guild invite request (InvitePrompt.lua, InviteKey.lua): the choice of the look, the keys
-- that may confirm an invite and the countdown. No game calls.
local _, ns = ...

local PL = {}
ns.InvitePromptLogic = PL

-- "window": one small window per request. "bar": a single line at the top.
PL.STYLES, PL.DEFAULT_STYLE = { "window", "bar" }, "window"

-- The look for a stored value. Numbers are the values of earlier versions: 1 was the bar, 2 and 3 (card, chat
-- line with symbol) are replaced by the window. Anything else is the default.
function PL.CleanStyle(value)
  if type(value) == "string" then
    local word = value:lower()
    for _, style in ipairs(PL.STYLES) do
      if word == style then
        return style
      end
    end
    value = tonumber(value)
  end
  if type(value) == "number" and value == value then
    return value == 1 and "bar" or "window"
  end
  return PL.DEFAULT_STYLE
end

-- The keys the settings offer, "" is off. Binding syntax of the game: modifier, dash, key.
PL.KEYS = { "", "Y", "G", "CTRL-Y", "SHIFT-G" }

-- Keys that move the character, open the chat or leave a window: never taken, whatever is stored.
local BLOCKED = {}
for _, key in ipairs({
  "W",
  "A",
  "S",
  "D",
  "Q",
  "E",
  "X",
  "R",
  "SPACE",
  "ENTER",
  "NUMPADENTER",
  "SLASH",
  "TAB",
  "ESCAPE",
  "UP",
  "DOWN",
  "LEFT",
  "RIGHT",
  "BACKSPACE",
  "PAGEUP",
  "PAGEDOWN",
  "NUMLOCK",
}) do
  BLOCKED[key] = true
end

-- The key itself without its modifier, nil for anything that is not a string.
function PL.BaseKey(key)
  if type(key) ~= "string" or key == "" then
    return nil
  end
  return key:upper():match("([^%-]+)$")
end

function PL.IsBlocked(key)
  local base = PL.BaseKey(key)
  return base == nil or BLOCKED[base] == true
end

-- A key of the list that is not blocked, "" for everything else.
function PL.CleanKey(value)
  if type(value) ~= "string" then
    return ""
  end
  local wanted = value:upper()
  for _, key in ipairs(PL.KEYS) do
    if key ~= "" and key == wanted and not PL.IsBlocked(key) then
      return key
    end
  end
  return ""
end

-- Text of a key for the player; names maps the modifiers ("CTRL", "SHIFT") to their words.
function PL.KeyLabel(key, names)
  key = PL.CleanKey(key)
  if key == "" then
    return nil
  end
  local mod, base = key:match("^(%a+)%-(.+)$")
  if mod then
    return ((names and names[mod]) or mod) .. "+" .. base
  end
  return key
end

-- Share of the lifetime that is left, 0 to 1.
function PL.Fraction(expires, now, lifetime)
  if type(expires) ~= "number" or type(now) ~= "number" or type(lifetime) ~= "number" or lifetime <= 0 then
    return 0
  end
  return math.min(1, math.max(0, (expires - now) / lifetime))
end

-- A line of text from a game value: a plain string without escape sequences, else nil.
function PL.PlainText(value)
  if type(value) ~= "string" or value == "" or #value > 60 or value:find("[%c|]") then
    return nil
  end
  return value
end

-- A level the game could report, nil for anything else.
function PL.CleanLevel(value)
  local n = tonumber(value)
  if not n or n ~= n or n < 1 or n > 100 then
    return nil
  end
  return math.floor(n)
end
