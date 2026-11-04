-- Reminders of the overview, no game calls and nothing is sent: what is due (a hint taken from the plan,
-- never an action), anniversaries, birthdays, returners, the traffic light per rank, absence and the
-- statistics of the week. The clock is an input (day numbers, see DatesLogic).
--
-- Data of a member entry (guild.members[key]), local only, never part of a share payload:
--   birthday = { month, day }   typed by hand, no year (29 February is allowed)
--   away     = untilDay         typed by hand, protects against the rules until that day (inclusive)
-- A row is the roster member joined with its entry: { key, name, rank, online, ago (hours), joined,
-- birthday, away, returnedDay, returnedAfter }.
local _, gm = ...
if not gm.ext then
  return
end
local DL, IL, ML = gm.DatesLogic, gm.InactivityLogic, gm.MembersLogic
local PN = gm.FG.PlayerName

local RM = {}
gm.RemindersLogic = RM

-- Anniversaries in years that are reminded.
RM.MILESTONES = { 1, 2, 5 }
RM.LEAD = { min = 1, max = 60, default = 14 }
-- A returner stays on the list this many days.
RM.RETURN_WINDOW = 14
-- Longest absence that can be typed (days ahead).
RM.MAX_AWAY = 365
-- Share of inactive members from which a rank turns yellow and red.
RM.YELLOW_FROM = 0.25
RM.RED_FROM = 0.5
RM.WEEK_STARTS = { "rolling", "mon", "sun" }
RM.MAX_CHAT_NAMES = 3
RM.MAX_CHAT = 200
-- 29 February needs a leap year: the check uses one.
local LEAP = 2000

local function whole(v)
  return type(v) == "number" and v == v and v >= 0 and v < math.huge and v == math.floor(v) and v or nil
end

local function sortByName(list)
  table.sort(list, function(a, b)
    local x, y = PN.Lower(a.name), PN.Lower(b.name)
    return x ~= y and x < y or (x == y and a.key < b.key)
  end)
  return list
end

-- Entry data ---------------------------------------------------------------------------------------------

-- Repairs birthday and away of a stored entry in place; a value that is not usable is dropped.
function RM.CleanMember(e)
  local b = e.birthday
  if type(b) == "table" and whole(b.month) and whole(b.day) and DL.ValidDate(LEAP, b.month, b.day) then
    e.birthday = { month = b.month, day = b.day }
  else
    e.birthday = nil
  end
  local away = whole(e.away)
  if away and away > 0 and away <= DL.DayFromDate(DL.MAX_YEAR, 12, 31) then
    e.away = away
  else
    e.away = nil
  end
end

-- "24.12", "24.12." (day first) or "12/24", "12-24" (month first). order: "dmy" (default), "mdy" or "iso"
-- (the last two read month first). No year: a third number is refused. Answers { month, day } or nil and
-- the reason: "empty", "format", "month", "day".
function RM.ParseBirthday(text, order)
  if type(text) ~= "string" then
    return nil, "format"
  end
  text = text:match("^%s*(.-)%s*$")
  if text == "" then
    return nil, "empty"
  end
  if #text > 6 then
    return nil, "format"
  end
  local a, b = text:match("^(%d%d?)[%./%-](%d%d?)%.?$")
  if not a then
    return nil, "format"
  end
  local monthFirst = order == "mdy" or order == "iso"
  local month, day = tonumber(monthFirst and a or b), tonumber(monthFirst and b or a)
  if month < 1 or month > 12 then
    return nil, "month"
  end
  if not DL.ValidDate(LEAP, month, day) then
    return nil, "day"
  end
  return { month = month, day = day }
end

-- "24.12" or "12/24" / "12-24" for the date format of the player.
function RM.FormatBirthday(b, order)
  if type(b) ~= "table" or not whole(b.month) or not whole(b.day) then
    return ""
  end
  if order == "iso" then
    return string.format("%02d-%02d", b.month, b.day)
  elseif order == "mdy" then
    return string.format("%02d/%02d", b.month, b.day)
  end
  return string.format("%02d.%02d", b.day, b.month)
end

-- A date for the end of an absence: today or later, at most MAX_AWAY days ahead. Answers the day or nil
-- and the reason: "empty", "invalid", "ambiguous", "range", "past", "far".
function RM.ParseAway(text, order, today)
  if type(text) == "string" and text:match("^%s*$") then
    return nil, "empty"
  end
  local day, why = DL.ParseDate(text, order)
  if not day then
    return nil, why == "future" and "invalid" or why
  end
  if whole(today) then
    if day < today then
      return nil, "past"
    elseif day > today + RM.MAX_AWAY then
      return nil, "far"
    end
  end
  return day
