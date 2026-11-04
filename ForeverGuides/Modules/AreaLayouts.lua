-- Windows and their layouts (ns.AreaLayouts), without WoW API. A HUD window and its layout are one thing: every
-- window shows exactly one layout, every layout belongs to exactly one window, and both carry the same name.
-- The layout is stored apart from the window, settings.areas.layouts[layoutId], and the window points at it with
-- settings.areas.items[id].layoutId. Creating, duplicating, renaming and deleting a window does the same to its
-- layout.
--
-- AreaLayouts.New({ get = function() -> settings.areas, put = function(path, value) }) binds the functions to a
-- store: `put` gets paths relative to settings.areas ("layouts.layout1", "items.area1.name") and writes them (the
-- add-on goes through Store.set, so every window follows). Every function that changes something returns the
-- new id or true, or nil and the reason: "name", "dup", "limit" (windows), "layoutLimit", "missing".
--
-- AreaLayouts.Migrate brings stored data of the earlier model (shared layouts, layouts without a window) into
-- this one.
local _, ns = ...
local U, L, CL, AL = ns.U, ns.L, ns.CanvasLogic, ns.AreaLogic

local AY = {
  MAX_LAYOUTS = 60,
  MAX_NAME = CL.MAX_LAYOUT_NAME,
  -- Marks data that went through the migration to one layout per window.
  MODEL = 2,
}
ns.AreaLayouts = AY

ns.AddLocale(
  "enUS",
  ns.AreaTerms.Apply("enUS", {
    ["areas.lib.copyName"] = "%s Copy",
  })
)
ns.AddLocale(
  "deDE",
  ns.AreaTerms.Apply("deDE", {
    ["areas.lib.copyName"] = "%s Kopie",
  })
)

local function count(layouts)
  local n = 0
  for _, layout in pairs(layouts) do
    if type(layout) == "table" then
      n = n + 1
    end
  end
  return n
end

-- A name that is safe to show: plain one-line text of at most MAX_NAME characters, "" when nothing is left.
function AY.CleanName(name)
  return CL.CleanText(name, AY.MAX_NAME)
end

-- The first free id "layout1", "layout2", ...; nil once MAX_LAYOUTS layouts exist (`force` ignores the limit).
function AY.NewId(layouts, force)
  layouts = type(layouts) == "table" and layouts or {}
  if not force and count(layouts) >= AY.MAX_LAYOUTS then
    return nil
  end
  local n = 1
  while layouts["layout" .. n] ~= nil do
    n = n + 1
  end
  return "layout" .. n
end

local function takenNames(layouts, exceptId)
  local taken = {}
  for id, layout in pairs(layouts) do
    if id ~= exceptId and type(layout) == "table" then
      taken[AY.CleanName(layout.name):lower()] = true
    end
  end
  return taken
end

