-- Cards of the group "Game UI": the features Tooltips (Modules/TooltipTweaks.lua), Unit frames
-- (Modules/UnitFrameTweaks.lua) and Spells (Modules/CastBarTweaks.lua). Every switch goes through
-- Store.set and the module follows through FG_SETTING_CHANGED, or applies it itself where the game's own
-- console variable is the one source (status text, target of target, cooldown numbers). The tooltip
-- options that used to sit in the cards Inventory, Flight master and the auction page moved here with
-- their keys and control ids unchanged.
local _, ns = ...
local W, Store = ns.W, ns.Store
local TT, UF, CB = ns.TooltipTweaks, ns.UnitFrameTweaks, ns.CastBarTweaks

local S = {}
ns.GameUiSettings = S

ns.AddLocale("enUS", {
  ["gameui.items.heading"] = "Item tooltips",
  ["gameui.units.heading"] = "Unit tooltips",
  ["gameui.tooltip.heading"] = "Position and more",
  ["gameui.frames.heading"] = "Look and text",
  ["gameui.size.heading"] = "Frame size",
  ["gameui.castbar.heading"] = "Cast bars",
  ["gameui.actions.heading"] = "Cooldowns and spell IDs",
  ["tipset.itemLevel"] = "Item level line",
  ["tipset.itemLevelTip"] = "Shows the item level of gear in its tooltip.",
  ["tipset.sellPrice"] = "Vendor sell price",
  ["tipset.sellPriceTip"] = "Adds the sell price where the game shows none.",
  ["tipset.itemId"] = "Item ID",
  ["tipset.itemIdTip"] = "Adds the item ID to item tooltips.",
  ["tipset.spellId"] = "Spell ID",
  ["tipset.spellIdTip"] = "Adds the spell ID to spell and buff tooltips.",
  ["tipset.unitTarget"] = "Target of the unit",
  ["tipset.unitTargetTip"] = "Shows who the unit is targeting.",
  ["tipset.classColor"] = "Class color for players",
  ["tipset.classColorTip"] = "Colors the name of a player by class.",
  ["tipset.guildRank"] = "Guild rank",
  ["tipset.guildRankTip"] = "Adds the guild rank to the guild line.",
  ["tipset.hideCombat"] = "Hide in combat",
  ["tipset.hideCombatTip"] = "Hides unit tooltips while you fight.",
  ["tipset.cursor"] = "Tooltip at the cursor",
  ["tipset.cursorTip"] = "Shows the standard tooltip at the mouse pointer.",
  ["tipset.scale"] = "Tooltip size",
  ["tipset.scaleTip"] = "Scales all tooltips of the game.",
  ["ufset.classBars"] = "Class colored health",
  ["ufset.classBarsTip"] = "Colors the health bars of players by class.",
  ["ufset.classIcons"] = "Class icons as portraits",
  ["ufset.classIconsTip"] = "Shows the class icon instead of a player portrait.",
  ["ufset.statusText"] = "Health and mana text",
  ["ufset.statusTextTip"] = "On player, target and party frames.",
  ["ufset.status.NONE"] = "Off",
  ["ufset.status.NUMERIC"] = "Numbers",
  ["ufset.status.PERCENT"] = "Percent",
  ["ufset.status.BOTH"] = "Both",
  ["ufset.targetOfTarget"] = "Target of target",
  ["ufset.targetOfTargetTip"] = "Shows the frame of your target's target.",
  ["ufset.scalePlayer"] = "Player frame size",
  ["ufset.scalePlayerTip"] = "Scales the player frame. Not in combat.",
  ["ufset.scaleTarget"] = "Target frame size",
  ["ufset.scaleTargetTip"] = "Scales the target frame. Not in combat.",
  ["ufset.scaleParty"] = "Party frame size",
  ["ufset.scalePartyTip"] = "Scales the party frames. Not in combat.",
  ["spellset.castTimer"] = "Time on the cast bar",
  ["spellset.castTimerTip"] = "Shows the seconds left while a spell is cast.",
  ["spellset.castIcon"] = "Spell icon on cast bar",
  ["spellset.castIconTip"] = "Shows the spell icon next to the cast bar.",
  ["spellset.targetBig"] = "Larger target cast bar",
  ["spellset.targetBigTip"] = "Enlarges the target's cast bar. Not in combat.",
  ["spellset.cooldowns"] = "Cooldown numbers",
  ["spellset.cooldownsTip"] = "Shows seconds on the action buttons.",
  ["spellset.spellIdHint"] = "Spell IDs in tooltips are a tooltip option.",
  ["spellset.spellIdOpen"] = "Open tooltip options",
  ["spells.cvarMissing"] = "This game version has no such option.",
})
ns.AddLocale("deDE", {
  ["gameui.items.heading"] = "Item-Tooltips",
  ["gameui.units.heading"] = "Einheiten-Tooltips",
  ["gameui.tooltip.heading"] = "Position und mehr",
  ["gameui.frames.heading"] = "Aussehen und Text",
  ["gameui.size.heading"] = "Fenstergröße",
  ["gameui.castbar.heading"] = "Zauberleisten",
  ["gameui.actions.heading"] = "Abklingzeiten und Zauber-IDs",
  ["tipset.itemLevel"] = "Itemlevel-Zeile",
  ["tipset.itemLevelTip"] = "Zeigt das Itemlevel von Ausrüstung im Tooltip.",
  ["tipset.sellPrice"] = "Händler-Verkaufspreis",
  ["tipset.sellPriceTip"] = "Fügt den Verkaufspreis hinzu, wo das Spiel keinen zeigt.",
  ["tipset.itemId"] = "Item-ID",
  ["tipset.itemIdTip"] = "Fügt die Item-ID zu Item-Tooltips hinzu.",
  ["tipset.spellId"] = "Zauber-ID",
  ["tipset.spellIdTip"] = "Fügt die Zauber-ID zu Zauber- und Buff-Tooltips hinzu.",
  ["tipset.unitTarget"] = "Ziel der Einheit",
  ["tipset.unitTargetTip"] = "Zeigt, wen die Einheit im Ziel hat.",
  ["tipset.classColor"] = "Klassenfarbe bei Spielern",
  ["tipset.classColorTip"] = "Färbt den Namen eines Spielers nach Klasse.",
  ["tipset.guildRank"] = "Gildenrang",
  ["tipset.guildRankTip"] = "Fügt den Gildenrang zur Gildenzeile hinzu.",
  ["tipset.hideCombat"] = "Im Kampf ausblenden",
  ["tipset.hideCombatTip"] = "Blendet Einheiten-Tooltips im Kampf aus.",
  ["tipset.cursor"] = "Tooltip am Mauszeiger",
  ["tipset.cursorTip"] = "Zeigt den Standard-Tooltip am Mauszeiger.",
  ["tipset.scale"] = "Tooltip-Größe",
  ["tipset.scaleTip"] = "Skaliert alle Tooltips des Spiels.",
  ["ufset.classBars"] = "Leisten in Klassenfarbe",
  ["ufset.classBarsTip"] = "Färbt die Lebensleisten von Spielern nach Klasse.",
  ["ufset.classIcons"] = "Klassensymbol als Porträt",
  ["ufset.classIconsTip"] = "Zeigt das Klassensymbol statt des Spielerporträts.",
  ["ufset.statusText"] = "Lebens- und Manatext",
  ["ufset.statusTextTip"] = "Auf Spieler-, Ziel- und Gruppenfenstern.",
  ["ufset.status.NONE"] = "Aus",
  ["ufset.status.NUMERIC"] = "Zahlen",
  ["ufset.status.PERCENT"] = "Prozent",
  ["ufset.status.BOTH"] = "Beides",
  ["ufset.targetOfTarget"] = "Ziel des Ziels",
  ["ufset.targetOfTargetTip"] = "Zeigt das Fenster für das Ziel deines Ziels.",
  ["ufset.scalePlayer"] = "Spielerfenster-Größe",
  ["ufset.scalePlayerTip"] = "Skaliert das Spielerfenster. Nicht im Kampf.",
  ["ufset.scaleTarget"] = "Zielfenster-Größe",
  ["ufset.scaleTargetTip"] = "Skaliert das Zielfenster. Nicht im Kampf.",
  ["ufset.scaleParty"] = "Gruppenfenster-Größe",
  ["ufset.scalePartyTip"] = "Skaliert die Gruppenfenster. Nicht im Kampf.",
  ["spellset.castTimer"] = "Zeit an der Zauberleiste",
  ["spellset.castTimerTip"] = "Zeigt beim Zaubern die Restzeit in Sekunden.",
  ["spellset.castIcon"] = "Zaubersymbol an Leiste",
  ["spellset.castIconTip"] = "Zeigt das Zaubersymbol neben der Zauberleiste.",
  ["spellset.targetBig"] = "Größere Ziel-Zauberleiste",
  ["spellset.targetBigTip"] = "Vergrößert die Zauberleiste des Ziels. Nicht im Kampf.",
  ["spellset.cooldowns"] = "Abklingzeit-Zahlen",
  ["spellset.cooldownsTip"] = "Zeigt Sekunden auf den Aktionsleisten-Tasten.",
  ["spellset.spellIdHint"] = "Zauber-IDs im Tooltip sind eine Tooltip-Option.",
  ["spellset.spellIdOpen"] = "Tooltip-Optionen öffnen",
  ["spells.cvarMissing"] = "Diese Spielversion kennt die Option nicht.",
})

