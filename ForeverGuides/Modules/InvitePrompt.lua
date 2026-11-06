-- Guild invite request of a whisper ("ginv"): the game only takes the guild invite from a click or a key
-- (a hardware event), never from a chat event, so the add-on asks first. Two looks (settings.inviteBarStyle):
-- "window", a small window at the top with the name, the text and two buttons, and "bar", one line.
-- Both end in the same click handler: invoke(row) calls handlers.invite. When the game blocks that
-- call, the normal button hides and the secure button below it (a macro with /ginvite, run by the game
-- itself) takes the next click. Buttons are made and armed out of combat only; a request that arrives in
-- combat waits and is shown when the combat ends. A copy button shows the command as the last fallback.
-- Demo rows (P.ShowDemo, the settings preview and the developer preview) look the same and call nothing.
local _, ns = ...
local W, L, Theme = ns.W, ns.L, ns.Theme
local PN = ns.PlayerName
local PL = ns.InvitePromptLogic

local P = {}
ns.InvitePrompt = P

ns.AddLocale("enUS", {
  ["invite.prompt.text"] = "%s wants to join the guild (ginv)",
  ["invite.prompt.windowText"] = "wants to join the guild (ginv)",
  ["invite.prompt.button"] = "Invite to guild",
  ["invite.prompt.copy"] = "Copy command",
  ["invite.prompt.copyTitle"] = "Guild invite command",
  ["invite.prompt.copyHint"] = "Press Ctrl+C, open the chat with Enter, paste with Ctrl+V and press Enter. The game only takes this invite when you enter the command yourself.",
  ["invite.prompt.detail"] = "Level %d %s",
  ["invite.prompt.detailLevel"] = "Level %d",
  ["invite.prompt.hint"] = "Key %s",
  ["invite.prompt.hintMore"] = "Key %s, %d more",
  ["invite.prompt.more"] = "+%d more waiting",
  ["invite.prompt.closeAll"] = "Close all",
  ["invite.prompt.overflow"] = "More than %d waiting invites, the oldest are dropped",
  ["invite.prompt.demoNote"] = "Demo: no invite sent",
  ["invite.prompt.demoClass"] = "Warrior",
})
ns.AddLocale("deDE", {
  ["invite.prompt.text"] = "%s möchte in die Gilde (ginv)",
  ["invite.prompt.windowText"] = "möchte in die Gilde (ginv)",
  ["invite.prompt.button"] = "In die Gilde einladen",
  ["invite.prompt.copy"] = "Befehl kopieren",
  ["invite.prompt.copyTitle"] = "Gilden-Einladungsbefehl",
  ["invite.prompt.copyHint"] = "Drücke Strg+C, öffne den Chat mit Enter, füge mit Strg+V ein und drücke Enter. Das Spiel nimmt diese Einladung nur an, wenn du den Befehl selbst eingibst.",
  ["invite.prompt.detail"] = "Stufe %d %s",
  ["invite.prompt.detailLevel"] = "Stufe %d",
  ["invite.prompt.hint"] = "Taste %s",
  ["invite.prompt.hintMore"] = "Taste %s, %d weitere",
  ["invite.prompt.more"] = "+%d weitere warten",
  ["invite.prompt.closeAll"] = "Alle schließen",
  ["invite.prompt.overflow"] = "Mehr als %d wartende Einladungen, die ältesten fallen weg",
  ["invite.prompt.demoNote"] = "Demo: keine Einladung gesendet",
  ["invite.prompt.demoClass"] = "Krieger",
})

P.SLASH = "/ginvite"
-- At most MAX_ROWS requests are on screen, the rest waits unseen in a line of at most MAX_WAITING. The lifetime of
-- a request starts when it shows.
P.MAX_ROWS = 4
P.MAX_WAITING = 300
P.LIFETIME = 120
-- First line of the macro: the secure code itself refuses to run in combat.
local GUARD_LINE = "/stopmacro [combat]"
-- Sizes in the units of the frame: the window is as wide as its name and buttons need, within these limits.
local WIN_MIN_W, WIN_MAX_W, WIN_TOP = 340, 520, 48
local BAR_MIN_W, BAR_MAX_W, BAR_MIN_H, BAR_TOP = 600, 900, 34, 150
local PAD, GAP, CLOSE_ROOM, BTN_PAD, BTN_MIN_W = 14, 6, 28, 24, 110
local GAP_ROWS = 4
-- The bar keeps at least this much room for its text before the count of waiting requests is dropped.
local BAR_TEXT_ROOM = 160
-- A demo may show both looks at once: the pool holds the real rows and these.
local DEMO_ROWS = 2
local DEMO_LIFETIME = 15
local TICK = 0.25
local DEMO_NAME = "Wayneelf-Blackhand"

