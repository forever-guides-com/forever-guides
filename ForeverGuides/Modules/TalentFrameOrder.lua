-- The skill order of the active build at the game's talent window: step numbers on the talent buttons
-- (setting "Numbers in the talent tree", off by default) and a collapsible side panel with the steps
-- (setting "Skill order at the talent window", on by default, collapsed at first). Only the own class and
-- the talent group the window shows.
--
-- Everything drawn is our own: child frames of the talent window (bar, panel, numbers, border) that are
-- anchored to the game's buttons and window. As children they share its strata, follow it when another
-- window is raised over it and hide with it; the window is no protected frame (the side tabs of the
-- add-on are its children too), we only create our own frames below it and never write a field onto it.
-- No protected function is called: only method calls, HookScript and hooksecurefunc, installed shortly after
-- Blizzard_PlayerSpells loaded (never a TOC dependency).
-- The game rebuilds its talent buttons (all new objects), so every redraw looks the buttons up again by
-- node id. Hooks only queue a redraw; nothing is read or anchored in combat, it waits for the combat to end.
-- Stored: settings.talentFrameNumbers, settings.talentFramePanel, and per character
-- talentOrderUi.frameOpen (panel expanded) and talentOrderUi.frameHideDone (learned steps hidden).
local _, ns = ...
local W, L, Theme, K, Store = ns.W, ns.L, ns.Theme, ns.PageKit, ns.Store
local TA, TL, TalentApply, F = ns.TalentActive, ns.TalentLogic, ns.TalentApply, ns.TalentFrameOrderLogic

local TFO = {}
ns.TalentFrameOrder = TFO

TFO.HOOK_DELAY = 0.5
TFO.REDRAW_DELAY = 0.1
TFO.RETRIES = 3
TFO.WIDTH = 300
TFO.BAR_WIDTH = 24
TFO.WATCH_DELAY = 0.5
-- Methods of the game's talent view that rebuild or refresh it; only those that exist are hooked.
TFO.METHODS = { "UpdateTreeInfo", "SetConfigID", "SetTalentTreeID", "CommitConfig", "RollbackConfig" }
-- Ways a talent view may tell which talent group it shows; none is confirmed for this client, the active
-- group of the character is the fallback.
TFO.GROUP_METHODS = { "GetActiveSpecGroup", "GetSelectedSpecGroup", "GetSpecGroup", "GetTalentGroup" }

local HEADER_H, PAD, ROW_BASE, ICON = 28, 8, 36, 22
local LIST_ROWS = 10
local SIDE_ROOM = 52 -- room right of the panel for the side tab of the add-on (Modules/BlizzardLinks.lua)
local BUTTON, GAP = 24, 4
local MARK_W, MARK_H = 22, 14
local BORDER = 3

ns.AddLocale("enUS", {
  ["talentframe.title"] = "Skill order",
  ["talentframe.titleBuild"] = "Skill order: %s",
  ["talentframe.tip"] = "The skill order of your active build for this talent group. Click to expand or collapse this section.",
  ["talentframe.progress"] = "%d of %d steps learned",
  ["talentframe.open"] = "Open in the add-on",
  ["talentframe.hideDone"] = "Hide learned steps",
  ["talentframe.hideDoneTip"] = "Hides the steps you have already learned, so the list starts with the next one.",
  ["talentframe.showDone"] = "Show learned steps",
  ["talentframe.showDoneTip"] = "Shows all steps of the build again.",
  ["talentframe.openTip"] = "Opens the active build in the talent editor.",
  ["talentframe.openNoneTip"] = "Opens the talents page of the add-on.",
  ["talentframe.state.done"] = "learned",
  ["talentframe.state.next"] = "next",
  ["talentframe.sub"] = "Level %d · %s",
  ["talentframe.row"] = "Step %d, level %d, %s, rank %d of %d, %s",
  ["talentframe.rowOpen"] = "open",
  ["talentframe.rowTip"] = "Level %d, rank %d/%d\nHover it or press Enter to mark the talent in the tree.",
  ["talentframe.steps"] = "Skill order, steps: %s",
  ["talentframe.set.heading"] = "Talent window",
  ["talentframe.set.hint"] = "Shows the skill order of your active build at the talent window of the game, for your own class and the talent group the window shows. The numbers and the side panel are drawn by the add-on, the talent window itself stays untouched.",
  ["talentframe.set.numbers"] = "Numbers in the talent tree",
  ["talentframe.set.numbersTip"] = "Shows the number of the next open step on every talent of the build, for example 10+ when more ranks follow. The tooltip of the talent lists all steps.",
  ["talentframe.set.panel"] = "Skill order at the talent window",
  ["talentframe.set.panelTip"] = "Shows a side panel with the steps of the active build next to the talent window. It starts collapsed, hovering a step marks the talent in the tree.",
})
ns.AddLocale("deDE", {
  ["talentframe.title"] = "Skillreihenfolge",
  ["talentframe.titleBuild"] = "Skillreihenfolge: %s",
  ["talentframe.tip"] = "Die Skillreihenfolge deiner aktiven Skillung für diese Talentgruppe. Klicken klappt den Bereich auf oder zu.",
  ["talentframe.progress"] = "%d von %d Schritten gelernt",
  ["talentframe.open"] = "Im Addon öffnen",
  ["talentframe.hideDone"] = "Gelernte Schritte ausblenden",
  ["talentframe.hideDoneTip"] = "Blendet die bereits gelernten Schritte aus, die Liste beginnt dann mit dem nächsten.",
  ["talentframe.showDone"] = "Gelernte Schritte einblenden",
  ["talentframe.showDoneTip"] = "Zeigt wieder alle Schritte der Skillung.",
  ["talentframe.openTip"] = "Öffnet die aktive Skillung im Talent-Editor.",
  ["talentframe.openNoneTip"] = "Öffnet die Talentseite des Addons.",
  ["talentframe.state.done"] = "gelernt",
  ["talentframe.state.next"] = "als Nächstes",
  ["talentframe.sub"] = "Stufe %d · %s",
  ["talentframe.row"] = "Schritt %d, Stufe %d, %s, Rang %d von %d, %s",
  ["talentframe.rowOpen"] = "offen",
  ["talentframe.rowTip"] = "Stufe %d, Rang %d/%d\nMit der Maus darüber oder mit Enter markierst du das Talent im Baum.",
  ["talentframe.steps"] = "Skillreihenfolge, Schritte: %s",
  ["talentframe.set.heading"] = "Talentfenster",
  ["talentframe.set.hint"] = "Zeigt die Skillreihenfolge deiner aktiven Skillung am Talentfenster des Spiels, für deine eigene Klasse und die Talentgruppe, die das Fenster zeigt. Die Zahlen und der Seitenbereich werden vom Addon gezeichnet, das Talentfenster selbst bleibt unberührt.",
  ["talentframe.set.numbers"] = "Zahlen im Talentbaum",
  ["talentframe.set.numbersTip"] = "Zeigt an jedem Talent der Skillung die Nummer des nächsten offenen Schritts, zum Beispiel 10+ wenn weitere Ränge folgen. Der Tooltip des Talents nennt alle Schritte.",
  ["talentframe.set.panel"] = "Reihenfolge am Talentfenster",
  ["talentframe.set.panelTip"] = "Zeigt neben dem Talentfenster einen Seitenbereich mit den Schritten der aktiven Skillung. Er startet zugeklappt, ein Schritt unter der Maus markiert das Talent im Baum.",
})

