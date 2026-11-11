-- The settings in the global search: what a hit does (jump to the page, the tab, the card or the single
-- setting), the section "Settings" of the page of results, the tooltip of a hit and the command
-- /fg einstellungen <word>. The index and the ranking are in Modules/SettingsSearchLogic.lua, the suggestion list
-- under the search field in Modules/SettingsSuggest.lua.
local _, ns = ...

local SS = {}
ns.SettingsSearch = SS

ns.AddLocale("enUS", {
  ["settings.search.page"] = "Menu page",
  ["settings.search.kind.page"] = "Menu page",
  ["settings.search.kind.feature"] = "Tab",
  ["settings.search.kind.card"] = "Card",
  ["settings.search.kind.setting"] = "Setting",
  ["settings.search.pending"] = "Appears after switching on %s",
  ["settings.search.pendingShort"] = "add-on off",
  ["settings.search.pendingTip"] = "This setting appears after switching on %s. A click opens the switch.",
  ["settings.search.groupNav"] = "Menu and tabs",
  ["settings.search.groupSettings"] = "Settings",
  ["settings.search.all"] = "Search",
  ["settings.search.allMore"] = "Search (+%d more)",
  ["settings.search.allTip"] = 'Opens the search page with every hit for "%s".',
  ["settings.search.none"] = "No matching setting.",
  ["settings.search.list"] = "Suggestions",
  ["settings.search.place"] = "Place: %s",
  ["settings.search.opens"] = "Click to open it.",
  ["settings.search.command"] = 'No tab or card "%s". Searching the settings.',
  ["search.kind.setting"] = "Setting",
  ["search.kind.card"] = "Card",
  ["search.kind.feature"] = "Tab",
  ["search.group.setting"] = "Settings",
})
ns.AddLocale("deDE", {
  ["settings.search.page"] = "Menüpunkt",
  ["settings.search.kind.page"] = "Menüpunkt",
  ["settings.search.kind.feature"] = "Reiter",
  ["settings.search.kind.card"] = "Karte",
  ["settings.search.kind.setting"] = "Einstellung",
  ["settings.search.pending"] = "Erscheint nach dem Einschalten von %s",
  ["settings.search.pendingShort"] = "Addon aus",
  ["settings.search.pendingTip"] = "Diese Einstellung erscheint nach dem Einschalten von %s. Ein Klick öffnet den Schalter.",
  ["settings.search.groupNav"] = "Menü und Reiter",
  ["settings.search.groupSettings"] = "Einstellungen",
  ["settings.search.all"] = "Suchen",
  ["settings.search.allMore"] = "Suchen (+%d weitere)",
  ["settings.search.allTip"] = 'Öffnet die Suche mit allen Treffern für "%s".',
  ["settings.search.none"] = "Keine passende Einstellung.",
  ["settings.search.list"] = "Vorschläge",
  ["settings.search.place"] = "Ort: %s",
  ["settings.search.opens"] = "Ein Klick öffnet sie.",
  ["settings.search.command"] = 'Kein Reiter und keine Karte "%s". Die Einstellungen werden durchsucht.',
  ["search.kind.setting"] = "Einstellung",
  ["search.kind.card"] = "Karte",
  ["search.kind.feature"] = "Reiter",
  ["search.group.setting"] = "Einstellungen",
})

-- The label of the kind of a hit ("Setting", "Tab", "Card", "Menu page").
function SS.KindLabel(hit)
  return ns.L["settings.search.kind." .. hit.kind]
end

-- The line before the name of a setting: its tab ("Gathering: Ore veins").
function SS.Label(hit)
  if hit.kind == "setting" or hit.kind == "card" then
    return hit.featureName .. ": " .. hit.name
  end
  return hit.name
end

-- Opens the place of a hit: a menu page, a tab, a card or a single setting. A setting of a sub-add-on that is
-- off opens the switch of the add-on instead.
function SS.Go(hit)
  if not hit then
    return false
  end
  if hit.kind == "page" then
    ns.Main.Show(hit.page)
    return true
  end
  local card, control = hit.card, hit.control
  if hit.missing then
    card, control = ns.AddonSettings.CardId(hit.addon), nil
  elseif hit.kind == "feature" then
    card, control = nil, nil
  elseif hit.kind == "card" then
    control = nil
  end
  -- The page opens first: showing it selects its saved tab and would wipe the mark of a jump made before.
  ns.Main.Show("settings")
  ns.SettingsPage.Select(hit.feature, card, control)
  return true
end

-- The tooltip of a hit: the full name, the place, the explanation and what a click does.
function SS.Tooltip(hit)
  local lines = {}
  if hit.hint and hit.hint ~= "" then
    lines[#lines + 1] = { text = hit.hint, color = "textSecondary" }
  end
  if hit.pending then
    local title = ns.L["subaddon." .. hit.addon .. ".title"]
    lines[#lines + 1] = { text = string.format(ns.L["settings.search.pendingTip"], title), color = "warning" }
  end
  return {
    title = SS.Label(hit),
    text = hit.sub and string.format(ns.L["settings.search.place"], hit.sub) or nil,
    lines = lines,
    hint = ns.L["settings.search.opens"],
    anchor = "ANCHOR_LEFT",
  }
end

-- Rows of the section "Settings" for the page of results: a header with the count, a sub header per tab and
-- the hits (kind of a row stays "setting" for the page, `settingHit` marks them). Returns rows, count.
function SS.Rows(query)
  local result = ns.SettingsSearchLogic.Results(query)
  if result.total == 0 then
    return {}, 0
  end
  local L = ns.L
  local rows = {
    {
      header = true,
      settings = true,
      name = string.format(L["search.group"], L["search.group.setting"], result.total),
    },
  }
  for _, group in ipairs(result.groups) do
    rows[#rows + 1] = { header = true, sub = true, settings = true, name = group.name .. " (" .. group.group .. ")" }
    for _, hit in ipairs(group.hits) do
      hit.settingHit = true
      hit.path = hit.uid
      -- The line under the name: the place, and the note for a setting that is not there yet.
      hit.subLine = hit.pending and (hit.sub .. ", " .. hit.pending) or hit.sub
      hit.right = SS.KindLabel(hit)
      rows[#rows + 1] = hit
    end
  end
  return rows, result.total
end

-- /fg einstellungen <word>: a tab or card named by the word opens right away, anything else opens the
-- search with the word, where the settings have a section of their own. Without a word the page opens.
function SS.Command(word)
  word = (word or ""):match("^%s*(.-)%s*$")
  if word == "" then
    ns.Main.Show("settings")
    return "page"
  end
  local found = ns.SettingsSearchLogic.Resolve(word)
  if found then
    ns.Main.Show("settings")
    ns.SettingsPage.Select(found.feature, found.card)
    return "jump", found
  end
  ns.Main.Show("search/" .. (word:gsub("/", " ")))
  return "search"
end

-- A changed language or sub-add-on changes names and the cards that exist.
ns.On("FG_LOCALE_CHANGED", function()
  ns.SettingsSearchLogic.Reset()
end)
ns.On("FG_SUBADDON_CHANGED", function()
  ns.SettingsSearchLogic.Reset()
end)
