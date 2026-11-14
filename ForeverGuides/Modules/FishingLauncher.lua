-- Entry of the optional sub-addon ForeverGuides_Fishing (the fishing helper) in the main add-on: the key
-- "Cast and reel in" in the key bindings window, "/fg angeln" and "/fg angeln status". The sub-addon
-- registers its handlers here after it joined (hook version 1), so the main add-on never calls into a
-- folder that is missing, off or outdated. While the helper is off the key and the command only say
-- where to switch it on and change nothing else.
local _, ns = ...
local L = ns.L

local FL = { version = 1 }
ns.FishingLauncher = FL

local ID = "fishing"

ns.AddLocale("enUS", {
  ["binding.fishing"] = "Fishing helper: cast and reel in",
  ["fishing.launch.off"] = "The fishing helper is off. Switch it on under Settings > Fishing.",
  ["fishing.launch.usage"] = "/fg fishing [status|journal]",
})
ns.AddLocale("deDE", {
  ["binding.fishing"] = "Angelhilfe: Auswerfen und Einholen",
  ["fishing.launch.off"] = "Die Angelhilfe ist aus. Einschalten unter Einstellungen > Angeln.",
  ["fishing.launch.usage"] = "/fg angeln [status|journal]",
})

local handlers

-- handlers.StatusText(diagnosis) returns the status lines as one text (with diagnosis the line of the spell
-- search too). False for anything else.
function FL.Register(api)
  if type(api) ~= "table" or type(api.StatusText) ~= "function" then
    return false
  end
  handlers = api
  return true
end

-- What the sub-addon registered, nil while it does not run.
function FL.Api()
  return handlers
end

-- True while the sub-addon is switched on, loaded and registered.
function FL.Active()
  return handlers ~= nil and ns.SubAddons.State(ID) == "active"
end

local function ensure()
  if not handlers and ns.SubAddons.Enabled(ID) then
    ns.SubAddons.Ensure(ID)
  end
end

-- Says why the helper does not run. With showSwitch the Addons tab opens where it is switched on.
-- Returns "off", "outdated" or the State of the sub-addon ("waiting", "failed", "missing", ...).
local function explain(showSwitch)
  local state = ns.SubAddons.State(ID)
  if state == "pending-off" then
    state = "off"
  end
  if state == "off" then
    ns.Notify.chat(L["fishing.launch.off"])
    if showSwitch then
      ns.SettingsPage.Select("fishing", "fishing.enable")
      ns.Main.Show("settings")
    end
  elseif state == "active" then
    -- Loaded without a registered handler: the hook version differs.
    ns.Notify.chat(L["addons.state.outdated"])
    return "outdated"
  else
    ns.Notify.chat((ns.AddonSettings.StatusText(ID)))
  end
  return state
end

-- Prints the status lines in chat (never as a toast, "feedback off" must not silence it). Returns "status"
-- or what keeps the helper from running.
function FL.Status()
  ensure()
  if FL.Active() then
    -- One call, one chat line: the lines of the status come as one text.
    ns.Notify.chat(handlers.StatusText(true))
    return "status"
  end
  return explain(false)
end

-- Opens the settings on the tab with the card of the helper. Returns "open" or what keeps it from running.
function FL.Open()
  ensure()
  if FL.Active() then
    if type(handlers.Show) == "function" then
      handlers.Show()
    end
    return "open"
  end
  return explain(true)
end

-- The key while the helper has no binding in place (something blocks fishing, the option is off, the
-- helper is off): it names the reason in chat and does nothing else.
-- The same hint again within this many seconds stays out of the chat: a held or repeated key must not flood it.
FL.KEY_REPEAT = 5
local lastKeyText, lastKeyAt

function FL.Key()
  ensure()
  if FL.Active() and type(handlers.KeyText) == "function" then
    local text = handlers.KeyText()
    local now = type(GetTime) == "function" and GetTime() or 0
    if type(text) == "string" and text ~= "" and not (text == lastKeyText and lastKeyAt and now - lastKeyAt < FL.KEY_REPEAT) then
      lastKeyText, lastKeyAt = text, now
      ns.Notify.chat(text)
    end
    return "status"
  end
  return FL.Status()
end

-- Opens the catch journal ("My catches"). Returns "journal" or what keeps the helper from running.
function FL.Journal()
  ensure()
  if FL.Active() and handlers.Journal then
    handlers.Journal()
    return "journal"
  end
  return explain(true)
end

-- The words of "/fg angeln": none (open the card), status and journal, in both languages.
FL.WORDS = {
  status = "status",
  zustand = "status",
  journal = "journal",
  fangjournal = "journal",
  faenge = "journal",
  ["fänge"] = "journal",
}

-- Runs a word. Returns what the action returned, or nil for a word that is none of them (the caller
-- names the usage).
function FL.Command(word)
  word = tostring(word or ""):lower():match("^%s*(%S*)") or ""
  if word == "" then
    return FL.Open()
  end
  if FL.WORDS[word] == "status" then
    return FL.Status()
  elseif FL.WORDS[word] == "journal" then
    return FL.Journal()
  end
  return nil
end

-- Key binding, appended to the list of Modules/KeyBindings.lua (Bindings.xml calls it). The helper puts its
-- own override binding over the key while fishing is possible, so this runs only when it does not.
ns.KeyBindings.list[#ns.KeyBindings.list + 1] =
  { name = "FOREVERGUIDES_FISHING_CAST", label = "binding.fishing", fn = "Fishing" }
ns.KeyBindings.Fishing = function()
  ns.Safe("binding:Fishing", FL.Key)
end
