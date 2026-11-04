-- Tab "Rules", logic without frames or game calls: the editor's view of conditions and actions, plain
-- sentences for conditions and reasons, the input of PlanLogic.Build from the roster and the store, the
-- tick state of the preview, edits of the rule list and the rule assistant. Rules live in guild.rules as
-- plain tables; RulesLogic repairs and judges them, nothing here writes to the game.
local _, gm = ...
if not gm.ext then
  return
end
local RL, RT, PL = gm.RulesLogic, gm.RuleTemplates, gm.PlanLogic
if not (RL and RT and PL) then
  return
end

local RUL = {}
gm.RulesUiLogic = RUL

-- What the editor offers per condition kind: the operators and the kind of value. Checked against
-- RulesLogic.CleanCond in the tests, so the two cannot drift apart.
RUL.KINDS = {
  { id = "rank", ops = { "in" }, value = "ranks" },
  { id = "daysInGuild", ops = { "atLeast", "lessThan" }, value = "days" },
  { id = "daysInRank", ops = { "atLeast", "lessThan" }, value = "days" },
  { id = "daysOffline", ops = { "atLeast", "lessThan" }, value = "days" },
  { id = "groupDaysOffline", ops = { "atLeast", "lessThan" }, value = "days" },
  { id = "level", ops = { "atLeast", "atMost", "equals", "isMax" }, value = "level", bare = { isMax = true } },
  { id = "link", ops = { "isMain", "isAlt", "hasAlts" }, bare = { isMain = true, isAlt = true, hasAlts = true } },
  {
    id = "mainRank",
    ops = { "equal", "higher", "lower", "differs" },
    bare = { equal = true, higher = true, lower = true, differs = true },
  },
  { id = "publicNote", ops = { "contains", "notContains", "isEmpty" }, value = "text", bare = { isEmpty = true } },
  { id = "officerNote", ops = { "contains", "notContains" }, value = "text" },
  { id = "ownNote", ops = { "contains", "notContains" }, value = "text" },
  { id = "tag", ops = { "has", "hasNot" }, value = "tag" },
  { id = "dateKnown", ops = { "exact", "bounded" }, value = "field" },
  { id = "online", ops = { "is", "isNot" }, bare = { is = true, isNot = true } },
}
RUL.FIELDS = RL.DATE_FIELDS
RUL.TAGS = { "inactive", "review", "cleanup", "returned", "protect" }

local KIND = {}
for _, k in ipairs(RUL.KINDS) do
  KIND[k.id] = k
end

function RUL.Kind(id)
  return KIND[id]
end

local DEFAULT_VALUE = { days = 30, level = 60, text = "", tag = "inactive", field = "joined" }

-- A new condition of the kind with its first operator and a usable value ({} for a rank list: the player
-- has to choose).
function RUL.NewCond(kind)
  local spec = KIND[kind] or KIND.daysInRank
  local op = spec.ops[1]
  local c = { kind = spec.id, op = op }
  if not (spec.bare and spec.bare[op]) then
    local v = DEFAULT_VALUE[spec.value]
    c.value = v == nil and {} or v
  end
  return c
end

-- The player changes the operator: a bare operator drops the value, any other gets one again.
function RUL.SetOp(c, op)
  local spec = KIND[c.kind]
  if not spec then
    return c
  end
  c.op = op
  if spec.bare and spec.bare[op] then
    c.value = nil
  elseif c.value == nil then
    local v = DEFAULT_VALUE[spec.value]
    c.value = v == nil and {} or v
  end
  return c
end

function RUL.SetKind(c, kind)
  local fresh = RUL.NewCond(kind)
  c.kind, c.op, c.value = fresh.kind, fresh.op, fresh.value
  return c
end

-- Text -------------------------------------------------------------------------------------------------

local function fill(text, params)
  return (
    tostring(text):gsub("{(%w+)}", function(k)
      local v = params[k]
      return v ~= nil and tostring(v) or "?"
    end)
  )
end
RUL.Fill = fill

