-- Enchant and gems next to the equipment slots of the character window and of the inspect window
-- (the unit comes from InspectOverlay, the same code paints both): the enchant text in
-- green (or a red note when a slot that takes an enchant has none) and up to three small gem
-- icons, on the side of the slot that faces the model. Slots of the left column write to their
-- right, slots of the right column to their left, the weapon slots below the model write above
-- the slot. In the inspect window every slot shows the short marker only ("+" green, "!" red) with
-- the full text as hover tooltip, so nothing runs over the model or into the next slot. Only a
-- post-hook on PaperDollItemSlotButton_Update, an OnShow hook on CharacterFrame and game events;
-- the regions (one FontString, three textures, one hover-only frame) live in button.fgEnch, nothing of Blizzard's is written. A button repaints only when its item, its
-- layout or a setting changed. A button that needs its regions while in combat is queued and
-- finished at PLAYER_REGEN_ENABLED.
local _, ns = ...
local I = ns.ItemInfo
local O = ns.ItemLevelOverlay

local E = {}
ns.ItemEnchantOverlay = E

ns.AddLocale("enUS", {
  ["ench.none"] = "No enchant",
  ["ench.enchanted"] = "Enchanted",
})
ns.AddLocale("deDE", {
  ["ench.none"] = "Keine Verzauberung",
  ["ench.enchanted"] = "Verzaubert",
})

E.SIZE_MIN, E.SIZE_MAX = 9, 14
local MAX_WIDTH = 110 -- widest text line in pixels
local MIN_TEXT_ROOM = 60 -- less room than this: a short marker instead of the text
local SLOT_PITCH = 46 -- the weapon slots sit side by side, so they get no more than this
local SLOT_SIZE = 40
local GEM_SIZE, GEM_STEP, MAX_GEMS = 14, 15, 3
local GAP = 8
local HIT_SIZE = 18 -- hover area of a marker, the character itself is only a few pixels wide
local FALLBACK_ICON = 134400
local GREEN = { 0.1, 1, 0.1 }
local RED = { 1, 0.25, 0.25 }
local MARKER_OK, MARKER_MISSING = "+", "!"
E.MARKER_OK, E.MARKER_MISSING = MARKER_OK, MARKER_MISSING
-- Height the marker and the gem row of a weapon slot take above the slot (gems, gap, one line of
-- the largest font): what a panel above the weapon row has to leave free.
E.BOTTOM_RESERVE = GEM_SIZE + 4 + E.SIZE_MAX

-- Slot groups of Blizzard_UIPanels_Game (Camelot/PaperDollFrame.xml): PaperDollItemSlotButton-
-- LeftTemplate, ...RightTemplate and ...BottomTemplate. The measured slot position wins over this.
local GROUP = {}
for _, id in ipairs({ 1, 2, 3, 15, 5, 4, 19, 9 }) do
  GROUP[id] = "left"
end
for _, id in ipairs({ 10, 6, 7, 8, 11, 12, 13, 14 }) do
  GROUP[id] = "right"
end
for _, id in ipairs({ 16, 17, 18 }) do
  GROUP[id] = "bottom"
end
E.GROUP = GROUP

local handled = {}
for _, slot in ipairs(I.SLOTS) do
  handled[slot.id] = slot.overlay ~= false and slot.name or nil
end

local weak = { __mode = "k" }
local painted = setmetatable({}, weak) -- button -> cache key of its last evaluation
local known = setmetatable({}, weak) -- button -> true
local units = setmetatable({}, weak) -- inspect button -> unit token it shows
local pending = setmetatable({}, weak) -- button -> true, waiting for the end of combat
local generation = 0 -- bumped by every setting change, part of the cache key

-- work: evaluations that got past the cache, paints: slot lines written.
E.stats = { work = 0, paints = 0 }
E.Option = O.Option

function E.Size()
  local n = tonumber(E.Option("enchantSize")) or 10
  return math.max(E.SIZE_MIN, math.min(E.SIZE_MAX, math.floor(n)))
end

local size = E.Size

local function slotOf(button)
  local f = button.GetID
  if type(f) ~= "function" then
    return nil
  end
  local ok, id = pcall(f, button)
  if ok and I.readable(id) and handled[id] then
    return id
  end
end

