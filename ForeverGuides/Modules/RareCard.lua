-- Hover card of a rare enemy: name, level, elite and the known loot as a row of item buttons. One card
-- frame is shared by the world map pins and the minimap pins; the content comes from RareLogic.lua.
-- The card is our own frame (not GameTooltip) so its item buttons can be hovered and clicked: an item button
-- shows the client's item tooltip, shift-click puts the item link into the chat edit box, ctrl-click opens
-- the dressing room.
-- Two modes. Preview: hovering a pin shows the card, it stays while the mouse is on the pin or on the card and
-- hides RL.CARD_HIDE_DELAY seconds after it left both. Pinned: a left click on a pin keeps the card open
-- independent of the mouse until the close button, Esc, a hidden or changed pin or another pin's click; while
-- pinned, Show (hover) is ignored. A neighbour pin can still take a preview while the mouse travels to the card;
-- that is the reason for click-to-pin (no timing heuristics that would also delay sweeping over pins). The
-- OnUpdate runs only while the card is shown. Esc only takes part while pinned, a preview never eats the key.
--
-- API (ns.RareCard):
--   Show(owner, rare [, id])  preview of a rare (an entry of Data/Rares.lua) next to the owner frame; id = npc id
--   Pin(owner, rare [, id])   the same, pinned (replaces a pinned card)
--   Hide()                    hides the card (and unpins) at once
--   Check()                   hides the card when its owner is gone or shows another rare now
--   IsPinned(), Frame()       state; Frame is nil until the first Show
--   OnChange(fn)              fn(rare, owner, pinned) after every change; rare is nil once the card is hidden
--   Standing(id)              "new" | "seen" | "killed", last seen time, last killed time (server seconds)
--   SetIcon(texture, rare)    paints the pin symbol of a rare in its own colors (RareLogic.Icon: the game's rare
--                             vignette atlas when the client has it, else the raid skull); returns "atlas" or "texture"
--   NewMark(parent, anchor), PaintMark(mark, status)  red disc behind and "!" next to the symbol of a rare not seen yet
--   ItemRow(parent [, opts]) a reusable row of item buttons, opts = { size (px, default 34), gap (default 4),
--                          columns (default 6) }. The row is a frame with
--                          row:SetItems(list)  list = { { id = itemId, chance = percent or nil }, ... } (see
--                                              RareLogic.CardItems); returns the width and height it needs
--                          row:Refresh()       paints again, called when the client delivers item data
--                          Items the client has not cached show a question mark icon and a neutral border
--                          until GET_ITEM_INFO_RECEIVED arrives.
local _, ns = ...
local L, RL, W, Theme = ns.L, ns.RareLogic, ns.W, ns.Theme

local RC = {}
ns.RareCard = RC

ns.AddLocale("enUS", {
  ["rare.card.chance"] = "Drop chance: %s",
  ["rare.card.hint"] = "Shift-click: link in chat",
  ["rare.card.pin"] = "Click to pin",
  ["rare.card.new"] = "Not seen yet",
  ["rare.card.seen"] = "Last seen: %s",
  ["rare.card.killed"] = "Last killed: %s",
  ["rare.card.spawns"] = "%d more spawn points (small markers on the map)",
})
ns.AddLocale("deDE", {
  ["rare.card.chance"] = "Dropchance: %s",
  ["rare.card.hint"] = "Umschalt-Klick: Link in den Chat",
  ["rare.card.pin"] = "Klicken zum Anheften",
  ["rare.card.new"] = "Noch nicht gesehen",
  ["rare.card.seen"] = "Zuletzt gesehen: %s",
  ["rare.card.killed"] = "Zuletzt getötet: %s",
  ["rare.card.spawns"] = "%d weitere Spawnpunkte (kleine Marker auf der Karte)",
})

local QUESTION = 134400
local CARD_WIDTH, PAD = 260, 10
-- Edge of the creature portrait in the top left corner, in px.
local PORTRAIT = 52
local TICK = 0.05

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
end

local function itemApi(name)
  local api = rawget(_G, "C_Item")
  return type(api) == "table" and api[name] or nil
end

local function clock()
  local now = call(rawget(_G, "GetTime"))
  return type(now) == "number" and now or 0
end

