-- Forever Chat, the head of the tab "Teams" (game access): the notice for the consent (one button for what is off),
-- the cards of the open invitations (Accept, Decline, Block sender) and the symbols of the teams for the list.
-- ChatList.lua creates it (View.Attach) and puts its frame between the tabs and the rows. Everything runs through
-- chat.Teams; this file sends nothing itself. Names from the game or the add-on line pass AutoGuard before they
-- reach a text.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, Consent = FG.W, FG.L, FG.Consent
local UL = chat.TeamsUILogic

local View = {}
chat.TeamsView = View

local GAP, PAD = 6, 4

local function safe(value)
  local v = FG.AutoGuard.Safe(value)
  return type(v) == "string" and v or ""
end

local function api()
  return chat.Teams
end

-- The state of the consent: receive on, send on.
function View.Consent()
  local fn = api() and api().FN or "teamChat"
  return Consent.Allows(fn, "receive", "chat") == true, Consent.Allows(fn, "send", "chat") == true
end

-- Symbols of the teams by id (for the chips of the list).
function View.Icons()
  local out = {}
  for _, entry in ipairs(api() and api().List() or {}) do
    out[entry.id] = entry.icon
  end
  return out
end

-- Open invitations, for the badge of the tab and the icon (zero while nothing is received).
function View.OpenInvites()
  if not api() then
    return 0
  end
  local receiveOn = View.Consent()
  return receiveOn and UL.OpenInvites(api().Invites()) or 0
end

local function memberText(n)
  return n == 1 and L["chat.teams.members.one"] or string.format(L["chat.teams.members"], n)
end
View.MemberText = memberText

-- Text of the tooltip lines for invitations ("3 open invitations").
function View.InviteLine(n)
  return n == 1 and L["chat.teams.tip.invites.one"] or string.format(L["chat.teams.tip.invites"], n)
end

-- Switch on ------------------------------------------------------------------------------------------------------

local function definition()
  for _, def in ipairs(Consent.List()) do
    if def.id == "teamChat" then
      return def
    end
  end
end

-- The text of the dialog: the flags that are switched on, then the information text of the function.
function View.DialogText(missing)
  local def = definition()
  if not def then
    return ""
  end
  local lines = {}
  for _, dir in ipairs(missing) do
    lines[#lines + 1] = string.format(L["chat.teams.optin.lead"], L[def.labelKey], L["consent.flag." .. dir .. ".chat"])
  end
  return table.concat(lines, "\n") .. "\n\n" .. L[def.infoKey]
end

-- Step two: the dialog. Only "Switch on" there writes the consent; a character that has values of its own for
-- the function keeps them, so the value is written for the character, else for the account.
local function ask()
  local missing = UL.Missing(View.Consent())
  if #missing == 0 then
    return
  end
  FG.Dialogs.Confirm(
    nil,
    nil,
    function()
      local scope = Consent.Overrides("teamChat") > 0 and "char" or nil
      for _, dir in ipairs(missing) do
        Consent.Set("teamChat", dir, "chat", true, "user", scope)
      end
    end,
    nil,
    {
      title = L["chat.teams.optin.title"],
      text = View.DialogText(missing),
      yesKey = "chat.teams.optin.yes",
    }
  )
end
View.Ask = ask

-- Cards ----------------------------------------------------------------------------------------------------------

local function refuse(why)
  FG.Notify(api().ReasonText(why), "warning")
end

local function newCard(view)
  local card = CreateFrame("Frame", nil, view.frame)
  W.Fill(card, "surface", 1)
  W.Border(card, "accentDim", 1)
  card.text = W.Text(card, { role = "ui", color = "text", wrap = true })
  card.wait = W.Text(card, { role = "micro", color = "warning", wrap = true })
  local function button(key, id, fn, variant)
    local b = W.Action(card, { key = key, wrap = id, variant = variant, height = 24, onClick = fn })
    b.fgId = id
    return b
  end
  card.accept = button("chat.teams.accept", "chat-team-accept", function()
    local ok, why = api().Accept(card.invite.id)
    if not ok then
      refuse(why)
    end
  end, "primary")
  card.decline = button("chat.teams.decline", "chat-team-decline", function()
    local ok, why = api().Decline(card.invite.id)
    if not ok then
      refuse(why)
    end
  end)
  card.block = button("chat.teams.blockSender", "chat-team-block", function()
    local ok, why = api().Block(card.invite.from)
    if not ok then
      refuse(why)
    end
  end, "ghost")
  card:Hide()
  return card
end

local function paintCard(card, inv)
  card.invite = inv
  local from, name = UL.Short(safe(inv.from)), safe(inv.name)
  local members = memberText(tonumber(inv.count) or 1)
  local icon = UL.IconText(inv.icon, 14)
  if inv.accepted then
    card.text:SetText(icon .. " " .. string.format(L["chat.teams.invite.waiting"], name, members))
    card.wait:SetText("")
  else
    card.text:SetText(icon .. " " .. string.format(L["chat.teams.invite.text"], from, name, members))
    card.wait:SetText("")
  end
  card.open = inv.accepted ~= true
  card.accept:SetShown(card.open)
  card.decline:SetShown(true)
  card.block:SetShown(card.open)
  if not card.open then
    W.SetText(card.decline.label, "chat.teams.decline")
  end
end

-- Places the buttons in rows that wrap; returns the height of the card.
local function layoutCard(card, width)
  local inner = math.max(40, width - 2 * PAD)
  card.text:ClearAllPoints()
  card.text:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -PAD)
  card.text:SetWidth(inner)
  local top = PAD + math.ceil(card.text:GetStringHeight()) + GAP
  local x, row, rowH = 0, 0, 24
  for _, b in ipairs({ card.accept, card.decline, card.block }) do
    if b:IsShown() then
      local w = math.min(b:FullWidth(), inner)
      if x > 0 and x + w > inner then
        x, row = 0, row + 1
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", card, "TOPLEFT", PAD + x, -(top + row * (rowH + 4)))
      b:SetWidth(w)
      x = x + w + 6
    end
  end
  local h = top + (row + 1) * (rowH + 4) + PAD - 4
  card:SetWidth(width)
  card:SetHeight(h)
  return h
