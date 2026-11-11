-- Display settings of the instances page, kept in the account settings (Core/Store.lua): the favorite
-- instances and the pin size of the dungeon map. Display state only, no instance data. A favorite is the
-- slug of the instance (RefLogic.InstanceSlug), stored as a set { [slug] = true } so a toggle needs no search.
-- Every change goes through Store.set, so FG_SETTING_CHANGED tells the views.
local _, ns = ...

local D = {}
ns.InstanceDisplay = D

-- Pin size of the dungeon map in percent of the normal size.
D.PIN_MIN, D.PIN_MAX, D.PIN_DEFAULT, D.PIN_STEP = 60, 200, 100, 10

local FAVORITES, PIN = "settings.instanceFavorites", "settings.dungeonPinScale"

local function settings()
  return ns.db and ns.db.settings
end

-- Pin size ----------------------------------------------------------------------------------------

-- A damaged value (not a number, NaN, infinite) is the default, anything else is rounded and clamped.
function D.ClampPin(value)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    return D.PIN_DEFAULT
  end
  return math.max(D.PIN_MIN, math.min(D.PIN_MAX, math.floor(value + 0.5)))
end

-- Stored pin size in percent (60 to 200).
function D.PinScale()
  local s = settings()
  return D.ClampPin(s and s.dungeonPinScale)
end

-- The same as a factor for the pin sizes (0.6 to 2).
function D.PinFactor()
  return D.PinScale() / 100
end

function D.SetPinScale(value)
  local clamped = D.ClampPin(value)
  ns.Store.set(PIN, clamped)
  return clamped
end

-- Favorites ---------------------------------------------------------------------------------------

local function valid(slug)
  return type(slug) == "string" and slug ~= ""
end

local function stored()
  local s = settings()
  local set = s and s.instanceFavorites
  return type(set) == "table" and set or {}
end

function D.IsFavorite(slug)
  return valid(slug) and stored()[slug] == true
end

-- The favorites as a list of slugs, sorted, so a view and a test see one order.
function D.Favorites()
  local out = {}
  for slug, on in pairs(stored()) do
    if valid(slug) and on == true then
      out[#out + 1] = slug
    end
  end
  table.sort(out)
  return out
end

function D.FavoriteCount()
  return #D.Favorites()
end

-- Marks or unmarks an instance. The settings table is replaced, never changed in place, so a listener
-- holding the old table keeps a consistent copy. Returns the new state.
function D.SetFavorite(slug, on)
  if not valid(slug) then
    return false
  end
  local set = {}
  for key, value in pairs(stored()) do
    if valid(key) and value == true then
      set[key] = true
    end
  end
  set[slug] = on and true or nil
  ns.Store.set(FAVORITES, set)
  return set[slug] == true
end

function D.ToggleFavorite(slug)
  return D.SetFavorite(slug, not D.IsFavorite(slug))
end

function D.ClearFavorites()
  ns.Store.set(FAVORITES, {})
end
