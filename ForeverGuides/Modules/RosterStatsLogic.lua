-- Character statistics, pure data side (no frames, no game calls): played time, PvP, reputation and
-- the statistics list. Capture reads the game (RosterStats.lua), CharRoster stores the cleaned
-- blocks, the character overview shows them through Summary and TooltipLines.
--   pvp   = { honor, level, rankName, kills, highestRank, ratings = { { bracket, rating, best } }, at }
--   rep   = { list = { { id, name, standing (1-8), label, value, max } }, at }   (value and max within the standing)
--   stats = { list = { { id, name, value } }, at }
-- Dates and durations reuse the chars.seen.* and chars.dur.* texts of RosterView.
local _, ns = ...
local L = ns.L

ns.AddLocale("enUS", {
  ["rosterstats.thousands"] = ",",
  ["rosterstats.decimal"] = ".",
  ["rosterstats.hours"] = "%d h",
  ["rosterstats.minutes"] = "%d min",
  ["rosterstats.played.total"] = "Total: %s",
  ["rosterstats.played.level"] = "This level: %s",
  ["rosterstats.pvp.rating"] = "Rating %d",
  ["rosterstats.pvp.rank"] = "Rank %d",
  ["rosterstats.pvp.kills"] = "%s HK",
  ["rosterstats.tip.rank"] = "Rank: %s",
  ["rosterstats.tip.honor"] = "Honor: %s",
  ["rosterstats.tip.kills"] = "Honorable kills: %s",
  ["rosterstats.tip.highest"] = "Highest rank: %d",
  ["rosterstats.tip.rating"] = "Rating %d: %s",
  ["rosterstats.tip.best"] = " (best %s)",
  ["rosterstats.rep.known"] = "%d known",
  ["rosterstats.rep.top"] = ", %d %s",
  ["rosterstats.tip.more"] = "+%d more",
  ["rosterstats.stat.unnamed"] = "Statistic %d",
})

ns.AddLocale("deDE", {
  ["rosterstats.thousands"] = ".",
  ["rosterstats.decimal"] = ",",
  ["rosterstats.hours"] = "%d Std",
  ["rosterstats.minutes"] = "%d Min",
  ["rosterstats.played.total"] = "Gesamt: %s",
  ["rosterstats.played.level"] = "Aktuelle Stufe: %s",
  ["rosterstats.pvp.rating"] = "Wertung %d",
  ["rosterstats.pvp.rank"] = "Rang %d",
  ["rosterstats.pvp.kills"] = "%s EK",
  ["rosterstats.tip.rank"] = "Rang: %s",
  ["rosterstats.tip.honor"] = "Ehre: %s",
  ["rosterstats.tip.kills"] = "Ehrenhafte Kills: %s",
  ["rosterstats.tip.highest"] = "Höchster Rang: %d",
  ["rosterstats.tip.rating"] = "Wertung %d: %s",
  ["rosterstats.tip.best"] = " (Beste %s)",
  ["rosterstats.rep.known"] = "%d bekannt",
  ["rosterstats.rep.top"] = ", %d %s",
  ["rosterstats.tip.more"] = "+%d weitere",
  ["rosterstats.stat.unnamed"] = "Statistik %d",
})

local S = {}
ns.RosterStatsLogic = S

S.MAX_REP = 60
S.MAX_STATS = 40
S.MAX_RATINGS = 8
S.TIP_REP = 20
S.KINDS = { "pvp", "rep", "playtime", "stats" }

-- GetStatistic ids that are tracked, in display order. Names come from the client
-- (GetAchievementInfo), so a wrong id shows another statistic and never a wrong label. Extend it
-- with further ids as needed.
S.STAT_IDS = { 60, 98, 1197 }

local NEUTRAL = 4
local EXALTED = 8
local DAY = 86400

-- Validation ------------------------------------------------------------------------------

local function num(v, lo, hi)
  if type(v) ~= "number" or v ~= v or v < lo or v > hi then
    return nil
  end
  return v
end

local function whole(v, lo, hi)
  v = num(v, lo, hi)
  return v and math.floor(v) or nil
end

local function text(v, max)
  if type(v) ~= "string" or v == "" then
    return nil
  end
  return v:sub(1, max)
