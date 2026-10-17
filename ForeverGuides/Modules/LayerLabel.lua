-- Layer label at the minimap (the layer itself comes from Layer.lua), the settings card "Layer" and the
-- command /fg layer. The label is a child of whatever the global Minimap is and only reads its centre, never
-- its name or size, so a rebuilt minimap moves it along and a missing one means no label.
-- It can be dragged with the left mouse button (out of combat); a left click opens or closes the layer
-- window (LayerWindow.lua), a right click reads the layer again.
local _, ns = ...
local Guard, L, Layer = ns.AutoGuard, ns.L, ns.Layer
local Theme, W = ns.Theme, ns.W

local Label = {}
ns.LayerLabel = Label

ns.AddLocale("enUS", {
  ["layer.label"] = "Layer %d",
  ["layer.unknown"] = "Layer ?",
  ["layer.age.sec"] = "%d s ago",
  ["layer.age.min"] = "%d min ago",
  ["layer.age.hour"] = "%d h ago",
  ["layer.source.target"] = "Target",
  ["layer.source.mouseover"] = "Mouseover",
  ["layer.source.focus"] = "Focus",
  ["layer.source.softenemy"] = "Soft target (enemy)",
  ["layer.source.softfriend"] = "Soft target (friend)",
  ["layer.source.softinteract"] = "Soft target (interact)",
  ["layer.source.nameplate"] = "Name plate",
  ["layer.source.gossip"] = "NPC dialog",
  ["layer.source.merchant"] = "Merchant",
  ["layer.tip.zone"] = "Zone: %s",
  ["layer.tip.confirmed"] = "Confirmed: %s",
  ["layer.tip.source"] = "Source: %s",
  ["layer.tip.previous"] = "Previous layer: %d",
  ["layer.tip.none"] = "No layer read in this zone yet. Target any NPC or move the mouse over one.",
  ["layer.tip.zoneOnly"] = "Layer IDs only apply within one zone.",
  ["layer.tip.hint"] = "Left click: open window, right click: read again, drag: move",
  ["layer.none"] = "No NPC in sight, target one or move the mouse over one",
  ["layer.summary"] = "%s in %s, confirmed %s, source: %s",
  ["layer.blocked.combat"] = "Not changeable in combat.",
  ["layer.set.heading"] = "Layer",
  ["layer.set.show"] = "Show layer at the minimap",
  ["layer.set.hint"] = "The layer is read from the NPCs you see: target one, move the mouse over one or open its dialog. Drag the label to move it, click it to open the window.",
  ["layer.set.open"] = "Open layer window",
  ["layer.set.reset"] = "Reset position",
})
ns.AddLocale("deDE", {
  ["layer.label"] = "Layer %d",
  ["layer.unknown"] = "Layer ?",
  ["layer.age.sec"] = "vor %d s",
  ["layer.age.min"] = "vor %d min",
  ["layer.age.hour"] = "vor %d h",
  ["layer.source.target"] = "Ziel",
  ["layer.source.mouseover"] = "Maus",
  ["layer.source.focus"] = "Fokus",
  ["layer.source.softenemy"] = "Weiches Ziel (Feind)",
  ["layer.source.softfriend"] = "Weiches Ziel (Freund)",
  ["layer.source.softinteract"] = "Weiches Ziel (Interaktion)",
  ["layer.source.nameplate"] = "Namensplakette",
  ["layer.source.gossip"] = "NPC-Dialog",
  ["layer.source.merchant"] = "Händler",
  ["layer.tip.zone"] = "Zone: %s",
  ["layer.tip.confirmed"] = "Bestätigt: %s",
  ["layer.tip.source"] = "Quelle: %s",
  ["layer.tip.previous"] = "Vorheriger Layer: %d",
  ["layer.tip.none"] = "In dieser Zone wurde noch kein Layer gelesen. Anvisiere irgendeinen NPC oder geh mit der Maus darüber.",
  ["layer.tip.zoneOnly"] = "Layer-IDs gelten nur innerhalb einer Zone.",
  ["layer.tip.hint"] = "Linksklick: Fenster öffnen, Rechtsklick: neu einlesen, Ziehen: verschieben",
  ["layer.none"] = "Kein NPC in Sicht, anvisieren oder mit der Maus darüber gehen",
  ["layer.summary"] = "%s in %s, bestätigt %s, Quelle: %s",
  ["layer.blocked.combat"] = "Im Kampf nicht änderbar.",
  ["layer.set.heading"] = "Layer",
  ["layer.set.show"] = "Layer an der Minimap anzeigen",
  ["layer.set.hint"] = "Der Layer wird aus NPCs gelesen, die du siehst: anvisieren, mit der Maus darüber gehen oder den Dialog öffnen. Ziehe das Etikett, um es zu verschieben, ein Klick öffnet das Fenster.",
  ["layer.set.open"] = "Layer-Fenster öffnen",
  ["layer.set.reset"] = "Position zurücksetzen",
})

