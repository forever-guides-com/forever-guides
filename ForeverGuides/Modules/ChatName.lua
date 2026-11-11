-- Chat name: the own name in front of the own chat messages ("(Name): text"). Rules live in ChatNameLogic, the
-- shape of the profile in ChatNameProfile, the settings card in ChatNameSettings, the colored display of
-- received prefixes in ChatNameColor.
-- How: the text of the chat input field is changed right before the game sends it. The send function of the game
-- is never replaced. Two entry points feed the same routine and each is harmless after the other, because a text
-- that already starts with the prefix is left alone:
--   the pre-send event of the chat window (EventRegistry), the way meant for add-ons, and
--   the Enter key of every chat input field (HookScript), the fallback while the event is not measured in the game.
-- Safety: nothing is hooked while the feature is off. A text that is a secret value, or that cannot be read, is
-- never touched and never concatenated. While the client restricts add-ons (boss encounter, Mythic+, PvP match,
-- locked chat) the text stays as typed. The restriction is asked on every send, never cached. Three errors switch
-- the feature off. Nothing is sent to other players by this module.
local _, ns = ...
local CNL, P, Guard, Store, L, PN = ns.ChatNameLogic, ns.ChatNameProfile, ns.AutoGuard, ns.Store, ns.L, ns.PlayerName

local CN = {}
ns.ChatName = CN

CN.MAX_ERRORS = 3
-- Name of the pre-send event of the chat window. Unverified in the Forever client: the Enter key hook covers
-- for it, and the developer probe tells whether it fires.
CN.PRESEND_EVENTS = { "ChatFrame.OnEditBoxPreSendText" }
-- Chat windows are ChatFrame1.. (temporary windows come after the normal ones).
CN.MAX_FRAMES = 50
CN.TRACE_SIZE = 12
CN.OWNER = {}

local errors, off, installed, windowHooked = 0, false, false, false
-- edit box -> true for every field that carries the key hook (a hook cannot be removed, it is inert when off).
local hooked = setmetatable({}, { __mode = "k" })
-- Counters of the session: how a pre-send arrived and what was done.
local counts = { event = 0, key = 0, set = 0, skipped = 0 }
-- The last decisions in a ring of preallocated slots. Memory only: no text and no channel name.
local trace, traceAt = {}, 0
for i = 1, CN.TRACE_SIZE do
  trace[i] = {}
end

local function g(name)
  return rawget(_G, name)
end

local function now()
  local fn = g("GetTime")
  return type(fn) == "function" and fn() or 0
end

-- Profile -----------------------------------------------------------------------------------------------

-- The profile in use and its scope ("account" or "character").
function CN.Profile()
  return P.Active(ns.db, ns.charDB)
end

-- Writes one field of the profile in use (key may be dotted, "channels.guild") into the right store.
function CN.Set(key, value)
  local _, scope = CN.Profile()
  if scope == "character" then
    return Store.setChar("chatName." .. key, value)
  end
  Store.set("settings.chatName." .. key, value)
  return true
end

-- Sets the name. Returns true, or false and the reason the name was refused (nothing is saved then).
function CN.SetName(raw)
  local clean, err = CNL.CheckName(raw)
  if err then
    return false, err
  end
  local profile = CN.Profile()
  if not profile then
    return false, "no profile"
  end
  if clean ~= profile.name then
    CN.Set("recent", P.Remember(profile.recent, profile.name, clean))
    CN.Set("name", clean)
  end
  return true
end

function CN.SetEnabled(on)
  CN.Set("enabled", on == true)
end

-- The character takes a copy of the account profile (true) or follows the account again (false).
function CN.UseCharacterProfile(on)
  if type(ns.charDB) ~= "table" then
    return false
  end
  if on then
    P.UseCharacter(ns.db, ns.charDB)
  else
    P.UseAccount(ns.charDB)
  end
  if ns.Emit then
    ns.Emit("FG_SETTING_CHANGED", "chatName", nil, "char")
  end
  return true
end

-- The profile in use goes back to the defaults.
function CN.Reset()
  local _, scope = CN.Profile()
  local fresh = P.Defaults()
  if scope == "character" then
    ns.charDB.chatName = fresh
    if ns.Emit then
      ns.Emit("FG_SETTING_CHANGED", "chatName", nil, "char")
    end
  else
    Store.set("settings.chatName", fresh)
  end
end

-- Facts from the client --------------------------------------------------------------------------------

