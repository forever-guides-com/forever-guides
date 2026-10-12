-- Global search results: a "best matches" block, then all hits grouped by kind (header with
-- count, "show more"); recent searches without a query; a typo suggestion and a website link when
-- nothing matches. Arrow keys move a cursor through the hits, Enter opens it. Logic: ns.SearchLogic.
local _, ns = ...
local L, K, W, U, Theme = ns.L, ns.PageKit, ns.W, ns.U, ns.Theme

ns.AddLocale("enUS", {
  ["search.hint"] = "Type a term (Ctrl+F). Arrow keys pick, Enter opens, Esc clears. Case and umlauts do not matter.",
  ["search.total"] = '%d result(s) for "%s"',
  ["search.none"] = "Nothing found.",
  ["search.none.hint"] = "Check the spelling or use a shorter word. Spaces and umlauts do not matter.",
  ["search.empty.text"] = "Search the whole guide",
  ["search.empty.hint"] = "Pages, classes, races, instances, bosses, quests, places, trainers, abilities, items, recipes and profession trainers. Try Silverleaf, Gnomeregan or Copper.",
  ["search.group"] = "%s (%d)",
  ["search.group.page"] = "Pages",
  ["search.group.class"] = "Classes",
  ["search.group.race"] = "Races",
  ["search.group.instance"] = "Instances",
  ["search.group.boss"] = "Bosses",
  ["search.group.quest"] = "Quests",
  ["search.group.place"] = "Places",
  ["search.group.trainer"] = "Trainers",
  ["search.group.weaponMaster"] = "Weapon masters",
  ["search.group.weapon"] = "Weapon skills",
  ["search.group.ability"] = "Abilities",
  ["search.showMore"] = "Show more (%d)",
  ["search.showMore.sub"] = "Shows every hit of this group.",
  ["search.recent"] = "Recent searches",
  ["search.recent.sub"] = "Search again",
  ["search.recent.clear"] = "Clear history",
  ["search.recent.clearSub"] = "Removes the saved searches.",
  ["search.sourceError"] = 'The search source "%s" failed. The other sources keep working.',
  ["search.sourceFailed"] = "Not searched: %s.",
  ["search.best"] = "Best matches",
  ["search.all"] = "By type",
  ["search.didYouMean"] = 'Did you mean "%s"?',
  ["search.web"] = "Search on forever-guides.com",
  ["search.web.title"] = "Website search",
  ["search.web.hint"] = "Copy the link, open it in your browser.",
  ["search.kind.page"] = "Page",
  ["search.kind.class"] = "Class",
  ["search.kind.race"] = "Race",
  ["search.kind.instance"] = "Instance",
  ["search.kind.boss"] = "Boss",
  ["search.kind.quest"] = "Quest",
  ["search.kind.place"] = "Place",
  ["search.kind.trainer"] = "Trainer",
  ["search.kind.weaponMaster"] = "Weapon master",
  ["search.kind.weapon"] = "Weapon skill",
  ["search.kind.ability"] = "Ability",
  ["tour.search.title"] = "Search",
  ["tour.search.intro.title"] = "Search",
  ["tour.search.intro.text"] = "Finds pages, instances, bosses, quests, places, trainers, abilities, items, recipes and profession trainers.",
  ["tour.search.box.title"] = "Search field",
  ["tour.search.box.text"] = "Ctrl+F jumps here, Enter shows the results.",
  ["tour.search.results.title"] = "Results",
  ["tour.search.results.text"] = "Tab to a result and press Enter to open it.",
})

