-- Page "Gilde & Kontakte" (/fg gilde, /fg guild; /fg sozial, /fg social, /fg kontakte, /fg contacts
-- open the tab "Sozial"): read-only guild overview (members, message of the day, search, filters,
-- sorting, detail card with whisper) and the tab "Sozial" with every player met (group, dungeon,
-- trade, ...), paginated, with a whisper, an invite and an update button in every row. The detail card
-- sits between the filters and the list; it tells when and where the player was last seen and how the
-- contact began (NearbyContacts keeps the sighting current, the first contact never changes). Item level and professions come from Peers (read by
-- GroupInspect and PeerComm) and show "reading ..." for a fresh group member, "-" while unknown.
-- Data comes from GuildData (guild) and SeenPlayers (local list). Nothing here
-- changes the guild; the management belongs to the add-on "Forever Guides: GildenManager", which
-- adds tabs, detail lines and columns through ns.GuildExt (GuildExt.lua) and hides the hint card
-- (the hint card shows on the tab "Gilde" only).
-- In demo mode (GuildData.IsDemo) the page shows the sample guild of GuildDemo.lua under a banner.
-- That add-on loads on demand: with a guild (or the demo) and the add-on switched on the page loads it
-- once when it opens, else the hint card offers the button (ns.PackageUI). Tabs, columns and detail
-- lines that register later are picked up without losing selection, filters or page.
local _, ns = ...
local W, L, Theme, K, Store = ns.W, ns.L, ns.Theme, ns.PageKit, ns.Store
local GL, GD, SP, PN, R, GE = ns.GuildLogic, ns.GuildData, ns.SeenPlayers, ns.PlayerName, ns.RefLogic, ns.GuildExt

local P = {}
ns.GuildPage = P

local ROW_HEIGHT = 44
local MAX_ROWS = 12
local PAD = 12
local DROPDOWN_WIDTH = 170
local TOGGLE_WIDTH = 200
local CHECK_WIDTH = 150
local PAGER_BUTTON = 90
local GAP = 8
local SEARCH_HEIGHT = 26
local ACTION_WIDTH = 150
local MAX_ACTIONS = 6
local STOP_WIDTH = 130
local DEMO_START_WIDTH = 180
local WHISPER_ICON, INVITE_ICON, UPDATE_ICON = "pencil", "plus", "refresh" -- icons of ns.UI_ICONS
local MANAGER_ADDON = "ForeverGuides_GildenManager"
local MANAGER_STATE = { loaded = "guild.manager.on", disabled = "guild.manager.off", missing = "guild.manager.missing" }
-- One automatic load attempt per session, whatever the page is built how often.
local autoTried = false

