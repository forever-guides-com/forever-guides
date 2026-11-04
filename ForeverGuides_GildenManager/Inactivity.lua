-- Tab "Inactive": members by last online time, threshold in days and rank filter. Read-only, a click
-- selects the member in the detail card of the guild page.
local _, gm = ...
if not gm.ext then
  return
end
local FG, IL, ML = gm.FG, gm.InactivityLogic, gm.MembersLogic
local W, L, K, GL = FG.W, FG.L, FG.PageKit, FG.GuildLogic

local ROW_HEIGHT = 44
local MAX_ROWS = 12
local GAP = 8
local SLIDER_WIDTH = 260
local SLIDER_HEIGHT = 42
local DROPDOWN_WIDTH = 170
local DROPDOWN_HEIGHT = 46
local MAKE_HEIGHT = 26

local function rowOf(m)
  local parts = {}
  if m.rankName ~= "" then
    parts[#parts + 1] = m.rankName
  end
  if m.level > 0 then
    parts[#parts + 1] = string.format(L["guild.level"], m.level)
  end
  local main = ML.MainOf(gm.Guild().members, m.key)
  if main then
    parts[#parts + 1] = string.format(L["gm.col.mainValue"], main)
  end
  return { title = m.name, sub = table.concat(parts, " · "), right = GL.LastOnlineText(m, L) }
end

local function build(parent, ctx)
  local body = CreateFrame("Frame", nil, parent)
  local state = { rank = "all", options = {}, rows = {} }
  body.state = state
  -- RulesKit is a later file of the add-on: looked up when the tab is built.
  local kit = gm.RulesKit
  body.head = kit and kit.Head(body, "gm-inactive-head", "gm.help.inactive", "gm.help.inactive.help")

  body.slider = W.Slider(body, {
    key = "gm.inactive.days",
    min = IL.MIN_DAYS,
    max = IL.MAX_DAYS,
    step = 1,
    get = function()
      return gm.Guild().settings.inactiveDays
    end,
    set = function(v)
      gm.Guild().settings.inactiveDays = IL.ClampDays(v)
      ctx.Refresh()
    end,
    format = function(v)
      return string.format(L["gm.inactive.daysValue"], v)
    end,
  })
  body.slider.fgId = "gm-inactive-days"
  body.rank = W.Dropdown(body, {
    key = "guild.rank",
    width = DROPDOWN_WIDTH,
    options = state.options,
    get = function()
      return state.rank
    end,
    set = function(v)
      state.rank = v
      ctx.Refresh()
    end,
  })
  body.rank.fgId = "gm-inactive-rank"
  body.count = W.Text(body, { role = "micro", color = "textMuted" })
  -- Hands the current threshold and rank filter to the rule assistant; nothing is created before its confirm.
  body.makeRule = W.Action(body, {
    key = "gm.inactive.makeRule",
    height = MAKE_HEIGHT,
    tooltip = "gm.inactive.makeRule",
    tooltipText = "gm.inactive.makeRule.tip",
    opens = true,
    onClick = function()
      local who = {}
      if state.rank ~= "all" then
        who[1] = state.rank
      else
        for _, r in ipairs(ctx.Roster().ranks) do
          if r.index >= 1 then
            who[#who + 1] = r.index
          end
        end
      end
      if gm.RuleWizard then
        gm.RuleWizard.Open({ what = "mark", who = who, days = gm.Guild().settings.inactiveDays }, ctx)
      end
    end,
  })
  body.makeRule.fgId = "gm-inactive-makerule"
  body.list = K.NewList(body, {
    rowHeight = ROW_HEIGHT,
    bind = function(m)
      local row = rowOf(m)
      row.selected = state.selected == m.key
      return row
    end,
    onClick = function(m)
      ctx.Select(m)
    end,
  })

  function body:fgGridLayout(width)
    local top = 0
    if self.head then
      self.head:ClearAllPoints()
      self.head:SetPoint("TOPLEFT", 0, 0)
      self.head:SetWidth(width)
      top = self.head:fgGridLayout(width) + GAP
    end
    local sliderWidth = math.min(SLIDER_WIDTH, width)
    self.slider:SetWidth(sliderWidth)
    self.slider:ClearAllPoints()
    self.slider:SetPoint("TOPLEFT", 0, -top)
    self.rank:SetWidth(DROPDOWN_WIDTH)
    self.rank:ClearAllPoints()
    local y
    if sliderWidth + GAP + DROPDOWN_WIDTH <= width then
      self.rank:SetPoint("TOPLEFT", sliderWidth + GAP, -top)
      y = top + DROPDOWN_HEIGHT
    else
      self.rank:SetPoint("TOPLEFT", 0, -(top + SLIDER_HEIGHT + GAP))
      y = top + SLIDER_HEIGHT + GAP + DROPDOWN_HEIGHT
    end
    y = y + GAP
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", 0, -y)
    y = y + self.count:GetStringHeight() + GAP
    self.makeRule:ClearAllPoints()
    self.makeRule:SetPoint("TOPLEFT", 0, -y)
    self.makeRule:SetSize(math.min(math.ceil(self.makeRule.label:GetStringWidth()) + 24, width), MAKE_HEIGHT)
    y = y + MAKE_HEIGHT + GAP
    local listHeight = K.scaledHeight(ROW_HEIGHT) * math.min(math.max(#state.rows, 1), MAX_ROWS)
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", 0, -y)
    self.list:SetSize(width, listHeight)
    self:SetHeight(y + listHeight)
    return y + listHeight
  end
  return body
end

-- Rank choices follow the roster; a rank that is gone falls back to "all".
local function syncRanks(body, ranks)
  local state, options = body.state, body.state.options
  for i = #options, 1, -1 do
    options[i] = nil
  end
  options[1] = { value = "all", key = "guild.rank.all" }
  local known = state.rank == "all"
  for _, r in ipairs(ranks) do
    options[#options + 1] = { value = r.index, text = r.name }
    known = known or r.index == state.rank
  end
  if not known then
    state.rank = "all"
  end
  body.rank.Refresh()
end

local function update(ctx, body)
  local state, snap = body.state, ctx.Roster()
  syncRanks(body, snap.ranks)
  body.slider.Refresh()
  state.rows = IL.List(snap.members, {
    days = gm.Guild().settings.inactiveDays,
    rank = state.rank ~= "all" and state.rank or nil,
  })
  local picked = ctx.Selected()
  state.selected = picked and picked.key
  local count = string.format(L["gm.inactive.count"], #state.rows, #snap.members)
  -- An empty list says why, not only "0".
  body.count:SetText(#state.rows == 0 and (count .. "\n" .. L["gm.inactive.empty"]) or count)
  body.list:SetData(state.rows)
end

gm.ext.RegisterTab({ id = "inactive", key = "gm.tab.inactive", order = 10, build = build, onShow = update })
