-- The control for the display choice of ores and herbs (ns.GatherFilter) and of the spots without an item
-- (ns.GatherObjects): one switch per profession and per category (chests, fishing schools) and a list of
-- every material of the gathering data, ores first, each group sorted by skill, then the kinds of each
-- category sorted by name, with a switch per entry and "All" and "None" per group. Used in the panel of the
-- world map and in the settings, later on the minimap. It takes the width of its parent and a list height
-- that the host sets, nothing is fixed.
-- Without the data add-on the list gives way to the package banner.
local _, ns = ...
local W, L, K = ns.W, ns.L, ns.PageKit
local F, G, Data, R = ns.GatherFilter, ns.GatheringLogic, ns.GatherDataAccess, ns.ProfessionRouteLogic
local GO = ns.GatherObjects

local UI = {}
ns.GatherFilterUI = UI

ns.AddLocale("enUS", {
  ["gather.filter.herbs"] = "Herbs",
  ["gather.filter.herbsTip"] = "Shows the spots of all herbs that are not switched off in the list.",
  ["gather.filter.mining"] = "Ores",
  ["gather.filter.miningTip"] = "Shows the spots of all ores that are not switched off in the list.",
  ["gather.filter.all"] = "All",
  ["gather.filter.allTip"] = "Switches on every material of this profession.",
  ["gather.filter.none"] = "None",
  ["gather.filter.noneTip"] = "Switches off every material of this profession.",
  ["gather.filter.skill"] = "Skill %d",
  ["gather.filter.hiddenSuffix"] = " (hidden)",
  ["gather.filter.itemTip"] = "Click: show or hide the spots of this material on the map.",
  ["gather.filter.groupTip"] = "Materials of this profession. All and None switch the whole group.",
  ["gather.filter.groupOffTip"] = "The spots of this profession are hidden. Switch it on with the check box above the list.",
  ["gather.filter.treasure"] = "Chests",
  ["gather.filter.treasureTip"] = "Shows the spots of chests, clams and other finds that are not switched off in the list.",
  ["gather.filter.school"] = "Fishing schools",
  ["gather.filter.schoolTip"] = "Shows the spots of fishing schools and wreckage on the map, the kinds that are not switched off in the list. Off hides every school on the map.",
  ["gather.filter.kindTip"] = "Click: show or hide the spots of this kind on the map.",
  ["gather.filter.catTip"] = "Kinds of this category. All and None switch the whole group.",
  ["gather.filter.catOffTip"] = "The spots of this category are hidden. Switch it on with the check box above the list.",
})
ns.AddLocale("deDE", {
  ["gather.filter.herbs"] = "Kräuter",
  ["gather.filter.herbsTip"] = "Zeigt die Fundorte aller Kräuter, die in der Liste nicht abgewählt sind.",
  ["gather.filter.mining"] = "Erze",
  ["gather.filter.miningTip"] = "Zeigt die Fundorte aller Erze, die in der Liste nicht abgewählt sind.",
  ["gather.filter.all"] = "Alle",
  ["gather.filter.allTip"] = "Schaltet jedes Material dieses Berufs ein.",
  ["gather.filter.none"] = "Keine",
  ["gather.filter.noneTip"] = "Schaltet jedes Material dieses Berufs aus.",
  ["gather.filter.skill"] = "Fertigkeit %d",
  ["gather.filter.hiddenSuffix"] = " (ausgeblendet)",
  ["gather.filter.itemTip"] = "Klick: Fundorte dieses Materials auf der Karte zeigen oder ausblenden.",
  ["gather.filter.groupTip"] = "Materialien dieses Berufs. Alle und Keine schalten die ganze Gruppe um.",
  ["gather.filter.groupOffTip"] = "Die Fundorte dieses Berufs sind ausgeblendet. Mit dem Schalter über der Liste einschalten.",
  ["gather.filter.treasure"] = "Truhen",
  ["gather.filter.treasureTip"] = "Zeigt die Fundorte von Truhen, Muscheln und weiteren Fundstücken, die in der Liste nicht abgewählt sind.",
  ["gather.filter.school"] = "Fischschwärme",
  ["gather.filter.schoolTip"] = "Zeigt die Fundorte von Fischschwärmen und Wrackteilen auf der Karte, die Arten, die in der Liste nicht abgewählt sind. Aus blendet alle Schwärme auf der Karte aus.",
  ["gather.filter.kindTip"] = "Klick: Fundorte dieser Art auf der Karte zeigen oder ausblenden.",
  ["gather.filter.catTip"] = "Arten dieser Kategorie. Alle und Keine schalten die ganze Gruppe um.",
  ["gather.filter.catOffTip"] = "Die Fundorte dieser Kategorie sind ausgeblendet. Mit dem Schalter über der Liste einschalten.",
})

