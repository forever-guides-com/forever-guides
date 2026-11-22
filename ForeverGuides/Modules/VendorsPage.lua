-- Vendors: the NPCs that sell goods for the professions (recipes, materials, cooking ingredients, fishing gear,
-- food, bandages, poisons, tools) with the zone, the position and what they sell. Master and detail like the
-- reputation page: filters on top, the vendor list on the left, the chosen vendor with his offer on the right
-- (narrow pages show one of the two with a back button). Data: VendorSource (load-on-demand add-on), logic:
-- VendorLogic.
local _, ns = ...
local Theme = ns.Theme
local W, L, K = ns.W, ns.L, ns.PageKit
local R, VL, VS = ns.ProfessionRouteLogic, ns.VendorLogic, ns.VendorSource

ns.AddLocale("enUS", {
  ["page.vendors"] = "Vendors",
  ["vendors.intro"] = "NPCs that sell recipes, materials, fishing gear and food, by profession, with zone, position and offer",
  ["page.vendors.sub"] = "Vendors for recipes, materials and more",
  ["vendors.source"] = "Offers are Classic data and not yet verified for Forever. Vendors that exist only in Forever are missing.",
  ["vendors.profession"] = "Profession",
  ["vendors.professionTip"] = "Shows the vendors that sell goods for one profession or for all.",
  ["vendors.professionAll"] = "All professions",
  ["vendors.kind"] = "Kind",
  ["vendors.kindTip"] = "Shows vendors with this kind of goods.",
  ["vendors.kindAll"] = "All kinds",
  ["vendors.kind.g"] = "General goods",
  ["vendors.kind.r"] = "Recipes",
  ["vendors.kind.m"] = "Crafting materials",
  ["vendors.kind.k"] = "Cooking ingredients",
  ["vendors.kind.x"] = "Spell reagents",
  ["vendors.kind.f"] = "Fishing gear",
  ["vendors.kind.d"] = "Food and drink",
  ["vendors.kind.b"] = "Bandages",
  ["vendors.kind.p"] = "Poisons",
  ["vendors.kind.t"] = "Profession tools",
  ["vendors.kind.o"] = "Mounts",
  ["vendors.posUnknown"] = "Position unknown",
  ["vendors.search"] = "Search",
  ["vendors.searchPh"] = "Vendor, zone or item",
  ["vendors.placeLine"] = "%s, %s",
  ["vendors.attr.position"] = "Position",
  ["vendors.card.wares"] = "Wares",
  ["vendors.npc"] = "NPC ID %d",
  ["vendors.total"] = "Vendors: %d, offers: %d",
  ["vendors.empty"] = "No vendors for this selection.",
  ["vendors.mapTip"] = "Shows the vendor's zone on the map.",
  ["vendors.markerTip"] = "Sets a waypoint at the vendor.",
  ["vendors.back"] = "Vendors",
  ["vendors.backTip"] = "Back to the vendor list",
  ["vendors.itemSearchPh"] = "Search the offer",
  ["vendors.sortList"] = "Order",
  ["vendors.sortName"] = "Name",
  ["vendors.sortPrice"] = "Price",
  ["vendors.offerCount"] = "%d of %d items",
  ["vendors.offerEmpty"] = "No item matches.",
  ["vendors.linkTip"] = "Click: show vendor",
})

