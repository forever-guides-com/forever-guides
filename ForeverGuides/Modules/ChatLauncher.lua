-- Entry of the optional sub-addon ForeverGuides_Chat ("Forever Chat") in the main add-on. /fg chat loads
-- it when it is switched on and opens its window; while it is off, nothing loads and the player gets the
-- way to the switch. The sub-addon registers its handlers here after it joined (hook version 1), so the
-- main add-on never calls into a folder that is missing, off or outdated.
local _, ns = ...
local L = ns.L

local CL = { version = 1 }
ns.ChatLauncher = CL

local ID = "chat"

ns.AddLocale("enUS", {
  ["chatlaunch.off"] = "Forever Chat is off. Switch it on under Settings > Forever Chat.",
  ["chatlaunch.dock.title"] = "Forever Chat",
  ["chatlaunch.dock.tip"] = "Open or close the messenger",
  ["chatlaunch.dock.unread"] = "%d unread",
  ["chatlaunch.usage"] = "/fgchat [toggle | open | close]",
  ["chatlaunch.usage.fg"] = "/fg chat [toggle | open | close]",
})
ns.AddLocale("deDE", {
  ["chatlaunch.off"] = "Forever Chat ist aus. Einschalten unter Einstellungen > Forever Chat.",
  ["chatlaunch.dock.title"] = "Forever Chat",
  ["chatlaunch.dock.tip"] = "Messenger öffnen oder schließen",
  ["chatlaunch.dock.unread"] = "%d ungelesen",
  ["chatlaunch.usage"] = "/fgchat [umschalten | öffnen | schließen]",
  ["chatlaunch.usage.fg"] = "/fg nachrichten [umschalten | öffnen | schließen]",
})

local handlers

-- handlers.Open() shows the window. False for anything else.
function CL.Register(api)
  if type(api) ~= "table" or type(api.Open) ~= "function" then
    return false
  end
  handlers = api
  -- The dock entry waits for this.
  ns.Emit("FG_CHAT_READY")
  return true
end

-- What the sub-addon registered (Open, Close, IsShown, Store, Db, Status), nil while it does not run.
function CL.Api()
  return handlers
end

-- True while the sub-addon runs and registered its window.
function CL.Ready()
  return handlers ~= nil
end

-- True while the sub-addon is switched on, loaded and registered: the dock offers the messenger then.
function CL.Active()
  return handlers ~= nil and ns.SubAddons.State(ID) == "active"
end

-- Unread lines over all chats (0 while the sub-addon does not run) and the badge text of it ("", 1 to 99, "99+").
function CL.Unread()
  local api = handlers
  if not (api and api.Unread and api.State) then
    return 0
  end
  local ok, total = pcall(api.Unread.Total, api.State())
  return ok and type(total) == "number" and total or 0
end

function CL.UnreadLabel()
  local api = handlers
  return api and api.Unread and api.Unread.Label(CL.Unread()) or ""
end

-- Shows the window, or hides it while it is open (the key and the dock entry). Same results as Open, "closed"
-- when it hid the window.
function CL.Toggle()
  if handlers and handlers.IsShown and handlers.IsShown() then
    handlers.Close()
    return "closed"
  end
  return CL.Open()
end

-- The answer key: loads Forever Chat when it is switched on and answers the last whisper (window on that chat,
-- focus in the input line). Without the sub-addon it behaves like Open and names the reason.
function CL.Reply()
  if not handlers and ns.SubAddons.Enabled(ID) then
    ns.SubAddons.Ensure(ID)
  end
  if CL.Active() and type(handlers.Reply) == "function" then
    return handlers.Reply()
  end
  return CL.Open()
end

