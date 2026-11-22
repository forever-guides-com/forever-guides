-- Screen navigation: the client puts a frame on the super-tracked map pin (C_Navigation.GetFrame) that
-- sticks to the target in the world. Our marker (pin icon, light beam, distance, arrival time, edge arrow
-- when the target is off screen) is anchored to that frame. Without the frame (API missing, CVar off,
-- instance, nothing tracked) the arrow window leads as before.
-- Without a waypoint of ours the same marker replaces the client diamond of the super-tracked quest
-- (switch "navReplaceQuest", read-only: we never change what the client tracks). While our marker is drawn
-- the client marker (SuperTrackedFrame) is held at alpha 0 through a hook on its alpha update.
-- Every client call is wrapped in pcall, nothing here assumes the calls are allowed.
-- The hidden CVar showInGameNavigation is only changed through the switch "screenNav" and the
-- previous value is restored when the switch goes off.
-- Settings: "navMarker" off and the near-target mode "native" (WaypointLogic.nearMode) make us draw nothing
-- and release the client marker; "marker" only drops the beam close to the target. Also owns the measured speed behind the arrival time.
local _, ns = ...
local WL, WP = ns.WaypointLogic, ns.Waypoints

local WN = {}
ns.WaypointNav = WN

local CVAR = "showInGameNavigation"
local UPDATE_EVERY = 0.1

local tracker = WL.newSpeed()
local trackedId
local marker, driver, acc = nil, nil, 0
local active = false
-- True while we deliberately leave the marker to the client (setting off, or near the target in "native"):
-- the arrow window must not step in for it.
local yielded = false
-- Near-target state with hysteresis, see WaypointLogic.nearMode.
local isNear = false
-- True while we set the user waypoint as super-tracked ourselves.
local tracking = false
local applyWaiting = false

-- Client access ----------------------------------------------------------------------------------

local function fn(path)
  local value = rawget(_G, path[1])
  for i = 2, #path do
    if type(value) ~= "table" then
      return nil
    end
    value = value[path[i]]
  end
  return type(value) == "function" and value or nil
end

local function try(path, ...)
  local f = fn(path)
  if not f then
    return false
  end
  local ok, a = pcall(f, ...)
  if ok then
    return true, a
  end
  return false
end

-- The native navigation frame, or nil when this client has none (yet).
function WN.NavFrame()
  local ok, frame = try({ "C_Navigation", "GetFrame" })
  if ok and type(frame) == "table" and type(frame.GetCenter) == "function" then
    return frame
  end
end

-- Distance in yards from the client, nil when not readable.
function WN.NavDistance()
  local ok, yards = try({ "C_Navigation", "GetDistance" })
  if ok and type(yards) == "number" and WL.readable(yards) and WL.finite(yards) then
    return yards
  end
end

local function readCVar()
  local ok, value = try({ "C_CVar", "GetCVar" }, CVAR)
  if not ok then
    ok, value = try({ "GetCVar" }, CVAR)
  end
  if ok and value ~= nil then
    return tostring(value)
  end
end

local function writeCVar(value)
  if not try({ "C_CVar", "SetCVar" }, CVAR, value) then
    return try({ "SetCVar" }, CVAR, value)
  end
  return true
end

-- Settings ----------------------------------------------------------------------------------------

local function enabled()
  return ns.db ~= nil and WP.Settings().screenNav == true
end

-- Puts the CVar in line with the switch: on = enabled (the old value is kept), off = old value back.
-- Deferred while in combat.
function WN.Apply()
  if not ns.db then
    return
  end
  if ns.InCombat() then
    applyWaiting = true
    return
  end
  applyWaiting = false
  local settings = WP.Settings()
  if settings.screenNav then
    local current = readCVar()
    if current ~= nil and current ~= "1" then
      if settings.navCvarBefore == "" then
        settings.navCvarBefore = current
      end
      writeCVar("1")
    end
  else
    WN.Track(false)
    if settings.navCvarBefore ~= "" then
      writeCVar(settings.navCvarBefore)
      settings.navCvarBefore = ""
    end
  end
  WN.Refresh()
