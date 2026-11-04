-- The preview of the tab "Rules": one row per member and rule from PlanLogic.Build, a tick for every
-- entry that may run (a removal is never ticked in advance), the reason for every entry that may not
-- ("Why not?") and the answers of the conditions behind each entry.
local _, gm = ...
if not gm.ext then
  return
end
local FG, RUL, K = gm.FG, gm.RulesUiLogic, gm.RulesKit
local W, L = FG.W, FG.L

local PV = {}
gm.PreviewList = PV

-- Rows that exist at once; the rest is counted in a line below the list.
PV.MAX_ROWS = 40
PV.FILTERS = { "ready", "later", "unknown", "conflict", "noRight", "blocked", "protected", "all" }
local ROW_GAP = 8
local CHECK_HEIGHT = 22
local DROPDOWN_WIDTH = 220
local MATURITY_COLOR = {
  ready = "success",
  later = "textSecondary",
  unknown = "warning",
  conflict = "warning",
  noRight = "danger",
  blocked = "danger",
  protected = "textMuted",
}

local function newRow(list)
  local row = CreateFrame("Frame", nil, list)
  row.fgId = "gm-pv-row"
  row.check = W.Checkbox(row, {
    text = "",
    get = function()
      return row.entry ~= nil and RUL.IsPicked(list.state, row.entry)
    end,
    set = function(v)
      RUL.SetPicked(list.state, row.entry, v)
      list.hooks.onChange()
    end,
  })
  row.check.fgId = "gm-pv-check"
  row.name = W.Text(row, { role = "ui", color = "textSecondary" })
  row.line = W.Text(row, { role = "small", color = "text", wrap = true })
  row.reason = W.Text(row, { role = "small", color = "textMuted", wrap = true })
  row.detail = W.Text(row, { role = "micro", color = "textSecondary", wrap = true })
  row.why = K.Button(row, "gm.rules.why", function()
    local id = RUL.EntryId(row.entry)
    list.state.expanded[id] = not list.state.expanded[id] or nil
    list.hooks.onChange()
  end, nil, "gm-pv-why")
  row.why.fgHeight = 24
  -- Marks of the store: the protection list and "skip today" (RulesUiLogic.Protect, SkipToday).
  local function mark(kind, id)
    local b = W.Action(row, {
      key = "gm.rules." .. kind,
      height = K.BUTTON_HEIGHT,
      tooltip = "gm.rules." .. kind,
      tooltipText = "gm.rules." .. kind .. ".tip",
      onClick = function()
        list.hooks.onMark(kind, row.entry)
      end,
    })
    b.fgId = id
    return b
  end
  row.protect = mark("protect", "gm-pv-protect")
  row.skip = mark("skipToday", "gm-pv-skip")
  return row
end

