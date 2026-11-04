-- The tab "Gather" of the panel on Blizzard's world map (WorldMapBar.lua): the switch for the spots, the
-- switch for the explored look with the banner of its data add-on, and the display choice of materials
-- (ns.GatherFilterUI). The bar calls Layout(avail) with the room it has and gets the height the tab needs;
-- the list of materials takes what is left and scrolls.
local _, ns = ...
local W, K = ns.W, ns.PageKit
local B = ns.BlizzardLinks

local Tab = {}
ns.WorldMapGatherTab = Tab

ns.AddLocale("enUS", {
  ["wm.gather.tab"] = "Gather",
  ["wm.gather.show"] = "Show on the map",
  ["wm.gather.showTip"] = "Shows ore veins and herbs on the zone map of this window.",
  ["wm.gather.reveal"] = "Show map as explored",
  ["wm.gather.revealTip"] = "Draws every area of a zone map as if you had explored it. Needs the switch above. Off puts the normal look back.",
  ["wm.gather.hint"] = "Spots and explored areas show on zone maps, not on the world or continent map.",
})
ns.AddLocale("deDE", {
  ["wm.gather.tab"] = "Sammeln",
  ["wm.gather.show"] = "Auf der Karte zeigen",
  ["wm.gather.showTip"] = "Zeigt Erzadern und Kräuter auf der Zonenkarte dieses Fensters.",
  ["wm.gather.reveal"] = "Karte als erkundet zeigen",
  ["wm.gather.revealTip"] = "Zeichnet jedes Gebiet einer Zonenkarte so, als hättest du es erkundet. Braucht den Schalter darüber. Aus stellt die normale Darstellung wieder her.",
  ["wm.gather.hint"] = "Fundorte und erkundete Gebiete erscheinen auf Zonenkarten, nicht auf der Welt- oder Kontinentkarte.",
})

local CHECK_H, GAP = 22, 4
local MIN_ROWS = 3

local function on(path)
  return ns.Store.get(path) ~= false
end

-- parent: the panel, width: inner width of the panel, opts.relayout(): the bar lays out again.
-- Returns the frame of the tab with Layout(avail) -> height and the parts.
function Tab.Create(parent, width, opts)
  opts = opts or {}
  local relayout = opts.relayout or function() end
  local pg = CreateFrame("Frame", nil, parent)

  local function check(key, path)
    local c = W.Checkbox(pg, {
      key = key,
      tooltip = key,
      tooltipText = key .. "Tip",
      get = function()
        return on(path)
      end,
      set = function(value)
        ns.Store.set(path, value and true or false)
      end,
    })
    B.LeaveFocusRing(c)
    return c
  end
  local show = check("wm.gather.show", "settings.gather.worldmap")
  local reveal = check("wm.gather.reveal", "settings.worldMapReveal")
  show.fgId, reveal.fgId = "wm-gather-show", "wm-gather-reveal"

  local banner = ns.PackageUI.Banner(pg, ns.MapReveal.ADDON, {
    labelKey = "map.reveal.pkg",
    onLoaded = function()
      ns.WorldMapGather.Refresh()
      relayout()
    end,
    onResize = relayout,
  })
  local hint = W.Text(pg, { key = "wm.gather.hint", role = "micro", color = "textMuted", wrap = true })
  local filter = ns.GatherFilterUI.Build(pg, { leaveFocusRing = true })

  function pg:Layout(avail)
    local y = 0
    for _, c in ipairs({ show, reveal }) do
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -y)
      c:SetWidth(width)
      c:Refresh()
      y = y + CHECK_H + GAP
    end
    local wanted = on("settings.worldMapReveal") and ns.MapReveal.BannerWanted(false)
    if banner:Update(wanted) then
      banner:ClearAllPoints()
      banner:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -y)
      y = y + banner:Fit(width) + GAP
    end
    hint:ClearAllPoints()
    hint:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -y)
    hint:SetWidth(width)
    y = y + math.ceil(hint:GetStringHeight()) + GAP * 2
    filter:ClearAllPoints()
    filter:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -y)
    filter:SetWidth(width)
    filter:Update()
    -- The control needs its two switches and a gap above the list; the list takes the rest, at least a few rows.
    local rowH = K.scaledHeight(26)
    local room = (avail or 0) - y - (2 * CHECK_H + 2 + 6)
    local rows = math.max(MIN_ROWS, math.min(ns.GatherFilterUI.LIST_ROWS, math.floor(room / rowH)))
    local height = filter:SetListHeight(rows * rowH)
    pg:SetSize(width, y + height)
    return y + height
  end

  pg.parts = { show = show, reveal = reveal, banner = banner, hint = hint, filter = filter }
  return pg
end
