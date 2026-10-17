-- Filter panel at the right side of Blizzard's group finder (LFGParentFrame). Docked (settings.lfgPanelDock, the
-- default) it sits flush at the window and the column of side tabs hangs at its right edge (Modules/LfgPanelDock.lua),
-- otherwise it sits beside the column of side tabs.
-- It shows only while the window is open and its browse list is active. By default it opens by itself with the
-- window (settings.lfgPanelAuto, hook installed, no LFG Filter Forever); closing it (X or side tab) keeps it shut
-- until the window opens again, nothing of that is stored. With the setting off the player opens it with the
-- side tab, /fg gruppensuche or /fg lfg and the choice is stored (lfgFilter.open). The rules live in Modules/LfgBrowseFilterLogic.lua, the hook that removes the
-- entries in Modules/LfgBrowseFilter.lua, the search in Modules/LfgBrowseSearch.lua; this file builds the controls
-- and stores the choices in ns.db.lfgFilter.
--
-- Layout: two columns over the height of the window. Left the dungeons (category, All, None, My level and the list
-- of activities with its own scroll area), right the filters (own scroll area), below both the search button, the
-- counter line and the reset button. The width is 600 px at 100 % font (480 at the least, 900 at the most, all
-- scaled with the font size), the columns share it 50 : 50, a grip at the right edge changes it (mouse, or the
-- keys Left and Right with the focus on the grip; stored in lfgFilter.width). With too little room right of the
-- window the panel narrows to the room, and below the least width it becomes one column with the tabs "Dungeons"
-- and "Filter".
--
-- The panel is a child of the group finder window, built on the first opening. Nothing of Blizzard's is replaced:
-- only HookScript on the window and on the browse frame. Keyboard: Tab and Shift+Tab walk the controls of the
-- panel while the pointer is over it or a control has the focus, Enter and Space activate. Esc closes a panel the
-- player opened first (Esc stack); an automatic panel stays out of the stack, Esc closes Blizzard's window and the
-- panel goes with it. The controls leave the focus ring of the main window.
local _, ns = ...
local W, L, Theme, K = ns.W, ns.L, ns.Theme, ns.PageKit
local LB, H, S = ns.LfgBrowseFilterLogic, ns.LfgBrowseFilter, ns.LfgBrowseSearch

ns.AddLocale("enUS", {
  ["lfgp.title"] = "Filter",
  ["lfgp.count"] = "Filtered groups: %d/%d",
  ["lfgp.nosearch"] = "No search yet. Choose dungeons and click Search.",
  ["lfgp.tab.dungeons"] = "Dungeons",
  ["lfgp.tab.filter"] = "Filter",
  ["lfgp.category"] = "Category",
  ["lfgp.all"] = "All",
  ["lfgp.none"] = "None",
  ["lfgp.mine"] = "My level",
  ["lfgp.mark"] = "your level",
  ["lfgp.levels"] = "Levels %s",
  ["lfgp.row.range"] = "%s, levels %d to %d",
  ["lfgp.row.single"] = "%s, level %d",
  ["lfgp.row.from"] = "%s, from level %d",
  ["lfgp.row.upto"] = "%s, up to level %d",
  ["lfgp.dungeons.hint"] = "Search covers the checked dungeons",
  ["lfgp.dungeons.none"] = "No activities available.",
  ["lfgp.activity.unknown"] = "Activity %d",
  ["lfgp.search"] = "Search",
  ["lfgp.searching"] = "Searching...",
  ["lfgp.search.none"] = "Choose at least one dungeon",
  ["lfgp.search.failed"] = "Search failed. Please wait a moment and try again.",
  ["lfgp.search.blocked"] = "Search is blocked right now.",
  ["lfgp.show"] = "Show",
  ["lfgp.show.groups"] = "Groups looking for players",
  ["lfgp.show.players"] = "Players looking for a group",
  ["lfgp.show.open"] = "Only groups with a free slot",
  ["lfgp.show.open.tip"] = "Affects groups only",
  ["lfgp.preset.groups"] = "Groups seek players",
  ["lfgp.preset.players"] = "Players seek group",
  ["lfgp.preset.all"] = "Show everything",
  ["lfgp.resize"] = "Panel width",
  ["lfgp.resize.hint"] = "Drag or use Left and Right.\nEnter resets.",
  ["lfgp.roles"] = "Role",
  ["lfgp.role.tank"] = "Tank",
  ["lfgp.role.healer"] = "Healer",
  ["lfgp.role.damage"] = "Damage",
  ["lfgp.classes"] = "Class",
  ["lfgp.sizes"] = "Group size",
  ["lfgp.size.1"] = "1",
  ["lfgp.size.2"] = "2",
  ["lfgp.size.3"] = "3",
  ["lfgp.size.4"] = "4",
  ["lfgp.size.5"] = "5+",
  ["lfgp.level"] = "Leader level",
  ["lfgp.level.from"] = "From",
  ["lfgp.level.to"] = "To",
  ["lfgp.playstyle"] = "Playstyle",
  ["lfgp.playstyle.1"] = "Standard",
  ["lfgp.playstyle.2"] = "Relaxed",
  ["lfgp.playstyle.3"] = "Serious",
  ["lfgp.playstyle.4"] = "Expert",
  ["lfgp.text"] = "Name or activity",
  ["lfgp.text.hint"] = "One term per line or comma",
  ["lfgp.age"] = "Entry age",
  ["lfgp.age.0"] = "Any",
  ["lfgp.age.30"] = "Under 30 s",
  ["lfgp.age.60"] = "Under 1 min",
  ["lfgp.age.120"] = "Under 2 min",
  ["lfgp.age.300"] = "Under 5 min",
  ["lfgp.reset"] = "Reset filters",
  ["lfgp.where"] = "The filter shows in the group finder, on the search tab.",
  ["lfgp.off"] = "Filter panel is off, see Settings > Guild and contacts.",
})
ns.AddLocale("deDE", {
  ["lfgp.title"] = "Filter",
  ["lfgp.count"] = "Gefilterte Gruppen: %d/%d",
  ["lfgp.nosearch"] = "Noch keine Suche. Wähle Dungeons und klicke Suchen.",
  ["lfgp.tab.dungeons"] = "Dungeons",
  ["lfgp.tab.filter"] = "Filter",
  ["lfgp.category"] = "Kategorie",
  ["lfgp.all"] = "Alle",
  ["lfgp.none"] = "Keine",
  ["lfgp.mine"] = "Meine Stufe",
  ["lfgp.mark"] = "deine Stufe",
  ["lfgp.levels"] = "Stufen %s",
  ["lfgp.row.range"] = "%s, Stufen %d bis %d",
  ["lfgp.row.single"] = "%s, Stufe %d",
  ["lfgp.row.from"] = "%s, ab Stufe %d",
  ["lfgp.row.upto"] = "%s, bis Stufe %d",
  ["lfgp.dungeons.hint"] = "Gesucht wird in den angehakten Dungeons",
  ["lfgp.dungeons.none"] = "Keine Aktivitäten verfügbar.",
  ["lfgp.activity.unknown"] = "Aktivität %d",
  ["lfgp.search"] = "Suchen",
  ["lfgp.searching"] = "Suche läuft...",
  ["lfgp.search.none"] = "Mindestens einen Dungeon wählen",
  ["lfgp.search.failed"] = "Suche fehlgeschlagen. Bitte kurz warten und erneut versuchen.",
  ["lfgp.search.blocked"] = "Die Suche ist gerade gesperrt.",
  ["lfgp.show"] = "Zeigen",
  ["lfgp.show.groups"] = "Gruppen, die Spieler suchen",
  ["lfgp.show.players"] = "Spieler, die eine Gruppe suchen",
  ["lfgp.show.open"] = "Nur Gruppen mit freiem Platz",
  ["lfgp.show.open.tip"] = "Wirkt nur auf Gruppen",
  ["lfgp.preset.groups"] = "Gruppen suchen Spieler",
  ["lfgp.preset.players"] = "Spieler suchen Gruppe",
  ["lfgp.preset.all"] = "Alles zeigen",
  ["lfgp.resize"] = "Panelbreite",
  ["lfgp.resize.hint"] = "Ziehen oder Pfeiltasten.\nEnter setzt zurück.",
  ["lfgp.roles"] = "Rolle",
  ["lfgp.role.tank"] = "Tank",
  ["lfgp.role.healer"] = "Heiler",
  ["lfgp.role.damage"] = "Schaden",
  ["lfgp.classes"] = "Klasse",
  ["lfgp.sizes"] = "Gruppengröße",
  ["lfgp.size.1"] = "1",
  ["lfgp.size.2"] = "2",
  ["lfgp.size.3"] = "3",
  ["lfgp.size.4"] = "4",
  ["lfgp.size.5"] = "5+",
  ["lfgp.level"] = "Stufe des Leiters",
  ["lfgp.level.from"] = "Von",
  ["lfgp.level.to"] = "Bis",
  ["lfgp.playstyle"] = "Spielstil",
  ["lfgp.playstyle.1"] = "Standard",
  ["lfgp.playstyle.2"] = "Entspannt",
  ["lfgp.playstyle.3"] = "Ernst",
  ["lfgp.playstyle.4"] = "Experte",
  ["lfgp.text"] = "Name oder Aktivität",
  ["lfgp.text.hint"] = "Ein Begriff pro Zeile oder Komma",
  ["lfgp.age"] = "Eintragsalter",
  ["lfgp.age.0"] = "Beliebig",
  ["lfgp.age.30"] = "Unter 30 s",
  ["lfgp.age.60"] = "Unter 1 Min.",
  ["lfgp.age.120"] = "Unter 2 Min.",
  ["lfgp.age.300"] = "Unter 5 Min.",
  ["lfgp.reset"] = "Filter zurücksetzen",
  ["lfgp.where"] = "Der Filter erscheint in der Gruppensuche, im Reiter Suche.",
  ["lfgp.off"] = "Filter-Panel ist aus (Einstellungen, Gilde und Kontakte).",
})

