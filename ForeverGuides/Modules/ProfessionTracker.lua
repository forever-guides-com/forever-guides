-- Compact shopping list panel next to the quest tracker: the open lines of the chosen profession
-- route (item and quantity still needed, stock already taken off), ticked lines dimmed at the end,
-- a click on a row searches the item in the auction house (ProfessionShop.lua, RowClick). The panel
-- is a frame of its own under UIParent, anchored below ObjectiveTrackerFrame so it follows the
-- tracker, at the right screen edge while the tracker is missing or hidden. The tracker itself is
-- never touched (no module in its protected containers, only reads and two HookScript calls).
--
-- Off by default (settings.profTracker). Visible only with the setting on, a chosen route and at
-- least one open line. Look and zoom come from Modules/WindowStyle.lua (kind "proftracker"). The
-- position is an offset from the anchor in UIParent units, one per anchor kind, in
-- ns.db.frames.profTracker = { track = { x, y }, screen = { x, y }, collapsed, scale, style }.
-- The position changes only out of combat; PLAYER_REGEN_ENABLED places it afterwards.
local _, ns = ...
local W, L, Theme, U, WS = ns.W, ns.L, ns.Theme, ns.U, ns.WindowStyle
local S, SW = ns.ProfessionShop, ns.ProfessionShopWindow

local T = {}
ns.ProfessionTracker = T

WS.PREFIX.proftracker = "profTrackerWindow"

ns.AddLocale("enUS", {
  ["proftracker.heading"] = "Shopping list",
  ["proftracker.setting"] = "Shopping list in tracker",
  ["proftracker.hint"] = "Panel below the quest tracker, drag the title.",
  ["proftracker.collapse"] = "Collapse or expand",
  ["proftracker.send"] = "To shopping list",
  ["proftracker.window"] = "Window",
  ["proftracker.more"] = "+%d more",
})
ns.AddLocale("deDE", {
  ["proftracker.heading"] = "Einkaufsliste",
  ["proftracker.setting"] = "Einkaufsliste im Tracker",
  ["proftracker.hint"] = "Feld unter dem Quest-Tracker, am Titel ziehen.",
  ["proftracker.collapse"] = "Ein- oder ausklappen",
  ["proftracker.send"] = "An Einkaufsliste",
  ["proftracker.window"] = "Fenster",
  ["proftracker.more"] = "+%d weitere",
})

local WIDTH, HEAD_H = 250, 22
local PAD, ROW_H, BOX, BUTTON_H = 8, 20, 12, 24
local MAX_ROWS = 12
local TRACKER_GAP = 8 -- below the tracker
local SCREEN_X, SCREEN_Y = -12, -320 -- from the top right corner while there is no tracker
local OFFSET_LIMIT = 5000
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.6, 2, 0.1
local ANCHOR_DELAY = 0.05
local REFRESH_DELAY = 0.5

local frame

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function frameDb()
  local frames = ns.db.frames
  if type(frames.profTracker) ~= "table" then
    frames.profTracker = {}
  end
  return frames.profTracker
end

-- Setting -----------------------------------------------------------------------------------------

function T.Enabled()
  return type(ns.db) == "table" and type(ns.db.settings) == "table" and ns.db.settings.profTracker == true
end

function T.SetEnabled(on)
  ns.Store.set("settings.profTracker", on == true)
end

-- The switch of the route page and of the settings.
function T.NewToggle(parent)
  local toggle = W.Toggle(parent, { key = "proftracker.setting", get = T.Enabled, set = T.SetEnabled })
  toggle.fgId = "proftracker-enabled"
  return toggle
end

function T.AddSettings(view)
  ns.AddHeading(view, "proftracker.heading")
  view.stack:Add(T.NewToggle(view.content), { height = 24, gap = 6 })
  ns.AddParagraph(view, "proftracker.hint", { role = "micro", color = "textMuted" })
end

-- Position ----------------------------------------------------------------------------------------

local function trackerFrame()
  local tracker = rawget(_G, "ObjectiveTrackerFrame")
  if type(tracker) == "table" and type(tracker.IsShown) == "function" and type(tracker.GetBottom) == "function" then
    local ok, shown = pcall(tracker.IsShown, tracker)
    if ok and shown then
      return tracker
    end
  end
end

-- Where the panel hangs: its top right corner at `point` of `rel`, moved by x and y.
local function anchor()
  local tracker = trackerFrame()
  if tracker then
    return { mode = "track", rel = tracker, point = "BOTTOMRIGHT", x = 0, y = -TRACKER_GAP }
  end
  return { mode = "screen", rel = UIParent, point = "TOPRIGHT", x = SCREEN_X, y = SCREEN_Y }
end

