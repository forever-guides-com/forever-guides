-- What the statistics pages show: periods, rows of the kill and use lists, filters, sort, search, shares, bar widths,
-- day series and the overview numbers. Pure, no game calls: the day, the clock and the texts of items and keys come
-- from outside. Account totals are formed while reading and never stored.
--
-- Kills have the detail (xp, zones, type, level) only in the totals. In a period the count comes from the day table
-- (or the session) and the detail from the totals of the same monster: a monster counts in its main zone, and xp is
-- not known (nil). The confirmed part of a use in a period is estimated from the share of its totals (`estimated`).
local _, ns = ...

local L = {}
ns.StatsLogic = L

local Store, Cat = ns.StatsStore, ns.StatsCategories

L.PERIODS = { "session", "today", "d7", "d30", "d90", "total" }
L.VIEWS = { kills = { "monster", "zone", "type", "level" }, uses = { "item", "category" } }
L.SORTS = { kills = { "name", "count", "last", "xp", "zone" }, uses = { "name", "count", "last", "category" } }
L.UNKNOWN = "stats.unknown"
L.SESSION_GAP = Store.SESSION_GAP

local SPAN = { today = 1, d7 = 7, d30 = 30, d90 = 90 }
local DEFAULT_SORT = { name = false, count = true, last = true, xp = true, zone = false, category = false }
local UNKNOWN_ZONE = 0

local FOLD = { ["ä"] = "a", ["Ä"] = "a", ["ö"] = "o", ["Ö"] = "o", ["ü"] = "u", ["Ü"] = "u", ["ß"] = "ss" }

-- Case and umlauts folded for the search and the name sort.
function L.Fold(value)
  return (tostring(value or ""):gsub("[\195][\132\164\150\182\156\188\159]", FOLD):lower())
end

