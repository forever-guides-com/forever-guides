-- Parts of the list view of the instance overview (Modules/InstanceCards.lua owns them): one row per instance
-- (thumbnail, name with the NEW badge, level in the color of its difficulty, faction, zone, access, quests, map
-- button), the sortable column header and the collapsible section header. The texts and the column widths come
-- from Modules/InstanceListLogic.lua and Modules/InstanceBracketLogic.lua, the picture from InstanceArt.
local _, ns = ...
local W, L, Theme, R, K = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit
local IL, B = ns.InstanceListLogic, ns.InstanceBracketLogic

local LV = {}
ns.InstanceListView = LV

ns.AddLocale("enUS", {
  ["instances.list.type.dungeon"] = "Dungeon",
  ["instances.list.type.raid"] = "Raid",
})

ns.AddLocale("deDE", {
  ["instances.list.type.dungeon"] = "Dungeon",
  ["instances.list.type.raid"] = "Raid",
})

LV.THUMB_H = 40
LV.ROW_MIN = 48
LV.ROW_PAD = 6
LV.ACTION = 24
LV.SECTION_H = 30

local function ceil(n)
  return math.ceil(n)
end

-- Row ---------------------------------------------------------------------------------------------

-- The text size factor the fixed columns follow (the line height of the body font against its base size).
function LV.Scale()
  return math.max(1, Theme.fontScale() * Theme.roleScale("ui"))
end

function LV.NewRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.rim = W.Border(row, "accentDim", 1, 1)
  row.rule = row:CreateTexture(nil, "BORDER")
  row.rule:SetPoint("BOTTOMLEFT")
  row.rule:SetPoint("BOTTOMRIGHT")
  row.rule:SetHeight(1)
  local function paint()
    row.bg:SetColorTexture(Theme.fillColor(row.fgHover and "hover" or nil))
    row.rim.show(row.fgHover == true)
    row.rule:SetColorTexture(Theme.color("accentDim", 0.35))
  end
  -- The owner lights the row for the mouse and for its keyboard cursor.
  function row:SetHover(on)
    self.fgHover = on == true
    paint()
  end
  ns.Bind(row, paint)
  row.art = ns.InstanceArt.Create(row)
  row.name = W.Text(row, { role = "ui", color = "text" })
  row.sub = W.Text(row, { role = "small", color = "textMuted" })
  row.badge = W.Badge(row, "instances.list.new", "success")
  row.level = W.Text(row, { role = "ui", color = "text" })
  row.zone = W.Text(row, { role = "ui", color = "textSecondary" })
  row.access = W.Text(row, { role = "ui", color = "textSecondary" })
  row.quests = W.Text(row, { role = "ui", color = "textSecondary", justify = "RIGHT" })
  row.crest = {
    A = K.IconSlot(row, K.FactionIconSpec("A")),
    H = K.IconSlot(row, K.FactionIconSpec("H")),
  }
  row.map = W.Action(row, {
    icon = "map",
    size = LV.ACTION,
    boxed = true,
    tooltip = "instances.list.map",
    tooltipText = "instances.list.map.tip",
    onClick = function()
      if row.inst and row.owner then
        row.owner:Open(row.inst, "map")
      end
    end,
  })
  return row
end

