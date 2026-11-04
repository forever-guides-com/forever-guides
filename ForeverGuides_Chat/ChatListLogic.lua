-- Forever Chat, the rules of the conversation list (pure, no frames, no game access): plain preview text,
-- relative age, titles, the rows of a tab, the rows of a search over all conversations, keys and empty
-- states. ChatList.lua draws what this returns.
--
-- row = { kind = "conv"|"hit"|"head", id, key, kindOf, letter, title, nick, sub, time, count, label,
--         mentions, pinned, muted, seq }
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local LL = {}
chat.ListLogic = LL

local Logic = FG.ChatHistoryLogic
local LB = FG.LfgBrowseFilterLogic

LL.KIND_LETTER = {
  whisper = "W",
  bnet = "B",
  party = "P",
  raid = "R",
  instance = "I",
  guild = "G",
  officer = "O",
  channel = "#",
  ["local"] = "L",
  team = "T",
}
-- How a line of the conversation "local" was spoken: the type of the stored line (say, yell, emote and the text
-- emote are stored as these three) -> voice. The symbol is Latin-1 so every game font draws it, the word
-- next to it (chat.voice.<voice>) carries the meaning, the color only supports it.
LL.VOICES = { "say", "yell", "emote" }
LL.VOICE_SYMBOL = { say = "»", yell = "!", emote = "*" }
-- The whisper tab lists these kinds in sections, with the text key of the heading.
LL.SECTIONS = { whisper = "chat.group.characters", bnet = "chat.group.bnet" }
-- Text keys that explain a conversation whose name is the label of its kind.
LL.HINTS = { ["local"] = "chat.hint.local" }
LL.PREVIEW_CHARS = 72
LL.SNIPPET_CHARS = 64
LL.SEARCH_HITS = 60
LL.SEARCH_PER_CHAT = 3
LL.PAGE_STEP = 5
-- Ages (seconds) where the label changes unit.
LL.MINUTE, LL.HOUR, LL.DAY, LL.WEEK = 60, 3600, 86400, 604800

local CHAR = "[\1-\127\194-\244][\128-\191]*"

