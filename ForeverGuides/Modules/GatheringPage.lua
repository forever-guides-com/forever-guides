-- Page "Ores and herbs" (/fg erze): the ore veins and herbs of the gathering data with their skill, a
-- zone list for the chosen items (levels, number of spots, one switch per item) and a Map button per
-- zone. The switches are kept per zone in ns.GatherSelection, which the map pins read. Data:
-- ns.GatherDataAccess (load-on-demand add-on), logic: GatheringLogic.
local _, ns = ...
local W, L, Theme, K = ns.W, ns.L, ns.Theme, ns.PageKit
local G, Sel, Data, R = ns.GatheringLogic, ns.GatherSelection, ns.GatherDataAccess, ns.ProfessionRouteLogic

ns.AddLocale("enUS", {
  ["page.gathering"] = "Ores and herbs",
  ["gather.intro"] = "Where ore veins and herbs grow, zone by zone. The maps show every item. Pick items to narrow a zone down, then open it on the map.",
  ["page.gathering.sub"] = "Where ore and herbs grow, by zone",
  ["gather.source"] = "Positions come from Classic data and your own finds, not all of them are confirmed for Forever.",
  ["gather.search"] = "Search",
  ["gather.searchPh"] = "Item name",
  ["gather.profession"] = "Profession",
  ["gather.professionTip"] = "Shows the items of one profession or of both.",
  ["gather.professionAll"] = "Mining and herbalism",
  ["gather.zone"] = "Zone",
  ["gather.zoneTip"] = "Shows only the items that grow in this zone.",
  ["gather.zoneAll"] = "All zones",
  ["gather.zoneOption"] = "%s (%d-%d)",
  ["gather.mine"] = "Only what I can gather",
  ["gather.mineTip"] = "Hides items above your skill. A profession you do not have hides all its items.",
  ["gather.resetTip"] = "Clears search, profession, zone and faction. The selection stays.",
  ["gather.itemsHeading"] = "Items",
  ["gather.zonesHeading"] = "Zones",
  ["gather.all"] = "Select all",
  ["gather.allTip"] = "Selects every item of the list.",
  ["gather.none"] = "Select none",
  ["gather.noneTip"] = "Clears the selection. The zones then show every item of the list.",
  ["gather.selected"] = "%d of %d selected",
  ["gather.noneSelected"] = "Nothing selected: the zones show every item of the list.",
  ["gather.itemSub"] = "%s, skill %d",
  ["gather.itemZones"] = "Zones: %d",
  ["gather.itemTip"] = "Needs skill %d. Click to select or clear the item.",
  ["gather.groupCount"] = "Items: %d",
  ["gather.groupTip"] = "Click to select every item of this group in the list. Click again to clear them.",
  ["gather.groupLabel"] = "%s (%d/%d)",
  ["gather.groupZoneTip"] = "Click to switch all %s items of this zone on or off.",
  ["gather.total"] = "Items: %d, zones: %d",
  ["gather.levels"] = "Levels %d-%d",
  ["gather.city"] = "City",
  ["gather.spots"] = "Spots: %d",
  ["gather.map"] = "Map",
  ["gather.mapTip"] = "Shows the zone on the map with the switched on items.",
  ["gather.chipTip"] = "Spots: %d. Click to switch this item on or off for the zone.",
  ["gather.chipOn"] = "On",
  ["gather.chipOff"] = "Off",
  ["gather.empty"] = "No items for this filter.",
  ["gather.noProfession"] = "No mining or herbalism found on this character.",
  ["gather.noZones"] = "No zones for this selection.",
})

