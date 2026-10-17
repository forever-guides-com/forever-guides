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
  ["auto.set.hint"] = "- Everything is off until you switch it on\n- Hold the stop key to pause every helper",
  ["auto.set.key"] = "Stop key",
  ["auto.set.keyTip"] = "Hold it: no helper acts.\nIn combat none acts either.",
  ["auto.set.chat"] = "Messages in chat",
  ["auto.set.chatTip"] = "One chat line per action",
  ["auto.tip.autoRepair"] = "Repairs when a merchant opens.\nOnly with enough gold.",
  ["auto.set.repairGuild"] = "Guild bank first",
  ["auto.tip.repairGuild"] = "Uses the guild bank when you\nmay withdraw that much.",
  ["auto.tip.autoSummon"] = "Never in combat.\nSummoner and place are checked again.",
  ["auto.set.summonDelay"] = "Delay (seconds)",
  ["auto.set.summonTrusted"] = "Only known players",
  ["auto.tip.summonTrusted"] = "Group, guild and friends.\nOthers: nothing happens.",
  ["auto.tip.autoResurrect"] = "Group, guild and friends only.\nAccepts after 1 second.",
  ["auto.set.resNoCombat"] = "Not in combat",
  ["auto.tip.resNoCombat"] = "Skips resurrections that are\ncast during combat.",
  ["auto.tip.autoQuest"] = "No reward choice, no gold,\nno currency. Hold the key to pause.",
  ["auto.set.questNormal"] = "Normal quests",
  ["auto.set.questDaily"] = "Daily quests",
  ["auto.set.questWeekly"] = "Weekly quests",
  ["auto.set.questItems"] = "Also with items",
  ["auto.tip.questItems"] = "Turns in quests that take items.\nOff: the window stays open.",
  ["auto.set.questKey"] = "Key needed",
  ["auto.tip.questKey"] = "Only acts while the stop key is held.",
  ["auto.set.ignoreQuests"] = "Ignored quest IDs",
  ["auto.set.ignoreNpcs"] = "Ignored NPC IDs",
  ["auto.set.questHint"] = "Add by chat: /fg autoquest ignore <ID>",
  ["auto.tip.autoSocial"] = "Duels from strangers: declined.\nInvites of strangers: see below.",
  ["auto.set.socialDuel"] = "Block duels",
  ["auto.set.inviteHeading"] = "Accept group invites",
  ["auto.set.inviteHint"] = "- Every switch works on its own\n- Never while you are queued\n- Hold the stop key to decide yourself",
  ["auto.tip.acceptFriends"] = "Group invites of friends are\naccepted right away.",
  ["auto.tip.acceptGuild"] = "Group invites of guild members are\naccepted right away.",
  ["auto.tip.acceptContacts"] = "Group invites of players in Guild &\nContacts. The list also holds strangers\nfrom trade and groups.",
  ["auto.set.contactsHint"] = "Careful: the contact list also holds strangers\nyou only met in trade or groups.",
  ["auto.tip.autoRoleCheck"] = "Dungeon finder: confirms your saved roles.\nGroup role poll: sets your role.\nNothing without a saved role.",
  ["auto.set.socialDecline"] = "Decline strangers",
  ["auto.tip.socialDecline"] = "Group invites of everyone else.\nNot while you are queued.",
  ["auto.tip.autoRelease"] = "Battlegrounds and PvP maps only.\nNot with a soulstone.",
  ["auto.set.releaseDelay"] = "Delay (ms)",
  ["auto.tip.hideErrors"] = "Hides red text like Out of range.\nChat is not touched.",
  ["auto.tip.layerShare"] = "Shares zone, layer, class and name with\nother users of the layer channel and\naccepts the invite of the host you asked.\nAlso on the card Layer (Map).",
  ["auto.tip.layerHost"] = "Invites players who ask you for a layer\nswitch. Needs sharing.",
  ["auto.set.errorsKeep"] = "Keep important ones",
  ["auto.tip.errorsKeep"] = "Bag full, quest log full,\nnot enough gold stay visible.",
})
ns.AddLocale("deDE", {
  ["auto.set.heading"] = "Automatik",
  ["auto.set.hint"] = "- Alles ist aus, bis du es einschaltest\n- Gehaltene Stopp-Taste pausiert jede Automatik",
  ["auto.set.key"] = "Stopp-Taste",
  ["auto.set.keyTip"] = "Gedrückt halten: nichts passiert.\nIm Kampf passiert ebenfalls nichts.",
  ["auto.set.chat"] = "Meldungen im Chat",
  ["auto.set.chatTip"] = "Eine Chatzeile pro Aktion",
  ["auto.tip.autoRepair"] = "Repariert beim Öffnen des Händlers.\nNur mit genug Gold.",
  ["auto.set.repairGuild"] = "Gildenkasse zuerst",
  ["auto.tip.repairGuild"] = "Nutzt die Gildenkasse, wenn du\nso viel entnehmen darfst.",
  ["auto.tip.autoSummon"] = "Nie im Kampf.\nBeschwörer und Ort werden erneut geprüft.",
  ["auto.set.summonDelay"] = "Pause (Sekunden)",
  ["auto.set.summonTrusted"] = "Nur bekannte Spieler",
  ["auto.tip.summonTrusted"] = "Gruppe, Gilde und Freunde.\nBei anderen passiert nichts.",
  ["auto.tip.autoResurrect"] = "Nur Gruppe, Gilde und Freunde.\nNimmt nach 1 Sekunde an.",
  ["auto.set.resNoCombat"] = "Nicht im Kampf",
  ["auto.tip.resNoCombat"] = "Überspringt Wiederbelebungen,\ndie im Kampf gewirkt werden.",
  ["auto.tip.autoQuest"] = "Keine Belohnungswahl, kein Gold,\nkeine Währung. Taste hält an.",
  ["auto.set.questNormal"] = "Normale Quests",
  ["auto.set.questDaily"] = "Tägliche Quests",
  ["auto.set.questWeekly"] = "Wöchentliche Quests",
  ["auto.set.questItems"] = "Auch mit Item-Abgabe",
  ["auto.tip.questItems"] = "Gibt Quests ab, die Items nehmen.\nAus: das Fenster bleibt offen.",
  ["auto.set.questKey"] = "Taste nötig",
  ["auto.tip.questKey"] = "Wirkt nur bei gehaltener Stopp-Taste.",
  ["auto.set.ignoreQuests"] = "Ignorierte Quest-IDs",
  ["auto.set.ignoreNpcs"] = "Ignorierte NPC-IDs",
  ["auto.set.questHint"] = "Per Chat: /fg autoquest ignore <ID>",
  ["auto.tip.autoSocial"] = "Duelle von Fremden: abgelehnt.\nEinladungen von Fremden: siehe unten.",
  ["auto.set.socialDuel"] = "Duelle blocken",
  ["auto.set.inviteHeading"] = "Einladungen annehmen",
  ["auto.set.inviteHint"] = "- Jeder Schalter wirkt für sich\n- Nie während einer Warteschlange\n- Stopp-Taste halten: du entscheidest selbst",
  ["auto.tip.acceptFriends"] = "Gruppeneinladungen von Freunden\nwerden sofort angenommen.",
  ["auto.tip.acceptGuild"] = "Gruppeneinladungen von Gildenmitgliedern\nwerden sofort angenommen.",
  ["auto.tip.acceptContacts"] = "Gruppeneinladungen von Spielern aus Gilde &\nKontakte. Die Liste enthält auch Fremde aus\nHandel und Gruppen.",
  ["auto.set.contactsHint"] = "Vorsicht: Die Kontaktliste enthält auch Fremde,\ndie du nur im Handel oder in Gruppen getroffen hast.",
  ["auto.tip.autoRoleCheck"] = "Dungeonbrowser: bestätigt deine gespeicherten Rollen.\nGruppen-Rollenabfrage: setzt deine Rolle.\nOhne gespeicherte Rolle passiert nichts.",
  ["auto.set.socialDecline"] = "Fremde ablehnen",
  ["auto.tip.socialDecline"] = "Gruppeneinladungen aller anderen.\nNicht während einer Warteschlange.",
  ["auto.tip.autoRelease"] = "Nur Schlachtfelder und PvP-Karten.\nNicht mit Seelenstein.",
  ["auto.set.releaseDelay"] = "Pause (ms)",
  ["auto.tip.hideErrors"] = "Blendet roten Text wie Außer Reichweite aus.\nDer Chat bleibt unberührt.",
  ["auto.tip.layerShare"] = "Teilt Zone, Layer, Klasse und Name mit\nanderen Nutzern des Layer-Kanals und nimmt\ndie Einladung des gefragten Hosts an.\nAuch auf der Karte Layer (Karte).",
  ["auto.tip.layerHost"] = "Lädt Spieler ein, die dich nach einem\nLayer-Wechsel fragen. Braucht das Teilen.",
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
      -- Hosting needs sharing: the layer network checks that and says so.
      if key == "layerHost" then
        ns.LayerNet.SetHost(value)
      else
        Store.set("settings." .. key, value)
      end
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

-- A comma list of ids: typed text is kept as typed, Enter cleans it up.
local function idList(view, key, label)
  view.stack:Add(
    W.Text(view.content, { key = label, role = "ui", color = "textSecondary" }),
    { gap = 4, indent = INDENT }
  )
  local box
  box = W.EditBox(view.content, {
    onChange = function(text)
      Store.set("settings." .. key, text)
    end,
    onEnter = function(text)
      local clean = ns.SellLogic.JoinIds(ns.SellLogic.ParseIds(text))
      Store.set("settings." .. key, clean)
      box.edit:SetText(clean)
    end,
  })
  box.edit:SetMaxLetters(ns.SellLogic.MAX_PROTECT * 10)
  box.fgId = "auto-" .. key
  function box:Refresh()
    if not self.edit:HasFocus() then
      self.edit:SetText(stored(key) or "")
    end
  end
  box:Refresh()
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

function S.Add(view)
  controls = {}
  S.view = view
  S.heading = ns.AddHeading(view, "auto.set.heading")
  ns.AddParagraph(view, "auto.set.hint", { role = "micro", color = "textMuted" })
  keyDropdown(view)
  toggle(view, "autoChat", "auto.set.chat", "auto.set.chatTip")

  toggle(view, "autoRepair", "auto.name.autoRepair", "auto.tip.autoRepair")
  toggle(view, "autoRepairGuild", "auto.set.repairGuild", "auto.tip.repairGuild", true)

  toggle(view, "autoSummon", "auto.name.autoSummon", "auto.tip.autoSummon")
  slider(view, "autoSummonDelay", "auto.set.summonDelay", ns.AutoSummon.DELAY_MIN, ns.AutoSummon.DELAY_MAX, 1, "s")
  toggle(view, "autoSummonTrusted", "auto.set.summonTrusted", "auto.tip.summonTrusted", true)

  toggle(view, "autoResurrect", "auto.name.autoResurrect", "auto.tip.autoResurrect")
  toggle(view, "autoResurrectNoCombat", "auto.set.resNoCombat", "auto.tip.resNoCombat", true)

  toggle(view, "autoQuest", "auto.name.autoQuest", "auto.tip.autoQuest")
  toggle(view, "autoQuestNormal", "auto.set.questNormal", nil, true)
  toggle(view, "autoQuestDaily", "auto.set.questDaily", nil, true)
  toggle(view, "autoQuestWeekly", "auto.set.questWeekly", nil, true)
  toggle(view, "autoQuestItems", "auto.set.questItems", "auto.tip.questItems", true)
  toggle(view, "autoQuestNeedKey", "auto.set.questKey", "auto.tip.questKey", true)
  idList(view, "autoQuestIgnoreQuests", "auto.set.ignoreQuests")
  idList(view, "autoQuestIgnoreNpcs", "auto.set.ignoreNpcs")
  view.stack:Add(
    W.Text(view.content, { key = "auto.set.questHint", role = "micro", color = "textMuted", wrap = true }),
    { gap = 8, indent = INDENT }
  )

  toggle(view, "autoSocial", "auto.name.autoSocial", "auto.tip.autoSocial")
  toggle(view, "autoSocialDuel", "auto.set.socialDuel", nil, true)
  toggle(view, "autoSocialDecline", "auto.set.socialDecline", "auto.tip.socialDecline", true)

  toggle(view, "autoRelease", "auto.name.autoRelease", "auto.tip.autoRelease")
  slider(view, "autoReleaseDelay", "auto.set.releaseDelay", 0, ns.AutoRelease.DELAY_MAX, 100, "ms")

  toggle(view, "autoRoleCheck", "auto.name.autoRoleCheck", "auto.tip.autoRoleCheck")

  toggle(view, "hideErrors", "auto.name.hideErrors", "auto.tip.hideErrors")
  toggle(view, "hideErrorsKeep", "auto.set.errorsKeep", "auto.tip.errorsKeep", true)

  toggle(view, "layerShare", "auto.name.layerShare", "auto.tip.layerShare")
  toggle(view, "layerHost", "auto.name.layerHost", "auto.tip.layerHost", true)
end

-- Accepting group invites per group: on the tab Guild and contacts, where the whisper invites are.
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
  ns.SettingsPage.Select("automation")
  ns.Main.Show("settings")
  S.ScrollTo()
end

-- A helper switches itself off after errors, and the toggles follow.
ns.On("FG_SETTING_CHANGED", function(_, path)
  local watched = type(path) == "string"
    and (path:find("^settings%.auto") or path:find("^settings%.hideErrors") or path:find("^settings%.layer"))
  if not watched then
    return
  end
  for _, control in ipairs(controls) do
    if control.Refresh and not (control.edit and control.edit:HasFocus()) then
      control:Refresh()
    end
  end
end)
