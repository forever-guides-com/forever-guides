-- Page "Gear planner": the character with its equipment slots around it. A click on a slot lists items for the
-- level and class of the player, grouped by source (quest reward, world quest, dungeon drop, world drop, crafted,
-- vendor), each with its required level, where it comes from and a "New" mark when it beats the worn item.
-- Rules: GearPlanLogic.lua. Data is the data the add-on ships (instance loot and quests, world quests and world
-- drops, recipes, vendors); the lists are built per slot on
-- the first click and cached. Reads only, nothing here is protected, so the page works in combat.
local _, ns = ...
local Theme = ns.Theme
local W, L, K, GP, I = ns.W, ns.L, ns.PageKit, ns.GearPlanLogic, ns.ItemInfo

ns.AddLocale("enUS", {
  ["page.gearplan"] = "Gear planner",
  ["page.gearplan.sub"] = "Better gear for every slot",
  ["gearplan.intro"] = "Click a slot to see items for your level and class: quest rewards, dungeon drops, world drops, crafted items and vendor goods. The mark New shows items that beat the one you wear. The star puts an item on your wishlist.",
  ["gearplan.pick"] = "Click a slot to see suggestions.",
  ["gearplan.empty"] = "No suggestions for this slot at your level.",
  ["gearplan.head"] = "Suggestions: %s",
  ["gearplan.worn"] = "Worn: %s",
  ["gearplan.wornNone"] = "Nothing worn in this slot.",
  ["gearplan.count"] = "%d items",
  ["gearplan.pending.one"] = "1 more item is loading.",
  ["gearplan.pending.other"] = "%d more items are loading.",
  ["gearplan.kind.quest"] = "Quest rewards",
  ["gearplan.kind.wquest"] = "World quests",
  ["gearplan.kind.boss"] = "Dungeon drops",
  ["gearplan.kind.world"] = "World drops",
  ["gearplan.kind.craft"] = "Crafted",
  ["gearplan.kind.vendor"] = "Vendors",
  ["gearplan.new"] = "New",
  ["gearplan.level"] = "Level %d",
  ["gearplan.ilvl"] = "Item level %d",
  ["gearplan.src.quest"] = "Quest %s (%s)",
  ["gearplan.src.questBare"] = "Quest %s",
  ["gearplan.src.questId"] = "Quest %d",
  ["gearplan.src.world"] = "World drop in %s, from level %d",
  ["gearplan.src.worldBare"] = "World drop, from level %d",
  ["gearplan.src.rate"] = "%s (%s)",
  ["gearplan.src.more"] = "%s, +%d more",
  ["gearplan.open"] = "Show source",
  ["gearplan.open.tip"] = "Opens the page of the source.",
  ["gearplan.slot.tip"] = "Shows suggestions for this slot.",
  ["gearplan.slot.empty"] = "Empty",
})
ns.AddLocale("deDE", {
  ["page.gearplan"] = "Ausrüstungsplaner",
  ["page.gearplan.sub"] = "Bessere Ausrüstung für jeden Platz",
  ["gearplan.intro"] = "Klick auf einen Platz, um Items für deine Stufe und Klasse zu sehen: Questbelohnungen, Dungeon-Beute, Weltdrops, Hergestelltes und Händlerware. Die Marke Neu zeigt Items, die besser sind als dein getragenes. Der Stern setzt ein Item auf deine Wunschliste.",
  ["gearplan.pick"] = "Klick auf einen Platz, um Vorschläge zu sehen.",
  ["gearplan.empty"] = "Keine Vorschläge für diesen Platz auf deiner Stufe.",
  ["gearplan.head"] = "Vorschläge: %s",
  ["gearplan.worn"] = "Getragen: %s",
  ["gearplan.wornNone"] = "In diesem Platz trägst du nichts.",
  ["gearplan.count"] = "%d Items",
  ["gearplan.pending.one"] = "1 weiteres Item lädt noch.",
  ["gearplan.pending.other"] = "%d weitere Items laden noch.",
  ["gearplan.kind.quest"] = "Questbelohnungen",
  ["gearplan.kind.wquest"] = "Quests in der Welt",
  ["gearplan.kind.boss"] = "Dungeon-Beute",
  ["gearplan.kind.world"] = "Weltdrops",
  ["gearplan.kind.craft"] = "Hergestellt",
  ["gearplan.kind.vendor"] = "Händler",
  ["gearplan.new"] = "Neu",
  ["gearplan.level"] = "Stufe %d",
  ["gearplan.ilvl"] = "Itemlevel %d",
  ["gearplan.src.quest"] = "Quest %s (%s)",
  ["gearplan.src.questBare"] = "Quest %s",
  ["gearplan.src.questId"] = "Quest %d",
  ["gearplan.src.world"] = "Weltdrop in %s, ab Stufe %d",
  ["gearplan.src.worldBare"] = "Weltdrop, ab Stufe %d",
  ["gearplan.src.rate"] = "%s (%s)",
  ["gearplan.src.more"] = "%s, +%d weitere",
  ["gearplan.open"] = "Quelle zeigen",
  ["gearplan.open.tip"] = "Öffnet die Seite der Quelle.",
  ["gearplan.slot.tip"] = "Zeigt Vorschläge für diesen Platz.",
  ["gearplan.slot.empty"] = "Leer",
})