ns.AddLocale("deDE", {
  ["page.gathering"] = "Erze und Kräuter",
  ["gather.intro"] = "Wo Erzadern und Kräuter wachsen, Gebiet für Gebiet. Die Karten zeigen alle Items. Wähle Items, um ein Gebiet einzuschränken, und öffne es dann auf der Karte.",
  ["page.gathering.sub"] = "Wo Erz und Kräuter wachsen, nach Gebiet",
  ["gather.source"] = "Die Positionen stammen aus Classic-Daten und eigenen Funden, nicht alle sind für Forever bestätigt.",
  ["gather.search"] = "Suchen",
  ["gather.searchPh"] = "Itemname",
  ["gather.profession"] = "Beruf",
  ["gather.professionTip"] = "Zeigt die Items eines Berufs oder beider.",
  ["gather.professionAll"] = "Bergbau und Kräuterkunde",
  ["gather.zone"] = "Gebiet",
  ["gather.zoneTip"] = "Zeigt nur Items, die in diesem Gebiet wachsen.",
  ["gather.zoneAll"] = "Alle Gebiete",
  ["gather.zoneOption"] = "%s (%d-%d)",
  ["gather.mine"] = "Nur was ich sammeln kann",
  ["gather.mineTip"] = "Blendet Items über deiner Fertigkeit aus. Ein Beruf, den du nicht hast, blendet alle seine Items aus.",
  ["gather.resetTip"] = "Leert Suche, Beruf, Gebiet und Fraktion. Die Auswahl bleibt.",
  ["gather.itemsHeading"] = "Items",
  ["gather.zonesHeading"] = "Gebiete",
  ["gather.all"] = "Alle wählen",
  ["gather.allTip"] = "Wählt jedes Item der Liste.",
  ["gather.none"] = "Keine wählen",
  ["gather.noneTip"] = "Leert die Auswahl. Die Gebiete zeigen dann jedes Item der Liste.",
  ["gather.selected"] = "%d von %d gewählt",
  ["gather.noneSelected"] = "Nichts gewählt: die Gebiete zeigen jedes Item der Liste.",
  ["gather.itemSub"] = "%s, Fertigkeit %d",
  ["gather.itemZones"] = "Gebiete: %d",
  ["gather.itemTip"] = "Braucht Fertigkeit %d. Klick wählt das Item oder hebt die Wahl auf.",
  ["gather.groupCount"] = "Items: %d",
  ["gather.groupTip"] = "Klick wählt alle Items dieser Gruppe in der Liste. Ein weiterer Klick hebt die Wahl auf.",
  ["gather.groupLabel"] = "%s (%d/%d)",
  ["gather.groupZoneTip"] = "Klick schaltet alle %s-Items dieses Gebiets ein oder aus.",
  ["gather.total"] = "Items: %d, Gebiete: %d",
  ["gather.levels"] = "Stufen %d-%d",
  ["gather.city"] = "Stadt",
  ["gather.spots"] = "Fundorte: %d",
  ["gather.map"] = "Karte",
  ["gather.mapTip"] = "Zeigt das Gebiet auf der Karte mit den eingeschalteten Items.",
  ["gather.chipTip"] = "Fundorte: %d. Klick schaltet das Item für das Gebiet ein oder aus.",
  ["gather.chipOn"] = "Ein",
  ["gather.chipOff"] = "Aus",
  ["gather.empty"] = "Keine Items für diesen Filter.",
  ["gather.noProfession"] = "Kein Bergbau und keine Kräuterkunde bei diesem Charakter gefunden.",
  ["gather.noZones"] = "Keine Gebiete für diese Auswahl.",
})

local BUTTON_H = 24
local MAP_W = 90
local CHIP_ICON = 20
local CHIP_PAD = 6
local CHIP_GAP_X = 10
local CHIP_GAP_Y = 6
local LABEL_H = 18
local GROUP_GAP = 6
-- A zone is a card: at least this wide, up to three side by side (ns.CardFlow).
local CARD_MIN_W = 300

-- Zone rows ----------------------------------------------------------------------------------------

local function createChip(parent)
  local chip = CreateFrame("Button", nil, parent)
  W.Fill(chip, "surface2")
  chip.onBg = W.Fill(chip, "action", 0.35)
  chip.border = W.Border(chip, "white", 0.25)
  local hover = chip:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(Theme.fillColor("hover"))
  chip.check = W.CheckMark(chip, 10, "text")
  chip.check:SetPoint("LEFT", CHIP_PAD, 0)
  chip.icon = chip:CreateTexture(nil, "ARTWORK")
  chip.icon:SetSize(CHIP_ICON, CHIP_ICON)
  chip.icon:SetPoint("LEFT", chip.check, "RIGHT", 4, 0)
  chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  chip.name = W.Text(chip, { role = "ui" })
  chip.name:SetPoint("LEFT", chip.icon, "RIGHT", 6, 0)
  chip:SetScript("OnEnter", function(self)
    local d = self.data
    if d then
      ns.ShowTooltip(self, d.name, string.format(L["gather.chipTip"], d.count), { link = "item:" .. tostring(d.id) })
    end
  end)
  chip:SetScript("OnLeave", ns.HideTooltip)
  chip:SetScript(
    "OnClick",
    ns.Wrap("gather-chip", function(self, button)
      -- Shift+click links the item in the chat like everywhere else, a plain click toggles the chip.
      if self.data and ns.ItemActions.Click(self.data.id, button) then
        return
      end
      if self.onToggle then
        self.onToggle()
      end
    end)
  )
  ns.Focus.register(chip, function(self)
    self:Click()
  end)
  return chip
