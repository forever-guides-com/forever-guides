-- Race views of the classes page: the detail view of one race (class grid,
-- racial abilities, removed abilities, role) and the overview (cards of all
-- races, race x class matrix, new classes per race). Data comes from
-- ns.RaceLogic (ns.Data.RaceInfo); every view lays itself out through
-- fgGridLayout(width), so it works inside a page Stack and reflows on resize.
local _, ns = ...
local W, L, Theme, K, RL, R = ns.W, ns.L, ns.Theme, ns.PageKit, ns.RaceLogic, ns.RefLogic

local RV = {}
ns.RaceViews = RV

ns.AddLocale("enUS", {
  ["classes.race.classes"] = "Classes",
  ["classes.race.abilities"] = "Racial abilities",
  ["classes.race.removed"] = "Removed abilities",
  ["classes.race.role"] = "Role",
  ["classes.race.classAbilities"] = "Race-specific class abilities",
  ["classes.race.line"] = "%s · level %s · %s",
  ["classes.race.englishOnly"] = "Text in English only",
  ["classes.class.new"] = "New in Forever",
  ["classes.class.locked"] = "Not available",
  ["classes.class.tip.new"] = "%s + %s: new in Forever, not possible in Classic.",
  ["classes.class.tip.ok"] = "%s + %s: available.",
  ["classes.class.tip.locked"] = "%s + %s: not available.",
  ["classes.type.active"] = "Active",
  ["classes.type.passive"] = "Passive",
  ["classes.status.new"] = "New",
  ["classes.status.changed"] = "Changed",
  ["classes.status.unchanged"] = "Unchanged",
  ["classes.ability.classic"] = "In Classic",
  ["classes.over.hint"] = "All ten races, click for details",
  ["classes.over.count"] = "%d classes",
  ["classes.over.matrix"] = "Races and classes",
  ["classes.over.matrixHint"] = "Check = available, green square = new in Forever",
  ["classes.over.new"] = "New in Forever",
  ["classes.over.newHint"] = "Pick a class to see races that newly play it",
  ["classes.over.newNone"] = "No race gets this class as a new option.",
})

ns.AddLocale("deDE", {
  ["classes.race.classes"] = "Klassen",
  ["classes.race.abilities"] = "Rassenfähigkeiten",
  ["classes.race.removed"] = "Entfernte Fähigkeiten",
  ["classes.race.role"] = "Rolle",
  ["classes.race.classAbilities"] = "Volksspezifische Klassenfähigkeiten",
  ["classes.race.line"] = "%s · Stufe %s · %s",
  ["classes.race.englishOnly"] = "Text nur auf Englisch",
  ["classes.class.new"] = "Neu in Forever",
  ["classes.class.locked"] = "Nicht verfügbar",
  ["classes.class.tip.new"] = "%s + %s: neu in Forever, in Classic nicht möglich.",
  ["classes.class.tip.ok"] = "%s + %s: verfügbar.",
  ["classes.class.tip.locked"] = "%s + %s: nicht verfügbar.",
  ["classes.type.active"] = "Aktiv",
  ["classes.type.passive"] = "Passiv",
  ["classes.status.new"] = "Neu",
  ["classes.status.changed"] = "Geändert",
  ["classes.status.unchanged"] = "Unverändert",
  ["classes.ability.classic"] = "In Classic",
  ["classes.over.hint"] = "Alle zehn Völker, Klick öffnet die Details",
  ["classes.over.count"] = "%d Klassen",
  ["classes.over.matrix"] = "Völker und Klassen",
  ["classes.over.matrixHint"] = "Haken = verfügbar, grünes Quadrat = neu in Forever",
  ["classes.over.new"] = "Neu in Forever",
  ["classes.over.newHint"] = "Klasse wählen: zeigt Völker, die sie neu spielen können",
  ["classes.over.newNone"] = "Kein Volk bekommt diese Klasse neu.",
})

local GAP = 8
local SECTION_GAP = 16
local CARD_PAD = 10
local CARD_ICON = 36

-- Helpers -------------------------------------------------------------------------------

-- Height of a wrapped text at a given width (the width is set first, anchor-derived widths are
-- not resolved in the same frame).
local function textHeight(fs, width)
  fs:SetWidth(math.max(1, width))
  return math.ceil(fs:GetStringHeight())
end

