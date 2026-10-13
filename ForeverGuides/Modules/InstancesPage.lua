-- Dungeons & raids: list on the left, header and tabs on the right (side by side from a page width of
-- 760, stacked and without tabs below it). Data: ns.Data.Instances. The header and the row lists are
-- in Modules/InstanceView.lua, the items in Modules/InstanceItemsView.lua.
local _, ns = ...
local W, L, Theme, R, K, IV = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit, ns.InstanceView

ns.AddLocale("enUS", {
  ["instances.intro"] = "Dungeons and raids: levels, entrance, bosses, quests",
  ["instances.tab.dungeon"] = "Dungeons",
  ["instances.tab.raid"] = "Raids",
  ["instances.search"] = "Filter by instance or boss name",
  ["instances.sub"] = "%s · group %s",
  ["instances.unknown"] = "?",
  ["instances.level.range"] = "Level %s",
  ["instances.level.from"] = "from level %d",
  ["instances.level.unknown"] = "Level ?",
  ["instances.level.tip"] = "Recommended level, maximum unknown.",
  ["instances.sort.label"] = "Sort by",
  ["instances.sort.name"] = "Name",
  ["instances.sort.level"] = "Level",
  ["instances.status.announced"] = "announced",
  ["instances.release"] = "release %s",
  ["instances.empty"] = "No instance matches.",
  ["instances.pick"] = "Select an instance from the list.",
  ["instances.dtab.info"] = "Info",
  ["instances.dtab.bosses"] = "Bosses",
  ["instances.dtab.quests"] = "Quests",
  ["instances.dtab.map"] = "Map",
  ["instances.dtab.access"] = "Access",
  ["instances.info.level"] = "Level: %s",
  ["instances.info.levelFrom"] = "Level: from %d (recommended)",
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
  ["tour.instances.filters.text"] = "Switch dungeons and raids, filter by name and faction.",
  ["tour.instances.list.title"] = "Instance list",
  ["tour.instances.list.text"] = "Tab to an entry and press Enter to open its details.",
  ["tour.instances.detail.title"] = "Details",
  ["tour.instances.detail.text"] = "Picture, numbers and map button, below them bosses, quests, items, access and map.",
})

ns.AddLocale("deDE", {
  ["instances.intro"] = "Dungeons und Raids: Stufen, Eingang, Bosse, Quests",
  ["instances.tab.dungeon"] = "Dungeons",
  ["instances.tab.raid"] = "Raids",
  ["instances.search"] = "Nach Instanz- oder Bossname filtern",
  ["instances.sub"] = "%s · Gruppe %s",
  ["instances.unknown"] = "?",
  ["instances.level.range"] = "Stufe %s",
  ["instances.level.from"] = "ab Stufe %d",
  ["instances.level.unknown"] = "Stufe ?",
  ["instances.level.tip"] = "Empfohlene Stufe, Maximalstufe unbekannt.",
  ["instances.sort.label"] = "Sortieren nach",
  ["instances.sort.name"] = "Name",
  ["instances.sort.level"] = "Stufe",
  ["instances.status.announced"] = "angekündigt",
  ["instances.release"] = "Release %s",
  ["instances.empty"] = "Keine Instanz passt.",
  ["instances.pick"] = "Wähle eine Instanz aus der Liste.",
  ["instances.dtab.info"] = "Info",
  ["instances.dtab.bosses"] = "Bosse",
  ["instances.dtab.quests"] = "Quests",
  ["instances.dtab.map"] = "Karte",
  ["instances.dtab.access"] = "Zugang",
  ["instances.info.level"] = "Stufe: %s",
  ["instances.info.levelFrom"] = "Stufe: ab %d (empfohlen)",
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
  ["tour.instances.filters.text"] = "Wechsle zwischen Dungeons und Raids, filtere nach Namen und Fraktion.",
  ["tour.instances.list.title"] = "Instanzliste",
  ["tour.instances.list.text"] = "Mit Tab zu einem Eintrag, Enter öffnet die Details.",
  ["tour.instances.detail.title"] = "Details",
  ["tour.instances.detail.text"] = "Bild, Eckdaten und Karten-Knopf, darunter Bosse, Quests, Items, Zugang und Karte.",
})

local plural, dual = IV.Plural, IV.Dual

