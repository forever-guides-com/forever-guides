-- "Choose map" window of the drawing editor: a search field over a grouped list (zones, then dungeons
-- and raids with the number of floors as the second line), a floor dropdown for instances with more
-- than one floor, the opacity of the map and the buttons "No map" and "Fit sheet to map". The list
-- comes from ns.DrawingMap. A click shows the map at once (the editor draws it live), a double click
-- or Enter takes it and closes the window when nothing is left to choose (a zone or an instance with
-- one floor), the arrow keys move the selection, Esc closes. Instances without a map yet ("map
-- coming soon") are listed dimmed and cannot be chosen.
-- DMP.Open{ map, onChange(map | nil), onFit(map) (optional) } reports every change; the caller owns
-- the drawing.
local _, ns = ...
local W, L, Theme, D, DM = ns.W, ns.L, ns.Theme, ns.DrawingLogic, ns.DrawingMap
local FL = ns.FlowLayout

local DMP = {}
ns.DrawingMapPicker = DMP

local PAD, FULL_W, FULL_H = 16, 560, 600
local SEARCH_Y = 52
local SCREEN_MARGIN = 24

ns.AddLocale("enUS", {
  ["draw.map.title"] = "Choose map",
  ["draw.map.search"] = "Search zones, dungeons and raids",
  ["draw.map.hint"] = "Click shows the map, double click or Enter takes it.",
  ["draw.map.empty"] = "Nothing found.",
  ["draw.map.noZones"] = "Zone maps are not available on this client.",
  ["draw.map.current"] = "Active",
  ["draw.map.floor"] = "Floor",
  ["draw.map.alpha"] = "Opacity of the map",
  ["draw.map.none"] = "No map",
  ["draw.map.noneTip"] = "Removes the map. The drawing stays.",
  ["draw.map.fit"] = "Fit sheet to map",
  ["draw.map.fitTip"] = "Gives the sheet the shape of the map.\nUndo brings the old size back.",
  ["draw.map.missing"] = "Map not available here: %s",
  ["draw.group.map"] = "Map",
  ["draw.map.choose"] = "Choose map...",
  ["draw.map.choose.tip"] = "Pick a zone, dungeon or raid map as the background to draw on.",
  ["draw.map.remove"] = "Remove map",
  ["draw.map.hardEdges"] = "Over a map the pen draws hard edges",
  ["draw.map.fitNone"] = "This map is not available here.",
  ["draw.map.fitSame"] = "The sheet already has this shape.",
})
ns.AddLocale("deDE", {
  ["draw.map.title"] = "Karte wählen",
  ["draw.map.search"] = "Gebiete, Dungeons und Raids suchen",
  ["draw.map.hint"] = "Klick zeigt die Karte, Doppelklick oder Enter übernimmt sie.",
  ["draw.map.empty"] = "Nichts gefunden.",
  ["draw.map.noZones"] = "Gebietskarten sind in diesem Client nicht verfügbar.",
  ["draw.map.current"] = "Aktiv",
  ["draw.map.floor"] = "Ebene",
  ["draw.map.alpha"] = "Deckkraft der Karte",
  ["draw.map.none"] = "Keine Karte",
  ["draw.map.noneTip"] = "Entfernt die Karte. Die Zeichnung bleibt.",
  ["draw.map.fit"] = "Blatt an Karte anpassen",
  ["draw.map.fitTip"] = "Gibt dem Blatt die Form der Karte.\nRückgängig bringt die alte Größe zurück.",
  ["draw.map.missing"] = "Karte hier nicht verfügbar: %s",
  ["draw.group.map"] = "Karte",
  ["draw.map.choose"] = "Karte wählen...",
  ["draw.map.choose.tip"] = "Wähle eine Gebiets-, Dungeon- oder Raidkarte als Hintergrund zum Zeichnen.",
  ["draw.map.remove"] = "Karte entfernen",
  ["draw.map.hardEdges"] = "Über einer Karte zeichnet der Stift mit harten Kanten",
  ["draw.map.fitNone"] = "Diese Karte ist hier nicht verfügbar.",
  ["draw.map.fitSame"] = "Das Blatt hat diese Form schon.",
})

local dialog

local function rowHeight()
  return ns.Desktop and ns.Desktop.scaled(38) or 38
end

local function selectable(item)
  return item ~= nil and item.id ~= nil and not item.soon
end

-- A copy of a map with the given parts replaced.
local function with(map, patch)
  local out = { kind = map.kind, id = map.id, key = map.key, floor = map.floor, alpha = map.alpha }
  for k, v in pairs(patch) do
    out[k] = v
  end
  return out
end

-- Nothing left to choose after this entry: a zone, or an instance with one floor.
local function complete(item)
  return item.map.kind == "zone" or item.floors <= 1
end

local function build()
  local f = ns.Dialogs.Create("ForeverGuidesDrawingMapPicker", FULL_W, FULL_H)
  W.SetText(f.title, "draw.map.title")
  local st = { query = "", rows = {}, floorOptions = {} }
  f.st = st

  -- Entries -------------------------------------------------------------------------------------

  local function currentId()
    return DM.IdOf(st.map)
  end

  local function rebuild()
    local rows = {}
    for _, g in ipairs(DM.Filter(st.groups, st.query)) do
      rows[#rows + 1] = { header = g.title }
      for _, entry in ipairs(g.items) do
        rows[#rows + 1] = entry
      end
    end
    if #rows == 0 then
      rows[1] = { note = L["draw.map.empty"] }
    end
    if not st.hasZones and st.query == "" then
      rows[#rows + 1] = { note = L["draw.map.noZones"] }
    end
    st.rows = rows
    local found = false
    for _, row in ipairs(rows) do
      if row.id and row.id == st.sel then
        found = true
      end
    end
    if not found then
      st.sel = nil
      for _, row in ipairs(rows) do
        if row.id and row.id == currentId() then
          st.sel = row.id
        end
      end
      if not st.sel then
        for _, row in ipairs(rows) do
          if selectable(row) then
            st.sel = row.id
            break
          end
        end
      end
    end
  end

  local function selected()
    for i, row in ipairs(st.rows) do
      if row.id and row.id == st.sel then
        return row, i
      end
    end
  end

  -- Controls --------------------------------------------------------------------------------------

  local list, search, hint, floorDrop, alpha, buttons, layout

  local function showList()
    list:SetData(st.rows)
  end

  local function commit(map)
    st.map = map
    if st.opts and st.opts.onChange then
      st.opts.onChange(map)
    end
  end

  local function sync()
    local map = st.map
    local floors = map and map.kind == "instance" and DM.FloorCount(map.key) or 0
    for i = #st.floorOptions, 1, -1 do
      st.floorOptions[i] = nil
    end
    for i = 1, floors do
      st.floorOptions[i] = { value = i, text = DM.FloorName(map.key, i) }
    end
    floorDrop:SetShown(floors > 1)
    floorDrop.Refresh()
    alpha:SetShown(map ~= nil)
    alpha.Refresh()
    buttons:SetItemShown("none", map ~= nil)
    buttons:SetItemShown("fit", map ~= nil and st.opts ~= nil and st.opts.onFit ~= nil and DM.FitSize(map) ~= nil)
    layout()
    showList()
  end

  local function choose(item, close)
    if not selectable(item) then
      return
    end
    st.sel = item.id
    local cur = st.map
    local map = with(item.map, { alpha = cur and cur.alpha or D.MAP_ALPHA_DEFAULT })
    if
      map.kind == "instance"
      and cur
      and cur.kind == "instance"
      and cur.key == map.key
      and cur.floor <= item.floors
    then
      map.floor = cur.floor
    end
    commit(map)
    sync()
    if close and complete(item) then
      f:Hide()
    end
  end

  local function take()
    local item = selected()
    if item then
      choose(item, true)
    end
  end

  local function move(step)
    local _, at = selected()
    local i = (at or (step > 0 and 0 or #st.rows + 1)) + step
    while st.rows[i] and not selectable(st.rows[i]) do
      i = i + step
    end
    if st.rows[i] then
      st.sel = st.rows[i].id
      list:Reveal(i)
    end
  end

  -- Frames ----------------------------------------------------------------------------------------

  search = W.EditBox(f, {
    placeholder = "draw.map.search",
    clear = true,
    onChange = function(text)
      st.query = text
      rebuild()
      showList()
    end,
    onEnter = take,
  })
  search:SetPoint("TOPLEFT", PAD, -SEARCH_Y)
  search:SetPoint("TOPRIGHT", -PAD, -SEARCH_Y)
  search.edit:SetScript("OnArrowPressed", function(_, key)
    if key == "UP" then
      move(-1)
    elseif key == "DOWN" then
      move(1)
    end
  end)
  search.edit:SetScript("OnEscapePressed", function()
    f:Hide()
  end)

  hint = W.Text(f, { key = "draw.map.hint", role = "micro", color = "textMuted", wrap = true })
  hint:SetPoint("TOPLEFT", PAD, -(SEARCH_Y + 34))

  local ROW_H = rowHeight()
  local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    ns.Bind(row, function()
      hl:SetColorTexture(1, 1, 1, 0.08)
      row.sel:SetColorTexture(Theme.color("action", 0.5))
    end)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetPoint("BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", 0, 0)
    row.line:SetHeight(1)
    ns.Bind(row.line, function(t)
      t:SetColorTexture(1, 1, 1, Theme.lineAlpha())
    end)
    row.current = W.Text(row, { key = "draw.map.current", role = "micro", color = "accent2", justify = "RIGHT" })
    row.current:SetPoint("RIGHT", -8, 0)
    row.title = W.Text(row, { role = "ui" })
    row.title:SetPoint("TOPLEFT", 8, -4)
    row.title:SetPoint("RIGHT", row.current, "LEFT", -8, 0)
    row.sub = W.Text(row, { role = "micro", color = "textMuted" })
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
    row.sub:SetPoint("RIGHT", row.current, "LEFT", -8, 0)
    row:SetScript(
      "OnClick",
      ns.Wrap("drawmap-row", function()
        choose(row.item, false)
      end)
    )
    row:SetScript(
      "OnDoubleClick",
      ns.Wrap("drawmap-row2", function()
        choose(row.item, true)
      end)
    )
    ns.Focus.register(row, function()
      row:Click()
    end)
    return row
  end

  local function bindRow(row, item)
    row.item = item
    local isEntry = item.id ~= nil
    row.line:SetShown(item.header ~= nil)
    row.sel:SetShown(isEntry and item.id == st.sel)
    row.current:SetShown(isEntry and item.id == currentId())
    local text = item.header or item.note or item.title
    W.SetText(row.title, nil, text)
    W.SetColor(row.title, item.header and "accent2" or (item.note or item.soon) and "textMuted" or "text")
    W.SetText(row.sub, nil, item.sub or "")
    row.sub:SetShown(item.sub ~= nil)
    if item.header then
      row.title:ClearAllPoints()
      row.title:SetPoint("LEFT", 8, 0)
      row.title:SetPoint("RIGHT", -8, 0)
    else
      row.title:ClearAllPoints()
      row.title:SetPoint("TOPLEFT", 8, -4)
      row.title:SetPoint("RIGHT", row.current, "LEFT", -8, 0)
    end
  end

  list = W.ScrollList(f, { rowHeight = ROW_H, createRow = createRow, bindRow = bindRow })
  W.Fill(list, "surface", 1)

  floorDrop = W.Dropdown(f, {
    key = "draw.map.floor",
    options = st.floorOptions,
    width = 200,
    get = function()
      return st.map and st.map.floor or 1
    end,
    set = function(n)
      if st.map and st.map.kind == "instance" then
        commit(with(st.map, { floor = n }))
        sync()
      end
    end,
  })
  FL.FitDropdown(floorDrop)

  alpha = W.Slider(f, {
    key = "draw.map.alpha",
    min = 10,
    max = 100,
    step = 5,
    get = function()
      return st.map and st.map.alpha or D.MAP_ALPHA_DEFAULT
    end,
    set = function(v)
      if st.map then
        commit(with(st.map, { alpha = v }))
      end
    end,
    format = function(v)
      return v .. " %"
    end,
  })

  buttons = FL.ButtonRow(f, {
    {
      id = "none",
      label = "act.remove",
      icon = "close",
      width = 110,
      tooltip = "draw.map.none",
      tooltipText = "draw.map.noneTip",
      onClick = function()
        commit(nil)
        sync()
      end,
    },
    {
      id = "fit",
      label = "act.fit",
      icon = "refresh",
      width = 150,
      tooltip = "draw.map.fit",
      tooltipText = "draw.map.fitTip",
      onClick = function()
        if st.map and st.opts and st.opts.onFit then
          st.opts.onFit(st.map)
        end
      end,
    },
    {
      id = "close",
      label = "act.close",
      icon = "close",
      tooltip = "common.close",
      width = 90,
      variant = "primary",
      onClick = function()
        f:Hide()
      end,
    },
  }, { gap = 8 })

  -- The window follows the screen on small screens; the controls stack from the bottom, the list
  -- takes what is left.
  function layout()
    local scale = f:GetScale() > 0 and f:GetScale() or 1
    local sw, sh = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
    local width = math.max(300, math.min(FULL_W, math.floor(sw - SCREEN_MARGIN)))
    local height = math.max(420, math.min(FULL_H, math.floor(sh - SCREEN_MARGIN)))
    f:SetSize(width, height)
    local inner = width - 2 * PAD
    local y = PAD
    buttons:SetWidth(inner)
    local bh = buttons:SetWidthAvailable(inner)
    buttons:ClearAllPoints()
    buttons:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, y)
    y = y + bh + 10
    if alpha:IsShown() then
      alpha:ClearAllPoints()
      alpha:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, y)
      alpha:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, y)
      y = y + alpha:GetHeight() + 8
    end
    if floorDrop:IsShown() then
      floorDrop:ClearAllPoints()
      floorDrop:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, y)
      floorDrop:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, y)
      y = y + floorDrop:GetHeight() + 8
    end
    hint:SetWidth(inner)
    local top = SEARCH_Y + 34 + math.ceil(hint:GetStringHeight()) + 6
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -top)
    list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, y)
  end

  f.search, f.list, f.hint, f.floorDrop, f.alpha, f.buttons = search, list, hint, floorDrop, alpha, buttons
  f.choose, f.take, f.move, f.sync, f.layout, f.selected = choose, take, move, sync, layout, selected
  f.rebuild, f.showList = rebuild, showList

  f:HookScript("OnHide", function()
    st.opts = nil
  end)
  ns.On("FG_UI_REFRESHED", function()
    if f:IsShown() and st.opts then
      st.groups = DM.Choices()
      rebuild()
      sync()
    end
  end)
  return f
end

-- Opens the window. opts: map (the current one), onChange(map | nil), onFit(map) (optional).
function DMP.Open(opts)
  if not dialog then
    dialog = build()
  end
  local f, st = dialog, dialog.st
  st.opts = opts
  st.map = opts and D.cleanMap(opts.map) or nil
  st.groups = DM.Choices()
  st.hasZones = false
  for _, g in ipairs(st.groups) do
    if g.id == "zones" then
      st.hasZones = true
    end
  end
  st.query, st.sel = "", nil
  f.search.edit:SetText("")
  f:Show()
  f.rebuild()
  f.sync()
  -- A map that is set: its entry is brought into view.
  local _, at = f.selected()
  if at and st.map then
    f.list:Reveal(at)
  end
  f.search.edit:SetFocus()
  return f
end

function DMP.Close()
  if dialog and dialog:IsShown() then
    dialog:Hide()
  end
end

function DMP.IsOpen()
  return dialog ~= nil and dialog:IsShown()
end

function DMP.Dialog()
  return dialog
end
