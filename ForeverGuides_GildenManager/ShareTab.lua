-- The page "Sharing" of the tab "Settings" (filled through the field `build` of SettingsPages.lua): the
-- two switches (send and receive, dimmed with a reason while the channel is not available to the
-- rank), the options of ShareLogic, the counters, the inbox with a button per offer and the buttons
-- that empty it. The consent itself lives in the main add-on (Consent); switching on goes through
-- the same confirm dialog as the hint of OptInNotice, switching off takes effect at once.
local _, gm = ...
if not gm.ext then
  return
end
local FG, SH, SL, Share = gm.FG, gm.ShareLogic, gm.SettingsLogic, gm.Share
local W, L, Consent, DL = FG.W, FG.L, FG.Consent, gm.DatesLogic

local ST = {}
gm.ShareTab = ST

local FN = SH.FN
local ROWS = 8
local BUTTON_PAD = 24
local BUTTON_H = 26
local BUTTON_GAP = 6
local DIM = 0.45

local function scope()
  return Consent.Overrides(FN) > 0 and "char" or nil
end

local function dimmedReason()
  if gm.WriteBlock() == "noGuild" then
    return "gm.share.noGuild"
  end
  if not Share.ChannelAvailable(Share.Settings().channel) then
    return "gm.share.noChannel"
  end
end

