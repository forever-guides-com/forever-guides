-- Join dates in the interface: the dialog "Join date" (one member, typed by hand), the bulk import
-- from a text with a preview, the detail lines "Joined" and "In rank since" with source and accuracy
-- and the optional column "Joined". Reads and writes only the own store, never the guild.
local _, gm = ...
if not gm.ext then
  return
end
local FG, HL, DL = gm.FG, gm.HistoryLogic, gm.DatesLogic
local W, L = FG.W, FG.L
local H = gm.History

local J = {}
gm.JoinDialog = J

local PREVIEW_ROWS = 6

local function store()
  return gm.Guild().members
end

local function say(box, key, ...)
  box:SetText(string.format(L[key], ...))
end

-- Single member -----------------------------------------------------------------------------------------

local dialog
local save

local function buildDialog()
  local d = FG.Dialogs.Create("ForeverGuidesGMJoin", 400, 270)
  W.SetText(d.title, "gm.join.title")
  d.who = W.Text(d, { role = "ui", color = "accent2" })
  d.who:SetPoint("TOPLEFT", 16, -44)
  local label = W.Text(d, { key = "gm.join.date", role = "ui" })
  label:SetPoint("TOPLEFT", 16, -76)
  d.date = W.EditBox(d, { placeholder = "gm.join.dateEmpty", onEnter = save })
  d.date:SetPoint("TOPLEFT", 16, -96)
  d.date:SetWidth(368)
  d.date.edit:SetMaxLetters(10)
  local hint = W.Text(d, { key = "gm.join.clearHint", role = "micro", color = "textMuted" })
  hint:SetPoint("TOPLEFT", 16, -128)
  d.current = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
  d.current:SetPoint("TOPLEFT", 16, -152)
  d.current:SetPoint("RIGHT", -16, 0)
  d.msg = W.Text(d, { role = "ui", color = "danger", wrap = true })
  d.msg:SetPoint("TOPLEFT", 16, -190)
  d.msg:SetPoint("RIGHT", -16, 0)
  local ok = W.Action(
    d,
    { label = "act.save", icon = "save", tooltip = "gm.join.save", variant = "primary", width = 110, onClick = save }
  )
  ok.fgId = "gm-join-save"
  ok:SetPoint("BOTTOMRIGHT", -16, 14)
  local cancel = W.Action(d, {
    label = "act.cancel",
    icon = "close",
    tooltip = "common.cancel",
    width = 110,
    onClick = function()
      d:Hide()
    end,
  })
  cancel:SetPoint("RIGHT", ok, "LEFT", -8, 0)
  local import = W.Button(d, {
    key = "gm.join.import",
    tooltip = "gm.join.import.tip",
    width = 100,
    opens = true,
    onClick = function()
      d:Hide()
      J.OpenImport(d.ctx)
    end,
  })
  import.fgId = "gm-join-import"
  import:SetPoint("BOTTOMLEFT", 16, 14)
  return d
end

local function currentText(member)
  local e = store()[member.key]
  if not (e and e.joined) then
    return ""
  end
  return string.format(L["gm.join.current"], DL.Text(e.joined, L, H.DateFormat()), DL.SourceText(e.joined, L))
end

function save()
  local d = dialog
  local blocked = gm.WriteBlock()
  if blocked then
    d.msg:SetText(L["gm.err." .. blocked])
    return
  end
  local today = H.Clock()
  if not today then
    say(d.msg, "gm.join.err.clock")
    return
  end
  local text = d.date.edit:GetText()
  if text:match("^%s*$") then
    HL.ClearJoined(store(), d.member.key)
  else
    local day, why = DL.ParseDate(text, H.SlashOrder(), today)
    if not day then
      say(d.msg, "gm.join.err." .. why)
      return
    end
    HL.SetJoined(store(), d.member, day, today)
  end
  d:Hide()
  d.ctx.Refresh()
end

-- member: { key, name } of the roster; ctx: the context of the guild page (Refresh).
function J.Open(member, ctx)
  dialog = dialog or buildDialog()
  dialog.member, dialog.ctx = member, ctx
  dialog.who:SetText(member.name)
  local e = store()[member.key]
  local manual = e and e.joined and e.joined.src == "manual" and e.joined.minDay == e.joined.maxDay
  dialog.date.edit:SetText(manual and DL.Format(e.joined.minDay, H.DateFormat()) or "")
  dialog.current:SetText(currentText(member))
  dialog.msg:SetText("")
  dialog:Show()
end

-- Bulk import -----------------------------------------------------------------------------------------------

local importer

