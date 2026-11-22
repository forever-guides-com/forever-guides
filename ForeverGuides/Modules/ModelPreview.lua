-- One preview window for items, whole item sets and creatures (shell of every window of the addon).
-- Items and sets are tried on the player's own model (DressUpModel), creatures use a PlayerModel with a display
-- ID or an NPC ID. Drag turns the model, the mouse wheel zooms, the buttons do the same from the keyboard.
-- The models are created on the first use of their kind, the window is reused, OnUpdate runs only while dragging.
-- Nothing here is protected, so it opens and closes in combat. Without a model frame (or without a way to
-- show the creature) the window shows the icon and a note instead of an error.
--   MP.OpenItem(itemId)                    try on one item
--   MP.OpenSet({ name, items = { ids } })  try on all pieces of a set
--   MP.OpenCreature({ name, sub, displayId, npcId, icon })
--   MP.CanShowCreature(spec)               true when spec carries a display ID or an NPC ID
local _, ns = ...
local W, L = ns.W, ns.L

local MP = {}
ns.ModelPreview = MP

ns.AddLocale("enUS", {
  ["preview.title"] = "Preview",
  ["preview.item"] = "Item",
  ["preview.set"] = "%d pieces",
  ["preview.hint"] = "Drag to turn, mouse wheel to zoom.",
  ["preview.reset"] = "Reset",
  ["preview.undress"] = "Undress",
  ["preview.undressTip"] = "Takes off your gear so only the previewed pieces show.",
  ["preview.left"] = "Turn left",
  ["preview.right"] = "Turn right",
  ["preview.in"] = "Zoom in",
  ["preview.out"] = "Zoom out",
  ["preview.close"] = "Close preview",
  ["preview.display"] = "Display ID %d",
  ["preview.unknown"] = "No model known for this entry.",
  ["preview.failed"] = "The client could not load this model.",
  ["preview.unsupported"] = "3D models are not available in this client.",
  ["preview.open"] = "Preview",
  ["preview.openTip"] = "Opens the preview window.",
})
ns.AddLocale("deDE", {
  ["preview.title"] = "Vorschau",
  ["preview.item"] = "Item",
  ["preview.set"] = "%d Teile",
  ["preview.hint"] = "Ziehen dreht, Mausrad zoomt.",
  ["preview.reset"] = "Zurücksetzen",
  ["preview.undress"] = "Ausziehen",
  ["preview.undressTip"] = "Legt deine Ausrüstung ab, damit nur die Teile der Vorschau zu sehen sind.",
  ["preview.left"] = "Nach links drehen",
  ["preview.right"] = "Nach rechts drehen",
  ["preview.in"] = "Näher heranzoomen",
  ["preview.out"] = "Weiter wegzoomen",
  ["preview.close"] = "Vorschau schließen",
  ["preview.display"] = "Display-ID %d",
  ["preview.unknown"] = "Zu diesem Eintrag ist kein Modell bekannt.",
  ["preview.failed"] = "Der Client konnte dieses Modell nicht laden.",
  ["preview.unsupported"] = "3D-Modelle sind in diesem Client nicht verfügbar.",
  ["preview.open"] = "Vorschau",
  ["preview.openTip"] = "Öffnet das Vorschaufenster.",
})

local WIDTH, HEIGHT, TITLE_H, PAD = 360, 470, 24, 12
local TURN_PER_PIXEL, TURN_STEP = 0.01, 0.3
local DIST_MIN, DIST_MAX, DIST_STEP = 0.4, 2.5, 0.15
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.5, 2.5, 0.15

local frame
-- mode: "dress" or "creature". items: item IDs worn in dress mode.
local state = { mode = nil, items = {}, undressed = false, facing = 0, dist = 1, scale = 1, serial = 0 }

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function activeModel()
  if not frame then
    return nil
  end
  return state.mode == "dress" and frame.dress or state.mode == "creature" and frame.creature or nil
end

-- View -----------------------------------------------------------------------------------------

local function applyView()
  local model = activeModel()
  if not (model and model:IsShown()) then
    return
  end
  pcall(model.SetFacing, model, state.facing)
  if type(model.SetCamDistanceScale) == "function" then
    pcall(model.SetCamDistanceScale, model, state.dist)
  elseif type(model.SetModelScale) == "function" then
    pcall(model.SetModelScale, model, state.scale)
  end
end

