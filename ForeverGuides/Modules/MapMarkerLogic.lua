-- Instance entrance markers for maps: build from Data.Instances, the player's own entrances per
-- instance, filters, tooltip lines, text export and import. Pure logic, no WoW API.
-- Own data lives in ns.db.mapMarkers = { v = 1, items = { [slug] = { { map, x, y, nt? } } }, hidden = { [slug] = true } }.
-- An own entrance list replaces the shipped entrances of that instance as a whole.
local _, ns = ...

ns.AddLocale("enUS", {
  ["mm.type.dungeon"] = "Dungeon",
  ["mm.type.raid"] = "Raid",
  ["mm.players"] = "Players: %s",
  ["mm.hint.map"] = "Click: dungeon map",
  ["mm.hint.page"] = "Click: instance page",
  ["mm.set.world"] = "Instance markers in the world map",
  ["mm.set.addon"] = "Instance markers on the add-on map",
  ["mm.set.dungeons"] = "Show dungeon markers",
  ["mm.set.raids"] = "Show raid markers",
})
ns.AddLocale("deDE", {
  ["mm.type.dungeon"] = "Dungeon",
  ["mm.type.raid"] = "Raid",
  ["mm.players"] = "Spieler: %s",
  ["mm.hint.map"] = "Klicken: Dungeonkarte",
  ["mm.hint.page"] = "Klicken: Instanzseite",
  ["mm.set.world"] = "Instanz-Marker in der Weltkarte",
  ["mm.set.addon"] = "Instanz-Marker auf der Addon-Karte",
  ["mm.set.dungeons"] = "Dungeon-Marker anzeigen",
  ["mm.set.raids"] = "Raid-Marker anzeigen",
})

local M = {}
ns.MapMarkerLogic = M

M.SCHEMA = 1
M.MAX_PER_INSTANCE = 20
M.MAX_NOTE = 80

local FACTIONS = { A = true, H = true }

-- Validation --------------------------------------------------------------------------------

local function validMap(v)
  return type(v) == "number" and v >= 1 and v < 2 ^ 31 and v == math.floor(v)
end

local function validCoord(v)
  return type(v) == "number" and v >= 0 and v <= 1
end

-- Extra name of a side entrance: { de, en } from the data, or a plain text of the player.
local function cleanNote(nt)
  if type(nt) == "string" then
    return nt ~= "" and #nt <= M.MAX_NOTE and nt or nil
  end
  if type(nt) == "table" then
    local out = {}
    for _, lang in ipairs({ "de", "en" }) do
      local s = nt[lang]
      if type(s) == "string" and s ~= "" and #s <= M.MAX_NOTE then
        out[lang] = s
      end
    end
    return next(out) and out or nil
  end
end

local function entrance(map, x, y, nt)
  if validMap(map) and validCoord(x) and validCoord(y) then
    return { map = map, x = x, y = y, nt = cleanNote(nt) }
  end
end

