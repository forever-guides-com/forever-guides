-- Side panel that hangs flush at the right edge of a Blizzard window, over its whole height: a header row
-- with a chevron, the title and a state word, and below it the content of the caller. Collapsed it is a thin
-- strip with the chevron on top and the title as one word turned 90 degrees (stacked letters
-- where the client cannot turn text); a click anywhere on the strip
-- opens it. The open state is saved per character (default charDB.sidePanelOpen[key]). Without room right of
-- the host the panel goes inside the right edge as an overlay (or to the left edge, opts.fallback = "left").
-- Used by the talent window (TalentFrameOrder), the world map (WorldMapRoutePanel) and the spellbook
-- (SpellbookSide). The panel is our own child frame of the host and never writes a field onto it. It is only
-- built while the client lets this add-on touch the host (ns.ProtectedAllowed); a toggle the client refuses
-- in combat is answered with ns.CombatBlocked and never queued.
local _, ns = ...
local W, L, Theme, K = ns.W, ns.L, ns.Theme, ns.PageKit

local SP = {}
ns.SidePanel = SP

SP.WIDTH = 300
SP.BAR_WIDTH = 28
SP.ROOM = 52 -- room right of the panel that stays free for the side tab of the add-on
local HEADER_H, CHEVRON, STRIP_TOP, LETTER_H, SPACE_H = 28, 12, 8, 14, 8
local ICON, NUM_W = 22, 26

ns.AddLocale("enUS", {
  ["sidepanel.open"] = "expanded",
})
ns.AddLocale("deDE", {
  ["sidepanel.open"] = "aufgeklappt",
})

local panels = {}

-- Compact dark list row: number, spell icon, title and a second line, a thin line below, a mark bar at the
-- left edge. `makeTail(row)` (optional) returns a frame that sits at the right edge; the texts end before it.
function SP.Row(parent, makeTail)
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
  row.num:SetWidth(NUM_W)
  row.spell = row:CreateTexture(nil, "ARTWORK")
  row.spell:SetSize(ICON, ICON)
  row.spell:SetPoint("LEFT", 38, 0)
  row.spell:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local rel, relPoint, gap = row, "RIGHT", -8
  if makeTail then
    row.tail = makeTail(row)
    row.tail:SetPoint("RIGHT", -8, 0)
    rel, relPoint, gap = row.tail, "LEFT", -6
  end
  row.title = W.Text(row, { role = "ui" })
  row.title:SetPoint("TOPLEFT", row.spell, "TOPRIGHT", 8, 3)
  row.title:SetPoint("RIGHT", rel, relPoint, gap, 0)
  row.sub = W.Text(row, { role = "small", color = "textSecondary" })
  row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
  row.sub:SetPoint("RIGHT", rel, relPoint, gap, 0)
  return row
end

-- Colors of a row: selected while `lit`, hover look under the pointer, the mark bar while `marked`.
function SP.PaintRow(row, lit, marked)
  row.bg:SetColorTexture(Theme.fillColor(lit and "selected" or (row.hover and "hover" or nil)))
  row.mark:SetColorTexture(Theme.color("accent"))
  row.mark:SetShown(marked == true)
  row.line:SetColorTexture(Theme.fillColor("line"))
end

