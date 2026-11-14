-- The window "My catches": the fish with count, last catch and places, the places with the fish caught there,
-- figures for the selected fish or place as tiles and bars (JournalDetail.lua), and what the selected fish is used
-- for. It is drawn with the shell and the look of the other windows of Forever Guides (UI/WindowShell.lua,
-- Modules/WindowStyle.lua).
--
-- Mouse: every fish shows the item tooltip of the game on hover, a click on a fish or place line opens it, Shift+click
-- on a fish puts its link into the chat edit box when one is open.
--
-- Keyboard: Up, Down, Page Up, Page Down, Home and End move the selection, Enter opens the fish of the selected
-- place, Backspace leaves that place, V changes between fish and places, S changes the sort, C changes between
-- all characters and this one, / or Tab goes to the search, Tab or Enter in the search goes back to the list,
-- Esc clears the search first and closes the window then. The same keys work in the search field (arrows).
-- Nothing is told by colour alone, the selected row has a bar and an outline.
local _, fish = ...
if not fish.FG then
  return
end

local FG = fish.FG
local W, L, Theme, U, WS = FG.W, FG.L, FG.Theme, FG.U, FG.WindowStyle
local Store, Logic, Uses, Detail = fish.CatchStore, fish.JournalLogic, fish.Uses, fish.JournalDetail

local V = {}
fish.JournalView = V

WS.PREFIX.fishjournal = WS.PREFIX.fishjournal or "fishJournalWindow"

local HEAD_H, ROW_H = 22, 28
local ICON_W, EXTRA_W, COUNT_W, GAP, BUTTON_W = 22, 72, 40, 6, 176
local BAR_H, BAR_BOTTOM = 3, 3
local MIN_W, MIN_H, DEFAULT_W, DEFAULT_H = 560, 340, 700, 480
local DETAIL_W = 260
local MAX_FISH, MAX_USES, TOP_PLACES = 12, 8, 3

local function contains(list, value)
  for _, entry in ipairs(list) do
    if entry == value then
      return true
    end
  end
  return false
end

FG.AddLocale("enUS", {
  ["fishj.title"] = "My catches",
  ["fishj.close"] = "Close the catch journal",
  ["fishj.grip"] = "Drag to resize",
  ["fishj.search"] = "Search fish or place",
  ["fishj.mode.fish"] = "Fish",
  ["fishj.mode.places"] = "Places",
  ["fishj.view"] = "View: %s",
  ["fishj.sortBy"] = "Sort: %s",
  ["fishj.show"] = "Show: %s",
  ["fishj.sort.name"] = "Name",
  ["fishj.sort.count"] = "Count",
  ["fishj.sort.last"] = "Last caught",
  ["fishj.sort.places"] = "Places",
  ["fishj.sort.kinds"] = "Kinds of fish",
  ["fishj.scope.account"] = "All characters",
  ["fishj.scope.char"] = "This character",
  ["fishj.summary"] = "%d catches, %d kinds of fish, %d places",
  ["fishj.inPlace"] = "In %s",
  ["fishj.empty"] = "Nothing caught yet. Every fish you catch while fishing is listed here from now on.",
  ["fishj.noMatch"] = "Nothing matches your search.",
  ["fishj.off"] = "Recording is switched off in the settings of the fishing helper. Nothing new is added.",
  ["fishj.newer"] = "The saved catches come from a newer version of the add-on. They are not touched and not shown.",
  ["fishj.hint"] = "Arrow keys select. Enter opens a place. V view, S sort, C characters, / search, Esc close.",
  ["fishj.row.fish"] = "%s, %d caught, last %s, %d places",
  ["fishj.row.place"] = "%s, %d caught, %d kinds of fish",
  ["fishj.legend.fish"] = "Bar and percent: share of all catches. A full bar is 100 %.",
  ["fishj.legend.fishAt"] = "Bar and percent: share of the catches at this place. A full bar is 100 %.",
  ["fishj.legend.places"] = "Bar and percent: catch rate, the casts with a catch. A full bar is 100 %.",
  ["fishj.bar.fish"] = "Bar: %s of all catches (%d of %d). A full bar is 100 %%.",
  ["fishj.bar.fishAt"] = "Bar: %s of the catches at %s (%d of %d). A full bar is 100 %%.",
  ["fishj.bar.place"] = "Bar: catch rate %s, %d of %d casts had a catch. A full bar is 100 %%.",
  ["fishj.bar.placeNone"] = "Bar: no catch rate yet, no casts are recorded for this place.",
  ["fishj.never"] = "never",
  ["fishj.unknown"] = "unknown",
  ["fishj.d.places"] = "Where",
  ["fishj.t.count"] = "Caught",
  ["fishj.t.places"] = "Places",
  ["fishj.t.share"] = "Share",
  ["fishj.t.shareLong"] = "Share of all catches",
  ["fishj.t.first"] = "First",
  ["fishj.t.last"] = "Last",
  ["fishj.t.best"] = "Best session",
  ["fishj.t.kind"] = "Kind",
  ["fishj.t.kind.fish"] = "Fish",
  ["fishj.t.kind.other"] = "Other catch",
  ["fishj.t.casts"] = "Casts",
  ["fishj.t.catches"] = "Catches",
  ["fishj.t.rate"] = "Catch rate",
  ["fishj.t.rateLong"] = "Casts with a catch",
  ["fishj.t.rateValue"] = "%s (%d of %d)",
  ["fishj.t.kinds"] = "Kinds of fish",
  ["fishj.d.topPlaces"] = "Best places",
  ["fishj.d.openTitle"] = "Only the fish of this place",
  ["fishj.d.placeLine"] = "%s: %d (%s of this fish, %s of the catches there), best session %s, last %s",
  ["fishj.tip.fish"] = "Click: show this fish. Shift+click: link in chat.",
  ["fishj.tip.place"] = "Click: show this place.",
  ["fishj.tip.link"] = "Shift+click: link in chat.",
  ["fishj.d.place"] = "%s: %d (%s), best session %s, last %s",
  ["fishj.d.more"] = "and %d more",
  ["fishj.d.unknownUse"] = "Unknown recipe",
  ["fishj.d.uses"] = "Used for",
  ["fishj.d.use"] = "%s: %s%s",
  ["fishj.d.useFrom"] = " (from skill %d)",
  ["fishj.d.useAmount"] = ", %d needed",
  ["fishj.d.useRemoved"] = " (not in Forever)",
  ["fishj.d.noUses"] = "No recipe uses this fish.",
  ["fishj.d.fish"] = "Fish caught here",
  ["fishj.d.fishLine"] = "%s: %d (%s), best session %s, last %s",
  ["fishj.d.open"] = "Press Enter to list only the fish of this place.",
  ["fishj.d.pick"] = "Select a row to see the figures.",
  ["fishj.prof.cooking"] = "Cooking",
  ["fishj.prof.first-aid"] = "First Aid",
  ["fishj.prof.alchemy"] = "Alchemy",
  ["fishj.prof.fishing"] = "Fishing",
  ["fishj.prof.blacksmithing"] = "Blacksmithing",
  ["fishj.prof.leatherworking"] = "Leatherworking",
  ["fishj.prof.tailoring"] = "Tailoring",
  ["fishj.prof.engineering"] = "Engineering",
  ["fishj.prof.enchanting"] = "Enchanting",
  ["fishj.prof.other"] = "Profession",
  ["fishj.dateFormat"] = "%Y-%m-%d",
  ["fishj.open"] = "Open the catch journal",
  ["fishj.set.heading"] = "Catch journal",
  ["fishj.set.hint"] = "Command: /fg fishing journal",
})

