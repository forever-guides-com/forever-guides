-- Side panel at the right edge of Blizzard's spellbook window (shared Modules/SidePanel.lua) with the next
-- spells of the learn list: level, icon, name and rank, cost or the "needs talent" marker, and a counter
-- "x of y learned". A row of class icons switches the list to another class (plain level overview of that
-- class, no learned state and no costs); the choice lives only in memory, so a reload shows the own class
-- again. It comes in addition to the learn list tab (Modules/SpellbookPanel.lua) and gives way
-- to it while that tab shows. Data: ns.LevelLogic.Sections, the same split as the learn list page.
local _, ns = ...
local W, L, K, SP, LV, CL, R = ns.W, ns.L, ns.PageKit, ns.SidePanel, ns.LevelLogic, ns.CostLogic, ns.RefLogic

local Side = {}
ns.SpellbookSide = Side

local KEY = "spellbook"
local PAD, GAP, BUTTON, ROW_BASE, HEADER_H, LIST_ROWS, MAX_ROWS = 8, 4, 24, 36, 28, 10, 80

ns.AddLocale("enUS", {
  ["spellbook.side.tip"] = "Shows the next spells to learn. Click to expand or collapse.",
  ["spellbook.side.progress"] = "%d of %d learned",
  ["spellbook.side.done"] = "Everything learned.",
  ["spellbook.side.level"] = "Level %d",
  ["spellbook.side.total"] = "%d spells",
  ["spellbook.side.titleClass"] = "%s - %s",
})
ns.AddLocale("deDE", {
  ["spellbook.side.tip"] = "Zeigt die nächsten Zauber zum Lernen. Klicken klappt den Bereich auf oder zu.",
  ["spellbook.side.progress"] = "%d von %d gelernt",
  ["spellbook.side.done"] = "Alles gelernt.",
  ["spellbook.side.level"] = "Stufe %d",
  ["spellbook.side.total"] = "%d Zauber",
  ["spellbook.side.titleClass"] = "%s - %s",
})

-- The class shown in the panel; nil is the own class. Held in memory only, a reload starts with the own class.
local viewClass

function Side.Class()
  return viewClass or K.PlayerClass()
end

local function playerLevel()
  local ok, level = pcall(UnitLevel, "player")
  return ok and type(level) == "number" and level > 0 and level or nil
end

