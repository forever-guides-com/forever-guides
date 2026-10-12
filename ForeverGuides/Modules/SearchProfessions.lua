-- Global search over the profession data add-ons: items (materials), recipes and profession
-- trainers. The add-ons load on demand and are large (recipes about 2.8 MB), so the first search
-- prepares everything in the background: load one add-on per frame, then cut the entries in time
-- slices (SP.BUDGET_MS per frame, C_Timer, no OnUpdate) and hand them to the index as batches of
-- ns.SearchLogic. While that runs the search works without these kinds. Switched-off add-ons give
-- one "load data" row instead of an error. Row actions (Row, Open) are shared by the results page.
local _, ns = ...
local L, S, K, W = ns.L, ns.SearchLogic, ns.PageKit, ns.W
local R, RL, Shop, U = ns.ProfessionRouteLogic, ns.RecipeLogic, ns.ProfessionShop, ns.PackageUI

local SP = {}
ns.SearchProfessions = SP

SP.KINDS = { "item", "recipe", "professionTrainer" }
-- Milliseconds of work per frame while the index is cut, and the pause before the first slice that
-- loads an add-on (the page shows its hint before the client stops for the load).
SP.BUDGET_MS = 4
SP.START_DELAY = 0.1
-- Entries between two looks at the clock.
local TICK = 16
local MAX_SLUGS_SHOWN = 3
local ICON_DIR = "Interface\\Icons\\"
local AUCTION_ICON = ICON_DIR .. "INV_Misc_Coin_01"
local SHOP_ICON = ICON_DIR .. "INV_Scroll_03"

-- Words that also find every herb or ore of a route (the names often lack them: "Friedensblume").
local TAGS = {
  herbalism = { de = "Kraut", en = "Herb" },
  mining = { de = "Erz", en = "Ore" },
}

ns.AddLocale("enUS", {
  ["search.kind.item"] = "Item",
  ["search.kind.recipe"] = "Recipe",
  ["search.kind.professionTrainer"] = "Profession trainer",
  ["search.group.item"] = "Items",
  ["search.group.recipe"] = "Recipes",
  ["search.group.professionTrainer"] = "Profession trainers",
  ["search.recipe.sub"] = "%s, skill %d",
  ["search.data.title"] = "Load profession data",
  ["search.data.sub"] = "Items, recipes and profession trainers are missing.",
  ["search.data.preparing"] = "Preparing items, recipes and profession trainers ...",
  ["search.data.waiting"] = "Profession data loads after the combat.",
  ["search.act.route"] = "Profession route",
  ["search.act.routeTip"] = "Opens the route of %s.",
  ["search.act.shop"] = "Shopping list",
  ["search.act.shopTip"] = "Opens the shopping list of %s.",
  ["search.act.auction"] = "Search in auction house",
  ["search.act.auctionTip"] = "Needs the open auction house, the search is filled for you.",
  ["search.act.auctionTipPlain"] = "Needs the open auction house.",
  ["search.act.map"] = "Show on map",
  ["search.act.marker"] = "Set waypoint",
  ["search.act.mapTip"] = "Opens the map at the trainer.",
  ["search.act.markerTip"] = "Sets a waypoint at the trainer.",
  ["search.act.noPosition"] = "The data has no position for this trainer.",
})

ns.AddLocale("deDE", {
  ["search.kind.item"] = "Item",
  ["search.kind.recipe"] = "Rezept",
  ["search.kind.professionTrainer"] = "Berufslehrer",
  ["search.group.item"] = "Items",
  ["search.group.recipe"] = "Rezepte",
  ["search.group.professionTrainer"] = "Berufslehrer",
  ["search.recipe.sub"] = "%s, Skill %d",
  ["search.data.title"] = "Berufsdaten laden",
  ["search.data.sub"] = "Items, Rezepte und Berufslehrer fehlen.",
  ["search.data.preparing"] = "Items, Rezepte und Berufslehrer werden vorbereitet ...",
  ["search.data.waiting"] = "Die Berufsdaten laden nach dem Kampf.",
  ["search.act.route"] = "Berufsroute",
  ["search.act.routeTip"] = "Öffnet die Route von %s.",
  ["search.act.shop"] = "Einkaufsliste",
  ["search.act.shopTip"] = "Öffnet die Einkaufsliste von %s.",
  ["search.act.auction"] = "Im Auktionshaus suchen",
  ["search.act.auctionTip"] = "Braucht das offene Auktionshaus, die Suche wird für dich gefüllt.",
  ["search.act.auctionTipPlain"] = "Braucht das offene Auktionshaus.",
  ["search.act.map"] = "Auf der Karte zeigen",
  ["search.act.marker"] = "Wegpunkt setzen",
  ["search.act.mapTip"] = "Öffnet die Karte beim Lehrer.",
  ["search.act.markerTip"] = "Setzt einen Wegpunkt beim Lehrer.",
  ["search.act.noPosition"] = "Die Daten haben für diesen Lehrer keine Position.",
})