local function detailText(e, names)
  local lines = {}
  for _, a in ipairs(e.why or {}) do
    local mark = a.result == "yes" and "+ " or a.result == "no" and "- " or "? "
    lines[#lines + 1] = mark .. RUL.Explain(a, names, L)
  end
  return table.concat(lines, "\n")
end

-- hooks: onChange() runs after a tick or an expand; state: { pick, expanded, filter } shared with the tab.
function PV.New(parent, state, hooks)
  local list = CreateFrame("Frame", nil, parent)
  list.fgId = "gm-preview"
  list.state, list.hooks, list.rows, list.names = state, hooks, {}, {}
  list.head = W.Text(list, { role = "small", color = "textSecondary", wrap = true })
  list.filter = W.Dropdown(list, {
    key = "gm.rules.filter",
    width = DROPDOWN_WIDTH,
    options = (function()
      local o = {}
      for i, f in ipairs(PV.FILTERS) do
        o[i] = { value = f, key = "gm.rules.mat." .. f }
      end
      return o
    end)(),
    get = function()
      return state.filter
    end,
    set = function(v)
      state.filter = v
      hooks.onChange()
    end,
  })
  list.filter.fgId = "gm-pv-filter"
  -- The last mark and the way back from it (state.last = { kind, key, name }).
  list.fb = W.Text(list, { role = "small", color = "textSecondary", wrap = true })
  list.fb.fgId = "gm-pv-feedback"
  list.undo = K.Button(list, "gm.rules.markUndo", function()
    hooks.onUndo()
  end, nil, "gm-pv-undo")
  list.empty = W.Text(list, { key = "gm.rules.pvEmpty", role = "small", color = "textMuted", wrap = true })
  list.more = W.Text(list, { role = "small", color = "textMuted", wrap = true })

  -- plan: PlanLogic result, names: rank index -> name.
  function list:SetPlan(plan, names, dateText)
    self.plan, self.names, self.dateText = plan, names, dateText
    self.shown = plan and RUL.Filter(plan, state.filter) or {}
    local c = plan and plan.counts or {}
    self.head:SetText(
      string.format(
        L["gm.rules.pvHead"],
        c.ready or 0,
        (c.later or 0) + (c.unknown or 0) + (c.conflict or 0) + (c.noRight or 0) + (c.blocked or 0) + (c.protected or 0)
      )
    )
    self.filter.Refresh()
    local last = state.last
    self.fb:SetShown(last ~= nil)
    self.undo:SetShown(last ~= nil)
    if last then
      self.fb:SetText(string.format(L["gm.rules.mark." .. last.kind], last.name))
    end
    for i = 1, math.min(#self.shown, PV.MAX_ROWS) do
      local row = self.rows[i] or newRow(self)
      self.rows[i] = row
      local e = self.shown[i]
      row.entry = e
      local pickable = RUL.Pickable(e)
      W.SetText(row.check.label, nil, e.name)
      row.check.Refresh()
      row.check:SetShown(pickable)
      local markable = hooks.onMark ~= nil and e.maturity ~= "protected" and RUL.CanMark(e)
      row.protect:SetShown(markable)
      row.skip:SetShown(markable)
      row.name:SetText(e.name)
      row.name:SetShown(not pickable)
      row.line:SetText(RUL.ActionLine(e, names, L) .. " (" .. e.ruleName .. ")")
      local reason = RUL.ReasonLine(e, L, dateText)
      row.reason:SetText(reason)
      W.SetColor(row.reason, MATURITY_COLOR[e.maturity] or "textMuted")
      W.SetText(row.why.label, e.maturity == "ready" and "gm.rules.details" or "gm.rules.why")
      local open = state.expanded[RUL.EntryId(e)]
      row.detail:SetText(open and detailText(e, names) or "")
      row.detail:SetShown(open == true)
    end
    for i = #self.rows, 1, -1 do
      self.rows[i]:SetShown(i <= math.min(#self.shown, PV.MAX_ROWS))
    end
    self.empty:SetShown(#self.shown == 0)
    -- Why the list is empty: no rule takes part, no member fits, or only the filter hides them.
    local none = plan and #plan.rules == 0 and "gm.rules.pvNoRule"
      or plan and #plan.entries == 0 and "gm.rules.pvNoMatch"
    W.SetText(self.empty, none or "gm.rules.pvEmpty")
    local extra = #self.shown - PV.MAX_ROWS
    self.more:SetShown(extra > 0)
    if extra > 0 then
      self.more:SetText(string.format(L["gm.rules.pvMore"], extra))
    end
  end

  function list:fgGridLayout(width)
    local y = 0
    local function place(item, h, x)
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", self, "TOPLEFT", x or 0, -y)
      y = y + h
    end
    self.head:SetWidth(width)
    place(self.head, math.ceil(self.head:GetStringHeight()) + ROW_GAP)
    if self.fb:IsShown() then
      self.fb:SetWidth(width)
      place(self.fb, math.ceil(self.fb:GetStringHeight()) + 4)
      self.undo:SetSize(math.min(math.ceil(self.undo.label:GetStringWidth()) + 24, width), K.BUTTON_HEIGHT)
      place(self.undo, K.BUTTON_HEIGHT + ROW_GAP)
    end
    self.filter:SetWidth(DROPDOWN_WIDTH)
    place(self.filter, 46 + ROW_GAP)
    if self.empty:IsShown() then
      self.empty:SetWidth(width)
      place(self.empty, math.ceil(self.empty:GetStringHeight()) + ROW_GAP)
    end
    for _, row in ipairs(self.rows) do
      if row:IsShown() then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        row:SetWidth(width)
        local head = row.check:IsShown() and row.check or row.name
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        if head == row.check then
          row.check:SetSize(width, CHECK_HEIGHT)
        end
        local h = CHECK_HEIGHT
        for _, fs in ipairs({ row.line, row.reason }) do
          fs:SetWidth(width - 24)
          fs:ClearAllPoints()
          fs:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -h)
          h = h + math.ceil(fs:GetStringHeight()) + 2
        end
        local x, line = 24, h
        for _, b in ipairs({ row.why, row.protect, row.skip }) do
          if b:IsShown() then
            local w = math.min(math.ceil(b.label:GetStringWidth()) + 24, width - 24)
            if x > 24 and x + w > width then
              x, line = 24, line + 24 + 6
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", row, "TOPLEFT", x, -line)
            b:SetSize(w, 24)
            x = x + w + 6
          end
        end
        h = line + 24 + 2
        if row.detail:IsShown() then
          row.detail:SetWidth(width - 24)
          row.detail:ClearAllPoints()
          row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -h)
          h = h + math.ceil(row.detail:GetStringHeight()) + 2
        end
        row:SetHeight(h)
        y = y + h + ROW_GAP
      end
    end
    if self.more:IsShown() then
      self.more:SetWidth(width)
      place(self.more, math.ceil(self.more:GetStringHeight()) + ROW_GAP)
    end
    y = math.max(y - ROW_GAP, 1)
    self:SetHeight(y)
    return y
  end
  return list
end
