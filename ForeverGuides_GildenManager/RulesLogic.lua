-- Rule engine, part 1, no game calls: the rule model, its validation and the three-valued
-- evaluation of the conditions. Plan building lives in PlanLogic, the stock rules in RuleTemplates.
--
-- Rule   = { id, name, enabled, template, ranks = { rank index... }, rankNames = { [index] = name },
--            all = { Cond... }, action = Action, protect = { useGlobal, extraRanks, extraKeys },
--            maxPerRun, review }
-- Cond   = { kind, op, value }   (all conditions must be yes, OR is several rules)
-- Action = { kind, rank, rankName, rankFrom, note, public, tag }
--
-- Every date is an interval: DateInfo = { minDay, maxDay, src } in day numbers, either end may be
-- nil (open). A condition answers "yes", "no" or "unknown"; unknown never triggers an action. Each
-- answer carries an explanation { key, params, missing, quality }: the text comes later from the
-- locale key, nothing in here is shown to the user.
--
-- Rank indexes are the roster base (guild master = 0). The game call SetGuildRankOrder counts from 1,
-- RankOrderOf is the one place that converts.
local _, gm = ...

local RL = {}
gm.RulesLogic = RL

RL.YES, RL.NO, RL.UNKNOWN = "yes", "no", "unknown"
RL.MATCH = "match"
local YES, NO, UNKNOWN, MATCH = RL.YES, RL.NO, RL.UNKNOWN, RL.MATCH

RL.MAX_RANK = 9
RL.MAX_DAYS = 3650
RL.MAX_LEVEL = 120
RL.MAX_CONDITIONS = 12
RL.MAX_RULES = 50
RL.MAX_LIST = 100
RL.MAX_NAME = 40
-- Same limit the game applies to guild notes.
RL.MAX_NOTE = 31
RL.MAX_OWN_NOTE = 60
RL.MAX_TAG = 20
RL.DEFAULT_PER_RUN = 10
RL.MAX_PER_RUN = 25

-- Order is the order of the editor lists.
RL.CONDITIONS = {
  "rank",
  "daysInGuild",
  "daysInRank",
  "daysOffline",
  "groupDaysOffline",
  "level",
  "link",
  "mainRank",
  "publicNote",
  "officerNote",
  "ownNote",
  "tag",
  "dateKnown",
  "online",
}
RL.ACTIONS = { "promote", "demote", "setRank", "remove", "setNote", "mark", "none" }
RL.DATE_FIELDS = { "joined", "rankSince", "lastOnline" }

-- Helpers --------------------------------------------------------------------------------------------

local function set(list)
  local t = {}
  for _, v in ipairs(list) do
    t[v] = true
  end
  return t
end

local function whole(v)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
    return nil
  end
  return math.floor(v + 0.5)
end

local function clamp(v, lo, hi, default)
  v = whole(v)
  if not v then
    return default
  end
  return math.max(lo, math.min(hi, v))
end

-- One line of at most max characters (UTF-8 safe), "" for anything that is no text.
local function cleanText(s, max)
  if type(s) ~= "string" then
    return ""
  end
  s = s:gsub("%c", " "):gsub("%s+", " ")
  local out, n = {}, 0
  for ch in s:gmatch("[\1-\127\194-\244][\128-\191]*") do
    n = n + 1
    if n > max then
      break
    end
    out[n] = ch
  end
  return (table.concat(out):match("^%s*(.-)%s*$"))
end
RL.CleanText = cleanText

local function rankIndex(v)
  v = type(v) == "number" and v or nil
  return v and v % 1 == 0 and v >= 0 and v <= RL.MAX_RANK and v or nil
end

RL.Whole, RL.Clamp, RL.RankIndex = whole, clamp, rankIndex

-- Roster rank index (0 = master) -> order the rank calls expect (1 = master); nil for no valid rank.
function RL.RankOrderOf(index)
  local r = rankIndex(index)
  return r and r + 1 or nil
end

-- Inverse of RankOrderOf.
function RL.RankIndexOf(order)
  local o = type(order) == "number" and order or nil
  return o and o % 1 == 0 and rankIndex(o - 1) or nil