local rows, waiting = {}, {}
-- True after the line overflowed, until it is empty again: the chat gets one line per overflow.
local overflowed = false
-- The key hint: label of the key (nil = none) and the row that carries it, set by InviteKey.
local hintLabel, hintRow = nil, nil
-- Set while "close all" empties the line, so no waiting request moves up in between.
local closingAll = false
local pump
-- Rows that were released in combat; their attributes are cleared when the combat ends.
local stale = {}
local secureFailed = false
local driver, sinceTick = nil, 0
local nextId = 0
local needReflow = false

local function inCombat()
  return ns.InCombat()
end

local function clock()
  local fn = rawget(_G, "GetTime")
  return type(fn) == "function" and tonumber(fn()) or 0
end

-- A name that is safe inside a slash command: one line, no escape sequences.
local function safeName(name)
  return type(name) == "string" and name ~= "" and #name <= 80 and not name:find("[%c|]") and name or nil
end

-- The command to paste, nil for an unsafe name.
function P.Command(name)
  name = safeName(name)
  return name and (P.SLASH .. " " .. name) or nil
end

-- Opens the copy box with the command of one player (the way that works where the game refuses add-ons).
function P.OpenCopy(name)
  local text = P.Command(name)
  if text and ns.Dialogs and ns.Dialogs.Copy then
    ns.Dialogs.Copy("invite.prompt.copyTitle", text, "invite.prompt.copyHint")
    return true
  end
  return false
end

function P.MacroText(name)
  local command = P.Command(name)
  return command and (GUARD_LINE .. "\n" .. command) or nil
end

-- The look the player chose: "window" or "bar".
function P.Style()
  local settings = ns.db and ns.db.settings
  return PL.CleanStyle(settings and settings.inviteBarStyle)
end

local function classColor(token)
  return type(token) == "string" and Theme.classColors[token] or nil
end

-- Class color as "#rrggbb", lightened until it reads on the surface the name stands on (the title strip in the
-- window, the bar body in the bar) in the theme, skin and contrast mode in force; nil for an unknown class.
local function readableClass(token, window)
  local hex = classColor(token)
  return hex and (Theme.readable(hex, Theme.hex(window and "surface3" or "surface"))) or nil
end

local function coloredName(row)
  local hex = readableClass(row.info.class, false)
  return hex and ("|cff" .. hex:gsub("#", "") .. row.name .. "|r") or row.name
end

local function detailText(info)
  local level, className = PL.CleanLevel(info.level), PL.PlainText(info.className)
  if level and className then
    return string.format(L["invite.prompt.detail"], level, className)
  elseif level then
    return string.format(L["invite.prompt.detailLevel"], level)
  end
  return className or ""
end

local function openCount(demo)
  local n = 0
  for _, row in ipairs(rows) do
    if not row.free and (row.demo == true) == demo then
      n = n + 1
    end
  end
  return n
end

-- Layout ----------------------------------------------------------------------------------------

local function clamp(value, low, high)
  return math.min(high, math.max(low, value))
end

-- Width of a text in the font of a hidden measuring text (it has no box, so nothing wraps).
local function textWidth(fs, text)
  fs:SetText(text)
  return fs:GetStringWidth() or 0
end

local function lineHeight(fs)
  fs:SetText("Ag")
  return math.max(12, fs:GetStringHeight() or 0)
end

local function screenWidth(scale)
  local width = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
  return width > 0 and width / math.max(scale, 0.1) or nil
end

-- Requests that are open or waiting, the real ones only.
local function pendingCount()
  local n = #waiting
  for _, row in ipairs(rows) do
    if not row.free and not row.demo then
      n = n + 1
    end
  end
  return n
end

-- Text of the key hint of a row: the key and how many requests follow this one.
local function hintTextFor(row)
  if not hintLabel or row ~= hintRow or row.free then
    return ""
  end
  local more = math.max(0, pendingCount() - 1)
  if more > 0 then
    return string.format(L["invite.prompt.hintMore"], hintLabel, more)
  end
  return string.format(L["invite.prompt.hint"], hintLabel)
end