end

-- Super-tracks the native pin (on) or hands it back (off). Only while the switch is on, never in combat.
function WN.Track(on)
  if ns.InCombat() then
    return
  end
  if on then
    if enabled() and try({ "C_SuperTrack", "SetSuperTrackedUserWaypoint" }, true) then
      tracking = true
    end
  elseif tracking then
    tracking = false
    try({ "C_SuperTrack", "SetSuperTrackedUserWaypoint" }, false)
  end
end

-- Measured speed ----------------------------------------------------------------------------------

local function now()
  local get = rawget(_G, "GetTime")
  return type(get) == "function" and get() or nil
end

local function mounted()
  local f = fn({ "IsMounted" })
  if not f then
    return false
  end
  local ok, value = pcall(f)
  return ok and value == true
end

-- Feeds the reading and returns the arrival time in seconds at the measured speed.
function WN.Eta(yards, key)
  local id = key
  if id == nil then
    local wp = WP.Active()
    id = wp and wp.id
  end
  if id ~= trackedId then
    trackedId = id
    WL.speedReset(tracker)
  end
  local isMounted = mounted()
  WL.speedSample(tracker, yards, now(), isMounted)
  return WL.etaMeasured(tracker, yards, isMounted)
end

function WN.Tracker()
  return tracker
end

-- Marker -------------------------------------------------------------------------------------------

function WN.MarkerActive()
  return active or yielded
end

-- Light beam strength by distance: full out to FAR_START, thinner and fainter beyond it, gone inside
-- ARRIVE_MIN and fading in up to ARRIVE_FULL so it does not fill the view on arrival.
local ARRIVE_MIN, ARRIVE_FULL = 5, 15
local FAR_START, FAR_END = 150, 1500
local FAR_ALPHA, FAR_WIDTH = 0.3, 0.5

-- Returns alpha and width factor (both 0..1, alpha 0 = hidden). Unknown distance gives the full beam.
function WN.BeamStyle(yards)
  if type(yards) ~= "number" or not WL.finite(yards) then
    return 1, 1
  end
  if yards < ARRIVE_MIN then
    return 0, 1
  end
  local near = math.min(1, (yards - ARRIVE_MIN) / (ARRIVE_FULL - ARRIVE_MIN))
  local far = math.max(0, math.min(1, (yards - FAR_START) / (FAR_END - FAR_START)))
  return near * (1 - far * (1 - FAR_ALPHA)), 1 - far * (1 - FAR_WIDTH)
end

-- The client clamps the navigation frame to the screen edge when the target is off screen. A centre within
-- EDGE_MARGIN of an edge counts as off screen; the angle (radians, 0 = right, counter-clockwise) points from
-- the screen centre toward the frame, which is the way to the target. Coordinates in UIParent units.
local EDGE_MARGIN = 24

function WN.EdgeState(x, y, w, h)
  if not (WL.finite(x) and WL.finite(y) and WL.finite(w) and WL.finite(h)) or w <= 0 or h <= 0 then
    return false, 0
  end
  local off = x <= EDGE_MARGIN or y <= EDGE_MARGIN or x >= w - EDGE_MARGIN or y >= h - EDGE_MARGIN
  return off, math.atan2(y - h / 2, x - w / 2)
end

local function screenPoint(nav)
  local x, y = nav:GetCenter()
  if type(x) ~= "number" or type(y) ~= "number" then
    return nil
  end
  local scale = nav.GetEffectiveScale and nav:GetEffectiveScale() or 1
  local ui = UIParent:GetEffectiveScale() or 1
  if type(scale) ~= "number" or type(ui) ~= "number" or ui <= 0 then
    return nil
  end
  return x * scale / ui, y * scale / ui