-- Preparation -----------------------------------------------------------------------------------

-- "idle", "waiting" (combat, loads afterwards), "loading", "ready" or "failed".
local phase = "idle"
-- Generation of the running job: a newer one makes the older pump stop.
local gen = 0
-- An add-on of ours changed state, the next Prepare starts again.
local stale = false
local job

local function packages()
  return { ns.ProfessionRouteData.ADDON, ns.RecipeAccess.ADDON }
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function clock()
  if SP.clock then
    return SP.clock()
  end
  local stop = rawget(_G, "debugprofilestop")
  return type(stop) == "function" and stop() or nil
end

local function after(delay, fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, fn)
  else
    fn()
  end
end

local function nonEmpty(v)
  return type(v) == "string" and v ~= "" and v or nil
end

-- One item per id over all professions; the names of the routes (German and English) come first,
-- the recipe data fills what is missing.
local function noteItem(items, id, slug, names, icon)
  if type(id) ~= "number" then
    return nil
  end
  local it = items[id]
  if not it then
    it = { id = id, slugs = {}, has = {} }
    items[id] = it
  end
  names = type(names) == "table" and names or {}
  it.de, it.en = it.de or nonEmpty(names.de), it.en or nonEmpty(names.en)
  it.icon = it.icon or nonEmpty(icon)
  if not it.has[slug] then
    it.has[slug] = true
    it.slugs[#it.slugs + 1] = slug
  end
  return it
end

-- Position as fractions of the zone map; many trainers have none in the data (nil, nil).
local function fractions(t)
  local x, y = t.x, t.y
  if type(x) == "number" and type(y) == "number" and x > 0 and x <= 100 and y > 0 and y <= 100 then
    return x / 100, y / 100
  end
  return nil, nil
end

local function slugOrder()
  local order = {}
  for i, slug in ipairs(R.SLUGS) do
    order[slug] = i
  end
  return order
end

local function itemSubtitle(it)
  local parts = {}
  local tag = it.tag and TAGS[it.tag]
  if tag then
    parts[1] = ns.T(tag)
  end
  for i, slug in ipairs(it.slugs) do
    if i > MAX_SLUGS_SHOWN then
      parts[#parts + 1] = "..."
      break
    end
    parts[#parts + 1] = R.Name(slug)
  end
  return table.concat(parts, ", ")
end

-- The work of one preparation, run as a coroutine: it yields after a load and whenever the slice
-- of SP.BUDGET_MS is used up.
local function prepare()
  local yield = coroutine.yield
  local sliceStart, count = clock(), 0
  local function rest()
    sliceStart = clock()
  end
  local function tick()
    count = count + 1
    if count % TICK == 0 then
      local now = clock()
      if now and sliceStart and now - sliceStart >= SP.BUDGET_MS then
        yield()
        rest()
      end
    end
  end

  for _, name in ipairs(packages()) do
    if U.State(name) == "idle" then
      ns.LoadPackage(name)
      yield()
      rest()
    end
  end

  local routes, recipes = rawget(ns, "ProfessionData"), rawget(ns, "RecipeData")
  routes, recipes = type(routes) == "table" and routes or {}, type(recipes) == "table" and recipes or {}
  local batch = {}
  for _, kind in ipairs(SP.KINDS) do
    batch[kind] = S.NewBatch(kind)
  end
  local items, trainers, trainerSeen = {}, {}, {}
  -- Names { de, en } of the recipes by result item.
  local products = {}

  for _, slug in ipairs(R.SLUGS) do
    local d = routes[slug]
    if type(d) == "table" then
      local crafts = type(d.steps) == "table" and #d.steps > 0
      for id, row in pairs(type(d.items) == "table" and d.items or {}) do
        local it = noteItem(items, id, slug, row, type(row) == "table" and row.icon or nil)
        if it then
          it.tag = it.tag or (TAGS[slug] and slug) or nil
          it.gather = it.gather or (d.gather ~= nil and slug) or nil
          it.shop = it.shop or (crafts and slug) or nil
        end
      end
      for _, rank in ipairs(type(d.ranks) == "table" and d.ranks or {}) do
        for _, t in ipairs(type(rank.trainers) == "table" and rank.trainers or {}) do
          if type(t) == "table" and nonEmpty(t.n) then
            local zone = type(t.zone) == "table" and t.zone or { de = t.locDe, en = t.loc }
            local key = slug .. "|" .. t.n .. "|" .. tostring(zone.en)
            if not trainerSeen[key] then
              trainerSeen[key] = true
              trainers[#trainers + 1] = { slug = slug, t = t, zone = zone }
            end
          end
        end
      end
      tick()
    end
  end

  for _, slug in ipairs(R.SLUGS) do
    local d = recipes[slug]
    if type(d) == "table" and type(d.list) == "table" then
      for id, row in pairs(type(d.items) == "table" and d.items or {}) do
        noteItem(items, id, slug, row, type(row) == "table" and row.ico or nil)
      end
      local prof, fmt = R.Name(slug), L["search.recipe.sub"]
      for _, r in ipairs(d.list) do
        if RL.Valid(r) and not r.rm then
          local level = r.sk[1]
          local sub = type(level) == "number" and level > 0 and string.format(fmt, prof, level) or prof
          -- The payload is the item the recipe makes (its icon is looked up when a row is shown).
          batch.recipe.add(
            { de = nonEmpty(r.n[1]), en = nonEmpty(r.n[2]) },
            sub,
            "professions/" .. slug .. "/" .. r.s,
            nil,
            type(r.i) == "number" and r.i or nil
          )
          if type(r.i) == "number" and not products[r.i] then
            products[r.i] = r.n
          end
          tick()
        end
      end
    end
  end

  -- Most materials have an English name only. A recipe that makes the item under the same English
  -- name (potions, bars) lends its German name.
  for id, n in pairs(products) do
    local it = items[id]
    if it and not it.de and it.en and it.en == n[2] and nonEmpty(n[1]) and n[1] ~= n[2] then
      it.de = n[1]
    end
  end

  local order = slugOrder()
  local ids = {}
  for id in pairs(items) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local it = items[id]
    if it.de or it.en then
      table.sort(it.slugs, function(a, b)
        return (order[a] or 99) < (order[b] or 99)
      end)
      local primary = it.gather or it.shop or it.slugs[1]
      local tag = it.tag and TAGS[it.tag]
      batch.item.add(
        { de = it.de, en = it.en },
        itemSubtitle(it),
        "professionroute/" .. primary,
        tag and { tag.de, tag.en } or nil,
        { id = id, de = it.de, en = it.en, icon = it.icon, slugs = it.slugs, route = primary, shop = it.shop }
      )
      tick()
    end
  end

  table.sort(trainers, function(a, b)
    if a.slug ~= b.slug then
      return (order[a.slug] or 99) < (order[b.slug] or 99)
    end
    return a.t.n < b.t.n
  end)
  for _, e in ipairs(trainers) do
    local p = R.PROFESSIONS[e.slug]
    local parts = { R.Name(e.slug), ns.T(e.zone) or "" }
    if e.t.f == "A" or e.t.f == "H" then
      parts[#parts + 1] = L["kit.faction." .. e.t.f]
    end
    local x, y = fractions(e.t)
    batch.professionTrainer.add(
      e.t.n,
      table.concat(parts, ", "),
      "professionroute/" .. e.slug,
      p and { p.de .. " Lehrer", p.en .. " trainer" } or nil,
      { slug = e.slug, n = e.t.n, x = x, y = y, zone = e.zone }
    )
    tick()
  end

  for _, b in pairs(batch) do
    b.done()
  end
end

local function finish(ok)
  phase = ok and "ready" or "failed"
  job = nil
  ns.Emit("FG_SEARCH_DATA", phase)
end

local function pump(mine)
  if mine ~= gen or not job then
    return
  end
  local co = job
  local ran = ns.Safe("search-professions", function()
    local alive, err = coroutine.resume(co)
    if not alive then
      error(err, 0)
    end
  end)
  if mine ~= gen then
    return
  end
  if not ran then
    finish(false)
  elseif coroutine.status(co) == "dead" then
    -- The merged index is built in a frame of its own, not on top of the last slice.
    after(0, function()
      if mine == gen then
        finish(ns.Safe("search-professions", S.GetIndex))
      end
    end)
  else
    after(0, function()
      pump(mine)
    end)
  end
end

-- Starts the preparation when it is due (first search, language changed, an add-on changed) and
-- returns the phase. The page asks on every search, a finished or running job is left alone.
function SP.Prepare()
  if phase == "loading" or phase == "waiting" then
    return phase
  end
  local ready = phase == "ready" and S.BatchLocale("item") == ns.GetActiveLocale()
  if (ready or phase == "failed") and not stale then
    return phase
  end
  stale = false
  local needsLoad = false
  for _, name in ipairs(packages()) do
    needsLoad = needsLoad or U.State(name) == "idle"
  end
  if needsLoad and inCombat() then
    phase = "waiting"
    return phase
  end
  phase = "loading"
  gen = gen + 1
  job = coroutine.create(prepare)
  local mine = gen
  after(needsLoad and SP.START_DELAY or 0, function()
    pump(mine)
  end)
  return phase
end

function SP.Phase()
  return phase
end

-- Forgets everything (tests).
function SP.Reset()
  phase, gen, stale, job = "idle", gen + 1, false, nil
end

ns.On("PLAYER_REGEN_ENABLED", function()
  if phase == "waiting" then
    phase = "idle"
    SP.Prepare()
  end
end)

-- An add-on was switched on or loaded elsewhere: cut again, but only once the search was used.
ns.On("FG_PACKAGE_CHANGED", function(_, name)
  local mine = false
  for _, p in ipairs(packages()) do
    mine = mine or p == name
  end
  if mine and phase ~= "idle" then
    gen = gen + 1
    stale, phase, job = true, "idle", nil
    SP.Prepare()
  end
end)

-- Hints ------------------------------------------------------------------------------------------

-- The add-ons that are switched off or not installed: { { name, state } }.
function SP.Unavailable()
  local out = {}
  for _, name in ipairs(packages()) do
    local state = U.State(name)
    if state == "off" or state == "missing" then
      out[#out + 1] = { name = name, state = state }
    end
  end
  return out
end

-- The "load data" row of the result list, nil when every data add-on is there.
function SP.PackageRow()
  local list = SP.Unavailable()
  if #list == 0 then
    return nil
  end
  local off = false
  for _, p in ipairs(list) do
    off = off or p.state == "off"
  end
  return {
    package = true,
    kind = "package",
    name = L["search.data.title"],
    sub = L["search.data.sub"],
    right = L[off and "pkg.enable" or "pkg.copy"],
  }
end

-- A click on the row: switch on and load what is off, the download link for what is not installed.
function SP.EnableMissing()
  for _, p in ipairs(SP.Unavailable()) do
    if p.state == "missing" then
      ns.Dialogs.Copy("pkg.copy.title", ns.Website, "pkg.copy.hint")
      return
    end
    local ok, reason = U.Enable(p.name)
    if not ok then
      local text = reason == "COMBAT" and L["pkg.combat"]
        or (U.RestartPending(p.name) and L["pkg.restart"])
        or L["pkg.err.failed"]
      ns.Notify(text, "warning")
    end
  end
end

-- Text under the list while the data is not complete yet, nil otherwise.
function SP.StatusText()
  if phase == "loading" then
    return L["search.data.preparing"]
  elseif phase == "waiting" then
    return L["search.data.waiting"]
  end
  return nil
end

-- Actions ----------------------------------------------------------------------------------------

-- Map of a zone by its name in either language; only a unique hit counts (a wrong pin is worse
-- than none).
local function zoneMap(zone)
  local index = ns.Waypoints.ZoneIndex()
  for _, name in ipairs({ ns.T(zone) or "", zone.de or "", zone.en or "" }) do
    if name ~= "" then
      local hits = ns.WaypointLogic.matchZones(index, name)
      if #hits == 1 then
        return hits[1].id
      end
    end
  end
  return nil
end

-- { map, x, y, label } of a trainer (x, y nil without a position), nil (with a warning) when the
-- zone has no unique map.
local function trainerPlace(d)
  local map = type(d.zone) == "table" and zoneMap(d.zone) or nil
  if not map then
    ns.Notify(ns.Waypoints.ErrorText("unknownZone", type(d.zone) == "table" and ns.T(d.zone) or d.n), "warning")
    return nil
  end
  return { map = map, x = d.x, y = d.y, label = d.n }
end

-- The primary action of a hit that is more than opening a page: a trainer sets the waypoint (when
-- the data has a position) and opens the map. Returns true when it handled the hit.
function SP.Open(hit)
  if hit.kind ~= "professionTrainer" or type(hit.data) ~= "table" then
    return false
  end
  local place = trainerPlace(hit.data)
  if place then
    if place.x then
      K.PlaceMarker(place)
    end
    K.PlaceOnMap(place)
  end
  return true
end

local function routeAction(slug)
  return {
    icon = ns.ResolveIcon(ns.ICONS.professionroute),
    boxed = true,
    tooltip = L["search.act.route"],
    tooltipText = string.format(L["search.act.routeTip"], R.Name(slug)),
    onClick = function()
      ns.Router:navigate("professionroute/" .. slug)
    end,
  }
end

local function shopAction(slug)
  return {
    icon = SHOP_ICON,
    boxed = true,
    tooltip = L["search.act.shop"],
    tooltipText = string.format(L["search.act.shopTip"], R.Name(slug)),
    onClick = function()
      Shop.SetOption("slug", slug)
      ns.ProfessionShopWindow.Open()
    end,
  }
end

local function auctionAction(hit)
  local d = hit.data
  return {
    icon = AUCTION_ICON,
    boxed = true,
    tooltip = L["search.act.auction"],
    tooltipText = L[Shop.ListApiReady() and "search.act.auctionTip" or "search.act.auctionTipPlain"],
    onClick = function()
      Shop.RowClick({ id = d.id, de = d.de, en = d.en, name = hit.name }, "LeftButton")
    end,
  }
end

-- Client icon file of each profession, the fallback icon of its recipes.
local PROFESSION_ICON = {
  alchemy = "Trade_Alchemy",
  blacksmithing = "Trade_BlackSmithing",
  cooking = "INV_Misc_Food_15",
  enchanting = "Trade_Engraving",
  engineering = "Trade_Engineering",
  ["first-aid"] = "Spell_Holy_SealOfSacrifice",
  fishing = "Trade_Fishing",
  herbalism = "Trade_Herbalism",
  leatherworking = "Trade_LeatherWorking",
  mining = "Trade_Mining",
  skinning = "INV_Misc_Pelt_Wolf_01",
  tailoring = "Trade_Tailoring",
}

-- Icon of a recipe: the item it makes where the data knows one (few do), else its profession's.
local function recipeIcon(slug, id)
  local all = rawget(ns, "RecipeData")
  local row = type(id) == "number" and type(all) == "table" and type(all[slug]) == "table" and all[slug].items
  row = type(row) == "table" and row[id]
  local ico = type(row) == "table" and nonEmpty(row.ico) or PROFESSION_ICON[slug]
  return ico and ns.ResolveIcon(ICON_DIR .. ico) or nil
end

-- { icon, actions } for the list row of a hit of these kinds (nil for others): the first action
-- sits at the right edge. Nothing here touches a protected frame, so it works in combat.
function SP.Row(hit)
  local d = type(hit.data) == "table" and hit.data or nil
  if hit.kind == "item" and d then
    local actions = { routeAction(d.route) }
    if d.shop then
      actions[#actions + 1] = shopAction(d.shop)
    end
    if type(d.id) == "number" then
      actions[#actions + 1] = auctionAction(hit)
    end
    local tooltip
    if type(d.id) == "number" then
      -- The client's own item tooltip; the name and professions stand in while it is not cached.
      tooltip = {
        link = "item:" .. d.id,
        title = hit.name,
        lines = hit.sub and hit.sub ~= "" and { { text = hit.sub, color = "textSecondary" } } or nil,
      }
    end
    return { icon = d.icon and ns.ResolveIcon(ICON_DIR .. d.icon) or nil, actions = actions, tooltipSpec = tooltip }
  elseif hit.kind == "recipe" then
    local slug = hit.path and hit.path:match("^professions/([^/]+)")
    return { icon = slug and recipeIcon(slug, hit.data) or nil, actions = slug and { routeAction(slug) } or {} }
  elseif hit.kind == "professionTrainer" and d then
    return {
      actions = {
        {
          icon = ns.ICONS.map,
          boxed = true,
          tooltip = L["search.act.map"],
          tooltipText = L["search.act.mapTip"],
          onClick = function()
            local place = trainerPlace(d)
            if place then
              K.PlaceOnMap(place)
            end
          end,
        },
        {
          icon = W.MARKER_ICON,
          boxed = true,
          tooltip = L["search.act.marker"],
          tooltipText = L[d.x and "search.act.markerTip" or "search.act.noPosition"],
          dim = d.x == nil,
          onClick = function()
            local place = trainerPlace(d)
            if place then
              K.PlaceMarker(place)
            end
          end,
        },
        routeAction(d.slug),
      },
    }
  end
  return nil
end

-- Sources ----------------------------------------------------------------------------------------

-- Entries come from the batches of Prepare, not from a source function.
S.RegisterSource("item", nil)
S.RegisterSource("recipe", nil, { weight = 0.9 })
S.RegisterSource("professionTrainer", nil)
