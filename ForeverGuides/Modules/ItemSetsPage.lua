-- Page "Item sets": every armor and weapon set of Forever as a card (name, class, pieces owned, active
-- bonuses) with filters for class, category and name. A click opens the detail: the pieces with icon,
-- slot, state and source (with map and waypoint buttons) and the set bonuses with their thresholds.
-- Logic: ItemSetsLogic.lua, data: ForeverGuides_Itemsets (docs/ITEMSETS-FORMAT.md), loading: GuideKit.Load.
local _, ns = ...
local W, L, Theme, K = ns.W, ns.L, ns.Theme, ns.PageKit
local IL, GL, GK = ns.ItemSetsLogic, ns.GuideKitLogic, ns.GuideKit

local P = {}
ns.ItemSetsPage = P

ns.AddLocale("enUS", {
  ["page.itemsets"] = "Item sets",
  ["sets.intro"] = "All armor and weapon sets of Forever with their pieces, set bonuses and where each piece comes from. Your bags, bank and worn gear show how far you are with every set.",
  ["page.itemsets.sub"] = "All sets with pieces, bonuses and sources",
  ["sets.class"] = "Class",
  ["sets.classTip"] = "Shows the sets of one class. Sets for every class of an armor type are listed for the classes that wear it.",
  ["sets.classAll"] = "All classes",
  ["sets.category"] = "Category",
  ["sets.categoryTip"] = "Shows the sets of one kind of source.",
  ["sets.cat.all"] = "All categories",
  ["sets.cat.raid"] = "Raid",
  ["sets.cat.dungeon"] = "Dungeon",
  ["sets.cat.pvp"] = "PvP",
  ["sets.cat.crafted"] = "Crafted",
  ["sets.cat.world"] = "World and other",
  ["sets.cat.forever"] = "New in Forever",
  ["sets.search"] = "Search",
  ["sets.searchPh"] = "Set or piece name",
  ["sets.progress"] = "Only sets with my pieces",
  ["sets.progressTip"] = "Shows the sets of which at least one piece is worn, in your bags or in your bank.",
  ["sets.count"] = "%d sets",
  ["sets.countDone"] = "%d sets, %d complete",
  ["sets.empty"] = "No sets for this selection.",
  ["sets.owned"] = "%d of %d pieces",
  ["sets.ownedWorn"] = "%d of %d pieces, %d worn",
  ["sets.bonusActive"] = "%d of %d active",
  ["sets.bonusNone"] = "No bonus active",
  ["sets.allClasses"] = "All classes",
  ["sets.armor.cloth"] = "Cloth",
  ["sets.armor.leather"] = "Leather",
  ["sets.armor.mail"] = "Mail",
  ["sets.armor.plate"] = "Plate",
  ["sets.forever"] = "New in Forever",
  ["sets.open"] = "Source open",
  ["sets.openTip"] = "The addon knows no source for any piece of this set yet.",
  ["sets.requires"] = "%s, skill %d",
  ["sets.attr.level"] = "Level",
  ["sets.attr.where"] = "Found in",
  ["sets.attr.pieces"] = "Pieces",
  ["sets.attr.bonuses"] = "Bonuses",
  ["sets.attr.requires"] = "Requires",
  ["sets.back"] = "Back to the sets",
  ["sets.backTip"] = "Returns to the list of sets.",
  ["sets.bonusHead"] = "Set bonuses",
  ["sets.piecesHead"] = "Pieces",
  ["sets.bonusRow"] = "%d pieces",
  ["sets.bonusFallback"] = "Set bonus, the game shows its text",
  ["sets.bonus.active"] = "Active",
  ["sets.bonus.reachable"] = "Wear more",
  ["sets.bonus.locked"] = "Not reached",
  ["sets.state.equipped"] = "Worn",
  ["sets.state.owned"] = "Owned",
  ["sets.state.missing"] = "Missing",
  ["sets.src.boss"] = "%s: %s",
  ["sets.src.bossRate"] = "%s: %s (%s%%)",
  ["sets.src.trash"] = "%s: enemies of the instance",
  ["sets.src.quest"] = "Quest %s (%s)",
  ["sets.src.craft"] = "Crafted: %s",
  ["sets.src.craftSkill"] = "Crafted: %s from skill %d",
  ["sets.src.standing"] = "%s: %s",
  ["sets.src.vendor"] = "%s from vendor %s",
  ["sets.src.none"] = "Source not known yet",
  ["sets.src.more"] = "+%d more sources",
  ["sets.sep"] = " · ",
})
ns.AddLocale("deDE", {
  ["page.itemsets"] = "Itemsets",
  ["sets.intro"] = "Alle Rüstungs- und Waffensets von Forever mit ihren Teilen, Setboni und der Herkunft jedes Teils. Deine Taschen, die Bank und die getragene Ausrüstung zeigen, wie weit du bei jedem Set bist.",
  ["page.itemsets.sub"] = "Alle Sets mit Teilen, Boni und Herkunft",
  ["sets.class"] = "Klasse",
  ["sets.classTip"] = "Zeigt die Sets einer Klasse. Sets ohne Klassenbindung stehen bei den Klassen, die diese Rüstungsart tragen.",
  ["sets.classAll"] = "Alle Klassen",
  ["sets.category"] = "Kategorie",
  ["sets.categoryTip"] = "Zeigt die Sets einer Quellenart.",
  ["sets.cat.all"] = "Alle Kategorien",
  ["sets.cat.raid"] = "Raid",
  ["sets.cat.dungeon"] = "Dungeon",
  ["sets.cat.pvp"] = "PvP",
  ["sets.cat.crafted"] = "Hergestellt",
  ["sets.cat.world"] = "Welt und Sonstiges",
  ["sets.cat.forever"] = "Neu in Forever",
  ["sets.search"] = "Suchen",
  ["sets.searchPh"] = "Name von Set oder Teil",
  ["sets.progress"] = "Nur Sets mit meinen Teilen",
  ["sets.progressTip"] = "Zeigt die Sets, von denen mindestens ein Teil getragen wird, in deinen Taschen oder in der Bank liegt.",
  ["sets.count"] = "%d Sets",
  ["sets.countDone"] = "%d Sets, %d komplett",
  ["sets.empty"] = "Keine Sets für diese Auswahl.",
  ["sets.owned"] = "%d von %d Teilen",
  ["sets.ownedWorn"] = "%d von %d Teilen, %d getragen",
  ["sets.bonusActive"] = "%d von %d aktiv",
  ["sets.bonusNone"] = "Kein Bonus aktiv",
  ["sets.allClasses"] = "Alle Klassen",
  ["sets.armor.cloth"] = "Stoff",
  ["sets.armor.leather"] = "Leder",
  ["sets.armor.mail"] = "Kette",
  ["sets.armor.plate"] = "Platte",
  ["sets.forever"] = "Neu in Forever",
  ["sets.open"] = "Quelle offen",
  ["sets.openTip"] = "Für kein Teil dieses Sets kennt das Addon bisher eine Quelle.",
  ["sets.requires"] = "%s, Skill %d",
  ["sets.attr.level"] = "Stufe",
  ["sets.attr.where"] = "Zu finden in",
  ["sets.attr.pieces"] = "Teile",
  ["sets.attr.bonuses"] = "Boni",
  ["sets.attr.requires"] = "Benötigt",
  ["sets.back"] = "Zurück zu den Sets",
  ["sets.backTip"] = "Kehrt zur Liste der Sets zurück.",
  ["sets.bonusHead"] = "Setboni",
  ["sets.piecesHead"] = "Teile",
  ["sets.bonusRow"] = "%d Teile",
  ["sets.bonusFallback"] = "Setbonus, das Spiel zeigt den Text",
  ["sets.bonus.active"] = "Aktiv",
  ["sets.bonus.reachable"] = "Mehr tragen",
  ["sets.bonus.locked"] = "Nicht erreicht",
  ["sets.state.equipped"] = "Getragen",
  ["sets.state.owned"] = "Im Besitz",
  ["sets.state.missing"] = "Fehlt",
  ["sets.src.boss"] = "%s: %s",
  ["sets.src.bossRate"] = "%s: %s (%s%%)",
  ["sets.src.trash"] = "%s: Gegner der Instanz",
  ["sets.src.quest"] = "Quest %s (%s)",
  ["sets.src.craft"] = "Hergestellt: %s",
  ["sets.src.craftSkill"] = "Hergestellt: %s ab Skill %d",
  ["sets.src.standing"] = "%s: %s",
  ["sets.src.vendor"] = "%s bei Händler %s",
  ["sets.src.none"] = "Quelle noch nicht bekannt",
  ["sets.src.more"] = "+%d weitere Quellen",
  ["sets.sep"] = " · ",
})

