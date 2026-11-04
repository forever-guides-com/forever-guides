-- Export and import windows (ExportLogic.lua holds the rules). The export window makes a text, CSV, JSON
-- or restore point string and opens it in the copy window; nothing is sent anywhere. The import window
-- reads a restore point, shows what would change and lists every clash with something typed by hand: the
-- player decides each one (default: keep mine), then confirms once. Never a silent overwrite.
local _, gm = ...
if not gm.ext then
  return
end
local FG, EL = gm.FG, gm.ExportLogic
local W, L, PK = FG.W, FG.L, FG.PageKit

local X = {}
gm.Export = X

local FORMATS = { "text", "csv", "json", "backup" }
local LIST_HEIGHT = 156
local ROW_HEIGHT = 52

local function notify(text, kind)
  FG.Notify(text, kind or "info")
end

local function context()
  local today, now = gm.History.Clock()
  return { L = L, format = gm.History.DateFormat(), today = today, now = now }
end

local function close(parent)
  local b = W.Action(parent, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    width = 110,
    onClick = function()
      parent:Hide()
    end,
  })
  b:SetPoint("BOTTOMLEFT", 16, 14)
  return b
end

-- Export ------------------------------------------------------------------------------------------------

local exporter

local function create(d)
  local state, guild = d.state, gm.Guild()
  local text, info
  if state.format == "backup" then
    text, info = EL.Backup(guild)
  else
    local any = false
    for _, on in pairs(state.parts) do
      any = any or on
    end
    if not any then
      notify(L["gm.exp.err.noParts"], "warning")
      return
    end
    text, info = EL.Build(guild, state.format, state.parts, context())
  end
  if not text then
    notify(L["gm.exp.err." .. tostring(info)], "warning")
    return
  end
  d:Hide()
  FG.Dialogs.Copy("gm.exp.copyTitle", text, state.format == "backup" and "gm.exp.copyHintBackup" or "gm.exp.copyHint")
  if type(info) == "table" and info.truncated then
    notify(L["gm.exp.truncatedNote"], "warning")
  end
end