ns.AddLocale("deDE", {
  ["search.hint"] = "Begriff eingeben (Strg+F). Pfeiltasten wählen, Enter öffnet, Esc leert. Groß-/Kleinschreibung und Umlaute egal.",
  ["search.total"] = '%d Treffer für "%s"',
  ["search.none"] = "Nichts gefunden.",
  ["search.none.hint"] = "Prüfe die Schreibweise oder nimm ein kürzeres Wort. Leerzeichen und Umlaute spielen keine Rolle.",
  ["search.empty.text"] = "Alles durchsuchen",
  ["search.empty.hint"] = "Seiten, Klassen, Völker, Instanzen, Bosse, Quests, Orte, Lehrer, Fähigkeiten, Items, Rezepte und Berufslehrer. Probiere Silberblatt, Gnomeregan oder Kupfer.",
  ["search.group"] = "%s (%d)",
  ["search.group.page"] = "Seiten",
  ["search.group.class"] = "Klassen",
  ["search.group.race"] = "Völker",
  ["search.group.instance"] = "Instanzen",
  ["search.group.boss"] = "Bosse",
  ["search.group.quest"] = "Quests",
  ["search.group.place"] = "Orte",
  ["search.group.trainer"] = "Lehrer",
  ["search.group.weaponMaster"] = "Waffenmeister",
  ["search.group.weapon"] = "Waffenfertigkeiten",
  ["search.group.ability"] = "Fähigkeiten",
  ["search.showMore"] = "Mehr anzeigen (%d)",
  ["search.showMore.sub"] = "Zeigt jeden Treffer dieser Gruppe.",
  ["search.recent"] = "Letzte Suchen",
  ["search.recent.sub"] = "Erneut suchen",
  ["search.recent.clear"] = "Verlauf löschen",
  ["search.recent.clearSub"] = "Entfernt die gespeicherten Suchen.",
  ["search.sourceError"] = 'Die Suchquelle "%s" ist ausgefallen. Die anderen Quellen laufen weiter.',
  ["search.sourceFailed"] = "Nicht durchsucht: %s.",
  ["search.best"] = "Beste Treffer",
  ["search.all"] = "Nach Art",
  ["search.didYouMean"] = 'Meintest du "%s"?',
  ["search.web"] = "Auf forever-guides.com suchen",
  ["search.web.title"] = "Suche auf der Website",
  ["search.web.hint"] = "Link kopieren, im Browser öffnen.",
  ["search.kind.page"] = "Seite",
  ["search.kind.class"] = "Klasse",
  ["search.kind.race"] = "Volk",
  ["search.kind.instance"] = "Instanz",
  ["search.kind.boss"] = "Boss",
  ["search.kind.quest"] = "Quest",
  ["search.kind.place"] = "Ort",
  ["search.kind.trainer"] = "Lehrer",
  ["search.kind.weaponMaster"] = "Waffenmeister",
  ["search.kind.weapon"] = "Waffenfertigkeit",
  ["search.kind.ability"] = "Fähigkeit",
  ["tour.search.title"] = "Suche",
  ["tour.search.intro.title"] = "Suche",
  ["tour.search.intro.text"] = "Findet Seiten, Instanzen, Bosse, Quests, Orte, Lehrer, Fähigkeiten, Items, Rezepte und Berufslehrer.",
  ["tour.search.box.title"] = "Suchfeld",
  ["tour.search.box.text"] = "Strg+F springt hierher, Enter zeigt die Treffer.",
  ["tour.search.results.title"] = "Treffer",
  ["tour.search.results.text"] = "Mit Tab zu einem Treffer, Enter öffnet ihn.",
})

-- The page's own input mirrors the header box (ns.Main.search). `state` is the
-- most recently built page view, the header hooks below act on it only while
-- its container is shown.
local LIVE_DELAY = 0.15
-- Two lines plus the boxed action buttons (20 px) under the kind label.
local ROW_HEIGHT = 42
local state
local previousPage

local function normalize(text)
  return (U.trim(text or ""):gsub("/", " "))
end

local function pageVisible()
  return state ~= nil and state.container:IsShown()
end

local function headerEdit()
  return ns.Main and ns.Main.search and ns.Main.search.edit
end

local function kindLabel(kind)
  return L["search.kind." .. kind]
end

-- "Rezepte (12)": the plural of a kind with its hit count.
local function groupLabel(kind, count)
  local plural = L["search.group." .. kind]
  if plural == "search.group." .. kind then
    plural = kindLabel(kind)
  end
  return string.format(L["search.group"], plural, count)
end

-- A source that fails costs its kind only: one notice, the rest keeps searching.
ns.SearchLogic.OnSourceError = function(kind)
  ns.Notify(string.format(L["search.sourceError"], kindLabel(kind)), "warning")
end