ns.AddLocale("enUS", {
  ["page.guild"] = "Guild & Contacts",
  ["guild.tab.guild"] = "Guild",
  ["guild.tab.social"] = "Social",
  ["guild.manager"] = "Needs the add-on Forever Guides: GildenManager.",
  ["guild.manager.state"] = "State: %s",
  ["guild.manager.on"] = "on",
  ["guild.manager.off"] = "off",
  ["guild.manager.missing"] = "missing",
  ["guild.demo.banner"] = "Sample data, not a real guild",
  ["guild.demo.start"] = "View sample data",
  ["guild.demo.end"] = "End demo",
  ["guild.demo.rights"] = "Demo rights",
  ["guild.demo.role.leader"] = "Guild master",
  ["guild.demo.role.officer"] = "Officer",
  ["guild.demo.role.member"] = "Member",
  ["guild.demo.seen"] = "Sample list, nothing is stored",
  ["guild.link"] = "Copy link",
  ["guild.link.title"] = "GildenManager",
  ["guild.link.hint"] = "Link to copy",
  ["guild.none"] = "You are not in a guild.",
  ["guild.loading"] = "Loading guild list ...",
  ["guild.online"] = "Online: %d of %d",
  ["guild.motd.title"] = "Message of the day",
  ["guild.motd.empty"] = "No message of the day",
  ["guild.stats.levels"] = "Levels: %s",
  ["guild.stats.classes"] = "Classes: %s",
  ["guild.search"] = "Search",
  ["guild.onlyOnline"] = "Online only",
  ["guild.rank"] = "Rank",
  ["guild.rank.all"] = "All ranks",
  ["guild.race"] = "Race",
  ["guild.race.all"] = "All races",
  ["guild.class"] = "Class",
  ["guild.class.all"] = "All classes",
  ["guild.sort"] = "Sort by",
  ["guild.sort.rank"] = "Rank",
  ["guild.sort.name"] = "Name",
  ["guild.sort.level"] = "Level",
  ["guild.sort.class"] = "Class",
  ["guild.sort.zone"] = "Zone",
  ["guild.sort.online"] = "Last online",
  ["guild.sort.recent"] = "Last seen",
  ["guild.count"] = "%d of %d",
  ["guild.empty"] = "No matches.",
  ["guild.page"] = "Page %d of %d",
  ["guild.prev"] = "Back",
  ["guild.next"] = "Next",
  ["guild.cols"] = "Columns",
  ["guild.col.rank"] = "Rank",
  ["guild.col.level"] = "Level",
  ["guild.col.zone"] = "Zone",
  ["guild.col.ilvl"] = "Item level",
  ["guild.col.jobs"] = "Professions",
  ["guild.col.note"] = "Note",
  ["guild.col.last"] = "Last online",
  ["guild.col.race"] = "Race",
  ["guild.col.class"] = "Class",
  ["guild.col.seen"] = "Last seen",
  ["guild.col.source"] = "First contact",
  ["guild.col.guild"] = "Guild",
  ["guild.level"] = "Level %d",
  ["guild.ilvl"] = "iLvl %s",
  ["guild.last.online"] = "Online",
  ["guild.last.unknown"] = "unknown",
  ["guild.last.years"] = "%d y ago",
  ["guild.last.months"] = "%d mo ago",
  ["guild.last.day"] = "1 day ago",
  ["guild.last.days"] = "%d days ago",
  ["guild.last.hours"] = "%d h ago",
  ["guild.last.lt1"] = "< 1 h ago",
  ["guild.detail.rank"] = "Rank: %s",
  ["guild.detail.race"] = "Race: %s",
  ["guild.detail.zone"] = "Zone: %s",
  ["guild.detail.last"] = "Last online: %s",
  ["guild.detail.seen"] = "Last seen: %s",
  ["guild.detail.seenIn"] = "Last seen: %s in %s",
  ["guild.detail.first"] = "First contact: %s",
  ["guild.on"] = "on %s",
  ["guild.in"] = "in %s",
  ["guild.date"] = "%m/%d",
  ["guild.detail.note"] = "Note: %s",
  ["guild.detail.officer"] = "Officer note: %s",
  ["guild.detail.ilvl"] = "Item level: %s",
  ["guild.detail.jobs"] = "Professions: %s",
  ["guild.detail.guild"] = "Guild: %s",
  ["guild.detail.title"] = "Title: %s",
  ["guild.detail.pvp"] = "PvP flagged",
  ["guild.detail.honor"] = "Honor level: %d",
  ["guild.detail.role"] = "Role: %s",
  ["guild.detail.live"] = "Group: %s",
  ["guild.role.TANK"] = "Tank",
  ["guild.role.HEALER"] = "Healer",
  ["guild.role.DAMAGER"] = "Damage",
  ["guild.live.afk"] = "AFK",
  ["guild.live.offline"] = "offline",
  ["guild.live.in"] = "in range",
  ["guild.live.out"] = "out of range",
  ["guild.peer.tip"] = "As of %s, source: %s",
  ["guild.peer.source.game"] = "Game",
  ["guild.peer.source.inspect"] = "Inspect",
  ["guild.peer.source.addon"] = "Add-on",
  ["guild.peer.source.manual"] = "Manual",
  ["guild.peer.now"] = "just now",
  ["guild.peer.minutes"] = "%d min ago",
  ["guild.reading"] = "reading ...",
  ["guild.whisper"] = "Whisper",
  ["guild.whisper.tip"] = "Fills the chat box, nothing is sent.",
  ["guild.invite"] = "Invite",
  ["guild.invite.tip"] = "Invites the player to your group.",
  ["guild.invite.demo"] = "Sample data, nobody is invited.",
  ["guild.seen.empty"] = "Nobody seen yet.",
  ["guild.seen.local"] = "Stored locally only",
  ["guild.seen.off"] = "Saving is off (settings)",
  ["guild.seen.privacy"] = "Item level via inspect, jobs only from add-on users who share. Contacts are refreshed when they show up as a visible unit.",
  ["guild.src.group"] = "Group",
  ["guild.src.raid"] = "Raid",
  ["guild.src.dungeon"] = "Dungeon",
  ["guild.src.trade"] = "Trade",
  ["guild.src.guild"] = "Guild",
  ["guild.src.target"] = "Target",
  ["guild.set.heading"] = "Guild and players",
  ["guild.set.seen"] = "Save recently seen players",
  ["guild.set.targets"] = "Include targets",
  ["guild.set.clear"] = "Clear list",
  ["guild.set.clearTitle"] = "Clear list",
  ["guild.set.clearText"] = "Delete all recently seen players?",
  ["guild.set.cleared"] = "List cleared",
  ["guild.set.inspect"] = "Read group item level",
  ["guild.set.inspectHint"] = "Inspects members in range, never in combat.",
  ["guild.set.nearby"] = "Detect players nearby",
  ["guild.set.nearbyHint"] = "Refreshes known contacts when they show up as a visible unit (name plate, target, mouse over). Needs the friendly player name plates of the game (Shift+V, setting nameplateShowFriendlyPlayers), the add-on never changes that setting on its own. Nothing is asked from the server, strangers are not stored.",
  ["guild.plates.state"] = "Friendly player name plates: %s",
  ["guild.plates.on"] = "on",
  ["guild.plates.off"] = "off",
  ["guild.plates.unreadable"] = "not readable",
  ["guild.plates.enable"] = "Switch on friendly player name plates",
  ["guild.plates.hint"] = "Shows more name plates in cities, so players walking by are found. The add-on never changes your setting on its own, only when you click this button.",
  ["guild.plates.done"] = "Friendly player name plates are on.",
  ["guild.plates.combat"] = "Not possible in combat. Try again afterwards.",
  ["guild.plates.unavailable"] = "This game client does not offer the setting. Switch the name plates on in the game options.",
  ["guild.plates.failed"] = "The game did not accept the setting.",
  ["guild.set.share"] = "Share jobs, item level",
  ["guild.set.shareHint"] = "Shares your professions and item level with your group and guild, only with players who have Forever Guides. No other data is sent.",
  ["guild.set.shareGuild"] = "Also share with guild",
})
ns.AddLocale("deDE", {
  ["page.guild"] = "Gilde & Kontakte",
  ["guild.tab.guild"] = "Gilde",
  ["guild.tab.social"] = "Sozial",
  ["guild.manager"] = "Braucht das Zusatz-Addon Forever Guides: GildenManager.",
  ["guild.manager.state"] = "Status: %s",
  ["guild.manager.on"] = "an",
  ["guild.manager.off"] = "aus",
  ["guild.manager.missing"] = "fehlt",
  ["guild.demo.banner"] = "Beispieldaten, keine echte Gilde",
  ["guild.demo.start"] = "Beispieldaten ansehen",
  ["guild.demo.end"] = "Demo beenden",
  ["guild.demo.rights"] = "Rechte in der Demo",
  ["guild.demo.role.leader"] = "Gildenleiter",
  ["guild.demo.role.officer"] = "Offizier",
  ["guild.demo.role.member"] = "Mitglied",
  ["guild.demo.seen"] = "Beispielliste, nichts wird gespeichert",
  ["guild.link"] = "Link kopieren",
  ["guild.link.title"] = "GildenManager",
  ["guild.link.hint"] = "Link zum Kopieren",
  ["guild.none"] = "Du bist in keiner Gilde.",
  ["guild.loading"] = "Gildenliste lädt ...",
  ["guild.online"] = "Online: %d von %d",
  ["guild.motd.title"] = "Tagesnachricht",
  ["guild.motd.empty"] = "Keine Tagesnachricht",
  ["guild.stats.levels"] = "Stufen: %s",
  ["guild.stats.classes"] = "Klassen: %s",
  ["guild.search"] = "Suchen",
  ["guild.onlyOnline"] = "Nur online",
  ["guild.rank"] = "Rang",
  ["guild.rank.all"] = "Alle Ränge",
  ["guild.race"] = "Rasse",
  ["guild.race.all"] = "Alle Rassen",
  ["guild.class"] = "Klasse",
  ["guild.class.all"] = "Alle Klassen",
  ["guild.sort"] = "Sortierung",
  ["guild.sort.rank"] = "Rang",
  ["guild.sort.name"] = "Name",
  ["guild.sort.level"] = "Stufe",
  ["guild.sort.class"] = "Klasse",
  ["guild.sort.zone"] = "Ort",
  ["guild.sort.online"] = "Zuletzt online",
  ["guild.sort.recent"] = "Zuletzt gesehen",
  ["guild.count"] = "%d von %d",
  ["guild.empty"] = "Keine Treffer.",
  ["guild.page"] = "Seite %d von %d",
  ["guild.prev"] = "Zurück",
  ["guild.next"] = "Weiter",
  ["guild.cols"] = "Spalten",
  ["guild.col.rank"] = "Rang",
  ["guild.col.level"] = "Stufe",
  ["guild.col.zone"] = "Ort",
  ["guild.col.ilvl"] = "Itemlevel",
  ["guild.col.jobs"] = "Berufe",
  ["guild.col.note"] = "Notiz",
  ["guild.col.last"] = "Zuletzt online",
  ["guild.col.race"] = "Rasse",
  ["guild.col.class"] = "Klasse",
  ["guild.col.seen"] = "Zuletzt gesehen",
  ["guild.col.source"] = "Erstkontakt",
  ["guild.col.guild"] = "Gilde",
  ["guild.level"] = "Stufe %d",
  ["guild.ilvl"] = "iLvl %s",
  ["guild.last.online"] = "Online",
  ["guild.last.unknown"] = "unbekannt",
  ["guild.last.years"] = "vor %d J.",
  ["guild.last.months"] = "vor %d Mon.",
  ["guild.last.day"] = "vor 1 Tag",
  ["guild.last.days"] = "vor %d Tagen",
  ["guild.last.hours"] = "vor %d Std.",
  ["guild.last.lt1"] = "vor < 1 Std.",
  ["guild.detail.rank"] = "Rang: %s",
  ["guild.detail.race"] = "Rasse: %s",
  ["guild.detail.zone"] = "Ort: %s",
  ["guild.detail.last"] = "Zuletzt online: %s",
  ["guild.detail.seen"] = "Zuletzt gesehen: %s",
  ["guild.detail.seenIn"] = "Zuletzt gesehen: %s in %s",
  ["guild.detail.first"] = "Erstkontakt: %s",
  ["guild.on"] = "am %s",
  ["guild.in"] = "in %s",
  ["guild.date"] = "%d.%m.",
  ["guild.detail.note"] = "Notiz: %s",
  ["guild.detail.officer"] = "Offiziersnotiz: %s",
  ["guild.detail.ilvl"] = "Itemlevel: %s",
  ["guild.detail.jobs"] = "Berufe: %s",
  ["guild.detail.guild"] = "Gilde: %s",
  ["guild.detail.title"] = "Titel: %s",
  ["guild.detail.pvp"] = "PvP aktiv",
  ["guild.detail.honor"] = "Ehrenstufe: %d",
  ["guild.detail.role"] = "Rolle: %s",
  ["guild.detail.live"] = "Gruppe: %s",
  ["guild.role.TANK"] = "Tank",
  ["guild.role.HEALER"] = "Heiler",
  ["guild.role.DAMAGER"] = "Schaden",
  ["guild.live.afk"] = "AFK",
  ["guild.live.offline"] = "offline",
  ["guild.live.in"] = "in Reichweite",
  ["guild.live.out"] = "außer Reichweite",
  ["guild.peer.tip"] = "Stand %s, Quelle: %s",
  ["guild.peer.source.game"] = "Spiel",
  ["guild.peer.source.inspect"] = "Betrachten",
  ["guild.peer.source.addon"] = "Addon",
  ["guild.peer.source.manual"] = "Manuell",
  ["guild.peer.now"] = "gerade eben",
  ["guild.peer.minutes"] = "vor %d Min.",
  ["guild.reading"] = "wird gelesen",
  ["guild.whisper"] = "Flüstern",
  ["guild.whisper.tip"] = "Füllt die Chatzeile, es wird nichts gesendet.",
  ["guild.invite"] = "Einladen",
  ["guild.invite.tip"] = "Lädt den Spieler in deine Gruppe ein.",
  ["guild.invite.demo"] = "Beispieldaten, niemand wird eingeladen.",
  ["guild.seen.empty"] = "Noch niemand gesehen.",
  ["guild.seen.local"] = "Nur lokal gespeichert",
  ["guild.seen.off"] = "Speichern ist aus (Einstellungen)",
  ["guild.seen.privacy"] = "Itemlevel per Betrachten, Berufe nur von Addon-Nutzern mit Freigabe. Kontakte werden aktualisiert, wenn sie als sichtbare Einheit auftauchen.",
  ["guild.src.group"] = "Gruppe",
  ["guild.src.raid"] = "Raid",
  ["guild.src.dungeon"] = "Dungeon",
  ["guild.src.trade"] = "Handel",
  ["guild.src.guild"] = "Gilde",
  ["guild.src.target"] = "Ziel",
  ["guild.set.heading"] = "Gilde und Spieler",
  ["guild.set.seen"] = "Zuletzt gesehene Spieler speichern",
  ["guild.set.targets"] = "Ziele aufnehmen",
  ["guild.set.clear"] = "Liste löschen",
  ["guild.set.clearTitle"] = "Liste löschen",
  ["guild.set.clearText"] = "Alle zuletzt gesehenen Spieler löschen?",
  ["guild.set.cleared"] = "Liste gelöscht",
  ["guild.set.inspect"] = "Gruppen-Itemlevel lesen",
  ["guild.set.inspectHint"] = "Betrachtet Mitglieder in Reichweite, nie im Kampf.",
  ["guild.set.nearby"] = "Spieler in der Nähe erkennen",
  ["guild.set.nearbyHint"] = "Aktualisiert bekannte Kontakte, wenn sie als sichtbare Einheit auftauchen (Namensplakette, Ziel, Maus). Braucht die freundlichen Spieler-Plaketten des Spiels (Umschalt+V, Einstellung nameplateShowFriendlyPlayers), das Addon ändert diese Einstellung nie von selbst. Es wird nichts beim Server abgefragt, Fremde werden nicht gespeichert.",
  ["guild.plates.state"] = "Freundliche Spieler-Plaketten: %s",
  ["guild.plates.on"] = "an",
  ["guild.plates.off"] = "aus",
  ["guild.plates.unreadable"] = "nicht lesbar",
  ["guild.plates.enable"] = "Freundliche Spieler-Plaketten einschalten",
  ["guild.plates.hint"] = "Zeigt mehr Plaketten in Städten, damit vorbeilaufende Spieler erkannt werden. Das Addon ändert deine Einstellung nie von selbst, nur auf Klick auf diesen Knopf.",
  ["guild.plates.done"] = "Freundliche Spieler-Plaketten sind an.",
  ["guild.plates.combat"] = "Im Kampf nicht möglich. Versuche es danach noch einmal.",
  ["guild.plates.unavailable"] = "Dieser Spielclient bietet die Einstellung nicht an. Schalte die Plaketten in den Spieloptionen ein.",
  ["guild.plates.failed"] = "Das Spiel hat die Einstellung nicht übernommen.",
  ["guild.set.share"] = "Berufe, Itemlevel teilen",
  ["guild.set.shareHint"] = "Teilt deine Berufe und dein Itemlevel mit deiner Gruppe und Gilde, nur mit Spielern, die Forever Guides haben. Es werden keine anderen Daten gesendet.",
  ["guild.set.shareGuild"] = "Auch mit Gilde teilen",
})

