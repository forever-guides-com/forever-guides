-- Rule engine, part 2: the twelve stock rules as data, no game calls. A template is a rule skeleton
-- with { param = "name" } holes, the parameters (type, default, limits) and locale keys. Instantiate
-- copies it into plain draft rules (never enabled); the guild ranks are holes the user has to fill,
-- every guild names its ranks differently.
--
-- Parameter types: rank (one index 1..9), ranks (list), int (min, max, default), bool (default).
-- A parameter may take its default from the caller: defaultFrom = "maxLevel" | "lowestRank".
-- A skeleton condition with `when = "param"` only exists while that parameter is true.
-- Locale keys: gm.tpl.<id>.title, .desc, .warn (only when warn = true), .p.<param>.
local _, gm = ...

local RT = {}
gm.RuleTemplates = RT

local function days(name, default, max)
  return { name = name, type = "int", default = default, min = 1, max = max or 365 }
end

local function hole(name)
  return { param = name }
end

RT.LIST = {
  {
    id = "promoteByTime",
    warn = true,
    params = { { name = "rank", type = "rank" }, days("days", 30) },
    rules = {
      {
        template = "promoteByTime",
        ranks = { hole("rank") },
        all = { { kind = "daysInRank", op = "atLeast", value = hole("days") } },
        action = { kind = "promote" },
      },
    },
  },
  {
    id = "promoteByGuildTime",
    warn = true,
    params = { { name = "rank", type = "rank" }, days("days", 14), { name = "targetRank", type = "rank" } },
    rules = {
      {
        template = "promoteByGuildTime",
        ranks = { hole("rank") },
        all = { { kind = "daysInGuild", op = "atLeast", value = hole("days") } },
        action = { kind = "setRank", rank = hole("targetRank") },
      },
    },
  },
  {
    id = "promoteByLevel",
    params = {
      { name = "rank", type = "rank" },
      { name = "level", type = "int", default = 60, min = 1, max = 120, defaultFrom = "maxLevel" },
    },
    rules = {
      {
        template = "promoteByLevel",
        ranks = { hole("rank") },
        all = { { kind = "level", op = "atLeast", value = hole("level") } },
        action = { kind = "promote" },
      },
    },
  },
  {
    id = "reviewNewcomers",
    warn = true,
    params = { { name = "rank", type = "rank", defaultFrom = "lowestRank" }, days("days", 7) },
    rules = {
      {
        template = "reviewNewcomers",
        ranks = { hole("rank") },
        all = {
          { kind = "daysInGuild", op = "atLeast", value = hole("days") },
          { kind = "dateKnown", op = "exact", value = "joined" },
        },
        action = { kind = "mark", tag = "review" },
      },
    },
  },
  {
    id = "demoteByInactivity",
    params = { { name = "rank", type = "rank" }, days("days", 45) },
    rules = {
      {
        template = "demoteByInactivity",
        ranks = { hole("rank") },
        all = { { kind = "groupDaysOffline", op = "atLeast", value = hole("days") } },
        action = { kind = "demote" },
      },
    },
  },
  {
    id = "markInactive",
    params = { { name = "ranks", type = "ranks" }, days("days", 14) },
    rules = {
      {
        template = "markInactive",
        ranks = hole("ranks"),
        all = { { kind = "groupDaysOffline", op = "atLeast", value = hole("days") } },
        action = { kind = "mark", tag = "inactive" },
      },
    },
  },
  {
    id = "removeInactive",
    warn = true,
    params = {
      { name = "ranks", type = "ranks" },
      days("days", 90),
      { name = "requireMark", type = "bool", default = true },
    },
    rules = {
      {
        template = "removeInactive",
        ranks = hole("ranks"),
        all = {
          { kind = "groupDaysOffline", op = "atLeast", value = hole("days") },
          { kind = "online", op = "isNot" },
          { kind = "tag", op = "has", value = "inactive", when = "requireMark" },
        },
        action = { kind = "remove" },
      },
    },
  },
  {
    id = "cleanupAlts",
    warn = true,
    params = { { name = "ranks", type = "ranks" }, days("days", 60) },
    rules = {
      {
        template = "cleanupAlts",
        ranks = hole("ranks"),
        all = {
          { kind = "link", op = "isAlt" },
          { kind = "daysOffline", op = "atLeast", value = hole("days") },
          -- The group minimum includes the alt itself: below the limit means someone else is active.
          { kind = "groupDaysOffline", op = "lessThan", value = hole("days") },
        },
        action = { kind = "mark", tag = "cleanup" },
      },
    },
  },
  {
    id = "matchAltRank",
    warn = true,
    params = { { name = "ranks", type = "ranks" } },
    rules = {
      {
        template = "matchAltRank",
        ranks = hole("ranks"),
        all = { { kind = "link", op = "isAlt" }, { kind = "mainRank", op = "differs" } },
        action = { kind = "setRank", rankFrom = "main" },
      },
    },
  },
  {
    id = "returnees",
    warn = true,
    params = { { name = "ranks", type = "ranks" }, days("days", 3, 30) },
    rules = {
      {
        template = "returnees",
        ranks = hole("ranks"),
        all = {
          { kind = "tag", op = "has", value = "returned" },
          { kind = "daysOffline", op = "lessThan", value = hole("days") },
        },
        action = { kind = "mark", tag = "returnee" },
      },
    },
  },
  {
    id = "writeJoinDate",
    warn = true,
    params = { { name = "ranks", type = "ranks" }, { name = "public", type = "bool", default = true } },
    rules = {
      {
        template = "writeJoinDate",
        ranks = hole("ranks"),
        all = {
          { kind = "dateKnown", op = "exact", value = "joined" },
          { kind = "publicNote", op = "notContains", value = "J:" },
        },
        action = { kind = "setNote", note = "J:{date}", public = hole("public") },
      },
    },
  },
  {
    -- One click, three coordinated rules. Order is the priority: removal beats demotion beats the mark.
    id = "inactivityLadder",
    warn = true,
    ascending = { "markDays", "demoteDays", "removeDays" },
    params = {
      { name = "ranks", type = "ranks" },
      { name = "rank", type = "rank" },
      days("markDays", 14),
      days("demoteDays", 45),
      days("removeDays", 90),
    },
    rules = {
      {
        template = "removeInactive",
        ranks = hole("ranks"),
        all = {
          { kind = "groupDaysOffline", op = "atLeast", value = hole("removeDays") },
          { kind = "online", op = "isNot" },
          { kind = "tag", op = "has", value = "inactive" },
        },
        action = { kind = "remove" },
      },
      {
        template = "demoteByInactivity",
        ranks = { hole("rank") },
        all = { { kind = "groupDaysOffline", op = "atLeast", value = hole("demoteDays") } },
        action = { kind = "demote" },
      },
      {
        template = "markInactive",
        ranks = hole("ranks"),
        all = { { kind = "groupDaysOffline", op = "atLeast", value = hole("markDays") } },
        action = { kind = "mark", tag = "inactive" },
      },
    },
  },
}

