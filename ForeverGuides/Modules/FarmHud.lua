-- Farm HUD: the real minimap enlarged over the middle of the screen, behind the user interface, without mouse,
-- with the terrain faded or switched off. Only the real minimap draws the blips of the game (ore and herbs of
-- the active tracking), so it is moved and not copied; our pins are its children and grow with it. The logic
-- is Modules/FarmHudLogic.lua.
--
-- Moving a Blizzard frame can touch its layout code, so this is strictly on demand (/fg farmhud, the key
-- binding), never on login, and only outside of combat. Before anything is touched the whole state of the
-- minimap is cached; it is put back step by step (each in its own pcall) when the HUD goes off, in
-- instances, during a loading screen, at logout and when a step fails. Combat only shows or hides our
-- own frames. docs/TAINT-AUDIT.md lists what is touched.
local _, ns = ...
local FH, Layer = ns.FarmHudLogic, ns.MinimapLayer
local Theme = ns.Theme
local readable, call, flag, secret = Layer.Readable, Layer.Call, Layer.Flag, Layer.Secret

local H = {}
ns.FarmHud = H

ns.AddLocale("enUS", {
  ["farmhud.on"] = "Farm HUD on.",
  ["farmhud.off"] = "Farm HUD off.",
  ["farmhud.waitOn"] = "Farm HUD switches on after the combat.",
  ["farmhud.waitOff"] = "Farm HUD switches off after the combat.",
  ["farmhud.waitInstance"] = "Farm HUD is on and appears again outside of instances.",
  ["farmhud.failed"] = "Farm HUD could not start (%s). The minimap is back in its place.",
  ["farmhud.usage"] = "/fg farmhud [on | off]",
  ["farmhud.dir.N"] = "N",
  ["farmhud.dir.E"] = "E",
  ["farmhud.dir.S"] = "S",
  ["farmhud.dir.W"] = "W",
  ["binding.farmHud"] = "Farm HUD on or off",
})
ns.AddLocale("deDE", {
  ["farmhud.on"] = "Farm-HUD an.",
  ["farmhud.off"] = "Farm-HUD aus.",
  ["farmhud.waitOn"] = "Farm-HUD schaltet sich nach dem Kampf ein.",
  ["farmhud.waitOff"] = "Farm-HUD schaltet sich nach dem Kampf aus.",
  ["farmhud.waitInstance"] = "Farm-HUD ist an und erscheint außerhalb von Instanzen wieder.",
  ["farmhud.failed"] = "Farm-HUD konnte nicht starten (%s). Die Minimap ist wieder an ihrem Platz.",
  ["farmhud.usage"] = "/fg farmhud [an | aus]",
  ["farmhud.dir.N"] = "N",
  ["farmhud.dir.E"] = "O",
  ["farmhud.dir.S"] = "S",
  ["farmhud.dir.W"] = "W",
  ["binding.farmHud"] = "Farm-HUD ein oder aus",
})

-- Seconds between two looks at the compass and the ring, and between two checks that the minimap is still
-- where the HUD put it.
local TICK, VERIFY = 0.05, 1
local LEVEL_ABOVE = 4
local MAX_NOTES = 20
local DIRS = { "N", "E", "S", "W" }

local state = { attached = false, shown = false }
-- The player's switch (this session only) and a loading screen that puts the minimap back for a moment.
local wanted, suspended = false, false
-- Settings the dev test overrides without storing them: { terrain, alpha }.
local override
local snapshot
local hud, overlay, letters, ring
local notes = {}
local acc, sinceVerify = 0, 0
local needsRefit = false
local lettersKey, ringPath

-- Helpers -------------------------------------------------------------------------------------------------

local function minimap()
  return rawget(_G, "Minimap")
end

