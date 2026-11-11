-- Entry "Forever Guides" in the game's add-on list (Settings > AddOns): the installed version, the short
-- text of the newest changelog version and two buttons, one opens the add-on window, one opens it on the
-- Changelog page. The modern settings panel takes a canvas category; a client with the older interface
-- options takes the same panel through InterfaceOptions_AddCategory. Every game call is checked and
-- wrapped, a client without either panel simply has no entry (the add-on window and the minimap button
-- stay the way in).
local _, ns = ...
local W, L, Logic = ns.W, ns.L, ns.AddonCategoryLogic

local Category = {}
ns.AddonCategory = Category

ns.AddLocale("enUS", {
  ["addoncat.openAddon"] = "Open Forever Guides",
  ["addoncat.openChangelog"] = "Open changelog",
  ["addoncat.latest"] = "Newest changes",
  ["addoncat.empty"] = "This build has no changelog data.",
  ["addoncat.hint"] = "The changelog lists every change of the latest versions.",
})
ns.AddLocale("deDE", {
  ["addoncat.openAddon"] = "Forever Guides öffnen",
  ["addoncat.openChangelog"] = "Changelog öffnen",
  ["addoncat.latest"] = "Neueste Änderungen",
  ["addoncat.empty"] = "Dieser Stand enthält keine Changelog-Daten.",
  ["addoncat.hint"] = "Der Changelog zeigt jede Änderung der letzten Versionen.",
})

local NAME = "Forever Guides"
local WIDTH = 560
local PAD = 16
local GAP = 10

local panel, texts

-- Closes the game's settings window before ours opens on top of it. A client that refuses the call
-- leaves it open, the add-on window opens either way.
local function closeSettings()
  local settingsPanel = rawget(_G, "SettingsPanel")
  if type(settingsPanel) == "table" and type(settingsPanel.Close) == "function" then
    pcall(settingsPanel.Close, settingsPanel, true)
  end
  local legacy = rawget(_G, "InterfaceOptionsFrame")
  if type(legacy) == "table" and type(legacy.Hide) == "function" then
    pcall(legacy.Hide, legacy)
  end
end

function Category.Open(path)
  closeSettings()
  ns.Main.Show(path)
end

local function versionLine(summary)
  local line = string.format(L["changelog.version"], summary.version)
  if summary.beta then
    line = line .. " " .. L["changelog.beta"]
  end
  if summary.date and summary.date ~= "" then
    line = line .. ", " .. summary.date
  end
  return line
end

-- Fills the texts from the current data and language; runs every time the panel is shown.
function Category.Refresh()
  if not panel then
    return
  end
  local summary = Logic.Summary(ns.Changelog and ns.Changelog.Versions() or nil)
  texts.installed:SetText(string.format(L["changelog.installed"], ns.version or ""))
  if not summary then
    texts.heading:SetText("")
    texts.body:SetText(L["addoncat.empty"])
    return
  end
  texts.heading:SetText(L["addoncat.latest"] .. " (" .. versionLine(summary) .. ")")
  local body = {}
  for _, line in ipairs(Logic.Lines(summary)) do
    body[#body + 1] = "- " .. line
  end
  body[#body + 1] = ""
  body[#body + 1] = L["addoncat.hint"]
  texts.body:SetText(table.concat(body, "\n"))
end

local function build()
  local frame = CreateFrame("Frame")
  frame.name = NAME
  texts = {}
  texts.title = W.Text(frame, { text = NAME, role = "h2", family = "heading", color = "accent2" })
  texts.title:SetPoint("TOPLEFT", PAD, -PAD)
  texts.installed = W.Text(frame, { role = "body", color = "textSecondary" })
  texts.installed:SetPoint("TOPLEFT", texts.title, "BOTTOMLEFT", 0, -4)
  texts.heading = W.Text(frame, { role = "h3", family = "heading", color = "text", wrap = true })
  texts.heading:SetWidth(WIDTH)
  texts.heading:SetPoint("TOPLEFT", texts.installed, "BOTTOMLEFT", 0, -GAP * 2)
  texts.body = W.Text(frame, { role = "body", color = "text", wrap = true })
  texts.body:SetWidth(WIDTH)
  texts.body:SetPoint("TOPLEFT", texts.heading, "BOTTOMLEFT", 0, -GAP)
  local changelog = W.Action(frame, {
    key = "addoncat.openChangelog",
    icon = "open",
    variant = "primary",
    width = 220,
    opens = true,
    onClick = function()
      Category.Open("changelog")
    end,
  })
  changelog:SetPoint("TOPLEFT", texts.body, "BOTTOMLEFT", 0, -GAP * 2)
  local open = W.Action(frame, {
    key = "addoncat.openAddon",
    icon = "open",
    variant = "secondary",
    width = 220,
    opens = true,
    onClick = function()
      Category.Open()
    end,
  })
  open:SetPoint("LEFT", changelog, "RIGHT", GAP, 0)
  frame.fgChangelogButton, frame.fgOpenButton = changelog, open
  frame:SetScript("OnShow", Category.Refresh)
  -- The settings window shows it when its entry is chosen; until then its buttons stay out of the Tab order.
  frame:Hide()
  return frame
end

-- Registers the entry once. Returns the way it took ("settings", "interface") or nil.
function Category.Register()
  if panel then
    return Category.registered
  end
  local ok, way = pcall(function()
    local frame = build()
    local settings = rawget(_G, "Settings")
    if
      ns.can.settingsCanvas
      and ns.can.settingsAddCategory
      and type(settings) == "table"
      and type(settings.RegisterCanvasLayoutCategory) == "function"
      and type(settings.RegisterAddOnCategory) == "function"
    then
      local category = settings.RegisterCanvasLayoutCategory(frame, NAME)
      settings.RegisterAddOnCategory(category)
      panel, Category.category = frame, category
      return "settings"
    end
    local legacy = rawget(_G, "InterfaceOptions_AddCategory")
    if type(legacy) == "function" then
      legacy(frame)
      panel = frame
      return "interface"
    end
    return nil
  end)
  Category.registered = ok and way or nil
  if Category.registered then
    Category.Refresh()
  end
  return Category.registered
end

function Category.Panel()
  return panel
end
