-- Settings card "Logo in chat" on the tab Share (ChatBadge.lua): the switch, style, size, chat groups, the own
-- logo, a preview line and the hints (sharing missing, other chat add-on, locked chat in encounters).
-- The display switch is on by default and shows nothing without the receive consent; every change goes through
-- Store.set and the badge follows at once.
local _, ns = ...
local W, L, Store = ns.W, ns.L, ns.Store
local CBL, PL, CB = ns.ChatBadgeLogic, ns.PresenceLogic, ns.ChatBadge

local S = {}
ns.ChatBadgeSettings = S

ns.AddLocale("enUS", {
  ["chatbadge.heading"] = "Logo in chat",
  ["chatbadge.hint"] = "Logo before the names of players who want to be recognized.\nOnly on your screen, nothing is sent.",
  ["chatbadge.show"] = "See logos of others",
  ["chatbadge.show.tip"] = "Logo for group and guild members who allowed it.",
  ["chatbadge.showIn"] = "See logos in chat",
  ["chatbadge.needs"] = "Needs Receive for group or guild.",
  ["chatbadge.notice"] = "Logos of others need sharing.",
  ["chatbadge.style"] = "Style",
  ["chatbadge.style.icon"] = "Icon",
  ["chatbadge.style.text"] = "Text [FG]",
  ["chatbadge.style.both"] = "Both",
  ["chatbadge.size"] = "Size",
  ["chatbadge.size.auto"] = "Auto (font size)",
  ["chatbadge.crest.hint"] = "Guild and community logos follow the add-on logo. The tooltip of the add-on logo lists all of them.",
  ["chatbadge.crest.count"] = "More logos per line",
  ["chatbadge.crest.off"] = "None",
  ["chatbadge.crest.notice"] = "Logos of guilds and communities need sharing.",
  ["chatbadge.crest.local"] = "Recognize logos without the add-on",
  ["chatbadge.crest.local.tip"] = "Shows guild and community logos for players who do not use the add-on, from data your game already has.",
  ["chatbadge.crest.local.hint"] = "Local only: nothing is sent and nobody is asked. Only data your game already holds is read: your guild roster, the names of your communities and the guild of players you have seen. The logo comes from the list of the add-on, else from the emblem your game has for your own guild, else a neutral symbol (a shield for a guild, two figures for a community) with the name from your game. The game gives no pictures of communities or of other guilds.",
  ["chatbadge.size.px"] = "%d px",
  ["chatbadge.channels"] = "Chats with logo",
  ["chatbadge.ch.guild"] = "Guild",
  ["chatbadge.ch.party"] = "Party",
  ["chatbadge.ch.raid"] = "Raid",
  ["chatbadge.ch.instance"] = "Instance",
  ["chatbadge.ch.whisper"] = "Whisper",
  ["chatbadge.ch.say"] = "Say and yell",
  ["chatbadge.ch.channel"] = "Channels",
  ["chatbadge.self"] = "Show my own logo in chat",
  ["chatbadge.self.tip"] = "Only on your screen, others do not see it.",
  ["chatbadge.preview"] = "Preview",
  ["chatbadge.sample.name"] = "Example",
  ["chatbadge.sample.text"] = "Hello!",
  ["chatbadge.meaning"] = "The logo means: this player uses Forever Guides.",
  ["chatbadge.other"] = "Other chat add-on active (%s).\nThe logo can look different there.",
  ["chatbadge.otherOn"] = "Use it anyway",
  ["chatbadge.otherOn.tip"] = "Logo even though another add-on formats chat.",
  ["chatbadge.locked"] = "Locked chat in encounters: no logo there.",
  ["chatbadge.off"] = "Chat logo switched off after %d errors.",
  ["chatbadge.status"] = "Status",
  ["chatbadge.limits"] = "Who gets a logo: only players of your group or guild who share their logo and whose message you have already heard. Never: strangers in Say, Yell and public channels, system and loot lines, your own lines (unless enabled) and whispers (unless enabled). Local recognition (\"Recognize logos without the add-on\") reads names from your guild roster, your communities and the guild of players you have seen, and sends nothing.",
  ["chatbadge.status.off"] = "The chat logo was switched off after errors. Switch it on again to try once more.",
  ["chatbadge.status.switchOff"] = 'You receive logos, yet "See logos of others" is switched off, so no add-on logo appears. Switch it on to see them.',
  ["chatbadge.status.idle"] = 'Nothing is switched on, so no logo appears. Turn on "See logos of others" or the guild and community logos.',
  ["chatbadge.status.other"] = 'No logo appears while %s formats the chat. Allow it with "Use it anyway" below.',
  ["chatbadge.status.heard"] = "Add-on users heard so far: %d. They appear once they share: when someone joins your group, when a guild member comes online, otherwise about every 30 to 40 minutes.",
  ["chatbadge.status.noSend"] = "You do not share your own logo yet, so others do not see it. Turn on Send for Presence (group or guild) in the list above.",
  ["chatbadge.status.noCount"] = "Guild and community logos are off (More logos per line: None).",
  ["chatbadge.status.noSource"] = "Guild and community logos need receiving or the local recognition.",
  ["chatbadge.status.emptyList"] = "The logo list of the add-on is empty, so nobody can share a logo yet. Guild and community logos only appear with the local recognition.",
  ["chatbadge.status.emptyLocal"] = "The logo list of the add-on is empty. For players without the add-on you see a neutral symbol (a shield for a guild, two figures for a community) with the name from your game, and the emblem of your own guild when your game gives it. Players with the add-on show what they share, and this symbol when they share no guild or community logo.",
  ["chatbadge.status.localUnread"] = "The local recognition has not read your guild yet. The game sends the roster a few seconds after login, then the symbols appear.",
  ["chatbadge.status.localNoGuild"] = "The local recognition found no guild: your game names none, or its name is hidden right now. Communities still work.",
  ["chatbadge.status.channelsOff"] = 'No logo in chat lines of: %s (see "Chats with logo").',
  ["chatbadge.status.skin"] = "%s draws the chat in its own window. The logo needs this add-on to sit in front of it, which happens on its own a few seconds after login. If it is missing there, send the lines of /fg diag chat.",
})
ns.AddLocale("deDE", {
  ["chatbadge.heading"] = "Logo im Chat",
  ["chatbadge.hint"] = "Logo vor den Namen von Spielern, die erkannt werden wollen.\nNur auf deinem Bildschirm, es wird nichts gesendet.",
  ["chatbadge.show"] = "Logos anderer sehen",
  ["chatbadge.show.tip"] = "Logo für Gruppe und Gilde, wenn erlaubt.",
  ["chatbadge.showIn"] = "Logos im Chat sehen",
  ["chatbadge.needs"] = "Braucht Empfangen für Gruppe oder Gilde.",
  ["chatbadge.notice"] = "Logos anderer brauchen Teilen.",
  ["chatbadge.style"] = "Stil",
  ["chatbadge.style.icon"] = "Symbol",
  ["chatbadge.style.text"] = "Text [FG]",
  ["chatbadge.style.both"] = "Beides",
  ["chatbadge.size"] = "Größe",
  ["chatbadge.size.auto"] = "Auto (Schriftgröße)",
  ["chatbadge.crest.hint"] = "Gilden- und Community-Logos folgen dem Addon-Logo. Der Tooltip des Addon-Logos listet alle auf.",
  ["chatbadge.crest.count"] = "Weitere Logos je Zeile",
  ["chatbadge.crest.off"] = "Keine",
  ["chatbadge.crest.notice"] = "Logos von Gilden und Communitys brauchen Teilen.",
  ["chatbadge.crest.local"] = "Logos auch ohne Addon erkennen",
  ["chatbadge.crest.local.tip"] = "Zeigt Gilden- und Community-Logos auch bei Spielern ohne Addon, aus Daten, die dein Spiel schon hat.",
  ["chatbadge.crest.local.hint"] = "Rein lokal: Es wird nichts gesendet und niemand gefragt. Gelesen werden nur Daten, die dein Spiel schon hat: deine Gildenliste, die Namen deiner Communitys und die Gilde von Spielern, die du gesehen hast. Das Logo kommt aus der Liste des Addons, sonst aus dem Wappen, das dein Spiel für deine eigene Gilde hat, sonst ein neutrales Symbol (ein Schild für eine Gilde, zwei Figuren für eine Community) mit dem Namen aus deinem Spiel. Bilder von Communitys oder fremden Gilden gibt das Spiel nicht her.",
  ["chatbadge.size.px"] = "%d px",
  ["chatbadge.channels"] = "Chats mit Logo",
  ["chatbadge.ch.guild"] = "Gilde",
  ["chatbadge.ch.party"] = "Gruppe",
  ["chatbadge.ch.raid"] = "Raid",
  ["chatbadge.ch.instance"] = "Instanz",
  ["chatbadge.ch.whisper"] = "Flüstern",
  ["chatbadge.ch.say"] = "Sagen und Rufen",
  ["chatbadge.ch.channel"] = "Kanäle",
  ["chatbadge.self"] = "Mein eigenes Logo im Chat zeigen",
  ["chatbadge.self.tip"] = "Nur auf deinem Bildschirm, andere sehen es nicht.",
  ["chatbadge.preview"] = "Vorschau",
  ["chatbadge.sample.name"] = "Beispiel",
  ["chatbadge.sample.text"] = "Hallo!",
  ["chatbadge.meaning"] = "Das Logo heißt: Dieser Spieler nutzt Forever Guides.",
  ["chatbadge.other"] = "Anderes Chat-Addon aktiv (%s).\nDas Logo kann dort anders aussehen.",
  ["chatbadge.otherOn"] = "Trotzdem nutzen",
  ["chatbadge.otherOn.tip"] = "Logo auch, wenn ein anderes Addon den Chat formatiert.",
  ["chatbadge.locked"] = "Gesperrter Chat in Begegnungen: dort kein Logo.",
  ["chatbadge.off"] = "Chat-Logo nach %d Fehlern ausgeschaltet.",
  ["chatbadge.status"] = "Status",
  ["chatbadge.limits"] = "Wer ein Logo bekommt: nur Spieler deiner Gruppe oder Gilde, die ihr Logo teilen und deren Nachricht du schon gehört hast. Nie: Fremde in Sagen, Rufen und öffentlichen Kanälen, System- und Beutezeilen, deine eigenen Zeilen (außer eingeschaltet) und Flüstern (außer eingeschaltet). Die lokale Erkennung (\"Logos auch ohne Addon erkennen\") liest Namen aus deiner Gildenliste, deinen Communitys und die Gilde gesehener Spieler und sendet nichts.",
  ["chatbadge.status.off"] = "Das Chat-Logo wurde nach Fehlern ausgeschaltet. Schalte es wieder ein, um es erneut zu versuchen.",
  ["chatbadge.status.switchOff"] = 'Du empfängst Logos, doch "Logos anderer sehen" ist ausgeschaltet, deshalb erscheint kein Addon-Logo. Schalte es ein, um sie zu sehen.',
  ["chatbadge.status.idle"] = 'Nichts ist eingeschaltet, deshalb erscheint kein Logo. Schalte "Logos anderer sehen" oder die Gilden- und Community-Logos ein.',
  ["chatbadge.status.other"] = 'Solange %s den Chat formatiert, erscheint kein Logo. Erlaube es unten mit "Trotzdem nutzen".',
  ["chatbadge.status.heard"] = "Bisher gehörte Addon-Nutzer: %d. Sie erscheinen, sobald sie teilen: wenn jemand deiner Gruppe beitritt, wenn ein Gildenmitglied online kommt, sonst etwa alle 30 bis 40 Minuten.",
  ["chatbadge.status.noSend"] = "Du teilst dein eigenes Logo noch nicht, deshalb sehen andere es nicht. Schalte Senden für Anwesenheit (Gruppe oder Gilde) in der Liste oben ein.",
  ["chatbadge.status.noCount"] = "Gilden- und Community-Logos sind aus (Weitere Logos je Zeile: Keine).",
  ["chatbadge.status.noSource"] = "Gilden- und Community-Logos brauchen Empfangen oder die lokale Erkennung.",
  ["chatbadge.status.emptyList"] = "Die Logo-Liste des Addons ist leer, deshalb kann noch niemand ein Logo teilen. Gilden- und Community-Logos erscheinen nur mit der lokalen Erkennung.",
  ["chatbadge.status.emptyLocal"] = "Die Logo-Liste des Addons ist leer. Bei Spielern ohne Addon siehst du ein neutrales Symbol (ein Schild für eine Gilde, zwei Figuren für eine Community) mit dem Namen aus deinem Spiel, dazu das Wappen deiner eigenen Gilde, wenn dein Spiel es hergibt. Spieler mit Addon zeigen, was sie teilen, und dieses Symbol, wenn sie kein Gilden- oder Community-Logo teilen.",
  ["chatbadge.status.localUnread"] = "Die lokale Erkennung hat deine Gilde noch nicht gelesen. Das Spiel schickt die Mitgliederliste einige Sekunden nach dem Login, danach erscheinen die Symbole.",
  ["chatbadge.status.localNoGuild"] = "Die lokale Erkennung hat keine Gilde gefunden: Dein Spiel nennt keine oder der Name ist gerade verborgen. Communitys funktionieren weiter.",
  ["chatbadge.status.channelsOff"] = 'Kein Logo in Chatzeilen von: %s (siehe "Chats mit Logo").',
  ["chatbadge.status.skin"] = "%s zeichnet den Chat in einem eigenen Fenster. Das Logo braucht dieses Addon davor, das geschieht einige Sekunden nach dem Login von selbst. Fehlt es dort, sende die Zeilen von /fg diag chat.",
})

