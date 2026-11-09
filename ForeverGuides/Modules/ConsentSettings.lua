-- Settings tab "Share": every sharing function of Core/Consent.lua as a card with a switch per
-- direction and audience, who it applies to (account or this character), a card with the overview and
-- a card that mirrors the chat lines the add-on writes in the player's name. The cards come from
-- Consent.List(); a function shows once its package marked it available. Every write goes through
-- Consent.Set and Consent.Reset, never through Store.set.
local _, ns = ...
local W, L, Consent = ns.W, ns.L, ns.Consent

local S = {}
ns.ConsentSettings = S

local BUTTON_W = 220

-- Functions whose switches write for this character only, chosen in this session. A character that
-- already has values of its own counts as "char" without that.
local chosen = {}
-- Everything that repaints when a consent changes.
local live = setmetatable({}, { __mode = "k" })

local function mode(fn)
  if Consent.Overrides(fn) > 0 then
    return "char"
  end
  return chosen[fn] or "account"
end

local function scope(fn)
  return mode(fn) == "char" and "char" or "account"
end

local function refreshAll()
  for frame in pairs(live) do
    frame.Refresh()
  end
end

local function track(frame, refresh)
  frame.Refresh = refresh
  live[frame] = true
  return frame
end

local function dateText(t)
  local fmt = rawget(_G, "date")
  if type(fmt) ~= "function" or type(t) ~= "number" then
    return ""
  end
  local ok, text = pcall(fmt, "%d.%m.%Y", t)
  return ok and text or ""
end