local SET_ROW, PIECE_ROW, BONUS_ROW = 52, 72, 56
local SOURCE_LINES = 2
local SKILL_SLUG = { [164] = "blacksmithing", [165] = "leatherworking", [197] = "tailoring" }
local REFRESH_EVENTS = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED" }

local function lang()
  return ns.GetActiveLocale() == "deDE" and "de" or "en"
end

local function method(name)
  local f = rawget(_G, name)
  return type(f) == "function" and f or nil
end

-- Client reading ----------------------------------------------------------------------------------------

-- "equipped", "owned" (bags and bank) or nil. Both calls are guarded: a client without them says nil.
function P.State(itemId)
  local equipped, count = method("IsEquippedItem"), method("GetItemCount")
  if equipped then
    local ok, on = pcall(equipped, itemId)
    if ok and on then
      return "equipped"
    end
  end
  if count then
    local ok, n = pcall(count, itemId, true)
    if ok and type(n) == "number" and n > 0 then
      return "owned"
    end
  end
  return nil
end

local function ownClass()
  local unitClass = method("UnitClass")
  if unitClass then
    local ok, _, token = pcall(unitClass, "player")
    if ok and type(token) == "string" then
      return token
    end
  end
  return "all"
end

local function className(token)
  local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return type(names) == "table" and names[token] or token