-- Counts and the open entries of the learn list of the own class, nearest level first: what can be learned
-- now, then what waits for a higher level. nil without data or a known level.
-- Returns { learned, total, rows = { { level, item, ready } } }.
function Side.Upcoming(class, level, limit)
  if not (class and level and K.HasData("Abilities")) then
    return nil
  end
  local res = LV.Sections(class, {
    playerLevel = level,
    isKnown = LV.IsKnown,
    race = K.PlayerRaceSlug(),
  })
  if res.plain then
    return nil
  end
  local learned, total, rows = 0, 0, {}
  for _, section in ipairs(res.sections) do
    total = total + section.count
    if section.id == "learned" then
      learned = section.count
    end
  end
  for _, id in ipairs({ "available", "locked" }) do
    for _, section in ipairs(res.sections) do
      if section.id == id then
        for _, card in ipairs(section.levels) do
          for _, item in ipairs(card.groups.teacher) do
            if #rows < (limit or MAX_ROWS) then
              rows[#rows + 1] = { level = card.level, item = item, ready = id == "available" }
            end
          end
        end
      end
    end
  end
  return { learned = learned, total = total, rows = rows }
end

-- Every entry of another class by level, nothing about the player (no known state, no race filter).
-- Returns { total, rows = { { level, item, ready = true, class } } } or nil without data.
function Side.ForClass(class)
  if not (class and K.HasData("Abilities")) then
    return nil
  end
  local rows, total = {}, 0
  for _, section in ipairs(LV.Sections(class, {}).sections) do
    total = total + section.count
    for _, card in ipairs(section.levels) do
      for _, item in ipairs(card.groups.teacher) do
        rows[#rows + 1] = { level = card.level, item = item, ready = true, class = class }
      end
    end
  end
  return { total = total, rows = rows }
end

-- The window the spellbook view sits in: the top-level frame above it.
local function windowOf(book)
  local node = book
  for _ = 1, 8 do
    local ok, parent = pcall(node.GetParent, node)
    if not ok or parent == nil or parent == UIParent then
      return node
    end
    node = parent
  end
  return node
end

local function costOf(item, class)
  local price = not item.known and CL.ItemPrice(item, class) or nil
  return CL.Text(price)
end

local function bindRow(row, data)
  local item, class = data.item, data.class or K.PlayerClass()
  row.data = data
  local chip = ns.LevelView.Chips({ item }, "default", class)[1]
  row.chip = chip
  row.spell:SetTexture(chip.icon)
  row.spell:SetAlpha(data.ready and 1 or 0.5)
  row.num:SetText(tostring(data.level))
  row.title:SetText(
    item.rank and string.format("%s %s", chip.name, string.format(L["levels.rank"], item.rank)) or chip.name
  )
  local cost = not data.class and costOf(item, class) or nil
  local bits = {}
  if item.talent then
    bits[#bits + 1] = L["levels.viaTalent"]
  end
  bits[#bits + 1] = cost or (not item.talent and string.format(L["spellbook.side.level"], data.level) or nil)
  row.sub:SetText(table.concat(bits, " · "))
  W.SetColor(row.sub, item.talent and "warning" or "textSecondary")
  SP.PaintRow(row, false, data.ready)
end

local function createRow(parent)
  local row = SP.Row(parent)
  ns.Bind(row, function()
    SP.PaintRow(row, false, row.data ~= nil and row.data.ready)
  end)
  row.fgName = function()
    local data = row.data
    return data and string.format("%s, %s", row.title:GetText() or "", row.sub:GetText() or "") or nil
  end
  local function tip()
    local chip = row.chip
    if chip then
      ns.ShowTooltip(row, chip.name, chip.tip)
    end
  end
  row:SetScript("OnEnter", function()
    row.hover = true
    SP.PaintRow(row, false, row.data ~= nil and row.data.ready)
    tip()
  end)
  row:SetScript("OnLeave", function()
    row.hover = false
    SP.PaintRow(row, false, row.data ~= nil and row.data.ready)
    ns.HideTooltip()
  end)
  row.fgOnFocus, row.fgOnBlur = tip, ns.HideTooltip
  ns.Focus.register(row, function() end)
  return row
end

local function listHeight(host, used)
  local rowH = K.scaledHeight(ROW_BASE)
  local height = tonumber(host:GetHeight())
  local rows = LIST_ROWS
  if height and height > 0 then
    rows = math.floor((height - used - PAD) / rowH)
  end
  return math.max(1, rows) * rowH
end

-- The panel for the spellbook view `book`; `full` is the frame of the learn list tab (the panel hides
-- while that shows). onOpen() opens the learn list in the add-on. nil while the client holds the window.
function Side.Attach(book, full, onOpen)
  local state = {}
  local p
  p = SP.Attach(windowOf(book), {
    key = KEY,
    parent = book,
    title = function()
      local class = Side.Class()
      if class == K.PlayerClass() then
        return L["spellbook.title"]
      end
      return string.format(L["spellbook.side.titleClass"], L["spellbook.title"], R.className(class))
    end,
    strip = function()
      return L["spellbook.title"]
    end,
    tip = "spellbook.side.tip",
    onToggle = function()
      Side.SyncEdge(state)
    end,
    -- The panel comes as the argument: the first layout runs inside SP.Attach, before `p` is assigned.
    onLayout = function(panel, open)
      if open and state.list then
        Side.Layout(panel, state)
      end
    end,
    build = function(body)
      local items = {}
      for _, class in ipairs(R.CLASSES) do
        items[#items + 1] = {
          value = class,
          label = "",
          tooltip = R.className(class),
          ring = K.ClassColorHex(class),
          idleRing = K.ClassColorHex(class),
          icon = K.ClassIconSpec(class),
        }
      end
      state.picker = K.ChoiceGroup(body, {
        items = items,
        get = Side.Class,
        click = function(class)
          Side.SetClass(p, class)
        end,
      })
      state.note = W.Text(body, { role = "small", color = "textSecondary", wrap = true })
      state.open = W.Action(body, {
        icon = "open",
        size = BUTTON,
        tooltip = "spellbook.open",
        tooltipText = "spellbook.open.tip",
        opens = true,
        onClick = function()
          if onOpen then
            onOpen()
          end
        end,
      })
      state.list = W.ScrollList(body, {
        rowHeight = K.scaledHeight(ROW_BASE),
        createRow = createRow,
        bindRow = bindRow,
      })
    end,
  })
  if not p then
    return nil
  end
  p.side = state
  state.panel = p
  if full then
    full:HookScript("OnShow", function()
      p:Hide()
    end)
    full:HookScript("OnHide", function()
      p:Show()
    end)
    p:SetShown(not full:IsShown())
  end
  p:HookScript("OnShow", function()
    Side.Update(p)
    Side.SyncEdge(state)
  end)
  p:HookScript("OnHide", function()
    Side.SyncEdge(state)
  end)
  Side.Update(p)
  return p
end

-- Shows the list of `class` (the own class resets the choice).
function Side.SetClass(p, class)
  viewClass = class ~= K.PlayerClass() and class or nil
  Side.Update(p)
end

-- Reads the learn list again and paints the counter and the rows.
function Side.Update(p)
  local state = p.side
  if not (state and state.list) then
    return
  end
  local class = Side.Class()
  local other = viewClass ~= nil
  local info = other and Side.ForClass(class) or Side.Upcoming(class, playerLevel())
  state.info = info
  state.picker.Refresh()
  if not info then
    state.note:SetText(L["kit.noData"])
  elseif other then
    state.note:SetText(string.format(L["spellbook.side.total"], info.total))
  elseif #info.rows == 0 then
    state.note:SetText(
      string.format(
        "%s\n%s",
        string.format(L["spellbook.side.progress"], info.learned, info.total),
        L["spellbook.side.done"]
      )
    )
  else
    state.note:SetText(string.format(L["spellbook.side.progress"], info.learned, info.total))
  end
  state.list:SetData(info and info.rows or {})
  p:Refresh()
end

-- Note and button on top, the list below it down to the bottom of the window.
function Side.Layout(p, state)
  local inner = p.opts.width - PAD * 2
  state.picker:ClearAllPoints()
  state.picker:SetPoint("TOPLEFT", p.body, "TOPLEFT", PAD, -PAD)
  state.picker:SetWidth(inner)
  local pickerH = state.picker:fgGridLayout(inner)
  local y = PAD + pickerH + GAP
  state.note:SetWidth(inner - BUTTON - GAP)
  state.note:ClearAllPoints()
  state.note:SetPoint("TOPLEFT", p.body, "TOPLEFT", PAD, -y)
  state.open:ClearAllPoints()
  state.open:SetPoint("TOPRIGHT", p.body, "TOPRIGHT", -PAD, -y)
  local top = y + math.max(BUTTON, math.ceil(state.note:GetStringHeight() or 0)) + PAD
  state.list:ClearAllPoints()
  state.list:SetPoint("TOPLEFT", p.body, "TOPLEFT", PAD, -top)
  state.list:SetSize(inner, listHeight(p.host, top + K.scaledHeight(HEADER_H)))
  state.list.Refresh()
end

-- The panel on its edge while it shows at the right of the window: the side tabs of the add-on hang on it.
function Side.EdgeFrame()
  local p = SP.Get(KEY)
  if p and p:IsShown() and p.mode == "right" then
    return p
  end
end

-- The side tabs of the add-on look for their place again when the panel appeared, vanished or moved.
function Side.SyncEdge(state)
  local active = Side.EdgeFrame() ~= nil
  local links = ns.BlizzardLinks
  if active ~= state.edge and links and links.Discover then
    state.edge = active
    pcall(links.Discover, "spellbook side")
  end
end

for _, event in ipairs(ns.LevelView.Events) do
  ns.On(event, function()
    ns.Debounce("spellbook-side", 0.3, function()
      local p = SP.Get(KEY)
      if p and p:IsVisible() then
        ns.Safe("spellbook-side", Side.Update, p)
      end
    end)
  end)
end
