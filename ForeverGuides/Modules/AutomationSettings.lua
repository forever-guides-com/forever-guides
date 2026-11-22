-- Settings section "Automation" (Modules/AutoGuard.lua and the helpers it guards). One switch per
-- helper with a short tooltip, the stop key, chat messages, delays and the exception lists of the
-- quest helper. Every helper is off by default; the explanation shows when one is switched on.
local _, ns = ...
local W, Store = ns.W, ns.Store
local Guard = ns.AutoGuard

local S = {}
ns.AutomationSettings = S

ns.AddLocale("enUS", {
  ["auto.set.heading"] = "Automation",
  ["auto.card.repair"] = "Repair at the vendor",
  ["auto.card.quests"] = "Quest automation",
  ["auto.card.questExceptions"] = "Exceptions",
  ["auto.card.summon"] = "Summon and death",
  ["auto.card.duels"] = "Duels and strangers",
  ["auto.card.errors"] = "Hide error messages",
  ["auto.set.hint"] = "- Everything is off until you switch it on\n- Hold the stop key to pause every helper",
  ["auto.set.key"] = "Stop key",
  ["auto.set.keyTip"] = "Hold it: no helper acts.\nIn combat none acts either.",
  ["auto.set.chat"] = "Messages in chat",
  ["auto.set.chatTip"] = "One chat line per action",
  ["auto.tip.autoRepair"] = "Repairs when a vendor opens.\nOnly with enough gold.",
  ["auto.set.repairGuild"] = "Guild bank first",
  ["auto.tip.repairGuild"] = "Uses the guild bank when you\nmay withdraw that much.",
  ["auto.tip.autoSummon"] = "Never in combat.\nChecks summoner and place again.",
  ["auto.set.summonDelay"] = "Delay (seconds)",
  ["auto.set.summonTrusted"] = "Only known players",
  ["auto.tip.summonTrusted"] = "Group, guild and friends.\nOthers: nothing happens.",
  ["auto.tip.autoResurrect"] = "Group, guild and friends only.\nAccepts after 1 second.",
  ["auto.set.resNoCombat"] = "Not in combat",
  ["auto.tip.resNoCombat"] = "Skips resurrections\nduring combat.",
  ["auto.tip.autoQuest"] = "No reward choice, no gold,\nno currency. Hold the key to pause.",
  ["auto.set.questNormal"] = "Normal quests",
  ["auto.set.questDaily"] = "Daily quests",
  ["auto.set.questWeekly"] = "Weekly quests",
  ["auto.set.questItems"] = "Also with items",
  ["auto.tip.questItems"] = "Turns in quests that take items.\nOff: the window stays open.",
  ["auto.set.questKey"] = "Key needed",
  ["auto.tip.questKey"] = "Only acts while the stop key is held.",
  ["auto.set.questNotice"] = "Quest hints",
  ["auto.tip.questNotice"] = "Writes a chat line when you have to do a\nquest by hand: reward choice, items or a\nfull quest log. Nothing else happens.",
  ["auto.overview.heading"] = "All helpers at a glance",
  ["auto.overview.hint"] = "Each helper has its switch in the matching tab. Here you only see which ones are on.",
  ["auto.overview.row"] = "%s: %s",
  ["auto.overview.open"] = "Open",
  ["auto.set.questReady"] = "Quest ready message",
  ["auto.tip.questReady"] = "Shows one chat line when a quest of your\nlog is done and ready to hand in.",
  ["auto.set.questReadyHint"] = "Shows a chat line as soon as all objectives of a quest\nare done, so you know when to hand it in. Off by default.",
  ["auto.set.questReadyGroup"] = "Post done quests to group",
  ["auto.tip.questReadyGroup"] = "Posts one line with a clickable quest link\nto your party, raid or instance chat.",
  ["auto.set.questReadyGroupHint"] = "Posts one line per quest in the group chat.\nOnly while you are in a group. Off by default.",
  ["auto.set.questProgressGroup"] = "Post progress to group",
  ["auto.tip.questProgressGroup"] = "Posts a line like \"Wolves slain: 3/10\" to your\nparty, raid or instance chat when a goal advances.",
  ["auto.set.questProgressGroupHint"] = "Posts your objective progress in the group chat.\nQuick changes are combined into one line.\nOnly while you are in a group. Off by default.",
  ["auto.set.questChatPrefix"] = "Name in group lines",
  ["auto.tip.questChatPrefix"] = "Starts the quest lines for the group with\n\"Forever Guides:\".",
  ["auto.set.questChatIcon"] = "Icon in group lines",
  ["auto.tip.questChatIcon"] = "Shows a picture in front of the quest lines for the group.",
  ["auto.set.questChatIconHint"] = "The logo shows for players with Forever Guides.\nEveryone else sees a diamond instead.",
  ["auto.icon.logo"] = "Forever Guides logo",
  ["auto.icon.none"] = "No icon",
  ["auto.icon.rt1"] = "Star",
  ["auto.icon.rt2"] = "Circle",
  ["auto.icon.rt3"] = "Diamond",
  ["auto.icon.rt4"] = "Triangle",
  ["auto.icon.rt5"] = "Moon",
  ["auto.icon.rt6"] = "Square",
  ["auto.icon.rt7"] = "Cross",
  ["auto.icon.rt8"] = "Skull",
  ["auto.set.ignoreQuests"] = "Ignored quest IDs",
  ["auto.set.ignoreNpcs"] = "Ignored NPC IDs",
  ["auto.set.questHint"] = "Add by chat: /fg autoquest ignore <ID>",
  ["auto.tip.autoSocial"] = "Duels from strangers: declined.\nInvites of strangers: see below.",
  ["auto.set.socialDuel"] = "Block duels",
  ["auto.set.inviteHeading"] = "Accept group invites",
  ["auto.set.inviteHint"] = "- Every switch works on its own\n- Never while you are queued\n- Hold the stop key to decide yourself",
  ["auto.tip.acceptFriends"] = "Accepts group invites of friends\nright away.",
  ["auto.tip.acceptGuild"] = "Accepts group invites of guild members\nright away.",
  ["auto.tip.acceptContacts"] = "Accepts group invites of players in\nGuild & Contacts. The list also holds\nstrangers from trade and groups.",
  ["auto.set.contactsHint"] = "Careful: the contact list also holds strangers\nyou only met in trade or groups.",
  ["auto.tip.autoRoleCheck"] = "Dungeon finder: confirms your saved roles.\nGroup role poll: sets your role.\nNothing without a saved role.",
  ["auto.set.socialDecline"] = "Decline strangers",
  ["auto.tip.socialDecline"] = "Declines group invites of everyone else.\nNot while you are queued.",
  ["auto.tip.autoRelease"] = "Battlegrounds and PvP maps only.\nNot with a soulstone.",
  ["auto.set.releaseDelay"] = "Delay (ms)",
  ["auto.tip.hideErrors"] = "Hides red text like \"Out of range\".\nChat is not touched.",
  ["auto.set.errorsKeep"] = "Keep important ones",
  ["auto.tip.errorsKeep"] = "Bag full, quest log full,\nnot enough gold stay visible.",
})
ns.AddLocale("deDE", {
  ["auto.set.heading"] = "Automatik",
  ["auto.card.repair"] = "Reparatur beim Händler",
  ["auto.card.quests"] = "Quest-Automatik",
  ["auto.card.questExceptions"] = "Ausnahmen",
  ["auto.card.summon"] = "Beschwörung und Tod",
  ["auto.card.duels"] = "Duelle und Fremde",
  ["auto.card.errors"] = "Fehlermeldungen ausblenden",
  ["auto.set.hint"] = "- Alles ist aus, bis du es einschaltest\n- Stopp-Taste halten pausiert jeden Helfer",
  ["auto.set.key"] = "Stopp-Taste",
  ["auto.set.keyTip"] = "Gedrückt halten: nichts passiert.\nIm Kampf passiert ebenfalls nichts.",
  ["auto.set.chat"] = "Meldungen im Chat",
  ["auto.set.chatTip"] = "Eine Chatzeile pro Aktion",
  ["auto.tip.autoRepair"] = "Repariert beim Öffnen des Händlers.\nNur mit genug Gold.",
  ["auto.set.repairGuild"] = "Gildenkasse zuerst",
  ["auto.tip.repairGuild"] = "Nutzt die Gildenkasse, wenn du\nso viel entnehmen darfst.",
  ["auto.tip.autoSummon"] = "Nie im Kampf.\nPrüft Beschwörer und Ort erneut.",
  ["auto.set.summonDelay"] = "Pause (Sekunden)",
  ["auto.set.summonTrusted"] = "Nur bekannte Spieler",
  ["auto.tip.summonTrusted"] = "Gruppe, Gilde und Freunde.\nBei anderen passiert nichts.",
  ["auto.tip.autoResurrect"] = "Nur Gruppe, Gilde und Freunde.\nNimmt nach 1 Sekunde an.",
  ["auto.set.resNoCombat"] = "Nicht im Kampf",
  ["auto.tip.resNoCombat"] = "Überspringt Wiederbelebungen\nwährend des Kampfes.",
  ["auto.tip.autoQuest"] = "Keine Belohnungswahl, kein Gold,\nkeine Währung. Taste halten pausiert.",
  ["auto.set.questNormal"] = "Normale Quests",
  ["auto.set.questDaily"] = "Tägliche Quests",
  ["auto.set.questWeekly"] = "Wöchentliche Quests",
  ["auto.set.questItems"] = "Auch mit Item-Abgabe",
  ["auto.tip.questItems"] = "Gibt Quests ab, die Items nehmen.\nAus: das Fenster bleibt offen.",
  ["auto.set.questKey"] = "Taste nötig",
  ["auto.tip.questKey"] = "Wirkt nur bei gehaltener Stopp-Taste.",
  ["auto.set.questNotice"] = "Quest-Hinweise",
  ["auto.tip.questNotice"] = "Schreibt eine Chatzeile, wenn du eine Quest\nvon Hand erledigen musst: Belohnungswahl,\nItems oder volles Questlog. Mehr passiert nicht.",
  ["auto.overview.heading"] = "Alle Helfer im Überblick",
  ["auto.overview.hint"] = "Jeder Helfer hat seinen Schalter im passenden Reiter. Hier siehst du nur, welche eingeschaltet sind.",
  ["auto.overview.row"] = "%s: %s",
  ["auto.overview.open"] = "Öffnen",
  ["auto.set.questReady"] = "Quest-fertig-Meldung",
  ["auto.tip.questReady"] = "Zeigt eine Chatzeile, sobald eine Quest deines\nLogs erfüllt und abgabebereit ist.",
  ["auto.set.questReadyHint"] = "Zeigt eine Chatzeile, sobald alle Ziele einer Quest\nerfüllt sind, damit du weißt, wann du sie abgeben kannst.\nStandardmäßig aus.",
  ["auto.set.questReadyGroup"] = "Fertige Quests an Gruppe",
  ["auto.tip.questReadyGroup"] = "Schreibt eine Zeile mit anklickbarem Questlink\nin den Gruppen-, Raid- oder Instanzchat.",
  ["auto.set.questReadyGroupHint"] = "Schreibt pro Quest eine Zeile in den Gruppenchat.\nNur in einer Gruppe. Standardmäßig aus.",
  ["auto.set.questProgressGroup"] = "Fortschritt an Gruppe",
  ["auto.tip.questProgressGroup"] = "Schreibt eine Zeile wie „Wölfe getötet: 3/10“\nin den Gruppen-, Raid- oder Instanzchat,\nsobald ein Ziel weiterkommt.",
  ["auto.set.questProgressGroupHint"] = "Schreibt deinen Fortschritt in den Gruppenchat.\nSchnelle Änderungen kommen in eine Zeile.\nNur in einer Gruppe. Standardmäßig aus.",
  ["auto.set.questChatPrefix"] = "Name in Gruppenzeilen",
  ["auto.tip.questChatPrefix"] = "Beginnt die Questzeilen für die Gruppe mit\n„Forever Guides:“.",
  ["auto.set.questChatIcon"] = "Icon in Gruppenzeilen",
  ["auto.tip.questChatIcon"] = "Zeigt ein Bild vor den Questzeilen für die Gruppe.",
  ["auto.set.questChatIconHint"] = "Spieler mit Forever Guides sehen das Logo.\nAlle anderen sehen stattdessen einen Diamanten.",
  ["auto.icon.logo"] = "Forever-Guides-Logo",
  ["auto.icon.none"] = "Kein Icon",
  ["auto.icon.rt1"] = "Stern",
  ["auto.icon.rt2"] = "Kreis",
  ["auto.icon.rt3"] = "Diamant",
  ["auto.icon.rt4"] = "Dreieck",
  ["auto.icon.rt5"] = "Mond",
  ["auto.icon.rt6"] = "Quadrat",
  ["auto.icon.rt7"] = "Kreuz",
  ["auto.icon.rt8"] = "Totenkopf",
  ["auto.set.ignoreQuests"] = "Ignorierte Quest-IDs",
  ["auto.set.ignoreNpcs"] = "Ignorierte NPC-IDs",
  ["auto.set.questHint"] = "Per Chat: /fg autoquest ignore <ID>",
  ["auto.tip.autoSocial"] = "Duelle von Fremden: abgelehnt.\nEinladungen von Fremden: siehe unten.",
  ["auto.set.socialDuel"] = "Duelle blocken",
  ["auto.set.inviteHeading"] = "Einladungen annehmen",
  ["auto.set.inviteHint"] = "- Jeder Schalter wirkt für sich\n- Nie während einer Warteschlange\n- Stopp-Taste halten: du entscheidest selbst",
  ["auto.tip.acceptFriends"] = "Nimmt Gruppeneinladungen von Freunden\nsofort an.",
  ["auto.tip.acceptGuild"] = "Nimmt Gruppeneinladungen von Gildenmitgliedern\nsofort an.",
  ["auto.tip.acceptContacts"] = "Nimmt Gruppeneinladungen von Spielern\naus Gilde & Kontakte an. Die Liste enthält\nauch Fremde aus Handel und Gruppen.",
  ["auto.set.contactsHint"] = "Vorsicht: Die Kontaktliste enthält auch Fremde,\ndie du nur im Handel oder in Gruppen getroffen hast.",
  ["auto.tip.autoRoleCheck"] = "Dungeonbrowser: bestätigt deine gespeicherten Rollen.\nGruppen-Rollenabfrage: setzt deine Rolle.\nOhne gespeicherte Rolle passiert nichts.",
  ["auto.set.socialDecline"] = "Fremde ablehnen",
  ["auto.tip.socialDecline"] = "Lehnt Gruppeneinladungen aller anderen ab.\nNicht während einer Warteschlange.",
  ["auto.tip.autoRelease"] = "Nur Schlachtfelder und PvP-Karten.\nNicht mit Seelenstein.",
  ["auto.set.releaseDelay"] = "Pause (ms)",
  ["auto.tip.hideErrors"] = "Blendet roten Text wie „Außer Reichweite“ aus.\nDer Chat bleibt unberührt.",
  ["auto.set.errorsKeep"] = "Wichtige behalten",
  ["auto.tip.errorsKeep"] = "Tasche voll, Questlog voll,\nzu wenig Gold bleiben sichtbar.",
})

