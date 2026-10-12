-- Settings tab "Selling" (Modules/SellHelper.lua), in sections: general, rules by quality, binding,
-- keep options, protect list. Changes go through Store.set, the helper reads the values on every scan.
-- The protect list takes item ids typed in or a shift-click on an item while its field has the focus.
local _, ns = ...
local W, Store = ns.W, ns.Store
local Logic = ns.SellLogic

local S = {}
ns.SellSettings = S

ns.AddLocale("enUS", {
  ["sell.set.heading"] = "Selling",
  ["sell.set.hint"] = "Quality rules pick items, protection always wins.\nKept in any case: protect list, worn items, sets,\nlocked items and items without a price.\nThen binding and the keep options apply.",
  ["sell.sec.general"] = "General",
  ["sell.sec.quality"] = "Rules by quality",
  ["sell.sec.bind"] = "Binding",
  ["sell.sec.keep"] = "Keep",
  ["sell.sec.protect"] = "Protect list",
  ["sell.set.buttonHint"] = "Merchant button: a click sells what the rules\nselect, {key:sellSwap} swaps it (see below).",
  ["sell.set.click"] = "Click at the junk button",
  ["sell.click.quick"] = "Sell now ({key:sellSwap}: selection)",
  ["sell.click.select"] = "Open selection ({key:sellSwap}: sell now)",
  ["sell.set.confirmRare"] = "Confirm rare items",
  ["sell.set.confirmRareHint"] = "Rare (blue) or better in a quick sale:\nconfirmation with count and proceeds first",
  ["sell.set.gray"] = "Gray items (all)",
  ["sell.set.white"] = "White below item level",
  ["sell.set.green"] = "Green below item level",
  ["sell.set.blue"] = "Blue below item level",
  ["sell.set.epic"] = "Epic below item level",
  ["sell.set.whiteAll"] = "White items (all)",
  ["sell.set.greenAll"] = "Green items (all)",
  ["sell.set.blueAll"] = "Blue items (all)",
  ["sell.set.epicAll"] = "Epic items (all)",
  ["sell.set.levelHint"] = "Gray sells everything. Item level fields sell gear\nbelow the level you type. 0 = rule off.\nAn (all) switch sells every item of its quality and\noverrides the item level field below it.",
  ["sell.set.whiteAllHint"] = "Gear is sold too, upgrades are not kept",
  ["sell.set.greenAllHint"] = "Gear is sold too, upgrades are not kept",
  ["sell.set.blueAllHint"] = "Warning: all rare items are sold,\ngear and upgrades included",
  ["sell.set.epicAllHint"] = "Warning: all epic items are sold,\ngear and upgrades included",
  ["sell.rule.overridden"] = "Overridden by the (all) switch",
  ["sell.set.blueHint"] = "Warning: rare gear is sold below this level",
  ["sell.set.epicHint"] = "Warning: epic gear is sold below this level",
  ["sell.rule.off"] = "Off",
  ["sell.rule.on"] = "On: below %d",
  ["sell.set.bind"] = "Sell which items?",
  ["sell.bind.all"] = "All",
  ["sell.bind.unbound"] = "Unbound only",
  ["sell.bind.bound"] = "Bound only",
  ["sell.set.consumables"] = "Keep consumables",
  ["sell.set.reagents"] = "Keep crafting reagents",
  ["sell.set.upgrades"] = "Keep upgrades",
  ["sell.set.upgradesHint"] = "Gear at least as good as the worn one",
  ["sell.set.blizz"] = "Use the game's button",
  ["sell.set.blizzHint"] = 'Takes over "Sell all junk" in the merchant window.\nOur rules decide what is sold.',
  ["sell.set.native"] = "Game junk function",
  ["sell.set.nativeHint"] = "Only when all gray items are sold",
  ["sell.set.protect"] = "Item IDs, never sold",
  ["sell.set.protectHint"] = "Shift-click an item while typing\nor enter item IDs",
  ["sell.set.auto"] = "Auto-sell at merchant",
  ["sell.set.autoHint"] = "Sells on opening, no preview\nUp to 12 items, protection applies",
})
ns.AddLocale("deDE", {
  ["sell.set.heading"] = "Verkaufen",
  ["sell.set.hint"] = "Qualitätsregeln wählen Items, Schutz geht immer vor.\nImmer behalten: Schutzliste, Angelegtes, Sets,\ngesperrte Items und Items ohne Preis.\nDanach gelten Bindung und die Behalten-Optionen.",
  ["sell.sec.general"] = "Allgemein",
  ["sell.sec.quality"] = "Regeln nach Qualität",
  ["sell.sec.bind"] = "Bindung",
  ["sell.sec.keep"] = "Behalten",
  ["sell.sec.protect"] = "Schutzliste",
  ["sell.set.buttonHint"] = "Verkaufsknopf am Händler: Klick verkauft, was die\nRegeln auswählen, {key:sellSwap} tauscht (siehe unten).",
  ["sell.set.click"] = "Klick am Plunder-Knopf",
  ["sell.click.quick"] = "Schnell verkaufen ({key:sellSwap}: Auswahl)",
  ["sell.click.select"] = "Auswahl öffnen ({key:sellSwap}: schnell verkaufen)",
  ["sell.set.confirmRare"] = "Rückfrage: seltene Items",
  ["sell.set.confirmRareHint"] = "Selten (blau) oder besser im Schnellverkauf:\nerst Bestätigung mit Anzahl und Erlös",
  ["sell.set.gray"] = "Graue Items (alle)",
  ["sell.set.white"] = "Weiß unter Itemlevel",
  ["sell.set.green"] = "Grün unter Itemlevel",
  ["sell.set.blue"] = "Blau unter Itemlevel",
  ["sell.set.epic"] = "Episch unter Itemlevel",
  ["sell.set.whiteAll"] = "Weiße Items (alle)",
  ["sell.set.greenAll"] = "Grüne Items (alle)",
  ["sell.set.blueAll"] = "Blaue Items (alle)",
  ["sell.set.epicAll"] = "Epische Items (alle)",
  ["sell.set.levelHint"] = "Grau verkauft alles. Itemlevel-Felder verkaufen nur\nAusrüstung unter dem Level. 0 = Regel aus.\nEin Schalter (alle) verkauft jedes Item der Qualität\nund überstimmt das Itemlevel-Feld darunter.",
  ["sell.set.whiteAllHint"] = "Ausrüstung wird mitverkauft, Upgrades bleiben nicht",
  ["sell.set.greenAllHint"] = "Ausrüstung wird mitverkauft, Upgrades bleiben nicht",
  ["sell.set.blueAllHint"] = "Achtung: alle seltenen Items werden verkauft,\nauch Ausrüstung und Upgrades",
  ["sell.set.epicAllHint"] = "Achtung: alle epischen Items werden verkauft,\nauch Ausrüstung und Upgrades",
  ["sell.rule.overridden"] = "Vom Schalter (alle) überstimmt",
  ["sell.set.blueHint"] = "Achtung: seltene Ausrüstung wird darunter verkauft",
  ["sell.set.epicHint"] = "Achtung: epische Ausrüstung wird darunter verkauft",
  ["sell.rule.off"] = "Aus",
  ["sell.rule.on"] = "An: unter %d",
  ["sell.set.bind"] = "Welche Items verkaufen?",
  ["sell.bind.all"] = "Alle",
  ["sell.bind.unbound"] = "Nur nicht gebunden",
  ["sell.bind.bound"] = "Nur gebunden",
  ["sell.set.consumables"] = "Verbrauchsgüter behalten",
  ["sell.set.reagents"] = "Handwerksstoffe behalten",
  ["sell.set.upgrades"] = "Upgrades behalten",
  ["sell.set.upgradesHint"] = "Ausrüstung so gut wie die getragene",
  ["sell.set.blizz"] = "Blizzard-Knopf übernehmen",
  ["sell.set.blizzHint"] = 'Übernimmt "Alles Plunder verkaufen" im Händlerfenster.\nUnsere Regeln entscheiden, was verkauft wird.',
  ["sell.set.native"] = "Native Plunder-Funktion",
  ["sell.set.nativeHint"] = "Nur wenn alle grauen Items verkauft werden",
  ["sell.set.protect"] = "Item-IDs, nie verkauft",
  ["sell.set.protectHint"] = "Item beim Tippen per Shift-Klick einfügen\noder Item-IDs eintragen",
  ["sell.set.auto"] = "Automatisch verkaufen",
  ["sell.set.autoHint"] = "Verkauft beim Öffnen, ohne Vorschau\nBis 12 Items, Schutz gilt",
})

