-- Experience arithmetic without WoW API: the size of a level (learned value, table value scaled by
-- a calibration factor), walking XP across level borders, the values behind the bar placeholders,
-- template rendering, durations, and the session math (gain across level-ups, active time, rate,
-- ETA, time per level, chat texts, XP sources, the chat lines that report XP). The game side (events, quest log, SavedVariables) lives in
-- Modules/XpTracker.lua. Positions are (level, xp) with xp inside that level.
local _, ns = ...
local L = ns.L

local XL = {}
ns.XpLogic = XL

ns.AddLocale("enUS", {
  ["xpbar.dur.days"] = "%d d %d h",
  ["xpbar.dur.hours"] = "%d h %d min",
  ["xpbar.dur.minutes"] = "%d min",
  ["xpbar.dur.seconds"] = "%d s",
  ["xpbar.state.running"] = "running",
  ["xpbar.state.paused"] = "paused",
  ["xpbar.maxLevel"] = "Max level",
  ["xpbar.overflow"] = "+%s levels",
  ["xpbar.chat.full"] = "Level %d reached: level %d took %s (total %s).",
  ["xpbar.chat.levelOnly"] = "Level %d reached: level %d took %s.",
  ["xpbar.chat.totalOnly"] = "Level %d reached (total %s).",
  ["xpbar.chat.plain"] = "Level %d reached.",
  ["xpbar.chat.pubFull"] = "Level %d reached: level %d took %s (total played %s).",
  ["xpbar.chat.pubLevelOnly"] = "Level %d reached: level %d took %s.",
  ["xpbar.chat.pubTotalOnly"] = "Level %d reached (total played %s).",
  ["xpbar.chat.sayBlocked"] = "Say is blocked by the game here, the level-up line is shown for you only.",
  ["xpbar.report.time"] = "Level %d to %d took %s.",
  ["xpbar.report.missing"] = "No time stored for level %s.",
  ["xpbar.report.range"] = "Give two levels, the first one lower than the second.",
})
ns.AddLocale("deDE", {
  ["xpbar.dur.days"] = "%d Tg %d Std",
  ["xpbar.dur.hours"] = "%d Std %d Min",
  ["xpbar.dur.minutes"] = "%d Min",
  ["xpbar.dur.seconds"] = "%d Sek",
  ["xpbar.state.running"] = "läuft",
  ["xpbar.state.paused"] = "pausiert",
  ["xpbar.maxLevel"] = "Maximalstufe",
  ["xpbar.overflow"] = "+%s Stufen",
  ["xpbar.chat.full"] = "Stufe %d erreicht: Stufe %d dauerte %s (gesamt %s).",
  ["xpbar.chat.levelOnly"] = "Stufe %d erreicht: Stufe %d dauerte %s.",
  ["xpbar.chat.totalOnly"] = "Stufe %d erreicht (gesamt %s).",
  ["xpbar.chat.plain"] = "Stufe %d erreicht.",
  ["xpbar.chat.pubFull"] = "Stufe %d erreicht: Stufe %d dauerte %s (Spielzeit gesamt %s).",
  ["xpbar.chat.pubLevelOnly"] = "Stufe %d erreicht: Stufe %d dauerte %s.",
  ["xpbar.chat.pubTotalOnly"] = "Stufe %d erreicht (Spielzeit gesamt %s).",
  ["xpbar.chat.sayBlocked"] = "Sagen ist im Spiel hier gesperrt, die Aufstiegszeile siehst nur du.",
  ["xpbar.report.time"] = "Stufe %d bis %d dauerte %s.",
  ["xpbar.report.missing"] = "Für Stufe %s ist keine Zeit gespeichert.",
  ["xpbar.report.range"] = "Zwei Stufen angeben, die erste kleiner als die zweite.",
})

-- A factor within this share of 1 counts as no difference between the table and the client.
XL.FACTOR_TOLERANCE = 0.005
-- Fewest active seconds before a rate is shown.
XL.MIN_RATE_SECONDS = 60
-- Guard against a corrupt level far above the table.
local MAX_STEPS = 200
local NONE = "-"

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function whole(v)
  return finite(v) and v == math.floor(v)
end

local function validSize(v)
  return finite(v) and v > 0
end

local function nonNegative(v)
  return finite(v) and v > 0 and v or 0
