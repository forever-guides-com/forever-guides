-- Dates of guild members as intervals, no game calls. A date is DateInfo = { minDay, maxDay, src,
-- setDay }: day numbers (whole days since 1970 in local time, see DayOf), either end may be nil
-- (open), src names where the date comes from, setDay is the day it was recorded. The rule engine
-- (RulesLogic, PlanLogic) reads exactly this form.
--
-- Sources, strongest first: manual (typed by hand), note (marker in a guild note), log (server guild
-- log), chat (system message), diff / roster (roster comparison), shared (other officers), baseline
-- (start of recording). A date never lies in the future.
local _, gm = ...
if not gm.ext then
  return
end

local DL = {}
gm.DatesLogic = DL

-- WoW did not exist before this year.
DL.MIN_YEAR = 2004
DL.MAX_YEAR = 2100
DL.RANK = { manual = 8, note = 7, log = 6, chat = 5, diff = 4, roster = 4, shared = 3, baseline = 1 }
-- Names the task and the add-on use for the same source.
DL.ALIASES = { hand = "manual", server = "log", peer = "shared" }
DL.FORMATS = { "dmy", "iso", "mdy" }

local function whole(v)
  return type(v) == "number" and v == v and v >= 0 and v < math.huge and v == math.floor(v) and v or nil
end

local function num(v)
  return type(v) == "number" and v == v and v > 0 and v < math.huge and v or 0
end

-- Days and calendar ---------------------------------------------------------------------------------

-- Days since 1970-01-01 of a calendar date (proleptic Gregorian).
function DL.DayFromDate(y, m, d)
  if m <= 2 then
    y = y - 1
  end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

-- year, month, day of a day number.
function DL.DateFromDay(day)
  local z = day + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400
  return m <= 2 and y + 1 or y, m, d
end

-- True for a date that exists (no 30 February).
function DL.ValidDate(y, m, d)
  if not (whole(y) and whole(m) and whole(d)) or m < 1 or m > 12 or d < 1 or d > 31 then
    return false
  end
  local yy, mm, dd = DL.DateFromDay(DL.DayFromDate(y, m, d))
  return yy == y and mm == m and dd == d
end

-- Day number of a time stamp in local time; offset = seconds local time is ahead of UTC.
function DL.DayOf(t, offset)
  return math.floor((t + (offset or 0)) / 86400)
end

-- Offset in seconds from two date tables of the same moment (date("*t", t) and date("!*t", t)).
function DL.OffsetOf(localT, utcT)
  local function secs(t)
    return DL.DayFromDate(t.year, t.month, t.day) * 86400 + (t.hour or 0) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
  end
  return secs(localT) - secs(utcT)
end

-- "dmy" 12.03.2024, "iso" 2024-03-12, "mdy" 03/12/2024. "" for no day.
function DL.Format(day, format)
  if not whole(day) then
    return ""
  end
  local y, m, d = DL.DateFromDay(day)
  if format == "iso" then
    return string.format("%04d-%02d-%02d", y, m, d)
  elseif format == "mdy" then
    return string.format("%02d/%02d/%04d", m, d, y)
  end
  return string.format("%02d.%02d.%04d", d, m, y)
end

-- One date typed or written by a person: DD.MM.YYYY, DD.MM.YY, YYYY-MM-DD or with slashes. A slash
-- date needs order ("dmy" or "mdy") unless one number is above 12; without it the answer is
-- nil, "ambiguous". today (optional) rejects a date after it. Answers day or nil and the reason:
-- "invalid", "ambiguous", "range" (year out of bounds), "future".
function DL.ParseDate(text, order, today)
  if type(text) ~= "string" then
    return nil, "invalid"
  end
  text = text:match("^%s*(.-)%s*$")
  local a, b, c = text:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
  local y, m, d
  if a then
    y, m, d = a, b, c
  else
    a, b, c = text:match("^(%d%d?)%.(%d%d?)%.(%d+)$")
    if a then
      d, m, y = a, b, c
    else
      a, b, c = text:match("^(%d%d?)/(%d%d?)/(%d+)$")
      if not a then
        return nil, "invalid"
      end
      if order == "mdy" then
        m, d = a, b
      elseif order == "dmy" then
        d, m = a, b
      elseif tonumber(a) > 12 or tonumber(a) == tonumber(b) then
        d, m = a, b
      elseif tonumber(b) > 12 then
        m, d = a, b
      else
        return nil, "ambiguous"
      end
      y = c
    end
  end
  if #y == 2 then
    y = "20" .. y
  elseif #y ~= 4 then
    return nil, "invalid"
  end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not DL.ValidDate(y, m, d) then
    return nil, "invalid"
  end
  if y < DL.MIN_YEAR or y > DL.MAX_YEAR then
    return nil, "range"
  end
  local day = DL.DayFromDate(y, m, d)
  if whole(today) and day > today then
    return nil, "future"
  end
  return day
end

-- Date info ------------------------------------------------------------------------------------------

-- Canonical source name, nil for something that is no name.
function DL.Source(src)
  if type(src) ~= "string" or src == "" or #src > 12 then
    return nil
  end
  return DL.ALIASES[src] or src
end

-- Strength of a source, 0 for a name this version does not know.
function DL.Rank(src)
  return DL.RANK[DL.Source(src) or ""] or 0
end

