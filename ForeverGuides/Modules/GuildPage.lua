-- Page "Gilde" (/fg gilde, /fg guild): read-only guild overview (members, message of the day, search,
-- filters, sorting, detail card with whisper). Item level and professions come from Peers (read by
-- GroupInspect and PeerComm) and show "reading ..." for a fresh group member, "-" while unknown.
-- Data comes from GuildData. The players met live on the page "Kontakte" (ContactsPage.lua, the old
-- deep links guild/social and guild/seen lead there); the helpers both pages share are in GuildKit.lua.
-- Nothing here changes the guild; the management belongs to the optional add-on "Forever Guides:
-- GildenManager", which adds tabs, detail lines and columns through ns.GuildExt (GuildExt.lua).
-- While a stand-in source is set (GuildData.SetSource, an extension showing sample data) the page shows its
-- data instead of the game's roster; extensions add their own parts through ns.DevTools.Build.
-- ns.SubAddons loads that add-on; the page only offers the switch (GuildManagerButton.lua). The tab bar
-- shows once an add-on brings a tab. Tabs, columns and detail lines that register later are picked up
-- without losing selection, filters or page.
local _, ns = ...
local W, L, Theme, K, Store = ns.W, ns.L, ns.Theme, ns.PageKit, ns.Store
local GL, GD, GE, Kit, GM = ns.GuildLogic, ns.GuildData, ns.GuildExt, ns.GuildKit, ns.GuildManagerButton
local coloredName, className, classIcon, joinParts = Kit.ColoredName, Kit.ClassName, Kit.ClassIcon, Kit.JoinParts
local columns, peerOf, ilvlText, jobsText, peerLines =
  Kit.Columns, Kit.PeerOf, Kit.IlvlText, Kit.JobsText, Kit.PeerLines
local newDetail, newFlow, syncOptions, listHeight = Kit.NewDetail, Kit.NewFlow, Kit.SyncOptions, Kit.ListHeight

local P = {}
ns.GuildPage = P

local ROW_HEIGHT = Kit.ROW_HEIGHT
local DROPDOWN_WIDTH = Kit.DROPDOWN_WIDTH
local TOGGLE_WIDTH = 200
local SEARCH_HEIGHT = Kit.SEARCH_HEIGHT
local MAX_ACTIONS = 6

