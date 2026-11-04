-- Card "GildenManager" in the settings tab "Guild and contacts": the switch of the optional add-on for
-- this character, its state and a link to the tab "Settings" of the add-on on the guild page. The
-- options themselves live in that tab, so this card works without the add-on being loaded. Loading
-- belongs to ns.SubAddons, this file only reads its State and flips the character switch.
local _, ns = ...
local W = ns.W

local S = {}
ns.GuildManagerSettings = S

local ID = "guildmanager"
-- Id of the tab the add-on registers through ns.GuildExt.
local TAB = "settings"
local BUTTON_W = 200

ns.AddLocale("enUS", {
  ["gmset.title"] = "GuildManager",
  ["gmset.help"] = "Guild tools for officers.\nSettings sit in the tab Settings of the guild page.",
  ["gmset.enable"] = "Use GuildManager",
  ["gmset.enable.hint"] = "Applies to this character",
  ["gmset.open"] = "Open settings",
  ["gmset.open.wait"] = "Opens once the GuildManager runs",
})
ns.AddLocale("deDE", {
  ["gmset.title"] = "GildenManager",
  ["gmset.help"] = "Gildenwerkzeuge für Offiziere.\nEinstellungen im Reiter Optionen der Gildenseite.",
  ["gmset.enable"] = "GildenManager nutzen",
  ["gmset.enable.hint"] = "Gilt für diesen Charakter",
  ["gmset.open"] = "Einstellungen öffnen",
  ["gmset.open.wait"] = "Öffnet, sobald der GildenManager läuft",
})

-- True when the add-on registered its settings tab.
function S.TabReady()
  for _, entry in ipairs(ns.GuildExt.Entries("tab")) do
    if entry.id == TAB then
      return true
    end
  end
  return false
end

local built = {}

-- The switch and its state are read when they can change (build, FG_SUBADDON_CHANGED), not on every
-- repaint: the stored key belongs to the tab "Addons", which lists every switch of the sub-add-ons.
local state = { on = false, text = "", color = "textMuted" }

local function read()
  state.on = ns.SubAddons.Enabled(ID)
  state.text, state.color = ns.AddonSettings.StatusText(ID)
end

-- Fills the card it gets.
function S.Add(card)
  read()
  local s = card.stack
  local row = CreateFrame("Frame", nil, card.content)
  local info = W.InfoButton(row, "gmset.title", "gmset.help")
  info.fgId = "gm-card-help"
  info:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
  local title = W.Text(row, { key = "gmset.title", role = "h3", family = "heading", color = "accent2" })
  title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
  function row:fgGridLayout(width)
    title:SetWidth(math.max(width - W.INFO_SIZE - 6, 1))
    return math.max(W.INFO_SIZE, math.ceil(title:GetStringHeight()) + 2)
  end
  s:Add(row, { gap = 6 })

  local toggle = W.Toggle(card.content, {
    key = "gmset.enable",
    get = function()
      return state.on
    end,
    set = function(v)
      ns.SubAddons.SetEnabled(ID, v == true, "char")
    end,
    tooltip = "gmset.title",
    tooltipText = "gmset.enable.hint",
  })
  toggle.fgId = "gm-card-enable"
  s:Add(toggle, { height = 24, gap = 4 })

  local status = W.Text(card.content, { role = "small", wrap = true })
  status.fgId = "gm-card-state"
  function status.Refresh()
    status:SetText(state.text)
    W.SetColor(status, state.color)
  end
  s:Add(status, { gap = 8 })

  local open = W.Action(card.content, {
    key = "gmset.open",
    width = BUTTON_W,
    height = 26,
    opens = true,
    onClick = function()
      ns.GuildExt.OpenTab(TAB)
    end,
  })
  open.fgId = "gm-card-open"
  s:Add(open, { height = 26, width = BUTTON_W, gap = 4 })

  local wait = W.Text(card.content, { key = "gmset.open.wait", role = "small", color = "textMuted", wrap = true })
  wait.fgId = "gm-card-wait"
  s:Add(wait, { gap = 6 })

  function open.Refresh()
    local ready = S.TabReady()
    open:SetEnabled(ready)
    wait:SetShown(not ready)
  end
  built[#built + 1] = { card = card, open = open }
  open.Refresh()
  status.Refresh()
end

-- The switch changed or the add-on registered its tab: every card reads its state again.
local function refresh()
  read()
  for _, entry in ipairs(built) do
    entry.card:Refresh()
    if entry.open:IsVisible() then
      entry.card:Layout()
    end
  end
end
ns.On("FG_SUBADDON_CHANGED", refresh)
ns.On("FG_GUILDEXT_CHANGED", refresh)

ns.SettingsPage.Add(S.Add, "social")
