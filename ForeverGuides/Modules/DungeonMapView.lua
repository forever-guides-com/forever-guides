-- Dungeon map widget: the floors of one instance as a picture of 256 px tiles (FileDataIDs from
-- Data.DungeonAssets, the client loads the files) with the boss, entrance, passage and marker
-- pins of Modules/PinLogic.lua on top, and an editor mode for the player's own pins. A floor is either
-- the older 4 by 3 grid cut to 3:2, or a minimap crop of any cols by rows (floor.cols, floor.rows), also
-- portrait; the picture is fitted into the room that is left (see DMV.MapSize) and pins and marker use
-- fractions of the visible picture. More than one floor: a dropdown picks the floor. An instance
-- without a map shows a dimmed loading screen with "map coming soon". Players have no position inside
-- instances, so there is no player marker, only the optional rough area marker (SetMarker). Hosts:
-- Modules/InstancesPage.lua and Modules/DungeonWorldMap.lua (which uses the hooks onFloorPick and
-- onMapClick and the height limit maxHeight). Tiles and pins come from pools and go back (textures
-- cleared) when the widget hides.
local _, ns = ...
local W, L, Theme, P, PD = ns.W, ns.L, ns.Theme, ns.PinLogic, ns.DungeonPinDialogs

local DMV = {}
ns.DungeonMapView = DMV

DMV.COLS, DMV.ROWS = 4, 3
-- 256 px tiles; of the 4 by 3 grid only the top left 1002x668 px (3:2) of the 1024x768 show map.
DMV.TILE, DMV.VIEW_W, DMV.VIEW_H = 256, 1002, 668
DMV.LAST_W = DMV.VIEW_W - (DMV.COLS - 1) * DMV.TILE
DMV.LAST_H = DMV.VIEW_H - (DMV.ROWS - 1) * DMV.TILE
DMV.MAX_W = 720
-- Tallest and lowest the picture gets; a host can lower the top with view.maxHeight (height of the widget).
DMV.MAX_H, DMV.MIN_H = 600, 120
DMV.PIN = 20

local GAP, CTRL_H, DROP_W, DROP_H, MARKER = 6, 24, 170, 46, 22

-- Visible part of a floor in texture pixels: { cols, rows, w, h }. A minimap crop (floor.cols and
-- floor.rows) shows every tile whole, any other floor is the 4 by 3 grid cut to 3:2.
function DMV.Geometry(floor)
  if floor and floor.cols and floor.rows then
    return { cols = floor.cols, rows = floor.rows, w = floor.cols * DMV.TILE, h = floor.rows * DMV.TILE }
  end
  return { cols = DMV.COLS, rows = DMV.ROWS, w = DMV.VIEW_W, h = DMV.VIEW_H }
end

-- Size of the picture in a widget of this width: as wide as the width allows (at most MAX_W), as high
-- as its aspect says, at most maxHeight (default MAX_H). When the height is the limit the picture is
-- fitted into that room (R.Fit) and sits in the middle of it. Returns x (offset inside the room), w, h.
function DMV.MapSize(width, geo, maxHeight)
  local roomW = math.max(1, math.floor(math.min(width, DMV.MAX_W)))
  local natural = math.max(1, math.floor(roomW * geo.h / geo.w + 0.5))
  local roomH = math.max(DMV.MIN_H, math.floor(math.min(maxHeight or DMV.MAX_H, DMV.MAX_H)))
  if natural <= roomH then
    return 0, roomW, natural
  end
  local x, _, w, h = ns.MapRevealLogic.Fit(geo.w, geo.h, roomW, roomH)
  return math.floor(x + 0.5), math.max(1, math.floor(w + 0.5)), math.max(1, math.floor(h + 0.5))
end

