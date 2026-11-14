-- Quest chains of the instances page, without any game API (the window is Modules/QuestChainWindow.lua,
-- the list Modules/QuestChainView.lua). Quest fields read here: id, n, f ("A", "H", "B" or nil = both),
-- l (quest level), rq or ml (minimum level), av (available from, chain aware), pre and nxt (quest ids),
-- pair (counterpart of the other faction), ch ({ line, i }), ac (access quest), dg (server tag 81 or 62 of a
-- direct quest), direct (false for a chain link), sn and sz (giver and zone), m, x, y (giver place), xp, mo,
-- step, head, pos (follow-up row of a chain), grp, var (parallel chains), preAny, excl, cls, rpt.
-- Today's data has no `av`.
local _, ns = ...

local QC = {}
ns.QuestChainLogic = QC

QC.MAX_STEPS = 20
QC.FACTIONS = { "A", "H", "B" }
QC.FILTERS = { "all", "A", "H", "B" }

local function whole(v, min)
  return type(v) == "number" and v >= min and v == math.floor(v) and v or nil
end

-- "A", "H" or "B"; a missing or unknown value means both factions.
function QC.Faction(q)
  local f = q and q.f
  return (f == "A" or f == "H") and f or "B"
end

function QC.Filter(value)
  for _, f in ipairs(QC.FILTERS) do
    if f == value then
      return value
    end
  end
  return "all"
end

