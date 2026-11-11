-- Vendors: the NPCs that sell goods for the professions (recipes, materials, cooking ingredients, fishing gear,
-- food, bandages, poisons, tools) with the zone, the position and what they sell. Follows the layout of the
-- profession trainers page (ProfessionTrainersPage.lua): filters on top, a list below, Map and Waypoint buttons,
-- a tooltip with the full offer. Data: VendorSource (load-on-demand add-on), logic: VendorLogic.
local _, ns = ...
local W, L, Theme, K = ns.W, ns.L, ns.Theme, ns.PageKit
local R, VL, VS = ns.ProfessionRouteLogic, ns.VendorLogic, ns.VendorSource

ns.AddLocale("enUS", {
  ["page.vendors"] = "Vendors",
  ["vendors.intro"] = "NPCs that sell recipes, materials, fishing gear and food, by profession, with zone, position and offer",
  ["vendors.source"] = "The offers are Classic values and are not verified in Forever yet. Vendors that only exist in Forever are missing.",
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
  ["vendors.search"] = "Search",
  ["vendors.searchPh"] = "Vendor, zone or item",
  ["vendors.placeLine"] = "%s, %s",
  ["vendors.kindsLine"] = "%s",
  ["vendors.sells"] = "Sells: %s",
  ["vendors.sellsMore"] = "%s and %d more",
  ["vendors.pos"] = "Position %s",
  ["vendors.npc"] = "NPC ID %d",
  ["vendors.total"] = "Vendors: %d, offers: %d",
  ["vendors.empty"] = "No vendors for this selection.",
  ["vendors.mapTip"] = "Show the vendor's zone on the map",
  ["vendors.markerTip"] = "Set a waypoint at the vendor",
  ["vendors.tipItem"] = "%s: %s",
  ["vendors.tipMore"] = "and %d more",
})

ns.AddLocale("deDE", {
  ["page.vendors"] = "Händler",
  ["vendors.intro"] = "NPCs, die Rezepte, Material, Angelzubehör und Nahrung verkaufen, nach Beruf, mit Zone, Position und Angebot",
  ["vendors.source"] = "Die Angebote sind Classic-Werte und in Forever noch nicht geprüft. Händler, die es nur in Forever gibt, fehlen.",
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
  ["vendors.kind.d"] = "Nahrung",
  ["vendors.kind.b"] = "Verbände",
  ["vendors.kind.p"] = "Gifte",
  ["vendors.kind.t"] = "Berufswerkzeug",
  ["vendors.search"] = "Suchen",
  ["vendors.searchPh"] = "Händler, Zone oder Gegenstand",
  ["vendors.placeLine"] = "%s, %s",
  ["vendors.kindsLine"] = "%s",
  ["vendors.sells"] = "Verkauft: %s",
  ["vendors.sellsMore"] = "%s und %d weitere",
  ["vendors.pos"] = "Position %s",
  ["vendors.npc"] = "NPC-ID %d",
  ["vendors.total"] = "Händler: %d, Angebote: %d",
  ["vendors.empty"] = "Keine Händler für diese Auswahl.",
  ["vendors.mapTip"] = "Zone des Händlers auf der Karte zeigen",
  ["vendors.markerTip"] = "Wegpunkt am Händler setzen",
  ["vendors.tipItem"] = "%s: %s",
  ["vendors.tipMore"] = "und %d weitere",
})

-- Four text lines: name, kinds, faction and place, offer. The buttons sit top right, the first two lines end
-- before them.
local ROW_HEIGHT = 76
local ROW_ACTION_TOP = 5
local MIN_ROWS = 3
local CONTROL_W = 200
local FIELD_W = 240
local CONTROL_GAP = 12
local CONTROL_H = 46
-- Items named in the offer line and in the tooltip.
local EXCERPT = 5
local TIP_ITEMS = 24

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

