-- Page "Profession route" (/fg berufsroute): pick a profession, see the skill route step by step
-- (skill range, recipe, crafts, reagents, where the recipe comes from), the current step marked, done
-- steps dimmed, the trainers per rank with a map link, and the button for the shopping list window.
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
  ["profroute.progress"] = "%s: skill %d of %d, step %d of %d",
  ["profroute.finished"] = "%s: route finished (skill %d)",
  ["profroute.notOwned"] = "%s: not learned, route from the start",
  ["profroute.routeHeading"] = "Route",
  ["profroute.trainersHeading"] = "Trainers",
  ["profroute.state.current"] = "Current",
  ["profroute.state.done"] = "Done",
  ["profroute.area.before"] = "Before the start skill",
  ["profroute.area.after"] = "After the target skill",
  ["profroute.crafts"] = "%dx",
  ["profroute.perCraft"] = "%d per craft",
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
  ["profroute.target"] = "Ziel-Skill",
  ["profroute.targetPh"] = "Maximum",
  ["profroute.from"] = "Start-Skill",
  ["profroute.fromPh"] = "Automatisch",
  ["profroute.shop"] = "Einkaufsliste",
  ["profroute.shopTip"] = "Öffnet das Fenster der Einkaufsliste.",
  ["profroute.progress"] = "%s: Skill %d von %d, Schritt %d von %d",
  ["profroute.finished"] = "%s: Route fertig (Skill %d)",
  ["profroute.notOwned"] = "%s: nicht gelernt, Route ab Anfang",
  ["profroute.routeHeading"] = "Route",
  ["profroute.trainersHeading"] = "Lehrer",
  ["profroute.state.current"] = "Aktuell",
  ["profroute.state.done"] = "Erledigt",
  ["profroute.area.before"] = "Vor dem Start-Skill",
  ["profroute.area.after"] = "Nach dem Ziel-Skill",
  ["profroute.crafts"] = "%dx",
  ["profroute.perCraft"] = "%d pro Herstellung",
  ["profroute.src.trainer"] = "Lehrer (%s): %s",
  ["profroute.src.trainerNone"] = "Lehrer (%s)",
  ["profroute.src.item"] = "Rezept-Item",
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

local LEFT_W = 64
local SIDE = 12
local CRAFTERS_SIDE = 22
local HEAD_H = 26
local HEAD_GAP = 8
-- Light fills that carry one black text color, the same as the areas of the level list.
local AREA_COLORS = { before = "sectionLearned", after = "sectionLocked" }
-- Areas the user opened this session ("before" / "after"), closed by default.
local opened = {}

-- Header of a collapsed or opened area, a real button so the keyboard reaches it.
local function newAreaHead(row)
  local head = CreateFrame("Button", nil, row)
  head:SetPoint("TOPLEFT")
  head:SetPoint("BOTTOMRIGHT", 0, HEAD_GAP)
  head.bg = head:CreateTexture(nil, "BACKGROUND")
  head.bg:SetAllPoints()
  local hover = head:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
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
  row.bg:SetColorTexture(1, 1, 1, 0)
  row.mark = row:CreateTexture(nil, "ARTWORK")
  row.mark:SetPoint("TOPLEFT")
  row.mark:SetPoint("BOTTOMLEFT")
  row.mark:SetWidth(3)
  row.mark:SetColorTexture(1, 1, 1, 0)
  row.range = W.Text(row, { role = "ui", family = "heading" })
  row.state = W.Text(row, { role = "micro", justify = "RIGHT" })
  row.title = W.Text(row, { role = "ui", wrap = true })
  row.sub = W.Text(row, { role = "micro", color = "textSecondary", wrap = true })
  row.chips = K.ChipRow(row)
  row.src = W.Text(row, { role = "micro", color = "textMuted", wrap = true })
  row.head = newAreaHead(row)
  -- Who in the guild can make the recipe of the step.
  row.crafters = ns.CraftersView.Action(row, { size = CRAFTERS_SIDE, id = "profroute-crafters" })
  row:SetScript("OnEnter", function(self)
    if self.spell then
      W.Tooltip.Show(self, { spell = self.spell, title = self.recipe })
    end
  end)
  row:SetScript("OnLeave", ns.HideTooltip)
  function row:fgLayout(width)
    if self.isHead then
      return K.scaledHeight(HEAD_H) + HEAD_GAP
    end
    local textW = math.max(40, width - LEFT_W - SIDE * 2)
    self.range:ClearAllPoints()
    self.range:SetPoint("TOPLEFT", SIDE, -8)
    self.range:SetWidth(LEFT_W - 8)
    self.state:ClearAllPoints()
    self.state:SetPoint("TOPRIGHT", -SIDE, -8)
    self.state:SetWidth(80)
    self.crafters:ClearAllPoints()
    self.crafters:SetPoint("TOPRIGHT", -SIDE - 84, -6)
    local x, y = LEFT_W + SIDE, -8
    self.title:ClearAllPoints()
    self.title:SetPoint("TOPLEFT", x, y)
    self.title:SetWidth(math.max(40, textW - 80 - (self.crafters:IsShown() and CRAFTERS_SIDE + 6 or 0)))
    y = y - math.max(self.title:GetStringHeight(), 14) - 2
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
  row.head:SetShown(row.isHead)
  for _, part in ipairs({ row.range, row.state, row.title, row.sub, row.chips, row.src }) do
    part:SetShown(not row.isHead)
  end
  if row.isHead then
    row.spell, row.recipe, row.onToggle = nil, nil, item.onToggle
    row.crafters:SetSpell(nil)
    row.bg:SetColorTexture(1, 1, 1, 0)
    row.mark:SetColorTexture(1, 1, 1, 0)
    row.head.bg:SetColorTexture(Theme.color(AREA_COLORS[item.area]))
    row.head.label:SetText(item.text)
    return
  end
  row.onToggle = nil
  local step, data, status = item.step, item.data, item.status
  local colors = COLORS[status]
  local recipe = spellName(step.spell) or ns.T(step.name)
  row.spell, row.recipe = step.spell, recipe
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
      name = ns.T({ de = info.de, en = info.en }) or ("item:" .. tostring(m[1])),
      meta = tostring((m[2] or 1) * (step.crafts or 1)),
      tip = string.format(L["profroute.perCraft"], m[2] or 1),
    }
    -- A material the route buys at a vendor names the nearest vendor, a click sets the waypoint there.
    local best = info.buy == "vendor" and ns.VendorSource and ns.VendorSource.Best(m[1], false) or nil
    if best then
      chip.tip = chip.tip .. "\n" .. string.format(L["vendor.where"], best.text) .. "\n" .. L["vendor.listTip"]
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
  row.bg:SetColorTexture(1, 1, 1, status == "current" and 0.06 or 0)
  if status == "current" then
    row.mark:SetColorTexture(Theme.color("accent2"))
  else
    row.mark:SetColorTexture(1, 1, 1, 0)
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

