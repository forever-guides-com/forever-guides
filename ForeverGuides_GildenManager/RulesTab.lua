-- Tab "Rules" of the guild page: the list of rules (on and off, order, copy, delete), the editor, the
-- twelve templates with their parameters, the preview with a tick per member and the run (RunPanel).
-- A page row (W.Tabs) switches between Rules, Templates and "Check and run". The plan is always built again on
-- fresh data, nothing runs without a tick, a confirmation and a click, and the game is only touched
-- through Actions.StartRun. This file registers the tab and is loaded after the other files of it.
-- Also the assistant dialog (three questions) that makes a rule from a template: gm.RuleWizard.
local _, gm = ...
if not gm.ext then
  return
end
local FG, RL, RT, PL = gm.FG, gm.RulesLogic, gm.RuleTemplates, gm.PlanLogic
local RUL, K, SL, DL = gm.RulesUiLogic, gm.RulesKit, gm.SettingsLogic, gm.DatesLogic
local W, L, PN, GD = FG.W, FG.L, FG.PlayerName, FG.GuildData
if not (RUL and K and gm.PreviewList and gm.RunPanel and gm.RuleEditor) then
  return
end

local RT_UI = {}
gm.RulesTab = RT_UI

local PAGES = { "rules", "templates", "preview" }
local FIELD_WIDTH = 260
local GAP_RED = 6

local function guild()
  return gm.Guild()
end

local function sctx()
  return { guild = gm.Guild(), prefs = gm.db.prefs }
end

local function rules()
  return RUL.Repair(guild())
end

-- Position of the rule with the id in the list, nil for none.
local function ruleIndex(id)
  for i, r in ipairs(rules()) do
    if r.id == id then
      return i
    end
  end
  return nil
end

local function dateText(day)
  return DL.Format(day, gm.History.DateFormat())
end

-- Name of a rank from the guild settings of the client (1-based there), nil when it says nothing.
local function settingsRankName(index)
  local fn = rawget(_G, "GuildControlGetRankName")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, name = pcall(fn, index + 1)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

-- Ranks of the current roster: the list for RulesLogic, index -> name and the lowest index. The roster
-- only knows ranks with members, so a gap between two ranks gets its name from the guild settings.
local function ranksOf()
  local snap = GD.Get()
  local names, lowest = K.RankNames(snap)
  for r = 1, lowest do
    names[r] = names[r] or settingsRankName(r)
  end
  return snap.ranks or {}, names, lowest
end

-- Seconds the roster is old, nil when unknown.
local function rosterAge()
  local takenAt = GD.Get().takenAt
  local ok, tick = pcall(GetTime)
  return ok and type(takenAt) == "number" and tick - takenAt or nil
end

-- Input of the plan on the data of this moment: roster, store, rights, settings, the clock. only: the id of
-- the one rule to check (also when it is off).
local function inputNow(only)
  local today, now, offset = gm.History.Clock()
  local input = RUL.Input(GD.Get(), guild(), {
    today = today,
    now = now,
    offset = offset,
    meKey = PN.Key(PN.Self()),
    rights = FG.GuildExt.Rights(),
    caps = { setNote = gm.Caps.Get("setNote"), locked = gm.Caps.Locked() },
    plan = gm.Actions.PlanContext(),
    age = rosterAge(),
  })
  input.only = only
  return input
end

local function planNow(only)
  return PL.Build(guild().rules, inputNow(only))
end
-- Called by others without an argument: the plan of every active rule.
RT_UI.PlanNow = function()
  return planNow()
end

local function notify(text, kind)
  FG.Notify(text, kind or "info")
end

local function locked()
  local block = gm.WriteBlock()
  if block then
    notify(L[block == "newer" and "gm.err.newer" or "gm.err.noGuild"], "warning")
  end
  return block ~= nil
end

local function errorText(why)
  local key = "gm.rules.err." .. tostring(why)
  return L[key] ~= key and L[key] or tostring(why)
end

-- Way of the next step as the settings and the client say it now.
local function wayInfo()
  local choice = SL.Get(sctx(), "actionBackend")
  local way = gm.Backend.Resolve(choice, "promote")
  local dry = guild().settings.dryRun == true
  local text = gm.Backend.Locked() and L["gm.rules.way.locked"]
    or string.format(L["gm.rules.way"], L["gm.rules.choice." .. tostring(choice)], L["gm.rules.way." .. way])
  return {
    live = not dry,
    dry = L[dry and "gm.rules.dryOn" or "gm.rules.dryOff"],
    way = text,
  }
end

-- Rule list ---------------------------------------------------------------------------------------------

