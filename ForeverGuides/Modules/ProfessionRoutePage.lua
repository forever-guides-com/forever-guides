-- Page "Profession route" (/fg berufsroute): pick a profession, see the skill route step by step
-- (skill range, recipe, crafts, reagents, where the recipe comes from), the current step marked, done
-- steps dimmed, the trainers per rank with a map link, and the buttons for the shopping list window and
-- the small shopping list (ProfessionTracker.lua).
-- The data comes from the data add-on (Modules/ProfessionData.lua), the logic is in
-- ProfessionRouteLogic.lua, own skill and saved choices in ProfessionShop.lua.
local _, ns = ...
local W, L, Theme, K = ns.W, ns.L, ns.Theme, ns.PageKit
local R, S, Data = ns.ProfessionRouteLogic, ns.ProfessionShop, ns.ProfessionRouteData

local P = {}
ns.ProfessionRoutePage = P

local CONTROL_GAP = 12
local DROPDOWN_W, FIELD_W, BUTTON_W = 220, 90, 170
local BAR_H = 10

ns.AddLocale("enUS", {
  ["page.professionroute"] = "Profession route",
  ["profroute.intro"] = "Skill route per profession, step by step.",
  ["profroute.profession"] = "Profession",
  ["profroute.target"] = "Target skill",
  ["profroute.targetPh"] = "Maximum",
  ["profroute.from"] = "Start skill",
  ["profroute.fromPh"] = "Automatic",
  ["profroute.shop"] = "Shopping list",
  ["profroute.shopTip"] = "Opens the shopping list window.",
  ["profroute.addRange"] = "Start to target to the list",
  ["profroute.addRangeTip"] = "Adds start to target. Empty fields: whole route.",
  ["profroute.addPicked"] = "Selection to list (%d)",
  ["profroute.addPickedTip"] = "Adds the materials of the picked steps.",
  ["profroute.pick"] = "Pick steps",
  ["profroute.pickOff"] = "Stop picking",
  ["profroute.pickTip"] = "Shows a switch in front of every step.",
  ["profroute.pickStep"] = "Step on the shopping list",
  ["profroute.progress"] = "%s: skill %d of %d, step %d of %d",
  ["profroute.finished"] = "%s: route finished (skill %d)",
  ["profroute.notOwned"] = "%s: not learned, route from the start",
  ["profroute.routeHeading"] = "Route",
  ["profroute.trainersHeading"] = "Trainers",
  ["profroute.state.current"] = "Current",
  ["profroute.state.done"] = "Done",
  ["profroute.area.before"] = "Before the start skill",
  ["profroute.area.after"] = "After the target skill",
  ["profroute.area.alternatives"] = "Alternatives",
  ["profroute.alt.intro"] = "These routes replace the named range of the main route.",
  ["profroute.alt.intro2"] = "Worth it when the materials are cheaper.",
  ["profroute.alt.head"] = "%d to %d: %s",
  ["profroute.crafts"] = "%dx",
  ["profroute.perCraft"] = "%d per craft",
  ["profroute.recipeIcon"] = "Recipe",
  ["profroute.itemIcon"] = "Finished item",
  ["profroute.src.trainer"] = "Trainer (%s): %s",
  ["profroute.src.trainerNone"] = "Trainer (%s)",
  ["profroute.src.item"] = "Recipe item",
  ["profroute.rankHead"] = "%s (up to %d)",
  ["profroute.mapTip"] = "Shows the place on the map.",
  ["profroute.markerTip"] = "Sets a waypoint with an arrow.",
  ["profroute.noSteps"] = "No steps in the data.",
  ["profroute.rank.apprentice"] = "Apprentice",
  ["profroute.rank.journeyman"] = "Journeyman",
  ["profroute.rank.expert"] = "Expert",
  ["profroute.rank.artisan"] = "Artisan",
  ["profroute.rank.master"] = "Master",
  ["profroute.rank.grandmaster"] = "Grand Master",
})
ns.AddLocale("deDE", {
  ["page.professionroute"] = "Berufsroute",
  ["profroute.intro"] = "Skillroute je Beruf, Schritt für Schritt.",
  ["profroute.profession"] = "Beruf",
  ["profroute.target"] = "Zielskill",
  ["profroute.targetPh"] = "Maximum",
  ["profroute.from"] = "Startskill",
  ["profroute.fromPh"] = "Automatisch",
  ["profroute.shop"] = "Einkaufsliste",
  ["profroute.shopTip"] = "Öffnet das Fenster der Einkaufsliste.",
  ["profroute.addRange"] = "Start bis Ziel zur Einkaufsliste",
  ["profroute.addRangeTip"] = "Fügt Start bis Ziel hinzu. Leere Felder: ganze Route.",
  ["profroute.addPicked"] = "Ausgewählte zur Einkaufsliste (%d)",
  ["profroute.addPickedTip"] = "Fügt die Materialien der gewählten Schritte hinzu.",
  ["profroute.pick"] = "Schritte auswählen",
  ["profroute.pickOff"] = "Auswahl beenden",
  ["profroute.pickTip"] = "Zeigt vor jedem Schritt einen Schalter.",
  ["profroute.pickStep"] = "Schritt auf die Einkaufsliste",
  ["profroute.progress"] = "%s: Skill %d von %d, Schritt %d von %d",
  ["profroute.finished"] = "%s: Route fertig (Skill %d)",
  ["profroute.notOwned"] = "%s: nicht gelernt, Route ab Anfang",
  ["profroute.routeHeading"] = "Route",
  ["profroute.trainersHeading"] = "Lehrer",
  ["profroute.state.current"] = "Aktuell",
  ["profroute.state.done"] = "Erledigt",
  ["profroute.area.before"] = "Vor dem Startskill",
  ["profroute.area.after"] = "Nach dem Zielskill",
  ["profroute.area.alternatives"] = "Alternativen",
  ["profroute.alt.intro"] = "Diese Routen ersetzen den genannten Bereich der Hauptroute.",
  ["profroute.alt.intro2"] = "Lohnt sich, wenn die Materialien günstiger sind.",
  ["profroute.alt.head"] = "%d bis %d: %s",
  ["profroute.crafts"] = "%dx",
  ["profroute.perCraft"] = "%d pro Herstellung",
  ["profroute.recipeIcon"] = "Rezept",
  ["profroute.itemIcon"] = "Fertiges Item",
  ["profroute.src.trainer"] = "Lehrer (%s): %s",
  ["profroute.src.trainerNone"] = "Lehrer (%s)",
  ["profroute.src.item"] = "Rezeptitem",
  ["profroute.rankHead"] = "%s (bis %d)",
  ["profroute.mapTip"] = "Zeigt den Ort auf der Karte.",
  ["profroute.markerTip"] = "Setzt einen Wegpunkt mit Pfeil.",
  ["profroute.noSteps"] = "Keine Schritte in den Daten.",
  ["profroute.rank.apprentice"] = "Lehrling",
  ["profroute.rank.journeyman"] = "Geselle",
  ["profroute.rank.expert"] = "Experte",
  ["profroute.rank.artisan"] = "Fachmann",
  ["profroute.rank.master"] = "Meister",
  ["profroute.rank.grandmaster"] = "Großmeister",
})

