-- Dungeon map pins (bosses, entrances, links, free markers): validation, merge of the shipped pins
-- (Data.BossPins) with the player's own, JSON export and import. Format: docs/BOSSPINS-FORMAT.md.
-- Pure logic, no WoW API. Own pins live in ns.db.bossPins = { v = 1, items = { pin } }.
local _, ns = ...

local P = {}
ns.PinLogic = P

P.SCHEMA = 1
P.MAX_LABEL = 40
P.MAX_NOTE = 500
P.MAX_OWN = 2000

local KIND_ORDER = { boss = 1, entrance = 2, link = 3, marker = 4 }
-- Fixed field order of the exported JSON, so the same pins always give the same text.
local FIELDS =
  { "inst", "id", "kind", "boss", "eid", "npc", "idx", "icon", "label", "note", "floor", "x", "y", "toFloor" }

local function data()
  return ns.Data or {}
end

local function posInt(v)
  return type(v) == "number" and v >= 1 and v < 2 ^ 31 and v == math.floor(v)
end

local function nonEmpty(v)
  return type(v) == "string" and v ~= ""
end

-- Length in characters, not bytes: names and labels are UTF-8.
local function charCount(s)
  local _, continuation = s:gsub("[\128-\191]", "")
  return #s - continuation
end

local function round3(v)
  return math.floor(v * 1000 + 0.5) / 1000
end

-- Instances and bosses ----------------------------------------------------------------------

-- Ordered bosses of an instance from Data.Instances, matched by instance id (number) or English name.
-- Returns { { idx, name = { en, de }, eid, npc, opt } } and the instance entry.
function P.BossList(instKey)
  local out, found = {}, nil
  for _, inst in ipairs(data().Instances or {}) do
    if
      (type(instKey) == "number" and inst.id == instKey)
      or (type(instKey) == "string" and inst.n and inst.n.en == instKey)
    then
      found = inst
      break
    end
  end
  for i, b in ipairs(found and found.bo or {}) do
    local n = b.n or {}
    out[i] = { idx = i, name = { en = n.en or n.de, de = n.de or n.en }, eid = b.eid, npc = b.npc, opt = b.opt }
  end
  return out, found
end

-- Fills id, idx, eid and npc from the boss list where the pin lacks them.
local function enrich(c)
  local list, inst = P.BossList(c.id or c.inst)
  c.id = c.id or (inst and posInt(inst.id) and inst.id) or nil
  if not c.boss then
    return
  end
  for _, b in ipairs(list) do
    if (c.eid and b.eid == c.eid) or (not c.eid and (b.name.en == c.boss or b.name.de == c.boss)) then
      c.idx = c.idx or b.idx
      c.eid = c.eid or (posInt(b.eid) and b.eid) or nil
      c.npc = c.npc or (posInt(b.npc) and b.npc) or nil
      return
    end
  end
end

-- Validation --------------------------------------------------------------------------------

local function coord(v, name)
  if type(v) ~= "number" or v ~= v or v < 0 or v > 1 then
    return name .. " must be between 0 and 1"
  end
end

-- Returns true, nil, cleanCopy or false, reason. The copy has rounded coordinates, only the
-- fields of its kind and ids filled in from the instance data.
function P.Validate(pin)
  if type(pin) ~= "table" then
    return false, "pin is not a table"
  end
  local kind = pin.kind
  if not KIND_ORDER[kind] then
    return false, "unknown kind"
  end
  if not nonEmpty(pin.inst) then
    return false, "missing inst"
  end
  local map = data().DungeonAssets and data().DungeonAssets.maps and data().DungeonAssets.maps[pin.inst]
  if not (map and map.floors) then
    return false, "instance has no map"
  end
  if kind == "boss" and not nonEmpty(pin.boss) then
    return false, "missing boss"
  end
  if pin.boss ~= nil and not nonEmpty(pin.boss) then
    return false, "invalid boss"
  end
  if kind == "marker" then
    if not nonEmpty(pin.icon) then
      return false, "missing icon"
    end
    if pin.label ~= nil and (type(pin.label) ~= "string" or charCount(pin.label) > P.MAX_LABEL) then
      return false, "label too long"
    end
    if pin.note ~= nil and (type(pin.note) ~= "string" or charCount(pin.note) > P.MAX_NOTE) then
      return false, "note too long"
    end
  end
  if not posInt(pin.floor) then
    return false, "floor must be a positive integer"
  end
  if pin.floor > #map.floors then
    return false, "floor out of range"
  end
  local bad = coord(pin.x, "x") or coord(pin.y, "y")
  if bad then
    return false, bad
  end
  if kind == "link" then
    if not posInt(pin.toFloor) or pin.toFloor > #map.floors then
      return false, "toFloor out of range"
    end
    if pin.toFloor == pin.floor then
      return false, "toFloor equals floor"
    end
  end
  local c = { inst = pin.inst, kind = kind, floor = pin.floor, x = round3(pin.x), y = round3(pin.y) }
  c.id = posInt(pin.id) and pin.id or nil
  if kind == "boss" or kind == "marker" then
    c.boss = pin.boss
    c.eid = posInt(pin.eid) and pin.eid or nil
    c.npc = posInt(pin.npc) and pin.npc or nil
    c.idx = posInt(pin.idx) and pin.idx or nil
  end
  if kind == "marker" then
    c.icon, c.label, c.note = pin.icon, pin.label, pin.note
  elseif kind == "link" then
    c.toFloor = pin.toFloor
  end
  enrich(c)
  return true, nil, c
