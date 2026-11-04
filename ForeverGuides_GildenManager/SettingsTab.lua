-- Tab "Settings": a row of page buttons and below it the cards of the chosen page (SettingsPages.lua),
-- one control per option (SettingsLogic.lua) with a short hint, an info button with the help of the
-- card and a reset per page. A change is written at once to the guild record (or the account
-- preferences) and never touches the guild itself.
local _, gm = ...
if not gm.ext then
  return
end
local FG, SL = gm.FG, gm.SettingsLogic
local W, L, GL = FG.W, FG.L, FG.GuildLogic

local ST = {}
gm.SettingsTab = ST

local MAX_WIDTH = 640
local GAP = 12
local PAD = 12
local DROPDOWN_WIDTH = 240
local NAV_HEIGHT = 26
local NAV_PAD = 24
local NAV_GAP = 6
local RESET_WIDTH = 200
local ROW = { bool = 24, int = 42, enum = 46, text = 46, column = 22 }

local function ctx()
  return { guild = gm.Guild(), prefs = gm.db.prefs }
end

-- Display text of a slider value: the unit, or the word a 0 stands for.
local function valueText(option, v)
  if v == 0 and option.zero == "off" then
    return L["common.off"]
  elseif v == 0 and option.zero == "client" then
    return L["gm.set.unit.client"]
  end
  return string.format(L["gm.set.unit." .. option.unit], v)
end

-- Cards -------------------------------------------------------------------------------------------

-- A card is a surface with a stack of rows; card:Measure(width) places them and answers the height.
local function newCard(body, def)
  local frame = W.Card(body)
  local card = { frame = frame, def = def, refresh = {} }
  local area = { content = frame }
  function area.GetHeight()
    return body:GetHeight()
  end
  function area.SetContentHeight(_, h)
    card.inner = h
  end
  card.stack = W.Stack(area, PAD)

  -- The gap behind the last shown row is not part of the card.
  local function lastGap()
    local items = card.stack.items
    for i = #items, 1, -1 do
      local entry = items[i]
      if entry.item:IsShown() then
        return entry.opts.gap or 10
      end
    end
    return 0
  end

  function card:Measure(width)
    frame:SetWidth(width)
    self.stack:Layout()
    local h = (self.inner or 0) - lastGap()
    frame:SetHeight(h)
    return h
  end
  return card
end

-- The first row: the title and the info button with the help of the card.
local function addHeading(card)
  local id = card.def.id
  local row = CreateFrame("Frame", nil, card.frame)
  local info = W.InfoButton(row, "gm.set.card." .. id, "gm.set.card." .. id .. ".help")
  info.fgId = "gm-set-help-" .. id
  info:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
  local title = W.Text(row, { key = "gm.set.card." .. id, role = "h3", family = "heading", color = "accent2" })
  title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
  function row:fgGridLayout(width)
    title:SetWidth(math.max(width - W.INFO_SIZE - 6, 1))
    return math.max(W.INFO_SIZE, math.ceil(title:GetStringHeight()) + 2)
  end
  card.stack:Add(row, { gap = 8 })
end

local function addText(card, key, color, gap)
  local fs = W.Text(card.frame, { key = key, role = "small", color = color or "textMuted", wrap = true })
  card.stack:Add(fs, { gap = gap or 8 })
  return fs
end

