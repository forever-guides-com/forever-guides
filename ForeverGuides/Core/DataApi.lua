-- Read access to the generated data package (spells, macro presets,
-- instances, travel graph). Pure table lookups, no WoW API; indexes are
-- built on first use. Entries are shared with ns.Data: do not modify them.
local _, ns = ...

local D = {}
ns.DataApi = D

local spellById, chains

local function buildSpellIndex()
  spellById, chains = {}, {}
  for _, list in pairs((ns.Data and ns.Data.Spells) or {}) do
    for _, s in ipairs(list) do
      spellById[s.id] = s
    end
  end
  for _, s in pairs(spellById) do
    local base = s.b or s.id
    chains[base] = chains[base] or {}
    chains[base][#chains[base] + 1] = s
  end
  for _, chain in pairs(chains) do
    table.sort(chain, function(a, b)
      local ra, rb = a.rk or 0, b.rk or 0
      if ra ~= rb then
        return ra < rb
      end
      return a.id < b.id
    end)
  end
end

-- Call after ns.Data.Spells changed (tests, data reload).
function D.Reset()
  spellById, chains = nil, nil
end

function D.Spell(id)
  if not spellById then
    buildSpellIndex()
  end
  return spellById[id]
end

-- Spells of one class token (WARRIOR..DRUID) or "GENERAL" for class-less ones.
function D.SpellsForClass(class)
  return (ns.Data and ns.Data.Spells and ns.Data.Spells[class]) or {}
end

-- All ranks of the spell's chain, lowest rank first. Empty when unknown.
function D.RankChain(id)
  local s = D.Spell(id)
  if not s then
    return {}
  end
  return chains[s.b or s.id] or { s }
end

-- Rank text in the active language: catalog text if present, else "Rank N"/"Rang N".
function D.RankText(spell)
  if spell.rt then
    return ns.T(spell.rt)
  end
  local rank = spell.rk
  if not rank then
    return nil
  end
  return string.format(ns.T({ de = "Rang %d", en = "Rank %d" }), rank)
end

-- The generator's presets followed by the system templates (ns.Data.MacroSystemPresets); a key that
-- both lists carry counts once.
function D.MacroPresets()
  local out, seen = {}, {}
  for _, list in ipairs({ (ns.Data and ns.Data.MacroPresets) or {}, (ns.Data and ns.Data.MacroSystemPresets) or {} }) do
    for _, p in ipairs(list) do
      if not seen[p.key] then
        seen[p.key] = true
        out[#out + 1] = p
      end
    end
  end
  return out
end

-- Presets for a class token; presets without class list apply to every class.
function D.MacroPresetsFor(class)
  local out = {}
  for _, p in ipairs(D.MacroPresets()) do
    local ok = #p.c == 0
    for _, c in ipairs(p.c) do
      if c == class then
        ok = true
      end
    end
    if ok then
      out[#out + 1] = p
    end
  end
  return out
end

function D.MacroPreset(key)
  for _, p in ipairs(D.MacroPresets()) do
    if p.key == key then
      return p
    end
  end
end

-- Instances of kind "dungeon" or "raid", or all when kind is nil.
function D.Instances(kind)
  local out = {}
  for _, i in ipairs((ns.Data and ns.Data.Instances) or {}) do
    if not kind or i.t == kind then
      out[#out + 1] = i
    end
  end
  return out
end

function D.TravelNode(slug)
  for _, n in ipairs((ns.Data and ns.Data.Travel and ns.Data.Travel.nodes) or {}) do
    if n.s == slug then
      return n
    end
  end
end