local function scaled(base)
  return K.scaledHeight(base)
end

local function englishNote()
  return ns.GetActiveLocale() ~= "enUS"
end

-- Stacks `entries` ({ item, gap = after, indent }) below each other. Items are text or frames
-- with fgGridLayout(width); hidden items take no room. Returns the total height.
local function stackEntries(host, entries, width)
  local y, gap = 0, 0
  for _, e in ipairs(entries) do
    local item = e[1]
    if item:IsShown() then
      local indent = e.indent or 0
      local w = math.max(1, width - indent)
      y = y + gap
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", host, "TOPLEFT", indent, -y)
      local h
      if item.fgGridLayout then
        item:SetWidth(w)
        h = item:fgGridLayout(w)
      else
        h = textHeight(item, w)
      end
      y = y + h
      gap = e.gap or GAP
    end
  end
  y = math.max(1, y)
  host:SetHeight(y)
  return y
end

local function heading(parent, key)
  return W.Text(parent, { key = key, role = "h3", family = "heading", color = "accent2", wrap = true })
end

local function note(parent)
  return W.Text(parent, { role = "ui", color = "textMuted", wrap = true })
end

local function tooltip(owner, title, text)
  owner:EnableMouse(true)
  owner:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, title(), text and text() or nil)
  end)
  owner:SetScript("OnLeave", ns.HideTooltip)
end

-- A small colored square, themed (high contrast and color blind modes follow the Theme).
local function newDot(parent, size)
  local dot = parent:CreateTexture(nil, "ARTWORK")
  dot:SetSize(size, size)
  ns.Bind(dot, function(t)
    if t.fgColor then
      t:SetColorTexture(Theme.color(t.fgColor))
    end
  end)
  return dot
end

local function setDot(dot, color)
  dot.fgColor = color
  dot:SetColorTexture(Theme.color(color))
end

local function factionColor(f)
  return f == "H" and "horde" or "alliance"
end

local function className(class)
  return R.className(class)
end

