-- The one exit for text that goes into the chat. The client refuses a message with an escape it does not know
-- ("Invalid escape code in chat message") and the receiver gets nothing, so every outgoing text passes
-- Prepare first. What is left is exactly: plain text, doubled literal pipes and complete client links
-- |cffXXXXXX|H<type>:...|h[...]|h|r of an allowed type. Everything else (colors, textures, links of another
-- shape or type, line breaks, control characters, broken UTF-8) is reduced to its visible text, and the
-- result is cut at 255 bytes on a character or link boundary, never inside a link.
-- Add-on messages (C_ChatInfo.SendAddonMessage) are not chat text and go through ns.Comm with its own limits.
local _, ns = ...

local CS = {}
ns.ChatSafe = CS

CS.MAX_BYTES = 255

-- Link types proven to arrive (probe on client 1.60.1): a colored link of these types reaches the receiver, an
-- uncolored one is refused with "Invalid escape code". "addon" links are dropped silently by the server, so they
-- never leave and every other type is reduced to its text.
CS.TYPES = {
  item = true,
  spell = true,
  enchant = true,
  quest = true,
}

-- A quest link is only sent as |Hquest:<id>:0|h[Title]|h: the server mangles the whole message when field 2 is
-- not 0 or the title does not match the quest. CS.QuestLink builds it from client data only.

-- Length of the UTF-8 character that starts with this byte, nil for a byte that starts none.
local function charLength(byte)
  if byte < 0x80 then
    return 1
  elseif byte >= 0xC2 and byte < 0xE0 then
    return 2
  elseif byte >= 0xE0 and byte < 0xF0 then
    return 3
  elseif byte >= 0xF0 and byte < 0xF5 then
    return 4
  end
end

-- One element at pos: its output text and the next position. "" drops the element.
local function nextAtom(text, pos)
  if text:byte(pos) ~= 124 then
    local length = charLength(text:byte(pos))
    local char = length and text:sub(pos, pos + length - 1)
    if char and #char == length and not char:find("[^\128-\191]", 2) then
      return char, pos + length
    end
    return "", pos + 1
  end
  local two = text:sub(pos, pos + 1)
  if two == "||" then
    return two, pos + 2
  end
  -- A complete client link of an allowed type stays whole.
  local from, to, kind = text:find("^|cff%x%x%x%x%x%x|H(%a+):[^|]*|h%[[^|]+%]|h|r", pos)
  if from and CS.TYPES[kind] and (kind ~= "quest" or text:find("^|cff%x%x%x%x%x%x|Hquest:%d+:0|h", pos)) then
    return text:sub(from, to), to + 1
  end
  local _, headEnd = text:find("^|H[^|]*|h", pos)
  if headEnd then
    -- Any other link shows its text only (the closing |h is dropped later when it stands alone).
    local label, after = text:match("^([^|]*)|h()", headEnd + 1)
    if label then
      return label, after
    end
    return "", headEnd + 1
  end
  local _, skipTo = text:find("^|c%x%x%x%x%x%x%x%x", pos)
  if not skipTo then
    _, skipTo = text:find("^|[rhnkK]", pos)
  end
  if not skipTo then
    _, skipTo = text:find("^|T[^|]*|t", pos)
  end
  if not skipTo then
    _, skipTo = text:find("^|A[^|]*|a", pos)
  end
  if skipTo then
    return text:sub(pos, pos + 1) == "|n" and " " or "", skipTo + 1
  end
  -- A literal pipe is doubled.
  return "||", pos + 1
end

-- The text as the client takes it. limit is the byte limit (default 255). A cut text may end in a blank.
function CS.Prepare(text, limit)
  if type(text) ~= "string" then
    return ""
  end
  limit = limit or CS.MAX_BYTES
  text = text:gsub("[\r\n\t]+", " "):gsub("[%z\1-\31\127]", "")
  local out, used, pos, n = {}, 0, 1, #text
  while pos <= n do
    local atom, after = nextAtom(text, pos)
    if used + #atom > limit then
      break
    end
    out[#out + 1] = atom
    used = used + #atom
    pos = after
  end
  return table.concat(out)
end

-- True when the text may go out as it is. The second result names the first rule that fails.
function CS.Validate(text)
  if type(text) ~= "string" or text == "" then
    return false, "empty"
  elseif #text > CS.MAX_BYTES then
    return false, "length"
  elseif text:find("[\r\n]") then
    return false, "newline"
  elseif CS.Prepare(text, math.huge) ~= text then
    return false, "markup"
  end
  return true
end

local function callQuestApi(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  return ok and value or nil
end

-- Title the client knows for a quest, nil when it has none (yet).
local function clientQuestTitle(id)
  local log = rawget(_G, "C_QuestLog")
  local title = type(log) == "table" and callQuestApi(log.GetTitleForQuestID, id) or nil
  if type(title) ~= "string" or title == "" then
    local cache = rawget(_G, "QuestCache")
    local info = type(cache) == "table" and callQuestApi(cache.Get, cache, id) or nil
    title = type(info) == "table" and info.title or nil
  end
  return type(title) == "string" and title ~= "" and title or nil
end

-- The quest as chat text: (text, isLink). A link only comes from the client: its own link for this id, else
-- |Hquest:id:0|h[client title]|h. Without a client title the plain "[fallbackTitle]" goes out, never a title
-- from our data. reserve is the byte count of the rest of the message, a link that does not fit is dropped.
function CS.QuestLink(id, fallbackTitle, reserve)
  local plain = "[" .. tostring(fallbackTitle or id) .. "]"
  if type(id) ~= "number" or id ~= math.floor(id) or id <= 0 then
    return plain, false
  end
  local function fits(link)
    return #link + (reserve or 0) <= CS.MAX_BYTES
  end
  local log = rawget(_G, "C_QuestLog")
  for _, fn in ipairs({ rawget(_G, "GetQuestLink") or false, type(log) == "table" and log.GetQuestLink or false }) do
    local link = callQuestApi(fn or nil, id)
    if type(link) == "string" and tonumber(link:match("|Hquest:(%d+):0|h")) == id and fits(link) then
      return link, true
    end
  end
  local title = clientQuestTitle(id)
  if not title then
    local request = type(log) == "table" and log.RequestLoadQuestByID
    callQuestApi(request or nil, id)
  elseif not title:find("[|%[%]]") then
    local link = string.format("|cffffff00|Hquest:%d:0|h[%s]|h|r", id, title)
    if fits(link) then
      return link, true
    end
  end
  return plain, false
end

-- Sends one prepared chat message. fn is the chat function (default SendChatMessage), called from here so the
-- client sees a Lua call. Raises an error for a text that is empty after Prepare, like the client does.
function CS.Send(text, chatType, target, fn)
  local clean = CS.Prepare(text)
  if clean == "" then
    error("empty chat message", 0)
  end
  fn = fn or rawget(_G, "SendChatMessage")
  if type(fn) ~= "function" then
    error("no chat function", 0)
  end
  return fn(clean, chatType, nil, target)
end
