-- Start page: who am I, data status, quick links, tour offer, character list.
local _, ns = ...
local W, L, Theme = ns.W, ns.L, ns.Theme

ns.AddLocale("enUS", {
  ["roster.title"] = "Your characters",
  ["roster.note"] = "Logged-in characters, stored locally, never sent.",
  ["roster.off"] = "List is off, switch it on in the settings.",
  ["roster.empty"] = "No characters yet, log in with each once.",
  ["roster.total"] = "Total: %d characters, gold of all: %s",
  ["roster.total1"] = "Total: 1 character, gold: %s",
  ["roster.sort.seen"] = "Last seen",
  ["roster.sort.name"] = "Name",
  ["roster.sort.level"] = "Level",
  ["roster.sort.gold"] = "Gold",
  ["roster.sort.played"] = "Played",
  ["roster.col.name"] = "Character",
  ["roster.col.level"] = "Lvl",
  ["roster.col.gold"] = "Gold",
  ["roster.col.played"] = "Played",
  ["roster.col.ilvl"] = "iLvl",
  ["roster.col.seen"] = "Last seen",
  ["roster.col.zone"] = "Zone",
  ["roster.col.guild"] = "Guild",
  ["roster.you"] = "(current)",
  ["roster.today"] = "today",
  ["roster.yesterday"] = "yesterday",
  ["roster.days"] = "%d days ago",
  ["roster.weeks"] = "%d weeks ago",
  ["roster.months"] = "%d months ago",
  ["roster.dateFormat"] = "%Y-%m-%d %H:%M",
  ["roster.forget"] = "Remove from list",
  ["roster.forget.title"] = "Remove character",
  ["roster.forget.text"] = "Remove? It appears again on next login.",
  ["roster.tip.level"] = "Level %s %s",
  ["roster.tip.zone"] = "Zone: %s",
  ["roster.tip.guild"] = "Guild: %s",
  ["roster.tip.ilvl"] = "Item level: %.1f",
  ["roster.tip.played"] = "Played: %s",
  ["roster.total.played"] = "Played time: %s",
  ["roster.total.playedMissing"] = "Played time: %s (%d not recorded yet)",
  ["roster.played.unknown"] = "not recorded yet",
  ["roster.tip.professions"] = "Professions: %s",
  ["roster.tip.seen"] = "Last seen: %s",
  ["roster.tip.asOf"] = "Gold, item level and place read: %s",
  ["roster.tip.build"] = "Game %s, addon %s",
})

ns.AddLocale("deDE", {
  ["roster.title"] = "Deine Charaktere",
  ["roster.note"] = "Angemeldete Charaktere, lokal, nie gesendet.",
  ["roster.off"] = "Liste aus, einschalten in den Einstellungen.",
  ["roster.empty"] = "Noch keine Charaktere, melde jeden einmal an.",
  ["roster.total"] = "Gesamt: %d Charaktere, Summe Gold: %s",
  ["roster.total1"] = "Gesamt: 1 Charakter, Gold: %s",
  ["roster.sort.seen"] = "Zuletzt",
  ["roster.sort.name"] = "Name",
  ["roster.sort.level"] = "Stufe",
  ["roster.sort.gold"] = "Gold",
  ["roster.sort.played"] = "Spielzeit",
  ["roster.col.name"] = "Charakter",
  ["roster.col.level"] = "Stufe",
  ["roster.col.gold"] = "Gold",
  ["roster.col.played"] = "Spielzeit",
  ["roster.col.ilvl"] = "iLvl",
  ["roster.col.seen"] = "Zuletzt",
  ["roster.col.zone"] = "Zone",
  ["roster.col.guild"] = "Gilde",
  ["roster.you"] = "(aktuell)",
  ["roster.today"] = "heute",
  ["roster.yesterday"] = "gestern",
  ["roster.days"] = "vor %d Tagen",
  ["roster.weeks"] = "vor %d Wochen",
  ["roster.months"] = "vor %d Monaten",
  ["roster.dateFormat"] = "%d.%m.%Y %H:%M",
  ["roster.forget"] = "Aus der Liste entfernen",
  ["roster.forget.title"] = "Charakter entfernen",
  ["roster.forget.text"] = "Entfernen? Er erscheint beim nächsten Login wieder.",
  ["roster.tip.level"] = "Stufe %s %s",
  ["roster.tip.zone"] = "Zone: %s",
  ["roster.tip.guild"] = "Gilde: %s",
  ["roster.tip.ilvl"] = "Gegenstandsstufe: %.1f",
  ["roster.tip.played"] = "Spielzeit: %s",
  ["roster.total.played"] = "Spielzeit gesamt: %s",
  ["roster.total.playedMissing"] = "Spielzeit gesamt: %s (%d noch nicht erfasst)",
  ["roster.played.unknown"] = "noch nicht erfasst",
  ["roster.tip.professions"] = "Berufe: %s",
  ["roster.tip.seen"] = "Zuletzt gesehen: %s",
  ["roster.tip.asOf"] = "Gold, Gegenstandsstufe und Ort: Stand %s",
  ["roster.tip.build"] = "Spiel %s, Addon %s",
})