end

-- Client pictures, tried in order; the first one the client knows wins. None known: the fallback.
local ICON_ATLASES = { "Waypoint-MapPin-Tracked", "Waypoint-MapPin-ChatIcon", "Waypoint-MapPin-Untracked" }
local ARROW_ATLASES = { "poi-traveldirections-arrow" }
local ARROW_FILE = "Interface\\Minimap\\ROTATING-MINIMAPARROW"
local SPARK_FILE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local FLAT = "Interface\\Buttons\\WHITE8X8"
WN.ICON_ATLASES, WN.ARROW_ATLASES = ICON_ATLASES, ARROW_ATLASES

local function atlasKnown(name)
  local api = rawget(_G, "C_Texture")
  if type(api) ~= "table" or type(api.GetAtlasInfo) ~= "function" then
    return false
  end
  local ok, info = pcall(api.GetAtlasInfo, name)
  return ok and info ~= nil
end

local function firstAtlas(list)
  for _, name in ipairs(list) do
    if atlasKnown(name) then
      return name
    end
  end
end

local GOLD = { 1, 0.82, 0 }
local ICON_SIZE, ARROW_SIZE = 30, 22
local BEAM_W, BEAM_H, SEGMENTS = 28, 380, 16
local BEAM_MIN, BEAM_LIFT = 60, 6
local TEXT_W = 140

-- Horizontal gradient from alpha a0 to a1 in one colour; false when the client cannot do it.
local function gradient(tex, r, g, b, a0, a1)
  if type(tex.SetGradient) ~= "function" then
    return false
  end
  tex:SetColorTexture(1, 1, 1, 1)
  local color = rawget(_G, "CreateColor")
  if type(color) == "function" and pcall(function()
    tex:SetGradient("HORIZONTAL", color(r, g, b, a0), color(r, g, b, a1))
  end) then
    return true
  end
  return pcall(tex.SetGradient, tex, "HORIZONTAL", r, g, b, a0, r, g, b, a1)
end

-- The beam: stacked slices, each a soft-edged column (clear, bright, clear) whose peak falls off toward
-- the top. Additive so it glows on any background. Without gradients each slice is a thin flat column.
-- The slices are laid out again by layoutBeam whenever the height changes.
local function createBeam(parent, anchor)
  local outer = CreateFrame("Frame", nil, parent)
  outer:SetSize(BEAM_W, BEAM_H)
  outer:SetPoint("BOTTOM", anchor, "CENTER", 0, 6)
  local inner = CreateFrame("Frame", nil, outer)
  inner:SetAllPoints()
  local r, g, b = GOLD[1], GOLD[2], GOLD[3]
  outer.slices, outer.inner = {}, inner
  for i = 1, SEGMENTS do
    local peak = 0.6 * (1 - (i - 1) / SEGMENTS) ^ 1.2
    local left = inner:CreateTexture(nil, "ARTWORK")
    local right = inner:CreateTexture(nil, "ARTWORK")
    left:SetBlendMode("ADD")
    right:SetBlendMode("ADD")
    local flat = not (gradient(left, r, g, b, 0, peak) and gradient(right, r, g, b, peak, 0))
    if flat then
      left:SetColorTexture(r, g, b, peak * 0.35)
      right:Hide()
    end
    outer.slices[i] = { left = left, right = right, flat = flat }
  end
  outer.pulse = inner
  outer.height = 0
  return outer
end