ns.AddLocale("deDE", {
  ["page.vendors"] = "Händler",
  ["vendors.intro"] = "NPCs, die Rezepte, Material, Angelzubehör und Nahrung verkaufen, nach Beruf, mit Zone, Position und Angebot",
  ["page.vendors.sub"] = "Händler für Rezepte, Material und mehr",
  ["vendors.source"] = "Die Angebote sind Classic-Daten und noch nicht für Forever geprüft. Händler, die es nur in Forever gibt, fehlen.",
  ["vendors.profession"] = "Beruf",
  ["vendors.professionTip"] = "Zeigt die Händler, die Waren für einen Beruf oder für alle verkaufen.",
  ["vendors.professionAll"] = "Alle Berufe",
  ["vendors.kind"] = "Art",
  ["vendors.kindTip"] = "Zeigt Händler mit dieser Art von Waren.",
  ["vendors.kindAll"] = "Alle Arten",
  ["vendors.kind.g"] = "Gemischtwaren",
  ["vendors.kind.r"] = "Rezepte",
  ["vendors.kind.m"] = "Handwerksmaterial",
  ["vendors.kind.k"] = "Kochzutaten",
  ["vendors.kind.x"] = "Zauberreagenzien",
  ["vendors.kind.f"] = "Angelzubehör",
  ["vendors.kind.d"] = "Essen und Trinken",
  ["vendors.kind.b"] = "Verbände",
  ["vendors.kind.p"] = "Gifte",
  ["vendors.kind.t"] = "Berufswerkzeug",
  ["vendors.kind.o"] = "Reittiere",
  ["vendors.posUnknown"] = "Position unbekannt",
  ["vendors.search"] = "Suchen",
  ["vendors.searchPh"] = "Händler, Zone oder Item",
  ["vendors.placeLine"] = "%s, %s",
  ["vendors.attr.position"] = "Position",
  ["vendors.card.wares"] = "Waren",
  ["vendors.npc"] = "NPC-ID %d",
  ["vendors.total"] = "Händler: %d, Angebote: %d",
  ["vendors.empty"] = "Keine Händler für diese Auswahl.",
  ["vendors.mapTip"] = "Zeigt die Zone des Händlers auf der Karte.",
  ["vendors.markerTip"] = "Setzt einen Wegpunkt am Händler.",
  ["vendors.back"] = "Händler",
  ["vendors.backTip"] = "Zurück zur Händlerliste",
  ["vendors.itemSearchPh"] = "Angebot durchsuchen",
  ["vendors.sortList"] = "Reihenfolge",
  ["vendors.sortName"] = "Name",
  ["vendors.sortPrice"] = "Preis",
  ["vendors.offerCount"] = "%d von %d Items",
  ["vendors.offerEmpty"] = "Kein Item passt.",
  ["vendors.linkTip"] = "Klicken: Händler anzeigen",
})

-- Boxed offer rows carry tags on the second line, so they take the tag row height.
local OFFER_ROW = 52
local SORTS = { "name", "price" }
local SORT_KEY = { name = "vendors.sortName", price = "vendors.sortPrice" }

local VP = {}
ns.VendorsPage = VP

-- Opens the vendors page with the vendor chosen (filters reset, list scrolled to him). An unknown id opens the
-- page without a chosen vendor.
function VP.OpenVendor(npc)
  npc = tonumber(npc)
  return ns.Router:navigate(npc and npc >= 1 and ("vendors/" .. math.floor(npc)) or "vendors")
end

-- Turns a vendor name text into a link to its vendor page. Call once per (pooled) row and keep the returned
-- button; link:SetNpc(id) then binds the current vendor (nil hides the link), so a recycled row never opens
-- a stale vendor.
function VP.Link(owner, text)
  local link = CreateFrame("Button", nil, owner)
  link:SetAllPoints(text)
  link.hl = link:CreateTexture(nil, "BACKGROUND")
  link.hl:SetAllPoints()
  link.hl:SetColorTexture(ns.Theme.fillColor())
  function link:SetNpc(npc)
    self.npc = npc
    self:SetShown(npc ~= nil)
  end
  link:SetNpc(nil)
  if link.RegisterForClicks then
    link:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  end
  link:SetScript("OnEnter", function(self)
    self.hl:SetColorTexture(Theme.fillColor("hover"))
    ns.ShowTooltip(self, L["vendors.linkTip"])
  end)
  link:SetScript("OnLeave", function(self)
    self.hl:SetColorTexture(ns.Theme.fillColor())
    ns.HideTooltip()
  end)
  link:SetScript(
    "OnClick",
    ns.Wrap("vendor-link", function(self, button)
      -- Modified clicks (shift-link, compare) and the right button stay with the row underneath.
      local modified = type(rawget(_G, "IsModifiedClick")) == "function" and rawget(_G, "IsModifiedClick")()
      if modified or button == "RightButton" then
        local handler = owner.GetScript and owner:GetScript("OnClick")
        if handler then
          handler(owner, button)
        end
        return
      end
      if self.npc then
        VP.OpenVendor(self.npc)
      end
    end)
  )
  ns.Focus.register(link, function(self)
    self:Click()
  end)
  return link
end