local QUICK = { "talents", "trainers", "instances", "map", "macros", "character" }

-- Character list ---------------------------------------------------------------

local ICON, CREST = 20, 16
local GAP, DELETE = 8, 24
-- Left part of a row: crest, class icon, race icon, then the name.
local NAME_X = 4 + CREST + 4 + ICON + 4 + ICON + 6
local NAME_MIN = 120
local HEADER_H, HEADER_GAP = 18, 2
-- Columns right of the name in display order. All of them stay, a page or a font that leaves too little
-- room makes the table scroll sideways (S.ColumnLayout, W.HScrollArea).
local COLUMNS = {
  { id = "level", w = 40, justify = "RIGHT" },
  { id = "played", w = 84, justify = "RIGHT" },
  { id = "gold", w = 124, justify = "RIGHT" },
  { id = "ilvl", w = 44, justify = "RIGHT" },
  { id = "seen", w = 100 },
  { id = "zone", w = 140 },
  { id = "guild", w = 120 },
}
local FIT = { lead = NAME_X, tail = DELETE + GAP, gap = GAP, nameMin = NAME_MIN, columns = COLUMNS }
local SORTS = { "seen", "name", "level", "gold", "played" }
local sortMode = "seen"

-- Icons: the specs come from PageKit (the class, faction and race icons of the
-- choice buttons). This wrapper is the only place that knows how a roster icon
-- is built and painted.
local function iconSpec(kind, e)
  local K = ns.PageKit
  if kind == "class" then
    return K.ClassIconSpec(e.class or "?")
  elseif kind == "faction" then
    return e.faction and K.FactionIconSpec(e.faction) or nil
  end
  local name
  for _, r in ipairs((ns.Data and ns.Data.Races) or {}) do
    if r.slug == e.raceSlug then
      name = ns.T(r.n)
    end
  end
  return K.RaceIconSpec(e.raceSlug or e.race or "?", e.faction, name or e.race, e.sex)
end