local function idList(value)
  local out = {}
  for _, id in ipairs(type(value) == "table" and value or {}) do
    if whole(id, 1) then
      out[#out + 1] = id
    end
  end
  return out
end

-- Minimum level of the quest (`ml` wins over `rq`), nil when the data has none.
function QC.MinLevel(q)
  return whole(q.ml, 1) or whole(q.rq, 1)
end

-- Availability of one quest: { level, kind } with kind "min" (minimum level of the data), "chain" (the
-- generated `av`, which includes the prequests) or "hint" (only the quest level is known: not a rule, the
-- caller words it as a hint). Nil when the data has no level at all.
function QC.Availability(q)
  local av, min = whole(q.av, 1), QC.MinLevel(q)
  if av then
    return { level = av, kind = "chain" }
  elseif min then
    return { level = min, kind = "min" }
  end
  local l = whole(q.l, 1)
  if l then
    return { level = l, kind = "hint" }
  end
  return nil
end

-- True when the quest has a place a waypoint can point to.
function QC.HasPlace(q)
  return type(q.m) == "number" and type(q.x) == "number" and type(q.y) == "number"
end

-- Index of every quest of the data by id: { [id] = { quest, inst } }. The instance given first wins when
-- an id is listed twice (a quest shared by two instances). `instances` defaults to the data.
local function index(inst, instances)
  local byId = {}
  local function add(owner)
    for _, q in ipairs(owner.q or {}) do
      if whole(q.id, 1) and not byId[q.id] then
        byId[q.id] = { quest = q, inst = owner }
      end
    end
  end
  if inst then
    add(inst)
  end
  for _, other in ipairs(instances or (ns.Data and ns.Data.Instances) or {}) do
    if other ~= inst then
      add(other)
    end
  end
  return byId
end
QC.Index = index

-- Ids of the quests of one instance that lead on to another quest of the same list (named in its `pre`, or
-- through their own `nxt`), to tell a plain prerequisite from a quest of the dungeon.
local function leadsOn(quests)
  local listed, out = {}, {}
  for _, q in ipairs(quests) do
    listed[q.id or 0] = true
  end
  for _, q in ipairs(quests) do
    for _, id in ipairs(idList(q.pre)) do
      out[id] = true
    end
    for _, id in ipairs(idList(q.nxt)) do
      if listed[id] then
        out[q.id or 0] = true
      end
    end
  end
  return out
end

-- Direct dungeon quest: a row of the list. A follow-up step (`step`) is never one, it shows in the chain; `dg` is only
-- the server tag (81 dungeon, 62 raid), `direct = false` marks a chain link and `ac` an access quest. Without
-- any flag a quest is direct unless it only leads on to another quest of the list (a prerequisite).
function QC.IsDirect(q, leads)
  if q.step == true or q.direct == false then
    return false
  elseif q.dg or q.direct == true or q.ac == true then
    return true
  end
  return not (leads and leads[q.id or 0])
end

-- Builds the entry of one quest for a list or a step.
local function entry(q, owner, direct)
  local avail = QC.Availability(q)
  return {
    id = q.id,
    quest = q,
    inst = owner,
    faction = QC.Faction(q),
    level = whole(q.l, 1),
    minLevel = QC.MinLevel(q),
    avail = avail,
    xp = whole(q.xp, 0),
    gold = whole(q.mo, 0),
    giver = type(q.sn) == "string" and q.sn ~= "" and q.sn or nil,
    zone = q.sz,
    startItem = type(q.si) == "number" and q.si or nil,
    place = QC.HasPlace(q),
    direct = direct,
    access = q.ac == true,
    pair = whole(q.pair, 1),
    repeatable = q.rpt == true,
    class = type(q.cls) == "string" and q.cls ~= "" and q.cls or nil,
    grp = type(q.grp) == "string" and q.grp ~= "" and q.grp or nil,
    var = whole(q.var, 1),
    step = q.step == true,
    excl = idList(q.excl),
  }
end

-- Lower-case name without a leading article, so "The Hall of Thanes" equals "Hall of Thanes".
local function plain(s)
  if type(s) ~= "string" then
    return nil
  end
  s = s:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("^the ", ""):gsub("^die ", ""):gsub("^der ", "")
  return s ~= "" and s or nil
end

-- Whether the giver of a quest stands inside the instance: true, false (the zone is another place), nil when
-- the quest has no zone. The zone counts as inside when it is a name of the instance (en, de or an alias),
-- alone, followed by a part after a comma ("Hall of Thanes, Reliquary of Kings") or the common part of a
-- wing name (zone "Dire Maul" for "Dire Maul - East"). The derived fact of the quest (st "in" or "out",
-- tools/derive_quest_start.py) decides first.
function QC.StartsInside(inst, item)
  local st = item and item.quest and item.quest.st
  if st == "in" or st == "out" then
    return st == "in"
  end
  local zone = item and item.zone
  if type(zone) ~= "table" or not inst then
    return nil
  end
  local names = {}
  for _, v in ipairs({ inst.n and inst.n.en, inst.n and inst.n.de }) do
    names[#names + 1] = plain(v)
  end
  for _, v in ipairs(inst.al or {}) do
    names[#names + 1] = plain(v)
  end
  local seen
  for _, lang in ipairs({ "en", "de" }) do
    local z = plain(zone[lang])
    if z then
      seen = true
      local head = plain(z:match("^([^,]+)"))
      for _, name in ipairs(names) do
        if z == name or head == name or name:sub(1, #head + 3) == head .. " - " then
          return true
        end
      end
    end
  end
  if seen then
    return false
  end
  return nil
end

-- Ids a quest needs before it (`pre`, all of them, then `preAny`, one of them).
local function preIds(q)
  local out = idList(q.pre)
  for _, id in ipairs(idList(q.preAny)) do
    out[#out + 1] = id
  end
  return out
end

local LANE_ORDER = { faction = 1, var = 2, any = 3 }

-- The chain a quest belongs to, in reading order. It holds the prequests of the quest (`pre`, `preAny`, back to
-- the first one), the follow-up steps of its chain head (`step` rows reached through `nxt`) and, for a quest of
-- a group of parallel chains (`grp`), the chains of every head of the group.
-- opts.instances: all instances to look prequests up in (default the data); opts.byId: the index of them
-- (QC.Index), built once by a caller that asks for many chains.
-- Returns { steps, next, truncated, cycle, missing, availableFrom, partial, faction, chosen, before, after } where
--   steps          entries (see `entry`) plus `number` (position in the chain, restarts inside a branch),
--                  `chosen`, `external` (listed in another instance or in none: `inst` is that instance or
--                  nil), `missing` (the id is not in the data at all, the entry then only has `id`), `lane`
--                  ({ key, kind = "faction" | "var" | "any", faction, var, grp } or nil on the common part),
--                  `laneStart` (first step of a branch), `anyOf` (one of several that are enough for a later
--                  quest), `after` (a follow-up of the chosen quest, not a prequest of it)
--   next           entries of the successors (`nxt`) of the chosen quest that are not steps of the chain
--   truncated      the chain was longer than MAX_STEPS and was cut at the start
--   cycle          a prequest pointed back into the chain (that edge was ignored)
--   availableFrom  the highest minimum level on the prequests and the chosen quest, nil when none has one
--   partial        some of those has no minimum level or no quest data, so availableFrom may be too low
--   faction        "A", "H" or "B" of the whole chain: "B" when the steps differ or are neutral
--   chosen         the step of the chosen quest
--   before, after  number of prequests of the chosen quest and of the other follow-up steps in the chain
function QC.Chain(inst, quest, opts)
  opts = opts or {}
  local byId = opts.byId or index(inst, opts.instances)
  local out = {
    steps = {},
    next = {},
    truncated = false,
    cycle = false,
    missing = 0,
    partial = false,
    before = 0,
    after = 0,
  }
  if not quest then
    return out
  end

  local leads = leadsOn(inst and inst.q or {})
  local function isDirect(q, owner)
    return owner == inst and QC.IsDirect(q, leads)
  end

  local function resolve(id)
    local hit = byId[id]
    if hit then
      local e = entry(hit.quest, hit.inst, isDirect(hit.quest, hit.inst))
      e.external = hit.inst ~= inst
      e.pairQuest = e.pair and byId[e.pair] and byId[e.pair].quest or nil
      return e
    end
    return { id = id, missing = true, external = true, faction = "B", direct = false }
  end

  -- Post-order walk over `pre` and `preAny`: the prequests of a quest come before it. `onPath` guards against
  -- cycles, `done` against walking a quest twice when two branches share a prequest. `upstream[key]` tells a
  -- prequest of the chosen quest from a follow-up step.
  local ordered, onPath, done, upstream = {}, {}, {}, {}
  local function visit(q, depth, mark)
    local id = q.id
    local key = id or q
    if onPath[key] or done[key] then
      out.cycle = out.cycle or onPath[key] == true
      return
    end
    onPath[key] = true
    local pres = preIds(q)
    if depth < QC.MAX_STEPS then
      for _, pre in ipairs(pres) do
        local hit = byId[pre]
        if hit then
          visit(hit.quest, depth + 1, mark)
        elseif not done[pre] then
          done[pre] = true
          ordered[#ordered + 1] = { id = pre, missing = true }
          upstream[pre] = mark
        end
      end
    elseif #pres > 0 then
      out.truncated = true
    end
    onPath[key], done[key] = nil, true
    ordered[#ordered + 1] = q
    upstream[key] = mark
  end
  visit(quest, 1, true)

  -- Follow-up steps of the chain heads: the head of a step, the quest itself otherwise, every head of a group.
  local anchors = {}
  local function addAnchor(q)
    for _, a in ipairs(anchors) do
      if a == q then
        return
      end
    end
    anchors[#anchors + 1] = q
  end
  if quest.grp and inst then
    for _, q in ipairs(inst.q or {}) do
      if q.grp == quest.grp and q.step ~= true then
        addAnchor(q)
      end
    end
  end
  local head = quest.step == true and whole(quest.head, 1) and byId[quest.head]
  addAnchor(head and head.quest or quest)
  local forward, seen = {}, {}
  local function follow(q)
    if q.id then
      seen[q.id] = true
    end
    for _, id in ipairs(idList(q.nxt)) do
      local hit = byId[id]
      if hit and hit.quest.step == true and not seen[id] then
        forward[#forward + 1] = hit.quest
        follow(hit.quest)
      end
    end
  end
  for _, a in ipairs(anchors) do
    follow(a)
  end
  for _, list in ipairs({ anchors, forward }) do
    for _, q in ipairs(list) do
      visit(q, 1, false)
    end
  end

  if #ordered > QC.MAX_STEPS then
    out.truncated = true
    local cut = {}
    for i = #ordered - QC.MAX_STEPS + 1, #ordered do
      cut[#cut + 1] = ordered[i]
    end
    ordered = cut
  end

  local nodes, byNode = {}, {}
  for i, q in ipairs(ordered) do
    local step
    if q.missing then
      step = resolve(q.id)
    else
      local hit = q.id and byId[q.id]
      if hit and hit.quest == q then
        step = resolve(q.id)
      else
        step = entry(q, inst, isDirect(q, inst))
        step.external = false
      end
    end
    step.chosen = (q.id ~= nil and q.id == quest.id) or q == quest
    step.after = upstream[q.id or q] ~= true or nil
    step.order = i
    if step.excl and #step.excl > 0 then
      step.exclQuests = {}
      for _, id in ipairs(step.excl) do
        if byId[id] then
          step.exclQuests[#step.exclQuests + 1] = byId[id].quest
        end
      end
    end
    nodes[i] = step
    if step.id then
      byNode[step.id] = step
    end
  end

  -- Stage: the longest way from a first quest (over the quests of this chain only).
  local onStack = {}
  local function stage(step)
    if step.stage then
      return step.stage
    end
    if onStack[step] then
      return 0
    end
    onStack[step] = true
    local top = 0
    for _, id in ipairs(step.quest and preIds(step.quest) or {}) do
      local pre = byNode[id]
      if pre and pre ~= step then
        top = math.max(top, stage(pre))
      end
    end
    onStack[step] = nil
    step.stage = top + 1
    return step.stage
  end
  -- Branches by faction only where an Alliance and a Horde quest stand at the same stage.
  local split, factionsAt = false, {}
  for _, step in ipairs(nodes) do
    local s = stage(step)
    local at = factionsAt[s] or {}
    factionsAt[s] = at
    if step.faction ~= "B" and not step.missing then
      at[step.faction] = true
      split = split or (at.A and at.H) or false
    end
  end

  -- Alternatives: the quests named in a `preAny` of a quest of the chain.
  local altOf = {}
  for _, step in ipairs(nodes) do
    local ids = step.quest and idList(step.quest.preAny) or {}
    if #ids > 1 then
      for _, id in ipairs(ids) do
        local alt = byNode[id]
        if alt and not altOf[alt] then
          altOf[alt] = step.id
        end
      end
    end
  end

  local sorted = {}
  for i, step in ipairs(nodes) do
    sorted[i] = step
  end
  table.sort(sorted, function(a, b)
    if a.stage ~= b.stage then
      return a.stage < b.stage
    end
    return a.order < b.order
  end)
  for _, step in ipairs(sorted) do
    local lane
    if step.grp and step.var then
      lane = { key = "var" .. step.var, kind = "var", var = step.var, grp = step.grp }
    elseif split and (step.faction == "A" or step.faction == "H") and not step.missing then
      lane = { key = step.faction, kind = "faction", faction = step.faction }
    elseif altOf[step] then
      lane = { key = "any" .. altOf[step], kind = "any" }
      step.anyOf = true
    else
      -- A step behind exactly one branch stays in it, a step behind several or behind the common part does not.
      local common
      for _, id in ipairs(step.quest and preIds(step.quest) or {}) do
        local pre = byNode[id]
        if pre and pre ~= step then
          local key = pre.lane and pre.lane.key or false
          if common == nil then
            common = key
          elseif common ~= key then
            common = false
          end
          if key and key == common and key ~= "any" .. tostring(step.id) then
            lane = pre.lane
          end
        end
      end
      if not common then
        lane = nil
      end
    end
    step.lane = lane
  end

  -- Reading order: the common start, each branch, the common rest (quests behind a branch).
  local function behindLane(step, depth)
    if depth > QC.MAX_STEPS then
      return false
    end
    for _, id in ipairs(step.quest and preIds(step.quest) or {}) do
      local pre = byNode[id]
      if pre and pre ~= step and (pre.lane or behindLane(pre, depth + 1)) then
        return true
      end
    end
    return false
  end
  local start, lanes, rest, groups = {}, {}, {}, {}
  for _, step in ipairs(sorted) do
    if step.lane then
      local group = lanes[step.lane.key]
      if not group then
        group = { lane = step.lane, steps = {} }
        lanes[step.lane.key] = group
        groups[#groups + 1] = group
      end
      group.steps[#group.steps + 1] = step
    elseif behindLane(step, 1) then
      rest[#rest + 1] = step
    else
      start[#start + 1] = step
    end
  end
  local function rank(lane)
    return lane.var or (lane.faction == "H" and 2 or 1)
  end
  table.sort(groups, function(a, b)
    local ka, kb = LANE_ORDER[a.lane.kind], LANE_ORDER[b.lane.kind]
    if ka ~= kb then
      return ka < kb
    end
    if rank(a.lane) ~= rank(b.lane) then
      return rank(a.lane) < rank(b.lane)
    end
    return a.lane.key < b.lane.key
  end)

  local n = 0
  for _, step in ipairs(start) do
    n = n + 1
    step.number = n
    out.steps[#out.steps + 1] = step
  end
  local base, reach = n, n
  for _, group in ipairs(groups) do
    n = base
    for i, step in ipairs(group.steps) do
      n = n + 1
      step.number = n
      step.laneStart = i == 1 or nil
      out.steps[#out.steps + 1] = step
    end
    reach = math.max(reach, n)
  end
  n = reach
  for _, step in ipairs(rest) do
    n = n + 1
    step.number = n
    out.steps[#out.steps + 1] = step
  end

  local factions, highest = {}, nil
  for _, step in ipairs(out.steps) do
    if step.chosen then
      out.chosen = step
    end
    if step.missing then
      out.missing = out.missing + 1
    else
      factions[step.faction] = true
    end
    if not step.after then
      if step.missing or not step.minLevel then
        out.partial = true
      else
        highest = math.max(highest or 0, step.minLevel)
      end
      if not step.chosen then
        out.before = out.before + 1
      end
    else
      out.after = out.after + 1
    end
  end
  out.availableFrom = highest

  local count, only = 0, nil
  for f in pairs(factions) do
    count, only = count + 1, f
  end
  out.faction = (count == 1 and only) or "B"

  for _, id in ipairs(idList(quest.nxt)) do
    if not byNode[id] then
      out.next[#out.next + 1] = resolve(id)
    end
  end
  return out
end

-- Entries of the quests of an instance for a list, sorted by quest level and name.
-- `quests` is the list to show (for example R.Quests(inst, faction), merged), `inst` gives the ids of the
-- prerequisites. Returns { entries, byFaction = { A = {...}, H = {...}, B = {...} }, counts }.
function QC.Entries(inst, quests)
  local leads = leadsOn(inst and inst.q or {})
  local entries = {}
  for _, q in ipairs(quests or {}) do
    local e = entry(q, inst, QC.IsDirect(q, leads))
    e.name = ns.T and ns.T(q.n) or (q.n and (q.n.en or q.n.de)) or ""
    entries[#entries + 1] = e
  end
  table.sort(entries, function(a, b)
    if (a.level or 0) ~= (b.level or 0) then
      return (a.level or 0) < (b.level or 0)
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return (a.id or 0) < (b.id or 0)
  end)

  -- A step stands in the row of its head (`owner`). A step none of whose prerequisites is in the list (the data
  -- names a head that has no entry here) would vanish, so it becomes a row itself.
  local byId = {}
  for _, e in ipairs(entries) do
    if e.id then
      byId[e.id] = e
    end
  end
  local function firstListed(e)
    for _, id in ipairs(preIds(e.quest)) do
      if byId[id] and byId[id] ~= e then
        return byId[id]
      end
    end
  end
  for _, e in ipairs(entries) do
    if e.step and not firstListed(e) then
      e.direct = true
    end
  end
  for _, e in ipairs(entries) do
    if e.step and not e.direct then
      local cur = e
      for _ = 1, QC.MAX_STEPS do
        cur = firstListed(cur)
        if not cur or cur.direct then
          break
        end
      end
      e.owner = cur and cur.direct and cur.id or nil
    end
  end
  return entries
end

-- Groups per faction (Alliance, Horde, both, in this order, empty groups left out) for the filter "all", or
-- only the chosen faction. Each group has `direct` (the dungeon quests) and `pre` (prerequisites of other
-- quests), both sorted like the entries, and `count`.
-- Returns { groups = { { faction, direct, pre, count } }, total, shown, counts = { A, H, B } }.
function QC.Groups(entries, filter)
  filter = QC.Filter(filter)
  local by, counts = {}, { A = 0, H = 0, B = 0 }
  for _, f in ipairs(QC.FACTIONS) do
    by[f] = { faction = f, direct = {}, pre = {}, count = 0 }
  end
  for _, e in ipairs(entries) do
    counts[e.faction] = counts[e.faction] + 1
    if filter == "all" or filter == e.faction then
      local group = by[e.faction]
      local list = e.direct and group.direct or group.pre
      list[#list + 1] = e
      group.count = group.count + 1
    end
  end
  local groups, shown = {}, 0
  for _, f in ipairs(QC.FACTIONS) do
    if by[f].count > 0 then
      groups[#groups + 1] = by[f]
      shown = shown + by[f].count
    end
  end
  return { groups = groups, total = #entries, shown = shown, counts = counts }
end

-- Quests of the chain that the player can start at a given level: the number of steps whose minimum
-- level is known and above `level`. Used for the summary of the window ("2 steps still too high").
function QC.StepsAbove(chain, level)
  local n = 0
  for _, step in ipairs(chain.steps) do
    if step.minLevel and level and step.minLevel > level then
      n = n + 1
    end
  end
  return n
end

-- What a prerequisite or follow-up link of the detail panel points to: a quest of this instance ("select", the
-- list can show it) or of another one ("open", it opens the chain window). nil when the id is not in the data.
function QC.Reference(inst, byId, id)
  local hit = byId and byId[id]
  if not hit then
    return nil
  end
  local name = ns.T and ns.T(hit.quest.n)
  return {
    id = id,
    name = (name and name ~= "") and name or ("#" .. id),
    -- A chain link (direct = false) is no entry of the list, so it opens its chain window like a quest of another instance.
    kind = hit.inst == inst and hit.quest.direct ~= false and "select" or "open",
    quest = hit.quest,
    inst = hit.inst,
  }
end
