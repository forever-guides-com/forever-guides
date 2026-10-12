-- Durability window, content: a summary (average, lowest part) and one row per worn part with the item
-- icon, slot name, a bar and the percent as text (the color is never the only signal). The same content
-- sits in the floating window (Modules/DurabilityWindow.lua) and on the sidebar page. Reads the game with
-- guarded calls, runs in combat and touches no protected frame. Updates come from a few game events,
-- bundled into one repaint per frame, no OnUpdate. The numbers are in Modules/DurabilityLogic.lua.
local _, ns = ...
local W, L, Theme, U = ns.W, ns.L, ns.Theme, ns.U
local DL, I = ns.DurabilityLogic, ns.ItemInfo

local DV = {}
ns.DurabilityView = DV

local ROW_H, ICON, NAME_W, PCT_W, BAR_H = 22, 18, 84, 46, 8
local SUMMARY_H = 40
-- WCAG 2.1 AA for text, also the bar against the window background.
DV.MIN_CONTRAST = 4.5
DV.ROW_H, DV.SUMMARY_H = ROW_H, SUMMARY_H
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

ns.AddLocale("enUS", {
  ["dur.slot.head"] = "Head",
  ["dur.slot.neck"] = "Neck",
  ["dur.slot.shoulder"] = "Shoulders",
  ["dur.slot.back"] = "Back",
  ["dur.slot.chest"] = "Chest",
  ["dur.slot.wrist"] = "Wrists",
  ["dur.slot.hands"] = "Hands",
  ["dur.slot.waist"] = "Waist",
  ["dur.slot.legs"] = "Legs",
  ["dur.slot.feet"] = "Feet",
  ["dur.slot.mainhand"] = "Main hand",
  ["dur.slot.offhand"] = "Off hand",
  ["dur.slot.ranged"] = "Ranged",
  ["dur.slot.finger1"] = "Ring 1",
  ["dur.slot.finger2"] = "Ring 2",
  ["dur.slot.trinket1"] = "Trinket 1",
  ["dur.slot.trinket2"] = "Trinket 2",
  ["dur.fmt.percent"] = "%d%%",
  ["dur.fmt.points"] = "%d / %d",
  ["dur.summary.avg"] = "Average: %s",
  ["dur.summary.worst"] = "Lowest: %s, %s",
  ["dur.summary.none"] = "No worn part has a durability.",
  ["dur.emptyShort"] = "empty",
  ["dur.tip.durability"] = "Durability",
  ["dur.tip.condition"] = "Condition",
  ["dur.tip.empty"] = "Nothing equipped.",
  ["dur.level.good"] = "Good",
  ["dur.level.warn"] = "Fair",
  ["dur.level.low"] = "Low",
  ["dur.level.critical"] = "Critical",
  ["dur.warn"] = "Durability below %s: %s",
})
ns.AddLocale("deDE", {
  ["dur.slot.head"] = "Kopf",
  ["dur.slot.neck"] = "Hals",
  ["dur.slot.shoulder"] = "Schultern",
  ["dur.slot.back"] = "Rücken",
  ["dur.slot.chest"] = "Brust",
  ["dur.slot.wrist"] = "Handgelenke",
  ["dur.slot.hands"] = "Hände",
  ["dur.slot.waist"] = "Taille",
  ["dur.slot.legs"] = "Beine",
  ["dur.slot.feet"] = "Füße",
  ["dur.slot.mainhand"] = "Haupthand",
  ["dur.slot.offhand"] = "Nebenhand",
  ["dur.slot.ranged"] = "Fernkampf",
  ["dur.slot.finger1"] = "Ring 1",
  ["dur.slot.finger2"] = "Ring 2",
  ["dur.slot.trinket1"] = "Schmuck 1",
  ["dur.slot.trinket2"] = "Schmuck 2",
  ["dur.fmt.percent"] = "%d %%",
  ["dur.fmt.points"] = "%d / %d",
  ["dur.summary.avg"] = "Durchschnitt: %s",
  ["dur.summary.worst"] = "Niedrigstes: %s, %s",
  ["dur.summary.none"] = "Kein angelegtes Teil hat eine Haltbarkeit.",
  ["dur.emptyShort"] = "leer",
  ["dur.tip.durability"] = "Haltbarkeit",
  ["dur.tip.condition"] = "Zustand",
  ["dur.tip.empty"] = "Nichts angelegt.",
  ["dur.level.good"] = "Gut",
  ["dur.level.warn"] = "Mittel",
  ["dur.level.low"] = "Niedrig",
  ["dur.level.critical"] = "Kritisch",
  ["dur.warn"] = "Haltbarkeit unter %s: %s",
})

