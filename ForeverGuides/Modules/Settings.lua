-- Settings page in tabs: general, appearance, map, items, loot and inventory, selling, automation,
-- guild and contacts, advanced. Every tab is a grid of cards (Modules/SettingsGrid.lua), one card per
-- section. The sections of other modules are added through ns.SettingsPage.
local _, ns = ...
local W, Store, WS, Theme = ns.W, ns.Store, ns.WindowStyle, ns.Theme

local function setting(key)
  return function()
    return ns.db.settings[key]
  end, function(v)
    Store.set("settings." .. key, v)
  end
end

local function restyle()
  ns.RefreshUI()
  ns.Main.Relayout()
end

ns.AddLocale("enUS", {
  ["settings.buttonLabels"] = "Show text on icon buttons",
  ["settings.buttonLabelsHint"] = "Buttons show a short word next to their icon. Off: icons only, the tooltip names the action. Narrow places hide the text by themselves.",
  ["settings.hostSkin"] = "Behavior with other UI add-ons",
  ["settings.hostSkin.auto"] = "Automatic (follows the window)",
  ["settings.hostSkin.light"] = "Light (Blizzard's own look)",
  ["settings.hostSkin.dark"] = "Dark (own dark surface)",
  ["settings.hostSkinHint"] = "Forever Guides adds panels to Blizzard windows, for example the learn list in the spellbook. Automatic reads whether the window is drawn light or a UI add-on has made it dark, and picks matching colors. If a panel is hard to read, choose Light or Dark.",
  ["settings.slotOverlays"] = "Avoid double display",
  ["settings.slotOverlays.auto"] = "Automatic",
  ["settings.slotOverlays.ours"] = "Always show ours",
  ["settings.slotOverlays.none"] = "Hide ours",
  ["settings.slotOverlaysHint"] = "Some UI add-ons draw item level or enchants next to the slots of the character and inspect window themselves. Automatic hides our texts that show the same and keeps the gems and the warning for a missing enchant. Hide ours removes all of our slot texts.",
  ["settings.keys"] = "Key bindings",
  ["settings.keysHint"] = "Not preset. Set your keys under AddOns > Forever Guides. Current keys:",
  ["settings.keysOpen"] = "Open key bindings",
  ["settings.keysUnbound"] = "not set",
  ["settings.keysFallback"] = "Open Esc > Options > Key Bindings > Forever Guides",
  ["settings.winStyle"] = "Window appearance",
  ["settings.winStyleHint"] = "Default for floating windows. Each window can differ.",
  ["settings.winStyle.note"] = "Note windows",
  ["settings.winStyle.drawing"] = "Drawing windows",
  ["settings.reopenNoteWindows"] = "Reopen last opened note windows at start",
  ["settings.reopenNoteWindowsHint"] = "Open note windows return at the next login. On by default.",
  ["settings.feedback"] = "Feedback",
  ["settings.feedbackHelp"] = 'Off (default): no confirmations, errors and warnings still show as a toast.\nToast: small message at the top right, disappears on its own.\nExample: "Drawing House saved".\nChat: message as a line in the chat window.\nHovering pauses the timer.\nClick closes it, right-click closes all.\nErrors and warnings can also go to chat.\nThe last 50 messages, whatever the setting: "Recent messages".\nNot affected: chat links of shared notes and drawings.',
  ["settings.feedbackModeLabel"] = "Where should feedback appear?",
  ["settings.feedback.off"] = "Off (only errors and warnings as a toast)",
  ["settings.feedback.toast"] = "Toast (small window at the top right)",
  ["settings.feedback.chat"] = "Chat",
  ["settings.feedback.both"] = "Both",
  ["settings.feedbackErrors"] = "Also show errors and warnings in chat",
  ["settings.feedbackErrorsHint"] = "For Off and Toast only. Chat and Both show them in chat anyway.",
  ["settings.feedbackTest"] = "Send test message",
  ["settings.feedbackHistory"] = "Recent messages",
  ["settings.toastPosition"] = "Adjust position",
  ["settings.toastPositionDone"] = "Done adjusting",
  ["settings.toastPositionHint"] = "Shows a sample toast. Drag it, then right-click or press the button again.",
  ["settings.toastReset"] = "Reset toast position",
  ["settings.roster"] = "Character list",
  ["settings.rosterSave"] = "Save character list",
  ["settings.rosterHint"] = "Saves name, race, class, level, gold, zone, guild, item level and professions of each character you log in with.\nStays in your SavedVariables on this computer, never sent anywhere.\nShown on the start page.\nSwitching off stops saving. Stored entries stay until you remove them on the start page.",
  ["settings.packages"] = "Add-on packages",
  ["settings.packagesHint"] = "Switch on here, off in the add-on list in game.",
  ["settings.pkg.professions"] = "Profession data",
  ["settings.pkg.recipes"] = "Recipes",
  ["settings.pkg.guild"] = "Guild manager",
  ["settings.pkg.loaded"] = "On",
  ["settings.pkg.disabled"] = "Off",
  ["settings.pkg.missing"] = "Missing",
  ["settings.tab.general"] = "General",
  ["settings.tab.window"] = "Appearance",
  ["settings.tab.map"] = "Map and travel",
  ["settings.tab.items"] = "Items",
  ["settings.tab.bags"] = "Loot and inventory",
  ["settings.tab.sell"] = "Selling",
  ["settings.tab.automation"] = "Automation",
  ["settings.tab.social"] = "Guild and contacts",
  ["settings.tab.advanced"] = "Advanced",
})
ns.AddLocale("deDE", {
  ["settings.buttonLabels"] = "Beschriftung an Symbolknöpfen anzeigen",
  ["settings.buttonLabelsHint"] = "Knöpfe zeigen ein kurzes Wort neben ihrem Symbol. Aus: nur Symbole, der Tooltip nennt die Aktion. Schmale Stellen blenden den Text selbst aus.",
  ["settings.hostSkin"] = "Verhalten mit anderen UI-Addons",
  ["settings.hostSkin.auto"] = "Automatisch (folgt dem Fenster)",
  ["settings.hostSkin.light"] = "Hell (Original-Look von Blizzard)",
  ["settings.hostSkin.dark"] = "Dunkel (eigene dunkle Fläche)",
  ["settings.hostSkinHint"] = "Forever Guides ergänzt Blizzard-Fenster um eigene Bereiche, zum Beispiel die Lernliste im Zauberbuch. Automatisch erkennt, ob das Fenster hell dargestellt wird oder ein UI-Addon es dunkel gemacht hat, und wählt passende Farben. Ist ein Bereich schwer lesbar, wähle Hell oder Dunkel.",
  ["settings.slotOverlays"] = "Doppelte Anzeige vermeiden",
  ["settings.slotOverlays.auto"] = "Automatisch",
  ["settings.slotOverlays.ours"] = "Immer unsere zeigen",
  ["settings.slotOverlays.none"] = "Unsere ausblenden",
  ["settings.slotOverlaysHint"] = "Manche UI-Addons zeichnen Itemlevel oder Verzauberungen selbst neben die Slots im Charakter- und Betrachten-Fenster. Automatisch blendet dann unsere Texte aus, die dasselbe zeigen, und behält Sockel sowie die Warnung bei fehlender Verzauberung. Unsere ausblenden entfernt alle unsere Slot-Texte.",
  ["settings.keys"] = "Tastenbelegung",
  ["settings.keysHint"] = "Nicht vorbelegt. Eigene Tasten unter AddOns > Forever Guides. Aktuelle Tasten:",
  ["settings.keysOpen"] = "Tastenbelegung öffnen",
  ["settings.keysUnbound"] = "nicht belegt",
  ["settings.keysFallback"] = "Öffne ESC > Optionen > Tastaturbelegung > Forever Guides",
  ["settings.winStyle"] = "Fenster-Darstellung",
  ["settings.winStyleHint"] = "Standard für schwebende Fenster. Jedes Fenster kann abweichen.",
  ["settings.winStyle.note"] = "Notizfenster",
  ["settings.winStyle.drawing"] = "Zeichnungsfenster",
  ["settings.reopenNoteWindows"] = "Beim Start zuletzt geöffnete Notizfenster wieder öffnen",
  ["settings.reopenNoteWindowsHint"] = "Offene Notizfenster kommen beim nächsten Login zurück. Standardmäßig an.",
  ["settings.feedback"] = "Rückmeldungen",
  ["settings.feedbackHelp"] = "Aus (Standard): keine Bestätigungen, Fehler und Warnungen erscheinen weiter als Toast.\nToast: kleine Meldung oben rechts, verschwindet von selbst.\nBeispiel: „Zeichnung Haus gespeichert“.\nChat: Meldung als Zeile im Chatfenster.\nMaus darüber pausiert den Timer.\nKlick schließt ihn, Rechtsklick schließt alle.\nFehler und Warnungen können zusätzlich im Chat erscheinen.\nDie letzten 50 Meldungen, egal bei welcher Einstellung: „Letzte Meldungen“.\nNicht betroffen: Chat-Links geteilter Notizen und Zeichnungen.",
  ["settings.feedbackModeLabel"] = "Wo sollen Rückmeldungen erscheinen?",
  ["settings.feedback.off"] = "Aus (nur Fehler und Warnungen als Toast)",
  ["settings.feedback.toast"] = "Toast (kleines Fenster oben rechts)",
  ["settings.feedback.chat"] = "Chat",
  ["settings.feedback.both"] = "Beides",
  ["settings.feedbackErrors"] = "Fehler und Warnungen zusätzlich im Chat",
  ["settings.feedbackErrorsHint"] = "Nur für Aus und Toast. Bei Chat und Beides ohnehin im Chat.",
  ["settings.feedbackTest"] = "Testmeldung senden",
  ["settings.feedbackHistory"] = "Letzte Meldungen",
  ["settings.toastPosition"] = "Position anpassen",
  ["settings.toastPositionDone"] = "Anpassen beenden",
  ["settings.toastPositionHint"] = "Zeigt einen Beispiel-Toast. Ziehen, dann Rechtsklick oder Knopf erneut drücken.",
  ["settings.toastReset"] = "Toast-Position zurücksetzen",
  ["settings.roster"] = "Charakterliste",
  ["settings.rosterSave"] = "Charakterliste speichern",
  ["settings.rosterHint"] = "Speichert Name, Volk, Klasse, Stufe, Gold, Zone, Gilde, Gegenstandsstufe und Berufe jedes angemeldeten Charakters.\nBleibt in deinen SavedVariables auf diesem Rechner, wird nirgendwohin gesendet.\nAnzeige auf der Startseite.\nAusschalten stoppt das Speichern. Gespeicherte Einträge bleiben, bis du sie auf der Startseite entfernst.",
  ["settings.packages"] = "Zusatzpakete",
  ["settings.packagesHint"] = "Hier einschalten, in der Addon-Liste im Spiel ausschalten.",
  ["settings.pkg.professions"] = "Berufsdaten",
  ["settings.pkg.recipes"] = "Rezepte",
  ["settings.pkg.guild"] = "GildenManager",
  ["settings.pkg.loaded"] = "An",
  ["settings.pkg.disabled"] = "Aus",
  ["settings.pkg.missing"] = "Fehlt",
  ["settings.tab.general"] = "Allgemein",
  ["settings.tab.window"] = "Darstellung",
  ["settings.tab.map"] = "Karte und Reise",
  ["settings.tab.items"] = "Items",
  ["settings.tab.bags"] = "Beute und Bestand",
  ["settings.tab.sell"] = "Verkauf",
  ["settings.tab.automation"] = "Automatik",
  ["settings.tab.social"] = "Gilde und Kontakte",
  ["settings.tab.advanced"] = "Erweitert",
})

