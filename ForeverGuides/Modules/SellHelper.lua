-- Sell helper at the merchant: reads the bags, applies the rules of Modules/SellLogic.lua, shows an
-- icon button with the item count inside the merchant window and sells item by item after the preview
-- (Modules/SellPreview.lua) or, when switched on, right when the merchant opens.
-- Safety: every game call is wrapped in pcall, a failed read of the bags, worn items or equipment
-- sets sells nothing, and each step checks that the merchant is still open, that there is no combat
-- and that the slot still holds the item the preview showed.
local _, ns = ...
local Logic, I = ns.SellLogic, ns.ItemInfo

local Helper = {}
ns.SellHelper = Helper

ns.AddLocale("enUS", {
  ["sell.tip.title"] = "Sell junk",
  ["sell.tip.total"] = "Total",
  ["sell.tip.more"] = "and %d more",
  ["sell.tip.quick"] = "Click: sell now",
  ["sell.tip.select"] = "Click: open selection",
  ["sell.tip.ctrlQuick"] = "{key:sellSwap}: sell now",
  ["sell.tip.ctrlSelect"] = "{key:sellSwap}: open selection",
  ["sell.quick.confirm"] = "%d items, %d of them rare or better, for %s. Sell?",
  ["sell.tip.empty"] = "Nothing to sell",
  ["sell.done"] = "%d items sold for %s, buyback possible in the merchant window",
  ["sell.stopped"] = "Sale stopped (%s): %d of %d items sold for %s",
  ["sell.why.closed"] = "merchant closed",
  ["sell.why.combat"] = "combat",
  ["sell.why.rest"] = "items stayed",
  ["sell.warn12"] = "More than 12 items: buyback keeps only the last 12",
  ["sell.autoHold"] = "Auto sale paused: %d items, open the preview",
  ["sell.combat"] = "Not possible in combat",
})
ns.AddLocale("deDE", {
  ["sell.tip.title"] = "Plunder verkaufen",
  ["sell.tip.total"] = "Gesamt",
  ["sell.tip.more"] = "und %d weitere",
  ["sell.tip.quick"] = "Klick: schnell verkaufen",
  ["sell.tip.select"] = "Klick: Auswahl öffnen",
  ["sell.tip.ctrlQuick"] = "{key:sellSwap}: schnell verkaufen",
  ["sell.tip.ctrlSelect"] = "{key:sellSwap}: Auswahl öffnen",
  ["sell.quick.confirm"] = "%d Items, davon %d selten oder besser, für %s. Verkaufen?",
  ["sell.tip.empty"] = "Nichts zu verkaufen",
  ["sell.done"] = "%d Items für %s verkauft, Rückkauf im Händlerfenster möglich",
  ["sell.stopped"] = "Verkauf abgebrochen (%s): %d von %d Items für %s verkauft",
  ["sell.why.closed"] = "Händler geschlossen",
  ["sell.why.combat"] = "Kampf",
  ["sell.why.rest"] = "Items blieben liegen",
  ["sell.warn12"] = "Mehr als 12 Items: Rückkauf fasst nur die letzten 12",
  ["sell.autoHold"] = "Auto-Verkauf pausiert: %d Items, Vorschau öffnen",
  ["sell.combat"] = "Im Kampf nicht möglich",
})

local BAGS = { 0, 1, 2, 3, 4 }
local REAGENT_BAG = 5
local LAST_EQUIP_SLOT = 19
-- Seconds between two sales, until the server has answered, and until the merchant window is filled.
local DELAY = 0.15
local SETTLE = 0.8
local SHOW_DELAY = 0.3
-- Positions in the return values of GetItemInfo.
local INFO_NAME, INFO_QUALITY, INFO_EQUIP_LOC, INFO_ICON, INFO_PRICE, INFO_CLASS, INFO_REAGENT = 1, 3, 9, 10, 11, 12, 17

local state = { open = false, combat = false, gen = 0, autoDone = false }
Helper.state = state

local button

local function readable(v)
  return I.readable(v)
end

