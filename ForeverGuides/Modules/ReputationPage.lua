-- Page "Reputation" of the guides: a faction list with filters (group, side, name, known factions) and
-- the detail of the chosen faction: the standing ladder with the best ways per standing, the rewards and
-- the vendors, plus the current standing from the client. Wide pages put the list beside the detail, narrow
-- ones stack them. Logic: ReputationLogic.lua, data: ForeverGuides_Reputation (docs/RUF-FORMAT.md),
-- loading and the side buttons: GuideKit.lua.
local _, ns = ...
local Theme = ns.Theme
local W, L, K, GL, RL = ns.W, ns.L, ns.PageKit, ns.GuideKitLogic, ns.ReputationLogic

local P = {}
ns.ReputationPage = P

ns.AddLocale("enUS", {
  ["rep.group"] = "Group",
  ["rep.groupTip"] = "Shows the factions of one group or of all.",
  ["rep.groupAll"] = "All groups",
  ["rep.search"] = "Search",
  ["rep.searchPh"] = "Faction name",
  ["rep.known"] = "Only my factions",
  ["rep.knownTip"] = "Shows only factions the game lists for this character.",
  ["rep.empty"] = "No factions for this selection.",
  ["rep.new"] = "New",
  ["rep.newLine"] = "New in Forever",
  ["rep.side.both"] = "Both factions",
  ["rep.reading"] = "%s %d",
  ["rep.current"] = "Your reputation: %s %d of %d",
  ["rep.currentUnknown"] = "Your reputation: not available from the game",
  ["rep.here"] = "You are here",
  ["rep.hereSub"] = "%d of %d",
  ["rep.range"] = "%s to %s",
  ["rep.rangeFrom"] = "from %s",
  ["rep.rangeTo"] = "up to %s",
  ["rep.point"] = "%s %d",
  ["rep.span"] = "%s 0 to %d",
  ["rep.startLine"] = "Start: %s",
  ["rep.maxLine"] = "Maximum: %s",
  ["rep.classes"] = "Classes: %s",
  ["rep.kind.turnin"] = "Turn-in",
  ["rep.kind.kill"] = "Kills",
  ["rep.kind.quest"] = "Quest",
  ["rep.perTurnin"] = "+%d reputation per turn-in",
  ["rep.perKill"] = "+%d reputation per kill",
  ["rep.perQuest"] = "+%d reputation, once",
  ["rep.valid"] = "Counts %s",
  ["rep.npc"] = "Quest giver: %s",
  ["rep.cost"] = "Needs: %s",
  ["rep.level"] = "Level %d",
  ["rep.mobLevels"] = "Mob levels %s",
  ["rep.gate"] = "Refers to your reputation with %s",
  ["rep.race"] = "Only for some races",
  ["rep.chain"] = "Chain of %d quests, %d reputation in total",
  ["rep.reward"] = "Reward from %s",
  ["rep.rewardPrice"] = "Reward from %s, price %s",
  ["rep.rewardVendor"] = "Vendor: %s",
  ["rep.vendors"] = "Vendors",
  ["rep.sep"] = " · ",
})
ns.AddLocale("deDE", {
  ["rep.group"] = "Gruppe",
  ["rep.groupTip"] = "Zeigt die Fraktionen einer Gruppe oder aller Gruppen.",
  ["rep.groupAll"] = "Alle Gruppen",
  ["rep.search"] = "Suchen",
  ["rep.searchPh"] = "Name der Fraktion",
  ["rep.known"] = "Nur meine Fraktionen",
  ["rep.knownTip"] = "Zeigt nur Fraktionen, die das Spiel für diesen Charakter listet.",
  ["rep.empty"] = "Keine Fraktionen für diese Auswahl.",
  ["rep.new"] = "Neu",
  ["rep.newLine"] = "Neu in Forever",
  ["rep.side.both"] = "Beide Fraktionen",
  ["rep.reading"] = "%s %d",
  ["rep.current"] = "Dein Ruf: %s %d von %d",
  ["rep.currentUnknown"] = "Dein Ruf: vom Spiel nicht lesbar",
  ["rep.here"] = "Hier stehst du",
  ["rep.hereSub"] = "%d von %d",
  ["rep.range"] = "%s bis %s",
  ["rep.rangeFrom"] = "ab %s",
  ["rep.rangeTo"] = "bis %s",
  ["rep.point"] = "%s %d",
  ["rep.span"] = "%s 0 bis %d",
  ["rep.startLine"] = "Start: %s",
  ["rep.maxLine"] = "Maximum: %s",
  ["rep.classes"] = "Klassen: %s",
  ["rep.kind.turnin"] = "Abgabe",
  ["rep.kind.kill"] = "Kills",
  ["rep.kind.quest"] = "Quest",
  ["rep.perTurnin"] = "+%d Ruf pro Abgabe",
  ["rep.perKill"] = "+%d Ruf pro Kill",
  ["rep.perQuest"] = "+%d Ruf, einmalig",
  ["rep.valid"] = "Zählt %s",
  ["rep.npc"] = "Questgeber: %s",
  ["rep.cost"] = "Benötigt: %s",
  ["rep.level"] = "Stufe %d",
  ["rep.mobLevels"] = "Mobstufen %s",
  ["rep.gate"] = "Bezieht sich auf deinen Ruf bei %s",
  ["rep.race"] = "Nur für einige Völker",
  ["rep.chain"] = "Kette aus %d Quests, zusammen %d Ruf",
  ["rep.reward"] = "Belohnung ab %s",
  ["rep.rewardPrice"] = "Belohnung ab %s, Preis %s",
  ["rep.rewardVendor"] = "Händler: %s",
  ["rep.vendors"] = "Händler",
  ["rep.sep"] = " · ",
})