local function down(name)
  local fn = rawget(_G, name)
  return type(fn) == "function" and fn() == true
end

local function itemIcon(id)
  local icon = call(itemApi("GetItemIconByID") or rawget(_G, "GetItemIcon"), id)
  return (type(icon) == "number" or type(icon) == "string") and icon or nil
end

-- Pin symbol --------------------------------------------------------------------------------------------

local atlasKnown = {}

local function hasAtlas(name)
  local known = atlasKnown[name]
  if known == nil then
    local api = rawget(_G, "C_Texture")
    known = type(api) == "table" and type(call(api.GetAtlasInfo, name)) == "table"
    atlasKnown[name] = known
  end
  return known
end

-- A rare not seen yet: the symbol keeps its own colors (a vertex tint darkens it into the map) and gets a red
-- disc behind it plus a "!" mark, the way the other map pins show their state with a ring.
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local NEW_RING = 3

function RC.SetIcon(texture, rare)
  local kind, value = RL.Icon(rare, hasAtlas)
  if kind == "atlas" then
    -- SetAtlas sets the coordinates of the atlas region, a later SetTexCoord would show the whole sheet.
    texture:SetAtlas(value)
  else
    texture:SetTexture(value)
    texture:SetTexCoord(0, 1, 0, 1)
  end
  texture:SetVertexColor(1, 1, 1)
  return kind
end

function RC.NewMark(parent, anchor)
  local mark = W.Text(parent, { role = "micro", family = "heading", color = "danger", text = "!" })
  mark:SetPoint("CENTER", anchor, "TOPRIGHT", -1, -1)
  mark:Hide()
  local back = parent:CreateTexture(nil, "BACKGROUND")
  back:SetTexture(DISC)
  back:SetPoint("TOPLEFT", anchor, "TOPLEFT", -NEW_RING, NEW_RING)
  back:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", NEW_RING, -NEW_RING)
  back:SetVertexColor(Theme.color("danger"))
  back:Hide()
  mark.back = back
  return mark
end

function RC.PaintMark(mark, status)
  mark:SetShown(status == "new")
  if mark.back then
    mark.back:SetShown(status == "new")
  end
end

-- Personal state ------------------------------------------------------------------------------------------

local seenIndex, kills

local function indexes()
  if not seenIndex then
    local db = ns.db
    seenIndex = db and RL.SeenIndex(ns.RareFoundLogic.Section(db).items) or {}
    kills = db and RL.KillsSection(db).items or {}
  end
  return seenIndex, kills
end

-- A sighting or a kill was recorded: the next Standing reads the saved lists again.
ns.On("FG_RARE_STATUS", function()
  seenIndex, kills = nil, nil
end)

function RC.Standing(id)
  local seen, dead = indexes()
  return RL.Status(id, seen, dead), seen[id], dead[id]
end

local function serverNow()
  local t = call(rawget(_G, "GetServerTime"))
  return type(t) == "number" and t or ns.U.now()
end

local function ageText(seconds)
  local logic = ns.CraftersViewLogic
  return logic and logic.Age(seconds, L) or string.format("%d s", math.max(0, math.floor(seconds)))
end

-- Item rows ---------------------------------------------------------------------------------------------

-- Every row that exists, so one data event repaints them all.
local rows = setmetatable({}, { __mode = "k" })

-- The item name from the client, nil while it is not cached (ItemInfo.name asks the client once).
local function itemName(id)
  local name = ns.ItemInfo.name(id, nil, nil)
  return type(name) == "string" and name or nil
end

-- The link for the chat box, nil while the item is not cached.
local function chatLink(id)
  local _, link = call(itemApi("GetItemInfo") or rawget(_G, "GetItemInfo"), id)
  if type(link) == "string" and link ~= "" then
    return link
  end
  local name = itemName(id)
  return name and string.format("|Hitem:%d|h[%s]|h", id, name) or nil
end

-- Into the open chat edit box, else opens the chat with the link in it.
local function insertChatLink(link)
  local util = rawget(_G, "ChatFrameUtil")
  util = type(util) == "table" and util or {}
  local insert = util.InsertLink or rawget(_G, "ChatEdit_InsertLink")
  if type(insert) ~= "function" then
    return
  end
  local ok, done = pcall(insert, link)
  local open = util.OpenChat or rawget(_G, "ChatFrame_OpenChat")
  if not (ok and done) and type(open) == "function" then
    pcall(open, link)
  end