FG.AddLocale("deDE", {
  ["fishj.title"] = "Meine Fänge",
  ["fishj.close"] = "Fangjournal schließen",
  ["fishj.grip"] = "Zum Ändern der Größe ziehen",
  ["fishj.search"] = "Fisch oder Fundort suchen",
  ["fishj.mode.fish"] = "Fische",
  ["fishj.mode.places"] = "Fundorte",
  ["fishj.view"] = "Ansicht: %s",
  ["fishj.sortBy"] = "Sortierung: %s",
  ["fishj.show"] = "Zeigt: %s",
  ["fishj.sort.name"] = "Name",
  ["fishj.sort.count"] = "Anzahl",
  ["fishj.sort.last"] = "Zuletzt gefangen",
  ["fishj.sort.places"] = "Fundorte",
  ["fishj.sort.kinds"] = "Fischarten",
  ["fishj.scope.account"] = "Alle Charaktere",
  ["fishj.scope.char"] = "Dieser Charakter",
  ["fishj.summary"] = "%d Fänge, %d Fischarten, %d Fundorte",
  ["fishj.inPlace"] = "In %s",
  ["fishj.empty"] = "Noch nichts gefangen. Jeder Fisch, den du beim Angeln fängst, steht ab jetzt hier.",
  ["fishj.noMatch"] = "Zu deiner Suche passt nichts.",
  ["fishj.off"] = "Die Aufzeichnung ist in den Einstellungen der Angelhilfe ausgeschaltet. Es kommt nichts Neues dazu.",
  ["fishj.newer"] = "Die gespeicherten Fänge stammen aus einer neueren Version des Addons. Sie bleiben unberührt und werden nicht angezeigt.",
  ["fishj.hint"] = "Pfeiltasten wählen aus. Eingabe öffnet einen Fundort. V Ansicht, S Sortierung, C Charaktere, / Suche, Esc schließen.",
  ["fishj.row.fish"] = "%s, %d gefangen, zuletzt %s, %d Fundorte",
  ["fishj.row.place"] = "%s, %d gefangen, %d Fischarten",
  ["fishj.legend.fish"] = "Balken und Prozent: Anteil an allen Fängen. Ein voller Balken sind 100 %.",
  ["fishj.legend.fishAt"] = "Balken und Prozent: Anteil an den Fängen an diesem Fundort. Ein voller Balken sind 100 %.",
  ["fishj.legend.places"] = "Balken und Prozent: Fangquote, die Würfe mit einem Fang. Ein voller Balken sind 100 %.",
  ["fishj.bar.fish"] = "Balken: %s aller Fänge (%d von %d). Ein voller Balken sind 100 %%.",
  ["fishj.bar.fishAt"] = "Balken: %s der Fänge in %s (%d von %d). Ein voller Balken sind 100 %%.",
  ["fishj.bar.place"] = "Balken: Fangquote %s, bei %d von %d Würfen gab es einen Fang. Ein voller Balken sind 100 %%.",
  ["fishj.bar.placeNone"] = "Balken: noch keine Fangquote, für diesen Fundort sind keine Würfe gespeichert.",
  ["fishj.never"] = "nie",
  ["fishj.unknown"] = "unbekannt",
  ["fishj.d.places"] = "Wo",
  ["fishj.t.count"] = "Gefangen",
  ["fishj.t.places"] = "Fundorte",
  ["fishj.t.share"] = "Anteil",
  ["fishj.t.shareLong"] = "Anteil an allen Fängen",
  ["fishj.t.first"] = "Zuerst",
  ["fishj.t.last"] = "Zuletzt",
  ["fishj.t.best"] = "Beste Sitzung",
  ["fishj.t.kind"] = "Art",
  ["fishj.t.kind.fish"] = "Fisch",
  ["fishj.t.kind.other"] = "Anderer Fang",
  ["fishj.t.casts"] = "Würfe",
  ["fishj.t.catches"] = "Fänge",
  ["fishj.t.rate"] = "Fangquote",
  ["fishj.t.rateLong"] = "Würfe mit Fang",
  ["fishj.t.rateValue"] = "%s (%d von %d)",
  ["fishj.t.kinds"] = "Fischarten",
  ["fishj.d.topPlaces"] = "Beste Fundorte",
  ["fishj.d.openTitle"] = "Nur die Fische dieses Fundorts",
  ["fishj.d.placeLine"] = "%s: %d (%s dieses Fischs, %s der Fänge dort), beste Sitzung %s, zuletzt %s",
  ["fishj.tip.fish"] = "Klick: diesen Fisch zeigen. Umschalt-Klick: Link in den Chat.",
  ["fishj.tip.place"] = "Klick: diesen Fundort zeigen.",
  ["fishj.tip.link"] = "Umschalt-Klick: Link in den Chat.",
  ["fishj.d.place"] = "%s: %d (%s), beste Sitzung %s, zuletzt %s",
  ["fishj.d.more"] = "und %d weitere",
  ["fishj.d.unknownUse"] = "Unbekanntes Rezept",
  ["fishj.d.uses"] = "Verwendung",
  ["fishj.d.use"] = "%s: %s%s",
  ["fishj.d.useFrom"] = " (ab Fertigkeit %d)",
  ["fishj.d.useAmount"] = ", %d nötig",
  ["fishj.d.useRemoved"] = " (nicht in Forever)",
  ["fishj.d.noUses"] = "Kein Rezept braucht diesen Fisch.",
  ["fishj.d.fish"] = "Hier gefangene Fische",
  ["fishj.d.fishLine"] = "%s: %d (%s), beste Sitzung %s, zuletzt %s",
  ["fishj.d.open"] = "Mit Eingabe siehst du nur die Fische dieses Fundorts.",
  ["fishj.d.pick"] = "Wähle eine Zeile, um die Zahlen zu sehen.",
  ["fishj.prof.cooking"] = "Kochen",
  ["fishj.prof.first-aid"] = "Erste Hilfe",
  ["fishj.prof.alchemy"] = "Alchemie",
  ["fishj.prof.fishing"] = "Angeln",
  ["fishj.prof.blacksmithing"] = "Schmiedekunst",
  ["fishj.prof.leatherworking"] = "Lederverarbeitung",
  ["fishj.prof.tailoring"] = "Schneiderei",
  ["fishj.prof.engineering"] = "Ingenieurskunst",
  ["fishj.prof.enchanting"] = "Verzauberkunst",
  ["fishj.prof.other"] = "Beruf",
  ["fishj.dateFormat"] = "%d.%m.%Y",
  ["fishj.open"] = "Fangjournal öffnen",
  ["fishj.set.heading"] = "Fangjournal",
  ["fishj.set.hint"] = "Befehl: /fg angeln journal",
})

