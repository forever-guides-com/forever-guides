-- Page "Kontakte" (/fg kontakte, /fg contacts, /fg sozial, /fg social): the players met in groups,
-- dungeons, trades and as targets, with its own selection and detail card. The widgets and the filling
-- are ContactsView.lua, the shared helpers are GuildKit.lua. Contacts are not part of the guild page;
-- its old deep links (guild/social, guild/seen) lead here.
local _, ns = ...
local W, Store = ns.W, ns.Store
local GD, Kit, CV = ns.GuildData, ns.GuildKit, ns.ContactsView

local P = {}
ns.ContactsPage = P

ns.AddLocale("enUS", {
  ["page.contacts"] = "Contacts",
  ["contacts.set.heading"] = "Contacts",
  ["guild.race"] = "Race",
  ["guild.race.all"] = "All races",
  ["guild.class"] = "Class",
  ["guild.class.all"] = "All classes",
  ["guild.sort.recent"] = "Last seen",
  ["guild.page"] = "Page %d of %d",
  ["guild.prev"] = "Back",
  ["guild.next"] = "Next",
  ["guild.col.race"] = "Race",
  ["guild.col.class"] = "Class",
  ["guild.col.seen"] = "Last seen",
  ["guild.col.source"] = "First contact",
  ["guild.col.guild"] = "Guild",
  ["guild.detail.race"] = "Race: %s",
  ["guild.detail.seen"] = "Last seen: %s",
  ["guild.detail.seenIn"] = "Last seen: %s in %s",
  ["guild.detail.first"] = "First contact: %s",
  ["guild.on"] = "on %s",
  ["guild.in"] = "in %s",
  ["guild.date"] = "%m/%d",
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
  ["guild.whisper.tip"] = "Fills the chat box, nothing is sent.",
  ["guild.invite"] = "Invite",
  ["guild.invite.tip"] = "Invites the player to your group.",
  ["guild.seen.empty"] = "Nobody seen yet.",
  ["guild.seen.off"] = "Saving is off (settings)",
  ["guild.seen.privacy"] = "Item level via inspect, jobs only from add-on users who share. Contacts are refreshed when they show up as a visible unit.",
  ["guild.src.group"] = "Group",
  ["guild.src.raid"] = "Raid",
  ["guild.src.dungeon"] = "Dungeon",
  ["guild.src.trade"] = "Trade",
  ["guild.src.guild"] = "Guild",
  ["guild.src.target"] = "Target",
  ["guild.set.targets"] = "Include targets",
  ["guild.set.clear"] = "Clear list",
  ["guild.set.clearTitle"] = "Clear list",
  ["guild.set.clearText"] = "Delete all recently seen players?",
  ["guild.set.cleared"] = "List cleared",
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
})
ns.AddLocale("deDE", {
  ["page.contacts"] = "Kontakte",
  ["contacts.set.heading"] = "Kontakte",
  ["guild.race"] = "Rasse",
  ["guild.race.all"] = "Alle Rassen",
  ["guild.class"] = "Klasse",
  ["guild.class.all"] = "Alle Klassen",
  ["guild.sort.recent"] = "Zuletzt gesehen",
  ["guild.page"] = "Seite %d von %d",
  ["guild.prev"] = "Zurück",
  ["guild.next"] = "Weiter",
  ["guild.col.race"] = "Rasse",
  ["guild.col.class"] = "Klasse",
  ["guild.col.seen"] = "Zuletzt gesehen",
  ["guild.col.source"] = "Erstkontakt",
  ["guild.col.guild"] = "Gilde",
  ["guild.detail.race"] = "Rasse: %s",
  ["guild.detail.seen"] = "Zuletzt gesehen: %s",
  ["guild.detail.seenIn"] = "Zuletzt gesehen: %s in %s",
  ["guild.detail.first"] = "Erstkontakt: %s",
  ["guild.on"] = "am %s",
  ["guild.in"] = "in %s",
  ["guild.date"] = "%d.%m.",
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
  ["guild.whisper.tip"] = "Füllt die Chatzeile, es wird nichts gesendet.",
  ["guild.invite"] = "Einladen",
  ["guild.invite.tip"] = "Lädt den Spieler in deine Gruppe ein.",
  ["guild.seen.empty"] = "Noch niemand gesehen.",
  ["guild.seen.off"] = "Speichern ist aus (Einstellungen)",
  ["guild.seen.privacy"] = "Itemlevel per Betrachten, Berufe nur von Addon-Nutzern mit Freigabe. Kontakte werden aktualisiert, wenn sie als sichtbare Einheit auftauchen.",
  ["guild.src.group"] = "Gruppe",
  ["guild.src.raid"] = "Raid",
  ["guild.src.dungeon"] = "Dungeon",
  ["guild.src.trade"] = "Handel",
  ["guild.src.guild"] = "Gilde",
  ["guild.src.target"] = "Ziel",
  ["guild.set.targets"] = "Ziele aufnehmen",
  ["guild.set.clear"] = "Liste löschen",
  ["guild.set.clearTitle"] = "Liste löschen",
  ["guild.set.clearText"] = "Alle zuletzt gesehenen Spieler löschen?",
  ["guild.set.cleared"] = "Liste gelöscht",
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
})

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  -- Filters, sorting and page of the contacts view live in state.contacts.
  local state = { sel = nil, contacts = { search = "", race = "all", class = "all", sort = "recent", page = 1 } }
  local detail = Kit.NewDetail(view.content, "social")
  local refresh

  local function pick(key, target)
    state.sel = state.sel ~= key and key or nil
    detail.target = target
    refresh()
  end
  detail.onClose = function()
    state.sel = nil
    refresh()
  end

  local contacts = CV.Build({
    view = view,
    container = container,
    state = state,
    detail = detail,
    add = function(item, opts)
      s:Add(item, opts)
      return item
    end,
    pick = pick,
    refresh = function()
      refresh()
    end,
  })

  function refresh()
    contacts.Refresh()
    detail:SetShown(state.sel ~= nil)
    view:Layout()
  end

  function view:Show()
    state.sel = nil
    -- The invite button reads the guild roster (offline members).
    GD.Request()
    refresh()
  end
  view.state = state

  ns.On("FG_GUILD_SOURCE", function()
    if container:IsVisible() then
      refresh()
    end
  end)
  return view
end

-- The settings card of the contacts: include targets, detect players nearby, clear the list. The switch
-- for storing the data of seen players is on the guild card (GuildPage.AddSettings).
function P.AddSettings(view)
  local s = view.stack
  ns.AddHeading(view, "contacts.set.heading")
  for _, item in ipairs({
    { "seenTargets", "guild.set.targets", ns.SeenPlayers.Targets, "guild-targets" },
    { "nearbyDetect", "guild.set.nearby", ns.NearbyContacts.Switch, "guild-nearby", "guild.set.nearbyHint" },
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
      CV.AddPlates(view)
    end
  end
  CV.AddClear(view)
  CV.AddLocalNote(view)
end

ns.RegisterPage({
  id = "contacts",
  order = 260,
  group = "social",
  title = "page.contacts",
  icon = ns.ICONS.contacts,
  aliases = { "kontakte", "contacts", "sozial", "social" },
  build = build,
})