end

-- On is shown by the check mark, the frame and the text color, never by color alone.
local function paintChip(chip, d, onToggle)
  chip.data, chip.onToggle = d, onToggle
  chip.icon:SetTexture(G.IconPath(d.id, d))
  if chip.icon.SetDesaturated then
    chip.icon:SetDesaturated(not d.on)
  end
  chip.name:SetText(string.format("%s %d", d.name, d.count))
  W.SetColor(chip.name, d.on and "text" or "textMuted")
  chip.check:SetShown(d.on)
  chip.onBg:SetShown(d.on)
  chip.border.set(d.on and "actionHi" or "white", d.on and 1 or 0.25)
end

-- The small caption of a profession group inside a zone row; a click switches the whole group.
local function createGroupLabel(parent)
  local label = CreateFrame("Button", nil, parent)
  local hover = label:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(Theme.fillColor("hover"))
  label.text = W.Text(label, { role = "micro", color = "textSecondary" })
  label.text:SetPoint("LEFT", 6, 0)
  label:SetScript("OnEnter", function(self)
    if self.prof then
      local name = R.Name(self.prof)
      ns.ShowTooltip(self, name, string.format(L["gather.groupZoneTip"], name))
    end
  end)
  label:SetScript("OnLeave", ns.HideTooltip)
  label:SetScript(
    "OnClick",
    ns.Wrap("gather-group", function(self)
      if self.onToggle then
        self.onToggle()
      end
    end)
  )
  ns.Focus.register(label, function(self)
    self:Click()
  end)
  label.fgOnFocus = function(self)
    self:GetScript("OnEnter")(self)
  end
  label.fgOnBlur = ns.HideTooltip
  return label
end