-- State -------------------------------------------------------------------------------------------------------------

V.state = { mode = "fish", scope = "account", sort = "name", query = "", place = nil, index = 1 }
local state = V.state
local frame

local function saved()
  local db = fish.Controller and fish.Controller.Saved and fish.Controller.Saved() or nil
  if type(db) ~= "table" then
    return {}
  end
  if type(db.window) ~= "table" then
    db.window = {}
  end
  return db.window
end

local function names()
  return {
    item = fish.Game.FishName,
  }
end

-- The ledger the window reads: nil while the saved data is from a later version.
function V.Ledger()
  local journal = fish.Recorder and fish.Recorder.Journal()
  if not journal then
    return nil
  end
  return Store.Scope(journal, state.scope == "char" and fish.Recorder.CharKey() or nil)
end

-- Text helpers ------------------------------------------------------------------------------------------------------

function V.Date(time)
  if type(time) ~= "number" or time <= 0 then
    return L["fishj.never"]
  end
  local ok, text = pcall(date, L["fishj.dateFormat"], time)
  return ok and text or L["fishj.unknown"]
end

local function percent(value)
  if value == nil then
    return "-"
  end
  local text = string.format("%.1f", value)
  if FG.GetActiveLocale() == "deDE" then
    text = text:gsub("%.", ",")
  end
  return text .. " %"
end
V.Percent = percent

local function number(value)
  return value and tostring(value) or "-"
end

function V.SortLabel()
  return L["fishj.sort." .. state.sort]
end

-- Rows ---------------------------------------------------------------------------------------------------------------