local function measure(frame, name)
  local f = type(frame) == "table" and frame[name]
  if type(f) ~= "function" then
    return nil
  end
  local ok, value = pcall(f, frame)
  return ok and I.readable(value) and value or nil
end

-- Side of the slot ("left", "right", "bottom") and the room for text in pixels between the slot
-- and the middle of the model. The middle is halfway between the centers of the head and the
-- hands slot (the top slot of each column), the window center when those are unknown. The inspect
-- window has the same slot names with the prefix "Inspect".
local function layout(button, id, inspected)
  local group = GROUP[id]
  if group == "bottom" then
    return group, SLOT_PITCH
  end
  local prefix = inspected and "Inspect" or "Character"
  local x = measure(button, "GetCenter")
  local head = measure(rawget(_G, prefix .. "HeadSlot"), "GetCenter")
  local hands = measure(rawget(_G, prefix .. "HandsSlot"), "GetCenter")
  local mid
  if head and hands and hands > head then
    mid = (head + hands) / 2
  else
    mid = measure(rawget(_G, inspected and "InspectFrame" or "CharacterFrame"), "GetCenter")
  end
  if not (x and mid) then
    return group, MAX_WIDTH
  end
  local width = measure(button, "GetWidth") or SLOT_SIZE
  return x < mid and "left" or "right", math.abs(x - mid) - width / 2 - GAP / 2
end

local function textMode(room)
  return room >= MIN_TEXT_ROOM
end