-- "Flour 25c, Salt 10c, ... and 7 more": the first EXCERPT offers.
local function offerText(entry)
  local names, ids = {}, {}
  for i, offer in ipairs(entry.offers) do
    if i > EXCERPT then
      break
    end
    ids[#ids + 1] = offer.id
    names[#names + 1] = itemLabel(offer.id)
  end
  requestNames(ids)
  local text = table.concat(names, ", ")
  if #entry.offers > EXCERPT then
    text = string.format(L["vendors.sellsMore"], text, #entry.offers - EXCERPT)
  end
  return string.format(L["vendors.sells"], text)
end

-- Tooltip of a row: the NPC id and the offers with their prices.
local function showRowTip(row)
  local e = row.entry
  if not e then
    return
  end
  local lines = { string.format(L["vendors.npc"], e.npc) }
  local ids = {}
  for i, offer in ipairs(e.offers) do
    if i > TIP_ITEMS then
      lines[#lines + 1] = string.format(L["vendors.tipMore"], #e.offers - TIP_ITEMS)
      break
    end
    ids[#ids + 1] = offer.id
    local price = VL.PriceText(offer, VS.Money)
    local note = ""
    if VL.Limited(offer.flags) then
      note = note .. " (" .. L["vendor.limited"] .. ")"
    end
    if VL.Restricted(offer.flags) then
      note = note .. " (" .. L["vendor.restricted"] .. ")"
    end
    lines[#lines + 1] = string.format(L["vendors.tipItem"], itemLabel(offer.id), price) .. note
  end
  requestNames(ids)
  ns.ShowTooltip(row, e.name, nil, { lines = lines })
end

local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetClipsChildren(true)
  row:EnableMouse(true)
  row:SetScript("OnEnter", showRowTip)
  row:SetScript("OnLeave", ns.HideTooltip)
  row.actions = W.MapActionButtons(row, { mapTip = "vendors.mapTip", markerTip = "vendors.markerTip" })
  K.RowHover(row, { extraFrames = { row.actions.map, row.actions.marker } })
  row.actions:SetPoint("TOPRIGHT", -8, -ROW_ACTION_TOP)
  row.title = W.Text(row, { role = "ui" })
  row.kinds = W.Text(row, { role = "micro", color = "textSecondary" })
  row.place = W.Text(row, { role = "micro", color = "textSecondary" })
  row.offers = W.Text(row, { role = "micro", color = "textMuted" })
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  ns.Bind(row, function()
    row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)
  return row
end

local function bindRow(row, entry)
  row.entry = entry
  row.actions:SetPlace(function()
    return VL.Place(entry, VS.ZoneName(entry))
  end)
  local function anchor(fs, rel, y, clear)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", rel, rel == row and "TOPLEFT" or "BOTTOMLEFT", rel == row and 8 or 0, y)
    if clear then
      fs:SetPoint("RIGHT", row.actions, "LEFT", -8, 0)
    else
      fs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    end
  end
  anchor(row.title, row, -5, true)
  anchor(row.kinds, row.title, -2, true)
  anchor(row.place, row.kinds, -2, false)
  anchor(row.offers, row.place, -2, false)
  row.title:SetText(entry.name)
  row.kinds:SetText(string.format(L["vendors.kindsLine"], kindsText(entry)))
  local faction = L[FACTION_KEY[entry.faction]]
  local coord = K.Coord(entry.x, entry.y)
  row.place:SetText(
    string.format(L["vendors.placeLine"], faction, VS.ZoneName(entry) or "?")
      .. (coord and (" · " .. string.format(L["vendors.pos"], coord)) or "")
  )
  row.offers:SetText(offerText(entry))
  row.paintHover()
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = { slug = "all", kind = "all", faction = K.PlayerFaction() or "all", query = "" }
  local index
  local refresh

  ns.AddParagraph(view, "vendors.intro")
  ns.AddParagraph(view, "vendors.source", { role = "micro", color = "textMuted", gap = 8 })
  local hint = ns.AddParagraph(view, nil, { role = "ui", color = "warning", gap = 12 })
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
  s:Add(banner, { gap = 12 })

  local professionOptions = { { value = "all", key = "vendors.professionAll" } }
  for _, slug in ipairs(R.SLUGS) do
    professionOptions[#professionOptions + 1] = { value = slug, text = R.Name(slug) }
  end
  local kindOptions = { { value = "all", key = "vendors.kindAll" } }
  for _, kind in ipairs(VL.KINDS) do
    kindOptions[#kindOptions + 1] = { value = kind, key = "vendors.kind." .. kind }
  end
  local controls = CreateFrame("Frame", nil, view.content)
  local professionDd = W.Dropdown(controls, {
    key = "vendors.profession",
    width = CONTROL_W,
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
  professionDd:SetWidth(CONTROL_W)
  local kindDd = W.Dropdown(controls, {
    key = "vendors.kind",
    width = CONTROL_W,
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
  kindDd:SetWidth(CONTROL_W)
  local searchBox = CreateFrame("Frame", nil, controls)
  searchBox:SetSize(FIELD_W, CONTROL_H)
  W.Text(searchBox, { key = "vendors.search", role = "ui" }):SetPoint("TOPLEFT")
  local search = W.EditBox(searchBox, {
    placeholder = "vendors.searchPh",
    clear = true,
    onChange = function(text)
      state.query = text
      refresh()
    end,
  })
  search:SetPoint("TOPLEFT", 0, -18)
  search:SetWidth(FIELD_W)
  function controls:fgGridLayout(width)
    local x, y = 0, 0
    for _, item in ipairs({ professionDd, kindDd, searchBox }) do
      local w = item:GetWidth()
      if x > 0 and x + w > width then
        x, y = 0, y + CONTROL_H + 8
      end
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
      x = x + w + CONTROL_GAP
    end
    local h = y + CONTROL_H
    self:SetHeight(h)
    return h
  end
  s:Add(controls, { gap = 10 })
  K.Anchor("FG.Vendors.Controls", controls)

  local factionButtons = K.FactionButtons(view.content, {
    withAll = true,
    get = function()
      return state.faction
    end,
    set = function(v)
      state.faction = v
      refresh()
    end,
  })
  s:Add(factionButtons, { gap = 10 })

  local total = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = 6 })

  local list = W.ScrollList(view.content, {
    rowHeight = K.scaledHeight(ROW_HEIGHT),
    createRow = createRow,
    bindRow = bindRow,
  })
  -- The list takes the page height left below the controls, at least MIN_ROWS rows.
  function list:fgGridLayout(_, room)
    local free = room and (room.viewHeight - room.top - room.pad) or 0
    local h = math.max(K.scaledHeight(ROW_HEIGHT) * MIN_ROWS, math.floor(free))
    self:SetHeight(h)
    return h
  end
  s:Add(list, { gap = 14 })
  K.Anchor("FG.Vendors.List", list)
  local empty = ns.AddParagraph(view, "vendors.empty", { role = "ui" })

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
    local offered = banner:Update(index == nil)
    hint:SetShown(index == nil and not offered)
    if index == nil then
      hint:SetText(VS.Hint())
    end
    local shown = index
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
    list:SetShown(vendors > 0)
    empty:SetShown(index ~= nil and vendors == 0)
    list:SetData(shown)
    view:Layout()
  end

  -- params[1] = profession slug (deep link, /fg vendors <profession>), unknown ones are ignored.
  function view:Show(params)
    local slug = params and params[1]
    if slug and R.PROFESSIONS[slug] then
      state.slug = slug
    end
    refresh(true)
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
  icon = ns.ICONS.vendors,
  aliases = { "haendler", "händler", "vendors", "vendor" },
  crumbLabel = function(param)
    return R.PROFESSIONS[param] and R.Name(param) or param
  end,
  build = build,
})
