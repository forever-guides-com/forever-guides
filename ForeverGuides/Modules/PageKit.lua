-- Small helpers shared by the data pages (map, classes, trainers, weapons,
-- instances, search): player info, a two-line list, tour button.
local _, ns = ...
local W, Theme, L, R = ns.W, ns.Theme, ns.L, ns.RefLogic

local K = {}
ns.PageKit = K

ns.AddLocale("enUS", {
  ["kit.tourTip"] = "Short tour of this page (Esc skips).",
  ["kit.noData"] = "Data package not loaded, nothing to show. Check /fg diag.",
  ["kit.empty"] = "Nothing found.",
  ["kit.gap"] = "Data gap",
  ["kit.faction.A"] = "Alliance",
  ["kit.faction.H"] = "Horde",
  ["kit.faction.all"] = "Both factions",
  ["kit.filterFaction"] = "Faction",
  ["kit.filterClass"] = "Class",
  ["kit.conf.3"] = "reliable",
  ["kit.conf.2"] = "likely",
  ["kit.conf.1"] = "estimated",
  ["kit.coords"] = "Position %s (percent of zone map)",
  ["kit.view.list"] = "List",
  ["kit.view.cards"] = "Cards",
  ["kit.placeMap"] = "Map",
  ["kit.placeMapTip"] = "Show the place on the map",
  ["kit.placeMarker"] = "Waypoint",
  ["kit.placeMarkerTip"] = "Set a waypoint at the place",
  ["kit.mapSet"] = "Waypoint set for %s, world map opened.",
  ["kit.mapFallbackTitle"] = "Position",
  ["kit.mapFallbackHint"] = "Not marked on the map. Look near these coordinates in the world map.",
})

ns.AddLocale("deDE", {
  ["kit.tourTip"] = "Kurze Führung durch die Seite (Esc überspringt).",
  ["kit.noData"] = "Datenpaket nicht geladen, nichts zu zeigen. Prüfe /fg diag.",
  ["kit.empty"] = "Nichts gefunden.",
  ["kit.gap"] = "Datenlücke",
  ["kit.faction.A"] = "Allianz",
  ["kit.faction.H"] = "Horde",
  ["kit.faction.all"] = "Beide Fraktionen",
  ["kit.filterFaction"] = "Fraktion",
  ["kit.filterClass"] = "Klasse",
  ["kit.conf.3"] = "verlässlich",
  ["kit.conf.2"] = "wahrscheinlich",
  ["kit.conf.1"] = "geschätzt",
  ["kit.coords"] = "Position %s (Prozent der Zonenkarte)",
  ["kit.view.list"] = "Liste",
  ["kit.view.cards"] = "Karten",
  ["kit.placeMap"] = "Karte",
  ["kit.placeMapTip"] = "Ort auf der Karte zeigen",
  ["kit.placeMarker"] = "Marker",
  ["kit.placeMarkerTip"] = "Wegpunkt am Ort setzen",
  ["kit.mapSet"] = "Wegpunkt für %s gesetzt, Weltkarte geöffnet.",
  ["kit.mapFallbackTitle"] = "Position",
  ["kit.mapFallbackHint"] = "Nicht auf der Karte markiert. Suche in der Weltkarte bei diesen Koordinaten.",
})

-- "A", "H" or nil.
function K.PlayerFaction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

function K.PlayerClass()
  local _, class = UnitClass("player")
  return class
end

function K.Coord(x, y)
  if not (x and y) then
    return nil
  end
  return string.format("%.1f, %.1f", x * 100, y * 100)
end

-- Marks a point on the world map for the player. Never errors: the UiMapIDs in
-- the data come from Classic, so any step can be unavailable on this client and
-- the position is then offered as copyable text instead.
-- C_SuperTrack.SetSuperTrackedUserWaypoint is deliberately not used, the
-- client blocks it.
function K.ShowOnMap(mapId, x, y, label)
  label = label or ""
  local function fallback()
    local pos = K.Coord(x, y)
    ns.Dialogs.Copy("kit.mapFallbackTitle", pos and (label .. " " .. pos) or label, "kit.mapFallbackHint")
  end
  local hasInfo, info = false, nil
  if mapId and C_Map and C_Map.GetMapInfo then
    hasInfo, info = pcall(C_Map.GetMapInfo, mapId)
  end
  if
    not (hasInfo and info and x and y)
    or not (C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates)
  then
    return fallback()
  end
  if C_Map.CanSetUserWaypointOnMap then
    local okCan, can = pcall(C_Map.CanSetUserWaypointOnMap, mapId)
    if not (okCan and can) then
      return fallback()
    end
  end
  local set = pcall(function()
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapId, x, y))
  end)
  if not set then
    return fallback()
  end
  if OpenWorldMap then
    pcall(OpenWorldMap, mapId)
  elseif WorldMapFrame then
    pcall(function()
      WorldMapFrame:Show()
      if WorldMapFrame.SetMapID then
        WorldMapFrame:SetMapID(mapId)
      end
    end)
  end
  ns.Notify(string.format(L["kit.mapSet"], label), "success")
end

-- Actions of W.MapActionButtons. A place is { map = UiMapID, x, y, label, zone } (x, y optional
-- fractions of the zone map, zone only names the place in the warning) or a function returning
-- one, so a costly zone lookup only runs on click. Without a map nothing is guessed, the player
-- gets a warning naming the zone.
local function resolvePlace(place)
  if type(place) == "function" then
    place = place()
  end
  if not place then
    return nil
  end
  if not place.map then
    ns.Notify(ns.Waypoints.ErrorText("unknownZone", place.zone or place.label or "?"), "warning")
    return nil
  end
  return place
end

function K.PlaceOnMap(place)
  place = resolvePlace(place)
  if place then
    ns.MapRequest.Open({ map = place.map, x = place.x, y = place.y, label = place.label })
  end
end

function K.PlaceMarker(place)
  place = resolvePlace(place)
  if place then
    ns.Waypoints.Command({ map = place.map, x = place.x, y = place.y, title = place.label })
  end
