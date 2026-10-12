-- Talent editor rules (pure, no frames): point budget by level, row gating,
-- prerequisites, whole-tree removal check and the web build-link format.
-- Data: ns.Data.TalentTrees (talents sorted by row, column). Mirrors
-- the talent calculator of the website.
-- ranks = { [talentId] = rank } for one class (talent ids are unique per class);
-- absent means 0.
local _, ns = ...

local TL = {}
ns.TalentLogic = TL

-- Same values as the header of Data/TalentTrees.lua (checked in the tests).
TL.POINTS_PER_ROW = 5
TL.MAX_POINTS = 51
TL.MIN_LEVEL = 10
TL.MAX_LEVEL = 60

-- Build link v1: one digit 0-9 per talent of the v1 layout (see v1Talents).
local MAX_DIGIT = 9

local function rankOf(ranks, id)
  return ranks[id] or 0
end

-- List of three spec trees for a class token, or nil without data.
function TL.Specs(class)
  local data = ns.Data and ns.Data.TalentTrees
  return data and data.classes and data.classes[class] or nil
end

local indexCache = setmetatable({}, { __mode = "k" })

-- { byId = { [talentId] = talent }, specOf = { [talentId] = spec } } over all specs.
function TL.Index(specs)
  local index = indexCache[specs]
  if not index then
    index = { byId = {}, specOf = {} }
    for _, spec in ipairs(specs) do
      for _, talent in ipairs(spec.talents) do
        index.byId[talent.id] = talent
        index.specOf[talent.id] = spec
      end
    end
    indexCache[specs] = index
  end
  return index
end

-- Level ---------------------------------------------------------------------

-- Anything that is not a number becomes the level cap.
function TL.ClampLevel(level)
  level = tonumber(level)
  if not level then
    return TL.MAX_LEVEL
  end
  return math.min(TL.MAX_LEVEL, math.max(TL.MIN_LEVEL, math.floor(level)))
end

-- Level 10 gives the first point, level 60 the 51st.
function TL.PointsForLevel(level)
  return math.min(TL.MAX_POINTS, TL.ClampLevel(level) - (TL.MIN_LEVEL - 1))
end

-- Lowest level that still pays for this many points.
function TL.LevelForPoints(points)
  return TL.ClampLevel(points + (TL.MIN_LEVEL - 1))
end

-- Points -------------------------------------------------------------------

function TL.PointsInSpec(spec, ranks)
  local sum = 0
  for _, talent in ipairs(spec.talents) do
    sum = sum + rankOf(ranks, talent.id)
  end
  return sum
end

-- Ceiling of one tree: every talent at max rank, not the level budget.
function TL.MaxPointsInSpec(spec)
  local sum = 0
  for _, talent in ipairs(spec.talents) do
    sum = sum + talent.mr
  end
  return sum
end

function TL.Total(specs, ranks)
  local sum = 0
  for _, spec in ipairs(specs) do
    sum = sum + TL.PointsInSpec(spec, ranks)
  end
  return sum
end

-- Points spent in rows strictly above `row`. Points in the talent's own row or
-- below must not count, otherwise removing a point from an earlier row could
-- hide behind later points.
function TL.PointsBeforeRow(spec, ranks, row)
  local sum = 0
  for _, talent in ipairs(spec.talents) do
    if talent.r < row then
      sum = sum + rankOf(ranks, talent.id)
    end
  end
  return sum
end

-- Next row threshold the tree has not unlocked yet, nil when all are open.
function TL.NextThreshold(spec, ranks)
  local maxRow = 0
  for _, talent in ipairs(spec.talents) do
    maxRow = math.max(maxRow, talent.r)
  end
  local per = TL.POINTS_PER_ROW
  local threshold = (math.floor(TL.PointsInSpec(spec, ranks) / per) + 1) * per
  return threshold <= maxRow * per and threshold or nil
end

-- Prerequisites ---------------------------------------------------------------