-- Settings and stored state --------------------------------------------------------------------------

local function setting(key, default)
  local value = ns.db and ns.db.settings and ns.db.settings[key]
  if value == nil then
    return default
  end
  return value == true
end

function TFO.NumbersOn()
  return setting("talentFrameNumbers", false)
end

function TFO.PanelOn()
  return setting("talentFramePanel", true)
end

local function uiFlag(key)
  local ui = ns.charDB and ns.charDB.talentOrderUi
  return type(ui) == "table" and ui[key] == true
end

function TFO.IsOpen()
  return uiFlag("frameOpen")
end

function TFO.HideDone()
  return uiFlag("frameHideDone")
end

-- Guarded reading of the game's frames -----------------------------------------------------------------

local function isSecret(value)
  local fn = rawget(_G, "issecretvalue")
  if type(fn) ~= "function" then
    return false
  end
  local ok, hidden = pcall(fn, value)
  return not ok or hidden == true
end

-- A plain value or nil: errors and secret values both become nil.
local function plain(ok, value)
  if ok and value ~= nil and not isSecret(value) then
    return value
  end
  return nil
end

local function ask(obj, method, ...)
  if type(obj) ~= "table" or type(obj[method]) ~= "function" then
    return nil
  end
  return plain(pcall(obj[method], obj, ...))
end

local function field(obj, name)
  if type(obj) ~= "table" then
    return nil
  end
  return plain(pcall(function()
    return obj[name]
  end))
end

local function isObject(value)
  return type(value) == "table" and type(value.GetObjectType) == "function"
end

local function frames()
  local window = rawget(_G, "PlayerSpellsFrame")
  local tf = field(window, "TalentsFrame")
  if isObject(tf) then
    return tf, window
  end
  return nil, window
end

local function shown(frame)
  return ask(frame, "IsShown") == true
end

local function visible(frame)
  local v = ask(frame, "IsVisible")
  if v == nil then
    v = ask(frame, "IsShown")
  end
  return v == true
end

local function nodeIdOf(button)
  local id = ask(button, "GetNodeID")
  if type(id) ~= "number" then
    id = field(ask(button, "GetNodeInfo") or field(button, "nodeInfo"), "ID")
  end
  if type(id) ~= "number" then
    id = field(button, "nodeID")
  end
  return type(id) == "number" and id or nil
end

