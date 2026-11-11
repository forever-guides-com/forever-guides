-- Card "GildenManager options" in the settings tab "Guild": a link to the tab "Settings" of the add-on on the
-- guild page. The options themselves live in that tab, so this card works without the add-on being loaded.
-- The switch of the add-on sits in the card above it (Modules/AddonSettings.lua).
local _, ns = ...
local W = ns.W

local S = {}
ns.GuildManagerSettings = S

-- Id of the tab the add-on registers through ns.GuildExt.
local TAB = "settings"
local BUTTON_W = 200

ns.AddLocale("enUS", {
  ["gmset.title"] = "GuildManager",
  ["gmset.help"] = "Guild tools for officers.\nSettings sit in the tab Settings of the guild page.",
  ["gmset.open"] = "Open settings",
  ["gmset.open.wait"] = "Opens once the GuildManager runs",
})
ns.AddLocale("deDE", {
  ["gmset.title"] = "GildenManager",
  ["gmset.help"] = "Gildenwerkzeuge für Offiziere.\nEinstellungen im Reiter Optionen der Gildenseite.",
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

-- Fills the card it gets.
function S.Add(card)
  local s = card.stack
  local row = CreateFrame("Frame", nil, card.content)
  local info = W.InfoButton(row, "gmset.title", "gmset.help")
  info.fgId = "gm-card-help"
  info:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
  local title = W.Text(row, { key = "settings.card.guild.manager", role = "h3", family = "heading", color = "accent2" })
  title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
  function row:fgGridLayout(width)
    title:SetWidth(math.max(width - W.INFO_SIZE - 6, 1))
    return math.max(W.INFO_SIZE, math.ceil(title:GetStringHeight()) + 2)
  end
  s:Add(row, { gap = 6 })

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
end

-- The switch changed or the add-on registered its tab: every card reads its state again.
local function refresh()
  for _, entry in ipairs(built) do
    entry.card:Refresh()
    if entry.open:IsVisible() then
      entry.card:Layout()
    end
  end
end
ns.On("FG_SUBADDON_CHANGED", refresh)
ns.On("FG_GUILDEXT_CHANGED", refresh)

ns.SettingsPage.Add(S.Add, "guild", "guild.manager")
