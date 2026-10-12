-- Place list of the map page side column: one card per place (symbol, name, kind, zone, a
-- stripe in the faction color) with the actions Start, Goal, arrow and "show on map". The
-- list is a W.ScrollList, so only the visible cards exist. Hover is shared with the pins on
-- the map in both directions through the hover/unhover callbacks of the Attach context.
local _, ns = ...
local W, L, Theme, TL, MI = ns.W, ns.L, ns.Theme, ns.TravelLogic, ns.MapIcons
local K = ns.PageKit

local PL = {}
ns.MapPlaceList = PL

PL.CARD_H = 100 -- base height of a card (scaled with the text size)
PL.CARDS = 3 -- cards visible at once
local BUTTON_H = 24

ns.AddLocale("enUS", {
  ["map.places.count"] = "Places: %d",
  ["map.card.asStart"] = "As start",
  ["map.card.asDest"] = "As destination",
  ["map.card.toArrow"] = "To arrow",
  ["map.card.toArrowTip"] = "Makes the place the active waypoint.\nNeeds a game map position.",
  ["map.card.show"] = "Show on map",
  ["map.card.showTip"] = "Opens the zone map and highlights the place.\nDouble click works too.",
})

ns.AddLocale("deDE", {
  ["map.places.count"] = "Orte: %d",
  ["map.card.asStart"] = "Als Start",
  ["map.card.asDest"] = "Als Ziel",
  ["map.card.toArrow"] = "Zum Pfeil",
  ["map.card.toArrowTip"] = "Setzt den Ort als aktiven Wegpunkt.\nBraucht eine Spielkarten-Position.",
  ["map.card.show"] = "Auf Karte zeigen",
  ["map.card.showTip"] = "Öffnet die Zonenkarte und hebt den Ort hervor.\nDoppelklick geht auch.",
})

-- Pure logic ---------------------------------------------------------------------------

-- Order of the list, entries = { { node, name } }: the places of the open zone first, then
-- the ones whose name starts with the search text, then by name.
function PL.Sort(entries, query, zone)
  local q = (query or ""):lower()
  local function rank(e)
    return (zone and e.node.z == zone and 0 or 2) + ((q ~= "" and e.name:lower():find(q, 1, true) ~= 1) and 1 or 0)
  end
  table.sort(entries, function(a, b)
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then
      return ra < rb
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.node.s < b.node.s
  end)
  return entries
end

local function fraction(v, lo, hi)
  return math.max(0, math.min(1, (v - lo) / (hi - lo)))
end

-- The position of a place on the map of its zone as { map, x, y } (fractions), taken from the
-- first of the views that has it inside the zone; nil for an estimated place or a zone that
-- has no game map, since no waypoint can point there.
function PL.ZonePoint(views, n)
  for _, view in ipairs(views) do
    local p = view and view.pos and view.pos[n.s]
    local r = view and view.zones and view.zones[n.z]
    local map = view and view.maps and view.maps[n.z]
    if
      p
      and r
      and map
      and (p.kind == "real" or p.kind == "island")
      and type(p.x) == "number"
      and type(p.y) == "number"
      and r.right > r.left
      and r.bottom > r.top
    then
      return { map = map, x = fraction(p.x, r.left, r.right), y = fraction(p.y, r.top, r.bottom) }
    end
  end
end

-- Attach -------------------------------------------------------------------------------

