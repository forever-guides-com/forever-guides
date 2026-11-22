-- Options of the guild member display on the maps, a card in the tab "Map" of the settings: where members
-- show (world map, minimap), the symbol size per map, what the symbol tells (class color, rank marks, level,
-- name), grouping and the filter. The own side (Invisible, Accuracy) and the hints for receiving and
-- sending sit in the same card, so the whole function is in one place. Values are written through the
-- settings; WorldMapGuildLogic reads them clamped.
local _, ns = ...
local W, L, Store, GLG = ns.W, ns.L, ns.Store, ns.WorldMapGuildLogic

local S = {}
ns.GuildMapSettings = S

ns.AddLocale("enUS", {
  ["guildmap.set.heading"] = "Guild members on the maps",
  ["guildmap.set.hint"] = "Members of your guild and your friends who share their position show as symbols. The addon shows and sends nothing until sharing is on.",
  ["guildmap.set.showWorld"] = "Show on the world map",
  ["guildmap.set.showWorldTip"] = "Draws guild members on the world map, the zone maps, the continent maps and the addon map.",
  ["guildmap.set.showMini"] = "Show on the minimap",
  ["guildmap.set.showMiniTip"] = "Draws guild members on the minimap.\nNo tooltip there, details are on the world map.",
  ["guildmap.set.worldSize"] = "Symbol size, world map",
  ["guildmap.set.miniSize"] = "Symbol size, minimap",
  ["guildmap.set.sizeTip"] = "Sets the size: 50 to 200 % of the normal size.",
  ["guildmap.set.showClass"] = "Class color",
  ["guildmap.set.showClassTip"] = "Colors the symbol by class. Off draws a neutral color. The shape stays the same.",
  ["guildmap.set.showRank"] = "Rank marks",
  ["guildmap.set.showRankTip"] = "Draws strokes above the symbol: three for the guild master, two and one for the next ranks.",
  ["guildmap.set.showLevel"] = "Show level",
  ["guildmap.set.showLevelTip"] = "Writes the level next to the symbol. Needs the guild list.",
  ["guildmap.set.showName"] = "Show name",
  ["guildmap.set.showNameTip"] = "Writes the name next to the symbol.",
  ["guildmap.set.group"] = "Merge nearby members",
  ["guildmap.set.groupTip"] = "Merges members whose symbols would touch into one symbol with a number. The tooltip lists them.",
  ["guildmap.set.onlineOnly"] = "Only online",
  ["guildmap.set.onlineOnlyTip"] = "Hides members that the guild list shows as offline.",
  ["guildmap.set.minLevel"] = "Level from",
  ["guildmap.set.maxLevel"] = "Level up to",
  ["guildmap.set.rank"] = "Rank",
  ["guildmap.set.own"] = "Your own position",
  ["guildmap.set.hideInstances"] = "Hide inside instances",
  ["guildmap.set.hideInstancesTip"] = "Hides the dots of guild members and friends in dungeons, raids and battlegrounds.",
  ["guildmap.set.friendZones"] = "Players in their zone",
  ["guildmap.set.friendZonesTip"] = "Marks the zone of guild members and friends who are online and do not share their position, as the guild and friends lists show it.",
})
ns.AddLocale("deDE", {
  ["guildmap.set.heading"] = "Gildenmitglieder auf den Karten",
  ["guildmap.set.hint"] = "Mitglieder deiner Gilde und deine Freunde, die ihre Position teilen, erscheinen als Symbole. Solange Teilen aus ist, zeigt und sendet das Addon nichts.",
  ["guildmap.set.showWorld"] = "Auf der Weltkarte anzeigen",
  ["guildmap.set.showWorldTip"] = "Zeichnet Gildenmitglieder auf der Weltkarte, den Zonen- und Kontinentkarten und der Addonkarte.",
  ["guildmap.set.showMini"] = "Auf der Minimap anzeigen",
  ["guildmap.set.showMiniTip"] = "Zeichnet Gildenmitglieder auf der Minimap.\nDort gibt es keinen Tooltip, Details stehen auf der Weltkarte.",
  ["guildmap.set.worldSize"] = "Symbolgröße, Weltkarte",
  ["guildmap.set.miniSize"] = "Symbolgröße, Minimap",
  ["guildmap.set.sizeTip"] = "Legt die Größe fest: 50 bis 200 % der normalen Größe.",
  ["guildmap.set.showClass"] = "Klassenfarbe",
  ["guildmap.set.showClassTip"] = "Färbt das Symbol nach Klasse. Aus zeichnet eine neutrale Farbe. Die Form bleibt gleich.",
  ["guildmap.set.showRank"] = "Rangmarken",
  ["guildmap.set.showRankTip"] = "Zeichnet Striche über dem Symbol: drei für den Gildenleiter, zwei und einer für die nächsten Ränge.",
  ["guildmap.set.showLevel"] = "Stufe anzeigen",
  ["guildmap.set.showLevelTip"] = "Schreibt die Stufe neben das Symbol. Braucht die Gildenliste.",
  ["guildmap.set.showName"] = "Name anzeigen",
  ["guildmap.set.showNameTip"] = "Schreibt den Namen neben das Symbol.",
  ["guildmap.set.group"] = "Nahe Mitglieder zusammenfassen",
  ["guildmap.set.groupTip"] = "Fasst Mitglieder, deren Symbole sich berühren würden, zu einem Symbol mit Zahl zusammen. Der Tooltip listet sie auf.",
  ["guildmap.set.onlineOnly"] = "Nur online",
  ["guildmap.set.onlineOnlyTip"] = "Blendet Mitglieder aus, die die Gildenliste als offline zeigt.",
  ["guildmap.set.minLevel"] = "Stufe ab",
  ["guildmap.set.maxLevel"] = "Stufe bis",
  ["guildmap.set.rank"] = "Rang",
  ["guildmap.set.own"] = "Deine eigene Position",
  ["guildmap.set.hideInstances"] = "In Instanzen ausblenden",
  ["guildmap.set.hideInstancesTip"] = "Blendet die Punkte von Gildenmitgliedern und Freunden in Dungeons, Raids und Schlachtfeldern aus.",
  ["guildmap.set.friendZones"] = "Spieler in ihrem Gebiet",
  ["guildmap.set.friendZonesTip"] = "Markiert das Gebiet von Gildenmitgliedern und Freunden, die online sind und ihre Position nicht teilen, wie Gilden- und Freundesliste es zeigen.",
})

