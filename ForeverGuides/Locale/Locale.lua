-- L["key"] resolves active locale -> enUS -> key itself. Missing keys are
-- logged once to the internal log.
local _, ns = ...

ns.Locales = ns.Locales or {}
local active = "enUS"
local warned = {}
local nilWarned = false

local L = setmetatable({}, {
  __index = function(_, key)
    if key == nil then
      -- A caller without its key must not break the frame script it runs in (a table index cannot be nil).
      if not nilWarned and ns.Log then
        nilWarned = true
        ns.Log.debug("nil locale key")
      end
      return ""
    end
    local t = ns.Locales[active]
    local v = t and t[key]
    if v == nil then
      v = ns.Locales.enUS and ns.Locales.enUS[key]
      if not warned[key] and active ~= "enUS" and ns.Log then
        warned[key] = true
        ns.Log.debug("missing %s string: %s", active, tostring(key))
      end
    end
    -- {key:id} and {mod:id} name the current key combination (Core/Keys.lua).
    if type(v) == "string" and ns.Keys and v:find("{", 1, true) then
      v = ns.Keys.Expand(v)
    end
    return v or key
  end,
})
ns.L = L

function ns.ResolveLocale(setting, clientLocale)
  if setting == "deDE" or setting == "enUS" then
    return setting
  end
  return clientLocale == "deDE" and "deDE" or "enUS"
end

function ns.SetLocale(setting)
  local client = type(GetLocale) == "function" and GetLocale() or "enUS"
  active = ns.ResolveLocale(setting, client)
  return active
end

function ns.GetActiveLocale()
  return active
end

-- Picks the right language from data fields shaped { de = "...", en = "..." }.
function ns.T(field)
  if type(field) ~= "table" then
    return field
  end
  if active == "deDE" then
    return field.de or field.en
  end
  return field.en or field.de
end

-- Modules ship their own strings next to their code.
function ns.AddLocale(locale, strings)
  local t = ns.Locales[locale] or {}
  ns.Locales[locale] = t
  for k, v in pairs(strings) do
    t[k] = v
  end
end
