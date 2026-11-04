-- Rule engine, part 3, no game calls: builds the plan from rules and members. Deterministic, writes
-- nothing, the clock is an input.
--
-- Expected input of PlanLogic.Build(rules, ctx), plain tables only:
--   rules = { Rule... }  raw or clean, position = priority (see RulesLogic, repaired here again)
--   ctx = { today = day number, me = { key, rank }, ranks = { { index, name }... } (rank 0 = master),
--           rights = GuildExt.Rights() fields promote, demote, remove, publicNote, officerNote, officerEdit,
--           caps = { setNote = bool }, rosterAge = seconds (nil = not checked), maxTotal, maxLevel,
--           protect = { ranks, keys, words, newbieDays, graceDays, activeGroupDays }, skip = { [key] = untilDay },
--           only = id of the one rule to check (also when it is off),
--           members = { Member... } }
--   Member = { key, name, guid, rank, level, online, publicNote, officerNote (nil unless readable),
--              ownNote, mainKey, tags = { [tag] = true }, away = untilDay, returnedDay,
--              joined, rankSince, lastOnline = { minDay, maxDay, src } }
--
-- Result: { today, entries, rules, rulesSkipped, counts, summary, quality }. An entry is one member
-- under one rule: { key, name, guid, rule, ruleName, position, action, fromRank, toRank, maturity,
-- reason, reasonParams, missing, why, quality, checked, overruledBy }. maturity is one of
-- PL.MATURITY, reason a code of PL.REASONS (locale key "gm.why.<code>"). Only a "ready" entry is ever
-- executed; "remove" is never pre-checked. The guild master (rank 0) never appears in an entry.
local _, gm = ...
local RL = gm.RulesLogic
if not RL then
  return
end

local PL = {}
gm.PlanLogic = PL

-- Display order of the entries.
PL.MATURITY = { "ready", "later", "unknown", "conflict", "noRight", "blocked", "protected" }
PL.MAX_ROSTER_AGE = 120
PL.DEFAULT_TOTAL = 10
PL.MAX_TOTAL = 25
PL.DEFAULT_PROTECT = { newbieDays = 7, graceDays = 14, activeGroupDays = 14, words = { "urlaub" } }

-- Every reason code of an entry; the first group shares the locale keys of ActionsLogic.
PL.REASONS = {
  "noRight",
  "self",
  "leader",
  "notLower",
  "promoteCap",
  "lowest",
  "unknownRank",
  "noApi",
  "staleRoster",
  "leaderTarget",
  "unknownData",
  "noMain",
  "protectTag",
  "protectAway",
  "protectSkip",
  "protectKey",
  "protectRank",
  "protectWord",
  "protectNewbie",
  "protectGrace",
  "protectGroup",
  "overruled",
  "maxPerRun",
  "maxTotal",
}

local MATURITY_OF = {
  noRight = "noRight",
  self = "protected",
  protectTag = "protected",
  protectAway = "protected",
  protectSkip = "protected",
  protectKey = "protected",
  protectRank = "protected",
  protectWord = "protected",
  protectNewbie = "protected",
  protectGrace = "protected",
  protectGroup = "protected",
}
local RANKED = { promote = true, demote = true, setRank = true, remove = true }
-- Actions that only touch the add-on store: newbie and return protection do not apply.
local LOCAL = { mark = true, none = true }
local NEGATIVE = { demote = true, remove = true }
-- Never ticked in advance: a removal is always a conscious click, "none" has nothing to run.
local NOT_CHECKED = { remove = true, none = true }

