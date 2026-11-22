-- Feature probe: which APIs this client actually has. Features check
-- ns.can.<key> and fall back quietly instead of erroring.
local _, ns = ...

local can = {}
ns.can = can

local function has(path)
  local node = _G
  for part in path:gmatch("[^%.]+") do
    if type(node) ~= "table" then
      return false
    end
    node = rawget(node, part) or node[part]
    if node == nil then
      return false
    end
  end
  return true
end

-- key -> global path (or function returning boolean)
local PROBES = {
  { "timer", "C_Timer.After" },
  { "addOnsApi", "C_AddOns.LoadAddOn" },
  { "loadAddOnLegacy", "LoadAddOn" },
  { "map", "C_Map.GetBestMapForUnit" },
  { "mapPlayerPos", "C_Map.GetPlayerMapPosition" },
  { "userWaypoint", "C_Map.SetUserWaypoint" },
  { "canSetWaypoint", "C_Map.CanSetUserWaypointOnMap" },
  { "uiMapPoint", "UiMapPoint.CreateFromCoordinates" },
  { "superTrack", "C_SuperTrack.SetSuperTrackedUserWaypoint" },
  { "worldMap", "WorldMapFrame" },
  {
    "worldMapDataProvider",
    function()
      return has("WorldMapFrame.AddDataProvider") and has("MapCanvasDataProviderMixin")
    end,
  },
  { "traits", "C_Traits.GetConfigInfo" },
  { "traitsImportString", "C_Traits.GenerateImportString" },
  { "traitsPurchase", "C_Traits.PurchaseRank" },
  { "traitsCommit", "C_Traits.CommitConfig" },
  { "classTalents", "C_ClassTalents.GetActiveConfigID" },
  { "specialization", "GetSpecialization" },
  { "addonCompartment", "AddonCompartmentFrame.RegisterAddon" },
  { "settingsCanvas", "Settings.RegisterCanvasLayoutCategory" },
  { "settingsAddCategory", "Settings.RegisterAddOnCategory" },
  { "specialFrames", "UISpecialFrames" },
  { "libStub", "LibStub" },
  {
    "libDBIcon",
    function()
      local stub = rawget(_G, "LibStub")
      return stub ~= nil and stub:GetLibrary("LibDBIcon-1.0", true) ~= nil
    end,
  },
  {
    "ldb",
    function()
      local stub = rawget(_G, "LibStub")
      return stub ~= nil and stub:GetLibrary("LibDataBroker-1.1", true) ~= nil
    end,
  },
  { "chatInfo", "C_ChatInfo.SendAddonMessage" },
  { "chatFilter", "ChatFrame_AddMessageEventFilter" },
  { "setItemRef", "SetItemRef" },
  {
    "simpleHtml",
    function()
      local probe = CreateFrame("SimpleHTML")
      return type(probe.SetText) == "function"
        and type(probe.GetContentHeight) == "function"
        and type(probe.SetHyperlinksEnabled) == "function"
    end,
  },
  {
    "sharedMedia",
    function()
      local stub = rawget(_G, "LibStub")
      return stub ~= nil and stub:GetLibrary("LibSharedMedia-3.0", true) ~= nil
    end,
  },
  { "itemInfo", "C_Item.GetItemInfo" },
  { "spellInfo", "C_Spell.GetSpellInfo" },
  { "classColor", "C_ClassColor.GetClassColor" },
  { "container", "C_Container.GetContainerItemInfo" },
  { "tooltipPostCall", "TooltipDataProcessor.AddTooltipPostCall" },
  { "macros", "CreateMacro" },
  { "cvar", "C_CVar.GetCVar" },
  { "debugstack", "debugstack" },
  { "memoryUsage", "GetAddOnMemoryUsage" },
  {
    "resizeBounds",
    function()
      local probe = CreateFrame("Frame")
      return type(probe.SetResizeBounds) == "function"
    end,
  },
  -- Vector pen candidates, picked by measuring in the client.
  {
    "lineObject",
    function()
      local probe = CreateFrame("Frame")
      return type(probe.CreateLine) == "function"
    end,
  },
  {
    "lineThickness",
    function()
      local line = CreateFrame("Frame"):CreateLine()
      return type(line.SetThickness) == "function" and type(line.SetStartPoint) == "function"
    end,
  },
  {
    "lineColorTexture",
    function()
      local line = CreateFrame("Frame"):CreateLine()
      return type(line.SetColorTexture) == "function"
    end,
  },
  {
    "pixelSnapping",
    function()
      local tex = CreateFrame("Frame"):CreateTexture()
      return type(tex.SetSnapToPixelGrid) == "function" and type(tex.SetTexelSnappingBias) == "function"
    end,
  },
  {
    "propagateKeyboard",
    function()
      local probe = CreateFrame("Frame")
      return type(probe.SetPropagateKeyboardInput) == "function"
    end,
  },
}
ns.CAPABILITY_PROBES = PROBES

function ns.ProbeCapabilities()
  for _, probe in ipairs(PROBES) do
    local key, test = probe[1], probe[2]
    local ok, result
    if type(test) == "function" then
      ok, result = pcall(test)
    else
      ok, result = pcall(has, test)
    end
    can[key] = ok and result and true or false
  end
  return can
end