-- Lines of the preview: the summary, then the first rows that are ready or wrong.
local function previewText(parsed)
  local lines = { string.format(L["gm.import.summary"], parsed.ok, parsed.bad) }
  if parsed.tooMany then
    lines[#lines + 1] = string.format(L["gm.import.tooMany"], HL.MAX_LINES)
  end
  local shown = 0
  local format = H.DateFormat()
  for _, row in ipairs(parsed.rows) do
    if shown >= PREVIEW_ROWS then
      lines[#lines + 1] = string.format(L["gm.import.more"], #parsed.rows - shown)
      break
    end
    shown = shown + 1
    if row.reason then
      lines[#lines + 1] = string.format(
        L["gm.import.badRow"],
        row.line,
        string.format(L["gm.import.row"], row.name or "?", L["gm.join.err." .. row.reason])
      )
    else
      lines[#lines + 1] = string.format(L["gm.import.row"], row.member.name, DL.Format(row.day, format))
    end
  end
  return table.concat(lines, "\n")
end

local function roster()
  local out = {}
  for _, m in ipairs(FG.GuildData.Get().members) do
    out[#out + 1] = { key = m.key, name = m.name }
  end
  return out
end

local function setApply(d, n)
  d.apply.label:SetText(string.format(L["gm.import.apply"], n or 0))
  if n and n > 0 then
    d.apply:Enable()
  else
    d.apply:Disable()
  end
end

local function check()
  local d = importer
  local today = H.Clock()
  if not today then
    d.preview:SetText(L["gm.join.err.clock"])
    return
  end
  local parsed = HL.ParseImport(d.input:GetValue(), roster(), { order = H.SlashOrder(), today = today })
  if #parsed.rows == 0 then
    d.parsed = nil
    d.preview:SetText(L["gm.import.empty"])
    setApply(d, 0)
    return
  end
  d.preview:SetText(previewText(parsed))
  d.parsed = parsed
  setApply(d, parsed.bad == 0 and parsed.ok or 0)
end

local function apply()
  local d = importer
  local blocked = gm.WriteBlock()
  if blocked then
    d.preview:SetText(L["gm.err." .. blocked])
    return
  end
  local today = H.Clock()
  local parsed = d.parsed
  if not (today and parsed and parsed.bad == 0 and parsed.ok > 0) then
    return
  end
  local n = HL.ApplyImport(store(), parsed, today)
  d.parsed = nil
  d.preview:SetText(string.format(L["gm.import.done"], n))
  setApply(d, 0)
  if d.ctx and d.ctx.Refresh then
    d.ctx.Refresh()
  end
end

local function buildImporter()
  local d = FG.Dialogs.Create("ForeverGuidesGMImport", 520, 440)
  W.SetText(d.title, "gm.import.title")
  local hint = W.Text(d, { key = "gm.import.hint", role = "ui", color = "textSecondary", wrap = true })
  hint:SetPoint("TOPLEFT", 16, -48)
  hint:SetPoint("RIGHT", -16, 0)
  d.input = W.TextArea(d, {
    height = 170,
    onChange = function()
      d.parsed = nil
      setApply(d, 0)
    end,
  })
  d.input:SetPoint("TOPLEFT", 16, -76)
  d.input:SetPoint("RIGHT", -16, 0)
  d.preview = W.Text(d, { role = "ui", wrap = true })
  d.preview:SetPoint("TOPLEFT", 16, -260)
  d.preview:SetPoint("RIGHT", -16, 0)
  d.apply = W.Action(d, {
    label = "gm.import.apply",
    variant = "primary",
    width = 130,
    onClick = apply,
  })
  d.apply.fgId = "gm-import-apply"
  d.apply:SetPoint("BOTTOMRIGHT", -16, 14)
  d.check = W.Button(d, { key = "gm.import.check", width = 110, onClick = check })
  d.check.fgId = "gm-import-check"
  d.check:SetPoint("RIGHT", d.apply, "LEFT", -8, 0)
  local close = W.Action(d, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    width = 110,
    onClick = function()
      d:Hide()
    end,
  })
  close:SetPoint("BOTTOMLEFT", 16, 14)
  return d
end

function J.OpenImport(ctx)
  importer = importer or buildImporter()
  importer.ctx, importer.parsed = ctx, nil
  importer.input:SetValue("")
  importer.preview:SetText("")
  setApply(importer, 0)
  importer:Show()
end

-- Detail lines and column ----------------------------------------------------------------------------------

gm.ext.RegisterDetail({
  id = "gm-dates",
  order = 15,
  lines = function(m)
    local e = store()[m.key]
    local format = H.DateFormat()
    local lines = {}
    if e and e.joined then
      lines[1] = string.format(L["gm.detail.joined"], DL.Text(e.joined, L, format), DL.SourceText(e.joined, L))
    else
      lines[1] = L["gm.detail.joinedNone"]
    end
    if e and e.rankSince then
      lines[#lines + 1] =
        string.format(L["gm.detail.rankSince"], DL.Text(e.rankSince, L, format), DL.SourceText(e.rankSince, L))
    end
    if e and e.returnedDay then
      local day = DL.Format(e.returnedDay, format)
      lines[#lines + 1] = e.returnedAfter and string.format(L["gm.detail.returnedAfter"], day, e.returnedAfter)
        or string.format(L["gm.detail.returned"], day)
    end
    return lines
  end,
})

-- Optional column: off until the player switches it on (a stored choice is never touched).
local COLUMN_PATH = "settings.guildCols.guild.gm-joined"
if type(FG.db) == "table" and FG.Store.get(COLUMN_PATH) == nil then
  FG.Store.set(COLUMN_PATH, false)
end

-- Short form for the list: the day when exact, else the latest or the earliest day known.
gm.ext.RegisterColumn({
  id = "gm-joined",
  key = "gm.col.joined",
  order = 20,
  value = function(m)
    local e = store()[m.key]
    local info = e and DL.Clean(e.joined)
    if not info then
      return nil
    end
    local format = H.DateFormat()
    if info.maxDay and info.minDay == info.maxDay then
      return DL.Format(info.maxDay, format)
    end
    return info.maxDay and string.format(L["gm.col.joinedMax"], DL.Format(info.maxDay, format))
      or string.format(L["gm.col.joinedMin"], DL.Format(info.minDay, format))
  end,
})
