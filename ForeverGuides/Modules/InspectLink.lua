-- Side tab at the right edge of the inspect window (InspectFrame, load on demand with
-- Blizzard_InspectUI): same look and tooltip as the tabs of the other windows (B.CreateSideTab).
-- It sits outside the window at the lower right corner, clear of the title bar, the portrait and the
-- slots; both it and the short view (InspectPage), which spans the whole height of the window on its
-- right, are anchored to the window itself, never to each other. The click opens the page Target() names.
--
-- The side tabs of Blizzard and our own tab make room for the short view: while it is shown,
-- K.Shift(width) moves them to its right (the anchors keep their original offsets, only x grows),
-- K.Shift(nil) puts them back. Nothing moves in combat, the move waits for PLAYER_REGEN_ENABLED.
-- Blizzard's rebuild of its tabs is caught by hooks that check the anchors again.
local _, ns = ...

local K = {}
ns.InspectLink = K

ns.AddLocale("enUS", {
  ["inspect.tab"] = "Forever Guides: Inspect",
  ["inspect.tab.tip"] = "Opens the inspect page of the addon.",
})
ns.AddLocale("deDE", {
  ["inspect.tab"] = "Forever Guides: Betrachten",
  ["inspect.tab.tip"] = "Öffnet die Betrachten-Seite des Addons.",
})

local TAB_INSET, TAB_RISE = 4, 48 -- outside the right edge, lifted over the bottom edge
local TAB_SIZE = 52 -- as every side tab (BlizzardLinks)
local TAB_GAP = 2 -- between the short view and the tabs moved behind it
local SCAN_RETRY, SCAN_TRIES = 0.1, 3 -- Blizzard places its tabs a moment after the window shows
local UPDATE_METHODS = { "UpdateTabs", "UpdateTabLayout" } -- methods of the window that rebuild its tabs
local tab, hooked
local shift -- width of the short view while it is shown, else nil
local ownOffset = 0 -- how far our own tab sits right of its usual spot
local records, byFrame = {}, {} -- Blizzard tabs we moved: { frame, orig, applied, dx }
local needScan, tries, status = true, 0, "idle"

K.TAB_INSET, K.TAB_GAP, K.TAB_SIZE = TAB_INSET, TAB_GAP, TAB_SIZE

-- Page id the tab opens.
function K.Target()
  return "inspect"
end

function K.Open()
  ns.Main.Show(K.Target())
end

-- Test seam.
function K.Tab()
  return tab
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function window()
  local f = rawget(_G, "InspectFrame")
  return type(f) == "table" and f or nil
end

-- Anchors of a frame as { point, rel, relPoint, x, y }, and as one comparable text.
local function snapshot(frame)
  local out = {}
  for i = 1, frame:GetNumPoints() do
    local point, rel, relPoint, x, y = frame:GetPoint(i)
    out[i] = { point, rel, relPoint, x or 0, y or 0 }
  end
  return out
end

local function signature(points)
  local out = {}
  for i, p in ipairs(points) do
    out[i] =
      string.format("%s|%s|%s|%s|%s", tostring(p[1]), tostring(p[2]), tostring(p[3]), tostring(p[4]), tostring(p[5]))
  end
  return table.concat(out, ";")
end

-- Sets the original anchors again, dx further right. An anchor to another moved tab stays as it
-- is, that tab carries it along.
local function place(rec, dx)
  local frame = rec.frame
  frame:ClearAllPoints()
  for _, p in ipairs(rec.orig) do
    local follows = type(p[2]) == "table" and byFrame[p[2]] ~= nil
    frame:SetPoint(p[1], p[2], p[3], p[4] + (follows and 0 or dx), p[5])
  end
  rec.applied = dx ~= 0 and signature(snapshot(frame)) or nil
  rec.dx = dx
end

local function excluded(frame)
  local ok, name = pcall(frame.GetName, frame)
  return frame == tab or (ok and type(name) == "string" and name:find("CloseButton$") ~= nil)
end