local P = {}
ns.GearPlanPage = P

local ROW = 64
local SLOT, GAP, DOLL_W, COL_GAP = 38, 6, 300, 14
local SIDE_ROWS = #GP.LEFT
local DOLL_H = SIDE_ROWS * SLOT + (SIDE_ROWS - 1) * GAP + 10 + SLOT
local WIDE_MIN = 560
-- Item requests to the client per pass: the rest follows with the next GET_ITEM_INFO_RECEIVED.
local MAX_REQUESTS = 80
local REFRESH_EVENTS = {
  "PLAYER_EQUIPMENT_CHANGED",
  "PLAYER_LEVEL_UP",
  "GET_ITEM_INFO_RECEIVED",
  "FG_INSTANCE_DATA",
  "FG_UI_REFRESHED",
  "PLAYER_REGEN_ENABLED",
}

-- Client reading ----------------------------------------------------------------------------------------

local function method(tableName, name)
  local t = tableName and rawget(_G, tableName)
  local f = type(t) == "table" and t[name] or rawget(_G, name)
  return type(f) == "function" and f or nil
end

local function call(f, ...)
  if not f then
    return nil
  end
  local ok, a, b, c, d, e, g, h = pcall(f, ...)
  if ok then
    return a, b, c, d, e, g, h
  end
end

local function inCombat()
  return call(rawget(_G, "InCombatLockdown")) == true
end

local function player()
  local _, class = call(rawget(_G, "UnitClass"), "player")
  local level = call(rawget(_G, "UnitLevel"), "player")
  return type(class) == "string" and class or "WARRIOR", type(level) == "number" and level or 1
end

local staticCache = {}
-- Items the client answered "does not exist" for: never listed, never asked again.
local failed = {}
local requests, requested = 0, {}

-- One load request per item, at most MAX_REQUESTS per pass (the rest follows with the next answer).
local function request(id)
  if not requested[id] and requests < MAX_REQUESTS then
    requested[id] = true
    requests = requests + 1
    call(method("C_Item", "RequestLoadItemDataByID"), id)
  end
end

local LOADING = { loading = true }

