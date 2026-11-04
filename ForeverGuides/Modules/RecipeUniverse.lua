-- The recipe universe of each profession for the guild sync (function crafting): the spell ids of the
-- recipe data, sorted by id (not by skill), with the rank of every id and the checksum `u` of the whole
-- list. Both sides of an exchange need the same universe to read a bit mask: bit k stands for the k-th id,
-- so a different data version shows up as a different `u` and the sender falls back to an id list.
-- Built lazily from the data of ForeverGuides_Recipes (RecipeAccess loads it on the first ask) with
-- GuildSyncCodec.NewUniverse. A change of the data (reload of the package, other entries) is noticed on
-- the next ask: the universe is rebuilt and FG_RECIPE_UNIVERSE_CHANGED(slug, newChecksum) fires.
local _, ns = ...
local G = ns.GuildSyncCodec

local U = {}
ns.RecipeUniverse = U

-- Number of rebuilds that changed a universe since the start; a cache of results compares this.
U.rev = 0

-- cache[slug] = { data, count, universe }; index[spell] = slug, rebuilt after any change.
local cache, index = {}, nil

local function slugs()
  return ns.ProfessionRouteLogic.SLUGS
end

-- The universe { ids, size, rank, sum } of a profession slug, or nil and the reason: "missing" (data add-on
-- not loadable), "noData" (no entry for the slug), "size" (more ids than the protocol carries).
function U.Get(slug)
  local data, _, status = ns.RecipeAccess.Get(slug)
  if not data then
    return nil, status
  end
  local list = data.list
  local c = cache[slug]
  if c and c.data == data and c.count == #list then
    return c.universe
  end
  local ids = {}
  for _, r in ipairs(list) do
    if type(r) == "table" and type(r.s) == "number" then
      ids[#ids + 1] = r.s
    end
  end
  local universe, why = G.NewUniverse(ids)
  if not universe then
    return nil, why
  end
  local changed = c ~= nil and c.universe.sum ~= universe.sum
  cache[slug] = { data = data, count = #list, universe = universe }
  index = nil
  if c == nil or changed then
    U.rev = U.rev + 1
  end
  if changed then
    ns.Emit("FG_RECIPE_UNIVERSE_CHANGED", slug, universe.sum)
  end
  return universe
end

-- Checksum `u` of a profession, 0 when there is no universe.
function U.Sum(slug)
  local universe = U.Get(slug)
  return universe and universe.sum or 0
end

-- Skill line id of a slug (the job id on the wire) and back.
function U.JobId(slug)
  local p = ns.ProfessionRouteLogic.PROFESSIONS[slug]
  return p and p.id or nil
end

function U.SlugOfJob(id)
  for _, slug in ipairs(slugs()) do
    if U.JobId(slug) == id then
      return slug
    end
  end
end

-- The profession a spell id belongs to (first slug in list order when a data error lists it twice), nil
-- when no universe holds it. Loads all professions once.
function U.JobOf(spell)
  for _, slug in ipairs(slugs()) do
    U.Get(slug)
  end
  if not index then
    index = {}
    for _, slug in ipairs(slugs()) do
      local c = cache[slug]
      for _, id in ipairs(c and c.universe.ids or {}) do
        index[id] = index[id] or slug
      end
    end
  end
  return index[spell]
end

-- Forgets everything built (tests). A changed data package needs no call: Get compares the data table.
function U.Reset()
  cache, index = {}, nil
end
