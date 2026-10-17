-- Search side of the group finder panel: reads the categories and activities the game offers and starts a search
-- with the choice of the panel (Modules/LfgFilterPanel.lua). The result list is Blizzard's own, the filter hook
-- (Modules/LfgBrowseFilter.lua) works on it as for every other search.
--
-- C_LFGList.Search(categoryID, 0, 0, nil, false, nil, activityIDs): filter, preferred filters, language, cross
-- faction and advanced filter as Blizzard's own search sends them (LFGBrowse_DoSearch). An empty activity list
-- returns nothing, so an empty choice means every activity of the category; "None" is its own state (no search). The call needs a real click, so S.Run is
-- only called from the click of the panel's button, never from a timer or an event.
--
-- The answer is asynchronous: busy until LFG_LIST_SEARCH_RESULTS_RECEIVED or LFG_LIST_SEARCH_FAILED, or until the
-- time limit. There is no check before the call. A refusal by the client shows as ADDON_ACTION_BLOCKED naming the
-- function, the search then ends with the note "blocked". Blizzard's frame lists the result through the same
-- events by itself; nothing of Blizzard's is written or called here.
local addonName, ns = ...
local Guard, LB = ns.AutoGuard, ns.LfgBrowseFilterLogic

local S = {}
ns.LfgBrowseSearch = S

S.TIMEOUT = 15

local busy, note, generation = false, nil, 0

local function api()
  local list = rawget(_G, "C_LFGList")
  return type(list) == "table" and list or nil
end

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  return ok and value or nil
end

local function whole(value)
  value = Guard.Safe(value)
  return type(value) == "number" and value == value and value or nil
end

local function label(value)
  value = Guard.Safe(value)
  return type(value) == "string" and value ~= "" and value or nil
end

-- The ids the game offers for a category, whatever the level filter of Blizzard's own dropdown says.
local function activityIDs(list, categoryID)
  local out = {}
  local ids = Guard.Safe(call(list.GetAvailableActivities, categoryID))
  for _, id in ipairs(type(ids) == "table" and ids or {}) do
    id = whole(id)
    if id then
      out[#out + 1] = id
    end
  end
  return out
end

-- Entries { id, name, min, max } of a category in display order. An activity without an info table stays in
-- the list (name nil, no range), so the player can still pick it.
function S.Activities(categoryID)
  local list = api()
  local out = {}
  if not list then
    return out
  end
  for _, id in ipairs(activityIDs(list, categoryID)) do
    local info = Guard.Safe(call(list.GetActivityInfoTable, id))
    local entry = { id = id }
    if type(info) == "table" then
      entry.name = label(info.fullName) or label(info.shortName)
      entry.min, entry.max = whole(info.minLevelSuggestion) or 0, whole(info.maxLevelSuggestion) or 0
    end
    out[#out + 1] = entry
  end
  return LB.SortActivities(out)
end

-- { categories = { { id, name, total, ranged } }, activities = { [categoryID] = entries } } for the categories
-- that have activities. The chosen category comes from LB.ResolveCategory.
function S.Snapshot()
  local snapshot = { categories = {}, activities = {} }
  local list = api()
  if not list then
    return snapshot
  end
  local ids = Guard.Safe(call(list.GetAvailableCategories))
  for _, id in ipairs(type(ids) == "table" and ids or {}) do
    id = whole(id)
    local entries = id and S.Activities(id)
    if entries and #entries > 0 then
      local ranged = 0
      for _, entry in ipairs(entries) do
        if (entry.min or 0) > 0 or (entry.max or 0) > 0 then
          ranged = ranged + 1
        end
      end
      local info = Guard.Safe(call(list.GetLfgCategoryInfo, id))
      local name = type(info) == "table" and label(info.name) or tostring(id)
      snapshot.categories[#snapshot.categories + 1] = { id = id, name = name, total = #entries, ranged = ranged }
      snapshot.activities[id] = entries
    end
  end
  return snapshot
end

function S.Busy()
  return busy
end

-- nil, "failed" (no answer, an error or nothing to search) or "blocked" (the client refused the call).
function S.Note()
  return note
end

local function changed()
  ns.Emit("FG_LFG_SEARCH_CHANGED")
end

local function finish(result)
  busy = false
  generation = generation + 1
  note = result
  changed()
end

-- Starts a search for a category with the chosen activities (a set of ids; none = the player chose "None", which
-- searches nothing and sets no note). Only from a click.
function S.Run(categoryID, chosen, none)
  if busy or none == true then
    return false
  end
  local list = api()
  if not list or type(list.Search) ~= "function" or type(categoryID) ~= "number" or categoryID <= 0 then
    note = "failed"
    changed()
    return false
  end
  local ids = LB.SearchIDs(chosen, activityIDs(list, categoryID))
  if #ids == 0 then
    note = "failed"
    changed()
    return false
  end
  busy, note = true, nil
  generation = generation + 1
  local mine = generation
  -- Busy before the call: a refusal raises its event inside the call and must find the search running.
  -- The game's function is called from a Lua closure, not handed to pcall: a protected function reached through
  -- pcall is refused as UNKNOWN() in this client, the same call from a plain statement is not.
  local ok, err = pcall(function()
    list.Search(categoryID, 0, 0, nil, false, nil, ids)
  end)
  if not ok then
    ns.Log.warn("lfg search: %s", tostring(err))
    finish("failed")
    return false
  end
  if busy and generation == mine then
    -- Cleared only after the call went through: a refused search must leave the old list standing. Same tick,
    -- so no row with a dead result id can be hovered in between.
    local filter = ns.LfgBrowseFilter
    if filter then
      ns.Safe("lfg-browse-clear", filter.Clear)
    end
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then
      pcall(timer.After, S.TIMEOUT, function()
        if busy and generation == mine then
          finish("failed")
        end
      end)
    end
    changed()
  end
  return true
end

ns.On("LFG_LIST_SEARCH_RESULTS_RECEIVED", function()
  if busy then
    finish(nil)
  end
end)

ns.On("LFG_LIST_SEARCH_FAILED", function()
  if busy then
    finish("failed")
  end
end)

-- The client names the add-on and the function it refused.
ns.On("ADDON_ACTION_BLOCKED", function(_, blockedAddon, func)
  -- A protected call reached through the engine's own wrappers is reported as UNKNOWN(), so that counts too.
  local name = tostring(func)
  if busy and blockedAddon == addonName and (name:find("Search", 1, true) or name:find("UNKNOWN", 1, true)) then
    finish("blocked")
  end
end)
