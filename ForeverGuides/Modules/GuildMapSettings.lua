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
  ["guildmap.set.hint"] = "Members of your guild who share their position show as symbols. Nothing is shown or sent until sharing is on.",
  ["guildmap.set.showWorld"] = "Show on the world map",
  ["guildmap.set.showWorldTip"] = "Draws guild members on the world map, the zone maps, the continent maps and the add-on map.",
  ["guildmap.set.showMini"] = "Show on the minimap",
  ["guildmap.set.showMiniTip"] = "Draws guild members on the minimap.\nNo tooltip there, details are on the world map.",
  ["guildmap.set.worldSize"] = "Symbol size, world map",
  ["guildmap.set.miniSize"] = "Symbol size, minimap",
  ["guildmap.set.sizeTip"] = "From 50 to 200 percent of the normal size.",
  ["guildmap.set.showClass"] = "Class color",
  ["guildmap.set.showClassTip"] = "Colors the symbol by class. Off draws a neutral color, the shape stays the same.",
  ["guildmap.set.showRank"] = "Rank marks",
  ["guildmap.set.showRankTip"] = "Strokes above the symbol: three for the guild master, two and one for the next ranks.",
  ["guildmap.set.showLevel"] = "Show level",
  ["guildmap.set.showLevelTip"] = "Writes the level next to the symbol. Needs the guild list.",
  ["guildmap.set.showName"] = "Show name",
  ["guildmap.set.showNameTip"] = "Writes the name next to the symbol.",
  ["guildmap.set.group"] = "Group members close together",
  ["guildmap.set.groupTip"] = "Members whose symbols would touch become one symbol with a number. The tooltip lists them.",
  ["guildmap.set.onlineOnly"] = "Only online",
  ["guildmap.set.onlineOnlyTip"] = "Hides members that the guild list shows as offline.",
  ["guildmap.set.minLevel"] = "Level from",
  ["guildmap.set.maxLevel"] = "Level up to",
  ["guildmap.set.rank"] = "Rank",
  ["guildmap.set.own"] = "Your own position",
})
ns.AddLocale("deDE", {
  ["guildmap.set.heading"] = "Gildenmitglieder auf den Karten",
  ["guildmap.set.hint"] = "Mitglieder deiner Gilde, die ihre Position teilen, erscheinen als Symbole. Ohne eingeschaltetes Teilen wird nichts gezeigt oder gesendet.",
  ["guildmap.set.showWorld"] = "Auf der Weltkarte zeigen",
  ["guildmap.set.showWorldTip"] = "Zeichnet Gildenmitglieder auf der Weltkarte, den Zonen- und Kontinentkarten und der Addon-Karte.",
  ["guildmap.set.showMini"] = "Auf der Minikarte zeigen",
  ["guildmap.set.showMiniTip"] = "Zeichnet Gildenmitglieder auf der Minikarte.\nDort ohne Tooltip, Details auf der Weltkarte.",
  ["guildmap.set.worldSize"] = "Symbolgröße, Weltkarte",
  ["guildmap.set.miniSize"] = "Symbolgröße, Minikarte",
  ["guildmap.set.sizeTip"] = "Von 50 bis 200 Prozent der normalen Größe.",
  ["guildmap.set.showClass"] = "Klassenfarbe",
  ["guildmap.set.showClassTip"] = "Färbt das Symbol nach Klasse. Aus zeichnet eine neutrale Farbe, die Form bleibt gleich.",
  ["guildmap.set.showRank"] = "Rangmarken",
  ["guildmap.set.showRankTip"] = "Striche über dem Symbol: drei für den Gildenmeister, zwei und einer für die nächsten Ränge.",
  ["guildmap.set.showLevel"] = "Stufe zeigen",
  ["guildmap.set.showLevelTip"] = "Schreibt die Stufe neben das Symbol. Braucht die Gildenliste.",
  ["guildmap.set.showName"] = "Name zeigen",
  ["guildmap.set.showNameTip"] = "Schreibt den Namen neben das Symbol.",
  ["guildmap.set.group"] = "Nahe Mitglieder zusammenfassen",
  ["guildmap.set.groupTip"] = "Mitglieder, deren Symbole sich berühren würden, werden zu einem Symbol mit Zahl. Der Tooltip listet sie auf.",
  ["guildmap.set.onlineOnly"] = "Nur online",
  ["guildmap.set.onlineOnlyTip"] = "Blendet Mitglieder aus, die die Gildenliste als offline zeigt.",
  ["guildmap.set.minLevel"] = "Stufe ab",
  ["guildmap.set.maxLevel"] = "Stufe bis",
  ["guildmap.set.rank"] = "Rang",
  ["guildmap.set.own"] = "Deine eigene Position",
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

local function dropdown(view, key, options, get, set)
  local control = W.Dropdown(view.content, {
    key = key,
    width = 240,
    options = options,
    get = get,
    set = set,
  })
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
  toggle(view, "showWorld")
  toggle(view, "showMini")
  slider(view, "worldSize", "guildmap.set.worldSize", percent, "guildmap.set.sizeTip")
  slider(view, "miniSize", "guildmap.set.miniSize", percent, "guildmap.set.sizeTip")
  toggle(view, "showClass")
  toggle(view, "showRank")
  toggle(view, "showLevel")
  toggle(view, "showName")
  toggle(view, "group")
  toggle(view, "onlineOnly")
  slider(view, "minLevel", "guildmap.set.minLevel", number)
  slider(view, "maxLevel", "guildmap.set.maxLevel", number)
  local ranks = {}
  ns.WorldMapGuildTab.FillRanks(ranks)
  dropdown(view, "guildmap.set.rank", ranks, function()
    return GLG.Current().rankFilter
  end, function(v)
    Store.set("settings." .. setting("rankFilter"), v)
  end)
  ns.AddHeading(view, "guildmap.set.own", { role = "ui" })
  local send = ns.OptInNotice.Banner(view.content, {
    fn = "guildMap",
    dir = "send",
    aud = "guild",
    textKey = "wm.guild.needSend",
  })
  view.stack:Add(send, { gap = 6 })
  local invisible = W.Toggle(view.content, {
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
  view.stack:Add(invisible, { height = 24, gap = 4 })
  local accuracy = {}
  for i, id in ipairs(ns.WorldMapGuildTab.ACCURACY) do
    accuracy[i] = { value = id, key = "wm.guild.accuracy." .. id }
  end
  dropdown(view, "wm.guild.accuracy", accuracy, ns.GuildMapComm.Accuracy, function(v)
    Store.set("settings.guildMapAccuracy", v)
  end)
end

ns.SettingsPage.Add(S.Add, "map")
