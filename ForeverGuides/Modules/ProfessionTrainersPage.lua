-- Profession trainers: every trainer of the trainer data file and the profession route data with the
-- rank he teaches and where he stands. The class trainers have their own page (TrainersPage.lua), this
-- one follows the same layout: filters on top, a list below, Map and Waypoint buttons for a trainer with
-- a position, a tooltip with the safety of the entry. Data: ns.ProfessionRouteData and
-- ns.ProfessionTrainers (load-on-demand add-on), logic: ProfessionTrainersLogic.
local _, ns = ...
local W, L, Theme, K = ns.W, ns.L, ns.Theme, ns.PageKit
local R, PL, Data = ns.ProfessionRouteLogic, ns.ProfessionTrainersLogic, ns.ProfessionRouteData

ns.AddLocale("enUS", {
  ["page.proftrainers"] = "Profession trainers",
  ["proftrainers.intro"] = "Profession trainers by profession, faction and rank, with their positions",
  ["proftrainers.source"] = "The positions are not verified in Forever yet. %d of %d trainers have coordinates.",
  ["proftrainers.counts"] = "With coordinates: %s",
  ["proftrainers.countItem"] = "%s %d of %d",
  ["proftrainers.limits"] = "A rank can be learned up to skill: %s",
  ["proftrainers.limitItem"] = "%s %d",
  ["proftrainers.profession"] = "Profession",
  ["proftrainers.professionTip"] = "Shows the trainers of one profession or of all.",
  ["proftrainers.professionAll"] = "All professions",
  ["proftrainers.rank"] = "Rank",
  ["proftrainers.rankTip"] = "Shows only trainers who teach this rank.",
  ["proftrainers.rankAll"] = "All ranks",
  ["proftrainers.search"] = "Search",
  ["proftrainers.searchPh"] = "Name or place",
  ["proftrainers.neutral"] = "Neutral",
  ["proftrainers.ranksLine"] = "%s: %s",
  ["proftrainers.placeLine"] = "%s, %s",
  ["proftrainers.pos"] = "Position %s",
  ["proftrainers.posConf"] = "Position %s · %s",
  ["proftrainers.cf.1"] = "Confidence high",
  ["proftrainers.cf.2"] = "Confidence medium",
  ["proftrainers.cf.3"] = "Confidence low",
  ["proftrainers.cfTip.1"] = "The position is considered accurate.",
  ["proftrainers.cfTip.2"] = "The position is probably accurate.",
  ["proftrainers.cfTip.3"] = "The position is doubtful or unknown.",
  ["proftrainers.classic"] = "Not verified in Forever",
  ["proftrainers.npc"] = "NPC ID %d",
  ["proftrainers.inf"] = "Rank derived from the recipe level",
  ["proftrainers.noPos"] = "Location unknown, coordinates missing",
  ["proftrainers.total"] = "Trainers: %d, with coordinates: %d",
  ["proftrainers.empty"] = "No trainers for this selection.",
  ["proftrainers.mapTip"] = "Show the trainer's zone on the map",
  ["proftrainers.markerTip"] = "Set a waypoint at the trainer",
})

