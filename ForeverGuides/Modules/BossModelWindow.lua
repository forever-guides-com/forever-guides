-- The 3D model of a boss in a small floating window (shell of every window of the addon, a PlayerModel inside).
-- The display ID comes from Data/BossModels.lua (ns.DataApi.BossModel), a boss without one gets a note instead
-- of a model. Drag turns the model, the mouse wheel zooms, the buttons do the same from the keyboard, "Reset"
-- restores the view. One window, reused for the next boss. Nothing here is protected, so it works in combat.
-- BM.Hotspot(parent, region) makes the portrait or the name of a boss row the click target.
local _, ns = ...
local W, L = ns.W, ns.L

local BM = {}
ns.BossModelWindow = BM

ns.AddLocale("enUS", {
  ["bossmodel.title"] = "Boss model",
  ["bossmodel.view"] = "View 3D model",
  ["bossmodel.viewTip"] = "Opens the model of this boss in a window.",
  ["bossmodel.unknown"] = "Model not known.",
  ["bossmodel.failed"] = "The client could not load this model.",
  ["bossmodel.unsupported"] = "3D models are not available in this client.",
  ["bossmodel.display"] = "Display ID %d",
  ["bossmodel.hint"] = "Drag to turn, mouse wheel to zoom.",
  ["bossmodel.reset"] = "Reset",
  ["bossmodel.left"] = "Turn left",
  ["bossmodel.right"] = "Turn right",
  ["bossmodel.in"] = "Zoom in",
  ["bossmodel.out"] = "Zoom out",
  ["bossmodel.close"] = "Close boss model",
})
ns.AddLocale("deDE", {
  ["bossmodel.title"] = "Boss-Modell",
  ["bossmodel.view"] = "3D-Modell ansehen",
  ["bossmodel.viewTip"] = "Öffnet das Modell dieses Bosses in einem Fenster.",
  ["bossmodel.unknown"] = "Modell nicht bekannt.",
  ["bossmodel.failed"] = "Der Client konnte dieses Modell nicht laden.",
  ["bossmodel.unsupported"] = "3D-Modelle sind in diesem Client nicht verfügbar.",
  ["bossmodel.display"] = "Display-ID %d",
  ["bossmodel.hint"] = "Ziehen dreht, Mausrad zoomt.",
  ["bossmodel.reset"] = "Zurücksetzen",
  ["bossmodel.left"] = "Nach links drehen",
  ["bossmodel.right"] = "Nach rechts drehen",
  ["bossmodel.in"] = "Näher heranzoomen",
  ["bossmodel.out"] = "Weiter wegzoomen",
  ["bossmodel.close"] = "Boss-Modell schließen",
})

local WIDTH, HEIGHT, TITLE_H, PAD = 320, 460, 24, 12
local TURN_PER_PIXEL, TURN_STEP = 0.01, 0.3
local DIST_MIN, DIST_MAX, DIST_STEP = 0.4, 2.5, 0.15
local ZOOM_STEP = 0.1

local frame
local view = { facing = 0, dist = 1, zoom = 0 }

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- Data ------------------------------------------------------------------------------------------

local function entryOf(inst, boss)
  local instance, name = inst and inst.n and inst.n.en, boss and boss.n and boss.n.en
  return instance and name and ns.DataApi.BossModel(instance, name) or nil
end

-- The display ID of a boss, nil without a model in the data.
function BM.DisplayId(inst, boss)
  local entry = entryOf(inst, boss)
  local id = entry and entry.display
  return type(id) == "number" and id > 0 and id or nil
end

function BM.Has(inst, boss)
  return BM.DisplayId(inst, boss) ~= nil
end

-- View -----------------------------------------------------------------------------------------

local function applyView()
  local model = frame and frame.model
  if not model then
    return
  end
  pcall(model.SetFacing, model, view.facing)
  -- The camera distance when the client has it, else the portrait zoom.
  if type(model.SetCamDistanceScale) == "function" then
    pcall(model.SetCamDistanceScale, model, view.dist)
  elseif type(model.SetPortraitZoom) == "function" then
    pcall(model.SetPortraitZoom, model, view.zoom)
  end
