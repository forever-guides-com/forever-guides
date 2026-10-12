-- Legacy planner logic (no frames, no game calls): the plan against the current state of the character
-- (what a purchase would cost, which perk comes next) and the stored plans (one per character in the
-- character SavedVariables, named plans account wide). Nothing here buys anything: Legacy points cannot be
-- refunded, so the plan only ever tells what could be bought.
-- plan = a LegacyLogic build; state = the result of LegacyRead.read().
local _, ns = ...
local LL, U = ns.LegacyLogic, ns.U

local LP = {}
ns.LegacyPlan = LP

LP.MAX_PLANS = 30
LP.NAME_MAX = 40

ns.AddLocale("enUS", {
  ["legacy.plan.blocked.game"] = "%s: the game does not allow this purchase yet.",
})

ns.AddLocale("deDE", {
  ["legacy.plan.blocked.game"] = "%s: das Spiel erlaubt diesen Kauf noch nicht.",
})

local function treesOf()
  return ns.Data.LegacyTrees.trees
end

local function rankIn(build, key)
  local rank = tonumber(build and build.ranks and build.ranks[key])
  if not rank or rank ~= rank or rank < 1 then
    return 0
  end
  return math.floor(rank)
end

-- Compare ---------------------------------------------------------------------------------------

-- What the plan would change in the game. Returns
--   buy   = { { key, tree, from, to, cost } } perks whose planned rank is above the current rank
--   over  = { { key, tree, have, plan } }     perks that are already higher in the game than planned
--   cost  = points the purchases need, free = free points (nil when unknown), short = points missing (nil
--   when the free points are unknown), same = nothing to buy and nothing above the plan, unknown = keys of
--   perks the state could not read (they are left out of buy and over).
-- Perks come in tree order, then by column and row. The game cannot take points back, so "over" is only
-- reported, never acted on.
function LP.compare(plan, state)
  local out = { buy = {}, over = {}, unknown = {}, cost = 0, free = state and state.free or nil }
  local known = state and state.nodes
  for _, tree in ipairs(treesOf()) do
    for _, perk in ipairs(LL.perksOf(tree.tree)) do
      local have = rankIn(state and state.build, perk.key)
      local want = math.min(perk.ranks, rankIn(plan, perk.key))
      if known and not known[perk.node] then
        out.unknown[#out.unknown + 1] = perk.key
      elseif want > have then
        out.buy[#out.buy + 1] = { key = perk.key, tree = tree.tree, from = have, to = want, cost = want - have }
        out.cost = out.cost + want - have
      elseif want < have then
        out.over[#out.over + 1] = { key = perk.key, tree = tree.tree, have = have, plan = want }
      end
    end
  end
  if out.free then
    out.short = math.max(0, out.cost - out.free)
  end
  out.same = #out.buy == 0 and #out.over == 0 and #out.unknown == 0
  return out
end

-- The perks whose edge leads to a perk: { [targetKey] = { sourcePerk, ... } }.
local function sourcesIndex()
  local D = ns.Data.LegacyTrees
  local index = {}
  for _, tree in ipairs(D.trees) do
    for _, perk in ipairs(tree.nodes) do
      for _, node in ipairs(perk.unlocks) do
        local target = D.byNode[node]
        if target and target.key then
          index[target.key] = index[target.key] or {}
          table.insert(index[target.key], perk)
        end
      end
    end
  end
  return index
end

-- The perk table and its tree id by key.
local function perkOf(key)
  for _, tree in ipairs(treesOf()) do
    for _, perk in ipairs(tree.nodes) do
      if perk.key == key then
        return perk, tree
      end
    end
  end
end

-- What a perk needs before it opens, measured on a build:
--   gate  = { need, have, met }  points in its tree from perks with a lower gate (the order of purchases in the
--                                game is reproducible this way, see LegacyLogic.validate)
--   edges = { { other, need, have, met } } the perks whose edge leads here and the rank they need
--   met   = everything is met
-- Returns nil for a key that is no perk.
function LP.requirements(build, key, rules)
  local perk, tree = perkOf(key)
  if not perk then
    return nil
  end
  rules = LL.rules(rules)
  local need = LL.gateOf(perk, rules)
  local have = 0
  for _, other in ipairs(tree.nodes) do
    if LL.gateOf(other, rules) < need then
      have = have + math.min(other.ranks, rankIn(build, other.key))
    end
  end
  local out = { gate = { need = need, have = have, met = have >= need }, edges = {} }
  out.met = out.gate.met
  for _, source in ipairs(sourcesIndex()[key] or {}) do
    local want = rules.edgeStrict and source.ranks or 1
    local got = rankIn(build, source.key)
    out.edges[#out.edges + 1] = { other = source.key, need = want, have = got, met = got >= want }
    out.met = out.met and got >= want
  end
  return out
end

-- How a perk stands in the plan: "warn" (points on a perk whose requirements are not met), "maxed", "partly",
-- "available" or "locked" (no points, requirements not met). Nil for a key that is no perk.
function LP.status(build, key, rules)
  local perk = perkOf(key)
  if not perk then
    return nil
  end
  local rank = math.min(perk.ranks, rankIn(build, key))
  local met = LP.requirements(build, key, rules).met
  if rank > 0 and not met then
    return "warn"
  elseif rank >= perk.ranks then
    return "maxed"
  elseif rank > 0 then
    return "partly"
  end
  return met and "available" or "locked"
end

-- Why a perk cannot be bought in the state right now, as a warning table for LegacyLogic.warningText, or nil
-- when it can. The game's own answer (canPurchaseRank) wins over the rules when the state carries it.
local function blockedBy(perk, treeId, state, rules, sources, spentInTree)
  local gate = LL.gateOf(perk, rules)
  if spentInTree < gate then
    return {
      code = "gate",
      key = perk.key,
      tree = treeId,
      have = spentInTree,
      need = gate,
      textKey = "legacy.warn.gate",
    }
  end
  for _, source in ipairs(sources[perk.key] or {}) do
    local need = rules.edgeStrict and source.ranks or 1
    local have = rankIn(state.build, source.key)
    if have < need then
      return {
        code = "edge",
        key = perk.key,
        other = source.key,
        have = have,
        need = need,
        textKey = rules.edgeStrict and "legacy.warn.edge.full" or "legacy.warn.edge",
      }
    end
  end
  local node = state.nodes and state.nodes[perk.node]
  if node and node.canBuy == false then
    return { code = "game", key = perk.key, textKey = "legacy.plan.blocked.game" }
  end
end

-- The next sensible purchase of the plan in the current state: the first perk, by column (lowest gate first),
-- tree and row, whose planned rank is above its current rank and that the state allows right now.
-- Returns { key, tree, from, to } for one more rank, or nil plus a reason:
--   "done"     nothing to buy (the plan is reached or below the state)
--   "nopoints" no free point left
--   "blocked"  perks wait for a gate or an edge; the third result lists them as warning tables
function LP.nextPurchase(plan, state, rules)
  rules = LL.rules(rules)
  local cmp = LP.compare(plan, state)
  if #cmp.buy == 0 then
    return nil, "done"
  end
  local free = cmp.free or LL.unspentLimit(state.build, rules).total
  if free <= 0 then
    return nil, "nopoints"
  end
  local byKey = {}
  for _, tree in ipairs(treesOf()) do
    for _, perk in ipairs(tree.nodes) do
      byKey[perk.key] = perk
    end
  end
  local sources = sourcesIndex()
  local spent = LL.spent(state.build).byTree
  local order = {}
  for index, item in ipairs(cmp.buy) do
    order[index] = { item = item, perk = byKey[item.key], index = index }
    order[index].gate = LL.gateOf(order[index].perk, rules)
  end
  table.sort(order, function(a, b)
    if a.gate ~= b.gate then
      return a.gate < b.gate
    end
    return a.index < b.index
  end)
  local blocked = {}
  for _, entry in ipairs(order) do
    local treeId = entry.item.tree
    local inTree = state.trees and state.trees[treeId] and state.trees[treeId].spent or spent[treeId]
    local why = blockedBy(entry.perk, treeId, state, rules, sources, inTree)
    if not why then
      return { key = entry.item.key, tree = treeId, from = entry.item.from, to = entry.item.from + 1 }
    end
    blocked[#blocked + 1] = why
  end
  return nil, "blocked", blocked
end

-- Stored plans ------------------------------------------------------------------------------------

local function accountRoot()
  local db = ns.db
  if type(db) ~= "table" then
    return nil
  end
  if type(db.legacy) ~= "table" then
    db.legacy = {}
  end
  if type(db.legacy.plans) ~= "table" then
    db.legacy.plans = {}
  end
  return db.legacy
end

local function charRoot()
  local db = ns.charDB
  if type(db) ~= "table" then
    return nil
  end
  if type(db.legacy) ~= "table" then
    db.legacy = {}
  end
  if type(db.legacy.ranks) ~= "table" then
    db.legacy.ranks = {}
  end
  return db.legacy
end

-- A build from stored ranks: only known perks, ranks clamped, everything else dropped.
function LP.clean(raw)
  local build = LL.new()
  local ranks = type(raw) == "table" and (type(raw.ranks) == "table" and raw.ranks or raw) or {}
  for key, rank in pairs(ranks) do
    if type(key) == "string" then
      LL.setRank(build, key, rank)
    end
  end
  return build
end

-- The plan of this character (an empty plan before the first save).
function LP.loadChar()
  local root = charRoot()
  return LP.clean(root and root.ranks)
end

function LP.saveChar(build)
  local root = charRoot()
  if root then
    root.ranks = LP.clean(build).ranks
  end
end

-- Plan names: control characters and "|" (colour escapes) dropped, white space squeezed, at most NAME_MAX
-- characters. Returns the name or nil when nothing is left.
function LP.cleanName(name)
  name = tostring(name or ""):gsub("[%c|]", " "):gsub("%s+", " ")
  name = U.trim(name)
  local chars = 0
  for index in name:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
    chars = chars + 1
    if chars > LP.NAME_MAX then
      name = name:sub(1, index - 1)
      break
    end
  end
  name = U.trim(name)
  return name ~= "" and name or nil
end

local function find(root, name)
  local wanted = name:lower()
  for i, entry in ipairs(root.plans) do
    if type(entry) == "table" and type(entry.name) == "string" and entry.name:lower() == wanted then
      return i, entry
    end
  end
end

-- { { name, total, updated } } sorted by name; entries that are no plans are skipped.
function LP.list()
  local root = accountRoot()
  local out = {}
  for _, entry in ipairs(root and root.plans or {}) do
    if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
      out[#out + 1] = {
        name = entry.name,
        total = LL.spent(LP.clean(entry)).total,
        updated = tonumber(entry.updated) or 0,
      }
    end
  end
  table.sort(out, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  return out
end

function LP.get(name)
  local root = accountRoot()
  name = LP.cleanName(name)
  if not (root and name) then
    return nil
  end
  local _, entry = find(root, name)
  return entry and LP.clean(entry) or nil
end

-- Saves a copy of the build under a name. An existing name is only replaced with replace = true.
-- Returns true, the stored name; or false and "name" (no usable name), "exists", "full" or "nodb".
function LP.save(name, build, replace)
  local root = accountRoot()
  if not root then
    return false, "nodb"
  end
  name = LP.cleanName(name)
  if not name then
    return false, "name"
  end
  local index = find(root, name)
  if index and not replace then
    return false, "exists"
  end
  if not index and #root.plans >= LP.MAX_PLANS then
    return false, "full"
  end
  local entry = { name = name, ranks = LP.clean(build).ranks, updated = U.now() }
  if index then
    root.plans[index] = entry
  else
    root.plans[#root.plans + 1] = entry
  end
  return true, name
end

function LP.exists(name)
  local root = accountRoot()
  name = LP.cleanName(name)
  return name ~= nil and root ~= nil and find(root, name) ~= nil
end

function LP.delete(name)
  local root = accountRoot()
  name = LP.cleanName(name)
  local index = name and root and find(root, name)
  if index then
    table.remove(root.plans, index)
    return true
  end
  return false
end
