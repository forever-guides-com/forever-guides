-- Legendaries, pure side (no frames): the steps of Data/Legendaries.lua with their state (ticked by the player,
-- or read from quest completion and the bags), the progress and the place of a step for the Waypoint button. The
-- page is Modules/LegendariesPage.lua, the data file is generated.
local _, ns = ...

local P = {}
ns.LegendariesLogic = P

local function data()
  return ns.Data and ns.Data.Legendaries or { items = {}, zones = {} }
end

function P.Basis()
  return data().basis
end

function P.Items()
  return data().items
end

function P.Item(id)
  for _, leg in ipairs(data().items) do
    if leg.id == id then
      return leg
    end
  end
  return nil
end

local function callApi(tableName, name, ...)
  local c = rawget(_G, tableName)
  local fn = type(c) == "table" and c[name] or rawget(_G, name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  return ok and value or nil
end

P.Probe = {
  quest = function(id)
    return callApi("C_QuestLog", "IsQuestFlaggedCompleted", id) == true
  end,
  count = function(item)
    local n = callApi("C_Item", "GetItemCount", item, true)
    return type(n) == "number" and n or 0
  end,
}

local function store()
  local done = ns.charDB and ns.charDB.legendariesDone
  return type(done) == "table" and done or {}
end

local function key(leg, step)
  return leg.id .. ":" .. step.id
end

function P.IsMarked(leg, step)
  return store()[key(leg, step)] == true
end

function P.SetMarked(leg, step, on)
  ns.Store.setChar("legendariesDone." .. key(leg, step), on and true or nil)
end

-- The player owns the finished item (any class variant), bank included.
function P.Owned(leg, probe)
  probe = probe or P.Probe
  for _, item in ipairs(leg.item) do
    if probe.count(item) > 0 then
      return true
    end
  end
  return false
end

local function questDone(step, probe)
  for _, q in ipairs(step.q or {}) do
    if probe.quest(q) then
      return true
    end
  end
  return false
end

-- State of a step: "marked" (ticked), "auto" (read from the game) or nil. A step consumed by a later quest or by the
-- finished item counts as done once that one is.
function P.StepState(leg, step, probe)
  probe = probe or P.Probe
  if P.IsMarked(leg, step) then
    return "marked"
  end
  if P.Owned(leg, probe) then
    return "auto"
  end
  if step.t == "quest" then
    return questDone(step, probe) and "auto" or nil
  end
  if step.bq and probe.quest(step.bq) then
    return "auto"
  end
  if step.bi and probe.count(step.bi) > 0 then
    return "auto"
  end
  if step.item and probe.count(step.item) >= (step.c or 1) then
    return "auto"
  end
  return nil
end

-- Done steps and total of one legendary.
function P.Progress(leg, probe)
  local done = 0
  for _, step in ipairs(leg.steps) do
    if P.StepState(leg, step, probe) then
      done = done + 1
    end
  end
  return done, #leg.steps
end

-- Number of legendaries with every step done.
function P.Finished(probe)
  local n = 0
  for _, leg in ipairs(data().items) do
    local done, total = P.Progress(leg, probe)
    if total > 0 and done == total then
      n = n + 1
    end
  end
  return n
end

function P.Zone(z)
  return data().zones[z]
end

-- The place of a step for the Map and Waypoint buttons, nil for a step without a position.
function P.Place(step)
  local zone = step.z and P.Zone(step.z)
  if not (zone and step.x and step.y) then
    return nil
  end
  return { map = zone.m, x = step.x, y = step.y, label = step.nn and ns.T(step.nn) or ns.T(zone), zone = ns.T(zone) }
end

local function hit(match, query, n)
  return (n.de and match(n.de, query)) or (n.en and match(n.en, query)) or false
end

-- Legendaries whose name or step names (items, quests, NPCs) match the query; all for an empty query.
function P.Filter(query, match)
  local out = {}
  for _, leg in ipairs(data().items) do
    local ok = query == "" or hit(match, query, leg.n)
    for _, step in ipairs(ok and {} or leg.steps) do
      ok = ok or hit(match, query, step.n) or (step.nn ~= nil and hit(match, query, step.nn))
    end
    if ok then
      out[#out + 1] = leg
    end
  end
  return out
end

return P