-- One entry per character of the title (a space is "", a gap in the strip), capitals for a calm column.
function SP.Letters(text)
  local out = {}
  for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    out[#out + 1] = ch == " " and "" or ch:upper()
  end
  return out
end

-- Outside the host while the panel and the room for the side tab fit on the screen and the host is not
-- maximised, else inside. Returns inside and how far the host reaches past the screen (host units), the
-- overlay moves in by that. Absolute coordinates (scale applied); unknown geometry counts as fitting.
function SP.Placement(hostRight, hostScale, screenRight, need, maximized)
  if not (hostRight and hostScale and screenRight) then
    return maximized == true, 0
  end
  local over = hostRight * hostScale - screenRight
  return maximized == true or over + need > 0, math.max(0, over / hostScale)
end

local function number(obj, method)
  if not obj or type(obj[method]) ~= "function" then
    return nil
  end
  local ok, value = pcall(obj[method], obj)
  local secret = rawget(_G, "issecretvalue")
  if not ok or type(value) ~= "number" or (type(secret) == "function" and secret(value)) then
    return nil
  end
  return value
end

local function maximized(host)
  if type(host.IsMaximized) ~= "function" then
    return false
  end
  local ok, value = pcall(host.IsMaximized, host)
  return ok and value == true
end

local function readPath(path)
  local node = ns.charDB
  for part in path:gmatch("[^.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = node[part]
  end
  return node
end

local function titleOf(p)
  local text = p.titleText or p.opts.title
  if type(text) == "function" then
    text = text()
  end
  return text or ""
end

local function stripOf(p)
  local text = p.stripText or p.opts.strip
  if type(text) == "function" then
    text = text()
  end
  return text or titleOf(p)
end

function SP.Get(key)
  return panels[key]
end

-- Which way the strip title can be turned: FontString:SetRotation where the client has it, else a held
-- Rotation animation, nil when neither exists (stacked letters then).
function SP.RotationMode(fs)
  if type(fs.SetRotation) == "function" then
    return "rotation"
  end
  if type(fs.CreateAnimationGroup) == "function" then
    return "animation"
  end
  return nil
end

-- The title as one word turned 90 degrees (reads bottom to top), centered in the strip below the chevron.
local function paintRotated(p, open, mode, height)
  local fs = p.strip
  fs:SetShown(not open)
  if open then
    if p.stripAnim then
      p.stripAnim:Stop()
    end
    return
  end
  local text = stripOf(p)
  fs:SetText(text)
  local room = height and height - 2 * K.scaledHeight(STRIP_TOP + CHEVRON + STRIP_TOP)
  local want = fs:GetStringWidth()
  fs:SetWidth(room and math.max(1, math.min(want, room)) or want)
  -- A fixed line box keeps the turned text centered across the strip instead of riding on its descender space.
  local line = K.scaledHeight(LETTER_H)
  fs:SetHeight(line)
  fs:ClearAllPoints()
  -- Text turned by SetRotation sits about half a line right of its anchor in the client; the animation turns
  -- about the center (origin set below).
  fs:SetPoint("CENTER", p.header, "CENTER", mode == "rotation" and -line / 2 or 0, 0)
  if mode == "rotation" then
    fs:SetRotation(math.pi / 2)
  else
    local group = p.stripAnim
    if not group then
      group = fs:CreateAnimationGroup()
      local turn = group:CreateAnimation("Rotation")
      turn:SetDegrees(90)
      turn:SetDuration(0.001)
      turn:SetEndDelay(3600) -- the end delay holds the turn
      turn:SetOrigin("CENTER", 0, 0)
      group:SetLooping("REPEAT")
      p.stripAnim = group
    end
    if not group:IsPlaying() then
      group:Play()
    end
  end
  p.stripShown = #SP.Letters(text)
end

-- Letters of the collapsed strip, the last fallback: one font string per character at a fixed pitch from the
-- top, so the column is the same in every client. What does not fit into the height of the host stays out.
local function paintLetters(p, open, height)
  local letters = p.letters
  local pitch, space = K.scaledHeight(LETTER_H), K.scaledHeight(SPACE_H)
  local y = STRIP_TOP + CHEVRON + STRIP_TOP
  local chars = SP.Letters(stripOf(p))
  p.stripShown = 0
  for i, ch in ipairs(chars) do
    local fs = letters[i]
    if not fs then
      fs = W.Text(p.header, { role = "small", color = "textSecondary", justify = "CENTER" })
      fs:SetWidth(SP.BAR_WIDTH)
      letters[i] = fs
    end
    local step = ch == "" and space or pitch
    local fits = not open and (height == nil or y + step + STRIP_TOP <= height)
    fs:SetShown(fits and ch ~= "")
    if fits then
      fs:SetText(ch)
      fs:SetHeight(pitch)
      fs:ClearAllPoints()
      fs:SetPoint("TOP", p.header, "TOP", 0, -y)
      if ch ~= "" then
        p.stripShown = p.stripShown + 1
      end
    end
    y = y + step
  end
  for i = #chars + 1, #letters do
    letters[i]:Hide()
  end
end

local function paintStrip(p, open)
  local height = number(p.host, "GetHeight")
  if not p.strip then
    p.strip = W.Text(p.header, { role = "small", color = "textSecondary", justify = "CENTER" })
    p.strip:SetWordWrap(false)
  end
  local mode = SP.RotationMode(p.strip)
  if mode then
    paintLetters(p, true, height) -- hides the letters of an earlier fallback
    paintRotated(p, open, mode, height)
  else
    p.strip:Hide()
    paintLetters(p, open, height)
  end
end

-- Right edge: the strip shows ">", the open panel "<". Mirrored to the left edge it is the other way round.
local function chevronOf(p, open)
  local toRight = open == (p.mode == "left")
  return toRight and "chevron-right" or "chevron-left"
end

function SP.IsOpen(p)
  return readPath(p.store) == true
end

-- Width of the panel in its state.
local function widthOf(p)
  return SP.IsOpen(p) and p.opts.width or SP.BAR_WIDTH
end

-- Directly at the edge of the host over its whole height. Returns the mode: "right" (outside), "inside"
-- (overlay at the inside of the right edge) or "left" (fallback = "left").
local function place(p)
  local host = p.host
  local ui = UIParent
  local screenRight = number(ui, "GetRight")
  screenRight = screenRight and screenRight * (number(ui, "GetEffectiveScale") or 1)
  local scale = number(host, "GetEffectiveScale") or 1
  local need = (widthOf(p) + (p.opts.room or SP.ROOM)) * scale
  local inside, over = SP.Placement(number(host, "GetRight"), scale, screenRight, need, maximized(host))
  -- Outside the host the panel spans its whole height; the insets only keep the overlay inside clear of corners.
  local low, top = 0, 0
  if inside and p.opts.fallback ~= "left" then
    low, top = p.opts.insetBottom or 0, p.opts.insetTop
    top = type(top) == "function" and top() or top or 0
  end
  p:ClearAllPoints()
  if not inside then
    p.mode = "right"
    p:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, 0)
    p:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", 0, 0)
  elseif p.opts.fallback == "left" then
    p.mode = "left"
    p:SetPoint("TOPRIGHT", host, "TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", host, "BOTTOMLEFT", 0, 0)
  else
    p.mode = "inside"
    p:SetPoint("TOPRIGHT", host, "TOPRIGHT", -over, -top)
    p:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -over, low)
  end
  if p.opts.lift then
    p.opts.lift(p)
  else
    ns.Layer.SetTreeLevel(p, math.min((number(host, "GetFrameLevel") or 0) + 20, ns.Layer.CAP))
  end
  return p.mode
