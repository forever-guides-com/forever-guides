-- The rule editor of the tab "Rules": name, ranks, conditions (kind, operator, value, a sentence that
-- explains the kind), action with a single choice of the target rank, protection and the limit per run. It
-- works on a copy of the rule; Save hands the copy to RulesLogic for repair, so a value is always clamped
-- there. What a rule still lacks is listed in red above the buttons. Nothing here talks to the game.
local _, gm = ...
if not gm.ext then
  return
end
local FG, RL, RUL, K = gm.FG, gm.RulesLogic, gm.RulesUiLogic, gm.RulesKit
local W, L = FG.W, FG.L

local ED = {}
gm.RuleEditor = ED

local ROW = { dropdown = 24, slider = 42, edit = 26, check = 22 }
local KIND_WIDTH, OP_WIDTH, FIELD_WIDTH = 200, 170, 260
local GAP = 8
local MAX_RANK = RL.MAX_RANK
-- Narrowest column of a group of rank boxes; a group of more than five boxes uses two columns from here.
local COL_MIN = 190
local GAP_RED = 6

local function contains(list, v)
  for _, x in ipairs(list or {}) do
    if x == v then
      return true
    end
  end
  return false
end

-- Places the shown boxes below y: one column, or two (more than five boxes and room for two columns) filled
-- row by row from the top left. x is the left edge. Answers the new y.
local function placeBoxes(boxes, owner, y, width, x)
  local shown = {}
  for _, box in ipairs(boxes) do
    if box:IsShown() then
      shown[#shown + 1] = box
    end
  end
  local cols = (#shown > 5 and width >= 2 * COL_MIN + GAP) and 2 or 1
  local colWidth = cols == 2 and math.floor((width - GAP) / 2) or width
  for n, box in ipairs(shown) do
    local col, row = (n - 1) % cols, math.floor((n - 1) / cols)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", owner, "TOPLEFT", (x or 0) + col * (colWidth + GAP), -(y + row * (ROW.check + 2)))
    box:SetSize(colWidth, ROW.check)
  end
  return y + math.ceil(#shown / cols) * (ROW.check + 2)
end

-- Hide and Place of a group of boxes.
local function finish(g)
  function g.Hide()
    for _, box in ipairs(g.boxes) do
      box:Hide()
    end
  end
  function g.Place(owner, y, width, x)
    return placeBoxes(g.boxes, owner, y, width, x)
  end
  return g
end

-- Checkbox per rank (index 1 to 9); the owner shows the first `lowest` of them.
local function rankGroup(parent, id, names, get, set)
  local g = { boxes = {} }
  for i = 1, MAX_RANK do
    local box = W.Checkbox(parent, {
      text = "",
      get = function()
        return contains(get(), i)
      end,
      set = function(on)
        local list = get()
        if on and not contains(list, i) then
          list[#list + 1] = i
          table.sort(list)
        elseif not on then
          for k = #list, 1, -1 do
            if list[k] == i then
              table.remove(list, k)
            end
          end
        end
        set(list)
      end,
    })
    box.fgId = id .. "-" .. i
    g.boxes[i] = box
  end
  function g.Refresh(lowest)
    local rankNames = names()
    for i, box in ipairs(g.boxes) do
      box:SetShown(i <= lowest)
      if i <= lowest then
        W.SetText(box.label, nil, rankNames[i] or string.format(L["gm.pv.rankN"], i))
        box.Refresh()
      end
    end
  end
  return finish(g)
end

-- A single choice in the look of checkboxes: one box per rank (1 to the lowest) and "rank of the main" last.
-- get() answers the chosen rank index, "main" or nil; select(value) is called for a click on another box.
local function radioGroup(parent, id, names, get, select)
  local g = { boxes = {} }
  for i = 1, MAX_RANK + 1 do
    local value = i <= MAX_RANK and i or "main"
    local box = W.Checkbox(parent, {
      text = "",
      get = function()
        return get() == value
      end,
      set = function(on)
        if on then
          select(value)
        end
      end,
    })
    box.fgId = id .. "-" .. value
    g.boxes[i] = box
  end
  function g.Refresh(lowest)
    local rankNames = names()
    for i, box in ipairs(g.boxes) do
      local show = i <= lowest or i == MAX_RANK + 1
      box:SetShown(show)
      if show then
        local text = i <= MAX_RANK and (rankNames[i] or string.format(L["gm.pv.rankN"], i)) or L["gm.rules.mainRank"]
        W.SetText(box.label, nil, text)
        box.Refresh()
      end
    end
  end
  return finish(g)
end

ED.RankGroup = rankGroup

local function dropdown(parent, id, width, options, get, set)
  local d = W.Dropdown(parent, { compact = true, width = width, options = options, get = get, set = set })
  d.fgId = id
  d.fgWidth = width
  return d
end

local function label(parent, key)
  return W.Text(parent, { key = key, role = "small", color = "textMuted" })
end

local function condRow(editor, i)
  local row = CreateFrame("Frame", nil, editor)
  row.fgId = "gm-cond-" .. i
  -- A row without a condition (hidden) answers an empty one, so its controls can paint.
  local function cond()
    return editor.draft.all[i] or {}
  end
  local kinds = {}
  for n, k in ipairs(RUL.KINDS) do
    kinds[n] = { value = k.id, key = "gm.cond." .. k.id }
  end
  local ops = {}
  row.kind = dropdown(row, "gm-cond-kind-" .. i, KIND_WIDTH, kinds, function()
    return cond().kind
  end, function(v)
    RUL.SetKind(cond(), v)
    editor.hooks.ctx.Refresh()
  end)
  row.op = dropdown(row, "gm-cond-op-" .. i, OP_WIDTH, ops, function()
    return cond().op
  end, function(v)
    RUL.SetOp(cond(), v)
    editor.hooks.ctx.Refresh()
  end)
  W.AttachTooltip(row.op, "gm.rules.opLabel", "gm.rules.op.tip")
  row.days = W.Slider(row, {
    key = "gm.rules.value.days",
    min = 0,
    max = 365,
    step = 1,
    get = function()
      return type(cond().value) == "number" and cond().value or 0
    end,
    set = function(v)
      cond().value = v
    end,
    format = function(v)
      return string.format(L["gm.rules.unit.days"], v)
    end,
  })
  row.days.fgId = "gm-cond-days-" .. i
  row.level = W.Slider(row, {
    key = "gm.rules.value.level",
    min = 1,
    max = RL.MAX_LEVEL,
    step = 1,
    get = function()
      return type(cond().value) == "number" and cond().value or 1
    end,
    set = function(v)
      cond().value = v
    end,
    format = function(v)
      return tostring(v)
    end,
  })
  row.level.fgId = "gm-cond-level-" .. i
  row.text = W.EditBox(row, {
    placeholder = "gm.rules.value.text",
    onChange = function(text)
      if row.textKind then
        cond().value = text
      end
    end,
  })
  row.text.fgId = "gm-cond-text-" .. i
  local fields = {}
  for n, f in ipairs(RUL.FIELDS) do
    fields[n] = { value = f, key = "gm.data." .. f }
  end
  row.field = dropdown(row, "gm-cond-field-" .. i, FIELD_WIDTH, fields, function()
    return cond().value
  end, function(v)
    cond().value = v
  end)
  row.remove = K.Button(row, "gm.rules.removeCond", function()
    table.remove(editor.draft.all, i)
    editor.hooks.ctx.Refresh()
  end, nil, "gm-cond-remove-" .. i)
  row.help = W.Text(row, { role = "micro", color = "textSecondary", wrap = true })
  row.ops = ops
  return row
end

-- hooks: ctx, names() -> index -> name, lowest() -> lowest rank index, save(draft) -> ok, why, onClose().
function ED.New(parent, hooks)
  local ed = CreateFrame("Frame", nil, parent)
  ed.fgId = "gm-editor"
  ed.hooks = hooks
  ed.draft = { all = {}, ranks = {}, action = { kind = "mark" }, protect = { useGlobal = true } }

  ed.name = W.EditBox(ed, {
    placeholder = "gm.rules.namePlaceholder",
    onChange = function(text)
      ed.draft.name = text
    end,
  })
  ed.name.fgId = "gm-editor-name"
  ed.name.edit:SetMaxLetters(RL.MAX_NAME)
  ed.nameLabel = label(ed, "gm.rules.name")
  ed.scopeLabel = label(ed, "gm.rules.scopeLabel")
  ed.scopeInfo = W.InfoButton(ed, "gm.rules.scopeLabel", "gm.rules.scopeLabel.help")
  ed.scope = rankGroup(ed, "gm-editor-rank", hooks.names, function()
    return ed.draft.ranks
  end, function()
    hooks.ctx.Refresh()
  end)
  ed.condLabel = label(ed, "gm.rules.condLabel")
  ed.condInfo = W.InfoButton(ed, "gm.rules.condLabel", "gm.rules.condLabel.help")
  ed.rows = {}
  for i = 1, RL.MAX_CONDITIONS do
    ed.rows[i] = condRow(ed, i)
  end
  ed.add = K.Button(ed, "gm.rules.addCond", function()
    if #ed.draft.all < RL.MAX_CONDITIONS then
      ed.draft.all[#ed.draft.all + 1] = RUL.NewCond("daysInRank")
    end
    hooks.ctx.Refresh()
  end, nil, "gm-editor-add")
  ed.actionLabel = label(ed, "gm.rules.actionLabel")
  local actions = {}
  for n, a in ipairs(RL.ACTIONS) do
    actions[n] = { value = a, key = "gm.rules.actName." .. a }
  end
  ed.action = dropdown(ed, "gm-editor-action", FIELD_WIDTH, actions, function()
    return ed.draft.action.kind
  end, function(v)
    ed.draft.action = { kind = v, public = true }
    hooks.ctx.Refresh()
  end)
  ed.targetLabel = label(ed, "gm.rules.targetLabel")
  ed.target = radioGroup(ed, "gm-editor-target", hooks.names, function()
    local a = ed.draft.action
    return a.rankFrom == "main" and "main" or a.rank
  end, function(v)
    local a = ed.draft.action
    if v == "main" then
      a.rankFrom, a.rank, a.rankName = "main", nil, nil
    else
      a.rankFrom, a.rank, a.rankName = nil, v, hooks.names()[v]
    end
    hooks.ctx.Refresh()
  end)
  ed.note = W.EditBox(ed, {
    placeholder = "gm.rules.notePlaceholder",
    onChange = function(text)
      if ed.draft.action.kind == "setNote" then
        ed.draft.action.note = text
      end
    end,
  })
  ed.note.fgId = "gm-editor-note"
  ed.note.edit:SetMaxLetters(RL.MAX_NOTE)
  ed.public = W.Checkbox(ed, {
    key = "gm.rules.notePublic",
    tooltip = "gm.rules.notePublic",
    tooltipText = "gm.rules.notePublic.tip",
    get = function()
      return ed.draft.action.public ~= false
    end,
    set = function(v)
      ed.draft.action.public = v
    end,
  })
  ed.public.fgId = "gm-editor-public"
  ed.tag = W.EditBox(ed, {
    placeholder = "gm.rules.tagPlaceholder",
    onChange = function(text)
      if ed.draft.action.kind == "mark" then
        ed.draft.action.tag = text
      end
    end,
  })
  ed.tag.fgId = "gm-editor-tag"
  ed.tag.edit:SetMaxLetters(RL.MAX_TAG)
  ed.protectLabel = label(ed, "gm.rules.protectLabel")
  ed.useGlobal = W.Checkbox(ed, {
    key = "gm.rules.useGlobal",
    tooltip = "gm.rules.useGlobal",
    tooltipText = "gm.rules.useGlobal.tip",
    get = function()
      return ed.draft.protect.useGlobal ~= false
    end,
    set = function(v)
      ed.draft.protect.useGlobal = v
    end,
  })
  ed.useGlobal.fgId = "gm-editor-global"
  ed.extraLabel = label(ed, "gm.rules.extraRanks")
  ed.extraInfo = W.InfoButton(ed, "gm.rules.extraRanks", "gm.rules.extraRanks.help")
  ed.extra = rankGroup(ed, "gm-editor-extra", hooks.names, function()
    ed.draft.protect.extraRanks = ed.draft.protect.extraRanks or {}
    return ed.draft.protect.extraRanks
  end, function() end)
  ed.perRun = W.Slider(ed, {
    key = "gm.rules.maxPerRun",
    min = 1,
    max = RL.MAX_PER_RUN,
    step = 1,
    get = function()
      return ed.draft.maxPerRun or RL.DEFAULT_PER_RUN
    end,
    set = function(v)
      ed.draft.maxPerRun = v
    end,
    format = function(v)
      return tostring(v)
    end,
  })
  ed.perRun.fgId = "gm-editor-perrun"
  W.AttachTooltip(ed.perRun, "gm.rules.maxPerRun", "gm.rules.maxPerRun.tip")
  -- What the rule still lacks, in red (RulesUiLogic.Gaps); empty and hidden for a complete rule.
  ed.gaps = W.Text(ed, { role = "small", color = "danger", wrap = true })
  ed.gaps.fgId = "gm-editor-gaps"
  ed.msg = W.Text(ed, { role = "small", color = "danger", wrap = true })
  ed.save = K.Button(ed, "gm.rules.save", function()
    ed:Save()
  end, "primary", "gm-editor-save")
  ed.cancel = K.Button(ed, "gm.rules.cancel", function()
    hooks.onClose()
  end, nil, "gm-editor-cancel")
  ed.buttons = K.Flow(ed, { ed.add, ed.save, ed.cancel })

  -- rule: a copy of a stored rule (RUL.DeepCopy) or a fresh draft.
  function ed:Load(rule)
    self.draft = rule
    rule.all, rule.ranks = rule.all or {}, rule.ranks or {}
    rule.action = rule.action or { kind = "mark" }
    rule.protect = rule.protect or { useGlobal = true }
    self.msg:SetText("")
    self.name.edit:SetText(type(rule.name) == "string" and rule.name or "")
  end

  function ed:Save()
    -- Saving confirms the ranks the player sees: the names stored with an older save are renewed.
    self.draft.rankNames, self.draft.action.rankName = nil, nil
    local ok, why = hooks.save(self.draft)
    if ok then
      hooks.onClose()
    else
      local key = "gm.rules.err." .. tostring(why)
      self.msg:SetText(L[key] ~= key and L[key] or key)
      hooks.ctx.Refresh()
    end
  end

  -- Brings the controls in line with the draft (after a load or a structural change).
  function ed:Update()
    local d, lowest = self.draft, hooks.lowest()
    self.scope.Refresh(lowest)
    self.extra.Refresh(lowest)
    local gaps = RUL.Gaps(d, hooks.ranks and hooks.ranks() or nil, L)
    self.gaps:SetText(RUL.GapBlock(gaps, L))
    self.gaps:SetShown(#gaps > 0)
    for i, row in ipairs(self.rows) do
      local c = d.all[i]
      row:SetShown(c ~= nil)
      if c then
        local spec = RUL.Kind(c.kind) or RUL.Kind("daysInRank")
        for k = #row.ops, 1, -1 do
          row.ops[k] = nil
        end
        for k, op in ipairs(spec.ops) do
          row.ops[k] = { value = op, key = "gm.op." .. op }
        end
        row.kind.Refresh()
        row.op.Refresh()
        local kind = spec.value
        local bare = spec.bare and spec.bare[c.op]
        row.valueKind = not bare and kind or nil
        row.days:SetShown(row.valueKind == "days")
        row.level:SetShown(row.valueKind == "level")
        row.text:SetShown(row.valueKind == "text" or row.valueKind == "tag")
        row.textKind = row.text:IsShown()
        row.field:SetShown(row.valueKind == "field")
        if row.days:IsShown() then
          row.days.Refresh()
        end
        if row.level:IsShown() then
          row.level.Refresh()
        end
        if row.text:IsShown() then
          row.text.edit:SetText(type(c.value) == "string" and c.value or "")
          row.text.edit:SetMaxLetters(
            kind == "tag" and RL.MAX_TAG or (c.kind == "ownNote" and RL.MAX_OWN_NOTE or RL.MAX_NOTE)
          )
        end
        if row.field:IsShown() then
          row.field.Refresh()
        end
        if row.valueKind == "ranks" then
          row.group = row.group
            or rankGroup(row, "gm-cond-rank-" .. i, hooks.names, function()
              if type(row.cond().value) ~= "table" then
                row.cond().value = {}
              end
              return row.cond().value
            end, function() end)
          row.cond = function()
            return d.all[i]
          end
          row.group.Refresh(lowest)
        elseif row.group then
          row.group.Hide()
        end
        W.SetText(row.help, "gm.cond." .. c.kind .. ".help")
      end
    end
    self.add:SetShown(#d.all < RL.MAX_CONDITIONS)
    local kind = d.action.kind
    self.targetLabel:SetShown(kind == "setRank")
    self.note:SetShown(kind == "setNote")
    self.public:SetShown(kind == "setNote")
    self.tag:SetShown(kind == "mark")
    if kind == "setRank" then
      self.target.Refresh(lowest)
      W.SetColor(self.targetLabel, (d.action.rank ~= nil or d.action.rankFrom == "main") and "textMuted" or "danger")
    else
      self.target.Hide()
    end
    self.action.Refresh()
    if kind == "setNote" and not self.note.edit:HasFocus() then
      self.note.edit:SetText(d.action.note or "")
      self.public.Refresh()
    end
    if kind == "mark" and not self.tag.edit:HasFocus() then
      self.tag.edit:SetText(d.action.tag or "")
    end
    self.useGlobal.Refresh()
    self.perRun.Refresh()
  end

  function ed:fgGridLayout(width)
    local y = 0
    local function place(item, h, w)
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      if w then
        item:SetWidth(math.min(w, width))
      end
      y = y + h + GAP
    end
    local function fs(item)
      item:SetWidth(width)
      place(item, math.ceil(item:GetStringHeight()))
    end
    -- A label with the round info button right behind its text.
    local function head(item, info)
      item:SetWidth(width - W.INFO_SIZE - 6)
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      info:ClearAllPoints()
      info:SetPoint("TOPLEFT", self, "TOPLEFT", math.min(math.ceil(item:GetStringWidth()) + 6, width - W.INFO_SIZE), -y)
      y = y + math.max(math.ceil(item:GetStringHeight()), W.INFO_SIZE) + GAP
    end
    fs(self.nameLabel)
    place(self.name, ROW.edit, math.min(FIELD_WIDTH, width))
    head(self.scopeLabel, self.scopeInfo)
    y = self.scope.Place(self, y, width) + GAP
    head(self.condLabel, self.condInfo)
    for _, row in ipairs(self.rows) do
      if row:IsShown() then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        row:SetWidth(width)
        local h = 0
        local function at(item, x, hh, w)
          item:ClearAllPoints()
          item:SetPoint("TOPLEFT", row, "TOPLEFT", x, -h)
          if w then
            item:SetWidth(math.min(w, width))
          end
          return hh
        end
        local sideBySide = KIND_WIDTH + GAP + OP_WIDTH <= width
        at(row.kind, 0, ROW.dropdown, KIND_WIDTH)
        if sideBySide then
          at(row.op, KIND_WIDTH + GAP, ROW.dropdown, OP_WIDTH)
          h = h + ROW.dropdown + GAP
        else
          h = h + ROW.dropdown + GAP
          at(row.op, 0, ROW.dropdown, OP_WIDTH)
          h = h + ROW.dropdown + GAP
        end
        if row.days:IsShown() then
          at(row.days, 0, ROW.slider, math.min(width, 300))
          h = h + ROW.slider + GAP
        end
        if row.level:IsShown() then
          at(row.level, 0, ROW.slider, math.min(width, 300))
          h = h + ROW.slider + GAP
        end
        if row.text:IsShown() then
          at(row.text, 0, ROW.edit, math.min(width, FIELD_WIDTH))
          h = h + ROW.edit + GAP
        end
        if row.field:IsShown() then
          at(row.field, 0, ROW.dropdown, FIELD_WIDTH)
          h = h + ROW.dropdown + GAP
        end
        if row.valueKind == "ranks" and row.group then
          h = row.group.Place(row, h, width)
          h = h + GAP
        end
        row.help:SetWidth(width)
        at(row.help, 0, 0)
        h = h + math.ceil(row.help:GetStringHeight()) + GAP
        row.remove:ClearAllPoints()
        row.remove:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -h)
        row.remove:SetSize(math.min(math.ceil(row.remove.label:GetStringWidth()) + 24, width), K.BUTTON_HEIGHT)
        h = h + K.BUTTON_HEIGHT + GAP
        row:SetHeight(h)
        y = y + h + GAP
      end
    end
    fs(self.actionLabel)
    place(self.action, ROW.dropdown, FIELD_WIDTH)
    if self.targetLabel:IsShown() then
      fs(self.targetLabel)
      y = self.target.Place(self, y, width) + GAP
    end
    if self.note:IsShown() then
      place(self.note, ROW.edit, math.min(FIELD_WIDTH, width))
      place(self.public, ROW.check, width)
    end
    if self.tag:IsShown() then
      place(self.tag, ROW.edit, math.min(FIELD_WIDTH, width))
    end
    fs(self.protectLabel)
    place(self.useGlobal, ROW.check, width)
    head(self.extraLabel, self.extraInfo)
    y = self.extra.Place(self, y, width) + GAP
    place(self.perRun, ROW.slider, math.min(width, 300))
    if self.gaps:IsShown() then
      -- Clear space above the list so it does not blend into the detail lines.
      y = y + GAP_RED
      fs(self.gaps)
      y = y + GAP_RED
    end
    self.msg:SetWidth(width)
    place(self.msg, math.ceil(self.msg:GetStringHeight()))
    self.buttons:SetWidth(width)
    place(self.buttons, self.buttons:fgGridLayout(width))
    y = math.max(y - GAP, 1)
    self:SetHeight(y)
    return y
  end
  return ed
end
