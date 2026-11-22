-- Page "Console" of the main window (group ADDON, behind the game window tweaks): sliders, switches and lists for the console variables of
-- Data/ConsoleVars.lua, grouped in cards that flow into one to three columns, plus profile buttons. Every
-- change goes through Modules/ConsoleLogic.lua (write, read back, show what the client kept). In combat the
-- controls are locked, nothing is queued.
local _, ns = ...
local W, L, Theme = ns.W, ns.L, ns.Theme
local CL, D = ns.ConsoleLogic, ns.ConsoleVars

local P = {}
ns.ConsolePage = P

local CARD_MIN_W = 280
local RENDER_FORMATS = { ["0"] = "BGRA8", ["1"] = "A2BGR10", ["2"] = "RGBA16F", ["3"] = "RGBA32F" }

-- The pages that are built, kept weakly: the combat events lock and unlock all of them.
local pages = setmetatable({}, { __mode = "k" })
P.combatEvent = false

local function idOf(key)
  return (key:gsub("%.", "-"))
end

-- Texts ----------------------------------------------------------------------------------------------

-- Dropdown entry of one option value.
local function optionSpec(var, value)
  value = tostring(value)
  if var.name == "renderFormat" then
    return { value = value, text = value .. ": " .. (RENDER_FORMATS[value] or value) }
  end
  return { value = value, text = value:upper() }
end

-- The option whose value the client reports (the client may answer in another case).
local function matchOption(var, raw)
  for _, v in ipairs(var.options or {}) do
    if CL.Same(raw, tostring(v)) then
      return tostring(v)
    end
  end
  return raw
end

function P.ShowValue(var, raw)
  if raw == nil then
    return "?"
  end
  if var.kind == "toggle" then
    local n = tonumber(raw)
    if n then
      return n ~= 0 and L["common.on"] or L["common.off"]
    end
  elseif var.kind == "choice" then
    return optionSpec(var, matchOption(var, raw)).text
  end
  local n = tonumber(raw)
  return n and CL.Fmt(n) or tostring(raw)
end

