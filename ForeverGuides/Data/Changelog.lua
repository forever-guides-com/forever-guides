-- Generated from the changelog of the repo, do not edit.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.Changelog = {
  v = 1,
  versions = {
    {
      version = "1.1.0",
      date = "2026-11-22",
      highlights = {
        { head = { de = "Menü anpassen", en = "Customize menu" }, text = { de = "Ein eigenes Fenster mit Vorschau, darin Farbe, Name, Reihenfolge und Sichtbarkeit jedes Bereichs.", en = "A window of its own with a preview, for color, name, order and visibility of every section." }, go = "settings:menu.main" },
        { head = { de = "Aufgeräumtes Menü", en = "Tidier menu" }, text = { de = "Jeder Bereich liegt in einem eigenen Kasten, neu installiert ist nur die Übersicht offen.", en = "Every section sits in a box of its own, a fresh install opens only the overview." } },
        { head = { de = "Reittiere", en = "Mounts" }, text = { de = "Größeres Modell, nur Liste und Details scrollen.", en = "Larger model, only the list and the details scroll." }, go = "mounts" },
      },
      added = {
        { de = "Menü: Jeder Bereich liegt in einem Kasten, der sich einfärben lässt. Zu helle Farben werden abgedunkelt, damit die Schrift lesbar bleibt.", en = "Menu: Every section sits in a box that can be tinted. Colors that are too bright are darkened so the text stays readable." },
        { de = "Menü: Das neue Fenster \"Menü anpassen\" zeigt das ganze Menü als Vorschau und stellt Farbe, Name, Reihenfolge und Sichtbarkeit ein, auch je Charakter. Es öffnet sich über die Stifte im Menü.", en = "Menu: The new \"Customize menu\" window previews the whole menu and sets color, name, order and visibility, also per character. It opens from the pencils in the menu.", go = "settings:menu.main" },
      },
      changed = {
        { de = "Menü: Der Bearbeitungsmodus direkt in der Seitenleiste entfällt, alles läuft über das Fenster \"Menü anpassen\".", en = "Menu: The edit mode inside the sidebar is gone, everything runs through the \"Customize menu\" window.", go = "settings:menu.main" },
        { de = "Menü: Bei einer Neuinstallation sind alle Bereiche außer der Übersicht zugeklappt. Wer das Addon schon nutzt, wird einmal gefragt, danach merkt sich das Addon, was du auf- und zuklappst.", en = "Menu: A fresh install starts with every section except the overview collapsed. Existing users are asked once, afterwards the addon remembers what you open and close." },
        { de = "Reittiere: Die Seite scrollt nicht mehr als Ganzes, nur Liste und Details scrollen. Das Modell ist größer und passt sich dem Fenster an, das Häkchen \"Ich habe dieses Reittier\" steht direkt unter dem Kopf.", en = "Mounts: The page no longer scrolls as a whole, only the list and the details scroll. The model is larger and fits the window, and the \"I have this mount\" checkbox sits right below the header.", go = "mounts" },
      },
      fixed = {
        { de = "Reittiere: Ohne eigenes Modell steht \"Keine Vorschau verfügbar\" statt des Modells eines anderen Reittiers, der Vorschau-Knopf entfällt dann.", en = "Mounts: Without a model of its own the page says \"No preview available\" instead of showing another mount's model, and the preview button is hidden.", go = "mounts" },
      },
    },
    {
      version = "1.0.1",
      date = "2026-11-22",
      highlights = {
        { head = { de = "Neuerungsfenster", en = "News window" }, text = { de = "Erscheint jetzt nach jedem Update zuverlässig, auch nach einer Neuinstallation.", en = "Now shows reliably after every update, also after a fresh install." } },
      },
      fixed = {
        { de = "Neuerungen: Das Fenster erscheint nach dem Update auf 1.0 und nach einer Neuinstallation zuverlässig, bis du es abschaltest.", en = "News: The window now shows reliably after the update to 1.0 and after a fresh install, until you switch it off." },
      },
    },
    {
      version = "1.0.0",
      date = "2026-11-22",
      important = true,
      highlights = {
        { head = { de = "Neues Design", en = "New design" }, text = { de = "Karten, Listen und Details auf allen Seiten, dazu ein Teilen-Knopf mit Kanalwahl.", en = "Cards, lists and details on every page, plus a share button with channel choice." } },
        { head = { de = "Laufwege", en = "Walking routes" }, text = { de = "Die Route folgt dem echten Gelände mit Brücken und Höhlen und erscheint auf Karte und Minimap.", en = "The route follows the real terrain with bridges and caves and shows on the map and minimap." } },
        { head = { de = "Instanzen", en = "Instances" }, text = { de = "Dungeonkarte mit Routen und Raumnamen, jede Dungeonquest mit Ruf, Hinweisen und Vorquests.", en = "Dungeon map with routes and room names, every dungeon quest with reputation, notes and prequests." } },
        { head = { de = "Im Chat teilen", en = "Share in chat" }, text = { de = "Quests und Seiten als anklickbare Links, andere öffnen sie mit einem Klick.", en = "Quests and pages as clickable links that others open with one click." } },
      },
      added = {
        { de = "Neues Design: Seiten und Listen zeigen Karten mit Symbolen, Stufen und Status.", en = "New design: Pages and lists show cards with icons, levels and status." },
        { de = "Neuerungen: Nach einem Update zeigt ein Fenster die Neuerungen der neuen Version. Darunter zeigt es alles, was Forever Guides kann, mit /fg news jederzeit.", en = "News: After an update a window shows the news of the new version and below everything Forever Guides can do, any time with /fg news." },
        { de = "Angeln: Das Fangjournal ist eine eigene Seite im Menü, das kleine Fenster öffnet sich weiter von dort.", en = "Fishing: The catch journal is its own page in the menu, the small window still opens from there.", go = "settings:fishing.cast" },
        { de = "Teilen: Fast jede Seite hat einen Teilen-Knopf, auch die Einstellungen. Du sendest einen Link oder den Code FG-... in den Chat, andere öffnen ihn mit einem Klick oder mit /fg open.", en = "Sharing: Almost every page has a share button, including the settings. Send a link or an FG-... code to chat, and others open it with one click or with /fg open.", go = "search" },
        { de = "Dungeonkarte: Routen durch den Dungeon mit Etappen, Raumnamen als Beschriftung, dazu Karten für die fünf neuen Dungeons, die Obere Schwarzfelsspitze und die Schattenseite von Dalaran.", en = "Dungeon map: Routes through the dungeon with legs, room names as labels, plus maps for the five new dungeons, Upper Blackrock Spire and the Dalaran Underbelly.", go = "instances" },
        { de = "Ausrüstungsplaner: Quests in der Welt und Weltdrops erscheinen als Quellen, dazu deutlich mehr Questbelohnungen. Die Liste zeigt nur, was zu Stufe, Klasse und Fraktion passt, und das Charaktermodell steht still.", en = "Gear planner: World quests and world drops show up as sources, plus far more quest rewards. The list only shows what fits your level, class and faction, and the character model stands still." },
        { de = "Instanzquests: Jede Dungeonquest hat Ruf, Hinweise und Vorquests, den Abgabeort mit Karten- und Wegpunkt-Knopf und die Orte der Questziele mit Wegpunkt.", en = "Instance quests: Every dungeon quest shows reputation, notes and prequests, the hand-in place with map and waypoint buttons and the places of the quest objectives with a waypoint.", go = "instances" },
        { de = "Instanzquests: Rund 200 weitere Quests und Kettenglieder der 5er-Dungeons, 24 davon im Spiel bestätigt, dazu fehlende Geberorte, Belohnungen und Vorquests.", en = "Instance quests: About 200 more quests and chain links of the 5-man dungeons, 24 of them confirmed in game, plus missing giver places, rewards and prequests." },
        { de = "Instanzen: Mehr Beute bei Bossen und Instanzen (unbestätigte Einträge sind markiert), gemessene Drop-Chancen, weitere seltene Gegner und deutsche Namen für Bosse und Gegenstände.", en = "Instances: More boss and instance loot (unconfirmed entries are marked), measured drop chances, more rare enemies and German names for bosses and items." },
        { de = "Zugang: Der Reiter Zugang zeigt Schlüssel und Wege für elf Instanzen. Nur Scharlachroter Schlüssel und Skelettschlüssel sind bestätigt, alle anderen tragen den Hinweis \"nicht bestätigt\".", en = "Access: The Access tab shows keys and routes for eleven instances. Only the Scarlet Key and the Skeleton Key are confirmed, all others carry the note \"not confirmed\"." },
        { de = "Zauberbuch: Im Seitenfenster wählst du die Klasse, deren Zauber du sehen willst.", en = "Spellbook: Pick the class whose spells you want to see in the side panel." },
        { de = "Laufwege: Die Wege folgen dem echten Gelände mit Brücken, Höhlen und Stockwerken, die Daten laden je Kontinent erst bei Bedarf. Die neue Einstellung Laufweg wählt Querfeldein, Ausgewogen oder Vor allem Straßen.", en = "Walking routes: Paths follow the real terrain including bridges, caves and floors. The new setting Walking route picks cross-country, balanced or mostly roads." },
        { de = "Minimap: Der geplante Laufweg erscheint als Linie auf der Minimap (Einstellung Route auf der Minimap, standardmäßig an).", en = "Minimap: The planned walking path shows as a line on the minimap (setting Route on the minimap, on by default)." },
        { de = "Guides: Neuer Bereich in der Seitenleiste mit drei Anleitungen. Werte, die nicht bestätigt sind, sind markiert.", en = "Guides: A new area in the side bar with three guides. Values that are not confirmed are marked.", go = "lockpicking" },
        { de = "Schlossknacken: Fertigkeitsbereiche mit Zielen je Fraktion, Schließkassetten mit ihren Quellen und die Schurkenquests, Truhen lassen sich auf der Karte zeigen.", en = "Lockpicking: Skill ranges with targets per faction, lockboxes with their sources and the rogue quests, chests can be shown on the map.", go = "lockpicking" },
        { de = "Verständnis: Die Anleitung für Magier mit Stufen, Schriftrollen und Ergebnissen, dazu die 39 Bibliotheksbücher in vier Sätzen mit Status je Buch, Zähler und den Belohnungen der Bibliothek.", en = "Comprehension: The guide for mages with stages, scrolls and results, plus the 39 library books in four sets with a status per book, counts and the library rewards.", go = "comprehension" },
        { de = "Ruf: Alle Fraktionen mit deinem Stand, die besten Wege je Rufstufe, Belohnungen und Händler, dazu Filter.", en = "Reputation: All factions with your own standing, the best ways per standing, rewards and vendors, plus filters.", go = "reputation" },
        { de = "Sammeln: Je Gebiet ein Filterfenster für Erze, Kräuter, Truhen und Fischschwärme, mit Suche, Alle, Keine und Nur was ich sammeln kann.", en = "Gathering: One filter window per area for ores, herbs, chests and fishing schools, with search, select all, select none and only what I can gather.", go = "gathering" },
        { de = "Sammeln: Verschlossene Truhen haben ein eigenes Schlosssymbol, der Tooltip nennt die nötige Schlossknacken-Fertigkeit.", en = "Gathering: Locked chests have their own lock icon, the tooltip names the lockpicking skill you need.", go = "gathering" },
        { de = "Farm-HUD: Beim Überfahren eines Erz- oder Kräutersymbols erscheint sein Name, mit gehaltener Alt-Taste zeigt das Spiel seine eigenen Tooltips der verfolgten Fundorte. Die Taste ist einstellbar, die Funktion abschaltbar.", en = "Farm HUD: Hovering an ore or herb symbol shows its name, hold Alt to see the game's own tooltips for tracked nodes. The key can be changed and the feature can be switched off in the settings." },
        { de = "Weltkarte: Beim Überfahren eines Gebiets steht unter dem Gebietsnamen die Stufenspanne, nach Wunsch zeigt jedes Gebiet auf den Kontinentkarten seine Spanne in der Mitte. Die Farbe folgt deiner Stufe.", en = "World map: Hovering a zone shows its level range under the zone name, optionally every zone on the continent maps shows its range in the middle. The color follows your level." },
        { de = "Berufe: 79 Händler und 56 Berufslehrer mehr, darunter Alteracgebirge, die Insel Zephras, Flusslande und die Anfängergebiete.", en = "Professions: 79 more vendors and 56 more profession trainers, including Alterac Mountains, Zephras Isle, Riverglades and the starter zones." },
        { de = "Rezepte: Die Detailansicht nennt Werkzeug, Werkbank, Spezialisierung und Abklingzeit eines Rezepts, fehlende Lernstufen und zwei Verzauberungen sind ergänzt.", en = "Recipes: The detail view names the tools, station, specialization and cooldown of a recipe, missing learn levels and two enchants are added." },
        { de = "Charaktere: Stufe, EP und Erholt-Bonus je Charakter auf der Startseite und in der Übersicht, geschätzt aus Zeit und Ort des Ausloggens, mit Hinweis wenn ein anderer Charakter voll erholt ist.", en = "Characters: Level, XP and rested XP per character on the start page and in the overview, estimated from the logout time and place, with a notice when another character is fully rested." },
        { de = "Gegenstände: Hover zeigt den Tooltip, Umschalt+Klick verlinkt im Chat, Strg+Klick öffnet die Vorschau. Ein Vorschaufenster zeigt Gegenstände, ganze Sets und Kreaturen als 3D-Modell.", en = "Items: Hover shows the item tooltip, Shift+click links it in chat, Ctrl+click previews it. A preview window shows items, whole sets and creatures on a 3D model." },
        { de = "Auktionshaus-Preise: Die neue Einstellung Preise anderer Auktionshäuser zeigen listet im Item-Tooltip auch die neutralen Häuser und das der anderen Fraktion, kurz und mit dem Alter des Scans.", en = "Auction house prices: The new setting Show prices of other auction houses also lists the neutral houses and the other faction's house in the item tooltip, short and with the age of the scan." },
        { de = "Minimap und Farm-HUD: Fundorte erscheinen dezent als kleiner, blasser Ring in der Farbe des Items, ein Fundort mit mehreren möglichen Items trägt einen Punkt. Der Stil \"Item-Symbol\" bringt das alte Aussehen zurück.", en = "Minimap and farm HUD: Spots show subtly as a small faint ring in the item color, a spot with several possible items carries a dot. The \"Item symbol\" style brings the old look back." },
        { de = "Karte: Deine Position mit Gilde, Freunden und Battle.net-Freunden teilen, je Gruppe wählst du Sehen und Senden.", en = "Map: Share your position with guild, friends and Battle.net friends, pick See and Send per group." },
      },
      changed = {
        { de = "Oberfläche: Beute, Ruf, Legendäre, Skillungen und die Wegpunkte nutzen jetzt Zeilen mit Rahmen und Symbolen wie die übrigen Seiten.", en = "Interface: Loot, reputation, legendaries, talent builds and waypoints now use framed rows with icons like the other pages.", go = "reputation" },
        { de = "Karte und Route: Eine Route für Seite und Weltkarte. Ziel suchen, Stopps ergänzen, Route berechnen und starten, dazu \"Ruhestein nutzen\" und \"Zurück zum Start\". Im Kampf ändert sich nichts, solange \"Im Kampf sperren\" aus ist.", en = "Map and route: One route for the page and the world map. Search a goal, add stops, calculate and start the route, plus \"Use hearthstone\" and \"Back to start\"." },
        { de = "Karte und Route: Die Routenleiste sitzt als Griff am rechten Rand der Weltkarte mit Karte und Etappenliste. \"Tauschen\" und \"Wegpunkt anfügen\" stehen in der Routenkarte, der Haken \"Ab meiner Position\" nutzt deinen Standort.", en = "Map and route: The route drawer sits at the right edge of the world map with the card and the leg list. \"Swap\" and \"Add waypoint\" are in the route card, \"Start at my position\" uses where you stand." },
        { de = "Aussehen: Standard ist der Fensterstil WoW Forever (wer noch Flach gespeichert hat, wechselt einmalig mit Hinweis, danach bleibt jede Wahl). Er nutzt die Spielgrafik für Karten, Knöpfe, Reiter, Suchfeld und Auswahllisten und die Spielschrift im Titel.", en = "Look: WoW Forever is the default window style (a stored Flat switches once with a notice). It uses the game's own art for cards, buttons, tabs, search box and dropdowns and the game font in the title." },
        { de = "Aussehen: Überschriften in Spielgold, warme Textfarben, ein gemeinsamer Hover und eine gemeinsame Auswahl, Reiter mit Hover und Fokus, dunkle Auswahlfelder mit gut lesbarem Text, Deckkraft und Zoom hinter dem Knopf Ansicht.", en = "Look: Headings in game gold, warm text colors, one shared hover and selection, tabs with hover and focus, dark select fields with readable text, opacity and zoom behind the View button." },
        { de = "Seitenleiste: Ohne harte Linien unter den Gruppen, mit gezeichneten Pfeilen, einheitlichem Hover und Fokus und einer Breite, die den Namen folgt. Strg+K öffnet die Suche.", en = "Side bar: No hard lines under the groups, drawn chevrons, one hover and focus look and a width that follows the names. Ctrl+K opens the search." },
        { de = "Händler und Talente: Die Händlerliste zeigt rechts das Angebot des gewählten Händlers, jeder Talentbaum hat seinen Hintergrund, Items & BiS ist vorerst ausgeblendet.", en = "Vendors and talents: The vendor list shows the chosen vendor's offer on the right, each talent tree has its background, Items & BiS is hidden for now." },
        { de = "Einkaufslisten: Liste, Haken, Beruf, Zielskill und Bestand gelten pro Charakter, der erste Charakter übernimmt die alten Werte.", en = "Shopping lists: list, ticks, profession, target skill and stock are per character, the first character takes the old ones." },
        { de = "Filter: Eine Filterzeile je Listenseite mit Zähler der aktiven Filter und Knopf \"Filter zurücksetzen\". Leere Listen zeigen ein Symbol und bieten den Knopf ebenfalls an.", en = "Filters: One filter row per list page with a count of active filters and a Reset filters button. Empty lists show an icon and offer the button too." },
        { de = "Seitenkopf: Untertitel unter dem Titel, der Hilfetext sitzt als Leiste unter dem Kopf, beim ersten Besuch offen, mit \"Hilfe ausblenden\" je Seite dauerhaft zugeklappt und über das \"?\" im Kopf wieder da.", en = "Page header: A subtitle under the title, the help text as a strip below it that is open on the first visit, collapses per page with Hide help and comes back with the ? in the header." },
        { de = "Oberfläche: Dichte Normal oder Kompakt in den Einstellungen, Klassen und Berufsroute als Kartenraster, Ruf mit Fortschrittsbalken, Filter und Reiter je Seite gemerkt, ein Starthinweis auf Strg+K.", en = "Interface: Density Normal or Compact in the settings, classes and profession route as card grid, reputation with progress bars, filters and tabs remembered per page, a first-start hint for Ctrl+K." },
        { de = "Schlossknacken und Verständnis: Oben dein Skill mit Balken und dem nächsten Schritt samt Wegpunkt, darunter einklappbare Abschnitte mit Fortschritt und Status je Zeile, der Abschnitt für deinen Skill ist offen.", en = "Lockpicking and Comprehension: Your skill with a bar and the next step with its waypoint at the top, collapsible sections below with progress and state per row, the section for your skill is open." },
        { de = "Erze und Kräuter: Jedes Gebiet ist eine Karte, bei breitem Fenster stehen bis zu drei nebeneinander, die Filter liegen im Fenster des Gebiets. Die Seite zeigt die Gebiete ohne langes Scrollen.", en = "Ores and herbs: Every area is a card, a wide window shows up to three side by side, the filters sit in the window of the area. The page shows the areas without long scrolling.", go = "gathering" },
        { de = "Erze und Kräuter: Alle Fundorte neu abgeglichen, in Mulgore, Sturmwind, den Östlichen Pestländern und im Rotkammgebirge liegen sie jetzt an den richtigen Orten, Berg Hyjal ist neu.", en = "Ores and herbs: All spots checked again, in Mulgore, Stormwind, Eastern Plaguelands and Redridge they now sit at the right places, Mount Hyjal is new.", go = "gathering" },
        { de = "Erze und Kräuter: Ein Spawnpunkt mit mehreren möglichen Erzen oder Kräutern zeigt alle Möglichkeiten. Der Tooltip nennt sie alle, ein farbiger Rand und eine Zahl markieren den Punkt, abschaltbar in den Einstellungen.", en = "Ores and herbs: A spawn point with several possible ores or herbs shows all possibilities. The tooltip lists them all, a colored rim and a number mark the spot, switchable in the settings.", go = "gathering" },
        { de = "Orte: Händler, Berufslehrer, Klassenlehrer und Dungeon-Eingänge in Mulgore, Sturmwind, den Östlichen Pestländern und im Rotkammgebirge zeigen auf die richtigen Orte.", en = "Places: Vendors, profession trainers, class trainers and dungeon entrances in Mulgore, Stormwind, Eastern Plaguelands and Redridge now point to the right places." },
        { de = "Farm-HUD: Es öffnet und schließt im Kampf auf den eigenen Schalter des Spielers. Auf dem HUD zeigt der Tooltip Item, alle Möglichkeiten und die Entfernung, das HUD bleibt durchklickbar.", en = "Farm HUD: It opens and closes in combat on the player's own switch. On the HUD the tooltip shows the item, all possibilities and the distance, and the HUD stays click-through." },
        { de = "Karte: Die Pfeile an den Zonengrenzen wechseln den Kartenbereich auch im Kampf, solange die Karte offen und nicht geschützt ist.", en = "Map: The zone border arrows switch the map area in combat too, as long as the map is open and not protected." },
        { de = "Fenster: Die Fenster des Spiels lassen sich auch im Kampf ziehen, ein im Kampf zum ersten Mal geöffnetes Fenster ebenso, die Weltkarte solange sie nicht geschützt ist. Position und Zoom warten weiter bis zum Kampfende.", en = "Windows: The game windows can be dragged in combat too, including the world map as long as it is not protected. Position and zoom still wait for the end of the fight." },
        { de = "Teilen: Chat-Links stehen lesbar als [Addon Forever Guides: ...] ohne Code. Der Klick auf Teilen sendet diese Zeile mit ihren Daten, empfangene Zeilen werden zu Links, beides lässt sich abschalten. Say und Co. senden den Code.", en = "Sharing: Chat links read as [Addon Forever Guides: ...] without a code. Sharing sends that line with its data and received lines become links, both can be switched off. Say and similar send the code." },
        { de = "Instanzen: Stufenbereiche von 11 Dungeons nach dem Gruppenfinder des Spiels (Scharlachrotes Kloster, Düsterbruch, Untere und Obere Blackrockspitze, Maraudon, Versunkener Tempel), Berg Hyjal zeigt seine Stufen 55-60 in der Weltkarte.", en = "Instances: Level ranges of 11 dungeons from the game's group finder (Scarlet Monastery, Dire Maul, Maraudon and more), Mount Hyjal shows its levels 55-60 on the world map." },
        { de = "Auktionshaus-Preise: Preise werden je Auktionshaus gespeichert (Allianz, Horde, Gadgetzan, Beutebucht, Ewige Warte) und gelten für alle Charaktere. Tooltips, Einkaufsliste und Berufsrouten nutzen das Haus deiner Fraktion und nehmen sonst ein neutrales Haus (mit ~ markiert).", en = "Auction house prices: Prices are stored per auction house for every character. Tooltips, shopping list and profession routes use your faction's house, else a neutral house (marked ~)." },
      },
      fixed = {
        { de = "Charaktere: Bestand und Charakterdaten werden wieder gespeichert, wenn das Spiel keinen Realmnamen meldet.", en = "Characters: Inventory and character data are saved again when the game reports no realm name." },
        { de = "Besitz: Der Tooltip zeigt für den aktiven Charakter den Bestand direkt aus dem Spiel, und der Befehl /fg inventar nennt, ob Taschen und Ausrüstung zuletzt lesbar waren.", en = "Owned: The tooltip shows the active character's stock straight from the game, and the /fg inventory command says whether bags and worn items were readable at the last capture." },
        { de = "Zauberbuch: Die Lernliste neben dem Zauberbuch öffnet wieder ohne Fehler, wenn sie beim letzten Mal offen war.", en = "Spellbook: The learn list next to the spellbook opens without an error again when it was left open last time." },
        { de = "Fehlerliste: Leere Warnungen ohne Text werden nicht mehr gespeichert, und die Liste behält den vollen Ablauf.", en = "Error list: Empty warnings without text are no longer stored, and the list keeps the full trace." },
        { de = "Kartenpanel: Reiter, Kontrollkästchen und die Knöpfe Alle/Keine zeigen ihre Texte vollständig, auch mit großer Schrift. Das Panel wird bei Bedarf breiter, lange Beschriftungen laufen in die nächste Zeile.", en = "Map panel: Tabs, check boxes and the All/None buttons show their full text, also at a large font size. The panel widens when needed, long labels wrap onto the next line." },
        { de = "Teilen: Nachrichten im Chat enthalten nur noch Links, die das Spiel annimmt, sonst steht der Name in eckigen Klammern. Das Teilen einer Quest per Flüstern bricht nicht mehr ab, die Vorschau zeigt genau den gesendeten Text.", en = "Sharing: Chat messages contain only links the game accepts, otherwise the name stands in square brackets. Sharing a quest by whisper no longer fails, and the preview shows exactly the sent text." },
        { de = "Farm-HUD: Kein Ruckeln mehr mit vielen Addons, die Symbolsuche verteilt sich über mehrere Bilder.", en = "Farm HUD: No more stutter with many add-ons, the icon search is spread over several frames." },
        { de = "Minimap: Die Pins laufen beim Reiten ruhiger.", en = "Minimap: The pins run smoother while riding." },
        { de = "Kampf: Fundfenster seltener Gegner, Gildeneinladungen, Chat, Handwerkerliste, Gildenkarten-Liste, Tour, Berufs-Tracker und die Popups (Boss-Reset-Frage, Einrichtung) öffnen und schließen auch im Kampf, die Knöpfe zum Anvisieren und Einladen werden nach dem Kampf scharf, Auf Karte zeigen öffnet im Kampf die Karte des Addons.", en = "Combat: Rare find window, guild invites, chat, crafters list, tour, shopping tracker and popups open and close in combat too, the targeting and invite buttons arm after the fight." },
        { de = "Instanzen: Feste Krol'dok zeigt 5 Spieler, und einige Einträge, die es im Spiel nicht gibt, sind entfernt (ein Instanz-Gegenstand und drei Rufgruppen).", en = "Instances: Krol'dok Stronghold shows 5 players, and a few entries that do not exist in the game are removed (one dungeon item and three reputation factions)." },
        { de = "Teilen-Symbol: Es bleibt nicht mehr sichtbar, wenn die Maus die Zeile verlassen hat, und erscheint wieder beim Überfahren jeder Zeile in Seitenleiste und Rezeptliste.", en = "Share icon: It no longer stays visible after the mouse has left the row, and it shows again when hovering any row in the side bar and the recipe list." },
        { de = "Oberfläche: Das Hauptfenster frischt beim Öffnen die Menüsymbole wieder auf, Dialoge kommen nach vorn, und im Gruppenfinder-Filter verschwindet der gedrückte Zustand beim Verlassen.", en = "Interface: The main window refreshes the menu icons again when it opens, dialogs come to the front, and the pressed look in the group finder filter goes away when the pointer leaves." },
        { de = "Weltkarte: Erz- und Kräutersymbole, Marker und Routen liegen auch über der zusammengesetzten Weltkarte, behalten bei jeder Vergrößerung ihre Größe und zeigen die Gebiete der Kartenansicht.", en = "World map: Ore and herb symbols, markers and routes also lie above the stitched world map, keep their size at every zoom and show the zones of the map view." },
        { de = "Gruppensuche: Die Liste des Spiels bleibt unverändert, damit die Suche und der Eintrag nicht mehr als blockiert gemeldet werden, zwei Fehler im Chat und in Knöpfen sind behoben.", en = "Group finder: The game's list stays untouched, so searching and listing are no longer reported as blocked, and two errors in chat and buttons are fixed." },
        { de = "Besitz im Tooltip: Der Block fehlt nicht mehr, wenn ein anderes Addon den Tooltip eines Items nach dem Aufbau neu füllt.", en = "Ownership in the tooltip: The block no longer goes missing when the tooltip of an item is refilled after it was built." },
      },
    },
    {
      version = "0.10.2",
      date = "2026-11-16",
      highlights = {
      },
      fixed = {
        { de = "Instanzen & Raids: Die Tabs bleiben auch im schmalen Fenster oben, statt dass alle Bereiche untereinander stehen.", en = "Instances & Raids: The tabs stay at the top in a narrow window too, instead of every section following the other.", go = "instances" },
        { de = "Changelog: Die Liste zeigt wieder alle veröffentlichten Versionen, 0.9.0 und 0.10.0 fehlten.", en = "Changelog: The list shows every released version again, 0.9.0 and 0.10.0 were missing." },
      },
    },
    {
      version = "0.10.1",
      date = "2026-11-16",
      highlights = {
      },
      changed = {
        { de = "Stufen-Übersicht: Ränge, die ein Talent brauchen, sind markiert, der Tooltip erklärt, dass der Lehrer sie erst mit dem Talent anbietet.", en = "Level overview: Ranks that need a talent are marked, the tooltip explains that the trainer offers them once you know the talent.", go = "levels" },
      },
      fixed = {
        { de = "Stufen-Übersicht: Ränge, die es in Forever nicht mehr gibt, sind entfernt, etwa Mehrfachschuss und Skorpidstich (Jäger), Elunes Anmut (Priester), Rasende Regeneration (Druide) und Fluch der Schatten (Hexenmeister).", en = "Level overview: Ranks that no longer exist in Forever are gone, for example Multi-Shot and Scorpid Sting (Hunter), Elune's Grace (Priest), Frenzied Regeneration (Druid) and Curse of Shadow (Warlock).", go = "levels" },
      },
    },
    {
      version = "0.10.0",
      date = "2026-11-16",
      highlights = {
        { head = { de = "Alternativen in der Berufsroute", en = "Alternatives in the profession route" }, text = { de = "Material sparende Wege stehen in einem zugeklappten Bereich unter der Hauptroute.", en = "Ways that save materials sit in a collapsed area below the main route." } },
        { head = { de = "Rezeptquellen", en = "Recipe sources" }, text = { de = "Rezepte, die man nicht beim Lehrer lernt, zeigen ihre Herkunft mit Symbol, Tooltip und Filter.", en = "Recipes you do not learn at a trainer show their source with a marker, tooltip and filter." } },
      },
      added = {
        { de = "Berufsroute: Alternativen stehen in einem zugeklappten Bereich unter der Hauptroute, zum Beispiel Wege, die Material sparen. Sie kommen nicht auf die Einkaufsliste.", en = "Profession route: Alternatives sit in a collapsed area below the main route, for example ways that save materials. They do not go on the shopping list.", go = "professionroute" },
        { de = "Berufe: Rezepte, die man nicht beim Lehrer lernt, zeigen ein Symbol mit ihrer Herkunft: Händler, Gunst, Ruf, Gegnerbeute, Weltdrop, Quest, Objekt oder Dungeon.", en = "Professions: Recipes you do not learn at a trainer show a marker with their source: vendor, favor, reputation, creature drop, world drop, quest, object or dungeon.", go = "professions" },
        { de = "Berufe: Der Tooltip des Symbols nennt NPC und Ort je Fraktion, Preis, Rufstufe, Quest, Gegner mit Droprate oder den Stufenbereich eines Weltdrops.", en = "Professions: The tooltip of the marker names NPC and place per faction, the price, the needed standing, the quest, the dropping creatures with their drop rate or the level range of a world drop.", go = "professions" },
        { de = "Berufe: Ein Filter zeigt nur die Rezepte einer Herkunft.", en = "Professions: A filter shows only the recipes of one source.", go = "professions" },
      },
      changed = {
        { de = "Berufsrouten: Neue Routen für alle zwölf Berufe, jeder Schritt gegen die aktuellen Spieldaten geprüft.", en = "Profession routes: New routes for all twelve professions, every step checked against the current game data.", go = "professionroute" },
        { de = "Ingenieurskunst: Schweres Sprengpulver läuft nur noch bis 140, danach übernimmt Surrendes bronzenes Dingsda bis 150.", en = "Engineering: Heavy Blasting Powder now runs to 140 only, then Whirring Bronze Gizmo takes over to 150.", go = "professionroute" },
        { de = "Berufe: Die Muster der beiden Zentauren-Rüstmeister in Desolace zeigen Rufstufe und Preis je Händler.", en = "Professions: The patterns of the two centaur quartermasters in Desolace show standing and price for each seller.", go = "professions" },
      },
      fixed = {
        { de = "Berufe: Das ausgewählte Rezept bleibt nach einem Reload ausgewählt, wie der Beruf.", en = "Professions: The selected recipe stays selected after a reload, like the profession.", go = "professions" },
        { de = "Berufe: Preise in Items erscheinen jetzt im Tooltip des Rezepts.", en = "Professions: Prices paid in items now show in the recipe tooltip.", go = "professions" },
      },
    },
    {
      version = "0.9.0",
      date = "2026-11-15",
      highlights = {
        { head = { de = "Skillreihenfolge planen", en = "Plan your skill order" }, text = { de = "Lege im Talent-Editor fest, in welcher Reihenfolge du jeden Punkt vergibst, per Pfeil oder Ziehen.", en = "Set in the talent editor in which order you spend every point, with arrows or drag and drop." } },
        { head = { de = "Reihenfolge am Talentfenster", en = "Order at the talent window" }, text = { de = "Eine Leiste am Talentfenster zeigt den nächsten Schritt, die Zahlen stehen direkt an den Talenten.", en = "A panel at the talent window shows your next step, the numbers sit right on the talents." } },
        { head = { de = "Aktive Skillung", en = "Active build" }, text = { de = "Wähle eine Skillung als aktiv, Talentfenster und Editor richten sich dann nach ihr.", en = "Pick one build as active, the talent window and the editor then follow it." } },
        { head = { de = "Bewertete Skillungen", en = "Rated builds" }, text = { de = "Mitgeliefert werden die Skillungen der Website mit den meisten Likes, samt ihrer Reihenfolge.", en = "The add-on ships the website builds with the most likes, including their skill order." } },
      },
      added = {
        { de = "Talent-Editor: Der Kasten Skillreihenfolge zeigt jeden Punkt als Schritt mit Rang und Stufe. Pfeile, Ziehen und Umschalt+Hoch/Runter ändern die Reihenfolge.", en = "Talent editor: The skill order box shows every point as a step with rank and level. Arrows, drag and drop and Shift+Up/Down change the order.", go = "talents" },
        { de = "Talent-Editor: Schrittnummern an den Talenten auf Wunsch, der Tooltip eines Talents nennt alle seine Schritte.", en = "Talent editor: Optional step numbers on the talents, the tooltip of a talent lists all of its steps.", go = "talents" },
        { de = "Talent-Editor: \"Als neue Skillung nutzen\" speichert die Verteilung als neue Skillung und macht sie aktiv.", en = "Talent editor: \"Use as new build\" saves the distribution as a new build and makes it active.", go = "talents" },
        { de = "Skillungen: Der Knopf Nutzen macht eine Skillung aktiv, je Charakter und Talentgruppe. \"Aktive Skillung öffnen\" und \"In aktive Skillung speichern\" auf der Talente-Seite.", en = "Builds: The Use button makes a build active, per character and talent group. \"Open active build\" and \"Save to active build\" on the talents page.", go = "talents" },
        { de = "Talentfenster: Eine Leiste am rechten Rand klappt zu einem Bereich in Fensterhöhe auf, mit Fortschritt, gelernten Schritten und dem nächsten Schritt.", en = "Talent window: A bar on the right edge opens into a panel of window height with progress, learned steps and the next step.", go = "settings:talentframe.main" },
        { de = "Talentfenster: Zahlen an den Talenten zeigen den nächsten offenen Rang, \"10+\" solange weitere Ränge folgen. Ein Haken im Bereich schaltet sie an und aus.", en = "Talent window: Numbers on the talents show the next open rank, \"10+\" while more ranks follow. A checkbox in the panel turns them on and off.", go = "settings:talentframe.main" },
        { de = "Talentfenster: Ein Knopf blendet gelernte Schritte aus, beim Öffnen springt die Liste zum nächsten Schritt.", en = "Talent window: A button hides learned steps, on opening the list jumps to the next step.", go = "settings:talentframe.main" },
      },
      changed = {
        { de = "Skillungen: Mitgeliefert werden nur noch bewertete Skillungen der Website, die meisten Likes zuerst, jede mit ihrer Skillreihenfolge.", en = "Builds: Only rated website builds are shipped, most liked first, each with its skill order.", go = "talents" },
        { de = "Teilen: Links, Codes und Chat-Links tragen die Skillreihenfolge mit, ältere Codes ohne Reihenfolge bleiben gültig.", en = "Sharing: Links, codes and chat links carry the skill order, older codes without an order stay valid.", go = "talents" },
      },
      fixed = {
        { de = "Fenster: Inhalte des Addon-Fensters liegen nicht mehr über anderen Fenstern, wenn das Fenster nach vorn kommt.", en = "Windows: Contents of the add-on window no longer sit above other windows when the window comes to the front." },
      },
    },
    {
      version = "0.8.4",
      date = "2026-11-15",
      highlights = {
      },
      added = {
        { de = "Berufsroute: \"Start bis Ziel zur Einkaufsliste\" setzt die Materialien des Bereichs auf die Liste, mit \"Schritte auswählen\" nur die gewählten Schritte.", en = "Profession route: \"Start to target to the list\" puts the materials of the range on the list, \"Pick steps\" only the chosen steps.", go = "professionroute" },
        { de = "Berufsroute: Jeder Schritt zeigt Rezeptrolle und fertiges Item mit eigenem Tooltip. Ein Klick öffnet das Rezept im Berufsfenster, der Hammer auf der Rolle immer.", en = "Profession route: Every step shows the recipe scroll and the finished item with its own tooltip. A click opens the recipe in the profession window, the hammer always does.", go = "professionroute" },
        { de = "Berufe: Fehlt der Beruf oder das Rezept, sagt das Addon beim Klick, was fehlt, statt das Fenster zu öffnen.", en = "Professions: Without the profession or the recipe, a click says what is missing instead of opening the window.", go = "professionroute" },
        { de = "Einkaufsliste: Knöpfe zum Öffnen der kleinen Liste auf den Seiten Berufe und Berufsroute, in den Einstellungen und in der Titelleiste.", en = "Shopping list: Buttons that open the small list on the professions and profession route pages, in the settings and in the title bar.", go = "professions" },
      },
      changed = {
        { de = "Berufe: Materialien zeigen den vollen Item-Tooltip mit Icon, Herstellungskosten, Händlerpreis und den AH-Preisen aus dem letzten Scan.", en = "Professions: Materials show the full item tooltip with icon, crafting cost, vendor price and the auction prices of the last scan.", go = "professionroute" },
        { de = "Berufe: \"Zur Einkaufsliste hinzufügen\" legt beim hergestellten Item die Reagenzien an, \"Fertig hinzufügen\" das fertige Item. Beides steht nebeneinander.", en = "Professions: \"Add to shopping list\" on a made item adds its reagents, \"Add finished\" the finished item. Both stand side by side.", go = "professions" },
        { de = "Berufe: Die Seite merkt sich Beruf und Skill vom letzten Besuch.", en = "Professions: The page remembers profession and skill of the last visit.", go = "professions" },
        { de = "Einkaufsliste: Die kleine Liste zeigt die Menge vor dem Namen und im Tooltip, wie viel noch zu kaufen ist und wie viel du schon hast.", en = "Shopping list: The small list shows the amount before the name and in the tooltip how much is left to buy and how much you have.", go = "professions" },
      },
      fixed = {
        { de = "Berufsroute: Die Skill-Bereiche stehen immer ganz da, nicht mehr gekürzt wie \"100-...\".", en = "Profession route: Skill ranges are always shown in full, no longer cut like \"100-...\".", go = "professionroute" },
      },
    },
    {
      version = "0.8.3",
      date = "2026-11-14",
      highlights = {
      },
      changed = {
        { de = "Instanzen: Der Reiter Bosse zeigt links die Liste und rechts den gewählten Boss mit Porträt, Stufe und Fähigkeiten.", en = "Instances: The Bosses tab lists the bosses on the left and shows the chosen boss with portrait, level and abilities on the right.", go = "instances" },
        { de = "Instanzen: Seltene Gegner stehen unter den festen Bossen. Teilen sie sich einen Platz, sind sie ein Eintrag \"Einer von\".", en = "Instances: Rare enemies are listed below the regular bosses. Those sharing a spot are one \"One of\" entry.", go = "instances" },
      },
      fixed = {
        { de = "Instanzen: Die Dungeonkarte zeigt im Kloster, in Düsterbruch und in der Schwarzfelsspitze die Bosse aller Flügel, jeder mit seinem Flügel.", en = "Instances: The dungeon map shows the bosses of every wing in Scarlet Monastery, Dire Maul and Blackrock Spire, each with its wing.", go = "instances" },
        { de = "Instanzen: Besiegt und Sperren stimmen jetzt je Flügel, vorher zeigte etwa Schönufer den Stand von Herod.", en = "Instances: Defeated states and lockouts now match per wing, before Fairbanks showed the state of Herod.", go = "instances" },
      },
    },
    {
      version = "0.8.2",
      date = "2026-11-14",
      highlights = {
      },
      added = {
        { de = "Seltene Gegner: Drei Stufen direkt oben in den Einstellungen: auf den Karten mit Hinweis, nur Hinweis in der Bildschirmmitte oder aus.", en = "Rare enemies: Three modes right at the top of the settings: on the maps with alert, only the alert in the screen center or off.", go = "settings:map.rares" },
        { de = "Setup: Die Zeile Seltene Gegner hat die Haken \"Auf den Karten\" und \"Hinweis bei Fund\". Ohne Karte bleibt nur der Hinweis.", en = "Setup: The rare enemies row has the options \"On the maps\" and \"Alert when found\". Without the map only the alert stays.", go = "settings:setup.wizard" },
      },
      changed = {
        { de = "Seltene Gegner: Die einzelnen Schalter für Weltkarte, Minikarte und Hinweis stehen jetzt unter Weitere Einstellungen.", en = "Rare enemies: The single switches for world map, minimap and alert are now under More settings.", go = "settings:map.rares" },
        { de = "Setup: Sammelpunkte funkeln steht wieder in einer eigenen Zeile, die Sätze unter Sammeln und Seltene Gegner zeigt der Tooltip.", en = "Setup: Gathering sparkles has a line of its own again, the tooltip shows the sentences of Gathering and Rare enemies.", go = "settings:setup.wizard" },
      },
    },
  },
}
