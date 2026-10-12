-- Dialogs of the macro editor: spell picker (search, class filter, one row per
-- rank), icon palette, script consent. Own implementation.
local _, ns = ...
local W, L, Theme, C, S, I = ns.W, ns.L, ns.Theme, ns.MacroCore, ns.MacroSpells, ns.MacroItems
local UI = ns.MacroUI

local QUESTION_ICON = 134400
UI.QUESTION_ICON = QUESTION_ICON

local function settings()
  return UI.db().ui
end
UI.settings = settings

local function try(fn, ...)
  return pcall(fn, ...)
end

local function className(token)
  local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return names and names[token] or token
end

local function texture(icon)
  if type(icon) == "string" then
    return "Interface\\Icons\\" .. icon
  end
  return icon
end
UI.texture = texture

local function showSpellTooltip(owner, id, fallbackText)
  W.Tooltip.Show(owner, { spell = id, title = fallbackText or tostring(id) })
end
UI.showSpellTooltip = showSpellTooltip

-- Spell picker ----------------------------------------------------------------

local ROW_H = 24
local picker

local function classOptions()
  local opts = {
    { value = "ALL", key = "macros.picker.class.all" },
    { value = "GENERAL", key = "macros.picker.class.general" },
  }
  for _, token in ipairs(S.CLASSES) do
    opts[#opts + 1] = { value = token, text = className(token) }
  end
  return opts
end

local MODES = {
  { value = "token", key = "macros.picker.mode.token" },
  { value = "name", key = "macros.picker.mode.name" },
  { value = "known", key = "macros.picker.mode.known" },
  { value = "id", key = "macros.picker.mode.id" },
}

local function buildPicker()
  local f = ns.Dialogs.Create("ForeverGuidesSpellPicker", 600, 540)
  local st = { class = "ALL", data = {}, selected = nil }
  f.st = st

  local function selectedRow()
    for _, row in ipairs(st.data) do
      if row.id == st.selected then
        return row
      end
    end
    return st.data[1] and not st.data[1].empty and st.data[1] or nil
  end

  local list
  local detail = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  local count = W.Text(f, { role = "micro", color = "textMuted" })

  local function refresh()
    st.data = S.search(st.query or "", { class = st.class, passive = st.passive, limit = 300 })
    if st.known then
      local kept = {}
      for _, row in ipairs(st.data) do
        if S.isKnown(row.id) == true then
          kept[#kept + 1] = row
        end
      end
      st.data = kept
    end
    if #st.data == 0 then
      st.data = { { empty = true } }
    end
    local found = false
    for _, row in ipairs(st.data) do
      if row.id == st.selected then
        found = true
      end
    end
    if not found then
      st.selected = st.data[1].id
    end
    list:SetData(st.data)
    local row = selectedRow()
    if row then
      local level = row.spell.l and string.format(L["macros.picker.level"], row.spell.l) or ""
      detail:SetText(S.label(row.id) .. (level ~= "" and ("  -  " .. level) or ""))
    else
      detail:SetText(L["macros.picker.none"])
    end
    count:SetText(row and string.format(L["macros.picker.count"], #st.data) or "")
  end
  st.refresh = refresh

  local function move(step)
    for i, row in ipairs(st.data) do
      if row.id == st.selected then
        local nxt = st.data[ns.U.clamp(i + step, 1, #st.data)]
        st.selected = nxt.id
        refresh()
        local visible = math.max(1, math.floor(list:GetHeight() / ROW_H))
        local index = ns.U.clamp(i + step, 1, #st.data)
        list:ScrollBy(-1000000)
        list:ScrollBy(math.max(0, index - visible))
        break
      end
    end
  end

  local function pick(mode)
    local row = selectedRow()
    if not row or not st.opts or not st.opts.onPick then
      return
    end
    local keep = settings().pickerKeep and not st.opts.selectMode
    if not keep then
      f:Hide()
    end
    st.opts.onPick(row, mode)
  end
  st.pick = pick

  local search = W.EditBox(f, {
    placeholder = "macros.spells.search",
    clear = true,
    onChange = function(text)
      st.query = text
      ns.Debounce("macros-spell-search", 0.15, refresh)
    end,
    onEnter = function()
      pick(st.opts and st.opts.selectMode and "token" or settings().pickMode or "token")
    end,
  })
  search:SetPoint("TOPLEFT", 16, -52)
  search:SetWidth(300)
  search.edit:SetScript("OnArrowPressed", function(_, key)
    if key == "UP" then
      move(-1)
    elseif key == "DOWN" then
      move(1)
    end
  end)
  st.search = search

  local classDrop
  local options = classOptions()
  classDrop = W.Dropdown(f, {
    key = "macros.picker.class",
    options = options,
    width = 240,
    get = function()
      return st.class
    end,
    set = function(v)
      st.class = v
      refresh()
    end,
  })
  classDrop:SetPoint("TOPLEFT", 332, -32)
  st.classDrop = classDrop

  local passive = W.Checkbox(f, {
    key = "macros.picker.passive",
    get = function()
      return st.passive == true
    end,
    set = function(v)
      st.passive = v
      refresh()
    end,
  })
  passive:SetPoint("TOPLEFT", 16, -88)
  passive:SetWidth(300)

  local knownCheck = W.Checkbox(f, {
    key = "macros.picker.knownOnly",
    get = function()
      return st.known == true
    end,
    set = function(v)
      st.known = v
      refresh()
    end,
  })
  knownCheck:SetPoint("TOPLEFT", 332, -88)
  knownCheck:SetWidth(252)
  st.knownBox = knownCheck

  local rowCreate = function(parent)
    local row = CreateFrame("Button", nil, parent)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    ns.Bind(row, function()
      hl:SetColorTexture(1, 1, 1, 0.08)
      row.sel:SetColorTexture(Theme.color("action", 0.5))
    end)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 4, ROW_H - 4)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.label = W.Text(row, { role = "ui" })
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", -130, 0)
    row.state = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
    row.state:SetPoint("RIGHT", -4, 0)
    row:SetScript(
      "OnClick",
      ns.Wrap("picker-row", function()
        if row.item and not row.item.empty then
          st.selected = row.item.id
          refresh()
        end
      end)
    )
    row:SetScript(
      "OnDoubleClick",
      ns.Wrap("picker-row2", function()
        if row.item and not row.item.empty then
          st.selected = row.item.id
          pick(st.opts and st.opts.selectMode and "token" or settings().pickMode or "token")
        end
      end)
    )
    row:SetScript("OnEnter", function()
      if row.item and not row.item.empty then
        showSpellTooltip(row, row.item.id, S.label(row.item.id))
      end
    end)
    row:SetScript("OnLeave", ns.HideTooltip)
    ns.Focus.register(row, function()
      row:Click()
    end)
    return row
  end
  local rowBind = function(row, item)
    row.item = item
    if item.empty then
      row.icon:Hide()
      W.SetText(row.label, "macros.spells.empty")
      W.SetColor(row.label, "textMuted")
      row.state:SetText("")
      row.sel:Hide()
      return
    end
    local fid = item.spell.fid
    row.icon:SetShown(fid ~= nil)
    if fid then
      row.icon:SetTexture(fid)
    end
    W.SetText(row.label, nil, S.label(item.id))
    W.SetColor(row.label, item.spell.st and "textMuted" or "text")
    local known = S.isKnown(item.id)
    local state = known == true and L["macros.picker.known"] or known == false and L["macros.picker.unknown"] or ""
    row.state:SetText(state)
    W.SetColor(row.state, known and "success" or "textMuted")
    row.sel:SetShown(item.id == st.selected)
  end
  list = W.ScrollList(f, { rowHeight = ROW_H, createRow = rowCreate, bindRow = rowBind })
  list:SetPoint("TOPLEFT", 16, -116)
  list:SetPoint("BOTTOMRIGHT", -16, 124)
  W.Fill(list, "surface", 1)

  detail:SetPoint("BOTTOMLEFT", 16, 100)
  detail:SetPoint("RIGHT", -120, 0)
  count:SetPoint("BOTTOMRIGHT", -16, 102)

  local modeDrop = W.Dropdown(f, {
    key = "macros.picker.mode",
    options = MODES,
    width = 250,
    get = function()
      return settings().pickMode or "token"
    end,
    set = function(v)
      settings().pickMode = v
    end,
  })
  modeDrop:SetPoint("BOTTOMLEFT", 16, 46)
  st.modeDrop = modeDrop

  local keep = W.Checkbox(f, {
    key = "macros.picker.keep",
    get = function()
      return settings().pickerKeep == true
    end,
    set = function(v)
      settings().pickerKeep = v
    end,
  })
  keep:SetPoint("BOTTOMLEFT", 280, 50)
  keep:SetWidth(300)
  st.keep = keep

  local hint = W.Text(f, { key = "macros.picker.hint", role = "micro", color = "textMuted" })
  hint:SetPoint("BOTTOMLEFT", 16, 18)

  st.insertBtn = W.Button(f, {
    key = "macros.picker.insert",
    variant = "primary",
    width = 120,
    onClick = function()
      pick(st.opts and st.opts.selectMode and "token" or settings().pickMode or "token")
    end,
  })
  st.insertBtn:SetPoint("BOTTOMRIGHT", -16, 14)
  st.baseBtn = W.Button(f, {
    key = "macros.picker.base",
    width = 170,
    tooltip = "macros.picker.base",
    tooltipText = "macros.picker.base.tip",
    onClick = function()
      pick("base")
    end,
  })
  st.baseBtn:SetPoint("RIGHT", st.insertBtn, "LEFT", -8, 0)
  return f
end

-- opts: onPick(row, mode) with mode token|name|known|id|base; selectMode (preset slot, no mode choice);
-- class: initial class filter; query: initial search text; rankStyle: the builder's rank style (any
-- other than "picked" decides the rank itself, so the "highest rank" button goes away).
function UI.OpenSpellPicker(opts)
  if not S.count or S.count() == 0 then
    ns.Notify(L["macros.picker.nodata"], "warning")
    return
  end
  if not picker then
    picker = buildPicker()
  end
  local st = picker.st
  st.opts = opts
  st.class = opts.class or st.class or "ALL"
  st.query = opts.query or ""
  st.search.edit:SetText(st.query)
  W.SetText(picker.title, opts.selectMode and "macros.picker.titleSelect" or "macros.picker.title")
  st.modeDrop:SetShown(not opts.selectMode)
  st.baseBtn:SetShown(not opts.rankStyle or opts.rankStyle == "picked")
  st.keep:SetShown(not opts.selectMode)
  W.SetText(st.insertBtn.label, opts.selectMode and "macros.picker.select" or "macros.picker.insert")
  st.classDrop.Refresh()
  picker:Show()
  st.refresh()
  st.search.edit:SetFocus()
end

-- Item picker --------------------------------------------------------------------

local itemPicker

local function buildItemPicker()
  local f = ns.Dialogs.Create("ForeverGuidesItemPicker", 480, 460)
  local st = { data = {}, query = "" }
  f.st = st
  local list, host, empty

  local function pick(row)
    if not row or not st.opts or not st.opts.onPick then
      return
    end
    f:Hide()
    st.opts.onPick(row)
  end
  st.pick = pick

  local count = W.Text(f, { role = "micro", color = "textMuted" })
  count:SetPoint("BOTTOMLEFT", 16, 18)

  local function refresh()
    st.data = I.search(st.query, { limit = I.LIMIT })
    list:SetData(st.data)
    list:SetShown(#st.data > 0)
    empty:SetShown(#st.data == 0)
    count:SetText(#st.data > 0 and string.format(L["macros.items.count"], #st.data) or "")
  end
  st.refresh = refresh

  local search = W.EditBox(f, {
    placeholder = "macros.items.search",
    clear = true,
    onChange = function(text)
      st.query = text
      ns.Debounce("macros-item-search", 0.15, refresh)
    end,
    onEnter = function()
      pick(st.data[1])
    end,
  })
  search:SetPoint("TOPLEFT", 16, -52)
  search:SetPoint("RIGHT", -16, 0)
  st.search = search

  host = CreateFrame("Frame", nil, f)
  host:SetPoint("TOPLEFT", 16, -90)
  host:SetPoint("BOTTOMRIGHT", -16, 44)
  W.Fill(host, "surface", 1)
  list = ns.PageKit.NewList(host, {
    rowHeight = 40,
    bind = function(row)
      local sources = {}
      for _, source in ipairs(row.sources) do
        sources[#sources + 1] = L["macros.items.source." .. source]
      end
      if #sources == 0 then
        sources[1] = L["macros.items.source.none"]
      end
      return {
        title = ns.ItemInfo.ColorName(row.name, row.quality),
        sub = string.format(L["macros.items.sub"], row.id) .. ", " .. table.concat(sources, ", "),
        icon = I.icon(row.id),
      }
    end,
    onClick = pick,
  })
  list:SetAllPoints(host)
  empty = W.EmptyState(host, { text = "macros.items.empty", hint = "macros.items.emptyHint", icon = "search" })
  empty:Fill()
  return f
end

-- opts: onPick(row) with row = { id, name, quality, sources }. One click on a row chooses it, so does
-- Enter in the search field (the first row).
function UI.OpenItemPicker(opts)
  if not itemPicker then
    itemPicker = buildItemPicker()
  end
  local st = itemPicker.st
  st.opts, st.query = opts, opts.query or ""
  I.Reset()
  W.SetText(itemPicker.title, "macros.items.title")
  st.search.edit:SetText(st.query)
  itemPicker:Show()
  st.refresh()
  st.search.edit:SetFocus()
end

-- Icon palette ------------------------------------------------------------------

local COLS, ROWS, CELL, GAP = 13, 9, 32, 6
local iconPicker
local allIcons

local function gatherIcons()
  if allIcons then
    return allIcons
  end
  local out, seen = {}, {}
  local function add(list)
    for _, icon in ipairs(list) do
      if not seen[icon] then
        seen[icon] = true
        out[#out + 1] = icon
      end
    end
  end
  for _, fnName in ipairs({ "GetMacroIcons", "GetMacroItemIcons", "GetLooseMacroIcons", "GetLooseMacroItemIcons" }) do
    local fn = rawget(_G, fnName)
    if fn then
      local t = {}
      if try(fn, t) then
        add(t)
      end
    end
  end
  if #out == 0 then
    add(S.catalogIcons())
  end
  allIcons = out
  return out
end

local function filterIcons(query)
  local all = gatherIcons()
  local q = S.normalize(query or "")
  if q == "" then
    local out = { QUESTION_ICON }
    for _, icon in ipairs(all) do
      if icon ~= QUESTION_ICON then
        out[#out + 1] = icon
      end
    end
    return out
  end
  local out, seen = {}, {}
  local num = q:match("^%d+$")
  if not num then
    for _, fid in ipairs(S.iconsByName(query, 400)) do
      seen[fid] = true
      out[#out + 1] = fid
    end
  end
  for _, icon in ipairs(all) do
    if not seen[icon] then
      local hit
      if num then
        hit = tostring(icon):find("^" .. num) ~= nil
      elseif type(icon) == "string" then
        hit = icon:lower():gsub("_", " "):find(q, 1, true) ~= nil
      end
      if hit then
        out[#out + 1] = icon
      end
    end
  end
  return out
end

local function buildIconPicker()
  local width = COLS * (CELL + GAP) + 32 + 10
  local f = ns.Dialogs.Create("ForeverGuidesIconPicker", width, 130 + ROWS * (CELL + GAP) + 30)
  local st = { icons = {}, top = 0, cursor = 1 }
  f.st = st
  local cells = {}
  local range = W.Text(f, { role = "micro", color = "textMuted" })
  range:SetPoint("BOTTOMLEFT", 16, 40)
  local hint = W.Text(f, { key = "macros.icon.hint", role = "micro", color = "textMuted" })
  hint:SetPoint("BOTTOMLEFT", 16, 18)

  local function paint()
    local total = #st.icons
    local maxTop = math.max(0, math.ceil(total / COLS) - ROWS)
    st.top = ns.U.clamp(st.top, 0, maxTop)
    for i, cell in ipairs(cells) do
      local index = st.top * COLS + i
      local icon = st.icons[index]
      cell.icon = icon
      cell.index = index
      cell:SetShown(icon ~= nil)
      if icon ~= nil then
        cell.tex:SetTexture(texture(icon))
        local on = index == st.cursor
        cell.mark:SetShown(on or icon == st.current)
        cell.mark:SetColorTexture(Theme.color(on and "actionHi" or "accentDim", on and 0.9 or 0.6))
      end
    end
    if total == 0 then
      range:SetText(L["macros.icon.none"])
    else
      local first = st.top * COLS + 1
      range:SetText(string.format(L["macros.icon.range"], first, math.min(total, first + COLS * ROWS - 1), total))
    end
  end

  local function refresh(resetTop)
    st.icons = filterIcons(st.query)
    if resetTop then
      st.top, st.cursor = 0, 1
    end
    paint()
  end
  st.refresh = refresh

  local function choose(icon)
    if icon == nil then
      return
    end
    f:Hide()
    if st.opts and st.opts.onPick then
      st.opts.onPick(icon)
    end
  end

  local function moveCursor(delta)
    if #st.icons == 0 then
      return
    end
    st.cursor = ns.U.clamp(st.cursor + delta, 1, #st.icons)
    local row = math.floor((st.cursor - 1) / COLS)
    if row < st.top then
      st.top = row
    elseif row >= st.top + ROWS then
      st.top = row - ROWS + 1
    end
    paint()
  end

  local search = W.EditBox(f, {
    placeholder = "macros.icon.search",
    clear = true,
    onChange = function(text)
      st.query = text
      ns.Debounce("macros-icon-search", 0.15, function()
        refresh(true)
      end)
    end,
    onEnter = function()
      choose(st.icons[st.cursor])
    end,
  })
  search:SetPoint("TOPLEFT", 16, -48)
  search:SetPoint("RIGHT", -16, 0)
  search.edit:SetScript("OnArrowPressed", function(self, key)
    local empty = self:GetText() == ""
    if key == "UP" then
      moveCursor(-COLS)
    elseif key == "DOWN" then
      moveCursor(COLS)
    elseif key == "LEFT" and empty then
      moveCursor(-1)
    elseif key == "RIGHT" and empty then
      moveCursor(1)
    end
  end)
  st.search = search

  local grid = CreateFrame("Frame", nil, f)
  grid:SetPoint("TOPLEFT", 16, -86)
  grid:SetSize(COLS * (CELL + GAP), ROWS * (CELL + GAP))
  W.Fill(grid, "surface", 1)
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local cell = CreateFrame("Button", nil, grid)
      cell:SetSize(CELL, CELL)
      cell:SetPoint("TOPLEFT", c * (CELL + GAP) + GAP / 2, -(r * (CELL + GAP) + GAP / 2))
      cell.mark = cell:CreateTexture(nil, "BACKGROUND")
      cell.mark:SetPoint("TOPLEFT", -2, 2)
      cell.mark:SetPoint("BOTTOMRIGHT", 2, -2)
      cell.mark:Hide()
      cell.tex = cell:CreateTexture(nil, "ARTWORK")
      cell.tex:SetAllPoints()
      cell.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      cell:SetScript(
        "OnClick",
        ns.Wrap("icon-cell", function()
          choose(cell.icon)
        end)
      )
      cell:SetScript("OnEnter", function()
        if cell.icon == nil then
          return
        end
        local lines = {}
        if cell.icon == QUESTION_ICON then
          lines[1] = L["macros.icon.dynamic"]
        elseif type(cell.icon) == "number" then
          local names = S.iconNames(cell.icon)
          lines[1] = names[1] or L["macros.icon.unnamed"]
          lines[2] = string.format(L["macros.icon.fileid"], cell.icon)
        else
          lines[1] = tostring(cell.icon)
        end
        ns.ShowTooltip(cell, lines[1], lines[2])
      end)
      cell:SetScript("OnLeave", ns.HideTooltip)
      ns.Focus.register(cell, function()
        cell:Click()
      end)
      cells[#cells + 1] = cell
    end
  end
  grid:EnableMouseWheel(true)
  grid:SetScript("OnMouseWheel", function(_, delta)
    st.top = st.top - delta * 2
    paint()
  end)
  return f
end

-- opts: current (icon), onPick(icon).
function UI.OpenIconPicker(opts)
  if not iconPicker then
    iconPicker = buildIconPicker()
  end
  local st = iconPicker.st
  st.opts, st.current, st.query = opts, opts.current, ""
  W.SetText(iconPicker.title, "macros.icon.title")
  st.search.edit:SetText("")
  st.refresh(true)
  iconPicker:Show()
  st.search.edit:SetFocus()
end

function UI.ResetIcons()
  allIcons = nil
end

-- Script consent ---------------------------------------------------------------

local consent

-- lines: from MacroCore.scriptLines; actionKey: locale key naming what happens.
-- Nothing is accepted by closing: accept() only runs from the explicit button.
function UI.AskScriptConsent(lines, actionKey, accept, decline)
  if not consent then
    consent = ns.Dialogs.Create("ForeverGuidesConsentDialog", 520, 400)
    consent.warn = W.Text(consent, { role = "text", wrap = true, color = "warning" })
    consent.warn:SetPoint("TOPLEFT", 16, -48)
    consent.warn:SetPoint("RIGHT", -16, 0)
    consent.action = W.Text(consent, { role = "ui", wrap = true })
    consent.action:SetPoint("TOPLEFT", consent.warn, "BOTTOMLEFT", 0, -10)
    consent.action:SetPoint("RIGHT", -16, 0)
    consent.lines = W.Text(consent, { role = "ui", color = "textSecondary", wrap = true })
    consent.lines:SetPoint("TOPLEFT", consent.action, "BOTTOMLEFT", 0, -8)
    consent.lines:SetPoint("RIGHT", -16, 0)
    consent.yes = W.Button(consent, { key = "macros.consent.accept", variant = "gold", width = 210 })
    consent.yes:SetPoint("BOTTOMRIGHT", -16, 14)
    consent.no = W.Button(consent, { key = "macros.consent.decline", variant = "primary", width = 150 })
    consent.no:SetPoint("RIGHT", consent.yes, "LEFT", -8, 0)
    consent:SetScript("OnHide", function(self)
      ns.Dialogs.open[self] = nil
      local fn = self.onDecline
      self.onAccept, self.onDecline = nil, nil
      if fn then
        fn()
      end
    end)
    consent.yes:SetScript(
      "OnClick",
      ns.Wrap("consent-yes", function()
        local fn = consent.onAccept
        consent.onAccept, consent.onDecline = nil, nil
        consent:Hide()
        if fn then
          fn()
        end
      end)
    )
    consent.no:SetScript("OnClick", function()
      consent:Hide()
    end)
  end
  W.SetText(consent.title, "macros.consent.title")
  local cats = {}
  for _, cat in ipairs(C.categories(lines)) do
    cats[#cats + 1] = "- " .. L["macros.consent.cat." .. cat]
  end
  consent.warn:SetText(L["macros.consent.text"] .. "\n" .. table.concat(cats, "\n"))
  consent.action:SetText(string.format(L["macros.consent.action"], L[actionKey]))
  local shown = {}
  for i, entry in ipairs(lines) do
    if i > 6 then
      shown[#shown + 1] = string.format(L["macros.consent.more"], #lines - 6)
      break
    end
    local text = ns.U.trim(entry.text)
    if #text > 70 then
      text = text:sub(1, 67) .. "..."
    end
    shown[#shown + 1] = string.format(L["macros.consent.line"], entry.line, (text:gsub("|", "||")))
  end
  consent.lines:SetText(table.concat(shown, "\n"))
  consent.onAccept, consent.onDecline = accept, decline
  consent:Show()
end
