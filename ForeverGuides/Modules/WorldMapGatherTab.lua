-- The tab "Gather" of the panel on Blizzard's world map (WorldMapBar.lua), two independent groups. First the
-- explored look: its own switch with the banner of its data add-on, it does not depend on the spots. Then
-- the spots: the main switch and below it the display choice of materials (ns.GatherFilterUI), which only
-- applies while the main switch is on (dimmed, with a tooltip that says why, while it is off). The bar calls
-- Layout(avail) with the room it has and gets the height the tab needs; the list of materials takes what is
-- left and scrolls.
local _, ns = ...
local W, K = ns.W, ns.PageKit
local B = ns.BlizzardLinks

local Tab = {}
ns.WorldMapGatherTab = Tab

ns.AddLocale("enUS", {
  ["wm.gather.tab"] = "Gather",
  ["wm.gather.show"] = "Show spots on the map",
  ["wm.gather.showTip"] = "Main switch for ore veins, herbs, chests and fishing schools on the zone map of this window. The choice of materials, chests and schools below only applies while it is on.",
  ["wm.gather.reveal"] = "Show map as explored",
  ["wm.gather.revealTip"] = "Draws every area of a zone map as if you had explored it. Works on its own, independent of the spots. Off puts the normal look back.",
  ["wm.gather.spots"] = "Spots",
  ["wm.gather.spotsOffTip"] = 'The spots are switched off. Switch on "Show spots on the map" first, then the choice below takes effect.',
  ["wm.gather.hint"] = "Spots and explored areas show on zone maps, not on the world or continent map.",
})
ns.AddLocale("deDE", {
  ["wm.gather.tab"] = "Sammeln",
  ["wm.gather.show"] = "Fundorte auf der Karte zeigen",
  ["wm.gather.showTip"] = "Hauptschalter für Erzadern, Kräuter, Truhen und Fischschwärme auf der Zonenkarte dieses Fensters. Die Auswahl von Materialien, Truhen und Schwärmen darunter wirkt nur, solange er an ist.",
  ["wm.gather.reveal"] = "Karte als erkundet zeigen",
  ["wm.gather.revealTip"] = "Zeichnet jedes Gebiet einer Zonenkarte so, als hättest du es erkundet. Wirkt für sich allein, unabhängig von den Fundorten. Aus stellt die normale Darstellung wieder her.",
  ["wm.gather.spots"] = "Fundorte",
  ["wm.gather.spotsOffTip"] = 'Die Fundorte sind ausgeschaltet. Schalte zuerst "Fundorte auf der Karte zeigen" ein, dann wirkt die Auswahl darunter.',
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
        -- The dependent controls dim or wake up at once.
        relayout()
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
  local spots = W.Text(pg, { key = "wm.gather.spots", role = "ui", family = "heading", color = "accent2" })
  local filter = ns.GatherFilterUI.Build(pg, { leaveFocusRing = true })
  local fishing = ns.WorldMapFishing.Build(pg, width, { relayout = relayout })
  -- Over the choice of materials while the spots are off: it takes the clicks and says why nothing happens.
  local shield = CreateFrame("Frame", nil, pg)
  shield:EnableMouse(true)
  shield:SetAllPoints(filter)
  shield:SetFrameLevel(filter:GetFrameLevel() + 200)
  W.AttachTooltip(shield, "wm.gather.show", "wm.gather.spotsOffTip")
  shield:Hide()

  function pg:Layout(avail)
    local y = 0
    reveal:ClearAllPoints()
    reveal:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -y)
    reveal:SetWidth(width)
    reveal:Refresh()
    y = y + CHECK_H + GAP
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
    spots:ClearAllPoints()
    spots:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -y)
    spots:SetWidth(width)
    y = y + 16 + GAP
    show:ClearAllPoints()
    show:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -y)
    show:SetWidth(width)
    show:Refresh()
    y = y + CHECK_H + GAP
    filter:ClearAllPoints()
    filter:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -y)
    filter:SetWidth(width)
    filter:Update()
    local spotsOn = on("settings.gather.worldmap")
    filter:SetAlpha(spotsOn and 1 or 0.45)
    shield:SetShown(not spotsOn)
    fishing:Update()
    local fishingHeight = fishing:Layout(width)
    -- The control needs its two rows of switches and a gap above the list; the list takes what the group
    -- Fishing leaves, at least a few rows. A tab taller than the panel scrolls.
    local rowH = K.scaledHeight(26)
    local room = (avail or 0) - y - (ns.GatherFilterUI.TOP + 6) - fishingHeight - 2 * GAP
    local rows = math.max(MIN_ROWS, math.min(ns.GatherFilterUI.LIST_ROWS, math.floor(room / rowH)))
    local height = filter:SetListHeight(rows * rowH)
    y = y + height + 2 * GAP
    fishing:ClearAllPoints()
    fishing:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -y)
    pg:SetSize(width, y + fishingHeight)
    return y + fishingHeight
  end

  pg.parts = {
    show = show,
    reveal = reveal,
    banner = banner,
    hint = hint,
    filter = filter,
    shield = shield,
    fishing = fishing,
  }
  return pg
end
