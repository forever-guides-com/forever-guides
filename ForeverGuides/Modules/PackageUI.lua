-- Switching on and loading the add-ons next to this one (Professions, Recipes, GildenManager) from
-- the place that needs them. U.Enable does the work, U.Banner builds the one line (state text plus
-- button) that pages, windows and the settings show instead of a dead end.
-- Never in combat: EnableAddOn and LoadAddOn are not called then, the button is dimmed.
local _, ns = ...
local W, L = ns.W, ns.L

local U = {}
ns.PackageUI = U

local BUTTON_W = 190
local BUTTON_H = 24
local GAP = 8
-- From this width the button sits right of the text, narrower it goes below.
local SIDE_MIN = 460

ns.AddLocale("enUS", {
  ["pkg.missing"] = "Not installed",
  ["pkg.off"] = "Switched off",
  ["pkg.idle"] = "Switched on, not loaded",
  ["pkg.ready"] = "Loaded",
  ["pkg.restart"] = "Active at next game start, /reload is blocked",
  ["pkg.combat"] = "Not in combat",
  ["pkg.err.disabled"] = "Could not switch on",
  ["pkg.err.noApi"] = "Not possible in this client",
  ["pkg.err.failed"] = "Loading failed",
  ["pkg.enable"] = "Switch on and load",
  ["pkg.load"] = "Load data",
  ["pkg.copy"] = "Copy link",
  ["pkg.copy.title"] = "Download",
  ["pkg.copy.hint"] = "Open the link in your browser",
})
ns.AddLocale("deDE", {
  ["pkg.missing"] = "Nicht installiert",
  ["pkg.off"] = "Ausgeschaltet",
  ["pkg.idle"] = "An, noch nicht geladen",
  ["pkg.ready"] = "Geladen",
  ["pkg.restart"] = "Beim nächsten Spielstart aktiv, /reload ist gesperrt",
  ["pkg.combat"] = "Nicht im Kampf",
  ["pkg.err.disabled"] = "Einschalten fehlgeschlagen",
  ["pkg.err.noApi"] = "Im Client nicht möglich",
  ["pkg.err.failed"] = "Laden fehlgeschlagen",
  ["pkg.enable"] = "Einschalten und laden",
  ["pkg.load"] = "Daten laden",
  ["pkg.copy"] = "Link kopieren",
  ["pkg.copy.title"] = "Download",
  ["pkg.copy.hint"] = "Link im Browser öffnen",
})

-- Reason of a failed U.Enable -> locale key of the hint (NOT_DEMAND_LOADED and MISSING have their own states).
local REASON_KEYS = {
  COMBAT = "pkg.combat",
  DISABLED = "pkg.err.disabled",
  NO_API = "pkg.err.noApi",
  ["no-loader"] = "pkg.err.noApi",
}

-- Add-ons that are switched on but only start with the next game start.
local restart = {}
-- Add-ons this session loaded itself, for clients that cannot say IsAddOnLoaded.
local loadedHere = {}
local busy = 0
local banners = setmetatable({}, { __mode = "k" })

local function inCombat()
  return InCombatLockdown and InCombatLockdown() or false
end

local function addOnLoaded(name)
  local addons = rawget(_G, "C_AddOns")
  local fn = type(addons) == "table" and addons.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
  if type(fn) ~= "function" then
    return false
  end
  local ok, loaded = pcall(fn, name)
  return ok and loaded and true or false
end

-- "missing", "off" (installed, switched off), "idle" (on, not loaded yet) or "ready" (loaded).
function U.State(name)
  local base = ns.PackageState(name)
  if base == "missing" then
    return "missing"
  elseif base == "disabled" then
    return "off"
  end
  if loadedHere[name] or (ns.Packages[name] and ns.Packages[name].status == "loaded") or addOnLoaded(name) then
    return "ready"
  end
  return "idle"
end

-- True while U.Enable loads: the add-on registers its parts one by one, a page waits for the end.
function U.Busy()
  return busy > 0
end

function U.RestartPending(name)
  return restart[name] == true
end

local function enableFunction()
  local addons = rawget(_G, "C_AddOns")
  local fn = type(addons) == "table" and addons.EnableAddOn or rawget(_G, "EnableAddOn")
  return type(fn) == "function" and fn or nil
end

-- Switches the add-on on when needed and loads it. Returns true, or false plus the reason:
-- COMBAT, MISSING, NO_API, ERROR or the answer of the client (NOT_DEMAND_LOADED, DISABLED, ...).
function U.Enable(name)
  if inCombat() then
    return false, "COMBAT"
  end
  local state = U.State(name)
  if state == "ready" then
    return true
  end
  if state == "missing" then
    return false, "MISSING"
  end
  local enable = enableFunction()
  if state == "off" then
    if not enable then
      return false, "NO_API"
    end
    if not pcall(enable, name, UnitName("player")) then
      return false, "ERROR"
    end
  end
  busy = busy + 1
  local ok, loaded, reason = pcall(ns.LoadPackage, name)
  if ok and not loaded and reason == "DISABLED" and enable and pcall(enable, name) then
    -- Some clients take no character: switch it on for all and try once more.
    ok, loaded, reason = pcall(ns.LoadPackage, name)
  end
  busy = busy - 1
  if not ok then
    return false, "ERROR"
  end
  if loaded then
    restart[name], loadedHere[name] = nil, true
    ns.Emit("FG_PACKAGE_CHANGED", name)
    return true
  end
  if reason == "NOT_DEMAND_LOADED" then
    restart[name] = true
    ns.Emit("FG_PACKAGE_CHANGED", name)
  end
  return false, reason or "ERROR"