local FIELD_WIDTH = 320
local INDENT = 12

local controls = {}

local function stored(key)
  local value = ns.db.settings[key]
  if value == nil then
    value = Store.defaults.settings[key]
  end
  return value
end

local function add(view, control, opts)
  controls[#controls + 1] = control
  view.stack:Add(control, opts)
  return control
end

local function toggle(view, key, label, tip, sub)
  local control = W.Toggle(view.content, {
    key = label,
    tooltip = label,
    tooltipText = tip,
    get = function()
      return stored(key) == true
    end,
    set = function(value)
      Store.set("settings." .. key, value)
    end,
  })
  control.fgId = "auto-" .. key
  return add(view, control, { height = 24, gap = 6, indent = sub and INDENT or nil })
end

local function slider(view, key, label, min, max, step, suffix)
  local control = W.Slider(view.content, {
    key = label,
    min = min,
    max = max,
    step = step,
    get = function()
      return tonumber(stored(key)) or min
    end,
    set = function(value)
      Store.set("settings." .. key, value)
    end,
    format = function(value)
      return string.format("%d %s", math.floor(value + 0.5), suffix)
    end,
  })
  control.fgId = "auto-" .. key
  return add(view, control, { height = 42, width = FIELD_WIDTH, indent = INDENT })
end

-- A comma list of ids: Enter and leaving the field store the cleaned list.
local function idList(view, key, label)
  view.stack:Add(
    W.Text(view.content, { key = label, role = "ui", color = "textSecondary" }),
    { gap = 4, indent = INDENT }
  )
  local box = W.EditBox(view.content, {
    maxLetters = ns.SellLogic.MAX_PROTECT * 10,
    get = function()
      return stored(key) or ""
    end,
    set = function(text)
      Store.set("settings." .. key, ns.SellLogic.JoinIds(ns.SellLogic.ParseIds(text)))
    end,
  })
  box.fgId = "auto-" .. key
  add(view, box, { height = 26, width = FIELD_WIDTH, gap = 8, indent = INDENT })
end

local function keyDropdown(view)
  local options = {}
  for _, id in ipairs(Guard.KEYS) do
    options[#options + 1] = { value = id, key = "auto.key." .. id }
  end
  local control = W.Dropdown(view.content, {
    key = "auto.set.key",
    tooltip = "auto.set.key",
    tooltipText = "auto.set.keyTip",
    width = 240,
    options = options,
    get = Guard.KeyId,
    set = function(value)
      Store.set("settings.autoKey", value)
    end,
  })
  control.fgId = "auto-autoKey"
  add(view, control, { height = 46, width = 240 })
end

-- Stop key and chat messages: the head of the page, the target of /fg automatik.
function S.AddControl(view)
  S.view = view
  S.heading = ns.AddHeading(view, "auto.set.heading")
  ns.AddParagraph(view, "auto.set.hint", { role = "micro", color = "textMuted" })
  keyDropdown(view)
  toggle(view, "autoChat", "auto.set.chat", "auto.set.chatTip")
end

-- The helpers with the setting that switches them and the tab where it sits.
S.HELPERS = {
  { "autoQuest", "quests" },
  { "autoRepair", "selling" },
  { "autoSummon", "party" },
  { "autoResurrect", "party" },
  { "autoRelease", "party" },
  { "autoRoleCheck", "party" },
  { "autoSocial", "party" },
  { "hideErrors", "messages" },
  { "autoSocialAcceptFriends", "invites" },
  { "autoSocialAcceptGuild", "invites" },
  { "autoSocialAcceptContacts", "invites" },
}

-- Read only: one line per helper with its state, no second copy of a switch.
function S.AddOverview(view)
  ns.AddHeading(view, "auto.overview.heading")
  ns.AddParagraph(view, "auto.overview.hint", { role = "micro", color = "textMuted" })
  for _, helper in ipairs(S.HELPERS) do
    local key, feature = helper[1], helper[2]
    local row = W.Text(view.content, { role = "ui", color = "text", wrap = true })
    row.fgId = "auto-overview-" .. key
    local function paint()
      local on = ns.db.settings[key] == true
      row:SetText(
        string.format(ns.L["auto.overview.row"], ns.L["auto.name." .. key], ns.L[on and "common.on" or "common.off"])
      )
      W.SetColor(row, on and "text" or "textMuted")
    end
    ns.Bind(row, paint)
    row.Refresh = paint
    view.stack:Add(row, { gap = 2 })
    local open = W.Action(view.content, {
      key = "auto.overview.open",
      width = 120,
      height = 24,
      opens = true,
      onClick = function()
        ns.SettingsPage.Select(feature)
      end,
    })
    open.fgId = "auto-overview-" .. key .. "-open"
    view.stack:Add(open, { height = 24, width = 120, gap = 6 })
  end
end

function S.AddRepair(view)
  ns.AddHeading(view, "auto.card.repair")
  toggle(view, "autoRepair", "auto.name.autoRepair", "auto.tip.autoRepair")
  toggle(view, "autoRepairGuild", "auto.set.repairGuild", "auto.tip.repairGuild", true)
end

-- Icon choice of the group lines: the add-on logo, the raid marks (the only pictures chat carries) or none.
function S.AddQuestIcon(view)
  local QR = ns.QuestReadyLogic
  local function mark(n)
    return string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:14|t", n)
  end
  local logo = ns.BadgeAssets and string.format("|T%s:14:14|t", ns.BadgeAssets.Path(14)) or nil
  local options = { { value = "logo", key = "auto.icon.logo", icon = logo } }
  for n, id in ipairs(QR.MARKS) do
    options[#options + 1] = { value = id, key = "auto.icon." .. id, icon = mark(n) }
  end
  options[#options + 1] = { value = "none", key = "auto.icon.none" }
  local control = W.Dropdown(view.content, {
    key = "auto.set.questChatIcon",
    tooltip = "auto.set.questChatIcon",
    tooltipText = "auto.tip.questChatIcon",
    width = 240,
    options = options,
    get = function()
      return QR.CleanIcon(stored("questChatIcon"))
    end,
    set = function(value)
      Store.set("settings.questChatIcon", QR.CleanIcon(value))
    end,
  })
  control.fgId = "auto-questChatIcon"
  add(view, control, { height = 46, width = 240, indent = INDENT })
  ns.AddParagraph(view, "auto.set.questChatIconHint", { role = "micro", color = "textMuted" })
end

function S.AddQuests(view)
  ns.AddHeading(view, "auto.card.quests")
  toggle(view, "autoQuest", "auto.name.autoQuest", "auto.tip.autoQuest")
  toggle(view, "questReadyNotice", "auto.set.questReady", "auto.tip.questReady")
  ns.AddParagraph(view, "auto.set.questReadyHint", { role = "micro", color = "textMuted" })
  toggle(view, "questReadyGroup", "auto.set.questReadyGroup", "auto.tip.questReadyGroup")
  ns.AddParagraph(view, "auto.set.questReadyGroupHint", { role = "micro", color = "textMuted" })
  toggle(view, "questProgressGroup", "auto.set.questProgressGroup", "auto.tip.questProgressGroup")
  ns.AddParagraph(view, "auto.set.questProgressGroupHint", { role = "micro", color = "textMuted" })
  toggle(view, "questChatPrefix", "auto.set.questChatPrefix", "auto.tip.questChatPrefix", true)
  S.AddQuestIcon(view)
  -- The marker of the tracked quest: the same settings as in Map > Navigation.
  ns.WaypointNavSettings.AddQuestMarker(view)
  -- Which quests the helper takes and how it behaves: behind "More settings".
  local more = W.Accordion(view, { id = view.id or "quests.main" })
  toggle(more, "autoQuestNormal", "auto.set.questNormal", nil, true)
  toggle(more, "autoQuestDaily", "auto.set.questDaily", nil, true)
  toggle(more, "autoQuestWeekly", "auto.set.questWeekly", nil, true)
  toggle(more, "autoQuestItems", "auto.set.questItems", "auto.tip.questItems", true)
  toggle(more, "autoQuestNeedKey", "auto.set.questKey", "auto.tip.questKey", true)
  toggle(more, "autoQuestNotice", "auto.set.questNotice", "auto.tip.questNotice", true)
end

function S.AddQuestExceptions(view)
  ns.AddHeading(view, "auto.card.questExceptions")
  idList(view, "autoQuestIgnoreQuests", "auto.set.ignoreQuests")
  idList(view, "autoQuestIgnoreNpcs", "auto.set.ignoreNpcs")
  view.stack:Add(
    W.Text(view.content, { key = "auto.set.questHint", role = "micro", color = "textMuted", wrap = true }),
    { gap = 8, indent = INDENT }
  )
end

function S.AddSummon(view)
  ns.AddHeading(view, "auto.card.summon")
  -- The switch of each helper stays in sight, delays and exceptions sit behind "More settings".
  toggle(view, "autoSummon", "auto.name.autoSummon", "auto.tip.autoSummon")
  toggle(view, "autoResurrect", "auto.name.autoResurrect", "auto.tip.autoResurrect")
  toggle(view, "autoRelease", "auto.name.autoRelease", "auto.tip.autoRelease")
  toggle(view, "autoRoleCheck", "auto.name.autoRoleCheck", "auto.tip.autoRoleCheck")
  local more = W.Accordion(view, { id = view.id or "party.summon" })
  slider(more, "autoSummonDelay", "auto.set.summonDelay", ns.AutoSummon.DELAY_MIN, ns.AutoSummon.DELAY_MAX, 1, "s")
  toggle(more, "autoSummonTrusted", "auto.set.summonTrusted", "auto.tip.summonTrusted", true)
  toggle(more, "autoResurrectNoCombat", "auto.set.resNoCombat", "auto.tip.resNoCombat", true)
  slider(more, "autoReleaseDelay", "auto.set.releaseDelay", 0, ns.AutoRelease.DELAY_MAX, 100, "ms")
end

function S.AddDuels(view)
  ns.AddHeading(view, "auto.card.duels")
  toggle(view, "autoSocial", "auto.name.autoSocial", "auto.tip.autoSocial")
  toggle(view, "autoSocialDuel", "auto.set.socialDuel", nil, true)
  toggle(view, "autoSocialDecline", "auto.set.socialDecline", "auto.tip.socialDecline", true)
end

function S.AddErrors(view)
  ns.AddHeading(view, "auto.card.errors")
  toggle(view, "hideErrors", "auto.name.hideErrors", "auto.tip.hideErrors")
  toggle(view, "hideErrorsKeep", "auto.set.errorsKeep", "auto.tip.errorsKeep", true)
end

-- Accepting group invites per group, next to the whisper invites.
function S.AddInvites(view)
  ns.AddHeading(view, "auto.set.inviteHeading")
  ns.AddParagraph(view, "auto.set.inviteHint", { role = "micro", color = "textMuted" })
  toggle(view, "autoSocialAcceptFriends", "auto.name.autoSocialAcceptFriends", "auto.tip.acceptFriends")
  toggle(view, "autoSocialAcceptGuild", "auto.name.autoSocialAcceptGuild", "auto.tip.acceptGuild")
  toggle(view, "autoSocialAcceptContacts", "auto.name.autoSocialAcceptContacts", "auto.tip.acceptContacts")
  ns.AddParagraph(view, "auto.set.contactsHint", { role = "micro", color = "warning" })
end

-- Scrolls the open settings page to this section (the heading is the top of its tab).
function S.ScrollTo()
  local view, heading = S.view, S.heading
  if not (view and heading) then
    return false
  end
  view:Layout()
  local _, _, _, _, y = heading:GetPoint()
  if type(y) ~= "number" then
    return false
  end
  view.area:ScrollTo(-y - 4)
  return true
end

-- /fg automatik
function S.Open()
  ns.SettingsPage.SelectControl("auto.set.heading")
  ns.Main.Show("settings")
  S.ScrollTo()
end

-- A helper switches itself off after errors, and the toggles follow.
ns.On("FG_SETTING_CHANGED", function(_, path)
  local watched = type(path) == "string" and (path:find("^settings%.auto") or path:find("^settings%.hideErrors"))
  if not watched then
    return
  end
  for _, control in ipairs(controls) do
    if control.Refresh and not (control.edit and control.edit:HasFocus()) then
      control:Refresh()
    end
  end
end)
