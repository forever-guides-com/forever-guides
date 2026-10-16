-- The contacts view of the page "Kontakte": every player met (group, dungeon, trade, ...), paginated,
-- with a whisper, an invite and an update button in every row, and a detail card that tells when and
-- where the player was last seen and how the contact began (NearbyContacts keeps the sighting current,
-- the first contact never changes). The page (ContactsPage.lua) owns the selection and the stack; this
-- file builds the widgets into it and fills them. The data comes from SeenPlayers (looked up when
-- used) or from the stand-in source of GuildData.
local _, ns = ...
local W, L, K = ns.W, ns.L, ns.PageKit
local GL, CL, GD, PN, Kit = ns.GuildLogic, ns.ContactsLogic, ns.GuildData, ns.PlayerName, ns.GuildKit
local coloredName, className, classIcon, whisper, joinParts =
  Kit.ColoredName, Kit.ClassName, Kit.ClassIcon, Kit.Whisper, Kit.JoinParts
local columns, peerOf, ilvlText, jobsText, peerLines =
  Kit.Columns, Kit.PeerOf, Kit.IlvlText, Kit.JobsText, Kit.PeerLines
local syncOptions, listHeight = Kit.SyncOptions, Kit.ListHeight

local CV = {}
ns.ContactsView = CV

local DROPDOWN_WIDTH = Kit.DROPDOWN_WIDTH
local SEARCH_HEIGHT = Kit.SEARCH_HEIGHT
local PAGER_BUTTON = 90
local WHISPER_ICON, INVITE_ICON, UPDATE_ICON = "pencil", "plus", "refresh" -- icons of ns.UI_ICONS
local SOURCES = { group = true, raid = true, dungeon = true, trade = true, guild = true, target = true }

-- The local list of seen players is resolved when it is used, so the page loads without it.
local function seen()
  return ns.SeenPlayers
end

-- Texts -------------------------------------------------------------------------------------------------

local function sourceText(e)
  return SOURCES[e.src] and L["guild.src." .. e.src] or ""
end

-- "10/09" or "09.10.", "" for an unknown time.
local function dateText(t)
  if type(t) ~= "number" or t <= 0 then
    return ""
  end
  local ok, text = pcall(date, L["guild.date"], t)
  return ok and type(text) == "string" and text or ""
end

local function seenKey(e)
  return "s:" .. PN.Key(e.name)
end

