-- Forever Chat, the rules of the thread view (pure, no frames, no game access): the items of a conversation
-- (day dividers, the divider "new messages", lines grouped by sender), their heights, which items are in view,
-- links in a text, delivery marks, the mode of a conversation. ChatThread.lua draws what this returns; the
-- caller passes every clock value, the date function and the text measure.
--
-- item = { type = "day"|"new"|"line", top, h, key (day), seq, index, line, first, own, delivery, links, voice }
local _, chat = ...
local FG = chat.FG
if not FG then
  return
end

local TL = {}
chat.ThreadLogic = TL

local Logic = FG.ChatHistoryLogic

TL.GROUP_SECONDS = 300
TL.MAX_CHIPS = 3
TL.CHIP_LABEL_CHARS = 28
TL.MAX_LINK_BYTES = 240
TL.POOL_MAX = 60
TL.END_SLACK = 4
-- Links the thread may open (item tooltips and SetItemRef). Player links and anything else stay text.
TL.LINK_KINDS = {
  item = true,
  spell = true,
  achievement = true,
  quest = true,
  currency = true,
  enchant = true,
  talent = true,
}
TL.DELIVERY = { queued = true, sent = true, waiting = true, failed = true }
-- The voices of the conversation "local" with the entry of the game's ChatTypeInfo and the color that is used
-- when the game gives none (its own defaults). The text color of a voice is lightened until it reads on its card.
TL.VOICE_TYPE = { say = "SAY", yell = "YELL", emote = "EMOTE" }
TL.VOICE_FALLBACK = { say = { 1, 1, 1 }, yell = { 1, 0.25, 0.25 }, emote = { 1, 0.5, 0.25 } }
TL.MIN_CONTRAST = 4.5
-- Modes the thread draws; "mini" is a window of its own (a later package) and reads as compact here.
TL.MODES = { "messenger", "compact" }
-- Measures of the layout in pixels at 100 percent text size, the window scales them with the font.
TL.SPEC = {
  pad = 8,
  stripe = 3,
  padV = 4,
  gap = 6,
  groupGap = 2,
  head = 15,
  chip = 18,
  chipGap = 4,
  chipPad = 12,
  day = 22,
  minLine = 14,
  share = 0.86,
  minCard = 140,
  -- The compact look: lines close together, a thin divider, small chips.
  compact = { gap = 1, divider = 16, chip = 16, chipGap = 2 },
}

-- Height of a chip and the gap above it in a mode (unscaled).
function TL.ChipSize(mode)
  local spec = TL.SPEC
  if mode == "messenger" then
    return spec.chip, spec.chipGap
  end
  return spec.compact.chip, spec.compact.chipGap
end

