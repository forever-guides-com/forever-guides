-- Settings card "Logo on nameplates" on the tab Share (PlateBadge.lua): the switch, size, side, the own logo,
-- a preview of a plate and the hints (sharing missing, plates must be on, who gets a logo).
-- Everything is off by default; every change goes through Store.set and the logos follow at once.
local _, ns = ...
local W, L, Store = ns.W, ns.L, ns.Store
local PBL, PB = ns.PlateBadgeLogic, ns.PlateBadge

local S = {}
ns.PlateBadgeSettings = S

ns.AddLocale("enUS", {
  ["platebadge.heading"] = "Logo on nameplates",
  ["platebadge.hint"] = "Logo at the nameplate of recognized players.\nOnly on your screen, nothing is sent.",
  ["platebadge.show"] = "Logos on nameplates",
  ["platebadge.show.tip"] = "Only for group and guild members who allowed it.",
  ["platebadge.notice"] = "Logos of others need sharing.",
  ["platebadge.plates"] = "Needs the friendly player nameplates of the game (Shift+V). Without them the game shows no plate over guild and group members.",
  ["platebadge.who"] = "Only members of your guild or group who sent a presence message. Other community members are not recognized.",
  ["platebadge.size"] = "Size",
  ["platebadge.size.px"] = "%d px",
  ["platebadge.side"] = "Side",
  ["platebadge.side.center"] = "Centered",
  ["platebadge.side.left"] = "Left",
  ["platebadge.side.right"] = "Right",
  ["platebadge.logo"] = "Forever Guides logo",
  ["platebadge.logo.tip"] = "The add-on logo of players who use it.",
  ["platebadge.guild"] = "Guild symbol",
  ["platebadge.guild.tip"] = "The symbol of the guild of the player, next to the logo.",
  ["platebadge.community"] = "Community symbols",
  ["platebadge.community.tip"] = "The symbols of the communities of the player, after the guild symbol.",
  ["platebadge.symbols"] = "Forever Guides shows guild and community symbols only for players you share a guild or community with. They come from the logos of your group and guild and from the local recognition (Share).",
  ["platebadge.self"] = "Show my own logo",
  ["platebadge.self.tip"] = "On your own nameplate, only on your screen.",
  ["platebadge.preview"] = "Preview",
  ["platebadge.sample.name"] = "Example",
  ["platebadge.other"] = "Other nameplate add-ons can cover the logo.",
  ["platebadge.locked"] = "Locked nameplates in encounters: no logo there.",
  ["platebadge.off"] = "Nameplate logo switched off after %d errors.",
})
ns.AddLocale("deDE", {
  ["platebadge.heading"] = "Logo an Namensplaketten",
  ["platebadge.hint"] = "Logo an der Plakette erkannter Spieler.\nNur auf deinem Bildschirm, es wird nichts gesendet.",
  ["platebadge.show"] = "Logos an Plaketten",
  ["platebadge.show.tip"] = "Nur für Gruppe und Gilde, wenn erlaubt.",
  ["platebadge.notice"] = "Logos anderer brauchen Teilen.",
  ["platebadge.plates"] = "Braucht die freundlichen Spieler-Plaketten des Spiels (Umschalt+V). Ohne sie zeigt das Spiel keine Plakette über Gilden- und Gruppenmitgliedern.",
  ["platebadge.who"] = "Nur Mitglieder deiner Gilde oder Gruppe mit Präsenz-Nachricht. Andere Community-Mitglieder werden nicht erkannt.",
  ["platebadge.size"] = "Größe",
  ["platebadge.size.px"] = "%d px",
  ["platebadge.side"] = "Seite",
  ["platebadge.side.center"] = "Mittig",
  ["platebadge.side.left"] = "Links",
  ["platebadge.side.right"] = "Rechts",
  ["platebadge.logo"] = "Forever-Guides-Logo",
  ["platebadge.logo.tip"] = "Das Addon-Logo von Spielern, die es nutzen.",
  ["platebadge.guild"] = "Gildensymbol",
  ["platebadge.guild.tip"] = "Das Symbol der Gilde des Spielers, neben dem Logo.",
  ["platebadge.community"] = "Community-Symbole",
  ["platebadge.community.tip"] = "Die Symbole der Communitys des Spielers, hinter dem Gildensymbol.",
  ["platebadge.symbols"] = "Gilden- und Community-Symbole zeigt Forever Guides nur bei Spielern, mit denen du Gilde oder Community teilst. Sie kommen aus den Logos deiner Gruppe und Gilde und aus der lokalen Erkennung (Teilen).",
  ["platebadge.self"] = "Mein Logo zeigen",
  ["platebadge.self.tip"] = "An deiner Plakette, nur auf deinem Bildschirm.",
  ["platebadge.preview"] = "Vorschau",
  ["platebadge.sample.name"] = "Beispiel",
  ["platebadge.other"] = "Andere Plaketten-Addons können das Logo verdecken.",
  ["platebadge.locked"] = "Gesperrte Plaketten in Begegnungen: dort kein Logo.",
  ["platebadge.off"] = "Plaketten-Logo nach %d Fehlern ausgeschaltet.",
})