local P = {}
ns.LfgFilterPanel = P

local PAD, COL_GAP = 10, 10
local HEAD, TAB_ROW = 34, 30
local GAP = 4 -- between the side tab column and the panel (not docked)
local FALLBACK = 56 -- width of the tab column when it cannot be measured (tab inset 4 plus tab 52)
local LEVEL_LIFT = 20 -- above the group finder window
local APPLY_DELAY = 0.3 -- typing: the list changes after a pause
local ATTACH_DELAY = 0.5
local RETRY_DELAY, RETRIES = 2, 3
local GRIP_WIDTH, KEY_STEP = 8, 20
local DROPDOWN_WIDTH = 170

local built, attached, attachPending
-- Runtime only, reset whenever the group finder opens: the player closed the panel, or opened it with the tab.
local dismissed, manual = false, false
local buildFailed -- building the frame raised once; only a click on the tab tries again
local refreshStatus

-- The dungeon column: what the game offers (snapshot), the category shown and its activities in display order.
local snapshot, category, entries = nil, 0, {}

local function state()
  return ns.db and ns.db.lfgFilter
end

local overlay -- the search overlay, built on the first search

local function window()
  local frame = rawget(_G, "LFGParentFrame")
  return type(frame) == "table" and frame or nil
end

local function browse()
  local frame = rawget(_G, "LFGBrowseFrame")
  return type(frame) == "table" and frame or nil
end

local function apply()
  H.Apply()
end

-- Writes one value of the state and filters again.
local function set(path, value)
  ns.Store.set("lfgFilter." .. path, value)
  apply()
end

-- One entry of a set of switches (numbers and class tokens are keys, so no path text).
local function setSwitch(field, key, value)
  local s = state()
  if s then
    s[field][key] = value
    ns.Emit("FG_SETTING_CHANGED", "lfgFilter." .. field, s[field])
    apply()
  end
end

local function typed(path, value)
  ns.Store.set("lfgFilter." .. path, value)
  ns.Debounce("lfg-panel-apply", APPLY_DELAY, apply)
end