-- Race icon at any size: atlas, sheet, shipped file or letter badge (K.RaceIconSpec).
local function newBigIcon(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  f.badge = f:CreateTexture(nil, "ARTWORK")
  f.badge:SetAllPoints()
  f.letter = W.Text(f, { role = "h2", family = "heading", color = "bg", justify = "CENTER" })
  f.letter:SetPoint("CENTER")
  function f:SetSpec(spec)
    self.iconSpec = spec
    self.tex:Hide()
    self.badge:Hide()
    self.letter:Hide()
    if spec.kind == "atlas" then
      self.tex:SetAtlas(spec.atlas)
      self.tex:Show()
    elseif spec.kind == "sheet" then
      self.tex:SetTexture(spec.texture)
      self.tex:SetTexCoord(unpack(spec.coords))
      self.tex:Show()
    elseif spec.kind == "texture" then
      self.tex:SetTexture(spec.texture)
      self.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      self.tex:Show()
    else
      self.badge:SetColorTexture(Theme.rgb(spec.color or "accent2"))
      self.badge:Show()
      self.letter:SetText(spec.letter or "?")
      self.letter:Show()
    end
  end
  return f
end

-- Racial ability icon with a thin border. The texture is a client icon, the question mark
-- stands in for a file the client does not know (RaceLogic.IconPath).
local function newAbilityIcon(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  W.Border(f, "white", 0.5)
  function f:SetAbility(ability)
    self.path = RL.IconPath(ability.icon)
    self.tex:SetTexture(self.path)
  end
  return f
end

local function abilityMeta(a)
  return string.format("%s · %s", L["classes.type." .. a.t], L["classes.status." .. a.st])
end

local function classTip(race, class)
  local state = RL.ClassState(race.slug, class)
  local key = state == "new" and "classes.class.tip.new"
    or state == "locked" and "classes.class.tip.locked"
    or "classes.class.tip.ok"
  return string.format(L[key], ns.T(race.n), className(class))
end

-- Detail ----------------------------------------------------------------------------------

local function newClassChip(parent, class)
  local chip = CreateFrame("Frame", nil, parent)
  W.Fill(chip, "surface", 1)
  chip.border = W.Border(chip, "white")
  chip.class = class
  chip.classIcon = K.IconSlot(chip, K.ClassIconSpec(class))
  chip.classIcon:SetPoint("LEFT", 8, 0)
  chip.name = W.Text(chip, { role = "ui", color = "text" })
  chip.status = W.Text(chip, { role = "micro", color = "textMuted" })
  chip.mark = newDot(chip, 8)
  chip.mark:SetPoint("TOPRIGHT", -4, -4)
  tooltip(chip, function()
    return className(class)
  end, function()
    return chip.tip
  end)
  function chip:Paint(race)
    local state = RL.ClassState(race.slug, class)
    W.SetText(self.name, nil, className(class))
    W.SetColor(self.name, state == "locked" and "textMuted" or K.ClassColorHex(class))
    self.classIcon:SetAlpha(state == "locked" and 0.4 or 1)
    local label = state == "new" and L["classes.class.new"] or state == "locked" and L["classes.class.locked"] or nil
    W.SetText(self.status, nil, label or "")
    W.SetColor(self.status, state == "new" and "success" or "textMuted")
    self.status:SetShown(label ~= nil)
    self.mark:SetShown(state == "new")
    if state == "new" then
      setDot(self.mark, "success")
      self.border.set("success", 0.9)
    else
      self.border.set("white", nil)
    end
    self.tip = classTip(race, class)
  end
  -- Natural width, never above `width`; the name sits next to the icon, the optional status
  -- line below it.
  function chip:Fit(width)
    local w = math.min(width, 34 + math.ceil(math.max(self.name:GetStringWidth(), self.status:GetStringWidth())) + 16)
    local h = scaled(36)
    self.name:ClearAllPoints()
    self.status:ClearAllPoints()
    if self.status:IsShown() then
      self.name:SetPoint("TOPLEFT", self, "TOPLEFT", 34, -5)
      self.status:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 34, 5)
    else
      self.name:SetPoint("LEFT", self, "LEFT", 34, 0)
    end
    return w, h
  end
  return chip
end

local function newChipGrid(parent)
  local grid = CreateFrame("Frame", nil, parent)
  grid.chips = {}
  for _, class in ipairs(R.CLASSES) do
    grid.chips[#grid.chips + 1] = newClassChip(grid, class)
  end
  function grid:Paint(race)
    for _, chip in ipairs(self.chips) do
      chip:Paint(race)
    end
  end
  function grid:fgGridLayout(width)
    local x, y, rowH = 0, 0, 0
    for _, chip in ipairs(self.chips) do
      local w, h = chip:Fit(width)
      if x > 0 and x + w > width then
        x, y, rowH = 0, y + rowH + GAP, 0
      end
      chip:ClearAllPoints()
      chip:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
      chip:SetSize(w, h)
      x = x + w + GAP
      rowH = math.max(rowH, h)
    end
    self:SetHeight(math.max(1, y + rowH))
    return y + rowH
  end
  return grid
end

local function newAbilityCard(parent)
  local card = W.Card(parent, {})
  card.icon = newAbilityIcon(card, CARD_ICON)
  card.icon:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
  card.name = W.Text(card, { role = "h3", family = "heading", color = "text", wrap = true })
  card.dot = newDot(card, 8)
  card.meta = W.Text(card, { role = "ui", color = "textSecondary", wrap = true })
  card.text = W.Text(card, { role = "text", color = "text", wrap = true })
  card.classic = W.Text(card, { role = "ui", color = "textMuted", wrap = true })
  function card:Paint(a)
    self.icon:SetAbility(a)
    W.SetText(self.name, nil, a.n)
    W.SetText(self.meta, nil, abilityMeta(a))
    setDot(self.dot, RL.STATUS_COLOR[a.st] or "textMuted")
    W.SetText(self.text, nil, a.text)
    W.SetText(self.classic, nil, a.classic and (L["classes.ability.classic"] .. ": " .. a.classic) or "")
    self.classic:SetShown(a.classic ~= nil)
  end
  -- Sets the content positions for `width` and returns the card height.
  function card:Fit(width)
    local textX = CARD_PAD + CARD_ICON + 8
    local nameW = width - textX - CARD_PAD
    local nameH = textHeight(self.name, nameW)
    local metaH = textHeight(self.meta, nameW - 12)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -CARD_PAD)
    self.dot:ClearAllPoints()
    self.dot:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -(CARD_PAD + nameH + 2 + 3))
    self.meta:ClearAllPoints()
    self.meta:SetPoint("TOPLEFT", self, "TOPLEFT", textX + 12, -(CARD_PAD + nameH + 2))
    local y = CARD_PAD + math.max(CARD_ICON, nameH + 2 + metaH) + GAP
    local innerW = width - CARD_PAD * 2
    local textH = textHeight(self.text, innerW)
    self.text:ClearAllPoints()
    self.text:SetPoint("TOPLEFT", self, "TOPLEFT", CARD_PAD, -y)
    y = y + textH
    if self.classic:IsShown() then
      local classicH = textHeight(self.classic, innerW)
      self.classic:ClearAllPoints()
      self.classic:SetPoint("TOPLEFT", self, "TOPLEFT", CARD_PAD, -(y + 6))
      y = y + 6 + classicH
    end
    return y + CARD_PAD
  end
  return card
