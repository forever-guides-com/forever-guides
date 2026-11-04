-- The control for the display choice of ores and herbs (ns.GatherFilter): one switch per profession and
-- a list of every material of the gathering data, ores first, each group sorted by skill, with a switch per
-- item and "All" and "None" per group. Used in the panel of the world map and in the settings, later on the
-- minimap. It takes the width of its parent and a list height that the host sets, nothing is fixed.
-- Without the data add-on the list gives way to the package banner.
local _, ns = ...
local W, L, K = ns.W, ns.L, ns.PageKit
local F, G, Data, R = ns.GatherFilter, ns.GatheringLogic, ns.GatherDataAccess, ns.ProfessionRouteLogic

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
})

local ROW_H = 26
local CHECK_H, GAP = 22, 6
local ICON, BOX = 18, 16
local SMALL_H = 20
UI.LIST_ROWS = 10

-- The entries of the list: a heading per profession, then its items by skill. Only professions with items.
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
  mining:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  mining:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  herbs:SetPoint("TOPLEFT", mining, "BOTTOMLEFT", 0, -2)
  herbs:SetPoint("TOPRIGHT", mining, "BOTTOMRIGHT", 0, -2)

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
      width = 40,
      height = SMALL_H,
      tooltip = "gather.filter.none",
      tooltipText = "gather.filter.noneTip",
      onClick = function()
        F.None(row.prof)
      end,
    }))
    row.none:SetPoint("RIGHT", -2, 0)
    row.all = plain(W.Button(row, {
      key = "gather.filter.all",
      variant = "ghost",
      width = 40,
      height = SMALL_H,
      tooltip = "gather.filter.all",
      tooltipText = "gather.filter.allTip",
      onClick = function()
        F.All(row.prof)
      end,
    }))
    row.all:SetPoint("RIGHT", row.none, "LEFT", -2, 0)
    row.title:SetPoint("RIGHT", row.all, "LEFT", -6, 0)
    row:SetScript(
      "OnClick",
      ns.Wrap("gather-filter-item", function()
        if row.itemId then
          F.SetItem(row.itemId, not F.ItemOn(row.itemId))
        end
      end)
    )
    ns.Focus.register(row, function(self)
      self:Click()
    end)
    return plain(row)
  end

  local function bindRow(row, item)
    local isItem = item.kind == "item"
    row.itemId, row.prof = isItem and item.entry.id or nil, item.prof
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
      local name = R.Name(item.prof)
      if not F.ProfessionOn(item.prof) then
        name = name .. " (" .. L["common.off"] .. ")"
      end
      row.title:SetText(name)
      row.paintHover()
      return
    end
    local e = item.entry
    local on = F.ItemOn(e.id)
    row.icon:SetTexture(G.IconPath(e.id, e))
    row.name:SetText(e.name)
    W.SetColor(row.name, F.ProfessionOn(e.prof) and "text" or "textMuted")
    row.skill:SetText(string.format(L["gather.filter.skill"], e.skill))
    row.check:SetShown(on)
    row.boxOn:SetShown(on)
    row.boxBorder.set(on and "actionHi" or "white", on and 1 or 0.4)
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

  local top = 2 * CHECK_H + 2
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

  f.parts = { mining = mining, herbs = herbs, list = list, banner = banner }
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
