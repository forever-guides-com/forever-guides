-- The log views (ActionLog.lua), no game calls: filters, search, pages and the text of an event. Two
-- logs share the tab: the events (guild.events, what happened in the guild) and the actions (guild.actions,
-- what this add-on did). Both come out newest first.
local _, gm = ...
if not gm.ext then
  return
end
local PN, U = gm.FG.PlayerName, gm.FG.U
local AL, HL, DL = gm.ActionsLogic, gm.HistoryLogic, gm.DatesLogic

local LG = {}
gm.LogLogic = LG

LG.PAGE_SIZE = 12
-- Periods of the filter in days, 0 is no limit.
LG.PERIODS = { 0, 7, 30, 90 }
LG.RESULTS = { "sent", "verified", "unverified", "mismatch", "undone" }
LG.ACTION_KINDS = { "promote", "demote", "remove", "editNote", "editOfficerNote" }
LG.EVENT_KINDS = HL.KINDS

-- A fresh filter: everything shown.
function LG.NewFilter()
  return { search = "", kind = "all", period = 0, member = "", rule = "", result = "all" }
end

local function needleOf(v)
  return PN.Lower(U.trim(type(v) == "string" and v or ""))
end

local function has(field, needle)
  return PN.Lower(type(field) == "string" and field or ""):find(needle, 1, true) ~= nil
end

-- unit: how many of the stamp's units make a day (1 for day numbers, 86400 for seconds).
local function inPeriod(f, stamp, now, unit)
  return f.period == 0 or (type(stamp) == "number" and type(now) == "number" and stamp >= now - f.period * unit)
end

-- Events that pass the filter, newest first. ctx: today (day number), label(kind) text of a kind.
function LG.Events(list, f, ctx)
  local search, member = needleOf(f.search), needleOf(f.member)
  local out = {}
  for i = #list, 1, -1 do
    local e = list[i]
    local ok = (f.kind == "all" or e.kind == f.kind)
      and inPeriod(f, e.day, ctx.today, 1)
      and (member == "" or has(e.name, member) or has(e.key, member))
    if ok and search ~= "" then
      ok = has(e.name, search)
        or has(e.from, search)
        or has(e.to, search)
        or has(e.by, search)
        or has(ctx.label and ctx.label(e.kind), search)
    end
    if ok then
      out[#out + 1] = e
    end
  end
  return out
end

-- Actions that pass the filter, newest first. ctx: now (time stamp), label(action).
function LG.Actions(list, f, ctx)
  local rule, member = needleOf(f.rule), needleOf(f.member)
  local out = {}
  for _, e in ipairs(AL.Filter(list, f.search, ctx.label)) do
    local ok = (f.kind == "all" or e.action == f.kind)
      and inPeriod(f, e.t, ctx.now, 86400)
      and (member == "" or has(e.name, member))
      and (rule == "" or has(e.rule, rule))
    if ok and f.result ~= "all" then
      ok = f.result == "undone" and e.undone == true or e.result == f.result
    end
    if ok then
      out[#out + 1] = e
    end
  end
  return out
end

-- One page of a list: the slice, the page number (kept inside the range) and the number of pages.
function LG.Page(list, page)
  local pages = math.max(1, math.ceil(#list / LG.PAGE_SIZE))
  page = math.min(math.max(math.floor(tonumber(page) or 1), 1), pages)
  local out = {}
  for i = (page - 1) * LG.PAGE_SIZE + 1, math.min(#list, page * LG.PAGE_SIZE) do
    out[#out + 1] = list[i]
  end
  return out, page, pages
end

-- True when a filter differs from the fresh one (the empty list then says "nothing matches").
function LG.Active(f)
  local fresh = LG.NewFilter()
  for k, v in pairs(fresh) do
    if f[k] ~= v then
      return true
    end
  end
  return false
end

-- True when the logged rank change may be taken back now: same rules as the undo itself (window,
-- result, member still in the rank the change set). member: roster row or nil.
function LG.CanUndo(e, member, now, days)
  return gm.RunLogic.Undo(e, member, now, days) ~= nil
end

-- The detail line of an event from the locale table L: what changed, who did it, where it is from.
function LG.EventText(e, L)
  local parts = { L["gm.ev." .. e.kind] }
  local function add(text)
    if text and text ~= "" then
      parts[#parts + 1] = text
    end
  end
  if e.kind == "promote" or e.kind == "demote" then
    add((e.from or "?") .. " > " .. (e.to or "?"))
  elseif e.kind == "rename" then
    add((e.from or "?") .. " > " .. e.name)
  elseif e.kind == "note" then
    add(e.to and L["gm.ev.note." .. e.to] or nil)
  elseif e.kind == "return" and e.days then
    add(string.format(L["gm.ev.returnDays"], e.days))
  end
  if e.by and e.by ~= "" then
    add(string.format(L["gm.ev.by"], e.by))
  end
  add(L["gm.date.src." .. e.src] or e.src)
  if e.fuzz then
    add(string.format(L["gm.ev.fuzz"], e.fuzz))
  end
  return table.concat(parts, ", ")
end

-- The date of an event as the player reads it.
function LG.EventDate(e, format)
  return DL.Format(e.day, format)
end
