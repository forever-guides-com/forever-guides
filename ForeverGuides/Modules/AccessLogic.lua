-- Access requirements of instances, the pure side: filter, check per condition, totals and the
-- saved state per character. No game access, AccessView.lua reads the game and passes it in as
-- `env`. Data: ns.Data.Access (docs/ZUGANG-FORMAT.md).
--
-- env = {
--   itemCount(id) -> number|nil   live count of the current character,
--   inventory = snapshot|nil      stored inventory (InventoryLogic) of the character,
--   quest(id) -> boolean|nil      quest completed,
--   standing(id) -> number|nil    reputation standing 1..8,
--   level = number|nil,
-- }
-- A check returns "yes", "no" or "unknown" (value not readable); a note has no check (nil).
local _, ns = ...

local Logic = {}
ns.AccessLogic = Logic

Logic.KINDS = { item = true, quest = true, rep = true, level = true, note = true }
Logic.MAX_SAVED = 200
Logic.MAX_COUNT = 99

local function int(v, lo, hi)
  if type(v) ~= "number" or v ~= v or v < lo or v > hi then
    return nil
  end
  return math.floor(v)
end

-- The function result, nil when it is missing or fails.
local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  if not ok then
    return nil
  end
  return value
end

-- The valid conditions of a list for a faction ("A"/"H"/nil = all). opts.optional == false
-- leaves out the optional ones.
function Logic.Conditions(list, opts)
  opts = opts or {}
  local out = {}
  for _, c in ipairs(type(list) == "table" and list or {}) do
    if
      type(c) == "table"
      and Logic.KINDS[c.kind]
      and (opts.faction == nil or c.faction == nil or c.faction == opts.faction)
      and (opts.optional ~= false or not c.optional)
    then
      out[#out + 1] = c
    end
  end
  return out
end

function Logic.Check(cond, env)
  env = type(env) == "table" and env or {}
  local kind = cond.kind
  if kind == "note" then
    return nil
  end
  if kind == "level" then
    local need, have = int(cond.need, 1, 200), int(env.level, 1, 200)
    if not (need and have) then
      return "unknown"
    end
    return have >= need and "yes" or "no"
  end
  local id = int(cond.id, 1, 1e8)
  if not id then
    return "unknown"
  end
  if kind == "item" then
    local need = int(cond.need, 1, 1e6) or 1
    local have, read = 0, false
    local live = call(env.itemCount, id)
    if type(live) == "number" and live == live then
      have, read = live, true
    end
    if type(env.inventory) == "table" then
      local _, sum = ns.InventoryLogic.Counts(env.inventory, id)
      have, read = math.max(have, sum), true
    end
    if have >= need then
      return "yes"
    end
    return read and "no" or "unknown"
  elseif kind == "quest" then
    local done = call(env.quest, id)
    if type(done) ~= "boolean" then
      return "unknown"
    end
    return done and "yes" or "no"
  elseif kind == "rep" then
    local need, have = int(cond.need, 1, 8), int(call(env.standing, id), 1, 8)
    if not (need and have) then
      return "unknown"
    end
    return have >= need and "yes" or "no"
  end
  return "unknown"
end

-- { { cond, state } } in list order.
function Logic.Evaluate(conds, env)
  local rows = {}
  for i, c in ipairs(conds) do
    rows[i] = { cond = c, state = Logic.Check(c, env) }
  end
  return rows
end

-- Totals over the required conditions (not optional, no notes): done, total, unknown.
function Logic.Summary(rows)
  local done, total, unknown = 0, 0, 0
  for _, row in ipairs(rows) do
    if row.state and not row.cond.optional then
      total = total + 1
      if row.state == "yes" then
        done = done + 1
      elseif row.state == "unknown" then
        unknown = unknown + 1
      end
    end
  end
  return done, total, unknown
end

-- Number of required conditions (not optional, no notes) of a list from Conditions.
function Logic.Total(conds)
  local n = 0
  for _, c in ipairs(conds) do
    if c.kind ~= "note" and not c.optional then
      n = n + 1
    end
  end
  return n
end

-- The required rows that are not met yet (unknown ones included, they are not proven).
function Logic.Missing(rows)
  local out = {}
  for _, row in ipairs(rows) do
    if (row.state == "no" or row.state == "unknown") and not row.cond.optional then
      out[#out + 1] = row
    end
  end
  return out
end

-- Saved state ---------------------------------------------------------------------------

-- A clean copy of a stored { [instanceKey] = { done, total, at } }; nil when nothing is left.
function Logic.CleanSaved(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local out, count = {}, 0
  for key, v in pairs(raw) do
    if type(key) == "string" and key ~= "" and #key <= 60 and type(v) == "table" and count < Logic.MAX_SAVED then
      local total = int(v.total, 1, Logic.MAX_COUNT)
      local done = int(v.done, 0, total or 0)
      if total and done then
        out[key] = { done = done, total = total, at = int(v.at, 0, 1e11) or 0 }
        count = count + 1
      end
    end
  end
  return next(out) and out or nil
end

-- The stored state of an instance, nil when there is none or the number of conditions changed
-- since (the data was updated, the state is outdated).
function Logic.Saved(saved, key, expectedTotal)
  local v = type(saved) == "table" and saved[key]
  if type(v) == "table" and v.total == expectedTotal then
    return v
  end
  return nil
end