local function settings()
  return (ns.db and ns.db.settings) or {}
end

-- Reading the game -------------------------------------------------------------------------------

local function call(name, ...)
  local f = rawget(_G, name)
  if type(f) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(f, ...)
  if ok then
    return a, b
  end
  return nil
end

local placeholders = {}

-- The empty-slot background of the character window.
local function placeholderOf(slot)
  if placeholders[slot.token] == nil then
    local _, texture = call("GetInventorySlotInfo", slot.token)
    placeholders[slot.token] = type(texture) == "string" and texture or false
  end
  return placeholders[slot.token] or nil
end

local function readSlot(slot)
  local cur, max = call("GetInventoryItemDurability", slot.id)
  if not (I.readable(cur) and I.readable(max)) then
    cur, max = nil, nil
  end
  local icon = call("GetInventoryItemTexture", "player", slot.id)
  local link = call("GetInventoryItemLink", "player", slot.id)
  return {
    cur = cur,
    max = max,
    icon = type(icon) == "string" and icon or (type(icon) == "number" and icon) or nil,
    link = type(link) == "string" and link or nil,
    placeholder = placeholderOf(slot),
    worn = icon ~= nil or link ~= nil,
  }
end

-- The current state: entries, summary and the three limits.
function DV.Collect()
  local s = settings()
  local yellow, orange, red = DL.Thresholds(s.durabilityYellow, s.durabilityOrange, s.durabilityRed)
  local entries = DL.Entries(readSlot)
  return {
    entries = entries,
    summary = DL.Summary(entries),
    yellow = yellow,
    orange = orange,
    red = red,
  }
end

-- Colors and texts -------------------------------------------------------------------------------

-- `base` as "#rrggbb", lifted (or, on a light background, darkened) until it reads on `bg`.
function DV.Readable(base, bg)
  local hex = Theme.readable(base, bg, DV.MIN_CONTRAST)
  if Theme.contrastRatio(hex, bg) < DV.MIN_CONTRAST then
    for step = 1, 20 do
      hex = Theme.mix(base, "#000000", step * 0.05)
      if Theme.contrastRatio(hex, bg) >= DV.MIN_CONTRAST then
        break
      end
    end
  end
  return hex
end

function DV.LevelColor(level, bg)
  return DV.Readable(DL.COLORS[level] or DL.COLORS.good, bg or Theme.colors.bg)
end

function DV.PercentText(pct)
  return string.format(L["dur.fmt.percent"], DL.Display(pct))
end

local function itemName(link)
  return type(link) == "string" and link:match("%[(.-)%]") or nil
end

-- Row tooltip: item name in its quality color, slot, "x / y (percent)" and the condition.
function DV.ShowTooltip(owner, e, data)
  local slotName = L["dur.slot." .. e.key]
  if e.empty then
    ns.ShowTooltip(owner, slotName, L["dur.tip.empty"])
    return
  end
  local name = itemName(e.link) or slotName
  -- Quality color from the shared item functions (lifted to 4.5:1 on the tooltip surfaces).
  local title = I.ColorName(name, I.quality(e.link))
  local level = DL.Level(e.pct, data.yellow, data.orange, data.red)
  local lr, lg, lb = U.hex(DV.LevelColor(level))
  ns.ShowTooltip(owner, title, nil, {
    lines = {
      { text = slotName, color = "textSecondary" },
      {
        left = L["dur.tip.durability"],
        right = string.format(L["dur.fmt.points"], e.cur, e.max) .. " (" .. DV.PercentText(e.pct) .. ")",
        color = "text",
      },
      { left = L["dur.tip.condition"], right = L["dur.level." .. level], color = "text", rightColor = { lr, lg, lb } },
    },
  })
