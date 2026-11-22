-- Display name of a quest of the instance data. The data holds a German name only for some quests; for the rest
-- a German client gets the title the game itself knows (C_QuestLog.GetTitleForQuestID), English stays the fallback.
-- Titles live in a runtime table only (never in SavedVariables). A title the client does not have yet is requested
-- once per id and session; the answers (QUEST_DATA_LOAD_RESULT) of one burst cause one FG_QUEST_NAMES message.
-- Search: the index is built from the stored names at load, so a runtime title is not searchable (documented in
-- docs/TESTPLAN-IM-SPIEL.md).
local _, ns = ...

local Q = {}
ns.QuestNames = Q

Q.DEBOUNCE = 0.2

-- id -> title found at runtime; id -> true once requested; id -> true while waiting for the next message.
local titles, requested, pending = {}, {}, {}
local scheduled = false

local function api(name)
  local log = rawget(_G, "C_QuestLog")
  local fn = type(log) == "table" and log[name] or nil
  return type(fn) == "function" and fn or nil
end

-- Title the client has for the quest, nil when it has none (yet).
local function clientTitle(id)
  local fn = api("GetTitleForQuestID")
  local ok, title = false, nil
  if fn then
    ok, title = pcall(fn, id)
  end
  if ok and type(title) == "string" and title ~= "" then
    return title
  end
  return nil
end

-- Name of the quest row { id, n = { en, de } } in the language of the client.
function Q.Name(quest)
  if type(quest) ~= "table" then
    return nil
  end
  local field, id = quest.n, quest.id
  if type(field) ~= "table" or ns.GetActiveLocale() ~= "deDE" or field.de or type(id) ~= "number" then
    return ns.T(field)
  end
  local title = titles[id]
  if not title then
    title = clientTitle(id)
    if title then
      titles[id] = title
    elseif not requested[id] then
      requested[id] = true
      pending[id] = true
      local request = api("RequestLoadQuestByID")
      if request then
        pcall(request, id)
      end
    end
  end
  return title or ns.T(field)
end

ns.On("QUEST_DATA_LOAD_RESULT", function(_, id)
  if not pending[id] then
    return
  end
  pending[id] = nil
  if scheduled then
    return
  end
  scheduled = true
  C_Timer.After(Q.DEBOUNCE, function()
    scheduled = false
    ns.Emit("FG_QUEST_NAMES")
  end)
end)