-- Says why Forever Chat does not run. With showSwitch the Addons tab opens where it is switched on.
-- Returns "off", "outdated" or the State of the sub-addon ("waiting", "failed", "missing", ...).
local function explain(showSwitch)
  local state = ns.SubAddons.State(ID)
  if state == "pending-off" then
    -- Switched off in this session: the same answer as a switch that was off at the start.
    state = "off"
  end
  if state == "off" then
    ns.Notify.chat(L["chatlaunch.off"])
    if showSwitch then
      ns.SettingsPage.Select("foreverchat", "foreverchat.enable")
      ns.Main.Show("settings")
    end
  elseif state == "active" then
    -- Loaded without a registered window: the hook version differs.
    ns.Notify.chat(L["addons.state.outdated"])
    return "outdated"
  else
    ns.Notify.chat((ns.AddonSettings.StatusText(ID)))
  end
  return state
end

local function ensure()
  if not handlers and ns.SubAddons.Enabled(ID) then
    ns.SubAddons.Ensure(ID)
  end
end

-- Loads Forever Chat when it is switched on and opens the window. Returns "open", "off" or the State of
-- the sub-addon ("waiting", "failed", "missing", ...) that kept it from running.
function CL.Open()
  ensure()
  if CL.Active() then
    handlers.Open()
    return "open"
  end
  return explain(true)
end

-- Hides the window. Returns "closed", or "idle" when there was nothing to close.
function CL.Close()
  if handlers and handlers.IsShown and handlers.IsShown() then
    handlers.Close()
    return "closed"
  end
  return "idle"
end

-- The key and the macro button: the same as Toggle while Forever Chat runs. While it is off they only say where
-- to switch it on (Settings, tab Addons) and do nothing else, a key press never changes a screen on its own.
function CL.Key()
  ensure()
  if CL.Active() then
    return CL.Toggle()
  end
  return explain(false)
end

-- The words of "/fg chat" and "/fgchat": toggle (also empty), open, close, in both languages.
CL.WORDS = {
  toggle = "toggle",
  umschalten = "toggle",
  open = "open",
  ["öffnen"] = "open",
  oeffnen = "open",
  close = "close",
  ["schließen"] = "close",
  schliessen = "close",
}

-- Runs a word of CL.WORDS. Returns what the action returned, or nil for a word that is none of them (the
-- caller names the usage).
function CL.Command(word)
  word = tostring(word or ""):lower():match("^%s*(%S*)") or ""
  local action = word == "" and "toggle" or CL.WORDS[word]
  if action == "open" then
    return CL.Open()
  elseif action == "close" then
    return CL.Close()
  elseif action == "toggle" then
    return CL.Toggle()
  end
  return nil
end

-- A button for macros: /click FGChatToggleButton. Not protected, so it works in combat; it does what the key
-- does. Invisible and without mouse, it only exists to be clicked by name.
local macroButton = CreateFrame("Button", "FGChatToggleButton", UIParent)
macroButton:SetSize(1, 1)
macroButton:SetAlpha(0)
macroButton:EnableMouse(false)
macroButton:RegisterForClicks("AnyUp")
macroButton:SetScript("OnClick", ns.Wrap("chat-toggle-button", CL.Key))

-- The short command /fgchat, registered late and only when no other add-on owns it (like /calc).
local COMMAND = "/fgchat"
local SLASH_KEY = "FOREVERGUIDES_CHAT_CMD"
function CL.RegisterSlash()
  local owner = ns.WaypointSlash and ns.WaypointSlash.SlashOwners(COMMAND)
  if owner then
    for _, name in ipairs(owner) do
      if name ~= SLASH_KEY then
        return false
      end
    end
  end
  SlashCmdList[SLASH_KEY] = function(msg)
    ns.Safe("slash:fgchat", function()
      if CL.Command(msg) == nil then
        ns.Notify.chat(L["chatlaunch.usage"])
      end
    end)
  end
  rawset(_G, "SLASH_" .. SLASH_KEY .. "1", COMMAND)
  local refresh = rawget(_G, "ChatFrame_ImportAllListsToHash")
  if type(refresh) == "function" then
    pcall(refresh)
  end
  return true
end

ns.On("PLAYER_LOGIN", function()
  C_Timer.After(0, function()
    ns.Safe("chat-slash", CL.RegisterSlash)
  end)
end)