local function setting(name)
  return GLG.SPEC[name][1]
end

local function toggle(view, name)
  local key = "guildmap.set." .. name
  local t = W.Toggle(view.content, {
    key = key,
    tooltip = key,
    tooltipText = key .. "Tip",
    get = function()
      return GLG.Current()[name]
    end,
    set = function(v)
      Store.set("settings." .. setting(name), v and true or false)
    end,
  })
  t.fgId = "guildmap-set-" .. name
  view.stack:Add(t, { height = 24, gap = 4 })
  return t
end

-- Whole numbers; `tip` is the locale key of the tooltip text.
local function slider(view, name, labelKey, format, tip)
  local control = W.Slider(view.content, {
    key = labelKey,
    min = GLG.SPEC[name][3],
    max = GLG.SPEC[name][4],
    step = 1,
    get = function()
      return GLG.Current()[name]
    end,
    set = function(v)
      v = math.floor(v + 0.5)
      Store.set("settings." .. setting(name), v)
      -- The level range never turns around: the other end follows.
      local other = name == "minLevel" and "maxLevel" or name == "maxLevel" and "minLevel" or nil
      local follow = other and GLG.Partner(name, v, tonumber(Store.get("settings." .. setting(other))))
      if follow then
        Store.set("settings." .. setting(other), follow)
      end
    end,
    format = format,
  })
  control.fgId = "guildmap-set-" .. name
  if tip then
    control.slider:HookScript("OnEnter", function(self)
      ns.ShowTooltip(self, L[labelKey], L[tip])
    end)
    control.slider:HookScript("OnLeave", ns.HideTooltip)
  end
  view.stack:Add(control, { height = 42, width = 320, gap = 4 })
  return control
