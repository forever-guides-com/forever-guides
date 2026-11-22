-- Search sources over everything the add-on shows: talents, builds, spells, reputations, item sets, gathering,
-- fishing, rares, flight points, stable masters, boss loot, macros, commands, console variables, help, tours and
-- the sub-tabs of the pages. Core data is read directly; the names of load-on-demand data come from the small
-- generated Data/SearchIndex.lua, so no source loads an add-on of its own (boss loot rides on the quest source's
-- load of the instance data). Vendors are cut with the profession data (SearchProfessions).
local _, ns = ...
local S, L = ns.SearchLogic, ns.L

local ST = {}
ns.SearchTargets = ST

-- Kind, German and English label (the row's right column). Weight below 1 keeps pages and settings above data.
local KINDS = {
  { "talent", "Talent", "Talent" },
  { "build", "Build", "Build" },
  { "spell", "Zauber", "Spell" },
  { "faction", "Ruf", "Reputation" },
  { "gather", "Sammeln", "Gathering" },
  { "itemset", "Set", "Set" },
  { "fishing", "Angeln", "Fishing" },
  { "rare", "Seltener", "Rare" },
  { "flightpoint", "Flugpunkt", "Flight point" },
  { "stable", "Stallmeister", "Stable master" },
  { "loot", "Beute", "Loot" },
  { "macro", "Makro", "Macro" },
  { "command", "Befehl", "Command" },
  { "cvar", "Konsole", "Console" },
  { "help", "Hilfe", "Help" },
  { "tour", "Rundgang", "Tour" },
  { "tab", "Reiter", "Tab" },
  { "vendor", "Händler", "Vendor" },
}
ST.KINDS = KINDS

do
  local en, de = {}, {}
  for _, k in ipairs(KINDS) do
    de["search.kind." .. k[1]], en["search.kind." .. k[1]] = k[2], k[3]
  end
  en["search.sub.herb"], de["search.sub.herb"] = "Herb", "Kraut"
  en["search.sub.ore"], de["search.sub.ore"] = "Ore", "Erz"
  en["search.sub.area"], de["search.sub.area"] = "Fishing spot", "Angelplatz"
  en["search.sub.fish"], de["search.sub.fish"] = "Fish", "Fisch"
  en["search.sub.level"], de["search.sub.level"] = "Level %d", "Stufe %d"
  en["search.sub.trash"], de["search.sub.trash"] = "Trash", "Trash"
  ns.AddLocale("enUS", en)
  ns.AddLocale("deDE", de)
end

-- { de, en } of a locale key, read from both language tables.
local function both(key)
  local loc = ns.Locales or {}
  local de, en = loc.deDE and loc.deDE[key], loc.enUS and loc.enUS[key]
  if de or en then
    return { de = de or en, en = en or de }
  end
  return L[key]
end

-- { de, en } from two strings, empty ones left out.
local function pair(de, en)
  de, en = de ~= "" and de or nil, en ~= "" and en or nil
  return { de = de or en, en = en or de }
end

local function short(text, max)
  text = ns.T(text) or ""
  text = text:gsub("%s*\n%s*", " ")
  if #text > (max or 60) then
    text = text:sub(1, (max or 60) - 3):gsub("[\128-\191]*$", "") .. "..."
  end
  return text
end

local function className(class)
  return ns.RefLogic.className(class)
end

local function data()
  return ns.Data or {}
end

-- Talents and saved builds -------------------------------------------------------------------

S.RegisterSource("talent", function(add)
  local trees = data().TalentTrees
  for _, class in ipairs(ns.RefLogic.CLASSES) do
    for _, tree in ipairs(trees and trees.classes and trees.classes[class] or {}) do
      local sub = className(class) .. ", " .. ns.T(tree.n)
      add(tree.n, className(class), "talents", nil, { icon = tree.i })
      for _, t in ipairs(tree.talents or {}) do
        add(t.n, sub, "talents", nil, { icon = t.i })
      end
    end
  end
end, { weight = 0.9 })

S.RegisterSource("build", function(add)
  local TB = ns.TalentBuilds
  for _, class in ipairs(TB and ns.RefLogic.CLASSES or {}) do
    for _, entry in ipairs(TB.AllEntries(class)) do
      add(entry.name, className(class), "talents")
    end
  end
end, { weight = 0.9 })

-- Spells: one entry per name (ranks collapse). Names of the learn lists stay with the "ability" kind.
S.RegisterSource("spell", function(add)
  local R = ns.RefLogic
  local files = {}
  for _, class in ipairs(R.CLASSES) do
    files[#files + 1] = class
  end
  files[#files + 1] = "GENERAL"
  for _, class in ipairs(files) do
    local known = {}
    if class ~= "GENERAL" then
      for _, a in ipairs(R.LearnList(class)) do
        known[S.fold(ns.T(a.n) or "")] = true
      end
    end
    local seen = {}
    for _, sp in ipairs(data().Spells and data().Spells[class] or {}) do
      local name = ns.T(sp.n)
      local key = name and S.fold(name)
      if key and sp.k ~= "talent" and not seen[key] and not known[key] then
        seen[key] = true
        local sub = class == "GENERAL" and nil or className(class)
        add(sp.n, sub, class == "GENERAL" and "levels" or ("levels/" .. class), nil, { fid = sp.fid, icon = sp.i })
      end
    end
  end
end, { weight = 0.85 })

-- Generated name index (load-on-demand data) --------------------------------------------------

local function index(kind)
  local all = data().SearchIndex
  return all and all[kind] or {}
end

S.RegisterSource("faction", function(add)
  for _, row in ipairs(index("faction")) do
    add(pair(row[1], row[2]), nil, "reputation")
  end
end, { weight = 0.9 })

S.RegisterSource("itemset", function(add)
  for _, row in ipairs(index("itemset")) do
    add(pair(row[1], row[2]), nil, "itemsets/" .. row[3])
  end
end, { weight = 0.9 })

local GATHER_SUB = { herbalism = "search.sub.herb", mining = "search.sub.ore" }

S.RegisterSource("gather", function(add)
  for _, row in ipairs(index("gather")) do
    local key = GATHER_SUB[row[4]]
    add(pair(row[1], row[2]), key and L[key] or nil, "gathering/" .. row[3], key and { both(key).de, both(key).en })
  end
end)

S.RegisterSource("fishing", function(add)
  for _, row in ipairs(index("fishing")) do
    add(pair(row[1], row[2]), L["search.sub." .. row[4]], "fishing/" .. row[4] .. "/" .. row[3], { "Angeln", "Fishing" })
  end
end, { weight = 0.9 })

-- World: rares, flight points, stable masters --------------------------------------------------

local mapNames = {}
local function mapName(id)
  if mapNames[id] == nil then
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    mapNames[id] = info and info.name or false
  end
  return mapNames[id] or nil
end

S.RegisterSource("rare", function(add)
  local rares = data().Rares
  local ids = {}
  for id in pairs(rares and rares.npcs or {}) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local r = rares.npcs[id]
    local map
    for m in pairs(r.p or {}) do
      map = (not map or m < map) and m or map
    end
    local pts = map and r.p[map]
    local sub = string.format(L["search.sub.level"], r.l or 0)
    local zone = map and mapName(map)
    add(r.n, zone and (zone .. ", " .. sub) or sub, "map", nil, {
      place = map and { map = map, x = pts[1] / 100, y = pts[2] / 100, label = ns.T(r.n) } or nil,
    })
  end
end, { weight = 0.9 })

S.RegisterSource("flightpoint", function(add)
  for _, p in ipairs(data().FlightPoints or {}) do
    add(p.n, p.f and L["kit.faction." .. p.f] or nil, "map/" .. p.s)
  end
end, { weight = 0.85 })

S.RegisterSource("stable", function(add)
  for _, m in ipairs(ns.RefLogic.StableMasters(nil)) do
    add(m.n, m.p, "trainers/HUNTER", nil, {
      place = m.m and m.x and { map = m.m, x = m.x, y = m.y, label = ns.T(m.n) } or nil,
    })
  end
end, { weight = 0.9 })

-- Boss loot ----------------------------------------------------------------------------------

S.RegisterSource("loot", function(add)
  if ns.InstanceDataAccess then
    ns.InstanceDataAccess.Ensure()
  end
  for _, inst in ipairs(data().Instances or {}) do
    local slug, iname = ns.RefLogic.InstanceSlug(inst), ns.T(inst.n)
    local path = "instances/" .. slug .. "/items"
    for _, boss in ipairs(inst.bo or {}) do
      for _, row in ipairs(boss.lo or {}) do
        add(row.n, ns.T(boss.n) .. ", " .. iname, path, nil, { id = row.id })
      end
    end
    for _, row in ipairs(inst.tl or {}) do
      add(row.n, L["search.sub.trash"] .. ", " .. iname, path, nil, { id = row.id })
    end
  end
end, { weight = 0.8 })

-- Macros, commands, console variables, help, tours ---------------------------------------------

S.RegisterSource("macro", function(add)
  for _, m in ipairs(data().MacroPresets or {}) do
    add(m.t, short(m.d), "macros/templates")
  end
end, { weight = 0.9 })

S.RegisterSource("command", function(add)
  local C = ns.Commands
  for _, c in ipairs(C and C.list or {}) do
    local page = c.page and c.page ~= "main" and ns.Router:get(c.page) and c.page or "help/keys"
    add(c.usage, short(both("cmd." .. c.id)), page, c.names, nil)
  end
end, { weight = 0.9 })

S.RegisterSource("cvar", function(add)
  for _, v in ipairs(ns.ConsoleVars and ns.ConsoleVars.vars or {}) do
    add(both("console.v." .. v.name), nil, "console", { v.name })
  end
end, { weight = 0.9 })

S.RegisterSource("tour", function(add)
  local T = ns.Tutorials
  for _, tour in ipairs(T and T.list() or {}) do
    add(both(tour.title), nil, tour.page and ns.Router:get(tour.page) and tour.page or "help/start", nil, { tour = tour.id })
  end
end, { weight = 0.9 })

-- Sub-tabs -------------------------------------------------------------------------------------

-- Every tab strip of a page: page id, locale key of the tab, route (pages without a tab route open the page).
-- tests/test_searchsources.lua compares this with the tab strips found in the code.
ST.TABS = {
  { page = "classes", key = "classes.tab.classes", route = "classes" },
  { page = "classes", key = "classes.tab.races", route = "classes/races" },
  { page = "classes", key = "classes.tab.overview", route = "classes/overview" },
  { page = "help", key = "help.section.start", route = "help/start", kind = "help" },
  { page = "help", key = "help.section.keys", route = "help/keys", kind = "help" },
  { page = "help", key = "help.section.diag", route = "help/diag", kind = "help" },
  { page = "help", key = "help.section.feedback", route = "help/feedback", kind = "help" },
  { page = "help", key = "help.section.about", route = "help/about", kind = "help" },
  { page = "macros", key = "macros.tab.mine", route = "macros/mine" },
  { page = "macros", key = "macros.tab.build", route = "macros/build" },
  { page = "macros", key = "macros.tab.templates", route = "macros/templates" },
  { page = "macros", key = "macros.tab.io", route = "macros/io" },
  { page = "pets", key = "pets.tab.families", route = "pets/families" },
  { page = "pets", key = "pets.tab.abilities", route = "pets/abilities" },
  { page = "pets", key = "pets.tab.rares", route = "pets/rares" },
  { page = "map", key = "map.tab.azeroth", route = "map" },
  { page = "map", key = "map.tab.island", route = "map" },
  { page = "notes", key = "notes.tab.notes", route = "notes" },
  { page = "notes", key = "notes.tab.trash", route = "notes" },
  { page = "waypoints", key = "wp.tab.list", route = "waypoints" },
  { page = "waypoints", key = "wp.tab.settings", route = "waypoints" },
  { page = "wishlist", key = "wish.by.instance", route = "wishlist" },
  { page = "wishlist", key = "wish.by.slot", route = "wishlist" },
  { page = "guild", key = "guild.tab.guild", route = "guild" },
  { page = "calc", key = "calcui.history", route = "calc" },
  { page = "calc", key = "calcui.memory", route = "calc" },
}

-- Files that build a tab strip without being a page tab (windows and panels) or whose tabs are added above.
ST.TAB_FILES = {
  ["ClassesPage.lua"] = "classes",
  ["Help.lua"] = "help",
  ["Macros.lua"] = "macros",
  ["MacroUiKit.lua"] = "macros",
  ["PetsPage.lua"] = "pets",
  ["MapPage.lua"] = "map",
  ["NotesPage.lua"] = "notes",
  ["WaypointList.lua"] = "waypoints",
  ["WishlistPage.lua"] = "wishlist",
  ["CalcSide.lua"] = "calc",
  ["InstancesPage.lua"] = "instances",
  ["GuildPage.lua"] = "guild",
  ["DungeonWorldMap.lua"] = false,
  ["LfgFilterPanel.lua"] = false,
  ["LfgPanelDock.lua"] = false,
  ["AuctionLink.lua"] = false,
  ["BlizzardLinks.lua"] = false,
  ["Widgets.lua"] = false,
}

-- Tabs of the instance page, one set per instance.
ST.INSTANCE_TABS = { "bosses", "quests", "items", "access", "map", "info" }

local function tabName(pageKey, tabKey)
  local p, t = both(pageKey), both(tabKey)
  if type(p) ~= "table" or type(t) ~= "table" then
    return ns.T(p) and ns.T(t) and (ns.T(p) .. ": " .. ns.T(t)) or nil
  end
  return { de = p.de .. ": " .. t.de, en = p.en .. ": " .. t.en }
end

-- Tabs of the list as rows; asHelp picks the help sections (kind "help"), otherwise the others (kind "tab").
local function addTabs(add, asHelp)
  for _, tab in ipairs(ST.TABS) do
    local page = (tab.kind == "help") == asHelp and ns.Router:get(tab.page)
    local name = page and tabName(page.title, tab.key)
    if name then
      add(name, nil, tab.route)
    end
  end
end

S.RegisterSource("help", function(add)
  addTabs(add, true)
end, { weight = 0.9 })

S.RegisterSource("tab", function(add)
  addTabs(add, false)
  -- Tabs that add-ons put on the guild page.
  local guild = ns.Router:get("guild")
  for _, entry in ipairs(guild and ns.GuildExt and ns.GuildExt.Entries("tab") or {}) do
    local name = entry.key and tabName(guild.title, entry.key)
    if name then
      add(name, nil, "guild")
    end
  end
  local instances = ns.Router:get("instances")
  for _, inst in ipairs(instances and data().Instances or {}) do
    local slug = ns.RefLogic.InstanceSlug(inst)
    for _, id in ipairs(ST.INSTANCE_TABS) do
      local t = both("instances.dtab." .. id)
      if type(t) == "table" and type(inst.n) == "table" then
        add(
          { de = (inst.n.de or inst.n.en) .. ": " .. t.de, en = (inst.n.en or inst.n.de) .. ": " .. t.en },
          nil,
          "instances/" .. slug .. "/" .. id
        )
      end
    end
  end
end, { weight = 0.8 })

-- Row and click ------------------------------------------------------------------------------

local ICON_DIR = "Interface\\Icons\\"

local function itemIcon(id)
  local fn = C_Item and C_Item.GetItemIconByID or rawget(_G, "GetItemIcon")
  if type(fn) == "function" and type(id) == "number" then
    local ok, icon = pcall(fn, id)
    return ok and icon or nil
  end
end

-- Icon of a hit (texture path or file id), nil when the kind has none.
function ST.Icon(hit)
  local d = type(hit.data) == "table" and hit.data or nil
  if not d then
    return nil
  end
  if hit.kind == "loot" then
    return itemIcon(d.id)
  elseif d.icon then
    return ns.ResolveIcon(ICON_DIR .. d.icon)
  end
  return d.fid
end

-- Item id of a hit that is an item (the quality color and the tooltip come from it).
function ST.ItemId(hit)
  return hit.kind == "loot" and type(hit.data) == "table" and hit.data.id or nil
end

-- Primary action of a hit that is more than opening a page. Returns true when it handled the hit.
function ST.Open(hit)
  local d = type(hit.data) == "table" and hit.data or nil
  if hit.kind == "fishing" then
    local FL = ns.FishingLauncher
    local result = FL and FL.Open()
    if result ~= "open" and result then
      ns.Notify(tostring(result), "warning")
    end
    return true
  elseif hit.kind == "tour" and d and d.tour then
    ns.Router:navigate(hit.path)
    if ns.TutorialUI then
      ns.TutorialUI.Start(d.tour)
    end
    return true
  elseif d and d.place and (hit.kind == "rare" or hit.kind == "stable") then
    ns.PageKit.PlaceOnMap(d.place)
    return true
  end
  return false
end

return ST