-- The shown rows, oldest request first.
local function ordered()
  local list = {}
  for _, row in ipairs(rows) do
    if not row.free then
      list[#list + 1] = row
    end
  end
  table.sort(list, function(a, b)
    return (a.id or 0) < (b.id or 0)
  end)
  return list
end

local layout

-- The footer (count of waiting requests, "close all") belongs to the bottom real request, as soon as more than
-- one request is open or waiting. A row is laid out again only when its footer appears, goes or changes its width.
local function updateFooters()
  local bottom
  for _, row in ipairs(ordered()) do
    if not row.demo then
      bottom = row
    end
  end
  local text = #waiting > 0 and string.format(L["invite.prompt.more"], #waiting) or ""
  local crowded = pendingCount() > 1
  for _, row in ipairs(rows) do
    local want = not row.free and not row.demo and row == bottom and crowded
    local moreText = want and text or ""
    if inCombat() then
      row.more:SetText(moreText)
    elseif want ~= (row.footer == true) or (want and row.layoutStyle == "bar" and moreText ~= row.moreText) then
      row.footer, row.moreText = want, moreText
      row.more:SetText(moreText)
      if not row.free then
        layout(row, row.layoutStyle)
      end
    else
      row.moreText = moreText
      row.more:SetText(moreText)
    end
  end
end

-- The shown rows one below the other from the top middle of the screen. Not in combat (a protected child).
local function reflow()
  if ns.InCombat() then
    needReflow = true
    return
  end
  needReflow = false
  updateFooters()
  local any = false
  for _, row in ipairs(rows) do
    if not row.free and row.layoutStyle == "window" then
      any = true
    end
  end
  local y = any and WIN_TOP or BAR_TOP
  for _, row in ipairs(ordered()) do
    local f = row.frame
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, -y)
    y = y + f:GetHeight() + GAP_ROWS
  end
end

-- The key hint of every row (only the row that carries the key shows one).
local function updateHints()
  for _, row in ipairs(rows) do
    local text = hintTextFor(row)
    if text ~= (row.hintWant or "") then
      row.hintWant = text ~= "" and text or nil
      row.hintShort = hintLabel and text ~= "" and string.format(L["invite.prompt.hint"], hintLabel) or nil
      row.hint:SetText(text)
      -- A longer hint can wrap onto a second line of the window or widen the bar.
      if
        not row.free
        and not inCombat()
        and (row.layoutStyle == "bar" or row.hintLines ~= math.ceil(row.hint:GetStringHeight() or 0))
      then
        layout(row, row.layoutStyle)
        needReflow = true
      end
    end
  end
  if needReflow and not inCombat() then
    reflow()
  end
end

local function resize(button, width, height)
  button:SetSize(width, height)
  if button.fgPlace then
    button.fgPlace(button)
  end
end

-- Widths of the two buttons: the label and a margin, at least BTN_MIN_W, shrunk together when they do not fit.
local function buttonWidths(row, room)
  local invite = math.max(BTN_MIN_W, textWidth(row.measureUi, L["invite.prompt.button"]) + BTN_PAD)
  local copy = math.max(BTN_MIN_W, textWidth(row.measureUi, L["invite.prompt.copy"]) + BTN_PAD)
  if invite + copy + GAP > room then
    local factor = math.max(0, room - GAP) / (invite + copy)
    invite, copy = math.floor(invite * factor), math.floor(copy * factor)
  end
  return invite, copy
end

local PARTS =
  { "text", "title", "detail", "hint", "barClose", "winClose", "button", "direct", "copy", "more", "closeAll" }

-- The footer line of the bottom request: how many wait and the button that closes them all.
local function footerHeight(row)
  return row.footer and (math.max(20, math.ceil(lineHeight(row.measureUi)) + 6) + GAP) or 0
end

local function layoutFooter(row, y)
  local c = row.content
  local on = row.footer == true
  row.more:SetShown(on)
  row.closeAll:SetShown(on)
  if not on then
    return y
  end
  local h = footerHeight(row) - GAP
  local closeW = math.max(70, textWidth(row.measureUi, L["invite.prompt.closeAll"]) + BTN_PAD)
  row.closeAll:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -y)
  resize(row.closeAll, closeW, h)
  row.more:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y - 2)
  row.more:SetWidth(math.max(40, (row.width or WIN_MIN_W) - closeW - 3 * PAD))
  return y + h + GAP
end

