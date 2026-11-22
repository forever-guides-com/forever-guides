-- Shared view helpers of the guide pages (group "guides"): data loading, bracket rows as a step timeline with waypoint
-- buttons, the unconfirmed marker, the "data follows" state and the faction filter. Logic lives in
-- GuideKitLogic. GK.Build(spec) makes the page of one guide; a guide with its own layout passes
-- spec.render(view, data, ctx) and reuses the parts.
local _, ns = ...
local W, L, Theme, K, GL = ns.W, ns.L, ns.Theme, ns.PageKit, ns.GuideKitLogic

local GK = {}
ns.GuideKit = GK
ns.GuideData = ns.GuideData or {}

ns.AddLocale("enUS", {
  ["guidekit.unconfirmed"] = "Unconfirmed",
  ["guidekit.unconfirmedTip"] = "This value has not been checked in Forever yet and may differ.",
  ["guidekit.follows"] = "Data follows",
  ["guidekit.followsHint"] = "The data for this guide is not available yet.",
  ["guidekit.disabled"] = "The data addon is switched off",
  ["guidekit.disabledHint"] = "Switch it on to see this guide.",
  ["guidekit.noData"] = "No data found",
  ["guidekit.noDataHint"] = "The data addon is installed. It holds no usable data.",
  ["guidekit.noRows"] = "No entries for this faction.",
  ["guidekit.position"] = "Position %s",
  ["guidekit.placeLine"] = "%s, %s",
  ["guidekit.mapTip"] = "Shows the zone on the map",
  ["guidekit.markerTip"] = "Sets a waypoint here",
  ["guidekit.rangeLevel"] = "Level %s",
  ["guidekit.showChests"] = "Show on map",
  ["guidekit.chestsTip"] = "Switches these chests on in the map filter and opens the map:",
  ["guidekit.chestLine"] = "%s (lockpicking skill %d)",
  ["guidekit.nextStep"] = "Next step",
  ["guidekit.skillLine"] = "%s: %d of %d",
  ["guidekit.skillLineOpen"] = "%s: %d",
  ["guidekit.skillNone"] = "%s: not learned",
  ["guidekit.allDone"] = "Nothing left in this list for your current skill.",
  ["guidekit.state.current"] = "Current",
  ["guidekit.state.done"] = "Done",
  ["guidekit.collect.handed"] = "Handed in",
  ["guidekit.collect.read"] = "Read",
  ["guidekit.markRead"] = "Mark as read",
  ["guidekit.collect.bag"] = "In bags",
  ["guidekit.collect.bank"] = "In the bank",
  ["guidekit.collect.missing"] = "Missing",
  ["guidekit.collect.open"] = "Open",
  ["guidekit.collect.count"] = "%d/%d handed in",
  ["guidekit.collect.summary"] = "%s: %d/%d handed in",
  ["guidekit.group.count"] = "%d / %d handed in",
  ["guidekit.col.status"] = "Status",
  ["guidekit.col.range"] = "Range",
  ["guidekit.col.target"] = "Target",
  ["guidekit.col.title"] = "Title",
  ["guidekit.col.territory"] = "Territory",
  ["guidekit.col.zone"] = "Zone / Coordinates",
  ["guidekit.col.actions"] = "Actions",
})
ns.AddLocale("deDE", {
  ["guidekit.unconfirmed"] = "Unbestätigt",
  ["guidekit.unconfirmedTip"] = "Dieser Wert ist in Forever noch nicht geprüft und kann abweichen.",
  ["guidekit.follows"] = "Daten folgen",
  ["guidekit.followsHint"] = "Die Daten für diese Anleitung sind noch nicht verfügbar.",
  ["guidekit.disabled"] = "Das Datenaddon ist ausgeschaltet",
  ["guidekit.disabledHint"] = "Schalte es ein, um diese Anleitung zu sehen.",
  ["guidekit.noData"] = "Keine Daten gefunden",
  ["guidekit.noDataHint"] = "Das Datenaddon ist installiert. Es enthält keine nutzbaren Daten.",
  ["guidekit.noRows"] = "Keine Einträge für diese Fraktion.",
  ["guidekit.position"] = "Position %s",
  ["guidekit.placeLine"] = "%s, %s",
  ["guidekit.mapTip"] = "Zeigt das Gebiet auf der Karte",
  ["guidekit.markerTip"] = "Setzt hier einen Wegpunkt",
  ["guidekit.rangeLevel"] = "Stufe %s",
  ["guidekit.showChests"] = "Auf Karte zeigen",
  ["guidekit.chestsTip"] = "Schaltet diese Truhen im Kartenfilter ein und öffnet die Karte:",
  ["guidekit.chestLine"] = "%s (Schlossknacken ab %d)",
  ["guidekit.nextStep"] = "Nächster Schritt",
  ["guidekit.skillLine"] = "%s: %d von %d",
  ["guidekit.skillLineOpen"] = "%s: %d",
  ["guidekit.skillNone"] = "%s: nicht gelernt",
  ["guidekit.allDone"] = "Für deine aktuelle Fertigkeit steht in dieser Liste nichts mehr an.",
  ["guidekit.state.current"] = "Aktuell",
  ["guidekit.state.done"] = "Erledigt",
  ["guidekit.collect.handed"] = "Abgegeben",
  ["guidekit.collect.read"] = "Gelesen",
  ["guidekit.markRead"] = "Als gelesen markieren",
  ["guidekit.collect.bag"] = "In der Tasche",
  ["guidekit.collect.bank"] = "In der Bank",
  ["guidekit.collect.missing"] = "Fehlt",
  ["guidekit.collect.open"] = "Offen",
  ["guidekit.collect.count"] = "%d/%d abgegeben",
  ["guidekit.collect.summary"] = "%s: %d/%d abgegeben",
  ["guidekit.group.count"] = "%d / %d abgegeben",
  ["guidekit.col.status"] = "Status",
  ["guidekit.col.range"] = "Bereich",
  ["guidekit.col.target"] = "Ziel",
  ["guidekit.col.title"] = "Titel",
  ["guidekit.col.territory"] = "Gebiet",
  ["guidekit.col.zone"] = "Zone / Koordinaten",
  ["guidekit.col.actions"] = "Aktionen",
})