local function rankName(rank)
  local key = "profroute.rank." .. tostring(rank)
  local text = L[key]
  return text ~= key and text or tostring(rank)
end

local function iconPath(icon)
  return type(icon) == "string" and icon ~= "" and ("Interface\\Icons\\" .. icon)
    or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Name of the recipe spell from the client, nil when it cannot tell.
local function spellName(id)
  if type(id) ~= "number" then
    return nil
  end
  local api = rawget(_G, "C_Spell")
  local get = type(api) == "table" and api.GetSpellName or rawget(_G, "GetSpellInfo")
  if type(get) ~= "function" then
    return nil
  end
  local ok, name = pcall(get, id)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

local function trainersOf(data, rank)
  for _, r in ipairs(type(data.ranks) == "table" and data.ranks or {}) do
    if r.rank == rank then
      return r.trainers or {}
    end
  end
  return {}
end

-- The item a recipe spell makes, from the recipe database: { id, icon } or nil (enchanting, add-on off).
-- The reverse index is kept per data table, so a reloaded database builds a new one.
local productIndex = setmetatable({}, { __mode = "k" })
local function productOf(slug, spell)
  if type(spell) ~= "number" or not ns.RecipeAccess then
    return nil
  end
  local data, list = ns.RecipeAccess.Get(slug)
  if not data then
    return nil
  end
  local index = productIndex[data]
  if not index then
    index = {}
    for _, r in ipairs(list or {}) do
      if type(r.s) == "number" and type(r.i) == "number" then
        index[r.s] = r.i
      end
    end
    productIndex[data] = index
  end
  local id = index[spell]
  if not id then
    return nil
  end
  local info = type(data.items) == "table" and data.items[id] or {}
  return { id = id, icon = info.ico }
end

-- Recipe icon and the icon of the finished item in front of the step title.
local STEP_ICON = 26
local STEP_ICON_GAP = 4

-- The recipe icon is the recipe scroll for every step; the finished item has its own icon next to it.
local RECIPE_TEXTURE = "Interface\\Icons\\INV_Scroll_03"

-- Icon of the made item: the data icon, else the client's.
local function productTexture(product)
  if product.icon then
    return iconPath(product.icon)
  end
  local shop = ns.ProfessionShop
  return shop and shop.ItemIcon(product.id) or iconPath(nil)
end

-- A square icon button showing a game texture in its own colors (W.Action tints its icon with the theme).
local function newIconButton(parent, nameKey, id)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(STEP_ICON, STEP_ICON)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 1, -1)
  b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints(b.icon)
  hover:SetColorTexture(Theme.fillColor("selected"))
  W.Border(b, "accentDim", 1)
  b.fgNameKey, b.fgId = nameKey, id
  function b.fgName()
    return L[nameKey]
  end
  b:SetScript("OnLeave", ns.HideTooltip)
  return b
end