-- One option: its control, the hint below it and, for a risky choice, a warning line while it is on.
local function addOption(card, option, uiCtx)
  local id = option.id
  local function get()
    return SL.Get(ctx(), id)
  end
  local function set(v)
    SL.Set(ctx(), id, v)
    uiCtx.Refresh()
  end
  local control
  if option.kind == "bool" then
    control = W.Toggle(card.frame, {
      key = "gm.set." .. id,
      get = get,
      set = set,
      tooltip = "gm.set." .. id,
      tooltipText = "gm.set." .. id .. ".hint",
    })
  elseif option.kind == "int" then
    control = W.Slider(card.frame, {
      key = "gm.set." .. id,
      min = option.min,
      max = option.max,
      step = option.step,
      get = get,
      set = set,
      format = function(v)
        return valueText(option, v)
      end,
    })
  elseif option.kind == "enum" then
    local options = {}
    for i, value in ipairs(option.values) do
      options[i] = { value = value, key = "gm.set." .. id .. "." .. value }
    end
    control = W.Dropdown(card.frame, {
      key = "gm.set." .. id,
      width = DROPDOWN_WIDTH,
      options = options,
      get = get,
      set = set,
    })
  else
    control = CreateFrame("Frame", nil, card.frame)
    local label = W.Text(control, { key = "gm.set." .. id, role = "ui" })
    label:SetPoint("TOPLEFT")
    local field = W.EditBox(control, {
      onChange = function(text)
        SL.Set(ctx(), id, text)
      end,
      onEnter = function()
        uiCtx.Refresh()
      end,
    })
    field.edit:SetMaxLetters(option.maxLen)
    field:SetPoint("TOPLEFT", control, "TOPLEFT", 0, -20)
    field:SetPoint("TOPRIGHT", control, "TOPRIGHT", 0, -20)
    field.edit:HookScript("OnEditFocusLost", function()
      field.edit:SetText(get())
    end)
    control.edit = field.edit
    function control.Refresh()
      if not field.edit:HasFocus() then
        field.edit:SetText(get())
      end
    end
  end
  control.fgId = "gm-set-" .. id
  card.stack:Add(control, {
    height = ROW[option.kind],
    width = option.kind == "enum" and DROPDOWN_WIDTH or nil,
    gap = 2,
  })
  card.refresh[#card.refresh + 1] = control
  addText(card, "gm.set." .. id .. ".hint", nil, 8)
  if option.danger or option.risky then
    -- A frame around the line, so a test and the layout can address it.
    local warn = CreateFrame("Frame", nil, card.frame)
    warn.fgId = "gm-set-warn-" .. id
    local line = W.Text(warn, { key = "gm.set.warnActive", role = "small", color = "danger", wrap = true })
    line:SetPoint("TOPLEFT", warn, "TOPLEFT", 0, 0)
    function warn:fgGridLayout(width)
      line:SetWidth(width)
      return math.max(math.ceil(line:GetStringHeight()), 1)
    end
    function warn.Refresh()
      warn:SetShown(SL.IsRisky(id, get()))
    end
    card.stack:Add(warn, { gap = 8 })
    card.refresh[#card.refresh + 1] = warn
  end
end

-- Switches for the optional columns of the guild list (stored by the main add-on).
local function addColumns(card, uiCtx)
  for _, col in ipairs(card.def.columns) do
    local path = "settings.guildCols.guild." .. col.id
    local box = W.Checkbox(card.frame, {
      key = col.key,
      get = function()
        return GL.ColumnOn(FG.GuildKit.Columns("guild"), col.id)
      end,
      set = function(v)
        FG.Store.set(path, v == true)
        uiCtx.Refresh()
      end,
    })
    box.fgId = "gm-set-col-" .. col.id
    card.stack:Add(box, { height = ROW.column, gap = 6 })
    card.refresh[#card.refresh + 1] = box
  end
end

local function fill(card, uiCtx)
  local def = card.def
  addHeading(card)
  if def.build then
    def.build(card, { ctx = ctx, uiCtx = uiCtx, addText = addText, addOption = addOption })
    return
  end
  if def.note then
    addText(card, def.note, "textSecondary", 8)
  end
  for _, id in ipairs(def.options or {}) do
    addOption(card, SL.Option(id), uiCtx)
  end
  if def.columns then
    addColumns(card, uiCtx)
  end
  if def.fixed then
    addText(card, "gm.set.fixed.name", "textSecondary", 4)
    local count = W.Text(card.frame, { role = "small", color = "textSecondary", wrap = true })
    W.SetText(count, nil, string.format(L["gm.set.fixed.count"], SL.CONFIRM_COUNT))
    count.fgId = "gm-set-fixed-count"
    card.stack:Add(count, { gap = 8 })
  end
end

-- The page buttons: a row that wraps at the width of the tab, the chosen page is marked.
local function newNav(parent, pages, get, click)
  local f = CreateFrame("Frame", nil, parent)
  f.buttons = {}
  for _, page in ipairs(pages) do
    local b = W.Action(f, {
      key = "gm.set.page." .. page.id,
      width = 100,
      height = NAV_HEIGHT,
      onClick = function()
        click(page.id)
      end,
    })
    b.value = page.id
    f.buttons[#f.buttons + 1] = b
  end

  function f.Refresh()
    for _, b in ipairs(f.buttons) do
      b:SetSelected(b.value == get())
    end
  end

  function f:fgGridLayout(width)
    local x, y = 0, 0
    for _, b in ipairs(self.buttons) do
      local w = math.min(width, math.ceil(b.label:GetStringWidth()) + NAV_PAD)
      if x > 0 and x + w > width then
        x, y = 0, y + NAV_HEIGHT + NAV_GAP
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
      b:SetSize(w, NAV_HEIGHT)
      x = x + w + NAV_GAP
    end
    self:SetHeight(y + NAV_HEIGHT)
    return y + NAV_HEIGHT
  end
  return f
end

-- Tab ---------------------------------------------------------------------------------------------

local function build(parent, uiCtx)
  local body = CreateFrame("Frame", nil, parent)
  body.fgId = "gm-settings"
  local state = { page = gm.SettingsPages[1].id }
  body.state = state

  -- Why nothing is saved right now (no guild, data of a newer version).
  body.note = W.Text(body, { role = "small", color = "warning", wrap = true })

  body.nav = newNav(body, gm.SettingsPages, function()
    return state.page
  end, function(id)
    state.page = id
    uiCtx.Refresh()
  end)
  body.nav.fgId = "gm-set-pages"

  body.cards = {}
  for _, page in ipairs(gm.SettingsPages) do
    for _, def in ipairs(page.cards) do
      local card = newCard(body, def)
      card.page = page.id
      card.frame.fgId = "gm-set-card-" .. def.id
      fill(card, uiCtx)
      body.cards[#body.cards + 1] = card
    end
  end

  body.reset = W.Action(body, {
    key = "gm.set.reset",
    width = RESET_WIDTH,
    height = 26,
    onClick = function()
      FG.Dialogs.Confirm("gm.set.reset.title", "gm.set.reset.body", function()
        SL.Reset(ctx(), state.page)
        uiCtx.Refresh()
      end)
    end,
  })
  body.reset.fgId = "gm-set-reset"

  function body:fgGridLayout(width)
    local w = math.min(width, MAX_WIDTH)
    local y = 0
    if self.note:IsShown() then
      self.note:SetWidth(w)
      self.note:ClearAllPoints()
      self.note:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      local h = math.ceil(self.note:GetStringHeight())
      self.note:SetHeight(h)
      y = h + GAP
    end
    self.nav:SetWidth(w)
    self.nav:ClearAllPoints()
    self.nav:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    y = y + self.nav:fgGridLayout(w) + GAP
    for _, card in ipairs(self.cards) do
      if card.page == state.page then
        card.frame:ClearAllPoints()
        card.frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        y = y + card:Measure(w) + GAP
      end
    end
    if self.reset:IsShown() then
      self.reset:ClearAllPoints()
      self.reset:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      y = y + 26 + GAP
    end
    y = math.max(y - GAP, 1)
    self:SetHeight(y)
    return y
  end
  return body
end

local function update(_, body)
  local state = body.state
  local block = gm.WriteBlock()
  body.note:SetShown(block ~= nil)
  if block then
    W.SetText(body.note, block == "newer" and "gm.err.newer" or "gm.err.noGuild")
  end
  body.nav.Refresh()
  for _, card in ipairs(body.cards) do
    local on = card.page == state.page
    card.frame:SetShown(on)
    if on then
      for _, item in ipairs(card.refresh) do
        item.Refresh()
      end
    end
  end
  body.reset:SetShown(#SL.OfPage(state.page) > 0)
end

gm.ext.RegisterTab({ id = "settings", key = "gm.tab.settings", order = 90, build = build, onShow = update })
