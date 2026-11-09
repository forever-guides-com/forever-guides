-- The mouse cursor ring (ns.Cursor): one frame that follows the cursor and draws the active canvas layout
-- (Modules/CursorLogic.lua, CursorElements.lua, CanvasRender). One switch, settings.cursorRing.enabled:
-- while it is off there is no frame, no event and no OnUpdate. While on, the events below keep the mouselook
-- state and the shared game state (ns.LoadState: combat, instance, group, mount, vehicle, target, class,
-- specialization) feeds the "when active" conditions; the frame only runs OnUpdate while it is shown and the
-- only call per frame is GetCursorPosition. The ring is a plain frame without mouse and keyboard, so it works
-- in combat.
-- Settings: ns.db.settings.cursorRing = { enabled, strata, mouselook, load, layoutId, layouts = { [id] =
-- layout } }, all layouts account wide. One character may override the switch and the layout for itself:
-- ns.charDB.cursorRing = { enabled = true | false, layoutId } (a missing field means like the account, a layout
-- that is gone falls back to the next step, Modules/CharScopeLogic.lua). The layout is also assignable to a class:
-- settings.cursorRing.classLayouts = { [classToken] = layoutId }, account wide. Resolution: this character, then
-- its class, then the account (Modules/LayoutAssignLogic.lua).
local _, ns = ...
local L, CU, CR, E, LL, LS, CS =
  ns.L, ns.CursorLogic, ns.CanvasRender, ns.CursorElements, ns.LoadLogic, ns.LoadState, ns.CharScopeLogic

local C = {}
ns.Cursor = C

local EVENTS = {
  "PLAYER_STARTED_LOOKING",
  "PLAYER_STOPPED_LOOKING",
  "PLAYER_ENTERING_WORLD",
  "LOADING_SCREEN_ENABLED",
  "LOADING_SCREEN_DISABLED",
  "UI_SCALE_CHANGED",
  "DISPLAY_SIZE_CHANGED",
}
C.EVENTS = EVENTS

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

-- The override of this character, the table of ns.charDB (nil while there is none).
local function charRing()
  local node = ns.charDB and ns.charDB.cursorRing
  return type(node) == "table" and node or nil
end

local function set(key, value)
  ns.Store.set("settings.cursorRing." .. key, value)
end

-- The class of this character never changes within a session.
local classToken

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
  blank = CU.Blank,
  override = {
    get = function()
      local node = charRing()
      return node and node.layoutId or nil
    end,
    put = function(id)
      ns.Store.setChar("cursorRing.layoutId", id)
    end,
  },
  class = {
    token = function()
      if not classToken then
        local identity = LS.Identity()
        classToken = identity and identity.class or nil
      end
      return classToken
    end,
    get = function()
      return rawSettings().classLayouts
    end,
    put = function(map)
      set("classLayouts", map)
    end,
  },
})
C.LayoutSet = LAYOUTS
C.EnsureLayouts = LAYOUTS.EnsureLayouts
C.Layouts = LAYOUTS.Layouts
C.Layout = LAYOUTS.Layout
C.SetLayout = LAYOUTS.SetLayout
C.SetAccountLayout = LAYOUTS.SetAccountLayout
C.Manager = LAYOUTS.Manager
C.Assign = LAYOUTS.Assign
C.Assignment = LAYOUTS.Assignment
C.ScopeOf = LAYOUTS.ScopeOf

-- The settings with every field valid, as they hold for this character: layoutId names a stored layout (the
-- override of the character while it names one), enabled is the switch in effect. layoutSource and
-- enabledSource say where each comes from ("char" or "account"), layoutStale that an override points at a
-- layout that is gone, accountLayoutId and accountEnabled hold the account's own values.
function C.Config()
  local raw = ns.db and ns.db.settings.cursorRing
  raw = type(raw) == "table" and raw or {}
  local cfg = CU.Clean(raw)
  local _
  cfg.layouts, cfg.layoutId, cfg.layoutSource, cfg.layoutStale = LAYOUTS.State(raw)
  _, cfg.accountLayoutId = LAYOUTS.AccountState(raw)
  cfg.accountEnabled = cfg.enabled
  local node = charRing()
  cfg.enabled, cfg.enabledSource = CS.Enabled(cfg.enabled, node and node.enabled)
  return cfg
end

function C.IsEnabled()
  return ns.db ~= nil and C.Config().enabled
end

