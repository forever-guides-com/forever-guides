-- The top of the side column of the Map & Route page: one flow "choose a destination, add stops if you want,
-- look at the route, start the journey". A search field finds places, flight points, instance entrances and
-- whole zones (a zone name lists its places); a hit becomes the goal or a stop. Below it stands the route card
-- of the world map panel (RouteStopList), the same list of the same shared plan (RoutePlan).
--   MPB.Search(data, o, zoneNameOf, query, limit) -> { { node, name }, ... }   pure
--   MPB.Attach(ctx) -> { card, box }   ctx = { side, data(), options(), zoneNameOf(zoneSlug), relayout() }
local _, ns = ...
local W, TL, PL, RP = ns.W, ns.TravelLogic, ns.MapPlaceList, ns.RoutePlan

ns.AddLocale("enUS", {
  ["map.target"] = "Choose a destination",
  ["map.target.placeholder"] = "Place, zone, flight point or instance",
  ["map.target.none"] = "Nothing found.",
  ["map.target.goal"] = "Goal",
  ["map.target.goal.tip"] = "Makes this place the goal of the route.",
  ["map.target.stop"] = "Stop",
  ["map.target.stop.tip"] = "Adds this place as a stop before the goal.",
  ["map.options"] = "Settings",
  ["map.options.tip"] = "Faction, transport types, flying, mount and map display.",
  ["map.route.view"] = "Route",
})

ns.AddLocale("deDE", {
  ["map.target"] = "Ziel wählen",
  ["map.target.placeholder"] = "Ort, Zone, Flugpunkt oder Instanz",
  ["map.target.none"] = "Nichts gefunden.",
  ["map.target.goal"] = "Ziel",
  ["map.target.goal.tip"] = "Macht diesen Ort zum Ziel der Route.",
  ["map.target.stop"] = "Stopp",
  ["map.target.stop.tip"] = "Fügt diesen Ort als Stopp vor dem Ziel hinzu.",
  ["map.options"] = "Einstellungen",
  ["map.options.tip"] = "Fraktion, Verkehrsmittel, Fliegen, Reittier und Kartenanzeige.",
  ["map.route.view"] = "Route",
})

local MPB = {}
ns.MapPlanBlock = MPB

MPB.LIMIT = 6
local ROW_H, BTN_W, GAP = 28, 64, 4

-- The places that match `query` by their name or the name of their zone, places of the best match first.
function MPB.Search(data, o, zoneNameOf, query, limit)
  query = ns.U.trim(query or "")
  if not (data and data.nodes) or #query < 2 then
    return {}
  end
  local entries = TL.Nodes(data, o, function(n)
    local zone = zoneNameOf and zoneNameOf(n.z)
    return (ns.T(n.n) or n.s) .. (zone and (" " .. zone) or "")
  end, query, ns.SearchLogic.match)
  PL.Sort(entries, query, nil)
  local out = {}
  for i = 1, math.min(limit or MPB.LIMIT, #entries) do
    out[i] = { node = entries[i].node, name = ns.T(entries[i].node.n) or entries[i].node.s }
  end
  return out
end

function MPB.Attach(ctx)
  local side = ctx.side
  ns.AddHeading(side, "map.target")

  local box = CreateFrame("Frame", nil, side.content)
  local rows, hits = {}, {}
  local none = W.Text(box, { key = "map.target.none", role = "ui", color = "textSecondary" })
  none:Hide()
  local edit

  local function clear()
    edit.edit:SetText("")
  end

  local function newRow()
    local row = CreateFrame("Frame", nil, box)
    row:SetHeight(ROW_H)
    row.name = W.Text(row, { role = "ui", color = "text" })
    row.zone = W.Text(row, { role = "micro", color = "textSecondary" })
    row.stop = W.Action(row, {
      key = "map.target.stop",
      variant = "secondary",
      width = BTN_W,
      height = 24,
      tooltip = "map.target.stop",
      tooltipText = "map.target.stop.tip",
      onClick = function()
        RP.Insert(row.slug)
        clear()
      end,
    })
    row.goal = W.Action(row, {
      key = "map.target.goal",
      variant = "primary",
      width = BTN_W,
      height = 24,
      tooltip = "map.target.goal",
      tooltipText = "map.target.goal.tip",
      onClick = function()
        RP.SetGoalPlace(row.slug)
        clear()
      end,
    })
    row.stop:SetPoint("RIGHT", 0, 0)
    row.goal:SetPoint("RIGHT", row.stop, "LEFT", -GAP, 0)
    row.name:SetPoint("TOPLEFT", 0, -2)
    row.name:SetPoint("RIGHT", row.goal, "LEFT", -GAP, 0)
    row.zone:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, 0)
    row.zone:SetPoint("RIGHT", row.goal, "LEFT", -GAP, 0)
    return row
  end

  local function paint(text)
    hits = MPB.Search(ctx.data(), ctx.options(), ctx.zoneNameOf, text)
    for i, hit in ipairs(hits) do
      local row = rows[i]
      if not row then
        row = newRow()
        rows[i] = row
      end
      row.slug = hit.node.s
      W.SetText(row.name, nil, hit.name)
      W.SetText(row.zone, nil, ctx.zoneNameOf and ctx.zoneNameOf(hit.node.z) or "")
      row:Show()
    end
    for i = #hits + 1, #rows do
      rows[i]:Hide()
    end
    none:SetShown(#hits == 0 and #ns.U.trim(text or "") >= 2)
    ctx.relayout()
  end

  edit = W.EditBox(box, {
    placeholder = "map.target.placeholder",
    clear = true,
    onChange = paint,
    onEnter = function()
      if hits[1] then
        RP.SetGoalPlace(hits[1].node.s)
        clear()
      end
    end,
  })
  edit:SetPoint("TOPLEFT")
  edit:SetPoint("TOPRIGHT")

  function box:fgGridLayout(width)
    local y = edit:GetHeight() + GAP
    for _, row in ipairs(rows) do
      if row:IsShown() then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
        row:SetWidth(width)
        y = y + ROW_H + 2
      end
    end
    none:ClearAllPoints()
    if none:IsShown() then
      none:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -y)
      y = y + 20
    end
    self:SetHeight(y)
    return y
  end
  side.stack:Add(box, { gap = 8 })

  local holder = CreateFrame("Frame", nil, side.content)
  local card = ns.RouteStopList.Create(holder, 220)
  card:SetPoint("TOPLEFT", holder, "TOPLEFT")
  card.onResize = ctx.relayout
  function holder:fgGridLayout(width)
    card:Resize(width)
    local h = card:Refresh()
    self:SetHeight(h)
    return h
  end
  side.stack:Add(holder, { gap = 8 })
  return { card = card, box = box, holder = holder, edit = edit }
end
