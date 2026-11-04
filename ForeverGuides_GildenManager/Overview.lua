-- Tab "Overview" of the guild page: what is due (a hint from the active rules, a click opens the tab
-- Rules), anniversaries and birthdays, returners, the traffic light per rank, absence and the statistics of
-- the week (RemindersLogic.lua). Also the detail lines for birthday and absence and the optional chat line
-- at login (off by default, once per session, never in combat). Everything is read; the only writes are
-- the local birthday list (delete) and the entries the player types in the member dialog (Members.lua).
-- Nothing is sent to anyone.
local _, gm = ...
if not gm.ext then
  return
end
local FG, RM, K, SL, DL = gm.FG, gm.RemindersLogic, gm.RulesKit, gm.SettingsLogic, gm.DatesLogic
local W, L, GD = FG.W, FG.L, FG.GuildData
if not (RM and K and SL) then
  return
end

local OV = {}
gm.Overview = OV

-- Names of one line before "and n more".
local MAX_NAMES = 6
local MAX_AWAY = 10
local DUE_COLOR = { promote = "success", demote = "warning", remove = "danger", mark = "text" }
local LEVEL_COLOR = { green = "success", yellow = "warning", red = "danger", none = "textMuted" }

local function sctx()
  return { guild = gm.Guild(), prefs = gm.db.prefs }
end

local function setting(id)
  return SL.Get(sctx(), id)
end

local function inCombat()
  local ok, fighting = pcall(InCombatLockdown)
  return ok and fighting == true
end

-- Data ------------------------------------------------------------------------------------------------------

-- The input of RemindersLogic.Build from the roster, the record, the settings and the plan of the rules.
-- nil without a clock.
function OV.Input()
  local today = gm.History.Clock()
  if not today then
    return nil
  end
  local snap = GD.Get()
  local guild = gm.Guild()
  local plan
  local tab = gm.RulesTab
  if tab and tab.PlanNow then
    local ok, built = pcall(tab.PlanNow)
    plan = ok and built or nil
  end
  return {
    today = today,
    lead = setting("reminderDays"),
    weekStart = setting("weekStart"),
    inactiveDays = setting("inactiveDays"),
    roster = snap.members,
    store = guild.members,
    ranks = snap.ranks,
    events = guild.events,
    plan = plan,
  }
end

function OV.Model()
  local input = OV.Input()
  return input and RM.Build(input)
end

-- Texts -----------------------------------------------------------------------------------------------------

local function whenText(inDays)
  if inDays == 0 then
    return L["gm.rem.when.today"]
  elseif inDays == 1 then
    return L["gm.rem.when.tomorrow"]
  end
  return string.format(L["gm.rem.when.days"], inDays)
end

local function agoText(ago)
  if ago == 0 then
    return L["gm.rem.when.today"]
  elseif ago == 1 then
    return L["gm.rem.ago.yesterday"]
  end
  return string.format(L["gm.rem.ago.days"], ago)
end