local function offsetOf(mode)
  local saved = frameDb()[mode]
  saved = type(saved) == "table" and saved or {}
  return finite(saved.x) and U.clamp(saved.x, -OFFSET_LIMIT, OFFSET_LIMIT) or 0,
    finite(saved.y) and U.clamp(saved.y, -OFFSET_LIMIT, OFFSET_LIMIT) or 0
end

local function scaleOf()
  local scale = frameDb().scale
  return finite(scale) and U.clamp(scale, SCALE_MIN, SCALE_MAX) or 1
end

local function place(f)
  local a = anchor()
  local ox, oy = offsetOf(a.mode)
  local s = f:GetScale()
  f:ClearAllPoints()
  f:SetPoint("TOPRIGHT", a.rel, a.point, (a.x + ox) / s, (a.y + oy) / s)
  f.mode, f.rel, f.placed, f.replace = a.mode, a.rel, true, nil
end

-- A value in the units of `frame` as UIParent units.
local function units(target, v)
  return v * target:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- Keeps where the panel stands now as the offset from its anchor.
local function saveOffset(f)
  local a = anchor()
  local right, top = f:GetRight(), f:GetTop()
  local ax = a.rel:GetRight()
  local ay = a.point == "BOTTOMRIGHT" and a.rel:GetBottom() or a.rel:GetTop()
  if not (right and top and ax and ay) then
    return
  end
  frameDb()[a.mode] = {
    x = U.clamp(units(f, right) - units(a.rel, ax) - a.x, -OFFSET_LIMIT, OFFSET_LIMIT),
    y = U.clamp(units(f, top) - units(a.rel, ay) - a.y, -OFFSET_LIMIT, OFFSET_LIMIT),
  }
end

-- Zoom: mouse wheel with the windowScale key (default Ctrl) on the title bar, the top right corner stays where it is.
local function changeScale(f, delta)
  if inCombat() then
    return
  end
  local db = frameDb()
  db.scale = U.clamp(math.floor(scaleOf() * 100 + delta * SCALE_STEP * 100 + 0.5) / 100, SCALE_MIN, SCALE_MAX)
  f:SetScale(db.scale)
  place(f)
end

-- Look -------------------------------------------------------------------------------------------

function T.Style()
  return WS.Resolve("proftracker", frameDb().style)
end

local function applyLook(f)
  local style = T.Style()
  WS.Apply(f, style, f.styleParts)
  WS.ApplyShadow(f.title, WS.TextShadow(style), Theme.rgb("accent2"))
end

local function patchStyle(patch)
  local style = U.copy(frameDb().style or {})
  if patch.bg ~= nil then
    style.bg = patch.bg or nil
  end
  if patch.alpha ~= nil then
    style.alpha = patch.alpha
  end
  if patch.autoHide ~= nil then
    style.autoHide = patch.autoHide
  end
  frameDb().style = style
  if frame then
    applyLook(frame)
  end
end

function T.OpenLook()
  if not frame then
    return nil
  end
  return WS.OpenPanel(frame.look, {
    frame = frame,
    kind = "proftracker",
    get = T.Style,
    set = patchStyle,
    onSaveDefault = function()
      WS.SaveDefault("proftracker", T.Style())
    end,
    onReset = function()
      frameDb().style = {}
      applyLook(frame)
    end,
  })
end

-- Rows -------------------------------------------------------------------------------------------

local function newRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_H)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.hover = row:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(1, 1, 1, 0)
  row.box = CreateFrame("Button", nil, row)
  row.box:SetSize(BOX, BOX)
  row.box:SetPoint("LEFT", PAD, 0)
  row.box:SetHitRectInsets(-4, -4, -4, -4)
  W.Fill(row.box, "surface2")
  row.boxOn = W.Fill(row.box, "action", 1)
  row.boxBorder = W.Border(row.box, "white", 0.4)
  row.mark = W.CheckMark(row.box, 10, "text")
  row.mark:SetPoint("CENTER")
  row.qty = W.Text(row, { role = "ui", justify = "RIGHT" })
  row.qty:SetPoint("RIGHT", -PAD, 0)
  row.qty:SetWidth(44)
  row.name = W.Text(row, { role = "ui" })
  row.name:SetPoint("LEFT", PAD + BOX + 6, 0)
  row.name:SetPoint("RIGHT", row.qty, "LEFT", -4, 0)
  row.name:SetMaxLines(1)
  row:SetScript("OnEnter", function(self)
    self.hover:SetColorTexture(1, 1, 1, 0.06)
    if self.line then
      S.RowTooltip(self, self.line)
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.hover:SetColorTexture(1, 1, 1, 0)
    ns.HideTooltip()
  end)
  row:SetScript(
    "OnClick",
    ns.Wrap("proftracker-row", function(self, button)
      S.RowClick(self.line, button)
    end)
  )
  row.box:SetScript(
    "OnClick",
    ns.Wrap("proftracker-tick", function()
      if row.line then
        S.SetChecked(row.slug, row.line.id, not row.ticked)
      end
    end)
  )
  row.box:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, L["profshop.rowTip"])
  end)
  row.box:SetScript("OnLeave", ns.HideTooltip)
  ns.Focus.register(row, function(self)
    self:Click()
  end)
  ns.Focus.register(row.box, function(self)
    self:Click()
  end)
  return row
