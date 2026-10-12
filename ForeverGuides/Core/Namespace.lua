-- The one addon-wide global is `ForeverGuides` (Bindings.xml, LoD data
-- addons and the Addon Compartment need a stable name). Everything else
-- lives on this namespace table.
local ADDON_NAME, ns = ...

ForeverGuides = ns
ns.name = ADDON_NAME
-- Stable tutorial/target ids -> frames, filled by the UI.
ns.Anchors = {}

local function metadata(field)
  local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if type(getter) ~= "function" then
    return nil
  end
  local ok, value = pcall(getter, ADDON_NAME, field)
  return ok and value or nil
end

ns.version = metadata("Version") or "dev"

local U = {}
ns.U = U

function U.trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function U.split(s, sep)
  local out = {}
  for part in tostring(s or ""):gmatch("[^" .. sep .. "]+") do
    out[#out + 1] = part
  end
  return out
end

function U.clamp(v, lo, hi)
  if v < lo then
    return lo
  elseif v > hi then
    return hi
  end
  return v
end

function U.round(v, step)
  step = step or 1
  -- Strip float noise (0.05 steps would give 1.2000000000000002).
  return tonumber(string.format("%.6f", math.floor(v / step + 0.5) * step))
end

-- Parent of a frame that may belong to the game (mouse focus walks): nil at the top, for forbidden
-- frames and when the client refuses the call to tainted code. Never raises.
function ns.SafeParent(node)
  if type(node) ~= "table" then
    return nil
  end
  local ok, parent = pcall(function()
    if node.IsForbidden and node:IsForbidden() then
      return nil
    end
    return node:GetParent()
  end)
  return ok and type(parent) == "table" and parent or nil
end

function U.copy(t)
  if type(t) ~= "table" then
    return t
  end
  local out = {}
  for k, v in pairs(t) do
    out[k] = U.copy(v)
  end
  return out
end

-- Fills missing keys from defaults, recursing into tables, and keeps
-- unknown keys (downgrade-safe SavedVariables).
function U.applyDefaults(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then
      target[k] = U.copy(v)
    elseif type(v) == "table" and type(target[k]) == "table" then
      U.applyDefaults(target[k], v)
    end
  end
  return target
end

function U.hex(hex)
  hex = hex:gsub("#", "")
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function U.now()
  local ok, t = pcall(time)
  return ok and t or 0
end

function U.sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end
