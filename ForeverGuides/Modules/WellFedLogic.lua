-- Well Fed logic without WoW API (ns.WellFedLogic), for the aura element: every food gives its own buff spell
-- and all of them are named "Well Fed" (German "Satt"), so a single spell id never says whether the player is
-- well fed. The generated table (Data/WellFed.lua) lists every such spell and its names. This file knows which
-- chosen spell is one of them, builds the set of ids the element looks for, and compares a readable aura name
-- with the names, which also catches an id a later patch adds. A name the game keeps secret arrives as nil and
-- is never compared.
local _, ns = ...

local W = {}
ns.WellFedLogic = W

-- The classic buff spell, the example of the preset (checked against the data in the tests).
W.SAMPLE = 19705

W.DEFAULTS = {
  -- Any well fed buff counts, not only the chosen id.
  anyWellFed = true,
}

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local built

local function sets()
  if built then
    return built
  end
  local data = ns.Data and ns.Data.WellFed or {}
  built = { ids = {}, names = {} }
  for _, id in ipairs(data.ids or {}) do
    built.ids[id] = true
  end
  for _, name in ipairs(data.names or {}) do
    built.names[name] = true
  end
  return built
end

-- The set of every well fed spell id. Shared, callers do not change it.
function W.Ids()
  return sets().ids
end

-- The set of the names of the buff in both languages. Shared, callers do not change it.
function W.Names()
  return sets().names
end

function W.IsId(id)
  return finite(id) and sets().ids[id] == true
end

-- Whether a readable aura or spell name is the name of the buff; a secret or missing name (nil) never is.
function W.IsName(name)
  return type(name) == "string" and sets().names[name] == true
end

-- Whether the chosen spell of an element is a well fed buff, by its base id, its exact id or (when the caller
-- could read it) its name.
function W.Chosen(p, name)
  return W.IsId(p.spellBase) or W.IsId(p.spellExact) or W.IsName(name)
end

-- Whether the element looks for any well fed buff: an aura (no proc, no weapon) whose chosen spell is one, with
-- the switch on.
function W.Applies(p, name)
  return p.source == "aura" and p.anyWellFed ~= false and W.Chosen(p, name)
end

-- `ids` (a set) joined with every well fed id, as a new set.
function W.Join(ids)
  local out = {}
  for id in pairs(sets().ids) do
    out[id] = true
  end
  for id in pairs(ids) do
    out[id] = true
  end
  return out
end

-- The switch of a saved element repaired; a missing value is the default (on).
function W.Clean(raw, d)
  if type(raw.anyWellFed) == "boolean" then
    return { anyWellFed = raw.anyWellFed }
  end
  return { anyWellFed = d.anyWellFed }
end