-- Classes the game knows, with its own names; the addon's list when the client names none.
local function classEntries()
  local out = {}
  local count, info = rawget(_G, "GetNumClasses"), rawget(_G, "GetClassInfo")
  if type(count) == "function" and type(info) == "function" then
    local ok, n = pcall(count)
    for i = 1, ok and tonumber(n) or 0 do
      local okInfo, name, token = pcall(info, i)
      if okInfo and type(token) == "string" and token ~= "" then
        out[#out + 1] = { token = token, name = type(name) == "string" and name or token }
      end
    end
  end
  if #out == 0 then
    local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE") or rawget(_G, "LOCALIZED_CLASS_NAMES") or {}
    for _, token in ipairs(LB.CLASSES) do
      out[#out + 1] =
        { token = token, name = type(names[token]) == "string" and names[token] or ns.RefLogic.className(token) }
    end
  end
  return out
end

-- Controls ---------------------------------------------------------------------------------------------------------

-- A caption with checkboxes in columns. o: key, items = { { value, key } }, columns, get(value), set(value, on).
local function checkGroup(parent, o)
  local f = CreateFrame("Frame", nil, parent)
  local caption = W.Text(f, { key = o.key, role = "ui", family = "heading", color = "accent2" })
  caption:SetPoint("TOPLEFT")
  local boxes = {}
  for _, item in ipairs(o.items) do
    boxes[#boxes + 1] = W.Checkbox(f, {
      key = item.key,
      get = function()
        return o.get(item.value)
      end,
      set = function(on)
        o.set(item.value, on)
      end,
    })
  end
  function f:fgGridLayout(width)
    local top = math.ceil(caption:GetStringHeight()) + 4
    local row = Theme.lineHeight(22, "ui")
    local colWidth = math.max(1, (width - 6 * (o.columns - 1)) / o.columns)
    for i, box in ipairs(boxes) do
      local col, line = (i - 1) % o.columns, math.floor((i - 1) / o.columns)
      box:ClearAllPoints()
      box:SetPoint("TOPLEFT", f, "TOPLEFT", col * (colWidth + 6), -(top + line * (row + 2)))
      box:SetSize(colWidth, row)
    end
    local height = top + math.ceil(#boxes / o.columns) * (row + 2)
    f:SetHeight(height)
    return height
  end
  function f.Refresh()
    for _, box in ipairs(boxes) do
      box.Refresh()
    end
  end
  return f
end

-- One checkbox group over a "set of switches" of the state: a missing entry is on, off is stored as false.
local function switchGroup(parent, o)
  return checkGroup(parent, {
    key = o.key,
    columns = o.columns,
    items = o.items,
    get = function(value)
      local s = state()
      return not s or s[o.field][value] ~= false
    end,
    set = function(value, on)
      setSwitch(o.field, value, on)
    end,
  })
end

local function classGroup(parent)
  local items = {}
  for _, entry in ipairs(classEntries()) do
    items[#items + 1] = {
      value = entry.token,
      label = entry.name,
      ring = K.ClassColorHex(entry.token),
      idleRing = K.ClassColorHex(entry.token),
      icon = K.ClassIconSpec(entry.token),
    }
  end
  local group
  group = K.ChoiceGroup(parent, {
    items = items,
    labelKey = "lfgp.classes",
    get = function() end,
    click = function(token)
      local s = state()
      if s then
        -- Only the classes switched off are stored.
        if s.classes[token] == false then
          setSwitch("classes", token, nil)
        else
          setSwitch("classes", token, false)
        end
        group.Refresh()
      end
    end,
  })
  -- Several classes can be on: the group's own refresh knows one selection only.
  function group.Refresh()
    local s = state()
    for _, button in ipairs(group.buttons) do
      button:SetSelected(not s or s.classes[button.value] ~= false)
    end
  end
  group.Refresh()
  return group
end

local function levelRow(parent)
  local f = CreateFrame("Frame", nil, parent)
  local caption = W.Text(f, { key = "lfgp.level", role = "ui", family = "heading", color = "accent2" })
  caption:SetPoint("TOPLEFT")
  local function box(placeholder, field)
    local e = W.EditBox(f, {
      placeholder = placeholder,
      onChange = function(text)
        typed(field, math.max(0, math.min(LB.MAX_LEVEL, tonumber(text) or 0)))
      end,
    })
    e.edit:SetNumeric(true)
    e.edit:SetMaxLetters(3)
    return e
  end
  local low, high = box("lfgp.level.from", "levelMin"), box("lfgp.level.to", "levelMax")
  function f:fgGridLayout(width)
    local top = math.ceil(caption:GetStringHeight()) + 4
    local half = math.max(1, (width - 6) / 2)
    low:ClearAllPoints()
    low:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
    low:SetWidth(half)
    high:ClearAllPoints()
    high:SetPoint("TOPLEFT", f, "TOPLEFT", half + 6, -top)
    high:SetWidth(half)
    local height = top + 26
    f:SetHeight(height)
    return height
  end
  function f.Refresh()
    local s = state()
    low.edit:SetText(s and s.levelMin > 0 and tostring(s.levelMin) or "")
    high.edit:SetText(s and s.levelMax > 0 and tostring(s.levelMax) or "")
  end
  return f
end

-- Show group: presets, kinds of listing, free slot ----------------------------------------------------------------

local function showGroup(parent)
  local f = CreateFrame("Frame", nil, parent)
  local caption = W.Text(f, { key = "lfgp.show", role = "ui", family = "heading", color = "accent2" })
  caption:SetPoint("TOPLEFT")
  local presets, boxes = {}, {}
  for _, id in ipairs({ "groups", "players", "all" }) do
    presets[#presets + 1] = {
      id = id,
      button = W.Action(f, {
        key = "lfgp.preset." .. id,
        variant = "secondary",
        size = 24,
        onClick = function()
          local s = state()
          if s then
            LB.ApplyPreset(s, id)
            ns.Emit("FG_SETTING_CHANGED", "lfgFilter", s)
            apply()
            f.Refresh()
          end
        end,
      }),
    }
  end
  local function box(key, get, put, tip)
    boxes[#boxes + 1] = W.Checkbox(f, {
      key = key,
      tooltip = tip and key,
      tooltipText = tip,
      get = function()
        local s = state()
        return not s or get(s)
      end,
      set = function(on)
        put(on)
        f.Refresh()
      end,
    })
  end
  box("lfgp.show.groups", function(s)
    return s.show.groups ~= false
  end, function(on)
    setSwitch("show", "groups", on)
  end)
  box("lfgp.show.players", function(s)
    return s.show.players ~= false
  end, function(on)
    setSwitch("show", "players", on)
  end)
  box("lfgp.show.open", function(s)
    return s.onlyOpen == true
  end, function(on)
    set("onlyOpen", on)
  end, "lfgp.show.open.tip")
  function f:fgGridLayout(width)
    local top = math.ceil(caption:GetStringHeight()) + 4
    local button, row = Theme.lineHeight(24, "ui"), Theme.lineHeight(22, "ui")
    for i, preset in ipairs(presets) do
      preset.button:ClearAllPoints()
      preset.button:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(top + (i - 1) * (button + 4)))
      preset.button:SetSize(width, button)
    end
    top = top + #presets * (button + 4) + 4
    for i, item in ipairs(boxes) do
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(top + (i - 1) * (row + 2)))
      item:SetSize(width, row)
    end
    local height = top + #boxes * (row + 2)
    f:SetHeight(height)
    return height
  end
  function f.Refresh()
    local s = state()
    local current = s and LB.PresetOf(s)
    for _, preset in ipairs(presets) do
      preset.button:SetSelected(preset.id == current)
    end
    for _, item in ipairs(boxes) do
      item.Refresh()
    end
  end
  return f
end

-- Dungeon list ---------------------------------------------------------------------------------------------------

local function playerLevel()
  local fn = rawget(_G, "UnitLevel")
  local ok, level = pcall(fn or function() end, "player")
  return ok and type(level) == "number" and level or nil
end

-- Stores a checked set; all of the category is the default, nothing is "None" (the search button says so).
local function chooseActivities(chosen)
  local s = state()
  if s then
    LB.SetChosen(s, chosen, entries)
    ns.Emit("FG_SETTING_CHANGED", "lfgFilter.activities", s.activities)
    built.list.Refresh()
    refreshStatus()
  end
end

local function toggleActivity(id)
  local s = state()
  if s and id then
    local chosen = LB.Chosen(s, entries)
    chosen[id] = chosen[id] ~= true or nil
    LB.SetChosen(s, chosen, entries)
    ns.Emit("FG_SETTING_CHANGED", "lfgFilter.activities", s.activities)
    refreshStatus()
  end
end

