-- Export and import of the guild record, no game calls and nothing is sent. Three outward formats
-- (text, CSV, JSON) for reading elsewhere and one restore point: the whole record as one string with a
-- version and a checksum. An import never overwrites silently: Plan shows what would change, a clash
-- with something typed by hand is a conflict the player decides, Apply writes only what the player
-- confirmed. The string has no "|" (docs/FORMAT-SICHERHEIT.md), the text formats replace it.
local _, gm = ...
if not gm.ext then
  return
end
local FG, GS, HL, DL, ML, BL = gm.FG, gm.GuildStore, gm.HistoryLogic, gm.DatesLogic, gm.MembersLogic, gm.BansLogic
local RM = gm.RemindersLogic
local PN, U = FG.PlayerName, FG.U

local EL = {}
gm.ExportLogic = EL

EL.FORMAT = "fggm-backup"
EL.VERSION = 1
EL.PREFIX = "FGGMB1:"
-- Longest string the import reads (characters) and longest text the import inflates it to (bytes).
EL.MAX_TEXT = 400000
EL.MAX_JSON = 3000000
-- Longest text export (characters); more is cut at a line end and marked.
EL.MAX_OUTPUT = 300000
EL.FORMATS = { "text", "csv", "json" }
EL.PARTS = { "members", "events", "actions", "bans", "rules" }
-- Conflicts the preview lists in full; the rest are counted.
EL.MAX_CONFLICTS = 200

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

local function stamp(t)
  local fn = rawget(_G, "date")
  local ok, text = pcall(fn or tostring, "%Y-%m-%d %H:%M", t)
  return ok and type(text) == "string" and text or tostring(t)
end

