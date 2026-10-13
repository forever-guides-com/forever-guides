-- Item level as a small number in a corner of the item icon: on the equipment slots of the
-- character window, of the inspect window (kind "inspect", the unit comes from InspectOverlay)
-- and on the item buttons of the bags and the bank, colored by quality.
-- Only post-hooks (hooksecurefunc) on Blizzard's update functions: PaperDollItemSlotButton_Update
-- for the slots and SetItemButtonQuality for container and bank buttons (it runs on every
-- refresh of those buttons, whatever the bag layout). The one FontString per button lives in
-- button.fgIlvl, nothing else of Blizzard's is written. A button repaints only when its item
-- or a setting changed. A button that needs a new FontString while in combat is queued and
-- finished at PLAYER_REGEN_ENABLED.
-- Slots of the character and the inspect window carry everything of ours on one named child frame
-- (O.SlotFrame), and settings.slotOverlays decides what we draw there while another add-on draws
-- item level and enchant text itself (O.Policy, HostSkin.SheetOwner).
local _, ns = ...
local I = ns.ItemInfo
local H = ns.HostSkin

local O = {}
ns.ItemLevelOverlay = O

local CORNERS = {
  TOPRIGHT = { x = -2, y = -2, justify = "RIGHT" },
  BOTTOMRIGHT = { x = -2, y = 2, justify = "RIGHT" },
  TOPLEFT = { x = 2, y = -2, justify = "LEFT" },
}
O.SIZE_MIN, O.SIZE_MAX = 9, 16
local KIND_OPTION = { equip = "itemLevelCharacter", bag = "itemLevelBags", inspect = "itemLevelInspect" }

local shownSlots = {}
for _, slot in ipairs(I.SLOTS) do
  shownSlots[slot.id] = slot.overlay ~= false
end

local weak = { __mode = "k" }
local painted = setmetatable({}, weak) -- button -> cache key of its last evaluation
local known = setmetatable({}, weak) -- button -> kind ("equip", "bag" or "inspect")
local units = setmetatable({}, weak) -- inspect button -> unit token it shows
local pending = setmetatable({}, weak) -- button -> kind, waiting for the end of combat
local generation = 0 -- bumped by every setting change, part of the cache key

-- work: evaluations that got past the cache, paints: numbers written to a FontString.
O.stats = { work = 0, paints = 0 }

function O.Option(key)
  local settings = ns.db and ns.db.settings
  local value = settings and settings[key]
  if value == nil then
    value = ns.Store.defaults.settings[key]
  end
  return value
end

local function corner()
  local name = O.Option("itemLevelCorner")
  return CORNERS[name] and name or "TOPRIGHT"
end

local function size()
  local n = tonumber(O.Option("itemLevelSize")) or 12
  return math.max(O.SIZE_MIN, math.min(O.SIZE_MAX, math.floor(n)))
end

local function minQuality()
  return tonumber(O.Option("itemLevelMinQuality")) or 1
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- Calls obj:name(...) when it exists, nil on any problem.
local function call(obj, name, ...)
  local f = type(obj) == "table" and obj[name]
  if type(f) ~= "function" then
    return nil
  end
  local ok, a = pcall(f, obj, ...)
  return ok and a or nil
end

local function safe(f, ...)
  if type(f) ~= "function" then
    return nil
  end
  local ok, a = pcall(f, ...)
  return ok and a or nil
end

-- Where the button's item is: ("equip", "inspect") inventory slot id, ("bag") bag id and slot.
-- Container buttons know GetBagID and GetID; bank buttons GetBankTabID and GetContainerSlotID.
local function placeOf(button, kind)
  if kind ~= "bag" then
    local id = call(button, "GetID")
    if I.readable(id) and shownSlots[id] then
      return id
    end
    return nil
  end
  local bag = call(button, "GetBankTabID")
  local slot
  if I.readable(bag) then
    slot = call(button, "GetContainerSlotID")
  else
    bag, slot = call(button, "GetBagID"), call(button, "GetID")
  end
  if I.readable(bag) and I.readable(slot) then
    return bag, slot
  end
end

local function itemOf(kind, a, b, unit)
  local itemLocation = rawget(_G, "ItemLocation")
  local link, location, quality
  if kind == "inspect" then
    -- No item location exists for another player's gear: the link alone answers.
    link = I.inventoryLink(a, unit)
    quality = safe(rawget(_G, "GetInventoryItemQuality"), unit, a)
  elseif kind == "equip" then
    link = safe(rawget(_G, "GetInventoryItemLink"), "player", a)
    quality = safe(rawget(_G, "GetInventoryItemQuality"), "player", a)
    if type(itemLocation) == "table" then
      location = safe(itemLocation.CreateFromEquipmentSlot, itemLocation, a)
    end
  else
    local container = rawget(_G, "C_Container")
    link = type(container) == "table" and safe(container.GetContainerItemLink, a, b) or nil
    if type(itemLocation) == "table" then
      location = safe(itemLocation.CreateFromBagAndSlot, itemLocation, a, b)
    end
  end
  return link, location, quality
