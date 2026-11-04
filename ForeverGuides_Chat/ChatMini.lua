-- Forever Chat, the mini window: a small window of its own for one whisper partner, without the list. It
-- shows the last lines in the compact look and the input line of the partner (ChatInput.lua), moves by its
-- title bar, resizes by the grip, closes on Esc and remembers place and size per partner (the last
-- MAX_SAVED partners). At most MAX windows are open at once; the frames are built when first needed (never in
-- combat) and reused. A window opens from the chat menu ("Open as mini window") and by itself when a new
-- unread line arrives for a chat whose view the player set to "Mini" (not in combat, not while the big window
-- shows that chat, not above the limit). Nothing here sends: the input line sends on Enter like everywhere.
local _, chat = ...
if not chat.hook then
  return
end

local FG = chat.FG
local W, L, Theme = FG.W, FG.L, FG.Theme
local Shell, WS = FG.WindowShell, FG.WindowStyle
local LL, Thread = chat.ListLogic, chat.Thread

local Mini = {}
chat.Mini = Mini

Mini.MAX = 5
Mini.MAX_SAVED = 20
Mini.DEFAULT_W, Mini.DEFAULT_H = 300, 220
Mini.MIN_W, Mini.MIN_H, Mini.MAX_W, Mini.MAX_H = 240, 160, 640, 600
-- STRIP_H is the title strip of the flat look; in the skin "forever" the metal bar replaces it (Shell.HeadHeight).
local STRIP_H, PAD, GAP = 22, 6, 6

local slots = {}
local emitting = false
local seen = {}

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- Rules (no frames) -------------------------------------------------------------------------------------------

-- True for a chat the player set to "Mini" (its own view setting; the default view never opens windows).
function Mini.Wants(db, conv)
  local view = type(db) == "table" and type(db.view) == "table" and db.view or {}
  return conv ~= nil and conv.kind == "whisper" and type(view.chats) == "table" and view.chats[conv.key] == "mini"
end

