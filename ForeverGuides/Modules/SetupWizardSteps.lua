-- Steps and texts of the setup wizard. Controls name their Store key; a control whose key has
-- no default yet (a module not built yet) is left out by the logic, so steps can be added early.
local _, ns = ...
local SW, Theme = ns.SetupWizard, ns.Theme

ns.AddLocale("enUS", {
  ["setup.title"] = "Setup",
  ["setup.start"] = "Start setup",
  ["setup.notice"] = "New: setup with /fg setup",
  ["setup.noticeNew"] = "New setup steps: /fg setup new",
  ["setup.nothingNew"] = "No new steps.",
  ["setup.progress"] = "Step %d of %d",
  ["setup.back"] = "Back",
  ["setup.next"] = "Next",
  ["setup.finish"] = "Done",
  ["setup.skip"] = "Skip",
  ["setup.close"] = "Close",
  ["setup.resetAll"] = "Reset all",
  ["setup.skipTitle"] = "Skip setup",
  ["setup.skipText"] = "Apply defaults and close?",
  ["setup.cancelTitle"] = "Cancel setup",
  ["setup.cancelText"] = "Cancel setup? Your changes stay.",
  ["setup.resetTitle"] = "Reset all",
  ["setup.resetText"] = "Set all setup options to default?",
  ["setup.copy"] = "Copy",
  ["setup.open"] = "Open",
  ["setup.info.tutorials"] = "Tutorials: page in the left navigation (group Addon)",
  ["setup.info.help"] = "Help & feedback: page in the left navigation, report errors there too",
  ["setup.changed"] = "You changed:",
  ["setup.noChanges"] = "No changes, defaults active.",
  ["setup.changeWhere"] = "Change later: Settings, tab in brackets.",
  ["setup.step.look"] = "Language and look",
  ["setup.step.look.text"] = "A few quick settings. Changes apply right away.\nSkip any time.",
  ["setup.step.addons"] = "Optional add-ons",
  ["setup.step.addons.text"] = "For all characters. Per character: Settings > Addons.",
  ["setup.step.windows"] = "Windows",
  ["setup.step.windows.text"] = "Game windows, addon and messages.",
  ["setup.step.invitations"] = "Invites and data",
  ["setup.step.invitations.text"] = "Who you invite, who may invite you and what you share.",
  ["setup.ctl.inviteGroup"] = "Group invite by whisper",
  ["setup.ctl.inviteWords"] = "Keywords for the group invite",
  ["setup.ctl.inviteWordsHint"] = "Default: only friends may ask (Settings).",
  ["setup.ctl.inviteWordsExample"] = "inv, invite",
  ["setup.ctl.inviteWordsUsed"] = "Used: %s",
  ["setup.ctl.inviteWordsNone"] = "No keyword: the whisper invite stays off.",
  ["setup.ctl.inviteWordsOff"] = "none",
  ["setup.ctl.inviteGuild"] = "Guild invite by whisper",
  ["setup.ctl.inviteGuildWords"] = "Keywords for the guild invite",
  ["setup.ctl.acceptFriends"] = "Friends may invite me",
  ["setup.ctl.acceptGuild"] = "Guild members may invite me",
  ["setup.ctl.acceptGuildHint"] = "Friends and guild are accepted at once, never while queued.",
  ["setup.ctl.peerShare"] = "Share jobs, item level",
  ["setup.ctl.peerShareHint"] = "Only to add-on users in group and guild.",
  ["setup.step.map"] = "Map and waypoints",
  ["setup.step.map.text"] = "World map, gathering spots and waypoint arrow.",
  ["setup.step.loot"] = "Loot and selling",
  ["setup.step.loot.text"] = "Boss loot recording, selling and repair.",
  ["setup.step.comfort"] = "Convenience",
  ["setup.step.comfort.text"] = "Helpers stay off until you switch them on.",
  ["setup.step.controls"] = "Controls",
  ["setup.step.controls.text"] = "Buttons, text size and key combinations.",
  ["setup.ctl.sparklesHint"] = "Sets game graphics, off puts them back (restart ends it).",
  ["setup.ctl.sellNote"] = "Selling every white, green, blue or epic item: Settings.",
  ["setup.ctl.contrastHint"] = "Black background, white text.",
  ["setup.ctl.motionHint"] = "Fewer fades and moving effects.",
  ["setup.ctl.keysOpen"] = "Key combinations for mouse actions",
  ["setup.ctl.keysOpenHint"] = "Opens: Settings, General, Key combinations.",
  ["setup.ctl.mapReveal"] = "Show all map areas in color",
  ["setup.ctl.mapRevealHint"] = "Off: only explored areas, the rest dark.",
  ["setup.ctl.dungeonMap"] = "Dungeon map on M inside instances",
  ["setup.ctl.dungeonMapHint"] = "A panel in the world map, a button switches back.",
  ["setup.ctl.autoRepair"] = "Repair at the merchant",
  ["setup.ctl.autoRepairHint"] = "Repairs when it opens, with enough gold.",
  ["setup.ctl.autoSummon"] = "Accept summons",
  ["setup.ctl.autoSummonHint"] = "Known players only, never in combat.",
  ["setup.ctl.autoResurrect"] = "Accept resurrections",
  ["setup.ctl.autoResurrectHint"] = "Group, guild and friends only.",
  ["setup.ctl.stopKeyHint"] = "Hold it: no helper acts.",
  ["setup.ctl.autoQuest"] = "Accept and turn in quests",
  ["setup.ctl.autoQuestHint"] = "Without reward choice. The stop key pauses it.",
  ["setup.ctl.autoRelease"] = "Release in battlegrounds",
  ["setup.ctl.autoReleaseHint"] = "Battlegrounds only, not with a soulstone.",
  ["setup.ctl.hideErrors"] = "Hide red error messages",
  ["setup.ctl.hideErrorsHint"] = "Chat stays. Warnings like bag full stay.",
  ["setup.ctl.lootEnabled"] = "Record boss loot",
  ["setup.ctl.lootEnabledHint"] = "Improves the data. Stays on your PC, no names.",
  ["setup.ctl.sellGray"] = "Sell gray items",
  ["setup.ctl.sellGrayHint"] = "A Junk button at the merchant sells them.",
  ["setup.ctl.buttonLabels"] = "Show text on icon buttons",
  ["setup.ctl.buttonLabelsHint"] = "Icon buttons get a short label.",
  ["setup.step.done"] = "All set",
  ["setup.step.done.text"] = "Later: /fg setup or Settings > Setup",
  ["setup.ctl.frameTweaks"] = "Move game windows",
  ["setup.ctl.frameTweaksHint"] = "Drag by the title bar, reset on the page Windows.",
  ["setup.ctl.frameMore"] = "More options",
  ["setup.ctl.hideTalkingHead"] = "Show Talking Head",
  ["setup.ctl.hideTalkingHeadHint"] = "Off hides the NPC speech window.",
  ["setup.ctl.arrow"] = "Show arrow",
  ["setup.ctl.arrowTitle"] = "Arrow: show destination",
  ["setup.ctl.arrowBackground"] = "Arrow: background",
})
ns.AddLocale("deDE", {
  ["setup.title"] = "Einrichtung",
  ["setup.start"] = "Einrichtung starten",
  ["setup.notice"] = "Neu: Einrichtung mit /fg setup",
  ["setup.noticeNew"] = "Neue Einrichtungsschritte: /fg setup neu",
  ["setup.nothingNew"] = "Keine neuen Schritte.",
  ["setup.progress"] = "Schritt %d von %d",
  ["setup.back"] = "Zurück",
  ["setup.next"] = "Weiter",
  ["setup.finish"] = "Fertig",
  ["setup.skip"] = "Überspringen",
  ["setup.close"] = "Schließen",
  ["setup.resetAll"] = "Alles auf Standard",
  ["setup.skipTitle"] = "Einrichtung überspringen",
  ["setup.skipText"] = "Standardwerte übernehmen und schließen?",
  ["setup.cancelTitle"] = "Einrichtung abbrechen",
  ["setup.cancelText"] = "Einrichtung abbrechen? Änderungen bleiben.",
  ["setup.resetTitle"] = "Alles auf Standard",
  ["setup.resetText"] = "Alle Optionen der Einrichtung auf Standard setzen?",
  ["setup.copy"] = "Kopieren",
  ["setup.open"] = "Öffnen",
  ["setup.info.tutorials"] = "Tutorials: Seite in der Navigation links (Gruppe Addon)",
  ["setup.info.help"] = "Hilfe & Feedback: Seite in der Navigation links, dort auch Fehler melden",
  ["setup.changed"] = "Du hast geändert:",
  ["setup.noChanges"] = "Keine Änderungen, Standardwerte aktiv.",
  ["setup.changeWhere"] = "Später ändern: Einstellungen, Reiter in Klammern.",
  ["setup.step.look"] = "Sprache und Aussehen",
  ["setup.step.look.text"] = "Ein paar schnelle Einstellungen. Änderungen wirken sofort.\nJederzeit überspringbar.",
  ["setup.step.addons"] = "Optionale Addons",
  ["setup.step.addons.text"] = "Für alle Charaktere. Pro Charakter: Einstellungen > Addons.",
  ["setup.step.windows"] = "Fenster",
  ["setup.step.windows.text"] = "Spielfenster, Addon und Meldungen.",
  ["setup.step.invitations"] = "Einladungen und Daten",
  ["setup.step.invitations.text"] = "Wen du einlädst, wer dich einladen darf und was du teilst.",
  ["setup.ctl.inviteGroup"] = "Gruppe per Flüstern einladen",
  ["setup.ctl.inviteWords"] = "Stichwörter für die Gruppeneinladung",
  ["setup.ctl.inviteWordsHint"] = "Standard: nur Freunde dürfen fragen (Einstellungen).",
  ["setup.ctl.inviteWordsExample"] = "inv, invite",
  ["setup.ctl.inviteWordsUsed"] = "Gilt: %s",
  ["setup.ctl.inviteWordsNone"] = "Kein Stichwort: Einladung per Flüstern bleibt aus.",
  ["setup.ctl.inviteWordsOff"] = "keine",
  ["setup.ctl.inviteGuild"] = "Gilde per Flüstern einladen",
  ["setup.ctl.inviteGuildWords"] = "Stichwörter für die Gildeneinladung",
  ["setup.ctl.acceptFriends"] = "Freunde dürfen mich einladen",
  ["setup.ctl.acceptGuild"] = "Gildenmitglieder dürfen mich einladen",
  ["setup.ctl.acceptGuildHint"] = "Freunde und Gilde sofort angenommen, nie in Warteschlangen.",
  ["setup.ctl.peerShare"] = "Berufe, Itemlevel teilen",
  ["setup.ctl.peerShareHint"] = "Nur an Addon-Nutzer in Gruppe und Gilde.",
  ["setup.step.map"] = "Karte und Wegpunkte",
  ["setup.step.map.text"] = "Weltkarte, Sammelpunkte und Wegpunkt-Pfeil.",
  ["setup.step.loot"] = "Beute und Verkaufen",
  ["setup.step.loot.text"] = "Beute der Bosse, Verkaufen und Reparieren.",
  ["setup.step.comfort"] = "Komfort",
  ["setup.step.comfort.text"] = "Helfer bleiben aus, bis du sie einschaltest.",
  ["setup.step.controls"] = "Bedienung",
  ["setup.step.controls.text"] = "Knöpfe, Schriftgröße und Tastenkombinationen.",
  ["setup.ctl.sparklesHint"] = "Setzt Spiel-Grafik, Aus stellt sie zurück (mit Neustart).",
  ["setup.ctl.sellNote"] = "Alles Weiß, Grün, Blau, Episch verkaufen: Einstellungen.",
  ["setup.ctl.contrastHint"] = "Schwarzer Grund, weiße Schrift.",
  ["setup.ctl.motionHint"] = "Weniger Überblendungen und Bewegung.",
  ["setup.ctl.keysOpen"] = "Tastenkombinationen für Mausaktionen",
  ["setup.ctl.keysOpenHint"] = "Öffnet: Einstellungen, Allgemein, Tastenkombinationen.",
  ["setup.ctl.mapReveal"] = "Alle Kartengebiete in Farbe zeigen",
  ["setup.ctl.mapRevealHint"] = "Aus: nur erkundete Gebiete, der Rest dunkel.",
  ["setup.ctl.dungeonMap"] = "In Instanzen bei M die Dungeonkarte zeigen",
  ["setup.ctl.dungeonMapHint"] = "Ein Feld in der Weltkarte, ein Knopf schaltet zurück.",
  ["setup.ctl.autoRepair"] = "Beim Händler reparieren",
  ["setup.ctl.autoRepairHint"] = "Repariert beim Öffnen, nur mit genug Gold.",
  ["setup.ctl.autoSummon"] = "Beschwörungen annehmen",
  ["setup.ctl.autoSummonHint"] = "Nur bekannte Spieler, nie im Kampf.",
  ["setup.ctl.autoResurrect"] = "Wiederbelebung annehmen",
  ["setup.ctl.autoResurrectHint"] = "Nur Gruppe, Gilde und Freunde.",
  ["setup.ctl.stopKeyHint"] = "Gedrückt halten: kein Helfer handelt.",
  ["setup.ctl.autoQuest"] = "Quests annehmen und abgeben",
  ["setup.ctl.autoQuestHint"] = "Ohne Belohnungswahl. Die Stopp-Taste hält an.",
  ["setup.ctl.autoRelease"] = "Im Schlachtfeld freilassen",
  ["setup.ctl.autoReleaseHint"] = "Nur Schlachtfelder, nicht mit Seelenstein.",
  ["setup.ctl.hideErrors"] = "Rote Fehlermeldungen ausblenden",
  ["setup.ctl.hideErrorsHint"] = "Chat bleibt. Warnungen wie Tasche voll bleiben.",
  ["setup.ctl.lootEnabled"] = "Beute der Bosse erfassen",
  ["setup.ctl.lootEnabledHint"] = "Verbessert die Daten. Nur lokal, keine Namen.",
  ["setup.ctl.sellGray"] = "Graue Items verkaufen",
  ["setup.ctl.sellGrayHint"] = "Ein Plunder-Knopf beim Händler verkauft sie.",
  ["setup.ctl.buttonLabels"] = "Beschriftung an Symbolknöpfen anzeigen",
  ["setup.ctl.buttonLabelsHint"] = "Symbolknöpfe bekommen einen kurzen Text.",
  ["setup.step.done"] = "Fertig",
  ["setup.step.done.text"] = "Später: /fg setup oder Einstellungen > Einrichtung",
  ["setup.ctl.frameTweaks"] = "Spielfenster verschiebbar",
  ["setup.ctl.frameTweaksHint"] = "Am Titel ziehen, zurücksetzen auf der Seite Fenster.",
  ["setup.ctl.frameMore"] = "Mehr Optionen",
  ["setup.ctl.hideTalkingHead"] = "Talking Head anzeigen",
  ["setup.ctl.hideTalkingHeadHint"] = "Aus blendet das NPC-Sprechfenster aus.",
  ["setup.ctl.arrow"] = "Pfeil anzeigen",
  ["setup.ctl.arrowTitle"] = "Pfeil: Ziel anzeigen",
  ["setup.ctl.arrowBackground"] = "Pfeil: Hintergrund",
})