local FIELD_WIDTH = 320
local MAX_NAMES = 8
local SECTION_GAP = 18

-- Item qualities of the rows (0 gray, 1 white, 2 green, 3 blue, 4 epic): the label gets the color
-- of its quality, the quality name stays in the text.
local GRAY, WHITE, GREEN, BLUE, EPIC = 0, 1, 2, 3, 4

-- The quality rows below the gray switch: the "all" switch, then the item level field it overrides.
local QUALITY_ROWS = {
  {
    quality = WHITE,
    all = "sellWhiteAll",
    allLabel = "sell.set.whiteAll",
    allHint = "sell.set.whiteAllHint",
    level = "sellWhiteBelow",
    label = "sell.set.white",
  },
  {
    quality = GREEN,
    all = "sellGreenAll",
    allLabel = "sell.set.greenAll",
    allHint = "sell.set.greenAllHint",
    level = "sellGreenBelow",
    label = "sell.set.green",
  },
  {
    quality = BLUE,
    all = "sellBlueAll",
    allLabel = "sell.set.blueAll",
    allHint = "sell.set.blueAllHint",
    level = "sellBlueBelow",
    label = "sell.set.blue",
    hint = "sell.set.blueHint",
  },
  {
    quality = EPIC,
    all = "sellEpicAll",
    allLabel = "sell.set.epicAll",
    allHint = "sell.set.epicAllHint",
    level = "sellEpicBelow",
    label = "sell.set.epic",
    hint = "sell.set.epicHint",
  },
}