-- Fills a row with an instance. quests: { status, count }, playerLevel: nil without a known level.
function LV.PaintRow(row, inst, owner, index, quests, playerLevel)
  row.owner, row.inst, row.index = owner, inst, index
  row.questText = IL.QuestText(quests.status, quests.count, L)
  row.art:SetInstance(inst)
  row.name:SetText(R.Names(inst.n) or "")
  local kind = inst.t == "raid" and "raid" or "dungeon"
  row.sub:SetText(L["instances.list.type." .. kind] .. " · " .. IL.PlayersText(inst, L))
  row.badge:SetShown(IL.IsNew(inst))
  row.level:SetText(IL.LevelText(inst, L))
  local difficulty = B.Difficulty(inst, playerLevel)
  W.SetColor(row.level, B.DifficultyColor(difficulty) or "text")
  row.difficulty = difficulty
  row.zone:SetText(IL.ZoneText(inst))
  local access, full = IL.AccessText(inst, L)
  row.access:SetText(access)
  row.accessFull = full
  row.quests:SetText(quests.status == "ok" and tostring(quests.count) or "-")
  local faction = ns.InstanceLevelLogic.Faction(inst)
  row.crest.A:SetShown(faction == "A")
  row.crest.H:SetShown(faction == "H")
  row.faction = faction
  -- Lines the tooltip adds below the common ones.
  local extra = {}
  local word = B.DifficultyText(difficulty, L)
  if word then
    extra[#extra + 1] = { text = word, color = B.DifficultyColor(difficulty) }
  end
  if full then
    extra[#extra + 1] = string.format(L["instances.list.tip.access"], full)
  end
  row.extraTip = extra
end

-- Height of the rows for the font in use: the two text lines and the padding, never below ROW_MIN.
function LV.RowHeight(row)
  local text = ceil(row.name:GetStringHeight()) + 2 + ceil(row.sub:GetStringHeight())
  return math.max(LV.ROW_MIN, text + 2 * LV.ROW_PAD)
end

local function cell(fs, col, row, height)
  fs:SetShown(col ~= nil)
  if not col then
    return
  end
  fs:ClearAllPoints()
  fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
  fs:SetWidth(col.w)
  fs:SetHeight(height)
end

-- Places the parts for the columns of IL.ListColumns and the row height.
function LV.LayoutRow(row, cols, height)
  local by = cols.by
  local lineH = ceil(row.name:GetStringHeight())
  local thumb = by.thumb
  row.art:SetShown(thumb ~= nil)
  if thumb then
    local h = math.min(LV.THUMB_H, height - 2 * LV.ROW_PAD)
    row.art:ClearAllPoints()
    row.art:SetPoint("LEFT", row, "LEFT", thumb.x, 0)
    row.art:Layout(thumb.w, h)
  end
  local name = by.name
  local badgeW = row.badge:IsShown() and (ceil(row.badge:GetWidth()) + 6) or 0
  local avail = math.max(1, name.w - badgeW)
  local subH = ceil(row.sub:GetStringHeight())
  local top = (height - (lineH + 2 + subH)) / 2
  row.name:ClearAllPoints()
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", name.x, -top)
  row.name:SetWidth(avail)
  row.name:SetHeight(lineH)
  row.sub:ClearAllPoints()
  row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
  row.sub:SetWidth(name.w)
  row.sub:SetHeight(subH)
  row.badge:ClearAllPoints()
  if badgeW > 0 then
    local used = math.min(ceil(row.name:GetStringWidth()), avail)
    row.badge:SetPoint("LEFT", row.name, "TOPLEFT", used + 6, -lineH / 2)
  end
  cell(row.level, by.level, row, lineH)
  cell(row.zone, by.zone, row, lineH)
  cell(row.access, by.access, row, lineH)
  cell(row.quests, by.quests, row, lineH)
  local faction = by.faction
  for side, icon in pairs(row.crest) do
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", row, "LEFT", faction and (faction.x + (faction.w - icon:GetWidth()) / 2) or 0, 0)
    icon:SetShown(faction ~= nil and row.faction == side)
  end
  row.map:SetShown(by.action ~= nil)
  if by.action then
    row.map:ClearAllPoints()
    row.map:SetPoint("LEFT", row, "LEFT", by.action.x + (by.action.w - LV.ACTION) / 2, 0)
  end
end

-- Column header --------------------------------------------------------------------------------------

local SORTABLE = { name = true, level = true, zone = true, quests = true }

-- onSort(id): the click on a sortable column. The header shows the column in use and its direction.
function LV.NewHeader(parent, onSort)
  local h = CreateFrame("Frame", nil, parent)
  h.buttons, h.labels = {}, {}
  for _, id in ipairs({ "name", "level", "zone", "quests", "access" }) do
    if SORTABLE[id] then
      local b = W.Action(h, {
        key = "instances.list.col." .. id,
        icon = "sort-up",
        variant = "ghost",
        height = 24,
        tooltip = "instances.list.col." .. id,
        tooltipText = "instances.list.col.tip",
        onClick = function()
          onSort(id)
        end,
      })
      h.buttons[id] = b
    else
      h.labels[id] = W.Text(h, { key = "instances.list.col." .. id, role = "ui", color = "textMuted" })
    end
  end
  return h
end

function LV.SetHeader(h, sort, desc)
  for id, b in pairs(h.buttons) do
    local on = id == sort
    b:SetSelected(on)
    b:SetIcon(on and desc and "sort-down" or "sort-up")
    if b.icon and b.icon.SetAlpha then
      b.icon:SetAlpha(on and 1 or 0.35)
    end
  end
end

-- Places the header over the columns; returns its height.
function LV.LayoutHeader(h, cols)
  local height = 26
  for id, b in pairs(h.buttons) do
    local col = cols.by[id]
    b:SetShown(col ~= nil)
    if col then
      b:SetWidth(math.min(col.w, b:Fit(col.w)))
      b:ClearAllPoints()
      b:SetPoint("LEFT", h, "LEFT", col.x, 0)
    end
  end
  for id, fs in pairs(h.labels) do
    local col = cols.by[id]
    fs:SetShown(col ~= nil)
    if col then
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", h, "LEFT", col.x + 8, 0)
      fs:SetWidth(col.w - 8)
      fs:SetHeight(ceil(fs:GetStringHeight()))
    end
  end
  h:SetHeight(height)
  return height
end

-- Section header ---------------------------------------------------------------------------------------

-- onToggle(section): collapse or expand. The title is a button (keyboard and screen reader reach it), the
-- count stands on the right.
function LV.NewSection(parent, onToggle)
  local f = CreateFrame("Frame", nil, parent)
  f.rule = f:CreateTexture(nil, "BACKGROUND")
  f.rule:SetPoint("BOTTOMLEFT")
  f.rule:SetPoint("BOTTOMRIGHT")
  f.rule:SetHeight(1)
  ns.Bind(f.rule, function(t)
    t:SetColorTexture(Theme.color("accentDim", 0.6))
  end)
  f.count = W.Text(f, { role = "ui", color = "textMuted", justify = "RIGHT" })
  f.toggle = W.Action(f, {
    text = " ",
    icon = "chevron-down",
    variant = "ghost",
    height = LV.SECTION_H - 2,
    manual = true,
    onClick = function()
      if f.section then
        onToggle(f.section)
      end
    end,
  })
  f.toggle:HookScript("OnEnter", function(self)
    if f.section then
      ns.ShowTooltip(self, L[f.section.closed and "instances.group.closed" or "instances.group.open"])
    end
  end)
  f.toggle:HookScript("OnLeave", ns.HideTooltip)
  return f
end

function LV.PaintSection(f, section)
  f.section = section
  local title = B.SectionTitle(section, L)
  local count = B.CountText(section, L)
  f.toggle.label:SetText(title)
  f.toggle:SetIcon(section.closed and "chevron-right" or "chevron-down")
  f.toggle.fgName = function()
    return title .. ", " .. count
  end
  f.count:SetText(count)
end

function LV.LayoutSection(f, width)
  local countW = ceil(f.count:GetStringWidth()) + 2
  f.count:ClearAllPoints()
  f.count:SetPoint("RIGHT", f, "RIGHT", -IL.ROW_PAD, 0)
  f.count:SetWidth(countW)
  f.count:SetHeight(ceil(f.count:GetStringHeight()))
  f.toggle:SetWidth(math.min(f.toggle:Fit(width), math.max(1, width - countW - 2 * IL.ROW_PAD)))
  f.toggle:ClearAllPoints()
  f.toggle:SetPoint("LEFT", f, "LEFT", 0, 1)
  local height = math.max(LV.SECTION_H, f.toggle:GetHeight() + 2)
  f:SetHeight(height)
  return height
end
