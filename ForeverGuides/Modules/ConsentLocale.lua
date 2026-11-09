-- Texts of the sharing functions (Core/Consent.lua) and of the settings tab "Share" in both languages:
-- per function consent.<id>.label, .hint, .fields (micro line) and .info (the full information text
-- the dialog and the privacy info show), plus the shared texts of the tab. A package that makes
-- its function available checks the draft of its text before it marks it.
local _, ns = ...

-- Lines of an information text per language: what is sent, to whom, why, what the receiver keeps. The
-- last three lines are the same for every function.
local TAIL = {
  enUS = {
    "Transfer: through the chat servers of Blizzard, never through a server of the add-on or its website.",
    "Withdraw: Settings > Share, it takes effect at once. Copies that others have already stored cannot be fetched back.",
    "Voluntary: the date of your choice is stored on this computer only.",
  },
  deDE = {
    "Übertragung: über die Chat-Server von Blizzard, nie über einen Server des Addons oder der Website.",
    "Widerruf: Einstellungen > Teilen, wirkt sofort. Kopien, die andere schon gespeichert haben, kannst du nicht zurückholen.",
    "Freiwillig: Das Datum deiner Entscheidung wird nur auf diesem Rechner gespeichert.",
  },
}
-- The sentence about the probe ("who is there?") of the guild functions, added to the line "to whom".
local PROBE = {
  enUS = "Who is there: receivers ask the guild on switch-on and login, senders answer, at most once per minute.",
  deDE = "Nachfrage: Empfänger fragen beim Einschalten und Login die Gilde, Sender antworten (einmal je Minute).",
}
-- Functions that ask and answer this way (ShareSync).
local PROBES = { peerStats = true, professions = true, presenceMark = true, crestMark = true, guildMap = true, crafting = true }

local LABEL = {
  enUS = { "Data: ", "To whom: ", "Purpose: ", "Receiver: " },
  deDE = { "Daten: ", "An wen: ", "Zweck: ", "Empfänger: " },
}
local READ = {
  enUS = " Everyone in that channel can read the message, other addons included.",
  deDE = " Alle in diesem Kanal können die Nachricht mitlesen, auch andere Addons.",
}

-- rows: { data, to, purpose, receiver } of one language; reads = false when the line "to" says it itself.
local function info(lang, rows, reads, probe)
  local out = {}
  for i = 1, 4 do
    out[i] = LABEL[lang][i] .. rows[i] .. (i == 2 and reads ~= false and READ[lang] or "")
  end
  if probe then
    -- Same line as "to whom": the information text keeps its seven lines.
    out[2] = out[2] .. " " .. PROBE[lang]
  end
  for _, line in ipairs(TAIL[lang]) do
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end

local KEPT = {
  enUS = "Name, realm and value go into your list. They stay until you delete them or switch receiving off.",
  deDE = "Name, Realm und Wert kommen in deine Liste. Sie bleiben, bis du sie löschst oder Empfangen ausschaltest.",
}

local en, de = {}, {}

local function add(id, label, hint, fields, enRows, deRows, reads)
  en["consent." .. id .. ".label"], de["consent." .. id .. ".label"] = label[1], label[2]
  en["consent." .. id .. ".hint"], de["consent." .. id .. ".hint"] = hint[1], hint[2]
  en["consent." .. id .. ".fields"], de["consent." .. id .. ".fields"] = fields[1], fields[2]
  en["consent." .. id .. ".info"] = info("enUS", enRows, reads, PROBES[id])
  de["consent." .. id .. ".info"] = info("deDE", deRows, reads, PROBES[id])
end

