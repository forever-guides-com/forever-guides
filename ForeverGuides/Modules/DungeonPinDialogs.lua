-- Dialogs of the dungeon map editor: the pin chooser (what to place at the clicked spot), the
-- export window and the import window with its preview. Rules and storage live in
-- Modules/PinLogic.lua, the map widget is Modules/DungeonMapView.lua.
local _, ns = ...
local W, L, Theme, P, U = ns.W, ns.L, ns.Theme, ns.PinLogic, ns.U

local D = {}
ns.DungeonPinDialogs = D

ns.AddLocale("enUS", {
  ["dmap.kind.boss"] = "Boss",
  ["dmap.kind.entrance"] = "Entrance",
  ["dmap.kind.link"] = "Passage to another floor",
  ["dmap.kind.marker"] = "Marker",
  ["dmap.icon.skull"] = "Skull",
  ["dmap.icon.star"] = "Star",
  ["dmap.icon.circle"] = "Circle",
  ["dmap.icon.diamond"] = "Diamond",
  ["dmap.icon.triangle"] = "Triangle",
  ["dmap.icon.moon"] = "Moon",
  ["dmap.icon.square"] = "Square",
  ["dmap.icon.cross"] = "Cross",
  ["dmap.pick.title"] = "Set pin",
  ["dmap.pick.kind"] = "What do you want to place here?",
  ["dmap.pick.boss"] = "Pick the boss (one pin per boss, a new one moves it)",
  ["dmap.pick.floor"] = "Pick the floor this passage leads to.",
  ["dmap.pick.icon"] = "Pick a symbol for the marker.",
  ["dmap.pick.markerBoss"] = "Does the marker belong to a boss? (optional)",
  ["dmap.pick.noBoss"] = "No boss",
  ["dmap.pick.placed"] = "set (floor %d)",
  ["dmap.pick.floorRow"] = "Floor %d",
  ["dmap.pick.label"] = "Text for the marker (optional, up to 40 characters).",
  ["dmap.pick.labelPlaceholder"] = "Text",
  ["dmap.pick.set"] = "Set pin",
  ["dmap.pick.back"] = "Back",
  ["dmap.export.title"] = "Export pins",
  ["dmap.export.hint"] = "For the website: selected, Ctrl+C copies",
  ["dmap.export.scopeInst"] = "This instance",
  ["dmap.export.scopeAll"] = "All own pins",
  ["dmap.import.title"] = "Import pins",
  ["dmap.import.hint"] = "Paste the exported text, then click Apply",
  ["dmap.import.apply"] = "Apply",
  ["dmap.import.preview"] = "%d new, %d replaced, %d rejected",
  ["dmap.import.invalid"] = "The text can not be read: %s",
  ["dmap.import.rejectedRow"] = "Pin %d: %s",
  ["dmap.import.done"] = "Pins imported: %d new, %d replaced.",
})
ns.AddLocale("deDE", {
  ["dmap.kind.boss"] = "Boss",
  ["dmap.kind.entrance"] = "Eingang",
  ["dmap.kind.link"] = "Übergang zu einer anderen Ebene",
  ["dmap.kind.marker"] = "Marker",
  ["dmap.icon.skull"] = "Totenkopf",
  ["dmap.icon.star"] = "Stern",
  ["dmap.icon.circle"] = "Kreis",
  ["dmap.icon.diamond"] = "Raute",
  ["dmap.icon.triangle"] = "Dreieck",
  ["dmap.icon.moon"] = "Mond",
  ["dmap.icon.square"] = "Quadrat",
  ["dmap.icon.cross"] = "Kreuz",
  ["dmap.pick.title"] = "Pin setzen",
  ["dmap.pick.kind"] = "Was möchtest du hier setzen?",
  ["dmap.pick.boss"] = "Boss wählen (ein Pin pro Boss, neuer verschiebt)",
  ["dmap.pick.floor"] = "Wähle die Ebene, zu der dieser Übergang führt.",
  ["dmap.pick.icon"] = "Wähle ein Symbol für den Marker.",
  ["dmap.pick.markerBoss"] = "Gehört der Marker zu einem Boss? (optional)",
  ["dmap.pick.noBoss"] = "Kein Boss",
  ["dmap.pick.placed"] = "gesetzt (Ebene %d)",
  ["dmap.pick.floorRow"] = "Ebene %d",
  ["dmap.pick.label"] = "Text für den Marker (optional, höchstens 40 Zeichen).",
  ["dmap.pick.labelPlaceholder"] = "Text",
  ["dmap.pick.set"] = "Pin setzen",
  ["dmap.pick.back"] = "Zurück",
  ["dmap.export.title"] = "Pins exportieren",
  ["dmap.export.hint"] = "Für die Website: markiert, Strg+C kopiert",
  ["dmap.export.scopeInst"] = "Diese Instanz",
  ["dmap.export.scopeAll"] = "Alle eigenen Pins",
  ["dmap.import.title"] = "Pins importieren",
  ["dmap.import.hint"] = "Exportierten Text einfügen, dann Übernehmen",
  ["dmap.import.apply"] = "Übernehmen",
  ["dmap.import.preview"] = "%d neu, %d ersetzt, %d abgelehnt",
  ["dmap.import.invalid"] = "Der Text lässt sich nicht lesen: %s",
  ["dmap.import.rejectedRow"] = "Pin %d: %s",
  ["dmap.import.done"] = "Pins importiert: %d neu, %d ersetzt.",
})