end

-- Cards in one or two columns (a wide page keeps the lines short), every row as high as its
-- highest card.
local function newCardGrid(parent, makeCard, minWidth, maxCols)
  local grid = CreateFrame("Frame", nil, parent)
  grid.cards, grid.shownCount = {}, 0
  function grid:Sync(count, paint)
    for i = 1, count do
      local card = self.cards[i]
      if not card then
        card = makeCard(self)
        self.cards[i] = card
      end
      paint(card, i)
      card:Show()
    end
    for i = count + 1, #self.cards do
      self.cards[i]:Hide()
    end
    self.shownCount = count
  end
  function grid:fgGridLayout(width)
    local cols = math.max(1, math.min(maxCols, math.floor((width + GAP) / (minWidth + GAP))))
    local cw = math.floor((width - GAP * (cols - 1)) / cols)
    local y = 0
    for first = 1, self.shownCount, cols do
      local rowH = 0
      for i = first, math.min(first + cols - 1, self.shownCount) do
        rowH = math.max(rowH, self.cards[i]:Fit(cw))
      end
      for i = first, math.min(first + cols - 1, self.shownCount) do
        local card = self.cards[i]
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", self, "TOPLEFT", (i - first) * (cw + GAP), -y)
        card:SetSize(cw, rowH)
      end
      y = y + rowH + GAP
    end
    y = math.max(1, y - GAP)
    self:SetHeight(y)
    return y
  end
  return grid
end

local function newRemovedRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.bar = row:CreateTexture(nil, "ARTWORK")
  row.bar:SetWidth(2)
  row.bar:SetPoint("TOPLEFT")
  row.bar:SetPoint("BOTTOMLEFT")
  ns.Bind(row.bar, function(t)
    t:SetColorTexture(Theme.color("danger", 0.8))
  end)
  row.name = W.Text(row, { role = "text", family = "heading", color = "text", wrap = true })
  row.text = W.Text(row, { role = "ui", color = "textSecondary", wrap = true })
  function row:fgGridLayout(width)
    local w = width - 12
    local nameH = textHeight(self.name, w)
    local textH = textHeight(self.text, w)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", 10, 0)
    self.text:ClearAllPoints()
    self.text:SetPoint("TOPLEFT", self, "TOPLEFT", 10, -(nameH + 2))
    local h = nameH + 2 + textH
    self:SetHeight(h)
    return h
  end
  row.Fit = row.fgGridLayout
  return row
end

local function newFactionHead(parent, side)
  local f = CreateFrame("Frame", nil, parent)
  f.side = side
  f.crest = K.IconSlot(f, K.FactionIconSpec(side))
  f.crest:SetPoint("LEFT")
  f.label = W.Text(f, { role = "text", family = "heading", color = factionColor(side) })
  f.label:SetPoint("LEFT", f.crest, "RIGHT", 6, 0)
  function f:Paint()
    W.SetText(self.label, nil, L["kit.faction." .. self.side])
  end
  function f:fgGridLayout()
    local h = scaled(24)
    self:SetHeight(h)
    return h
  end
  return f
end