add(
  "peerStats",
  { "Item level", "Itemlevel" },
  { "Your item level to addon users in group and guild.", "Dein Itemlevel an Addon-Nutzer in Gruppe und Gilde." },
  { "Sent: item level as a number.", "Gesendet wird: Itemlevel als Zahl." },
  {
    "your item level as a number, nothing else.",
    "addon users in your group and guild, as far as you switch them on.",
    "your item level shows in the guild list and the contacts of others.",
    KEPT.enUS,
  },
  {
    "dein Itemlevel als Zahl, sonst nichts.",
    "Addon-Nutzer in deiner Gruppe und Gilde, soweit du sie einschaltest.",
    "dein Itemlevel erscheint in der Gildenliste und in den Kontakten der anderen.",
    KEPT.deDE,
  }
)
add("professions", { "Professions", "Berufe" }, {
  "Your professions and skill to addon users in group and guild.",
  "Deine Berufe und Stufen an Addon-Nutzer in Gruppe und Gilde.",
}, {
  "Sent: up to 6 professions with skill and maximum.",
  "Gesendet wird: bis zu 6 Berufe mit Stufe und Maximum.",
}, {
  "up to 6 professions, each with skill and maximum.",
  "addon users in your group and guild, as far as you switch them on.",
  "your professions show in the guild list and the contacts of others.",
  KEPT.enUS,
}, {
  "bis zu 6 Berufe, je mit Stufe und Maximum.",
  "Addon-Nutzer in deiner Gruppe und Gilde, soweit du sie einschaltest.",
  "deine Berufe erscheinen in der Gildenliste und in den Kontakten der anderen.",
  KEPT.deDE,
})
add("presenceMark", { "Presence", "Anwesenheit" }, {
  "Shows other addon users that you use the addon.",
  "Zeigt anderen Addon-Nutzern, dass du das Addon nutzt.",
}, {
  "Sent: the sign that you use the addon, with a logo flag.",
  "Gesendet wird: das Zeichen, dass du das Addon nutzt, mit Logo-Markierung.",
}, {
  "the sign that you use the add-on and a flag whether your logo shows on nameplates or in chat only. No values, no names beyond the sender.",
  "addon users in your group and guild, as far as you switch them on.",
  "other users see your logo at your name in chat or on the nameplate and know that you use the add-on.",
  "They keep it in memory only. It is gone at the next login, when they switch receiving off or when you withdraw.",
}, {
  "das Zeichen, dass du das Addon nutzt, und eine Markierung, ob dein Logo an Namensplaketten oder nur im Chat erscheint. Keine Werte, keine Namen außer dem Absender.",
  "Addon-Nutzer in deiner Gruppe und Gilde, soweit du sie einschaltest.",
  "andere sehen dein Logo an deinem Namen im Chat oder an der Namensplakette und wissen, dass du das Addon nutzt.",
  "Sie halten es nur im Arbeitsspeicher. Es ist beim nächsten Login weg, wenn sie Empfangen ausschalten oder wenn du widerrufst.",
})
add("crestMark", { "Guild and communities", "Gilde und Communitys" }, {
  "Shows the logo of your guild and communities next to your name.",
  "Zeigt anderen das Logo deiner Gilde und Communitys neben deinem Namen.",
}, {
  "Sent: short codes of the logos you choose. Never a name or a picture.",
  "Gesendet wird: kurze Kennungen der Logos, die du wählst. Nie ein Name und nie ein Bild.",
}, {
  "short codes of the guild logo and the community logos you choose, only logos that the add-on knows. No names, no pictures, nothing is sent while you choose nothing.",
  "addon users in your group and guild, as far as you switch them on.",
  "other users see these logos next to your name in chat and know which guild and communities you chose to show.",
  "They keep it in memory only. It is gone at the next login, when they switch receiving off or when you withdraw.",
}, {
  "kurze Kennungen des Gildenlogos und der Community-Logos, die du wählst, nur Logos, die das Addon kennt. Keine Namen, keine Bilder, nichts wird gesendet, solange du nichts wählst.",
  "Addon-Nutzer in deiner Gruppe und Gilde, soweit du sie einschaltest.",
  "andere sehen diese Logos neben deinem Namen im Chat und wissen, welche Gilde und welche Communitys du zeigen willst.",
  "Sie halten es nur im Arbeitsspeicher. Es ist beim nächsten Login weg, wenn sie Empfangen ausschalten oder wenn du widerrufst.",
})
add("linkShare", { "Chat links", "Chat-Links" }, {
  "Notes, drawings, builds, lists and layouts as a chat link.",
  "Notizen, Zeichnungen, Skillungen, Listen und Layouts als Chat-Link.",
}, {
  "Sent: the content you pick, in the link or by whisper.",
  "Gesendet wird: der Inhalt, den du wählst, im Link oder per Flüstern.",
}, {
  "the note, drawing, build, list, layout, element or group you pick. Short content sits in the link, larger content goes by whisper to whoever opens the link, only until /reload or logout. It can contain anything you wrote.",
  "everyone who sees the link in the chat you send it to, and everyone who opens it. Receiving: links of others become clickable and opening one asks the sender by whisper.",
  "others open your content in the add-on instead of copying text by hand.",
  "Whoever opens it sees the content and can keep a copy. Nobody gets an answer for content you did not share.",
}, {
  "die Notiz, Zeichnung, Skillung, Liste, das Layout, Element oder die Gruppe, die du wählst. Kurzer Inhalt steckt im Link, größerer geht per Flüstern an jeden, der den Link öffnet, nur bis /reload oder Logout. Der Inhalt kann alles enthalten, was du geschrieben hast.",
  "alle, die den Link in dem Chat sehen, in den du ihn sendest, und alle, die ihn öffnen. Empfangen: Links anderer werden klickbar, beim Öffnen fragt das Addon den Absender per Flüstern.",
  "andere öffnen deinen Inhalt im Addon, statt Text von Hand zu kopieren.",
  "Wer ihn öffnet, sieht den Inhalt und kann eine Kopie behalten. Für Inhalt, den du nicht geteilt hast, bekommt niemand eine Antwort.",
}, false)
add("guildMap", { "Guild map", "Gildenkarte" }, {
  "Your position for guild members on the map.",
  "Deine Position für Gildenmitglieder auf der Karte.",
}, {
  "Sent: map and position, exact by default (you can change it).",
  "Gesendet wird: Karte und Position, Standard genau (einstellbar).",
}, {
  "your map and position on it. Default: exact. Under Settings > Map and travel > Your own position you can switch to a grid (5 percent of the map) or zone only. It is a live track of where you are.",
  "guild members who use the add-on.",
  "they see you as a dot on the world map and the minimap. Switch Invisible on to stop it at once. Nothing goes out in combat, instances, battlegrounds or while AFK.",
  "They keep it in memory only and show it while it is current. It is never saved.",
}, {
  "deine Karte und Position darauf. Standard: genau. Unter Einstellungen > Karte und Reise > Deine eigene Position stellst du auf ein Raster (5 Prozent der Karte) oder nur die Zone um. Es ist eine Live-Spur dessen, wo du bist.",
  "Gildenmitglieder, die das Addon nutzen.",
  "sie sehen dich als Punkt auf der Weltkarte und der Minikarte. Mit Unsichtbar stoppst du es sofort. Im Kampf, in Instanzen, Schlachtfeldern und bei AFK geht nichts raus.",
  "Sie halten sie nur im Arbeitsspeicher und zeigen sie, solange sie aktuell ist. Sie wird nie gespeichert.",
})
add("crafting", { "Recipes", "Rezepte" }, {
  "Your professions and recipes for guild members who look for a crafter.",
  "Deine Berufe und Rezepte für Gildenmitglieder, die einen Hersteller suchen.",
}, {
  "Sent: professions, skill levels and the recipes you know.",
  "Gesendet wird: Berufe, Skillstufen und die Rezepte, die du kennst.",
}, {
  "your professions with skill and maximum and the recipes you know in them as numbers. Only the character you play. A profession appears once you opened its window.",
  "guild members with the add-on who switched receiving on. Asked who can make a recipe, you whisper an answer to the asker, and only if you know it. Nothing goes to group, friends or strangers. Opening a crafter list asks the guild.",
  "they find out who in the guild can craft an item.",
  "They keep your list for up to 14 days or until they delete it. Withdrawing makes everyone online delete it, members who are offline keep it until it expires.",
}, {
  "deine Berufe mit Stufe und Maximum und die dort bekannten Rezepte als Zahlen. Nur der Charakter, den du spielst. Ein Beruf erscheint, sobald du sein Fenster öffnest.",
  "Gildenmitglieder mit Addon und Empfangen an. Bei einer Rezept-Frage flüsterst du nur dem Fragenden, nur bei bekanntem Rezept. Nichts geht an Gruppe, Freunde oder Fremde. Eine Hersteller-Liste fragt die Gilde.",
  "sie sehen, wer in der Gilde einen Gegenstand herstellen kann.",
  "Sie behalten deine Liste bis zu 14 Tage oder bis zum Löschen. Beim Widerruf löschen Online-Spieler sie sofort, Offline-Spieler bis Ablauf.",
})
add("gmShare", { "Share GildenManager", "GildenManager teilen" }, {
  "Join dates, marks and notes to your officers.",
  "Beitrittsdaten, Markierungen und Notizen an deine Offiziere.",
}, {
  "Sent: join dates, marks and notes, as you choose.",
  "Gesendet wird: Beitrittsdaten, Markierungen und Notizen, wie du wählst.",
}, {
  "the categories you switch on in the GildenManager: join dates of members (day, accuracy, source), the marks returned and inactive, and your own notes. Notes are off until you choose them and can hold private text.",
  "guild members with the GildenManager, by default in the officer chat. In the guild chat every member sees it. Only senders of the rank you set and above are accepted.",
  "officers use what others know about members without typing it again.",
  "They find your data in an inbox and adopt or discard each entry. Nothing is applied by itself and nothing typed by hand is overwritten.",
}, {
  "die Kategorien, die du im GildenManager einschaltest: Beitrittsdaten der Mitglieder (Tag, Genauigkeit, Quelle), die Markierungen zurückgekehrt und inaktiv und deine eigenen Notizen. Notizen sind aus, bis du sie wählst, und können Privates enthalten.",
  "Gildenmitglieder mit dem GildenManager, standardmäßig im Offizierschat. Im Gildenchat sieht es jedes Mitglied. Angenommen wird nur von Absendern des eingestellten Rangs und besser.",
  "Offiziere nutzen, was andere über Mitglieder wissen, ohne es neu einzutippen.",
  "Sie finden deine Daten in einem Eingang und übernehmen oder verwerfen jeden Eintrag. Nichts wird von selbst angewendet und nichts von Hand Eingetragenes überschrieben.",
})
add("chatPeer", { "Chat extras", "Chat-Extras" }, {
  "Typing, seen and reactions with addon users you whisper.",
  "Tippen, Gesehen, Reaktionen mit Addon-Nutzern beim Flüstern.",
}, {
  "Sent: typing, seen and reaction signs, never message text.",
  "Gesendet wird: Zeichen für Tippen, Gesehen und Reaktion, nie Nachrichtentext.",
}, {
  "signs only: that you type (on or off), a 5 character mark of the line you read, or a mark of a line with the number of a reaction symbol. The mark is made from the text and the time of the line, the text cannot be read from it. Never a message text.",
  "only the addon user of the whisper chat that is open in the messenger, and only if he sent such a sign first or made himself recognizable. Other addons on both computers can read the signs.",
  'the messenger shows "typing", "seen" and your reactions at the lines.',
  "They show the signs and do not store them. Switching off removes the display at once, a goodbye sign tells partners to remove yours.",
}, {
  "nur Zeichen: dass du tippst (an oder aus), eine 5-stellige Marke der Zeile, die du gelesen hast, oder die Marke einer Zeile mit der Nummer eines Reaktionssymbols. Die Marke entsteht aus Text und Zeit der Zeile, den Text kann man daraus nicht lesen. Nie ein Nachrichtentext.",
  "nur der Addon-Nutzer des Flüster-Chats, der im Messenger offen ist, und nur wenn er zuerst ein solches Zeichen geschickt hat oder sich erkennbar gemacht hat. Andere Addons auf beiden Rechnern können die Zeichen lesen.",
  'der Messenger zeigt "tippt", "gesehen" und deine Reaktionen an den Zeilen.',
  "Sie zeigen die Zeichen an und speichern sie nicht. Ausschalten entfernt die Anzeige sofort, ein Abschiedszeichen sagt Partnern, dass sie deine entfernen sollen.",
}, false)
add("teamChat", { "Team chats", "Team-Chats" }, {
  "Messages and invitations of your teams with addon users.",
  "Nachrichten und Einladungen deiner Teams mit Addon-Nutzern.",
}, {
  "Sent: team messages, invitations and team data.",
  "Gesendet wird: Team-Nachrichten, Einladungen und Teamdaten.",
}, {
  "your team messages as plain text, your name for the team, its symbol and the member list, invitations you write, and the answers to them.",
  "only the members of your teams and the players you invite, one hidden addon message per person. Other addons on both computers can read the messages.",
  "you chat with your team like in a group, and members who were offline fetch what they missed from you.",
  "They keep the history of a team on their computer for at most 30 days and 500 messages and delete it when they leave. Admins can change the name, the symbol and the members.",
}, {
  "deine Team-Nachrichten als reiner Text, dein Name für das Team, sein Symbol und die Mitgliederliste, Einladungen, die du schreibst, und die Antworten darauf.",
  "nur die Mitglieder deiner Teams und die Spieler, die du einlädst, je eine versteckte Addon-Nachricht pro Person. Andere Addons auf beiden Rechnern können die Nachrichten lesen.",
  "du chattest mit deinem Team wie in einer Gruppe, und Mitglieder, die offline waren, holen bei dir nach, was sie verpasst haben.",
  "Sie speichern den Verlauf eines Teams höchstens 30 Tage und 500 Nachrichten auf ihrem Rechner und löschen ihn beim Verlassen. Admins können Name, Symbol und Mitglieder ändern.",
}, false)
add(
  "layer",
  { "Layer", "Layer" },
  { "Not in use.", "Ohne Funktion." },
  { "Nothing is sent.", "Es wird nichts gesendet." },
  {
    "none, this is a placeholder.",
    "nobody.",
    "none yet.",
    "Nothing arrives.",
  },
  {
    "keine, das ist ein Platzhalter.",
    "niemand.",
    "noch keiner.",
    "Es kommt nichts an.",
  },
  false
)