function MP.Turn(delta)
  state.facing = (state.facing + delta) % (2 * math.pi)
  applyView()
end

-- direction 1 comes closer, -1 goes away.
function MP.Zoom(direction)
  state.dist = clamp(state.dist - direction * DIST_STEP, DIST_MIN, DIST_MAX)
  state.scale = clamp(state.scale + direction * SCALE_STEP, SCALE_MIN, SCALE_MAX)
  applyView()
end

-- Items ----------------------------------------------------------------------------------------

local function itemApi(name)
  local c = rawget(_G, "C_Item")
  return type(c) == "table" and c[name] or nil
end

-- The link the client wants for TryOn: its own when the item is cached, else the plain item string.
local function wearLink(id)
  local fn = itemApi("GetItemInfo") or rawget(_G, "GetItemInfo")
  if type(fn) == "function" then
    local ok, _, link = pcall(fn, id)
    if ok and type(link) == "string" and link ~= "" then
      return link
    end
  end
  return "item:" .. id
end

-- Takes off the own gear when asked and puts the previewed pieces on.
local function wear()
  local model = frame and frame.dress
  if not model then
    return
  end
  if state.undressed and type(model.Undress) == "function" then
    pcall(model.Undress, model)
  end
  for _, id in ipairs(state.items) do
    pcall(model.TryOn, model, wearLink(id))
  end
end

-- An item the client has not cached cannot be tried on yet: ask for it and wear again once it is there.
local function requestMissing()
  local serial = state.serial
  local item = rawget(_G, "Item")
  local info = itemApi("GetItemInfo") or rawget(_G, "GetItemInfo")
  if type(item) ~= "table" or type(item.CreateFromItemID) ~= "function" or type(info) ~= "function" then
    return
  end
  for _, id in ipairs(state.items) do
    local ok, name = pcall(info, id)
    if ok and name == nil then
      local made, obj = pcall(item.CreateFromItemID, item, id)
      if made and type(obj) == "table" and type(obj.ContinueOnItemLoad) == "function" then
        pcall(obj.ContinueOnItemLoad, obj, function()
          if serial == state.serial and state.mode == "dress" then
            wear()
          end
        end)
      end
    end
  end
end

local function dressFromScratch()
  local model = frame.dress
  pcall(function()
    model:SetUnit("player")
  end)
  wear()
  requestMissing()
end

-- Window ---------------------------------------------------------------------------------------

local function showNote(key)
  frame.note:SetText(L[key])
  frame.note:Show()
  if frame.dress then
    frame.dress:Hide()
  end
  if frame.creature then
    frame.creature:Hide()
  end
end

local function attachInput(model)
  model:EnableMouse(true)
  model:EnableMouseWheel(true)
  local lastX = 0
  local function turn()
    local x = GetCursorPosition()
    if x ~= lastX then
      MP.Turn((x - lastX) * TURN_PER_PIXEL)
      lastX = x
    end
  end
  local function stop()
    model:SetScript("OnUpdate", nil)
  end
  model:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      lastX = (GetCursorPosition())
      model:SetScript("OnUpdate", ns.Wrap("preview-turn", turn))
    end
  end)
  model:SetScript("OnMouseUp", stop)
  model:SetScript("OnHide", stop)
  model:SetScript(
    "OnMouseWheel",
    ns.Wrap("preview-zoom", function(_, delta)
      MP.Zoom(delta > 0 and 1 or -1)
    end)
  )
end

-- Creates the model of one kind on its first use. Returns nil when the client has no such frame type.
local function makeModel(kind)
  local ok, model = pcall(CreateFrame, kind, nil, frame.holder)
  if not (ok and type(model) == "table") then
    return nil
  end
  model:SetAllPoints()
  attachInput(model)
  -- The client resets the camera when a model has loaded.
  model:SetScript("OnModelLoaded", function()
    if kind == "DressUpModel" then
      wear()
    end
    applyView()
  end)
  model:Hide()
  return model
end

