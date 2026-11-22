-- Card "Profiles" in the settings group Basics: the profile of this character, new, copy, rename, delete, reset,
-- export, import, send to a player and the switch that allows receiving profiles. The logic is in
-- Modules/ProfileLogic.lua, the run time part in Modules/Profiles.lua. Every action works on the profile picked in
-- "Manage profile" (the active one at first); only the first dropdown switches the profile of this character.
local _, ns = ...
local W, L, P, PL = ns.W, ns.L, ns.Profiles, ns.ProfileLogic

local PS = {}
ns.ProfileSettings = PS

ns.AddLocale("enUS", {
  ["profile.heading"] = "Profiles",
  ["profile.intro"] = "A profile holds your settings. Each character picks one, so characters share settings or keep their own. Window positions, notes, waypoints and other data are not part of a profile.",
  ["profile.use"] = "This character uses",
  ["profile.manage"] = "Manage profile",
  ["profile.new"] = "New ...",
  ["profile.copy"] = "Copy ...",
  ["profile.rename"] = "Rename ...",
  ["profile.delete"] = "Delete ...",
  ["profile.reset"] = "Reset to defaults",
  ["profile.export"] = "Export",
  ["profile.import"] = "Import ...",
  ["profile.send"] = "Send to player ...",
  ["profile.sendTip"] = "Sends this profile to another player.",
  ["profile.accept"] = "Allow receiving profiles",
  ["profile.acceptHint"] = "Off by default. A link from another player opens a preview only while this is on and receiving chat links is on in the privacy settings. Nothing changes before you click Import, and an import never switches your profile.",
  ["profile.dlg.new"] = "New profile",
  ["profile.dlg.copy"] = "Copy profile",
  ["profile.dlg.rename"] = "Rename profile",
  ["profile.dlg.hint"] = "Name of the profile",
  ["profile.confirm.deleteTitle"] = "Delete profile",
  ["profile.confirm.deleteText"] = "Delete the profile %s? Characters that use it switch to Standard.",
  ["profile.confirm.resetTitle"] = "Reset profile",
  ["profile.confirm.resetText"] = "Reset the profile %s to the default values? This cannot be undone.",
  ["profile.reload.title"] = "Reload needed",
  ["profile.reload.text"] = "Some of these settings apply after a reload. Reload the interface now?",
  ["profile.reload.yes"] = "Reload now",
  ["profile.reload.later"] = "Later",
  ["profile.export.title"] = "Export profile",
  ["profile.export.hint"] = "Copy the text with Ctrl+C. Another player pastes it under Import.",
  ["profile.import.title"] = "Import profile",
  ["profile.import.hint"] = "Paste the profile text here.",
  ["profile.import.from"] = "From %s",
  ["profile.import.sum"] = 'Profile "%s" with %d settings.',
  ["profile.import.dropped"] = "%d entries could not be used and are skipped.",
  ["profile.import.note"] = "The import adds a new profile. It does not switch to it and changes none of your profiles.",
  ["profile.import.go"] = "Add profile",
})
ns.AddLocale("deDE", {
  ["profile.heading"] = "Profile",
  ["profile.intro"] = "Ein Profil enthält deine Einstellungen. Jeder Charakter wählt eines, so teilen sich Charaktere die Einstellungen oder behalten eigene. Fensterpositionen, Notizen, Wegpunkte und andere Daten gehören nicht zum Profil.",
  ["profile.use"] = "Dieser Charakter nutzt",
  ["profile.manage"] = "Profil verwalten",
  ["profile.new"] = "Neu ...",
  ["profile.copy"] = "Kopieren ...",
  ["profile.rename"] = "Umbenennen ...",
  ["profile.delete"] = "Löschen ...",
  ["profile.reset"] = "Auf Standardwerte zurücksetzen",
  ["profile.export"] = "Exportieren",
  ["profile.import"] = "Importieren ...",
  ["profile.send"] = "An Spieler senden ...",
  ["profile.sendTip"] = "Sendet dieses Profil an einen anderen Spieler.",
  ["profile.accept"] = "Empfangen erlauben",
  ["profile.acceptHint"] = "Standardmäßig aus. Ein Link von einem anderen Spieler öffnet nur eine Vorschau, solange das hier an ist und in den Datenschutz-Einstellungen das Empfangen von Chat-Links an ist. Vor deinem Klick auf Importieren ändert sich nichts, und ein Import wechselt nie dein Profil.",
  ["profile.dlg.new"] = "Neues Profil",
  ["profile.dlg.copy"] = "Profil kopieren",
  ["profile.dlg.rename"] = "Profil umbenennen",
  ["profile.dlg.hint"] = "Name des Profils",
  ["profile.confirm.deleteTitle"] = "Profil löschen",
  ["profile.confirm.deleteText"] = "Das Profil %s löschen? Charaktere, die es nutzen, wechseln zu Standard.",
  ["profile.confirm.resetTitle"] = "Profil zurücksetzen",
  ["profile.confirm.resetText"] = "Das Profil %s auf die Standardwerte zurücksetzen? Das lässt sich nicht rückgängig machen.",
  ["profile.reload.title"] = "Neu laden nötig",
  ["profile.reload.text"] = "Einige dieser Einstellungen wirken erst nach einem Neuladen. Die Oberfläche jetzt neu laden?",
  ["profile.reload.yes"] = "Jetzt neu laden",
  ["profile.reload.later"] = "Später",
  ["profile.export.title"] = "Profil exportieren",
  ["profile.export.hint"] = "Kopiere den Text mit Strg+C. Ein anderer Spieler fügt ihn unter Importieren ein.",
  ["profile.import.title"] = "Profil importieren",
  ["profile.import.hint"] = "Füge den Profil-Text hier ein.",
  ["profile.import.from"] = "Von %s",
  ["profile.import.sum"] = 'Profil "%s" mit %d Einstellungen.',
  ["profile.import.dropped"] = "%d Einträge waren nicht brauchbar und werden übersprungen.",
  ["profile.import.note"] = "Der Import legt ein neues Profil an. Er wechselt nicht dorthin und ändert keines deiner Profile.",
  ["profile.import.go"] = "Profil hinzufügen",
})