local function requirementsMet(talent, ranks)
  for _, req in ipairs(talent.rq or {}) do
    if rankOf(ranks, req.id) < req.q then
      return false
    end
  end
  return true
end

-- Add / remove --------------------------------------------------------------

-- true, or false plus the reason: "max", "points", "row" or "req".
function TL.CanAdd(specs, spec, talent, ranks, maxPoints)
  if rankOf(ranks, talent.id) >= talent.mr then
    return false, "max"
  end
  if TL.Total(specs, ranks) >= maxPoints then
    return false, "points"
  end
  if TL.PointsBeforeRow(spec, ranks, talent.r) < talent.rp then
    return false, "row"
  end
  if not requirementsMet(talent, ranks) then
    return false, "req"
  end
  return true
end

-- Every talent that holds points must still meet its own row threshold and
-- prerequisites. Row sums are built once per call.
function TL.IsValid(spec, ranks)
  local rowSum, maxRow = {}, 0
  for _, talent in ipairs(spec.talents) do
    maxRow = math.max(maxRow, talent.r)
    rowSum[talent.r] = (rowSum[talent.r] or 0) + rankOf(ranks, talent.id)
  end
  local before, above = {}, 0
  for row = 0, maxRow do
    before[row] = above
    above = above + (rowSum[row] or 0)
  end
  for _, talent in ipairs(spec.talents) do
    local rank = rankOf(ranks, talent.id)
    if rank > 0 then
      if rank > talent.mr or before[talent.r] < talent.rp or not requirementsMet(talent, ranks) then
        return false
      end
    end
  end
  return true
end

-- Removing a point can break a dependent talent or a later row threshold, so
-- the whole tree is validated with the point taken away (and put back).
function TL.CanRemove(spec, talent, ranks)
  local rank = rankOf(ranks, talent.id)
  if rank <= 0 then
    return false
  end
  ranks[talent.id] = rank - 1
  local valid = TL.IsValid(spec, ranks)
  ranks[talent.id] = rank
  return valid
end

function TL.Add(specs, spec, talent, ranks, maxPoints)
  if not TL.CanAdd(specs, spec, talent, ranks, maxPoints) then
    return false
  end
  ranks[talent.id] = rankOf(ranks, talent.id) + 1
  return true
end

function TL.Remove(spec, talent, ranks)
  if not TL.CanRemove(spec, talent, ranks) then
    return false
  end
  local rank = rankOf(ranks, talent.id) - 1
  ranks[talent.id] = rank > 0 and rank or nil
  return true
end

function TL.Reset(ranks)
  for id in pairs(ranks) do
    ranks[id] = nil
  end
end

-- "maxed", "partly", "available" or "locked" (plus the CanAdd reason).
function TL.Status(specs, spec, talent, ranks, maxPoints)
  local rank = rankOf(ranks, talent.id)
  if rank >= talent.mr then
    return "maxed"
  elseif rank > 0 then
    return "partly"
  end
  local ok, reason = TL.CanAdd(specs, spec, talent, ranks, maxPoints)
  return ok and "available" or "locked", reason
end

-- Summary -------------------------------------------------------------------

-- "31/20/0": points per tree in display order.
function TL.Summary(specs, ranks)
  local parts = {}
  for i, spec in ipairs(specs) do
    parts[i] = TL.PointsInSpec(spec, ranks)
  end
  return table.concat(parts, "/")
end

