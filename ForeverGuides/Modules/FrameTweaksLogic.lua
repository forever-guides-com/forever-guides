-- Pure part of the window tweaks (Modules/FrameTweaks.lua): which Blizzard windows are handled,
-- the saved position format, keeping a window on screen and the combat queue. No game calls here.
--
-- Saved data per frame name (ns.db.settings.frames[name]):
--   { p = point, r = relative frame name, rp = relative point, x = offset, y = offset, scale = zoom,
--     alpha = background opacity in percent }
-- with offsets rounded to one decimal; scale (0.5 to 2) and alpha (0 to 100) are optional and may
-- stand alone.
local _, ns = ...

local FT = {}
ns.FrameTweaksLogic = FT

-- Pixels of a window that always stay on screen.
FT.MIN_VISIBLE = 40
FT.MAX_OFFSET = 20000

-- Horizontal and vertical position of an anchor point inside a frame (0 = left/bottom, 1 = right/top).
local AX = {
  TOPLEFT = 0,
  LEFT = 0,
  BOTTOMLEFT = 0,
  TOP = 0.5,
  CENTER = 0.5,
  BOTTOM = 0.5,
  TOPRIGHT = 1,
  RIGHT = 1,
  BOTTOMRIGHT = 1,
}
local AY = {
  BOTTOMLEFT = 0,
  BOTTOM = 0,
  BOTTOMRIGHT = 0,
  LEFT = 0.5,
  CENTER = 0.5,
  RIGHT = 0.5,
  TOPLEFT = 1,
  TOP = 1,
  TOPRIGHT = 1,
}