local STATUS_KEYS = {
  [GL.STATUS.missing] = { "guidekit.follows", "guidekit.followsHint" },
  [GL.STATUS.disabled] = { "guidekit.disabled", "guidekit.disabledHint" },
  [GL.STATUS.empty] = { "guidekit.noData", "guidekit.noDataHint" },
}

local attempted = {}

-- Data of a guide and its status (GL.STATUS). The add-on is loaded on the first call while it is
-- installed and switched on; a failed attempt is not repeated before the player switches it on.
function GK.Load(id)
  local cfg = GL.GUIDES[id]
  if not cfg then
    return nil, GL.STATUS.missing
  end
  local state = ns.PackageUI.State(cfg.addon)
  if not GL.IsValid(ns.GuideData[id]) and state == "idle" and not attempted[id] then
    attempted[id] = true
    ns.LoadPackage(cfg.addon)
    state = ns.PackageUI.State(cfg.addon)
  end
  local data = ns.GuideData[id]
  local status = GL.Status(state, data)
  return status == GL.STATUS.loaded and data or nil, status
end

-- Reads of the game for GL.CollectionStatus. Both APIs live in C_ tables or as globals depending on the client.
local function callApi(tableName, name, ...)
  local c = rawget(_G, tableName)
  local fn = type(c) == "table" and c[name] or rawget(_G, name)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, value = pcall(fn, ...)
  return ok and value or nil
end

GK.Probe = {
  quest = function(id)
    return callApi("C_QuestLog", "IsQuestFlaggedCompleted", id) == true
  end,
  count = function(id, withBank)
    local n = callApi("C_Item", "GetItemCount", id, withBank == true)
    return type(n) == "number" and n or 0
  end,
}

-- Small text tag with a tooltip, so the state is named in words and not by color alone.
function GK.UnconfirmedTag(parent)
  local tag = CreateFrame("Button", nil, parent)
  tag.label = W.Text(tag, { key = "guidekit.unconfirmed", role = "micro", color = "warning" })
  tag.label:SetPoint("LEFT")
  local function show()
    ns.ShowTooltip(tag, L["guidekit.unconfirmed"], L["guidekit.unconfirmedTip"])
  end
  tag:SetScript("OnEnter", show)
  tag:SetScript("OnLeave", ns.HideTooltip)
  tag:SetScript("OnClick", show)
  tag.fgOnFocus, tag.fgOnBlur = show, ns.HideTooltip
  ns.Focus.register(tag, show)
  tag:SetSize(math.max(18, tag.label:GetStringWidth()), math.max(18, tag.label:GetStringHeight()))
  return tag
end

-- Centered "data follows" state; GK.SetEmptyStatus switches its texts to another status.
function GK.EmptyState(parent, status)
  local keys = STATUS_KEYS[status] or STATUS_KEYS[GL.STATUS.missing]
  return W.EmptyState(parent, { text = keys[1], hint = keys[2], icon = "search" })
end

function GK.SetEmptyStatus(empty, status)
  local keys = STATUS_KEYS[status] or STATUS_KEYS[GL.STATUS.missing]
  empty:SetTexts(keys[1], keys[2])
end

local FACTION_KEY = { A = "kit.faction.A", H = "kit.faction.H" }
local PAD, ACTION_GAP, BUTTON_H = 8, 8, 24

-- Zone the chest button falls back to when the row has no map: the one of the player.
local function playerMap()
  if not (C_Map and C_Map.GetBestMapForUnit) then
    return nil
  end
  local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
  return ok and id or nil
end

-- Switches the chest kinds of a row on in the shared object filter and opens the map. Blizzard's map is never
-- touched in combat (docs/TAINT-AUDIT.md), the map page of the add-on opens then. Returns "opened", "page"
-- or nil (a row without chests).
function GK.ShowChests(row)
  local ids = GL.ObjectIds(row)
  if not ids then
    return nil
  end
  ns.GatherObjects.Reveal(ids)
  local mapId = GL.TargetMap(row, playerMap())
  local blizzard = not ns.InCombat() and (rawget(_G, "OpenWorldMap") or rawget(_G, "WorldMapFrame"))
  if not blizzard or not (ns.WorldMapLinks and ns.WorldMapLinks.Map()) then
    ns.MapRequest.Open({ map = mapId })
    return "page"
  end
  ns.Store.set("settings.worldMapPanelOpen", true)
  ns.Store.set("settings.worldMapPanelTab", "gather")
  if rawget(_G, "OpenWorldMap") then
    ns.MapOps.Record("OpenWorldMap", mapId)
    pcall(OpenWorldMap, mapId)
  else
    ns.MapOps.Record("WorldMapFrame:SetMapID", mapId)
    pcall(function()
      WorldMapFrame:Show()
      if mapId and WorldMapFrame.SetMapID then
        WorldMapFrame:SetMapID(mapId)
      end
    end)
  end
  return "opened"
