-- Access to the gathering data of the load-on-demand add-on "Forever Guides: Gathering".
-- The add-on fills ns.GatherData (docs/GATHERING-FORMAT.md); this module loads it when first asked
-- and tells apart "add-on missing" from "add-on there, no usable data".
local _, ns = ...

local D = {}
ns.GatherDataAccess = D

D.ADDON = "ForeverGuides_Gathering"
D.STATUS = { ok = "ok", missing = "missing", noData = "noData" }

ns.AddLocale("enUS", {
  ["gatherdata.missing"] = "Data add-on missing: install Forever Guides: Gathering.",
  ["gatherdata.noData"] = "No gathering data found.",
})
ns.AddLocale("deDE", {
  ["gatherdata.missing"] = "Daten-Addon fehlt: Forever Guides: Sammelpunkte installieren.",
  ["gatherdata.noData"] = "Keine Sammeldaten gefunden.",
})

local attempted, loaded = false, false

local function current()
  local data = rawget(ns, "GatherData")
  if type(data) == "table" and type(data.zones) == "table" and type(data.items) == "table" and next(data.items) then
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

-- Returns data, "ok" when the data is there, else nil plus "missing" (add-on not loadable) or
-- "noData" (add-on loaded, but the table is empty or damaged).
function D.Get()
  local data = current()
  if data then
    return data, D.STATUS.ok
  end
  if not load() then
    return nil, D.STATUS.missing
  end
  data = current()
  if data then
    return data, D.STATUS.ok
  end
  return nil, D.STATUS.noData
end

-- The hint text for a status other than "ok".
function D.Hint(status)
  return ns.L[status == D.STATUS.missing and "gatherdata.missing" or "gatherdata.noData"]
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
