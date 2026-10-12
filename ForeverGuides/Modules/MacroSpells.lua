-- Spell catalog access for the macro editor: name index, rank chains, search,
-- icon index. Reads through ns.DataApi; no WoW API except optional C_Spell for
-- client names. Entries are shared with ns.Data and never modified.
local _, ns = ...
local C = ns.MacroCore

local S = {}
ns.MacroSpells = S

S.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local GROUPS = { "GENERAL", "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local CASTABLE = { spell = true, talent = true, racial = true, other = true }

local idx

function S.normalize(s)
  s = (s or ""):lower()
  s = s:gsub("\195\164", "a"):gsub("\195\132", "a"):gsub("\195\182", "o"):gsub("\195\150", "o")
  s = s:gsub("\195\188", "u"):gsub("\195\156", "u"):gsub("\195\159", "ss")
  s = s:gsub("[\195][\160-\175]", "e"):gsub("[%p]", ""):gsub("%s+", " ")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
local normalize = S.normalize

function S.Reset()
  idx = nil
  if ns.DataApi then
    ns.DataApi.Reset()
  end
end

local function build()
  idx = { list = {}, byName = {}, classes = {}, byIcon = {}, count = 0 }
  local seen = {}
  for _, group in ipairs(GROUPS) do
    for _, s in ipairs(ns.DataApi.SpellsForClass(group)) do
      local set = idx.classes[s.id]
      if not set then
        set = {}
        idx.classes[s.id] = set
      end
      if group ~= "GENERAL" then
        set[group] = true
      end
      for _, c in ipairs(s.c or {}) do
        set[c] = true
      end
      if not seen[s.id] then
        seen[s.id] = true
        local entry = { spell = s, de = normalize(s.n.de), en = normalize(s.n.en) }
        idx.list[#idx.list + 1] = entry
        idx.count = idx.count + 1
        if s.fid then
          local names = idx.byIcon[s.fid]
          if not names then
            names = {}
            idx.byIcon[s.fid] = names
          end
          names[#names + 1] = entry
        end
      end
    end
  end
  table.sort(idx.list, function(a, b)
    if a.en ~= b.en then
      return a.en < b.en
    end
    local ra, rb = a.spell.rk or 0, b.spell.rk or 0
    if ra ~= rb then
      return ra < rb
    end
    return a.spell.id < b.spell.id
  end)
  for _, entry in ipairs(idx.list) do
    local s = entry.spell
    local base = s.b or s.id
    for _, key in ipairs({ entry.de, entry.en }) do
      local list = idx.byName[key]
      if not list then
        list = {}
        idx.byName[key] = list
      end
      if not list[base] then
        list[base] = true
        list[#list + 1] = base
      end
    end
  end
end

local function index()
  if not idx then
    build()
  end
  return idx
end

function S.count()
  return index().count
end

function S.isSpell(id)
  return ns.DataApi.Spell(id) ~= nil
end

-- Spell facts for the macro validator: { name, removed, classes = set of class tokens (empty = every
-- class) } or nil for an unknown id. Removed and deprecated spells do not work in the web either.
function S.info(id)
  local s = ns.DataApi.Spell(id)
  if not s then
    return nil
  end
  return {
    name = S.displayName(s),
    removed = s.st == "removed" or s.st == "deprecated",
    classes = index().classes[id] or {},
  }
end

function S.inClass(id, class)
  local set = index().classes[id]
  return set ~= nil and (set[class] == true or next(set) == nil)
end

-- Client language, independent of the addon's display language.
local function clientField(field)
  if not field then
    return nil
  end
  local deDE = type(GetLocale) == "function" and GetLocale() == "deDE"
  return deDE and (field.de or field.en) or (field.en or field.de)
end

function S.clientName(id)
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and name and name ~= "" then
      return name
    end
  end
  local s = ns.DataApi.Spell(id)
  return s and clientField(s.n)
end

function S.clientRankText(id)
  local s = ns.DataApi.Spell(id)
  if not s or not s.rk then
    return nil
  end
  if s.rt then
    return clientField(s.rt)
  end
  local deDE = type(GetLocale) == "function" and GetLocale() == "deDE"
  return string.format(deDE and "Rang %d" or "Rank %d", s.rk)
end

function S.displayName(spell)
  return ns.T(spell.n)
end

-- Label for lists and tooltips in the addon language: "Name (ID)" / "Name, Rang N (ID)".
function S.label(id)
  local s = ns.DataApi.Spell(id)
  if not s then
    return string.format("? (%d)", id)
  end
  return C.formatSpell(S.displayName(s), s.rk and ns.DataApi.RankText(s) or nil, id)
end

-- Picks one chain base for a name; nil when unknown.
local function pickChain(bases, class)
  local best, bestScore
  for _, base in ipairs(bases) do
    local chain = ns.DataApi.RankChain(base)
    local score = 0
    if class and S.inClass(base, class) then
      score = score + 4
    end
    if #chain > 1 then
      score = score + 2
    end
    local head = chain[1]
    if head and head.st == nil then
      score = score + 1
    end
    if not best or score > bestScore or (score == bestScore and base < best) then
      best, bestScore = base, score
    end
  end
  return best, #bases > 1
end

-- Name (+ optional rank) -> { id, base, rankAmbiguous, nameAmbiguous } or nil, reason.
function S.lookup(name, rank, class)
  local bases = index().byName[normalize(name)]
  if not bases then
    return nil, "name"
  end
  local base, nameAmbiguous = pickChain(bases, class)
  local chain = ns.DataApi.RankChain(base)
  if rank then
    for _, s in ipairs(chain) do
      if s.rk == rank then
        return { id = s.id, nameAmbiguous = nameAmbiguous }
      end
    end
    return nil, "rank"
  end
  if #chain > 1 then
    return { id = chain[#chain].id, base = true, rankAmbiguous = true, nameAmbiguous = nameAmbiguous }
  end
  return { id = chain[1].id, nameAmbiguous = nameAmbiguous }
end

-- Is the spell known to the player? nil when the API cannot tell.
function S.isKnown(id)
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
    if ok then
      return known and true or false
    end
  end
  if IsPlayerSpell then
    local ok, known = pcall(IsPlayerSpell, id)
    if ok then
      return known and true or false
    end
  end
  if IsSpellKnown then
    local ok, known = pcall(IsSpellKnown, id)
    if ok then
      return known and true or false
    end
  end
  return nil
end

-- Highest rank of the chain of `id` that the player knows (else the highest).
function S.highestKnown(id)
  return C.highestKnown(ns.DataApi.RankChain(id), function(rankId)
    return S.isKnown(rankId) == true
  end)
end

-- Rows for the picker. opts: class ("ALL"|token|"GENERAL"), passive (bool), limit.
-- Row = { spell, id, name, rank, chainSize }.
function S.search(query, opts)
  opts = opts or {}
  local list = index().list
  local q = normalize(query or "")
  local num = (query or ""):match("^%s*(%d+)%s*$")
  local limit = opts.limit or 300
  local out, exact = {}, {}
  for _, entry in ipairs(list) do
    local s = entry.spell
    local ok = opts.passive or CASTABLE[s.k or "spell"]
    if ok and opts.class and opts.class ~= "ALL" then
      ok = opts.class == "GENERAL" and next(index().classes[s.id] or {}) == nil or S.inClass(s.id, opts.class)
    end
    if ok and not opts.removed and (s.st == "removed" or s.st == "deprecated") then
      ok = false
    end
    if ok and q ~= "" then
      if num then
        ok = tostring(s.id):find("^" .. num) ~= nil
      else
        ok = entry.de:find(q, 1, true) ~= nil or entry.en:find(q, 1, true) ~= nil
      end
    end
    if ok then
      local row = { spell = s, id = s.id, name = S.displayName(s), rank = s.rk and ns.DataApi.RankText(s) or nil }
      if num and tostring(s.id) == num or (not num and q ~= "" and (entry.de == q or entry.en == q)) then
        exact[#exact + 1] = row
      else
        out[#out + 1] = row
      end
      if #exact + #out >= limit * 4 then
        break
      end
    end
  end
  for i = #exact, 1, -1 do
    table.insert(out, 1, exact[i])
  end
  for i = #out, limit + 1, -1 do
    out[i] = nil
  end
  return out
end

-- Rank chain with the picked id marked, for the rank column.
function S.chainSize(id)
  return #ns.DataApi.RankChain(id)
end

-- Icons --------------------------------------------------------------------------

-- FileIDs whose spell name matches the query (name or number prefix).
function S.iconsByName(query, limit)
  local q = normalize(query or "")
  local out, seen = {}, {}
  if q == "" then
    return out
  end
  for _, entry in ipairs(index().list) do
    local fid = entry.spell.fid
    if fid and not seen[fid] and (entry.de:find(q, 1, true) or entry.en:find(q, 1, true)) then
      seen[fid] = true
      out[#out + 1] = fid
      if #out >= (limit or 200) then
        break
      end
    end
  end
  return out
end

-- All catalog FileIDs, ascending (fallback when the client lists no macro icons).
function S.catalogIcons()
  local out, seen = {}, {}
  for _, entry in ipairs(index().list) do
    local fid = entry.spell.fid
    if fid and not seen[fid] then
      seen[fid] = true
      out[#out + 1] = fid
    end
  end
  table.sort(out)
  return out
end

function S.iconNames(fid)
  local names = {}
  for _, entry in ipairs(index().byIcon[fid] or {}) do
    names[#names + 1] = S.displayName(entry.spell)
  end
  return names
end

-- Presets -------------------------------------------------------------------------

-- opts: class ("ALL"|token), category, query. Sorted by title.
function S.presets(opts)
  opts = opts or {}
  local out = {}
  local list = (opts.class and opts.class ~= "ALL") and ns.DataApi.MacroPresetsFor(opts.class)
    or ns.DataApi.MacroPresets()
  local q = normalize(opts.query or "")
  for _, p in ipairs(list) do
    local ok = true
    if opts.category and opts.category ~= "ALL" then
      ok = false
      for _, c in ipairs(p.cat or {}) do
        if c == opts.category then
          ok = true
        end
      end
    end
    if ok and q ~= "" then
      ok = normalize(ns.T(p.t)):find(q, 1, true) ~= nil or normalize(ns.T(p.d)):find(q, 1, true) ~= nil
    end
    if ok then
      out[#out + 1] = p
    end
  end
  table.sort(out, function(a, b)
    return normalize(ns.T(a.t)) < normalize(ns.T(b.t))
  end)
  return out
end

function S.categories()
  local set, out = {}, {}
  for _, p in ipairs(ns.DataApi.MacroPresets()) do
    for _, c in ipairs(p.cat or {}) do
      if not set[c] then
        set[c] = true
        out[#out + 1] = c
      end
    end
  end
  table.sort(out)
  return out
end
