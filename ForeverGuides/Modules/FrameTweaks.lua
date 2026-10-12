-- Move and zoom Blizzard windows and remember where they were left (setting frameTweaks). Only
-- post hooks and method calls on the windows: nothing of Blizzard's code is replaced and no field of
-- a window is written. Every game call runs under pcall, so a window that behaves differently in
-- some client costs that window, never an error. In combat a window is left alone when it is
-- protected (or when "no changes in combat" is on) and the action waits for PLAYER_REGEN_ENABLED.
-- Windows are found in the fixed list, UIPanelWindows, UISpecialFrames and by a signature scan.
-- Every window also gets an invisible drag handle over its top edge, because the title strip of
-- some windows lies under children that catch the mouse.
-- The bar below a window (opacity, zoom, resize grip) is Modules/FrameTweaksBar.lua, the background
-- opacity Modules/FrameTweaksAlpha.lua, the settings page Modules/FrameTweaksPage.lua.
-- Per window the player can switch single features off (settings.frameOff), ignore a window
-- (frameIgnore) or add one the detection missed (frameAdd).
-- Pure parts (window lists, position format, zoom math, clamping, queue, export): Modules/FrameTweaksLogic.lua.
local _, ns = ...
local FL, L = ns.FrameTweaksLogic, ns.L

local FT = {}
ns.FrameTweaks = FT

ns.AddLocale("enUS", {
  ["tweaks.usage"] = "Usage: /fg fenster list | reset [name] | open",
  ["tweaks.listHead"] = "Windows: %d active, %d moved",
  ["tweaks.listKnown"] = "Active: %s",
  ["tweaks.listAuto"] = "Detected: %s",
  ["tweaks.zoomLine"] = "%s: zoom %d %%",
  ["tweaks.conflict"] = "Other move addon loaded: %s",
  ["tweaks.resetAll"] = "Window positions reset: %d",
  ["tweaks.resetOne"] = "Window position reset: %s",
  ["tweaks.noSaved"] = "No saved position: %s",
})
ns.AddLocale("deDE", {
  ["tweaks.usage"] = "Benutzung: /fg fenster liste | reset [Name] | open",
  ["tweaks.listHead"] = "Fenster: %d aktiv, %d verschoben",
  ["tweaks.listKnown"] = "Aktiv: %s",
  ["tweaks.listAuto"] = "Erkannt: %s",
  ["tweaks.zoomLine"] = "%s: Zoom %d %%",
  ["tweaks.conflict"] = "Anderes Move-Addon geladen: %s",
  ["tweaks.resetAll"] = "Fensterpositionen zurückgesetzt: %d",
  ["tweaks.resetOne"] = "Fensterposition zurückgesetzt: %s",
  ["tweaks.noSaved"] = "Keine Position gespeichert: %s",
})

local MOVE_ADDONS = { "BlizzMove", "MoveAnything", "ForeverMove", "ElvUI" }
local ADDON_NAME = "ForeverGuides"

local weak = { __mode = "k" }
local hooked = setmetatable({}, weak) -- frame -> name
local dragging = setmetatable({}, weak) -- frame -> true while the user moves it
local handles = setmetatable({}, weak) -- frame -> its drag handle
local restoring = setmetatable({}, weak) -- frame -> true while we set its points
local known = {} -- name -> frame
local auto = {} -- name -> true for windows found by UISpecialFrames or the signature scan
local original = {} -- saved key -> points the client gave the window, for reset
local originalScale = {} -- name -> zoom the window had before we changed it
local pendingScale = {} -- name -> zoom to apply after combat (true: the saved one)
local queue = FL.NewQueue()
local started, panelHooked, panelShown, scanQueued, scanDeferred = false, false, false, false, false
local SCAN_CAP = 60000

-- Tells the bar below a window that something changed (it may not be loaded in a test).
local function notify(name)
  local bar = ns.FrameTweaksBar
  if bar and type(bar.Refresh) == "function" then
    pcall(bar.Refresh, name)
  end
end

local function guard(fn, ...)
  return pcall(fn, ...)
end

local function settings()
  return ns.db and ns.db.settings
end

local function enabled()
  local s = settings()
  return s ~= nil and s.frameTweaks ~= false
end

local function mapZoom()
  local s = settings()
  return s ~= nil and s.frameMapZoom == true
end

local function combatSafe()
  local s = settings()
  return s == nil or s.frameTweaksCombat ~= false
end

local function clampOn()
  local s = settings()
  return s == nil or s.frameClamp ~= false
end

-- Is the name in one of the player's name sets (frameIgnore, frameAdd)?
local function listed(key, name)
  local s = settings()
  local set = s and s[key]
  return type(set) == "table" and set[name] == true
end

local function ignored(name)
  return listed("frameIgnore", name)
end

local function addedByPlayer(name)
  return listed("frameAdd", name)
end

local FEATURES = { move = true, zoom = true, alpha = true }

local function featureOff(name, key)
  local s = settings()
  local off = s and s.frameOff
  local entry = type(off) == "table" and off[name]
  return type(entry) == "table" and entry[key] == true
end

-- The switch is on, the window is not ignored and the feature is not off for it.
local function featureOn(name, key)
  return enabled() and not ignored(name) and not featureOff(name, key)