-- Checksum of a string: a 32 bit sum and the length. Finds damage, is no protection against a forgery.
function EL.Sum(s)
  return string.format("%08x%x", HL.Sum(s), #s)
end

-- Rows ----------------------------------------------------------------------------------------------

local function dayText(day)
  return day and DL.Format(day, "iso") or ""
end

local function dateOf(info)
  info = DL.Clean(info)
  if not info then
    return { min = "", max = "", src = "" }
  end
  return { min = dayText(info.minDay), max = dayText(info.maxDay), src = info.src }
end

-- Members of the record and of the last roster, sorted by name: { key, name, rank, main, alts, note,
-- joined, rankSince, left, birthday, away }. joined and rankSince are { min, max, src } in ISO dates,
-- birthday is MM-DD and away the last day of an absence (both typed by hand, local data of the player).
function EL.MemberRows(guild)
  local keys = {}
  for k in pairs(guild.members) do
    keys[k] = true
  end
  for k in pairs(guild.seen) do
    keys[k] = true
  end
  local rows = {}
  for key in pairs(keys) do
    local m, seen = guild.members[key] or {}, guild.seen[key] or {}
    rows[#rows + 1] = {
      key = key,
      name = m.name or seen.name or key,
      rank = seen.rankName or "",
      main = m.main or "",
      alts = ML.AltsOf(guild.members, key),
      note = m.note or "",
      joined = dateOf(m.joined),
      rankSince = dateOf(m.rankSince),
      left = m.left and dayText(m.left.day) or "",
      birthday = m.birthday and RM.FormatBirthday(m.birthday, "iso") or "",
      away = dayText(m.away),
    }
  end
  table.sort(rows, function(a, b)
    local x, y = PN.Lower(a.name), PN.Lower(b.name)
    return x ~= y and x < y or (x == y and a.key < b.key)
  end)
  return rows
end

local function eventRows(guild)
  local rows = {}
  for i = #guild.events, 1, -1 do
    local e = guild.events[i]
    rows[#rows + 1] = {
      day = dayText(e.day),
      kind = e.kind,
      name = e.name,
      from = e.from or "",
      to = e.to or "",
      by = e.by or "",
      src = e.src,
      fuzz = e.fuzz or 0,
    }
  end
  return rows
end

local function actionRows(guild)
  local rows = {}
  for i = #guild.actions, 1, -1 do
    local e = guild.actions[i]
    rows[#rows + 1] = {
      time = stamp(e.t),
      action = e.action,
      name = e.name,
      old = e.old,
      new = e.new,
      rule = e.rule or "",
      result = e.result or "",
      undone = e.undone == true,
    }
  end
  return rows
end

local function banRows(guild)
  local rows = {}
  for _, b in ipairs(BL.List(guild.bans, "")) do
    rows[#rows + 1] = { name = b.name, day = dayText(b.day), reason = b.reason, note = b.note }
  end
  return rows
end

local function ruleRows(guild)
  local rows = {}
  for _, r in ipairs(guild.rules) do
    if type(r) == "table" then
      rows[#rows + 1] = {
        name = tostring(r.name or ""),
        enabled = r.enabled == true,
        action = type(r.action) == "table" and tostring(r.action.kind or "") or "",
        ranks = type(r.ranks) == "table" and table.concat(r.ranks, " ") or "",
      }
    end
  end
  return rows
end

-- Columns of the flat tables (CSV and text), in this order.
local COLUMNS = {
  members = {
    "name",
    "rank",
    "main",
    "note",
    "joined_min",
    "joined_max",
    "joined_source",
    "rank_since_min",
    "rank_since_max",
    "rank_since_source",
    "left",
    "birthday",
    "away_until",
  },
  events = { "day", "kind", "name", "from", "to", "by", "source", "fuzz" },
  actions = { "time", "action", "name", "old", "new", "rule", "result", "undone" },
  bans = { "name", "day", "reason", "note" },
  rules = { "name", "enabled", "action", "ranks" },
}

local function cells(part, r)
  if part == "members" then
    return {
      r.name,
      r.rank,
      r.main,
      r.note,
      r.joined.min,
      r.joined.max,
      r.joined.src,
      r.rankSince.min,
      r.rankSince.max,
      r.rankSince.src,
      r.left,
      r.birthday,
      r.away,
    }
  elseif part == "events" then
    return { r.day, r.kind, r.name, r.from, r.to, r.by, r.src, r.fuzz }
  elseif part == "actions" then
    return { r.time, r.action, r.name, r.old, r.new, r.rule, r.result, r.undone and "1" or "0" }
  elseif part == "bans" then
    return { r.name, r.day, r.reason, r.note }
  end
  return { r.name, r.enabled and "1" or "0", r.action, r.ranks }
end

local function rowsOf(guild, part)
  if part == "members" then
    return EL.MemberRows(guild)
  elseif part == "events" then
    return eventRows(guild)
  elseif part == "actions" then
    return actionRows(guild)
  elseif part == "bans" then
    return banRows(guild)
  end
  return ruleRows(guild)
end

-- No "|" and no control character in text a player copies: the client reads "|" as a code.
local function safe(s)
  return (tostring(s):gsub("|", "/"):gsub("[%z\1-\31\127]", " "))
end

local function csvCell(v)
  v = safe(v)
  if v:find('[;"]') then
    v = '"' .. v:gsub('"', '""') .. '"'
  end
  return v
end

-- Builds the export. format: "text", "csv" or "json"; parts: set of EL.PARTS names (all when nil); ctx:
-- L (locale table), guild. Answers the text and info = { rows = n, truncated = bool } or nil and a reason.
function EL.Build(guild, format, parts, ctx)
  ctx = ctx or {}
  parts = parts or { members = true, events = true, actions = true, bans = true, rules = true }
  local L = ctx.L or FG.L
  local out, rows, truncated = {}, 0, false
  local function push(line)
    out[#out + 1] = line
  end
  if format == "json" then
    local doc = {
      app = "ForeverGuides_GildenManager",
      format = "export",
      version = EL.VERSION,
      exportedAt = ctx.now or U.now(),
      guild = { name = guild.name, realm = guild.realm },
    }
    for _, part in ipairs(EL.PARTS) do
      if parts[part] then
        if part == "rules" then
          doc.rules = U.copy(guild.rules)
          rows = rows + #guild.rules
        else
          doc[part] = rowsOf(guild, part)
          rows = rows + #doc[part]
        end
      end
    end
    local ok, text = pcall(FG.Json.encode, doc)
    if not ok then
      return nil, "json"
    end
    if #text > EL.MAX_OUTPUT then
      return nil, "tooLarge"
    end
    return text, { rows = rows, truncated = false }
  elseif format ~= "csv" and format ~= "text" then
    return nil, "format"
  end
  push(
    format == "csv" and "#" .. safe(guild.name .. " " .. guild.realm)
      or string.format(L["gm.exp.title"], safe(guild.name ~= "" and guild.name or "?"))
  )
  for _, part in ipairs(EL.PARTS) do
    if parts[part] then
      local list = rowsOf(guild, part)
      rows = rows + #list
      push("")
      if format == "csv" then
        push("#" .. part)
        push(table.concat(COLUMNS[part], ";"))
        for _, r in ipairs(list) do
          local c = cells(part, r)
          for i = 1, #c do
            c[i] = csvCell(c[i])
          end
          push(table.concat(c, ";"))
        end
      else
        push(string.format(L["gm.exp.sec." .. part], #list))
        for _, r in ipairs(list) do
          local c = cells(part, r)
          local shown = {}
          for i = 1, #c do
            local v = safe(c[i])
            if v ~= "" and v ~= "0" then
              shown[#shown + 1] = v
            end
          end
          push(table.concat(shown, "; "))
        end
      end
    end
  end
  local text = table.concat(out, "\n")
  if #text > EL.MAX_OUTPUT then
    local cut = text:sub(1, EL.MAX_OUTPUT):match("^(.*)\n") or ""
    text, truncated = cut .. "\n" .. L["gm.exp.truncated"], true
  end
  return text, { rows = rows, truncated = truncated }
end

-- Restore point ----------------------------------------------------------------------------------------

local CONTAINERS =
  { "members", "idByGuid", "seen", "events", "actions", "bans", "rules", "protect", "skip", "settings" }
local NUMBERS = { "firstScanDay", "lastScanDay", "lastScanCount" }

-- The restore point of a guild record as a string, or nil and a reason ("noCodec", "json", "tooLarge").
-- Format: PREFIX .. EncodeForPrint(deflate(JSON { fmt, ver, savedAt, name, realm, sum, body })) where
-- body is the JSON text of the record and sum its checksum.
function EL.Backup(guild, now)
  local LD = FG.LibDeflate
  if not (LD and FG.Json) then
    return nil, "noCodec"
  end
  local data = { name = guild.name, realm = guild.realm }
  for _, field in ipairs(CONTAINERS) do
    data[field] = guild[field]
  end
  for _, field in ipairs(NUMBERS) do
    data[field] = guild[field]
  end
  local ok, body = pcall(FG.Json.encode, data)
  if not ok or #body > EL.MAX_JSON then
    return nil, ok and "tooLarge" or "json"
  end
  local okEnv, json = pcall(FG.Json.encode, {
    fmt = EL.FORMAT,
    ver = EL.VERSION,
    savedAt = now or U.now(),
    name = guild.name,
    realm = guild.realm,
    sum = EL.Sum(body),
    body = body,
  })
  if not okEnv then
    return nil, "json"
  end
  local text = EL.PREFIX .. LD:EncodeForPrint(LD:CompressDeflate(json))
  if #text > EL.MAX_TEXT then
    return nil, "tooLarge"
  end
  return text
end

-- Counts of what the repair of an import changed: how many entries of each list were dropped.
local function repairCount(before, after)
  return math.max(0, before - after)
end

local function size(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

-- Brings a decoded record into shape: only known containers, every entry through the same cleaning as
-- the store, rules always off. Answers the record and { members, events, actions, bans, rules } = number
-- of entries that were dropped.
function EL.Repair(raw, opts)
  opts = opts or {}
  local guild =
    GS.NewGuild(type(raw.name) == "string" and raw.name or "", type(raw.realm) == "string" and raw.realm or "")
  for _, field in ipairs(CONTAINERS) do
    if type(raw[field]) == "table" then
      guild[field] = raw[field]
    end
  end
  for _, field in ipairs(NUMBERS) do
    guild[field] = raw[field]
  end
  local before = {
    members = size(guild.members),
    events = #guild.events,
    actions = #guild.actions,
    bans = size(guild.bans),
    rules = #guild.rules,
  }
  GS.CleanGuild(guild)
  gm.CleanGuild(guild)
  local rules = gm.RulesLogic.CleanList(guild.rules, opts.ranks or {})
  for _, r in ipairs(rules) do
    r.enabled = false
  end
  guild.rules = rules
  local report = {
    members = repairCount(before.members, size(guild.members)),
    events = repairCount(before.events, #guild.events),
    actions = repairCount(before.actions, #guild.actions),
    bans = repairCount(before.bans, size(guild.bans)),
    rules = repairCount(before.rules, #guild.rules),
  }
  return guild, report
end

-- Reads a restore point. Strict: the prefix, the size, the version and the checksum must all be right.
-- Answers { guild, report, savedAt, name, realm } or nil and a reason: "empty", "format", "tooLarge",
-- "noCodec", "decode", "json", "newer", "sum", "shape".
function EL.Parse(text, opts)
  if type(text) ~= "string" then
    return nil, "empty"
  end
  if #text > EL.MAX_TEXT * 2 then
    return nil, "tooLarge"
  end
  text = text:gsub("%s+", "")
  if text == "" then
    return nil, "empty"
  end
  if #text > EL.MAX_TEXT then
    return nil, "tooLarge"
  end
  if text:sub(1, #EL.PREFIX) ~= EL.PREFIX then
    return nil, "format"
  end
  local LD = FG.LibDeflate
  if not (LD and LD._FG_MAX_OUTPUT and FG.Json) then
    return nil, "noCodec"
  end
  local okDecode, packed = pcall(LD.DecodeForPrint, LD, text:sub(#EL.PREFIX + 1))
  if not okDecode or not packed then
    return nil, "decode"
  end
  local okInflate, json, status = pcall(LD.DecompressDeflate, LD, packed, EL.MAX_JSON)
  if not okInflate or not json then
    return nil, status == -20 and "tooLarge" or "decode"
  end
  local okJson, env = pcall(FG.Json.decode, json)
  if not okJson or type(env) ~= "table" or env.fmt ~= EL.FORMAT then
    return nil, okJson and "format" or "json"
  end
  if type(env.ver) ~= "number" or env.ver % 1 ~= 0 or env.ver < 1 then
    return nil, "format"
  end
  if env.ver > EL.VERSION then
    return nil, "newer"
  end
  if type(env.body) ~= "string" or type(env.sum) ~= "string" or #env.body > EL.MAX_JSON then
    return nil, "shape"
  end
  if EL.Sum(env.body) ~= env.sum then
    return nil, "sum"
  end
  local okBody, raw = pcall(FG.Json.decode, env.body)
  if not okBody or type(raw) ~= "table" then
    return nil, "json"
  end
  -- A restore point always carries its lists, even empty ones.
  if type(raw.members) ~= "table" or type(raw.events) ~= "table" or type(raw.actions) ~= "table" then
    return nil, "shape"
  end
  local guild, report = EL.Repair(raw, opts)
  return {
    guild = guild,
    report = report,
    savedAt = type(env.savedAt) == "number" and env.savedAt or nil,
    name = guild.name,
    realm = guild.realm,
  }
end

-- Merge --------------------------------------------------------------------------------------------------

local function same(a, b)
  return FG.Json.encode(a) == FG.Json.encode(b)
end

local function ruleKey(r)
  return PN.Lower(tostring(r.name or ""))
end

local function ruleBody(r)
  local copy = U.copy(r)
  copy.id, copy.enabled = nil, nil
  return copy
end

-- Merges incoming (a repaired record) into mine, in place. decide(conflict) answers true to take the
-- incoming value of a clash with something typed by hand, false to keep mine. Answers the counts and the
-- conflicts { id, part, key, field, name, mine, theirs } in a fixed order (the id names the clash and
-- stays the same between the preview and the write).
local function merge(mine, incoming, decide, ctx)
  local counts = { members = 0, events = 0, actions = 0, bans = 0, rules = 0 }
  local conflicts = {}
  local today = ctx.today
  local function clash(part, key, field, name, mineText, theirsText)
    local c = {
      id = part .. ":" .. key .. ":" .. field,
      part = part,
      key = key,
      field = field,
      name = name,
      mine = mineText,
      theirs = theirsText,
    }
    conflicts[#conflicts + 1] = c
    return decide(c)
  end
  local function dateText(info)
    return DL.Text(info, ctx.L or FG.L, ctx.format or "iso")
  end

  for _, key in ipairs(sortedKeys(incoming.members)) do
    local inc, cur = incoming.members[key], mine.members[key]
    local isNew = cur == nil
    if isNew then
      cur = ML.Touch(mine.members, { key = key, name = inc.name })
    end
    local changed = isNew
    if inc.note ~= "" and cur.note ~= inc.note then
      if cur.note == "" or clash("members", key, "note", inc.name, cur.note, inc.note) then
        cur.note, changed = inc.note, true
      end
    end
    if inc.main ~= "" and cur.main ~= inc.main then
      local take = cur.main == "" or clash("members", key, "main", inc.name, cur.main, inc.main)
      if take and ML.SetMain(mine.members, { key = key, name = cur.name }, inc.main) then
        changed = true
      end
    end
    for _, field in ipairs({ "joined", "rankSince" }) do
      local a, b = cur[field], inc[field]
      if b and not a then
        cur[field], changed = U.copy(b), true
      elseif a and b and not same(a, b) then
        if a.src == "manual" or b.src == "manual" then
          if clash("members", key, field, inc.name, dateText(a), dateText(b)) then
            cur[field], changed = U.copy(b), true
          end
        else
          local merged = DL.Merge(a, b, today)
          if merged and not same(merged, a) then
            cur[field], changed = merged, true
          end
        end
      end
    end
    if type(inc.tags) == "table" then
      for tag, v in pairs(inc.tags) do
        cur.tags = cur.tags or {}
        if cur.tags[tag] == nil then
          cur.tags[tag], changed = v, true
        end
      end
    end
    -- Birthday and absence are typed by hand: a different value is a clash the player decides.
    if inc.birthday then
      local a, b = cur.birthday, inc.birthday
      if not a then
        cur.birthday, changed = U.copy(b), true
      elseif a.month ~= b.month or a.day ~= b.day then
        local order = ctx.format or "iso"
        if clash("members", key, "birthday", inc.name, RM.FormatBirthday(a, order), RM.FormatBirthday(b, order)) then
          cur.birthday, changed = U.copy(b), true
        end
      end
    end
    if inc.away and inc.away ~= cur.away then
      if not cur.away then
        cur.away, changed = inc.away, true
      elseif
        clash(
          "members",
          key,
          "away",
          inc.name,
          DL.Format(cur.away, ctx.format or "iso"),
          DL.Format(inc.away, ctx.format or "iso")
        )
      then
        cur.away, changed = inc.away, true
      end
    end
    if inc.left and not cur.left then
      cur.left, changed = U.copy(inc.left), true
    end
    ML.Keep(mine.members, key)
    if changed and mine.members[key] then
      counts.members = counts.members + 1
    end
  end

  counts.events = HL.AddEvents(mine.events, incoming.events, GS.Limit(mine, "maxEvents"))

  local have = {}
  for _, e in ipairs(mine.actions) do
    have[e.t .. "|" .. e.action .. "|" .. e.name] = true
  end
  for _, e in ipairs(incoming.actions) do
    local k = e.t .. "|" .. e.action .. "|" .. e.name
    if not have[k] then
      have[k] = true
      mine.actions[#mine.actions + 1] = U.copy(e)
      counts.actions = counts.actions + 1
    end
  end
  local order = {}
  for i, e in ipairs(mine.actions) do
    order[e] = i
  end
  table.sort(mine.actions, function(a, b)
    return a.t ~= b.t and a.t < b.t or (a.t == b.t and order[a] < order[b])
  end)
  GS.Trim(mine.actions, GS.Limit(mine, "maxActions"))

  for _, key in ipairs(sortedKeys(incoming.bans)) do
    local inc, cur = incoming.bans[key], mine.bans[key]
    if not cur then
      mine.bans[key] = U.copy(inc)
      counts.bans = counts.bans + 1
    elseif cur.reason ~= inc.reason or cur.note ~= inc.note then
      local a, b = cur.reason .. " / " .. cur.note, inc.reason .. " / " .. inc.note
      if clash("bans", key, "ban", inc.name, a, b) then
        mine.bans[key] = U.copy(inc)
        counts.bans = counts.bans + 1
      end
    end
  end

  -- Rules are matched by name against what was there before the import: several rules may share a
  -- name (two rules of one template), each of them has to arrive.
  local index, taken = {}, {}
  for i, r in ipairs(mine.rules) do
    local k = ruleKey(r)
    index[k] = index[k] or {}
    index[k][#index[k] + 1] = i
  end
  for _, r in ipairs(incoming.rules) do
    local slots = index[ruleKey(r)] or {}
    local present, free = false, nil
    for _, at in ipairs(slots) do
      if same(ruleBody(mine.rules[at]), ruleBody(r)) then
        present = true
      elseif not taken[at] and not free then
        free = at
      end
    end
    -- A rule that is already there (same name and body) needs nothing.
    if not present then
      if not free then
        mine.rules[#mine.rules + 1] = U.copy(r)
        counts.rules = counts.rules + 1
      elseif
        clash("rules", ruleKey(r), "rule", tostring(r.name), tostring(mine.rules[free].name), tostring(r.name))
      then
        mine.rules[free] = U.copy(r)
        taken[free] = true
        counts.rules = counts.rules + 1
      end
    end
  end
  return counts, conflicts
end

local function keepMine()
  return false
end

-- What an import would do, without changing anything. Answers { counts, conflicts, total, sameGuild }:
-- the number of entries that would be added or changed per part and the clashes with hand entries.
-- Only the first EL.MAX_CONFLICTS conflicts are listed, the rest count in `more`.
function EL.Plan(mine, parsed, ctx)
  ctx = ctx or {}
  local counts, conflicts = merge(U.copy(mine), parsed.guild, keepMine, ctx)
  local total = 0
  for _, n in pairs(counts) do
    total = total + n
  end
  local more = math.max(0, #conflicts - EL.MAX_CONFLICTS)
  for i = #conflicts, EL.MAX_CONFLICTS + 1, -1 do
    conflicts[i] = nil
  end
  local theirs = GS.Key(parsed.name, parsed.realm)
  local ours = GS.Key(mine.name, mine.realm)
  return { counts = counts, conflicts = conflicts, more = more, total = total, sameGuild = theirs == ours }
end

-- Writes the import into mine. decisions: set of conflict ids the player chose "take the backup" for;
-- every other clash keeps the value in mine. Answers the counts. The record is cleaned afterwards, so
-- the size limits hold.
function EL.Apply(mine, parsed, decisions, ctx)
  ctx = ctx or {}
  decisions = decisions or {}
  local counts = merge(mine, parsed.guild, function(c)
    return decisions[c.id] == true
  end, ctx)
  gm.CleanGuild(mine)
  return counts
end