local function cleanProtect(p)
  p = type(p) == "table" and p or {}
  local D = PL.DEFAULT_PROTECT
  local out = {
    newbieDays = RL.Clamp(p.newbieDays, 0, 365, D.newbieDays),
    graceDays = RL.Clamp(p.graceDays, 0, 365, D.graceDays),
    activeGroupDays = RL.Clamp(p.activeGroupDays, 0, 365, D.activeGroupDays),
    words = {},
    ranks = {},
    keys = {},
  }
  for _, w in ipairs(type(p.words) == "table" and p.words or D.words) do
    w = RL.CleanText(w, RL.MAX_NOTE):lower()
    if w ~= "" and #out.words < RL.MAX_LIST then
      out.words[#out.words + 1] = w
    end
  end
  for _, r in ipairs(type(p.ranks) == "table" and p.ranks or {}) do
    local i = RL.RankIndex(r)
    if i then
      out.ranks[i] = true
    end
  end
  for _, k in ipairs(type(p.keys) == "table" and p.keys or {}) do
    if type(k) == "string" then
      out.keys[k] = true
    end
  end
  return out
end

-- Rank after the action; nil for actions that keep the rank. For "rank of the main" a main that is
-- missing from the roster gives nil and `false` as second value.
local function targetRank(a, m, env)
  if a.kind == "promote" then
    return m.rank - 1
  elseif a.kind == "demote" then
    return m.rank + 1
  elseif a.kind == "setRank" then
    if a.rankFrom == "main" then
      local main = RL.MainOf(env, m)
      local r = main and RL.RankIndex(main.rank)
      return r, r ~= nil
    end
    return a.rank
  end
  return nil, true
end

-- Locks no rule can lift: stale roster, missing right, rank rules of the game.
local function blockReason(a, m, to, x)
  if x.stale then
    return "staleRoster"
  end
  local field
  if a.kind == "promote" or a.kind == "demote" or a.kind == "remove" then
    field = a.kind
  elseif a.kind == "setRank" then
    field = to < m.rank and "promote" or "demote"
  elseif a.kind == "setNote" then
    field = a.public and "publicNote" or "officerEdit"
  end
  if field and x.rights[field] ~= true then
    return "noRight"
  end
  if a.kind == "setNote" and x.caps.setNote ~= true then
    return "noApi"
  end
  if not RANKED[a.kind] then
    return nil
  end
  if not x.mine then
    return "unknownRank"
  end
  if m.rank <= x.mine then
    return "notLower"
  end
  if to then
    if to == 0 then
      return "leaderTarget"
    end
    if to < m.rank and to <= x.mine then
      return "promoteCap"
    end
    if a.kind == "demote" and to > x.lowest then
      return "lowest"
    end
    if a.kind == "setRank" and not x.have[to] then
      return "unknownRank"
    end
  end
  return nil
end

local function noteWord(m, words, officer)
  for _, text in ipairs({ m.publicNote, officer and m.officerNote or false, m.ownNote }) do
    if type(text) == "string" then
      text = text:lower()
      for _, w in ipairs(words) do
        if text:find(w, 1, true) then
          return w
        end
      end
    end
  end
end

-- Members the rule must not touch. Always on: marker, absence, "skip today". Behind the rule's
-- useGlobal: the global lists, newbie and return grace, active group.
local function protectReason(rule, a, m, env, x)
  local today = env.today
  if type(m.tags) == "table" and m.tags.protect then
    return "protectTag"
  end
  local away = RL.Whole(m.away)
  if away and away >= today then
    return "protectAway", { untilDay = away }
  end
  local skip = RL.Whole(x.skip[m.key])
  if skip and skip >= today then
    return "protectSkip", { untilDay = skip }
  end
  for _, k in ipairs(rule.protect.extraKeys) do
    if k == m.key then
      return "protectKey"
    end
  end
  for _, r in ipairs(rule.protect.extraRanks) do
    if r == m.rank then
      return "protectRank"
    end
  end
  if not rule.protect.useGlobal then
    return nil
  end
  local p = x.protect
  if p.keys[m.key] then
    return "protectKey"
  end
  if p.ranks[m.rank] then
    return "protectRank"
  end
  local word = noteWord(m, p.words, env.officerNote)
  if word then
    return "protectWord", { word = word }
  end
  if not LOCAL[a.kind] then
    if p.newbieDays > 0 then
      -- "Safely" in the guild: only a real lower bound counts, a member of unknown age may be new.
      local lo = RL.Span(m.joined, today)
      if not lo or lo < p.newbieDays then
        return "protectNewbie", { days = lo, need = p.newbieDays }
      end
    end
    local returned = RL.Whole(m.returnedDay)
    if p.graceDays > 0 and returned and today - returned < p.graceDays then
      return "protectGrace", { days = today - returned, need = p.graceDays }
    end
  end
  if NEGATIVE[a.kind] and p.activeGroupDays > 0 then
    for _, g in ipairs(RL.GroupOf(env, m)) do
      if g.key ~= m.key then
        local _, hi = RL.Offline(g, today)
        if hi and hi < p.activeGroupDays then
          return "protectGroup", { by = g.key }
        end
      end
    end
  end
  return nil
end

local function missingOf(answers)
  local out, seen = {}, {}
  for _, a in ipairs(answers) do
    if a.result == RL.UNKNOWN and a.missing and not seen[a.missing] then
      seen[a.missing] = true
      out[#out + 1] = a.missing
    end
  end
  return out
end

local function copyAction(a)
  local out = {}
  for k, v in pairs(a) do
    out[k] = v
  end
  return out
end

-- One member under one rule whose conditions did not say no. nil when nothing is worth showing.
local function decide(rule, position, m, result, answers, q, env, x)
  local a = rule.action
  local to, known = targetRank(a, m, env)
  if to ~= nil and to == m.rank then
    return nil
  end
  local reason, params
  if x.meKey and m.key == x.meKey then
    reason = "self"
  elseif known ~= false then
    reason = blockReason(a, m, to, x)
  end
  if not reason then
    reason, params = protectReason(rule, a, m, env, x)
  end
  if reason and result == RL.UNKNOWN then
    return nil
  end
  local entry = {
    key = m.key,
    name = type(m.name) == "string" and m.name or m.key,
    guid = m.guid,
    rule = rule.id,
    ruleName = rule.name,
    position = position,
    action = copyAction(a),
    fromRank = m.rank,
    -- A blocked target of rank 0 stays out of the entry, the reason says it.
    toRank = to ~= 0 and to or nil,
    why = answers,
    quality = q,
    checked = false,
  }
  if a.kind == "setNote" then
    local lo, hi = RL.Span(m.joined, env.today)
    entry.joinedDay = lo and hi == lo and env.today - lo or nil
  end
  if reason then
    entry.maturity, entry.reason, entry.reasonParams = MATURITY_OF[reason] or "blocked", reason, params
  elseif result == RL.UNKNOWN then
    entry.maturity, entry.reason, entry.missing = "unknown", "unknownData", missingOf(answers)
  elseif known == false then
    entry.maturity, entry.reason, entry.missing = "unknown", "noMain", { "main" }
  else
    entry.maturity = "ready"
  end
  return entry
end

local function newCounts()
  local out = {}
  for _, name in ipairs(PL.MATURITY) do
    out[name] = 0
  end
  return out
end

local function rankMap(ranks)
  local have, lowest = {}, nil
  for _, r in ipairs(type(ranks) == "table" and ranks or {}) do
    local i = type(r) == "table" and RL.RankIndex(r.index)
    if i then
      have[i] = true
      lowest = math.max(lowest or 0, i)
    end
  end
  return have, lowest
end

local function order(a, b)
  if a.mature ~= b.mature then
    return a.mature < b.mature
  end
  if a.e.position ~= b.e.position then
    return a.e.position < b.e.position
  end
  return a.e.key < b.e.key
end

-- Why a rule is left out, nil when it takes part. only: the id of the one rule to check (it counts as on,
-- also when it is off; an unfinished one is still left out).
local function skipReason(rule, only)
  if only and rule.id ~= only then
    return "notChosen"
  elseif rule.review then
    return rule.review
  elseif #rule.ranks == 0 then
    return "noRanks"
  elseif RL.ActionIssue(rule.action) then
    return only and "incomplete" or "disabled"
  elseif not rule.enabled and not only then
    return "disabled"
  end
  return nil
end

-- Builds the plan, never raises. A rule that is off, has no rank scope or changed its ranks is listed
-- in rulesSkipped; ctx.only (a rule id) checks that one rule even when it is off. Conflicts: one step per member and run, the rule higher in the list wins. Limits:
-- maxPerRun of the rule and maxTotal of the run, the rest stays visible as "later".
function PL.Build(rules, ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local plan = {
    entries = {},
    rules = {},
    rulesSkipped = {},
    counts = newCounts(),
    summary = {},
    quality = { exact = 0, earliest = 0 },
  }
  for _, kind in ipairs(RL.ACTIONS) do
    plan.summary[kind] = 0
  end
  local rights = type(ctx.rights) == "table" and ctx.rights or {}
  local env = RL.Env({
    today = ctx.today,
    members = ctx.members,
    maxLevel = ctx.maxLevel,
    officerNote = rights.officerNote == true,
  })
  plan.today = env.today
  local only = type(ctx.only) == "string" and ctx.only ~= "" and ctx.only or nil
  plan.only = only
  local clean, rejected = RL.CleanList(rules, ctx.ranks)
  for _, r in ipairs(rejected) do
    plan.rulesSkipped[#plan.rulesSkipped + 1] = { index = r.index, reason = r.reason }
  end

  local have, lowest = rankMap(ctx.ranks)
  local me = type(ctx.me) == "table" and ctx.me or {}
  local x = {
    meKey = type(me.key) == "string" and me.key or nil,
    mine = RL.RankIndex(me.rank),
    lowest = lowest,
    have = have,
    rights = rights,
    caps = type(ctx.caps) == "table" and ctx.caps or {},
    stale = type(ctx.rosterAge) == "number" and ctx.rosterAge > PL.MAX_ROSTER_AGE,
    protect = cleanProtect(ctx.protect),
    skip = type(ctx.skip) == "table" and ctx.skip or {},
  }
  local maxTotal = RL.Clamp(ctx.maxTotal, 1, PL.MAX_TOTAL, PL.DEFAULT_TOTAL)

  -- Without a day or a rank list nothing can be judged.
  local blocked = (not env.today and "noToday") or (not lowest and "noRanks") or nil

  local candidates = {}
  for position, rule in ipairs(clean) do
    local why = blocked or skipReason(rule, only)
    if why and why ~= "notChosen" then
      plan.rulesSkipped[#plan.rulesSkipped + 1] = { id = rule.id, name = rule.name, position = position, reason = why }
    elseif not why then
      plan.rules[#plan.rules + 1] = { id = rule.id, name = rule.name, position = position, counts = newCounts() }
      local scope = {}
      for _, r in ipairs(rule.ranks) do
        scope[r] = true
      end
      for _, m in ipairs(env.list) do
        -- The master is never a source or a target, whatever the rule says.
        if scope[m.rank] and m.rank ~= 0 then
          local result, answers, q = RL.Evaluate(rule, m, env)
          if result ~= RL.NO then
            local entry = decide(rule, position, m, result, answers, q, env, x)
            if entry then
              candidates[#candidates + 1] = entry
            end
          end
        end
      end
    end
  end

  -- Conflicts: the first ready entry of a member wins. "none" only reports, it neither wins nor loses.
  local winner = {}
  for _, e in ipairs(candidates) do
    if e.maturity == "ready" and e.action.kind ~= "none" then
      if winner[e.key] then
        e.maturity, e.reason, e.overruledBy = "conflict", "overruled", winner[e.key]
      else
        winner[e.key] = e.rule
      end
    end
  end

  -- Limits, in rule order.
  local perRule, total = {}, 0
  local limit = {}
  for _, rule in ipairs(clean) do
    limit[rule.id] = rule.maxPerRun
  end
  for _, e in ipairs(candidates) do
    if e.maturity == "ready" and e.action.kind == "none" then
      e.checked = false
    elseif e.maturity == "ready" then
      perRule[e.rule] = perRule[e.rule] or 0
      if perRule[e.rule] >= limit[e.rule] then
        e.maturity, e.reason = "later", "maxPerRun"
      elseif total >= maxTotal then
        e.maturity, e.reason = "later", "maxTotal"
      else
        perRule[e.rule], total = perRule[e.rule] + 1, total + 1
        e.checked = not NOT_CHECKED[e.action.kind]
      end
    end
  end

  local byRule = {}
  for _, r in ipairs(plan.rules) do
    byRule[r.id] = r
  end
  local rank = {}
  for i, name in ipairs(PL.MATURITY) do
    rank[name] = i
  end
  local sorted = {}
  for _, e in ipairs(candidates) do
    sorted[#sorted + 1] = { mature = rank[e.maturity], e = e }
    plan.counts[e.maturity] = plan.counts[e.maturity] + 1
    byRule[e.rule].counts[e.maturity] = byRule[e.rule].counts[e.maturity] + 1
    if e.maturity == "ready" then
      plan.summary[e.action.kind] = plan.summary[e.action.kind] + 1
      if e.quality then
        plan.quality[e.quality] = plan.quality[e.quality] + 1
      end
    end
  end
  table.sort(sorted, order)
  for i, s in ipairs(sorted) do
    plan.entries[i] = s.e
  end
  return plan
end