end

local function preview(id)
  local show = rawget(_G, "DressUpLink") or rawget(_G, "DressUpItemLink")
  local link = chatLink(id)
  if type(show) == "function" and link then
    pcall(show, link)
  end
end

local function onEnter(btn)
  local id = btn.itemId
  if not id then
    return
  end
  local lines = {}
  if btn.chance then
    lines[1] = {
      text = string.format(L["rare.card.chance"], RL.ChanceText(btn.chance, ns.GetActiveLocale())),
      color = "accent2",
    }
  end
  ns.ShowTooltip(btn, itemName(id) or "", nil, {
    link = "item:" .. id,
    lines = lines,
    hint = L["rare.card.hint"],
    anchor = "ANCHOR_RIGHT",
  })
end

local function onClick(btn)
  local id = btn.itemId
  if not id then
    return
  end
  if down("IsShiftKeyDown") then
    local link = chatLink(id)
    if link then
      insertChatLink(link)
    end
  elseif down("IsControlKeyDown") then
    preview(id)
  end
end

local function newButton(row, size)
  local btn = CreateFrame("Button", nil, row)
  btn:SetSize(size, size)
  btn:RegisterForClicks("LeftButtonUp")
  btn.edge = btn:CreateTexture(nil, "BACKGROUND")
  btn.edge:SetAllPoints()
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetPoint("TOPLEFT", 2, -2)
  btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  btn.strip = btn:CreateTexture(nil, "OVERLAY")
  btn.strip:SetPoint("BOTTOMLEFT", 2, 2)
  btn.strip:SetPoint("BOTTOMRIGHT", -2, 2)
  btn.strip:SetHeight(13)
  btn.chanceText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  btn.chanceText:SetPoint("BOTTOM", btn.strip, "BOTTOM", 0, 1)
  ns.Bind(btn, function(b)
    Theme.applyFont(b.chanceText, "micro", "body")
    b.chanceText:SetTextColor(Theme.color("text"))
    b.strip:SetColorTexture(Theme.color("bg", 0.8))
  end)
  btn:SetScript("OnEnter", onEnter)
  btn:SetScript("OnLeave", ns.HideTooltip)
  btn:SetScript("OnClick", onClick)
  return btn
end

local function paintButton(btn)
  local id = btn.itemId
  local quality = ns.ItemInfo.quality("item:" .. id)
  btn.icon:SetTexture(itemIcon(id) or QUESTION)
  if quality then
    btn.edge:SetColorTexture(ns.ItemInfo.qualityColor(quality))
    btn.painted = "quality"
  else
    btn.edge:SetColorTexture(Theme.color("textMuted"))
    btn.painted = "pending"
    -- Asks the client for the data once; GET_ITEM_INFO_RECEIVED repaints.
    itemName(id)
  end
  btn.chanceText:SetText(btn.chance and (RL.Percent(btn.chance) .. "%") or "")
  btn.strip:SetShown(btn.chance ~= nil)
end

local function refreshRow(row)
  for i = 1, row.count do
    paintButton(row.buttons[i])
  end
end