-- Sets the beam height in marker units; no-op while the rounded height is unchanged.
local function layoutBeam(outer, height)
  height = math.max(BEAM_MIN, math.floor(height / 2 + 0.5) * 2)
  if outer.height == height then
    return
  end
  outer.height = height
  outer:SetHeight(height)
  local inner, slice = outer.inner, height / SEGMENTS
  for i, s in ipairs(outer.slices) do
    local lo, hi = (i - 1) * slice, i * slice
    s.left:ClearAllPoints()
    s.right:ClearAllPoints()
    if s.flat then
      s.left:SetPoint("BOTTOMLEFT", inner, "BOTTOM", -2, lo)
      s.left:SetPoint("TOPRIGHT", inner, "BOTTOM", 2, hi)
    else
      s.left:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", 0, lo)
      s.left:SetPoint("TOPRIGHT", inner, "BOTTOM", 0, hi)
      s.right:SetPoint("BOTTOMLEFT", inner, "BOTTOM", 0, lo)
      s.right:SetPoint("TOPRIGHT", inner, "BOTTOMRIGHT", 0, hi)
    end
  end
end

-- Beam height in marker units: a fixed height from the setting, or (0) up to the top edge of the screen.
-- y is the marker centre and uiHeight the screen height, both in UIParent units; scale is the marker scale.
function WN.BeamHeight(setting, y, uiHeight, scale)
  if type(setting) == "number" and setting > 0 then
    return setting
  end
  if not (WL.finite(y) and WL.finite(uiHeight)) or type(scale) ~= "number" or scale <= 0 then
    return BEAM_H
  end
  return math.max(BEAM_MIN, (uiHeight - y) / scale - BEAM_LIFT)
end

-- Slow breathing of the beam (alpha only); nil when the client has no animations.
local function createPulse(frame)
  local group
  local ok = pcall(function()
    group = frame:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.65)
    fade:SetDuration(1.5)
    fade:SetSmoothing("IN_OUT")
    group:SetLooping("BOUNCE")
  end)
  return ok and group or nil
end

local function createMarker()
  local f = CreateFrame("Frame", "FGWaypointMarker", UIParent)
  f:SetSize(TEXT_W, 56)
  f:SetFrameStrata("MEDIUM")
  f.icon = f:CreateTexture(nil, "ARTWORK", nil, 2)
  f.icon:SetSize(ICON_SIZE, ICON_SIZE)
  f.icon:SetPoint("CENTER", f, "CENTER", 0, 0)
  local atlas = firstAtlas(ICON_ATLASES)
  if atlas and pcall(f.icon.SetAtlas, f.icon, atlas) then
    f.iconAtlas = atlas
  else
    f.icon:SetTexture(FLAT)
    f.icon:SetRotation(math.pi / 4)
    f.icon:SetSize(ICON_SIZE * 0.55, ICON_SIZE * 0.55)
    f.icon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
  end
  f.glow = f:CreateTexture(nil, "ARTWORK", nil, 1)
  f.glow:SetTexture(SPARK_FILE)
  f.glow:SetBlendMode("ADD")
  f.glow:SetRotation(math.pi / 2)
  f.glow:SetSize(26, 90)
  f.glow:SetPoint("CENTER", f.icon, "CENTER", 0, -ICON_SIZE / 2)
  f.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.8)
  f.beam = createBeam(f, f.icon)
  f.pulse = createPulse(f.beam.pulse)
  f.arrow = f:CreateTexture(nil, "OVERLAY")
  f.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
  local arrowAtlas = firstAtlas(ARROW_ATLASES)
  if not (arrowAtlas and pcall(f.arrow.SetAtlas, f.arrow, arrowAtlas)) then
    f.arrow:SetTexture(ARROW_FILE)
  end
  f.arrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
  f.arrow:Hide()
  f.dist = ns.W.Text(f, { role = "h3", family = "heading", justify = "CENTER", color = "text" })
  f.dist:SetPoint("TOP", f.icon, "BOTTOM", 0, -10)
  f.dist:SetWidth(TEXT_W)
  f.dist:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
  f.eta = ns.W.Text(f, { role = "micro", color = "text", justify = "CENTER" })
  f.eta:SetPoint("TOP", f.dist, "BOTTOM", 0, -2)
  f.eta:SetWidth(TEXT_W)
  for _, fs in ipairs({ f.dist, f.eta }) do
    if fs.SetShadowOffset then
      fs:SetShadowColor(0, 0, 0, 1)
      fs:SetShadowOffset(1, -1)
    end
  end
  f:Hide()
  return f