ns.AddLocale("deDE", {
  ["page.proftrainers"] = "Berufslehrer",
  ["proftrainers.intro"] = "Berufslehrer nach Beruf, Fraktion und Rang, mit ihren Standorten",
  ["proftrainers.source"] = "Die Standorte sind in Forever noch nicht geprüft. %d von %d Lehrern haben Koordinaten.",
  ["proftrainers.counts"] = "Mit Koordinaten: %s",
  ["proftrainers.countItem"] = "%s %d von %d",
  ["proftrainers.limits"] = "Ein Rang ist lernbar bis Fertigkeit: %s",
  ["proftrainers.limitItem"] = "%s %d",
  ["proftrainers.profession"] = "Beruf",
  ["proftrainers.professionTip"] = "Zeigt die Lehrer eines Berufs oder aller Berufe.",
  ["proftrainers.professionAll"] = "Alle Berufe",
  ["proftrainers.rank"] = "Rang",
  ["proftrainers.rankTip"] = "Zeigt nur Lehrer, die diesen Rang lehren.",
  ["proftrainers.rankAll"] = "Alle Ränge",
  ["proftrainers.search"] = "Suchen",
  ["proftrainers.searchPh"] = "Name oder Ort",
  ["proftrainers.neutral"] = "Neutral",
  ["proftrainers.ranksLine"] = "%s: %s",
  ["proftrainers.placeLine"] = "%s, %s",
  ["proftrainers.pos"] = "Position %s",
  ["proftrainers.posConf"] = "Position %s · %s",
  ["proftrainers.cf.1"] = "Sicherheit hoch",
  ["proftrainers.cf.2"] = "Sicherheit mittel",
  ["proftrainers.cf.3"] = "Sicherheit niedrig",
  ["proftrainers.cfTip.1"] = "Die Position gilt als genau.",
  ["proftrainers.cfTip.2"] = "Die Position ist wahrscheinlich genau.",
  ["proftrainers.cfTip.3"] = "Die Position ist zweifelhaft oder unbekannt.",
  ["proftrainers.classic"] = "In Forever nicht verifiziert",
  ["proftrainers.npc"] = "NPC-ID %d",
  ["proftrainers.inf"] = "Rang aus Rezeptstufe abgeleitet",
  ["proftrainers.noPos"] = "Standort unbekannt, Koordinaten fehlen",
  ["proftrainers.total"] = "Lehrer: %d, davon mit Koordinaten: %d",
  ["proftrainers.empty"] = "Keine Lehrer für diese Auswahl.",
  ["proftrainers.mapTip"] = "Zone des Lehrers auf der Karte zeigen",
  ["proftrainers.markerTip"] = "Wegpunkt am Lehrer setzen",
})

-- Four text lines: name, profession and ranks, faction and place, position. The buttons sit top
-- right, the first two lines end before them.
local ROW_HEIGHT = 72
local ROW_ACTION_TOP = 5
local MIN_ROWS = 3
local CONTROL_W = 200
local FIELD_W = 220
local CONTROL_GAP = 12
local CONTROL_H = 46

local FACTION_KEY = { A = "kit.faction.A", H = "kit.faction.H", N = "proftrainers.neutral" }

local function rankName(rank)
  local key = "profroute.rank." .. tostring(rank)
  local text = L[key]
  return text ~= key and text or tostring(rank)
end