-- A switch for one direction. Off is always possible; on needs the channel and the confirm dialog.
local function addSwitch(card, uiCtx, dir)
  local toggle = W.Toggle(card.frame, {
    key = "gm.share." .. (dir == "send" and "send" or "recv"),
    tooltip = "gm.share." .. (dir == "send" and "send" or "recv"),
    tooltipText = "gm.share." .. (dir == "send" and "send" or "recv") .. ".tip",
    get = function()
      return Consent.Allows(FN, dir, "guild")
    end,
    set = function(value)
      if value ~= true then
        Consent.Set(FN, dir, "guild", false, "user", scope())
      elseif not dimmedReason() then
        FG.Dialogs.Confirm(
          nil,
          nil,
          function()
            Consent.Set(FN, dir, "guild", true, "user", scope())
            uiCtx.Refresh()
          end,
          nil,
          {
            title = L["optin.dialog.title"],
            text = FG.OptInNotice.DialogText(FN, dir, "guild"),
            yesKey = "optin.dialog.yes",
          }
        )
      end
      uiCtx.Refresh()
    end,
  })
  toggle.fgId = "gm-share-" .. dir
  local paint = toggle.Refresh
  function toggle.Refresh()
    paint()
    toggle:SetAlpha(dimmedReason() and not Consent.Allows(FN, dir, "guild") and DIM or 1)
  end
  card.stack:Add(toggle, { height = 24, gap = 4 })
  card.refresh[#card.refresh + 1] = toggle
end

-- A text line that follows the state; textOf answers a literal, or a locale key and nothing else.
local function addLine(card, id, role, color, textOf)
  local fs = W.Text(card.frame, { role = role, color = color, wrap = true })
  fs.fgId = id
  function fs.Refresh()
    local key, literal = textOf()
    fs:SetShown(key ~= nil or literal ~= nil)
    if key or literal then
      W.SetText(fs, key, literal)
    end
  end
  card.stack:Add(fs, { gap = 8 })
  card.refresh[#card.refresh + 1] = fs
  return fs
end

local function acceptedRanks()
  local limit, names = Share.Settings().maxRank, {}
  for _, rank in ipairs(FG.GuildData.Get().ranks or {}) do
    if rank.index <= limit then
      names[#names + 1] = rank.name
    end
  end
  return names
end

local function dateText(t)
  return DL.Format(DL.DayOf(t, 0), gm.History.DateFormat())
end

-- One offer of the inbox: what, who, when and the two buttons.
local function newRow(card, uiCtx, i, status)
  local row = CreateFrame("Frame", nil, card.frame)
  row.fgId = "gm-share-row-" .. i
  row.what = W.Text(row, { role = "small", color = "text", wrap = true })
  row.meta = W.Text(row, { role = "micro", color = "textMuted", wrap = true })
  local function act(fn)
    return function()
      if row.offer then
        fn(row.offer)
      end
      uiCtx.Refresh()
    end
  end
  row.adopt = W.Action(row, {
    key = "gm.share.adopt",
    height = BUTTON_H,
    onClick = act(function(offer)
      local ok, why = Share.Adopt(offer)
      status.key = "gm.share.result." .. (ok and "ok" or why)
    end),
  })
  row.discard = W.Action(row, {
    key = "gm.share.discard",
    height = BUTTON_H,
    onClick = act(function(offer)
      Share.Discard(offer)
      status.key = nil
    end),
  })
  row.adopt.fgId, row.discard.fgId = "gm-share-adopt-" .. i, "gm-share-discard-" .. i

  function row:fgGridLayout(width)
    self.what:SetWidth(width)
    self.what:ClearAllPoints()
    self.what:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    local h1 = math.ceil(self.what:GetStringHeight())
    self.meta:SetWidth(width)
    self.meta:ClearAllPoints()
    self.meta:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -h1 - 2)
    local y = h1 + 2 + math.ceil(self.meta:GetStringHeight()) + 6
    local x = 0
    for _, b in ipairs({ self.adopt, self.discard }) do
      local w = math.min(width, math.ceil(b.label:GetStringWidth()) + BUTTON_PAD)
      if x > 0 and x + w > width then
        x, y = 0, y + BUTTON_H + BUTTON_GAP
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
      b:SetSize(w, BUTTON_H)
      x = x + w + BUTTON_GAP
    end
    local h = y + BUTTON_H
    self:SetHeight(h)
    return h
  end

  function row.Bind(offer)
    row.offer = offer
    row:SetShown(offer ~= nil)
    if not offer then
      return
    end
    local source = L["gm.date.src." .. (offer.src or "shared")] or ""
    local meta =
      string.format(L["gm.share.from"], offer.from, offer.rank ~= "" and offer.rank or "?", dateText(offer.t), source)
    if offer.also and offer.also > 0 then
      meta = meta .. ", " .. string.format(L["gm.share.also"], offer.also)
    end
    W.SetText(row.what, nil, offer.name .. ": " .. SH.What(offer, L, gm.History.DateFormat()))
    W.SetText(row.meta, nil, meta)
  end
  return row
end

local function addButton(card, id, key, onClick, opens)
  local b = W.Action(card.frame, { key = key, height = BUTTON_H, opens = opens, onClick = onClick })
  b.fgId = id
  function b:fgGridLayout(width)
    local w = math.min(width, math.ceil(self.label:GetStringWidth()) + BUTTON_PAD)
    self:SetSize(w, BUTTON_H)
    return BUTTON_H
  end
  card.stack:Add(b, { gap = 6 })
  return b
end

-- Builds the card. api: ctx, uiCtx, addText, addOption (SettingsTab.lua).
function ST.Build(card, api)
  local uiCtx = api.uiCtx
  local function option(id)
    api.addOption(card, SL.Option(id), uiCtx)
  end
  api.addText(card, "gm.share.intro", "textSecondary", 8)
  addLine(card, "gm-share-note", "small", "warning", function()
    return dimmedReason()
  end)
  addSwitch(card, uiCtx, "send")
  addSwitch(card, uiCtx, "receive")
  option("shareChannel")
  option("shareMinRank")
  addLine(card, "gm-share-ranks", "small", "textSecondary", function()
    local names = acceptedRanks()
    if #names == 0 then
      return "gm.share.rankNone"
    end
    return nil, string.format(L["gm.share.rankNames"], table.concat(names, ", "))
  end)
  api.addText(card, "gm.share.cats", "textSecondary", 4)
  option("shareJoins")
  option("shareMarks")
  option("shareNotes")

  addLine(card, "gm-share-counts", "small", "textSecondary", function()
    local guild, c = gm.Guild(), SH.Counts(gm.Guild())
    local line = string.format(L["gm.share.counts"], c.sent, c.received, #guild.inbox)
    if Share.Peers() > 0 then
      line = line .. "\n" .. string.format(L["gm.share.peers"], Share.Peers())
    end
    return nil, line
  end)
  local open = addButton(card, "gm-share-open", "gm.share.open", function()
    FG.SettingsPage.Select("sharing")
    FG.Main.Show("settings")
  end, true)

  api.addText(card, "gm.share.inbox", "textSecondary", 4)
  local banner = FG.OptInNotice.Banner(card.frame, {
    fn = FN,
    dir = "receive",
    aud = "guild",
    textKey = "gm.share.needRecv",
  })
  banner.Refresh = function()
    banner:Update()
  end
  card.stack:Add(banner, { gap = 6 })
  card.refresh[#card.refresh + 1] = banner

  local status = {}
  local empty = addLine(card, "gm-share-empty", "small", "textMuted", function()
    if #gm.Guild().inbox == 0 then
      return status.key or "gm.share.inbox.empty"
    end
    return status.key
  end)
  local rows = {}
  for i = 1, ROWS do
    rows[i] = newRow(card, uiCtx, i, status)
    card.stack:Add(rows[i], { gap = 8 })
  end
  local more = addLine(card, "gm-share-more", "small", "textMuted", function()
    local extra = #gm.Guild().inbox - ROWS
    return nil, extra > 0 and string.format(L["gm.share.inbox.more"], extra) or nil
  end)
  local list = {}
  function list.Refresh()
    local inbox = gm.Guild().inbox
    -- Newest first.
    for i = 1, ROWS do
      rows[i].Bind(inbox[#inbox - i + 1])
    end
  end
  card.refresh[#card.refresh + 1] = list

  local discard = addButton(card, "gm-share-discard-all", "gm.share.discardAll", function()
    FG.Dialogs.Confirm("gm.share.discardAll.title", "gm.share.discardAll.body", function()
      Share.DiscardAll()
      status.key = nil
      uiCtx.Refresh()
    end)
  end)
  addButton(card, "gm-share-wipe", "gm.share.wipe", function()
    FG.Dialogs.Confirm("gm.share.wipe.title", "gm.share.wipe.body", function()
      Share.Wipe()
      status.key = nil
      uiCtx.Refresh()
    end)
  end)
  card.refresh[#card.refresh + 1] = {
    Refresh = function()
      discard:SetEnabled(#gm.Guild().inbox > 0)
    end,
  }
  -- Rows come before the "more" line, the line after them reads the same list.
  card.share = { open = open, empty = empty, more = more, rows = rows }

  FG.On("FG_GM_SHARE_CHANGED", function()
    if card.frame:IsVisible() then
      uiCtx.Refresh()
    end
  end)
end
