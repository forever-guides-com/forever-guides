-- Error list: every recorded error of every addon (ErrorCatcher.lua), filterable and
-- sortable, with the full text of the picked entry in a field that can be marked and copied.
-- The list takes all free height, the detail field sits at the bottom.
local _, ns = ...
local W, L, Logic, FL = ns.W, ns.L, ns.ErrorCatcherLogic, ns.FlowLayout

ns.AddLocale("enUS", {
  ["errcatch.filter.scope"] = "Show",
  ["errcatch.scope.all"] = "All",
  ["errcatch.scope.session"] = "This session",
  ["errcatch.scope.own"] = "Forever Guides only",
  ["errcatch.filter.addon"] = "Addon",
  ["errcatch.addon.all"] = "All addons",
  ["errcatch.filter.sort"] = "Sort",
  ["errcatch.sort.recent"] = "Newest first",
  ["errcatch.sort.count"] = "Most frequent",
  ["errcatch.search"] = "Search errors",
  ["errcatch.copyOne"] = "Copy entry",
  ["errcatch.noMatch"] = "No error matches the filter.",
  ["errcatch.clear.title"] = "Clear error list",
  ["errcatch.clear.text"] = "Delete all errors from the list?",
})
ns.AddLocale("deDE", {
  ["errcatch.filter.scope"] = "Anzeigen",
  ["errcatch.scope.all"] = "Alle",
  ["errcatch.scope.session"] = "Diese Sitzung",
  ["errcatch.scope.own"] = "Nur Forever Guides",
  ["errcatch.filter.addon"] = "Addon",
  ["errcatch.addon.all"] = "Alle Addons",
  ["errcatch.filter.sort"] = "Sortierung",
  ["errcatch.sort.recent"] = "Neueste zuerst",
  ["errcatch.sort.count"] = "Häufigste zuerst",
  ["errcatch.search"] = "Fehler suchen",
  ["errcatch.copyOne"] = "Eintrag kopieren",
  ["errcatch.noMatch"] = "Kein Fehler passt zum Filter.",
  ["errcatch.clear.title"] = "Fehlerliste leeren",
  ["errcatch.clear.text"] = "Alle Fehler aus der Liste löschen?",
})

local PAD = 16
local GAP = 8
local ROW_H = 22
local BUTTON_H = 26
local FILTER_H = 46 + 4 + 26
local LIST_SHARE = 0.45

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  ns.Bind(row, function()
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.sel:SetColorTexture(ns.Theme.color("action", 0.5))
  end)
  row.time = W.Text(row, { role = "micro", color = "textMuted" })
  row.time:SetPoint("LEFT", 6, 0)
  row.time:SetWidth(84)
  row.addon = W.Text(row, { role = "ui", color = "accent2" })
  row.addon:SetPoint("LEFT", row.time, "RIGHT", 4, 0)
  row.addon:SetWidth(100)
  row.kind = W.Text(row, { role = "micro", color = "textSecondary" })
  row.kind:SetPoint("LEFT", row.addon, "RIGHT", 4, 0)
  row.kind:SetWidth(64)
  row.count = W.Text(row, { role = "micro", color = "warning", justify = "RIGHT" })
  row.count:SetPoint("RIGHT", -4, 0)
  row.count:SetWidth(40)
  row.msg = W.Text(row, { role = "ui" })
  row.msg:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
  row.msg:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
  return row
end

