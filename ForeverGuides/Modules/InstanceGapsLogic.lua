-- Data stand of one instance: what the shipped data does not hold yet. Pure, no game access.
-- The view (Modules/InstanceView.lua) turns the gaps into the badge, its tooltip and the Info text, so a missing
-- piece reads as "not recorded" and never as "does not exist".
local _, ns = ...

local G = {}
ns.InstanceGaps = G

-- Order of the tooltip lines.
G.KEYS = {
  "id",
  "name",
  "level",
  "levelRange",
  "entrance",
  "map",
  "bosses",
  "bossNames",
  "loot",
  "abilities",
  "questIds",
  "access",
}

local function countBosses(inst, missing)
  local count = 0
  for _, boss in ipairs(inst.bo or {}) do
    if missing(boss) then
      count = count + 1
    end
  end
  return count, #(inst.bo or {})
end

local function hasEntrance(inst)
  for _, e in ipairs(inst.ent or {}) do
    if e.m and e.x and e.y then
      return true
    end
  end
  return false
end

local function hasMap(inst)
  local maps = ns.Data and ns.Data.DungeonAssets and ns.Data.DungeonAssets.maps
  local map = maps and inst.n and maps[inst.n.en]
  return map ~= nil and map.floors ~= nil and #map.floors > 0
end

local function hasAccess(inst)
  local list = ns.Data and ns.Data.Access and ns.Data.Access[ns.RefLogic.InstanceSlug(inst)]
  return #ns.AccessLogic.Conditions(list) > 0
end

-- A quest without a quest ID is weakly confirmed: rewards, experience and chain links cannot be matched.
function G.QuestWeak(q)
  return q.id == nil
end

-- Gaps of an instance as { key, count?, total? } in G.KEYS order. Bosses and quests are counted, the rest is
-- present or missing.
function G.Of(inst)
  local out = {}
  local function add(key, count, total)
    out[#out + 1] = { key = key, count = count, total = total }
  end
  if inst.id == nil then
    add("id")
  end
  if not (inst.n and inst.n.de) then
    add("name")
  end
  if inst.lv == nil then
    add(inst.rl == nil and "level" or "levelRange")
  end
  if not hasEntrance(inst) then
    add("entrance")
  end
  if not hasMap(inst) then
    add("map")
  end
  local bosses = #(inst.bo or {})
  if bosses == 0 then
    add("bosses")
  else
    local noDe, total = countBosses(inst, function(b)
      return not (b.n and b.n.de)
    end)
    if noDe > 0 then
      add("bossNames", noDe, total)
    end
    local noLoot = countBosses(inst, function(b)
      return b.lo == nil
    end)
    if noLoot > 0 then
      add("loot", noLoot, total)
    end
    local noAbility = countBosses(inst, function(b)
      return b.ab == nil
    end)
    if noAbility > 0 then
      add("abilities", noAbility, total)
    end
  end
  local weak = 0
  for _, q in ipairs(inst.q or {}) do
    if G.QuestWeak(q) then
      weak = weak + 1
    end
  end
  if weak > 0 then
    add("questIds", weak, #inst.q)
  end
  if not hasAccess(inst) then
    add("access")
  end
  return out
end

-- True when the access list of the instance holds at least one valid condition.
G.HasAccess = hasAccess