local function isNumber(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Links of a text that may be opened: { kind, link (the payload for SetItemRef), label }. At most MAX_CHIPS,
-- no link twice. Hidden lines have no text and so no links.
function TL.Links(text)
  local out = {}
  if type(text) ~= "string" or text == "" then
    return out
  end
  local seen = {}
  for payload, label in text:gsub("||", ""):gmatch("|H(.-)|h(.-)|h") do
    local kind = payload:match("^(%a+):")
    if kind and TL.LINK_KINDS[kind] and #payload <= TL.MAX_LINK_BYTES and not seen[payload] then
      label = label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%[", ""):gsub("%]$", "")
      seen[payload] = true
      out[#out + 1] = { kind = kind, link = payload, label = chat.ListLogic.CutChars(label, TL.CHIP_LABEL_CHARS) }
      if #out >= TL.MAX_CHIPS then
        break
      end
    end
  end
  return out
end

local function linear(v)
  return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
end

local function luminance(c)
  return 0.2126 * linear(c[1]) + 0.7152 * linear(c[2]) + 0.0722 * linear(c[3])
end

-- Contrast ratio (WCAG) of two colors { r, g, b } in 0..1.
function TL.Contrast(a, b)
  local la, lb = luminance(a), luminance(b)
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

-- The color lightened toward white until it reads on bg at `min` (default MIN_CONTRAST). Returns r, g, b.
function TL.Readable(color, bg, min)
  min = min or TL.MIN_CONTRAST
  for step = 0, 20 do
    local t = step * 0.05
    local out = {
      color[1] + (1 - color[1]) * t,
      color[2] + (1 - color[2]) * t,
      color[3] + (1 - color[3]) * t,
    }
    if TL.Contrast(out, bg) >= min then
      return out[1], out[2], out[3]
    end
  end
  return 1, 1, 1
end

local function unit(v)
  return type(v) == "number" and v == v and v >= 0 and v <= 1
end

-- The color of a voice on a card of color bg ({ r, g, b }): the entry of the game (`types` is ChatTypeInfo,
-- anything else or a bad entry gives the fallback), made readable. Returns r, g, b.
function TL.VoiceColor(voice, types, bg)
  local key, color = TL.VOICE_TYPE[voice], nil
  if key and type(types) == "table" then
    local ok, entry = pcall(function()
      return types[key]
    end)
    if ok and type(entry) == "table" and unit(entry.r) and unit(entry.g) and unit(entry.b) then
      color = { entry.r, entry.g, entry.b }
    end
  end
  return TL.Readable(color or TL.VOICE_FALLBACK[voice] or TL.VOICE_FALLBACK.say, bg or { 0, 0, 0 })
end

function TL.Delivery(line)
  return TL.DELIVERY[line.delivery] and line.delivery or nil
end

local function same(a, b)
  if a.own ~= b.own then
    return false
  end
  return a.own or (a.line.sender == b.line.sender and a.line.sender ~= nil)
end

-- The items of a conversation in order. opts: date(format, time) (the clock text, default `date`),
-- dividerSeq (first unread line: the divider goes before it), unread (count shown on the divider),
-- deliveryOf(line) (the delivery mark of a line that has none stored, a team keeps its own).
function TL.Build(conv, opts)
  opts = opts or {}
  local dateOf = opts.date or rawget(_G, "date") or os.date
  local items, previous, day = {}, nil, nil
  for i, line in ipairs(conv.lines) do
    local key = isNumber(line.time) and dateOf("%Y-%m-%d", line.time) or "?"
    if key ~= day then
      items[#items + 1] = { type = "day", key = key, time = line.time }
      day, previous = key, nil
    end
    if opts.dividerSeq and line.seq == opts.dividerSeq then
      items[#items + 1] = { type = "new", seq = line.seq, count = opts.unread }
      previous = nil
    end
    local item = {
      type = "line",
      index = i,
      line = line,
      seq = line.seq,
      own = line.dir == Logic.DIR_OUT,
      delivery = opts.deliveryOf and opts.deliveryOf(line) or TL.Delivery(line),
      voice = chat.ListLogic.Voice(conv, line),
    }
    -- A line of the same sender within a few minutes continues the group; a delivery mark needs its head and a
    -- change of the voice (say, yell, emote) starts a new one, the head names the voice.
    item.first = not (
      previous
      and same(previous, item)
      and previous.voice == item.voice
      and not item.delivery
      and isNumber(line.time)
      and isNumber(previous.line.time)
      and line.time - previous.line.time <= TL.GROUP_SECONDS
    )
    if not line.hidden then
      item.links = TL.Links(line.text)
    end
    items[#items + 1] = item
    previous = item
  end
  return items
end

-- Width of the card of a line: most of the thread in the card mode, all of it in the compact mode.
function TL.CardWidth(width, mode)
  if mode ~= "messenger" then
    return width
  end
  local card = math.floor(width * TL.SPEC.share)
  return math.max(math.min(TL.SPEC.minCard, width), math.min(card, width))
end

-- Width for the text of a line inside its card.
function TL.TextWidth(width, mode)
  local spec = TL.SPEC
  if mode ~= "messenger" then
    return math.max(20, width - spec.pad)
  end
  return math.max(20, TL.CardWidth(width, mode) - spec.stripe - 2 * spec.pad)
end

-- Places the chips of a line in one row: { { x, w } } for as many as fit in `width`. widthOf(label) measures
-- a label.
function TL.ChipRow(links, width, widthOf)
  local spec, out, x = TL.SPEC, {}, 0
  for _, link in ipairs(links) do
    local w = math.ceil(widthOf(link.label)) + spec.chipPad
    if x + w > width then
      break
    end
    out[#out + 1] = { x = x, w = w }
    x = x + w + spec.chipGap
  end
  return out
end

-- Heights and tops of the items for a width. m: mode, scale(px) (text size scaling of fixed measures, default
-- identity), measure(text, width, item) -> height of the wrapped text (a yell is set larger), widthOf(label) (chips), text(item) -> the
-- text the line shows. Fills item.top, item.h, item.chips and returns the height of everything.
function TL.Layout(items, width, m)
  local spec = TL.SPEC
  local scale = m.scale or function(v)
    return v
  end
  local textW = TL.TextWidth(width, m.mode)
  local chipW = TL.CardWidth(width, m.mode) - spec.stripe - 2 * spec.pad
  local y, previous = 0, nil
  local chipH, chipGap = TL.ChipSize(m.mode)
  local compact = m.mode ~= "messenger"
  for _, item in ipairs(items) do
    local h
    if item.type == "line" then
      local body = math.max(scale(spec.minLine), m.measure(m.text(item), textW, item))
      item.bodyH = body
      item.chips = item.links and #item.links > 0 and TL.ChipRow(item.links, chipW, m.widthOf) or {}
      local chips = #item.chips > 0 and scale(chipH) + chipGap or 0
      if m.mode == "messenger" then
        h = 2 * spec.padV + (item.first and scale(spec.head) or 0) + body + chips
      else
        h = body + chips
      end
    else
      h = scale(compact and spec.compact.divider or spec.day)
    end
    local gap = 0
    if previous then
      if compact then
        gap = (item.type == "line" and previous.type == "line") and spec.compact.gap or 2
      elseif item.type == "line" and not item.first and previous.type == "line" then
        gap = spec.groupGap
      else
        gap = spec.gap
      end
    end
    y = y + gap
    item.top, item.h = y, h
    y = y + h
    previous = item
  end
  return y
end

-- Indexes of the first and last item that touch the view from offset on, with `extra` pixels on both sides.
-- 0, 0 for no items.
function TL.Visible(items, offset, viewH, extra)
  local n = #items
  if n == 0 then
    return 0, 0
  end
  extra = extra or 0
  local top, bottom = offset - extra, offset + viewH + extra
  local lo, hi = 1, n
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if items[mid].top + items[mid].h < top then
      lo = mid + 1
    else
      hi = mid
    end
  end
  local last = lo
  while last < n and items[last + 1].top <= bottom do
    last = last + 1
  end
  return lo, last
end

function TL.MaxOffset(contentH, viewH)
  return math.max(0, contentH - viewH)
end

function TL.ClampOffset(offset, contentH, viewH)
  return math.max(0, math.min(isNumber(offset) and offset or 0, TL.MaxOffset(contentH, viewH)))
end

function TL.AtEnd(offset, contentH, viewH)
  return offset >= TL.MaxOffset(contentH, viewH) - TL.END_SLACK
end

-- Index of the item that shows the line with this seq (the divider before it when withDivider and there is one).
function TL.IndexOfSeq(items, seq, withDivider)
  for i, item in ipairs(items) do
    if item.type == "line" and item.seq == seq then
      if withDivider and items[i - 1] and items[i - 1].type == "new" then
        return i - 1
      end
      return i
    end
  end
  return nil
end

-- The highest seq of a line within the items first..last, nil without a line.
function TL.LastSeq(items, first, last)
  local seq
  for i = first, last do
    local item = items[i]
    if item and item.type == "line" then
      seq = math.max(seq or 0, item.seq)
    end
  end
  return seq
end

-- Day text kind: "today", "yesterday" or "date" for a day key ("YYYY-MM-DD") against the day of now.
function TL.DayKind(key, now, dateOf)
  dateOf = dateOf or rawget(_G, "date") or os.date
  if key == dateOf("%Y-%m-%d", now) then
    return "today"
  elseif key == dateOf("%Y-%m-%d", now - 86400) then
    return "yesterday"
  end
  return "date"
end

-- The mode a conversation shows: its own setting, else the default of the store, always one of MODES.
function TL.Mode(db, key)
  local view = type(db) == "table" and type(db.view) == "table" and db.view or {}
  local own = type(view.chats) == "table" and view.chats[key] or nil
  local mode = own or view.mode
  return (mode == "compact" or mode == "mini") and "compact" or "messenger"
end

function TL.NextMode(mode)
  return mode == "messenger" and "compact" or "messenger"
end

-- "Lempard#1234" is "Lempard": the BattleTag without its number.
function TL.TagName(tag)
  if type(tag) ~= "string" then
    return nil
  end
  return tag:match("^(.-)#%d+$") or tag
end

-- What is known about a Battle.net partner from an account table of the game (C_BattleNet account info):
-- { tag, character, realm, inGame }. safe(value) drops a secret value (nil). Strings only, nil without a
-- table. inGame: the partner plays WoW right now (nil when the game says nothing about it).
function TL.BnetFacts(account, safe)
  if type(account) ~= "table" then
    return nil
  end
  safe = safe or function(v)
    return v
  end
  local function str(v)
    v = safe(v)
    return type(v) == "string" and v ~= "" and v or nil
  end
  local game = type(account.gameAccountInfo) == "table" and account.gameAccountInfo or {}
  local online = safe(game.isOnline)
  local facts = { tag = str(account.battleTag) }
  if type(online) == "boolean" then
    facts.inGame = online and str(game.clientProgram) == "WoW"
  end
  facts.character = str(game.characterName)
  facts.realm = facts.character and str(game.realmName) or nil
  return facts
end

-- What the header says about a conversation as parts: { key, value }. member is what the guild list
-- knows about the partner (class, level, online, zone), may be nil. Zone only when it reads as text. bnet
-- (optional) is BnetFacts of a Battle.net partner: the BattleTag, the character and whether it plays WoW.
function TL.InfoParts(conv, member, bnet)
  local parts = { { "kind", conv.kind } }
  if conv.kind == "bnet" then
    bnet = type(bnet) == "table" and bnet or {}
    local tag = bnet.tag or conv.tag
    if tag and tag ~= conv.name then
      parts[#parts + 1] = { "tag", tag }
    end
    if bnet.character then
      parts[#parts + 1] = { "character", bnet.realm and (bnet.character .. "-" .. bnet.realm) or bnet.character }
    end
    if type(bnet.inGame) == "boolean" then
      parts[#parts + 1] = { "game", bnet.inGame }
    end
  end
  if conv.kind == "whisper" and type(member) == "table" then
    if type(member.online) == "boolean" then
      parts[#parts + 1] = { "status", member.online and "online" or "offline" }
    end
    if type(member.class) == "string" and member.class ~= "" then
      parts[#parts + 1] = { "class", member.class }
    end
    if isNumber(member.level) and member.level > 0 then
      parts[#parts + 1] = { "level", member.level }
    end
    if member.online and type(member.zone) == "string" and member.zone ~= "" then
      parts[#parts + 1] = { "zone", member.zone }
    end
  end
  parts[#parts + 1] = { "lines", #conv.lines }
  return parts
end

-- Frames the pool needs for a view: enough rows of the lowest height, never more than POOL_MAX.
function TL.PoolSize(viewH, minRow)
  return math.max(4, math.min(TL.POOL_MAX, math.ceil(viewH / math.max(1, minRow)) + 3))
end