local function setItems(row, list)
  list = list or {}
  local count = math.min(#list, RL.CARD_MAX_ITEMS)
  local size, gap, columns = row.size, row.gap, row.columns
  row.count = count
  for i = 1, math.max(count, #row.buttons) do
    local btn = row.buttons[i]
    local item = list[i]
    if i <= count then
      if not btn then
        btn = newButton(row, size)
        row.buttons[i] = btn
      end
      btn.itemId, btn.chance = item.id, item.chance
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", ((i - 1) % columns) * (size + gap), -math.floor((i - 1) / columns) * (size + gap))
      btn:Show()
    elseif btn then
      btn.itemId, btn.chance = nil, nil
      btn:Hide()
    end
  end
  refreshRow(row)
  local cols = math.min(count, columns)
  local lines = math.ceil(count / columns)
  local width = cols > 0 and cols * size + (cols - 1) * gap or 0
  local height = lines > 0 and lines * size + (lines - 1) * gap or 0
  row:SetSize(math.max(width, 1), math.max(height, 1))
  return width, height
end

function RC.ItemRow(parent, opts)
  opts = opts or {}
  local row = CreateFrame("Frame", nil, parent)
  row.size, row.gap, row.columns = opts.size or 34, opts.gap or 4, opts.columns or 6
  row.buttons, row.count = {}, 0
  row.SetItems, row.Refresh = setItems, refreshRow
  rows[row] = true
  return row
end

ns.On("GET_ITEM_INFO_RECEIVED", function()
  for row in pairs(rows) do
    if row:IsVisible() then
      refreshRow(row)
    end
  end
end)

-- The card ----------------------------------------------------------------------------------------------

local card

-- The portrait shows the creature's head once the client reports a model file; a creature it cannot draw
-- keeps the rare symbol in the box.
local function modelReady(model)
  local fn = model.GetModelFileID
  if type(fn) ~= "function" then
    return true
  end
  local ok, file = pcall(fn, model)
  return ok and type(file) == "number" and file > 0
end

local function showModel(model)
  pcall(model.SetPortraitZoom, model, 1)
  model:Show()
  card.portraitIcon:Hide()
end

local function setPortrait(rare, id)
  local model = card.model
  RC.SetIcon(card.portraitIcon, rare, RC.Standing(id))
  card.portraitIcon:Show()
  if not model then
    return
  end
  model:Hide()
  if type(id) ~= "number" then
    return
  end
  local ok = pcall(function()
    model:ClearModel()
    model:SetCreature(id)
  end)
  if ok and modelReady(model) then
    showModel(model)
  end
end

local function buildPortrait()
  local box = CreateFrame("Frame", nil, card)
  box:SetSize(PORTRAIT, PORTRAIT)
  box:SetPoint("TOPLEFT", PAD, -PAD)
  W.Fill(box, "bg", 1)
  W.Border(box, "white")
  card.portrait = box
  card.portraitIcon = box:CreateTexture(nil, "ARTWORK")
  card.portraitIcon:SetPoint("CENTER")
  card.portraitIcon:SetSize(PORTRAIT - 20, PORTRAIT - 20)
  local ok, model = pcall(CreateFrame, "PlayerModel", nil, box)
  if ok and model then
    model:SetPoint("TOPLEFT", 1, -1)
    model:SetPoint("BOTTOMRIGHT", -1, 1)
    model:EnableMouse(false)
    model:SetScript("OnModelLoaded", function(self)
      if modelReady(self) then
        showModel(self)
      end
    end)
    model:Hide()
    card.model = model
  end
end

local function build()
  card = CreateFrame("Frame", nil, UIParent)
  card:SetFrameStrata("FULLSCREEN_DIALOG")
  card:SetClampedToScreen(true)
  card:EnableMouse(true)
  card:SetWidth(CARD_WIDTH)
  W.Fill(card, "surface", 1)
  W.Border(card, "white")
  buildPortrait()
  card.name = W.Text(card, { role = "h3", family = "heading", color = "accent2", wrap = true })
  card.name:SetPoint("TOPLEFT", PAD + PORTRAIT + 8, -PAD)
  card.name:SetWidth(CARD_WIDTH - 2 * PAD - PORTRAIT - 8 - 18)
  card.head = W.Text(card, { role = "body", color = "textSecondary" })
  card.status = W.Text(card, { role = "small", color = "textMuted" })
  card.hint = W.Text(card, { role = "small", color = "textMuted", key = "rare.card.pin" })
  card.close = W.CloseButton(card, {
    onClick = function()
      RC.Hide()
    end,
  })
  card.close:Hide()
  card.loot = W.Text(card, { role = "small", color = "textMuted", key = "rare.tip.loot" })
  card.row = RC.ItemRow(card)
  card:SetScript("OnUpdate", function(self, dt)
    self.acc = (self.acc or 0) + (tonumber(dt) or 0)
    if self.acc < TICK then
      return
    end
    self.acc = 0
    if self.pinned then
      RC.Check()
      return
    end
    local owner = self.owner
    local over = owner and owner:IsVisible() and (owner:IsMouseOver() or self:IsMouseOver())
    local hide
    hide, self.idleSince = RL.CardHold(over == true, self.idleSince, clock(), RL.CARD_HIDE_DELAY)
    if hide then
      RC.Hide()
    else
      RC.Check()
    end
  end)
  if ns.WindowShell and ns.WindowShell.RegisterEsc then
    ns.WindowShell.RegisterEsc(card, function()
      RC.Hide()
      return true
    end)
  end
  card:Hide()
  return card
end

function RC.Frame()
  return card
end

local listeners = {}

function RC.OnChange(fn)
  listeners[#listeners + 1] = fn
end

local function changed()
  local open = card and card:IsShown()
  for _, fn in ipairs(listeners) do
    ns.Safe("rare-card-change", fn, open and card.rare or nil, open and card.owner or nil, open and card.pinned)
  end
end

-- Only a pinned card takes part in the Esc stack.
local function setEsc(on)
  if card and ns.WindowShell and ns.WindowShell.SetEsc then
    ns.WindowShell.SetEsc(card, on)
  end
end

function RC.IsPinned()
  return card ~= nil and card.pinned == true and card:IsShown()
end

function RC.Hide()
  if not card then
    return
  end
  local wasShown = card:IsShown()
  card:Hide()
  card.owner, card.rare, card.pinned = nil, nil, false
  if wasShown then
    setEsc(false)
    changed()
  end
end

function RC.Check()
  if card and card:IsShown() then
    local owner = card.owner
    if not owner or not owner:IsVisible() or owner.rare ~= card.rare then
      RC.Hide()
    end
  end
end

-- Texts and sizes, top to bottom.
-- compact: the minimap card, portrait and texts only (the loot belongs to the world map card).
local function fill(rare, id, pinned, compact)
  card.name:SetText(RL.Name(rare, ns.GetActiveLocale()) or "")
  local nameHeight = tonumber(call(card.name.GetStringHeight, card.name)) or 16
  card.head:ClearAllPoints()
  card.head:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
  card.head:SetText(RL.CardHead(rare, L))
  setPortrait(rare, id)
  -- Name and level sit next to the portrait, the rest runs under it at full width.
  local top = PAD + math.max(PORTRAIT, nameHeight + 2 + 16)
  local status, seenAt, killAt = RC.Standing(id)
  card.status:ClearAllPoints()
  card.status:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -(top + 6))
  local lines = { id and RL.StatusLine(status, seenAt, killAt, serverNow(), ageText, L) or "" }
  local others = RL.OtherCount(rare)
  if others > 0 then
    lines[#lines + 1] = string.format(L["rare.card.spawns"], others)
  end
  card.status:SetText(table.concat(lines, "\n"))
  local height = top + 6 + 14 * #lines
  local items = compact and {} or RL.CardItems(rare)
  card.loot:SetShown(#items > 0)
  card.row:SetShown(#items > 0)
  local last = card.status
  if #items > 0 then
    card.loot:ClearAllPoints()
    card.loot:SetPoint("TOPLEFT", card.status, "BOTTOMLEFT", 0, -8)
    card.row:ClearAllPoints()
    card.row:SetPoint("TOPLEFT", card.loot, "BOTTOMLEFT", 0, -4)
    local _, rowHeight = card.row:SetItems(items)
    height = height + 8 + 14 + 4 + rowHeight
    last = card.row
  end
  card.hint:SetShown(not pinned)
  card.close:SetShown(pinned)
  if not pinned then
    card.hint:ClearAllPoints()
    card.hint:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -6)
    height = height + 6 + 14
  end
  card:SetHeight(height + PAD)
end

local function open(owner, rare, id, pinned)
  if not (owner and type(rare) == "table") then
    return
  end
  card = card or build()
  card.owner, card.rare, card.idleSince, card.acc, card.pinned = owner, rare, nil, 0, pinned
  fill(rare, id, pinned, owner.rareSource == "mini")
  card:ClearAllPoints()
  card:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", -6, -6)
  card:Show()
  setEsc(pinned)
  changed()
end

function RC.Show(owner, rare, id)
  if card and card.pinned and card:IsShown() then
    return
  end
  open(owner, rare, id, false)
end

function RC.Pin(owner, rare, id)
  open(owner, rare, id, true)
end
