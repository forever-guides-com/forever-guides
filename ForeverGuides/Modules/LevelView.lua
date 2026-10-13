-- Per-level learn list of the level overview page and the spellbook panel:
-- search, "from level", reset and one card per level, grouped into the
-- collapsible areas "already learned" (collapsed by default), "learnable now" and
-- "not learned yet" for the player's own class. Logic: ns.LevelLogic.Sections.
local _, ns = ...
local W, L, Theme, R, K, LV, CL = ns.W, ns.L, ns.Theme, ns.RefLogic, ns.PageKit, ns.LevelLogic, ns.CostLogic

ns.AddLocale("enUS", {
  ["levels.area.available"] = "Learnable now",
  ["levels.area.locked"] = "Not learned yet",
  ["levels.area.learned"] = "Already learned",
  ["levels.area.tip"] = "Click to collapse or expand this area.",
  ["levels.reset"] = "Reset filters",
  ["levels.summary"] = "%d already learned, %d learnable now, %d not learned yet",
  ["levels.otherClass"] = "No learned status: all entries for %s per level",
})

ns.AddLocale("deDE", {
  ["levels.area.available"] = "Jetzt lernbar",
  ["levels.area.locked"] = "Noch nicht gelernt",
  ["levels.area.learned"] = "Bereits gelernt",
  ["levels.area.tip"] = "Klicke, um diesen Bereich ein- oder auszuklappen.",
  ["levels.reset"] = "Filter zurücksetzen",
  ["levels.summary"] = "%d bereits gelernt, %d jetzt lernbar, %d noch nicht gelernt",
  ["levels.otherClass"] = "Kein Lernstatus: alle Einträge für %s pro Stufe",
})

local V = {}
ns.LevelView = V