-- The trainers of every rank of a route: { { head } or { trainer } } rows, the trainers of the rank
-- sorted by faction, place and name. The trainer data file (when loaded) adds trainers and positions.
local function trainerRows(slug, data)
  local PL = ns.ProfessionTrainersLogic
  local entries =
    PL.Sort(PL.Collect({ { slug = slug, data = data, name = R.PROFESSIONS[slug] } }, rawget(ns, "ProfessionTrainers")))
  local list = {}
  for _, r in ipairs(type(data.ranks) == "table" and data.ranks or {}) do
    list[#list + 1] = { head = string.format(L["profroute.rankHead"], rankName(r.rank), tonumber(r.max) or 0) }
    for _, t in ipairs(PL.Filter(entries, { rank = r.rank })) do
      list[#list + 1] = { trainer = t }
    end
  end
  return list
end

-- Page ----------------------------------------------------------------------------------------------

local function build(container)
  local view = ns.NewPageView(container)
  local s = view.stack
  local refresh

  ns.AddParagraph(view, "profroute.intro")

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
  function controls:fgGridLayout(width)
    local x, y, rowH = 0, 0, 46
    for _, item in ipairs({ dropdown, from, target, shop }) do
      local w = item:GetWidth()
      if x > 0 and x + w > width then
        x, y = 0, y + rowH + 8
      end
      item:ClearAllPoints()
      if item == shop then
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
  s:Add(controls, { gap = 12 })
  s:Add(ns.ProfessionTracker.NewToggle(view.content), { height = 24, gap = 12 })

  local progress = ns.AddParagraph(view, nil, { role = "ui", color = "accent2", gap = 6 })
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
  s:Add(bar, { gap = 14 })

  local hint = ns.AddParagraph(view, nil, { role = "ui", color = "warning", gap = 12 })
  -- Instead of the hint while the data add-on is off or missing: the button that switches it on.
  local banner = ns.PackageUI.Banner(view.content, Data.ADDON, {
    onLoaded = function()
      refresh()
    end,
    onResize = function()
      view:Layout()
    end,
  })
  s:Add(banner, { gap = 12 })
  local routeHead = ns.AddHeading(view, "profroute.routeHeading")
  local steps = K.RowPool(view.content, newStepRow)
  s:Add(steps, { gap = 12 })
  local trainerHead = ns.AddHeading(view, "profroute.trainersHeading")
  local trainers = K.RowPool(view.content, newTrainerRow)
  s:Add(trainers, { gap = 12 })

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
      trainers:Sync({}, paintTrainer)
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
    local function addSteps(entries)
      for _, e in ipairs(entries) do
        rows[#rows + 1] = { step = e.step, data = data, status = e.status }
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
    if #rows == 0 then
      hint:SetText(L["profroute.noSteps"])
      hint:SetShown(true)
    end
    steps:Sync(rows, paintStep)
    trainers:Sync(trainerRows(slug, data), paintTrainer)
    view:Layout()
  end

  -- The input fields follow the saved choice when the page opens.
  local function syncFields()
    target.edit.edit:SetText(S.Option("target") and tostring(S.Option("target")) or "")
    from.edit.edit:SetText(S.Option("from") and tostring(S.Option("from")) or "")
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