end

-- Icon of an item from the client item table, no server answer needed.
local function iconOf(itemId)
  local api = rawget(_G, "C_Item")
  if type(api) == "table" and type(api.GetItemIconByID) == "function" then
    local ok, icon = pcall(api.GetItemIconByID, itemId)
    if ok and icon then
      return icon
    end
  end
  local instant = method("GetItemInfoInstant")
  if instant then
    local ok, _, _, _, _, icon = pcall(instant, itemId)
    if ok then
      return icon
    end
  end
  return nil
end

-- Text of a set bonus: the data text of the language, else the description the client builds, else a note.
local function bonusText(data, spell)
  local text = IL.BonusText(data, spell, lang())
  if text then
    return text
  end
  local api = rawget(_G, "C_Spell")
  local get = type(api) == "table" and api.GetSpellDescription or method("GetSpellDescription")
  if get then
    local ok, desc = pcall(get, spell)
    if ok and type(desc) == "string" and desc ~= "" then
      return desc
    end
  end
  return L["sets.bonusFallback"]
end

-- Texts -------------------------------------------------------------------------------------------------

local function setName(section)
  return ns.T(section.title) or section.id
end

local function pieceName(piece)
  return ns.ItemInfo.name(piece.id, piece.n, "#" .. tostring(piece.id))
end

local function standingName(tier)
  local label = rawget(_G, "FACTION_STANDING_LABEL" .. tostring(tier))
  return label or ("#" .. tostring(tier))
end

local function slotName(piece)
  local key = IL.SLOT_GLOBAL[piece.sl]
  return key and rawget(_G, key) or ""
end

local function sourceText(d)
  local place = ns.T(d.place) or ""
  if d.kind == "boss" then
    local boss = ns.T(d.boss) or ""
    if d.rate then
      return string.format(L["sets.src.bossRate"], place, boss, tostring(d.rate))
    end
    return string.format(L["sets.src.boss"], place, boss)
  elseif d.kind == "trash" then
    return string.format(L["sets.src.trash"], place)
  elseif d.kind == "quest" then
    return string.format(L["sets.src.quest"], ns.T(d.quest) or "", place)
  elseif d.kind == "craft" then
    local skill = ns.ProfessionRouteLogic and ns.ProfessionRouteLogic.Name(d.skill) or tostring(d.skill)
    if d.level then
      return string.format(L["sets.src.craftSkill"], skill, d.level)
    end
    return string.format(L["sets.src.craft"], skill)
  end
  local text = string.format(L["sets.src.standing"], ns.T(d.faction) or "", standingName(d.tier))
  if d.vendor then
    text = string.format(L["sets.src.vendor"], text, ns.T(d.vendor) or "")
  end
  return text