local function toggle(key, labelKey, extra)
  local c = { type = "toggle", key = key, labelKey = labelKey }
  for k, v in pairs(extra or {}) do
    c[k] = v
  end
  return c
end

local function percent(v)
  return string.format("%d %%", math.floor(v * 100 + 0.5))
end

-- Optional module hook: the Store change already reaches listeners of FG_SETTING_CHANGED.
local function applyModule(name)
  return function()
    local module = ns[name]
    if type(module) == "table" and type(module.Apply) == "function" then
      module.Apply()
    end
  end
end

-- The same repaint as the accessibility settings.
local function restyle()
  ns.RefreshUI()
  ns.Main.Relayout()
end

local function applyLocale(value)
  ns.SetLocale(value)
  ns.RefreshUI()
  if ns.Main.frame then
    ns.Main.InvalidateViews()
  end
end

local themes = {}
for _, id in ipairs(Theme.PRESET_ORDER) do
  themes[#themes + 1] = { value = id, key = "settings.theme." .. id }
end

local SINCE = "0.1.0"

-- extra.tab: the Settings tab of the step's controls, named in the summary; a control with its own
-- tab (or tab = false for none) overrides it.
local function step(id, order, controls, extra)
  local def = {
    id = id,
    order = order,
    titleKey = "setup.step." .. id,
    textKey = "setup.step." .. id .. ".text",
    since = SINCE,
    controls = controls,
  }
  for k, v in pairs(extra or {}) do
    def[k] = v
  end
  for _, c in ipairs(controls) do
    if c.tab == nil then
      c.tab = def.tab
    end
  end
  SW.RegisterStep(def)
end

-- A line of text without a setting. The key only has to exist in the defaults, nothing is stored.
local function note(key, textKey)
  return {
    type = "custom",
    key = key,
    labelKey = textKey,
    action = true,
    build = function(view)
      local text = ns.W.Text(view.content, { key = textKey, role = "micro", color = "textMuted", wrap = true })
      view.stack:Add(text, { gap = 8 })
      return text
    end,
  }
end

-- Text, a hint and a button that opens a tab of the Settings. Nothing is stored.
local function settingsLink(key, labelKey, hintKey, tab)
  return {
    type = "custom",
    key = key,
    labelKey = labelKey,
    action = true,
    build = function(view)
      local W = ns.W
      local width = math.floor(180 * math.max(1, tonumber(ns.db.settings.fontScale) or 1) + 0.5)
      view.stack:Add(
        W.Text(view.content, { key = labelKey, role = "ui", color = "textSecondary", wrap = true }),
        { gap = 2 }
      )
      view.stack:Add(
        W.Text(view.content, { key = hintKey, role = "micro", color = "textMuted", wrap = true }),
        { gap = 4 }
      )
      local button = W.Action(view.content, {
        label = "act.open",
        icon = "open",
        tooltip = labelKey,
        width = width,
        onClick = function()
          ns.SettingsPage.Select(tab)
          ns.Main.Show("settings")
        end,
      })
      view.stack:Add(button, { height = 26, width = width, gap = 8 })
      return button
    end,
  }
end

-- The keyword field of a whisper invite: what is typed is stored cleaned by IL.ParseWords (at most
-- 8 words, 20 letters each), the field shows it that way once it loses the focus.
local function cleanWords(text)
  local IL = ns.InviteLogic
  return IL.JoinWords(IL.ParseWords(text))
end

local function inviteWords(key, labelKey, withHint)
  local path = "settings." .. key
  return {
    type = "custom",
    key = path,
    labelKey = labelKey,
    format = function(v)
      return v == "" and ns.L["setup.ctl.inviteWordsOff"] or v
    end,
    build = function(view)
      local W, IL = ns.W, ns.InviteLogic
      view.stack:Add(W.Text(view.content, { key = labelKey, role = "ui", color = "textSecondary" }), { gap = 4 })
      local box
      box = W.EditBox(view.content, {
        placeholder = "setup.ctl.inviteWordsExample",
        onChange = function(text)
          ns.Store.set(path, cleanWords(text))
        end,
        onEnter = function(text)
          ns.Store.set(path, cleanWords(text))
          box.edit:SetText(cleanWords(text))
        end,
      })
      box.edit:SetMaxLetters(IL.MAX_WORDS * (IL.MAX_WORD + 2))
      box.fgId = "setup-" .. key
      view.stack:Add(box, { height = 26, width = 320, gap = 4 })
      local status = W.Text(view.content, { role = "micro", wrap = true })
      local function paint()
        local words = ns.Store.get(path)
        local used = type(words) == "string" and words or ""
        W.SetColor(status, used == "" and "warning" or "textMuted")
        status:SetText(
          used == "" and ns.L["setup.ctl.inviteWordsNone"] or string.format(ns.L["setup.ctl.inviteWordsUsed"], used)
        )
      end
      ns.Bind(status, paint)
      view.stack:Add(status, { gap = 2 })
      if withHint then
        view.stack:Add(
          W.Text(view.content, { key = "setup.ctl.inviteWordsHint", role = "micro", color = "textMuted", wrap = true }),
          { gap = 8 }
        )
      end
      function box:Refresh()
        if not self.edit:HasFocus() then
          self.edit:SetText(ns.Store.get(path) or "")
        end
        paint()
      end
      box.edit:HookScript("OnEditFocusLost", function()
        box.edit:SetText(ns.Store.get(path) or "")
      end)
      box:Refresh()
      return box
    end,
  }
end

-- Language first: the welcome text, the logo and the website link open the wizard.
step("look", 10, {
  {
    type = "dropdown",
    key = "settings.locale",
    labelKey = "settings.languageLabel",
    options = {
      { value = "auto", key = "settings.lang.auto" },
      { value = "deDE", text = "Deutsch" },
      { value = "enUS", text = "English" },
    },
    apply = applyLocale,
  },
  {
    type = "dropdown",
    key = "settings.skin",
    labelKey = "settings.skin",
    hintKey = "settings.skinHint",
    options = ns.Appearance.SkinOptions(),
    apply = function(value)
      ns.Appearance.SetSkin(value)
    end,
  },
  {
    type = "dropdown",
    key = "settings.theme",
    labelKey = "settings.theme",
    options = themes,
    apply = function(value)
      ns.Appearance.SetTheme(value)
    end,
  },
  {
    type = "slider",
    key = "settings.mainAlpha",
    labelKey = "settings.alpha",
    min = Theme.ALPHA_MIN,
    max = Theme.ALPHA_MAX,
    step = 5,
    format = function(v)
      return string.format("%d %%", v)
    end,
    apply = function(value)
      ns.Main.SetAlpha(value)
    end,
  },
  {
    type = "slider",
    key = "settings.scale",
    labelKey = "settings.scale",
    min = 0.7,
    max = 1.5,
    step = 0.05,
    format = percent,
    applyOn = "release",
    apply = function(value)
      ns.Main.SetScale(value)
    end,
  },
}, { layout = { "logo", "title", "text", "links", "controls" } })

-- One switch per optional add-on of the manifest: the wizard sets the default for all characters, the
-- override of a single character lives in the Settings tab.
local addonSwitches = {}
for _, entry in ipairs(ns.SubAddons.List()) do
  addonSwitches[#addonSwitches + 1] = toggle("settings.subaddons." .. entry.id, entry.titleKey, {
    hintKey = entry.descKey,
    apply = function(value)
      ns.SubAddons.SetEnabled(entry.id, value, "account")
    end,
  })
