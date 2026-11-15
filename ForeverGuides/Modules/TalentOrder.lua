-- Skill order of a talent build (pure, no frames): the sequence in which the points are spent.
-- order = { { sid = spell id, rank = rank reached with this step }, ... }, one step per point. The
-- spell id (talent.sid) stays the same when the layout changes, the rank is the count of the talent's
-- steps so far, so a step is fully named by its spell id and its place in the list.
-- Rules per step: the talent rules of TalentLogic with the points spent before the step, the cap of
-- 51 points and the level budget (point n needs level n + 9). The order of the website is the same
-- list ({ talentId, rank } there, see TO.FromWeb and TO.ToWeb). Code format: docs/SKILLUNGEN-FORMAT.md.
local _, ns = ...
local L, TL = ns.L, ns.TalentLogic

local TO = {}
ns.TalentOrder = TO

local MARK = "o"
local BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz"
-- Talents with points that one character can name; more need two characters per step.
local ONE_CHAR = 36
local MAX_STEPS = TL.MAX_POINTS
-- Every class has three trees.
local SPECS = 3

ns.AddLocale("enUS", {
  ["talents.order.err.range"] = "That step does not exist.",
  ["talents.order.err.unknown"] = "This talent is not in the current talent data.",
  ["talents.order.err.max"] = "The talent is already at its maximum rank.",
  ["talents.order.err.points"] = "All 51 points are already spent.",
  ["talents.order.err.row"] = "Not enough points in the rows above at this step.",
  ["talents.order.err.req"] = "A required talent does not have the needed rank at this step.",
  ["talents.order.err.level"] = "The level is too low for this point.",
  ["talents.order.err.rank"] = "The rank numbers do not follow the order.",
  ["talents.order.err.none"] = "This talent has no point to take back.",
})
ns.AddLocale("deDE", {
  ["talents.order.err.range"] = "Diesen Schritt gibt es nicht.",
  ["talents.order.err.unknown"] = "Dieses Talent gibt es in den aktuellen Talentdaten nicht.",
  ["talents.order.err.max"] = "Das Talent hat schon den höchsten Rang.",
  ["talents.order.err.points"] = "Alle 51 Punkte sind schon verteilt.",
  ["talents.order.err.row"] = "An dieser Stelle fehlen Punkte in den Reihen darüber.",
  ["talents.order.err.req"] = "Ein vorausgesetztes Talent hat an dieser Stelle noch nicht den nötigen Rang.",
  ["talents.order.err.level"] = "Die Stufe reicht für diesen Punkt nicht.",
  ["talents.order.err.rank"] = "Die Ränge passen nicht zur Reihenfolge.",
  ["talents.order.err.none"] = "Dieses Talent hat keinen Punkt zum Zurücknehmen.",
})

-- Text of a reason code ("range", "unknown", "max", "points", "row", "req", "level", "rank", "none").
function TO.ReasonText(reason)
  return L["talents.order.err." .. tostring(reason)]
end

-- Lookup -----------------------------------------------------------------------------------------

local cache = setmetatable({}, { __mode = "k" })

-- { bySid = { [spell id] = talent }, seq = { [talent] = n } }: the first tree wins a spell id both
-- trees have (as in the v2 code), seq is the position over all trees in file order.
local function lookup(specs)
  local info = cache[specs]
  if not info then
    info = { bySid = {}, seq = {} }
    local n = 0
    for _, spec in ipairs(specs) do
      for _, talent in ipairs(spec.talents) do
        n = n + 1
        info.seq[talent] = n
        if talent.sid and not info.bySid[talent.sid] then
          info.bySid[talent.sid] = talent
        end
      end
    end
    cache[specs] = info
  end
  return info
end

local function stepTalent(specs, step)
  return type(step) == "table" and lookup(specs).bySid[step.sid] or nil
end

-- The talent a step names (nil for a spell id the data does not know).
function TO.TalentOf(specs, step)
  return stepTalent(specs, step)
end

local function rankOf(ranks, talent)
  return ranks[talent.id] or 0
end

local function copy(order)
  local out = {}
  for i, step in ipairs(order) do
    out[i] = { sid = step.sid, rank = step.rank }
  end
  return out
