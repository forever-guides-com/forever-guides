-- Mounts: every mount of Forever with its source (vendor, drop, reputation, PvP rank, quest, class), level, faction
-- and race, a list on the left and the chosen mount on the right (K.MasterDetail: narrow pages show one of the
-- two with a back button). The owned state follows the spell book and the bags, a checkbox marks the rest per character.
-- Data: Data/Mounts.lua, logic: MountsLogic.
local _, ns = ...
local Theme = ns.Theme
local W, L, K = ns.W, ns.L, ns.PageKit
local P = ns.MountsLogic

ns.AddLocale("enUS", {
  ["page.mounts"] = "Mounts",
  ["page.mounts.sub"] = "All mounts, where to get them and what you own",
  ["mounts.intro"] = "Which mounts exist, where you get each one and what it needs. Mounts you own are marked. Tick the rest yourself if the game does not show them.",
  ["mounts.search"] = "Search",
  ["mounts.searchPh"] = "Mount, vendor or boss",
  ["mounts.source"] = "Source",
  ["mounts.status"] = "Status",
  ["mounts.all"] = "All",
  ["mounts.owned"] = "Owned",
  ["mounts.missing"] = "Missing",
  ["mounts.kind.vendor"] = "Vendor",
  ["mounts.kind.drop"] = "Drop",
  ["mounts.kind.rep"] = "Reputation",
  ["mounts.kind.pvp"] = "PvP rank",
  ["mounts.kind.quest"] = "Quest",
  ["mounts.kind.class"] = "Class mount",
  ["mounts.kind.custom"] = "Forever",
  ["mounts.total"] = "Owned: %d of %d",
  ["mounts.shown"] = "Mounts shown: %d",
  ["mounts.empty"] = "Nothing matches your filters.",
  ["mounts.back"] = "Back",
  ["mounts.attr.level"] = "Level",
  ["mounts.attr.riding"] = "Riding skill",
  ["mounts.attr.races"] = "Races",
  ["mounts.attr.rep"] = "Reputation",
  ["mounts.backTip"] = "Back to the list",
  ["mounts.rank.friendly"] = "Friendly",
  ["mounts.rank.honored"] = "Honored",
  ["mounts.rank.revered"] = "Revered",
  ["mounts.rank.exalted"] = "Exalted",
  ["mounts.state.marked"] = "Owned: you ticked it",
  ["mounts.state.known"] = "Owned: learned by this character",
  ["mounts.state.bag"] = "Owned: in your bags or bank",
  ["mounts.state.none"] = "Not owned yet",
  ["mounts.have"] = "I have this mount",
  ["mounts.haveTip"] = "Saved for this character only",
  ["mounts.unconfirmed"] = "Source not known yet. The mount exists in Forever.",
  ["mounts.sources"] = "Where to get it",
  ["mounts.vendor"] = "Vendor",
  ["mounts.vendorSub"] = "%s, %s",
  ["mounts.vendorPrice"] = "%s",
  ["mounts.vendorNoPlace"] = "Position not known yet",
  ["mounts.dropSub"] = "%s, drop chance %s%%",
  ["mounts.dropSubNoRate"] = "%s",
  ["mounts.rideQuest"] = "Riding training quest",
  ["mounts.quest"] = "Quest",
  ["mounts.pvpRank"] = "PvP rank %d",
  ["mounts.pvpSub"] = "Honor rank needed",
  ["mounts.class.PALADIN"] = "Paladin class quest",
  ["mounts.class.WARLOCK"] = "Warlock class quest",
  ["mounts.classSub"] = "Learned from your class trainer after the quest",
  ["mounts.mapTip"] = "Show the place on the map",
  ["mounts.markerTip"] = "Set a waypoint here",
})