end

-- Sorted list of the distinct rank indexes in `list` that lie within [lo, MAX_RANK].
local function rankList(list, lo)
  local out, seen = {}, {}
  for _, v in ipairs(type(list) == "table" and list or {}) do
    local r = rankIndex(v)
    if r and r >= lo and not seen[r] and #out < RL.MAX_RANK + 1 then
      seen[r] = true
      out[#out + 1] = r
    end
  end
  table.sort(out)
  return out
end

local function keyList(list)
  local out, seen = {}, {}
  for _, v in ipairs(type(list) == "table" and list or {}) do
    v = cleanText(v, 60)
    if v ~= "" and not seen[v] and #out < RL.MAX_LIST then
      seen[v] = true
      out[#out + 1] = v
    end
  end
  table.sort(out)
  return out
end

-- Date intervals -------------------------------------------------------------------------------------

-- Days since the date: lo (at least), hi (at most, nil = open), src and whether lo is a real lower
-- bound (maxDay known). nil when the date is unknown or contradicts itself.
local function span(info, today)
  if type(info) ~= "table" or not today then
    return nil
  end
  local minDay, maxDay = whole(info.minDay), whole(info.maxDay)
  if (not minDay and not maxDay) or (minDay and maxDay and maxDay < minDay) then
    return nil
  end
  local lo = maxDay and math.max(0, today - maxDay) or 0
  local hi = minDay and math.max(0, today - minDay) or nil
  return lo, hi, type(info.src) == "string" and info.src or nil, maxDay ~= nil
end
RL.Span = span

-- Days since the member was last online. Online now is exactly 0 days.
local function offline(m, today)
  if m.online == true then
    return 0, 0, "roster", true
  end
  return span(m.lastOnline, today)
end
RL.Offline = offline

local function quality(lo, hi)
  return hi ~= nil and lo == hi and "exact" or "earliest"
end

-- Environment ----------------------------------------------------------------------------------------

-- ctx: today (day number), members (rows, see PlanLogic), maxLevel, officerNote (true when the
-- officer notes may be read). Builds the lookups the conditions need, one time per plan.
function RL.Env(ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local env = {
    today = whole(ctx.today),
    maxLevel = whole(ctx.maxLevel),
    officerNote = ctx.officerNote == true,
    byKey = {},
    list = {},
    groups = {},
  }
  for _, m in ipairs(type(ctx.members) == "table" and ctx.members or {}) do
    if type(m) == "table" and type(m.key) == "string" and m.key ~= "" and not env.byKey[m.key] then
      env.byKey[m.key] = m
      env.list[#env.list + 1] = m
    end
  end
  table.sort(env.list, function(a, b)
    return a.key < b.key
  end)
  for _, m in ipairs(env.list) do
    local root = RL.GroupRoot(m)
    env.groups[root] = env.groups[root] or {}
    table.insert(env.groups[root], m)
  end
  return env
end

local function isAlt(m)
  return type(m.mainKey) == "string" and m.mainKey ~= "" and m.mainKey ~= m.key
end

-- Key of the main of the group the member belongs to (its own key for a main or a single).
function RL.GroupRoot(m)
  return isAlt(m) and m.mainKey or m.key
end

-- The main and all alts, the member included.
function RL.GroupOf(env, m)
  return env.groups[RL.GroupRoot(m)] or { m }
end

-- The row of the main of an alt, nil for a main and for a main that is not in the roster.
function RL.MainOf(env, m)
  return isAlt(m) and env.byKey[m.mainKey] or nil
end

-- Condition kinds ------------------------------------------------------------------------------------

local KINDS = {
  rank = { ops = set({ "in" }), value = "ranks" },
  daysInGuild = { ops = set({ "atLeast", "lessThan" }), value = "days" },
  daysInRank = { ops = set({ "atLeast", "lessThan" }), value = "days" },
  daysOffline = { ops = set({ "atLeast", "lessThan" }), value = "days" },
  groupDaysOffline = { ops = set({ "atLeast", "lessThan" }), value = "days" },
  level = { ops = set({ "atLeast", "atMost", "equals", "isMax" }), value = "level", bare = set({ "isMax" }) },
  link = { ops = set({ "isMain", "isAlt", "hasAlts" }), bare = set({ "isMain", "isAlt", "hasAlts" }) },
  mainRank = {
    ops = set({ "equal", "higher", "lower", "differs" }),
    bare = set({ "equal", "higher", "lower", "differs" }),
  },
  publicNote = {
    ops = set({ "contains", "notContains", "isEmpty" }),
    value = "text",
    max = RL.MAX_NOTE,
    bare = set({ "isEmpty" }),
  },
  officerNote = { ops = set({ "contains", "notContains" }), value = "text", max = RL.MAX_NOTE },
  ownNote = { ops = set({ "contains", "notContains" }), value = "text", max = RL.MAX_OWN_NOTE },
  tag = { ops = set({ "has", "hasNot" }), value = "tag" },
  dateKnown = { ops = set({ "exact", "bounded" }), value = "field" },
  online = { ops = set({ "is", "isNot" }), bare = set({ "is", "isNot" }) },
}

local FIELDS = set(RL.DATE_FIELDS)

-- value kind -> cleaned value, nil when it cannot be repaired.
local VALUE = {
  ranks = function(v)
    local list = rankList(v, 0)
    return #list > 0 and list or nil
  end,
  days = function(v)
    return clamp(v, 0, RL.MAX_DAYS, nil)
  end,
  level = function(v)
    return clamp(v, 1, RL.MAX_LEVEL, nil)
  end,
  text = function(v, spec)
    local s = cleanText(v, spec.max)
    return s ~= "" and s or nil
  end,
  tag = function(v)
    local s = cleanText(v, RL.MAX_TAG):lower()
    return s ~= "" and s or nil
  end,
  field = function(v)
    return FIELDS[v] and v or nil
  end,
}

-- Returns the repaired condition (limits clamped, bare operators lose their value) or nil and a
-- reason. A condition that cannot be repaired rejects the rule: dropping it would widen the rule.
function RL.CleanCond(c)
  if type(c) ~= "table" then
    return nil, "badCondition"
  end
  local spec = KINDS[c.kind]
  if not spec then
    return nil, "badKind"
  end
  if type(c.op) ~= "string" or not spec.ops[c.op] then
    return nil, "badOp"
  end
  if spec.bare and spec.bare[c.op] then
    return { kind = c.kind, op = c.op }
  end
  local value = VALUE[spec.value](c.value, spec)
  if value == nil then
    return nil, "badValue"
  end
  return { kind = c.kind, op = c.op, value = value }
end

-- Evaluation -----------------------------------------------------------------------------------------

-- Each evaluator answers result, params, missing (data field to supply), quality.
local EVAL = {}

local function daysAnswer(op, need, lo, hi)
  if op == "atLeast" then
    if lo >= need then
      return YES
    elseif hi and hi < need then
      return NO
    end
  else
    if hi and hi < need then
      return YES
    elseif lo >= need then
      return NO
    end
  end
  return UNKNOWN
end

local function daysEval(field, read)
  return function(c, m, env)
    local lo, hi, src = read(m, env)
    if not lo then
      return UNKNOWN, { need = c.value }, field
    end
    local result = daysAnswer(c.op, c.value, lo, hi)
    return result,
      { days = lo, daysMax = hi, need = c.value, src = src },
      result == UNKNOWN and field or nil,
      quality(lo, hi)
  end
end

function EVAL.rank(c, m)
  local r = m.rank
  if type(r) ~= "number" then
    return UNKNOWN, nil, "rank"
  end
  for _, v in ipairs(c.value) do
    if v == r then
      return YES, { rank = r }
    end
  end
  return NO, { rank = r }
end

EVAL.daysInGuild = daysEval("joined", function(m, env)
  return span(m.joined, env.today)
end)
EVAL.daysInRank = daysEval("rankSince", function(m, env)
  return span(m.rankSince, env.today)
end)
EVAL.daysOffline = daysEval("lastOnline", function(m, env)
  return offline(m, env.today)
end)

-- Smallest value of the group: a member without data may be active, so it counts as 0 and an
-- open upper end does not raise the upper bound.
function EVAL.groupDaysOffline(c, m, env)
  local lo, hi, unknown, by
  for _, g in ipairs(RL.GroupOf(env, m)) do
    local glo, ghi = offline(g, env.today)
    if not glo then
      glo, unknown = 0, unknown or g.key
    end
    if not lo or glo < lo then
      lo, by = glo, g.key
    end
    if ghi and (not hi or ghi < hi) then
      hi = ghi
    end
  end
  local result = daysAnswer(c.op, c.value, lo, hi)
  return result,
    { days = lo, daysMax = hi, need = c.value, by = by, unknown = unknown },
    result == UNKNOWN and "lastOnline" or nil,
    quality(lo, hi)
end

function EVAL.level(c, m, env)
  local lv = whole(m.level)
  if not lv then
    return UNKNOWN, nil, "level"
  end
  local need = c.value
  if c.op == "isMax" then
    if not env.maxLevel then
      return UNKNOWN, { level = lv }, "maxLevel"
    end
    need = env.maxLevel
  end
  local ok
  if c.op == "atMost" then
    ok = lv <= need
  elseif c.op == "equals" then
    ok = lv == need
  else
    ok = lv >= need
  end
  return ok and YES or NO, { level = lv, need = need }
end

function EVAL.link(c, m, env)
  local alt = isAlt(m)
  local ok
  if c.op == "isAlt" then
    ok = alt
  elseif c.op == "isMain" then
    ok = not alt
  else
    ok = not alt and #RL.GroupOf(env, m) > 1
  end
  return ok and YES or NO
end

function EVAL.mainRank(c, m, env)
  if not isAlt(m) then
    return NO
  end
  local main = RL.MainOf(env, m)
  local theirs, mine = main and rankIndex(main.rank), rankIndex(m.rank)
  if not theirs or not mine then
    return UNKNOWN, nil, "main"
  end
  local ok
  if c.op == "equal" then
    ok = theirs == mine
  elseif c.op == "higher" then
    ok = theirs < mine
  elseif c.op == "lower" then
    ok = theirs > mine
  else
    ok = theirs ~= mine
  end
  return ok and YES or NO, { mainRank = theirs, rank = mine }
end

-- Case does not matter (ASCII only, the game gives no portable lower casing).
local function noteAnswer(c, text, field)
  if type(text) ~= "string" then
    return UNKNOWN, nil, field
  end
  local ok
  if c.op == "isEmpty" then
    ok = text:match("^%s*$") ~= nil
  else
    local found = text:lower():find(c.value:lower(), 1, true) ~= nil
    ok = (c.op == "contains") == found
  end
  return ok and YES or NO, { text = c.value }
end

function EVAL.publicNote(c, m)
  return noteAnswer(c, m.publicNote, "publicNote")
end

function EVAL.officerNote(c, m, env)
  if not env.officerNote then
    return UNKNOWN, nil, "officerNote"
  end
  return noteAnswer(c, m.officerNote, "officerNote")
end

-- The own note lives in the add-on store, so a missing one is an empty one.
function EVAL.ownNote(c, m)
  return noteAnswer(c, type(m.ownNote) == "string" and m.ownNote or "", "ownNote")
end

function EVAL.tag(c, m)
  local has = type(m.tags) == "table" and m.tags[c.value] ~= nil and m.tags[c.value] ~= false
  return (c.op == "has") == has and YES or NO, { tag = c.value }
end

-- Data quality as a condition: exact = one known day, bounded = a real lower bound on the days.
function EVAL.dateKnown(c, m, env)
  local lo, hi, _, bounded
  if c.value == "lastOnline" then
    lo, hi, _, bounded = offline(m, env.today)
  else
    lo, hi, _, bounded = span(m[c.value], env.today)
  end
  local ok = lo ~= nil and ((c.op == "exact" and hi == lo) or (c.op == "bounded" and bounded))
  return ok and YES or NO, { field = c.value }
end

function EVAL.online(c, m)
  if type(m.online) ~= "boolean" then
    return UNKNOWN, nil, "online"
  end
  return (c.op == "is") == m.online and YES or NO
end

-- Answer of one condition: { kind, op, result, key, params, missing, quality }. key is the locale
-- key "gm.cond.<kind>.<result>". A condition that is not valid answers no.
function RL.EvalCond(c, m, env)
  local fn = type(c) == "table" and EVAL[c.kind]
  if not fn then
    return { kind = tostring(type(c) == "table" and c.kind), result = NO, key = "gm.cond.invalid" }
  end
  local result, params, missing, q = fn(c, m, env)
  return {
    kind = c.kind,
    op = c.op,
    result = result,
    key = "gm.cond." .. c.kind .. "." .. result,
    params = params,
    missing = missing,
    quality = q,
  }
end

-- Every explanation key the evaluation can produce, sorted, for the locale check.
function RL.ExplainKeys()
  local out = { "gm.cond.invalid" }
  for _, kind in ipairs(RL.CONDITIONS) do
    for _, result in ipairs({ YES, NO, UNKNOWN }) do
      out[#out + 1] = "gm.cond." .. kind .. "." .. result
    end
  end
  table.sort(out)
  return out
end

-- Evaluates all conditions of the rule for one member (no short cut, the explanation is complete).
-- Returns "match" (all yes), "no" (one no) or "unknown" (no no, one unknown), the list of answers
-- and the data quality: "exact", "earliest" (a bound only) or nil when no date was involved.
function RL.Evaluate(rule, m, env)
  local answers, any, unknown, q = {}, false, false, nil
  local result = MATCH
  for i, c in ipairs(type(rule) == "table" and type(rule.all) == "table" and rule.all or {}) do
    local a = RL.EvalCond(c, m, env)
    answers[i] = a
    any = true
    if a.result == NO then
      result = NO
    elseif a.result == UNKNOWN then
      unknown = true
    end
    if a.quality == "earliest" or (a.quality == "exact" and q == nil) then
      q = a.quality
    end
  end
  if not any then
    result = NO
  elseif result == MATCH and unknown then
    result = UNKNOWN
  end
  return result, answers, q
end

-- Actions --------------------------------------------------------------------------------------------

local ACTIONS = set(RL.ACTIONS)

-- Returns the repaired action and nil, nil and a reason for an unknown kind. A repair that leaves
-- the action unusable (no valid target rank, no note, no tag) adds a code to `issues`.
local function cleanAction(a, issues)
  if type(a) ~= "table" or not ACTIONS[a.kind] then
    return nil, "badAction"
  end
  local out = { kind = a.kind }
  if a.kind == "setRank" then
    local r = rankIndex(a.rank)
    if a.rankFrom == "main" then
      out.rankFrom = "main"
    elseif r and r >= 1 then
      out.rank = r
      local name = cleanText(a.rankName, RL.MAX_NAME)
      out.rankName = name ~= "" and name or nil
    else
      issues[#issues + 1] = "badTargetRank"
    end
  elseif a.kind == "setNote" then
    out.note = cleanText(a.note, RL.MAX_NOTE)
    out.public = a.public ~= false
    if out.note == "" then
      issues[#issues + 1] = "noNote"
    end
  elseif a.kind == "mark" then
    out.tag = VALUE.tag(a.tag)
    if not out.tag then
      issues[#issues + 1] = "noTag"
    end
  end
  return out
end

-- Issue code of a repaired action that cannot run yet (no target rank, note or marker), nil when complete.
function RL.ActionIssue(a)
  if type(a) ~= "table" then
    return "badAction"
  elseif a.kind == "setRank" and not a.rank and a.rankFrom ~= "main" then
    return "badTargetRank"
  elseif a.kind == "setNote" and (a.note or "") == "" then
    return "noNote"
  elseif a.kind == "mark" and not a.tag then
    return "noTag"
  end
  return nil
end

-- Rules -----------------------------------------------------------------------------------------------

-- index -> trimmed name of the guild ranks, nil when the guild gives no ranks.
local function rankNameMap(ranks)
  if type(ranks) ~= "table" then
    return nil
  end
  local map, any = {}, false
  for _, r in ipairs(ranks) do
    local i = type(r) == "table" and rankIndex(r.index)
    if i and type(r.name) == "string" then
      map[i], any = cleanText(r.name, RL.MAX_NAME), true
    end
  end
  return any and map or nil
end

-- True when the name stored with a rank no longer matches the guild. Fills in a name that was never
-- stored; returns whether the rank changed.
local function nameChanged(stored, index, current)
  if not current then
    return false
  end
  local name = current[index]
  if not name then
    return true
  end
  if stored[index] == nil then
    stored[index] = name
    return false
  end
  return stored[index]:lower() ~= name:lower()
end

-- raw: a rule from SavedVariables or the editor. ranks: { { index, name }... } of the guild or nil
-- (then rank names are not checked). Never raises. Returns the repaired rule and the list of issue
-- codes, or nil and a reason when the rule cannot be repaired. A rule is only enabled when it was
-- enabled, has a rank scope and no issue; an issue never enables.
-- Issues: noRanks, rankChanged (also in rule.review), badTargetRank, noNote, noTag.
function RL.CleanRule(raw, ranks)
  if type(raw) ~= "table" then
    return nil, "notARule"
  end
  local issues = {}
  local action, why = cleanAction(raw.action, issues)
  if not action then
    return nil, why
  end
  local all = {}
  for _, c in ipairs(type(raw.all) == "table" and raw.all or {}) do
    local clean, reason = RL.CleanCond(c)
    if not clean then
      return nil, reason
    end
    if #all >= RL.MAX_CONDITIONS then
      return nil, "tooManyConditions"
    end
    all[#all + 1] = clean
  end
  if #all == 0 then
    return nil, "noConditions"
  end

  -- The master (0) is never in a scope.
  local scope = rankList(raw.ranks, 1)
  local names = {}
  for _, i in ipairs(scope) do
    local n = type(raw.rankNames) == "table" and cleanText(raw.rankNames[i], RL.MAX_NAME) or ""
    names[i] = n ~= "" and n or nil
  end
  local current = rankNameMap(ranks)
  local changed = false
  for _, i in ipairs(scope) do
    changed = nameChanged(names, i, current) or changed
  end
  if action.rank then
    local stored = { [action.rank] = action.rankName }
    changed = nameChanged(stored, action.rank, current) or changed
    action.rankName = stored[action.rank]
  end
  if changed then
    issues[#issues + 1] = "rankChanged"
  end
  if #scope == 0 then
    issues[#issues + 1] = "noRanks"
  end

  local protect = type(raw.protect) == "table" and raw.protect or {}
  return {
    id = cleanText(raw.id, 20),
    name = cleanText(raw.name, RL.MAX_NAME),
    enabled = raw.enabled == true and #issues == 0,
    template = cleanText(raw.template, 30) ~= "" and cleanText(raw.template, 30) or nil,
    ranks = scope,
    rankNames = names,
    all = all,
    action = action,
    protect = {
      useGlobal = protect.useGlobal ~= false,
      extraRanks = rankList(protect.extraRanks, 0),
      extraKeys = keyList(protect.extraKeys),
    },
    maxPerRun = clamp(raw.maxPerRun, 1, RL.MAX_PER_RUN, RL.DEFAULT_PER_RUN),
    review = changed and "rankChanged" or nil,
  },
    issues
end

-- Repairs a whole list: keeps the order (= priority), gives each rule a unique id, drops what cannot
-- be repaired. Returns the clean list and the rejected ones { index, reason }.
function RL.CleanList(list, ranks)
  local out, rejected, used = {}, {}, {}
  for i, raw in ipairs(type(list) == "table" and list or {}) do
    local rule, reason
    if #out >= RL.MAX_RULES then
      reason = "tooManyRules"
    else
      rule, reason = RL.CleanRule(raw, ranks)
    end
    if rule then
      local id, n = rule.id, 0
      while id == "" or used[id] do
        n = n + 1
        id = "r" .. n
      end
      used[id] = true
      rule.id = id
      out[#out + 1] = rule
    else
      rejected[#rejected + 1] = { index = i, reason = reason }
    end
  end
  return out, rejected
end
