-- Forever Chat, unread counters, mentions and muting (pure, no game access, the caller passes the clock).
-- Works on the conversations of ChatConversations.lua. A line is counted when it arrives (Note) and stays
-- counted until the conversation is read up to it, so muting later never changes what was counted.
--
-- Rules, in this order, for a line of someone else:
--   * a channel (and the local chat) counts only when a mention names the player (options.channelMentionOnly, default on)
--   * a muted conversation counts only a mention (options.mentionBreaksMute, default on)
--   * anything else counts
-- Own lines never count and mark the conversation as read. A mention is the own name (full name and first
-- name) or a keyword of the list, letter case blind, as a whole word. Links and colors are no mention.
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local Logic, PN, Limits = FG.ChatHistoryLogic, FG.PlayerName, FG.ChatHistoryLimits
local fold = FG.LfgBrowseFilterLogic.Fold

local Unread = {}
chat.Unread = Unread

-- Highest number the badge shows, above it "99+".
Unread.CAP = 99
-- Same limits as the store (Store.MAX_KEYWORDS, KEYWORD_BYTES); a test keeps them equal.
Unread.MAX_KEYWORDS = 20
Unread.KEYWORD_BYTES = 48
-- Shortest term that counts as a mention, in bytes.
Unread.MIN_TERM = 2
-- Offered mute periods in seconds: one hour, eight hours, one day, one week. true in the store has no end.
Unread.MUTE_SECONDS = { 3600, 28800, 86400, 604800 }

local function isNumber(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

----------------------------------------------------------------------------------------------------
-- Muting
----------------------------------------------------------------------------------------------------

-- value is an entry of the store list muted: true (no end), a time, or nothing. A time counts until it has passed.
function Unread.IsMuted(value, now)
  if value == true then
    return true
  end
  return isNumber(value) and (not isNumber(now) or now < value)
end

-- The time for Store.Set(db, "muted", key, ...) when the conversation is muted for seconds from now.
function Unread.MuteUntil(now, seconds)
  if isNumber(now) and isNumber(seconds) and seconds > 0 then
    return math.floor(now + seconds)
  end
  return nil
end

----------------------------------------------------------------------------------------------------
-- Mentions
----------------------------------------------------------------------------------------------------

local function trim(text)
  return (text:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", ""))
end

-- Letters, digits and every byte of a multibyte character belong to a word.
local function isWordByte(byte)
  return byte ~= nil
    and (byte >= 128 or (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122))
end

-- The terms to look for: own full name without realm, own first name, then the keywords. Folded, no double,
-- none shorter than MIN_TERM. Build them once and again when the name or the list changes.
function Unread.Terms(ownName, keywords)
  local terms, seen = {}, {}
  local function add(text)
    text = fold(trim(text))
    if #text >= Unread.MIN_TERM and not seen[text] then
      seen[text] = true
      terms[#terms + 1] = text
    end
  end
  if type(ownName) == "string" then
    local full = PN.Clean(ownName):gsub("%-[^ ]*$", "")
    add(full)
    add((PN.Split(full)))
  end
  if type(keywords) == "table" then
    for i = 1, math.min(#keywords, Unread.MAX_KEYWORDS) do
      if type(keywords[i]) == "string" then
        add(Limits.CutUtf8(keywords[i], Unread.KEYWORD_BYTES))
      end
    end
  end
  return terms
end

-- Text as a mention search sees it: folded, colors gone, a link as a space.
local function searchable(text)
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H[^|]*|h.-|h", " ")
  return fold(text)
end

-- The first term the text names, nil when there is none. text must be a readable string.
function Unread.Mentions(text, terms)
  if type(text) ~= "string" or type(terms) ~= "table" or #terms == 0 then
    return nil
  end
  text = searchable(text)
  for _, term in ipairs(terms) do
    local needStart, needEnd = isWordByte(term:byte(1)), isWordByte(term:byte(-1))
    local from = 1
    while true do
      local first, last = text:find(term, from, true)
      if not first then
        break
      end
      if not (needStart and isWordByte(text:byte(first - 1))) and not (needEnd and isWordByte(text:byte(last + 1))) then
        return term
      end
      from = first + 1
    end
  end
  return nil
end

----------------------------------------------------------------------------------------------------
-- Counting
----------------------------------------------------------------------------------------------------

-- The context of Note: db is the store (ChatConversations key settings), ownName the own full name, now the clock.
function Unread.Context(db, ownName, now)
  local options = type(db) == "table" and type(db.options) == "table" and db.options or {}
  return {
    muted = type(db) == "table" and type(db.muted) == "table" and db.muted or {},
    terms = Unread.Terms(ownName, options.keywords),
    now = now,
    mentionBreaksMute = options.mentionBreaksMute ~= false,
    channelMentionOnly = options.channelMentionOnly ~= false,
  }
end

-- Judges a line that was just added to the conversation: sets line.mention and line.unread and returns
-- whether it counts. An own line marks the conversation as read.
function Unread.Note(ctx, conv, line)
  if line.dir == Logic.DIR_OUT then
    Unread.MarkRead(conv)
    return false
  end
  local mention = not line.hidden and Unread.Mentions(line.text, ctx.terms) ~= nil
  local counts = true
  if (conv.kind == "channel" or conv.kind == "local") and ctx.channelMentionOnly and not mention then
    counts = false
  elseif Unread.IsMuted(ctx.muted[conv.key], ctx.now) and not (mention and ctx.mentionBreaksMute) then
    counts = false
  end
  line.mention = mention or nil
  line.unread = counts or nil
  return counts
end

-- Number of lines counted and not read yet; a conversation marked as unread shows at least 1.
function Unread.Count(conv)
  local count = 0
  for i = #conv.lines, 1, -1 do
    local line = conv.lines[i]
    if line.seq <= conv.readSeq then
      break
    end
    if line.unread then
      count = count + 1
    end
  end
  return conv.marked and math.max(count, 1) or count
end

-- Unread lines that name the player.
function Unread.MentionCount(conv)
  local count = 0
  for i = #conv.lines, 1, -1 do
    local line = conv.lines[i]
    if line.seq <= conv.readSeq then
      break
    end
    if line.unread and line.mention then
      count = count + 1
    end
  end
  return count
end

-- The sum over all conversations, for the badge.
function Unread.Total(state)
  local total = 0
  for _, conv in pairs(state.convs) do
    total = total + Unread.Count(conv)
  end
  return total
end

-- Text of a counter: "" for none, the number up to CAP, then "99+".
function Unread.Label(count)
  if not isNumber(count) or count < 1 then
    return ""
  end
  count = math.floor(count)
  return count > Unread.CAP and (Unread.CAP .. "+") or tostring(count)
end

function Unread.MarkRead(conv)
  conv.readSeq, conv.marked = conv.seq, false
end

-- Read up to and including the line at position seq. Never goes back.
function Unread.MarkReadTo(conv, seq)
  if isNumber(seq) then
    conv.readSeq = math.max(conv.readSeq, math.min(math.floor(seq), conv.seq))
  end
  conv.marked = false
end

function Unread.MarkUnread(conv)
  conv.marked = true
end

-- Index in conv.lines of the first unread line of someone else, where the divider "new messages" goes. nil
-- when there is none.
function Unread.DividerIndex(conv)
  for i, line in ipairs(conv.lines) do
    if line.seq > conv.readSeq and line.dir == Logic.DIR_IN then
      return i
    end
  end
  return nil
end
