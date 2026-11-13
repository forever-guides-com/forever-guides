-- Settings page: 8 groups with 43 features as tabs (Modules/SettingsFeatures.lua, drawn by
-- Modules/SettingsNav.lua). Every feature is a grid of cards (Modules/SettingsGrid.lua), one card per
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
  ["settings.hudwindowsHint"] = "The HUD windows have their own page in the main menu. Size, position and content are set there.",
  ["settings.hudwindowsOpen"] = "Open HUD windows",
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
  ["settings.pkg.professions"] = "Profession data",
  ["settings.pkg.recipes"] = "Recipes",
  ["settings.pkg.loaded"] = "On",
  ["settings.pkg.disabled"] = "Off",
  ["settings.pkg.missing"] = "Missing",
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
  ["settings.hudwindowsHint"] = "Die HUD-Fenster haben eine eigene Seite im Hauptmenü. Größe, Position und Inhalt stellst du dort ein.",
  ["settings.hudwindowsOpen"] = "HUD-Fenster öffnen",
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
  ["settings.pkg.professions"] = "Berufsdaten",
  ["settings.pkg.recipes"] = "Rezepte",
  ["settings.pkg.loaded"] = "An",
  ["settings.pkg.disabled"] = "Aus",
  ["settings.pkg.missing"] = "Fehlt",
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
  local function button(target, key, label, icon, onClick, opens)
    local b = W.Action(target.content, {
      label = label,
      icon = icon,
      tooltip = key,
      width = 220,
      height = 28,
      opens = opens,
      onClick = onClick,
    })
    b.fgId = "button-" .. key:gsub("%.", "-")
    target.stack:Add(b, { height = 28, width = 220 })
    return b
  end
  button(view, "settings.feedbackTest", "act.test", "play", Toast.SendTest)
  -- History and the place of the toast are set once: behind "More settings".
  local more = W.Accordion(view, { id = view.id or "messages.feedback" })
  button(more, "settings.feedbackHistory", "act.history", "history", Toast.OpenHistory, true)
  local position
  position = button(more, "settings.toastPosition", "act.move", "marker", function()
    Toast.SetEditing(not Toast.IsEditing())
  end)
  local function syncPosition()
    W.SetText(position.label, Toast.IsEditing() and "act.done" or "act.move")
  end
  -- A right-click on the sample toast also ends the mode.
  ns.On("FG_TOAST_EDITING", syncPosition)
  position.Refresh = syncPosition
  button(more, "settings.toastReset", "act.reset", "reset", Toast.ResetPosition)
  ns.AddParagraph(more, "settings.toastPositionHint", { role = "micro", color = "textMuted" })
end

-- The settings are features, each with cards (Modules/SettingsFeatures.lua). A card is added with a
-- function build(view); the built-in cards below call the Add functions of their modules, other modules
-- register theirs with ns.SettingsPage.Add(build, target, cardId).
local PAD = 16
local L = ns.SettingsFeatureLogic

local SP = {}
ns.SettingsPage = SP

-- Card builders by card id, and the cards a module adds without an id the registry knows (a sub-add-on of
-- an older version) per feature.
local builders = {}
local late = {}

-- Registers the builder of a card. target is a feature or an old tab id and only matters while the id
-- is unknown to the registry: the card then goes to the end of that feature (an unknown target means
-- the first feature). build(view) fills a card of its own when the feature is built.
function SP.Add(build, target, cardId)
  local feature = cardId and L.CardFeature(cardId)
  if feature then
    builders[cardId] = { build = build, safe = true }
  else
    feature = L.FeatureOrFirst(target)
    late[feature] = late[feature] or {}
    table.insert(late[feature], { build = build, id = cardId })
  end
  -- A sub-add-on that loads while the page stands shows its cards without a /reload.
  if SP.page and SP.page.features[feature] then
    ns.Debounce("settings-rebuild-" .. feature, 0, function()
      SP.page:Rebuild(feature)
    end)
  end
end

