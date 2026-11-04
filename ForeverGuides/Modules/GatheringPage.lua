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
  ["gather.reset"] = "Reset filters",
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
  ["gather.reset"] = "Filter zurücksetzen",
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
  ["gather.groupZoneTip"] = "Klick schaltet alle %s-Items dieses Gebiets an oder aus.",
  ["gather.total"] = "Items: %d, Gebiete: %d",
  ["gather.levels"] = "Stufen %d-%d",
  ["gather.city"] = "Stadt",
  ["gather.spots"] = "Fundorte: %d",
  ["gather.map"] = "Karte",
  ["gather.mapTip"] = "Zeigt das Gebiet auf der Karte mit den eingeschalteten Items.",
  ["gather.chipTip"] = "Fundorte: %d. Klick schaltet das Item für das Gebiet an oder aus.",
  ["gather.chipOn"] = "An",
  ["gather.chipOff"] = "Aus",
  ["gather.empty"] = "Keine Items für diesen Filter.",
  ["gather.noProfession"] = "Kein Bergbau und keine Kräuterkunde bei diesem Charakter gefunden.",
  ["gather.noZones"] = "Keine Gebiete für diese Auswahl.",
})

local ITEM_ROW_H = 44
local ITEM_ROWS = 8
local ICON = 28
local CONTROL_W = 200
local FIELD_W = 220
local CHECK_W = 260
local RESET_W = 160
local CONTROL_GAP = 12
local CONTROL_H = 46
local BUTTON_H = 24
local MAP_W = 90
local CHIP_ICON = 20
local CHIP_PAD = 6
local CHIP_GAP_X = 10
local CHIP_GAP_Y = 6
local LABEL_H = 18
local GROUP_GAP = 6

-- The own skill per profession of the data ({ mining = n, herbalism = n }), only the professions the
-- character has.
local function ownSkills()
  local skills = {}
  local shop = ns.ProfessionShop
  for _, p in ipairs(shop and shop.Own() or {}) do
    for _, prof in ipairs(G.PROFESSIONS) do
      if p.slug == prof then
        skills[prof] = p.skill
      end
    end
  end
  return skills
end

-- Item rows ----------------------------------------------------------------------------------------

local function showItemTip(row)
  local e = row.entry
  if e then
    ns.ShowTooltip(row, e.name, string.format(L["gather.itemTip"], e.skill))
  elseif row.header then
    ns.ShowTooltip(row, row.header.name, L["gather.groupTip"])
  end
end

local function createItemRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetClipsChildren(true)
  row:SetScript("OnEnter", showItemTip)
  row:SetScript("OnLeave", ns.HideTooltip)
  -- The head row of a profession group is this same row with the plate on.
  row.headBg = W.Fill(row, "surface2", 0.6)
  K.RowHover(row)
  row.box = CreateFrame("Frame", nil, row)
  row.box:SetSize(16, 16)
  row.box:SetPoint("LEFT", 8, 0)
  W.Fill(row.box, "surface2")
  row.boxOn = W.Fill(row.box, "action", 1)
  row.boxBorder = W.Border(row.box, "white", 0.4)
  row.check = W.CheckMark(row.box, 12, "text")
  row.check:SetPoint("CENTER")
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.count = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
  row.count:SetPoint("RIGHT", -8, 0)
  row.title = W.Text(row, { role = "ui" })
  row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
  row.title:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
  row.sub = W.Text(row, { role = "micro", color = "textSecondary" })
  row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
  row.sub:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  ns.Bind(row, function()
    row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)
  row:SetScript(
    "OnClick",
    ns.Wrap("gather-item", function()
      if row.onToggle then
        row.onToggle()
      end
    end)
  )
  ns.Focus.register(row, function(self)
    self:Click()
  end)
  -- Keyboard focus shows the same tooltip as the mouse, so the head row explains itself without one.
  row.fgOnFocus = showItemTip
  row.fgOnBlur = ns.HideTooltip
  return row
end