-- Windows measured in the client (docs/FENSTER-ANPASSEN.md), movable or not: the client positions
-- the not movable ones itself, they are made movable. Others are found at run time (panel table,
-- UISpecialFrames, signature scan).
FT.DEFAULT = {
  "CharacterFrame",
  "BankFrame",
  "CommunitiesFrame",
  "FriendsFrame",
  "GossipFrame",
  "QuestFrame",
  "MerchantFrame",
  "TaxiFrame",
  "TradeFrame",
  "ItemTextFrame",
  "PetStableFrame",
  "RaidParentFrame",
  "SettingsPanel",
  "ContainerFrameCombinedBags",
  "PlayerSpellsFrame",
  "ProfessionsFrame",
  "WorldMapFrame",
  "MailFrame",
  "DressUpFrame",
  "HelpFrame",
  "ChatConfigFrame",
  "LFGParentFrame",
  "AddonList",
  "PVEFrame",
}
for i = 1, 13 do
  FT.DEFAULT[#FT.DEFAULT + 1] = "ContainerFrame" .. i
end

-- Frames that must not be touched in combat, whatever IsProtected says.
FT.PROTECTED = { PlayerSpellsFrame = true, ProfessionsFrame = true }

-- Never handled: windows we hang on to ourselves, system dialogs, chat, action bars and unit frames.
FT.EXCLUDED = {
  FlightMapFrame = true,
  GameMenuFrame = true,
  LootFrame = true,
  CinematicFrame = true,
  MovieFrame = true,
  EditModeManagerFrame = true,
  TalkingHeadFrame = true,
  UIParent = true,
  WorldFrame = true,
}
-- Popups, dialogs and tutorials of the client: they look like windows and are none. A window the
-- player added by hand skips these (the soft rules), never the hard ones above and below.
FT.SOFT = {
  ColorPickerFrame = true,
  EditModeSystemSettingsDialog = true,
  CreateChannelPopup = true,
  RolePollPopup = true,
  PingSystemTutorial = true,
  QuickJoinRoleSelectionFrame = true,
  ModelPreviewFrame = true,
}
-- Parts of a name that mark a tooltip, a tutorial or a popup; endings that mark a tab.
FT.SOFT_PARTS = { "Tooltip", "Tutorial", "Popup" }
FT.SOFT_ENDINGS = { "Tab%d*$", "TabButton%d*$" }

FT.EXCLUDED_PREFIX = {
  "ForeverGuides",
  "FG",
  "ChatFrame",
  "FloatingChatFrame",
  "GeneralDockManager",
  "MainMenuBar",
  "MainActionBar",
  "MultiBar",
  "ActionBar",
  "OverrideActionBar",
  "StanceBar",
  "PetActionBar",
  "MicroMenu",
  "BagBar",
  "PlayerFrame",
  "TargetFrame",
  "FocusFrame",
  "PartyFrame",
  "BossTargetFrame",
  "CompactRaidFrame",
  "CompactPartyFrame",
  "NamePlate",
  "Minimap",
  "BuffFrame",
  "DebuffFrame",
  "ObjectiveTracker",
  "StaticPopup",
  "DropDownList",
  "GameTooltip",
  "ShoppingTooltip",
  "ItemRefTooltip",
  "BNToast",
}

-- Frame keys that hold a window's title strip, tried in this order, on the window and on its
-- BorderFrame (world map).
FT.DRAG_KEYS = { "TitleContainer", "TitleBar", "Header", "DragBar" }

-- Windows whose body is not a drag surface (map clicks stay map clicks): only a title strip drags.
FT.STRIP_ONLY = { WorldMapFrame = true }

-- Windows that have two layouts and keep one position for each.
FT.MAXIMIZABLE = { WorldMapFrame = true }

-- Windows whose zoom needs a switch (settings.frameMapZoom); moving and the bar always work.
FT.BAR_OPT_IN = { WorldMapFrame = true }

-- Drag handle over the top of a window: height, space kept free at the right (close and maximize
-- buttons) and level above the window's own. Windows with more at the left or right of the strip.
FT.HANDLE_HEIGHT, FT.HANDLE_RIGHT, FT.HANDLE_LEVEL = 26, 40, 3
local HANDLE_INSETS = { WorldMapFrame = { 0, 80 } }
for _, name in ipairs(FT.DEFAULT) do
  if name:find("^ContainerFrame") then
    HANDLE_INSETS[name] = { 40, FT.HANDLE_RIGHT }
  end
end

-- Space (left, right) the handle of a window leaves free.
function FT.HandleInsets(name)
  local inset = HANDLE_INSETS[name]
  return inset and inset[1] or 0, inset and inset[2] or FT.HANDLE_RIGHT
end

-- Key of the saved entry: the maximized world map has its own position.
function FT.StateKey(name, maximized)
  if maximized and FT.MAXIMIZABLE[name] then
    return name .. ":max"
  end
  return name
end

local defaultSet = {}
for _, name in ipairs(FT.DEFAULT) do
  defaultSet[name] = true
end

local function hardExcluded(name)
  if type(name) ~= "string" or name == "" or FT.EXCLUDED[name] then
    return true
  end
  for _, prefix in ipairs(FT.EXCLUDED_PREFIX) do
    if name:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

local function softExcluded(name)
  if FT.SOFT[name] then
    return true
  end
  for _, part in ipairs(FT.SOFT_PARTS) do
    if name:find(part, 1, true) then
      return true
    end
  end
  for _, ending in ipairs(FT.SOFT_ENDINGS) do
    if name:find(ending) then
      return true
    end
  end
  return false
end

-- added: the player chose the window, only the hard rules count.
function FT.Excluded(name, added)
  if hardExcluded(name) then
    return true
  end
  return not added and softExcluded(name)
end

-- A tooltip is never a window, whatever its name is.
function FT.StrataExcluded(strata)
  return strata == "TOOLTIP"
end

function FT.Protected(name)
  return FT.PROTECTED[name] == true
end

-- Is this window handled? Every window of the lists and every detected one, minus the excluded.
function FT.Wanted(name, added)
  return not FT.Excluded(name, added)
end

-- A window of the fixed list (the others are "auto" in the list command).
function FT.Listed(name)
  return defaultSet[name] == true
end

-- Default windows, the names of the client's panel table, more names (UISpecialFrames) and the
-- windows the player added, without excluded ones (sorted, unique).
function FT.Names(panelNames, moreNames, addedNames)
  local seen, out = {}, {}
  local function add(name, added)
    if not seen[name] and not FT.Excluded(name, added) then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  for _, name in ipairs(FT.DEFAULT) do
    add(name)
  end
  for _, name in ipairs(panelNames or {}) do
    add(name)
  end
  for _, name in ipairs(moreNames or {}) do
    add(name)
  end
  for _, name in ipairs(addedNames or {}) do
    add(name, true)
  end
  table.sort(out)
  return out
end

-- Position data ----------------------------------------------------------------------------------

function FT.Round(n)
  return math.floor(n * 10 + 0.5) / 10
end

local function offset(v)
  if type(v) ~= "number" or v ~= v or math.abs(v) > FT.MAX_OFFSET then
    return nil
  end
  return FT.Round(v)
end

-- Zoom -------------------------------------------------------------------------------------------

FT.SCALE_MIN, FT.SCALE_MAX, FT.SCALE_STEP = 0.5, 2, 0.05

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function hundredth(v)
  return math.floor(v * 100 + 0.5) / 100
end

-- A zoom inside the limits, nil for anything that is not a number.
function FT.CleanScale(v)
  if not finite(v) then
    return nil
  end
  return math.max(FT.SCALE_MIN, math.min(FT.SCALE_MAX, hundredth(v)))
end

-- The nearest multiple of the step.
function FT.SnapScale(v)
  return FT.CleanScale(hundredth(math.floor(v / FT.SCALE_STEP + 0.5) * FT.SCALE_STEP)) or 1
end

-- One step up (dir 1) or down (dir -1); a value between two steps goes to the next one.
function FT.StepScale(current, dir)
  local v = finite(current) and current or 1
  local n = v / FT.SCALE_STEP
  local k
  if dir > 0 then
    k = math.floor(n + 1e-6) + 1
  else
    k = math.ceil(n - 1e-6) - 1
  end
  return FT.CleanScale(hundredth(k * FT.SCALE_STEP)) or 1
end

function FT.Percent(scale)
  return math.floor(scale * 100 + 0.5)
end

-- Zoom while the resize grip (at the bottom right corner) is pulled by dx, dy screen units from
-- where it was taken: right and down grow. w, h: size of the window at zoom 1. snap: steps of 5 %.
function FT.DragScale(startScale, w, h, dx, dy, snap)
  if not (finite(startScale) and finite(dx) and finite(dy) and finite(w) and finite(h) and w > 0 and h > 0) then
    return FT.CleanScale(startScale) or 1
  end
  local s = FT.CleanScale(startScale + (dx / w - dy / h) / 2) or 1
  return snap and FT.SnapScale(s) or s
end

-- Background opacity ------------------------------------------------------------------------------

FT.ALPHA_MIN, FT.ALPHA_MAX, FT.ALPHA_STEP = 0, 100, 5

-- Parts of a window that carry its background, looked up by key on the window.
FT.BG_KEYS = { "NineSlice", "Bg", "Inset", "InsetBg", "Background", "TitleBg", "TopTileStreaks" }

-- Draw layers of the frame art; text and icons live above them.
function FT.BackgroundLayer(layer)
  return layer == "BACKGROUND" or layer == "BORDER"
end

-- Opacity modes: only the background textures of a window, or the whole window (its text fades
-- too, so the value never drops below WINDOW_ALPHA_MIN percent).
FT.ALPHA_MODES = { "background", "window" }
FT.WINDOW_ALPHA_MIN = 35

function FT.CleanMode(v)
  if v == "background" or v == "window" then
    return v
  end
  return nil
end

-- Percent that is really set on the window in the given mode.
function FT.EffectiveAlpha(mode, percent)
  if mode == "window" then
    return math.max(FT.WINDOW_ALPHA_MIN, percent)
  end
  return percent
end

-- Deep scan of a window for background textures: depth below the window, frames looked at per
-- window, share of the window area that makes a texture "large", and the size under which a
-- texture on both sides counts as an icon.
FT.SCAN_DEPTH, FT.SCAN_MAX_FRAMES, FT.SCAN_HOOK_DEPTH, FT.SCAN_MAX_HOOKS = 6, 400, 3, 40
FT.LARGE_SHARE, FT.ICON_SIZE = 0.08, 64
-- Methods of a frame whose call means that the client built its textures again.
FT.REFRESH_METHODS = { "SetCurrentPage", "UpdateAllElements" }

local BG_KEY_SET = {}
for _, key in ipairs(FT.BG_KEYS) do
  BG_KEY_SET[key] = true
end
local HINT_PARTS = { "nineslice", "background", "parchment", "backdrop" }
local HINT_WORDS = { bg = true, inset = true, art = true, border = true }

-- Does a frame name or field name point at the window's background ("InsetBg", "CharacterFrameInset")?
function FT.BackgroundName(name)
  if type(name) ~= "string" or name == "" then
    return false
  end
  if BG_KEY_SET[name] then
    return true
  end
  local lower = name:lower()
  for _, part in ipairs(HINT_PARTS) do
    if lower:find(part, 1, true) then
      return true
    end
  end
  for word in name:gsub("[%d_]", " "):gmatch("%a%l*") do
    if HINT_WORDS[word:lower()] then
      return true
    end
  end
  return false
end

local function contains(text, parts)
  if type(text) ~= "string" then
    return false
  end
  local lower = text:lower()
  for _, part in ipairs(parts) do
    if lower:find(part, 1, true) then
      return true
    end
  end
  return false
end

local ITEM_PARTS = { "slot", "icon", "button" }
local PORTRAIT_PARTS = { "portrait", "profileicon" }
-- The gamepad focus glow is oversized and invisible with a mouse: fading it only costs time.
local GLOW_PARTS = { "frameglow" }
local GLOW_ATLAS_PARTS = { "gamepad", "-focus" }

-- Is a texture of a window part of its background? t: layer, w, h, windowArea, parentKind (object
-- type of the holder), parentLabel and name (names or field names of holder and texture), atlas
-- (atlas name, may be missing), hinted (the holder is background art). Returns hit, large and, for a
-- texture left alone, the reason.
function FT.Classify(t)
  local w = finite(t.w) and t.w or 0
  local h = finite(t.h) and t.h or 0
  local area = finite(t.windowArea) and t.windowArea or 0
  local large = area > 0 and w * h >= FT.LARGE_SHARE * area and not (w < FT.ICON_SIZE and h < FT.ICON_SIZE)
  local kind = type(t.parentKind) == "string" and t.parentKind or ""
  local named = FT.BackgroundName(t.name)
  if contains(t.parentLabel, GLOW_PARTS) or contains(t.name, GLOW_PARTS) or contains(t.atlas, GLOW_ATLAS_PARTS) then
    return false, large, "glow"
  end
  if kind:find("Button", 1, true) then
    return false, large, "button"
  end
  if contains(t.parentLabel, ITEM_PARTS) or contains(t.name, ITEM_PARTS) then
    return false, large, "slot"
  end
  if contains(t.parentLabel, PORTRAIT_PARTS) or contains(t.name, PORTRAIT_PARTS) then
    return false, large, "portrait"
  end
  -- A model holds its own background pieces next to the model: only those pass.
  if kind:find("Model", 1, true) and not named then
    return false, large, "model"
  end
  if named or t.hinted or FT.BackgroundLayer(t.layer) or large then
    return true, large, nil
  end
  return false, large, "artwork"
end

-- A whole percent inside the limits, nil for anything that is not a number.
function FT.CleanAlpha(v)
  if not finite(v) then
    return nil
  end
  return math.max(FT.ALPHA_MIN, math.min(FT.ALPHA_MAX, math.floor(v + 0.5)))
end

-- One step up (dir 1) or down (dir -1); a value between two steps goes to the next one.
function FT.StepAlpha(current, dir)
  local v = finite(current) and current or FT.ALPHA_MAX
  local n = v / FT.ALPHA_STEP
  local k
  if dir > 0 then
    k = math.floor(n + 1e-6) + 1
  else
    k = math.ceil(n - 1e-6) - 1
  end
  return FT.CleanAlpha(k * FT.ALPHA_STEP) or FT.ALPHA_MAX
end

-- Defaults of the settings page: steps and limits of zoom and opacity (whole percent). The zoom
-- stays inside 50 to 200 and always includes 100, the opacity inside 0 to 100.
local function whole(v, low, high, default)
  if not finite(v) then
    return default
  end
  return math.max(low, math.min(high, math.floor(v + 0.5)))
end

function FT.Configure(opts)
  opts = type(opts) == "table" and opts or {}
  FT.SCALE_STEP = whole(opts.zoomStep, 1, 10, 5) / 100
  FT.SCALE_MIN = whole(opts.zoomMin, 50, 100, 50) / 100
  FT.SCALE_MAX = whole(opts.zoomMax, 100, 200, 200) / 100
  FT.ALPHA_STEP = whole(opts.alphaStep, 1, 10, 5)
  FT.ALPHA_MIN = whole(opts.alphaMin, 0, 90, 0)
end

-- Top left corner (screen units, y up) of a window anchored to the screen by its first point.
-- size as in FT.Clamp. Nil when the window is anchored to another frame.
function FT.Corner(entry, size)
  if type(entry) ~= "table" or not AX[entry.p] or not AX[entry.rp or entry.p] then
    return nil
  end
  local s = size.scale or 1
  local rp = entry.rp or entry.p
  local left = AX[rp] * size.sw + entry.x * s - AX[entry.p] * size.w * s
  local bottom = AY[rp] * size.sh + entry.y * s - AY[entry.p] * size.h * s
  return left, bottom + size.h * s
end

-- The anchor that keeps a top left corner on the same screen spot at a new zoom (not rounded, so
-- repeated zooming does not drift).
function FT.TopLeftAt(left, top, scale)
  return { p = "TOPLEFT", r = "UIParent", rp = "BOTTOMLEFT", x = left / scale, y = top / scale }
end

-- Bar --------------------------------------------------------------------------------------------

FT.BAR_HEIGHT, FT.BAR_GAP, FT.BAR_IDLE_ALPHA = 22, 1, 0.4

local STRATA = {
  "BACKGROUND",
  "LOW",
  "MEDIUM",
  "HIGH",
  "DIALOG",
  "FULLSCREEN",
  "FULLSCREEN_DIALOG",
  "TOOLTIP",
}
local STRATA_RANK = {}
for i, name in ipairs(STRATA) do
  STRATA_RANK[name] = i
end

-- The strata above the window's (the bar must not sit under it); tooltips stay above the bar.
function FT.BarStrata(windowStrata)
  local rank = STRATA_RANK[windowStrata] or STRATA_RANK.MEDIUM
  return STRATA[math.min(rank + 1, STRATA_RANK.FULLSCREEN_DIALOG)]
end

-- Below the window (offset in screen units from the window's bottom edge) or, when the screen
-- ends there, inside the bottom of the screen. bottom: window's bottom edge, screen units.
-- inside: the player wants it inside the window's bottom edge.
function FT.BarPlacement(bottom, barHeight, gap, inside)
  if inside then
    return { inside = true, y = (finite(bottom) and bottom < 0) and -bottom or 0 }
  end
  if finite(bottom) and bottom - gap - barHeight >= 0 then
    return { inside = false, y = -gap }
  end
  return { inside = true, y = finite(bottom) and -bottom or 0 }
end

-- Windows narrower than this (screen units) get a bar with numbers and buttons only, no sliders.
FT.BAR_SLIDER_MIN_WINDOW = 360

function FT.BarSliders(windowWidth)
  return finite(windowWidth) and windowWidth >= FT.BAR_SLIDER_MIN_WINDOW
end

-- Handle, bar or nothing ---------------------------------------------------------------------------

-- grip: a small handle that opens a panel (default), bar: the fixed bar, off: keys and commands only.
FT.BAR_MODES = { "grip", "bar", "off" }
FT.HANDLE_SIZE = 18

function FT.CleanBarMode(v)
  for _, mode in ipairs(FT.BAR_MODES) do
    if v == mode then
      return v
    end
  end
  return nil
end

-- The mode in force. legacyOn is the switch of the versions before the modes (settings.frameBar):
-- false there means off and stays so until the player picks a mode on the page.
function FT.BarMode(mode, legacyOn)
  if legacyOn == false then
    return "off"
  end
  return FT.CleanBarMode(mode) or "grip"
end

-- Rectangles are { l, b, r, t } in the units of UIParent, y up.
local EDGE = 1.5

function FT.Rect(l, b, r, t)
  if finite(l) and finite(b) and finite(r) and finite(t) and r > l and t > b then
    return { l = l, b = b, r = r, t = t }
  end
  return nil
end

local function overlaps(a, b)
  return a.l < b.r - 0.01 and b.l < a.r - 0.01 and a.b < b.t - 0.01 and b.b < a.t - 0.01
end
FT.Overlaps = overlaps

-- A part of a window (tab, button row) that hangs out of it and can be in the way, or nil: parts
-- inside the window, and frames that surround the whole window (glow, backdrop), do not count.
function FT.Protrusion(win, part)
  if not (win and part) then
    return nil
  end
  local out = part.l < win.l - EDGE or part.r > win.r + EDGE or part.b < win.b - EDGE or part.t > win.t + EDGE
  local around = part.l <= win.l + EDGE and part.r >= win.r - EDGE and part.b <= win.b + EDGE and part.t >= win.t - EDGE
  if out and not around then
    return part
  end
  return nil
end

local function hits(box, list)
  for _, other in ipairs(list) do
    if overlaps(box, other) then
      return true
    end
  end
  return false
end

local function span(low, length, limit)
  return math.max(0, math.min(low, limit - length))
end

-- Is the box on the screen, off the window and clear of every part?
local function free(box, win, parts, screen)
  return box.l >= -0.01
    and box.b >= -0.01
    and box.r <= screen.w + 0.01
    and box.t <= screen.h + 0.01
    and not overlaps(box, win)
    and not hits(box, parts)
end

-- The anchor that puts the box where it is: its point p against the point rp of the reference.
local function anchored(side, p, rp, box, ref)
  local bx = box.l + AX[p] * (box.r - box.l)
  local by = box.b + AY[p] * (box.t - box.b)
  local rx = ref.l + AX[rp] * (ref.r - ref.l)
  local ry = ref.b + AY[rp] * (ref.t - ref.b)
  return { side = side, p = p, rp = rp, x = hundredth(bx - rx), y = hundredth(by - ry), box = box }
end

local function box(l, b, w, h)
  return { l = l, b = b, r = l + w, t = b + h }
end

-- Where a bar of size { w, h } goes without covering a part of the window: under the deepest part
-- in its way, else above the window, else at its right, else at its left. Nil when nothing is free.
-- win, parts (list of rects) and screen { w, h } are in UIParent units.
function FT.PlaceBar(win, parts, size, screen, gap)
  local w, h = size.w, size.h
  local cx = (win.l + win.r) / 2
  local l = span(cx - w / 2, w, screen.w)
  local r = l + w
  local low, high = win.b, win.t
  for _, part in ipairs(parts) do
    if part.r > l and part.l < r then
      low = math.min(low, part.b)
      high = math.max(high, part.t)
    end
  end
  local candidates = {
    anchored("below", "TOP", "BOTTOM", box(l, low - gap - h, w, h), win),
    anchored("above", "BOTTOM", "TOP", box(l, high + gap, w, h), win),
  }
  local b = span(win.b, h, screen.h)
  local right, left = win.r + gap, win.l - gap
  for _, part in ipairs(parts) do
    if part.t > b and part.b < b + h then
      if part.r > win.r then
        right = math.max(right, part.r + gap)
      end
      if part.l < win.l then
        left = math.min(left, part.l - gap)
      end
    end
  end
  candidates[#candidates + 1] = anchored("right", "BOTTOMLEFT", "BOTTOMRIGHT", box(right, b, w, h), win)
  candidates[#candidates + 1] = anchored("left", "BOTTOMRIGHT", "BOTTOMLEFT", box(left - w, b, w, h), win)
  for _, at in ipairs(candidates) do
    if free(at.box, win, parts, screen) then
      return at
    end
  end
  return nil
end

-- Where the handle (a square of size s) goes: outside the lower right corner of the window, below
-- it, beside it, above its right corner, at its left; then below the deepest part in its way. When
-- nothing is free it sits inside the corner (fallback = true), that spot always exists.
function FT.PlaceHandle(win, parts, s, screen, gap)
  local l = win.r - s
  local low = win.b
  for _, part in ipairs(parts) do
    if part.r > l and part.l < win.r then
      low = math.min(low, part.b)
    end
  end
  local candidates = {
    anchored("below", "TOPRIGHT", "BOTTOMRIGHT", box(l, win.b - gap - s, s, s), win),
    anchored("right", "BOTTOMLEFT", "BOTTOMRIGHT", box(win.r + gap, win.b, s, s), win),
    anchored("above", "BOTTOMRIGHT", "TOPRIGHT", box(l, win.t + gap, s, s), win),
    anchored("left", "BOTTOMRIGHT", "BOTTOMLEFT", box(win.l - gap - s, win.b, s, s), win),
    anchored("deep", "TOPRIGHT", "BOTTOMRIGHT", box(l, low - gap - s, s, s), win),
  }
  for _, at in ipairs(candidates) do
    if free(at.box, win, parts, screen) then
      return at
    end
  end
  local inner = box(span(win.r - s - 2, s, screen.w), span(win.b + 2, s, screen.h), s, s)
  local at = anchored("inside", "BOTTOMRIGHT", "BOTTOMRIGHT", inner, win)
  at.fallback = true
  return at
end

-- Where a panel of size { w, h } opens next to the handle box: below it, else above it, flush right
-- with the handle, else flush left, always inside the screen.
function FT.PlacePopover(handle, size, screen, gap)
  local w, h = size.w, size.h
  local below = handle.b - gap - h >= 0
  local above = handle.t + gap + h <= screen.h
  local down = below or not above
  local flushRight = handle.r - w >= 0
  local l = flushRight and handle.r - w or handle.l
  l = span(l, w, screen.w)
  local b = down and handle.b - gap - h or handle.t + gap
  b = span(b, h, screen.h)
  local p = (down and "TOP" or "BOTTOM") .. (flushRight and "RIGHT" or "LEFT")
  local rp = (down and "BOTTOM" or "TOP") .. (flushRight and "RIGHT" or "LEFT")
  return anchored(down and "below" or "above", p, rp, box(l, b, w, h), handle)
end

-- Detection -------------------------------------------------------------------------------------

-- Parts a window of the client has (title strip, frame art, close button, background).
FT.SIGNATURE_KEYS = { "TitleContainer", "TitleBar", "TitleBg", "NineSlice", "CloseButton", "Bg" }
FT.SIGNATURE_MIN_W, FT.SIGNATURE_MIN_H = 150, 100

-- info: name, rootChild (parent is UIParent), keys (set of parts present), w, h, strata.
function FT.Signature(info)
  if type(info) ~= "table" or FT.Excluded(info.name) or info.rootChild ~= true then
    return false
  end
  if not (finite(info.w) and finite(info.h) and info.w > FT.SIGNATURE_MIN_W and info.h > FT.SIGNATURE_MIN_H) then
    return false
  end
  local rank = STRATA_RANK[info.strata]
  if not rank or rank < STRATA_RANK.MEDIUM or rank > STRATA_RANK.DIALOG then
    return false
  end
  for _, key in ipairs(FT.SIGNATURE_KEYS) do
    if type(info.keys) == "table" and info.keys[key] then
      return true
    end
  end
  return false
end

-- A usable saved position or nil for anything damaged.
function FT.Clean(raw)
  if type(raw) ~= "table" or not AX[raw.p] then
    return nil
  end
  local x, y = offset(raw.x), offset(raw.y)
  if x == nil or y == nil then
    return nil
  end
  if raw.rp ~= nil and not AX[raw.rp] then
    return nil
  end
  if raw.r ~= nil and (type(raw.r) ~= "string" or raw.r == "") then
    return nil
  end
  return {
    p = raw.p,
    r = raw.r or "UIParent",
    rp = raw.rp or raw.p,
    x = x,
    y = y,
    scale = FT.CleanScale(raw.scale),
    alpha = FT.CleanAlpha(raw.alpha),
  }
end

-- relName: name of the anchor frame, nil for UIParent.
function FT.Encode(point, relName, relPoint, x, y)
  return FT.Clean({ p = point, r = relName, rp = relPoint, x = x, y = y })
end

local function num(n)
  return (string.format("%.1f", n):gsub("%.0$", ""))
end

function FT.Describe(entry)
  return string.format("%s %s, %s", entry.p, num(entry.x), num(entry.y))
end

-- Names with a usable saved position, sorted.
function FT.SavedNames(frames)
  local out = {}
  if type(frames) == "table" then
    for name, raw in pairs(frames) do
      if type(name) == "string" and FT.Clean(raw) then
        out[#out + 1] = name
      end
    end
  end
  table.sort(out)
  return out
end

-- Export and import ---------------------------------------------------------------------------------

-- Text of the window values: a head line, then one line per window
-- "Name|point|relative frame|relative point|x|y|zoom|opacity", empty fields for what is not set.
-- A window with its own opacity mode gets a ninth field (background or window); older lines have
-- eight fields and stay valid. Plain text only, nothing of it is ever run.
FT.EXPORT_HEAD = "FGWIN1"
FT.IMPORT_MAX_LINES, FT.IMPORT_MAX_CHARS, FT.NAME_MAX = 400, 60000, 80

-- The name of a window or of its maximized state ("WorldMapFrame:max").
function FT.ValidName(name)
  if type(name) ~= "string" or #name == 0 or #name > FT.NAME_MAX or not name:find("^[%w_]+:?%w*$") then
    return false
  end
  return not FT.Excluded((name:gsub(":.*$", "")), true)
end

local function trimmed(n, places)
  return (string.format("%." .. places .. "f", n):gsub("0+$", ""):gsub("%.$", ""))
end

-- Zoom 0.5 to 2 as typed, never clamped to the player's own limits.
local function zoomOf(v)
  if finite(v) and v >= 0.5 and v <= 2 then
    return hundredth(v)
  end
  return nil
end

local function opacityOf(v)
  if finite(v) and v >= 0 and v <= 100 then
    return math.floor(v + 0.5)
  end
  return nil
end

function FT.Export(frames)
  local lines = { FT.EXPORT_HEAD }
  local names = {}
  for name in pairs(type(frames) == "table" and frames or {}) do
    if FT.ValidName(name) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local raw = frames[name]
    local pos = type(raw) == "table" and FT.Clean(raw) or nil
    local scale = type(raw) == "table" and zoomOf(raw.scale) or nil
    local alpha = type(raw) == "table" and opacityOf(raw.alpha) or nil
    local mode = type(raw) == "table" and FT.CleanMode(raw.alphaMode) or nil
    if pos or scale or alpha or mode then
      lines[#lines + 1] = table.concat({
        name,
        pos and pos.p or "",
        pos and pos.r or "",
        pos and pos.rp or "",
        pos and trimmed(pos.x, 1) or "",
        pos and trimmed(pos.y, 1) or "",
        scale and trimmed(scale, 2) or "",
        alpha and tostring(alpha) or "",
        mode,
      }, "|")
    end
  end
  return table.concat(lines, "\n")
end

local function field(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One line of an import: the entry { name, p, r, rp, x, y, scale, alpha, alphaMode } or nil.
local function parseLine(line)
  local f = {}
  for part in (line .. "|"):gmatch("([^|]*)|") do
    f[#f + 1] = field(part)
  end
  if (#f ~= 8 and #f ~= 9) or not FT.ValidName(f[1]) then
    return nil
  end
  local item = { name = f[1] }
  if f[2] ~= "" then
    if f[3] ~= "" and not f[3]:find("^[%w_]+$") then
      return nil
    end
    local clean = FT.Clean({
      p = f[2],
      r = f[3] ~= "" and f[3] or nil,
      rp = f[4] ~= "" and f[4] or nil,
      x = tonumber(f[5]),
      y = tonumber(f[6]),
    })
    if not clean then
      return nil
    end
    item.p, item.r, item.rp, item.x, item.y = clean.p, clean.r, clean.rp, clean.x, clean.y
  elseif f[3] ~= "" or f[4] ~= "" or f[5] ~= "" or f[6] ~= "" then
    return nil
  end
  if f[7] ~= "" then
    item.scale = zoomOf(tonumber(f[7]))
    if not item.scale then
      return nil
    end
  end
  if f[8] ~= "" then
    item.alpha = opacityOf(tonumber(f[8]))
    if not item.alpha then
      return nil
    end
  end
  if f[9] and f[9] ~= "" then
    item.alphaMode = FT.CleanMode(f[9])
    if not item.alphaMode then
      return nil
    end
  end
  if not (item.p or item.scale or item.alpha or item.alphaMode) then
    return nil
  end
  return item
end

-- { head = the first line is the head, entries = list, rejected = count of lines that were not usable }.
function FT.ParseImport(text)
  local out = { head = false, entries = {}, rejected = 0 }
  if type(text) ~= "string" or #text > FT.IMPORT_MAX_CHARS then
    return out
  end
  local byName, seenHead, lines = {}, false, 0
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    line = field(line)
    if line ~= "" then
      if not seenHead then
        if line ~= FT.EXPORT_HEAD then
          return out
        end
        seenHead, out.head = true, true
      else
        lines = lines + 1
        local item = lines <= FT.IMPORT_MAX_LINES and parseLine(line) or nil
        if item then
          if byName[item.name] then
            out.entries[byName[item.name]] = item
          else
            out.entries[#out.entries + 1] = item
            byName[item.name] = #out.entries
          end
        else
          out.rejected = out.rejected + 1
        end
      end
    end
  end
  return out
end

-- Counts for the preview: entries that are new and entries that replace a saved one.
function FT.ImportCounts(parsed, frames)
  local new, replaced = 0, 0
  for _, item in ipairs(parsed.entries) do
    if type(frames) == "table" and frames[item.name] ~= nil then
      replaced = replaced + 1
    else
      new = new + 1
    end
  end
  return new, replaced, parsed.rejected
end

-- The saved form of an imported entry (only the fields that were set).
function FT.EntryOf(item)
  local entry = { scale = item.scale, alpha = item.alpha, alphaMode = item.alphaMode }
  if item.p then
    entry.p, entry.r, entry.rp, entry.x, entry.y = item.p, item.r, item.rp, item.x, item.y
  end
  return entry
end

-- Window list --------------------------------------------------------------------------------------

FT.FILTERS = { "all", "changed", "auto" }

-- rows: { name, changed, auto }. query: part of a name (any case). mode: all, changed or auto.
function FT.FilterRows(rows, query, mode)
  local needle = type(query) == "string" and query:lower() or ""
  local out = {}
  for _, row in ipairs(rows) do
    local keep = needle == "" or row.name:lower():find(needle, 1, true) ~= nil
    if mode == "changed" then
      keep = keep and row.changed == true
    elseif mode == "auto" then
      keep = keep and row.auto == true
    end
    if keep then
      out[#out + 1] = row
    end
  end
  return out
end

-- Keeps at least MIN_VISIBLE pixels of the window inside the screen. Only positions relative to
-- UIParent can be judged. size: w, h of the window, sw, sh of the screen, scale of the window
-- relative to UIParent. Returns the entry and whether it moved.
function FT.Clamp(entry, size)
  if type(entry) ~= "table" or entry.r ~= "UIParent" or type(size) ~= "table" then
    return entry, false
  end
  local w, h, sw, sh, s = size.w, size.h, size.sw, size.sh, size.scale or 1
  for _, v in ipairs({ w or 0, h or 0, sw or 0, sh or 0, s }) do
    if type(v) ~= "number" or v ~= v or v <= 0 then
      return entry, false
    end
  end
  w, h = w * s, h * s
  local left = AX[entry.rp] * sw + entry.x * s - AX[entry.p] * w
  local bottom = AY[entry.rp] * sh + entry.y * s - AY[entry.p] * h
  local mx, my = math.min(FT.MIN_VISIBLE, w), math.min(FT.MIN_VISIBLE, h)
  local newLeft = math.max(mx - w, math.min(sw - mx, left))
  local newBottom = math.max(my - h, math.min(sh - my, bottom))
  if newLeft == left and newBottom == bottom then
    return entry, false
  end
  local out = {
    p = entry.p,
    r = entry.r,
    rp = entry.rp,
    x = FT.Round(entry.x + (newLeft - left) / s),
    y = FT.Round(entry.y + (newBottom - bottom) / s),
  }
  return out, true
end

-- Combat ------------------------------------------------------------------------------------------

-- Protected windows are never touched in combat, the others only when combat safety is off.
function FT.CanTouch(inCombat, isProtected, combatSafe)
  if not inCombat then
    return true
  end
  return not isProtected and not combatSafe
end

-- One pending action per window: a later, stronger one replaces an earlier one.
local RANK = { restore = 1, reset = 2, hook = 3 }

local Queue = {}
Queue.__index = Queue

function FT.NewQueue()
  return setmetatable({ items = {} }, Queue)
end

function Queue:Add(name, action)
  if type(name) ~= "string" or not RANK[action] then
    return
  end
  local current = self.items[name]
  if not current or RANK[action] > RANK[current] then
    self.items[name] = action
  end
end

function Queue:Has(name)
  return self.items[name]
end

function Queue:Count()
  local n = 0
  for _ in pairs(self.items) do
    n = n + 1
  end
  return n
end

-- All pending { name, action } sorted by name; the queue is empty afterwards.
function Queue:Take()
  local out = {}
  for name, action in pairs(self.items) do
    out[#out + 1] = { name = name, action = action }
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  self.items = {}
  return out
end