local function isSecret(value)
  local fn = g("issecretvalue")
  if type(fn) ~= "function" then
    return false
  end
  local ok, hidden = pcall(fn, value)
  return not ok or hidden == true
end

-- A boolean answer of a game function; a secret answer marks the facts, an error or another type counts as no
-- answer.
local function flag(facts, fn, ...)
  local ok, value = pcall(fn, ...)
  if not ok then
    return nil
  end
  if isSecret(value) then
    facts.secret = true
    return nil
  end
  return type(value) == "boolean" and value or nil
end

-- Kind of the instance the player is in ("none", "party", "raid", "pvp", "arena", "scenario"), nil when the
-- client does not say or hides it.
function CN.InstanceType()
  local fn = g("IsInInstance")
  if type(fn) == "function" then
    local ok, _, kind = pcall(fn)
    kind = ok and Guard.Safe(kind) or nil
    if type(kind) == "string" then
      return kind
    end
  end
  fn = g("GetInstanceInfo")
  if type(fn) == "function" then
    local ok, _, kind = pcall(fn)
    kind = ok and Guard.Safe(kind) or nil
    if type(kind) == "string" then
      return kind
    end
  end
  return nil
end

-- What the client says about restrictions for add-ons right now, in the shape of CNL.PauseReason.
function CN.RestrictionFacts()
  local facts = { kinds = {}, hasKinds = false, instance = CN.InstanceType() }
  local info = g("C_ChatInfo")
  if type(info) == "table" and type(info.InChatMessagingLockdown) == "function" then
    facts.lockdown = flag(facts, info.InChatMessagingLockdown)
  end
  local api = g("C_RestrictedActions")
  if type(api) == "table" then
    if type(api.IsAddOnRestrictionActive) == "function" then
      facts.hasKinds = true
      for kind = 1, #CNL.RESTRICTION_KINDS do
        facts.kinds[kind] = flag(facts, api.IsAddOnRestrictionActive, kind)
      end
    elseif type(api.GetAddOnRestrictionState) == "function" then
      local enum = g("Enum")
      local states = type(enum) == "table" and enum.AddOnRestrictionState or nil
      local active = type(states) == "table" and states.Active or 2
      facts.hasKinds = true
      for kind = 1, #CNL.RESTRICTION_KINDS do
        local ok, state = pcall(api.GetAddOnRestrictionState, kind)
        if ok and isSecret(state) then
          facts.secret = true
        elseif ok and type(state) == "number" then
          facts.kinds[kind] = state == active
        end
      end
    end
  end
  return facts
end

-- Why the add-on keeps its hands off the text right now, nil when it may work.
function CN.PauseReason()
  return CNL.PauseReason(CN.RestrictionFacts())
end

