-- Steps of the setup wizard. A step names its controls (Store keys or feature rows); the feature steps are built
-- from the registry in Modules/SetupFeatureData.lua (one block "features" per step, see SetupWizardRows.lua).
-- The texts of all steps are in Modules/SetupWizardLocale.lua, the step "menu" registers itself in
-- Modules/SetupWizardMenu.lua. A control whose key has no default (a module that is not there) is left out by the
-- logic, a step without a usable control is skipped.
--
--   start  look  access  display  world  helpers  chat  party  social  sharing  menu  menu2  done
-- Every step has to fit the one window height with all its options shown (see Modules/SetupWizard.lua):
-- a topic that grows past that gets a step of its own.
local _, ns = ...
local SW, Theme, FL = ns.SetupWizard, ns.Theme, ns.SetupFeatureLogic

-- The version that brings the steps of this layout. look, sharing and done keep their own: a player who saw
-- them before does not see them again (SW.Baseline).
local RELEASE = "0.7.0"
-- Order of the steps. The steps "menu" and "menu2" sit between sharing and done (Modules/SetupWizardMenu.lua).
local ORDER = { start = 5, look = 10, access = 15, display = 20, world = 30, helpers = 40, chat = 50, party = 60 }
ORDER.social, ORDER.sharing, ORDER.done = 65, 75, 80

-- Every action row of a step has no setting. Its control only needs a key that exists in the defaults.
local ACTION_KEY = "setup.done"

local function percent(v)
  return string.format("%d %%", math.floor(v * 100 + 0.5))
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

local function toggle(key, labelKey, extra)
  local c = { type = "toggle", key = key, labelKey = labelKey }
  for k, v in pairs(extra or {}) do
    c[k] = v
  end
  return c
end