-- Icon of a hit whose kind has one: the page's menu icon, the class circle.
local function kindIcon(item)
  if item.kind == "page" then
    local page = ns.Router:get(item.path)
    return page and page.icon and ns.ResolveIcon(page.icon) or nil
  elseif item.kind == "class" then
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[tostring(item.path):match("^classes/(%u+)$")]
    if coords then
      local function paint(tex)
        tex:SetTexture(K.CLASS_ICON_SHEET)
        tex:SetTexCoord(unpack(coords))
      end
      return nil, paint
    end
  end
  return nil
end

-- Quality color of an item hit ("rrggbb"), nil for other kinds and while the client has no quality.
local function itemHex(item)
  local data = item.kind == "item" and type(item.data) == "table" and item.data or nil
  if data and type(data.id) == "number" then
    return ns.ItemInfo.qualityHex(ns.ItemInfo.quality(data.id))
  end
end

-- Identity of a row across two renders of the same query (the hit tables are new each time).
local function rowKey(item)
  return table.concat({ tostring(item.kind), tostring(item.path or item.name or item.hidden) }, "|")
end

local function recentList()
  return ns.SearchLogic.CleanRecent(ns.db and ns.db.searchRecent)
end

-- Two-way mirror: text typed (or cleared) in one box lands in the other, the
-- equal-text check ends the echo, then the results follow after a short pause.
local function mirror(from)
  if not pageVisible() then
    return
  end
  local header, page = headerEdit(), state.pageEdit
  local to = from == page and header or page
  if to and to:GetText() ~= from:GetText() then
    to:SetText(from:GetText())
  end
  ns.Debounce("search-live", LIVE_DELAY, state.live)
end

-- Hooks the header box once: its text changes mirror into the page, and a
-- programmatic SetFocus (Ctrl+F, /fg search, key binding) goes to the page's
-- input while the page is open. Mouse clicks do not pass through SetFocus, so
-- the header box stays usable.
local function hookHeader()
  local edit = headerEdit()
  if not edit or edit.fgSearchHooked then
    return
  end
  edit.fgSearchHooked = true
  edit:HookScript("OnTextChanged", function(self)
    mirror(self)
  end)
  local setFocus = edit.SetFocus
  edit.SetFocus = function(self, ...)
    if pageVisible() then
      state.pageEdit:SetFocus()
      return
    end
    return setFocus(self, ...)
  end
end

