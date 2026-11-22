-- Legendaries: the Classic legendary items of Forever as a list on the left and the step list of the chosen one on
-- the right (narrow pages show one of the two with a back button). A step is done when the game says so (quest
-- completed, items in bags or bank) or when the player ticks it with a click. Data: Data/Legendaries.lua, logic:
-- LegendariesLogic.
local _, ns = ...
local Theme = ns.Theme
local W, L, K = ns.W, ns.L, ns.PageKit
local P = ns.LegendariesLogic
local LEGENDARIES_ENABLED = false

ns.AddLocale("enUS", {
  ["page.legendaries"] = "Legendaries",
  ["page.legendaries.sub"] = "Quest chains, drops and materials of legendary items",
  ["legendaries.intro"] = "Every step on the way to a legendary item. The game marks quests and items you have. Click a step to tick it yourself.",
  ["legendaries.search"] = "Search",
  ["legendaries.searchPh"] = "Item, quest, boss or NPC",
  ["legendaries.total"] = "Finished: %d of %d",
  ["legendaries.empty"] = "Nothing matches your search.",
  ["legendaries.pick"] = "Choose an item to see its steps.",
  ["legendaries.back"] = "Back",
  ["legendaries.backTip"] = "Back to the list",
  ["legendaries.listSub"] = "%d of %d steps",
  ["legendaries.progress"] = "Progress: %d of %d steps",
  ["legendaries.steps"] = "Steps",
  ["legendaries.hint"] = "Click a step to tick it or to clear the tick.",
  ["legendaries.done"] = "Done",
  ["legendaries.doneMarked"] = "Ticked",
  ["legendaries.open"] = "Open",
  ["legendaries.countName"] = "%dx %s",
  ["legendaries.dropSub"] = "%s, %s, drop chance %s%%",
  ["legendaries.dropSubNoRate"] = "%s, %s",
  ["legendaries.lootSub"] = "Found in %s",
  ["legendaries.craftSub"] = "Crafted with %s",
  ["legendaries.questSub"] = "Quest, %s",
  ["legendaries.questSubZone"] = "Quest, %s in %s",
  ["legendaries.killTitle"] = "Defeat %s",
  ["legendaries.killSub"] = "Drops %s",
  ["legendaries.mapTip"] = "Show the place on the map",
  ["legendaries.markerTip"] = "Set a waypoint here",
  ["legendaries.stepTip"] = "Click to tick or clear",
})

ns.AddLocale("deDE", {
  ["page.legendaries"] = "Legendäre",
  ["page.legendaries.sub"] = "Questketten, Drops und Material legendärer Gegenstände",
  ["legendaries.intro"] = "Jeder Schritt auf dem Weg zu einem legendären Gegenstand. Das Spiel markiert Quests und Gegenstände, die du hast. Klicke einen Schritt an, um ihn selbst abzuhaken.",
  ["legendaries.search"] = "Suchen",
  ["legendaries.searchPh"] = "Gegenstand, Quest, Boss oder NPC",
  ["legendaries.total"] = "Fertig: %d von %d",
  ["legendaries.empty"] = "Zu deiner Suche gibt es keinen Treffer.",
  ["legendaries.pick"] = "Wähle einen Gegenstand, um seine Schritte zu sehen.",
  ["legendaries.back"] = "Zurück",
  ["legendaries.backTip"] = "Zurück zur Liste",
  ["legendaries.listSub"] = "%d von %d Schritten",
  ["legendaries.progress"] = "Fortschritt: %d von %d Schritten",
  ["legendaries.steps"] = "Schritte",
  ["legendaries.hint"] = "Klicke einen Schritt an, um ihn abzuhaken oder den Haken zu löschen.",
  ["legendaries.done"] = "Erledigt",
  ["legendaries.doneMarked"] = "Abgehakt",
  ["legendaries.open"] = "Offen",
  ["legendaries.countName"] = "%dx %s",
  ["legendaries.dropSub"] = "%s, %s, Dropchance %s%%",
  ["legendaries.dropSubNoRate"] = "%s, %s",
  ["legendaries.lootSub"] = "Zu finden in %s",
  ["legendaries.craftSub"] = "Hergestellt mit %s",
  ["legendaries.questSub"] = "Quest, %s",
  ["legendaries.questSubZone"] = "Quest, %s in %s",
  ["legendaries.killTitle"] = "Besiege %s",
  ["legendaries.killSub"] = "Lässt %s fallen",
  ["legendaries.mapTip"] = "Ort auf der Karte zeigen",
  ["legendaries.markerTip"] = "Wegpunkt hier setzen",
  ["legendaries.stepTip"] = "Klicken zum Abhaken oder Löschen",
})

local LIST_ROW = 50
local STEP_ROW = 46
local MIN_HEIGHT = 380
local WIDE_FROM = 640
local GAP = 12

