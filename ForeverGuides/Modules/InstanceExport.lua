-- Instance data export for the website (/fg instexport, help page, Info tab of the instance page).
-- Collects what the addon knows and the website does not: floors and tile crops of the dungeon maps,
-- learned areas, own boss pins, recorded loot, boss NPC and encounter ids, access conditions and the
-- entrances, plus the shipped boss and quest lists as a reference. Format: docs/INSTANZ-EXPORT-FORMAT.md.
-- One JSON document per instance (schema fg-instance-v1), all of them in one package
-- (fg-instance-pack-v1). Output: plain JSON in the copy dialog, a print string (ns.Strings, type
-- instanceData) on request, and the whole package in ns.db.instExport.text (SavedVariables), because
-- the loot of 20000 items does not fit a window or a pasted string. Pure reading, no game protection.
local _, ns = ...
local L = ns.L

local IE = {}
ns.InstanceExport = IE

IE.SCHEMA = "fg-instance-v1"
IE.PACK_SCHEMA = "fg-instance-pack-v1"
IE.KIND = "instanceData"
-- Plain JSON stays below Strings.MAX_JSON, so the website can inflate it with the same limit.
IE.MAX_JSON = 1800000
IE.MAX_DIALOG = 300000 -- characters the copy dialog takes, a long text makes its edit box crawl
IE.MAX_PRINT = 600000 -- bytes of JSON a print string is built from, compression runs in the client

local MARGIN = 4096 -- room for the "truncated" markers added after sizing
local MAX_DEPTH = 6

ns.AddLocale("enUS", {
  ["instexport.open"] = "Export instance data",
  ["instexport.title"] = "Instance data export",
  ["instexport.hint"] = "Floors, learned areas, own boss pins, recorded loot, boss ids and access for the website data.\nAlso saved in SavedVariables (ForeverGuides.lua, field instExport) after /reload or logout.",
  ["instexport.printTitle"] = "Instance data print string",
  ["instexport.printHint"] = "The same data as a compressed print string for the website import.",
  ["instexport.print"] = "Print string",
  ["instexport.plain"] = "Plain JSON",
  ["instexport.large"] = "The export has %d KB, too much for this window.\nIt is saved in SavedVariables (ForeverGuides.lua, field instExport) after /reload or logout.\nA single instance fits: /fg instexport <name>.",
  ["instexport.printLarge"] = "Too large for a print string. Use the saved file or a single instance.",
  ["instexport.printFail"] = "The print string could not be built.",
  ["instexport.combat"] = "Not possible in combat.",
  ["instexport.failed"] = "The export failed, see the error list.",
  ["instexport.unknown"] = "No instance found for: %s",
})
ns.AddLocale("deDE", {
  ["instexport.open"] = "Instanzdaten exportieren",
  ["instexport.title"] = "Instanzdaten-Export",
  ["instexport.hint"] = "Ebenen, gelernte Bereiche, eigene Boss-Pins, erfasste Beute, Boss-IDs und Zugang für die Website-Daten.\nNach /reload oder Abmelden auch in den SavedVariables (ForeverGuides.lua, Feld instExport).",
  ["instexport.printTitle"] = "Instanzdaten als Druckstring",
  ["instexport.printHint"] = "Dieselben Daten als komprimierter Druckstring für den Website-Import.",
  ["instexport.print"] = "Druckstring",
  ["instexport.plain"] = "Klartext JSON",
  ["instexport.large"] = "Der Export hat %d KB, zu viel für dieses Fenster.\nEr liegt nach /reload oder Abmelden in den SavedVariables (ForeverGuides.lua, Feld instExport).\nEine einzelne Instanz passt: /fg instexport <Name>.",
  ["instexport.printLarge"] = "Zu groß für einen Druckstring. Nimm die gespeicherte Datei oder eine einzelne Instanz.",
  ["instexport.printFail"] = "Der Druckstring ließ sich nicht bauen.",
  ["instexport.combat"] = "Im Kampf nicht möglich.",
  ["instexport.failed"] = "Der Export ist fehlgeschlagen, siehe Fehlerliste.",
  ["instexport.unknown"] = "Keine Instanz gefunden für: %s",
})

