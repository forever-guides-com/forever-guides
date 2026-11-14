-- Find window of a rare enemy: centered low on the screen with the name, level, a 3D model of the creature
-- above it, the known loot (the item row of Modules/RareCard.lua), a close button and arrows to page through
-- the last rares found. It never takes the keyboard. A click on the window targets the creature: the body and the model area are secure
-- buttons with a macro, so the attributes only change outside of combat. A find in combat waits for
-- PLAYER_REGEN_ENABLED; closing hides the window through ns.SafeHide. Dragging with the key of rareFoundMove
-- (Shift by default, ns.Keys) moves the window, the position is saved. The list, the macro and the decisions
-- are in Modules/RareFoundLogic.lua.
--
-- API (ns.RareFound):
--   Show(id, rare, unitName)  a rare was found (npc id, its data entry, the name of the unit when known)
--   Page(dir)                 -1 or 1, the next entry of the list (not in combat)
--   Close()                   empties the list and hides the window
--   ResetPosition()           back to the default place
--   Frame()                   the window, nil until the first find
local _, ns = ...
local L, RL, RFL, W = ns.L, ns.RareLogic, ns.RareFoundLogic, ns.W

local RF = {}
ns.RareFound = RF

ns.AddLocale("enUS", {
  ["rare.found.target"] = "Click to target, right click to close",
  ["rare.found.prev"] = "Previous rare",
  ["rare.found.next"] = "Next rare",
})
ns.AddLocale("deDE", {
  ["rare.found.target"] = "Klicken zum Anvisieren, Rechtsklick schließt",
  ["rare.found.prev"] = "Vorheriger Seltener",
  ["rare.found.next"] = "Nächster Seltener",
})

local WIDTH, PAD, SIDE = 300, 12, 28
local MODEL_SIZE = 170
local TICK = 1

local entries, index = {}, 1
local pending = false
local frame

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a = pcall(fn, ...)
  if ok then
    return a
  end
end

local function clock()
  local now = call(rawget(_G, "GetTime"))
  return type(now) == "number" and now or 0
end

local function number(v, fallback)
  v = tonumber(v)
  if v == nil or v ~= v then
    return fallback
  end
  return v
end

-- Position -------------------------------------------------------------------------------------------------

local function savedPosition()
  return ns.db and ns.db.frames and ns.db.frames.rareFound
end

local function applyPosition()
  local point, rel, x, y = RFL.Position(savedPosition(), RFL.DEFAULT_POSITION)
  frame:ClearAllPoints()
  frame:SetPoint(point, UIParent, rel, x, y)
end

local function savePosition()
  if not (ns.db and ns.db.frames) then
    return
  end
  local point, _, rel, x, y = frame:GetPoint(1)
  ns.db.frames.rareFound = { point = point, rel = rel, x = number(x, 0), y = number(y, 0) }
end

-- Model --------------------------------------------------------------------------------------------------

local function modelReady(model)
  local fn = model.GetModelFileID
  if type(fn) ~= "function" then
    return true
  end
  local ok, id = pcall(fn, model)
  return ok and RFL.HasModel(id)
end

-- The model shows once the client reports a file for it; a creature it cannot draw leaves it hidden.
local function setModel(npcId)
  local model = frame.model
  if not model then
    return
  end
  model:Hide()
  local ok = pcall(function()
    model:ClearModel()
    model:SetCreature(npcId)
  end)
  if ok and modelReady(model) then
    model:Show()
  end
end

-- Build --------------------------------------------------------------------------------------------------

local function wireHit(btn)
  -- Both edges: the secure handler acts on the press or the release, depending on the client setting for
  -- action keys, and drops the other one.
  btn:RegisterForClicks("AnyUp", "AnyDown")
  -- Right click closes: a type without an action keeps the secure handler idle for that button.
  btn:SetAttribute("type2", "close")
  btn:HookScript("OnClick", function(_, button)
    if button == "RightButton" then
      RF.Close()
    end
  end)
  btn:RegisterForDrag("LeftButton")
  btn:HookScript("OnDragStart", function()
    if ns.Keys.Matches("rareFoundMove") and not ns.InCombat() then
      frame:StartMoving()
      frame.moving = true
    end
  end)
  btn:HookScript("OnDragStop", function()
    if frame.moving then
      frame.moving = nil
      pcall(frame.StopMovingOrSizing, frame)
      savePosition()
    end
  end)
  btn:HookScript("OnEnter", function()
    W.SetColor(frame.hint, "accent2")
  end)
  btn:HookScript("OnLeave", function()
    W.SetColor(frame.hint, "textMuted")
  end)
end

local function secureButton(parent)
  local btn = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
  wireHit(btn)
  return btn
end

local function expire(self, dt)
  self.acc = (self.acc or 0) + (tonumber(dt) or 0)
  if self.acc < TICK then
    return
  end
  self.acc = 0
  if RFL.Prune(entries, clock()) > 0 then
    RF.Update()
  end
end