end

local function hide(button)
  local fs = button.fgIlvl
  if fs then
    fs:Hide()
  end
end

local function setFont(fs, fontSize)
  local font = rawget(_G, "STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF"
  local ok, set = pcall(fs.SetFont, fs, font, fontSize, "OUTLINE")
  if ok and set then
    return true
  end
  local object = rawget(_G, "GameFontNormalSmall")
  if object then
    fs:SetFontObject(object)
    return true
  end
  return false
end

-- Shared with ItemEnchantOverlay.
O.SetFont, O.InCombat = setFont, inCombat

local slotSerial = 0

-- The child frame of a slot button that carries everything we draw on the slot (item level, enchant
-- text, gems, hover area). It has a global name: skin add-ons fade the anonymous parts of a Blizzard
-- button and leave named frames of other add-ons alone. Made once per button, not while in combat.
function O.SlotFrame(button)
  local frame = button.fgSlot
  if frame then
    return frame
  end
  if type(button.CreateFontString) ~= "function" or inCombat() then
    return nil
  end
  local name = call(button, "GetName")
  if type(name) ~= "string" then
    slotSerial = slotSerial + 1
    name = "Slot" .. slotSerial
  end
  local ok, created = pcall(CreateFrame, "Frame", "ForeverGuidesSlotOverlay_" .. name, button)
  if not (ok and created) then
    return nil
  end
  created:SetAllPoints(button)
  button.fgSlot = created
  return created
end

-- What we draw on the slots of a window ("character" or "inspect"): level (item level number), text
-- (enchant text), extras (gems and the missing enchant marker), inset (extras sit inside the slot, because
-- the skin uses the side of the slot). Chosen by settings.slotOverlays; with auto only while another
-- add-on draws the slot information, see HostSkin.SheetOwner.
local policies = {}

local function makePolicy(level, text, extras, inset)
  local sig = (level and "L" or "l") .. (text and "T" or "t") .. (extras and "X" or "x") .. (inset and "I" or "i")
  return { level = level, text = text, extras = extras, inset = inset, sig = sig }
end

local function choose(surface)
  local mode = H.SlotMode()
  if mode == "none" then
    return makePolicy(false, false, false, false)
  end
  if mode == "auto" then
    local owner, draws = H.SheetOwner(surface)
    if owner then
      return makePolicy(not draws.level, not draws.text, true, draws.text)
    end
  end
  return makePolicy(true, true, true, false)
end

function O.Policy(surface)
  surface = surface == "inspect" and "inspect" or "character"
  local policy = policies[surface]
  if not policy then
    policy = choose(surface)
    policies[surface] = policy
  end
  return policy
end

-- Reads the setting and the skin again. When the answer changed after something was painted, FG_SLOT_POLICY
-- repaints every overlay. Returns true then.
function O.Reassess(surface)
  surface = surface == "inspect" and "inspect" or "character"
  local old = policies[surface]
  policies[surface] = choose(surface)
  if old and old.sig ~= policies[surface].sig then
    ns.Emit("FG_SLOT_POLICY", surface)
    return true
  end
  return false
end

local function reassessAll()
  for _, surface in ipairs(H.SHEETS) do
    O.Reassess(surface)
  end
end

-- Skins build their slot texts a moment after the window shows: look again at once and a bit later.
function O.WatchSheet(surface, window)
  return H.Watch(window, function()
    O.Reassess(surface)
  end)
end

-- The FontString of a button, created on first use. Not while in combat.
local function region(button, kind)
  if button.fgIlvl then
    return button.fgIlvl
  end
  if inCombat() then
    return nil
  end
  local parent = kind == "bag" and button or O.SlotFrame(button)
  if not parent then
    return nil
  end
  local ok, fs = pcall(parent.CreateFontString, parent, nil, "OVERLAY")
  if not (ok and fs) then
    return nil
  end
  fs:SetDrawLayer("OVERLAY", 7)
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 1)
  button.fgIlvl = fs
  return fs
end

local function paint(button, fs, text, r, g, b)
  local fontSize, where = size(), corner()
  if fs.fgSize ~= fontSize then
    fs.fgSize = fontSize
    fs.fgFont = setFont(fs, fontSize)
  end
  if not fs.fgFont then
    fs:Hide()
    return
  end
  if fs.fgCorner ~= where then
    fs.fgCorner = where
    local c = CORNERS[where]
    fs:ClearAllPoints()
    fs:SetPoint(where, button, where, c.x, c.y)
    fs:SetJustifyH(c.justify)
  end
  fs:SetTextColor(r, g, b)
  fs:SetText(text)
  fs:Show()
  O.stats.paints = O.stats.paints + 1
end