end

-- Attach ---------------------------------------------------------------------------------------------------------

-- Builds the head for a list (parent: the frame of the list). Fields: frame; methods Update(), Height(width).
function View.Attach(list, parent)
  local view = { list = list, cards = {} }
  local f = CreateFrame("Frame", nil, parent)
  view.frame = f
  f:Hide()
  view.banner = FG.ActionBanner.New(f, {
    buttonKey = "chat.teams.optin.button",
    opens = true,
    buttonWidth = 150,
    onClick = ask,
  })
  view.banner.button.fgId = "chat-teams-optin"
  view.banner:Hide()
  for i = 1, UL.MAX_CARDS do
    view.cards[i] = newCard(view)
  end
  view.more = W.Text(f, { role = "micro", color = "textMuted", wrap = true })
  view.more:Hide()

  -- Whether the head shows at all: the tab Teams without a search.
  function view:Wanted()
    return list.tab == "teams" and not list.query:find("%S")
  end

  -- The data now: the key of the notice (nil when everything is on) and the cards.
  function view:Data()
    local receiveOn, sendOn = View.Consent()
    local shown, rest = {}, 0
    if receiveOn and api() then
      shown, rest = UL.Cards(api().Invites(), UL.MAX_CARDS)
    end
    return UL.NoticeKey(receiveOn, sendOn), shown, rest
  end

  -- Fills and places the parts for the width, shows or hides the frame, returns the height it needs.
  function view:Layout(width)
    if not view:Wanted() then
      f:Hide()
      return 0
    end
    local noticeKey, shown, rest = view:Data()
    local top = 0
    view.banner:SetShown(noticeKey ~= nil)
    if noticeKey then
      W.SetText(view.banner.text, noticeKey)
      view.banner:ClearAllPoints()
      view.banner:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
      top = math.ceil(view.banner:Fit(width)) + GAP
    end
    for i, card in ipairs(view.cards) do
      local inv = shown[i]
      if inv then
        paintCard(card, inv)
        card:Show()
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
        top = top + layoutCard(card, width) + GAP
      else
        card:Hide()
      end
    end
    view.more:SetShown(rest > 0)
    if rest > 0 then
      view.more:SetText(string.format(L["chat.teams.invite.more"], rest))
      view.more:ClearAllPoints()
      view.more:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
      view.more:SetWidth(width)
      top = top + math.ceil(view.more:GetStringHeight()) + GAP
    end
    top = math.max(0, top - GAP)
    f:SetWidth(width)
    f:SetHeight(math.max(1, top))
    f:SetShown(top > 0)
    return top
  end

  return view
end

-- The window and the list follow every change of the teams and of the consent.
FG.On("FG_CHAT_TEAMS", function()
  local win = chat.Window
  if win and win.IsShown() then
    win.Refresh()
    if win.RefreshTeams then
      win.RefreshTeams()
    end
  end
end)
FG.On("FG_CONSENT_CHANGED", function(_, fn)
  local win = chat.Window
  if fn == "teamChat" and win and win.IsShown() then
    win.Refresh()
  end
end)

-- Blocked senders in the options ---------------------------------------------------------------------------------

View.MAX_BLOCKED_ROWS = 8

-- Builds the list of blocked senders with a button "Unblock" for each (under the heading of the extras of the
-- options). The rows are fixed; the list follows FG_CHAT_TEAMS and fills them from Teams.Blocked().
function View.BuildBlocked(page)
  FG.AddHeading(page, "chat.teams.blocked.title", { role = "ui", gap = 4 })
  local none =
    W.Text(page.content, { key = "chat.teams.blocked.none", role = "micro", color = "textMuted", wrap = true })
  page.stack:Add(none, { gap = 4 })
  local rows = {}
  for i = 1, View.MAX_BLOCKED_ROWS do
    local row = CreateFrame("Frame", nil, page.content)
    row.name = W.Text(row, { role = "ui", color = "text" })
    row.name:SetWordWrap(false)
    row.button = W.Action(row, { key = "chat.teams.unblock", wrap = "chat-team-unblock", height = 24 })
    row.button.fgId = "chat-team-unblock-" .. i
    row.button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetPoint("RIGHT", row.button, "LEFT", -6, 0)
    row.button:SetScript(
      "OnClick",
      FG.Wrap("chat-team-unblock", function()
        if row.who then
          api().Unblock(row.who)
        end
      end)
    )
    row:Hide()
    page.stack:Add(row, { height = 26, gap = 4 })
    rows[i] = row
  end
  page.blockedRows = rows
  local function update()
    local names = api() and api().Blocked() or {}
    none:SetShown(#names == 0)
    for i, row in ipairs(rows) do
      local who = names[i]
      row.who = who
      row:SetShown(who ~= nil)
      if who then
        row.name:SetText(safe(who))
      end
    end
    page.stack:Layout()
  end
  FG.On("FG_CHAT_TEAMS", update)
  update()
end

if chat.Settings and chat.Settings.AddFooter then
  chat.Settings.AddFooter("extras", View.BuildBlocked)
end