local function nameList(list, limit)
  local shown = {}
  for i = 1, math.min(#list, limit) do
    shown[i] = list[i].name
  end
  local text = table.concat(shown, ", ")
  if #list > limit then
    text = text .. " " .. string.format(L["gm.rem.more"], #list - limit)
  end
  return text
end

local function dateText(day)
  return DL.Format(day, gm.History.DateFormat())
end

local function row(text, color)
  return { text = text, color = color or "textSecondary" }
end

-- The lines of every card for a model: { due, people, returners, traffic, week }, each a list of
-- { text, color } rows; `notes` and flags the tab needs besides.
function OV.Lines(model)
  local out = { due = {}, people = {}, returners = {}, traffic = {}, week = {} }
  if not model then
    return out
  end
  local due = model.due
  if not due.active then
    out.due[1] = row(L["gm.rem.due.noRules"], "textMuted")
  elseif due.total == 0 then
    out.due[1] = row(L["gm.rem.due.none"], "textMuted")
  else
    for _, g in ipairs(RM.DUE_GROUPS) do
      local list = due.groups[g]
      if #list > 0 then
        out.due[#out.due + 1] = row(
          string.format(L["gm.rem.due.line"], L["gm.rem.due.group." .. g], #list, nameList(list, MAX_NAMES)),
          DUE_COLOR[g]
        )
      end
    end
  end

  local people = out.people
  if #model.anniversaries > 0 then
    people[#people + 1] = row(L["gm.rem.anniv.head"], "accent2")
    for _, a in ipairs(model.anniversaries) do
      local key = a.years == 1 and "gm.rem.anniv.one" or "gm.rem.anniv.line"
      local text = a.years == 1 and string.format(L[key], a.name, whenText(a.inDays))
        or string.format(L[key], a.name, a.years, whenText(a.inDays))
      people[#people + 1] = row(text, a.inDays == 0 and "text" or "textSecondary")
    end
  end
  if #model.birthdays > 0 then
    people[#people + 1] = row(L["gm.rem.birthday.head"], "accent2")
    local order = gm.History.DateFormat()
    for _, b in ipairs(model.birthdays) do
      people[#people + 1] = row(
        string.format(L["gm.rem.birthday.line"], b.name, RM.FormatBirthday(b, order), whenText(b.inDays)),
        b.inDays == 0 and "text" or "textSecondary"
      )
    end
  end
  if #people == 0 then
    people[1] = row(string.format(L["gm.rem.people.empty"], model.lead), "textMuted")
  end
  if model.birthdayCount == 0 then
    people[#people + 1] = row(L["gm.rem.birthday.none"] .. ". " .. L["gm.rem.birthday.how"], "textMuted")
  end
  if model.unknownJoins > 0 then
    people[#people + 1] = row(string.format(L["gm.rem.anniv.unknown"], model.unknownJoins), "textMuted")
  end

  if #model.returners == 0 then
    out.returners[1] = row(string.format(L["gm.rem.returners.empty"], RM.RETURN_WINDOW), "textMuted")
  else
    for _, r in ipairs(model.returners) do
      out.returners[#out.returners + 1] = row(
        r.after and string.format(L["gm.rem.returner.line"], r.name, agoText(r.ago), r.after)
          or string.format(L["gm.rem.returner.lineShort"], r.name, agoText(r.ago))
      )
    end
  end

  for _, t in ipairs(model.traffic) do
    if t.share then
      out.traffic[#out.traffic + 1] = row(
        string.format(
          L["gm.rem.traffic.line"],
          t.name,
          L["gm.rem.level." .. t.level],
          t.inactive,
          t.total - t.away,
          t.percent
        ),
        LEVEL_COLOR[t.level]
      )
    else
      out.traffic[#out.traffic + 1] = row(string.format(L["gm.rem.traffic.noMembers"], t.name), "textMuted")
    end
  end
  if #model.away > 0 then
    out.traffic[#out.traffic + 1] = row(L["gm.rem.away.head"], "accent2")
    for i = 1, math.min(#model.away, MAX_AWAY) do
      local a = model.away[i]
      out.traffic[#out.traffic + 1] = row(string.format(L["gm.rem.away.line"], a.name, dateText(a.untilDay)))
    end
    if #model.away > MAX_AWAY then
      out.traffic[#out.traffic + 1] = row(string.format(L["gm.rem.more"], #model.away - MAX_AWAY), "textMuted")
    end
  end

  local w = model.week
  out.week[1] = row(string.format(L["gm.rem.week.range"], dateText(w.from), dateText(w.to)), "textMuted")
  if w.joins + w.leaves + w.ranks == 0 then
    out.week[2] = row(L["gm.rem.week.empty"], "textMuted")
  else
    out.week[2] = row(string.format(L["gm.rem.week.joins"], w.joins), "success")
    out.week[3] = row(string.format(L["gm.rem.week.leaves"], w.leaves), w.leaves > 0 and "warning" or "textSecondary")
    out.week[4] = row(string.format(L["gm.rem.week.ranks"], w.ranks))
  end
  return out
end

-- A stack of colored text rows; the rows are made when needed.
local function newRows(parent, id)
  local f = CreateFrame("Frame", nil, parent)
  f.fgId = id
  f.rows, f.count = {}, 0

  function f:Set(items)
    for i, item in ipairs(items) do
      local fs = self.rows[i]
      if not fs then
        fs = W.Text(self, { role = "small", color = "textSecondary", wrap = true })
        self.rows[i] = fs
      end
      fs:SetText(item.text)
      W.SetColor(fs, item.color or "textSecondary")
      fs:Show()
    end
    for i = #items + 1, #self.rows do
      self.rows[i]:Hide()
    end
    self.count = #items
  end

  function f:fgGridLayout(width)
    local y = 0
    for i = 1, self.count do
      local fs = self.rows[i]
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      fs:SetWidth(width)
      y = y + math.ceil(fs:GetStringHeight()) + 4
    end
    y = math.max(y - 4, 1)
    self:SetHeight(y)
    return y
  end
  return f
end

-- Tab -------------------------------------------------------------------------------------------------------

local function notify(text, kind)
  FG.Notify(text, kind or "info")
end

local function build(parent, uiCtx)
  local body = CreateFrame("Frame", nil, parent)
  body.fgId = "gm-overview"
  body.note = W.Text(body, { role = "small", color = "warning", wrap = true })
  local cards, parts = {}, {}

  local function card(id, extra)
    local c = K.Card(body, "gm-ov-" .. id, "gm.rem." .. extra.title, "gm.rem." .. extra.title .. ".help")
    cards[#cards + 1] = c
    parts[id] = newRows(c.frame, "gm-ov-" .. id .. "-rows")
    c:Add(parts[id], { gap = 10 })
    return c
  end

  local due = card("due", { title = "due" })
  parts.open = K.Button(due.frame, "gm.rem.due.open", function()
    if gm.ext.OpenTab then
      if gm.RulesTab and gm.RulesTab.OpenPage then
        gm.RulesTab.OpenPage("preview")
      end
      gm.ext.OpenTab("rules")
    end
  end, nil, "gm-ov-open")
  due:Add(parts.open, { width = 200, gap = 8, height = K.BUTTON_HEIGHT })

  local people = card("people", { title = "people" })
  parts.clear = K.Button(people.frame, "gm.rem.birthday.clear", function()
    FG.Dialogs.Confirm("gm.rem.clear.title", "gm.rem.clear.body", function()
      if gm.WriteBlock() then
        return
      end
      notify(string.format(L["gm.rem.clear.done"], RM.ClearBirthdays(gm.Guild())), "success")
      uiCtx.Refresh()
    end)
  end, "danger", "gm-ov-clear")
  people:Add(parts.clear, { width = 200, gap = 8, height = K.BUTTON_HEIGHT })
  K.Text(people, "gm.rem.local", "textMuted", 8, "micro")

  card("returners", { title = "returners" })
  local traffic = card("traffic", { title = "traffic" })
  parts.trafficHint = K.Text(traffic, nil, "textMuted", 8, "micro")
  card("week", { title = "week" })

  body.parts, body.cards = parts, cards

  function body:fgGridLayout(width)
    local w = math.min(width, K.MAX_WIDTH)
    local y = 0
    if self.note:IsShown() then
      self.note:SetWidth(w)
      self.note:ClearAllPoints()
      self.note:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      y = math.ceil(self.note:GetStringHeight()) + K.GAP
    end
    for _, c in ipairs(self.cards) do
      c.frame:ClearAllPoints()
      c.frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      y = y + c:Measure(w) + K.GAP
    end
    y = math.max(y - K.GAP, 1)
    self:SetHeight(y)
    return y
  end
  return body
end

local function update(_, body)
  local block = gm.WriteBlock()
  body.note:SetShown(block ~= nil)
  if block then
    W.SetText(body.note, block == "newer" and "gm.err.newer" or "gm.err.noGuild")
  end
  local parts = body.parts
  if gm.Tour then
    gm.Tour.Anchor(body)
  end
  local model = OV.Model()
  body.model = model
  if not model then
    for _, id in ipairs({ "due", "people", "returners", "traffic", "week" }) do
      parts[id]:Set({ row(L["gm.rem.noData"], "textMuted") })
    end
    parts.open:Hide()
    parts.clear:Hide()
    parts.trafficHint:Hide()
    return
  end
  local lines = OV.Lines(model)
  for _, id in ipairs({ "due", "people", "returners", "traffic", "week" }) do
    parts[id]:Set(lines[id])
  end
  parts.open:SetShown(not model.due.active or model.due.total > 0)
  parts.clear:SetShown(model.birthdayCount > 0)
  parts.trafficHint:Show()
  parts.trafficHint:SetText(string.format(L["gm.rem.traffic.hint"], SL.Get(sctx(), "inactiveDays")))
end

gm.ext.RegisterTab({ id = "overview", key = "gm.tab.overview", order = 5, build = build, onShow = update })

-- Detail lines ------------------------------------------------------------------------------------------------

gm.ext.RegisterDetail({
  id = "gm-reminders",
  order = 16,
  lines = function(m)
    local e = gm.Guild().members[m.key]
    local lines = {}
    if e and e.birthday then
      lines[#lines + 1] =
        string.format(L["gm.rem.detail.birthday"], RM.FormatBirthday(e.birthday, gm.History.DateFormat()))
    end
    local today = gm.History.Clock()
    if e and e.away and today and RM.IsAway(e.away, today) then
      lines[#lines + 1] = string.format(L["gm.rem.detail.away"], dateText(e.away))
    end
    return lines
  end,
})

-- Chat line at login -------------------------------------------------------------------------------------------

local announced, pending = false, false

-- Says one short line in the chat when the option is on: once per session, never in combat, nothing while
-- the demo runs. Answers true when a line was written.
function OV.Chat()
  if announced or inCombat() or gm.WriteBlock() or GD.Source() or not setting("reminderChat") then
    return false
  end
  local snap = GD.Get()
  if type(snap.members) ~= "table" or #snap.members == 0 then
    return false
  end
  local model = OV.Model()
  if not model then
    return false
  end
  announced = true
  local line = RM.ChatLine(model, L)
  if line then
    FG.Notify.chat(line)
  end
  return line ~= nil
end

-- A new session of the add-on state (tests and /reload start fresh anyway).
function OV.ResetSession()
  announced, pending = false, false
end

-- The roster arrives in parts: the line waits until it has been quiet, like the history does.
FG.On("GUILD_ROSTER_UPDATE", function()
  if announced or pending or not (C_Timer and C_Timer.After) then
    return
  end
  pending = true
  C_Timer.After((gm.HistoryLogic and gm.HistoryLogic.MIN_QUIET or 10) + 5, function()
    pending = false
    FG.Safe("gm-overview-chat", OV.Chat)
  end)
end)