local function buildExporter()
  local d = FG.Dialogs.Create("ForeverGuidesGMExport", 460, 366)
  W.SetText(d.title, "gm.exp.window")
  d.state = { format = "text", parts = { members = true, events = true, actions = true, bans = true, rules = true } }
  local options = {}
  for _, id in ipairs(FORMATS) do
    options[#options + 1] = { value = id, key = "gm.exp.fmt." .. id }
  end
  d.format = W.Dropdown(d, {
    key = "gm.exp.format",
    options = options,
    width = 240,
    get = function()
      return d.state.format
    end,
    set = function(v)
      d.state.format = v
      d.refresh()
    end,
  })
  d.format.button.fgId = "gm-exp-format"
  d.format:SetPoint("TOPLEFT", 16, -48)
  d.format:SetWidth(240)
  d.checks = {}
  for i, part in ipairs(EL.PARTS) do
    local c = W.Checkbox(d, {
      key = "gm.exp.part." .. part,
      get = function()
        return d.state.parts[part] == true
      end,
      set = function(v)
        d.state.parts[part] = v == true
      end,
    })
    c.fgId = "gm-exp-part-" .. part
    c:SetPoint("TOPLEFT", 16, -108 - (i - 1) * 26)
    c:SetWidth(428)
    d.checks[#d.checks + 1] = c
  end
  d.note = W.Text(d, { key = "gm.exp.note", role = "small", color = "textSecondary", wrap = true })
  d.note:SetPoint("TOPLEFT", 16, -250)
  d.note:SetWidth(428)
  d.create = W.Action(d, {
    label = "gm.exp.create",
    variant = "primary",
    width = 130,
    onClick = function()
      create(d)
    end,
  })
  d.create.fgId = "gm-exp-create"
  d.create:SetPoint("BOTTOMRIGHT", -16, 14)
  close(d)
  function d.refresh()
    d.format.Refresh()
    for _, c in ipairs(d.checks) do
      c:SetShown(d.state.format ~= "backup")
      c.Refresh()
    end
  end
  return d
end

function X.OpenExport()
  exporter = exporter or buildExporter()
  exporter.refresh()
  exporter:Show()
end

-- Import --------------------------------------------------------------------------------------------------

local importer

local function setApply(d, n)
  d.apply.label:SetText(string.format(L["gm.imp.apply"], n or 0))
  if n and n > 0 then
    d.apply:Enable()
  else
    d.apply:Disable()
  end
end

local function takeCount(d)
  local n = 0
  for _, c in ipairs(d.plan and d.plan.conflicts or {}) do
    if d.take[c.id] then
      n = n + 1
    end
  end
  return n
end

local function refreshList(d)
  local conflicts = d.plan and d.plan.conflicts or {}
  d.list:SetData(conflicts)
  d.allMine:SetShown(#conflicts > 0)
  d.allTheirs:SetShown(#conflicts > 0)
  d.listHint:SetShown(#conflicts > 0)
  d.list:SetShown(#conflicts > 0)
end

local function clearPlan(d)
  d.parsed, d.plan, d.take = nil, nil, {}
  setApply(d, 0)
  refreshList(d)
end

local function previewText(d)
  local p, plan = d.parsed, d.plan
  local lines = { string.format(L["gm.imp.from"], p.name ~= "" and p.name or "?", p.realm ~= "" and p.realm or "?") }
  if not plan.sameGuild then
    lines[#lines + 1] = L["gm.imp.otherGuild"]
  end
  local c = plan.counts
  lines[#lines + 1] = string.format(L["gm.imp.counts"], c.members, c.events, c.actions, c.bans, c.rules)
  local dropped = 0
  for _, n in pairs(p.report) do
    dropped = dropped + n
  end
  if dropped > 0 then
    lines[#lines + 1] = string.format(L["gm.imp.repaired"], dropped)
  end
  local clashes = #plan.conflicts + plan.more
  if clashes > 0 then
    lines[#lines + 1] = string.format(L["gm.imp.conflicts"], clashes)
  elseif plan.total == 0 then
    lines[#lines + 1] = L["gm.imp.nothing"]
  end
  return table.concat(lines, "\n")
end

local function check(d)
  local text = d.input:GetValue()
  local parsed, why = EL.Parse(text, { ranks = FG.GuildData.Get().ranks })
  clearPlan(d)
  if not parsed then
    d.preview:SetText(L["gm.imp.err." .. tostring(why)])
    return
  end
  d.parsed = parsed
  d.plan = EL.Plan(gm.Guild(), parsed, context())
  d.preview:SetText(previewText(d))
  refreshList(d)
  setApply(d, d.plan.total + #d.plan.conflicts)
end

local function apply(d)
  local block = gm.WriteBlock()
  if block then
    d.preview:SetText(L["gm.err." .. block])
    return
  end
  if not (d.parsed and d.plan) then
    return
  end
  local plan = d.plan
  local text =
    string.format(L["gm.imp.confirmText"], plan.counts.members + plan.counts.bans + plan.counts.rules, takeCount(d))
  if not plan.sameGuild then
    text = text .. "\n" .. L["gm.imp.otherGuild"]
  end
  FG.Dialogs.Confirm("gm.imp.confirmTitle", nil, function()
    local counts = EL.Apply(gm.Guild(), d.parsed, d.take, context())
    local total = 0
    for _, n in pairs(counts) do
      total = total + n
    end
    clearPlan(d)
    d.preview:SetText(string.format(L["gm.imp.done"], total))
    if d.ctx and d.ctx.Refresh then
      d.ctx.Refresh()
    end
  end, nil, { text = text, yesKey = "gm.imp.yes" })
end

local function setAll(d, value)
  for _, c in ipairs(d.plan and d.plan.conflicts or {}) do
    d.take[c.id] = value or nil
  end
  d.list:SetData(d.plan.conflicts)
end

local function buildImporter()
  local d = FG.Dialogs.Create("ForeverGuidesGMImportBackup", 560, 560)
  W.SetText(d.title, "gm.imp.window")
  d.take = {}
  local hint = W.Text(d, { key = "gm.imp.hint", role = "ui", color = "textSecondary", wrap = true })
  hint:SetPoint("TOPLEFT", 16, -48)
  hint:SetPoint("RIGHT", -16, 0)
  d.input = W.TextArea(d, {
    height = 96,
    onChange = function()
      if d.parsed then
        clearPlan(d)
      end
    end,
  })
  d.input:SetPoint("TOPLEFT", 16, -80)
  d.input:SetPoint("RIGHT", -16, 0)
  d.preview = W.Text(d, { role = "ui", wrap = true })
  d.preview:SetPoint("TOPLEFT", 16, -190)
  d.preview:SetPoint("RIGHT", -16, 0)
  d.listHint = W.Text(d, { key = "gm.imp.listHint", role = "small", color = "textSecondary", wrap = true })
  d.listHint:SetPoint("TOPLEFT", 16, -312)
  d.listHint:SetPoint("RIGHT", -16, 0)
  d.list = PK.NewList(d, {
    rowHeight = ROW_HEIGHT,
    bind = function(c)
      local mine = not d.take[c.id]
      return {
        title = c.name .. ": " .. L["gm.imp.field." .. c.field],
        sub = string.format(L["gm.imp.conflict"], c.mine, c.theirs),
        wrapSub = true,
        badge = { text = L[mine and "gm.imp.keepMine" or "gm.imp.takeBackup"], color = mine and "accent2" or "warning" },
      }
    end,
    onClick = function(c)
      d.take[c.id] = (not d.take[c.id]) or nil
      d.list:SetData(d.plan.conflicts)
    end,
  })
  d.list.fgId = "gm-imp-list"
  d.list:SetPoint("TOPLEFT", 16, -352)
  d.list:SetSize(528, LIST_HEIGHT)
  d.allMine = W.Action(d, {
    label = "gm.imp.allMine",
    width = 130,
    height = 24,
    onClick = function()
      setAll(d, false)
    end,
  })
  d.allMine.fgId = "gm-imp-all-mine"
  d.allMine:SetPoint("BOTTOMLEFT", 16, 52)
  d.allTheirs = W.Action(d, {
    label = "gm.imp.allTheirs",
    width = 150,
    height = 24,
    onClick = function()
      setAll(d, true)
    end,
  })
  d.allTheirs.fgId = "gm-imp-all-theirs"
  d.allTheirs:SetPoint("LEFT", d.allMine, "RIGHT", 8, 0)
  d.apply = W.Action(d, {
    label = "gm.imp.apply",
    variant = "primary",
    width = 130,
    onClick = function()
      apply(d)
    end,
  })
  d.apply.fgId = "gm-imp-apply"
  d.apply:SetPoint("BOTTOMRIGHT", -16, 14)
  d.check = W.Button(d, {
    key = "gm.imp.check",
    width = 110,
    onClick = function()
      check(d)
    end,
  })
  d.check.fgId = "gm-imp-check"
  d.check:SetPoint("RIGHT", d.apply, "LEFT", -8, 0)
  close(d)
  return d
end

function X.OpenImport(ctx)
  importer = importer or buildImporter()
  importer.ctx = ctx
  importer.input:SetValue("")
  importer.preview:SetText("")
  clearPlan(importer)
  importer:Show()
end