local function method(tableName, name)
  local t = rawget(_G, tableName)
  return type(t) == "table" and type(t[name]) == "function" and t[name] or nil
end

local function inCombat()
  local f = rawget(_G, "InCombatLockdown")
  return state.combat or (type(f) == "function" and f() == true)
end

local function after(delay, fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, ns.Wrap("sell-timer", fn))
  else
    ns.Wrap("sell-timer", fn)()
  end
end

local function chat(text)
  ns.Notify.chat(text)
end

-- Reading the game ----------------------------------------------------------------------------

-- Quality, level and the other facts of an item from the item cache, nil while it is not cached.
local function facts(link)
  local get = method("C_Item", "GetItemInfo") or rawget(_G, "GetItemInfo")
  if type(get) ~= "function" or link == nil then
    return nil
  end
  local out = { pcall(get, link) }
  if not out[1] or out[2] == nil then
    return nil
  end
  local function at(n)
    return out[n + 1]
  end
  return {
    name = type(at(INFO_NAME)) == "string" and at(INFO_NAME) or nil,
    quality = at(INFO_QUALITY),
    equipLoc = type(at(INFO_EQUIP_LOC)) == "string" and at(INFO_EQUIP_LOC) or nil,
    icon = at(INFO_ICON),
    price = at(INFO_PRICE),
    class = at(INFO_CLASS),
    reagent = at(INFO_REAGENT) == true,
  }
end

local function location(kind, a, b)
  local make = rawget(_G, "ItemLocation")
  local f = type(make) == "table" and make[kind]
  if type(f) ~= "function" then
    return nil
  end
  local ok, loc = pcall(f, make, a, b)
  return ok and loc or nil
end