ns.AddLocale("enUS", {
  ["dmap.floor"] = "Choose floor",
  ["dmap.floorN"] = "Floor %d",
  ["dmap.edit"] = "Edit pins",
  ["dmap.export"] = "Export",
  ["dmap.import"] = "Import",
  ["dmap.noInstance"] = "Select an instance to see its map.",
  ["dmap.soon"] = "Map coming soon",
  ["dmap.pins.none"] = "No pins on this floor yet.",
  ["dmap.pins.bosses"] = "Bosses on this floor: %s",
  ["dmap.pins.noBosses"] = "No bosses set on this floor yet.",
  ["dmap.editHint"] = "Left click sets, drag moves, right click deletes",
  ["dmap.link.to"] = "Passage to floor %d",
  ["dmap.own"] = "Your own pin",
  ["dmap.pin.editHint"] = "Drag to move, right click to delete.",
  ["dmap.delete.title"] = "Delete pin",
  ["dmap.delete.text"] = "Delete this pin?",
  ["dmap.error"] = "Pin not saved: %s",
})
ns.AddLocale("deDE", {
  ["dmap.floor"] = "Ebene wählen",
  ["dmap.floorN"] = "Ebene %d",
  ["dmap.edit"] = "Pins bearbeiten",
  ["dmap.export"] = "Exportieren",
  ["dmap.import"] = "Importieren",
  ["dmap.noInstance"] = "Wähle eine Instanz, um ihre Karte zu sehen.",
  ["dmap.soon"] = "Karte kommt bald",
  ["dmap.pins.none"] = "Auf dieser Ebene sind noch keine Pins gesetzt.",
  ["dmap.pins.bosses"] = "Bosse auf dieser Ebene: %s",
  ["dmap.pins.noBosses"] = "Auf dieser Ebene sind noch keine Bosse gesetzt.",
  ["dmap.editHint"] = "Linksklick setzt, Ziehen verschiebt, Rechtsklick löscht",
  ["dmap.link.to"] = "Übergang zu Ebene %d",
  ["dmap.own"] = "Dein eigener Pin",
  ["dmap.pin.editHint"] = "Ziehen verschiebt, Rechtsklick löscht.",
  ["dmap.delete.title"] = "Pin löschen",
  ["dmap.delete.text"] = "Diesen Pin löschen?",
  ["dmap.error"] = "Pin nicht gespeichert: %s",
})

local function maps()
  return ns.Data.DungeonAssets and ns.Data.DungeonAssets.maps or {}
end

local function round3(v)
  return math.floor(v * 1000 + 0.5) / 1000
end

-- Instance lookup -------------------------------------------------------------------------------

-- Data.Instances entry by game instance ID (number) or by name in either language (string).
local function findInstance(what)
  for _, inst in ipairs(ns.Data.Instances or {}) do
    local n = inst.n or {}
    if (type(what) == "number" and inst.id == what) or (type(what) == "string" and (n.en == what or n.de == what)) then
      return inst
    end
  end
end

-- DungeonAssets key (English name) for GetInstanceInfo() results: the instance ID or the name.
-- Nil when the instance is unknown or has no entry in the map data.
function DMV.KeyFor(what)
  if type(what) == "string" and maps()[what] then
    return what
  end
  local inst = findInstance(what)
  local en = inst and inst.n and inst.n.en
  return en and maps()[en] and en or nil
end

-- The Data.Instances entry of the dungeon or raid the player is in, else nil.
function DMV.Current()
  if not GetInstanceInfo then
    return nil
  end
  local name, kind, _, _, _, _, _, id = GetInstanceInfo()
  if kind ~= "party" and kind ~= "raid" then
    return nil
  end
  return findInstance(id) or findInstance(name)
end

-- Widget ----------------------------------------------------------------------------------------

local function canEdit(pin)
  return pin.own or pin.kind == "boss"
end