local PAD = 12
local GROUP_GAP = 8
local ROW_GAP = 8
local HEAD_H = 26
local SECTION_COLORS = { learned = "sectionLearned", available = "sectionAvailable", locked = "sectionLocked" }
local EVENTS = { "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "LEARNED_SPELL_IN_TAB" }

-- Theme tokens per palette. "parchment" is for lists that sit directly on WoW's
-- own spellbook page: dark brown text and no dark card fill, the page shows through.
-- "dark" is the same compact list on an opaque dark surface (a skin addon hides the page):
-- the light tokens of the default palette, cards a step lighter than the surface under them.
-- Palettes of one view must agree on `compact` (layout of the filter row).
local PALETTES = {
  default = {
    fill = "surface",
    text = "text",
    secondary = "textSecondary",
    muted = "textMuted",
    accent = "accent2",
    success = "success",
    chips = { name = "text", meta = "textMuted", hover = { 1, 1, 1, 0.08 } },
  },
  dark = {
    compact = true,
    fill = "surface2",
    text = "text",
    secondary = "textSecondary",
    muted = "textMuted",
    accent = "accent2",
    success = "success",
    chips = { name = "text", meta = "textMuted", hover = { 1, 1, 1, 0.08 } },
  },
  parchment = {
    compact = true,
    text = "parchmentText",
    secondary = "parchmentTextSecondary",
    muted = "parchmentTextSecondary",
    accent = "parchmentAccent",
    success = "parchmentSuccess",
    border = "parchmentAccent",
    borderAlpha = 0.45,
    chips = { name = "parchmentText", meta = "parchmentTextSecondary", hover = { 0, 0, 0, 0.1 } },
  },
}

-- Areas the user toggled this session, shared by every view instance.
local toggled = {}
local live = {}

-- Live localized spell name when the addon language is the client language,
-- the data only carries English names otherwise.
local function itemName(item)
  if item.sid and C_Spell and C_Spell.GetSpellInfo and GetLocale and ns.GetActiveLocale() == GetLocale() then
    local ok, info = pcall(C_Spell.GetSpellInfo, item.sid)
    if ok and type(info) == "table" and info.name and info.name ~= "" then
      return info.name
    end
  end
  return ns.T(item.n) or "?"
end

-- The data icon name, else the live spell texture, else the question mark.
local function itemIcon(item)
  if item.i then
    return "Interface\\Icons\\" .. item.i
  end
  if item.sid and C_Spell and C_Spell.GetSpellTexture then
    local ok, texture = pcall(C_Spell.GetSpellTexture, item.sid)
    if ok and texture then
      return texture
    end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function itemMeta(item, pal)
  local bits = {}
  if item.rank then
    bits[#bits + 1] = string.format(L["levels.rank"], item.rank)
  end
  if item.quest then
    bits[#bits + 1] = L["levels.viaQuest"]
  end
  if item.known then
    bits[#bits + 1] = Theme.hexText(pal.success, L["levels.learned"])
  end
  return table.concat(bits, " · ")
end

-- Learned entries show no price, the cost is spent.
local function toChips(items, pal, class)
  local chips = {}
  for i, item in ipairs(items) do
    local meta = itemMeta(item, pal)
    local price = not item.known and CL.ItemPrice(item, class) or nil
    local text = CL.Text(price)
    if text then
      meta = meta ~= "" and (meta .. " · " .. text) or text
    end
    chips[i] = { icon = itemIcon(item), name = itemName(item), meta = meta, sid = item.sid, tip = CL.Tip(price) }
  end
  return chips
end

-- One row is either an area header or a level card. Level card: title, then the
-- chips of its abilities.
-- Everything hangs off the inner card frame, the outer row only adds the gap to
-- the next row.
local function layoutRow(row, width)
  if row.mode == "head" then
    return K.scaledHeight(HEAD_H) + ROW_GAP
  end
  local card = row.card
  local inner = width - PAD * 2
  row.title:ClearAllPoints()
  row.title:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -PAD)
  local y = PAD + math.ceil(row.title:GetStringHeight())
  -- The sum sits right of the title and drops below it when the card is too narrow.
  row.sum:ClearAllPoints()
  local sumW = math.ceil(row.sum:GetStringWidth())
  if sumW > 0 then
    -- Each coin icon gets a little slack, so a measure that misses an inline texture cannot clip the text.
    sumW = sumW + 2 * select(2, row.sum:GetText():gsub("|T", ""))
    row.sum:SetWidth(math.min(sumW, inner))
    if sumW + math.ceil(row.title:GetStringWidth()) + PAD <= inner then
      row.sum:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, -PAD)
    else
      row.sum:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -(y + 2))
      y = y + 2 + math.ceil(row.sum:GetStringHeight())
    end
  end
  if row.used then
    y = y + GROUP_GAP
    row.chips:ClearAllPoints()
    row.chips:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -y)
    row.chips:SetWidth(inner)
    y = y + row.chips:Layout(inner)
  end
  return y + PAD + ROW_GAP
end

local function makeHead(row)
  local head = CreateFrame("Button", nil, row)
  head:SetPoint("TOPLEFT")
  head:SetPoint("BOTTOMRIGHT", 0, ROW_GAP)
  local bg = head:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  -- Lightens the area color on hover, the black text only gains contrast.
  local hover = head:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.3)
  local line = head:CreateTexture(nil, "ARTWORK")
  line:SetPoint("BOTTOMLEFT")
  line:SetPoint("BOTTOMRIGHT")
  line:SetHeight(1)
  function head:fgApply()
    self.fgBgColor = SECTION_COLORS[self.fgSection] or "surface2"
    bg:SetColorTexture(Theme.color(self.fgBgColor))
  end
  ns.Bind(head, function(self)
    line:SetColorTexture(Theme.color("accentDim", 0.7))
    self:fgApply()
  end)
  head.label = W.Text(head, { role = "h3", family = "heading", color = "sectionText" })
  head.sum = W.Text(head, { role = "micro", color = "sectionText" })
  head.sum:SetPoint("RIGHT", -8, 0)
  head.label:SetPoint("LEFT", 8, 0)
  head.label:SetPoint("RIGHT", head.sum, "LEFT", -8, 0)
  head:SetScript(
    "OnClick",
    ns.Wrap("level-area", function()
      if row.onToggle then
        row.onToggle()
      end
    end)
  )
  head:SetScript("OnEnter", function()
    ns.ShowTooltip(head, L["levels.area.tip"])
  end)
  head:SetScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(head, function(self)
    self:Click()
  end)
  return head
end