-- Facts of the item table that need no server answer. nil: no gear or no such item. LOADING: the client does not
-- know the item yet (items of the realm that are not in the local tables), it is requested and answers later.
local function static(id)
  local hit = staticCache[id]
  if hit ~= nil then
    return hit or nil
  end
  if failed[id] then
    return nil
  end
  local f = method("C_Item", "GetItemInfoInstant") or method(nil, "GetItemInfoInstant")
  if not f then
    return nil
  end
  local known, _, _, equipLoc, icon, classId, subClassId = call(f, id)
  if not known then
    request(id)
    return LOADING
  end
  local entry = type(equipLoc) == "string" and equipLoc ~= ""
      and { equipLoc = equipLoc, icon = icon, classId = classId, subClassId = subClassId }
    or false
  staticCache[id] = entry
  return entry or nil
end

-- Required level, item level and quality from the client cache; nil (and one request) while it is not cached,
-- false for an item the client does not have.
local function dynamic(id)
  if failed[id] then
    return false
  end
  local f = method("C_Item", "GetItemInfo") or method(nil, "GetItemInfo")
  local name, _, quality, ilvl, req = call(f, id)
  if name then
    return { req = req, ilvl = ilvl, quality = quality }
  end
  request(id)
  return nil
end

local function stats(id)
  local f = method("C_Item", "GetItemStats") or method(nil, "GetItemStats")
  local result = call(f, "item:" .. tostring(id))
  return type(result) == "table" and result or nil
end

local function worn(slotId)
  local id = call(method(nil, "GetInventoryItemID"), "player", slotId)
  if type(id) ~= "number" then
    return nil
  end
  local dyn = dynamic(id) or {}
  return { id = id, ilvl = dyn.ilvl, quality = dyn.quality }
end

-- Pool --------------------------------------------------------------------------------------------------

local pool, poolFor, poolPartial