end

function BM.Turn(delta)
  view.facing = (view.facing + delta) % (2 * math.pi)
  applyView()
end

-- direction 1 comes closer, -1 goes away.
function BM.Zoom(direction)
  view.dist = clamp(view.dist - direction * DIST_STEP, DIST_MIN, DIST_MAX)
  view.zoom = clamp(view.zoom + direction * ZOOM_STEP, 0, 1)
  applyView()
end

function BM.Reset()
  view.facing, view.dist, view.zoom = 0, 1, 0
  applyView()
end

-- Window ---------------------------------------------------------------------------------------

local function note(f, key)
  f.note:SetText(L[key])
  f.note:Show()
  if f.model then
    f.model:Hide()
  end
end

local function create()
  local f = CreateFrame("Frame", "FGBossModelWindow", UIParent)
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 240, 0)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  W.Fill(f, "bg", 0.97)
  local shell = ns.WindowShell.Attach(f, { title = "bossmodel.title", titleHeight = TITLE_H, shadow = true })
  local close = W.Action(shell.titleBar, { icon = "close", size = 18, tooltip = "bossmodel.close" })
  close:SetPoint("RIGHT", -4, 0)
  close:SetScript(
    "OnClick",
    ns.Wrap("bossmodel-close", function()
      f:Hide()
    end)
  )
  shell.titleText:ClearAllPoints()
  shell.titleText:SetPoint("LEFT", 8, 0)
  shell.titleText:SetPoint("RIGHT", close, "LEFT", -4, 0)

  f.name = W.Text(f, { role = "h3", color = "accent2", wrap = true })
  f.name:SetPoint("TOPLEFT", PAD, -(TITLE_H + 10))
  f.name:SetWidth(WIDTH - 2 * PAD)
  f.instance = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  f.instance:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -2)
  f.instance:SetWidth(WIDTH - 2 * PAD)

  local holder = CreateFrame("Frame", nil, f)
  holder:SetPoint("TOPLEFT", PAD, -(TITLE_H + 62))
  holder:SetPoint("BOTTOMRIGHT", -PAD, 96)
  W.Fill(holder, "surface", 1)
  f.holder = holder
  f.note = W.Text(holder, { role = "ui", color = "textSecondary", wrap = true, justify = "CENTER" })
  f.note:SetPoint("LEFT", 12, 0)
  f.note:SetPoint("RIGHT", -12, 0)
  f.note:Hide()

  -- A client without the frame type or without display IDs shows the note, never an error.
  local ok, model = pcall(CreateFrame, "PlayerModel", nil, holder)
  if ok and type(model) == "table" and type(model.SetDisplayInfo) == "function" then
    f.model = model
    model:SetAllPoints()
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    local dragging, lastX = false, 0
    model:SetScript("OnMouseDown", function(_, button)
      if button == "LeftButton" then
        dragging, lastX = true, (GetCursorPosition())
      end
    end)
    model:SetScript("OnMouseUp", function()
      dragging = false
    end)
    model:SetScript("OnHide", function()
      dragging = false
    end)
    model:SetScript(
      "OnUpdate",
      ns.Wrap("bossmodel-turn", function()
        if dragging then
          local x = GetCursorPosition()
          if x ~= lastX then
            BM.Turn((x - lastX) * TURN_PER_PIXEL)
            lastX = x
          end
        end
      end)
    )
    model:SetScript(
      "OnMouseWheel",
      ns.Wrap("bossmodel-zoom", function(_, delta)
        BM.Zoom(delta > 0 and 1 or -1)
      end)
    )
    -- The client resets the camera when the model has loaded.
    model:SetScript("OnModelLoaded", applyView)
  else
    f.unsupported = true
  end

  f.display = W.Text(f, { role = "micro", color = "textMuted", wrap = true })
  f.display:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -6)
  f.display:SetWidth(WIDTH - 2 * PAD)
  f.hint = W.Text(f, { key = "bossmodel.hint", role = "micro", color = "textMuted", wrap = true })
  f.hint:SetPoint("TOPLEFT", f.display, "BOTTOMLEFT", 0, -2)
  f.hint:SetWidth(WIDTH - 2 * PAD)

  local function button(spec, left)
    local b = W.Action(f, { text = spec.text, key = spec.key, tooltip = spec.tooltip, height = 24, width = spec.width })
    b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", left, PAD)
    b:SetScript(
      "OnClick",
      ns.Wrap("bossmodel-button", function()
        spec.run()
      end)
    )
    return b
  end
  local x = PAD
  local specs = {
    {
      text = "<",
      tooltip = "bossmodel.left",
      width = 34,
      run = function()
        BM.Turn(-TURN_STEP)
      end,
    },
    {
      text = ">",
      tooltip = "bossmodel.right",
      width = 34,
      run = function()
        BM.Turn(TURN_STEP)
      end,
    },
    {
      text = "+",
      tooltip = "bossmodel.in",
      width = 34,
      run = function()
        BM.Zoom(1)
      end,
    },
    {
      text = "-",
      tooltip = "bossmodel.out",
      width = 34,
      run = function()
        BM.Zoom(-1)
      end,
    },
  }
  f.buttons = {}
  for _, spec in ipairs(specs) do
    f.buttons[#f.buttons + 1] = button(spec, x)
    x = x + spec.width + 6
  end
  f.reset = button({ key = "bossmodel.reset", width = 110, run = BM.Reset }, WIDTH - PAD - 110)

  f:SetScript("OnShow", function()
    f:SetScale(ns.Theme.windowScale())
    f:Raise()
    ns.WindowShell.FitToScreen(f)
  end)
  ns.WindowShell.RegisterEsc(f)
  f:Hide()
  return f
end

function BM.Frame()
  return frame
end

-- Shows the model of the boss (inst and boss are entries of Data.Instances) and returns the window.
function BM.Open(inst, boss)
  if not (inst and boss) then
    return nil
  end
  if not frame then
    frame = create()
  end
  frame.inst, frame.boss = inst, boss
  frame.name:SetText(ns.T(boss.n) or "?")
  frame.instance:SetText(ns.T(inst.n) or "?")
  local display = BM.DisplayId(inst, boss)
  frame.display:SetText(display and string.format(L["bossmodel.display"], display) or "")
  frame.note:Hide()
  frame.displayId = nil
  if frame.unsupported then
    note(frame, "bossmodel.unsupported")
  elseif not display then
    note(frame, "bossmodel.unknown")
  else
    local model = frame.model
    local ok = pcall(function()
      model:ClearModel()
      model:SetDisplayInfo(display)
    end)
    if ok then
      model:Show()
      frame.displayId = display
    else
      note(frame, "bossmodel.failed")
    end
  end
  -- Every boss starts with the default view.
  BM.Reset()
  frame:Show()
  return frame
end

function BM.Close()
  if frame then
    frame:Hide()
  end
end

-- Click targets ------------------------------------------------------------------------------

-- A transparent button over `region` (the portrait or the name of a boss row). It is only shown for a boss
-- with a model: b:SetBoss(inst, boss) sets the boss and shows or hides it. keyboard = true makes it a stop of
-- the keyboard walk (Enter opens the model).
function BM.Hotspot(parent, region, keyboard)
  local b = CreateFrame("Button", nil, parent)
  b:SetAllPoints(region)
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.08)
  local function open(self)
    BM.Open(self.inst, self.boss)
  end
  b:SetScript("OnClick", ns.Wrap("bossmodel-open", open))
  W.AttachTooltip(b, "bossmodel.view", "bossmodel.viewTip")
  if keyboard then
    ns.Focus.register(b, open)
  end
  function b:SetBoss(inst, boss)
    self.inst, self.boss = inst, boss
    self:SetShown(BM.Has(inst, boss))
  end
  b:Hide()
  return b
end
