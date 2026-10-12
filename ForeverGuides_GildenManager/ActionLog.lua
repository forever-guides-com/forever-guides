-- Tab "Log": the local log of the guild actions done with this add-on (read only, search, clear
-- after a confirmation) and the dry run switch of the actions.
local _, gm = ...
if not gm.ext then
  return
end
local FG, AL = gm.FG, gm.ActionsLogic
local W, L, K = FG.W, FG.L, FG.PageKit

local ROW_HEIGHT = 44
local MAX_ROWS = 12
local GAP = 8
local CHECKBOX_HEIGHT = 22
local SEARCH_HEIGHT = 26
local CLEAR_WIDTH = 110
local MIN_SEARCH = 120

local function label(action)
  return L["gm.act." .. action]
end

local function stamp(t)
  local ok, text = pcall(date, "%Y-%m-%d %H:%M", t)
  return ok and text or "?"
end

local function detail(e)
  local parts = label(e.action)
  if e.action == "remove" then
    return e.old ~= "" and parts .. ": " .. e.old or parts
  end
  local function shown(s)
    return s ~= "" and s or L["gm.pv.empty"]
  end
  return string.format("%s: %s > %s", parts, shown(e.old), shown(e.new))
end

local function build(parent, ctx)
  local body = CreateFrame("Frame", nil, parent)
  local state = { search = "", rows = {} }
  body.state = state

  body.dry = W.Checkbox(body, {
    key = "gm.dry.option",
    tooltip = "gm.dry.option",
    tooltipText = "gm.dry.tip",
    get = function()
      return gm.db.dryRun
    end,
    set = function(v)
      gm.db.dryRun = v == true
    end,
  })
  body.dry.fgId = "gm-log-dry"
  body.search = W.EditBox(body, {
    placeholder = "guild.search",
    clear = true,
    onChange = function(text)
      state.search = text
      ctx.Refresh()
    end,
  })
  body.search.fgId = "gm-log-search"
  body.clear = W.Action(body, {
    label = "act.clear",
    icon = "trash",
    tooltip = "gm.log.clear",
    width = CLEAR_WIDTH,
    onClick = function()
      if #gm.db.log == 0 then
        return
      end
      FG.Dialogs.Confirm("gm.log.clear", "gm.log.clearAsk", function()
        gm.db.log = {}
        ctx.Refresh()
      end)
    end,
  })
  body.clear.fgId = "gm-log-clear"
  body.count = W.Text(body, { role = "micro", color = "textMuted" })
  body.list = K.NewList(body, {
    rowHeight = ROW_HEIGHT,
    bind = function(e)
      return { title = e.name, sub = detail(e), right = stamp(e.t) }
    end,
  })

  function body:fgGridLayout(width)
    self.dry:ClearAllPoints()
    self.dry:SetPoint("TOPLEFT", 0, 0)
    self.dry:SetWidth(width)
    local y = CHECKBOX_HEIGHT + GAP
    self.search:ClearAllPoints()
    self.search:SetPoint("TOPLEFT", 0, -y)
    self.clear:ClearAllPoints()
    if width >= MIN_SEARCH + GAP + CLEAR_WIDTH then
      self.search:SetWidth(width - CLEAR_WIDTH - GAP)
      self.clear:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -y)
      y = y + SEARCH_HEIGHT
    else
      self.search:SetWidth(width)
      y = y + SEARCH_HEIGHT + GAP
      self.clear:SetPoint("TOPLEFT", 0, -y)
      y = y + self.clear:GetHeight()
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

local function update(_, body)
  local state = body.state
  state.rows = AL.Filter(gm.db.log, state.search, label)
  body.dry.Refresh()
  body.count:SetText(string.format(L["gm.log.count"], #state.rows, #gm.db.log))
  body.list:SetData(state.rows)
end

gm.ext.RegisterTab({ id = "log", key = "gm.tab.log", order = 20, build = build, onShow = update })
