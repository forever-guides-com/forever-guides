-- Page "Library books": the books of the library sets by level, with status, counters per set and in total, and
-- the map and waypoint buttons of every book. The data is the books part of the Comprehension guide
-- (ForeverGuides_Comprehension, loaded by GuideKit.Load), the row list and the status words come from GuideKit.
local _, ns = ...
local W, L, Theme, GL, GK = ns.W, ns.L, ns.Theme, ns.GuideKitLogic, ns.GuideKit

ns.AddLocale("enUS", {
  ["page.librarybooks"] = "Library Books",
  ["page.librarybooks.sub"] = "Books to collect and hand in, by set",
  ["search.kind.book"] = "Library book",
  ["search.group.book"] = "Library books",
  ["librarybooks.intro"] = "Library books lie around the world. Pick them up and hand them in at a librarian. Every set belongs to a level range. The list shows where each book is and whether you have it.",
  ["librarybooks.total"] = "Handed in: %d/%d",
  ["librarybooks.owned"] = "Owned or handed in: %d/%d",
  ["librarybooks.setTitle"] = "Set %d - Level %d",
  ["librarybooks.legend.note"] = "The status follows the quest of the book, so a book you handed in does not need to stay in your bags.",
  ["librarybooks.help"] = "What can I do?",
  ["librarybooks.help.where"] = "Find the books in the zones of the list and use the Map or Waypoint button to get there. Some lie inside caves or at a dungeon entrance, the note on the row says so.",
  ["librarybooks.help.turnin"] = "Hand the books in at a librarian: Garion Wendell in Stormwind (Mage Quarter) or Owen Thadd in Orgrimmar (Magic Quarter).",
  ["librarybooks.help.rewards"] = "For 10, 20 and 25 handed in books you can pick a reward. The last list shows which ones.",
  ["librarybooks.help.zone"] = "The faction in front of a zone is only the usual territory of that zone. Either side can take the books. The buttons above the list narrow it down.",
  ["librarybooks.help.unconfirmed"] = "Rows marked Unconfirmed have not been checked in Forever yet. Position and zone can differ.",
})

ns.AddLocale("deDE", {
  ["page.librarybooks"] = "Bibliotheksbücher",
  ["page.librarybooks.sub"] = "Bücher sammeln und abgeben, nach Sets",
  ["search.kind.book"] = "Bibliotheksbuch",
  ["search.group.book"] = "Bibliotheksbücher",
  ["librarybooks.intro"] = "Bibliotheksbücher liegen überall in der Welt. Hebe sie auf und gib sie bei einem Bibliothekar ab. Jedes Set gehört zu einem Stufenbereich. Die Liste zeigt, wo jedes Buch liegt und ob du es hast.",
  ["librarybooks.total"] = "Abgegeben: %d/%d",
  ["librarybooks.owned"] = "Besessen oder abgegeben: %d/%d",
  ["librarybooks.setTitle"] = "Set %d - Stufe %d",
  ["librarybooks.legend.note"] = "Der Status folgt der Quest des Buchs, ein abgegebenes Buch muss also nicht in deinen Taschen bleiben.",
  ["librarybooks.help"] = "Was kann ich tun?",
  ["librarybooks.help.where"] = "Suche die Bücher in den Zonen der Liste und nutze die Knöpfe Karte oder Wegpunkt, um hinzukommen. Manche liegen in Höhlen oder an einem Dungeon-Eingang, die Notiz in der Zeile sagt es.",
  ["librarybooks.help.turnin"] = "Gib die Bücher bei einem Bibliothekar ab: Garion Wendell in Sturmwind (Magierviertel) oder Owen Thadd in Orgrimmar (Magieviertel).",
  ["librarybooks.help.rewards"] = "Für 10, 20 und 25 abgegebene Bücher kannst du dir eine Belohnung aussuchen. Die letzte Liste zeigt, welche.",
  ["librarybooks.help.zone"] = "Die Fraktion vor einer Zone ist nur das übliche Gebiet dieser Zone. Beide Seiten können die Bücher nehmen. Die Knöpfe über der Liste grenzen die Anzeige ein.",
  ["librarybooks.help.unconfirmed"] = "Zeilen mit dem Hinweis Unbestätigt sind in Forever noch nicht geprüft. Position und Zone können abweichen.",
})

local P = {}
ns.LibraryBooksPage = P