local function trimmed(query)
  return (L.Fold(query):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Plain folded substring test, an empty query matches everything.
function L.Match(value, query)
  local q = trimmed(query)
  return q == "" or L.Fold(value):find(q, 1, true) ~= nil
end

-- Periods ---------------------------------------------------------------------------------------------------------------

-- The periods that are complete for a retention in days: a longer one than the data is kept for is left out.
function L.Periods(keepDays)
  local keep = Store.KeepDays(keepDays)
  local out = {}
  for _, period in ipairs(L.PERIODS) do
    if not SPAN[period] or SPAN[period] <= keep then
      out[#out + 1] = period
    end
  end
  return out
end

local function normalPeriod(period)
  return (period == "session" or SPAN[period]) and period or "total"
end

-- The characters to read: all of them, or the one of the key. A session counts only for characters that played
-- within the session gap of opts.now (when given).
local function scopeChars(db, opts)
  local out = {}
  if type(db) ~= "table" or type(db.chars) ~= "table" then
    return out
  end
  local scope = opts.scope
  for key, char in pairs(db.chars) do
    if scope == nil or scope == "all" or scope == key then
      local live = opts.period ~= "session" or not opts.now or (char.sess.at > 0 and opts.now - char.sess.at <= L.SESSION_GAP)
      if live then
        out[#out + 1] = { key = key, char = char }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.key < b.key
  end)
  return out
end

-- The characters for the "Zeigt" control: { key, name, realm, class, last }, the most recent first.
function L.Characters(db)
  local out = {}
  for key, char in pairs(type(db) == "table" and db.chars or {}) do
    out[#out + 1] = { key = key, name = char.name, realm = char.realm, class = char.class, last = char.last }
  end
  table.sort(out, function(a, b)
    if a.last ~= b.last then
      return a.last > b.last
    end
    return a.key < b.key
  end)
  return out
end

-- id -> count of one character in a period.
local function periodCounts(char, domain, period, today)
  local block = char[domain]
  if period == "total" then
    local out = {}
    for id, entry in pairs(block.tot) do
      out[id] = entry.n
    end
    return out
  end
  if period == "session" then
    return char.sess[domain]
  end
  local out = {}
  if today then
    for day = today - SPAN[period] + 1, today do
      for id, n in pairs(block.day[day] or {}) do
        out[id] = (out[id] or 0) + n
      end
    end
  end
  return out
end

local function mainZone(entry)
  local best, bestN
  for zone, n in pairs(entry.z or {}) do
    if not bestN or n > bestN or (n == bestN and (best == UNKNOWN_ZONE or (zone ~= UNKNOWN_ZONE and zone < best))) then
      best, bestN = zone, n
    end
  end
  return best or UNKNOWN_ZONE
end

-- One aggregate per monster or item over the characters of the scope.
local function collect(db, domain, opts)
  local period = opts.period
  local aggs = {}
  for _, item in ipairs(scopeChars(db, opts)) do
    local tot = item.char[domain].tot
    for id, n in pairs(periodCounts(item.char, domain, period, opts.today)) do
      local agg = aggs[id]
      if not agg then
        agg = { id = id, n = 0, last = 0, z = {}, conf = 0, xp = period == "total" and 0 or nil, tlast = -1 }
        aggs[id] = agg
      end
      agg.n = agg.n + n
      local entry = tot[id]
      if entry then
        agg.last = math.max(agg.last, entry.last or 0)
        local newest = (entry.last or 0) >= agg.tlast
        if newest then
          agg.tlast = entry.last or 0
          agg.ty, agg.cl, agg.cat = entry.ty or agg.ty, entry.cl or agg.cl, entry.cat or agg.cat
        end
        if domain == "kills" then
          if agg.xp then
            agg.xp = agg.xp + (entry.xp or 0)
          end
          if entry.lv then
            agg.lv = agg.lv and { math.min(agg.lv[1], entry.lv[1]), math.max(agg.lv[2], entry.lv[2]) } or { entry.lv[1], entry.lv[2] }
          end
          if period == "total" then
            local known = 0
            for zone, zn in pairs(entry.z or {}) do
              agg.z[zone] = (agg.z[zone] or 0) + zn
              known = known + zn
            end
            if entry.n > known then
              agg.z[UNKNOWN_ZONE] = (agg.z[UNKNOWN_ZONE] or 0) + entry.n - known
            end
          else
            local zone = mainZone(entry)
            agg.z[zone] = (agg.z[zone] or 0) + n
          end
        else
          local confirmed = entry.n - (entry.g or 0)
          agg.conf = agg.conf + (period == "total" and confirmed or math.floor(n * confirmed / entry.n + 0.5))
        end
      elseif domain == "kills" then
        agg.z[UNKNOWN_ZONE] = (agg.z[UNKNOWN_ZONE] or 0) + n
      end
    end
  end
  return aggs
end

local function levelKey(agg)
  return agg.lv and agg.lv[2] or 0
end

-- Rows ------------------------------------------------------------------------------------------------------------------

local function typeKey(agg)
  return agg.ty or 0
end

-- The units a kill row is built from: one per monster, or one per monster and zone when a zone filter or the zone view
-- needs the split. Returns the units that pass the type and level filter.
local function killUnits(aggs, view, f)
  local split = view == "zone" or f.zone ~= nil
  local units = {}
  for _, agg in pairs(aggs) do
    if (f.type == nil or typeKey(agg) == f.type) and (f.level == nil or levelKey(agg) == f.level) then
      if split then
        for zone, n in pairs(agg.z) do
          if f.zone == nil or f.zone == zone then
            local xp = agg.xp and agg.n > 0 and math.floor(agg.xp * n / agg.n + 0.5) or nil
            units[#units + 1] = { agg = agg, zone = zone, n = n, xp = xp }
          end
        end
      else
        units[#units + 1] = { agg = agg, zone = mainZone(agg), n = agg.n, xp = agg.xp }
      end
    end
  end
  return units
end

local function newRow(key, n)
  return { key = key, n = n, last = 0, mobs = 0 }
end

local function killRows(db, aggs, view, f)
  local rows, by = {}, {}
  for _, unit in ipairs(killUnits(aggs, view, f)) do
    local agg = unit.agg
    local key
    if view == "monster" then
      key = agg.id
    elseif view == "zone" then
      key = unit.zone
    elseif view == "type" then
      key = typeKey(agg)
    else
      key = levelKey(agg)
    end
    local row = by[key]
    if not row then
      row = newRow(key, 0)
      by[key] = row
      rows[#rows + 1] = row
      row.xp = unit.xp and 0 or nil
      if view == "monster" then
        row.name, row.zone, row.ty, row.cl, row.lv = db.names[agg.id], unit.zone, agg.ty, agg.cl, agg.lv
      elseif view == "zone" then
        row.name = unit.zone ~= UNKNOWN_ZONE and db.names[unit.zone] or nil
      end
      row.labelKey = (key == 0 and view ~= "monster" and L.UNKNOWN) or (view == "type" and "stats.type." .. key) or nil
      if view == "zone" and unit.zone ~= UNKNOWN_ZONE and not row.name then
        row.labelKey = L.UNKNOWN
      end
    end
    row.n = row.n + unit.n
    row.last = math.max(row.last, agg.last)
    row.mobs = row.mobs + 1
    if row.xp then
      row.xp = row.xp + (unit.xp or 0)
    end
  end
  return rows
end

local function useRows(aggs, view, f, opts)
  local rows, by = {}, {}
  for _, agg in pairs(aggs) do
    local cat = agg.cat or Cat.OTHER
    local n = f.confirmed and agg.conf or agg.n
    if n > 0 and (f.category == nil or f.category == cat) then
      local key = view == "item" and agg.id or cat
      local row = by[key]
      if not row then
        row = newRow(key, 0)
        row.assumed, row.cat = 0, cat
        if view == "item" then
          row.name = opts.itemName and opts.itemName(agg.id) or nil
        else
          row.labelKey = Cat.Key(cat)
        end
        by[key] = row
        rows[#rows + 1] = row
      end
      row.n = row.n + n
      row.assumed = row.assumed + (f.confirmed and 0 or agg.n - agg.conf)
      row.last = math.max(row.last, agg.last)
      row.mobs = row.mobs + 1
      row.estimated = row.estimated or (opts.period ~= "total" and agg.n > agg.conf) or nil
    end
  end
  return rows
end

local function label(opts, row)
  if row.name then
    return row.name
  end
  local text = row.labelKey and opts.label and opts.label(row.labelKey)
  return text or row.labelKey or tostring(row.key)
end

local function zoneLabel(db, opts, zone)
  if zone and zone ~= UNKNOWN_ZONE and db.names[zone] then
    return db.names[zone]
  end
  return opts.label and opts.label(L.UNKNOWN) or L.UNKNOWN
end

local function sortKey(opts, row)
  if type(row.key) == "number" and row.name == nil and row.labelKey == nil then
    return string.format("%012d", row.key)
  end
  return L.Fold(label(opts, row))
end

local function sorter(db, opts, sort)
  local desc = opts.desc
  if desc == nil then
    desc = DEFAULT_SORT[sort]
  end
  local function value(row)
    if sort == "count" then
      return row.n
    elseif sort == "last" then
      return row.last
    elseif sort == "xp" then
      return row.xp or 0
    elseif sort == "zone" then
      -- a monster without a known zone sorts after the named ones ("~" follows every letter)
      return row.zone and row.zone ~= UNKNOWN_ZONE and L.Fold(zoneLabel(db, opts, row.zone)) or "~"
    elseif sort == "category" then
      return L.Fold(opts.label and opts.label(Cat.Key(row.cat) or "") or string.format("%03d", row.cat or 0))
    end
    return row.sortName
  end
  return function(a, b)
    local va, vb = value(a), value(b)
    if va ~= vb then
      if desc then
        return va > vb
      end
      return va < vb
    end
    if a.sortName ~= b.sortName then
      return a.sortName < b.sortName
    end
    return tostring(a.key) < tostring(b.key)
  end
end

local function build(db, domain, opts, f)
  local aggs = collect(db, domain, opts)
  if domain == "kills" then
    return killRows(db, aggs, opts.view, f)
  end
  return useRows(aggs, opts.view, f, opts)
end

local function searchText(db, opts, domain, row)
  local parts = { label(opts, row) }
  if domain == "kills" and row.zone then
    parts[#parts + 1] = zoneLabel(db, opts, row.zone)
  elseif domain == "uses" and row.cat and row.name then
    local text = opts.label and opts.label(Cat.Key(row.cat) or "")
    parts[#parts + 1] = text or ""
  end
  return table.concat(parts, " ")
end

local function hasFilter(f)
  return f.zone ~= nil or f.type ~= nil or f.level ~= nil or f.category ~= nil or f.confirmed == true
end

-- The rows of a list page. opts:
--   domain      "kills" or "uses"
--   view        one of L.VIEWS[domain]
--   period      one of L.PERIODS, today the day index (needed for the day periods), now the server time (sessions)
--   scope       nil or "all" for every character, else a character key
--   filters     kills: zone (name id, 0 unknown), type, level (0 unknown); uses: category, confirmed (true = only confirmed)
--   sort, desc  one of L.SORTS[domain] (default count), desc overrides the default direction of the sort
--   query       search text, folded, on the name, the zone or the category
--   itemName    function(itemId) -> text for the use rows, label function(key) -> text for the keys
--   barWidth    width in px for the bars (default 100)
-- Returns { rows, total, max, hidden, domain, view, period, sort }. A row has key, name or labelKey, n, last, share
-- (0 to 1), permille (0 to 1000), bar (0 to 1) and px; kill rows xp (nil in a period) and mobs, zone, ty, cl, lv (monster
-- view); use rows assumed (the part without proof), cat, estimated. total is the sum of n after the filters, before the
-- search. hidden is the number of rows the filters remove.
function L.Rows(db, opts)
  opts = opts or {}
  local domain = opts.domain == "uses" and "uses" or "kills"
  local views = L.VIEWS[domain]
  local view = views[1]
  for _, name in ipairs(views) do
    if opts.view == name then
      view = name
    end
  end
  local sort = "count"
  for _, name in ipairs(L.SORTS[domain]) do
    if opts.sort == name then
      sort = name
    end
  end
  local run = { period = normalPeriod(opts.period), view = view, scope = opts.scope, today = opts.today, now = opts.now,
    itemName = opts.itemName }
  local f = opts.filters or {}
  local rows = build(db, domain, run, f)
  local hidden = 0
  if hasFilter(f) then
    hidden = math.max(0, #build(db, domain, run, {}) - #rows)
  end
  local total, max = 0, 0
  for _, row in ipairs(rows) do
    row.sortName = sortKey(opts, row)
    total = total + row.n
    max = math.max(max, row.n)
  end
  local width = opts.barWidth or 100
  for _, row in ipairs(rows) do
    row.share = total > 0 and row.n / total or 0
    row.permille = math.floor(row.share * 1000 + 0.5)
    row.bar = max > 0 and row.n / max or 0
    row.px = row.n > 0 and math.max(1, math.floor(row.bar * width)) or 0
  end
  if trimmed(opts.query) ~= "" then
    local kept = {}
    for _, row in ipairs(rows) do
      if L.Match(searchText(db, opts, domain, row), opts.query) then
        kept[#kept + 1] = row
      end
    end
    rows = kept
  end
  table.sort(rows, sorter(db, opts, sort))
  return { rows = rows, total = total, max = max, hidden = hidden, domain = domain, view = view, period = run.period,
    sort = sort }
end

-- The entries of the filter dropdowns with their counts in the period and scope, "unknown" as its own entry (key 0).
-- kills: { zones, types, levels }, uses: { categories }. Each entry is { key, name or labelKey, n }.
function L.FilterChoices(db, opts)
  opts = opts or {}
  local domain = opts.domain == "uses" and "uses" or "kills"
  local run = { period = normalPeriod(opts.period), scope = opts.scope, today = opts.today, now = opts.now }
  local function list(view, filterOpts)
    run.view = view
    local rows = build(db, domain, run, filterOpts or {})
    for _, row in ipairs(rows) do
      row.sortName = sortKey(opts, row)
    end
    table.sort(rows, function(a, b)
      if (a.key == 0) ~= (b.key == 0) then
        return b.key == 0
      end
      return a.sortName < b.sortName
    end)
    return rows
  end
  if domain == "kills" then
    return { zones = list("zone"), types = list("type"), levels = list("level") }
  end
  return { categories = list("category") }
end

-- Textual alternative of a bar as a locale key plus the values (the page formats it): key "stats.bar.<domain>".
function L.BarText(row, domain)
  return { key = "stats.bar." .. (domain == "uses" and "uses" or "kills"), name = row.name, labelKey = row.labelKey,
    value = row.key, n = row.n, permille = row.permille }
end

-- Day series ---------------------------------------------------------------------------------------------------------------

-- One point per day, the oldest first, `days` points ending at opts.today: { day, n, bar }. Scope as in L.Rows.
-- Returns { points, total, max }.
function L.DaySeries(db, domain, opts)
  domain = domain == "uses" and "uses" or "kills"
  local days = opts.days or 30
  local points, total, max = {}, 0, 0
  local chars = scopeChars(db, { scope = opts.scope, period = "total" })
  for day = opts.today - days + 1, opts.today do
    local n = 0
    for _, item in ipairs(chars) do
      for _, qty in pairs(item.char[domain].day[day] or {}) do
        n = n + qty
      end
    end
    points[#points + 1] = { day = day, n = n }
    total, max = total + n, math.max(max, n)
  end
  for _, point in ipairs(points) do
    point.bar = max > 0 and point.n / max or 0
  end
  return { points = points, total = total, max = max }
end

-- Textual alternative of a day bar: key "stats.bar.day.<domain>", the date as "YYYY-MM-DD" and the count.
function L.DayText(point, domain)
  return { key = "stats.bar.day." .. (domain == "uses" and "uses" or "kills"), date = Store.DayDate(point.day),
    n = point.n }
end

-- Overview ---------------------------------------------------------------------------------------------------------------

-- The numbers of the overview for a period and scope (opts as in L.Rows, without view, filters and query):
--   kills  { n, xp (nil in a period), monsters, zones, top (the most killed row), skippedSecret }
--   uses   { n, assumed, confirmedPermille (nil without uses), items, top, skippedWindow, skippedSecret }
--   pvp    players defeated (all time), chars  characters read
function L.Overview(db, opts)
  opts = opts or {}
  local function base(domain, view)
    return L.Rows(db, { domain = domain, view = view, period = opts.period, scope = opts.scope, today = opts.today,
      now = opts.now, itemName = opts.itemName, label = opts.label })
  end
  local monsters, zones, items = base("kills", "monster"), base("kills", "zone"), base("uses", "item")
  local out = {
    kills = { n = monsters.total, monsters = #monsters.rows, zones = #zones.rows, top = monsters.rows[1],
      skippedSecret = 0 },
    uses = { n = items.total, assumed = 0, items = #items.rows, top = items.rows[1], skippedWindow = 0,
      skippedSecret = 0 },
    pvp = 0,
    chars = 0,
  }
  if normalPeriod(opts.period) == "total" then
    out.kills.xp = 0
    for _, row in ipairs(monsters.rows) do
      out.kills.xp = out.kills.xp + (row.xp or 0)
    end
  end
  for _, row in ipairs(items.rows) do
    out.uses.assumed = out.uses.assumed + row.assumed
  end
  if out.uses.n > 0 then
    out.uses.confirmedPermille = math.floor((out.uses.n - out.uses.assumed) * 1000 / out.uses.n + 0.5)
  end
  for _, item in ipairs(scopeChars(db, { scope = opts.scope, period = "total" })) do
    local char = item.char
    out.chars = out.chars + 1
    out.pvp = out.pvp + char.pvp
    out.kills.skippedSecret = out.kills.skippedSecret + char.kills.skip.secret
    out.uses.skippedWindow = out.uses.skippedWindow + char.uses.skip.window
    out.uses.skippedSecret = out.uses.skippedSecret + char.uses.skip.secret
  end
  return out
end
