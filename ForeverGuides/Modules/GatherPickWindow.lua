-- One small filter window for a single area of the gathering data (ores, herbs, chests, fishing schools):
-- one check box per entry with icon and skill, "Select all", "Select none", a search field and, where the
-- area has a skill, "Only what I can gather". The window keeps no selection of its own. The caller hands a
-- spec and owns the state, so the world map panel (ns.GatherFilterUI, the display filter) and the page
-- "Ores and herbs" (the picked items) use the same window over different state.
--
--   ns.GatherPick.Open(spec)
--   spec.title        locale key of the window title
--   spec.entries()    -> list of { id, name, icon, sub (skill text), tip (optional line), skill, prof } of the whole area
--   spec.isOn(id)     -> bool
--   spec.setMany(ids, on)   applies the change to all ids at once
--   spec.canGather(entry) -> bool, optional: when set the window offers "Only what I can gather"
--   spec.dim()        -> true when the area is off elsewhere (names are muted), optional
--   spec.hint         locale key of a note line under the controls, optional
local _, ns = ...
local W, L, K = ns.W, ns.L, ns.PageKit
local G = ns.GatheringLogic

local P = {}
ns.GatherPick = P

ns.AddLocale("enUS", {
  ["gather.win.searchPh"] = "Search by name",
  ["gather.win.mine"] = "Only what I can gather",
  ["gather.win.mineTip"] = "Hides entries above your skill. A profession you do not have hides all its entries.",
  ["gather.win.all"] = "Select all",
  ["gather.win.allTip"] = "Selects every entry shown in the list. A search narrows the list first.",
  ["gather.win.none"] = "Select none",
  ["gather.win.noneTip"] = "Clears every entry shown in the list. A search narrows the list first.",
  ["gather.win.count"] = "%d of %d selected",
  ["gather.win.btn"] = "%d of %d",
  ["gather.win.openTip"] = "Opens a small window with one check box per entry of this area.",
  ["gather.win.itemTip"] = "Click: select or clear this entry.",
  ["gather.win.empty"] = "No entries for this search.",
  ["gather.win.dimTip"] = "This area is switched off. Its entries show nothing until you switch it on.",
  ["gather.win.t.mining"] = "Choose ores",
  ["gather.win.t.herbalism"] = "Choose herbs",
  ["gather.win.t.treasure"] = "Choose chests",
  ["gather.win.t.school"] = "Choose fishing schools",
  ["gather.win.lock"] = "Lockpicking %d",
})
ns.AddLocale("deDE", {
  ["gather.win.searchPh"] = "Nach Namen suchen",
  ["gather.win.mine"] = "Nur was ich sammeln kann",
  ["gather.win.mineTip"] = "Blendet Einträge über deiner Fertigkeit aus. Ein Beruf, den du nicht hast, blendet alle seine Einträge aus.",
  ["gather.win.all"] = "Alle auswählen",
  ["gather.win.allTip"] = "Wählt jeden Eintrag der Liste. Eine Suche schränkt die Liste vorher ein.",
  ["gather.win.none"] = "Alle abwählen",
  ["gather.win.noneTip"] = "Wählt jeden Eintrag der Liste ab. Eine Suche schränkt die Liste vorher ein.",
  ["gather.win.count"] = "%d von %d gewählt",
  ["gather.win.btn"] = "%d von %d",
  ["gather.win.openTip"] = "Öffnet ein kleines Fenster mit einem Haken pro Eintrag dieses Bereichs.",
  ["gather.win.itemTip"] = "Klick: Eintrag wählen oder abwählen.",
  ["gather.win.empty"] = "Keine Einträge für diese Suche.",
  ["gather.win.dimTip"] = "Dieser Bereich ist ausgeschaltet. Seine Einträge zeigen nichts, bis du ihn einschaltest.",
  ["gather.win.t.mining"] = "Erze auswählen",
  ["gather.win.t.herbalism"] = "Kräuter auswählen",
  ["gather.win.t.treasure"] = "Truhen auswählen",
  ["gather.win.t.school"] = "Fischschwärme auswählen",
  ["gather.win.lock"] = "Schlossknacken %d",
})

local WIDTH, HEIGHT = 380, 500
local SIDE, TITLE_H, GAP = 16, 48, 8
local ROW_H, ICON, BOX = 26, 18, 16
local BUTTON_H = 24
local HINT_H = 30 -- two lines of the micro role
local MIN_TARGET = 18

