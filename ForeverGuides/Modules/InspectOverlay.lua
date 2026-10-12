-- Item level, enchants and gems on the slots of the inspect window (InspectFrame, load on demand
-- with Blizzard_InspectUI) plus a small summary at its bottom. The slots are painted by the same code
-- as the own character window (ItemLevelOverlay kind "inspect", ItemEnchantOverlay with a unit);
-- this module only finds the Inspect<Slot>Slot frames, knows the inspected unit and says when the
-- data is there. Only an OnShow/OnHide hook on InspectFrame and game events; the summary panel
-- (one short line above the weapon row of the paper doll page) is ours, nothing of Blizzard's is
-- written.
local _, ns = ...
local I = ns.ItemInfo
local O = ns.ItemLevelOverlay
local E = ns.ItemEnchantOverlay

local V = {}
ns.InspectOverlay = V

ns.AddLocale("enUS", {
  ["insp.loading"] = "Loading ...",
  ["insp.avg"] = "Item level %s",
  ["insp.enchants"] = "Ench. %d/%d",
  ["insp.gems"] = "Gems %d",
})
ns.AddLocale("deDE", {
  ["insp.loading"] = "Lädt ...",
  ["insp.avg"] = "Itemlevel %s",
  ["insp.enchants"] = "Verz. %d/%d",
  ["insp.gems"] = "Sockel %d",
})

local DELAY = 0.1 -- INSPECT_READY and item cache events come in bursts
local MIN_SIZE = 9
local LINE_GAP = "  " -- between the item level and the enchant part of the line
local PANEL_PAD, PANEL_GAP = 4, 8
local PANEL_ALPHA, PANEL_LEVEL = 0.55, 10
local MIN_WIDTH, MAX_WIDTH, DEFAULT_WIDTH, SLOT_SIZE = 80, 220, 338, 40
local GREEN = { 0.1, 1, 0.1 }
local RED = { 1, 0.25, 0.25 }
local MUTED = { 0.7, 0.7, 0.7 }
local AVERAGE_SLOTS = 16 -- Blizzard: 14 armor slots plus two weapon slots, a two-hander counts twice
local NOT_AVERAGED = { [4] = true, [18] = true, [19] = true } -- shirt, ranged, tabard
local MAIN_HAND, OFF_HAND = 16, 17

local readyGuid -- GUID the last INSPECT_READY was for, nil while nothing arrived
local header, hooked
V.stats = { refreshes = 0 }

local function frame()
  local f = rawget(_G, "InspectFrame")
  return type(f) == "table" and f or nil
end

-- Font size of the summary: the "micro" role of the addon's typography (the user's font scale
-- counts), never larger than the slot texts. The line height follows it.
local function headerSize()
  return math.min(E.SIZE_MAX, ns.Theme.fontSize("micro"))
end

local function isShown(f)
  return type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() == true
end

-- The unit the window shows (Blizzard keeps it in InspectFrame.unit), "target" when unknown.
function V.Unit()
  local f = frame()
  local unit = f and f.unit
  return type(unit) == "string" and unit ~= "" and unit or "target"
end

local function guidOf(unit)
  local f = rawget(_G, "UnitGUID")
  if type(f) ~= "function" then
    return nil
  end
  local ok, guid = pcall(f, unit)
  return ok and type(guid) == "string" and guid or nil
end

-- true once INSPECT_READY came for the unit that is shown now.
function V.Ready(unit)
  if readyGuid == nil then
    return false
  end
  local guid = guidOf(unit)
  return guid == nil or guid == readyGuid
end