-- Instance loot and quests, recipes and vendors. In combat only data that is loaded already is read (the
-- add-ons load after combat), such a pool is rebuilt on PLAYER_REGEN_ENABLED.
local function buildPool(level)
  local fight = inCombat()
  local instances
  local access = ns.InstanceDataAccess
  if access then
    local state = access.Ensure()
    poolPartial = state == access.STATUS.combat
  end
  instances = ns.Data and ns.Data.Instances
  local worldQuests, worldDrops = rawget(ns, "WorldQuests"), rawget(ns, "WorldDrops")
  local recipes = {}
  local R = ns.ProfessionRouteLogic
  for _, slug in ipairs(R and R.SLUGS or {}) do
    local list
    if fight then
      local all = rawget(ns, "RecipeData")
      local data = type(all) == "table" and all[slug]
      list = type(data) == "table" and data.list
      if not list then
        poolPartial = true
      end
    elseif ns.RecipeAccess then
      local _, cleaned = ns.RecipeAccess.Get(slug)
      list = cleaned
    end
    if list then
      recipes[#recipes + 1] = { slug = slug, list = list }
    end
  end
  local vendors
  if ns.VendorSource then
    if fight and not rawget(ns, "VendorData") then
      poolPartial = true
    else
      vendors = ns.VendorSource.Index(not fight)
    end
  end
  return GP.Pool({
    instances = instances,
    worldQuests = type(worldQuests) == "table" and worldQuests or nil,
    worldDrops = type(worldDrops) == "table" and worldDrops or nil,
    class = (player()),
    level = level,
    recipes = recipes,
    vendors = vendors,
    faction = K.PlayerFaction(),
  })
end

local function getPool(level)
  if not pool or poolFor ~= level then
    poolPartial = false
    pool, poolFor = buildPool(level), level
  end
  return pool
end

-- Texts -------------------------------------------------------------------------------------------------

local function slotName(slotId)
  return L["gs.slot." .. slotId]
end

-- Zone name of an area id from the client, nil when it does not know it.
local function zoneName(area)
  local name = type(area) == "number" and call(method("C_Map", "GetAreaInfo"), area)
  return type(name) == "string" and name ~= "" and name or nil
end

-- Title of a world quest: the name of the data, else what the client knows, else "Quest <id>".
local function questTitle(q)
  local name = ns.T(q.n)
  if name and name ~= "" then
    return name
  end
  local title = call(method("C_QuestLog", "GetTitleForQuestID"), q.id) or call(method("C_QuestLog", "GetQuestInfo"), q.id)
  if type(title) == "string" and title ~= "" then
    return title
  end
  return string.format(L["gearplan.src.questId"], q.id or 0)
end

local function sourceText(src)
  if src.kind == "wquest" then
    local zone = zoneName(src.quest.z)
    local title = questTitle(src.quest)
    return zone and string.format(L["gearplan.src.quest"], title, zone) or string.format(L["gearplan.src.questBare"], title)
  elseif src.kind == "world" then
    local zone, req = zoneName(src.drop.z), src.drop.l or 1
    local text = zone and string.format(L["gearplan.src.world"], zone, req) or string.format(L["gearplan.src.worldBare"], req)
    if type(src.drop.r) == "number" and ns.InstanceLootRow then
      text = string.format(L["gearplan.src.rate"], text, string.format(L["instances.loot.rate"], ns.InstanceLootRow.Percent(src.drop.r)))
    end
    return text
  elseif src.kind == "boss" then
    local inst = ns.T(src.inst.n) or ""
    local text = src.boss and string.format(L["wish.src.boss"], ns.T(src.boss.n) or "", inst) or inst
    if src.rate and ns.InstanceLootRow then
      text = string.format(L["gearplan.src.rate"], text, string.format(L["instances.loot.rate"], ns.InstanceLootRow.Percent(src.rate)))
    end
    return text
  elseif src.kind == "quest" then
    return string.format(L["gearplan.src.quest"], ns.T(src.quest.n) or "", ns.T(src.inst.n) or "")
  elseif src.kind == "craft" then
    local R = ns.ProfessionRouteLogic
    local name = R and R.Name(src.slug) or src.slug
    return src.skill and string.format(L["wish.src.craftSkill"], name, src.skill)
      or string.format(L["wish.src.craft"], name)
  end
  return string.format(L["wish.src.vendor"], src.vendor.name)
end

local function open(src)
  if src.kind == "vendor" then
    if ns.VendorsPage then
      ns.VendorsPage.OpenVendor(src.npc)
    end
  elseif src.route then
    ns.Router:navigate(src.route)
  end
end

local function itemRow(entry)
  local id = entry.id
  local name = I.name(id, nil, "#" .. id)
  local facts = static(id)
  local meta = {}
  if entry.req > 0 then
    meta[1] = string.format(L["gearplan.level"], entry.req)
  end
  local kind = ns.InstanceLootRow and ns.InstanceLootRow.Kind(id)
  if kind then
    meta[#meta + 1] = kind
  end
  local lines = {}
  if #meta > 0 then
    lines[1] = table.concat(meta, " · ")
  end
  local first = entry.sources[1]
  lines[#lines + 1] = sourceText(first)
  if #entry.sources > 1 then
    lines[#lines] = string.format(L["gearplan.src.more"], lines[#lines], #entry.sources - 1)
  end
  local actions = {}
  if first.route or first.kind == "vendor" then
    actions[#actions + 1] = {
      icon = "open",
      boxed = true,
      tooltip = L["gearplan.open"],
      tooltipText = L["gearplan.open.tip"],
      opens = true,
      onClick = function()
        open(first)
      end,
    }
  end
  local hex = I.qualityHex(entry.quality)
  return {
    id = id,
    title = name,
    titleHex = hex,
    iconFrame = { edge = hex and ("#" .. hex) or nil },
    icon = facts and facts.icon,
    meta = entry.ilvl and entry.ilvl > 0 and string.format(L["gearplan.ilvl"], entry.ilvl) or nil,
    sub = table.concat(lines, "\n"),
    wrapSub = true,
    badge = entry.new and { text = L["gearplan.new"], color = "success" } or nil,
    actions = actions,
    tooltipSpec = { link = "item:" .. id, title = name },
    open = function()
      open(first)
    end,
  }
end

-- The list rows of one source group, one per item. Every group has a list of its own: a list has one row height,
-- so a heading row inside it would stand as tall as an item row and leave a gap.
function P.GroupRows(group)
  local rows = {}
  for _, entry in ipairs(group.items) do
    rows[#rows + 1] = itemRow(entry)
  end
  return rows
end

-- Slot buttons --------------------------------------------------------------------------------------------

local function emptyTexture(slotId)
  for _, slot in ipairs(I.SLOTS) do
    if slot.id == slotId then
      local _, texture = call(method(nil, "GetInventorySlotInfo"), slot.name)
      return texture
    end
  end
end

local function qualityEdge(quality)
  local hex = quality and I.qualityHex(quality)
  if hex then
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
  end
  return Theme.rgb("textMuted")
end

local function createSlot(parent, slotId, onPick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(SLOT, SLOT)
  W.Fill(b, "surface", 1)
  b.edge = b:CreateTexture(nil, "BORDER")
  b.edge:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 2, -2)
  b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.ring = W.Border(b, "accent2", 1, 2)
  b.ring.show(false)
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(Theme.fillColor("hover"))
  b.slotId = slotId
  local function tip()
    if b.itemId then
      W.Tooltip.Show(b, { link = "item:" .. b.itemId, title = slotName(slotId) })
    else
      ns.ShowTooltip(b, slotName(slotId), L["gearplan.slot.tip"])
    end
  end
  b:SetScript("OnEnter", tip)
  b:SetScript("OnLeave", ns.HideTooltip)
  b.fgOnFocus, b.fgOnBlur = tip, ns.HideTooltip
  b.fgName = function()
    local item = b.itemId and I.name(b.itemId, nil, "#" .. b.itemId) or L["gearplan.slot.empty"]
    return slotName(slotId) .. ": " .. item
  end
  b:SetScript(
    "OnClick",
    ns.Wrap("gearplan-slot", function()
      onPick(slotId)
    end)
  )
  ns.Focus.register(b, function(self)
    self:Click()
  end)
  ns.Bind(b, function()
    b.edge:SetColorTexture(qualityEdge(b.quality))
  end)
  return b
end

local function paintSlot(b, selected)
  local id = worn(b.slotId)
  local quality = id and id.quality
  b.itemId, b.quality = id and id.id, quality
  local texture = call(method(nil, "GetInventoryItemTexture"), "player", b.slotId)
  b.icon:SetTexture(texture or emptyTexture(b.slotId))
  b.icon:SetDesaturated(texture == nil)
  b.edge:SetColorTexture(qualityEdge(quality))
  b.ring.show(selected)
end

-- Page --------------------------------------------------------------------------------------------------

local function build(container)
  local view = ns.NewPageView(container)
  local state = {}
  ns.PageState.Bind(view, state, { "slot" })
  local refresh, select

  ns.AddIntro(view, "gearplan.intro")
  local body = CreateFrame("Frame", nil, view.content)

  local doll = CreateFrame("Frame", nil, body)
  local slots = {}
  local function put(list, column)
    for row, slotId in ipairs(list) do
      local b = createSlot(doll, slotId, function(id)
        select(id)
      end)
      b.column, b.row = column, row
      slots[#slots + 1] = b
    end
  end
  put(GP.LEFT, "left")
  put(GP.RIGHT, "right")
  put(GP.BOTTOM, "bottom")
  local stage = W.Panel(doll)
  local model
  local okModel, created = pcall(CreateFrame, "PlayerModel", nil, stage)
  if okModel and type(created) == "table" and type(created.SetUnit) == "function" then
    model = created
    model:SetPoint("TOPLEFT", 16, -16)
    model:SetPoint("BOTTOMRIGHT", -16, 16)
  end
  local function placeDoll(width)
    local w = math.min(DOLL_W, width)
    doll:SetSize(w, DOLL_H)
    local step = SLOT + GAP
    local bottom = #GP.BOTTOM
    for _, b in ipairs(slots) do
      b:ClearAllPoints()
      if b.column == "left" then
        b:SetPoint("TOPLEFT", doll, "TOPLEFT", 0, -(b.row - 1) * step)
      elseif b.column == "right" then
        b:SetPoint("TOPRIGHT", doll, "TOPRIGHT", 0, -(b.row - 1) * step)
      else
        local span = bottom * SLOT + (bottom - 1) * GAP
        b:SetPoint("TOPLEFT", doll, "TOPLEFT", math.floor((w - span) / 2) + (b.row - 1) * step, -(SIDE_ROWS * step + 4))
      end
    end
    stage:ClearAllPoints()
    stage:SetPoint("TOPLEFT", doll, "TOPLEFT", SLOT + GAP, 0)
    stage:SetSize(math.max(20, w - 2 * (SLOT + GAP)), SIDE_ROWS * step - GAP)
  end

  local head = W.Text(body, { role = "h3", family = "heading", color = "accent2", wrap = true })
  local info = W.Text(body, { role = "ui", color = "textSecondary", wrap = true })
  local hint = W.Text(body, { key = "gearplan.pick", role = "ui", color = "textMuted", wrap = true })
  local groups = {}
  for _, kind in ipairs(GP.KINDS) do
    groups[kind] = {
      head = K.GroupHeader(body, {}),
      open = true,
      list = K.NewList(body, {
        look = "boxed",
        rowHeight = ROW,
        bind = function(item)
          return item
        end,
        -- The wishlist star is the trailing widget of the row.
        onBindRow = function(row, item)
          ns.WishlistStar.Bind(row, item.id)
          row.trailing = row.star
        end,
        onClick = function(item)
          if item.open then
            item.open()
          end
        end,
      }),
      count = 0,
    }
  end
  function body:fgGridLayout(width)
    local wide = width >= WIDE_MIN
    placeDoll(wide and width - 200 or width)
    doll:ClearAllPoints()
    doll:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    local x, w, y = 0, width, DOLL_H + COL_GAP
    if wide then
      local dollW = math.min(DOLL_W, width - 200)
      x, w, y = dollW + COL_GAP, width - dollW - COL_GAP, 0
    end
    local function text(fs, gap)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
      fs:SetWidth(w)
      y = y + math.max(math.ceil(fs:GetStringHeight()), 12) + gap
    end
    text(head, 4)
    text(info, 8)
    text(hint, 0)
    for _, kind in ipairs(GP.KINDS) do
      local g = groups[kind]
      if g.head:IsShown() then
        g.head:ClearAllPoints()
        g.head:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
        g.head:SetWidth(w)
        y = y + g.head:fgGridLayout(w) + 4
        if g.list:IsShown() then
          local h = g.count * K.scaledHeight(ROW)
          g.list:ClearAllPoints()
          g.list:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
          g.list:SetSize(w, math.max(1, h))
          y = y + h
        end
        y = y + 10
      end
    end
    y = math.max(y, wide and DOLL_H or 0)
    self:SetHeight(math.max(1, y))
    return math.max(1, y)
  end
  view.stack:Add(body, { gap = Theme.space.sm })

  local cache = {}
  local function result(slotId)
    local hit = cache[slotId]
    if hit then
      return hit
    end
    local class, level = player()
    requests = 0
    hit = GP.Suggest(getPool(level), slotId, {
      class = class,
      level = level,
      static = static,
      dynamic = dynamic,
      stats = stats,
      worn = worn(slotId),
    })
    cache[slotId] = hit
    return hit
  end

  -- Fills the list of every group of the result and hides the others (nil hides all).
  local function showGroups(found)
    local byKind = {}
    for _, g in ipairs(found and found.groups or {}) do
      byKind[g.kind] = g
    end
    for _, kind in ipairs(GP.KINDS) do
      local g, rows = groups[kind], byKind[kind] and P.GroupRows(byKind[kind]) or {}
      g.count = #rows
      g.head:Set({
        title = L["gearplan.kind." .. kind],
        counter = tostring(#rows),
        open = g.open,
        onToggle = function(isOpen)
          g.open = isOpen
          g.list:SetShown(g.count > 0 and isOpen)
          view:Layout()
        end,
      })
      g.head:SetShown(#rows > 0)
      g.list:SetShown(#rows > 0 and g.open)
      g.list:SetData(rows)
    end
  end

  function refresh()
    for _, b in ipairs(slots) do
      paintSlot(b, b.slotId == (state.slot or nil))
    end
    local slotId = state.slot or nil
    head:SetShown(slotId ~= nil)
    info:SetShown(slotId ~= nil)
    hint:SetShown(slotId == nil)
    if not slotId then
      showGroups(nil)
      view:Layout()
      return
    end
    local found = result(slotId)
    local current = worn(slotId)
    head:SetText(string.format(L["gearplan.head"], slotName(slotId)))
    local lines = {
      current and string.format(L["gearplan.worn"], I.name(current.id, nil, "#" .. current.id)) or L["gearplan.wornNone"],
      string.format(L["gearplan.count"], found.count),
    }
    if #found.pending > 0 then
      lines[#lines + 1] = #found.pending == 1 and L["gearplan.pending.one"]
        or string.format(L["gearplan.pending.other"], #found.pending)
    end
    info:SetText(table.concat(lines, "\n"))
    showGroups(found)
    hint:SetText(found.count == 0 and #found.pending == 0 and L["gearplan.empty"] or "")
    hint:SetShown(found.count == 0 and #found.pending == 0)
    view:Layout()
  end

  function select(slotId)
    state.slot = slotId
    refresh()
  end

  -- The model restarts its animation on every SetUnit, so it is set when the page opens and when the look of the
  -- player really changes, never with a list refresh.
  local function resetModel()
    if model then
      pcall(model.SetUnit, model, "player")
    end
  end
  function view:Show()
    cache = {}
    resetModel()
    refresh()
  end
  local key = {}
  local function later(event)
    if not container:IsVisible() then
      return
    end
    -- A rebuilt pool or a changed worn item invalidates every list, a new item answer only the lists still waiting.
    if event == "PLAYER_REGEN_ENABLED" and poolPartial then
      pool = nil
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
      resetModel()
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
      local cached = state.slot and cache[state.slot]
      if not (cached and #cached.pending > 0) then
        return
      end
    end
    ns.Debounce(key, 0.3, function()
      cache = {}
      refresh()
    end)
  end
  for _, event in ipairs(REFRESH_EVENTS) do
    ns.On(event, function(_, id, ok)
      if event == "GET_ITEM_INFO_RECEIVED" and ok == false and type(id) == "number" then
        failed[id] = true
      end
      later(event)
    end)
  end
  ns.On("UNIT_MODEL_CHANGED", function(_, unit)
    if unit == "player" and container:IsVisible() then
      resetModel()
    end
  end)
  ns.On("FG_WISHLIST_CHANGED", function()
    if container:IsVisible() and state.slot then
      local cached = cache[state.slot]
      if cached then
        showGroups(cached)
        view:Layout()
      end
    end
  end)
  return view
end

ns.RegisterPage({
  id = "gearplan",
  order = 225,
  group = "character",
  title = "page.gearplan",
  subtitle = "page.gearplan.sub",
  icon = ns.ICONS.gearplan,
  aliases = { "ausruestungsplaner", "ausrüstungsplaner", "gearplan", "gearplanner", "gear", "ausruestung", "ausrüstung" },
  build = build,
})