local function note(text)
  notes[#notes + 1] = tostring(text)
  if #notes > MAX_NOTES then
    table.remove(notes, 1)
  end
end

-- Calls fn inside pcall: true plus the results, or false after a note.
local function try(fn, ...)
  if type(fn) ~= "function" then
    note("missing function")
    return false
  end
  local r = { pcall(fn, ...) }
  if not r[1] then
    note(r[2])
    return false
  end
  return true, unpack(r, 2)
end

local function settings()
  local s = FH.Settings(ns.Store.get("settings.farmhud"))
  if override then
    s.terrain = override.terrain or s.terrain
    if override.alpha ~= nil then
      s.alpha = override.alpha
    end
  end
  return s
end

local function boolean(v)
  if v == true or v == false then
    return v
  end
end

-- Snapshot ----------------------------------------------------------------------------------------------

local function groundApi()
  local api = rawget(_G, "C_Minimap")
  if
    type(api) == "table"
    and type(api.GetDrawGroundTextures) == "function"
    and type(api.SetDrawGroundTextures) == "function"
  then
    return api
  end
end

-- The state of the minimap as the cache needs it. A part that cannot be read stays nil, FH.Missing says which
-- required part is absent. A failing anchor read makes the whole anchor list unusable.
function H.ReadSnapshot()
  local mm = minimap()
  if not mm then
    return nil
  end
  local function get(object, method, ...)
    if type(object) ~= "table" then
      return nil
    end
    local ok, v = try(object[method], object, ...)
    if ok and not secret(v) then
      return v
    end
  end
  local snap = {}
  snap.parent = get(mm, "GetParent")
  local count = readable(get(mm, "GetNumPoints"))
  if count and count > 0 then
    local points = {}
    for i = 1, count do
      local ok, point, rel, relPoint, x, y = try(mm.GetPoint, mm, i)
      if not (ok and type(point) == "string") then
        points = nil
        break
      end
      points[#points + 1] =
        { point = point, rel = rel, relPoint = relPoint or point, x = readable(x) or 0, y = readable(y) or 0 }
    end
    snap.points = points
  end
  snap.width, snap.height = readable(get(mm, "GetWidth")), readable(get(mm, "GetHeight"))
  snap.scale, snap.effective = readable(get(mm, "GetScale")), readable(get(mm, "GetEffectiveScale"))
  snap.strata, snap.level = get(mm, "GetFrameStrata"), readable(get(mm, "GetFrameLevel"))
  snap.alpha = readable(get(mm, "GetAlpha"))
  snap.mouse, snap.wheel, snap.shown =
    boolean(get(mm, "IsMouseEnabled")), boolean(get(mm, "IsMouseWheelEnabled")), boolean(get(mm, "IsShown"))
  snap.zoom = readable(get(mm, "GetZoom"))
  local api = groundApi()
  if api then
    local ok, v = try(api.GetDrawGroundTextures)
    snap.ground = ok and not secret(v) and boolean(v) or nil
  end
  local backdrop = rawget(_G, "MinimapBackdrop")
  snap.backdropShown = boolean(get(backdrop, "IsShown"))
  snap.backdropMouse, snap.backdropWheel =
    boolean(get(backdrop, "IsMouseEnabled")), boolean(get(backdrop, "IsMouseWheelEnabled"))
  snap.compassShown = boolean(get(rawget(_G, "MinimapCompassTexture"), "IsShown"))
  return snap
end

-- Put back --------------------------------------------------------------------------------------------------

local RESTORE = {
  parent = function(mm, snap)
    mm:SetParent(snap.parent)
  end,
  points = function(mm, snap)
    mm:ClearAllPoints()
    for _, p in ipairs(snap.points) do
      mm:SetPoint(p.point, p.rel or snap.parent, p.relPoint, p.x, p.y)
    end
  end,
  size = function(mm, snap)
    mm:SetSize(snap.width, snap.height)
  end,
  scale = function(mm, snap)
    mm:SetScale(snap.scale)
  end,
  strata = function(mm, snap)
    mm:SetFrameStrata(snap.strata)
  end,
  level = function(mm, snap)
    mm:SetFrameLevel(snap.level)
  end,
  alpha = function(mm, snap)
    mm:SetAlpha(snap.alpha)
  end,
  mouse = function(mm, snap)
    mm:EnableMouse(snap.mouse)
  end,
  wheel = function(mm, snap)
    mm:EnableMouseWheel(snap.wheel)
  end,
  zoom = function(mm, snap)
    if readable(call(mm.GetZoom, mm)) ~= snap.zoom then
      mm:SetZoom(snap.zoom)
    end
  end,
  ground = function(_, snap)
    local api = groundApi()
    if api and state.groundChanged then
      api.SetDrawGroundTextures(snap.ground)
    end
  end,
  backdrop = function(_, snap)
    local backdrop = rawget(_G, "MinimapBackdrop")
    if not backdrop then
      return
    end
    backdrop:SetShown(snap.backdropShown)
    if snap.backdropMouse ~= nil then
      backdrop:EnableMouse(snap.backdropMouse)
    end
    if snap.backdropWheel ~= nil then
      backdrop:EnableMouseWheel(snap.backdropWheel)
    end
  end,
  compass = function(_, snap)
    local texture = rawget(_G, "MinimapCompassTexture")
    if texture then
      texture:SetShown(snap.compassShown)
    end
  end,
  shown = function(mm, snap)
    mm:SetShown(snap.shown)
  end,
}

-- Puts every cached part back, each step on its own so one failure does not leave the rest undone. Returns
-- true when every step worked.
local function leave()
  if not state.attached then
    return true
  end
  local mm, snap = minimap(), snapshot
  local ok = true
  if mm and #FH.Missing(snap) == 0 then
    for _, step in ipairs(FH.RestoreSteps(snap)) do
      if not try(RESTORE[step], mm, snap) then
        ok = false
      end
    end
  else
    note("no whole cache: nothing was written back")
    ok = false
  end
  if hud then
    hud:Hide()
  end
  state.attached, state.shown, state.groundChanged = false, false, nil
  snapshot = nil
  Layer.SetScale(1)
  Layer.Refit()
  return ok
end

-- Frames -------------------------------------------------------------------------------------------------------

local function compassStyle(s)
  local key = s.compassSize .. s.compassColor
  if key == lettersKey then
    return
  end
  lettersKey = key
  local color = FH.COMPASS_COLORS[s.compassColor] or FH.COMPASS_COLORS.white
  for _, fs in ipairs(letters) do
    local path, _, flags = fs:GetFont()
    fs:SetFont(path or rawget(_G, "STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF", s.compassSize, flags or "OUTLINE")
    fs:SetTextColor(color[1], color[2], color[3], 1)
  end
end

local function labels()
  for i, key in ipairs(DIRS) do
    letters[i]:SetText(ns.L["farmhud.dir." .. key])
  end
end

-- Compass letters and gather ring, from the facing and the radius of the minimap.
local function updateOverlay(s)
  local half = readable(call(hud.GetWidth, hud))
  half = half and half / 2
  local getCVar = rawget(_G, "GetCVar")
  local rotate = call(getCVar, "rotateMinimap") == "1"
  local points = s.compass and half and FH.CompassPoints(half, rotate, ns.Waypoints.Facing()) or nil
  if points then
    compassStyle(s)
  end
  for i, fs in ipairs(letters) do
    local p = points and points[i]
    if p then
      fs:ClearAllPoints()
      fs:SetPoint("CENTER", hud, "CENTER", p.x, p.y)
      fs:Show()
    else
      fs:Hide()
    end
  end
  local radius = Layer.Radius()
  local px = s.ring and half and radius and FH.YardsToPx(s.ringYards, radius, half) or nil
  local size = px and px * 2
  local assets = ns.CursorAssets
  local stem = size and size >= 8 and assets and assets.NearestStroke("circle", 2, size)
  local path = stem and assets.Path(stem)
  if path then
    if path ~= ringPath then
      ringPath = path
      ring:SetTexture(path)
    end
    ring:SetVertexColor(Theme.color("warning", 0.9))
    ring:SetSize(size, size)
    ring:Show()
  else
    ring:Hide()
  end
end

local function onUpdate(_, dt)
  dt = tonumber(dt) or 0
  acc, sinceVerify = acc + dt, sinceVerify + dt
  if acc < TICK or not state.attached then
    return
  end
  acc = 0
  ns.Safe("farmhud-overlay", updateOverlay, state.settings)
  if sinceVerify >= VERIFY then
    sinceVerify = 0
    local mm = minimap()
    if mm and call(mm.GetParent, mm) ~= hud then
      note("the minimap left the HUD parent")
      needsRefit = true
      H.Update()
    end
  end
end

local function ensureFrames()
  if hud then
    return
  end
  local ui = rawget(_G, "UIParent")
  hud = CreateFrame("Frame", nil, ui)
  hud:EnableMouse(false)
  hud:Hide()
  hud:SetScript("OnUpdate", onUpdate)
  overlay = CreateFrame("Frame", nil, hud)
  overlay:SetAllPoints(hud)
  overlay:EnableMouse(false)
  letters = {}
  for i = 1, #DIRS do
    letters[i] = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    letters[i]:Hide()
  end
  ring = overlay:CreateTexture(nil, "ARTWORK")
  ring:SetPoint("CENTER", hud, "CENTER")
  ring:Hide()
end

-- Enter ----------------------------------------------------------------------------------------------------------

local function screenSize()
  local ui = rawget(_G, "UIParent")
  if not ui then
    return nil
  end
  return readable(call(ui.GetWidth, ui)), readable(call(ui.GetHeight, ui))
end

-- Frame, anchors and size of the HUD and of the minimap in it. Also the check that the minimap is still there.
local function place(mm, s)
  local w, h = screenSize()
  local size = FH.Size(w, h, s.scale, 1)
  local mmSize = FH.Size(w, h, s.scale, snapshot.scale)
  if not (size and mmSize) then
    error("the screen size is not readable", 0)
  end
  hud:SetFrameStrata(s.strata)
  hud:SetSize(size, size)
  hud:ClearAllPoints()
  hud:SetPoint("CENTER", rawget(_G, "UIParent"), "CENTER", 0, 0)
  hud:Show()
  mm:SetParent(hud)
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", hud, "CENTER", 0, 0)
  mm:SetSize(mmSize, mmSize)
  mm:SetFrameStrata(s.strata)
  local level = readable(call(hud.GetFrameLevel, hud)) or 1
  mm:SetFrameLevel(level + 1)
  mm:EnableMouse(false)
  mm:EnableMouseWheel(false)
  overlay:SetFrameLevel(level + LEVEL_ABOVE + 2)
end

-- The parts that may fail without harm: each on its own, a failure is a note.
local function dress(mm, s)
  local backdrop = rawget(_G, "MinimapBackdrop")
  if backdrop then
    try(function()
      backdrop:Hide()
      backdrop:EnableMouse(false)
      backdrop:EnableMouseWheel(false)
    end)
  end
  local texture = rawget(_G, "MinimapCompassTexture")
  if texture then
    try(texture.Hide, texture)
  end
  local plan = FH.Terrain(s.terrain, { ground = snapshot.ground ~= nil and groundApi() ~= nil }, s.alpha)
  state.terrain = plan
  if plan.mode == "ground" then
    state.groundChanged = true
    try(groundApi().SetDrawGroundTextures, false)
  elseif plan.mode == "alpha" then
    try(mm.SetAlpha, mm, plan.alpha)
  end
  if s.zoom ~= FH.ZOOM_KEEP and snapshot.zoom ~= nil and snapshot.zoom ~= s.zoom then
    try(mm.SetZoom, mm, s.zoom)
  end
end

local function attach(mm, s)
  place(mm, s)
  dress(mm, s)
  local effective = readable(call(mm.GetEffectiveScale, mm))
  Layer.SetScale(FH.PinFactor(s.pinScale, snapshot.effective, effective))
  Layer.Refit()
  lettersKey, ringPath = nil, nil
  labels()
  state.settings = s
  state.shown = true
end

-- Moves the minimap into the HUD. Returns true, or false and the reason after the minimap was put back.
local function enter()
  local mm = minimap()
  if not mm then
    return false, "Minimap is missing"
  end
  if state.attached then
    return true
  end
  if not ns.ProtectedAllowed(mm) then
    return false, "the minimap is restricted"
  end
  local snap = H.ReadSnapshot()
  local missing = FH.Missing(snap)
  if #missing > 0 then
    return false, "cache incomplete: " .. table.concat(missing, ", ")
  end
  ensureFrames()
  snapshot, state.attached = snap, true
  local ok, err = pcall(attach, mm, settings())
  if not ok then
    leave()
    return false, tostring(err)
  end
  return true
end

-- Switch -------------------------------------------------------------------------------------------------------

local function context(s)
  return {
    wanted = wanted,
    suspended = suspended,
    combat = flag("InCombatLockdown"),
    instance = flag("IsInInstance"),
    hideInCombat = s.hideInCombat,
    hideInInstance = s.hideInInstance,
  }
end

-- Does what the plan says: moves the minimap in or back (outside of combat), shows or hides our frames (also in
-- combat), waits (in combat). A change of the settings or of the screen while the HUD is on goes through a
-- put back and a new move, outside of combat.
function H.Update()
  local s = settings()
  local ctx = context(s)
  local action = FH.Plan(state, ctx)
  if action == "enter" then
    local ok, reason = enter()
    if not ok then
      wanted = false
      note("start failed: " .. tostring(reason))
      ns.Notify.chat(string.format(ns.L["farmhud.failed"], tostring(reason)))
    end
  elseif action == "leave" then
    leave()
  elseif action == "show" or action == "hide" then
    state.shown = action == "show"
    hud:SetShown(state.shown)
  end
  if state.attached and needsRefit and not ctx.combat then
    needsRefit = false
    leave()
    local again = FH.Plan(state, ctx)
    if again == "enter" then
      local ok, reason = enter()
      if not ok then
        wanted = false
        ns.Notify.chat(string.format(ns.L["farmhud.failed"], tostring(reason)))
      end
    end
  end
  return action
end

function H.SetWanted(on)
  wanted = on == true
  return H.Update()
end

function H.Toggle()
  H.SetWanted(not wanted)
  return wanted
end

-- Forces the minimap back whatever the plan says (logout), still never in a restricted state.
function H.Release()
  wanted = false
  local mm = minimap()
  if state.attached and mm and ns.ProtectedAllowed(mm) then
    leave()
  end
end

function H.IsWanted()
  return wanted
end

-- What is going on, for the tests and the dev test: { wanted, suspended, attached, shown, terrain (the plan),
-- settings, hud, overlay, notes, pending (a change waits for the end of the combat) }.
function H.State()
  local pending = false
  if wanted ~= state.attached then
    pending = flag("InCombatLockdown")
  end
  return {
    wanted = wanted,
    suspended = suspended,
    attached = state.attached,
    shown = state.shown,
    terrain = state.terrain,
    settings = state.settings,
    hud = hud,
    overlay = overlay,
    notes = notes,
    pending = pending,
    snapshot = snapshot,
  }
end

-- Settings the dev test sets for this session only (not stored); nil removes them.
function H.SetOverride(t)
  override = t
  needsRefit = state.attached
  return H.Update()
end

local ON, OFF = { on = true, an = true, ["1"] = true }, { off = true, aus = true, ["0"] = true }

-- The chat line for the state after a switch.
local function report()
  local ctx = context(settings())
  if state.attached == wanted then
    ns.Notify.chat(ns.L[wanted and "farmhud.on" or "farmhud.off"])
  elseif ctx.combat then
    ns.Notify.chat(ns.L[wanted and "farmhud.waitOn" or "farmhud.waitOff"])
  elseif wanted then
    ns.Notify.chat(ns.L["farmhud.waitInstance"])
  end
end

-- /fg farmhud: no word toggles, "on" and "off" (an, aus) set it.
function H.Slash(rest)
  local word = tostring(rest or ""):match("^%s*(%w*)"):lower()
  if word == "" then
    H.Toggle()
  elseif ON[word] then
    H.SetWanted(true)
  elseif OFF[word] then
    H.SetWanted(false)
  else
    ns.Notify.chat(ns.L["farmhud.usage"])
    return
  end
  report()
end

-- Events -------------------------------------------------------------------------------------------------------

ns.On("PLAYER_REGEN_ENABLED", function()
  H.Update()
end)

ns.On("PLAYER_REGEN_DISABLED", function()
  H.Update()
end)

-- A loading screen puts the minimap back, the new world takes it again.
ns.On("PLAYER_LEAVING_WORLD", function()
  if state.attached then
    suspended = true
    H.Update()
  end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
  if suspended then
    suspended = false
    H.Update()
  elseif wanted then
    H.Update()
  end
end)

ns.On("PLAYER_LOGOUT", function()
  H.Release()
end)

local function refit()
  if state.attached then
    needsRefit = true
  end
  if state.attached or wanted then
    ns.Debounce("farmhud-refit", 0.15, H.Update)
  end
end

ns.On("DISPLAY_SIZE_CHANGED", refit)
ns.On("UI_SCALE_CHANGED", refit)

ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.farmhud") then
    refit()
  end
end)

-- Key binding, appended to the list of Modules/KeyBindings.lua (Bindings.xml calls it).
ns.KeyBindings.list[#ns.KeyBindings.list + 1] =
  { name = "FOREVERGUIDES_FARMHUD", label = "binding.farmHud", fn = "FarmHud" }
ns.KeyBindings.FarmHud = function()
  ns.Safe("binding:FarmHud", H.Slash, "")
end