-- Where the recipe of a step comes from.
local function sourceText(data, step)
  if step.src == "item" then
    return L["profroute.src.item"]
  end
  local names = {}
  for i, t in ipairs(trainersOf(data, step.rank)) do
    if i > 2 then
      break
    end
    names[#names + 1] = t.loc and (t.n .. ", " .. t.loc) or t.n
  end
  local rank = rankName(step.rank)
  if #names == 0 then
    return string.format(L["profroute.src.trainerNone"], rank)
  end
  return string.format(L["profroute.src.trainer"], rank, table.concat(names, "; "))
end

-- Step rows ---------------------------------------------------------------------------------------

-- Room of the skill range ("225-300" in full, never cut): measured from the widest range at the font in use.
local LEFT_MIN = 84
local function rangeWidth(fs)
  local text = fs:GetText()
  fs:SetText("300-300")
  local w = fs:GetStringWidth() or 0
  fs:SetText(text)
  return math.max(LEFT_MIN, math.ceil(w) + 12)
end
local SIDE = 12
-- Room of the switch in front of a step while steps are picked.
local PICK_W = 80
-- Picking steps for the shopping list: on while the player picks, the picked steps by their table.
local PICK = { on = false, steps = {} }
local CRAFTERS_SIDE = 22
local HEAD_H = 26
local HEAD_GAP = 8
-- Light fills that carry one black text color, the same as the areas of the level list.
local AREA_COLORS = {
  before = "sectionLearned",
  after = "sectionLocked",
  alternatives = "sectionLearned",
  altblock = "sectionLocked",
}
-- Areas the user opened this session ("before" / "after" / "alternatives"), closed by default.
local opened = {}
-- Alternative blocks the user folded this session by slug and index, expanded while their area is open.
local folded = {}

-- Header of a collapsed or opened area, a real button so the keyboard reaches it.
local function newAreaHead(row)
  local head = CreateFrame("Button", nil, row)
  head:SetPoint("TOPLEFT")
  head:SetPoint("BOTTOMRIGHT", 0, HEAD_GAP)
  head.bg = head:CreateTexture(nil, "BACKGROUND")
  head.bg:SetAllPoints()
  local hover = head:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  -- Lightens the light area color, the black text only gains contrast.
  hover:SetColorTexture(1, 1, 1, 0.3)
  head.label = W.Text(head, { role = "h3", family = "heading", color = "sectionText" })
  head.label:SetPoint("LEFT", 8, 0)
  head.label:SetPoint("RIGHT", -8, 0)
  head:SetScript(
    "OnClick",
    ns.Wrap("profroute-area", function()
      if row.onToggle then
        row.onToggle()
      end
    end)
  )
  head:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["levels.area.tip"])
  end)
  head:SetScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(head, function(self)
    self:Click()
  end)
  return head
end

