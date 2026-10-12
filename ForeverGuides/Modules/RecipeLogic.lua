-- Recipe database, pure side (no frames, no game calls): skill bands, filters, sorting, grouping
-- into display rows, known recipe lists and reagent stock. The data shape is in docs/REZEPT-FORMAT.md,
-- the data access is Modules/RecipeData.lua, the game side Modules/RecipeKnown.lua, the page
-- Modules/RecipePage.lua.
local _, ns = ...

local R = {}
ns.RecipeLogic = R

R.BANDS = { "orange", "yellow", "green", "gray" }
-- Display order of the bands in a flat list; "locked" (skill below the learn level) and "none" (no levels
-- in the data) come last.
R.SECTIONS = { "orange", "yellow", "green", "gray", "locked", "none" }
-- Colors of the skill bands, 0..1.
R.COLORS = {
  orange = { 1, 0.5, 0.25 },
  yellow = { 1, 0.82, 0 },
  green = { 0.25, 0.75, 0.25 },
  gray = { 0.6, 0.6, 0.6 },
  locked = { 0.8, 0.3, 0.3 },
  none = { 0.45, 0.45, 0.45 },
}
R.DEFAULT_MAX_SKILL = 300
R.MAX_SKILL = 1000
-- Known recipes kept per character and characters kept (the roster holds 60 at most).
R.MAX_KNOWN = 1500
R.MAX_CHARS = 60
R.MAX_ID = 1e8
R.OTHER = 0

local floor, huge = math.floor, math.huge

-- Recipes ---------------------------------------------------------------------------------------

local function whole(v)
  return type(v) == "number" and v == v and v >= 0 and v <= R.MAX_SKILL and floor(v) or 0
end

-- True for an entry the page can show: spell id, a name and four skill values.
function R.Valid(r)
  return type(r) == "table"
    and type(r.s) == "number"
    and type(r.n) == "table"
    and (type(r.n[1]) == "string" or type(r.n[2]) == "string")
    and type(r.sk) == "table"
end

