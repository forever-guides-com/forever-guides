-- Look of the main window: opacity (Main.SetAlpha), window style (UI/Skins.lua), color theme
-- and accent color. All values are account-wide settings, a change restyles every open element at once
-- (ns.RefreshUI). The footer controls (UI/FooterControls.lua) share the opacity value.
local _, ns = ...
local W, Theme, Store, U, Skins = ns.W, ns.Theme, ns.Store, ns.U, ns.Skins

local A = {}
ns.Appearance = A

-- Below this opacity (percent) the settings page points to the way back.
local LOW_ALPHA = 15

ns.AddLocale("enUS", {
  ["settings.look"] = "Look",
  ["settings.alpha"] = "Window opacity",
  ["settings.alphaHint"] = "Backgrounds only, text stays",
  ["settings.alphaLow"] = "Nearly invisible. Footer: opacity, /fg reset",
  ["settings.theme"] = "Color theme",
  ["settings.theme.default"] = "Default",
  ["settings.theme.dark"] = "Dark",
  ["settings.theme.blue"] = "Blue",
  ["settings.theme.green"] = "Green",
  ["settings.theme.warm"] = "Warm (parchment)",
  ["settings.theme.red"] = "Red",
  ["settings.theme.class"] = "My class",
  ["settings.theme.warrior"] = "Warrior",
  ["settings.theme.paladin"] = "Paladin",
  ["settings.theme.hunter"] = "Hunter",
  ["settings.theme.rogue"] = "Rogue",
  ["settings.theme.priest"] = "Priest",
  ["settings.theme.shaman"] = "Shaman",
  ["settings.theme.mage"] = "Mage",
  ["settings.theme.warlock"] = "Warlock",
  ["settings.theme.druid"] = "Druid",
  ["settings.accent"] = "Accent color",
  ["settings.accentDefault"] = "Theme accent",
  ["settings.accentOk"] = "Contrast OK",
  ["settings.accentAdjusted"] = "Lightened for contrast",
  ["settings.lookReset"] = "Reset look",
})
ns.AddLocale("deDE", {
  ["settings.look"] = "Aussehen",
  ["settings.alpha"] = "Fenster-Deckkraft",
  ["settings.alphaHint"] = "Nur Hintergründe, Text bleibt",
  ["settings.alphaLow"] = "Fast unsichtbar. Footer: Deckkraft, /fg reset",
  ["settings.theme"] = "Farbschema",
  ["settings.theme.default"] = "Standard",
  ["settings.theme.dark"] = "Dunkel",
  ["settings.theme.blue"] = "Blau",
  ["settings.theme.green"] = "Grün",
  ["settings.theme.warm"] = "Warm (Pergament)",
  ["settings.theme.red"] = "Rot",
  ["settings.theme.class"] = "Meine Klasse",
  ["settings.theme.warrior"] = "Krieger",
  ["settings.theme.paladin"] = "Paladin",
  ["settings.theme.hunter"] = "Jäger",
  ["settings.theme.rogue"] = "Schurke",
  ["settings.theme.priest"] = "Priester",
  ["settings.theme.shaman"] = "Schamane",
  ["settings.theme.mage"] = "Magier",
  ["settings.theme.warlock"] = "Hexenmeister",
  ["settings.theme.druid"] = "Druide",
  ["settings.accent"] = "Akzentfarbe",
  ["settings.accentDefault"] = "Akzent des Schemas",
  ["settings.accentOk"] = "Kontrast OK",
  ["settings.accentAdjusted"] = "Für Kontrast aufgehellt",
  ["settings.lookReset"] = "Aussehen zurücksetzen",
})

function A.SetTheme(id)
  Store.set("settings.theme", Theme.presets[id] and id or "default")
  ns.RefreshUI()
end

-- Unknown ids fall back to the default style, like the theme.
function A.SetSkin(id)
  Store.set("settings.skin", Skins.cleanId(id))
  ns.RefreshUI()
end

-- hex: "rrggbb" or "#rrggbb", anything else clears the accent (theme accent). `live` is
-- for a picker that reports every step: the restyle then waits for a pause.
function A.SetAccent(hex, live)
  Store.set("settings.accent", Theme.cleanAccent(hex) or "")
  if live then
    ns.Debounce("accent-restyle", 0.1, ns.RefreshUI)
  else
    ns.RefreshUI()
  end
end

function A.Reset()
  ns.Main.SetAlpha(Theme.ALPHA_DEFAULT)
  Store.set("settings.theme", "default")
  Store.set("settings.skin", Skins.DEFAULT)
  A.SetAccent(nil)
end