end

-- The view ---------------------------------------------------------------------------------------

local View = {}
View.__index = View
local views = setmetatable({}, { __mode = "k" })

local function newRow(view)
  local row = CreateFrame("Frame", nil, view.frame)
  row:SetHeight(ROW_H)
  row:EnableMouse(true)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetPoint("LEFT", 0, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.name = W.Text(row, { role = "ui" })
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetWidth(NAME_W)
  row.pct = W.Text(row, { role = "ui", justify = "RIGHT" })
  row.pct:SetPoint("RIGHT", 0, 0)
  row.pct:SetWidth(PCT_W)
  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetHeight(BAR_H)
  row.bar:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
  row.bar:SetPoint("RIGHT", row.pct, "LEFT", -6, 0)
  row.bar:SetMinMaxValues(0, 100)
  row.bar:SetValue(0)
  row.track = row.bar:CreateTexture(nil, "BACKGROUND")
  row.track:SetAllPoints()
  row.track:SetColorTexture(0, 0, 0, 0.5)
  row.fill = row.bar:CreateTexture(nil, "ARTWORK")
  row.fill:SetColorTexture(1, 1, 1, 1)
  row.bar:SetStatusBarTexture(row.fill)
  row:SetScript("OnEnter", function(self)
    if self.entry then
      DV.ShowTooltip(self, self.entry, view.data)
    end
  end)
  row:SetScript("OnLeave", ns.HideTooltip)
  return row
end

-- Text color and, on a see-through window, the shadow that keeps it readable (light under dark text).
function View:Paint(fs, hex)
  local r, g, b = U.hex(hex)
  fs:SetTextColor(r, g, b)
  ns.WindowStyle.ApplyShadow(fs, self.shadow == true, r, g, b)
end

-- Height the content needs for the rows it shows now.
function View:Height()
  return SUMMARY_H + math.max(1, self.count) * ROW_H
end

function View:Update(data)
  data = data or DV.Collect()
  self.data = data
  local bg = self.bgOf()
  -- A window with a background of its own: names and "empty" read on it too.
  local textHex = self.adapt and DV.Readable(Theme.colors.text, bg) or nil
  local mutedHex = self.adapt and DV.Readable(Theme.colors.textMuted, bg) or nil
  local summary = data.summary
  if summary.count > 0 then
    local avgLevel = DL.Level(summary.average, data.yellow, data.orange, data.red)
    local worstLevel = DL.Level(summary.worst.pct, data.yellow, data.orange, data.red)
    self.avg:SetText(string.format(L["dur.summary.avg"], DV.PercentText(summary.average)))
    self:Paint(self.avg, DV.LevelColor(avgLevel, bg))
    self.worst:SetText(
      string.format(L["dur.summary.worst"], L["dur.slot." .. summary.worst.key], DV.PercentText(summary.worst.pct))
    )
    self:Paint(self.worst, DV.LevelColor(worstLevel, bg))
  else
    self.avg:SetText(L["dur.summary.none"])
    self:Paint(self.avg, DV.LevelColor("good", bg))
    self.worst:SetText("")
  end

  for i, e in ipairs(data.entries) do
    local row = self.rows[i]
    if not row then
      row = newRow(self)
      self.rows[i] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -(SUMMARY_H + (i - 1) * ROW_H))
    row:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, -(SUMMARY_H + (i - 1) * ROW_H))
    row.entry = e
    row.icon:SetTexture(e.icon or UNKNOWN_ICON)
    row.icon:SetDesaturated(e.empty == true)
    row.icon:SetAlpha(e.empty and 0.6 or 1)
    row.name:SetText(L["dur.slot." .. e.key])
    if textHex then
      self:Paint(row.name, textHex)
    else
      W.SetColor(row.name, "text")
    end
    if e.empty then
      row.pct:SetText(L["dur.emptyShort"])
      if mutedHex then
        self:Paint(row.pct, mutedHex)
      else
        W.SetColor(row.pct, "textMuted")
      end
      row.bar:Hide()
    else
      local level = DL.Level(e.pct, data.yellow, data.orange, data.red)
      local hex = DV.LevelColor(level, bg)
      row.pct:SetText(DV.PercentText(e.pct))
      self:Paint(row.pct, hex)
      row.bar:SetValue(e.pct)
      row.fill:SetColorTexture(U.hex(hex))
      row.bar:Show()
    end
    row:Show()
  end
  for i = #data.entries + 1, #self.rows do
    self.rows[i]:Hide()
    self.rows[i].entry = nil
  end
  self.count = #data.entries
  if self.onResize then
    self.onResize(self:Height())
  end