local SIDE, ROW_H = 16, 26
local MAX_REJECTS_SHOWN = 4

-- Marker palette -------------------------------------------------------------------------------

D.ICONS = { "skull", "star", "circle", "diamond", "triangle", "moon", "square", "cross" }
-- Position in the client's raid target sheet (4 columns, each icon a quarter of the width and height).
local SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local SHEET_INDEX = { star = 1, circle = 2, diamond = 3, triangle = 4, moon = 5, square = 6, cross = 7, skull = 8 }

-- Paints a palette symbol on a texture. Returns false (texture cleared) for a key outside the palette.
function D.PaintIcon(tex, key)
  local i = SHEET_INDEX[key]
  if not i then
    tex:SetTexture(nil)
    return false
  end
  local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
  tex:SetTexture(SHEET)
  tex:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25)
  return true
end

function D.IconName(key)
  local k = "dmap.icon." .. tostring(key)
  return L[k] ~= k and L[k] or tostring(key)
end

-- Boss name in the active language.
function D.BossName(boss)
  local n = boss.name or {}
  return ns.GetActiveLocale() == "deDE" and (n.de or n.en) or (n.en or n.de) or "?"
end

local function closeOnEscape(dialog, edit)
  edit:SetScript("OnEscapePressed", function()
    dialog:Hide()
  end)
end

-- Focus the field next frame, the window is not laid out when Show returns.
local function focusLater(edit, select)
  C_Timer.After(0.05, function()
    edit:SetFocus()
    if select then
      edit:HighlightText()
    end
  end)
end

-- A button that shows a selected state (never by color alone: the selected one also gets a border).
local function choiceButton(parent, key, width, onClick)
  local b = W.Button(parent, { key = key, width = width, onClick = onClick })
  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  ns.Bind(b, function()
    b.sel:SetColorTexture(Theme.color("action", 0.5))
  end)
  return b
end

-- Pin chooser -----------------------------------------------------------------------------------

local chooser
local STEP = {}

local function placedFloors(ctx)
  local placed = {}
  for _, pin in ipairs(P.Pins(ctx.inst)) do
    if pin.kind == "boss" then
      for _, b in ipairs(ctx.bosses) do
        if (pin.eid and b.eid == pin.eid) or b.name.en == pin.boss or pin.idx == b.idx then
          placed[b.idx] = pin.floor
          break
        end
      end
    end
  end
  return placed
end

local function bossFields(b)
  return { boss = b.name.en, idx = b.idx, eid = b.eid, npc = b.npc }
end

local function finish(d, spec)
  d:Hide()
  d.onPick(spec)
end

local function go(d, step)
  d.step = step
  if step == "kind" then
    d.spec = nil
  end
  local items, prompt = STEP[step].items(d), STEP[step].prompt
  W.SetText(d.prompt, prompt)
  local isLabel = step == "label"
  d.list:SetShown(not isLabel)
  d.field:SetShown(isLabel)
  d.setButton:SetShown(isLabel)
  d.back:SetShown(step ~= "kind")
  d.items = items
  d.list:SetData(items)
  if isLabel then
    d.field.edit:SetText("")
    focusLater(d.field.edit, false)
  end
end