local protectBox, namesText

local function stored(key)
  local value = ns.db.settings[key]
  if value == nil then
    value = Store.defaults.settings[key]
  end
  return value
end

local function itemName(id)
  local get = rawget(_G, "C_Item")
  local f = type(get) == "table" and get.GetItemNameByID or rawget(_G, "GetItemInfo")
  if type(f) == "function" then
    local ok, name = pcall(f, id)
    if ok and type(name) == "string" and name ~= "" then
      return ns.ItemInfo.ColorName(name, ns.ItemInfo.quality(id))
    end
  end
  return "#" .. id
end

-- Names of the protected items, as far as the game knows them.
function S.NamesText()
  local ids, names = Logic.ParseIds(stored("sellProtect")), {}
  for i = 1, math.min(#ids, MAX_NAMES) do
    names[i] = itemName(ids[i])
  end
  local more = #ids > MAX_NAMES and (" +" .. (#ids - MAX_NAMES)) or ""
  return table.concat(names, ", ") .. more
end

local function paintNames()
  if namesText then
    W.SetText(namesText, nil, S.NamesText())
  end
end

-- Adds a shift-clicked item to the protect list. Only while the field has the focus.
function S.InsertLink(link)
  if not (protectBox and protectBox.edit:HasFocus()) then
    return false
  end
  local text = Logic.AddId(protectBox.edit:GetText(), link)
  protectBox.edit:SetText(text)
  Store.set("settings.sellProtect", text)
  paintNames()
  return true
end

-- A heading with room above it, except for the first one of the tab.
local function section(view, key)
  local items = view.stack.items
  local last = items[#items]
  if last then
    last.opts.gap = SECTION_GAP
  end
  ns.AddHeading(view, key)
end

-- A label in the color of an item quality.
local function qualityLabel(view, key, quality)
  local label = W.Text(view.content, { key = key, role = "ui", color = "textSecondary" })
  ns.Bind(label, function(fs)
    fs:SetText(ns.ItemInfo.ColorName(ns.L[key], quality))
  end)
  view.stack:Add(label, { gap = 4 })
end

-- Item level limit of one quality: the number field and, next to it, the state as text. While the
-- "all" switch of the quality (allKey) is on, the field is dimmed and locked, the switch wins.
local function levelField(view, key, label, quality, warning, allKey)
  qualityLabel(view, label, quality)
  local row = CreateFrame("Frame", nil, view.content)
  local status = W.Text(row, { role = "micro", color = "textSecondary" })
  local box
  local function overridden()
    return allKey ~= nil and stored(allKey) == true
  end
  local function paintStatus()
    if overridden() then
      status:SetText(ns.L["sell.rule.overridden"])
      return
    end
    local level = Logic.CleanLevel(stored(key))
    status:SetText(level > 0 and string.format(ns.L["sell.rule.on"], level) or ns.L["sell.rule.off"])
  end
  local function paintLock()
    local locked = overridden()
    box.edit:SetEnabled(not locked)
    box:SetAlpha(locked and 0.5 or 1)
    if locked then
      box.edit:ClearFocus()
    end
  end
  ns.Bind(status, paintStatus)
  local function commit(text)
    local level = Logic.CleanLevel(text)
    Store.set("settings." .. key, level)
    paintStatus()
    return level
  end
  box = W.EditBox(row, {
    onChange = commit,
    onEnter = function(text)
      box.edit:SetText(tostring(commit(text)))
    end,
  })
  box:SetPoint("TOPLEFT", row, "TOPLEFT")
  box:SetSize(120, 26)
  status:SetPoint("LEFT", box, "RIGHT", 10, 0)
  status:SetPoint("RIGHT", row, "RIGHT")
  box.edit:SetMaxLetters(4)
  box.edit:HookScript("OnEditFocusLost", function()
    box.edit:SetText(tostring(Logic.CleanLevel(stored(key))))
  end)
  box.fgId = "sell-" .. key
  function box:Refresh()
    if not self.edit:HasFocus() then
      self.edit:SetText(tostring(Logic.CleanLevel(stored(key))))
    end
    paintStatus()
    paintLock()
  end
  row.Refresh = function()
    box:Refresh()
  end
  box:Refresh()
  view.stack:Add(row, { height = 26, width = FIELD_WIDTH, gap = warning and 4 or 10 })
  if warning then
    ns.AddParagraph(view, warning, { role = "micro", color = "warning" })
  end
  return row
end

-- opts: hint (locale key, muted), warning (locale key, warning color), quality (colors the label),
-- onSet (called after a change).
local function toggle(view, key, label, opts)
  opts = opts or {}
  local t = W.Toggle(view.content, {
    key = label,
    quality = opts.quality,
    get = function()
      return stored(key) == true
    end,
    set = function(v)
      Store.set("settings." .. key, v)
      if opts.onSet then
        opts.onSet(v)
      end
    end,
  })
  t.fgId = "sell-" .. key
  local hint = opts.hint or opts.warning
  view.stack:Add(t, { height = 24, gap = hint and 2 or 6 })
  if hint then
    ns.AddParagraph(view, hint, { role = "micro", color = opts.warning and "warning" or "textMuted" })
  end
end

local function generalSection(view)
  section(view, "sell.sec.general")
  ns.AddParagraph(view, "sell.set.buttonHint", { role = "micro", color = "textMuted" })
  toggle(view, "sellBlizzButton", "sell.set.blizz", { hint = "sell.set.blizzHint" })
  local click = W.Dropdown(view.content, {
    key = "sell.set.click",
    width = 270,
    options = {
      { value = "quick", key = "sell.click.quick" },
      { value = "select", key = "sell.click.select" },
    },
    get = function()
      return stored("sellClickMode") == "select" and "select" or "quick"
    end,
    set = function(v)
      Store.set("settings.sellClickMode", v == "select" and "select" or "quick")
    end,
  })
  click.fgId = "sell-click"
  view.stack:Add(click, { height = 46, width = 270 })
  toggle(view, "sellConfirmRare", "sell.set.confirmRare", { hint = "sell.set.confirmRareHint" })
  toggle(view, "sellAuto", "sell.set.auto", { warning = "sell.set.autoHint" })
  toggle(view, "sellNative", "sell.set.native", { hint = "sell.set.nativeHint" })
end

local function qualitySection(view)
  section(view, "sell.sec.quality")
  ns.AddParagraph(view, "sell.set.levelHint", { role = "micro", color = "textMuted" })
  toggle(view, "sellGray", "sell.set.gray", { quality = GRAY })
  for _, def in ipairs(QUALITY_ROWS) do
    local field
    toggle(view, def.all, def.allLabel, {
      quality = def.quality,
      warning = def.allHint,
      onSet = function()
        field:Refresh()
      end,
    })
    field = levelField(view, def.level, def.label, def.quality, def.hint, def.all)
  end
end

local function bindSection(view)
  section(view, "sell.sec.bind")
  local bind = W.Dropdown(view.content, {
    key = "sell.set.bind",
    width = 240,
    options = {
      { value = "all", key = "sell.bind.all" },
      { value = "unbound", key = "sell.bind.unbound" },
      { value = "bound", key = "sell.bind.bound" },
    },
    get = function()
      return Logic.CleanBind(stored("sellBind"))
    end,
    set = function(v)
      Store.set("settings.sellBind", Logic.CleanBind(v))
    end,
  })
  bind.fgId = "sell-bind"
  view.stack:Add(bind, { height = 46, width = 240 })
end

local function keepSection(view)
  section(view, "sell.sec.keep")
  toggle(view, "sellKeepConsumables", "sell.set.consumables")
  toggle(view, "sellKeepReagents", "sell.set.reagents")
  toggle(view, "sellKeepUpgrades", "sell.set.upgrades", { hint = "sell.set.upgradesHint" })
end

local function protectSection(view)
  local s = view.stack
  section(view, "sell.sec.protect")
  s:Add(W.Text(view.content, { key = "sell.set.protect", role = "ui", color = "textSecondary" }), { gap = 4 })
  protectBox = W.EditBox(view.content, {
    onChange = function(text)
      Store.set("settings.sellProtect", text)
      paintNames()
    end,
    onEnter = function(text)
      local clean = Logic.JoinIds(Logic.ParseIds(text))
      Store.set("settings.sellProtect", clean)
      protectBox.edit:SetText(clean)
      paintNames()
    end,
  })
  protectBox.edit:SetMaxLetters(Logic.MAX_PROTECT * 10)
  protectBox.fgId = "sell-protect"
  function protectBox:Refresh()
    if not self.edit:HasFocus() then
      self.edit:SetText(stored("sellProtect") or "")
    end
    paintNames()
  end
  s:Add(protectBox, { height = 26, width = FIELD_WIDTH, gap = 4 })
  namesText = W.Text(view.content, { role = "micro", color = "textSecondary", wrap = true })
  s:Add(namesText, { gap = 4 })
  ns.AddParagraph(view, "sell.set.protectHint", { role = "micro", color = "textMuted" })
  protectBox:Refresh()
end

-- The sections in page order. A later section "Always sell (list)" belongs after the quality rules:
-- it selects items like a rule, the protections still win over it.
local SECTIONS = { generalSection, qualitySection, bindSection, keepSection, protectSection }

function S.Add(view)
  ns.AddHeading(view, "sell.set.heading")
  ns.AddParagraph(view, "sell.set.hint", { role = "micro", color = "textMuted" })
  -- On the settings page every further section is a card of its own.
  for i, build in ipairs(SECTIONS) do
    build(i > 1 and view.grid and view.grid:Card() or view)
  end
end

-- Both names: older clients know ChatEdit_InsertLink, newer ones ChatFrameUtil.InsertLink. Adding the
-- same id twice changes nothing.
local function hookInsert()
  if type(hooksecurefunc) ~= "function" then
    return
  end
  local onLink = ns.Wrap("sell-insert", S.InsertLink)
  if type(rawget(_G, "ChatEdit_InsertLink")) == "function" then
    pcall(hooksecurefunc, "ChatEdit_InsertLink", onLink)
  end
  local util = rawget(_G, "ChatFrameUtil")
  if type(util) == "table" and type(util.InsertLink) == "function" then
    pcall(hooksecurefunc, util, "InsertLink", onLink)
  end
end

hookInsert()
