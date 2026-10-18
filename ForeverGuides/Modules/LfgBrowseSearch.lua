-- Search side of the group finder panel: reads the categories and activities the game offers and starts a search
-- with the choice of the panel (Modules/LfgFilterPanel.lua). The result list is Blizzard's own, the filter hook
-- (Modules/LfgBrowseFilter.lua) works on it as for every other search.
--
-- C_LFGList.Search(categoryID, 0, 0, languages, false, nil, activityIDs): filter, preferred filters, language, cross
-- faction and advanced filter as Blizzard's own search sends them (LFGBrowse_DoSearch). An empty activity list
-- returns nothing, so an empty choice means every activity of the category; "None" is its own state (no search).
-- The languages are a set of client codes, nil while only the player's own language is searched (the client adds
-- that one itself). The call needs a real click, so S.Run is only called from the click of the panel's button,
-- never from a timer or an event. One search returns at most 100 results, whatever the choice.
--
-- The answer is asynchronous: busy until LFG_LIST_SEARCH_RESULTS_RECEIVED or LFG_LIST_SEARCH_FAILED, or until the
-- time limit. There is no check before the call. A refusal by the client shows as ADDON_ACTION_BLOCKED naming the
-- function, the search then ends with the note "blocked". Blizzard's frame lists the result through the same
-- events by itself; nothing of Blizzard's is written here.
--
-- S.ShowList: after a started search the window shows its browse tab (the list), whatever tab the click came from.
-- Blizzard's SetActiveTab is a local of its file, so the global handler of tab 2 is the way in (it is what the
-- tab button of the old style calls). Found by name and id only, never by a tab text: the texts are translated.
-- One attempt per click, outside combat, with the filter hook in place and without LFG Filter Forever. A raise or
-- a refusal ends the switching for the session and leaves the search running; the panel keeps its note.
local addonName, ns = ...
local Guard, LB = ns.AutoGuard, ns.LfgBrowseFilterLogic

ns.AddLocale("enUS", {
  ["lfgp.lang.deDE"] = "German",
  ["lfgp.lang.enUS"] = "English",
  ["lfgp.lang.esES"] = "Spanish (Spain)",
  ["lfgp.lang.esMX"] = "Spanish (Latin America)",
  ["lfgp.lang.frFR"] = "French",
  ["lfgp.lang.itIT"] = "Italian",
  ["lfgp.lang.koKR"] = "Korean",
  ["lfgp.lang.ptBR"] = "Portuguese",
  ["lfgp.lang.ruRU"] = "Russian",
  ["lfgp.lang.zhCN"] = "Chinese (Simplified)",
  ["lfgp.lang.zhTW"] = "Chinese (Traditional)",
})
ns.AddLocale("deDE", {
  ["lfgp.lang.deDE"] = "Deutsch",
  ["lfgp.lang.enUS"] = "Englisch",
  ["lfgp.lang.esES"] = "Spanisch (Spanien)",
  ["lfgp.lang.esMX"] = "Spanisch (Lateinamerika)",
  ["lfgp.lang.frFR"] = "Französisch",
  ["lfgp.lang.itIT"] = "Italienisch",
  ["lfgp.lang.koKR"] = "Koreanisch",
  ["lfgp.lang.ptBR"] = "Portugiesisch",
  ["lfgp.lang.ruRU"] = "Russisch",
  ["lfgp.lang.zhCN"] = "Chinesisch (vereinfacht)",
  ["lfgp.lang.zhTW"] = "Chinesisch (traditionell)",
})

local S = {}
ns.LfgBrowseSearch = S

S.TIMEOUT = 15

local busy, note, generation = false, nil, 0
-- ShowList: a switch is running (a refusal then belongs to it, not to the search), and the session switch.
local switching, switchFailed = false, false

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

-- Language codes ----------------------------------------------------------------------------------------------------