local function questTitle(step)
  local api = rawget(_G, "C_QuestLog")
  local fn = type(api) == "table" and api.GetTitleForQuestID
  local ok, title = false, nil
  if type(fn) == "function" then
    ok, title = pcall(fn, step.q[1])
  end
  return ok and type(title) == "string" and title ~= "" and title or ns.T(step.n)
end

local function stepTexts(step)
  local zone = step.z and P.Zone(step.z)
  local npc = step.nn and ns.T(step.nn) or nil
  if step.t == "quest" then
    local sub = npc and zone and string.format(L["legendaries.questSubZone"], npc, ns.T(zone))
      or string.format(L["legendaries.questSub"], npc or "?")
    return questTitle(step), sub
  elseif step.t == "kill" then
    return string.format(L["legendaries.killTitle"], npc or "?"), string.format(L["legendaries.killSub"], ns.T(step.n))
  end
  local name = ns.T(step.n)
  local title = step.c and step.c > 1 and string.format(L["legendaries.countName"], step.c, name) or name
  if step.t == "drop" then
    local where = ns.T(step.i)
    return title,
      step.r and string.format(L["legendaries.dropSub"], npc or "?", where, step.r)
        or string.format(L["legendaries.dropSubNoRate"], npc or "?", where)
  elseif step.t == "craft" then
    return title, string.format(L["legendaries.craftSub"], ns.T(step.prof))
  end
  return title, string.format(L["legendaries.lootSub"], ns.T(step.i))
end

local function stepActions(step)
  local place = P.Place(step)
  if not place then
    return nil
  end
  return {
    {
      icon = "map",
      boxed = true,
      opens = true,
      tooltip = L["kit.placeMap"],
      tooltipText = L["legendaries.mapTip"],
      onClick = function()
        K.PlaceOnMap(place)
      end,
    },
    {
      icon = "marker",
      boxed = true,
      tooltip = L["kit.placeMarker"],
      tooltipText = L["legendaries.markerTip"],
      onClick = function()
        K.PlaceMarker(place)
      end,
    },
  }