function DMV.Create(parent)
  local f = CreateFrame("Frame", nil, parent)
  local state = { key = nil, floor = 1, floors = 0, edit = false, bosses = {}, width = nil, mapW = 0, mapH = 0 }
  f.state = state
  f.tiles, f.pinFrames = {}, {}
  f.tilesUsed, f.pinsUsed = 0, 0
  local floorDrop, floorOptions, editToggle, exportButton, importButton, map, hint, info, marker, soon
  local pins = {}

  -- Called after a click changed what the widget needs in height (the page lays out again).
  local function changed()
    if f.onChange then
      f.onChange()
    end
  end

  -- Pools ---------------------------------------------------------------------------------------

  local function acquireTile()
    f.tilesUsed = f.tilesUsed + 1
    local tex = f.tiles[f.tilesUsed]
    if not tex then
      tex = map:CreateTexture(nil, "ARTWORK")
      f.tiles[f.tilesUsed] = tex
    end
    tex:Show()
    return tex
  end

  local function cursorFraction()
    local cx, cy = GetCursorPosition()
    local scale = map:GetEffectiveScale()
    local w, h = map:GetWidth(), map:GetHeight()
    if not scale or scale <= 0 or w <= 0 or h <= 0 then
      return 0, 0
    end
    local x = ((cx or 0) / scale - (map:GetLeft() or 0)) / w
    local y = ((map:GetTop() or 0) - (cy or 0) / scale) / h
    return round3(math.min(1, math.max(0, x))), round3(math.min(1, math.max(0, y)))
  end

  local function bossLabel(pin)
    for _, b in ipairs(state.bosses) do
      if (pin.eid and b.eid == pin.eid) or b.name.en == pin.boss then
        return PD.BossName(b)
      end
    end
    return pin.boss
  end

  local function pinTitle(pin)
    if pin.kind == "boss" then
      return bossLabel(pin) or "?"
    elseif pin.kind == "entrance" then
      return L["dmap.kind.entrance"]
    elseif pin.kind == "link" then
      return string.format(L["dmap.link.to"], pin.toFloor)
    end
    return pin.label or PD.IconName(pin.icon)
  end

  local function showTooltip(pin)
    local lines = {}
    if pin.kind == "marker" and pin.boss then
      lines[#lines + 1] = bossLabel(pin)
    end
    if pin.own then
      lines[#lines + 1] = L["dmap.own"]
    end
    if state.edit and canEdit(pin) then
      lines[#lines + 1] = L["dmap.pin.editHint"]
    end
    ns.ShowTooltip(pin.frame, pinTitle(pin), table.concat(lines, "\n"))
  end

  -- Storage -------------------------------------------------------------------------------------

  local function fail(err)
    ns.Notify(string.format(L["dmap.error"], tostring(err)), "error")
  end

  -- Index of an own pin among the own pins of its kind, the address PinLogic.Remove takes.
  local function ownIndex(pin)
    local n = 0
    for _, p in ipairs(P.OwnPins(state.key)) do
      if p.kind == pin.kind then
        n = n + 1
        if
          p.floor == pin.floor
          and p.x == pin.x
          and p.y == pin.y
          and p.icon == pin.icon
          and p.toFloor == pin.toFloor
        then
          return n
        end
      end
    end
  end

  local function removeOwn(pin)
    if pin.kind == "boss" then
      return P.Remove(state.key, pin.boss)
    end
    local index = ownIndex(pin)
    return index and P.Remove(state.key, pin.kind, index) or false
  end

  local render

  local function move(pin, x, y)
    local moved = {}
    for k, v in pairs(pin) do
      moved[k] = v
    end
    moved.frame, moved.own, moved.x, moved.y = nil, nil, round3(x), round3(y)
    -- Boss pins are replaced by identity, every other kind is identified by its position.
    if pin.own and pin.kind ~= "boss" then
      removeOwn(pin)
    end
    local ok, err = P.Set(moved)
    if not ok then
      fail(err)
    end
    render()
    changed()
  end

  local function delete(pin)
    ns.Dialogs.Confirm("dmap.delete.title", "dmap.delete.text", function()
      removeOwn(pin)
      render()
      changed()
    end)
  end

  local function place(spec, floor, x, y)
    spec.inst, spec.floor, spec.x, spec.y = state.key, floor, x, y
    local ok, err = P.Set(spec)
    if not ok then
      fail(err)
    end
    render()
    changed()
  end

  -- Pins ----------------------------------------------------------------------------------------

  local function createPin()
    local pin = CreateFrame("Button", nil, map)
    pin:SetSize(DMV.PIN, DMV.PIN)
    pin.plate = pin:CreateTexture(nil, "BACKGROUND")
    pin.plate:SetAllPoints()
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("TOPLEFT", 2, -2)
    pin.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    pin.glyph = W.Text(pin, { role = "micro", color = "text", justify = "CENTER" })
    pin.glyph:SetPoint("CENTER")
    W.Border(pin, "white", 0.8, 1)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:RegisterForDrag("LeftButton")
    pin:SetScript("OnEnter", function(self)
      if self.pin then
        showTooltip(self.pin)
      end
    end)
    pin:SetScript("OnLeave", ns.HideTooltip)
    pin:SetScript(
      "OnClick",
      ns.Wrap("dmap-pin", function(self, button)
        if button == "RightButton" and state.edit and self.pin and self.pin.own then
          delete(self.pin)
        end
      end)
    )
    pin:SetScript(
      "OnDragStart",
      ns.Wrap("dmap-drag", function(self)
        if not (state.edit and self.pin and canEdit(self.pin)) then
          return
        end
        state.drag = self
        self:SetScript("OnUpdate", function()
          local x, y = cursorFraction()
          self:ClearAllPoints()
          self:SetPoint("CENTER", map, "TOPLEFT", x * state.mapW, -y * state.mapH)
        end)
      end)
    )
    pin:SetScript(
      "OnDragStop",
      ns.Wrap("dmap-drop", function(self)
        if state.drag ~= self then
          return
        end
        state.drag = nil
        self:SetScript("OnUpdate", nil)
        local x, y = cursorFraction()
        move(self.pin, x, y)
      end)
    )
    return pin
  end

  local function paintPin(frame, pin)
    local plate, glyph
    glyph = ""
    frame.icon:SetTexture(nil)
    if pin.kind == "boss" then
      plate = "danger"
      PD.PaintIcon(frame.icon, "skull")
    elseif pin.kind == "entrance" then
      plate, glyph = "success", "E"
    elseif pin.kind == "link" then
      plate, glyph = "action", tostring(pin.toFloor)
    else
      plate = "accent2"
      if not PD.PaintIcon(frame.icon, pin.icon) then
        glyph = "?"
      end
    end
    frame.plate:SetColorTexture(Theme.color(plate, 0.95))
    W.SetText(frame.glyph, nil, glyph)
  end

  -- The rough area marker sits on its own floor only; it is not a position, the tooltip says so.
  local function placeMarker()
    local spec = state.marker
    if not (spec and state.floors > 0 and state.mapW > 0 and (spec.floor == nil or spec.floor == state.floor)) then
      if marker then
        marker:Hide()
      end
      return
    end
    if not marker then
      marker = CreateFrame("Button", nil, map)
      marker:SetSize(MARKER, MARKER)
      marker.plate = marker:CreateTexture(nil, "BACKGROUND")
      marker.plate:SetAllPoints()
      ns.Bind(marker.plate, function(t)
        t:SetColorTexture(Theme.color("surface", 0.75))
      end)
      marker.glyph = W.Text(marker, { text = "~", role = "ui", color = "accent2", justify = "CENTER" })
      marker.glyph:SetPoint("CENTER")
      W.Border(marker, "accent2", 1, 2)
      marker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      marker:SetScript("OnEnter", function(self)
        if state.marker then
          ns.ShowTooltip(self, state.marker.title, state.marker.text)
        end
      end)
      marker:SetScript("OnLeave", ns.HideTooltip)
      -- A click on the marker is a click on the map below it.
      marker:SetScript("OnClick", function(_, button)
        local click = map:GetScript("OnClick")
        if click then
          click(map, button)
        end
      end)
      f.marker = marker
    end
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", map, "TOPLEFT", spec.x * state.mapW, -spec.y * state.mapH)
    marker:Show()
  end

  local function placeAll()
    local geo = state.geo
    for i = 1, geo and f.tilesUsed or 0 do
      local col, row = (i - 1) % geo.cols, math.floor((i - 1) / geo.cols)
      local tex = f.tiles[i]
      -- The last column and row are cut to the visible area, the rest of the tile is empty.
      local cw = math.min(DMV.TILE, geo.w - col * DMV.TILE)
      local ch = math.min(DMV.TILE, geo.h - row * DMV.TILE)
      local sx, sy = state.mapW / geo.w, state.mapH / geo.h
      tex:ClearAllPoints()
      tex:SetPoint("TOPLEFT", map, "TOPLEFT", col * DMV.TILE * sx, -row * DMV.TILE * sy)
      tex:SetSize(cw * sx, ch * sy)
      tex:SetTexCoord(0, cw / DMV.TILE, 0, ch / DMV.TILE)
    end
    for i = 1, f.pinsUsed do
      local frame = f.pinFrames[i]
      frame:ClearAllPoints()
      frame:SetPoint("CENTER", map, "TOPLEFT", frame.pin.x * state.mapW, -frame.pin.y * state.mapH)
    end
    placeMarker()
  end

  -- Release and fill -----------------------------------------------------------------------------

  local function releaseAll()
    for i = 1, f.tilesUsed do
      f.tiles[i]:SetTexture(nil)
      f.tiles[i]:Hide()
    end
    for i = 1, f.pinsUsed do
      local frame = f.pinFrames[i]
      frame.icon:SetTexture(nil)
      frame.pin = nil
      frame:Hide()
    end
    f.tilesUsed, f.pinsUsed = 0, 0
    soon.pic:SetTexture(nil)
  end

  local function infoText(onFloor)
    local names = {}
    for _, p in ipairs(onFloor) do
      if p.kind == "boss" then
        names[#names + 1] = bossLabel(p) or "?"
      end
    end
    local lines = {}
    if #onFloor == 0 then
      lines[1] = L["dmap.pins.none"]
    elseif #names == 0 then
      lines[1] = L["dmap.pins.noBosses"]
    else
      lines[1] = string.format(L["dmap.pins.bosses"], table.concat(names, ", "))
    end
    if state.edit then
      lines[#lines + 1] = L["dmap.editHint"]
    end
    return table.concat(lines, "\n")
  end

  -- The floor entry of the dropdown: the name of the floor when the data has one, else "Floor n".
  local function floorName(n)
    local floor = state.entry and state.entry.floors[n]
    local name = floor and floor.n and ns.T(floor.n)
    return name or string.format(L["dmap.floorN"], n)
  end

  local function paintFloors()
    for i = #floorOptions, 1, -1 do
      floorOptions[i] = nil
    end
    for i = 1, state.floors do
      floorOptions[i] = { value = i, text = floorName(i) }
    end
    floorDrop:SetShown(state.floors > 1)
    floorDrop.Refresh()
  end

  -- The dimmed loading screen of the instance (when there is one) behind the note "map coming soon".
  local function paintSoon()
    local inst = findInstance(state.requested)
    local IV = ns.InstanceView
    local image = inst and IV and IV.LoadingImage(inst) or nil
    soon.image = image
    soon.pic:SetShown(image ~= nil)
    soon.dim:SetShown(image ~= nil)
    soon.pic:SetTexture(image and image.fid or nil)
  end

  function render()
    releaseAll()
    local hasMap = state.floors > 0
    local waiting = not hasMap and state.requested ~= nil
    map:SetShown(hasMap)
    info:SetShown(hasMap)
    soon:SetShown(waiting)
    hint:SetShown(not hasMap and not waiting)
    editToggle:SetShown(hasMap)
    exportButton:SetShown(hasMap)
    importButton:SetShown(hasMap)
    W.SetText(hint, "dmap.noInstance")
    if not hasMap then
      state.geo = nil
      paintFloors()
      if waiting and f:IsVisible() then
        paintSoon()
      end
      return
    end
    pins = P.Pins(state.key)
    local onFloor = {}
    for _, p in ipairs(pins) do
      if p.floor == state.floor then
        onFloor[#onFloor + 1] = p
      end
    end
    local floor = state.entry.floors[state.floor]
    state.geo = DMV.Geometry(floor)
    paintFloors()
    editToggle.Refresh()
    W.SetText(info, nil, infoText(onFloor))
    -- Hidden pages keep no textures, OnShow paints again.
    if not f:IsVisible() then
      return
    end
    for i, id in ipairs(floor.fid) do
      acquireTile():SetTexture(id)
      if i >= state.geo.cols * state.geo.rows then
        break
      end
    end
    for _, p in ipairs(onFloor) do
      f.pinsUsed = f.pinsUsed + 1
      local frame = f.pinFrames[f.pinsUsed]
      if not frame then
        frame = createPin()
        f.pinFrames[f.pinsUsed] = frame
      end
      p.frame = frame
      frame.pin = p
      paintPin(frame, p)
      frame:Show()
    end
    placeAll()
  end

  -- Layout ----------------------------------------------------------------------------------------

  -- Wraps the controls into rows of the given width, returns their height. An item with `low` sits on
  -- the line of the dropdown button when its row holds the (taller) dropdown.
  local function flow(items, width)
    local rows, row, x = {}, nil, 0
    for _, it in ipairs(items) do
      if it.frame:IsShown() then
        if not row or (x > 0 and x + it.w > width) then
          row, x = { h = 0 }, 0
          rows[#rows + 1] = row
        end
        row[#row + 1] = { item = it, x = x }
        row.h = math.max(row.h, it.h)
        x = x + it.w + GAP
      end
    end
    local y = 0
    for _, r in ipairs(rows) do
      for _, cell in ipairs(r) do
        local it = cell.item
        local dy = it.low and math.max(0, r.h - it.h - 4) or 0
        it.frame:ClearAllPoints()
        it.frame:SetPoint("TOPLEFT", f, "TOPLEFT", cell.x, -(y + dy))
        it.frame:SetSize(it.w, it.h)
      end
      y = y + r.h + GAP
    end
    return math.max(0, y - GAP)
  end

  -- Room the picture may take: the host's height limit minus what the widget needs besides the picture.
  local function pictureLimit(used)
    if not f.maxHeight then
      return DMV.MAX_H
    end
    return math.max(DMV.MIN_H, math.min(DMV.MAX_H, f.maxHeight - used))
  end

  -- "Map coming soon": the dimmed loading screen fitted like a map, the note on a plate in the middle.
  local function layoutSoon(width)
    local x0, w, h = DMV.MapSize(width, DMV.Geometry(nil), pictureLimit(0))
    soon:ClearAllPoints()
    soon:SetPoint("TOPLEFT", f, "TOPLEFT", x0, 0)
    soon:SetSize(w, h)
    local image = soon.image
    if image then
      local probe = ns.AssetFiles.cache[image.fid]
      soon.pic:SetTexCoord(ns.InstanceView.Crop(image.src, w, h, probe and probe.w, probe and probe.h))
    end
    soon.text:SetWidth(math.max(1, w - 48))
    local plateW = math.max(1, math.min(w - 16, math.ceil(soon.text:GetStringWidth()) + 32))
    soon.plate:ClearAllPoints()
    soon.plate:SetPoint("CENTER", soon, "CENTER")
    soon.plate:SetSize(plateW, math.ceil(soon.text:GetStringHeight()) + 20)
    soon.text:ClearAllPoints()
    soon.text:SetPoint("TOPLEFT", soon.plate, "TOPLEFT", 16, -10)
    soon.text:SetPoint("BOTTOMRIGHT", soon.plate, "BOTTOMRIGHT", -16, 10)
    return h
  end

  local function layout(width)
    local y
    if state.floors > 0 then
      local items = {
        { frame = floorDrop, w = math.min(DROP_W, width), h = DROP_H },
        { frame = editToggle, w = 170, h = 22, low = true },
        { frame = exportButton, w = 110, h = CTRL_H, low = true },
        { frame = importButton, w = 110, h = CTRL_H, low = true },
      }
      y = flow(items, width) + GAP * 2
      info:SetWidth(width)
      local infoH = info:GetStringHeight()
      local x0, w, h = DMV.MapSize(width, state.geo, pictureLimit(y + GAP + infoH))
      state.mapW, state.mapH = w, h
      map:ClearAllPoints()
      map:SetPoint("TOPLEFT", f, "TOPLEFT", x0, -y)
      map:SetSize(w, h)
      placeAll()
      y = y + h + GAP
      info:ClearAllPoints()
      info:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
      info:SetHeight(infoH)
      y = y + infoH
    elseif state.requested then
      y = layoutSoon(width)
    else
      hint:ClearAllPoints()
      hint:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
      hint:SetWidth(width)
      y = hint:GetStringHeight()
      hint:SetHeight(y)
    end
    f:SetHeight(math.max(1, y))
    return y
  end

  -- The page stack calls this with the width it gives the widget and uses the returned height.
  function f:fgGridLayout(width)
    state.width = width
    return layout(width)
  end

  -- Public ---------------------------------------------------------------------------------------

  local function startFloor()
    for _, p in ipairs(P.Pins(state.key)) do
      if p.kind == "entrance" then
        return p.floor
      end
    end
    return 1
  end

  -- Shows the instance with this DungeonAssets key or English name (no floor: "map coming soon"). Returns
  -- true when it has a map.
  function f:SetInstance(key)
    local entry = key and maps()[key] or nil
    state.requested = key
    state.entry = entry
    state.floors = entry and entry.floors and #entry.floors or 0
    -- Without a floor there is nothing to put pins on.
    state.key = state.floors > 0 and key or nil
    state.bosses = state.key and P.BossList(state.key) or {}
    state.edit = false
    state.marker = nil
    state.floor = state.floors > 0 and startFloor() or 1
    render()
    placeMarker()
    if state.width then
      layout(state.width)
    end
    return state.floors > 0
  end

  function f:SetFloor(n)
    if type(n) ~= "number" or n < 1 or n > state.floors then
      return false
    end
    state.floor = n
    render()
    if state.width then
      layout(state.width)
    end
    return true
  end

  -- spec = { x, y (0..1), floor (optional), title, text } or nil to remove the marker.
  function f:SetMarker(spec)
    state.marker = spec
    placeMarker()
  end

  function f:Refresh()
    render()
    if state.width then
      layout(state.width)
    end
  end

  -- Frames ---------------------------------------------------------------------------------------

  floorOptions = {}
  floorDrop = W.Dropdown(f, {
    key = "dmap.floor",
    options = floorOptions,
    width = DROP_W,
    get = function()
      return state.floor
    end,
    set = function(n)
      f:SetFloor(n)
      if f.onFloorPick then
        f.onFloorPick(n)
      end
      changed()
    end,
  })
  ns.FlowLayout.FitDropdown(floorDrop)
  editToggle = W.Checkbox(f, {
    key = "dmap.edit",
    get = function()
      return state.edit
    end,
    set = function(on)
      state.edit = on
      render()
      changed()
    end,
  })
  exportButton = W.Action(f, {
    label = "act.export",
    icon = "export",
    tooltip = "dmap.export",
    width = 110,
    height = CTRL_H,
    onClick = function()
      PD.Export(state.key)
    end,
  })
  importButton = W.Action(f, {
    label = "act.import",
    icon = "import",
    tooltip = "dmap.import",
    width = 110,
    height = CTRL_H,
    onClick = function()
      PD.Import(function()
        render()
        changed()
      end)
    end,
  })
  map = CreateFrame("Button", nil, f)
  W.Fill(map, "surface", 1)
  map:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  map:SetScript(
    "OnClick",
    ns.Wrap("dmap-map", function(_, button)
      -- A host can take the click (true = used) before the editor sees it.
      if f.onMapClick and f.onMapClick(button, cursorFraction()) then
        return
      end
      if button ~= "LeftButton" or not state.edit or not state.key then
        return
      end
      local x, y = cursorFraction()
      local floor = state.floor
      PD.Choose({ inst = state.key, floor = floor, floors = state.floors }, function(spec)
        place(spec, floor, x, y)
      end)
    end)
  )
  hint = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  info = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  soon = CreateFrame("Frame", nil, f)
  W.Fill(soon, "surface", 1)
  soon.pic = soon:CreateTexture(nil, "ARTWORK")
  soon.pic:SetAllPoints()
  soon.dim = soon:CreateTexture(nil, "OVERLAY")
  soon.dim:SetAllPoints()
  soon.dim:SetColorTexture(0, 0, 0, 0.65)
  soon.plate = CreateFrame("Frame", nil, soon)
  W.Fill(soon.plate, "surface", 0.92)
  W.Border(soon.plate, "accent2", 1, 1)
  soon.text = W.Text(soon.plate, { key = "dmap.soon", role = "h3", color = "text", justify = "CENTER", wrap = true })
  f.map, f.info, f.hint, f.soon, f.floorDrop = map, info, hint, soon, floorDrop
  f.exportButton, f.importButton, f.editToggle = exportButton, importButton, editToggle

  f:SetScript(
    "OnShow",
    ns.Wrap("dmap-show", function()
      render()
      if state.width then
        layout(state.width)
      end
    end)
  )
  f:SetScript(
    "OnHide",
    ns.Wrap("dmap-hide", function()
      releaseAll()
    end)
  )
  render()
  return f
end