-- Preview of a plate: bar, name and the logo as the settings place it.
local PREVIEW_WIDTH, PREVIEW_HEIGHT = 240, 84
local PLATE_WIDTH, PLATE_HEIGHT = 120, 34

-- Everything that repaints when a setting or the consent changes.
local live = setmetatable({}, { __mode = "k" })

local function refreshAll()
  for item in pairs(live) do
    if item.Refresh then
      item:Refresh()
    end
  end
end

local function get(key)
  return ns.db.settings[key]
end

local function settingToggle(view, key, labelKey, tipKey)
  local t = W.Toggle(view.content, {
    key = labelKey,
    get = function()
      return get(key) == true
    end,
    set = function(v)
      Store.set("settings." .. key, v == true)
      refreshAll()
    end,
    tooltip = labelKey,
    tooltipText = tipKey,
  })
  t.fgId = "platebadge-" .. key
  view.stack:Add(t, { height = 24, gap = 6 })
  live[t] = true
  return t
end

local function sizeSlider(view)
  local s = W.Slider(view.content, {
    key = "platebadge.size",
    min = PBL.MIN_SIZE,
    max = PBL.MAX_SIZE,
    step = 1,
    get = function()
      return PBL.CleanSize(get("plateBadgeSize"))
    end,
    set = function(v)
      Store.set("settings.plateBadgeSize", PBL.CleanSize(v))
      refreshAll()
    end,
    format = function(v)
      return string.format(L["platebadge.size.px"], v)
    end,
  })
  s.fgId = "platebadge-size"
  view.stack:Add(s, { height = 42, width = 320, gap = 6 })
  live[s] = true
end

local function sideDropdown(view)
  local dd = W.Dropdown(view.content, {
    key = "platebadge.side",
    width = 200,
    options = {
      { value = "center", key = "platebadge.side.center" },
      { value = "left", key = "platebadge.side.left" },
      { value = "right", key = "platebadge.side.right" },
    },
    get = function()
      return PBL.CleanSide(get("plateBadgeSide"))
    end,
    set = function(v)
      Store.set("settings.plateBadgeSide", PBL.CleanSide(v))
      refreshAll()
    end,
  })
  dd.fgId = "platebadge-side"
  view.stack:Add(dd, { height = 46, width = 200, gap = 6 })
  live[dd] = true
end

-- Paints the logo of the preview where the settings put it on a real plate.
function S.PlacePreview(logo, anchor)
  local size = PBL.CleanSize(get("plateBadgeSize"))
  local pos = PBL.Position(get("plateBadgeSide"))
  logo:SetSize(size, size)
  logo:SetTexture(ns.BadgeAssets.Path(size))
  logo:ClearAllPoints()
  logo:SetPoint(pos.point, anchor, pos.relPoint, pos.x, pos.y)
end

local function previewPlate(view)
  local box = CreateFrame("Frame", nil, view.content)
  box.fgId = "platebadge-preview"
  local plate = CreateFrame("Frame", nil, box)
  plate:SetSize(PLATE_WIDTH, PLATE_HEIGHT)
  plate:SetPoint("BOTTOM", box, "BOTTOM", 0, 4)
  local bar = plate:CreateTexture(nil, "ARTWORK")
  bar:SetSize(PLATE_WIDTH - 20, 8)
  bar:SetPoint("BOTTOM", plate, "BOTTOM", 0, 4)
  bar:SetColorTexture(0.25, 0.7, 0.3, 1)
  local name = W.Text(plate, { key = "platebadge.sample.name", role = "small", color = "text", justify = "CENTER" })
  name:SetPoint("TOP", plate, "TOP", 0, -2)
  name:SetWidth(PLATE_WIDTH)
  local logo = box:CreateTexture(nil, "OVERLAY")
  box.logo = logo
  view.stack:Add(box, { height = PREVIEW_HEIGHT, width = PREVIEW_WIDTH, gap = 6 })
  box.Refresh = function()
    S.PlacePreview(logo, name)
  end
  live[box] = true
  return box
end

