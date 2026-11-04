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
  ["platebadge.plates"] = "Needs nameplates for players (Shift+V).",
  ["platebadge.who"] = "Only players who sent a presence message (guild, group).",
  ["platebadge.size"] = "Size",
  ["platebadge.size.px"] = "%d px",
  ["platebadge.side"] = "Side",
  ["platebadge.side.left"] = "Left",
  ["platebadge.side.right"] = "Right",
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
  ["platebadge.plates"] = "Braucht Plaketten für Spieler (Umschalt+V).",
  ["platebadge.who"] = "Nur Spieler mit Präsenz-Nachricht (Gilde, Gruppe).",
  ["platebadge.size"] = "Größe",
  ["platebadge.size.px"] = "%d px",
  ["platebadge.side"] = "Seite",
  ["platebadge.side.left"] = "Links",
  ["platebadge.side.right"] = "Rechts",
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
function S.PlacePreview(logo, plate)
  local size = PBL.CleanSize(get("plateBadgeSize"))
  local pos = PBL.Position(get("plateBadgeSide"))
  logo:SetSize(size, size)
  logo:SetTexture(ns.BadgeAssets.Path(size))
  logo:ClearAllPoints()
  logo:SetPoint(pos.point, plate, pos.relPoint, pos.x, pos.y)
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
    S.PlacePreview(logo, plate)
  end
  live[box] = true
  return box
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
  ns.AddParagraph(view, "platebadge.plates", { role = "micro", color = "textMuted", gap = 2 })
  ns.AddParagraph(view, "platebadge.who", { role = "micro", color = "textMuted", gap = 6 })
  sizeSlider(view)
  sideDropdown(view)
  settingToggle(view, "plateBadgeSelf", "platebadge.self", "platebadge.self.tip")
  ns.AddParagraph(view, "platebadge.preview", { role = "micro", color = "textMuted", gap = 2 })
  previewPlate(view)
  ns.AddParagraph(view, "platebadge.other", { role = "micro", color = "textMuted", gap = 2 })
  ns.AddParagraph(view, "platebadge.locked", { role = "micro", color = "textMuted", gap = 2 })
  refreshAll()
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.plateBadge") then
    refreshAll()
  end
end)
ns.On("FG_CONSENT_CHANGED", refreshAll)
ns.On("FG_CONSENT_WITHDRAWN", refreshAll)

-- Later than the built-in sections of the tab (Modules/Settings.lua appends in this order).
ns.SettingsPage.Add(S.Add, "sharing")