local function isNumber(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The text as a player reads it: links show their label, colors, textures and control characters are gone,
-- blanks are single. Anything but a string gives "".
function LL.Plain(text)
  if type(text) ~= "string" then
    return ""
  end
  text = text:gsub("[%z\1-\31\127]", " ")
  text = text:gsub("||", "\1")
  text = text:gsub("|H.-|h(.-)|h", "%1")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
  text = text:gsub("%s+", " ")
  return (trim(text):gsub("\1", "|"))
end

-- At most maxChars characters (UTF-8 aware), "..." behind a cut text. The second result tells about the cut.
function LL.CutChars(text, maxChars)
  local count = 0
  for at in text:gmatch("()" .. CHAR) do
    count = count + 1
    if count > maxChars then
      return text:sub(1, at - 1) .. "...", true
    end
  end
  return text, false
end

function LL.Preview(text, maxChars)
  return (LL.CutChars(LL.Plain(text), maxChars or LL.PREVIEW_CHARS))
end

-- The part of a message around the first hit of query (letter case and umlaut blind like the search).
function LL.Snippet(text, query, maxChars)
  maxChars = maxChars or LL.SNIPPET_CHARS
  local plain = LL.Plain(text)
  local list = {}
  for ch in plain:gmatch(CHAR) do
    list[#list + 1] = ch
  end
  local q = type(query) == "string" and LB.Fold(trim(query)) or ""
  local at = q ~= "" and LB.Fold(plain):find(q, 1, true) or nil
  local start = 1
  if at then
    local bytes = 0
    for i, ch in ipairs(list) do
      bytes = bytes + #ch
      if bytes >= at then
        start = i
        break
      end
    end
  end
  local from = math.max(1, start - 12)
  local to = math.min(#list, from + maxChars - 1)
  local out = table.concat(list, "", from, to)
  return (from > 1 and "..." or "") .. out .. (to < #list and "..." or "")
end

-- Unit and number of the label of a time: "now", "min", "hour", "day" or "date" (older than a week or
-- unknown). The window turns it into a text.
function LL.Age(now, time)
  if not (isNumber(now) and isNumber(time)) then
    return "date", 0
  end
  local d = math.max(0, now - time)
  if d < LL.MINUTE then
    return "now", 0
  elseif d < LL.HOUR then
    return "min", math.floor(d / LL.MINUTE)
  elseif d < LL.DAY then
    return "hour", math.floor(d / LL.HOUR)
  elseif d < LL.WEEK then
    return "day", math.floor(d / LL.DAY)
  end
  return "date", 0
end

-- Name without realm for the short forms (previews, headings).
function LL.ShortName(name)
  if type(name) ~= "string" then
    return ""
  end
  return (name:gsub("%-.*$", ""))
end

-- The name of a Battle.net partner as the game shows it in the friend list: "Lempard (Wayneil)" with the
-- character while the partner plays WoW.
function LL.BnetName(conv)
  if type(conv.name) ~= "string" or conv.name == "" then
    return ""
  end
  if type(conv.character) == "string" and conv.character ~= "" then
    return conv.name .. " (" .. conv.character .. ")"
  end
  return conv.name
end

-- The nickname, else the name of the conversation, else the label of its kind.
function LL.Title(conv, nickname, kindLabel)
  if type(nickname) == "string" and nickname ~= "" then
    return nickname, true
  end
  if conv.kind == "bnet" and LL.BnetName(conv) ~= "" then
    return LL.BnetName(conv), false
  end
  if type(conv.name) == "string" and conv.name ~= "" then
    return conv.name, false
  end
  return kindLabel or conv.kind, false
end

-- The voice of a line of a "local" conversation: "say", "yell", "emote", nil for any other conversation or a
-- type that is none of them.
function LL.Voice(conv, line)
  if type(conv) ~= "table" or conv.kind ~= "local" or type(line) ~= "table" then
    return nil
  end
  local name = Logic.TYPE_NAMES[line.type]
  return LL.VOICE_SYMBOL[name] and name or nil
end

-- The tab that lists a kind of conversation.
function LL.TabOf(kind)
  for _, tab in ipairs(chat.Conversations.TAB_ORDER) do
    if chat.Conversations.TAB_KINDS[tab][kind] then
      return tab
    end
  end
  return chat.Conversations.TAB_ORDER[1]
end

-- ctx: now, db (the store), kindLabel(kind), you (text of "You"), hidden (text of a hidden line).
local function preview(conv, ctx)
  local last = conv.lines[#conv.lines]
  if not last then
    return ""
  end
  if last.hidden then
    return ctx.hidden or ""
  end
  local text = LL.Preview(last.text)
  local voice = LL.Voice(conv, last)
  local mark = voice and (LL.VOICE_SYMBOL[voice] .. " ") or ""
  if last.dir == Logic.DIR_OUT then
    return mark .. (ctx.you or "") .. ": " .. text
  end
  local who = LL.ShortName(last.sender)
  if conv.kind ~= "whisper" and conv.kind ~= "bnet" and who ~= "" then
    return mark .. who .. ": " .. text
  end
  return mark .. text
end

local function dbMap(ctx, field)
  local db = type(ctx.db) == "table" and ctx.db or {}
  return type(db[field]) == "table" and db[field] or {}
end

function LL.Row(conv, ctx)
  local Unread = chat.Unread
  local count = Unread.Count(conv)
  local kindLabel = ctx.kindLabel and ctx.kindLabel(conv.kind) or conv.kind
  local title, nick = LL.Title(conv, dbMap(ctx, "nicknames")[conv.key], kindLabel)
  return {
    kind = "conv",
    id = conv.key,
    key = conv.key,
    kindOf = conv.kind,
    letter = LL.KIND_LETTER[conv.kind] or "?",
    icon = ctx.iconOf and ctx.iconOf(conv) or nil,
    title = title,
    nick = nick,
    sub = preview(conv, ctx),
    time = conv.last,
    count = count,
    label = Unread.Label(count),
    mentions = Unread.MentionCount(conv),
    pinned = dbMap(ctx, "pins")[conv.key] == true,
    muted = Unread.IsMuted(dbMap(ctx, "muted")[conv.key], ctx.now),
  }
end

-- True when the conversations hold two or more kinds that have a section.
local function sectioned(convs)
  local first
  for _, conv in ipairs(convs) do
    if LL.SECTIONS[conv.kind] then
      first = first or conv.kind
      if conv.kind ~= first then
        return true
      end
    end
  end
  return false
end

-- The rows of one tab in list order (pinned first, then the kinds of a sectioned tab, then the latest activity).
-- A sectioned tab with more than one kind gets a heading before each run of unpinned conversations of a kind;
-- the pinned ones above them need none, their pin and symbol say what they are.
function LL.Rows(state, tab, ctx)
  local rows = {}
  local convs = chat.Conversations.Sorted(state, tab)
  local headings = chat.Conversations.KIND_SORTED_TABS[tab] and sectioned(convs)
  local pins = type(state.pins) == "table" and state.pins or {}
  local run
  for _, conv in ipairs(convs) do
    if headings then
      local kind = pins[conv.key] ~= true and LL.SECTIONS[conv.kind] and conv.kind or nil
      if kind and kind ~= run then
        rows[#rows + 1] = { kind = "head", id = "head:" .. kind, textKey = LL.SECTIONS[kind] }
      end
      run = kind
    end
    rows[#rows + 1] = LL.Row(conv, ctx)
  end
  return rows
end

-- Unread lines per tab, for the tab labels.
function LL.TabUnread(state)
  local out = {}
  for _, tab in ipairs(chat.Conversations.TAB_ORDER) do
    local sum = 0
    for _, conv in ipairs(chat.Conversations.Sorted(state, tab)) do
      sum = sum + chat.Unread.Count(conv)
    end
    out[tab] = sum
  end
  return out
end

-- The rows of a search: a heading, the chats that match by name, nickname or note, a heading, the messages
-- that match. tab (optional): only the conversations of that tab, else all of them. The second result tells
-- that the search cut hits.
function LL.SearchRows(state, query, ctx, tab)
  local hits, cut =
    chat.Search.Run(state, ctx.db, query, { limit = LL.SEARCH_HITS, perConversation = LL.SEARCH_PER_CHAT, tab = tab })
  local chats, messages = {}, {}
  for _, hit in ipairs(hits) do
    local row = LL.Row(hit.conv, ctx)
    if hit.field == "text" then
      local line = hit.conv.lines[hit.index]
      row.kind, row.id, row.seq = "hit", hit.key .. "#" .. hit.seq, hit.seq
      row.sub = line and LL.Snippet(line.text, query) or ""
      row.time = line and line.time or row.time
      row.count, row.label, row.mentions = 0, "", 0
      messages[#messages + 1] = row
    else
      chats[#chats + 1] = row
    end
  end
  local rows = {}
  if #chats > 0 then
    rows[#rows + 1] = { kind = "head", id = "head:chats", textKey = "chat.group.chats" }
    for _, row in ipairs(chats) do
      rows[#rows + 1] = row
    end
  end
  if #messages > 0 then
    rows[#rows + 1] = { kind = "head", id = "head:messages", textKey = "chat.group.messages" }
    for _, row in ipairs(messages) do
      rows[#rows + 1] = row
    end
  end
  return rows, cut
end

-- Why the list is empty: "search" (a query without a match), "none" (no conversation at all), "tab" (none in
-- this tab). nil while there are rows.
function LL.EmptyReason(total, shown, query)
  if shown > 0 then
    return nil
  elseif type(query) == "string" and trim(query) ~= "" then
    return "search"
  elseif total == 0 then
    return "none"
  end
  return "tab"
end

local STEP = { UP = -1, DOWN = 1, PAGEUP = -LL.PAGE_STEP, PAGEDOWN = LL.PAGE_STEP }

-- The row index a key moves to (headings are skipped). nil for a key that does not move, or an empty list.
function LL.Navigate(rows, index, key)
  local list = {}
  local at = 0
  for i, row in ipairs(rows) do
    if row.kind ~= "head" then
      list[#list + 1] = i
      if i == index then
        at = #list
      end
    end
  end
  if #list == 0 then
    return nil
  end
  local target
  if key == "HOME" then
    target = 1
  elseif key == "END" then
    target = #list
  elseif STEP[key] then
    target = at == 0 and (STEP[key] > 0 and 1 or #list) or at + STEP[key]
  else
    return nil
  end
  return list[math.max(1, math.min(#list, target))]
end

-- The tab left (-1) or right (+1) of tab, held at the ends.
function LL.NextTab(tab, delta)
  local order = chat.Conversations.TAB_ORDER
  for i, id in ipairs(order) do
    if id == tab then
      return order[math.max(1, math.min(#order, i + delta))]
    end
  end
  return order[1]
end
