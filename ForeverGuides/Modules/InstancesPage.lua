-- Dungeons & raids in two levels: without a slug the card grid with its filter bar (Modules/InstanceCards.lua),
-- with a slug the instance: back button, header band with the loading screen and the tabs (every section in a
-- column below a page width of 760). Data: ns.Data.Instances. The header and the row lists are in
-- Modules/InstanceView.lua, the items in Modules/InstanceItemsView.lua.
local _, ns = ...
local W, L, Theme, R, K, IV = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit, ns.InstanceView
local DA = ns.InstanceDataAccess

ns.AddLocale("enUS", {
  ["instances.intro"] = "Dungeons and raids: levels, entrance, bosses, quests",
  ["instances.search"] = "Filter by instance or boss name",
  ["instances.unknown"] = "?",
  ["instances.sort.label"] = "Sort by",
  ["instances.sort.name"] = "Name",
  ["instances.sort.level"] = "Level",
  ["instances.back"] = "All instances",
  ["instances.back.tip"] = "Back to the overview of all instances (Backspace).",
  ["instances.status.announced"] = "announced",
  ["instances.dtab.info"] = "Info",
  ["instances.dtab.bosses"] = "Bosses",
  ["instances.dtab.quests"] = "Quests",
  ["instances.dtab.map"] = "Map",
  ["instances.dtab.access"] = "Access",
  ["instances.info.level"] = "Level: %s",
  ["instances.info.group"] = "Group size: %s",
  ["instances.info.faction"] = "Faction: %s",
  ["instances.info.location"] = "Location: %s",
  ["instances.info.status"] = "Status: %s",
  ["instances.info.entrance"] = "Entrance: map %s, position %s",
  ["instances.info.entranceNone"] = "No entrance position in the data.",
  ["instances.info.counts"] = "%d boss(es), %d quest(s) in the data.",
  ["instances.info.noId"] = "This instance has no game instance ID in the data.",
  ["instances.bosses.none"] = "No bosses recorded for this instance yet.",
  ["instances.bosses.optional"] = "optional",
  ["instances.bosses.heroic"] = "heroic",
  ["instances.bosses.count.one"] = "1 boss",
  ["instances.bosses.count.other"] = "%d bosses",
  ["instances.bosses.names"] = "Some boss names exist in one language only.",
  ["instances.quests.none"] = "No quests recorded for this instance. That does not mean it has none.",
  ["instances.quests.noneDirect"] = "No instance quests known.",
  ["instances.quests.noneFaction"] = "No quests in the data for this faction.",
  ["instances.quest.head"] = "%s (quest level %s, from level %s)",
  ["instances.quest.start"] = "Starts at: %s",
  ["instances.quest.startIn"] = "in %s",
  ["instances.quest.end"] = "Hand in: %s",
  ["instances.quest.pre"] = "Requires first: %s",
  ["instances.quest.next"] = "Next: %s",
  ["instances.quest.reward"] = "Reward: %s",
  ["instances.quest.choice"] = "choice",
  ["instances.quest.xp"] = "%s XP",
  ["instances.quest.pos"] = "map %s, position %s",
  ["instances.quest.noStartPos"] = "start position not in the data",
  ["tour.instances.title"] = "Dungeons & raids",
  ["tour.instances.intro.title"] = "Dungeons and raids",
  ["tour.instances.intro.text"] = "Instances with bosses and quests (Enter: next, Esc: end)",
  ["tour.instances.filters.title"] = "Filters",
  ["tour.instances.filters.text"] = "Filter by type, faction, level and name.",
  ["tour.instances.list.title"] = "Instance cards",
  ["tour.instances.list.text"] = "Arrow keys move between cards, Enter opens the details.",
  ["tour.instances.detail.title"] = "Details",
  ["tour.instances.detail.text"] = "Loading screen, numbers and map button, below them bosses, quests, items, access and map.",
})