-- A new date info, nil when it is empty (no end), reversed or without a source.
function DL.Info(minDay, maxDay, src, setDay)
  minDay, maxDay, src = whole(minDay), whole(maxDay), DL.Source(src)
  if not src or (not minDay and not maxDay) or (minDay and maxDay and maxDay < minDay) then
    return nil
  end
  return { minDay = minDay, maxDay = maxDay, src = src, setDay = whole(setDay) }
end

function DL.Exact(day, src, setDay)
  return DL.Info(day, day, src, setDay)
end

-- Repairs a stored value, nil when nothing usable is left.
function DL.Clean(v)
  if type(v) ~= "table" then
    return nil
  end
  return DL.Info(v.minDay, v.maxDay, v.src, v.setDay)
end

-- "exact", "range", "after" (minDay only), "before" (maxDay only), nil for no date.
function DL.Kind(info)
  info = DL.Clean(info)
  if not info then
    return nil
  elseif info.minDay and info.maxDay then
    return info.minDay == info.maxDay and "exact" or "range"
  end
  return info.minDay and "after" or "before"
end

-- A copy that does not end after today; nil when it starts after today.
function DL.Clamp(info, today)
  info = DL.Clean(info)
  if not info or not whole(today) then
    return info
  end
  if info.minDay and info.minDay > today then
    return nil
  end
  if info.maxDay and info.maxDay > today then
    info.maxDay = today
  end
  return info
end

-- The overlap of two infos, with the source of the stronger one. nil when they do not overlap.
function DL.Narrow(a, b)
  a, b = DL.Clean(a), DL.Clean(b)
  if not (a and b) then
    return nil
  end
  local lo = (a.minDay and b.minDay) and math.max(a.minDay, b.minDay) or a.minDay or b.minDay
  local hi = (a.maxDay and b.maxDay) and math.min(a.maxDay, b.maxDay) or a.maxDay or b.maxDay
  local stronger = DL.Rank(b.src) > DL.Rank(a.src) and b or a
  return DL.Info(lo, hi, stronger.src, math.max(a.setDay or 0, b.setDay or 0))
end

-- Combines what is known with a new finding (b), never in the future. A manual date always wins (the
-- newer one when both are manual). Otherwise the two narrow each other; when they contradict, the
-- stronger source wins and an equal one keeps a. today is optional.
function DL.Merge(a, b, today)
  a, b = DL.Clamp(a, today), DL.Clamp(b, today)
  if not (a and b) then
    return a or b
  end
  if a.src == "manual" or b.src == "manual" then
    return a.src ~= "manual" and b or (b.src ~= "manual" and a or b)
  end
  local both = DL.Narrow(a, b)
  if both then
    return both
  end
  return DL.Rank(b.src) > DL.Rank(a.src) and b or a
end

-- Server age -----------------------------------------------------------------------------------------

-- Whole days a server age can mean, lo and hi. The server gives years, months, days and hours; a
-- month has 28 to 31 days and a year may be counted two days short, so months weigh 28 for the lower
-- bound and 31 for the upper one. Under a month the days are exact (hours only fill the last day).
function DL.AgeBounds(years, months, days)
  years, months, days = num(years), num(months), num(days)
  local lo = math.max(0, years * 365 + months * 28 + days - (years > 0 and 2 or 0))
  local hi = years * 366 + months * 31 + days + 1
  if years == 0 and months == 0 then
    hi = days + 1
  end
  return lo, math.max(lo, hi)
end

-- The day of something that happened "years, months, days, hours ago" as a date info (src defaults to
-- "log"). With now (time stamp) and offset an age under a month gives the exact day in most cases.
function DL.FromServerAge(years, months, days, hours, today, src, now, offset)
  if not whole(today) then
    return nil
  end
  years, months, days, hours = num(years), num(months), num(days), num(hours)
  if years == 0 and months == 0 and type(now) == "number" then
    local ago = (days * 24 + hours) * 3600
    return DL.Clamp(
      DL.Info(DL.DayOf(now - ago - 3600, offset), DL.DayOf(now - ago, offset), src or "log", today),
      today
    )
  end
  local lo, hi = DL.AgeBounds(years, months, days)
  return DL.Clamp(DL.Info(math.max(0, today - hi), today - lo, src or "log", today), today)
end

-- When a roster row was last online: today for a member online now, the server age otherwise. nil when
-- the client did not say.
function DL.LastOnline(m, today, now, offset)
  if type(m) ~= "table" or not whole(today) then
    return nil
  end
  if m.online then
    return DL.Exact(today, "roster", today)
  end
  local t = m.last
  if type(t) ~= "table" then
    return nil
  end
  return DL.FromServerAge(t.years, t.months, t.days, t.hours, today, "roster", now, offset)
end

-- Text ------------------------------------------------------------------------------------------------

function DL.SourceText(info, L)
  info = DL.Clean(info)
  return info and (L["gm.date.src." .. info.src] or info.src) or ""
end

-- "12.03.2024", "earliest 05.10.2026, latest 12.10.2026" and so on in plain words; L is the locale
-- table, format one of DL.FORMATS.
function DL.Text(info, L, format)
  info = DL.Clean(info)
  local kind = DL.Kind(info)
  if not kind then
    return L["gm.date.unknown"]
  end
  local function day(d)
    return DL.Format(d, format)
  end
  if kind == "exact" then
    return string.format(L["gm.date.exact"], day(info.minDay))
  elseif kind == "range" then
    return string.format(L["gm.date.range"], day(info.minDay), day(info.maxDay))
  elseif kind == "after" then
    return string.format(L["gm.date.after"], day(info.minDay))
  end
  return string.format(L["gm.date.before"], day(info.maxDay))
end