local function build()
  frame = CreateFrame("Frame", nil, UIParent)
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetWidth(WIDTH)
  W.Fill(frame, "surface", 0.95)
  W.Border(frame, "white")

  local ok, model = pcall(CreateFrame, "PlayerModel", nil, frame)
  if ok and model then
    frame.model = model
    model:SetSize(MODEL_SIZE, MODEL_SIZE)
    model:SetPoint("BOTTOM", frame, "TOP", 0, 0)
    model:EnableMouse(false)
    model:SetScript("OnModelLoaded", function(self)
      if modelReady(self) then
        self:Show()
      end
    end)
    model:Hide()
  end

  frame.body = secureButton(frame)
  frame.body:SetAllPoints(frame)
  if frame.model then
    frame.modelHit = secureButton(frame)
    frame.modelHit:SetAllPoints(frame.model)
  end

  frame.name = W.Text(frame, { role = "h3", family = "heading", color = "accent2", wrap = true, justify = "CENTER" })
  frame.name:SetPoint("TOP", frame, "TOP", 0, -PAD)
  frame.name:SetWidth(WIDTH - 2 * SIDE)
  frame.head = W.Text(frame, { role = "body", color = "textSecondary", justify = "CENTER" })
  frame.head:SetWidth(WIDTH - 2 * SIDE)
  frame.hint = W.Text(frame, { role = "small", color = "textMuted", key = "rare.found.target", justify = "CENTER" })
  frame.hint:SetPoint("BOTTOM", frame, "BOTTOM", 0, PAD)
  -- Full width: the arrows sit at mid height, the bottom line is free.
  frame.hint:SetWidth(WIDTH - 16)
  frame.count = W.Text(frame, { role = "micro", color = "textMuted" })
  frame.count:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)

  frame.row = ns.RareCard.ItemRow(frame)
  frame.prev = W.Action(frame, {
    icon = "chevron-left",
    size = 20,
    boxed = true,
    tooltip = "rare.found.prev",
    onClick = function()
      RF.Page(-1)
    end,
  })
  frame.prev:SetPoint("LEFT", frame, "LEFT", 4, 0)
  frame.next = W.Action(frame, {
    icon = "chevron-right",
    size = 20,
    boxed = true,
    tooltip = "rare.found.next",
    onClick = function()
      RF.Page(1)
    end,
  })
  frame.next:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
  frame.close = W.CloseButton(frame, {
    onClick = function()
      RF.Close()
    end,
  })

  -- The target buttons cover the whole window: the controls sit above them, or their clicks would target.
  local top = frame.body:GetFrameLevel() + 2
  for _, child in ipairs({ frame.row, frame.prev, frame.next, frame.close }) do
    child:SetFrameLevel(top)
  end

  frame:SetScript("OnUpdate", expire)
  -- No Esc: a keyboard handler on a frame with secure children can swallow every key (walking, bars),
  -- and the window pops up unasked. It closes with its button or runs out by itself.
  frame:Hide()
  return frame
end

-- Content -------------------------------------------------------------------------------------------------

local function setTarget(macro)
  for _, btn in ipairs({ frame.body, frame.modelHit }) do
    btn:SetAttribute("type", macro and "macro" or nil)
    btn:SetAttribute("macrotext", macro)
  end
  frame.hint:SetShown(macro ~= nil)
end

-- Texts, loot, target and size of the entry on show; only called outside of combat.
local function render()
  local entry = entries[index]
  local rare = entry and ns.DataApi.Rare(entry.id)
  if not rare then
    return
  end
  local name = RL.Name(rare, ns.GetActiveLocale())
  frame.name:SetText(name or entry.unitName or "?")
  local nameHeight = number(call(frame.name.GetStringHeight, frame.name), 16)
  frame.head:ClearAllPoints()
  frame.head:SetPoint("TOP", frame.name, "BOTTOM", 0, -2)
  frame.head:SetText(RL.CardHead(rare, L))
  local height = PAD + nameHeight + 2 + 16
  local items = RL.CardItems(rare)
  frame.row:SetShown(#items > 0)
  if #items > 0 then
    local _, rowHeight = frame.row:SetItems(items)
    frame.row:ClearAllPoints()
    frame.row:SetPoint("TOP", frame, "TOP", 0, -(height + 8))
    height = height + 8 + rowHeight
  end
  frame:SetHeight(height + 8 + 14 + PAD)
  setTarget(RFL.Macro(RFL.TargetName(entry.unitName, name)))
  setModel(entry.id)
  frame.count:SetText(#entries > 1 and (index .. "/" .. #entries) or "")
  frame.prev:SetShown(#entries > 1)
  frame.next:SetShown(#entries > 1)
  applyPosition()
  frame:Show()
end

-- Brings the window in line with the list: hides it when the list is empty, otherwise paints now or after
-- the combat.
function RF.Update()
  RFL.Prune(entries, clock())
  index = RFL.Clamp(index, #entries)
  if #entries == 0 then
    pending = false
    if frame then
      ns.SafeHide(frame)
    end
    return
  end
  frame = frame or build()
  if RFL.Route(ns.InCombat()) == "queue" then
    pending = true
    return
  end
  pending = false
  render()
end

function RF.Show(id, rare, unitName)
  if type(rare) ~= "table" then
    return
  end
  RFL.Add(entries, { id = id, unitName = type(unitName) == "string" and unitName or nil }, clock())
  index = 1
  RF.Update()
end

function RF.Page(dir)
  if RFL.Route(ns.InCombat()) == "queue" or #entries < 2 then
    return
  end
  index = RFL.Step(index, #entries, dir)
  RF.Update()
end

function RF.Close()
  for i = #entries, 1, -1 do
    entries[i] = nil
  end
  index = 1
  RF.Update()
end

function RF.ResetPosition()
  if ns.db and ns.db.frames then
    ns.db.frames.rareFound = nil
  end
  if frame and frame:IsShown() then
    pending = true
    RF.Update()
  end
end

function RF.Frame()
  return frame
end

-- For tests and diagnostics: the list and whether a repaint waits for the end of combat.
function RF.State()
  return entries, index, pending
end

ns.On("PLAYER_REGEN_ENABLED", function()
  if pending then
    RF.Update()
  end
end)