local function seenSub(e, peer)
  local on, cols = GL.ColumnOn, columns("social")
  local parts = {}
  if on(cols, "race") and e.race ~= "" then
    parts[#parts + 1] = e.raceName ~= "" and e.raceName or e.race
  end
  if on(cols, "class") and e.class ~= "" then
    parts[#parts + 1] = className(e.class, "")
  end
  if on(cols, "level") and e.level > 0 then
    parts[#parts + 1] = string.format(L["guild.level"], e.level)
  end
  if on(cols, "zone") and e.zone ~= "" then
    parts[#parts + 1] = e.zone
  end
  if on(cols, "ilvl") then
    parts[#parts + 1] = string.format(L["guild.ilvl"], ilvlText(peer, e.name))
  end
  if on(cols, "jobs") then
    parts[#parts + 1] = string.format(L["guild.detail.jobs"], jobsText(peer, e.name))
  end
  if on(cols, "guild") and CL.GuildText(e) ~= "" then
    parts[#parts + 1] = CL.GuildText(e)
  end
  return joinParts(parts)
end

local function seenRight(e)
  local on, cols = GL.ColumnOn, columns("social")
  local parts = {}
  if on(cols, "seen") then
    parts[#parts + 1] = GL.PeerAgeText(ns.U.now() - e.t, L)
  end
  if on(cols, "source") and sourceText(e) ~= "" then
    parts[#parts + 1] = sourceText(e)
  end
  return joinParts(parts)
end

-- Role, AFK, range and connection of a current group member, one "Group: ..." line.
local function liveLines(lines, live)
  if live.role then
    lines[#lines + 1] = string.format(L["guild.detail.role"], L["guild.role." .. live.role])
  end
  local state = {}
  if live.online == false then
    state[#state + 1] = L["guild.live.offline"]
  end
  if live.afk then
    state[#state + 1] = L["guild.live.afk"]
  end
  if live.range then
    state[#state + 1] = L["guild.live." .. live.range]
  end
  if #state > 0 then
    lines[#lines + 1] = string.format(L["guild.detail.live"], table.concat(state, ", "))
  end
end

-- live: SeenPlayers.Live of a current group member (its zone is the member's own), else nil.
local function seenLines(e, peer, live)
  live = live or {}
  local lines = {}
  if e.race ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.race"], e.raceName ~= "" and e.raceName or e.race)
  end
  local who = {}
  if e.level > 0 then
    who[#who + 1] = string.format(L["guild.level"], e.level)
  end
  if e.class ~= "" then
    who[#who + 1] = className(e.class, "")
  end
  if #who > 0 then
    lines[#lines + 1] = joinParts(who)
  end
  if CL.GuildText(e) ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.guild"], CL.GuildText(e))
  end
  if (e.title or "") ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.title"], e.title)
  end
  local status = {}
  if e.pvp == true then
    status[#status + 1] = L["guild.detail.pvp"]
  end
  if (tonumber(e.honor) or 0) > 0 then
    status[#status + 1] = string.format(L["guild.detail.honor"], e.honor)
  end
  if #status > 0 then
    lines[#lines + 1] = joinParts(status)
  end
  if live.zone then
    lines[#lines + 1] = string.format(L["guild.detail.zone"], live.zone)
  end
  liveLines(lines, live)
  local ago = GL.PeerAgeText(ns.U.now() - e.t, L)
  lines[#lines + 1] = e.zone ~= "" and string.format(L["guild.detail.seenIn"], ago, e.zone)
    or string.format(L["guild.detail.seen"], ago)
  local first = e.first or { t = e.t, src = e.src, zone = e.zone }
  local firstText =
    CL.FirstContactText(first, L, SOURCES[first.src] and L["guild.src." .. first.src] or "", dateText(first.t))
  if firstText ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.first"], firstText)
  end
  if type(e.who) == "table" and (tonumber(e.who.t) or 0) > 0 then
    local whoAgo = GL.PeerAgeText(ns.U.now() - e.who.t, L)
    lines[#lines + 1] = e.who.zone ~= "" and string.format(L["nearby.who.online"], whoAgo, e.who.zone)
      or string.format(L["nearby.who.onlineNoZone"], whoAgo)
  end
  peerLines(lines, peer, e.name)
  return lines
end

-- Row buttons ---------------------------------------------------------------------------------------------

-- Guild roster member of a name (offline state for the invite button), rebuilt per roster snapshot.
local rosterIndex, rosterFor
local function guildMember(name)
  local snap = GD.Get()
  if rosterFor ~= snap then
    rosterIndex, rosterFor = {}, snap
    for _, m in ipairs(snap.members) do
      rosterIndex[m.key] = m
    end
  end
  return rosterIndex[PN.Key(name)]
end

-- The three icon buttons of a contact row (whisper, invite, update, from the right). A button that
-- cannot work is dimmed with the reason as its tooltip text; with a stand-in source nothing is sent or
-- asked. refresh redraws the page after a query, so the dimmed state shows at once.
local function rowActions(e, refresh)
  local source = GD.Source()
  local member = not source and guildMember(e.name) or nil
  local offline = member ~= nil and not member.online
  local reason = source and "source" or ns.Invites.GroupInviteBlock(e.name, e.guid, offline)
  local whyNot, wait = ns.NearbyWho.Block()
  whyNot = source and "source" or whyNot
  return {
    {
      icon = WHISPER_ICON,
      boxed = true,
      tooltip = L["guild.whisper"],
      tooltipText = L["guild.whisper.tip"],
      onClick = function()
        whisper(e.name)
      end,
    },
    {
      icon = INVITE_ICON,
      boxed = true,
      dim = reason ~= nil,
      tooltip = L["guild.invite"],
      tooltipText = reason and (source and L[source.why.invite] or L["invite.why." .. reason]) or L["guild.invite.tip"],
      onClick = function()
        ns.Invites.InviteToGroup(e.name, e.guid, offline)
      end,
    },
    {
      icon = UPDATE_ICON,
      boxed = true,
      dim = whyNot ~= nil,
      tooltip = L["nearby.who.update"],
      tooltipText = whyNot and (source and L[source.why.update] or ns.NearbyWho.WhyText(whyNot, wait))
        or L["nearby.who.tip"],
      onClick = function()
        ns.NearbyWho.Request(e)
        refresh()
      end,
    },
  }
end

-- View --------------------------------------------------------------------------------------------------

-- Builds the widgets into the page's stack. host: view (the page view), add(item, opts) (puts an item on
-- the stack), state (the page state: sel, contacts), detail (the detail card), pick(key, name) (selects
-- a row), refresh() (redraws the page), container (the page frame). Returns { Refresh }, which fills the
-- page with the current data.
function CV.Build(host)
  local view, add, state, detail = host.view, host.add, host.state, host.detail
  local c = state.contacts
  local function refresh()
    host.refresh()
  end

  local info = add(ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 6 }))
  local controls = Kit.NewFlow(view.content)
  local search = W.EditBox(controls, {
    placeholder = "guild.search",
    clear = true,
    onChange = function(text)
      c.search, c.page = text, 1
      refresh()
    end,
  })
  search.fgId = "social-search"
  local raceOptions, classOptions = {}, {}
  local raceDropdown = W.Dropdown(controls, {
    key = "guild.race",
    width = DROPDOWN_WIDTH,
    options = raceOptions,
    get = function()
      return c.race
    end,
    set = function(v)
      c.race, c.page = v, 1
      refresh()
    end,
  })
  raceDropdown.fgId = "social-race"
  local classDropdown = W.Dropdown(controls, {
    key = "guild.class",
    width = DROPDOWN_WIDTH,
    options = classOptions,
    get = function()
      return c.class
    end,
    set = function(v)
      c.class, c.page = v, 1
      refresh()
    end,
  })
  classDropdown.fgId = "social-class"
  local sortOptions = {}
  for _, mode in ipairs(CL.SEEN_SORTS) do
    sortOptions[#sortOptions + 1] = { value = mode, key = "guild.sort." .. mode }
  end
  local sort = W.Dropdown(controls, {
    key = "guild.sort",
    width = DROPDOWN_WIDTH,
    options = sortOptions,
    get = function()
      return c.sort
    end,
    set = function(v)
      c.sort, c.page = v, 1
      refresh()
    end,
  })
  sort.fgId = "social-sort"
  controls.items = {
    { frame = search, full = true, height = SEARCH_HEIGHT },
    { frame = raceDropdown, width = DROPDOWN_WIDTH, height = 46 },
    { frame = classDropdown, width = DROPDOWN_WIDTH, height = 46 },
    { frame = sort, width = DROPDOWN_WIDTH, height = 46 },
  }
  add(controls, { gap = 8 })
  add(ns.AddParagraph(view, "guild.cols", { role = "micro", color = "textMuted", gap = 2 }))
  add(Kit.NewColumns(view.content, "social", CL.COLUMNS, refresh), { gap = 8 })
  local count = add(ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 4 }))

  local pager = Kit.NewFlow(view.content)
  local prev = W.Action(pager, {
    label = "act.back",
    icon = "chevron-left",
    tooltip = "guild.prev",
    width = PAGER_BUTTON,
    height = 24,
    onClick = function()
      c.page = c.page - 1
      refresh()
    end,
  })
  prev.fgId = "social-prev"
  local nextPage = W.Action(pager, {
    label = "act.next",
    icon = "chevron-right",
    tooltip = "guild.next",
    width = PAGER_BUTTON,
    height = 24,
    onClick = function()
      c.page = c.page + 1
      refresh()
    end,
  })
  nextPage.fgId = "social-next"
  local pageLabel = W.Text(pager, { role = "ui", color = "textSecondary" })
  pager.items = {
    { frame = prev, width = PAGER_BUTTON, height = 24 },
    { frame = nextPage, width = PAGER_BUTTON, height = 24 },
    { frame = pageLabel, width = 140, height = 24 },
  }
  add(pager, { gap = 8 })
  view.stack:Add(detail, { gap = 12 })

  local listOpts = { gap = 12 }
  local list = K.NewList(view.content, {
    rowHeight = Kit.ROW_HEIGHT,
    bind = function(e)
      local peer = peerOf(e.name, e.guid)
      return {
        title = coloredName(e.name, e.class),
        sub = seenSub(e, peer),
        right = seenRight(e),
        selected = state.sel == seenKey(e),
        iconPaint = classIcon(e.class),
        tooltip = GL.PeerTip(peer, ns.U.now(), L),
        actions = rowActions(e, refresh),
      }
    end,
    onClick = function(e)
      host.pick(seenKey(e), e.name)
    end,
  })
  add(list, listOpts)

  ns.On("FG_SEEN_UPDATE", function()
    if host.container:IsVisible() then
      refresh()
    end
  end)

  local function fill()
    local source = GD.Source()
    local rowsOf = source and source.seen() or seen().List()
    info:SetText(
      source and L[source.seenNote]
        or L["guild.seen.local"]
          .. (seen().Enabled() and "" or "\n" .. L["guild.seen.off"])
          .. "\n"
          .. L["guild.seen.privacy"]
    )
    local races, classes = {}, {}
    for _, choice in ipairs(CL.SeenChoices(rowsOf, "race")) do
      races[#races + 1] = { value = choice.value, text = choice.label }
    end
    for _, choice in ipairs(CL.SeenChoices(rowsOf, "class")) do
      classes[#classes + 1] = { value = choice.value, text = className(choice.value, "") }
    end
    c.race = syncOptions(raceOptions, raceDropdown, "guild.race.all", races, c.race)
    c.class = syncOptions(classOptions, classDropdown, "guild.class.all", classes, c.class)
    sort.Refresh()
    local rows = CL.SeenSort(
      CL.SeenFilter(rowsOf, {
        race = c.race ~= "all" and c.race or nil,
        class = c.class ~= "all" and c.class or nil,
        search = c.search,
      }),
      c.sort
    )
    local items, page, pages = CL.Page(rows, c.page)
    c.page = page
    count:SetText(
      #rowsOf == 0 and L["guild.seen.empty"]
        or (#rows == 0 and L["guild.empty"] or string.format(L["guild.count"], #rows, #rowsOf))
    )
    pageLabel:SetText(string.format(L["guild.page"], page, pages))
    if page > 1 then
      prev:Enable()
    else
      prev:Disable()
    end
    if page < pages then
      nextPage:Enable()
    else
      nextPage:Disable()
    end
    listHeight(listOpts, #items)
    list:SetData(items)
    local picked
    for _, e in ipairs(items) do
      if seenKey(e) == state.sel then
        picked = e
      end
    end
    if picked then
      local live = not source and seen().Live(picked.guid, picked.name) or nil
      detail.name:SetText(coloredName(picked.name, picked.class))
      detail.body:SetText(table.concat(seenLines(picked, peerOf(picked.name, picked.guid), live), "\n"))
      detail:SetActions({})
    else
      state.sel = nil
    end
  end

  return { Refresh = fill }
end

-- Settings parts --------------------------------------------------------------------------------------------

-- The switch for the friendly player name plates: state line, button and the explanation. Only a click
-- changes the game's setting.
function CV.AddPlates(view)
  local s = view.stack
  local state = W.Text(view.content, { role = "ui", color = "textSecondary", wrap = true })
  local function paint()
    state:SetText(string.format(L["guild.plates.state"], L["guild.plates." .. ns.NearbyContacts.PlatesState()]))
  end
  state.Refresh = paint
  ns.Bind(state, paint)
  s:Add(state, { gap = 4 })
  local row = ns.FlowLayout.ButtonRow(view.content, {
    {
      id = "plates",
      label = "act.enable",
      icon = "check",
      tooltip = "guild.plates.enable",
      fgId = "guild-plates",
      onClick = function()
        local ok, reason = ns.NearbyContacts.EnablePlates()
        ns.Notify(L[ok and "guild.plates.done" or "guild.plates." .. reason], ok and "success" or "warning")
        paint()
      end,
    },
  })
  s:Add(row, { gap = 4 })
  ns.AddParagraph(view, "guild.plates.hint", { role = "micro", color = "textMuted", gap = 8 })
end

-- The button that deletes the whole list (it asks first).
function CV.AddClear(view)
  local clear = W.Action(view.content, {
    label = "act.clear",
    icon = "trash",
    tooltip = "guild.set.clear",
    width = 180,
    onClick = function()
      seen().ConfirmClear()
    end,
  })
  clear.fgId = "guild-clear"
  view.stack:Add(clear, { height = 26, width = 180, gap = 6 })
end

function CV.AddLocalNote(view)
  ns.AddParagraph(view, "guild.seen.local", { role = "micro", color = "textMuted" })
end