ns.AddLocale("deDE", {
  ["page.mounts"] = "Reittiere",
  ["page.mounts.sub"] = "Alle Reittiere, Bezugsquellen und dein Besitz",
  ["mounts.intro"] = "Welche Reittiere es gibt, wo du jedes bekommst und was es braucht. Reittiere in deinem Besitz sind markiert. Hake den Rest selbst ab, wenn das Spiel sie nicht zeigt.",
  ["mounts.search"] = "Suchen",
  ["mounts.searchPh"] = "Reittier, Händler oder Boss",
  ["mounts.source"] = "Quelle",
  ["mounts.status"] = "Status",
  ["mounts.all"] = "Alle",
  ["mounts.owned"] = "Vorhanden",
  ["mounts.missing"] = "Fehlt",
  ["mounts.kind.vendor"] = "Händler",
  ["mounts.kind.drop"] = "Beute",
  ["mounts.kind.rep"] = "Ruf",
  ["mounts.kind.pvp"] = "PvP-Rang",
  ["mounts.kind.quest"] = "Quest",
  ["mounts.kind.class"] = "Klassenreittier",
  ["mounts.kind.custom"] = "Forever",
  ["mounts.total"] = "Vorhanden: %d von %d",
  ["mounts.shown"] = "Angezeigte Reittiere: %d",
  ["mounts.empty"] = "Zu deinen Filtern gibt es keinen Treffer.",
  ["mounts.back"] = "Zurück",
  ["mounts.attr.level"] = "Stufe",
  ["mounts.attr.riding"] = "Reitfertigkeit",
  ["mounts.attr.races"] = "Völker",
  ["mounts.attr.rep"] = "Ruf",
  ["mounts.backTip"] = "Zurück zur Liste",
  ["mounts.rank.friendly"] = "Freundlich",
  ["mounts.rank.honored"] = "Wohlwollend",
  ["mounts.rank.revered"] = "Respektvoll",
  ["mounts.rank.exalted"] = "Ehrfürchtig",
  ["mounts.state.marked"] = "Vorhanden: von dir abgehakt",
  ["mounts.state.known"] = "Vorhanden: von diesem Charakter gelernt",
  ["mounts.state.bag"] = "Vorhanden: in Taschen oder Bank",
  ["mounts.state.none"] = "Noch nicht vorhanden",
  ["mounts.have"] = "Ich habe dieses Reittier",
  ["mounts.haveTip"] = "Wird nur für diesen Charakter gespeichert",
  ["mounts.unconfirmed"] = "Quelle noch nicht bekannt. Das Reittier gibt es in Forever.",
  ["mounts.sources"] = "Wo du es bekommst",
  ["mounts.vendor"] = "Händler",
  ["mounts.vendorSub"] = "%s, %s",
  ["mounts.vendorPrice"] = "%s",
  ["mounts.vendorNoPlace"] = "Position noch nicht bekannt",
  ["mounts.dropSub"] = "%s, Dropchance %s%%",
  ["mounts.dropSubNoRate"] = "%s",
  ["mounts.rideQuest"] = "Quest für das Reittraining",
  ["mounts.quest"] = "Quest",
  ["mounts.pvpRank"] = "PvP-Rang %d",
  ["mounts.pvpSub"] = "Ehrenrang nötig",
  ["mounts.class.PALADIN"] = "Paladin-Klassenquest",
  ["mounts.class.WARLOCK"] = "Hexenmeister-Klassenquest",
  ["mounts.classSub"] = "Beim Klassenlehrer nach der Quest gelernt",
  ["mounts.mapTip"] = "Ort auf der Karte zeigen",
  ["mounts.markerTip"] = "Wegpunkt hier setzen",
})

local MODEL_HEIGHT = 170
local LIST_ROW = 46
local RIDING = { [40] = 75, [60] = 150 }

-- The title of a quest in the language of the client when it knows it, else the stored one.
local function questTitle(s)
  local api = rawget(_G, "C_QuestLog")
  local fn = type(api) == "table" and api.GetTitleForQuestID
  local ok, title = false, nil
  if type(fn) == "function" then
    ok, title = pcall(fn, s.q)
  end
  return ok and type(title) == "string" and title ~= "" and title or ns.T(s.n)
end

local function priceSub(s)
  local zone = s.z and P.Zone(s.z)
  local place = zone and ns.T(zone) or L["mounts.vendorNoPlace"]
  return s.c and string.format(L["mounts.vendorSub"], P.PriceText(s.c), place) or place
end

-- Title and sub line of one source row.
local function sourceRow(s)
  if s.t == "vendor" then
    return s.n and ns.T(s.n) or L["mounts.vendor"], priceSub(s)
  elseif s.t == "drop" then
    local where = ns.T(s.i)
    return s.n and ns.T(s.n) or ns.T(s.i),
      s.r and string.format(L["mounts.dropSub"], where, s.r) or string.format(L["mounts.dropSubNoRate"], where)
  elseif s.t == "quest" then
    return questTitle(s), s.ride and L["mounts.rideQuest"] or L["mounts.quest"]
  elseif s.t == "pvp" then
    return string.format(L["mounts.pvpRank"], s.rank), L["mounts.pvpSub"]
  end
  return L["mounts.class." .. s.cls] or s.cls, L["mounts.classSub"]
end

