-- The mouse cursor ring (ns.Cursor): one frame that follows the cursor and draws the active canvas layout
-- (Modules/CursorLogic.lua, CursorElements.lua, CanvasRender). One switch, settings.cursorRing.enabled:
-- while it is off there is no frame, no event and no OnUpdate. While on, the events below keep a small
-- state (combat, instance, target, mount, vehicle, mouselook) that the rules read; the frame only runs
-- OnUpdate while it is shown and the only call per frame is GetCursorPosition. The ring is a plain
-- frame without mouse and keyboard, so it works in combat.
-- Settings: ns.db.settings.cursorRing = { enabled, strata, mouselook, combatOnly, instanceOnly, needsTarget,
-- hideMounted, hideInVehicle, layoutId, layouts = { [id] = layout } }, all layouts account wide.
local _, ns = ...
local L, CU, CR, E = ns.L, ns.CursorLogic, ns.CanvasRender, ns.CursorElements

local C = {}
ns.Cursor = C

local EVENTS = {
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
  "PLAYER_TARGET_CHANGED",
  "PLAYER_STARTED_LOOKING",
  "PLAYER_STOPPED_LOOKING",
  "PLAYER_MOUNT_DISPLAY_CHANGED",
  "PLAYER_ENTERING_WORLD",
  "LOADING_SCREEN_ENABLED",
  "LOADING_SCREEN_DISABLED",
  "UI_SCALE_CHANGED",
  "DISPLAY_SIZE_CHANGED",
}
local UNIT_EVENTS = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }
C.EVENTS, C.UNIT_EVENTS = EVENTS, UNIT_EVENTS

-- The game's own pointer image, drawn at the hotspot in the editor when the client knows the file.
local POINTER = "Interface\\Cursor\\Point"
local POINTER_SIZE, POINTER_TIP = 32, 0.04

ns.AddLocale("enUS", {
  ["cursor.edit.title"] = "Mouse cursor ring layout",
  ["cursor.edit.missing"] = "The layout editor is not available.",
  ["cursor.slash.on"] = "Mouse cursor ring: on.",
  ["cursor.slash.off"] = "Mouse cursor ring: off.",
  ["cursor.slash.reset"] = "Mouse cursor ring options reset. Your layouts stay as they are.",
  ["cursor.slash.usage"] = "/fg cursor [on | off | edit | reset]",
  ["binding.cursorRing"] = "Mouse cursor ring on or off",
})
ns.AddLocale("deDE", {
  ["cursor.edit.title"] = "Layout des Mauszeiger-Rings",
  ["cursor.edit.missing"] = "Der Layout-Editor ist nicht verfügbar.",
  ["cursor.slash.on"] = "Mauszeiger-Ring: an.",
  ["cursor.slash.off"] = "Mauszeiger-Ring: aus.",
  ["cursor.slash.reset"] = "Optionen des Mauszeiger-Rings zurückgesetzt. Deine Layouts bleiben unverändert.",
  ["cursor.slash.usage"] = "/fg mauszeiger [an | aus | edit | reset]",
  ["binding.cursorRing"] = "Mauszeiger-Ring ein oder aus",
})

-- Settings -------------------------------------------------------------------------------------------

local function defaults()
  return ns.Store.defaults.settings.cursorRing
end

local function rawSettings()
  local s = ns.db.settings
  if type(s.cursorRing) ~= "table" then
    s.cursorRing = {}
  end
  return s.cursorRing
end

-- The layouts of the ring (Modules/LayoutSet.lua), seeded from the presets on first use.
local LAYOUTS = ns.LayoutSet.New({
  id = "cursor",
  path = "settings.cursorRing",
  get = rawSettings,
  defaults = defaults,
  maxLayouts = 30,
  presets = function()
    return { ids = CU.PRESET_IDS, build = CU.Preset }
  end,
})
C.LayoutSet = LAYOUTS
C.EnsureLayouts = LAYOUTS.EnsureLayouts
C.Layouts = LAYOUTS.Layouts
C.Layout = LAYOUTS.Layout
C.SetLayout = LAYOUTS.SetLayout
C.Manager = LAYOUTS.Manager

