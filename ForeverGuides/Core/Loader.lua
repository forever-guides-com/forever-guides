-- Loads LoadOnDemand data addons and collects what they register.
local _, ns = ...

ns.Data = ns.Data or {}

ns.Packages = {}

-- Returns true when loaded (or already loaded), false plus reason otherwise.
function ns.LoadPackage(name)
  if ns.Packages[name] and ns.Packages[name].status == "loaded" then
    return true
  end
  local loader = (ns.can.addOnsApi and C_AddOns.LoadAddOn) or (ns.can.loadAddOnLegacy and LoadAddOn)
  if not loader then
    return false, "no-loader"
  end
  local ok, loaded, reason = pcall(loader, name)
  if not ok then
    return false, tostring(loaded)
  end
  if not loaded then
    ns.Log.warn("package %s not loaded: %s", name, tostring(reason))
    return false, reason
  end
  return true
end

-- State of an add-on of ours for the settings page: "loaded" (in use, or enabled and loaded on
-- demand), "disabled" (installed, switched off) or "missing". Every client call is guarded.
function ns.PackageState(name)
  local addons = rawget(_G, "C_AddOns")
  addons = type(addons) == "table" and addons or {}
  local function call(modern, legacy, ...)
    local fn = addons[modern] or (legacy and rawget(_G, legacy))
    if type(fn) ~= "function" then
      return nil
    end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then
      return a, b, c, d, e
    end
  end
  if (ns.Packages[name] and ns.Packages[name].status == "loaded") or call("IsAddOnLoaded", "IsAddOnLoaded", name) then
    return "loaded"
  end
  local info, _, _, _, reason = call("GetAddOnInfo", "GetAddOnInfo", name)
  if type(info) == "table" then
    info, reason = info.name, info.reason
  end
  if info == nil or reason == "MISSING" then
    return "missing"
  end
  -- Only the C_AddOns order (name, character): the old global takes them the other way round.
  local state = call("GetAddOnEnableState", nil, name)
  if reason == "DISABLED" or state == 0 then
    return "disabled"
  end
  return "loaded"
end

function ns.DataStatusText()
  local L = ns.L
  local m = ns.Data.Manifest
  if not m then
    return L["data.notLoaded"]
  end
  return string.format(L["data.status"], tostring(m.dataStamp or "?"), tostring(m.build or "?"))
end