ns.AddLocale("deDE", {
  ["instances.intro"] = "Dungeons und Raids: Stufen, Eingang, Bosse, Quests",
  ["instances.search"] = "Nach Instanz- oder Bossname filtern",
  ["instances.unknown"] = "?",
  ["instances.sort.label"] = "Sortieren nach",
  ["instances.sort.name"] = "Name",
  ["instances.sort.level"] = "Stufe",
  ["instances.back"] = "Alle Instanzen",
  ["instances.back.tip"] = "Zurück zur Übersicht aller Instanzen (Rücktaste).",
  ["instances.status.announced"] = "angekündigt",
  ["instances.dtab.info"] = "Info",
  ["instances.dtab.bosses"] = "Bosse",
  ["instances.dtab.quests"] = "Quests",
  ["instances.dtab.map"] = "Karte",
  ["instances.dtab.access"] = "Zugang",
  ["instances.info.level"] = "Stufe: %s",
  ["instances.info.group"] = "Gruppengröße: %s",
  ["instances.info.faction"] = "Fraktion: %s",
  ["instances.info.location"] = "Lage: %s",
  ["instances.info.status"] = "Status: %s",
  ["instances.info.entrance"] = "Eingang: Karte %s, Position %s",
  ["instances.info.entranceNone"] = "Keine Eingangsposition in den Daten.",
  ["instances.info.counts"] = "%d Boss(e), %d Quest(s) in den Daten.",
  ["instances.info.noId"] = "Diese Instanz hat in den Daten keine Spiel-Instanz-ID.",
  ["instances.bosses.none"] = "Für diese Instanz sind noch keine Bosse erfasst.",
  ["instances.bosses.optional"] = "optional",
  ["instances.bosses.heroic"] = "heroisch",
  ["instances.bosses.count.one"] = "1 Boss",
  ["instances.bosses.count.other"] = "%d Bosse",
  ["instances.bosses.names"] = "Einige Bossnamen nur in einer Sprache vorhanden.",
  ["instances.quests.none"] = "Für diese Instanz sind keine Quests erfasst. Das heißt nicht, dass es keine gibt.",
  ["instances.quests.noneDirect"] = "Keine Instanz-Quests bekannt.",
  ["instances.quests.noneFaction"] = "Keine Quests für diese Fraktion in den Daten.",
  ["instances.quest.head"] = "%s (Quest-Stufe %s, ab Stufe %s)",
  ["instances.quest.start"] = "Beginnt bei: %s",
  ["instances.quest.startIn"] = "in %s",
  ["instances.quest.end"] = "Abgabe: %s",
  ["instances.quest.pre"] = "Voraussetzung: %s",
  ["instances.quest.next"] = "Danach: %s",
  ["instances.quest.reward"] = "Belohnung: %s",
  ["instances.quest.choice"] = "Wahl",
  ["instances.quest.xp"] = "%s EP",
  ["instances.quest.pos"] = "Karte %s, Position %s",
  ["instances.quest.noStartPos"] = "Startposition nicht in den Daten",
  ["tour.instances.title"] = "Dungeons & Raids",
  ["tour.instances.intro.title"] = "Dungeons und Raids",
  ["tour.instances.intro.text"] = "Instanzen mit Bossen und Quests (Enter: weiter, Esc: Ende)",
  ["tour.instances.filters.title"] = "Filter",
  ["tour.instances.filters.text"] = "Filtere nach Typ, Fraktion, Stufe und Namen.",
  ["tour.instances.list.title"] = "Instanzkarten",
  ["tour.instances.list.text"] = "Pfeiltasten wechseln die Karte, Enter öffnet die Details.",
  ["tour.instances.detail.title"] = "Details",
  ["tour.instances.detail.text"] = "Ladebild, Eckdaten und Karten-Knopf, darunter Bosse, Quests, Items, Zugang und Karte.",
})

local plural, dual = IV.Plural, IV.Dual