-- Saved offsets beyond this many pixels from the minimap centre count as damaged.
local LIMIT = 1000
local PAD_X, PAD_Y = 6, 3
local BG_ALPHA, BG_ALPHA_CONTRAST = 0.75, 0.95
local FLASH_ALPHA, FLASH_SECONDS = 0.5, 1.5

local label
-- The switches of the settings card, repainted when a setting changes behind their back (a helper that
-- switched itself off).
local netToggles = {}
-- True from the start of a drag to the next mouse down: the click that ends a drag moves, it does not read.
local dragged = false

local function settings()
  return (ns.db and ns.db.settings) or {}
end

local function finite(value)
  return type(value) == "number" and value == value and math.abs(value) <= LIMIT
end

-- Saved offset of the label centre from the minimap centre; nil (default place) when absent or damaged.
function Label.Position()
  local saved = settings().layerPos
  if type(saved) == "table" and finite(saved.x) and finite(saved.y) then
    return saved.x, saved.y
  end
  return nil
end

local function place(x, y)
  local minimap = rawget(_G, "Minimap")
  label:ClearAllPoints()
  if x then
    label:SetPoint("CENTER", minimap, "CENTER", x, y)
  else
    label:SetPoint("BOTTOM", minimap, "BOTTOM", 0, 4)
  end
end

-- Texts -----------------------------------------------------------------------------------------------------

function Label.Summary()
  local layer, mapId, _, source = Layer.Get()
  if not layer then
    return L["layer.tip.none"]
  end
  return string.format(
    L["layer.summary"],
    Layer.Text(),
    Layer.ZoneName(mapId),
    Layer.Age() or "?",
    L["layer.source." .. tostring(source)]
  )
end