-- The codes of a game answer, whether it is a list of codes or a set keyed by code. Sorted, so the order is stable.
local function codes(value)
  value = Guard.Safe(value)
  local out = {}
  if type(value) ~= "table" then
    return out
  end
  for _, code in ipairs(value) do
    code = label(code)
    if code then
      out[#out + 1] = code
    end
  end
  local keyed = {}
  for key, flag in pairs(value) do
    if type(key) == "string" and Guard.Safe(flag) == true then
      keyed[#keyed + 1] = key
    end
  end
  table.sort(keyed)
  for _, code in ipairs(keyed) do
    out[#out + 1] = code
  end
  return out
end

-- The game's own text for a code where one exists: Blizzard names Spanish and Chinese alike in the group finder
-- texts, those four use their locale texts.
local NAME_GLOBALS =
  { esES = "ESES", esMX = "ESMX", zhCN = "LOCALE_DISPLAY_NAME_ZHCN", zhTW = "LOCALE_DISPLAY_NAME_ZHTW" }

-- Display name of a language code: Blizzard's text in the player's language, else ours, else the code itself.
function S.LanguageName(code)
  local text = label(rawget(_G, NAME_GLOBALS[code] or ("LFG_LIST_LANGUAGE_" .. code:upper())))
  if text then
    return text
  end
  local key = "lfgp.lang." .. code
  local own = ns.L[key]
  return own ~= key and own or code
end

-- Entries { code, name, locked } of the languages the client offers for a search, the player's own language
-- (the client's default filter, always searched) locked. Empty when the client offers none.
function S.Languages()
  local list = api()
  if not list then
    return {}
  end
  local own = {}
  for _, code in ipairs(codes(call(list.GetDefaultLanguageSearchFilter))) do
    own[code] = true
  end
  return LB.LanguageEntries(codes(call(list.GetAvailableLanguageSearchFilter)), own, S.LanguageName)
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
-- searches nothing and sets no note) and the chosen extra languages (a set of codes). Only from a click.
function S.Run(categoryID, chosen, none, languages)
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
  local languageFilter = LB.LanguageSearch(S.Languages(), languages)
  busy, note = true, nil
  generation = generation + 1
  local mine = generation
  -- Busy before the call: a refusal raises its event inside the call and must find the search running.
  -- The game's function is called from a Lua closure, not handed to pcall: a protected function reached through
  -- pcall is refused as UNKNOWN() in this client, the same call from a plain statement is not.
  local ok, err = pcall(function()
    list.Search(categoryID, 0, 0, languageFilter, false, nil, ids)
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

local function frameOf(name)
  local frame = rawget(_G, name)
  return type(frame) == "table" and frame or nil
end

-- Shows Blizzard's browse tab after Run started a search. True when the tab was switched, false when nothing was
-- done or the switch failed. Only from the click that started the search, like Run.
function S.ShowList()
  local filter = ns.LfgBrowseFilter
  local window, list = frameOf("LFGParentFrame"), frameOf("LFGBrowseFrame")
  local show = rawget(_G, "LFGParentFrameTab2_OnClick")
  if
    not (busy and note == nil)
    or switchFailed
    or type(show) ~= "function"
    or not (window and list)
    or not (filter and filter.Installed() and not filter.Foreign())
    or Guard.Blocked()
    or window:IsShown() ~= true
    or list:IsVisible() == true
  then
    return false
  end
  local secure = rawget(_G, "securecall")
  switching = true
  -- A Lua closure, not the game's function handed to pcall (see Run). securecall keeps the taint of this click
  -- out of the tab's own code, which refreshes the dropdowns of the list.
  local ok, err = pcall(function()
    if type(secure) == "function" then
      secure(show)
    else
      show()
    end
  end)
  switching = false
  if not ok then
    switchFailed = true
    ns.Log.warn("lfg tab: %s", tostring(err))
  end
  if ok and not switchFailed then
    -- Run's clear skipped the list while its tab was hidden, and the tab's own redraw may have read the old
    -- list back: empty it now that it is visible.
    ns.Safe("lfg-browse-clear", filter.Clear)
  end
  return ok and not switchFailed
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
  if switching then
    -- The tab switch was refused: the search itself is fine.
    if blockedAddon == addonName and not switchFailed then
      switchFailed = true
      ns.Log.warn("lfg tab blocked: %s", tostring(func))
    end
    return
  end
  -- A protected call reached through the engine's own wrappers is reported as UNKNOWN(), so that counts too.
  local name = tostring(func)
  if busy and blockedAddon == addonName and (name:find("Search", 1, true) or name:find("UNKNOWN", 1, true)) then
    finish("blocked")
  end
end)