-- Menu entries of the views for a conversation: the look it does not have yet, the mini window for a whisper
-- (the only kind that has one) and the open window. mode: its view now (nil: the default of the store).
function Mini.MenuItems(conv, mode, open)
  local items = {}
  local function add(id, key)
    items[#items + 1] = { id = id, key = key, group = "view" }
  end
  if mode ~= "messenger" then
    add("viewMessenger", "chat.menu.viewMessenger")
  end
  if mode ~= "compact" then
    add("viewCompact", "chat.menu.viewCompact")
  end
  if conv.kind == "whisper" then
    if mode ~= "mini" then
      add("viewMini", "chat.menu.viewMini")
    end
    if not open then
      add("openMini", "chat.menu.openMini")
    end
  end
  return items
end

-- Saved geometry ---------------------------------------------------------------------------------------------

local function store()
  local frames = FG.db.frames
  if type(frames.chatMini) ~= "table" then
    frames.chatMini = {}
  end
  return frames.chatMini
end

-- The saved { x, y, w, h } of a partner, clamped; nil when there is none.
function Mini.Geometry(key)
  local saved = FG.db and store()[key]
  if type(saved) ~= "table" then
    return nil
  end
  return {
    x = finite(saved.x) and saved.x or nil,
    y = finite(saved.y) and saved.y or nil,
    w = clamp(finite(saved.w) and saved.w or Mini.DEFAULT_W, Mini.MIN_W, Mini.MAX_W),
    h = clamp(finite(saved.h) and saved.h or Mini.DEFAULT_H, Mini.MIN_H, Mini.MAX_H),
  }
end

-- Keeps the geometry of a partner; the oldest entries go when more than MAX_SAVED partners are kept.
function Mini.SaveGeometry(key, x, y, w, h)
  if type(key) ~= "string" or key == "" or #key > chat.Store.KEY_BYTES or not FG.db then
    return false
  end
  local map = store()
  Mini.clock = (Mini.clock or 0) + 1
  map[key] = { x = x, y = y, w = w, h = h, t = Mini.clock }
  local keys = {}
  for k in pairs(map) do
    keys[#keys + 1] = k
  end
  if #keys > Mini.MAX_SAVED then
    table.sort(keys, function(a, b)
      local ta, tb = finite(map[a].t) and map[a].t or 0, finite(map[b].t) and map[b].t or 0
      if ta ~= tb then
        return ta < tb
      end
      return a < b
    end)
    for i = 1, #keys - Mini.MAX_SAVED do
      map[keys[i]] = nil
    end
  end
  return true
end

-- Slots ---------------------------------------------------------------------------------------------------------

local function slotOf(key)
  for _, slot in ipairs(slots) do
    if slot.key == key and slot.frame:IsShown() then
      return slot
    end
  end
  return nil
end

function Mini.IsOpen(key)
  return slotOf(key) ~= nil
end

function Mini.Count()
  local n = 0
  for _, slot in ipairs(slots) do
    n = n + (slot.frame:IsShown() and 1 or 0)
  end
  return n
end

function Mini.Keys()
  local out = {}
  for _, slot in ipairs(slots) do
    if slot.frame:IsShown() and slot.key then
      out[#out + 1] = slot.key
    end
  end
  table.sort(out)
  return out
end

function Mini.Frame(key)
  local slot = slotOf(key)
  return slot and slot.frame or nil
end

function Mini.Slot(key)
  return slotOf(key)
end

local function save(slot)
  local f = slot.frame
  if not (slot.key and f.ready) then
    return
  end
  local left, top = f:GetLeft(), f:GetTop()
  if left and top then
    local s = f:GetScale() or 1
    Mini.SaveGeometry(slot.key, left * s, top * s, f:GetWidth(), f:GetHeight())
  end
end

local function place(slot)
  local f = slot.frame
  local geo = Mini.Geometry(slot.key)
  f:SetScale(Theme.windowScale())
  f:SetResizeBounds(Mini.MIN_W, Mini.MIN_H, Mini.MAX_W, Mini.MAX_H)
  f:SetSize(geo and geo.w or Mini.DEFAULT_W, geo and geo.h or Mini.DEFAULT_H)
  f:ClearAllPoints()
  if geo and geo.x and geo.y then
    local s = f:GetScale() or 1
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", geo.x / s, geo.y / s)
  else
    -- A window with no saved place cascades from the centre, so two new ones never cover each other.
    local n = Mini.Count()
    f:SetPoint("CENTER", UIParent, "CENTER", 30 * n, -30 * n)
  end
end

local function applyLook(slot)
  local f = slot.frame
  WS.Apply(f, chat.Settings.Style(nil), f.styleParts)
end

-- Layout of the thread and the input line for the size of the window. sync: draw the thread at once.
local function layout(slot, sync)
  local f = slot.frame
  local w, h = f:GetWidth() or Mini.MIN_W, f:GetHeight() or Mini.MIN_H
  local cw, ch = w - 2 * PAD, h - Shell.HeadHeight(f) - 2 * PAD
  slot.host:SetWidth(cw)
  slot.input:Fit(cw)
  local input = slot.host:GetHeight() or 0
  slot.thread.frame:ClearAllPoints()
  slot.thread.frame:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
  slot.thread.frame:SetPoint("BOTTOMRIGHT", slot.host, "TOPRIGHT", 0, input > 0 and GAP or 0)
  slot.thread:SetViewSize(cw, ch - input - (input > 0 and GAP or 0))
  local function heavy()
    if f:IsShown() then
      slot.thread:Refresh()
    end
  end
  if sync then
    heavy()
  else
    FG.Debounce("chat-mini-size-" .. (slot.index or 0), 0.05, heavy)
  end
end

local function title(slot)
  local conv = slot.key and chat.convs and chat.convs.convs[slot.key]
  if not conv then
    return
  end
  local text = LL.Title(conv, chat.db.nicknames[conv.key], L["chat.kind." .. conv.kind])
  slot.frame.shell.titleText:SetText(text)
end

local function announce(key)
  emitting = true
  FG.Emit("FG_CHAT_UPDATE", { [key] = true }, chat.Unread.Total(chat.convs))
  emitting = false
end

local function build(index)
  local slot = { index = index }
  local f = CreateFrame("Frame", "FGChatMini" .. index, UIParent)
  slot.frame = f
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  f.bg = W.Fill(f, "bg", 0.97)
  f.shell = Shell.Attach(f, {
    text = " ",
    titleHeight = STRIP_H,
    shadow = true,
    onHead = function()
      if f.content then
        f.content:SetPoint("TOPLEFT", PAD, -(Shell.HeadHeight(f) + PAD))
        local side = Shell.BarControlSize(f, 18)
        f.close:SetSize(side, side)
        if f.ready then
          layout(slot, false)
        end
      end
    end,
  })
  f.bar = f.shell.titleBar
  f.bar:HookScript(
    "OnDragStop",
    FG.Wrap("chat-mini-move", function()
      f:StopMovingOrSizing()
      save(slot)
    end)
  )
  f.close = W.Action(f.bar, { icon = "close", size = 18, tooltip = "common.close" })
  f.close:SetPoint("RIGHT", -2, 0)
  f.close:SetScript(
    "OnClick",
    FG.Wrap("chat-mini-close", function()
      f:Hide()
    end)
  )
  f.shell.titleText:ClearAllPoints()
  f.shell.titleText:SetPoint("LEFT", f.bar, "LEFT", 8, 0)
  f.shell.titleText:SetPoint("RIGHT", f.close, "LEFT", -4, 0)
  f.content = CreateFrame("Frame", nil, f)
  f.content:SetPoint("TOPLEFT", PAD, -(Shell.HeadHeight(f) + PAD))
  f.content:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  slot.host = CreateFrame("Frame", nil, f.content)
  slot.host:SetPoint("BOTTOMLEFT", 0, 0)
  slot.host:SetHeight(0)
  local win = chat.Window
  slot.thread = Thread.Create(f.content, {
    ClassOfName = function(name)
      return win.ClassOfName(name)
    end,
    ClassOf = function(key)
      return win.ClassOfKey(key)
    end,
    MemberOf = function(key)
      return win.MemberOfKey(key)
    end,
    Reading = function()
      return f:IsShown()
    end,
    ReadChanged = function(key)
      announce(key)
    end,
    Back = function() end,
  }, { headless = true, mode = "compact" })
  slot.input = chat.Input.Create(slot.host, {
    Conv = function()
      return slot.key and chat.convs and chat.convs.convs[slot.key] or nil
    end,
    Sent = function()
      slot.thread:Refresh(true)
    end,
    Layout = function()
      layout(slot, true)
    end,
    Menu = function(anchor)
      return slot.key and chat.Menu.Open(slot.key, anchor or slot.input.menu) or false
    end,
    Leave = function() end,
    Draw = function(keys)
      if slot.key and (keys == nil or keys[slot.key]) then
        slot.thread:Refresh()
      end
    end,
  }, { mini = true })

  local grip = CreateFrame("Frame", nil, f)
  grip:SetSize(14, 14)
  grip:EnableMouse(true)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  local tex = grip:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints()
  tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetScript("OnMouseDown", function()
    WS.Hold(f, "size", true)
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript(
    "OnMouseUp",
    FG.Wrap("chat-mini-size", function()
      f:StopMovingOrSizing()
      WS.Hold(f, "size", false)
      save(slot)
      layout(slot, true)
    end)
  )
  grip:SetScript("OnEnter", function(self)
    FG.ShowTooltip(self, L["chat.win.grip"])
  end)
  grip:SetScript("OnLeave", FG.HideTooltip)
  f.grip = grip
  f.styleParts = {
    bg = { f.bg },
    bars = f.shell.bars,
    border = f.shell.border,
    shadow = f.shell.shadow,
    chrome = { f.bar, grip },
    busy = function()
      return false
    end,
  }
  f:SetScript("OnSizeChanged", function()
    if f:IsShown() and slot.key then
      layout(slot, false)
    end
  end)
  f:SetScript(
    "OnShow",
    FG.Wrap("chat-mini-show", function()
      Shell.SetEsc(f, true)
      applyLook(slot)
      title(slot)
      layout(slot, true)
      slot.input:Refresh()
    end)
  )
  f:SetScript(
    "OnHide",
    FG.Wrap("chat-mini-hide", function()
      Shell.SetEsc(f, false)
      slot.input:SaveDraft()
      slot.input.edit:ClearFocus()
      save(slot)
      slot.input:SetConversation(nil, true)
      slot.thread:Clear()
      slot.key = nil
    end)
  )
  f:Hide()
  f.ready = true
  slots[#slots + 1] = slot
  return slot
end

-- Opens the mini window of a whisper chat (the window that shows it already comes to the front). opts.focus:
-- the input line takes the focus. Returns the frame, or nil and why: "conversation" (unknown chat), "kind" (not
-- a whisper), "limit" (MAX windows are open) or "combat" (no free frame and none may be built now).
function Mini.Open(key, opts)
  opts = opts or {}
  local conv = chat.convs and chat.convs.convs[key]
  if not conv then
    return nil, "conversation"
  end
  if conv.kind ~= "whisper" then
    return nil, "kind"
  end
  local open = slotOf(key)
  if open then
    open.frame:Raise()
    return open.frame
  end
  if Mini.Count() >= Mini.MAX then
    return nil, "limit"
  end
  local slot
  for _, candidate in ipairs(slots) do
    if not candidate.frame:IsShown() then
      slot = candidate
      break
    end
  end
  if not slot then
    if FG.InCombat() or not FG.db then
      return nil, "combat"
    end
    slot = build(#slots + 1)
  end
  slot.key = key
  place(slot)
  slot.input:SetConversation(key, true)
  slot.frame:Show()
  slot.thread:Show(conv)
  layout(slot, true)
  slot.frame:Raise()
  if opts.focus then
    slot.input:Focus()
  end
  return slot.frame
end

function Mini.Close(key)
  local slot = slotOf(key)
  if slot then
    slot.frame:Hide()
    return true
  end
  return false
end

function Mini.CloseAll()
  for _, slot in ipairs(slots) do
    if slot.frame:IsShown() then
      slot.frame:Hide()
    end
  end
end

-- Events ---------------------------------------------------------------------------------------------------------

local function mainShows(key)
  local win = chat.Window
  return win.IsShown() and win.State().key == key
end

-- Opens the window of a chat set to "Mini" when a new unread line arrived (more than the last time seen).
local function autoOpen(keys)
  for key in pairs(keys) do
    local conv = chat.convs.convs[key]
    local count = conv and chat.Unread.Count(conv) or 0
    local before = seen[key] or 0
    seen[key] = count
    if
      conv
      and count > before
      and Mini.Wants(chat.db, conv)
      and not slotOf(key)
      and not mainShows(key)
      and not FG.InCombat()
    then
      Mini.Open(key)
    end
  end
end

FG.On("FG_CHAT_UPDATE", function(_, keys)
  if emitting or type(keys) ~= "table" then
    return
  end
  if next(keys) ~= nil then
    FG.Safe("chat-mini-auto", autoOpen, keys)
  end
  for _, slot in ipairs(slots) do
    if slot.key and slot.frame:IsShown() and (next(keys) == nil or keys[slot.key]) then
      if not chat.convs.convs[slot.key] then
        slot.frame:Hide()
      else
        title(slot)
        slot.thread:Refresh()
        slot.input:Refresh(true)
      end
    end
  end
end)

local function relayout()
  for _, slot in ipairs(slots) do
    if slot.frame:IsShown() and slot.key then
      layout(slot, true)
      slot.input:Refresh()
    end
  end
end

FG.On("FG_UI_REFRESHED", relayout)
FG.On("FG_SETTING_CHANGED", function(_, path)
  if WS.AffectsKind(path, "chat") then
    for _, slot in ipairs(slots) do
      applyLook(slot)
    end
  elseif path == "settings.scale" then
    for _, slot in ipairs(slots) do
      slot.frame:SetScale(Theme.windowScale())
    end
  end
end)
FG.On("FG_CHAT_SETTING", function(_, id)
  if id == "opacity" or id == "timeFormat" or id == "timeSeconds" then
    for _, slot in ipairs(slots) do
      applyLook(slot)
      if slot.key and slot.frame:IsShown() then
        slot.thread:Refresh()
      end
    end
  end
end)
FG.On("PLAYER_LOGOUT", function()
  for _, slot in ipairs(slots) do
    if slot.frame:IsShown() then
      save(slot)
    end
  end
end)