end

-- Size of a level -----------------------------------------------------------------------------------

-- Calibration factor of the table: max (UnitXPMax of the current level) against the table value of
-- that level. A difference within XL.FACTOR_TOLERANCE counts as the same table, factor 1.
function XL.Factor(level, max, tbl)
  tbl = tbl or ns.XpTable
  local base = whole(level) and tbl and tbl.need[level]
  if not base or not validSize(max) then
    return 1
  end
  if math.abs(max - base) / base > XL.FACTOR_TOLERANCE then
    return max / base
  end
  return 1
end

-- The sizes a calculation works with: learned values, the table, the factor, and the current level
-- taken from `max` as it is (it is the freshest reading there is). Call once per calculation.
function XL.Sizes(learned, level, max, tbl)
  tbl = tbl or ns.XpTable
  local ctx = { table = tbl, maxLevel = tbl.maxLevel, factor = XL.Factor(level, max, tbl), learned = learned }
  if whole(level) and validSize(max) then
    ctx.learned = setmetatable({ [level] = max }, { __index = learned })
  end
  return ctx
end

-- XP from `level` to the next one and whether the value is an estimate. Order: learned value, table
-- value times factor (estimate when the factor is not 1), the last known size when the table has a gap
-- below its maximum. nil above the maximum level (no level up) and for no level at all.
function XL.Need(level, ctx)
  ctx = ctx or {}
  local tbl = ctx.table or ns.XpTable
  if not whole(level) or level < 1 or level > (ctx.maxLevel or tbl.maxLevel) then
    return nil
  end
  local learned = ctx.learned
  local factor = ctx.factor or 1
  local known = learned and learned[level]
  if validSize(known) then
    return known, false
  end
  local base = tbl.need[level]
  if base then
    return math.floor(base * factor + 0.5), factor ~= 1
  end
  for below = level - 1, 1, -1 do
    known = learned and learned[below]
    if validSize(known) then
      return known, true
    end
    base = tbl.need[below]
    if base then
      return math.floor(base * factor + 0.5), true
    end
  end
  return nil
end

-- Walking ----------------------------------------------------------------------------------------------

-- Adds `amount` XP to the position (level, xp) and walks on level by level. Result: levels (whole
-- levels crossed), fraction (0 to 1 inside the target level), level (target), atCap (the walk ends on
-- the maximum level, there is nothing above to cross into), estimated (a size of an estimate was
-- used) and total = levels + fraction. On the maximum level the fraction stops at 1.
function XL.Walk(level, xp, amount, ctx)
  local tbl = (ctx and ctx.table) or ns.XpTable
  local maxLevel = (ctx and ctx.maxLevel) or tbl.maxLevel
  local need, estimated = XL.Need(level, ctx)
  if not need then
    return { levels = 0, fraction = 0, level = level, atCap = true, estimated = false, total = 0 }
  end
  local at = math.min(nonNegative(xp), need)
  local rest = nonNegative(amount)
  local current = level
  for _ = 1, MAX_STEPS do
    local room = need - at
    if current >= maxLevel then
      at = math.min(at + rest, need)
      break
    elseif rest < room then
      at = at + rest
      break
    end
    local nextNeed, nextEstimated = XL.Need(current + 1, ctx)
    if not nextNeed then
      at = need
      break
    end
    rest = rest - room
    current, need, at = current + 1, nextNeed, 0
    estimated = estimated or nextEstimated
  end
  local fraction = at / need
  local levels = current - level
  return {
    levels = levels,
    fraction = fraction,
    level = current,
    atCap = current >= maxLevel,
    estimated = estimated,
    total = levels + fraction,
  }
end

-- XP still needed to reach level `target` from (level, xp, max): the rest of this level plus every
-- level in between. nil when target is not above level or beyond the maximum level.
function XL.ToLevel(level, xp, max, target, ctx)
  if not whole(target) or target <= level then
    return nil
  end
  local size, estimated = max, false
  if not validSize(size) then
    size, estimated = XL.Need(level, ctx)
  end
  if not size or target > ((ctx and ctx.maxLevel) or ns.XpTable.maxLevel) or target - level > MAX_STEPS then
    return nil
  end
  local sum = math.max(0, size - nonNegative(xp))
  for between = level + 1, target - 1 do
    local need, guess = XL.Need(between, ctx)
    if not need then
      return nil
    end
    sum = sum + need
    estimated = estimated or guess
  end
  return sum, estimated