-- The settings with every field valid; layoutId names a stored layout.
function C.Config()
  local raw = ns.db and ns.db.settings.cursorRing
  raw = type(raw) == "table" and raw or {}
  local cfg = CU.Clean(raw)
  cfg.layouts, cfg.layoutId = LAYOUTS.State(raw)
  return cfg
end

local function set(key, value)
  ns.Store.set("settings.cursorRing." .. key, value)
end

function C.IsEnabled()
  return ns.db ~= nil and C.Config().enabled
end

function C.SetEnabled(on)
  if ns.db and (on == true) ~= C.IsEnabled() then
    set("enabled", on == true)
  end
end

function C.Enable()
  C.SetEnabled(true)
end

function C.Disable()
  C.SetEnabled(false)
end

function C.Toggle()
  C.SetEnabled(not C.IsEnabled())
end

-- Back to the default options. The layouts and the on/off switch stay.
function C.ResetOptions()
  local d = defaults()
  for _, key in ipairs({ "strata", "mouselook", unpack(CU.RULES) }) do
    set(key, d[key])
  end
end

-- Game readings -------------------------------------------------------------------------------------------

-- A yes/no answer of a game function: false when it is missing or fails.
local function flag(name, arg)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then
    return false
  end
  local ok, value = pcall(function()
    return fn(arg) and true or false
  end)
  return ok and value
end

-- The game's own answer about mouselook: its API where there is one, the right button otherwise.
local function readMouselook()
  return flag("IsMouselooking") or flag("IsMouseButtonDown", "RightButton")
end

local function now()
  local fn = rawget(_G, "GetTime")
  return type(fn) == "function" and fn() or 0
end

-- Runtime ------------------------------------------------------------------------------------------------

local frame, watcher
local running = false -- events registered: the ring is switched on
local editing = false -- the editor shows the ring at the real cursor
local loading = false
local visible = false
local centred = false
local confirmed = false
local appliedLook = false
local rules = CU.Clean({})
local state = { combat = false, instance = false, target = false, mounted = false, vehicle = false, mouselook = false }
local look = CU.NewMouselook(now)
local hotDX, hotDY = 0, 0
local lastX, lastY, lastScale

local function invalidate()
  lastX, lastY, lastScale = nil, nil, nil
end

local function syncState()
  state.combat = flag("InCombatLockdown")
  state.instance = flag("IsInInstance")
  state.target = flag("UnitExists", "target")
  state.mounted = flag("IsMounted")
  state.vehicle = flag("UnitInVehicle", "player")
  look.Resync(readMouselook())
  confirmed = false
end

-- Puts the center of the frame so that the hotspot of the layout is on the cursor (or on the middle of
-- the screen). Does nothing when the rounded position and the scale are the ones of the last call.
local function follow()
  local fn = rawget(_G, "GetCursorPosition")
  if type(fn) ~= "function" then
    return
  end
  local x, y = fn()
  local scale = UIParent:GetEffectiveScale()
  if centred then
    x, y = UIParent:GetWidth() * scale / 2, UIParent:GetHeight() * scale / 2
  end
  local px, py = CU.Place(x, y, scale, hotDX, hotDY)
  if not px or (px == lastX and py == lastY and scale == lastScale) then
    return
  end
  lastX, lastY, lastScale = px, py, scale
  frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px, py)
end

local refresh

local function onUpdate()
  if look.Active() ~= appliedLook then
    refresh()
  end
  follow()
end

local function show(on)
  if on == visible then
    return
  end
  visible = on
  if on then
    -- Jump to the cursor first: the ring never shows at an old place.
    invalidate()
    follow()
    frame:SetScript("OnUpdate", onUpdate)
    frame:Show()
  else
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
  end