local function build(container)
  local state = { scope = "all", addon = "", sort = "recent", query = "", sel = nil }
  local items = {}
  local list, detail, empty, buttons
  local refresh

  local filters = CreateFrame("Frame", nil, container)
  filters:SetHeight(FILTER_H)
  filters:SetPoint("TOPLEFT", PAD, -PAD)
  filters:SetPoint("TOPRIGHT", -PAD, -PAD)

  local addonOptions = { { value = "", key = "errcatch.addon.all" } }
  local function dropdown(key, options, get, set)
    return FL.FitDropdown(W.Dropdown(filters, { key = key, options = options, get = get, set = set }))
  end
  local scopeDd = dropdown("errcatch.filter.scope", {
    { value = "all", key = "errcatch.scope.all" },
    { value = "session", key = "errcatch.scope.session" },
    { value = "own", key = "errcatch.scope.own" },
  }, function()
    return state.scope
  end, function(v)
    state.scope = v
    refresh()
  end)
  local addonDd = dropdown("errcatch.filter.addon", addonOptions, function()
    return state.addon
  end, function(v)
    state.addon = v
    refresh()
  end)
  local sortDd = dropdown("errcatch.filter.sort", {
    { value = "recent", key = "errcatch.sort.recent" },
    { value = "count", key = "errcatch.sort.count" },
  }, function()
    return state.sort
  end, function(v)
    state.sort = v
    refresh()
  end)
  local search = W.EditBox(filters, {
    placeholder = "errcatch.search",
    clear = true,
    onChange = function(text)
      state.query = text
      refresh()
    end,
  })
  -- Three dropdowns share the width, the search box takes the line below.
  local function layoutFilters(_, width)
    width = width or filters:GetWidth()
    local gap = 8
    local each = math.max(60, math.floor((width - 2 * gap) / 3))
    for i, dd in ipairs({ scopeDd, addonDd, sortDd }) do
      local x = (i - 1) * (each + gap)
      dd:ClearAllPoints()
      dd:SetPoint("TOPLEFT", filters, "TOPLEFT", x, 0)
      dd:SetPoint("TOPRIGHT", filters, "TOPLEFT", x + each, 0)
    end
    search:ClearAllPoints()
    search:SetPoint("TOPLEFT", filters, "TOPLEFT", 0, -50)
    search:SetPoint("TOPRIGHT", filters, "TOPRIGHT", 0, -50)
  end
  filters:SetScript("OnSizeChanged", layoutFilters)
  layoutFilters(filters, filters:GetWidth())

  local function selected()
    return state.sel
  end
  buttons = FL.ButtonRow(container, {
    {
      id = "copy",
      label = "act.copy",
      icon = "copy",
      tooltip = "errcatch.copyOne",
      width = 130,
      onClick = function()
        local e = selected()
        if e then
          ns.Dialogs.Copy("page.errors", Logic.EntryText(e, L, Logic.CurrentSession()), "help.errorsCopyHint")
        end
      end,
    },
    {
      id = "copyAll",
      label = "act.report",
      icon = "copy",
      tooltip = "help.copyErrors",
      width = 160,
      onClick = function()
        ns.Dialogs.Copy(
          "page.errors",
          Logic.ReportText(ns.Errors.list, L, Logic.CurrentSession()),
          "help.errorsCopyHint"
        )
      end,
    },
    {
      id = "clear",
      label = "act.clear",
      icon = "trash",
      tooltip = "help.clearErrors",
      variant = "ghost",
      width = 130,
      onClick = function()
        ns.Dialogs.Confirm("errcatch.clear.title", "errcatch.clear.text", function()
          ns.Errors.clear()
        end)
      end,
    },
  })
  -- Every block below gets an explicit height: a frame whose height only follows from the
  -- frames around it has no valid rectangle in the client, so what hangs off it stays blank.
  buttons:SetPoint("TOPLEFT", filters, "BOTTOMLEFT", 0, -GAP)
  buttons:SetPoint("TOPRIGHT", filters, "BOTTOMRIGHT", 0, -GAP)
  buttons:SetHeight(BUTTON_H)

  detail = W.TextArea(container, { readOnly = true, height = 120 })

  list = W.ScrollList(container, {
    rowHeight = ROW_H,
    createRow = createRow,
    bindRow = function(row, e)
      local r = Logic.Row(e, L)
      row.entry = e
      row.time:SetText(r.time)
      row.addon:SetText(r.addon)
      row.kind:SetText(r.kind)
      row.count:SetText(r.count)
      row.msg:SetText(r.msg)
      row.sel:SetShown(e == state.sel)
      row:SetScript(
        "OnClick",
        ns.Wrap("errors-row", function()
          state.sel = e
          refresh()
        end)
      )
    end,
  })
  W.Fill(list, "surface", 1)
  empty = W.Text(list, { role = "ui", color = "textMuted", wrap = true })
  empty:SetPoint("TOPLEFT", 10, -10)
  empty:SetPoint("TOPRIGHT", -20, -10)

  -- Below the filters: button row, then the list (45 percent of the free height) and the
  -- detail field (the rest), stacked.
  local function place(listHeight, detailHeight)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", buttons, "BOTTOMLEFT", 0, -GAP)
    list:SetPoint("TOPRIGHT", buttons, "BOTTOMRIGHT", 0, -GAP)
    list:SetHeight(listHeight)
    detail:ClearAllPoints()
    detail:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -GAP)
    detail:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -GAP)
    detail:SetHeight(detailHeight)
  end
  local function layoutPage()
    local width, height = container:GetWidth() or 0, container:GetHeight() or 0
    if width <= 0 or height <= 0 then
      return
    end
    local rowsHeight = math.max(BUTTON_H, buttons:SetWidthAvailable(width - 2 * PAD))
    buttons:SetHeight(rowsHeight)
    local free = height - 2 * PAD - FILTER_H - rowsHeight - 3 * GAP
    local listHeight = math.max(3 * ROW_H, math.floor(free * LIST_SHARE))
    place(listHeight, math.max(80, free - listHeight))
  end
  place(8 * ROW_H, 160)
  container:HookScript("OnSizeChanged", layoutPage)
  layoutPage()

  refresh = function()
    local all = ns.Errors.list
    local names = Logic.Addons(all)
    for i = #addonOptions, 2, -1 do
      addonOptions[i] = nil
    end
    local known = state.addon == ""
    for _, name in ipairs(names) do
      addonOptions[#addonOptions + 1] = { value = name, text = Logic.AddonLabel(name, L) }
      known = known or name == state.addon
    end
    if not known then
      state.addon = ""
    end
    items = Logic.Sort(
      Logic.Filter(
        all,
        { scope = state.scope, addon = state.addon, query = state.query, session = Logic.CurrentSession(), L = L }
      ),
      state.sort
    )
    local present = false
    for _, e in ipairs(items) do
      present = present or e == state.sel
    end
    if not present then
      state.sel = items[1]
    end
    list:SetData(items)
    empty:SetShown(#items == 0)
    empty:SetText(#all == 0 and L["help.noErrors"] or L["errcatch.noMatch"])
    detail:SetValue(state.sel and Logic.EntryText(state.sel, L, Logic.CurrentSession()) or "")
    buttons:SetItemEnabled("copy", state.sel ~= nil)
    buttons:SetItemEnabled("copyAll", #all > 0)
    buttons:SetItemEnabled("clear", #all > 0)
    scopeDd:Refresh()
    addonDd:Refresh()
    sortDd:Refresh()
  end

  ns.On("FG_ERRORS_CHANGED", function()
    if container:IsShown() then
      refresh()
    end
  end)

  local view = {
    list = list,
    detail = detail,
    buttons = buttons,
    state = state,
    search = search,
    addonOptions = addonOptions,
  }
  function view:Show()
    refresh()
    layoutPage()
    -- The page may have no size yet in the frame it is first shown.
    C_Timer.After(0.1, layoutPage)
  end
  function view:Refresh()
    refresh()
  end
  -- The entries the current filter and sort show.
  function view:Items()
    return items
  end
  return view
end

ns.RegisterPage({
  id = "errors",
  order = 230,
  group = "system",
  title = "page.errors",
  icon = ns.ICONS.errors,
  aliases = { "fehler", "errors" },
  build = build,
})