end

-- Client marker --------------------------------------------------------------------------------------

local replacing, hooked = false, false

-- The client recomputes the alpha of SuperTrackedFrame every frame (UpdateAlpha), so a plain SetAlpha would
-- be overwritten. The hook runs after it and keeps alpha 0 while we draw ours; when we stop the client
-- takes over again on its next frame, nothing to restore. Skipped when the frame or method is missing.
local function nativeFrame()
  local frame = rawget(_G, "SuperTrackedFrame")
  if type(frame) == "table" and type(frame.UpdateAlpha) == "function" and type(frame.SetAlpha) == "function" then
    return frame
  end
end

local function holdNative(on)
  replacing = on
  if not on then
    return
  end
  local frame = nativeFrame()
  if not frame then
    return
  end
  if not hooked then
    local hook = rawget(_G, "hooksecurefunc")
    local function keepHidden()
      if replacing then
        frame:SetAlpha(0)
      end
    end
    hooked = type(hook) == "function" and pcall(hook, frame, "UpdateAlpha", keepHidden)
  end
  pcall(frame.SetAlpha, frame, 0)
end

local function setActive(on, yield)
  holdNative(on)
  yield = yield == true
  if active ~= on or yielded ~= yield then
    active = on
    yielded = yield
    if ns.WaypointArrow then
      ns.WaypointArrow.Refresh()
    end
  end
end

-- yield: the client marker takes over on purpose, so the arrow window stays away.
local function hideMarker(yield)
  if marker then
    marker:Hide()
    marker:ClearAllPoints()
    marker.anchor = nil
    marker.arrow:Hide()
    marker.beam:Hide()
    marker.glow:Hide()
    if marker.pulse then
      marker.pulse:Stop()
    end
  end
  if not yield then
    isNear = false
  end
  setActive(false, yield)
end

-- False once the target is gone for the client: our own pin is no longer super-tracked or no user
-- waypoint exists. An API that is missing or fails counts as unknown, so the marker stays.
local function pinAlive()
  local ok, tracked = try({ "C_SuperTrack", "IsSuperTrackingUserWaypoint" })
  if ok and tracked ~= true then
    return false
  end
  local has, point = try({ "C_Map", "HasUserWaypoint" })
  if has and point == false then
    return false
  end
  return true
end

-- Beam on or off for this tick: strength by distance, breathing unless motion is reduced.
local function showBeam(m, on, yards)
  local alpha, width = WN.BeamStyle(yards)
  on = on and alpha > 0
  m.beam:SetShown(on)
  m.glow:SetShown(on)
  if not on then
    if m.pulse then
      m.pulse:Stop()
    end
    return
  end
  m.beam:SetAlpha(alpha)
  m.beam:SetWidth(BEAM_W * width)
  m.glow:SetAlpha(alpha)
  if m.pulse then
    if ns.Theme.reduceMotion() then
      m.pulse:Stop()
    elseif not m.pulse:IsPlaying() then
      m.pulse:Play()
    end
  end
end

-- Edge arrow on the inner side of the clamped frame, pointing outward, so it stays on screen.
local function showArrow(m, nav)
  local x, y = screenPoint(nav)
  local off, angle = false, 0
  if x then
    off, angle = WN.EdgeState(x, y, UIParent:GetWidth(), UIParent:GetHeight())
  end
  m.arrow:SetShown(off)
  if off then
    m.arrow:SetRotation(angle - math.pi / 2)
    m.arrow:ClearAllPoints()
    m.arrow:SetPoint("CENTER", m.icon, "CENTER", -math.cos(angle) * 30, -math.sin(angle) * 30)
  end
  return off
end