local function layoutWindow(row)
  local f, c = row.frame, row.content
  row.hint:SetText(row.hintWant or "")
  local textW = textWidth(row.measureUi, L["invite.prompt.windowText"])
  local nameW = textWidth(row.measureTitle, row.name)
  local inviteW, copyW = buttonWidths(row, WIN_MAX_W - 2 * PAD)
  local width = clamp(
    math.max(nameW + 2 * PAD + CLOSE_ROOM, textW + 2 * PAD, inviteW + copyW + GAP + 2 * PAD),
    WIN_MIN_W,
    WIN_MAX_W
  )
  local inner = width - 2 * PAD
  inviteW, copyW = buttonWidths(row, inner)
  -- The name sits in the title strip, as high as its lines (a very long name wraps, it is never cut).
  row.title:SetWidth(inner - CLOSE_ROOM + PAD)
  row.title:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -8)
  local nameH = math.max(lineHeight(row.measureTitle), row.title:GetStringHeight() or 0)
  local strip = math.max(30, math.ceil(nameH) + 16)
  row.shell.titleBar:SetHeight(strip)
  local line = lineHeight(row.measureUi)
  local y = strip + 8
  row.text:SetWidth(inner)
  row.text:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
  y = y + math.max(line, row.text:GetStringHeight() or 0) + GAP_ROWS
  row.detail:SetWidth(math.floor(inner * 0.45))
  row.detail:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
  row.hint:SetWidth(math.floor(inner * 0.55))
  row.hint:SetPoint("TOPRIGHT", c, "TOPRIGHT", -PAD, -y)
  row.hintLines = math.ceil(row.hint:GetStringHeight() or 0)
  y = y + math.max(line, row.hintLines) + GAP
  local btnH = math.max(28, math.ceil(line) + 12)
  for _, button in ipairs({ row.button, row.direct }) do
    button:SetPoint("TOPLEFT", c, "TOPLEFT", PAD, -y)
    resize(button, inviteW, btnH)
  end
  row.copy:SetPoint("TOPLEFT", c, "TOPLEFT", PAD + inviteW + GAP, -y)
  resize(row.copy, copyW, btnH)
  row.winClose:SetPoint("TOPRIGHT", row.shell.titleBar, "TOPRIGHT", -6, -6)
  y = y + btnH + 12
  row.width = width
  y = layoutFooter(row, y - 6) + 6
  f:SetSize(width, y)
end

local function layoutBar(row)
  local f, c = row.frame, row.content
  local hintText = row.hintWant or string.format(L["invite.prompt.hint"], "SHIFT+G")
  local hintW = textWidth(row.measureUi, hintText)
  local textW = textWidth(row.measureUi, string.format(L["invite.prompt.text"], row.name))
  local inviteW, copyW = buttonWidths(row, BAR_MAX_W)
  local fixed = 10 + 6 + hintW + 8 + copyW + GAP + inviteW + GAP + W.CLOSE_SIZE + 6
  -- The count of waiting requests and "close all" sit in the line, left of the key hint.
  local closeW = math.max(70, textWidth(row.measureUi, L["invite.prompt.closeAll"]) + BTN_PAD)
  local limit = math.min(BAR_MAX_W, screenWidth(Theme.windowScale()) or BAR_MAX_W)
  -- A hint with the count of the others gives way to the plain key when the line has no room for both.
  if row.hintShort and fixed + BAR_TEXT_ROOM > limit then
    hintText = row.hintShort
    fixed = fixed - hintW + textWidth(row.measureUi, hintText)
    hintW = textWidth(row.measureUi, hintText)
  end
  row.hint:SetText(row.hintWant and hintText or "")
  local moreW = row.footer and textWidth(row.measureUi, row.moreText or "") or 0
  -- Without room for a readable text the count steps back, "close all" stays.
  local inline = row.footer == true and fixed + closeW + 8 + BAR_TEXT_ROOM <= limit
  local showMore = inline and moreW > 0 and fixed + closeW + moreW + 16 + BAR_TEXT_ROOM <= limit
  if not showMore then
    moreW = 0
  end
  if inline then
    fixed = fixed + closeW + 8 + (showMore and moreW + 8 or 0)
  end
  local width = clamp(fixed + textW, math.min(BAR_MIN_W, limit), limit)
  -- A text wider than the room wraps onto a second line, the bar grows with it.
  row.text:SetWidth(width - fixed)
  local height = math.max(BAR_MIN_H, math.ceil(row.text:GetStringHeight() or 0) + 12)
  local btnH = math.max(24, math.ceil(lineHeight(row.measureUi)) + 8)
  -- No room in the line: "close all" gets a line of its own below, the line moves up by half of it.
  local below = row.footer == true and not inline
  local extra = below and (btnH + 6) or 0
  local dy = extra / 2
  height = height + extra
  row.barClose:SetPoint("RIGHT", c, "RIGHT", -6, dy)
  for _, button in ipairs({ row.button, row.direct }) do
    button:SetPoint("RIGHT", row.barClose, "LEFT", -GAP, 0)
    resize(button, inviteW, btnH)
  end
  row.copy:SetPoint("RIGHT", row.button, "LEFT", -GAP, 0)
  resize(row.copy, copyW, btnH)
  row.hint:SetWidth(hintW)
  row.hint:SetPoint("RIGHT", row.copy, "LEFT", -8, 0)
  row.more:SetShown(showMore)
  row.closeAll:SetShown(row.footer == true)
  if inline then
    row.closeAll:SetPoint("RIGHT", row.hint, "LEFT", -8, 0)
  elseif below then
    row.closeAll:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -6, 4)
  end
  if row.footer then
    resize(row.closeAll, closeW, btnH)
  end
  if showMore then
    row.more:SetWidth(moreW + 2)
    row.more:SetPoint("RIGHT", row.closeAll, "LEFT", -8, 0)
  end
  row.text:SetPoint("LEFT", c, "LEFT", 10, dy)
  f:SetSize(width, height)
  row.width = width
