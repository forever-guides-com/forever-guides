-- Registry of slash commands and key bindings. Every entry names the menu
-- control that does the same: page = page id or "main" (window chrome),
-- control = locale key(s) of the button/toggle, or "page.<id>" for a sidebar
-- entry. tests/test_menu.lua fails when a command has no entry or the
-- control does not exist. exec = what the help page's "Run" button sends.
-- Add-ons that extend the main add-on register through C.Add.
local _, ns = ...

local C = { list = {}, byId = {}, bound = {}, bindings = {} }
ns.Commands = C

local function add(entry)
  C.list[#C.list + 1] = entry
  C.byId[entry.id] = entry
end

add({
  id = "show",
  names = { "show", "zeigen" },
  usage = "/fg show",
  page = "settings",
  control = "settings.minimap",
  area = "general",
  public = false,
})
add({
  id = "hide",
  names = { "hide", "verbergen" },
  usage = "/fg hide",
  page = "main",
  control = "common.close",
  area = "general",
  public = false,
})
add({
  id = "search",
  area = "general",
  example = { en = "/fg search silverleaf", de = "/fg suche Silberblatt" },
  public = true,
  names = { "search", "suche", "suchen" },
  usage = "/fg search <text>",
  page = "main",
  control = "search.placeholder",
})
add({
  id = "scale",
  area = "general",
  example = { en = "/fg scale 110", de = "/fg skalierung 110" },
  public = true,
  names = { "scale", "skalierung" },
  usage = "/fg scale 70-150",
  page = "settings",
  control = "settings.scale",
})
add({
  id = "reset",
  area = "general",
  example = { en = "/fg reset", de = "/fg reset" },
  public = true,
  names = { "reset" },
  usage = "/fg reset",
  page = "settings",
  control = "settings.resetWindow",
  exec = "reset",
})
add({
  id = "diag",
  area = "general",
  public = false,
  names = { "diag" },
  usage = "/fg diag",
  page = "help",
  control = "help.diagButton",
  exec = "diag",
})
add({
  id = "errors",
  area = "general",
  example = { en = "/fg errors", de = "/fg fehler" },
  public = true,
  names = { "errors", "fehler" },
  usage = "/fg errors",
  page = "errors",
  control = "help.copyErrors",
  exec = "errors",
})
add({
  id = "tour",
  area = "general",
  example = { en = "/fg tour", de = "/fg tour" },
  public = true,
  names = { "tour", "tutorial" },
  usage = "/fg tour [id]",
  page = "tutorials",
  control = "tutorials.start",
  exec = "tour",
})
add({
  id = "setup",
  area = "general",
  example = { en = "/fg setup", de = "/fg einrichtung" },
  public = true,
  names = { "setup", "einrichtung", "install", "installer", "assistent" },
  usage = "/fg setup [new]",
  page = "settings",
  control = "setup.start",
  exec = "setup",
})
add({
  id = "note",
  area = "tools",
  example = { en = "/fg note new", de = "/fg notiz new" },
  public = true,
  names = { "note", "notiz" },
  usage = "/fg note [new|close|stick|unstick|<title>]",
  page = "notes",
  control = { "notes.new", "notes.closeAll", "notes.field.sticky" },
  exec = "note",
})
add({
  id = "draw",
  area = "tools",
  example = { en = "/fg draw new", de = "/fg zeichnen new" },
  public = true,
  names = { "draw", "zeichnen", "zeichnung", "paint" },
  usage = "/fg draw [new|window <name>|name]",
  page = "drawings",
  control = { "page.drawings", "draw.new", "draw.page.window" },
  exec = "draw",
})
add({
  id = "shot",
  area = "map",
  example = { en = "/fg shot list", de = "/fg ortsshot list" },
  public = true,
  names = { "shot", "ortsshot" },
  usage = "/fg shot [list|save]",
  page = "shots",
  control = { "shots.take", "shots.save", "page.shots" },
  exec = "shot list",
})
add({
  id = "levels",
  area = "trainers",
  example = { en = "/fg levels MAGE", de = "/fg stufen MAGE" },
  public = true,
  names = { "levels", "stufen" },
  usage = "/fg levels [class]",
  page = "levels",
  control = { "levels.search", "levels.fromMe", "page.levels" },
  exec = "levels",
})
add({
  id = "weapons",
  area = "trainers",
  example = { en = "/fg weapons MAGE", de = "/fg waffen MAGE" },
  public = true,
  names = { "weapons", "waffen" },
  usage = "/fg weapons [class]",
  page = "weapons",
  control = "page.weapons",
  exec = "weapons",
})
add({
  id = "trainers",
  area = "trainers",
  example = { en = "/fg trainers MAGE", de = "/fg lehrer MAGE" },
  public = true,
  names = { "trainers", "lehrer" },
  usage = "/fg trainers [class]",
  page = "trainers",
  control = "page.trainers",
  exec = "trainers",
})
add({
  id = "way",
  area = "map",
  example = { en = "/fg way 45.2 63.1 Mine", de = "/fg weg 45,2 63,1 Mine" },
  public = true,
  names = { "way", "wegpunkt", "weg" },
  usage = "/fg way <x> <y> [title] | list | clear | next | prev | here [title] | arrow | remove <n>",
  page = "waypoints",
  control = { "page.waypoints", "wp.here", "wp.next", "wp.clear", "wp.set.arrow" },
  exec = "way list",
})
add({
  id = "calc",
  area = "tools",
  example = { en = "/fg calc 12g 50s * 3", de = "/fg rechner 12g 50s * 3" },
  public = true,
  names = { "calc", "rechner", "taschenrechner" },
  usage = "/fg calc [calculation]",
  page = "calc",
  control = "page.calc",
  exec = "calc",
})
add({
  id = "durability",
  area = "tools",
  example = { en = "/fg durability", de = "/fg haltbarkeit" },
  public = true,
  names = { "durability", "haltbarkeit", "haltbar", "repair", "reparatur" },
  usage = "/fg durability",
  page = "durability",
  control = "page.durability",
  exec = "durability",
})
add({
  id = "xpbar",
  area = "tools",
  example = { en = "/fg xp", de = "/fg erfahrung" },
  public = true,
  names = { "erfahrung", "xp", "xpbar" },
  usage = "/fg erfahrung [pause | reset | edit | zeit <von> <bis> | chat an|aus | chat <selbst|gruppe|gilde|sagen> an|aus]",
  page = "xpbar",
  control = "xpbar.set.show",
})
add({
  id = "cursor",
  area = "tools",
  example = { en = "/fg cursor", de = "/fg mauszeiger" },
  public = true,
  names = { "mauszeiger", "cursor", "ring" },
  usage = "/fg mauszeiger [an | aus | edit | reset]",
  page = "cursor",
  control = "cursor.set.enabled",
  exec = "mauszeiger",
})
add({
  id = "einkauf",
  area = "professions",
  example = { en = "/fg shopping", de = "/fg einkauf" },
  public = true,
  names = { "einkauf", "shopping", "einkaufsliste" },
  usage = "/fg einkauf [profession]",
  page = "professionroute",
  control = { "page.professionroute", "profroute.shop" },
  exec = "einkauf",
})
add({
  id = "loot",
  area = "character",
  example = { en = "/fg loot", de = "/fg beute" },
  public = true,
  names = { "beute", "loot", "lootcapture" },
  usage = "/fg loot [reset]",
  page = "loot",
  control = { "page.loot", "loot.clear" },
  exec = "loot",
})
add({
  id = "automation",
  area = "tools",
  example = { en = "/fg automation", de = "/fg automatik" },
  public = true,
  names = { "automatik", "automation" },
  usage = "/fg automatik",
  page = "settings",
  control = "auto.set.heading",
  exec = "automatik",
})
add({
  id = "lfg",
  area = "guild",
  example = { en = "/fg lfg", de = "/fg gruppensuche" },
  public = true,
  names = { "gruppensuche", "lfg" },
  usage = "/fg gruppensuche",
  page = "settings",
  control = "lfg.set.panel",
  exec = "gruppensuche",
})
add({
  id = "autoquest",
  area = "tools",
  example = { en = "/fg autoquest list", de = "/fg autoquest list" },
  public = true,
  names = { "autoquest", "autoquests" },
  usage = "/fg autoquest ignore <questID> | ignore npc <npcID> | list",
  page = "settings",
  control = "auto.set.ignoreQuests",
  exec = "autoquest list",
})
add({
  id = "fenster",
  area = "general",
  example = { en = "/fg windows list", de = "/fg fenster list" },
  public = true,
  names = { "fenster", "windows" },
  usage = "/fg fenster list | reset [name] | open",
  page = "windows",
  control = "win.enabled",
  exec = "fenster list",
})
add({
  id = "flighttimer",
  area = "map",
  example = { en = "/fg flighttimer", de = "/fg flugtimer" },
  public = true,
  names = { "flugtimer", "flighttimer", "flugzeit" },
  usage = "/fg flugtimer",
  page = "settings",
  control = "flighttimer.enable",
})
add({
  id = "route",
  area = "map",
  example = { en = "/fg route", de = "/fg route" },
  public = true,
  names = { "route", "routen" },
  usage = "/fg route",
  page = "map",
  control = "map.rb.open",
})
add({
  id = "share",
  area = "tools",
  example = { en = "/fg share", de = "/fg teilen" },
  public = true,
  names = { "share", "teilen" },
  usage = "/fg share [note title]",
  page = "notes",
  control = "notes.act.share",
})
add({
  id = "dock",
  area = "tools",
  example = { en = "/fg dock", de = "/fg kompakt" },
  public = true,
  names = { "dock", "kompakt" },
  usage = "/fg dock",
  page = "main",
  control = { "dock.toggle", "settings.dock" },
  exec = "dock",
})
add({
  id = "export",
  names = { "export" },
  usage = "/fg export",
  page = "character",
  control = "page.character",
  area = "character",
  example = { en = "/fg export", de = "/fg export" },
  public = true,
})
add({
  id = "import",
  names = { "import" },
  usage = "/fg import",
  page = "talents",
  control = "page.talents",
  area = "trainers",
  example = { en = "/fg import", de = "/fg import" },
  public = true,
})
add({
  id = "lang",
  area = "general",
  example = { en = "/fg lang de", de = "/fg sprache en" },
  public = true,
  names = { "lang", "sprache" },
  usage = "/fg lang de|en|auto",
  page = "settings",
  control = "settings.languageLabel",
})
add({
  id = "help",
  area = "general",
  example = { en = "/fg help map", de = "/fg hilfe karte" },
  public = true,
  names = { "help", "hilfe", "?" },
  usage = "/fg help",
  page = "help",
  control = "page.help",
  exec = "help",
})
add({
  id = "chars",
  area = "character",
  example = { en = "/fg alts", de = "/fg chars" },
  public = true,
  names = { "chars", "alts" },
  usage = "/fg chars",
  page = "chars",
  control = "page.chars",
  exec = "chars",
})
add({
  id = "todo",
  area = "character",
  example = { en = "/fg todo Empty guild bank", de = "/fg todo Gildenbank leeren" },
  public = true,
  names = { "todo" },
  usage = "/fg todo <text>",
  page = "chars",
  control = "chars.todo.addRow",
})
add({
  id = "find",
  area = "character",
  example = { en = "/fg find Silverleaf", de = "/fg bestand Silberblatt" },
  public = true,
  names = { "bestand", "find" },
  usage = "/fg find <item>",
  page = "search",
  control = "page.search",
  exec = "find",
})
add({
  id = "inventory",
  area = "character",
  example = { en = "/fg inventory", de = "/fg inventar" },
  public = true,
  names = { "inventar", "inventory" },
  usage = "/fg inventory [item]",
  page = "settings",
  control = "inv.set.enable",
  exec = "inventory",
})
add({
  id = "inspect",
  area = "character",
  example = { en = "/fg inspect", de = "/fg betrachten" },
  public = true,
  names = { "untersuchen", "inspect", "betrachten" },
  usage = "/fg inspect",
  page = "inspect",
  control = "page.inspect",
  exec = "inspect",
})
add({
  id = "talents",
  area = "trainers",
  example = { en = "/fg talents", de = "/fg talente" },
  public = true,
  names = { "talente", "talents" },
  usage = "/fg talents",
  page = "talents",
  control = "page.talents",
  exec = "talents",
})
add({
  id = "legacy",
  area = "character",
  example = { en = "/fg legacy", de = "/fg vermaechtnis" },
  public = true,
  names = { "legacy", "vermaechtnis", "vermächtnis" },
  usage = "/fg legacy",
  page = "legacy",
  control = "page.legacy",
  exec = "legacy",
})
add({
  id = "map",
  area = "map",
  example = { en = "/fg map Orgrimmar", de = "/fg karte Orgrimmar" },
  public = true,
  names = { "karte", "map" },
  usage = "/fg map [place]",
  page = "map",
  control = { "page.map", "map.placeSearch" },
  exec = "map",
})
add({
  id = "marker",
  area = "map",
  example = { en = "/fg marks", de = "/fg marker" },
  public = true,
  names = { "marker", "marks" },
  usage = "/fg marker",
  page = "map",
  control = "map.mode.markers",
  exec = "marker",
})
add({
  id = "access",
  area = "instances",
  example = { en = "/fg access", de = "/fg zugang" },
  public = true,
  names = { "zugang", "access" },
  usage = "/fg access [instance]",
  page = "instances",
  control = { "page.instances", "instances.dtab.access" },
  exec = "access",
})
add({
  id = "lockouts",
  area = "instances",
  example = { en = "/fg lockouts", de = "/fg sperren" },
  public = true,
  names = { "sperren", "lockouts" },
  usage = "/fg lockouts",
  page = "chars",
  control = "chars.row.raids",
  exec = "lockouts",
})
add({
  id = "profession",
  area = "professions",
  example = { en = "/fg profession", de = "/fg beruf" },
  public = true,
  names = { "beruf", "profession", "berufsroute", "professionroute" },
  usage = "/fg profession",
  page = "professionroute",
  control = "page.professionroute",
  exec = "profession",
})
add({
  id = "proftrainers",
  area = "professions",
  example = { en = "/fg proftrainers alchemy", de = "/fg berufslehrer alchemie" },
  public = true,
  names = { "berufslehrer", "proftrainers", "professiontrainers" },
  usage = "/fg proftrainers [profession]",
  page = "proftrainers",
  control = "page.proftrainers",
  exec = "proftrainers",
})
add({
  id = "guild",
  area = "guild",
  example = { en = "/fg guild", de = "/fg gilde" },
  public = true,
  names = { "gilde", "guild", "gilden" },
  usage = "/fg guild",
  page = "guild",
  control = "page.guild",
  exec = "guild",
})
add({
  id = "social",
  area = "guild",
  example = { en = "/fg social", de = "/fg sozial" },
  public = true,
  names = { "sozial", "social", "kontakte", "contacts" },
  usage = "/fg social",
  page = "contacts",
  control = "page.contacts",
  exec = "social",
})
add({
  id = "macros",
  area = "tools",
  example = { en = "/fg macros", de = "/fg makro" },
  public = true,
  names = { "makro", "macros", "makros" },
  usage = "/fg macros",
  page = "macros",
  control = "page.macros",
  exec = "macros",
})
add({
  id = "settings",
  area = "general",
  example = { en = "/fg settings", de = "/fg einstellungen" },
  public = true,
  names = { "einstellungen", "settings", "optionen", "options" },
  usage = "/fg settings",
  page = "settings",
  control = "page.settings",
  exec = "settings",
})
add({
  id = "about",
  area = "general",
  example = { en = "/fg about", de = "/fg info" },
  public = true,
  names = { "info", "about" },
  usage = "/fg about",
  page = "help",
  control = "help.websiteButton",
  exec = "about",
})

-- Help areas in display order. names[1] is the English id, names[2] the German name (both are
-- typed after /fg help), further names are synonyms. Titles live in the "area.<id>" locale keys.
C.AREAS = {
  { id = "general", names = { "general", "allgemein" } },
  { id = "map", names = { "map", "karte", "reise", "travel" } },
  { id = "trainers", names = { "trainers", "lehrer", "talents", "talente" } },
  { id = "instances", names = { "instances", "instanzen", "raids", "dungeons" } },
  { id = "professions", names = { "professions", "berufe" } },
  { id = "character", names = { "character", "charakter", "übersicht", "overview" } },
  { id = "guild", names = { "guild", "gilde", "social", "sozial", "contacts", "kontakte" } },
  { id = "tools", names = { "tools", "werkzeuge" } },
  { id = "next", names = { "next", "weiter", "nächste" } },
}
C.areaById = {}
for _, a in ipairs(C.AREAS) do
  C.areaById[a.id] = a
end

for _, c in ipairs(C.list) do
  assert(C.areaById[c.area], "command without a known area: " .. c.id)
end

-- Entry of an add-on that loads after the main add-on, under the same rules as the entries above.
function C.Add(entry)
  assert(not C.byId[entry.id], "command id taken: " .. entry.id)
  assert(C.areaById[entry.area], "command without a known area: " .. entry.id)
  add(entry)
end

-- Help area of every page of the main window: the "Commands" link in the page header opens
-- the help of that area. tests/test_slash.lua fails for a page without an entry.
C.PAGE_AREA = {
  dashboard = "general",
  search = "general",
  help = "general",
  settings = "general",
  errors = "general",
  tutorials = "general",
  windows = "general",
  map = "map",
  waypoints = "map",
  shots = "map",
  trainers = "trainers",
  weapons = "trainers",
  levels = "trainers",
  talents = "trainers",
  legacy = "character",
  classes = "trainers",
  instances = "instances",
  professions = "professions",
  professionroute = "professions",
  proftrainers = "professions",
  chars = "character",
  character = "character",
  inspect = "character",
  loot = "character",
  items = "character",
  guild = "guild",
  contacts = "guild",
  notes = "tools",
  drawings = "tools",
  calc = "tools",
  durability = "tools",
  xpbar = "tools",
  cursor = "tools",
  macros = "tools",
}
for page, area in pairs(C.PAGE_AREA) do
  assert(C.areaById[area], "page mapped to an unknown area: " .. page)
end

-- Entries of one area, public (player) commands or the hidden developer ones.
function C.inArea(area, public)
  local out = {}
  for _, c in ipairs(C.list) do
    if c.area == area and c.public == public then
      out[#out + 1] = c
    end
  end
  return out
end

-- Areas that have at least one public command, in AREAS order.
function C.activeAreas()
  local out = {}
  for _, a in ipairs(C.AREAS) do
    if #C.inArea(a.id, true) > 0 then
      out[#out + 1] = a
    end
  end
  return out
end

-- Example line in the active language, nil for hidden commands.
function C.example(entry)
  local ex = entry.example
  return ex and (ns.GetActiveLocale() == "deDE" and ex.de or ex.en) or nil
end

C.bindings.FOREVERGUIDES_TOGGLE = { page = "settings", control = "settings.minimap" }
C.bindings.FOREVERGUIDES_SEARCH = { page = "main", control = "search.placeholder" }
C.bindings.FOREVERGUIDES_DOCK = { page = "main", control = { "dock.toggle", "settings.dock" } }
C.bindings.FOREVERGUIDES_SHOT = { page = "shots", control = "shots.take" }
C.bindings.FOREVERGUIDES_NOTES = { page = "notes", control = "page.notes" }
C.bindings.FOREVERGUIDES_NOTE_NEW = { page = "notes", control = "notes.new" }
C.bindings.FOREVERGUIDES_DRAWINGS = { page = "drawings", control = "page.drawings" }
C.bindings.FOREVERGUIDES_DRAWING_NEW = { page = "drawings", control = "draw.new" }
C.bindings.FOREVERGUIDES_TALENTS = { page = "talents", control = "page.talents" }
C.bindings.FOREVERGUIDES_LEVELS = { page = "levels", control = "page.levels" }
C.bindings.FOREVERGUIDES_MAP = { page = "map", control = "page.map" }
C.bindings.FOREVERGUIDES_ROUTE = { page = "map", control = "map.rb.open" }
C.bindings.FOREVERGUIDES_WEAPONS = { page = "weapons", control = "page.weapons" }
C.bindings.FOREVERGUIDES_TRAINERS = { page = "trainers", control = "page.trainers" }
C.bindings.FOREVERGUIDES_SHARE = { page = "notes", control = "notes.act.share" }
C.bindings.FOREVERGUIDES_WAYPOINT_NEXT = { page = "waypoints", control = "wp.next" }
C.bindings.FOREVERGUIDES_WAYPOINT_ARROW = { page = "waypoints", control = "wp.set.arrow" }
C.bindings.FOREVERGUIDES_WAYPOINT_HERE = { page = "waypoints", control = "wp.here" }
C.bindings.FOREVERGUIDES_CALC = { page = "calc", control = "page.calc" }
C.bindings.FOREVERGUIDES_DURABILITY = { page = "durability", control = "page.durability" }
C.bindings.FOREVERGUIDES_XPBAR = { page = "xpbar", control = "xpbar.set.show" }
C.bindings.FOREVERGUIDES_CURSORRING = { page = "cursor", control = "cursor.set.enabled" }

local EN = {}
local DE = {}
local function desc(id, en, de)
  EN["cmd." .. id] = en
  DE["cmd." .. id] = de
end
desc(
  "levels",
  "Open the level overview, optional class (e.g. MAGE).",
  "Öffnet die Stufen-Übersicht, optional Klasse (z. B. MAGE)."
)
desc("weapons", "Weapon skills page, optional class (e.g. MAGE).", "Waffenfertigkeiten, optional Klasse (z. B. MAGE).")
desc("trainers", "Class trainers page, optional class (e.g. MAGE).", "Klassenlehrer, optional Klasse (z. B. MAGE).")
desc(
  "way",
  "Waypoints with arrow: /fg way 45.2 63.1 title. Also list, clear, next, prev, here, arrow, remove <n>.",
  "Wegpunkte mit Pfeil: /fg way 45,2 63,1 Titel. Auch list, clear, next, prev, here, arrow, remove <n>."
)
desc(
  "calc",
  "Calculator toggle, with text it calculates (e.g. /fg calc 12g 50s * 3).",
  "Rechner umschalten, mit Text rechnen (z. B. /fg calc 12g 50s * 3)."
)
desc(
  "durability",
  "Durability window: condition of your equipment in percent per part, toggles the window.",
  "Haltbarkeits-Fenster: Zustand der Ausrüstung in Prozent je Teil, schaltet das Fenster um."
)
desc(
  "xpbar",
  "Experience bar: toggles the window. Also pause, reset, edit, time <from> <to>, chat on|off, chat <channel> on|off.",
  "Erfahrungsleiste: schaltet das Fenster um. Auch pause, reset, edit, zeit <von> <bis>, chat an|aus, chat <Kanal> an|aus."
)
desc(
  "cursor",
  "Mouse cursor ring: toggles the ring that follows the cursor. Also on, off, edit, reset.",
  "Mauszeiger-Ring: schaltet den Ring um, der dem Zeiger folgt. Auch an, aus, edit, reset."
)
desc(
  "einkauf",
  "Shopping list window of the profession route, optional profession.",
  "Einkaufsliste der Berufsroute, optional Beruf."
)
desc(
  "loot",
  "Loot page: boss drops with drop rate. reset deletes after asking.",
  "Beute-Seite: Boss-Drops mit Droprate. reset löscht nach Rückfrage."
)
desc(
  "fenster",
  "Game windows: list moved ones, reset positions.",
  "Spielfenster: verschobene zeigen, Positionen zurücksetzen."
)
desc(
  "automation",
  "Open the automation settings (repair, summon, quests, duels, release).",
  "Öffnet die Automatik-Einstellungen (Reparatur, Beschwörung, Quests, Duelle, Freilassen)."
)
desc(
  "autoquest",
  "Quest helper exceptions: ignore <questID>, ignore npc <npcID>, list.",
  "Ausnahmen der Quest-Automatik: ignore <Quest-ID>, ignore npc <NPC-ID>, list."
)
desc("lfg", "Show/hide the filter panel at the group finder.", "Filter-Panel an der Gruppensuche ein-/ausblenden.")
desc(
  "flighttimer",
  "Show/hide a 60 s example flight in the flight timer.",
  "Beispielflug (60 s) im Flug-Timer ein-/ausblenden."
)
desc("route", "Open/close the route window.", "Routen-Fenster öffnen/schließen.")
desc("share", "Share a note in chat, empty dialog without a title.", "Notiz im Chat teilen, ohne Titel leerer Dialog.")
EN["way.usage"] =
  "Usage: /fg way <x> <y> [title], #map x y [title], zone x, y [title], list, clear, next, prev, here [title], arrow, remove <n>"
DE["way.usage"] =
  "Benutzung: /fg way <x> <y> [Titel], #Karte x y [Titel], Zone x, y [Titel], list, clear, next, prev, here [Titel], arrow, remove <n>"
desc("show", "Open the main window.", "Öffnet das Hauptfenster.")
desc("hide", "Close the main window.", "Schließt das Hauptfenster.")
desc("search", "Search everything, without text jump to the box.", "Alles durchsuchen, ohne Text ins Suchfeld.")
desc("scale", "Set the window scale in percent (70-150).", "Setzt die Fensterskalierung in Prozent (70-150).")
desc("reset", "Reset window position, size and scale.", "Setzt Position, Größe und Skalierung des Fensters zurück.")
desc("diag", "Show the diagnostic report to copy.", "Zeigt den Diagnosebericht zum Kopieren.")
desc("errors", "Open the error list page.", "Öffnet die Fehlerliste-Seite.")
desc(
  "tour",
  "Start a tour (default: first steps), else tutorials page.",
  "Tour starten (Standard: Erste Schritte), sonst Tutorials."
)
desc("setup", "Open the setup wizard, new: only new steps.", "Öffnet die Einrichtung, new: nur neue Schritte.")
desc("note", "Manage notes, without arguments the notes page.", "Notizen verwalten, ohne Angabe die Notizen-Seite.")
desc(
  "draw",
  "Drawings: new, name or window name (empty: page).",
  "Zeichnungen: new, Name oder window Name (leer: Seite)."
)
desc(
  "shot",
  "Location screenshot, list: page, save: write with reload.",
  "Orts-Screenshot, list: Seite, save: sichern per Neuladen."
)
desc("dock", "Show or hide the compact window.", "Blendet das Kompaktfenster ein oder aus.")
desc("export", "Open the character export page.", "Öffnet die Seite Charakter und Export.")
desc("import", "Talent editor: import link, load, apply.", "Talent-Editor: Link importieren, laden, anwenden.")
desc("lang", "Set the language: de, en or auto.", "Stellt die Sprache ein: de, en oder auto.")
desc("help", "List the commands in chat.", "Listet die Befehle im Chat.")
desc("chars", "Open the character overview.", "Öffnet die Charakter-Übersicht.")
desc("todo", "Add your own todo to the overview.", "Fügt einen eigenen Punkt zur Übersicht hinzu.")
desc("find", "Search for an item.", "Sucht ein Item.")
desc(
  "inventory",
  "Check the stock of all characters in the item tooltip, optional item link or id.",
  "Prüft den Bestand aller Charaktere im Item-Tooltip, optional Item-Link oder ID."
)
desc("inspect", "Open the inspect page.", "Öffnet die Betrachten-Seite.")
desc("talents", "Open the talent editor.", "Öffnet den Talent-Editor.")
desc("legacy", "Open the Legacy planner.", "Öffnet den Vermächtnis-Planer.")
desc("map", "Open the map, optional place search.", "Öffnet die Karte, optional Ortssuche.")
desc("marker", "Open the map in marker mode.", "Öffnet die Karte im Marker-Modus.")
desc("access", "Access requirements, optional instance.", "Zugangsbedingungen, optional Instanz.")
desc("lockouts", "Raid lockouts of all characters.", "Raid-Sperren aller Charaktere.")
desc("profession", "Open the profession route.", "Öffnet die Berufsroute.")
desc(
  "proftrainers",
  "Profession trainers page with positions, optional profession.",
  "Berufslehrer mit Standorten, optional Beruf."
)
desc("guild", "Open the guild page.", "Öffnet die Gildenseite.")
desc("social", "Open the contacts: players you have met.", "Öffnet die Kontakte: Spieler, die du getroffen hast.")
desc("macros", "Open the macro editor.", "Öffnet den Makro-Editor.")
desc("settings", "Open the settings.", "Öffnet die Einstellungen.")
desc("about", "Version, data status, website, license.", "Version, Datenstand, Website, Lizenz.")
local AREA_TITLES = {
  general = { "General", "Allgemein" },
  map = { "Map and travel", "Karte und Reise" },
  trainers = { "Trainers and talents", "Lehrer und Talente" },
  instances = { "Instances and raids", "Instanzen und Raids" },
  professions = { "Professions", "Berufe" },
  character = { "Character and overview", "Charakter und Übersicht" },
  guild = { "Guild & Contacts", "Gilde & Kontakte" },
  tools = { "Tools", "Werkzeuge" },
  next = { "Next steps", "Nächste Schritte" },
}
for id, t in pairs(AREA_TITLES) do
  EN["area." .. id] = t[1]
  DE["area." .. id] = t[2]
end
EN["cmdhelp.areas"] = "Help by area, click to type:"
DE["cmdhelp.areas"] = "Hilfe nach Bereich, Klick tippt ein:"
EN["cmdhelp.area"] = "%s, click to type:"
DE["cmdhelp.area"] = "%s, Klick tippt ein:"
EN["cmdhelp.unknownArea"] = 'No area "%s". Areas:'
DE["cmdhelp.unknownArea"] = 'Kein Bereich "%s". Bereiche:'
EN["cmdhelp.more"] = "More:"
DE["cmdhelp.more"] = "Weitere:"
EN["cmdhelp.copyHint"] = "Commands of this area, one per line."
DE["cmdhelp.copyHint"] = "Befehle dieses Bereichs, je einer pro Zeile."
EN["pagecmd.button"] = "Commands"
DE["pagecmd.button"] = "Befehle"
EN["pagecmd.tip"] = "Commands of this area in chat"
DE["pagecmd.tip"] = "Befehle dieses Bereichs im Chat"
EN["cmdhelp.copy"] = "Copy example"
DE["cmdhelp.copy"] = "Beispiel kopieren"
EN["help.section.commands"] = "Commands and key bindings"
DE["help.section.commands"] = "Befehle und Tastenbelegung"
EN["help.commandsIntro"] = "All commands also exist in the menu, Run starts them."
DE["help.commandsIntro"] = "Alle Befehle gibt es auch im Menü, Ausführen startet sie."
EN["help.commandMenu"] = "Menu: %s"
DE["help.commandMenu"] = "Menü: %s"
EN["help.commandRun"] = "Run"
DE["help.commandRun"] = "Ausführen"
EN["help.commandRunTip"] = "Runs this command as if typed in chat."
DE["help.commandRunTip"] = "Führt den Befehl aus, als hättest du ihn im Chat getippt."
EN["help.bindings"] =
  "Key bindings: Esc > Options > Key Bindings > AddOns > Forever Guides, none set by default.\nBindable: window, search, compact window, location screenshot, notes, drawings, talent editor, learn list, map, route window, weapon masters, class trainers, share, waypoints, calculator, durability window, experience bar, mouse cursor ring.\nEvery action also has a button in the window."
DE["help.bindings"] =
  "Tastenbelegung: Esc > Optionen > Tastaturbelegung > AddOns > Forever Guides, standardmäßig leer.\nBelegbar: Fenster, Suche, Kompaktfenster, Orts-Screenshot, Notizen, Zeichnungen, Talent-Editor, Lernliste, Karte, Routen-Fenster, Waffenmeister, Klassenlehrer, Teilen, Wegpunkte, Rechner, Haltbarkeits-Fenster, Erfahrungsleiste, Mauszeiger-Ring.\nJede Aktion gibt es auch als Knopf im Fenster."
ns.AddLocale("enUS", EN)
ns.AddLocale("deDE", DE)