-- Level for list rows: the range from the data, else the recommended level, else "?".
-- The second result is true when only the recommended level is known (maximum unknown).
local function levelLabel(inst)
  if inst.lv then
    return string.format(L["instances.level.range"], inst.lv), false
  end
  if inst.rl then
    return string.format(L["instances.level.from"], inst.rl), true
  end
  return L["instances.level.unknown"], false
end
ns.InstanceLevelLabel = levelLabel

function ns.InstanceInfoText(inst)
  local lines = {}
  if not inst.lv and inst.rl then
    lines[1] = string.format(L["instances.info.levelFrom"], inst.rl)
    lines[2] = Theme.hexText("textMuted", L["instances.level.tip"])
  else
    lines[1] = string.format(L["instances.info.level"], plural(inst.lv))
  end
  lines[#lines + 1] = string.format(L["instances.info.group"], plural(inst.gs))
  lines[#lines + 1] =
    string.format(L["instances.info.faction"], inst.f == "B" and L["kit.faction.all"] or L["kit.faction." .. inst.f])
  if inst.loc then
    lines[#lines + 1] = string.format(L["instances.info.location"], dual(inst.loc))
  end
  if inst.st or inst.rd then
    local bits = {}
    if inst.st then
      local key = "instances.status." .. inst.st
      bits[#bits + 1] = L[key] ~= key and L[key] or inst.st
    end
    if inst.rd then
      bits[#bits + 1] = string.format(L["instances.release"], inst.rd)
    end
    lines[#lines + 1] = string.format(L["instances.info.status"], table.concat(bits, ", "))
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
  lines[#lines + 1] = string.format(L["instances.info.counts"], #(inst.bo or {}), #(inst.q or {}))
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

function ns.InstanceQuestText(inst, faction)
  local quests = R.Quests(inst, faction)
  if #quests == 0 then
    return L[#(inst.q or {}) == 0 and "instances.quests.none" or "instances.quests.noneFaction"]
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

-- Two sub lines (level, group, location / second-language names) need more than the 42 px default.
local ROW_HEIGHT = 56
local LIST_ROWS_SIDE, LIST_ROWS_STACKED = 3, 5 -- the least rows the list shows
local SCROLLBAR = 12 -- gutter of a ScrollArea
local TABS = { "bosses", "quests", "items", "access", "map", "info" }
local VALID_TAB = {}
for _, id in ipairs(TABS) do
  VALID_TAB[id] = true
end

-- The instance chosen last, kept while the game runs so the page opens where it was left.
local lastSlug

local function build(container)
  local FL = ns.FlowLayout
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = {
    kind = "dungeon",
    faction = K.PlayerFaction() or "all",
    query = "",
    slug = nil,
    dtab = "bosses",
    sort = ns.db.settings.instancesSort == "level" and "level" or "name",
  }
  local refresh, layoutPanes, relayout, scrollToDetail
  -- The rows of the list as shown, and whether the list still has to scroll to the chosen row (after layout).
  local shown, revealPending

  local intro = ns.AddParagraph(view, "instances.intro", { role = "micro", gap = 6 })

  -- Two panes: list and filters on the left, the chosen instance on the right. Below a page width
  -- of 760 the panes stack: the list on top at a fixed height, the instance below it with every
  -- section one after the other and the page itself scrolling.
  local split = FL.TwoPane(view.content, {
    ratio = 0.32,
    leftMin = 260,
    leftMax = 380,
    rightMin = 300,
    stackedShare = 0,
    stackedRightMin = 1,
    minHeight = 420,
    getPageWidth = function()
      return view.area:GetWidth()
    end,
    getHeight = function()
      return view.area:GetHeight() - 2 * s.pad - intro:GetHeight() - 6
    end,
    onLayout = function(info)
      return layoutPanes(info)
    end,
  })
  s:Add(split, { gap = 0 })
  local leftPane, rightPane = split.left, split.right

  local function currentItems()
    local faction = state.faction ~= "all" and state.faction or nil
    return R.Instances(state.kind, faction, state.query, ns.SearchLogic.match, state.sort)
  end

  local function firstSlug()
    local first = K.HasData("Instances") and currentItems()[1]
    return first and R.InstanceSlug(first) or nil
  end

  -- Left pane: kind tabs, faction, search and sort, then the list --------------------------------
  local filters = CreateFrame("Frame", nil, leftPane)
  K.Anchor("FG.Instances.Filters", filters)
  local kindTabs = W.Tabs(filters, {
    tabs = { { id = "dungeon", key = "instances.tab.dungeon" }, { id = "raid", key = "instances.tab.raid" } },
    onSelect = function(id)
      if state.kind ~= id then
        state.kind = id
        state.slug = firstSlug()
      end
      refresh()
    end,
  })
  kindTabs:SetPoint("TOPLEFT")
  local facDd = K.FactionButtons(filters, {
    withAll = true,
    get = function()
      return state.faction
    end,
    set = function(v)
      state.faction = v
      refresh()
    end,
  })
  local search = W.EditBox(filters, {
    placeholder = "instances.search",
    clear = true,
    onChange = function(text)
      state.query = text
      refresh()
    end,
  })
  local sortLabel = W.Text(filters, { key = "instances.sort.label", role = "ui", color = "textSecondary" })
  local sortToggle = K.ViewToggle(filters, {
    views = { "name", "level" },
    keyPrefix = "instances.sort.",
    get = function()
      return state.sort
    end,
    set = function(v)
      state.sort = v
      ns.Store.set("settings.instancesSort", v)
      refresh()
    end,
  })
  local resetBtn = ns.InstanceReset.Button(filters)
  function filters:fgGridLayout(width)
    local y = 38
    facDd:ClearAllPoints()
    facDd:SetPoint("TOPLEFT", filters, "TOPLEFT", 0, -y)
    facDd:SetWidth(width)
    y = y + facDd:fgGridLayout(width) + 12
    search:ClearAllPoints()
    search:SetPoint("TOPLEFT", filters, "TOPLEFT", 0, -y)
    search:SetWidth(math.min(width, 360))
    y = y + 26 + 8
    sortLabel:ClearAllPoints()
    sortToggle:ClearAllPoints()
    if math.ceil(sortLabel:GetStringWidth()) + 8 + sortToggle:GetWidth() <= width then
      sortLabel:SetPoint("LEFT", filters, "TOPLEFT", 0, -(y + 11))
      sortToggle:SetPoint("LEFT", sortLabel, "RIGHT", 8, 0)
      y = y + 22
    else
      sortLabel:SetPoint("TOPLEFT", filters, "TOPLEFT", 0, -y)
      y = y + math.ceil(sortLabel:GetStringHeight()) + 4
      sortToggle:SetPoint("TOPLEFT", filters, "TOPLEFT", 0, -y)
      y = y + 22
    end
    y = y + 8
    resetBtn:ClearAllPoints()
    resetBtn:SetPoint("TOPLEFT", filters, "TOPLEFT", 0, -y)
    resetBtn:SetWidth(resetBtn:Fit(width))
    y = y + resetBtn:GetHeight()
    filters:SetHeight(y)
    return y
  end

  local list = K.NewList(leftPane, {
    rowHeight = ROW_HEIGHT,
    bind = function(inst)
      local when = inst.rd and Theme.hexText("textMuted", string.format(L["instances.release"], inst.rd)) or ""
      local name, otherName = R.Names(inst.n)
      local loc, otherLoc = R.Names(inst.loc)
      local label, estimated = levelLabel(inst)
      local sub = string.format(L["instances.sub"], label, plural(inst.gs)) .. (loc and (" · " .. loc) or "")
      local others = {}
      for _, text in ipairs({ otherName or "", otherLoc or "" }) do
        if text ~= "" then
          others[#others + 1] = text
        end
      end
      if #others > 0 then
        sub = sub .. "\n" .. Theme.hexText("textMuted", table.concat(others, " · "))
      end
      return {
        title = name or "?",
        sub = sub,
        wrapSub = true,
        right = when,
        tooltip = estimated and L["instances.level.tip"] or nil,
        selected = R.InstanceSlug(inst) == state.slug,
      }
    end,
    onClick = function(inst)
      scrollToDetail = true
      ns.Router:navigate("instances/" .. R.InstanceSlug(inst))
      scrollToDetail = false
    end,
  })
  K.Anchor("FG.Instances.List", list)
  local listNote = W.Text(leftPane, { role = "ui", color = "textSecondary", wrap = true })

  -- Places the left pane and returns the height it needs at least (the list at its least rows).
  local function layoutLeft(info)
    local width = info.leftWidth
    filters:ClearAllPoints()
    filters:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, 0)
    filters:SetWidth(width)
    local y = filters:fgGridLayout(width) + 8
    if listNote:IsShown() then
      listNote:ClearAllPoints()
      listNote:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, -y)
      listNote:SetWidth(width)
      y = y + math.ceil(listNote:GetStringHeight()) + 6
    end
    local least = K.scaledHeight(ROW_HEIGHT) * (info.mode == "stacked" and LIST_ROWS_STACKED or LIST_ROWS_SIDE)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", leftPane, "TOPLEFT", 0, -y)
    list:SetSize(width, math.max(least, info.leftHeight - y))
    if revealPending then
      revealPending = false
      for i, inst in ipairs(shown or {}) do
        if R.InstanceSlug(inst) == state.slug then
          list:Reveal(i)
        end
      end
    end
    return y + least
  end

  -- Right pane: the chosen instance in a column ------------------------------------------------
  local rightArea = W.ScrollArea(rightPane)
  rightArea:SetFrameLevel(rightPane:GetFrameLevel() + 1)
  rightArea:SetAllPoints()
  local rc = rightArea.content
  local side = { area = rightArea, content = rc, stack = W.Stack(rightArea, 0) }

  local header = IV.Header(rc)
  K.Anchor("FG.Instances.Detail", header)
  side.stack:Add(header, { gap = 12 })

  -- Shown without a chosen instance (no data, or an empty list).
  local pickTitle = ns.AddHeading(side, "instances.pick", { gap = 6 })
  local pickText = ns.AddParagraph(side, "instances.pick.text", { role = "ui" })

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
  local tabRow = FL.ButtonRow(rc, tabDefs)
  side.stack:Add(tabRow, { gap = 10 })
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
    sec.heading = ns.AddHeading(side, "instances.dtab." .. id, { gap = 6 })
    order[#order + 1] = sec
    return sec
  end
  local function part(sec, item, opts)
    side.stack:Add(item, opts or { gap = 10 })
    sec.parts[#sec.parts + 1] = item
    return item
  end
  local function note(sec)
    return part(sec, W.Text(rc, { role = "ui", color = "textSecondary", wrap = true }))
  end

  local bosses = newSection("bosses")
  local bossNote = note(bosses)
  local bossList = part(bosses, IV.BossList(rc), { gap = 14 })

  local quests = newSection("quests")
  local questNote = note(quests)
  local questList = part(quests, IV.QuestList(rc), { gap = 14 })

  local items = newSection("items")
  local itemsView = part(items, ns.InstanceItemsView.Create(rc), { gap = 14 })
  itemsView.onChange = function()
    relayout()
  end

  local accessSec = newSection("access")
  local access = part(accessSec, ns.AccessView.Create(rc), { gap = 14 })
  access.onChange = function()
    relayout()
  end

  local mapSec = newSection("map")
  local mapView = part(mapSec, ns.DungeonMapView.Create(rc), { gap = 14 })
  mapView.onChange = function()
    relayout()
  end

  local infoSec = newSection("info")
  local infoText = part(infoSec, W.Text(rc, { role = "ui", color = "text", wrap = true }), { gap = 10 })
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
    part(infoSec, FL.ButtonRow(rc, infoButtons), { gap = 14 })
  end

  -- Shows what the layout mode asks for: every section when stacked, the chosen tab beside the list.
  local function showSections(mode)
    local stacked = mode == "stacked"
    local inst = state.inst
    for _, sec in ipairs(order) do
      local on = inst ~= nil and (stacked or state.dtab == sec.id)
      sec.heading:SetShown(on and stacked)
      for _, item in ipairs(sec.parts) do
        item:SetShown(on and item.fgOn ~= false)
      end
    end
    header:SetShown(inst ~= nil)
    tabRow:SetShown(inst ~= nil and not stacked)
    pickTitle:SetShown(inst == nil)
    pickText:SetShown(inst == nil)
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

  function layoutPanes(info)
    showSections(info.mode)
    local need = layoutLeft(info)
    rc:SetWidth(math.max(1, info.rightWidth - SCROLLBAR))
    side.stack:Layout()
    if info.mode == "stacked" then
      -- The page scrolls, so the pane takes the height of its content and the wheel goes to the page.
      info.rightHeight = math.max(1, math.ceil(rc:GetHeight()))
      info.height = info.leftHeight + info.gap + info.rightHeight
      rightPane:SetHeight(info.rightHeight)
      split:SetHeight(info.height)
    end
    rightArea:EnableMouseWheel(info.mode ~= "stacked")
    return need
  end

  function relayout()
    view:Layout()
  end

  local function revealDetail()
    if split:GetMode() ~= "stacked" then
      return
    end
    local top, at = view.content:GetTop(), rightPane:GetTop()
    if top and at then
      view.area:ScrollTo(top - at)
    end
  end

  function refresh()
    if not K.HasData("Instances") then
      state.inst = nil
      listNote:SetText(L["kit.noData"])
      listNote:SetShown(true)
      pickText:SetText(L["kit.noData"])
      header:SetInstance(nil)
      relayout()
      return
    end
    local faction = state.faction ~= "all" and state.faction or nil
    local found = currentItems()
    list:SetData(found)
    shown = found
    listNote:SetText(#found == 0 and L["instances.empty"] or "")
    listNote:SetShown(#found == 0)
    local inst = state.slug and R.FindInstance(state.slug) or nil
    state.inst = inst
    pickText:SetText(L["instances.pick.text"])
    header:SetInstance(inst, faction)
    if inst then
      lastSlug = state.slug
      bossList:SetInstance(inst)
      questList:SetInstance(inst, faction)
      itemsView:SetInstance(inst, faction)
      bossNote:SetText(L["instances.bosses.none"])
      bossNote.fgOn = bossList.count == 0
      questNote:SetText(L[#(inst.q or {}) == 0 and "instances.quests.none" or "instances.quests.noneFaction"])
      questNote.fgOn = questList.count == 0
      access:SetInstance(inst, faction)
      infoText:SetText(ns.InstanceInfoText(inst))
    end
    paintTabs()
    facDd.Refresh()
    sortToggle.Refresh()
    relayout()
    if scrollToDetail then
      scrollToDetail = false
      revealDetail()
    end
  end

  -- A kill or a reset: the header count and the marks of the boss rows follow while the page is open.
  ns.On("FG_BOSS_PROGRESS", function()
    local inst = state.inst
    if inst and view.area:IsVisible() then
      header:SetInstance(inst, state.faction ~= "all" and state.faction or nil)
      bossList:SetInstance(inst)
      relayout()
    end
  end)

  -- Opened from a link or the search: that instance and tab. Opened inside an instance: that one,
  -- on its map. Opened bare: the one chosen last, else the first of the list.
  -- Chooses the instance the player stands in (the resolver of the dungeon map: instance ID, else the name in
  -- either language) with the boss tab. A filter that would hide it gives way: faction on both, search cleared.
  local function selectCurrent()
    local here = ns.DungeonMapView.Current()
    if not here then
      return false
    end
    state.kind, state.slug, state.dtab, revealPending = here.t, R.InstanceSlug(here), "bosses", true
    local function listed()
      for _, inst in ipairs(currentItems()) do
        if R.InstanceSlug(inst) == state.slug then
          return true
        end
      end
      return false
    end
    if not listed() then
      state.faction = "all"
    end
    if not listed() then
      state.query = ""
      search.edit:SetText("")
    end
    return true
  end

  -- The instance the player stood in when the page last looked: a change while the page is open chooses the new one,
  -- a floor change or the same instance leaves a manual choice alone.
  local hereSlug
  local function currentSlug()
    local here = ns.DungeonMapView.Current()
    return here and R.InstanceSlug(here) or nil
  end

  ns.On("PLAYER_ENTERING_WORLD", function()
    local slug = currentSlug()
    local changed = slug ~= nil and slug ~= hereSlug
    hereSlug = slug
    if changed and view.area:IsVisible() and selectCurrent() then
      kindTabs:Select(state.kind)
    end
  end)

  function view:Show(params)
    local slug = params and params[1]
    local tab = params and params[2]
    hereSlug = currentSlug()
    if not slug and selectCurrent() then
      if VALID_TAB[tab] then
        state.dtab = tab
      end
      kindTabs:Select(state.kind)
      return
    end
    local inst = slug and R.FindInstance(slug) or (not slug and lastSlug and R.FindInstance(lastSlug)) or nil
    if inst then
      state.kind = inst.t
      state.slug = R.InstanceSlug(inst)
    else
      state.slug = firstSlug()
    end
    if VALID_TAB[tab] then
      state.dtab = tab
    end
    kindTabs:Select(state.kind)
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
    local key = "instances.dtab." .. param
    return L[key] ~= key and L[key] or param
  end,
  build = build,
})
