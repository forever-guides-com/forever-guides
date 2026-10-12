-- Typography settings in Settings > General > Accessibility: one slider per font role (title, heading,
-- subheading, text, small, micro), presets, reset and a live preview. The sizes themselves come from
-- Theme.fontSize (settings.fontScales times the overall settings.fontScale). Every change repaints the
-- open windows at once (ns.RefreshUI), nothing needs a reload.
local _, ns = ...
local W, Theme, Store, U, FL = ns.W, ns.Theme, ns.Store, ns.U, ns.FlowLayout

local TS = {}
ns.TypographySettings = TS

ns.AddLocale("enUS", {
  ["typo.title"] = "Font sizes by kind of text",
  ["typo.hint"] = "Each slider changes one kind of text on top of the font size above. Nothing gets smaller than 11 px, and a smaller window zoom raises that limit so the text on screen stays readable.",
  ["typo.presets"] = "Presets",
  ["typo.preset.default"] = "Default",
  ["typo.preset.large"] = "Large 125 %",
  ["typo.preset.xlarge"] = "Very large 150 %",
  ["typo.preset.compact"] = "Compact 90 %",
  ["typo.presetsHint"] = "A preset sets all six sliders. The font size above stays as it is.",
  ["typo.role.title"] = "Page title",
  ["typo.role.h2"] = "Heading",
  ["typo.role.h3"] = "Subheading",
  ["typo.role.body"] = "Text",
  ["typo.role.small"] = "Small",
  ["typo.role.micro"] = "Micro",
  ["typo.reset"] = "Reset font sizes",
  ["typo.resetHint"] = "Sets all six sliders and the font size above back to 100 %.",
  ["typo.preview"] = "Preview",
  ["typo.sample.title"] = "Page title",
  ["typo.sample.h2"] = "Heading of a section",
  ["typo.sample.h3"] = "Subheading",
  ["typo.sample.body"] = "This is how text looks in buttons, tabs and list titles.",
  ["typo.sample.small"] = "Hints and the second line of a list.",
  ["typo.sample.micro"] = "Sidebar groups, footer and status lines.",
})

ns.AddLocale("deDE", {
  ["typo.title"] = "Schriftgrößen nach Textart",
  ["typo.hint"] = "Jeder Regler ändert eine Textart zusätzlich zur Schriftgröße darüber. Unter 11 px wird nichts kleiner, und bei kleinerem Fensterzoom steigt diese Grenze, damit der Text auf dem Bildschirm lesbar bleibt.",
  ["typo.presets"] = "Voreinstellungen",
  ["typo.preset.default"] = "Standard",
  ["typo.preset.large"] = "Groß 125 %",
  ["typo.preset.xlarge"] = "Sehr groß 150 %",
  ["typo.preset.compact"] = "Kompakt 90 %",
  ["typo.presetsHint"] = "Eine Voreinstellung setzt alle sechs Regler. Die Schriftgröße darüber bleibt unverändert.",
  ["typo.role.title"] = "Seitentitel",
  ["typo.role.h2"] = "Überschrift",
  ["typo.role.h3"] = "Zwischenüberschrift",
  ["typo.role.body"] = "Text",
  ["typo.role.small"] = "Klein",
  ["typo.role.micro"] = "Mikro",
  ["typo.reset"] = "Schriftgrößen zurücksetzen",
  ["typo.resetHint"] = "Setzt alle sechs Regler und die Schriftgröße darüber auf 100 % zurück.",
  ["typo.preview"] = "Vorschau",
  ["typo.sample.title"] = "Seitentitel",
  ["typo.sample.h2"] = "Überschrift eines Abschnitts",
  ["typo.sample.h3"] = "Zwischenüberschrift",
  ["typo.sample.body"] = "So sieht Text in Knöpfen, Reitern und Listentiteln aus.",
  ["typo.sample.small"] = "Hinweise und die zweite Zeile einer Liste.",
  ["typo.sample.micro"] = "Seitenleistengruppen, Fußzeile und Statuszeilen.",
})

-- Factor of every preset (all six roles get the same one).
TS.PRESETS = {
  { id = "default", key = "typo.preset.default", factor = 1 },
  { id = "large", key = "typo.preset.large", factor = 1.25 },
  { id = "xlarge", key = "typo.preset.xlarge", factor = 1.5 },
  { id = "compact", key = "typo.preset.compact", factor = 0.9 },
}

-- Preview lines, one per role, in the colors the roles have on the pages.
local SAMPLES = {
  { role = "title", family = "heading", color = "accent2" },
  { role = "h2", family = "heading", color = "accent2" },
  { role = "h3", family = "heading", color = "accent2" },
  { role = "body", color = "text" },
  { role = "small", color = "textSecondary" },
  { role = "micro", color = "textMuted" },
}

local function percent(v)
  return string.format("%d %%", math.floor(v * 100 + 0.5))