function ns.GetCVar(name)
  if can.cvar then
    local ok, v = pcall(C_CVar.GetCVar, name)
    return ok and v or nil
  end
  if type(GetCVar) == "function" then
    local ok, v = pcall(GetCVar, name)
    return ok and v or nil
  end
end

-- Writes a console variable; false when the client refuses it (a protected variable, an unknown name).
function ns.SetCVar(name, value)
  local api = rawget(_G, "C_CVar")
  local set = type(api) == "table" and api.SetCVar or rawget(_G, "SetCVar")
  if type(set) ~= "function" then
    return false
  end
  local ok, result = pcall(set, name, value)
  return ok and result ~= false
end

-- Addon restrictions (C_RestrictedActions): while one is active the client refuses addon calls
-- on Blizzard frames and on some functions and raises ADDON_ACTION_BLOCKED/FORBIDDEN, which no
-- pcall can stop. Names are keys of Enum.AddOnRestrictionType: Combat, Encounter, ChallengeMode,
-- PvPMatch, Map, Chat. False when the client has no such API.
function ns.AddonRestricted(...)
  local api, enum = rawget(_G, "C_RestrictedActions"), rawget(_G, "Enum")
  local types = type(enum) == "table" and enum.AddOnRestrictionType
  if type(api) ~= "table" or type(api.IsAddOnRestrictionActive) ~= "function" or type(types) ~= "table" then
    return false
  end
  for i = 1, select("#", ...) do
    local value = types[(select(i, ...))]
    if value ~= nil then
      local ok, active = pcall(api.IsAddOnRestrictionActive, value)
      if ok and active == true then
        return true
      end
    end
  end
  return false
end

-- Is the player in combat lockdown? False when the client has no such function.
function ns.InCombat()
  local fn = rawget(_G, "InCombatLockdown")
  return type(fn) == "function" and fn() == true
end

-- Combat lock the player opted into ("Lock in combat", settings.combatLock, off by default): true only in
-- combat lockdown with the option on. Every check that only exists to keep our own UI quiet in a fight asks
-- this instead of ns.InCombat(), so nothing of ours is locked unless the player wants it.
function ns.CombatLocked()
  local settings = ns.db and ns.db.settings
  return type(settings) == "table" and settings.combatLock == true and ns.InCombat()
end

local BLOCKED_NOTICE_GAP = 4
local blockedAt

-- For what Blizzard forbids in combat (protected frames, secure buttons, macros, bindings): the caller has
-- already seen that the call is not allowed and does nothing. This shows one throttled line and returns
-- true, so the call site reads `if ns.CombatBlocked() then return end`. Nothing is queued for later.
function ns.CombatBlocked(reason)
  local now = type(GetTime) == "function" and GetTime() or 0
  if blockedAt == nil or now - blockedAt >= BLOCKED_NOTICE_GAP then
    blockedAt = now
    if ns.Notify and ns.L then
      ns.Notify(ns.L["combat.blocked"], "warning", { reason = reason })
    end
  end
  return true
end

-- May this addon call protected methods (Show, Hide, SetPoint, ...) on the frame right now? The
-- silent flag keeps the check itself from raising ADDON_ACTION_BLOCKED. True when unknown.
function ns.ProtectedAllowed(frame)
  local api = rawget(_G, "C_RestrictedActions")
  if type(api) ~= "table" or type(api.CheckAllowProtectedFunctions) ~= "function" then
    return true
  end
  local ok, allowed = pcall(api.CheckAllowProtectedFunctions, frame, true)
  return not ok or allowed ~= false
end

-- Frames whose Hide the client refused (a protected window in combat): they close when the combat ends.
local deferredHides = {}

-- Hides the frame when the client lets this add-on do it now. Otherwise the hide waits for the end of the
-- combat (ns.FlushDeferredHides) and the call is never made, so no ADDON_ACTION_BLOCKED is raised. Returns
-- true when the frame was hidden.
function ns.SafeHide(frame)
  if not frame then
    return false
  end
  if ns.ProtectedAllowed(frame) then
    frame:Hide()
    return true
  end
  deferredHides[frame] = true
  return false
end

function ns.FlushDeferredHides()
  for frame in pairs(deferredHides) do
    if ns.ProtectedAllowed(frame) then
      deferredHides[frame] = nil
      frame:Hide()
    end
  end
end

-- Key propagation of a frame. In combat the client blocks the call and reports it as an addon
-- action, so nothing is called then and the frame keeps its last state. The method runs inside
-- a Lua closure: a protected function handed straight to pcall shows up as UNKNOWN(). Returns
-- whether the call ran.
function ns.PropagateKeys(frame, flag)
  local inCombat = rawget(_G, "InCombatLockdown")
  if type(inCombat) == "function" then
    local ok, locked = pcall(inCombat)
    if ok and locked then
      return false
    end
  end
  local method = frame and frame.SetPropagateKeyboardInput
  if type(method) ~= "function" then
    return false
  end
  return (pcall(function()
    method(frame, flag)
  end))
end

function ns.ClientInfo()
  local info = {}
  if type(GetBuildInfo) == "function" then
    info.version, info.build, info.date, info.interface = GetBuildInfo()
  end
  info.projectId = rawget(_G, "WOW_PROJECT_ID")
  info.projectCamelot = rawget(_G, "WOW_PROJECT_CAMELOT")
  info.locale = type(GetLocale) == "function" and GetLocale() or "?"
  return info
end