end

-- Banner ---------------------------------------------------------------------------------------------

-- The text, color and button key of the banner for the add-on in its current state.
local function describe(b, state)
  local name = b.pkg
  if state == "ready" then
    return L["pkg.ready"], "success", nil
  elseif state == "missing" then
    return L["pkg.missing"], "danger", "pkg.copy"
  elseif restart[name] then
    return L["pkg.restart"], "warning", nil
  end
  local text = L[state == "off" and "pkg.off" or "pkg.idle"]
  if b.messageKey and b.messageState == state then
    text = L[b.messageKey]
  end
  if inCombat() then
    text = text .. ". " .. L["pkg.combat"]
  end
  return text, "warning", state == "off" and "pkg.enable" or "pkg.load"
end

-- Places text and button for the given width and returns the height. Also the Stack hook.
local function fit(b, width)
  width = math.max(1, width)
  b.fitWidth = width
  local text, button = b.text, b.button
  text:ClearAllPoints()
  button:ClearAllPoints()
  if not button:IsShown() then
    text:SetWidth(width)
    text:SetPoint("TOPLEFT", 0, 0)
    local h = math.max(text:GetStringHeight(), 1)
    b:SetHeight(h)
    return h
  end
  if width >= SIDE_MIN then
    text:SetWidth(width - BUTTON_W - GAP)
    local textH = text:GetStringHeight()
    local h = math.max(textH, BUTTON_H)
    text:SetPoint("TOPLEFT", 0, -math.floor((h - textH) / 2))
    button:SetPoint("TOPRIGHT", 0, -math.floor((h - BUTTON_H) / 2))
    b:SetHeight(h)
    return h
  end
  text:SetWidth(width)
  text:SetPoint("TOPLEFT", 0, 0)
  button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -GAP)
  local h = text:GetStringHeight() + GAP + BUTTON_H
  b:SetHeight(h)
  return h
end

local function press(b)
  local name = b.pkg
  if U.State(name) == "missing" then
    ns.Dialogs.Copy("pkg.copy.title", ns.Website, "pkg.copy.hint")
    return
  end
  b.messageKey = nil
  local ok, reason = U.Enable(name)
  if ok then
    if b.opts.onLoaded then
      b.opts.onLoaded(name)
    end
  else
    b.messageKey, b.messageState = REASON_KEYS[reason], U.State(name)
    if not b.messageKey and reason ~= "NOT_DEMAND_LOADED" and reason ~= "MISSING" then
      b.messageKey = "pkg.err.failed"
    end
  end
  b:Update()
end

-- opts: onLoaded(name) after the add-on is loaded, onResize() when the banner changed its height
-- on its own, labelKey (locale key shown before the state, "Label: state"), showLoaded (stay visible
-- as a state line once loaded, the settings do that).
-- Methods: Update(wanted) shows or hides the banner for the current state and answers whether it is
-- shown (wanted = false hides it, a page whose data is fine); Refresh() the same after forgetting an
-- old failure (the settings page calls it on open); Fit(width) -> height for hosts without a stack.
-- In a Stack it needs nothing else (fgGridLayout).
function U.Banner(parent, name, opts)
  local b = CreateFrame("Frame", nil, parent)
  b.pkg, b.opts, b.wanted = name, opts or {}, true
  b.text = W.Text(b, { role = "ui", color = "warning", wrap = true })
  b.button = W.Button(b, {
    key = "pkg.enable",
    width = BUTTON_W,
    height = BUTTON_H,
    onClick = function()
      press(b)
    end,
  })
  b.button.fgId = "package-button-" .. name
  b.fgGridLayout = fit
  b.Fit = fit
  b:SetHeight(BUTTON_H)

  function b:Update(wanted)
    if wanted ~= nil then
      self.wanted = wanted
    end
    local state = U.State(name)
    local show = self.wanted ~= false and (state ~= "ready" or self.opts.showLoaded == true)
    self:SetShown(show)
    if not show then
      return false
    end
    local text, color, buttonKey = describe(self, state)
    if self.opts.labelKey then
      text = L[self.opts.labelKey] .. ": " .. text
    end
    W.SetText(self.text, nil, text)
    W.SetColor(self.text, color)
    self.button:SetShown(buttonKey ~= nil)
    if buttonKey then
      W.SetText(self.button.label, buttonKey)
      if inCombat() and state ~= "missing" then
        self.button:Disable()
      else
        self.button:Enable()
      end
    end
    if self.fitWidth then
      local before = self:GetHeight()
      fit(self, self.fitWidth)
      if self.opts.onResize and self:GetHeight() ~= before then
        self.opts.onResize()
      end
    end
    return true
  end

  -- Forgets an old failure and follows a state that changed elsewhere (a page calls it when it opens).
  function b:Refresh()
    self.messageKey = nil
    return self:Update()
  end

  b:HookScript("OnSizeChanged", function(self, width)
    if width and width > 0 and width ~= self.fitWidth and self:IsShown() then
      fit(self, width)
    end
  end)
  banners[b] = true
  b:Update()
  return b
end

local function updateAll()
  for b in pairs(banners) do
    if b.wanted ~= false then
      b:Update()
    end
  end
end

ns.On("PLAYER_REGEN_DISABLED", updateAll)
ns.On("PLAYER_REGEN_ENABLED", updateAll)
ns.On("FG_PACKAGE_CHANGED", updateAll)
ns.On("FG_UI_REFRESHED", updateAll)
