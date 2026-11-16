-- Generated from the changelog of the repo, do not edit.
local _, ns = ...
ns.Data = ns.Data or {}
ns.Data.Changelog = {
  v = 1,
  versions = {
    {
      version = "0.10.1",
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
    {
      version = "0.8.1",
      date = "2026-11-14",
      highlights = {
      },
      changed = {
        { de = "Sammelpunkte: Erze, Kräuter, Truhen und Fischschwärme sind ab Werk auf allen Karten aus. Bestehende Einstellungen bleiben, wie sie sind.", en = "Gathering: Ores, herbs, chests and fishing schools are off by default on all maps. Existing settings stay as they are.", go = "settings:gathering.pins" },
        { de = "Sammelpunkte: Einschalten geht im Setup, in den Einstellungen unter Sammeln oder im Kartenfilter, alle nutzen dieselbe Einstellung. Das Setup bietet jede der vier Arten einzeln.", en = "Gathering: Turn them on in the setup, the settings under Gathering or the map filter, all share one setting. The setup offers each of the four kinds.", go = "settings:gathering.pins" },
        { de = "Addon-Karte: Sind die Sammelpunkte aus, sagt die Zeile unter dem Schalter, wo man sie einschaltet.", en = "Addon map: When the gathering spots are off, the line under the switch tells where to turn them on.", go = "settings:gathering.pins" },
      },
    },
    {
      version = "0.8.0",
      date = "2026-11-14",
      highlights = {
        { head = { de = "Seltene Gegner", en = "Rare enemies" }, text = { de = "Weltkarte und Minimap zeigen seltene Gegner mit Stufe, Beute und Spawnpunkten.", en = "The world map and the minimap show rare enemies with level, loot and spawn points." }, go = "settings:map.rares" },
        { head = { de = "Fundhinweis", en = "Find alert" }, text = { de = "Taucht ein Seltener auf, zeigt ein Fenster Modell und Beute, ein Klick nimmt ihn ins Ziel.", en = "When a rare shows up, a window shows its model and loot, one click targets it." }, go = "settings:map.rares" },
      },
      added = {
        { de = "Seltene Gegner: Scanner für 486 seltene Gegner mit Symbolen auf Weltkarte und Minimap. Ab Werk aus, einschalten in den Einstellungen unter Karte oder im Setup.", en = "Rare enemies: Scanner for 486 rare enemies with symbols on the world map and the minimap. Off by default, turn it on in the settings under Map or in the setup.", go = "settings:map.rares" },
        { de = "Seltene Gegner: Eine Karte zeigt Porträt, Stufe und Status, auf der Weltkarte auch die Beute mit Dropchance. Ein Klick heftet sie an, kleine Marker zeigen die übrigen Spawnpunkte.", en = "Rare enemies: A card shows portrait, level and status, on the world map also the loot with drop chance. One click pins it, small markers show the other spawn points.", go = "settings:map.rares" },
        { de = "Seltene Gegner: Ein Seltener in der Nähe wird erkannt und mit Fenster, Text in der Bildschirmmitte, Chatzeile und Ton gemeldet. Linksklick ins Fenster nimmt ihn ins Ziel, Rechtsklick schließt.", en = "Rare enemies: A rare nearby is recognised and reported with a window, a line in the screen center, a chat line and a sound. Left click on the window targets it, right click closes it.", go = "settings:map.rares" },
        { de = "Seltene Gegner: Das Addon merkt sich, welche Seltenen du gesehen oder getötet hast. Noch nicht gesehene tragen einen roten Kreis.", en = "Rare enemies: The add-on remembers which rares you have seen or killed. Those not seen yet carry a red circle.", go = "settings:map.rares" },
      },
    },
    {
      version = "0.7.12",
      date = "2026-11-14",
      highlights = {
      },
      changed = {
        { de = "Instanzen: Die Quest-Liste zeigt nur den Anfang jeder Kette. Die Schritte stehen nummeriert im Detail und im Kettenfenster, Allianz und Horde getrennt. Der Funkelmat ist eine Zeile.", en = "Instances: The quest list shows only the start of each chain. Steps are numbered in the details and the chain window, Alliance and Horde apart. The Sparklematic is one row.", go = "instances" },
        { de = "Instanzen: Klassenquests tragen \"Klassenquest:\" mit Klassensymbol und Klassenname in der Klassenfarbe, wiederholbare Quests das Wort \"wiederholbar\" mit Symbol.", en = "Instances: Class quests carry \"Class quest:\" with the class icon and the class name in its class color, repeatable quests the word \"repeatable\" with an icon.", go = "instances" },
      },
      fixed = {
        { de = "Instanzen: Fraktion, Stufe, Vorquests und Klasse der Dungeon- und Raid-Quests in allen Instanzen geprüft und korrigiert, unter anderem 11 falsche Fraktionen und 46 fehlende Stufen.", en = "Instances: Faction, level, prequests and class of the dungeon and raid quests checked and corrected in all instances, among them 11 wrong factions and 46 missing levels.", go = "instances" },
        { de = "Stufen-Übersicht: Fähigkeiten, die es im Spiel nicht mehr gibt, sind entfernt, darunter Tigerfuror beim Druiden. Fluch der Pein heißt jetzt Omen der Pein, Feuernova-Totem heißt Feuernova.", en = "Level overview: Abilities that no longer exist in the game are removed, among them Tiger's Fury for druids. Curse of Agony is now Bane of Agony, Fire Nova Totem is now Fire Nova." },
      },
    },
    {
      version = "0.7.11",
      date = "2026-11-14",
      highlights = {
      },
      changed = {
        { de = "Daten: Spielbuild 1.60.1.70938 mit allen Hotfixes.", en = "Data: Game build 1.60.1.70938 with all hotfixes." },
        { de = "Talente: Sieben neue Talente von Druide, Paladin, Priester und Schurke heißen im deutschen Spiel jetzt auf Deutsch.", en = "Talents: Seven new talents of druid, paladin, priest and rogue now have their German names in the German game.", go = "talents" },
        { de = "Berufe: Die Skillstufen von 25 Rezepten und die Reagenzmengen von 5 Schneiderei-Rezepten entsprechen dem aktuellen Spielstand.", en = "Professions: The skill levels of 25 recipes and the reagent counts of 5 tailoring recipes match the current game.", go = "professions" },
      },
    },
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
  },
}