local function keysText()
  local lines = {}
  for _, b in ipairs(ns.KeyBindings.list) do
    lines[#lines + 1] = ns.L[b.label] .. ": " .. (ns.KeyBindings.KeysText(b.name) or ns.L["settings.keysUnbound"])
  end
  return table.concat(lines, "\n")
end

-- Default look of the floating windows: color, opacity and auto-hide per window kind, one
-- text shadow policy for all. Store.set emits FG_SETTING_CHANGED, open windows follow.
local function windowStyleSection(view)
  local s = view.stack
  local previews = {}
  local function repaint()
    for _, preview in ipairs(previews) do
      preview:Refresh()
    end
  end
  ns.AddHeading(view, "settings.winStyle")
  ns.AddParagraph(view, "settings.winStyleHint", { role = "micro", color = "textMuted" })
  for _, kind in ipairs({ "note", "drawing" }) do
    local prefix = WS.PREFIX[kind]
    local function get()
      return WS.Defaults(kind)
    end
    s:Add(W.Text(view.content, { key = "settings.winStyle." .. kind, role = "ui", color = "accent" }), { gap = 6 })
    s:Add(
      WS.NewControls(view.content, {
        width = 320,
        get = get,
        set = function(patch)
          if patch.bg ~= nil then
            Store.set("settings." .. prefix .. "Bg", patch.bg or WS.FALLBACK.bg)
          end
          if patch.alpha ~= nil then
            Store.set("settings." .. prefix .. "Alpha", patch.alpha)
          end
          if patch.autoHide ~= nil then
            Store.set("settings." .. prefix .. "AutoHide", patch.autoHide)
          end
          repaint()
        end,
      }),
      { height = 104, width = 320, gap = 8 }
    )
    local preview = WS.NewPreview(view.content, { get = get })
    previews[#previews + 1] = preview
    s:Add(preview, { height = 36, width = 168, gap = 12 })
  end
  s:Add(
    W.Dropdown(view.content, {
      key = "wstyle.shadow",
      options = {
        { value = "auto", key = "wstyle.shadow.auto" },
        { value = "on", key = "wstyle.shadow.on" },
        { value = "off", key = "wstyle.shadow.off" },
      },
      get = function()
        return WS.Defaults("note").textShadow
      end,
      set = function(v)
        Store.set("settings." .. WS.SHADOW_KEY, v)
        repaint()
      end,
    }),
    { height = 46, width = 240 }
  )
end

-- Prominent explanation block: wrapped text on a surface with an accent edge. The stack
-- asks it for its height through fgGridLayout.
local function callout(view, key)
  local f = CreateFrame("Frame", nil, view.content)
  W.Fill(f, "surface2", 1)
  local edge = f:CreateTexture(nil, "ARTWORK")
  edge:SetPoint("TOPLEFT")
  edge:SetPoint("BOTTOMLEFT")
  edge:SetWidth(3)
  ns.Bind(edge, function(t)
    t:SetColorTexture(ns.Theme.color("accent2"))
  end)
  f.text = W.Text(f, { key = key, role = "text", color = "text", wrap = true })
  f.text:SetPoint("TOPLEFT", 14, -10)
  function f:fgGridLayout(width)
    f.text:SetWidth(width - 28)
    local h = f.text:GetStringHeight() + 20
    f:SetHeight(h)
    return h
  end
  return f
end

-- Where feedback appears: off (default), toast, chat or both, plus the toast tools.
local function feedbackSection(view)
  local s = view.stack
  local Notify, Toast = ns.Notify, ns.Toast
  ns.AddHeading(view, "settings.feedback")
  s:Add(callout(view, "settings.feedbackHelp"), { gap = 12 })
  local mode = W.Dropdown(view.content, {
    key = "settings.feedbackModeLabel",
    width = 280,
    options = {
      { value = "off", key = "settings.feedback.off" },
      { value = "toast", key = "settings.feedback.toast" },
      { value = "chat", key = "settings.feedback.chat" },
      { value = "both", key = "settings.feedback.both" },
    },
    get = Notify.mode,
    set = function(v)
      Store.set("settings.feedback", v)
    end,
  })
  mode.fgId = "feedback-mode"
  s:Add(mode, { height = 46, width = 280 })
  local errors = W.Toggle(view.content, {
    key = "settings.feedbackErrors",
    get = Notify.errorsInChat,
    set = function(v)
      Store.set("settings.feedbackErrorsInChat", v)
    end,
  })
  errors.fgId = "feedback-errors"
  s:Add(errors, { height = 24, gap = 6 })
  ns.AddParagraph(view, "settings.feedbackErrorsHint", { role = "micro", color = "textMuted" })
  local function button(key, label, icon, onClick)
    local b =
      W.Action(view.content, { label = label, icon = icon, tooltip = key, width = 220, height = 28, onClick = onClick })
    s:Add(b, { height = 28, width = 220 })
    return b
  end
  button("settings.feedbackTest", "act.test", "play", Toast.SendTest)
  button("settings.feedbackHistory", "act.history", "history", Toast.OpenHistory)
  local position
  position = button("settings.toastPosition", "act.move", "marker", function()
    Toast.SetEditing(not Toast.IsEditing())
  end)
  local function syncPosition()
    W.SetText(position.label, Toast.IsEditing() and "act.done" or "act.move")
  end
  -- A right-click on the sample toast also ends the mode.
  ns.On("FG_TOAST_EDITING", syncPosition)
  position.Refresh = syncPosition
  button("settings.toastReset", "act.reset", "reset", Toast.ResetPosition)
  ns.AddParagraph(view, "settings.toastPositionHint", { role = "micro", color = "textMuted" })
end

-- Optional add-ons next to this one: one line each with their state and the button that switches
-- them on and loads them (ns.PackageUI).
local PACKAGES = {
  { name = "ForeverGuides_Professions", key = "settings.pkg.professions" },
  { name = "ForeverGuides_Recipes", key = "settings.pkg.recipes" },
  { name = "ForeverGuides_GildenManager", key = "settings.pkg.guild" },
}

local function packagesSection(view)
  ns.AddHeading(view, "settings.packages")
  for _, pkg in ipairs(PACKAGES) do
    local row = ns.PackageUI.Banner(view.content, pkg.name, {
      labelKey = pkg.key,
      showLoaded = true,
      onResize = function()
        view:Layout()
      end,
    })
    row.fgId = "settings-pkg-" .. pkg.name
    -- The state may have changed in the add-on list: Show() calls row:Refresh() whenever the page opens.
    view.stack:Add(row, { gap = 8 })
  end
  ns.AddParagraph(view, "settings.packagesHint", { role = "micro", color = "textMuted" })
end

-- The tabs of the page. A section is added to a tab with a function build(view); the built-in
-- sections below call the Add functions of their modules, other modules append theirs with
-- ns.SettingsPage.Add(build, tab).
local PAD = 16
local TAB_LIST = { "general", "window", "map", "items", "bags", "sell", "automation", "social", "advanced" }
local TABS = {}
for _, id in ipairs(TAB_LIST) do
  TABS[id] = true
end

local SP = { TABS = TAB_LIST }
ns.SettingsPage = SP

local extra = {}

-- Appends a section to a tab (default "general"; an unknown tab id falls back to it). build(view)
-- runs when the page is built, after the built-in sections of that tab, and fills a card of its own.
function SP.Add(build, tab)
  tab = TABS[tab] and tab or "general"
  extra[tab] = extra[tab] or {}
  table.insert(extra[tab], build)
end

local function toggle(view, key, labelKey, after, tooltipText)
  local get, set = setting(key)
  view.stack:Add(
    W.Toggle(view.content, {
      key = labelKey,
      get = get,
      set = function(v)
        set(v)
        if after then
          after(v)
        end
      end,
      tooltip = labelKey,
      tooltipText = tooltipText,
    }),
    { height = 24, gap = 6 }
  )
end

local function button(view, key, label, icon, onClick)
  view.stack:Add(
    W.Action(view.content, { label = label, icon = icon, tooltip = key, width = 220, height = 28, onClick = onClick }),
    { height = 28, width = 220 }
  )
end

-- Sections: each function fills one card (a view-like object with content, stack and Layout).
local function setupSection(view)
  ns.AddHeading(view, "setup.title")
  view.stack:Add(
    W.Action(view.content, {
      label = "act.start",
      icon = "play",
      tooltip = "setup.start",
      width = 220,
      onClick = function()
        ns.SetupWizardUI.Open()
      end,
    }),
    { height = 28, width = 220 }
  )
end

local function languageSection(view)
  ns.AddHeading(view, "settings.language")
  view.stack:Add(
    W.Dropdown(view.content, {
      key = "settings.languageLabel",
      options = {
        { value = "auto", key = "settings.lang.auto" },
        { value = "deDE", text = "Deutsch" },
        { value = "enUS", text = "English" },
      },
      get = function()
        return ns.db.settings.locale
      end,
      set = function(v)
        Store.set("settings.locale", v)
        ns.SetLocale(v)
        ns.RefreshUI()
        ns.Main.InvalidateViews()
      end,
    }),
    { height = 46, width = 240 }
  )
end

local function accessSection(view)
  ns.AddHeading(view, "settings.access")
  local fontScale = W.Slider(view.content, {
    key = "settings.fontScale",
    min = Theme.FONT_SCALE_MIN,
    max = Theme.FONT_SCALE_MAX,
    step = 0.05,
    get = Theme.fontScale,
    set = function(v)
      Store.set("settings.fontScale", v)
      ns.Debounce("font-scale", 0.2, restyle)
    end,
    format = function(v)
      return string.format("%d %%", math.floor(v * 100 + 0.5))
    end,
  })
  view.stack:Add(fontScale, { height = 42, width = 320 })
  -- The reset of the typography section changes the same value.
  ns.On("FG_SETTING_CHANGED", function(_, path)
    -- Not while the player drags this slider: it already shows the value.
    if path == "settings.fontScale" and math.abs(fontScale.slider:GetValue() - Theme.fontScale()) > 0.001 then
      fontScale:Refresh()
    end
  end)
  toggle(view, "contrast", "settings.contrast", restyle)
  toggle(view, "colorblind", "settings.colorblind", restyle, "settings.colorblindHint")
  toggle(view, "reduceMotion", "settings.reduceMotion")
end

local function rosterSection(view)
  ns.AddHeading(view, "settings.roster")
  local roster = W.Toggle(view.content, {
    key = "settings.rosterSave",
    get = ns.CharRoster.Enabled,
    set = ns.CharRoster.SetEnabled,
  })
  roster.fgId = "roster-save"
  view.stack:Add(roster, { height = 24, gap = 6 })
  ns.AddParagraph(view, "settings.rosterHint", { role = "micro", color = "textMuted" })
end

local function keysSection(view)
  ns.AddHeading(view, "settings.keys")
  ns.AddParagraph(view, "settings.keysHint", { role = "micro", color = "textMuted" })
  button(view, "settings.keysOpen", "act.keys", "open", function()
    if not ns.KeyBindings.OpenUI() then
      ns.Notify(ns.L["settings.keysFallback"], "info")
    end
  end)
  -- The keys can change in the game's own dialog: the list repaints whenever the page opens.
  local keyList = W.Text(view.content, { role = "micro", color = "textSecondary", wrap = true })
  view.stack:Add(keyList)
  local function paintKeys()
    keyList:SetText(keysText())
  end
  keyList.Refresh = paintKeys
  ns.Bind(keyList, paintKeys)
end

local function windowSection(view)
  ns.AddHeading(view, "settings.window")
  local scale = W.Slider(view.content, {
    key = "settings.scale",
    min = 0.7,
    max = 1.5,
    step = 0.05,
    applyOn = "release",
    get = function()
      return ns.db.settings.scale
    end,
    set = function(v, anchor)
      ns.Main.SetScale(v, anchor)
    end,
    format = function(v)
      return string.format("%d %%", math.floor(v * 100 + 0.5))
    end,
  })
  view.stack:Add(scale, { height = 42, width = 320 })
  -- The footer zoom buttons change the same value.
  ns.On("FG_SETTING_CHANGED", function(_, path)
    if path == "settings.scale" then
      scale:Refresh()
    end
  end)
  ns.AddParagraph(view, "settings.scaleHint", { role = "micro", color = "textMuted" })
  button(view, "settings.resetWindow", "act.reset", "reset", function()
    ns.Main.ResetGeometry()
  end)
  button(view, "settings.dock", "act.compact", "open", function()
    ns.Dock.Toggle()
  end)
  toggle(view, "combatHide", "settings.combatHide")
  view.stack:Add(
    W.Toggle(view.content, {
      key = "settings.minimap",
      get = function()
        return not ns.db.settings.minimap.hide
      end,
      set = function(v)
        ns.db.settings.minimap.hide = not v
        ns.MinimapButton.Apply()
      end,
    }),
    { height = 24, gap = 6 }
  )
  toggle(view, "sidebarCollapsed", "settings.sidebarCollapsed", function()
    ns.Main.Relayout()
  end, "settings.sidebarCollapsedHint")
  toggle(view, "buttonLabels", "settings.buttonLabels", restyle, "settings.buttonLabelsHint")
  toggle(view, "characterButton", "blizz.set.character", function()
    ns.BlizzardLinks.Apply()
  end)
  toggle(view, "hideTalkingHead", "settings.hideTalkingHead", function()
    ns.TalkingHead.Apply()
  end, "settings.hideTalkingHeadHint")
  local hostSkin = W.Dropdown(view.content, {
    key = "settings.hostSkin",
    width = 280,
    options = {
      { value = "auto", key = "settings.hostSkin.auto" },
      { value = "light", key = "settings.hostSkin.light" },
      { value = "dark", key = "settings.hostSkin.dark" },
    },
    get = function()
      return ns.db.settings.hostSkin
    end,
    set = function(v)
      Store.set("settings.hostSkin", v)
      ns.RefreshUI()
    end,
  })
  hostSkin.fgId = "host-skin"
  view.stack:Add(hostSkin, { height = 46, width = 280 })
  ns.AddParagraph(view, "settings.hostSkinHint", { role = "micro", color = "textMuted" })
  local slotOverlays = W.Dropdown(view.content, {
    key = "settings.slotOverlays",
    width = 280,
    options = {
      { value = "auto", key = "settings.slotOverlays.auto" },
      { value = "ours", key = "settings.slotOverlays.ours" },
      { value = "none", key = "settings.slotOverlays.none" },
    },
    get = function()
      return ns.db.settings.slotOverlays
    end,
    set = function(v)
      Store.set("settings.slotOverlays", v)
      ns.RefreshUI()
    end,
  })
  slotOverlays.fgId = "slot-overlays"
  view.stack:Add(slotOverlays, { height = 46, width = 280 })
  ns.AddParagraph(view, "settings.slotOverlaysHint", { role = "micro", color = "textMuted" })
end

local function styleSection(view)
  windowStyleSection(view)
  local reopen = W.Toggle(view.content, {
    key = "settings.reopenNoteWindows",
    get = function()
      return ns.db.settings.reopenNoteWindows == true
    end,
    set = function(v)
      Store.set("settings.reopenNoteWindows", v)
    end,
  })
  reopen.fgId = "note-reopen"
  view.stack:Add(reopen, { height = 24, gap = 6 })
  ns.AddParagraph(view, "settings.reopenNoteWindowsHint", { role = "micro", color = "textMuted" })
end

local function worldMapSection(view)
  ns.AddHeading(view, "wm.set.heading")
  for _, item in ipairs({
    { "worldMapButton", "wm.set.button" },
    { "worldMapPanel", "wm.set.bar" },
    { "worldMapPins", "wm.set.pins" },
  }) do
    toggle(view, item[1], item[2], function()
      ns.WorldMapLinks.Apply()
    end)
  end
  toggle(view, "dungeonWorldMap", "dwm.set", function()
    ns.DungeonWorldMap.Apply()
  end)
end

local function flightSection(view)
  ns.AddHeading(view, "flightlabel.heading")
  toggle(view, "flightLabels", "flightlabel.enable")
  toggle(view, "flightTooltip", "flightlabel.tooltip")
  toggle(view, "flightTimer", "flighttimer.enable")
  view.stack:Add(
    W.Slider(view.content, {
      key = "flightlabel.size",
      min = ns.FlightLabels.SIZE_MIN,
      max = ns.FlightLabels.SIZE_MAX,
      step = 1,
      get = ns.FlightLabels.FontSize,
      set = function(v)
        Store.set("settings.flightFontSize", v)
      end,
      format = function(v)
        return string.format("%d px", math.floor(v + 0.5))
      end,
    }),
    { height = 42, width = 320 }
  )
end

local function advancedSection(view)
  ns.AddHeading(view, "settings.advanced")
  button(view, "settings.openTutorials", "act.tour", "play", function()
    ns.Router:navigate("tutorials")
  end)
end

-- The buttons an extension registers for the settings (slot "settings") under the head it sets.
-- Built only when there is a button, see the loop in build.
local function extensionSection(view)
  ns.DevTools.AddButtons(view, "settings")
end

-- The sections of each tab in page order, one card each.
local SECTIONS = {
  general = {
    setupSection,
    languageSection,
    feedbackSection,
    rosterSection,
    keysSection,
    function(view)
      ns.KeysSettings.Add(view)
    end,
    packagesSection,
  },
  window = {
    windowSection,
    function(view)
      ns.Appearance.AddSettings(view)
    end,
    styleSection,
    accessSection,
    function(view)
      ns.TypographySettings.Add(view)
    end,
  },
  map = {
    worldMapSection,
    flightSection,
    function(view)
      ns.GatherSparklesSettings.Add(view)
    end,
  },
  items = {
    function(view)
      ns.ItemLevelSettings.Add(view)
    end,
    function(view)
      ns.InspectPage.AddSettings(view)
    end,
  },
  bags = {
    function(view)
      ns.LootPage.AddSettings(view)
    end,
    function(view)
      ns.InventorySettings.Add(view)
    end,
    function(view)
      ns.ProfessionTracker.AddSettings(view)
    end,
  },
  sell = {
    function(view)
      ns.SellSettings.Add(view)
    end,
  },
  automation = {
    function(view)
      ns.AutomationSettings.Add(view)
    end,
  },
  social = {
    function(view)
      ns.InviteSettings.Add(view)
    end,
    function(view)
      ns.AutomationSettings.AddInvites(view)
    end,
    function(view)
      ns.GuildPage.AddSettings(view)
    end,
  },
  advanced = {
    advancedSection,
    function(view)
      ns.ErrorCatcher.AddSettings(view)
    end,
    extensionSection,
  },
}

-- The tab that opens next, kept per character. Anything unknown means the first one.
local function savedTab()
  local id = ns.charDB and ns.charDB.settingsTab
  return TABS[id] and id or TAB_LIST[1]
end

-- Selects a tab, also before the page exists: /fg automatik opens the settings on its tab.
function SP.Select(id)
  if not TABS[id] then
    return false
  end
  if ns.charDB then
    ns.charDB.settingsTab = id
  end
  if SP.page then
    SP.page:Select(id)
  end
  return true
end

function SP.Current()
  return SP.page and SP.page.current or savedTab()
end

local function build(container)
  local FL = ns.FlowLayout
  local page = { tabs = {}, current = savedTab() }
  SP.page = page

  -- The tab row wraps instead of cutting off, the selected tab has a bar (and its own color).
  local defs = {}
  for _, id in ipairs(TAB_LIST) do
    defs[#defs + 1] = {
      id = id,
      key = "settings.tab." .. id,
      variant = "ghost",
      fgId = "settings-tab-" .. id,
      onClick = function()
        page:Select(id)
      end,
    }
  end
  local row = FL.ButtonRow(container, defs)
  row:SetPoint("TOPLEFT", container, "TOPLEFT", PAD, -PAD)
  row:SetPoint("TOPRIGHT", container, "TOPRIGHT", -PAD, -PAD)
  page.row = row

  local function paintTabs()
    for _, id in ipairs(TAB_LIST) do
      local b = row:GetButton(id)
      local on = id == page.current
      b.bar:SetShown(on)
      W.SetColor(b.label, on and "accent" or "textSecondary")
    end
  end
  for _, id in ipairs(TAB_LIST) do
    local b = row:GetButton(id)
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("BOTTOMLEFT", 4, 0)
    b.bar:SetPoint("BOTTOMRIGHT", -4, 0)
    b.bar:SetHeight(2)
    ns.Bind(b.bar, function(t)
      t:SetColorTexture(ns.Theme.color("accent2"))
    end)
    b:HookScript("OnEnter", paintTabs)
    b:HookScript("OnLeave", paintTabs)
  end

  -- One scrolling view per tab, built once; only the selected one is shown.
  local body = CreateFrame("Frame", nil, container)
  body:SetPoint("TOPLEFT", row, "BOTTOMLEFT", -PAD, -8)
  body:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
  for _, id in ipairs(TAB_LIST) do
    local view = ns.NewPageView(body)
    view.area:Hide()
    local grid = ns.SettingsGrid.New(view)
    for _, section in ipairs(SECTIONS[id]) do
      if section ~= extensionSection or #ns.DevTools.Slot("settings") > 0 then
        section(grid:Card())
      end
    end
    for _, add in ipairs(extra[id] or {}) do
      ns.Safe("settings-section", add, grid:Card())
    end
    page.tabs[id] = view
  end

  local function refresh(view)
    for _, entry in ipairs(view.stack.items) do
      if entry.item.Refresh then
        entry.item:Refresh()
      end
    end
  end

  function page:Select(id)
    if not (TABS[id] and page.tabs[id]) then
      return
    end
    page.current = id
    if ns.charDB then
      ns.charDB.settingsTab = id
    end
    for tabId, view in pairs(page.tabs) do
      view.area:SetShown(tabId == id)
    end
    paintTabs()
    refresh(page.tabs[id])
    page.tabs[id]:Layout()
  end

  function page:Layout()
    local width = container:GetWidth()
    if width and width > 2 * PAD then
      row:SetWidthAvailable(width - 2 * PAD)
    end
    local view = page.tabs[page.current]
    if view then
      view:Layout()
    end
  end

  -- Values can change elsewhere (Ctrl+wheel, /fg scale, reset, the key bindings dialog).
  function page:Show()
    for id, view in pairs(page.tabs) do
      if id ~= page.current then
        refresh(view)
      end
    end
    page:Select(savedTab())
  end
  return page
end

ns.RegisterPage({
  id = "settings",
  order = 710,
  group = "system",
  title = "page.settings",
  icon = ns.ICONS.settings,
  aliases = { "einstellungen", "optionen", "settings", "options" },
  build = build,
})