local KNOWN_CLASS = {}
for _, class in ipairs(R.CLASSES) do
  KNOWN_CLASS[class] = true
end
local SOURCES = { group = true, raid = true, dungeon = true, trade = true, guild = true, target = true }

local function coloredName(name, class)
  if not KNOWN_CLASS[class] then
    return name
  end
  return string.format("|cff%s%s|r", K.ClassColorHex(class):sub(2), name)
end

local function className(class, fallback)
  return KNOWN_CLASS[class] and R.className(class) or (fallback ~= "" and fallback or class)
end

local function classIcon(class)
  local coords = KNOWN_CLASS[class] and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if not coords then
    return nil
  end
  return function(tex)
    tex:SetTexture(K.CLASS_ICON_SHEET)
    tex:SetTexCoord(unpack(coords))
  end
end

-- Only fills the chat box, nothing is sent. The name keeps its surname and realm.
local function whisper(name)
  name = PN.Clean(name)
  if name == "" then
    return
  end
  local tell = rawget(_G, "ChatFrame_SendTell")
  if type(tell) == "function" and pcall(tell, name) then
    return
  end
  local open = rawget(_G, "ChatFrame_OpenChat")
  if type(open) == "function" then
    pcall(open, "/w " .. name .. " ")
  end
end

local function joinParts(parts)
  return table.concat(parts, " · ")
end

local function sourceText(e)
  return SOURCES[e.src] and L["guild.src." .. e.src] or ""
end

-- "10/09" or "09.10.", "" for an unknown time.
local function dateText(t)
  if type(t) ~= "number" or t <= 0 then
    return ""
  end
  local ok, text = pcall(date, L["guild.date"], t)
  return ok and type(text) == "string" and text or ""
end

local function columns(tab)
  return ns.db.settings.guildCols and ns.db.settings.guildCols[tab]
end

local function peerOf(name, guid)
  if GD.IsDemo() then
    return GD.DemoPeer(name)
  end
  return ns.Peers.Get(name, guid)
end

-- "-" while unknown, "reading ..." while GroupInspect or PeerComm still work on a group member.
local function ilvlText(peer, name)
  local text, group = GL.IlvlText(peer), ns.GroupInspect
  if text == "-" and not GD.IsDemo() and group and group.Loading(name) then
    return L["guild.reading"]
  end
  return text
end

local function jobsText(peer, name)
  local text, comm = GL.JobsText(peer), ns.PeerComm
  if text == "-" and not GD.IsDemo() and comm and comm.Waiting(name) then
    return L["guild.reading"]
  end
  return text
end

-- Guild roster member of a name (offline state for the invite button), rebuilt per roster snapshot.
local rosterIndex, rosterFor
local function guildMember(name)
  local snap = GD.Get()
  if rosterFor ~= snap then
    rosterIndex, rosterFor = {}, snap
    for _, m in ipairs(snap.members) do
      rosterIndex[m.key] = m
    end
  end
  return rosterIndex[PN.Key(name)]
end

-- The three icon buttons of a contact row (whisper, invite, update, from the right). A button that
-- cannot work is dimmed with the reason as its tooltip text; in the sample data nothing is sent or
-- asked. refresh redraws the page after a query, so the dimmed state shows at once.
local function rowActions(e, refresh)
  local demo = GD.IsDemo()
  local member = not demo and guildMember(e.name) or nil
  local offline = member ~= nil and not member.online
  local reason = demo and "demo" or ns.Invites.GroupInviteBlock(e.name, e.guid, offline)
  local whyNot, wait = ns.NearbyWho.Block()
  whyNot = demo and "demo" or whyNot
  return {
    {
      icon = WHISPER_ICON,
      boxed = true,
      tooltip = L["guild.whisper"],
      tooltipText = L["guild.whisper.tip"],
      onClick = function()
        whisper(e.name)
      end,
    },
    {
      icon = INVITE_ICON,
      boxed = true,
      dim = reason ~= nil,
      tooltip = L["guild.invite"],
      tooltipText = reason and (reason == "demo" and L["guild.invite.demo"] or L["invite.why." .. reason])
        or L["guild.invite.tip"],
      onClick = function()
        ns.Invites.InviteToGroup(e.name, e.guid, offline)
      end,
    },
    {
      icon = UPDATE_ICON,
      boxed = true,
      dim = whyNot ~= nil,
      tooltip = L["nearby.who.update"],
      tooltipText = whyNot and ns.NearbyWho.WhyText(whyNot, wait) or L["nearby.who.tip"],
      onClick = function()
        ns.NearbyWho.Request(e)
        refresh()
      end,
    },
  }
end

-- Rows ----------------------------------------------------------------------------------------------

local function guildKey(m)
  return "g:" .. m.key
end

local function seenKey(e)
  return "s:" .. PN.Key(e.name)
end