-- Days as a lower and an upper bound: "40", "40 to 45" or "at least 40".
local function spanText(lo, hi, L)
  if hi == nil then
    return fill(L["gm.rules.span.atLeast"], { n = lo })
  elseif hi == lo then
    return tostring(lo)
  end
  return fill(L["gm.rules.span.range"], { lo = lo, hi = hi })
end

-- Name of a rank; a rank without a known name reads "Rank 4", no rank at all "not chosen".
local function rankText(names, r, L)
  if type(r) ~= "number" then
    return L["gm.rules.rankNone"]
  end
  return names and names[r] or string.format(L["gm.pv.rankN"], r)
end

local function rankList(list, names, L)
  local out = {}
  for i, r in ipairs(type(list) == "table" and list or {}) do
    out[i] = rankText(names, r, L)
  end
  return table.concat(out, ", ")
end

-- The sentence of a condition in plain words: "Days in the rank: at least 30".
function RUL.CondLine(c, names, L)
  local spec = type(c) == "table" and KIND[c.kind]
  if not spec then
    return L["gm.cond.invalid"]
  end
  local text = L["gm.cond." .. c.kind] .. ": " .. L["gm.op." .. c.op]
  local v = c.value
  if v ~= nil then
    if spec.value == "ranks" then
      v = rankList(v, names, L)
    elseif spec.value == "field" then
      v = L["gm.data." .. tostring(v)]
    elseif spec.value == "days" and type(v) == "number" then
      v = string.format(L["gm.rules.unit.days"], v)
    end
    text = text .. " " .. tostring(v)
  end
  return text
end

-- Explanation of one answer of the rule engine with the values put in.
function RUL.Explain(answer, names, L)
  local p = {}
  for k, v in pairs(answer.params or {}) do
    p[k] = v
  end
  if p.days ~= nil then
    p.days = spanText(p.days, p.daysMax, L)
  end
  if p.rank ~= nil then
    p.rank = rankText(names, p.rank, L)
  end
  if p.mainRank ~= nil then
    p.mainRank = rankText(names, p.mainRank, L)
  end
  if p.field ~= nil then
    p.field = L["gm.data." .. tostring(p.field)]
  end
  p.op = L["gm.op." .. tostring(answer.op)]
  local text = L[answer.key]
  return fill(text, p)
end

-- Names of the data fields an entry is missing, in plain words.
function RUL.MissingText(list, L)
  local out = {}
  for i, field in ipairs(list or {}) do
    out[i] = L["gm.data." .. tostring(field)]
  end
  return table.concat(out, ", ")
end

-- Why an entry is not ready (or the short note of a ready one): the sentence of gm.why.<code>.
function RUL.ReasonLine(e, L, dateText)
  if not e.reason then
    return ""
  end
  local p = {}
  for k, v in pairs(e.reasonParams or {}) do
    p[k] = v
  end
  if p.untilDay ~= nil and dateText then
    p.untilDay = dateText(p.untilDay)
  end
  p.missing = RUL.MissingText(e.missing, L)
  return fill(L["gm.why." .. e.reason], p)
end

-- One line for the action of an entry: "Promote: Member > Officer".
function RUL.ActionLine(e, names, L)
  local a = e.action or {}
  local kind = a.kind
  local rank = ""
  if e.toRank ~= nil and e.fromRank ~= nil then
    rank = ": " .. string.format(L["gm.pv.rank"], rankText(names, e.fromRank, L), rankText(names, e.toRank, L))
  end
  if kind == "promote" or kind == "demote" or kind == "setRank" or kind == "remove" then
    return L["gm.rules.act." .. kind] .. rank
  elseif kind == "setNote" then
    return fill(L["gm.rules.act.setNote"], { note = a.note or "" })
  elseif kind == "mark" then
    return fill(L["gm.rules.act.mark"], { tag = L["gm.tag." .. tostring(a.tag)] or tostring(a.tag) })
  end
  return L["gm.rules.act.none"]
end