-- State of the friendly player plates of the game and the button that switches them on (only a click changes
-- the game's setting). Same texts and function as the contacts page, so the wording stays one.
local function platesSwitch(view)
  local state = W.Text(view.content, { role = "ui", color = "textSecondary", wrap = true })
  state.fgId = "platebadge-plates-state"
  local function paint()
    state:SetText(string.format(L["guild.plates.state"], L["guild.plates." .. ns.NearbyContacts.PlatesState()]))
  end
  state.Refresh = paint
  view.stack:Add(state, { gap = 4 })
  live[state] = true
  local row = ns.FlowLayout.ButtonRow(view.content, {
    {
      id = "plates",
      label = "act.enable",
      icon = "check",
      tooltip = "guild.plates.enable",
      fgId = "platebadge-plates",
      onClick = function()
        local ok, reason = ns.NearbyContacts.EnablePlates()
        ns.Notify(L[ok and "guild.plates.done" or "guild.plates." .. reason], ok and "success" or "warning")
        paint()
      end,
    },
  })
  view.stack:Add(row, { gap = 6 })
end

-- Names only: one click switches the friendly plates on and the health bar off, the second puts the old values back.
local function namesOnly(view)
  local PNames = ns.PlateNames
  local state = W.Text(view.content, { role = "ui", color = "textSecondary", wrap = true })
  state.fgId = "platebadge-names-state"
  local function paint()
    state:SetText(
      string.format(
        L["platenames.state"],
        L["guild.plates." .. ns.NearbyContacts.PlatesState()],
        L["platenames.bar." .. PNames.BarState()]
      )
    )
  end
  state.Refresh = paint
  view.stack:Add(state, { gap = 4 })
  live[state] = true
  local function run(action, done)
    local ok, reason, wrong = action()
    local text, level = PNames.Message(ok, reason, wrong, done)
    ns.Notify(text, level)
    refreshAll()
  end
  local row = ns.FlowLayout.ButtonRow(view.content, {
    {
      id = "names",
      label = "platenames.enable",
      icon = "check",
      tooltip = "platenames.enable.tip",
      fgId = "platebadge-names",
      onClick = function()
        run(PNames.Enable, "platenames.done")
      end,
    },
    {
      id = "restore",
      label = "platenames.restore",
      tooltip = "platenames.restore.tip",
      fgId = "platebadge-names-restore",
      onClick = function()
        run(PNames.Restore, "platenames.restored")
      end,
    },
  })
  view.stack:Add(row, { gap = 4 })
  ns.AddParagraph(view, "platenames.hint", { role = "micro", color = "textMuted", gap = 6 })
end

function S.Add(view)
  ns.AddHeading(view, "platebadge.heading")
  ns.AddParagraph(view, "platebadge.hint", { role = "micro", color = "textMuted" })
  settingToggle(view, "plateBadge", "platebadge.show", "platebadge.show.tip")
  -- The consent of presenceMark is "receive" for group or guild; the button asks for the group.
  local notice = ns.OptInNotice.Banner(view.content, {
    fn = PB.FN,
    dir = "receive",
    aud = "group",
    textKey = "platebadge.notice",
    onChanged = refreshAll,
  })
  notice.fgId = "platebadge-notice"
  view.stack:Add(notice, { gap = 6 })
  notice.Refresh = function()
    notice:Update(not PB.Allowed())
  end
  live[notice] = true
  -- The consent notice stays visible, everything else is rarely changed: behind "More settings".
  local more = W.Accordion(view, { id = view.id or "logos.plates" })
  ns.AddParagraph(more, "platebadge.plates", { role = "micro", color = "textMuted", gap = 2 })
  platesSwitch(more)
  namesOnly(more)
  ns.AddParagraph(more, "platebadge.who", { role = "micro", color = "textMuted", gap = 6 })
  settingToggle(more, "plateShowLogo", "platebadge.logo", "platebadge.logo.tip")
  settingToggle(more, "plateCrestGuild", "platebadge.guild", "platebadge.guild.tip")
  settingToggle(more, "plateCrestCommunity", "platebadge.community", "platebadge.community.tip")
  ns.AddParagraph(more, "platebadge.symbols", { role = "micro", color = "textMuted", gap = 6 })
  sizeSlider(more)
  sideDropdown(more)
  settingToggle(more, "plateBadgeSelf", "platebadge.self", "platebadge.self.tip")
  ns.AddParagraph(more, "platebadge.preview", { role = "micro", color = "textMuted", gap = 2 })
  previewPlate(more)
  ns.AddParagraph(more, "platebadge.other", { role = "micro", color = "textMuted", gap = 2 })
  ns.AddParagraph(more, "platebadge.locked", { role = "micro", color = "textMuted", gap = 2 })
  refreshAll()
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if
    type(path) == "string"
    and (
      path:find("^settings%.plateBadge")
      or path:find("^settings%.plateShowLogo")
      or path:find("^settings%.plateCrest")
    )
  then
    refreshAll()
  end
end)
ns.On("FG_CONSENT_CHANGED", refreshAll)
ns.On("FG_CONSENT_WITHDRAWN", refreshAll)

-- Later than the built-in sections of the tab (Modules/Settings.lua appends in this order).
ns.SettingsPage.Add(S.Add, "sharing", "logos.plates")
