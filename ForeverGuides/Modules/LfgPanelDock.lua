-- Docks the filter panel (Modules/LfgFilterPanel.lua) to the right edge of Blizzard's group finder window: the
-- panel sits flush there and Blizzard's column of side tabs (ListingTab, BrowsingTab, WhoListingTab) moves to the
-- right edge of the panel while the panel shows. Only the first tab is anchored anew, the other two hang on it, and
-- the tab of ours (Modules/BlizzardLinks.lua) follows through its own column logic.
--
-- Rules: the anchor the tab had is kept in a table of ours (never written into a Blizzard frame) and put back when
-- the panel hides, the setting goes off or the filter is off. Only ClearAllPoints and SetPoint, never in combat (the
-- work waits for PLAYER_REGEN_ENABLED), no Blizzard function replaced or hooked. A tab whose anchor is not
-- Blizzard's own (another add-on moved it) keeps the old layout, and an anchor someone else changed while docked is
-- left alone. A failing call, or a blocked action of this add-on while docked, ends the docking for the session.
local addonName, ns = ...
local L, H = ns.L, ns.LfgBrowseFilter

ns.AddLocale("enUS", {
  ["lfgd.paused"] = "Docking paused",
})
ns.AddLocale("deDE", {
  ["lfgd.paused"] = "Andocken pausiert",
})

local D = {}
ns.LfgPanelDock = D

local TAB_KEYS = { "ListingTab", "BrowsingTab", "WhoListingTab" }
local SLACK = 8 -- a plausible original starts at most this far from the window edge
local MAX_DROP = 200 -- and at most this far below its top

-- Anchor of a tab before the first move, by frame.
local originals = setmetatable({}, { __mode = "k" })
local docked, dockedTo -- the first tab while it hangs on the panel, and the panel
local disabled = false -- session switch after a failure
local pending = false -- a change waits for the end of combat

local function window()
  local frame = rawget(_G, "LFGParentFrame")
  return type(frame) == "table" and frame or nil
end

-- Blizzard's three right tabs in order, nil when one is missing.
local function tabsOf(win)
  local out = {}
  for i, key in ipairs(TAB_KEYS) do
    local tab = win and rawget(win, key)
    if type(tab) ~= "table" or type(tab.GetPoint) ~= "function" then
      return nil
    end
    out[i] = tab
  end
  return out
end

-- The only anchor of a frame, nil for none or several.
local function anchorOf(frame)
  local okCount, count = pcall(frame.GetNumPoints, frame)
  if not okCount or count ~= 1 then
    return nil
  end
  local ok, point, rel, relPoint, x, y = pcall(frame.GetPoint, frame, 1)
  if not ok or type(x) ~= "number" or type(y) ~= "number" then
    return nil
  end
  return { point, rel, relPoint, x, y }
end

local function same(a, b)
  for i = 1, 5 do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

-- Blizzard's layout: the first tab hangs at the top right corner of the window, each next one under the one before.
local function plausible(list, win)
  local first = anchorOf(list[1])
  if
    not (
      first
      and first[1] == "TOPLEFT"
      and first[2] == win
      and first[3] == "TOPRIGHT"
      and math.abs(first[4]) <= SLACK
      and first[5] < 0
      and first[5] > -MAX_DROP
    )
  then
    return false
  end
  for i = 2, #list do
    local anchor = anchorOf(list[i])
    if not (anchor and anchor[2] == list[i - 1]) then
      return false
    end
  end
  return true
end

local function refreshLinks()
  local links = ns.BlizzardLinks
  if links and links.Discover then
    links.Discover("lfg dock")
  end
end

local function combat()
  return InCombatLockdown ~= nil and InCombatLockdown() == true
end

-- Puts the first tab back where Blizzard had it.
local function restore(first)
  local o = originals[first]
  if o then
    first:ClearAllPoints()
    first:SetPoint(o[1], o[2], o[3], o[4], o[5])
    originals[first] = nil
  end
  docked, dockedTo = nil, nil
end

local function dock(first, panel, o)
  originals[first] = o
  first:ClearAllPoints()
  first:SetPoint("TOPLEFT", panel, "TOPRIGHT", o[4], o[5])
  docked, dockedTo = first, panel
end

-- Ends the docking for this session: originals back (after the combat when needed), one log line, one notice.
local function giveUp(reason)
  if disabled then
    return
  end
  disabled = true
  ns.Log.warn("lfg dock: %s", tostring(reason))
  ns.Notify(L["lfgd.paused"], "warning")
  if combat() then
    pending = true
    return
  end
  local first = docked or next(originals)
  if first then
    pcall(restore, first)
  end
  docked, dockedTo = nil, nil
  refreshLinks()
end

-- Whether docking is allowed now: the setting, no failure this session, not LFG Filter Forever.
function D.Enabled()
  local settings = ns.db and ns.db.settings
  return not disabled and not (settings and settings.lfgPanelDock == false) and not H.Foreign()
end

-- True while the tabs hang on the panel.
function D.Docked()
  return docked ~= nil
end

-- The panel while the tabs hang on it, else nil.
function D.DockFrame()
  return dockedTo
end

-- Blizzard's three tabs (empty when the structure is not there).
function D.Tabs()
  return tabsOf(window()) or {}
end

local function sync(panel)
  local win = window()
  local list = tabsOf(win)
  if not (panel and list and D.Enabled()) then
    if docked then
      restore(docked)
      refreshLinks()
    end
    return
  end
  local first, now = list[1], anchorOf(list[1])
  if docked then
    local o = originals[docked]
    if docked ~= first or not (now and o) then
      -- Another frame or no anchor: not ours to repair.
      docked, dockedTo, originals[docked] = nil, nil, nil
      return
    end
    if same(now, { "TOPLEFT", panel, "TOPRIGHT", o[4], o[5] }) then
      return
    end
    if same(now, o) then
      -- Blizzard anchored it back: once more, no loop (Sync runs once per call).
      dock(first, panel, o)
      return
    end
    -- Someone else moved it: leave it to them.
    docked, dockedTo, originals[first] = nil, nil, nil
    return
  end
  if plausible(list, win) then
    dock(first, panel, now)
    refreshLinks()
  end
end

-- The panel frame while the panel shows, nil while it hides or does not exist. Returns whether the tabs hang on it.
function D.Sync(panel)
  if combat() then
    pending = true
    return D.Docked()
  end
  local ok, err = pcall(sync, panel)
  if not ok then
    giveUp(err)
  end
  return D.Docked()
end

ns.On("PLAYER_REGEN_ENABLED", function()
  if pending then
    pending = false
    if ns.LfgFilterPanel then
      ns.Safe("lfg-dock", ns.LfgFilterPanel.Update)
    end
  end
end)

-- The client names the add-on and the function it refused. The search of the panel has its own handling.
ns.On("ADDON_ACTION_BLOCKED", function(_, blockedAddon, func)
  if not docked or blockedAddon ~= addonName or tostring(func):find("Search", 1, true) then
    return
  end
  local search = ns.LfgBrowseSearch
  if search and search.Busy() then
    return
  end
  giveUp("blocked " .. tostring(func))
  -- The panel leaves the flush position at once.
  if ns.LfgFilterPanel and not pending then
    ns.Safe("lfg-dock", ns.LfgFilterPanel.Update)
  end
end)
