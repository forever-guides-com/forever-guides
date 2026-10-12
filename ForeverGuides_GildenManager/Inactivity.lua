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

local function rowOf(m)
  local parts = {}
  if m.rankName ~= "" then
    parts[#parts + 1] = m.rankName
  end
  if m.level > 0 then
    parts[#parts + 1] = string.format(L["guild.level"], m.level)
  end
  local main = ML.MainOf(gm.db.members, m.key)
  if main then
    parts[#parts + 1] = string.format(L["gm.col.mainValue"], main)
  end
  return { title = m.name, sub = table.concat(parts, " · "), right = GL.LastOnlineText(m, L) }
end

local function build(parent, ctx)
  local body = CreateFrame("Frame", nil, parent)
  local state = { rank = "all", options = {}, rows = {} }
  body.state = state

  body.slider = W.Slider(body, {
    key = "gm.inactive.days",
    min = IL.MIN_DAYS,
    max = IL.MAX_DAYS,
    step = 1,
    get = function()
      return gm.db.inactiveDays
    end,
    set = function(v)
      gm.db.inactiveDays = IL.ClampDays(v)
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
    local sliderWidth = math.min(SLIDER_WIDTH, width)
    self.slider:SetWidth(sliderWidth)
    self.slider:ClearAllPoints()
    self.slider:SetPoint("TOPLEFT", 0, 0)
    self.rank:SetWidth(DROPDOWN_WIDTH)
    self.rank:ClearAllPoints()
    local y
    if sliderWidth + GAP + DROPDOWN_WIDTH <= width then
      self.rank:SetPoint("TOPLEFT", sliderWidth + GAP, 0)
      y = DROPDOWN_HEIGHT
    else
      self.rank:SetPoint("TOPLEFT", 0, -(SLIDER_HEIGHT + GAP))
      y = SLIDER_HEIGHT + GAP + DROPDOWN_HEIGHT
    end
    y = y + GAP
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", 0, -y)
    y = y + self.count:GetStringHeight() + GAP
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
    days = gm.db.inactiveDays,
    rank = state.rank ~= "all" and state.rank or nil,
  })
  local picked = ctx.Selected()
  state.selected = picked and picked.key
  body.count:SetText(string.format(L["gm.inactive.count"], #state.rows, #snap.members))
  body.list:SetData(state.rows)
end

gm.ext.RegisterTab({ id = "inactive", key = "gm.tab.inactive", order = 10, build = build, onShow = update })