local function data()
  return ns.Data or {}
end

local function positive(v)
  return type(v) == "number" and v >= 1 and v == math.floor(v) and v or nil
end

-- A copy that Json.encode takes: no functions, no NaN, no cycles (depth limit).
local function plain(v, depth)
  local kind = type(v)
  if kind == "string" or kind == "boolean" then
    return v
  elseif kind == "number" then
    return v == v and v ~= math.huge and v ~= -math.huge and v or nil
  elseif kind ~= "table" or (depth or 0) > MAX_DEPTH then
    return nil
  end
  local out = {}
  for k, item in pairs(v) do
    if type(k) == "string" or type(k) == "number" then
      out[k] = plain(item, (depth or 0) + 1)
    end
  end
  return out
end

local function nameTable(n)
  if type(n) ~= "table" then
    return nil
  end
  local out = { en = type(n.en) == "string" and n.en or nil, de = type(n.de) == "string" and n.de or nil }
  return next(out) and out or nil
end

local function buildId()
  local ok, version, build = pcall(GetBuildInfo)
  if ok and type(version) == "string" and build ~= nil then
    return version .. "." .. tostring(build)
  end
  return data().Manifest and data().Manifest.build or ""
end

-- Instance slots --------------------------------------------------------------------------------

-- One slot per instance, found by name first (English or German), then by instance id: the Dire Maul
-- wings share one instance id. The sources (shipped list, maps, loot, learned areas, own pins) name
-- the same instance in different ways. The first slot that claims an id or name keeps it.
local function collect()
  local slots, byId, byName = {}, {}, {}
  local function claim(s, id, name)
    if id and not byId[id] then
      byId[id] = s
      s.id = s.id or id
    end
    if type(name) == "string" and name ~= "" and not byName[name:lower()] then
      byName[name:lower()] = s
    end
  end
  local function add(id, name)
    local s = { name = type(name) == "string" and name ~= "" and name or ("id:" .. tostring(id)), loot = {} }
    slots[#slots + 1] = s
    claim(s, positive(id), name)
    return s
  end
  local function get(id, name)
    id = positive(id)
    local s = (type(name) == "string" and byName[name:lower()]) or (id and byId[id]) or nil
    if not s then
      return add(id, name)
    end
    claim(s, id, name)
    return s
  end

  for _, inst in ipairs(data().Instances or {}) do
    if type(inst) == "table" and type(inst.n) == "table" and type(inst.n.en) == "string" then
      local s = add(inst.id, inst.n.en)
      s.inst = inst
      s.names = nameTable(inst.n)
      claim(s, nil, inst.n.de)
    end
  end
  local assets = data().DungeonAssets
  for name in pairs(type(assets) == "table" and assets.maps or {}) do
    get(nil, name)
  end
  local LC = ns.LootCapture
  for _, b in ipairs(LC and LC.Bosses() or {}) do
    local s = get(b.e.instanceId, b.e.instance)
    s.loot[#s.loot + 1] = b
  end
  local areas = type(ns.db) == "table" and type(ns.db.dungeonAreas) == "table" and ns.db.dungeonAreas.items
  for id in pairs(type(areas) == "table" and areas or {}) do
    get(id, nil)
  end
  -- Own pins are validated on the first read; OwnPins("") triggers it without picking one.
  local P = ns.PinLogic
  if P then
    P.OwnPins("")
  end
  local pins = type(ns.db) == "table" and type(ns.db.bossPins) == "table" and ns.db.bossPins.items
  for _, p in ipairs(type(pins) == "table" and pins or {}) do
    get(p.id, p.inst)
  end

  table.sort(slots, function(a, b)
    local na, nb = a.name:lower(), b.name:lower()
    if na ~= nb then
      return na < nb
    end
    return (a.id or 0) < (b.id or 0)
  end)
  return slots
end

-- Does the slot match a filter { id, name } (from an instance table, an id or typed text)?
local function matches(s, only)
  local id = positive(only.id)
  if id and s.id == id then
    return true
  end
  local want = type(only.name) == "string" and only.name:lower() or nil
  if not want then
    return false
  end
  local R = ns.RefLogic
  local slug = R and R.slug(want) or want
  for _, n in ipairs({ s.name, s.names and s.names.de or "" }) do
    if n:lower() == want or (R and slug ~= "" and R.slug(n) == slug) then
      return true
    end
  end
  return false
end

-- A typed name that starts exactly one slug ("blackf" for Blackfathom Deeps), else nil.
local function prefixMatch(slots, only)
  local R = ns.RefLogic
  local want = type(only.name) == "string" and R and R.slug(only.name) or ""
  local found
  for _, s in ipairs(want ~= "" and slots or {}) do
    if R.slug(s.name):sub(1, #want) == want then
      if found then
        return nil
      end
      found = s
    end
  end
  return found
end

-- Typed text: a number is an instance id, anything else a name or slug.
local function filterOf(query)
  if type(query) == "table" then
    return { id = query.id, name = query.n and query.n.en or query.name }
  end
  local id = tonumber(query)
  if id then
    return { id = id }
  end
  return { name = ns.U.trim(tostring(query)) }
end

-- Blocks ----------------------------------------------------------------------------------------

local function floorsOf(map)
  local out = {}
  local grid = map.grid
  for i, floor in ipairs(map.floors or {}) do
    -- Crop floors carry their own raster, the plain ones the 4 by 3 of the old maps.
    local cols = floor.cols or (i == 1 and grid and grid.cols) or nil
    local rows = floor.rows or (i == 1 and grid and grid.rows) or nil
    out[#out + 1] = { n = i, fid = plain(floor.fid), cols = cols, rows = rows }
  end
  return out
end

local function assetBlocks(doc, name)
  local assets = data().DungeonAssets
  if type(assets) ~= "table" then
    return
  end
  local map = type(assets.maps) == "table" and assets.maps[name]
  if type(map) == "table" then
    doc.floors = floorsOf(map)
    doc.folder = type(map.folder) == "string" and map.folder or nil
    doc.grid = plain(map.grid)
    doc.tiles = plain(map.tiles)
    doc.soon = map.soon == true or nil
    doc.loadingImage = positive(map.lo)
    if type(map.alt) == "table" then
      local alt = {}
      for _, a in ipairs(map.alt) do
        alt[#alt + 1] = { folder = a.folder, floors = floorsOf(a) }
      end
      doc.alt = alt
    end
  end
  local loading = type(assets.loading) == "table" and assets.loading[name]
  doc.loading = type(loading) == "table" and plain(loading) or nil
  local portraits = type(assets.portraits) == "table" and assets.portraits[name]
  doc.portraits = type(portraits) == "table" and next(portraits) and plain(portraits) or nil
end

local function areaRows(id)
  local out = {}
  local items = type(ns.db) == "table" and type(ns.db.dungeonAreas) == "table" and ns.db.dungeonAreas.items
  local areas = id and type(items) == "table" and items[id]
  if type(areas) ~= "table" then
    return out
  end
  for _, key in ipairs(ns.U.sortedKeys(areas)) do
    local e = areas[key]
    if type(e) == "table" then
      out[#out + 1] = { key = key, name = e.name or key, floor = e.floor, x = e.x, y = e.y }
    end
  end
  return out
end

local PIN_FIELDS =
  { "inst", "id", "kind", "boss", "eid", "npc", "idx", "icon", "label", "note", "floor", "x", "y", "toFloor" }

local function pinRows(name)
  local out = {}
  for _, p in ipairs(ns.PinLogic and ns.PinLogic.OwnPins(name) or {}) do
    local row = {}
    for _, f in ipairs(PIN_FIELDS) do
      row[f] = p[f]
    end
    out[#out + 1] = row
  end
  return out
end

local KIND = { n = "npc", o = "object" }

-- Boss sources of the slot and their loot rows (sorted by source, then item id).
local function lootBlocks(s)
  local npcs, rows = {}, {}
  local LC = ns.LootCapture
  local sources = {}
  for _, b in ipairs(s.loot) do
    sources[#sources + 1] = b
  end
  table.sort(sources, function(a, b)
    if a.kind ~= b.kind then
      return a.kind == "n"
    end
    return a.id < b.id
  end)
  for _, b in ipairs(sources) do
    local e = b.e
    npcs[#npcs + 1] = { kind = KIND[b.kind], id = b.id, name = e.name, eid = e.eid, kills = e.kills }
    for _, id in ipairs(LC.SortedItems(e)) do
      local it = e.items[id]
      rows[#rows + 1] = {
        src = KIND[b.kind],
        id = b.id,
        item = id,
        name = LC.ItemName(id, true, it),
        drops = it.n,
        qty = it.qty,
        q = it.q,
      }
    end
  end
  return npcs, rows
end

local function accessRows(s)
  local list = type(data().Access) == "table" and ns.RefLogic and data().Access[ns.RefLogic.slug(s.name)]
  return plain(type(list) == "table" and list or {}) or {}
end

local function entranceRows(inst)
  local out = {}
  for _, e in ipairs(inst and inst.ent or {}) do
    out[#out + 1] = { kind = e.k, map = e.m, x = e.x, y = e.y, note = nameTable(e.nt) }
  end
  return out
end

-- The shipped lists, for comparing: boss names and the quests with their reward items.
local function reference(inst)
  if not inst then
    return nil
  end
  local ref = { bosses = {}, quests = {} }
  for i, b in ipairs(inst.bo or {}) do
    ref.bosses[i] = { idx = i, name = nameTable(b.n), optional = b.opt == true or nil }
  end
  for _, q in ipairs(inst.q or {}) do
    local rewards = {}
    for _, r in ipairs(q.rw or {}) do
      rewards[#rewards + 1] = { id = r.id, name = r.n, choice = r.ch == true or nil }
    end
    ref.quests[#ref.quests + 1] = { id = q.id, name = nameTable(q.n), level = q.l, rewards = rewards }
  end
  return ref
end

local function document(s, ctx)
  local doc = {
    schema = IE.SCHEMA,
    build = ctx.build,
    exportedAt = ctx.at,
    instanceId = s.id,
    instance = s.name,
    names = s.names,
    source = "addon",
    floors = {},
  }
  assetBlocks(doc, s.name)
  doc.areas = areaRows(s.id)
  doc.pins = pinRows(s.name)
  local npcs, rows = lootBlocks(s)
  doc.bossNpcs = npcs
  doc.loot = {}
  doc.access = accessRows(s)
  doc.entrances = entranceRows(s.inst)
  doc.reference = reference(s.inst)
  return doc, rows
end

-- Drops the least telling loot rows (few drops, low quality, last instance) until the sizes fit.
-- Returns the number of dropped rows; the kept rows go back into the documents in their order.
local function fit(docs, rowsOf, fixed, limit)
  local sizes, order, total = {}, {}, fixed
  for i, rows in ipairs(rowsOf) do
    sizes[i] = {}
    for j, row in ipairs(rows) do
      sizes[i][j] = #ns.Json.encode(row) + 1
      total = total + sizes[i][j]
      order[#order + 1] = { i = i, j = j, row = row }
    end
  end
  local dropped = {}
  local count = 0
  if total > limit then
    table.sort(order, function(a, b)
      if a.row.drops ~= b.row.drops then
        return a.row.drops < b.row.drops
      end
      if a.row.q ~= b.row.q then
        return a.row.q < b.row.q
      end
      if a.i ~= b.i then
        return a.i > b.i
      end
      return a.j > b.j
    end)
    for _, o in ipairs(order) do
      if total <= limit then
        break
      end
      total = total - sizes[o.i][o.j]
      dropped[o.i] = dropped[o.i] or {}
      dropped[o.i][o.j] = true
      count = count + 1
    end
  end
  for i, rows in ipairs(rowsOf) do
    local kept, cut = {}, 0
    for j, row in ipairs(rows) do
      if dropped[i] and dropped[i][j] then
        cut = cut + 1
      else
        kept[#kept + 1] = row
      end
    end
    docs[i].loot = kept
    docs[i].truncated = cut > 0 and { loot = cut } or nil
  end
  return count
end

-- opts: instance = what to export (instance table, id or typed text), nil = every instance;
-- exportedAt, build and limit replace the defaults (tests). Returns
-- { json, data, count, truncated = dropped loot rows } or nil and "unknown".
function IE.Build(opts)
  opts = opts or {}
  local ctx = { build = opts.build or buildId(), at = opts.exportedAt or ns.U.now() }
  local picked = collect()
  if opts.instance ~= nil then
    local only = filterOf(opts.instance)
    local found
    for _, s in ipairs(picked) do
      if matches(s, only) then
        found = s
        break
      end
    end
    found = found or prefixMatch(picked, only)
    if not found then
      return nil, "unknown"
    end
    picked = { found }
  end
  local docs, rowsOf = {}, {}
  for i, s in ipairs(picked) do
    docs[i], rowsOf[i] = document(s, ctx)
  end
  local value = docs[1]
  if opts.instance == nil then
    value = { schema = IE.PACK_SCHEMA, build = ctx.build, exportedAt = ctx.at, source = "addon", instances = docs }
  end
  local dropped = fit(docs, rowsOf, #ns.Json.encode(value), (opts.limit or IE.MAX_JSON) - MARGIN)
  if dropped > 0 and opts.instance == nil then
    value.truncated = { loot = dropped }
  end
  return { json = ns.Json.encode(value), data = value, count = #docs, truncated = dropped }
end

-- Output ----------------------------------------------------------------------------------------

local function inCombat()
  return InCombatLockdown ~= nil and InCombatLockdown() == true
end

local showPlain

local function showPrint(result)
  if #result.json > IE.MAX_PRINT then
    ns.Notify(L["instexport.printLarge"], "warning")
    return
  end
  local ok, text = ns.Safe("instexport-print", ns.Strings.encode, IE.KIND, result.data)
  if not (ok and text) then
    ns.Notify(L["instexport.printFail"], "warning")
    return
  end
  ns.Dialogs.Copy("instexport.printTitle", text, "instexport.printHint", {
    {
      key = "instexport.plain",
      onClick = function()
        showPlain(result)
      end,
    },
  })
end

function showPlain(result)
  local text = result.json
  if #text > IE.MAX_DIALOG then
    text = string.format(L["instexport.large"], math.ceil(#text / 1024))
  end
  ns.Dialogs.Copy("instexport.title", text, "instexport.hint", {
    {
      key = "instexport.print",
      onClick = function()
        showPrint(result)
      end,
    },
  })
end

-- opts.instance limits the window (and the print string) to one instance. The SavedVariables
-- always get the whole package, so the file on disk is the complete state. Returns the text of
-- the window, nil without result.
function IE.Run(opts)
  opts = opts or {}
  if inCombat() then
    ns.Notify(L["instexport.combat"], "warning")
    return nil
  end
  local ok, all = ns.Safe("instexport", IE.Build)
  if not ok or not all then
    ns.Notify(L["instexport.failed"], "warning")
    return nil
  end
  if ns.db then
    ns.db.instExport = { at = ns.U.now(), text = all.json }
  end
  local result = all
  if opts.instance ~= nil then
    local built, one = ns.Safe("instexport-one", IE.Build, { instance = opts.instance })
    if not built or not one then
      ns.Notify(
        string.format(
          L["instexport.unknown"],
          tostring(type(opts.instance) == "table" and opts.instance.n and opts.instance.n.en or opts.instance)
        ),
        "warning"
      )
      return nil
    end
    result = one
  end
  if ns.Dialogs and ns.Dialogs.Copy then
    showPlain(result)
  end
  return result.json
end
