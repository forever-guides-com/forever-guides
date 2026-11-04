-- Sharing between officers of one guild, no game calls: the payloads of the function gmShare (what a
-- message carries and how it is read), the strict decoder, the size budget, the outgoing selection and
-- the inbox. Data of others never lands in the guild record by itself: every valid record becomes an
-- offer in guild.inbox (sender, rank, time, source) that the player adopts or discards. Adopting never
-- overwrites a value typed by hand.
--   H<cats>                       hello, the categories the sender shares (J, M, N)
--   J<rec>;<rec>...               join dates:  <name>,<minDay>,<maxDay>,<source letter>
--   M<rec>;...                    marks:       <name>,<flags> (r returned, i inactive)
--   N<rec>;...                    notes:       <name>,<text>
--   (empty)                       goodbye, the sender withdrew
-- Names and texts are percent-escaped: only letters, digits, "-", "%", "," and ";" occur, so a payload
-- is plain ASCII whatever the player names contain. The envelope and the cut into blocks are CommLogic's.
local _, gm = ...
if not gm.ext then
  return
end
local PN = gm.FG.PlayerName
local DL, ML = gm.DatesLogic, gm.MembersLogic

local SH = {}
gm.ShareLogic = SH

SH.FN = "gmShare"
SH.CATEGORIES = { "J", "M", "N" }
SH.LIMITS = {
  -- One data message: characters (three blocks of CommLogic) and records.
  MAX_PAYLOAD = 660,
  MAX_RECORDS = 30,
  MAX_NAME = 64,
  -- Longest escaped note a record may carry.
  MAX_NOTE_CODE = 500,
  MAX_INBOX = 200,
  MAX_PER_SENDER = 80,
  MAX_SENT = 3000,
  -- Seconds an offer waits in the inbox.
  MAX_AGE = 30 * 86400,
  -- Sender side: seconds between two messages, between two rounds, days until everything is sent again
  -- (an officer who was not there before gets it then), messages of one round.
  SEND_GAP = 20,
  ROUND_GAP = 600,
  FULL_DAYS = 14,
  ROUND_MESSAGES = 40,
  -- Receiver side: messages per sender, burst and seconds per message in the long run.
  RECEIVE_BURST = 6,
  RECEIVE_REFILL = 1 / 15,
}
local LIM = SH.LIMITS

local CAT_SET = { J = true, M = true, N = true }
local SRC_CODE =
  { manual = "m", note = "n", log = "l", chat = "c", diff = "d", roster = "r", baseline = "b", shared = "s" }
local CODE_SRC = {}
for src, code in pairs(SRC_CODE) do
  CODE_SRC[code] = src
end
-- Marks that may travel: the tag and its letter. Everything else (protection, own tags) stays local.
local MARK_CODE = { returned = "r", inactive = "i" }
local CODE_MARK = { r = "returned", i = "inactive" }
local MARK_ORDER = { "returned", "inactive" }
local MIN_DAY = DL.DayFromDate(DL.MIN_YEAR, 1, 1)

-- Escaping ---------------------------------------------------------------------------------------------

