-- Windows of the Legacy planner: import with a preview and the name prompt for saved plans. The editor owns the
-- plan; these windows only collect text and hand the result back. Export reuses ns.TalentDialogs.Export.
local _, ns = ...
local W, L, U, LL = ns.W, ns.L, ns.U, ns.LegacyLogic

local LD = {}
ns.LegacyDialogs = LD

ns.AddLocale("enUS", {
  ["legacy.dlg.importTitle"] = "Import Legacy plan",
  ["legacy.dlg.importHint"] = "Paste a Legacy link or code from forever-guides.com. Your plan is replaced when you click Import.",
  ["legacy.dlg.preview.empty"] = "Paste a link or code to see what it contains.",
  ["legacy.dlg.preview.ok"] = "Valid code (version %d): %d points in %d perks.",
  ["legacy.dlg.preview.unknown"] = "Left out, unknown perks: %s",
  ["legacy.dlg.preview.clamped"] = "Cut to the maximum rank: %s",
  ["legacy.dlg.preview.duplicates"] = "Listed twice, the last rank counts: %s",
  ["legacy.dlg.preview.warnings"] = "The plan breaks %d rule(s), it is still imported:",
  ["legacy.dlg.import"] = "Import",
  ["legacy.dlg.nameTitle"] = "Save plan",
  ["legacy.dlg.nameHint"] = "Name of the plan",
  ["legacy.dlg.save"] = "Save",
  ["legacy.dlg.err.name"] = "Enter a name.",
  ["legacy.dlg.err.exists"] = "A plan with this name exists. Click Save again to replace it.",
  ["legacy.dlg.err.full"] = "There are already %d saved plans. Delete one first.",
  ["legacy.dlg.err.nodb"] = "Saved plans are not available right now.",
})

ns.AddLocale("deDE", {
  ["legacy.dlg.importTitle"] = "Vermächtnis-Plan importieren",
  ["legacy.dlg.importHint"] = "Füge einen Vermächtnis-Link oder -Code von forever-guides.com ein. Dein Plan wird ersetzt, sobald du auf Importieren klickst.",
  ["legacy.dlg.preview.empty"] = "Füge einen Link oder Code ein, um den Inhalt zu sehen.",
  ["legacy.dlg.preview.ok"] = "Gültiger Code (Version %d): %d Punkte in %d Perks.",
  ["legacy.dlg.preview.unknown"] = "Weggelassen, unbekannte Perks: %s",
  ["legacy.dlg.preview.clamped"] = "Auf den Höchstrang gekürzt: %s",
  ["legacy.dlg.preview.duplicates"] = "Doppelt aufgeführt, der letzte Rang zählt: %s",
  ["legacy.dlg.preview.warnings"] = "Der Plan verletzt %d Regel(n), er wird trotzdem importiert:",
  ["legacy.dlg.import"] = "Importieren",
  ["legacy.dlg.nameTitle"] = "Plan speichern",
  ["legacy.dlg.nameHint"] = "Name des Plans",
  ["legacy.dlg.save"] = "Speichern",
  ["legacy.dlg.err.name"] = "Gib einen Namen ein.",
  ["legacy.dlg.err.exists"] = "Ein Plan mit diesem Namen existiert. Klicke noch einmal auf Speichern, um ihn zu ersetzen.",
  ["legacy.dlg.err.full"] = "Es gibt schon %d gespeicherte Pläne. Lösche zuerst einen.",
  ["legacy.dlg.err.nodb"] = "Gespeicherte Pläne sind gerade nicht verfügbar.",
})

local SIDE = 16
local PREVIEW_WARNINGS = 3

-- Preview ------------------------------------------------------------------------------------------

local function names(keys)
  local out = {}
  for i, key in ipairs(keys) do
    out[i] = LL.name(key) ~= "" and LL.name(key) or key
  end
  return table.concat(out, ", ")
end