end

-- Lays the panel out for its state: a strip (collapsed) or the header and the body (expanded).
local function layout(p)
  local open = SP.IsOpen(p)
  local header = p.header
  p:SetWidth(widthOf(p))
  header:ClearAllPoints()
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  p.chevron:ClearAllPoints()
  p.chevron:SetIcon(chevronOf(p, open))
  p.label:SetText(titleOf(p))
  p.label:SetShown(open)
  p.state:SetText(L["sidepanel.open"])
  p.state:SetShown(open)
  p.body:SetShown(open)
  if open then
    header:SetHeight(K.scaledHeight(HEADER_H))
    p.chevron:SetPoint("LEFT", 8, 0)
  else
    header:SetPoint("BOTTOMLEFT")
    header:SetPoint("BOTTOMRIGHT")
    p.chevron:SetPoint("TOP", 0, -STRIP_TOP)
  end
  paintStrip(p, open)
  if p.opts.onLayout then
    p.opts.onLayout(p, open)
  end
end

-- Anchors and lays out again (the host moved, the language changed, the title has a new text).
function SP.Refresh(p)
  place(p)
  layout(p)
  -- The gear handle of the window looks for a spot clear of what hangs at its edge (Modules/FrameTweaksBar.lua).
  local bar, name = ns.FrameTweaksBar, p.host.GetName and p.host:GetName()
  if bar and name then
    bar.Invalidate(name)
    bar.Refresh(name)
  end