local FACTION_KEY = { A = "kit.faction.A", H = "kit.faction.H", B = "kit.faction.all" }

local function itemLabel(id)
  return VS.ItemName(id) or string.format(L["proflist.itemName"], id)
end

-- Asks the client for the names it does not hold yet; GET_ITEM_INFO_RECEIVED repaints the list.
local function requestNames(ids)
  local item = rawget(_G, "C_Item")
  if type(item) == "table" and type(item.RequestLoadItemDataByID) == "function" then
    for _, id in ipairs(ids) do
      if not VS.ItemName(id) then
        pcall(item.RequestLoadItemDataByID, id)
      end
    end
  end
end

local function kindsText(entry)
  local parts = {}
  for _, kind in ipairs(VL.KINDS) do
    if VL.HasKind(entry, kind) then
      parts[#parts + 1] = L["vendors.kind." .. kind]
    end
  end
  return table.concat(parts, ", ")
end

local function factionName(entry)
  return L[FACTION_KEY[entry.faction]]
end

-- Meta line of a list row: faction and zone.
local function placeText(entry)
  return string.format(L["vendors.placeLine"], factionName(entry), VS.ZoneName(entry) or "?")
end

-- The faction crest of a vendor; neutral vendors show both.
local function crest(entry)
  return K.FactionIconSpec(entry.faction == "B" and "all" or entry.faction)
end

-- Row of the item list: framed icon with the quality edge, name in the quality color, price, tags for the stock
-- and the conditions.
local function bindOffer(offer)
  local name = itemLabel(offer.id)
  local tags = {}
  if VL.Limited(offer.flags) then
    tags[#tags + 1] = { key = "vendor.limited", color = "warning" }
  end
  if VL.Restricted(offer.flags) then
    tags[#tags + 1] = { key = "vendor.restricted", color = "warning" }
  end
  local hex = ns.ItemInfo and ns.ItemInfo.qualityHex(VS.ItemQuality(offer.id)) or nil
  return {
    title = name,
    titleHex = hex,
    icon = VS.ItemIcon(offer.id),
    iconFrame = { size = Theme.size.iconFrame.md, edge = hex and ("#" .. hex) or nil },
    meta = VL.PriceText(offer, VS.Money),
    tags = #tags > 0 and tags or nil,
    tooltipSpec = { link = "item:" .. tostring(offer.id), title = name },
  }
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = {
    slug = "all",
    kind = "all",
    faction = K.PlayerFaction() or "all",
    query = "",
    npc = 0,
    sort = "data",
    itemQuery = "",
    detail = false,
  }
  ns.PageState.Bind(view, state, { "slug", "kind", "faction", "query", "npc", "sort" })
  local index
  local refresh

  ns.AddIntro(view, "vendors.intro")
  ns.AddParagraph(view, "vendors.source", { role = "micro", color = "textMuted", gap = Theme.space.sm })
  local hint = ns.AddParagraph(view, nil, { role = "ui", color = "warning", gap = Theme.space.md })
  -- Instead of the hint while the data add-on is off or missing: the button that switches it on.
  local banner = ns.PackageUI.Banner(view.content, VS.ADDON, {
    onLoaded = function()
      VS.Reset()
      refresh()
    end,
    onResize = function()
      view:Layout()
    end,
  })
  s:Add(banner, { gap = Theme.space.md })

  local professionOptions = { { value = "all", key = "vendors.professionAll" } }
  for _, slug in ipairs(R.SLUGS) do
    professionOptions[#professionOptions + 1] = { value = slug, text = R.Name(slug) }
  end
  local kindOptions = { { value = "all", key = "vendors.kindAll" } }
  for _, kind in ipairs(VL.KINDS) do
    kindOptions[#kindOptions + 1] = { value = kind, key = "vendors.kind." .. kind }
  end
  local search
  local function clearFilters()
    state.slug, state.kind, state.faction, state.query = "all", "all", K.PlayerFaction() or "all", ""
    search.edit:SetText("")
    refresh()
  end
  local filters = K.FilterBar(view.content, {
    count = function()
      return (state.slug ~= "all" and 1 or 0)
        + (state.kind ~= "all" and 1 or 0)
        + (state.faction ~= (K.PlayerFaction() or "all") and 1 or 0)
        + (state.query ~= "" and 1 or 0)
    end,
    reset = clearFilters,
  })
  local professionDd = filters:AddDropdown({
    key = "vendors.profession",
    options = professionOptions,
    tooltip = "vendors.profession",
    tooltipText = "vendors.professionTip",
    get = function()
      return state.slug
    end,
    set = function(v)
      state.slug = v
      refresh()
    end,
  })
  local kindDd = filters:AddDropdown({
    key = "vendors.kind",
    options = kindOptions,
    tooltip = "vendors.kind",
    tooltipText = "vendors.kindTip",
    get = function()
      return state.kind
    end,
    set = function(v)
      state.kind = v
      refresh()
    end,
  })
  search = filters:AddSearch({
    key = "vendors.search",
    text = state.query,
    placeholder = "vendors.searchPh",
    width = 240,
    onChange = function(text)
      state.query = text
      refresh()
    end,
  })
  local factionButtons = filters:AddGroup(K.FactionButtons(filters, {
    withAll = true,
    get = function()
      return state.faction
    end,
    set = function(v)
      state.faction = v
      refresh()
    end,
  }))
  s:Add(filters, { gap = Theme.space.md })
  K.Anchor("FG.Vendors.Controls", filters)

  local total = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = Theme.space.sm })

  local shown, selected = {}, nil
  local paintDetail, layoutDetail
  local syncing = false

  -- The list is made before the master/detail shell so the keyboard reaches it before the detail.
  local list, split
  list = K.NewList(view.content, {
    look = "boxed",
    bind = function(entry)
      local mine = selected ~= nil and selected.npc == entry.npc
      return {
        title = VL.Name(entry),
        sub = placeText(entry),
        iconFrame = { spec = crest(entry) },
        selected = mine,
        cursor = mine,
      }
    end,
    onClick = function(entry)
      state.npc, state.detail = entry.npc, true
      selected = entry
      list:SetData(shown)
      paintDetail()
      split:SetSelected(entry)
      split:ShowDetail(true)
      view:Layout()
    end,
  })
  K.Anchor("FG.Vendors.List", list)

  split = K.MasterDetail(view.content, {
    list = list,
    backKey = "vendors.back",
    backTip = "vendors.backTip",
    onToggle = function(on)
      if not syncing then
        state.detail = on
      end
    end,
    detail = function(width)
      return layoutDetail(width)
    end,
  })
  K.Anchor("FG.Vendors.Detail", split.detail)
  local content = split.content

  -- Hero: crest, name, zone, attribute lines, the id as a tag; map, waypoint and share at the top right.
  local hero = K.Hero(content, {})
  local actions = W.MapActionButtons(hero, { mapTip = "vendors.mapTip", markerTip = "vendors.markerTip", share = true })
  hero:SetActions(actions)

  local itemSearch, sortLabel, count, noOffer, offerList, wares
  local sortButtons = {}
  local offerShown = 0
  wares = K.SectionCard(content, {
    key = "vendors.card.wares",
    body = function(w)
      local sm = Theme.space.sm
      itemSearch:ClearAllPoints()
      itemSearch:SetPoint("TOPLEFT", wares.body, "TOPLEFT", 0, 0)
      itemSearch:SetWidth(w)
      local y = itemSearch:GetHeight() + sm
      -- Order: label and buttons on one line when they fit, else the label above.
      local rowH = sortButtons.name:GetHeight()
      local labelW = math.ceil(sortLabel:GetStringWidth())
      local buttonsW = 0
      for _, sort in ipairs(SORTS) do
        buttonsW = buttonsW + sortButtons[sort]:GetWidth() + 6
      end
      local inline = labelW + sm + buttonsW - 6 <= w
      local x = 0
      sortLabel:ClearAllPoints()
      if inline then
        sortLabel:SetPoint("TOPLEFT", wares.body, "TOPLEFT", 0, -(y + math.floor((rowH - sortLabel:GetHeight()) / 2)))
        x = labelW + sm
      else
        sortLabel:SetPoint("TOPLEFT", wares.body, "TOPLEFT", 0, -y)
        y = y + math.ceil(sortLabel:GetHeight()) + 2
      end
      for _, sort in ipairs(SORTS) do
        local b = sortButtons[sort]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", wares.body, "TOPLEFT", x, -y)
        x = x + b:GetWidth() + 6
      end
      y = y + rowH + sm
      count:ClearAllPoints()
      count:SetPoint("TOPLEFT", wares.body, "TOPLEFT", 0, -y)
      y = y + W.FitLabel(count, w) + sm
      noOffer:ClearAllPoints()
      offerList:ClearAllPoints()
      if offerShown == 0 then
        noOffer:SetPoint("TOPLEFT", wares.body, "TOPLEFT", 0, -y)
        y = y + W.FitLabel(noOffer, w)
      else
        local h = offerShown * K.scaledHeight(OFFER_ROW)
        offerList:SetPoint("TOPLEFT", wares.body, "TOPLEFT", 0, -y)
        offerList:SetSize(w, h)
        y = y + h
      end
      return y
    end,
  })
  itemSearch = W.EditBox(wares.body, {
    placeholder = "vendors.itemSearchPh",
    clear = true,
    onChange = function(text)
      state.itemQuery = text
      paintDetail()
      view:Layout()
    end,
  })
  sortLabel = W.Meta(wares.body, { key = "vendors.sortList" })
  for _, sort in ipairs(SORTS) do
    sortButtons[sort] = W.Button(wares.body, {
      key = SORT_KEY[sort],
      width = 90,
      onClick = function()
        -- A second click on the active order goes back to the order of the data.
        state.sort = state.sort == sort and "data" or sort
        paintDetail()
        view:Layout()
      end,
    })
  end
  count = W.Meta(wares.body, { wrap = true })
  noOffer = W.Text(wares.body, { key = "vendors.offerEmpty", role = "ui", color = "textMuted", wrap = true })
  offerList = K.NewList(wares.body, {
    look = "boxed",
    rowHeight = OFFER_ROW,
    bind = bindOffer,
    -- Hook point: ns.ItemActions (tooltip, shift-click link, ctrl-click dress-up) joins the rows when it exists.
    onBindRow = function(row, offer)
      ns.WishlistStar.Bind(row, offer.id)
      row.trailing = row.star
      row.offerId = offer.id
      -- Pooled rows: hook once and read the current id, or old ids fire too.
      if ns.ItemActions and not row.itemActionsBound then
        row.itemActionsBound = true
        ns.ItemActions.Bind(row, function(self) return self.offerId end)
      end
    end,
  })

  function paintDetail()
    local entry = selected
    hero:SetShown(entry ~= nil)
    wares:SetShown(entry ~= nil)
    if not entry then
      return
    end
    local coord = K.Coord(entry.x, entry.y)
    hero:SetPortrait({ spec = crest(entry), name = VL.Name(entry) })
    hero:SetTitle(VL.Name(entry))
    hero:SetSubtitle(VS.ZoneName(entry) or "?")
    local kinds = kindsText(entry)
    hero:SetAttrs({
      { labelKey = "kit.filterFaction", value = factionName(entry) },
      kinds ~= "" and { labelKey = "vendors.kind", value = kinds } or nil,
      coord and { labelKey = "vendors.attr.position", value = coord } or { label = L["vendors.posUnknown"] },
    })
    hero:SetTags({ { text = string.format(L["vendors.npc"], entry.npc) } })
    actions:SetPlace(VL.Place(entry) and function()
      return VL.Place(entry, VS.ZoneName(entry))
    end or nil)
    actions:SetShare("vendors/" .. entry.npc)
    for sort, b in pairs(sortButtons) do
      b:SetSelected(state.sort == sort)
    end
    local ids = {}
    for i, offer in ipairs(entry.offers) do
      ids[i] = offer.id
    end
    requestNames(ids)
    local offers = VL.Offers(entry, {
      query = state.itemQuery,
      name = itemLabel,
      match = ns.SearchLogic.match,
      sort = state.sort,
    })
    count:SetText(string.format(L["vendors.offerCount"], #offers, #entry.offers))
    wares:SetCount(#entry.offers)
    offerShown = #offers
    noOffer:SetShown(#offers == 0)
    offerList:SetShown(#offers > 0)
    offerList:SetData(offers)
  end

  function layoutDetail(width)
    if not selected then
      return 0
    end
    hero:ClearAllPoints()
    hero:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    local gap = Theme.space.lg
    local y = hero:fgLayout(width) + gap
    wares:ClearAllPoints()
    wares:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    return y + wares:fgLayout(width)
  end

  s:Add(split, { gap = Theme.space.lg })
  local emptyList = view.stack:Add(W.EmptyState(view.content, { text = "vendors.empty", icon = "search", compact = true }))

  -- Item names the client does not hold yet arrive later: repaint once they are there.
  local pending = false
  ns.On("GET_ITEM_INFO_RECEIVED", function()
    if pending or not container:IsVisible() or type(C_Timer) ~= "table" then
      return
    end
    pending = true
    C_Timer.After(0.5, function()
      pending = false
      if container:IsVisible() then
        refresh(false)
      end
    end)
  end)

  -- reload: read the data again (page opened, add-on switched on), else only the filter changed.
  function refresh(reload)
    if reload ~= false and (reload == true or not index) then
      index = VS.Index()
    end
    for _, o in ipairs(professionOptions) do
      if o.text then
        o.text = R.Name(o.value)
      end
    end
    professionDd.Refresh()
    kindDd.Refresh()
    factionButtons.Refresh()
    filters:Refresh()
    local offered = banner:Update(index == nil)
    hint:SetShown(index == nil and not offered)
    if index == nil then
      hint:SetText(VS.Hint())
    end
    shown = index
        and VL.Sort(
          VL.Filter(index.list, {
            index = index,
            slug = state.slug,
            kind = state.kind,
            faction = state.faction,
            query = state.query,
            match = ns.SearchLogic.match,
            zoneText = VS.ZoneName,
            itemName = VS.ItemName,
          }),
          VS.ZoneName
        )
      or {}
    local vendors, offers = VL.Count(shown)
    total:SetText(string.format(L["vendors.total"], vendors, offers))
    total:SetShown(index ~= nil)
    split:SetShown(vendors > 0)
    emptyList:SetAction(filters:IsFiltered() and W.EMPTY_RESET or nil, function()
      filters:Reset()
    end)
    emptyList:SetShown(index ~= nil and vendors == 0)
    -- The chosen vendor stays while the filters still list him, else the first one of the list.
    selected = nil
    for _, entry in ipairs(shown) do
      if entry.npc == state.npc then
        selected = entry
      end
    end
    selected = selected or shown[1]
    state.npc = selected and selected.npc or 0
    state.detail = state.detail and selected ~= nil
    list:SetData(shown)
    paintDetail()
    -- Narrow pages open on the list unless a vendor was asked for.
    syncing = true
    split:SetSelected(selected)
    split:ShowDetail(state.detail)
    syncing = false
    view:Layout()
  end

  -- Page link: the chosen vendor while his detail is open.
  function view:ShareState()
    return state.detail and selected and { tostring(selected.npc) } or {}
  end

  -- params[1] = profession slug (deep link, /fg vendors <profession>) or NPC id (vendors/<id>, VP.OpenVendor).
  -- Unknown slugs and ids are ignored (filters stay, no vendor is chosen).
  function view:Show(params)
    local arg = params and params[1]
    local want = tonumber(arg)
    if arg and R.PROFESSIONS[arg] then
      state.slug = arg
    elseif want and VS.Index() and VS.Index().byNpc[want] then
      state.slug, state.kind, state.faction, state.query = "all", "all", "all", ""
      search.edit:SetText("")
      state.npc, state.detail = want, true
    end
    refresh(true)
    if want then
      local at
      for i, entry in ipairs(shown) do
        if entry.npc == want then
          at = i
        end
      end
      if at then
        list:Reveal(at)
      else
        state.detail = false
        view:Layout()
      end
    end
  end
  ns.On("FG_UI_REFRESHED", function()
    if container:IsVisible() then
      refresh(false)
    end
  end)
  return view
end

ns.RegisterPage({
  id = "vendors",
  order = 450,
  group = "professions",
  title = "page.vendors",
  subtitle = "page.vendors.sub",
  icon = ns.ICONS.vendors,
  aliases = { "haendler", "händler", "vendors", "vendor" },
  crumbLabel = function(param)
    local entry = tonumber(param) and VS.Index(false)
    entry = entry and entry.byNpc[tonumber(param)]
    return R.PROFESSIONS[param] and R.Name(param) or entry and entry.name or param
  end,
  build = build,
})