-- Evaluates one button. kind "equip": paper doll slot. kind "inspect": slot of the inspect window,
-- unit is the inspected unit (remembered for later refreshes). kind "bag": container or bank
-- button; quality is what the hooked Blizzard function passed (nil on a refresh from our side).
function O.Update(button, kind, quality, unit)
  if type(button) ~= "table" then
    return
  end
  if kind == "inspect" then
    unit = unit or units[button]
    if not unit then
      return
    end
    units[button] = unit
  end
  local a, b = placeOf(button, kind)
  if not a then
    return
  end
  known[button] = kind
  local enabled = O.Option("itemLevel") ~= false and O.Option(KIND_OPTION[kind]) ~= false
  if enabled and kind ~= "bag" then
    enabled = O.Policy(kind).level
  end
  if not enabled then
    if painted[button] ~= generation .. "|off" then
      painted[button] = generation .. "|off"
      hide(button)
    end
    return
  end
  local link, location, slotQuality = itemOf(kind, a, b, unit)
  if link == nil then
    if painted[button] ~= generation .. "|empty" then
      painted[button] = generation .. "|empty"
      hide(button)
    end
    return
  end
  if not I.readable(quality) then
    quality = I.readable(slotQuality) and slotQuality or I.quality(link)
  end
  local key = table.concat({ generation, tostring(link), tostring(quality) }, "|")
  if painted[button] == key then
    return
  end
  O.stats.work = O.stats.work + 1
  -- Equipped items are gear by definition, bag items must be armor or weapons.
  local wanted = quality ~= nil and quality >= minQuality() and (kind ~= "bag" or I.isGear(link))
  if not wanted then
    -- An uncached item has no quality yet: try again on the next update.
    painted[button] = quality ~= nil and key or nil
    hide(button)
    return
  end
  local level = I.itemLevel(location, link)
  if not level then
    painted[button] = nil
    hide(button)
    return
  end
  if not button.fgIlvl and inCombat() then
    pending[button] = kind
    return
  end
  local fs = region(button, kind)
  if not fs then
    return
  end
  paint(button, fs, I.format(level), I.qualityColor(quality))
  painted[button] = key
end

-- Evaluates the equipment slot frames by name, so the buttons are known and painted even when the
-- hooked Blizzard function has not run yet (the probe and the refresh events use this).
function O.Scan()
  for _, slot in ipairs(I.SLOTS) do
    local button = slot.overlay ~= false and rawget(_G, "Character" .. slot.name) or nil
    if type(button) == "table" then
      ns.Safe("itemlevel", O.Update, button, "equip")
    end
  end
end

-- Applies a changed setting to every button seen so far.
function O.Refresh()
  generation = generation + 1
  for button, kind in pairs(known) do
    ns.Safe("itemlevel", O.Update, button, kind)
  end
end

-- Finishes the buttons that needed a FontString during combat.
function O.Flush()
  local queue = {}
  for button, kind in pairs(pending) do
    queue[#queue + 1] = { button, kind }
  end
  for _, entry in ipairs(queue) do
    pending[entry[1]] = nil
    ns.Safe("itemlevel", O.Update, entry[1], entry[2])
  end
end

local HOOKS = {
  PaperDollItemSlotButton_Update = function(button)
    ns.Safe("itemlevel", O.Update, button, "equip")
  end,
  SetItemButtonQuality = function(button, quality)
    ns.Safe("itemlevel", O.Update, button, "bag", quality)
  end,
}
local hooked = {}
O.hooked = hooked

-- name -> true for every hook that is in place. Missing functions are retried at the next call.
function O.Install()
  for name, fn in pairs(HOOKS) do
    if not hooked[name] and type(hooksecurefunc) == "function" and type(rawget(_G, name)) == "function" then
      hooked[name] = pcall(hooksecurefunc, name, fn) or nil
    end
  end
  return hooked
end

function O.HookNames()
  local names = {}
  for name in pairs(HOOKS) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function O.Counts()
  local equip, bag = 0, 0
  for _, kind in pairs(known) do
    if kind == "equip" then
      equip = equip + 1
    elseif kind == "bag" then
      bag = bag + 1
    end
  end
  return equip, bag
end

-- Number of known buttons whose number is on screen right now.
function O.Shown()
  local n = 0
  for button in pairs(known) do
    local fs = button.fgIlvl
    if fs and call(fs, "IsShown") == true then
      n = n + 1
    end
  end
  return n
end

ns.On("PLAYER_LOGIN", O.Install)
ns.On("ADDON_LOADED", function()
  for name in pairs(HOOKS) do
    if not hooked[name] then
      O.Install()
      return
    end
  end
end)
ns.On("PLAYER_REGEN_ENABLED", O.Flush)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.itemLevel") then
    O.Refresh()
  elseif path == "settings.slotOverlays" then
    reassessAll()
  end
end)
ns.On("FG_SLOT_POLICY", function()
  O.Refresh()
end)
-- A skin switch or any restyle runs ns.RefreshUI: read the skin now and once more after it settled.
local settle
ns.On("FG_UI_REFRESHED", function()
  if settle then
    settle.Burst()
  else
    settle = H.Watch(nil, reassessAll)
  end
end)
