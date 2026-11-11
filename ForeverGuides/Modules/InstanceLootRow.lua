-- One loot row of an instance: icon with a frame in the quality color, name in the quality color, slot and type
-- under it, the drop chance on the right (with the mark "Preferred"). Used for boss loot, the loot a boss
-- does not own, recorded loot and quest rewards (Modules/InstanceBossView.lua). The quality is also in the
-- tooltip and in the spoken description, the color is never the only carrier.
local _, ns = ...
local W, L, Theme, IV = ns.W, ns.L, ns.Theme, ns.InstanceView

ns.AddLocale("enUS", {
  ["instances.loot.rate"] = "%s%%",
  ["instances.loot.rateNone"] = "-",
  ["instances.loot.rateUnknown"] = "Drop chance not known",
  ["instances.loot.rateImported"] = "Drop chance %s%% (imported)",
  ["instances.loot.preferred"] = "Preferred",
  ["instances.loot.chance"] = "Drop chance",
})

ns.AddLocale("deDE", {
  ["instances.loot.rate"] = "%s %%",
  ["instances.loot.rateNone"] = "-",
  ["instances.loot.rateUnknown"] = "Droprate unbekannt",
  ["instances.loot.rateImported"] = "Droprate %s %% (importiert)",
  ["instances.loot.preferred"] = "Bevorzugt",
  ["instances.loot.chance"] = "Droprate",
})

local LR = {}
ns.InstanceLootRow = LR

local ICON = 28
local EDGE = 1
local PAD = 4
local GAP = 8
local RATE_MIN = 24
local RATE_SHARE = 0.4
local ARMOR_CLASS, MISC_SUBCLASS = 4, 0

local function ceil(fs)
  return math.ceil(fs:GetStringHeight())
end

function LR.Percent(value)
  return value >= 10 and tostring(math.floor(value + 0.5)) or tostring(math.floor(value * 10 + 0.5) / 10)
end

-- "Plate · Waist" for gear, the item type for the rest. Empty when the client does not know the item yet.
function LR.Kind(id)
  local c = rawget(_G, "C_Item")
  local api = type(c) == "table" and c.GetItemInfoInstant or nil
  if not (api and id) then
    return nil
  end
  local ok, _, _, subType, equipLoc, _, classId, subclassId = pcall(api, id)
  if not ok then
    return nil
  end
  local bits = {}
  -- Rings, cloaks and trinkets are "armor, miscellaneous": the slot says it all.
  local misc = classId == ARMOR_CLASS and subclassId == MISC_SUBCLASS
  if type(subType) == "string" and subType ~= "" and not misc then
    bits[#bits + 1] = subType
  end
  local slot = type(equipLoc) == "string" and equipLoc ~= "" and rawget(_G, equipLoc) or nil
  if type(slot) == "string" and slot ~= "" then
    bits[#bits + 1] = slot
  end
  return #bits > 0 and table.concat(bits, " · ") or nil
end

-- rate: the number shown on the right and the tooltip line that says where it comes from.
local function rateOf(item)
  local own = item.captured
  local measured = own and ns.LootCapture.Rate(own.kills, own.drops)
  if measured then
    return measured, string.format(L["instances.items.rateOwn"], LR.Percent(measured), own.kills)
  end
  if item.rate then
    return item.rate, string.format(L["instances.loot.rateImported"], LR.Percent(item.rate))
  end
  return nil, L["instances.loot.rateUnknown"]
end

local function qualityEdge(quality)
  local hex = ns.ItemInfo.qualityHex(quality)
  if hex then
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
  end
  return Theme.rgb("textMuted")
end

-- parent: the frame the row sits in. register(frame, activate) hands the row to the keyboard order of the owner.
function LR.Create(parent, register)
  local row = CreateFrame("Frame", nil, parent)
  row:EnableMouse(true)
  row.edge = row:CreateTexture(nil, "BORDER")
  row.edge:SetSize(ICON + 2 * EDGE, ICON + 2 * EDGE)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.name = W.Text(row, { role = "ui", color = "text", wrap = true })
  row.meta = W.Text(row, { role = "micro", color = "textSecondary", wrap = true })
  row.rate = W.Text(row, { role = "ui", color = "text", justify = "RIGHT" })
  row.mark = W.Text(row, { role = "micro", color = "accent2", justify = "RIGHT" })
  local hover = row:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.06)
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  ns.Bind(row, function()
    row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
    if row.entry then
      row.edge:SetColorTexture(qualityEdge(row.quality))
    end
  end)

  local function show()
    if row.entry then
      W.Tooltip.Show(
        row,
        { link = row.entry.id and ("item:" .. row.entry.id) or nil, title = row.itemName, lines = row.tipLines }
      )
    end
  end
  row:SetScript("OnEnter", show)
  row:SetScript("OnLeave", ns.HideTooltip)
  row.fgOnFocus, row.fgOnBlur = show, ns.HideTooltip
  row.fgName = function()
    return row.label
  end
  row.fgDescription = function()
    return row.description
  end
  register(row, function() end)

  function row:fgLayout(width)
    local rightW = 0
    if self.rate:IsShown() then
      local rateW = math.ceil(self.rate:GetStringWidth())
      local markW = self.mark:IsShown() and math.ceil(self.mark:GetStringWidth()) or 0
      rightW = math.min(math.floor(width * RATE_SHARE), math.max(RATE_MIN, rateW, markW))
    end
    local textX = EDGE + ICON + EDGE + GAP
    local nameW = math.max(40, width - textX - (rightW > 0 and rightW + GAP or 0))
    self.edge:ClearAllPoints()
    self.edge:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -PAD)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", EDGE, -(PAD + EDGE))
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -PAD)
    self.name:SetWidth(nameW)
    local y = PAD + ceil(self.name)
    if self.meta:IsShown() then
      self.meta:ClearAllPoints()
      self.meta:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -(y + 2))
      self.meta:SetWidth(nameW)
      y = y + 2 + ceil(self.meta)
    end
    local side = 0
    if rightW > 0 then
      self.rate:ClearAllPoints()
      self.rate:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -PAD)
      self.rate:SetWidth(rightW)
      side = PAD + ceil(self.rate)
      if self.mark:IsShown() then
        self.mark:ClearAllPoints()
        self.mark:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -(side + 2))
        self.mark:SetWidth(rightW)
        side = side + 2 + ceil(self.mark)
      end
    end
    return math.max(ICON + 2 * EDGE + 2 * PAD, y + PAD, side + PAD)
  end
  return row
