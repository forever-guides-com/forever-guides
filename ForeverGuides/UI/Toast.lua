-- Toast stack: small notifications at the top right of the screen, fed by ns.Notify
-- (Core/Notify.lua decides when a message becomes a toast). Frames are pooled, plain
-- (non-secure) and only the toast rectangles take mouse, so the game world stays clickable.
-- Also the history popup ("Recent messages") and the position editor.
local _, ns = ...
local W, Theme, U, L, IconDraw = ns.W, ns.Theme, ns.U, ns.L, ns.IconDraw

local Toast = { active = {}, queue = {}, created = 0 }
ns.Toast = Toast

ns.AddLocale("enUS", {
  ["toast.history"] = "Recent messages",
  ["toast.history.empty"] = "No messages yet.",
  ["toast.level.success"] = "Done",
  ["toast.level.info"] = "Info",
  ["toast.level.warning"] = "Warning",
  ["toast.level.error"] = "Error",
  ["toast.sample"] = "Drag to move, right-click when done.",
  ["toast.test.success"] = "Test message: drawing House saved.",
  ["toast.test.info"] = "Test message: this is how a hint looks.",
  ["toast.test.warning"] = "Test message: this is how a warning looks.",
  ["toast.test.error"] = "Test message: this is how an error looks.",
})
ns.AddLocale("deDE", {
  ["toast.history"] = "Letzte Meldungen",
  ["toast.history.empty"] = "Noch keine Meldungen.",
  ["toast.level.success"] = "Erledigt",
  ["toast.level.info"] = "Info",
  ["toast.level.warning"] = "Warnung",
  ["toast.level.error"] = "Fehler",
  ["toast.sample"] = "Ziehen zum Verschieben, Rechtsklick zum Beenden.",
  ["toast.test.success"] = "Testmeldung: Zeichnung Haus gespeichert.",
  ["toast.test.info"] = "Testmeldung: So sieht ein Hinweis aus.",
  ["toast.test.warning"] = "Testmeldung: So sieht eine Warnung aus.",
  ["toast.test.error"] = "Testmeldung: So sieht ein Fehler aus.",
})

local MAX_VISIBLE = 4
local MAX_QUEUE = 20
local WIDTH = 320
local MIN_HEIGHT = 32
local PAD_Y = 8
local TEXT_LEFT = 34
local TEXT_WIDTH = WIDTH - TEXT_LEFT - 10
local GAP = 6
local FADE = 0.15
local DUPLICATE_WINDOW = 1.5
-- A hovered toast lingers at least this long after the mouse leaves.
local LINGER = 1
local BUTTON_W, BUTTON_H = 24, 18
local HISTORY_ROWS = 50
local STRATA = "FULLSCREEN_DIALOG"

local DURATION = { success = 3.5, info = 3.5, warning = 6, error = 9 }
local STYLE = {
  success = { color = "success", glyph = "check" },
  info = { color = "accent", glyph = "toast-info" },
  warning = { color = "warning", glyph = "toast-warning" },
  error = { color = "danger", glyph = "close" },
}
local LEVEL_ORDER = { "success", "info", "warning", "error" }

local DEFAULT_POSITION = { point = "TOPRIGHT", rel = "TOPRIGHT", x = -20, y = -120 }
local ANCHORS = {
  TOPLEFT = true,
  TOP = true,
  TOPRIGHT = true,
  LEFT = true,
  CENTER = true,
  RIGHT = true,
  BOTTOMLEFT = true,
  BOTTOM = true,
  BOTTOMRIGHT = true,
}

-- Glyphs on IconDraw's 12 x 12 grid, so the level never relies on color alone.
IconDraw.register("toast-info", function(p)
  p:Rect(5, 1, 2, 2)
  p:Rect(5, 4, 2, 7)
end)
IconDraw.register("toast-warning", function(p)
  p:Rect(5, 1, 2, 6)
  p:Rect(5, 9, 2, 2)
end)
IconDraw.register("toast-history", function(p)
  for y = 2, 8, 3 do
    p:Rect(1, y, 2, 2)
    p:Rect(4, y, 7, 2)
  end
end)

local anchor, driver, historyButton, sample
local ensure
local pool = {}
local editing = false

local function clock()
  return type(GetTime) == "function" and GetTime() or 0
end

local function number(v, fallback)
  v = tonumber(v)
  if v == nil or v ~= v then
    return fallback
  end
  return v