end
step("addons", 15, addonSwitches, { tab = "addons", since = "0.1.4" })

-- Appears once the key has a default (the icon button labels are built separately).
step("controls", 20, {
  toggle("settings.buttonLabels", "setup.ctl.buttonLabels", {
    hintKey = "setup.ctl.buttonLabelsHint",
    tab = false,
    apply = function()
      ns.RefreshUI()
    end,
  }),
  {
    type = "slider",
    key = "settings.fontScale",
    labelKey = "settings.fontScale",
    min = Theme.FONT_SCALE_MIN,
    max = Theme.FONT_SCALE_MAX,
    step = 0.05,
    format = percent,
    applyOn = "release",
    apply = restyle,
  },
  toggle("settings.contrast", "settings.contrast", { hintKey = "setup.ctl.contrastHint", apply = restyle }),
  toggle("settings.colorblind", "settings.colorblind", { hintKey = "settings.colorblindHint", apply = restyle }),
  toggle("settings.reduceMotion", "settings.reduceMotion", { hintKey = "setup.ctl.motionHint" }),
  settingsLink("settings.modKeys", "setup.ctl.keysOpen", "setup.ctl.keysOpenHint", "general"),
}, { tab = "window" })

step("windows", 30, {
  toggle("settings.frameTweaks", "setup.ctl.frameTweaks", {
    hintKey = "setup.ctl.frameTweaksHint",
    apply = applyModule("FrameTweaks"),
  }),
  {
    -- A link to the page "Windows". The key only has to exist in the defaults, nothing is stored.
    type = "custom",
    key = "settings.frameBarHover",
    labelKey = "setup.ctl.frameMore",
    build = function(view)
      local button = ns.W.Action(view.content, {
        label = "act.options",
        icon = "gear",
        tooltip = "setup.ctl.frameMore",
        width = 180,
        onClick = function()
          ns.Main.Show("windows")
        end,
      })
      view.stack:Add(button, { height = 26, width = 180, gap = 8 })
      return button
    end,
  },
  toggle("settings.combatHide", "settings.combatHide"),
  toggle("settings.hideTalkingHead", "setup.ctl.hideTalkingHead", {
    hintKey = "setup.ctl.hideTalkingHeadHint",
    invert = true,
    apply = applyModule("TalkingHead"),
  }),
  toggle("settings.minimap.hide", "settings.minimap", {
    invert = true,
    apply = function()
      ns.MinimapButton.Apply()
    end,
  }),
  toggle("settings.hideErrors", "setup.ctl.hideErrors", { hintKey = "setup.ctl.hideErrorsHint", tab = "automation" }),
})