-- One line summarising a rule for the list.
function RUL.RuleLine(rule, names, L)
  local parts = { rankList(rule.ranks, names, L) }
  parts[1] = fill(L["gm.rules.scope"], { ranks = parts[1] ~= "" and parts[1] or L["gm.rules.noRanks"] })
  local conds = {}
  for i, c in ipairs(rule.all or {}) do
    conds[i] = RUL.CondLine(c, names, L)
  end
  parts[2] = table.concat(conds, "; ")
  local a = rule.action or {}
  local act = L["gm.rules.act." .. tostring(a.kind)] or tostring(a.kind)
  if a.kind == "setRank" then
    -- A missing target is named in the red list below the line, not here.
    if a.rankFrom == "main" then
      act = act .. " " .. L["gm.rules.mainRank"]
    elseif a.rank ~= nil then
      act = act .. " " .. rankText(names, a.rank, L)
    end
  elseif a.kind == "mark" then
    act = fill(L["gm.rules.act.mark"], { tag = L["gm.tag." .. tostring(a.tag)] or tostring(a.tag) })
  end
  parts[3] = act
  return table.concat(parts, " | ")
end

-- Gaps and readiness -------------------------------------------------------------------------------------

-- The words for a code of RulesLogic: an issue of a repaired rule or the reason a rule cannot be repaired.
local function gapText(code, L)
  for _, prefix in ipairs({ "gm.rules.miss.", "gm.rules.err." }) do
    local key = prefix .. tostring(code)
    if L[key] ~= key then
      return L[key]
    end
  end
  return tostring(code)
end

-- What a rule (raw or a draft of the editor) still needs before it can be switched on: a list of short
-- texts such as "Target rank: not chosen"; empty when the rule is complete.
function RUL.Gaps(raw, ranks, L)
  local rule, issues = RL.CleanRule(raw, ranks)
  local out = {}
  for i, code in ipairs(rule and issues or { issues }) do
    out[i] = gapText(code, L)
  end
  return out
end

-- The list "Still missing:" with one dash per gap, "" for no gap.
function RUL.GapBlock(gaps, L)
  if #gaps == 0 then
    return ""
  end
  return L["gm.rules.miss.title"] .. "\n- " .. table.concat(gaps, "\n- ")
end