end

-- item: an entry of IL.Build (boss loot, recorded loot or a quest reward).
function LR.Paint(row, item)
  row.entry = item
  local name = IV.ItemName(item)
  row.itemName = name
  local label = name
  if item.count and item.count > 1 then
    label = item.count .. "x " .. name
  end
  local shown = ns.ItemInfo.ColorName(label, item.q or IV.ItemQuality(item.id))
  if item.choice then
    shown = shown .. "  " .. Theme.hexText("textMuted", "(" .. L["instances.quest.choice"] .. ")")
    label = label .. " (" .. L["instances.quest.choice"] .. ")"
  end
  if item.src == "captured" then
    shown = shown .. "  " .. Theme.hexText("textMuted", "(" .. L["instances.items.captured"] .. ")")
  end
  row.name:SetText(shown)
  row.label = label
  row.quality = item.q or IV.ItemQuality(item.id)
  row.icon:SetTexture(IV.ItemIcon(item.id))
  row.edge:SetColorTexture(qualityEdge(row.quality))

  local lines, spoken = {}, {}
  local word = row.quality and L["questpanel.quality." .. row.quality] or nil
  if word then
    lines[#lines + 1] = word
    spoken[#spoken + 1] = word
  end
  local meta
  if item.src == "quest" then
    meta = string.format(L["instances.items.from"], table.concat(item.quests or {}, ", "))
  else
    meta = LR.Kind(item.id)
  end
  row.meta:SetText(meta or "")
  row.meta:SetShown(meta ~= nil)
  if meta then
    spoken[#spoken + 1] = meta
  end
  local own = item.captured
  if item.src == "quest" then
    row.rate:Hide()
    row.mark:Hide()
  else
    local value, tip = rateOf(item)
    row.rate:SetText(
      value and string.format(L["instances.loot.rate"], LR.Percent(value)) or L["instances.loot.rateNone"]
    )
    row.rate:Show()
    lines[#lines + 1] = tip
    spoken[#spoken + 1] = tip
    row.mark:SetText(L["instances.loot.preferred"])
    row.mark:SetShown(item.preferred == true)
    if item.preferred then
      spoken[#spoken + 1] = L["instances.loot.preferred"]
    end
  end
  if own then
    lines[#lines + 1] = string.format(L["instances.items.capturedTip"], own.drops, own.kills)
  end
  row.tipLines = lines
  row.description = table.concat(spoken, ", ")
end