-- "Apprentice (up to 75), Journeyman (up to 150)".
local function ranksText(entry)
  local parts = {}
  for _, r in ipairs(entry.ranks) do
    parts[#parts + 1] = r.max and string.format(L["profroute.rankHead"], rankName(r.rank), r.max) or rankName(r.rank)
  end
  return table.concat(parts, ", ")
end

-- Tooltip of a row: safety of the entry, the kind of data, the NPC id and a note for ranks that were
-- derived. Only entries of the trainer data file carry them.
local function showRowTip(row)
  local e = row.entry
  if not (e and e.cf) then
    return
  end
  local lines = {
    L["proftrainers.cfTip." .. e.cf] or "",
    L["proftrainers.classic"],
  }
  if e.npc then
    lines[#lines + 1] = string.format(L["proftrainers.npc"], e.npc)
  end
  if e.inf then
    lines[#lines + 1] = L["proftrainers.inf"]
  end
  ns.ShowTooltip(row, L["proftrainers.cf." .. e.cf] or PL.DisplayName(e), nil, { lines = lines })
end

local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetClipsChildren(true)
  row:EnableMouse(true)
  row:SetScript("OnEnter", showRowTip)
  row:SetScript("OnLeave", ns.HideTooltip)
  row.actions = W.MapActionButtons(row, { mapTip = "proftrainers.mapTip", markerTip = "proftrainers.markerTip" })
  row.actions:SetPoint("TOPRIGHT", -8, -ROW_ACTION_TOP)
  row.title = W.Text(row, { role = "ui" })
  row.ranks = W.Text(row, { role = "micro", color = "textSecondary" })
  row.place = W.Text(row, { role = "micro", color = "textSecondary" })
  row.pos = W.Text(row, { role = "micro", color = "textMuted" })
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
  local hasPos = PL.HasPosition(entry)
  row.entry = entry
  row.actions:SetPlace(hasPos and function()
    return PL.Place(entry)
  end or nil)
  local function anchor(fs, rel, point, y, clear)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", rel, point, rel == row and 8 or 0, y)
    if clear then
      fs:SetPoint("RIGHT", row.actions, "LEFT", -8, 0)
    else
      fs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    end
  end
  anchor(row.title, row, "TOPLEFT", -5, hasPos)
  anchor(row.ranks, row.title, "BOTTOMLEFT", -2, hasPos)
  anchor(row.place, row.ranks, "BOTTOMLEFT", -2, false)
  anchor(row.pos, row.place, "BOTTOMLEFT", -2, false)
  row.title:SetText(PL.DisplayName(entry))
  row.ranks:SetText(string.format(L["proftrainers.ranksLine"], ns.T(entry.profession) or entry.slug, ranksText(entry)))
  local where = ns.T(entry.place) or ns.T(entry.zone)
  local faction = L[FACTION_KEY[entry.faction]]
  row.place:SetText(where and string.format(L["proftrainers.placeLine"], faction, where) or faction)
  if hasPos then
    local coord = K.Coord(entry.x, entry.y)
    row.pos:SetText(
      entry.cf and string.format(L["proftrainers.posConf"], coord, L["proftrainers.cf." .. entry.cf] or "")
        or string.format(L["proftrainers.pos"], coord)
    )
    W.SetColor(row.pos, "textMuted")
  else
    row.pos:SetText(L["proftrainers.noPos"])
    W.SetColor(row.pos, "warning")
  end
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = {
    slug = "all",
    rank = "all",
    faction = K.PlayerFaction() or "all",
    query = "",
  }
  -- All trainers of the loaded data, filled by load().
  local all = {}
  local refresh

  ns.AddParagraph(view, "proftrainers.intro")
  local source = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 4 })
  local counts = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 4 })
  local limits = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted" })
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

  -- Controls: profession, rank, search, wrapped to the width.
  local professionOptions = { { value = "all", key = "proftrainers.professionAll" } }
  for _, slug in ipairs(R.SLUGS) do
    professionOptions[#professionOptions + 1] = { value = slug, text = R.Name(slug) }
  end
  local rankOptions = { { value = "all", key = "proftrainers.rankAll" } }
  for _, rank in ipairs(PL.RANKS) do
    rankOptions[#rankOptions + 1] = { value = rank, text = rankName(rank) }
  end
  local controls = CreateFrame("Frame", nil, view.content)
  local professionDd = W.Dropdown(controls, {
    key = "proftrainers.profession",
    width = CONTROL_W,
    options = professionOptions,
    tooltip = "proftrainers.profession",
    tooltipText = "proftrainers.professionTip",
    get = function()
      return state.slug
    end,
    set = function(v)
      state.slug = v
      refresh()
    end,
  })
  professionDd:SetWidth(CONTROL_W)
  local rankDd = W.Dropdown(controls, {
    key = "proftrainers.rank",
    width = CONTROL_W,
    options = rankOptions,
    tooltip = "proftrainers.rank",
    tooltipText = "proftrainers.rankTip",
    get = function()
      return state.rank
    end,
    set = function(v)
      state.rank = v
      refresh()
    end,
  })
  rankDd:SetWidth(CONTROL_W)
  local searchBox = CreateFrame("Frame", nil, controls)
  searchBox:SetSize(FIELD_W, CONTROL_H)
  W.Text(searchBox, { key = "proftrainers.search", role = "ui" }):SetPoint("TOPLEFT")
  local search = W.EditBox(searchBox, {
    placeholder = "proftrainers.searchPh",
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
    for _, item in ipairs({ professionDd, rankDd, searchBox }) do
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
  K.Anchor("FG.ProfTrainers.Controls", controls)

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
  K.Anchor("FG.ProfTrainers.List", list)
  local empty = ns.AddParagraph(view, "proftrainers.empty", { role = "ui" })

  -- Reads the trainers of every profession (loads the data add-on on the first call).
  local function load()
    local sources, missing, status = {}, false, nil
    for _, slug in ipairs(R.SLUGS) do
      local data, st = Data.Get(slug)
      if data then
        sources[#sources + 1] = { slug = slug, data = data, name = R.PROFESSIONS[slug] }
      elseif st == Data.STATUS.missing then
        missing = true
      else
        status = st
      end
    end
    all = PL.Collect(sources, rawget(ns, "ProfessionTrainers"))
    return missing, status
  end

  local function paintNotes()
    local count, placed = PL.Count(all)
    source:SetText(count > 0 and string.format(L["proftrainers.source"], placed, count) or "")
    local per = PL.CountBySlug(all)
    local items = {}
    for _, slug in ipairs(R.SLUGS) do
      local c = per[slug]
      if c then
        items[#items + 1] = string.format(L["proftrainers.countItem"], R.Name(slug), c.placed, c.total)
      end
    end
    counts:SetText(#items > 0 and string.format(L["proftrainers.counts"], table.concat(items, " · ")) or "")
    local ranks = {}
    for _, r in ipairs(PL.RankLimits(all)) do
      ranks[#ranks + 1] = string.format(L["proftrainers.limitItem"], rankName(r.rank), r.max)
    end
    limits:SetText(#ranks > 0 and string.format(L["proftrainers.limits"], table.concat(ranks, ", ")) or "")
  end

  -- reload: read the data again (page opened, add-on switched on), else only the filter changed.
  function refresh(reload)
    local missing, status
    if reload ~= false and (reload == true or #all == 0) then
      missing, status = load()
    end
    for _, o in ipairs(professionOptions) do
      if o.text then
        o.text = R.Name(o.value)
      end
    end
    for _, o in ipairs(rankOptions) do
      if o.text then
        o.text = rankName(o.value)
      end
    end
    professionDd.Refresh()
    rankDd.Refresh()
    factionButtons.Refresh()
    local offered = banner:Update(#all == 0 and missing == true)
    hint:SetShown(#all == 0 and not offered)
    if #all == 0 then
      hint:SetText(Data.Hint(missing and Data.STATUS.missing or status or Data.STATUS.noRoute))
    end
    paintNotes()
    local shown = PL.Sort(PL.Filter(all, {
      slug = state.slug,
      faction = state.faction,
      rank = state.rank,
      query = state.query,
      match = ns.SearchLogic.match,
    }))
    local n, placed = PL.Count(shown)
    total:SetText(string.format(L["proftrainers.total"], n, placed))
    total:SetShown(#all > 0)
    list:SetShown(n > 0)
    empty:SetShown(#all > 0 and n == 0)
    list:SetData(shown)
    view:Layout()
  end

  -- params[1] = profession slug (deep link, /fg proftrainers <profession>), unknown ones are ignored.
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
  id = "proftrainers",
  order = 430,
  group = "professions",
  title = "page.proftrainers",
  icon = ns.ICONS.proftrainers,
  aliases = { "berufslehrer", "proftrainers", "professiontrainers" },
  crumbLabel = function(param)
    return R.PROFESSIONS[param] and R.Name(param) or param
  end,
  build = build,
})