local function build(container)
  local view = ns.NewPageView(container)
  local S, SP = ns.SearchLogic, ns.SearchProfessions

  -- The box is anchored on both sides of its holder, so it follows the page width.
  local holder = CreateFrame("Frame", nil, view.content)
  local box = W.EditBox(holder, { placeholder = "search.placeholder", clear = true, height = 30 })
  local edit = box.edit
  box:SetPoint("TOPLEFT", holder, "TOPLEFT")
  box:SetPoint("TOPRIGHT", holder, "TOPRIGHT")
  function holder:fgGridLayout()
    holder:SetHeight(box:GetHeight())
    return box:GetHeight()
  end
  K.Anchor("FG.Search.Input", box)
  view.stack:Add(holder, { gap = 8 })

  -- rows: what the list shows; selected: the row of the keyboard cursor (nil until an arrow key);
  -- limits: kinds the user expanded with "show more".
  local st = { container = container, pageEdit = edit, query = "", rows = {}, total = 0, limits = {} }

  local render, open, list

  local summary = ns.AddParagraph(view, nil, { role = "text", color = "text" })
  list = K.NewList(view.content, {
    rowHeight = ROW_HEIGHT,
    bind = function(item)
      if item.header then
        return { title = Theme.hexText("accent2", item.name), inert = true }
      end
      local cursor = item == st.selected
      if item.more then
        return {
          title = string.format(L["search.showMore"], item.hidden),
          sub = L["search.showMore.sub"],
          selected = cursor,
          cursor = cursor,
        }
      elseif item.clear then
        return { title = item.name, sub = item.sub, selected = cursor, cursor = cursor }
      elseif item.recent then
        return { title = item.name, sub = L["search.recent.sub"], selected = cursor, cursor = cursor }
      elseif item.package then
        return { title = item.name, sub = item.sub, right = item.right, selected = cursor, cursor = cursor }
      end
      local spec = {
        title = item.name,
        titleHex = itemHex(item),
        sub = item.sub,
        right = kindLabel(item.kind),
        marks = S.Spans(item.name, st.query),
        selected = cursor,
        cursor = cursor,
      }
      spec.icon, spec.iconPaint = kindIcon(item)
      local row = SP.Row(item)
      if row then
        spec.icon, spec.actions, spec.tooltipSpec = row.icon or spec.icon, row.actions, row.tooltipSpec
      end
      return spec
    end,
    onClick = function(item)
      if item.header then
        return
      end
      -- A click moves the cursor too, so the mouse and the arrow keys share one selection.
      st.selected = item
      list:SetData(st.rows)
      open(item)
    end,
  })
  K.Anchor("FG.Search.Results", list)
  view.stack:Add(list, { height = K.scaledHeight(ROW_HEIGHT) * 12 })
  local empty = W.EmptyState(list, { text = "search.empty.text", icon = "search" }):Fill()
  empty:Hide()
  local more = ns.AddParagraph(view, nil, { role = "ui", color = "textMuted" })

  -- Shown only without a hit: the corrected query (a click takes it over) and the website link.
  local suggestion
  local suggest = W.Button(view.content, {
    text = "",
    variant = "ghost",
    width = 320,
    height = 26,
    onClick = function()
      if suggestion then
        edit:SetText(suggestion)
      end
    end,
  })
  suggest:Hide()
  view.stack:Add(suggest, { height = 26, width = 320, gap = 4 })
  local webQuery
  local web = W.Action(view.content, {
    label = "act.search",
    icon = "search",
    tooltip = "search.web",
    width = 260,
    height = 26,
    onClick = function()
      if webQuery then
        local lang = ns.GetActiveLocale() == "deDE" and "de" or "en"
        ns.Dialogs.Copy("search.web.title", S.WebUrl(ns.Website, lang, webQuery), "search.web.hint")
      end
    end,
  })
  web:Hide()
  view.stack:Add(web, { height = 26, width = 260, gap = 4 })

  -- Without a query: the saved searches, a row to clear them.
  local function recentRows()
    local saved = recentList()
    if #saved == 0 then
      return {}
    end
    local rows = { { header = true, name = L["search.recent"] } }
    for _, q in ipairs(saved) do
      rows[#rows + 1] = { recent = true, name = q }
    end
    rows[#rows + 1] = { clear = true, name = L["search.recent.clear"], sub = L["search.recent.clearSub"] }
    return rows
  end

  -- Only searches that found something are worth coming back to.
  local function remember(q)
    if q ~= "" and q == st.query and st.total > 0 then
      ns.Store.set("searchRecent", S.PushRecent(recentList(), q))
    end
  end

  local rendering = false
  function render(q, keep)
    local previous = keep and st.selected and rowKey(st.selected) or nil
    suggestion, webQuery = nil, nil
    rendering = true
    local rows, emptyText, emptyHint
    local total, notes = 0, {}
    if q == "" then
      summary:SetText(L["search.hint"])
      rows = recentRows()
      if #rows == 0 then
        emptyText, emptyHint = "search.empty.text", "search.empty.hint"
      end
    else
      -- The item, recipe and trainer kinds fill in once the data add-ons are cut (a few frames).
      SP.Prepare()
      local result = S.Search(q, { limit = S.GROUP_LIMIT, limits = st.limits })
      total = result.total
      summary:SetText(total == 0 and L["search.none"] or string.format(L["search.total"], total, q))
      rows = S.ListRows(result, L["search.best"], L["search.all"], groupLabel)
      rows[#rows + 1] = SP.PackageRow()
      if total == 0 then
        webQuery = q
        suggestion = result.suggestion
        emptyText, emptyHint = "search.none", "search.none.hint"
      end
      local failed = {}
      for _, kind in ipairs(S.FailedKinds()) do
        failed[#failed + 1] = kindLabel(kind)
      end
      if #failed > 0 then
        notes[#notes + 1] = string.format(L["search.sourceFailed"], table.concat(failed, ", "))
      end
    end
    notes[#notes + 1] = SP.StatusText()
    st.rows, st.total, st.selected = rows, total, nil
    if previous then
      for _, row in ipairs(rows) do
        if rowKey(row) == previous then
          st.selected = row
          break
        end
      end
    end
    if emptyText then
      empty:SetTexts(emptyText, emptyHint)
    end
    empty:SetShown(emptyText ~= nil)
    list:SetData(rows)
    more:SetText(table.concat(notes, " "))
    rendering = false
    if suggestion then
      suggest.label:SetText(string.format(L["search.didYouMean"], suggestion))
    end
    suggest:SetShown(suggestion ~= nil)
    web:SetShown(webQuery ~= nil)
    view:Layout()
  end

  -- Opens a row: a hit goes to its page, the helper rows act in place.
  function open(item)
    if item.more then
      st.limits[item.kind] = math.huge
      render(st.query, true)
    elseif item.clear then
      ns.Store.set("searchRecent", {})
      render(st.query)
    elseif item.recent then
      ns.Router:navigate("search/" .. item.name)
    elseif item.package then
      SP.EnableMissing()
    else
      remember(st.query)
      if not SP.Open(item) and item.path then
        ns.Router:navigate(item.path)
      end
    end
  end

  -- Cursor: the next row that is no heading, in the direction of the arrow key; it stops at the ends.
  local function move(step)
    local rows = st.rows
    local at = step > 0 and 0 or #rows + 1
    for i, row in ipairs(rows) do
      if row == st.selected then
        at = i
      end
    end
    repeat
      at = at + step
    until at < 1 or at > #rows or not rows[at].header
    if at < 1 or at > #rows then
      return
    end
    st.selected = rows[at]
    list:SetData(rows)
    list:Reveal(at)
    -- Moving up to the first row of a group shows its heading as well.
    if rows[at - 1] and rows[at - 1].header then
      list:Reveal(at - 1)
    end
  end

  -- Live update: renders without a route change (a route change hides the
  -- container, which would drop the typing focus) and keeps the current route
  -- in step, so Enter and the history see the typed query.
  function st.live()
    if state ~= st or not pageVisible() then
      return
    end
    local q = normalize(edit:GetText())
    if q ~= st.query then
      st.query = q
      st.limits = {}
      ns.Router.current = q == "" and "search" or ("search/" .. q)
      render(q)
    end
  end
  state = st
  -- The data add-ons are cut (or changed): the same query again with the new kinds.
  ns.On("FG_SEARCH_DATA", function()
    if state == st and pageVisible() and not rendering then
      render(st.query, true)
    end
  end)

  edit:HookScript("OnTextChanged", function(changed)
    if state == st then
      mirror(changed)
    end
  end)
  edit:SetScript("OnArrowPressed", function(_, key)
    if key == "UP" then
      move(-1)
    elseif key == "DOWN" then
      move(1)
    end
  end)
  -- Enter opens the row of the cursor, without one it commits the typed query.
  edit:SetScript("OnEnterPressed", function()
    local q = normalize(edit:GetText())
    local item = st.selected
    if item and q == st.query then
      open(item)
      if not (item.more or item.clear) then
        edit:ClearFocus()
      end
      return
    end
    if q ~= "" then
      remember(q)
      ns.Router:navigate("search/" .. q)
    end
    edit:ClearFocus()
  end)
  -- Esc clears a filled field first and leaves an empty one.
  edit:SetScript("OnEscapePressed", function()
    if edit:GetText() ~= "" then
      edit:SetText("")
    else
      edit:ClearFocus()
    end
  end)

  function view:Show(params)
    state = st
    hookHeader()
    local q = normalize(params and table.concat(params, "/") or "")
    if q ~= st.query then
      st.limits = {}
    end
    st.query = q
    for _, e in ipairs({ edit, headerEdit() or edit }) do
      if normalize(e:GetText()) ~= q then
        e:SetText(q)
      end
    end
    render(q)
    -- Opened through the Search entry (no query yet): ready to type.
    if q == "" and previousPage ~= "search" then
      C_Timer.After(0, function()
        if state == st and pageVisible() then
          edit:SetFocus()
        end
      end)
    end
  end
  return view
end

ns.On("FG_ROUTE_CHANGED", function(_, _, pageId)
  previousPage = pageId
end)

ns.RegisterPage({
  id = "search",
  order = 15,
  group = "main",
  title = "page.search",
  icon = ns.ICONS.search,
  aliases = { "suche", "search" },
  crumbLabel = function(param)
    return '"' .. param .. '"'
  end,
  build = build,
})