step("map", 40, {
  toggle("settings.sparkles.enabled", "sparkles.set.enabled", { hintKey = "setup.ctl.sparklesHint" }),
  -- The map image mode lives on the Map page, not in the Settings tabs.
  toggle("settings.mapReveal", "setup.ctl.mapReveal", { hintKey = "setup.ctl.mapRevealHint", tab = false }),
  toggle("settings.dungeonWorldMap", "setup.ctl.dungeonMap", {
    hintKey = "setup.ctl.dungeonMapHint",
    apply = applyModule("DungeonWorldMap"),
  }),
  -- The arrow and its title and background are set on the arrow itself, not in the Settings tabs.
  toggle("waypoints.settings.arrow", "setup.ctl.arrow", {
    tab = false,
    apply = function(value)
      ns.Waypoints.SetSetting("arrow", value)
    end,
  }),
  toggle("settings.waypointWindowTitle", "setup.ctl.arrowTitle", { tab = false }),
  toggle("settings.waypointWindowBackground", "setup.ctl.arrowBackground", { tab = false }),
}, { tab = "map" })

step("loot", 50, {
  toggle("settings.lootEnabled", "setup.ctl.lootEnabled", { hintKey = "setup.ctl.lootEnabledHint" }),
  toggle("settings.sellGray", "setup.ctl.sellGray", { hintKey = "setup.ctl.sellGrayHint", tab = "sell" }),
  toggle("settings.autoRepair", "setup.ctl.autoRepair", { hintKey = "setup.ctl.autoRepairHint", tab = "automation" }),
  toggle("settings.durabilityWarn", "dur.set.warn", { hintKey = "dur.set.warnTip" }),
  note("settings.sellWhiteAll", "setup.ctl.sellNote"),
}, { tab = "bags" })

