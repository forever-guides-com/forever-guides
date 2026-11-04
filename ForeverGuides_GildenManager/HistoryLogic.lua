-- What happened in the guild, no game calls: roster comparison with a guard against partial rosters,
-- chat system messages, notes with a join marker, the server guild log, de-duplicated events and the
-- dates they give a member (see DatesLogic). Nothing in here reads or changes the game; History.lua
-- feeds it and writes the result into the guild record.
--
-- Event = { day, kind, key, name, src, from, to, by, toRank, days, fuzz }
--   kind: "join", "leave", "remove", "promote", "demote", "rename", "note", "return"
--   src:  "diff", "chat", "log"; fuzz: the event lies in [day - fuzz, day] (nil = exactly day)
-- guild.seen[key] = { name, rank, rankName, level, guid, np, no, off, miss }: the roster as of the
-- last valid snapshot (np/no: checksums of public and officer note, off: days offline).
local _, gm = ...
if not gm.ext then
  return
end
local DL, GS, ML = gm.DatesLogic, gm.GuildStore, gm.MembersLogic
local PN, U = gm.FG.PlayerName, gm.FG.U

local HL = {}
gm.HistoryLogic = HL

HL.KINDS = { "join", "leave", "remove", "promote", "demote", "rename", "note", "return" }
HL.SOURCES = { "diff", "chat", "log" }
-- Seconds without a roster update before a snapshot counts (the server sends the roster in parts).
HL.MIN_QUIET = 10
-- A change of the member count above this share (at least JUMP_MIN) needs a second snapshot.
HL.JUMP_PERCENT = 15
HL.JUMP_MIN = 5
-- A member offline for this many days who comes back is marked "returned".
HL.RETURN_DAYS = 60
HL.MAX_NOTE_EVENTS = 20
HL.MAX_LOG = 200
HL.MAX_LINES = 500
HL.MAX_NAME = 40

local KIND, SOURCE = {}, {}
for _, k in ipairs(HL.KINDS) do
  KIND[k] = true
end
for _, s in ipairs(HL.SOURCES) do
  SOURCE[s] = true
end

local function whole(v)
  return type(v) == "number" and v == v and v >= 0 and v < math.huge and v == math.floor(v) and v or nil
end

local function str(v, limit)
  if type(v) ~= "string" then
    return ""
  end
  v = (v:gsub("[%z\1-\31\127|]", " "))
  return PN.Cut(U.trim(v), limit or HL.MAX_NAME)
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

-- Cleaning --------------------------------------------------------------------------------------------

