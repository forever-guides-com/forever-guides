-- Items of one instance, grouped for the Items tab (Modules/InstanceItemsView.lua). No game API:
-- the caller hands in the quest rewards and the captured loot, so every rule here runs in the tests.
-- Sources, in the order of a group: boss loot from the data (boss.lo), loot the player captured
-- (ns.LootCapture) and quest rewards. Groups follow the boss order of the Bosses tab, then the captured
-- loot that fits no boss, then the quests.
--
-- boss.lo = { { id = itemId, n = "name" or { de, en }, q = quality 0-7, r = drop chance in percent } }
-- (`i` is read as `id` too). Format: docs/INSTANZ-EXPORT-FORMAT.md.
local _, ns = ...

local IL = {}
ns.InstanceItemsLogic = IL

IL.VIEWS = { "boss", "all" }
IL.SORTS = { "boss", "item" }

function IL.View(value)
  return value == "all" and "all" or "boss"
end

function IL.Sort(value)
  return value == "item" and "item" or "boss"
end

local function whole(v, min)
  return type(v) == "number" and v >= min and v == math.floor(v) and v or nil
end

-- Name comparison key: lower case, no spaces and no punctuation.
local function key(text)
  return (tostring(text or ""):lower():gsub("[%s%p]+", ""))
end

local function nameKeys(names)
  local out = {}
  for _, v in pairs(type(names) == "table" and names or { names }) do
    local k = type(v) == "string" and key(v) or ""
    if k ~= "" then
      out[k] = true
    end
  end
  return out
end

local function anyShared(a, b)
  for k in pairs(a) do
    if b[k] then
      return true
    end
  end
  return false
end

local function dataItems(boss)
  local out, seen = {}, {}
  for _, e in ipairs(type(boss.lo) == "table" and boss.lo or {}) do
    local id = type(e) == "table" and whole(e.id or e.i, 1)
    if id and not seen[id] then
      seen[id] = true
      local q = whole(e.q, 0)
      out[#out + 1] = {
        id = id,
        src = "data",
        name = ns.T(e.n),
        q = q and math.min(q, 7) or nil,
        rate = type(e.r) == "number" and e.r >= 0 and e.r <= 100 and e.r or nil,
      }
    end
  end
  return out
end

-- How a captured source belongs to the instance: "name" (its instance name is ours), "id" (same
-- instance id), "shared" (the id is shared with other instances, like the Dire Maul wings) or nil.
local function claim(inst, e, instances)
  local want = key(e.instance)
  if nameKeys(inst.n)[want] then
    return "name"
  end
  if not (inst.id and e.instanceId == inst.id) then
    return nil
  end
  local shared = false
  for _, other in ipairs(instances) do
    if other ~= inst and other.id == inst.id then
      shared = true
      if nameKeys(other.n)[want] then
        return nil
      end
    end
  end
  return shared and "shared" or "id"
end

-- The boss of a captured source: by encounter id (a boss `eid` in the data, else the confirmed
-- encounter name), then by name.
local function bossFor(bosses, e, encounterNames)
  if e.eid then
    local keys = nameKeys(encounterNames and encounterNames(e.eid))
    for _, b in ipairs(bosses) do
      if b.boss.eid == e.eid or anyShared(b.keys, keys) then
        return b
      end
    end
  end
  local mine = key(e.name)
  if mine ~= "" then
    for _, b in ipairs(bosses) do
      if b.keys[mine] then
        return b
      end
    end
  end
end

local function sortedIds(items)
  local ids = {}
  for id in pairs(items) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