-- The valid entries of a data list, in their order.
function R.Clean(list)
  local out = {}
  for _, r in ipairs(type(list) == "table" and list or {}) do
    if R.Valid(r) then
      out[#out + 1] = r
    end
  end
  return out
end

-- lang "de" or "en"; falls back to the other language, then to the spell id.
function R.Name(r, lang)
  local first, second = 1, 2
  if lang ~= "de" then
    first, second = 2, 1
  end
  local n = type(r.n) == "table" and r.n or {}
  local name = type(n[first]) == "string" and n[first] ~= "" and n[first] or n[second]
  if type(name) ~= "string" or name == "" then
    return "#" .. tostring(r.s)
  end
  return name
end

-- "t" trainer, "i" recipe item, "u" everything else (unknown or not told apart yet).
function R.SourceKind(r)
  return (r.src == "t" or r.src == "i") and r.src or "u"
end

-- Bands -------------------------------------------------------------------------------------------

local function levels(sk)
  return whole(sk[1]), whole(sk[2]), whole(sk[3]), whole(sk[4])
end

-- The band of a recipe at a skill: "orange", "yellow", "green", "gray", "locked" (below the learn
-- level) or "none" (the data names no level).
function R.Band(sk, skill)
  if type(sk) ~= "table" then
    return "none"
  end
  local la, y, gr, gy = levels(sk)
  if la + y + gr + gy == 0 then
    return "none"
  end
  skill = type(skill) == "number" and skill or 0
  if la > 0 and skill < la then
    return "locked"
  elseif gy > 0 and skill >= gy then
    return "gray"
  elseif gr > 0 and skill >= gr then
    return "green"
  elseif y > 0 and skill >= y then
    return "yellow"
  end
  return "orange"
end

-- The skill a recipe is sorted by: its learn level, else the start of yellow; recipes without any
-- level sort to the end.
function R.Level(r)
  local la, y, gr, gy = levels(r.sk)
  for _, v in ipairs({ la, y, gr, gy }) do
    if v > 0 then
      return v
    end
  end
  return huge
end

-- True when the recipe can be learned at this skill (an unknown learn level counts as learnable).
function R.Learnable(r, skill)
  local la = whole(r.sk[1])
  return la == 0 or (type(skill) == "number" and skill >= la)
end

-- Highest skill the data knows, the range of the slider.
function R.MaxSkill(list)
  local max = 0
  for _, r in ipairs(type(list) == "table" and list or {}) do
    if R.Valid(r) then
      local la, y, gr, gy = levels(r.sk)
      max = math.max(max, la, y, gr, gy)
    end
  end
  return max > 0 and max or R.DEFAULT_MAX_SKILL
end

-- The colored strip of one recipe over the skill range 1..max: { band, from, to } segments, the
-- skills below the learn level as "locked". Unknown (0) values leave their band out.
function R.Segments(sk, max)
  local out = {}
  if type(sk) ~= "table" or type(max) ~= "number" or max < 1 then
    return out
  end
  local la, y, gr, gy = levels(sk)
  if la + y + gr + gy == 0 then
    return out
  end
  if la > 1 then
    out[#out + 1] = { band = "locked", from = 1, to = math.min(la - 1, max) }
  end
  local starts = {}
  for i, v in ipairs({ la, y, gr, gy }) do
    if v > 0 then
      starts[#starts + 1] = { band = R.BANDS[i], from = math.max(v, 1) }
    end
  end
  for i, s in ipairs(starts) do
    local last = starts[i + 1] and starts[i + 1].from - 1 or max
    last = math.min(last, max)
    if s.from <= last then
      out[#out + 1] = { band = s.band, from = s.from, to = last }
    end
  end
  return out
end

-- Filter and sort -----------------------------------------------------------------------------------

-- Folded words of both names, built once per recipe.
local words = setmetatable({}, { __mode = "k" })

local function wordsOf(r)
  local w = words[r]
  if not w then
    local S = ns.SearchLogic
    w = {}
    for _, name in ipairs({ type(r.n[1]) == "string" and r.n[1] or "", type(r.n[2]) == "string" and r.n[2] or "" }) do
      for _, word in ipairs(S.Tokens(name)) do
        w[#w + 1] = word
      end
    end
    words[r] = w
  end
  return w
end

local function typoLimit(len)
  if len >= 7 then
    return 2
  end
  return len >= 4 and 1 or 0
end

local function tokenMatches(token, w)
  if w:find(token, 1, true) then
    return true
  end
  local limit = typoLimit(#token)
  if limit == 0 then
    return false
  end
  local S = ns.SearchLogic
  -- A typo in a word, or in the beginning of a longer one the user is still typing.
  return S.distance(token, w, limit) ~= nil or (#w > #token and S.distance(token, w:sub(1, #token), limit) ~= nil)
end

-- True when every word of the query is found in a word of either name (part of a word, folded,
-- umlauts and small typos from 4 letters tolerated). tokens: ns.SearchLogic.Tokens(query).
function R.Matches(r, tokens)
  if #tokens == 0 then
    return true
  end
  local list = wordsOf(r)
  for _, token in ipairs(tokens) do
    local hit = false
    for _, w in ipairs(list) do
      if tokenMatches(token, w) then
        hit = true
        break
      end
    end
    if not hit then
      return false
    end
  end
  return true
end

-- o: query (text), changed (only recipes changed against Classic or removed), source ("t", "i" or
-- "u"), learnable (only recipes learnable at o.skill), unknown (only recipes not in o.known, a set of
-- spell ids), removed (also show the recipes removed in Forever, off by default).
function R.Filter(list, o)
  o = o or {}
  local tokens = o.query and o.query ~= "" and ns.SearchLogic.Tokens(o.query) or {}
  local out = {}
  for _, r in ipairs(list) do
    local keep = o.removed or not r.rm
    keep = keep and (not o.changed or r.ch or r.rm)
    keep = keep and (not o.source or R.SourceKind(r) == o.source)
    keep = keep and (not o.learnable or R.Learnable(r, o.skill))
    keep = keep and not (o.unknown and o.known and o.known[r.s])
    if keep and R.Matches(r, tokens) then
      out[#out + 1] = r
    end
  end
  return out
end

-- Sorted copy: skill level ascending, then name, then spell id.
function R.Sort(list, lang)
  local keys = {}
  local out = {}
  for i, r in ipairs(list) do
    out[i] = r
    keys[r] = { R.Level(r), R.Name(r, lang):lower() }
  end
  table.sort(out, function(a, b)
    local ka, kb = keys[a], keys[b]
    if ka[1] ~= kb[1] then
      return ka[1] < kb[1]
    elseif ka[2] ~= kb[2] then
      return ka[2] < kb[2]
    end
    return a.s < b.s
  end)
  return out
end

-- Rows -----------------------------------------------------------------------------------------------

local function groupName(g, lang)
  local name = lang == "de" and g.de or g.en
  return type(name) == "string" and name ~= "" and name or g.en or g.de or "?"
end

-- Display rows of a profession, sorted recipes in. Head rows { kind = "head", id, depth, name, count,
-- open } (band sections have `band` and no name), recipe rows { kind = "recipe", recipe, depth }.
-- Grouped by the game's categories (data.groups, recipe field g, parents p, order o) when the data has
-- them, else flat in sections per band at o.skill. o: lang, skill, collapsed ({ [headId] = true }),
-- forceOpen (ignore collapsed, e.g. while searching), otherName (head of recipes without a category),
-- presorted (the list is already in R.Sort order).
function R.Rows(data, list, o)
  o = o or {}
  local lang = o.lang
  local sorted = o.presorted and list or R.Sort(list, lang)
  local collapsed = o.forceOpen and {} or o.collapsed or {}
  local rows = {}
  local groups = type(data) == "table" and type(data.groups) == "table" and data.groups or {}
  local grouped = next(groups) ~= nil
  if grouped then
    grouped = false
    for _, r in ipairs(sorted) do
      if groups[r.g] then
        grouped = true
        break
      end
    end
  end

  if not grouped then
    local by = {}
    for _, band in ipairs(R.SECTIONS) do
      by[band] = {}
    end
    for _, r in ipairs(sorted) do
      local t = by[R.Band(r.sk, o.skill)]
      t[#t + 1] = r
    end
    for _, band in ipairs(R.SECTIONS) do
      local t = by[band]
      if #t > 0 then
        local open = not collapsed["band:" .. band]
        rows[#rows + 1] = { kind = "head", id = "band:" .. band, band = band, depth = 0, count = #t, open = open }
        for _, r in ipairs(open and t or {}) do
          rows[#rows + 1] = { kind = "recipe", recipe = r, depth = 1 }
        end
      end
    end
    return rows
  end

  local recipesOf, kids, roots = {}, {}, {}
  for _, r in ipairs(sorted) do
    local g = groups[r.g] and r.g or R.OTHER
    recipesOf[g] = recipesOf[g] or {}
    recipesOf[g][#recipesOf[g] + 1] = r
  end
  local function order(a, b)
    local ga, gb = groups[a], groups[b]
    local oa, ob = tonumber(ga.o) or 0, tonumber(gb.o) or 0
    if oa ~= ob then
      return oa < ob
    end
    local na, nb = groupName(ga, lang):lower(), groupName(gb, lang):lower()
    if na ~= nb then
      return na < nb
    end
    return a < b
  end
  for id, g in pairs(groups) do
    if type(id) == "number" and type(g) == "table" then
      if groups[g.p] and g.p ~= id then
        kids[g.p] = kids[g.p] or {}
        kids[g.p][#kids[g.p] + 1] = id
      else
        roots[#roots + 1] = id
      end
    end
  end
  table.sort(roots, order)
  for _, list2 in pairs(kids) do
    table.sort(list2, order)
  end

  -- Recipes in a category and below it; the visiting set keeps a damaged parent loop from running away.
  local totals, visiting = {}, {}
  local function total(id)
    if totals[id] then
      return totals[id]
    end
    if visiting[id] then
      return 0
    end
    visiting[id] = true
    local n = #(recipesOf[id] or {})
    for _, kid in ipairs(kids[id] or {}) do
      n = n + total(kid)
    end
    visiting[id] = nil
    totals[id] = n
    return n
  end

  local emitted = {}
  local function emit(id, depth)
    if emitted[id] or total(id) == 0 then
      return
    end
    emitted[id] = true
    local open = not collapsed[id]
    rows[#rows + 1] =
      { kind = "head", id = id, depth = depth, name = groupName(groups[id], lang), count = totals[id], open = open }
    if not open then
      return
    end
    for _, r in ipairs(recipesOf[id] or {}) do
      rows[#rows + 1] = { kind = "recipe", recipe = r, depth = depth + 1 }
    end
    for _, kid in ipairs(kids[id] or {}) do
      emit(kid, depth + 1)
    end
  end
  for _, id in ipairs(roots) do
    emit(id, 0)
  end
  local other = recipesOf[R.OTHER]
  if other then
    local open = not collapsed[R.OTHER]
    rows[#rows + 1] = { kind = "head", id = R.OTHER, depth = 0, name = o.otherName or "?", count = #other, open = open }
    for _, r in ipairs(open and other or {}) do
      rows[#rows + 1] = { kind = "recipe", recipe = r, depth = 1 }
    end
  end
  return rows
end

-- Known recipes ----------------------------------------------------------------------------------------

-- Sorted list of the valid, distinct spell ids in raw, at most `cap` (the lowest ones stay).
function R.CleanIds(raw, cap)
  local seen, out = {}, {}
  for _, id in ipairs(type(raw) == "table" and raw or {}) do
    if type(id) == "number" and id == id and id >= 1 and id <= R.MAX_ID and id == floor(id) and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  table.sort(out)
  for i = #out, (cap or R.MAX_KNOWN) + 1, -1 do
    out[i] = nil
  end
  return out
end

-- Union of the stored ids and a new reading. A reading without ids changes nothing. Returns the
-- merged list and whether it differs from the stored one.
function R.MergeIds(old, new, cap)
  local base = R.CleanIds(old, cap)
  local add = R.CleanIds(new, cap)
  if #add == 0 then
    return base, false
  end
  local all = {}
  for _, id in ipairs(base) do
    all[#all + 1] = id
  end
  for _, id in ipairs(add) do
    all[#all + 1] = id
  end
  local merged = R.CleanIds(all, cap)
  return merged, #merged ~= #base
end

function R.IdSet(ids)
  local set = {}
  for _, id in ipairs(type(ids) == "table" and ids or {}) do
    set[id] = true
  end
  return set
end

-- The keys (sorted) of the characters whose set holds the spell. sets: { [characterKey] = { [spell] = true } }.
function R.Owners(sets, spell)
  local out = {}
  for key, set in pairs(type(sets) == "table" and sets or {}) do
    if type(set) == "table" and set[spell] then
      out[#out + 1] = key
    end
  end
  table.sort(out)
  return out
end

-- Reagents ----------------------------------------------------------------------------------------------

-- Reagent rows { id, need, have } with the counts of a stock table { [itemId] = n }, and how many
-- times the recipe can be made from the stock (nil without reagents).
function R.Reagents(mats, stock)
  local out, crafts = {}, nil
  stock = type(stock) == "table" and stock or {}
  for _, m in ipairs(type(mats) == "table" and mats or {}) do
    if type(m) == "table" and type(m[1]) == "number" then
      local need = type(m[2]) == "number" and m[2] >= 1 and floor(m[2]) or 1
      local have = type(stock[m[1]]) == "number" and stock[m[1]] or 0
      out[#out + 1] = { id = m[1], need = need, have = have }
      local n = floor(have / need)
      crafts = crafts and math.min(crafts, n) or n
    end
  end
  return out, crafts
end
