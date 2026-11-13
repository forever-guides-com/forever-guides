-- Forever Chat, the rules for the text of a message (pure, no frames, no game access): web addresses in a text,
-- [Item name] typed by hand, the readable plain text of a line (copy, quote), the quote head of a reply and the
-- targets of a forwarded message. ChatThread.lua draws what this finds, ChatInput.lua sends what this builds.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local TX = {}
chat.TextLogic = TX

TX.MAX_URL_BYTES = 240
TX.EXCERPT_CHARS = 40
TX.NAME_MAX = 60

-- Top level domains the thread takes as a web address without "www." or a scheme ("google.de"). A short list keeps
-- "e.g." and "z.B." out.
local TLD = {}
for tld in ("com de org net eu io tv gg info biz co uk fr es it nl at ch ru pl us ca me app dev xyz"):gmatch("%a+") do
  TLD[tld] = true
end

-- Marks that end a sentence, not an address.
local TRAIL = "[%.,;:!%?%)%]\"'>]+$"
local LEAD = "^[%(%[\"'<]+"

-- The address a word holds: { from, to } (byte range inside the word) or nil. The word is a run of non-blanks.
local function addressIn(word)
  if word:find("|", 1, true) then
    return nil
  end
  local from = (word:match(LEAD) or ""):len() + 1
  local rest = word:sub(from)
  local cut = rest:match(TRAIL)
  local to = #word - (cut and #cut or 0)
  local core = word:sub(from, to)
  if core == "" or #core > TX.MAX_URL_BYTES then
    return nil
  end
  local lower = core:lower()
  if lower:find("^https?://%S") then
    return from, to
  end
  local host, tail = core:match("^([^/%?#:]+)(.*)$")
  if not host or not host:find("^[%w%-%.]+$") or host:find("%.%.") or host:find("^%.") or host:find("%.$") then
    return nil
  end
  if tail ~= "" and not tail:find("^[/%?#]") and not tail:find("^:%d+") then
    return nil
  end
  local labels = {}
  for label in host:gmatch("[^%.]+") do
    labels[#labels + 1] = label
  end
  if #labels < 2 then
    return nil
  end
  if labels[1]:lower() == "www" or TLD[labels[#labels]:lower()] then
    return from, to
  end
  return nil
end

-- Whether a word is a web address (trailing marks ignored).
function TX.IsUrl(word)
  return type(word) == "string" and addressIn(word) ~= nil
end

-- The web addresses of a plain text: { { from, to, url } } in order, byte ranges inside the text.
function TX.Urls(text)
  local out = {}
  if type(text) ~= "string" then
    return out
  end
  for first, word in text:gmatch("()(%S+)") do
    local from, to = addressIn(word)
    if from then
      out[#out + 1] = { from = first + from - 1, to = first + to - 1, url = word:sub(from, to) }
    end
  end
  return out
end

-- The shown text with the web addresses in a color (hex = "rrggbb"). Links and escapes stay as they are: a word
-- with a pipe is left alone.
function TX.ColorUrls(shown, hex)
  if type(shown) ~= "string" or shown == "" or type(hex) ~= "string" then
    return shown
  end
  return (
    shown:gsub("%S+", function(word)
      local from, to = addressIn(word)
      if not from then
        return nil
      end
      return word:sub(1, from - 1) .. "|cff" .. hex .. word:sub(from, to) .. "|r" .. word:sub(to + 1)
    end)
  )
end

-- Plain text -------------------------------------------------------------------------------------------------

-- The text a reader sees: a link becomes its [name], colors, textures and atlas marks go, "||" is one pipe.
function TX.Plain(text)
  if type(text) ~= "string" then
    return ""
  end
  local out = text:gsub("||", "\1")
  out = out:gsub("|H[^|]*|h(.-)|h", "%1")
  out = out:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  out = out:gsub("|T[^|]*|t", ""):gsub("|A[^|]*|a", "")
  out = out:gsub("\1", "|")
  return out
end

-- At most `chars` characters of a plain text (UTF-8 safe), with "..." when cut. Blanks are collapsed.
function TX.Excerpt(text, chars)
  local plain = TX.Plain(text):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  chars = chars or TX.EXCERPT_CHARS
  local count, pos, size = 0, 1, #plain
  while pos <= size do
    local byte = plain:byte(pos)
    local step = byte >= 0xF0 and 4 or byte >= 0xE0 and 3 or byte >= 0xC0 and 2 or 1
    count = count + 1
    if count > chars then
      return plain:sub(1, pos - 1) .. "..."
    end
    pos = pos + step
  end
  return plain
end

-- [Item name] typed by hand ----------------------------------------------------------------------------------

-- Replaces every [Name] outside a real link by the link lookup(name) gives (a string with |H, nil when the item is
-- not known). Real links, colors and everything else stay untouched. Returns the text and how many were replaced.
function TX.Linkify(text, lookup)
  if type(text) ~= "string" or type(lookup) ~= "function" or not text:find("[", 1, true) then
    return text, 0
  end
  local out, count, pos = {}, 0, 1
  local function plain(segment)
    return (
      segment:gsub("%[([^%[%]|]+)%]", function(name)
        if #name > TX.NAME_MAX or not name:find("%S") then
          return nil
        end
        local ok, link = pcall(lookup, name)
        if ok and type(link) == "string" and link:find("|H", 1, true) then
          count = count + 1
          return link
        end
        return nil
      end)
    )
  end
  while pos <= #text do
    local from, to = text:find("|H[^|]*|h.-|h", pos)
    if not from then
      out[#out + 1] = plain(text:sub(pos))
      break
    end
    out[#out + 1] = plain(text:sub(pos, from - 1))
    out[#out + 1] = text:sub(from, to)
    pos = to + 1
  end
  return table.concat(out), count
end

-- Replies ----------------------------------------------------------------------------------------------------

-- The short head in front of a reply in a chat with other players: "@Name " (the first name only, so it stays
-- short). "" without a sender.
function TX.ReplyHead(sender)
  if type(sender) ~= "string" or not sender:find("%S") then
    return ""
  end
  local name = sender:gsub("%-.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return "@" .. name .. " "
end

-- The text a forwarded message puts into the chat box: with the quote head "Sender: " when asked, the text with its
-- links as they are. Never longer than `limit` bytes of head (the sender is cut when it would not fit).
function TX.ForwardText(sender, text, withHead)
  if type(text) ~= "string" then
    return ""
  end
  if withHead and type(sender) == "string" and sender:find("%S") then
    local name = sender:gsub("%-.*$", "")
    return name .. ": " .. text
  end
  return text
end