local function newRuleRow(list)
  local row = CreateFrame("Frame", nil, list)
  row.fgId = "gm-rule-row"
  row.enable = W.Checkbox(row, {
    text = "",
    get = function()
      local r = list.cleaned[row.index]
      return r ~= nil and r.enabled == true
    end,
    set = function(on)
      if locked() then
        return
      end
      local ok, why = RUL.SetEnabled(rules(), row.index, on, (ranksOf()))
      if not ok then
        notify(errorText(why), "warning")
      end
      list.hooks.refresh()
    end,
  })
  row.enable.fgId = "gm-rule-enable"
  row.line = W.Text(row, { role = "small", color = "textSecondary", wrap = true })
  row.warn = W.Text(row, { role = "small", color = "danger", wrap = true })
  local function button(key, id, fn)
    return K.Button(row, key, function()
      if locked() then
        return
      end
      fn(row.index)
      list.hooks.refresh()
    end, nil, id)
  end
  row.up = button("gm.rules.up", "gm-rule-up", function(i)
    RUL.Move(rules(), i, -1)
  end)
  row.down = button("gm.rules.down", "gm-rule-down", function(i)
    RUL.Move(rules(), i, 1)
  end)
  row.copy = button("gm.rules.copy", "gm-rule-copy", function(i)
    local ok, why = RUL.Duplicate(rules(), i, (ranksOf()))
    if not ok then
      notify(errorText(why), "warning")
    end
  end)
  row.edit = K.Button(row, "gm.rules.edit", function()
    list.hooks.edit(row.index)
  end, nil, "gm-rule-edit")
  row.delete = K.Button(row, "gm.rules.delete", function()
    FG.Dialogs.Confirm("gm.rules.delete.title", "gm.rules.delete.body", function()
      if not locked() then
        RUL.Delete(rules(), row.index)
        list.hooks.afterDelete(row.index)
        list.hooks.refresh()
      end
    end)
  end, "danger", "gm-rule-delete")
  row.flow = K.Flow(row, { row.up, row.down, row.copy, row.edit, row.delete })
  return row
end