local BY_ID = {}
for _, t in ipairs(RT.LIST) do
  BY_ID[t.id] = t
end

function RT.Get(id)
  return BY_ID[id]
end

function RT.IDs()
  local out = {}
  for i, t in ipairs(RT.LIST) do
    out[i] = t.id
  end
  return out
end

-- Every locale key the templates need, for the locale check.
function RT.Keys()
  local out = {}
  for _, t in ipairs(RT.LIST) do
    local base = "gm.tpl." .. t.id
    out[#out + 1] = base .. ".title"
    out[#out + 1] = base .. ".desc"
    if t.warn then
      out[#out + 1] = base .. ".warn"
    end
    for _, p in ipairs(t.params) do
      out[#out + 1] = base .. ".p." .. p.name
    end
  end
  return out
end

local function whole(v)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
    return nil
  end
  return math.floor(v + 0.5)
end

local function rankOf(v)
  v = whole(v)
  return v and v >= 1 and v <= 9 and v or nil
end

local function ranksOf(list)
  local out, seen = {}, {}
  for _, v in ipairs(type(list) == "table" and list or {}) do
    v = rankOf(v)
    if v and not seen[v] then
      seen[v] = true
      out[#out + 1] = v
    end
  end
  table.sort(out)
  return out
end

-- Clean parameter values: every number inside its limits, every missing one at its default.
-- Returns a table name -> value (rank and list parameters stay nil / empty until chosen).
function RT.Values(template, given, opts)
  template = type(template) == "string" and BY_ID[template] or template
  if type(template) ~= "table" or not template.params then
    return nil
  end
  given = type(given) == "table" and given or {}
  opts = type(opts) == "table" and opts or {}
  local values = {}
  for _, p in ipairs(template.params) do
    local v = given[p.name]
    local fallback = p.defaultFrom and opts[p.defaultFrom] or p.default
    if p.type == "rank" then
      values[p.name] = rankOf(v) or (v == nil and rankOf(fallback)) or nil
    elseif p.type == "ranks" then
      values[p.name] = ranksOf(v)
    elseif p.type == "int" then
      local n = whole(v) or whole(fallback) or p.default
      values[p.name] = math.max(p.min, math.min(p.max, n))
    else
      if v == nil then
        v = p.default
      end
      values[p.name] = v == true
    end
  end
  -- The limits of a ladder only make sense in rising order.
  local previous
  for _, name in ipairs(template.ascending or {}) do
    local p
    for _, candidate in ipairs(template.params) do
      if candidate.name == name then
        p = candidate
      end
    end
    if previous and values[name] <= values[previous] then
      values[name] = math.min(p.max, values[previous] + 1)
    end
    previous = name
  end
  return values
end

local function fill(node, values)
  if type(node) ~= "table" then
    return node
  end
  if node.param then
    local v = values[node.param]
    if type(v) == "table" then
      return fill(v, values)
    end
    return v
  end
  local out = {}
  if #node > 0 then
    for _, item in ipairs(node) do
      if type(item) ~= "table" or not item.when or values[item.when] == true then
        local v = fill(item, values)
        if v ~= nil then
          out[#out + 1] = v
        end
      end
    end
    return out
  end
  for k, v in pairs(node) do
    if k ~= "when" then
      out[k] = fill(v, values)
    end
  end
  return out
end

-- Draft rules for the template: a list (one rule, three for the ladder), always disabled. given:
-- parameter values, opts: maxLevel and lowestRank of the guild for the parameters that default to them.
-- nil for an unknown template.
function RT.Instantiate(id, given, opts)
  local template = BY_ID[id]
  local values = template and RT.Values(template, given, opts)
  if not values then
    return nil
  end
  local out = {}
  for i, skeleton in ipairs(template.rules) do
    local rule = fill(skeleton, values)
    rule.name = ""
    rule.enabled = false
    out[i] = rule
  end
  return out
end