-- Description of a rank in the active language. Ranks beyond the documented
-- ones reuse the last text.
function TL.RankText(talent, rank)
  local list = ns.T(talent.d)
  if type(list) ~= "table" or #list == 0 or rank < 1 then
    return nil
  end
  return list[math.min(rank, #list)]
end

-- Build link ------------------------------------------------------------------

-- The talents of a tree in v1 digit order: the tree without the hotfix nodes (nv1 = true), the
-- layout of every v1 code written before those nodes existed.
local function v1Talents(spec)
  local list = {}
  for _, talent in ipairs(spec.talents) do
    if not talent.nv1 then
      list[#list + 1] = talent
    end
  end
  return list
end

-- Talents a hotfix replaced in place, by game node: the node kept its position (so the v1 digit
-- order is unchanged) but holds another talent now. `sid` and `name` are the replaced talent's
-- (the v1 snapshot of the website). A v1 digit there meant the old talent, so reading it drops the
-- points like the website does; the new talent has to be chosen again.
TL.V1_REPLACED = {
  [110857] = { sid = 12962, name = { de = "Eiserner Wille", en = "Iron Will" } },
  [105953] = { sid = 1310236, name = { de = "Grenzenlose Wut", en = "Boundless Rage" } },
}

-- The replaced talent of a node while the data still holds a different one there, else nil.
local function replacedAt(talent)
  local old = talent.node and TL.V1_REPLACED[talent.node]
  if old and old.sid ~= talent.sid then
    return old
  end
end

-- true when a node outside the v1 digits holds points: a hotfix node or a replaced talent.
local function usesNewNodes(specs, ranks)
  for _, spec in ipairs(specs) do
    for _, talent in ipairs(spec.talents) do
      if (talent.nv1 or replacedAt(talent)) and rankOf(ranks, talent.id) > 0 then
        return true
      end
    end
  end
  return false
end

-- v1 digits: one per talent of the v1 layout. Points on hotfix nodes and on replaced talents
-- cannot be written (they would read as the old talent).
function TL.EncodeV1(specs, ranks)
  local segments = {}
  for i, spec in ipairs(specs) do
    local digits = {}
    for j, talent in ipairs(v1Talents(spec)) do
      local rank = replacedAt(talent) and 0 or rankOf(ranks, talent.id)
      digits[j] = tostring(math.min(MAX_DIGIT, math.max(0, math.floor(rank))))
    end
    segments[i] = table.concat(digits)
  end
  return table.concat(segments, "-")
end

-- The code kept in the saved builds and sent in chat links: v1 digits while a build fits them (older
-- codes and clients stay valid), the spell-id format (v2) once a hotfix node holds points.
function TL.Encode(specs, ranks)
  if usesNewNodes(specs, ranks) then
    return TL.EncodeV2(specs, ranks) or TL.EncodeV1(specs, ranks)
  end
  return TL.EncodeV1(specs, ranks)
end

-- Build link v2 (as on the website): "v2." plus one entry per talent with
-- points, sorted by spell id: the spell id in 5 base36 digits and the rank 1-9, then 2 check
-- characters. The spell id (talent.sid) is stable when talents move, so v2 survives data updates.
local V2_TAG = "v2."
local V2_ENTRY = 6
local V2_CHECK = 1296
local BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz"

local function base36(value, width)
  local out = ""
  repeat
    local digit = value % 36
    out = BASE36:sub(digit + 1, digit + 1) .. out
    value = math.floor(value / 36)
  until value == 0
  return string.rep("0", width - #out) .. out
end

local function checksum(body)
  local acc = 0
  for i = 1, #body do
    acc = (acc * 37 + tonumber(body:sub(i, i), 36)) % V2_CHECK
  end
  return base36(acc, 2)
end

-- true when the code is written in the v2 format (the website's current one).
function TL.IsV2(text)
  return tostring(text or ""):sub(1, #V2_TAG) == V2_TAG
end

-- The v2 code of ranks, or nil when a talent with points has no spell id or one that does not
-- fit 5 digits.
function TL.EncodeV2(specs, ranks)
  local found = {}
  for specIndex, spec in ipairs(specs) do
    for _, talent in ipairs(spec.talents) do
      local rank = math.min(MAX_DIGIT, math.floor(rankOf(ranks, talent.id)))
      if rank > 0 then
        if type(talent.sid) ~= "number" or talent.sid < 0 or talent.sid >= 36 ^ (V2_ENTRY - 1) then
          return nil
        end
        found[#found + 1] = { sid = talent.sid, rank = rank, spec = specIndex }
      end
    end
  end
  table.sort(found, function(a, b)
    if a.sid ~= b.sid then
      return a.sid < b.sid
    end
    return a.spec < b.spec
  end)
  local parts = {}
  for i, entry in ipairs(found) do
    parts[i] = base36(entry.sid, V2_ENTRY - 1) .. entry.rank
  end
  local body = table.concat(parts)
  return V2_TAG .. body .. checksum(body)
end

local sidCache = setmetatable({}, { __mode = "k" })

-- One { [spell id] = talent } table per tree (spell ids are unique within a tree only).
local function sidMaps(specs)
  local maps = sidCache[specs]
  if not maps then
    maps = {}
    for i, spec in ipairs(specs) do
      maps[i] = {}
      for _, talent in ipairs(spec.talents) do
        if talent.sid then
          maps[i][talent.sid] = talent
        end
      end
    end
    sidCache[specs] = maps
  end
  return maps
end

-- Same contract as the v1 read below. A damaged code (characters, length, check characters, rank 0,
-- a spell id twice) gives no ranks and one problem; a spell id of no talent of the class counts
-- as a problem, a rank above the maximum is cut down and counts too.
local function decodeV2(text, specs)
  local ranks, problems = {}, 0
  local payload = text:sub(#V2_TAG + 1)
  if not payload:match("^[0-9a-z]+$") or (#payload - 2) % V2_ENTRY ~= 0 then
    return ranks, 1
  end
  local body = payload:sub(1, -3)
  if checksum(body) ~= payload:sub(-2) then
    return ranks, 1
  end
  local seen, maps = {}, sidMaps(specs)
  for i = 1, #body, V2_ENTRY do
    local sid = tonumber(body:sub(i, i + V2_ENTRY - 2), 36)
    local rank = tonumber(body:sub(i + V2_ENTRY - 1, i + V2_ENTRY - 1))
    if not rank or rank < 1 or seen[sid] then
      return {}, 1
    end
    seen[sid] = true
    local talent
    for _, map in ipairs(maps) do
      talent = talent or map[sid]
    end
    if not talent then
      problems = problems + 1
    else
      if rank > talent.mr then
        rank = talent.mr
        problems = problems + 1
      end
      ranks[talent.id] = rank
    end
  end
  return ranks, problems
end

local function split(text)
  local out, pos = {}, 1
  while true do
    local i = text:find("-", pos, true)
    if not i then
      out[#out + 1] = text:sub(pos)
      return out
    end
    out[#out + 1] = text:sub(pos, i - 1)
    pos = i + 1
  end
end

-- Accepts the bare code (v1: one digit per talent of the v1 layout, so codes from before the hotfix
-- nodes still read right; v2: "v2." and spell ids, see above) or a pasted
-- web address with ?b=<code>. Never errors:
-- unreadable characters stay 0, digits above a talent's max rank are cut down.
-- Returns ranks and the number of problems (wrong segment count or length,
-- unreadable characters, clamped digits). The result is not rule-checked, see
-- TL.Normalize. The third result lists the v1 points dropped because a hotfix replaced the talent
-- (see TL.V1_REPLACED): { id, node, sid, name = { de, en }, rank } of the OLD talent. They are no
-- problems. v2 codes name the talent by spell id and never drop this way.
function TL.Decode(text, specs)
  local ranks, problems, dropped = {}, 0, {}
  text = tostring(text or ""):gsub("%s+", "")
  text = text:match("[%?&]b=([^&#]*)") or text
  if text == "" then
    return ranks, 0, dropped
  end
  if TL.IsV2(text) then
    local v2, bad = decodeV2(text, specs)
    return v2, bad, dropped
  end
  local segments = split(text)
  if #segments ~= #specs then
    problems = problems + 1
  end
  for i, spec in ipairs(specs) do
    local segment = segments[i] or ""
    local layout = v1Talents(spec)
    if #segment ~= #layout then
      problems = problems + 1
    end
    for j, talent in ipairs(layout) do
      local char = segment:sub(j, j)
      if char ~= "" then
        local digit = char:match("^%d$") and tonumber(char)
        local old = replacedAt(talent)
        if not digit then
          problems = problems + 1
        elseif old then
          if digit > 0 then
            dropped[#dropped + 1] = { id = talent.id, node = talent.node, sid = old.sid, name = old.name, rank = digit }
          end
        else
          if digit > talent.mr then
            digit = talent.mr
            problems = problems + 1
          end
          if digit > 0 then
            ranks[talent.id] = digit
          end
        end
      end
    end
  end
  return ranks, problems, dropped
end

-- Replays wanted ranks through the rules (row gating, prerequisites, point
-- budget) and keeps what fits. Returns the valid ranks and how many wanted
-- points had to be left out.
function TL.Normalize(specs, wanted, maxPoints)
  local ranks, requested = {}, 0
  for _, spec in ipairs(specs) do
    for _, talent in ipairs(spec.talents) do
      requested = requested + math.min(rankOf(wanted, talent.id), talent.mr)
    end
  end
  local progress = true
  while progress do
    progress = false
    for _, spec in ipairs(specs) do
      for _, talent in ipairs(spec.talents) do
        while rankOf(ranks, talent.id) < rankOf(wanted, talent.id) and TL.Add(specs, spec, talent, ranks, maxPoints) do
          progress = true
        end
      end
    end
  end
  return ranks, requested - TL.Total(specs, ranks)
end

-- Strict read of a build from outside (chat link, API): the class needs data,
-- the code must decode cleanly and survive the rules untouched. Returns the
-- ranks and their total, or nil and the number of problems. Points dropped for a replaced talent
-- (third result, see TL.Decode) are no problem; points that lose their row or prerequisite through
-- that are left out too and counted in the fourth result.
function TL.Parse(class, text)
  local list = TL.Specs(class)
  if not list or tostring(text or "") == "" then
    return nil, 1
  end
  local decoded, problems, replaced = TL.Decode(text, list)
  if problems > 0 then
    return nil, problems
  end
  local ranks, left = TL.Normalize(list, decoded, TL.MAX_POINTS)
  if left > 0 and #replaced == 0 then
    return nil, left
  end
  return ranks, TL.Total(list, ranks), replaced, left
end

-- Maps purchased ranks per game node ({ [nodeID] = ranks }, as read by
-- TalentApply.readNodeRanks) back to talent ids through talent.node. Returns
-- the ranks (not rule-checked, see TL.Normalize) and how many points belong to
-- no known talent or exceed its max rank.
function TL.RanksFromNodes(specs, nodeRanks)
  local byNode = {}
  for _, spec in ipairs(specs) do
    for _, talent in ipairs(spec.talents) do
      if talent.node then
        byNode[talent.node] = talent
      end
    end
  end
  local ranks, unmapped = {}, 0
  for nodeId, purchased in pairs(nodeRanks) do
    local talent = byNode[nodeId]
    local kept = talent and math.min(purchased, talent.mr) or 0
    if kept > 0 then
      ranks[talent.id] = kept
    end
    unmapped = unmapped + purchased - kept
  end
  return ranks, unmapped
end

-- Entries for TalentApply.applyEntries: one per talent with points, in tree order.
function TL.NodeEntries(specs, ranks)
  local entries = {}
  for _, spec in ipairs(specs) do
    for _, talent in ipairs(spec.talents) do
      local rank = rankOf(ranks, talent.id)
      if rank > 0 and talent.node then
        entries[#entries + 1] = { nodeID = talent.node, ranksPurchased = rank }
      end
    end
  end
  return entries
end