local audiences = {
  group = { "Group", "Gruppe" },
  guild = { "Guild", "Gilde" },
  chat = { "Chat", "Chat" },
  world = { "World", "Welt" },
}
for aud, names in pairs(audiences) do
  en["consent.aud." .. aud], de["consent.aud." .. aud] = names[1], names[2]
end
local flags = {
  send = {
    group = { "Send to group", "An Gruppe senden" },
    guild = { "Send to guild", "An Gilde senden" },
    chat = { "Send in chat", "Im Chat senden" },
    world = { "Send to world", "An Welt senden" },
  },
  receive = {
    group = { "Receive from group", "Aus Gruppe empfangen" },
    guild = { "Receive from guild", "Aus Gilde empfangen" },
    chat = { "Receive from chat", "Aus Chat empfangen" },
    world = { "Receive from world", "Aus Welt empfangen" },
  },
}
for dir, list in pairs(flags) do
  for aud, names in pairs(list) do
    en["consent.flag." .. dir .. "." .. aud], de["consent.flag." .. dir .. "." .. aud] = names[1], names[2]
  end
end

local shared = {
  ["consent.title"] = { "Share data with other addon users", "Daten mit anderen Addon-Nutzern teilen" },
  ["consent.default"] = {
    "Off by default. Nothing is sent or received until you switch it on here.",
    "Standard aus. Nichts wird gesendet oder empfangen, bevor du es hier einschaltest.",
  },
  ["consent.count"] = { "On: %d of %d", "Aktiv: %d von %d" },
  ["consent.withdrawAll"] = { "Switch everything off", "Alles ausschalten" },
  ["consent.withdrawAll.title"] = { "Switch everything off", "Alles ausschalten" },
  ["consent.withdrawAll.confirm"] = {
    "Switch off all sharing for this account? Sending stops at once. Deleted: presence, logos, guild map, crafter directory, and item levels and professions that came from add-on messages. The open invitations of Teams and the open entries of the GildenManager go as well. Teams and saved chats stay, you delete them in the messenger. GildenManager entries you adopted stay.",
    "Alles Teilen für dieses Konto ausschalten? Senden endet sofort. Gelöscht werden Anwesenheit, Logos, Gildenkarte, Hersteller-Verzeichnis sowie Itemlevel und Berufe aus Addon-Nachrichten. Auch die offenen Einladungen der Teams und die offenen Einträge im GildenManager verschwinden. Teams und gespeicherte Chats bleiben, du löschst sie im Messenger. Übernommene Einträge im GildenManager bleiben.",
  },
  ["consent.privacy"] = { "Privacy info", "Datenschutz-Info" },
  ["consent.privacy.hint"] = { "Select the text and copy it with Ctrl+C", "Text markieren und mit Strg+C kopieren" },
  ["consent.privacy.body"] = {
    "Sharing with other addon users is off until you switch it on, per function, direction and audience. Sending and receiving are separate.\n"
      .. "Data goes from player to player through the chat servers of Blizzard. Nothing is sent to the author of the add-on or to a website.\n"
      .. "Other players in the channel and their addons can read the messages. Receivers store names, realms and values on their computer.\n"
      .. "Whoever receives a guild function sends one small question to the guild (who is there?) with no data about themselves. Whoever has sending on answers it, at most once per function and minute.\n"
      .. "You can switch off at any time, it takes effect at once. Copies others have stored stay with them.\n"
      .. "This text describes what the add-on does. It is not legal advice.",
    "Teilen mit anderen Addon-Nutzern ist aus, bis du es einschaltest, je Funktion, Richtung und Zielgruppe. Senden und Empfangen sind getrennt.\n"
      .. "Die Daten gehen von Spieler zu Spieler über die Chat-Server von Blizzard. Sie gehen nie an den Entwickler des Addons oder an eine Website.\n"
      .. "Andere Spieler im Kanal und ihre Addons können die Nachrichten mitlesen. Empfänger speichern Namen, Realms und Werte auf ihrem Rechner.\n"
      .. "Wer eine Gildenfunktion empfängt, schickt einmal eine kleine Frage an die Gilde (wer ist da?), ohne Daten über sich. Wer Senden an hat, antwortet darauf, höchstens einmal je Funktion und Minute.\n"
      .. "Du kannst jederzeit ausschalten, es wirkt sofort. Kopien, die andere gespeichert haben, bleiben bei ihnen.\n"
      .. "Dieser Text beschreibt, was das Addon tut. Er ist keine Rechtsberatung.",
  },
  ["consent.empty"] = {
    "No function is available yet. Functions appear here once they are part of the add-on.",
    "Noch keine Funktion verfügbar. Funktionen erscheinen hier, sobald sie Teil des Addons sind.",
  },
  ["consent.send"] = { "Send", "Senden" },
  ["consent.receive"] = { "Receive", "Empfangen" },
  ["consent.since"] = { "since %s", "seit %s" },
  ["consent.scope"] = { "For this character", "Für diesen Charakter" },
  ["consent.scope.account"] = { "Like account", "Wie Konto" },
  ["consent.scope.char"] = { "Own setting", "Eigene Einstellung" },
  ["consent.scope.hint"] = {
    "Own setting applies to this character only. Like account follows the account again.",
    "Eigene Einstellung gilt nur für diesen Charakter. Wie Konto folgt wieder dem Konto.",
  },
  -- Switches for all functions of one direction at once (setup step and tab Share). "On" always asks first.
  ["consent.bulk.send.on"] = { "Sending: all on", "Senden: alle an" },
  ["consent.bulk.send.off"] = { "Sending: all off", "Senden: alle aus" },
  ["consent.bulk.receive.on"] = { "Receiving: all on", "Empfangen: alle an" },
  ["consent.bulk.receive.off"] = { "Receiving: all off", "Empfangen: alle aus" },
  -- Short labels for the buttons under a column heading (setup step); the long ones stay as their tooltip.
  ["consent.bulk.on"] = { "All on", "Alle an" },
  ["consent.bulk.off"] = { "All off", "Alle aus" },
  ["consent.bulk.count.send"] = { "Sending on: %d of %d", "Senden aktiv: %d von %d" },
  ["consent.bulk.count.receive"] = { "Receiving on: %d of %d", "Empfangen aktiv: %d von %d" },
  ["consent.bulk.scope"] = {
    "%d functions have an own setting for this character: the switch changes this character only there. For all others it changes the account, so every character that follows the account is affected.",
    "%d Funktionen haben eine eigene Einstellung für diesen Charakter: Dort ändert der Schalter nur diesen Charakter. Bei allen anderen ändert er das Konto, jeder Charakter, der dem Konto folgt, ist betroffen.",
  },
  -- Status line of a function card: switches, last sent, last heard, players heard, and the reason when nothing happens.
  ["consent.status.line"] = {
    "Send %s, receive %s. Last sent %s, last heard %s, %d players heard.",
    "Senden %s, Empfangen %s. Zuletzt gesendet %s, zuletzt gehört %s, %d Mitspieler gehört.",
  },
  ["consent.status.ago"] = { "%d s ago", "vor %d s" },
  ["consent.status.never"] = { "never", "noch nie" },
  ["consent.status.why"] = { "Why nothing happens: %s", "Warum nichts passiert: %s" },
  ["consent.why.off"] = {
    "Sending and receiving are off for this function.",
    "Senden und Empfangen sind für diese Funktion aus.",
  },
  ["consent.why.noguild"] = {
    "You are not in a guild, or the game has not reported it yet.",
    "Du bist in keiner Gilde, oder das Spiel hat sie noch nicht gemeldet.",
  },
  ["consent.why.unregistered"] = {
    "The function has not started yet. It starts with the first switch.",
    "Die Funktion ist noch nicht gestartet. Sie startet mit dem ersten Schalter.",
  },
  ["consent.why.roster"] = {
    "The guild list is still loading, the add-on waits for it.",
    "Die Gildenliste lädt noch, das Addon wartet darauf.",
  },
  ["consent.why.trial"] = {
    "This looks like a trial account. Trial accounts cannot send add-on messages, and the game reports no error.",
    "Das sieht nach einem Probekonto aus. Probekonten können keine Addon-Nachrichten senden, das Spiel meldet dabei keinen Fehler.",
  },
  ["consent.why.combat"] = { "Paused in combat.", "Pausiert im Kampf." },
  ["consent.why.instance"] = { "Paused in an instance.", "Pausiert in einer Instanz." },
  ["consent.why.afk"] = { "Paused while you are away.", "Pausiert, solange du abwesend bist." },
  ["consent.why.hidden"] = { "You are hidden, nothing is sent.", "Du bist unsichtbar, es wird nichts gesendet." },
  ["consent.why.restricted"] = {
    "The game blocks add-on messages right now (restriction).",
    "Das Spiel sperrt Addon-Nachrichten gerade (Einschränkung).",
  },
  ["consent.why.throttle"] = {
    "Send limit reached, the add-on waits.",
    "Sendegrenze erreicht, das Addon wartet.",
  },
  ["consent.why.refused"] = {
    "The game refused the last message. /fg diag share names the code.",
    "Das Spiel hat die letzte Nachricht abgelehnt. /fg diag share nennt den Code.",
  },
  ["consent.why.silent"] = {
    "Nobody with the add-on has answered yet. Either nobody in the guild sends this function, or they play on trial accounts.",
    "Noch hat niemand mit dem Addon geantwortet. Entweder sendet niemand in der Gilde diese Funktion, oder es sind Probekonten.",
  },
  ["consent.why.inactive"] = { "Not active right now.", "Gerade nicht aktiv." },
  ["consent.why.empty"] = { "There is nothing to send yet.", "Es gibt noch nichts zu senden." },
  ["consent.bulk.title"] = { "Switch on all", "Alle einschalten" },
  ["consent.bulk.confirm.send"] = {
    "Switch on sending for %d functions?\nOther add-on users in the matching channels can then receive your data.\nDetails: Privacy info. You can switch off at any time.",
    "Senden für %d Funktionen einschalten?\nAndere Addon-Nutzer in den passenden Kanälen können deine Daten dann empfangen.\nDetails: Datenschutz-Info. Du kannst jederzeit ausschalten.",
  },
  ["consent.bulk.confirm.receive"] = {
    "Switch on receiving for %d functions?\nData of other add-on users is then stored on your computer.\nDetails: Privacy info. You can switch off at any time.",
    "Empfangen für %d Funktionen einschalten?\nDaten anderer Addon-Nutzer werden dann auf deinem Rechner gespeichert.\nDetails: Datenschutz-Info. Du kannst jederzeit ausschalten.",
  },
  ["consent.bulk.confirm.aud"] = {
    "All audiences of these functions are included.",
    "Alle Zielgruppen dieser Funktionen sind eingeschlossen.",
  },
  ["consent.chat.title"] = { "Chat lines in your name", "Chat-Zeilen in deinem Namen" },
  ["consent.chat.hint"] = {
    "The add-on writes these lines into normal chat. Everyone in the channel sees them, not only addon users. You change them at the function.",
    "Das Addon schreibt diese Zeilen in den normalen Chat. Alle im Kanal sehen sie, nicht nur Addon-Nutzer. Ändern kannst du sie bei der Funktion.",
  },
  ["consent.chat.reset"] = { "Instance reset to group", "Instanz-Reset an Gruppe" },
  ["consent.chat.xp"] = { "Level-up line to", "Stufenaufstieg an" },
  ["consent.chat.invite"] = { "Reply to invite requests", "Antwort auf Einladungen" },
  ["consent.chat.none"] = { "nobody", "niemanden" },
  ["consent.chat.say"] = { "Say", "Sagen" },
  ["consent.chat.inspect"] = {
    "Reading the group: item level of group members comes from the inspect function of the game. No add-on message is sent. The switch is under Guild and contacts.",
    "Gruppe lesen: Das Itemlevel von Gruppenmitgliedern kommt aus der Betrachten-Funktion des Spiels. Es wird keine Addon-Nachricht gesendet. Der Schalter steht unter Gilde und Kontakte.",
  },
  ["consent.chat.who"] = {
    "Who query: only after your click. It asks the game server about one contact and sends nothing to addon users.",
    "Wer-Abfrage: nur nach deinem Klick. Sie fragt den Spielserver nach einem Kontakt und sendet nichts an Addon-Nutzer.",
  },
}
for key, pair in pairs(shared) do
  en[key], de[key] = pair[1], pair[2]
end
en["settings.tab.sharing"], de["settings.tab.sharing"] = "Share", "Teilen"

ns.AddLocale("enUS", en)
ns.AddLocale("deDE", de)