end

-- Names of the chest kinds with the skill each one needs, one per line.
function GK.ChestLines(ids)
  local data = ns.GatherDataAccess.Get()
  local kinds = data and data.objects and data.objects.kinds or {}
  local lines = {}
  for i, id in ipairs(ids) do
    local name = ns.GatherObjects.Name(id, kinds[id])
    local skill = ns.GatherObjects.LockSkill(kinds[id])
    lines[i] = skill and string.format(L["guidekit.chestLine"], name, skill) or name
  end
  return table.concat(lines, "\n")
end

local function createChestButton(row)
  local b = W.Button(row, {
    key = "guidekit.showChests",
    height = BUTTON_H,
    onClick = function()
      GK.ShowChests(row.item and row.item.row)
    end,
  })
  local function show()
    local ids = GL.ObjectIds(row.item and row.item.row)
    if ids then
      local text = L["guidekit.chestsTip"] .. "\n" .. GK.ChestLines(ids)
      ns.ShowTooltip(b, L["guidekit.showChests"], text, { hint = L["action.opensWindow"] })
    end
  end
  b:HookScript("OnEnter", show)
  b:HookScript("OnLeave", ns.HideTooltip)
  b.fgOnFocus, b.fgOnBlur = show, ns.HideTooltip
  b.fgDescription = function()
    return L["action.opensWindow"]
  end
  return b
end

local BAR_H, DOT, TERRITORY_W = 4, 10, 28
local STATUS_W, RANGE_W, ACTIONS_W = 104, 72, W.MAP_ACTION_SIZE * 2 + W.MAP_ACTION_GAP
-- Colors per step state, the same roles as the step rows of the profession route.
local STATE_COLORS = {
  current = { title = "accent2", text = "text", range = "accent2" },
  done = { title = "textMuted", text = "textMuted", range = "textMuted" },
  open = { title = "text", text = "textSecondary", range = "text" },
}
STATE_COLORS.upcoming = STATE_COLORS.open

-- Status dot of a row state or collection status. The word beside the dot names the state, the shape of the
-- dot (disc, ring, dash) and its color only support it.
local STATE_DOT = { done = "done", current = "info", open = "todo", upcoming = "todo" }
GK.COLLECT_DOT = { handed = "done", read = "ok", bag = "info", bank = "warn", missing = "todo", open = "todo" }

-- Thin progress bar; bar:SetBarWidth(w) sets the width and draws the share kept in bar.share (0 to 1).
local function createBar(parent, height)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(height)
  bar.track = bar:CreateTexture(nil, "BACKGROUND")
  bar.track:SetAllPoints()
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill:SetPoint("TOPLEFT")
  bar.fill:SetPoint("BOTTOMLEFT")
  bar.share = 0
  ns.Bind(bar, function()
    bar.track:SetColorTexture(Theme.fillColor("selected"))
    bar.fill:SetColorTexture(Theme.color("accent2"))
  end)
  function bar:SetBarWidth(w)
    self:SetWidth(w)
    self.fill:SetWidth(math.max(1, math.floor(w * self.share)))
    self.fill:SetShown(self.share > 0)
  end
  return bar
end

