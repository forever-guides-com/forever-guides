-- The "Manage layouts" dialog of the layout editor (ns.LayoutDialog): its own window with a search box and a
-- list of every layout that scrolls over the full height. Each row shows the name (check mark: open in the
-- editor, star: unsaved changes), a line of tags (who uses the layout) and the controls: Select, "Applies to"
-- (not assigned, this character, every character of its class) where the host assigns layouts, Rename, Copy and
-- Delete. The footer holds New and Close. The size follows the editor window (LayoutAssign.DialogSize).
-- The dialog knows nothing of the editor: everything goes through the table passed to Open:
--   entries() -> { { id, name, detail?, scope?, classes? }, ... }   current() -> id   dirty() -> bool
--   headKey = locale key of the list name ("Layouts"), titleKey = locale key of the title
--   select(id), rename(id), duplicate(id), delete(id), new(), assign(id, scope)   (a missing one hides its control)
--   canDelete(id) -> bool, assignment() -> { accountId, classToken, hintKey? } | nil (nil: nothing is assigned here)
--   an entry may carry default (true: the default of its group, false: not) and defaultKey (the tag text)
--   editorSize() -> w, h of the editor window, onClose()
local _, ns = ...
local W, L, Theme, LA, ES = ns.W, ns.L, ns.Theme, ns.LayoutAssign, ns.EditorSize

local LD = {}
ns.LayoutDialog = LD

ns.AddLocale("enUS", {
  ["layoutdlg.title"] = "Manage layouts",
  ["layoutdlg.manage"] = "Manage",
  ["layoutdlg.manageTip"] = "Opens a window with every layout: search, open, rename, copy, delete and choose who uses it.",
  ["layoutdlg.hint"] = "Choose per layout whether this character only or every character of its class uses it. A choice for the character wins over the class, the account default applies otherwise.",
  ["layoutdlg.search"] = "Search layouts",
  ["layoutdlg.count"] = "%d of %d",
  ["layoutdlg.none"] = "No layout matches.",
  ["layoutdlg.select"] = "Open",
  ["layoutdlg.selectTip"] = "Opens this layout in the editor.",
  ["layoutdlg.opened"] = "Open",
  ["layoutdlg.scope"] = "Applies to",
  ["layoutdlg.scopeTip"] = "Who uses this layout: nobody in particular (the account default applies), this character only, or every character of its class on the account.",
  ["layoutdlg.scope.none"] = "Not assigned",
  ["layoutdlg.scope.char"] = "This character",
  ["layoutdlg.scope.class"] = "Class: %s",
  ["layoutdlg.tag.char"] = "This character",
  ["layoutdlg.tag.class"] = "Class: %s",
  ["layoutdlg.tag.account"] = "Account default",
  ["layoutdlg.tag.dirty"] = "Unsaved changes",
  ["layoutdlg.new"] = "New",
  ["layoutdlg.close"] = "Close",
})
ns.AddLocale("deDE", {
  ["layoutdlg.title"] = "Layouts verwalten",
  ["layoutdlg.manage"] = "Verwalten",
  ["layoutdlg.manageTip"] = "Öffnet ein Fenster mit allen Layouts: suchen, öffnen, umbenennen, kopieren, löschen und festlegen, wer es nutzt.",
  ["layoutdlg.hint"] = "Lege pro Layout fest, ob nur dieser Charakter oder alle Charaktere seiner Klasse es nutzen. Eine Wahl für den Charakter schlägt die Klasse, sonst gilt der Konto-Standard.",
  ["layoutdlg.search"] = "Layouts suchen",
  ["layoutdlg.count"] = "%d von %d",
  ["layoutdlg.none"] = "Kein Layout passt.",
  ["layoutdlg.select"] = "Öffnen",
  ["layoutdlg.selectTip"] = "Öffnet dieses Layout im Editor.",
  ["layoutdlg.opened"] = "Geöffnet",
  ["layoutdlg.scope"] = "Gilt für",
  ["layoutdlg.scopeTip"] = "Wer dieses Layout nutzt: niemand im Besonderen (es gilt der Konto-Standard), nur dieser Charakter oder alle Charaktere seiner Klasse auf dem Account.",
  ["layoutdlg.scope.none"] = "Nicht zugewiesen",
  ["layoutdlg.scope.char"] = "Dieser Charakter",
  ["layoutdlg.scope.class"] = "Klasse: %s",
  ["layoutdlg.tag.char"] = "Dieser Charakter",
  ["layoutdlg.tag.class"] = "Klasse: %s",
  ["layoutdlg.tag.account"] = "Konto-Standard",
  ["layoutdlg.tag.dirty"] = "Ungespeicherte Änderungen",
  ["layoutdlg.new"] = "Neu",
  ["layoutdlg.close"] = "Schließen",
})