-- True when a module registered the builder of the card (a sub-add-on's card exists only while it is loaded).
function SP.HasCard(cardId)
  return builders[cardId] ~= nil
end

local function register(cardId, build, when)
  builders[cardId] = { build = build, when = when }
end

-- invert: the toggle shows the opposite of the stored value (on = feature shown, stored as hidden = false).
local function toggle(view, key, labelKey, after, tooltipText, invert)
  local get, set = setting(key)
  local control = W.Toggle(view.content, {
    key = labelKey,
    get = function()
      local v = get() and true or false
      if invert then
        v = not v
      end
      return v
    end,
    set = function(v)
      v = v and true or false
      if invert then
        v = not v
      end
      set(v)
      if after then
        after(v)
      end
    end,
    tooltip = labelKey,
    tooltipText = tooltipText,
  })
  control.fgId = "setting-" .. key
  view.stack:Add(control, { height = 24, gap = 6 })
end

local function button(view, key, label, icon, onClick, opens)
  local action = W.Action(view.content, {
    label = label,
    icon = icon,
    tooltip = key,
    width = 220,
    height = 28,
    opens = opens,
    onClick = onClick,
  })
  action.fgId = "button-" .. key:gsub("%.", "-")
  view.stack:Add(action, { height = 28, width = 220 })
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
      opens = true,
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
  end, true)
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
  scale.fgId = "setting-scale"
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
  local minimap = W.Toggle(view.content, {
    key = "settings.minimap",
    get = function()
      return not ns.db.settings.minimap.hide
    end,
    set = function(v)
      ns.db.settings.minimap.hide = not v
      ns.MinimapButton.Apply()
    end,
  })
  minimap.fgId = "setting-minimap"
  view.stack:Add(minimap, { height = 24, gap = 6 })
  -- Behaviour and looks of the window that one sets once: behind "More settings".
  local more = W.Accordion(view, { id = view.id or "window.size" })
  button(more, "settings.dock", "act.compact", "open", function()
    ns.Dock.Toggle()
  end)
  toggle(more, "combatHide", "settings.combatHide")
  toggle(more, "sidebarCollapsed", "settings.sidebarCollapsed", function()
    ns.Main.Relayout()
  end, "settings.sidebarCollapsedHint")
  toggle(more, "buttonLabels", "settings.buttonLabels", restyle, "settings.buttonLabelsHint")
  toggle(more, "characterButton", "blizz.set.character", function()
    ns.BlizzardLinks.Apply()
  end)
  toggle(more, "hideTalkingHead", "settings.hideTalkingHead", function()
    ns.TalkingHead.Apply()
  end, "settings.hideTalkingHeadHint", true)
  local hostSkin = W.Dropdown(more.content, {
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
  more.stack:Add(hostSkin, { height = 46, width = 280 })
  ns.AddParagraph(more, "settings.hostSkinHint", { role = "micro", color = "textMuted" })
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
  -- The pins of single map layers and the flight list are set once: behind "More settings".
  local more = W.Accordion(view, { id = view.id or "map.world" })
  view = more
  for _, item in ipairs({
    { "mapMarkersWorld", "mm.set.world" },
    { "mapMarkersAddonMap", "mm.set.addon" },
    { "mapMarkerDungeons", "mm.set.dungeons" },
    { "mapMarkerRaids", "mm.set.raids" },
  }) do
    toggle(view, item[1], item[2], function()
      ns.WorldMapInstancePins.Refresh()
      ns.MapInstancePins.Refresh()
    end)
  end
  toggle(view, "mapFlightWorld", "fp.set.world", function()
    ns.WorldMapFlightPins.Refresh()
  end)
  toggle(view, "mapFlightAddonMap", "fp.set.addon", function()
    ns.MapInstancePins.Refresh()
  end)
  toggle(view, "mapZoneArrowsWorld", "zb.set.world", function()
    ns.WorldMapZoneArrows.Refresh()
  end)
  toggle(view, "mapZoneArrowsAddonMap", "zb.set.addon", function()
    ns.MapInstancePins.Refresh()
  end)
  toggle(view, "mapZoneArrowsGuess", "zb.set.guess", function()
    ns.ZoneCrossingLogic.Touch()
  end, "zb.set.guessHint")
  toggle(view, "zoneCrossRecord", "zcr.set.record", function()
    ns.ZoneCrossingRecorder.Apply()
  end, "zcr.set.recordHint")
  toggle(view, "zoneCrossNotify", "zcr.set.notify")
  local count = W.Slider(view.content, {
    key = "fp.set.listCount",
    min = ns.FlightPointsLogic.COUNT_MIN,
    max = ns.FlightPointsLogic.COUNT_MAX,
    step = 1,
    get = ns.FlightPointList.Count,
    set = function(v)
      Store.set("settings.flightListCount", ns.FlightPointsLogic.ClampCount(v))
      ns.WorldMapLinks.Apply()
    end,
    format = function(v)
      return string.format("%d", math.floor(v + 0.5))
    end,
  })
  count.fgId = "setting-flightListCount"
  view.stack:Add(count, { height = 42, width = 320 })
  toggle(view, "flightListOnlyKnown", "fp.set.onlyKnown", function()
    ns.WorldMapLinks.Apply()
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
  end, true)
end

-- The buttons an extension registers for the settings (slot "settings") under the head it sets.
-- Built only when there is a button, see the loop in build.
local function extensionSection(view)
  ns.DevTools.AddButtons(view, "settings")
end

-- Built-in cards: the card id and the function that fills it. Module functions are looked up when the
-- feature is built, the modules load after this file.
local function call(module, fn, ...)
  local args = { ... }
  return function(view)
    ns[module][fn](view, unpack(args))
  end
end

-- The HUD windows are pages of the main menu, this card only points there.
local function hudWindowsSection(view)
  ns.AddHeading(view, "settings.feature.hudwindows")
  ns.AddParagraph(view, "settings.hudwindowsHint", { role = "micro", color = "textMuted" })
  button(view, "settings.hudwindowsOpen", "act.show", "open", function()
    ns.Router:navigate("areas")
  end, true)
end

-- The logos of guilds and communities are a sharing function: the card only points to its consent.
local function logosCrestsSection(view)
  ns.AddHeading(view, "settings.card.logos.crests")
  ns.AddParagraph(view, "settings.logosCrestsHint", { role = "micro", color = "textMuted" })
  button(view, "settings.logosCrestsOpen", "act.show", "open", function()
    ns.SettingsPage.Select("consents", "consents.crestMark")
  end, true)
end

register("setup.wizard", setupSection)
register("logos.crests", logosCrestsSection)
register("hudwindows.main", hudWindowsSection)
register("setup.tour", advancedSection)
register("setup.addons", call("AddonSettings", "AddOverview"))
register("language.main", languageSection)
register("messages.feedback", feedbackSection)
register("messages.errors", call("AutomationSettings", "AddErrors"))
register("automation.control", call("AutomationSettings", "AddControl"))
register("automation.overview", call("AutomationSettings", "AddOverview"))
register("diagnostics.errors", call("ErrorCatcher", "AddSettings"))
register("diagnostics.dev", extensionSection, function()
  return #ns.DevTools.Slot("settings") > 0
end)
register("window.size", windowSection)
register("window.look", call("Appearance", "AddSettings"))
register("notes.main", styleSection)
register("fonts.main", call("TypographySettings", "Add"))
register("access.main", accessSection)
register("keys.main", keysSection)
register("mouse.main", call("KeysSettings", "Add"))
register("farmhud.main", call("FarmHudSettings", "Add"))
register("map.world", worldMapSection)
register("flight.main", flightSection)
register("gathering.pins", call("GatheringSettings", "Add"))
register("gathering.sparkles", call("GatherSparklesSettings", "Add"))
register("gathering.sparkles.kinds", call("GatherSparklesSettings", "AddKinds"))
register("gathering.sparkles.general", call("GatherSparklesSettings", "AddGeneral"))
register("fishing.enable", call("AddonSettings", "AddEnable", "fishing"))
register("quests.main", call("AutomationSettings", "AddQuests"))
register("quests.exceptions", call("AutomationSettings", "AddQuestExceptions"))
register("professions.shopping", call("ProfessionTracker", "AddSettings"))
register("selling.repair", call("AutomationSettings", "AddRepair"))
for _, id in ipairs({ "selling.main", "sellrules.quality", "sellrules.binding", "sellrules.keep", "protect.main" }) do
  register(id, function(view)
    ns.SellSettings.BUILDERS[id](view)
  end)
end
register("items.itemlevel", call("ItemLevelSettings", "Add"))
register("items.inspect", call("InspectPage", "AddSettings"))
register("inventory.stock", call("InventorySettings", "Add"))
register("loot.main", call("LootPage", "AddSettings"))
register("foreverchat.enable", call("AddonSettings", "AddEnable", "chat"))
register("foreverchat.lines", call("ConsentSettings", "AddChatLines"))
register("party.summon", call("AutomationSettings", "AddSummon"))
register("party.duels", call("AutomationSettings", "AddDuels"))
register("guild.enable", call("AddonSettings", "AddEnable", "guildmanager"))
register("guild.inspect", call("GuildPage", "AddSettings"))
register("contacts.main", call("ContactsPage", "AddSettings"))
register("contacts.plates", call("ContactsPage", "AddPlates"))
register("invites.whisper", call("InviteSettings", "Add"))
register("invites.accept", call("AutomationSettings", "AddInvites"))
register("privacy.overview", call("ConsentSettings", "AddOverview"))
register("roster.main", rosterSection)

-- Features whose cards are not fixed: they add their cards to the grid after the listed ones.
local DYNAMIC = {
  consents = function(grid)
    ns.ConsentSettings.AddFunctionCards(grid)
  end,
  setup = function(grid)
    for _, entry in ipairs(ns.SubAddons.List()) do
      local id = ns.AddonSettings.CardId(entry.id)
      if not L.Card(id) then
        ns.AddonSettings.AddEnable(grid:Card({ id = id }), entry.id)
      end
    end
  end,
}

-- The feature that opens next, kept per character. A value of the old tab store (settingsTab) is
-- translated through the aliases and moved to settingsFeature. Anything unknown means the first feature.
local function savedFeature()
  local char = ns.charDB
  if not char then
    return L.FeatureOrFirst(nil)
  end
  local feature = L.FeatureOrFirst(char.settingsFeature or char.settingsTab)
  if char.settingsTab ~= nil or char.settingsFeature ~= feature then
    char.settingsFeature, char.settingsTab = feature, nil
  end
  return feature
end

-- The feature that was open last in each group, kept per character.
local function groupLast()
  local char = ns.charDB
  if not char then
    return {}
  end
  if type(char.settingsGroupLast) ~= "table" then
    char.settingsGroupLast = {}
  end
  return char.settingsGroupLast
end

local pending

-- Selects a feature and optionally one of its cards and one control of it, also before the page exists:
-- /fg automatik opens the settings there. target is a feature id or an old tab id, a card id also works on
-- its own. controlId is the id (fgId) of a control or the locale key of its name; a control behind a closed
-- "More settings" section opens it for now. A page that is not on screen keeps the jump until it shows.
function SP.Select(target, cardId, controlId)
  local feature, card = L.Target(target, cardId)
  if not feature then
    return false
  end
  if ns.charDB then
    ns.charDB.settingsFeature, ns.charDB.settingsTab = feature, nil
  end
  pending = { card = card, control = controlId }
  if SP.page then
    SP.page:Select(feature, card, controlId)
    if SP.page.container:IsVisible() then
      pending = nil
    end
  end
  return true
end

-- Jump from the label key of a command control (the "control" of Core/Commands.lua): opens its card, and
-- the "More settings" section that holds the control when it sits behind one.
function SP.SelectControl(controlKey)
  local card = ns.SettingsFeatures.CONTROLS[controlKey]
  if not card then
    return false
  end
  return SP.Select(card, card, ns.SettingsFeatures.CONTROL_IDS[controlKey])
end

function SP.Current()
  return SP.page and SP.page.current or savedFeature()
end

local function build(container)
  local page = { features = {}, current = savedFeature(), container = container }
  SP.page = page

  local nav = ns.SettingsNav.New(container, {
    current = page.current,
    groupLast = groupLast(),
    onSelect = function(id)
      page:Select(id)
    end,
    onHeight = function()
      local view = page.features[page.current]
      if view then
        view:Layout()
      end
    end,
  })
  nav.frame:SetPoint("TOPLEFT", container, "TOPLEFT", PAD, -PAD)
  nav.frame:SetPoint("TOPRIGHT", container, "TOPRIGHT", -PAD, -PAD)
  page.nav, page.row = nav, nav.frame

  local body = CreateFrame("Frame", nil, container)
  body:SetPoint("TOPLEFT", nav.frame, "BOTTOMLEFT", -PAD, -8)
  body:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)

  -- The view of a feature, built when it is first needed. Its cards come in the order of the registry,
  -- then the dynamic ones, then those of a module that did not name a card the registry knows.
  local function buildView(id)
    local view = ns.NewPageView(body)
    view.area:Hide()
    local grid = ns.SettingsGrid.New(view)
    for _, cardId in ipairs(L.Cards(id, nil, false)) do
      local entry = builders[cardId]
      if entry and (not entry.when or entry.when()) then
        local card = grid:Card({ id = cardId })
        if entry.safe then
          ns.Safe("settings-section", entry.build, card)
        else
          entry.build(card)
        end
      end
    end
    if DYNAMIC[id] then
      DYNAMIC[id](grid)
    end
    for _, add in ipairs(late[id] or {}) do
      ns.Safe("settings-section", add.build, grid:Card({ id = add.id }))
    end
    page.features[id] = view
    return view
  end

  -- The view of a feature or of the feature an old tab id stands for; nil for anything else.
  function page:View(target)
    local id = L.ResolveFeature(target)
    if not id then
      return nil
    end
    return self.features[id] or buildView(id)
  end

  -- Drops the built view of a feature and builds it again, the page keeps showing the feature it shows.
  function page:Rebuild(target)
    local id = L.ResolveFeature(target)
    local old = id and self.features[id]
    if not old then
      return
    end
    old.area:Hide()
    self.features[id] = nil
    if self.current == id then
      self:Select(id)
    end
  end

  local function refresh(view)
    for _, entry in ipairs(view.stack.items) do
      if entry.item.Refresh then
        entry.item:Refresh()
      end
    end
  end

  local function scrollToCard(view, cardId)
    for _, card in ipairs(view.grid.cards) do
      if card.id == cardId and card.top then
        view.area:ScrollTo(card.top)
        return
      end
    end
  end

  -- A control is named by its id (fgId) or by the locale key of its name. Without a card the first card that
  -- holds it answers. A control inside a closed "More settings" section opens the section (for now, the saved
  -- state stays).
  local function goToControl(view, cardId, ref)
    for _, card in ipairs(view.grid.cards) do
      if not cardId or card.id == cardId then
        if ns.SettingsJump.Go(view, card, ref, function()
          view:Layout()
        end) then
          return true
        end
      end
    end
    return false
  end

  function page:Select(target, cardId, controlId)
    local id, card = L.Target(target, cardId)
    local view = id and self:View(id)
    if not view then
      return
    end
    self.current = id
    if ns.charDB then
      ns.charDB.settingsFeature, ns.charDB.settingsTab = id, nil
    end
    for featureId, v in pairs(self.features) do
      ns.SettingsJump.ClearMark(v)
      v.area:SetShown(featureId == id)
    end
    nav:SetCurrent(id)
    refresh(view)
    self:Layout()
    if card then
      scrollToCard(view, card)
    end
    if controlId then
      goToControl(view, card, controlId)
    end
  end

  function page:Layout()
    local width = container:GetWidth()
    if width and width > 2 * PAD then
      nav:Layout(width - 2 * PAD)
    end
    local view = self.features[self.current]
    if view then
      view:Layout()
    end
  end

  -- Values can change elsewhere (Ctrl+wheel, /fg scale, reset, the key bindings dialog).
  -- params[1] is a feature or card id of a route "settings/<id>" (a link of the changelog, kept by the history).
  function page:Show(params)
    for id, view in pairs(self.features) do
      if id ~= self.current then
        refresh(view)
      end
    end
    local jump = pending or {}
    pending = nil
    local feature = savedFeature()
    local routed, routedCard = L.Target(params and params[1])
    if routed then
      feature, jump = routed, { card = routedCard }
    end
    self:Select(feature, jump.card, jump.control)
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
  crumbLabel = function(param)
    local feature = L.Target(param)
    return feature and ns.L["settings.feature." .. feature] or param
  end,
  build = build,
})