-- Level text for list rows, with the tooltip that names a gap, the entry level and the recommended level.
local function levelLabel(inst)
  local info = ns.InstanceLevelLogic.Of(inst, L)
  local tip = {}
  for _, bit in ipairs({ info.gapText or false, info.entryText or false, info.recommendedText or false }) do
    if bit then
      tip[#tip + 1] = bit
    end
  end
  return info.text, #tip > 0 and table.concat(tip, "\n") or nil
end
ns.InstanceLevelLabel = levelLabel

function ns.InstanceInfoText(inst)
  local lines = {}
  local info = ns.InstanceLevelLogic.Of(inst, L)
  lines[1] = string.format(L["instances.info.level"], info.text)
  if info.entryText then
    lines[#lines + 1] = info.entryText
  end
  if info.recommendedText then
    lines[#lines + 1] = info.recommendedText
  end
  if info.gapText then
    lines[#lines + 1] = Theme.hexText("textMuted", info.gapText)
  end
  lines[#lines + 1] = string.format(L["instances.info.group"], plural(inst.gs))
  lines[#lines + 1] =
    string.format(L["instances.info.faction"], inst.f == "B" and L["kit.faction.all"] or L["kit.faction." .. inst.f])
  if inst.loc then
    lines[#lines + 1] = string.format(L["instances.info.location"], dual(inst.loc))
  end
  if inst.st then
    local key = "instances.status." .. inst.st
    local bits = { L[key] ~= key and L[key] or inst.st }
    if info.releaseText then
      bits[#bits + 1] = info.releaseText
    end
    lines[#lines + 1] = string.format(L["instances.info.status"], table.concat(bits, ", "))
  elseif info.releaseText then
    lines[#lines + 1] = Theme.hexText("textMuted", info.releaseText)
  end
  if inst.ent and #inst.ent > 0 then
    for _, e in ipairs(inst.ent) do
      local line = string.format(L["instances.info.entrance"], tostring(e.m or "?"), K.Coord(e.x, e.y) or "?")
      if e.nt then
        line = line .. " (" .. (ns.T(e.nt) or "") .. ")"
      end
      lines[#lines + 1] = line
    end
  else
    lines[#lines + 1] = L["instances.info.entranceNone"]
  end
  if inst.q or DA.Loaded() then
    lines[#lines + 1] = string.format(L["instances.info.counts"], #(inst.bo or {}), #(inst.q or {}))
  else
    lines[#lines + 1] = string.format(L["instancedata.counts"], #(inst.bo or {}))
  end
  if not inst.id then
    lines[#lines + 1] = Theme.hexText("warning", L["instances.info.noId"])
  end
  lines[#lines + 1] = ""
  local gaps = IV.GapLines(inst)
  if #gaps == 0 then
    lines[#lines + 1] = Theme.hexText("textMuted", L["instances.gap.complete"])
  else
    lines[#lines + 1] = Theme.hexText("warning", L["instances.gap.head"])
    for _, gap in ipairs(gaps) do
      lines[#lines + 1] = Theme.hexText("textMuted", "· " .. gap)
    end
    lines[#lines + 1] = Theme.hexText("textMuted", L["instances.gap.hint"])
  end
  return table.concat(lines, "\n")
end

function ns.InstanceBossText(inst)
  local count = inst.bo and #inst.bo or 0
  if count == 0 then
    return L["instances.bosses.none"]
  end
  local key = ns.GetActiveLocale() == "deDE" and "de" or "en"
  local lines, partial =
    {
      Theme.hexText("accent2", string.format(L["instances.bosses.count." .. (count == 1 and "one" or "other")], count)),
    }, false
  for i, b in ipairs(inst.bo) do
    local line = string.format("%d. %s", i, dual(b.n) or "?")
    if b.opt then
      line = line .. "  " .. Theme.hexText("textMuted", L["instances.bosses.optional"])
    end
    if b.hc then
      line = line .. "  " .. Theme.hexText("warning", L["instances.bosses.heroic"])
    end
    partial = partial or not (b.n and b.n[key])
    lines[#lines + 1] = line
  end
  if partial then
    lines[#lines + 1] = ""
    lines[#lines + 1] = Theme.hexText("textMuted", L["instances.bosses.names"])
  end
  return table.concat(lines, "\n")
end

-- Text of an empty quest list: the faction note only when the other faction has direct quests, a neutral text
-- when the instance has only chain links.
local function emptyQuestText(inst)
  if #(inst.q or {}) == 0 then
    return L["instances.quests.none"]
  end
  return L[#R.Quests(inst, nil) == 0 and "instances.quests.noneDirect" or "instances.quests.noneFaction"]
end

function ns.InstanceQuestText(inst, faction)
  local quests = R.Quests(inst, faction)
  if #quests == 0 then
    return emptyQuestText(inst)
  end
  local byId = {}
  for _, q in ipairs(inst.q) do
    byId[q.id or 0] = q
  end
  local blocks = {}
  for _, q in ipairs(quests) do
    blocks[#blocks + 1] = table.concat(IV.QuestLines(q, byId), "\n")
  end
  return table.concat(blocks, "\n\n")
end

local STACK_BELOW = 760 -- below this width every section follows the other and the tabs are gone
local TABS = { "bosses", "quests", "items", "access", "map", "info" }
local VALID_TAB = {}
for _, id in ipairs(TABS) do
  VALID_TAB[id] = true
end
-- Other names of a tab in a route.
local TAB_ALIAS = { loot = "items" }
-- One faction choice for the cards, the header, the loot quests and the quest tab (see QuestChainView).
local FACTION_PATH = "settings.instancesQuestFilter"

local function build(container)
  local FL = ns.FlowLayout
  local IL = ns.InstanceListLogic
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = { slug = nil, dtab = "bosses" }
  local refresh, relayout

  local function faction()
    return IL.Faction(ns.db.settings.instancesQuestFilter, K.PlayerFaction())
  end
  -- The faction as the detail views take it: "A", "H", or nil for both.
  local function detailFaction()
    local choice = faction()
    return choice ~= "all" and choice or nil
  end

  -- The intro and the reset row belong to the cards; the detail level has the reset beside its back button.
  local intro = ns.AddParagraph(view, "instances.intro", { role = "micro", gap = 6 })

  -- The reset of the instances (chat command of the game).
  local resetRow = CreateFrame("Frame", nil, view.content)
  local resetBtn = ns.InstanceReset.Button(resetRow)
  resetBtn:SetPoint("TOPLEFT")
  function resetRow:fgGridLayout(width)
    resetBtn:SetWidth(resetBtn:Fit(width))
    self:SetHeight(resetBtn:GetHeight())
    return resetBtn:GetHeight()
  end
  s:Add(resetRow, { gap = 8 })

  -- Decides what the page shows before anything below it is placed: the cards, or the chosen instance
  -- (every section in a column when narrow, else the chosen tab).
  local probe = CreateFrame("Frame", nil, view.content)
  local showSections
  function probe:fgGridLayout()
    showSections(view.area:GetWidth() < STACK_BELOW)
    return 0
  end
  s:Add(probe, { height = 0, gap = 0 })

  -- Level one: the card grid ----------------------------------------------------------------------------
  local cards = ns.InstanceCards.Create(view.content, {
    faction = K.PlayerFaction(),
    filter = { faction = faction() },
    onOpen = function(inst)
      ns.Router:navigate("instances/" .. R.InstanceSlug(inst))
    end,
    onFaction = function(choice)
      ns.Store.set(FACTION_PATH, choice)
    end,
  })
  function cards:fgGridLayout(width)
    return self:Layout(width)
  end
  K.Anchor("FG.Instances.Filters", cards.bar)
  K.Anchor("FG.Instances.List", cards.grid)
  s:Add(cards, { gap = 0 })

  -- Level two: the chosen instance ----------------------------------------------------------------------
  local back = W.Action(view.content, {
    key = "instances.back",
    icon = "chevron-left",
    variant = "ghost",
    height = 26,
    opens = false,
    tooltip = "instances.back",
    tooltipText = "instances.back.tip",
    onClick = function()
      ns.Router:navigate("instances")
    end,
  })
  local detailReset = ns.InstanceReset.Button(view.content)
  detailReset:SetVariant("ghost")
  -- Back and reset share one row, the reset wraps below the back button when the row is too narrow.
  local backRow = CreateFrame("Frame", nil, view.content)
  back:SetParent(backRow)
  detailReset:SetParent(backRow)
  function backRow:fgGridLayout(width)
    local gap = 8
    local bw, rw = back:Fit(width), detailReset:Fit(width)
    back:SetWidth(bw)
    detailReset:SetWidth(rw)
    back:ClearAllPoints()
    back:SetPoint("TOPLEFT")
    detailReset:ClearAllPoints()
    local h = math.max(back:GetHeight(), detailReset:GetHeight())
    if bw + gap + rw <= width then
      detailReset:SetPoint("TOPLEFT", back, "TOPRIGHT", gap, 0)
    else
      detailReset:SetPoint("TOPLEFT", back, "BOTTOMLEFT", 0, -gap)
      h = back:GetHeight() + gap + detailReset:GetHeight()
    end
    self:SetHeight(h)
    return h
  end
  s:Add(backRow, { gap = 8 })

  local header = IV.Header(view.content)
  K.Anchor("FG.Instances.Detail", header)
  s:Add(header, { gap = 12 })

  -- The tab row wraps instead of cutting off, a selected tab has a bar (and its own color).
  local tabDefs = {}
  for _, id in ipairs(TABS) do
    tabDefs[#tabDefs + 1] = {
      id = id,
      key = "instances.dtab." .. id,
      variant = "ghost",
      onClick = function()
        state.dtab = id
        refresh()
      end,
    }
  end
  local tabRow = FL.ButtonRow(view.content, tabDefs)
  s:Add(tabRow, { gap = 10 })
  local function paintTabs()
    for _, id in ipairs(TABS) do
      local b = tabRow:GetButton(id)
      local on = id == state.dtab
      b.bar:SetShown(on)
      W.SetColor(b.label, on and "accent" or "textSecondary")
    end
  end
  for _, id in ipairs(TABS) do
    local b = tabRow:GetButton(id)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("BOTTOMLEFT", 4, 0)
    b.bar:SetPoint("BOTTOMRIGHT", -4, 0)
    b.bar:SetHeight(2)
    ns.Bind(b.bar, function(t)
      t:SetColorTexture(Theme.color("accent2"))
    end)
    b:HookScript("OnEnter", paintTabs)
    b:HookScript("OnLeave", paintTabs)
  end

  -- A section is a heading (stacked layout only) and parts. A part with fgOn == false stays hidden.
  local order = {}
  local function newSection(id)
    local sec = { id = id, parts = {} }
    sec.heading = ns.AddHeading(view, "instances.dtab." .. id, { gap = 6 })
    order[#order + 1] = sec
    return sec
  end
  local function part(sec, item, opts)
    s:Add(item, opts or { gap = 10 })
    sec.parts[#sec.parts + 1] = item
    return item
  end
  local function note(sec)
    return part(sec, W.Text(view.content, { role = "ui", color = "textSecondary", wrap = true }))
  end

  local bosses = newSection("bosses")
  local bossNote = note(bosses)
  local bossList = part(bosses, IV.BossList(view.content), { gap = 14 })

  local quests = newSection("quests")
  local questNote = note(quests)
  local questList = part(quests, ns.QuestChainView.Create(view.content), { gap = 14 })
  questList.onChange = function()
    relayout()
  end

  local items = newSection("items")
  local itemsView = part(items, ns.InstanceItemsView.Create(view.content), { gap = 14 })
  itemsView.onChange = function()
    relayout()
  end

  local accessSec = newSection("access")
  local access = part(accessSec, ns.AccessView.Create(view.content), { gap = 14 })
  access.onChange = function()
    relayout()
  end

  local mapSec = newSection("map")
  local mapView = part(mapSec, ns.DungeonMapView.Create(view.content), { gap = 14 })
  mapView.onChange = function()
    relayout()
  end

  local infoSec = newSection("info")
  local infoText = part(infoSec, W.Text(view.content, { role = "ui", color = "text", wrap = true }), { gap = 10 })
  -- Buttons an extension registers for the open instance (slot "instances"), none without an extension.
  local infoButtons = {}
  for _, tool in ipairs(ns.DevTools.Slot("instances")) do
    local b = tool.button
    infoButtons[#infoButtons + 1] = {
      id = b.id or tool.id,
      label = b.label,
      icon = b.icon,
      tooltip = b.tooltip,
      onClick = function()
        if state.inst then
          tool.run(state.inst)
        end
      end,
    }
  end
  if #infoButtons > 0 then
    part(infoSec, FL.ButtonRow(view.content, infoButtons), { gap = 14 })
  end

  function showSections(stacked)
    local inst = state.inst
    cards:SetShown(inst == nil)
    intro:SetShown(inst == nil)
    resetRow:SetShown(inst == nil)
    backRow:SetShown(inst ~= nil)
    header:SetShown(inst ~= nil)
    for _, sec in ipairs(order) do
      local on = inst ~= nil and (stacked or state.dtab == sec.id)
      sec.heading:SetShown(on and stacked)
      for _, item in ipairs(sec.parts) do
        item:SetShown(on and item.fgOn ~= false)
      end
    end
    tabRow:SetShown(inst ~= nil and not stacked)
    -- The map holds tile textures, so it only has an instance while it is on screen.
    local mapOn = inst ~= nil and (stacked or state.dtab == "map")
    if mapOn then
      local key = inst.n.en
      if mapView.state.requested ~= key then
        mapView:SetInstance(key)
      end
    elseif mapView.state.requested then
      mapView:SetInstance(nil)
    end
  end

  function relayout()
    view:Layout()
  end

  function refresh()
    -- The quests are in a data add-on that loads here, before anything reads inst.q.
    local dataStatus = DA.Ensure()
    local inst = K.HasData("Instances") and state.slug and R.FindInstance(state.slug) or nil
    state.inst = inst
    local choice = detailFaction()
    header:SetInstance(inst, choice)
    if inst then
      bossList:SetInstance(inst)
      questList:SetInstance(inst, choice)
      itemsView:SetInstance(inst, choice)
      -- No bosses: the empty note. Else one line says for how many bosses the data has abilities.
      if bossList.count == 0 then
        bossNote:SetText(L["instances.bosses.none"])
      else
        local known, total = ns.InstanceGaps.AbilityCount(inst)
        bossNote:SetText(string.format(L["instances.abilities.summary"], known, total))
      end
      bossNote.fgOn = true
      if dataStatus ~= DA.STATUS.ok then
        questNote:SetText(DA.Hint(dataStatus))
      else
        questNote:SetText(emptyQuestText(inst))
      end
      questNote.fgOn = questList.count == 0
      access:SetInstance(inst, choice)
      infoText:SetText(ns.InstanceInfoText(inst))
    end
    paintTabs()
    relayout()
  end

  -- The switch of the quest tab or of the cards changed the shared choice: the other controls follow.
  ns.On("FG_SETTING_CHANGED", function(_, path, value)
    if path ~= FACTION_PATH then
      return
    end
    local choice = IL.Faction(value, K.PlayerFaction())
    if cards.filter.faction ~= choice then
      cards:SetFilter({ faction = choice })
    end
    if state.inst and view.area:IsVisible() then
      refresh()
    end
  end)

  -- The quest data came in after a fight: the open page shows the quests.
  ns.On("FG_INSTANCE_DATA", function()
    if state.inst and view.area:IsVisible() then
      refresh()
    end
  end)

  -- A kill or a reset: the header count and the marks of the boss rows follow while the page is open.
  ns.On("FG_BOSS_PROGRESS", function()
    local inst = state.inst
    if inst and view.area:IsVisible() then
      header:SetInstance(inst, detailFaction())
      bossList:SetInstance(inst)
      relayout()
    end
  end)

  -- The instance the player stands in (the resolver of the dungeon map: instance ID, else the name in either
  -- language), on its boss tab.
  local function selectCurrent()
    local here = ns.DungeonMapView.Current()
    if not here then
      return false
    end
    state.slug, state.dtab = R.InstanceSlug(here), "bosses"
    return true
  end

  local hereSlug
  local function currentSlug()
    local here = ns.DungeonMapView.Current()
    return here and R.InstanceSlug(here) or nil
  end

  local function showState()
    -- The shared choice may have changed on another page since the cards were built.
    if cards.filter.faction ~= faction() then
      cards:SetFilter({ faction = faction() })
    end
    refresh()
    view.area:ScrollTo(0)
  end

  -- Entering another instance while the page is open chooses it, a floor change or the same instance does not.
  ns.On("PLAYER_ENTERING_WORLD", function()
    local slug = currentSlug()
    local changed = slug ~= nil and slug ~= hereSlug
    hereSlug = slug
    if slug ~= state.overviewFor then
      state.overviewFor = nil
    end
    if changed and view.area:IsVisible() and selectCurrent() then
      showState()
    end
  end)

  -- onPage: the page was shown and neither another page nor a closed window came since. The container is hidden
  -- and shown again on every route change, so OnHide cannot tell a new opening from a move inside the page.
  local function leavePage()
    state.onPage, state.overviewFor = false, nil
  end
  ns.On("FG_MAIN_HIDDEN", leavePage)
  ns.On("FG_ROUTE_CHANGED", function(_, _, pageId)
    if pageId ~= "instances" then
      leavePage()
    end
  end)

  -- A slug (and a tab) of the route: that instance, an unknown slug shows the cards. No slug: the instance the
  -- player stands in, else the cards. An explicit move to "instances" from inside the page (back button, back
  -- key, breadcrumb, sidebar) always shows the cards and keeps the current instance from opening again until
  -- the player enters another one or opens the page anew.
  function view:Show(params)
    hereSlug = currentSlug()
    local inst = params and params[1] and R.FindInstance(params[1]) or nil
    local tab = params and params[2]
    tab = TAB_ALIAS[tab] or tab
    if inst then
      state.slug = R.InstanceSlug(inst)
    else
      local bare = not (params and params[1])
      local leaving = bare and state.onPage and ns.Router.current == "instances"
      if leaving then
        state.overviewFor = currentSlug()
      elseif not state.onPage then
        state.overviewFor = nil
      end
      local muted = state.overviewFor ~= nil and state.overviewFor == currentSlug()
      -- The boss tab of the instance the player stands in, unless the route names another tab.
      local picked = bare and not leaving and not muted and selectCurrent()
      if not picked then
        state.slug = nil
      end
    end
    if VALID_TAB[tab] then
      state.dtab = tab
    end
    state.onPage = true
    showState()
  end
  return view
end

ns.RegisterPage({
  id = "instances",
  order = 130,
  group = "world",
  title = "page.instances",
  icon = ns.ICONS.instances,
  aliases = { "instanzen", "raids", "instances", "dungeons" },
  crumbLabel = function(param, index)
    if index == 1 then
      local inst = R.FindInstance(param)
      return inst and ns.T(inst.n) or param
    end
    local key = "instances.dtab." .. (TAB_ALIAS[param] or param)
    return L[key] ~= key and L[key] or param
  end,
  build = build,
})