local function sourceActions(s)
  local place = P.Place(s)
  if not place then
    return nil
  end
  return {
    {
      icon = "map",
      boxed = true,
      opens = true,
      tooltip = L["kit.placeMap"],
      tooltipText = L["mounts.mapTip"],
      onClick = function()
        K.PlaceOnMap(place)
      end,
    },
    {
      icon = "marker",
      boxed = true,
      tooltip = L["kit.placeMarker"],
      tooltipText = L["mounts.markerTip"],
      onClick = function()
        K.PlaceMarker(place)
      end,
    },
  }
end

local function factionText(m)
  return m.fac and L["kit.faction." .. m.fac] or nil
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = { query = "", kind = "all", faction = "all", status = "all", mount = "", detail = false }
  ns.PageState.Bind(view, state, { "query", "kind", "faction", "status", "mount" })
  local refresh

  ns.AddIntro(view, "mounts.intro")
  local basis = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = Theme.space.sm })

  local search
  local filters
  local function clear()
    state.query, state.kind, state.faction, state.status = "", "all", "all", "all"
    search.edit:SetText("")
    refresh()
  end
  filters = K.FilterBar(view.content, {
    count = function()
      return (state.query ~= "" and 1 or 0)
        + (state.kind ~= "all" and 1 or 0)
        + (state.faction ~= "all" and 1 or 0)
        + (state.status ~= "all" and 1 or 0)
    end,
    reset = clear,
  })
  search = filters:AddSearch({
    key = "mounts.search",
    text = state.query,
    placeholder = "mounts.searchPh",
    width = 220,
    onChange = function(text)
      state.query = text
      refresh()
    end,
  })
  local kindOptions = { { value = "all", key = "mounts.all" } }
  for _, kind in ipairs(P.Kinds()) do
    kindOptions[#kindOptions + 1] = { value = kind, key = "mounts.kind." .. kind }
  end
  filters:AddDropdown({
    key = "mounts.source",
    width = 170,
    options = kindOptions,
    get = function()
      return state.kind
    end,
    set = function(v)
      state.kind = v
      refresh()
    end,
  })
  filters:AddDropdown({
    key = "mounts.status",
    width = 150,
    options = {
      { value = "all", key = "mounts.all" },
      { value = "owned", key = "mounts.owned" },
      { value = "missing", key = "mounts.missing" },
    },
    get = function()
      return state.status
    end,
    set = function(v)
      state.status = v
      refresh()
    end,
  })
  filters:AddGroup(K.FactionButtons(filters, {
    withAll = true,
    get = function()
      return state.faction
    end,
    set = function(v)
      state.faction = v
      refresh()
    end,
  }))
  s:Add(filters, { gap = Theme.space.md })
  K.Anchor("FG.Mounts.Controls", filters)

  local total = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = Theme.space.sm })

  local shown, selected = {}, nil
  local paintDetail, layoutDetail
  local syncing = false

  -- The list is made before the master/detail shell so the keyboard reaches it before the detail.
  local list, split
  list = K.NewList(view.content, {
    look = "boxed",
    bind = function(m)
      local mine = selected ~= nil and selected.id == m.id
      local fac = factionText(m)
      return {
        title = ns.T(m.n),
        sub = fac and (L["mounts.kind." .. m.k] .. ", " .. fac) or L["mounts.kind." .. m.k],
        icon = m.icon,
        iconFrame = true,
        level = m.lvl,
        meta = P.Owned(m) and L["mounts.owned"] or nil,
        metaColor = "success",
        selected = mine,
        cursor = mine,
      }
    end,
    onClick = function(m)
      state.mount, state.detail = m.id, true
      selected = m
      list:SetData(shown)
      paintDetail()
      split:SetSelected(m)
      split:ShowDetail(true)
      view:Layout()
    end,
  })
  K.Anchor("FG.Mounts.List", list)

  split = K.MasterDetail(view.content, {
    list = list,
    backKey = "mounts.back",
    backTip = "mounts.backTip",
    onToggle = function(on)
      if not syncing then
        state.detail = on
      end
    end,
    detail = function(width)
      return layoutDetail(width)
    end,
  })
  K.Anchor("FG.Mounts.Detail", split.detail)
  local content = split.content

  -- Hero: mount icon, name, attribute lines, the owned state as a tag; share at the top right.
  local hero = K.Hero(content, {})
  local actions = W.MapActionButtons(hero, { mapTip = "mounts.mapTip", markerTip = "mounts.markerTip", share = true })
  hero:SetActions(actions)

  -- Model of the mount: drag turns it, the wheel zooms. Created on the first mount with a creature; a client
  -- without the frame type simply shows no model.
  local model, facing, dist
  local function applyView()
    if model then
      pcall(model.SetFacing, model, facing)
      if model.SetCamDistanceScale then
        pcall(model.SetCamDistanceScale, model, dist)
      end
    end
  end
  local function ensureModel()
    if model or model == false then
      return model
    end
    local ok, frame = pcall(CreateFrame, "PlayerModel", nil, content)
    if not (ok and type(frame) == "table") then
      model = false
      return false
    end
    model = frame
    W.Fill(model, "surface", 1)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    local lastX = 0
    model:SetScript("OnMouseDown", function(_, button)
      if button == "LeftButton" then
        lastX = (GetCursorPosition())
        model:SetScript("OnUpdate", ns.Wrap("mount-turn", function()
          local x = GetCursorPosition()
          facing = (facing + (x - lastX) * 0.01) % (2 * math.pi)
          lastX = x
          applyView()
        end))
      end
    end)
    model:SetScript("OnMouseUp", function()
      model:SetScript("OnUpdate", nil)
    end)
    model:SetScript("OnHide", function()
      model:SetScript("OnUpdate", nil)
    end)
    model:SetScript("OnMouseWheel", ns.Wrap("mount-zoom", function(_, delta)
      dist = math.max(0.4, math.min(2.5, dist - (delta > 0 and 0.15 or -0.15)))
      applyView()
    end))
    -- The client resets the camera once a model has loaded.
    model:SetScript("OnModelLoaded", applyView)
    return model
  end
  local previewBtn = W.IconButton(content, {
    icon = "eye",
    boxed = true,
    opens = true,
    tooltip = "preview.open",
    tooltipText = "preview.openTip",
    onClick = function()
      if selected and selected.cr then
        ns.ModelPreview.OpenCreature({ name = ns.T(selected.n), npcId = selected.cr, icon = selected.icon })
      end
    end,
  })
  local have = W.Checkbox(content, {
    key = "mounts.have",
    tooltip = "mounts.have",
    tooltipText = "mounts.haveTip",
    get = function()
      return selected ~= nil and P.IsMarked(selected)
    end,
    set = function(on)
      if selected then
        P.SetMarked(selected, on)
        paintDetail()
        list:SetData(shown)
        total:SetText(string.format(L["mounts.total"], P.Counts(nil, state.faction)))
        view:Layout()
      end
    end,
  })

  -- Where to get it: one boxed row per source (vendor links, map and waypoint buttons), a note while the source
  -- is not known.
  local srcList, srcNote, sources
  local srcShown = 0
  sources = K.SectionCard(content, {
    key = "mounts.sources",
    body = function(w)
      local sm = Theme.space.sm
      local y = 0
      srcList:ClearAllPoints()
      srcList:SetShown(srcShown > 0)
      if srcShown > 0 then
        local h = srcShown * K.scaledHeight(LIST_ROW)
        srcList:SetPoint("TOPLEFT", sources.body, "TOPLEFT", 0, 0)
        srcList:SetSize(w, h)
        y = h + sm
      end
      srcNote:ClearAllPoints()
      local noted = srcNote:IsShown()
      if noted then
        srcNote:SetPoint("TOPLEFT", sources.body, "TOPLEFT", 0, -y)
        y = y + W.FitLabel(srcNote, w)
      elseif srcShown > 0 then
        y = y - sm
      end
      return y
    end,
  })
  srcNote = W.Text(sources.body, { key = "mounts.unconfirmed", role = "ui", color = "textMuted", wrap = true })
  srcList = K.NewList(sources.body, {
    look = "boxed",
    vendorLinks = true,
    rowHeight = LIST_ROW,
    bind = function(src)
      local title, sub = sourceRow(src)
      return { title = title, sub = sub, titleNpc = src.t == "vendor" and src.npc or nil, actions = sourceActions(src) }
    end,
  })

  local function attrs(m)
    local out = {
      { labelKey = "mounts.source", value = L["mounts.kind." .. m.k] },
      { labelKey = "mounts.attr.level", value = tostring(m.lvl) },
    }
    if RIDING[m.lvl] and m.k ~= "class" then
      out[#out + 1] = { labelKey = "mounts.attr.riding", value = tostring(RIDING[m.lvl]) }
    end
    local fac = factionText(m)
    if fac then
      out[#out + 1] = { labelKey = "kit.filterFaction", value = fac }
    end
    if m.race then
      out[#out + 1] = { labelKey = "mounts.attr.races", value = table.concat(P.RaceNames(m.race), ", ") }
    end
    if m.rep then
      out[#out + 1] = {
        labelKey = "mounts.attr.rep",
        value = ns.T(m.rep.n) .. ", " .. L["mounts.rank." .. P.RANKS[m.rep.r]],
      }
    end
    out[#out + 1] = { labelKey = "mounts.status", value = L["mounts.state." .. (P.Owned(m) or "none")] }
    return out
  end

  function paintDetail()
    local on = selected ~= nil
    hero:SetShown(on)
    have:SetShown(on)
    local shownModel = on and selected.cr ~= nil and ensureModel() or false
    if model then
      model:SetShown(shownModel and true or false)
    end
    previewBtn:SetShown(shownModel and true or false)
    if not on then
      sources:Hide()
      return
    end
    if shownModel then
      facing, dist = 0, 1
      pcall(model.SetCreature, model, selected.cr)
      applyView()
    end
    local m = selected
    hero:SetPortrait({ texture = m.icon, name = ns.T(m.n) })
    hero:SetTitle(ns.T(m.n))
    hero:SetSubtitle(L["mounts.kind." .. m.k])
    hero:SetAttrs(attrs(m))
    local owned = P.Owned(m)
    hero:SetTags({
      owned and { key = "mounts.owned", color = "success" } or { key = "mounts.missing", color = "warning" },
    })
    actions:SetPlace(nil)
    actions:SetShare("mounts/" .. m.id)
    have.Refresh()
    srcShown = #m.s
    srcNote:SetShown(m.u == true)
    sources:SetShown(srcShown > 0 or m.u == true)
    sources:SetCount(srcShown > 0 and srcShown or nil)
    srcList:SetData(m.s)
  end

  function layoutDetail(width)
    if not selected then
      return 0
    end
    local gap = Theme.space.lg
    hero:ClearAllPoints()
    hero:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    local y = hero:fgLayout(width) + gap
    if model and model:IsShown() then
      model:ClearAllPoints()
      model:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
      model:SetSize(width, MODEL_HEIGHT)
      previewBtn:SetFrameLevel(model:GetFrameLevel() + 2)
      previewBtn:ClearAllPoints()
      previewBtn:SetPoint("TOPRIGHT", model, "TOPRIGHT", -4, -4)
      y = y + MODEL_HEIGHT + gap
    end
    have:ClearAllPoints()
    have:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    have:SetWidth(width)
    y = y + have:fgGridLayout(width) + gap
    if sources:IsShown() then
      sources:ClearAllPoints()
      sources:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
      y = y + sources:fgLayout(width) + gap
    end
    return y - gap
  end

  s:Add(split, { gap = Theme.space.lg })
  local emptyList = view.stack:Add(W.EmptyState(view.content, { text = "mounts.empty", icon = "search", compact = true }))

  function refresh()
    basis:SetText(ns.T(P.Basis()) or "")
    filters:Refresh()
    shown = P.Filter(state, ns.SearchLogic.match)
    total:SetText(
      string.format(L["mounts.total"], P.Counts(nil, state.faction))
        .. "   "
        .. string.format(L["mounts.shown"], #shown)
    )
    split:SetShown(#shown > 0)
    emptyList:SetAction(filters:IsFiltered() and W.EMPTY_RESET or nil, function()
      filters:Reset()
    end)
    emptyList:SetShown(#shown == 0)
    selected = nil
    for _, m in ipairs(shown) do
      if m.id == state.mount then
        selected = m
      end
    end
    selected = selected or shown[1]
    state.mount = selected and selected.id or ""
    state.detail = state.detail and selected ~= nil
    list:SetData(shown)
    paintDetail()
    -- Narrow pages open on the list unless a mount was asked for.
    syncing = true
    split:SetSelected(selected)
    split:ShowDetail(state.detail)
    syncing = false
    view:Layout()
  end

  -- Page link: the chosen mount.
  function view:ShareState()
    return state.mount ~= "" and { state.mount } or {}
  end

  -- params[1] = a mount id ("i8563" for an item, "s5784" for a spell); unknown ones are ignored.
  function view:Show(params)
    local first = params and params[1]
    if first and P.Mount(first) then
      state.mount = first
    end
    refresh()
  end
  ns.On("FG_UI_REFRESHED", function()
    if container:IsVisible() then
      refresh()
    end
  end)
  return view
end

ns.RegisterPage({
  id = "mounts",
  order = 360,
  group = "learn",
  title = "page.mounts",
  subtitle = "page.mounts.sub",
  icon = ns.ICONS.mounts,
  aliases = { "mounts", "mount", "reittiere", "reittier", "reiten" },
  crumbLabel = function(param)
    local m = P.Mount(param)
    return m and ns.T(m.n) or param
  end,
  build = build,
})