end

-- Mouselook counts once it has lasted the hysteresis; the first time it does, the game is asked whether it
-- really is on, so a lost STOPPED event cannot hide the ring for good.
local function lookingNow()
  local active = look.Active()
  if active and not confirmed then
    confirmed = true
    if not readMouselook() then
      look.Stop()
      active = false
    end
  end
  return active
end

-- Applies the rules to the current state: shows or hides the ring and moves it to the middle of the screen
-- or back to the cursor.
function refresh()
  if not frame then
    return
  end
  local looking = lookingNow()
  appliedLook = looking
  state.mouselook = looking
  local want, middle = false, false
  if editing then
    want = true
  elseif running and not loading then
    want, middle = CU.Visible(rules, state)
  end
  if middle ~= centred then
    centred = middle
    invalidate()
  end
  show(want)
end

local function redraw()
  local layout = LAYOUTS.Layout()
  CR.Draw(frame, layout, E.Types(), { host = "cursor", editor = false, reduceMotion = ns.Theme.reduceMotion() })
  hotDX, hotDY = CU.HotOffset(layout)
  invalidate()
  if visible then
    follow()
  end
end

local function ensureFrame()
  if frame then
    return
  end
  frame = CreateFrame("Frame", nil, UIParent)
  frame:EnableMouse(false)
  frame:SetClampedToScreen(false)
  frame:SetScale(1)
  frame:Hide()
end

local function teardown()
  if not frame then
    return
  end
  visible = false
  frame:SetScript("OnUpdate", nil)
  frame:Hide()
  CR.Clear(frame)
end

local function onEvent(_, event, unit)
  if event == "PLAYER_REGEN_DISABLED" then
    state.combat = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    state.combat = false
  elseif event == "PLAYER_TARGET_CHANGED" then
    state.target = flag("UnitExists", "target")
  elseif event == "PLAYER_STARTED_LOOKING" then
    confirmed = false
    look.Start()
  elseif event == "PLAYER_STOPPED_LOOKING" then
    confirmed = false
    look.Stop()
  elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
    state.mounted = flag("IsMounted")
  elseif event == "PLAYER_ENTERING_WORLD" then
    syncState()
  elseif event == "LOADING_SCREEN_ENABLED" then
    loading = true
  elseif event == "LOADING_SCREEN_DISABLED" then
    loading = false
    syncState()
    invalidate()
  elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    invalidate()
  elseif event == "UNIT_ENTERED_VEHICLE" then
    state.vehicle = unit == "player" or state.vehicle
  elseif event == "UNIT_EXITED_VEHICLE" then
    state.vehicle = unit ~= "player" and state.vehicle
  end
  refresh()
end

local function startEvents()
  if running then
    return
  end
  if not watcher then
    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", ns.Wrap("cursor-event", onEvent))
  end
  for _, event in ipairs(EVENTS) do
    pcall(watcher.RegisterEvent, watcher, event)
  end
  for _, event in ipairs(UNIT_EVENTS) do
    pcall(watcher.RegisterUnitEvent, watcher, event, "player")
  end
  running = true
  loading = false
  syncState()
end

local function stopEvents()
  if watcher and running then
    watcher:UnregisterAllEvents()
  end
  running = false
end

-- Brings the runtime in line with the settings: events and frame exist only while the ring is on (or the
-- editor tests it), the frame takes the layer and the active layout.
function C.Apply()
  if not ns.db then
    return
  end
  local cfg = C.Config()
  rules = cfg
  if cfg.enabled then
    startEvents()
  else
    stopEvents()
  end
  if cfg.enabled or editing then
    ensureFrame()
    frame:SetFrameStrata(cfg.strata)
    redraw()
    refresh()
  else
    teardown()
  end
end

function C.Frame()
  return frame
end

-- The frame that holds the event registrations, nil until the ring was switched on once.
function C.Watcher()
  return watcher