ns.AddLocale("enUS", {
  ["page.guild"] = "Guild",
  ["guild.tab.guild"] = "Guild",
  ["guild.none"] = "You are not in a guild.",
  ["guild.loading"] = "Loading guild list ...",
  ["guild.online"] = "Online: %d of %d",
  ["guild.motd.title"] = "Message of the day",
  ["guild.motd.empty"] = "No message of the day",
  ["guild.stats.levels"] = "Levels: %s",
  ["guild.stats.classes"] = "Classes: %s",
  ["guild.search"] = "Search",
  ["guild.onlyOnline"] = "Online only",
  ["guild.rank"] = "Rank",
  ["guild.rank.all"] = "All ranks",
  ["guild.sort"] = "Sort by",
  ["guild.sort.rank"] = "Rank",
  ["guild.sort.name"] = "Name",
  ["guild.sort.level"] = "Level",
  ["guild.sort.class"] = "Class",
  ["guild.sort.zone"] = "Zone",
  ["guild.sort.online"] = "Last online",
  ["guild.count"] = "%d of %d",
  ["guild.empty"] = "No matches.",
  ["guild.cols"] = "Columns",
  ["guild.col.rank"] = "Rank",
  ["guild.col.level"] = "Level",
  ["guild.col.zone"] = "Zone",
  ["guild.col.ilvl"] = "Item level",
  ["guild.col.jobs"] = "Professions",
  ["guild.col.note"] = "Note",
  ["guild.col.last"] = "Last online",
  ["guild.level"] = "Level %d",
  ["guild.ilvl"] = "iLvl %s",
  ["guild.last.online"] = "Online",
  ["guild.last.unknown"] = "unknown",
  ["guild.last.years"] = "%d y ago",
  ["guild.last.months"] = "%d mo ago",
  ["guild.last.day"] = "1 day ago",
  ["guild.last.days"] = "%d days ago",
  ["guild.last.hours"] = "%d h ago",
  ["guild.last.lt1"] = "< 1 h ago",
  ["guild.detail.rank"] = "Rank: %s",
  ["guild.detail.zone"] = "Zone: %s",
  ["guild.detail.last"] = "Last online: %s",
  ["guild.detail.note"] = "Note: %s",
  ["guild.detail.officer"] = "Officer note: %s",
  ["guild.detail.ilvl"] = "Item level: %s",
  ["guild.detail.jobs"] = "Professions: %s",
  ["guild.peer.tip"] = "As of %s, source: %s",
  ["guild.peer.source.game"] = "Game",
  ["guild.peer.source.inspect"] = "Inspect",
  ["guild.peer.source.addon"] = "Add-on",
  ["guild.peer.source.manual"] = "Manual",
  ["guild.peer.now"] = "just now",
  ["guild.peer.minutes"] = "%d min ago",
  ["guild.reading"] = "reading ...",
  ["guild.whisper"] = "Whisper",
  ["guild.seen.local"] = "Stored locally only",
  ["guild.set.heading"] = "Guild: item level and professions",
  ["guild.set.seen"] = "Store data of seen players locally",
  ["guild.set.inspect"] = "Read group item level",
  ["guild.set.inspectHint"] = "Inspects members in range, never in combat.",
  ["guild.set.share"] = "Share jobs, item level",
  ["guild.set.shareHint"] = "Shares your professions and item level with your group and guild, only with players who have Forever Guides. No other data is sent.",
  ["guild.set.shareGuild"] = "Also share with guild",
})
ns.AddLocale("deDE", {
  ["page.guild"] = "Gilde",
  ["guild.tab.guild"] = "Gilde",
  ["guild.none"] = "Du bist in keiner Gilde.",
  ["guild.loading"] = "Gildenliste lädt ...",
  ["guild.online"] = "Online: %d von %d",
  ["guild.motd.title"] = "Tagesnachricht",
  ["guild.motd.empty"] = "Keine Tagesnachricht",
  ["guild.stats.levels"] = "Stufen: %s",
  ["guild.stats.classes"] = "Klassen: %s",
  ["guild.search"] = "Suchen",
  ["guild.onlyOnline"] = "Nur online",
  ["guild.rank"] = "Rang",
  ["guild.rank.all"] = "Alle Ränge",
  ["guild.sort"] = "Sortierung",
  ["guild.sort.rank"] = "Rang",
  ["guild.sort.name"] = "Name",
  ["guild.sort.level"] = "Stufe",
  ["guild.sort.class"] = "Klasse",
  ["guild.sort.zone"] = "Ort",
  ["guild.sort.online"] = "Zuletzt online",
  ["guild.count"] = "%d von %d",
  ["guild.empty"] = "Keine Treffer.",
  ["guild.cols"] = "Spalten",
  ["guild.col.rank"] = "Rang",
  ["guild.col.level"] = "Stufe",
  ["guild.col.zone"] = "Ort",
  ["guild.col.ilvl"] = "Itemlevel",
  ["guild.col.jobs"] = "Berufe",
  ["guild.col.note"] = "Notiz",
  ["guild.col.last"] = "Zuletzt online",
  ["guild.level"] = "Stufe %d",
  ["guild.ilvl"] = "iLvl %s",
  ["guild.last.online"] = "Online",
  ["guild.last.unknown"] = "unbekannt",
  ["guild.last.years"] = "vor %d J.",
  ["guild.last.months"] = "vor %d Mon.",
  ["guild.last.day"] = "vor 1 Tag",
  ["guild.last.days"] = "vor %d Tagen",
  ["guild.last.hours"] = "vor %d Std.",
  ["guild.last.lt1"] = "vor < 1 Std.",
  ["guild.detail.rank"] = "Rang: %s",
  ["guild.detail.zone"] = "Ort: %s",
  ["guild.detail.last"] = "Zuletzt online: %s",
  ["guild.detail.note"] = "Notiz: %s",
  ["guild.detail.officer"] = "Offiziersnotiz: %s",
  ["guild.detail.ilvl"] = "Itemlevel: %s",
  ["guild.detail.jobs"] = "Berufe: %s",
  ["guild.peer.tip"] = "Stand %s, Quelle: %s",
  ["guild.peer.source.game"] = "Spiel",
  ["guild.peer.source.inspect"] = "Betrachten",
  ["guild.peer.source.addon"] = "Addon",
  ["guild.peer.source.manual"] = "Manuell",
  ["guild.peer.now"] = "gerade eben",
  ["guild.peer.minutes"] = "vor %d Min.",
  ["guild.reading"] = "wird gelesen",
  ["guild.whisper"] = "Flüstern",
  ["guild.seen.local"] = "Nur lokal gespeichert",
  ["guild.set.heading"] = "Gilde: Itemlevel und Berufe",
  ["guild.set.seen"] = "Daten gesehener Spieler lokal speichern",
  ["guild.set.inspect"] = "Gruppen-Itemlevel lesen",
  ["guild.set.inspectHint"] = "Betrachtet Mitglieder in Reichweite, nie im Kampf.",
  ["guild.set.share"] = "Berufe, Itemlevel teilen",
  ["guild.set.shareHint"] = "Teilt deine Berufe und dein Itemlevel mit deiner Gruppe und Gilde, nur mit Spielern, die Forever Guides haben. Es werden keine anderen Daten gesendet.",
  ["guild.set.shareGuild"] = "Auch mit Gilde teilen",
})

