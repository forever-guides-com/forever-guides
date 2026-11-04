-- Chat badge: the add-on logo in front of the name of players who want to be recognized (Presence), then the
-- guild and community logos they chose to show (CrestMark), set into the chat line when it is shown. Only the
-- local display changes, nothing is sent and the text of a message is never touched. Everything is opt-in:
--   add-on logo:      settings.chatBadge on AND the receive consent of "presenceMark" for the group or the guild
--   guild/community:  settings.chatCrestCount > 0 AND (the receive consent of "crestMark" for the group or the guild
--                     OR settings.crestLocal, the local recognition that receives nothing, see CrestLocal)
-- Each part works without the other. Without either the hook passes every line through unchanged and nothing
-- reads a register.
-- Where: the AddMessage of the chat windows. The event filters of the game can only change the sender or
-- the text, and the name sits inside the player link there, so a filter would break the link.
-- A chat add-on that draws the chat in a window of its own through hooksecurefunc (CB.SKINS) gets the line the
-- game wrote, so the wrapper has to be the outermost one: it wraps again when such an add-on hooked in after it.
-- Safety: the wrapper never raises, a secret line goes through as it is, and three errors switch the
-- badge off. A line that carries a badge is not changed again, so other chat add-ons may wrap the same
-- function before or after this one.
local _, ns = ...
local CBL, PL, PN, Consent, Store = ns.ChatBadgeLogic, ns.PresenceLogic, ns.PlayerName, ns.Consent, ns.Store
local CRL = ns.CrestLogic

local CB = {}
ns.ChatBadge = CB

CB.FN = "presenceMark"
CB.MAX_ERRORS = 3
-- Chat add-ons that format the line themselves: the badge waits for the user's word there.
CB.OTHER_ADDONS = { "ElvUI", "Prat-3.0", "Chatter", "Glass", "Chattynator" }
-- Chat skins that copy the line of Blizzard's chat frame into a window of their own with a post-hook (the hook
-- gets the arguments of the call, so a wrapper inside the hook is not seen): the badge only shows there when the
-- wrapper of this add-on is the outermost one.
CB.SKINS = { "EllesmereUIChat" }
-- Times the wrapper of one window is put around the hook of a skin again (a bound against add-ons that fight for
-- the outer place).
CB.MAX_REWRAPS = 3
-- Seconds after entering the world when the windows are checked again (skins are built by deferred passes).
CB.REINSTALL_DELAYS = { 8, 25 }
-- Chat windows are ChatFrame1.. (temporary windows come after the normal ones).
CB.MAX_FRAMES = 50
-- Seconds after entering the world until the wrapper goes in, so it sits after other add-ons.
CB.INSTALL_DELAY = 1

local errors, off = 0, false
-- Lines that went through a wrapper in this session, lines that got a badge and lines the client called secret
-- (status report: tells a wrapper that is never called from one that finds nothing to badge).
local seen = { lines = 0, badged = 0, secret = 0 }
-- frame -> true for every window that carries the wrapper (the wrapper stays, it passes through when off).
local wrapped = setmetatable({}, { __mode = "k" })
-- frame -> the newest wrapper (older ones pass through) and how often a window was wrapped again.
local outer = setmetatable({}, { __mode = "k" })
local rewraps = setmetatable({}, { __mode = "k" })
local rewrapTotal = 0

-- The last lines that went through the wrapper, newest last in a ring of TRACE_SIZE preallocated slots. Memory only:
-- no text, only the chat group, the first letters and the length of the name and the facts of the decision.
-- Nothing is formatted here, CB.Trace does that on request.
local TRACE_SIZE = 8
local trace, traceAt = {}, 0
for i = 1, TRACE_SIZE do
  trace[i] = {}
end
-- Facts of the last CB.Prefix call (what the lookup found), read by the trace right after it.
local last = { forever = false, count = 0 }

local function settings()
  return ns.db and ns.db.settings or {}
end

local function g(name)
  return rawget(_G, name)
end