-- Pure side ---------------------------------------------------------------------------------------------

-- The own skill per profession of the data ({ mining = n, herbalism = n }), only the professions the
-- character has.
function P.OwnSkills()
  local skills = {}
  local shop = ns.ProfessionShop
  for _, p in ipairs(shop and shop.Own() or {}) do
    for _, prof in ipairs(G.PROFESSIONS) do
      if p.slug == prof then
        skills[prof] = p.skill
      end
    end
  end
  return skills
end

-- The entries that match the search text and, with canGather, only those the player can gather.
function P.Visible(entries, query, canGather)
  local out = {}
  query = type(query) == "string" and query or ""
  for _, e in ipairs(entries) do
    if (query == "" or ns.SearchLogic.match(e.name or "", query)) and (canGather == nil or canGather(e)) then
      out[#out + 1] = e
    end
  end
  return out
end

-- Number of entries that are on and the number of all entries.
function P.Count(entries, isOn)
  local on = 0
  for _, e in ipairs(entries) do
    if isOn(e.id) then
      on = on + 1
    end
  end
  return on, #entries
end

-- Text of the button that opens the window for an area, "2 of 39".
function P.ButtonText(entries, isOn)
  return string.format(L["gather.win.btn"], P.Count(entries, isOn))
end

-- The gate "Only what I can gather" for entries of professions (nil when the player has none of them).
function P.SkillGate()
  local skills = P.OwnSkills()
  return function(e)
    local own = tonumber(skills[e.prof])
    return own ~= nil and (tonumber(e.skill) or 0) <= own
  end
end

-- Window ------------------------------------------------------------------------------------------------

local win

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetClipsChildren(true)
  K.RowHover(row)
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
  row.sub = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
  row.sub:SetPoint("RIGHT", -4, 0)
  row.name = W.Text(row, { role = "ui" })
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row.sub, "LEFT", -6, 0)
  row:SetScript(
    "OnClick",
    ns.Wrap("gather-pick-item", function()
      if row.entry then
        win.Apply({ row.entry.id }, not win.spec.isOn(row.entry.id))
      end
    end)
  )
  -- Long names are cut by the row width: the tooltip carries the whole name.
  row:HookScript("OnEnter", function(self)
    if self.entry then
      local text = (self.entry.sub or "")
      if self.entry.tip then
        text = text .. "\n" .. self.entry.tip
      end
      text = text .. "\n" .. L["gather.win.itemTip"]
      if win.spec.dim and win.spec.dim() then
        text = text .. "\n" .. L["gather.win.dimTip"]
      end
      ns.ShowTooltip(self, self.entry.name, text)
    end
  end)
  row:HookScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(row, function(self)
    self:Click()
  end)
  return row
end

local function bindRow(row, entry)
  local spec = win.spec
  local on = spec.isOn(entry.id)
  row.entry = entry
  row.icon:SetTexture(entry.icon)
  row.name:SetText(entry.name)
  W.SetColor(row.name, (spec.dim and spec.dim()) and "textMuted" or "text")
  row.sub:SetText(entry.sub or "")
  row.check:SetShown(on)
  row.boxOn:SetShown(on)
  row.boxBorder.set(on and "actionHi" or "white", on and 1 or 0.4)
  row.paintHover()
end