local function newStepRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(ns.Theme.fillColor())
  row.mark = row:CreateTexture(nil, "ARTWORK")
  row.mark:SetPoint("TOPLEFT")
  row.mark:SetPoint("BOTTOMLEFT")
  row.mark:SetWidth(3)
  row.mark:SetColorTexture(ns.Theme.fillColor())
  row.range = W.Text(row, { role = "ui", family = "heading" })
  row.state = W.Text(row, { role = "micro", justify = "RIGHT" })
  row.title = W.Text(row, { role = "ui", wrap = true })
  row.sub = W.Meta(row, { wrap = true })
  row.chips = K.ChipRow(row)
  row.src = W.Text(row, { role = "micro", color = "textMuted", wrap = true })
  row.head = newAreaHead(row)
  row.pick = W.Toggle(row, {
    key = "profroute.pickStep",
    compact = true,
    tooltip = "profroute.pickStep",
    get = function()
      return row.step ~= nil and PICK.steps[row.step] == true
    end,
    set = function(on)
      if row.step then
        PICK.steps[row.step] = on or nil
        ns.Emit("FG_PROFROUTE_PICKED")
      end
    end,
  })
  row.pick:SetWidth(72)
  row.pick.fgId = "profroute-pick"
  row.pick:Hide()
  -- Who in the guild can make the recipe of the step.
  row.crafters = ns.CraftersView.Action(row, { size = CRAFTERS_SIDE, id = "profroute-crafters" })
  -- The hint says what a click does: open the recipe in the profession window, or what is missing for it.
  local function craftHint()
    local craft = ns.ProfessionCraft
    local status = craft.Status(S.Slug(), row.spell)
    return status == "ok" and L["craft.open"] or craft.StatusText(S.Slug(), status)
  end
  local function recipeTip(self)
    if row.spell then
      W.Tooltip.Show(self, { spell = row.spell, title = row.recipe, hint = craftHint() })
    end
  end
  local function openCraft()
    if row.spell then
      ns.ProfessionCraft.Open(S.Slug(), row.spell)
    end
  end
  row:SetScript("OnEnter", recipeTip)
  row:SetScript("OnClick", openCraft)
  -- The recipe icon repeats the tooltip of the row; the item icon shows the finished item alone.
  row.recipeIcon = newIconButton(row, "profroute.recipeIcon", "profroute-recipe-icon")
  row.recipeIcon.icon:SetTexture(RECIPE_TEXTURE)
  row.recipeIcon:SetScript("OnEnter", recipeTip)
  row.recipeIcon:SetScript("OnClick", openCraft)
  -- The hammer on the recipe icon: the game opens its window only from a secure click, so the hover lays
  -- the shared secure button of ProfessionCraft over it; without one (no recipe, combat) a click says why.
  row.badge = CreateFrame("Button", nil, row.recipeIcon)
  row.badge:SetSize(14, 14)
  row.badge:SetPoint("BOTTOMRIGHT", 2, -2)
  row.badge:SetFrameLevel(row.recipeIcon:GetFrameLevel() + 2)
  row.badge.icon = row.badge:CreateTexture(nil, "OVERLAY")
  row.badge.icon:SetAllPoints()
  row.badge.icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
  row.badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  W.Border(row.badge, "accent2", 1)
  row.badge.fgNameKey, row.badge.fgId = "craft.badge", "profroute-craft-badge"
  function row.badge.fgName()
    return L["craft.badge"]
  end
  row.badge:SetScript("OnEnter", function(self)
    if row.spell and not ns.ProfessionCraft.ArmBadge(self, S.Slug(), row.spell) then
      ns.ShowTooltip(self, L["craft.badge"], craftHint())
    end
  end)
  row.badge:SetScript("OnLeave", ns.HideTooltip)
  row.badge:SetScript("OnClick", openCraft)
  row.itemIcon = newIconButton(row, "profroute.itemIcon", "profroute-item-icon")
  row.itemIcon:SetScript("OnEnter", function(self)
    if row.product then
      ns.ProfessionShop.ShowItemTooltip(self, row.product.id)
    end
  end)

  row:SetScript("OnLeave", ns.HideTooltip)
  function row:fgLayout(width)
    if self.isHead then
      return K.scaledHeight(HEAD_H) + HEAD_GAP
    end
    if self.isNote then
      self.sub:ClearAllPoints()
      self.sub:SetPoint("TOPLEFT", SIDE, -4)
      self.sub:SetWidth(math.max(40, width - SIDE * 2))
      return self.sub:GetStringHeight() + 12
    end
    local pickW = self.pick:IsShown() and PICK_W or 0
    local LEFT_W = rangeWidth(self.range)
    local textW = math.max(40, width - LEFT_W - SIDE * 2 - pickW)
    self.pick:ClearAllPoints()
    self.pick:SetPoint("TOPLEFT", SIDE, -5)
    self.range:ClearAllPoints()
    self.range:SetPoint("TOPLEFT", SIDE + pickW, -8)
    self.range:SetWidth(LEFT_W - 8)
    self.state:ClearAllPoints()
    self.state:SetPoint("TOPRIGHT", -SIDE, -8)
    self.state:SetWidth(80)
    self.crafters:ClearAllPoints()
    self.crafters:SetPoint("TOPRIGHT", -SIDE - 84, -6)
    local x, y = LEFT_W + SIDE + pickW, -8
    self.recipeIcon:ClearAllPoints()
    self.recipeIcon:SetPoint("TOPLEFT", x, y + 2)
    self.itemIcon:ClearAllPoints()
    self.itemIcon:SetPoint("LEFT", self.recipeIcon, "RIGHT", STEP_ICON_GAP, 0)
    local iconsW = self.recipeIcon:IsShown() and STEP_ICON + STEP_ICON_GAP or 0
    if self.itemIcon:IsShown() then
      iconsW = iconsW + STEP_ICON + STEP_ICON_GAP
    end
    self.title:ClearAllPoints()
    local iconY = iconsW > 0 and 4 or 0
    self.title:SetPoint("TOPLEFT", x + iconsW + iconY, y - iconY)
    self.title:SetWidth(math.max(40, textW - iconsW - 84 - (self.crafters:IsShown() and CRAFTERS_SIDE + 6 or 0)))
    y = y - math.max(self.title:GetStringHeight() + iconY, iconsW > 0 and STEP_ICON - 2 or 14) - 2 - iconY
    local subH = 0
    if self.sub:GetText() and self.sub:GetText() ~= "" then
      self.sub:SetWidth(textW)
      self.sub:ClearAllPoints()
      self.sub:SetPoint("TOPLEFT", x, y)
      subH = self.sub:GetStringHeight()
      y = y - subH - 4
    end
    self.sub:SetShown(subH > 0)
    local chipsH = self.chips:Layout(textW)
    self.chips:ClearAllPoints()
    self.chips:SetPoint("TOPLEFT", x, y)
    self.chips:SetWidth(textW)
    y = y - chipsH - (chipsH > 0 and 4 or 0)
    self.src:SetWidth(textW)
    self.src:ClearAllPoints()
    self.src:SetPoint("TOPLEFT", x, y)
    y = y - self.src:GetStringHeight() - 8
    return -y
  end
  return row
end

local COLORS = {
  current = { title = "accent2", text = "text", state = "accent2" },
  open = { title = "text", text = "textSecondary", state = "textMuted" },
  done = { title = "textMuted", text = "textMuted", state = "textMuted" },
}