local function escape(s)
  return (s:gsub("[^%w%-]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end
SH.Escape = escape

-- Strict reverse of escape: nil for anything that escape could not have made.
local function unescape(s, maxBytes)
  if type(s) ~= "string" or s == "" or s:find("[^%w%%%-]") then
    return nil
  end
  local bad = false
  local out = s:gsub("%%(%x?%x?)", function(hex)
    if not hex:find("^[0-9A-F][0-9A-F]$") then
      bad = true
      return ""
    end
    return string.char(tonumber(hex, 16))
  end)
  if bad or #out > maxBytes then
    return nil
  end
  return out
end

-- A name as a roster has it: no control characters, no pipe, at most MAX_NAME bytes. Returns name, key.
local function readName(field)
  local raw = unescape(field, LIM.MAX_NAME)
  if not raw or raw:find("[%z\1-\31\127|]") then
    return nil
  end
  local name = PN.Normalize(raw)
  if name == "" or name ~= raw and PN.Clean(raw) ~= raw then
    return nil
  end
  return name, PN.Lower(name)
end

local function whole(v)
  return type(v) == "number" and v == v and v >= 0 and v == math.floor(v) and v or nil
end

local function split(text, sep)
  local out, from = {}, 1
  while true do
    local at = text:find(sep, from, true)
    if not at then
      out[#out + 1] = text:sub(from)
      return out
    end
    out[#out + 1] = text:sub(from, at - 1)
    from = at + 1
  end
end

-- Decoding ---------------------------------------------------------------------------------------------

local function readDay(field, today)
  if field == "" then
    return nil, true
  end
  if not field:find("^%d%d?%d?%d?%d?%d?$") then
    return nil, false
  end
  local day = tonumber(field)
  -- A day ahead is allowed: the sender's local day may run ahead of ours.
  if day < MIN_DAY or day > today + 1 then
    return nil, false
  end
  return day, true
end

local readers = {}

function readers.J(fields, today)
  if #fields ~= 4 then
    return nil
  end
  local name, key = readName(fields[1])
  local lo, okLo = readDay(fields[2], today)
  local hi, okHi = readDay(fields[3], today)
  local src = CODE_SRC[fields[4]]
  if not (name and okLo and okHi and src) or (not lo and not hi) or (lo and hi and hi < lo) then
    return nil
  end
  return { name = name, key = key, minDay = lo, maxDay = hi, src = src }
end

function readers.M(fields)
  if #fields ~= 2 or fields[2] == "" or #fields[2] > #MARK_ORDER then
    return nil
  end
  local name, key = readName(fields[1])
  local tags, seen = {}, {}
  for code in fields[2]:gmatch(".") do
    if not CODE_MARK[code] or seen[code] then
      return nil
    end
    seen[code] = true
    tags[#tags + 1] = CODE_MARK[code]
  end
  if not name then
    return nil
  end
  return { name = name, key = key, tags = tags }
end

function readers.N(fields)
  if #fields ~= 2 or #fields[2] > LIM.MAX_NOTE_CODE then
    return nil
  end
  local name, key = readName(fields[1])
  local raw = unescape(fields[2], ML.MAX_NOTE * 4)
  local text = raw and ML.CleanNote(raw)
  if not name or not text or text == "" then
    return nil
  end
  return { name = name, key = key, text = text }
end

-- One payload (any type) as { kind = "hello", cats }, { kind = "bye" } or { kind = "data", cat, rows };
-- nil for everything that is not exactly what an encoder makes. today: the day number of today. A single
-- bad record refuses the whole message. Never raises.
function SH.Decode(payload, today)
  if type(payload) ~= "string" or #payload > LIM.MAX_PAYLOAD or not whole(today) then
    return nil
  end
  if payload == "" then
    return { kind = "bye" }
  end
  if payload:find("[^%w%%%-,;]") then
    return nil
  end
  local head, rest = payload:sub(1, 1), payload:sub(2)
  if head == "H" then
    local cats = {}
    if rest == "" or #rest > #SH.CATEGORIES then
      return nil
    end
    for c in rest:gmatch(".") do
      if not CAT_SET[c] or cats[c] then
        return nil
      end
      cats[c] = true
    end
    return { kind = "hello", cats = cats }
  end
  local read = readers[head]
  if not read then
    return nil
  end
  local rows, names = {}, {}
  for _, record in ipairs(split(rest, ";")) do
    local row = record ~= "" and read(split(record, ","), today)
    if not row or names[row.key] or #rows >= LIM.MAX_RECORDS then
      return nil
    end
    names[row.key] = true
    rows[#rows + 1] = row
  end
  return { kind = "data", cat = head, rows = rows }
end

-- Sender rank ------------------------------------------------------------------------------------------

-- True when the sender stands at or above the chosen rank (index 0 is the guild master); an unknown
-- rank never passes.
function SH.RankAllowed(rankIndex, limit)
  rankIndex = whole(rankIndex)
  limit = whole(limit)
  return rankIndex ~= nil and limit ~= nil and rankIndex <= limit
end

-- Outgoing ---------------------------------------------------------------------------------------------

local function dayText(v)
  return v and tostring(v) or ""
end

-- The record of one member for one category: key, signature (what changed means a new signature) and
-- text. nil when the member has nothing of it to share.
local function build(cat, e)
  local name = escape(e.name)
  if cat == "J" then
    local info = DL.Clean(e.joined)
    if not info or info.src == "shared" then
      return nil
    end
    local sig = string.format("%s,%s,%s", dayText(info.minDay), dayText(info.maxDay), SRC_CODE[info.src] or "s")
    return sig, name .. "," .. sig
  elseif cat == "M" then
    local flags = {}
    for _, tag in ipairs(MARK_ORDER) do
      if type(e.tags) == "table" and e.tags[tag] == true then
        flags[#flags + 1] = MARK_CODE[tag]
      end
    end
    if #flags == 0 then
      return nil
    end
    local sig = table.concat(flags)
    return sig, name .. "," .. sig
  end
  local note = type(e.note) == "string" and e.note or ""
  local code = note ~= "" and escape(note)
  if not code or #code > LIM.MAX_NOTE_CODE then
    return nil
  end
  return code, name .. "," .. code
end

-- What this client may say: the records of the members on the roster (`roster` is a set of keys) in the
-- chosen categories (`cats` = { J = true ... }) that differ from what `sent` ([cat .. key] = signature)
-- says went out before. Sorted, stable. Own received data never goes on: a date with the source
-- "shared" is skipped.
function SH.Collect(guild, roster, cats, sent)
  local out = {}
  sent = type(sent) == "table" and sent or {}
  local keys = {}
  for key in pairs(guild.members) do
    if roster[key] then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  for _, cat in ipairs(SH.CATEGORIES) do
    if cats[cat] then
      for _, key in ipairs(keys) do
        local sig, text = build(cat, guild.members[key])
        if sig and sent[cat .. key] ~= sig then
          out[#out + 1] = { cat = cat, key = key, sig = sig, text = text }
        end
      end
    end
  end
  return out
end

-- Cuts records (one category each, in order) into payloads of at most MAX_PAYLOAD characters and
-- MAX_RECORDS records. Returns a list of { cat, payload, records = { record... } }.
function SH.Batches(records)
  local out, cur = {}, nil
  for _, rec in ipairs(records) do
    if #rec.text + 2 <= LIM.MAX_PAYLOAD then
      if
        cur and (cur.cat ~= rec.cat or #cur.records >= LIM.MAX_RECORDS or cur.size + #rec.text + 1 > LIM.MAX_PAYLOAD)
      then
        cur = nil
      end
      if not cur then
        cur = { cat = rec.cat, records = {}, size = 1 }
        out[#out + 1] = cur
      end
      cur.records[#cur.records + 1] = rec
      cur.size = cur.size + #rec.text + 1
    end
  end
  for _, batch in ipairs(out) do
    local texts = {}
    for i, rec in ipairs(batch.records) do
      texts[i] = rec.text
    end
    batch.payload = batch.cat .. table.concat(texts, ";")
    batch.size = nil
  end
  return out
end

-- The hello that opens a round: the categories in the order J, M, N.
function SH.Hello(cats)
  local out = {}
  for _, c in ipairs(SH.CATEGORIES) do
    if cats[c] then
      out[#out + 1] = c
    end
  end
  return #out > 0 and "H" .. table.concat(out) or nil
end

-- Marks the records of a batch as sent (in place), within MAX_SENT entries.
function SH.NoteSent(sent, batch)
  local n = 0
  for _ in pairs(sent) do
    n = n + 1
  end
  for _, rec in ipairs(batch.records) do
    if sent[rec.cat .. rec.key] == nil then
      if n >= LIM.MAX_SENT then
        return false
      end
      n = n + 1
    end
    sent[rec.cat .. rec.key] = rec.sig
  end
  return true
end

-- Inbox ------------------------------------------------------------------------------------------------

local function sameDate(a, b)
  return (a == nil) == (b == nil) and (a == nil or (a.minDay == b.minDay and a.maxDay == b.maxDay and a.src == b.src))
end

-- What an offer would change: true when adopting it adds something to the record. Hand input is never
-- touched, so a note that exists already (other text) and a manual date make an offer worthless.
local function adds(guild, row, cat, today)
  local e = guild.members[row.key]
  if cat == "J" then
    local own = e and DL.Clean(e.joined)
    local info = DL.Info(row.minDay, row.maxDay, "shared", today)
    local merged = info and DL.Merge(own, info, today)
    return merged ~= nil and not sameDate(own, merged)
  elseif cat == "M" then
    for _, tag in ipairs(row.tags) do
      if not (e and type(e.tags) == "table" and e.tags[tag]) then
        return true
      end
    end
    return false
  end
  return e == nil or e.note == "" or e.note == nil
end

local function sameValue(a, b)
  if a.cat ~= b.cat or a.key ~= b.key then
    return false
  end
  if a.cat == "J" then
    return a.minDay == b.minDay and a.maxDay == b.maxDay
  elseif a.cat == "M" then
    return table.concat(a.tags, ",") == table.concat(b.tags, ",")
  end
  return a.text == b.text
end

local function dropOldest(inbox, test)
  local at
  for i, offer in ipairs(inbox) do
    if test(offer) and (not at or offer.t < inbox[at].t) then
      at = i
    end
  end
  if at then
    table.remove(inbox, at)
  end
  return at ~= nil
end

-- Drops offers older than MAX_AGE. Returns how many went.
function SH.Prune(guild, now)
  local inbox, n = guild.inbox, 0
  for i = #inbox, 1, -1 do
    if now - inbox[i].t > LIM.MAX_AGE then
      table.remove(inbox, i)
      n = n + 1
    end
  end
  return n
end

-- Puts the rows of a valid message into the inbox of the guild. from = { name, key, rank (name of the
-- rank), rankIndex }, ctx = { now (seconds), today (day), roster (set of keys) }. A row about nobody on the
-- roster, one that adds nothing, or one that repeats another sender's offer (that one only counts it) is
-- not stored; the same sender's older offer for the same member is replaced. Returns added, skipped.
function SH.Accept(guild, cat, rows, from, ctx)
  local inbox, added, skipped = guild.inbox, 0, 0
  SH.Prune(guild, ctx.now)
  for _, row in ipairs(rows) do
    local offer = {
      from = from.name,
      fromKey = from.key,
      rank = from.rank,
      rankIndex = from.rankIndex,
      t = ctx.now,
      cat = cat,
      key = row.key,
      name = row.name,
      minDay = row.minDay,
      maxDay = row.maxDay,
      src = row.src,
      tags = row.tags,
      text = row.text,
    }
    local dup
    for i = #inbox, 1, -1 do
      local old = inbox[i]
      if old.cat == cat and old.key == row.key then
        if old.fromKey == from.key then
          table.remove(inbox, i)
        elseif sameValue(old, offer) then
          dup = old
        end
      end
    end
    if not ctx.roster[row.key] or not adds(guild, row, cat, ctx.today) then
      skipped = skipped + 1
    elseif dup then
      dup.also = (dup.also or 0) + 1
      skipped = skipped + 1
    else
      local mine = 0
      for _, old in ipairs(inbox) do
        if old.fromKey == from.key then
          mine = mine + 1
        end
      end
      if mine >= LIM.MAX_PER_SENDER then
        dropOldest(inbox, function(o)
          return o.fromKey == from.key
        end)
      end
      if #inbox >= LIM.MAX_INBOX then
        dropOldest(inbox, function()
          return true
        end)
      end
      inbox[#inbox + 1] = offer
      added = added + 1
    end
  end
  return added, skipped
end

local function indexOf(inbox, offer)
  for i, o in ipairs(inbox) do
    if o == offer then
      return i
    end
  end
end

-- Takes one offer over into the guild record and removes it from the inbox. Returns true, or false and
-- why: "gone" (not in the inbox), "same" (nothing to add any more), "conflict" (a note is there now).
function SH.Adopt(guild, offer, today)
  local at = indexOf(guild.inbox, offer)
  if not at then
    return false, "gone"
  end
  table.remove(guild.inbox, at)
  local members, member = guild.members, { key = offer.key, name = offer.name }
  if offer.cat == "J" then
    local e = members[offer.key]
    local own = e and DL.Clean(e.joined)
    local info = DL.Info(offer.minDay, offer.maxDay, "shared", today)
    local merged = info and DL.Merge(own, info, today)
    if not merged or sameDate(own, merged) then
      return false, "same"
    end
    ML.Touch(members, member).joined = merged
  elseif offer.cat == "M" then
    local e, changed = ML.Touch(members, member), false
    e.tags = type(e.tags) == "table" and e.tags or {}
    for _, tag in ipairs(offer.tags) do
      if not e.tags[tag] then
        e.tags[tag], changed = true, true
      end
    end
    if not changed then
      ML.Keep(members, offer.key)
      return false, "same"
    end
  else
    local e = members[offer.key]
    if e and e.note ~= "" then
      return false, "conflict"
    end
    ML.SetNote(members, member, offer.text)
  end
  return true
end

function SH.Discard(guild, offer)
  local at = indexOf(guild.inbox, offer)
  if at then
    table.remove(guild.inbox, at)
  end
  return at ~= nil
end

-- Empties the inbox, or only what one sender (key) sent. Returns how many offers went.
function SH.DiscardAll(guild, fromKey)
  local inbox, n = guild.inbox, 0
  for i = #inbox, 1, -1 do
    if fromKey == nil or inbox[i].fromKey == fromKey then
      table.remove(inbox, i)
      n = n + 1
    end
  end
  return n
end

-- Everything the sharing stored: inbox, what went out, counters. Settings stay.
function SH.Wipe(guild)
  guild.inbox = {}
  guild.share = {}
end

function SH.Counts(guild)
  local c = guild.share.counts
  return { sent = whole(c and c.sent) or 0, received = whole(c and c.received) or 0 }
end

function SH.Count(guild, field, n)
  guild.share.counts = type(guild.share.counts) == "table" and guild.share.counts or {}
  guild.share.counts[field] = (whole(guild.share.counts[field]) or 0) + n
end

-- Text of what an offer says, "Join date: ..." and so on; L is the locale table, format a date format.
function SH.What(offer, L, format)
  if offer.cat == "J" then
    return string.format(L["gm.share.what.J"], DL.Text(DL.Info(offer.minDay, offer.maxDay, "shared"), L, format))
  elseif offer.cat == "M" then
    local names = {}
    for i, tag in ipairs(offer.tags) do
      names[i] = L["gm.tag." .. tag] or tag
    end
    return string.format(L["gm.share.what.M"], table.concat(names, ", "))
  end
  return string.format(L["gm.share.what.N"], offer.text)
end

-- Repair of stored data ---------------------------------------------------------------------------------

local function cleanOffer(o)
  if type(o) ~= "table" or not CAT_SET[o.cat] or type(o.key) ~= "string" or o.key == "" then
    return nil
  end
  if type(o.from) ~= "string" or type(o.fromKey) ~= "string" or not whole(o.t) then
    return nil
  end
  local out = {
    from = PN.Cut(PN.Clean(o.from), LIM.MAX_NAME),
    fromKey = o.fromKey,
    rank = type(o.rank) == "string" and PN.Cut(o.rank:gsub("[%c|]", ""), 32) or "",
    rankIndex = whole(o.rankIndex),
    t = o.t,
    cat = o.cat,
    key = o.key,
    name = type(o.name) == "string" and o.name ~= "" and PN.Cut(PN.Clean(o.name), LIM.MAX_NAME) or o.key,
    also = whole(o.also),
  }
  if o.cat == "J" then
    local info = DL.Info(o.minDay, o.maxDay, o.src)
    if not info or not SRC_CODE[info.src] then
      return nil
    end
    out.minDay, out.maxDay, out.src = info.minDay, info.maxDay, info.src
  elseif o.cat == "M" then
    local tags = {}
    for _, tag in ipairs(type(o.tags) == "table" and o.tags or {}) do
      if MARK_CODE[tag] then
        tags[#tags + 1] = tag
      end
    end
    if #tags == 0 then
      return nil
    end
    out.tags = tags
  else
    out.text = type(o.text) == "string" and ML.CleanNote(o.text) or ""
    if out.text == "" then
      return nil
    end
  end
  return out
end

-- Brings guild.inbox and guild.share into shape, in place.
function SH.Clean(guild)
  local inbox = {}
  for _, o in ipairs(type(guild.inbox) == "table" and guild.inbox or {}) do
    local clean = cleanOffer(o)
    if clean and #inbox < LIM.MAX_INBOX then
      inbox[#inbox + 1] = clean
    end
  end
  guild.inbox = inbox
  local share = type(guild.share) == "table" and guild.share or {}
  local sent, n = {}, 0
  for k, v in pairs(type(share.sent) == "table" and share.sent or {}) do
    if type(k) == "string" and type(v) == "string" and #k <= 80 and #v <= 40 and n < LIM.MAX_SENT then
      sent[k], n = v, n + 1
    end
  end
  share.sent = sent
  share.full = whole(share.full)
  local counts = type(share.counts) == "table" and share.counts or {}
  share.counts = { sent = whole(counts.sent) or 0, received = whole(counts.received) or 0 }
  guild.share = share
end

local clean = gm.CleanGuild
if clean then
  function gm.CleanGuild(guild)
    clean(guild)
    SH.Clean(guild)
  end
end
