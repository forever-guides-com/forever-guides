-- Dungeons & raids in two levels: without a slug the card grid with its filter bar (Modules/InstanceCards.lua),
-- with a slug the instance: back button, header band with the loading screen and the tabs (every section in a
-- column below a page width of 760). Data: ns.Data.Instances. The header and the row lists are in
-- Modules/InstanceView.lua, the bosses in Modules/InstanceBossPanel.lua, the items in Modules/InstanceItemsView.lua.
local _, ns = ...
local W, L, Theme, R, K, IV = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit, ns.InstanceView
local DA = ns.InstanceDataAccess

ns.AddLocale("enUS", {
  ["instances.intro"] = "Dungeons and raids: levels, entrance, bosses, quests",
  ["page.instances.sub"] = "All dungeons and raids",
  ["instances.search"] = "Filter by instance or boss name",
  ["instances.unknown"] = "?",
  ["instances.sort.label"] = "Sort by",
  ["instances.sort.name"] = "Name",
  ["instances.sort.level"] = "Level",
  ["instances.back"] = "All instances",
  ["instances.back.tip"] = "Returns to the overview of all instances (Backspace).",
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
  ["page.instances.sub"] = "Alle Dungeons und Raids",
  ["instances.search"] = "Nach Instanz- oder Bossname filtern",
  ["instances.unknown"] = "?",
  ["instances.sort.label"] = "Sortieren nach",
  ["instances.sort.name"] = "Name",
  ["instances.sort.level"] = "Stufe",
  ["instances.back"] = "Alle Instanzen",
  ["instances.back.tip"] = "Kehrt zur Übersicht aller Instanzen zurück (Rücktaste).",
  ["instances.status.announced"] = "angekündigt",
  ["instances.dtab.info"] = "Info",
  ["instances.dtab.bosses"] = "Bosse",
  ["instances.dtab.quests"] = "Quests",
  ["instances.dtab.map"] = "Karte",
  ["instances.dtab.access"] = "Zugang",
  ["instances.info.level"] = "Stufe: %s",
  ["instances.info.group"] = "Gruppengröße: %s",
  ["instances.info.faction"] = "Fraktion: %s",
  ["instances.info.location"] = "Ort: %s",
  ["instances.info.status"] = "Status: %s",
  ["instances.info.entrance"] = "Eingang: Karte %s, Position %s",
  ["instances.info.entranceNone"] = "Keine Eingangsposition in den Daten.",
  ["instances.info.counts"] = "%d Boss(e), %d Quest(s) in den Daten.",
  ["instances.info.noId"] = "Diese Instanz hat in den Daten keine Instanz-ID des Spiels.",
  ["instances.bosses.none"] = "Für diese Instanz sind noch keine Bosse erfasst.",
  ["instances.bosses.optional"] = "optional",
  ["instances.bosses.heroic"] = "heroisch",
  ["instances.bosses.count.one"] = "1 Boss",
  ["instances.bosses.count.other"] = "%d Bosse",
  ["instances.bosses.names"] = "Einige Bossnamen nur in einer Sprache vorhanden.",
  ["instances.quests.none"] = "Für diese Instanz sind keine Quests erfasst. Das heißt nicht, dass es keine gibt.",
  ["instances.quests.noneDirect"] = "Keine Instanz-Quests bekannt.",
  ["instances.quests.noneFaction"] = "Keine Quests für diese Fraktion in den Daten.",
  ["instances.quest.head"] = "%s (Queststufe %s, ab Stufe %s)",
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
  ["tour.instances.detail.text"] = "Ladebild, Eckdaten und Kartenknopf, darunter Bosse, Quests, Items, Zugang und Karte.",
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

local TABS = { "bosses", "quests", "items", "access", "map", "info" }
local VALID_TAB = {}
for _, id in ipairs(TABS) do
  VALID_TAB[id] = true
end
-- Other names of a tab in a route.
local TAB_ALIAS = { loot = "items" }
-- One faction choice for the cards, the header, the loot quests and the quest tab (see QuestChainView).
local FACTION_PATH = "settings.instancesQuestFilter"
-- Where the overview keeps its choices (see InstanceCards opts.onPersist).
local PERSIST_PATH = {
  view = "settings.instancesView",
  sort = "settings.instancesSortBy",
  desc = "settings.instancesSortDesc",
  bracket = "settings.instancesBracket",
  closed = "settings.instancesCollapsed",
}

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

  -- The intro belongs to the cards; the instance reset is part of their first bar row.
  local intro = ns.AddIntro(view, "instances.intro", { gap = Theme.space.sm })

  -- Decides what the page shows before anything below it is placed: the cards, or the chosen tab of the
  -- instance. The tab row stays at every width, a narrow page wraps it instead of stacking the sections.
  local probe = CreateFrame("Frame", nil, view.content)
  local showSections
  function probe:fgGridLayout()
    showSections()
    return 0
  end
  s:Add(probe, { height = 0, gap = 0 })

  -- Level one: the card grid ----------------------------------------------------------------------------
  local saved = ns.db.settings
  local cards = ns.InstanceCards.Create(view.content, {
    corner = ns.InstanceReset.Button,
    faction = K.PlayerFaction(),
    filter = {
      faction = faction(),
      sort = IL.NormalizeSort(saved.instancesSortBy),
      desc = saved.instancesSortDesc == true,
      bracket = ns.InstanceBracketLogic.Normalize(saved.instancesBracket),
    },
    view = IL.NormalizeView(saved.instancesView),
    closed = saved.instancesCollapsed,
    onOpen = function(inst, tab)
      state.cameFrom = R.InstanceSlug(inst)
      ns.Router:navigate("instances/" .. R.InstanceSlug(inst) .. (tab and ("/" .. tab) or ""))
    end,
    onPersist = function(key, value)
      ns.Store.set(PERSIST_PATH[key], value)
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
  -- The page never scrolls as a whole here (unless the window is below the minimum height): a fixed head (banner, tab
  -- row) and a body that takes the rest. Which layout applies comes from Modules/InstanceLayoutLogic.lua.
  local ILL = ns.InstanceLayoutLogic
  local head = CreateFrame("Frame", nil, view.content)
  head.layoutCount, head.applyCount = 0, 0
  local header = IV.Header(head, {
    onBack = function()
      ns.Router:navigate("instances")
    end,
  })
  K.Anchor("FG.Instances.Detail", header)

  local tabDefs = {}
  for _, id in ipairs(TABS) do
    tabDefs[#tabDefs + 1] = { id = id, key = "instances.dtab." .. id }
  end
  local tabRow = W.Tabs(head, {
    tabs = tabDefs,
    onSelect = function(id)
      state.dtab = id
      refresh()
    end,
  })
  -- "More" (last resort of a narrow tab row): a list of all tabs, reachable by Tab and Enter like any choice field.
  local moreOptions = {}
  for i, id in ipairs(TABS) do
    moreOptions[i] = { value = id, key = "instances.dtab." .. id }
  end
  local more = W.Dropdown(head, {
    compact = true,
    key = "instances.tabs.more",
    width = 140,
    options = moreOptions,
    get = function()
      return state.dtab
    end,
    set = function(id)
      tabRow:Select(id)
    end,
  })
  -- The faction switch is shared with the cards (FACTION_PATH); it sits right of the tabs and only on tabs it filters.
  local FACTION_TABS = { quests = true, items = true, access = true }
  local factionRow = K.FactionButtons(head, {
    withAll = true,
    allKey = "questchain.filter.all",
    labelKey = false,
    get = faction,
    set = function(id)
      ns.Store.set(FACTION_PATH, id)
    end,
  })
  local function paintTabs()
    tabRow:SetSelected(state.dtab)
  end

  local function tabWidths(pad)
    local out = {}
    for i, id in ipairs(TABS) do
      out[i] = math.ceil(tabRow.buttons[id].label:GetStringWidth()) + pad
    end
    return out
  end

  -- Measures, asks the layout logic and places banner, tabs and faction switch. Returns the height of the head.
  function head:fgGridLayout(width, room)
    self.layoutCount = self.layoutCount + 1
    local opts = header:Measure()
    opts.tabWidths, opts.tabCompactWidths = tabWidths(32), tabWidths(16)
    opts.moreW = 140
    opts.factionW = FACTION_TABS[state.dtab] and factionRow.NaturalWidth() or nil
    opts.factionH = opts.factionW and factionRow:fgGridLayout(width) or nil
    local layout = ILL.Compute(view.area:GetWidth(), room.viewHeight - 2 * room.pad, opts)
    local same = self.layout and ILL.Equal(self.layout, layout) and self.appliedWidth == width and not self.dirty
    self.layout = layout
    if same then
      return self:GetHeight()
    end
    self.dirty, self.appliedWidth = false, width
    self.applyCount = self.applyCount + 1
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    header:Apply(width, layout)

    local rowY = layout.bannerH + ILL.ROW_GAP
    tabRow:ClearAllPoints()
    tabRow:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -rowY)
    tabRow:SetSize(width, ILL.TAB_ROW_H)
    tabRow:SetShown(layout.tabsMode ~= "more")
    more:SetShown(layout.tabsMode == "more")
    more:ClearAllPoints()
    more:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -rowY)
    if layout.tabsMode ~= "more" then
      local widths = layout.tabsMode == "compact" and opts.tabCompactWidths or opts.tabWidths
      local x = 0
      for i, id in ipairs(TABS) do
        local b = tabRow.buttons[id]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", tabRow, "TOPLEFT", x, 0)
        b:SetWidth(widths[i])
        x = x + widths[i] + ILL.TAB_GAP
      end
    end
    local on = opts.factionW ~= nil
    factionRow:SetShown(on)
    if on then
      local own = layout.factionRow == "own"
      local fw = math.min(opts.factionW, width)
      local fh = factionRow:fgGridLayout(fw)
      factionRow:SetWidth(fw)
      factionRow:ClearAllPoints()
      local y = own and (rowY + ILL.TAB_ROW_H + ILL.ROW_GAP) or rowY
      factionRow:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(y + math.max(0, math.floor((ILL.TAB_ROW_H - fh) / 2))))
    end
    self:SetHeight(layout.headH)
    return layout.headH
  end
  s:Add(head, { gap = ILL.ROW_GAP })

  -- Parts of one tab. A tab is `frame` (a panel that lays itself out with fgGridLayout(width, room)), an optional
  -- one-line `note` above it, and whether it can fill the whole height (list and detail scroll on their own) or flows
  -- at its natural height inside one scroll area of the body.
  local body = CreateFrame("Frame", nil, view.content)
  body.scroll = W.ScrollArea(body)
  local GUTTER = 12
  local function newNote()
    return W.Text(body, { role = "ui", color = "textSecondary", wrap = true })
  end
  local bossNote, questNote = newNote(), newNote()
  local bossList = ns.InstanceBossPanel.Create(body)
  local questList = ns.QuestChainView.Create(body)
  questList.hideToolbar = true
  local itemsView = ns.InstanceItemsView.Create(body)
  local access = ns.AccessView.Create(body)
  local mapView = ns.DungeonMapView.Create(body)

  local infoPanel = CreateFrame("Frame", nil, body)
  local infoText = W.Text(infoPanel, { role = "ui", color = "text", wrap = true })
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
  local infoRow = #infoButtons > 0 and FL.ButtonRow(infoPanel, infoButtons) or nil
  function infoPanel:fgGridLayout(width)
    infoText:ClearAllPoints()
    infoText:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    infoText:SetWidth(math.max(1, width))
    local h = math.ceil(infoText:GetStringHeight())
    if infoRow then
      infoRow:ClearAllPoints()
      infoRow:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(h + Theme.space.lg))
      h = h + Theme.space.lg + infoRow:fgGridLayout(width)
    end
    self:SetSize(math.max(1, width), math.max(1, h))
    return h
  end

  local panels = {
    bosses = { frame = bossList, fill = true, note = bossNote },
    quests = { frame = questList, fill = true, note = questNote },
    items = {
      frame = itemsView,
      fill = function()
        return itemsView:CanFill()
      end,
    },
    access = { frame = access },
    map = { frame = mapView },
    info = { frame = infoPanel },
  }
  for _, panel in pairs(panels) do
    panel.frame.onChange = function()
      relayout()
    end
  end

  local function adopt(frame, parent)
    if frame:GetParent() ~= parent then
      frame:SetParent(parent)
    end
  end

  -- Takes the height the page has left (viewport minus what lies above) and places the panel of the open tab.
  function body:fgGridLayout(width, room)
    local layout = head.layout or ILL.Compute(view.area:GetWidth(), room.viewHeight - 2 * room.pad, {})
    local free = math.max(1, math.floor(room.viewHeight - room.top - room.pad))
    local active = panels[state.dtab]
    local frame = active.frame
    local noteH = 0
    for _, other in pairs(panels) do
      if other.note then
        other.note:SetShown(other == active and other.note.fgOn ~= false and state.inst ~= nil)
      end
    end
    if active.note and active.note:IsShown() then
      active.note:ClearAllPoints()
      active.note:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      active.note:SetWidth(math.max(1, width))
      noteH = math.ceil(active.note:GetStringHeight()) + Theme.space.sm
    end
    local canFill = active.fill == true or (type(active.fill) == "function" and active.fill())
    local scrollWhole = layout.pageScroll
    local below = { top = room.top + noteH, viewHeight = room.viewHeight, pad = room.pad, gap = room.gap }
    local out
    if canFill and (not scrollWhole or state.dtab == "quests") then
      -- Fills: the panel gets exactly the height and scrolls its list and detail by itself.
      local height = scrollWhole and ILL.BODY_MIN_H or math.max(1, free - noteH)
      below.fill = { height = height, mode = layout.mode, listW = layout.listW }
      body.scroll:Hide()
      adopt(frame, self)
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -noteH)
      frame:SetWidth(width)
      frame:fgGridLayout(width, below)
      out = scrollWhole and (noteH + height) or free
    elseif scrollWhole then
      -- Below the minimum height: no inner scroll area, the page scrolls as a whole.
      body.scroll:Hide()
      adopt(frame, self)
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -noteH)
      frame:SetWidth(width)
      out = noteH + frame:fgGridLayout(width, below)
    else
      -- One scroll area for the whole panel.
      local scroll = body.scroll
      scroll:Show()
      scroll:ClearAllPoints()
      scroll:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -noteH)
      scroll:SetSize(width, math.max(1, free - noteH))
      local inner = math.max(1, width - GUTTER)
      scroll.content:SetWidth(inner)
      adopt(frame, scroll.content)
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, 0)
      frame:SetWidth(inner)
      scroll:SetContentHeight(frame:fgGridLayout(inner, below))
      out = free
    end
    self:SetSize(math.max(1, width), math.max(1, out))
    return out
  end
  s:Add(body, { gap = 0 })

  function showSections()
    local inst = state.inst
    cards:SetShown(inst == nil)
    intro:SetAvailable(inst == nil)
    head:SetShown(inst ~= nil)
    body:SetShown(inst ~= nil)
    header:SetShown(inst ~= nil)
    for id, panel in pairs(panels) do
      panel.frame:SetShown(inst ~= nil and state.dtab == id)
    end
    -- The map holds tile textures, so it only has an instance while it is on screen.
    local mapOn = inst ~= nil and state.dtab == "map"
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
    head.dirty = true
    factionRow.Refresh()
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
    showSections()
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

  -- A client title for a quest arrived: the open page shows it (one message per burst of answers).
  ns.On("FG_QUEST_NAMES", function()
    if state.inst and view.area:IsVisible() then
      refresh()
    end
  end)

  -- A kill or a reset: the header count and the marks of the boss rows follow while the page is open.
  ns.On("FG_BOSS_PROGRESS", function()
    local inst = state.inst
    if inst and view.area:IsVisible() then
      header:SetInstance(inst, detailFaction())
      head.dirty = true
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

  -- Back on the overview: the card of the instance that was opened takes the focus (see PageState.Restore).
  function view:TakeFocusKey()
    local slug = state.cameFrom
    state.cameFrom = nil
    return slug
  end

  function view:FocusEntry(slug)
    if state.inst then
      return false
    end
    for i, card in ipairs(cards.cards) do
      if card.inst and R.InstanceSlug(card.inst) == slug then
        cards:SetCursor(i)
        ns.Focus.set(cards.proxy)
        return true
      end
    end
    return false
  end

  -- Esc and the back key: a narrow detail (quest, boss, loot) goes back to its list first. True when it did.
  function view:HandleBack()
    if not state.inst then
      return false
    end
    if state.dtab == "quests" then
      return questList:CloseDetail()
    elseif state.dtab == "bosses" then
      return ns.InstanceBossView.CloseDetail(bossList)
    elseif state.dtab == "items" then
      return ns.InstanceBossView.CloseDetail(itemsView.bossView)
    end
    return false
  end

  -- Page link of the header: the instance and its tab. The selected boss or quest has its own share button.
  function view:ShareState()
    if not state.slug then
      return {}
    end
    return { state.slug, state.dtab }
  end

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
    -- instances/<slug>/bosses/<encounterId> and instances/<slug>/quests/<questId> choose that entry.
    local id = state.inst and tonumber(params and params[3])
    if id and tab == "bosses" then
      bossList:SelectBossId(id)
    elseif id and tab == "quests" then
      questList:SelectId(id)
    end
  end
  return view
end

-- Name of the boss or quest in a page link (instances/<slug>/bosses/<id>), nil when the data does not know it.
local function shareEntryName(slug, tab, param)
  local inst, id = slug and R.FindInstance(slug), tonumber(param)
  if not (inst and id) then
    return nil
  end
  if tab == "bosses" then
    for _, boss in ipairs(inst.bo or {}) do
      if boss.eid == id then
        return ns.T(boss.n)
      end
    end
  elseif tab == "quests" then
    DA.Ensure()
    for _, q in ipairs(inst.q or {}) do
      if q.id == id then
        return ns.QuestNames and ns.QuestNames.Name(q) or ns.T(q.n)
      end
    end
  end
end

ns.RegisterPage({
  id = "instances",
  order = 130,
  group = "world",
  title = "page.instances",
  subtitle = "page.instances.sub",
  icon = ns.ICONS.instances,
  aliases = { "instanzen", "raids", "instances", "dungeons" },
  crumbLabel = function(param, index, params)
    if index == 1 then
      local inst = R.FindInstance(param)
      return inst and ns.T(inst.n) or param
    end
    if index == 3 then
      return shareEntryName(params and params[1], params and params[2], param) or param
    end
    local key = "instances.dtab." .. (TAB_ALIAS[param] or param)
    return L[key] ~= key and L[key] or param
  end,
  build = build,
})