-- The names of the own character to compare the chosen name with: the full name and the first name.
local function characterNames()
  local out = { PN.Self() }
  local fn = g("UnitName")
  if type(fn) == "function" then
    local ok, name = pcall(fn, "player")
    name = ok and Guard.Safe(name) or nil
    if type(name) == "string" and name ~= out[1] then
      out[#out + 1] = name
    end
  end
  return out
end

-- Names of the add-ons with the same purpose that are loaded.
function CN.Conflicts()
  local api = g("C_AddOns")
  local fn = type(api) == "table" and api.IsAddOnLoaded or g("IsAddOnLoaded")
  local out = {}
  if type(fn) == "function" then
    for _, name in ipairs(CNL.CONFLICT_ADDONS) do
      local ok, loaded = pcall(fn, name)
      if ok and loaded then
        out[#out + 1] = name
      end
    end
  end
  return out
end

-- The chat input field ----------------------------------------------------------------------------------

-- What a chat input field holds: { text, chatType, channel } with nil for what is secret or unreadable, and the
-- flags secretText and secretType. Reads only.
function CN.Read(editBox)
  local out = {}
  if type(editBox) ~= "table" or type(editBox.GetText) ~= "function" then
    return out
  end
  local ok, text = pcall(editBox.GetText, editBox)
  if ok and isSecret(text) then
    out.secretText = true
  elseif ok and type(text) == "string" then
    out.text = Guard.Safe(text)
  end
  local chatType
  if type(editBox.GetAttribute) == "function" then
    local okType, value = pcall(editBox.GetAttribute, editBox, "chatType")
    chatType = okType and value or nil
  end
  if chatType == nil then
    chatType = rawget(editBox, "chatType")
  end
  if isSecret(chatType) then
    out.secretType = true
  elseif type(chatType) == "string" then
    out.chatType = chatType:upper()
  end
  if out.chatType == "CHANNEL" then
    local target
    if type(editBox.GetAttribute) == "function" then
      local okTarget, value = pcall(editBox.GetAttribute, editBox, "channelTarget")
      target = okTarget and value or nil
    end
    target = target or rawget(editBox, "channelTarget")
    local lookup = g("GetChannelName")
    if not isSecret(target) and target ~= nil and type(lookup) == "function" then
      local okName, _, name = pcall(lookup, target)
      name = okName and Guard.Safe(name) or nil
      if type(name) == "string" then
        out.channel = name
      end
    end
  end
  return out
end

-- Calls fn(editBox) for every chat input field of the windows that exist.
function CN.EachEditBox(fn)
  for i = 1, CN.MAX_FRAMES do
    local box = g("ChatFrame" .. i .. "EditBox")
    if type(box) == "table" then
      fn(box, i)
    end
  end
end

-- Trace -------------------------------------------------------------------------------------------------

local function record(via, chatType, decision, reason)
  traceAt = traceAt % CN.TRACE_SIZE + 1
  local slot = trace[traceAt]
  slot.t, slot.via, slot.chatType, slot.decision, slot.reason = now(), via, chatType, decision, reason
  if decision == "set" then
    counts.set = counts.set + 1
  else
    counts.skipped = counts.skipped + 1
  end
  ns.Log.debug("chatname: %s %s %s %s", tostring(via), tostring(chatType), decision, tostring(reason))
end

-- The decisions of this session, oldest first: { age (seconds), via, chatType, decision, reason }.
function CN.Trace()
  local out = {}
  for step = 1, CN.TRACE_SIZE do
    local slot = trace[(traceAt + step - 1) % CN.TRACE_SIZE + 1]
    if slot.decision then
      out[#out + 1] = {
        age = math.max(0, now() - (slot.t or 0)),
        via = slot.via,
        chatType = slot.chatType,
        decision = slot.decision,
        reason = slot.reason,
      }
    end
  end
  return out
end

function CN.Counts()
  return { event = counts.event, key = counts.key, set = counts.set, skipped = counts.skipped }
end

-- Sending -----------------------------------------------------------------------------------------------

local function prefixes(profile)
  return CNL.Prefix(profile.name, profile.style), CNL.KnownPrefixes(profile.name, profile.style, profile.recent)
end

-- The routine behind both entry points: decides and, when it may, writes the text with the prefix.
local function run(editBox, via, profile)
  local pause = CN.PauseReason()
  if pause then
    return record(via, nil, "skip", "paused " .. pause)
  end
  local read = CN.Read(editBox)
  if read.secretText or read.secretType then
    return record(via, nil, "skip", "secret")
  end
  if not read.text then
    return record(via, read.chatType, "skip", "unreadable")
  end
  local ctx = { chatType = read.chatType, instance = CN.InstanceType(), channel = read.channel }
  local allowed, why = CNL.Allowed(profile, ctx)
  if not allowed then
    return record(via, read.chatType, "skip", why)
  end
  if profile.hideSame and CNL.SameName(profile.name, characterNames(), profile.match) then
    return record(via, read.chatType, "skip", "same name")
  end
  local prefix, known = prefixes(profile)
  local text, how = CNL.Compose(read.text, prefix, known)
  if not text then
    return record(via, read.chatType, "skip", how)
  end
  if not pcall(editBox.SetText, editBox, text) then
    return record(via, read.chatType, "skip", "settext failed")
  end
  record(via, read.chatType, "set", how)
end

-- For a sender that is not the game's input field (Forever Chat): the text with the prefix in front, or nil and the
-- reason it stays as it is. The same rules as the input field: switched on, not off after errors, not paused by a
-- restriction, the chat type is switched on, no command, no empty text, never twice, secret text untouched,
-- whisper, say and yell never. The length is the caller's business (CNL.Build).
local function decorate(text, chatType, channel)
  local profile = CN.Profile()
  if off or not profile or profile.enabled ~= true then
    return nil, "off"
  end
  if isSecret(text) or type(text) ~= "string" then
    return nil, "unreadable"
  end
  local pause = CN.PauseReason()
  if pause then
    return nil, "paused " .. pause
  end
  local ctx = { chatType = chatType, instance = CN.InstanceType(), channel = channel }
  local allowed, why = CNL.Allowed(profile, ctx)
  if not allowed then
    return nil, why
  end
  if profile.hideSame and CNL.SameName(profile.name, characterNames(), profile.match) then
    return nil, "same name"
  end
  local prefix, known = prefixes(profile)
  return CNL.Build(text, prefix, known)
end

function CN.Decorate(text, chatType, channel, quiet)
  local out, how = decorate(text, chatType, channel)
  if how ~= "off" and not quiet then
    record("send", chatType, out and "set" or "skip", how)
  end
  return out, how
end

local function fail(err)
  errors = errors + 1
  ns.Log.warn("chatname: %s", tostring(err))
  if errors < CN.MAX_ERRORS then
    return
  end
  off = true
  CN.Uninstall()
  CN.Set("enabled", false)
  local text = string.format(L["chatname.off"], errors)
  ns.Errors.add({ msg = text, kind = "warning", ctx = "chatname" })
  ns.Notify(text, "warning")
end

-- The entry point: the field the game is about to send. via is "event" or "key" (status and trace only).
function CN.Process(editBox, via)
  local profile = CN.Profile()
  if off or not profile or profile.enabled ~= true then
    return
  end
  counts[via] = (counts[via] or 0) + 1
  local ok = ns.Safe("chatname", run, editBox, via, profile)
  if not ok then
    fail("error while preparing a message")
  end
end

-- After Up or Down the field shows an older line of the input history. The prefix this add-on wrote into it is
-- taken off again, so the line can be sent under the current name or copied without it.
local function stripHistory(editBox)
  local profile = CN.Profile()
  if off or not profile or profile.enabled ~= true or CN.PauseReason() then
    return
  end
  local read = CN.Read(editBox)
  if not read.text then
    return
  end
  local _, known = prefixes(profile)
  local rest = CNL.Strip(read.text, known)
  if rest then
    pcall(editBox.SetText, editBox, rest)
  end
end

local function afterHistoryKey(editBox)
  local timer = g("C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    pcall(timer.After, 0, function()
      ns.Safe("chatname", stripHistory, editBox)
    end)
  end
end

local ENTER_KEYS = { ENTER = true, NUMPADENTER = true }
local HISTORY_KEYS = { UP = true, DOWN = true }

local function onKey(editBox, key)
  if ENTER_KEYS[key] then
    CN.Process(editBox, "key")
  elseif HISTORY_KEYS[key] and installed then
    afterHistoryKey(editBox)
  end
end

local function hookFields()
  CN.EachEditBox(function(box)
    if hooked[box] or type(box.HookScript) ~= "function" then
      return
    end
    hooked[box] = true
    pcall(box.HookScript, box, "OnKeyDown", function(self, key)
      if installed then
        onKey(self, key)
      end
    end)
    pcall(box.HookScript, box, "OnArrowPressed", function(self, key)
      if installed and HISTORY_KEYS[key] then
        afterHistoryKey(self)
      end
    end)
  end)
end

local function eventRegistry()
  local registry = g("EventRegistry")
  if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
    return registry
  end
end

-- Puts the entry points in. Safe to call again: the fields that carry the hook are remembered.
function CN.Install()
  installed = true
  hookFields()
  -- A temporary chat window (a whisper window, a pop-out) brings its own input field after the game built it.
  local hook = g("hooksecurefunc")
  if not windowHooked and type(hook) == "function" and type(g("FCF_OpenTemporaryWindow")) == "function" then
    windowHooked = pcall(hook, "FCF_OpenTemporaryWindow", function()
      if installed then
        hookFields()
      end
    end)
  end
  local registry = eventRegistry()
  if registry then
    for _, event in ipairs(CN.PRESEND_EVENTS) do
      pcall(registry.RegisterCallback, registry, event, function(_, editBox)
        if installed then
          CN.Process(editBox, "event")
        end
      end, CN.OWNER)
    end
  end
end

-- Takes the entry points out: the event callback is unregistered, the key hooks stay and do nothing.
function CN.Uninstall()
  installed = false
  local registry = eventRegistry()
  if registry and type(registry.UnregisterCallback) == "function" then
    for _, event in ipairs(CN.PRESEND_EVENTS) do
      pcall(registry.UnregisterCallback, registry, event, CN.OWNER)
    end
  end
end

function CN.Installed()
  return installed
end

-- Installed exactly while the profile in use is on.
function CN.Refresh()
  local profile = CN.Profile()
  local on = not off and profile ~= nil and profile.enabled == true
  if on and not installed then
    CN.Install()
  elseif not on and installed then
    CN.Uninstall()
  end
end

-- Switching it on again after errors gives it a fresh start.
function CN.Revive()
  errors, off = 0, false
end

function CN.IsOff()
  return off
end

-- Status ------------------------------------------------------------------------------------------------

-- The facts CNL.Status works from (memory and settings, nobody is asked).
function CN.StatusFacts()
  local profile = CN.Profile() or P.Defaults()
  local _, nameError = CNL.CheckName(profile.name)
  local anyPlace = CNL.CleanChannels(profile.custom) ~= ""
  for _, group in ipairs(CNL.GROUPS) do
    anyPlace = anyPlace or profile.channels[group] == true
  end
  return {
    enabled = profile.enabled == true,
    name = profile.name,
    nameError = nameError,
    anyPlace = anyPlace,
    hidden = profile.hideSame and CNL.SameName(profile.name, characterNames(), profile.match) or false,
    pause = CN.PauseReason(),
    off = off,
    conflicts = CN.Conflicts(),
  }
end

-- Commands ----------------------------------------------------------------------------------------------

local ON_WORDS = { on = true, an = true, ein = true }
local OFF_WORDS = { off = true, aus = true }
local HELP_WORDS = { help = true, hilfe = true, ["?"] = true }

-- The reply of a command is a chat line, whatever the feedback mode says (a command asks for an answer).
local function say(text)
  ns.Notify.chat(text)
end

-- One status item { key, argument } of CNL.Status as a line of text.
function CN.StatusText(item)
  local text = L["chatname.status." .. item[1]]
  local arg = item[2]
  if item[1] == "paused" then
    arg = L["chatname.pause." .. tostring(arg)]
  elseif item[1] == "badName" then
    arg = L["chatname.error." .. tostring(arg)]
  end
  return arg ~= nil and text:format(arg) or text
end

-- The word behind "name" without a pair of quotes around it.
local function unquote(text)
  return text:match('^"(.*)"$') or text:match("^\226\128\156(.*)\226\128\157$") or text
end

function CN.TraceText()
  local lines = {}
  for _, item in ipairs(CN.Trace()) do
    lines[#lines + 1] = string.format(
      "%4ds  %-5s  %-14s  %-5s  %s",
      math.floor(item.age),
      tostring(item.via),
      tostring(item.chatType or "-"),
      tostring(item.decision),
      tostring(item.reason)
    )
  end
  return table.concat(lines, "\n")
end

-- /fg chatname [name <name> | on | off | status | log | help]
function CN.Slash(rest)
  local sub, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
  sub = sub:lower()
  if sub == "name" then
    local ok, err = CN.SetName(unquote(arg))
    if not ok then
      say(string.format(L["chatname.error"], L["chatname.error." .. tostring(err)] or tostring(err)))
    elseif arg == "" then
      say(L["chatname.slash.cleared"])
    else
      say(string.format(L["chatname.slash.set"], (CN.Profile() or {}).name or ""))
    end
  elseif ON_WORDS[sub] then
    local profile = CN.Profile()
    if not profile or profile.name == "" then
      say(L["chatname.slash.needName"])
      return
    end
    CN.Revive()
    CN.SetEnabled(true)
    say(L["chatname.slash.on"])
  elseif OFF_WORDS[sub] then
    CN.SetEnabled(false)
    say(L["chatname.slash.off"])
  elseif sub == "status" then
    for _, item in ipairs(CNL.Status(CN.StatusFacts())) do
      say(string.format(L["chatname.slash.status"], CN.StatusText(item)))
    end
  elseif sub == "log" then
    local text = CN.TraceText()
    if text == "" then
      say(L["chatname.slash.log.empty"])
    else
      ns.Dialogs.Copy("chatname.slash.log.title", text, "chatname.slash.log.hint")
    end
  elseif HELP_WORDS[sub] then
    say(L["chatname.slash.help"])
  else
    ns.ChatNameSettings.Open()
  end
end

-- Lifecycle ---------------------------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", CN.Refresh)
ns.On("FG_SETTING_CHANGED", function(_, path, value, scope)
  if type(path) ~= "string" then
    return
  end
  local mine = scope == "char" and path:find("^chatName") or path:find("^settings%.chatName")
  if not mine then
    return
  end
  if value == true and path:find("enabled$") then
    CN.Revive()
  end
  CN.Refresh()
end)