-- The detail view of one race. :SetRace(slug) fills it, the page lays it out.
function RV.Detail(parent)
  local f = CreateFrame("Frame", nil, parent)
  local state = {}

  local head = CreateFrame("Frame", nil, f)
  head.icon = newBigIcon(head, 44)
  head.icon:SetPoint("TOPLEFT")
  head.name = W.Text(head, { role = "title", family = "heading", color = "text", wrap = true })
  head.factions = { A = newFactionHead(head, "A"), H = newFactionHead(head, "H") }
  function head:fgGridLayout(width)
    local textX = 44 + 12
    local nameH = textHeight(self.name, width - textX)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", textX, 0)
    local faction = self.factions[state.f or "A"]
    for _, other in pairs(self.factions) do
      other:SetShown(other == faction)
    end
    faction:ClearAllPoints()
    faction:SetPoint("TOPLEFT", self, "TOPLEFT", textX, -(nameH + 4))
    faction:SetWidth(math.max(1, width - textX))
    faction:fgGridLayout()
    local h = math.max(44, nameH + 4 + faction:GetHeight())
    self:SetHeight(h)
    return h
  end
  local summary = W.Text(f, { role = "text", color = "textSecondary", wrap = true })

  local classesHead = heading(f, "classes.race.classes")
  local chips = newChipGrid(f)
  local abilitiesHead = heading(f, "classes.race.abilities")
  local abilitiesNote = note(f)
  local cards = newCardGrid(f, newAbilityCard, 280, 2)
  local roleHead = heading(f, "classes.race.role")
  local roleNote = note(f)
  local role = W.Text(f, { role = "text", color = "text", wrap = true })
  local removedHead = heading(f, "classes.race.removed")
  local removed = newCardGrid(f, newRemovedRow, 240, 1)
  local classAbilitiesHead = heading(f, "classes.race.classAbilities")
  local classAbilities = W.Text(f, { role = "text", color = "text", wrap = true })

  local entries = {
    { head, gap = GAP },
    { summary, gap = SECTION_GAP },
    { classesHead, gap = 6 },
    { chips, gap = SECTION_GAP },
    { abilitiesHead, gap = 4 },
    { abilitiesNote, gap = 6 },
    { cards, gap = SECTION_GAP },
    { roleHead, gap = 4 },
    { roleNote, gap = 6 },
    { role, gap = SECTION_GAP },
    { removedHead, gap = 6 },
    { removed, gap = SECTION_GAP },
    { classAbilitiesHead, gap = 6 },
    { classAbilities, gap = SECTION_GAP },
  }

  function f:SetRace(slug)
    local info = RL.Info(slug)
    state.slug = info and slug or nil
    if not info then
      self:Hide()
      return
    end
    self:Show()
    state.f = info.f
    local race = { slug = slug, f = info.f, n = info.n }
    head.icon:SetSpec(K.RaceIconSpec(slug, info.f, ns.T(info.n)))
    W.SetText(head.name, nil, ns.T(info.n))
    for _, faction in pairs(head.factions) do
      faction:Paint()
    end
    W.SetText(summary, nil, info.summary or "")
    summary:SetShown(info.summary ~= nil)
    chips:Paint(race)
    local abilities = info.abilities or {}
    cards:Sync(#abilities, function(card, i)
      card:Paint(abilities[i])
    end)
    W.SetText(abilitiesNote, nil, englishNote() and L["classes.race.englishOnly"] or "")
    abilitiesNote:SetShown(englishNote() and #abilities > 0)
    abilitiesHead:SetShown(#abilities > 0)
    cards:SetShown(#abilities > 0)
    W.SetText(roleNote, nil, englishNote() and L["classes.race.englishOnly"] or "")
    roleNote:SetShown(englishNote() and info.role ~= nil)
    roleHead:SetShown(info.role ~= nil)
    W.SetText(role, nil, info.role or "")
    role:SetShown(info.role ~= nil)
    local gone = info.removed or {}
    removed:Sync(#gone, function(row, i)
      W.SetText(row.name, nil, gone[i].n)
      W.SetText(row.text, nil, gone[i].text)
    end)
    removedHead:SetShown(#gone > 0)
    removed:SetShown(#gone > 0)
    local lines = {}
    for _, e in ipairs(R.RaceAbilities(slug)) do
      lines[#lines + 1] = string.format(
        L["classes.race.line"],
        className(e.class),
        tostring(e.ability.l or "?"),
        ns.T(e.ability.n) or "?"
      )
    end
    W.SetText(classAbilities, nil, table.concat(lines, "\n"))
    classAbilitiesHead:SetShown(#lines > 0)
    classAbilities:SetShown(#lines > 0)
  end

  function f:fgGridLayout(width)
    if not state.slug then
      return 1
    end
    return stackEntries(self, entries, width)
  end
  f.parts = {
    head = head,
    chips = chips,
    cards = cards,
    removed = removed,
    role = role,
    summary = summary,
    classAbilities = classAbilities,
    abilitiesNote = abilitiesNote,
    roleNote = roleNote,
  }
  return f
end

-- Overview --------------------------------------------------------------------------------

local function newRaceCard(parent, race, onClick)
  local card = CreateFrame("Button", nil, parent)
  W.Fill(card, "surface", 1)
  card.border = W.Border(card, factionColor(race.f), 0.6)
  local hover = card:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.06)
  card.slug = race.slug
  card.icon = K.IconSlot(card, K.RaceIconSpec(race.slug, race.f, ns.T(race.n)))
  card.icon:SetPoint("TOPLEFT", CARD_PAD, -CARD_PAD)
  card.name = W.Text(card, { role = "h3", family = "heading", color = "text", wrap = true })
  card.count = W.Text(card, { role = "ui", color = "textSecondary" })
  card.abilities = {}
  local info = RL.Info(race.slug)
  for i, a in ipairs(info.abilities or {}) do
    local icon = newAbilityIcon(card, 24)
    icon:SetAbility(a)
    icon.dot = newDot(icon, 7)
    icon.dot:SetPoint("BOTTOMRIGHT", 3, -3)
    setDot(icon.dot, RL.STATUS_COLOR[a.st] or "textMuted")
    tooltip(icon, function()
      return a.n
    end, function()
      return abilityMeta(a) .. "\n" .. a.text
    end)
    card.abilities[i] = icon
  end
  card:SetScript(
    "OnClick",
    ns.Wrap("race-card", function()
      onClick(race.slug)
    end)
  )
  ns.Focus.register(card, function(self)
    self:Click()
  end)
  function card:Paint()
    W.SetText(self.name, nil, ns.T(race.n))
    W.SetText(self.count, nil, string.format(L["classes.over.count"], RL.ClassCount(race.slug)))
  end
  function card:Fit(width)
    local nameX = CARD_PAD + 20 + 6
    local nameH = textHeight(self.name, width - nameX - CARD_PAD)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self, "TOPLEFT", nameX, -CARD_PAD)
    local y = CARD_PAD + math.max(20, nameH) + GAP
    for i, icon in ipairs(self.abilities) do
      icon:ClearAllPoints()
      icon:SetPoint("TOPLEFT", self, "TOPLEFT", CARD_PAD + (i - 1) * 30, -y)
    end
    y = y + 24 + GAP
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPLEFT", self, "TOPLEFT", CARD_PAD, -y)
    y = y + math.ceil(self.count:GetStringHeight())
    return y + CARD_PAD
  end
  return card
end

-- Matrix of the races (rows) and classes (columns). Narrower than the matrix needs: the
-- matrix scrolls sideways with its own thin bar.
local LABEL_W, CELL_MIN, CELL_MAX = 150, 32, 48

local function newMatrix(parent, races, onClick)
  local host = CreateFrame("Frame", nil, parent)
  local clip = CreateFrame("Frame", nil, host)
  clip:SetClipsChildren(true)
  clip:SetPoint("TOPLEFT")
  local inner = CreateFrame("Frame", nil, clip)
  local scrollX, maxScroll = 0, 0

  local columns = {}
  for _, class in ipairs(R.CLASSES) do
    local col = CreateFrame("Frame", nil, inner)
    col.icon = K.IconSlot(col, K.ClassIconSpec(class))
    col.icon:SetPoint("CENTER")
    tooltip(col, function()
      return className(class)
    end)
    columns[#columns + 1] = col
  end

  local rows = {}
  for _, race in ipairs(races) do
    local row = { race = race, cells = {} }
    row.label = CreateFrame("Button", nil, inner)
    row.hover = row.label:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.08)
    row.icon = K.IconSlot(row.label, K.RaceIconSpec(race.slug, race.f, ns.T(race.n)))
    row.icon:SetPoint("LEFT", 4, 0)
    row.text = W.Text(row.label, { role = "ui", color = "text", wrap = true })
    row.line = inner:CreateTexture(nil, "BACKGROUND")
    ns.Bind(row.line, function(t)
      t:SetColorTexture(1, 1, 1, 0.07)
    end)
    row.label:SetScript(
      "OnClick",
      ns.Wrap("race-matrix", function()
        onClick(race.slug)
      end)
    )
    ns.Focus.register(row.label, function(self)
      self:Click()
    end)
    for _, class in ipairs(R.CLASSES) do
      local cell = CreateFrame("Frame", nil, inner)
      cell.check = W.CheckMark(cell, 14, "text")
      cell.check:SetPoint("CENTER")
      cell.mark = newDot(cell, 10)
      cell.mark:SetPoint("CENTER")
      cell.state = RL.ClassState(race.slug, class)
      cell.check:SetShown(cell.state == "available")
      cell.mark:SetShown(cell.state == "new")
      if cell.state == "new" then
        setDot(cell.mark, "success")
      end
      tooltip(cell, function()
        return ns.T(race.n) .. " / " .. className(class)
      end, function()
        return classTip(race, class)
      end)
      row.cells[#row.cells + 1] = cell
    end
    rows[#rows + 1] = row
  end

  -- Thin scrollbar below the matrix, shown only when the matrix is wider than the page.
  local bar = CreateFrame("Frame", nil, host)
  bar:SetHeight(8)
  bar:EnableMouse(true)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  ns.Bind(track, function(t)
    t:SetColorTexture(1, 1, 1, 0.12)
  end)
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  thumb:SetHeight(8)
  ns.Bind(thumb, function(t)
    t:SetColorTexture(Theme.color("accentDim", 0.9))
  end)

  local function applyScroll(x)
    scrollX = math.max(0, math.min(maxScroll, x))
    inner:ClearAllPoints()
    inner:SetPoint("TOPLEFT", clip, "TOPLEFT", -scrollX, 0)
    local trackW = bar:GetWidth()
    local clipW = clip:GetWidth()
    if maxScroll > 0 and trackW > 0 then
      local thumbW = math.max(20, trackW * clipW / (clipW + maxScroll))
      thumb:SetWidth(thumbW)
      thumb:ClearAllPoints()
      thumb:SetPoint("LEFT", bar, "LEFT", (trackW - thumbW) * scrollX / maxScroll, 0)
    end
  end
  local function scrollToCursor()
    local cx = GetCursorPosition()
    local frac = (cx / bar:GetEffectiveScale() - bar:GetLeft()) / math.max(1, bar:GetWidth())
    applyScroll(math.max(0, math.min(1, frac)) * maxScroll)
  end
  bar:SetScript("OnMouseDown", function(self)
    scrollToCursor()
    self:SetScript("OnUpdate", function(bar2)
      if not IsMouseButtonDown("LeftButton") then
        bar2:SetScript("OnUpdate", nil)
        return
      end
      scrollToCursor()
    end)
  end)
  bar:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  function host:Paint()
    for _, row in ipairs(rows) do
      W.SetText(row.text, nil, ns.T(row.race.n))
    end
  end

  function host:fgGridLayout(width)
    local cell = math.max(CELL_MIN, math.min(CELL_MAX, math.floor((width - LABEL_W) / #columns)))
    local innerW = LABEL_W + cell * #columns
    local headH = scaled(32)
    local y = headH
    for i, col in ipairs(columns) do
      col:ClearAllPoints()
      col:SetPoint("TOPLEFT", inner, "TOPLEFT", LABEL_W + (i - 1) * cell, 0)
      col:SetSize(cell, headH)
    end
    for _, row in ipairs(rows) do
      local textH = textHeight(row.text, LABEL_W - 4 - 20 - 6 - 4)
      local h = math.max(scaled(30), textH + 8)
      row.label:ClearAllPoints()
      row.label:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -y)
      row.label:SetSize(LABEL_W, h)
      row.text:ClearAllPoints()
      row.text:SetPoint("LEFT", row.label, "LEFT", 4 + 20 + 6, 0)
      row.line:ClearAllPoints()
      row.line:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -y)
      row.line:SetSize(innerW, 1)
      for i, c in ipairs(row.cells) do
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", inner, "TOPLEFT", LABEL_W + (i - 1) * cell, -y)
        c:SetSize(cell, h)
      end
      y = y + h
    end
    inner:SetSize(innerW, y)
    local clipW = math.min(width, innerW)
    clip:SetSize(clipW, y)
    maxScroll = math.max(0, innerW - clipW)
    bar:SetShown(maxScroll > 0)
    local total = y
    if maxScroll > 0 then
      bar:ClearAllPoints()
      bar:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -(y + 6))
      bar:SetWidth(clipW)
      total = y + 6 + 8
    end
    host:SetHeight(total)
    applyScroll(scrollX)
    return total
  end
  host.rows, host.columns, host.clip, host.inner, host.bar = rows, columns, clip, inner, bar
  return host
end

local function newFlow(parent, cards, minWidth)
  local flow = CreateFrame("Frame", nil, parent)
  function flow:fgGridLayout(width)
    local cols = math.max(1, math.min(#cards, math.floor((width + GAP) / (minWidth + GAP))))
    local cw = math.floor((width - GAP * (cols - 1)) / cols)
    local y = 0
    for first = 1, #cards, cols do
      local rowH = 0
      for i = first, math.min(first + cols - 1, #cards) do
        rowH = math.max(rowH, cards[i]:Fit(cw))
      end
      for i = first, math.min(first + cols - 1, #cards) do
        cards[i]:ClearAllPoints()
        cards[i]:SetPoint("TOPLEFT", self, "TOPLEFT", (i - first) * (cw + GAP), -y)
        cards[i]:SetSize(cw, rowH)
      end
      y = y + rowH + GAP
    end
    y = math.max(1, y - GAP)
    self:SetHeight(y)
    return y
  end
  return flow
end

-- Overview of all races. opts: onSelect(slug) (open the race), relayout() (the page lays out
-- again after the class choice changed).
function RV.Overview(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  local races = RL.Races()
  local state = { class = R.CLASSES[1] }

  local hint = W.Text(f, { key = "classes.over.hint", role = "ui", color = "textSecondary", wrap = true })
  local entries = { { hint, gap = SECTION_GAP } }
  local cards, flows = {}, {}
  for _, side in ipairs({ "A", "H" }) do
    local sideHead = newFactionHead(f, side)
    local list = {}
    for _, race in ipairs(races) do
      if race.f == side then
        local card = newRaceCard(f, race, opts.onSelect)
        list[#list + 1] = card
        cards[#cards + 1] = card
      end
    end
    local flow = newFlow(f, list, 230)
    flows[#flows + 1] = flow
    entries[#entries + 1] = { sideHead, gap = 6 }
    entries[#entries + 1] = { flow, gap = SECTION_GAP }
    flow.head = sideHead
  end

  local matrix = newMatrix(f, races, opts.onSelect)
  entries[#entries + 1] = { heading(f, "classes.over.matrix"), gap = 4 }
  entries[#entries + 1] =
    { W.Text(f, { key = "classes.over.matrixHint", role = "ui", color = "textSecondary", wrap = true }), gap = 8 }
  entries[#entries + 1] = { matrix, gap = SECTION_GAP }

  local classButtons, raceButtons
  classButtons = K.ClassButtons(f, {
    labelKey = false,
    get = function()
      return state.class
    end,
    set = function(class)
      state.class = class
      classButtons.Refresh()
      raceButtons.Refresh()
      f:Paint()
      opts.relayout()
    end,
  })
  raceButtons = K.RaceButtons(f, {
    races = races,
    get = function()
      return nil
    end,
    set = opts.onSelect,
    isShown = function(item)
      return RL.ClassState(item.slug, state.class) == "new"
    end,
  })
  local none = W.Text(f, { key = "classes.over.newNone", role = "ui", color = "textSecondary", wrap = true })
  entries[#entries + 1] = { heading(f, "classes.over.new"), gap = 4 }
  entries[#entries + 1] =
    { W.Text(f, { key = "classes.over.newHint", role = "ui", color = "textSecondary", wrap = true }), gap = 8 }
  entries[#entries + 1] = { classButtons, gap = 10 }
  entries[#entries + 1] = { raceButtons, gap = 6 }
  entries[#entries + 1] = { none, gap = 0 }

  function f:Paint()
    for _, side in ipairs(flows) do
      side.head:Paint()
    end
    for _, card in ipairs(cards) do
      card:Paint()
    end
    matrix:Paint()
    classButtons.Refresh()
    raceButtons.Refresh()
    none:SetShown(#RL.NewRaces(state.class) == 0)
  end

  function f:fgGridLayout(width)
    return stackEntries(self, entries, width)
  end
  f.cards, f.matrix, f.classButtons, f.raceButtons, f.state = cards, matrix, classButtons, raceButtons, state
  return f
end