local function paintItemRow(row, entry, on, onToggle)
  row.entry, row.header, row.onToggle = entry, nil, onToggle
  row.headBg:Hide()
  row.icon:Show()
  W.SetColor(row.title, "text")
  row.icon:SetTexture(G.IconPath(entry.id, entry))
  row.title:SetText(entry.name)
  row.sub:SetText(string.format(L["gather.itemSub"], R.Name(entry.prof), entry.skill))
  row.count:SetText(string.format(L["gather.itemZones"], entry.zones))
  row.check:SetShown(on)
  row.boxOn:SetShown(on)
  row.boxBorder.set(on and "actionHi" or "white", on and 1 or 0.4)
  row.paintHover()
end

-- Head row of a profession group: a box that is full when every item of the group is picked, the name of
-- the profession, how many of its items are picked and the number of items. The entry is
-- { header, prof, name, count, items }.
local function paintHeaderRow(row, entry, picked, onToggle)
  row.entry, row.header, row.onToggle = nil, entry, onToggle
  row.headBg:Show()
  row.icon:Hide()
  W.SetColor(row.title, "accent2")
  row.title:SetText(entry.name)
  row.sub:SetText(string.format(L["gather.selected"], picked, entry.count))
  row.count:SetText(string.format(L["gather.groupCount"], entry.count))
  local all = picked == entry.count
  row.check:SetShown(all)
  row.boxOn:SetShown(all)
  row.boxBorder.set(picked > 0 and "actionHi" or "white", picked > 0 and 1 or 0.4)
  row.paintHover()
end

-- Zone rows ----------------------------------------------------------------------------------------