-- One line after a profile or reset run.
function P.SummaryText(sum)
  if sum.blocked then
    return L["console.blockedCombat"]
  elseif sum.empty then
    return L["console.result.empty"]
  end
  local parts = { string.format(L["console.result"], sum.applied) }
  if #sum.clamped > 0 then
    parts[#parts + 1] = string.format(L["console.result.clamped"], #sum.clamped)
  end
  if sum.missing > 0 then
    parts[#parts + 1] = string.format(L["console.result.missing"], sum.missing)
  end
  if (sum.skipped or 0) > 0 then
    parts[#parts + 1] = string.format(L["console.result.skipped"], sum.skipped)
  end
  if sum.failed > 0 then
    parts[#parts + 1] = string.format(L["console.result.failed"], sum.failed)
  end
  if sum.restart then
    parts[#parts + 1] = L["console.result.restart"]
  end
  return table.concat(parts, " ")
end

-- Layout ---------------------------------------------------------------------------------------------

-- Places buttons in rows that wrap at `inner`; answers the y below the last row.
local function placeRow(host, items, pad, y, inner, gap)
  local x, rowH = 0, 0
  for _, b in ipairs(items) do
    local w = math.min(inner, math.max(b:Fit(inner), 1))
    b:SetWidth(w)
    if x > 0 and x + w > inner then
      x, y, rowH = 0, y + rowH + gap, 0
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", host, "TOPLEFT", pad + x, -y)
    x = x + w + gap
    rowH = math.max(rowH, b:GetHeight())
  end
  return y + rowH
end

local function textHeight(fs)
  return math.ceil(fs:GetStringHeight())
end

local function layoutCard(card, cw)
  local pad = card.pad
  local inner = math.max(1, cw - pad * 2)
  -- The name wraps instead of being cut, so the card is as high as its text needs.
  card.title:SetWidth(inner)
  card.title:ClearAllPoints()
  card.title:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -pad)
  local y = pad + textHeight(card.title) + 6
  card.info:SetWidth(inner)
  card.info:ClearAllPoints()
  card.info:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -y)
  y = y + textHeight(card.info) + 4
  local hasNote = card.note:GetText() ~= nil and card.note:GetText() ~= ""
  card.note:SetShown(hasNote)
  if hasNote then
    card.note:SetWidth(inner)
    card.note:ClearAllPoints()
    card.note:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -y)
    y = y + textHeight(card.note) + 4
  end
  y = y + 4
  local control = card.control
  -- A secure variable has nothing to set: only the command button stays.
  control:SetShown(not card.secure)
  card.reset:SetShown(not card.secure)
  if not card.secure then
    control:SetWidth(inner)
    if card.var.kind == "choice" then
      control.button:SetWidth(inner)
    end
    control:ClearAllPoints()
    control:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -y)
    y = y + (card.var.kind == "slider" and 24 or 28)
  end
  y = placeRow(card, card.secure and { card.cmd } or { card.reset, card.cmd }, pad, y, inner, Theme.space.sm)
  return y + pad
end

-- Cards of one group in one to three columns, every card as high as its content.
local function attachFlow(flow, cards)
  function flow:fgGridLayout(width)
    local gap = Theme.space.md
    local cols, cw = ns.CardFlow.Columns(width, CARD_MIN_W, gap)
    local heights = {}
    for i, card in ipairs(cards) do
      card:SetWidth(cw)
      heights[i] = layoutCard(card, cw)
      card:SetHeight(heights[i])
    end
    local spots, total = ns.CardFlow.Place(heights, cols, cw, gap)
    for i, card in ipairs(cards) do
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", self, "TOPLEFT", spots[i].x, -spots[i].y)
    end
    self:SetHeight(total)
    return total
  end
end

-- One card per variable ------------------------------------------------------------------------------

-- Writes a value and, with the raid option on, to the raid twin too. Returns the result of the main variable.
local function write(ctx, var, value)
  local r = CL.Apply(ctx.api, var.name, value)
  if r.ok and CL.RaidOn() then
    local twin = CL.RaidTwin(ctx.api, var.name)
    if twin then
      CL.Apply(ctx.api, twin, value)
    end
  end
  return r
end

local function setControlEnabled(card, on)
  local control = card.control
  if control.SetEnabled then
    control:SetEnabled(on)
  end
  if card.var.kind == "choice" then
    control.button:SetEnabled(on)
  end
  control:SetAlpha(on and 1 or 0.5)
  card.reset:SetEnabled(on)
  -- The command text only reads, so it stays available.
end

local function refreshCard(ctx, card)
  local var = card.var
  local info = CL.Info(ctx.api, var.name)
  card.current = info.current
  card.secure = info.exists and CL.IsSecure(ctx.api, var.name)
  -- The client may hold a value outside the offered list: it stays selectable (and the list stays sorted).
  if card.options and info.current ~= nil then
    local known = false
    for _, o in ipairs(card.options) do
      known = known or CL.Same(o.value, info.current)
    end
    if not known then
      card.options[#card.options + 1] = optionSpec(var, CL.Normalize(info.current))
      table.sort(card.options, function(a, b)
        return (tonumber(a.value) or 0) < (tonumber(b.value) or 0)
      end)
    end
  end
  if not info.exists then
    card.info:SetText(L["console.unavailable"])
  elseif info.default ~= nil then
    card.info:SetText(
      string.format(L["console.current"], P.ShowValue(var, info.current), P.ShowValue(var, info.default))
    )
  else
    card.info:SetText(string.format(L["console.currentNoDefault"], P.ShowValue(var, info.current)))
  end
  local notes = {}
  if card.message then
    notes[#notes + 1] = card.message
  end
  if var.status == "check" then
    notes[#notes + 1] = L["console.unchecked"]
  elseif var.status == "unverified" then
    notes[#notes + 1] = L["console.unverified"]
  end
  if card.secure then
    notes[#notes + 1] = L["console.secure"]
  elseif card.presetGroup then
    notes[#notes + 1] = L["console.presetNote"]
  end
  if var.restart then
    notes[#notes + 1] = L["console.needsRestart"]
  elseif var.reload then
    notes[#notes + 1] = L["console.needsReload"]
  end
  card.note:SetText(table.concat(notes, " "))
  if info.exists then
    local control = card.control
    if var.kind == "slider" then
      local n = tonumber(info.current)
      if n then
        -- The range opens up to the client value so opening the page never moves the user's setting.
        control:SetRange(math.min(var.min, n), math.max(var.max, n))
        control:Sync(n)
      end
    elseif control.Refresh then
      control.Refresh()
    end
  end
  setControlEnabled(card, info.exists and not card.secure and not ctx.inCombat())
end

-- After a write: the message tells what the client did with the value.
local function commit(ctx, card, value)
  local var = card.var
  -- CVAR_UPDATE can fire inside SetCVar while the client still answers the old value: the card is
  -- refreshed once, after the read back, so a stale event never moves the control.
  ctx.writing = true
  local r = write(ctx, var, value)
  ctx.writing = false
  card.message, card.messageValue = nil, r.got
  if r.reason == "combat" then
    card.message = L["console.blockedCombat"]
  elseif r.reason == "missing" then
    card.message = L["console.unavailable"]
  elseif not r.ok then
    card.message = L["console.rejected"]
  elseif r.ignored then
    card.message = L["console.ignored"]
  elseif r.clamped then
    card.message = string.format(L["console.clamped"], P.ShowValue(var, r.got), P.ShowValue(var, r.want))
  end
  refreshCard(ctx, card)
  ctx.view:Layout()
end

local function newControl(ctx, card)
  local var = card.var
  local labelKey = "console.v." .. var.name
  local tipKey = labelKey .. ".tip"
  if var.kind == "slider" then
    return W.CompactSlider(card, {
      min = var.min,
      max = var.max,
      step = var.step,
      height = 14,
      applyOn = "release",
      preview = function(v)
        card.info:SetText(string.format(L["console.currentNoDefault"], CL.Fmt(v)))
      end,
      set = function(v)
        commit(ctx, card, v)
      end,
      tooltip = labelKey,
      tooltipText = tipKey,
    })
  elseif var.kind == "toggle" then
    return W.Toggle(card, {
      key = labelKey,
      compact = true,
      get = function()
        local n = tonumber(card.current)
        return n ~= nil and n ~= 0
      end,
      set = function(on)
        commit(ctx, card, on and "1" or "0")
      end,
      tooltip = labelKey,
      tooltipText = tipKey,
    })
  end
  local options = {}
  for _, v in ipairs(var.options) do
    options[#options + 1] = optionSpec(var, v)
  end
  card.options = options
  return W.Dropdown(card, {
    key = labelKey,
    compact = true,
    options = options,
    get = function()
      for _, o in ipairs(options) do
        if card.current and CL.Same(card.current, o.value) then
          return o.value
        end
      end
      return nil
    end,
    set = function(value)
      commit(ctx, card, value)
    end,
    tooltip = labelKey,
    tooltipText = tipKey,
  })
end

local function newCard(ctx, parent, var, groupGfx)
  local labelKey = "console.v." .. var.name
  local card = W.Card(parent)
  card.title = W.Text(card, { key = labelKey, role = "h3", family = "heading", color = "accent2", wrap = true })
  card.var = var
  card.presetGroup = groupGfx and not var.preset or nil
  card.fgId = idOf(labelKey)
  card.info = W.Text(card, { role = "small", color = "textSecondary", wrap = true })
  card.note = W.Text(card, { role = "small", color = "warning", wrap = true })
  card.control = newControl(ctx, card)
  card.control.fgId = card.fgId
  card.reset = W.Action(card, {
    key = "console.reset",
    size = 24,
    tooltip = "console.reset",
    tooltipText = "console.reset.tip",
    wrap = "console-reset",
    onClick = function()
      local info = CL.Info(ctx.api, var.name)
      if info.default ~= nil then
        commit(ctx, card, info.default)
      end
    end,
  })
  card.cmd = W.Action(card, {
    key = "console.cmd",
    size = 24,
    tooltip = "console.cmd",
    tooltipText = "console.cmd.tip",
    wrap = "console-cmd",
    opens = true,
    onClick = function()
      -- A secure value is typed by hand, so the dialog starts from the client default.
      local value = card.secure and (CL.Info(ctx.api, var.name).default or card.current) or card.current
      local text = value ~= nil and CL.Command(var.name, value) or ("/console " .. var.name)
      ns.Dialogs.Copy("console.copy.title", text, "console.copy.hint")
    end,
  })
  return card
end

-- Profile card ---------------------------------------------------------------------------------------

local function newProfileCard(ctx, parent)
  local card = W.Card(parent, { key = "console.profiles" })
  local pad = card.pad
  local hint = W.Text(card, { key = "console.profiles.hint", role = "text", color = "textSecondary", wrap = true })
  local status = W.Text(card, { role = "ui", color = "text", wrap = true })
  local snapshot = W.Text(card, { role = "small", color = "textSecondary", wrap = true })
  local store = CL.CharStore()
  card.status = status

  local function button(key, tipKey, variant, onClick, opens)
    return W.Action(card, {
      key = key,
      size = 28,
      variant = variant,
      tooltip = key,
      tooltipText = tipKey,
      wrap = "console-" .. key,
      onClick = onClick,
      opens = opens,
    })
  end

  local function report(sum)
    status:SetText(P.SummaryText(sum))
    ctx.refreshAll()
  end

  card.max = button("console.profile.max", "console.profile.maxTip", "primary", function()
    report(CL.ApplyProfile(ctx.api, store, "max", CL.RaidOn()))
  end)
  card.perf = button("console.profile.perf", "console.profile.perfTip", "secondary", function()
    report(CL.ApplyProfile(ctx.api, store, "perf", CL.RaidOn()))
  end)
  card.undo = button("console.profile.undo", "console.profile.undoTip", "secondary", function()
    report(CL.Restore(ctx.api, store))
  end)
  card.defaults = button("console.profile.defaults", "console.profile.defaultsTip", "secondary", function()
    report(CL.ResetAll(ctx.api, store, CL.RaidOn()))
  end)
  card.restart = button("console.restart", "console.restart.tip", "secondary", function()
    if ctx.inCombat() then
      status:SetText(L["console.blockedCombat"])
      return
    end
    ns.Dialogs.Confirm("console.restart.title", "console.restart.text", function()
      ctx.api.restart()
    end)
  end, true)
  card.copyAll = button("console.copyAll", "console.copyAll.tip", "secondary", function()
    local names = {}
    for _, var in ipairs(D.vars) do
      names[#names + 1] = var.name
    end
    ns.Dialogs.Copy("console.copy.title", CL.CommandText(ctx.api, names), "console.copy.hint")
  end, true)
  card.raid = W.Toggle(card, {
    key = "console.raid",
    get = CL.RaidOn,
    set = function(on)
      CL.SetRaid(on)
    end,
    tooltip = "console.raid",
    tooltipText = "console.raid.tip",
  })
  card.raid.fgId = idOf("console.raid")

  function card:Refresh()
    local snap = store.load()
    local has = type(snap) == "table" and type(snap.names) == "table" and #snap.names > 0
    if has then
      snapshot:SetText(string.format(L["console.snapshot"], L["console.snapshot." .. tostring(snap.label)]))
    else
      snapshot:SetText(L["console.snapshot.none"])
    end
    local free = not ctx.inCombat()
    for _, b in ipairs({ self.max, self.perf, self.defaults, self.restart }) do
      b:SetEnabled(free)
    end
    self.undo:SetEnabled(free and has)
    self.raid:Refresh()
  end

  function card:fgGridLayout(width)
    local inner = math.max(1, width - pad * 2)
    local y = -self.contentTop
    hint:SetWidth(inner)
    hint:ClearAllPoints()
    hint:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -y)
    y = y + textHeight(hint) + Theme.space.sm
    y = placeRow(self, { self.max, self.perf, self.undo, self.defaults }, pad, y, inner, Theme.space.sm)
    y = y + Theme.space.sm
    self.raid:SetWidth(math.min(inner, 320))
    self.raid:ClearAllPoints()
    self.raid:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -y)
    -- The label wraps in a narrow card, the row grows with it.
    y = y + self.raid:fgGridLayout(math.min(inner, 320)) + Theme.space.sm
    y = placeRow(self, { self.restart, self.copyAll }, pad, y, inner, Theme.space.sm)
    y = y + Theme.space.sm
    status:SetWidth(inner)
    status:ClearAllPoints()
    status:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -y)
    y = y + math.max(textHeight(status), 16) + 2
    snapshot:SetWidth(inner)
    snapshot:ClearAllPoints()
    snapshot:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -y)
    y = y + textHeight(snapshot) + pad
    self:SetHeight(y)
    return y
  end
  return card
end

-- Page -----------------------------------------------------------------------------------------------

-- api: the client access (tests pass a fake). Returns the view with view.cards.
function P.Build(container, api)
  local view = ns.NewPageView(container)
  local ctx = { api = api or CL.RealApi(), view = view }
  function ctx.inCombat()
    return P.combatEvent or ctx.api.combat()
  end
  ns.AddIntro(view, "console.hint")
  local banner = W.Text(view.content, { key = "console.combat", role = "ui", color = "warning", wrap = true })
  view.stack:Add(banner, { gap = Theme.space.md })

  local cards = {}
  ctx.profile = newProfileCard(ctx, view.content)
  view.stack:Add(ctx.profile, {})
  for _, group in ipairs(D.groups) do
    local groupCards = {}
    local flow = CreateFrame("Frame", nil, view.content)
    for _, var in ipairs(D.vars) do
      if var.group == group.id then
        local card = newCard(ctx, flow, var, group.gfx)
        groupCards[#groupCards + 1] = card
        cards[#cards + 1] = card
      end
    end
    attachFlow(flow, groupCards)
    ns.AddHeading(view, "console.group." .. group.id)
    view.stack:Add(flow, {})
  end

  local byLower = {}
  for _, card in ipairs(cards) do
    byLower[card.var.name:lower()] = card
  end
  function ctx.refreshAll()
    banner:SetShown(ctx.inCombat())
    ctx.profile:Refresh()
    for _, card in ipairs(cards) do
      refreshCard(ctx, card)
    end
    view:Layout()
  end
  function view:Show()
    ctx.refreshAll()
  end
  -- Changed elsewhere (game menu, /console, another addon): refresh the one card.
  function ctx.cvarChanged(name)
    local card = byLower[type(name) == "string" and name:lower() or ""]
    if card and not ctx.writing then
      -- A note about our own write stays until the value moves on (another source changed it).
      if card.message and not CL.Same(ctx.api.get(card.var.name), card.messageValue) then
        card.message = nil
      end
      refreshCard(ctx, card)
      view:Layout()
    end
  end
  view.cards, view.ctx, view.profile = cards, ctx, ctx.profile
  pages[view] = ctx
  ctx.refreshAll()
  return view
end

ns.On("CVAR_UPDATE", function(_, name)
  for _, ctx in pairs(pages) do
    if ctx.view.content:IsVisible() then
      ctx.cvarChanged(name)
    end
  end
end)

ns.On("PLAYER_REGEN_DISABLED", function()
  P.combatEvent = true
  for _, ctx in pairs(pages) do
    ctx.refreshAll()
  end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  P.combatEvent = false
  for _, ctx in pairs(pages) do
    ctx.refreshAll()
  end
end)

ns.RegisterPage({
  id = "console",
  order = 745,
  group = "system",
  title = "page.console",
  icon = ns.ICONS.console,
  aliases = {
    "konsole",
    "console",
    "grafik",
    "graphics",
    "cvar",
    "cvars",
    "fps",
    "sichtweite",
    "schatten",
    "kamera",
    "camera",
    "performance",
  },
  build = function(container)
    return P.Build(container)
  end,
})
