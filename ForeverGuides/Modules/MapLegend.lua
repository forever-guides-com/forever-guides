-- Legend of the map page: the symbol of every kind of place with its name and the three
-- faction frames. A folding block of the side column, closed at first. The symbols come from
-- ns.MapIcons, the same functions the pins and the place cards use.
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
})

ns.AddLocale("deDE", {
  ["map.legend.heading"] = "Legende",
  ["map.legend.places"] = "Orte",
  ["map.legend.frames"] = "Rahmenfarbe",
})

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
  for i = 1, #MI.KINDS + 3 do
    ctl.entries[i] = { badge = MI.NewBadge(body), text = W.Text(body, { role = "ui", color = "text" }) }
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
      by = by + GAP
      framesTitle:ClearAllPoints()
      framesTitle:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -by)
      by = by + math.ceil(framesTitle:GetStringHeight()) + GAP
      by = place(frames(), #MI.KINDS + 1, by, colW, cols, function(e, f)
        e.badge:Set("city", f.faction, ML.SYMBOL)
        return f.name
      end)
      body:SetHeight(by)
      y = y + by
    end
    self:SetHeight(y)
    return y
  end

  ctx.side.stack:Add(section, { gap = GAP })
  return ctl
end