-- Facts of the worn gear of a unit: average item level (the game's value when it has one, else
-- computed like Blizzard does), enchants done and possible, empty gem sockets. level is nil while
-- an item is not cached yet.
function V.Collect(unit)
  local flagged = I.flaggedSlots(O.Option("enchantSlots"))
  local sum, complete = 0, true
  local enchanted, possible, empty = 0, 0, 0
  local mainLink, offLink, mainLevel
  for _, slot in ipairs(I.SLOTS) do
    local id = slot.id
    local link = I.inventoryLink(id, unit)
    if link ~= nil then
      if id == MAIN_HAND then
        mainLink = link
      elseif id == OFF_HAND then
        offLink = link
      end
      if not NOT_AVERAGED[id] then
        local level = I.itemLevel(link)
        if level then
          sum = sum + level
          if id == MAIN_HAND then
            mainLevel = level
          end
        else
          complete = false
        end
      end
      if I.enchantable(id, link, flagged) == true then
        possible = possible + 1
        local info = I.enchantInfo(id, link, unit)
        if info and (info.id ~= nil or info.text ~= nil) then
          enchanted = enchanted + 1
        end
      end
      local sockets = I.numSockets(link)
      if sockets then
        empty = empty + math.max(0, sockets - #I.gems(id, link, unit))
      end
    end
  end
  if mainLink and not offLink and mainLevel and I.isTwoHand(mainLink) then
    sum = sum + mainLevel
  end
  local calculated = complete and sum > 0 and math.floor(sum / AVERAGE_SLOTS) or nil
  local api = V.gameAverage(unit)
  return {
    average = api or calculated,
    calculated = calculated,
    api = api,
    enchanted = enchanted,
    possible = possible,
    empty = empty,
  }
end

-- The game's own average for the inspected unit, nil when this client has no such function.
function V.gameAverage(unit)
  local api = rawget(_G, "C_PaperDollInfo")
  local f = type(api) == "table" and api.GetInspectItemLevel
  if type(f) ~= "function" then
    return nil
  end
  local ok, value = pcall(f, unit)
  if ok and I.readable(value) and value > 0 then
    return math.floor(value)
  end
end

local function option(on, inspect)
  return O.Option(on) ~= false and O.Option(inspect) ~= false
end

-- Lines of the summary as { text, color, short }, at most two, empty when both displays are
-- switched off. Color nil: the normal text color; short: the same text without the gems part.
function V.Lines(unit)
  local levelOn = option("itemLevel", "itemLevelInspect")
  local enchantOn = option("enchantOverlay", "enchantInspect")
  if not (levelOn or enchantOn) then
    return {}
  end
  if not V.Ready(unit) then
    return { { ns.L["insp.loading"], MUTED } }
  end
  local facts = V.Collect(unit)
  local lines = {}
  if levelOn then
    lines[#lines + 1] = { string.format(ns.L["insp.avg"], facts.average and I.format(facts.average) or "...") }
  end
  if enchantOn then
    local text = string.format(ns.L["insp.enchants"], facts.enchanted, facts.possible)
    local short = text
    if O.Option("enchantGems") ~= false then
      text = text .. "  " .. string.format(ns.L["insp.gems"], facts.empty)
    end
    local complete = facts.possible > 0 and facts.enchanted >= facts.possible
    lines[#lines + 1] = { text, complete and GREEN or (facts.possible > 0 and RED or MUTED), short }
  end
  return lines
end

local function colored(text, color)
  if not color then
    return text
  end
  return string.format(
    "|cff%02x%02x%02x%s|r",
    math.floor(color[1] * 255 + 0.5),
    math.floor(color[2] * 255 + 0.5),
    math.floor(color[3] * 255 + 0.5),
    text
  )
end

-- The one summary line as candidates, longest first: { text = with color codes, plain = without }.
-- A narrower panel takes the next one: without the gems part, then the item level alone.
function V.Summary(unit)
  local lines = V.Lines(unit)
  local out, seen = {}, {}
  if #lines == 0 then
    return out
  end
  local function add(count, useShort)
    local shown, plain = {}, {}
    for i = 1, count do
      local text = useShort and lines[i][3] or lines[i][1]
      shown[#shown + 1] = colored(text, lines[i][2])
      plain[#plain + 1] = text
    end
    local joined = table.concat(plain, LINE_GAP)
    if not seen[joined] then
      seen[joined] = true
      out[#out + 1] = { text = table.concat(shown, LINE_GAP), plain = joined }
    end
  end
  add(#lines, false)
  add(#lines, true)
  add(1, true)
  return out
end

local function measure(target, name)
  local f = type(target) == "table" and target[name]
  if type(f) ~= "function" then
    return nil
  end
  local ok, value = pcall(f, target)
  return ok and I.readable(value) and value or nil
end

-- The summary: a small dark panel with one FontString (one line). Created on first use, never while
-- in combat. It is a child of the paper doll page, so it is gone on the PvP and guild tabs.
local function region()
  if header then
    return header
  end
  local f = frame()
  local host = rawget(_G, "InspectPaperDollFrame")
  if type(host) ~= "table" or type(host.CreateFontString) ~= "function" then
    host = f
  end
  if not (host and f) or O.InCombat() then
    return nil
  end
  local ok, holder = pcall(CreateFrame, "Frame", nil, host)
  if not (ok and holder) then
    return nil
  end
  pcall(holder.SetFrameLevel, holder, host:GetFrameLevel() + PANEL_LEVEL)
  local bg = holder:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, PANEL_ALPHA)
  local rec = { host = host, holder = holder, lines = {} }
  local fs = holder:CreateFontString(nil, "OVERLAY")
  fs:SetDrawLayer("OVERLAY", 7)
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetJustifyH("CENTER")
  fs:SetWordWrap(false)
  rec.lines[1] = fs
  -- Hover only when the line had to be shortened; the model below keeps the mouse otherwise.
  holder:SetScript("OnEnter", function(self)
    if rec.tip then
      ns.ShowTooltip(self, rec.tip)
    end
  end)
  holder:SetScript("OnLeave", ns.HideTooltip)
  header = rec
  holder:Hide()
  return rec
end

-- Width of the panel: the room between the two slot columns, so it never reaches a slot.
local function panelWidth(rec)
  local head = measure(rawget(_G, "InspectHeadSlot"), "GetCenter")
  local hands = measure(rawget(_G, "InspectHandsSlot"), "GetCenter")
  local width
  if head and hands and hands ~= head then
    local slot = measure(rawget(_G, "InspectHeadSlot"), "GetWidth") or SLOT_SIZE
    width = math.abs(hands - head) - slot - 2 * PANEL_GAP
  else
    width = (measure(rec.host, "GetWidth") or DEFAULT_WIDTH) * 0.6
  end
  return math.floor(math.max(MIN_WIDTH, math.min(MAX_WIDTH, width)))
end

-- Under the weapon row when the footer of the page has room for it, else on the lower edge of the
-- model area above the weapon row and above the markers and gems of its slots (E.BOTTOM_RESERVE),
-- else on the lower edge of the page. The window is measured every time, so another window size
-- or scale needs no extra step.
local function place(rec, width)
  local height = headerSize() + 3 + 2 * PANEL_PAD
  local weapon = rawget(_G, "InspectMainHandSlot")
  local bottom = measure(rec.host, "GetBottom")
  local weaponBottom, weaponTop = measure(weapon, "GetBottom"), measure(weapon, "GetTop")
  local point, y = "BOTTOM", PANEL_GAP
  if bottom and weaponBottom and weaponBottom - bottom >= height + PANEL_GAP then
    point, y = "TOP", weaponBottom - bottom - PANEL_GAP
  elseif bottom and weaponTop then
    y = weaponTop - bottom + E.BOTTOM_RESERVE + PANEL_GAP
  end
  local key = table.concat({ point, y, width, height }, "|")
  if rec.key == key then
    return
  end
  rec.key = key
  rec.holder:ClearAllPoints()
  rec.holder:SetPoint(point, rec.host, "BOTTOM", 0, y)
  rec.holder:SetSize(width, height)
  local fs = rec.lines[1]
  fs:ClearAllPoints()
  fs:SetPoint("TOP", rec.holder, "TOP", 0, -PANEL_PAD)
  fs:SetWidth(width - 2 * PANEL_PAD)
end

-- Writes the first candidate that fits the width, taking the font down in steps before the next,
-- shorter candidate is tried. When none fits, the shortest is cut with "...". Whatever is not the
-- full text is in the hover tooltip of the panel.
local function setLine(rec, candidates, width)
  local fs, room = rec.lines[1], width - 2 * PANEL_PAD
  local top = headerSize()
  local function font(size)
    if fs.fgSize ~= size then
      fs.fgSize = size
      fs.fgFont = O.SetFont(fs, size)
    end
    return fs.fgFont
  end
  local r, g, b = ns.Theme.rgb("text")
  fs:SetTextColor(r, g, b)
  rec.tip = nil
  for index, candidate in ipairs(candidates) do
    for size = top, MIN_SIZE, -1 do
      local set = font(size)
      fs:SetText(candidate.text)
      if not set or fs:GetStringWidth() <= room then
        rec.tip = index > 1 and candidates[1].plain or nil
        fs:Show()
        return
      end
    end
  end
  local last = candidates[#candidates]
  font(MIN_SIZE)
  E.Fit(fs, last.plain, room)
  rec.tip = candidates[1].plain
  fs:Show()
end

function V.PaintHeader(unit)
  local candidates = V.Summary(unit)
  if #candidates == 0 then
    if header then
      header.holder:Hide()
    end
    return
  end
  local rec = region()
  if not rec then
    return
  end
  local width = panelWidth(rec)
  place(rec, width)
  setLine(rec, candidates, width)
  rec.holder:EnableMouse(rec.tip ~= nil)
  rec.holder:Show()
end

-- The panel parts ({ holder, lines }), nil until it was built. For the tests.
function V.Panel()
  return header
end

-- The summary line on screen now without color codes, nil when it is hidden. Test seam.
function V.HeaderText()
  if not (header and header.holder:IsShown()) then
    return nil
  end
  local out = {}
  for _, fs in ipairs(header.lines) do
    if fs:IsShown() and fs:GetText() ~= "" then
      out[#out + 1] = (fs:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

-- Paints every slot of the window and the summary.
function V.Refresh()
  if not isShown(frame()) then
    return
  end
  V.stats.refreshes = V.stats.refreshes + 1
  local unit = V.Unit()
  for _, slot in ipairs(I.SLOTS) do
    local button = slot.overlay ~= false and rawget(_G, "Inspect" .. slot.name) or nil
    if type(button) == "table" then
      ns.Safe("inspect", O.Update, button, "inspect", nil, unit)
      ns.Safe("inspect", E.Update, button, unit)
    end
  end
  ns.Safe("inspect", V.PaintHeader, unit)
  ns.Emit("FG_INSPECT_REFRESHED")
end

function V.Request()
  if isShown(frame()) then
    ns.Debounce("inspect-overlay", DELAY, V.Refresh)
  end
end

-- Hooks the window once it exists. Safe to call again and again.
function V.Install()
  local f = frame()
  if hooked or not f or type(f.HookScript) ~= "function" then
    return hooked == true
  end
  hooked = pcall(function()
    f:HookScript("OnShow", V.Request)
    f:HookScript("OnHide", function()
      readyGuid = nil
    end)
  end)
  if hooked then
    V.Request()
  end
  return hooked == true
end

-- Test seam.
function V.HookInstalled()
  return hooked == true
end

ns.On("PLAYER_LOGIN", V.Install)
ns.On("ADDON_LOADED", V.Install)
ns.On("INSPECT_READY", function(_, guid)
  readyGuid = type(guid) == "string" and guid or guidOf(V.Unit())
  V.Request()
end)
ns.On("INSPECT_TALENT_READY", V.Request) -- the talent row of the short view; clients without it never fire it
ns.On("GET_ITEM_INFO_RECEIVED", V.Request)
ns.On("PLAYER_REGEN_ENABLED", V.Request)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and (path:find("^settings%.itemLevel") or path:find("^settings%.enchant")) then
    V.Request()
  end
end)