end

-- Position -----------------------------------------------------------------------------------

-- Saved position, validated: damaged SavedVariables fall back to the default.
function Toast.Position()
  local saved = ns.db and ns.db.frames and ns.db.frames.toast
  local d = DEFAULT_POSITION
  if type(saved) ~= "table" or not ANCHORS[saved.point] or not ANCHORS[saved.rel] then
    return d.point, d.rel, d.x, d.y
  end
  return saved.point, saved.rel, number(saved.x, d.x), number(saved.y, d.y)
end

local function applyPosition()
  local point, rel, x, y = Toast.Position()
  anchor:ClearAllPoints()
  anchor:SetPoint(point, UIParent, rel, x, y)
end

local function applyScale()
  anchor:SetScale(Theme.windowScale())
end

local function savePosition()
  if not (ns.db and ns.db.frames) then
    return
  end
  local point, _, rel, x, y = anchor:GetPoint(1)
  if not (ANCHORS[point] and ANCHORS[rel]) then
    return
  end
  ns.db.frames.toast = { point = point, rel = rel, x = number(x, 0), y = number(y, 0) }
end

function Toast.ResetPosition()
  if ns.db and ns.db.frames then
    ns.db.frames.toast = U.copy(DEFAULT_POSITION)
  end
  if anchor then
    applyPosition()
  end
end

-- Layout -------------------------------------------------------------------------------------

local function layout()
  local y = 0
  if sample then
    sample:SetShown(editing)
    if editing then
      sample:ClearAllPoints()
      sample:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
      y = sample:GetHeight() + GAP
    end
  end
  historyButton:SetShown(editing or #Toast.active > 0)
  if historyButton:IsShown() then
    historyButton:ClearAllPoints()
    historyButton:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, -y)
    y = y + BUTTON_H + GAP
  end
  for _, e in ipairs(Toast.active) do
    local f = e.frame
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, -y)
    y = y + f:GetHeight() + GAP
  end
end

-- Frames -------------------------------------------------------------------------------------

local function styleOf(level)
  return STYLE[level] or STYLE.info
end

local function setLevel(f, level)
  f.level = level
  local style = styleOf(level)
  f.icon:Draw(style.glyph)
  f.icon:SetTint(style.color)
  f.bar:SetColorTexture(Theme.color(style.color))
end

-- Text and height; the font was set when the FontString was created.
local function setText(f, text)
  f.text:SetWidth(TEXT_WIDTH)
  f.text:SetText(text)
  local lineHeight = math.ceil(Theme.fontSize("ui") * 1.3)
  local height = math.min(f.text:GetStringHeight(), lineHeight * 3)
  f:SetHeight(math.max(MIN_HEIGHT, math.ceil(height) + PAD_Y * 2))
end

local function shownText(e)
  return e.count > 1 and (e.text .. "  x" .. e.count) or e.text
end

local function newFrame()
  Toast.created = Toast.created + 1
  local f = CreateFrame("Button", nil, anchor)
  f:SetSize(WIDTH, MIN_HEIGHT)
  f:SetFrameStrata(STRATA)
  f:EnableMouse(true)
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  W.Fill(f, "surface", 0.96)
  f.border = W.Border(f, "accentDim", 0.7)
  f.bar = f:CreateTexture(nil, "ARTWORK")
  f.bar:SetPoint("TOPLEFT")
  f.bar:SetPoint("BOTTOMLEFT")
  f.bar:SetWidth(4)
  f.icon = IconDraw.new(f, 12)
  f.icon:SetPoint("TOPLEFT", 14, -PAD_Y - 1)
  f.text = W.Text(f, { role = "ui", color = "text", wrap = true })
  f.text:SetPoint("TOPLEFT", f, "TOPLEFT", TEXT_LEFT, -PAD_Y)
  if f.text.SetMaxLines then
    f.text:SetMaxLines(3)
  end
  f:SetScript("OnEnter", function(self)
    local e = self.entry
    if e then
      e.hover = true
      e.left = math.max(e.left, LINGER)
    end
  end)
  f:SetScript("OnLeave", function(self)
    if self.entry then
      self.entry.hover = false
    end
  end)
  f:SetScript(
    "OnClick",
    ns.Wrap("toast-click", function(self, button)
      if button == "RightButton" then
        Toast.Clear()
      elseif self.entry then
        Toast.Dismiss(self.entry)
      end
    end)
  )
  ns.Bind(f, function(self)
    if self.level then
      self.bar:SetColorTexture(Theme.color(styleOf(self.level).color))
    end
  end)
  return f