-- Own entrances of one instance: the valid ones (at most MAX_PER_INSTANCE) and the discarded count.
local function ownEntrances(raw)
  local list, rejected = {}, 0
  for _, e in ipairs(type(raw) == "table" and raw or {}) do
    local c = type(e) == "table" and #list < M.MAX_PER_INSTANCE and entrance(e.map, e.x, e.y, e.nt)
    if c then
      list[#list + 1] = c
    else
      rejected = rejected + 1
    end
  end
  return list, rejected
end

-- Shipped entrances (k == "entrance"); side entrances count, the meeting stones do not.
local function shippedEntrances(inst)
  local list = {}
  for _, e in ipairs(inst.ent or {}) do
    local c = e.k == "entrance" and entrance(e.m, e.x, e.y, e.nt)
    if c then
      list[#list + 1] = c
    end
  end
  return list
end

-- Build -------------------------------------------------------------------------------------

local function hasDungeonMap(nameEn)
  local view = ns.DungeonMapView
  return view ~= nil and view.KeyFor(nameEn) ~= nil
end

-- One marker per entrance: { slug, name, kind, lv, ml, rl, players, faction, map, x, y, note, source,
-- hasDungeonMap, entranceIndex }. overrides is ns.db.mapMarkers (or nil); opts.hasMap(nameEn)
-- tells whether the instance has a dungeon map (default: ns.DungeonMapView.KeyFor). Second result:
-- count of own entries that were invalid and left out.
function M.Build(instances, overrides, opts)
  local hasMap = opts and opts.hasMap or hasDungeonMap
  local own = type(overrides) == "table" and type(overrides.items) == "table" and overrides.items or {}
  local hidden = type(overrides) == "table" and type(overrides.hidden) == "table" and overrides.hidden or {}
  local markers, rejected = {}, 0
  for _, inst in ipairs(instances or {}) do
    local slug = ns.RefLogic.InstanceSlug(inst)
    -- An announced instance has no entrance to walk to yet, so it gets no pin.
    if slug ~= "" and hidden[slug] ~= true and not ns.InstanceLevelLogic.Unconfirmed(inst) then
      local list, source = shippedEntrances(inst), "data"
      local custom, bad = ownEntrances(own[slug])
      rejected = rejected + bad
      if #custom > 0 then
        list, source = custom, "user"
      end
      local withMap = #list > 0 and hasMap(inst.n.en) == true
      for i, e in ipairs(list) do
        markers[#markers + 1] = {
          slug = slug,
          name = inst.n,
          kind = inst.t == "raid" and "raid" or "dungeon",
          lv = inst.lv,
          ml = inst.ml,
          rl = inst.rl,
          players = inst.gs,
          faction = inst.f or "B",
          map = e.map,
          x = e.x,
          y = e.y,
          note = e.nt,
          source = source,
          hasDungeonMap = withMap,
          entranceIndex = i,
        }
      end
    end
  end
  return markers, rejected
end

function M.ForMap(markers, uiMapID)
  local out = {}
  for _, m in ipairs(markers) do
    if m.map == uiMapID then
      out[#out + 1] = m
    end
  end
  return out
end

-- opts.dungeons / opts.raids: false hides that type (nil shows it). opts.faction "A" or "H" hides
-- the other faction; markers for both factions ("B") always stay.
function M.Filter(markers, opts)
  opts = opts or {}
  local faction = FACTIONS[opts.faction] and opts.faction
  local out = {}
  for _, m in ipairs(markers) do
    local typeShown = m.kind == "raid" and opts.raids ~= false or m.kind ~= "raid" and opts.dungeons ~= false
    if typeShown and (not faction or m.faction == "B" or m.faction == faction) then
      out[#out + 1] = m
    end
  end
  return out
end

-- title, { text lines }. L is the locale table (ns.L), T picks the language of { de, en } fields
-- (ns.T); without T the English name is used.
function M.TooltipLines(marker, L, T)
  local pick = T or ns.T
  local title = pick and pick(marker.name) or marker.name.en
  local lines = {}
  if marker.note then
    lines[#lines + 1] = pick and pick(marker.note) or marker.note.en or marker.note
  end
  lines[#lines + 1] = L["mm.type." .. marker.kind]
  -- Every instance shows its level range, a missing side is named instead of left out.
  local level = ns.InstanceLevelLogic.Of(marker, L)
  lines[#lines + 1] = level.text
  if level.entryText then
    lines[#lines + 1] = level.entryText
  end
  if level.gapText then
    lines[#lines + 1] = level.gapText
  end
  if marker.players ~= nil and marker.players ~= "" then
    lines[#lines + 1] = L["mm.players"]:format(marker.players)
  end
  lines[#lines + 1] = L[marker.hasDungeonMap and "mm.hint.map" or "mm.hint.page"]
  return title, lines
end

-- Own data ----------------------------------------------------------------------------------

local function itemsOf(db)
  if type(db.items) ~= "table" then
    db.items = {}
  end
  return db.items
end

-- Replaces the entrances of one instance with `entrances` ({ { map, x, y, nt? } }). Returns the
-- accepted and the discarded count. Nothing valid in a non-empty list leaves the old data alone.
function M.SetOverride(db, slug, entrances)
  local list, rejected = ownEntrances(entrances)
  if #list > 0 then
    itemsOf(db)[slug] = list
  elseif rejected == 0 then
    itemsOf(db)[slug] = nil
  end
  return #list, rejected
end

function M.ClearOverride(db, slug)
  itemsOf(db)[slug] = nil
end

function M.SetHidden(db, slug, hidden)
  if type(db.hidden) ~= "table" then
    db.hidden = {}
  end
  db.hidden[slug] = hidden == true or nil
end

-- One line per own entrance: slug|map|x|y, slugs sorted so the same data gives the same text.
function M.Export(db)
  local items = itemsOf(db)
  local slugs = {}
  for slug in pairs(items) do
    slugs[#slugs + 1] = slug
  end
  table.sort(slugs)
  local lines = {}
  for _, slug in ipairs(slugs) do
    for _, e in ipairs((ownEntrances(items[slug]))) do
      lines[#lines + 1] = ("%s|%d|%.4f|%.4f"):format(slug, e.map, e.x, e.y)
    end
  end
  return table.concat(lines, "\n")
end

local function knownSlugs()
  local known = {}
  for _, inst in ipairs(ns.Data and ns.Data.Instances or {}) do
    known[ns.RefLogic.InstanceSlug(inst)] = true
  end
  return known
end

-- Takes the text of Export. Only the slugs named in the text change, and only when at least one of
-- their lines is valid. Returns the taken and the discarded line count (blank lines do not count).
function M.Import(db, text)
  if type(text) ~= "string" then
    return 0, 0
  end
  local known = knownSlugs()
  local groups, order, taken, discarded = {}, {}, 0, 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local slug, map, x, y = line:match("^([%w%-]+)|(%d+)|([%d%.]+)|([%d%.]+)$")
      if slug and known[slug] then
        if not groups[slug] then
          groups[slug] = {}
          order[#order + 1] = slug
        end
        table.insert(groups[slug], { map = tonumber(map), x = tonumber(x), y = tonumber(y) })
      else
        discarded = discarded + 1
      end
    end
  end
  for _, slug in ipairs(order) do
    local accepted, rejected = M.SetOverride(db, slug, groups[slug])
    taken = taken + accepted
    discarded = discarded + rejected
  end
  return taken, discarded
end