-- Columns of a list, by what its rows carry (shared.hasStatus, hasRange, hasTerritory, titleKey). The row and
-- the column header read the same set, so the cells line up. Low priority columns drop first on a narrow page,
-- the row then stacks their content under the title.
local columnSets = {}
local function columnsFor(shared)
  local titleKey = shared.titleKey or "guidekit.col.target"
  local id = table.concat({
    shared.hasStatus and "s" or "-",
    shared.hasRange and "r" or "-",
    shared.hasTerritory and "t" or "-",
    titleKey,
  }, ":")
  if not columnSets[id] then
    local spec = {}
    if shared.hasStatus then
      spec[#spec + 1] = { id = "status", key = "guidekit.col.status", width = STATUS_W, priority = 3 }
    end
    if shared.hasRange then
      spec[#spec + 1] = { id = "range", key = "guidekit.col.range", width = RANGE_W, priority = 2 }
    end
    spec[#spec + 1] = { id = "title", key = titleKey, flex = 2, min = 110, priority = 7 }
    if shared.hasTerritory then
      spec[#spec + 1] = { id = "territory", key = "guidekit.col.territory", width = TERRITORY_W, align = "center", priority = 1 }
    end
    spec[#spec + 1] = { id = "zone", key = "guidekit.col.zone", flex = 2, min = 100, priority = 4 }
    spec[#spec + 1] = { id = "actions", key = "guidekit.col.actions", width = ACTIONS_W + 4, priority = 6 }
    columnSets[id] = K.Columns(spec)
  end
  return columnSets[id]
end

local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetClipsChildren(true)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.mark = row:CreateTexture(nil, "ARTWORK")
  row.mark:SetPoint("TOPLEFT")
  row.mark:SetPoint("BOTTOMLEFT")
  row.mark:SetWidth(3)
  row.actions = W.MapActionButtons(row, { mapTip = "guidekit.mapTip", markerTip = "guidekit.markerTip" })
  row.range = W.Text(row, { role = "ui" })
  row.bar = createBar(row, BAR_H)
  row.dot = K.StatusDot(row, {})
  row.state = W.Text(row, { role = "micro", wrap = true })
  row.crest = K.IconFrame(row, { size = 24 })
  row.title = W.Text(row, { role = "ui", wrap = true })
  row.place = W.Meta(row, { wrap = true })
  row.pos = W.Meta(row)
  row.tag = GK.UnconfirmedTag(row)
  row.chests = createChestButton(row)
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  ns.Bind(row, function()
    row.line:SetColorTexture(Theme.fillColor("line"))
  end)

  -- Zone, position, unconfirmed tag, chest button and mark box stacked in a column of width w; returns the
  -- bottom. Position, tag and chest button take a line of their own when the width is short.
  local function stackPlace(self, x, y, w, inner)
    local line = K.scaledHeight(14)
    self.place:ClearAllPoints()
    self.place:SetPoint("TOPLEFT", x, -y)
    self.place:SetWidth(w)
    y = y + math.max(self.place:GetStringHeight(), line) + 2
    local hasPos = (self.pos:GetText() or "") ~= ""
    self.pos:ClearAllPoints()
    self.pos:SetPoint("TOPLEFT", x, -y)
    local posH = hasPos and math.max(self.pos:GetStringHeight(), line) or 0
    if self.tag:IsShown() then
      local tagW = math.max(18, self.tag.label:GetStringWidth())
      local tagH = math.max(18, self.tag.label:GetStringHeight())
      local posW = hasPos and self.pos:GetStringWidth() + ACTION_GAP or 0
      self.tag:SetSize(tagW, tagH)
      self.tag:ClearAllPoints()
      if hasPos and posW + tagW > w then
        y = y + posH + 2
        self.tag:SetPoint("TOPLEFT", x, -y)
        y = y + tagH
      else
        self.tag:SetPoint("TOPLEFT", x + posW, -y)
        y = y + math.max(tagH, posH)
      end
    else
      y = y + posH
    end
    if self.chests:IsShown() then
      local need = math.ceil(self.chests.label:GetStringWidth()) + 2 * PAD + 4
      -- A label wider than the column starts at the left edge of the row, where the whole width is free.
      local left = need > w and PAD or x
      self.chests:SetWidth(math.min(need, inner - (left - PAD)))
      self.chests:ClearAllPoints()
      self.chests:SetPoint("TOPLEFT", left, -(y + 6))
      y = y + 6 + BUTTON_H
    end
    if self.readBox and self.readBox:IsShown() then
      self.readBox:ClearAllPoints()
      self.readBox:SetPoint("TOPLEFT", x, -(y + 6))
      self.readBox:SetWidth(math.min(w, 200))
      y = y + 6 + self.readBox:fgGridLayout(math.min(w, 200))
    end
    return y
  end

  -- Cells follow the columns of the list (status, range with progress, title, territory crest, zone with
  -- position, map buttons). A column that does not fit leaves the row, its content stacks under the title.
  function row:fgLayout(width)
    local inner = math.max(40, width - 2 * PAD)
    local lay = columnsFor(self.item.shared):Layout(inner)
    local function col(id)
      local c = lay.cols[id]
      return c and c.shown and c or nil
    end
    local line = K.scaledHeight(14)
    local top = 5
    local bottom = top + math.max(BUTTON_H, 24)
    local function put(fs, x, y, w)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", x, -y)
      fs:SetWidth(w)
    end
    local function dotAt(x, y)
      self.dot:ClearAllPoints()
      self.dot:SetPoint("TOPLEFT", x, -(y + math.floor((line - DOT) / 2)))
    end
    local hasState = self.state:IsShown()
    local status, range, title, crest, zone, actions =
      col("status"), col("range"), col("title"), col("territory"), col("zone"), col("actions")
    self.actions:ClearAllPoints()
    if actions then
      self.actions:SetPoint("TOPLEFT", PAD + actions.x + (actions.w - self.actions:GetWidth()), -top)
    else
      self.actions:SetPoint("TOPRIGHT", -PAD, -top)
    end
    if status and hasState then
      dotAt(PAD + status.x, top)
      put(self.state, PAD + status.x + DOT + 4, top, math.max(20, status.w - DOT - 4))
      bottom = math.max(bottom, top + math.max(self.state:GetStringHeight(), line))
    end
    if range then
      put(self.range, PAD + range.x, top, range.w)
      local by = top + math.max(self.range:GetStringHeight(), line) + 3
      if self.bar:IsShown() then
        self.bar:ClearAllPoints()
        self.bar:SetPoint("TOPLEFT", PAD + range.x, -by)
        self.bar:SetBarWidth(range.w)
        by = by + BAR_H + 4
      end
      bottom = math.max(bottom, by)
    else
      self.bar:Hide()
    end
    self.crest:SetShown(crest ~= nil and self.faction ~= nil)
    if crest then
      self.crest:ClearAllPoints()
      self.crest:SetPoint("TOP", self, "TOPLEFT", PAD + crest.x + crest.w / 2, -(top - 1))
      bottom = math.max(bottom, top + 28)
    end
    local tx = PAD + (title and title.x or 0)
    local tw = title and title.w or inner
    put(self.title, tx, top, tw)
    local y = top + math.max(self.title:GetStringHeight(), line) + 2
    if hasState and not status then
      dotAt(tx, y)
      put(self.state, tx + DOT + 4, y, math.max(20, tw - DOT - 4))
      y = y + math.max(self.state:GetStringHeight(), line)
    end
    if not range and (self.range:GetText() or "") ~= "" then
      put(self.range, tx, y, tw)
      y = y + math.max(self.range:GetStringHeight(), line)
    end
    self.place:SetText(crest and self.zoneText or self.placeText)
    if zone then
      bottom = math.max(bottom, stackPlace(self, PAD + zone.x, top, zone.w, inner))
    else
      y = stackPlace(self, tx, y, tw, inner)
    end
    return math.max(y, bottom) + 8
  end
  return row
end

-- item: row, section, rangeLabel, state (GL.RowState), value (skill or level of the player), collect (status of
-- GL.CollectionStatus, replaces state and names it in words), shared (table the rows of one list share, it
-- collects which columns the list needs).
local function paintRow(row, item)
  local r = item.row
  row.item = item
  -- The mark box is made on the first row that offers it (item.read = { get(row), set(row, on) }).
  if item.read and not row.readBox then
    row.readBox = W.Checkbox(row, {
      key = "guidekit.markRead",
      get = function()
        return row.item and row.item.read and row.item.read.get(row.item.row)
      end,
      set = function(on)
        if row.item and row.item.read then
          row.item.read.set(row.item.row, on)
        end
      end,
    })
  end
  if row.readBox then
    row.readBox:SetShown(item.read ~= nil)
    row.readBox:Refresh()
  end
  local status = item.collect and GL.COLLECT_STATE[item.collect] or item.state or "open"
  local colors = STATE_COLORS[status]
  local range = GL.RangeText(r.min, r.max)
  local key = range and item.rangeLabel and item.rangeLabel(item.section, r)
  if key then
    range = string.format(L[key], range)
  end
  row.range:SetText(range or "")
  W.SetColor(row.range, colors.range)
  local target = ns.T(r.target)
  row.title:SetText(target or "")
  W.SetColor(row.title, colors.title)
  local zone = ns.T(r.zone)
  local faction = FACTION_KEY[r.faction] and L[FACTION_KEY[r.faction]]
  row.zoneText = zone or ""
  row.placeText = zone and faction and string.format(L["guidekit.placeLine"], faction, zone) or zone or faction or ""
  row.place:SetText(row.placeText)
  W.SetColor(row.place, colors.text)
  row.faction = faction and r.faction or nil
  if row.faction then
    row.crest:SetSpec(K.FactionIconSpec(row.faction))
    row.crest:SetTip(nil, nil, faction)
  end
  local coord = K.Coord(r.x, r.y)
  row.pos:SetText(coord and string.format(L["guidekit.position"], coord) or "")
  row.tag:SetShown(not GL.IsConfirmed(r, item.section))
  row.chests:SetShown(GL.ObjectIds(r) ~= nil)
  row.actions:SetPlace(GL.Place(r, target))
  local share = GL.Progress(item.value, r.min, r.max)
  row.bar.share = share or 0
  row.bar:SetShown(share ~= nil and status ~= "done")
  local stateKey
  if item.collect then
    stateKey = "guidekit.collect." .. item.collect
  elseif item.state then
    stateKey = (item.state == "current" or item.state == "done") and "guidekit.state." .. item.state
      or "guidekit.collect.open"
  end
  row.state:SetShown(stateKey ~= nil)
  row.state:SetText(stateKey and L[stateKey] or "")
  W.SetColor(row.state, colors.range)
  row.dot:SetShown(stateKey ~= nil)
  if stateKey then
    row.dot:SetState(item.collect and GK.COLLECT_DOT[item.collect] or STATE_DOT[item.state], L[stateKey])
  end
  row.bg:SetColorTexture(Theme.fillColor(status == "current" and "hover" or nil))
  if status == "current" then
    row.mark:SetColorTexture(Theme.color("accent2"))
  else
    row.mark:SetColorTexture(ns.Theme.fillColor())
  end
  local shared = item.shared
  shared.hasStatus = shared.hasStatus or stateKey ~= nil
  shared.hasRange = shared.hasRange or (range or "") ~= ""
  shared.hasTerritory = shared.hasTerritory or row.faction ~= nil
end

-- Pooled list of table rows (status dot and word, range with progress, target, territory crest, zone and
-- coordinates, waypoint buttons, unconfirmed tag, chest button on rows with objects). list:SetRows(rows,
-- section, opts) fills it; the list is a stack item. list:Columns() answers the column set the rows need.
-- opts.rangeLabel(section, row) may return the locale key of a "%s" format that names the kind of the range
-- ("Level 16+"); without it the bare range is shown. opts.kind and opts.value ("skill" or "level" and the
-- value of the player) give every row its state and progress. opts.probe (GK.Probe) gives rows with an item
-- or quest id their collection status. opts.read = { get(row), set(row, on) } adds a "mark as read" box to
-- the rows with an item. opts.titleKey is the locale key of the title column.
function GK.RowList(parent)
  local list = K.RowPool(parent, createRow)
  list.shared = {}
  function list:SetRows(rows, section, opts)
    opts = opts or {}
    local items, shared = {}, { titleKey = opts.titleKey }
    for i, r in ipairs(rows) do
      items[i] = {
        row = r,
        section = section,
        rangeLabel = opts.rangeLabel,
        state = opts.kind and GL.RowState(opts.value, r.min, r.max) or nil,
        value = opts.kind and opts.value or nil,
        collect = opts.probe and GL.CollectionStatus(r, opts.probe) or nil,
        read = opts.read and type(r.item) == "number" and opts.read or nil,
        shared = shared,
      }
    end
    self.shared = shared
    self:Sync(items, paintRow)
  end
  function list:Columns()
    return columnsFor(self.shared)
  end
  return list
end

-- Collapsible group of a guide: K.GroupHeader (title, counter on the right, fill strip), the column header
-- and the row list below it, an optional note and a hint line for an empty list. opts: id (keeps the open
-- state), note (text), titleKey (title column), open. group:SetRows(rows, section, opts) fills the list,
-- group:SetSummary(title, counter, fill, color) the header, group:SetHint(text) shows the hint when there
-- are no rows. The group is a stack item.
function GK.Group(view, opts)
  local g = CreateFrame("Frame", nil, view.content)
  g.header = K.GroupHeader(g, {
    id = opts.id,
    open = opts.open == true,
    onToggle = function()
      view:Layout()
    end,
  })
  if opts.note then
    g.note = W.Text(g, { text = opts.note, role = "micro", color = "textMuted", wrap = true })
  end
  g.list = GK.RowList(g)
  g.hint = W.Text(g, { role = "ui", color = "textSecondary", wrap = true })
  g.hint:Hide()
  g.titleKey = opts.titleKey
  g.count = 0

  function g:SetRows(rows, section, o)
    o = o or {}
    o.titleKey = o.titleKey or self.titleKey
    self.list:SetRows(rows, section, o)
    self.count = #rows
    local columns = self.list:Columns()
    if self.columns ~= columns then
      self.columns = columns
      if self.colHeader then
        self.colHeader:Hide()
      end
      self.colHeader = K.ColumnHeader(self, { columns = columns })
    end
  end
  function g:SetSummary(title, counter, fill, color)
    self.header:SetTitle(title)
    self.header:SetCounter(counter)
    self.header:SetFill(fill)
    W.SetColor(self.header.label, color or "text")
  end
  function g:SetHint(text)
    self.hintText = text
    self.hint:SetText(text or "")
  end
  function g:Open(remember)
    self.header:SetOpen(true, remember)
  end

  function g:fgGridLayout(width)
    self.header:ClearAllPoints()
    self.header:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.header:SetWidth(width)
    local y = self.header:fgGridLayout(width)
    local open = self.header:IsOpen()
    local gap = Theme.space.sm
    local rows = open and self.count > 0
    if self.note then
      self.note:SetShown(open)
    end
    if self.colHeader then
      self.colHeader:SetShown(rows)
    end
    self.list:SetShown(rows)
    self.hint:SetShown(open and self.count == 0 and self.hintText ~= nil)
    if open and self.note then
      self.note:ClearAllPoints()
      self.note:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -(y + gap))
      self.note:SetWidth(math.max(40, width - 2 * PAD))
      y = y + gap + math.max(self.note:GetStringHeight(), K.scaledHeight(12))
    end
    if rows then
      y = y + gap
      self.colHeader:ClearAllPoints()
      self.colHeader:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      self.colHeader:SetWidth(width)
      y = y + self.colHeader:Layout(math.max(40, width - 2 * PAD))
      -- The row cells start PAD from the edge, the header titles follow.
      for id, cell in pairs(self.colHeader.cells) do
        local slot = self.colHeader.layout.cols[id]
        if slot.shown then
          cell:ClearAllPoints()
          cell:SetPoint("LEFT", self.colHeader, "LEFT", PAD + slot.x, 0)
        end
      end
      self.list:ClearAllPoints()
      self.list:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      self.list:SetWidth(width)
      y = y + self.list:fgGridLayout(width)
    elseif self.hint:IsShown() then
      self.hint:ClearAllPoints()
      self.hint:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -(y + gap))
      self.hint:SetWidth(math.max(40, width - 2 * PAD))
      y = y + gap + math.max(self.hint:GetStringHeight(), K.scaledHeight(14))
    end
    self:SetHeight(y)
    return y
  end
  return g
end

-- Legend of the status dots as a stack item. states: list of { state, key } (see K.StatusLegend).
function GK.Legend(view, states)
  local legend = K.StatusLegend(view.content, { states = states })
  view.stack:Add(legend, { gap = Theme.space.sm })
  return legend
end

-- Faction filter buttons added to the page stack. state.faction starts as the faction of the player.
function GK.FactionFilter(view, state, onChange)
  state.faction = state.faction or GL.DefaultFaction(K.PlayerFaction())
  local buttons = K.FactionButtons(view.content, {
    withAll = true,
    get = function()
      return state.faction
    end,
    set = function(value)
      state.faction = value
      onChange()
    end,
  })
  view.stack:Add(buttons, { gap = Theme.space.md })
  return buttons
end

-- Skill and maximum of the skill line called like the {de, en} name, nil when the character does not have it
-- or the client offers no skill list.
function GK.ReadSkill(name)
  if type(GetNumSkillLines) ~= "function" or type(GetSkillLineInfo) ~= "function" then
    return nil
  end
  local okCount, count = pcall(GetNumSkillLines)
  if not okCount or type(count) ~= "number" then
    return nil
  end
  local lines = {}
  for i = 1, math.min(count, 200) do
    local ok, lineName, header, _, skill, _, _, max = pcall(GetSkillLineInfo, i)
    if ok and lineName and not header then
      lines[#lines + 1] = { name = lineName, skill = skill, max = max }
    end
  end
  return GL.FindSkill(lines, { name.de, name.en })
end

-- Card above the sections: the skill of the player with a bar, and the step to do next as a full row with
-- its map buttons. ctx carries values, skillMax, stepIndex and stepRow (see GK.Build).
function GK.SummaryCard(view, spec, ctx)
  local card = W.Card(view.content, {})
  card.head = W.Text(card, { role = "h3", family = "heading", color = "accent2", wrap = true })
  card.bar = createBar(card, 6)
  card.collect = W.Text(card, { role = "ui", color = "textSecondary", wrap = true })
  card.next = W.Text(card, { key = "guidekit.nextStep", role = "micro", color = "textMuted" })
  card.row = createRow(card)
  card.hint = W.Text(card, { role = "ui", color = "textSecondary", wrap = true })
  local name = ns.T(spec.skillName) or ""

  function card:Update(data)
    local skill, max = ctx.values.skill, ctx.skillMax
    if skill then
      local line = max and string.format(L["guidekit.skillLine"], name, skill, max)
        or string.format(L["guidekit.skillLineOpen"], name, skill)
      card.head:SetText(line)
      card.bar.share = max and max > 0 and math.min(1, skill / max) or 0
    else
      card.head:SetText(string.format(L["guidekit.skillNone"], name))
    end
    card.bar:SetShown(skill ~= nil and max ~= nil)
    local counted = (ctx.collectTotal or 0) > 0
    card.collect:SetShown(counted)
    card.collect:SetText(counted
        and string.format(L["guidekit.collect.summary"], ns.T(spec.collect.name) or "", ctx.collectHanded, ctx.collectTotal)
      or "")
    card.next:SetShown(ctx.stepRow ~= nil)
    card.row:SetShown(ctx.stepRow ~= nil)
    if ctx.stepRow then
      paintRow(card.row, {
        row = ctx.stepRow,
        section = data.sections[ctx.stepIndex],
        rangeLabel = ctx.rangeLabel,
        state = "current",
        value = skill,
        shared = {},
      })
    end
    local hint = not skill and L[spec.learn] or (not ctx.stepRow and L["guidekit.allDone"]) or nil
    card.hint:SetShown(hint ~= nil)
    card.hint:SetText(hint or "")
  end

  function card:fgGridLayout(width)
    -- The card pads like every boxed container, so no child comes closer than that to its edge.
    local pad = card.pad
    local inner = math.max(40, width - 2 * pad)
    local y = pad
    card.head:ClearAllPoints()
    card.head:SetPoint("TOPLEFT", pad, -y)
    card.head:SetWidth(inner)
    y = y + math.max(card.head:GetStringHeight(), K.scaledHeight(16)) + 6
    if card.bar:IsShown() then
      card.bar:ClearAllPoints()
      card.bar:SetPoint("TOPLEFT", pad, -y)
      card.bar:SetBarWidth(inner)
      y = y + 6 + 8
    end
    if card.collect:IsShown() then
      card.collect:ClearAllPoints()
      card.collect:SetPoint("TOPLEFT", pad, -y)
      card.collect:SetWidth(inner)
      y = y + math.max(card.collect:GetStringHeight(), K.scaledHeight(14)) + 4
    end
    if card.hint:IsShown() then
      card.hint:ClearAllPoints()
      card.hint:SetPoint("TOPLEFT", pad, -y)
      card.hint:SetWidth(inner)
      y = y + math.max(card.hint:GetStringHeight(), K.scaledHeight(14)) + 2
    end
    if card.row:IsShown() then
      card.next:ClearAllPoints()
      card.next:SetPoint("TOPLEFT", pad, -y)
      y = y + math.max(card.next:GetStringHeight(), K.scaledHeight(12)) + 4
      card.row:ClearAllPoints()
      card.row:SetPoint("TOPLEFT", pad, -y)
      local rowW = inner
      card.row:SetWidth(rowW)
      local h = card.row:fgLayout(rowW)
      card.row:SetHeight(h)
      y = y + h
    end
    y = y + pad
    card:SetHeight(y)
    return y
  end
  view.stack:Add(card, { gap = Theme.space.md })
  return card
end

-- Legend entries of the collection statuses (names of GK.COLLECT_DOT) or, without a list, of the row states.
function GK.LegendStates(statuses)
  local out = {}
  for _, status in ipairs(statuses) do
    out[#out + 1] = { state = GK.COLLECT_DOT[status], key = "guidekit.collect." .. status }
  end
  return out
end

local function legendStates(ctx)
  if ctx.probe then
    return GK.LegendStates({ "handed", "bag", "bank", "missing" })
  end
  return {
    { state = STATE_DOT.done, key = "guidekit.state.done" },
    { state = STATE_DOT.current, key = "guidekit.state.current" },
    { state = STATE_DOT.open, key = "guidekit.collect.open" },
  }
end

-- Default body: every section as a collapsible group (header with counter and fill, column header, rows), or a
-- "data follows" line while the section has no rows. The section of the next step is open, the others keep
-- what the player chose. Returns the function that repaints after a filter change.
local function renderSections(view, data, ctx)
  local sections = {}
  if ctx.kindOf or ctx.probe then
    GK.Legend(view, legendStates(ctx))
  end
  for _, section in ipairs(data.sections) do
    local entry = { section = section, title = ns.T(section.title) or "" }
    entry.group = GK.Group(view, {
      id = "guide." .. ctx.id .. "." .. tostring(section.id),
      note = section.note and ns.T(section.note) or nil,
    })
    view.stack:Add(entry.group, { gap = Theme.space.sm })
    sections[#sections + 1] = entry
  end
  local first = true
  return function()
    for i, e in ipairs(sections) do
      local kind = ctx.kindOf and ctx.kindOf(e.section)
      local rows = GL.FilterRows(e.section.rows, ctx.state.faction)
      e.group:SetRows(rows, e.section, {
        rangeLabel = ctx.rangeLabel,
        kind = kind,
        value = kind and ctx.values[kind],
        probe = ctx.probe,
      })
      e.group:SetHint(L[GL.HasRows(e.section) and "guidekit.noRows" or "guidekit.follows"])
      local isNext = ctx.stepIndex == i
      local title = isNext and (e.title .. " (" .. L["guidekit.state.current"] .. ")") or e.title
      local handed, total = 0, 0
      if ctx.probe then
        handed, total = GL.CollectionTotals(e.section.rows, ctx.probe)
      end
      e.group:SetSummary(
        title,
        total > 0 and string.format(L["guidekit.group.count"], handed, total) or nil,
        total > 0 and handed / total or nil,
        isNext and "accent2" or "text"
      )
      if first and (isNext or not GL.HasRows(e.section) or (not ctx.stepIndex and i == 1)) then
        e.group:Open(false)
      end
    end
    first = false
  end
end

-- Page builder of one guide. spec: id (key of GL.GUIDES), intro (locale key), rangeLabel (optional
-- function(section, row) -> locale key of the range format, see GK.RowList), skillName ({ de, en } of the
-- skill line) with learn (locale key of the hint while it is not learned) and kindOf(section) -> "skill",
-- "level" or nil (what the ranges of a section measure) switch on the summary card and the row states, collect
-- ({ name = { de, en } }, optional) tracks the rows that carry an item or quest id (status word per row, count per
-- section and in the card, repaint on bag, quest and bank events while the page is visible), faction (start value of
-- the faction filter, default the faction of the player), render (optional
-- function(view, data, ctx) that adds the body to the stack and returns a repaint function).
function GK.Build(spec)
  local cfg = assert(GL.GUIDES[spec.id], spec.id)
  return function(container)
    local view = ns.NewPageView(container)
    local ctx = { id = spec.id, state = { faction = spec.faction }, rangeLabel = spec.rangeLabel, kindOf = spec.kindOf, values = {} }
    local repaint, filter, card, banner, empty
    ctx.probe = spec.collect and GK.Probe or nil
    -- Reads the skill and level of the player and the next step, then repaints card and sections.
    local function update(data)
      if spec.kindOf and spec.skillName then
        ctx.values.skill, ctx.skillMax = GK.ReadSkill(spec.skillName)
        ctx.values.level = UnitLevel and UnitLevel("player") or nil
        ctx.stepIndex, ctx.stepRow = GL.NextStep(data.sections, spec.kindOf, ctx.values, ctx.state.faction)
        ctx.collectHanded, ctx.collectTotal = 0, 0
        for _, section in ipairs(ctx.probe and data.sections or {}) do
          local handed, total = GL.CollectionTotals(section.rows, ctx.probe)
          ctx.collectHanded, ctx.collectTotal = ctx.collectHanded + handed, ctx.collectTotal + total
        end
        card:Update(data)
      end
      repaint()
    end
    local function refresh()
      local data, status = GK.Load(spec.id)
      banner:Update(status == GL.STATUS.disabled)
      if data and not repaint then
        filter = GK.FactionFilter(view, ctx.state, function()
          update(data)
          view:Layout()
        end)
        if spec.kindOf and spec.skillName then
          card = GK.SummaryCard(view, spec, ctx)
        end
        repaint = (spec.render or renderSections)(view, data, ctx)
      end
      if not data then
        GK.SetEmptyStatus(empty, status)
      end
      empty:SetShown(not data)
      if filter then
        filter:SetShown(data ~= nil)
      end
      if card then
        card:SetShown(data ~= nil)
      end
      if data then
        update(data)
      end
      view:Layout()
    end
    ns.AddIntro(view, spec.intro, { gap = Theme.space.md })
    banner = ns.PackageUI.Banner(view.content, cfg.addon, {
      onLoaded = refresh,
      onResize = function()
        view:Layout()
      end,
    })
    view.stack:Add(banner, { gap = Theme.space.md })
    empty = view.stack:Add(GK.EmptyState(view.content, GL.STATUS.missing), { gap = 0 })
    -- Page link: a guide may report and take a selection (spec.shareState, spec.openShared).
    function view:ShareState()
      return spec.shareState and spec.shareState(ctx) or {}
    end
    function view:Show(params)
      if spec.openShared and params then
        spec.openShared(ctx, params)
      end
      refresh()
    end
    ns.On("FG_UI_REFRESHED", function()
      if container:IsVisible() then
        refresh()
      end
    end)
    local events = { "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP" }
    if spec.collect then
      for _, event in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_TURNED_IN", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do
        events[#events + 1] = event
      end
    end
    for _, event in ipairs(events) do
      ns.On(event, function()
        if repaint and container:IsVisible() then
          ns.Debounce(view, 0.3, refresh)
        end
      end)
    end
    return view
  end
end
