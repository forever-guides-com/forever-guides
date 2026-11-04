-- Tab "Lists" of the guild page: the ban list, former members and alt groups behind a page row. All of it
-- stays on this PC. The ban list is typed by hand (name, reason, note); a banned name that is in the roster or
-- joins gets a hint in the chat and in the tab. Nothing is removed, invited or changed automatically.
local _, gm = ...
if not gm.ext then
  return
end
local FG, BL, K, DL = gm.FG, gm.BansLogic, gm.RulesKit, gm.DatesLogic
local W, L, PK, GD = FG.W, FG.L, FG.PageKit, FG.GuildData

local X = {}
gm.Lists = X

local ROW_HEIGHT = 52
local GAP = 8
local FIELD_WIDTH = 220
local SHOWN_WARNINGS = 4
local PAGES = { "bans", "former", "alts" }

local function guild()
  return gm.Guild()
end

local function dateText(day)
  return day and day > 0 and DL.Format(day, gm.History.DateFormat()) or ""
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

-- Warnings ------------------------------------------------------------------------------------------------

local announced = {}

local function rosterRows()
  return GD.Get().members or {}
end

local function today()
  return (gm.History.Clock())
end

-- The people the ban list warns about right now (roster and recent joins).
function X.Warnings()
  local g = guild()
  if next(g.bans) == nil then
    return {}
  end
  return BL.Warnings(g, rosterRows(), today(), {})
end

local function warningLine(w)
  local reason = w.ban.reason ~= "" and w.ban.reason or L["gm.ban.noReason"]
  local key = w.via == "main" and "gm.ban.warnMain" or "gm.ban.warn"
  return string.format(L[key], w.name, reason)
end

-- Says once per session in the chat who is on the ban list and in the roster. Answers the new warnings.
function X.Check()
  local g = guild()
  if next(g.bans) == nil then
    return {}
  end
  local set = announced[g.name .. "|" .. g.realm]
  if not set then
    set = {}
    announced[g.name .. "|" .. g.realm] = set
  end
  local list = BL.Warnings(g, rosterRows(), today(), set)
  for _, w in ipairs(list) do
    FG.Notify.chat(warningLine(w))
  end
  return list
end

FG.On("GUILD_ROSTER_UPDATE", function()
  FG.Safe("gm-lists-check", X.Check)
end)
FG.On("CHAT_MSG_SYSTEM", function()
  FG.Safe("gm-lists-check", X.Check)
end)

-- Ban dialog -------------------------------------------------------------------------------------------

local dialog

local function saveBan()
  local d = dialog
  if locked() then
    return
  end
  local name = d.editing or d.name.edit:GetText()
  local ok, why =
    BL.Set(guild().bans, { name = name, reason = d.reason.edit:GetText(), note = d.note.edit:GetText() }, today())
  if not ok then
    d.msg:SetText(L["gm.ban.err." .. why])
    return
  end
  d:Hide()
  if d.ctx and d.ctx.Refresh then
    d.ctx.Refresh()
  end
end

local function field(d, y, labelKey, placeholder, limit)
  local label = W.Text(d, { key = labelKey, role = "ui" })
  label:SetPoint("TOPLEFT", 16, -y)
  local box = W.EditBox(d, { placeholder = placeholder, onEnter = saveBan })
  box:SetPoint("TOPLEFT", 16, -y - 20)
  box:SetWidth(368)
  box.edit:SetMaxLetters(limit)
  return box
end

local function buildDialog()
  local d = FG.Dialogs.Create("ForeverGuidesGMBan", 400, 330)
  W.SetText(d.title, "gm.ban.title")
  d.name = field(d, 48, "gm.ban.name", "gm.ban.nameHint", BL.MAX_NAME)
  d.name.fgId = "gm-ban-name"
  d.reason = field(d, 100, "gm.ban.reason", "gm.ban.reasonHint", BL.MAX_REASON)
  d.reason.fgId = "gm-ban-reason"
  d.note = field(d, 152, "gm.ban.note", "gm.ban.noteHint", BL.MAX_NOTE)
  d.note.fgId = "gm-ban-note"
  d.msg = W.Text(d, { role = "ui", color = "danger", wrap = true })
  d.msg:SetPoint("TOPLEFT", 16, -208)
  d.msg:SetPoint("RIGHT", -16, 0)
  local ok = W.Action(
    d,
    { label = "act.save", icon = "save", tooltip = "gm.ban.save", variant = "primary", width = 110, onClick = saveBan }
  )
  ok.fgId = "gm-ban-save"
  ok:SetPoint("BOTTOMRIGHT", -16, 14)
  local cancel = W.Action(d, {
    label = "act.cancel",
    icon = "close",
    tooltip = "common.cancel",
    width = 110,
    onClick = function()
      d:Hide()
    end,
  })
  cancel:SetPoint("RIGHT", ok, "LEFT", -8, 0)
  return d
