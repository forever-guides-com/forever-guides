-- Location screenshots, game part: hide the UI, take the screenshot, show the UI
-- again. The UI always comes back: on the game's success/failure event, after a
-- timeout, on combat, logout and zoning. Nothing here touches protected actions.
local _, ns = ...
local L, S = ns.L, ns.ShotLogic

local Shot = { state = "idle", HIDE_DELAY = 0.35, TIMEOUT = 6 }
ns.Shot = Shot

local PLATE_CVARS = {
  "nameplateShowAll",
  "nameplateShowEnemies",
  "nameplateShowFriends",
  "UnitNameOwn",
  "UnitNameNPC",
  "UnitNameNonCombatCreatureName",
  "UnitNameFriendlyPlayerName",
  "UnitNameFriendlyPetName",
  "UnitNameFriendlyGuardianName",
  "UnitNameFriendlyTotemName",
  "UnitNameEnemyPlayerName",
  "UnitNameEnemyPetName",
  "UnitNameEnemyGuardianName",
  "UnitNameEnemyTotemName",
  "UnitNamePlayerGuild",
  "UnitNamePlayerPVPTitle",
}

local driver = CreateFrame("Frame")

local function fmt(key, ...)
  local ok, text = pcall(string.format, L[key], ...)
  return ok and text or L[key]
end

local function readCVar(name)
  local get = (C_CVar and C_CVar.GetCVar) or GetCVar
  local ok, v = pcall(get, name)
  return ok and v or nil
end

local function writeCVar(name, value)
  local set = (C_CVar and C_CVar.SetCVar) or SetCVar
  return type(set) == "function" and pcall(set, name, value)
end

-- Extension the game writes now (jpg, png or tga), from CVar screenshotFormat; jpg when unknown.
function Shot.Format()
  return S.formatExt(readCVar("screenshotFormat")) or "jpg"
end

-- File name the game gives this entry's picture, e.g. WoWScrnShot_100526_140309.jpg.
function Shot.ExpectedFile(e)
  return S.expectedName(e, Shot.Format())
end

function Shot.PlatesEnabled()
  return S.meta().plates ~= false
end

function Shot.SetPlates(on)
  S.meta().plates = on and true or false
end

local function hidePlates()
  local meta = S.meta()
  if meta.restore or not Shot.PlatesEnabled() then
    return
  end
  local saved = {}
  for _, name in ipairs(PLATE_CVARS) do
    local v = readCVar(name)
    if v ~= nil and v ~= "0" then
      saved[name] = v
      writeCVar(name, "0")
    end
  end
  if next(saved) then
    meta.restore = saved
  end
end

-- Also called at login, in case the last session ended while the plates were off.
function Shot.RestorePlates()
  local meta = S.meta()
  if type(meta.restore) == "table" then
    for name, value in pairs(meta.restore) do
      if type(name) == "string" and type(value) == "string" then
        writeCVar(name, value)
      end
    end
  end
  meta.restore = nil
end

local function showUI()
  Shot.RestorePlates()
  if Shot.hid then
    local ok = pcall(UIParent.Show, UIParent)
    if ok then
      Shot.hid = false
    else
      Shot.retryShow = true
    end
  end
end

local function finish(result, entry)
  driver:SetScript("OnUpdate", nil)
  local e = entry or Shot.entry
  Shot.state, Shot.entry = "idle", nil
  showUI()
  if result == "failed" and e then
    S.removeLast(e)
  end
  if result == "abort" then
    ns.Notify(L["shots.msg.abort"], "info")
  elseif result == "failed" then
    ns.Notify(L["shots.msg.failed"], "error")
  elseif e then
    local pos = e.x and e.y and string.format("%.1f / %.1f", e.x * 100, e.y * 100) or "?"
    ns.Notify(fmt("shots.msg.saved", e.id, e.lt, e.zone, pos, S.unsaved), "success")
    if result == "timeout" then
      ns.Notify(L["shots.msg.timeout"], "warning")
    end
  end
  -- The page selects the entry named here. When the page is hidden it refreshes on show.
  local id = e and S.get(e.id) and e.id or nil
  ns.Emit("FG_SHOTS_CHANGED", id)
  -- Once more after the interface had a frame to come back (list size and layout are settled).
  if C_Timer and C_Timer.After then
    C_Timer.After(0.3, function()
      ns.Emit("FG_SHOTS_CHANGED")
    end)
  end
end

