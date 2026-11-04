-- The tab "Guild" of the panel on Blizzard's world map (WorldMapBar.lua): filters of the guild members on
-- the map (show, online per guild list, level range, rank), the legend of the symbols and the own side of
-- the function: the hint for sending, "Invisible" and the accuracy. While receiving is off the hint with
-- its button stands in place of the filters. The bar calls Layout(avail) and gets the height the tab
-- needs. Everything is written through the settings (Store.set), the display follows by its events.
local _, ns = ...
local W, L, Store, GLG = ns.W, ns.L, ns.Store, ns.WorldMapGuildLogic
local B = ns.BlizzardLinks

local Tab = {}
ns.WorldMapGuildTab = Tab

ns.AddLocale("enUS", {
  ["wm.guild.tab.title"] = "Guild members",
  ["wm.guild.tab.tip"] = "Filters, legend and the sharing of your own position.",
  ["wm.guild.needRecv"] = "Guild members on the map need receiving positions.",
  ["wm.guild.needSend"] = "Your position is not sent. Guild members with the add-on do not see you.",
  ["wm.guild.show"] = "Show guild members",
  ["wm.guild.showTip"] = "Shows the members who share their position on this map.",
  ["wm.guild.online"] = "Only online",
  ["wm.guild.onlineTip"] = "Hides members that the guild list shows as offline.",
  ["wm.guild.minLevel"] = "Level from",
  ["wm.guild.maxLevel"] = "Level up to",
  ["wm.guild.rank"] = "Rank",
  ["wm.guild.rankAll"] = "All ranks",
  ["wm.guild.rankFrom"] = "%s and above",
  ["wm.guild.legend"] = "Legend",
  ["wm.guild.legend.current"] = "Current position",
  ["wm.guild.legend.old"] = "Older or unconfirmed (ring)",
  ["wm.guild.legend.approx"] = "Approximate place (diamond)",
  ["wm.guild.legend.group"] = "Several members close together (number)",
  ["wm.guild.legend.rank"] = "Strokes above: high rank (option Rank)",
  ["wm.guild.own"] = "Your position",
  ["wm.guild.invisible"] = "Invisible",
  ["wm.guild.invisibleTip"] = "Stops sending your position and asks others to remove it.",
  ["wm.guild.accuracy"] = "Accuracy",
  ["wm.guild.accuracy.exact"] = "Exact",
  ["wm.guild.accuracy.grid"] = "Grid (5 percent of the map)",
  ["wm.guild.accuracy.zone"] = "Zone only",
})
ns.AddLocale("deDE", {
  ["wm.guild.tab.title"] = "Gildenmitglieder",
  ["wm.guild.tab.tip"] = "Filter, Legende und das Teilen deiner eigenen Position.",
  ["wm.guild.needRecv"] = "Gildenmitglieder auf der Karte brauchen den Empfang von Positionen.",
  ["wm.guild.needSend"] = "Deine Position wird nicht gesendet. Gildenmitglieder mit dem Addon sehen dich nicht.",
  ["wm.guild.show"] = "Gildenmitglieder zeigen",
  ["wm.guild.showTip"] = "Zeigt die Mitglieder, die ihre Position teilen, auf dieser Karte.",
  ["wm.guild.online"] = "Nur online",
  ["wm.guild.onlineTip"] = "Blendet Mitglieder aus, die die Gildenliste als offline zeigt.",
  ["wm.guild.minLevel"] = "Stufe ab",
  ["wm.guild.maxLevel"] = "Stufe bis",
  ["wm.guild.rank"] = "Rang",
  ["wm.guild.rankAll"] = "Alle Ränge",
  ["wm.guild.rankFrom"] = "%s und höher",
  ["wm.guild.legend"] = "Legende",
  ["wm.guild.legend.current"] = "Aktuelle Position",
  ["wm.guild.legend.old"] = "Älter oder unbestätigt (Ring)",
  ["wm.guild.legend.approx"] = "Ungefährer Ort (Raute)",
  ["wm.guild.legend.group"] = "Mehrere Mitglieder dicht beieinander (Zahl)",
  ["wm.guild.legend.rank"] = "Striche darüber: hoher Rang (Option Rang)",
  ["wm.guild.own"] = "Deine Position",
  ["wm.guild.invisible"] = "Unsichtbar",
  ["wm.guild.invisibleTip"] = "Stoppt das Senden deiner Position und bittet andere, sie zu löschen.",
  ["wm.guild.accuracy"] = "Genauigkeit",
  ["wm.guild.accuracy.exact"] = "Genau",
  ["wm.guild.accuracy.grid"] = "Raster (5 Prozent der Karte)",
  ["wm.guild.accuracy.zone"] = "Nur Zone",
})