local function build()
  local f = ns.Dialogs.Create("ForeverGuidesGatherPickWindow", WIDTH, HEIGHT)
  win = { frame = f }

  win.query, win.mine = "", false
  win.search = W.EditBox(f, {
    placeholder = "gather.win.searchPh",
    clear = true,
    onChange = function(text)
      win.query = text
      win.Refresh()
    end,
  })
  win.search:SetPoint("TOPLEFT", SIDE, -TITLE_H)
  win.search:SetPoint("TOPRIGHT", -SIDE, -TITLE_H)

  win.mineBox = W.Checkbox(f, {
    key = "gather.win.mine",
    tooltip = "gather.win.mine",
    tooltipText = "gather.win.mineTip",
    get = function()
      return win.mine
    end,
    set = function(on)
      win.mine = on
      win.Refresh()
    end,
  })

  win.all = W.Button(f, {
    key = "gather.win.all",
    width = 140,
    height = BUTTON_H,
    tooltip = "gather.win.all",
    tooltipText = "gather.win.allTip",
    onClick = function()
      win.Apply(win.ids(), true)
    end,
  })
  win.none = W.Button(f, {
    key = "gather.win.none",
    width = 140,
    height = BUTTON_H,
    tooltip = "gather.win.none",
    tooltipText = "gather.win.noneTip",
    onClick = function()
      win.Apply(win.ids(), false)
    end,
  })
  win.count = W.Text(f, { role = "micro", color = "textMuted" })
  win.hint = W.Text(f, { role = "micro", color = "textMuted", wrap = true })

  local host = CreateFrame("Frame", nil, f)
  W.Fill(host, "surface", 1)
  win.list = W.ScrollList(host, { rowHeight = K.scaledHeight(ROW_H), createRow = createRow, bindRow = bindRow })
  win.list:SetAllPoints(host)
  win.empty = W.Text(host, { key = "gather.win.empty", role = "ui", color = "textMuted", wrap = true })
  win.empty:SetPoint("TOPLEFT", 8, -8)
  win.empty:SetPoint("TOPRIGHT", -8, -8)

  local done = W.Action(f, {
    label = "act.close",
    icon = "close",
    tooltip = "common.close",
    variant = "primary",
    width = 110,
    onClick = function()
      f:Hide()
    end,
  })
  done:SetPoint("BOTTOMRIGHT", -SIDE, 14)
  win.count:SetPoint("BOTTOMLEFT", SIDE, 20)
  win.count:SetPoint("RIGHT", done, "LEFT", -GAP, 0)
  win.host = host

  -- The rows under the controls: the check box only exists where the area has a skill.
  function win.Layout()
    local y = TITLE_H + 26 + GAP
    win.mineBox:ClearAllPoints()
    if win.spec.canGather then
      win.mineBox:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -y)
      win.mineBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -SIDE, -y)
      y = y + math.max(22, MIN_TARGET) + GAP
    end
    win.all:ClearAllPoints()
    win.all:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -y)
    win.none:ClearAllPoints()
    win.none:SetPoint("LEFT", win.all, "RIGHT", GAP, 0)
    y = y + BUTTON_H + GAP
    win.hint:ClearAllPoints()
    win.hint:SetShown(win.spec.hint ~= nil)
    if win.spec.hint then
      W.SetText(win.hint, win.spec.hint)
      win.hint:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -y)
      win.hint:SetPoint("TOPRIGHT", f, "TOPRIGHT", -SIDE, -y)
      y = y + HINT_H + GAP
    end
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -y)
    host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SIDE, 52)
  end

  function win.ids()
    local ids = {}
    for _, e in ipairs(win.shown) do
      ids[#ids + 1] = e.id
    end
    return ids
  end

  function win.Refresh()
    local spec = win.spec
    if not spec then
      return
    end
    local all = spec.entries()
    local gate = (win.mine and spec.canGather) and spec.canGather or nil
    win.shown = P.Visible(all, win.query, gate)
    win.mineBox:SetShown(spec.canGather ~= nil)
    win.mineBox.Refresh()
    win.list:SetData(win.shown)
    win.empty:SetShown(#win.shown == 0)
    win.count:SetText(string.format(L["gather.win.count"], P.Count(all, spec.isOn)))
  end

  function win.Apply(ids, on)
    if #ids > 0 then
      win.spec.setMany(ids, on)
    end
    win.Refresh()
  end

  f:HookScript("OnHide", function()
    win.search.edit:SetText("")
    win.search.edit:ClearFocus()
  end)
  ns.On("FG_GATHER_FILTER_CHANGED", function()
    if f:IsShown() then
      win.Refresh()
    end
  end)
  return win
end

-- Opens the window for the area the spec describes. A second call re-targets the same window.
function P.Open(spec)
  if not win then
    build()
  end
  win.spec = spec
  win.query, win.mine = "", false
  win.search.edit:SetText("")
  W.SetText(win.frame.title, spec.title)
  win.Layout()
  win.frame:Show()
  win.Refresh()
end

function P.Close()
  if win then
    win.frame:Hide()
  end
end

function P.IsShown()
  return win ~= nil and win.frame:IsShown()
end

-- The window object (tests): frame, search, list, buttons.
function P.Window()
  return win
end
