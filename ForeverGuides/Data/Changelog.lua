-- Generated from the changelog of the repo, do not edit.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.Changelog = {
  v = 1,
  versions = {
    {
      version = "0.7.10",
      date = "2026-11-14",
      highlights = {
      },
      changed = {
        { de = "Angelhilfe: Die Taste meldet sich im Chat nur noch, wenn Angeln gerade nicht geht, mit dem Grund und ohne Wiederholung.", en = "Fishing helper: The key only speaks up in chat when fishing is not possible right now, with the reason and without repeating itself.", go = "settings:fishing.cast" },
      },
      fixed = {
        { de = "Angelhilfe: Ein Tastendruck im Kampf bei offenem Fangjournal schaltet die Angelhilfe nicht mehr aus.", en = "Fishing helper: A key press in combat while the catch journal is open no longer switches the fishing helper off.", go = "settings:fishing.cast" },
        { de = "Angelhilfe: Blockiert das Spiel einen Aufruf, pausiert die Hilfe nur und läuft nach dem Kampf von selbst weiter. Wer seit dem Fehler festhing, kann sofort wieder angeln.", en = "Fishing helper: When the game blocks a call, the helper only pauses and resumes by itself after combat. Anyone stuck since the bug can fish again right away.", go = "settings:fishing.cast" },
      },
    },
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
  },
}
