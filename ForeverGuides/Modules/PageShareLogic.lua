-- Page links: a view of the add-on (page, tab, selection) as one short payload "page[/part[/part...]]" that goes
-- into the chat as "[FGP1:payload:label]" (older form) or becomes a share code (ShareCodeLogic.lua). Pure
-- functions, no game access. Everything that arrives from another player passes Validate first: only characters
-- of a fixed set, a bounded number and length of parts, the first part has to be a page the caller knows. The parts after the page are the route
-- params of that page, the page itself ignores values it does not know.
local _, ns = ...

local PSL = {}
ns.PageShareLogic = PSL

PSL.VERSION = 1
PSL.TOKEN = "FGP" .. PSL.VERSION
PSL.MAX_PARTS = 4
PSL.MAX_PART = 40
PSL.MAX_PAYLOAD = 100
-- The client takes 255 bytes per chat message, stay clear of it.
PSL.MAX_CHAT = 240
-- Longest message a receiver looks at (a chat line is far shorter, this bounds the work for a faked event).
PSL.MAX_SCAN = 1024
PSL.SEPARATOR = " \226\128\186 "

local function utf8Cut(text, maxBytes)
  if #text <= maxBytes then
    return text
  end
  local cut = maxBytes
  -- Do not stop inside a multi-byte character (continuation bytes are 10xxxxxx).
  while cut > 0 do
    local byte = text:byte(cut + 1)
    if not byte or byte < 128 or byte >= 192 then
      break
    end
    cut = cut - 1
  end
  return text:sub(1, cut)
end

-- Parts of a valid payload, else nil and a reason ("type", "empty", "long", "parts", "chars", "page").
-- known(pageId) tells whether the page exists.
function PSL.Validate(payload, known)
  if type(payload) ~= "string" then
    return nil, "type"
  end
  if payload == "" then
    return nil, "empty"
  end
  if #payload > PSL.MAX_PAYLOAD then
    return nil, "long"
  end
  local parts = {}
  for part in (payload .. "/"):gmatch("([^/]*)/") do
    if #parts >= PSL.MAX_PARTS then
      return nil, "parts"
    end
    if part == "" or #part > PSL.MAX_PART or part:find("[^%w_%-]") then
      return nil, "chars"
    end
    parts[#parts + 1] = part
  end
  if type(known) ~= "function" or known(parts[1]) ~= true then
    return nil, "page"
  end
  return parts
end

-- Payload of a list of parts (page id first), nil when it would not pass Validate.
function PSL.Encode(parts, known)
  if type(parts) ~= "table" then
    return nil
  end
  local clean = {}
  for i, part in ipairs(parts) do
    clean[i] = tostring(part)
  end
  local payload = table.concat(clean, "/")
  if not PSL.Validate(payload, known) then
    return nil
  end
  return payload
end

-- A label for people without the add-on: no characters that end the token or start a link, cut to `room` bytes.
function PSL.CleanLabel(label, room)
  label = tostring(label or ""):gsub("[%c%[%]|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return utf8Cut(label, room)
end

-- "[FGP1:payload:label]", at most MAX_CHAT bytes (the label gives way).
function PSL.Token(payload, label)
  local head = "[" .. PSL.TOKEN .. ":" .. payload .. ":"
  local room = PSL.MAX_CHAT - #head - 1
  if room < 0 then
    return nil
  end
  return head .. PSL.CleanLabel(label, room) .. "]"
end

-- Replaces the first valid token of a message. convert(payload, label) returns the replacement text or nil
-- (then the token stays as it is). Returns the new message or nil when nothing changed.
function PSL.Rewrite(msg, convert)
  if type(msg) ~= "string" or #msg > PSL.MAX_SCAN or not msg:find("[" .. PSL.TOKEN .. ":", 1, true) then
    return nil
  end
  local done = false
  local out = msg:gsub("%[" .. PSL.TOKEN .. ":([^:%]|]+):([^%]|]*)%]", function(payload, label)
    if done then
      return nil
    end
    local replacement = convert(payload, label)
    if replacement then
      done = true
    end
    return replacement
  end)
  return done and out or nil
end

-- Labels of the crumbs joined for display ("Instances > Gnomeregan > Quests").
function PSL.Join(labels)
  return table.concat(labels, PSL.SEPARATOR)
end
