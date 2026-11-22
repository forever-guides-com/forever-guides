-- Readable chat labels: a share goes into the chat as plain readable text "[Addon Forever Guides: ...]" and the data
-- travels beside it as one add-on message to the same audience (see ChatLabel.lua). The receiver matches the line to
-- the data by a key, a hash of the visible text. Pure functions, no game access.
local _, ns = ...

local CLL = {}
ns.ChatLabelLogic = CLL

CLL.HEAD = "Addon Forever Guides: "
-- Seconds a received payload waits for its chat line, senders and entries per sender kept at most.
CLL.TTL = 120
CLL.MAX_SENDERS = 40
CLL.PER_SENDER = 6
-- The client takes 255 bytes per chat message, stay clear of it.
CLL.MAX_TEXT = 240
-- Longest chat line a receiver looks at (this bounds the work for a faked event).
CLL.MAX_SCAN = 1024
-- Longest wire payload (a key, a kind letter and the payload of the link).
CLL.MAX_WIRE = 440
-- The kind letter of a page link, the kinds of NoteLink are capital letters.
CLL.PAGE = "p"

local MOD = 4294967296
local OPEN = "[" .. CLL.HEAD

-- 16 hex digits of two independent running hashes over the bytes of `text` (UTF-8 safe, byte exact).
function CLL.Key(text)
  text = tostring(text or "")
  local h1, h2 = 5381, 7
  for i = 1, #text do
    local b = text:byte(i)
    h1 = (h1 * 33 + b) % MOD
    h2 = (h2 * 131 + b + i) % 4294967291
  end
  return string.format("%08x%08x", h1, h2)
end

-- "[Addon Forever Guides: body]" for a body without brackets and pipes, cut to MAX_TEXT bytes.
function CLL.Text(body)
  local clean = ns.PageShareLogic.CleanLabel(body, CLL.MAX_TEXT - #OPEN - 1)
  return OPEN .. clean .. "]"
end

-- The first readable text of a line: start, end and the text, nil when there is none.
function CLL.Find(msg)
  if type(msg) ~= "string" or #msg > CLL.MAX_SCAN then
    return nil
  end
  local s, e = msg:find("%[Addon Forever Guides: [^%[%]|]+%]")
  if not s then
    return nil
  end
  return s, e, msg:sub(s, e)
end

-- What stands between the first opening quote ("„" or a straight one) and the closing one, nil without quotes.
function CLL.TitleOf(text)
  local body = type(text) == "string" and text:sub(#OPEN + 1, -2) or ""
  local s, e = body:find("\226\128\158", 1, true)
  if not s then
    s, e = body:find('"', 1, true)
  end
  if not s then
    return nil
  end
  local rest = body:sub(e + 1)
  if rest:sub(-3) == "\226\128\156" then
    rest = rest:sub(1, -4)
  elseif rest:sub(-1) == '"' then
    rest = rest:sub(1, -2)
  end
  return rest
end

-- Wire ------------------------------------------------------------------------------------------------------

-- "<key16>:<letter>:<payload>", nil for anything that does not fit.
function CLL.Wire(key, letter, payload)
  if type(key) ~= "string" or not key:find("^%x+$") or #key ~= 16 then
    return nil
  end
  if type(letter) ~= "string" or not letter:find("^%a$") then
    return nil
  end
  if type(payload) ~= "string" or not payload:find("^[%w%(%)/_%-]+$") then
    return nil
  end
  local wire = key .. ":" .. letter .. ":" .. payload
  return #wire <= CLL.MAX_WIRE and wire or nil
end

-- { key, letter, payload } of a wire text, nil when malformed.
function CLL.ParseWire(wire)
  if type(wire) ~= "string" or #wire > CLL.MAX_WIRE then
    return nil
  end
  local key, letter, payload = wire:match("^(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x):(%a):([%w%(%)/_%-]+)$")
  if not key then
    return nil
  end
  return { key = key, letter = letter, payload = payload }
end

-- Channels ---------------------------------------------------------------------------------------------------

local GROUP = { PARTY = "PARTY", RAID = "RAID", RAID_WARNING = "RAID", INSTANCE_CHAT = "INSTANCE_CHAT" }

-- The add-on audience for a chat type of the edit box or of SendChatMessage: kind, target (whisper name or channel
-- number) and the group channel the audience has to be (so a party line never reaches a raid). nil for Say, Yell,
-- emotes and everything without an add-on channel.
function CLL.Route(chatType, target)
  if GROUP[chatType] then
    return { kind = "group", channel = GROUP[chatType] }
  elseif chatType == "GUILD" then
    return { kind = "guild" }
  elseif chatType == "OFFICER" then
    return { kind = "officer" }
  elseif chatType == "WHISPER" then
    if type(target) == "string" and target ~= "" and #target <= 64 then
      return { kind = "whisper", target = target }
    end
  elseif chatType == "CHANNEL" then
    local number = tonumber(target)
    if number and number >= 1 and number <= 99 and number % 1 == 0 then
      return { kind = "channel", target = number }
    end
  end
  return nil
end

-- Cache of received payloads --------------------------------------------------------------------------------

-- Payloads by sender and key, kept for TTL seconds. Bounded, pruned only when used (no timer).
function CLL.NewCache(clock)
  local cache = {}
  local senders, order = {}, {}

  local function drop(name)
    senders[name] = nil
    for i, other in ipairs(order) do
      if other == name then
        table.remove(order, i)
        break
      end
    end
  end

  local function prune(list, now)
    for i = #list, 1, -1 do
      if now - list[i].at > CLL.TTL then
        table.remove(list, i)
      end
    end
  end

  function cache.Add(name, key, entry)
    if type(name) ~= "string" or name == "" or type(key) ~= "string" then
      return false
    end
    local now = clock()
    local list = senders[name]
    if not list then
      while #order >= CLL.MAX_SENDERS do
        drop(order[1])
      end
      list = {}
      senders[name] = list
      order[#order + 1] = name
    end
    prune(list, now)
    for i = #list, 1, -1 do
      if list[i].key == key then
        table.remove(list, i)
      end
    end
    list[#list + 1] = { key = key, entry = entry, at = now }
    while #list > CLL.PER_SENDER do
      table.remove(list, 1)
    end
    return true
  end

  -- The entry of a sender for a key, nil when none or too old. The first hit of a slot (the chat event) belongs to
  -- one chat line (lineId, the game asks once per chat frame for the same line): that line keeps getting it, any other
  -- line of the slot gets nothing. Slots are separate on purpose: a whisper to oneself shows up twice (WHISPER_INFORM
  -- and WHISPER), both lines are the same share.
  function cache.Find(name, key, lineId, slot)
    local list = senders[name]
    if not list then
      return nil
    end
    local now = clock()
    prune(list, now)
    if #list == 0 then
      drop(name)
      return nil
    end
    slot = slot or ""
    for _, item in ipairs(list) do
      if item.key == key then
        item.lines = item.lines or {}
        local bound = item.lines[slot]
        if bound == nil then
          -- false: taken by a line without an id, nobody else gets it.
          if lineId == nil then
            item.lines[slot] = false
          else
            item.lines[slot] = lineId
          end
          return item.entry
        end
        return lineId ~= nil and bound == lineId and item.entry or nil
      end
    end
  end

  function cache.Size()
    local n = 0
    for _, list in pairs(senders) do
      n = n + #list
    end
    return n
  end

  function cache.Clear()
    senders, order = {}, {}
  end

  return cache
end