end

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = { query = "", item = "", detail = false }
  ns.PageState.Bind(view, state, { "query", "item" })
  local refresh

  ns.AddIntro(view, "legendaries.intro")
  local basis = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = Theme.space.sm })

  local search
  local filters = K.FilterBar(view.content, {
    count = function()
      return state.query ~= "" and 1 or 0
    end,
    reset = function()
      state.query = ""
      search.edit:SetText("")
      refresh()
    end,
  })
  search = filters:AddSearch({
    key = "legendaries.search",
    text = state.query,
    placeholder = "legendaries.searchPh",
    width = 260,
    onChange = function(text)
      state.query = text
      refresh()
    end,
  })
  s:Add(filters, { gap = Theme.space.md })
  K.Anchor("FG.Legendaries.Controls", filters)

  local total = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = Theme.space.sm })

  local shown, selected = {}, nil
  local paintDetail

  local split = CreateFrame("Frame", nil, view.content)
  local list
  list = K.NewList(split, {
    look = "boxed",
    rowHeight = LIST_ROW,
    bind = function(leg)
      local mine = selected ~= nil and selected.id == leg.id
      local done, count = P.Progress(leg)
      return {
        title = ns.T(leg.n),
        sub = string.format(L["legendaries.listSub"], done, count),
        icon = leg.icon,
        iconFrame = true,
        bar = count > 0 and done / count or 0,
        right = done == count and L["legendaries.done"] or nil,
        selected = mine,
        cursor = mine,
      }
    end,
    onClick = function(leg)
      state.item, state.detail = leg.id, true
      selected = leg
      list:SetData(shown)
      paintDetail()
      view:Layout()
    end,
  })
  K.Anchor("FG.Legendaries.List", list)

  local detail = W.Panel(split)
  K.Anchor("FG.Legendaries.Detail", detail)
  local back = W.Button(detail, {
    key = "legendaries.back",
    tooltip = "legendaries.backTip",
    width = 110,
    onClick = function()
      state.detail = false
      view:Layout()
    end,
  })
  local head = W.Text(detail, { role = "h3", family = "heading", color = "accent2", wrap = true })
  local progress = W.Text(detail, { role = "ui", color = "textSecondary", wrap = true })
  local hint = W.Text(detail, { key = "legendaries.hint", role = "micro", color = "textMuted", wrap = true })
  local pick = W.Text(detail, { key = "legendaries.pick", role = "ui", color = "textMuted", wrap = true })
  local stepList
  stepList = K.NewList(detail, {
    look = "flat", -- step checklist inside the detail panel, nested in a card
    rowHeight = STEP_ROW,
    bind = function(step)
      local title, sub = stepTexts(step)
      local state_ = P.StepState(selected, step)
      return {
        title = title,
        sub = sub,
        icon = step.icon,
        right = state_ == "marked" and L["legendaries.doneMarked"]
          or state_ == "auto" and L["legendaries.done"]
          or L["legendaries.open"],
        tooltip = L["legendaries.stepTip"],
        actions = stepActions(step),
      }
    end,
    onClick = function(step)
      P.SetMarked(selected, step, not P.IsMarked(selected, step))
      paintDetail()
      list:SetData(shown)
      total:SetText(string.format(L["legendaries.total"], P.Finished(), #P.Items()))
    end,
  })

  function paintDetail()
    local on = selected ~= nil
    for _, w in ipairs({ back, head, progress, hint, stepList }) do
      w:SetShown(on)
    end
    pick:SetShown(not on)
    if not on then
      return
    end
    head:SetText(ns.T(selected.n))
    progress:SetText(string.format(L["legendaries.progress"], P.Progress(selected)))
    stepList:SetData(selected.steps)
  end

  local function layoutDetail(width, height, narrow)
    local pad = detail.pad
    local inner = width - pad * 2
    detail:SetSize(width, height)
    pick:ClearAllPoints()
    pick:SetPoint("TOPLEFT", detail, "TOPLEFT", pad, -pad)
    pick:SetWidth(inner)
    if not selected then
      return
    end
    local y = pad
    back:ClearAllPoints()
    back:SetPoint("TOPLEFT", detail, "TOPLEFT", pad, -y)
    back:SetShown(narrow)
    if narrow then
      y = y + back:GetHeight() + 8
    end
    for _, w in ipairs({ head, progress, hint }) do
      w:ClearAllPoints()
      w:SetPoint("TOPLEFT", detail, "TOPLEFT", pad, -y)
      w:SetWidth(inner)
      y = y + math.ceil(w:GetStringHeight()) + 6
    end
    stepList:ClearAllPoints()
    stepList:SetPoint("TOPLEFT", detail, "TOPLEFT", pad, -y)
    stepList:SetSize(inner, math.max(K.scaledHeight(STEP_ROW) * 2, height - y - pad))
  end

  function split:fgGridLayout(width, room)
    local free = room and (room.viewHeight - room.top - room.pad) or 0
    local full = math.max(K.scaledHeight(MIN_HEIGHT), math.floor(free))
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
    detail:ClearAllPoints()
    if width >= WIDE_FROM then
      local listW = math.max(240, math.min(320, math.floor(width * 0.34)))
      list:SetSize(listW, full)
      list:Show()
      detail:Show()
      detail:SetPoint("TOPLEFT", split, "TOPLEFT", listW + GAP, 0)
      layoutDetail(width - listW - GAP, full, false)
    else
      local showDetail = state.detail and selected ~= nil
      list:SetShown(not showDetail)
      detail:SetShown(showDetail)
      list:SetSize(width, full)
      detail:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
      layoutDetail(width, full, true)
    end
    self:SetHeight(full)
    return full
  end
  s:Add(split, { gap = Theme.space.lg })
  local emptyList = view.stack:Add(W.EmptyState(view.content, { text = "legendaries.empty", icon = "search", compact = true }))

  function refresh()
    basis:SetText(ns.T(P.Basis()) or "")
    filters:Refresh()
    shown = P.Filter(state.query, ns.SearchLogic.match)
    total:SetText(string.format(L["legendaries.total"], P.Finished(), #P.Items()))
    split:SetShown(#shown > 0)
    emptyList:SetAction(filters:IsFiltered() and W.EMPTY_RESET or nil, function()
      filters:Reset()
    end)
    emptyList:SetShown(#shown == 0)
    selected = nil
    for _, leg in ipairs(shown) do
      if leg.id == state.item then
        selected = leg
      end
    end
    selected = selected or shown[1]
    state.item = selected and selected.id or ""
    state.detail = state.detail and selected ~= nil
    list:SetData(shown)
    paintDetail()
    view:Layout()
  end

  -- params[1] = a legendary id (deep link, /fg legendaries thunderfury); unknown ones are ignored.
  function view:Show(params)
    local first = params and params[1]
    if first and P.Item(first) then
      state.item = first
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

ns.LegendariesPage = {
  id = "legendaries",
  order = 370,
  group = "learn",
  title = "page.legendaries",
  subtitle = "page.legendaries.sub",
  icon = ns.ICONS.legendaries,
  aliases = { "legendaries", "legendary", "legendaere", "legendäre", "thunderfury", "sulfuras", "atiesh" },
  crumbLabel = function(param)
    local leg = P.Item(param)
    return leg and ns.T(leg.n) or param
  end,
  build = build,
}

-- Hidden from every menu for now; flip the flag to bring the page back.
if LEGENDARIES_ENABLED then
  ns.RegisterPage(ns.LegendariesPage)
end
