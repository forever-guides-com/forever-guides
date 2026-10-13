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
  ["trainers.mapTip"] = "Show the trainer's zone on the map",
  ["trainers.markerTip"] = "Set a waypoint at the trainer",
  ["tour.trainers.title"] = "Class trainers",
  ["tour.trainers.intro.title"] = "Class trainers",
  ["tour.trainers.intro.text"] = "Find your class trainers (Enter: next, Esc: end)",
  ["tour.trainers.filters.title"] = "Class and faction",
  ["tour.trainers.filters.text"] = "Class and faction default to you, change them to look up others",
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
  ["trainers.mapTip"] = "Lehrerzone auf der Karte zeigen",
  ["trainers.markerTip"] = "Wegpunkt am Lehrer setzen",
  ["tour.trainers.title"] = "Klassenlehrer",
  ["tour.trainers.intro.title"] = "Klassenlehrer",
  ["tour.trainers.intro.text"] = "Finde deine Klassenlehrer (Enter: weiter, Esc: Ende)",
  ["tour.trainers.filters.title"] = "Klasse und Fraktion",
  ["tour.trainers.filters.text"] = "Klasse und Fraktion sind vorbelegt, ändere sie zum Nachschlagen",
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

-- Row height and the top inset of the button pair: the buttons end above the confidence line
-- at the bottom right, so the two never touch.
local ROW_HEIGHT = 48
local ROW_ACTION_TOP = 5

local KIND_BADGE_COLOR =
  { start = "success", town = "textMuted", capital = "accent2", own = "accent2", pet = "warning" }

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