end

-- entry: { key, name, reason, note } of a ban to change, or { name } to prefill a new one, or nil.
function X.OpenBan(ctx, entry)
  dialog = dialog or buildDialog()
  dialog.ctx = ctx
  local existing = entry and entry.key and guild().bans[entry.key]
  dialog.editing = existing and existing.name or nil
  dialog.name.edit:SetText(entry and entry.name or "")
  dialog.reason.edit:SetText(existing and existing.reason or "")
  dialog.note.edit:SetText(existing and existing.note or "")
  dialog.msg:SetText("")
  dialog:Show()
end

-- Tab -------------------------------------------------------------------------------------------------------

local function build(parent, ctx)
  local body = CreateFrame("Frame", nil, parent)
  body.fgId = "gm-lists"
  local state = { page = "bans", search = "", rows = {}, ctx = ctx }
  body.state = state

  body.head = K.Head(body, "gm-lists-head", "gm.help.lists", "gm.help.lists.help")
  body.warn = W.Text(body, { role = "small", color = "warning", wrap = true })
  local pages = {}
  for i, id in ipairs(PAGES) do
    pages[i] = { id = id, key = "gm.lists.page." .. id }
  end
  body.nav = W.Tabs(body, {
    tabs = pages,
    wrap = true,
    onSelect = function(id)
      if state.page ~= id then
        state.page, state.search = id, ""
        body.search.edit:SetText("")
        ctx.Refresh()
      end
    end,
  })
  body.nav.fgId = "gm-lists-pages"
  body.hint = W.Text(body, { role = "small", color = "textSecondary", wrap = true })
  body.search = W.EditBox(body, {
    placeholder = "guild.search",
    clear = true,
    onChange = function(text)
      state.search = text
      ctx.Refresh()
    end,
  })
  body.search.fgId = "gm-lists-search"
  body.add = K.Button(body, "gm.ban.add", function()
    X.OpenBan(ctx)
  end, "primary", "gm-ban-add", true)
  body.count = W.Text(body, { role = "micro", color = "textMuted" })
  body.empty = W.Text(body, { role = "small", color = "textSecondary", wrap = true })
  body.list = PK.NewList(body, {
    rowHeight = ROW_HEIGHT,
    bind = function(item)
      if state.page == "bans" then
        local reason = item.reason ~= "" and item.reason or L["gm.ban.noReason"]
        return {
          title = item.name,
          sub = item.note ~= "" and reason .. "\n" .. item.note or reason,
          right = dateText(item.day),
          wrapSub = true,
          actions = {
            {
              icon = "pencil",
              tooltip = L["gm.ban.edit"],
              opens = true,
              onClick = function()
                X.OpenBan(ctx, item)
              end,
            },
            {
              icon = "trash",
              tooltip = L["gm.ban.remove"],
              onClick = function()
                FG.Dialogs.Confirm("gm.ban.remove", nil, function()
                  if not locked() then
                    BL.Remove(guild().bans, item.key)
                    ctx.Refresh()
                  end
                end, nil, { text = string.format(L["gm.ban.removeAsk"], item.name) })
              end,
            },
          },
        }
      elseif state.page == "former" then
        local how = L["gm.former." .. item.how]
        local parts = { how }
        if item.rank then
          parts[#parts + 1] = string.format(L["gm.former.rank"], item.rank)
        end
        if item.by and item.by ~= "" then
          parts[#parts + 1] = string.format(L["gm.ev.by"], item.by)
        end
        local out = { title = item.name, sub = table.concat(parts, ", "), right = dateText(item.day), wrapSub = true }
        if item.banned then
          out.badge = { text = L["gm.former.banned"], color = "warning" }
        else
          out.actions = {
            {
              icon = "tag",
              tooltip = L["gm.former.ban"],
              opens = true,
              onClick = function()
                X.OpenBan(ctx, { name = item.name })
              end,
            },
          }
          if gm.Actions.CanInvite(item.name) then
            table.insert(out.actions, {
              icon = "plus",
              tooltip = L["gm.act.invite"],
              tooltipText = L["gm.invite.tip"],
              opens = true,
              onClick = function()
                gm.Actions.OpenInvite(item.name, ctx)
              end,
            })
          end
        end
        return out
      end
      local out =
        { title = item.name, sub = string.format(L["gm.alts.list"], table.concat(item.alts, ", ")), wrapSub = true }
      if item.banned then
        out.badge = { text = L["gm.former.banned"], color = "warning" }
      end
      return out
    end,
  })

  function body:fgGridLayout(width)
    local w = math.min(width, K.MAX_WIDTH)
    self.head:ClearAllPoints()
    self.head:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.head:SetWidth(w)
    local y = self.head:fgGridLayout(w) + GAP
    if self.warn:IsShown() then
      self.warn:SetWidth(w)
      self.warn:ClearAllPoints()
      self.warn:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      y = y + math.ceil(self.warn:GetStringHeight()) + GAP
    end
    self.nav:ClearAllPoints()
    self.nav:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    self.nav:SetWidth(w)
    y = y + self.nav:fgGridLayout(w) + GAP
    self.hint:SetWidth(w)
    self.hint:ClearAllPoints()
    self.hint:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    y = y + math.ceil(self.hint:GetStringHeight()) + GAP
    self.search:ClearAllPoints()
    self.search:SetPoint("TOPLEFT", 0, -y)
    self.add:ClearAllPoints()
    if self.add:IsShown() then
      local addW = math.ceil(self.add.label:GetStringWidth()) + 24
      if w >= FIELD_WIDTH + GAP + addW then
        self.search:SetWidth(FIELD_WIDTH)
        self.add:SetPoint("TOPLEFT", self.search, "TOPRIGHT", GAP, 0)
        self.add:SetSize(addW, K.BUTTON_HEIGHT)
        y = y + math.max(self.search:GetHeight(), K.BUTTON_HEIGHT) + GAP
      else
        self.search:SetWidth(w)
        y = y + self.search:GetHeight() + GAP
        self.add:SetPoint("TOPLEFT", 0, -y)
        self.add:SetSize(math.min(addW, w), K.BUTTON_HEIGHT)
        y = y + K.BUTTON_HEIGHT + GAP
      end
    else
      self.search:SetWidth(math.min(w, FIELD_WIDTH))
      y = y + self.search:GetHeight() + GAP
    end
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", 0, -y)
    y = y + self.count:GetStringHeight() + GAP
    if self.empty:IsShown() then
      self.empty:SetWidth(w)
      self.empty:ClearAllPoints()
      self.empty:SetPoint("TOPLEFT", 0, -y)
      y = y + math.ceil(self.empty:GetStringHeight()) + GAP
    end
    local listHeight = PK.scaledHeight(ROW_HEIGHT) * #state.rows
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", 0, -y)
    self.list:SetSize(w, math.max(listHeight, 1))
    y = y + listHeight
    self:SetHeight(y)
    return y
  end
  return body
end

local function update(ctx, body)
  local state = body.state
  state.ctx = ctx
  local g = guild()
  local rows, total
  if state.page == "bans" then
    rows = BL.List(g.bans, state.search)
    total = 0
    for _ in pairs(g.bans) do
      total = total + 1
    end
  elseif state.page == "former" then
    local current = {}
    for _, m in ipairs(rosterRows()) do
      current[m.key] = true
    end
    rows = BL.Former(g, state.search, current)
    total = #BL.Former(g, "", current)
  else
    rows = BL.AltGroups(g, state.search)
    total = #BL.AltGroups(g, "")
  end
  state.rows = rows
  body.nav:Select(state.page)
  W.SetText(body.hint, "gm.lists.hint." .. state.page)
  body.add:SetShown(state.page == "bans")
  body.count:SetText(string.format(L["gm.lists.count"], #rows, total))
  body.empty:SetShown(#rows == 0)
  if #rows == 0 then
    W.SetText(body.empty, state.search ~= "" and "gm.lists.noMatch" or "gm.lists.empty." .. state.page)
  end
  local warnings = X.Warnings()
  body.warn:SetShown(#warnings > 0)
  if #warnings > 0 then
    local lines = {}
    for i = 1, math.min(#warnings, SHOWN_WARNINGS) do
      lines[i] = warningLine(warnings[i])
    end
    if #warnings > SHOWN_WARNINGS then
      lines[#lines + 1] = string.format(L["gm.ban.warnMore"], #warnings - SHOWN_WARNINGS)
    end
    body.warn:SetText(table.concat(lines, "\n"))
  end
  body.list:SetData(rows)
end

gm.ext.RegisterTab({ id = "lists", key = "gm.tab.lists", order = 40, build = build, onShow = update })