-- The quest the client super-tracks, nil when none or not readable.
local function superQuest()
  local ok, id = try({ "C_SuperTrack", "GetSuperTrackedQuestID" })
  if ok and type(id) == "number" and WL.finite(id) and id > 0 then
    return id
  end
end

local function questTitle(id)
  local ok, title = try({ "C_QuestLog", "GetTitleForQuestID" }, id)
  if ok and type(title) == "string" then
    return title
  end
  return ""
end

function WN.Update()
  local on = enabled()
  if not on then
    return hideMarker()
  end
  local settings = WP.Settings()
  -- An active waypoint of ours only counts while the client super-tracks it; once the player tracks a quest
  -- instead, the quest is what the native frame points at.
  local wp = on and WP.Active() or nil
  if wp and not pinAlive() then
    wp = nil
  end
  local nav = on and WN.NavFrame() or nil
  local questId = on and not wp and settings.navReplaceQuest and nav and superQuest() or nil
  local target = WL.navTarget({
    enabled = on,
    hasFrame = nav ~= nil,
    hasWaypoint = wp ~= nil,
    questId = questId,
    replaceQuest = settings.navReplaceQuest,
  })
  if target == "none" then
    return hideMarker()
  end
  local quest = target == "quest"
  local yards = WN.NavDistance() or (not quest and WP.Distance(wp)) or nil
  -- Arrived, frame hidden or pin gone: nothing to point at, so no stale marker stays on screen.
  local arrived = not quest and yards and yards <= settings.arrivalRadius and not settings.keepOnArrival
  if arrived or not nav:IsShown() or (not quest and not pinAlive()) then
    return hideMarker()
  end
  if settings.navMarker == false then
    return hideMarker(true)
  end
  local draw
  draw, isNear = WL.nearMode({
    mode = settings.navNear,
    limit = settings.navNearDistance,
    yards = yards,
    near = isNear,
  })
  if draw == "native" then
    return hideMarker(true)
  end
  if not marker then
    marker = createMarker()
  end
  if marker.anchor ~= nav then
    marker.anchor = nav
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", nav, "CENTER")
  end
  marker:SetScale(settings.navSize or 1)
  local off = showArrow(marker, nav)
  local _, y = screenPoint(nav)
  layoutBeam(marker.beam, WN.BeamHeight(settings.navBeamHeight, y, UIParent:GetHeight(), settings.navSize or 1))
  showBeam(marker, settings.navBeam ~= false and draw == "full" and not off, yards)
  if yards then
    marker.dist:SetText(WL.formatDistance(yards, ns.GetActiveLocale()))
    marker.eta:SetText(string.format(ns.L["wparrow.eta"], WL.formatEta(WN.Eta(yards, quest and ("quest" .. questId) or nil))))
  else
    marker.dist:SetText(quest and questTitle(questId) or wp.title)
    marker.eta:SetText("")
  end
  marker:Show()
  setActive(true)
end

-- Starts or stops the tick that follows the frame while there is something to show.
function WN.Refresh()
  local want = enabled() and (WP.Active() ~= nil or WP.Settings().navReplaceQuest == true)
  if want and not driver then
    driver = CreateFrame("Frame")
  end
  if driver then
    acc = UPDATE_EVERY
    driver:SetScript("OnUpdate", want and function(_, elapsed)
      acc = acc + elapsed
      if acc >= UPDATE_EVERY then
        acc = 0
        ns.Safe("waypoint-marker", WN.Update)
      end
    end or nil)
  end
  if not want then
    hideMarker()
  end
end

ns.On("FG_WAYPOINTS_CHANGED", function()
  WN.Refresh()
end)
ns.On("NAVIGATION_FRAME_CREATED", function()
  WN.Update()
end)
ns.On("NAVIGATION_FRAME_DESTROYED", function()
  WN.Update()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if applyWaiting then
    WN.Apply()
  end
end)
ns.On("PLAYER_LOGIN", function()
  WN.Apply()
end)