-- Names out of `list` that are loaded add-ons.
local function loaded(list)
  local api = g("C_AddOns")
  local fn = type(api) == "table" and api.IsAddOnLoaded or g("IsAddOnLoaded")
  local out = {}
  if type(fn) == "function" then
    for _, name in ipairs(list) do
      local ok, is = pcall(fn, name)
      if ok and is then
        out[#out + 1] = name
      end
    end
  end
  return out
end

-- Switches ---------------------------------------------------------------------------------------------

-- Receiving is allowed for at least one audience.
function CB.Listening()
  return Consent.Allows(CB.FN, "receive", "group") or Consent.Allows(CB.FN, "receive", "guild")
end

-- Names of the other chat add-ons that are loaded.
function CB.OtherAddons()
  return loaded(CB.OTHER_ADDONS)
end

-- Names of the chat skins that are loaded (see CB.SKINS).
function CB.Skins()
  return loaded(CB.SKINS)
end

-- Switch on, consent given and not switched off by errors: the add-on logo may be shown.
function CB.ForeverOn()
  return not off and settings().chatBadge == true and CB.Listening()
end

-- At least one place in the line, not switched off by errors, and a source of logos: the receive consent of
-- crestMark (logos that add-on users send) or the local recognition (no consent, it receives nothing).
function CB.CrestsOn()
  if off or CRL.CleanCount(settings().chatCrestCount) < 1 then
    return false
  end
  return ns.CrestMark.Listening() or ns.CrestLocal.On()
end

-- Something may be shown anywhere.
function CB.On()
  return CB.ForeverOn() or CB.CrestsOn()
end

-- On, and no other chat add-on in the way unless the user said so: the chat windows get the badge.
function CB.Active()
  if not CB.On() then
    return false
  end
  return settings().chatBadgeOtherAddons == true or #CB.OtherAddons() == 0
end

-- The facts the status line of the settings card and CBL.Status work from (memory and settings only, nobody is asked).
function CB.StatusFacts()
  local s = settings()
  local _, switchedOff = CB.Errors()
  return {
    off = switchedOff,
    forever = CB.ForeverOn(),
    switch = s.chatBadge == true,
    listening = CB.Listening(),
    crests = CRL.CleanCount(s.chatCrestCount),
    crestSource = ns.CrestMark.Listening() or ns.CrestLocal.On(),
    crestLocal = ns.CrestLocal.On(),
    directory = CRL.Directory.Count(),
    blockers = s.chatBadgeOtherAddons == true and {} or CB.OtherAddons(),
    heard = ns.Presence.Count(),
    localState = (ns.CrestLocal.Report() or { guildState = "unread" }).guildState,
    channelsOff = CBL.ChannelsOff(s.chatBadgeChannels),
    skins = CB.Skins(),
    sending = Consent.Allows(CB.FN, "send", "group") or Consent.Allows(CB.FN, "send", "guild"),
  }
end

function CB.Style()
  return CBL.CleanStyle(settings().chatBadgeStyle)
end

-- Badge markup for a player ("" for everybody else and while nothing is on), for the own message window: the
-- same settings and the same consent as the chat lines. The add-on logo comes first, then the guild and the
-- community logos (as many as chatCrestCount says), the add-on logo shows all of them on hover. Which logos a
-- player has is decided in CrestLocal.Shown (sent by an add-on user, else recognized locally). size: pixel height,
-- default 14. The own name needs settings.chatBadgeSelf.
function CB.Prefix(name, size)
  last.forever, last.count, last.tag, last.first = false, 0, nil, nil
  if type(name) ~= "string" or not CB.On() then
    last.tag = "off"
    return ""
  end
  local s = settings()
  size = CBL.Height(size or s.chatBadgeSize)
  local mine = PN.Equal(name, PN.Self())
  if mine and s.chatBadgeSelf ~= true then
    last.tag = "own name"
    return ""
  end
  local forever = ""
  if CB.ForeverOn() then
    forever = mine and PL.Badge(name, CB.Style(), size) or ns.Presence.Badge(name, CB.Style(), size)
  end
  local crests = CB.CrestsOn()
  local count = crests and CRL.CleanCount(s.chatCrestCount) or 0
  local entries, tag = {}, nil
  if forever ~= "" or count > 0 then
    entries, tag = ns.CrestLocal.Shown(name)
  end
  last.forever, last.count, last.first, last.tag = forever ~= "", count, entries[1], tag
  if count == 0 then
    last.tag = CRL.CleanCount(s.chatCrestCount) < 1 and "count=0" or "no source"
  end
  return CRL.Compose(name, forever, entries, count, size)
end

-- Rewriting --------------------------------------------------------------------------------------------

local function fontSize(frame)
  local ok, _, size = pcall(frame.GetFont, frame)
  return ok and size or nil
end

-- Puts the facts of one line into the next slot of the ring.
local function record(group, name, why)
  traceAt = traceAt % TRACE_SIZE + 1
  local slot = trace[traceAt]
  slot.group, slot.why = group, why
  if name then
    slot.head, slot.len, slot.realm = name:sub(1, 8), #name, name:find("-", 1, true) ~= nil
  else
    slot.head, slot.len, slot.realm = nil, nil, nil
  end
  if why == "badge" or why == "no logo" then
    slot.forever, slot.count, slot.tag, slot.first = last.forever, last.count, last.tag, last.first
  else
    slot.forever, slot.count, slot.tag, slot.first = nil, nil, nil, nil
  end
end

local function rewrite(frame, text)
  local s = settings()
  if text ~= nil and ns.AutoGuard.Safe(text) == nil then
    seen.secret = seen.secret + 1
    record(nil, nil, "secret line")
    return nil
  end
  local name, group
  local result, why, info = CBL.Rewrite(text, {
    safe = ns.AutoGuard.Safe,
    channels = s.chatBadgeChannels,
    badge = function(who, chat)
      name, group = who, chat
      return CB.Prefix(who, CBL.Height(s.chatBadgeSize, fontSize(frame)))
    end,
  })
  if result then
    record(group, name, "badge")
  elseif why == "no logo" then
    record(group, name, why)
  elseif why == "channel off" or why == "has badge" then
    record(info.group, info.name, why)
  end
  return result
end

-- The head of a name for the trace: the first two characters and the length, never the name.
local function who(slot)
  if not slot.head then
    return "-"
  end
  return string.format("%s(%d)%s", PN.Cut(slot.head, 2), slot.len, slot.realm and "+realm" or "")
end

-- What the lookup of a line found, as text.
local function outcome(slot)
  local why = slot.why
  if why == "inactive" then
    return CB.On() and "other addon" or "off"
  elseif why ~= "badge" and why ~= "no logo" then
    return why
  end
  local part = slot.tag
  if part == "local" then
    part = "hit " .. tostring(ns.CrestLocalLogic.Source(slot.first))
  elseif part == "sent" then
    part = "hit sent by the player"
  elseif part == "off" then
    part = "local recognition off"
  elseif part == "no hit" then
    part = "no hit in index"
  elseif part == nil then
    part = "none"
  end
  return string.format("forever=%s local=%s", slot.forever and "yes" or "no", part)
end

-- The last lines of the wrapper as text, newest first: "<group> <name head>(<length>) <outcome>". Built on request
-- only.
function CB.Trace()
  local out = {}
  for i = 0, TRACE_SIZE - 1 do
    local slot = trace[(traceAt - i - 1) % TRACE_SIZE + 1]
    if not slot.why then
      break
    end
    out[#out + 1] = string.format("%s %s %s", slot.group or "-", who(slot), outcome(slot))
  end
  return out
end

local function fail(err)
  errors = errors + 1
  ns.Log.warn("chatbadge: %s", tostring(err))
  if errors < CB.MAX_ERRORS or off then
    return
  end
  -- Off first: the notice below is itself a chat line.
  off = true
  Store.set("settings.chatBadge", false)
  local text = string.format(ns.L["chatbadge.off"], errors)
  ns.Errors.add({ msg = text, kind = "warning", ctx = "chatbadge" })
  ns.Notify(text, "warning")
end

local function wrapper(original, frame, generation)
  return function(self, text, ...)
    -- An older wrapper of the same window lets the newer one outside it do the work.
    if outer[frame] ~= nil and outer[frame] ~= generation then
      return original(self, text, ...)
    end
    local line = text
    seen.lines = seen.lines + 1
    if CB.Active() then
      local ok, result = pcall(rewrite, self, text)
      if ok then
        line = result or text
        if result then
          seen.badged = seen.badged + 1
        end
      else
        pcall(fail, result)
      end
    else
      record(nil, nil, "inactive")
    end
    return original(self, line, ...)
  end
end

local function install(frame)
  if type(frame) ~= "table" or type(frame.AddMessage) ~= "function" then
    return
  end
  local again = false
  if wrapped[frame] then
    -- A skin hooked in after this wrapper and reads the line the game wrote: go around it, a few times at most.
    if (rewraps[frame] or 0) >= CB.MAX_REWRAPS or outer[frame] == nil or #CB.Skins() == 0 then
      return
    end
    local current = frame.AddMessage
    if type(current) ~= "function" or current == outer[frame].fn then
      return
    end
    again = true
  end
  -- Marked first: a failed assignment is not retried on every refresh.
  wrapped[frame] = true
  local token = {}
  pcall(function()
    local fn = wrapper(frame.AddMessage, frame, token)
    token.fn = fn
    outer[frame] = token
    frame.AddMessage = fn
  end)
  if again then
    rewraps[frame] = (rewraps[frame] or 0) + 1
    rewrapTotal = rewrapTotal + 1
  else
    pcall(ns.CrestLink.Hook, frame)
  end
end

-- Puts the wrapper into every chat window that exists, only while the badge is active. Safe to call often.
function CB.Install()
  if not CB.Active() then
    return false
  end
  for i = 1, CB.MAX_FRAMES do
    local frame = g("ChatFrame" .. i)
    if type(frame) == "table" then
      install(frame)
    end
  end
  return true
end

-- True when the window carries the wrapper.
function CB.Wrapped(frame)
  return wrapped[frame] == true
end

-- Chat windows that carry the wrapper and chat windows that exist (status report).
function CB.WrappedCount()
  local with, total = 0, 0
  for i = 1, CB.MAX_FRAMES do
    local frame = g("ChatFrame" .. i)
    if type(frame) == "table" then
      total = total + 1
      if wrapped[frame] == true then
        with = with + 1
      end
    end
  end
  return with, total
end

-- Counters of this session: { lines, badged, secret }.
function CB.Seen()
  return { lines = seen.lines, badged = seen.badged, secret = seen.secret }
end

-- How often a wrapper was put around a skin that hooked in after it.
function CB.Rewraps()
  return rewrapTotal
end

-- Errors and the switch-off of this session; the user switching the badge on again starts afresh.
function CB.Errors()
  return errors, off
end

local function reset()
  errors, off = 0, false
end

ns.On("PLAYER_ENTERING_WORLD", function()
  local timer = g("C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    pcall(timer.After, CB.INSTALL_DELAY, ns.Wrap("chatbadge", CB.Install))
    for _, delay in ipairs(CB.REINSTALL_DELAYS) do
      pcall(timer.After, delay, ns.Wrap("chatbadge", CB.Install))
    end
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path, value)
  if
    (path == "settings.chatBadge" and value == true)
    or (path == "settings.chatCrestCount" and (tonumber(value) or 0) > 0)
    or (path == "settings.crestLocal" and value == true)
  then
    reset()
  end
  if
    type(path) == "string"
    and (path:find("^settings%.chatBadge") or path:find("^settings%.chatCrest") or path == "settings.crestLocal")
  then
    ns.Safe("chatbadge", CB.Install)
  end
end)
ns.On("FG_CONSENT_CHANGED", function(_, fn, dir, _, value)
  if fn == ns.CrestMark.FN and dir == "receive" and value == true then
    reset()
  end
  if fn == CB.FN or fn == ns.CrestMark.FN then
    ns.Safe("chatbadge", CB.Install)
  end
end)
ns.On("FG_CONSENT_WITHDRAWN", function(_, fn)
  if fn == CB.FN or fn == ns.CrestMark.FN then
    ns.Safe("chatbadge", CB.Install)
  end
end)
ns.On("FG_PRESENCE_UPDATE", function()
  ns.Safe("chatbadge", CB.Install)
end)
ns.On("FG_CREST_UPDATE", function()
  ns.Safe("chatbadge", CB.Install)
end)
-- Temporary windows (whisper pop-outs) appear after login.
local hook = g("hooksecurefunc")
if type(hook) == "function" and type(g("FCF_OpenTemporaryWindow")) == "function" then
  pcall(hook, "FCF_OpenTemporaryWindow", ns.Wrap("chatbadge", CB.Install))
end