-- "Ann, Bo, Cy and 4 more": at most `max` names.
function RUL.NameList(names, max, L)
  local out = {}
  for i = 1, math.min(#names, max) do
    out[i] = names[i]
  end
  local text = table.concat(out, ", ")
  if #names > max then
    text = text .. " " .. string.format(L["gm.rules.cf.more"], #names - max)
  end
  return text
end

-- The texts of what still stops a run (the checklist of the step "Run"); an empty list means ready.
-- o: rules (rules in the plan), open (gaps of the chosen rule), steps and marks (ticked counts), noRight,
-- noWay, combat, stale (booleans).
function RUL.Readiness(o, L)
  local out = {}
  local function add(key, ...)
    out[#out + 1] = string.format(L[key], ...)
  end
  if #(o.open or {}) > 0 then
    add("gm.rules.chk.ruleOpen", table.concat(o.open, ", "))
  elseif (o.rules or 0) == 0 then
    add("gm.rules.chk.rule")
  elseif (o.steps or 0) + (o.marks or 0) == 0 then
    add("gm.rules.chk.members")
  end
  if o.stale then
    add("gm.rules.chk.roster")
  end
  if (o.steps or 0) > 0 then
    if o.noRight then
      add("gm.rules.chk.rights")
    end
    if o.noWay then
      add("gm.rules.chk.way")
    end
    if o.combat then
      add("gm.rules.chk.combat")
    end
  end
  return out
end

-- What is known about the join dates: { total, known, exact, atLeast, unknown = sorted names }. members are
-- the rows of RUL.Input, ranks the rank indexes to look at (nil: every rank but the master).
function RUL.DataSituation(members, today, ranks)
  local scope
  if ranks then
    scope = {}
    for _, r in ipairs(ranks) do
      scope[r] = true
    end
  end
  local out = { total = 0, known = 0, exact = 0, atLeast = 0, unknown = {} }
  for _, m in ipairs(members or {}) do
    if m.rank ~= 0 and (not scope or scope[m.rank]) then
      out.total = out.total + 1
      local lo, hi = RL.Span(m.joined, today)
      if lo then
        local kind = hi == lo and "exact" or "atLeast"
        out.known, out[kind] = out.known + 1, out[kind] + 1
      else
        out.unknown[#out.unknown + 1] = m.name
      end
    end
  end
  table.sort(out.unknown)
  return out
end

local NAMES_SHOWN = 10
local CONFIRM_KINDS = { "promote", "setRank", "demote", "remove", "setNote" }

-- The lines of the confirmation before a run: what happens to whom, mode, way, pause, stop, undo.
-- o: live (the guild changes), way (text), pause (seconds), undoDays.
function RUL.ConfirmLines(steps, marks, o, L)
  local lines = { L["gm.rules.cf.intro"] }
  local names = {}
  for _, e in ipairs(steps) do
    local kind = e.action.kind
    names[kind] = names[kind] or {}
    table.insert(names[kind], e.name)
  end
  for _, kind in ipairs(CONFIRM_KINDS) do
    local list = names[kind]
    if list then
      lines[#lines + 1] = "- " .. string.format(L["gm.rules.cf." .. kind], #list, RUL.NameList(list, NAMES_SHOWN, L))
    end
  end
  if #marks > 0 then
    local list = {}
    for i, e in ipairs(marks) do
      list[i] = e.name
    end
    lines[#lines + 1] = "- " .. string.format(L["gm.rules.cf.mark"], #list, RUL.NameList(list, NAMES_SHOWN, L))
    lines[#lines + 1] = "- " .. L["gm.rules.cf.local"]
  end
  if #steps > 0 then
    lines[#lines + 1] = "- " .. L[o.live and "gm.rules.cf.live" or "gm.rules.cf.dry"]
    lines[#lines + 1] = "- " .. o.way
    lines[#lines + 1] = "- " .. string.format(L["gm.rules.cf.pause"], o.pause or 0)
    lines[#lines + 1] = "- " .. L["gm.rules.cf.stop"]
    if names.promote or names.demote or names.setRank then
      lines[#lines + 1] = "- " .. string.format(L["gm.rules.cf.undo"], o.undoDays or 0)
    end
    if names.remove then
      lines[#lines + 1] = "- " .. L["gm.rules.cf.removeAsk"]
    end
  end
  return lines
end

-- Plan input -------------------------------------------------------------------------------------------

local function copyList(list)
  local out = {}
  for i, v in ipairs(type(list) == "table" and list or {}) do
    out[i] = v
  end
  return out
end

-- The context of PlanLogic.Build from the roster snapshot, the guild record and what the game says now.
-- o: { today, now, offset, meKey, rights, caps, plan (SettingsLogic.PlanContext), age (seconds the roster
-- is old, nil when unknown), DL (DatesLogic) }
function RUL.Input(snap, guild, o)
  o = o or {}
  local DL = o.DL or gm.DatesLogic
  local store = guild.members or {}
  local rights = o.rights or {}
  local members, me = {}, nil
  for _, m in ipairs(snap.members or {}) do
    local e = type(store[m.key]) == "table" and store[m.key] or {}
    members[#members + 1] = {
      key = m.key,
      name = m.name,
      guid = m.guid,
      rank = m.rank,
      level = m.level,
      online = m.online == true,
      publicNote = m.note,
      officerNote = rights.officerNote == true and m.officerNote or nil,
      ownNote = e.note,
      mainKey = e.mainKey ~= "" and e.mainKey or nil,
      tags = e.tags,
      away = e.away,
      returnedDay = e.returnedDay,
      joined = e.joined,
      rankSince = e.rankSince,
      lastOnline = DL.LastOnline(m, o.today, o.now, o.offset),
    }
    if m.key == o.meKey then
      me = { key = m.key, rank = m.rank }
    end
  end
  local plan = o.plan or {}
  local protect = {}
  for k, v in pairs(plan.protect or {}) do
    protect[k] = v
  end
  local own = type(guild.protect) == "table" and guild.protect or {}
  protect.ranks, protect.keys = copyList(own.ranks), copyList(own.keys)
  return {
    today = o.today,
    me = me,
    ranks = snap.ranks,
    rights = rights,
    caps = o.caps or {},
    rosterAge = o.age,
    maxTotal = plan.maxTotal,
    maxLevel = plan.maxLevel,
    protect = protect,
    skip = guild.skip,
    members = members,
  }
end

-- Ticks ------------------------------------------------------------------------------------------------

function RUL.EntryId(e)
  return tostring(e.rule) .. "|" .. tostring(e.key)
end

-- Entries a tick can be set on: ready ones that do something.
function RUL.Pickable(e)
  return e.maturity == "ready" and e.action.kind ~= "none"
end

-- The tick of an entry: what the player chose, else the plan's default (a removal is never on).
function RUL.IsPicked(state, e)
  if not RUL.Pickable(e) then
    return false
  end
  local v = state.pick[RUL.EntryId(e)]
  if v == nil then
    return e.checked == true and e.action.kind ~= "remove"
  end
  return v
end

function RUL.SetPicked(state, e, on)
  if RUL.Pickable(e) then
    state.pick[RUL.EntryId(e)] = on == true
  end
end

-- "All valid": every ready entry except removals, which stay a conscious click each.
function RUL.PickAll(state, plan)
  for _, e in ipairs(plan.entries) do
    if RUL.Pickable(e) then
      state.pick[RUL.EntryId(e)] = e.action.kind ~= "remove"
    end
  end
end

function RUL.PickNone(state, plan)
  for _, e in ipairs(plan.entries) do
    if RUL.Pickable(e) then
      state.pick[RUL.EntryId(e)] = false
    end
  end
end

-- Marks of a preview row: the protection list (guild.protect.keys) and "skip today" (guild.skip, a day
-- number the member is left alone until). Only the store changes. Rank 0 never gets a mark.
local MAX_SKIP = 200

-- True, or false and a reason: "noTarget" (no key) or "leader" (rank 0).
function RUL.CanMark(e)
  if type(e) ~= "table" or type(e.key) ~= "string" or e.key == "" then
    return false, "noTarget"
  end
  if e.fromRank == 0 then
    return false, "leader"
  end
  return true
end

-- Puts the member of the entry on the protection list. True (also when already there), or false and a
-- reason ("noTarget", "leader", "full").
function RUL.Protect(guild, e)
  local ok, why = RUL.CanMark(e)
  if not ok then
    return false, why
  end
  guild.protect = type(guild.protect) == "table" and guild.protect or {}
  local keys = copyList(guild.protect.keys)
  guild.protect.keys = keys
  for _, k in ipairs(keys) do
    if k == e.key then
      return true
    end
  end
  if #keys >= RL.MAX_LIST then
    return false, "full"
  end
  keys[#keys + 1] = e.key
  return true
end

-- Takes the key off the protection list; true when it was there.
function RUL.Unprotect(guild, key)
  local keys = type(guild.protect) == "table" and guild.protect.keys
  local found = false
  for i = #(keys or {}), 1, -1 do
    if keys[i] == key then
      table.remove(keys, i)
      found = true
    end
  end
  return found
end

-- Leaves the member alone for this day only. Answers true and the day it replaced (nil when there was
-- none), or false and a reason ("noTarget", "leader", "noClock", "full"). Days gone by drop out.
function RUL.SkipToday(guild, e, today)
  local ok, why = RUL.CanMark(e)
  if not ok then
    return false, why
  end
  if type(today) ~= "number" or today ~= today then
    return false, "noClock"
  end
  guild.skip = type(guild.skip) == "table" and guild.skip or {}
  local count = 0
  for key, day in pairs(guild.skip) do
    if type(day) ~= "number" or day < today then
      guild.skip[key] = nil
    else
      count = count + 1
    end
  end
  local before = guild.skip[e.key]
  if before == nil and count >= MAX_SKIP then
    return false, "full"
  end
  guild.skip[e.key] = math.max(today, before or today)
  return true, before
end

-- Puts the day back that SkipToday replaced (nil removes the mark).
function RUL.Unskip(guild, key, before)
  if type(guild.skip) == "table" then
    guild.skip[key] = before
  end
end

local GUILD_STEP = { promote = true, demote = true, setRank = true, remove = true, setNote = true }

-- The ticked entries: steps for the run (they change the guild) and marks (only the store).
function RUL.Chosen(state, plan)
  local steps, marks = {}, {}
  for _, e in ipairs(plan.entries) do
    if RUL.IsPicked(state, e) then
      if GUILD_STEP[e.action.kind] then
        steps[#steps + 1] = e
      elseif e.action.kind == "mark" then
        marks[#marks + 1] = e
      end
    end
  end
  return steps, marks
end

-- Count of ticked entries per action kind.
function RUL.Counts(entries)
  local out = {}
  for _, kind in ipairs(RL.ACTIONS) do
    out[kind] = 0
  end
  for _, e in ipairs(entries) do
    out[e.action.kind] = out[e.action.kind] + 1
  end
  return out
end

-- Entries of the plan that a filter shows: "all" or a maturity.
function RUL.Filter(plan, which)
  local out = {}
  for _, e in ipairs(plan.entries) do
    if which == "all" or e.maturity == which then
      out[#out + 1] = e
    end
  end
  return out
end

-- Sets the tag of every ticked mark entry in the store; returns how many were set.
function RUL.ApplyMarks(guild, marks)
  local n = 0
  for _, e in ipairs(marks) do
    local tag = e.action.tag
    if tag then
      local entry = gm.MembersLogic.Touch(guild.members, { key = e.key, name = e.name })
      entry.tags = type(entry.tags) == "table" and entry.tags or {}
      if not entry.tags[tag] then
        entry.tags[tag] = true
        n = n + 1
      end
    end
  end
  return n
end

-- The rule list ----------------------------------------------------------------------------------------

-- Drops what is no table, keeps everything else (a damaged rule is shown and left to the player).
function RUL.Repair(guild)
  if type(guild.rules) ~= "table" then
    guild.rules = {}
  end
  local out = {}
  for _, r in ipairs(guild.rules) do
    if type(r) == "table" and #out < RL.MAX_RULES then
      out[#out + 1] = r
    end
  end
  for i = 1, math.max(#guild.rules, #out) do
    guild.rules[i] = out[i]
  end
  return guild.rules
end

local function newId(list)
  local used = {}
  for _, r in ipairs(list) do
    if type(r.id) == "string" then
      used[r.id] = true
    end
  end
  local n = #list + 1
  while used["r" .. n] do
    n = n + 1
  end
  return "r" .. n
end

-- Stores a rule at the index (nil: at the end). Answers true, or false and a reason of RulesLogic or "tooMany".
function RUL.Save(list, index, raw, ranks)
  local rule, issues = RL.CleanRule(raw, ranks)
  if not rule then
    return false, issues
  end
  if index == nil then
    if #list >= RL.MAX_RULES then
      return false, "tooMany"
    end
    index = #list + 1
  end
  local old = list[index]
  rule.id = rule.id ~= "" and rule.id or (type(old) == "table" and old.id) or newId(list)
  rule.enabled = rule.enabled and not rule.review
  list[index] = rule
  return true, issues
end

-- Switches a rule on or off. A rule with an open issue stays off: false and the first issue.
function RUL.SetEnabled(list, index, on, ranks)
  local raw = list[index]
  if type(raw) ~= "table" then
    return false, "notARule"
  end
  if not on then
    raw.enabled = false
    return true
  end
  local copy = {}
  for k, v in pairs(raw) do
    copy[k] = v
  end
  copy.enabled = true
  local rule, issues = RL.CleanRule(copy, ranks)
  if not rule then
    return false, issues
  end
  if not rule.enabled then
    return false, issues[1] or "noRanks"
  end
  rule.id = raw.id
  list[index] = rule
  return true
end

function RUL.Move(list, index, delta)
  local to = index + delta
  if list[index] == nil or to < 1 or to > #list then
    return false
  end
  list[index], list[to] = list[to], list[index]
  return true
end

function RUL.Delete(list, index)
  if list[index] == nil then
    return false
  end
  table.remove(list, index)
  return true
end

local function deepCopy(v)
  if type(v) ~= "table" then
    return v
  end
  local out = {}
  for k, x in pairs(v) do
    out[k] = deepCopy(x)
  end
  return out
end
RUL.DeepCopy = deepCopy

-- A copy behind the rule, always off, with " 2" behind the name.
function RUL.Duplicate(list, index, ranks)
  local raw = list[index]
  if type(raw) ~= "table" then
    return false, "notARule"
  end
  local copy = deepCopy(raw)
  copy.id, copy.enabled = "", false
  copy.name = RL.CleanText((type(raw.name) == "string" and raw.name or "") .. " 2", RL.MAX_NAME)
  local ok, why = RUL.Save(list, nil, copy, ranks)
  if ok then
    -- Right behind the original.
    table.insert(list, index + 1, table.remove(list))
  end
  return ok, why
end

-- Draft rules of a template stored as off rules; the names come from the locale. Answers the count.
function RUL.AddFromTemplate(list, id, given, opts, ranks, L)
  local drafts = RT.Instantiate(id, given, opts)
  if not drafts then
    return false, "unknownTemplate"
  end
  if #list + #drafts > RL.MAX_RULES then
    return false, "tooMany"
  end
  for _, d in ipairs(drafts) do
    d.name = RL.CleanText(L["gm.tpl." .. tostring(d.template or id) .. ".title"], RL.MAX_NAME)
    local ok, why = RUL.Save(list, nil, d, ranks)
    if not ok then
      return false, why
    end
  end
  return #drafts
end

-- The choices of the rule picker of the preview: every active rule, then each rule by name (a rule that is
-- off says so). A rule without an id cannot be picked.
function RUL.RuleChoices(list, ranks, L)
  local out = { { value = "active", key = "gm.rules.pick.active" } }
  for _, raw in ipairs(list) do
    local rule = type(raw) == "table" and type(raw.id) == "string" and raw.id ~= "" and RL.CleanRule(raw, ranks)
    if rule then
      local name = rule.name ~= "" and rule.name or L["gm.rules.unnamed"]
      out[#out + 1] = {
        value = raw.id,
        text = rule.enabled and name or string.format(L["gm.rules.pick.off"], name),
      }
    end
  end
  return out
end

-- Assistant ----------------------------------------------------------------------------------------------

-- Goal -> template; all four take the parameter "days". rankParam is the template's name for the ranks.
RUL.GOALS = {
  { id = "promote", template = "promoteByTime", rank = "rank", days = 30 },
  { id = "demote", template = "demoteByInactivity", rank = "rank", days = 45 },
  { id = "mark", template = "markInactive", rank = "ranks", days = 14 },
  { id = "remove", template = "removeInactive", rank = "ranks", days = 90 },
}

function RUL.Goal(id)
  for _, g in ipairs(RUL.GOALS) do
    if g.id == id then
      return g
    end
  end
end

-- Stores the rules of the three answers (who = rank indexes, what = goal id, when = days). A template
-- with one rank gets one rule per chosen rank. Answers the count, or false and a reason.
function RUL.AddFromAnswers(list, answers, opts, ranks, L)
  local goal = RUL.Goal(answers.what)
  local who = {}
  for _, r in ipairs(type(answers.who) == "table" and answers.who or {}) do
    if RL.RankIndex(r) and r >= 1 then
      who[#who + 1] = r
    end
  end
  table.sort(who)
  if not goal then
    return false, "noGoal"
  end
  if #who == 0 then
    return false, "noRanks"
  end
  local given = { days = answers.days }
  local added = 0
  if goal.rank == "ranks" then
    given.ranks = who
    local n, why = RUL.AddFromTemplate(list, goal.template, given, opts, ranks, L)
    return n or false, why
  end
  for _, r in ipairs(who) do
    given.rank = r
    local n, why = RUL.AddFromTemplate(list, goal.template, given, opts, ranks, L)
    if not n then
      return false, why
    end
    added = added + n
  end
  return added
end