local function snapshot()
  local info = {}
  local function try(fn, ...)
    if type(fn) ~= "function" then
      return nil
    end
    local ok, a, b = pcall(fn, ...)
    if ok then
      return a, b
    end
  end
  info.zone = try(GetZoneText) or ""
  info.sub = try(GetSubZoneText) or ""
  info.face = try(GetPlayerFacing)
  local map = C_Map and try(C_Map.GetBestMapForUnit, "player")
  if map then
    info.map = map
    local pos = try(C_Map.GetPlayerMapPosition, map, "player")
    if type(pos) == "table" and pos.GetXY then
      info.x, info.y = try(pos.GetXY, pos)
    end
  end
  local version, build = try(GetBuildInfo)
  info.build = version and (version .. " (" .. tostring(build) .. ")") or ""
  info.ver = ns.version
  return info
end

local function take()
  local e, why = S.add(snapshot())
  if not e then
    finish("quiet")
    ns.Notify(L["shots.msg." .. tostring(why)], "warning")
    return
  end
  Shot.entry = e
  ns.Emit("FG_SHOTS_CHANGED", e.id)
  local ok = pcall(Screenshot)
  if not ok then
    finish("failed", e)
    return
  end
  Shot.state, Shot.elapsed = "waiting", 0
end

function Shot.Tick(dt)
  Shot.elapsed = (Shot.elapsed or 0) + (dt or 0)
  if Shot.state == "hiding" and Shot.elapsed >= Shot.HIDE_DELAY then
    take()
  elseif Shot.state == "waiting" and Shot.elapsed >= Shot.TIMEOUT then
    finish("timeout")
  end
end

-- true, or false + reason ("busy", "combat", "limit", "noapi"), plus a list of warnings.
function Shot.Check()
  local warnings = {}
  if Shot.state ~= "idle" then
    return false, "busy", warnings
  end
  if type(Screenshot) ~= "function" then
    return false, "noapi", warnings
  end
  if InCombatLockdown() then
    return false, "combat", warnings
  end
  local ok, why = S.canAdd()
  if not ok then
    return false, why, warnings
  end
  if type(IsInInstance) == "function" and IsInInstance() then
    warnings[#warnings + 1] = "instance"
  end
  if type(IsResting) == "function" and IsResting() then
    warnings[#warnings + 1] = "city"
  end
  return true, nil, warnings
end

function Shot.Capture()
  local ok, why, warnings = Shot.Check()
  if not ok then
    ns.Notify(L["shots.msg." .. why], "warning")
    return false
  end
  for _, w in ipairs(warnings) do
    ns.Notify(L["shots.warn." .. w], "warning")
  end
  local hidden = pcall(function()
    Shot.hid = UIParent:IsShown()
    if Shot.hid then
      UIParent:Hide()
    end
  end)
  if not hidden then
    showUI()
    ns.Notify(L["shots.msg.abort"], "warning")
    return false
  end
  hidePlates()
  Shot.state, Shot.elapsed = "hiding", 0
  driver:SetScript("OnUpdate", function(_, dt)
    ns.Safe("shot-tick", Shot.Tick, dt)
  end)
  return true
end

function Shot.Binding()
  ns.Safe("shot", Shot.Capture)
end

function Shot.Save()
  if InCombatLockdown() then
    ns.Notify(L["shots.msg.saveCombat"], "warning")
    return false
  end
  if type(ReloadUI) ~= "function" then
    return false
  end
  ReloadUI()
  return true
end

function Shot.Slash(rest)
  rest = (rest or ""):lower()
  if rest == "list" or rest == "liste" or rest == "page" or rest == "seite" then
    ns.Main.Show("shots")
  elseif rest == "save" or rest == "sichern" then
    Shot.Save()
  else
    Shot.Capture()
  end
end

ns.On("SCREENSHOT_SUCCEEDED", function()
  if Shot.state == "waiting" then
    finish("ok")
  end
end)

ns.On("SCREENSHOT_FAILED", function()
  if Shot.state == "waiting" then
    finish("failed")
  end
end)

local function abort()
  if Shot.state ~= "idle" then
    finish(Shot.state == "waiting" and "timeout" or "abort")
  end
end

ns.On("PLAYER_REGEN_DISABLED", abort)
ns.On("PLAYER_LOGOUT", abort)
ns.On("PLAYER_LEAVING_WORLD", abort)

ns.On("PLAYER_REGEN_ENABLED", function()
  if Shot.retryShow then
    Shot.retryShow = false
    Shot.hid = true
    showUI()
  end
end)

ns.On("PLAYER_LOGIN", function()
  Shot.RestorePlates()
end)