end

local function configure()
  local s = settings() or {}
  FL.Configure({
    zoomStep = s.frameZoomStep,
    zoomMin = s.frameZoomMin,
    zoomMax = s.frameZoomMax,
    alphaStep = s.frameAlphaStep,
    alphaMin = s.frameAlphaMin,
  })
end

-- The saved positions; a damaged value of the setting is replaced by an empty table.
local function saved()
  local s = settings()
  if not s then
    return {}
  end
  if type(s.frames) ~= "table" then
    s.frames = {}
  end
  return s.frames
end

local function nameOf(frame)
  local ok, name = pcall(function()
    return frame:GetName()
  end)
  return ok and type(name) == "string" and name or nil
end

local function isWindow(frame)
  return type(frame) == "table" and type(frame.GetName) == "function" and type(frame.StartMoving) == "function"
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function isProtected(frame)
  local ok, value = pcall(function()
    return frame:IsProtected()
  end)
  return ok and value == true
end

local function maximized(name, frame)
  if not FL.MAXIMIZABLE[name] then
    return false
  end
  local ok, value = pcall(function()
    return frame:IsMaximized()
  end)
  return ok and value == true
end

-- Key of the saved data of a window in its present state.
local function keyOf(name, frame)
  return FL.StateKey(name, maximized(name, frame))
end

local function canTouch(name, frame)
  if not inCombat() then
    -- A restriction (instance map, encounter) protects the window for addons without combat lockdown.
    return not isProtected(frame) or ns.ProtectedAllowed(frame)
  end
  return FL.CanTouch(true, FL.Protected(name) or isProtected(frame), combatSafe())
end