-- extra.tab: the settings feature of the step's controls, named in the summary; a control with its own tab
-- (or tab = false for none) overrides it.
local function step(id, controls, extra)
  local def = {
    id = id,
    order = ORDER[id],
    titleKey = "setup.step." .. id,
    textKey = "setup.step." .. id .. ".text",
    since = RELEASE,
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

-- An action row of the step: build(view) adds its widgets to view.stack. Nothing is stored.
local function action(build)
  return { type = "custom", key = ACTION_KEY, action = true, build = build }
end

-- Opens a card of the settings next to the wizard, which stays open.
local function openSettings(feature, card)
  if ns.SettingsPage.Select(feature, card) then
    ns.Main.Show("settings")
    ns.SetupWizardUI.Reveal()
  end
end

-- One line of buttons, each named after an area of the settings and opening its card (with the new-window mark).
-- areas: { { nameKey, feature, card }, .. }
local BUTTON_W, BUTTON_GAP, BUTTON_H = 170, 8, 26

local function areaButtons(id, areas)
  return action(function(view)
    local holder = CreateFrame("Frame", nil, view.content)
    holder.fgId = "wizard-areas-" .. id
    holder.buttons = {}
    local factor = ns.SetupWizardRows.Factor()
    for i, area in ipairs(areas) do
      local button = ns.W.Button(holder, {
        key = area[1],
        width = math.floor(BUTTON_W * factor + 0.5),
        tooltip = area[1],
        tooltipText = "setup.row.optionsTip",
        opens = true,
        onClick = function()
          openSettings(area[2], area[3])
        end,
      })
      button.fgId = "wizard-areas-" .. id .. "-button" .. i
      holder.buttons[i] = button
    end
    function holder:fgGridLayout(width)
      local x, y, h = 0, 0, 0
      for _, button in ipairs(self.buttons) do
        local w = math.ceil(button:GetWidth())
        if x > 0 and x + w > width then
          x, y = 0, y + h + BUTTON_GAP
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", x, -y)
        h = math.max(h, BUTTON_H)
        x = x + w + BUTTON_GAP
      end
      self:SetHeight(y + h)
      return y + h
    end
    view.stack:Add(holder, { gap = 10 })
    return holder
  end)
end

-- The three lines of the first step: what the switch, the button "Options" and the pencil of the menu do.
local HOW_TO =
  { { "setup.start.how1", "check" }, { "setup.start.how2", "gear" }, { "setup.start.how3", "pencil", "text" } }
local HOW_ICON = 16

local function howTo()
  return action(function(view)
    local W = ns.W
    local holder = CreateFrame("Frame", nil, view.content)
    local lines = {}
    for i, entry in ipairs(HOW_TO) do
      local line = {}
      line.icon = holder:CreateTexture(nil, "ARTWORK")
      line.icon:SetSize(HOW_ICON, HOW_ICON)
      line.icon:SetTexture(ns.UI_ICONS[entry[2]])
      line.text = W.Text(holder, { key = entry[1], role = "ui", color = entry[3] or "textSecondary", wrap = true })
      lines[i] = line
    end
    function holder:fgGridLayout(width)
      local y = 0
      local indent = math.floor(HOW_ICON * 1.5)
      for _, line in ipairs(lines) do
        line.icon:ClearAllPoints()
        line.icon:SetPoint("TOPLEFT", 0, -(y + 2))
        line.text:ClearAllPoints()
        line.text:SetPoint("TOPLEFT", indent, -y)
        line.text:SetWidth(math.max(40, width - indent))
        y = y + math.max(HOW_ICON + 4, line.text:GetStringHeight()) + 4
      end
      self:SetHeight(y)
      return y
    end
    view.stack:Add(holder, { gap = 8 })
    return holder
  end)
end

-- The controls of the feature rows of a step: the switch of each row and its options, for the summary and
-- "Reset all". The window draws the rows through the block "features", not through the block "controls".
local function featureControls(stepId)
  local controls = {}
  for _, def in ipairs(FL.Rows(stepId)) do
    local c = FL.Control(def.id)
    if c then
      if c.tab == nil then
        c.tab = false
      end
      controls[#controls + 1] = c
    end
    for _, option in ipairs(FL.Options(def.id)) do
      if option.control then
        controls[#controls + 1] = option.control
      else
        -- A list of key words: shown as its text in the summary, drawn by the row.
        controls[#controls + 1] = {
          type = "custom",
          key = option.key,
          labelKey = option.labelKey,
          owner = def.id,
          tab = def.target.feature,
          format = function(v)
            return v == "" and ns.L["setup.ctl.inviteWordsOff"] or v
          end,
          build = function() end,
        }
      end
    end
  end
  return controls
end

local function featureStep(id)
  step(id, featureControls(id), { layout = { "title", "text", "features" } })
end

-- 1: start ---------------------------------------------------------------------------------------------

step("start", {
  {
    type = "dropdown",
    key = "settings.locale",
    labelKey = "settings.languageLabel",
    tab = "language",
    options = {
      { value = "auto", key = "settings.lang.auto" },
      { value = "deDE", text = "Deutsch" },
      { value = "enUS", text = "English" },
    },
    apply = applyLocale,
  },
  howTo(),
}, { layout = { "logo", "title", "text", "controls", "links" } })

-- 2: look and windows ------------------------------------------------------------------------------------

local lookControls = {
  {
    type = "dropdown",
    key = "settings.skin",
    labelKey = "settings.skin",
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
    lowHintKey = "setup.alphaLow",
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
  areaButtons("look", { { "settings.feature.window", "window", "window.look" } }),
}
step("look", lookControls, { since = "0.1.0", tab = "window", layout = { "title", "text", "controls" } })

-- 3: readability and the two window rows --------------------------------------------------------------

local accessControls = {
  {
    type = "slider",
    key = "settings.fontScale",
    labelKey = "settings.fontScale",
    tab = "fonts",
    min = Theme.FONT_SCALE_MIN,
    max = Theme.FONT_SCALE_MAX,
    step = 0.05,
    format = percent,
    applyOn = "release",
    apply = restyle,
  },
  toggle("settings.contrast", "settings.contrast", { tab = "access", apply = restyle }),
  toggle("settings.colorblind", "settings.colorblind", { tab = "access", apply = restyle }),
  areaButtons("access", { { "settings.feature.access", "access" } }),
}
for _, c in ipairs(featureControls("access")) do
  accessControls[#accessControls + 1] = c
end
step("access", accessControls, { tab = "access", layout = { "title", "text", "controls", "features" } })

-- The feature steps ------------------------------------------------------------------------------

for _, id in ipairs({ "display", "world", "helpers", "chat", "party", "social" }) do
  featureStep(id)
end

-- 8: sharing ---------------------------------------------------------------------------------------------

-- A row per function of the opt-in register that can show up (the first nine; the rest is in the settings
-- tab), send and receive for its first audience. Nothing is on until the player switches it on.
local MAX_SHARING = 9
local sharing = {}
for _, def in ipairs(ns.Consent and ns.Consent.List() or {}) do
  if #sharing < MAX_SHARING and not ns.Consent.IsHidden(def.id) then
    sharing[#sharing + 1] = {
      type = "consent",
      key = "consent." .. def.id,
      fn = def.id,
      aud = def.audiences[1],
      labelKey = def.labelKey,
      hintKey = def.hintKey,
    }
  end
end
step("sharing", sharing, {
  tab = "privacy",
  since = "0.5.0",
  layout = { "title", "text", "privacy", "bulk", "controls", "allSettings" },
})

-- 10: done -----------------------------------------------------------------------------------------------

-- Closes every run: lists what was changed and where to change it later. The menu step lists its own changes.
step("done", {
  action(function(view)
    return ns.SetupWizardRows.PencilLine(view)
  end),
  action(function(view)
    local row = ns.SetupWizardRows.Row(view.content, {
      id = "pencil",
      nameKey = "setup.done.pencil",
      button = {
        key = "page.settings",
        tooltip = "page.settings",
        opens = true,
        onClick = function()
          ns.Main.Show("settings")
          ns.SetupWizardUI.Reveal()
        end,
        width = 140,
      },
    })
    view.stack:Add(row, { gap = 10 })
    return row
  end),
}, {
  closing = true,
  since = "0.1.0",
  layout = { "title", "summary", "controls", "restart", "info", "community", "text" },
})
