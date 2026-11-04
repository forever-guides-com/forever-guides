-- Which game client runs the add-on: the Forever client (Classic base, interface 16xxx) or Retail 12
-- (interface 12xxxx). One code base serves both; every place that needs to know asks here and the
-- differences are listed in docs/CLIENTS.md. Anything not recognised counts as "unknown" and is treated
-- like Forever, the client this add-on is built for.
local _, ns = ...

local Client = {}
ns.Client = Client

Client.FOREVER, Client.RETAIL, Client.UNKNOWN = "forever", "retail", "unknown"

-- Value of settings.clientOverride: "auto" detects, the two flavors force one (hidden setting for tests).
Client.OVERRIDES = { auto = true, forever = true, retail = true }

local function inRange(n, low, high)
  return type(n) == "number" and n >= low and n <= high
end

-- Flavor of a number that is an interface number or a build number: 16000..16999 Forever, 120000..129999 Retail.
local function byNumber(n)
  n = tonumber(n)
  if inRange(n, 16000, 16999) then
    return Client.FOREVER
  elseif inRange(n, 120000, 129999) then
    return Client.RETAIL
  end
end

local function byProject(id)
  if id == nil then
    return nil
  end
  if id == rawget(_G, "WOW_PROJECT_CAMELOT") then
    return Client.FOREVER
  elseif id == rawget(_G, "WOW_PROJECT_MAINLINE") then
    return Client.RETAIL
  end
end

-- Major version of "12.0.7" or "1.60.1".
local function byVersion(version)
  local major = type(version) == "string" and tonumber(version:match("^(%d+)%."))
  if major == 12 then
    return Client.RETAIL
  elseif major == 1 then
    return Client.FOREVER
  end
end

local function readBuild()
  local fn = rawget(_G, "GetBuildInfo")
  if type(fn) ~= "function" then
    return nil, nil, nil
  end
  local ok, version, build, _, interface = pcall(fn)
  if not ok then
    return nil, nil, nil
  end
  return version, tonumber(build), tonumber(interface)
end

-- What the game itself says, never the override: flavor, source ("interface", "build", "project",
-- "version" or "none"), version, build, interface.
function Client.Detect()
  local version, build, interface = readBuild()
  local flavor, source = byNumber(interface), "interface"
  if not flavor then
    flavor, source = byNumber(build), "build"
  end
  if not flavor then
    flavor, source = byProject(rawget(_G, "WOW_PROJECT_ID")), "project"
  end
  if not flavor then
    flavor, source = byVersion(version), "version"
  end
  if not flavor then
    return Client.UNKNOWN, "none", version, build, interface
  end
  return flavor, source, version, build, interface
end

-- "auto", "forever" or "retail" (the hidden setting; anything else counts as "auto").
function Client.Override()
  local settings = ns.db and ns.db.settings
  local value = settings and settings.clientOverride
  return Client.OVERRIDES[value] and value or "auto"
end

-- Sets the override. False for a value that does not exist.
function Client.SetOverride(value)
  if not Client.OVERRIDES[value] or not (ns.db and ns.db.settings) then
    return false
  end
  ns.db.settings.clientOverride = value
  ns.Emit("FG_CLIENT_CHANGED", Client.Flavor())
  return true
end

function Client.Flavor()
  local override = Client.Override()
  if override ~= "auto" then
    return override
  end
  return (Client.Detect())
end

function Client.IsForever()
  return Client.Flavor() == Client.FOREVER
end

function Client.IsRetail()
  return Client.Flavor() == Client.RETAIL
end

-- { flavor, detected, source, override, interface, build, version }. source is "override" when forced.
function Client.Info()
  local detected, source, version, build, interface = Client.Detect()
  local override = Client.Override()
  return {
    flavor = override ~= "auto" and override or detected,
    detected = detected,
    source = override ~= "auto" and "override" or source,
    override = override,
    interface = interface,
    build = build,
    version = version,
  }
end

ns.AddLocale("enUS", {
  ["client.forever"] = "Forever",
  ["client.retail"] = "Retail",
  ["client.unknown"] = "unknown",
  ["client.line"] = "Game client: %s",
  ["client.lineForced"] = "Game client: %s (set by hand, detected: %s)",
})
ns.AddLocale("deDE", {
  ["client.forever"] = "Forever",
  ["client.retail"] = "Retail",
  ["client.unknown"] = "unbekannt",
  ["client.line"] = "Spiel-Client: %s",
  ["client.lineForced"] = "Spiel-Client: %s (von Hand gesetzt, erkannt: %s)",
})

-- One display line for the settings and info pages.
function Client.Line()
  local info = Client.Info()
  local L = ns.L
  if info.override ~= "auto" then
    return string.format(L["client.lineForced"], L["client." .. info.flavor], L["client." .. info.detected])
  end
  return string.format(L["client.line"], L["client." .. info.flavor])
end

-- Plain English line for /fg diag and the support report.
function Client.DiagLine()
  local info = Client.Info()
  return string.format(
    "flavor=%s source=%s detected=%s override=%s interface=%s build=%s",
    info.flavor,
    info.source,
    info.detected,
    info.override,
    tostring(info.interface),
    tostring(info.build)
  )
end