local function createChip(parent)
  local chip = CreateFrame("Button", nil, parent)
  W.Fill(chip, "surface2")
  chip.onBg = W.Fill(chip, "action", 0.35)
  chip.border = W.Border(chip, "white", 0.25)
  local hover = chip:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.08)
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
      ns.ShowTooltip(self, d.name, string.format(L["gather.chipTip"], d.count))
    end
  end)
  chip:SetScript("OnLeave", ns.HideTooltip)
  chip:SetScript(
    "OnClick",
    ns.Wrap("gather-chip", function(self)
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
  hover:SetColorTexture(1, 1, 1, 0.08)
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
  local row = CreateFrame("Frame", nil, parent)
  row.title = W.Text(row, { role = "ui", color = "accent2", wrap = true })
  row.meta = W.Text(row, { role = "micro", color = "textMuted", wrap = true })
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
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  ns.Bind(row, function()
    row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)
  function row:fgLayout(width)
    local inner = math.max(40, width - 16)
    self.map:ClearAllPoints()
    self.map:SetPoint("TOPRIGHT", -8, -8)
    local textW = math.max(40, inner - MAP_W - 8)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", 8, -10)
    self.title:SetWidth(textW)
    local y = 10 + math.max(self.title:GetStringHeight(), 14) + 2
    self.meta:ClearAllPoints()
    self.meta:SetPoint("TOPLEFT", 8, -y)
    self.meta:SetWidth(textW)
    y = math.max(y + self.meta:GetStringHeight() + 6, 8 + BUTTON_H + 6)
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
      label:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -(y + cy))
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
        chip:SetPoint("TOPLEFT", self, "TOPLEFT", 8 + x, -(y + cy))
        chip:SetSize(w, chipH)
        x = x + w + CHIP_GAP_X
      end
      cy = cy + chipH + GROUP_GAP
    end
    local chipsH = #self.spans > 0 and (cy - GROUP_GAP + 8) or 0
    return y + chipsH + 1
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
  -- Items the player picked in the list, kept while the page lives.
  local selected = {}
  -- What the last refresh showed: the items of the list, the zones of the list below.
  local items, zones, itemOrder = {}, {}, {}
  -- The rows of the item list (a head row per profession, then its items) and the row of each item.
  local rows, rowOf = {}, {}
  local data
  local refresh, setSelected, afterSelection

  ns.AddParagraph(view, "gather.intro")
  local source = ns.AddParagraph(view, "gather.source", { role = "micro", color = "textMuted", gap = 4 })
  local hint = ns.AddParagraph(view, nil, { role = "ui", color = "warning", gap = 12 })
  -- Instead of the hint while the data add-on is off or missing: the button that switches it on.
  local banner = ns.PackageUI.Banner(view.content, Data.ADDON, {
    onLoaded = function()
      refresh(true)
    end,
    onResize = function()
      view:Layout()
    end,
  })
  s:Add(banner, { gap = 12 })

  -- Controls, wrapped to the width: search, profession, zone, own skill, reset.
  local professionOptions = { { value = "all", key = "gather.professionAll" } }
  for _, prof in ipairs(G.PROFESSIONS) do
    professionOptions[#professionOptions + 1] = { value = prof, text = R.Name(prof) }
  end
  local zoneOptions = { { value = "all", key = "gather.zoneAll" } }
  local controls = CreateFrame("Frame", nil, view.content)
  local searchBox = CreateFrame("Frame", nil, controls)
  searchBox:SetSize(FIELD_W, CONTROL_H)
  W.Text(searchBox, { key = "gather.search", role = "ui" }):SetPoint("TOPLEFT")
  local search = W.EditBox(searchBox, {
    placeholder = "gather.searchPh",
    clear = true,
    onChange = function(text)
      state.query = text
      refresh(false)
    end,
  })
  search:SetPoint("TOPLEFT", 0, -18)
  search:SetWidth(FIELD_W)
  local professionDd = W.Dropdown(controls, {
    key = "gather.profession",
    width = CONTROL_W,
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
  professionDd:SetWidth(CONTROL_W)
  local zoneDd = W.Dropdown(controls, {
    key = "gather.zone",
    width = FIELD_W,
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
  zoneDd:SetWidth(FIELD_W)
  local mine = W.Checkbox(controls, {
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
  mine:SetWidth(CHECK_W)
  local reset = W.Button(controls, {
    key = "gather.reset",
    width = RESET_W,
    height = BUTTON_H,
    tooltip = "gather.reset",
    tooltipText = "gather.resetTip",
    onClick = function()
      state.prof, state.zone, state.faction, state.mine = "all", "all", "all", false
      state.query = ""
      search.edit:SetText("")
      refresh(false)
    end,
  })
  -- The checkbox and the button sit level with the fields, not with their captions.
  local controlItems = {
    { frame = searchBox },
    { frame = professionDd },
    { frame = zoneDd },
    { frame = mine, dy = CONTROL_H - 22 },
    { frame = reset, dy = CONTROL_H - BUTTON_H },
  }
  function controls:fgGridLayout(width)
    local x, y = 0, 0
    for _, item in ipairs(controlItems) do
      local w = item.frame:GetWidth()
      if x > 0 and x + w > width then
        x, y = 0, y + CONTROL_H + 8
      end
      item.frame:ClearAllPoints()
      item.frame:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(y + (item.dy or 0)))
      x = x + w + CONTROL_GAP
    end
    local h = y + CONTROL_H
    self:SetHeight(h)
    return h
  end
  s:Add(controls, { gap = 10 })
  K.Anchor("FG.Gathering.Controls", controls)

  local factionButtons = K.FactionButtons(view.content, {
    withAll = true,
    get = function()
      return state.faction
    end,
    set = function(v)
      state.faction = v
      refresh(false)
    end,
  })
  s:Add(factionButtons, { gap = 10 })

  local itemsHead = ns.AddHeading(view, "gather.itemsHeading")
  local bar = CreateFrame("Frame", nil, view.content)
  local selectAll = W.Button(bar, {
    key = "gather.all",
    width = 120,
    height = BUTTON_H,
    tooltip = "gather.all",
    tooltipText = "gather.allTip",
    onClick = function()
      for _, e in ipairs(items) do
        setSelected(e.id, true)
      end
      afterSelection()
    end,
  })
  local selectNone = W.Button(bar, {
    key = "gather.none",
    width = 120,
    height = BUTTON_H,
    tooltip = "gather.none",
    tooltipText = "gather.noneTip",
    onClick = function()
      for _, e in ipairs(items) do
        setSelected(e.id, false)
      end
      afterSelection()
    end,
  })
  local selectedText = W.Text(bar, { role = "micro", color = "textMuted", wrap = true })
  function bar:fgGridLayout(width)
    selectAll:ClearAllPoints()
    selectAll:SetPoint("TOPLEFT", 0, 0)
    selectNone:ClearAllPoints()
    selectNone:SetPoint("LEFT", selectAll, "RIGHT", 8, 0)
    local textX = 2 * 120 + 16
    local textW = width - textX
    if textW < 120 then
      selectedText:ClearAllPoints()
      selectedText:SetPoint("TOPLEFT", 0, -(BUTTON_H + 6))
      selectedText:SetWidth(math.max(40, width))
      local h = BUTTON_H + 6 + selectedText:GetStringHeight()
      self:SetHeight(h)
      return h
    end
    selectedText:ClearAllPoints()
    selectedText:SetPoint("TOPLEFT", textX, -5)
    selectedText:SetWidth(textW)
    local h = math.max(BUTTON_H, 5 + selectedText:GetStringHeight())
    self:SetHeight(h)
    return h
  end
  s:Add(bar, { gap = 8 })

  local list = W.ScrollList(view.content, {
    rowHeight = K.scaledHeight(ITEM_ROW_H),
    createRow = createItemRow,
    bindRow = function(row, entry)
      if entry.header then
        local function picked()
          local n = 0
          for _, e in ipairs(entry.items) do
            n = n + (selected[e.id] and 1 or 0)
          end
          return n
        end
        paintHeaderRow(row, entry, picked(), function()
          local on = picked() < entry.count
          for _, e in ipairs(entry.items) do
            setSelected(e.id, on)
          end
          afterSelection()
        end)
        return
      end
      paintItemRow(row, entry, selected[entry.id] == true, function()
        setSelected(entry.id, selected[entry.id] ~= true)
        afterSelection()
      end)
    end,
  })
  function list:fgGridLayout()
    local h = K.scaledHeight(ITEM_ROW_H) * ITEM_ROWS
    self:SetHeight(h)
    return h
  end
  s:Add(list, { gap = 14 })
  K.Anchor("FG.Gathering.Items", list)
  local empty = ns.AddParagraph(view, nil, { role = "ui", gap = 14 })

  local zonesHead = ns.AddHeading(view, "gather.zonesHeading")
  local total = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = 6 })
  local zoneList = K.RowPool(view.content, createZoneRow)
  s:Add(zoneList, { gap = 8 })
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
  end

  -- Head rows and items of the list in the order of the professions.
  local function buildRows()
    rows, rowOf = {}, {}
    for _, g in ipairs(G.GroupByProfession(items)) do
      rows[#rows + 1] = { header = true, prof = g.prof, name = R.Name(g.prof), count = g.count, items = g.items }
      for _, e in ipairs(g.items) do
        rows[#rows + 1] = e
        rowOf[e.id] = #rows
      end
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
    list:SetData(rows)
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
      buildRows()
      list:SetData(rows)
      zoneList:Sync(zones, function() end)
    else
      fillZoneOptions()
      local skills, own = nil, nil
      if state.mine then
        skills = ownSkills()
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
      buildRows()
      empty:SetText(L[state.mine and own == false and "gather.noProfession" or "gather.empty"])
      empty:SetShown(#items == 0)
    end
    professionDd.Refresh()
    zoneDd.Refresh()
    mine.Refresh()
    factionButtons.Refresh()
    local shown = data ~= nil
    for _, f in ipairs({ source, controls, factionButtons, itemsHead, bar, list, zonesHead, total }) do
      f:SetShown(shown)
    end
    if not shown then
      empty:Hide()
      noZones:Hide()
      zoneList:Hide()
      view:Layout()
      return
    end
    list:SetShown(#items > 0)
    afterSelection()
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
    if id then
      if rowOf[id] then
        list:Reveal(rowOf[id])
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
  id = "gathering",
  order = 440,
  group = "professions",
  title = "page.gathering",
  icon = ns.ICONS.gathering,
  aliases = { "sammelpunkte", "erze", "kraeuter", "kräuter", "gathering", "nodes", "farmen", "farm", "ore", "herbs" },
  crumbLabel = function(param)
    local got = rawget(ns, "GatherData")
    local id = got and G.FindItem(got, param)
    return id and G.ItemName(id, got.items[id]) or param
  end,
  build = build,
})
