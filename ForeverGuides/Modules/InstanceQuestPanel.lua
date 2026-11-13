-- Detail panel of the quests tab, right of the list of Modules/QuestChainView.lua, built like the quest log: title
-- with the quest icon, objectives, description, rewards (choice and fixed items as tiles in two columns, then
-- experience and money), then the fields of the quest (giver with map buttons, hand-in, prerequisites and
-- follow-ups as links, the other wings that list it) and the button that opens the share dialog. A field the data does not have is left
-- out, nothing is guessed. Description and goal come from Modules/QuestText.lua; for a quest in the own quest
-- log the goal also lists the objective lines of the client.
-- Nothing is sent from here: the share dialog sends after its own click, and the quest log call that pushes a
-- quest to the group is never used (docs/TAINT-AUDIT.md).
local _, ns = ...
local W, L, Theme, QW, IV, QL = ns.W, ns.L, ns.Theme, ns.QuestChainWindow, ns.InstanceView, ns.QuestListLogic

ns.AddLocale("enUS", {
  ["questpanel.start"] = "Accepted",
  ["questpanel.start.inside"] = "Inside the instance",
  ["questpanel.start.outside"] = "Outside",
  ["questpanel.start.item"] = "item %s",
  ["questpanel.finish"] = "Hand in at",
  ["questpanel.pre"] = "Requires",
  ["questpanel.next"] = "Then",
  ["questpanel.chain"] = "Chain",
  ["questpanel.goal"] = "Goal",
  ["questpanel.desc"] = "Description",
  ["questpanel.reward"] = "Rewards",
  ["questpanel.rewardChoice"] = "You will be able to choose one of these rewards:",
  ["questpanel.rewardFixed"] = "You will also receive:",
  ["questpanel.also"] = "Also in",
  ["questpanel.alsoTip"] = "Opens the quests of this wing.",
  ["questpanel.empty"] = "Pick a quest from the list.",
  ["questpanel.shareTip"] = "Opens the share dialog.\nNothing is sent before you click Send.",
  ["questpanel.linkSelect"] = "Shows this quest in the list.",
  ["questpanel.quality.0"] = "Quality: Poor",
  ["questpanel.quality.1"] = "Quality: Common",
  ["questpanel.quality.2"] = "Quality: Uncommon",
  ["questpanel.quality.3"] = "Quality: Rare",
  ["questpanel.quality.4"] = "Quality: Epic",
  ["questpanel.quality.5"] = "Quality: Legendary",
})

ns.AddLocale("deDE", {
  ["questpanel.start"] = "Annahme",
  ["questpanel.start.inside"] = "In der Instanz",
  ["questpanel.start.outside"] = "Außerhalb",
  ["questpanel.start.item"] = "Gegenstand %s",
  ["questpanel.finish"] = "Abgeben bei",
  ["questpanel.pre"] = "Voraussetzung",
  ["questpanel.next"] = "Danach",
  ["questpanel.chain"] = "Reihe",
  ["questpanel.goal"] = "Ziel",
  ["questpanel.desc"] = "Beschreibung",
  ["questpanel.reward"] = "Belohnungen",
  ["questpanel.rewardChoice"] = "Auf Euch wartet eine dieser Belohnungen:",
  ["questpanel.rewardFixed"] = "Ihr bekommt außerdem:",
  ["questpanel.also"] = "Auch in",
  ["questpanel.alsoTip"] = "Öffnet die Quests dieses Flügels.",
  ["questpanel.empty"] = "Wähle eine Quest aus der Liste.",
  ["questpanel.shareTip"] = "Öffnet den Teilen-Dialog.\nGesendet wird erst nach Klick auf Senden.",
  ["questpanel.linkSelect"] = "Zeigt diese Quest in der Liste.",
  ["questpanel.quality.0"] = "Qualität: Schlecht",
  ["questpanel.quality.1"] = "Qualität: Gewöhnlich",
  ["questpanel.quality.2"] = "Qualität: Ungewöhnlich",
  ["questpanel.quality.3"] = "Qualität: Selten",
  ["questpanel.quality.4"] = "Qualität: Episch",
  ["questpanel.quality.5"] = "Qualität: Legendär",
})

