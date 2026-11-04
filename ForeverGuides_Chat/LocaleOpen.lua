-- Texts of the ways to open the window and of the intake of every chat line: the switches that open the window
-- by itself (ChatAutoOpen.lua), the screen button, the minimap icon and the macro card (ChatLaunch.lua,
-- ChatButton.lua, ChatMinimap.lua) and the name of the chat for lines the game does not let the add-on read.
local _, chat = ...
if not chat.hook then
  return
end

chat.FG.AddLocale("enUS", {
  ["chat.restricted.name"] = "Not readable (game restriction)",
  ["chat.bnet.unknown"] = "Battle.net contact",
  ["chat.reason.conversation"] = "You cannot write here. Answer in the game chat.",

  ["chat.open.group"] = "Open by itself",
  ["chat.open.autoOpen"] = "Open for whispers",
  ["chat.open.autoOpen.hint"] = "Also Battle.net whispers",
  ["chat.open.autoOpenGroup"] = "Open for party chat",
  ["chat.open.autoOpenGroup.hint"] = "Party and instance, when a chat begins",
  ["chat.open.autoOpenRaid"] = "Open for raid chat",
  ["chat.open.autoOpenRaid.hint"] = "When a raid chat begins",
  ["chat.open.autoOpenGuild"] = "Open for guild chat",
  ["chat.open.autoOpenGuild.hint"] = "Guild and officers, when a chat begins",
  ["chat.open.autoOpenChannel"] = "Open for channels",
  ["chat.open.autoOpenChannel.hint"] = "Only mentions count, see Mentions",
  ["chat.open.autoOpenTeam"] = "Open for teams",
  ["chat.open.autoOpenTeam.hint"] = "When a team chat begins",
  ["chat.open.rules1"] = "The window never takes the focus. Enter stays in game chat.",
  ["chat.open.rules2"] = "After you closed it, only a new chat opens it again.",
  ["chat.open.rules3"] = "In combat it only opens if it was built before.",

  ["chat.launch.group"] = "Button and minimap icon",
  ["chat.launch.screenButton"] = "Button on the screen",
  ["chat.launch.screenButton.hint"] = "Opens and closes the window, works in combat",
  ["chat.launch.minimapIcon"] = "Forever Chat minimap icon",
  ["chat.launch.minimapIcon.hint"] = "Shows unread messages, drag it along the edge",
  ["chat.launch.edit"] = "Edit position",
  ["chat.launch.edit.tip"] = "Drag to move, pull the corner to resize.",
  ["chat.launch.reset"] = "Reset position",
  ["chat.launch.reset.tip"] = "Button and icon go back to the first place.",
  ["chat.launch.macro"] = "Open by macro",
  ["chat.launch.macro.hint"] = "Click the line, copy with Ctrl+C. Also /fgchat works.",

  ["chat.btn.done"] = "Done",
  ["chat.btn.done.tip"] = "Saves place and size",
  ["chat.btn.grip"] = "Pull to resize",
  ["chat.btn.tip"] = "Click to open or close the messenger",

  ["chat.icon.unread"] = "%d unread",
  ["chat.icon.leftClick"] = "Left click: open or close",
  ["chat.icon.rightClick"] = "Right click: menu",
  ["chat.icon.markRead"] = "Mark everything as read",
  ["chat.icon.settings"] = "Chat settings",
})
chat.FG.AddLocale("deDE", {
  ["chat.restricted.name"] = "Nicht lesbar (Spielbeschränkung)",
  ["chat.bnet.unknown"] = "Battle.net-Kontakt",
  ["chat.reason.conversation"] = "Hier kannst du nicht schreiben. Antworte im Spiel-Chat.",

  ["chat.open.group"] = "Von selbst öffnen",
  ["chat.open.autoOpen"] = "Bei Flüstern öffnen",
  ["chat.open.autoOpen.hint"] = "Auch Battle.net-Flüstern",
  ["chat.open.autoOpenGroup"] = "Bei Gruppenchat öffnen",
  ["chat.open.autoOpenGroup.hint"] = "Gruppe und Instanz, wenn ein Chat beginnt",
  ["chat.open.autoOpenRaid"] = "Bei Raidchat öffnen",
  ["chat.open.autoOpenRaid.hint"] = "Wenn ein Raidchat beginnt",
  ["chat.open.autoOpenGuild"] = "Bei Gildenchat öffnen",
  ["chat.open.autoOpenGuild.hint"] = "Gilde und Offiziere, wenn ein Chat beginnt",
  ["chat.open.autoOpenChannel"] = "Bei Kanälen öffnen",
  ["chat.open.autoOpenChannel.hint"] = "Nur Erwähnungen zählen, siehe Erwähnungen",
  ["chat.open.autoOpenTeam"] = "Bei Teams öffnen",
  ["chat.open.autoOpenTeam.hint"] = "Wenn ein Team-Chat beginnt",
  ["chat.open.rules1"] = "Das Fenster nimmt nie den Fokus. Enter bleibt im Spiel-Chat.",
  ["chat.open.rules2"] = "Hast du es geschlossen, öffnet nur ein neuer Chat es wieder.",
  ["chat.open.rules3"] = "Im Kampf öffnet es nur, wenn es vorher gebaut wurde.",

  ["chat.launch.group"] = "Knopf und Minimap-Symbol",
  ["chat.launch.screenButton"] = "Knopf auf dem Bildschirm",
  ["chat.launch.screenButton.hint"] = "Öffnet und schließt das Fenster, geht im Kampf",
  ["chat.launch.minimapIcon"] = "Chat-Minimap-Symbol",
  ["chat.launch.minimapIcon.hint"] = "Zeigt Ungelesenes, am Rand der Minimap ziehbar",
  ["chat.launch.edit"] = "Position bearbeiten",
  ["chat.launch.edit.tip"] = "Ziehen verschiebt, die Ecke ändert die Größe.",
  ["chat.launch.reset"] = "Position zurücksetzen",
  ["chat.launch.reset.tip"] = "Knopf und Symbol gehen an den Startplatz.",
  ["chat.launch.macro"] = "Öffnen per Makro",
  ["chat.launch.macro.hint"] = "Zeile anklicken, mit Strg+C kopieren. Auch /fgchat geht.",

  ["chat.btn.done"] = "Fertig",
  ["chat.btn.done.tip"] = "Speichert Platz und Größe",
  ["chat.btn.grip"] = "Ziehen ändert die Größe",
  ["chat.btn.tip"] = "Klick öffnet oder schließt den Messenger",

  ["chat.icon.unread"] = "%d ungelesen",
  ["chat.icon.leftClick"] = "Linksklick: öffnen oder schließen",
  ["chat.icon.rightClick"] = "Rechtsklick: Menü",
  ["chat.icon.markRead"] = "Alles als gelesen markieren",
  ["chat.icon.settings"] = "Chat-Einstellungen",
})
