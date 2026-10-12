-- Inventory of the current character: bags and worn items always, the bank and the mailbox
-- while they are open. Stored per character in ns.db.inventory (account-wide SavedVariables,
-- never sent anywhere), counted by item id. Every game call goes through pcall and a missing
-- API leaves its area untouched. The tooltip side is Modules/InventoryTooltip.lua.
local _, ns = ...
local Logic = ns.InventoryLogic
local Roster = ns.CharRoster
local I = ns.ItemInfo

local Inv = {}
ns.Inventory = Inv

local DELAY = 2
local BAGS = { 0, 1, 2, 3, 4 }
-- Old bank layout, used only when Enum.BagIndex names no bank container: main bank slots and
-- the bank bags (numbered 5 to 11).
local LEGACY_BANK = { -1, 5, 6, 7, 8, 9, 10, 11 }
-- Worn items 1 to 19 and the four bag slots.
local LAST_EQUIP_SLOT = 23
local MAX_MAILS = 100
local MAX_ATTACHMENTS = 32

-- bags and bank wait for the next flush, a tooltip flushes first (see Fresh).
local state = { dirty = true, bankDirty = false, mailDirty = false, bankOpen = false, mailOpen = false }
Inv.state = state

-- Option(key): the stored setting, else the default (on unless the default says otherwise).
function Inv.Option(key)
  local settings = ns.db and ns.db.settings
  local value = settings and settings[key]
  if value == nil then
    value = ns.Store.defaults.settings[key]
  end
  return value
end

local function globalFn(name)
  local f = rawget(_G, name)
  return type(f) == "function" and f or nil
end

local function containerApi()
  local c = rawget(_G, "C_Container")
  if ns.can.container and type(c) == "table" then
    return c
  end
end