local function newRuleList(parent, hooks)
  local list = CreateFrame("Frame", nil, parent)
  list.fgId = "gm-rule-list"
  list.hooks, list.rows, list.cleaned = hooks, {}, {}
  list.empty = W.Text(list, { key = "gm.rules.empty", role = "small", color = "textMuted", wrap = true })

  function list:Update()
    local raw = rules()
    local ranks, names = ranksOf()
    self.cleaned = {}
    for i, r in ipairs(raw) do
      local row = self.rows[i] or newRuleRow(self)
      self.rows[i] = row
      row.index = i
      local clean, issues = RL.CleanRule(r, ranks)
      self.cleaned[i] = clean or false
      local name = type(r.name) == "string" and r.name ~= "" and r.name or L["gm.rules.unnamed"]
      W.SetText(row.enable.label, nil, name)
      row.enable.Refresh()
      row.enable:SetShown(clean ~= nil)
      if clean then
        row.line:SetText(RUL.RuleLine(clean, names, L))
        row.warn:SetText(RUL.GapBlock(RUL.Gaps(r, ranks, L), L))
      else
        row.line:SetText(string.format(L["gm.rules.damaged"], name, errorText(issues)))
        row.warn:SetText("")
      end
      row.up:SetShown(i > 1)
      row.down:SetShown(i < #raw)
      row.copy:SetShown(clean ~= nil)
      row.edit:SetShown(clean ~= nil)
    end
    for i = #self.rows, 1, -1 do
      self.rows[i]:SetShown(i <= #raw)
    end
    self.empty:SetShown(#raw == 0)
  end

  function list:fgGridLayout(width)
    local y = 0
    if self.empty:IsShown() then
      self.empty:SetWidth(width)
      self.empty:ClearAllPoints()
      self.empty:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      y = math.ceil(self.empty:GetStringHeight()) + 8
    end
    for _, row in ipairs(self.rows) do
      if row:IsShown() then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        row:SetWidth(width)
        local h = 0
        local head = row.enable:IsShown() and row.enable or row.line
        if row.enable:IsShown() then
          row.enable:ClearAllPoints()
          row.enable:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
          row.enable:SetSize(width, 22)
          h = 24
        end
        row.line:SetWidth(width)
        row.line:ClearAllPoints()
        row.line:SetPoint("TOPLEFT", row, "TOPLEFT", head == row.enable and 24 or 0, -h)
        h = h + math.ceil(row.line:GetStringHeight()) + 2
        if row.warn:GetText() ~= "" then
          -- The red list of what is missing sits clear of the detail line above and the buttons below.
          h = h + GAP_RED
          row.warn:Show()
          row.warn:SetWidth(width)
          row.warn:ClearAllPoints()
          row.warn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -h)
          h = h + math.ceil(row.warn:GetStringHeight()) + GAP_RED
        else
          row.warn:Hide()
        end
        row.flow:ClearAllPoints()
        row.flow:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -h)
        row.flow:SetWidth(width)
        h = h + row.flow:fgGridLayout(width) + 4
        row:SetHeight(h)
        y = y + h + 12
      end
    end
    y = math.max(y - 12, 1)
    self:SetHeight(y)
    return y
  end
  return list
end

-- Assistant ---------------------------------------------------------------------------------------------

local WIZARD = {}
gm.RuleWizard = WIZARD
local wizard

local function buildWizard()
  local d = FG.Dialogs.Create("ForeverGuidesGMRuleWizard", 440, 560)
  d.answers = { who = {}, what = "mark", days = 14 }
  d.q1 = W.Text(d, { key = "gm.rules.wiz.who", role = "ui", color = "accent2" })
  d.q1:SetPoint("TOPLEFT", 16, -48)
  d.q1.fgId = "gm-wiz-who"
  d.group = gm.RuleEditor.RankGroup(d, "gm-wiz-rank", function()
    return (select(2, ranksOf()))
  end, function()
    return d.answers.who
  end, function() end)
  d.q2 = W.Text(d, { key = "gm.rules.wiz.what", role = "ui", color = "accent2" })
  d.q2.fgId = "gm-wiz-what"
  local goals = {}
  for i, g in ipairs(RUL.GOALS) do
    goals[i] = { value = g.id, key = "gm.rules.goal." .. g.id }
  end
  d.what = W.Dropdown(d, {
    compact = true,
    width = FIELD_WIDTH,
    options = goals,
    get = function()
      return d.answers.what
    end,
    set = function(v)
      d.answers.what = v
      d.answers.days = RUL.Goal(v).days
      d.days.Refresh()
    end,
  })
  d.what.fgId = "gm-wiz-goal"
  d.q3 = W.Text(d, { key = "gm.rules.wiz.when", role = "ui", color = "accent2" })
  d.q3.fgId = "gm-wiz-when"
  d.days = W.Slider(d, {
    key = "gm.rules.value.days",
    min = 1,
    max = 365,
    step = 1,
    get = function()
      return d.answers.days
    end,
    set = function(v)
      d.answers.days = v
    end,
    format = function(v)
      return string.format(L["gm.rules.unit.days"], v)
    end,
  })
  d.days.fgId = "gm-wiz-days"
  d.hint = W.Text(d, { key = "gm.rules.wiz.hint", role = "micro", color = "textSecondary", wrap = true })
  d.msg = W.Text(d, { role = "small", color = "danger", wrap = true })
  d.create = W.Action(d, {
    key = "gm.rules.wiz.create",
    variant = "primary",
    width = 150,
    onClick = function()
      d:Create()
    end,
  })
  d.create.fgId = "gm-wiz-create"
  d.create:SetPoint("BOTTOMRIGHT", -16, 14)
  d.cancel = W.Action(d, {
    label = "act.cancel",
    icon = "close",
    tooltip = "common.cancel",
    width = 110,
    onClick = function()
      d:Hide()
    end,
  })
  d.cancel:SetPoint("RIGHT", d.create, "LEFT", -8, 0)

  function d:Create()
    if locked() then
      return
    end
    local ranks, names, lowest = ranksOf()
    local n, why =
      RUL.AddFromAnswers(rules(), self.answers, { maxLevel = SL.MaxLevel(sctx()), lowestRank = lowest }, ranks, L)
    if not n then
      self.msg:SetText(errorText(why))
      return
    end
    self:Hide()
    notify(string.format(L["gm.rules.wiz.done"], n), "success")
    if self.ctx and self.ctx.Refresh then
      gm.ext.OpenTab("rules")
      self.ctx.Refresh()
    end
    return names
  end
  return d
end

-- prefill: { what = goal id, who = rank list, days }; ctx: the page context (for the refresh).
function WIZARD.Open(prefill, ctx)
  wizard = wizard or buildWizard()
  local d = wizard
  prefill = prefill or {}
  local goal = RUL.Goal(prefill.what) or RUL.Goal("mark")
  d.answers.what = goal.id
  d.answers.days = tonumber(prefill.days) or goal.days
  d.answers.who = {}
  for _, r in ipairs(prefill.who or {}) do
    d.answers.who[#d.answers.who + 1] = r
  end
  d.ctx = ctx
  d.msg:SetText("")
  local _, _, lowest = ranksOf()
  d.group.Refresh(lowest)
  d.what.Refresh()
  d.days.Refresh()
  local top = d.group.Place(d, 70, 408, 16)
  d.q2:ClearAllPoints()
  d.q2:SetPoint("TOPLEFT", 16, -(top + 8))
  d.what:ClearAllPoints()
  d.what:SetPoint("TOPLEFT", 16, -(top + 30))
  d.q3:ClearAllPoints()
  d.q3:SetPoint("TOPLEFT", 16, -(top + 66))
  d.days:ClearAllPoints()
  d.days:SetPoint("TOPLEFT", 16, -(top + 88))
  d.days:SetWidth(300)
  d.hint:ClearAllPoints()
  d.hint:SetPoint("TOPLEFT", 16, -(top + 140))
  d.hint:SetWidth(408)
  d.msg:ClearAllPoints()
  d.msg:SetPoint("TOPLEFT", 16, -(top + 176))
  d.msg:SetWidth(408)
  d:SetHeight(top + 240)
  d:Show()
  return d
end

-- Templates -----------------------------------------------------------------------------------------------

local function templateCard(body, tpl, uiCtx, state)
  local id = tpl.id
  local card = K.Card(body, "gm-tpl-" .. id, "gm.tpl." .. id .. ".title", "gm.tpl." .. id .. ".desc")
  K.Text(card, "gm.tpl." .. id .. ".desc", "textSecondary", 8)
  if tpl.warn then
    K.Text(card, "gm.tpl." .. id .. ".warn", "warning", 8)
  end
  local given = state.tpl[id] or {}
  state.tpl[id] = given
  local function opts()
    local _, _, lowest = ranksOf()
    return { maxLevel = SL.MaxLevel(sctx()), lowestRank = lowest }
  end
  local controls = {}
  for _, p in ipairs(tpl.params) do
    local key = "gm.tpl." .. id .. ".p." .. p.name
    local control, height
    local function value()
      return RT.Values(tpl, given, opts())[p.name]
    end
    if p.type == "rank" then
      local options = {}
      control = W.Dropdown(card.frame, {
        key = key,
        width = FIELD_WIDTH,
        options = options,
        get = function()
          return value() or 0
        end,
        set = function(v)
          given[p.name] = v ~= 0 and v or nil
        end,
      })
      control.options = options
      function control.Fill()
        local _, names, lowest = ranksOf()
        for i = #options, 1, -1 do
          options[i] = nil
        end
        options[1] = { value = 0, key = "gm.rules.chooseRank" }
        for r = 1, lowest do
          options[#options + 1] = { value = r, text = names[r] or string.format(L["gm.pv.rankN"], r) }
        end
      end
      height = 46
    elseif p.type == "ranks" then
      control = CreateFrame("Frame", nil, card.frame)
      local label = W.Text(control, { key = key, role = "ui", color = "textMuted" })
      label:SetPoint("TOPLEFT")
      control.group = gm.RuleEditor.RankGroup(control, "gm-tpl-" .. id .. "-" .. p.name, function()
        return (select(2, ranksOf()))
      end, function()
        given[p.name] = given[p.name] or {}
        return given[p.name]
      end, function() end)
      function control.Fill()
        local _, _, lowest = ranksOf()
        control.group.Refresh(lowest)
      end
      function control:fgGridLayout(width)
        local y = self.group.Place(self, 20, width)
        self:SetHeight(y)
        return y
      end
    elseif p.type == "int" then
      control = W.Slider(card.frame, {
        key = key,
        min = p.min,
        max = p.max,
        step = 1,
        get = value,
        set = function(v)
          given[p.name] = v
        end,
        format = function(v)
          return tostring(v)
        end,
      })
      height = 42
    else
      control = W.Toggle(card.frame, {
        key = key,
        get = value,
        set = function(v)
          given[p.name] = v
        end,
      })
      height = 24
    end
    control.fgId = "gm-tpl-" .. id .. "-" .. p.name
    card:Add(control, { height = height, gap = 8, width = p.type ~= "ranks" and FIELD_WIDTH or nil })
    controls[#controls + 1] = control
  end
  local create = K.Button(card.frame, "gm.rules.createDraft", function()
    if locked() then
      return
    end
    local ranks = ranksOf()
    local n, why = RUL.AddFromTemplate(rules(), id, given, opts(), ranks, L)
    if not n then
      notify(errorText(why), "warning")
      return
    end
    notify(string.format(L["gm.rules.draftMade"], n), "success")
    state.page = "rules"
    uiCtx.Refresh()
  end, "primary", "gm-tpl-" .. id .. "-create")
  card:Add(create, { width = 200, gap = 8, height = K.BUTTON_HEIGHT })
  card.controls = controls
  card.id = id
  return card
end

-- Tab -------------------------------------------------------------------------------------------------------

local function build(parent, uiCtx)
  local body = CreateFrame("Frame", nil, parent)
  body.fgId = "gm-rules"
  local state = { page = "rules", pick = {}, expanded = {}, filter = "ready", tpl = {} }
  body.state = state
  body.note = W.Text(body, { role = "small", color = "warning", wrap = true })
  -- One line per page: what to do, in order.
  body.guide = W.Text(body, { role = "small", color = "textSecondary", wrap = true })
  body.guide.fgId = "gm-rules-guide"

  local pages = {}
  for i, id in ipairs(PAGES) do
    pages[i] = { id = id, key = "gm.rules.page." .. id }
  end
  body.nav = W.Tabs(body, {
    tabs = pages,
    wrap = true,
    onSelect = function(id)
      if state.page ~= id then
        state.page = id
        uiCtx.Refresh()
      end
    end,
  })
  body.nav.fgId = "gm-rules-pages"

  -- Page "rules": list and editor.
  local listCard = K.Card(body, "gm-rules-list", "gm.rules.listTitle", "gm.rules.listTitle.help")
  K.Text(listCard, "gm.rules.listHint", "textSecondary", 8)
  local newBtn = K.Button(listCard.frame, "gm.rules.newFromTemplate", function()
    state.page = "templates"
    uiCtx.Refresh()
  end, "primary", "gm-rules-new")
  local newOwn = K.Button(listCard.frame, "gm.rules.newOwn", function()
    state.edit = { new = true }
    uiCtx.Refresh()
  end, nil, "gm-rules-own")
  local wizBtn = K.Button(listCard.frame, "gm.rules.assistant", function()
    WIZARD.Open({}, uiCtx)
  end, nil, "gm-rules-wizard", true)
  local flow = K.Flow(listCard.frame, { newBtn, newOwn, wizBtn })
  listCard:Add(flow, { gap = 10 })
  local list = newRuleList(listCard.frame, {
    refresh = function()
      uiCtx.Refresh()
    end,
    edit = function(i)
      state.edit = { index = i }
      state.editLoaded = nil
      uiCtx.Refresh()
    end,
    afterDelete = function(i)
      if state.edit and state.edit.index == i then
        state.edit = nil
      end
    end,
  })
  listCard:Add(list, { gap = 10 })

  local editorCard = K.Card(body, "gm-rules-editor", "gm.rules.editorTitle", "gm.rules.editorTitle.help")
  local editor = gm.RuleEditor.New(editorCard.frame, {
    ctx = uiCtx,
    names = function()
      return (select(2, ranksOf()))
    end,
    ranks = function()
      return (ranksOf())
    end,
    lowest = function()
      return (select(3, ranksOf()))
    end,
    save = function(draft)
      if locked() then
        return false, "locked"
      end
      local ok, why = RUL.Save(rules(), state.edit and state.edit.index, draft, (ranksOf()))
      return ok, why
    end,
    onClose = function()
      state.edit, state.editLoaded = nil, nil
      uiCtx.Refresh()
    end,
  })
  editorCard:Add(editor, { gap = 10 })

  -- Page "templates".
  local cards = {}
  for _, tpl in ipairs(RT.LIST) do
    cards[#cards + 1] = templateCard(body, tpl, uiCtx, state)
  end

  -- Page "preview": step 1 (pick a rule, check, tick), the data, step 2 (ready list and run).
  local pvCard = K.Card(body, "gm-rules-preview", "gm.rules.pvTitle", "gm.rules.pvTitle.help")
  K.Text(pvCard, "gm.rules.pvHint", "textSecondary", 8)
  local pickOptions = {}
  local pick = W.Dropdown(pvCard.frame, {
    key = "gm.rules.pickRule",
    width = FIELD_WIDTH,
    options = pickOptions,
    get = function()
      return state.rule or "active"
    end,
    set = function(v)
      state.rule, state.pick = v, {}
      uiCtx.Refresh()
    end,
  })
  pick.fgId = "gm-rules-pick"
  pvCard:Add(pick, { height = 46, gap = 8, width = FIELD_WIDTH })
  local gaps = K.Text(pvCard, nil, "danger", 8)
  gaps.fgId = "gm-rules-gaps"
  local offNote = K.Text(pvCard, "gm.rules.pvOff", "textSecondary", 8)
  local preview = gm.PreviewList.New(pvCard.frame, state, {
    onChange = function()
      uiCtx.Refresh()
    end,
    -- Protection list or "skip today" for one member, undone by the line above the list.
    onMark = function(kind, entry)
      if locked() then
        return
      end
      local ok, why
      if kind == "protect" then
        ok, why = RUL.Protect(guild(), entry)
      else
        ok, why = RUL.SkipToday(guild(), entry, (gm.History.Clock()))
      end
      if not ok then
        notify(L["gm.rules.markErr." .. why], "warning")
        return
      end
      state.last = { kind = kind, key = entry.key, name = entry.name, before = why }
      notify(string.format(L["gm.rules.mark." .. kind], entry.name), "success")
      uiCtx.Refresh()
    end,
    onUndo = function()
      local last = state.last
      if not last or locked() then
        return
      end
      if last.kind == "protect" then
        RUL.Unprotect(guild(), last.key)
      else
        RUL.Unskip(guild(), last.key, last.before)
      end
      state.last = nil
      notify(string.format(L["gm.rules.markUndone"], last.name), "info")
      uiCtx.Refresh()
    end,
  })
  pvCard:Add(preview, { gap = 10 })
  local function runBtn(card, key, id, fn, variant, opens)
    return K.Button(card.frame, key, fn, variant, id, opens)
  end
  local refreshBtn = runBtn(pvCard, "gm.rules.refresh", "gm-rules-refresh", function()
    GD.Request()
    uiCtx.Refresh()
  end)
  local allBtn = runBtn(pvCard, "gm.rules.pickAll", "gm-rules-all", function()
    if preview.plan then
      RUL.PickAll(state, preview.plan)
    end
    uiCtx.Refresh()
  end)
  local noneBtn = runBtn(pvCard, "gm.rules.pickNone", "gm-rules-none", function()
    if preview.plan then
      RUL.PickNone(state, preview.plan)
    end
    uiCtx.Refresh()
  end)
  -- A rule that is off is switched on here after the check.
  local enableBtn = runBtn(pvCard, "gm.rules.enableRule", "gm-rules-enable", function()
    if locked() then
      return
    end
    local i = ruleIndex(state.rule)
    if i then
      local ok, why = RUL.SetEnabled(rules(), i, true, (ranksOf()))
      if not ok then
        notify(errorText(why), "warning")
      end
    end
    uiCtx.Refresh()
  end, "primary")
  pvCard:Add(K.Flow(pvCard.frame, { refreshBtn, allBtn, noneBtn, enableBtn }), { gap = 10 })

  -- The data the rules by time stand on.
  local dataCard = K.Card(body, "gm-rules-data", "gm.rules.dataTitle", "gm.rules.dataTitle.help")
  local dataLine = K.Text(dataCard, nil, "text", 6)
  dataLine.fgId = "gm-rules-data-line"
  local dataSince = K.Text(dataCard, nil, "textSecondary", 8)
  local dataGaps = K.Text(dataCard, nil, "danger", 6)
  dataGaps.fgId = "gm-rules-data-gaps"
  local dataNames = K.Text(dataCard, nil, "textSecondary", 8)
  local dataOk = K.Text(dataCard, "gm.rules.data.ok", "success", 8)
  local enterBtn = runBtn(dataCard, "gm.rules.data.enter", "gm-rules-data-enter", function()
    if gm.JoinDialog then
      gm.JoinDialog.OpenImport(uiCtx)
    end
  end, nil, true)
  W.AttachTooltip(enterBtn, "gm.rules.data.enter", "gm.rules.data.enter.tip")
  local notesBtn = runBtn(dataCard, "gm.rules.data.notes", "gm-rules-data-notes", function()
    if locked() then
      return
    end
    local n = gm.History.ReadNotes()
    notify(n and n > 0 and string.format(L["gm.rules.data.notesDone"], n) or L["gm.rules.data.notesNone"], "info")
    uiCtx.Refresh()
  end)
  W.AttachTooltip(notesBtn, "gm.rules.data.notes", "gm.rules.data.notes.tip")
  dataCard:Add(K.Flow(dataCard.frame, { enterBtn, notesBtn }), { gap = 10 })

  -- Step 2: what still stops the run, the mode, the way and the button.
  local execCard = K.Card(body, "gm-rules-exec", "gm.rules.execTitle", "gm.rules.execTitle.help")
  local checklist = K.Text(execCard, nil, "danger", 8, "ui")
  checklist.fgId = "gm-rules-checklist"
  local summary = K.Text(execCard, nil, "text", 8, "ui")
  summary.fgId = "gm-rules-summary"
  local dry = W.Toggle(execCard.frame, {
    key = "gm.dry.option",
    get = function()
      return guild().settings.dryRun == true
    end,
    set = function(v)
      if not locked() then
        SL.Set(sctx(), "dryRun", v)
      end
      uiCtx.Refresh()
    end,
    tooltip = "gm.dry.option",
    tooltipText = "gm.dry.tip",
  })
  dry.fgId = "gm-rules-dry"
  execCard:Add(dry, { height = 24, gap = 6, width = FIELD_WIDTH })
  local way = K.Text(execCard, nil, "textSecondary", 8)
  way.fgId = "gm-rules-way"
  local runReason = ""
  local runButton
  -- The confirmation before every run, also a dry one: what happens, to whom, how.
  runButton = runBtn(execCard, "gm.rules.runNow", "gm-rules-run", function()
    local missing, steps, marks = body.readiness()
    if #missing > 0 or locked() then
      return
    end
    local info = wayInfo()
    local lines = RUL.ConfirmLines(steps, marks, {
      live = info.live,
      way = info.way,
      pause = SL.Get(sctx(), "pauseSec"),
      undoDays = SL.Get(sctx(), "undoDays"),
    }, L)
    local keep = state.rule ~= "active" and state.rule or nil
    FG.Dialogs.Confirm("gm.rules.cf.title", nil, function()
      if locked() then
        return
      end
      if #marks > 0 then
        notify(string.format(L["gm.rules.marks.done"], RUL.ApplyMarks(guild(), marks)), "success")
      end
      if #steps > 0 then
        -- The run checks every step on a fresh plan of the same rule choice.
        body.run:Start(steps, function()
          return planNow(keep)
        end)
      end
      uiCtx.Refresh()
    end, nil, { text = table.concat(lines, "\n") })
  end, "primary")
  runButton:HookScript("OnEnter", function(self)
    FG.ShowTooltip(self, L["gm.rules.runNow"], runReason ~= "" and runReason or L["gm.rules.runNow.tip"])
  end)
  runButton:HookScript("OnLeave", FG.HideTooltip)
  execCard:Add(K.Flow(execCard.frame, { runButton }), { gap = 10 })

  local runCard = K.Card(body, "gm-rules-runcard", "gm.rules.runTitle", "gm.rules.runTitle.help")
  body.run = gm.RunPanel.New(runCard.frame, {
    ctx = uiCtx,
    names = function()
      return (select(2, ranksOf()))
    end,
    info = wayInfo,
    onEnd = function()
      uiCtx.Refresh()
    end,
  })
  runCard:Add(body.run, { gap = 10 })

  -- What stops a run right now: the texts (empty list: ready) and the ticked steps and marks.
  function body.readiness()
    local plan = preview.plan
    if not plan then
      return { L["gm.rules.chk.rule"] }, {}, {}
    end
    local steps, marks = RUL.Chosen(state, plan)
    local rights, choice = FG.GuildExt.Rights(), SL.Get(sctx(), "actionBackend")
    local noRight, noWay = false, false
    for _, e in ipairs(steps) do
      local step = gm.RunLogic.Step(e)
      local field = step and gm.ActionsLogic.RIGHT[step.action]
      if not step or not gm.Backend.Available(choice, step.action) then
        noWay = true
      elseif field and rights[field] ~= true then
        noRight = true
      end
    end
    local ok, fighting = pcall(InCombatLockdown)
    local age = rosterAge()
    local only = state.rule ~= "active" and state.rule or nil
    local raw = only and rules()[ruleIndex(only) or 0]
    local missing = RUL.Readiness({
      rules = #plan.rules,
      open = raw and RUL.Gaps(raw, (ranksOf()), L) or {},
      steps = #steps,
      marks = #marks,
      noRight = noRight,
      noWay = noWay,
      combat = ok and fighting == true,
      stale = age ~= nil and age > PL.MAX_ROSTER_AGE,
    }, L)
    return missing, steps, marks
  end

  body.pages = {
    rules = { listCard, editorCard },
    templates = cards,
    preview = { pvCard, dataCard, execCard, runCard },
  }
  body.parts = {
    list = list,
    editor = editor,
    editorCard = editorCard,
    runCard = runCard,
    execCard = execCard,
    preview = preview,
    summary = summary,
    way = way,
    runButton = runButton,
    dry = dry,
    pick = pick,
    pickOptions = pickOptions,
    gaps = gaps,
    offNote = offNote,
    enableBtn = enableBtn,
    dataLine = dataLine,
    dataSince = dataSince,
    dataGaps = dataGaps,
    dataNames = dataNames,
    dataOk = dataOk,
    checklist = checklist,
    setReason = function(text)
      runReason = text
    end,
  }

  function body:fgGridLayout(width)
    local w = math.min(width, K.MAX_WIDTH)
    local y = 0
    if self.note:IsShown() then
      self.note:SetWidth(w)
      self.note:ClearAllPoints()
      self.note:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      local h = math.ceil(self.note:GetStringHeight())
      y = h + K.GAP
    end
    self.nav:SetWidth(w)
    self.nav:ClearAllPoints()
    self.nav:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    y = y + self.nav:fgGridLayout(w) + 8
    self.guide:SetWidth(w)
    self.guide:ClearAllPoints()
    self.guide:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    y = y + math.ceil(self.guide:GetStringHeight()) + K.GAP
    for _, card in ipairs(self.pages[state.page]) do
      if card.frame:IsShown() then
        card.frame:ClearAllPoints()
        card.frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        y = y + card:Measure(w) + K.GAP
      end
    end
    y = math.max(y - K.GAP, 1)
    self:SetHeight(y)
    return y
  end
  return body
end

local function summaryLine(steps, marks)
  local c = RUL.Counts(steps)
  return string.format(L["gm.rules.summary"], c.promote + c.setRank, c.demote, c.remove, c.setNote, #marks)
end

-- Asks the tab to show a page (one of PAGES) the next time it is shown; open the tab afterwards.
function RT_UI.OpenPage(id)
  for _, page in ipairs(PAGES) do
    if page == id then
      RT_UI.wanted = id
      return true
    end
  end
  return false
end

local function update(_, body)
  local state, parts = body.state, body.parts
  if RT_UI.wanted then
    state.page, RT_UI.wanted = RT_UI.wanted, nil
  end
  local block = gm.WriteBlock()
  body.note:SetShown(block ~= nil)
  if block then
    W.SetText(body.note, block == "newer" and "gm.err.newer" or "gm.err.noGuild")
  end
  body.nav:Select(state.page)
  W.SetText(body.guide, "gm.rules.guide." .. state.page)
  RUL.Repair(guild())
  local _, names, lowest = ranksOf()
  for page, cards in pairs(body.pages) do
    for _, card in ipairs(cards) do
      card.frame:SetShown(page == state.page)
    end
  end
  if state.page == "rules" then
    parts.list:Update()
    parts.editorCard.frame:SetShown(state.edit ~= nil)
    if state.edit then
      if not state.editLoaded then
        local raw = state.edit.index and rules()[state.edit.index]
        if state.edit.index and type(raw) ~= "table" then
          state.edit = nil
        else
          parts.editor:Load(raw and RUL.DeepCopy(raw) or {
            name = "",
            enabled = false,
            ranks = {},
            all = { RUL.NewCond("daysInRank") },
            action = { kind = "mark", tag = "inactive" },
            protect = { useGlobal = true },
            maxPerRun = RL.DEFAULT_PER_RUN,
          })
          state.editLoaded = true
        end
      end
      if state.edit then
        parts.editor:Update()
      else
        parts.editorCard.frame:Hide()
      end
    end
  elseif state.page == "templates" then
    for _, card in ipairs(body.pages.templates) do
      for _, control in ipairs(card.controls) do
        if control.Fill then
          control.Fill()
        end
        if control.Refresh then
          control.Refresh()
        end
      end
    end
  else
    local ranksList = ranksOf()
    -- A roster that is too old blocks every entry: ask for a fresh one (the call is throttled).
    local age = rosterAge()
    if age and age > PL.MAX_ROSTER_AGE then
      GD.Request()
    end
    local choices = RUL.RuleChoices(rules(), ranksList, L)
    for i = #parts.pickOptions, 1, -1 do
      parts.pickOptions[i] = nil
    end
    local known = false
    for i, c in ipairs(choices) do
      parts.pickOptions[i] = c
      known = known or c.value == (state.rule or "active")
    end
    if not known then
      state.rule = "active"
    end
    parts.pick.Refresh()
    local only = state.rule ~= "active" and state.rule or nil
    local input = inputNow(only)
    local plan = PL.Build(guild().rules, input)
    parts.preview:SetPlan(plan, names, dateText)
    -- The rule that is checked: what it lacks (red) or the hint that it is off.
    local raw = only and rules()[ruleIndex(only) or 0]
    local ruleGaps = raw and RUL.Gaps(raw, ranksList, L) or {}
    local clean = raw and RL.CleanRule(raw, ranksList)
    parts.gaps:SetText(RUL.GapBlock(ruleGaps, L))
    parts.gaps:SetShown(#ruleGaps > 0)
    local off = clean ~= nil and clean ~= false and not clean.enabled and #ruleGaps == 0
    parts.offNote:SetShown(off)
    parts.enableBtn:SetShown(off)
    -- The data behind rules by time.
    local data = RUL.DataSituation(input.members, input.today, clean and clean.ranks or nil)
    parts.dataLine:SetText(string.format(L["gm.rules.data.known"], data.total, data.known, data.exact, data.atLeast))
    local first = guild().firstScanDay
    parts.dataSince:SetText(
      type(first) == "number" and first > 0 and string.format(L["gm.rules.data.since"], dateText(first))
        or L["gm.rules.data.noScan"]
    )
    local lack = #data.unknown > 0
    parts.dataGaps:SetShown(lack)
    parts.dataNames:SetShown(lack)
    parts.dataOk:SetShown(not lack and data.total > 0)
    if lack then
      parts.dataGaps:SetText(RUL.GapBlock({
        L["gm.rules.data.lack"],
        string.format(L["gm.rules.data.unknown"], #data.unknown),
      }, L))
      parts.dataNames:SetText(RUL.NameList(data.unknown, 10, L))
    end
    -- Step 2.
    local missing, steps, marks = body.readiness()
    local ready = #missing == 0
    if ready then
      parts.checklist:SetText(L["gm.rules.ready.all"])
      W.SetColor(parts.checklist, "success")
    else
      parts.checklist:SetText(RUL.GapBlock(missing, L))
      W.SetColor(parts.checklist, "danger")
    end
    parts.setReason(ready and "" or table.concat(missing, "\n"))
    parts.summary:SetText(summaryLine(steps, marks))
    parts.way:SetText(wayInfo().way)
    parts.dry.Refresh()
    parts.runButton:SetEnabled(ready)
    parts.execCard.frame:SetShown(not body.run:Active())
    parts.runCard.frame:SetShown(body.run:Active())
    if body.run:Active() then
      body.run:Refresh()
    end
  end
  return lowest
end

gm.ext.RegisterTab({ id = "rules", key = "gm.tab.rules", order = 20, build = build, onShow = update })