local function showTooltip(owner)
  local layer, mapId, _, source, previous = Layer.Get()
  local lines = {}
  if layer then
    lines[#lines + 1] = string.format(L["layer.tip.zone"], Layer.ZoneName(mapId))
    lines[#lines + 1] = string.format(L["layer.tip.confirmed"], Layer.Age() or "?")
    lines[#lines + 1] = string.format(L["layer.tip.source"], L["layer.source." .. tostring(source)])
    if previous then
      lines[#lines + 1] = string.format(L["layer.tip.previous"], previous)
    end
  else
    lines[#lines + 1] = L["layer.tip.none"]
  end
  lines[#lines + 1] = { text = L["layer.tip.zoneOnly"], color = "textMuted" }
  W.Tooltip.Show(owner, { title = Layer.Text(), lines = lines, hint = L["layer.tip.hint"], anchor = "ANCHOR_LEFT" })
end

-- Label ------------------------------------------------------------------------------------------------------

-- Fits the label to its text, and paints the background that keeps the text readable on any map.
local function paint()
  label.text:SetTextColor(Theme.color("text"))
  label.bg:SetColorTexture(0, 0, 0, Theme.highContrast() and BG_ALPHA_CONTRAST or BG_ALPHA)
  label:SetSize(math.ceil(label.text:GetStringWidth()) + 2 * PAD_X, math.ceil(label.text:GetStringHeight()) + 2 * PAD_Y)
end

local function flash()
  if Theme.reduceMotion() then
    return
  end
  label.flash:Show()
  label.flashGroup:Stop()
  label.flashGroup:Play()
end

local function stopDrag(self)
  self:SetScript("OnUpdate", nil)
end

local function onDragStart(self)
  local minimap = rawget(_G, "Minimap")
  if Guard.Blocked() then
    return
  end
  -- Distance between the label centre and the cursor, so the label does not jump to the cursor.
  local ok, grabX, grabY = pcall(function()
    local lx, ly = self:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = minimap:GetEffectiveScale()
    return lx - cx / scale, ly - cy / scale
  end)
  if not (ok and finite(grabX) and finite(grabY)) then
    return
  end
  dragged = true
  self:SetScript("OnUpdate", function()
    if Guard.Blocked() then
      return stopDrag(self)
    end
    local moved = pcall(function()
      local mx, my = minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = minimap:GetEffectiveScale()
      self.dragX = ns.U.clamp(cx / scale + grabX - mx, -LIMIT, LIMIT)
      self.dragY = ns.U.clamp(cy / scale + grabY - my, -LIMIT, LIMIT)
      place(self.dragX, self.dragY)
    end)
    if not moved then
      stopDrag(self)
    end
  end)
end

local function onDragStop(self)
  stopDrag(self)
  if self.dragX then
    ns.Store.set("settings.layerPos", { x = self.dragX, y = self.dragY })
  end
  self.dragX, self.dragY = nil, nil
end

-- Reads the layer again and says what came of it.
function Label.Read()
  if Layer.Refresh() then
    ns.Notify(Layer.Text(), "success", { force = true })
  else
    ns.Notify(L["layer.none"], "warning")
  end
end

function Label.Toggle()
  ns.LayerWindow.Toggle()
end

local function create(minimap)
  label = CreateFrame("Button", "ForeverGuidesLayerLabel", minimap)
  label:SetFrameStrata("MEDIUM")
  label:SetFrameLevel(9)
  label:SetClampedToScreen(true)
  label:EnableMouse(true)
  label:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  label:RegisterForDrag("LeftButton")
  label.bg = label:CreateTexture(nil, "BACKGROUND")
  label.bg:SetAllPoints()
  label.flash = label:CreateTexture(nil, "ARTWORK")
  label.flash:SetAllPoints()
  label.flash:SetColorTexture(Theme.rgb("accent2"))
  label.flash:Hide()
  label.flashGroup = label.flash:CreateAnimationGroup()
  local fade = label.flashGroup:CreateAnimation("Alpha")
  fade:SetFromAlpha(FLASH_ALPHA)
  fade:SetToAlpha(0)
  fade:SetDuration(FLASH_SECONDS)
  label.flashGroup:SetScript("OnFinished", function()
    label.flash:Hide()
  end)
  label.text = W.Text(label, { role = "small", color = "text", justify = "CENTER" })
  label.text:SetJustifyV("MIDDLE")
  label.text:SetPoint("CENTER")
  label:SetScript("OnMouseDown", function()
    dragged = false
  end)
  label:SetScript("OnClick", function(_, button)
    if dragged then
      return
    end
    if button == "LeftButton" then
      ns.Safe("layer-click", Label.Toggle)
    elseif button == "RightButton" then
      ns.Safe("layer-read", Label.Read)
    end
  end)
  label:SetScript("OnDragStart", ns.Wrap("layer-drag", onDragStart))
  label:SetScript("OnDragStop", ns.Wrap("layer-drag", onDragStop))
  label:SetScript("OnEnter", ns.Wrap("layer-tooltip", showTooltip))
  label:SetScript("OnLeave", ns.HideTooltip)
  place(Label.Position())
end

-- The label that sits on the minimap now: made on first use, moved over when the minimap was replaced.
-- nil without a minimap.
local function ensure()
  local minimap = rawget(_G, "Minimap")
  if type(minimap) ~= "table" then
    return nil
  end
  if not label then
    create(minimap)
  elseif label:GetParent() ~= minimap then
    label:SetParent(minimap)
    place(Label.Position())
  end
  return label
end

function Label.Frame()
  return label
end

-- Brings the label in line with the setting and the layer.
function Label.Apply()
  if settings().layerShow == false then
    if label then
      label:Hide()
    end
    return
  end
  if not ensure() then
    return
  end
  W.SetText(label.text, nil, Layer.Text())
  paint()
  label:Show()
end

function Label.ResetPosition()
  if Guard.Blocked() then
    ns.Notify(L["layer.blocked.combat"], "warning")
    return false
  end
  ns.Store.set("settings.layerPos", nil)
  if label then
    place(nil)
  end
  return true
end

-- /fg layer shows the layer, /fg layer refresh (neu) reads it again first.
function Label.Slash(rest)
  local word = (rest or ""):lower()
  if word == "refresh" or word == "neu" then
    Layer.Refresh()
  end
  ns.Notify(Label.Summary(), Layer.Get() and "info" or "warning", { force = true })
end

-- Settings ---------------------------------------------------------------------------------------------------

function Label.AddSettings(card)
  ns.AddHeading(card, "layer.set.heading")
  local toggle = W.Toggle(card.content, {
    key = "layer.set.show",
    get = function()
      return settings().layerShow ~= false
    end,
    set = function(on)
      ns.Store.set("settings.layerShow", on == true)
    end,
  })
  toggle.fgId = "layer-show"
  card.stack:Add(toggle, { height = 24, gap = 6 })
  ns.AddParagraph(card, "layer.set.hint", { role = "micro", color = "textMuted", gap = 8 })
  -- The opt-ins of the layer network: same switches as in the window, both off until the player asks.
  netToggles = {}
  for _, def in ipairs({
    { "layer.net.share", "layer.net.shareTip", "layerShare", ns.LayerNet.SetShare },
    { "layer.net.host", "layer.net.hostTip", "layerHost", ns.LayerNet.SetHost },
  }) do
    local control = W.Toggle(card.content, {
      key = def[1],
      tooltip = def[1],
      tooltipText = def[2],
      get = function()
        return settings()[def[3]] == true
      end,
      set = function(on)
        def[4](on)
      end,
    })
    control.fgId = "layer-" .. def[3]
    netToggles[#netToggles + 1] = control
    card.stack:Add(control, { height = 24, gap = 6 })
  end
  ns.AddParagraph(card, "layer.net.privacy", { role = "micro", color = "textMuted", gap = 8 })
  local open = W.Button(card.content, {
    key = "layer.set.open",
    width = 220,
    onClick = ns.LayerWindow.Open,
  })
  open.fgId = "layer-open"
  card.stack:Add(open, { height = 28, width = 220, gap = 8 })
  local reset = W.Button(card.content, {
    key = "layer.set.reset",
    width = 220,
    onClick = Label.ResetPosition,
  })
  reset.fgId = "layer-reset"
  card.stack:Add(reset, { height = 28, width = 220, gap = 14 })
end

-- Events -----------------------------------------------------------------------------------------------------

-- A layer that was there before and is another one now: the label lights up once.
ns.On("FG_LAYER_CHANGED", function(_, layer, old)
  Label.Apply()
  if label and layer ~= nil and old ~= nil and settings().layerShow ~= false then
    flash()
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.layerShow" or path == "settings.layerPos" then
    Label.Apply()
  elseif path == "settings.layerShare" or path == "settings.layerHost" then
    for _, control in ipairs(netToggles) do
      control:Refresh()
    end
  end
end)
ns.On("FG_UI_REFRESHED", Label.Apply)
-- A finer map (a building, a cave) is another zone for the layer, so the text may turn into "Layer ?".
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
  ns.On(event, Label.Apply)
end

ns.SettingsPage.Add(Label.AddSettings, "map")