end

local function paintRow(row, item)
  local line, ticked = item.line, item.ticked
  row.line, row.slug, row.ticked = line, item.slug, ticked
  row.mark:SetShown(ticked)
  row.boxOn:SetShown(ticked)
  row.boxBorder.set(ticked and "actionHi" or "white", ticked and 1 or 0.4)
  local color = ticked and "textMuted" or "text"
  -- A ticked line is done and stays muted, an open one shows the quality color of its item.
  row.name:SetText(ticked and line.name or ns.ItemInfo.ColorName(line.name, ns.ItemInfo.quality(line.id)))
  W.SetColor(row.name, color)
  row.qty:SetText(tostring(line.qty))
  W.SetColor(row.qty, color)
end

-- The lines of the plan, open ones first, ticked ones after them: { items, open }.
local function entries(plan)
  local open, done, checked = {}, {}, S.Checked(plan.slug)
  for _, group in ipairs(plan.groups or {}) do
    for _, line in ipairs(group.lines) do
      local ticked = checked[line.id] == true
      local list = ticked and done or open
      list[#list + 1] = { line = line, slug = plan.slug, ticked = ticked }
    end
  end
  local count = #open
  for _, item in ipairs(done) do
    open[#open + 1] = item
  end
  return open, count
end

-- Panel -------------------------------------------------------------------------------------------

local function height(rows, more)
  if frameDb().collapsed == true then
    return HEAD_H
  end
  return HEAD_H + PAD + BUTTON_H + 4 + rows * ROW_H + (more and ROW_H or 0) + PAD
end

local function setCollapsed(f, on)
  frameDb().collapsed = on or nil
  f.collapse:SetIcon(on and "plus" or "minus")
  f.body:SetShown(not on)
  f:SetHeight(height(f.shownRows or 0, f.hasMore))
end

local function create()
  local f = CreateFrame("Frame", "FGProfTrackerWindow", UIParent)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetSize(WIDTH, HEAD_H)
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.shell = ns.WindowShell.Attach(f, { title = "profshop.title", titleHeight = HEAD_H, shadow = true })
  f.border, f.bar, f.barBg, f.title = f.shell.border, f.shell.titleBar, f.shell.barFill, f.shell.titleText

  f.bar:EnableMouse(true)
  f.bar:RegisterForDrag("LeftButton")
  f.bar:SetScript("OnDragStart", function()
    if inCombat() then
      return
    end
    f.dragging = true
    WS.Hold(f, "move", true)
    f:StartMoving()
  end)
  f.bar:SetScript(
    "OnDragStop",
    ns.Wrap("proftracker-move", function()
      if not f.dragging then
        return
      end
      f:StopMovingOrSizing()
      f.dragging = nil
      WS.Hold(f, "move", false)
      saveOffset(f)
      f.replace = true
      if not inCombat() then
        place(f)
      end
    end)
  )
  f.bar:EnableMouseWheel(true)
  f.bar:SetScript(
    "OnMouseWheel",
    ns.Wrap("proftracker-scale", function(_, delta)
      if ns.Keys.Matches("windowScale") then
        changeScale(f, delta)
      end
    end)
  )

  f.look = W.Action(f.bar, { icon = "palette", size = 18, tooltip = "wstyle.title" })
  f.look:SetPoint("RIGHT", -2, 0)
  f.look:SetScript(
    "OnClick",
    ns.Wrap("proftracker-look", function()
      T.OpenLook()
    end)
  )
  f.collapse = W.Action(f.bar, { icon = "minus", size = 18, tooltip = "proftracker.collapse" })
  f.collapse:SetPoint("RIGHT", f.look, "LEFT", -2, 0)
  f.collapse:SetScript(
    "OnClick",
    ns.Wrap("proftracker-collapse", function()
      setCollapsed(f, frameDb().collapsed ~= true)
    end)
  )
  f.title:ClearAllPoints()
  f.title:SetPoint("LEFT", 8, 0)
  f.title:SetPoint("RIGHT", f.collapse, "LEFT", -4, 0)

  -- Everything below the title bar, hidden while collapsed.
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", 0, -HEAD_H)
  f.body:SetPoint("BOTTOMRIGHT", 0, 0)
  local half = math.floor((WIDTH - 2 * PAD - 6) / 2)
  f.send = W.Action(f.body, {
    label = "act.send",
    icon = "share",
    width = half,
    height = BUTTON_H,
    tooltip = "profshop.send",
    tooltipText = "profshop.sendTip",
    onClick = function()
      SW.Send(S.Plan())
    end,
  })
  f.send:SetPoint("TOPLEFT", PAD, -PAD)
  f.window = W.Action(f.body, {
    label = "act.open",
    icon = "open",
    width = half,
    height = BUTTON_H,
    tooltip = "profshop.title",
    tooltipText = "profroute.shopTip",
    onClick = function()
      SW.Open()
    end,
  })
  f.window:SetPoint("TOPRIGHT", -PAD, -PAD)

  f.rows = {}
  f.more = W.Text(f.body, { role = "micro", color = "textMuted" })

  f.styleParts = {
    bg = { f.bg },
    bars = { f.barBg },
    border = f.border,
    shadow = f.shell.shadow,
    chrome = { f.bar },
    busy = function()
      return WS.PanelOpenFor(f) or WS.PickerOpenFor(f)
    end,
  }
  f:Hide()
  return f
end

local function rowAt(f, index)
  local row = f.rows[index]
  if not row then
    row = newRow(f.body)
    f.rows[index] = row
  end
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -(PAD + BUTTON_H + 4 + (index - 1) * ROW_H))
  row:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, -(PAD + BUTTON_H + 4 + (index - 1) * ROW_H))
  return row
