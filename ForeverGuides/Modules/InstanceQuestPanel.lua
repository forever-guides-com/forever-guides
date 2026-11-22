-- Detail of the quests tab, right of the list of Modules/QuestChainView.lua: a hero (title, level and state tags,
-- share icon), a key/value block (starts at, turn in at, dungeon, status; the places carry map and waypoint
-- buttons) and section cards: objective (goal text, objective places, description), quest chain (numbered steps
-- with map buttons and their state, links to prequests and follow-ups, the other wings that list the quest),
-- rewards (choice and fixed items as tiles in two columns, experience and money), reputation (gains and the
-- standing the quest needs) and notes (hints and warnings, only in the language of the client). A field the data
-- does not have is left out, nothing is guessed. Description, goal and notes come from Modules/QuestText.lua; for
-- a quest in the own quest log the goal also lists the objective lines of the client.
-- Nothing is sent from here: the share dialog sends after its own click, and the quest log call that pushes a
-- quest to the group is never used (docs/TAINT-AUDIT.md).
local _, ns = ...
local W, L, Theme, QW, IV, QL, K = ns.W, ns.L, ns.Theme, ns.QuestChainWindow, ns.InstanceView, ns.QuestListLogic, ns.PageKit

ns.AddLocale("enUS", {
  ["questpanel.start"] = "Starts at",
  ["questpanel.start.inside"] = "Inside the instance",
  ["questpanel.start.outside"] = "Outside",
  ["questpanel.start.item"] = "item %s",
  ["questpanel.finish"] = "Turn in at",
  ["questpanel.dungeon"] = "Dungeon",
  ["questpanel.status"] = "Status",
  ["questpanel.pre"] = "Previous quest",
  ["questpanel.preAny"] = "Previous (any one)",
  ["questpanel.objectives"] = "Objective locations",
  ["questpanel.obj.k"] = "Kill",
  ["questpanel.obj.i"] = "Collect",
  ["questpanel.obj.o"] = "Use",
  ["questpanel.obj.e"] = "Place",
  ["questpanel.obj.s"] = "Talk to",
  ["questpanel.next"] = "Then",
  ["questpanel.card.goal"] = "Objective",
  ["questpanel.card.chain"] = "Quest chain",
  ["questpanel.card.reward"] = "Rewards",
  ["questpanel.card.rep"] = "Reputation",
  ["questpanel.card.notes"] = "Notes",
  ["questpanel.tag.req"] = "Requires level %d",
  ["questpanel.tag.dungeon"] = "Dungeon quest",
  ["questpanel.tag.raid"] = "Raid quest",
  ["questpanel.tag.step"] = "Step %d of %d",
  ["questpanel.rep.gain"] = "+%d reputation",
  ["questpanel.rep.need"] = "Requires %s",
  ["questpanel.rep.unknown"] = "Faction %d",
  ["questpanel.note.note"] = "Note",
  ["questpanel.note.warn"] = "Warning",
  ["questpanel.stepTip"] = "Shows this quest of the chain.",
  ["questpanel.stepCurrent"] = "You are viewing this quest.",
  ["questpanel.desc"] = "Description",
  ["questpanel.rewardChoice"] = "You can choose one of these rewards:",
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
  ["questpanel.start"] = "Startet bei",
  ["questpanel.start.inside"] = "In der Instanz",
  ["questpanel.start.outside"] = "Außerhalb",
  ["questpanel.start.item"] = "Item %s",
  ["questpanel.finish"] = "Abgabe bei",
  ["questpanel.dungeon"] = "Dungeon",
  ["questpanel.status"] = "Status",
  ["questpanel.pre"] = "Vorquest",
  ["questpanel.preAny"] = "Vorquest (eine davon)",
  ["questpanel.objectives"] = "Zielorte",
  ["questpanel.obj.k"] = "Besiegen",
  ["questpanel.obj.i"] = "Sammeln",
  ["questpanel.obj.o"] = "Benutzen",
  ["questpanel.obj.e"] = "Ort",
  ["questpanel.obj.s"] = "Sprechen mit",
  ["questpanel.next"] = "Danach",
  ["questpanel.card.goal"] = "Ziel",
  ["questpanel.card.chain"] = "Questkette",
  ["questpanel.card.reward"] = "Belohnungen",
  ["questpanel.card.rep"] = "Ruf",
  ["questpanel.card.notes"] = "Hinweise",
  ["questpanel.tag.req"] = "Ab Stufe %d",
  ["questpanel.tag.dungeon"] = "Dungeonquest",
  ["questpanel.tag.raid"] = "Raidquest",
  ["questpanel.tag.step"] = "Schritt %d von %d",
  ["questpanel.rep.gain"] = "+%d Ruf",
  ["questpanel.rep.need"] = "Benötigt: %s",
  ["questpanel.rep.unknown"] = "Fraktion %d",
  ["questpanel.note.note"] = "Hinweis",
  ["questpanel.note.warn"] = "Warnung",
  ["questpanel.stepTip"] = "Zeigt diese Quest der Kette.",
  ["questpanel.stepCurrent"] = "Du siehst diese Quest gerade.",
  ["questpanel.desc"] = "Beschreibung",
  ["questpanel.rewardChoice"] = "Du kannst eine dieser Belohnungen wählen:",
  ["questpanel.rewardFixed"] = "Du bekommst außerdem:",
  ["questpanel.also"] = "Auch in",
  ["questpanel.alsoTip"] = "Öffnet die Quests dieses Flügels.",
  ["questpanel.empty"] = "Wähle eine Quest aus der Liste.",
  ["questpanel.shareTip"] = "Öffnet den Teilen-Dialog.\nDas Addon sendet erst nach deinem Klick auf Senden.",
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

local GAP, ROW_GAP = 8, 6
local ICON = 24
local BUTTON_H = 24
local BAR_SIZE = 20
-- Narrowest tile of the reward grid: icon plus a short name.
local TILE_MIN = 120
local OBJECTIVE_NAME_GAP = 6
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

local function name(quest)
  return ns.QuestNames and quest.id and ns.QuestNames.Name(quest) or ns.T(quest.n)
end

-- Client reads -------------------------------------------------------------------------------------------

-- The value, or nil when it is secret or not readable for the addon.
local function safe(value)
  local guard = ns.AutoGuard
  return guard and guard.Safe(value) or nil
end

-- True when the quest is in the own quest log.
function P.InLog(id)
  local log = rawget(_G, "C_QuestLog")
  local fn = type(log) == "table" and log.GetLogIndexForQuestID or rawget(_G, "GetQuestLogIndexByID")
  if type(fn) ~= "function" then
    return false
  end
  local ok, index = pcall(fn, id)
  index = ok and safe(index) or nil
  return type(index) == "number" and index > 0
end

-- True when the character has handed the quest in.
function P.Done(id)
  local log = rawget(_G, "C_QuestLog")
  local fn = type(log) == "table" and log.IsQuestFlaggedCompleted or rawget(_G, "IsQuestFlaggedCompleted")
  if type(fn) ~= "function" then
    return false
  end
  local ok, done = pcall(fn, id)
  return ok and safe(done) == true
end

-- The objective lines of a quest that is in the own quest log, else nil (the data has no goal text).
function P.Goal(id)
  if type(id) ~= "number" or not P.InLog(id) then
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

-- One chat line: quest link (ChatSafe.QuestLink, else the plain quest name), instance, quest level and giver.
function P.ShareText(entry, inst)
  local q = entry.quest
  local quest = name(q) or "?"
  local rest = {}
  local place = inst and name(inst)
  if place then
    rest[#rest + 1] = place
  end
  if entry.level then
    rest[#rest + 1] = string.format(L["questchain.level"], entry.level)
  end
  if entry.giver then
    rest[#rest + 1] = string.format(L["questchain.giver"], entry.giver)
  end
  local tail = #rest > 0 and (", " .. table.concat(rest, ", ")) or ""
  if type(q.id) ~= "number" then
    return quest .. tail
  end
  return (ns.ChatSafe.QuestLink(q.id, quest, #tail)) .. tail
end

-- Texts ------------------------------------------------------------------------------------------------

-- Color token of a quest state (the word always stands next to it).
local STATE_TOKEN = { log = "info", done = "success", locked = "warning" }

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

-- The text with the muted coordinates of a place behind it, nil without both.
local function withCoords(text, x, y)
  local coord = type(x) == "number" and type(y) == "number" and K.Coord(x, y) or nil
  if coord then
    coord = Theme.hexText("textMuted", coord)
    return text and text ~= "" and (text .. "  " .. coord) or coord
  end
  return text
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

-- Name of a faction by its id: the reputation guide data, else the client, else "Faction <id>".
local function factionName(id)
  local GK = ns.GuideKit
  local ok, data = pcall(function()
    return GK and GK.Load("reputation") or nil
  end)
  for _, section in ipairs(ok and type(data) == "table" and data.sections or {}) do
    if section.fid == id and section.title then
      return ns.T(section.title)
    end
  end
  local get = rawget(_G, "GetFactionInfoByID")
  if type(get) == "function" then
    local called, label = pcall(get, id)
    label = called and safe(label) or nil
    if type(label) == "string" and label ~= "" then
      return label
    end
  end
  return string.format(L["questpanel.rep.unknown"], id)
end

-- Name of a standing id (1 Hated ... 8 Exalted), from the reputation guide data, else the client label.
local function standingName(id)
  local GK = ns.GuideKit
  local ok, data = pcall(function()
    return GK and GK.Load("reputation") or nil
  end)
  local standing = ok and ns.ReputationLogic and ns.ReputationLogic.Standing(data, id) or nil
  if standing then
    return ns.T(standing)
  end
  local label = rawget(_G, "FACTION_STANDING_LABEL" .. tostring(id))
  return type(label) == "string" and label or tostring(id)
end

-- Note and warning of a quest in the language of the client only. The text data falls back to English for a
-- German client, an English text in a German interface stays out.
function P.Notes(id)
  local note, warning = ns.QuestText.Notes(id)
  if ns.GetActiveLocale() == "deDE" then
    local all = rawget(ns, "InstanceQuestTexts")
    local row = type(all) == "table" and type(id) == "number" and all[id] or nil
    local function german(key)
      local texts = type(row) == "table" and row[key] or nil
      return type(texts) == "table" and type(texts.de) == "string" and texts.de ~= ""
    end
    note, warning = german("nt") and note or nil, german("wn") and warning or nil
  end
  local who = ns.QuestText.Player()
  return ns.QuestText.Fill(note, who), ns.QuestText.Fill(warning, who)
end

-- Reward rows: icon and name in the quality color, the tooltip is the item tooltip plus the quality word. The
-- row is no button: the tooltip on hover and on keyboard focus, Shift+click and Ctrl+click as for every item.
local function makeReward(parent)
  local row = CreateFrame("Frame", nil, parent)
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
  ns.Focus.register(row, function()
    ns.ItemActions.Preview(row.reward and row.reward.id)
  end)
  ns.ItemActions.Bind(row, function()
    return row.reward and row.reward.id
  end)
  -- The panel re-sorts the focus order (SyncFocusOrder), so the star only has to register.
  row.star = ns.WishlistStar.Create(row, function()
    return row.reward and row.reward.id
  end, ns.Focus.register)

  function row:fgLayout(width)
    local starW = ns.WishlistStar.SIZE + 4
    self.icon:ClearAllPoints()
    self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    self.star:ClearAllPoints()
    self.star:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
    self.text:ClearAllPoints()
    self.text:SetPoint("TOPLEFT", self, "TOPLEFT", ICON + GAP, 0)
    return math.max(ICON, W.FitLabel(self.text, math.max(40, width - ICON - GAP - starW))) + 2
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
  row.star:SetShown(tile.id ~= nil)
  row.star:Refresh()
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
local function makeLink(parent, panel)
  local b
  b = W.Action(parent, {
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

-- One objective place: map and waypoint buttons left, the kind and name right of them.
local function makeObjective(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.text = W.Text(row, { role = "ui", color = "text", wrap = true })
  row.bar = W.MapActionButtons(row)
  row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  return row
end

local function objectiveText(o)
  local kind = L["questpanel.obj." .. o.kind]
  local text = o.name and string.format("%s: %s", kind, o.name) or kind
  return o.count and string.format("%s (%dx)", text, o.count) or text
end

-- Plain text of a marked-up string, for the keyboard name of a row.
local function plainText(text)
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("%s+", " ")
  return (text:gsub("^ ", ""))
end

-- The two lines of a step of the chain: "2. Name" and the level, the faction when it is one side only, the giver
-- with its zone, "repeatable", the class and the quests it rules out.
local function stepLines(step)
  if step.missing then
    return string.format(L["questchain.missing"], step.id), ""
  end
  local bits =
    { step.level and string.format(L["questchain.stepLevel"], step.level) or L["questchain.stepLevelUnknown"] }
  if step.faction ~= "B" then
    bits[#bits + 1] = QW.FactionText(step.faction)
  end
  if step.giver then
    local zone = step.zone and ns.T(step.zone)
    bits[#bits + 1] = zone and string.format("%s (%s)", step.giver, zone) or step.giver
  end
  if step.repeatable then
    bits[#bits + 1] = QW.RepeatText()
  end
  bits[#bits + 1] = QW.ClassText(step.class)
  bits[#bits + 1] = QW.ExclText(step)
  return string.format("%d. %s", step.number, name(step.quest) or "?"), table.concat(bits, " · ")
end

-- State word of a step at the right of its row: "Current" for the quest in view, else the state of the player.
local function stepState(step)
  if step.chosen then
    return L["questchain.tag.chosen"], "accent2"
  end
  local state = step.missing and "open" or ns.QuestChainView.State(step)
  if state == "open" then
    return nil
  end
  return L["questlist.state." .. state], STATE_TOKEN[state]
end

-- One row of the numbered chain: a button that shows the quest in the list (the current quest is marked and
-- does nothing), its state word at the right and the map buttons of the giver. Like the reward rows it is a
-- focus stop with a name for readers.
local function makeStep(parent, panel)
  local b = CreateFrame("Button", nil, parent)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.hover = b:CreateTexture(nil, "HIGHLIGHT")
  b.hover:SetAllPoints()
  b.hover:SetColorTexture(Theme.fillColor("hover"))
  b.mark = b:CreateTexture(nil, "OVERLAY")
  b.mark:SetPoint("TOPLEFT")
  b.mark:SetPoint("BOTTOMLEFT")
  b.mark:SetWidth(3)
  b.title = W.Text(b, { role = "ui", color = "text", wrap = true })
  b.meta = W.Text(b, { role = "small", color = "textSecondary", wrap = true })
  b.state = W.Text(b, { role = "small", color = "textSecondary", justify = "RIGHT" })
  -- The buttons are siblings of the row, not children: a click on them must not choose the step.
  b.bar = W.MapActionButtons(parent, { size = BAR_SIZE })
  ns.Bind(b, function()
    b.mark:SetColorTexture(Theme.color("accent2"))
    b.bg:SetColorTexture(Theme.color("accent2", b.current and 0.2 or 0))
  end)
  local function act()
    if b.ref and not b.current and panel.ctx then
      panel.ctx.go(b.ref)
    end
  end
  b:SetScript("OnClick", ns.Wrap("questpanel-step", act))
  local function tip()
    ns.ShowTooltip(b, b.plainTitle or "", b.current and L["questpanel.stepCurrent"] or L["questpanel.stepTip"])
  end
  b:HookScript("OnEnter", tip)
  b:HookScript("OnLeave", ns.HideTooltip)
  b.fgOnFocus, b.fgOnBlur = tip, ns.HideTooltip
  b.fgName = function()
    return b.label
  end
  b.fgDescription = function()
    return b.current and L["questpanel.stepCurrent"] or nil
  end
  ns.Focus.register(b, act)

  -- The map buttons stand right of the button, so the two never overlap; fgWidth is the width of the button.
  function b:fgLayout(width)
    local barBlock = self.bar:IsShown() and (self.bar:GetWidth() + 6) or 0
    local own = math.max(60, width - barBlock)
    self.fgWidth = own
    self.bar:ClearAllPoints()
    self.bar:SetPoint("TOPLEFT", self, "TOPRIGHT", 6, -2)
    local stateW = 0
    if self.state:IsShown() then
      self.state:SetWidth(0)
      stateW = math.ceil(self.state:GetStringWidth()) + 6
      self.state:SetWidth(stateW)
      self.state:ClearAllPoints()
      self.state:SetPoint("TOPRIGHT", self, "TOPRIGHT", -6, -6)
    end
    local textW = math.max(40, own - 14 - stateW)
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -4)
    local y = 4 + W.FitLabel(self.title, textW) + 2
    if self.meta:IsShown() then
      self.meta:ClearAllPoints()
      self.meta:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -y)
      y = y + W.FitLabel(self.meta, math.max(40, own - 14)) + 2
    end
    return math.max(y + 2, self.bar:IsShown() and (self.bar:GetHeight() + 4) or 0)
  end
  return b
end

local function paintStep(b, step, ref)
  local title, meta = stepLines(step)
  local word, token = stepState(step)
  b.ref, b.current = ref, step.chosen == true
  b.plainTitle = plainText(title)
  b.label = plainText(title .. (meta ~= "" and (", " .. meta) or "") .. (word and (", " .. word) or ""))
  b.title:SetText(title)
  b.meta:SetText(meta)
  b.meta:SetShown(meta ~= "")
  b.state:SetText(word or "")
  b.state:SetShown(word ~= nil)
  W.SetColor(b.state, Theme.readable(Theme.hex(token or "textSecondary"), Theme.hex("surface2")))
  b.bar:SetPlace(QW.Place(step))
  b.mark:SetShown(b.current)
  b.bg:SetColorTexture(Theme.color("accent2", b.current and 0.2 or 0))
end

-- One button of the "Also in" field: opens the quests of another wing that lists the quest.
local function makeAlso(parent)
  local b
  b = W.Action(parent, {
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

-- A row of the reputation card: the faction left, the amount or the standing right.
local function makeRepRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.name = W.Text(row, { role = "ui", color = "text", wrap = true })
  row.value = W.Text(row, { role = "ui", color = "text", justify = "RIGHT" })
  function row:fgLayout(width)
    self.value:SetWidth(0)
    local valueW = math.min(math.ceil(self.value:GetStringWidth()), math.floor(width * 0.5))
    self.value:SetWidth(valueW)
    self.value:ClearAllPoints()
    self.value:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    local h = math.max(W.FitLabel(self.name, math.max(20, width - valueW - GAP)), math.ceil(self.value:GetStringHeight()))
    return h + 2
  end
  return row
end

-- A row of the notes card: a status dot, then the word and the text.
local function makeNoteRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.dot = K.StatusDot(row, {})
  row.text = W.Text(row, { role = "ui", color = "text", wrap = true })
  function row:fgLayout(width)
    local dotW = self.dot:GetWidth() + GAP
    self.dot:ClearAllPoints()
    self.dot:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -3)
    self.text:ClearAllPoints()
    self.text:SetPoint("TOPLEFT", self, "TOPLEFT", dotW, 0)
    return W.FitLabel(self.text, math.max(20, width - dotW)) + 2
  end
  return row
end

local function pooled(parent, panel, pool, index, make)
  local item = pool[index]
  if not item then
    item = make(parent, panel)
    pool[index] = item
  end
  return item
end

-- Faction tag of the hero: the word, the color of the side.
local function factionTag(faction)
  local token = faction == "A" and "alliance" or faction == "H" and "horde" or "textSecondary"
  return { text = L["kit.faction." .. (faction == "B" and "all" or faction)], color = token }
end

-- parent: the frame the panel sits in (the content of the master/detail shell). Methods: :SetQuest(entry, ctx),
-- :fgGridLayout(width) -> height, :Stops() -> the focus stops in display order, :FocusFirst() -> true when one took
-- the focus.
-- ctx: { inst, chain, resolve(id) -> reference, go(reference), openChain() }; the panel only shows what
-- QC.Reference describes and hands a click back through ctx.go. .onChange(): asks the owner for a layout.
function P.Create(parent)
  local panel = CreateFrame("Frame", nil, parent)
  panel.pre, panel.preAny, panel.nxt, panel.also, panel.rewards, panel.objs = {}, {}, {}, {}, {}, {}
  panel.steps, panel.lanes, panel.chainItems = {}, {}, {}
  panel.repRows, panel.noteRows, panel.noteList = {}, {}, {}
  panel.nChoice, panel.nTiles = 0, 0
  panel.shown = {}

  panel.empty = W.Text(panel, { key = "questpanel.empty", role = "ui", color = "textSecondary", wrap = true })

  -- Hero: the title, the tags and the share icon (the page link sits on the list rows).
  panel.hero = K.Hero(panel, {})
  panel.hero:SetPortrait({ texture = QUEST_ICON })
  panel.title = panel.hero.title
  panel.share = ns.PageShare.Button(panel.hero, {
    size = BUTTON_H,
    tooltip = "act.share",
    tooltipText = "questpanel.shareTip",
    opens = true,
    onClick = function()
      if panel.entry then
        ns.Share.Open("", P.ShareText(panel.entry, panel.ctx and panel.ctx.inst))
      end
    end,
  })
  panel.hero:SetActions(panel.share)
  panel.kv = K.KeyValue(panel, {})

  local function label(parentFrame, key, color)
    return W.Text(parentFrame, { key = key, role = "ui", color = color or "textSecondary", wrap = true })
  end

  -- Objective card ---------------------------------------------------------------------------------------
  panel.goalCard = K.SectionCard(panel, { key = "questpanel.card.goal" })
  local goalBody = panel.goalCard.body
  panel.goalText = W.Text(goalBody, { role = "ui", color = "text", wrap = true })
  panel.objLabel = label(goalBody, "questpanel.objectives")
  panel.descLabel = label(goalBody, "questpanel.desc")
  panel.descText = W.Text(goalBody, { role = "ui", color = "text", wrap = true })
  -- Quest texts come from data and may name a web address: one button per address under the card text.
  panel.textLinks = W.WebLinks(goalBody)

  -- Quest chain card --------------------------------------------------------------------------------------
  panel.chainCard = K.SectionCard(panel, { key = "questpanel.card.chain" })
  local chainBody = panel.chainCard.body
  panel.linkLabels = {
    pre = label(chainBody, "questpanel.pre"),
    preAny = label(chainBody, "questpanel.preAny"),
    next = label(chainBody, "questpanel.next"),
    also = label(chainBody, "questpanel.also"),
  }
  panel.chainButton = W.Action(chainBody, {
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

  -- Reward, reputation and notes cards ---------------------------------------------------------------------
  panel.rewardCard = K.SectionCard(panel, { key = "questpanel.card.reward" })
  local rewardBody = panel.rewardCard.body
  panel.rewardChoice = label(rewardBody, "questpanel.rewardChoice", "text")
  panel.rewardFixed = label(rewardBody, "questpanel.rewardFixed", "text")
  panel.payText = W.Text(rewardBody, { role = "ui", color = "text", wrap = true })
  panel.repCard = K.SectionCard(panel, { key = "questpanel.card.rep" })
  panel.notesCard = K.SectionCard(panel, { key = "questpanel.card.notes" })
  panel.cards = { panel.goalCard, panel.chainCard, panel.rewardCard, panel.repCard, panel.notesCard }

  -- The map buttons of the start and the hand-in row of the key/value block (nil without a place).
  function panel:Bars()
    return self.startBar, self.finishBar
  end

  function panel:Stops()
    local out = { self.share }
    for _, bar in ipairs({ self.startBar or false, self.finishBar or false }) do
      if bar then
        out[#out + 1] = bar.map
        out[#out + 1] = bar.marker
      end
    end
    for _, row in ipairs(self.objs) do
      if row:IsShown() then
        out[#out + 1] = row.bar.map
        out[#out + 1] = row.bar.marker
      end
    end
    for _, button in ipairs(self.textLinks.buttons) do
      out[#out + 1] = button
    end
    for _, step in ipairs(self.steps) do
      out[#out + 1] = step
      out[#out + 1] = step.bar.map
      out[#out + 1] = step.bar.marker
    end
    for _, pool in ipairs({ self.pre, self.preAny, self.nxt, self.also }) do
      for _, item in ipairs(pool) do
        out[#out + 1] = item
      end
    end
    out[#out + 1] = self.chainButton
    for _, item in ipairs(self.rewards) do
      out[#out + 1] = item
      out[#out + 1] = item.star
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
  local function paintLinks(pool, refs, make)
    for i, ref in ipairs(refs) do
      local b = pooled(chainBody, panel, pool, i, make or makeLink)
      b.ref = ref
      W.SetText(b.label, nil, ref.name)
      b:Show()
    end
    for i = #refs + 1, #pool do
      pool[i].ref = nil
      pool[i]:Hide()
    end
  end

  -- Paints the numbered chain: one row per step, a heading before the first step of a branch. nil hides it all.
  function panel:PaintChain(chain, ctx)
    local items = {}
    for _, step in ipairs(chain and chain.steps or {}) do
      if step.laneStart and step.lane then
        items[#items + 1] = { head = QW.LaneText(step.lane) }
      end
      items[#items + 1] = { step = step }
    end
    self.chainItems = {}
    local nHead, nStep = 0, 0
    for _, item in ipairs(items) do
      if item.head then
        nHead = nHead + 1
        local fs = self.lanes[nHead]
        if not fs then
          fs = W.Text(chainBody, { role = "ui", color = "accent2", wrap = true })
          self.lanes[nHead] = fs
        end
        fs:SetText(item.head)
        fs:Show()
        self.chainItems[#self.chainItems + 1] = fs
      else
        nStep = nStep + 1
        local b = pooled(chainBody, panel, self.steps, nStep, makeStep)
        paintStep(b, item.step, ctx and ctx.resolve(item.step.id) or nil)
        b:Show()
        self.chainItems[#self.chainItems + 1] = b
      end
    end
    for i = nHead + 1, #self.lanes do
      self.lanes[i]:Hide()
    end
    for i = nStep + 1, #self.steps do
      self.steps[i].ref = nil
      self.steps[i]:Hide()
      self.steps[i].bar:Hide()
    end
  end

  -- Hides everything that belongs to a quest (no quest chosen).
  local function clear()
    paintLinks(panel.pre, {})
    paintLinks(panel.preAny, {})
    paintLinks(panel.nxt, {})
    for _, row in ipairs(panel.objs) do
      row:Hide()
    end
    panel:PaintChain(nil)
    for i = 1, #panel.also do
      panel.also[i].inst = nil
      panel.also[i]:Hide()
    end
    for i = 1, #panel.rewards do
      panel.rewards[i].reward = nil
      panel.rewards[i]:Hide()
    end
    for _, row in ipairs(panel.repRows) do
      row:Hide()
    end
    for _, row in ipairs(panel.noteRows) do
      row:Hide()
    end
    panel.startBar, panel.finishBar, panel.noteList = nil, nil, {}
    panel.kv:SetRows({})
    panel.hero:SetTags({})
  end

  -- The hero tags of a quest: required level, side, kind or step of the chain, state, repeatable, class, access.
  local function heroTags(entry, state, chain)
    local tags = {}
    local avail = entry.avail
    if avail and avail.kind ~= "hint" and type(avail.level) == "number" then
      tags[#tags + 1] = { text = string.format(L["questpanel.tag.req"], avail.level) }
    end
    tags[#tags + 1] = factionTag(entry.faction)
    local stepAt
    for i, step in ipairs(chain and chain.steps or {}) do
      if step.chosen then
        stepAt = i
      end
    end
    if stepAt and #chain.steps > 1 then
      tags[#tags + 1] = { text = string.format(L["questpanel.tag.step"], stepAt, #chain.steps), color = "accent2" }
    else
      tags[#tags + 1] = { text = L["questpanel.tag." .. QL.Kind(entry)], color = "accent2" }
    end
    if state ~= "open" then
      tags[#tags + 1] = { text = L["questlist.state." .. state], color = STATE_TOKEN[state] }
    end
    if entry.repeatable then
      tags[#tags + 1] = { text = L["questchain.repeatable"] }
    end
    local class = QW.ClassPlain(entry.class)
    if class then
      tags[#tags + 1] = { text = class, rich = QW.ClassText(entry.class, "surface2") }
    end
    if entry.access then
      tags[#tags + 1] = { text = L["questchain.tag.access"] }
    end
    return tags
  end

  -- entry: an entry of QC.Entries, nil shows the empty state.
  function panel:SetQuest(entry, ctx)
    self.entry, self.ctx = entry, ctx
    self.empty:SetShown(entry == nil)
    self.hero:SetShown(entry ~= nil)
    self.share:SetShown(entry ~= nil)
    self.kv:SetShown(entry ~= nil)
    if not entry then
      clear()
      for _, card in ipairs(self.cards) do
        card:Hide()
      end
      return
    end
    local q = entry.quest
    local state = ns.QuestChainView.State(entry)
    self.state = state
    self.hero:SetTitle(name(q) or "?")
    self.hero:SetSubtitle(entry.level and string.format(L["questchain.level"], entry.level) or "")
    self.hero:SetTags(heroTags(entry, state, ctx.chain))

    -- Key/value block: starts at, turn in at, dungeon, status.
    local rows = {}
    local start = startText(entry)
    local place = QW.Place(entry)
    if start or place then
      rows[#rows + 1] = {
        key = "questpanel.start",
        value = withCoords(start, q.x, q.y) or "",
        place = place,
        which = "start",
      }
    end
    local finishPlace = ns.QuestChainLogic.FinishPlace(q)
    local finishName = type(q.en) == "string" and q.en ~= "" and q.en or nil
    if finishPlace then
      finishPlace.label = finishPlace.label or name(q)
    end
    if finishName or finishPlace then
      rows[#rows + 1] = {
        key = "questpanel.finish",
        value = withCoords(finishName, finishPlace and finishPlace.x, finishPlace and finishPlace.y) or "",
        place = finishPlace,
        which = "finish",
      }
    end
    if ctx.inst and name(ctx.inst) then
      rows[#rows + 1] = { key = "questpanel.dungeon", value = name(ctx.inst) }
    end
    rows[#rows + 1] = {
      key = "questpanel.status",
      value = L["questlist.state." .. state],
      color = state ~= "open" and Theme.readable(Theme.hex(STATE_TOKEN[state]), Theme.hex("surface")) or nil,
    }
    self.kv:SetRows(rows)
    self.startBar, self.finishBar = nil, nil
    for i, row in ipairs(rows) do
      local kvRow = self.kv:Row(i)
      if row.which and row.place and kvRow then
        self[row.which .. "Bar"] = kvRow.map
      end
    end

    -- Objective card: goal text, objective places, description.
    local desc, goal = ns.QuestText.Get(q.id)
    local live = P.Goal(q.id)
    if live then
      goal = goal and (goal .. "\n" .. live) or live
    end
    self.goalText:SetText(goal or "")
    self.descText:SetText(desc or "")
    self.textLinks:Set((goal or "") .. " " .. (desc or ""))
    local objectives = ns.QuestChainLogic.Objectives(q)
    for i, o in ipairs(objectives) do
      local row = pooled(goalBody, panel, self.objs, i, makeObjective)
      row.text:SetText(objectiveText(o))
      row.bar:SetPlace({ map = o.map, x = o.x, y = o.y, label = o.name or L["questpanel.obj." .. o.kind] })
      row:Show()
    end
    for i = #objectives + 1, #self.objs do
      self.objs[i]:Hide()
    end
    self.shown.goal, self.shown.desc, self.shown.objectives = goal ~= nil, desc ~= nil, #objectives > 0

    -- Quest chain card: steps, links, the other wings.
    local pre, preAny, nxt = {}, {}, {}
    for _, id in ipairs(type(q.pre) == "table" and q.pre or {}) do
      pre[#pre + 1] = ctx.resolve(id)
    end
    for _, id in ipairs(type(q.preAny) == "table" and q.preAny or {}) do
      preAny[#preAny + 1] = ctx.resolve(id)
    end
    for _, id in ipairs(type(q.nxt) == "table" and q.nxt or {}) do
      nxt[#nxt + 1] = ctx.resolve(id)
    end
    paintLinks(self.pre, pre)
    paintLinks(self.preAny, preAny)
    paintLinks(self.nxt, nxt)
    self.shown.pre, self.shown.preAny, self.shown.next = #pre > 0, #preAny > 0, #nxt > 0
    local also = ctx.also or {}
    for i, other in ipairs(also) do
      local b = pooled(chainBody, panel, self.also, i, makeAlso)
      b.inst = other
      W.SetText(b.label, nil, name(other) or "?")
      b:Show()
    end
    for i = #also + 1, #self.also do
      self.also[i].inst = nil
      self.also[i]:Hide()
    end
    self.shown.also = #also > 0
    local chain = ctx.chain
    local steps = chain and #chain.steps or ctx.chainLength or 1
    self.shown.chain = steps > 1
    self:PaintChain(self.shown.chain and chain or nil, ctx)
    if self.shown.chain then
      W.SetText(self.chainButton.label, nil, (string.format(L["questchain.chainLen"], steps):gsub("^%l", string.upper)))
      self.chainCard:SetCount(steps)
    else
      self.chainCard:SetCount(nil)
    end

    -- Reward card.
    local pay = payText(entry)
    self.payText:SetText(pay or "")
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
      local row = pooled(rewardBody, panel, self.rewards, i, makeReward)
      paintReward(row, tile)
      row:Show()
    end
    for i = #tiles + 1, #self.rewards do
      self.rewards[i].reward = nil
      self.rewards[i]:Hide()
    end
    self.nChoice, self.nTiles = #model.choice, #tiles
    self.shown.rewardChoice, self.shown.rewardFixed = #model.choice > 0, #model.fixed > 0
    self.shown.pay = pay ~= nil
    self.shown.reward = pay ~= nil or #tiles > 0

    -- Reputation card: the gains, then the standing the quest needs.
    local gains, need = ns.InstanceDataAccess.Reputation(q)
    local repList = {}
    for _, gain in ipairs(gains) do
      repList[#repList + 1] = { name = factionName(gain.faction), value = string.format(L["questpanel.rep.gain"], gain.amount) }
    end
    if need then
      repList[#repList + 1] = {
        name = factionName(need.faction),
        value = string.format(L["questpanel.rep.need"], standingName(need.standing)),
      }
    end
    for i, item in ipairs(repList) do
      local row = pooled(self.repCard.body, panel, self.repRows, i, makeRepRow)
      row.name:SetText(item.name)
      row.value:SetText(item.value)
      row:Show()
    end
    for i = #repList + 1, #self.repRows do
      self.repRows[i]:Hide()
    end
    self.nRep = #repList
    self.repCard:SetCount(#repList > 0 and #repList or nil)

    -- Notes card: a gap in the data, the hint and the warning of the quest.
    local note, warning = P.Notes(q.id)
    local noteList = {}
    if ns.InstanceGaps and ns.InstanceGaps.QuestWeak(q) then
      noteList[#noteList + 1] = { kind = "warn", text = L["instances.quest.weak"] }
    end
    if warning then
      noteList[#noteList + 1] = { kind = "warn", text = warning }
    end
    if note then
      noteList[#noteList + 1] = { kind = "note", text = note }
    end
    self.noteList = noteList
    for i, item in ipairs(noteList) do
      local row = pooled(self.notesCard.body, panel, self.noteRows, i, makeNoteRow)
      local warn = item.kind == "warn"
      local word = L[warn and "questpanel.note.warn" or "questpanel.note.note"]
      row.dot:SetState(warn and "warn" or "info", word, warn and "filled" or "ring")
      row.text:SetText(Theme.hexText(warn and "warning" or "info", word) .. ": " .. item.text)
      row:Show()
    end
    for i = #noteList + 1, #self.noteRows do
      self.noteRows[i]:Hide()
    end
    self.syncFocus = true
    self:SyncFocusOrder()
  end

  -- Cards ----------------------------------------------------------------------------------------------------

  -- Row of tiles: placed in columns inside a body, returns the y below them.
  local function tiles(from, to, y, w)
    local cols = w >= 2 * TILE_MIN + GAP and 2 or 1
    local colW = cols == 2 and math.floor((w - GAP) / 2) or w
    local rowH, col = 0, 0
    for i = from, to do
      local tile = panel.rewards[i]
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", rewardBody, "TOPLEFT", col * (colW + GAP), -y)
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
    return y
  end

  local function at(frame, anchor, y, x, width)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", x or 0, -y)
    if width then
      frame:SetWidth(width)
    end
  end

  panel.goalCard:SetBody(function(w)
    local s = panel.shown
    local y = 0
    panel.goalText:SetShown(s.goal == true)
    if s.goal then
      at(panel.goalText, goalBody, y)
      y = y + W.FitLabel(panel.goalText, w) + ROW_GAP
    end
    panel.objLabel:SetShown(s.objectives == true)
    if s.objectives then
      at(panel.objLabel, goalBody, y)
      y = y + W.FitLabel(panel.objLabel, w) + 4
      local barW = panel.objs[1].bar:GetWidth()
      for _, row in ipairs(panel.objs) do
        if row:IsShown() then
          local textW = math.max(40, w - barW - OBJECTIVE_NAME_GAP)
          row.text:ClearAllPoints()
          row.text:SetPoint("TOPLEFT", row, "TOPLEFT", barW + OBJECTIVE_NAME_GAP, -4)
          row.text:SetWidth(textW)
          local rowH = math.max(row.bar:GetHeight(), math.ceil(row.text:GetStringHeight()) + 4)
          at(row, goalBody, y)
          row:SetSize(w, rowH)
          y = y + rowH + 2
        end
      end
      y = y + ROW_GAP - 2
    end
    panel.descLabel:SetShown(s.desc == true)
    panel.descText:SetShown(s.desc == true)
    if s.desc then
      at(panel.descLabel, goalBody, y)
      y = y + W.FitLabel(panel.descLabel, w) + 2
      at(panel.descText, goalBody, y)
      y = y + W.FitLabel(panel.descText, w) + ROW_GAP
    end
    panel.textLinks:SetShown(s.goal == true or s.desc == true)
    if panel.textLinks:IsShown() then
      at(panel.textLinks, goalBody, y)
      y = y + panel.textLinks:fgGridLayout(w) + ROW_GAP
    end
    return math.max(0, y - ROW_GAP)
  end)

  -- Link buttons in a wrapping row. Returns the height they take.
  local function flow(buttons, y, width)
    local cx, cy = 0, 0
    for _, b in ipairs(buttons) do
      if b:IsShown() then
        local bw = math.min(width, math.ceil(b:Fit(width)))
        if cx > 0 and cx + bw > width then
          cx, cy = 0, cy + BUTTON_H + 4
        end
        b:SetWidth(bw)
        at(b, chainBody, y + cy, cx)
        cx = cx + bw + 4
      end
    end
    return cy + BUTTON_H
  end

  panel.chainCard:SetBody(function(w)
    local s = panel.shown
    local y = 0
    for _, item in ipairs(panel.chainItems) do
      at(item, chainBody, y, 0, w)
      if item.fgLayout then
        local ih = item:fgLayout(w)
        item:SetSize(item.fgWidth or w, ih)
        y = y + ih + 2
      else
        y = y + W.FitLabel(item, w) + 2
      end
    end
    if #panel.chainItems > 0 then
      y = y + ROW_GAP
    end
    for _, field in ipairs({
      { "pre", panel.pre },
      { "preAny", panel.preAny },
      { "next", panel.nxt },
      { "also", panel.also },
    }) do
      local on = s[field[1]] == true
      panel.linkLabels[field[1]]:SetShown(on)
      if on then
        local l = panel.linkLabels[field[1]]
        at(l, chainBody, y)
        y = y + W.FitLabel(l, w) + 2
        y = y + flow(field[2], y, w) + ROW_GAP
      end
    end
    panel.chainButton:SetShown(s.chain == true)
    if s.chain then
      local bw = math.min(w, math.ceil(panel.chainButton:Fit(w)))
      panel.chainButton:SetWidth(bw)
      at(panel.chainButton, chainBody, y)
      y = y + BUTTON_H + ROW_GAP
    end
    return math.max(0, y - ROW_GAP)
  end)

  panel.rewardCard:SetBody(function(w)
    local s = panel.shown
    local y = 0
    panel.rewardChoice:SetShown(s.rewardChoice == true)
    panel.rewardFixed:SetShown(s.rewardFixed == true)
    if s.rewardChoice then
      at(panel.rewardChoice, rewardBody, y)
      y = y + W.FitLabel(panel.rewardChoice, w) + 4
      y = tiles(1, panel.nChoice, y, w)
    end
    if s.rewardFixed then
      at(panel.rewardFixed, rewardBody, y)
      y = y + W.FitLabel(panel.rewardFixed, w) + 4
      y = tiles(panel.nChoice + 1, panel.nTiles, y, w)
    end
    panel.payText:SetShown(s.pay == true)
    if s.pay then
      at(panel.payText, rewardBody, y)
      y = y + W.FitLabel(panel.payText, w) + 4
    end
    return math.max(0, y - 4)
  end)

  panel.repCard:SetBody(function(w)
    local y = 0
    for _, row in ipairs(panel.repRows) do
      if row:IsShown() then
        at(row, panel.repCard.body, y)
        local h = row:fgLayout(w)
        row:SetSize(w, h)
        y = y + h + 2
      end
    end
    return math.max(0, y - 2)
  end)

  panel.notesCard:SetBody(function(w)
    local y = 0
    for _, row in ipairs(panel.noteRows) do
      if row:IsShown() then
        at(row, panel.notesCard.body, y)
        local h = row:fgLayout(w)
        row:SetSize(w, h)
        y = y + h + ROW_GAP
      end
    end
    return math.max(0, y - ROW_GAP)
  end)

  function panel:fgGridLayout(width)
    width = math.max(60, width)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    if not self.entry then
      self.empty:ClearAllPoints()
      self.empty:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      local h = W.FitLabel(self.empty, width)
      self:SetSize(width, h)
      return h
    end
    local gap = Theme.space.lg
    self.hero:ClearAllPoints()
    self.hero:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    local y = self.hero:fgLayout(width) + gap
    self.kv:ClearAllPoints()
    self.kv:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
    y = y + self.kv:fgLayout(width) + gap
    local s = self.shown
    local on = {
      s.goal or s.desc or s.objectives,
      s.chain or s.pre or s.preAny or s.next or s.also,
      s.reward,
      self.nRep and self.nRep > 0,
      #self.noteList > 0,
    }
    for i, card in ipairs(self.cards) do
      card:SetShown(on[i] == true)
      if on[i] then
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        y = y + card:fgLayout(width) + gap
      end
    end
    local height = y - gap
    self:SetSize(width, height)
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