end

local function repaint()
  ns.RefreshUI()
  ns.Main.Relayout()
end

-- Saves one factor per role (a table role -> factor), clamped to the range of the sliders.
function TS.SetAll(factors)
  local scales = {}
  for _, role in ipairs(Theme.FONT_ROLES) do
    local v = factors[role] or 1
    scales[role] = U.clamp(U.round(v, 0.05), Theme.ROLE_SCALE_MIN, Theme.ROLE_SCALE_MAX)
  end
  Store.set("settings.fontScales", scales)
end

function TS.SetPreset(id)
  for _, preset in ipairs(TS.PRESETS) do
    if preset.id == id then
      local factors = {}
      for _, role in ipairs(Theme.FONT_ROLES) do
        factors[role] = preset.factor
      end
      TS.SetAll(factors)
      repaint()
      return true
    end
  end
  return false
end

-- All six sliders and the overall size back to 100 percent.
function TS.Reset()
  TS.SetAll({})
  Store.set("settings.fontScale", 1)
  repaint()
end

-- Id of the preset whose factor every role has now, nil for a mix.
function TS.ActivePreset()
  for _, preset in ipairs(TS.PRESETS) do
    local all = true
    for _, role in ipairs(Theme.FONT_ROLES) do
      all = all and math.abs(Theme.roleScale(role) - preset.factor) < 0.001
    end
    if all then
      return preset.id
    end
  end
  return nil
end

local function addPresets(view)
  local defs = {}
  for _, preset in ipairs(TS.PRESETS) do
    defs[#defs + 1] = {
      id = preset.id,
      fgId = "typo-preset-" .. preset.id,
      key = preset.key,
      variant = "secondary",
      width = 110,
      onClick = function()
        TS.SetPreset(preset.id)
      end,
    }
  end
  local row = FL.ButtonRow(view.content, defs)
  view.stack:Add(row, { gap = 10 })
  return function()
    local active = TS.ActivePreset()
    for _, preset in ipairs(TS.PRESETS) do
      row:GetButton(preset.id):SetSelected(preset.id == active)
    end
  end
end

local function addSliders(view)
  local sliders = {}
  for _, role in ipairs(Theme.FONT_ROLES) do
    local slider = W.Slider(view.content, {
      key = "typo.role." .. role,
      min = Theme.ROLE_SCALE_MIN,
      max = Theme.ROLE_SCALE_MAX,
      step = 0.05,
      get = function()
        return Theme.roleScale(role)
      end,
      set = function(v)
        Store.set("settings.fontScales." .. role, v)
        ns.Debounce("font-scale", 0.2, repaint)
      end,
      format = percent,
    })
    slider.fgId = "typo-" .. role
    view.stack:Add(slider, { height = 42, width = 320 })
    sliders[#sliders + 1] = slider
  end
  return sliders
end

-- One line per role in its real size, with the size in px behind the sample text.
local function addPreview(view)
  view.stack:Add(W.Text(view.content, { key = "typo.preview", role = "ui", color = "accent" }), { gap = 6 })
  for _, sample in ipairs(SAMPLES) do
    local line = W.Text(view.content, {
      role = sample.role,
      family = sample.family,
      color = sample.color,
      wrap = true,
    })
    line.fgId = "typo-sample-" .. sample.role
    ns.Bind(line, function(fs)
      fs:SetText(string.format("%s (%d px)", ns.L["typo.sample." .. sample.role], Theme.fontSize(sample.role)))
    end)
    view.stack:Add(line, { gap = 6 })
  end
end

-- The section: presets, preview, one slider per role, reset. Sliders and presets follow changes that
-- come from elsewhere (reset, preset, a later import).
function TS.Add(view)
  local s = view.stack
  s:Add(W.Text(view.content, { key = "typo.title", role = "ui", color = "accent" }), { gap = 8 })
  ns.AddParagraph(view, "typo.hint", { role = "micro", color = "textMuted" })
  local paintPresets = addPresets(view)
  ns.AddParagraph(view, "typo.presetsHint", { role = "micro", color = "textMuted" })
  addPreview(view)
  local sliders = addSliders(view)
  s:Add(
    W.Action(view.content, {
      label = "act.reset",
      icon = "reset",
      tooltip = "typo.reset",
      tooltipText = "typo.resetHint",
      width = 220,
      height = 28,
      onClick = TS.Reset,
    }),
    { height = 28, width = 220 }
  )
  paintPresets()
  ns.On("FG_SETTING_CHANGED", function(_, path)
    if type(path) == "string" and path:find("^settings%.fontScales") then
      for i, slider in ipairs(sliders) do
        -- Not the slider the player drags: it already shows the value.
        if math.abs(slider.slider:GetValue() - Theme.roleScale(Theme.FONT_ROLES[i])) > 0.001 then
          slider:Refresh()
        end
      end
      paintPresets()
    end
  end)
end