-- The tab order: head, dungeon column, its rows, filter column, foot, grip.
local function rebuildItems()
  local out = {}
  for _, key in ipairs({ "head", "left", "rows", "right", "foot", "grip" }) do
    for _, item in ipairs(built.parts[key]) do
      out[#out + 1] = item
    end
  end
  built.items = out
end

local function claimFocus(from)
  local list, mine = ns.Focus.items, {}
  for i = #list, from + 1, -1 do
    table.insert(mine, 1, table.remove(list, i))
  end
  return mine
end

local LEVEL_GAP = 8 -- space between the name and the level column
local LEVEL_PROBE = "88-88" -- the widest range the game offers; digits are about equally wide

-- The row as a screen reader or the keyboard focus names it: "Name, levels 15 to 24".
local function spokenLabel(entry, name)
  local low, high = tonumber(entry.min) or 0, tonumber(entry.max) or 0
  if low > 0 and high > 0 then
    return low == high and string.format(L["lfgp.row.single"], name, low)
      or string.format(L["lfgp.row.range"], name, low, high)
  elseif low > 0 then
    return string.format(L["lfgp.row.from"], name, low)
  elseif high > 0 then
    return string.format(L["lfgp.row.upto"], name, high)
  end
  return name
end

-- One row: a checkbox, the name (cut with "..." when it does not fit), the level range at the right edge (never
-- cut, the tooltip has both whole) and, under the name, the marker for the activities of the player's level.
local function newRow(parent)
  local row = CreateFrame("Button", nil, parent)
  local box = CreateFrame("Frame", nil, row)
  box:SetSize(16, 16)
  box:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
  W.Fill(box, "surface2")
  local boxOn = W.Fill(box, "action", 1)
  local border = W.Border(box, "white", 0.4)
  local check = W.CheckMark(box, 12, "text")
  check:SetPoint("CENTER")
  row.label = W.Text(row, { role = "ui" })
  row.level = W.Text(row, { role = "ui", justify = "RIGHT", color = "textMuted" })
  row.level:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -3)
  row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -3)
  row.label:SetPoint("TOPRIGHT", row.level, "TOPLEFT", -LEVEL_GAP, 0)
  row.mark = W.Text(row, { key = "lfgp.mark", role = "small", color = "accent2" })
  function row.paint()
    local s = state()
    local on = s ~= nil and row.id ~= nil and LB.Chosen(s, entries)[row.id] == true
    check:SetShown(on)
    boxOn:SetShown(on)
    border.set(on and "actionHi" or "white", on and 1 or 0.4)
  end
  function row.tip()
    ns.ShowTooltip(
      row,
      row.text,
      row.range ~= "-" and string.format(L["lfgp.levels"], row.range) or nil,
      row.mine and { lines = { L["lfgp.mark"] } } or nil
    )
  end
  function row.fgName()
    return row.spoken
  end
  ns.Bind(row, row.paint)
  row:SetScript(
    "OnClick",
    ns.Wrap("lfg-dungeon", function()
      toggleActivity(row.id)
      row.paint()
    end)
  )
  row:SetScript("OnEnter", row.tip)
  row:SetScript("OnLeave", ns.HideTooltip)
  row.fgOnFocus, row.fgOnBlur = row.tip, ns.HideTooltip
  local from = #ns.Focus.items
  ns.Focus.register(row, function(self)
    self:Click()
  end)
  for _, item in ipairs(claimFocus(from)) do
    table.insert(built.parts.rows, item)
  end
  return row
end

local function bindRow(row, entry, level)
  row.id = entry.id
  row.text = LB.ActivityName(entry, string.format(L["lfgp.activity.unknown"], entry.id))
  row.range = LB.ActivityLevels(entry)
  row.spoken = spokenLabel(entry, row.text)
  row.label:SetText(row.text)
  row.level:SetText(row.range)
  row.mine = LB.InRange(entry, level)
  row.mark:SetShown(row.mine)
  row.paint()
  row:Show()
end

