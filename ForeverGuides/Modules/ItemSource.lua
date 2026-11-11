-- "Where does this drop": the way back from an item to the boss and the instance, built from the loot rows of the
-- instance data (boss.lo of every boss and inst.tl, the loot of an instance that no boss owns). No game API and no
-- stored state: the index is rebuilt from ns.Data.Instances on first use, so a data update needs nothing else.
-- Lines are for item tooltips (Modules/InventoryTooltip.lua appends them).
--
-- Rules: one line per instance, the bosses of that instance joined; an item that only sits in inst.tl gets the
-- instance with a note that no boss is known. A row marked pr (provisional) says so. A drop chance (r) is shown
-- only when the data carries one.
local _, ns = ...

local S = {}
ns.ItemSource = S

-- Instance lines in a tooltip, the rest is counted.
S.MAX_LINES = 3
-- Bosses named per instance line, the rest is counted.
S.MAX_BOSSES = 3

ns.AddLocale("enUS", {
  ["itemsource.header"] = "Drops from:",
  ["itemsource.line"] = "%s: %s",
  ["itemsource.noBoss"] = "no boss known",
  ["itemsource.more"] = "and %d more",
  ["itemsource.moreBosses"] = "+%d",
  ["itemsource.provisional"] = "unconfirmed",
  ["itemsource.rate"] = "%s%%",
})
ns.AddLocale("deDE", {
  ["itemsource.header"] = "Droppt bei:",
  ["itemsource.line"] = "%s: %s",
  ["itemsource.noBoss"] = "kein Boss bekannt",
  ["itemsource.more"] = "und %d weitere",
  ["itemsource.moreBosses"] = "+%d",
  ["itemsource.provisional"] = "unbestätigt",
  ["itemsource.rate"] = "%s %%",
})

local index

local function whole(v, min)
  return type(v) == "number" and v >= min and v == math.floor(v) and v or nil
end

local function text(field)
  local v = ns.T(field)
  return type(v) == "string" and v ~= "" and v or nil
end

-- One entry per item id and instance: { inst = instance table, bosses = { { name, pr, r } }, tlOnly = bool }.
local function add(map, id, inst, boss, row)
  local list = map[id]
  if not list then
    list = {}
    map[id] = list
  end
  local entry
  for _, e in ipairs(list) do
    if e.inst == inst then
      entry = e
      break
    end
  end
  if not entry then
    entry = { inst = inst, bosses = {} }
    list[#list + 1] = entry
  end
  if boss then
    for _, b in ipairs(entry.bosses) do
      if b.boss == boss then
        return
      end
    end
    entry.bosses[#entry.bosses + 1] = {
      boss = boss,
      pr = row.pr == 1 or row.pr == true,
      r = type(row.r) == "number" and row.r > 0 and row.r <= 100 and row.r or nil,
    }
  end
end

-- id -> list of entries, in the order of the data. Rows without a whole item id are skipped.
function S.Build(instances)
  local map = {}
  for _, inst in ipairs(type(instances) == "table" and instances or {}) do
    for _, boss in ipairs(type(inst.bo) == "table" and inst.bo or {}) do
      for _, row in ipairs(type(boss.lo) == "table" and boss.lo or {}) do
        local id = type(row) == "table" and whole(row.id or row.i, 1)
        if id then
          add(map, id, inst, boss, row)
        end
      end
    end
    for _, row in ipairs(type(inst.tl) == "table" and inst.tl or {}) do
      local id = type(row) == "table" and whole(row.id or row.i, 1)
      if id then
        add(map, id, inst, nil, row)
      end
    end
  end
  return map
end

-- Drops the index; the next lookup builds it again from the data.
function S.Reset()
  index = nil
end

local function ensure()
  if not index then
    index = S.Build(ns.Data and ns.Data.Instances)
  end
  return index
end

-- Entries of an item: { { instance = "name", bosses = { { name, pr, r } }, noBoss = bool } }, nil when the data
-- has no row for the item. An instance whose tl row has a boss row too is not marked noBoss.
function S.Rows(itemId)
  local id = whole(tonumber(itemId), 1)
  local list = id and ensure()[id]
  if not list then
    return nil
  end
  local out = {}
  for _, e in ipairs(list) do
    local row = { instance = text(e.inst.n) or tostring(e.inst.id or "?"), bosses = {}, noBoss = #e.bosses == 0 }
    for _, b in ipairs(e.bosses) do
      local name = text(b.boss.n)
      if name then
        row.bosses[#row.bosses + 1] = { name = name, pr = b.pr, r = b.r }
      end
    end
    row.noBoss = #row.bosses == 0
    out[#out + 1] = row
  end
  return out
end

local function percent(r)
  local shown = string.format("%.1f", r):gsub("%.0$", "")
  return string.format(ns.L["itemsource.rate"], shown)
end

local function bossText(row)
  if row.noBoss then
    return ns.L["itemsource.noBoss"]
  end
  local names, provisional = {}, true
  for i, b in ipairs(row.bosses) do
    provisional = provisional and b.pr
    if i <= S.MAX_BOSSES then
      local label = b.name
      if b.r then
        label = label .. " (" .. percent(b.r) .. ")"
      end
      names[#names + 1] = label
    end
  end
  local out = table.concat(names, ", ")
  if #row.bosses > S.MAX_BOSSES then
    out = out .. " " .. string.format(ns.L["itemsource.moreBosses"], #row.bosses - S.MAX_BOSSES)
  end
  if provisional then
    out = out .. " (" .. ns.L["itemsource.provisional"] .. ")"
  end
  return out
end

-- Tooltip lines for an item: the header first, then one line per instance, nil for an item without a row.
function S.Lines(itemId)
  local rows = S.Rows(itemId)
  if not rows then
    return nil
  end
  local lines = { ns.L["itemsource.header"] }
  for i, row in ipairs(rows) do
    if i > S.MAX_LINES then
      lines[#lines + 1] = string.format(ns.L["itemsource.more"], #rows - S.MAX_LINES)
      break
    end
    lines[#lines + 1] = string.format(ns.L["itemsource.line"], row.instance, bossText(row))
  end
  return lines
end

-- The setting that switches the block off in tooltips (settings.itemSource.tooltip = false).
function S.Enabled()
  local settings = type(ns.db) == "table" and ns.db.settings
  local s = type(settings) == "table" and settings.itemSource
  return not (type(s) == "table" and s.tooltip == false)
end
