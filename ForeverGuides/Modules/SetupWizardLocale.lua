-- Texts of the setup wizard steps in both languages: window texts, step titles and sentences, the sentence of
-- every feature row (Modules/SetupFeatureData.lua) and the options of the steps. The steps are built in
-- Modules/SetupWizardSteps.lua, the texts of the row blocks are in Modules/SetupWizardRows.lua, the texts of the
-- menu step belong to Modules/SetupWizardMenu.lua.
-- Names of the feature rows come from the settings (settings.feature.<id>), only the two rows that are no
-- feature of the settings name themselves (setup.feature.frametweaks, setup.feature.minimap).
local _, ns = ...

ns.AddLocale("enUS", {
  -- Window
  ["setup.title"] = "Setup",
  ["setup.start"] = "Start setup",
  ["setup.notice"] = "New: setup with /fg setup",
  ["setup.noticeNew"] = "New setup steps: /fg setup",
  ["setup.nothingNew"] = "No new steps.",
  ["setup.escapeHint"] = "Controls blocked? Type /fg setup close in chat",
  ["setup.progress"] = "Step %d of %d",
  ["setup.back"] = "Back",
  ["setup.next"] = "Next",
  ["setup.finish"] = "Done",
  ["setup.skip"] = "Skip",
  ["setup.close"] = "Close",
  ["setup.resetAll"] = "Reset all",
  ["setup.skipTitle"] = "Skip setup",
  ["setup.skipText"] = "Apply defaults and close?",
  ["setup.cancelTitle"] = "Close setup",
  ["setup.cancelText"] = "Really close the setup? Your progress stays saved.",
  ["setup.resetTitle"] = "Reset all",
  ["setup.resetText"] = "Set all options to default? Sharing is switched off.",
  ["setup.copy"] = "Copy",
  ["setup.open"] = "Open",
  ["setup.info.tutorials"] = "Tutorials: page in the left navigation (group Addon)",
  ["setup.info.help"] = "Help & feedback: page in the left navigation, report errors there too",
  ["setup.changed"] = "You changed:",
  ["setup.noChanges"] = "No changes, defaults active.",
  ["setup.changeWhere"] = "Change later: Settings, tab in brackets.",

  -- Step start
  ["setup.step.start"] = "Welcome to Forever Guides",
  ["setup.step.start.text"] = "You decide what the addon does for you. Switch features on or off. What is off does not run and is not in the menu.",
  ["setup.start.how1"] = "Switch: turns the feature on or off.",
  ["setup.start.how2"] = "Options: opens every setting of the area in a new window.",
  ["setup.start.how3"] = "Pencil above the menu: hide areas, show them again any time.",

  -- Step look
  ["setup.step.look"] = "Look",
  ["setup.step.look.text"] = "Style, colors and size of the windows. Changes apply right away. Everything else is behind the button.",
  ["setup.step.access"] = "Readability and windows",
  ["setup.step.access.text"] = "Text size, contrast and colors for easier reading, plus two window helpers.",
  ["setup.alphaLow"] = "Very transparent, text can be hard to read.",
  ["setup.moreBelow"] = "More below",
  ["setup.feature.frametweaks"] = "Movable game windows",
  ["setup.feature.frametweaks.text"] = "Drag by the title bar, reset on the page Windows.",
  ["setup.feature.minimap"] = "Minimap button",
  ["setup.feature.minimap.text"] = "The Forever button at the minimap.",

  -- Step display
  ["setup.step.display"] = "On-screen displays",
  ["setup.step.display.text"] = "Ring, experience bar, durability and your own windows.",
  ["setup.feature.cursor.text"] = "A ring around the pointer. Off: the ring stops.",
  ["setup.feature.xpbar.text"] = "Your own experience bar. Off: the bar is closed.",
  ["setup.feature.durability.text"] = "Gear durability. Off hides only the menu entry.",
  ["setup.feature.hudwindows.text"] = "Your own windows. Off hides only the menu entry.",

  -- Step world
  ["setup.step.world"] = "Map and game world",
  ["setup.step.world.text"] = "Extra symbols, gathering spots, flight times and fishing help.",
  ["setup.feature.map.text"] = "Instances, flight points and zone arrows on the map.",
  ["setup.feature.gathering.text"] = "Ore and herbs on the map and the minimap.",
  ["setup.feature.flight.text"] = "Flight times at the flight master and as a timer.",
  ["setup.feature.fishing.text"] = "Fishing helper. Off takes effect after /reload.",
  ["setup.ctl.mapReveal"] = "Show all map areas in color",
  ["setup.ctl.mapRevealHint"] = "Off: only explored areas, the rest dark.",
  ["setup.ctl.sparklesHint"] = "Sets game graphics, off puts them back (restart ends it).",

  -- Step helpers
  ["setup.step.helpers"] = "Helpers and trade",
  ["setup.step.helpers.text"] = "Quests, selling, item level and loot. Risky options stay in the settings.",
  ["setup.feature.quests.text"] = "Accept and turn in quests automatically.",
  ["setup.feature.selling.text"] = "Sell gray items at the merchant.",
  ["setup.feature.items.text"] = "Show item level and enchants.",
  ["setup.feature.inventory.text"] = "The tooltip shows what your characters own.",
  ["setup.feature.loot.text"] = "Record boss loot. Off also hides its menu page.",
  ["setup.ctl.autoRepair"] = "Repair at the merchant",
  ["setup.ctl.autoRepairHint"] = "Repairs when it opens, with enough gold.",
  ["setup.ctl.sellNote"] = "Selling every white, green, blue or epic item: Settings.",

  -- Step chat
  ["setup.step.chat"] = "Chat",
  ["setup.step.chat.text"] = "Names, history and logos in chat. Much of it is active only after your consent.",
  ["setup.feature.chatname.text"] = "Puts your name in front of your messages.",
  ["setup.feature.foreverchat.text"] = "Messenger window. Off takes effect after /reload.",
  ["setup.feature.chathistory.text"] = "Keep the history of the chat window.",
  ["setup.feature.logos.text"] = "Logo before the names of recognized players.",

  -- Step party
  ["setup.step.party"] = "Group and guild",
  ["setup.step.party.text"] = "Invites and helpers in the group.",
  ["setup.step.social"] = "Guild and contacts",
  ["setup.step.social.text"] = "The guild manager and players near you.",
  ["setup.feature.invites.text"] = "Invite to the group by whisper, with a keyword.",
  ["setup.feature.party.text"] = "You decide each answer on its own.",
  ["setup.feature.guild.text"] = "Guild tools for officers. Off takes effect after /reload.",
  ["setup.feature.contacts.text"] = "Spots nearby players for your contacts.",
  ["setup.ctl.inviteWords"] = "Keywords for the group invite",
  ["setup.ctl.inviteWordsExample"] = "inv, invite",
  ["setup.ctl.inviteWordsUsed"] = "Used: %s",
  ["setup.ctl.inviteWordsNone"] = "No keyword: the whisper invite stays off.",
  ["setup.ctl.inviteWordsOff"] = "none",
  ["setup.ctl.acceptFriends"] = "Friends may invite me",
  ["setup.ctl.autoSummon"] = "Accept summons",
  ["setup.ctl.autoSummonHint"] = "Known players only, never in combat.",
  ["setup.ctl.autoResurrect"] = "Accept resurrections",
  ["setup.ctl.autoResurrectHint"] = "Group, guild and friends only.",

  -- Step sharing
  ["setup.step.sharing"] = "Share with others",
  ["setup.step.sharing.text"] = "Everything here is off until you switch it on.",
  ["setup.sharing.privacy"] = "Where the data goes, how to withdraw.",
  ["setup.sharing.more"] = "More info",
  ["setup.sharing.all.text"] = "More audiences and all functions.",
  ["setup.sharing.all"] = "All settings",

  -- Step done
  ["setup.step.done"] = "All set",
  ["setup.step.done.text"] = "Later: /fg setup or Settings > Setup and tour",
  ["setup.done.pencil"] = "Show hidden areas again with the pencil at the top of the menu. Switch features on again in the settings.",
})