local function dungeonList(parent)
  local list = CreateFrame("Frame", nil, parent)
  local empty = W.Text(list, { key = "lfgp.dungeons.none", role = "small", color = "textMuted", wrap = true })
  local rows = {}
  local probe = W.Text(list, { role = "ui", text = LEVEL_PROBE })
  probe:Hide()
  function list.Refresh()
    local level = playerLevel()
    for i, entry in ipairs(entries) do
      rows[i] = rows[i] or newRow(list)
      bindRow(rows[i], entry, level)
    end
    for i = #entries + 1, #rows do
      rows[i].id = nil
      rows[i]:Hide()
    end
    empty:SetShown(#entries == 0)
    rebuildItems()
    if built.frame:IsShown() then
      built.leftView:Layout()
    end
  end
  function list:fgGridLayout(width)
    local single, markHeight = Theme.lineHeight(22, "ui"), Theme.lineHeight(14, "small")
    local line = Theme.lineHeight(16, "ui")
    local y = 0
    -- Measured at the real font, so the range stays whole at every font size.
    local widths = { probe:GetStringWidth() }
    for i = 1, #entries do
      widths[#widths + 1] = rows[i].level:GetStringWidth()
    end
    local levelWidth = LB.LevelColumnWidth(widths)
    for i = 1, #entries do
      local row = rows[i]
      local height = single + (row.mine and markHeight or 0)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
      row:SetSize(width, height)
      row.label:SetHeight(line)
      row.level:SetSize(levelWidth, line)
      row.mark:ClearAllPoints()
      row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -(3 + line))
      y = y + height + 2
    end
    if #entries == 0 then
      empty:ClearAllPoints()
      empty:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
      empty:SetWidth(math.max(1, width))
      y = math.ceil(empty:GetStringHeight())
    end
    y = math.max(1, y)
    list:SetHeight(y)
    return y
  end
  return list
end

-- Reads what the game offers and shows the category and its activities.
local function refreshDungeons()
  if not built then
    return
  end
  snapshot = S.Snapshot()
  local s = state()
  category = LB.ResolveCategory(s and s.categoryID or 0, snapshot.categories)
  -- The first time the dungeon category the game offers is stored, so the choice is explicit from then on.
  if s and s.categoryID == 0 and category > 0 then
    ns.Store.set("lfgFilter.categoryID", category)
  end
  local options = built.options
  for i = #options, 1, -1 do
    options[i] = nil
  end
  for _, entry in ipairs(snapshot.categories) do
    options[#options + 1] = { value = entry.id, text = entry.name }
  end
  if #options == 0 then
    options[1] = { value = 0, text = "-" }
  end
  entries = snapshot.activities[category] or {}
  built.category.Refresh()
  built.list.Refresh()
end

-- Keyboard ------------------------------------------------------------------------------------------------------

local function usable(frame)
  return frame:IsVisible() and (not frame.IsEnabled or frame:IsEnabled())
end

local function ownFocus()
  local current = ns.Focus.current
  if not (built and current) then
    return false
  end
  for _, item in ipairs(built.items) do
    if item == current then
      return true
    end
  end
  return false
end

local function step(direction)
  local list, index = {}, 0
  for _, item in ipairs(built.items) do
    if usable(item) then
      list[#list + 1] = item
      if item == ns.Focus.current then
        index = #list
      end
    end
  end
  if #list == 0 then
    return
  end
  index = index + direction
  if index < 1 then
    index = #list
  elseif index > #list then
    index = 1
  end
  ns.Focus.set(list[index])
end

local layout

-- Stores a width the player chose (0 = automatic again) and lays the panel out.
local function setWidth(width)
  ns.Store.set("lfgFilter.width", width)
  built.preview = nil
  layout()
end

local function onKey(frame, key)
  local _, handled = ns.Safe("lfg-panel-key", function()
    if key == "ESCAPE" then
      return ns.EscStack.Close(frame)
    end
    local own = ownFocus()
    if key == "TAB" and (own or frame:IsMouseOver()) then
      step(IsShiftKeyDown() and -1 or 1)
      return true
    end
    if own and (key == "UP" or key == "DOWN") then
      step(key == "UP" and -1 or 1)
      return true
    end
    if own and ns.Focus.current == built.grip and (key == "LEFT" or key == "RIGHT") then
      setWidth(LB.ClampWidth(built.width + (key == "LEFT" and -KEY_STEP or KEY_STEP), Theme.fontRatio("ui")))
      return true
    end
    if own and (key == "ENTER" or key == "SPACE") then
      return ns.Focus.activate()
    end
    return false
  end)
  pcall(frame.SetPropagateKeyboardInput, frame, not handled)
end

-- Layout ----------------------------------------------------------------------------------------------------------

-- Foot over both columns: the line (counter, hint or note), then the search and the reset button.
local function layoutFoot(inner, two, foreign)
  local foot, frame = built.foot, built.frame
  built.line:SetWidth(inner)
  local lineHeight = math.max(Theme.lineHeight(14, "small"), math.ceil(built.line:GetStringHeight()))
  local rowY = 8 + lineHeight + 4
  local searchHeight, resetHeight = Theme.lineHeight(32, "ui"), Theme.lineHeight(28, "ui")
  local height = foreign and 8 or (rowY + searchHeight + 8 + (two and 0 or resetHeight + 4))
  foot:ClearAllPoints()
  foot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  foot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  foot:SetHeight(height)
  built.line:ClearAllPoints()
  built.line:SetPoint("TOPLEFT", foot, "TOPLEFT", PAD, -8)
  built.search:ClearAllPoints()
  built.reset:ClearAllPoints()
  built.search:SetPoint("TOPLEFT", foot, "TOPLEFT", PAD, -rowY)
  if two then
    local searchWidth = math.floor(inner * 0.6) - 3
    built.search:SetSize(searchWidth, searchHeight)
    built.reset:SetPoint("TOPRIGHT", foot, "TOPRIGHT", -PAD, -(rowY + math.floor((searchHeight - resetHeight) / 2)))
    built.reset:SetSize(inner - searchWidth - 6, resetHeight)
  else
    built.search:SetSize(inner, searchHeight)
    built.reset:SetPoint("TOPLEFT", foot, "TOPLEFT", PAD, -(rowY + searchHeight + 4))
    built.reset:SetSize(inner, resetHeight)
  end
  return height
end

-- Head of the dungeon column: category, three buttons, hint.
local function layoutHead(leftWidth)
  local head, hint = built.leftHead, built.hint
  local button = Theme.lineHeight(24, "ui")
  local hintHeight = math.max(Theme.lineHeight(14, "small"), math.ceil(hint:GetStringHeight()))
  head:ClearAllPoints()
  head:SetPoint("TOPLEFT", built.left, "TOPLEFT", 0, 0)
  head:SetPoint("TOPRIGHT", built.left, "TOPRIGHT", 0, 0)
  head:SetHeight(46 + 4 + button + 4 + hintHeight)
  built.category:ClearAllPoints()
  built.category:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
  built.category:SetWidth(math.min(DROPDOWN_WIDTH, leftWidth))
  local avail = leftWidth - 8
  local wAll, wNone = math.floor(avail * 0.27), math.floor(avail * 0.29)
  local widths = { wAll, wNone, avail - wAll - wNone }
  local x = 0
  for i, control in ipairs({ built.all, built.none, built.mine }) do
    control:ClearAllPoints()
    control:SetPoint("TOPLEFT", head, "TOPLEFT", x, -50)
    control:SetSize(widths[i], button)
    x = x + widths[i] + 4
  end
  hint:ClearAllPoints()
  hint:SetPoint("TOPLEFT", head, "TOPLEFT", 0, -(50 + button + 4))
  hint:SetWidth(math.max(1, leftWidth))
  built.leftBody:ClearAllPoints()
  built.leftBody:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
  built.leftBody:SetPoint("BOTTOMRIGHT", built.left, "BOTTOMRIGHT", 0, 0)
end

-- Everything that depends on the width, the font size and the mode: the two columns or one column with tabs.
function layout()
  if not built then
    return
  end
  local frame, s = built.frame, state()
  local width, columns = LB.Layout(built.preview or (s and s.width) or 0, Theme.fontRatio("ui"), built.room)
  local two, foreign = columns == 2, H.Foreign()
  built.width, built.columns = width, columns
  frame:SetWidth(width)
  local inner = width - 2 * PAD
  local footHeight = layoutFoot(inner, two, foreign)

  local tabs = not two and not foreign
  built.tabs:ClearAllPoints()
  built.tabs:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -HEAD)
  built.tabs:SetWidth(inner)
  built.tabs:SetShown(tabs)
  local top = HEAD + (tabs and TAB_ROW or 0)
  local leftWidth, rightWidth = LB.Columns(width, PAD, COL_GAP)
  local left, right = built.left, built.right
  left:ClearAllPoints()
  right:ClearAllPoints()
  if two then
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -top)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, footHeight)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -top)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, footHeight)
  else
    leftWidth, rightWidth = inner, inner
    for _, column in ipairs({ left, right }) do
      column:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -top)
      column:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, footHeight)
    end
  end
  left:SetWidth(leftWidth)
  right:SetWidth(rightWidth)
  built.metrics = { width = width, columns = columns, left = leftWidth, right = rightWidth, foot = footHeight }
  left:SetShown(not foreign and (two or built.tab == "dungeons"))
  right:SetShown(two or foreign or built.tab == "filter")
  local at = PAD + leftWidth + math.floor(COL_GAP / 2)
  built.divider:ClearAllPoints()
  built.divider:SetPoint("TOPLEFT", frame, "TOPLEFT", at, -top)
  built.divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", at, footHeight)
  built.divider:SetWidth(1)
  built.divider:SetShown(two and not foreign)
  layoutHead(leftWidth)
  built.grip:ClearAllPoints()
  built.grip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -HEAD)
  built.grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  built.grip:SetWidth(GRIP_WIDTH)
  built.leftView:Layout()
  built.rightView:Layout()
end

-- Building -----------------------------------------------------------------------------------------------------

function refreshStatus()
  if not built then
    return
  end
  local foreign = H.Foreign()
  local text = foreign and L["lfgb.foreign"] or H.Paused() and L["lfgb.paused"] or nil
  built.status:SetText(text or "")
  built.status:SetShown(text ~= nil)
  W.SetColor(built.status, foreign and "textSecondary" or "warning")
  local note = S.Note()
  local line, color
  if note == "failed" then
    line, color = L["lfgp.search.failed"], "warning"
  elseif note == "blocked" then
    line, color = L["lfgp.search.blocked"], "warning"
  elseif not H.HasList() then
    line, color = L["lfgp.nosearch"], "textSecondary"
  else
    line, color = LB.CountText(L["lfgp.count"], H.Counts()), "textSecondary"
  end
  built.line:SetText(line)
  W.SetColor(built.line, color)
  built.line:SetShown(not foreign)
  built.reset:SetShown(not foreign)
  built.search:SetShown(not foreign)
  local busy = S.Busy()
  local none = state() ~= nil and state().noActivities == true
  W.SetText(built.search.label, busy and "lfgp.searching" or none and "lfgp.search.none" or "lfgp.search")
  built.search:SetEnabled(not busy and not none)
  if built.frame:IsShown() then
    layout()
  end
