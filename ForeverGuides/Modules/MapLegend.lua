-- Legend of the map page: the symbol of every kind of place with its name, the three faction
-- frames and the dimmed symbol of an undiscovered flight point. A folding block of the side column,
-- closed at first. The symbols come from ns.MapIcons, the same functions the pins and the place
-- cards use.
local _, ns = ...
local W, L, MI, K = ns.W, ns.L, ns.MapIcons, ns.PageKit

local ML = {}
ns.MapLegend = ML

ML.SYMBOL = 18 -- edge of a symbol in the legend
local GAP, COLUMN_MIN = 6, 240

ns.AddLocale("enUS", {
  ["map.legend.heading"] = "Legend",
  ["map.legend.places"] = "Places",
  ["map.legend.frames"] = "Frame color",
  ["map.legend.state"] = "State",
  ["map.legend.guild"] = "Guild members",
})

ns.AddLocale("deDE", {
  ["map.legend.heading"] = "Legende",
  ["map.legend.places"] = "Orte",
  ["map.legend.frames"] = "Rahmenfarbe",
  ["map.legend.state"] = "Zustand",
  ["map.legend.guild"] = "Gildenmitglieder",
})

-- Symbols of the guild members on the map, in legend order (texts of the world map tab).
local GUILD_SYMBOLS = {
  { id = "current", spec = {} },
  { id = "old", spec = { hollow = true } },
  { id = "approx", spec = { shape = "diamond" } },
  { id = "group", spec = { cluster = 3 } },
}
local GUILD_EDGE = 12

-- Faction frames in legend order: faction code and the name shown next to it.
local function frames()
  return {
    { faction = "A", name = L["faction.alliance"] },
    { faction = "H", name = L["faction.horde"] },
    { faction = "B", name = L["map.pin.neutral"] },
  }
end

