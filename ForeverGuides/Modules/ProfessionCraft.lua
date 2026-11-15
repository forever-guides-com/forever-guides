-- Opens a recipe in the game's profession window so the player can craft it there. Checks first that the
-- character has the profession and knows the recipe and says what is missing otherwise.
-- Two ways in: C.Open tries the client's C_TradeSkillUI.OpenRecipe from a plain click (some clients only
-- select inside a window that is already open), and the craft badge is one shared secure button that casts
-- the profession spell (opens the window with a hardware click) and selects the recipe once it is shown.
-- Nothing is crafted here: the player presses the window's own craft button.
local _, ns = ...
local L = ns.L

local C = {}
ns.ProfessionCraft = C

-- Mining crafts in the smelting window, which opens from its own spell.
local SMELTING_SPELL = 2656
-- Time the client gets to show the window before the hint is given.
local SHOW_WAIT = 0.4
local WINDOWS = { "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }

ns.AddLocale("enUS", {
  ["craft.open"] = "Click: open in the profession window",
  ["craft.badge"] = "Open the profession window on this recipe",
  ["craft.noProfession"] = "You do not have %s.",
  ["craft.unknown"] = "You do not know this recipe yet (trainer or recipe item).",
  ["craft.combat"] = "Not possible in combat.",
  ["craft.useBadge"] = "The game opens the window only from the hammer on the recipe icon.",
})
ns.AddLocale("deDE", {
  ["craft.open"] = "Klick: im Berufsfenster öffnen",
  ["craft.badge"] = "Berufsfenster bei diesem Rezept öffnen",
  ["craft.noProfession"] = "Du hast %s nicht.",
  ["craft.unknown"] = "Dieses Rezept kannst du noch nicht (Lehrer oder Rezept-Item).",
  ["craft.combat"] = "Im Kampf nicht möglich.",
  ["craft.useBadge"] = "Das Spiel öffnet das Fenster nur über den Hammer auf dem Rezept-Symbol.",
})

local function inCombat()
  local f = rawget(_G, "InCombatLockdown")
  return type(f) == "function" and f() == true
end

local function tradeApi(name)
  local api = rawget(_G, "C_TradeSkillUI")
  return type(api) == "table" and type(api[name]) == "function" and api[name] or nil
end

local function spellName(id)
  local api = rawget(_G, "C_Spell")
  local get = type(api) == "table" and api.GetSpellName or rawget(_G, "GetSpellInfo")
  if type(get) ~= "function" then
    return nil
  end
  local ok, name = pcall(get, id)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

-- True while one of the game's profession windows is shown.
function C.WindowShown()
  for _, name in ipairs(WINDOWS) do
    local f = rawget(_G, name)
    if type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() then
      return true
    end
  end
  return false
end

-- The own profession entry of a slug, nil when the character does not have it.
local function own(slug)
  for _, p in ipairs(ns.ProfessionShop.Own()) do
    if p.slug == slug then
      return p
    end
  end
end

-- Name of the profession in the client's language (the route name when the character does not have it).
function C.ProfessionName(slug)
  local p = own(slug)
  return p and p.name or ns.ProfessionRouteLogic.Name(slug)
end

-- The spell that opens the window of a profession, nil when it cannot be told.
function C.WindowSpell(slug)
  if slug == "mining" then
    return spellName(SMELTING_SPELL)
  end
  local p = own(slug)
  return p and p.name or nil
end

-- "ok", "noProfession" or "unknown" (the character has the profession, not the recipe).
function C.Status(slug, spell)
  if not own(slug) then
    return "noProfession"
  end
  local known = ns.RecipeKnown and ns.RecipeKnown.OwnHas(spell)
  if not known then
    local f = rawget(_G, "IsPlayerSpell")
    known = type(f) == "function" and select(2, pcall(f, spell)) == true
  end
  return known and "ok" or "unknown"
end

-- Text of a status other than "ok".
function C.StatusText(slug, status)
  if status == "noProfession" then
    return string.format(L["craft.noProfession"], C.ProfessionName(slug))
  end
  return L["craft." .. status]
end

-- The recipe the window selects as soon as it is shown (set by a click before the window opens).
local pending

local function selectRecipe(spell)
  local open = tradeApi("OpenRecipe")
  return open ~= nil and pcall(open, spell)
end

-- Opens the recipe: says what is missing, otherwise asks the client and gives the badge hint when no
-- window came up. Returns the status.
function C.Open(slug, spell)
  local status = C.Status(slug, spell)
  if status ~= "ok" then
    ns.Toast.Show(C.StatusText(slug, status), "warning")
    return status
  end
  if inCombat() then
    ns.Toast.Show(L["craft.combat"], "warning")
    return "combat"
  end
  pending = spell
  selectRecipe(spell)
  local timer = rawget(_G, "C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After(SHOW_WAIT, function()
      if not C.WindowShown() then
        ns.Toast.Show(L["craft.useBadge"], "info")
      end
    end)
  end
  return status
end

ns.On("TRADE_SKILL_SHOW", function()
  if pending then
    local spell = pending
    pending = nil
    selectRecipe(spell)
  end
end)

-- Craft badge ------------------------------------------------------------------------------------------

local overlay

local function hideOverlay()
  if overlay and not inCombat() then
    overlay:ClearAllPoints()
    overlay:Hide()
  end
end

-- The one secure button, laid over the badge of the hovered recipe icon (only out of combat: a secure
-- frame must not be moved, shown or hidden in combat).
local function getOverlay()
  if overlay then
    return overlay
  end
  local ok, b = pcall(CreateFrame, "Button", "ForeverGuidesCraftBadge", UIParent, "SecureActionButtonTemplate")
  if not ok or not b then
    return nil
  end
  overlay = b
  b:SetFrameStrata("TOOLTIP")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "spell")
  b:SetScript("PreClick", function(self)
    pending = self.fgSpell
  end)
  b:SetScript("OnEnter", function(self)
    if self.fgTip then
      ns.ShowTooltip(self, L["craft.badge"], self.fgTip)
    end
  end)
  b:SetScript("OnLeave", function()
    ns.HideTooltip()
    hideOverlay()
  end)
  b:Hide()
  return b
end

ns.On("PLAYER_REGEN_DISABLED", hideOverlay)

-- Lays the secure button over the badge of the recipe; a recipe that cannot be opened gets no button (the
-- plain click on the badge then says why).
function C.ArmBadge(badge, slug, spell)
  if inCombat() or C.Status(slug, spell) ~= "ok" then
    return false
  end
  local window = C.WindowSpell(slug)
  local b = window and getOverlay()
  if not b then
    return false
  end
  b:SetAttribute("spell", window)
  b.fgSpell, b.fgTip = spell, L["craft.open"]
  b:ClearAllPoints()
  b:SetAllPoints(badge)
  b:Show()
  return true
end

-- The secure button (tests).
function C.Overlay()
  return overlay
end