end

local function refreshControls()
  if not built then
    return
  end
  local foreign = H.Foreign()
  for _, group in ipairs(built.groups) do
    group:SetShown(not foreign)
    group.Refresh()
  end
  refreshDungeons()
  refreshStatus()
end

local function build(parent)
  local frame = CreateFrame("Frame", "ForeverGuidesLfgFilter", parent)
  frame:SetWidth(LB.WIDTH.base)
  frame:SetFrameLevel(parent:GetFrameLevel() + LEVEL_LIFT)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:Hide()
  W.Fill(frame, "surface", 1)
  W.Border(frame, "accentDim", 1)
  frame:SetScript("OnKeyDown", onKey)

  local parts = { head = {}, left = {}, rows = {}, right = {}, foot = {}, grip = {} }
  -- Controls register in creation order; each block takes its own from the shared list.
  local function block(key, make)
    local from = #ns.Focus.items
    make()
    for _, item in ipairs(claimFocus(from)) do
      table.insert(parts[key], item)
    end
  end

  local title = W.Text(frame, { key = "lfgp.title", role = "h3", family = "heading", color = "accent2" })
  title:SetPoint("TOPLEFT", 10, -8)
  local tabs
  block("head", function()
    local close = W.Action(frame, {
      icon = "close",
      size = 24,
      tooltip = "common.close",
      onClick = function()
        P.SetOpen(false)
      end,
    })
    close:SetPoint("TOPRIGHT", -6, -5)
    tabs = W.Tabs(frame, {
      tabs = { { id = "dungeons", key = "lfgp.tab.dungeons" }, { id = "filter", key = "lfgp.tab.filter" } },
      onSelect = function(id)
        if built then
          built.tab = id
          layout()
        end
      end,
    })
  end)

  -- Left column: category, choice buttons, hint and the list of activities.
  local left = CreateFrame("Frame", nil, frame)
  local leftHead = CreateFrame("Frame", nil, left)
  local options = { { value = 0, text = "-" } }
  local categoryBox, all, none, mine
  block("left", function()
    categoryBox = W.Dropdown(leftHead, {
      key = "lfgp.category",
      options = options,
      width = DROPDOWN_WIDTH,
      get = function()
        return category
      end,
      set = function(value)
        local s = state()
        if s then
          ns.Store.set("lfgFilter.categoryID", value)
          s.activities, s.noActivities = {}, false
          ns.Emit("FG_SETTING_CHANGED", "lfgFilter.activities", s.activities)
          refreshDungeons()
          refreshStatus()
        end
      end,
    })
    all = W.Action(leftHead, {
      key = "lfgp.all",
      variant = "secondary",
      size = 24,
      onClick = function()
        local picked = {}
        for _, entry in ipairs(entries) do
          picked[entry.id] = true
        end
        chooseActivities(picked)
      end,
    })
    none = W.Action(leftHead, {
      key = "lfgp.none",
      variant = "secondary",
      size = 24,
      onClick = function()
        chooseActivities({})
      end,
    })
    mine = W.Action(leftHead, {
      key = "lfgp.mine",
      variant = "secondary",
      size = 24,
      onClick = function()
        chooseActivities(LB.LevelSet(entries, playerLevel()))
      end,
    })
  end)
  local hint = W.Text(leftHead, { key = "lfgp.dungeons.hint", role = "small", color = "textMuted" })
  local leftBody = CreateFrame("Frame", nil, left)
  local leftView = ns.NewPageView(leftBody)
  leftView.stack.pad = 2
  local list = dungeonList(leftView.content)
  leftView.stack:Add(list, { gap = 0 })

  -- Right column: the filters.
  local right = CreateFrame("Frame", nil, frame)
  local rightView = ns.NewPageView(right)
  rightView.stack.pad = 4
  local content, stack = rightView.content, rightView.stack
  local status = W.Text(content, { role = "small", color = "warning", wrap = true })
  stack:Add(status, { gap = 8 })
  local groups = {}
  local function add(group, gap)
    groups[#groups + 1] = group
    stack:Add(group, { gap = gap or 12 })
  end
  block("right", function()
    add(showGroup(content))
    add(switchGroup(content, {
      key = "lfgp.roles",
      field = "roles",
      columns = 2,
      items = {
        { value = "tank", key = "lfgp.role.tank" },
        { value = "healer", key = "lfgp.role.healer" },
        { value = "damage", key = "lfgp.role.damage" },
      },
    }))
    add(classGroup(content))
    add(switchGroup(content, {
      key = "lfgp.sizes",
      field = "sizes",
      columns = 3,
      items = {
        { value = 1, key = "lfgp.size.1" },
        { value = 2, key = "lfgp.size.2" },
        { value = 3, key = "lfgp.size.3" },
        { value = 4, key = "lfgp.size.4" },
        { value = 5, key = "lfgp.size.5" },
      },
    }))
    add(levelRow(content))
    add(switchGroup(content, {
      key = "lfgp.playstyle",
      field = "playstyles",
      columns = 2,
      items = {
        { value = 1, key = "lfgp.playstyle.1" },
        { value = 2, key = "lfgp.playstyle.2" },
        { value = 3, key = "lfgp.playstyle.3" },
        { value = 4, key = "lfgp.playstyle.4" },
      },
    }))

    local textGroup = CreateFrame("Frame", nil, content)
    local textCaption = W.Text(textGroup, { key = "lfgp.text", role = "ui", family = "heading", color = "accent2" })
    textCaption:SetPoint("TOPLEFT")
    local area = W.TextArea(textGroup, {
      height = 56,
      onChange = function(text)
        typed("text", text:sub(1, LB.TEXT_LIMIT))
      end,
    })
    local textHint = W.Text(textGroup, { key = "lfgp.text.hint", role = "small", color = "textMuted", wrap = true })
    function textGroup:fgGridLayout(width)
      local top = math.ceil(textCaption:GetStringHeight()) + 4
      area:ClearAllPoints()
      area:SetPoint("TOPLEFT", textGroup, "TOPLEFT", 0, -top)
      area:SetWidth(math.max(1, width))
      textHint:ClearAllPoints()
      textHint:SetPoint("TOPLEFT", textGroup, "TOPLEFT", 0, -(top + 60))
      textHint:SetWidth(math.max(1, width))
      local height = top + 60 + math.ceil(textHint:GetStringHeight())
      textGroup:SetHeight(height)
      return height
    end
    function textGroup.Refresh()
      local s = state()
      area:SetValue(s and s.text or "")
    end
    add(textGroup)

    local ageOptions = {}
    for _, seconds in ipairs(LB.AGES) do
      ageOptions[#ageOptions + 1] = { value = seconds, key = "lfgp.age." .. seconds }
    end
    local age = W.Dropdown(content, {
      key = "lfgp.age",
      options = ageOptions,
      width = 200,
      get = function()
        local s = state()
        return s and s.maxAge or 0
      end,
      set = function(value)
        set("maxAge", value)
      end,
    })
    groups[#groups + 1] = age
    stack:Add(age, { height = 46, gap = 6 })
    stack:Add(CreateFrame("Frame", nil, content), { height = 8 })
  end)

  -- Foot over both columns.
  local foot = CreateFrame("Frame", nil, frame)
  local line = W.Text(foot, { role = "small", color = "textSecondary", wrap = true })
  local search, reset
  block("foot", function()
    search = W.Action(foot, {
      key = "lfgp.search",
      variant = "primary",
      size = 32,
      onClick = function()
        local s = state()
        S.Run(category, s and s.activities, s and s.noActivities)
        H.Ensure()
      end,
    })
    reset = W.Action(foot, {
      key = "lfgp.reset",
      icon = "reset",
      variant = "secondary",
      size = 28,
      onClick = function()
        local s = state()
        if s then
          LB.Reset(s)
          ns.Emit("FG_SETTING_CHANGED", "lfgFilter", s)
          apply()
          refreshControls()
        end
      end,
    })
  end)

  local divider = frame:CreateTexture(nil, "ARTWORK")
  ns.Bind(divider, function(t)
    t:SetColorTexture(1, 1, 1, Theme.lineAlpha())
  end)

  -- The grip at the right edge changes the width: drag with the mouse, Left and Right with the focus on it.
  local grip = CreateFrame("Button", nil, frame)
  grip:SetFrameLevel(frame:GetFrameLevel() + 5)
  grip:EnableMouse(true)
  local gripLine = grip:CreateTexture(nil, "OVERLAY")
  gripLine:SetPoint("CENTER")
  gripLine:SetSize(2, 40)
  ns.Bind(gripLine, function(t)
    t:SetColorTexture(Theme.color("accentDim", 0.8))
  end)
  local function showGripTip()
    ns.ShowTooltip(grip, L["lfgp.resize"], L["lfgp.resize.hint"])
  end
  local function endDrag()
    grip:SetScript("OnUpdate", nil)
    if built and built.preview then
      setWidth(built.preview)
    end
  end
  grip:SetScript("OnMouseDown", function()
    grip:SetScript("OnUpdate", function()
      if not IsMouseButtonDown("LeftButton") then
        endDrag()
        return
      end
      local scale, edge = frame:GetEffectiveScale(), frame:GetLeft()
      if type(scale) == "number" and scale > 0 and edge then
        built.preview = LB.ClampWidth(GetCursorPosition() / scale - edge, Theme.fontRatio("ui"))
        layout()
      end
    end)
  end)
  grip:SetScript("OnMouseUp", endDrag)
  grip:SetScript("OnEnter", showGripTip)
  grip:SetScript("OnLeave", ns.HideTooltip)
  grip.fgOnFocus, grip.fgOnBlur = showGripTip, ns.HideTooltip
  block("grip", function()
    ns.Focus.register(grip, function()
      setWidth(0)
    end)
  end)

  built = {
    frame = frame,
    parts = parts,
    items = {},
    left = left,
    leftHead = leftHead,
    leftBody = leftBody,
    leftView = leftView,
    right = right,
    rightView = rightView,
    status = status,
    line = line,
    foot = foot,
    search = search,
    reset = reset,
    tabs = tabs,
    tab = "dungeons",
    divider = divider,
    grip = grip,
    groups = groups,
    options = options,
    category = categoryBox,
    list = list,
    hint = hint,
    all = all,
    none = none,
    mine = mine,
  }
  tabs:Select("dungeons")
  rebuildItems()
  frame:HookScript("OnHide", function()
    ns.LfgPanelDock.Sync(nil)
    built.esc = nil
    if ownFocus() then
      ns.Focus.clear()
    end
  end)
  -- Esc closes the panel and remembers that it is closed; the key handler above stays.
  ns.WindowShell.RegisterEsc(frame, function()
    P.SetOpen(false)
    return true
  end)
  ns.Bind(frame, function()
    refreshStatus()
  end)
end

-- Placing ---------------------------------------------------------------------------------------------------------

local function rectEdge(frame, method)
  local ok, value = pcall(frame[method], frame)
  return ok and type(value) == "number" and value or nil
end

local function right(frame)
  return rectEdge(frame, "GetRight")
end

-- Width of the column of side tabs: Blizzard's three tabs and ours. Measured from the right edge of the window,
-- or from the near side of the column itself when it hangs at the panel (docked). A fixed width when nothing can
-- be measured.
local function columnWidth(win, docked)
  local from, links = right(win), ns.BlizzardLinks
  if not (from and links) then
    return FALLBACK
  end
  local far, near
  local tabs = docked and ns.LfgPanelDock.Tabs() or links.FindSideTabs(win)
  for _, button in ipairs(links.Buttons("lfg")) do
    tabs[#tabs + 1] = button
  end
  for _, tab in ipairs(tabs) do
    local r, l = tab:IsVisible() and right(tab), tab:IsVisible() and rectEdge(tab, "GetLeft")
    if r and l then
      far, near = math.max(far or r, r), math.min(near or l, l)
    end
  end
  local width = far and far - (docked and near or from) or 0
  return width >= 8 and width or FALLBACK
end

local function scaleOf(frame)
  local ok, scale = pcall(frame.GetEffectiveScale, frame)
  return ok and type(scale) == "number" and scale > 0 and scale or 1
end

-- Pixels, in the units of the panel, between the left edge of the panel (x right of the window) and the right edge
-- of the screen; nil when the geometry cannot be read.
local function roomRight(win, x)
  local edge, screen = right(win), right(UIParent)
  if not (edge and screen) then
    return nil
  end
  return screen * scaleOf(UIParent) / scaleOf(win) - (edge + x)
end

-- Docked, the panel sits flush at the window and the column of tabs takes room right of the panel.
local function place(win)
  built.frame:ClearAllPoints()
  local docked = ns.LfgPanelDock.Docked()
  local x = docked and 0 or columnWidth(win) + GAP
  built.frame:SetPoint("TOPLEFT", win, "TOPRIGHT", x, 0)
  built.frame:SetPoint("BOTTOMLEFT", win, "BOTTOMRIGHT", x, 0)
  local room = roomRight(win, x)
  built.room = room and docked and room - columnWidth(win, true) or room
end

-- Showing --------------------------------------------------------------------------------------------------------

-- Whether the panel opens by itself with the group finder: switch on, hook installed (not with LFG Filter Forever).
local function autoActive()
  local settings = ns.db and ns.db.settings
  return H.Offered() and H.Installed() and not H.Foreign() and not (settings and settings.lfgPanelAuto == false)
end

-- What the player wants: with the automatic panel everything except a close in this window session, otherwise
-- the stored choice of the tab.
local function intent()
  if autoActive() then
    return not dismissed
  end
  local s = state()
  return s ~= nil and s.open == true
end

-- Whether the panel is wanted: offered, wanted by the player, and the browse list of the open window is active.
local function wanted()
  local win, list = window(), browse()
  return state() ~= nil
    and intent()
    and H.Offered()
    and win ~= nil
    and win:IsShown()
    and list ~= nil
    and list:IsVisible()
end

-- Esc closes the panel first only when the player opened it (tab or command). An automatic panel stays out of the
-- Esc stack, so Esc closes Blizzard's window and the panel goes with it; it keeps the keyboard for Tab.
local function applyEsc()
  local on
  if autoActive() then
    on = manual
  else
    on = state() ~= nil and state().open == true
  end
  if built.esc == on then
    return
  end
  built.esc = on
  ns.WindowShell.SetEsc(built.frame, on)
  if not on and ns.can.propagateKeyboard then
    pcall(built.frame.SetPropagateKeyboardInput, built.frame, true)
    pcall(built.frame.EnableKeyboard, built.frame, true)
  end
end

function P.Update()
  local want = wanted()
  if want and not built and not buildFailed then
    local ok, err = pcall(function()
      build(window())
      refreshControls()
    end)
    if not ok then
      -- One try per opening by the player, never a loop of half built frames.
      buildFailed = true
      ns.Log.warn("lfg panel: %s", tostring(err))
    end
  end
  if built then
    if want then
      H.Ensure()
      ns.LfgPanelDock.Sync(built.frame)
      place(window())
      if not built.frame:IsShown() then
        refreshControls()
        built.frame:Show()
      end
      layout()
      applyEsc()
    else
      built.frame:Hide()
      ns.LfgPanelDock.Sync(nil)
    end
  end
  if ns.BlizzardLinks and ns.BlizzardLinks.SetSelected then
    ns.BlizzardLinks.SetSelected("lfg", state() ~= nil and intent() and H.Offered())
  end
end

-- The player opens or closes the panel. With the automatic panel that is a runtime choice for this window
-- session, otherwise it is stored.
function P.SetOpen(open)
  open = open == true
  if autoActive() then
    dismissed, manual = not open, open
  elseif state() then
    ns.Store.set("lfgFilter.open", open)
  end
  P.Update()
end

function P.IsOpen()
  return state() ~= nil and intent()
end

function P.IsShown()
  return built ~= nil and built.frame:IsShown()
end

function P.Frame()
  return built and built.frame
end

-- The controls of the panel in tab order (test seam).
function P.Items()
  return built and built.items or {}
end

-- Width, columns, column widths and foot height of the last layout (test seam).
function P.Metrics()
  return built and built.metrics or nil
end

-- The search overlay over Blizzard's list, nil before the first search (test seam).
function P.Overlay()
  return overlay
end

-- Side tab and /fg gruppensuche.
function P.Toggle()
  if not H.Offered() then
    ns.Notify(L["lfgp.off"], "info")
    return
  end
  H.NoticeForeign()
  H.Ensure()
  P.Schedule()
  buildFailed = false
  -- The automatic panel toggles by what the player sees: an open panel closes, otherwise it opens.
  local showing = P.IsOpen()
  if autoActive() then
    showing = P.IsShown()
  end
  P.SetOpen(not showing)
  if P.IsOpen() and not P.IsShown() then
    ns.Notify(L["lfgp.where"], "info")
  end
end

P.Slash = P.Toggle

-- Hooks ------------------------------------------------------------------------------------------------------------

-- opening: the group finder window itself, whose every opening starts without a close or a manual open.
local function hook(frame, opening)
  if type(frame) == "table" and type(frame.HookScript) == "function" then
    pcall(frame.HookScript, frame, "OnShow", function()
      if opening then
        dismissed, manual = false, false
      end
      ns.Safe("lfg-panel", P.Update)
    end)
    pcall(frame.HookScript, frame, "OnHide", function()
      ns.Safe("lfg-panel", P.Update)
    end)
  end
end

-- Hooks the window and its browse list once, after Blizzard built them (never while a file loads). False while
-- the frames do not exist yet.
function P.Attach()
  if attached then
    return true
  end
  local win, list = window(), browse()
  if not (win and list) then
    return false
  end
  attached = true
  hook(win, true)
  hook(list)
  P.Update()
  return true
end

-- Attaches after a delay; frames that are not there yet are tried again a few times.
function P.Schedule(tries)
  local timer = rawget(_G, "C_Timer")
  if attached or attachPending or type(timer) ~= "table" or type(timer.After) ~= "function" then
    return
  end
  attachPending = true
  pcall(timer.After, tries and RETRY_DELAY or ATTACH_DELAY, function()
    attachPending = false
    local _, done = ns.Safe("lfg-panel-attach", P.Attach)
    if done == false and (tries or 0) < RETRIES then
      P.Schedule((tries or 0) + 1)
    end
  end)
end

ns.On("PLAYER_LOGIN", function()
  P.Schedule()
end)
ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_GroupFinder_VanillaStyle" then
    P.Schedule()
  end
end)

-- Search overlay -------------------------------------------------------------------------------------------------

-- The list area of Blizzard's browse frame when it names one, else the whole frame.
local function listArea(list)
  for _, key in ipairs({ "ScrollBox", "ScrollFrame" }) do
    local part = rawget(list, key)
    if type(part) == "table" and type(part.GetObjectType) == "function" then
      return part
    end
  end
  return list
end

-- Our own frame over the list while a search of the panel runs: the old rows are void by then and must not be
-- hovered or clicked, and Blizzard's "no results" text must not show through. Nothing of Blizzard's is changed.
local function syncOverlay()
  local list = browse()
  local want = list ~= nil and S.Busy() and H.Installed() and not H.Foreign()
  if not want then
    if overlay then
      overlay:Hide()
    end
    return
  end
  if not overlay then
    overlay = CreateFrame("Frame", nil, list)
    overlay:EnableMouse(true)
    W.Fill(overlay, "surface", 1)
    local text = W.Text(overlay, { key = "lfgp.searching", role = "ui", justify = "CENTER", color = "textSecondary" })
    text:SetPoint("CENTER")
  end
  local area = listArea(list)
  overlay:ClearAllPoints()
  overlay:SetAllPoints(area)
  overlay:SetFrameLevel(area:GetFrameLevel() + 50)
  overlay:Show()
end

-- The hook counts changed (a search, a filter, a pause) or a search started or ended.
ns.On("FG_LFG_FILTER_CHANGED", refreshStatus)
ns.On("FG_LFG_SEARCH_CHANGED", function()
  refreshStatus()
  ns.Safe("lfg-search-overlay", syncOverlay)
end)
ns.On("FG_LFG_FILTER_INSTALLED", function()
  ns.Safe("lfg-panel", P.Update)
end)

ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.lfgPanel" or path == "settings.lfgPanelAuto" or path == "settings.lfgPanelDock" then
    P.Update()
  end
end)

-- The game offers other activities, or the player gained a level (the marker moves).
for _, event in ipairs({ "LFG_LIST_AVAILABILITY_UPDATE", "PLAYER_LEVEL_UP" }) do
  ns.On(event, function()
    if built and built.frame:IsShown() then
      refreshDungeons()
    end
  end)
end

-- Another screen size or UI scale changes the room right of the window.
for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
  ns.On(event, function()
    if built and built.frame:IsShown() then
      P.Update()
    end
  end)
end

-- Language change: captions and the counter follow, the rows are laid out again.
ns.On("FG_LOCALE_CHANGED", function()
  if built then
    refreshStatus()
    layout()
  end
end)
