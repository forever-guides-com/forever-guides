-- The offer for the optional GildenManager on the guild page: a compact row at the top right with a
-- button (switch it on for this character), a download link when the folder is missing, or one muted
-- line when something else keeps it from running. Loading belongs to ns.SubAddons; this file only
-- reads its State and writes the character switch. Nothing is shown while the manager runs.
local _, ns = ...
local W, L = ns.W, ns.L

local B = {}
ns.GuildManagerButton = B

local ID = "guildmanager"
local BUTTON_W = 200
local BUTTON_H = 24
local LABEL_PAD = 24

ns.AddLocale("enUS", {
  ["guild.manager.enable"] = "Enable GuildManager",
  ["guild.manager.copy"] = "Copy download link",
  ["guild.manager.tip.title"] = "GuildManager",
  ["guild.manager.tip"] = "Link mains and alts, keep personal notes and see an inactivity list. Officers and guild masters, meaning players with the needed guild rights and ranks, also get guild actions with a preview. Without the rights the guild stays read-only.",
  ["guild.manager.waitGuild"] = "GuildManager loads once you are in a guild.",
  ["guild.manager.wait"] = "GuildManager loads after combat or at the next start.",
  ["guild.manager.disabled"] = "GuildManager is off in the add-on list of the game.",
  ["guild.manager.failed"] = "GuildManager did not load. See Settings > Addons and the page Errors.",
  ["guild.manager.outdated"] = "GuildManager is outdated. See Settings > Addons.",
})
ns.AddLocale("deDE", {
  ["guild.manager.enable"] = "GildenManager einschalten",
  ["guild.manager.copy"] = "Download-Link kopieren",
  ["guild.manager.tip.title"] = "GildenManager",
  ["guild.manager.tip"] = "Main und Alt verknüpfen, eigene Notizen führen und eine Inaktivitätsliste ansehen. Offiziere und Gildenleiter, also Spieler mit den nötigen Gildenrechten und Gildenrängen, bekommen zusätzlich Gildenaktionen mit Vorschau. Ohne die Rechte bleibt die Gilde schreibgeschützt.",
  ["guild.manager.waitGuild"] = "Der GildenManager lädt, sobald du in einer Gilde bist.",
  ["guild.manager.wait"] = "Der GildenManager lädt nach dem Kampf oder beim nächsten Start.",
  ["guild.manager.disabled"] = "Der GildenManager ist in der Addon-Liste des Spiels aus.",
  ["guild.manager.failed"] = "Der GildenManager konnte nicht laden. Siehe Einstellungen > Addons und die Seite Fehler.",
  ["guild.manager.outdated"] = "Der GildenManager ist veraltet. Siehe Einstellungen > Addons.",
})

-- Muted lines per state of ns.SubAddons: line (short text), body (the status text of the Addons tab,
-- shown in the tooltip), color.
local NOTES = {
  disabled = { line = "guild.manager.disabled", body = "addons.state.disabled", color = "textMuted" },
  failed = { line = "guild.manager.failed", body = "addons.state.failed", color = "warning" },
  outdated = { line = "guild.manager.outdated", body = "addons.state.outdated", color = "warning" },
}

-- What the page shows: nil (nothing), { mode = "enable" | "download" } or
-- { mode = "note", line, body, color }. A manager that registered its parts counts as running even
-- when SubAddons does not know it (an add-on that never called Join reads as pending-off with the
-- switch off), so the offer never covers a working manager.
function B.Mode()
  if ns.GuildExt.Loaded() then
    return nil
  end
  local state = ns.SubAddons.State(ID)
  if state == "off" then
    return { mode = "enable" }
  elseif state == "missing" then
    return { mode = "download" }
  elseif state == "waiting" then
    local body = ns.AddonSettings.StatusKey(ID)
    return {
      mode = "note",
      line = body == "addons.state.waitingGuild" and "guild.manager.waitGuild" or "guild.manager.wait",
      body = body,
      color = "textMuted",
    }
  end
  local note = NOTES[state]
  return note and { mode = "note", line = note.line, body = note.body, color = note.color } or nil
end

-- A frame for a stack: row:Update() decides what shows and hides the row when there is nothing to
-- offer, row:fgGridLayout(width) answers the height.
function B.Build(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.fgId = "guild-manager-row"

  local function showTip(self)
    ns.ShowTooltip(self, L["guild.manager.tip.title"], L["guild.manager.tip"])
  end
  local function button(key, id, onClick)
    local b = W.Button(row, {
      key = key,
      width = BUTTON_W,
      height = BUTTON_H,
      tooltip = "guild.manager.tip.title",
      tooltipText = "guild.manager.tip",
      onClick = onClick,
    })
    b.fgId = id
    b.fgOnFocus, b.fgOnBlur = showTip, ns.HideTooltip
    return b
  end
  row.enable = button("guild.manager.enable", "guild-manager-enable", function()
    ns.SubAddons.SetEnabled(ID, true, "char")
  end)
  row.copy = button("guild.manager.copy", "guild-manager-copy", function()
    ns.Dialogs.Copy("pkg.copy.title", ns.Website, "pkg.copy.hint")
  end)

  -- A line of text, not a button: it only carries the tooltip.
  local note = CreateFrame("Frame", nil, row)
  note:EnableMouse(true)
  note.fgId = "guild-manager-note"
  note.text = W.Text(note, { role = "micro", color = "textMuted", justify = "RIGHT", wrap = true })
  note.text:SetPoint("TOPLEFT")
  local function showNote(self)
    if self.bodyKey then
      ns.ShowTooltip(self, L["guild.manager.tip.title"], L[self.bodyKey])
    end
  end
  note:SetScript("OnEnter", showNote)
  note:SetScript("OnLeave", ns.HideTooltip)
  note.fgOnFocus, note.fgOnBlur = showNote, ns.HideTooltip
  ns.Focus.register(note, showNote)
  row.note = note

  -- True when the row is shown.
  function row:Update()
    local m = B.Mode()
    self.mode = m
    self:SetShown(m ~= nil)
    self.enable:SetShown(m ~= nil and m.mode == "enable")
    self.copy:SetShown(m ~= nil and m.mode == "download")
    note:SetShown(m ~= nil and m.mode == "note")
    if m and m.mode == "note" then
      W.SetText(note.text, m.line)
      W.SetColor(note.text, m.color)
      note.bodyKey = m.body
    end
    return m ~= nil
  end

  function row:fgGridLayout(width)
    local m = self.mode
    local h = BUTTON_H
    if m and m.mode == "note" then
      note.text:SetWidth(width)
      h = math.max(math.ceil(note.text:GetStringHeight()), 1)
      note:ClearAllPoints()
      note:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      note:SetSize(width, h)
    else
      local b = m and m.mode == "download" and self.copy or self.enable
      b:ClearAllPoints()
      b:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
      -- Wider than the default when a large font needs the room.
      b:SetWidth(math.min(math.max(BUTTON_W, math.ceil(b.label:GetStringWidth()) + LABEL_PAD), width))
    end
    self:SetHeight(h)
    return h
  end

  row:Update()
  return row
end