-- Sum of a text, small enough to keep per member (changes of notes, never the text).
function HL.Sum(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 4294967296
  end
  return h
end

-- The GUID without its "Player-" prefix, nil for no usable value.
function HL.ShortGuid(guid)
  if type(guid) ~= "string" or guid == "" or #guid > 64 or guid:find("[%z\1-\31\127|]") then
    return nil
  end
  return (guid:gsub("^Player%-", ""))
end

-- Repairs one event in place; nil when it is unusable.
function HL.CleanEvent(e)
  if type(e) ~= "table" or not KIND[e.kind] or not whole(e.day) or type(e.key) ~= "string" or e.key == "" then
    return nil
  end
  e.key = PN.Cut(e.key, 100)
  e.name = str(e.name)
  e.src = SOURCE[e.src] and e.src or "diff"
  for _, field in ipairs({ "from", "to", "by" }) do
    e[field] = e[field] ~= nil and str(e[field]) or nil
  end
  e.toRank, e.days = whole(e.toRank), whole(e.days)
  e.fuzz = whole(e.fuzz) and e.fuzz > 0 and math.min(e.fuzz, e.day) or nil
  return e
end

local function sortEvents(list)
  local order = {}
  for i, e in ipairs(list) do
    order[e] = i
  end
  table.sort(list, function(a, b)
    if a.day ~= b.day then
      return a.day < b.day
    end
    return order[a] < order[b]
  end)
end

local function cleanSeen(seen)
  for key, e in pairs(seen) do
    if type(key) ~= "string" or key == "" or type(e) ~= "table" then
      seen[key] = nil
    else
      e.name = str(e.name) ~= "" and str(e.name) or key
      e.rankName = str(e.rankName)
      e.rank, e.level = whole(e.rank), whole(e.level)
      e.guid = HL.ShortGuid(e.guid)
      e.np, e.no, e.off, e.miss = whole(e.np), whole(e.no), whole(e.off), whole(e.miss)
    end
  end
end

-- Brings events, the seen list and the guid map of a guild record into shape and inside the limit.
function HL.Clean(guild)
  local events = {}
  for _, e in ipairs(guild.events) do
    if HL.CleanEvent(e) then
      events[#events + 1] = e
    end
  end
  sortEvents(events)
  guild.events = GS.Trim(events, GS.Limit(guild, "maxEvents"))
  cleanSeen(guild.seen)
  for guid, key in pairs(guild.idByGuid) do
    if type(guid) ~= "string" or type(key) ~= "string" then
      guild.idByGuid[guid] = nil
    end
  end
end

-- Repairs the dates and marks of a member entry in place.
function HL.CleanMember(e)
  for _, field in ipairs({ "joined", "rankSince" }) do
    if e[field] ~= nil then
      e[field] = DL.Clean(e[field])
    end
  end
  e.returnedDay, e.returnedAfter = whole(e.returnedDay), whole(e.returnedAfter)
  if type(e.tags) ~= "table" or next(e.tags) == nil then
    e.tags = nil
  end
  if type(e.left) ~= "table" or not whole(e.left.day) then
    e.left = nil
  end
end

-- Events ----------------------------------------------------------------------------------------------

-- Same happening reported twice: same kind and member and the same day, or windows that overlap when
-- the sources differ (a roster comparison only knows the days since the last look) or both are the
-- server log (the window of an old entry moves a little with every read).
function HL.SameEvent(a, b)
  if a.kind ~= b.kind or a.key ~= b.key then
    return false
  end
  if a.day == b.day then
    return true
  end
  return (a.src ~= b.src or a.src == "log") and a.day - (a.fuzz or 0) <= b.day and b.day - (b.fuzz or 0) <= a.day
end

local function absorb(old, new)
  local lo = math.max(old.day - (old.fuzz or 0), new.day - (new.fuzz or 0))
  local hi = math.min(old.day, new.day)
  if lo <= hi then
    local narrower = (new.fuzz or 0) < (old.fuzz or 0)
    old.day, old.fuzz = hi, hi > lo and hi - lo or nil
    if narrower then
      old.src = new.src
    end
  end
  -- The newer report fills gaps and, being the active one, corrects the rest.
  for _, field in ipairs({ "name", "from", "to", "by", "toRank", "days" }) do
    if new[field] ~= nil and new[field] ~= "" then
      old[field] = new[field]
    end
  end
end

-- Adds the events of `list` to `events` (time order, oldest first) and cuts to `limit`. A duplicate
-- is merged into the entry that exists, the incoming one wins where they differ. Returns the number
-- of events that were new.
function HL.AddEvents(events, list, limit)
  local index, added, unsorted = {}, 0, false
  for _, e in ipairs(events) do
    local k = e.kind .. "|" .. e.key
    index[k] = index[k] or {}
    index[k][#index[k] + 1] = e
  end
  for _, raw in ipairs(list) do
    local e = HL.CleanEvent(U.copy(raw))
    if e then
      local k = e.kind .. "|" .. e.key
      local twin
      for _, old in ipairs(index[k] or {}) do
        if HL.SameEvent(old, e) then
          twin = old
          break
        end
      end
      if twin then
        local day = twin.day
        absorb(twin, e)
        unsorted = unsorted or twin.day ~= day
      else
        if #events > 0 and e.day < events[#events].day then
          unsorted = true
        end
        events[#events + 1] = e
        index[k] = index[k] or {}
        index[k][#index[k] + 1] = e
        added = added + 1
      end
    end
  end
  if unsorted then
    sortEvents(events)
  end
  GS.Trim(events, limit)
  return added
end

-- Roster comparison -----------------------------------------------------------------------------------

-- Days a roster row has been offline as far as known (0 online), nil when unknown.
function HL.OfflineDays(m)
  if m.online then
    return 0
  elseif whole(m.agoMin) then
    return math.floor(m.agoMin / 1440)
  elseif type(m.last) == "table" then
    return (DL.AgeBounds(m.last.years, m.last.months, m.last.days))
  end
end

-- True when a member offline for `before` days is back: before reached `days`, now below it, and by
-- at least a week (the server rounds months, a day or two of wobble is no return).
function HL.Returned(before, now, days)
  days = whole(days) or HL.RETURN_DAYS
  return whole(before) ~= nil and whole(now) ~= nil and before >= days and now < days and before - now >= 7
end

local function moved(p, row)
  if p.rank == nil or p.rank == row.rank then
    return false
  end
  return p.rankName == "" or row.rankName == "" or p.rankName ~= row.rankName
end

-- Compares a roster snapshot with the stored one.
--   state = { seen, idByGuid, firstScanDay, lastScanDay, lastScanCount }
--   snap  = { loaded, inGuild, total, members = { row... } } (rows as GuildData reads them)
--   ctx   = { today, quiet (seconds since the last roster update), combat, officerRead, returnDays,
--             candidate (member count of the last snapshot that jumped) }
-- Answers a result, or nil and why nothing may be booked: "combat", "noGuild", "notLoaded", "quiet",
-- "noTotal", "partial" (fewer rows than members: a filter or unreadable rows) and "jump" (the count
-- moved a lot; the third value is the count to hand back as ctx.candidate with the next snapshot).
-- A departure counts only after two valid snapshots without the member. Nothing is written.
function HL.Diff(state, snap, ctx)
  if ctx.combat then
    return nil, "combat"
  end
  if type(snap) ~= "table" or snap.inGuild == false then
    return nil, "noGuild"
  end
  local rows = snap.members
  if not snap.loaded or type(rows) ~= "table" or #rows == 0 then
    return nil, "notLoaded"
  end
  if (ctx.quiet or 0) < HL.MIN_QUIET then
    return nil, "quiet"
  end
  if not whole(snap.total) then
    return nil, "noTotal"
  end
  if #rows ~= snap.total then
    return nil, "partial"
  end
  local prev, today = state.seen or {}, ctx.today
  local baseline = next(prev) == nil
  local last = state.lastScanCount or 0
  if not baseline and last > 0 then
    local allowed = math.max(HL.JUMP_MIN, math.ceil(last * HL.JUMP_PERCENT / 100))
    if math.abs(#rows - last) > allowed and ctx.candidate ~= #rows then
      return nil, "jump", #rows
    end
  end

  local cur = {}
  for _, row in ipairs(rows) do
    if cur[row.key] == nil then
      cur[row.key] = row
    end
  end
  local keys = sortedKeys(cur)
  local lastDay = whole(state.lastScanDay) and state.lastScanDay > 0 and state.lastScanDay or nil
  local fuzz = lastDay and today - lastDay or nil
  local res = {
    ok = true,
    count = #rows,
    baseline = baseline,
    seen = {},
    idByGuid = {},
    events = {},
    joined = {},
    rankSince = {},
    fresh = {},
    renamed = {},
    returned = {},
    left = {},
    leftName = {},
  }
  local function event(kind, key, name, extra)
    local e = { day = today, fuzz = fuzz, kind = kind, key = key, name = name, src = "diff" }
    for k, v in pairs(extra or {}) do
      e[k] = v
    end
    res.events[#res.events + 1] = e
  end

  -- A new key with a known guid that belonged to a key that is gone: a rename, not a join.
  local ids = state.idByGuid or {}
  local renameOf, consumed = {}, {}
  for _, key in ipairs(keys) do
    local g = HL.ShortGuid(cur[key].guid)
    local old = g and ids[g]
    if old and old ~= key and prev[old] and not prev[key] and not cur[old] and not consumed[old] then
      renameOf[key], consumed[old] = old, true
    end
  end

  -- A restructured rank list moves many members at once: no promotions then.
  local movers = 0
  for _, key in ipairs(keys) do
    local p = prev[renameOf[key] or key]
    if p and moved(p, cur[key]) then
      movers = movers + 1
    end
  end
  local mass = movers > math.max(10, math.floor(#rows / 4))

  local firstDay = whole(state.firstScanDay) and state.firstScanDay > 0 and state.firstScanDay or today
  local noteEvents = 0
  for _, key in ipairs(keys) do
    local row = cur[key]
    local g = HL.ShortGuid(row.guid)
    local old = renameOf[key]
    local p = prev[old or key]
    local entry = {
      name = row.name,
      rank = whole(row.rank),
      rankName = row.rankName or "",
      level = whole(row.level),
      guid = g,
      np = HL.Sum(row.note or ""),
      no = ctx.officerRead and HL.Sum(row.officerNote or "") or nil,
      off = HL.OfflineDays(row),
    }
    res.seen[key] = entry
    if g then
      res.idByGuid[g] = key
    end
    if baseline then
      res.joined[key] = DL.Info(nil, firstDay, "baseline", today)
      res.rankSince[key] = DL.Info(nil, firstDay, "baseline", today)
    elseif not p then
      event("join", key, row.name)
      res.fresh[key] = true
      res.joined[key] = DL.Info(lastDay, today, "diff", today)
      res.rankSince[key] = DL.Info(lastDay, today, "diff", today)
    else
      if old then
        event("rename", key, row.name, { from = p.name })
        res.renamed[#res.renamed + 1] = { from = old, to = key, name = row.name }
      end
      if moved(p, row) and not mass then
        event(row.rank < p.rank and "promote" or "demote", key, row.name, { from = p.rankName, to = row.rankName })
        res.rankSince[key] = DL.Info(lastDay, today, "diff", today)
      end
      local pub = p.np ~= nil and p.np ~= entry.np
      local off = p.no ~= nil and entry.no ~= nil and p.no ~= entry.no
      if (pub or off) and noteEvents < HL.MAX_NOTE_EVENTS then
        noteEvents = noteEvents + 1
        event("note", key, row.name, { to = (pub and off) and "both" or (pub and "public" or "officer") })
      end
      if HL.Returned(p.off, entry.off, ctx.returnDays) then
        event("return", key, row.name, { days = p.off })
        res.returned[key] = p.off
      end
    end
  end

  -- Members of the last snapshot that are not in this one.
  for _, key in ipairs(sortedKeys(prev)) do
    local p = prev[key]
    if not cur[key] and not consumed[key] then
      local miss = (p.miss or 0) + 1
      if miss >= 2 then
        -- The last known rank name goes with the event so the former-members list can show it.
        event("leave", key, p.name, p.rankName and p.rankName ~= "" and { from = p.rankName } or nil)
        res.left[key], res.leftName[key] = { day = today, reason = "left" }, p.name
      else
        res.seen[key] = U.copy(p)
        res.seen[key].miss = miss
        if p.guid then
          res.idByGuid[p.guid] = res.idByGuid[p.guid] or key
        end
      end
    end
  end
  return res
end

-- Writes the result of Diff into the guild record (events, seen list, dates and marks of members).
function HL.Apply(guild, res, today)
  guild.seen, guild.idByGuid = res.seen, res.idByGuid
  guild.lastScanDay, guild.lastScanCount = today, res.count
  if not whole(guild.firstScanDay) or guild.firstScanDay == 0 then
    guild.firstScanDay = today
  end
  local members = guild.members
  for _, r in ipairs(res.renamed) do
    local e = members[r.from]
    if e and not members[r.to] then
      members[r.to], members[r.from] = e, nil
      e.name = r.name
    end
    for _, other in pairs(members) do
      if other.mainKey == r.from then
        other.main, other.mainKey = r.name, r.to
      end
    end
  end
  local function entry(key)
    return ML.Touch(members, { key = key, name = res.seen[key] and res.seen[key].name or key })
  end
  -- A date found since the last look narrows the new one; an older one belongs to an earlier state.
  local function renew(e, field, info)
    local old = e[field]
    local since = info.minDay or info.setDay
    -- Found after the last look; on the very day of it only what a message told, not what the look found.
    local recent = old
      and old.setDay
      and (old.setDay > since or (old.setDay == since and old.src ~= "diff" and old.src ~= "baseline"))
    e[field] = recent and DL.Merge(old, info, info.setDay) or info
  end
  for _, key in ipairs(sortedKeys(res.joined)) do
    local e = entry(key)
    if res.baseline then
      e.joined = DL.Merge(e.joined, res.joined[key], today)
    else
      renew(e, "joined", res.joined[key])
      e.left = nil
    end
  end
  for _, key in ipairs(sortedKeys(res.rankSince)) do
    local e = entry(key)
    if res.baseline then
      e.rankSince = DL.Merge(e.rankSince, res.rankSince[key], today)
    else
      renew(e, "rankSince", res.rankSince[key])
    end
  end
  for key, days in pairs(res.returned) do
    local e = entry(key)
    e.tags = e.tags or {}
    e.tags.returned, e.returnedDay = true, today
    e.returnedAfter = days
  end
  for key, left in pairs(res.left) do
    ML.Touch(members, { key = key, name = res.leftName[key] or key }).left = left
  end
  HL.AddEvents(guild.events, res.events, GS.Limit(guild, "maxEvents"))
end

-- Notes -----------------------------------------------------------------------------------------------

-- Words in front of a date that mark it as the join date (lower case).
HL.NOTE_MARKERS =
  { j = true, join = true, joined = true, beitritt = true, eingetreten = true, seit = true, since = true }

local DATE_SHAPES = {
  "%d%d%d%d%-%d%d?%-%d%d?",
  "%d%d?%.%d%d?%.%d%d%d%d",
  "%d%d?%.%d%d?%.%d%d",
  "%d%d?/%d%d?/%d%d%d%d",
  "%d%d?/%d%d?/%d%d",
}

-- Reads a join date from a guild note: a marker word, optional ":", then DD.MM.YYYY, DD.MM.YY,
-- YYYY-MM-DD or a slash date ("J:12.03.2024", "Beitritt 2024-03-12"). Only reads, never writes.
-- opts: order ("dmy" or "mdy" for slash dates), today, markers (set of lower case words), bare (a note
-- that is only a date counts). Answers day and the part of the note that gave it, or nil and a
-- reason: "none", "invalid", "ambiguous", "range", "future".
function HL.NoteDate(note, opts)
  opts = opts or {}
  if type(note) ~= "string" or note == "" then
    return nil, "none"
  end
  local markers = opts.markers or HL.NOTE_MARKERS
  local lower, tokens = note:lower(), {}
  for _, shape in ipairs(DATE_SHAPES) do
    local from = 1
    while true do
      local a, b = note:find(shape, from)
      if not a then
        break
      end
      local before, after = note:sub(a - 1, a - 1), note:sub(b + 1, b + 1)
      if not before:find("[%d%.%-/]") and not after:find("[%d]") then
        tokens[#tokens + 1] = { a = a, b = b }
      end
      from = b + 1
    end
  end
  table.sort(tokens, function(x, y)
    return x.a < y.a
  end)
  local reason = "none"
  for _, t in ipairs(tokens) do
    local head = lower:sub(1, t.a - 1):gsub("[%s:=%-]+$", "")
    local word = head:match("(%a+)$")
    local marked = word ~= nil and markers[word] == true
    local from = marked and t.a - (#lower:sub(1, t.a - 1) - #head) - #word or t.a
    if marked or (opts.bare and U.trim(note) == note:sub(t.a, t.b)) then
      local day, why = DL.ParseDate(note:sub(t.a, t.b), opts.order, opts.today)
      if day then
        return day, note:sub(from, t.b)
      end
      reason = why
    end
  end
  return nil, reason
end

local function sameInfo(a, b)
  return (a == nil and b == nil)
    or (a ~= nil and b ~= nil and a.minDay == b.minDay and a.maxDay == b.maxDay and a.src == b.src)
end

-- Reads the join marker of every row (public note, officer note when officerRead) and narrows the join
-- date of the member with it. Rows are { key, name, note, officerNote }. opts: order, today,
-- officerRead. Returns the number of dates that changed.
function HL.ApplyNotes(guild, rows, opts)
  local changed = 0
  for _, row in ipairs(rows) do
    local day = HL.NoteDate(row.note, opts)
    if not day and opts.officerRead then
      day = HL.NoteDate(row.officerNote, opts)
    end
    if day then
      local e = guild.members[row.key]
      local merged = DL.Merge(e and e.joined, DL.Exact(day, "note", opts.today), opts.today)
      if merged and not sameInfo(e and e.joined, merged) then
        ML.Touch(guild.members, row).joined = merged
        changed = changed + 1
      end
    end
  end
  return changed
end

-- Chat ------------------------------------------------------------------------------------------------

-- Texts of the client for each kind of message, as format strings of the GlobalStrings
-- (ERR_GUILD_JOIN_S and so on); the game's own strings are tried first, see ChatPatterns.
HL.CHAT_FORMATS = {
  join = { "%s has joined the guild.", "%s ist der Gilde beigetreten." },
  leave = { "%s has left the guild.", "%s hat die Gilde verlassen." },
  remove = { "%s has been kicked out of the guild by %s.", "%s wurde von %s aus der Gilde geworfen." },
  promote = {
    "%s has promoted %s to %s.",
    "%s hat %s zum Rang %s befördert.",
    "%s hat %s zu %s befördert.",
    "%s hat %s auf %s befördert.",
    "%s hat %s zum %s befördert.",
  },
  demote = {
    "%s has demoted %s to %s.",
    "%s hat %s auf den Rang %s degradiert.",
    "%s hat %s zu %s degradiert.",
    "%s hat %s auf %s degradiert.",
    "%s hat %s zum %s degradiert.",
  },
}
-- Meaning of the n-th value of a format, per kind.
HL.CHAT_ARGS = {
  join = { "name" },
  leave = { "name" },
  remove = { "name", "by" },
  promote = { "by", "name", "to" },
  demote = { "by", "name", "to" },
}

-- A Lua pattern for a format string ("%s has joined the guild." or "%2$s ... %1$s"): anchored, every
-- value is a capture that may hold spaces and hyphens. Answers pattern and the argument number of each
-- capture; nil for a format without values.
function HL.PatternFromFormat(fmt)
  if type(fmt) ~= "string" or fmt == "" then
    return nil
  end
  local out, args, i = { "^" }, {}, 1
  local function plain(s)
    out[#out + 1] = (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
  end
  while i <= #fmt do
    local a, b, n = fmt:find("%%(%d*)%$?s", i)
    if not a then
      plain(fmt:sub(i))
      break
    end
    plain(fmt:sub(i, a - 1))
    args[#args + 1] = tonumber(n) or #args + 1
    out[#out + 1] = "(.-)"
    i = b + 1
  end
  if #args == 0 then
    return nil
  end
  out[#out + 1] = "$"
  return table.concat(out), args
end

-- The patterns to try, in order: `game` ({ [kind] = format string } from the client's GlobalStrings)
-- first, then the built-in formats of both languages.
function HL.ChatPatterns(game)
  local list = {}
  for _, kind in ipairs({ "join", "leave", "remove", "promote", "demote" }) do
    local formats = {}
    if type(game) == "table" and type(game[kind]) == "string" then
      formats[1] = game[kind]
    end
    for _, f in ipairs(HL.CHAT_FORMATS[kind]) do
      formats[#formats + 1] = f
    end
    for _, f in ipairs(formats) do
      local pattern, args = HL.PatternFromFormat(f)
      if pattern then
        list[#list + 1] = { kind = kind, pattern = pattern, args = args }
      end
    end
  end
  return list
end

-- A chat line without colour codes and links ("[Name]" inside a player link becomes "Name").
function HL.StripChat(msg)
  msg = (msg:gsub("|H.-|h(.-)|h", "%1"))
  msg = (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  return (msg:gsub("%[([^%]]*)%]", "%1"))
end

local function person(s)
  local name = PN.Normalize(str(s, 80))
  return name ~= "" and name or nil
end

-- One system message as { kind, name, key, by, to } (the member it is about, who did it, the new rank);
-- nil for anything else.
function HL.ParseChat(msg, patterns)
  if type(msg) ~= "string" or msg == "" or #msg > 500 then
    return nil
  end
  msg = HL.StripChat(msg)
  for _, p in ipairs(patterns or HL.ChatPatterns()) do
    local found = { msg:match(p.pattern) }
    if #found > 0 then
      local out = { kind = p.kind }
      for k, value in ipairs(found) do
        local field = HL.CHAT_ARGS[p.kind][p.args[k]]
        if field == "to" then
          out.to = str(value)
        elseif field then
          out[field] = person(value)
        end
      end
      if out.name then
        out.key = PN.Lower(out.name)
        return out
      end
    end
  end
  return nil
end

-- The event of a parsed message on `today`.
function HL.ChatEvent(parsed, today)
  return {
    day = today,
    kind = parsed.kind,
    key = parsed.key,
    name = parsed.name,
    src = "chat",
    by = parsed.by,
    to = parsed.to,
  }
end

-- Writes a parsed system message into the guild record: the event and what it says about the member.
function HL.ApplyChat(guild, parsed, today)
  HL.AddEvents(guild.events, { HL.ChatEvent(parsed, today) }, GS.Limit(guild, "maxEvents"))
  local members, key = guild.members, parsed.key
  local function entry()
    return ML.Touch(members, { key = key, name = parsed.name })
  end
  local function renew(e, field, info)
    local old = e[field]
    e[field] = (old and old.setDay == today) and DL.Merge(old, info, today) or info
  end
  local kind = parsed.kind
  if kind == "join" then
    local e = entry()
    renew(e, "joined", DL.Exact(today, "chat", today))
    renew(e, "rankSince", DL.Exact(today, "chat", today))
    e.left = nil
  elseif kind == "promote" or kind == "demote" then
    renew(entry(), "rankSince", DL.Exact(today, "chat", today))
  else
    -- Gone from the guild: the next comparison must not report it a second time.
    entry().left = { day = today, reason = kind == "remove" and "removed" or "left" }
    guild.seen[key] = nil
  end
end

-- Server guild log ------------------------------------------------------------------------------------

local LOG_KINDS = { join = "join", promote = "promote", demote = "demote", remove = "remove", quit = "leave" }

-- rows: { { type, player1, player2, rank, years, months, days, hours }... } as the guild log gives
-- them (type "invite", "join", "promote", "demote", "remove", "quit"). Answers events (src "log") and
-- joined, the join dates by member key (the latest one of each). The age is a window, see
-- DatesLogic.FromServerAge; now and offset make a young entry exact.
function HL.ServerEvents(rows, today, now, offset)
  local events, joined = {}, {}
  for i = 1, math.min(#rows, HL.MAX_LOG) do
    local r = rows[i]
    local kind = type(r) == "table" and LOG_KINDS[r.type]
    local info = kind and DL.FromServerAge(r.years, r.months, r.days, r.hours, today, "log", now, offset)
    if info then
      -- The member it is about: the one who joined or quit, else the second player.
      local who = person((kind == "join" or kind == "leave") and r.player1 or r.player2)
      if who then
        local e = {
          day = info.maxDay,
          fuzz = info.maxDay > info.minDay and info.maxDay - info.minDay or nil,
          kind = kind,
          key = PN.Lower(who),
          name = who,
          src = "log",
          toRank = (kind == "promote" or kind == "demote") and whole(r.rank) or nil,
        }
        if kind ~= "join" and kind ~= "leave" then
          e.by = person(r.player1)
        end
        events[#events + 1] = e
        if kind == "join" and (not joined[e.key] or joined[e.key].maxDay < info.maxDay) then
          joined[e.key] = info
        end
      end
    end
  end
  return events, joined
end

-- Writes log findings into the guild record: the events, and the join date of members that are in
-- the guild now.
function HL.ApplyLog(guild, events, joined, today)
  HL.AddEvents(guild.events, events, GS.Limit(guild, "maxEvents"))
  for key, info in pairs(joined) do
    local p = guild.seen[key]
    if p then
      local e = ML.Touch(guild.members, { key = key, name = p.name })
      e.joined = DL.Merge(e.joined, info, today)
    end
  end
end

-- Join dates by hand ----------------------------------------------------------------------------------

-- Sets the join date of a member to a day (source "manual").
function HL.SetJoined(members, member, day, today)
  ML.Touch(members, member).joined = DL.Exact(day, "manual", today)
end

-- Removes a join date typed by hand; true when there was one.
function HL.ClearJoined(members, key)
  local e = members[key]
  if e and e.joined and e.joined.src == "manual" then
    e.joined = nil
    ML.Keep(members, key)
    return true
  end
  return false
end

-- Bulk import: one line per member, "Name;DD.MM.YYYY" (a tab works too, a trailing date after
-- spaces as well); empty lines and lines that start with "#" are skipped. roster = { { key, name }... },
-- opts = { order, today }. Every line is checked on its own; nothing is written. Answers
-- { rows = { { line, name, key, day, reason }... }, ok, bad, tooMany } where reason is nil for a line
-- that can be applied or one of "format", "unknown", "name" (matches several), "duplicate", "invalid",
-- "ambiguous", "range", "future".
function HL.ParseImport(text, roster, opts)
  opts = opts or {}
  local out = { rows = {}, ok = 0, bad = 0, tooMany = false }
  if type(text) ~= "string" then
    return out
  end
  text = text:sub(1, 60000)
  local byKey, n = {}, 0
  for _, m in ipairs(roster or {}) do
    byKey[m.key] = m
  end
  local function resolve(name)
    local key = PN.Lower(name)
    if byKey[key] then
      return byKey[key]
    end
    local found, count = nil, 0
    for k, m in pairs(byKey) do
      if k:sub(1, #key + 1) == key .. "-" then
        found, count = m, count + 1
      end
    end
    return found, count > 1
  end
  local seen, lineNo = {}, 0
  for raw in (text .. "\n"):gmatch("(.-)\r?\n") do
    lineNo = lineNo + 1
    local line = U.trim(raw)
    if line ~= "" and line:sub(1, 1) ~= "#" then
      n = n + 1
      if n > HL.MAX_LINES then
        out.tooMany = true
        break
      end
      local name, date = line:match("^(.-)%s*[;\t]%s*(.-)$")
      if not name then
        name, date = line:match("^(.-)%s+(%S+)$")
      end
      local row = { line = lineNo, name = name and person(name) or nil }
      local m, many
      if not (row.name and date) then
        row.reason = "format"
      else
        m, many = resolve(row.name)
        if many then
          row.reason = "name"
        elseif not m then
          row.reason = "unknown"
        else
          row.key = m.key
          local day, why = DL.ParseDate(date, opts.order, opts.today)
          row.day, row.reason = day, why
          if not row.reason then
            row.reason = seen[m.key] and "duplicate" or nil
            seen[m.key] = true
          end
        end
      end
      row.member = m
      out.rows[#out.rows + 1] = row
      if row.reason then
        out.bad = out.bad + 1
      else
        out.ok = out.ok + 1
      end
    end
  end
  return out
end

-- Writes every line of a clean import (bad = 0), returns the number of members changed.
function HL.ApplyImport(members, parsed, today)
  if parsed.bad > 0 then
    return 0
  end
  for _, row in ipairs(parsed.rows) do
    HL.SetJoined(members, row.member, row.day, today)
  end
  return #parsed.rows
end
