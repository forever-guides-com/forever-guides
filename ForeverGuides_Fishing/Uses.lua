-- What a fish is used for: the recipes that take it as a reagent. Pure: the generated table (fish.UsesData,
-- ids and numbers from the client tables) and the recipe lists of the Forever Guides profession data come in,
-- rows come out. The names of recipes, results and professions are not stored here, they come from the recipe
-- data, the client or the locale file.
local _, fish = ...
if not fish.FG then
  return
end

local U = {}
fish.Uses = U

-- Skill line of the client to the slug of the profession data (docs/REZEPT-FORMAT.md). A line that is not here
-- still gives a row, it only has no recipe data and shows as "profession <line>".
U.SLUGS = {
  [129] = "first-aid",
  [164] = "blacksmithing",
  [165] = "leatherworking",
  [171] = "alchemy",
  [185] = "cooking",
  [197] = "tailoring",
  [202] = "engineering",
  [333] = "enchanting",
  [356] = "fishing",
}

-- The ids of the fish list as a set.
function U.FishSet(data)
  local set = {}
  if type(data) == "table" and type(data.fish) == "table" then
    for _, id in ipairs(data.fish) do
      set[id] = true
    end
  end
  return set
end

-- The raw uses of a fish from the generated table: { { spell, line, result, qty } }, in table order.
function U.Raw(data, id)
  local out = {}
  local list = type(data) == "table" and type(data.uses) == "table" and data.uses[id] or nil
  if type(list) ~= "table" then
    return out
  end
  for _, use in ipairs(list) do
    if type(use) == "table" and type(use.s) == "number" then
      out[#out + 1] = { spell = use.s, line = use.l, result = use.r, qty = use.q or 1 }
    end
  end
  return out
end

-- The recipe of a spell in a profession list, nil when it is not there.
local function find(list, spell)
  for _, recipe in ipairs(list or {}) do
    if type(recipe) == "table" and recipe.s == spell then
      return recipe
    end
  end
end

-- The name of a recipe in a language ("deDE" or "enUS") from its name pair { german, english }.
function U.RecipeName(recipe, lang)
  if type(recipe) ~= "table" or type(recipe.n) ~= "table" then
    return nil
  end
  local de, en = recipe.n[1], recipe.n[2]
  local name = lang == "deDE" and (de or en) or (en or de)
  return type(name) == "string" and name ~= "" and name or nil
end

-- The rows of the uses of one fish. recipeOf(slug) gives the recipe list of a profession (or nil), lang is the
-- language of the names. Row: spell, line, slug, result, qty, name (nil when nobody knows it), skill (the
-- skill the recipe turns orange at, nil when unknown), removed (the recipe is not in Forever).
-- Rows are ordered by profession slug, then by skill, then by spell.
function U.Rows(data, id, recipeOf, lang)
  local rows = {}
  for _, use in ipairs(U.Raw(data, id)) do
    local slug = U.SLUGS[use.line]
    local list = slug and recipeOf and recipeOf(slug) or nil
    local recipe = find(list, use.spell)
    local skill = recipe and type(recipe.sk) == "table" and recipe.sk[1] or nil
    rows[#rows + 1] = {
      spell = use.spell,
      line = use.line,
      slug = slug,
      result = use.result or (recipe and recipe.i) or nil,
      qty = use.qty,
      name = U.RecipeName(recipe, lang),
      skill = type(skill) == "number" and skill > 0 and skill or nil,
      removed = recipe and recipe.rm == true or false,
    }
  end
  table.sort(rows, function(a, b)
    local x, y = a.slug or "~", b.slug or "~"
    if x ~= y then
      return x < y
    end
    local sa, sb = a.skill or 0, b.skill or 0
    if sa ~= sb then
      return sa < sb
    end
    return a.spell < b.spell
  end)
  return rows
end

-- True when the fish has at least one use.
function U.Has(data, id)
  return #U.Raw(data, id) > 0
end

-- Checks a generated table: the shape every use needs and a size that stays small. Returns a list of problems.
function U.Check(data, limits)
  local problems = {}
  if type(data) ~= "table" or data.v ~= 1 then
    return { "wrong version" }
  end
  local set = U.FishSet(data)
  local uses = 0
  for id, list in pairs(data.uses or {}) do
    if not set[id] then
      problems[#problems + 1] = "use of an item that is not in the fish list: " .. tostring(id)
    end
    for _, use in ipairs(list) do
      uses = uses + 1
      if type(use.s) ~= "number" or type(use.l) ~= "number" then
        problems[#problems + 1] = "use without spell or line: " .. tostring(id)
      end
    end
  end
  if limits and limits.uses and uses > limits.uses then
    problems[#problems + 1] = "too many uses: " .. uses
  end
  return problems
end