local P = {}
ns.InstanceQuestPanel = P

local PAD, GAP, ROW_GAP = 12, 8, 6
local ICON = 24
local BUTTON_H = 24
-- Narrowest tile of the reward grid: icon plus a short name.
local TILE_MIN = 120
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

local function ceil(fs)
  return math.ceil(fs:GetStringHeight())
end

local function name(quest)
  return ns.T(quest.n)
end

-- Client reads -------------------------------------------------------------------------------------------

-- The value, or nil when it is secret or not readable for the addon.
local function safe(value)
  local guard = ns.AutoGuard
  return guard and guard.Safe(value) or nil
end

local function inQuestLog(id)
  local log = rawget(_G, "C_QuestLog")
  local fn = type(log) == "table" and log.GetLogIndexForQuestID or rawget(_G, "GetQuestLogIndexByID")
  if type(fn) ~= "function" then
    return false
  end
  local ok, index = pcall(fn, id)
  index = ok and safe(index) or nil
  return type(index) == "number" and index > 0
end

-- The objective lines of a quest that is in the own quest log, else nil (the data has no goal text).
function P.Goal(id)
  if type(id) ~= "number" or not inQuestLog(id) then
    return nil
  end
  local log = rawget(_G, "C_QuestLog")
  if type(log) ~= "table" or type(log.GetQuestObjectives) ~= "function" then
    return nil
  end
  local ok, objectives = pcall(log.GetQuestObjectives, id)
  objectives = ok and safe(objectives) or nil
  if type(objectives) ~= "table" then
    return nil
  end
  local lines = {}
  for _, objective in ipairs(objectives) do
    local text = type(objective) == "table" and safe(objective.text) or nil
    if type(text) == "string" and text ~= "" then
      lines[#lines + 1] = text
    end
  end
  return #lines > 0 and table.concat(lines, "\n") or nil
end

-- Share text -------------------------------------------------------------------------------------------

-- One chat line: quest link (only with a quest id), instance, quest level and giver. The link carries the
-- quest level the client expects, 0 when the data has none.
function P.ShareText(entry, inst)
  local q = entry.quest
  local quest = name(q) or "?"
  local parts = {}
  if type(q.id) == "number" then
    parts[1] = string.format("|Hquest:%d:%d|h[%s]|h", q.id, entry.level or 0, quest)
  else
    parts[1] = quest
  end
  local place = inst and name(inst)
  if place then
    parts[#parts + 1] = place
  end
  if entry.level then
    parts[#parts + 1] = string.format(L["questchain.level"], entry.level)
  end
  if entry.giver then
    parts[#parts + 1] = string.format(L["questchain.giver"], entry.giver)
  end
  return table.concat(parts, ", ")
end

-- Texts ------------------------------------------------------------------------------------------------

-- "Available from level 10 · Quest level 23 · Alliance": the levels the data has, the faction always.
local function subLine(entry)
  local bits = {}
  local avail = entry.avail
  if avail and avail.kind ~= "hint" then
    bits[#bits + 1] = string.format(L["questchain.from"], avail.level)
  end
  if entry.level then
    bits[#bits + 1] = string.format(L["questchain.level"], entry.level)
  end
  bits[#bits + 1] = QW.FactionText(entry.faction)
  if entry.access then
    bits[#bits + 1] = L["questchain.tag.access"]
  end
  return table.concat(bits, " · ")
end

-- Where the quest is accepted, led by "Inside the instance" (accent color plus the words) or "Outside" when the
-- data tells. Inside names the giver or the item that starts the quest, outside the giver with its zone. Without
-- that knowledge the giver and zone stand alone, without a marker.
local function startText(entry)
  local zone = entry.zone and ns.T(entry.zone)
  local text = entry.giver and (zone and string.format("%s (%s)", entry.giver, zone) or entry.giver) or zone
  local inside = ns.QuestChainLogic.StartsInside(entry.inst, entry)
  if inside == nil then
    return text
  end
  if inside then
    local item = entry.startItem and string.format(L["questpanel.start.item"], IV.ItemName({ id = entry.startItem }))
    local detail = entry.giver or item or text
    local head = Theme.hexText("accent2", L["questpanel.start.inside"])
    return detail and (head .. ": " .. detail) or head
  end
  local head = L["questpanel.start.outside"]
  return text and (head .. ": " .. text) or head
end

local function moneyText(gold)
  return ns.CostLogic and ns.CostLogic.Format(gold) or nil
end

-- Experience and money of the quest as one line, nil when the data has neither.
local function payText(entry)
  local bits = {}
  if entry.xp and entry.xp > 0 then
    bits[#bits + 1] = string.format(L["questchain.xp"], entry.xp)
  end
  if entry.gold and entry.gold > 0 then
    bits[#bits + 1] = moneyText(entry.gold)
  end
  return #bits > 0 and table.concat(bits, " · ") or nil
end

-- Reward rows: icon and name in the quality color, the tooltip is the item tooltip plus the quality word. The
-- row is no button, it has no action, only the tooltip on hover and on keyboard focus.
local function makeReward(panel)
  local row = CreateFrame("Frame", nil, panel)
  row:EnableMouse(true)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.text = W.Text(row, { role = "ui", color = "text", wrap = true })
  local function show()
    local r = row.reward
    if not r then
      return
    end
    local lines = {}
    if row.quality and L["questpanel.quality." .. row.quality] then
      lines[1] = L["questpanel.quality." .. row.quality]
    end
    W.Tooltip.Show(row, { link = r.id and ("item:" .. r.id) or nil, title = row.itemName, lines = lines })
  end
  row:SetScript("OnEnter", show)
  row:SetScript("OnLeave", ns.HideTooltip)
  row.fgOnFocus, row.fgOnBlur = show, ns.HideTooltip
  row.fgName = function()
    return row.label
  end
  row.fgDescription = function()
    return row.quality and L["questpanel.quality." .. row.quality] or nil
  end
  ns.Focus.register(row, function() end)

  function row:fgLayout(width)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.text:ClearAllPoints()
    self.text:SetPoint("TOPLEFT", self, "TOPLEFT", ICON + GAP, 0)
    self.text:SetWidth(math.max(40, width - ICON - GAP))
    return math.max(ICON, ceil(self.text)) + 2
  end
  return row
end

-- tile: a tile of QL.Rewards ({ id, name, count, choice }).
local function paintReward(row, tile)
  row.reward = tile
  row.itemName = tile.name
  row.quality = tile.id and IV.ItemQuality(tile.id) or nil
  local label = tile.count and (tile.count .. "x " .. tile.name) or tile.name
  -- The group heading says "choice", the keyboard name carries it too.
  row.text:SetText(ns.ItemInfo.ColorName(label, row.quality))
  if tile.choice then
    label = label .. " (" .. L["instances.quest.choice"] .. ")"
  end
  row.label = label
  row.icon:SetTexture(IV.ItemIcon(tile.id))
end

-- Panel -------------------------------------------------------------------------------------------------

local function bindTip(button, tip)
  button:HookScript("OnEnter", function()
    ns.ShowTooltip(button, tip.title(), tip.text and tip.text(), tip.hint and { hint = tip.hint() } or nil)
  end)
  button:HookScript("OnLeave", ns.HideTooltip)
  button.fgOnFocus = function()
    ns.ShowTooltip(button, tip.title(), tip.text and tip.text(), tip.hint and { hint = tip.hint() } or nil)
  end
  button.fgOnBlur = ns.HideTooltip
end

-- One link button of the prerequisite and follow-up fields. `ref` is what QC.Reference returned.
local function makeLink(panel)
  local b
  b = W.Action(panel, {
    text = "",
    variant = "secondary",
    height = BUTTON_H,
    wrap = "questpanel-link",
    onClick = function()
      if b.ref and panel.ctx then
        panel.ctx.go(b.ref)
      end
    end,
  })
  b.fgName = function()
    return b.ref and b.ref.name or nil
  end
  b.fgDescription = function()
    return b.ref and b.ref.kind == "open" and L["action.opensWindow"] or nil
  end
  bindTip(b, {
    title = function()
      return b.ref and b.ref.name or ""
    end,
    text = function()
      return b.ref and b.ref.kind == "open" and L["questchain.openTip"] or L["questpanel.linkSelect"]
    end,
    hint = function()
      return b.ref and b.ref.kind == "open" and L["action.opensWindow"] or ""
    end,
  })
  return b
end

-- One button of the "Also in" field: opens the quests of another wing that lists the quest.
local function makeAlso(panel)
  local b
  b = W.Action(panel, {
    text = "",
    variant = "secondary",
    height = BUTTON_H,
    wrap = "questpanel-also",
    onClick = function()
      if b.inst then
        ns.Router:navigate("instances/" .. ns.RefLogic.InstanceSlug(b.inst) .. "/quests")
      end
    end,
  })
  b.fgName = function()
    return b.inst and name(b.inst) or nil
  end
  bindTip(b, {
    title = function()
      return b.inst and name(b.inst) or ""
    end,
    text = function()
      return L["questpanel.alsoTip"]
    end,
  })
  return b
end

local function pooled(panel, pool, index, make)
  local item = pool[index]
  if not item then
    item = make(panel)
    pool[index] = item
  end
  return item
end

-- parent: the frame the panel sits in. Methods: :SetQuest(entry, ctx), :fgGridLayout(width) -> height,
-- :Stops() -> the focus stops in display order, :FocusFirst() -> true when one took the focus.
-- ctx: { inst, chainLength, resolve(id) -> reference, go(reference), openChain() }; the panel only shows what
-- QC.Reference describes and hands a click back through ctx.go. .onChange(): asks the owner for a layout.
function P.Create(parent)
  local panel = CreateFrame("Frame", nil, parent)
  W.Fill(panel, "surface", 1)
  panel.pre, panel.nxt, panel.also, panel.rewards = {}, {}, {}, {}
  panel.nChoice, panel.nTiles = 0, 0

  panel.empty = W.Text(panel, { key = "questpanel.empty", role = "ui", color = "textSecondary", wrap = true })
  panel.icon = panel:CreateTexture(nil, "ARTWORK")
  panel.icon:SetSize(ICON, ICON)
  panel.icon:SetTexture(QUEST_ICON)
  panel.title = W.Text(panel, { role = "h3", color = "text", wrap = true })
  panel.sub = W.Text(panel, { role = "ui", color = "textSecondary", wrap = true })
  panel.weak = W.Text(panel, { role = "ui", color = "warning", wrap = true })
  panel.share = W.Action(panel, {
    key = "act.share",
    icon = "share",
    height = BUTTON_H,
    tooltip = "act.share",
    tooltipText = "questpanel.shareTip",
    wrap = "questpanel-share",
    opens = true,
    onClick = function()
      if panel.entry then
        ns.Share.Open("", P.ShareText(panel.entry, panel.ctx and panel.ctx.inst))
      end
    end,
  })
  panel.share.fgOnFocus = function()
    ns.ShowTooltip(panel.share, L["act.share"], L["questpanel.shareTip"], { hint = L["action.opensWindow"] })
  end
  panel.share.fgOnBlur = ns.HideTooltip

  local function label(key)
    return W.Text(panel, { key = key, role = "ui", color = "textSecondary", wrap = true })
  end
  local function value()
    return W.Text(panel, { role = "ui", color = "text", wrap = true })
  end
  panel.labels = {
    start = label("questpanel.start"),
    finish = label("questpanel.finish"),
    pre = label("questpanel.pre"),
    next = label("questpanel.next"),
    chain = label("questpanel.chain"),
    also = label("questpanel.also"),
    desc = label("questpanel.desc"),
    reward = label("questpanel.reward"),
    rewardChoice = label("questpanel.rewardChoice"),
    rewardFixed = label("questpanel.rewardFixed"),
  }
  for _, key in ipairs({ "desc", "reward" }) do
    W.SetColor(panel.labels[key], "accent2")
  end
  for _, key in ipairs({ "rewardChoice", "rewardFixed" }) do
    W.SetColor(panel.labels[key], "text")
  end
  panel.values = { start = value(), finish = value(), goal = value(), desc = value(), reward = value() }
  panel.places = W.MapActionButtons(panel)
  panel.chainButton = W.Action(panel, {
    text = "",
    variant = "secondary",
    height = BUTTON_H,
    opens = true,
    tooltip = "questchain.title",
    tooltipText = "questchain.openTip",
    wrap = "questpanel-chain",
    onClick = function()
      if panel.ctx and panel.ctx.openChain then
        panel.ctx.openChain()
      end
    end,
  })
  panel.chainButton.fgName = function()
    return panel.chainButton.label:GetText()
  end
  panel.chainButton.fgOnFocus = function()
    ns.ShowTooltip(
      panel.chainButton,
      L["questchain.title"],
      L["questchain.openTip"],
      { hint = L["action.opensWindow"] }
    )
  end
  panel.chainButton.fgOnBlur = ns.HideTooltip

  function panel:Stops()
    local out = { self.share, self.places.map, self.places.marker, self.chainButton }
    for _, pool in ipairs({ self.pre, self.nxt, self.also, self.rewards }) do
      for _, item in ipairs(pool) do
        out[#out + 1] = item
      end
    end
    return out
  end

  -- Pooled stops are created late and would sit at the end of the page: keep them behind the share button in
  -- display order.
  function panel:SyncFocusOrder()
    local items = ns.Focus.items
    local stops, own = self:Stops(), {}
    for _, stop in ipairs(stops) do
      own[stop] = true
    end
    local at
    for i = #items, 1, -1 do
      if own[items[i]] then
        table.remove(items, i)
        at = i
      end
    end
    for offset, stop in ipairs(stops) do
      table.insert(items, math.min((at or #items + 1) + offset - 1, #items + 1), stop)
    end
  end

  function panel:FocusFirst()
    for _, stop in ipairs(self:Stops()) do
      if stop:IsVisible() and (not stop.IsEnabled or stop:IsEnabled()) then
        ns.Focus.set(stop)
        return true
      end
    end
    return false
  end

  -- Paints one pool of link buttons from a list of references and hides the rest of the pool.
  local function paintLinks(pool, refs)
    for i, ref in ipairs(refs) do
      local b = pooled(panel, pool, i, makeLink)
      b.ref = ref
      W.SetText(b.label, nil, ref.name)
      b:Show()
    end
    for i = #refs + 1, #pool do
      pool[i].ref = nil
      pool[i]:Hide()
    end
  end

  -- entry: an entry of QC.Entries, nil shows the empty state.
  function panel:SetQuest(entry, ctx)
    self.entry, self.ctx = entry, ctx
    local own = {
      self.icon,
      self.title,
      self.sub,
      self.weak,
      self.share,
      self.places,
      self.chainButton,
    }
    for _, l in pairs(self.labels) do
      own[#own + 1] = l
    end
    for _, v in pairs(self.values) do
      own[#own + 1] = v
    end
    self.empty:SetShown(entry == nil)
    for _, frame in ipairs(own) do
      frame:SetShown(entry ~= nil)
    end
    if not entry then
      paintLinks(self.pre, {})
      paintLinks(self.nxt, {})
      for i = 1, #self.also do
        self.also[i].inst = nil
        self.also[i]:Hide()
      end
      for i = 1, #self.rewards do
        self.rewards[i].reward = nil
        self.rewards[i]:Hide()
      end
      return
    end
    local q = entry.quest
    self.title:SetText(name(q) or "?")
    self.sub:SetText(subLine(entry))
    local weak = ns.InstanceGaps and ns.InstanceGaps.QuestWeak(q)
    self.weak:SetText(weak and L["instances.quest.weak"] or "")
    self.weak:SetShown(weak == true)

    local start = startText(entry)
    local place = QW.Place(entry)
    self.places:SetPlace(place)
    self.values.start:SetText(start or "")
    self.shown = {
      start = start ~= nil or place ~= nil,
      finish = type(q.en) == "string" and q.en ~= "",
    }
    self.values.finish:SetText(self.shown.finish and q.en or "")

    local pre, nxt = {}, {}
    for _, id in ipairs(type(q.pre) == "table" and q.pre or {}) do
      pre[#pre + 1] = ctx.resolve(id)
    end
    for _, id in ipairs(type(q.nxt) == "table" and q.nxt or {}) do
      nxt[#nxt + 1] = ctx.resolve(id)
    end
    paintLinks(self.pre, pre)
    paintLinks(self.nxt, nxt)
    self.shown.pre, self.shown.next = #pre > 0, #nxt > 0
    local also = ctx.also or {}
    for i, other in ipairs(also) do
      local b = pooled(panel, self.also, i, makeAlso)
      b.inst = other
      W.SetText(b.label, nil, name(other) or "?")
      b:Show()
    end
    for i = #also + 1, #self.also do
      self.also[i].inst = nil
      self.also[i]:Hide()
    end
    self.shown.also = #also > 0

    local steps = ctx.chainLength or 1
    self.shown.chain = steps > 1
    if self.shown.chain then
      W.SetText(self.chainButton.label, nil, string.format(L["questchain.chainLen"]:gsub("^%l", string.upper), steps))
    end

    local desc, goal = ns.QuestText.Get(q.id)
    local live = P.Goal(q.id)
    if live then
      goal = goal and (goal .. "\n" .. live) or live
    end
    self.shown.desc, self.shown.goal = desc ~= nil, goal ~= nil
    self.values.desc:SetText(desc or "")
    self.values.goal:SetText(goal or "")

    local pay = payText(entry)
    self.values.reward:SetText(pay or "")
    local model = QL.Rewards(q, function(id, stored)
      return IV.ItemName({ id = id, name = stored })
    end)
    local tiles = {}
    for _, tile in ipairs(model.choice) do
      tiles[#tiles + 1] = tile
    end
    for _, tile in ipairs(model.fixed) do
      tiles[#tiles + 1] = tile
    end
    for i, tile in ipairs(tiles) do
      local row = pooled(panel, self.rewards, i, makeReward)
      paintReward(row, tile)
      row:Show()
    end
    for i = #tiles + 1, #self.rewards do
      self.rewards[i].reward = nil
      self.rewards[i]:Hide()
    end
    self.nChoice, self.nTiles = #model.choice, #tiles
    self.shown.rewardChoice, self.shown.rewardFixed = #model.choice > 0, #model.fixed > 0
    self.shown.reward = pay ~= nil or #tiles > 0
    self.shown.pay = pay ~= nil
    self:SyncFocusOrder()
  end

  -- Row of one field: label left, content in the value column. Returns the y below the field.
  local function at(frame, x, y, width)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
    if width then
      frame:SetWidth(width)
    end
  end

  -- Link buttons in a wrapping row, starting at x. Returns the height they take.
  local function flow(buttons, x, y, width)
    local cx, cy = 0, 0
    for _, b in ipairs(buttons) do
      if b:IsShown() then
        local w = math.min(width, math.ceil(b:Fit(width)))
        if cx > 0 and cx + w > width then
          cx, cy = 0, cy + BUTTON_H + 4
        end
        b:SetWidth(w)
        at(b, x + cx, y + cy)
        cx = cx + w + 4
      end
    end
    return cy + BUTTON_H
  end

  -- Fields with a label left of the content, in contrast to the headings above them.
  local FACTS = { "start", "finish", "pre", "next", "chain", "also" }

  function panel:fgGridLayout(width)
    local inner = math.max(60, width - 2 * PAD)
    if not self.entry then
      at(self.empty, PAD, PAD, inner)
      local h = ceil(self.empty) + 2 * PAD
      self:SetHeight(h)
      return h
    end
    local shareW = math.ceil(self.share:Fit(inner))
    self.share:SetWidth(shareW)
    self.share:ClearAllPoints()
    self.share:SetPoint("TOPRIGHT", self, "TOPRIGHT", -PAD, -PAD)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", PAD, -PAD)
    local titleW = math.max(60, inner - ICON - GAP - shareW - GAP)
    at(self.title, PAD + ICON + GAP, PAD, titleW)
    local y = PAD + math.max(ceil(self.title), BUTTON_H) + 4
    at(self.sub, PAD, y, inner)
    y = y + ceil(self.sub) + 2
    if self.weak:IsShown() then
      at(self.weak, PAD, y, inner)
      y = y + ceil(self.weak) + 2
    end
    y = y + ROW_GAP

    local shown, labels, values = self.shown, self.labels, self.values
    for key, l in pairs(labels) do
      l:SetShown(shown[key] == true)
    end
    values.goal:SetShown(shown.goal == true)
    values.desc:SetShown(shown.desc == true)
    values.reward:SetShown(shown.pay == true)
    values.finish:SetShown(shown.finish == true)
    -- Objectives first, then the description under its heading.
    if shown.goal then
      at(values.goal, PAD, y, inner)
      y = y + ceil(values.goal) + ROW_GAP
    end
    if shown.desc then
      at(labels.desc, PAD, y, inner)
      y = y + ceil(labels.desc) + 2
      at(values.desc, PAD, y, inner)
      y = y + ceil(values.desc) + ROW_GAP
    end

    -- Rewards: choice tiles, fixed tiles (two columns when the pane is wide enough), experience and money.
    if shown.reward then
      at(labels.reward, PAD, y, inner)
      y = y + ceil(labels.reward) + 4
      local cols = inner >= 2 * TILE_MIN + GAP and 2 or 1
      local colW = cols == 2 and math.floor((inner - GAP) / 2) or inner
      local function group(heading, from, to)
        if to < from then
          return
        end
        at(heading, PAD, y, inner)
        y = y + ceil(heading) + 4
        local rowH, col = 0, 0
        for i = from, to do
          local tile = self.rewards[i]
          at(tile, PAD + col * (colW + GAP), y, colW)
          local h = tile:fgLayout(colW)
          tile:SetSize(colW, h)
          rowH, col = math.max(rowH, h), col + 1
          if col == cols then
            y, rowH, col = y + rowH + 4, 0, 0
          end
        end
        if col > 0 then
          y = y + rowH + 4
        end
      end
      group(labels.rewardChoice, 1, self.nChoice)
      group(labels.rewardFixed, self.nChoice + 1, self.nTiles)
      if shown.pay then
        at(values.reward, PAD, y, inner)
        y = y + ceil(values.reward) + 4
      end
      y = y + ROW_GAP - 4
    end

    local labelW = 0
    for _, key in ipairs(FACTS) do
      if shown[key] then
        labels[key]:SetWidth(0)
        labelW = math.max(labelW, math.ceil(labels[key]:GetStringWidth()))
      end
    end
    labelW = math.min(labelW, math.floor(inner * 0.4))
    local vx, vw = PAD + labelW + GAP, math.max(40, inner - labelW - GAP)
    local function head(key)
      local l = labels[key]
      l:SetWidth(labelW)
      at(l, PAD, y)
      return ceil(l)
    end

    if shown.start then
      local h = head("start")
      local text = values.start
      text:SetShown(text:GetText() ~= "")
      local vh = 0
      if text:IsShown() then
        at(text, vx, y, vw)
        vh = ceil(text)
      end
      if self.places:IsShown() then
        at(self.places, vx, y + vh + (vh > 0 and 2 or 0))
        vh = vh + (vh > 0 and 2 or 0) + self.places:GetHeight()
      end
      y = y + math.max(h, vh) + ROW_GAP
    end
    if shown.finish then
      local h = head("finish")
      at(values.finish, vx, y, vw)
      y = y + math.max(h, ceil(values.finish)) + ROW_GAP
    end
    for _, field in ipairs({ { "pre", self.pre }, { "next", self.nxt }, { "also", self.also } }) do
      if shown[field[1]] then
        local h = head(field[1])
        y = y + math.max(h, flow(field[2], vx, y, vw)) + ROW_GAP
      end
    end
    self.chainButton:SetShown(shown.chain == true)
    if shown.chain then
      local h = head("chain")
      local w = math.min(vw, math.ceil(self.chainButton:Fit(vw)))
      self.chainButton:SetWidth(w)
      at(self.chainButton, vx, y)
      y = y + math.max(h, BUTTON_H) + ROW_GAP
    end
    local height = y - ROW_GAP + PAD
    self:SetHeight(height)
    return height
  end

  panel.entry = nil
  panel:SetQuest(nil)

  -- Item names and colors arrive after the first look.
  ns.On("GET_ITEM_INFO_RECEIVED", function()
    if panel.entry and panel:IsVisible() then
      panel:SetQuest(panel.entry, panel.ctx)
      if panel.onChange then
        panel.onChange()
      end
    end
  end)
  return panel
end