local function makeRow(parent, pal)
  local row = CreateFrame("Frame", nil, parent)
  local card = CreateFrame("Frame", nil, row)
  card:SetPoint("TOPLEFT")
  card:SetPoint("BOTTOMRIGHT", 0, ROW_GAP)
  if pal.fill then
    W.Fill(card, pal.fill, 1)
  end
  W.Border(card, pal.border or "white", pal.borderAlpha)
  row.card = card
  row.title = W.Text(card, { role = "h3", family = "heading", color = pal.accent })
  row.sum = W.Text(card, { role = "micro", color = pal.secondary, justify = "RIGHT" })
  row.chips = K.ChipRow(card, pal.chips)
  row.head = makeHead(row)
  row.fgLayout = layoutRow
  return row
end

local function paintRow(row, entry, pal)
  local isHead = entry.section ~= nil
  row.mode = isHead and "head" or "card"
  row.head:SetShown(isHead)
  row.card:SetShown(not isHead)
  if isHead then
    row.onToggle = entry.onToggle
    row.head.label:SetText(entry.text)
    row.head.sum:SetText(entry.sumText or "")
    row.head.fgSection = entry.section
    row.head:fgApply()
    return
  end
  row.onToggle = nil
  row.title:SetText(string.format(L["levels.level"], entry.level))
  row.sum:SetText(entry.sumText or "")
  local items = entry.groups.teacher
  row.used = #items > 0
  row.chips:SetShown(row.used)
  row.chips:SetChips(toChips(items, pal, entry.class))
end

-- Empty or invalid text means level 1.
local function parseLevel(text)
  local n = tonumber(text)
  if not n then
    return 1
  end
  return math.min(LV.CAP, math.max(1, math.floor(n)))
end

local function playerLevel()
  if not UnitLevel then
    return nil
  end
  local ok, level = pcall(UnitLevel, "player")
  return ok and type(level) == "number" and level > 0 and level or nil
end

-- Slug of the player's race in Data.Races, nil when unknown.
local function playerRace()
  if not UnitRace then
    return nil
  end
  local ok, _, token = pcall(UnitRace, "player")
  if not ok or type(token) ~= "string" then
    return nil
  end
  local flat = token:lower()
  for _, r in ipairs((ns.Data and ns.Data.Races) or {}) do
    if flat == (r.slug:gsub("%-", "")) or (flat == "scourge" and r.slug == "undead") then
      return r.slug
    end
  end
end

-- Saved area states live in the account settings, { [area id] = true (collapsed)
-- | false (open) }. A missing or non-boolean entry (older versions only stored
-- true) falls back to the default: learned collapsed, every other area open.
local function collapsedMap()
  local settings = ns.db and ns.db.settings
  return settings and type(settings.levelsCollapsed) == "table" and settings.levelsCollapsed or {}
end

local function collapsedOf(id)
  local saved = collapsedMap()[id]
  if type(saved) == "boolean" then
    return saved
  end
  return id == "learned"
end

local function toggleCollapsed(id, wasClosed)
  local map = {}
  for k, v in pairs(collapsedMap()) do
    map[k] = v
  end
  map[id] = not wasClosed
  toggled[id] = true
  if ns.db then
    ns.Store.set("settings.levelsCollapsed", map)
  end
end

-- While a search is active, the learned area opens on its own when it holds
-- matches, unless the user toggled it this session. Other areas follow their
-- saved state.
local function isCollapsed(section, searching)
  if section.id == "learned" and searching and section.count > 0 and not toggled.learned then
    return false
  end
  return collapsedOf(section.id)
end