-- item.area ("before" | "after") paints the header of a collapsed area instead of a step.
local function paintStep(row, item)
  row.isHead = item.area ~= nil
  row.isNote = item.note ~= nil
  row.head:SetShown(row.isHead)
  for _, part in ipairs({ row.range, row.state, row.title, row.chips, row.src }) do
    part:SetShown(not row.isHead and not row.isNote)
  end
  row.sub:SetShown(not row.isHead)
  row.recipeIcon:SetShown(false)
  row.itemIcon:SetShown(false)
  row.step = item.step
  -- Only main steps can be picked, alternatives stay out of the shopping list.
  row.pick:SetShown(PICK.on and not row.isHead and not row.isNote and not item.alt)
  row.pick.Refresh()
  if row.isNote then
    row.spell, row.recipe, row.onToggle, row.product = nil, nil, nil, nil
    row.crafters:SetSpell(nil)
    row.sub:SetText(item.note)
    W.SetColor(row.sub, "textSecondary")
    row.bg:SetColorTexture(ns.Theme.fillColor())
    row.mark:SetColorTexture(ns.Theme.fillColor())
    return
  end
  if row.isHead then
    row.spell, row.recipe, row.onToggle = nil, nil, item.onToggle
    row.crafters:SetSpell(nil)
    row.bg:SetColorTexture(ns.Theme.fillColor())
    row.mark:SetColorTexture(ns.Theme.fillColor())
    row.head.bg:SetColorTexture(Theme.color(AREA_COLORS[item.area]))
    row.head.label:SetText(item.text)
    return
  end
  row.onToggle = nil
  local step, data, status = item.step, item.data, item.status
  local colors = COLORS[status]
  local recipe = spellName(step.spell) or ns.T(step.name)
  row.spell, row.recipe = step.spell, recipe
  row.product = productOf(S.Slug(), step.spell)
  if row.product then
    row.itemIcon.icon:SetTexture(productTexture(row.product))
  end
  -- A step without a recipe spell (effect text only) has neither icon.
  row.recipeIcon:SetShown(type(step.spell) == "number")
  row.itemIcon:SetShown(row.product ~= nil)
  row.crafters:SetSpell(type(step.spell) == "number" and step.spell or nil)
  row.range:SetText(string.format("%d-%d", step.from or 0, step.to or 0))
  W.SetColor(row.range, colors.title)
  -- Without a recipe name the effect text is the title.
  local res, note = ns.T(step.res), ns.T(step.note)
  local title = recipe or res or ""
  if step.crafts and step.crafts > 0 then
    title = title .. "  " .. string.format(L["profroute.crafts"], step.crafts)
  end
  row.title:SetText(title)
  W.SetColor(row.title, colors.title)
  local sub = {}
  if recipe and res then
    sub[#sub + 1] = res
  end
  if note then
    sub[#sub + 1] = note
  end
  row.sub:SetText(table.concat(sub, "\n"))
  W.SetColor(row.sub, colors.text)
  local chips = {}
  for _, m in ipairs(type(step.mats) == "table" and step.mats or {}) do
    local info = type(data.items) == "table" and data.items[m[1]] or {}
    local chip = {
      icon = iconPath(info.icon),
      name = ns.ItemInfo.name(m[1], { de = info.de, en = info.en }, "item:" .. tostring(m[1])),
      meta = tostring((m[2] or 1) * (step.crafts or 1)),
      tip = string.format(L["profroute.perCraft"], m[2] or 1),
      itemId = m[1],
    }
    -- A material the route buys at a vendor names the nearest vendor, a click sets the waypoint there.
    local best = info.buy == "vendor" and ns.VendorSource and ns.VendorSource.Best(m[1], false) or nil
    if best then
      chip.hint = string.format(L["vendor.where"], best.text) .. "\n" .. L["vendor.listTip"]
      chip.onClick = function()
        ns.VendorSource.SetWaypoint(best.place)
      end
    end
    chips[#chips + 1] = chip
  end
  row.chips:SetChips(chips)
  row.src:SetText(sourceText(data, step))
  W.SetColor(row.src, status == "done" and "textMuted" or "textSecondary")
  row.state:SetText(status == "open" and "" or L["profroute.state." .. status])
  W.SetColor(row.state, colors.state)
  row.bg:SetColorTexture(Theme.fillColor(status == "current" and "hover" or nil))
  if status == "current" then
    row.mark:SetColorTexture(Theme.color("accent2"))
  else
    row.mark:SetColorTexture(ns.Theme.fillColor())
  end
end

-- Trainer rows ------------------------------------------------------------------------------------

local function newTrainerRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:EnableMouse(true)
  row.text = W.Text(row, { role = "ui", wrap = true })
  row.actions = W.MapActionButtons(row, { mapTip = "profroute.mapTip", markerTip = "profroute.markerTip" })
  -- Rank heads and trainers without a position do not hover.
  K.RowHover(row, {
    extraFrames = { row.actions.map, row.actions.marker },
    isActive = function()
      return row.trainer ~= nil
    end,
  })
  function row:fgLayout(width)
    local hasPlace = self.actions:IsShown()
    local textW = math.max(40, width - 8 - (hasPlace and self.actions:GetWidth() + 12 or 4))
    self.text:ClearAllPoints()
    self.text:SetPoint("TOPLEFT", 8, -6)
    self.text:SetWidth(textW)
    self.actions:ClearAllPoints()
    self.actions:SetPoint("TOPRIGHT", -4, -2)
    return math.max(self.text:GetStringHeight() + 12, 28)
  end
  return row
end

-- item.trainer is an entry of ProfessionTrainersLogic.Collect: its position holds fractions of the zone
-- map, its map is the id of the data or the client map named like the zone (resolved on click).
local function paintTrainer(row, item)
  if item.head then
    row.text:SetText(item.head)
    W.SetColor(row.text, "accent2")
    row.trainer = nil
    row.actions:SetPlace(nil)
    row.paintHover()
    return
  end
  local t = item.trainer
  local PL = ns.ProfessionTrainersLogic
  local parts = { PL.DisplayName(t) }
  if t.faction == "A" or t.faction == "H" then
    parts[#parts + 1] = L["kit.faction." .. t.faction]
  end
  local place = ns.T(t.place)
  if place then
    parts[#parts + 1] = place
  end
  row.text:SetText(table.concat(parts, ", "))
  W.SetColor(row.text, "text")
  row.trainer = PL.HasPosition(t) and t or nil
  row.actions:SetPlace(row.trainer and function()
    return PL.Place(t)
  end or nil)
  row.paintHover()
end

-- A rank is one card (W.Panel) holding its head line and one line per trainer; the cards flow into columns.
local function newTrainerBlock(parent)
  local card = W.Panel(parent)
  card.lines, card.used = {}, 0
  function card:fgLayout(width)
    local inset = Theme.space.xs
    local inner = math.max(40, width - inset * 2)
    local y = inset
    for i = 1, self.used do
      local line = self.lines[i]
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", self, "TOPLEFT", inset, -y)
      line:SetWidth(inner)
      local h = line:fgLayout(inner)
      line:SetHeight(h)
      y = y + h
    end
    return y + inset
  end
  return card
end

local function paintTrainerBlock(card, block)
  local items = { { head = block.head } }
  for _, t in ipairs(block.trainers) do
    items[#items + 1] = { trainer = t }
  end
  for i, item in ipairs(items) do
    local line = card.lines[i]
    if not line then
      line = newTrainerRow(card)
      card.lines[i] = line
    end
    paintTrainer(line, item)
    line:Show()
  end
  for i = #items + 1, #card.lines do
    card.lines[i]:Hide()
  end
  card.used = #items
end

-- The trainers of every rank of a route: { { head, trainers } } blocks, the trainers of the rank
-- sorted by faction, place and name. The trainer data file (when loaded) adds trainers and positions.
local function trainerRows(slug, data)
  local PL = ns.ProfessionTrainersLogic
  local entries =
    PL.Sort(PL.Collect({ { slug = slug, data = data, name = R.PROFESSIONS[slug] } }, rawget(ns, "ProfessionTrainers")))
  local list = {}
  for _, r in ipairs(type(data.ranks) == "table" and data.ranks or {}) do
    list[#list + 1] = {
      head = string.format(L["profroute.rankHead"], rankName(r.rank), tonumber(r.max) or 0),
      trainers = PL.Filter(entries, { rank = r.rank }),
    }
  end
  return list
end

-- Page ----------------------------------------------------------------------------------------------

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local refresh

  ns.AddIntro(view, "profroute.intro")

  -- Controls: profession, start, target, shopping list button, wrapped to the width.
  local options = {}
  local controls = CreateFrame("Frame", nil, view.content)
  local dropdown = W.Dropdown(controls, {
    key = "profroute.profession",
    width = DROPDOWN_W,
    options = options,
    get = S.Slug,
    set = function(slug)
      S.SetOption("slug", slug)
    end,
  })
  dropdown:SetWidth(DROPDOWN_W)
  local function field(labelKey, placeholderKey, option)
    local box = CreateFrame("Frame", nil, controls)
    box:SetSize(FIELD_W, 46)
    local label = W.Text(box, { key = labelKey, role = "ui" })
    label:SetPoint("TOPLEFT")
    local edit = W.EditBox(box, {
      placeholder = placeholderKey,
      onChange = function(text)
        S.SetOption(option, text)
      end,
    })
    edit:SetPoint("TOPLEFT", 0, -18)
    edit:SetWidth(FIELD_W)
    box.edit = edit
    return box
  end
  local from = field("profroute.from", "profroute.fromPh", "from")
  local target = field("profroute.target", "profroute.targetPh", "target")
  local shop = W.Button(controls, {
    key = "profroute.shop",
    variant = "primary",
    width = BUTTON_W,
    tooltip = "profroute.shop",
    tooltipText = "profroute.shopTip",
    opens = true,
    onClick = function()
      ns.ProfessionShopWindow.Open()
    end,
  })
  local small = ns.ProfessionTracker.NewOpenButton(controls, "profroute-small", { width = BUTTON_W, height = 28 })
  -- The picked steps of the shown profession as { [index] = true } and their number.
  local function pickedSteps()
    local data = Data.Get(S.Slug())
    local set, n = {}, 0
    for i, step in ipairs(data and data.steps or {}) do
      if PICK.steps[step] then
        set[i], n = true, n + 1
      end
    end
    return set, n
  end
  local add, pick
  local function paintPick()
    local _, n = pickedSteps()
    W.SetText(add.label, nil, PICK.on and string.format(L["profroute.addPicked"], n) or L["profroute.addRange"])
    W.SetText(pick.label, nil, L[PICK.on and "profroute.pickOff" or "profroute.pick"])
    add:SetEnabled(not PICK.on or n > 0)
  end
  -- The two ways onto the list are the main actions of the page: filled and gold, not plain buttons.
  add = W.Action(controls, {
    label = "profroute.addRange",
    variant = "primary",
    icon = "plus",
    height = 28,
    tooltip = "profroute.addRange",
    tooltipText = "profroute.addRangeTip",
    onClick = function()
      if PICK.on then
        local set, n = pickedSteps()
        if n > 0 then
          ns.ProfessionList.AddRouteFromPage(S.Slug(), set, function()
            PICK.on, PICK.steps = false, {}
            refresh()
          end)
        end
      else
        ns.ProfessionList.AddRouteFromPage(S.Slug())
      end
    end,
  })
  add.fgId = "profroute-addrange"
  pick = W.Action(controls, {
    label = "profroute.pick",
    variant = "gold",
    icon = "check",
    height = 28,
    tooltip = "profroute.pick",
    tooltipText = "profroute.pickTip",
    onClick = function()
      PICK.on = not PICK.on
      refresh()
    end,
  })
  pick.fgId = "profroute-pick-mode"
  -- The longest labels of the row: at their own width where they fit, never wider than the page.
  add.naturalW = math.max(add:GetWidth(), 230)
  pick.naturalW = pick:GetWidth()
  ns.On("FG_PROFROUTE_PICKED", paintPick)
  local buttons = { [shop] = true, [small] = true, [add] = true, [pick] = true }
  function controls:fgGridLayout(width)
    local x, y, rowH = 0, 0, 46
    for _, item in ipairs({ dropdown, from, target, shop, small, add, pick }) do
      if item.naturalW then
        item:SetWidth(math.min(item.naturalW, width))
      end
      local w = item:GetWidth()
      if x > 0 and x + w > width then
        x, y = 0, y + rowH + 8
      end
      item:ClearAllPoints()
      if buttons[item] then
        item:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(y + 18))
      else
        item:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
      end
      x = x + w + CONTROL_GAP
    end
    local h = y + rowH
    self:SetHeight(h)
    return h
  end
  s:Add(controls, { gap = Theme.space.md })
  s:Add(ns.ProfessionTracker.NewToggle(view.content), { height = 24, gap = Theme.space.md })

  local progress = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = Theme.space.sm })
  local bar = CreateFrame("Frame", nil, view.content)
  bar:SetHeight(BAR_H)
  bar.back = bar:CreateTexture(nil, "BACKGROUND")
  bar.back:SetAllPoints()
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill:SetPoint("TOPLEFT")
  bar.fill:SetPoint("BOTTOMLEFT")
  bar.frac = 0
  ns.Bind(bar, function()
    bar.back:SetColorTexture(Theme.color("surface3"))
    bar.fill:SetColorTexture(Theme.color("action"))
  end)
  function bar:fgGridLayout(width)
    self.fill:SetWidth(math.max(1, math.floor(width * self.frac)))
    return BAR_H
  end
  s:Add(bar, { gap = Theme.space.lg })

  local hint = ns.AddParagraph(view, nil, { role = "ui", color = "warning", gap = Theme.space.md })
  -- Instead of the hint while the data add-on is off or missing: the button that switches it on.
  local banner = ns.PackageUI.Banner(view.content, Data.ADDON, {
    onLoaded = function()
      refresh()
    end,
    onResize = function()
      view:Layout()
    end,
  })
  s:Add(banner, { gap = Theme.space.md })
  local routeHead = ns.AddHeading(view, "profroute.routeHeading")
  local steps = K.RowPool(view.content, newStepRow)
  s:Add(steps, { gap = Theme.space.md })
  local trainerHead = ns.AddHeading(view, "profroute.trainersHeading")
  local trainers = K.RowPool(view.content, newTrainerBlock, { cards = { minWidth = 300, gap = Theme.space.md } })
  s:Add(trainers, { gap = Theme.space.md })

  local function fillOptions(own)
    for i = #options, 1, -1 do
      options[i] = nil
    end
    local mine = {}
    for _, p in ipairs(own) do
      mine[p.slug] = p
      options[#options + 1] = { value = p.slug, text = string.format("%s (%d/%d)", R.Name(p.slug), p.skill, p.max) }
    end
    for _, slug in ipairs(R.SLUGS) do
      if not mine[slug] then
        options[#options + 1] = { value = slug, text = R.Name(slug) }
      end
    end
  end

  function refresh()
    fillOptions(S.Own())
    dropdown.Refresh()
    paintPick()
    local slug = S.Slug()
    local data, status = Data.Get(slug)
    local name = R.Name(slug)
    local skill, max = S.Skill(slug)
    local offered = banner:Update(data == nil and status == Data.STATUS.missing)
    hint:SetShown(data == nil and not offered)
    routeHead:SetShown(data ~= nil)
    steps:SetShown(data ~= nil)
    trainerHead:SetShown(data ~= nil)
    trainers:SetShown(data ~= nil)
    bar:SetShown(data ~= nil)
    if not data then
      hint:SetText(Data.Hint(status))
      progress:SetText(skill and string.format("%s: %d/%d", name, skill, max or 0) or "")
      steps:Sync({}, paintStep)
      trainers:Sync({}, paintTrainerBlock)
      view:Layout()
      return
    end
    local state = R.Progress(data, skill or 0)
    if not skill then
      progress:SetText(string.format(L["profroute.notOwned"], name))
    elseif state.current then
      progress:SetText(
        string.format(L["profroute.progress"], name, skill, tonumber(data.max) or 0, state.current, state.total)
      )
    else
      progress:SetText(string.format(L["profroute.finished"], name, skill))
    end
    bar.frac = state.frac
    local rows = {}
    local function addSteps(entries, alt)
      for _, e in ipairs(entries) do
        rows[#rows + 1] = { step = e.step, data = data, status = e.status, alt = alt }
      end
    end
    -- Only a typed start or target hides steps, the automatic skill keeps every step in view.
    local before, shown, after = R.Areas(R.Steps(data, skill or 0), S.Option("from"), S.Option("target"))
    local function addArea(area, entries)
      if #entries == 0 then
        return
      end
      rows[#rows + 1] = {
        area = area,
        text = string.format("%s %s (%d)", opened[area] and "v" or ">", L["profroute.area." .. area], #entries),
        onToggle = function()
          opened[area] = not opened[area] or nil
          refresh()
        end,
      }
      if opened[area] then
        addSteps(entries)
      end
    end
    addArea("before", before)
    addSteps(shown)
    addArea("after", after)
    -- Alternatives whose range touches the visible range, listed after the main steps.
    local lo, hi = R.Whole(S.Option("from")) or 0, R.Whole(S.Option("target")) or R.MAX_SKILL
    local blocks = {}
    for i, block in ipairs(Data.Alternatives(slug)) do
      local a, b = tonumber(block.from) or 0, tonumber(block.to) or 0
      if math.min(b, hi) > math.max(a, lo) or (a == b and a >= lo and a <= hi) then
        blocks[#blocks + 1] = { i = i, block = block }
      end
    end
    if #blocks > 0 then
      rows[#rows + 1] = {
        area = "alternatives",
        text = string.format(
          "%s %s (%d)",
          opened.alternatives and "v" or ">",
          L["profroute.area.alternatives"],
          #blocks
        ),
        onToggle = function()
          opened.alternatives = not opened.alternatives or nil
          refresh()
        end,
      }
    end
    if opened.alternatives then
      rows[#rows + 1] = { note = L["profroute.alt.intro"] .. "\n" .. L["profroute.alt.intro2"] }
      for _, b in ipairs(blocks) do
        local key = slug .. b.i
        local shut = folded[key]
        rows[#rows + 1] = {
          area = "altblock",
          text = string.format(
            "%s %s",
            shut and ">" or "v",
            string.format(
              L["profroute.alt.head"],
              tonumber(b.block.from) or 0,
              tonumber(b.block.to) or 0,
              ns.T(b.block.title) or ""
            )
          ),
          onToggle = function()
            folded[key] = not shut or nil
            refresh()
          end,
        }
        local note = ns.T(b.block.note)
        if not shut and note and note ~= "" then
          rows[#rows + 1] = { note = note }
        end
        if not shut then
          local entries = {}
          for j, step in ipairs(type(b.block.steps) == "table" and b.block.steps or {}) do
            entries[#entries + 1] = { step = step, i = j, status = R.Status(step, skill or 0, false) }
          end
          addSteps(entries, true)
        end
      end
    end
    if #rows == 0 then
      hint:SetText(L["profroute.noSteps"])
      hint:SetShown(true)
    end
    steps:Sync(rows, paintStep)
    local trainerList = trainerRows(slug, data)
    W.SetCount(trainerHead, #trainerList)
    trainers:Sync(trainerList, paintTrainerBlock)
    view:Layout()
  end

  -- The input fields follow the saved choice when the page opens.
  local function syncFields()
    target.edit.edit:SetText(S.Option("target") and tostring(S.Option("target")) or "")
    from.edit.edit:SetText(S.Option("from") and tostring(S.Option("from")) or "")
  end

  -- Page link: the profession of the route.
  function view:ShareState()
    return { S.Slug() }
  end

  -- params[1] = profession slug (deep link from the search and other pages), unknown ones are ignored.
  function view:Show(params)
    local slug = params and params[1]
    if slug and R.PROFESSIONS[slug] then
      S.SetOption("slug", slug)
    end
    syncFields()
    refresh()
  end
  local function whenVisible()
    if container:IsVisible() then
      refresh()
    end
  end
  ns.On("FG_PROFROUTE_CHANGED", whenVisible)
  ns.On("FG_ROSTER_CHANGED", whenVisible)
  ns.On("FG_UI_REFRESHED", whenVisible)
  ns.On("SKILL_LINES_CHANGED", function()
    ns.Debounce("profroute-skill", 0.5, whenVisible)
  end)
  ns.On("GET_ITEM_INFO_RECEIVED", function()
    ns.Debounce("profroute-items", 0.5, whenVisible)
  end)
  P.view, P.options = view, options
  return view
end

ns.RegisterPage({
  id = "professionroute",
  order = 420,
  group = "professions",
  title = "page.professionroute",
  icon = ns.ICONS.professionroute,
  aliases = { "berufsroute", "skillroute", "professionroute", "professionroutes" },
  crumbLabel = function(param)
    return R.PROFESSIONS[param] and R.Name(param) or param
  end,
  build = build,
})
