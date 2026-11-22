-- Class trainers per class and faction. The abilities per level live on the
-- level overview page, a hint line links there.
-- Data: ns.Data.Trainers. Logic: ns.RefLogic.
local _, ns = ...
local W, L, Theme, R, K = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit

ns.AddLocale("enUS", {
  ["trainers.intro"] = "Class trainers by class and faction",
  ["trainers.levelsLink"] = "Abilities per level: level overview",
  ["trainers.levelsLinkTip"] = "Opens the level overview for the chosen class.",
  ["trainers.kind.start"] = "Starting area",
  ["trainers.kind.town"] = "Town",
  ["trainers.kind.capital"] = "Capital",
  ["trainers.sub"] = "%s · %s · position %s",
  ["trainers.noPos"] = "no position",
  ["trainers.kind.own"] = "recorded by you",
  ["trainers.kind.pet"] = "Pet trainer",
  ["trainers.emptyTitle"] = "Not recorded in Forever yet",
  ["trainers.races"] = "Playable as: %s (website 2026-10-06, no trainer known)",
  ["trainers.emptyHint"] = "Visit a trainer in game and the addon remembers it.",
  ["trainers.mapTip"] = "Shows the zone on the map.",
  ["trainers.markerTip"] = "Sets a waypoint at this trainer.",
  ["trainers.stable"] = "Stable masters",
  ["trainers.kind.stable"] = "Stable master",
  ["trainers.search"] = "Search",
  ["trainers.searchPh"] = "Name or place",
  ["trainers.count"] = "%d of %d trainers",
  ["trainers.groupCount"] = "%d trainers",
  ["trainers.searchEmpty"] = "No trainer matches this search.",
  ["tour.trainers.title"] = "Class trainers",
  ["tour.trainers.intro.title"] = "Class trainers",
  ["tour.trainers.intro.text"] = "Find your class trainers (Enter: next, Esc: end)",
  ["tour.trainers.filters.title"] = "Class and faction",
  ["tour.trainers.filters.text"] = "Class and faction default to yours. Change them to look up others.",
  ["tour.trainers.levels.title"] = "Level overview",
  ["tour.trainers.levels.text"] = "This link opens the level overview for this class",
  ["tour.trainers.list.title"] = "List",
  ["tour.trainers.list.text"] = "Position in % of the zone map, Classic data, not verified for Forever",
})

ns.AddLocale("deDE", {
  ["trainers.intro"] = "Klassenlehrer nach Klasse und Fraktion",
  ["trainers.levelsLink"] = "Fähigkeiten je Stufe: Stufenübersicht",
  ["trainers.levelsLinkTip"] = "Öffnet die Stufenübersicht für die gewählte Klasse.",
  ["trainers.kind.start"] = "Startgebiet",
  ["trainers.kind.town"] = "Ort",
  ["trainers.kind.capital"] = "Hauptstadt",
  ["trainers.sub"] = "%s · %s · Position %s",
  ["trainers.noPos"] = "keine Position",
  ["trainers.kind.own"] = "selbst erfasst",
  ["trainers.kind.pet"] = "Begleiter-Lehrer",
  ["trainers.emptyTitle"] = "In Forever noch nicht erfasst",
  ["trainers.races"] = "Spielbar als: %s (Website 06.10.2026, kein Lehrer belegt)",
  ["trainers.emptyHint"] = "Besuche einen Lehrer im Spiel, das Addon merkt ihn sich.",
  ["trainers.mapTip"] = "Zeigt die Zone auf der Karte.",
  ["trainers.markerTip"] = "Setzt einen Wegpunkt am Lehrer.",
  ["trainers.stable"] = "Stallmeister",
  ["trainers.kind.stable"] = "Stallmeister",
  ["trainers.search"] = "Suchen",
  ["trainers.searchPh"] = "Name oder Ort",
  ["trainers.count"] = "%d von %d Lehrern",
  ["trainers.groupCount"] = "%d Lehrer",
  ["trainers.searchEmpty"] = "Kein Lehrer passt zu dieser Suche.",
  ["tour.trainers.title"] = "Klassenlehrer",
  ["tour.trainers.intro.title"] = "Klassenlehrer",
  ["tour.trainers.intro.text"] = "Finde deine Klassenlehrer (Enter: weiter, Esc: Ende)",
  ["tour.trainers.filters.title"] = "Klasse und Fraktion",
  ["tour.trainers.filters.text"] = "Klasse und Fraktion sind mit deinen Werten vorbelegt. Ändere sie, um andere nachzuschlagen.",
  ["tour.trainers.levels.title"] = "Stufenübersicht",
  ["tour.trainers.levels.text"] = "Dieser Link öffnet die Stufenübersicht der Klasse",
  ["tour.trainers.list.title"] = "Liste",
  ["tour.trainers.list.text"] = "Position in % der Zonenkarte, Classic-Daten, für Forever ungeprüft",
})