-- Rows ----------------------------------------------------------------------------------------------

local function guildKey(m)
  return "g:" .. m.key
end

-- Second line of a guild row, the columns that are switched on, "-" for unknown peer data.
-- extra: the columns of add-ons (GuildExt), already wrapped, a failing one answers nil.
local function guildSub(m, rights, peer, extra)
  local on, cols = GL.ColumnOn, columns("guild")
  local parts = {}
  if on(cols, "rank") and m.rankName ~= "" then
    parts[#parts + 1] = m.rankName
  end
  if on(cols, "level") and m.level > 0 then
    parts[#parts + 1] = string.format(L["guild.level"], m.level)
  end
  if on(cols, "zone") and m.zone ~= "" then
    parts[#parts + 1] = m.zone
  end
  if on(cols, "ilvl") then
    parts[#parts + 1] = string.format(L["guild.ilvl"], ilvlText(peer, m.name))
  end
  if on(cols, "jobs") then
    parts[#parts + 1] = string.format(L["guild.detail.jobs"], jobsText(peer, m.name))
  end
  if on(cols, "note") then
    local note, officer = GL.VisibleNotes(m, rights)
    parts[#parts + 1] = note
    parts[#parts + 1] = officer
  end
  for _, col in ipairs(extra) do
    local v = on(cols, col.id) and col.value(m)
    if type(v) == "string" and v ~= "" then
      parts[#parts + 1] = v
    end
  end
  return joinParts(parts)
end

-- details: the sections of add-ons (GuildExt), their lines follow the item level and professions.
local function memberLines(m, rights, peer, details, ctx)
  local lines = {}
  if m.rankName ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.rank"], m.rankName)
  end
  local who = {}
  if m.level > 0 then
    who[#who + 1] = string.format(L["guild.level"], m.level)
  end
  who[#who + 1] = className(m.class, m.className)
  lines[#lines + 1] = joinParts(who)
  if m.zone ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.zone"], m.zone)
  end
  lines[#lines + 1] = string.format(L["guild.detail.last"], GL.LastOnlineText(m, L))
  local note, officer = GL.VisibleNotes(m, rights)
  if note then
    lines[#lines + 1] = string.format(L["guild.detail.note"], note)
  end
  if officer then
    lines[#lines + 1] = string.format(L["guild.detail.officer"], officer)
  end
  peerLines(lines, peer, m.name)
  for _, d in ipairs(details) do
    local extra = d.lines and d.lines(m, ctx)
    for _, line in ipairs(type(extra) == "table" and extra or {}) do
      if type(line) == "string" and line ~= "" then
        lines[#lines + 1] = line
      end
    end
  end
  return lines
end

-- Buttons of the add-on sections for one member: { { key, onClick } }, at most MAX_ACTIONS.
local function memberActions(m, details, ctx)
  local out = {}
  for _, d in ipairs(details) do
    local extra = d.actions and d.actions(m, ctx)
    for _, a in ipairs(type(extra) == "table" and extra or {}) do
      if #out < MAX_ACTIONS and type(a) == "table" and type(a.key) == "string" and type(a.onClick) == "function" then
        out[#out + 1] = {
          key = a.key,
          onClick = function()
            a.onClick(m, ctx)
          end,
        }
      end
    end
  end
  return out
end

-- Page --------------------------------------------------------------------------------------------------

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = {
    tab = "guild",
    search = "",
    online = false,
    rank = "all",
    sort = "rank",
    sel = nil,
    rights = {},
  }
  local refresh, pick

  -- Add-ons (GuildExt): columns and detail sections are read again by syncExt() whenever one registers.
  local extColumns, extDetails = GE.Entries("column"), GE.Entries("detail")
  local syncExt
  local started = false
  local ctx = {
    Roster = GD.Get,
    Rights = GE.Rights,
    Refresh = function()
      refresh()
    end,
    Select = function(m)
      pick(guildKey(m), m.name)
    end,
    Selected = function()
      for _, m in ipairs(GD.Get().members) do
        if guildKey(m) == state.sel then
          return m
        end
      end
    end,
  }
  -- Tab bodies of add-ons by id, built once by syncExt().
  local extTabs = {}

  -- Parts of an extension at the top of the page (a banner for a stand-in source).
  local topParts = ns.DevTools.Build("guild-top", view)

  -- The offer for the GildenManager: a row at the top right, empty while the manager runs.
  local manager = GM.Build(view.content)
  s:Add(manager, { gap = 8 })

  local groups = { guild = {} }
  local function add(group, item, opts)
    groups[group][#groups[group] + 1] = item
    s:Add(item, opts)
    return item
  end

  -- The tab bar cannot grow, so it lives in a holder whose bar is replaced when an add-on adds a tab.
  local tabs = CreateFrame("Frame", nil, view.content)
  tabs.fgId = "guild-tabs"
  function tabs:Select(id)
    self.bar:Select(id)
  end
  local tabSignature
  -- Returns true when the bar was built anew.
  local function syncBar()
    local list = { { id = "guild", key = "guild.tab.guild" } }
    for _, t in ipairs(GE.Entries("tab")) do
      if extTabs[t.id] then
        list[#list + 1] = { id = t.id, key = t.key }
      end
    end
    local parts = {}
    for i, t in ipairs(list) do
      parts[i] = t.id .. "=" .. t.key
    end
    -- A lone tab only repeats the page title.
    tabs:SetShown(#list > 1)
    local signature = table.concat(parts, ",")
    if signature == tabSignature then
      return false
    end
    tabSignature = signature
    if tabs.bar then
      tabs.bar:Hide()
    end
    tabs.bar = W.Tabs(tabs, {
      tabs = list,
      onSelect = function(id)
        state.tab = id
        refresh()
      end,
    })
    tabs.bar:SetAllPoints()
    tabs.buttons = tabs.bar.buttons
    return true
  end
  s:Add(tabs, { height = 28, gap = 12 })
  -- The detail card sits between the filters and the list.
  local detailGuild = newDetail(view.content, "guild")

  function pick(key, target)
    state.sel = state.sel ~= key and key or nil
    detailGuild.target = target
    refresh()
  end
  detailGuild.onClose = function()
    state.sel = nil
    refresh()
  end

  local function columnsChanged()
    refresh()
  end

  -- Switches of add-on columns (guild tab): one per id, after the page's own, in the order of the entries.
  local function syncColumns(f)
    for _, col in ipairs(extColumns) do
      if not f.ext[col.id] then
        f.ext[col.id] = Kit.AddColumnBox(f, "guild", col, columnsChanged)
      end
    end
    local items = {}
    for i = 1, f.base do
      items[i] = f.items[i]
    end
    for _, col in ipairs(extColumns) do
      items[#items + 1] = f.ext[col.id]
    end
    f.items = items
  end

  -- Guild tab ---------------------------------------------------------------------------------------
  local notice = add("guild", ns.AddParagraph(view, nil, { role = "text", color = "textSecondary", gap = 8 }))
  -- Parts of an extension below the notice (the offer to look at sample data), placed by refresh().
  local noticeParts = ns.DevTools.Build("guild-notice", view)
  local title =
    add("guild", ns.AddParagraph(view, nil, { role = "h3", family = "heading", color = "accent2", gap = 2 }))
  local onlineLine = add("guild", ns.AddParagraph(view, nil, { role = "ui", color = "text", gap = 4 }))
  local motd = CreateFrame("Button", nil, view.content)
  motd.text = W.Text(motd, { role = "ui", color = "textSecondary" })
  motd.text:SetPoint("LEFT")
  motd.text:SetPoint("RIGHT")
  local function showMotd(self)
    ns.ShowTooltip(self, L["guild.motd.title"], self.full ~= "" and self.full or L["guild.motd.empty"])
  end
  motd:SetScript("OnEnter", showMotd)
  motd:SetScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(motd, showMotd)
  add("guild", motd, { height = 18, gap = 6 })
  local levelsLine = add("guild", ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 2 }))
  local classesLine = add("guild", ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 10 }))

  local controls = newFlow(view.content)
  local search = W.EditBox(controls, {
    placeholder = "guild.search",
    clear = true,
    onChange = function(text)
      state.search = text
      refresh()
    end,
  })
  search.fgId = "guild-search"
  local onlyOnline = W.Toggle(controls, {
    key = "guild.onlyOnline",
    get = function()
      return state.online
    end,
    set = function(v)
      state.online = v
      refresh()
    end,
  })
  onlyOnline.fgId = "guild-online"
  local rankOptions = {}
  local rank = W.Dropdown(controls, {
    key = "guild.rank",
    width = DROPDOWN_WIDTH,
    options = rankOptions,
    get = function()
      return state.rank
    end,
    set = function(v)
      state.rank = v
      refresh()
    end,
  })
  rank.fgId = "guild-rank"
  local sortOptions = {}
  for _, mode in ipairs(GL.SORTS) do
    sortOptions[#sortOptions + 1] = { value = mode, key = "guild.sort." .. mode }
  end
  local sort = W.Dropdown(controls, {
    key = "guild.sort",
    width = DROPDOWN_WIDTH,
    options = sortOptions,
    get = function()
      return state.sort
    end,
    set = function(v)
      state.sort = v
      refresh()
    end,
  })
  sort.fgId = "guild-sort"
  controls.items = {
    { frame = search, full = true, height = SEARCH_HEIGHT },
    { frame = onlyOnline, width = TOGGLE_WIDTH, height = 46, top = 18 },
    { frame = rank, width = DROPDOWN_WIDTH, height = 46 },
    { frame = sort, width = DROPDOWN_WIDTH, height = 46 },
  }
  add("guild", controls, { gap = 8 })
  add("guild", ns.AddParagraph(view, "guild.cols", { role = "micro", color = "textMuted", gap = 2 }))
  local guildColumns =
    add("guild", Kit.NewColumns(view.content, "guild", GL.COLUMNS.guild, columnsChanged), { gap = 8 })
  local count = add("guild", ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 4 }))
  s:Add(detailGuild, { gap = 12 })

  local guildOpts = { gap = 12 }
  local guildList = K.NewList(view.content, {
    rowHeight = ROW_HEIGHT,
    bind = function(m)
      local peer = peerOf(m.name, m.guid)
      local cols = columns("guild")
      return {
        title = coloredName(m.name, m.class),
        sub = guildSub(m, state.rights, peer, extColumns),
        right = GL.ColumnOn(cols, "last")
            and (m.online and Theme.hexText("success", L["guild.last.online"]) or GL.LastOnlineText(m, L))
          or "",
        selected = state.sel == guildKey(m),
        iconPaint = classIcon(m.class),
        tooltip = GL.PeerTip(peer, ns.U.now(), L),
      }
    end,
    onClick = function(m)
      pick(guildKey(m), m.name)
    end,
  })
  add("guild", guildList, guildOpts)

  local function showGroup(name, shown)
    for _, item in ipairs(groups[name]) do
      item:SetShown(shown)
    end
  end

  local function hideExtTabs()
    for id in pairs(extTabs) do
      showGroup("ext:" .. id, false)
    end
  end

  -- Builds the body of every registered tab once; a build that failed is not tried again until the
  -- add-on registers the tab anew.
  local tried = {}
  local function syncTabs()
    for _, t in ipairs(GE.Entries("tab")) do
      if extTabs[t.id] then
        extTabs[t.id].onShow = t.onShow
      elseif tried[t.id] ~= t.build then
        tried[t.id] = t.build
        local body = t.build(view.content, ctx)
        if type(body) == "table" and body.SetShown then
          if not body.fgGridLayout then
            function body:fgGridLayout()
              return self:GetHeight()
            end
          end
          extTabs[t.id] = { body = body, onShow = t.onShow }
          groups["ext:" .. t.id] = { body }
          s:Add(body, { gap = 12 })
          body:Hide()
        end
      end
    end
  end

  -- Picks up what add-ons registered (also after the page was built): tab bodies, the tab bar, column
  -- switches and detail lines. Selection, filters and page stay in `state`.
  function syncExt()
    extColumns, extDetails = GE.Entries("column"), GE.Entries("detail")
    syncTabs()
    syncColumns(guildColumns)
    local rebuilt = syncBar()
    if not started then
      return
    end
    if rebuilt then
      -- Selecting paints the new bar and refreshes the page.
      tabs:Select(state.tab)
    else
      refresh()
    end
  end
  syncExt()

  -- Name and lines of a guild member in the detail card, plus the buttons of add-on sections.
  local function showMember(m)
    detailGuild.name:SetText(coloredName(m.name, m.class))
    detailGuild.body:SetText(table.concat(memberLines(m, state.rights, peerOf(m.name, m.guid), extDetails, ctx), "\n"))
    detailGuild:SetActions(memberActions(m, extDetails, ctx))
  end

  local function refreshGuild()
    local snap = GD.Get()
    hideExtTabs()
    local ready = snap.inGuild and snap.loaded
    showGroup("guild", ready)
    notice:SetShown(not ready)
    if not ready then
      notice:SetText(L[snap.inGuild and "guild.loading" or "guild.none"])
      state.sel = nil
      return
    end
    state.rights = GD.Rights()
    title:SetText(snap.name)
    onlineLine:SetText(string.format(L["guild.online"], snap.online, #snap.members))
    motd.full = snap.motd
    motd.text:SetText(snap.motd ~= "" and GL.Truncate(snap.motd, GL.MOTD_LENGTH) or L["guild.motd.empty"])
    local stats = GL.Stats(snap.members)
    local levels, classes = {}, {}
    for _, b in ipairs(stats.levels) do
      levels[#levels + 1] = GL.LevelRange(b.lo) .. ": " .. b.count
    end
    for _, c in ipairs(stats.classes) do
      classes[#classes + 1] = className(c.class, "") .. ": " .. c.count
    end
    levelsLine:SetText(string.format(L["guild.stats.levels"], table.concat(levels, ", ")))
    classesLine:SetText(string.format(L["guild.stats.classes"], table.concat(classes, ", ")))
    local ranks = {}
    for _, r in ipairs(snap.ranks) do
      ranks[#ranks + 1] = { value = r.index, text = r.name }
    end
    state.rank = syncOptions(rankOptions, rank, "guild.rank.all", ranks, state.rank)
    onlyOnline.Refresh()
    sort.Refresh()
    local rows = GL.Sort(
      GL.Filter(snap.members, {
        online = state.online,
        rank = state.rank ~= "all" and state.rank or nil,
        search = state.search,
        rights = state.rights,
      }),
      state.sort
    )
    count:SetText(#rows == 0 and L["guild.empty"] or string.format(L["guild.count"], #rows, #snap.members))
    listHeight(guildOpts, #rows)
    guildList:SetData(rows)
    local picked
    for _, m in ipairs(rows) do
      if guildKey(m) == state.sel then
        picked = m
      end
    end
    if picked then
      showMember(picked)
    else
      state.sel = nil
    end
  end

  -- Tab of an add-on: needs the loaded roster like the guild tab, the selection may be any member.
  local function refreshExt(id)
    local snap = GD.Get()
    showGroup("guild", false)
    hideExtTabs()
    local ready = snap.inGuild and snap.loaded
    notice:SetShown(not ready)
    if not ready then
      notice:SetText(L[snap.inGuild and "guild.loading" or "guild.none"])
      state.sel = nil
      return
    end
    state.rights = GD.Rights()
    showGroup("ext:" .. id, true)
    local picked = ctx.Selected()
    if picked then
      showMember(picked)
    else
      state.sel = nil
    end
    if extTabs[id].onShow then
      extTabs[id].onShow(ctx, extTabs[id].body)
    end
  end

  function refresh()
    for _, part in ipairs(topParts) do
      part.Refresh()
    end
    if state.tab ~= "guild" and not extTabs[state.tab] then
      state.tab = "guild"
    end
    manager:Update()
    if state.tab == "guild" then
      refreshGuild()
    else
      refreshExt(state.tab)
    end
    local offer = notice:IsShown() and not GD.Get().inGuild
    for _, part in ipairs(noticeParts) do
      part.Refresh({ offer = offer })
    end
    detailGuild:SetShown(state.sel ~= nil)
    view:Layout()
  end

  function view:Show(params)
    started = true
    local want = params and params[1]
    if want == "guild" or extTabs[want] then
      state.tab = want
    end
    state.sel = nil
    GD.Request()
    tabs:Select(state.tab)
  end
  view.state = state

  ns.On("FG_GUILD_UPDATE", function()
    if container:IsVisible() and (state.tab == "guild" or extTabs[state.tab]) then
      refresh()
    end
  end)
  ns.On("FG_GUILD_SOURCE", function()
    if container:IsVisible() then
      refresh()
    end
  end)
  -- An add-on registered (late, when it is loaded on demand), not while a switch loads it: the
  -- registrations come one by one and FG_SUBADDON_CHANGED follows the load.
  ns.On("FG_GUILDEXT_CHANGED", function()
    if not ns.PackageUI.Busy() then
      syncExt()
    end
  end)
  -- A switch of the add-on changed (the button, the Addons tab, a retry): tabs and the offer follow.
  ns.On("FG_SUBADDON_CHANGED", function()
    syncExt()
  end)
  return view
end

-- The settings card for item level and professions of guild members. The switch for the stored data of
-- seen players sits here because the guild list reads the same data.
function P.AddSettings(view)
  local s = view.stack
  ns.AddHeading(view, "guild.set.heading")
  for _, item in ipairs({
    { "groupInspect", "guild.set.inspect", ns.GroupInspect.Switch, "guild-inspect", "guild.set.inspectHint" },
    { "peerShare", "guild.set.share", ns.PeerComm.Sharing, "guild-share", "guild.set.shareHint" },
    { "peerShareGuild", "guild.set.shareGuild", ns.PeerComm.SharingGuild, "guild-share-guild" },
    { "seenSave", "guild.set.seen", ns.SeenPlayers.Enabled, "guild-seen" },
  }) do
    local toggle = W.Toggle(view.content, {
      key = item[2],
      get = item[3],
      set = function(v)
        Store.set("settings." .. item[1], v)
      end,
    })
    toggle.fgId = item[4]
    s:Add(toggle, { height = 24, gap = item[5] and 2 or 6 })
    if item[5] then
      ns.AddParagraph(view, item[5], { role = "micro", color = "textMuted", gap = 6 })
    end
  end
  ns.DevTools.AddButtons(view, "guild")
end

ns.RegisterPage({
  id = "guild",
  order = 250,
  group = "social",
  title = "page.guild",
  icon = ns.ICONS.guild,
  aliases = { "gilde", "guild", "gilden" },
  -- Old deep links of the former tab "Sozial".
  redirect = function(params)
    if params[1] == "social" or params[1] == "seen" then
      return "contacts"
    end
  end,
  build = build,
})