local function bagIds()
  local list = { unpack(BAGS) }
  local enum = rawget(_G, "Enum")
  local index = type(enum) == "table" and type(enum.BagIndex) == "table" and enum.BagIndex.ReagentBag
  if index == REAGENT_BAG then
    list[#list + 1] = index
  end
  return list
end

local function levelWanted(quality, equipLoc, rules)
  return Logic.Limit(quality, rules) > 0 and Logic.SLOTS[equipLoc] ~= nil
end

-- The items of the bags, nil when anything cannot be read: a partial list could make the game's own
-- junk sale look safe.
local function scanBags(rules)
  local c = rawget(_G, "C_Container")
  if type(c) ~= "table" or type(c.GetContainerNumSlots) ~= "function" or type(c.GetContainerItemInfo) ~= "function" then
    return nil
  end
  local items = {}
  for _, bag in ipairs(bagIds()) do
    local ok, slots = pcall(c.GetContainerNumSlots, bag)
    if not (ok and readable(slots)) then
      return nil
    end
    for slot = 1, slots do
      local read, info = pcall(c.GetContainerItemInfo, bag, slot)
      if not read then
        return nil
      end
      if type(info) == "table" then
        local id = readable(info.itemID) and info.itemID or Logic.ItemId(info.hyperlink)
        if not id then
          return nil
        end
        local f = facts(info.hyperlink or id) or {}
        local quality = readable(info.quality) and info.quality or f.quality
        local item = {
          bag = bag,
          slot = slot,
          itemID = id,
          link = info.hyperlink,
          count = readable(info.stackCount) and info.stackCount or 1,
          quality = quality,
          price = readable(f.price) and f.price or nil,
          class = f.class,
          equipLoc = f.equipLoc,
          reagent = f.reagent,
          bound = type(info.isBound) == "boolean" and info.isBound or nil,
          locked = info.isLocked == true,
          noValue = info.hasNoValue == true,
          name = f.name,
          icon = f.icon or info.iconFileID,
        }
        if levelWanted(quality, f.equipLoc, rules) then
          item.level = (I.itemLevel(location("CreateFromBagAndSlot", bag, slot), info.hyperlink))
        end
        items[#items + 1] = item
      end
    end
  end
  return items
end

-- Item ids of worn items and their item levels per slot (0 = empty slot, nil = level unknown). nil
-- when the worn items cannot be read.
local function equipment()
  local worn, level = {}, {}
  local getId = rawget(_G, "GetInventoryItemID")
  if type(getId) ~= "function" then
    return worn, nil
  end
  for slot = 1, LAST_EQUIP_SLOT do
    local ok, id = pcall(getId, "player", slot)
    if not ok then
      return nil
    end
    if readable(id) and id > 0 then
      worn[id] = true
      level[slot] = (I.itemLevel(location("CreateFromEquipmentSlot", slot), I.inventoryLink(slot)))
    else
      level[slot] = 0
    end
  end
  return worn, level
end

-- Item ids of all equipment sets. {} without the API, nil when the API fails.
local function equipmentSets()
  local api = rawget(_G, "C_EquipmentSet")
  if type(api) ~= "table" then
    return {}
  end
  if type(api.GetEquipmentSetIDs) ~= "function" or type(api.GetItemIDs) ~= "function" then
    return nil
  end
  local ok, ids = pcall(api.GetEquipmentSetIDs)
  if not ok or type(ids) ~= "table" then
    return nil
  end
  local set = {}
  for _, setId in ipairs(ids) do
    local read, list = pcall(api.GetItemIDs, setId)
    if not read or type(list) ~= "table" then
      return nil
    end
    for _, itemId in pairs(list) do
      if readable(itemId) and itemId > 0 then
        set[itemId] = true
      end
    end
  end
  return set
end

-- What the rules select right now: the Logic.Evaluate result plus items and rules. nil when the
-- game cannot be read completely.
function Helper.Evaluate()
  local rules = Logic.Rules(ns.db and ns.db.settings)
  local items = scanBags(rules)
  local sets = equipmentSets()
  local worn, level = equipment()
  if not (items and sets and worn) then
    return nil
  end
  local result = Logic.Evaluate(items, rules, { setIds = sets, worn = worn, equippedLevel = level })
  result.items, result.rules = items, rules
  return result
end

-- Button --------------------------------------------------------------------------------------

-- Size, gap to the money bar and room needed left of it (the dark bar at the bottom of the window),
-- rows listed in the tooltip, and the buyback tab of MerchantFrame.selectedTab.
local BUTTON_SIZE, OFFSET_X, GAP = 32, 8, 6
local TIP_ROWS = 15
local BUYBACK_TAB = 2
-- From this quality on (rare) a quick sale asks first.
local RARE = 3
-- Icon of the own button (a coin, a bag when the client lacks it), ring width and the frame levels
-- above the window art, so the dark money bar cannot cover the button.
local ICON_DIR = "Interface\\Icons\\"
local SELL_ICON, SELL_ICON_FALLBACK = ICON_DIR .. "INV_Misc_Coin_01", ICON_DIR .. "INV_Misc_Bag_10"
local RING, LEVEL_BOOST = 2, 20
-- The game's own "sell all junk" button and the scripts a takeover replaces.
local BLIZZARD_BUTTON = "MerchantSellAllJunkButton"
local TAKEN_SCRIPTS = { "OnClick", "OnEnter", "OnLeave" }
-- The black bar at the bottom of the window: the first of these that exists.
local MONEY_BARS = { "MerchantMoneyBg", "MerchantMoneyInset", "MerchantMoneyFrame" }

local function number(v)
  return readable(v) and type(v) == "number" and v or nil
end

local function moneyBar()
  for _, name in ipairs(MONEY_BARS) do
    local f = rawget(_G, name)
    if type(f) == "table" and type(f.GetLeft) == "function" then
      return f
    end
  end
end

-- The bar at the bottom of the window has room when the money bar starts right of the button. A
-- missing money bar means a skin rebuilt the window: the button then sits above the window.
local function roomInside(frame, money)
  if not money or type(frame.GetLeft) ~= "function" then
    return false
  end
  local ok, moneyLeft, frameLeft = pcall(function()
    return money:GetLeft(), frame:GetLeft()
  end)
  if not ok or not (number(moneyLeft) and number(frameLeft)) then
    return ok
  end
  return moneyLeft - frameLeft >= OFFSET_X + BUTTON_SIZE + GAP
end

local function place(b, frame)
  b:ClearAllPoints()
  local money = moneyBar()
  if roomInside(frame, money) then
    b:SetPoint("RIGHT", money, "LEFT", -GAP, 0)
  else
    b:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -6, -2)
  end
end

local function itemLine(entry)
  local left = (entry.icon and ("|T" .. entry.icon .. ":14|t ") or "")
    .. (entry.count > 1 and (entry.count .. "x ") or "")
    .. (entry.name or ("#" .. entry.itemID))
  local r, g, b = I.qualityColor(entry.quality)
  return { left = left, right = Logic.Money(entry.price), color = { r, g, b }, rightColor = "text" }
end

-- Whether a plain click sells at once (setting "quick") or opens the selection ("select"); the swap key (settings) swaps it.
local function clickMode()
  local settings = ns.db and ns.db.settings
  return settings and settings.sellClickMode == "select" and "select" or "quick"
end

local function quickByClick()
  return (clickMode() == "quick") ~= ns.Keys.Matches("sellSwap")
end

-- Colored while the rules select something, desaturated and dimmed when not. Defensive: a skin or
-- another client may build the button differently.
local DIM_ALPHA = 0.5

local function tint(texture, active)
  if type(texture) ~= "table" then
    return
  end
  if type(texture.SetDesaturated) == "function" then
    pcall(texture.SetDesaturated, texture, not active)
  end
  if type(texture.SetAlpha) == "function" then
    pcall(texture.SetAlpha, texture, active and 1 or DIM_ALPHA)
  end
end

-- The textures that carry the picture of the game's button.
local function gameTextures(frame)
  local list = { rawget(frame, "Icon"), rawget(frame, "icon"), rawget(_G, BLIZZARD_BUTTON .. "Icon") }
  if type(frame.GetNormalTexture) == "function" then
    local ok, texture = pcall(frame.GetNormalTexture, frame)
    list[#list + 1] = ok and texture or nil
  end
  return list
end

local function tintGameButton(frame, active)
  for _, texture in pairs(gameTextures(frame)) do
    tint(texture, active)
  end
end

local function showTooltip(owner)
  local result = state.result
  if not result then
    return
  end
  if #result.list == 0 then
    local empty = { { text = ns.L["sell.tip.empty"], color = "textMuted" } }
    ns.ShowTooltip(owner, ns.L["sell.tip.title"], nil, { lines = empty })
    return
  end
  local lines = { { left = ns.L["sell.tip.total"], right = Logic.Money(result.total), color = "textSecondary" } }
  lines[#lines + 1] = { separator = true }
  for i = 1, math.min(#result.list, TIP_ROWS) do
    lines[#lines + 1] = itemLine(result.list[i])
  end
  if #result.list > TIP_ROWS then
    lines[#lines + 1] = { text = string.format(ns.L["sell.tip.more"], #result.list - TIP_ROWS), color = "textMuted" }
  end
  local muted = quickByClick() and { "sell.tip.quick", "sell.tip.ctrlSelect" }
    or { "sell.tip.select", "sell.tip.ctrlQuick" }
  for _, key in ipairs(muted) do
    lines[#lines + 1] = { text = ns.L[key], color = "textMuted" }
  end
  ns.ShowTooltip(owner, ns.L["sell.tip.title"], nil, { lines = lines })
end

local function onBuybackTab()
  local frame = rawget(_G, "MerchantFrame")
  return type(frame) == "table" and frame.selectedTab == BUYBACK_TAB
end

local paintButton
local hooked

-- The client redraws the merchant window on every page and tab change through MerchantFrame_Update.
local function hookWindow(frame)
  if hooked then
    return
  end
  hooked = true
  local repaint = ns.Wrap("sell-repaint", function()
    paintButton()
  end)
  local hook = rawget(_G, "hooksecurefunc")
  if type(hook) == "function" and type(rawget(_G, "MerchantFrame_Update")) == "function" then
    -- Runs after the game's own update, which sets the state of its button again.
    pcall(hook, "MerchantFrame_Update", repaint)
  end
  if type(frame.HookScript) == "function" then
    pcall(frame.HookScript, frame, "OnShow", repaint)
  end
end

local function ensureButton()
  if button then
    return button
  end
  local frame = rawget(_G, "MerchantFrame")
  if type(frame) ~= "table" then
    return nil
  end
  button = ns.W.Action(frame, {
    texture = ns.ResolveIcon(SELL_ICON, SELL_ICON_FALLBACK),
    size = BUTTON_SIZE,
    variant = "gold",
    tooltip = "sell.tip.title",
    wrap = "sell-button",
    onClick = function()
      Helper.Click()
    end,
  })
  button.fgId = "sell-button"
  -- A clear ring and a level above the window art keep the button visible in the dark bar.
  button.ring = ns.W.Border(button, "accent2", 1, RING)
  button:SetFrameLevel(frame:GetFrameLevel() + LEVEL_BOOST)
  -- The count sits on a small plate in the lower right corner of the icon.
  local plate = CreateFrame("Frame", nil, button)
  plate:SetFrameLevel(button:GetFrameLevel() + 2)
  plate:SetHeight(12)
  plate:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  local bg = plate:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  button.count = ns.W.Text(plate, { role = "micro", color = "text", justify = "CENTER" })
  button.count:SetPoint("CENTER")
  button.plate = plate
  ns.Bind(plate, function()
    bg:SetColorTexture(ns.Theme.color("surface", 0.9))
  end)
  -- Runs after the tooltip of the action itself: the title alone is replaced by the full list.
  button:HookScript("OnEnter", ns.Wrap("sell-tip", showTooltip))
  return button
end

-- Takeover of the game's own button ---------------------------------------------------------------

-- { frame, scripts = { name = original }, enabled = original state } while the takeover is active.
local taken

local function setEnabled(frame, on)
  local f = on and frame.Enable or frame.Disable
  if type(f) == "function" then
    pcall(f, frame)
  end
end

-- Hands the button back: the original scripts and the state it had.
local function release()
  if not taken then
    return
  end
  local t = taken
  taken = nil
  for _, name in ipairs(TAKEN_SCRIPTS) do
    pcall(t.frame.SetScript, t.frame, name, t.scripts[name])
  end
  if t.enabled ~= nil then
    setEnabled(t.frame, t.enabled)
  end
  tintGameButton(t.frame, t.enabled ~= false)
end

-- The game's button when it should be taken over: setting on and the frame can take scripts.
local function takeoverTarget()
  local settings = ns.db and ns.db.settings
  if settings and settings.sellBlizzButton == false then
    return nil
  end
  local f = rawget(_G, BLIZZARD_BUTTON)
  if type(f) == "table" and type(f.SetScript) == "function" and type(f.GetScript) == "function" then
    return f
  end
end

-- Our click, tooltip and state replace the game's, so its own sale never runs next to ours. Nothing
-- happens in combat: the button stays as it is until the fight is over.
local function takeOver(target, result)
  if inCombat() then
    return
  end
  if taken and taken.frame ~= target then
    release()
  end
  if not taken then
    local t = { frame = target, scripts = {} }
    for _, name in ipairs(TAKEN_SCRIPTS) do
      t.scripts[name] = target:GetScript(name)
    end
    if type(target.IsEnabled) == "function" then
      local ok, on = pcall(target.IsEnabled, target)
      if ok and type(on) == "boolean" then
        t.enabled = on
      end
    end
    taken = t
    target:SetScript(
      "OnClick",
      ns.Wrap("sell-takeover-click", function()
        Helper.Click()
      end)
    )
    target:SetScript("OnEnter", ns.Wrap("sell-tip", showTooltip))
    target:SetScript("OnLeave", ns.HideTooltip)
  end
  -- Always clickable (an empty selection does nothing); the colors tell whether there is something.
  setEnabled(target, true)
  tintGameButton(target, result ~= nil and #result.list > 0)
end

paintButton = function()
  local result = state.result
  local frame = rawget(_G, "MerchantFrame")
  if state.open and type(frame) == "table" then
    hookWindow(frame)
  end
  local target = state.open and takeoverTarget() or nil
  if target then
    -- The game's button does the work: our own stays away.
    if button then
      button:Hide()
    end
    takeOver(target, result)
    return
  end
  release()
  -- No result means unreadable bags: no button. An empty list keeps the button, only the count goes.
  if not result or not state.open or onBuybackTab() then
    if button then
      button:Hide()
    end
    return
  end
  local b = ensureButton()
  if b then
    place(b, frame)
    local n = #result.list
    b.plate:SetShown(n > 0)
    tint(b.icon, n > 0)
    if n > 0 then
      ns.W.SetText(b.count, nil, n > 99 and "99+" or tostring(n))
      b.plate:SetWidth(math.max(12, b.count:GetStringWidth() + 6))
    end
    b:Show()
  end
end

-- Reads the bags again and repaints the button.
function Helper.Refresh()
  state.result = state.open and Helper.Evaluate() or nil
  paintButton()
end

-- Selling -------------------------------------------------------------------------------------

local function containerApi()
  local c = rawget(_G, "C_Container")
  return type(c) == "table" and c or nil
end

local function stopReason()
  if not state.open then
    return "closed"
  end
  if inCombat() then
    return "combat"
  end
end

local function slotInfo(entry)
  local c = containerApi()
  local ok, info = pcall(c.GetContainerItemInfo, entry.bag, entry.slot)
  return ok and type(info) == "table" and info or nil
end

-- The slot still holds the stack the preview showed and nothing locks it.
local function intact(entry)
  local info = slotInfo(entry)
  return info ~= nil
    and info.itemID == entry.itemID
    and info.isLocked ~= true
    and (readable(info.stackCount) and info.stackCount or 1) == entry.count
end

local function gone(entry)
  local info = slotInfo(entry)
  return info == nil or info.itemID ~= entry.itemID
end

local function report(job)
  local sold, copper = 0, 0
  for _, entry in ipairs(job.sent) do
    if gone(entry) then
      sold, copper = sold + 1, copper + entry.price
    end
  end
  local total = #job.list
  if sold == total then
    chat(string.format(ns.L["sell.done"], sold, Logic.Money(copper, true)))
  else
    local why = ns.L["sell.why." .. (job.stopped or "rest")]
    chat(string.format(ns.L["sell.stopped"], why, sold, total, Logic.Money(copper, true)))
  end
  state.job = nil
  Helper.Refresh()
end

-- Waits for the server before counting what is gone.
local function settle(job)
  after(SETTLE, function()
    report(job)
  end)
end

local function step(job)
  if state.job ~= job then
    return
  end
  local why = stopReason()
  if why then
    job.stopped = why
    return settle(job)
  end
  job.i = job.i + 1
  local entry = job.list[job.i]
  if not entry then
    return settle(job)
  end
  if intact(entry) and pcall(containerApi().UseContainerItem, entry.bag, entry.slot) then
    job.sent[#job.sent + 1] = entry
  end
  if job.i >= #job.list then
    return settle(job)
  end
  after(DELAY, function()
    step(job)
  end)
end

-- Sells the entries of `chosen` that the rules still select. Returns true when a sale started, else
-- false and the reason.
function Helper.Sell(chosen)
  local c = containerApi()
  if not (c and type(c.UseContainerItem) == "function" and type(c.GetContainerItemInfo) == "function") then
    return false, "api"
  end
  if state.job then
    return false, "busy"
  end
  if not state.open then
    return false, "closed"
  end
  if inCombat() then
    chat(ns.L["sell.combat"])
    return false, "combat"
  end
  -- The bags may have changed since the preview: sell only what the rules still select.
  local fresh = Helper.Evaluate()
  if not fresh then
    return false, "scan"
  end
  local current = {}
  for _, entry in ipairs(fresh.list) do
    current[Logic.Key(entry)] = entry
  end
  local list = {}
  for _, entry in ipairs(chosen or {}) do
    local now = current[Logic.Key(entry)]
    if now and now.itemID == entry.itemID then
      list[#list + 1] = now
    end
  end
  if #list == 0 then
    return false, "empty"
  end
  if Logic.OverBuyback(list) then
    chat(ns.L["sell.warn12"])
  end
  local job = { list = list, sent = {}, i = 0 }
  state.job = job
  local native = method("C_MerchantFrame", "SellAllJunkItems")
  if native and Logic.NativeFits(fresh.items, list, fresh.rules) and pcall(native) then
    job.sent = list
    settle(job)
  else
    step(job)
  end
  return true
end

-- Asks first with the count, the rare ones among them and the proceeds, then sells.
local function confirmQuick(list, rare, total)
  local text = string.format(ns.L["sell.quick.confirm"], #list, rare, Logic.Money(total, true))
  ns.Dialogs.Confirm("sell.tip.title", "sell.confirmText", function()
    Helper.Sell(list)
  end)
  -- The dialog takes a text key only: the counted sentence goes in as a literal.
  local dialog = rawget(_G, "ForeverGuidesConfirmDialog")
  if dialog and dialog.text then
    ns.W.SetText(dialog.text, nil, text)
  end
end

-- Quick sale: sells what the rules select right now, without the selection window. Nothing in combat
-- or while a sale runs; rare items ask first (setting "Confirm rare items").
function Helper.QuickSell()
  if not state.open or state.job then
    return false
  end
  if inCombat() then
    chat(ns.L["sell.combat"])
    return false
  end
  local result = Helper.Evaluate()
  if not result or #result.list == 0 then
    return false
  end
  local rare = 0
  for _, entry in ipairs(result.list) do
    if (entry.quality or 0) >= RARE then
      rare = rare + 1
    end
  end
  local settings = ns.db and ns.db.settings
  if rare > 0 and not (settings and settings.sellConfirmRare == false) then
    confirmQuick(result.list, rare, result.total)
    return true
  end
  return Helper.Sell(result.list)
end

-- Click on the junk button (the game's or ours): quick sale or selection, by setting and swap key.
function Helper.Click()
  if quickByClick() then
    Helper.QuickSell()
  else
    ns.SellPreview.Open()
  end
end

-- Sells on opening the merchant, once, never more than the buyback holds.
function Helper.Auto()
  local result = state.result
  if state.autoDone or state.job or not (result and result.rules.auto) or #result.list == 0 then
    return
  end
  state.autoDone = true
  if Logic.OverBuyback(result.list) then
    chat(string.format(ns.L["sell.autoHold"], #result.list))
    return
  end
  Helper.Sell(result.list)
end

-- Events --------------------------------------------------------------------------------------

ns.On("MERCHANT_SHOW", function()
  state.open, state.autoDone = true, false
  state.gen = state.gen + 1
  local gen = state.gen
  Helper.Refresh()
  after(SHOW_DELAY, function()
    if state.open and state.gen == gen then
      Helper.Refresh()
      Helper.Auto()
    end
  end)
end)

ns.On("MERCHANT_CLOSED", function()
  state.open = false
  state.gen = state.gen + 1
  state.result = nil
  paintButton()
  if ns.SellPreview then
    ns.SellPreview.Close()
  end
end)

ns.On("BAG_UPDATE_DELAYED", function()
  if state.open and not state.job then
    ns.Debounce("sell-refresh", 0.3, Helper.Refresh)
  end
end)

-- The game redraws its button on merchant updates: ours follows right after.
ns.On("MERCHANT_UPDATE", function()
  if state.open then
    paintButton()
  end
end)

ns.On("PLAYER_REGEN_DISABLED", function()
  state.combat = true
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  state.combat = false
  if state.open then
    paintButton()
  end
end)

ns.On("FG_SETTING_CHANGED", function(_, path)
  if state.open and not state.job and type(path) == "string" and path:find("^settings%.sell") then
    Helper.Refresh()
  end
end)
