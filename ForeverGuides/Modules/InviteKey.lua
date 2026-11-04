-- Optional key for the guild invite bar (settings.inviteConfirmKey, off by default). While a ginv request
-- is open, the game is not in combat and no text box has the keyboard, a temporary override binding
-- sends the chosen key as a click to the button of the first request. The key never calls the invite
-- itself: the click handler of that button does, as with a mouse click (a key press is a hardware event
-- for the game like the mouse). Override bindings can only be set and cleared out of combat; a change
-- that falls into a combat waits for PLAYER_REGEN_ENABLED, and a binding that is still set in combat
-- clicks a button that answers "in combat" and invites nobody.
-- A key that another action already uses is never taken over, the settings page says so.
local _, ns = ...
local PL = ns.InvitePromptLogic

local K = {}
ns.InviteKey = K

ns.AddLocale("enUS", {
  ["invite.key.off"] = "Off",
  ["invite.key.Y"] = "Y",
  ["invite.key.G"] = "G",
  ["invite.key.CTRL-Y"] = "Ctrl+Y",
  ["invite.key.SHIFT-G"] = "Shift+G",
  ["invite.key.CTRL"] = "Ctrl",
  ["invite.key.SHIFT"] = "Shift",
  ["invite.key.taken"] = "The key %s is already used for %s. It stays as it is and the invite bar does not use it.",
})
ns.AddLocale("deDE", {
  ["invite.key.off"] = "Aus",
  ["invite.key.Y"] = "Y",
  ["invite.key.G"] = "G",
  ["invite.key.CTRL-Y"] = "Strg+Y",
  ["invite.key.SHIFT-G"] = "Umschalt+G",
  ["invite.key.CTRL"] = "Strg",
  ["invite.key.SHIFT"] = "Umschalt",
  ["invite.key.taken"] = "Die Taste %s ist schon mit %s belegt. Sie bleibt unverändert und die Einladungsleiste nutzt sie nicht.",
})

local OWNER_NAME = "ForeverGuidesInviteKeyOwner"
local owner
-- { key, target } while the override is set.
local bound
local pending = false

local function g(name)
  return rawget(_G, name)
end

function K.Key()
  local settings = ns.db and ns.db.settings
  return PL.CleanKey(settings and settings.inviteConfirmKey)
end

function K.Label(key)
  return PL.KeyLabel(key, { CTRL = ns.L["invite.key.CTRL"], SHIFT = ns.L["invite.key.SHIFT"] })
end

-- The action a permanent binding of the key already runs, nil when it is free. Override bindings do not
-- count (ours is one of them).
function K.Taken(key)
  key = key or K.Key()
  local fn = g("GetBindingAction")
  if key == "" or type(fn) ~= "function" then
    return nil
  end
  local ok, action = pcall(fn, key, false)
  if ok and type(action) == "string" and action ~= "" then
    return action
  end
  return nil
end

-- Text for the settings page: why the chosen key is not used, nil when it is fine or off.
function K.TakenText(key)
  key = key or K.Key()
  local action = K.Taken(key)
  if not action then
    return nil
  end
  local name = g("GetBindingName")
  local ok, shown = pcall(type(name) == "function" and name or tostring, action)
  return string.format(
    ns.L["invite.key.taken"],
    K.Label(key) or key,
    ok and type(shown) == "string" and shown or action
  )
end

local function textFocus()
  local fn = g("GetCurrentKeyBoardFocus")
  if type(fn) ~= "function" then
    return false
  end
  local ok, frame = pcall(fn)
  return ok and frame ~= nil
end

-- The key and the button name that should be bound now, nil when nothing should be.
local function wanted()
  local key = K.Key()
  local row = key ~= "" and ns.InvitePrompt and ns.InvitePrompt.First()
  if not row or K.Taken(key) or textFocus() then
    return nil
  end
  return key, ns.InvitePrompt.KeyTarget(row), row
end

local function clear()
  if bound and owner then
    local fn = g("ClearOverrideBindings")
    if type(fn) == "function" then
      pcall(fn, owner)
    end
  end
  bound = nil
end

local function set(key, target)
  local fn = g("SetOverrideBindingClick")
  if type(fn) ~= "function" then
    return
  end
  if not owner then
    local ok, frame = pcall(CreateFrame, "Frame", OWNER_NAME)
    owner = ok and frame or nil
  end
  if owner and pcall(fn, owner, false, key, target) then
    bound = { key = key, target = target }
  end
end

-- Brings the binding in line with the state: set, moved to another button, or cleared. In combat nothing
-- is touched, the change waits.
function K.Refresh()
  local key, target, row = wanted()
  if (bound and bound.key) == key and (bound and bound.target) == target then
    pending = false
    return
  end
  if ns.InCombat() then
    pending = true
    return
  end
  pending = false
  clear()
  if key then
    set(key, target)
  end
  if ns.InvitePrompt then
    ns.InvitePrompt.SetHint(bound and K.Label(bound.key) or nil, row)
  end
end

-- The binding that is set now: key, button name.
function K.Bound()
  return bound and bound.key, bound and bound.target
end

function K.Pending()
  return pending
end

-- A text box takes the keyboard without an event of its own: looked at on every tick of the bar.
function K.Poll()
  if bound or K.Key() ~= "" then
    K.Refresh()
  end
end

ns.On("FG_INVITE_ROWS", K.Refresh)
ns.On("PLAYER_REGEN_ENABLED", K.Refresh)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if path == "settings.inviteConfirmKey" then
    K.Refresh()
  end
end)
if type(hooksecurefunc) == "function" then
  pcall(hooksecurefunc, "ChatEdit_ActivateChat", ns.Wrap("invite-key-chat", K.Refresh))
end