local function create()
  local f = CreateFrame("Frame", "FGModelPreview", UIParent)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  W.Fill(f, "bg", 0.97)
  local shell = ns.WindowShell.Attach(f, { title = "preview.title", titleHeight = TITLE_H, shadow = true })
  local close = W.Action(shell.titleBar, { icon = "close", size = 18, tooltip = "preview.close" })
  close:SetPoint("RIGHT", -4, 0)
  close:SetScript(
    "OnClick",
    ns.Wrap("preview-close", function()
      f:Hide()
    end)
  )
  shell.titleText:ClearAllPoints()
  shell.titleText:SetPoint("LEFT", 8, 0)
  shell.titleText:SetPoint("RIGHT", close, "LEFT", -4, 0)

  f.name = W.Text(f, { role = "h3", color = "accent2", wrap = true })
  f.name:SetPoint("TOPLEFT", PAD, -(TITLE_H + 10))
  f.name:SetWidth(WIDTH - 2 * PAD)
  f.sub = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -2)
  f.sub:SetWidth(WIDTH - 2 * PAD)

  local holder = CreateFrame("Frame", nil, f)
  holder:SetPoint("TOPLEFT", PAD, -(TITLE_H + 62))
  holder:SetPoint("BOTTOMRIGHT", -PAD, 96)
  W.Fill(holder, "surface", 1)
  f.holder = holder
  f.icon = holder:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(48, 48)
  f.icon:SetPoint("CENTER", 0, 24)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.icon:Hide()
  f.note = W.Text(holder, { role = "ui", color = "textSecondary", wrap = true, justify = "CENTER" })
  f.note:SetPoint("LEFT", 12, -20)
  f.note:SetPoint("RIGHT", -12, -20)
  f.note:Hide()

  f.display = W.Text(f, { role = "micro", color = "textMuted", wrap = true })
  f.display:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -6)
  f.display:SetWidth(WIDTH - 2 * PAD)
  f.hint = W.Text(f, { key = "preview.hint", role = "micro", color = "textMuted", wrap = true })
  f.hint:SetPoint("TOPLEFT", f.display, "BOTTOMLEFT", 0, -2)
  f.hint:SetWidth(WIDTH - 2 * PAD)

  local function button(spec, left)
    local b = W.Action(f, { text = spec.text, key = spec.key, tooltip = spec.tooltip, height = 24, width = spec.width })
    b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", left, PAD)
    b:SetScript(
      "OnClick",
      ns.Wrap("preview-button", function()
        spec.run()
      end)
    )
    return b
  end
  local x = PAD
  for _, spec in ipairs({
    {
      text = "<",
      tooltip = "preview.left",
      run = function()
        MP.Turn(-TURN_STEP)
      end,
    },
    {
      text = ">",
      tooltip = "preview.right",
      run = function()
        MP.Turn(TURN_STEP)
      end,
    },
    {
      text = "+",
      tooltip = "preview.in",
      run = function()
        MP.Zoom(1)
      end,
    },
    {
      text = "-",
      tooltip = "preview.out",
      run = function()
        MP.Zoom(-1)
      end,
    },
  }) do
    spec.width = 34
    button(spec, x)
    x = x + 40
  end
  f.undress = button({
    key = "preview.undress",
    tooltip = "preview.undressTip",
    width = 90,
    run = function()
      MP.SetUndressed(not state.undressed)
    end,
  }, x + 6)
  f.reset = button({ key = "preview.reset", width = 90, run = MP.Reset }, WIDTH - PAD - 90)

  f:SetScript("OnShow", function()
    f:SetScale(ns.Theme.windowScale())
    f:Raise()
    ns.WindowShell.FitToScreen(f)
  end)
  ns.WindowShell.RegisterEsc(f)
  f:Hide()
  return f
end

local function ensureFrame()
  if not frame then
    frame = create()
  end
  return frame
end

function MP.Frame()
  return frame
end

function MP.Close()
  if frame then
    frame:Hide()
  end
end

function MP.IsUndressed()
  return state.undressed
end

function MP.SetUndressed(on)
  state.undressed = on == true
  if frame then
    frame.undress:SetSelected(state.undressed)
  end
  if state.mode == "dress" and frame and frame.dress then
    dressFromScratch()
  end
end

function MP.Reset()
  state.facing, state.dist, state.scale = 0, 1, 1
  if state.mode == "dress" and frame and frame.dress then
    state.undressed = false
    frame.undress:SetSelected(false)
    dressFromScratch()
  end
  applyView()
end

local function begin(mode, name, sub)
  ensureFrame()
  state.mode = mode
  state.serial = state.serial + 1
  state.facing, state.dist, state.scale = 0, 1, 1
  frame.name:SetText(name or "?")
  frame.sub:SetText(sub or "")
  frame.note:Hide()
  frame.icon:Hide()
  frame.display:SetText("")
  frame.undress:SetShown(mode == "dress")
  frame.undress:SetSelected(false)
  state.undressed = false
  if frame.dress then
    frame.dress:Hide()
  end
  if frame.creature then
    frame.creature:Hide()
  end