STEP.kind = {
  prompt = "dmap.pick.title",
  items = function(d)
    local items = {}
    if #d.ctx.bosses > 0 then
      items[#items + 1] = { id = "boss", text = L["dmap.kind.boss"] }
    end
    items[#items + 1] = { id = "entrance", text = L["dmap.kind.entrance"] }
    if d.ctx.floors > 1 then
      items[#items + 1] = { id = "link", text = L["dmap.kind.link"] }
    end
    items[#items + 1] = { id = "marker", text = L["dmap.kind.marker"] }
    return items
  end,
  pick = function(d, item)
    if item.id == "entrance" then
      finish(d, { kind = "entrance" })
    elseif item.id == "boss" then
      go(d, "boss")
    elseif item.id == "link" then
      go(d, "floor")
    else
      d.spec = { kind = "marker" }
      go(d, "icon")
    end
  end,
}

STEP.boss = {
  prompt = "dmap.pick.boss",
  items = function(d)
    local placed, items = placedFloors(d.ctx), {}
    for _, b in ipairs(d.ctx.bosses) do
      items[#items + 1] = {
        text = D.BossName(b),
        boss = b,
        state = placed[b.idx] and string.format(L["dmap.pick.placed"], placed[b.idx]) or nil,
      }
    end
    return items
  end,
  pick = function(d, item)
    local spec = bossFields(item.boss)
    spec.kind = "boss"
    finish(d, spec)
  end,
}

STEP.floor = {
  prompt = "dmap.pick.floor",
  items = function(d)
    local items = {}
    for f = 1, d.ctx.floors do
      if f ~= d.ctx.floor then
        items[#items + 1] = { text = string.format(L["dmap.pick.floorRow"], f), floor = f }
      end
    end
    return items
  end,
  pick = function(d, item)
    finish(d, { kind = "link", toFloor = item.floor })
  end,
}

STEP.icon = {
  prompt = "dmap.pick.icon",
  items = function()
    local items = {}
    for _, key in ipairs(D.ICONS) do
      items[#items + 1] = { text = D.IconName(key), icon = key }
    end
    return items
  end,
  pick = function(d, item)
    d.spec.icon = item.icon
    go(d, #d.ctx.bosses > 0 and "markerBoss" or "label")
  end,
}

STEP.markerBoss = {
  prompt = "dmap.pick.markerBoss",
  items = function(d)
    local items = { { text = L["dmap.pick.noBoss"] } }
    for _, b in ipairs(d.ctx.bosses) do
      items[#items + 1] = { text = D.BossName(b), boss = b }
    end
    return items
  end,
  pick = function(d, item)
    if item.boss then
      for k, v in pairs(bossFields(item.boss)) do
        d.spec[k] = v
      end
    end
    go(d, "label")
  end,
}

STEP.label = {
  prompt = "dmap.pick.label",
  items = function()
    return {}
  end,
}

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  ns.Bind(row, function()
    hl:SetColorTexture(1, 1, 1, 0.08)
  end)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", 8, 0)
  row.state = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
  row.state:SetPoint("RIGHT", -4, 0)
  row.label = W.Text(row, { role = "ui" })
  row:SetScript(
    "OnClick",
    ns.Wrap("dmap-pick", function()
      if row.item and chooser then
        local pick = STEP[chooser.step].pick
        if pick then
          pick(chooser, row.item)
        end
      end
    end)
  )
  return row
end

local function bindRow(row, item)
  row.item = item
  W.SetText(row.label, nil, item.text)
  W.SetText(row.state, nil, item.state or "")
  local hasIcon = item.icon and D.PaintIcon(row.icon, item.icon)
  row.icon:SetShown(hasIcon and true or false)
  row.label:ClearAllPoints()
  row.label:SetPoint("LEFT", hasIcon and 34 or 8, 0)
  row.label:SetPoint("RIGHT", row.state, "LEFT", -4, 0)
end

local function submitLabel(d)
  local text = U.trim(d.field.edit:GetText() or "")
  d.spec.label = text ~= "" and text or nil
  finish(d, d.spec)
end

local function createChooser()
  local d = ns.Dialogs.Create("ForeverGuidesPinChooser", 360, 420)
  W.SetText(d.title, "dmap.pick.title")
  d.prompt = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
  d.prompt:SetPoint("TOPLEFT", SIDE, -48)
  d.prompt:SetPoint("RIGHT", -SIDE, 0)
  d.prompt:SetHeight(32)
  d.list = W.ScrollList(d, { rowHeight = ROW_H, createRow = createRow, bindRow = bindRow })
  d.list:SetPoint("TOPLEFT", d.prompt, "BOTTOMLEFT", 0, -8)
  d.list:SetPoint("BOTTOMRIGHT", -SIDE, 56)
  W.Fill(d.list, "surface", 1)
  d.field = W.EditBox(d, { placeholder = "dmap.pick.labelPlaceholder" })
  d.field:SetPoint("TOPLEFT", d.prompt, "BOTTOMLEFT", 0, -8)
  d.field:SetPoint("RIGHT", -SIDE, 0)
  d.field.edit:SetMaxLetters(P.MAX_LABEL)
  d.field.edit:SetScript(
    "OnEnterPressed",
    ns.Wrap("dmap-label", function()
      submitLabel(d)
    end)
  )
  closeOnEscape(d, d.field.edit)
  local cancel = W.Action(d, {
    label = "act.cancel",
    icon = "close",
    tooltip = "common.cancel",
    width = 100,
    onClick = function()
      d:Hide()
    end,
  })
  cancel:SetPoint("BOTTOMRIGHT", -SIDE, 14)
  d.setButton = W.Action(d, {
    label = "act.apply",
    icon = "check",
    tooltip = "dmap.pick.set",
    variant = "primary",
    width = 110,
    onClick = function()
      submitLabel(d)
    end,
  })
  d.setButton:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
  d.back = W.Action(d, {
    label = "act.back",
    icon = "chevron-left",
    tooltip = "dmap.pick.back",
    width = 100,
    height = 28,
    onClick = function()
      go(d, "kind")
    end,
  })
  d.back:SetPoint("BOTTOMLEFT", SIDE, 14)
  return d
end

-- ctx = { inst = DungeonAssets key, floor, floors = count }. onPick(spec) gets the kind specific
-- fields (kind, boss/idx/eid/npc, toFloor, icon, label); the caller adds inst, floor, x and y.
function D.Choose(ctx, onPick)
  if not chooser then
    chooser = createChooser()
  end
  local d = chooser
  d.ctx = { inst = ctx.inst, floor = ctx.floor, floors = ctx.floors, bosses = P.BossList(ctx.inst) }
  d.onPick = onPick
  d.spec = nil
  d:Show()
  go(d, "kind")
  return d
end

function D.Chooser()
  return chooser
end

-- Picks an item of the current step like a click on its row (for keyboard-free callers and tests).
function D.ChooserPick(index)
  local d = chooser
  local item = d and d.items[index]
  if item and STEP[d.step].pick then
    STEP[d.step].pick(d, item)
  end
end

-- Export ----------------------------------------------------------------------------------------

local exportDialog

local function fillExport(d)
  d.scopeInst.sel:SetShown(d.scope == "inst")
  d.scopeAll.sel:SetShown(d.scope == "all")
  d.area:SetValue(P.Export(d.scope == "inst" and { inst = d.inst } or nil))
  focusLater(d.area.edit, true)
end

-- inst = DungeonAssets key of the open instance (the export of this instance only).
function D.Export(inst)
  local d = exportDialog
  if not d then
    d = ns.Dialogs.Create("ForeverGuidesPinExport", 540, 380)
    exportDialog = d
    W.SetText(d.title, "dmap.export.title")
    local hint = W.Text(d, { key = "dmap.export.hint", role = "ui", color = "textSecondary", wrap = true })
    hint:SetPoint("TOPLEFT", SIDE, -48)
    hint:SetPoint("RIGHT", -SIDE, 0)
    hint:SetHeight(32)
    d.scopeInst = choiceButton(d, "dmap.export.scopeInst", 150, function()
      d.scope = "inst"
      fillExport(d)
    end)
    d.scopeInst:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    d.scopeAll = choiceButton(d, "dmap.export.scopeAll", 170, function()
      d.scope = "all"
      fillExport(d)
    end)
    d.scopeAll:SetPoint("LEFT", d.scopeInst, "RIGHT", 8, 0)
    d.area = W.TextArea(d, { height = 190, readOnly = true })
    d.area:SetPoint("TOPLEFT", d.scopeInst, "BOTTOMLEFT", 0, -8)
    d.area:SetPoint("RIGHT", -SIDE, 0)
    closeOnEscape(d, d.area.edit)
    d.area.edit:HookScript("OnEditFocusGained", function(self)
      self:HighlightText()
    end)
    local keys = W.Text(d, { key = "copy.hint", role = "micro", color = "textMuted" })
    keys:SetPoint("BOTTOMLEFT", SIDE, 20)
    local close = W.Action(d, {
      label = "act.close",
      icon = "close",
      tooltip = "common.close",
      variant = "primary",
      width = 110,
      onClick = function()
        d:Hide()
      end,
    })
    close:SetPoint("BOTTOMRIGHT", -SIDE, 14)
    local all = W.Button(d, {
      key = "copy.select",
      width = 130,
      onClick = function()
        d.area.edit:SetFocus()
        d.area.edit:HighlightText()
      end,
    })
    all:SetPoint("RIGHT", close, "LEFT", -8, 0)
  end
  d.inst, d.scope = inst, inst and "inst" or "all"
  d.scopeInst:SetShown(inst ~= nil)
  d:Show()
  fillExport(d)
  return d
end

-- Import -----------------------------------------------------------------------------------------

local importDialog

local function preview(d)
  local text = d.input:GetValue()
  d.result = nil
  d.apply:Disable()
  W.SetColor(d.summary, "textSecondary")
  W.SetText(d.summary, nil, "")
  W.SetText(d.rejects, nil, "")
  if U.trim(text) == "" then
    return
  end
  local result, reason = P.Import(text, "preview")
  if not result then
    W.SetColor(d.summary, "danger")
    W.SetText(d.summary, nil, string.format(L["dmap.import.invalid"], tostring(reason)))
    return
  end
  d.result = result
  W.SetText(d.summary, nil, string.format(L["dmap.import.preview"], result.added, result.replaced, #result.rejected))
  local lines = {}
  for i, r in ipairs(result.rejected) do
    if i > MAX_REJECTS_SHOWN then
      lines[#lines + 1] = "..."
      break
    end
    lines[#lines + 1] = string.format(L["dmap.import.rejectedRow"], r.index, r.reason)
  end
  W.SetText(d.rejects, nil, table.concat(lines, "\n"))
  if result.added + result.replaced > 0 then
    d.apply:Enable()
  end
end

local function apply(d)
  local result = P.Import(d.input:GetValue(), "apply")
  if not result then
    return
  end
  d:Hide()
  ns.Notify(string.format(L["dmap.import.done"], result.added, result.replaced), "success")
  if d.onApplied then
    d.onApplied(result)
  end
end

-- onApplied(result) runs after the pins were stored (the map repaints).
function D.Import(onApplied)
  local d = importDialog
  if not d then
    d = ns.Dialogs.Create("ForeverGuidesPinImport", 540, 400)
    importDialog = d
    W.SetText(d.title, "dmap.import.title")
    local hint = W.Text(d, { key = "dmap.import.hint", role = "ui", color = "textSecondary", wrap = true })
    hint:SetPoint("TOPLEFT", SIDE, -48)
    hint:SetPoint("RIGHT", -SIDE, 0)
    hint:SetHeight(32)
    d.input = W.TextArea(d, {
      height = 190,
      onChange = function()
        preview(d)
      end,
    })
    d.input:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    d.input:SetPoint("RIGHT", -SIDE, 0)
    closeOnEscape(d, d.input.edit)
    d.summary = W.Text(d, { role = "ui", color = "textSecondary", wrap = true, text = "" })
    d.summary:SetPoint("TOPLEFT", d.input, "BOTTOMLEFT", 0, -8)
    d.summary:SetPoint("RIGHT", -SIDE, 0)
    d.summary:SetHeight(18)
    d.rejects = W.Text(d, { role = "micro", color = "textMuted", wrap = true, text = "" })
    d.rejects:SetPoint("TOPLEFT", d.summary, "BOTTOMLEFT", 0, -4)
    d.rejects:SetPoint("RIGHT", -SIDE, 0)
    d.rejects:SetHeight(56)
    local cancel = W.Action(d, {
      label = "act.cancel",
      icon = "close",
      tooltip = "common.cancel",
      width = 110,
      onClick = function()
        d:Hide()
      end,
    })
    cancel:SetPoint("BOTTOMRIGHT", -SIDE, 14)
    d.apply = W.Action(d, {
      label = "act.apply",
      icon = "check",
      tooltip = "dmap.import.apply",
      variant = "primary",
      width = 130,
      onClick = function()
        apply(d)
      end,
    })
    d.apply:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
  end
  d.onApplied = onApplied
  d.input:SetValue("")
  preview(d)
  d:Show()
  focusLater(d.input.edit, false)
  return d
end