local function newIcon(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  f.badge = f:CreateTexture(nil, "ARTWORK")
  f.badge:SetAllPoints()
  f.letter = W.Text(f, { role = "micro", color = "bg", justify = "CENTER" })
  f.letter:SetPoint("CENTER")
  return f
end

local function paintIcon(f, spec)
  f.tex:Hide()
  f.badge:Hide()
  f.letter:Hide()
  if not spec then
    return
  end
  local kind = spec.kind
  if kind == "badge" then
    f.badge:SetColorTexture(Theme.rgb(spec.color or "accent2"))
    f.badge:Show()
    f.letter:SetText(spec.letter or "?")
    f.letter:Show()
    return
  end
  f.tex:SetTexCoord(0, 1, 0, 1)
  if kind == "atlas" then
    f.tex:SetAtlas(spec.atlas)
  elseif kind == "sheet" then
    f.tex:SetTexture(spec.texture)
    f.tex:SetTexCoord(unpack(spec.coords))
  else
    local source = kind == "split" and spec.left or spec
    f.tex:SetTexture(source.texture)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  f.tex:Show()
end

-- "3 days ago" style text, the exact date is in the tooltip. `at` is a server time.
local function agoText(e, at)
  local days = ns.CharRoster.DaysSince(at)
  if e.current or not days or days == 0 then
    return L["roster.today"]
  elseif days == 1 then
    return L["roster.yesterday"]
  elseif days < 14 then
    return string.format(L["roster.days"], days)
  elseif days < 60 then
    return string.format(L["roster.weeks"], math.floor(days / 7))
  end
  return string.format(L["roster.months"], math.floor(days / 30))
end

local function seenText(e)
  return agoText(e, e.seen)
end

local function nameText(e)
  local hex = e.class and ns.PageKit.ClassColorHex(e.class)
  local name = hex and ("|cff" .. hex:sub(2) .. e.display .. "|r") or e.display
  if e.current then
    name = name .. " " .. Theme.hexText("textMuted", L["roster.you"])
  end
  return name
end

local function raceLabel(e)
  for _, r in ipairs((ns.Data and ns.Data.Races) or {}) do
    if r.slug == e.raceSlug then
      return ns.T(r.n)
    end
  end
  return e.race or "?"
end

-- `live` is the played time of the entry brought up to now (S.LivePlayed), nil without a reading.
local function tooltipText(e, live, now)
  local lines = {}
  local cls = e.class and ns.RefLogic.className(e.class) or "?"
  lines[#lines + 1] = string.format(L["roster.tip.level"], tostring(e.level or "?"), raceLabel(e) .. " " .. cls)
  if e.zone then
    lines[#lines + 1] = string.format(L["roster.tip.zone"], e.subzone and (e.zone .. ", " .. e.subzone) or e.zone)
  end
  if e.guild then
    lines[#lines + 1] = string.format(L["roster.tip.guild"], e.guild)
  end
  if e.ilvl then
    lines[#lines + 1] = string.format(L["roster.tip.ilvl"], e.ilvl)
  end
  local S = ns.RosterStatsLogic
  local playLines = live and S.TooltipLines(live, "playtime", now)
  if playLines then
    lines[#lines + 1] = string.format(L["roster.tip.played"], S.Duration(live.played))
    for i = 2, #playLines do
      lines[#lines + 1] = playLines[i]
    end
  else
    lines[#lines + 1] = string.format(L["roster.tip.played"], L["roster.played.unknown"])
  end
  if #e.professions > 0 then
    local parts = {}
    for _, p in ipairs(e.professions) do
      parts[#parts + 1] = string.format("%s %d/%d", p.name, p.skill, p.max)
    end
    lines[#lines + 1] = string.format(L["roster.tip.professions"], table.concat(parts, ", "))
  end
  local okDate, when = pcall(date, L["roster.dateFormat"], e.seen)
  if okDate and e.seen > 0 then
    lines[#lines + 1] = string.format(L["roster.tip.seen"], when)
  end
  -- What was read at the last login of a character that is not the current one.
  local asOf = not e.current and ns.CharRoster.AsOf(e)
  if asOf then
    lines[#lines + 1] = string.format(L["roster.tip.asOf"], agoText(e, asOf))
  end
  if e.build or e.addon then
    lines[#lines + 1] = string.format(L["roster.tip.build"], e.build or "?", e.addon or "?")
  end
  return table.concat(lines, "\n")
end

-- The first column of a row or of the header line (icons and name). While the table is scrolled sideways
-- it moves with the scroll position and has its own background, so it stays in view and the other columns
-- pass underneath.
local function newPin(owner)
  local pin = CreateFrame("Frame", nil, owner)
  pin.back = pin:CreateTexture(nil, "BACKGROUND")
  pin.back:SetAllPoints()
  ns.Bind(pin.back, function(t)
    t:SetColorTexture(Theme.color("bg"))
  end)
  pin.tint = pin:CreateTexture(nil, "BORDER")
  pin.tint:SetAllPoints()
  pin.line = pin:CreateTexture(nil, "BORDER")
  pin.line:SetPoint("BOTTOMLEFT")
  pin.line:SetPoint("BOTTOMRIGHT")
  pin.line:SetHeight(1)
  pin.line:SetColorTexture(1, 1, 1, 0.08)
  function pin:Place(x)
    pin:ClearAllPoints()
    pin:SetPoint("TOPLEFT", owner, "TOPLEFT", x, 0)
    pin:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", x, 0)
    for _, t in ipairs({ pin.back, pin.tint, pin.line }) do
      t:SetShown(x > 0)
    end
  end
  return pin
end

-- The text cells of a row or of the header line, placed by layoutCells. The name sits in the pin.
local function newCells(parent, pin, role, color)
  local cells = { name = W.Text(pin, { role = role, color = color }) }
  for _, c in ipairs(COLUMNS) do
    cells[c.id] = W.Text(parent, { role = role, color = color, justify = c.justify })
  end
  return cells
end

-- Columns at the places of the layout (S.ColumnLayout), the name takes what is left and is cut with "...".
local function layoutCells(parent, cells, pin, lay)
  for _, c in ipairs(COLUMNS) do
    local cell = cells[c.id]
    cell:ClearAllPoints()
    cell:SetPoint("LEFT", parent, "LEFT", lay.x[c.id], 0)
    cell:SetWidth(lay.w[c.id])
  end
  pin:SetWidth(lay.pinW)
  cells.name:ClearAllPoints()
  cells.name:SetPoint("LEFT", pin, "LEFT", NAME_X, 0)
  cells.name:SetWidth(lay.nameW)
end

-- getLayout() gives the column layout of the table, pins collects the pin of every row.
local function makeRow(parent, onForget, getLayout, pins)
  local row = CreateFrame("Frame", nil, parent)
  row:EnableMouse(true)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.line = row:CreateTexture(nil, "BORDER")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  row.line:SetColorTexture(1, 1, 1, 0.08)
  row.pin = newPin(row)
  pins[#pins + 1] = row.pin
  row.crest = newIcon(row.pin, CREST)
  row.crest:SetPoint("LEFT", row.pin, "LEFT", 4, 0)
  row.class = newIcon(row.pin, ICON)
  row.class:SetPoint("LEFT", row.pin, "LEFT", 4 + CREST + 4, 0)
  row.race = newIcon(row.pin, ICON)
  row.race:SetPoint("LEFT", row.class, "RIGHT", 4, 0)
  row.cells = newCells(row, row.pin, "ui", "text")
  row.del = W.Action(row, {
    icon = "trash",
    size = DELETE - 2,
    tooltip = "roster.forget",
    onClick = function()
      local key = row.entry and row.entry.key
      ns.Dialogs.Confirm("roster.forget.title", "roster.forget.text", function()
        if key and ns.CharRoster.Forget(key) then
          onForget()
        end
      end)
    end,
  })
  row.del:SetPoint("RIGHT", row, "RIGHT", -2, 0)
  row:SetScript("OnEnter", function()
    if row.entry then
      ns.ShowTooltip(row, row.entry.display .. "-" .. row.entry.realm, tooltipText(row.entry, row.live, row.now))
    end
  end)
  row:SetScript("OnLeave", ns.HideTooltip)

  -- Gold as coin icons, the plain form when the icons do not fit the column.
  function row:fgLayout()
    local lay = getLayout()
    layoutCells(row, row.cells, row.pin, lay)
    local e = row.entry
    if e then
      local gold = row.cells.gold
      local coins = ns.CostLogic.Format(e.money)
      gold:SetText(coins or (e.money == nil and "-" or "0"))
      if coins and gold:GetStringWidth() > lay.w.gold then
        gold:SetText(ns.CostLogic.Format(e.money, { plain = true }))
      end
    end
    return ns.PageKit.scaledHeight(30)
  end
  return row
end

-- `live`: the played time of the entry up to `now` (S.PlayedRows row).
local function paintRow(row, e, live, now)
  row.entry, row.live, row.now = e, live, now
  local c = row.cells
  c.name:SetText(nameText(e))
  c.level:SetText(e.level and tostring(e.level) or "-")
  c.played:SetText(
    live and live.played and ns.RosterStatsLogic.Duration(live.played) or Theme.hexText("textMuted", "-")
  )
  c.ilvl:SetText(e.ilvl and string.format("%.0f", e.ilvl) or "-")
  c.seen:SetText(seenText(e))
  c.zone:SetText(e.zone or "-")
  c.guild:SetText(e.guild or "-")
  paintIcon(row.crest, iconSpec("faction", e))
  paintIcon(row.class, iconSpec("class", e))
  paintIcon(row.race, iconSpec("race", e))
  row.bg:SetColorTexture(Theme.color("accent", e.current and 0.14 or 0))
  row.pin.tint:SetColorTexture(Theme.color("accent", e.current and 0.14 or 0))
  -- The character in use cannot be removed, it would come back at once.
  row.del:SetShown(not e.current)
end

-- Returns the section handle { refresh, off, note, empty, total, header, sortRow,
-- pool, buttons, result } the page and the tests work with.
local function rosterSection(view)
  local K, Roster, S = ns.PageKit, ns.CharRoster, ns.RosterStatsLogic
  local s = view.stack
  local section = {}
  ns.AddHeading(view, "roster.title")
  section.off = ns.AddParagraph(view, "roster.off", { role = "ui", color = "textMuted" })

  local buttons = {}
  local sortRow = CreateFrame("Frame", nil, view.content)
  local function paintSort()
    for _, mode in ipairs(SORTS) do
      local b, key = buttons[mode], "roster.sort." .. mode
      local active = mode == sortMode
      if active then
        W.SetText(b.label, nil, "[" .. L[key] .. "]")
      else
        W.SetText(b.label, key)
      end
      b.border.set(active and "accent" or "white", active and 1 or nil)
    end
  end
  for _, mode in ipairs(SORTS) do
    buttons[mode] = W.Button(sortRow, {
      key = "roster.sort." .. mode,
      width = 92,
      height = 22,
      onClick = function()
        sortMode = mode
        section.refresh()
      end,
    })
  end
  -- The buttons grow with the font and wrap into further lines when the bar is narrow.
  function sortRow:fgGridLayout(width)
    local x, y, h = 0, 0, 22
    local bw = math.ceil(92 * math.max(1, Theme.fontRatio("ui")))
    for _, mode in ipairs(SORTS) do
      if x > 0 and x + bw > width then
        x, y = 0, y + h + 6
      end
      buttons[mode]:SetWidth(bw)
      buttons[mode]:ClearAllPoints()
      buttons[mode]:SetPoint("TOPLEFT", sortRow, "TOPLEFT", x, -y)
      x = x + bw + 6
    end
    sortRow:SetHeight(y + h)
    return y + h
  end
  s:Add(sortRow, { gap = 8 })

  -- The table: header and rows in one content frame that scrolls sideways when the columns need more
  -- than the page gives. The first column stays in view (the pins), the bar sits under the rows.
  local lay, hs
  local pins = {}
  local function placePins()
    local x = lay and lay.frozen and hs:GetScroll() or 0
    for _, pin in ipairs(pins) do
      pin:Place(x)
    end
  end
  hs = W.HScrollArea(view.content, { onScroll = placePins, passTo = view.area })
  local header = CreateFrame("Frame", nil, hs.content)
  header.pin = newPin(header)
  pins[#pins + 1] = header.pin
  header.cells = newCells(header, header.pin, "micro", "textMuted")
  for id, cell in pairs(header.cells) do
    cell:SetText(L["roster.col." .. id])
  end
  local pool = K.RowPool(hs.content, function(parent)
    return makeRow(parent, function()
      section.refresh()
    end, function()
      return lay
    end, pins)
  end)
  K.Anchor("FG.Dashboard.Roster", pool)
  function hs:fgGridLayout(width)
    lay = S.ColumnLayout(width, Theme.fontRatio("ui"), FIT)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", hs.content, "TOPLEFT", 0, 0)
    header:SetSize(lay.contentW, HEADER_H)
    layoutCells(header, header.cells, header.pin, lay)
    pool:ClearAllPoints()
    pool:SetPoint("TOPLEFT", hs.content, "TOPLEFT", 0, -(HEADER_H + HEADER_GAP))
    pool:SetWidth(lay.contentW)
    local rows = pool:fgGridLayout(lay.contentW)
    return hs:SetLayout(lay.viewW, lay.contentW, HEADER_H + HEADER_GAP + rows)
  end
  s:Add(hs, { gap = 8 })
  section.empty = ns.AddParagraph(view, "roster.empty", { role = "text", color = "textSecondary" })
  section.total = ns.AddParagraph(view, nil, { role = "ui", color = "text" })
  section.note = ns.AddParagraph(view, "roster.note", { role = "micro", color = "textMuted" })

  function section.refresh()
    local enabled = Roster.Enabled()
    local now = Roster.Now()
    -- PlayedRows drops the hidden characters and orders by played time, the other modes sort the
    -- same entries again.
    local result = S.PlayedRows(Roster.List(), now)
    local list, live = {}, {}
    for _, p in ipairs(result.rows) do
      list[#list + 1] = p.entry
      live[p.entry.key] = p
    end
    if sortMode ~= "played" then
      Roster.Sort(list, sortMode)
    end
    local has = #list > 0
    section.off:SetShown(not enabled)
    section.note:SetShown(enabled)
    section.empty:SetShown(enabled and not has)
    for _, f in ipairs({ sortRow, hs, header, pool, section.total }) do
      f:SetShown(has)
    end
    pool:Sync(list, function(row, e)
      paintRow(row, e, live[e.key], now)
    end)
    local count, gold = Roster.Totals(list)
    local coins = ns.CostLogic.Format(gold) or "0"
    local time = S.Duration(result.total)
    local playedText = result.missing > 0 and string.format(L["roster.total.playedMissing"], time, result.missing)
      or string.format(L["roster.total.played"], time)
    section.total:SetText(
      (count == 1 and string.format(L["roster.total1"], coins) or string.format(L["roster.total"], count, coins))
        .. ", "
        .. playedText
    )
    section.result = result
    paintSort()
    view:Layout()
  end
  section.sortRow, section.header, section.pool, section.buttons = sortRow, header, pool, buttons
  section.scroller = hs
  return section
end

local function build(container)
  local view = ns.NewPageView(container)
  ns.AddParagraph(view, "dashboard.welcome", { color = "text", role = "text" })

  local charCard = W.Card(view.content, { key = "dashboard.character" })
  local charText = W.Text(charCard, { role = "text", wrap = true })
  charText:SetPoint("TOPLEFT", 12, charCard.contentTop)
  charText:SetPoint("RIGHT", -12, 0)

  local dataCard = W.Card(view.content, { key = "dashboard.data" })
  local dataText = W.Text(dataCard, { role = "ui", color = "textSecondary", wrap = true })
  dataText:SetPoint("TOPLEFT", 12, dataCard.contentTop)
  dataText:SetPoint("RIGHT", -12, 0)

  view.stack:Add(W.Grid(view.content, { charCard, dataCard }, 96))

  ns.AddHeading(view, "dashboard.quick")
  local tiles = {}
  for _, id in ipairs(QUICK) do
    local page = ns.Router:get(id)
    if page then
      local b = W.Button(view.content, {
        key = page.title,
        variant = "secondary",
        height = 32,
        onClick = function()
          ns.Router:navigate(id)
        end,
      })
      tiles[#tiles + 1] = b
    end
  end
  view.stack:Add(W.Grid(view.content, tiles, 32, 8))

  local tour = W.Action(view.content, {
    label = "act.tour",
    icon = "play",
    tooltip = "dashboard.tour",
    variant = "primary",
    width = 200,
    onClick = function()
      ns.TutorialUI.Start("addon-start")
    end,
  })
  view.stack:Add(tour, { height = 26, width = 200 })

  local roster = rosterSection(view)
  view.roster = roster

  function view:Show()
    local _, classFile = UnitClass("player")
    local first, surname = UnitName("player")
    local name = ns.CharRoster.JoinName(first, surname) or "?"
    local level = UnitLevel("player") or "?"
    local faction = UnitFactionGroup("player")
    local cls = classFile and Theme.hexText(classFile, L["class." .. classFile]) or "?"
    local fac = faction == "Alliance" and Theme.hexText("alliance", L["faction.alliance"])
      or faction == "Horde" and Theme.hexText("horde", L["faction.horde"])
      or ""
    charText:SetText(
      string.format("%s\n%s %s %s", name, L["common.level"], tostring(level), cls)
        .. (fac ~= "" and ("\n" .. fac) or "")
    )
    local m = ns.Data.Manifest
    if m then
      dataText:SetText(ns.DataStatusText() .. "\n" .. (ns.T(ns.Data.Trainers and ns.Data.Trainers.basis) or ""))
    else
      dataText:SetText(L["data.notLoaded"])
    end
    roster.refresh()
  end
  ns.On("FG_ROSTER_CHANGED", function()
    if container:IsShown() then
      roster.refresh()
    end
  end)
  return view
end

ns.RegisterPage({
  id = "dashboard",
  order = 10,
  group = "main",
  title = "page.dashboard",
  icon = ns.ICONS.dashboard,
  aliases = { "start", "home", "dashboard" },
  build = build,
})
