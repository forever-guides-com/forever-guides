-- The hint with a button that stands where a function needs sharing (Core/Consent.lua) and it is
-- off: one line of text and the button "Switch on sharing". The button opens a confirm dialog with the
-- full information text of the function; only "Switch on" there writes the consent. Layout by
-- ActionBanner. Works in combat, nothing here touches a protected frame.
local _, ns = ...
local W, L, Consent = ns.W, ns.L, ns.Consent

local N = {}
ns.OptInNotice = N

ns.AddLocale("enUS", {
  ["optin.button"] = "Switch on sharing",
  ["optin.button.tip"] = "Opens a dialog that says what is shared. Nothing is switched on before you confirm.",
  ["optin.dialog.title"] = "Switch on sharing",
  ["optin.dialog.yes"] = "Switch on",
  ["optin.dialog.lead"] = "Switch on: %s (%s)",
  ["optin.on"] = "Sharing is on",
  ["optin.recv.peerStats"] = "Item level of other addon users needs sharing.",
  ["optin.recv.professions"] = "Professions of other addon users need sharing.",
})
ns.AddLocale("deDE", {
  ["optin.button"] = "Teilen einschalten",
  ["optin.button.tip"] = "Öffnet einen Dialog, der sagt, was geteilt wird. Erst deine Bestätigung schaltet es ein.",
  ["optin.dialog.title"] = "Teilen einschalten",
  ["optin.dialog.yes"] = "Einschalten",
  ["optin.dialog.lead"] = "Einschalten: %s (%s)",
  ["optin.on"] = "Teilen ist an",
  ["optin.recv.peerStats"] = "Itemlevel anderer Addon-Nutzer braucht Teilen.",
  ["optin.recv.professions"] = "Berufe anderer Addon-Nutzer brauchen Teilen.",
})

-- Every banner, to follow a change of the consent wherever it was made.
local banners = setmetatable({}, { __mode = "k" })

local function definition(fn)
  for _, def in ipairs(Consent.List()) do
    if def.id == fn then
      return def
    end
  end
end

-- The text of the dialog: which flag is switched on, then the information text of the function.
function N.DialogText(fn, dir, aud)
  local def = definition(fn)
  if not def then
    return ""
  end
  local lead = string.format(L["optin.dialog.lead"], L[def.labelKey], L["consent.flag." .. dir .. "." .. aud])
  return lead .. "\n\n" .. L[def.infoKey]
end

-- Step two: the dialog. A character that has values of its own for the function keeps them, so the new
-- value is written for the character, else for the account.
local function ask(b)
  local o = b.opts
  ns.Dialogs.Confirm(nil, nil, function()
    local scope = Consent.Overrides(o.fn) > 0 and "char" or nil
    Consent.Set(o.fn, o.dir, o.aud, true, "user", scope)
  end, nil, { title = L["optin.dialog.title"], text = N.DialogText(o.fn, o.dir, o.aud), yesKey = "optin.dialog.yes" })
end

-- opts: fn, dir, aud (the flag that is needed), textKey (locale key of the missing-sharing sentence),
-- showWhenOn (stay as a state line while it is on, default hidden), onChanged() (the page lays out
-- again; called when the consent of this function changed). Methods: Update(wanted) -> true when shown
-- (wanted = false hides it, a page that has nothing to show), Fit(width) -> height for hosts without
-- a stack. In a Stack it needs nothing else.
function N.Banner(parent, opts)
  local b
  b = ns.ActionBanner.New(parent, {
    buttonKey = "optin.button",
    tooltip = "optin.button",
    tooltipText = "optin.button.tip",
    opens = true,
    onClick = function()
      ask(b)
    end,
  })
  b.opts = opts
  b.button.fgId = "optin-" .. opts.fn .. "-" .. opts.dir .. "-" .. opts.aud

  b.wanted = true

  function b:Update(wanted)
    if wanted ~= nil then
      self.wanted = wanted
    end
    local o = self.opts
    local on = Consent.Allows(o.fn, o.dir, o.aud)
    local show = self.wanted ~= false and (not on or o.showWhenOn == true)
    self:SetShown(show)
    if not show then
      return false
    end
    W.SetText(self.text, on and "optin.on" or o.textKey)
    W.SetColor(self.text, on and "success" or "warning")
    self.button:SetShown(not on)
    self:Refit()
    return true
  end

  banners[b] = true
  b:Update()
  return b
end

local function follow(fn)
  for b in pairs(banners) do
    if b.opts.fn == fn then
      b:Update()
      if b.opts.onChanged then
        b.opts.onChanged()
      end
    end
  end
end

ns.On("FG_CONSENT_CHANGED", function(_, fn)
  follow(fn)
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  follow(fn)
end)