Tab.ACCURACY = { "exact", "grid", "zone" }
local CHECK_H, SLIDER_H, DROP_H, GAP, LEGEND_H, SYMBOL = 22, 42, 46, 4, 22, 12
local LEGEND = {
  { id = "current", spec = {} },
  { id = "old", spec = { hollow = true } },
  { id = "approx", spec = { shape = "diamond" } },
  { id = "group", spec = { cluster = 3 } },
  { id = "rank", spec = { ticks = 3 } },
}

-- Refills `options` (the table of a dropdown) with "all ranks" and "<rank> and above" for every rank of
-- the guild list.
function Tab.FillRanks(options)
  for i = #options, 2, -1 do
    options[i] = nil
  end
  options[1] = { value = -1, key = "wm.guild.rankAll" }
  local snap = ns.GuildData.Get()
  for _, rank in ipairs(snap and snap.ranks or {}) do
    options[#options + 1] = { value = rank.index, text = string.format(L["wm.guild.rankFrom"], rank.name) }
  end
end

-- Takes the control out of the Tab ring of the main window: the bar lives on a Blizzard frame.
local function leave(control)
  for _, c in ipairs({ control, control.slider, control.button }) do
    B.LeaveFocusRing(c)
  end
  return control
end

-- parent: the panel, width: inner width of the panel, opts.relayout(): the bar lays out again.
-- Returns the frame of the tab with Layout(avail) -> height and the parts.
function Tab.Create(parent, width, opts)
  opts = opts or {}
  local relayout = opts.relayout or function() end
  local pg = CreateFrame("Frame", nil, parent)
  local parts = { legend = {} }

  local function value(name)
    return GLG.Current()[name]
  end

  local function setting(name)
    return GLG.SPEC[name][1]
  end

  local function check(key, name, tip)
    local c = W.Checkbox(pg, {
      key = key,
      tooltip = key,
      tooltipText = tip,
      get = function()
        return value(name)
      end,
      set = function(v)
        Store.set("settings." .. setting(name), v and true or false)
      end,
    })
    c.fgId = "wm-guild-" .. name
    return leave(c)
  end

  local function slider(key, name, other)
    local s = W.Slider(pg, {
      key = key,
      min = GLG.SPEC[name][3],
      max = GLG.SPEC[name][4],
      step = 1,
      get = function()
        return value(name)
      end,
      set = function(v)
        v = math.floor(v + 0.5)
        Store.set("settings." .. setting(name), v)
        -- The other end follows: the range never turns around.
        if other then
          local follow = GLG.Partner(name, v, tonumber(Store.get("settings." .. setting(other))))
          if follow then
            Store.set("settings." .. setting(other), follow)
          end
          pg.parts[other]:Refresh()
        end
      end,
      format = function(v)
        return tostring(math.floor(v + 0.5))
      end,
    })
    s.fgId = "wm-guild-" .. name
    return leave(s)
  end

  parts.recv = ns.OptInNotice.Banner(pg, {
    fn = "guildMap",
    dir = "receive",
    aud = "guild",
    textKey = "wm.guild.needRecv",
    onChanged = relayout,
  })
  parts.show = check("wm.guild.show", "showWorld", "wm.guild.showTip")
  parts.online = check("wm.guild.online", "onlineOnly", "wm.guild.onlineTip")
  parts.minLevel = slider("wm.guild.minLevel", "minLevel", "maxLevel")
  parts.maxLevel = slider("wm.guild.maxLevel", "maxLevel", "minLevel")

  -- The options are refilled from the guild list's ranks on every layout, the dropdown reads the same table.
  parts.rankOptions = {}
  Tab.FillRanks(parts.rankOptions)
  parts.rank = leave(W.Dropdown(pg, {
    key = "wm.guild.rank",
    width = width,
    options = parts.rankOptions,
    get = function()
      return value("rankFilter")
    end,
    set = function(v)
      Store.set("settings." .. setting("rankFilter"), v)
    end,
  }))
  parts.rank.fgId = "wm-guild-rank"

  parts.legendHead = W.Text(pg, { key = "wm.guild.legend", role = "ui", family = "heading", color = "accent2" })
  for i, row in ipairs(LEGEND) do
    local symbol = ns.WorldMapGuildPins.NewSymbol(pg)
    symbol:SetSize(SYMBOL + 8, LEGEND_H)
    local text =
      W.Text(pg, { key = "wm.guild.legend." .. row.id, role = "micro", color = "textSecondary", wrap = true })
    parts.legend[i] = { symbol = symbol, text = text, spec = row.spec }
  end

  parts.sendHead = W.Text(pg, { key = "wm.guild.own", role = "ui", family = "heading", color = "accent2" })
  parts.send = ns.OptInNotice.Banner(pg, {
    fn = "guildMap",
    dir = "send",
    aud = "guild",
    textKey = "wm.guild.needSend",
    onChanged = relayout,
  })
  parts.invisible = W.Checkbox(pg, {
    key = "wm.guild.invisible",
    tooltip = "wm.guild.invisible",
    tooltipText = "wm.guild.invisibleTip",
    get = function()
      return Store.get("settings.guildMapInvisible") == true
    end,
    set = function(v)
      Store.set("settings.guildMapInvisible", v and true or false)
    end,
  })
  parts.invisible.fgId = "wm-guild-invisible"
  leave(parts.invisible)
  local accuracy = {}
  for i, id in ipairs(Tab.ACCURACY) do
    accuracy[i] = { value = id, key = "wm.guild.accuracy." .. id }
  end
  parts.accuracy = leave(W.Dropdown(pg, {
    key = "wm.guild.accuracy",
    width = width,
    options = accuracy,
    get = function()
      return ns.GuildMapComm.Accuracy()
    end,
    set = function(v)
      Store.set("settings.guildMapAccuracy", v)
    end,
  }))
  parts.accuracy.fgId = "wm-guild-accuracy"

  local y
  local function put(frame, height, w)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -y)
    if w then
      frame:SetWidth(w)
    end
    y = y + height + GAP
  end

  function pg:Layout()
    y = 0
    for _, name in ipairs({ "show", "online", "minLevel", "maxLevel", "rank" }) do
      parts[name]:Hide()
    end
    if parts.recv:Update(true) then
      put(parts.recv, parts.recv:Fit(width))
    else
      Tab.FillRanks(parts.rankOptions)
      parts.show:Show()
      parts.show:Refresh()
      put(parts.show, CHECK_H, width)
      parts.online:Show()
      parts.online:Refresh()
      put(parts.online, CHECK_H, width)
      for _, name in ipairs({ "minLevel", "maxLevel" }) do
        parts[name]:Show()
        parts[name]:Refresh()
        put(parts[name], SLIDER_H, width)
      end
      parts.rank:Show()
      parts.rank:Refresh()
      parts.rank.button:SetWidth(width)
      put(parts.rank, DROP_H, width)
    end
    y = y + GAP
    put(parts.legendHead, 16, width)
    local look = GLG.Current()
    for _, row in ipairs(parts.legend) do
      row.symbol:ClearAllPoints()
      row.symbol:SetPoint("TOPLEFT", pg, "TOPLEFT", 0, -y)
      local spec = {
        size = SYMBOL,
        shape = row.spec.shape or "hexagon",
        hollow = row.spec.hollow,
        cluster = row.spec.cluster,
        ticks = row.spec.ticks or 0,
        color = ns.WorldMapGuildPins.ClassColor(nil, look),
      }
      ns.WorldMapGuildPins.PaintSymbol(row.symbol, spec)
      row.text:ClearAllPoints()
      row.text:SetPoint("TOPLEFT", pg, "TOPLEFT", SYMBOL + 14, -y - 2)
      row.text:SetWidth(width - SYMBOL - 14)
      y = y + math.max(LEGEND_H, math.ceil(row.text:GetStringHeight()) + 4)
    end
    y = y + GAP
    put(parts.sendHead, 16, width)
    if parts.send:Update(true) then
      put(parts.send, parts.send:Fit(width))
    end
    parts.invisible:Refresh()
    put(parts.invisible, CHECK_H, width)
    parts.accuracy:Refresh()
    parts.accuracy.button:SetWidth(width)
    put(parts.accuracy, DROP_H, width)
    pg:SetSize(width, y)
    return y
  end

  pg.parts = parts
  return pg
end
