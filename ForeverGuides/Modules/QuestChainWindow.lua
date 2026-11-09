-- The window of one quest of an instance: the chain of prequests in order (first quest first, the chosen quest
-- last), per step the faction, the levels, the experience, the giver with the zone and two buttons, "Set marker"
-- (waypoint at the giver) and "Map" (opens the map at the giver). A step without a place keeps both buttons
-- greyed out and says why in its text. The rules are in Modules/QuestChainLogic.lua. Nothing here is protected,
-- the window closes with ns.SafeHide (Esc stack of the shell), so it works in combat.
-- Keys: Up, Down and Tab walk the buttons, Enter and Space press the focused one (without a focus Enter sets
-- the marker of the chosen quest), Esc closes. Other keys reach the game.
local _, ns = ...
local W, L, Theme, QC = ns.W, ns.L, ns.Theme, ns.QuestChainLogic

ns.AddLocale("enUS", {
  ["questchain.title"] = "Quest chain",
  ["questchain.close"] = "Close quest chain",
  ["questchain.steps.one"] = "1 step",
  ["questchain.steps.other"] = "%d steps",
  ["questchain.level"] = "Quest level %s",
  ["questchain.levelUnknown"] = "Quest level not in the data",
  ["questchain.from"] = "Available from level %d",
  ["questchain.fromPartial"] = "Available from level %d or later (not every step has a level)",
  ["questchain.fromUnknown"] = "Minimum level not in the data",
  ["questchain.stepLevel"] = "Level %d",
  ["questchain.stepLevelUnknown"] = "Level ?",
  ["questchain.stepFrom"] = "from level %d",
  ["questchain.stepFromChain"] = "from level %d with its prequests",
  ["questchain.stepFromHint"] = "from about level %d (hint, minimum level not in the data)",
  ["questchain.stepFromUnknown"] = "from level: not in the data",
  ["questchain.xp"] = "%s XP",
  ["questchain.giver"] = "Giver: %s",
  ["questchain.giverZone"] = "Giver: %s in %s",
  ["questchain.giverNone"] = "Giver not recorded",
  ["questchain.placeNone"] = "Place not recorded, so no marker and no map",
  ["questchain.tag.chosen"] = "This quest",
  ["questchain.tag.access"] = "Access quest",
  ["questchain.tag.from"] = "From %s",
  ["questchain.missing"] = "Quest %d is not in the data",
  ["questchain.pair"] = "Counterpart of the other faction: %s",
  ["questchain.marker"] = "Set marker",
  ["questchain.markerTip"] = "Sets a waypoint at the giver of this step.",
  ["questchain.map"] = "Map",
  ["questchain.mapTip"] = "Shows the giver of this step on the map.",
  ["questchain.next"] = "Next: %s",
  ["questchain.noteTruncated"] = "The chain is long: only the last %d steps are shown.",
  ["questchain.noteCycle"] = "The data has a loop between quests. It was ignored.",
  ["questchain.noteMissing"] = "%d prequests are not in the data.",
  ["questchain.keys"] = "Up and Down move between the buttons, Enter presses, Esc closes.",
})