local ROW_H = 26
local CHECK_H, GAP = 22, 6
local ICON, BOX = 18, 16
local SMALL_H = 20
UI.LIST_ROWS = 10
-- Height of the switches above the list: two rows of two (professions, then categories) with a 2 px gap.
UI.TOP = 2 * CHECK_H + 2

-- The entries of the list: a heading per profession, then its items by skill (only professions with items),
-- then a heading per category of the spots without an item, then its kinds by name.
function UI.Entries(data)
  local out = {}
  local items = G.Items(data, {})
  for _, prof in ipairs(G.PROFESSIONS) do
    local first = #out + 1
    for _, entry in ipairs(items) do
      if entry.prof == prof then
        out[#out + 1] = { kind = "item", entry = entry }
      end
    end
    if #out >= first then
      table.insert(out, first, { kind = "head", prof = prof })
    end
  end
  for _, entry in ipairs(GO.Entries(data)) do
    out[#out + 1] = entry
  end
  return out
end

-- Opts: leaveFocusRing (the control sits on a Blizzard frame: Tab of the main window must not reach it).
-- Returns the frame. Methods: Update() (reads the settings and the data again), SetListHeight(h) (the
-- height of the list, returns the height of the whole control), Height() (the height the control needs now).
function UI.Build(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent)
  local listH = K.scaledHeight(ROW_H) * UI.LIST_ROWS
  local leave = opts.leaveFocusRing and ns.BlizzardLinks and ns.BlizzardLinks.LeaveFocusRing

  local function plain(frame)
    if leave then
      leave(frame)
    end
    return frame
  end

  local function check(key, prof)
    local c = plain(W.Checkbox(f, {
      key = key,
      tooltip = key,
      tooltipText = key .. "Tip",
      get = function()
        return F.ProfessionOn(prof)
      end,
      set = function(on)
        F.SetProfession(prof, on)
      end,
    }))
    c.fgId = "gather-filter-" .. prof
    return c
  end
  local mining = check("gather.filter.mining", "mining")
  local herbs = check("gather.filter.herbs", "herbalism")
  local function checkCategory(cat)
    local key = "gather.filter." .. cat
    local c = plain(W.Checkbox(f, {
      key = key,
      tooltip = key,
      tooltipText = key .. "Tip",
      get = function()
        return GO.CategoryOn(cat)
      end,
      set = function(on)
        GO.SetCategory(cat, on)
      end,
    }))
    c.fgId = "gather-filter-" .. cat
    return c
  end
  local treasure = checkCategory("treasure")
  local schools = checkCategory("school")
  -- Two columns: ores and herbs on the first row, chests and fishing schools below.
  mining:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  mining:SetPoint("TOPRIGHT", f, "TOP", -2, 0)
  herbs:SetPoint("TOPLEFT", f, "TOP", 2, 0)
  herbs:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  treasure:SetPoint("TOPLEFT", mining, "BOTTOMLEFT", 0, -2)
  treasure:SetPoint("TOPRIGHT", mining, "BOTTOMRIGHT", 0, -2)
  schools:SetPoint("TOPLEFT", herbs, "BOTTOMLEFT", 0, -2)
  schools:SetPoint("TOPRIGHT", herbs, "BOTTOMRIGHT", 0, -2)

  -- Rows ---------------------------------------------------------------------------------------------

  local function createRow(rowParent)
    local row = CreateFrame("Button", nil, rowParent)
    row:SetClipsChildren(true)
    K.RowHover(row)
    -- An item row
    row.box = CreateFrame("Frame", nil, row)
    row.box:SetSize(BOX, BOX)
    row.box:SetPoint("LEFT", 4, 0)
    W.Fill(row.box, "surface2")
    row.boxOn = W.Fill(row.box, "action", 1)
    row.boxBorder = W.Border(row.box, "white", 0.4)
    row.check = W.CheckMark(row.box, 12, "text")
    row.check:SetPoint("CENTER")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.skill = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
    row.skill:SetPoint("RIGHT", -4, 0)
    row.name = W.Text(row, { role = "ui" })
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.skill, "LEFT", -6, 0)
    -- A heading row
    row.title = W.Text(row, { role = "ui", color = "accent2" })
    row.title:SetPoint("LEFT", 4, 0)
    row.none = plain(W.Button(row, {
      key = "gather.filter.none",
      variant = "ghost",
      width = 48,
      height = SMALL_H,
      tooltip = "gather.filter.none",
      tooltipText = "gather.filter.noneTip",
      onClick = function()
        if row.cat then
          GO.None(row.cat)
        else
          F.None(row.prof)
        end
      end,
    }))
    row.none:SetPoint("RIGHT", -2, 0)
    row.all = plain(W.Button(row, {
      key = "gather.filter.all",
      variant = "ghost",
      width = 48,
      height = SMALL_H,
      tooltip = "gather.filter.all",
      tooltipText = "gather.filter.allTip",
      onClick = function()
        if row.cat then
          GO.All(row.cat)
        else
          F.All(row.prof)
        end
      end,
    }))
    row.all:SetPoint("RIGHT", row.none, "LEFT", -2, 0)
    row.title:SetPoint("RIGHT", row.all, "LEFT", -6, 0)
    row:SetScript(
      "OnClick",
      ns.Wrap("gather-filter-item", function()
        if row.itemId then
          F.SetItem(row.itemId, not F.ItemOn(row.itemId))
        elseif row.kindId then
          GO.SetKind(row.kindId, not GO.KindOn(row.kindId))
        end
      end)
    )
    -- Long names are cut by the row width: the tooltip carries the whole name.
    row:HookScript("OnEnter", function(self)
      if self.tipTitle then
        ns.ShowTooltip(self, self.tipTitle, self.tipText)
      end
    end)
    row:HookScript("OnLeave", ns.HideTooltip)
    ns.Focus.register(row, function(self)
      self:Click()
    end)
    return plain(row)
  end

  local function paintBox(row, on)
    row.check:SetShown(on)
    row.boxOn:SetShown(on)
    row.boxBorder.set(on and "actionHi" or "white", on and 1 or 0.4)
  end

  local function bindRow(row, item)
    local isObject = item.kind == "object"
    local isItem = item.kind == "item" or isObject
    row.itemId = item.kind == "item" and item.entry.id or nil
    row.kindId = isObject and item.entry.id or nil
    row.prof, row.cat = item.prof, item.cat
    for _, part in ipairs({ row.box, row.icon, row.skill, row.name }) do
      part:SetShown(isItem)
    end
    for _, part in ipairs({ row.title, row.all, row.none }) do
      part:SetShown(not isItem)
    end
    -- A heading is no control: no click, no stop of the Tab ring.
    if isItem then
      row:Enable()
    else
      row:Disable()
    end
    if not isItem then
      local on, name, tipKey
      if item.cat then
        on, name, tipKey = GO.CategoryOn(item.cat), L["gather.filter." .. item.cat], "gather.filter.cat"
      else
        on, name, tipKey = F.ProfessionOn(item.prof), R.Name(item.prof), "gather.filter.group"
      end
      row.tipTitle = name
      row.tipText = L[tipKey .. (on and "Tip" or "OffTip")]
      if not on then
        name = name .. L["gather.filter.hiddenSuffix"]
      end
      row.title:SetText(name)
      row.paintHover()
      return
    end
    local e = item.entry
    if isObject then
      -- No skill column: the data lists no requirement for a kind.
      row.tipTitle = e.name
      row.tipText = L["gather.filter.kindTip"]
      row.icon:SetTexture(e.icon)
      row.name:SetText(e.name)
      W.SetColor(row.name, GO.CategoryOn(e.cat) and "text" or "textMuted")
      row.skill:SetText("")
      paintBox(row, GO.KindOn(e.id))
      row.paintHover()
      return
    end
    local on = F.ItemOn(e.id)
    row.tipTitle = e.name
    row.tipText = string.format(L["gather.filter.skill"], e.skill) .. "\n" .. L["gather.filter.itemTip"]
    row.icon:SetTexture(G.IconPath(e.id, e))
    row.name:SetText(e.name)
    W.SetColor(row.name, F.ProfessionOn(e.prof) and "text" or "textMuted")
    row.skill:SetText(string.format(L["gather.filter.skill"], e.skill))
    paintBox(row, on)
    row.paintHover()
  end

  local list = W.ScrollList(f, {
    rowHeight = K.scaledHeight(ROW_H),
    createRow = createRow,
    bindRow = bindRow,
  })

  local banner = ns.PackageUI.Banner(f, Data.ADDON, {
    onLoaded = function()
      f:Update()
    end,
    onResize = function()
      f:Layout()
    end,
  })

  banner:Update(false)

  -- The data add-on is loaded but holds nothing usable: a plain line instead of the banner.
  local empty = W.Text(f, { role = "ui", color = "warning", wrap = true })
  empty:Hide()

  -- Layout and refresh -------------------------------------------------------------------------------

  local top = UI.TOP
  local missing = false

  -- Places the list or the banner and sets the height of the control. Returns it.
  function f:Layout()
    local y = top + GAP
    list:ClearAllPoints()
    banner:ClearAllPoints()
    if missing then
      local width = math.max(1, f:GetWidth() or 0)
      local h
      if banner:IsShown() then
        banner:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        banner:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
        h = banner:Fit(width)
      else
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        empty:SetWidth(width)
        h = math.ceil(empty:GetStringHeight())
      end
      f:SetHeight(y + h)
      return y + h
    end
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    list:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
    list:SetHeight(listH)
    f:SetHeight(y + listH)
    return y + listH
  end

  function f:Update()
    mining.Refresh()
    herbs.Refresh()
    treasure.Refresh()
    schools.Refresh()
    local data, status = Data.Get()
    missing = data == nil
    list:SetShown(not missing)
    local bannerShown = banner:Update(missing and status == Data.STATUS.missing)
    empty:SetShown(missing and not bannerShown)
    if missing then
      empty:SetText(Data.Hint(status))
    end
    -- The height first: the list shows as many rows as it is high.
    local height = f:Layout()
    list:SetData(data and UI.Entries(data) or {})
    return height
  end

  function f:SetListHeight(h)
    listH = math.max(K.scaledHeight(ROW_H), h)
    local height = f:Layout()
    list.Refresh()
    return height
  end

  function f:Height()
    return f:GetHeight()
  end

  -- A host that lays its items out through fgGridLayout (the settings page) gets the default list height.
  function f:fgGridLayout()
    return f:Layout()
  end

  f.parts = { mining = mining, herbs = herbs, treasure = treasure, schools = schools, list = list, banner = banner }
  f:HookScript("OnShow", function()
    f:Update()
  end)
  ns.On("FG_GATHER_FILTER_CHANGED", function()
    if f:IsVisible() then
      f:Update()
    end
  end)
  ns.On("FG_PACKAGE_CHANGED", function(_, name)
    if name == Data.ADDON and f:IsVisible() then
      f:Update()
    end
  end)
  ns.On("FG_UI_REFRESHED", function()
    if f:IsVisible() then
      f:Update()
    end
  end)
  return f
end