-- The functions that exist in this build, in register order.
local function availableList()
  local out = {}
  for _, def in ipairs(Consent.List()) do
    if Consent.IsAvailable(def.id) then
      out[#out + 1] = def
    end
  end
  return out
end

-- Overview ---------------------------------------------------------------------------------------

local function counts()
  local total, active = 0, 0
  for _, def in ipairs(availableList()) do
    for _, dir in ipairs(def.directions) do
      for _, aud in ipairs(def.audiences) do
        total = total + 1
        if Consent.Allows(def.id, dir, aud) then
          active = active + 1
        end
      end
    end
  end
  return active, total
end

-- Functions of the tab whose switches write for this character only.
function S.CharModeCount()
  local n = 0
  for _, def in ipairs(availableList()) do
    if mode(def.id) == "char" then
      n = n + 1
    end
  end
  return n
end

local function onOff(on)
  return L[on and "common.on" or "common.off"]
end

-- "Send on, receive off. Last sent ..." and the reason below it, as text. "" for a function that does not report.
function S.StatusText(fn)
  local sync = rawget(ns, "ShareSync")
  local st = sync and sync.Status(fn)
  if not st then
    return ""
  end
  local function ago(value)
    if not value then
      return L["consent.status.never"]
    end
    return string.format(L["consent.status.ago"], math.floor(value + 0.5))
  end
  local text = string.format(
    L["consent.status.line"],
    onOff(st.send):lower(),
    onOff(st.receive):lower(),
    ago(st.lastSent),
    ago(st.lastHeard),
    st.heard
  )
  local why = st.reason and L["consent.why." .. st.reason]
  if why then
    text = text .. "\n" .. string.format(L["consent.status.why"], why)
  end
  return text
end

-- The text of the privacy info: the general part, then the information text of each function.
function S.PrivacyText()
  local parts = { L["consent.privacy.body"] }
  for _, def in ipairs(availableList()) do
    parts[#parts + 1] = L[def.labelKey] .. "\n" .. L[def.infoKey]
  end
  return table.concat(parts, "\n\n")
end

-- Bulk switches --------------------------------------------------------------------------------------
-- A target is { fn, aud }: a consent control of the setup step or an audience of a function in the tab.

local function functionCount(targets)
  local seen, n = {}, 0
  for _, t in ipairs(targets) do
    if not seen[t.fn] then
      seen[t.fn] = true
      n = n + 1
    end
  end
  return n
end

-- All audiences of the available functions that have this direction.
function S.BulkTargets(dir)
  local out = {}
  for _, def in ipairs(availableList()) do
    for _, d in ipairs(def.directions) do
      if d == dir then
        for _, aud in ipairs(def.audiences) do
          out[#out + 1] = { fn = def.id, aud = aud }
        end
      end
    end
  end
  return out
end

-- Functions, flags that are on and flags in total for one direction.
function S.BulkCounts(targets, dir)
  local on = 0
  for _, t in ipairs(targets) do
    if Consent.Allows(t.fn, dir, t.aud) then
      on = on + 1
    end
  end
  return functionCount(targets), on, #targets
end

-- Switches one direction of every target through write(target, value). Off acts at once. On is an explicit
-- act of the player and asks first (what is switched on, hint to the privacy info); nothing happens before
-- the confirmation. opts.allAudiences adds the line that every audience is included.
function S.BulkSwitch(targets, dir, value, write, opts)
  if #targets == 0 then
    return
  end
  local function run()
    for _, t in ipairs(targets) do
      write(t, value)
    end
  end
  if not value then
    run()
    return
  end
  local text = string.format(L["consent.bulk.confirm." .. dir], functionCount(targets))
  if opts and opts.allAudiences then
    text = text .. "\n" .. L["consent.bulk.confirm.aud"]
  end
  ns.Dialogs.Confirm("consent.bulk.title", nil, run, nil, { text = text })
end

-- "All on" and "all off" of one direction as two buttons: side by side, below each other when the room is too
-- narrow for the label. act(value) runs the switch. short: the labels "All on" and "All off" for a group that
-- sits under a column heading of its direction; the full label becomes the tooltip.
local BUTTON_GAP, LABEL_PAD = 8, 24

function S.BulkButtons(parent, dir, act, height, short)
  height = height or 28
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(height)
  local function button(value)
    local full = "consent.bulk." .. dir .. (value and ".on" or ".off")
    local b = W.Button(row, {
      key = short and (value and "consent.bulk.on" or "consent.bulk.off") or full,
      tooltip = short and full or nil,
      height = height,
      onClick = function()
        act(value)
      end,
    })
    b.fgId = "consent-bulk-" .. dir .. (value and "-on" or "-off")
    return b
  end
  row.on, row.off = button(true), button(false)
  function row:fgGridLayout(width)
    local need = math.max(self.on.label:GetStringWidth(), self.off.label:GetStringWidth()) + LABEL_PAD
    local beside = (width - BUTTON_GAP) / 2 >= need
    local half = math.floor((width - BUTTON_GAP) / 2)
    self.on:ClearAllPoints()
    self.off:ClearAllPoints()
    self.on:SetPoint("TOPLEFT")
    self.on:SetSize(beside and half or width, height)
    if beside then
      self.off:SetPoint("TOPLEFT", self.on, "TOPRIGHT", BUTTON_GAP, 0)
      self.off:SetSize(width - half - BUTTON_GAP, height)
    else
      self.off:SetPoint("TOPLEFT", self.on, "BOTTOMLEFT", 0, -4)
      self.off:SetSize(width, height)
    end
    local h = beside and height or 2 * height + 4
    self:SetHeight(h)
    return h
  end
  return row
end

-- Per direction: the buttons and what is on, for all audiences of the available functions.
local function bulkRows(view)
  for _, dir in ipairs({ "send", "receive" }) do
    local row = S.BulkButtons(view.content, dir, function(value)
      S.BulkSwitch(S.BulkTargets(dir), dir, value, function(t, v)
        Consent.Set(t.fn, dir, t.aud, v, "user", scope(t.fn))
      end, { allAudiences = true })
    end)
    view.stack:Add(row, { gap = 2 })
    local line = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 6 })
    line.fgId = "consent-bulk-count-" .. dir
    track(line, function()
      local _, on, total = S.BulkCounts(S.BulkTargets(dir), dir)
      line:SetText(string.format(L["consent.bulk.count." .. dir], on, total))
    end)
    local scopeNote = ns.AddParagraph(view, nil, { role = "micro", color = "textMuted", gap = 4 })
    scopeNote.fgId = "consent-bulk-scope-" .. dir
    track(scopeNote, function()
      local n = S.CharModeCount()
      scopeNote:SetText(n > 0 and string.format(L["consent.bulk.scope"], n) or "")
    end)
  end
end

local function overviewCard(view)
  local s = view.stack
  ns.AddHeading(view, "consent.title")
  ns.AddParagraph(view, "consent.default", { role = "ui", color = "text", gap = 6 })
  local count = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary", gap = 6 })
  count.fgId = "consent-count"
  track(count, function()
    local active, total = counts()
    count:SetText(string.format(L["consent.count"], active, total))
  end)
  local empty = ns.AddParagraph(view, "consent.empty", { role = "ui", color = "textMuted", gap = 6 })
  empty.fgId = "consent-empty"
  track(empty, function()
    empty:SetShown(#availableList() == 0)
  end)
  bulkRows(view)
  local withdraw = W.Action(view.content, {
    key = "consent.withdrawAll",
    variant = "danger",
    width = BUTTON_W,
    height = 28,
    onClick = function()
      ns.Dialogs.Confirm("consent.withdrawAll.title", "consent.withdrawAll.confirm", function()
        Consent.WithdrawAll("user")
        chosen = {}
        refreshAll()
      end)
    end,
  })
  withdraw.fgId = "consent-withdraw-all"
  s:Add(withdraw, { height = 28, width = BUTTON_W, gap = 6 })
  local privacy = W.Action(view.content, {
    key = "consent.privacy",
    width = BUTTON_W,
    height = 28,
    opens = true,
    onClick = function()
      ns.Dialogs.Copy("consent.privacy", S.PrivacyText(), "consent.privacy.hint")
    end,
  })
  privacy.fgId = "consent-privacy"
  s:Add(privacy, { height = 28, width = BUTTON_W, gap = 6 })
end

-- One function ------------------------------------------------------------------------------------

-- A switch with the date it was switched on behind it.
local function flagRow(card, def, dir, aud)
  local frame = CreateFrame("Frame", nil, card.content)
  local since = W.Text(frame, { role = "micro", color = "textMuted", justify = "RIGHT" })
  -- No width of its own: the date takes what it needs and the switch gets the rest, nothing while off.
  since:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
  local toggle = W.Toggle(frame, {
    key = "consent.aud." .. aud,
    get = function()
      return Consent.Allows(def.id, dir, aud)
    end,
    set = function(v)
      Consent.Set(def.id, dir, aud, v == true, "user", scope(def.id))
    end,
    tooltip = "consent.flag." .. dir .. "." .. aud,
    tooltipText = def.hintKey,
  })
  toggle:SetPoint("LEFT", frame, "LEFT", 0, 0)
  toggle:SetPoint("RIGHT", since, "LEFT", -8, 0)
  toggle.fgId = "consent-" .. def.id .. "-" .. dir .. "-" .. aud
  frame.fgId = "consent-row-" .. def.id .. "-" .. dir .. "-" .. aud
  return track(frame, function()
    toggle.Refresh()
    local t = Consent.Since(def.id, dir, aud)
    W.SetText(since, nil, t and string.format(L["consent.since"], dateText(t)) or "")
  end)
end

local function sizeText(bytes)
  if bytes < 1024 then
    return string.format("%d B", bytes)
  end
  return string.format("%.1f KB", bytes / 1024)
end

-- Crafting, receiving: what the directory of the guild holds on this PC and the button that deletes it.
local function directoryRows(card)
  local CD, s = ns.CraftDirectory, card.stack
  local line = ns.AddParagraph(card, nil, { role = "micro", color = "textSecondary", gap = 4 })
  line.fgId = "consent-crafting-stats"
  track(line, function()
    local st = CD.Stats()
    local size = sizeText(st.bytes)
    line:SetText(
      st.loaded and st.total > 0 and string.format(L["cv.stats"], st.members, st.sharing, st.total, size)
        or string.format(L["cv.statsShort"], st.members, size)
    )
  end)
  local clear = W.Action(card.content, {
    key = "cv.stats.clear",
    variant = "danger",
    width = BUTTON_W,
    height = 28,
    onClick = function()
      ns.Dialogs.Confirm("cv.stats.clear", "cv.stats.clear.confirm", function()
        CD.Clear()
        refreshAll()
      end)
    end,
  })
  clear.fgId = "consent-crafting-clear"
  s:Add(clear, { height = 28, width = BUTTON_W, gap = 6 })
end

-- Sections other modules add to the card of a function: build(card), run when the card is built. A switch of
-- a feature that needs the consent sits next to it this way.
local extras = {}

function S.AddExtra(fn, build)
  extras[fn] = extras[fn] or {}
  table.insert(extras[fn], build)
end

local function functionCard(card, def)
  local s = card.stack
  ns.AddHeading(card, def.labelKey)
  ns.AddParagraph(card, def.hintKey, { role = "ui", color = "textSecondary", gap = 6 })
  for _, dir in ipairs(def.directions) do
    ns.AddParagraph(card, "consent." .. dir, { role = "micro", color = "textMuted", gap = 2 })
    for _, aud in ipairs(def.audiences) do
      s:Add(flagRow(card, def, dir, aud), { height = 24, gap = 4 })
    end
  end
  ns.AddParagraph(card, "consent." .. def.id .. ".fields", { role = "micro", color = "textMuted", gap = 8 })
  local status = ns.AddParagraph(card, nil, { role = "micro", color = "textMuted", gap = 4 })
  status.fgId = "consent-" .. def.id .. "-status"
  track(status, function()
    status:SetText(S.StatusText(def.id))
  end)
  for _, build in ipairs(extras[def.id] or {}) do
    ns.Safe("consent-extra", build, card)
  end
  if rawget(ns, "CraftDirectory") and def.id == ns.CraftDirectory.FN then
    directoryRows(card)
  end
  local dropdown = W.Dropdown(card.content, {
    key = "consent.scope",
    width = 200,
    options = {
      { value = "account", key = "consent.scope.account" },
      { value = "char", key = "consent.scope.char" },
    },
    get = function()
      return mode(def.id)
    end,
    set = function(v)
      if v == "account" then
        chosen[def.id] = nil
        for _, dir in ipairs(def.directions) do
          for _, aud in ipairs(def.audiences) do
            Consent.Reset(def.id, dir, aud, "user")
          end
        end
      else
        chosen[def.id] = "char"
      end
      refreshAll()
    end,
  })
  dropdown.fgId = "consent-" .. def.id .. "-scope"
  live[dropdown] = true
  s:Add(dropdown, { height = 46, width = 200, gap = 6 })
  ns.AddParagraph(card, "consent.scope.hint", { role = "micro", color = "textMuted", gap = 2 })
  -- The grid hides a card without a visible entry, so a function that is not available shows nothing.
  local function show()
    local on = Consent.IsAvailable(def.id)
    for _, entry in ipairs(s.items) do
      entry.item:SetShown(on)
    end
  end
  track(card.frame, show)
  show()
end

-- Chat lines ------------------------------------------------------------------------------------------

local function names(list)
  return #list > 0 and table.concat(list, ", ") or L["consent.chat.none"]
end

-- The mirrored lines: label key and a function that answers the state as text.
local MIRRORS = {
  {
    "consent.chat.reset",
    function()
      return onOff(ns.InstanceReset.Announce())
    end,
  },
  {
    "consent.chat.xp",
    function()
      local cfg = ns.db.settings.xpBar
      local out = {}
      if type(cfg) == "table" and cfg.chatLevelUp == true then
        local channels = ns.XpTracker.ChatChannels()
        for _, item in ipairs({
          { "group", "consent.aud.group" },
          { "guild", "consent.aud.guild" },
          { "say", "consent.chat.say" },
        }) do
          if channels[item[1]] then
            out[#out + 1] = L[item[2]]
          end
        end
      end
      return names(out)
    end,
  },
  {
    "consent.chat.invite",
    function()
      local s = ns.db.settings
      local out = {}
      if s.inviteGroup == true and s.inviteGroupReplyOn == true then
        out[#out + 1] = L["consent.aud.group"]
      end
      if s.inviteGuild == true and s.inviteGuildReplyOn == true then
        out[#out + 1] = L["consent.aud.guild"]
      end
      return names(out)
    end,
  },
}

local function chatCard(view)
  ns.AddHeading(view, "consent.chat.title")
  ns.AddParagraph(view, "consent.chat.hint", { role = "micro", color = "textMuted", gap = 6 })
  for i, mirror in ipairs(MIRRORS) do
    local line = ns.AddParagraph(view, nil, { role = "ui", color = "textSecondary", gap = 4 })
    line.fgId = "consent-chat-" .. i
    track(line, function()
      local ok, state = pcall(mirror[2])
      line:SetText(L[mirror[1]] .. ": " .. (ok and state or ""))
    end)
  end
  ns.AddParagraph(view, "consent.chat.inspect", { role = "micro", color = "textMuted", gap = 4 })
  ns.AddParagraph(view, "consent.chat.who", { role = "micro", color = "textMuted", gap = 2 })
end

-- The tab: the overview in the card it is given, a card per function and the chat lines after it.
function S.Add(view)
  overviewCard(view)
  local grid = view.grid
  for _, def in ipairs(Consent.List()) do
    functionCard(grid:Card(), def)
  end
  chatCard(grid:Card())
  refreshAll()
end

ns.On("FG_CRAFT_UPDATE", refreshAll)
ns.On("FG_SHARE_STATUS", refreshAll)
ns.On("FG_CONSENT_CHANGED", refreshAll)
ns.On("FG_CONSENT_WITHDRAWN", refreshAll)