-- Hands the class and the level sum to the cards of a section and returns the
-- section's own sum. Learned entries carry no sums, the cost is spent.
local function priceSection(section, class)
  if section.id == "learned" then
    return nil
  end
  local all = {}
  for _, card in ipairs(section.levels) do
    local items = card.groups.teacher
    card.class = class
    card.sumText = CL.SumText(CL.SumItems(items, class))
    for _, item in ipairs(items) do
      all[#all + 1] = item
    end
  end
  return CL.SumItems(all, class)
end

local function headText(section, closed)
  return string.format("%s %s (%d)", closed and ">" or "v", L["levels.area." .. section.id], section.count)
end

-- Adds the filters, the summary line and the list to view's stack and returns
-- { Refresh, SetShown }. o: getClass() -> class token, anchor (tour anchor
-- prefix, "<anchor>.Filters" and "<anchor>.List"), palette ("parchment" for
-- lists on WoW's spellbook page: dark text, compact filter row, no hint line; "dark" for the
-- same list on a dark surface). handle.SetPalette(name) switches between palettes of the same
-- layout (parchment and dark) at runtime and repaints the list.
function V.Create(view, o)
  local palName = PALETTES[o.palette] and o.palette or "default"
  local pal = PALETTES[palName]
  local compact = pal.compact == true
  local s = view.stack
  local state = { search = "", from = 1 }
  local items = {}
  local handle = {}
  local refresh

  -- Frames of this view, so SetShown can hide them together. Paragraphs are
  -- already on the stack, everything else is added here.
  local function track(item)
    items[#items + 1] = item
    return item
  end
  local function add(item, opts)
    s:Add(item, opts)
    return track(item)
  end

  -- Texts that follow the palette: { font string, palette field }.
  local tinted = {}
  local function tint(fs, field)
    tinted[#tinted + 1] = { fs, field }
    return fs
  end

  local filters = CreateFrame("Frame", nil, view.content)
  K.Anchor(o.anchor .. ".Filters", filters)
  local searchLabel = tint(W.Text(filters, { key = "levels.search", role = "ui", color = pal.text }), "text")
  searchLabel:SetPoint("TOPLEFT")
  local box = W.EditBox(filters, {
    clear = true,
    onChange = function(text)
      state.search = text
      refresh()
    end,
  })
  box:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -4)
  box:SetWidth(compact and 200 or 240)
  local fromBox = W.EditBox(filters, {
    placeholder = "levels.fromPlaceholder",
    onChange = function(text)
      state.from = parseLevel(text)
      refresh()
    end,
  })
  fromBox.edit:SetNumeric(true)
  fromBox.edit:SetMaxLetters(2)
  fromBox:SetPoint("TOPLEFT", box, "TOPRIGHT", 24, 0)
  fromBox:SetWidth(56)
  local fromLabel = tint(W.Text(filters, { key = "levels.fromMe", role = "ui", color = pal.text }), "text")
  fromLabel:SetPoint("BOTTOMLEFT", fromBox, "TOPLEFT", 0, 4)
  if not compact then
    local mine = W.Button(filters, {
      key = "levels.mine",
      variant = "ghost",
      width = 100,
      height = 22,
      onClick = function()
        local own = playerLevel()
        if own then
          fromBox.edit:SetText(tostring(own))
          state.from = parseLevel(own)
          refresh()
        end
      end,
    })
    mine:SetPoint("LEFT", fromBox, "RIGHT", 8, 0)
    local fromHint = tint(W.Text(filters, { key = "levels.fromHint", role = "micro", color = pal.muted }), "muted")
    fromHint:SetPoint("TOPLEFT", fromBox, "BOTTOMLEFT", 0, -4)
  end
  local reset = W.Action(filters, {
    label = "act.reset",
    icon = "reset",
    tooltip = "levels.reset",
    variant = "secondary",
    width = 150,
    height = 22,
    onClick = function()
      state.search, state.from = "", 1
      box.edit:SetText("")
      fromBox.edit:SetText("")
      refresh()
    end,
  })
  if compact then
    reset:SetPoint("LEFT", fromBox, "RIGHT", 16, 0)
    add(filters, { height = K.scaledHeight(16) + 36 })
  else
    reset:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -14)
    add(filters, { height = K.scaledHeight(16) + 82 })
  end

  local count = tint(track(ns.AddParagraph(view, nil, { role = "ui", color = pal.secondary })), "secondary")
  if not compact then
    tint(track(ns.AddParagraph(view, "levels.hint", { role = "micro", color = pal.muted })), "muted")
  end
  tint(track(ns.AddParagraph(view, "cost.legend", { role = "micro", color = pal.muted })), "muted")

  -- One row pool per palette (rows and chips bake their colors in), made on first use. The stack
  -- holds the host, which lays out the pool of the current palette.
  local host = CreateFrame("Frame", nil, view.content)
  local pools = {}
  local function poolFor(p)
    if not pools[p] then
      pools[p] = K.RowPool(host, function(parent)
        return makeRow(parent, p)
      end)
    end
    return pools[p]
  end
  local function showActivePool()
    local active = poolFor(pal)
    for _, list in pairs(pools) do
      list:SetShown(list == active)
    end
  end
  function host:fgGridLayout(width)
    local list = poolFor(pal)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    list:SetWidth(width)
    local h = list:fgGridLayout(width)
    host:SetHeight(h)
    return h
  end
  local function paint(row, entry)
    paintRow(row, entry, pal)
  end
  K.Anchor(o.anchor .. ".List", host)
  add(host, { gap = 4 })
  showActivePool()
  local note = tint(track(ns.AddParagraph(view, nil, { role = "ui", color = pal.secondary })), "secondary")

  function refresh()
    if not K.HasData("Abilities") then
      note:SetText(L["kit.noData"])
      count:SetText("")
      poolFor(pal):Sync({}, paint)
      view:Layout()
      return
    end
    local class = o.getClass()
    local own = class == K.PlayerClass()
    local level = own and playerLevel() or nil
    local res = LV.Sections(class, {
      search = state.search,
      fromLevel = state.from,
      isKnown = level and LV.IsKnown or nil,
      playerLevel = level,
      race = own and playerRace() or nil,
      nameOf = itemName,
    })
    local searching = state.search:find("%S") ~= nil
    local rows, total, availableTotal = {}, 0, nil
    for _, section in ipairs(res.sections) do
      total = total + section.count
      local closed = false
      local sum = priceSection(section, class)
      if section.id == "available" then
        availableTotal = sum and CL.SumText(sum, { key = "cost.availableTotal" })
      end
      if not res.plain then
        closed = isCollapsed(section, searching)
        rows[#rows + 1] = {
          section = section.id,
          text = headText(section, closed),
          sumText = sum and CL.SumText(sum),
          onToggle = function()
            -- Flip what is shown now, an automatic search expansion included.
            toggleCollapsed(section.id, closed)
            refresh()
          end,
        }
      end
      if not closed then
        for _, card in ipairs(section.levels) do
          rows[#rows + 1] = card
        end
      end
    end
    poolFor(pal):Sync(rows, paint)
    handle.rows = rows
    local lines = {}
    if res.plain then
      local only = res.sections[1]
      count:SetText(total > 0 and string.format(L["levels.count"], total, #only.levels, R.className(class)) or "")
      if not own then
        lines[#lines + 1] = string.format(L["levels.otherClass"], R.className(class))
      end
    else
      local summary =
        string.format(L["levels.summary"], res.sections[1].count, res.sections[2].count, res.sections[3].count)
      count:SetText(availableTotal and (summary .. "\n" .. availableTotal) or summary)
    end
    if total == 0 then
      lines[#lines + 1] = L["levels.empty"]
    end
    note:SetText(table.concat(lines, "\n"))
    view:Layout()
  end

  handle.Refresh = refresh
  handle.palette = palName
  function handle.SetPalette(name)
    local target = PALETTES[name]
    if not target or target == pal or (target.compact == true) ~= compact then
      return
    end
    pal, handle.palette = target, name
    for _, entry in ipairs(tinted) do
      W.SetColor(entry[1], pal[entry[2]])
    end
    showActivePool()
    ns.Safe("level-view", refresh)
  end
  handle.state = state
  function handle:SetShown(shown)
    for _, item in ipairs(items) do
      item:SetShown(shown)
    end
  end
  function handle.IsVisible()
    return filters:IsVisible()
  end
  live[#live + 1] = handle
  return handle
end

local function refreshLive()
  for _, handle in ipairs(live) do
    if handle.IsVisible() then
      ns.Safe("level-view", handle.Refresh)
    end
  end
end

for _, event in ipairs(EVENTS) do
  ns.On(event, function()
    ns.Debounce("level-view-refresh", 0.3, refreshLive)
  end)
end

V.RefreshLive = refreshLive
-- Chip data of items for a palette name, for tests.
function V.Chips(items, palette, class)
  return toChips(items, PALETTES[palette or "default"], class)
end
V.Instances = live
V.SectionColors = SECTION_COLORS