-- Everything that repaints when a setting or the consent changes.
local live = setmetatable({}, { __mode = "k" })

local function refreshAll()
  for item in pairs(live) do
    if item.Refresh then
      item:Refresh()
    end
  end
end

local function track(item, refresh)
  item.Refresh = refresh
  live[item] = true
  return item
end

local function get(key)
  return ns.db.settings[key]
end

local function toggle(view, opts)
  local t = W.Toggle(view.content, {
    key = opts.key,
    get = opts.get,
    set = function(v)
      opts.set(v == true)
      refreshAll()
    end,
    tooltip = opts.key,
    tooltipText = opts.tip,
  })
  t.fgId = opts.id
  view.stack:Add(t, { height = 24, gap = 6 })
  live[t] = true
  return t
end

local function settingToggle(view, key, labelKey, tipKey)
  return toggle(view, {
    key = labelKey,
    tip = tipKey,
    id = "chatbadge-" .. key,
    get = function()
      return get(key) == true
    end,
    set = function(v)
      Store.set("settings." .. key, v)
    end,
  })
end

-- The badge text of the preview line: the settings as they are, the height of a default window font.
function S.PreviewLine()
  local name = L["chatbadge.sample.name"]
  local badge = PL.Badge(name, CB.Style(), CBL.Height(get("chatBadgeSize"), nil))
  return (badge ~= "" and badge .. " " or "") .. "[" .. name .. "]: " .. L["chatbadge.sample.text"]