local LIST_ROW, DETAIL_ROW = 46, 62
local MIN_HEIGHT = 360
local NARROW_LIST_ROWS = 5
local WIDE_FROM = 600
local GAP = 12
local KIND_PER = { turnin = "rep.perTurnin", kill = "rep.perKill", quest = "rep.perQuest" }

local function lang()
  return ns.GetActiveLocale() == "deDE" and "de" or "en"
end

local function standingName(s)
  return s and ns.T({ de = s.de, en = s.en }) or "?"
end

local function rangeFormat()
  return {
    range = L["rep.range"],
    from = L["rep.rangeFrom"],
    to = L["rep.rangeTo"],
    point = L["rep.point"],
  }
end

-- Client reading ----------------------------------------------------------------------------------------

-- Faction standing from the client, guarded: the API differs between clients. nil when it cannot tell.
function P.Read(data, fid)
  local get = rawget(_G, "GetFactionInfoByID")
  if type(get) == "function" then
    local ok, name, _, standing, barMin, _, value = pcall(get, fid)
    if ok and type(name) == "string" then
      return RL.Reading(data, standing, barMin, value)
    end
  end
  local api = rawget(_G, "C_Reputation")
  if type(api) == "table" and type(api.GetFactionDataByID) == "function" then
    local ok, d = pcall(api.GetFactionDataByID, fid)
    if ok and type(d) == "table" then
      return RL.Reading(data, d.reaction, d.currentReactionThreshold, d.currentStanding)
    end
  end
  return nil
end

local function raceId()
  local race = rawget(_G, "UnitRace")
  if type(race) ~= "function" then
    return nil
  end
  local ok, _, _, id = pcall(race, "player")
  return ok and type(id) == "number" and id or nil
end

local function className(token)
  local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return type(names) == "table" and names[token] or token
end

local function money(copper)
  local cost = rawget(ns, "CostLogic")
  return cost and type(copper) == "number" and cost.Format(copper) or nil
end

-- Texts of the rows -------------------------------------------------------------------------------------

local function join(parts)
  return table.concat(parts, L["rep.sep"])
end

local function placeText(r)
  local zone = ns.T(r.zone)
  local coord = K.Coord(r.x, r.y)
  if zone and coord then
    return zone .. " " .. coord
  end
  return zone or coord
end

local function wayRangeText(ctx, row)
  return RL.RangeText(ctx.data, row.min, row.max, standingName, rangeFormat())
end