-- `name` cleaned, and numbered ("Buffs 2", "Buffs 3", ...) while `taken` (a set of lower case names) has it.
local function numbered(taken, name)
  local base = AY.CleanName(name)
  if not taken[base:lower()] then
    return base
  end
  local n = 2
  while true do
    local suffix = " " .. n
    local candidate = AY.CleanName(AY.CleanName(base:sub(1, AY.MAX_NAME - #suffix)) .. suffix)
    if not taken[candidate:lower()] then
      return candidate
    end
    n = n + 1
  end
end

-- `name` cleaned, and numbered while another layout already has it (ignoring case).
function AY.UniqueName(layouts, name)
  return numbered(takenNames(type(layouts) == "table" and layouts or {}), name)
end

-- Brings the stored windows and layouts of `node` (settings.areas) into the model of one layout per window,
-- editing it in place. Repeated runs change nothing and nothing is ever dropped:
--  * the layout an old window carried in the field `layout` moves into the library, a reference that points
--    nowhere gets a fresh template;
--  * a layout several windows show stays with the first of them (by id), each further window gets a copy;
--  * window and layout share one name, unique among all windows (a clash is numbered);
--  * a layout without a window becomes a window of its own that no character shows on its own
--    (startShown = false). This happens once, `node.model` marks it, so a layout that is created a moment
--    before its window is not taken for a leftover.
-- Returns the number of changed windows and the ids of the windows made from leftover layouts.
function AY.Migrate(node)
  local hidden = {}
  if type(node) ~= "table" or type(node.items) ~= "table" then
    return 0, hidden
  end
  if type(node.layouts) ~= "table" then
    node.layouts = {}
  end
  local items, layouts = node.items, node.layouts
  local touched, claimed = 0, {}
  local ids = {}
  for _, id in ipairs(U.sortedKeys(items)) do
    if AL.CleanId(id) and type(items[id]) == "table" then
      ids[#ids + 1] = id
    end
  end
  local changed = {}
  for _, id in ipairs(ids) do
    local item = items[id]
    local lid = item.layoutId
    local present = type(lid) == "string" and type(layouts[lid]) == "table"
    if present and not claimed[lid] then
      claimed[lid] = id
    else
      local newId = AY.NewId(layouts, true)
      local source = present and CL.Copy(layouts[lid]) or item.layout
      layouts[newId] = CL.Pack(AL.RepairLayout(source, newId, AL.CleanName(item.name, id)))
      item.layoutId = newId
      claimed[newId] = id
      changed[id] = true
    end
    if item.layout ~= nil then
      item.layout = nil
      changed[id] = true
    end
  end
  -- One name for window and layout, first come first served in the order of the ids.
  local taken = {}
  for _, id in ipairs(ids) do
    local item = items[id]
    local layout = layouts[item.layoutId]
    local want = AY.CleanName(item.name)
    if want == "" then
      want = AY.CleanName(layout.name)
    end
    local name = numbered(taken, want ~= "" and want or id)
    taken[name:lower()] = true
    if item.name ~= name or layout.name ~= name then
      item.name, layout.name = name, name
      changed[id] = true
    end
  end
  for _ in pairs(changed) do
    touched = touched + 1
  end
  if node.model ~= AY.MODEL then
    for _, lid in ipairs(U.sortedKeys(layouts)) do
      local layout = layouts[lid]
      if AL.CleanId(lid) and type(layout) == "table" and not claimed[lid] then
        local name = numbered(taken, AY.CleanName(layout.name) ~= "" and layout.name or lid)
        taken[name:lower()] = true
        local id = AL.NewId(items, true)
        layout.name = name
        items[id] = { name = name, layoutId = lid, startShown = false }
        claimed[lid] = id
        hidden[#hidden + 1] = id
        touched = touched + 1
      end
    end
    node.model = AY.MODEL
  end
  return touched, hidden
end

local function same(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not same(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

function AY.New(o)
  local lib = {}

  local function node()
    local n = o.get()
    return type(n) == "table" and n or {}
  end
  local function layouts()
    local n = node()
    return type(n.layouts) == "table" and n.layouts or {}
  end
  local function items()
    local n = node()
    return type(n.items) == "table" and n.items or {}
  end
  local function exists(id)
    return type(id) == "string" and type(layouts()[id]) == "table"
  end
  local function areaExists(id)
    return type(id) == "string" and type(items()[id]) == "table"
  end

  lib.Has = exists

  function lib.Count()
    return count(layouts())
  end

  -- The name a layout shows: its own, else its id.
  function lib.Name(id)
    local layout = layouts()[id]
    return AY.CleanName(type(layout) == "table" and layout.name) ~= "" and AY.CleanName(layout.name) or tostring(id)
  end

  -- The id of the layout a window shows; nil when the window has none or its reference points nowhere.
  function lib.LayoutId(areaId)
    local item = items()[areaId]
    local id = type(item) == "table" and item.layoutId
    if exists(id) then
      return id
    end
  end

  -- The id of the window that shows layout `layoutId`.
  function lib.WindowOf(layoutId)
    if layoutId == nil then
      return nil
    end
    for _, entry in ipairs(AL.List(items())) do
      if items()[entry.id].layoutId == layoutId then
        return entry.id
      end
    end
  end

  -- { id, name, layoutId } of every window, sorted by name (ignoring case), then by id.
  function lib.Windows()
    local out = {}
    for i, entry in ipairs(AL.List(items())) do
      out[i] = { id = entry.id, name = entry.name, layoutId = lib.LayoutId(entry.id) }
    end
    return out
  end

  -- The layout a window draws: repaired, of kind "area", carrying the id and the name of its library entry. A
  -- window without a usable layout shows the template (AreaLayouts.Migrate stores one).
  function lib.Layout(areaId)
    local id = lib.LayoutId(areaId)
    if not id then
      local item = items()[areaId]
      return AL.NewLayout(areaId, AL.CleanName(type(item) == "table" and item.name, areaId))
    end
    return AL.RepairLayout(layouts()[id], id, lib.Name(id))
  end

  -- The layout `id` as the editor and the drawing take it: repaired, of kind "area", with id and name. nil
  -- when the library has no such layout.
  function lib.Get(id)
    if exists(id) then
      return AL.RepairLayout(layouts()[id], id, lib.Name(id))
    end
  end

  -- The names in use by windows and layouts (lower case), without window `exceptAreaId` and its layout.
  local function taken(exceptAreaId)
    local names = takenNames(layouts(), lib.LayoutId(exceptAreaId))
    for id, item in pairs(items()) do
      if id ~= exceptAreaId and type(item) == "table" then
        names[AL.CleanName(item.name, id):lower()] = true
      end
    end
    return names
  end

  -- A new window with a new layout (an empty one unless `layout` is given) under one name made unique. The
  -- layout is written first, `before(areaId)` runs when the window is about to be written (the caller marks it
  -- as shown on this character there), `extra` (optional) holds more fields of the window. Returns the window id
  -- and the layout id.
  -- "name" for an empty name, "limit" at MAX_AREAS windows, "layoutLimit" at MAX_LAYOUTS layouts.
  function lib.CreateWindow(name, layout, before, extra)
    local clean = AY.CleanName(name)
    if clean == "" then
      return nil, "name"
    end
    local areaId = AL.NewId(items())
    if not areaId then
      return nil, "limit"
    end
    local layoutId = AY.NewId(layouts())
    if not layoutId then
      return nil, "layoutLimit"
    end
    local unique = numbered(taken(), clean)
    local stored =
      AL.RepairLayout(type(layout) == "table" and layout or AL.EmptyLayout(layoutId, unique), layoutId, unique)
    o.put("layouts." .. layoutId, CL.Pack(stored))
    if before then
      before(areaId)
    end
    local item = AL.NewItem(unique, layoutId)
    for key, value in pairs(extra or {}) do
      item[key] = value
    end
    o.put("items." .. areaId, item)
    return areaId, layoutId
  end

  -- A copy of window `areaId` with a copy of its layout (`layout` replaces it, the editor passes its working
  -- copy) and its rules (load, startShown), named `name` (default "<name> Copy").
  function lib.DuplicateWindow(areaId, name, before, layout)
    local layoutId = lib.LayoutId(areaId)
    if not layoutId then
      return nil, "missing"
    end
    local item = items()[areaId]
    local base = AL.CleanName(item.name, areaId)
    local extra = {}
    if type(item.load) == "table" then
      extra.load = U.copy(item.load)
    end
    if type(item.startShown) == "boolean" then
      extra.startShown = item.startShown
    end
    return lib.CreateWindow(
      name or string.format(L["areas.lib.copyName"], base),
      CL.Copy(type(layout) == "table" and layout or layouts()[layoutId]),
      before,
      extra
    )
  end

  -- Renames a window and its layout: "name" for an empty name, "dup" when another window has it (ignoring case).
  function lib.RenameWindow(areaId, name)
    local layoutId = lib.LayoutId(areaId)
    if not (areaExists(areaId) and layoutId) then
      return nil, "missing"
    end
    local clean = AY.CleanName(name)
    if clean == "" then
      return nil, "name"
    end
    if taken(areaId)[clean:lower()] then
      return nil, "dup"
    end
    if lib.Name(layoutId) ~= clean then
      o.put("layouts." .. layoutId .. ".name", clean)
    end
    if items()[areaId].name ~= clean then
      o.put("items." .. areaId .. ".name", clean)
    end
    return true
  end

  -- Stores an edited layout under `id`; the stored name stays (renaming goes through RenameWindow).
  function lib.Save(id, layout)
    if not exists(id) or type(layout) ~= "table" then
      return nil, "missing"
    end
    local clean = CL.Pack(AL.RepairLayout(layout, id, lib.Name(id)))
    if not same(clean, layouts()[id]) then
      o.put("layouts." .. id, clean)
    end
    return true
  end

  -- Replaces what window `targetId` shows by a copy of what window `sourceId` shows. Name and ids stay.
  function lib.CopyContent(sourceId, targetId)
    local source, target = lib.LayoutId(sourceId), lib.LayoutId(targetId)
    if not (source and target) or sourceId == targetId then
      return nil, "missing"
    end
    return lib.Save(target, CL.Copy(layouts()[source]))
  end

  -- Deletes a window and its layout. The layout goes first: the write that removes the window runs the
  -- migration, which must not find the layout without a window.
  function lib.DeleteWindow(areaId)
    if not areaExists(areaId) then
      return nil, "missing"
    end
    local layoutId = lib.LayoutId(areaId)
    if layoutId then
      o.put("layouts." .. layoutId, nil)
    end
    o.put("items." .. areaId, nil)
    return true
  end

  return lib
end