end

-- Arranges the parts of a row for a look. Out of combat only (it sizes the secure button).
function layout(row, style)
  row.layoutStyle = style
  local window = style == "window"
  row.frame:SetScale(Theme.windowScale())
  for _, part in ipairs(PARTS) do
    row[part]:ClearAllPoints()
  end
  row.close = window and row.winClose or row.barClose
  row.winDeco:SetShown(window)
  row.barDeco:SetShown(not window)
  row.winClose:SetShown(window)
  row.barClose:SetShown(not window)
  row.title:SetShown(window)
  row.detail:SetShown(window)
  row.track:SetShown(window)
  row.fill:SetShown(window)
  if window then
    layoutWindow(row)
  else
    layoutBar(row)
  end
end

local function paintTexts(row)
  if row.layoutStyle == "window" then
    W.SetText(row.title, nil, row.name)
    W.SetColor(row.title, readableClass(row.info.class, true) or "text")
    W.SetText(row.text, "invite.prompt.windowText")
    W.SetText(row.detail, nil, detailText(row.info))
  else
    W.SetText(row.text, nil, string.format(L["invite.prompt.text"], coloredName(row)))
  end
end

-- The countdown of the window: a thin bar that shrinks to nothing at the end of the lifetime.
local function paintBar(row, now)
  if row.layoutStyle ~= "window" or row.free then
    return
  end
  row.fill:SetWidth(math.max(1, ((row.width or WIN_MIN_W) - 2) * PL.Fraction(row.expires, now, row.lifetime)))
end

-- Rows -----------------------------------------------------------------------------------------

local function disarm(row)
  row.button:SetAttribute("type", nil)
  row.button:SetAttribute("macrotext", nil)
  row.name, row.key, row.expires, row.handlers, row.info, row.demo, row.id = nil, nil, nil, nil, nil, nil, nil
  row.direct:Show()
  row.hint:SetText("")
  row.hintWant, row.hintShort, row.footer, row.moreText = nil, nil, nil, nil
  stale[row] = nil
  row.free = true
end

local function release(row)
  if not row or row.free then
    return
  end
  row.closing = true
  row.frame:Hide()
  row.closing = nil
  if ns.InCombat() then
    stale[row] = true
    row.free = true
    row.pendingClear = true
  else
    disarm(row)
  end
  -- The next waiting request moves up: it shows, it never invites.
  pump()
  reflow()
  updateHints()
  ns.Emit("FG_INVITE_ROWS")
end

-- The player closed the request (x, Escape) or declined it: the wait of the sender starts again from now.
local function dismiss(row)
  if row.free then
    return
  end
  local h = row.handlers
  if not row.demo and h and h.closed then
    pcall(h.closed, row.name)
  end
  release(row)
end

-- The click of the normal button and of the confirmation key.
local function invoke(row)
  if row.free then
    return
  end
  if row.demo then
    ns.Notify(L["invite.prompt.demoNote"], "info")
    return
  end
  local h = row.handlers
  if not h then
    return
  end
  if ns.InCombat() then
    if h.combat then
      h.combat(row.name)
    end
    return
  end
  local status = h.invite and h.invite(row.name)
  if status == "sent" then
    release(row)
  elseif status == "blocked" then
    -- The secure button below takes the next click.
    row.direct:Hide()
    ns.Emit("FG_INVITE_ROWS")
  end
end