-- Switches the ring where the switch in effect comes from: the override of this character while it has one,
-- else the account.
function C.SetEnabled(on)
  if ns.db and (on == true) ~= C.IsEnabled() then
    if C.Config().enabledSource == "char" then
      C.SetEnabledOverride(on == true)
    else
      set("enabled", on == true)
    end
  end
end

-- The account's own switch, whatever this character overrides.
function C.SetAccountEnabled(on)
  if ns.db and (on == true) ~= C.Config().accountEnabled then
    set("enabled", on == true)
  end
end

-- This character's switch: true, false, or nil for like the account.
function C.SetEnabledOverride(value)
  local node = charRing()
  if ns.charDB and (node and node.enabled) ~= CS.CleanEnabled(value) then
    ns.Store.setChar("cursorRing.enabled", CS.CleanEnabled(value))
  end
end

-- This character's layout: a layout id, or nil for like the account.
function C.SetLayoutOverride(id)
  return LAYOUTS.SetOverride(id)
end

-- Whether this character overrides anything of the ring (a layout, a dead layout included, or the switch).
function C.HasOverride()
  local node = charRing()
  return node ~= nil
    and ((type(node.layoutId) == "string" and node.layoutId ~= "") or CS.CleanEnabled(node.enabled) ~= nil)
end

-- Back to the account's values for this character.
function C.ResetOverride()
  local node = charRing()
  if node and node.layoutId ~= nil then
    ns.Store.setChar("cursorRing.layoutId", nil)
  end
  if node and node.enabled ~= nil then
    ns.Store.setChar("cursorRing.enabled", nil)
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
  for _, key in ipairs({ "strata", "mouselook" }) do
    set(key, d[key])
  end
  set("load", nil)
  -- Keys of the first version that were not carried over yet would bring the old rules back.
  for _, key in ipairs(LL.LEGACY) do
    if rawSettings()[key] ~= nil then
      set(key, nil)
    end
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
-- The readings the conditions use: the game state of LoadState (copied by pull) and the mouselook of this host.
local state = { mouselook = false }
local look = CU.NewMouselook(now)
local hotDX, hotDY = 0, 0
local lastX, lastY, lastScale

local function invalidate()
  lastX, lastY, lastScale = nil, nil, nil
end

-- Takes the readings of the shared game state; one that is unknown there is unknown here.
local function pull()
  local shared = LS.Get()
  for _, key in ipairs(LS.KEYS) do
    state[key] = shared[key]
  end
end

local function syncState()
  pull()
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

local function onEvent(_, event)
  if event == "PLAYER_STARTED_LOOKING" then
    confirmed = false
    look.Start()
  elseif event == "PLAYER_STOPPED_LOOKING" then
    confirmed = false
    look.Stop()
  elseif event == "PLAYER_ENTERING_WORLD" then
    syncState()
  elseif event == "LOADING_SCREEN_ENABLED" then
    loading = true
  elseif event == "LOADING_SCREEN_DISABLED" then
    loading = false
    -- An event can be lost behind a loading screen: the shared state is read again.
    LS.Resync()
    syncState()
    invalidate()
  elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    invalidate()
  end
  refresh()
end

-- A change of the shared game state: the conditions are read again.
local function onLoadState(_, event)
  if event == "PLAYER_REGEN_ENABLED" and frame and CR.Deferred(frame) then
    -- A change of a group that waited for the end of the combat.
    redraw()
  end
  pull()
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
  running = true
  loading = false
  LS.Subscribe(onLoadState)
  syncState()
end

local function stopEvents()
  if watcher and running then
    watcher:UnregisterAllEvents()
  end
  LS.Unsubscribe(onLoadState)
  running = false
end

-- Brings the runtime in line with the settings: events and frame exist only while the ring is on (or the
-- editor tests it), the frame takes the layer and the active layout.
function C.Apply()
  if not ns.db then
    return
  end
  -- The old yes/no keys move into `load` before anything reads them.
  LL.Migrate(rawSettings())
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
    groups = true,
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
    -- The result goes to the layout the editor has open: it may differ from the one this player uses.
    onApply = function(layout)
      manager.save(editor.LayoutId and editor.LayoutId() or manager.current(), layout)
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

ns.On("FG_SETTING_CHANGED", function(_, path, _, scope)
  if type(path) ~= "string" then
    return
  end
  if scope == "char" then
    if path:find("^cursorRing") then
      C.Apply()
    end
  elseif path:find("^settings%.cursorRing") then
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