local function add(view, control, id, height)
  control.fgId = id
  view.stack:Add(control, { height = height or 24, gap = 6 })
end

-- A switch on settings.<key>; opts.get and opts.set replace the stored value (an option that lives in the
-- game's console variables or under another key), opts.id keeps the control id of an option that moved.
local function toggle(view, key, opts)
  local labelKey = opts.label
  add(
    view,
    W.Toggle(view.content, {
      key = labelKey,
      tooltip = labelKey,
      tooltipText = opts.hint,
      get = opts.get or function()
        return TT.Option(key) == true
      end,
      set = opts.set or function(v)
        Store.set("settings." .. key, v == true)
      end,
    }),
    opts.id or ("gameui-" .. key)
  )
end

local function percent(view, key, id, label, apply)
  local slider = W.Slider(view.content, {
    key = label,
    tooltip = label,
    tooltipText = label .. "Tip",
    min = TT.SCALE_MIN,
    max = TT.SCALE_MAX,
    step = TT.SCALE_STEP,
    applyOn = apply and "release" or nil,
    get = function()
      return tonumber(TT.Option(key)) or 100
    end,
    set = function(v)
      if apply and not apply(v) then
        ns.RefreshUI()
        return
      end
      Store.set("settings." .. key, v)
    end,
    format = function(v)
      return string.format("%d%%", math.floor(v + 0.5))
    end,
  })
  add(view, slider, id, 42)
end

-- Tooltips ------------------------------------------------------------------------------------------------

local function itemsCard(view)
  ns.AddHeading(view, "gameui.items.heading")
  toggle(view, "tipItemLevel", { label = "tipset.itemLevel", hint = "tipset.itemLevelTip" })
  toggle(view, "tipSellPrice", { label = "tipset.sellPrice", hint = "tipset.sellPriceTip" })
  toggle(view, "tipItemId", { label = "tipset.itemId", hint = "tipset.itemIdTip" })
  -- Moved here from the card Inventory and the auction page, same keys.
  toggle(view, "inventoryTooltip", {
    label = "inv.set.enable",
    id = "inventory-inventoryTooltip",
    get = function()
      return ns.Inventory.Option("inventoryTooltip") ~= false
    end,
  })
  toggle(view, "priceDb.tooltip", {
    label = "inv.set.priceTooltip",
    id = "inventory-priceTooltip",
    get = function()
      return Store.get("settings.priceDb.tooltip") ~= false
    end,
  })
  local more = W.Accordion(view, { id = view.id or "tooltips.items" })
  for _, key in ipairs({ "inventoryCurrentFirst", "inventoryColors" }) do
    toggle(more, key, {
      label = key == "inventoryColors" and "inv.set.colors" or "inv.set.currentFirst",
      id = "inventory-" .. key,
      get = function()
        return ns.Inventory.Option(key) ~= false
      end,
    })
  end
end

local function unitsCard(view)
  ns.AddHeading(view, "gameui.units.heading")
  toggle(view, "tipUnitTarget", { label = "tipset.unitTarget", hint = "tipset.unitTargetTip" })
  toggle(view, "tipClassColor", { label = "tipset.classColor", hint = "tipset.classColorTip" })
  toggle(view, "tipGuildRank", { label = "tipset.guildRank", hint = "tipset.guildRankTip" })
  toggle(view, "tipHideCombat", { label = "tipset.hideCombat", hint = "tipset.hideCombatTip" })
end

local function tooltipCard(view)
  ns.AddHeading(view, "gameui.tooltip.heading")
  toggle(view, "tipCursor", { label = "tipset.cursor", hint = "tipset.cursorTip" })
  percent(view, "tipScale", "gameui-tipScale", "tipset.scale")
  toggle(view, "tipSpellId", { label = "tipset.spellId", hint = "tipset.spellIdTip" })
  -- The flight time line of the flight master's tooltip, moved here from the card Flight master.
  toggle(view, "flightTooltip", {
    label = "flightlabel.tooltip",
    id = "setting-flightTooltip",
    get = function()
      return Store.get("settings.flightTooltip") and true or false
    end,
  })
end

-- Unit frames ---------------------------------------------------------------------------------------------

local function framesCard(view)
  ns.AddHeading(view, "gameui.frames.heading")
  toggle(view, "ufClassBars", { label = "ufset.classBars", hint = "ufset.classBarsTip" })
  toggle(view, "ufClassIcons", { label = "ufset.classIcons", hint = "ufset.classIconsTip" })
  local options = {}
  for _, mode in ipairs(UF.STATUS_MODES) do
    options[#options + 1] = { value = mode, key = "ufset.status." .. mode }
  end
  add(
    view,
    W.Dropdown(view.content, {
      key = "ufset.statusText",
      tooltip = "ufset.statusText",
      tooltipText = "ufset.statusTextTip",
      width = 200,
      options = options,
      get = UF.StatusMode,
      set = UF.SetStatusMode,
    }),
    "gameui-statusText",
    46
  )
  toggle(view, "ufTargetOfTarget", {
    label = "ufset.targetOfTarget",
    hint = "ufset.targetOfTargetTip",
    get = UF.TargetOfTarget,
    set = UF.SetTargetOfTarget,
  })
end

local function sizeCard(view)
  ns.AddHeading(view, "gameui.size.heading")
  for _, group in ipairs({ "player", "target", "party" }) do
    local def = UF.GROUPS[group]
    local label = "ufset.scale" .. group:gsub("^%l", string.upper)
    percent(view, def.option, "gameui-" .. def.option, label, function(v)
      if UF.Blocked() then
        return false
      end
      Store.set("settings." .. def.option, v)
      UF.ApplyScale(group)
      return true
    end)
  end
end

-- Spells --------------------------------------------------------------------------------------------------

local function castBarCard(view)
  ns.AddHeading(view, "gameui.castbar.heading")
  toggle(view, "castTimer", { label = "spellset.castTimer", hint = "spellset.castTimerTip" })
  toggle(view, "castIcon", { label = "spellset.castIcon", hint = "spellset.castIconTip" })
  toggle(view, "castTargetBig", {
    label = "spellset.targetBig",
    hint = "spellset.targetBigTip",
    set = function(v)
      if UF.Blocked() then
        return
      end
      Store.set("settings.castTargetBig", v == true)
      CB.ApplyTargetSize()
    end,
  })
end

local function actionsCard(view)
  ns.AddHeading(view, "gameui.actions.heading")
  ns.AddParagraph(view, "spellset.spellIdHint", { role = "micro", color = "textMuted" })
  local open = W.Action(view.content, {
    label = "act.show",
    icon = "open",
    tooltip = "spellset.spellIdOpen",
    width = 220,
    height = 28,
    opens = true,
    onClick = function()
      ns.SettingsPage.Select("tooltips", "tooltips.general", "gameui-tipSpellId")
    end,
  })
  open.fgId = "button-gameui-spellIdOpen"
  view.stack:Add(open, { height = 28, width = 220 })
  toggle(view, "castCooldowns", {
    label = "spellset.cooldowns",
    hint = "spellset.cooldownsTip",
    get = CB.CooldownNumbers,
    set = CB.SetCooldownNumbers,
  })
end

ns.SettingsPage.Add(itemsCard, "tooltips", "tooltips.items")
ns.SettingsPage.Add(unitsCard, "tooltips", "tooltips.units")
ns.SettingsPage.Add(tooltipCard, "tooltips", "tooltips.general")
ns.SettingsPage.Add(framesCard, "unitframes", "unitframes.look")
ns.SettingsPage.Add(sizeCard, "unitframes", "unitframes.size")
ns.SettingsPage.Add(castBarCard, "spells", "spells.castbar")
ns.SettingsPage.Add(actionsCard, "spells", "spells.actions")