-- ctx = {
--   parent, search              the box the list lives in and the field it hangs below
--   data(), opts(), query()     travel data, route options (faction, level), search text
--   zone()                      slug of the zone that is open on the map, or nil
--   nameOf(node), zoneName(slug)
--   state                       { start, dest, selected, hover } place slugs
--   onSelect(slug)              a click on a card (as before: selects the place)
--   hover(slug), unhover(slug)  the mouse is on a card or left it
--   setRoute(which, slug)       which = "start" | "dest"
--   spec(node)                  { map, x, y } for an arrow to the place, or nil
--   show(slug)                  centers the map on the place (zone zoom), highlights it
-- }
-- Returns the controller: list, count, rows, Update, PaintHover, Height.
function PL.Attach(ctx)
  local st = ctx.state
  local ctl = { rows = {} }

  local function paintRow(row)
    local item = row.item
    if not item then
      return
    end
    local slug = item.node.s
    local selected, hovered = st.selected == slug, st.hover == slug
    row.bg:SetColorTexture(1, 1, 1, selected and 0.1 or (hovered and 0.06 or 0))
    row.border.show(selected)
    row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end

  local function createRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetClipsChildren(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.border = W.Border(row, "accent", 1, 1)
    row.border.show(false)
    row.stripe = row:CreateTexture(nil, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT")
    row.stripe:SetPoint("BOTTOMLEFT")
    row.stripe:SetWidth(4)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.line:SetHeight(1)
    row.badge = MI.NewBadge(row)
    row.badge.box:SetPoint("TOPLEFT", row, "TOPLEFT", 16, -10)
    row.tag = W.Text(row, { role = "micro", color = "textMuted", justify = "RIGHT" })
    row.tag:SetPoint("TOPRIGHT", -8, -8)
    row.title = W.Text(row, { role = "ui" })
    row.title:SetPoint("TOPLEFT", 38, -7)
    row.title:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
    row.sub = W.Text(row, { role = "micro", color = "textSecondary" })
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", -8, 0)

    local function leave()
      -- The mouse moving onto one of the card's own buttons is still hovering the card.
      if row.item and not row:IsMouseOver() then
        ctx.unhover(row.item.node.s)
      end
    end
    local function action(def)
      local b = W.Button(row, {
        key = def.key,
        height = BUTTON_H,
        tooltip = def.tip and def.key,
        tooltipText = def.tip,
        onClick = function()
          if row.item then
            def.run(row.item)
          end
        end,
      })
      b.label:ClearAllPoints()
      b.label:SetPoint("LEFT", 3, 0)
      b.label:SetPoint("RIGHT", -3, 0)
      b:SetPoint(def.point, row, def.rel, def.x, def.y)
      b:SetPoint(def.point2, row, def.rel2, def.x2, def.y)
      b:HookScript("OnEnter", function()
        if row.item then
          ctx.hover(row.item.node.s)
        end
      end)
      b:HookScript("OnLeave", leave)
      return b
    end
    local upper, lower = 2 * 3 + BUTTON_H + 2, 6
    row.start = action({
      key = "map.card.asStart",
      point = "BOTTOMLEFT",
      rel = "BOTTOMLEFT",
      x = 8,
      point2 = "BOTTOMRIGHT",
      rel2 = "BOTTOM",
      x2 = -2,
      y = upper,
      run = function(item)
        ctx.setRoute("start", item.node.s)
      end,
    })
    row.dest = action({
      key = "map.card.asDest",
      point = "BOTTOMLEFT",
      rel = "BOTTOM",
      x = 2,
      point2 = "BOTTOMRIGHT",
      rel2 = "BOTTOMRIGHT",
      x2 = -8,
      y = upper,
      run = function(item)
        ctx.setRoute("dest", item.node.s)
      end,
    })
    row.arrow = action({
      key = "map.card.toArrow",
      tip = "map.card.toArrowTip",
      point = "BOTTOMLEFT",
      rel = "BOTTOMLEFT",
      x = 8,
      point2 = "BOTTOMRIGHT",
      rel2 = "BOTTOM",
      x2 = -2,
      y = lower,
      run = function(item)
        local spec = ctx.spec(item.node)
        if not spec then
          return
        end
        spec.title, spec.source = item.name, "map"
        local wp = ns.Waypoints.Set(spec)
        if wp then
          ns.Notify(string.format(L["wp.activated"], wp.title), "info")
        end
      end,
    })
    row.show = action({
      key = "map.card.show",
      tip = "map.card.showTip",
      point = "BOTTOMLEFT",
      rel = "BOTTOM",
      x = 2,
      point2 = "BOTTOMRIGHT",
      rel2 = "BOTTOMRIGHT",
      x2 = -8,
      y = lower,
      run = function(item)
        ctx.show(item.node.s)
      end,
    })

    row:SetScript("OnEnter", function(self)
      if self.item then
        ctx.hover(self.item.node.s)
      end
    end)
    row:SetScript("OnLeave", leave)
    row:SetScript(
      "OnClick",
      ns.Wrap("map-card", function(self)
        if self.item then
          ctx.onSelect(self.item.node.s)
        end
      end)
    )
    row:SetScript(
      "OnDoubleClick",
      ns.Wrap("map-card-show", function(self)
        if self.item then
          ctx.show(self.item.node.s)
        end
      end)
    )
    ns.Focus.register(row, function(self)
      self:Click()
    end)
    ns.Bind(row, function()
      paintRow(row)
    end)
    ctl.rows[#ctl.rows + 1] = row
    return row
  end

  local function bindRow(row, item)
    local n = item.node
    row.item = item
    row.stripe:SetColorTexture(Theme.color(MI.FactionToken(n.f)))
    row.badge:Set(n.k, n.f, 20)
    W.SetText(row.title, nil, item.name)
    local parts = { MI.KindName(n.k) }
    if n.inst then
      parts[#parts + 1] = ns.T(n.inst) or ""
    end
    parts[#parts + 1] = ctx.zoneName(n.z) or tostring(n.z)
    if n.est then
      parts[#parts + 1] = Theme.hexText("textMuted", L["map.cf.estimate"])
    end
    W.SetText(row.sub, nil, table.concat(parts, " · "))
    local tag = ""
    if st.start == n.s then
      tag = Theme.hexText("success", L["map.tagStart"])
    elseif st.dest == n.s then
      tag = Theme.hexText("warning", L["map.tagDest"])
    elseif n.f == "A" or n.f == "H" then
      tag = L[n.f == "A" and "faction.alliance" or "faction.horde"]
    end
    W.SetText(row.tag, nil, tag)
    row.arrow:SetEnabled(ctx.spec(n) ~= nil)
    paintRow(row)
  end

  ctl.count = W.Text(ctx.parent, { role = "ui", color = "textSecondary" })
  ctl.count:SetPoint("TOPLEFT", ctx.search, "BOTTOMLEFT", 2, -4)
  ctl.list = W.ScrollList(ctx.parent, { rowHeight = PL.RowHeight(), createRow = createRow, bindRow = bindRow })
  ctl.list:SetPoint("TOPLEFT", ctx.search, "BOTTOMLEFT", 0, -24)
  ctl.list:SetPoint("RIGHT")
  ctl.list:SetHeight(PL.RowHeight() * PL.CARDS)

  -- Fills the list from the search text and the route options; the selection scrolls into
  -- view once per change.
  function ctl.Update()
    local data = ctx.data()
    local entries =
      PL.Sort(TL.Nodes(data, ctx.opts(), ctx.nameOf, ctx.query(), ns.SearchLogic.match), ctx.query(), ctx.zone())
    ctl.entries = entries
    W.SetText(ctl.count, nil, string.format(L["map.places.count"], #entries))
    ctl.list:SetData(entries)
    if st.selected ~= ctl.revealed then
      ctl.revealed = st.selected
      for i, e in ipairs(entries) do
        if e.node.s == st.selected then
          ctl.list:Reveal(i)
          break
        end
      end
    end
  end

  -- Hover, selection and tags of the cards that exist, without binding them again.
  function ctl.PaintHover()
    for _, row in ipairs(ctl.rows) do
      paintRow(row)
    end
  end

  -- Search field, counter line and the cards.
  function ctl.Height()
    return 32 + 18 + PL.RowHeight() * PL.CARDS
  end

  return ctl
end

function PL.RowHeight()
  return K.scaledHeight(PL.CARD_H)
end