end

local function acquire()
  local f = table.remove(pool) or newFrame()
  f:SetAlpha(1)
  return f
end

local function release(e)
  local f = e.frame
  if not f then
    return
  end
  e.frame = nil
  f.entry = nil
  f:Hide()
  f:ClearAllPoints()
  pool[#pool + 1] = f
end

local function display(e)
  local f = acquire()
  f.entry, e.frame = e, f
  e.shown, e.left, e.hover = 0, e.duration, false
  setLevel(f, e.level)
  setText(f, shownText(e))
  f:SetAlpha(Theme.reduceMotion() and 1 or 0)
  table.insert(Toast.active, 1, e)
  f:Show()
end

local function promote()
  while #Toast.active < MAX_VISIBLE and #Toast.queue > 0 do
    display(table.remove(Toast.queue, 1))
  end
end

local function refresh()
  ensure()
  promote()
  layout()
  if #Toast.active > 0 then
    driver:Show()
  else
    driver:Hide()
  end
end

-- Seconds a toast stays: by level, a little longer for long texts.
function Toast.Duration(text, level, opts)
  local custom = opts and number(opts.duration, 0) or 0
  if custom > 0 then
    return custom
  end
  return (DURATION[level] or DURATION.info) * (1 + math.min(#text, 160) / 160 * 0.5)
end

local function remove(list, e)
  for i, item in ipairs(list) do
    if item == e then
      table.remove(list, i)
      return true
    end
  end
  return false
end

function Toast.Dismiss(e)
  if remove(Toast.active, e) then
    release(e)
  else
    remove(Toast.queue, e)
  end
  refresh()
end

function Toast.Clear()
  for i = #Toast.active, 1, -1 do
    release(table.remove(Toast.active, i))
  end
  for i = #Toast.queue, 1, -1 do
    Toast.queue[i] = nil
  end
  refresh()
end

-- Advances every timer by dt seconds (the driver's OnUpdate): fade in, countdown unless
-- hovered, fade out in the last moments. Reduce motion skips the fades.
function Toast.Tick(dt)
  dt = number(dt, 0)
  local fade = not Theme.reduceMotion()
  local expired
  for _, e in ipairs(Toast.active) do
    e.shown = e.shown + dt
    if not e.hover then
      e.left = e.left - dt
    end
    if e.left <= 0 then
      expired = expired or {}
      expired[#expired + 1] = e
    else
      local alpha = 1
      if fade then
        alpha = math.min(1, e.shown / FADE, e.left / FADE)
      end
      e.frame:SetAlpha(U.clamp(alpha, 0, 1))
    end
  end
  for _, e in ipairs(expired or {}) do
    remove(Toast.active, e)
    release(e)
  end
  if expired then
    refresh()
  end
end

ensure = function()
  if anchor then
    return
  end
  anchor = CreateFrame("Frame", "ForeverGuidesToasts", UIParent)
  Toast.anchor = anchor
  anchor:SetSize(WIDTH, 24)
  anchor:SetFrameStrata(STRATA)
  anchor:SetClampedToScreen(true)
  anchor:SetMovable(true)
  applyPosition()
  applyScale()

  driver = CreateFrame("Frame", nil, UIParent)
  Toast.driver = driver
  driver:SetScript("OnUpdate", function(_, dt)
    Toast.Tick(dt)
  end)
  driver:Hide()

  historyButton = W.Action(anchor, {
    icon = "history",
    variant = "boxed",
    width = BUTTON_W,
    height = BUTTON_H,
    iconSize = 14,
    tooltip = "toast.history",
    onClick = function()
      Toast.OpenHistory()
    end,
  })
  Toast.historyButton = historyButton
  historyButton:SetFrameStrata(STRATA)
  historyButton:Hide()
end

-- Shows a toast; returns its entry. The same text again within the duplicate window counts
-- up ("x2") instead of stacking another one.
function Toast.Show(text, level, opts)
  text = tostring(text == nil and "" or text)
  if text == "" then
    return nil
  end
  if not STYLE[level] then
    level = "info"
  end
  ensure()
  applyScale()
  local now = clock()
  for _, list in ipairs({ Toast.active, Toast.queue }) do
    for _, e in ipairs(list) do
      if e.text == text and now - e.stamp <= DUPLICATE_WINDOW then
        e.count, e.stamp, e.left = e.count + 1, now, e.duration
        if e.frame then
          setText(e.frame, shownText(e))
          layout()
        end
        return e
      end
    end
  end
  local e = { text = text, level = level, count = 1, stamp = now, duration = Toast.Duration(text, level, opts) }
  if #Toast.active < MAX_VISIBLE then
    display(e)
  else
    Toast.queue[#Toast.queue + 1] = e
    if #Toast.queue > MAX_QUEUE then
      table.remove(Toast.queue, 1)
    end
  end
  refresh()
  return e
end

function Toast.Visible()
  return #Toast.active
end

function Toast.Queued()
  return #Toast.queue
end

-- One toast per level, to show what the current setting looks like. force makes mode "off"
-- show them too, otherwise the button would do nothing visible.
function Toast.SendTest()
  for _, level in ipairs(LEVEL_ORDER) do
    ns.Notify(L["toast.test." .. level], level, { force = true })
  end
end

-- Position editor ----------------------------------------------------------------------------

function Toast.IsEditing()
  return editing
end

-- While editing, a sample toast is the drag handle of the stack; right-click ends editing.
function Toast.SetEditing(on)
  on = on and true or false
  if on == editing then
    return
  end
  ensure()
  editing = on
  if on and not sample then
    sample = newFrame()
    Toast.sample = sample
    sample:RegisterForDrag("LeftButton")
    sample:SetScript("OnDragStart", function()
      anchor:StartMoving()
    end)
    sample:SetScript("OnDragStop", function()
      anchor:StopMovingOrSizing()
      savePosition()
    end)
    sample:SetScript(
      "OnClick",
      ns.Wrap("toast-sample", function(_, button)
        if button == "RightButton" then
          Toast.SetEditing(false)
        end
      end)
    )
    sample.border.set("actionHi", 1)
    setLevel(sample, "info")
  end
  if on then
    setText(sample, L["toast.sample"])
  end
  refresh()
  ns.Emit("FG_TOAST_EDITING", editing)
end

ns.On("FG_SETTING_CHANGED", function(_, path)
  if anchor and path == "settings.scale" then
    applyScale()
  end
end)

-- History popup ------------------------------------------------------------------------------

local history

local function buildHistory()
  local f = ns.Dialogs.Create("ForeverGuidesNotifyHistory", 480, 400)
  W.SetText(f.title, "toast.history")
  local area = W.ScrollArea(f)
  area:SetPoint("TOPLEFT", 16, -48)
  area:SetPoint("BOTTOMRIGHT", -16, 16)
  local stack = W.Stack(area, 6)
  f.area, f.stack, f.rows = area, stack, {}
  f.empty = W.Text(area.content, { key = "toast.history.empty", role = "ui", color = "textMuted", wrap = true })
  stack:Add(f.empty, { gap = 6 })
  for i = 1, HISTORY_ROWS do
    local row = W.Text(area.content, { role = "ui", color = "text", wrap = true })
    stack:Add(row, { gap = 6 })
    f.rows[i] = row
  end
  area:HookScript("OnSizeChanged", function()
    ns.Debounce(f, 0.05, function()
      stack:Layout()
    end)
  end)
  return f
end

local function rowText(e)
  local style = styleOf(e.l)
  local fmt = type(date) == "function" and date or (os and os.date)
  local stamp = fmt and fmt("%H:%M:%S", e.t) or ""
  local count = e.n > 1 and ("  x" .. e.n) or ""
  return Theme.hexText(style.color, L["toast.level." .. e.l]) .. "  " .. stamp .. "  " .. e.m .. count
end

local function refreshHistory()
  local items = ns.Notify.history:list()
  history.empty:SetShown(#items == 0)
  for i, row in ipairs(history.rows) do
    local e = items[#items - i + 1]
    if e then
      row:SetText(rowText(e))
    end
    row:SetShown(e ~= nil)
  end
  history.stack:Layout()
end

-- Opens the popup with the last notifications, newest first; a second call closes it.
function Toast.OpenHistory()
  history = history or buildHistory()
  if history:IsShown() then
    history:Hide()
    return
  end
  history:Show()
  refreshHistory()
end

function Toast.HistoryFrame()
  return history
end