end

-- Opens or closes the panel (nil toggles). Refused while the client holds the host protected.
function SP.SetOpen(p, open)
  if open == nil then
    open = not SP.IsOpen(p)
  end
  if not ns.ProtectedAllowed(p.host) then
    ns.CombatBlocked()
    return false
  end
  ns.Store.setChar(p.store, open and true or false)
  SP.Refresh(p)
  if p.opts.onToggle then
    p.opts.onToggle(open and true or false)
  end
  return true
end

-- opts: key (state and registry), title (text or function), strip (text or function for the letters, default
-- the title), tip (locale key of the header tooltip), width (default SP.WIDTH), store (path in charDB, default
-- sidePanelOpen.<key>), insetTop and insetBottom (px or function: only for the overlay inside the host, it stays that far below the top and above the bottom edge, default flush), parent (the frame it is a child of, default the host: shows and hides with it), fallback ("inside", default, or "left"), room (px kept free at the right, default
-- SP.ROOM), lift(panel) (own frame level, default above the host), build(content, panel) (called once),
-- onLayout(panel, open), onToggle(open). Returns the panel frame, nil while the host is protected.
-- Fields: header (the button), chevron, label, state, body, mode ("right" | "inside" | "left"), letters.
function SP.Attach(host, opts)
  local known = panels[opts.key]
  if known and known.host == host then
    return known
  end
  if not ns.ProtectedAllowed(host) then
    return nil
  end
  opts.width = opts.width or SP.WIDTH
  local p = CreateFrame("Frame", nil, opts.parent or host)
  ns.Layer.Own(p)
  p:EnableMouse(true)
  W.Fill(p, "surface", 1)
  W.Border(p, "white")
  p.host, p.opts, p.letters = host, opts, {}
  p.store = opts.store or ("sidePanelOpen." .. opts.key)

  local header = CreateFrame("Button", nil, p)
  W.Fill(header, "surface2")
  p.header = header
  p.chevron = W.Glyph(header, "chevron-right", CHEVRON, "textSecondary")
  p.state = W.Text(header, { role = "small", color = "textSecondary" })
  p.state:SetPoint("RIGHT", -8, 0)
  p.label = W.Text(header, { role = "ui", color = "text" })
  p.label:SetPoint("LEFT", p.chevron, "RIGHT", 6, 0)
  p.label:SetPoint("RIGHT", p.state, "LEFT", -6, 0)
  header.fgName = function()
    return titleOf(p)
  end
  header:SetScript("OnClick", function()
    SP.SetOpen(p)
  end)
  header:SetScript("OnEnter", function(self)
    ns.ShowTooltip(self, titleOf(p), opts.tip and L[opts.tip] or nil)
  end)
  header:SetScript("OnLeave", ns.HideTooltip)
  header:HookScript("OnShow", function()
    if p.stripAnim and not SP.IsOpen(p) and not p.stripAnim:IsPlaying() then
      p.stripAnim:Play()
    end
  end)
  ns.Focus.register(header, function()
    SP.SetOpen(p)
  end)
  function header:fgArrow(step)
    if (step > 0) ~= SP.IsOpen(p) then
      SP.SetOpen(p, step > 0)
    end
  end

  p.body = CreateFrame("Frame", nil, p)
  p.body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
  p.body:SetPoint("BOTTOMRIGHT")

  function p:SetTitle(text, strip)
    self.titleText, self.stripText = text, strip
  end
  function p:IsOpen()
    return SP.IsOpen(self)
  end
  function p:SetOpen(open)
    return SP.SetOpen(self, open)
  end
  function p:Refresh()
    SP.Refresh(self)
  end

  panels[opts.key] = p
  if opts.build then
    opts.build(p.body, p)
  end
  SP.Refresh(p)
  return p
end