end

local function showIcon(icon)
  if icon then
    frame.icon:SetTexture(icon)
    frame.icon:Show()
  end
end

-- Item and set ---------------------------------------------------------------------------------

local function itemName(id)
  local fn = itemApi("GetItemNameByID")
  if type(fn) == "function" then
    local ok, name = pcall(fn, id)
    if ok and type(name) == "string" and name ~= "" then
      return name
    end
  end
  local info = itemApi("GetItemInfo") or rawget(_G, "GetItemInfo")
  if type(info) == "function" then
    local ok, name = pcall(info, id)
    if ok and type(name) == "string" and name ~= "" then
      return name
    end
  end
end

local function itemIcon(id)
  local fn = itemApi("GetItemIconByID") or rawget(_G, "GetItemIcon")
  if type(fn) == "function" then
    local ok, icon = pcall(fn, id)
    if ok and icon then
      return icon
    end
  end
end

local function openDress(name, sub, ids)
  begin("dress", name, sub)
  state.items = ids
  local dress = frame.dress
  if not dress and not frame.dressFailed then
    dress = makeModel("DressUpModel")
    frame.dress = dress
    frame.dressFailed = dress == nil
  end
  if dress then
    dress:Show()
    dressFromScratch()
    applyView()
  else
    -- No model frame: Blizzard's own dressing room does the job for one item.
    local show = rawget(_G, "DressUpItemLink") or rawget(_G, "DressUpLink")
    if type(show) == "function" and ids[1] then
      pcall(show, wearLink(ids[1]))
    end
    showIcon(itemIcon(ids[1]))
    showNote("preview.unsupported")
  end
  frame:Show()
  return frame
end

-- Tries on one item. Returns the window.
function MP.OpenItem(itemId)
  if type(itemId) ~= "number" then
    return nil
  end
  return openDress(itemName(itemId) or ("item " .. itemId), L["preview.item"], { itemId })
end

-- set: { name, items = { item IDs } }. Pieces without a valid ID are skipped.
function MP.OpenSet(set)
  local ids = {}
  for _, id in ipairs(set and set.items or {}) do
    if type(id) == "number" then
      ids[#ids + 1] = id
    end
  end
  if #ids == 0 then
    return nil
  end
  return openDress(set.name, string.format(L["preview.set"], #ids), ids)
end

-- Creature -------------------------------------------------------------------------------------

function MP.CanShowCreature(spec)
  return type(spec) == "table"
    and ((type(spec.displayId) == "number" and spec.displayId > 0) or (type(spec.npcId) == "number" and spec.npcId > 0))
end

-- spec: { name, sub, displayId, npcId, icon }. A display ID wins over the NPC ID.
function MP.OpenCreature(spec)
  if type(spec) ~= "table" then
    return nil
  end
  begin("creature", spec.name, spec.sub)
  local model = frame.creature
  if not model and not frame.creatureFailed then
    model = makeModel("PlayerModel")
    frame.creature = model
    frame.creatureFailed = model == nil
  end
  local display = type(spec.displayId) == "number" and spec.displayId > 0 and spec.displayId or nil
  local npc = type(spec.npcId) == "number" and spec.npcId > 0 and spec.npcId or nil
  if not model then
    showIcon(spec.icon)
    showNote("preview.unsupported")
  elseif not (display or npc) then
    showIcon(spec.icon)
    showNote("preview.unknown")
  else
    local ok = pcall(function()
      model:ClearModel()
      if display then
        model:SetDisplayInfo(display)
      else
        model:SetCreature(npc)
      end
    end)
    if ok then
      model:Show()
      frame.display:SetText(display and string.format(L["preview.display"], display) or "")
      applyView()
    else
      showIcon(spec.icon)
      showNote("preview.failed")
    end
  end
  frame:Show()
  return frame
end

-- A small "Preview" action for rows and cards. parent gets the button, run() opens the preview.
function MP.Action(parent, run)
  local b = W.Action(parent, { icon = "eye", size = 20, tooltip = "preview.open", tooltipText = "preview.openTip" })
  b:SetScript("OnClick", ns.Wrap("preview-open", run))
  return b
end
