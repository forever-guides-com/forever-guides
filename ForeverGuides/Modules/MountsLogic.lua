-- Mounts, pure side (no frames): the mounts of Data/Mounts.lua with filters, the collected state and the place of
-- a source for the Waypoint button. The page is Modules/MountsPage.lua, the data file is generated
--.
local _, ns = ...

local P = {}
ns.MountsLogic = P

-- Source kinds in the order of the filter.
P.KINDS = { "vendor", "drop", "rep", "pvp", "quest", "class", "custom" }
-- Reputation ranks of the data (the client's standing ids).
P.RANKS = { [5] = "friendly", [6] = "honored", [7] = "revered", [8] = "exalted" }

local function data()
  return ns.Data and ns.Data.Mounts or { mounts = {}, zones = {}, races = {} }
end

local indexed
local function index()
  local d = data()
  if indexed and indexed.source == d then
    return indexed
  end
  local ix = { source = d, byId = {} }
  for _, m in ipairs(d.mounts) do
    ix.byId[m.id] = m
  end
  indexed = ix
  return ix
end

function P.Reset()
  indexed = nil
end

function P.Basis()
  return data().basis
end

function P.Mounts()
  return data().mounts
end

function P.Mount(id)
  return index().byId[id]
end

-- The kinds that at least one mount has, in filter order.
function P.Kinds()
  local seen, out = {}, {}
  for _, m in ipairs(data().mounts) do
    seen[m.k] = true
  end
  for _, k in ipairs(P.KINDS) do
    if seen[k] then
      out[#out + 1] = k
    end
  end
  return out
end

-- Reads of the game. Both are optional: a client without them answers "not owned".
local function callApi(tableName, name, ...)
  local c = rawget(_G, tableName)
  local fn = type(c) == "table" and c[name] or rawget(_G, name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  return ok and value or nil
end

P.Probe = {
  count = function(item)
    local n = callApi("C_Item", "GetItemCount", item, true)
    return type(n) == "number" and n or 0
  end,
  known = function(spell)
    return callApi("C_SpellBook", "IsSpellKnown", spell) == true
  end,
}

local function store()
  local have = ns.charDB and ns.charDB.mountsHave
  return type(have) == "table" and have or {}
end

function P.IsMarked(m)
  return store()[m.id] == true
end

function P.SetMarked(m, on)
  ns.Store.setChar("mountsHave." .. m.id, on and true or nil)
end

-- "marked" (the player ticked it), "known" (spell in the spell book), "bag" (the item in bags or bank) or nil.
function P.Owned(m, probe)
  probe = probe or P.Probe
  if P.IsMarked(m) then
    return "marked"
  end
  if m.spell and probe.known(m.spell) then
    return "known"
  end
  if m.item and probe.count(m.item) > 0 then
    return "bag"
  end
  return nil
end

-- Owned and total over all mounts the faction filter lets through.
function P.Counts(probe, faction)
  local have, total = 0, 0
  for _, m in ipairs(data().mounts) do
    if P.FitsFaction(m, faction) then
      total = total + 1
      if P.Owned(m, probe) then
        have = have + 1
      end
    end
  end
  return have, total
end

-- A mount without a faction is open to both sides.
function P.FitsFaction(m, faction)
  return faction == nil or faction == "all" or m.fac == nil or m.fac == faction
end

local function hit(match, query, n)
  return (n.de and match(n.de, query)) or (n.en and match(n.en, query)) or false
end

-- opts: query, kind ("all" or a kind), faction ("all", "A", "H"), status ("all", "owned", "missing"). probe optional.
function P.Filter(opts, match, probe)
  local out = {}
  for _, m in ipairs(data().mounts) do
    local ok = (opts.kind == nil or opts.kind == "all" or m.k == opts.kind) and P.FitsFaction(m, opts.faction)
    if ok and opts.status and opts.status ~= "all" then
      local owned = P.Owned(m, probe) ~= nil
      ok = (opts.status == "owned") == owned
    end
    if ok and opts.query and opts.query ~= "" then
      ok = hit(match, opts.query, m.n)
      for _, s in ipairs(ok and {} or m.s) do
        ok = ok or (s.n ~= nil and hit(match, opts.query, s.n)) or (s.i ~= nil and hit(match, opts.query, s.i))
      end
    end
    if ok then
      out[#out + 1] = m
    end
  end
  return out
end

function P.Zone(z)
  return data().zones[z]
end

-- The place of a source for the Map and Waypoint buttons, nil for a source without a position.
function P.Place(s)
  local zone = s.z and P.Zone(s.z)
  if not (zone and s.x and s.y) then
    return nil
  end
  return { map = zone.m, x = s.x, y = s.y, label = s.n and ns.T(s.n) or ns.T(zone), zone = ns.T(zone) }
end

-- Names of the races of a mask, in the order of the bits.
function P.RaceNames(mask)
  local out = {}
  for bit = 0, 7 do
    local race = mask and mask % (2 ^ (bit + 1)) >= 2 ^ bit and data().races[2 ^ bit]
    if race then
      out[#out + 1] = ns.T(race)
    end
  end
  return out
end

-- Price as plain coin text ("12g 5s"), "0" for nothing.
function P.PriceText(copper)
  return ns.SellLogic.Money(copper, true)
end

return P
