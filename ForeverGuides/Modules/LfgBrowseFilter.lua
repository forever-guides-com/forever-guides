-- Filter for the browse list of Blizzard's group finder: the entries that do not pass are removed from the list
-- the game draws (not just dimmed). Rules: Modules/LfgBrowseFilterLogic.lua, panel: Modules/LfgFilterPanel.lua.
--
-- Technique: hooksecurefunc on LFGBrowseFrame:UpdateResultList keeps the list of the search in a table of ours
-- (nothing is written into Blizzard's frame besides its own fields results and totalResults), the filtered ids go
-- into those two fields and LFGBrowseFrame:UpdateResults() draws them. The redraw clears the selection of the list,
-- so it runs only when the ids changed, and a flag stops the hook from filtering its own redraw.
--
-- Taint rules, learned from the add-on LFG Filter Forever: the hook is installed 0.5 s after PLAYER_LOGIN or after
-- the load of Blizzard_GroupFinder_VanillaStyle, never while a file loads (that tainted the category dropdown and
-- its search then hit ADDON_ACTION_BLOCKED). The Blizzard add-on is never a dependency of ours. Only post hooks, no
-- Blizzard function is replaced. Nothing is redrawn in combat (it waits for the end), a redraw that raises pauses
-- the filter until the next search and puts the unfiltered list back. Values the add-on may not read keep their
-- entry (LfgBrowseFilterLogic). With LFG Filter Forever loaded, our hook stays out.
local _, ns = ...
local Guard, L, LB = ns.AutoGuard, ns.L, ns.LfgBrowseFilterLogic

ns.AddLocale("enUS", {
  ["lfgb.paused"] = "Filter paused until your next search.",
  ["lfgb.foreign"] = "LFG Filter Forever filters the group finder.\nThe Forever Guides filter stays off.",
})
ns.AddLocale("deDE", {
  ["lfgb.paused"] = "Filter pausiert bis zur nächsten Suche.",
  ["lfgb.foreign"] = "LFG Filter Forever filtert die Gruppensuche.\nDer Filter von Forever Guides bleibt aus.",
})

local H = {}
ns.LfgBrowseFilter = H

local INSTALL_DELAY = 0.5 -- after login or after the Blizzard add-on loaded
local RETRY_DELAY = 2 -- the frames were not there yet
local RETRIES = 3
local REAPPLY_DELAY = 0.3 -- listings change after a search without a new list
local BLIZZARD_ADDON = "Blizzard_GroupFinder_VanillaStyle"
local FOREIGN_ADDON = "LFGFilterForever"

local raw -- ids of the last search, as Blizzard delivered them
local installed, applying, paused, dirty, noticed = false, false, false, false, false
local pending = false -- an install timer is running
local searched = false -- the game answered a search
local counts = { shown = 0, total = 0 }
local activityNames = {}

local function browseFrame()
  local frame = rawget(_G, "LFGBrowseFrame")
  return type(frame) == "table" and frame or nil
end

local function settings()
  return ns.db and ns.db.settings or {}
end

-- The switch of the card; a missing value counts as on.
function H.Offered()
  return settings().lfgPanel ~= false
end

local function filterState()
  return ns.db and ns.db.lfgFilter
end

local function addonLoaded(name)
  local api = rawget(_G, "C_AddOns")
  local fn = type(api) == "table" and api.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
  if type(fn) ~= "function" then
    return false
  end
  local ok, loaded = pcall(fn, name)
  return ok and loaded == true
end

-- LFG Filter Forever does the filtering; our hook stays out.
function H.Foreign()
  return addonLoaded(FOREIGN_ADDON)
end

-- One chat line per session, when the player opens the panel and could expect it to work.
function H.NoticeForeign()
  if noticed or not H.Foreign() then
    return
  end
  noticed = true
  ns.Notify(L["lfgb.foreign"], "info")
end

function H.Installed()
  return installed
end

function H.Paused()
  return paused
end

-- Whether a search ran since the login: an answer came (a list, even an empty one, or a failure), or the list
-- holds entries. Blizzard also updates the list when its window opens, so the list alone says nothing.
function H.HasList()
  return searched or (type(raw) == "table" and #raw > 0)
end

-- { shown, total } of the last pass.
function H.Counts()
  return { shown = counts.shown, total = counts.total }
end

local function copy(list)
  local out = {}
  for i, value in ipairs(list or {}) do
    out[i] = value
  end
  return out
end

-- Reading the game -------------------------------------------------------------------------------------------

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  return ok and value or nil
end

local function activityName(api, activityID)
  local id = Guard.Safe(activityID)
  if type(id) ~= "number" then
    return nil
  end
  local name = activityNames[id]
  if name == nil then
    local info = Guard.Safe(call(api.GetActivityInfoTable, id))
    local label = type(info) == "table" and (Guard.Safe(info.fullName) or Guard.Safe(info.shortName)) or nil
    name = type(label) == "string" and label or false
    activityNames[id] = name
  end
  return name or nil
end

-- Whether the game dropped the result since the list was made (delisted, or the list is from an older search).
-- Blizzard's tooltip indexes the info of a row without a check, so such an id must never stay on screen. An
-- unreadable answer or a missing API keeps the id.
local function gone(api, id)
  if type(api.HasSearchResultInfo) == "function" then
    local ok, has = pcall(api.HasSearchResultInfo, id)
    if ok and Guard.Safe(has) == false then
      return true
    end
  end
  if type(api.GetSearchResultInfo) ~= "function" then
    return false
  end
  local ok, info = pcall(api.GetSearchResultInfo, id)
  return ok and rawequal(info, nil)
end

-- The ids of a list that still have a result.
local function alive(list)
  local api = rawget(_G, "C_LFGList")
  if type(api) ~= "table" then
    return copy(list)
  end
  local out = {}
  for _, id in ipairs(list) do
    if not gone(api, id) then
      out[#out + 1] = id
    end
  end
  return out
end

-- The record of one result for the rules: only the fields the active filters need, each as the game gave it
-- (the rules check readability themselves).
local function read(id, needs)
  local api = rawget(_G, "C_LFGList")
  if type(api) ~= "table" then
    return nil
  end
  local rec = {}
  local info = Guard.Safe(call(api.GetSearchResultInfo, id))
  if type(info) == "table" then
    rec.numMembers, rec.age, rec.playstyle, rec.leaderName =
      info.numMembers, info.age, info.generalPlaystyle, info.leaderName
    if needs.activities and Guard.Safe(info.activityIDs) then
      rec.activityNames = {}
      for _, activityID in ipairs(info.activityIDs) do
        rec.activityNames[#rec.activityNames + 1] = activityName(api, activityID)
      end
    end
  end
  if needs.leader then
    local leader = Guard.Safe(call(api.GetSearchResultLeaderInfo, id))
    if type(leader) == "table" then
      rec.leaderClass, rec.leaderLevel, rec.leaderRoles = leader.classFilename, leader.level, leader.lfgRoles
    end
  end
  if needs.counts then
    rec.counts = call(api.GetSearchResultMemberCounts, id)
  end
  return rec
end

-- Applying ---------------------------------------------------------------------------------------------------

local function changed()
  ns.Emit("FG_LFG_FILTER_CHANGED")
end

local function redraw(browse, ids)
  browse.results = ids
  browse.totalResults = #ids
  browse:UpdateResults()
end

-- A redraw raised: the filter pauses, the unfiltered list goes back into the fields.
local function fail(browse, err)
  paused = true
  ns.Log.warn("lfg browse filter: %s", tostring(err))
  applying = true
  local list = alive(raw)
  pcall(function()
    browse.results = list
    browse.totalResults = #list
  end)
  pcall(browse.UpdateResults, browse)
  applying = false
  counts = { shown = #list, total = #list }
  ns.Notify(L["lfgb.paused"], "warning")
  changed()
end

-- Filters the list of the last search and redraws when the ids changed. In combat it waits.
function H.Apply()
  local browse = browseFrame()
  if not installed or applying or not browse or type(raw) ~= "table" then
    return
  end
  if Guard.Blocked() then
    dirty = true
    return
  end
  dirty = false
  local state = filterState()
  local live = alive(raw)
  local ids
  if state and H.Offered() and not paused then
    ids, counts = LB.Run(live, read, state)
  else
    ids, counts = live, { shown = #live, total = #live }
  end
  changed()
  if LB.Same(ids, browse.results) then
    return
  end
  applying = true
  local ok, err = pcall(redraw, browse, ids)
  applying = false
  if not ok then
    fail(browse, err)
  end
end

-- Empties the list the game draws while a search of ours runs: the ids of the old list are void by then, and a
-- row for one of them raises in Blizzard's own tooltip. The new list comes with the answer of the search.
function H.Clear()
  local browse = browseFrame()
  if not installed or applying or not browse then
    return
  end
  raw = {}
  counts = { shown = 0, total = 0 }
  if Guard.Blocked() then
    dirty = true
    return
  end
  dirty = false
  changed()
  if LB.Same({}, browse.results) then
    return
  end
  applying = true
  local ok, err = pcall(redraw, browse, {})
  applying = false
  if not ok then
    fail(browse, err)
  end
end

local function onList(browse)
  if applying then
    return
  end
  raw = copy(browse.results)
  paused = false
  H.Apply()
end

-- Install --------------------------------------------------------------------------------------------------------

function H.Install()
  if installed or not H.Offered() or H.Foreign() then
    return true
  end
  local browse = browseFrame()
  if
    not browse
    or not rawget(_G, "LFGParentFrame")
    or type(browse.UpdateResultList) ~= "function"
    or type(browse.UpdateResults) ~= "function"
    or type(hooksecurefunc) ~= "function"
  then
    return false
  end
  if not pcall(hooksecurefunc, browse, "UpdateResultList", onList) then
    return false
  end
  installed = true
  if type(browse.results) == "table" and #browse.results > 0 then
    raw = copy(browse.results)
    H.Apply()
  end
  -- The panel opens by itself only with the hook in place.
  ns.Emit("FG_LFG_FILTER_INSTALLED")
  return true
end

-- Never synchronous: see the taint rules above. Without a timer nothing is installed. Frames that are not there
-- yet are tried again a few times, and every opening of the panel asks again (H.Ensure).
local function scheduleInstall(tries)
  local timer = rawget(_G, "C_Timer")
  if type(timer) ~= "table" or type(timer.After) ~= "function" or pending then
    return
  end
  pending = true
  pcall(timer.After, tries and RETRY_DELAY or INSTALL_DELAY, function()
    pending = false
    local _, done = ns.Safe("lfg-browse-install", H.Install)
    if done == false and (tries or 0) < RETRIES then
      scheduleInstall((tries or 0) + 1)
    end
  end)
end

-- Installs when that did not happen yet (the player opens the panel or the group finder).
function H.Ensure()
  if not installed then
    scheduleInstall()
  end
end

function H.DiagLine()
  return string.format(
    "lfg filter: hook=%s offered=%s foreign=%s paused=%s list=%d/%d",
    installed and "yes" or "no",
    H.Offered() and "yes" or "no",
    H.Foreign() and "yes" or "no",
    paused and "yes" or "no",
    counts.shown,
    counts.total
  )
end

-- A stored state from an older or damaged file is repaired once, then the hook is scheduled.
ns.On("PLAYER_LOGIN", function()
  local state = filterState()
  if state then
    LB.Clean(state)
  end
  scheduleInstall()
end)

ns.On("ADDON_LOADED", function(_, name)
  if name == BLIZZARD_ADDON then
    scheduleInstall()
  end
end)

-- The listing of a result changed (delisted, new members) without a new list from Blizzard.
ns.On("LFG_LIST_SEARCH_RESULT_UPDATED", function()
  if not installed then
    return
  end
  ns.Debounce("lfg-browse-reapply", REAPPLY_DELAY, function()
    local browse = browseFrame()
    if browse and browse:IsVisible() then
      H.Apply()
    end
  end)
end)

-- The answer of any search, Blizzard's own or the panel's.
for _, event in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_FAILED" }) do
  ns.On(event, function()
    searched = true
    changed()
  end)
end

ns.On("PLAYER_REGEN_ENABLED", function()
  if dirty then
    H.Apply()
  end
end)

-- The card switch: on installs (when the frames exist), off puts the unfiltered list back.
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path ~= "settings.lfgPanel" then
    return
  end
  if installed then
    H.Apply()
  else
    scheduleInstall()
  end
end)
