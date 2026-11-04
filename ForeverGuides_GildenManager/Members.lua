-- Members plus: main and alt links and an own note per member, stored locally. Shown as a column
-- and as detail lines of the guild page, edited in a small dialog from the detail card.
local _, gm = ...
if not gm.ext then
  return
end
local FG, ML = gm.FG, gm.MembersLogic
local W, L = FG.W, FG.L

local function store()
  return gm.Guild().members
end

local dialog
local save

local function buildDialog()
  local d = FG.Dialogs.Create("ForeverGuidesGMMember", 400, 410)
  W.SetText(d.title, "gm.edit.title")
  d.who = W.Text(d, { role = "ui", color = "accent2" })
  d.who:SetPoint("TOPLEFT", 16, -44)
  local info = W.InfoButton(d, "gm.edit.title", "gm.edit.help")
  info.fgId = "gm-edit-help"
  info:SetPoint("TOPRIGHT", -16, -42)
  local function field(labelKey, placeholder, y, maxLetters)
    local label = W.Text(d, { key = labelKey, role = "ui" })
    label:SetPoint("TOPLEFT", 16, -y)
    local box = W.EditBox(d, { placeholder = placeholder, onEnter = save })
    box:SetPoint("TOPLEFT", 16, -(y + 20))
    box:SetWidth(368)
    box.edit:SetMaxLetters(maxLetters)
    box.label = label
    return box
  end
  d.main = field("gm.edit.main", "gm.edit.mainEmpty", 76, FG.PlayerName.MAX_PART * 3 + 2)
  d.note = field("gm.edit.note", "gm.edit.noteEmpty", 134, ML.MAX_NOTE)
  -- Birthday and absence of the reminders (RemindersLogic.lua): typed by hand, kept on this PC only.
  d.birthday = field("gm.rem.birthday.fmt.dmy", "gm.rem.birthdayEmpty", 190, 6)
  d.birthday.fgId = "gm-edit-birthday"
  d.away = field("gm.rem.away", "gm.rem.awayEmpty", 248, 10)
  d.away.fgId = "gm-edit-away"
  d.msg = W.Text(d, { role = "ui", color = "danger", wrap = true })
  d.msg:SetPoint("TOPLEFT", 16, -306)
  d.msg:SetPoint("RIGHT", -16, 0)
  local hint = W.Text(d, { key = "guild.seen.local", role = "micro", color = "textMuted" })
  hint:SetPoint("TOPLEFT", 16, -346)
  local ok = W.Action(
    d,
    { label = "act.save", icon = "save", tooltip = "gm.edit.save", variant = "primary", width = 110, onClick = save }
  )
  ok.fgId = "gm-edit-save"
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
  -- The join dialog is a later file of the add-on: looked up when clicked.
  local join = W.Button(d, {
    key = "gm.join.open",
    tooltip = "gm.join.title",
    width = 100,
    opens = true,
    onClick = function()
      if gm.JoinDialog then
        d:Hide()
        gm.JoinDialog.Open(d.member, d.ctx)
      end
    end,
  })
  join.fgId = "gm-edit-join"
  join:SetPoint("BOTTOMLEFT", 16, 14)
  return d
end

-- The main is checked first: a refused link changes nothing, not even the note.
function save()
  local d = dialog
  local blocked = gm.WriteBlock()
  if blocked then
    d.msg:SetText(L["gm.err." .. blocked])
    return
  end
  -- Birthday and absence are checked first too: a refused entry changes nothing.
  local RM, H = gm.RemindersLogic, gm.History
  local birthday, bwhy = RM.ParseBirthday(d.birthday.edit:GetText(), H.DateFormat())
  if bwhy and bwhy ~= "empty" then
    d.msg:SetText(L["gm.rem.err.birthday." .. bwhy])
    return
  end
  local away, awhy = RM.ParseAway(d.away.edit:GetText(), H.SlashOrder(), (H.Clock()))
  if awhy and awhy ~= "empty" then
    d.msg:SetText(L["gm.rem.err.away." .. awhy])
    return
  end
  local ok, why = ML.SetMain(store(), d.member, d.main.edit:GetText())
  if not ok then
    d.msg:SetText(L["gm.err." .. why])
    return
  end
  ML.SetNote(store(), d.member, d.note.edit:GetText())
  RM.SetBirthday(store(), d.member, birthday)
  RM.SetAway(store(), d.member, away)
  d:Hide()
  d.ctx.Refresh()
end

local function edit(member, ctx)
  dialog = dialog or buildDialog()
  dialog.member, dialog.ctx = member, ctx
  dialog.who:SetText(member.name)
  dialog.main.edit:SetText(ML.MainOf(store(), member.key) or "")
  local e = store()[member.key]
  dialog.note.edit:SetText(e and e.note or "")
  local RM, H = gm.RemindersLogic, gm.History
  local format = H.DateFormat()
  W.SetText(dialog.birthday.label, "gm.rem.birthday.fmt." .. format)
  dialog.birthday.edit:SetText(e and e.birthday and RM.FormatBirthday(e.birthday, format) or "")
  local today = H.Clock()
  local away = e and e.away
  dialog.away.edit:SetText(away and (not today or RM.IsAway(away, today)) and gm.DatesLogic.Format(away, format) or "")
  dialog.msg:SetText("")
  dialog:Show()
end

gm.ext.RegisterColumn({
  id = "gm-main",
  key = "gm.col.main",
  order = 10,
  value = function(m)
    local main = ML.MainOf(store(), m.key)
    return main and string.format(L["gm.col.mainValue"], main) or nil
  end,
})

gm.ext.RegisterDetail({
  id = "gm-members",
  order = 10,
  lines = function(m)
    local lines = {}
    local main = ML.MainOf(store(), m.key)
    if main then
      lines[#lines + 1] = string.format(L["gm.detail.main"], main)
    end
    local alts = ML.AltsOf(store(), m.key)
    if #alts > 0 then
      lines[#lines + 1] = string.format(L["gm.detail.alts"], table.concat(alts, ", "))
    end
    local e = store()[m.key]
    if e and e.note ~= "" then
      lines[#lines + 1] = string.format(L["gm.detail.note"], e.note)
    end
    return lines
  end,
  actions = function()
    return { { key = "gm.edit", opens = true, onClick = edit } }
  end,
})