end

local function paint(f, list)
  local shown = math.min(#list, MAX_ROWS)
  for i = 1, shown do
    local row = rowAt(f, i)
    paintRow(row, list[i])
    row:Show()
  end
  for i = shown + 1, #f.rows do
    f.rows[i]:Hide()
  end
  f.shownRows, f.hasMore = shown, #list > shown
  f.more:SetShown(f.hasMore)
  if f.hasMore then
    f.more:SetText(string.format(L["proftracker.more"], #list - shown))
    f.more:ClearAllPoints()
    f.more:SetPoint("TOPLEFT", f.body, "TOPLEFT", PAD, -(PAD + BUTTON_H + 4 + shown * ROW_H + 3))
  end
  f:SetHeight(height(shown, f.hasMore))
end

-- The tracker shows and hides without a hint to us, so its two scripts re-anchor the panel.
local hooked = setmetatable({}, { __mode = "k" })

local function hookTracker()
  local tracker = rawget(_G, "ObjectiveTrackerFrame")
  if type(tracker) ~= "table" or hooked[tracker] or type(tracker.HookScript) ~= "function" then
    return
  end
  hooked[tracker] = true
  local function later()
    ns.Debounce("proftracker-anchor", ANCHOR_DELAY, T.Refresh)
  end
  pcall(tracker.HookScript, tracker, "OnShow", later)
  pcall(tracker.HookScript, tracker, "OnHide", later)
end

local function hide()
  if frame and frame:IsShown() then
    frame:Hide()
  end
end

-- Shows, fills and places the panel, or hides it: setting off, no chosen route or nothing open.
function T.Refresh()
  if not ns.db or not T.Enabled() then
    hide()
    return
  end
  local plan = S.Option("slug") ~= nil and S.Plan() or nil
  local list, open = {}, 0
  if plan and plan.data then
    list, open = entries(plan)
  end
  if open == 0 or (inCombat() and not (frame and frame.placed)) then
    hide()
    return
  end
  hookTracker()
  if not frame then
    frame = create()
    frame:SetScale(scaleOf())
    setCollapsed(frame, frameDb().collapsed == true)
    applyLook(frame)
  end
  if not inCombat() and not frame.dragging then
    local a = anchor()
    if not frame.placed or frame.replace or frame.mode ~= a.mode or frame.rel ~= a.rel then
      place(frame)
    end
  end
  paint(frame, list)
  if not frame:IsShown() then
    frame:Show()
  end
end

function T.Frame()
  return frame
end

local function whenEnabled()
  if T.Enabled() then
    ns.Debounce("proftracker-refresh", REFRESH_DELAY, T.Refresh)
  end
end

ns.On("FG_PROFROUTE_CHANGED", T.Refresh)
ns.On("BAG_UPDATE_DELAYED", whenEnabled)
ns.On("SKILL_LINES_CHANGED", whenEnabled)
ns.On("PLAYER_REGEN_ENABLED", function()
  if frame or T.Enabled() then
    T.Refresh()
  end
end)
ns.On("PLAYER_LOGIN", T.Refresh)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.profTracker" then
    T.Refresh()
  elseif frame and WS.AffectsKind(path, "proftracker") then
    applyLook(frame)
  end
end)