-- ctx = { side = { content, stack }, relayout() }
-- Returns the controller: section, body, open, Toggle, entries (symbol and name per row).
function ML.Attach(ctx)
  local ctl = { open = false, entries = {} }
  local rowH = K.scaledHeight(ML.SYMBOL + 6)
  local section = CreateFrame("Frame", nil, ctx.side.content)
  K.Anchor("FG.Map.Legend", section)
  ctl.section = section

  function ctl.Toggle()
    ctl.open = not ctl.open
    ctx.relayout()
  end

  local head = W.Button(section, {
    text = "",
    variant = "ghost",
    height = K.scaledHeight(26),
    onClick = ctl.Toggle,
  })
  head.label:SetJustifyH("LEFT")
  ctl.head = head
  -- Everything below the heading, shown only while the block is open.
  local body = CreateFrame("Frame", nil, section)
  ctl.body = body
  local placesTitle = W.Text(body, { key = "map.legend.places", role = "ui", color = "textSecondary" })
  local framesTitle = W.Text(body, { key = "map.legend.frames", role = "ui", color = "textSecondary" })
  local stateTitle = W.Text(body, { key = "map.legend.state", role = "ui", color = "textSecondary" })
  for i = 1, #MI.KINDS + 4 do
    ctl.entries[i] = { badge = MI.NewBadge(body), text = W.Text(body, { role = "ui", color = "text" }) }
  end
  -- Guild members: shown while the option is on; without receiving the hint with its button takes the place
  -- of the symbols.
  local guildTitle = W.Text(body, { key = "map.legend.guild", role = "ui", color = "textSecondary" })
  local guildBanner = ns.OptInNotice.Banner(body, {
    fn = "guildMap",
    dir = "receive",
    aud = "guild",
    textKey = "wm.guild.needRecv",
    onChanged = ctx.relayout,
  })
  ctl.guild = { title = guildTitle, banner = guildBanner, rows = {} }
  for i, row in ipairs(GUILD_SYMBOLS) do
    ctl.guild.rows[i] = {
      symbol = ns.WorldMapGuildPins.NewSymbol(body),
      text = W.Text(body, { key = "wm.guild.legend." .. row.id, role = "ui", color = "text", wrap = true }),
      spec = row.spec,
    }
  end
  -- The zone transition arrow is not a kind of place: its entries follow the last one, the solid arrow of a known
  -- crossing and the dashed one of an estimate.
  local arrowAt = #MI.KINDS + 5
  for i = arrowAt, arrowAt + 1 do
    ctl.entries[i] = { badge = MI.NewArrow(body), text = W.Text(body, { role = "ui", color = "text" }) }
  end

  -- Places the entries from index `first` in columns below `top`; returns the bottom.
  local function place(items, first, top, colW, cols, draw)
    for i, item in ipairs(items) do
      local e = ctl.entries[first + i - 1]
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      e.badge.box:ClearAllPoints()
      e.badge.box:SetPoint("TOPLEFT", body, "TOPLEFT", col * colW + 6 + MI.RING, -(top + row * rowH + 3 + MI.RING))
      local name = draw(e, item)
      e.text:ClearAllPoints()
      e.text:SetPoint("LEFT", e.badge.box, "RIGHT", MI.RING + 8, 0)
      e.text:SetWidth(colW - ML.SYMBOL - 24)
      W.SetText(e.text, nil, name)
    end
    return top + math.ceil(#items / cols) * rowH
  end

  -- The guild block below `top`; returns the new bottom.
  function ctl.LayoutGuild(top, width)
    local g = ctl.guild
    local on = ns.WorldMapGuildLogic.Current().showWorld
    g.title:SetShown(on)
    local hint = g.banner:Update(on)
    for _, row in ipairs(g.rows) do
      row.symbol:SetShown(on and not hint)
      row.text:SetShown(on and not hint)
    end
    if not on then
      return top
    end
    local by = top + GAP
    g.title:ClearAllPoints()
    g.title:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -by)
    by = by + math.ceil(g.title:GetStringHeight()) + GAP
    if hint then
      g.banner:ClearAllPoints()
      g.banner:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -by)
      g.banner:SetWidth(width - 8)
      return by + g.banner:Fit(width - 8) + GAP
    end
    local look = ns.WorldMapGuildLogic.Current()
    local textW = width - ML.SYMBOL - 24
    for _, row in ipairs(g.rows) do
      row.symbol:SetSize(GUILD_EDGE + 8, rowH)
      row.symbol:ClearAllPoints()
      row.symbol:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -by)
      ns.WorldMapGuildPins.PaintSymbol(row.symbol, {
        size = GUILD_EDGE,
        shape = row.spec.shape or "hexagon",
        hollow = row.spec.hollow,
        cluster = row.spec.cluster,
        ticks = 0,
        color = ns.WorldMapGuildPins.ClassColor(nil, look),
      })
      row.text:ClearAllPoints()
      row.text:SetPoint("TOPLEFT", body, "TOPLEFT", ML.SYMBOL + 18, -by - 2)
      row.text:SetWidth(textW)
      by = by + math.max(rowH, math.ceil(row.text:GetStringHeight()) + 4)
    end
    return by
  end

  function section:fgGridLayout(width)
    W.SetText(head.label, nil, (ctl.open and "v " or "> ") .. L["map.legend.heading"])
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", self, "TOPLEFT")
    head:SetSize(width, head:GetHeight())
    local y = head:GetHeight()
    body:SetShown(ctl.open)
    if ctl.open then
      local cols = width >= COLUMN_MIN and 2 or 1
      local colW = math.floor(width / cols)
      body:ClearAllPoints()
      body:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      body:SetWidth(width)
      local by = GAP
      placesTitle:ClearAllPoints()
      placesTitle:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -by)
      by = by + math.ceil(placesTitle:GetStringHeight()) + GAP
      by = place(MI.KINDS, 1, by, colW, cols, function(e, kind)
        e.badge:Set(kind, "B", ML.SYMBOL)
        return MI.KindName(kind)
      end)
      by = place({ "arrow", "guess" }, arrowAt, by, colW, cols, function(e, item)
        e.badge:Set(ML.SYMBOL, math.pi / 2, item == "guess")
        return L[item == "guess" and "zb.legend.guess" or "zb.legend"]
      end)
      by = by + GAP
      framesTitle:ClearAllPoints()
      framesTitle:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -by)
      by = by + math.ceil(framesTitle:GetStringHeight()) + GAP
      by = place(frames(), #MI.KINDS + 1, by, colW, cols, function(e, f)
        e.badge:Set("city", f.faction, ML.SYMBOL)
        return f.name
      end)
      by = by + GAP
      stateTitle:ClearAllPoints()
      stateTitle:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -by)
      by = by + math.ceil(stateTitle:GetStringHeight()) + GAP
      by = place({ "dim" }, #MI.KINDS + 4, by, colW, cols, function(e)
        e.badge:Set("flightMaster", "B", ML.SYMBOL, false, true)
        return L["fp.legend.dim"]
      end)
      by = ctl.LayoutGuild(by, width)
      body:SetHeight(by)
      y = y + by
    end
    self:SetHeight(y)
    return y
  end

  ctx.side.stack:Add(section, { gap = GAP })
  return ctl
end