-- One list row: class icon, title and sub line on the left, the Map and
-- Waypoint buttons top right, the confidence under them. The title and sub
-- anchor to those, so nothing overlaps at any width.
local function createTrainerRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetClipsChildren(true)
  row.icon = classIcon(row, 20)
  row.icon:SetPoint("TOPLEFT", 8, -8)
  row.actions = W.MapActionButtons(row, { mapTip = "trainers.mapTip", markerTip = "trainers.markerTip" })
  row.actions:SetPoint("TOPRIGHT", -8, -ROW_ACTION_TOP)
  row.conf = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
  row.conf:SetPoint("BOTTOMRIGHT", -8, 5)
  row.title = W.Text(row, { role = "ui" })
  row.sub = W.Text(row, { role = "micro", color = "textSecondary" })
  row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
  row.sub:SetPoint("RIGHT", row.conf, "LEFT", -8, 0)
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  ns.Bind(row, function()
    row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)
  return row
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = {
    class = K.PlayerClass() or "WARRIOR",
    faction = K.PlayerFaction() or "A",
    view = ns.db.settings.trainersView or "list",
  }
  local refresh

  ns.AddParagraph(view, "trainers.intro")
  local basis = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted" })

  local filters = CreateFrame("Frame", nil, view.content)
  K.Anchor("FG.Trainers.Filters", filters)
  local classButtons = K.ClassButtons(filters, {
    get = function()
      return state.class
    end,
    set = function(v)
      state.class = v
      refresh()
    end,
  })
  local factionButtons = K.FactionButtons(filters, {
    withAll = true,
    get = function()
      return state.faction
    end,
    set = function(v)
      state.faction = v
      refresh()
    end,
  })
  function filters:fgGridLayout(width)
    return K.StackLayout(filters, { classButtons, factionButtons }, width, 12)
  end
  s:Add(filters, { gap = 8 })

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
  s:Add(levelsLink, { gap = 10 })

  -- Shown while pet trainers are in the list: in the list view they are told apart by the sub line only.
  local petHint = ns.AddParagraph(view, nil, { role = "micro", color = "textSecondary", gap = 10 })
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
  s:Add(viewToggle, { height = 22, gap = 10 })

  local function bindTrainerRow(row, t)
    local tx = trainerTexts(t)
    paintClassIcon(row.icon, state.class)
    local hasPos = t.x ~= nil and t.y ~= nil
    row.actions:SetPlace(hasPos and trainerPlace(t) or nil)
    row.title:ClearAllPoints()
    row.title:SetPoint("TOPLEFT", 36, -5)
    if hasPos then
      row.title:SetPoint("RIGHT", row.actions, "LEFT", -8, 0)
    else
      row.title:SetPoint("RIGHT", -8, 0)
    end
    row.title:SetText(tx.title)
    row.sub:SetText(tx.sub)
    row.conf:SetText(L["kit.conf." .. tostring(t.cf or 2)])
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
    card.sub = W.Text(card, { role = "micro", color = "textSecondary", wrap = true })
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
  -- list and card views, and the empty-state card. Panel 2 is only used for "both".
  local panels = {}
  local MIN_ROWS = 3

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
    local shown, overhead = 0, 14
    for _, p in ipairs(panels) do
      if p.list:IsShown() then
        shown = shown + 1
        if p.heading:IsShown() then
          overhead = 14 + p.heading:GetHeight() + 6
        end
      end
    end
    shown = math.max(shown, 1)
    local free = view.area:GetHeight() - y - s.pad - shown * overhead
    return math.max(K.scaledHeight(ROW_HEIGHT) * MIN_ROWS, math.floor(free / shown))
  end

  for i = 1, 2 do
    local p = {}
    p.heading = W.Text(view.content, { role = "h3", family = "heading", color = "accent2" })
    s:Add(p.heading, { gap = 6 })
    p.list = W.ScrollList(view.content, {
      rowHeight = K.scaledHeight(ROW_HEIGHT),
      createRow = createTrainerRow,
      bindRow = bindTrainerRow,
    })
    function p.list:fgGridLayout()
      local h = listHeight()
      self:SetHeight(h)
      return h
    end
    s:Add(p.list, { gap = 14 })
    p.grid = K.GridPool(view.content, 136, makeTrainerCard)
    s:Add(p.grid, { gap = 14 })
    p.empty = makeEmptyCard(view.content)
    s:Add(p.empty, { gap = 14 })
    K.Anchor("FG.Trainers.Empty" .. i, p.empty)
    panels[i] = p
  end
  K.Anchor("FG.Trainers.ListView", panels[1].list)
  K.Anchor("FG.Trainers.List", panels[1].grid)

  local note = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary" })

  -- Fills the panels from the faction groups; groups = {} hides all of them.
  local function paintPanels(groups)
    local asList = state.view == "list"
    for i, p in ipairs(panels) do
      local g = groups[i]
      p.heading:SetShown(g ~= nil and #groups > 1)
      p.list:SetShown(g ~= nil and not g.empty and asList)
      p.grid:SetShown(g ~= nil and not g.empty and not asList)
      p.empty:SetShown(g ~= nil and g.empty)
      if g then
        p.heading:SetText(L["kit.faction." .. g.faction])
        p.list:SetData(g.trainers)
        p.grid:Sync(g.trainers, paintTrainerCard)
        if g.empty then
          p.empty:Paint(g)
        end
      end
    end
  end

  function refresh()
    if not K.HasData("Trainers") then
      paintPanels({})
      petHint:Hide()
      note:SetText(L["kit.noData"])
      note:Show()
      view:Layout()
      return
    end
    local faction = state.faction ~= "all" and state.faction or nil
    basis:SetText(ns.T(ns.Data.Trainers.basis) or "")
    local groups = R.TrainerGroups(state.class, faction)
    paintPanels(groups)
    local hasPets = false
    for _, g in ipairs(groups) do
      hasPets = hasPets or #g.pets > 0
    end
    petHint:SetText(ns.T(ns.TrainerRoles.NOTE_PET) or "")
    petHint:SetShown(hasPets)
    note:Hide()
    classButtons.Refresh()
    factionButtons.Refresh()
    viewToggle.Refresh()
    view:Layout()
  end

  function view:Show(params)
    local class = params and params[1]
    if class and R.className(class) ~= class then
      state.class = class
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