end

function K.HasData(name)
  return ns.Data and ns.Data[name] ~= nil
end

function K.Anchor(name, frame)
  ns.Anchors[name] = frame
  return frame
end

local ACTION_SIZE = 20
local CURSOR_WIDTH = 3

-- Title of a list row with highlighted spans (byte ranges { from, to } of the title): accent
-- color plus a one pixel underline, so the hit never relies on color alone.
local function paintTitle(row, text, spans, hex)
  row.marks = row.marks or {}
  for _, m in ipairs(row.marks) do
    m:Hide()
  end
  -- hex ("rrggbb"): color of the plain parts of the title, e.g. the quality color of an item name.
  local function tint(part)
    return hex and part ~= "" and ("|cff" .. hex .. part .. "|r") or part
  end
  if not spans or #spans == 0 then
    row.title:SetText(tint(text))
    return
  end
  local parts, at = {}, 1
  for _, r in ipairs(spans) do
    parts[#parts + 1] = tint(text:sub(at, r.from - 1))
    parts[#parts + 1] = Theme.hexText("accent2", text:sub(r.from, r.to))
    at = r.to + 1
  end
  parts[#parts + 1] = tint(text:sub(at))
  row.title:SetText(table.concat(parts))
  if not row.measure then
    row.measure = W.Text(row, { role = "ui" })
    row.measure:Hide()
  end
  local room, height = row.title:GetWidth() or 0, row.title:GetStringHeight()
  for i, r in ipairs(spans) do
    row.measure:SetText(text:sub(1, r.from - 1))
    local x = row.measure:GetStringWidth()
    row.measure:SetText(text:sub(r.from, r.to))
    local w = row.measure:GetStringWidth()
    if room > 0 then
      w = math.min(w, room - x)
    end
    if w > 0 then
      local mark = row.marks[i]
      if not mark then
        mark = row:CreateTexture(nil, "OVERLAY")
        ns.Bind(mark, function(t)
          t:SetColorTexture(Theme.color("accent2"))
        end)
        row.marks[i] = mark
      end
      mark:ClearAllPoints()
      mark:SetPoint("TOPLEFT", row.title, "TOPLEFT", x, -height)
      mark:SetSize(w, 1)
      mark:Show()
    end
  end
end

-- Bar at the left edge of the row that has the keyboard cursor (a second cue besides the tint).
local function paintCursor(row, on)
  if not row.cursor then
    if not on then
      return
    end
    row.cursor = row:CreateTexture(nil, "OVERLAY")
    row.cursor:SetPoint("TOPLEFT")
    row.cursor:SetPoint("BOTTOMLEFT")
    row.cursor:SetWidth(CURSOR_WIDTH)
    ns.Bind(row.cursor, function(t)
      t:SetColorTexture(Theme.color("accent2"))
    end)
  end
  row.cursor:SetShown(on)
end

local function scaledHeight(base)
  return Theme.lineHeight(base)
end
K.scaledHeight = scaledHeight

-- Virtual two-line list. opts: rowHeight, bind(item) -> { title, sub, right,
-- selected, icon, iconPaint, wrapSub, actions, tooltip }, onClick(item).
-- tooltip: literal string shown while the row is hovered. tooltipSpec: a W.Tooltip spec instead
-- (link = "item:ID" shows the client's item tooltip, title is the fallback while it is not cached).
-- marks: byte ranges { from, to } of the title to highlight (accent color and underline).
-- titleHex: "rrggbb" color of the title text (an item name in its quality color).
-- cursor: bar at the left edge for the row of the keyboard cursor. inert: the row is a heading,
-- not clickable and skipped by Tab.
-- icon: full texture path, shown ~20x20 at the row's left with the default
-- icon crop, white tint. iconPaint(texture): for icons that need a custom
-- crop/tint (e.g. the class-circle icon), paints the row's icon texture
-- directly instead, takes precedence over icon when both are set. Neither
-- field reserves left space when absent, so rows without an icon look and
-- lay out exactly as before. wrapSub: word-wraps the sub line for callers
-- whose text can span multiple lines (row height still comes from
-- rowHeight and does not grow, so very long sub text is truncated).
-- actions: up to 4 small icon buttons (W.Action, 20 px) bottom-right of the row (icon: a texture path
-- or the name of an icon of ns.UI_ICONS), each
-- { icon = texture, tooltip = literal string, onClick = fn }; clicking one
-- does not also trigger the row's own onClick (child button consumes the
-- click). Absent/empty reserves no space, same discipline as icon above.
-- An action may also carry boxed (surface and edge, reads as a button), selected (a toggle that
-- is on), tooltipText (second tooltip line) and dim (dimmed and inert, the tooltip says
-- why; it stays focusable so the keyboard user can read the reason).
-- onReorder(item, anchor, after) / canReorder(): drag and drop, see W.ScrollList.
function K.NewList(parent, opts)
  return W.ScrollList(parent, {
    rowHeight = scaledHeight(opts.rowHeight or 40),
    onReorder = opts.onReorder,
    canReorder = opts.canReorder,
    createRow = function(p)
      local row = CreateFrame("Button", nil, p)
      -- Sibling frames don't clip each other in WoW, only a frame clips its
      -- own children. Without this, a row whose wrapSub text runs to more
      -- lines than rowHeight allows bleeds visually into the row below it
      -- instead of just being cropped at its own bottom edge.
      row:SetClipsChildren(true)
      row.bg = row:CreateTexture(nil, "BACKGROUND")
      row.bg:SetAllPoints()
      row.right = W.Text(row, { role = "small", color = "textMuted", justify = "RIGHT" })
      row.right:SetPoint("TOPRIGHT", -8, -6)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(20, 20)
      row.icon:SetPoint("TOPLEFT", 8, -8)
      row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      row.icon:Hide()
      row.title = W.Text(row, { role = "ui" })
      row.title:SetPoint("TOPLEFT", 8, -5)
      row.title:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
      row.sub = W.Text(row, { role = "small", color = "textSecondary" })
      row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
      row.actions = {}
      local prevAction
      for i = 1, 4 do
        -- A pooled W.Action: the icon, variant and tooltip change with every bind.
        local b = W.Action(row, { icon = "close", variant = "icon", size = ACTION_SIZE, manual = true })
        if prevAction then
          b:SetPoint("RIGHT", prevAction, "LEFT", -4, 0)
        else
          b:SetPoint("BOTTOMRIGHT", -6, 4)
        end
        -- A raw texture (item or spell icon) instead of an icon of the set.
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 3, -3)
        b.tex:SetPoint("BOTTOMRIGHT", -3, 3)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.tex:Hide()
        local function showTip()
          if b.tip then
            ns.ShowTooltip(b, b.tip, b.tipText)
          end
        end
        b.fgName = function()
          return b.tip
        end
        b:HookScript("OnEnter", showTip)
        b:HookScript("OnLeave", ns.HideTooltip)
        b.fgOnFocus, b.fgOnBlur = showTip, ns.HideTooltip
        b:SetScript(
          "OnClick",
          ns.Wrap("list-row-action", function()
            if b.fn then
              b.fn()
            end
          end)
        )
        b:Hide()
        row.actions[i] = b
        prevAction = b
      end
      row.line = row:CreateTexture(nil, "ARTWORK")
      row.line:SetPoint("BOTTOMLEFT")
      row.line:SetPoint("BOTTOMRIGHT")
      row.line:SetHeight(1)
      local function paint()
        local selected = row.selected
        row.bg:SetColorTexture(1, 1, 1, selected and 0.1 or (row.hover and 0.05 or 0))
        row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
      end
      row.paint = paint
      ns.Bind(row, paint)
      -- tipSpec (a W.Tooltip spec, e.g. an item link) wins over the plain tip string.
      local function showTip()
        if row.tipSpec then
          W.Tooltip.Show(row, row.tipSpec)
        elseif row.tip then
          ns.ShowTooltip(row, row.tip)
        end
      end
      row:SetScript("OnEnter", function()
        row.hover = true
        paint()
        showTip()
      end)
      row:SetScript("OnLeave", function()
        row.hover = false
        paint()
        if row.tip or row.tipSpec then
          ns.HideTooltip()
        end
      end)
      row:SetScript(
        "OnClick",
        ns.Wrap("list-row", function()
          if opts.onClick and row.item and not row.fgDragged then
            opts.onClick(row.item)
          end
        end)
      )
      ns.Focus.register(row, function(self)
        self:Click()
      end)
      return row
    end,
    bindRow = function(row, item)
      local t = opts.bind(item)
      row.item = item
      row.tip, row.tipSpec = t.tooltip, t.tooltipSpec
      row.selected = t.selected
      if t.iconPaint then
        t.iconPaint(row.icon)
        row.icon:Show()
      elseif t.icon then
        row.icon:SetTexture(t.icon)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon:SetVertexColor(1, 1, 1)
        row.icon:Show()
      else
        row.icon:Hide()
      end
      row.title:ClearAllPoints()
      row.title:SetPoint("TOPLEFT", (t.iconPaint or t.icon) and 36 or 8, -5)
      row.title:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
      local actions = t.actions or {}
      local shown, reserve = 0, 4
      for i, b in ipairs(row.actions) do
        local a = actions[i]
        if a then
          local size = ACTION_SIZE
          b:SetVariant(a.boxed and "boxed" or "icon")
          b:SetSelected(a.selected)
          if a.icon and ns.UI_ICONS[a.icon] then
            b.tex:Hide()
            b.icon:Show()
            b:SetIcon(a.icon)
          else
            b.icon:Hide()
            b.tex:SetTexture(a.icon)
            b.tex:Show()
          end
          b:SetSize(size, size)
          b:SetAlpha(a.dim and 0.45 or 1)
          b.tip, b.tipText = a.tooltip, a.tooltipText
          b.fn = not a.dim and a.onClick or nil
          b:Show()
          shown = shown + 1
          reserve = reserve + size + 4
        else
          b:Hide()
          b.tip, b.tipText, b.fn = nil, nil, nil
        end
      end
      row.sub:ClearAllPoints()
      row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
      row.sub:SetPoint("RIGHT", -8 - (shown > 0 and reserve or 0), 0)
      if row.sub.SetWordWrap then
        row.sub:SetWordWrap(t.wrapSub == true)
      end
      paintTitle(row, t.title or "", t.marks, t.titleHex)
      paintCursor(row, t.cursor == true)
      if (row.fgInert == true) ~= (t.inert == true) then
        row.fgInert = t.inert == true
        row:SetEnabled(not row.fgInert)
      end
      row.sub:SetText(t.sub or "")
      row.right:SetText(t.right or "")
      row.paint()
    end,
  })
end

-- Small List/Cards view toggle shared by pages that offer both a compact
-- K.NewList and a K.GridPool card grid for the same data. opts: get() ->
-- "list"|"cards", set(view). Selection is shown with the same accent ring
-- as the choice buttons below, never by color alone. Other two-way switches
-- pass views = { a, b } and keyPrefix (label key = keyPrefix .. view).
function K.ViewToggle(parent, opts)
  local gap = 4
  local width = 76
  local views = opts.views or { "list", "cards" }
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize((width + gap) * #views - gap, 22)
  local rings = {}
  local prev
  for _, view in ipairs(views) do
    local btn = W.Button(f, {
      key = (opts.keyPrefix or "kit.view.") .. view,
      variant = "ghost",
      width = width,
      height = 22,
      onClick = function()
        opts.set(view)
      end,
    })
    btn:SetPoint("LEFT", prev or f, prev and "RIGHT" or "LEFT", prev and gap or 0, 0)
    rings[view] = W.Border(btn, "accent2", 1, 2)
    rings[view].show(false)
    prev = btn
  end
  function f.Refresh()
    local current = opts.get()
    for view, ring in pairs(rings) do
      ring.show(view == current)
    end
  end
  f.Refresh()
  return f
end

-- Choice buttons ---------------------------------------------------------------
-- One look for every class, race and faction choice in the addon: compact
-- buttons that keep their content width and wrap into rows (never stretch).
-- Content is a check slot, the icon and the name. The selected button carries a
-- colored 2 px border, the check mark and a light tint of the same color, so the
-- state never relies on color alone. Hover and keyboard focus (ns.Focus) as for
-- every other button. Builders: K.ChoiceButton (one button), K.ChoiceGroup (a
-- wrapping row of them) and on top of it K.ClassButtons, K.FactionButtons,
-- K.RaceButtons and the combined K.FactionRaceSelector.

-- Faction crest icons. The names are taken from the website's own faction
-- icon assets and are not verified in this client yet, spot-check in game.
K.FACTION_CREST = {
  A = "Interface\\Icons\\INV_Misc_Tournaments_symbol_human",
  H = "Interface\\Icons\\INV_Misc_Tournaments_symbol_orc",
}

K.SKYBORNE_ICON = "Interface\\AddOns\\ForeverGuides\\Media\\race_skyborne.png"
K.CLASS_ICON_SHEET = "Interface\\TargetingFrame\\UI-Classes-Circles"
K.RACE_ICON_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races"

-- Race slug (Data.Races, WeaponRaces, RaceClasses) to its icon source:
-- atlas = name part of the client atlas "raceicon-<atlas>-<gender>" (see
-- GetRaceAtlas in the client's SharedUtils), sheet = row key of the
-- UI-CharacterCreate-Races texture sheet, file = icon shipped with the addon.
-- The two Skyborne races are new in Forever and have no race icon in any
-- classic or retail asset, they share the icon of the website (Media folder).
K.RACE_ICONS = {
  ["human"] = { atlas = "human", sheet = "HUMAN" },
  ["dwarf"] = { atlas = "dwarf", sheet = "DWARF" },
  ["night-elf"] = { atlas = "nightelf", sheet = "NIGHTELF" },
  ["gnome"] = { atlas = "gnome", sheet = "GNOME" },
  ["orc"] = { atlas = "orc", sheet = "ORC" },
  ["undead"] = { atlas = "undead", sheet = "SCOURGE" },
  ["tauren"] = { atlas = "tauren", sheet = "TAUREN" },
  ["troll"] = { atlas = "troll", sheet = "TROLL" },
  ["high-order-skyborne"] = { file = K.SKYBORNE_ICON },
  ["windshaper-skyborne"] = { file = K.SKYBORNE_ICON },
}

-- Standard 4x4 layout of the race sheet: male in the left half, female in the
-- right half, four races per column.
local RACE_SHEET_COORDS = {}
for column, races in ipairs({ { "HUMAN", "DWARF", "GNOME", "NIGHTELF" }, { "TAUREN", "SCOURGE", "TROLL", "ORC" } }) do
  for row, race in ipairs(races) do
    for half, gender in ipairs({ "MALE", "FEMALE" }) do
      local left = (column - 1 + (half - 1) * 2) * 0.25
      RACE_SHEET_COORDS[race .. "_" .. gender] = { left, left + 0.25, (row - 1) * 0.25, row * 0.25 }
    end
  end
end

-- Button anatomy: padding, icon slot (always 20 px wide, whatever the icon is),
-- 4 px, label, padding. The 2 px selected border is drawn inside the button, so
-- the padding is wider than the border. One gap for both directions between
-- the buttons of a group.
local CHOICE_ICON = 20
local CHOICE_PAD = 6
local CHOICE_ICON_GAP = 4
local CHOICE_CHECK = 12
local CHOICE_CHROME = CHOICE_PAD * 2 + CHOICE_ICON + CHOICE_ICON_GAP
local CHOICE_GAP = 6
local CREST_CROP = { 0.08, 0.92, 0.08, 0.92 }

local function luminance(r, g, b)
  local function lin(c)
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end

-- The color moved towards white (dark background) or black (light background)
-- until it reaches minRatio against the Theme color `background`.
function K.ContrastColor(r, g, b, background, minRatio)
  local bl = luminance(Theme.rgb(background or "surface"))
  local target = bl < 0.5 and 1 or 0
  for step = 0, 10 do
    local t = step / 10
    local cr, cg, cb = r + (target - r) * t, g + (target - g) * t, b + (target - b) * t
    local l = luminance(cr, cg, cb)
    if (math.max(l, bl) + 0.05) / (math.min(l, bl) + 0.05) >= (minRatio or 3) then
      return cr, cg, cb
    end
  end
  return target, target, target
end

local function toHex(r, g, b)
  return string.format("#%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Class color as "#rrggbb": the client's own class color, the theme's table
-- when the client has none, moved to at least 3:1 (non-text contrast) against
-- the button surface.
function K.ClassColorHex(class)
  local color = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
  color = color or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
  local r, g, b
  if
    type(color) == "table"
    and type(color.r) == "number"
    and type(color.g) == "number"
    and type(color.b) == "number"
  then
    r, g, b = color.r, color.g, color.b
  else
    r, g, b = Theme.rgb(class)
  end
  return toHex(K.ContrastColor(r, g, b, "surface", 3))
end

local function playerGender()
  local sex = UnitSex and UnitSex("player")
  return sex == 3 and "female" or "male"
end

local function atlasKnown(name)
  local get = C_Texture and C_Texture.GetAtlasInfo
  if not get then
    return false
  end
  local ok, info = pcall(get, name)
  return ok and info ~= nil
end

-- Without a file lookup in the client the sheet cannot be told from a missing
-- file (which renders as a green square), so it is not used then.
local function fileKnown(path)
  local get = (C_Texture and C_Texture.GetFileIDFromPath) or GetFileIDFromPath
  if not get then
    return false
  end
  local ok, id = pcall(get, path)
  return ok and id ~= nil
end

local function firstLetter(text)
  return (tostring(text or "?"):match("[%z\1-\127\194-\244][\128-\191]*") or "?"):upper()
end

local function badgeSpec(text, color)
  return { kind = "badge", letter = firstLetter(text), color = color }
end

-- Icon specs: { kind = "sheet", texture, coords } | { kind = "atlas", atlas } |
-- { kind = "texture", texture } | { kind = "split", left, right } |
-- { kind = "badge", letter, color }. The badge is the last resort, so a button
-- never ends up with an empty icon.
function K.ClassIconSpec(class)
  local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if coords then
    return { kind = "sheet", texture = K.CLASS_ICON_SHEET, coords = coords }
  end
  return badgeSpec(R.className(class), K.ClassColorHex(class))
end

local function crestSpec(side)
  return { kind = "texture", texture = K.FACTION_CREST[side] }
end

-- "A" or "H": the crest. "all": both crests, half each.
function K.FactionIconSpec(value)
  if value == "all" then
    return { kind = "split", left = crestSpec("A"), right = crestSpec("H") }
  end
  return crestSpec(value)
end

-- Order of resolution: client atlas (only when the client has it), the race
-- sheet (only when the client can tell the file exists), the shipped icon for
-- races without a client icon, the letter badge.
function K.RaceIconSpec(slug, side, name)
  local info = K.RACE_ICONS[slug]
  if info and info.atlas then
    local gender = playerGender()
    local atlas = "raceicon-" .. info.atlas .. "-" .. gender
    if atlasKnown(atlas) then
      return { kind = "atlas", atlas = atlas }
    end
    local key = info.sheet .. "_" .. gender:upper()
    local coords = (RACE_ICON_TCOORDS and RACE_ICON_TCOORDS[key]) or RACE_SHEET_COORDS[key]
    if coords and fileKnown(K.RACE_ICON_SHEET) then
      return { kind = "sheet", texture = K.RACE_ICON_SHEET, coords = coords }
    end
  elseif info and info.file then
    return { kind = "texture", texture = info.file }
  end
  return badgeSpec(name or slug, side == "H" and "horde" or side == "A" and "alliance" or "accent2")
end

local function paintIcon(btn, spec)
  btn.iconSpec = spec
  local icon, icon2 = btn.icon, btn.icon2
  icon:ClearAllPoints()
  icon:SetPoint("LEFT", btn.slot, "LEFT")
  icon:SetSize(CHOICE_ICON, CHOICE_ICON)
  icon:SetVertexColor(1, 1, 1)
  icon:Show()
  icon2:Hide()
  btn.badge:Hide()
  btn.badgeText:Hide()
  btn.outline:Hide()
  local kind = spec.kind
  if kind == "atlas" then
    icon:SetAtlas(spec.atlas)
  elseif kind == "sheet" then
    icon:SetTexture(spec.texture)
    icon:SetTexCoord(unpack(spec.coords))
  elseif kind == "texture" then
    icon:SetTexture(spec.texture)
    icon:SetTexCoord(unpack(CREST_CROP))
    btn.outline:Show()
  elseif kind == "split" then
    local half = CHOICE_ICON / 2
    icon:SetSize(half, CHOICE_ICON)
    icon:SetTexture(spec.left.texture)
    icon:SetTexCoord(0.08, 0.5, 0.08, 0.92)
    icon2:ClearAllPoints()
    icon2:SetPoint("LEFT", icon, "RIGHT", 0, 0)
    icon2:SetSize(half, CHOICE_ICON)
    icon2:SetTexture(spec.right.texture)
    icon2:SetTexCoord(0.5, 0.92, 0.08, 0.92)
    icon2:Show()
    btn.outline:Show()
  else
    icon:Hide()
    local r, g, b = Theme.rgb(spec.color or "accent2")
    btn.badge:SetColorTexture(r, g, b, 1)
    btn.badge:Show()
    btn.badgeText:SetText(spec.letter or "?")
    W.SetColor(btn.badgeText, luminance(r, g, b) > 0.35 and "bg" or "text")
    btn.badgeText:Show()
  end
end

-- The parts of an icon on `owner`: a fixed-size slot (the caller anchors it),
-- icon, second icon (split crest), letter badge and the thin dark outline.
-- Everything sits inside the slot, so a label next to the slot never overlaps.
local function newIconSlot(owner)
  owner.slot = owner:CreateTexture(nil, "ARTWORK")
  owner.slot:SetSize(CHOICE_ICON, CHOICE_ICON)
  -- Thin dark outline for square icons (crests), the class circles and race
  -- atlases are shaped already.
  owner.outline = owner:CreateTexture(nil, "BORDER")
  owner.outline:SetColorTexture(0, 0, 0, 0.6)
  owner.outline:SetPoint("TOPLEFT", owner.slot, "TOPLEFT", -1, 1)
  owner.outline:SetPoint("BOTTOMRIGHT", owner.slot, "BOTTOMRIGHT", 1, -1)
  owner.icon = owner:CreateTexture(nil, "ARTWORK")
  owner.icon2 = owner:CreateTexture(nil, "ARTWORK")
  owner.badge = owner:CreateTexture(nil, "ARTWORK")
  owner.badge:SetPoint("TOPLEFT", owner.slot, "TOPLEFT")
  owner.badge:SetSize(CHOICE_ICON, CHOICE_ICON)
  owner.badgeText = W.Text(owner, { role = "micro", color = "bg", justify = "CENTER" })
  owner.badgeText:SetPoint("CENTER", owner.badge, "CENTER")
end

-- A plain 20 px icon (class, faction or race, see the icon spec functions) for
-- places that are not choice buttons, e.g. the headers of the class cards.
function K.IconSlot(parent, spec)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(CHOICE_ICON, CHOICE_ICON)
  newIconSlot(holder)
  holder.slot:SetPoint("TOPLEFT")
  paintIcon(holder, spec)
  return holder
end

-- One choice button. o: label (text), labelColor (Theme token, default "text"),
-- ring (Theme token or "#rrggbb" of the selected border), idleRing (same for the
-- thin idle border, default a faint white), icon (icon spec),
-- onClick, tooltip (optional text). Methods: SetSelected(bool), Measure(width)
-- -> width, height at the button's natural size (never above width; a name
-- wider than the page wraps).
function K.ChoiceButton(parent, o)
  local btn = CreateFrame("Button", nil, parent)
  W.Fill(btn, "surface", 1)
  btn.tint = btn:CreateTexture(nil, "BACKGROUND")
  btn.tint:SetAllPoints()
  btn.tint:Hide()
  ns.Bind(btn, function()
    local r, g, b = Theme.rgb(o.ring or "accent2")
    btn.tint:SetColorTexture(r, g, b, 0.18)
  end)
  local hover = btn:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.08)
  -- Class buttons keep a thin border in their class color while idle.
  btn.ringOff = W.Border(btn, o.idleRing or "white", o.idleRing and 0.7 or 0.25, 1)
  btn.ringOn = W.Border(btn, o.ring or "accent2", 1, 2)
  btn.ringOn.show(false)
  newIconSlot(btn)
  btn.slot:SetPoint("LEFT", btn, "LEFT", CHOICE_PAD, 0)
  -- Check mark over the lower right corner of the icon slot (on a dark chip,
  -- so it reads on every icon), it takes no room of its own.
  btn.checkBack = btn:CreateTexture(nil, "OVERLAY")
  btn.checkBack:SetColorTexture(0, 0, 0, 0.7)
  btn.checkBack:SetSize(CHOICE_CHECK, CHOICE_CHECK)
  btn.checkBack:SetPoint("BOTTOMRIGHT", btn.slot, "BOTTOMRIGHT", 3, -3)
  btn.checkBack:Hide()
  btn.check = W.CheckMark(btn, CHOICE_CHECK, "text")
  btn.check:SetPoint("CENTER", btn.checkBack, "CENTER")
  btn.check:Hide()
  btn.label = W.Text(btn, { text = o.label, role = "ui", color = o.labelColor or "text", wrap = true })
  btn.label:SetPoint("LEFT", btn.slot, "RIGHT", CHOICE_ICON_GAP, 0)
  paintIcon(btn, o.icon)
  btn:SetScript("OnClick", ns.Wrap("choice-button", o.onClick))
  if o.tooltip then
    btn:SetScript("OnEnter", function()
      ns.ShowTooltip(btn, o.tooltip)
    end)
    btn:SetScript("OnLeave", ns.HideTooltip)
  end
  ns.Focus.register(btn, function(self)
    self:Click()
  end)

  function btn:SetSelected(selected)
    self.selected = selected
    self.ringOff.show(not selected)
    self.ringOn.show(selected)
    self.check:SetShown(selected)
    self.checkBack:SetShown(selected)
    self.tint:SetShown(selected)
  end

  function btn:Measure(width)
    self.label:SetWidth(0)
    local w = math.min(width, CHOICE_CHROME + math.ceil(self.label:GetStringWidth()))
    self.label:SetWidth(math.max(1, w - CHOICE_CHROME))
    self.contentWidth = w
    return w, math.max(scaledHeight(28), math.ceil(self.label:GetStringHeight()) + 10)
  end
  return btn
end

-- Wrapping row of choice buttons. o: items (list of { value, label, labelColor,
-- ring, icon, tooltip, group }), get() -> current value, click(value) (what a
-- click does), labelKey (optional caption above the buttons), isShown(item)
-- (optional, hides single buttons), a button whose item has another `group` than
-- the previous shown one starts a new line. Lays itself out through
-- fgGridLayout(width), so it works inside a page Stack and reflows on window
-- resize; every child hangs off the group's own frame.
function K.ChoiceGroup(parent, o)
  local f = CreateFrame("Frame", nil, parent)
  local caption = o.labelKey and W.Text(f, { key = o.labelKey, role = "ui" }) or nil
  if caption then
    caption:SetPoint("TOPLEFT")
  end
  local buttons = {}
  for _, item in ipairs(o.items) do
    local btn = K.ChoiceButton(f, {
      label = item.label,
      labelColor = item.labelColor,
      ring = item.ring,
      idleRing = item.idleRing,
      icon = item.icon,
      tooltip = item.tooltip,
      onClick = function()
        o.click(item.value)
      end,
    })
    btn.value, btn.item, btn.slug, btn.side = item.value, item, item.slug, item.side
    buttons[#buttons + 1] = btn
  end

  function f.Refresh()
    local current = o.get()
    for _, btn in ipairs(buttons) do
      btn:SetShown(not o.isShown or o.isShown(btn.item))
      btn:SetSelected(btn.value == current)
    end
  end

  function f:fgGridLayout(width)
    local y = 0
    if caption then
      y = math.ceil(caption:GetStringHeight()) + 4
    end
    local cx, rowH, lastGroup = 0, 0, nil
    for _, btn in ipairs(buttons) do
      local item = btn.item
      local show = not o.isShown or o.isShown(item)
      btn:SetShown(show)
      if show then
        local w, h = btn:Measure(width)
        if cx > 0 and (cx + w > width or item.group ~= lastGroup) then
          cx, y, rowH = 0, y + rowH + CHOICE_GAP, 0
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", cx, -y)
        btn:SetSize(w, h)
        cx = cx + w + CHOICE_GAP
        rowH = math.max(rowH, h)
        lastGroup = item.group
      end
    end
    local height = y + rowH
    f:SetHeight(math.max(1, height))
    return height
  end

  f.buttons = buttons
  f.Refresh()
  return f
end

-- Class choice, one button per class with the class icon and the class color as
-- selected border. opts: get() -> class token, set(token), labelKey (default
-- "kit.filterClass", false = no caption).
function K.ClassButtons(parent, opts)
  local items = {}
  for _, class in ipairs(R.CLASSES) do
    items[#items + 1] = {
      value = class,
      label = R.className(class),
      ring = K.ClassColorHex(class),
      idleRing = K.ClassColorHex(class),
      icon = K.ClassIconSpec(class),
    }
  end
  return K.ChoiceGroup(parent, {
    items = items,
    get = opts.get,
    click = opts.set,
    labelKey = opts.labelKey == nil and "kit.filterClass" or opts.labelKey or nil,
  })
end

local FACTION_RING = { A = "alliance", H = "horde", all = "accent2" }
local FACTION_VALUES = { "A", "H", "all" }

-- Faction choice (Alliance, Horde, optionally both) with the crest as icon, the
-- faction color as label and as selected border. opts: get() -> "A"|"H"|"all",
-- set(value), withAll (bool, adds "both factions"), labelKey (default
-- "kit.filterFaction", false = no caption).
function K.FactionButtons(parent, opts)
  local items = {}
  for _, value in ipairs(FACTION_VALUES) do
    if value ~= "all" or opts.withAll then
      items[#items + 1] = {
        value = value,
        label = L["kit.faction." .. value],
        labelColor = value == "all" and "text" or FACTION_RING[value],
        ring = FACTION_RING[value],
        icon = K.FactionIconSpec(value),
      }
    end
  end
  return K.ChoiceGroup(parent, {
    items = items,
    get = opts.get,
    click = opts.set,
    labelKey = opts.labelKey == nil and "kit.filterFaction" or opts.labelKey or nil,
  })
end

-- Race choice with the race icon (see K.RaceIconSpec), the races of one faction
-- on their own line. opts: races (list of { f = "A"|"H", n = { de, en }, s =
-- slug } as in WeaponRaces, or { f, n, slug } as in Data.Races), get() -> slug,
-- set(slug|nil), clearable (a second click on the selected race clears it),
-- isShown(race) (optional filter).
function K.RaceButtons(parent, opts)
  local items = {}
  for _, race in ipairs(opts.races or {}) do
    local slug = race.s or race.slug
    local name = ns.T(race.n)
    items[#items + 1] = {
      value = slug,
      label = name,
      ring = "accent2",
      icon = K.RaceIconSpec(slug, race.f, name),
      group = race.f,
      side = race.f,
      slug = slug,
    }
  end
  return K.ChoiceGroup(parent, {
    items = items,
    get = opts.get,
    isShown = opts.isShown,
    click = function(slug)
      if opts.clearable and opts.get() == slug then
        opts.set(nil)
      else
        opts.set(slug)
      end
    end,
  })
end

-- Stacks the shown children of `host` under each other, each at the full width,
-- and returns the total height. Children are frames with fgGridLayout(width).
function K.StackLayout(host, children, width, gap)
  local y = 0
  for _, child in ipairs(children) do
    if child:IsShown() then
      child:ClearAllPoints()
      child:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
      child:SetWidth(width)
      y = y + child:fgGridLayout(width) + gap
    end
  end
  local height = math.max(1, y - gap)
  host:SetHeight(height)
  return height
end

-- Faction and race picker of the weapon masters page: the faction buttons
-- (Alliance, Horde, Both factions) with the race buttons of the selected faction
-- wrapped below. opts: races, getFaction()/setFaction("A"|"H"|"all"),
-- getRace()/setRace(slug|nil), optional raceAllowed(slug) to hide races the page
-- cannot use (nil = all). Clicking the selected race again clears it.
function K.FactionRaceSelector(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  local heads = K.FactionButtons(f, {
    withAll = true,
    labelKey = false,
    get = opts.getFaction,
    set = opts.setFaction,
  })
  local races = K.RaceButtons(f, {
    races = opts.races,
    clearable = true,
    get = opts.getRace,
    set = opts.setRace,
    -- Only the allowed races of the selected faction are shown.
    isShown = function(item)
      local faction = opts.getFaction()
      return (faction == "all" or faction == item.side) and (not opts.raceAllowed or opts.raceAllowed(item.slug))
    end,
  })
  function f.Refresh()
    heads.Refresh()
    races.Refresh()
  end
  function f:fgGridLayout(width)
    return K.StackLayout(f, { heads, races }, width, CHOICE_GAP)
  end
  f.heads, f.races = heads.buttons, races.buttons
  return f
end

-- Small confidence marker (data reliability: 3=reliable, 2=likely, else
-- estimated), replacing the old inline "kit.conf.*" text. The word itself
-- lives in the tooltip so the information never depends on color alone.
function K.ConfidenceDot(parent, cf)
  local f = CreateFrame("Button", nil, parent)
  f:SetSize(12, 12)
  f.cf = cf
  local dot = f:CreateTexture(nil, "ARTWORK")
  dot:SetPoint("TOPLEFT", 1, -1)
  dot:SetPoint("BOTTOMRIGHT", -1, 1)
  W.Border(f, "white", 0.4)
  local function paint()
    local colorName = f.cf == 3 and "success" or f.cf == 2 and "warning" or "textMuted"
    dot:SetColorTexture(Theme.color(colorName))
  end
  ns.Bind(f, paint)
  f:SetScript("OnEnter", function()
    ns.ShowTooltip(f, L["kit.conf." .. tostring(f.cf or 2)])
  end)
  f:SetScript("OnLeave", ns.HideTooltip)
  function f:SetCf(newCf)
    f.cf = newCf
    paint()
  end
  return f
end

-- W.Grid with pooled card frames: :Sync(list, paint) reuses one card per
-- list index across refreshes instead of leaking a fresh set of frames
-- every time a filter changes the result count. makeCard(parent) -> card.
-- Cards are parented to the grid frame itself (not the caller's outer
-- container): WoW only cascades Hide()/SetShown(false) down the real
-- frame parent chain, so cards parented to the outer container would
-- stay visible and float over whatever is shown next to a hidden grid.
function K.GridPool(parent, cardHeight, makeCard, gap)
  local pool, active = {}, {}
  local grid = W.Grid(parent, active, cardHeight, gap)
  function grid:Sync(list, paint)
    for i, item in ipairs(list) do
      local card = pool[i]
      if not card then
        card = makeCard(grid)
        pool[i] = card
      end
      paint(card, item)
      card:Show()
      active[i] = card
    end
    for i = #list + 1, #pool do
      pool[i]:Hide()
    end
    for i = #active, #list + 1, -1 do
      active[i] = nil
    end
  end
  return grid
end

-- Pooled list of rows whose height depends on their content, the variable-height
-- sibling of K.GridPool. makeRow(parent) -> row frame that defines
-- row:fgLayout(width) -> height: it positions its children, sets the width of
-- wrapped FontStrings before reading GetStringHeight (anchor-derived widths are
-- not resolved in the same frame) and returns its own height.
-- :Sync(list, paint) reuses one row per list index and calls paint(row, item).
-- Rows hang off the pool's own frame, so hiding the pool hides them too.
-- fgGridLayout(width) stacks the active rows and returns the total height.
function K.RowPool(parent, makeRow)
  local pool, active = {}, {}
  local list = CreateFrame("Frame", nil, parent)
  function list:Sync(items, paint)
    for i, item in ipairs(items) do
      local row = pool[i]
      if not row then
        row = makeRow(list)
        pool[i] = row
      end
      paint(row, item)
      row:Show()
      active[i] = row
    end
    for i = #items + 1, #pool do
      pool[i]:Hide()
    end
    for i = #active, #items + 1, -1 do
      active[i] = nil
    end
  end
  function list:fgGridLayout(width)
    local y = 0
    for _, row in ipairs(active) do
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
      row:SetWidth(width)
      local h = row:fgLayout(width)
      row:SetHeight(h)
      y = y + h
    end
    list:SetHeight(y)
    return y
  end
  return list
end

-- Wrapping row of small icon chips (icon, name, muted meta text) for compact
-- overviews. :SetChips(list) takes { icon, name, meta, sid } entries and reuses
-- pooled Button frames; :Layout(width) places them left to right, breaks to a
-- new line when the next chip does not fit and returns the total height.
-- FontStrings here do not wrap, so chip widths come from GetStringWidth.
-- Hovering shows the spell tooltip when a spell id is set, else name and meta;
-- an optional tip is added as a last line.
-- Chips are parented to the row frame itself so hiding the row hides them.
local CHIP_ICON = 20
local CHIP_PAD = 6
local CHIP_GAP_X = 14
local CHIP_GAP_Y = 6

local function showChipTooltip(chip)
  local d = chip.data
  if not d then
    return
  end
  -- The spell tooltip heads it and the tip follows; without a spell, name and meta take over.
  if d.sid and W.Tooltip.Show(chip, { spell = d.sid, text = d.tip }) then
    return
  end
  ns.ShowTooltip(chip, d.name, d.tip and (d.meta .. "\n" .. d.tip) or d.meta)
end

local DEFAULT_CHIP_COLORS = { name = "text", meta = "textMuted", hover = { 1, 1, 1, 0.08 } }

local function newChip(parent, colors)
  local chip = CreateFrame("Button", nil, parent)
  local hover = chip:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(unpack(colors.hover))
  chip.icon = chip:CreateTexture(nil, "ARTWORK")
  chip.icon:SetSize(CHIP_ICON, CHIP_ICON)
  chip.icon:SetPoint("LEFT", CHIP_PAD, 0)
  chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  chip.name = W.Text(chip, { role = "ui", color = colors.name })
  chip.name:SetPoint("LEFT", chip.icon, "RIGHT", 6, 0)
  chip.meta = W.Text(chip, { role = "micro", color = colors.meta })
  chip.meta:SetPoint("LEFT", chip.name, "RIGHT", 6, 0)
  chip:SetScript("OnEnter", showChipTooltip)
  chip:SetScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(chip, function() end)
  return chip
end

-- colors: optional { name, meta (Theme tokens), hover = { r, g, b, a } } for chips on a light background.
function K.ChipRow(parent, colors)
  local row = CreateFrame("Frame", nil, parent)
  local pool, shown = {}, 0
  colors = colors or DEFAULT_CHIP_COLORS

  function row:SetChips(list)
    for i, d in ipairs(list) do
      local chip = pool[i]
      if not chip then
        chip = newChip(row, colors)
        pool[i] = chip
      end
      chip.data = d
      chip.icon:SetTexture(d.icon)
      chip.name:SetText(d.name or "")
      chip.meta:SetText(d.meta or "")
      chip:Show()
    end
    for i = #list + 1, #pool do
      pool[i].data = nil
      pool[i]:Hide()
    end
    shown = #list
  end

  function row:Layout(width)
    local chipH = scaledHeight(CHIP_ICON + 4)
    local x, y = 0, 0
    for i = 1, shown do
      local chip = pool[i]
      -- Measure unconstrained, then cap the name so one long chip cannot
      -- overflow the row.
      chip.name:SetWidth(0)
      local nameW = math.ceil(chip.name:GetStringWidth())
      chip.meta:SetWidth(0)
      local metaW = 0
      if (chip.data.meta or "") ~= "" then
        -- Inline textures (coin icons) get a little slack in case a measure misses them.
        metaW = math.ceil(chip.meta:GetStringWidth()) + 2 * select(2, chip.data.meta:gsub("|T", ""))
      end
      local fixed = CHIP_PAD + CHIP_ICON + 6 + CHIP_PAD
      local w = fixed + nameW + (metaW > 0 and metaW + 6 or 0)
      if w > width then
        w = math.max(fixed + 20, width)
        local nameRoom = math.max(20, math.min(nameW, w - fixed - (metaW > 0 and metaW + 6 or 0)))
        chip.name:SetWidth(nameRoom)
        if metaW > 0 then
          -- Too narrow even alone: the meta text shrinks instead of leaving the row.
          chip.meta:SetWidth(math.max(20, math.min(metaW, w - fixed - nameRoom - 6)))
        end
      end
      if x > 0 and x + w > width then
        x, y = 0, y + chipH + CHIP_GAP_Y
      end
      chip:ClearAllPoints()
      chip:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
      chip:SetSize(w, chipH)
      x = x + w + CHIP_GAP_X
    end
    local height = shown > 0 and (y + chipH) or 0
    row:SetHeight(height)
    return height
  end

  return row
end
