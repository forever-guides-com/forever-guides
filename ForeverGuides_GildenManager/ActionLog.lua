-- Tab "Log" of the guild page: two logs behind a page row, the events (what happened in the guild) and
-- the actions (what this add-on did, with rule and result). Filters (kind, period, result, member, rule),
-- search, pages, undo of a rank change inside its window, clear after a confirmation, export and import,
-- and the dry run switch of the actions. Read only: a click on a row changes nothing, the undo button opens
-- the same confirm dialog as every action (Actions.Undo).
local _, gm = ...
if not gm.ext then
  return
end
local FG, LG, K = gm.FG, gm.LogLogic, gm.RulesKit
local W, L, PN, DL = FG.W, FG.L, FG.PlayerName, gm.DatesLogic
local PK = FG.PageKit

local ROW_HEIGHT = 58
local GAP = 8
local CHECKBOX_HEIGHT = 22
local CLEAR_WIDTH = 110
local DROPDOWN_WIDTH = 150
local FIELD_WIDTH = 170

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

-- Rule, result and undo mark of an action in one line, "" for an entry that has none of them.
local function meta(e)
  local parts = {}
  if e.rule then
    parts[#parts + 1] = string.format(L["gm.log.rule"], e.rule)
  end
  if e.result then
    parts[#parts + 1] = L["gm.log.result." .. e.result]
  end
  if e.undone then
    parts[#parts + 1] = L["gm.log.undone"]
  end
  return table.concat(parts, ", ")
end

local function rowOf(roster, name)
  for _, m in ipairs(roster) do
    if PN.Equal(m.name, name) then
      return m
    end
  end
end

-- The button "Invite again" of a removed member who is not in the guild (nil when it cannot be offered).
local function inviteAction(name, ctx)
  if not gm.Actions.CanInvite(name) then
    return nil
  end
  return {
    {
      icon = "plus",
      tooltip = L["gm.act.invite"],
      tooltipText = L["gm.invite.tip"],
      opens = true,
      onClick = function()
        gm.Actions.OpenInvite(name, ctx)
      end,
    },
  }
end

local function options(first, list, prefix)
  local out = { { value = "all", key = first } }
  for _, v in ipairs(list) do
    out[#out + 1] = { value = v, key = prefix .. v }
  end
  return out
end

local function place(host, items, width, y)
  local x, rowH = 0, 0
  for _, it in ipairs(items) do
    if it.frame:IsShown() then
      local w = math.min(it.w, width)
      if x > 0 and x + w > width then
        x, y, rowH = 0, y + rowH + GAP, 0
      end
      it.frame:ClearAllPoints()
      it.frame:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
      it.frame:SetWidth(w)
      if it.frame.button then
        it.frame.button:SetWidth(w)
      end
      x = x + w + GAP
      rowH = math.max(rowH, it.frame:GetHeight())
    end
  end
  return y + rowH
end

local function build(parent, ctx)
  local body = CreateFrame("Frame", nil, parent)
  body.fgId = "gm-log"
  local state = { page = "actions", filter = LG.NewFilter(), pageNo = 1, rows = {}, roster = {}, ctx = ctx }
  body.state = state

  local function changed()
    state.pageNo = 1
    ctx.Refresh()
  end
  local function edit(id, placeholder, field)
    local box = W.EditBox(body, {
      placeholder = placeholder,
      clear = true,
      onChange = function(text)
        state.filter[field] = text
        changed()
      end,
    })
    box.fgId = id
    return box
  end
  local function dropdown(id, key, opts, field, tipKey)
    local d = W.Dropdown(body, {
      key = key,
      options = opts,
      width = DROPDOWN_WIDTH,
      tooltip = tipKey,
      get = function()
        return state.filter[field]
      end,
      set = function(v)
        state.filter[field] = v
        changed()
      end,
    })
    d.button.fgId = id
    return d
  end

  body.head = K.Head(body, "gm-log-head", "gm.help.log", "gm.help.log.help")
  body.nav = W.Tabs(body, {
    tabs = { { id = "actions", key = "gm.log.page.actions" }, { id = "events", key = "gm.log.page.events" } },
    wrap = true,
    onSelect = function(id)
      if state.page ~= id then
        state.page, state.pageNo, state.filter = id, 1, LG.NewFilter()
        ctx.Refresh()
      end
    end,
  })
  body.nav.fgId = "gm-log-pages"

  body.dry = W.Checkbox(body, {
    key = "gm.dry.option",
    tooltip = "gm.dry.option",
    tooltipText = "gm.dry.tip",
    get = function()
      return gm.Guild().settings.dryRun
    end,
    set = function(v)
      gm.Guild().settings.dryRun = v == true
    end,
  })
  body.dry.fgId = "gm-log-dry"

  local periods = {}
  for _, days in ipairs(LG.PERIODS) do
    periods[#periods + 1] = { value = days, key = "gm.log.period." .. days }
  end
  body.kindActions =
    dropdown("gm-log-kind-actions", "gm.log.kind", options("gm.log.all", LG.ACTION_KINDS, "gm.act."), "kind")
  body.kindEvents =
    dropdown("gm-log-kind-events", "gm.log.kind", options("gm.log.all", LG.EVENT_KINDS, "gm.ev."), "kind")
  body.period = dropdown("gm-log-period", "gm.log.period", periods, "period")
  body.result =
    dropdown("gm-log-result", "gm.log.resultLabel", options("gm.log.all", LG.RESULTS, "gm.log.filter."), "result")
  body.search = edit("gm-log-search", "guild.search", "search")
  body.member = edit("gm-log-member", "gm.log.member", "member")
  body.rule = edit("gm-log-rule", "gm.log.ruleField", "rule")

  body.clear = W.Action(body, {
    label = "act.clear",
    icon = "trash",
    tooltip = "gm.log.clear",
    width = CLEAR_WIDTH,
    onClick = function()
      local events = state.page == "events"
      local guild = gm.Guild()
      if #(events and guild.events or guild.actions) == 0 then
        return
      end
      local prefix = events and "gm.log.clearEvents" or "gm.log.clear"
      FG.Dialogs.Confirm(prefix, prefix .. "Ask", function()
        if events then
          gm.Guild().events = {}
        else
          gm.Guild().actions = {}
        end
        ctx.Refresh()
      end)
    end,
  })
  body.clear.fgId = "gm-log-clear"
  body.clear.fgWidth = CLEAR_WIDTH
  body.export = K.Button(body, "gm.log.export", function()
    gm.Export.OpenExport(ctx)
  end, nil, "gm-log-export", true)
  body.import = K.Button(body, "gm.log.import", function()
    gm.Export.OpenImport(ctx)
  end, nil, "gm-log-import", true)
  body.buttons = K.Flow(body, { body.clear, body.export, body.import })

  body.count = W.Text(body, { role = "micro", color = "textMuted" })
  body.pageText = W.Text(body, { role = "micro", color = "textMuted" })
  body.empty = W.Text(body, { role = "small", color = "textSecondary", wrap = true })
  body.prev = K.Button(body, "gm.log.prev", function()
    state.pageNo = state.pageNo - 1
    ctx.Refresh()
  end, nil, "gm-log-prev")
  body.next = K.Button(body, "gm.log.next", function()
    state.pageNo = state.pageNo + 1
    ctx.Refresh()
  end, nil, "gm-log-next")
  body.pager = K.Flow(body, { body.prev, body.next })

  body.list = PK.NewList(body, {
    rowHeight = ROW_HEIGHT,
    bind = function(e)
      if not e.action then
        local event = {
          title = e.name,
          sub = LG.EventText(e, L),
          right = LG.EventDate(e, gm.History.DateFormat()),
          wrapSub = true,
        }
        if e.kind == "remove" then
          event.actions = inviteAction(e.name, ctx)
        end
        return event
      end
      local extra = meta(e)
      local out = {
        title = e.name,
        sub = extra ~= "" and detail(e) .. "\n" .. extra or detail(e),
        right = stamp(e.t),
        wrapSub = true,
      }
      if e.action == "remove" then
        out.actions = inviteAction(e.name, ctx)
      end
      if LG.CanUndo(e, rowOf(state.roster, e.name), state.now, state.undoDays) then
        out.actions = {
          {
            icon = "undo",
            tooltip = L["gm.rules.undo"],
            tooltipText = L["gm.log.undoTip"],
            onClick = function()
              gm.Actions.Undo(e, ctx)
            end,
          },
        }
      end
      return out
    end,
  })

  function body:fgGridLayout(width)
    local actions = state.page == "actions"
    self.head:ClearAllPoints()
    self.head:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.head:SetWidth(width)
    local top = self.head:fgGridLayout(width) + GAP
    self.nav:ClearAllPoints()
    self.nav:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -top)
    self.nav:SetWidth(width)
    local y = top + self.nav:fgGridLayout(width) + GAP
    self.dry:ClearAllPoints()
    self.dry:SetPoint("TOPLEFT", 0, -y)
    self.dry:SetWidth(width)
    if actions then
      y = y + CHECKBOX_HEIGHT + GAP
    end
    y = place(self, {
      { frame = self.kindActions, w = DROPDOWN_WIDTH },
      { frame = self.kindEvents, w = DROPDOWN_WIDTH },
      { frame = self.period, w = DROPDOWN_WIDTH },
      { frame = self.result, w = DROPDOWN_WIDTH },
    }, width, y) + GAP
    y = place(self, {
      { frame = self.search, w = FIELD_WIDTH },
      { frame = self.member, w = FIELD_WIDTH },
      { frame = self.rule, w = FIELD_WIDTH },
    }, width, y) + GAP
    self.buttons:ClearAllPoints()
    self.buttons:SetPoint("TOPLEFT", 0, -y)
    self.buttons:SetWidth(width)
    y = y + self.buttons:fgGridLayout(width) + GAP
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", 0, -y)
    y = y + self.count:GetStringHeight() + GAP
    if self.pageText:IsShown() then
      self.pageText:ClearAllPoints()
      self.pageText:SetPoint("TOPLEFT", 0, -y)
      y = y + self.pageText:GetStringHeight() + GAP
    end
    if self.empty:IsShown() then
      self.empty:ClearAllPoints()
      self.empty:SetPoint("TOPLEFT", 0, -y)
      self.empty:SetWidth(width)
      y = y + math.ceil(self.empty:GetStringHeight()) + GAP
    end
    local listHeight = PK.scaledHeight(ROW_HEIGHT) * #state.rows
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", 0, -y)
    self.list:SetSize(width, math.max(listHeight, 1))
    y = y + listHeight
    if self.pager:IsShown() then
      y = y + GAP
      self.pager:ClearAllPoints()
      self.pager:SetPoint("TOPLEFT", 0, -y)
      self.pager:SetWidth(width)
      y = y + self.pager:fgGridLayout(width)
    end
    self:SetHeight(y)
    return y
  end
  return body
end

local function update(ctx, body)
  local state = body.state
  state.ctx = ctx
  local guild = gm.Guild()
  local H = gm.History
  local today, now = H.Clock()
  now = now or FG.U.now()
  today = today or DL.DayOf(now, 0)
  state.now = now
  state.undoDays = gm.SettingsLogic.Get({ guild = guild, prefs = gm.db.prefs }, "undoDays")
  state.roster = FG.GuildData.Get().members or {}

  local actions = state.page == "actions"
  local full, total
  if actions then
    full = LG.Actions(guild.actions, state.filter, { now = now, label = label })
    total = #guild.actions
  else
    full = LG.Events(guild.events, state.filter, {
      today = today,
      label = function(kind)
        return L["gm.ev." .. kind]
      end,
    })
    total = #guild.events
  end
  local pages
  state.rows, state.pageNo, pages = LG.Page(full, state.pageNo)

  body.nav:Select(state.page)
  for _, f in ipairs({ body.dry, body.kindActions, body.result, body.rule }) do
    f:SetShown(actions)
  end
  body.kindEvents:SetShown(not actions)
  body.dry.Refresh()
  for _, d in ipairs({ body.kindActions, body.kindEvents, body.period, body.result }) do
    d.Refresh()
  end
  body.count:SetText(string.format(L["gm.log.count"], #full, total))
  body.pageText:SetShown(pages > 1)
  body.pageText:SetText(string.format(L["gm.log.pageOf"], state.pageNo, pages))
  body.pager:SetShown(pages > 1)
  body.prev:SetShown(state.pageNo > 1)
  body.next:SetShown(state.pageNo < pages)
  body.empty:SetShown(#full == 0)
  if #full == 0 then
    local key = LG.Active(state.filter) and "gm.log.noMatch"
      or (actions and "gm.log.emptyActions" or "gm.log.emptyEvents")
    W.SetText(body.empty, key)
  end
  body.list:SetData(state.rows)
end

gm.ext.RegisterTab({ id = "log", key = "gm.tab.log", order = 30, build = build, onShow = update })