end

local function metaText(section)
  local parts = {}
  if type(section.cls) == "table" and #section.cls > 0 then
    local names = {}
    for i, token in ipairs(section.cls) do
      names[i] = className(token)
    end
    parts[#parts + 1] = table.concat(names, ", ")
  else
    parts[#parts + 1] = section.at and L["sets.armor." .. section.at] or L["sets.allClasses"]
  end
  parts[#parts + 1] = L["sets.cat." .. tostring(section.cat)]
  return table.concat(parts, L["sets.sep"])
end

-- List -------------------------------------------------------------------------------------------------

local function progressText(progress)
  return progress.equipped > 0 and string.format(L["sets.ownedWorn"], progress.owned, progress.total, progress.equipped)
    or string.format(L["sets.owned"], progress.owned, progress.total)
end

-- "#rrggbb" of a quality for the edge of an icon frame (nil without a known quality).
local function qualityEdge(quality)
  local hex = ns.ItemInfo.qualityHex(quality)
  return hex and ("#" .. hex) or nil
end

local function firstIcon(section)
  local piece = section.i and section.i[1]
  return piece and iconOf(piece.id) or nil
end

-- Sub line of a set row: class or armor type, category and the Forever and open-source notes.
local function subText(section)
  local parts = { metaText(section) }
  if IL.IsForever(section) then
    parts[#parts + 1] = L["sets.forever"]
  end
  if section.u then
    parts[#parts + 1] = L["sets.open"]
  end
  return table.concat(parts, L["sets.sep"])
end

-- Detail ------------------------------------------------------------------------------------------------

local function mapActions(d, label)
  local place = d and IL.Place(d, label)
  if not place then
    return nil
  end
  return {
    {
      icon = ns.ICONS.map,
      boxed = true,
      tooltip = L["guidekit.mapTip"],
      opens = true,
      onClick = function()
        K.PlaceOnMap(place)
      end,
    },
    {
      icon = W.MARKER_ICON,
      boxed = true,
      tooltip = L["guidekit.markerTip"],
      onClick = function()
        K.PlaceMarker(place)
      end,
    },
  }
end

local PIECE_DOT = { equipped = "done", owned = "ok", missing = "todo" }

-- Row spec of a piece: icon, name in the quality color, slot and state, the first sources. The map buttons
-- go to the first source that has a position.
local function pieceRow(data, section, progress, piece)
  local state = progress.states[piece.id]
  local sources, more = IL.PieceSources(piece, data, SOURCE_LINES)
  local lines = {}
  local first = L["sets.state." .. (state or "missing")]
  local slot = slotName(piece)
  lines[1] = slot ~= "" and (slot .. L["sets.sep"] .. first) or first
  for _, d in ipairs(sources) do
    lines[#lines + 1] = sourceText(d)
  end
  if #sources == 0 then
    lines[#lines + 1] = L["sets.src.none"]
  end
  if more > 0 then
    lines[#lines] = lines[#lines] .. L["sets.sep"] .. string.format(L["sets.src.more"], more)
  end
  -- The vendors page has a vendor under his English name when exactly one vendor carries it.
  local vendorNpc
  for _, d in ipairs(sources) do
    local en = type(d.vendor) == "table" and d.vendor.en
    vendorNpc = vendorNpc or (en and ns.VendorSource and ns.VendorSource.NpcByName(en)) or nil
  end
  local located
  for _, d in ipairs(sources) do
    if d.map then
      located = d
      break
    end
  end
  local name = pieceName(piece)
  local quality = piece.q or section.q
  local actions = mapActions(located, located and ns.T(located.place) or name) or {}
  local wished = ns.Wishlist.Has(piece.id)
  actions[#actions + 1] = {
    icon = wished and "star" or "star-outline",
    boxed = true,
    selected = wished,
    tooltip = L[wished and "wish.remove" or "wish.add"],
    tooltipText = L["wish.star.tip"],
    onClick = function()
      ns.Wishlist.Toggle(piece.id)
    end,
  }
  actions[#actions + 1] = {
    icon = "eye",
    boxed = true,
    tooltip = L["preview.open"],
    tooltipText = L["preview.openTip"],
    opens = true,
    onClick = function()
      ns.ModelPreview.OpenItem(piece.id)
    end,
  }
  return {
    title = name,
    titleHex = ns.ItemInfo.qualityHex(quality),
    iconFrame = { edge = qualityEdge(quality), desaturate = state == nil },
    icon = iconOf(piece.id),
    dot = { state = PIECE_DOT[state or "missing"], tip = L["sets.state." .. (state or "missing")] },
    sub = table.concat(lines, "\n"),
    wrapSub = true,
    subNpc = vendorNpc,
    actions = actions,
    tooltipSpec = { link = "item:" .. tostring(piece.id), title = name },
  }
end

local function bonusRow(data, b)
  return {
    level = string.format(L["sets.bonusRow"], b.n),
    levelColor = b.active and "success" or "textSecondary",
    title = L[b.active and "sets.bonus.active" or b.reachable and "sets.bonus.reachable" or "sets.bonus.locked"],
    sub = bonusText(data, b.spell),
    wrapSub = true,
    selected = b.active == true,
    inert = true,
  }
end

-- Page --------------------------------------------------------------------------------------------------

local function controls(view, state, onChange)
  local classOptions = { { value = "all", key = "sets.classAll" } }
  for _, token in ipairs(IL.CLASSES) do
    classOptions[#classOptions + 1] = { value = token, text = className(token) }
  end
  local categoryOptions = { { value = "all", key = "sets.cat.all" } }
  for _, cat in ipairs(IL.CATEGORIES) do
    categoryOptions[#categoryOptions + 1] = { value = cat, key = "sets.cat." .. cat }
  end
  categoryOptions[#categoryOptions + 1] = { value = "forever", key = "sets.cat.forever" }
  local search, progress
  local bar = K.FilterBar(view.content, {
    count = function()
      return (state.class ~= ownClass() and 1 or 0)
        + (state.category ~= "all" and 1 or 0)
        + (state.query ~= "" and 1 or 0)
        + (state.progress and 1 or 0)
    end,
    reset = function()
      state.class, state.category, state.query, state.progress = ownClass(), "all", "", false
      search.edit:SetText("")
      onChange()
    end,
  })
  local class = bar:AddDropdown({
    key = "sets.class",
    options = classOptions,
    tooltip = "sets.class",
    tooltipText = "sets.classTip",
    get = function()
      return state.class
    end,
    set = function(v)
      state.class = v
      onChange()
    end,
  })
  local category = bar:AddDropdown({
    key = "sets.category",
    options = categoryOptions,
    tooltip = "sets.category",
    tooltipText = "sets.categoryTip",
    get = function()
      return state.category
    end,
    set = function(v)
      state.category = v
      onChange()
    end,
  })
  search = bar:AddSearch({
    key = "sets.search",
    text = state.query,
    placeholder = "sets.searchPh",
    onChange = function(text)
      state.query = text
      onChange()
    end,
  })
  progress = bar:AddToggle({
    key = "sets.progress",
    tooltip = "sets.progress",
    tooltipText = "sets.progressTip",
    get = function()
      return state.progress
    end,
    set = function(v)
      state.progress = v
      onChange()
    end,
  })
  local refreshBar = bar.Refresh
  function bar:Refresh()
    for i, token in ipairs(IL.CLASSES) do
      classOptions[i + 1].text = className(token)
    end
    class.Refresh()
    category.Refresh()
    progress.Refresh()
    refreshBar(self)
  end
  return bar
end

-- Body of the page, called once the data is there. Returns the function that repaints list and detail.
function P.Render(view, data)
  local state = { class = ownClass(), category = "all", query = "", progress = false, detail = false }
  ns.PageState.Bind(view, state, { "class", "category", "query", "progress" }, "itemsets")
  local counts, byId = {}, {}
  for _, s in ipairs(data.sections) do
    byId[s.id] = s
  end
  local repaint
  local shown, selected = {}, nil
  local syncing = false

  local filterBar = controls(view, state, function()
    repaint()
    view:Layout()
  end)
  view.stack:Add(filterBar, { gap = Theme.space.md })
  local summary = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = Theme.space.sm })
  local empty = view.stack:Add(
    W.EmptyState(view.content, { text = "sets.empty", icon = "search", compact = true }),
    { gap = Theme.space.md }
  )

  -- The list is made before the master/detail shell so the keyboard reaches it before the detail.
  local list, split, paintDetail, layoutDetail
  list = K.NewList(view.content, {
    look = "boxed",
    rowHeight = SET_ROW,
    bind = function(section)
      local mine = selected ~= nil and selected.id == section.id
      return {
        title = setName(section),
        titleHex = ns.ItemInfo.qualityHex(section.q),
        sub = subText(section),
        meta = progressText(counts[section.id] or IL.Progress(section, P.State)),
        level = section.lv,
        iconFrame = { edge = qualityEdge(section.q), texture = firstIcon(section) },
        selected = mine,
        cursor = mine,
      }
    end,
    onClick = function(section)
      state.selected, state.detail = section.id, true
      selected = section
      list:SetData(shown)
      paintDetail()
      split:SetSelected(section)
      split:ShowDetail(true)
      view:Layout()
    end,
  })
  K.Anchor("FG.ItemSets.List", list)

  split = K.MasterDetail(view.content, {
    list = list,
    backKey = "sets.back",
    backTip = "sets.backTip",
    onToggle = function(on)
      if not syncing then
        state.detail = on
      end
    end,
    detail = function(width)
      return layoutDetail(width)
    end,
  })
  K.Anchor("FG.ItemSets.Detail", split.detail)
  local content = split.content

  -- Hero: first piece, name, facts and notes; the share icon sits at the top right.
  local hero = K.Hero(content, {})
  local actions = W.MapActionButtons(hero, { share = true })
  hero:SetActions(actions)

  local bonusCount, pieceCount = 0, 0
  local bonusList, pieceList, legend, bonusCard, pieceCard, previewSet
  bonusCard = K.SectionCard(content, {
    key = "sets.bonusHead",
    body = function(w)
      local h = bonusCount * K.scaledHeight(BONUS_ROW)
      bonusList:ClearAllPoints()
      bonusList:SetPoint("TOPLEFT", bonusCard.body, "TOPLEFT", 0, 0)
      bonusList:SetSize(w, h)
      return h
    end,
  })
  bonusList = K.NewList(bonusCard.body, {
    look = "boxed",
    rowHeight = BONUS_ROW,
    bind = function(item)
      return item
    end,
  })
  pieceCard = K.SectionCard(content, {
    key = "sets.piecesHead",
    body = function(w)
      -- The preview button leads the body (a button in the flush header band would touch the card edge).
      previewSet:ClearAllPoints()
      previewSet:SetPoint("TOPLEFT", pieceCard.body, "TOPLEFT", 0, 0)
      local y = previewSet:GetHeight() + Theme.space.sm
      legend:ClearAllPoints()
      legend:SetPoint("TOPLEFT", pieceCard.body, "TOPLEFT", 0, -y)
      legend:SetWidth(w)
      y = y + legend:fgGridLayout(w) + Theme.space.sm
      local h = pieceCount * K.scaledHeight(PIECE_ROW)
      pieceList:ClearAllPoints()
      pieceList:SetPoint("TOPLEFT", pieceCard.body, "TOPLEFT", 0, -y)
      pieceList:SetSize(w, h)
      return y + h
    end,
  })
  legend = K.StatusLegend(pieceCard.body, {
    states = {
      { state = "done", key = "sets.state.equipped" },
      { state = "ok", key = "sets.state.owned" },
      { state = "todo", key = "sets.state.missing" },
    },
  })
  pieceList = K.NewList(pieceCard.body, {
    look = "boxed",
    vendorLinks = true,
    rowHeight = PIECE_ROW,
    bind = function(item)
      return item
    end,
  })
  previewSet = W.Button(pieceCard.body, {
    key = "preview.open",
    width = 120,
    height = 24,
    tooltip = "preview.open",
    tooltipText = "preview.openTip",
    opens = true,
    onClick = function()
      local items = {}
      for _, piece in ipairs(selected and IL.SortedPieces(selected) or {}) do
        items[#items + 1] = piece.id
      end
      ns.ModelPreview.OpenSet({ name = selected and setName(selected), items = items })
    end,
  })

  -- Places the pieces come from (at most three names), for the "Found in" line of the hero.
  local function where(section)
    local seen, names = {}, {}
    for _, piece in ipairs(section.i or {}) do
      for _, d in ipairs((IL.PieceSources(piece, data, SOURCE_LINES))) do
        local name = ns.T(d.place)
        if name and not seen[name] then
          seen[name] = true
          names[#names + 1] = name
        end
      end
    end
    table.sort(names)
    for i = #names, 4, -1 do
      names[i] = nil
    end
    return table.concat(names, ", ")
  end

  function paintDetail()
    local section = selected
    hero:SetShown(section ~= nil)
    bonusCard:SetShown(false)
    pieceCard:SetShown(section ~= nil)
    if not section then
      return
    end
    local progress = counts[section.id] or IL.Progress(section, P.State)
    hero:SetPortrait({ texture = firstIcon(section), edge = qualityEdge(section.q), name = setName(section) })
    hero:SetTitle(setName(section))
    hero:SetSubtitle(metaText(section))
    local total, active = #(section.b or {}), IL.ActiveCount(section, progress)
    local attrs = {}
    if section.lv then
      attrs[#attrs + 1] = { labelKey = "sets.attr.level", value = tostring(section.lv) }
    end
    local at = where(section)
    if at ~= "" then
      attrs[#attrs + 1] = { labelKey = "sets.attr.where", value = at }
    end
    attrs[#attrs + 1] = { labelKey = "sets.attr.pieces", value = progressText(progress) }
    if total > 0 then
      attrs[#attrs + 1] = {
        labelKey = "sets.attr.bonuses",
        value = active > 0 and string.format(L["sets.bonusActive"], active, total) or L["sets.bonusNone"],
        valueColor = active > 0 and "success" or nil,
      }
    end
    if section.sk then
      local slug = SKILL_SLUG[section.sk[1]]
      local name = slug and ns.ProfessionRouteLogic and ns.ProfessionRouteLogic.Name(slug) or tostring(section.sk[1])
      attrs[#attrs + 1] = {
        labelKey = "sets.attr.requires",
        value = string.format(L["sets.requires"], name, section.sk[2]),
      }
    end
    hero:SetAttrs(attrs)
    local tags = {}
    if IL.IsForever(section) then
      tags[#tags + 1] = { text = L["sets.forever"], color = "info" }
    end
    if section.u then
      tags[#tags + 1] = { text = L["sets.open"], color = "warning", tip = L["sets.openTip"] }
    end
    hero:SetTags(tags)
    actions:SetShare("itemsets/" .. section.id)
    local bonusRows = {}
    for _, b in ipairs(IL.Bonuses(section, progress)) do
      bonusRows[#bonusRows + 1] = bonusRow(data, b)
    end
    bonusCount = #bonusRows
    bonusCard:SetShown(bonusCount > 0)
    bonusCard:SetCount(bonusCount)
    bonusList:SetData(bonusRows)
    local pieceRows = {}
    for _, piece in ipairs(IL.SortedPieces(section)) do
      pieceRows[#pieceRows + 1] = pieceRow(data, section, progress, piece)
    end
    pieceCount = #pieceRows
    pieceCard:SetCount(pieceCount)
    pieceList:SetData(pieceRows)
  end

  function layoutDetail(width)
    if not selected then
      return 0
    end
    local gap = Theme.space.lg
    hero:ClearAllPoints()
    hero:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    local y = hero:fgLayout(width) + gap
    if bonusCount > 0 then
      bonusCard:ClearAllPoints()
      bonusCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
      y = y + bonusCard:fgLayout(width) + gap
    end
    pieceCard:ClearAllPoints()
    pieceCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    return y + pieceCard:fgLayout(width)
  end
  view.stack:Add(split, { gap = Theme.space.lg })

  ns.On("FG_WISHLIST_CHANGED", function()
    if selected and split:IsVisible() then
      paintDetail()
    end
  end)

  local function readCounts()
    counts = {}
    for _, s in ipairs(data.sections) do
      counts[s.id] = IL.Progress(s, P.State)
    end
  end

  function repaint()
    filterBar:Refresh()
    local search = ns.TrainerSearchLogic
    shown = IL.Sort(
      IL.Filter(data.sections, {
        class = state.class,
        category = state.category,
        query = state.query,
        progress = state.progress,
        counts = counts,
        words = search and search.Words,
        match = search and search.Match,
      }),
      counts,
      setName
    )
    local done = 0
    for _, s in ipairs(shown) do
      local c = counts[s.id]
      done = done + (c and c.total > 0 and c.owned == c.total and 1 or 0)
    end
    summary:SetText(
      done > 0 and string.format(L["sets.countDone"], #shown, done) or string.format(L["sets.count"], #shown)
    )
    empty:SetAction(filterBar:IsFiltered() and W.EMPTY_RESET or nil, function()
      filterBar:Reset()
    end)
    empty:SetShown(#shown == 0)
    split:SetShown(#shown > 0)
    -- The chosen set stays while the filters still list it, else the first one of the list.
    local want = state.selected
    selected = nil
    for _, s in ipairs(shown) do
      if s.id == want then
        selected = s
      end
    end
    selected = selected or shown[1]
    state.selected = selected and selected.id or nil
    state.detail = state.detail and selected ~= nil
    list:SetData(shown)
    paintDetail()
    syncing = true
    split:SetSelected(selected)
    split:ShowDetail(state.detail)
    syncing = false
  end

  local function refresh()
    readCounts()
    repaint()
    view:Layout()
  end
  readCounts()
  return repaint, refresh, state, byId
end

-- Page builder: loads the data add-on on the first show and keeps the owned state fresh while visible.
function P.Build(container)
  local view = ns.NewPageView(container)
  local repaint, refresh, empty, banner, setState, setsById
  local pendingSet
  local key = {}
  local function show()
    local data, status = GK.Load("itemsets")
    banner:Update(status == GL.STATUS.disabled)
    if data and not repaint then
      repaint, refresh, setState, setsById = P.Render(view, data)
    end
    -- A shared set (route itemsets/<id>) opens its detail once the data is there.
    if setState and pendingSet then
      if setsById[pendingSet] then
        setState.selected, setState.detail = pendingSet, true
      end
      pendingSet = nil
    end
    if not data then
      GK.SetEmptyStatus(empty, status)
    end
    empty:SetShown(not data)
    if data then
      refresh()
    else
      view:Layout()
    end
  end
  ns.AddIntro(view, "sets.intro", { gap = Theme.space.md })
  banner = ns.PackageUI.Banner(view.content, GL.GUIDES.itemsets.addon, {
    onLoaded = show,
    onResize = function()
      view:Layout()
    end,
  })
  view.stack:Add(banner, { gap = Theme.space.md })
  empty = view.stack:Add(GK.EmptyState(view.content, GL.STATUS.missing), { gap = 0 })
  -- Page link: the set whose detail is open.
  function view:ShareState()
    return setState and setState.detail and setState.selected and { setState.selected } or {}
  end
  function view:Show(params)
    pendingSet = params and params[1]
    show()
  end
  ns.On("FG_UI_REFRESHED", function()
    if container:IsVisible() then
      show()
    end
  end)
  for _, event in ipairs(REFRESH_EVENTS) do
    ns.On(event, function()
      if refresh and container:IsVisible() then
        ns.Debounce(key, 0.3, refresh)
      end
    end)
  end
  return view
end

-- Not registered (so no menu, search, link or editor knows it) unless ns.showHiddenStubs is set before this
-- file runs; the code and the data stay.
if ns.showHiddenStubs then
  ns.Commands.PAGE_AREA.itemsets = "character"
  ns.RegisterPage({
    id = "itemsets",
    order = 525,
    group = "inventory",
    title = "page.itemsets",
    subtitle = "page.itemsets.sub",
    icon = ns.ICONS.itemsets,
    aliases = { "sets", "itemsets", "item-sets", "ruestungssets", "rüstungssets", "setteile", "tier", "set" },
    build = P.Build,
  })
end