local function createZoneRow(parent)
  local row = W.Panel(parent)
  row.title = W.Text(row, { role = "ui", color = "accent2", wrap = true })
  row.meta = W.Meta(row, { wrap = true })
  row.map = W.Button(row, {
    key = "gather.map",
    width = MAP_W,
    height = BUTTON_H,
    tooltip = "gather.map",
    tooltipText = "gather.mapTip",
    opens = true,
    onClick = function()
      if row.onMap then
        row.onMap()
      end
    end,
  })
  -- Chips come in the order of the groups: spans[g] = { first, last } are the chips of group g, labels[g]
  -- is its caption.
  row.chips, row.shown, row.labels, row.spans = {}, 0, {}, {}
  function row:fgLayout(width)
    local inner = math.max(40, width - 2 * Theme.space.md)
    self.map:ClearAllPoints()
    self.map:SetPoint("TOPRIGHT", -Theme.space.md, -Theme.space.md)
    local textW = math.max(40, inner - MAP_W - 8)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", Theme.space.md, -Theme.space.md - 2)
    self.title:SetWidth(textW)
    local y = Theme.space.md + 2 + math.max(self.title:GetStringHeight(), 14) + 2
    self.meta:ClearAllPoints()
    self.meta:SetPoint("TOPLEFT", Theme.space.md, -y)
    self.meta:SetWidth(textW)
    y = math.max(y + self.meta:GetStringHeight() + 6, Theme.space.md + BUTTON_H + 6)
    local chipH = K.scaledHeight(CHIP_ICON + 6)
    local labelH = K.scaledHeight(LABEL_H)
    -- cy is the top of the next line below y: a caption line, then the wrapped chips of its group.
    local cy = 0
    for g, span in ipairs(self.spans) do
      local label = self.labels[g]
      label.text:SetWidth(0)
      local lw = math.ceil(label.text:GetStringWidth()) + 12
      if lw > inner then
        lw = inner
        label.text:SetWidth(math.max(20, inner - 12))
      end
      label:ClearAllPoints()
      label:SetPoint("TOPLEFT", self, "TOPLEFT", Theme.space.md, -(y + cy))
      label:SetSize(lw, labelH)
      cy = cy + labelH + 2
      local x = 0
      for i = span.first, span.last do
        local chip = self.chips[i]
        chip.name:SetWidth(0)
        local fixed = CHIP_PAD + 10 + 4 + CHIP_ICON + 6 + CHIP_PAD
        local nameW = math.ceil(chip.name:GetStringWidth())
        local w = fixed + nameW
        if w > inner then
          w = inner
          chip.name:SetWidth(math.max(20, inner - fixed))
        end
        if x > 0 and x + w > inner then
          x, cy = 0, cy + chipH + CHIP_GAP_Y
        end
        chip:ClearAllPoints()
        chip:SetPoint("TOPLEFT", self, "TOPLEFT", Theme.space.md + x, -(y + cy))
        chip:SetSize(w, chipH)
        x = x + w + CHIP_GAP_X
      end
      cy = cy + chipH + GROUP_GAP
    end
    local chipsH = #self.spans > 0 and (cy - GROUP_GAP + Theme.space.md) or 0
    return y + chipsH + (#self.spans > 0 and 0 or Theme.space.xs)
  end
  return row
end

-- groups: G.GroupByProfession of the chips of the zone. onGroup(prof, on) switches a whole group.
local function paintZoneRow(row, z, groups, onMap, onChip, onGroup)
  row.onMap = onMap
  row.title:SetText(z.name)
  local levels = z.lmin and string.format(L["gather.levels"], z.lmin, z.lmax or z.lmin) or L["gather.city"]
  row.meta:SetText(levels .. " · " .. string.format(L["gather.spots"], z.total))
  local n = 0
  row.spans = {}
  for g, group in ipairs(groups) do
    local label = row.labels[g]
    if not label then
      label = createGroupLabel(row)
      row.labels[g] = label
    end
    local lit = 0
    for _, d in ipairs(group.items) do
      lit = lit + (d.on and 1 or 0)
    end
    label.prof = group.prof
    label.text:SetText(string.format(L["gather.groupLabel"], R.Name(group.prof), lit, group.count))
    -- A click turns the group off when every chip of it is on, else every chip of it on.
    label.onToggle = function()
      onGroup(group.prof, lit < group.count)
    end
    label:Show()
    local first = n + 1
    for _, d in ipairs(group.items) do
      n = n + 1
      local chip = row.chips[n]
      if not chip then
        chip = createChip(row)
        row.chips[n] = chip
      end
      paintChip(chip, d, function()
        onChip(d.id)
      end)
      chip:Show()
    end
    row.spans[g] = { first = first, last = n }
  end
  for i = n + 1, #row.chips do
    row.chips[i]:Hide()
  end
  for g = #groups + 1, #row.labels do
    row.labels[g]:Hide()
  end
  row.shown = n
end

-- Page ---------------------------------------------------------------------------------------------

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = { prof = "all", query = "", mine = false, zone = "all", faction = "all" }
  ns.PageState.Bind(view, state, { "prof", "query", "mine", "zone", "faction" })
  -- Items the player picked in the filter window, kept while the page lives.
  local selected = {}
  -- What the last refresh showed: the items of the list, the zones of the list below.
  local items, zones, itemOrder = {}, {}, {}
  local data
  local refresh, setSelected, afterSelection

  ns.AddIntro(view, "gather.intro")
  local source = ns.AddParagraph(view, "gather.source", { role = "micro", color = "textMuted", gap = Theme.space.xs })
  local hint = ns.AddParagraph(view, nil, { role = "ui", color = "warning", gap = Theme.space.md })
  -- Instead of the hint while the data add-on is off or missing: the button that switches it on.
  local banner = ns.PackageUI.Banner(view.content, Data.ADDON, {
    onLoaded = function()
      refresh(true)
    end,
    onResize = function()
      view:Layout()
    end,
  })
  s:Add(banner, { gap = Theme.space.md })

  -- Controls, wrapped to the width: search, profession, zone, own skill, reset.
  local professionOptions = { { value = "all", key = "gather.professionAll" } }
  for _, prof in ipairs(G.PROFESSIONS) do
    professionOptions[#professionOptions + 1] = { value = prof, text = R.Name(prof) }
  end
  local zoneOptions = { { value = "all", key = "gather.zoneAll" } }
  local search
  local function clearFilters()
    state.prof, state.zone, state.faction, state.mine = "all", "all", "all", false
    state.query = ""
    search.edit:SetText("")
    refresh(false)
  end
  local filters = K.FilterBar(view.content, {
    count = function()
      return (state.prof ~= "all" and 1 or 0)
        + (state.zone ~= "all" and 1 or 0)
        + (state.faction ~= "all" and 1 or 0)
        + (state.mine and 1 or 0)
        + (state.query ~= "" and 1 or 0)
    end,
    reset = clearFilters,
    resetTip = "gather.resetTip",
  })
  search = filters:AddSearch({
    key = "gather.search",
    text = state.query,
    placeholder = "gather.searchPh",
    onChange = function(text)
      state.query = text
      refresh(false)
    end,
  })
  local professionDd = filters:AddDropdown({
    key = "gather.profession",
    options = professionOptions,
    tooltip = "gather.profession",
    tooltipText = "gather.professionTip",
    get = function()
      return state.prof
    end,
    set = function(v)
      state.prof = v
      refresh(false)
    end,
  })
  local zoneDd = filters:AddDropdown({
    key = "gather.zone",
    width = 220,
    options = zoneOptions,
    tooltip = "gather.zone",
    tooltipText = "gather.zoneTip",
    get = function()
      return state.zone
    end,
    set = function(v)
      state.zone = v
      refresh(false)
    end,
  })
  local factionButtons = filters:AddGroup(K.FactionButtons(filters, {
    withAll = true,
    get = function()
      return state.faction
    end,
    set = function(v)
      state.faction = v
      refresh(false)
    end,
  }))
  local mine = filters:AddToggle({
    key = "gather.mine",
    tooltip = "gather.mine",
    tooltipText = "gather.mineTip",
    get = function()
      return state.mine
    end,
    set = function(v)
      state.mine = v
      refresh(false)
    end,
  })
  s:Add(filters, { gap = Theme.space.md })
  K.Anchor("FG.Gathering.Controls", filters)

  local itemsHead = ns.AddHeading(view, "gather.itemsHeading")
  local bar = CreateFrame("Frame", nil, view.content)
  -- One button per profession: it shows how many of its items are picked and opens the filter window.
  local pickers = {}
  local function itemsOf(prof)
    local out = {}
    for _, e in ipairs(items) do
      if e.prof == prof then
        out[#out + 1] = {
          id = e.id,
          prof = prof,
          name = e.name,
          icon = G.IconPath(e.id, e),
          skill = e.skill,
          sub = string.format(L["gather.filter.skill"], e.skill),
          tip = string.format(L["gather.itemZones"], e.zones),
        }
      end
    end
    return out
  end
  local function isPicked(id)
    return selected[id] == true
  end
  for _, prof in ipairs(G.PROFESSIONS) do
    local key = "gather.win.t." .. prof
    local b = W.Button(bar, {
      text = "",
      width = 120,
      height = BUTTON_H,
      tooltip = key,
      tooltipText = "gather.win.openTip",
      opens = true,
      onClick = function()
        ns.GatherPick.Open({
          title = key,
          hint = "gather.spots.hint." .. prof,
          entries = function()
            return itemsOf(prof)
          end,
          isOn = isPicked,
          setMany = function(ids, on)
            for _, id in ipairs(ids) do
              setSelected(id, on)
            end
            afterSelection()
          end,
          canGather = ns.GatherPick.SkillGate(),
        })
      end,
    })
    b.fgProf = prof
    pickers[prof] = b
  end
  local selectedText = W.Meta(bar, { wrap = true })
  function bar:fgGridLayout(width)
    local x, y = 0, 0
    for _, prof in ipairs(G.PROFESSIONS) do
      local b = pickers[prof]
      if b:IsShown() then
        local w = math.min(b:GetWidth(), width)
        b:SetWidth(w)
        if x > 0 and x + w > width then
          x, y = 0, y + BUTTON_H + 6
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, -y)
        x = x + w + 8
      end
    end
    selectedText:ClearAllPoints()
    selectedText:SetPoint("TOPLEFT", 0, -(y + BUTTON_H + 6))
    selectedText:SetWidth(math.max(40, width))
    local h = y + BUTTON_H + 6 + selectedText:GetStringHeight()
    self:SetHeight(h)
    return h
  end
  s:Add(bar, { gap = Theme.space.lg })
  local empty = view.stack:Add(
    W.EmptyState(view.content, { text = "gather.empty", icon = "search", compact = true }),
    { gap = Theme.space.lg }
  )

  local zonesHead = ns.AddHeading(view, "gather.zonesHeading")
  local total = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = Theme.space.sm })
  local zoneList = K.RowPool(view.content, createZoneRow, { cards = { minWidth = CARD_MIN_W, gap = Theme.space.md } })
  s:Add(zoneList, { gap = Theme.space.sm })
  K.Anchor("FG.Gathering.Zones", zoneList)
  local noZones = ns.AddParagraph(view, "gather.noZones", { role = "ui" })

  -- Selection ----------------------------------------------------------------------------------------

  -- A switched item reaches the zones that already hold a choice of their own, so an item picked later
  -- shows up there as well. Zones without a choice follow the list.
  function setSelected(id, on)
    selected[id] = on or nil
    for _, z in ipairs(G.Zones(data, { id }, { faction = state.faction })) do
      if Sel.Has(z.mapId) then
        Sel.SetItem(z.mapId, id, on)
      end
    end
  end

  -- The items the zone list is built for: the picked ones of the list, else every item of the list.
  local function activeIds()
    local ids, picked = {}, false
    for _, e in ipairs(items) do
      if selected[e.id] then
        picked = true
        ids[#ids + 1] = e.id
      end
    end
    if not picked then
      ids = {}
      for _, e in ipairs(items) do
        ids[#ids + 1] = e.id
      end
    end
    return ids, picked
  end

  local function chipsOf(z)
    local chips, stored = {}, Sel.Has(z.mapId)
    local on = Sel.Get(z.mapId)
    for id in pairs(z.counts) do
      local item = data.items[id]
      chips[#chips + 1] = {
        id = id,
        prof = item.prof,
        name = G.ItemName(id, item),
        icon = item.icon,
        count = z.counts[id],
        on = not stored or on[id] == true,
      }
    end
    table.sort(chips, function(a, b)
      local oa, ob = itemOrder[a.id] or math.huge, itemOrder[b.id] or math.huge
      if oa ~= ob then
        return oa < ob
      end
      return a.id < b.id
    end)
    return chips
  end

  -- The first click or the Map button turns the default (everything on) into a stored choice.
  local function store(z)
    if not Sel.Has(z.mapId) then
      for _, d in ipairs(chipsOf(z)) do
        Sel.SetItem(z.mapId, d.id, d.on)
      end
    end
  end

  local function paintZones()
    zoneList:Sync(zones, function(row, z)
      paintZoneRow(row, z, G.GroupByProfession(chipsOf(z)), function()
        store(z)
        K.PlaceOnMap({ map = z.mapId, label = z.name, zone = z.name })
      end, function(id)
        store(z)
        Sel.SetItem(z.mapId, id, not Sel.Get(z.mapId)[id])
        paintZones()
        view:Layout()
      end, function(prof, on)
        -- One stored choice with the group changed, so the map reacts once.
        local set = {}
        for _, d in ipairs(chipsOf(z)) do
          if d.prof == prof then
            set[d.id] = on
          else
            set[d.id] = d.on
          end
        end
        Sel.Set(z.mapId, set)
        paintZones()
        view:Layout()
      end)
    end)
  end

  local function paintCounts()
    local ids, picked = activeIds()
    if picked then
      selectedText:SetText(string.format(L["gather.selected"], #ids, #items))
    else
      selectedText:SetText(L["gather.noneSelected"])
    end
    total:SetText(string.format(L["gather.total"], #ids, #zones))
    W.SetCount(itemsHead, #items)
    W.SetCount(zonesHead, #zones)
    for _, prof in ipairs(G.PROFESSIONS) do
      local b = pickers[prof]
      local entries = itemsOf(prof)
      b:SetShown(#entries > 0)
      W.SetText(b.label, nil, R.Name(prof) .. ": " .. ns.GatherPick.ButtonText(entries, isPicked))
      b:SetWidth(b:Fit())
    end
  end

  function afterSelection()
    local ids = activeIds()
    zones = G.Zones(data, ids, { faction = state.faction })
    if state.zone ~= "all" then
      local only = {}
      for _, z in ipairs(zones) do
        if z.mapId == state.zone then
          only[#only + 1] = z
        end
      end
      zones = only
    end
    paintCounts()
    paintZones()
    noZones:SetShown(data ~= nil and #items > 0 and #zones == 0)
    zoneList:SetShown(#zones > 0)
    view:Layout()
  end

  -- Reading and filtering -------------------------------------------------------------------------------

  local function fillZoneOptions()
    for i = #zoneOptions, 2, -1 do
      zoneOptions[i] = nil
    end
    for _, z in ipairs(G.Zones(data, nil, { faction = state.faction })) do
      zoneOptions[#zoneOptions + 1] = {
        value = z.mapId,
        text = z.lmin and string.format(L["gather.zoneOption"], z.name, z.lmin, z.lmax or z.lmin) or z.name,
      }
    end
    local known = state.zone == "all"
    for _, o in ipairs(zoneOptions) do
      known = known or o.value == state.zone
    end
    if not known then
      state.zone = "all"
    end
  end

  -- reload: read the data again (page opened, add-on switched on), else only a filter changed.
  function refresh(reload)
    local missing, status
    if reload ~= false or not data then
      local got, st = Data.Get()
      data = got
      missing, status = st == Data.STATUS.missing, st
    end
    for _, o in ipairs(professionOptions) do
      if o.text then
        o.text = R.Name(o.value)
      end
    end
    local offered = banner:Update(data == nil and missing == true)
    hint:SetShown(data == nil and not offered)
    if not data then
      hint:SetText(Data.Hint(status))
      items, zones, itemOrder = {}, {}, {}
      zoneList:Sync(zones, function() end)
    else
      fillZoneOptions()
      local skills, own = nil, nil
      if state.mine then
        skills = ns.GatherPick.OwnSkills()
        own = next(skills) ~= nil
      end
      items = G.Items(data, {
        prof = state.prof,
        search = state.query,
        skills = skills,
        zone = state.zone ~= "all" and state.zone or nil,
        faction = state.faction,
      })
      itemOrder = {}
      for i, e in ipairs(items) do
        itemOrder[e.id] = i
      end
      local noSkill = state.mine and own == false
      empty:SetTexts(noSkill and "gather.noProfession" or "gather.empty")
      empty:SetAction(not noSkill and W.EMPTY_RESET or nil, function()
        filters:Reset()
      end)
      empty:SetShown(#items == 0)
    end
    professionDd.Refresh()
    zoneDd.Refresh()
    mine.Refresh()
    factionButtons.Refresh()
    filters:Refresh()
    local shown = data ~= nil
    for _, f in ipairs({ source, filters, itemsHead, bar, zonesHead, total }) do
      f:SetShown(shown)
    end
    if not shown then
      empty:Hide()
      noZones:Hide()
      zoneList:Hide()
      view:Layout()
      return
    end
    afterSelection()
  end

  -- Page link: the picked item when it is exactly one.
  function view:ShareState()
    local id = next(selected)
    return id and not next(selected, id) and { id } or {}
  end

  -- params[1] = item id or name (deep link, /fg erze <item>): the filters are cleared and only this item
  -- is picked. An unknown value is ignored.
  function view:Show(params)
    local got = Data.Get()
    local id = got and params and params[1] and G.FindItem(got, params[1])
    if id then
      state.prof, state.zone, state.faction, state.mine, state.query = "all", "all", "all", false, ""
      search.edit:SetText("")
      selected = {}
      selected[id] = true
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
  id = "gathering",
  order = 440,
  group = "professions",
  title = "page.gathering",
  subtitle = "page.gathering.sub",
  icon = ns.ICONS.gathering,
  aliases = { "sammelpunkte", "erze", "kraeuter", "kräuter", "gathering", "nodes", "farmen", "farm", "ore", "herbs" },
  crumbLabel = function(param)
    local got = rawget(ns, "GatherData")
    local id = got and G.FindItem(got, param)
    return id and G.ItemName(id, got.items[id]) or param
  end,
  build = build,
})