ns.AddLocale("deDE", {
  ["questchain.title"] = "Questreihe",
  ["questchain.close"] = "Questreihe schließen",
  ["questchain.steps.one"] = "1 Schritt",
  ["questchain.steps.other"] = "%d Schritte",
  ["questchain.level"] = "Quest-Stufe %s",
  ["questchain.levelUnknown"] = "Quest-Stufe nicht in den Daten",
  ["questchain.from"] = "Verfügbar ab Stufe %d",
  ["questchain.fromPartial"] = "Verfügbar frühestens ab Stufe %d (nicht jeder Schritt hat eine Stufe)",
  ["questchain.fromUnknown"] = "Mindeststufe nicht in den Daten",
  ["questchain.stepLevel"] = "Stufe %d",
  ["questchain.stepLevelUnknown"] = "Stufe ?",
  ["questchain.stepFrom"] = "ab Stufe %d",
  ["questchain.stepFromChain"] = "ab Stufe %d mit den Vorquests",
  ["questchain.stepFromHint"] = "ab etwa Stufe %d (Hinweis, Mindeststufe nicht in den Daten)",
  ["questchain.stepFromUnknown"] = "ab Stufe: nicht in den Daten",
  ["questchain.xp"] = "%s EP",
  ["questchain.giver"] = "Geber: %s",
  ["questchain.giverZone"] = "Geber: %s in %s",
  ["questchain.giverNone"] = "Geber nicht erfasst",
  ["questchain.placeNone"] = "Ort nicht erfasst, daher kein Marker und keine Karte",
  ["questchain.tag.chosen"] = "Diese Quest",
  ["questchain.tag.access"] = "Zugangsquest",
  ["questchain.tag.from"] = "Aus %s",
  ["questchain.missing"] = "Quest %d ist nicht in den Daten",
  ["questchain.pair"] = "Gegenstück der anderen Fraktion: %s",
  ["questchain.marker"] = "Marker setzen",
  ["questchain.markerTip"] = "Setzt einen Wegpunkt beim Geber dieses Schritts.",
  ["questchain.map"] = "Karte",
  ["questchain.mapTip"] = "Zeigt den Geber dieses Schritts auf der Karte.",
  ["questchain.next"] = "Danach: %s",
  ["questchain.noteTruncated"] = "Die Kette ist lang: Es werden nur die letzten %d Schritte gezeigt.",
  ["questchain.noteCycle"] = "Die Daten haben einen Kreis zwischen Quests. Er wurde ignoriert.",
  ["questchain.noteMissing"] = "%d Vorquests fehlen in den Daten.",
  ["questchain.keys"] = "Pfeil hoch und runter wechseln zwischen den Knöpfen, Enter drückt, Esc schließt.",
})

local QW = {}
ns.QuestChainWindow = QW

local WIDTH, HEIGHT, TITLE_H, PAD = 540, 480, 24, 12
local NUMBER_W, BUTTON_W, BUTTON_H, GAP = 34, 112, 24, 6
local FOOT_H = 34
local CONTENT_W = WIDTH - 2 * PAD - 12

local frame

local function name(q)
  return q and ns.T(q.n) or nil
end

local function plural(n, key)
  return string.format(L[key .. (n == 1 and ".one" or ".other")], n)
end

-- Texts ------------------------------------------------------------------------------------------------------

-- The faction as text: the word is the cue, the color only adds to it.
function QW.FactionText(faction)
  local token = faction == "A" and "alliance" or faction == "H" and "horde" or "textMuted"
  return Theme.hexText(token, L["kit.faction." .. (faction == "B" and "all" or faction)])
end

-- "ab Stufe" text of one step (nil for a placeholder step).
function QW.FromText(avail)
  if not avail then
    return L["questchain.stepFromUnknown"]
  end
  local key = avail.kind == "chain" and "questchain.stepFromChain"
    or avail.kind == "hint" and "questchain.stepFromHint"
    or "questchain.stepFrom"
  return string.format(L[key], avail.level)
end

-- The place of a step for the marker and the map: { map, x, y, label, zone } or nil.
function QW.Place(step)
  if step.missing or not step.place then
    return nil
  end
  local q = step.quest
  return { map = q.m, x = q.x, y = q.y, label = step.giver or name(q), zone = step.zone and ns.T(step.zone) or nil }
end