end

local function percent(v)
  return string.format("%d %%", math.floor(v + 0.5))
end

local function number(v)
  return tostring(math.floor(v + 0.5))
end

local function dropdown(view, name, key, options, get, set)
  local control = W.Dropdown(view.content, {
    key = key,
    width = 240,
    options = options,
    get = get,
    set = set,
  })
  control.fgId = "guildmap-set-" .. name
  view.stack:Add(control, { height = 46, width = 240, gap = 4 })
  return control
end

function S.Add(view)
  ns.AddHeading(view, "guildmap.set.heading")
  ns.AddParagraph(view, "guildmap.set.hint", { role = "micro", color = "textMuted" })
  local recv = ns.OptInNotice.Banner(view.content, {
    fn = "guildMap",
    dir = "receive",
    aud = "guild",
    textKey = "wm.guild.needRecv",
  })
  view.stack:Add(recv, { gap = 6 })
  -- Who you see and who sees you, per group: the same table as the question on the map.
  ns.AddHeading(view, "mapshare.heading", { role = "ui" })
  local share = ns.MapSharePrompt.NewTable(view.content, {
    width = 280,
    get = function(group, column)
      return ns.MapSharePrompt.Current(group, column, false)
    end,
    set = ns.MapSharePrompt.Set,
  })
  share.fgId = "guildmap-set-share"
  view.stack:Add(share, { height = share:GetHeight(), width = 280, gap = 8 })
  toggle(view, "showWorld")
  toggle(view, "showMini")
  toggle(view, "onlineOnly")
  toggle(view, "friendZones")
  toggle(view, "hideInstances")
  -- Everything else is rarely changed: behind "More settings".
  local more = W.Accordion(view, { id = view.id or "map.guild" })
  slider(more, "worldSize", "guildmap.set.worldSize", percent, "guildmap.set.sizeTip")
  slider(more, "miniSize", "guildmap.set.miniSize", percent, "guildmap.set.sizeTip")
  toggle(more, "showClass")
  toggle(more, "showRank")
  toggle(more, "showLevel")
  toggle(more, "showName")
  toggle(more, "group")
  slider(more, "minLevel", "guildmap.set.minLevel", number)
  slider(more, "maxLevel", "guildmap.set.maxLevel", number)
  local ranks = {}
  ns.WorldMapGuildTab.FillRanks(ranks)
  dropdown(more, "rank", "guildmap.set.rank", ranks, function()
    return GLG.Current().rankFilter
  end, function(v)
    Store.set("settings." .. setting("rankFilter"), v)
  end)
  ns.AddHeading(more, "guildmap.set.own", { role = "ui" })
  local send = ns.OptInNotice.Banner(more.content, {
    fn = "guildMap",
    dir = "send",
    aud = "guild",
    textKey = "wm.guild.needSend",
  })
  send.fgId = "guildmap-set-sendNotice"
  more.stack:Add(send, { gap = 6 })
  local invisible = W.Toggle(more.content, {
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
  invisible.fgId = "guildmap-set-invisible"
  more.stack:Add(invisible, { height = 24, gap = 4 })
  local accuracy = {}
  for i, id in ipairs(ns.WorldMapGuildTab.ACCURACY) do
    accuracy[i] = { value = id, key = "wm.guild.accuracy." .. id }
  end
  dropdown(more, "accuracy", "wm.guild.accuracy", accuracy, ns.GuildMapComm.Accuracy, function(v)
    Store.set("settings.guildMapAccuracy", v)
  end)
end

ns.SettingsPage.Add(S.Add, "map", "map.guild")