end

-- member: { key, name }. nil removes the birthday. Answers true, or false and the reason.
function RM.SetBirthday(store, member, b)
  if b == nil then
    local e = store[member.key]
    if e then
      e.birthday = nil
      ML.Keep(store, member.key)
    end
    return true
  end
  if type(b) ~= "table" or not (whole(b.month) and whole(b.day)) or not DL.ValidDate(LEAP, b.month, b.day) then
    return false, "format"
  end
  ML.Touch(store, member).birthday = { month = b.month, day = b.day }
  return true
end

-- day: last day of the absence (the member is protected on that day too), nil removes it.
function RM.SetAway(store, member, day)
  if day == nil then
    local e = store[member.key]
    if e then
      e.away = nil
      ML.Keep(store, member.key)
    end
    return true
  end
  if not whole(day) or day <= 0 then
    return false, "invalid"
  end
  ML.Touch(store, member).away = day
  return true
end

-- Removes every typed birthday of the guild record. Answers how many there were.
function RM.ClearBirthdays(guild)
  local n = 0
  for key, e in pairs(guild.members) do
    if type(e) == "table" and e.birthday ~= nil then
      e.birthday = nil
      n = n + 1
      ML.Keep(guild.members, key)
    end
  end
  return n
end

-- True while the member is away (the plan protects the same days).
function RM.IsAway(away, today)
  away = whole(away)
  return away ~= nil and whole(today) ~= nil and away >= today
end

-- Rows ---------------------------------------------------------------------------------------------------

-- roster: the members of the snapshot; store: guild.members.
function RM.Rows(roster, store)
  local rows = {}
  for _, m in ipairs(type(roster) == "table" and roster or {}) do
    if type(m) == "table" and type(m.key) == "string" then
      local e = type(store) == "table" and type(store[m.key]) == "table" and store[m.key] or {}
      rows[#rows + 1] = {
        key = m.key,
        name = type(m.name) == "string" and m.name or m.key,
        rank = m.rank,
        online = m.online == true,
        ago = type(m.ago) == "number" and m.ago or nil,
        joined = e.joined,
        birthday = e.birthday,
        away = e.away,
        returnedDay = e.returnedDay,
        returnedAfter = e.returnedAfter,
      }
    end
  end
  return rows
end

-- Calendar -----------------------------------------------------------------------------------------------

-- Day number of a month and day in a year; 29 February falls on the 28th in a year without one.
local function inYear(year, month, day)
  if month == 2 and day == 29 and not DL.ValidDate(year, 2, 29) then
    day = 28
  end
  return DL.DayFromDate(year, month, day)
end

-- Days until the next time the month and day come round (0 = today) and the day number of it.
function RM.NextOccurrence(month, day, today)
  local year = DL.DateFromDay(today)
  local at = inYear(year, month, day)
  if at < today then
    at = inYear(year + 1, month, day)
  end
  return at - today, at
end

-- Birthdays within `lead` days (today included), soonest first. Answers { list, count } where count is
-- how many members have a birthday at all.
function RM.Birthdays(rows, today, lead)
  local list, count = {}, 0
  for _, r in ipairs(rows) do
    local b = r.birthday
    if type(b) == "table" and whole(b.month) and whole(b.day) and DL.ValidDate(LEAP, b.month, b.day) then
      count = count + 1
      local inDays, at = RM.NextOccurrence(b.month, b.day, today)
      if inDays <= lead then
        list[#list + 1] = { key = r.key, name = r.name, month = b.month, day = b.day, inDays = inDays, at = at }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.inDays ~= b.inDays then
      return a.inDays < b.inDays
    end
    return PN.Lower(a.name) < PN.Lower(b.name) or (PN.Lower(a.name) == PN.Lower(b.name) and a.key < b.key)
  end)
  return { list = list, count = count }
end

-- Anniversaries of the join (RM.MILESTONES years) within `lead` days. A join date counts only when it is
-- known to the day: an interval of several days or an open one gives no day to remind of, such a member
-- is counted in `unknown`. `manual` says the date was typed by the player (names may go to the chat).
function RM.Anniversaries(rows, today, lead)
  local list, unknown = {}, 0
  for _, r in ipairs(rows) do
    local info = DL.Clean(r.joined)
    if not info or DL.Kind(info) ~= "exact" or info.maxDay > today then
      unknown = unknown + 1
    else
      local year, month, day = DL.DateFromDay(info.maxDay)
      for _, years in ipairs(RM.MILESTONES) do
        local at = inYear(year + years, month, day)
        local inDays = at - today
        if inDays >= 0 and inDays <= lead then
          list[#list + 1] = {
            key = r.key,
            name = r.name,
            years = years,
            inDays = inDays,
            at = at,
            manual = info.src == "manual",
          }
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if a.inDays ~= b.inDays then
      return a.inDays < b.inDays
    end
    if a.years ~= b.years then
      return a.years > b.years
    end
    return PN.Lower(a.name) < PN.Lower(b.name) or (PN.Lower(a.name) == PN.Lower(b.name) and a.key < b.key)
  end)
  return { list = list, unknown = unknown }