-- No public API returns a 2D portrait for an arbitrary creature ID unless
-- the NPC is actually rendered in the scene, so the circular class icon
-- stands in as the per-card visual identity on trainer cards instead.
local function classIcon(parent, size)
  local icon = parent:CreateTexture(nil, "ARTWORK")
  icon:SetSize(size, size)
  icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
  return icon
end

local function paintClassIcon(icon, class)
  local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if coords then
    icon:SetTexCoord(unpack(coords))
  end
  local hex = R.classColor(class)
  if hex then
    icon:SetVertexColor(Theme.rgb(hex))
  else
    icon:SetVertexColor(1, 1, 1)
  end
end

local ROW_HEIGHT = 52
local FIELD_W = 220
local FIELD_H = 46

local KIND_BADGE_COLOR =
  { start = "success", town = "textMuted", capital = "accent2", own = "accent2", pet = "warning", stable = "accent2" }

-- Shared by the card and list views so both always show the exact same
-- title/sub text for a given trainer entry. A pet trainer shows its role
-- where the others show the kind of place, and carries a note.
local function trainerTexts(t)
  local pos = K.Coord(t.x, t.y) or L["trainers.noPos"]
  local zone = R.zoneName(t.z) or t.p or "?"
  local title = ns.T(t.n) or t.id
  if t.nt then
    title = title .. "  " .. Theme.hexText("warning", "!")
  end
  local isPet = R.roleOf(t) == "pet"
  local kind = isPet and "pet" or t.k or "town"
  return {
    title = title,
    kind = kind,
    sub = string.format(L["trainers.sub"], zone, L["trainers.kind." .. kind], pos),
    note = isPet and ns.T(t.nt) or nil,
  }
end

-- UiMapID of a trainer's position: the recorded map of an own sighting, the
-- zone's map from the data, else the client map whose name matches the zone
-- (only a unique hit counts, a wrong pin is worse than none).
local function trainerMap(t)
  if t.m then
    return t.m
  end
  local zone = ns.Data.Trainers and ns.Data.Trainers.zones and ns.Data.Trainers.zones[t.z]
  if zone and zone.m then
    return zone.m
  end
  local index = ns.Waypoints.ZoneIndex()
  for _, name in ipairs({ zone and ns.T(zone) or t.p, zone and zone.de, zone and zone.en }) do
    local hits = name and ns.WaypointLogic.matchZones(index, name) or {}
    if #hits == 1 then
      return hits[1].id
    end
  end
  return nil
end

-- The place the Map and Waypoint buttons act on, resolved on click (the zone lookup is not
-- cheap and most rows are never clicked).
local function trainerPlace(t)
  return function()
    return {
      map = trainerMap(t),
      x = t.x,
      y = t.y,
      label = ns.T(t.n) or t.id,
      zone = R.zoneName(t.z) or t.p or "?",
    }
  end
end