-- Looks for tabs we do not know yet; returns how many the geometry search found.
local function scan(win)
  local found = ns.BlizzardLinks.FindSideTabs(win, excluded)
  for _, frame in ipairs(found) do
    if not byFrame[frame] then
      local rec = { frame = frame, orig = snapshot(frame) }
      records[#records + 1] = rec
      byFrame[frame] = rec
    end
  end
  return #found
end

local function placeOwnTab(win, offset)
  if tab and offset ~= ownOffset then
    ownOffset = offset
    tab:ClearAllPoints()
    tab:SetPoint("BOTTOMLEFT", win, "BOTTOMRIGHT", TAB_INSET + offset, TAB_RISE)
  end
end

-- Brings every tab in line with the short view: moved while it is shown, back otherwise. A tab
-- whose anchors changed behind our back (Blizzard rebuilt it) takes the new anchors as its original.
function K.Sync()
  local win = window()
  if not win then
    return
  end
  if inCombat() then
    status = "waiting for the end of combat"
    return
  end
  local dx = shift and shift + TAB_GAP or 0
  if shift and needScan then
    needScan = false
    if scan(win) == 0 and #records == 0 then
      status = "no side tabs found"
      if tries < SCAN_TRIES then
        tries = tries + 1
        needScan = true
        ns.Debounce("inspect-tabs", SCAN_RETRY, K.Sync)
      end
    end
  end
  for _, rec in ipairs(records) do
    local current = signature(snapshot(rec.frame))
    if shift then
      if rec.applied ~= current then
        rec.orig = snapshot(rec.frame)
        place(rec, dx)
      elseif rec.dx ~= dx then
        place(rec, dx)
      end
    elseif rec.applied ~= nil then
      if rec.applied == current then
        place(rec, 0)
      end
      rec.applied, rec.dx = nil, nil
    end
  end
  -- The short view is as high as the window, so our tab moves behind it even when no tab of Blizzard
  -- is known (yet): sitting apart is better than lying on the view.
  placeOwnTab(win, dx)
  if not shift then
    status = "idle"
  elseif #records > 0 then
    status = string.format("%d Blizzard tabs moved by %d", #records, dx)
  end
end

-- The short view is shown with this width (the tabs move behind it), or nil when it is gone.
function K.Shift(width)
  if width == shift then
    return
  end
  if width then
    needScan, tries = true, 0
  end
  shift = width
  ns.Safe("inspect-tabs", K.Sync)
end

-- Line of the diagnostic report.
function K.Info()
  return string.format("inspect tabs: %s, %d known, short view %s", status, #records, shift and "shown" or "hidden")
end

local function rebuilt()
  ns.Safe("inspect-tabs", K.Sync)
  if shift then
    needScan = true
    ns.Debounce("inspect-tabs", SCAN_RETRY, K.Sync)
  end
end

-- Blizzard places its tabs when the window shows and when it updates them.
local function hookWindow(win)
  if hooked or type(win.HookScript) ~= "function" then
    return
  end
  hooked = true
  pcall(win.HookScript, win, "OnShow", rebuilt)
  if type(hooksecurefunc) ~= "function" then
    return
  end
  if type(rawget(_G, "InspectFrame_UpdateTabs")) == "function" then
    pcall(hooksecurefunc, "InspectFrame_UpdateTabs", rebuilt)
  end
  for _, name in ipairs(UPDATE_METHODS) do
    if type(win[name]) == "function" then
      pcall(hooksecurefunc, win, name, rebuilt)
    end
  end
end

-- Builds the tab once the window exists; in combat it waits for PLAYER_REGEN_ENABLED.
function K.Install()
  local parent = window()
  if not parent or type(ns.BlizzardLinks) ~= "table" or inCombat() then
    return
  end
  hookWindow(parent)
  if tab then
    return
  end
  tab = ns.BlizzardLinks.CreateSideTab(parent, {
    key = "inspect.tab",
    tip = "inspect.tab.tip",
    onClick = K.Open,
    point = "BOTTOMLEFT",
    rel = parent,
    relPoint = "BOTTOMRIGHT",
    x = TAB_INSET,
    y = TAB_RISE,
  })
  if shift then
    ns.Safe("inspect-tabs", K.Sync)
  end
end

ns.On("PLAYER_LOGIN", K.Install)
ns.On("ADDON_LOADED", K.Install)
ns.On("PLAYER_REGEN_ENABLED", function()
  K.Install()
  K.Sync()
end)