local ICON, SELECT_W, SCOPE_W, GAP = 22, 84, 178, 4

local dlg, api
-- Every row frame made so far (the list pools them); tests and the editor read them through LD.Rows.
local made = {}

-- The localized name of a class token.
local function className(token)
  local ref = ns.RefLogic
  return ref and ref.className and ref.className(token) or token
end

local function classNames(tokens)
  local out = {}
  for i, token in ipairs(tokens or {}) do
    out[i] = className(token)
  end
  return table.concat(out, ", ")
end

-- The tag line of a layout: who uses it and whether it holds unsaved changes. Every part says its meaning in
-- words (no color or symbol alone).
function LD.Tags(entry, info, dirty)
  local parts = {}
  if entry.scope == "char" then
    parts[#parts + 1] = L["layoutdlg.tag.char"]
  end
  if type(entry.classes) == "table" and #entry.classes > 0 then
    parts[#parts + 1] = string.format(L["layoutdlg.tag.class"], classNames(entry.classes))
  end
  -- A host with a default of its own per entry (HUD windows) says so with `default`.
  local isDefault = entry.default
  if isDefault == nil then
    isDefault = info ~= nil and info.accountId == entry.id
  end
  if isDefault then
    parts[#parts + 1] = L[entry.defaultKey or "layoutdlg.tag.account"]
  end
  if dirty then
    parts[#parts + 1] = L["layoutdlg.tag.dirty"]
  end
  if type(entry.detail) == "string" and entry.detail ~= "" then
    parts[#parts + 1] = entry.detail
  end
  return table.concat(parts, ", ")
end

local function scopeOptions(info)
  local options = {
    { value = "none", key = "layoutdlg.scope.none" },
    { value = "char", key = "layoutdlg.scope.char" },
  }
  if info and info.classToken then
    options[3] = { value = "class", text = string.format(L["layoutdlg.scope.class"], className(info.classToken)) }
  end
  return options
end

local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  made[#made + 1] = row
  row.line = row:CreateTexture(nil, "BACKGROUND")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  row.line:SetColorTexture(1, 1, 1, 0.06)
  row.mark = W.Glyph(row, "check", 14, "accent2")
  row.flag = W.Text(row, { text = "*", role = "ui", color = "warning", justify = "RIGHT" })
  row.detail = W.Text(row, { role = "small", color = "textSecondary" })
  row.detail:SetWordWrap(false)
  row.detail:SetJustifyH("LEFT")
  local function icon(name, tip, tipText, onClick)
    return W.Action(row, {
      icon = name,
      size = ICON,
      tooltip = tip,
      tooltipText = tipText,
      wrap = "layout-dialog-row",
      onClick = onClick,
    })
  end
  row.del = icon("trash", "act.delete", "canvas.deleteTip", function()
    api.delete(row.id)
  end)
  row.share = icon("share", "layoutshare.btn", "layoutshare.tip.layout", function()
    api.share(row.id)
  end)
  row.dup = icon("copy", "act.duplicate", "canvas.dupTip", function()
    api.duplicate(row.id)
  end)
  row.ren = icon("pencil", "act.rename", "canvas.renameTip", function()
    api.rename(row.id)
  end)
  row.open = W.Action(row, {
    label = "layoutdlg.select",
    height = ICON,
    width = SELECT_W,
    tooltip = "layoutdlg.select",
    tooltipText = "layoutdlg.selectTip",
    wrap = "layout-dialog-row",
    onClick = function()
      api.select(row.id)
    end,
  })
  row.options = {}
  row.scope = W.Dropdown(row, {
    compact = true,
    width = SCOPE_W,
    options = row.options,
    tooltip = "layoutdlg.scope",
    tooltipText = "layoutdlg.scopeTip",
    get = function()
      return row.entry and row.entry.scope or "none"
    end,
    set = function(value)
      if row.id ~= nil then
        api.assign(row.id, value ~= "none" and value or nil)
      end
    end,
  })
  row.scope:SetWidth(SCOPE_W)
  row.scope.button.fgName = function()
    local value = row.entry and row.entry.scope or "none"
    for _, option in ipairs(row.options) do
      if option.value == value then
        return L["layoutdlg.scope"] .. ": " .. (option.text or L[option.key])
      end
    end
    return L["layoutdlg.scope"]
  end
  row.name = W.Text(row, { role = "ui", color = "text" })
  row.name:SetWordWrap(false)
  row.name:SetJustifyH("LEFT")
  row.name.fgName = function()
    return row.fullName
  end
  return row
end

local function bindRow(row, entry)
  local info = api.assignment and api.assignment() or nil
  row.id, row.entry, row.fullName = entry.id, entry, entry.name
  row.current = entry.id == api.current()
  row.dirty = row.current and api.dirty()
  row.mark:SetShown(row.current)
  row.mark:ClearAllPoints()
  row.mark:SetPoint("TOPLEFT", 4, -5)
  W.SetText(row.name, nil, entry.name)
  W.SetColor(row.name, row.current and "accent2" or "text")
  W.SetText(row.detail, nil, LD.Tags(entry, info, row.dirty))
  -- Right edge: Delete, Share, Copy, Rename, then the scope field and Open.
  local x = -4
  for _, item in ipairs({
    { row.del, api.delete ~= nil and api.canDelete(entry.id) },
    { row.share, api.share ~= nil },
    { row.dup, api.duplicate ~= nil },
    { row.ren, api.rename ~= nil },
  }) do
    local button, offered = item[1], item[2]
    button:SetShown(offered)
    if offered then
      button:ClearAllPoints()
      button:SetPoint("TOPRIGHT", row, "TOPRIGHT", x, -2)
      x = x - ICON - 2
    end
  end
  local assignable = info ~= nil and api.assign ~= nil
  row.scope:SetShown(assignable)
  if assignable then
    for i = #row.options, 1, -1 do
      row.options[i] = nil
    end
    for i, option in ipairs(scopeOptions(info)) do
      row.options[i] = option
    end
    row.scope:ClearAllPoints()
    row.scope:SetPoint("TOPRIGHT", row, "TOPRIGHT", x - 4, -1)
    row.scope.Refresh()
    x = x - 4 - SCOPE_W - GAP
  end
  row.open:SetShown(not row.current)
  row.open:ClearAllPoints()
  row.open:SetPoint("TOPRIGHT", row, "TOPRIGHT", x - 4, -2)
  local edge = x - 4 - (row.current and 0 or SELECT_W + GAP)
  row.flag:SetShown(row.dirty == true)
  row.flag:ClearAllPoints()
  row.name:ClearAllPoints()
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -4)
  row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", edge - (row.dirty and 14 or 0), -4)
  row.flag:SetPoint("TOPRIGHT", row, "TOPRIGHT", edge - 2, -4)
  local _, line = ES.TwoLineRowH(Theme.fontSize("small"))
  row.detail:SetHeight(line)
  row.name:SetHeight(ES.NAME_LINE_H - 4)
  row.detail:ClearAllPoints()
  row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -ES.TwoLineDetailY())
  row.detail:SetPoint("TOPRIGHT", row, "TOPRIGHT", edge, -ES.TwoLineDetailY())
end

local function build()
  local d = ns.Dialogs.Create("ForeverGuidesLayoutDialog", 760, 520)
  dlg = d
  d.hint = W.Text(d, { key = "layoutdlg.hint", role = "small", color = "textSecondary", wrap = true })
  d.hint:SetPoint("TOPLEFT", 16, -46)
  d.hint:SetPoint("TOPRIGHT", -16, -46)
  d.search = W.EditBox(d, {
    placeholder = "layoutdlg.search",
    clear = true,
    onChange = function()
      LD.Refresh()
    end,
  })
  d.count = W.Text(d, { role = "small", color = "textSecondary", justify = "RIGHT" })
  d.none = W.Text(d, { key = "layoutdlg.none", role = "ui", color = "textSecondary" })
  d.list = W.ScrollList(d, { rowHeight = 44, createRow = createRow, bindRow = bindRow })
  d.new = W.Action(d, {
    label = "layoutdlg.new",
    icon = "plus",
    tooltip = "layoutdlg.new",
    tooltipText = "canvas.newTip",
    width = 120,
    onClick = function()
      if api.new then
        api.new()
      end
    end,
  })
  d.new:SetPoint("BOTTOMLEFT", 16, 14)
  d.close = W.Action(d, {
    label = "layoutdlg.close",
    icon = "close",
    tooltip = "layoutdlg.close",
    variant = "primary",
    width = 120,
    onClick = function()
      d:Hide()
    end,
  })
  d.close:SetPoint("BOTTOMRIGHT", -16, 14)
  d:HookScript("OnHide", function()
    if api and api.onClose then
      ns.Safe("layout-dialog-close", api.onClose)
    end
  end)
end

-- Size and place the parts for the current window sizes: the hint takes the room its text needs, the search
-- box the line under it, the list the rest down to the footer.
local function place()
  local d = dlg
  local info = api.assignment and api.assignment() or nil
  W.SetText(d.hint, info and info.hintKey or "layoutdlg.hint")
  local hintH = api.assignment and api.assignment() and (math.ceil(d.hint:GetStringHeight()) + 4) or 0
  d.hint:SetShown(hintH > 0)
  local top = 46 + hintH + (hintH > 0 and 6 or 0)
  d.search:ClearAllPoints()
  d.search:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -top)
  d.search:SetPoint("TOPRIGHT", d, "TOPRIGHT", -150, -top)
  d.count:ClearAllPoints()
  d.count:SetPoint("TOPRIGHT", d, "TOPRIGHT", -16, -(top + 6))
  d.list:ClearAllPoints()
  -- Explicit size: the list counts its rows from its own height.
  d.list:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -(top + 34))
  d.list:SetSize(math.max(d:GetWidth() - 32, 1), math.max(d:GetHeight() - (top + 34) - 56, 1))
  d.none:ClearAllPoints()
  d.none:SetPoint("TOPLEFT", d.list, "TOPLEFT", 8, -8)
  d.new:SetShown(api.new ~= nil)
end

-- Sizes the dialog to the editor window (see LayoutAssign.DialogSize); keeps the dialog on screen.
function LD.Fit()
  if not (dlg and api) then
    return
  end
  local ew, eh = api.editorSize()
  local scale = dlg:GetScale()
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  if type(scale) == "number" and scale > 0 then
    sw, sh = sw / scale, sh / scale
  end
  dlg:SetSize(LA.DialogSize(ew, eh, sw, sh))
  place()
end

function LD.Refresh()
  if not (dlg and api and dlg:IsShown()) then
    return
  end
  local all = api.entries()
  local shown = LA.Filter(all, dlg.search.edit:GetText())
  dlg.count:SetText(string.format(L["layoutdlg.count"], #shown, #all))
  dlg.none:SetShown(#shown == 0)
  place()
  dlg.list:SetRowHeight((ES.TwoLineRowH(Theme.fontSize("small"))))
  dlg.list:SetData(shown)
end

-- Opens the dialog for the host `host` (see the top of the file). One dialog serves every editor session.
function LD.Open(host)
  if not dlg then
    build()
  end
  api = host
  W.SetText(dlg.title, host.titleKey or "layoutdlg.title")
  dlg.search.edit:SetText("")
  dlg:Show()
  LD.Fit()
  LD.Refresh()
  -- Show the open layout without searching for it.
  local entries = api.entries()
  for i, entry in ipairs(entries) do
    if entry.id == api.current() then
      dlg.list:Reveal(i)
    end
  end
  dlg.search.edit:SetFocus()
end

function LD.Close()
  if dlg and dlg:IsShown() then
    dlg:Hide()
  end
end

function LD.IsOpen()
  return dlg ~= nil and dlg:IsShown()
end

function LD.Rows()
  return made
end

function LD.Frame()
  return dlg
end