-- Second line of a guild row, the columns that are switched on, "-" for unknown peer data.
-- extra: the columns of add-ons (GuildExt), already wrapped, a failing one answers nil.
local function guildSub(m, rights, peer, extra)
  local on, cols = GL.ColumnOn, columns("guild")
  local parts = {}
  if on(cols, "rank") and m.rankName ~= "" then
    parts[#parts + 1] = m.rankName
  end
  if on(cols, "level") and m.level > 0 then
    parts[#parts + 1] = string.format(L["guild.level"], m.level)
  end
  if on(cols, "zone") and m.zone ~= "" then
    parts[#parts + 1] = m.zone
  end
  if on(cols, "ilvl") then
    parts[#parts + 1] = string.format(L["guild.ilvl"], ilvlText(peer, m.name))
  end
  if on(cols, "jobs") then
    parts[#parts + 1] = string.format(L["guild.detail.jobs"], jobsText(peer, m.name))
  end
  if on(cols, "note") then
    local note, officer = GL.VisibleNotes(m, rights)
    parts[#parts + 1] = note
    parts[#parts + 1] = officer
  end
  for _, col in ipairs(extra) do
    local v = on(cols, col.id) and col.value(m)
    if type(v) == "string" and v ~= "" then
      parts[#parts + 1] = v
    end
  end
  return joinParts(parts)
end

local function seenSub(e, peer)
  local on, cols = GL.ColumnOn, columns("social")
  local parts = {}
  if on(cols, "race") and e.race ~= "" then
    parts[#parts + 1] = e.raceName ~= "" and e.raceName or e.race
  end
  if on(cols, "class") and e.class ~= "" then
    parts[#parts + 1] = className(e.class, "")
  end
  if on(cols, "level") and e.level > 0 then
    parts[#parts + 1] = string.format(L["guild.level"], e.level)
  end
  if on(cols, "zone") and e.zone ~= "" then
    parts[#parts + 1] = e.zone
  end
  if on(cols, "ilvl") then
    parts[#parts + 1] = string.format(L["guild.ilvl"], ilvlText(peer, e.name))
  end
  if on(cols, "jobs") then
    parts[#parts + 1] = string.format(L["guild.detail.jobs"], jobsText(peer, e.name))
  end
  if on(cols, "guild") and GL.GuildText(e) ~= "" then
    parts[#parts + 1] = GL.GuildText(e)
  end
  return joinParts(parts)
end

local function seenRight(e)
  local on, cols = GL.ColumnOn, columns("social")
  local parts = {}
  if on(cols, "seen") then
    parts[#parts + 1] = GL.PeerAgeText(ns.U.now() - e.t, L)
  end
  if on(cols, "source") and sourceText(e) ~= "" then
    parts[#parts + 1] = sourceText(e)
  end
  return joinParts(parts)
end

-- Item level, professions and their age for the detail card.
local function peerLines(lines, peer, name)
  lines[#lines + 1] = string.format(L["guild.detail.ilvl"], ilvlText(peer, name))
  lines[#lines + 1] = string.format(L["guild.detail.jobs"], jobsText(peer, name))
  local tip = GL.PeerTip(peer, ns.U.now(), L)
  if tip then
    lines[#lines + 1] = tip
  end
end

-- details: the sections of add-ons (GuildExt), their lines follow the item level and professions.
local function memberLines(m, rights, peer, details, ctx)
  local lines = {}
  if m.rankName ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.rank"], m.rankName)
  end
  local who = {}
  if m.level > 0 then
    who[#who + 1] = string.format(L["guild.level"], m.level)
  end
  who[#who + 1] = className(m.class, m.className)
  lines[#lines + 1] = joinParts(who)
  if m.zone ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.zone"], m.zone)
  end
  lines[#lines + 1] = string.format(L["guild.detail.last"], GL.LastOnlineText(m, L))
  local note, officer = GL.VisibleNotes(m, rights)
  if note then
    lines[#lines + 1] = string.format(L["guild.detail.note"], note)
  end
  if officer then
    lines[#lines + 1] = string.format(L["guild.detail.officer"], officer)
  end
  peerLines(lines, peer, m.name)
  for _, d in ipairs(details) do
    local extra = d.lines and d.lines(m, ctx)
    for _, line in ipairs(type(extra) == "table" and extra or {}) do
      if type(line) == "string" and line ~= "" then
        lines[#lines + 1] = line
      end
    end
  end
  return lines
end

-- Buttons of the add-on sections for one member: { { key, onClick } }, at most MAX_ACTIONS.
local function memberActions(m, details, ctx)
  local out = {}
  for _, d in ipairs(details) do
    local extra = d.actions and d.actions(m, ctx)
    for _, a in ipairs(type(extra) == "table" and extra or {}) do
      if #out < MAX_ACTIONS and type(a) == "table" and type(a.key) == "string" and type(a.onClick) == "function" then
        out[#out + 1] = {
          key = a.key,
          onClick = function()
            a.onClick(m, ctx)
          end,
        }
      end
    end
  end
  return out
end

-- Role, AFK, range and connection of a current group member, one "Group: ..." line.
local function liveLines(lines, live)
  if live.role then
    lines[#lines + 1] = string.format(L["guild.detail.role"], L["guild.role." .. live.role])
  end
  local state = {}
  if live.online == false then
    state[#state + 1] = L["guild.live.offline"]
  end
  if live.afk then
    state[#state + 1] = L["guild.live.afk"]
  end
  if live.range then
    state[#state + 1] = L["guild.live." .. live.range]
  end
  if #state > 0 then
    lines[#lines + 1] = string.format(L["guild.detail.live"], table.concat(state, ", "))
  end
end

-- live: SeenPlayers.Live of a current group member (its zone is the member's own), else nil.
local function seenLines(e, peer, live)
  live = live or {}
  local lines = {}
  if e.race ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.race"], e.raceName ~= "" and e.raceName or e.race)
  end
  local who = {}
  if e.level > 0 then
    who[#who + 1] = string.format(L["guild.level"], e.level)
  end
  if e.class ~= "" then
    who[#who + 1] = className(e.class, "")
  end
  if #who > 0 then
    lines[#lines + 1] = joinParts(who)
  end
  if GL.GuildText(e) ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.guild"], GL.GuildText(e))
  end
  if (e.title or "") ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.title"], e.title)
  end
  local status = {}
  if e.pvp == true then
    status[#status + 1] = L["guild.detail.pvp"]
  end
  if (tonumber(e.honor) or 0) > 0 then
    status[#status + 1] = string.format(L["guild.detail.honor"], e.honor)
  end
  if #status > 0 then
    lines[#lines + 1] = joinParts(status)
  end
  if live.zone then
    lines[#lines + 1] = string.format(L["guild.detail.zone"], live.zone)
  end
  liveLines(lines, live)
  local ago = GL.PeerAgeText(ns.U.now() - e.t, L)
  lines[#lines + 1] = e.zone ~= "" and string.format(L["guild.detail.seenIn"], ago, e.zone)
    or string.format(L["guild.detail.seen"], ago)
  local first = e.first or { t = e.t, src = e.src, zone = e.zone }
  local firstText =
    GL.FirstContactText(first, L, SOURCES[first.src] and L["guild.src." .. first.src] or "", dateText(first.t))
  if firstText ~= "" then
    lines[#lines + 1] = string.format(L["guild.detail.first"], firstText)
  end
  if type(e.who) == "table" and (tonumber(e.who.t) or 0) > 0 then
    local whoAgo = GL.PeerAgeText(ns.U.now() - e.who.t, L)
    lines[#lines + 1] = e.who.zone ~= "" and string.format(L["nearby.who.online"], whoAgo, e.who.zone)
      or string.format(L["nearby.who.onlineNoZone"], whoAgo)
  end
  peerLines(lines, peer, e.name)
  return lines
end

-- Detail card -----------------------------------------------------------------------------------------

local function newDetail(parent, id)
  local card = W.Card(parent, {})
  card.name = W.Text(card, { role = "h3", family = "heading" })
  card.name:SetPoint("TOPLEFT", PAD, -10)
  card.name:SetPoint("RIGHT", -PAD, 0)
  card.body = W.Text(card, { role = "ui", color = "textSecondary", wrap = true })
  card.body:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -6)
  card.whisper = W.Action(card, {
    label = "act.whisper",
    icon = "pencil",
    tooltip = "guild.whisper",
    width = 110,
    height = 24,
    onClick = function()
      whisper(card.target)
    end,
  })
  card.whisper.fgId = id .. "-whisper"
  card.whisper:SetPoint("BOTTOMLEFT", PAD, 10)
  card.close = W.Action(card, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    width = 110,
    height = 24,
    onClick = function()
      if card.onClose then
        card.onClose()
      end
    end,
  })
  card.close:SetPoint("LEFT", card.whisper, "RIGHT", GAP, 0)
  -- Buttons of add-on sections above "Whisper" (placed in fgGridLayout); list = { { key, onClick } }.
  card.actions = {}
  card.actionCount = 0
  function card:SetActions(list)
    for i, a in ipairs(list) do
      local b = self.actions[i]
      if not b then
        b = W.Button(self, { key = a.key, width = ACTION_WIDTH, height = 24 })
        b.fgId = id .. "-action-" .. i
        self.actions[i] = b
      end
      W.SetText(b.label, a.key)
      b:SetScript("OnClick", ns.Wrap("guildext-action", a.onClick))
      b:Show()
    end
    for i = #list + 1, #self.actions do
      self.actions[i]:Hide()
    end
    self.actionCount = #list
  end
  function card:fgGridLayout(width)
    self.body:SetWidth(width - PAD * 2)
    local h = 10 + self.name:GetStringHeight() + 6 + self.body:GetStringHeight() + 10 + 24 + 10
    -- The add-on buttons wrap into rows above "Whisper" when the card is narrow.
    local perRow = math.max(1, math.floor((width - PAD * 2 + GAP) / (ACTION_WIDTH + GAP)))
    for i = 1, self.actionCount do
      local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
      self.actions[i]:ClearAllPoints()
      self.actions[i]:SetPoint("BOTTOMLEFT", PAD + col * (ACTION_WIDTH + GAP), 10 + 24 + GAP + row * (24 + GAP))
    end
    h = h + math.ceil(self.actionCount / perRow) * (24 + GAP)
    self:SetHeight(h)
    return h
  end
  return card
end

-- A frame that lays out its widgets (f.items = { { frame, width, height, top, full } }) in rows and
-- wraps to the next row when the width is used up. The widgets are children of the frame, so hiding
-- it hides them. A full item takes a row of its own.
local function newFlow(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.items = {}
  function f:fgGridLayout(width)
    local x, y, rowHeight = 0, 0, 0
    for _, item in ipairs(f.items) do
      local w = item.full and width or item.width
      if x > 0 and (item.full or x + w > width) then
        x, y, rowHeight = 0, y - rowHeight - GAP, 0
      end
      item.frame:ClearAllPoints()
      item.frame:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - (item.top or 0))
      item.frame:SetWidth(w)
      x = item.full and width + 1 or x + w + GAP
      rowHeight = math.max(rowHeight, item.height)
    end
    local h = -y + rowHeight
    f:SetHeight(h)
    return h
  end
  return f
end

-- Page --------------------------------------------------------------------------------------------------

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local state = {
    tab = "guild",
    search = "",
    online = false,
    rank = "all",
    sort = "rank",
    socialSearch = "",
    race = "all",
    class = "all",
    socialSort = "recent",
    page = 1,
    sel = nil,
    rights = {},
  }
  local refresh, pick

  -- Add-ons (GuildExt): columns and detail sections are read again by syncExt() whenever one registers.
  local extColumns, extDetails = GE.Entries("column"), GE.Entries("detail")
  local syncExt
  local started = false
  local ctx = {
    Roster = GD.Get,
    Rights = GE.Rights,
    Refresh = function()
      refresh()
    end,
    Select = function(m)
      pick(guildKey(m), m.name)
    end,
    Selected = function()
      for _, m in ipairs(GD.Get().members) do
        if guildKey(m) == state.sel then
          return m
        end
      end
    end,
  }
  -- Tab bodies of add-ons by id, built once by syncExt().
  local extTabs = {}

  -- Banner of the demo mode: what it is, the rights of the demo character and the way out.
  local banner = W.Card(view.content, {})
  banner.text = W.Text(banner, { key = "guild.demo.banner", role = "ui", color = "warning", wrap = true })
  banner.text:SetPoint("TOPLEFT", PAD, -10)
  local roleOptions = {}
  for _, role in ipairs(ns.GuildDemo.ROLES) do
    roleOptions[#roleOptions + 1] = { value = role, key = "guild.demo.role." .. role }
  end
  banner.role = W.Dropdown(banner, {
    key = "guild.demo.rights",
    width = DROPDOWN_WIDTH,
    options = roleOptions,
    get = function()
      return GD.DemoRole() or ns.GuildDemo.DEFAULT_ROLE
    end,
    set = GD.SetDemoRole,
  })
  banner.role.fgId = "guild-demo-role"
  banner.stop = W.Action(banner, {
    label = "act.close",
    icon = "close",
    tooltip = "guild.demo.end",
    width = STOP_WIDTH,
    height = 24,
    onClick = function()
      GD.SetDemo(false)
    end,
  })
  banner.stop.fgId = "guild-demo-end"
  function banner:fgGridLayout(width)
    self.text:SetWidth(width - PAD * 2)
    local top = 10 + self.text:GetStringHeight() + GAP
    self.role:SetWidth(DROPDOWN_WIDTH)
    self.role:ClearAllPoints()
    self.role:SetPoint("TOPLEFT", PAD, -top)
    self.stop:ClearAllPoints()
    local h
    if width >= PAD * 2 + DROPDOWN_WIDTH + GAP + STOP_WIDTH then
      -- Next to the dropdown, level with its box below the label.
      self.stop:SetPoint("TOPLEFT", PAD + DROPDOWN_WIDTH + GAP, -(top + 18))
      h = top + 46 + 10
    else
      self.stop:SetPoint("TOPLEFT", PAD, -(top + 46 + GAP))
      h = top + 46 + GAP + 24 + 10
    end
    self:SetHeight(h)
    return h
  end
  s:Add(banner, { gap = 12 })

  -- Hint card: management lives in the add-on GildenManager.
  local manager = W.Card(view.content, {})
  manager.text = W.Text(manager, { key = "guild.manager", role = "ui", color = "textSecondary", wrap = true })
  manager.text:SetPoint("TOPLEFT", PAD, -10)
  manager.state = W.Text(manager, { role = "micro", color = "textMuted" })
  manager.state:SetPoint("TOPLEFT", manager.text, "BOTTOMLEFT", 0, -4)
  manager.pkg = ns.PackageUI.Banner(manager, MANAGER_ADDON, {
    onLoaded = function()
      syncExt()
    end,
    onResize = function()
      view:Layout()
    end,
  })
  manager.pkg:SetPoint("TOPLEFT", manager.text, "BOTTOMLEFT", 0, -4)
  function manager:fgGridLayout(width)
    self.text:SetWidth(width - PAD * 2)
    local h = 10 + self.text:GetStringHeight() + 4
    if self.pkg:IsShown() then
      self.pkg:SetWidth(width - PAD * 2)
      h = h + self.pkg:Fit(width - PAD * 2) + 10
    else
      h = h + self.state:GetStringHeight() + 10
    end
    self:SetHeight(h)
    return h
  end
  s:Add(manager, { gap = 12 })

  local groups = { guild = {}, social = {} }
  local function add(group, item, opts)
    groups[group][#groups[group] + 1] = item
    s:Add(item, opts)
    return item
  end

  -- The tab bar cannot grow, so it lives in a holder whose bar is replaced when an add-on adds a tab.
  local tabs = CreateFrame("Frame", nil, view.content)
  tabs.fgId = "guild-tabs"
  function tabs:Select(id)
    self.bar:Select(id)
  end
  local tabSignature
  -- Returns true when the bar was built anew.
  local function syncBar()
    local list = { { id = "guild", key = "guild.tab.guild" }, { id = "social", key = "guild.tab.social" } }
    for _, t in ipairs(GE.Entries("tab")) do
      if extTabs[t.id] then
        list[#list + 1] = { id = t.id, key = t.key }
      end
    end
    local parts = {}
    for i, t in ipairs(list) do
      parts[i] = t.id .. "=" .. t.key
    end
    local signature = table.concat(parts, ",")
    if signature == tabSignature then
      return false
    end
    tabSignature = signature
    if tabs.bar then
      tabs.bar:Hide()
    end
    tabs.bar = W.Tabs(tabs, {
      tabs = list,
      onSelect = function(id)
        state.tab = id
        refresh()
      end,
    })
    tabs.bar:SetAllPoints()
    tabs.buttons = tabs.bar.buttons
    return true
  end
  s:Add(tabs, { height = 28, gap = 12 })
  -- One detail card per tab, each between the filters and the list of its tab.
  local detailGuild, detailSocial = newDetail(view.content, "guild"), newDetail(view.content, "social")

  function pick(key, target)
    state.sel = state.sel ~= key and key or nil
    detailGuild.target, detailSocial.target = target, target
    refresh()
  end
  local function closeDetail()
    state.sel = nil
    refresh()
  end
  detailGuild.onClose, detailSocial.onClose = closeDetail, closeDetail

  -- Column switches of a tab, one checkbox per column.
  local function addColumnBox(f, tab, col)
    local id = col.id
    local box = W.Checkbox(f, {
      key = col.key,
      get = function()
        return GL.ColumnOn(columns(tab), id)
      end,
      set = function(v)
        Store.set("settings.guildCols." .. tab .. "." .. id, v)
        refresh()
      end,
    })
    box.fgId = "guild-col-" .. tab .. "-" .. id
    local item = { frame = box, width = CHECK_WIDTH, height = 22 }
    f.items[#f.items + 1] = item
    return item
  end

  local function newColumns(tab)
    local f = newFlow(view.content)
    for _, id in ipairs(GL.COLUMNS[tab]) do
      addColumnBox(f, tab, { id = id, key = "guild.col." .. id })
    end
    f.base, f.ext = #f.items, {}
    return f
  end

  -- Switches of add-on columns (guild tab): one per id, after the page's own, in the order of the entries.
  local function syncColumns(f)
    for _, col in ipairs(extColumns) do
      if not f.ext[col.id] then
        f.ext[col.id] = addColumnBox(f, "guild", col)
      end
    end
    local items = {}
    for i = 1, f.base do
      items[i] = f.items[i]
    end
    for _, col in ipairs(extColumns) do
      items[#items + 1] = f.ext[col.id]
    end
    f.items = items
  end

  -- A dropdown whose entries follow the data; `choices` = { { value, text } }, `all` the key of "all".
  local function syncOptions(options, dropdown, allKey, choices, current)
    for i = #options, 1, -1 do
      options[i] = nil
    end
    options[1] = { value = "all", key = allKey }
    local known = current == "all"
    for _, c in ipairs(choices) do
      options[#options + 1] = { value = c.value, text = c.text }
      known = known or c.value == current
    end
    dropdown.Refresh()
    return known and current or "all"
  end

  local function listHeight(opts, n)
    opts.height = K.scaledHeight(ROW_HEIGHT) * math.min(math.max(n, 1), MAX_ROWS)
  end

  -- Guild tab ---------------------------------------------------------------------------------------
  local notice = add("guild", ns.AddParagraph(view, nil, { role = "text", color = "textSecondary", gap = 8 }))
  -- Only without a guild: shows the sample guild. Placed by refresh(), not part of a group.
  local demoStart = W.Action(view.content, {
    label = "act.show",
    icon = "eye",
    tooltip = "guild.demo.start",
    width = DEMO_START_WIDTH,
    height = 24,
    onClick = function()
      GD.SetDemo(true)
    end,
  })
  demoStart.fgId = "guild-demo-start"
  s:Add(demoStart, { height = 24, width = DEMO_START_WIDTH, gap = 8 })
  local title =
    add("guild", ns.AddParagraph(view, nil, { role = "h3", family = "heading", color = "accent2", gap = 2 }))
  local onlineLine = add("guild", ns.AddParagraph(view, nil, { role = "ui", color = "text", gap = 4 }))
  local motd = CreateFrame("Button", nil, view.content)
  motd.text = W.Text(motd, { role = "ui", color = "textSecondary" })
  motd.text:SetPoint("LEFT")
  motd.text:SetPoint("RIGHT")
  local function showMotd(self)
    ns.ShowTooltip(self, L["guild.motd.title"], self.full ~= "" and self.full or L["guild.motd.empty"])
  end
  motd:SetScript("OnEnter", showMotd)
  motd:SetScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(motd, showMotd)
  add("guild", motd, { height = 18, gap = 6 })
  local levelsLine = add("guild", ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 2 }))
  local classesLine = add("guild", ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 10 }))

  local controls = newFlow(view.content)
  local search = W.EditBox(controls, {
    placeholder = "guild.search",
    clear = true,
    onChange = function(text)
      state.search = text
      refresh()
    end,
  })
  search.fgId = "guild-search"
  local onlyOnline = W.Toggle(controls, {
    key = "guild.onlyOnline",
    get = function()
      return state.online
    end,
    set = function(v)
      state.online = v
      refresh()
    end,
  })
  onlyOnline.fgId = "guild-online"
  local rankOptions = {}
  local rank = W.Dropdown(controls, {
    key = "guild.rank",
    width = DROPDOWN_WIDTH,
    options = rankOptions,
    get = function()
      return state.rank
    end,
    set = function(v)
      state.rank = v
      refresh()
    end,
  })
  rank.fgId = "guild-rank"
  local sortOptions = {}
  for _, mode in ipairs(GL.SORTS) do
    sortOptions[#sortOptions + 1] = { value = mode, key = "guild.sort." .. mode }
  end
  local sort = W.Dropdown(controls, {
    key = "guild.sort",
    width = DROPDOWN_WIDTH,
    options = sortOptions,
    get = function()
      return state.sort
    end,
    set = function(v)
      state.sort = v
      refresh()
    end,
  })
  sort.fgId = "guild-sort"
  controls.items = {
    { frame = search, full = true, height = SEARCH_HEIGHT },
    { frame = onlyOnline, width = TOGGLE_WIDTH, height = 46, top = 18 },
    { frame = rank, width = DROPDOWN_WIDTH, height = 46 },
    { frame = sort, width = DROPDOWN_WIDTH, height = 46 },
  }
  add("guild", controls, { gap = 8 })
  add("guild", ns.AddParagraph(view, "guild.cols", { role = "micro", color = "textMuted", gap = 2 }))
  local guildColumns = add("guild", newColumns("guild"), { gap = 8 })
  local count = add("guild", ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 4 }))
  s:Add(detailGuild, { gap = 12 })

  local guildOpts = { gap = 12 }
  local guildList = K.NewList(view.content, {
    rowHeight = ROW_HEIGHT,
    bind = function(m)
      local peer = peerOf(m.name, m.guid)
      local cols = columns("guild")
      return {
        title = coloredName(m.name, m.class),
        sub = guildSub(m, state.rights, peer, extColumns),
        right = GL.ColumnOn(cols, "last")
            and (m.online and Theme.hexText("success", L["guild.last.online"]) or GL.LastOnlineText(m, L))
          or "",
        selected = state.sel == guildKey(m),
        iconPaint = classIcon(m.class),
        tooltip = GL.PeerTip(peer, ns.U.now(), L),
      }
    end,
    onClick = function(m)
      pick(guildKey(m), m.name)
    end,
  })
  add("guild", guildList, guildOpts)

  -- Social tab --------------------------------------------------------------------------------------
  local socialInfo = add("social", ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 6 }))
  local socialControls = newFlow(view.content)
  local socialSearch = W.EditBox(socialControls, {
    placeholder = "guild.search",
    clear = true,
    onChange = function(text)
      state.socialSearch, state.page = text, 1
      refresh()
    end,
  })
  socialSearch.fgId = "social-search"
  local raceOptions, classOptions = {}, {}
  local raceDropdown = W.Dropdown(socialControls, {
    key = "guild.race",
    width = DROPDOWN_WIDTH,
    options = raceOptions,
    get = function()
      return state.race
    end,
    set = function(v)
      state.race, state.page = v, 1
      refresh()
    end,
  })
  raceDropdown.fgId = "social-race"
  local classDropdown = W.Dropdown(socialControls, {
    key = "guild.class",
    width = DROPDOWN_WIDTH,
    options = classOptions,
    get = function()
      return state.class
    end,
    set = function(v)
      state.class, state.page = v, 1
      refresh()
    end,
  })
  classDropdown.fgId = "social-class"
  local socialSortOptions = {}
  for _, mode in ipairs(GL.SEEN_SORTS) do
    socialSortOptions[#socialSortOptions + 1] = { value = mode, key = "guild.sort." .. mode }
  end
  local socialSort = W.Dropdown(socialControls, {
    key = "guild.sort",
    width = DROPDOWN_WIDTH,
    options = socialSortOptions,
    get = function()
      return state.socialSort
    end,
    set = function(v)
      state.socialSort, state.page = v, 1
      refresh()
    end,
  })
  socialSort.fgId = "social-sort"
  socialControls.items = {
    { frame = socialSearch, full = true, height = SEARCH_HEIGHT },
    { frame = raceDropdown, width = DROPDOWN_WIDTH, height = 46 },
    { frame = classDropdown, width = DROPDOWN_WIDTH, height = 46 },
    { frame = socialSort, width = DROPDOWN_WIDTH, height = 46 },
  }
  add("social", socialControls, { gap = 8 })
  add("social", ns.AddParagraph(view, "guild.cols", { role = "micro", color = "textMuted", gap = 2 }))
  add("social", newColumns("social"), { gap = 8 })
  local socialCount = add("social", ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 4 }))

  local pager = newFlow(view.content)
  local prev = W.Action(pager, {
    label = "act.back",
    icon = "chevron-left",
    tooltip = "guild.prev",
    width = PAGER_BUTTON,
    height = 24,
    onClick = function()
      state.page = state.page - 1
      refresh()
    end,
  })
  prev.fgId = "social-prev"
  local nextPage = W.Action(pager, {
    label = "act.next",
    icon = "chevron-right",
    tooltip = "guild.next",
    width = PAGER_BUTTON,
    height = 24,
    onClick = function()
      state.page = state.page + 1
      refresh()
    end,
  })
  nextPage.fgId = "social-next"
  local pageLabel = W.Text(pager, { role = "ui", color = "textSecondary" })
  pager.items = {
    { frame = prev, width = PAGER_BUTTON, height = 24 },
    { frame = nextPage, width = PAGER_BUTTON, height = 24 },
    { frame = pageLabel, width = 140, height = 24 },
  }
  add("social", pager, { gap = 8 })
  s:Add(detailSocial, { gap = 12 })

  local socialOpts = { gap = 12 }
  local socialList = K.NewList(view.content, {
    rowHeight = ROW_HEIGHT,
    bind = function(e)
      local peer = peerOf(e.name, e.guid)
      return {
        title = coloredName(e.name, e.class),
        sub = seenSub(e, peer),
        right = seenRight(e),
        selected = state.sel == seenKey(e),
        iconPaint = classIcon(e.class),
        tooltip = GL.PeerTip(peer, ns.U.now(), L),
        actions = rowActions(e, refresh),
      }
    end,
    onClick = function(e)
      pick(seenKey(e), e.name)
    end,
  })
  add("social", socialList, socialOpts)

  local function showGroup(name, shown)
    for _, item in ipairs(groups[name]) do
      item:SetShown(shown)
    end
  end

  local function hideExtTabs()
    for id in pairs(extTabs) do
      showGroup("ext:" .. id, false)
    end
  end

  -- Builds the body of every registered tab once; a build that failed is not tried again until the
  -- add-on registers the tab anew.
  local tried = {}
  local function syncTabs()
    for _, t in ipairs(GE.Entries("tab")) do
      if extTabs[t.id] then
        extTabs[t.id].onShow = t.onShow
      elseif tried[t.id] ~= t.build then
        tried[t.id] = t.build
        local body = t.build(view.content, ctx)
        if type(body) == "table" and body.SetShown then
          if not body.fgGridLayout then
            function body:fgGridLayout()
              return self:GetHeight()
            end
          end
          extTabs[t.id] = { body = body, onShow = t.onShow }
          groups["ext:" .. t.id] = { body }
          s:Add(body, { gap = 12 })
          body:Hide()
        end
      end
    end
  end

  -- Picks up what add-ons registered (also after the page was built): tab bodies, the tab bar, column
  -- switches and detail lines. Selection, filters and page stay in `state`.
  function syncExt()
    extColumns, extDetails = GE.Entries("column"), GE.Entries("detail")
    syncTabs()
    syncColumns(guildColumns)
    local rebuilt = syncBar()
    if not started then
      return
    end
    if rebuilt then
      -- Selecting paints the new bar and refreshes the page.
      tabs:Select(state.tab)
    else
      refresh()
    end
  end
  syncExt()

  -- Name and lines of a guild member in the detail card, plus the buttons of add-on sections.
  local function showMember(m)
    detailGuild.name:SetText(coloredName(m.name, m.class))
    detailGuild.body:SetText(table.concat(memberLines(m, state.rights, peerOf(m.name, m.guid), extDetails, ctx), "\n"))
    detailGuild:SetActions(memberActions(m, extDetails, ctx))
  end

  local function refreshGuild()
    local snap = GD.Get()
    showGroup("social", false)
    hideExtTabs()
    local ready = snap.inGuild and snap.loaded
    showGroup("guild", ready)
    notice:SetShown(not ready)
    if not ready then
      notice:SetText(L[snap.inGuild and "guild.loading" or "guild.none"])
      state.sel = nil
      return
    end
    state.rights = GD.Rights()
    title:SetText(snap.name)
    onlineLine:SetText(string.format(L["guild.online"], snap.online, #snap.members))
    motd.full = snap.motd
    motd.text:SetText(snap.motd ~= "" and GL.Truncate(snap.motd, GL.MOTD_LENGTH) or L["guild.motd.empty"])
    local stats = GL.Stats(snap.members)
    local levels, classes = {}, {}
    for _, b in ipairs(stats.levels) do
      levels[#levels + 1] = GL.LevelRange(b.lo) .. ": " .. b.count
    end
    for _, c in ipairs(stats.classes) do
      classes[#classes + 1] = className(c.class, "") .. ": " .. c.count
    end
    levelsLine:SetText(string.format(L["guild.stats.levels"], table.concat(levels, ", ")))
    classesLine:SetText(string.format(L["guild.stats.classes"], table.concat(classes, ", ")))
    local ranks = {}
    for _, r in ipairs(snap.ranks) do
      ranks[#ranks + 1] = { value = r.index, text = r.name }
    end
    state.rank = syncOptions(rankOptions, rank, "guild.rank.all", ranks, state.rank)
    onlyOnline.Refresh()
    sort.Refresh()
    local rows = GL.Sort(
      GL.Filter(snap.members, {
        online = state.online,
        rank = state.rank ~= "all" and state.rank or nil,
        search = state.search,
        rights = state.rights,
      }),
      state.sort
    )
    count:SetText(#rows == 0 and L["guild.empty"] or string.format(L["guild.count"], #rows, #snap.members))
    listHeight(guildOpts, #rows)
    guildList:SetData(rows)
    local picked
    for _, m in ipairs(rows) do
      if guildKey(m) == state.sel then
        picked = m
      end
    end
    if picked then
      showMember(picked)
    else
      state.sel = nil
    end
  end

  local function refreshSocial()
    showGroup("guild", false)
    hideExtTabs()
    showGroup("social", true)
    local demo = GD.IsDemo()
    local list = demo and GD.DemoSeen() or SP.List()
    socialInfo:SetText(
      demo and L["guild.demo.seen"]
        or L["guild.seen.local"]
          .. (SP.Enabled() and "" or "\n" .. L["guild.seen.off"])
          .. "\n"
          .. L["guild.seen.privacy"]
    )
    local races, classes = {}, {}
    for _, c in ipairs(GL.SeenChoices(list, "race")) do
      races[#races + 1] = { value = c.value, text = c.label }
    end
    for _, c in ipairs(GL.SeenChoices(list, "class")) do
      classes[#classes + 1] = { value = c.value, text = className(c.value, "") }
    end
    state.race = syncOptions(raceOptions, raceDropdown, "guild.race.all", races, state.race)
    state.class = syncOptions(classOptions, classDropdown, "guild.class.all", classes, state.class)
    socialSort.Refresh()
    local rows = GL.SeenSort(
      GL.SeenFilter(list, {
        race = state.race ~= "all" and state.race or nil,
        class = state.class ~= "all" and state.class or nil,
        search = state.socialSearch,
      }),
      state.socialSort
    )
    local items, page, pages = GL.Page(rows, state.page)
    state.page = page
    socialCount:SetText(
      #list == 0 and L["guild.seen.empty"]
        or (#rows == 0 and L["guild.empty"] or string.format(L["guild.count"], #rows, #list))
    )
    pageLabel:SetText(string.format(L["guild.page"], page, pages))
    if page > 1 then
      prev:Enable()
    else
      prev:Disable()
    end
    if page < pages then
      nextPage:Enable()
    else
      nextPage:Disable()
    end
    listHeight(socialOpts, #items)
    socialList:SetData(items)
    local picked
    for _, e in ipairs(items) do
      if seenKey(e) == state.sel then
        picked = e
      end
    end
    if picked then
      local live = not demo and SP.Live(picked.guid, picked.name) or nil
      detailSocial.name:SetText(coloredName(picked.name, picked.class))
      detailSocial.body:SetText(table.concat(seenLines(picked, peerOf(picked.name, picked.guid), live), "\n"))
      detailSocial:SetActions({})
    else
      state.sel = nil
    end
  end

  -- Tab of an add-on: needs the loaded roster like the guild tab, the selection may be any member.
  local function refreshExt(id)
    local snap = GD.Get()
    showGroup("guild", false)
    showGroup("social", false)
    hideExtTabs()
    local ready = snap.inGuild and snap.loaded
    notice:SetShown(not ready)
    if not ready then
      notice:SetText(L[snap.inGuild and "guild.loading" or "guild.none"])
      state.sel = nil
      return
    end
    state.rights = GD.Rights()
    showGroup("ext:" .. id, true)
    local picked = ctx.Selected()
    if picked then
      showMember(picked)
    else
      state.sel = nil
    end
    if extTabs[id].onShow then
      extTabs[id].onShow(ctx, extTabs[id].body)
    end
  end

  -- Loads the add-on once per session when there is something to extend (a guild or the demo) and the
  -- player switched it on. True when it was loaded: syncExt() has refreshed the page then.
  local function autoLoad()
    if autoTried or GE.Loaded() or not (GD.IsDemo() or GD.Get().inGuild) then
      return false
    end
    if ns.PackageUI.State(MANAGER_ADDON) ~= "idle" then
      return false
    end
    local ok, reason = ns.PackageUI.Enable(MANAGER_ADDON)
    autoTried = reason ~= "COMBAT"
    if ok then
      syncExt()
    end
    return ok
  end

  function refresh()
    if autoLoad() then
      return
    end
    local demo = GD.IsDemo()
    banner:SetShown(demo)
    if demo then
      banner.role.Refresh()
    end
    local hint = not GE.Loaded() and state.tab == "guild"
    manager:SetShown(hint)
    if hint then
      -- The banner says what is wrong and offers the button; the state line stays for "loaded".
      local offered = manager.pkg:Update(true)
      manager.state:SetShown(not offered)
      manager.state:SetText(
        string.format(
          L["guild.manager.state"],
          L[MANAGER_STATE[ns.PackageState(MANAGER_ADDON)] or "guild.manager.missing"]
        )
      )
    end
    if state.tab == "guild" then
      refreshGuild()
    elseif extTabs[state.tab] then
      refreshExt(state.tab)
    else
      refreshSocial()
    end
    demoStart:SetShown(notice:IsShown() and not GD.Get().inGuild)
    detailGuild:SetShown(state.sel ~= nil and state.tab ~= "social")
    detailSocial:SetShown(state.sel ~= nil and state.tab == "social")
    view:Layout()
  end

  function view:Show(params)
    -- Before `started`: the registrations of the add-on must not refresh a page that is not ready yet.
    autoLoad()
    started = true
    local want = params and params[1]
    if want == "social" or want == "seen" then
      state.tab = "social"
    elseif want == "guild" or extTabs[want] then
      state.tab = want
    end
    state.sel = nil
    GD.Request()
    tabs:Select(state.tab)
  end
  view.state = state

  ns.On("FG_GUILD_UPDATE", function()
    if container:IsVisible() and (state.tab == "guild" or extTabs[state.tab]) then
      refresh()
    end
  end)
  ns.On("FG_DEMO_UPDATE", function()
    if container:IsVisible() then
      refresh()
    end
  end)
  -- An add-on registered (late, when it is loaded on demand), not while the package button loads it.
  ns.On("FG_GUILDEXT_CHANGED", function()
    if not ns.PackageUI.Busy() then
      syncExt()
    end
  end)
  ns.On("FG_SEEN_UPDATE", function()
    if container:IsVisible() and state.tab == "social" then
      refresh()
    end
  end)
  return view
end

-- The switch for the friendly player name plates: state line, button and the explanation. Only a click
-- changes the game's setting.
local function addPlates(view)
  local s = view.stack
  local state = W.Text(view.content, { role = "ui", color = "textSecondary", wrap = true })
  local function paint()
    state:SetText(string.format(L["guild.plates.state"], L["guild.plates." .. ns.NearbyContacts.PlatesState()]))
  end
  state.Refresh = paint
  ns.Bind(state, paint)
  s:Add(state, { gap = 4 })
  local row = ns.FlowLayout.ButtonRow(view.content, {
    {
      id = "plates",
      label = "act.enable",
      icon = "check",
      tooltip = "guild.plates.enable",
      fgId = "guild-plates",
      onClick = function()
        local ok, reason = ns.NearbyContacts.EnablePlates()
        ns.Notify(L[ok and "guild.plates.done" or "guild.plates." .. reason], ok and "success" or "warning")
        paint()
      end,
    },
  })
  s:Add(row, { gap = 4 })
  ns.AddParagraph(view, "guild.plates.hint", { role = "micro", color = "textMuted", gap = 8 })
end

-- The button that opens the nearby detection probe (also placed by the settings page on its own). It
-- exists only when an extension registers the probe.
function P.AddProbe(view)
  local tool = ns.DevTools.byId.nearbyprobe
  if not tool then
    return
  end
  local probe = W.Action(view.content, {
    label = "act.test",
    icon = "search",
    tooltip = "nearbyprobe.open",
    width = 180,
    onClick = tool.run,
  })
  probe.fgId = "guild-nearbyprobe"
  view.stack:Add(probe, { height = 26, width = 180, gap = 6 })
end

-- The settings section: keep the recently seen list, include targets, clear. opts.probe == false
-- leaves the probe button out.
function P.AddSettings(view, opts)
  local s = view.stack
  ns.AddHeading(view, "guild.set.heading")
  for _, item in ipairs({
    { "seenSave", "guild.set.seen", SP.Enabled, "guild-seen" },
    { "seenTargets", "guild.set.targets", SP.Targets, "guild-targets" },
    { "groupInspect", "guild.set.inspect", ns.GroupInspect.Switch, "guild-inspect", "guild.set.inspectHint" },
    { "nearbyDetect", "guild.set.nearby", ns.NearbyContacts.Switch, "guild-nearby", "guild.set.nearbyHint" },
    { "peerShare", "guild.set.share", ns.PeerComm.Sharing, "guild-share", "guild.set.shareHint" },
    { "peerShareGuild", "guild.set.shareGuild", ns.PeerComm.SharingGuild, "guild-share-guild" },
  }) do
    local toggle = W.Toggle(view.content, {
      key = item[2],
      get = item[3],
      set = function(v)
        Store.set("settings." .. item[1], v)
      end,
    })
    toggle.fgId = item[4]
    s:Add(toggle, { height = 24, gap = item[5] and 2 or 6 })
    if item[5] then
      ns.AddParagraph(view, item[5], { role = "micro", color = "textMuted", gap = 6 })
    end
    if item[1] == "nearbyDetect" then
      addPlates(view)
    end
  end
  if not (opts and opts.probe == false) then
    P.AddProbe(view)
  end
  local clear = W.Action(view.content, {
    label = "act.clear",
    icon = "trash",
    tooltip = "guild.set.clear",
    width = 180,
    onClick = function()
      SP.ConfirmClear()
    end,
  })
  clear.fgId = "guild-clear"
  s:Add(clear, { height = 26, width = 180, gap = 6 })
  local demo = W.Action(view.content, {
    label = "act.show",
    icon = "eye",
    tooltip = "guild.demo.start",
    width = 180,
    onClick = function()
      GD.SetDemo(true)
      ns.Main.Show("guild")
    end,
  })
  demo.fgId = "guild-demo-settings"
  s:Add(demo, { height = 26, width = 180, gap = 6 })
  ns.AddParagraph(view, "guild.seen.local", { role = "micro", color = "textMuted" })
end

ns.RegisterPage({
  id = "guild",
  order = 30,
  group = "character",
  title = "page.guild",
  icon = ns.ICONS.guild,
  aliases = { "gilde", "guild", "gilden", "kontakte", "contacts" },
  build = build,
})
