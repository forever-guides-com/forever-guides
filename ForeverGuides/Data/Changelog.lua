-- Generated from the changelog of the repo, do not edit.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.Changelog = {
  v = 1,
  versions = {
    {
      version = "0.7.9",
      date = "2026-11-14",
      highlights = {
      },
      added = {
        { de = "Berufe: Herstellbare Reagenzien tragen einen Pfeil. Ein Klick öffnet ihr Rezept, mit Zurück kommst du wieder hin, der Tooltip nennt ihre Reagenzien.", en = "Professions: Craftable reagents carry an arrow. One click opens their recipe, Back takes you there again, and the tooltip lists their reagents.", go = "professions" },
      },
      changed = {
        { de = "Berufe: Gegenstände und Reagenzien heißen so wie in deinem Spiel, im deutschen Spiel also auf Deutsch.", en = "Professions: Items and reagents use the names of your game, so they appear in German in the German game.", go = "professions" },
        { de = "Berufe: Ein Klick auf ein Reagenz setzt es nicht mehr auf die Einkaufsliste.", en = "Professions: Clicking a reagent no longer puts it on the shopping list.", go = "professions" },
        { de = "Forever Chat: Das Fenster öffnet sich deutlich schneller, auch wenn eine neue Nachricht es von selbst öffnet.", en = "Forever Chat: The window opens much faster, also when a new message opens it by itself.", go = "settings:foreverchat.options" },
      },
      fixed = {
        { de = "Forever Chat: Neue Nachrichten bei offenem Chat bremsen das Spiel nicht mehr aus.", en = "Forever Chat: New messages no longer slow the game down while the chat is open.", go = "settings:foreverchat.options" },
        { de = "Gilde: Minimap, Karte und Berufsverzeichnis lesen die Gildenliste seltener neu und kosten in großen Gilden weniger Leistung.", en = "Guild: The minimap, the map and the crafter directory read the guild list less often and cost less performance in large guilds." },
      },
    },
    {
      version = "0.7.8",
      date = "2026-11-13",
      highlights = {
      },
      fixed = {
        { de = "Forever Chat: Tippen im Eingabefeld bremst das Spiel nicht mehr aus.", en = "Forever Chat: typing in the input box no longer slows the game down.", go = "settings:foreverchat.options" },
        { de = "Forever Chat: Beginnst du zu tippen, bleibt die letzte Nachricht sichtbar und wird nicht mehr überdeckt.", en = "Forever Chat: when you start typing, the last message stays visible and is no longer covered.", go = "settings:foreverchat.options" },
      },
    },
    {
      version = "0.7.7",
      date = "2026-11-13",
      highlights = {
        { head = { de = "Wo eine Quest beginnt", en = "Where a quest starts" }, text = { de = "Die Instanz-Questliste zeigt bei jeder Quest, ob du sie vor der Instanz oder erst darin bekommst.", en = "The instance quest list shows for each quest whether you get it before the instance or only inside it." }, go = "instances" },
      },
      added = {
        { de = "Instanzen: Jede Quest nennt in der Liste \"Start: drinnen\" oder \"Start: draußen\", wenn der Annahmeort bekannt ist.", en = "Instances: Each quest says \"Start: inside\" or \"Start: outside\" in the list when the place to accept it is known.", go = "instances" },
        { de = "Instanzen: Die Details einer Quest zeigen unter \"Annahme\", ob sie in der Instanz beginnt (mit Geber oder Gegenstand) oder außerhalb (mit Geber und Zone).", en = "Instances: The details of a quest show under \"Accepted\" whether it starts inside the instance (with giver or item) or outside (with giver and zone).", go = "instances" },
      },
    },
    {
      version = "0.7.6",
      date = "2026-11-13",
      highlights = {
        { head = { de = "Quests wie im Questlog", en = "Quests like the quest log" }, text = { de = "Links die Instanz-Quests, rechts Ziel, Beschreibung und Belohnungen mit Gegenständen, EP und Gold.", en = "Instance quests on the left, objective, description and rewards with items, XP and gold on the right." }, go = "instances" },
        { head = { de = "Scharlachrotes Kloster in Flügeln", en = "Scarlet Monastery by wing" }, text = { de = "Friedhof, Bibliothek, Waffenkammer und Kathedrale haben eigene Karten mit Bossen und Quests.", en = "Graveyard, Library, Armory and Cathedral each have their own card with bosses and quests." }, go = "instances" },
        { head = { de = "Questtexte auf Deutsch", en = "Quest texts in German" }, text = { de = "Titel, Ziele und viele Beschreibungen der Instanz-Quests erscheinen im deutschen Spiel auf Deutsch.", en = "Titles, objectives and many descriptions of instance quests appear in German in the German game." }, go = "instances" },
      },
      added = {
        { de = "Instanzen: Die Quests einer Instanz erscheinen wie im Questlog, links die Liste, rechts die Details mit Belohnungen als Kacheln samt Tooltip.", en = "Instances: The quests of an instance look like the quest log, with the list on the left and details on the right, rewards shown as tiles with tooltips.", go = "instances" },
        { de = "Instanzen: Das Scharlachrote Kloster ist in Friedhof, Bibliothek, Waffenkammer und Kathedrale geteilt, jeder Flügel mit eigenen Bossen und Quests.", en = "Instances: Scarlet Monastery is split into Graveyard, Library, Armory and Cathedral, each wing with its own bosses and quests.", go = "instances" },
        { de = "Instanzen: 13 weitere Dungeon-Quests, unter anderem in Gnomeregan, Uldaman, den Blackrocktiefen, Düsterbruch und Scholomance.", en = "Instances: 13 more dungeon quests, among them in Gnomeregan, Uldaman, Blackrock Depths, Dire Maul and Scholomance.", go = "instances" },
        { de = "Instanzen: Eine Quest, die mehrere Flügel braucht, nennt die anderen Flügel, ein Klick wechselt dorthin.", en = "Instances: A quest that needs several wings names the other wings, and one click switches there.", go = "instances" },
        { de = "Quests: Titel, Ziele und viele Beschreibungen erscheinen im deutschen Spiel auf Deutsch.", en = "Quests: Titles, objectives and many descriptions appear in German in the German game.", go = "instances" },
      },
      changed = {
        { de = "Instanzen: Die Quest-Liste zeigt nur echte Dungeon- und Schlachtzug-Quests, Vorquests stehen im Fenster der Questreihe.", en = "Instances: The quest list shows only real dungeon and raid quests, and prequests are in the quest chain window.", go = "instances" },
        { de = "Instanzen: Gold, Erfahrung und Gegenstände der Belohnungen stimmen mit dem Spiel überein.", en = "Instances: Gold, experience and item rewards match the game.", go = "instances" },
        { de = "Instanzen: Die Quests in Düsterbruch und der Schwarzfelsspitze stehen beim richtigen Flügel.", en = "Instances: The quests in Dire Maul and Blackrock Spire are listed under the right wing.", go = "instances" },
        { de = "Instanzen-Seite: Zurück führt immer zur Übersicht, Zurücksetzen steht neben \"Alle Instanzen\", die Detailseite kommt ohne Einleitung aus und der Stufenfilter ist klarer.", en = "Instances page: Back always leads to the overview, reset sits beside \"All instances\", the detail page has no intro, and the level filter is clearer.", go = "instances" },
      },
    },
    {
      version = "0.7.5",
      date = "2026-11-13",
      highlights = {
        { head = { de = "Weiterleiten im Teilen-Fenster", en = "Forwarding in the Share window" }, text = { de = "Eine Chatzeile weiterleiten öffnet das bekannte Teilen-Fenster und sendet erst nach \"Senden\".", en = "Forwarding a chat line opens the familiar Share window and sends only after \"Send\"." }, go = "settings:foreverchat.options" },
      },
      added = {
        { de = "Forever Chat: Neue Option \"Chat bleibt bei Esc offen\", standardmäßig an: Esc verlässt das Eingabefeld und schließt offene Felder, das Fenster bleibt stehen.", en = "Forever Chat: new option \"Keep chat open on Esc\", on by default: Esc leaves the input box and closes open panels, and the window stays.", go = "settings:foreverchat.options" },
      },
      changed = {
        { de = "Forever Chat: Weiterleiten öffnet das gemeinsame Teilen-Fenster mit dem Titel \"Weiterleiten\", die Nachricht geht erst nach dem Klick auf \"Senden\" hinaus.", en = "Forever Chat: forwarding opens the shared Share window titled \"Forward\", and the message is sent only after you click \"Send\".", go = "settings:foreverchat.options" },
        { de = "Forever Chat: Beim Flüstern gibst du Vorname und Nachname ein, ein Realm ist nicht nötig.", en = "Forever Chat: for a whisper you enter first and last name, and no realm is needed.", go = "settings:foreverchat.options" },
        { de = "Forever Chat: Beim Weiterleiten steht der ursprüngliche Absender immer als Kopfzeile vor dem Text, die Option dafür entfällt.", en = "Forever Chat: when forwarding, the original writer always stands in a header line before the text, and the option for it is gone.", go = "settings:foreverchat.options" },
      },
      fixed = {
        { de = "Forever Chat: Die unterste Nachricht im Chatfenster ist jetzt immer ganz zu sehen, auch bei größerer Schrift und mit oder ohne Byte-Zähler.", en = "Forever Chat: the bottom message in the chat window is now always fully visible, also with a larger font and with or without the byte counter.", go = "settings:foreverchat.options" },
      },
    },
    {
      version = "0.7.4",
      date = "2026-11-13",
      highlights = {
        { head = { de = "Sammelstellen-Effekte", en = "Gathering spot effects" }, text = { de = "Jede Art Sammelstelle bekommt einen eigenen Effekt mit Stil, Farbe, Größe und Höhe.", en = "Every kind of gathering spot gets its own effect with style, color, size and height." }, go = "settings:gathering.sparkles.kinds" },
        { head = { de = "Eigenes Effekt-Fenster", en = "Own effects window" }, text = { de = "Eine Galerie mit Live-Vorschau zeigt alle Stile, du wählst einen per Klick.", en = "A gallery with live previews shows all styles, and you pick one with a click." }, go = "settings:gathering.sparkles.kinds" },
        { head = { de = "Farm-HUD nach deinem Geschmack", en = "Farm HUD your way" }, text = { de = "Rahmen und Kompass haben eigene Farben, Symbole anderer Addons verschwinden.", en = "Frame and compass have their own colors, and icons of other add-ons disappear." }, go = "settings:farmhud.main" },
      },
      added = {
        { de = "Sammelstellen: Kräuter, Erze, Truhen, Questobjekte, sonstige Objekte, Angelschwimmer und abbalgbare Kreaturen haben je einen Schalter, Stil, Farbe, Größe, Höhe, Anzahl und Streuung.", en = "Gathering spots: herbs, ore, chests, quest objects, other objects, fishing bobbers and skinnable creatures each have a switch, style, color, size, height, count and spread.", go = "settings:gathering.sparkles.kinds" },
        { de = "Sammelstellen-Effekte: Ein eigenes Fenster mit Stilgalerie und Live-Vorschau, geöffnet über den Knopf in den Einstellungen oder mit /fg sammelstellen und einer Art.", en = "Gathering spot effects: a window of its own with a style gallery and live previews, opened with the button in the settings or with /fg sammelstellen and a kind.", go = "settings:gathering.sparkles.kinds" },
        { de = "Sammelstellen: Viele neue Stile, zum Beispiel Glitzern, Lichtstrahl, Glühwürmchen und Schwebestaub.", en = "Gathering spots: many new styles, for example glitter, light beam, fireflies and floating dust.", go = "settings:gathering.sparkles.kinds" },
        { de = "Sammelstellen: Beim Sammeln läuft ein Abschlusseffekt, und die Stelle blitzt auf, sobald du in Reichweite kommst.", en = "Gathering spots: an ending effect plays when you gather, and the spot flashes as soon as you come within range.", go = "settings:gathering.sparkles.general" },
        { de = "Farm-HUD: Rahmen und Kompass lassen sich über die Farbauswahl des Spiels einfärben, der Rahmen hat eine einstellbare Dicke.", en = "Farm HUD: frame and compass can be colored with the game's color picker, and the frame has an adjustable thickness.", go = "settings:farmhud.main" },
        { de = "Farm-HUD: Symbole anderer Addons an der Minimap werden ausgeblendet, solange das HUD läuft, auf Wunsch abschaltbar.", en = "Farm HUD: icons of other add-ons on the minimap are hidden while the HUD is on, and you can switch this off.", go = "settings:farmhud.main" },
        { de = "Farm-HUD: Vier neue Tastenbelegungen für Zoom näher und weiter sowie Größe größer und kleiner.", en = "Farm HUD: four new key bindings for zooming in and out and for making it bigger and smaller.", go = "settings:farmhud.main" },
        { de = "Farm-HUD: Die Drehung der Karte lässt sich wählen (Blickrichtung oben oder Norden oben), und das HUD bleibt nach einem Neuladen an.", en = "Farm HUD: you can choose how the map turns (heading up or north up), and the HUD stays on after a reload.", go = "settings:farmhud.main" },
      },
      changed = {
        { de = "Sammelstellen: Die allgemeinen Optionen sind in Karten gruppiert (Sichtbarkeit, Unterwegs, Beim Sammeln, Filter, Reichweite).", en = "Gathering spots: the general options are grouped into cards (visibility, on the move, when gathering, filters, range).", go = "settings:gathering.sparkles.general" },
        { de = "Sammelstellen: Die Reichweite lässt sich wieder von 10 bis 60 Yards einstellen, der Standard ist 30.", en = "Gathering spots: the range can be set from 10 to 60 yards again, and the default is 30.", go = "settings:gathering.sparkles.general" },
        { de = "Sammelstellen: Gespeicherte alte Stile werden automatisch übernommen, Schmetterlinge werden zum Beispiel zu Blütenblättern.", en = "Gathering spots: saved old styles are migrated automatically, for example butterflies become petals.", go = "settings:gathering.sparkles.kinds" },
        { de = "Sammelstellen: Der experimentelle Stil \"Originalmodell\" entfällt, gespeicherte Einstellungen nutzen dann Partikel.", en = "Gathering spots: the experimental \"original model\" style is gone, and saved settings use particles instead.", go = "settings:gathering.sparkles.kinds" },
      },
      fixed = {
        { de = "Sammelstellen: Eine Sammelstelle außerhalb der Reichweite gilt nicht mehr fälschlich als gesperrt.", en = "Gathering spots: a gathering spot out of range no longer counts as locked by mistake.", go = "settings:gathering.sparkles.general" },
        { de = "Farm-HUD: Die runden Minimap-Knöpfe wandern nicht mehr in die Bildschirmmitte, solange das HUD läuft.", en = "Farm HUD: the round minimap buttons no longer move to the middle of the screen while the HUD is on.", go = "settings:farmhud.main" },
        { de = "Einstellungen: Die Markierung beim Sprung zu einer Einstellung erscheint nicht mehr über Kopfzeile und Minimap.", en = "Settings: the mark after jumping to a setting no longer shows over the header and the minimap." },
      },
    },
    {
      version = "0.7.3",
      date = "2026-11-12",
      highlights = {
      },
      changed = {
        { de = "Angeln: Die Pause vor dem Neuwurf steht jetzt auf 0,3 Sekunden, eine gespeicherte Pause von 1,0 Sekunden wird einmalig angepasst.", en = "Fishing: the pause before a recast now defaults to 0.3 seconds, a saved pause of 1.0 second is adjusted once.", go = "settings:fishing.cast" },
        { de = "Angeln: Die Texte der Einstellungen sind neu geschrieben und sagen klar, dass jeder Wurf einen echten Tastendruck braucht.", en = "Fishing: the settings texts are rewritten and say clearly that every cast needs a real key press.", go = "settings:fishing.cast" },
      },
      fixed = {
        { de = "Angeln: Ein zweiter schneller Druck oder Klick stört das Einholen und Looten nicht mehr und wirft nicht versehentlich neu aus.", en = "Fishing: a second quick press or click no longer disturbs reeling in and looting and does not cast again by mistake.", go = "settings:fishing.cast" },
        { de = "Angeln: Ein Doppelklick zählt nur bei kurzen Klicks auf der Spielwelt, langes Halten und Ziehen werden ignoriert.", en = "Fishing: a double click only counts for short clicks on the game world, long holds and drags are ignored.", go = "settings:fishing.cast" },
      },
    },
    {
      version = "0.7.2",
      date = "2026-11-12",
      highlights = {
      },
      fixed = {
        { de = "Schlafsack: Die Leiste startet auch im Sack eines anderen Spielers sofort beim Hinlegen.", en = "Sleeping bag: the bar also starts at once in another player's bag.", go = "settings:sleepbag.main" },
        { de = "Schlafsack: Legst du dich nach dem Aufstehen wieder in einen Sack, startet die Leiste sofort, Gasthäuser und Städte lösen sie nicht aus.", en = "Sleeping bag: lying down again in a bag starts the bar at once, inns and cities do not trigger it.", go = "settings:sleepbag.main" },
      },
    },
    {
      version = "0.7.1",
      date = "2026-11-12",
      highlights = {
      },
      fixed = {
        { de = "Tooltips: Tooltips liegen im Einrichtungsfenster und anderen Fenstern über dem Fensterrahmen.", en = "Tooltips: tooltips sit above the frame in the setup window and other windows." },
      },
    },
    {
      version = "0.7.0",
      date = "2026-11-11",
      highlights = {
        { head = { de = "Chat-Name", en = "Chat name" }, text = { de = "Auf Wunsch steht dein Name vor deinen Nachrichten, mit Klammern, Profil und Klassenfarbe.", en = "Your name can stand in front of your messages, with brackets, a profile and class color." }, go = "settings:chatname.main" },
        { head = { de = "Angeln mit Hilfe und Journal", en = "Fishing with help and a journal" }, text = { de = "Eine Taste wirft aus und holt ein, das Journal zeigt jeden Fang und jeden Angelplatz mit Chancen.", en = "One key casts and reels in, and the journal shows every catch and fishing place with its chances." }, go = "settings:fishing.cast" },
        { head = { de = "Instanzen als Kartenraster", en = "Instances as a card grid" }, text = { de = "Jede Instanz hat ihr Ladebild, dazu Beute nach Boss, Quest-Tafel mit Text und Dungeonkarten.", en = "Every instance has its loading screen, plus loot by boss, quest panel with text and dungeon maps." }, go = "instances" },
        { head = { de = "Einstellungen mit Suche", en = "Settings with search" }, text = { de = "43 Reiter in acht Gruppen, Suche nach einzelnen Einstellungen und ein neu gebauter Einrichtungsassistent.", en = "43 tabs in eight groups, a search for single settings and a rebuilt setup wizard." }, go = "settings" },
      },
      added = {
        { de = "Forever Chat: Zeilen lassen sich kopieren, weiterleiten und beantworten, Links sind klickbar.", en = "Forever Chat: lines can be copied, forwarded and replied to, and links are clickable.", go = "settings:foreverchat" },
        { de = "Chat-Name: Auf Wunsch steht dein Name vor deinen Nachrichten, mit Klammern, Profil und Klassenfarbe.", en = "Chat name: optionally put your own name in front of your messages, with brackets, profile and class color.", go = "settings:chatname.main" },
        { de = "Angelhilfe: Eine Taste wirft aus und holt ein, auf Wunsch mit Autoplündern und lauterem Ton.", en = "Fishing helper: one key casts and reels in, optionally with auto loot and louder sound.", go = "settings:fishing.cast" },
        { de = "Fangjournal: \"Meine Fänge\" zeigt jeden Fisch mit Fängen, Fundorten und Rezepten.", en = "Catch journal: \"My catches\" shows every fish with catches, locations and recipes.", go = "settings:fishing.journal" },
        { de = "Angelplätze: Ein Fenster nennt Gebiete, Mindest-Skill und Fangchance pro Wurf.", en = "Fishing places: a window lists areas, minimum skill and catch chance per cast.", go = "settings:fishing" },
        { de = "Instanzen: Das Raster zeigt Ladebilder, startet nach Stufe sortiert und hat eine gemeinsame Fraktionswahl.", en = "Instances: the grid shows loading screens, starts sorted by level and shares one faction choice.", go = "instances" },
        { de = "Instanzen: Der Reiter Items zeigt Beute nach Boss mit Droprate, Quests zeigen Text und Startort.", en = "Instances: the Items tab lists loot by boss with drop rate, and quests show text and where they start.", go = "instances" },
        { de = "Dungeonkarten: Zoom, Eingang und Legende, zwei weitere Instanzen haben jetzt eine Karte.", en = "Dungeon maps: zoom, entrance and a legend, and two more instances now have a map.", go = "instances" },
        { de = "Sammelpunkte: Truhen, Muscheln, Fischschwärme und Wrackteile haben einen eigenen Schalter.", en = "Gathering spots: chests, clams, fish schools and wreckage have a switch of their own.", go = "settings:gathering.pins" },
        { de = "Händler: Eine neue Seite findet Händler mit Suche, Filtern und Wegpunkt.", en = "Vendors: a new page finds vendors with search, filters and waypoint.", go = "vendors" },
        { de = "Suche: Das Suchfeld im Fensterkopf springt zu Menüpunkten, Reitern und einzelnen Einstellungen.", en = "Search: the field in the window header jumps to menu pages, tabs and single settings.", go = "search" },
        { de = "Einrichtung: Im Schritt \"Menü-Bereiche\" blendest du Bereiche und Seiten mit ihrem Symbol ein und aus.", en = "Setup: in the step \"Menu areas\" you show and hide areas and pages, each with its icon.", go = "settings:setup.wizard" },
        { de = "Schlafsack: Eine Leiste zeigt \"Gut erholt\" nur beim Liegen, ein X blendet sie aus. Standard aus.", en = "Sleeping bag: a bar shows the Well Rested stacks only while you lie, and an X hides it. Off by default.", go = "settings:sleepbag.main" },
        { de = "Berufstracker: Die Einkaufsliste hat einen Schließen-Knopf.", en = "Profession tracker: the shopping list has a close button.", go = "settings:professions.shopping" },
      },
      changed = {
        { de = "Einstellungen: Aus elf Reitern werden 43 in acht Gruppen, lange Karten klappen den Rest zu.", en = "Settings: the eleven tabs become 43 in eight groups, and long cards fold away the rest.", go = "settings" },
        { de = "Einrichtung: Der Assistent fragt nach Features statt nach Einzelschaltern.", en = "Setup: the wizard asks about features instead of single switches.", go = "settings:setup.wizard" },
        { de = "Fenster: Esc schließt alle Fenster des Addons, das zuletzt geöffnete zuerst.", en = "Windows: Esc closes every add-on window, the newest first." },
        { de = "Fensterstil: Neuinstallationen starten mit \"WoW Forever\", bestehende behalten ihre Wahl.", en = "Window style: fresh installs start with \"WoW Forever\", and existing installs keep their choice.", go = "settings:notes.main" },
        { de = "Weltkarte: Ein Klick auf einen Zonenübergang zeigt das Gebiet im Kartenfenster.", en = "World map: a click on a zone transition shows the area in the map window.", go = "map" },
        { de = "Raids: Barrow Deeps, Hyjal Summit und Onyxia's Lair sind Raids der Stufe 60 mit Datum 9. Dezember 2026.", en = "Raids: Barrow Deeps, Hyjal Summit and Onyxia's Lair are level 60 raids, dated December 9, 2026.", go = "instances" },
        { de = "Daten: Spielbuild 1.60.1.70888, Rezepte und Zauber der Saison der Entdeckungen sind entfernt.", en = "Data: game build 1.60.1.70888, and Season of Discovery recipes and spells are removed." },
        { de = "Erze und Kräuter: Etwa 1.900 Fundorte mehr, erstmals auch in Shen'dralas.", en = "Ores and herbs: about 1,900 more spots, for the first time also in Shen'dralas.", go = "gathering" },
      },
      fixed = {
        { de = "Schlafsack: Die Leiste erscheint nur beim Liegen, nicht mehr im Stehen.", en = "Sleeping bag: the bar shows only while you lie, no longer while you stand.", go = "settings:sleepbag.main" },
        { de = "Angelhilfe: Fische erscheinen mit Namen statt als Nummer.", en = "Fishing helper: fish show with their name instead of a number.", go = "settings:fishing.cast" },
        { de = "Instanzen: Gegenstände zeigen ihren Namen statt der Nummer.", en = "Instances: items show their name instead of the number.", go = "instances" },
        { de = "Tastatur: Enter und Leertaste wirken nur nach Tastaturbedienung eines Fensters.", en = "Keyboard: Enter and Space only act after you used the keyboard in a window." },
        { de = "Einstellungen: Escape verwirft die Eingabe in einem Textfeld.", en = "Settings: Escape discards the input in a text field.", go = "settings" },
        { de = "Fangjournal: Jeder Balken zeigt den echten Anteil und bleibt sichtbar.", en = "Catch journal: every bar shows its true share and stays visible.", go = "settings:fishing.journal" },
        { de = "Weltkarte: Das Panel \"Forever Guides\" liegt über dem Kartenrahmen.", en = "World map: the \"Forever Guides\" panel sits above the map frame.", go = "map" },
        { de = "Forever Chat: Gesperrte Nachrichten bleiben als Entwurf im Chatfeld.", en = "Forever Chat: blocked messages stay as a draft in the chat box.", go = "settings:foreverchat" },
      },
    },
  },
}