-- What a pasted text contains, without taking anything over. Returns
--   { ok = true, build, report, lines } for a readable code (lines = the preview texts), or
--   { ok = false, reason, lines = { error text } }.
function LD.Preview(text)
  if U.trim(text or "") == "" then
    return { ok = false, reason = "empty", lines = { L["legacy.dlg.preview.empty"] } }
  end
  local build, report, reason = LL.import(text)
  if not build then
    return { ok = false, reason = reason, lines = { LL.text("legacy.err." .. tostring(reason)) } }
  end
  local perks = 0
  for _ in pairs(build.ranks) do
    perks = perks + 1
  end
  local check = LL.validate(build)
  local lines = {
    string.format(L["legacy.dlg.preview.ok"], report.version, check.spent.total, perks),
    LL.summary(build),
  }
  if #report.unknownKeys > 0 then
    lines[#lines + 1] = string.format(L["legacy.dlg.preview.unknown"], table.concat(report.unknownKeys, ", "))
  end
  if #report.clamped > 0 then
    local keys = {}
    for i, entry in ipairs(report.clamped) do
      keys[i] = entry.key
    end
    lines[#lines + 1] = string.format(L["legacy.dlg.preview.clamped"], names(keys))
  end
  if #report.duplicates > 0 then
    lines[#lines + 1] = string.format(L["legacy.dlg.preview.duplicates"], names(report.duplicates))
  end
  if #check.warnings > 0 then
    lines[#lines + 1] = string.format(L["legacy.dlg.preview.warnings"], #check.warnings)
    for i = 1, math.min(PREVIEW_WARNINGS, #check.warnings) do
      lines[#lines + 1] = "- " .. LL.warningText(check.warnings[i])
    end
  end
  return { ok = true, build = build, report = report, lines = lines }
end

-- Windows ------------------------------------------------------------------------------------------

local function closeOnEscape(dialog, edit)
  edit:SetScript("OnEscapePressed", function()
    dialog:Hide()
  end)
end

local function focusLater(edit)
  C_Timer.After(0.05, function()
    edit:SetFocus()
  end)
end

local importDialog

-- submit(build, report) is called after the click on Import with the previewed build.
function LD.Import(submit)
  local d = importDialog
  if not d then
    d = ns.Dialogs.Create("ForeverGuidesLegacyImport", 520, 400)
    importDialog = d
    W.SetText(d.title, "legacy.dlg.importTitle")
    local hint = W.Text(d, { key = "legacy.dlg.importHint", role = "ui", color = "textSecondary", wrap = true })
    hint:SetPoint("TOPLEFT", SIDE, -48)
    hint:SetPoint("RIGHT", -SIDE, 0)
    d.input = W.TextArea(d, {
      height = 90,
      onChange = function()
        d.refresh()
      end,
    })
    d.input:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    d.input:SetPoint("RIGHT", -SIDE, 0)
    d.input.edit:SetMaxLetters(0)
    d.preview = W.Text(d, { role = "ui", color = "text", wrap = true, text = "" })
    d.preview:SetPoint("TOPLEFT", d.input, "BOTTOMLEFT", 0, -10)
    d.preview:SetPoint("RIGHT", -SIDE, 0)
    closeOnEscape(d, d.input.edit)

    d.confirm = W.Action(d, {
      label = "act.import",
      icon = "import",
      tooltip = "legacy.dlg.import",
      variant = "primary",
      width = 130,
      onClick = function()
        local result = d.result
        if result and result.ok then
          d:Hide()
          d.submit(result.build, result.report)
        end
      end,
    })
    d.confirm:SetPoint("BOTTOMRIGHT", -SIDE, 14)
    local cancel = W.Action(d, {
      label = "act.cancel",
      icon = "close",
      tooltip = "common.cancel",
      width = 110,
      onClick = function()
        d:Hide()
      end,
    })
    cancel:SetPoint("RIGHT", d.confirm, "LEFT", -8, 0)

    function d.refresh()
      d.result = LD.Preview(d.input:GetValue())
      W.SetText(d.preview, nil, table.concat(d.result.lines, "\n"))
      W.SetColor(d.preview, (d.result.ok or d.result.reason == "empty") and "text" or "danger")
      d.confirm:SetEnabled(d.result.ok)
    end
  end
  d.submit = submit
  d.input:SetValue("")
  d.refresh()
  d:Show()
  focusLater(d.input.edit)
  return d
end

local nameDialog

-- submit(name, replace) returns true when the plan was stored (the window closes), or false plus the error
-- ("name", "exists", "full", "nodb"). After "exists" a second click with the same name sends replace = true.
function LD.SaveName(submit, suggestion)
  local d = nameDialog
  if not d then
    d = ns.Dialogs.Create("ForeverGuidesLegacyName", 420, 190)
    nameDialog = d
    W.SetText(d.title, "legacy.dlg.nameTitle")
    local hint = W.Text(d, { key = "legacy.dlg.nameHint", role = "ui", color = "textSecondary" })
    hint:SetPoint("TOPLEFT", SIDE, -48)
    d.field = W.EditBox(d, {
      onChange = function()
        d.replaceFor = nil
        W.SetText(d.error, nil, "")
      end,
      onEnter = function()
        d.run()
      end,
    })
    d.field:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
    d.field:SetPoint("RIGHT", -SIDE, 0)
    d.field.edit:SetMaxLetters(ns.LegacyPlan.NAME_MAX)
    d.error = W.Text(d, { role = "ui", color = "danger", wrap = true, text = "" })
    d.error:SetPoint("TOPLEFT", d.field, "BOTTOMLEFT", 0, -8)
    d.error:SetPoint("RIGHT", -SIDE, 0)
    closeOnEscape(d, d.field.edit)

    function d.run()
      local name = ns.LegacyPlan.cleanName(d.field.edit:GetText())
      if not name then
        return W.SetText(d.error, nil, L["legacy.dlg.err.name"])
      end
      local ok, reason = d.submit(name, d.replaceFor == name:lower())
      if ok then
        d:Hide()
      elseif reason == "exists" then
        d.replaceFor = name:lower()
        W.SetText(d.error, nil, L["legacy.dlg.err.exists"])
      elseif reason == "full" then
        W.SetText(d.error, nil, string.format(L["legacy.dlg.err.full"], ns.LegacyPlan.MAX_PLANS))
      else
        W.SetText(d.error, nil, L["legacy.dlg.err." .. tostring(reason or "nodb")] or L["legacy.dlg.err.nodb"])
      end
    end
    local save = W.Action(d, {
      label = "act.save",
      icon = "save",
      tooltip = "legacy.dlg.save",
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
  d.replaceFor = nil
  d.field.edit:SetText(suggestion or "")
  W.SetText(d.error, nil, "")
  d:Show()
  focusLater(d.field.edit)
  return d
end