local function hexOf(name)
  local r, g, b = Theme.rgb(name)
  return string.format("%02x%02x%02x", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

local function addAccentButton(view)
  local s = view.stack
  local button = W.Action(view.content, {
    label = "act.pick",
    icon = "palette",
    tooltip = "settings.accent",
    width = 220,
    onClick = function()
      local before, current = ns.db.settings.accent, hexOf("accent2")
      -- Cancelling the picker reports the old color: that restores the old setting.
      ns.WindowStyle.PickColor(current, function(hex)
        A.SetAccent(hex == current and (before or "") or hex, true)
      end)
    end,
  })
  button.label:ClearAllPoints()
  button.label:SetPoint("LEFT", 8, 0)
  local chip = CreateFrame("Frame", nil, button)
  chip:SetSize(22, 14)
  chip:SetPoint("RIGHT", -8, 0)
  chip.tex = chip:CreateTexture(nil, "ARTWORK")
  chip.tex:SetAllPoints()
  W.Border(chip, "white", 0.4)
  ns.Bind(chip, function()
    chip.tex:SetColorTexture(Theme.color("accent2"))
  end)
  s:Add(button, { height = 26, width = 220 })
  local default = W.Action(view.content, {
    label = "act.reset",
    icon = "reset",
    tooltip = "settings.accentDefault",
    width = 220,
    onClick = function()
      A.SetAccent(nil)
    end,
  })
  default.label:ClearAllPoints()
  default.label:SetPoint("LEFT", 8, 0)
  s:Add(default, { height = 26, width = 220 })
  -- Always one line, so the page does not jump when the state changes.
  local status = W.Text(view.content, { role = "micro", color = "success" })
  local function paint()
    local custom = Theme.cleanAccent(ns.db.settings.accent) ~= nil
    local adjusted = Theme.accentAdjusted()
    W.SetColor(status, adjusted and "warning" or "success")
    W.SetText(status, custom and (adjusted and "settings.accentAdjusted" or "settings.accentOk") or nil, "")
  end
  status.Refresh = paint
  ns.Bind(status, paint)
  s:Add(status, { height = 16 })
  return status
end

-- Accent picker block (picker, "theme accent" reset, contrast note) for any stack view.
-- Returns the status line, whose Refresh repaints the note.
A.AddAccent = addAccentButton

-- Dropdown options of the window styles (settings page and setup wizard).
function A.SkinOptions()
  local options = {}
  for _, id in ipairs(Skins.ORDER) do
    options[#options + 1] = { value = id, key = Skins.list[id].nameKey }
  end
  return options
end

-- Settings page, under the window scale: opacity, color theme, accent color, reset.
function A.AddSettings(view)
  local s = view.stack
  s:Add(W.Text(view.content, { key = "settings.look", role = "ui", color = "accent" }), { gap = 8 })
  local alpha = W.Slider(view.content, {
    key = "settings.alpha",
    min = Theme.ALPHA_MIN,
    max = Theme.ALPHA_MAX,
    step = 5,
    get = function()
      return U.round(Theme.mainAlpha() * 100)
    end,
    set = function(v)
      ns.Main.SetAlpha(v)
    end,
    format = function(v)
      return string.format("%d %%", v)
    end,
  })
  s:Add(alpha, { height = 42, width = 320 })
  local hint = ns.AddParagraph(view, "settings.alphaHint", { role = "micro", color = "textMuted" })
  local function paintHint()
    local low = Theme.mainAlpha() * 100 < LOW_ALPHA
    W.SetText(hint, low and "settings.alphaLow" or "settings.alphaHint")
    W.SetColor(hint, low and "warning" or "textMuted")
  end
  hint.Refresh = paintHint
  s:Add(
    W.Dropdown(view.content, {
      key = "settings.skin",
      width = 240,
      options = A.SkinOptions(),
      get = Skins.currentId,
      set = A.SetSkin,
    }),
    { height = 46, width = 240 }
  )
  ns.AddParagraph(view, "settings.skinHint", { role = "micro", color = "textMuted" })
  local options = {}
  for _, id in ipairs(Theme.PRESET_ORDER) do
    options[#options + 1] = { value = id, key = "settings.theme." .. id }
  end
  s:Add(
    W.Dropdown(view.content, {
      key = "settings.theme",
      width = 240,
      options = options,
      get = function()
        return Theme.presets[ns.db.settings.theme] and ns.db.settings.theme or "default"
      end,
      set = A.SetTheme,
    }),
    { height = 46, width = 240 }
  )
  addAccentButton(view)
  s:Add(
    W.Action(view.content, {
      label = "act.reset",
      icon = "reset",
      tooltip = "settings.lookReset",
      width = 220,
      onClick = A.Reset,
    }),
    { height = 26, width = 220 }
  )
  -- The footer controls change the opacity as well.
  ns.On("FG_SETTING_CHANGED", function(_, path)
    if path == "settings.mainAlpha" then
      alpha:Refresh()
      paintHint()
    end
  end)
end