-- The rows of the list in the current view, search and sort.
function V.Rows()
  local ledger = V.Ledger()
  if not ledger then
    return {}
  end
  if state.mode == "places" then
    return Logic.Places(ledger, { query = state.query, sort = state.sort, names = names() })
  end
  return Logic.Fish(ledger, { query = state.query, sort = state.sort, place = state.place, names = names() })
end

local function sorts()
  return state.mode == "places" and Logic.PLACE_SORTS or Logic.FISH_SORTS
end

local function rowKey(row)
  return state.mode == "places" and row.key or row.id
end

-- The row text a screen reader or a plain read gets: all figures in words, no colour needed.
function V.RowText(row)
  if state.mode == "places" then
    return string.format(L["fishj.row.place"], row.name, row.n, row.kinds)
  end
  return string.format(L["fishj.row.fish"], row.name, row.n, V.Date(row.last), row.places)
end

-- What the bar of a row stands for, with the exact figures: the tooltip of the row and the plain read.
function V.BarText(row)
  if state.mode == "places" then
    if row.rate == nil then
      return L["fishj.bar.placeNone"]
    end
    return string.format(L["fishj.bar.place"], percent(row.rate), row.hits or 0, row.casts or 0)
  end
  if row.placeName then
    return string.format(L["fishj.bar.fishAt"], percent(row.share), row.placeName, row.n, row.whole or 0)
  end
  return string.format(L["fishj.bar.fish"], percent(row.share), row.n, row.whole or 0)
end

-- The text over the list that says what the bar and the percent column of the current view stand for.
function V.LegendText()
  if state.mode == "places" then
    return L["fishj.legend.places"]
  end
  return L[state.place and "fishj.legend.fishAt" or "fishj.legend.fish"]
end

-- Detail ----------------------------------------------------------------------------------------------------------------

local function recipeOf(slug)
  local access = FG.RecipeAccess
  if not access then
    return nil
  end
  local ok, _, list = pcall(access.Get, slug)
  return ok and list or nil
end