-- Everything below is off by default and only acts on the player's own switch.
step("comfort", 60, {
  toggle("settings.autoQuest", "setup.ctl.autoQuest", { hintKey = "setup.ctl.autoQuestHint" }),
  toggle("settings.autoRelease", "setup.ctl.autoRelease", { hintKey = "setup.ctl.autoReleaseHint" }),
  toggle("settings.autoSummon", "setup.ctl.autoSummon", { hintKey = "setup.ctl.autoSummonHint" }),
  toggle("settings.autoResurrect", "setup.ctl.autoResurrect", { hintKey = "setup.ctl.autoResurrectHint" }),
  {
    type = "dropdown",
    key = "settings.autoKey",
    labelKey = "auto.set.key",
    hintKey = "setup.ctl.stopKeyHint",
    -- The same ids as AutoGuard.KEYS, which loads after this file.
    options = {
      { value = "shift", key = "auto.key.shift" },
      { value = "alt", key = "auto.key.alt" },
      { value = "ctrl", key = "auto.key.ctrl" },
    },
  },
}, { tab = "automation" })

step("invitations", 70, {
  toggle("settings.inviteGroup", "setup.ctl.inviteGroup"),
  inviteWords("inviteGroupWords", "setup.ctl.inviteWords", true),
  toggle("settings.inviteGuild", "setup.ctl.inviteGuild"),
  inviteWords("inviteGuildWords", "setup.ctl.inviteGuildWords"),
  toggle("settings.autoSocialAcceptFriends", "setup.ctl.acceptFriends"),
  toggle("settings.autoSocialAcceptGuild", "setup.ctl.acceptGuild", { hintKey = "setup.ctl.acceptGuildHint" }),
  toggle("settings.peerShare", "setup.ctl.peerShare", { hintKey = "setup.ctl.peerShareHint" }),
})

-- Closes every run: lists what was changed and where to change it later.
step("done", 80, {}, { closing = true, layout = { "title", "summary", "info", "community", "text" } })