-- The buttons of the talent view as { { button, node } }, nil when the view cannot list them.
local function buttonsOf(tf)
  if type(tf.EnumerateAllTalentButtons) ~= "function" then
    return nil
  end
  local out = {}
  local ok, a, b, c = pcall(tf.EnumerateAllTalentButtons, tf)
  if not ok then
    return nil
  end
  local function add(x, y)
    local obj = isObject(x) and x or y
    local node = isObject(obj) and nodeIdOf(obj)
    if node then
      out[#out + 1] = { button = obj, node = node }
    end
  end
  if type(a) == "function" then
    pcall(function()
      for x, y in a, b, c do
        add(x, y)
      end
    end)
  elseif type(a) == "table" then
    for x, y in pairs(a) do
      add(x, y)
    end
  end
  return out
end

-- The talent group the window shows: what the view tells, else the active group of the character.
function TFO.GroupShown(tf)
  for _, method in ipairs(TFO.GROUP_METHODS) do
    local value = ask(tf, method)
    if type(value) == "number" and value >= 1 and value <= TA.GROUPS and value == math.floor(value) then
      return value
    end
  end
  return TA.Group()
end

-- Our frame lies a few levels above the game's frame. The strata stays the one it inherits from the window.
local function lift(frame, anchor, boost)
  local level = ask(anchor, "GetFrameLevel")
  if type(level) == "number" then
    frame:SetFrameLevel(math.min(level + boost, ns.Layer.CAP))
  end
end

-- State -------------------------------------------------------------------------------------------------

local S = {
  hooked = setmetatable({}, { __mode = "k" }), -- talent views that carry our hooks
  tipped = setmetatable({}, { __mode = "k" }), -- buttons that carry our tooltip hook
  pool = {}, -- number marks
  buttons = {}, -- node -> button of the last draw
  numbers = {}, -- node -> { first, steps } of the last draw
  hoverNode = nil,
  pinNode = nil,
  reveal = true, -- the list shows the next step at the next draw (opened, window shown)
  snap = {}, -- button -> visible, of the last draw (the watcher compares the game's buttons with it)
  snapN = 0,
  pending = false, -- a redraw waits for the end of the combat
  waiting = false, -- the hooks are scheduled
  installPending = false,
  tries = 0,
}
TFO.state = S

local function hideNumbers(from)
  for i = from or 1, #S.pool do
    S.pool[i]:Hide()
  end
end

-- Our frame belongs to the window it was drawn for.
local function adopt(frame, window)
  if frame:GetParent() ~= window then
    frame:SetParent(window)
  end
end

local function mark(i, window)
  local m = S.pool[i]
  if m then
    adopt(m, window)
    return m
  end
  m = CreateFrame("Frame", nil, window)
  ns.Layer.Own(m)
  m:SetSize(MARK_W, MARK_H)
  m:EnableMouse(false)
  m.bg = m:CreateTexture(nil, "BACKGROUND")
  m.bg:SetAllPoints()
  m.bg:SetColorTexture(0, 0, 0, 0.8)
  m.text = W.Text(m, { role = "small", color = "accent2", justify = "CENTER" })
  m.text:SetPoint("CENTER")
  m:Hide()
  S.pool[i] = m
  return m
end

-- Border around the talent that a hovered, focused or marked step names.
local function border(window)
  if not S.border then
    local f = CreateFrame("Frame", nil, window)
    ns.Layer.Own(f)
    f:EnableMouse(false)
    f.edges = W.Border(f, "actionHi", 1, BORDER)
    f:Hide()
    S.border = f
  end
  return S.border
end

function TFO.RefreshBorder()
  local node = S.hoverNode or S.pinNode
  local button = node and S.buttons[node]
  local window = select(2, frames())
  if not (button and visible(button) and shown(window)) then
    if S.border then
      S.border:Hide()
    end
    return
  end
  local f = border(window)
  adopt(f, window)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", button, "TOPLEFT", -BORDER, BORDER)
  f:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", BORDER, -BORDER)
  lift(f, button, 8)
  f:Show()
end

local function setHover(node)
  S.hoverNode = node
  TFO.RefreshBorder()
end

-- Side panel --------------------------------------------------------------------------------------------

local function nameOf(row)
  return row.talent and ns.T(row.talent.n) or ("#" .. tostring(row.sid))
end

local function stateWord(row)
  if row.done then
    return L["talentframe.state.done"]
  end
  return row.next and L["talentframe.state.next"] or L["talentframe.rowOpen"]
end

local function paintRow(row)
  local item = row.item
  local lit = item ~= nil and item.node ~= nil and item.node == (S.hoverNode or S.pinNode)
  row.bg:SetColorTexture(1, 1, 1, lit and 0.14 or (row.hover and 0.06 or 0))
  row.mark:SetColorTexture(Theme.color("accent"))
  row.mark:SetShown(item ~= nil and item.next == true)
  row.line:SetColorTexture(1, 1, 1, Theme.lineAlpha())
end

local function pin(node)
  S.pinNode = S.pinNode ~= node and node or nil
  TFO.RefreshBorder()
  if S.panel then
    S.panel.list.Refresh()
  end
end

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.mark = row:CreateTexture(nil, "ARTWORK")
  row.mark:SetPoint("TOPLEFT")
  row.mark:SetPoint("BOTTOMLEFT")
  row.mark:SetWidth(3)
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetPoint("BOTTOMLEFT")
  row.line:SetPoint("BOTTOMRIGHT")
  row.line:SetHeight(1)
  row.num = W.Text(row, { role = "ui", color = "accent2", justify = "RIGHT" })
  row.num:SetPoint("LEFT", 6, 0)
  row.num:SetWidth(26)
  row.spell = row:CreateTexture(nil, "ARTWORK")
  row.spell:SetSize(ICON, ICON)
  row.spell:SetPoint("LEFT", 38, 0)
  row.spell:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.check = W.Glyph(row, "check", 14, "success")
  row.check:SetPoint("RIGHT", -8, 0)
  row.title = W.Text(row, { role = "ui" })
  row.title:SetPoint("TOPLEFT", row.spell, "TOPRIGHT", 8, 3)
  row.title:SetPoint("RIGHT", row.check, "LEFT", -6, 0)
  row.sub = W.Text(row, { role = "small", color = "textSecondary" })
  row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
  row.sub:SetPoint("RIGHT", row.check, "LEFT", -6, 0)
  ns.Bind(row, function()
    paintRow(row)
  end)
  row.fgName = function()
    local item = row.item
    return item
        and item.talent
        and string.format(
          L["talentframe.row"],
          item.index,
          item.level,
          nameOf(item),
          item.rank,
          item.talent.mr,
          stateWord(item)
        )
      or nil
  end
  local function tip()
    local item = row.item
    if item and item.talent then
      ns.ShowTooltip(
        row,
        string.format("%d · %s", item.index, nameOf(item)),
        string.format(L["talentframe.rowTip"], item.level, item.rank, item.talent.mr)
      )
    end
  end
  row:SetScript("OnEnter", function()
    row.hover = true
    paintRow(row)
    tip()
    setHover(row.item and row.item.node)
    TFO.Keys(true)
  end)
  row:SetScript("OnLeave", function()
    row.hover = false
    paintRow(row)
    ns.HideTooltip()
    setHover(nil)
    TFO.Keys(false)
  end)
  row:SetScript(
    "OnClick",
    ns.Wrap("talentframe-pin", function()
      if row.item and row.item.node then
        pin(row.item.node)
      end
    end)
  )
  row.fgOnFocus = function()
    tip()
    setHover(row.item and row.item.node)
  end
  row.fgOnBlur = function()
    ns.HideTooltip()
    setHover(nil)
  end
  ns.Focus.register(row, function()
    if row.item and row.item.node then
      pin(row.item.node)
    end
  end)
  return row
end

local function bindRow(row, item)
  row.item = item
  local icon = item.talent and item.talent.i and ("Interface\\Icons\\" .. item.talent.i)
  if icon then
    row.spell:SetTexture(icon)
  else
    row.spell:SetColorTexture(Theme.color("surface3"))
  end
  row.spell:SetAlpha(item.done and 0.5 or 1)
  row.num:SetText(tostring(item.index))
  row.title:SetText(string.format("%s %d/%d", nameOf(item), item.rank, item.talent and item.talent.mr or item.rank))
  W.SetColor(row.title, item.done and "textSecondary" or "text")
  if item.done or item.next then
    row.sub:SetText(string.format(L["talentframe.sub"], item.level, stateWord(item)))
  else
    row.sub:SetText(string.format(L["talents.order.level"], item.level))
  end
  W.SetColor(row.sub, item.next and "accent" or "textSecondary")
  row.check:SetShown(item.done == true)
  paintRow(row)
end

-- The focusable parts of the panel in tab order: header, controls, rows that show.
local function focusables(p)
  local out = { p.header }
  if p.body:IsShown() then
    for _, control in ipairs({ p.numbers, p.hideDone, p.open }) do
      if control:IsVisible() then
        out[#out + 1] = control
      end
    end
  end
  if p.list:IsVisible() then
    for _, row in ipairs(p.rows) do
      if row:IsShown() and row.item then
        out[#out + 1] = row
      end
    end
  end
  return out
end

local function indexIn(list, frame)
  for i, f in ipairs(list) do
    if f == frame then
      return i
    end
  end
end

-- Moves the keyboard focus inside the panel; past the last or first visible row the list scrolls one step.
local function moveFocus(p, step)
  local items = focusables(p)
  local at = indexIn(items, ns.Focus.current)
  if not at then
    ns.Focus.set(items[step > 0 and 1 or #items])
    return
  end
  local current = items[at]
  local target = at + step
  local place = current.item and p.pos[current.item.index]
  if place and step > 0 and target > #items and place < #p.data then
    p.list:ScrollBy(1)
    ns.Focus.set(focusables(p)[#items])
  elseif place and step < 0 and place > 1 and items[target] and not items[target].item then
    p.list:ScrollBy(-1)
    ns.Focus.set(focusables(p)[target + 1])
  elseif items[target] then
    ns.Focus.set(items[target])
  end
end

local function handleKey(p, key)
  local items = focusables(p)
  local inside = indexIn(items, ns.Focus.current) ~= nil
  if not (inside or p:IsMouseOver()) then
    return false
  end
  if key == "TAB" then
    local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown()
    moveFocus(p, shift and -1 or 1)
    return true
  elseif key == "DOWN" or key == "UP" then
    moveFocus(p, key == "DOWN" and 1 or -1)
    return true
  elseif (key == "ENTER" or key == "SPACE") and inside and ns.Focus.recent() then
    return ns.Focus.activate()
  end
  return false
end

local function openAddon()
  local view = S.view
  if view then
    TA.Open(view.group)
  elseif ns.Main then
    ns.Main.Show("talents")
  end
end

-- Height of the list: what the window's height leaves under the controls, in whole rows.
local function listHeight(window, used)
  local rowH = K.scaledHeight(ROW_BASE)
  local height = ask(window, "GetHeight")
  local rows = LIST_ROWS
  if type(height) == "number" and height > 0 then
    rows = math.floor((height - used - PAD) / rowH)
  end
  return math.max(1, rows) * rowH
end

local function chevronOf(p)
  local toRight = TFO.IsOpen() == (p.mirrored == true)
  return toRight and "chevron-right" or "chevron-left"
end

-- Lays the panel out for its state: a slim bar (collapsed), or header, controls and the list (expanded).
-- The height of the panel itself follows its two anchors (the window's edge, top to bottom).
local function layoutPanel(p, window)
  local open = TFO.IsOpen()
  p:SetWidth(open and TFO.WIDTH or TFO.BAR_WIDTH)
  p.header:ClearAllPoints()
  p.header:SetPoint("TOPLEFT")
  p.header:SetPoint("TOPRIGHT")
  p.chevron:ClearAllPoints()
  p.chevron:SetIcon(chevronOf(p))
  p.label:SetShown(open)
  p.vlabel:SetShown(not open)
  -- Set on every layout so a language switch reaches the bar.
  p.vlabel:SetText(F.Vertical(L["talentframe.title"]))
  p.state:SetShown(open)
  p.body:SetShown(open)
  if not open then
    p.header:SetPoint("BOTTOMLEFT")
    p.header:SetPoint("BOTTOMRIGHT")
    p.chevron:SetPoint("TOP", 0, -8)
    return
  end
  local headerH = K.scaledHeight(HEADER_H)
  p.header:SetHeight(headerH)
  p.chevron:SetPoint("LEFT", 8, 0)
  p.state:SetText(L["talents.order.open"])
  local inner = TFO.WIDTH - PAD * 2
  local hasBuild = S.view ~= nil
  p.note:SetWidth(inner)
  p.note:ClearAllPoints()
  p.note:SetPoint("TOPLEFT", p.body, "TOPLEFT", PAD, -PAD)
  local noteH = math.max(14, math.ceil(p.note:GetStringHeight()))
  local controlsY = -(PAD + noteH + PAD)
  p.open:ClearAllPoints()
  p.open:SetPoint("TOPRIGHT", p.body, "TOPRIGHT", -PAD, controlsY)
  p.hideDone:SetShown(hasBuild)
  p.hideDone:ClearAllPoints()
  p.hideDone:SetPoint("RIGHT", p.open, "LEFT", -GAP, 0)
  local buttons = hasBuild and 2 or 1
  p.numbers:ClearAllPoints()
  p.numbers:SetPoint("TOPLEFT", p.body, "TOPLEFT", PAD, controlsY)
  p.numbers:SetWidth(inner - (BUTTON + GAP) * buttons)
  p.list:SetShown(hasBuild)
  if hasBuild then
    local top = PAD + noteH + PAD + BUTTON + PAD
    p.list:ClearAllPoints()
    p.list:SetPoint("TOPLEFT", p.body, "TOPLEFT", PAD, -top)
    p.list:SetSize(inner, listHeight(window, top + headerH))
    p.list.Refresh()
  end
end

-- The icon button that hides or shows the learned steps: icon and selected look follow the state.
local function paintHideDone(p)
  local hidden = TFO.HideDone()
  p.hideDone:SetIcon(hidden and "eye-off" or "eye")
  p.hideDone:SetSelected(hidden)
end

function TFO.Toggle(open)
  if open == nil then
    open = not TFO.IsOpen()
  end
  Store.setChar("talentOrderUi.frameOpen", open and true or false)
  if open then
    S.reveal = true
  end
  if S.panel then
    -- Our own frame only: the bar changes its width at once, even in combat; the rest waits for it.
    layoutPanel(S.panel, S.window)
    if ns.InCombat() then
      S.pending = true
    else
      TFO.Draw()
    end
  end
end

local function toggleHideDone()
  Store.setChar("talentOrderUi.frameHideDone", not TFO.HideDone())
  S.reveal = true
  TFO.Queue()
end

local function buildPanel(window)
  local p = CreateFrame("Frame", nil, window)
  ns.Layer.Own(p)
  p:EnableMouse(true)
  W.Fill(p, "surface", 1)
  W.Border(p, "white")
  p.data = {}
  p.pos = {}
  p.rows = {}

  local header = CreateFrame("Button", nil, p)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  W.Fill(header, "surface2")
  p.header = header
  p.chevron = W.Glyph(header, "chevron-right", 12, "textSecondary")
  p.chevron:SetPoint("LEFT", 8, 0)
  p.state = W.Text(header, { role = "small", color = "textSecondary" })
  p.state:SetPoint("RIGHT", -8, 0)
  p.label = W.Text(header, { key = "talentframe.title", role = "ui", color = "text" })
  p.label:SetPoint("LEFT", p.chevron, "RIGHT", 6, 0)
  p.label:SetPoint("RIGHT", p.state, "LEFT", -6, 0)
  -- Title of the collapsed bar, stacked below the chevron.
  p.vlabel = W.Text(header, { role = "small", color = "textSecondary", justify = "CENTER" })
  p.vlabel:SetPoint("TOP", p.chevron, "BOTTOM", 0, -8)
  header.fgName = function()
    return p.label:GetText() or L["talentframe.title"]
  end
  header:SetScript("OnClick", function()
    TFO.Toggle()
  end)
  header:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, p.label:GetText(), L["talentframe.tip"])
    TFO.Keys(true)
  end)
  header:HookScript("OnLeave", function()
    ns.HideTooltip()
    TFO.Keys(false)
  end)
  ns.Focus.register(header, function()
    TFO.Toggle()
  end)
  function header:fgArrow(step)
    if (step > 0) ~= TFO.IsOpen() then
      TFO.Toggle(step > 0)
    end
  end

  p.body = CreateFrame("Frame", nil, p)
  p.body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
  p.body:SetPoint("BOTTOMRIGHT")
  p.note = W.Text(p.body, { role = "small", color = "textSecondary", wrap = true })
  p.numbers = W.Toggle(p.body, {
    key = "talentframe.set.numbers",
    get = TFO.NumbersOn,
    set = function(v)
      Store.set("settings.talentFrameNumbers", v == true)
    end,
    tooltip = "talentframe.set.numbers",
    tooltipText = "talentframe.set.numbersTip",
  })
  p.numbers:HookScript("OnEnter", function()
    TFO.Keys(true)
  end)
  p.numbers:HookScript("OnLeave", function()
    TFO.Keys(false)
  end)
  p.hideDone = W.Action(p.body, {
    icon = "eye",
    size = BUTTON,
    tooltip = "talentframe.hideDone",
    onClick = toggleHideDone,
  })
  p.hideDone.fgName = function()
    return L[TFO.HideDone() and "talentframe.showDone" or "talentframe.hideDone"]
  end
  p.hideDone:HookScript("OnEnter", function(self)
    local hidden = TFO.HideDone()
    ns.ShowTooltip(
      self,
      L[hidden and "talentframe.showDone" or "talentframe.hideDone"],
      L[hidden and "talentframe.showDoneTip" or "talentframe.hideDoneTip"]
    )
    TFO.Keys(true)
  end)
  p.hideDone:HookScript("OnLeave", function()
    ns.HideTooltip()
    TFO.Keys(false)
  end)
  p.open = W.Action(p.body, {
    icon = "open",
    size = BUTTON,
    tooltip = "talentframe.open",
    opens = true,
    onClick = openAddon,
  })
  p.open:HookScript("OnEnter", function(self)
    ns.ShowTooltip(
      self,
      L["talentframe.open"],
      L[S.view and "talentframe.openTip" or "talentframe.openNoneTip"],
      { hint = L["action.opensWindow"] }
    )
    TFO.Keys(true)
  end)
  p.open:HookScript("OnLeave", function()
    ns.HideTooltip()
    TFO.Keys(false)
  end)
  p.list = W.ScrollList(p.body, {
    rowHeight = K.scaledHeight(ROW_BASE),
    createRow = function(parent)
      local row = createRow(parent)
      p.rows[#p.rows + 1] = row
      return row
    end,
    bindRow = bindRow,
  })

  p:SetScript("OnKeyDown", function(self, key)
    local handled = handleKey(self, key)
    ns.PropagateKeys(self, not handled)
  end)
  p:SetScript("OnEnter", function()
    TFO.Keys(true)
  end)
  p:SetScript("OnLeave", function()
    TFO.Keys(false)
  end)
  p:HookScript("OnHide", function()
    p:EnableKeyboard(false)
  end)
  p:Hide()
  S.panel = p
  return p
end

-- Keys go to the panel only while the pointer is over it and never in combat: a frame that takes the
-- keyboard would swallow the movement keys when the client refuses to pass them on.
function TFO.Keys(on)
  local p = S.panel
  if not p then
    return
  end
  if on and not ns.InCombat() then
    p:EnableKeyboard(true)
  elseif not on and not p:IsMouseOver() then
    p:EnableKeyboard(false)
  end
end

-- Directly at the edge of the window over its whole height: right, or mirrored to the left when the screen
-- has no room for the panel and the side tab of the add-on.
local function placePanel(p, window)
  p:ClearAllPoints()
  local width = TFO.IsOpen() and TFO.WIDTH or TFO.BAR_WIDTH
  local right, limit = ask(window, "GetRight"), ask(UIParent, "GetRight")
  p.mirrored = type(right) == "number" and type(limit) == "number" and right + width + SIDE_ROOM > limit
  if p.mirrored then
    p:SetPoint("TOPRIGHT", window, "TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", window, "BOTTOMLEFT", 0, 0)
  else
    p:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, 0)
    p:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", 0, 0)
  end
  ns.Layer.SetTreeLevel(p, math.min((ask(window, "GetFrameLevel") or 0) + 20, ns.Layer.CAP))
end

local function drawPanel(window)
  local p = S.panel or buildPanel(window)
  adopt(p, window)
  local view = S.view
  p.data, p.pos = F.Visible(view and view.rows or {}, TFO.HideDone())
  if view then
    p.label:SetText(string.format(L["talentframe.titleBuild"], view.entry.name))
    p.note:SetText(string.format(L["talentframe.progress"], F.Progress(view.rows)))
  else
    p.label:SetText(L["talentframe.title"])
    p.note:SetText(string.format(L["talents.active.lineNone"], TA.GroupName(S.group)))
  end
  W.SetColor(p.note, "textSecondary")
  placePanel(p, window)
  layoutPanel(p, window)
  paintHideDone(p)
  p.numbers.Refresh()
  p.list:SetData(p.data)
  -- The next step shows whenever the panel opens or the window shows, and when it moved; a list the player
  -- scrolled stays where it is during a plain redraw.
  local nextIndex = view and view.next
  if TFO.IsOpen() and (S.reveal or (nextIndex and nextIndex ~= S.lastNext)) then
    local at = nextIndex and p.pos[nextIndex]
    if at then
      p.list:Reveal(at)
    end
    S.reveal = false
  end
  S.lastNext = nextIndex
  p:Show()
end

-- The frame the side tab of the add-on hangs on: the panel at the right edge of the window, nil when there
-- is none or it sits on the left (Modules/BlizzardLinks.lua then keeps the tab at the window).
function TFO.EdgeFrame()
  local p = S.panel
  if p and p:IsShown() and not p.mirrored then
    return p
  end
end

local function syncEdge()
  local active = TFO.EdgeFrame() ~= nil
  local links = ns.BlizzardLinks
  if active ~= S.edgeActive and links and links.Discover then
    S.edgeActive = active
    pcall(links.Discover, "talent order")
  end
end

-- Redraw ------------------------------------------------------------------------------------------------

local function hideAll()
  S.reveal = true
  hideNumbers()
  if S.border then
    S.border:Hide()
  end
  if S.panel then
    S.panel:Hide()
  end
  if S.watcher then
    S.watcher:Hide()
  end
  syncEdge()
end

-- The active build of the shown group with its rows, nil without one for the own class.
local function readView(tf)
  local group = TFO.GroupShown(tf)
  local entry, order = TA.Get(nil, group)
  S.group = group
  if not entry or entry.class ~= K.PlayerClass() then
    return nil
  end
  local specs = TL.Specs(entry.class)
  if not specs then
    return nil
  end
  local rows, nextIndex = F.Rows(specs, order, (TalentApply.readNodeRanks()))
  for _, row in ipairs(rows) do
    row.node = row.talent and row.talent.node
  end
  return { entry = entry, group = group, rows = rows, next = nextIndex, numbers = F.Numbers(rows) }
end

local function hookButton(button)
  if S.tipped[button] or type(button.HookScript) ~= "function" then
    return
  end
  S.tipped[button] = true
  pcall(button.HookScript, button, "OnEnter", function(self)
    local entry = TFO.NumbersOn() and not ns.InCombat() and S.numbers[nodeIdOf(self)]
    local tip = rawget(_G, "GameTooltip")
    if not (entry and type(tip) == "table") then
      return
    end
    pcall(function()
      if tip:GetOwner() == self then
        local r, g, b = Theme.color("accent2")
        tip:AddLine(string.format(L["talentframe.steps"], F.StepsText(entry)), r, g, b)
        tip:Show()
      end
    end)
  end)
end

-- The next open step on every talent of the build; a learned talent shows nothing.
local function drawNumbers(list, window)
  local n = 0
  if TFO.NumbersOn() then
    for _, item in ipairs(list) do
      local entry = S.numbers[item.node]
      local text = entry and F.MarkText(entry)
      if text and visible(item.button) then
        n = n + 1
        local m = mark(n, window)
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", item.button, "TOPLEFT", -BORDER, BORDER)
        lift(m, item.button, 6)
        m.fgButton = item.button
        m.text:SetText(text)
        local width = ask(m.text, "GetStringWidth")
        m:SetWidth(math.max(MARK_W, math.ceil(type(width) == "number" and width or 0) + 8))
        m:Show()
      end
    end
  end
  hideNumbers(n + 1)
end

-- Which buttons the game has and which of them show, for the watcher.
local function snapshot(list)
  local map = {}
  for _, item in ipairs(list) do
    map[item.button] = visible(item.button)
  end
  return map, #list
end

local function sameSnapshot(a, an, b, bn)
  if an ~= bn then
    return false
  end
  for button, shows in pairs(a) do
    if b[button] ~= shows then
      return false
    end
  end
  return true
end

-- The game replaces its talent buttons without telling us through a hooked method: a light check of our own
-- frame, while the window shows, queues a redraw when the buttons are not the ones we drew on.
local function watch(_, elapsed)
  S.idle = (S.idle or 0) + elapsed
  if S.idle < TFO.WATCH_DELAY then
    return
  end
  S.idle = 0
  if ns.InCombat() or S.pending then
    return
  end
  local tf, window = frames()
  if not (tf and shown(tf) and shown(window)) then
    return
  end
  local list = buttonsOf(tf)
  if not list then
    return
  end
  local map, count = snapshot(list)
  if not sameSnapshot(map, count, S.snap, S.snapN) then
    S.drift = (S.drift or 0) + 1
    TFO.Queue()
  end
end

local function keepWatching()
  if not S.watcher then
    S.watcher = CreateFrame("Frame")
    S.watcher:SetScript("OnUpdate", watch)
  end
  S.watcher:Show()
end

function TFO.Draw()
  local tf, window = frames()
  if not tf or not shown(tf) or not shown(window) then
    hideAll()
    return
  end
  if ns.InCombat() then
    S.pending = true
    return
  end
  S.pending = false
  S.window = window
  local wantNumbers, wantPanel = TFO.NumbersOn(), TFO.PanelOn()
  if not (wantNumbers or wantPanel) then
    hideAll()
    return
  end
  S.view = readView(tf)
  S.numbers = S.view and S.view.numbers or {}
  local list = buttonsOf(tf) or {}
  S.buttons = {}
  for _, item in ipairs(list) do
    S.buttons[item.node] = item.button
    if wantNumbers then
      hookButton(item.button)
    end
  end
  S.snap, S.snapN = snapshot(list)
  S.draws = (S.draws or 0) + 1
  drawNumbers(list, window)
  if wantPanel then
    drawPanel(window)
  elseif S.panel then
    S.panel:Hide()
  end
  TFO.RefreshBorder()
  keepWatching()
  syncEdge()
end

-- Hooks only queue the redraw, so the game's own call returns first.
function TFO.Queue()
  ns.Debounce("talentframe-order", TFO.REDRAW_DELAY, TFO.Draw)
end

-- Hooks -------------------------------------------------------------------------------------------------

local function loaded(name)
  local api = rawget(_G, "C_AddOns")
  local fn = type(api) == "table" and api.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
  return type(fn) == "function" and plain(pcall(fn, name)) == true
end

function TFO.Install()
  local tf, window = frames()
  if not tf then
    if S.tries < TFO.RETRIES and C_Timer and C_Timer.After then
      S.tries = S.tries + 1
      C_Timer.After(TFO.HOOK_DELAY, TFO.Install)
    end
    return false
  end
  if S.hooked[tf] then
    return true
  end
  if ns.InCombat() then
    S.installPending = true
    return false
  end
  S.hooked[tf] = true
  local function script(target, event, fn)
    if isObject(target) and type(target.HookScript) == "function" then
      pcall(target.HookScript, target, event, fn)
    end
  end
  local function onHide()
    S.hoverNode = nil
    hideAll()
  end
  local function onShow()
    S.reveal = true
    TFO.Queue()
  end
  script(window, "OnShow", onShow)
  script(window, "OnHide", onHide)
  script(tf, "OnShow", onShow)
  script(tf, "OnHide", onHide)
  local secure = rawget(_G, "hooksecurefunc")
  if type(secure) == "function" then
    for _, method in ipairs(TFO.METHODS) do
      if type(tf[method]) == "function" then
        pcall(secure, tf, method, TFO.Queue)
      end
    end
  end
  if shown(tf) then
    TFO.Queue()
  end
  return true
end

local function scheduleInstall()
  if S.waiting then
    return
  end
  S.waiting = true
  S.tries = 0
  local function run()
    S.waiting = false
    TFO.Install()
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(TFO.HOOK_DELAY, run)
  else
    run()
  end
end

-- Diagnostics: the state of the numbers, for the Dev probe: the setting, the entries, how many buttons the
-- window lists and how many of them have an entry, the marks shown and the strata and level of a button
-- against its mark (a mark must lie above its button).
function TFO.NumbersStatus()
  local entries, matched, marks = 0, 0, 0
  for _ in pairs(S.numbers) do
    entries = entries + 1
  end
  local buttons = 0
  for node in pairs(S.buttons) do
    buttons = buttons + 1
    if S.numbers[node] then
      matched = matched + 1
    end
  end
  local sample
  for _, m in ipairs(S.pool) do
    if m:IsShown() then
      marks = marks + 1
      sample = sample or m
    end
  end
  local function layerOf(frame)
    return tostring(ask(frame, "GetFrameStrata")) .. "/" .. tostring(ask(frame, "GetFrameLevel"))
  end
  local window = select(2, frames())
  return string.format(
    "setting=%s entries=%d buttons=%d matched=%d marks=%d draws=%d drift=%d button=%s mark=%s window=%s markParent=%s",
    tostring(TFO.NumbersOn()),
    entries,
    buttons,
    matched,
    marks,
    S.draws or 0,
    S.drift or 0,
    sample and layerOf(sample.fgButton) or "-",
    sample and layerOf(sample) or "-",
    layerOf(window),
    sample and tostring(sample:GetParent() == window) or "-"
  )
end

-- Diagnostics: what the client answers for the talent group, for the Dev probe.
function TFO.GroupSources()
  local tf = frames()
  local parts = {}
  for _, method in ipairs(TFO.GROUP_METHODS) do
    parts[#parts + 1] = "frame:" .. method .. "=" .. tostring(ask(tf, method))
  end
  parts[#parts + 1] = "TalentActive.Group=" .. tostring(TA.Group())
  return table.concat(parts, " ")
end

ns.On("ADDON_LOADED", function(_, name)
  if name == "Blizzard_PlayerSpells" then
    scheduleInstall()
  end
end)

ns.On("PLAYER_LOGIN", function()
  if loaded("Blizzard_PlayerSpells") then
    scheduleInstall()
  end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  if S.installPending then
    S.installPending = false
    TFO.Install()
  end
  if S.pending then
    TFO.Queue()
  end
end)

ns.On("PLAYER_REGEN_DISABLED", function()
  if S.panel then
    S.panel:EnableKeyboard(false)
  end
end)

-- Points bought or refunded, the group switched, another build made active, a setting changed.
for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED", TA.EVENT }) do
  ns.On(event, TFO.Queue)
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.talentFrameNumbers" or path == "settings.talentFramePanel" then
    TFO.Queue()
  end
end)