end

local function list(v)
  return type(v) == "table" and v or {}
end

-- A statistic as the client prints it: "1,234", "1.234", "12" or "--" (nothing counted yet, so 0).
-- Texts with units ("5g 3s") are not counts and give nil.
function S.ParseCount(v)
  if type(v) == "number" then
    return whole(v, 0, 1e15)
  elseif type(v) ~= "string" then
    return nil
  elseif v:find("^%-+$") then
    return 0
  end
  local digits = v:gsub("[ ,%.']", ""):gsub("\194\160", "")
  if digits ~= "" and #digits <= 15 and not digits:find("%D") then
    return tonumber(digits)
  end
  return nil
end

-- Sorted, without duplicates by key, cut to cap. Entries later in `lists` replace earlier ones.
local function combine(lists, keyOf, less, cap)
  local byKey, out = {}, {}
  for _, items in ipairs(lists) do
    for _, e in ipairs(items) do
      byKey[keyOf(e)] = e
    end
  end
  for _, e in pairs(byKey) do
    out[#out + 1] = e
  end
  table.sort(out, less)
  while #out > cap do
    out[#out] = nil
  end
  return out
end

-- Reputation ----------------------------------------------------------------------------------

-- Known: any standing above or below neutral, or progress inside neutral.
function S.IsKnown(e)
  return (e.standing ~= nil and e.standing ~= NEUTRAL) or e.value > 0
end

local function repKey(e)
  return e.id and ("i" .. e.id) or ("n" .. e.name)
end

local function repLess(a, b)
  local sa, sb = a.standing or 0, b.standing or 0
  if sa ~= sb then
    return sa > sb
  elseif a.value ~= b.value then
    return a.value > b.value
  end
  local an, bn = a.name:lower(), b.name:lower()
  if an ~= bn then
    return an < bn
  end
  return repKey(a) < repKey(b)
end

local function cleanFaction(r)
  local name = type(r) == "table" and text(r.name, 60)
  if not name then
    return nil
  end
  return {
    id = whole(r.id, 1, 1e8),
    name = name,
    standing = whole(r.standing, 1, 8),
    label = text(r.label, 30),
    value = whole(r.value, 0, 1e7) or 0,
    max = whole(r.max, 0, 1e7) or 0,
  }
end

local function cleanFactions(raw)
  local out, seen = {}, {}
  for _, r in ipairs(list(raw)) do
    local e = cleanFaction(r)
    if e and not seen[repKey(e)] and #out < S.MAX_REP then
      seen[repKey(e)] = true
      out[#out + 1] = e
    end
  end
  return out
end

-- rows: { id, name, standing, label, min, max, current, header, hasRep } as read from the client,
-- current/min/max absolute. Known factions only, header groups left out, sorted, at most MAX_REP;
-- nil when none is left.
function S.FromReputation(rows)
  local out = {}
  for _, r in ipairs(list(rows)) do
    if type(r) == "table" and (r.header ~= true or r.hasRep == true) then
      local min = num(r.min, -1e9, 1e9) or 0
      local max = num(r.max, -1e9, 1e9)
      local current = num(r.current, -1e9, 1e9)
      local e = cleanFaction({
        id = r.id,
        name = r.name,
        standing = r.standing,
        label = r.label,
        value = current and math.max(0, current - min) or 0,
        max = max and math.max(0, max - min) or 0,
      })
      if e and S.IsKnown(e) then
        out[#out + 1] = e
      end
    end
  end
  out = combine({ out }, repKey, repLess, S.MAX_REP)
  return #out > 0 and out or nil
end

-- Old and new reading in one list: a faction missing in `new` (hidden below a collapsed header)
-- keeps its stored entry.
function S.MergeReputation(old, new)
  local out = combine({ cleanFactions(old), cleanFactions(new) }, repKey, repLess, S.MAX_REP)
  return #out > 0 and out or nil
end

function S.CleanRep(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local items = cleanFactions(raw.list)
  if #items == 0 then
    return nil
  end
  return { list = items, at = num(raw.at, 0, 1e11) }
end

-- PvP -------------------------------------------------------------------------------------------

-- A clean copy, nil without any value. Used for the reading as well as for stored data.
function S.CleanPvp(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local out = {
    honor = whole(raw.honor, 0, 1e9),
    level = whole(raw.level, 0, 1000),
    rankName = text(raw.rankName, 40),
    kills = whole(raw.kills, 0, 1e9),
    highestRank = whole(raw.highestRank, 0, 1000),
    ratings = {},
    at = num(raw.at, 0, 1e11),
  }
  for _, r in ipairs(list(raw.ratings)) do
    local bracket = type(r) == "table" and whole(r.bracket, 1, 20)
    local rating = bracket and whole(r.rating, 0, 10000)
    if rating and #out.ratings < S.MAX_RATINGS then
      out.ratings[#out.ratings + 1] = { bracket = bracket, rating = rating, best = whole(r.best, 0, 10000) }
    end
  end
  if out.honor or out.level or out.rankName or out.kills or out.highestRank or #out.ratings > 0 then
    return out
  end
  return nil
end

-- The new PvP reading (clean) with the counters the client answered with 0 or not at all filled from
-- the stored one (clean, may be nil). The kills, the honor level and the highest rank do not drop.
function S.MergePvp(old, new)
  if not (old and new) then
    return new
  end
  for _, field in ipairs({ "honor", "level", "kills", "highestRank" }) do
    if (new[field] == nil or new[field] == 0) and old[field] and old[field] > 0 then
      new[field] = old[field]
      if field == "level" then
        new.rankName = new.rankName or old.rankName
      end
    end
  end
  return new
end

-- Statistics ------------------------------------------------------------------------------------

local function statOrder(id)
  for i, known in ipairs(S.STAT_IDS) do
    if known == id then
      return i
    end
  end
  return 1000 + id
end

local function statKey(e)
  return e.id
end

local function statLess(a, b)
  local oa, ob = statOrder(a.id), statOrder(b.id)
  if oa ~= ob then
    return oa < ob
  end
  return a.id < b.id
end

local function cleanStatList(raw)
  local out, seen = {}, {}
  for _, r in ipairs(list(raw)) do
    local id = type(r) == "table" and whole(r.id, 1, 1e6)
    local value = id and whole(r.value, 0, 1e15)
    if value and not seen[id] and #out < S.MAX_STATS then
      seen[id] = true
      out[#out + 1] = { id = id, name = text(r.name, 60), value = value }
    end
  end
  return out
end

-- rows: { id, name, value } with the value as GetStatistic printed it. nil when none is a count.
function S.FromStatistics(rows)
  local counted = {}
  for _, r in ipairs(list(rows)) do
    if type(r) == "table" then
      counted[#counted + 1] = { id = r.id, name = r.name, value = S.ParseCount(r.value) }
    end
  end
  local out = combine({ cleanStatList(counted) }, statKey, statLess, S.MAX_STATS)
  return #out > 0 and out or nil
end

-- Old and new reading in one list. The counts only grow: a 0 in the new reading (the client is not
-- ready, "--") does not replace a stored count above 0.
function S.MergeStatistics(old, new)
  local stored, held, fresh = cleanStatList(old), {}, {}
  for _, e in ipairs(stored) do
    held[e.id] = e
  end
  for _, e in ipairs(cleanStatList(new)) do
    local prev = held[e.id]
    fresh[#fresh + 1] = (e.value == 0 and prev and prev.value > 0) and prev or e
  end
  local out = combine({ stored, fresh }, statKey, statLess, S.MAX_STATS)
  return #out > 0 and out or nil
end

function S.CleanStats(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local items = cleanStatList(raw.list)
  if #items == 0 then
    return nil
  end
  return { list = items, at = num(raw.at, 0, 1e11) }
end

-- A stable text of a block without its reading time, to tell a changed block from a repeated one.
local function sig(v)
  if type(v) ~= "table" then
    return tostring(v)
  end
  local keys = {}
  for k in pairs(v) do
    if k ~= "at" then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = tostring(k) .. "=" .. sig(v[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end
S.Sig = sig

-- Texts --------------------------------------------------------------------------------------------

-- 1234567 as "1,234,567" (en) or "1.234.567" (de).
function S.Group(n)
  local s = string.format("%.0f", n)
  local sep = L["rosterstats.thousands"]
  local k
  repeat
    s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1" .. sep .. "%2")
  until k == 0
  return s
end

local function decimal(v, suffix)
  local s = string.format("%.1f", v):gsub("%.0$", "")
  return (s:gsub("%.", L["rosterstats.decimal"])) .. suffix
end

-- 950, "1.2k", "34k", "5.6M".
function S.Compact(n)
  n = math.floor(n)
  if n < 1000 then
    return tostring(n)
  elseif n < 1e4 then
    return decimal(n / 1e3, "k")
  elseif n < 1e6 then
    return math.floor(n / 1e3) .. "k"
  elseif n < 1e7 then
    return decimal(n / 1e6, "M")
  end
  return math.floor(n / 1e6) .. "M"
end

function S.Duration(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  local days, hours = math.floor(seconds / DAY), math.floor(seconds % DAY / 3600)
  if days > 0 then
    return string.format(L["chars.dur.days"], days, hours)
  elseif hours == 0 then
    return string.format(L["rosterstats.minutes"], math.floor(seconds / 60))
  end
  return string.format(L["chars.dur.hours"], hours, math.floor(seconds % 3600 / 60))
end

-- Whole days since the reading, nil without a time.
function S.AgeDays(at, now)
  if type(at) ~= "number" or at <= 0 or type(now) ~= "number" then
    return nil
  end
  return math.max(0, math.floor((now - at) / DAY))
end

local function ago(days)
  if days == 0 then
    return L["chars.seen.today"]
  elseif days == 1 then
    return L["chars.seen.yesterday"]
  elseif days < 14 then
    return string.format(L["chars.seen.days"], days)
  elseif days < 60 then
    return string.format(L["chars.seen.weeks"], math.floor(days / 7))
  end
  return string.format(L["chars.seen.months"], math.floor(days / 30))
end

-- "Updated: 3 d ago", nil without a reading time or without `now`.
local function ageLine(at, now)
  local days = S.AgeDays(at, now)
  return days and string.format(L["chars.tip.prof.age"], ago(days)) or nil
end

-- Summary: one short cell per kind ---------------------------------------------------------------

local function played(profile)
  return whole(profile.played, 0, 1e9)
end

local function playtimeSummary(profile)
  local total = played(profile)
  if not total then
    return nil
  end
  return { text = S.Duration(total), plain = { string.format(L["rosterstats.hours"], math.floor(total / 3600)) } }
end

local function bestRating(pvp)
  local best
  for _, r in ipairs(pvp.ratings) do
    if r.rating > 0 and (not best or r.rating > best) then
      best = r.rating
    end
  end
  return best
end

-- The rating when there is one, else the rank, else the honorable kills.
local function pvpSummary(profile)
  local pvp = S.CleanPvp(profile.pvp)
  if not pvp then
    return nil
  end
  local rating = bestRating(pvp)
  if rating then
    return { text = string.format(L["rosterstats.pvp.rating"], rating), plain = { tostring(rating) } }
  elseif pvp.level and pvp.level > 0 then
    return { text = string.format(L["rosterstats.pvp.rank"], pvp.level), plain = { tostring(pvp.level) } }
  elseif pvp.kills and pvp.kills > 0 then
    return { text = string.format(L["rosterstats.pvp.kills"], S.Compact(pvp.kills)), plain = { S.Compact(pvp.kills) } }
  end
  return nil
end

-- "12 known" plus the number of exalted factions, named as the client names that standing.
local function repSummary(profile)
  local rep = S.CleanRep(profile.rep)
  if not rep then
    return nil
  end
  local exalted, label = 0, nil
  for _, e in ipairs(rep.list) do
    if e.standing == EXALTED then
      exalted = exalted + 1
      label = label or e.label
    end
  end
  local out = string.format(L["rosterstats.rep.known"], #rep.list)
  if exalted > 0 and label then
    out = out .. string.format(L["rosterstats.rep.top"], exalted, label)
  end
  return { text = out, plain = { tostring(#rep.list) } }
end

-- The values of the first two statistics, "12 / 1.2k"; the names are in the tooltip.
local function statsSummary(profile)
  local stats = S.CleanStats(profile.stats)
  if not stats then
    return nil
  end
  local values = {}
  for i = 1, math.min(2, #stats.list) do
    values[i] = S.Compact(stats.list[i].value)
  end
  return { text = table.concat(values, " / "), plain = { values[1] } }
end

local SUMMARY = { playtime = playtimeSummary, pvp = pvpSummary, rep = repSummary, stats = statsSummary }

-- { text, plain = { shorter forms } } for one kind (S.KINDS), nil without data.
function S.Summary(profile, kind)
  local build = type(profile) == "table" and SUMMARY[kind]
  return build and build(profile) or nil
end

-- Tooltip: the lines per kind ---------------------------------------------------------------------

local function playtimeLines(profile, now)
  local total = played(profile)
  if not total then
    return nil
  end
  local lines = { string.format(L["rosterstats.played.total"], S.Duration(total)) }
  local level = whole(profile.levelPlayed, 0, 1e9)
  if level then
    lines[#lines + 1] = string.format(L["rosterstats.played.level"], S.Duration(level))
  end
  lines[#lines + 1] = ageLine(num(profile.playedAt, 0, 1e11), now)
  return lines
end

local function rankText(pvp)
  if pvp.rankName and pvp.level and pvp.level > 0 then
    return pvp.rankName .. " (" .. pvp.level .. ")"
  end
  return pvp.rankName or (pvp.level and pvp.level > 0 and tostring(pvp.level)) or nil
end

local function pvpLines(profile, now)
  local pvp = S.CleanPvp(profile.pvp)
  if not pvp then
    return nil
  end
  local lines = {}
  local rank = rankText(pvp)
  if rank then
    lines[#lines + 1] = string.format(L["rosterstats.tip.rank"], rank)
  end
  if pvp.honor and pvp.honor > 0 then
    lines[#lines + 1] = string.format(L["rosterstats.tip.honor"], S.Group(pvp.honor))
  end
  if pvp.kills and pvp.kills > 0 then
    lines[#lines + 1] = string.format(L["rosterstats.tip.kills"], S.Group(pvp.kills))
  end
  if pvp.highestRank and pvp.highestRank > 0 then
    lines[#lines + 1] = string.format(L["rosterstats.tip.highest"], pvp.highestRank)
  end
  for _, r in ipairs(pvp.ratings) do
    local line = string.format(L["rosterstats.tip.rating"], r.bracket, S.Group(r.rating))
    if r.best and r.best > 0 then
      line = line .. string.format(L["rosterstats.tip.best"], S.Group(r.best))
    end
    lines[#lines + 1] = line
  end
  if #lines == 0 then
    return nil
  end
  lines[#lines + 1] = ageLine(pvp.at, now)
  return lines
end

local function repLines(profile, now)
  local rep = S.CleanRep(profile.rep)
  if not rep then
    return nil
  end
  local lines = {}
  for i = 1, math.min(#rep.list, S.TIP_REP) do
    local e = rep.list[i]
    local parts = {}
    if e.label then
      parts[#parts + 1] = e.label
    end
    if e.max > 0 then
      parts[#parts + 1] = S.Group(e.value) .. "/" .. S.Group(e.max)
    end
    lines[#lines + 1] = #parts > 0 and (e.name .. ": " .. table.concat(parts, " ")) or e.name
  end
  if #rep.list > S.TIP_REP then
    lines[#lines + 1] = string.format(L["rosterstats.tip.more"], #rep.list - S.TIP_REP)
  end
  lines[#lines + 1] = ageLine(rep.at, now)
  return lines
end

local function statsLines(profile, now)
  local stats = S.CleanStats(profile.stats)
  if not stats then
    return nil
  end
  local lines = {}
  for _, e in ipairs(stats.list) do
    lines[#lines + 1] = (e.name or string.format(L["rosterstats.stat.unnamed"], e.id)) .. ": " .. S.Group(e.value)
  end
  lines[#lines + 1] = ageLine(stats.at, now)
  return lines
end

local LINES = { playtime = playtimeLines, pvp = pvpLines, rep = repLines, stats = statsLines }

-- The tooltip lines for one kind as a list of strings, nil without data. `now` (server time) adds the
-- age of the reading.
function S.TooltipLines(profile, kind, now)
  local build = type(profile) == "table" and LINES[kind]
  return build and build(profile, now) or nil
end

-- Played time per character ---------------------------------------------------------------------

-- A copy of the entry with the played time brought up to `now`: the logged-in character keeps playing
-- after the reading, so its stored seconds grow by the time since `playedAt`. Others stay as read.
-- played is nil for a character without a reading (never measured or 0).
function S.LivePlayed(entry, now)
  local out = { played = whole(entry.played, 1, 1e9), levelPlayed = whole(entry.levelPlayed, 0, 1e9) }
  out.playedAt = num(entry.playedAt, 0, 1e11)
  if out.played and entry.current and out.playedAt and out.playedAt > 0 and type(now) == "number" then
    local gap = math.max(0, math.floor(now - out.playedAt))
    out.played = out.played + gap
    out.levelPlayed = out.levelPlayed and out.levelPlayed + gap or nil
    out.playedAt = now
  end
  return out
end

-- The rows of the played time overview for the shown characters (hidden ones stay out), longest
-- first, without a reading last, then by name. Returns rows = { { entry, played, levelPlayed, playedAt } },
-- total (seconds of all rows with a reading), missing (rows without one).
function S.PlayedRows(entries, now)
  local rows, total, missing = {}, 0, 0
  for _, entry in ipairs(entries or {}) do
    if not entry.hidden then
      local live = S.LivePlayed(entry, now)
      live.entry = entry
      rows[#rows + 1] = live
      if live.played then
        total = total + live.played
      else
        missing = missing + 1
      end
    end
  end
  table.sort(rows, function(a, b)
    if (a.played or 0) ~= (b.played or 0) then
      return (a.played or 0) > (b.played or 0)
    end
    local an, bn = a.entry.display:lower(), b.entry.display:lower()
    return an ~= bn and an < bn or an == bn and a.entry.key < b.entry.key
  end)
  return { rows = rows, total = total, missing = missing }
end

-- Table columns -----------------------------------------------------------------------------------

-- A table keeps every column. Widths per font `factor` (1 = base size) and whether the row is wider than
-- the room it has: then the table scrolls horizontally and the first column (icons and name) stays put,
-- unless it would take more than FREEZE_MAX of the view.
local FREEZE_MAX = 0.5

-- Where the columns of a row sit in a view of `width`, laid out right to left from the end of the row.
-- spec: lead (space left of the name), tail (space at the right end), gap, nameMin (narrowest name),
-- columns = { { id, w } } in display order. The columns and the name never get narrower than their minimum
-- (scaled by the font factor). The row is as wide as the view, or as wide as the minimums need when the
-- view is narrower: scroll is true then. Returns { x = { id = left }, w = { id = width }, nameW,
-- contentW (width of the row), viewW, scroll, range (how far the content scrolls, 0 .. contentW - viewW),
-- pinW (width of the first column with its gap), frozen (it stays while the rest scrolls) }.
function S.ColumnLayout(width, factor, spec)
  local f = type(factor) == "number" and factor >= 1 and math.min(factor, 4) or 1
  local view = type(width) == "number" and width > 0 and width or 0
  local cols = {}
  local need = spec.lead + math.ceil(spec.nameMin * f) + spec.tail
  for i, c in ipairs(spec.columns) do
    cols[i] = { id = c.id, w = math.ceil(c.w * f) }
    need = need + cols[i].w + spec.gap
  end
  local contentW = math.max(view, need)
  local x, pos, widths = contentW - spec.tail, {}, {}
  for i = #cols, 1, -1 do
    local c = cols[i]
    x = x - c.w
    pos[c.id], widths[c.id] = x, c.w
    x = x - spec.gap
  end
  local nameW = x - spec.lead
  local pinW = spec.lead + nameW + spec.gap
  local scroll = need > view
  return {
    x = pos,
    w = widths,
    nameW = nameW,
    contentW = contentW,
    viewW = view,
    scroll = scroll,
    range = contentW - view,
    pinW = pinW,
    frozen = scroll and pinW <= view * FREEZE_MAX,
  }
end