-- The use rows of a fish: { text, result, resultName } per recipe. Empty when no recipe uses the fish.
local function useRows(id)
  local data = fish.UsesData
  local out = {}
  if not data or not Uses.Has(data, id) then
    return out
  end
  -- The recipe data is loaded only for a fish that has a use.
  local rows = Uses.Rows(data, id, recipeOf, FG.GetActiveLocale())
  for index, row in ipairs(rows) do
    if index > MAX_USES then
      out[#out + 1] = { text = string.format(L["fishj.d.more"], #rows - MAX_USES) }
      break
    end
    local profession = L["fishj.prof." .. (row.slug or "other")]
    local resultName = row.result and fish.Game.ItemName(row.result) or nil
    local name = row.name or fish.Game.RecipeName(row.spell) or resultName or L["fishj.d.unknownUse"]
    local extra = (row.skill and string.format(L["fishj.d.useFrom"], row.skill) or "")
      .. (row.qty > 1 and string.format(L["fishj.d.useAmount"], row.qty) or "")
      .. (row.removed and L["fishj.d.useRemoved"] or "")
    out[#out + 1] = {
      text = string.format(L["fishj.d.use"], profession, name, extra),
      result = row.result,
      resultName = resultName,
    }
  end
  return out
end

-- A figure tile. long is the full name of the figure (tooltip and plain text), share draws a bar.
local function tile(key, value, extra)
  extra = extra or {}
  local label = L["fishj.t." .. key]
  local long = extra.longKey and L["fishj.t." .. extra.longKey] or nil
  return {
    label = label,
    long = long,
    value = value,
    share = extra.share,
    span = extra.span,
    plain = (long or label) .. ": " .. value,
  }
end

local function rowsBlock(rows, make)
  local out = {}
  for _, row in ipairs(rows) do
    out[#out + 1] = make(row)
  end
  return { kind = "rows", rows = out }
end

-- The blocks of the detail of a fish: the title, tiles, its best places and its uses.
local function fishBlocks(ledger, key)
  local detail = Logic.FishPlaces(ledger, key, names())
  if not detail then
    return nil
  end
  local isFish = fish.Uses.FishSet(fish.UsesData)[key]
  local blocks = {
    { kind = "title", id = key, name = detail.name, quality = fish.Game.ItemQuality(key) },
    {
      kind = "tiles",
      tiles = {
        tile("count", string.format("%d", detail.n)),
        tile("places", string.format("%d", detail.kinds)),
        tile("share", percent(detail.share), { longKey = "shareLong", share = detail.share or 0, span = 2 }),
        tile("first", V.Date(detail.first)),
        tile("last", V.Date(detail.last)),
        tile("best", number(detail.best)),
        tile("kind", L[isFish and "fishj.t.kind.fish" or "fishj.t.kind.other"]),
      },
    },
  }
  if #detail.places > 0 then
    blocks[#blocks + 1] = { kind = "heading", text = L["fishj.d.topPlaces"] }
    blocks[#blocks + 1] = rowsBlock(Logic.Top(detail.places, TOP_PLACES), function(row)
      return {
        key = row.key,
        name = row.name,
        n = row.n,
        pct = percent(row.ofFish),
        share = row.ofFish,
        line = string.format(
          L["fishj.d.placeLine"],
          row.name,
          row.n,
          percent(row.ofFish),
          percent(row.share),
          number(row.best),
          V.Date(row.last)
        ),
      }
    end)
    if #detail.places > TOP_PLACES then
      blocks[#blocks + 1] = { kind = "text", text = string.format(L["fishj.d.more"], #detail.places - TOP_PLACES) }
    end
  end
  blocks[#blocks + 1] = { kind = "heading", text = L["fishj.d.uses"] }
  local uses = useRows(key)
  if #uses == 0 then
    blocks[#blocks + 1] = { kind = "text", text = L["fishj.d.noUses"] }
  else
    blocks[#blocks + 1] = { kind = "uses", rows = uses }
  end
  return blocks
end

-- The blocks of the detail of a place: the title with its hint, tiles and the fish caught there.
local function placeBlocks(ledger, key)
  local detail = Logic.PlaceFish(ledger, key, names())
  if not detail then
    return nil
  end
  local rate = string.format(L["fishj.t.rateValue"], percent(detail.rate), detail.hits, detail.casts)
  local blocks = {
    { kind = "title", name = detail.name, info = { title = L["fishj.d.openTitle"], text = L["fishj.d.open"] } },
    {
      kind = "tiles",
      tiles = {
        tile("casts", string.format("%d", detail.casts)),
        tile("catches", string.format("%d", detail.n)),
        tile("rate", rate, { longKey = "rateLong", share = detail.rate or 0, span = 2 }),
        tile("kinds", string.format("%d", detail.kinds)),
        tile("last", V.Date(detail.last)),
      },
    },
    { kind = "heading", text = L["fishj.d.fish"] },
  }
  local shown = {}
  for index, row in ipairs(detail.fish) do
    if index > MAX_FISH then
      break
    end
    shown[index] = row
  end
  blocks[#blocks + 1] = rowsBlock(shown, function(row)
    return {
      id = row.id,
      name = row.name,
      quality = fish.Game.ItemQuality(row.id),
      n = row.n,
      pct = percent(row.share),
      share = row.share,
      line = string.format(
        L["fishj.d.fishLine"],
        row.name,
        row.n,
        percent(row.share),
        number(row.best),
        V.Date(row.last)
      ),
    }
  end)
  if #detail.fish > MAX_FISH then
    blocks[#blocks + 1] = { kind = "text", text = string.format(L["fishj.d.more"], #detail.fish - MAX_FISH) }
  end
  return blocks
end

-- The blocks the detail pane draws for a row key in the current view, nil when there is nothing to show.
function V.DetailBlocks(key)
  local ledger = V.Ledger()
  if not ledger or key == nil then
    return nil
  end
  if state.mode == "places" then
    return placeBlocks(ledger, key)
  end
  return fishBlocks(ledger, key)
end

-- The detail as plain lines, every figure in words: what a plain read of the pane says, no bar and no colour needed.
function V.DetailText(key)
  local blocks = V.DetailBlocks(key)
  if not blocks then
    return L["fishj.d.pick"]
  end
  local lines = {}
  for _, block in ipairs(blocks) do
    if block.kind == "title" then
      lines[#lines + 1] = block.name
    elseif block.kind == "tiles" then
      for _, entry in ipairs(block.tiles) do
        lines[#lines + 1] = entry.plain
      end
    elseif block.kind == "heading" or block.kind == "text" then
      lines[#lines + 1] = block.text
    else
      for _, row in ipairs(block.rows) do
        lines[#lines + 1] = row.line or row.text
      end
    end
    if block.info then
      lines[#lines + 1] = block.info.text
    end
  end
  return table.concat(lines, "\n")
end

-- Window -------------------------------------------------------------------------------------------------------------------

local function select(index)
  local rows = frame.rows
  state.index = Logic.Move(index, #rows, nil, 1)
  frame.selected = rows[state.index] and rowKey(rows[state.index]) or nil
end

local function pageSize()
  return math.max(1, math.floor((frame.list:GetHeight() or ROW_H) / ROW_H) - 1)
end

local function scrollToSelection()
  local list, index = frame.list, state.index
  if index < 1 then
    return
  end
  local first = list.GetOffset and list:GetOffset() or 0
  local visible = math.max(1, math.floor((list:GetHeight() or ROW_H) / ROW_H))
  if index <= first then
    list:ScrollBy(index - first - 1)
  elseif index > first + visible then
    list:ScrollBy(index - first - visible)
  end
end

-- Draws the detail pane for the selected row: the blocks, or the line that asks for a selection.
local function renderDetail()
  local blocks = V.DetailBlocks(frame.selected)
  frame.detailText = V.DetailText(frame.selected)
  frame.empty:SetText(blocks and "" or frame.detailText)
  frame.panel:Render(blocks or {})
end

function V.Refresh()
  if not frame then
    return
  end
  local ledger = V.Ledger()
  local rows = V.Rows()
  frame.rows = rows
  -- Keep the selected row by its key when the list changed under it.
  local keep = frame.selected
  state.index = 1
  for index, row in ipairs(rows) do
    if keep ~= nil and rowKey(row) == keep then
      state.index = index
    end
  end
  frame.selected = rows[state.index] and rowKey(rows[state.index]) or nil
  frame.list:SetData(rows)
  scrollToSelection()
  local label = state.mode == "places" and L["fishj.mode.places"] or L["fishj.mode.fish"]
  W.SetText(frame.viewButton.label, nil, string.format(L["fishj.view"], label))
  W.SetText(frame.sortButton.label, nil, string.format(L["fishj.sortBy"], V.SortLabel()))
  W.SetText(frame.placesButton.label, nil, L["fishp.open"])
  W.SetText(frame.scopeButton.label, nil, string.format(L["fishj.show"], L["fishj.scope." .. state.scope]))
  local summary = ""
  if ledger then
    local totals = Store.Totals(ledger)
    summary = string.format(L["fishj.summary"], totals.catches, totals.kinds, totals.places)
    if state.place then
      local name = Logic.PlaceName(ledger, state.place, nil) or "?"
      summary = string.format(L["fishj.inPlace"], name) .. ". " .. summary
    end
  end
  frame.summary:SetText(summary)
  local note = ""
  if not ledger then
    note = L["fishj.newer"]
  elseif #rows == 0 then
    note = state.query ~= "" and L["fishj.noMatch"] or L["fishj.empty"]
  elseif fish.Controller.Options().recordCatches ~= true then
    note = L["fishj.off"]
  end
  frame.note:SetText(note)
  frame.legend:SetText(ledger and #rows > 0 and V.LegendText() or "")
  renderDetail()
end

-- The selection moved by a key. Returns true when the key was a navigation key.
function V.Key(key)
  if not frame or not frame:IsShown() then
    return false
  end
  local moves = { UP = true, DOWN = true, PAGEUP = true, PAGEDOWN = true, HOME = true, END = true }
  if moves[key] then
    select(Logic.Move(state.index, #frame.rows, key, pageSize()))
    frame.list:SetData(frame.rows)
    scrollToSelection()
    renderDetail()
    return true
  elseif key == "ENTER" and state.mode == "places" and frame.selected then
    state.place, state.mode, state.sort = frame.selected, "fish", "count"
    frame.selected = nil
    V.Refresh()
    return true
  elseif key == "BACKSPACE" and state.place then
    state.place, frame.selected = nil, nil
    V.Refresh()
    return true
  elseif key == "V" then
    V.SetMode(state.mode == "places" and "fish" or "places")
    return true
  elseif key == "S" then
    V.SetSort(Logic.Next(sorts(), state.sort))
    return true
  elseif key == "C" then
    V.SetScope(state.scope == "char" and "account" or "char")
    return true
  elseif key == "/" or key == "TAB" then
    frame.search.edit:SetFocus()
    return true
  end
  return false
end

function V.SetMode(mode)
  state.mode = mode == "places" and "places" or "fish"
  state.place = nil
  if state.sort ~= "name" and not contains(sorts(), state.sort) then
    state.sort = "name"
  end
  if frame then
    frame.selected = nil
    V.Refresh()
  end
end

function V.SetSort(sort)
  state.sort = contains(sorts(), sort) and sort or "name"
  if frame then
    V.Refresh()
  end
end

function V.SetScope(scope)
  state.scope = scope == "char" and "char" or "account"
  if frame then
    frame.selected = nil
    V.Refresh()
  end
end

function V.SetQuery(text)
  state.query = type(text) == "string" and text or ""
  if frame then
    V.Refresh()
  end
end

local function normalizeSort()
  if state.sort ~= "name" and not contains(sorts(), state.sort) then
    state.sort = "name"
  end
end

-- Shows one view row by its key. A search that hides it is cleared, so the click never leads to an empty list.
local function reveal(mode, key)
  state.mode, state.place = mode, nil
  normalizeSort()
  local found = false
  for _, row in ipairs(V.Rows()) do
    found = found or rowKey(row) == key
  end
  if not found and state.query ~= "" then
    state.query = ""
    if frame then
      frame.search.edit:SetText("")
    end
  end
  if frame then
    frame.selected = key
    V.Refresh()
  end
end

-- A click on a fish line: the fish list with this fish selected.
function V.OpenFish(id)
  reveal("fish", id)
end

-- A click on a place line: the place list with this place selected.
function V.OpenPlace(key)
  reveal("places", key)
end

-- The bar of a row ends where the count column starts. Both ends sit on the row itself at the same height, so
-- the vertical place of the bar never depends on another control.
local BAR_RIGHT = -(GAP + EXTRA_W + GAP + COUNT_W + GAP)

-- The left edge of the name and the bar differs between the views (the fish rows have an icon). Anchors are set when
-- the view changes only: a re-anchor on every refresh makes the client re-resolve the bar for nothing.
local function layoutRow(row, places)
  local layout = places and "places" or "fish"
  if row.layout == layout then
    return
  end
  row.layout = layout
  row.name:ClearAllPoints()
  row.bar:ClearAllPoints()
  local left = places and 10 or (8 + ICON_W + GAP)
  row.name:SetPoint("LEFT", row, "LEFT", left, 0)
  row.name:SetPoint("RIGHT", row.count, "LEFT", -GAP, 0)
  row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, BAR_BOTTOM)
  row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", BAR_RIGHT, BAR_BOTTOM)
end

local function bindRow(row, item, index)
  local places = state.mode == "places"
  layoutRow(row, places)
  row.count:SetText(string.format("%d", item.n))
  row.name:SetText(places and item.name or Detail.ColorName(item.name, fish.Game.ItemQuality(item.id)))
  if places then
    row.icon:Hide()
  else
    row.icon:SetTexture(fish.Game.ItemIcon(item.id))
    row.icon:Show()
  end
  -- The percent column and the bar show the same figure: the catch rate of a place, the share of a fish.
  row.extra:SetText(percent(places and item.rate or item.share))
  row.bar:SetShare(item.bar, V.BarText(item))
  local on = index == state.index
  row.sel:SetShown(on)
  row.mark:SetShown(on)
  row.outline.show(on)
  row.item, row.index = item, index
end

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  local r, g, b = Theme.color("accent")
  row.sel:SetColorTexture(r, g, b, 0.22)
  row.mark = row:CreateTexture(nil, "ARTWORK")
  row.mark:SetPoint("TOPLEFT")
  row.mark:SetPoint("BOTTOMLEFT")
  row.mark:SetWidth(3)
  row.mark:SetColorTexture(r, g, b, 1)
  row.outline = W.Border(row, "accent", 1)
  row.outline.show(false)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON_W, ICON_W)
  row.icon:SetPoint("LEFT", 8, 0)
  row.extra = W.Text(row, { role = "ui", color = "textMuted", justify = "RIGHT" })
  row.extra:SetPoint("RIGHT", -6, 0)
  row.extra:SetWidth(EXTRA_W)
  row.count = W.Text(row, { role = "ui", color = "accent2", justify = "RIGHT" })
  row.count:SetPoint("RIGHT", row.extra, "LEFT", -6, 0)
  row.count:SetWidth(COUNT_W)
  row.name = W.Text(row, { role = "ui", color = "text" })
  row.bar = Detail.NewBar(row, BAR_H)
  row:SetScript("OnEnter", function(self)
    local item = self.item
    if not item then
      return
    end
    if state.mode == "places" then
      FG.ShowTooltip(self, item.name, V.RowText(item), { lines = { V.BarText(item) }, hint = L["fishj.tip.place"] })
    else
      Detail.ShowItem(self, item.id, item.name, { V.RowText(item), V.BarText(item) }, L["fishj.tip.link"])
    end
  end)
  row:SetScript("OnLeave", FG.HideTooltip)
  row:SetScript(
    "OnClick",
    FG.Wrap("fishj-row", function(self)
      local item = self.item
      if not item then
        return
      end
      if state.mode == "fish" and fish.Game.ShiftDown() then
        Detail.LinkItem(item.id, item.name)
        return
      end
      if self.index then
        select(self.index)
        V.Refresh()
      end
    end)
  )
  return row
end

local function place(f)
  local db = saved()
  f:SetSize(U.clamp(db.w or DEFAULT_W, MIN_W, 1400), U.clamp(db.h or DEFAULT_H, MIN_H, 1000))
  f:ClearAllPoints()
  if type(db.x) == "number" and type(db.y) == "number" then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

local function remember(f)
  local db = saved()
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    db.x, db.y = left, top
  end
  db.w, db.h = f:GetWidth(), f:GetHeight()
end

local function textButton(parent, onClick)
  return W.Button(parent, { text = " ", width = BUTTON_W, height = 26, onClick = onClick })
end

local function create()
  local f = CreateFrame("Frame", "FGFishJournalWindow", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(MIN_W, MIN_H, 1400, 1000)
  end
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.shell = FG.WindowShell.Attach(f, { title = "fishj.title", titleHeight = HEAD_H, shadow = true })
  f.bar = f.shell.titleBar
  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "fishj.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    FG.Wrap("fishj-close", function()
      f:Hide()
    end)
  )
  f.placesButton = W.Button(f.bar, {
    text = " ",
    width = 120,
    height = 18,
    onClick = function()
      if fish.PlacesView then
        fish.PlacesView.Toggle()
      end
    end,
  })
  f.placesButton:SetPoint("RIGHT", f.close, "LEFT", -6, 0)
  W.SetText(f.placesButton.label, nil, L["fishp.open"])
  f.shell.titleText:ClearAllPoints()
  f.shell.titleText:SetPoint("LEFT", 8, 0)
  f.shell.titleText:SetPoint("RIGHT", f.placesButton, "LEFT", -4, 0)

  local top = -(HEAD_H + 8)
  f.viewButton = textButton(f, function()
    V.SetMode(state.mode == "places" and "fish" or "places")
  end)
  f.viewButton:SetPoint("TOPLEFT", 10, top)
  f.sortButton = textButton(f, function()
    V.SetSort(Logic.Next(sorts(), state.sort))
  end)
  f.sortButton:SetPoint("LEFT", f.viewButton, "RIGHT", 6, 0)
  f.scopeButton = textButton(f, function()
    V.SetScope(state.scope == "char" and "account" or "char")
  end)
  f.scopeButton:SetPoint("LEFT", f.sortButton, "RIGHT", 6, 0)

  f.search = W.EditBox(f, { placeholder = "fishj.search", clear = true, onChange = V.SetQuery })
  f.search:SetPoint("TOPLEFT", f.viewButton, "BOTTOMLEFT", 0, -6)
  f.search:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  local edit = f.search.edit
  edit:SetScript("OnArrowPressed", function(_, key)
    V.Key(key)
  end)
  edit:SetScript("OnTabPressed", function(self)
    self:ClearFocus()
  end)
  edit:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  edit:SetScript("OnEscapePressed", function(self)
    if self:GetText() ~= "" then
      self:SetText("")
      V.SetQuery("")
    else
      self:ClearFocus()
    end
  end)

  f.summary = W.Text(f, { role = "ui", color = "textSecondary" })
  f.summary:SetPoint("TOPLEFT", f.search, "BOTTOMLEFT", 0, -6)
  f.summary:SetPoint("TOPRIGHT", f.search, "BOTTOMRIGHT", 0, -6)
  f.note = W.Text(f, { role = "ui", color = "textMuted", wrap = true })
  f.note:SetPoint("TOPLEFT", f.summary, "BOTTOMLEFT", 0, -4)
  f.note:SetPoint("TOPRIGHT", f.summary, "BOTTOMRIGHT", 0, -4)
  f.legend = W.Text(f, { role = "micro", color = "textMuted", wrap = true })
  f.legend:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", 0, -4)
  f.legend:SetPoint("RIGHT", f, "RIGHT", -(DETAIL_W + 18), 0)
  f.hint = W.Text(f, { role = "micro", color = "textMuted", wrap = true })
  f.hint:SetPoint("BOTTOMLEFT", 10, 8)
  f.hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 8)
  f.hint:SetText(L["fishj.hint"])

  f.list = W.ScrollList(f, { rowHeight = ROW_H, createRow = createRow, bindRow = bindRow })
  f.list:SetPoint("TOPLEFT", f.legend, "BOTTOMLEFT", 0, -6)
  f.list:SetPoint("BOTTOM", f.hint, "TOP", 0, 6)
  f.list:SetPoint("RIGHT", f, "RIGHT", -(DETAIL_W + 18), 0)
  f.panel = Detail.Create(f, { onFish = V.OpenFish, onPlace = V.OpenPlace })
  f.detailArea = f.panel.area
  f.detailArea:SetPoint("TOPLEFT", f.list, "TOPRIGHT", 8, 0)
  f.detailArea:SetPoint("BOTTOMRIGHT", f.list, "BOTTOMRIGHT", DETAIL_W + 8, 0)
  f.empty = W.Text(f, { role = "ui", color = "textMuted", wrap = true })
  f.empty:SetPoint("TOPLEFT", f.detailArea, "TOPLEFT", 4, -4)
  f.empty:SetPoint("RIGHT", f.detailArea, "RIGHT", -8, 0)
  f.rows = {}

  f:EnableKeyboard(true)
  f:SetScript("OnKeyDown", function(self, key)
    local handled = false
    if not (self.search.edit.HasFocus and self.search.edit:HasFocus()) then
      handled = V.Key(key)
    end
    -- Blocked in combat: a blocked call would switch the fishing helper off (Blockade).
    FG.PropagateKeys(self, not handled)
  end)

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  local tex = grip:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript(
    "OnMouseUp",
    FG.Wrap("fishj-size", function()
      f:StopMovingOrSizing()
      remember(f)
      V.Refresh()
    end)
  )
  grip:SetScript("OnEnter", function(self)
    FG.ShowTooltip(self, L["fishj.grip"])
  end)
  grip:SetScript("OnLeave", FG.HideTooltip)
  f.grip = grip

  f.styleParts = {
    bg = { f.bg },
    bars = { f.shell.barFill },
    border = f.shell.border,
    shadow = f.shell.shadow,
    chrome = { f.bar, grip },
  }
  f.bar:EnableMouse(true)
  f.bar:RegisterForDrag("LeftButton")
  f.bar:SetScript("OnDragStart", function()
    WS.Hold(f, "move", true)
    f:StartMoving()
  end)
  f.bar:SetScript(
    "OnDragStop",
    FG.Wrap("fishj-move", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "move", false)
      remember(f)
    end)
  )
  FG.WindowShell.RegisterEsc(f, function()
    if state.query ~= "" then
      f.search.edit:SetText("")
      V.SetQuery("")
    else
      f:Hide()
    end
  end)
  f:SetScript("OnShow", function()
    V.Refresh()
  end)
  f:SetScript("OnHide", fish.Game.StopNameWatch)
  f:Hide()
  return f
end

-- Open and close ----------------------------------------------------------------------------------------------------------

function V.IsShown()
  return frame ~= nil and frame:IsShown()
end

function V.Frame()
  return frame
end

-- Opens the window. Not in combat: the window needs no protected call, it only stays out of the way.
function V.Open()
  if not frame then
    frame = create()
  end
  place(frame)
  WS.Apply(frame, WS.Resolve("fishjournal", nil), frame.styleParts)
  frame:Show()
  frame:Raise()
  V.Refresh()
  return frame
end

function V.Hide()
  if frame then
    frame:Hide()
  end
end

function V.Toggle()
  if V.IsShown() then
    V.Hide()
  else
    V.Open()
  end
end

-- A catch was recorded or a name arrived: the open window follows.
FG.On("FG_FISHING_JOURNAL", function()
  if V.IsShown() then
    V.Refresh()
  end
end)

-- The client delivered names that were missing: the open window draws them.
FG.On("FG_FISHING_NAMES", function()
  if V.IsShown() then
    V.Refresh()
  end
end)

-- The player switched the recording on or off: the note in the window follows.
FG.On("FG_FISHING_CHANGED", function(_, id)
  if id == "recordCatches" and V.IsShown() then
    V.Refresh()
  end
end)

-- The language changed.
FG.On("FG_LOCALE_CHANGED", function()
  if frame then
    frame.hint:SetText(L["fishj.hint"])
    if V.IsShown() then
      V.Refresh()
    end
  end
end)