end

-- opts.bg: function() -> "#rrggbb", the background the text sits on (default: the theme background).
-- opts.adapt: also color the names to read on that background (a window with its own look).
-- opts.onResize(height): the content changed its height. view.shadow = true adds a text shadow.
function DV.build(parent, opts)
  opts = opts or {}
  local view = setmetatable({}, View)
  view.bgOf = opts.bg or function()
    return Theme.colors.bg
  end
  view.adapt, view.onResize = opts.adapt == true, opts.onResize
  view.rows, view.count = {}, 0
  view.frame = CreateFrame("Frame", nil, parent)
  view.avg = W.Text(view.frame, { role = "ui" })
  view.avg:SetPoint("TOPLEFT", 0, -2)
  view.avg:SetPoint("TOPRIGHT", 0, -2)
  view.worst = W.Text(view.frame, { role = "ui" })
  view.worst:SetPoint("TOPLEFT", 0, -20)
  view.worst:SetPoint("TOPRIGHT", 0, -20)
  views[view] = true
  view.frame:SetScript("OnShow", function()
    ns.Safe("durability-show", view.Update, view)
  end)
  return view
end

-- Events -----------------------------------------------------------------------------------------

local warned = {}

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- Chat line for parts that just fell below the warning limit (once per part and drop, not in combat).
function DV.CheckWarning(data)
  local s = settings()
  if s.durabilityWarn ~= true then
    warned = {}
    return
  end
  local limit = DL.CleanLimit(s.durabilityWarnPct, DL.DEFAULTS.warn)
  local hit = DL.Crossings(warned, data.entries, limit, inCombat())
  if #hit == 0 then
    return
  end
  local parts = {}
  for _, e in ipairs(hit) do
    parts[#parts + 1] = L["dur.slot." .. e.key] .. " " .. DV.PercentText(e.pct)
  end
  ns.Notify.chat(string.format(L["dur.warn"], DV.PercentText(limit), table.concat(parts, ", ")))
end

-- One repaint of every visible view, the warning check and a message for the window.
function DV.RefreshAll()
  local data = DV.Collect()
  for view in pairs(views) do
    if view.frame:IsVisible() then
      view:Update(data)
    end
  end
  DV.CheckWarning(data)
  ns.Emit("FG_DURABILITY_UPDATED", data)
end

-- Events in one frame count once.
function DV.Schedule()
  ns.Debounce("durability", 0, DV.RefreshAll)
end

-- None of these is reserved for the Blizzard UI (tests/test_restrictedevents.lua).
DV.EVENTS = {
  "UPDATE_INVENTORY_DURABILITY",
  "PLAYER_EQUIPMENT_CHANGED",
  "PLAYER_ENTERING_WORLD",
  "MERCHANT_SHOW",
  "MERCHANT_CLOSED",
  "PLAYER_REGEN_ENABLED",
}
for _, event in ipairs(DV.EVENTS) do
  ns.On(event, DV.Schedule)
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) == "string" and path:find("^settings%.durability") then
    DV.Schedule()
  end
end)

-- Colors set by hand are not part of the theme binding: paint again after a theme or language change.
ns.On("FG_UI_REFRESHED", function()
  for view in pairs(views) do
    if view.data and view.frame:IsVisible() then
      view:Update(view.data)
    end
  end
end)