-- The sections of the guide that belong to this page: the book sets and the rewards.
function P.Sections(data)
  local out = {}
  for _, section in ipairs(data.sections) do
    if type(section.id) == "string" and section.id:find("^book") then
      out[#out + 1] = section
    end
  end
  return out
end

-- Handed in and total over a list of sections.
function P.Totals(sections, probe)
  local handed, total = 0, 0
  for _, section in ipairs(sections) do
    local h, t = GL.CollectionTotals(section.rows, probe)
    handed, total = handed + h, total + t
  end
  return handed, total
end

-- Books the player marked as read, per character, keyed by the quest id (the item id without a quest).
function P.Key(row)
  return tostring(row.quest or row.item)
end

function P.IsRead(row)
  local read = ns.charDB and ns.charDB.libraryBooksRead
  return type(read) == "table" and read[P.Key(row)] == true
end

function P.SetRead(row, on)
  ns.Store.setChar("libraryBooksRead." .. P.Key(row), on and true or nil)
end

-- Books that are in the hands of the player: handed in, marked as read, in the bags or in the bank.
function P.Owned(sections, probe)
  local owned, total = 0, 0
  for _, section in ipairs(sections) do
    for _, row in ipairs(section.rows) do
      local status = type(row.item) == "number" and GL.CollectionStatus(row, probe) or nil
      if status then
        total = total + 1
        owned = owned + ((status == "missing" or status == "open") and 0 or 1)
      end
    end
  end
  return owned, total
end

local function addLegend(view)
  GK.Legend(view, GK.LegendStates({ "handed", "read", "bag", "bank", "missing" }))
  ns.AddParagraph(view, "librarybooks.legend.note", { role = "micro", color = "textMuted", gap = Theme.space.md })
end

local function addHelp(view)
  local acc = W.Accordion(view, { id = "guide.librarybooks.help", title = L["librarybooks.help"], panel = true })
  for _, key in ipairs({ "where", "turnin", "rewards", "zone", "unconfirmed" }) do
    ns.AddParagraph(acc, "librarybooks.help." .. key, { role = "ui", gap = Theme.space.sm })
  end
  ns.Bind(acc, function()
    W.SetText(acc.header.label, nil, L["librarybooks.help"])
  end)
  return acc
end

-- Body of the page (GuideKit.Build spec.render): the counters, the legend, the help and one collapsible group
-- per set (header with counter and fill, column header, rows). Returns the function that repaints everything.
function P.Render(view, data, ctx)
  local sections = P.Sections(data)
  local probe = setmetatable({ marked = P.IsRead }, { __index = ctx.probe })
  local summary = ns.AddParagraph(view, nil, { role = "h3", family = "heading", color = "accent2", gap = Theme.space.xs })
  local owned = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary", gap = Theme.space.md })
  addLegend(view)
  addHelp(view)
  local entries = {}
  local number = 0
  for _, section in ipairs(sections) do
    -- A book set gets a short title, so the header with its counter fits a narrow page.
    local level = tonumber(section.id:match("^books%-(%d+)$"))
    number = level and number + 1 or number
    local entry = { section = section, level = level, number = number }
    entry.group = GK.Group(view, {
      id = "guide.librarybooks." .. section.id,
      note = section.note and ns.T(section.note) or nil,
      titleKey = "guidekit.col.title",
    })
    view.stack:Add(entry.group, { gap = Theme.space.sm })
    entries[#entries + 1] = entry
  end
  local opened = false
  local repaint
  local read = {
    get = P.IsRead,
    set = function(row, on)
      P.SetRead(row, on)
      repaint()
    end,
  }
  repaint = function()
    local handed, total = P.Totals(sections, probe)
    summary:SetText(string.format(L["librarybooks.total"], handed, total))
    owned:SetText(string.format(L["librarybooks.owned"], P.Owned(sections, probe)))
    for _, e in ipairs(entries) do
      local rows = GL.FilterRows(e.section.rows, ctx.state.faction)
      e.group:SetRows(rows, e.section, { probe = probe, read = read })
      e.group:SetHint(L["guidekit.noRows"])
      local h, t = GL.CollectionTotals(e.section.rows, probe)
      local title = e.level and string.format(L["librarybooks.setTitle"], e.number, e.level) or ns.T(e.section.title) or ""
      e.group:SetSummary(title, t > 0 and string.format(L["guidekit.group.count"], h, t) or nil, t > 0 and h / t or nil)
      -- The first set that is not finished starts open; later repaints keep what the player chose.
      if not opened and (t == 0 or h < t) then
        opened = true
        e.group:Open(false)
      end
    end
  end
  return repaint
end

-- The titles of the books are found by the global search and lead to this page. The data is read only where the
-- guide data has been loaded (the search never loads an add-on for it).
ns.SearchLogic.RegisterSource("book", function(add)
  local data = GL.IsValid(ns.GuideData.comprehension) and ns.GuideData.comprehension or nil
  for _, section in ipairs(data and P.Sections(data) or {}) do
    for _, row in ipairs(section.rows) do
      if type(row.item) == "number" and row.target then
        add(row.target, ns.T(row.zone), "librarybooks", { "Bibliotheksbuch", "Library book" })
      end
    end
  end
end)

ns.RegisterPage({
  id = "librarybooks",
  order = 475,
  group = "guides",
  title = "page.librarybooks",
  subtitle = "page.librarybooks.sub",
  icon = ns.ICONS.librarybooks,
  aliases = {
    "bibliothek",
    "bibliotheksbuecher",
    "bibliotheksbücher",
    "buecher",
    "bücher",
    "library",
    "library books",
    "books",
  },
  build = GK.Build({
    id = "comprehension",
    intro = "librarybooks.intro",
    collect = { name = { de = "Bibliotheksbücher", en = "Library books" } },
    faction = "all",
    render = P.Render,
  }),
})