ns.AddLocale("deDE", {
  -- Window
  ["setup.title"] = "Einrichtung",
  ["setup.start"] = "Einrichtung starten",
  ["setup.notice"] = "Neu: Einrichtung mit /fg setup",
  ["setup.noticeNew"] = "Neue Einrichtungsschritte: /fg setup",
  ["setup.nothingNew"] = "Keine neuen Schritte.",
  ["setup.escapeHint"] = "Bedienung blockiert? Tippe /fg setup close im Chat",
  ["setup.progress"] = "Schritt %d von %d",
  ["setup.back"] = "Zurück",
  ["setup.next"] = "Weiter",
  ["setup.finish"] = "Fertig",
  ["setup.skip"] = "Überspringen",
  ["setup.close"] = "Schließen",
  ["setup.resetAll"] = "Alles auf Standard",
  ["setup.skipTitle"] = "Einrichtung überspringen",
  ["setup.skipText"] = "Standardwerte übernehmen und schließen?",
  ["setup.cancelTitle"] = "Einrichtung schließen",
  ["setup.cancelText"] = "Einrichtung wirklich schließen? Dein Fortschritt bleibt gespeichert.",
  ["setup.resetTitle"] = "Alles auf Standard",
  ["setup.resetText"] = "Alle Optionen auf Standard? Teilen wird ausgeschaltet.",
  ["setup.copy"] = "Kopieren",
  ["setup.open"] = "Öffnen",
  ["setup.info.tutorials"] = "Tutorials: Seite in der Navigation links (Gruppe Addon)",
  ["setup.info.help"] = "Hilfe & Feedback: Seite in der Navigation links, dort auch Fehler melden",
  ["setup.changed"] = "Du hast geändert:",
  ["setup.noChanges"] = "Keine Änderungen, Standardwerte aktiv.",
  ["setup.changeWhere"] = "Später ändern: Einstellungen, Reiter in Klammern.",

  -- Step start
  ["setup.step.start"] = "Willkommen bei Forever Guides",
  ["setup.step.start.text"] = "Du entscheidest, was das Addon für dich tut. Features schaltest du an oder aus. Was aus ist, läuft nicht und steht nicht im Menü.",
  ["setup.start.how1"] = "Schalter: Das Feature an- oder ausschalten.",
  ["setup.start.how2"] = "Optionen: Öffnet alle Einstellungen des Bereichs in einem neuen Fenster.",
  ["setup.start.how3"] = "Stift über dem Menü: Bereiche aus- und wieder einblenden.",

  -- Step look
  ["setup.step.look"] = "Aussehen",
  ["setup.step.look.text"] = "Stil, Farben und Größe der Fenster. Änderungen wirken sofort. Alles Weitere findest du über den Knopf.",
  ["setup.step.access"] = "Lesbarkeit und Fenster",
  ["setup.step.access.text"] = "Schriftgröße, Kontrast und Farben zum besseren Lesen, dazu zwei Fensterhelfer.",
  ["setup.alphaLow"] = "Sehr durchsichtig, Text kann schwer lesbar sein.",
  ["setup.moreBelow"] = "Mehr weiter unten",
  ["setup.feature.frametweaks"] = "Spielfenster verschiebbar",
  ["setup.feature.frametweaks.text"] = "Am Titel ziehen, zurücksetzen auf der Seite Fenster.",
  ["setup.feature.minimap"] = "Minimap-Knopf",
  ["setup.feature.minimap.text"] = "Der Forever-Knopf an der Minimap.",

  -- Step display
  ["setup.step.display"] = "Anzeigen im Spiel",
  ["setup.step.display.text"] = "Ring, Erfahrungsleiste, Haltbarkeit und eigene Fenster.",
  ["setup.feature.cursor.text"] = "Ein Ring um den Mauszeiger. Aus: Ring läuft nicht.",
  ["setup.feature.xpbar.text"] = "Eigene Erfahrungsleiste. Aus: Leiste zu.",
  ["setup.feature.durability.text"] = "Zustand der Ausrüstung. Aus blendet nur das Menü aus.",
  ["setup.feature.hudwindows.text"] = "Eigene Fenster. Aus blendet nur das Menü aus.",

  -- Step world
  ["setup.step.world"] = "Karte und Spielwelt",
  ["setup.step.world.text"] = "Zusatzsymbole, Sammelpunkte, Flugzeiten und Angelhilfe.",
  ["setup.feature.map.text"] = "Instanzen, Flugpunkte und Zonenpfeile auf der Karte.",
  ["setup.feature.gathering.text"] = "Erz und Kräuter auf Karte und Minimap.",
  ["setup.feature.flight.text"] = "Flugzeiten am Flugmeister und als Zeitanzeige.",
  ["setup.feature.fishing.text"] = "Hilfen zum Angeln. Aus wirkt nach /reload.",
  ["setup.ctl.mapReveal"] = "Alle Kartengebiete in Farbe zeigen",
  ["setup.ctl.mapRevealHint"] = "Aus: nur erkundete Gebiete, der Rest dunkel.",
  ["setup.ctl.sparklesHint"] = "Setzt Spiel-Grafik, Aus stellt sie zurück (mit Neustart).",

  -- Step helpers
  ["setup.step.helpers"] = "Helfer und Handel",
  ["setup.step.helpers.text"] = "Quests, Verkaufen, Itemlevel und Beute. Riskantes steht in den Einstellungen.",
  ["setup.feature.quests.text"] = "Quests automatisch annehmen und abgeben.",
  ["setup.feature.selling.text"] = "Graue Items beim Händler verkaufen.",
  ["setup.feature.items.text"] = "Itemlevel und Verzauberungen anzeigen.",
  ["setup.feature.inventory.text"] = "Der Tooltip zeigt den Besitz deiner Charaktere.",
  ["setup.feature.loot.text"] = "Beute der Bosse erfassen. Aus blendet auch die Seite aus.",
  ["setup.ctl.autoRepair"] = "Beim Händler reparieren",
  ["setup.ctl.autoRepairHint"] = "Repariert beim Öffnen, nur mit genug Gold.",
  ["setup.ctl.sellNote"] = "Alles Weiß, Grün, Blau, Episch verkaufen: Einstellungen.",

  -- Step chat
  ["setup.step.chat"] = "Chat",
  ["setup.step.chat.text"] = "Namen, Verlauf und Logos im Chat. Vieles ist erst nach Zustimmung aktiv.",
  ["setup.feature.chatname.text"] = "Setzt deinen Namen vor deine Nachrichten.",
  ["setup.feature.foreverchat.text"] = "Messenger-Fenster. Aus wirkt nach /reload.",
  ["setup.feature.chathistory.text"] = "Verlauf des Chat-Fensters speichern.",
  ["setup.feature.logos.text"] = "Logo vor den Namen erkannter Spieler.",

  -- Step party
  ["setup.step.party"] = "Gruppe und Gilde",
  ["setup.step.party.text"] = "Einladungen und Hilfen in der Gruppe.",
  ["setup.step.social"] = "Gilde und Kontakte",
  ["setup.step.social.text"] = "Der Gildenmanager und Spieler in deiner Nähe.",
  ["setup.feature.invites.text"] = "Per Flüstern in die Gruppe einladen, mit Stichwort.",
  ["setup.feature.party.text"] = "Du entscheidest jede Antwort einzeln.",
  ["setup.feature.guild.text"] = "Gildenwerkzeuge für Offiziere. Aus wirkt nach /reload.",
  ["setup.feature.contacts.text"] = "Erkennt Spieler in der Nähe für die Kontakte.",
  ["setup.ctl.inviteWords"] = "Stichwörter für die Gruppeneinladung",
  ["setup.ctl.inviteWordsExample"] = "inv, invite",
  ["setup.ctl.inviteWordsUsed"] = "Gilt: %s",
  ["setup.ctl.inviteWordsNone"] = "Kein Stichwort: Einladung per Flüstern bleibt aus.",
  ["setup.ctl.inviteWordsOff"] = "keine",
  ["setup.ctl.acceptFriends"] = "Freunde dürfen mich einladen",
  ["setup.ctl.autoSummon"] = "Beschwörungen annehmen",
  ["setup.ctl.autoSummonHint"] = "Nur bekannte Spieler, nie im Kampf.",
  ["setup.ctl.autoResurrect"] = "Wiederbelebung annehmen",
  ["setup.ctl.autoResurrectHint"] = "Nur Gruppe, Gilde und Freunde.",

  -- Step sharing
  ["setup.step.sharing"] = "Mit anderen teilen",
  ["setup.step.sharing.text"] = "Alles hier ist aus, bis du es einschaltest.",
  ["setup.sharing.privacy"] = "Wohin die Daten gehen, wie du widerrufst.",
  ["setup.sharing.more"] = "Mehr dazu",
  ["setup.sharing.all.text"] = "Weitere Zielgruppen und alle Funktionen.",
  ["setup.sharing.all"] = "Alle Einstellungen",

  -- Step done
  ["setup.step.done"] = "Fertig",
  ["setup.step.done.text"] = "Später: /fg setup oder Einstellungen > Einrichtung und Tour",
  ["setup.done.pencil"] = "Ausgeblendete Bereiche zeigst du mit dem Stift oben im Menü wieder an. Features schaltest du in den Einstellungen wieder ein.",
})