end

-- Identity and order ------------------------------------------------------------------------

-- One boss pin per boss (by eid, else name); other kinds are the same pin at the same spot.
local function same(a, b)
  if a.inst ~= b.inst or a.kind ~= b.kind then
    return false
  end
  if a.kind == "boss" then
    if a.eid and b.eid then
      return a.eid == b.eid
    end
    return a.boss == b.boss
  end
  return a.floor == b.floor and a.x == b.x and a.y == b.y and a.icon == b.icon and a.toFloor == b.toFloor
end

local function before(a, b)
  if a.inst ~= b.inst then
    return a.inst < b.inst
  end
  if a.kind ~= b.kind then
    return KIND_ORDER[a.kind] < KIND_ORDER[b.kind]
  end
  if (a.idx or 0) ~= (b.idx or 0) then
    return (a.idx or 0) < (b.idx or 0)
  end
  for _, f in ipairs({ "boss", "icon" }) do
    if (a[f] or "") ~= (b[f] or "") then
      return (a[f] or "") < (b[f] or "")
    end
  end
  for _, f in ipairs({ "floor", "x", "y", "toFloor" }) do
    if (a[f] or 0) ~= (b[f] or 0) then
      return (a[f] or 0) < (b[f] or 0)
    end
  end
  return false
end

local function copy(pin, own)
  local c = {}
  for _, f in ipairs(FIELDS) do
    c[f] = pin[f]
  end
  c.own = own or nil
  return c
end

-- Storage -----------------------------------------------------------------------------------