end

-- The rank of every step is the number of steps of its talent up to there.
local function renumber(order)
  local count = {}
  for _, step in ipairs(order) do
    count[step.sid] = (count[step.sid] or 0) + 1
    step.rank = count[step.sid]
  end
  return order
end

-- true when `stored` (untrusted) is exactly `order`.
local function sameOrder(order, stored)
  if #order ~= #stored then
    return false
  end
  for i, step in ipairs(order) do
    local other = stored[i]
    if type(other) ~= "table" or other.sid ~= step.sid or other.rank ~= step.rank then
      return false
    end
  end
  return true
end

-- Fallback ---------------------------------------------------------------------------------------

-- The order built from ranks alone: talents by required points, row, column (the position over all
-- trees breaks a tie), every rank point by point. Same result as deriveFallbackSkillOrder of the website.
function TO.Fallback(specs, ranks)
  local info, list = lookup(specs), {}
  for _, spec in ipairs(specs) do
    for _, talent in ipairs(spec.talents) do
      if talent.sid and rankOf(ranks, talent) > 0 then
        list[#list + 1] = talent
      end
    end
  end
  table.sort(list, function(a, b)
    if a.rp ~= b.rp then
      return a.rp < b.rp
    end
    if a.r ~= b.r then
      return a.r < b.r
    end
    if a.c ~= b.c then
      return a.c < b.c
    end
    return info.seq[a] < info.seq[b]
  end)
  local order = {}
  for _, talent in ipairs(list) do
    for rank = 1, rankOf(ranks, talent) do
      order[#order + 1] = { sid = talent.sid, rank = rank }
    end
  end
  return order
end

-- Reading ----------------------------------------------------------------------------------------

-- Ranks (by talent id) after the first n steps (all steps without n). Steps of a talent the data does
-- not know count as the second result.
function TO.RanksAt(specs, order, n)
  local ranks, unknown = {}, 0
  for i = 1, math.min(n or #order, #order) do
    local talent = stepTalent(specs, order[i])
    if talent then
      ranks[talent.id] = rankOf(ranks, talent) + 1
    else
      unknown = unknown + 1
    end
  end
  return ranks, unknown
end

-- Level the character needs for step n (the nth point).
function TO.StepLevel(n)
  return TL.LevelForPoints(n)
end

-- true, or false plus the reason code ("unknown", "max", "points", "row", "req", "level", "rank") and
-- the number of the first step that breaks it. level (optional) is the level of the build: it pays
-- for PointsForLevel(level) steps.
function TO.Validate(specs, order, level)
  local ranks, index = {}, TL.Index(specs)
  local budget = level and TL.PointsForLevel(level) or MAX_STEPS
  for i, step in ipairs(order) do
    local talent = stepTalent(specs, step)
    if not talent then
      return false, "unknown", i
    end
    if i > budget then
      return false, i > MAX_STEPS and "points" or "level", i
    end
    local ok, why = TL.CanAdd(specs, index.specOf[talent.id], talent, ranks, MAX_STEPS)
    if not ok then
      return false, why, i
    end
    ranks[talent.id] = rankOf(ranks, talent) + 1
    if step.rank ~= ranks[talent.id] then
      return false, "rank", i
    end
  end
  return true
end

-- true when the order holds exactly the points of ranks, no step more or less.
function TO.Consistent(specs, order, ranks)
  local got, unknown = TO.RanksAt(specs, order)
  if unknown > 0 then
    return false
  end
  for _, spec in ipairs(specs) do
    for _, talent in ipairs(spec.talents) do
      if rankOf(got, talent) ~= rankOf(ranks, talent) then
        return false
      end
    end
  end
  return true
end

-- Repair ---------------------------------------------------------------------------------------------

-- Places the steps one after the other, always the first one the rules allow at that point. Every
-- step waits only for steps it needs, all others keep their relative order. Returns the new order,
-- the number of steps that moved ahead of a waiting one and whether every step could be placed (they
-- can for ranks that follow the rules).
local function settle(specs, steps)
  local index, ranks, out, moved = TL.Index(specs), {}, {}, 0
  local waiting = steps
  while #waiting > 0 do
    local pick
    for i, step in ipairs(waiting) do
      local talent = stepTalent(specs, step)
      if talent and TL.CanAdd(specs, index.specOf[talent.id], talent, ranks, MAX_STEPS) then
        pick = i
        break
      end
    end
    if not pick then
      for _, step in ipairs(waiting) do
        out[#out + 1] = step
      end
      return renumber(out), moved, false
    end
    local step = table.remove(waiting, pick)
    local talent = stepTalent(specs, step)
    ranks[talent.id] = rankOf(ranks, talent) + 1
    if pick > 1 then
      moved = moved + 1
    end
    out[#out + 1] = step
  end
  return renumber(out), moved, true
end

-- Brings a stored order in line with the build (ranks, rule-checked): steps of talents the build does
-- not hold and steps above a talent's rank are left out, missing points follow in fallback order, then
-- steps that break the rules wait for what they need. Without an order (nil) the result is the
-- fallback order. Returns the order and a report { fallback, dropped, added, moved, invalid, changed }:
-- how many steps were left out, added and moved ahead, whether the ranks themselves break the rules
-- and whether the order differs from the stored one.
function TO.Repair(specs, ranks, order)
  if type(order) ~= "table" then
    return TO.Fallback(specs, ranks), { fallback = true, dropped = 0, added = 0, moved = 0, changed = true }
  end
  local used, steps, dropped = {}, {}, 0
  for i = 1, #order do
    local talent = stepTalent(specs, order[i])
    if talent and rankOf(used, talent) < math.min(rankOf(ranks, talent), talent.mr) then
      used[talent.id] = rankOf(used, talent) + 1
      steps[#steps + 1] = { sid = talent.sid, rank = 0 }
    else
      dropped = dropped + 1
    end
  end
  local missing = {}
  for _, spec in ipairs(specs) do
    for _, talent in ipairs(spec.talents) do
      local gap = math.min(rankOf(ranks, talent), talent.mr) - rankOf(used, talent)
      if gap > 0 then
        missing[talent.id] = gap
      end
    end
  end
  local extra = TO.Fallback(specs, missing)
  for _, step in ipairs(extra) do
    steps[#steps + 1] = step
  end
  local fixed, moved, whole = settle(specs, steps)
  return fixed,
    {
      dropped = dropped,
      added = #extra,
      moved = moved,
      invalid = not whole,
      changed = not sameOrder(fixed, order),
    }
end

-- Operations -------------------------------------------------------------------------------------------
-- Every operation leaves its input alone and returns true plus the new order, or false, a reason code
-- (see TO.ReasonText) and { index, sid } of the step that is the problem.

local function blocked(order, reason, at)
  local step = order[at]
  return false, reason, { index = at, sid = step and step.sid }
end

-- Moves step `from` to place `to`. Blocked when a step would need a point that comes later.
function TO.MoveTo(specs, order, from, to, level)
  local n = #order
  local function whole(i)
    return type(i) == "number" and i >= 1 and i <= n and i == math.floor(i)
  end
  if not (whole(from) and whole(to)) then
    return false, "range", { index = whole(from) and to or from }
  end
  local out = copy(order)
  if from ~= to then
    table.insert(out, to, table.remove(out, from))
    renumber(out)
  end
  local ok, reason, at = TO.Validate(specs, out, level)
  if not ok then
    return blocked(out, reason, at)
  end
  return true, out
end

function TO.MoveUp(specs, order, index, level)
  return TO.MoveTo(specs, order, index, index - 1, level)
end

function TO.MoveDown(specs, order, index, level)
  return TO.MoveTo(specs, order, index, index + 1, level)
end

-- Appends one point of `talent`. Blocked by the talent rules, the cap and the level (optional).
function TO.AddPoint(specs, order, talent, level)
  if not talent.sid then
    return false, "unknown", { sid = nil }
  end
  local ranks = TO.RanksAt(specs, order)
  local ok, reason = TL.CanAdd(specs, TL.Index(specs).specOf[talent.id], talent, ranks, MAX_STEPS)
  if not ok then
    return false, reason, { sid = talent.sid }
  end
  if level and #order >= TL.PointsForLevel(level) then
    return false, "level", { index = #order + 1, sid = talent.sid }
  end
  local out = copy(order)
  out[#out + 1] = { sid = talent.sid, rank = rankOf(ranks, talent) + 1 }
  return true, out
end

-- Takes back the last point of `talent` (its last step). Blocked when a talent or row that needs the
-- point would lose it (the rule of TL.CanRemove). Steps that only came too early now wait for what
-- they need, the number of them is the third result.
function TO.RemovePoint(specs, order, talent)
  local at
  for i = #order, 1, -1 do
    if order[i].sid == talent.sid then
      at = i
      break
    end
  end
  if not at then
    return false, "none", { sid = talent.sid }
  end
  local spec = TL.Index(specs).specOf[talent.id]
  local ranks = TO.RanksAt(specs, order)
  if not TL.CanRemove(spec, talent, ranks) then
    ranks[talent.id] = rankOf(ranks, talent) - 1
    for _, other in ipairs(spec.talents) do
      if rankOf(ranks, other) > 0 then
        for _, req in ipairs(other.rq or {}) do
          if (ranks[req.id] or 0) < req.q then
            return false, "req", { sid = other.sid }
          end
        end
        if TL.PointsBeforeRow(spec, ranks, other.r) < other.rp then
          return false, "row", { sid = other.sid }
        end
      end
    end
    return false, "row", { sid = talent.sid }
  end
  local out = copy(order)
  table.remove(out, at)
  local fixed, moved = settle(specs, out)
  return true, fixed, moved
end

-- Conversion to and from the website ---------------------------------------------------------------------

-- The website's list ({ talentId, rank } per point) as an order. Entries of an unknown talent are
-- left out (second result: how many); the ranks are counted anew.
function TO.FromWeb(specs, entries)
  local byId, order, dropped = TL.Index(specs).byId, {}, 0
  for _, entry in ipairs(type(entries) == "table" and entries or {}) do
    local talent = type(entry) == "table" and byId[entry.talentId]
    if talent and talent.sid then
      order[#order + 1] = { sid = talent.sid, rank = 0 }
    else
      dropped = dropped + 1
    end
  end
  return renumber(order), dropped
end

-- The order as the website's list. Steps of an unknown spell id are left out.
function TO.ToWeb(specs, order)
  local out = {}
  for _, step in ipairs(order) do
    local talent = stepTalent(specs, step)
    if talent then
      out[#out + 1] = { talentId = talent.id, rank = step.rank }
    end
  end
  return out
end

-- Code segment ---------------------------------------------------------------------------------------------
-- "o" + one name per step + 2 check characters (TL.Checksum of the names). A step names its talent by
-- the place of the talent in the list of talents with points, sorted by spell id (then tree): one
-- character 0-9a-z while at most 36 talents have points, else two. The rank of a step is implied by
-- the talent's earlier steps. The list comes from the build part of the code, so the segment is read
-- with the ranks of the same code.

local function holders(specs, ranks)
  local info, list = lookup(specs), {}
  for _, spec in ipairs(specs) do
    for _, talent in ipairs(spec.talents) do
      local rank = math.floor(rankOf(ranks, talent))
      if rank > 0 and talent.sid then
        list[#list + 1] = { talent = talent, rank = rank }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.talent.sid ~= b.talent.sid then
      return a.talent.sid < b.talent.sid
    end
    return info.seq[a.talent] < info.seq[b.talent]
  end)
  return list
end

local function name(value, width)
  local out = ""
  for _ = 1, width do
    local digit = value % 36
    out = BASE36:sub(digit + 1, digit + 1) .. out
    value = math.floor(value / 36)
  end
  return out
end

-- The segment of an order, or nil plus "mismatch" when the order does not hold exactly the points of
-- ranks (see TO.Repair) and "empty" without points.
function TO.Encode(specs, ranks, order)
  local list = holders(specs, ranks)
  if #list == 0 then
    return nil, "empty"
  end
  if not TO.Consistent(specs, order, ranks) then
    return nil, "mismatch"
  end
  local place = {}
  for i, entry in ipairs(list) do
    place[entry.talent.sid] = i - 1
  end
  local width = #list <= ONE_CHAR and 1 or 2
  local names = {}
  for i, step in ipairs(order) do
    names[i] = name(place[step.sid], width)
  end
  local body = table.concat(names)
  return MARK .. body .. TL.Checksum(body)
end

-- The steps of a segment (every talent exactly as often as its rank, not rule-checked, see TO.Repair) for the talents of ranks, or nil plus the
-- reason "format" (not a segment of this version), "check" (check characters wrong), "length" (steps
-- do not add up to the points), "name" (a step names no talent of the list) or "mismatch" (a talent
-- has other steps than ranks: the segment belongs to another build).
function TO.Decode(specs, ranks, segment)
  local list = holders(specs, ranks)
  local body = type(segment) == "string" and segment:match("^" .. MARK .. "([0-9a-z]+)$")
  if not body or #body < 3 then
    return nil, "format"
  end
  local names = body:sub(1, -3)
  if TL.Checksum(names) ~= body:sub(-2) then
    return nil, "check"
  end
  local width, points = #list <= ONE_CHAR and 1 or 2, 0
  for _, entry in ipairs(list) do
    points = points + entry.rank
  end
  if #names ~= points * width then
    return nil, "length"
  end
  local order, count = {}, {}
  for i = 1, #names, width do
    local entry = list[tonumber(names:sub(i, i + width - 1), 36) + 1]
    if not entry then
      return nil, "name"
    end
    count[entry] = (count[entry] or 0) + 1
    order[#order + 1] = { sid = entry.talent.sid, rank = 0 }
  end
  for _, entry in ipairs(list) do
    if count[entry] ~= entry.rank then
      return nil, "mismatch"
    end
  end
  return renumber(order)
end

-- Build code plus segment ("code-oSEGMENT"). A segment already on the code is replaced.
function TO.Join(code, segment)
  local build = TL.SplitOrder(TL.Bare(code), SPECS)
  return segment and (build .. "-" .. segment) or build
end

-- The segment for the order of a build given by any readable code: the order is brought in line with
-- the build first (TO.Repair). nil plus the reason "code" (build not readable), "none" (no order given)
-- or the reasons of TO.Encode.
function TO.SegmentFor(class, code, order)
  local specs = TL.Specs(class)
  local ranks = specs and TL.Parse(class, code)
  if not ranks then
    return nil, "code"
  end
  if type(order) ~= "table" then
    return nil, "none"
  end
  return TO.Encode(specs, ranks, (TO.Repair(specs, ranks, order)))
end

-- The code of a build with its order: `code` plus the segment of `order`. Without an order, or when
-- the build has no points, the code stays as it is (second result: why, see TO.SegmentFor).
function TO.CodeWithOrder(class, code, order)
  local segment, why = TO.SegmentFor(class, code, order)
  if not segment then
    return code, why
  end
  return TO.Join(code, segment)
end

-- The order a code carries (or `segment`, when given: the field `o` of Data/Builds.lua), already in
-- line with the build. Returns order, report: the report has `state` "none" (no segment), "ignored"
-- (segment damaged or foreign, reason in `why`, the build keeps its fallback order) or "ok", and the
-- repair counts of TO.Repair. nil as order for every state but "ok"; nil plus "invalid" when the build
-- itself cannot be read.
function TO.FromCode(class, code, segment)
  local specs = TL.Specs(class)
  local _, carried = TL.SplitOrder(TL.Bare(code), specs and #specs or SPECS)
  segment = carried or segment
  local ranks = specs and TL.Parse(class, code)
  if not ranks then
    return nil, { state = "invalid" }
  end
  if not segment then
    return nil, { state = "none" }
  end
  local raw = TL.Decode(code, specs)
  local steps, why = TO.Decode(specs, raw, segment)
  if not steps then
    return nil, { state = "ignored", why = why }
  end
  local order, report = TO.Repair(specs, ranks, steps)
  report.state = "ok"
  return order, report
end
