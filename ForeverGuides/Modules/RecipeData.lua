-- Access to the recipe database of the load-on-demand add-on "Forever Guides: Rezepte". The add-on
-- fills ns.RecipeData[slug] (docs/REZEPT-FORMAT.md); this module loads it when first asked and tells
-- apart "add-on missing or off" from "no recipes for this profession". The table of the add-on is
-- ns.RecipeData itself, so the module lives under another name.
local _, ns = ...

local D = {}
ns.RecipeAccess = D

D.ADDON = "ForeverGuides_Recipes"
D.STATUS = { ok = "ok", missing = "missing", noData = "noData" }

ns.AddLocale("enUS", {
  ["recipes.missing"] = "Recipe data missing or switched off",
  ["recipes.noData"] = "No recipes for this profession.",
})
ns.AddLocale("deDE", {
  ["recipes.missing"] = "Rezeptdaten fehlen oder sind ausgeschaltet",
  ["recipes.noData"] = "Keine Rezepte für diesen Beruf.",
})

local attempted, loaded = false, false
-- Valid entries per slug, cut once from the data table.
local cache = {}

local function entry(slug)
  local all = rawget(ns, "RecipeData")
  local data = type(all) == "table" and type(slug) == "string" and all[slug] or nil
  if type(data) == "table" and type(data.list) == "table" then
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

-- Returns data, valid list, "ok" for a profession with recipes, else nil plus "missing" (add-on not
-- loadable) or "noData" (add-on there, no entry for the slug).
function D.Get(slug)
  local data = entry(slug)
  if not data then
    if not load() then
      return nil, nil, D.STATUS.missing
    end
    data = entry(slug)
    if not data then
      return nil, nil, D.STATUS.noData
    end
  end
  local cached = cache[slug]
  if not cached or cached.data ~= data then
    cached = { data = data, list = ns.RecipeLogic.Clean(data.list) }
    cache[slug] = cached
  end
  return data, cached.list, D.STATUS.ok
end

-- The hint text for a status other than "ok".
function D.Hint(status)
  return ns.L[status == D.STATUS.missing and "recipes.missing" or "recipes.noData"]
end

-- Forgets the load attempt and the cut lists (tests).
function D.Reset()
  attempted, loaded = false, false
  cache = {}
end

-- The package banner switched the add-on on: ask again, the old "missing" answer is out of date.
ns.On("FG_PACKAGE_CHANGED", function(_, name)
  if name == D.ADDON then
    D.Reset()
  end
end)