-- Adds what one captured source dropped to a group. Items the data knows get the capture numbers,
-- new ones are collected in group.fresh and appended last.
local function takeCaptured(group, source, label)
  local e = source.e
  for _, id in ipairs(sortedIds(e.items or {})) do
    local c = e.items[id]
    local item = group.byId[id]
    if not item then
      item = { id = id, src = "captured", name = c.name, q = c.q, source = label, group = group }
      group.byId[id] = item
      group.fresh[#group.fresh + 1] = item
    end
    item.q = item.q or c.q
    item.name = item.name or c.name
    local own = item.captured
    if not own then
      own = { drops = 0, kills = 0, seen = {} }
      item.captured = own
    end
    if not own.seen[source] then
      own.seen[source] = true
      own.kills = own.kills + (e.kills or 0)
    end
    own.drops = own.drops + (c.n or 0)
  end
end

-- opts: rewards (IV.Rewards entries), captured (LootCapture.Bosses() rows), encounterNames(eid) ->
-- { de, en } or nil, instances (all instances, to tell shared ids apart; default the data).
-- Returns { groups = { { id, kind = "boss"|"extra"|"quests", index?, boss?, items } }, total, first }.
function IL.Build(inst, opts)
  opts = opts or {}
  local instances = opts.instances or (ns.Data and ns.Data.Instances) or {}
  local groups, bosses = {}, {}
  for i, boss in ipairs(inst.bo or {}) do
    local group =
      { id = "b" .. i, kind = "boss", index = i, boss = boss, items = dataItems(boss), byId = {}, fresh = {} }
    for _, item in ipairs(group.items) do
      item.group = group
      group.byId[item.id] = item
    end
    groups[i] = group
    bosses[i] = { index = i, boss = boss, keys = nameKeys(boss.n) }
  end
  local extra = { id = "extra", kind = "extra", items = {}, byId = {}, fresh = {} }
  for _, source in ipairs(opts.captured or {}) do
    local how = type(source.e) == "table" and claim(inst, source.e, instances)
    if how then
      local b = bossFor(bosses, source.e, opts.encounterNames)
      local group = b and groups[b.index] or (how ~= "shared" and extra) or nil
      if group then
        takeCaptured(group, source, source.e.name)
      end
    end
  end
  groups[#groups + 1] = extra
  for _, group in ipairs(groups) do
    table.sort(group.fresh, function(a, b)
      if a.captured.drops ~= b.captured.drops then
        return a.captured.drops > b.captured.drops
      end
      return a.id < b.id
    end)
    for _, item in ipairs(group.fresh) do
      group.items[#group.items + 1] = item
    end
    group.fresh, group.byId = nil, nil
  end
  local out, total = {}, 0
  for _, group in ipairs(groups) do
    if group.kind == "boss" or #group.items > 0 then
      out[#out + 1] = group
    end
  end
  local quests = {}
  local quest = { id = "quests", kind = "quests", items = quests }
  for _, r in ipairs(opts.rewards or {}) do
    quests[#quests + 1] = {
      id = r.id,
      src = "quest",
      name = r.name,
      count = r.count,
      choice = r.choice,
      quests = r.quests,
      group = quest,
    }
  end
  if #quests > 0 then
    out[#out + 1] = quest
  end
  for _, group in ipairs(out) do
    total = total + #group.items
  end
  return { groups = out, total = total, first = out[1] and out[1].id or nil }
end

function IL.Find(model, id)
  for _, group in ipairs(model.groups) do
    if group.id == id then
      return group
    end
  end
end

-- Every item as { item, group }, one row per boss and item. "boss" keeps the group order, "item"
-- sorts by name. nameOf(item) gives the name to sort by (the client's name, else item.name).
function IL.Flat(model, sort, nameOf)
  local rows = {}
  for gi, group in ipairs(model.groups) do
    for ii, item in ipairs(group.items) do
      rows[#rows + 1] = { item = item, group = group, order = gi * 100000 + ii }
    end
  end
  if IL.Sort(sort) == "item" then
    for _, row in ipairs(rows) do
      row.sortName = (nameOf and nameOf(row.item) or row.item.name or ""):lower()
    end
    table.sort(rows, function(a, b)
      if a.sortName ~= b.sortName then
        return a.sortName < b.sortName
      end
      return a.order < b.order
    end)
  end
  return rows
end