local function wayTexts(ctx, row, section)
  local target = ns.T(row.target) or ""
  local title = (L["rep.kind." .. tostring(row.kind)] or "") .. ": " .. target
  local per = KIND_PER[row.kind] and type(row.rep) == "number" and string.format(L[KIND_PER[row.kind]], row.rep)
  local range = wayRangeText(ctx, row)
  local sub = {}
  sub[#sub + 1] = per
  sub[#sub + 1] = range and string.format(L["rep.valid"], range)
  sub[#sub + 1] = placeText(row)
  local lines = {}
  local function add(key, value)
    if value then
      lines[#lines + 1] = string.format(L[key], value)
    end
  end
  add("rep.npc", ns.T(row.npc))
  add("rep.cost", ns.T(row.cost))
  add("rep.level", row.level)
  add("rep.mobLevels", row.lmin and GL.RangeText(row.lmin, row.lmax))
  if row.gate then
    local gate = ctx.byFid[row.gate]
    lines[#lines + 1] = string.format(L["rep.gate"], gate and ns.T(gate.title) or tostring(row.gate))
  end
  if row.race then
    lines[#lines + 1] = L["rep.race"]
  end
  if row.chain and row.chainRep then
    lines[#lines + 1] = string.format(L["rep.chain"], row.chain, row.chainRep)
  end
  if not GL.IsConfirmed(row, section) then
    lines[#lines + 1] = L["guidekit.unconfirmedTip"]
  end
  return title, join(sub), lines, target
end

-- Row of the detail list: { title, sub, inert, badge, actions, tooltipSpec }.
local function placeActions(place)
  if not place then
    return nil
  end
  return {
    {
      icon = ns.ICONS.map,
      boxed = true,
      tooltip = L["guidekit.mapTip"],
      opens = true,
      onClick = function()
        K.PlaceOnMap(place)
      end,
    },
    {
      icon = W.MARKER_ICON,
      boxed = true,
      tooltip = L["guidekit.markerTip"],
      onClick = function()
        K.PlaceMarker(place)
      end,
    },
  }
end

local UNCONFIRMED = function()
  return { text = L["guidekit.unconfirmed"], color = "warning" }
end

local function bindDetail(ctx, item)
  local section = ctx.section
  if item.kind == "head" then
    local s = item.standing
    local t = {
      title = string.format(L["rep.span"], standingName(s), RL.Span(s)),
      inert = true,
    }
    if item.current and ctx.reading then
      t.badge = { text = L["rep.here"], color = "accent2" }
      t.sub = string.format(L["rep.hereSub"], ctx.reading.offset, ctx.reading.span)
    end
    return t
  elseif item.kind == "note" then
    return { title = L["guidekit.follows"], sub = L["guidekit.followsHint"], inert = true }
  elseif item.kind == "vendorHead" then
    return { title = L["rep.vendors"], inert = true }
  elseif item.kind == "way" then
    local title, sub, lines, target = wayTexts(ctx, item.row, section)
    local confirmed = GL.IsConfirmed(item.row, section)
    return {
      title = title,
      sub = sub,
      wrapSub = true,
      badge = not confirmed and UNCONFIRMED() or nil,
      actions = placeActions(GL.Place(item.row, target)),
      tooltipSpec = { title = title, lines = lines },
    }
  elseif item.kind == "reward" then
    local r = item.reward
    local tier = RL.Standing(ctx.data, r.tier)
    local price = money(r.price)
    local sub = { price and string.format(L["rep.rewardPrice"], standingName(tier), price) or string.format(L["rep.reward"], standingName(tier)) }
    if item.vendors[1] then
      sub[#sub + 1] = string.format(L["rep.rewardVendor"], ns.T(item.vendors[1].vendor))
    end
    local name = ns.T(r) or "?"
    return {
      title = name,
      sub = join(sub),
      wrapSub = true,
      badge = not GL.IsConfirmed(r, section) and UNCONFIRMED() or nil,
      tooltipSpec = { link = "item:" .. tostring(r.item), title = name },
    }
  end
  -- Vendor: Classic knowledge, never confirmed for Forever.
  local v = item.vendor
  local name = ns.T(v) or "?"
  return {
    title = name,
    sub = placeText(v),
    wrapSub = true,
    titleNpc = item.id,
    badge = UNCONFIRMED(),
    actions = placeActions(GL.Place(v, name)),
    tooltipSpec = { title = name, lines = { L["guidekit.unconfirmedTip"] } },
  }
end

-- Page --------------------------------------------------------------------------------------------------

local function controls(view, state, onChange, ctx)
  local options = { { value = "all", key = "rep.groupAll" } }
  for _, g in ipairs(ctx.data.groups or {}) do
    options[#options + 1] = { value = g.id, text = ns.T(g.title) }
  end
  local search
  local bar = K.FilterBar(view.content, {
    count = function()
      return (state.group ~= "all" and 1 or 0) + (state.query ~= "" and 1 or 0) + (state.known and 1 or 0)
    end,
    reset = function()
      local linked = state.fid ~= nil
  state.group, state.query, state.known = "all", "", false
  ns.PageState.Bind(view, state, { "group", "query", "known", "fid" }, "reputation", linked)
      search.edit:SetText("")
      onChange()
    end,
  })
  local group = bar:AddDropdown({
    key = "rep.group",
    options = options,
    tooltip = "rep.group",
    tooltipText = "rep.groupTip",
    get = function()
      return state.group
    end,
    set = function(v)
      state.group = v
      onChange()
    end,
  })
  search = bar:AddSearch({
    key = "rep.search",
    text = state.query,
    placeholder = "rep.searchPh",
    onChange = function(text)
      state.query = text
      onChange()
    end,
  })
  local known = bar:AddToggle({
    key = "rep.known",
    tooltip = "rep.known",
    tooltipText = "rep.knownTip",
    get = function()
      return state.known
    end,
    set = function(v)
      state.known = v
      onChange()
    end,
  })
  local refreshBar = bar.Refresh
  function bar:Refresh()
    for _, o in ipairs(options) do
      if o.text then
        for _, g in ipairs(ctx.data.groups or {}) do
          if g.id == o.value then
            o.text = ns.T(g.title)
          end
        end
      end
    end
    group.Refresh()
    known.Refresh()
    refreshBar(self)
  end
  bar.known = known
  return bar
end

-- Body of the page, called by GuideKit.Build once the data is there. Returns the repaint function.
function P.Render(view, data, ctx)
  local state = ctx.state
  state.group, state.query, state.known = "all", "", false
  local by = { data = data, byFid = {} }
  for _, s in ipairs(data.sections) do
    by.byFid[s.fid] = s
  end
  local readings, shown = {}, {}
  local repaint

  local filterBar = controls(view, state, function()
    repaint()
    view:Layout()
  end, by)
  view.stack:Add(filterBar, { gap = Theme.space.md })
  local empty = view.stack:Add(
    W.EmptyState(view.content, { text = "rep.empty", icon = "search", compact = true }),
    { gap = Theme.space.md }
  )

  local split = CreateFrame("Frame", nil, view.content)
  local detail = W.Panel(split)
  local head = W.Text(detail, { role = "h3", family = "heading", color = "accent2", wrap = true })
  local info = W.Text(detail, { role = "ui", color = "textSecondary", wrap = true })

  local list = K.NewList(split, {
    look = "boxed",
    rowHeight = LIST_ROW,
    bind = function(s)
      local reading = readings[s.fid]
      local sub = {}
      for _, g in ipairs(data.groups or {}) do
        if g.id == s.group then
          sub[#sub + 1] = ns.T(g.title)
        end
      end
      if reading then
        sub[#sub + 1] = string.format(L["rep.reading"], standingName(reading.standing), reading.offset)
      end
      if not GL.HasRows(s) then
        sub[#sub + 1] = L["guidekit.follows"]
      end
      return {
        title = ns.T(s.title) or s.id,
        sub = join(sub),
        selected = state.fid == s.fid,
        cursor = state.fid == s.fid,
        badge = s.new and { text = L["rep.new"], color = "accent2" } or nil,
        bar = reading and reading.span and reading.span > 0 and reading.offset / reading.span or nil,
      }
    end,
    onClick = function(s)
      state.fid = s.fid
      repaint()
      view:Layout()
    end,
  })

  local detailList
  detailList = K.NewList(detail, {
    look = "flat", -- detail rows with vendor links inside the detail panel
    vendorLinks = true,
    rowHeight = DETAIL_ROW,
    bind = function(item)
      return bindDetail(by, item)
    end,
  })

  local function sideName(s)
    return s.side == "A" and L["kit.faction.A"] or s.side == "H" and L["kit.faction.H"] or L["rep.side.both"]
  end

  local function paintDetail(s)
    by.section = s
    by.reading = readings[s.fid]
    local race = raceId()
    head:SetText(ns.T(s.title) or s.id)
    local top = {}
    for _, g in ipairs(data.groups or {}) do
      if g.id == s.group then
        top[1] = ns.T(g.title)
      end
    end
    top[#top + 1] = sideName(s)
    if s.new then
      top[#top + 1] = L["rep.newLine"]
    end
    if type(s.classes) == "table" and #s.classes > 0 then
      local names = {}
      for i, token in ipairs(s.classes) do
        names[i] = className(token)
      end
      top[#top + 1] = string.format(L["rep.classes"], table.concat(names, ", "))
    end
    local lines = { join(top) }
    local reading = by.reading
    lines[#lines + 1] = reading
        and string.format(L["rep.current"], standingName(reading.standing), reading.offset, reading.span)
      or L["rep.currentUnknown"]
    local startS, startOffset = RL.StandingAt(data, RL.StartValue(s, race))
    local maxS, maxOffset = RL.StandingAt(data, RL.MaxValue(s))
    local function at(standing, offset)
      return offset > 0 and string.format(L["rep.point"], standingName(standing), offset) or standingName(standing)
    end
    if startS and maxS then
      lines[#lines + 1] = string.format(L["rep.startLine"], at(startS, startOffset))
        .. L["rep.sep"]
        .. string.format(L["rep.maxLine"], at(maxS, maxS.id == 8 and 0 or maxOffset))
    end
    info:SetText(table.concat(lines, "\n"))
    detailList:SetData(RL.Items(data, s, {
      side = state.faction,
      raceId = race,
      matches = GL.MatchesFaction,
      currentId = reading and reading.standing.id,
      lang = lang(),
    }))
  end

  local function layoutDetail(width, height)
    local pad = detail.pad
    local inner = width - pad * 2
    detail:SetSize(width, height)
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", detail, "TOPLEFT", pad, -pad)
    head:SetWidth(inner)
    info:ClearAllPoints()
    local y = pad + math.ceil(head:GetStringHeight()) + 4
    info:SetPoint("TOPLEFT", detail, "TOPLEFT", pad, -y)
    info:SetWidth(inner)
    y = y + math.ceil(info:GetStringHeight()) + 8
    detailList:ClearAllPoints()
    detailList:SetPoint("TOPLEFT", detail, "TOPLEFT", pad, -y)
    detailList:SetSize(inner, math.max(K.scaledHeight(DETAIL_ROW) * 2, height - y - pad))
  end

  function split:fgGridLayout(width, room)
    local free = room and (room.viewHeight - room.top - room.pad) or 0
    local min = K.scaledHeight(MIN_HEIGHT)
    local full = math.max(min, math.floor(free))
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
    detail:ClearAllPoints()
    if width >= WIDE_FROM then
      local listW = math.max(220, math.min(360, math.floor(width * 0.34)))
      list:SetSize(listW, full)
      detail:SetPoint("TOPLEFT", split, "TOPLEFT", listW + GAP, 0)
      layoutDetail(width - listW - GAP, full)
      self:SetHeight(full)
      return full
    end
    local listH = K.scaledHeight(LIST_ROW) * NARROW_LIST_ROWS
    list:SetSize(width, listH)
    detail:SetPoint("TOPLEFT", split, "TOPLEFT", 0, -(listH + GAP))
    local detailH = math.max(min, full - listH - GAP)
    layoutDetail(width, detailH)
    local total = listH + GAP + detailH
    self:SetHeight(total)
    return total
  end
  view.stack:Add(split, { gap = Theme.space.lg })

  function repaint()
    readings = {}
    local anyKnown = false
    for _, s in ipairs(data.sections) do
      readings[s.fid] = P.Read(data, s.fid)
      anyKnown = anyKnown or (readings[s.fid] and readings[s.fid].known) or false
    end
    if not anyKnown then
      state.known = false
    end
    filterBar.known:SetShown(anyKnown)
    filterBar:Refresh()
    local search = ns.TrainerSearchLogic
    shown = RL.Sort(
      data,
      RL.Filter(data.sections, {
        group = state.group,
        side = state.faction,
        query = state.query,
        known = state.known,
        readings = readings,
        matches = GL.MatchesFaction,
        words = search and search.Words,
        match = search and search.Match,
      }),
      function(s)
        return ns.T(s.title)
      end
    )
    empty:SetAction(filterBar:IsFiltered() and W.EMPTY_RESET or nil, function()
      filterBar:Reset()
    end)
    empty:SetShown(#shown == 0)
    split:SetShown(#shown > 0)
    local selected
    for _, s in ipairs(shown) do
      if s.fid == state.fid then
        selected = s
      end
    end
    selected = selected or shown[1]
    state.fid = selected and selected.fid
    list:SetData(shown)
    if selected then
      paintDetail(selected)
    end
  end

  ns.On("UPDATE_FACTION", function()
    if split:IsVisible() then
      repaint()
      view:Layout()
    end
  end)
  return repaint
end

-- Page builder for the registry (the file loads after GuidePages.lua, so the page looks it up late).
function P.Build(container)
  return ns.GuideKit.Build({
    id = "reputation",
    intro = "guides.reputation.intro",
    render = P.Render,
    -- Page link: the faction id. The filters go back to "all" so the faction is in the list.
    shareState = function(ctx)
      return { ctx.state.fid }
    end,
    openShared = function(ctx, params)
      local fid = tonumber(params[1])
      if fid and fid >= 1 and fid <= 99999 and fid == math.floor(fid) then
        ctx.state.fid, ctx.state.group, ctx.state.query, ctx.state.known = fid, "all", "", false
      end
    end,
  })(container)
end