-- The reagent bag sits at index 5 in some clients and counts as a bag there, not as bank.
local function bagIds()
  local list = { unpack(BAGS) }
  local enum = rawget(_G, "Enum")
  local index = type(enum) == "table" and type(enum.BagIndex) == "table" and enum.BagIndex.ReagentBag
  if I.readable(index) and index >= 5 and index <= 11 then
    list[#list + 1] = index
  end
  return list, index
end

-- Bank containers by their Enum.BagIndex names (Bank, BankBag_n, CharacterBankTab_n,
-- AccountBankTab_n), split into character bank and account bank. The ids differ between
-- client versions, so none is hard-wired. Without such names the old layout is the fallback.
-- The unnumbered names Characterbanktab and Accountbanktab (-2, -3) select a tab group and
-- are no container of their own, so they are skipped.
local function bankIds()
  local enum = rawget(_G, "Enum")
  local index = type(enum) == "table" and type(enum.BagIndex) == "table" and enum.BagIndex or {}
  local character, account, seen = {}, {}, {}
  for name, id in pairs(index) do
    if type(name) == "string" and I.readable(id) and not seen[id] then
      local lower = name:lower()
      if lower:find("bank", 1, true) and not lower:find("banktab$") then
        seen[id] = true
        local list = lower:find("account", 1, true) and account or character
        list[#list + 1] = id
      end
    end
  end
  if #character == 0 and #account == 0 then
    local _, reagent = bagIds()
    for _, id in ipairs(LEGACY_BANK) do
      if id ~= reagent then
        character[#character + 1] = id
      end
    end
    return character, account, true
  end
  table.sort(character)
  table.sort(account)
  return character, account, false
end

-- False when the client says the account bank cannot be read right now.
local function accountBankReadable()
  local bank, enum = rawget(_G, "C_Bank"), rawget(_G, "Enum")
  local kind = type(enum) == "table" and type(enum.BankType) == "table" and enum.BankType.Account
  if type(bank) ~= "table" or type(bank.CanViewBank) ~= "function" or kind == nil then
    return true
  end
  local ok, can = pcall(bank.CanViewBank, kind)
  return not ok or can ~= false
end

-- Counts the stacks of the given containers. nil without the container API or when a call
-- fails: half a count would replace a good one. The second value is the number of slots seen.
local function scanContainers(ids)
  local c = containerApi()
  if not c then
    return nil
  end
  local tally, total = {}, 0
  for _, bag in ipairs(ids) do
    local ok, slots = pcall(c.GetContainerNumSlots, bag)
    if not ok then
      return nil
    end
    total = total + (I.readable(slots) and slots or 0)
    for slot = 1, I.readable(slots) and math.min(slots, 200) or 0 do
      local read, info = pcall(c.GetContainerItemInfo, bag, slot)
      if not read then
        return nil
      end
      if type(info) == "table" then
        local done = pcall(function()
          local id = I.readable(info.itemID) and info.itemID or Logic.ItemId(info.hyperlink)
          local count = I.readable(info.stackCount) and info.stackCount or 1
          Logic.Add(tally, id, count)
        end)
        if not done then
          return nil
        end
      end
    end
  end
  return tally, total
end

local function scanEquipment()
  local byId, byLink = globalFn("GetInventoryItemID"), globalFn("GetInventoryItemLink")
  if not (byId or byLink) then
    return nil
  end
  local tally = {}
  for slot = 1, LAST_EQUIP_SLOT do
    local ok, id = pcall(function()
      local value = byId and byId("player", slot)
      return I.readable(value) and value or Logic.ItemId(byLink and byLink("player", slot))
    end)
    if not ok then
      return nil
    end
    Logic.Add(tally, id, 1)
  end
  return tally
end

-- A mail function of the client: the global one, else the same name in C_Mail.
local function mailFn(name)
  local f = globalFn(name)
  if f then
    return f
  end
  local c = rawget(_G, "C_Mail")
  return type(c) == "table" and type(c[name]) == "function" and c[name] or nil
end

-- The attachments of the inbox list, nil without the mail API. GetInboxItem gives name, item
-- id, icon, count; a link from GetInboxItemLink decides the id when there is one.
local function scanMail()
  local numItems, getItem = mailFn("GetInboxNumItems"), mailFn("GetInboxItem")
  if not (numItems and getItem) then
    return nil
  end
  local getLink = mailFn("GetInboxItemLink")
  local tally = {}
  local okCount, mails = pcall(numItems)
  if not okCount then
    return nil
  end
  local attachments = rawget(_G, "ATTACHMENTS_MAX_RECEIVE")
  attachments = I.readable(attachments) and math.min(attachments, MAX_ATTACHMENTS) or 16
  for mail = 1, I.readable(mails) and math.min(mails, MAX_MAILS) or 0 do
    for slot = 1, attachments do
      local ok = pcall(function()
        local name, itemId, _, count = getItem(mail, slot)
        if name then
          local id = Logic.ItemId(getLink and getLink(mail, slot)) or itemId
          Logic.Add(tally, I.readable(id) and id or nil, I.readable(count) and count or 1)
        end
      end)
      if not ok then
        return nil
      end
    end
  end
  return tally
end

-- Writes the given areas ({ bags = tally, ... }) into the snapshot of `key` (default: the
-- current character). The account snapshot records which character captured it.
local function write(areas, key)
  key = key or Roster.CurrentKey()
  if not key or type(ns.db) ~= "table" then
    return false
  end
  if type(ns.db.inventory) ~= "table" then
    ns.db.inventory = {}
  end
  local snap = Logic.Clean(ns.db.inventory[key])
  if key == Logic.ACCOUNT_KEY then
    snap.by = Roster.CurrentKey()
  end
  local now = Roster.Now()
  for area, tally in pairs(areas) do
    Logic.SetArea(snap, area, tally, now)
  end
  ns.db.inventory[key] = snap
  return true
end

function Inv.Enabled()
  return Inv.Option("inventoryTooltip") ~= false
end

-- Bags and worn items. Returns true when something was written.
function Inv.CaptureBags()
  if not Inv.Enabled() then
    return false
  end
  state.dirty = false
  local areas = { bags = scanContainers((bagIds())), equip = scanEquipment() }
  return next(areas) ~= nil and write(areas)
end

-- Only while the bank is open: a closed bank reads as empty. A bank without any slot counts
-- as not readable and leaves the last visit alone. Returns true when something was written.
function Inv.CaptureBank()
  if not (Inv.Enabled() and Inv.Option("inventoryBank") ~= false and state.bankOpen) then
    return false
  end
  state.bankDirty = false
  local character, account = bankIds()
  local wrote = false
  local tally, slots = scanContainers(character)
  if tally and slots > 0 then
    wrote = write({ bank = tally })
  end
  if #account > 0 and accountBankReadable() then
    tally, slots = scanContainers(account)
    if tally and slots > 0 then
      wrote = write({ [Logic.ACCOUNT_AREA] = tally }, Logic.ACCOUNT_KEY) or wrote
    end
  end
  return wrote
end

function Inv.CaptureMail()
  if not (Inv.Enabled() and Inv.Option("inventoryMail") ~= false and state.mailOpen) then
    return false
  end
  state.mailDirty = false
  local tally = scanMail()
  return tally ~= nil and write({ mail = tally })
end

-- Captures what changed since the last time.
function Inv.Flush()
  if state.dirty then
    Inv.CaptureBags()
  end
  if state.bankDirty then
    Inv.CaptureBank()
  end
  if state.mailDirty then
    Inv.CaptureMail()
  end
end

-- Called before a tooltip reads the numbers: the current character is read live.
function Inv.Fresh()
  if state.dirty and Inv.Enabled() then
    Inv.CaptureBags()
  end
end

local function schedule()
  ns.Debounce("inventory", DELAY, Inv.Flush)
end

local function markBags()
  state.dirty = true
  state.bankDirty = state.bankOpen
  schedule()
end

-- The button "capture again": everything that can be read right now.
function Inv.Rescan()
  state.dirty = true
  Inv.CaptureBags()
  Inv.CaptureBank()
  Inv.CaptureMail()
end

-- Deletes the snapshots of all characters, then reads the current bags again.
function Inv.Clear()
  if type(ns.db) == "table" then
    ns.db.inventory = {}
  end
  state.dirty = true
  Inv.CaptureBags()
end

for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
  ns.On(event, markBags)
end

-- The old events and the interaction bridge below reach the same handlers. Capturing only on the
-- change from closed to open keeps a client that sends both from reading twice.
local function openBank()
  if state.bankOpen then
    return
  end
  state.bankOpen = true
  state.bankDirty = true
  Inv.CaptureBank()
end

local function closeBank()
  state.bankOpen, state.bankDirty = false, false
end

local function openMail()
  if state.mailOpen then
    return
  end
  state.mailOpen, state.mailDirty = true, true
  schedule()
end

local function closeMail()
  state.mailOpen, state.mailDirty = false, false
end

ns.On("BANKFRAME_OPENED", openBank)
ns.On("BANKFRAME_CLOSED", closeBank)
ns.On("MAIL_SHOW", openMail)
ns.On("MAIL_CLOSED", closeMail)
ns.On("MAIL_INBOX_UPDATE", function()
  if state.mailOpen then
    state.mailDirty = true
    schedule()
  end
end)

-- Some clients report bank and mailbox only through the interaction manager, with an
-- Enum.PlayerInteractionType value as argument. Ids are read by name, never hard-wired.
local function interactionId(name)
  local types = type(Enum) == "table" and Enum.PlayerInteractionType
  return type(types) == "table" and types[name] or nil
end

local function onInteraction(opening)
  return function(_, kind)
    if kind == nil then
      return
    end
    if kind == interactionId("Banker") then
      return (opening and openBank or closeBank)()
    end
    if kind == interactionId("MailInfo") then
      return (opening and openMail or closeMail)()
    end
  end
end

ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", onInteraction(true))
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", onInteraction(false))

-- Switching it on reads the bags at once.
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.inventoryTooltip" and Inv.Enabled() then
    markBags()
  end
end)