-- Points of a window as the client has them now.
local function snapshot(frame)
  local list = {}
  local count = type(frame.GetNumPoints) == "function" and frame:GetNumPoints() or 1
  for i = 1, count do
    local point, rel, relPoint, x, y = frame:GetPoint(i)
    if point == nil then
      break
    end
    list[#list + 1] = { point, rel, relPoint, x, y }
  end
  return list
end

local function placePoints(frame, list)
  restoring[frame] = true
  local ok = pcall(function()
    frame:ClearAllPoints()
    for _, a in ipairs(list) do
      frame:SetPoint(a[1], a[2], a[3], a[4], a[5])
    end
  end)
  restoring[frame] = nil
  return ok
end

local function anchorFrame(name, frame)
  local rel = name and rawget(_G, name)
  if type(rel) == "table" and rel ~= frame and type(rel.GetPoint) == "function" then
    return rel
  end
  return UIParent
end

local function place(name, frame, entry)
  local rel = anchorFrame(entry.r, frame)
  restoring[frame] = true
  local ok = pcall(function()
    frame:ClearAllPoints()
    frame:SetPoint(entry.p, rel, entry.rp, entry.x, entry.y)
  end)
  restoring[frame] = nil
  if not ok then
    -- A frame without any anchor would vanish: go back to where the client had it.
    local before = original[name]
    if not (before and placePoints(frame, before)) then
      placePoints(frame, { { "CENTER", UIParent, "CENTER", 0, 0 } })
    end
  end
  return ok
end

local function sizeOf(frame)
  return {
    w = frame:GetWidth(),
    h = frame:GetHeight(),
    sw = UIParent:GetWidth(),
    sh = UIParent:GetHeight(),
    scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale(),
  }
end

local function clamp(frame, entry)
  if not clampOn() then
    return entry
  end
  local ok, out = pcall(function()
    return (FL.Clamp(entry, sizeOf(frame)))
  end)
  return ok and out or entry
end

-- Zoom -------------------------------------------------------------------------------------------

local function scaleAllowed(name)
  return (not FL.BAR_OPT_IN[name] or mapZoom()) and featureOn(name, "zoom")
end

-- The zoom a window should have now: the saved one, the original one while it must not be zoomed
-- (maximized map, zoom switched off). Nil when we never zoomed it.
local function targetScale(name, frame)
  if not scaleAllowed(name) or maximized(name, frame) then
    return originalScale[name]
  end
  local raw = saved()[name]
  return type(raw) == "table" and FL.CleanScale(raw.scale) or originalScale[name]
end

local function setScaleRaw(name, frame, value)
  if originalScale[name] == nil then
    originalScale[name] = frame:GetScale()
  end
  restoring[frame] = true
  local ok = pcall(frame.SetScale, frame, value)
  restoring[frame] = nil
  return ok
end

-- Puts the window at the zoom it should have; in combat a protected window waits.
local function syncScale(name, frame)
  if not enabled() then
    return
  end
  local want = targetScale(name, frame)
  local ok, current = pcall(frame.GetScale, frame)
  if want == nil or not ok or type(current) ~= "number" or math.abs(current - want) < 0.001 then
    return
  end
  if not canTouch(name, frame) then
    pendingScale[name] = pendingScale[name] or true
    return
  end
  setScaleRaw(name, frame, want)
end

-- Top left corner of the window on the screen, in the screen units of UIParent.
local function cornerOf(frame)
  local size = sizeOf(frame)
  local point, rel, relPoint, x, y = frame:GetPoint(1)
  if point and (rel == nil or rel == UIParent) then
    local left, top = FL.Corner({ p = point, rp = relPoint, x = x, y = y }, size)
    if left then
      return left, top
    end
  end
  local left, top = frame:GetLeft(), frame:GetTop()
  if type(left) == "number" and type(top) == "number" then
    return left * size.scale, top * size.scale
  end
  return nil
end

local function store(key, entry, scale)
  local clean = entry and FL.Clean({ p = entry.p, r = entry.r, rp = entry.rp, x = entry.x, y = entry.y })
  local previous = saved()[key]
  if clean then
    clean.scale = scale
    clean.alpha = type(previous) == "table" and FL.CleanAlpha(previous.alpha) or nil
    clean.alphaMode = type(previous) == "table" and FL.CleanMode(previous.alphaMode) or nil
    saved()[key] = clean
    return
  end
  if type(previous) == "table" then
    previous.scale = scale
  else
    saved()[key] = { scale = scale }
  end
end

local function zoom(name, frame, value)
  local key = keyOf(name, frame)
  if original[key] == nil then
    original[key] = snapshot(frame)
  end
  local okCorner, left, top = pcall(cornerOf, frame)
  if not setScaleRaw(name, frame, value) then
    return nil
  end
  local entry
  if okCorner and left then
    local size = sizeOf(frame)
    entry = clamp(frame, FL.TopLeftAt(left, top, size.scale))
    place(name, frame, entry)
  end
  store(key, entry, value)
  notify(name)
  return value
end

-- Sets the zoom of a window (0.5 to 2), the top left corner stays where it is. Returns the zoom
-- and whether it waits for the end of combat, nil when the window is not handled.
function FT.SetScale(name, value)
  local frame = known[name]
  local s = FL.CleanScale(value)
  if not (frame and hooked[frame] and s and enabled() and scaleAllowed(name)) then
    return nil
  end
  if not canTouch(name, frame) then
    pendingScale[name] = s
    return s, true
  end
  pendingScale[name] = nil
  local ok, result = pcall(zoom, name, frame, s)
  return ok and result or nil, false
end

function FT.GetScale(name)
  local frame = known[name]
  if not (frame and hooked[frame]) then
    return nil
  end
  local ok, value = pcall(frame.GetScale, frame)
  return ok and type(value) == "number" and value or nil
end

-- The frame of a handled window.
function FT.Window(name)
  local frame = known[name]
  return frame and hooked[frame] and frame or nil
end

function FT.Scalable(name)
  return scaleAllowed(name) and enabled()
end

-- Is this feature (move, zoom, alpha) on for the window?
function FT.FeatureOn(name, key)
  return featureOn(name, key)
end

function FT.Ignored(name)
  return ignored(name)
end

-- For the opacity module: may the window be changed now, and the table of saved entries.
function FT.CanTouch(name)
  local frame = known[name]
  return frame ~= nil and hooked[frame] ~= nil and canTouch(name, frame)
end

function FT.SavedFrames()
  return saved()
end

-- Position -----------------------------------------------------------------------------------------

-- fresh: the client has just set the points, so they are what a reset must go back to.
local function restore(name, frame, fresh)
  if restoring[frame] or dragging[frame] or not enabled() or ignored(name) then
    return
  end
  local key = keyOf(name, frame)
  local entry = featureOn(name, "move") and FL.Clean(saved()[key]) or nil
  if not entry and targetScale(name, frame) == nil then
    notify(name)
    return
  end
  if not canTouch(name, frame) then
    queue:Add(name, "restore")
    return
  end
  if entry and (fresh or original[key] == nil) then
    original[key] = snapshot(frame)
  end
  syncScale(name, frame)
  if entry then
    place(name, frame, clamp(frame, entry))
  end
  notify(name)
end

local function save(name, frame)
  local key = keyOf(name, frame)
  local point, rel, relPoint, x, y = frame:GetPoint(1)
  local relName
  if type(rel) == "table" and rel ~= frame then
    relName = nameOf(rel)
    if not relName then
      return
    end
  end
  local entry = FL.Encode(point, relName, relPoint, x, y)
  if not entry then
    return
  end
  local fitted, moved = entry, false
  if clampOn() then
    fitted, moved = FL.Clamp(entry, sizeOf(frame))
  end
  local previous = saved()[key]
  fitted.scale = type(previous) == "table" and FL.CleanScale(previous.scale) or nil
  fitted.alpha = type(previous) == "table" and FL.CleanAlpha(previous.alpha) or nil
  fitted.alphaMode = type(previous) == "table" and FL.CleanMode(previous.alphaMode) or nil
  saved()[key] = fitted
  if moved then
    place(name, frame, fitted)
  end
end

-- The key combination that leaves the window to the game's own move (default Ctrl+Shift).
local function bothModifiers()
  return ns.Keys.Matches("frameNativeDrag")
end

local function onDragStart(name, frame)
  if dragging[frame] or not featureOn(name, "move") or bothModifiers() or not canTouch(name, frame) then
    return
  end
  local key = keyOf(name, frame)
  if saved()[key] == nil and original[key] == nil then
    original[key] = snapshot(frame)
  end
  frame:StartMoving()
  dragging[frame] = true
end

local function onDragStop(name, frame)
  if not dragging[frame] then
    return
  end
  dragging[frame] = nil
  pcall(frame.StopMovingOrSizing, frame)
  save(name, frame)
  notify(name)
end

local function usable(handle, frame)
  return type(handle) == "table"
    and handle ~= frame
    and type(handle.HookScript) == "function"
    and type(handle.RegisterForDrag) == "function"
    and type(handle.EnableMouse) == "function"
end

-- Title strips that can carry the drag (on the window and on its BorderFrame). Without one the
-- window itself, except where the body must stay free for clicks (world map): there the border.
local function dragSurfaces(name, frame)
  local out = {}
  local border = frame.BorderFrame
  for _, holder in ipairs({ frame, type(border) == "table" and border or false }) do
    for _, key in ipairs(FL.DRAG_KEYS) do
      local handle = holder and holder[key]
      if usable(handle, frame) then
        out[#out + 1] = handle
      end
    end
  end
  if #out == 0 then
    if not FL.STRIP_ONLY[name] then
      out[1] = frame
    elseif usable(border, frame) then
      out[1] = border
    end
  end
  return out
end

-- The handle over the top edge of a window: a button of our own (no field of the window is written)
-- above the window's children. It stays clear of the corners with buttons. With Ctrl+Shift it lets
-- the mouse through.
local function syncHandle(name, frame, handle)
  local left, right = FL.HandleInsets(name)
  handle:ClearAllPoints()
  handle:SetPoint("TOPLEFT", frame, "TOPLEFT", left, 0)
  handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -right, 0)
  handle:SetHeight(FL.HANDLE_HEIGHT)
  handle:SetFrameLevel(frame:GetFrameLevel() + FL.HANDLE_LEVEL)
  handle:EnableMouse(not bothModifiers() and featureOn(name, "move"))
end

-- The handle catches the mouse only while the window may be moved and no Ctrl+Shift is held.
local function syncHandleMouse(name, handle)
  pcall(handle.EnableMouse, handle, not bothModifiers() and featureOn(name, "move"))
end

local function buildHandle(name, frame)
  local handle = CreateFrame("Button", nil, frame)
  handle:RegisterForDrag("LeftButton")
  handle:SetScript("OnDragStart", function()
    guard(onDragStart, name, frame)
  end)
  handle:SetScript("OnDragStop", function()
    guard(onDragStop, name, frame)
  end)
  handles[frame] = handle
  syncHandle(name, frame, handle)
  return handle
end

-- Tooltips (by strata) and parts of other windows (a parent other than the screen) are no windows;
-- the fixed list is trusted.
local function notAWindow(name, frame)
  local ok, strata, parent = pcall(function()
    return frame:GetFrameStrata(), frame:GetParent()
  end)
  if not ok then
    return false
  end
  if FL.StrataExcluded(strata) then
    return true
  end
  return not FL.Listed(name) and parent ~= nil and parent ~= UIParent
end

local function isOwn(frame)
  local shell = ns.WindowShell
  return shell ~= nil and type(shell.Of) == "function" and shell.Of(frame) ~= nil
end

-- One hook set per window, however often a window shows up. detected: found by UISpecialFrames or
-- the signature scan instead of the lists.
local function attach(name, frame, detected)
  local added = addedByPlayer(name)
  if hooked[frame] or not enabled() or ignored(name) or not FL.Wanted(name, added) or not isWindow(frame) then
    return
  end
  if isOwn(frame) or (type(frame.IsForbidden) == "function" and frame:IsForbidden()) then
    return
  end
  if not added and notAWindow(name, frame) then
    return
  end
  known[name] = frame
  if not canTouch(name, frame) then
    queue:Add(name, "hook")
    return
  end
  hooked[frame] = name
  auto[name] = detected and not FL.Listed(name) or nil
  pcall(frame.SetMovable, frame, true)
  guard(buildHandle, name, frame)
  for _, surface in ipairs(dragSurfaces(name, frame)) do
    pcall(function()
      surface:EnableMouse(true)
      surface:RegisterForDrag("LeftButton")
      surface:HookScript("OnDragStart", function()
        guard(onDragStart, name, frame)
      end)
      surface:HookScript("OnDragStop", function()
        guard(onDragStop, name, frame)
      end)
    end)
  end
  -- The panel manager anchors a window again when it opens: put it back at once.
  pcall(hooksecurefunc, frame, "SetPoint", function()
    guard(restore, name, frame, true)
  end)
  if FL.MAXIMIZABLE[name] then
    pcall(hooksecurefunc, frame, "SynchronizeDisplayState", function()
      guard(restore, name, frame, true)
    end)
  end
  pcall(frame.HookScript, frame, "OnShow", function()
    if handles[frame] and canTouch(name, frame) then
      guard(syncHandle, name, frame, handles[frame])
    end
    if name:find("^ContainerFrame") then
      guard(restore, name, frame, false)
    else
      guard(syncScale, name, frame)
    end
  end)
  if frame:IsShown() then
    restore(name, frame, false)
  else
    guard(syncScale, name, frame)
  end
  local alpha = ns.FrameTweaksAlpha
  if alpha and type(alpha.Attach) == "function" then
    guard(alpha.Attach, name, frame)
  end
  local bar = ns.FrameTweaksBar
  if bar and type(bar.Attach) == "function" then
    guard(bar.Attach, name, frame)
  end
end

local function namesOf(list)
  local names = {}
  if type(list) == "table" then
    for _, name in pairs(list) do
      if type(name) == "string" then
        names[#names + 1] = name
      end
    end
  end
  return names
end

local function panelNames()
  local names = {}
  local panels = rawget(_G, "UIPanelWindows")
  if type(panels) == "table" then
    for name in pairs(panels) do
      if type(name) == "string" then
        names[#names + 1] = name
      end
    end
  end
  return names
end

-- The parts of a frame the signature looks at.
local function signatureOf(frame, name)
  local keys = {}
  for _, key in ipairs(FL.SIGNATURE_KEYS) do
    if type(frame[key]) == "table" then
      keys[key] = true
    end
  end
  return {
    name = name,
    rootChild = frame:GetParent() == UIParent,
    keys = keys,
    w = frame:GetWidth(),
    h = frame:GetHeight(),
    strata = frame:GetFrameStrata(),
  }
end

-- Walks all frames once for named windows that look like windows of the client.
local function signatureScan()
  local enumerate = rawget(_G, "EnumerateFrames")
  if type(enumerate) ~= "function" then
    return
  end
  if inCombat() then
    scanDeferred = true
    return
  end
  pcall(function()
    local frame, walked = enumerate(), 0
    while frame and walked < SCAN_CAP do
      walked = walked + 1
      local name = nameOf(frame)
      if name and not hooked[frame] and FL.Wanted(name) and isWindow(frame) then
        local ok, info = pcall(signatureOf, frame, name)
        if ok and FL.Signature(info) then
          guard(attach, name, frame, true)
        end
      end
      frame = enumerate(frame)
    end
  end)
end

local function scan()
  if not started or not enabled() then
    return
  end
  local panels = panelNames()
  local panelSet = {}
  for _, name in ipairs(panels) do
    panelSet[name] = true
  end
  local special = namesOf(rawget(_G, "UISpecialFrames"))
  local specialSet = {}
  for _, name in ipairs(special) do
    specialSet[name] = true
  end
  local addedSet, addedList = {}, {}
  local adds = settings() and settings().frameAdd
  for name, on in pairs(type(adds) == "table" and adds or {}) do
    if on == true and type(name) == "string" then
      addedSet[name] = true
      addedList[#addedList + 1] = name
    end
  end
  for _, name in ipairs(FL.Names(panels, special, addedList)) do
    local frame = rawget(_G, name)
    if type(frame) == "table" then
      guard(attach, name, frame, (specialSet[name] and not panelSet[name]) or addedSet[name])
    end
  end
  guard(signatureScan)
end

-- Scans soon, once for a burst of loading addons.
local function scheduleScan()
  if scanQueued then
    return
  end
  scanQueued = true
  local function run()
    scanQueued = false
    guard(scan)
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(0.5, run)
  else
    run()
  end
end

local function installPanelHook()
  if panelHooked or type(hooksecurefunc) ~= "function" then
    return
  end
  panelHooked = pcall(hooksecurefunc, "ShowUIPanel", function(frame)
    guard(function()
      if started and type(frame) == "table" then
        local name = nameOf(frame)
        if name then
          attach(name, frame)
        end
        if not panelShown then
          panelShown = true
          scheduleScan()
        end
      end
    end)
  end)
end

-- Combat ended: do what was held back.
local function flush()
  for _, item in ipairs(queue:Take()) do
    guard(function()
      local frame = known[item.name] or rawget(_G, item.name)
      if type(frame) ~= "table" then
        return
      end
      if item.action == "hook" then
        attach(item.name, frame, auto[item.name])
      elseif item.action == "restore" then
        restore(item.name, frame, false)
      else
        FT.ResetFrame(item.name, frame)
      end
    end)
  end
  local waiting = {}
  for name, value in pairs(pendingScale) do
    waiting[#waiting + 1] = { name = name, value = value }
  end
  pendingScale = {}
  for _, item in ipairs(waiting) do
    guard(function()
      if item.value == true then
        local frame = known[item.name]
        if frame then
          syncScale(item.name, frame)
        end
      else
        FT.SetScale(item.name, item.value)
      end
    end)
  end
end

-- Reset ------------------------------------------------------------------------------------------

function FT.ResetFrame(name, frame)
  local key = keyOf(name, frame)
  local before, scale = original[key], originalScale[name]
  if not before and not scale then
    return
  end
  if not canTouch(name, frame) then
    queue:Add(name, "reset")
    return
  end
  original[key], originalScale[name] = nil, nil
  if scale then
    setScaleRaw(name, frame, scale)
    originalScale[name] = nil
  end
  if before then
    placePoints(frame, before)
  end
  notify(name)
end

-- Forgets the saved position and zoom of one window and puts the window back where the client had it.
function FT.Reset(name)
  local frames = saved()
  local stateKey = FL.StateKey(name, true)
  local had = frames[name] ~= nil or frames[stateKey] ~= nil
  frames[name], frames[stateKey] = nil, nil
  pendingScale[name] = nil
  local frame = known[name]
  if frame then
    guard(FT.ResetFrame, name, frame)
  end
  if stateKey ~= name then
    original[stateKey] = nil
  end
  local alpha = ns.FrameTweaksAlpha
  if alpha and type(alpha.Apply) == "function" then
    guard(alpha.Apply, name)
  end
  return had
end

function FT.ResetAll()
  local names = {}
  for name in pairs(saved()) do
    names[#names + 1] = name
  end
  for _, name in ipairs(names) do
    FT.Reset(name)
  end
  return #names
end

-- Settings page ----------------------------------------------------------------------------------

-- Puts every handled window in line with the settings: zoom, handle, opacity, bar.
local function syncAll()
  for frame, name in pairs(hooked) do
    guard(syncScale, name, frame)
    if handles[frame] then
      syncHandleMouse(name, handles[frame])
    end
  end
  local alpha, bar = ns.FrameTweaksAlpha, ns.FrameTweaksBar
  if alpha and type(alpha.ApplyAll) == "function" then
    guard(alpha.ApplyAll)
  end
  if bar and type(bar.RefreshAll) == "function" then
    guard(bar.RefreshAll)
  end
end

-- One feature of one window on or off (bar: the bar module keeps that switch).
function FT.SetFeature(name, key, on)
  if type(name) ~= "string" or name == "" then
    return false
  end
  if key == "bar" then
    if ns.FrameTweaksBar then
      ns.FrameTweaksBar.SetEnabled(name, on == true)
    end
    return true
  end
  local s = settings()
  if not (FEATURES[key] and s) then
    return false
  end
  if type(s.frameOff) ~= "table" then
    s.frameOff = {}
  end
  local entry = s.frameOff[name]
  if on then
    if type(entry) == "table" then
      entry[key] = nil
      if next(entry) == nil then
        s.frameOff[name] = nil
      end
    end
  else
    if type(entry) ~= "table" then
      entry = {}
      s.frameOff[name] = entry
    end
    entry[key] = true
  end
  local frame = known[name]
  if frame and hooked[frame] then
    guard(function()
      if key == "move" and on then
        restore(name, frame, false)
      end
      syncScale(name, frame)
      if handles[frame] then
        syncHandleMouse(name, handles[frame])
      end
      if ns.FrameTweaksAlpha then
        ns.FrameTweaksAlpha.Apply(name)
      end
      notify(name)
    end)
  end
  return true
end

local function setName(key, name, on)
  local s = settings()
  if not s then
    return
  end
  if type(s[key]) ~= "table" then
    s[key] = {}
  end
  s[key][name] = on and true or nil
end

-- The player stops us touching a window: what we changed goes back and the window leaves the bar.
function FT.Ignore(name)
  if type(name) ~= "string" or name == "" then
    return false
  end
  setName("frameIgnore", name, true)
  setName("frameAdd", name, false)
  FT.Reset(name)
  syncAll()
  return true
end

function FT.Unignore(name)
  setName("frameIgnore", name, false)
  FT.Apply()
  return true
end

-- A window the detection missed. Returns true, or false and "excluded" for windows that never qualify.
function FT.Add(name)
  if not FL.ValidName(name) or name:find(":", 1, true) then
    return false, "excluded"
  end
  setName("frameAdd", name, true)
  setName("frameIgnore", name, false)
  FT.Apply()
  return true
end

-- Name of the window under the mouse: the topmost named frame below the screen.
local function isFrame(v)
  return type(v) == "table" and type(v.GetParent) == "function"
end

local function frameUnderMouse()
  local frame
  local foci, focus = rawget(_G, "GetMouseFoci"), rawget(_G, "GetMouseFocus")
  if type(foci) == "function" then
    local found = foci()
    frame = isFrame(found) and found or (type(found) == "table" and found[1]) or nil
  elseif type(focus) == "function" then
    frame = focus()
  end
  local top, depth = nil, 0
  while isFrame(frame) and frame ~= UIParent and depth < 40 do
    depth = depth + 1
    local name = nameOf(frame)
    if name and name ~= "WorldFrame" then
      top = name
    end
    frame = ns.SafeParent(frame)
  end
  return top
end

FT.PICK_DELAY = 3

local picking = false

-- Waits PICK_DELAY seconds so the player can point at a window, then calls done(name) with the
-- name of the window under the mouse (nil when there is none). False while a pick is running.
function FT.Pick(done)
  if picking then
    return false
  end
  picking = true
  local function run()
    picking = false
    local ok, name = pcall(frameUnderMouse)
    done(ok and name or nil)
  end
  if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
    run()
  else
    C_Timer.After(FT.PICK_DELAY, run)
  end
  return true
end

-- Rows of the window list: name, status, auto, protected, changed and the four switches.
function FT.Rows()
  local set, names = {}, {}
  local function add(name)
    if type(name) == "string" and name ~= "" and not set[name] then
      set[name] = true
      names[#names + 1] = name
    end
  end
  local addedList = {}
  local s = settings() or {}
  for _, key in ipairs({ "frameAdd", "frameIgnore" }) do
    for name, on in pairs(type(s[key]) == "table" and s[key] or {}) do
      if on == true then
        add(name)
        if key == "frameAdd" then
          addedList[#addedList + 1] = name
        end
      end
    end
  end
  -- UISpecialFrames only counts once a window was hooked (the table lists many popups).
  for _, name in ipairs(FL.Names(panelNames(), {}, addedList)) do
    add(name)
  end
  for name in pairs(known) do
    add(name)
  end
  for name in pairs(saved()) do
    add(type(name) == "string" and (name:gsub(":max$", "")) or nil)
  end
  table.sort(names)
  local rows = {}
  for _, name in ipairs(names) do
    local frame = known[name]
    local isHooked = frame ~= nil and hooked[frame] ~= nil
    local global = rawget(_G, name)
    local status = "unloaded"
    if ignored(name) then
      status = "ignored"
    elseif isHooked then
      status = addedByPlayer(name) and "added" or (auto[name] and "auto" or "active")
    elseif type(global) == "table" then
      status = "waiting"
    end
    local off = {
      move = featureOff(name, "move"),
      zoom = featureOff(name, "zoom"),
      alpha = featureOff(name, "alpha"),
      bar = type(s.frameBars) == "table" and s.frameBars[name] == false,
    }
    local hasValues = saved()[name] ~= nil or saved()[FL.StateKey(name, true)] ~= nil
    rows[#rows + 1] = {
      name = name,
      status = status,
      auto = status == "auto" or status == "added",
      protected = FL.Protected(name) or (frame ~= nil and isProtected(frame)),
      off = off,
      hasValues = hasValues,
      changed = hasValues or off.move or off.zoom or off.alpha or off.bar or status == "ignored" or status == "added",
    }
  end
  return rows
end

-- The saved values of a window for the editor: x, y, zoom percent, opacity percent (nil = default).
function FT.Values(name)
  local raw = saved()[name]
  local pos = type(raw) == "table" and FL.Clean(raw) or nil
  local scale = type(raw) == "table" and FL.CleanScale(raw.scale) or nil
  return {
    x = pos and pos.x or nil,
    y = pos and pos.y or nil,
    zoom = scale and FL.Percent(scale) or nil,
    alpha = type(raw) == "table" and FL.CleanAlpha(raw.alpha) or nil,
  }
end

local function number(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Sets what the editor holds; nil clears a value. v = { x, y, zoom (percent), alpha (percent) }.
-- Returns true, or false and "pair" (only one of x and y) or "range".
function FT.SetValues(name, v)
  if type(name) ~= "string" or name == "" or type(v) ~= "table" then
    return false, "range"
  end
  local hasPos = v.x ~= nil or v.y ~= nil
  if hasPos and (v.x == nil or v.y == nil) then
    return false, "pair"
  end
  if
    hasPos and not (number(v.x) and number(v.y) and math.abs(v.x) <= FL.MAX_OFFSET and math.abs(v.y) <= FL.MAX_OFFSET)
  then
    return false, "range"
  end
  local percent, opacity = v.zoom, v.alpha
  if
    percent ~= nil
    and not (number(percent) and percent >= FL.SCALE_MIN * 100 - 1e-6 and percent <= FL.SCALE_MAX * 100 + 1e-6)
  then
    return false, "range"
  end
  if opacity ~= nil and not (number(opacity) and opacity >= FL.ALPHA_MIN and opacity <= FL.ALPHA_MAX) then
    return false, "range"
  end
  local frames = saved()
  local frame = known[name]
  local live = frame ~= nil and hooked[frame] ~= nil
  -- The zoom goes first: it keeps the window's corner in place and so changes the offsets.
  if percent ~= nil then
    local applied = live and FT.SetScale(name, percent / 100)
    if not applied then
      local target = type(frames[name]) == "table" and frames[name] or {}
      target.scale = FL.CleanScale(percent / 100)
      frames[name] = target
    end
  end
  local entry = type(frames[name]) == "table" and frames[name] or {}
  local before = FL.Clean(entry)
  if hasPos then
    local anchor = before or { p = "TOPLEFT", r = "UIParent", rp = "BOTTOMLEFT" }
    local pos = FL.Encode(anchor.p, anchor.r ~= "UIParent" and anchor.r or nil, anchor.rp, v.x, v.y)
    entry.p, entry.r, entry.rp, entry.x, entry.y = pos.p, pos.r, pos.rp, pos.x, pos.y
  else
    entry.p, entry.r, entry.rp, entry.x, entry.y = nil, nil, nil, nil, nil
  end
  entry.alpha = opacity and FL.CleanAlpha(opacity) < FL.ALPHA_MAX and FL.CleanAlpha(opacity) or nil
  if percent == nil then
    entry.scale = nil
  end
  frames[name] = next(entry) ~= nil and entry or nil
  if live then
    guard(function()
      local key = keyOf(name, frame)
      if not hasPos and original[key] and canTouch(name, frame) then
        placePoints(frame, original[key])
        original[key] = nil
      end
      restore(name, frame, false)
    end)
  end
  if ns.FrameTweaksAlpha then
    guard(ns.FrameTweaksAlpha.Apply, name)
  end
  notify(name)
  return true
end

-- Export and import of the window values as text (Modules/FrameTweaksLogic.lua has the format).
function FT.ExportText()
  return FL.Export(saved())
end

-- Writes the usable lines of a parsed import and puts the windows in line. Returns the count.
function FT.Import(parsed)
  local frames, count = saved(), 0
  for _, item in ipairs(type(parsed) == "table" and parsed.entries or {}) do
    if FL.ValidName(item.name) then
      frames[item.name] = FL.EntryOf(item)
      count = count + 1
    end
  end
  for frame, name in pairs(hooked) do
    guard(restore, name, frame, false)
    if ns.FrameTweaksAlpha then
      guard(ns.FrameTweaksAlpha.Apply, name)
    end
    notify(name)
  end
  return count
end

-- Commands ---------------------------------------------------------------------------------------

local function loadedMoveAddons()
  local fn = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
  local out = {}
  if type(fn) == "function" then
    for _, name in ipairs(MOVE_ADDONS) do
      local ok, loaded = pcall(fn, name)
      if ok and loaded then
        out[#out + 1] = name
      end
    end
  end
  return out
end

-- Names of other move addons that are loaded.
function FT.Conflicts()
  return loadedMoveAddons()
end

function FT.List()
  local active = {}
  for _, name in pairs(hooked) do
    active[#active + 1] = name
  end
  table.sort(active)
  local names = FL.SavedNames(saved())
  ns.Notify.chat(string.format(L["tweaks.listHead"], #active, #names))
  for _, name in ipairs(names) do
    ns.Notify.chat(string.format("%s: %s", name, FL.Describe(FL.Clean(saved()[name]))))
  end
  local scaled = {}
  for name, raw in pairs(saved()) do
    local value = type(name) == "string" and type(raw) == "table" and FL.CleanScale(raw.scale)
    if value then
      scaled[#scaled + 1] = string.format(L["tweaks.zoomLine"], name, FL.Percent(value))
    end
  end
  table.sort(scaled)
  for _, line in ipairs(scaled) do
    ns.Notify.chat(line)
  end
  if #active > 0 then
    ns.Notify.chat(string.format(L["tweaks.listKnown"], table.concat(active, ", ")))
  end
  local detected = {}
  for _, name in ipairs(active) do
    if auto[name] then
      detected[#detected + 1] = name
    end
  end
  if #detected > 0 then
    ns.Notify.chat(string.format(L["tweaks.listAuto"], table.concat(detected, ", ")))
  end
  local others = loadedMoveAddons()
  if #others > 0 then
    ns.Notify.chat(string.format(L["tweaks.conflict"], table.concat(others, ", ")))
  end
end

-- Exact name first, then without regard to case.
local function findName(wanted)
  local lower = wanted:lower()
  for _, source in ipairs({ saved(), known }) do
    if source[wanted] ~= nil then
      return wanted
    end
    for name in pairs(source) do
      if type(name) == "string" and name:lower() == lower then
        return name
      end
    end
  end
  return nil
end

function FT.Slash(rest)
  local sub, arg = (rest or ""):match("^(%a*)%s*(.-)$")
  sub = sub:lower()
  if sub == "list" or sub == "liste" then
    FT.List()
  elseif sub == "reset" and arg == "" then
    ns.Notify(string.format(L["tweaks.resetAll"], FT.ResetAll()), "success")
  elseif sub == "reset" then
    local name = findName(arg) or arg
    if FT.Reset(name) then
      ns.Notify(string.format(L["tweaks.resetOne"], name), "success")
    else
      ns.Notify(string.format(L["tweaks.noSaved"], arg), "warning")
    end
  elseif sub == "open" or sub == "seite" then
    ns.Main.Show("windows")
  else
    ns.Notify.chat(L["tweaks.usage"])
  end
end

-- Start ------------------------------------------------------------------------------------------

-- Switch or setting changed: takes effect at once. Switching off only stops restoring and dragging.
function FT.Apply()
  guard(function()
    configure()
    if started then
      installPanelHook()
      scan()
      flush()
      syncAll()
    end
  end)
end

-- Steps and limits of zoom and opacity from the settings page.
local LIMIT_PATHS = {
  ["settings.frameZoomStep"] = true,
  ["settings.frameAlphaStep"] = true,
  ["settings.frameZoomMin"] = true,
  ["settings.frameZoomMax"] = true,
  ["settings.frameAlphaMin"] = true,
  ["settings.frameAlphaMode"] = true,
}

ns.On("PLAYER_LOGIN", function()
  started = true
  FT.Apply()
end)
ns.On("ADDON_LOADED", function(_, name)
  if name ~= ADDON_NAME then
    scheduleScan()
  end
end)
ns.On("MODIFIER_STATE_CHANGED", function()
  for frame, handle in pairs(handles) do
    syncHandleMouse(hooked[frame], handle)
  end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  flush()
  if scanDeferred then
    scanDeferred = false
    scheduleScan()
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.frameTweaks" or path == "settings.frameTweaksCombat" then
    FT.Apply()
  elseif LIMIT_PATHS[path] then
    configure()
    syncAll()
  elseif path == "settings.frameMapZoom" then
    local frame = known.WorldMapFrame
    if frame and hooked[frame] then
      guard(syncScale, "WorldMapFrame", frame)
      notify("WorldMapFrame")
    end
  end
end)