end

-- Text formats -------------------------------------------------------------------------------------------

local function groupDigits(digits, separator)
  local grouped = digits:reverse():gsub("(%d%d%d)", "%1" .. separator):reverse()
  if grouped:sub(1, #separator) == separator then
    grouped = grouped:sub(#separator + 1)
  end
  return grouped
end

-- n with thousands separators and `decimals` places in the separators of the active language.
function XL.Number(n, decimals)
  if not finite(n) then
    return NONE
  end
  decimals = decimals or 0
  local german = ns.GetActiveLocale() == "deDE"
  local text = string.format("%." .. decimals .. "f", math.abs(n))
  local integer, fraction = text:match("^(%d+)%.?(%d*)$")
  local out = groupDigits(integer, german and "." or ",")
  if decimals > 0 then
    out = out .. (german and "," or ".") .. fraction
  end
  if n < 0 and tonumber(text) ~= 0 then
    out = "-" .. out
  end
  return out
end

-- "3 d 4 h", "2 h 14 min", "5 min", "40 s" (German: Tg, Std, Min, Sek).
function XL.Duration(seconds)
  if not finite(seconds) then
    return NONE
  end
  seconds = math.max(0, math.floor(seconds))
  local days, hours, minutes =
    math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
  if days > 0 then
    return string.format(L["xpbar.dur.days"], days, hours)
  elseif hours > 0 then
    return string.format(L["xpbar.dur.hours"], hours, minutes)
  elseif minutes > 0 then
    return string.format(L["xpbar.dur.minutes"], minutes)
  end
  return string.format(L["xpbar.dur.seconds"], seconds)
end

-- Session --------------------------------------------------------------------------------------------------
-- A session is a plain table: active (seconds up to `since`), since (clock at the last resume, nil
-- while paused), running, gained (XP), startedAt (wall clock), auto (paused by AFK), and the sums of
-- the sources the events explain (XL.SOURCE_FIELDS).

XL.SOURCE_FIELDS = { "kills", "kill_xp", "quest_xp", "explore_xp", "rested_gained", "group_xp" }

function XL.SessionNew(now, wall)
  local s = { active = 0, since = now, running = true, gained = 0, startedAt = wall, auto = false }
  for _, field in ipairs(XL.SOURCE_FIELDS) do
    s[field] = 0
  end
  return s
end

function XL.ActiveSeconds(s, now)
  if not s then
    return 0
  end
  local total = nonNegative(s.active)
  if s.running and finite(now) and finite(s.since) then
    total = total + math.max(0, now - s.since)
  end
  return total
end

-- True when the state changed.
function XL.Pause(s, now, auto)
  if not s.running then
    return false
  end
  s.active = XL.ActiveSeconds(s, now)
  s.since, s.running, s.auto = nil, false, auto == true
  return true
end

function XL.Resume(s, now)
  if s.running then
    return false
  end
  s.since, s.running, s.auto = now, true, false
  return true
end

-- XP gained between two readings { level, xp, max }, across level-ups: the rest of the old level
-- (`last.max` carried from the previous reading), the new XP, and the size of every level skipped.
-- A lower level or a lower XP counts as nothing. Second result: an estimate went in.
function XL.Gain(last, cur, ctx)
  if type(last) ~= "table" or type(cur) ~= "table" or not finite(last.xp) or not finite(cur.xp) then
    return 0, false
  end
  if cur.level == last.level then
    return math.max(0, cur.xp - last.xp), false
  end
  if not whole(last.level) or not whole(cur.level) or cur.level < last.level or cur.level - last.level > MAX_STEPS then
    return 0, false
  end
  local estimated = false
  local size = last.max
  if not validSize(size) then
    size, estimated = XL.Need(last.level, ctx)
  end
  local sum = math.max(0, (size or 0) - last.xp) + math.max(0, cur.xp)
  for between = last.level + 1, cur.level - 1 do
    local need, guess = XL.Need(between, ctx)
    sum = sum + (need or 0)
    estimated = estimated or guess == true
  end
  return sum, estimated
end

-- Counts a gain while the session runs. Returns the XP added.
function XL.Record(s, gain)
  if not s.running or not finite(gain) or gain <= 0 then
    return 0
  end
  s.gained = nonNegative(s.gained) + gain
  return gain
end

-- `amount` per hour: from XL.MIN_RATE_SECONDS active seconds on and with an amount, else nil.
local function perHour(s, now, amount)
  local active = XL.ActiveSeconds(s, now)
  amount = nonNegative(amount)
  if active < XL.MIN_RATE_SECONDS or amount <= 0 then
    return nil
  end
  return amount / active * 3600
end

-- XP per hour.
function XL.Rate(s, now)
  return perHour(s, now, s and s.gained)
end

-- Counts what an event explains: src = { kind = "kill" | "quest" | "explore", xp, rested, group }.
-- These sums describe the gain, the readings of XP alone add to `gained`. Returns the XP counted.
function XL.RecordSource(s, src)
  if not s.running or type(src) ~= "table" or not finite(src.xp) or src.xp <= 0 then
    return 0
  end
  if src.kind == "kill" then
    s.kills = nonNegative(s.kills) + 1
    s.kill_xp = nonNegative(s.kill_xp) + src.xp
    s.rested_gained = nonNegative(s.rested_gained) + nonNegative(src.rested)
    s.group_xp = nonNegative(s.group_xp) + nonNegative(src.group)
  elseif src.kind == "quest" then
    s.quest_xp = nonNegative(s.quest_xp) + src.xp
  elseif src.kind == "explore" then
    s.explore_xp = nonNegative(s.explore_xp) + src.xp
  else
    return 0
  end
  return src.xp
end

-- Seconds until `xp` more are earned at `rate`; nil without a rate or an amount.
function XL.Eta(xp, rate)
  if not finite(xp) or not finite(rate) or rate <= 0 then
    return nil
  end
  return math.max(0, xp) / rate * 3600
end

-- The persistable form (no clock values that mean nothing after a reload).
function XL.SessionSave(s, now, wall)
  local out = {
    active = XL.ActiveSeconds(s, now),
    gained = nonNegative(s.gained),
    running = s.running == true,
    auto = s.auto == true,
    startedAt = finite(s.startedAt) and s.startedAt or nil,
    savedAt = wall,
  }
  for _, field in ipairs(XL.SOURCE_FIELDS) do
    out[field] = nonNegative(s[field])
  end
  return out
end

-- A session from SavedVariables, nil when the table is not usable. Time offline is not counted.
function XL.SessionLoad(raw, now)
  if type(raw) ~= "table" or not finite(raw.active) or not finite(raw.gained) then
    return nil
  end
  local running = raw.running ~= false
  local s = {
    active = nonNegative(raw.active),
    since = running and now or nil,
    running = running,
    gained = nonNegative(raw.gained),
    startedAt = finite(raw.startedAt) and raw.startedAt or nil,
    auto = raw.auto == true,
  }
  for _, field in ipairs(XL.SOURCE_FIELDS) do
    s[field] = nonNegative(raw[field])
  end
  return s
end

-- The last reading (level, xp, max) the gain is measured from, saved so that a reload loses nothing.
-- A reading older than BASE_MAX_AGE is not taken back: XP of a longer gap may belong to time the session
-- did not count (offline, add-on off, another client), and counting it would inflate the rate.
XL.BASE_MAX_AGE = 120

-- { level, xp, max, savedAt } or nil for a reading that is not complete.
function XL.BaseSave(last, wall)
  if type(last) ~= "table" or not whole(last.level) or not finite(last.xp) or not validSize(last.max) then
    return nil
  end
  if not finite(wall) then
    return nil
  end
  return { level = last.level, xp = last.xp, max = last.max, savedAt = wall }
end

-- The reading { level, xp, max } of a saved base that is recent enough at `wall`, else nil.
function XL.BaseLoad(raw, wall)
  local saved = XL.BaseSave(raw, type(raw) == "table" and raw.savedAt or nil)
  if not saved or not finite(wall) then
    return nil
  end
  local age = wall - saved.savedAt
  if age < 0 or age > XL.BASE_MAX_AGE then
    return nil
  end
  return { level = saved.level, xp = saved.xp, max = saved.max }
end

-- Played time -------------------------------------------------------------------------------------------------
-- played = { total, at }: the total played seconds the game reported and the clock at that moment.

function XL.PlayedNow(played, now)
  if type(played) ~= "table" or not finite(played.total) or not finite(now) or not finite(played.at) then
    return nil
  end
  return played.total + math.max(0, now - played.at)
end

-- Played seconds at the start of a level, from TIME_PLAYED_MSG (total, thisLevel); nil for odd numbers.
function XL.LevelStartFromPlayed(total, thisLevel)
  if not finite(total) or not finite(thisLevel) or thisLevel < 0 or thisLevel > total then
    return nil
  end
  return total - thisLevel
end

-- Seconds spent on the current level so far, nil without a stored start or played time.
function XL.LevelTime(starts, level, played, now)
  local start = type(starts) == "table" and starts[level]
  local total = XL.PlayedNow(played, now)
  if not finite(start) or not total or start > total then
    return nil
  end
  return total - start
end

-- Time from level `from` to level `to` = start of `to` minus start of `from`. Result: { from, to,
-- seconds (nil when an end is missing), missing = levels without an entry } or { error = "range" }.
function XL.Between(starts, from, to)
  if not whole(from) or not whole(to) or from < 1 or from >= to then
    return { error = "range" }
  end
  starts = type(starts) == "table" and starts or {}
  local result = { from = from, to = to, missing = {} }
  for _, level in ipairs({ from, to }) do
    if not finite(starts[level]) then
      result.missing[#result.missing + 1] = level
    end
  end
  if #result.missing == 0 then
    if starts[to] >= starts[from] then
      result.seconds = starts[to] - starts[from]
    else
      result.missing = { from, to }
    end
  end
  return result
end

-- The chat line of XL.Between.
function XL.ReportText(r)
  if r.error then
    return L["xpbar.report.range"]
  elseif r.seconds then
    return string.format(L["xpbar.report.time"], r.from, r.to, XL.Duration(r.seconds))
  end
  local names = {}
  for i, level in ipairs(r.missing) do
    names[i] = tostring(level)
  end
  return string.format(L["xpbar.report.missing"], table.concat(names, ", "))
end

-- The chat line for reaching `level`: how long the level before took and the total played time.
-- Either number may be nil. `public` words the line for a channel others read ("total played").
function XL.ChatLevelUp(level, levelSeconds, totalSeconds, public)
  local hasLevel, hasTotal = finite(levelSeconds), finite(totalSeconds)
  if hasLevel and hasTotal then
    return string.format(
      L[public and "xpbar.chat.pubFull" or "xpbar.chat.full"],
      level,
      level - 1,
      XL.Duration(levelSeconds),
      XL.Duration(totalSeconds)
    )
  elseif hasLevel then
    return string.format(
      L[public and "xpbar.chat.pubLevelOnly" or "xpbar.chat.levelOnly"],
      level,
      level - 1,
      XL.Duration(levelSeconds)
    )
  elseif hasTotal then
    return string.format(
      L[public and "xpbar.chat.pubTotalOnly" or "xpbar.chat.totalOnly"],
      level,
      XL.Duration(totalSeconds)
    )
  end
  return string.format(L["xpbar.chat.plain"], level)
end

-- XP chat lines --------------------------------------------------------------------------------------------------
-- The client words its XP lines in format strings ("%s dies, you gain %d experience."). The patterns are
-- built from the strings the client itself has, so every language reads the same way, and a string a
-- client does not have is skipped.

-- One capture per %s or %d, anchored. Second result: the argument number of each capture (the "2" of
-- "%2$s", else the running count), third: "s" or "d" per capture. nil for no string or no placeholder.
function XL.FormatPattern(format)
  if type(format) ~= "string" then
    return nil
  end
  local pattern, args, kinds = {}, {}, {}
  local i = 1
  while i <= #format do
    if format:sub(i, i) == "%" then
      local position, kind, after = format:match("^%%(%d+)%$([sd])()", i)
      if not kind then
        kind, after = format:match("^%%([sd])()", i)
      end
      if kind then
        args[#args + 1] = tonumber(position) or #args + 1
        kinds[#kinds + 1] = kind
        pattern[#pattern + 1] = kind == "d" and "(%d+)" or "(.-)"
        i = after
      elseif format:sub(i, i + 1) == "%%" then
        pattern[#pattern + 1] = "%%"
        i = i + 2
      else
        return nil
      end
    else
      pattern[#pattern + 1] = (format:sub(i, i):gsub("%p", "%%%0"))
      i = i + 1
    end
  end
  if #args == 0 then
    return nil
  end
  return "^" .. table.concat(pattern) .. "$", args, kinds
end

-- Strings of the kill lines: the base names, each with a group and a raid variant. UNNAMED lines carry no
-- creature (a quest turn-in), EXHAUSTION1 and 2 add a rested bonus, 4 and 5 a penalty. The variants come
-- first: a %s of the plain string would swallow their tail.
local GAIN_BASES = {
  "FIRSTPERSON",
  "FIRSTPERSON_UNNAMED",
  "EXHAUSTION1",
  "EXHAUSTION2",
  "EXHAUSTION4",
  "EXHAUSTION5",
}
local GAIN_VARIANTS = { "_GROUP", "_RAID", "" }

-- The captures after the XP one, in the order of the arguments: { capture index, kind } each.
local function extras(args, kinds, xpAt)
  local out = {}
  for at = 1, #args do
    if args[at] > args[xpAt] then
      out[#out + 1] = { at = at, kind = kinds[at] }
    end
  end
  table.sort(out, function(a, b)
    return args[a.at] < args[b.at]
  end)
  return out
end

local function compile(format, base, variant)
  local pattern, args, kinds = XL.FormatPattern(format)
  if not pattern then
    return nil
  end
  -- The XP is the first number argument.
  local xpAt
  for at = 1, #args do
    if kinds[at] == "d" and (not xpAt or args[at] < args[xpAt]) then
      xpAt = at
    end
  end
  if not xpAt then
    return nil
  end
  local after = extras(args, kinds, xpAt)
  local entry = { pattern = pattern, xpAt = xpAt, named = not base:find("UNNAMED", 1, true) }
  if base:find("^EXHAUSTION[12]") and after[1] then
    entry.restedAt = after[1].at
  end
  local last = after[#after]
  if variant == "_GROUP" and last and last.kind == "d" and last.at ~= entry.restedAt then
    entry.groupAt = last.at
  end
  return entry
end

-- A number out of a captured text ("+100", "1.250"): digits only, separators dropped.
local function amountIn(text)
  local run = text:match("%d[%d.,]*")
  return run and tonumber((run:gsub("[.,]", ""))) or nil
end

-- The parsers of the client: { gain = {...}, explore = entry or nil }. `lookup(name)` gives a global string.
function XL.ChatParsers(lookup)
  local parsers = { gain = {} }
  for _, base in ipairs(GAIN_BASES) do
    for _, variant in ipairs(GAIN_VARIANTS) do
      local entry = compile(lookup("COMBATLOG_XPGAIN_" .. base .. variant), base, variant)
      if entry then
        parsers.gain[#parsers.gain + 1] = entry
      end
    end
  end
  parsers.explore = compile(lookup("ERR_ZONE_EXPLORED_XP"), "EXPLORE", "")
  return parsers
end

-- A CHAT_MSG_COMBAT_XP_GAIN line: { kind = "kill" | "nameless", xp, rested, group } or nil. Rested and
-- group are 0 where the line has none.
function XL.ParseGain(parsers, text)
  if type(text) ~= "string" then
    return nil
  end
  for _, entry in ipairs(parsers.gain) do
    local found = { text:match(entry.pattern) }
    local xp = found[1] ~= nil and amountIn(found[entry.xpAt]) or nil
    if xp then
      return {
        kind = entry.named and "kill" or "nameless",
        xp = xp,
        rested = entry.restedAt and amountIn(found[entry.restedAt]) or 0,
        group = entry.groupAt and amountIn(found[entry.groupAt]) or 0,
      }
    end
  end
  return nil
end

-- The XP of a discovery line (CHAT_MSG_SYSTEM), nil for any other text.
function XL.ParseExplore(parsers, text)
  local entry = parsers.explore
  if type(text) ~= "string" or not entry then
    return nil
  end
  local found = { text:match(entry.pattern) }
  return found[1] ~= nil and amountIn(found[entry.xpAt]) or nil
end

-- Values ---------------------------------------------------------------------------------------------------------

-- The values behind the placeholders. Input: level, xp, max, rested, doneXp, todoXp, atMax, sizes
-- (XL.Sizes), session, played, levelStart, now. The sources come from the session: other_xp is what the
-- readings gained beyond the XP the events explain (never below 0). Percentages across levels come from XL.Walk, the
-- "_cur" ones are relative to the current level only. est[name] = true marks values built on an
-- estimated level size. bar = fractions 0..1 for the layers (XP, completed quests, rested), each
-- measured from the current XP and cut at the end of the level.
function XL.Compute(i)
  local est = {}
  local v = { est = est }
  local tbl = (i.sizes and i.sizes.table) or ns.XpTable
  v.maxLevel = (i.sizes and i.sizes.maxLevel) or tbl.maxLevel
  v.level = whole(i.level) and i.level or nil
  v.valid = v.level ~= nil and finite(i.xp) and validSize(i.max)
  v.atMax = i.atMax == true or (v.level ~= nil and v.level >= v.maxLevel)
  v.rested, v.done, v.todo = nonNegative(i.rested), nonNegative(i.doneXp), nonNegative(i.todoXp)
  local now = i.now
  local s = i.session
  v.state = s and s.running == false and "paused" or "running"
  v.session_gain = s and nonNegative(s.gained) or 0
  v.kills = s and nonNegative(s.kills) or 0
  v.kill_xp = s and nonNegative(s.kill_xp) or 0
  v.quest_xp = s and nonNegative(s.quest_xp) or 0
  v.explore_xp = s and nonNegative(s.explore_xp) or 0
  v.other_xp = math.max(0, v.session_gain - v.kill_xp - v.quest_xp - v.explore_xp)
  v.xp_per_kill = v.kills > 0 and v.kill_xp / v.kills or nil
  v.kills_per_hour = perHour(s, now, v.kills)
  v.session_time = XL.ActiveSeconds(s, now)
  v.xph = s and XL.Rate(s, now) or nil
  v.played = XL.PlayedNow(i.played, now)
  v.level_time = v.level and XL.LevelTime(i.levelStart, v.level, i.played, now) or nil
  v.bar = { xp = 0, done = 0, rested = 0 }
  if not v.valid then
    return v
  end
  local ctx = i.sizes
  local level, xp, max = v.level, math.min(i.xp, i.max), i.max
  v.xp, v.max = xp, max
  v.pct = xp / max * 100
  v.remaining = max - xp
  v.remaining_pct = 100 - v.pct
  v.mobs_to_level = v.xp_per_kill and v.xp_per_kill > 0 and math.ceil(v.remaining / v.xp_per_kill) or nil
  v.rested_pct_cur = v.rested / max * 100
  v.done_pct_cur = v.done / max * 100
  local here = level + xp / max
  local restedWalk = XL.Walk(level, xp, v.rested, ctx)
  local doneWalk = XL.Walk(level, xp, v.done, ctx)
  v.rested_levels = restedWalk.level + restedWalk.fraction - here
  v.done_levels = doneWalk.level + doneWalk.fraction - here
  v.rested_pct, v.done_pct = v.rested_levels * 100, v.done_levels * 100
  v.total_pct = doneWalk.total * 100
  est.rested_levels, est.rested_pct = restedWalk.estimated, restedWalk.estimated
  est.done_levels, est.done_pct, est.total_pct = doneWalk.estimated, doneWalk.estimated, doneWalk.estimated
  local farthest = math.max(restedWalk.level + restedWalk.fraction, doneWalk.level + doneWalk.fraction)
  v.overflow = math.max(0, farthest - (level + 1))
  est.overflow = (restedWalk.estimated or doneWalk.estimated) and v.overflow > 0
  v.bar = {
    xp = xp / max,
    done = math.min(1, (xp + v.done) / max),
    rested = math.min(1, (xp + v.rested) / max),
  }
  v.eta = XL.Eta(v.remaining, v.xph)
  -- XP up to level N and the time it takes at the current rate.
  v.toLevel = function(target)
    return XL.ToLevel(level, xp, max, target, ctx)
  end
  v.etaTo = function(target)
    local need, guess = XL.ToLevel(level, xp, max, target, ctx)
    return XL.Eta(need, v.xph), guess
  end
  return v
end

-- Rendering ---------------------------------------------------------------------------------------------------------

-- Text for one placeholder; `o` = { number = function(n, decimals) }. Never nil for a known name.
local function number(o, n, decimals)
  return (o.number or XL.Number)(n, decimals)
end

local function mark(v, name, text)
  return v.est[name] and "~" .. text or text
end

local function percent(name)
  return function(v, _, o)
    return mark(v, name, number(o, v[name], 1))
  end
end

local function count(name)
  return function(v, _, o)
    return number(o, v[name], 0)
  end
end

local function seconds(name)
  return function(v)
    return XL.Duration(v[name])
  end
end

local function plain(name)
  return function(v)
    return v[name] ~= nil and tostring(v[name]) or NONE
  end
end

local PLACEHOLDERS = {
  level = plain("level"),
  max_level = plain("maxLevel"),
  xp = count("xp"),
  max = count("max"),
  pct = percent("pct"),
  remaining = count("remaining"),
  remaining_pct = percent("remaining_pct"),
  rested = count("rested"),
  rested_pct = percent("rested_pct"),
  rested_pct_cur = percent("rested_pct_cur"),
  rested_levels = function(v, _, o)
    return mark(v, "rested_levels", number(o, v.rested_levels, 1))
  end,
  done = count("done"),
  done_pct = percent("done_pct"),
  done_pct_cur = percent("done_pct_cur"),
  todo = count("todo"),
  total_pct = percent("total_pct"),
  overflow = function(v, _, o)
    if v.overflow <= 0 then
      return ""
    end
    return mark(v, "overflow", string.format(L["xpbar.overflow"], number(o, v.overflow, 1)))
  end,
  xph = function(v, _, o)
    return v.xph and number(o, v.xph, 0) or NONE
  end,
  eta = seconds("eta"),
  eta_to = function(v, arg)
    local target = tonumber(arg)
    if not target then
      return nil
    end
    local eta, guess = v.etaTo(target)
    if not eta then
      return NONE
    end
    return (guess and "~" or "") .. XL.Duration(eta)
  end,
  session_gain = count("session_gain"),
  kill_xp = count("kill_xp"),
  quest_xp = count("quest_xp"),
  explore_xp = count("explore_xp"),
  other_xp = count("other_xp"),
  kills = count("kills"),
  kills_per_hour = function(v, _, o)
    return v.kills_per_hour and number(o, v.kills_per_hour, 1) or NONE
  end,
  xp_per_kill = count("xp_per_kill"),
  mobs_to_level = count("mobs_to_level"),
  session_time = seconds("session_time"),
  level_time = seconds("level_time"),
  played = seconds("played"),
  state = function(v)
    return L["xpbar.state." .. v.state]
  end,
}

-- Placeholders that mean nothing at the maximum level (the XP bar is full or has no meaning there).
local XP_ONLY = {
  xp = true,
  max = true,
  pct = true,
  remaining = true,
  remaining_pct = true,
  rested = true,
  rested_pct = true,
  rested_pct_cur = true,
  rested_levels = true,
  done = true,
  done_pct = true,
  done_pct_cur = true,
  todo = true,
  total_pct = true,
  overflow = true,
  eta = true,
  eta_to = true,
  mobs_to_level = true,
}
-- Placeholders that take an argument ({eta_to:30}).
local WITH_ARG = { eta_to = true }

-- Replaces {name} and {eta_to:N} in the template. An unknown placeholder stays as typed. Values that
-- are not known yet show "-", XP values at the maximum level show nothing.
function XL.Render(template, v, o)
  o = o or {}
  return (
    tostring(template or ""):gsub("{([^{}]*)}", function(key)
      local name, arg = key:match("^([%w_]+):(%d+)$")
      name = name or key
      local make = PLACEHOLDERS[name]
      if not make or (arg ~= nil) ~= (WITH_ARG[name] == true) then
        return nil
      end
      if XP_ONLY[name] and (v.atMax or not v.valid) then
        return v.atMax and "" or NONE
      end
      return make(v, arg, o)
    end)
  )
end

-- Names of the placeholders, sorted (for an insert list; eta_to carries the sample level 30).
function XL.PlaceholderNames()
  local names = {}
  for name in pairs(PLACEHOLDERS) do
    names[#names + 1] = name == "eta_to" and "eta_to:N" or name
  end
  table.sort(names)
  return names
end