end

function C.IsShown()
  return visible
end

-- A copy of the state the rules read, for the diagnosis and tests.
function C.State()
  local copy = { loading = loading, centred = centred, editing = editing, running = running }
  for k, v in pairs(state) do
    copy[k] = v
  end
  return copy
end

function C.DiagLine()
  if not running and not editing then
    return "cursor ring: off"
  end
  local cfg = C.Config()
  return string.format(
    "cursor ring: %s, %s, layout %s, layer %s, combat %d instance %d target %d mounted %d vehicle %d look %d",
    running and "on" or "editor test",
    visible and "shown" or "hidden",
    tostring(cfg.layoutId),
    cfg.strata,
    state.combat and 1 or 0,
    state.instance and 1 or 0,
    state.target and 1 or 0,
    state.mounted and 1 or 0,
    state.vehicle and 1 or 0,
    state.mouselook and 1 or 0
  )
end

-- Editor ------------------------------------------------------------------------------------------------

-- The pointer image for the stage of the editor, nil when the client does not have the file.
local function pointer()
  if ns.ResolveIcon(POINTER) ~= POINTER then
    return nil
  end
  return { texture = POINTER, tipX = POINTER_TIP, tipY = POINTER_TIP, size = POINTER_SIZE }
end

function C.Edit()
  local editor = ns.CanvasEditor
  if not (editor and editor.Open) then
    ns.Notify.send(L["cursor.edit.missing"], "warning")
    return
  end
  C.EnsureLayouts()
  local manager = C.Manager()
  -- The tool buttons start off at every opening, so the simulation starts empty too.
  ns.CursorSim.Reset()
  editor.Open({
    host = "cursor",
    title = L["cursor.edit.title"],
    layout = C.Layout(),
    types = E.Types(),
    presets = CU.Presets(),
    manager = manager,
    stage = { marker = pointer() },
    tools = ns.CursorSim.Tools(),
    sim = ns.CursorSim.State(),
    -- "At the real cursor": the ring shows while the editor is open, whatever the rules say.
    liveTest = function(active)
      editing = active == true
      C.Apply()
    end,
    -- The editor may have switched the layout since it was opened: the result goes to the current one.
    onApply = function(layout)
      manager.save(manager.current(), layout)
    end,
    -- Every session ends here, so no simulation outlives the editor.
    onCancel = ns.CursorSim.Reset,
  })
end

-- /fg mauszeiger, /fg cursor, /fg ring: no word toggles the ring, the words below are handled here.
local ON, OFF = { on = true, an = true, ["1"] = true }, { off = true, aus = true, ["0"] = true }

function C.Slash(rest)
  local word = tostring(rest or ""):match("^%s*(%w*)"):lower()
  if word == "" then
    C.Toggle()
  elseif ON[word] then
    C.SetEnabled(true)
  elseif OFF[word] then
    C.SetEnabled(false)
  elseif word == "edit" or word == "bearbeiten" then
    C.Edit()
    return
  elseif word == "reset" then
    C.ResetOptions()
    ns.Notify.chat(L["cursor.slash.reset"])
    return
  else
    ns.Notify.chat(L["cursor.slash.usage"])
    return
  end
  ns.Notify.chat(L[C.IsEnabled() and "cursor.slash.on" or "cursor.slash.off"])
end

-- Events -------------------------------------------------------------------------------------------------

ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.cursorRing") then
    C.Apply()
  end
end)
ns.On("PLAYER_LOGIN", function()
  C.Apply()
end)

-- Key binding, appended to the list of Modules/KeyBindings.lua (Bindings.xml calls it).
ns.KeyBindings.list[#ns.KeyBindings.list + 1] =
  { name = "FOREVERGUIDES_CURSORRING", label = "binding.cursorRing", fn = "CursorRing" }
ns.KeyBindings.CursorRing = function()
  ns.Safe("binding:CursorRing", C.Toggle)
end
