-- Import and export windows of the talent editor. The editor owns the rules and
-- the build; these windows only collect the pasted text and show the codes.
local _, ns = ...
local W, L, U = ns.W, ns.L, ns.U

local TD = {}
ns.TalentDialogs = TD

ns.AddLocale("enUS", {
  ["talents.editor.exportLink"] = "Web link (forever-guides.com)",
  ["talents.editor.exportCode"] = "Code only (for chat or notes)",
  ["talents.editor.exportEmpty"] = "Build has no points: spend points first",
  ["talents.editor.exportShare"] = "Share in chat",
  ["talents.builds.nameHint"] = "Name of the build",
  ["talents.builds.nameSave"] = "Save",
})

ns.AddLocale("deDE", {
  ["talents.editor.exportLink"] = "Web-Link (forever-guides.com)",
  ["talents.editor.exportCode"] = "Nur der Code (für Chat oder Notizen)",
  ["talents.editor.exportEmpty"] = "Build ohne Punkte: erst Punkte vergeben",
  ["talents.editor.exportShare"] = "Im Chat teilen",
  ["talents.builds.nameHint"] = "Name der Skillung",
  ["talents.builds.nameSave"] = "Speichern",
})

local SIDE = 16

-- Esc closes the window with one press, even while a text field has the focus.
local function closeOnEscape(dialog, area)
  area.edit:SetScript("OnEscapePressed", function()
    dialog:Hide()
  end)
end

-- Focus the field next frame, the window is not laid out when Show returns.
local function focusLater(area, select)
  C_Timer.After(0.05, function()
    area.edit:SetFocus()
    if select then
      area.edit:HighlightText()
    end
  end)
end

local importDialog

-- submit(text) returns true when the build was taken over (the window closes), or
-- false plus the message to show in the window.
function TD.Import(submit)
  local d = importDialog
  if not d then
    d = ns.Dialogs.Create("ForeverGuidesTalentImport", 480, 330)
    importDialog = d
    W.SetText(d.title, "talents.editor.importTitle")
    local hint = W.Text(d, { key = "talents.editor.importHint", role = "ui", color = "textSecondary", wrap = true })
    hint:SetPoint("TOPLEFT", SIDE, -48)
    hint:SetPoint("RIGHT", -SIDE, 0)
    d.input = W.TextArea(d, { height = 110 })
    d.input:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    d.input:SetPoint("RIGHT", -SIDE, 0)
    d.error = W.Text(d, { role = "ui", color = "danger", wrap = true, text = "" })
    d.error:SetPoint("TOPLEFT", d.input, "BOTTOMLEFT", 0, -8)
    d.error:SetPoint("RIGHT", -SIDE, 0)
    closeOnEscape(d, d.input)

    local function run()
      local text = d.input:GetValue()
      if U.trim(text) == "" then
        return W.SetText(d.error, nil, L["talents.editor.loadEmpty"])
      end
      local ok, message = d.submit(text)
      if ok then
        d:Hide()
      else
        W.SetText(d.error, nil, message or "")
      end
    end
    local confirm = W.Action(d, {
      label = "act.import",
      icon = "import",
      tooltip = "talents.editor.import",
      variant = "primary",
      width = 110,
      height = 28,
      onClick = run,
    })
    confirm:SetPoint("BOTTOMRIGHT", -SIDE, 14)
    local cancel = W.Action(d, {
      label = "act.cancel",
      icon = "close",
      tooltip = "common.cancel",
      width = 110,
      height = 28,
      onClick = function()
        d:Hide()
      end,
    })
    cancel:SetPoint("RIGHT", confirm, "LEFT", -8, 0)
  end
  d.submit = submit
  d.input:SetValue("")
  W.SetText(d.error, nil, "")
  d:Show()
  focusLater(d.input, false)
  return d
end

local exportDialog