-- Title, numbers line and giver line of a step, as plain texts: { title, meta, giver }.
-- opts.listRow: the row of the quest list, where the group header already names the faction.
function QW.Describe(step, inst, opts)
  if step.missing then
    return { title = string.format(L["questchain.missing"], step.id), meta = "", giver = "" }
  end
  local tags = {}
  if not (opts and opts.listRow) then
    tags[#tags + 1] = QW.FactionText(step.faction)
  end
  if step.chosen then
    tags[#tags + 1] = Theme.hexText("accent2", L["questchain.tag.chosen"])
  end
  if step.access then
    tags[#tags + 1] = Theme.hexText("textSecondary", L["questchain.tag.access"])
  end
  if step.external and step.inst and step.inst ~= inst then
    tags[#tags + 1] = Theme.hexText("textMuted", string.format(L["questchain.tag.from"], name(step.inst) or "?"))
  end
  local bits = {
    step.level and string.format(L["questchain.stepLevel"], step.level) or L["questchain.stepLevelUnknown"],
    QW.FromText(step.avail),
  }
  if step.xp and step.xp > 0 then
    bits[#bits + 1] = string.format(L["questchain.xp"], step.xp)
  end
  if step.gold and step.gold > 0 and ns.CostLogic then
    bits[#bits + 1] = ns.CostLogic.Format(step.gold)
  end
  local giver
  if not step.giver then
    giver = L["questchain.giverNone"]
  elseif step.zone and ns.T(step.zone) then
    giver = string.format(L["questchain.giverZone"], step.giver, ns.T(step.zone))
  else
    giver = string.format(L["questchain.giver"], step.giver)
  end
  if not step.place then
    giver = giver .. ". " .. L["questchain.placeNone"]
  end
  local pair = step.pairQuest and name(step.pairQuest)
  if pair then
    giver = giver .. "\n" .. string.format(L["questchain.pair"], pair)
  end
  return {
    title = (name(step.quest) or "?") .. (#tags > 0 and ("  " .. table.concat(tags, "  ")) or ""),
    meta = table.concat(bits, " · "),
    giver = giver,
  }
end

-- Header lines: the faction and the number of steps, then the levels of the chosen quest.
function QW.HeadLines(chain)
  local last = chain.steps[#chain.steps]
  local first = QW.FactionText(chain.faction) .. " · " .. plural(#chain.steps, "questchain.steps")
  local level = last and last.level and string.format(L["questchain.level"], last.level) or L["questchain.levelUnknown"]
  local from
  if chain.availableFrom then
    from = string.format(L[chain.partial and "questchain.fromPartial" or "questchain.from"], chain.availableFrom)
  else
    from = L["questchain.fromUnknown"]
  end
  return first, level .. " · " .. from
end

-- Notes under the steps: what comes next and what the data cannot say.
function QW.FootLines(chain)
  local lines = {}
  if #chain.next > 0 then
    local names = {}
    for _, step in ipairs(chain.next) do
      names[#names + 1] = step.missing and ("#" .. step.id) or (name(step.quest) or "?")
    end
    lines[#lines + 1] = string.format(L["questchain.next"], table.concat(names, ", "))
  end
  if chain.truncated then
    lines[#lines + 1] = string.format(L["questchain.noteTruncated"], QC.MAX_STEPS)
  end
  if chain.cycle then
    lines[#lines + 1] = L["questchain.noteCycle"]
  end
  if chain.missing > 0 then
    lines[#lines + 1] = string.format(L["questchain.noteMissing"], chain.missing)
  end
  return lines
end

-- Rows -------------------------------------------------------------------------------------------------------

local function ceil(fs)
  return math.ceil(fs:GetStringHeight())
end

local function makeRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bar = row:CreateTexture(nil, "ARTWORK")
  row.bar:SetPoint("TOPLEFT")
  row.bar:SetPoint("BOTTOMLEFT")
  row.bar:SetWidth(3)
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  ns.Bind(row, function()
    row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
    row.bar:SetColorTexture(Theme.color("accent2"))
    row.bg:SetColorTexture(Theme.color("accent2", row.chosen and 0.14 or 0))
  end)
  row.number = W.Text(row, { role = "h3", family = "heading", color = "accent2", justify = "CENTER" })
  row.title = W.Text(row, { role = "ui", color = "text", wrap = true })
  row.meta = W.Text(row, { role = "ui", color = "textSecondary", wrap = true })
  row.giver = W.Text(row, { role = "ui", color = "textSecondary", wrap = true })
  row.marker = W.Action(row, {
    key = "questchain.marker",
    tooltip = "questchain.marker",
    tooltipText = "questchain.markerTip",
    width = BUTTON_W,
    height = BUTTON_H,
    onClick = function()
      if row.place then
        ns.PageKit.PlaceMarker(row.place)
      end
    end,
  })
  row.map = W.Action(row, {
    key = "questchain.map",
    tooltip = "questchain.map",
    tooltipText = "questchain.mapTip",
    opens = true,
    width = BUTTON_W,
    height = BUTTON_H,
    onClick = function()
      if row.place then
        ns.PageKit.PlaceOnMap(row.place)
      end
    end,
  })

  function row:fgLayout(width)
    local textX = NUMBER_W + 6
    local textW = math.max(60, width - textX - BUTTON_W - 2 * PAD)
    self.number:ClearAllPoints()
    self.number:SetPoint("TOPLEFT", self, "TOPLEFT", 4, -PAD)
    self.number:SetWidth(NUMBER_W)
    local y = PAD
    for _, fs in ipairs({ self.title, self.meta, self.giver }) do
      if fs:IsShown() then
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -y)
        fs:SetWidth(textW)
        y = y + ceil(fs) + 2
      end
    end
    self.marker:ClearAllPoints()
    self.marker:SetPoint("TOPRIGHT", self, "TOPRIGHT", -PAD, -PAD)
    self.map:ClearAllPoints()
    self.map:SetPoint("TOPRIGHT", self.marker, "BOTTOMRIGHT", 0, -GAP)
    local buttons = self.marker:IsShown() and (PAD + 2 * BUTTON_H + GAP) or 0
    return math.max(y + PAD - 2, buttons + PAD)
  end
  return row
end

local function paintRow(row, step, chain, inst)
  local text = QW.Describe(step, inst)
  row.step = step
  row.chosen = step.chosen == true
  row.place = QW.Place(step)
  row.number:SetText(tostring(step.number))
  row.title:SetText(text.title)
  row.meta:SetText(text.meta)
  row.meta:SetShown(text.meta ~= "")
  row.giver:SetText(text.giver)
  row.giver:SetShown(text.giver ~= "")
  row.bar:SetShown(row.chosen)
  row.bg:SetColorTexture(Theme.color("accent2", row.chosen and 0.14 or 0))
  local usable = row.place ~= nil
  row.marker:SetShown(not step.missing)
  row.map:SetShown(not step.missing)
  row.marker:SetEnabled(usable)
  row.map:SetEnabled(usable)
  row.chain = chain
end

-- Window -----------------------------------------------------------------------------------------------------

local function inside(node, root)
  while node do
    if node == root then
      return true
    end
    node = node:GetParent()
  end
  return false
end

-- The buttons the keys walk: enabled and visible, top to bottom.
local function stops(f)
  local list = {}
  for _, row in ipairs(f.rows) do
    if row:IsShown() then
      for _, b in ipairs({ row.marker, row.map }) do
        if b:IsVisible() and b:IsEnabled() then
          list[#list + 1] = b
        end
      end
    end
  end
  return list
end

local function move(f, step)
  local list = stops(f)
  if #list == 0 then
    return
  end
  local index = 0
  for i, b in ipairs(list) do
    if b == ns.Focus.current then
      index = i
    end
  end
  if index == 0 then
    index = step > 0 and 1 or #list
  else
    index = index + step
    index = index < 1 and #list or index > #list and 1 or index
  end
  ns.Focus.set(list[index])
end

local function handleKey(f, key)
  if key == "ESCAPE" then
    return ns.EscStack.Close(f)
  end
  local current = ns.Focus.current
  local mine = current ~= nil and inside(current, f)
  -- Other keys only with the pointer over the window or the focus in it, so walking keeps working.
  if not mine and not f:IsMouseOver() then
    return false
  end
  if key == "TAB" then
    move(f, IsShiftKeyDown() and -1 or 1)
    return true
  elseif key == "UP" or key == "DOWN" then
    move(f, key == "UP" and -1 or 1)
    return true
  elseif key == "ENTER" or key == "SPACE" then
    if mine then
      return ns.Focus.activate()
    elseif key == "ENTER" and f.chain then
      local last = f.chain.steps[#f.chain.steps]
      local place = last and QW.Place(last)
      if place then
        ns.PageKit.PlaceMarker(place)
        return true
      end
    end
  end
  return false
end

local function layout(f)
  local top = ns.WindowShell.HeadHeight(f) + 8
  f.head:ClearAllPoints()
  f.head:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -top)
  f.head:SetWidth(WIDTH - 2 * PAD)
  local y = top + ceil(f.head) + 2
  f.sub:ClearAllPoints()
  f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
  f.sub:SetWidth(WIDTH - 2 * PAD)
  y = y + ceil(f.sub) + 2
  f.where:ClearAllPoints()
  f.where:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
  f.where:SetWidth(WIDTH - 2 * PAD)
  y = y + ceil(f.where) + 8
  f.scroll:ClearAllPoints()
  f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
  f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD + FOOT_H)

  local at = 0
  for _, row in ipairs(f.rows) do
    if row:IsShown() then
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", f.scroll.content, "TOPLEFT", 0, -at)
      row:SetWidth(CONTENT_W)
      local h = row:fgLayout(CONTENT_W)
      row:SetHeight(h)
      at = at + h
    end
  end
  if f.foot:IsShown() then
    f.foot:ClearAllPoints()
    f.foot:SetPoint("TOPLEFT", f.scroll.content, "TOPLEFT", 4, -(at + 10))
    f.foot:SetWidth(CONTENT_W - 8)
    at = at + 10 + ceil(f.foot) + 8
  end
  f.scroll:SetContentHeight(at)
end

local function create()
  local f = CreateFrame("Frame", "FGQuestChainWindow", UIParent)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  W.Fill(f, "bg", 0.97)
  local shell = ns.WindowShell.Attach(f, { title = "questchain.title", titleHeight = TITLE_H, shadow = true })
  local close = W.Action(shell.titleBar, { icon = "close", size = 18, tooltip = "questchain.close" })
  close:SetPoint("RIGHT", -4, 0)
  close:SetScript(
    "OnClick",
    ns.Wrap("questchain-close", function()
      ns.SafeHide(f)
    end)
  )
  shell.titleText:ClearAllPoints()
  shell.titleText:SetPoint("LEFT", 8, 0)
  shell.titleText:SetPoint("RIGHT", close, "LEFT", -4, 0)
  f.close = close

  f.head = W.Text(f, { role = "h3", color = "text", wrap = true })
  f.sub = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  f.where = W.Text(f, { role = "micro", color = "textMuted", wrap = true })
  f.scroll = W.ScrollArea(f)
  f.foot = W.Text(f.scroll.content, { role = "ui", color = "textSecondary", wrap = true })
  f.keys = W.Text(f, { key = "questchain.keys", role = "micro", color = "textMuted", wrap = true })
  f.keys:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
  f.keys:SetWidth(WIDTH - 2 * PAD)
  f.rows = {}

  f:SetScript("OnShow", function()
    f:SetScale(Theme.windowScale())
    f:Raise()
    ns.WindowShell.FitToScreen(f)
  end)
  f:SetScript("OnKeyDown", function(self, key)
    local _, handled = ns.Safe("questchain-key", handleKey, self, key)
    ns.PropagateKeys(self, not handled)
  end)
  ns.On("PLAYER_REGEN_DISABLED", function()
    ns.PropagateKeys(f, true)
  end)
  ns.WindowShell.RegisterEsc(f)
  f:Hide()
  return f
end

function QW.Frame()
  return frame
end

-- The chain model of the open window (see QuestChainLogic.Chain), nil before the first open.
function QW.Chain()
  return frame and frame.chain
end

-- Shows the chain of `quest` (an entry of inst.q, or a merged copy of one) and returns the window.
-- opts.instances: the instances to look prequests up in (default the data).
function QW.Open(inst, quest, opts)
  if not (inst and quest) then
    return nil
  end
  if not frame then
    frame = create()
  end
  local f = frame
  local chain = QC.Chain(inst, quest, opts)
  f.inst, f.quest, f.chain = inst, quest, chain
  W.SetText(ns.WindowShell.Of(f).titleText, nil, name(quest) or "?")
  local head, sub = QW.HeadLines(chain)
  f.head:SetText(head)
  f.sub:SetText(sub)
  f.where:SetText(name(inst) or "")
  for i, step in ipairs(chain.steps) do
    local row = f.rows[i]
    if not row then
      row = makeRow(f.scroll.content)
      f.rows[i] = row
    end
    paintRow(row, step, chain, inst)
    row:Show()
  end
  for i = #chain.steps + 1, #f.rows do
    f.rows[i]:Hide()
  end
  local foot = QW.FootLines(chain)
  f.foot:SetText(table.concat(foot, "\n"))
  f.foot:SetShown(#foot > 0)
  f:Show()
  layout(f)
  f.scroll:ScrollTo(0)
  return f
end

function QW.Close()
  if frame then
    ns.SafeHide(frame)
  end
end

-- Re-lays out the open window (after a font or scale change).
function QW.Relayout()
  if frame and frame:IsShown() then
    layout(frame)
  end
end