local checked
local function own()
  if type(ns.db) ~= "table" then
    return nil
  end
  local d = ns.db.bossPins
  if type(d) ~= "table" then
    d = { v = 1, items = {} }
    ns.db.bossPins = d
  end
  if checked ~= d then
    local clean = {}
    for _, raw in ipairs(type(d.items) == "table" and d.items or {}) do
      local ok, _, c = P.Validate(raw)
      if ok and #clean < P.MAX_OWN then
        clean[#clean + 1] = c
      end
    end
    d.v, d.items = 1, clean
    checked = d
  end
  return d.items
end

local shippedCache = setmetatable({}, { __mode = "k" })
local function shipped(inst)
  local src = data().BossPins and data().BossPins[inst]
  if type(src) ~= "table" then
    return {}
  end
  if not shippedCache[src] then
    local clean = {}
    for _, raw in ipairs(src) do
      if type(raw) == "table" then
        local ok, _, c = P.Validate({
          inst = inst,
          id = raw.id,
          kind = raw.kind,
          boss = raw.boss,
          eid = raw.eid,
          npc = raw.npc,
          idx = raw.idx,
          icon = raw.icon,
          label = raw.label,
          note = raw.note,
          floor = raw.floor,
          x = raw.x,
          y = raw.y,
          toFloor = raw.toFloor,
        })
        if ok then
          clean[#clean + 1] = c
        end
      end
    end
    shippedCache[src] = clean
  end
  return shippedCache[src]
end

local function find(list, pin)
  for i, p in ipairs(list) do
    if same(p, pin) then
      return i
    end
  end
end

-- Replaces the pin with the same identity or appends it. Returns true when it replaced one.
local function put(list, pin)
  local i = find(list, pin)
  list[i or #list + 1] = pin
  return i ~= nil
end

-- Own pins of an instance, sorted. Remove addresses them as (kind, index) in this order.
function P.OwnPins(inst)
  local out = {}
  for _, p in ipairs(own() or {}) do
    if p.inst == inst then
      out[#out + 1] = copy(p, true)
    end
  end
  table.sort(out, before)
  return out
end

-- Shipped pins with the player's own on top. own = true marks the player's pins.
function P.Pins(inst)
  local list = {}
  for _, p in ipairs(shipped(inst)) do
    list[#list + 1] = copy(p)
  end
  for _, p in ipairs(own() or {}) do
    if p.inst == inst then
      put(list, copy(p, true))
    end
  end
  table.sort(list, before)
  return list
end

function P.Set(pin)
  local ok, err, clean = P.Validate(pin)
  if not ok then
    return false, err
  end
  local items = own()
  if not items then
    return false, "no database"
  end
  if #items >= P.MAX_OWN and not find(items, clean) then
    return false, "too many pins"
  end
  put(items, clean)
  return true
end

-- Remove(inst, bossName) drops the boss pin of that boss, Remove(inst, kind, index) the index-th own pin of a kind.
function P.Remove(inst, what, index)
  local items = own()
  if not items then
    return false
  end
  local target
  if index then
    local n = 0
    for _, p in ipairs(P.OwnPins(inst)) do
      if p.kind == what then
        n = n + 1
        if n == index then
          target = p
          break
        end
      end
    end
  else
    target = { inst = inst, kind = "boss", boss = what }
  end
  for i, p in ipairs(items) do
    if target and same(p, target) then
      table.remove(items, i)
      return true
    end
  end
  return false
end

function P.Clear(inst)
  local items, n = own() or {}, 0
  for i = #items, 1, -1 do
    if items[i].inst == inst then
      table.remove(items, i)
      n = n + 1
    end
  end
  return n
end

-- Export ------------------------------------------------------------------------------------

local function encodeField(f, v)
  if f == "x" or f == "y" then
    return string.format("%.3f", v)
  end
  return ns.Json.encode(v)
end

local function encodePin(p)
  local parts = {}
  for _, f in ipairs(FIELDS) do
    if p[f] ~= nil then
      parts[#parts + 1] = ns.Json.encode(f) .. ": " .. encodeField(f, p[f])
    end
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function instNames(all, only)
  if only then
    return { only }
  end
  local seen, names = {}, {}
  local function add(name)
    if not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  for _, p in ipairs(own() or {}) do
    add(p.inst)
  end
  if all then
    for name in pairs(data().BossPins or {}) do
      add(name)
    end
  end
  table.sort(names)
  return names
end

-- opts.all = shipped plus own (own on top), else own only. opts.inst limits the export to one instance.
-- opts.build and opts.created override the defaults.
function P.Export(opts)
  opts = opts or {}
  local pins = {}
  for _, inst in ipairs(instNames(opts.all, opts.inst)) do
    for _, p in ipairs(opts.all and P.Pins(inst) or P.OwnPins(inst)) do
      pins[#pins + 1] = "    " .. encodePin(p)
    end
  end
  local head = { '  "schema": ' .. P.SCHEMA }
  local build = opts.build or (data().Manifest and data().Manifest.build)
  if nonEmpty(build) then
    head[#head + 1] = '  "build": ' .. ns.Json.encode(build)
  end
  local created = opts.created
  if not created then
    local ok, d = pcall(date, "%Y-%m-%d")
    created = ok and d or nil
  end
  if nonEmpty(created) then
    head[#head + 1] = '  "created": ' .. ns.Json.encode(created)
  end
  local body = #pins > 0 and ("[\n" .. table.concat(pins, ",\n") .. "\n  ]") or "[]"
  head[#head + 1] = '  "pins": ' .. body
  return "{\n" .. table.concat(head, ",\n") .. "\n}"
end

-- Import -------------------------------------------------------------------------------------

-- mode "preview" counts only, "apply" stores the valid pins as own pins. Returns
-- { added, replaced, rejected = { { index, reason } } }, or nil plus a reason for an unusable file.
function P.Import(text, mode)
  if type(text) ~= "string" then
    return nil, "no text"
  end
  local ok, doc = pcall(ns.Json.decode, (text:gsub("^\239\187\191", "")))
  if not ok or type(doc) ~= "table" then
    return nil, "invalid JSON"
  end
  if doc.schema ~= P.SCHEMA then
    return nil, "unsupported schema"
  end
  if type(doc.pins) ~= "table" or (#doc.pins == 0 and next(doc.pins) ~= nil) then
    return nil, "missing pins"
  end
  local items = own()
  if mode == "apply" and not items then
    return nil, "no database"
  end
  local work = {}
  for i, p in ipairs(items or {}) do
    work[i] = p
  end
  local result = { added = 0, replaced = 0, rejected = {} }
  for index, raw in ipairs(doc.pins) do
    local valid, reason, clean = P.Validate(raw)
    if not valid then
      result.rejected[#result.rejected + 1] = { index = index, reason = reason }
    elseif #work >= P.MAX_OWN and not find(work, clean) then
      result.rejected[#result.rejected + 1] = { index = index, reason = "too many pins" }
    elseif put(work, clean) then
      result.replaced = result.replaced + 1
    else
      result.added = result.added + 1
    end
  end
  if mode == "apply" then
    ns.db.bossPins.items = work
  end
  return result
end