end

-- The reasons why nothing (or little) shows, one line each, from the live settings and the register.
function S.StatusText()
  local lines = {}
  for _, item in ipairs(CBL.Status(CB.StatusFacts())) do
    local text = L["chatbadge.status." .. item[1]]
    local arg = item[2]
    if item[1] == "channelsOff" then
      local names = {}
      for id in tostring(arg):gmatch("[^,]+") do
        names[#names + 1] = L["chatbadge.ch." .. id] or id
      end
      arg = table.concat(names, ", ")
    end
    lines[#lines + 1] = arg ~= nil and string.format(text, arg) or text
  end
  return table.concat(lines, "\n")
end

local function sizeSlider(view)
  local s = W.Slider(view.content, {
    key = "chatbadge.size",
    min = 9,
    max = CBL.MAX_HEIGHT,
    step = 1,
    get = function()
      local size = CBL.CleanSize(get("chatBadgeSize"))
      return size == 0 and 9 or size
    end,
    set = function(v)
      Store.set("settings.chatBadgeSize", v < CBL.MIN_HEIGHT and 0 or v)
      refreshAll()
    end,
    format = function(v)
      return v < CBL.MIN_HEIGHT and L["chatbadge.size.auto"] or string.format(L["chatbadge.size.px"], v)
    end,
  })
  s.fgId = "chatbadge-size"
  view.stack:Add(s, { height = 42, width = 320, gap = 6 })
  live[s] = true
end

-- How many guild and community logos follow the add-on logo, and the hint where receiving them is switched on.
local function crestRows(view)
  ns.AddParagraph(view, "chatbadge.crest.hint", { role = "micro", color = "textMuted", gap = 4 })
  local notice = ns.OptInNotice.Banner(view.content, {
    fn = ns.CrestMark.FN,
    dir = "receive",
    aud = "group",
    textKey = "chatbadge.crest.notice",
    onChanged = refreshAll,
  })
  notice.fgId = "chatbadge-crest-notice"
  view.stack:Add(notice, { gap = 6 })
  track(notice, function()
    notice:Update(not ns.CrestMark.Listening())
  end)
  local s = W.Slider(view.content, {
    key = "chatbadge.crest.count",
    min = 0,
    max = ns.CrestLogic.LIMITS.MAX_COUNT,
    step = 1,
    get = function()
      return ns.CrestLogic.CleanCount(get("chatCrestCount"))
    end,
    set = function(v)
      Store.set("settings.chatCrestCount", ns.CrestLogic.CleanCount(v))
      refreshAll()
    end,
    format = function(v)
      return v < 1 and L["chatbadge.crest.off"] or tostring(v)
    end,
  })
  s.fgId = "chatbadge-crest-count"
  view.stack:Add(s, { height = 42, width = 320, gap = 6 })
  live[s] = true
  ns.AddParagraph(view, "chatbadge.crest.local.hint", { role = "micro", color = "textMuted", gap = 4 })
  settingToggle(view, "crestLocal", "chatbadge.crest.local", "chatbadge.crest.local.tip")
end

local function styleDropdown(view)
  local dd = W.Dropdown(view.content, {
    key = "chatbadge.style",
    width = 200,
    options = {
      { value = "icon", key = "chatbadge.style.icon" },
      { value = "text", key = "chatbadge.style.text" },
      { value = "both", key = "chatbadge.style.both" },
    },
    get = CB.Style,
    set = function(v)
      Store.set("settings.chatBadgeStyle", CBL.CleanStyle(v))
      refreshAll()
    end,
  })
  dd.fgId = "chatbadge-style"
  view.stack:Add(dd, { height = 46, width = 200, gap = 6 })
  live[dd] = true
end

local function channelToggles(view)
  ns.AddParagraph(view, "chatbadge.channels", { role = "micro", color = "textMuted", gap = 2 })
  for _, id in ipairs(CBL.CHANNELS) do
    toggle(view, {
      key = "chatbadge.ch." .. id,
      id = "chatbadge-ch-" .. id,
      get = function()
        return CBL.ChannelOn(get("chatBadgeChannels"), id)
      end,
      set = function(v)
        Store.set("settings.chatBadgeChannels." .. id, v)
      end,
    })
  end
end

function S.Add(view)
  ns.AddHeading(view, "chatbadge.heading")
  ns.AddParagraph(view, "chatbadge.hint", { role = "micro", color = "textMuted" })
  settingToggle(view, "chatBadge", "chatbadge.show", "chatbadge.show.tip")
  -- The consent of presenceMark is "receive" for group or guild; the button asks for the group.
  local notice = ns.OptInNotice.Banner(view.content, {
    fn = CB.FN,
    dir = "receive",
    aud = "group",
    textKey = "chatbadge.notice",
    onChanged = refreshAll,
  })
  notice.fgId = "chatbadge-notice"
  view.stack:Add(notice, { gap = 6 })
  track(notice, function()
    notice:Update(not CB.Listening())
  end)
  styleDropdown(view)
  sizeSlider(view)
  crestRows(view)
  channelToggles(view)
  settingToggle(view, "chatBadgeSelf", "chatbadge.self", "chatbadge.self.tip")
  ns.AddParagraph(view, "chatbadge.preview", { role = "micro", color = "textMuted", gap = 2 })
  local preview = ns.AddParagraph(view, nil, { role = "ui", color = "text", gap = 2 })
  preview.fgId = "chatbadge-preview"
  track(preview, function()
    preview:SetText(S.PreviewLine())
  end)
  ns.AddParagraph(view, "chatbadge.meaning", { role = "micro", color = "textMuted", gap = 6 })
  ns.AddParagraph(view, "chatbadge.status", { role = "micro", color = "textMuted", gap = 2 })
  local status = ns.AddParagraph(view, nil, { role = "micro", color = "text", gap = 6 })
  status.fgId = "chatbadge-status"
  track(status, function()
    status:SetText(S.StatusText())
  end)
  local other = ns.AddParagraph(view, nil, { role = "micro", color = "warning", gap = 4 })
  other.fgId = "chatbadge-other"
  local otherOn = settingToggle(view, "chatBadgeOtherAddons", "chatbadge.otherOn", "chatbadge.otherOn.tip")
  track(other, function()
    local names = CB.OtherAddons()
    other:SetShown(#names > 0)
    otherOn:SetShown(#names > 0)
    if #names > 0 then
      other:SetText(string.format(L["chatbadge.other"], table.concat(names, ", ")))
    end
  end)
  ns.AddParagraph(view, "chatbadge.locked", { role = "micro", color = "textMuted", gap = 2 })
  ns.AddParagraph(view, "chatbadge.limits", { role = "micro", color = "textMuted", gap = 2 })
  refreshAll()
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if
    type(path) == "string"
    and (path:find("^settings%.chatBadge") or path:find("^settings%.chatCrest") or path == "settings.crestLocal")
  then
    refreshAll()
  end
end)
ns.On("FG_CONSENT_CHANGED", refreshAll)
ns.On("FG_CONSENT_WITHDRAWN", refreshAll)

-- The same switch at the consent of the function: players look for it there, the card "Logo in chat" lies
-- far below the function cards.
ns.ConsentSettings.AddExtra(CB.FN, function(card)
  ns.AddParagraph(card, "chatbadge.needs", { role = "micro", color = "textMuted", gap = 2 })
  toggle(card, {
    key = "chatbadge.showIn",
    tip = "chatbadge.show.tip",
    id = "consent-" .. CB.FN .. "-chatBadge",
    get = function()
      return get("chatBadge") == true
    end,
    set = function(v)
      Store.set("settings.chatBadge", v)
    end,
  })
end)

-- Later than the built-in sections of the tab (Modules/Settings.lua appends in this order).
ns.SettingsPage.Add(S.Add, "sharing")