local function specialFrame(name)
  local list = rawget(_G, "UISpecialFrames")
  if type(list) == "table" then
    list[#list + 1] = name
  end
end

-- Window look: the shell of the other small windows around the content. Its drag is switched off, the
-- title strip only holds the name and the x.
local function buildWindowDeco(frame)
  local deco = CreateFrame("Frame", nil, frame)
  deco:SetAllPoints(frame)
  W.FadeWithWindow(W.Fill(deco, "bg", 0.97))
  local shell = ns.WindowShell.Attach(deco, { role = "h3", titleHeight = 30, band = false, fade = "main" })
  shell.titleBar:RegisterForDrag()
  shell.titleBar:SetScript("OnDragStart", nil)
  shell.titleBar:SetScript("OnDragStop", nil)
  shell.titleText:Hide()
  return deco, shell
end

-- The secure button wears the look of the "confirm" variant of the normal button above it, so the one that
-- takes over when the game blocks the normal call is the same button to the eye. Theme tokens only.
local function paintSecure(button)
  local v = W.ACTION_VARIANTS.confirm
  button.fgBg = button.fgBg or button:CreateTexture(nil, "BACKGROUND")
  button.fgBg:SetAllPoints()
  button.fgBorder = button.fgBorder or W.Border(button, v.border, v.borderAlpha)
  local function paint()
    button.fgBg:SetColorTexture(Theme.color(button.fgHover and v.bgHover or v.bg))
    button.fgBorder.set(v.border, v.borderAlpha)
    button.fgRing = button.fgRing or W.Border(button, "accent2", 1, 2)
    button.fgRing.show(Theme.accessibleMode())
  end
  ns.Bind(button, paint)
  button:HookScript("OnEnter", function()
    button.fgHover = true
    paint()
  end)
  button:HookScript("OnLeave", function()
    button.fgHover = false
    paint()
  end)
end

local function newRow()
  local index = #rows + 1
  local ok, frame = pcall(CreateFrame, "Frame", "ForeverGuidesInvite" .. index, UIParent)
  if not (ok and type(frame) == "table") then
    secureFailed = true
    return nil
  end
  local row = { frame = frame, free = true, index = index }
  frame:SetSize(BAR_MIN_W, BAR_MIN_H)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  row.barDeco = CreateFrame("Frame", nil, frame)
  row.barDeco:SetAllPoints(frame)
  W.FadeWithWindow(W.Fill(row.barDeco, "surface", 0.96))
  W.Border(row.barDeco, "accentDim", 0.7)
  -- Forever style: the stone of the other windows behind the bar, fading with the window opacity like the fill.
  ns.Bind(row.barDeco, function(deco)
    local rock = ns.Skins.Apply(deco, "rock")
    deco.fgBack:SetShown(rock == nil)
    if rock then
      W.FadeWithWindow(rock)
    end
  end)
  row.winDeco, row.shell = buildWindowDeco(frame)
  -- Everything the player reads or clicks lies above the shell and its edge.
  local c = CreateFrame("Frame", nil, frame)
  c:SetAllPoints(frame)
  if c.SetFrameLevel and row.winDeco.GetFrameLevel then
    c:SetFrameLevel(row.winDeco:GetFrameLevel() + (ns.WindowShell.EDGE_LEVEL or 100) + 10)
  end
  row.content = c
  local okB, button =
    pcall(CreateFrame, "Button", "ForeverGuidesInviteSecure" .. index, c, "SecureActionButtonTemplate")
  if not (okB and type(button) == "table") then
    secureFailed = true
    return nil
  end
  row.button = button
  specialFrame("ForeverGuidesInvite" .. index)
  -- Escape hides the frame; the request ends with it.
  frame:SetScript("OnHide", function()
    if not row.free and not row.closing then
      dismiss(row)
    end
  end)
  row.track = c:CreateTexture(nil, "ARTWORK")
  ns.Bind(row.track, function(t)
    t:SetColorTexture(Theme.color("textMuted", 0.3))
  end)
  row.track:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 1, 1)
  row.track:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
  row.track:SetHeight(3)
  row.fill = c:CreateTexture(nil, "OVERLAY")
  row.fill:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 1, 1)
  row.fill:SetHeight(3)
  ns.Bind(row.fill, function(t)
    t:SetColorTexture(Theme.color("accent2"))
  end)
  row.text = W.Text(c, { role = "ui", color = "text", wrap = true })
  row.title = W.Text(c, { role = "h3", color = "text", wrap = true })
  row.detail = W.Text(c, { role = "ui", color = "textSecondary" })
  row.hint = W.Text(c, { role = "micro", color = "textMuted", justify = "RIGHT" })
  -- Hidden texts without a box: the width a text needs, whatever the font size of the player.
  row.more = W.Text(c, { role = "micro", color = "textMuted" })
  row.closeAll = W.Button(c, {
    key = "invite.prompt.closeAll",
    width = 70,
    height = 20,
    onClick = function()
      P.CloseAll()
    end,
  })
  row.more:Hide()
  row.closeAll:Hide()
  row.measureUi = W.Text(c, { role = "ui" })
  row.measureTitle = W.Text(c, { role = "h3" })
  row.measureUi:Hide()
  row.measureTitle:Hide()
  local function onClose()
    dismiss(row)
  end
  row.barClose = W.CloseButton(c, { onClick = onClose })
  row.winClose = W.Action(
    row.shell.titleBar,
    { icon = "close", size = 20, boxed = true, tooltip = "common.close", onClick = onClose }
  )
  row.close = row.barClose
  button:SetSize(BTN_MIN_W, 24)
  button:RegisterForClicks("AnyUp", "AnyDown")
  paintSecure(button)
  row.buttonText = W.Text(button, { key = "invite.prompt.button", role = "ui", color = "text", justify = "CENTER" })
  row.buttonText:SetPoint("CENTER")
  row.copy = W.Button(c, {
    key = "invite.prompt.copy",
    width = BTN_MIN_W,
    height = 24,
    onClick = function()
      P.OpenCopy(row.name)
    end,
  })
  -- The normal button sits on top of the secure one and hides itself when the game blocks its call.
  row.direct = W.Button(c, {
    key = "invite.prompt.button",
    variant = "confirm",
    width = BTN_MIN_W,
    height = 24,
    onClick = function()
      invoke(row)
    end,
  })
  if row.direct.SetFrameLevel and button.GetFrameLevel then
    row.direct:SetFrameLevel(button:GetFrameLevel() + 5)
  end
  -- A key press clicks this one (InviteKey.lua binds it); it is always shown, so the click works in every look.
  local okK, proxy = pcall(CreateFrame, "Button", "ForeverGuidesInviteKey" .. index, UIParent)
  if okK and type(proxy) == "table" then
    proxy:SetSize(1, 1)
    proxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    proxy:EnableMouse(false)
    proxy:SetAlpha(0)
    proxy:SetScript(
      "OnClick",
      ns.Wrap("invite-key", function()
        invoke(row)
      end)
    )
    row.proxy = proxy
  end
  -- Our code runs after the secure click and never changes what the click does.
  button:HookScript("PostClick", function()
    -- The macro stops itself in combat: nothing was sent, the button stays armed for another click.
    if ns.InCombat() or row.free or row.demo then
      return
    end
    local h, name = row.handlers, row.name
    release(row)
    if h and h.sent then
      h.sent(name)
    end
  end)
  frame:Hide()
  rows[#rows + 1] = row
  return row
end

local function takeRow()
  for _, row in ipairs(rows) do
    if row.free and not row.pendingClear then
      return row
    end
  end
  if not secureFailed and #rows < P.MAX_ROWS + DEMO_ROWS then
    return newRow()
  end
end

local function find(key)
  for _, row in ipairs(rows) do
    if not row.free and row.key == key then
      return row
    end
  end
end

-- Driver ------------------------------------------------------------------------------------------

local function refreshDriver()
  if driver or not rawget(_G, "CreateFrame") then
    return
  end
  driver = CreateFrame("Frame")
  driver:SetScript("OnUpdate", function(_, elapsed)
    sinceTick = sinceTick + (tonumber(elapsed) or 0)
    if sinceTick >= TICK then
      sinceTick = 0
      P.Tick()
    end
  end)
end

-- Over a window pinned to the top strata (the main window raised over a Blizzard view) the request goes to
-- that strata too, so the demo of the settings is never hidden behind its own window. Out of combat only.
local function lift(row)
  local f = row.frame
  f:SetFrameStrata(ns.TopLayer.Active() and "TOOLTIP" or "DIALOG")
  ns.TopLayer.Over(f, ns.TopLayer.DIALOG)
end

-- Shows a request now. Out of combat only. spec: name, handlers, info, style, demo.
local function open(row, spec)
  nextId = nextId + 1
  row.free, row.pendingClear = false, nil
  row.id, row.name, row.handlers, row.info = nextId, spec.name, spec.handlers, spec.info or {}
  row.demo = spec.demo == true or nil
  row.key = row.demo and ("demo:" .. nextId) or PN.Key(spec.name)
  row.lifetime = row.demo and DEMO_LIFETIME or P.LIFETIME
  row.expires = clock() + row.lifetime
  if row.demo then
    row.button:SetAttribute("type", nil)
    row.button:SetAttribute("macrotext", nil)
  else
    row.button:SetAttribute("type", "macro")
    row.button:SetAttribute("macrotext", P.MacroText(spec.name))
  end
  row.direct:Show()
  row.layoutStyle = spec.style
  paintTexts(row)
  layout(row, spec.style)
  reflow()
  lift(row)
  row.frame:Show()
  paintBar(row, clock())
  refreshDriver()
  ns.Emit("FG_INVITE_ROWS")
end

-- A request that has no room yet waits unseen, oldest first. Past MAX_WAITING the oldest falls out; the chat is told
-- once per overflow.
local function enqueue(name, key, handlers, info)
  while #waiting >= P.MAX_WAITING do
    table.remove(waiting, 1)
    if not overflowed then
      overflowed = true
      if ns.Notify and ns.Notify.chat then
        ns.Notify.chat(string.format(L["invite.prompt.overflow"], P.MAX_WAITING))
      end
    end
  end
  waiting[#waiting + 1] = { name = name, key = key, handlers = handlers, info = info }
  if inCombat() then
    needReflow = true
  else
    reflow()
  end
  updateHints()
end

-- A waiting request that has room now takes a row. Out of combat only.
pump = function()
  if inCombat() or closingAll then
    return
  end
  while #waiting > 0 and openCount(false) < P.MAX_ROWS do
    local row = takeRow()
    if not row then
      break
    end
    local q = table.remove(waiting, 1)
    open(row, { name = q.name, handlers = q.handlers, info = q.info, style = P.Style() })
  end
  if #waiting == 0 then
    overflowed = false
  end
end

local function arm(name, key, handlers, info)
  local existing = find(key)
  if existing then
    existing.expires = clock() + existing.lifetime
    return "ready"
  end
  for _, q in ipairs(waiting) do
    if q.key == key then
      return "queued"
    end
  end
  local row = openCount(false) < P.MAX_ROWS and takeRow()
  if row then
    open(row, { name = name, handlers = handlers, info = info, style = P.Style() })
    return "ready"
  end
  if secureFailed then
    return false, "no-api"
  end
  enqueue(name, key, handlers, info)
  return "queued"
end

-- Asks the player to invite `name` to the guild. Answers "ready" (shown), "waiting" (combat, shown when it ends),
-- "queued" (all rows are taken, it waits its turn) or false and "no-api" / "unsafe-name". handlers: invite(name)
-- -> "sent" | "blocked" | false (the click of the normal button), combat(name) (a click in combat), sent(name)
-- (after the click of the secure button), closed(name) (declined or closed). info (optional): class (token),
-- className, level.
function P.Request(name, handlers, info)
  if not safeName(name) then
    return false, "unsafe-name"
  end
  local key = PN.Key(name)
  if inCombat() then
    local existing = find(key)
    if existing then
      return "ready"
    end
    for _, q in ipairs(waiting) do
      if q.key == key then
        return "waiting"
      end
    end
    enqueue(name, key, handlers, info)
    return "waiting"
  end
  return arm(name, key, handlers, info)
end

-- Drops requests that waited too long. Out of combat only for the attributes, the frame hides at once.
function P.Tick()
  local now = clock()
  for _, row in ipairs(rows) do
    if not row.free then
      if row.expires and now >= row.expires then
        release(row)
      else
        paintBar(row, now)
      end
    end
  end
  if ns.InviteKey and ns.InviteKey.Poll then
    ns.InviteKey.Poll()
  end
end

-- The open real requests, oldest first.
function P.Rows()
  local out = {}
  for _, row in ipairs(ordered()) do
    if not row.demo then
      out[#out + 1] = row
    end
  end
  return out
end

-- Requests that wait for a free row (or for the end of the combat).
function P.Waiting()
  return #waiting
end

-- "Close all": every open request closes and the line is emptied; each sender waits again from now on.
function P.CloseAll()
  closingAll = true
  for _, row in ipairs(rows) do
    if not row.free and not row.demo then
      dismiss(row)
    end
  end
  local list = waiting
  waiting, overflowed = {}, false
  for _, q in ipairs(list) do
    local h = q.handlers
    if h and h.closed then
      pcall(h.closed, q.name)
    end
  end
  closingAll = false
  reflow()
  updateHints()
  ns.Emit("FG_INVITE_ROWS")
end

-- The request a confirmation key invites: the oldest open real one.
function P.First()
  return P.Rows()[1]
end

-- Name of the button a key press clicks for this row: the normal button, the secure one when the game
-- blocked the normal call.
function P.KeyTarget(row)
  if row.direct:IsShown() and row.proxy then
    return row.proxy:GetName()
  end
  return row.button:GetName()
end

-- Shows "Key Y" on one row (nil label or row clears every hint).
function P.SetHint(label, target)
  hintLabel, hintRow = label, target
  updateHints()
end

-- Demo ----------------------------------------------------------------------------------------------

-- Shows invented requests, one per look in `styles` (a list of "window" or "bar"). Nothing is sent, a
-- click only says so, and the demo closes by itself after DEMO_LIFETIME seconds.
function P.ShowDemo(styles)
  P.HideDemo()
  if inCombat() then
    return false, "combat"
  end
  local shown = 0
  for _, style in ipairs(styles) do
    local row = openCount(true) < DEMO_ROWS and takeRow()
    if row then
      open(row, {
        name = DEMO_NAME,
        demo = true,
        style = PL.CleanStyle(style),
        info = { class = "WARRIOR", className = L["invite.prompt.demoClass"], level = 60 },
        handlers = {},
      })
      shown = shown + 1
    end
  end
  return shown
end

function P.HideDemo()
  for _, row in ipairs(rows) do
    if not row.free and row.demo then
      release(row)
    end
  end
end

function P.DemoRows()
  local out = {}
  for _, row in ipairs(rows) do
    if not row.free and row.demo then
      out[#out + 1] = row
    end
  end
  return out
end

-- A change of style, color theme, accent, contrast mode or language restyles the open requests: the class
-- colors depend on the surface, the rest follows through ns.Bind.
ns.On("FG_UI_REFRESHED", function()
  for _, row in ipairs(rows) do
    if not row.free and row.layoutStyle then
      paintTexts(row)
    end
  end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  for row in pairs(stale) do
    disarm(row)
    row.pendingClear = nil
  end
  if needReflow then
    reflow()
  end
  pump()
  reflow()
  updateHints()
end)