-- "#rrggbb" of the class color for the left bar of a row.
local function classBar(class)
  local hex = K.ClassColorHex(class)
  return hex and (hex:sub(1, 1) == "#" and hex or "#" .. hex) or "accent2"
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = {
    class = K.PlayerClass() or "WARRIOR",
    faction = K.PlayerFaction() or "A",
    view = ns.db.settings.trainersView or "list",
    query = "",
  }
  local refresh

  ns.AddIntro(view, "trainers.intro")
  local basis = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted" })

  local filters = CreateFrame("Frame", nil, view.content)
  K.Anchor("FG.Trainers.Filters", filters)
  local classButtons = K.ClassButtons(filters, {
    get = function()
      return state.class
    end,
    set = function(v)
      state.class, state.npc = v, nil
      refresh()
    end,
  })
  local factionButtons = K.FactionButtons(filters, {
    withAll = true,
    get = function()
      return state.faction
    end,
    set = function(v)
      state.faction, state.npc = v, nil
      refresh()
    end,
  })
  function filters:fgGridLayout(width)
    return K.StackLayout(filters, { classButtons, factionButtons }, width, 12)
  end
  s:Add(filters, { gap = Theme.space.sm })

  -- Search by name or place, like the profession trainers (Modules/TrainerSearchLogic.lua).
  local searchBox = CreateFrame("Frame", nil, view.content)
  K.Anchor("FG.Trainers.Search", searchBox)
  W.Text(searchBox, { key = "trainers.search", role = "ui" }):SetPoint("TOPLEFT")
  local search = W.EditBox(searchBox, {
    placeholder = "trainers.searchPh",
    clear = true,
    onChange = function(text)
      state.query, state.npc = text, nil
      refresh()
    end,
  })
  search:SetPoint("TOPLEFT", 0, -18)
  search:SetWidth(FIELD_W)
  s:Add(searchBox, { height = FIELD_H, width = FIELD_W, gap = Theme.space.xs })
  local counter = ns.AddParagraph(view, nil, { role = "small", gap = Theme.space.md })
  K.Anchor("FG.Trainers.Count", counter)

  -- Small link line: the abilities per level are on the level overview page.
  local levelsLink = CreateFrame("Button", nil, view.content)
  K.Anchor("FG.Trainers.LevelsLink", levelsLink)
  levelsLink.label = W.Text(levelsLink, { key = "trainers.levelsLink", role = "micro", color = "accent2", wrap = true })
  levelsLink.label:SetPoint("TOPLEFT")
  levelsLink:SetScript("OnEnter", function()
    W.SetColor(levelsLink.label, "accent")
    ns.ShowTooltip(levelsLink, L["page.levels"], L["trainers.levelsLinkTip"])
  end)
  levelsLink:SetScript("OnLeave", function()
    W.SetColor(levelsLink.label, "accent2")
    ns.HideTooltip()
  end)
  levelsLink:SetScript(
    "OnClick",
    ns.Wrap("trainers-levels-link", function()
      ns.Router:navigate("levels/" .. state.class)
    end)
  )
  ns.Focus.register(levelsLink, function(self)
    self:Click()
  end)
  function levelsLink:fgGridLayout(width)
    levelsLink.label:SetWidth(width)
    local h = math.ceil(levelsLink.label:GetStringHeight())
    levelsLink:SetHeight(h)
    return h
  end
  s:Add(levelsLink, { gap = Theme.space.md })

  -- Shown while pet trainers are in the list: in the list view they are told apart by the sub line only.
  local petHint = ns.AddParagraph(view, nil, { role = "micro", color = "textSecondary", gap = Theme.space.md })
  K.Anchor("FG.Trainers.PetHint", petHint)

  local viewToggle = K.ViewToggle(view.content, {
    get = function()
      return state.view
    end,
    set = function(v)
      state.view = v
      ns.Store.set("settings.trainersView", v)
      refresh()
    end,
  })
  K.Anchor("FG.Trainers.ViewToggle", viewToggle)
  s:Add(viewToggle, { height = 22, gap = Theme.space.md })

  -- Boxed row: class-colored bar and class icon, name, zone line and the confidence word; the map, waypoint
  -- and share icons are the trailing widget of the row.
  local function bindTrainerRow(t)
    local tx = trainerTexts(t)
    return {
      title = tx.title,
      sub = tx.sub,
      meta = L["kit.conf." .. tostring(t.cf or 2)],
      leftBar = classBar(state.class),
      iconFrame = { spec = K.ClassIconSpec(state.class) },
    }
  end

  local function wireTrainerRow(row, t)
    if not row.bar then
      row.bar = W.MapActionButtons(row, { mapTip = "trainers.mapTip", markerTip = "trainers.markerTip", share = true })
    end
    row.bar:SetPlace(t.x ~= nil and t.y ~= nil and trainerPlace(t) or nil)
    row.bar:SetShare(t.npc and ("trainers/" .. state.class .. "/" .. t.npc) or nil)
    row.trailing = row.bar
  end

  local function paintTrainerCard(card, t)
    paintClassIcon(card.icon, state.class)
    local tx = trainerTexts(t)
    card.title:SetText(tx.title)
    card.badge:SetKey("trainers.kind." .. tx.kind, KIND_BADGE_COLOR[tx.kind] or "textMuted")
    card.sub:SetText(tx.sub)
    card.note:SetText(tx.note or "")
    card.dot:SetCf(t.cf)
  end

  local function makeTrainerCard(parent)
    local card = W.Card(parent, {})
    card.icon = classIcon(card, 36)
    card.icon:SetPoint("TOPLEFT", 12, -12)
    card.title = W.Text(card, { role = "ui", wrap = true })
    card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -4)
    card.title:SetPoint("RIGHT", -24, 0)
    card.badge = W.Badge(card, "trainers.kind.town", "textMuted")
    card.badge:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -12)
    card.sub = W.Meta(card, { wrap = true })
    card.sub:SetPoint("TOPLEFT", card.badge, "BOTTOMLEFT", 0, -6)
    card.sub:SetPoint("RIGHT", -12, 0)
    card.note = W.Text(card, { role = "micro", color = "textMuted", wrap = true })
    card.note:SetPoint("TOPLEFT", card.sub, "BOTTOMLEFT", 0, -4)
    card.note:SetPoint("RIGHT", -12, 0)
    card.dot = K.ConfidenceDot(card, 2)
    card.dot:SetPoint("TOPRIGHT", -10, -10)
    -- No-op activate, matches the old K.NewList rows: Tab still reaches
    -- every card even though there is nothing to click.
    ns.Focus.register(card, function() end)
    return card
  end

  -- Shown instead of a bare list when a class and faction has no trainer in
  -- the data and none recorded by the player. The Stack sizes it through
  -- fgGridLayout because the wrapped text decides the height.
  local function makeEmptyCard(parent)
    local card = W.Card(parent, {})
    card.body = W.Text(card, { role = "ui", color = "textSecondary", wrap = true })
    card.body:SetPoint("TOPLEFT", 12, -12)
    function card:fgGridLayout(width)
      card.body:SetWidth(math.max(1, width - 24))
      local h = card.body:GetStringHeight() + 24
      card:SetHeight(h)
      return h
    end
    function card:Paint(group)
      local lines = { Theme.hexText("accent2", L["trainers.emptyTitle"]) }
      for _, g in ipairs(group.gaps) do
        lines[#lines + 1] = ns.T(g.t) or ""
      end
      if #group.races > 0 then
        lines[#lines + 1] = string.format(L["trainers.races"], table.concat(group.races, ", "))
      end
      lines[#lines + 1] = L["trainers.emptyHint"]
      card.body:SetText(table.concat(lines, "\n\n"))
    end
    return card
  end

  -- One panel per faction group: a heading (only when both factions show), the
  -- list and card views, and the empty-state card. Panel 2 is only used for "both", panel 3 for the
  -- hunter's stable masters.
  local panels = {}
  local MIN_ROWS = 3
  local MAX_STABLE_ROWS = 5

  -- The lists share the page height left below the header items; the page
  -- itself only scrolls when even MIN_ROWS rows do not fit.
  local function listHeight()
    local y = s.pad
    for _, entry in ipairs(s.items) do
      if entry.item == panels[1].heading then
        break
      end
      if entry.item:IsShown() then
        y = y + entry.item:GetHeight() + (entry.opts.gap or 10)
      end
    end
    local shown, overhead, fixed = 0, 14, 0
    for _, p in ipairs(panels) do
      if p.list:IsShown() then
        if p.rows then
          -- The stable masters keep a short list of their own; the trainers share the rest.
          fixed = fixed + p.rows * K.scaledHeight(ROW_HEIGHT) + 14 + p.heading:GetHeight() + 6
        else
          shown = shown + 1
          if p.heading:IsShown() then
            overhead = 14 + p.heading:GetHeight() + 6
          end
        end
      end
    end
    shown = math.max(shown, 1)
    local free = view.area:GetHeight() - y - s.pad - fixed - shown * overhead
    return math.max(K.scaledHeight(ROW_HEIGHT) * MIN_ROWS, math.floor(free / shown))
  end

  for i = 1, 3 do
    local p = {}
    p.heading = K.GroupHeader(view.content, {
      onToggle = function()
        refresh()
      end,
    })
    s:Add(p.heading, { gap = Theme.space.sm })
    p.list = K.NewList(view.content, {
      look = "boxed",
      rowHeight = ROW_HEIGHT,
      bind = bindTrainerRow,
      onBindRow = wireTrainerRow,
    })
    function p.list:fgGridLayout()
      local h = p.rows and p.rows * K.scaledHeight(ROW_HEIGHT) or listHeight()
      self:SetHeight(h)
      return h
    end
    s:Add(p.list, { gap = Theme.space.lg })
    p.grid = K.GridPool(view.content, 136, makeTrainerCard)
    s:Add(p.grid, { gap = Theme.space.lg })
    p.empty = makeEmptyCard(view.content)
    s:Add(p.empty, { gap = Theme.space.lg })
    K.Anchor("FG.Trainers.Empty" .. i, p.empty)
    panels[i] = p
  end
  K.Anchor("FG.Trainers.ListView", panels[1].list)
  K.Anchor("FG.Trainers.List", panels[1].grid)

  local note = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary" })

  -- Fills the panels from the faction groups; groups = {} hides all of them.
  -- headings: name the faction above each group (always while both factions are asked for).
  local function paintPanels(groups, headings)
    local asList = state.view == "list"
    for i, p in ipairs(panels) do
      local g = groups[i]
      p.rows = g and g.stable and math.min(#g.trainers, MAX_STABLE_ROWS) or nil
      p.heading:SetShown(g ~= nil and (headings == true or g.stable == true))
      if g then
        p.heading:Set({
          id = "trainers." .. tostring(g.faction),
          title = g.stable and L["trainers.stable"] or L["kit.faction." .. g.faction],
          counter = not g.empty and string.format(L["trainers.groupCount"], #g.trainers) or nil,
          onToggle = p.heading.onToggle,
        })
      end
      -- A closed group header hides its rows; without a header the rows always show.
      local open = not p.heading:IsShown() or p.heading:IsOpen()
      p.list:SetShown(g ~= nil and not g.empty and asList and open)
      p.grid:SetShown(g ~= nil and not g.empty and not asList and open)
      p.empty:SetShown(g ~= nil and g.empty)
      if g then
        p.list:SetData(g.trainers)
        p.grid:Sync(g.trainers, paintTrainerCard)
        if g.empty then
          p.empty:Paint(g)
        end
      end
    end
  end

  -- The faction groups reduced to the trainers that match the search; a group without a hit drops out.
  local function narrow(groups)
    local out = {}
    for _, g in ipairs(groups) do
      local hits = ns.TrainerSearchLogic.FilterTrainers(g.trainers, state.query, ns.Data.Trainers.zones)
      if #hits > 0 then
        local copy = {}
        for k, v in pairs(g) do
          copy[k] = v
        end
        copy.trainers, copy.pets = hits, {}
        for _, t in ipairs(hits) do
          if R.roleOf(t) == "pet" then
            copy.pets[#copy.pets + 1] = t
          end
        end
        out[#out + 1] = copy
      end
    end
    return out
  end

  function refresh()
    if not K.HasData("Trainers") then
      paintPanels({})
      petHint:Hide()
      counter:Hide()
      note:SetText(L["kit.noData"])
      note:Show()
      view:Layout()
      return
    end
    local faction = state.faction ~= "all" and state.faction or nil
    basis:SetText(ns.T(ns.Data.Trainers.basis) or "")
    local groups = R.TrainerGroups(state.class, faction)
    local headings = #groups > 1
    local total, matched = 0, 0
    for _, g in ipairs(groups) do
      total = total + #g.trainers
    end
    if ns.TrainerSearchLogic.HasQuery(state.query) then
      groups = narrow(groups)
    end
    for _, g in ipairs(groups) do
      matched = matched + (g.empty and 0 or #g.trainers)
    end
    -- Stable masters of the hunter get their own group after the faction groups. They are not part
    -- of the trainer count.
    local stable
    if state.class == "HUNTER" then
      local list = ns.TrainerSearchLogic.FilterTrainers(R.StableMasters(faction), state.query)
      if #list > 0 then
        stable = { faction = "S", stable = true, empty = false, trainers = list, pets = {}, gaps = {}, races = {} }
        groups[#groups + 1] = stable
      end
    end
    paintPanels(groups, headings)
    local hasPets = false
    for _, g in ipairs(groups) do
      hasPets = hasPets or #g.pets > 0
    end
    petHint:SetText(ns.T(ns.TrainerRoles.NOTE_PET) or "")
    petHint:SetShown(hasPets)
    counter:SetText(string.format(L["trainers.count"], matched, total))
    counter:SetShown(total > 0)
    if total > 0 and matched == 0 and not stable then
      note:SetText(L["trainers.searchEmpty"])
      note:Show()
    else
      note:Hide()
    end
    classButtons.Refresh()
    factionButtons.Refresh()
    viewToggle.Refresh()
    view:Layout()
  end

  -- Page link: the class.
  function view:ShareState()
    return { state.class, state.npc and tostring(state.npc) or nil }
  end

  -- params: class, then the NPC id of one trainer (the list is searched for his name).
  function view:Show(params)
    local class = params and params[1]
    if class and R.className(class) ~= class then
      state.class = class
    end
    local npc = params and tonumber(params[2])
    state.npc = nil
    if npc then
      for _, t in ipairs(ns.Data.Trainers.trainers or {}) do
        if t.npc == npc and t.c == state.class then
          state.faction, state.query = "all", ns.T(t.n) or ""
          search.edit:SetText(state.query)
          state.npc = npc
          break
        end
      end
    end
    refresh()
  end
  return view
end

ns.RegisterPage({
  id = "trainers",
  order = 320,
  group = "learn",
  title = "page.trainers",
  icon = ns.ICONS.trainers,
  aliases = { "lehrer", "trainer", "trainers" },
  crumbLabel = function(param)
    return R.className(param)
  end,
  build = build,
})