-- data = { info, link, code, share }, or nil for a build without points (a hint instead).
function TD.Export(data)
  local d = exportDialog
  if not d then
    d = ns.Dialogs.Create("ForeverGuidesTalentExport", 520, 330)
    exportDialog = d
    W.SetText(d.title, "talents.editor.exportTitle")
    d.info = W.Text(d, { role = "ui", color = "textSecondary", wrap = true, text = "" })
    d.info:SetPoint("TOPLEFT", SIDE, -48)
    d.info:SetPoint("RIGHT", -SIDE, 0)
    d.linkLabel = W.Text(d, { key = "talents.editor.exportLink", role = "ui", color = "accent2" })
    d.linkLabel:SetPoint("TOPLEFT", d.info, "BOTTOMLEFT", 0, -10)
    d.link = W.TextArea(d, { height = 62, readOnly = true })
    d.link:SetPoint("TOPLEFT", d.linkLabel, "BOTTOMLEFT", 0, -4)
    d.link:SetPoint("RIGHT", -SIDE, 0)
    d.codeLabel = W.Text(d, { key = "talents.editor.exportCode", role = "ui", color = "accent2" })
    d.codeLabel:SetPoint("TOPLEFT", d.link, "BOTTOMLEFT", 0, -10)
    d.code = W.TextArea(d, { height = 46, readOnly = true })
    d.code:SetPoint("TOPLEFT", d.codeLabel, "BOTTOMLEFT", 0, -4)
    d.code:SetPoint("RIGHT", -SIDE, 0)
    for _, area in ipairs({ d.link, d.code }) do
      closeOnEscape(d, area)
      area.edit:HookScript("OnEditFocusGained", function(self)
        self:HighlightText()
      end)
    end
    local keys = W.Text(d, { key = "copy.hint", role = "micro", color = "textMuted" })
    keys:SetPoint("BOTTOMLEFT", SIDE, 20)
    local close = W.Action(d, {
      label = "act.close",
      icon = "close",
      tooltip = "common.close",
      variant = "primary",
      width = 110,
      height = 28,
      onClick = function()
        d:Hide()
      end,
    })
    close:SetPoint("BOTTOMRIGHT", -SIDE, 14)
    d.share = W.Action(d, {
      label = "act.share",
      icon = "share",
      tooltip = "talents.editor.exportShare",
      width = 150,
      height = 28,
      onClick = function()
        local share = d.onShare
        d:Hide()
        if share then
          share()
        end
      end,
    })
    d.share:SetPoint("RIGHT", close, "LEFT", -8, 0)
  end
  local filled = data ~= nil
  if filled then
    W.SetText(d.info, nil, data.info)
  else
    W.SetText(d.info, "talents.editor.exportEmpty")
  end
  for _, part in ipairs({ d.linkLabel, d.link, d.codeLabel, d.code }) do
    part:SetShown(filled)
  end
  d.onShare = filled and data.share or nil
  d.share:SetShown(d.onShare ~= nil)
  d.link:SetValue(filled and data.link or "")
  d.code:SetValue(filled and data.code or "")
  d:Show()
  if filled then
    focusLater(d.link, true)
  end
  return d
end

local nameDialog

-- Name prompt for saving or renaming a build. submit(name) returns true when the build was stored
-- (the window closes), or false plus the locale key of the problem (shown in the window).
function TD.Name(titleKey, suggestion, submit)
  local d = nameDialog
  if not d then
    d = ns.Dialogs.Create("ForeverGuidesTalentName", 420, 190)
    nameDialog = d
    local hint = W.Text(d, { key = "talents.builds.nameHint", role = "ui", color = "textSecondary" })
    hint:SetPoint("TOPLEFT", SIDE, -48)
    d.field = W.EditBox(d, {
      onChange = function()
        W.SetText(d.error, nil, "")
      end,
      onEnter = function()
        d.run()
      end,
    })
    d.field:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
    d.field:SetPoint("RIGHT", -SIDE, 0)
    d.field.edit:SetMaxLetters(ns.TalentBuilds.NAME_MAX)
    d.error = W.Text(d, { role = "ui", color = "danger", wrap = true, text = "" })
    d.error:SetPoint("TOPLEFT", d.field, "BOTTOMLEFT", 0, -8)
    d.error:SetPoint("RIGHT", -SIDE, 0)
    closeOnEscape(d, d.field)

    function d.run()
      local name = ns.TalentBuilds.cleanName(d.field.edit:GetText())
      if not name then
        return W.SetText(d.error, "talents.builds.err.name")
      end
      local ok, key = d.submit(name)
      if ok then
        d:Hide()
      else
        W.SetText(d.error, key)
      end
    end
    local save = W.Action(d, {
      label = "act.save",
      icon = "save",
      tooltip = "talents.builds.nameSave",
      variant = "primary",
      width = 110,
      onClick = d.run,
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
  focusLater(d.field, true)
  return d
end
