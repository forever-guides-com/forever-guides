-- Access to the profession route data of the load-on-demand add-on "Forever Guides: Professions".
-- The add-on fills ns.ProfessionData[slug] (docs/BERUFSROUTE-FORMAT.md); this module loads it when
-- first asked and tells apart "add-on missing" from "no route for this profession".
local _, ns = ...

local D = {}
ns.ProfessionRouteData = D

D.ADDON = "ForeverGuides_Professions"
D.STATUS = { ok = "ok", missing = "missing", noRoute = "noRoute" }

ns.AddLocale("enUS", {
  ["profdata.missing"] = "Data add-on missing: install Forever Guides: Professions.",
  ["profdata.noRoute"] = "No route for this profession.",
})
ns.AddLocale("deDE", {
  ["profdata.missing"] = "Daten-Addon fehlt: Forever Guides: Berufsdaten installieren.",
  ["profdata.noRoute"] = "Keine Route für diesen Beruf.",
})

local attempted, loaded = false, false

local function route(slug)
  local all = rawget(ns, "ProfessionData")
  local data = type(all) == "table" and type(slug) == "string" and all[slug] or nil
  if type(data) == "table" and type(data.steps) == "table" then
    return data
  end
end

-- One load attempt per session: a missing add-on does not become present without a reload.
local function load()
  if loaded then
    return true
  end
  if attempted then
    return false
  end
  attempted = true
  loaded = ns.LoadPackage(D.ADDON) == true
  return loaded
end

-- Returns data, "ok" for a profession with a route, else nil plus "missing" (add-on not loadable)
-- or "noRoute" (add-on there, no entry for the slug).
function D.Get(slug)
  local data = route(slug)
  if data then
    return data, D.STATUS.ok
  end
  if not load() then
    return nil, D.STATUS.missing
  end
  data = route(slug)
  if data then
    return data, D.STATUS.ok
  end
  return nil, D.STATUS.noRoute
end

-- The hint text for a status other than "ok".
function D.Hint(status)
  return ns.L[status == D.STATUS.missing and "profdata.missing" or "profdata.noRoute"]
end

-- Forgets the load attempt (tests).
function D.Reset()
  attempted, loaded = false, false
end

-- The package banner switched the add-on on: ask again, the old "missing" answer is out of date.
ns.On("FG_PACKAGE_CHANGED", function(_, name)
  if name == D.ADDON then
    D.Reset()
  end
end)