-- Shortens text with "..." until it is at most max pixels wide; leaves the text in the FontString.
-- Returns the shown text. Cuts between UTF-8 characters.
local function fit(fs, text, max)
  fs:SetText(text)
  if fs:GetStringWidth() <= max then
    return text
  end
  local chars = {}
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    chars[#chars + 1] = ch
  end
  local lo, hi = 0, #chars
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    fs:SetText(table.concat(chars, "", 1, mid) .. "...")
    if fs:GetStringWidth() <= max then
      lo = mid
    else
      hi = mid - 1
    end
  end
  local out = table.concat(chars, "", 1, lo) .. "..."
  fs:SetText(out)
  return out
end

E.Fit = fit

local function showTip(rec, owner)
  local tooltip = rawget(_G, "GameTooltip")
  local tip = rec.tip
  if type(tooltip) ~= "table" or not tip then
    return
  end
  tooltip:SetOwner(owner, "ANCHOR_RIGHT")
  tooltip:SetText(tip, rec.tipColor[1], rec.tipColor[2], rec.tipColor[3], 1, true)
  tooltip:Show()
end

-- The regions of a button, created on first use. Not while in combat.
local function build(button)
  if O.InCombat() then
    return nil
  end
  local okFs, fs = pcall(button.CreateFontString, button, nil, "OVERLAY")
  if not (okFs and fs) then
    return nil
  end
  fs:SetDrawLayer("OVERLAY", 7)
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetWordWrap(false)
  local rec = { fs = fs, gems = {}, tipColor = GREEN }
  for i = 1, MAX_GEMS do
    local okTex, tex = pcall(button.CreateTexture, button, nil, "OVERLAY")
    if okTex and tex then
      tex:SetSize(GEM_SIZE, GEM_SIZE)
      tex:Hide()
      rec.gems[i] = tex
    end
  end
  local okHit, hit = pcall(CreateFrame, "Frame", nil, button)
  if okHit and hit then
    hit:SetAllPoints(fs)
    hit:EnableMouse(true)
    -- Hover only: the slot below keeps every click and drag.
    if type(hit.SetMouseClickEnabled) == "function" then
      pcall(hit.SetMouseClickEnabled, hit, false)
    end
    hit:SetScript("OnEnter", function(self)
      showTip(rec, self)
    end)
    hit:SetScript("OnLeave", function()
      local tooltip = rawget(_G, "GameTooltip")
      if type(tooltip) == "table" then
        tooltip:Hide()
      end
    end)
    hit:Hide()
    rec.hit = hit
  end
  button.fgEnch = rec
  return rec
end

local function hide(button)
  local rec = button.fgEnch
  if not rec then
    return
  end
  rec.state = nil
  rec.fs:Hide()
  if rec.hit then
    rec.hit:Hide()
  end
  for _, tex in ipairs(rec.gems) do
    tex:Hide()
  end
end

-- Anchors the line and the gem row for the side of the slot.
local function place(rec, button, side)
  if rec.side == side then
    return
  end
  rec.side = side
  local fs = rec.fs
  fs:ClearAllPoints()
  if side == "left" then
    fs:SetPoint("LEFT", button, "RIGHT", GAP, 6)
    fs:SetJustifyH("LEFT")
  elseif side == "right" then
    fs:SetPoint("RIGHT", button, "LEFT", -GAP, 6)
    fs:SetJustifyH("RIGHT")
  else
    fs:SetPoint("BOTTOM", button, "TOP", 0, GEM_SIZE + 4)
    fs:SetJustifyH("CENTER")
  end
  for i, tex in ipairs(rec.gems) do
    tex:ClearAllPoints()
    if side == "left" then
      tex:SetPoint("LEFT", button, "RIGHT", GAP + (i - 1) * GEM_STEP, -8)
    elseif side == "right" then
      tex:SetPoint("RIGHT", button, "LEFT", -GAP - (i - 1) * GEM_STEP, -8)
    else
      tex:SetPoint("BOTTOM", button, "TOP", (i - 2) * GEM_STEP, 2)
    end
  end
end

local function paintGems(rec, gems, empty)
  for i, tex in ipairs(rec.gems) do
    local gem = gems[i]
    if gem then
      tex:SetTexture(gem.icon or FALLBACK_ICON)
      tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      tex:Show()
    elseif i <= #gems + empty then
      tex:SetColorTexture(0.1, 0.1, 0.1, 0.8)
      tex:SetTexCoord(0, 1, 0, 1)
      tex:Show()
    else
      tex:Hide()
    end
  end
end

-- what: { text = string or nil, color = {r,g,b}, gems = list, empty = number }
local function paint(button, rec, what, side, room)
  local fontSize = size()
  if rec.fgSize ~= fontSize then
    rec.fgSize = fontSize
    rec.fgFont = O.SetFont(rec.fs, fontSize)
  end
  if not rec.fgFont then
    hide(button)
    return
  end
  place(rec, button, side)
  paintGems(rec, what.gems, what.empty)
  local shown
  if what.text then
    local color = what.color
    rec.fs:SetTextColor(color[1], color[2], color[3])
    if textMode(room) then
      shown = fit(rec.fs, what.text, math.min(MAX_WIDTH, room))
    else
      shown = what.marker
      rec.fs:SetText(shown)
    end
    rec.tip, rec.tipColor = what.text, color
    rec.fs:Show()
    if rec.hit then
      rec.hit:ClearAllPoints()
      if textMode(room) then
        rec.hit:SetAllPoints(rec.fs)
      else
        rec.hit:SetPoint("CENTER", rec.fs, "CENTER")
        rec.hit:SetSize(HIT_SIZE, HIT_SIZE)
      end
      rec.hit:Show()
    end
    E.stats.paints = E.stats.paints + 1
  else
    rec.tip = nil
    rec.fs:Hide()
    if rec.hit then
      rec.hit:Hide()
    end
  end
  rec.state = { side = side, mode = textMode(room) and "text" or "marker", text = shown }
end

local function clear(button, key)
  if painted[button] ~= key then
    painted[button] = key
    hide(button)
  end
end

-- Evaluates one equipment slot button. unit: the inspected unit for a slot of the inspect window
-- (remembered for later refreshes), nil for the own character window.
function E.Update(button, unit)
  if type(button) ~= "table" then
    return
  end
  local id = slotOf(button)
  if not id then
    return
  end
  unit = unit or units[button]
  units[button] = unit
  known[button] = true
  if E.Option("enchantOverlay") == false or (unit and E.Option("enchantInspect") == false) then
    return clear(button, generation .. "|off")
  end
  local link = I.inventoryLink(id, unit)
  if link == nil then
    return clear(button, generation .. "|empty")
  end
  local side, room = layout(button, id, unit ~= nil)
  if unit then
    -- Another player's window is crowded: only the marker at the slot, the text is in its tooltip.
    room = 0
  end
  local key = table.concat({ generation, tostring(link), side, textMode(room) and "t" or "m" }, "|")
  if painted[button] == key then
    return
  end
  E.stats.work = E.stats.work + 1
  local info = I.enchantInfo(id, link, unit)
  local enchanted = info ~= nil and (info.id ~= nil or info.text ~= nil)
  local missing = not enchanted
    and E.Option("enchantMissing") ~= false
    and I.enchantable(id, link, I.flaggedSlots(E.Option("enchantSlots"))) == true
  local gems, empty = {}, 0
  if E.Option("enchantGems") ~= false then
    gems = I.gems(id, link, unit)
    local sockets = I.numSockets(link)
    if sockets then
      empty = math.max(0, math.min(MAX_GEMS, sockets) - #gems)
    end
  end
  local what = { gems = gems, empty = empty }
  if enchanted then
    what.text = I.enchantName(info.text) or ns.L["ench.enchanted"]
    what.color, what.marker = GREEN, MARKER_OK
  elseif missing then
    what.text = ns.L["ench.none"]
    what.color, what.marker = RED, MARKER_MISSING
  end
  if not (what.text or #gems > 0 or empty > 0) then
    return clear(button, key)
  end
  local rec = button.fgEnch
  if not rec then
    if O.InCombat() then
      pending[button] = true
      return
    end
    rec = build(button)
    if not rec then
      return
    end
  end
  paint(button, rec, what, side, room)
  -- An enchant id without a readable tooltip line is looked at again on the next update.
  if enchanted and info.text == nil then
    painted[button] = nil
  else
    painted[button] = key
  end
end

-- Evaluates every slot frame by name and every button seen so far.
function E.Scan()
  for id, name in pairs(handled) do
    local button = rawget(_G, "Character" .. name)
    if type(button) == "table" and slotOf(button) == id then
      ns.Safe("itemenchant", E.Update, button)
    end
  end
  for button in pairs(known) do
    ns.Safe("itemenchant", E.Update, button)
  end
end

-- Applies a changed setting to every button seen so far.
function E.Refresh()
  generation = generation + 1
  E.Scan()
end

-- Finishes the buttons that needed their regions during combat.
function E.Flush()
  local queue = {}
  for button in pairs(pending) do
    queue[#queue + 1] = button
  end
  for _, button in ipairs(queue) do
    pending[button] = nil
    ns.Safe("itemenchant", E.Update, button)
  end
end

-- What the probe needs for one slot: side, mode ("text" or "marker") and whether a line was painted.
function E.Describe(id)
  local name = handled[id]
  local button = name and rawget(_G, "Character" .. name) or nil
  if type(button) ~= "table" then
    return nil
  end
  local side, room = layout(button, id)
  local rec = type(button.fgEnch) == "table" and button.fgEnch or nil
  local state = rec and rec.state
  return {
    side = side,
    mode = textMode(room) and "text" or "marker",
    painted = state ~= nil and state.text ~= nil,
    text = state and state.text,
  }
end

local HOOKS = {
  PaperDollItemSlotButton_Update = function(button)
    ns.Safe("itemenchant", E.Update, button)
  end,
}
local hooked = {}
E.hooked = hooked
local frameHooked = false

-- name -> true for every hook that is in place. Missing targets are retried at the next call.
function E.Install()
  for name, fn in pairs(HOOKS) do
    if not hooked[name] and type(hooksecurefunc) == "function" and type(rawget(_G, name)) == "function" then
      hooked[name] = pcall(hooksecurefunc, name, fn) or nil
    end
  end
  local frame = rawget(_G, "CharacterFrame")
  if not frameHooked and type(frame) == "table" and type(frame.HookScript) == "function" then
    frameHooked = pcall(frame.HookScript, frame, "OnShow", function()
      ns.Safe("itemenchant", E.Scan)
    end)
  end
  return hooked
end

function E.HookNames()
  local names = {}
  for name in pairs(HOOKS) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

ns.On("PLAYER_LOGIN", E.Install)
ns.On("ADDON_LOADED", function()
  if not frameHooked or not hooked.PaperDollItemSlotButton_Update then
    E.Install()
  end
end)
ns.On("PLAYER_EQUIPMENT_CHANGED", E.Scan)
ns.On("UNIT_INVENTORY_CHANGED", function(_, unit)
  if unit == nil or unit == "player" then
    E.Scan()
  end
end)
ns.On("PLAYER_REGEN_ENABLED", E.Flush)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.enchant") then
    E.Refresh()
  end
end)