end

-- Returners and absence --------------------------------------------------------------------------------

-- Members marked "returned" within the last RM.RETURN_WINDOW days, most recent first.
function RM.Returners(rows, today)
  local list = {}
  for _, r in ipairs(rows) do
    local day = whole(r.returnedDay)
    if day and day <= today and today - day <= RM.RETURN_WINDOW then
      list[#list + 1] = {
        key = r.key,
        name = r.name,
        day = day,
        ago = today - day,
        after = whole(r.returnedAfter),
      }
    end
  end
  table.sort(list, function(a, b)
    if a.day ~= b.day then
      return a.day > b.day
    end
    return PN.Lower(a.name) < PN.Lower(b.name) or (PN.Lower(a.name) == PN.Lower(b.name) and a.key < b.key)
  end)
  return list
end

-- Members who are away today, the ones back soonest first.
function RM.AwayList(rows, today)
  local list = {}
  for _, r in ipairs(rows) do
    if RM.IsAway(r.away, today) then
      list[#list + 1] = { key = r.key, name = r.name, untilDay = r.away }
    end
  end
  table.sort(list, function(a, b)
    if a.untilDay ~= b.untilDay then
      return a.untilDay < b.untilDay
    end
    return a.key < b.key
  end)
  return list
end

-- Due ----------------------------------------------------------------------------------------------------

RM.DUE_GROUPS = { "promote", "demote", "remove", "mark" }
local DUE_GROUP =
  { promote = "promote", setRank = "promote", demote = "demote", remove = "remove", mark = "mark", none = "mark" }

-- What the plan (PlanLogic.Build) has ready: rank up, rank down, removal and "to check", per group a
-- list { key, name, rule, from, to, later }. A hint only: nothing here runs. `later` marks a step the
-- limit of a run keeps for the next one. Answers { groups, total, active } where active says a rule is
-- on (without one an empty list means nothing).
function RM.Due(plan)
  local groups = {}
  for _, g in ipairs(RM.DUE_GROUPS) do
    groups[g] = {}
  end
  local out = { groups = groups, total = 0, active = false }
  if type(plan) ~= "table" then
    return out
  end
  out.active = type(plan.rules) == "table" and #plan.rules > 0
  local seen = {}
  for _, e in ipairs(type(plan.entries) == "table" and plan.entries or {}) do
    local group = type(e.action) == "table" and DUE_GROUP[e.action.kind]
    if group and (e.maturity == "ready" or e.maturity == "later") and not seen[group .. "|" .. tostring(e.key)] then
      seen[group .. "|" .. tostring(e.key)] = true
      local list = groups[group]
      list[#list + 1] = {
        key = e.key,
        name = e.name,
        rule = e.ruleName,
        from = e.fromRank,
        to = e.toRank,
        later = e.maturity == "later",
      }
      out.total = out.total + 1
    end
  end
  for _, g in ipairs(RM.DUE_GROUPS) do
    sortByName(groups[g])
  end
  return out
end

-- Traffic light --------------------------------------------------------------------------------------------

-- One row per rank of the roster: members, members away, inactive ones (offline for `days` or more, an
-- absent one is not counted), their share and the colour: "green", "yellow", "red", or "none" without a
-- member to judge. ranks = { { index, name } }.
function RM.Traffic(rows, ranks, days, today)
  local byRank, out = {}, {}
  for _, r in ipairs(rows) do
    if type(r.rank) == "number" then
      local list = byRank[r.rank] or { total = 0, away = 0, inactive = 0 }
      byRank[r.rank] = list
      list.total = list.total + 1
      if RM.IsAway(r.away, today) then
        list.away = list.away + 1
      else
        local offline = IL.DaysOffline({ online = r.online, ago = r.ago })
        if offline and offline >= days then
          list.inactive = list.inactive + 1
        end
      end
    end
  end
  for _, rank in ipairs(type(ranks) == "table" and ranks or {}) do
    local c = byRank[rank.index] or { total = 0, away = 0, inactive = 0 }
    local judged = c.total - c.away
    local share = judged > 0 and c.inactive / judged or nil
    local level = "none"
    if share then
      level = share >= RM.RED_FROM and "red" or share >= RM.YELLOW_FROM and "yellow" or "green"
    end
    out[#out + 1] = {
      rank = rank.index,
      name = rank.name,
      total = c.total,
      away = c.away,
      inactive = c.inactive,
      share = share,
      percent = share and math.floor(share * 100 + 0.5) or nil,
      level = level,
    }
  end
  return out
end

-- Week ---------------------------------------------------------------------------------------------------

-- First day of the counted week: "rolling" is the last 7 days, "mon" and "sun" the latest Monday or Sunday
-- (today included). Day 0 (1970-01-01) was a Thursday.
function RM.WeekStart(today, mode)
  if mode == "mon" then
    return today - (today + 3) % 7
  elseif mode == "sun" then
    return today - (today + 4) % 7
  end
  return today - 6
end

-- Joins, leaves (left or removed) and rank changes in the week, from the events of the record.
function RM.WeekStats(events, today, mode)
  local from = RM.WeekStart(today, mode)
  local out = { from = from, to = today, joins = 0, leaves = 0, ranks = 0 }
  for _, e in ipairs(type(events) == "table" and events or {}) do
    local day = type(e) == "table" and whole(e.day)
    if day and day >= from and day <= today then
      if e.kind == "join" then
        out.joins = out.joins + 1
      elseif e.kind == "leave" or e.kind == "remove" then
        out.leaves = out.leaves + 1
      elseif e.kind == "promote" or e.kind == "demote" then
        out.ranks = out.ranks + 1
      end
    end
  end
  return out
end

-- Everything -----------------------------------------------------------------------------------------------

-- input: { today, lead, weekStart, inactiveDays, roster, store, ranks, events, plan }. nil without a day.
function RM.Build(input)
  if type(input) ~= "table" or not whole(input.today) then
    return nil
  end
  local today = input.today
  local lead = math.max(RM.LEAD.min, math.min(RM.LEAD.max, whole(input.lead) or RM.LEAD.default))
  local rows = RM.Rows(input.roster, input.store)
  local anniversaries = RM.Anniversaries(rows, today, lead)
  local birthdays = RM.Birthdays(rows, today, lead)
  return {
    today = today,
    lead = lead,
    members = #rows,
    due = RM.Due(input.plan),
    anniversaries = anniversaries.list,
    unknownJoins = anniversaries.unknown,
    birthdays = birthdays.list,
    birthdayCount = birthdays.count,
    returners = RM.Returners(rows, today),
    away = RM.AwayList(rows, today),
    traffic = RM.Traffic(rows, input.ranks, IL.ClampDays(input.inactiveDays), today),
    week = RM.WeekStats(input.events, today, input.weekStart),
  }
end

-- Chat line ------------------------------------------------------------------------------------------------

local function plain(name)
  return (tostring(name):gsub("[%c|]", ""))
end

-- Names, at most RM.MAX_CHAT_NAMES, then "+n". extra counts people that are not named.
local function nameList(names, extra)
  local shown = {}
  for i = 1, math.min(#names, RM.MAX_CHAT_NAMES) do
    shown[i] = plain(names[i])
  end
  extra = extra + math.max(0, #names - RM.MAX_CHAT_NAMES)
  local text = table.concat(shown, ", ")
  if extra > 0 then
    text = text .. (text ~= "" and ", +" or "") .. extra
  end
  return text
end

-- One short line for the chat, or nil when there is nothing to say. Names appear only for birthdays and
-- for anniversaries of a join date the player typed; everything else is a number. L: locale table.
function RM.ChatLine(model, L)
  if type(model) ~= "table" then
    return nil
  end
  local parts = {}
  local due = model.due and model.due.total or 0
  if due > 0 then
    parts[#parts + 1] = string.format(L["gm.rem.chat.due"], due)
  end
  if #model.birthdays > 0 then
    local names = {}
    for _, b in ipairs(model.birthdays) do
      names[#names + 1] = b.name
    end
    parts[#parts + 1] = string.format(L["gm.rem.chat.birthdays"], nameList(names, 0))
  end
  if #model.anniversaries > 0 then
    local names, extra = {}, 0
    for _, a in ipairs(model.anniversaries) do
      if a.manual then
        names[#names + 1] = a.name
      else
        extra = extra + 1
      end
    end
    parts[#parts + 1] = string.format(L["gm.rem.chat.anniversaries"], nameList(names, extra))
  end
  if #model.returners > 0 then
    parts[#parts + 1] = string.format(L["gm.rem.chat.returners"], #model.returners)
  end
  if #parts == 0 then
    return nil
  end
  return PN.Cut(string.format(L["gm.rem.chat.line"], table.concat(parts, "; ")), RM.MAX_CHAT)
end
