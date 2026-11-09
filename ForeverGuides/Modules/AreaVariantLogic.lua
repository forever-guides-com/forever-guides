-- Layout variants of a HUD window, without WoW API (ns.AreaVariants). A window has one default layout
-- (items[id].layoutId) and up to MAX_EXTRA further variants (items[id].variants, layout ids in order). Which
-- variant a character draws resolves like the layout of the cursor ring (ns.LayoutAssign): the variant this
-- character chose (charDB.areas[id].variant), else the variant of its class (items[id].classVariants), else the
-- default. A value that names a layout that is not a variant of the window counts as not set and the next step
-- answers. A later rule by situation (fishing, mounted, combat) is one more step in LayoutAssign.Candidates.
local _, ns = ...
local LA = ns.LayoutAssign

local AV = {
  MAX_EXTRA = 5,
}
ns.AreaVariants = AV

local function text(v)
  return type(v) == "string" and v ~= "" and v or nil
end

-- The extra variants of a stored window: layout ids in order, each once, never the default, at most MAX_EXTRA.
function AV.Extra(item)
  local out = {}
  if type(item) ~= "table" or type(item.variants) ~= "table" then
    return out
  end
  local seen = { [item.layoutId] = true }
  for _, id in ipairs(item.variants) do
    if text(id) and not seen[id] and #out < AV.MAX_EXTRA then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  return out
end

-- Every layout id of the window, the default first.
function AV.Ids(item)
  local out = {}
  if type(item) ~= "table" or not text(item.layoutId) then
    return out
  end
  out[1] = item.layoutId
  for _, id in ipairs(AV.Extra(item)) do
    out[#out + 1] = id
  end
  return out
end

function AV.Has(item, id)
  for _, own in ipairs(AV.Ids(item)) do
    if own == id then
      return true
    end
  end
  return false
end

-- The variant this player draws: returns its id (nil when the window has no layout), where it comes from
-- ("char", "class" or "account" for the default) and whether an entry in front of the winner is dead.
-- `exists(id)` tells whether the layout is in the library.
function AV.Resolve(item, charVariant, classToken, exists)
  if type(item) ~= "table" then
    return nil, nil, false
  end
  local function usable(id)
    return AV.Has(item, id) and exists(id) == true
  end
  return LA.Resolve(item.layoutId, charVariant, item.classVariants, classToken, usable)
end

-- The stored class map without the entries that name no variant of the window; nil when nothing is left.
function AV.CleanClassMap(item)
  local out = {}
  for token, id in pairs(LA.CleanClasses(type(item) == "table" and item.classVariants or nil)) do
    if AV.Has(item, id) then
      out[token] = id
    end
  end
  return next(out) ~= nil and out or nil
end

-- The assignment after variant `id` gets `scope` ("char", "class" or nil) for this player: the new character
-- variant (nil: none), the new class map (nil: empty) and a reason when nothing could change.
function AV.Plan(item, charVariant, classToken, id, scope)
  if not AV.Has(item, id) then
    return charVariant, AV.CleanClassMap(item), "missing"
  end
  local char, map, reason = LA.Plan(charVariant, AV.CleanClassMap(item), classToken, id, scope)
  return char, next(map) ~= nil and map or nil, reason
end

-- The assignments of this player and of the class map once variant `id` is gone.
function AV.Forget(charVariant, classMap, id)
  local char, map = LA.Forget(charVariant, classMap, id)
  return char, next(map) ~= nil and map or nil
end

-- How variant `id` is assigned for this player: "char", "class" or nil, and the class tokens that use it.
function AV.ScopeOf(item, charVariant, classToken, id)
  return LA.ScopeOf(id, charVariant, AV.CleanClassMap(item), classToken), LA.ClassesOf(id, AV.CleanClassMap(item))
end

-- The letter of a variant by its place: 1 is "A", 2 is "B", up to "Z".
function AV.Letter(index)
  if type(index) ~= "number" or index < 1 or index > 26 then
    return "?"
  end
  return string.char(64 + math.floor(index))
end

-- The first letter ("B", "C", ...) whose name `fmt` (a format with one %s) nobody in `names` (a set of lower case
-- names) has; letters after "Z" fall back to a number.
function AV.NextName(fmt, names)
  for index = 2, 26 do
    local name = string.format(fmt, AV.Letter(index))
    if not names[name:lower()] then
      return name
    end
  end
  local n = 27
  while names[string.format(fmt, tostring(n)):lower()] do
    n = n + 1
  end
  return string.format(fmt, tostring(n))
end