local BUTTON_WIDTH = 220
local SIDE = 16

-- The profile the buttons work on; follows the active one when the list changes.
local managed
local useBox, manageBox, acceptBox
local useOptions, manageOptions = {}, {}

local function fill(list)
  for i = #list, 1, -1 do
    list[i] = nil
  end
  for _, name in ipairs(P.Names()) do
    list[#list + 1] = { value = name, text = name }
  end
end

local function syncList()
  fill(useOptions)
  fill(manageOptions)
  local book = P.Book()
  if not (managed and book and PL.Find(book, managed)) then
    managed = P.Active()
  end
  for _, box in ipairs({ useBox, manageBox }) do
    if box then
      box:Refresh()
    end
  end
  if acceptBox then
    acceptBox.Refresh()
  end
end

local function fail(why)
  ns.Notify(L["profile.err." .. tostring(why)] or L["profile.err.missing"], "warning")
end

-- Reload only on the click of the player: the confirm button is a click of its own.
local function askReload()
  local S = ns.SaveState
  ns.Dialogs.Confirm(
    "profile.reload.title",
    "profile.reload.text",
    S.Click(function()
      ns.SaveUI.ConfirmedReload()
    end),
    nil,
    { callFirst = true, yesKey = "profile.reload.yes", noKey = "profile.reload.later" }
  )
end

-- Dialogs -----------------------------------------------------------------------------------------------------------

local nameDialog
-- submit(name) returns the stored name, or nil and the reason (shown in the dialog).
local function askName(titleKey, suggestion, submit)
  local d = nameDialog
  if not d then
    d = ns.Dialogs.Create("ForeverGuidesProfileName", 420, 190)
    nameDialog = d
    local hint = W.Text(d, { key = "profile.dlg.hint", role = "ui", color = "textSecondary" })
    hint:SetPoint("TOPLEFT", SIDE, -48)
    d.field = W.EditBox(d, {
      maxLetters = PL.MAX_NAME,
      onChange = function()
        W.SetText(d.error, nil, "")
      end,
      onEnter = function()
        d.run()
      end,
    })
    d.field:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
    d.field:SetPoint("RIGHT", -SIDE, 0)
    d.error = W.Text(d, { role = "ui", color = "danger", wrap = true, text = "" })
    d.error:SetPoint("TOPLEFT", d.field, "BOTTOMLEFT", 0, -8)
    d.error:SetPoint("RIGHT", -SIDE, 0)
    d.field.edit:SetScript("OnEscapePressed", function()
      d:Hide()
    end)
    function d.run()
      local stored, why = d.submit(d.field.edit:GetText())
      if stored then
        d:Hide()
      else
        W.SetText(d.error, "profile.err." .. tostring(why))
      end
    end
    local save = W.Action(d, {
      label = "act.save",
      icon = "save",
      tooltip = "act.save",
      variant = "primary",
      width = 110,
      onClick = function()
        d.run()
      end,
    })
    save:SetPoint("BOTTOMRIGHT", -SIDE, 14)
    local cancel = W.Action(d, {
      label = "act.cancel",
      icon = "close",
      tooltip = "common.cancel",
      width = 110,
      onClick = function()
        d:Hide()
      end,
    })
    cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
  end
  d.submit = submit
  W.SetText(d.title, titleKey)
  d.field.edit:SetText(suggestion or "")
  W.SetText(d.error, nil, "")
  d:Show()
  C_Timer.After(0.05, function()
    d.field.edit:SetFocus()
    d.field.edit:HighlightText()
  end)
  return d
end
PS.AskName = askName

local importDialog
local function parseImport(d)
  local read, why = P.Read(d.paste.edit:GetText())
  d.read = read
  if not read then
    local text = d.paste.edit:GetText()
    W.SetText(d.status, "profile.err." .. tostring(why))
    d.status:SetShown(why ~= "empty" or (text ~= nil and text ~= ""))
    W.SetColor(d.status, "danger")
    d.add:SetShown(false)
    return
  end
  local line = string.format(L["profile.import.sum"], read.name, read.count)
  if read.dropped > 0 then
    line = line .. " " .. string.format(L["profile.import.dropped"], read.dropped)
  end
  W.SetText(d.status, nil, line)
  W.SetColor(d.status, "text")
  d.status:Show()
  d.add:SetShown(true)
  if d.field.edit:GetText() == "" then
    d.field.edit:SetText(read.name)
  end
end

-- `sender` (optional): the string came in a chat link, `code` is that string.
local function showImport(code, sender)
  local d = importDialog
  if not d then
    d = ns.Dialogs.Create("ForeverGuidesProfileImport", 520, 330)
    importDialog = d
    d.from = W.Text(d, { role = "ui", color = "textSecondary" })
    d.from:SetPoint("TOPLEFT", SIDE, -44)
    d.hint = W.Text(d, { key = "profile.import.hint", role = "ui", color = "textSecondary" })
    d.hint:SetPoint("TOPLEFT", d.from, "BOTTOMLEFT", 0, -4)
    d.paste = W.EditBox(d, {
      maxLetters = ns.Strings.MAX_INPUT,
      onChange = function()
        parseImport(d)
      end,
    })
    d.paste:SetPoint("TOPLEFT", d.hint, "BOTTOMLEFT", 0, -6)
    d.paste:SetPoint("RIGHT", -SIDE, 0)
    d.status = W.Text(d, { role = "ui", color = "text", wrap = true, text = "" })
    d.status:SetPoint("TOPLEFT", d.paste, "BOTTOMLEFT", 0, -10)
    d.status:SetPoint("RIGHT", -SIDE, 0)
    d.field = W.EditBox(d, { maxLetters = PL.MAX_NAME })
    d.field:SetPoint("TOPLEFT", d.status, "BOTTOMLEFT", 0, -10)
    d.field:SetPoint("RIGHT", -SIDE, 0)
    d.note = W.Text(d, { key = "profile.import.note", role = "small", color = "textSecondary", wrap = true })
    d.note:SetPoint("BOTTOMLEFT", SIDE, 56)
    d.note:SetPoint("RIGHT", -SIDE, 0)
    for _, box in ipairs({ d.paste, d.field }) do
      box.edit:SetScript("OnEscapePressed", function()
        d:Hide()
      end)
    end
    d.add = W.Action(d, {
      label = "profile.import.go",
      icon = "import",
      tooltip = "profile.import.go",
      variant = "primary",
      width = 160,
      onClick = function()
        if not d.read then
          return
        end
        local stored, why = P.Add(d.read, d.field.edit:GetText())
        if stored then
          d:Hide()
        else
          fail(why)
        end
      end,
    })
    d.add:SetPoint("BOTTOMRIGHT", -SIDE, 14)
    d.close = W.Action(d, {
      label = "act.close",
      icon = "close",
      tooltip = "common.close",
      width = 100,
      onClick = function()
        d:Hide()
      end,
    })
    d.close:SetPoint("RIGHT", d.add, "LEFT", -8, 0)
  end
  W.SetText(d.title, "profile.import.title")
  W.SetText(d.from, nil, sender and string.format(L["profile.import.from"], tostring(sender)) or "")
  d.field.edit:SetText("")
  d.paste.edit:SetText(code or "")
  parseImport(d)
  d:Show()
  return d
end

function P.ShowReceived(sender, read)
  return showImport(read.code, sender)
end

-- Card ----------------------------------------------------------------------------------------------------------------

local function button(view, key, icon, id, onClick, opens)
  local b = W.Action(
    view.content,
    { key = key, icon = icon, tooltip = key, width = BUTTON_WIDTH, height = 28, onClick = onClick, opens = opens }
  )
  b.fgId = id
  view.stack:Add(b, { height = 28, width = BUTTON_WIDTH, gap = 6 })
  return b
end

local function choose(name)
  managed = name
  syncList()
end

-- The dropdown of the card: switches this character and, when a reload helps, asks for it.
function PS.SwitchTo(name)
  local ok, reload = P.Switch(name)
  if not ok then
    return fail(reload)
  end
  choose(name)
  if reload then
    askReload()
  end
end

function PS.AddSettings(view)
  local s = view.stack
  ns.AddHeading(view, "profile.heading")
  ns.AddParagraph(view, "profile.intro", { role = "micro", color = "textMuted" })
  fill(useOptions)
  fill(manageOptions)
  managed = managed or P.Active()
  useBox = W.Dropdown(view.content, {
    key = "profile.use",
    width = 240,
    options = useOptions,
    get = P.Active,
    set = function(name)
      PS.SwitchTo(name)
    end,
  })
  useBox.fgId = "profile-use"
  s:Add(useBox, { height = 46, width = 240, gap = 8 })
  manageBox = W.Dropdown(view.content, {
    key = "profile.manage",
    width = 240,
    options = manageOptions,
    get = function()
      return managed
    end,
    set = function(name)
      managed = name
    end,
  })
  manageBox.fgId = "profile-manage"
  s:Add(manageBox, { height = 46, width = 240, gap = 8 })

  button(view, "profile.new", "plus", "profile-new", function()
    askName("profile.dlg.new", "", function(name)
      local stored, why = P.New(name)
      if stored then
        choose(stored)
      end
      return stored, why
    end)
  end)
  button(view, "profile.copy", "copy", "profile-copy", function()
    askName("profile.dlg.copy", managed .. " 2", function(name)
      local stored, why = P.Copy(name, managed)
      if stored then
        choose(stored)
      end
      return stored, why
    end)
  end)
  -- The rarely used actions sit behind "More settings".
  local more = W.Accordion(view, { id = view.id or "profiles.main" })
  button(more, "profile.rename", "pencil", "profile-rename", function()
    if managed == PL.DEFAULT then
      return fail("default")
    end
    local old = managed
    askName("profile.dlg.rename", old, function(name)
      local stored, why = P.Rename(old, name)
      if stored then
        choose(stored)
      end
      return stored, why
    end)
  end)
  button(more, "profile.delete", "trash", "profile-delete", function()
    local name = managed
    if name == PL.DEFAULT then
      return fail("default")
    elseif name == P.Active() then
      return fail("active")
    end
    ns.Dialogs.Confirm("profile.confirm.deleteTitle", nil, function()
      local ok, why = P.Delete(name)
      if not ok then
        fail(why)
      end
    end, nil, { text = string.format(L["profile.confirm.deleteText"], name) })
  end)
  button(more, "profile.reset", "reset", "profile-reset", function()
    local name = managed
    ns.Dialogs.Confirm("profile.confirm.resetTitle", nil, function()
      local ok, reload = P.Reset(name)
      if not ok then
        return fail(reload)
      end
      if reload then
        askReload()
      end
    end, nil, { text = string.format(L["profile.confirm.resetText"], name) })
  end)
  button(more, "profile.export", "export", "profile-export", function()
    local code, why = P.Export(managed)
    if not code then
      return fail(why)
    end
    ns.Dialogs.Copy("profile.export.title", code, "profile.export.hint")
  end, true)
  button(more, "profile.import", "import", "profile-import", function()
    showImport()
  end)
  local send = ns.PageShare.Button(more.content, {
    size = 28,
    tooltip = "profile.send",
    tooltipText = "profile.sendTip",
    onClick = function()
      P.Share(managed)
    end,
  })
  send.fgId = "profile-send"
  more.stack:Add(send, { height = 28, width = 28, gap = 6 })

  acceptBox = W.Toggle(more.content, {
    key = "profile.accept",
    get = P.Accepts,
    set = P.SetAccept,
  })
  acceptBox.fgId = "profile-accept"
  more.stack:Add(acceptBox, { height = 24, gap = 8 })
  ns.AddParagraph(more, "profile.acceptHint", { role = "micro", color = "textMuted" })
end

ns.On("FG_PROFILES_CHANGED", function()
  if useBox then
    syncList()
  end
end)

ns.SettingsPage.Add(PS.AddSettings, "general", "profiles.main")
