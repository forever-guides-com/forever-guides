-- Timer elements of the mouse cursor ring (ns.CursorTimers): the global cooldown ring (gcd), the cast and
-- channel ring of the player (cast) and the weapon swing timer (swing, ring or bar). The engine does the
-- drawing: a Cooldown frame with the ring texture as swipe, fed by duration objects, or a StatusBar for
-- the swing bar, so nothing here reads or computes a value the game keeps secret. render only sets the
-- appearance; drive registers one event frame per type while an element of that type is drawn in the game
-- (never in the editor preview) and release unregisters it. In the editor the preview comes from ctx.sim
-- (one simulation source per type) or stands still at PREVIEW.
local _, ns = ...
local U, L, CU, A, E, S = ns.U, ns.L, ns.CursorLogic, ns.CursorAssets, ns.CursorElements, ns.CursorSim

local T = {}
ns.CursorTimers = T

T.GCD_SPELL = 29515
T.PREVIEW = 0.62
T.HANDS = { "mainhand", "offhand", "ranged" }
T.STYLES = { "ring", "bar" }
T.IDLES = { "hidden", "faint" }

-- Opacity of the faint full ring (idle option) relative to the element opacity.
local FAINT = 0.25
-- Seconds a cast ring stays in the interrupt colour.
local FLASH = 0.4
-- Seconds after a stop in which a failure still belongs to that cast.
local LATE = 0.25
-- A frozen Cooldown for the preview: a duration this long moves a ring by far less than a pixel per minute.
local STILL = 100000
local SWING_TYPE = { mainhand = 0, offhand = 1, ranged = 2 }
local SWING_NAME = { mainhand = "MainHand", offhand = "OffHand", ranged = "Ranged" }

ns.AddLocale("enUS", {
  ["cursor.type.gcd"] = "Global cooldown ring",
  ["cursor.type.cast"] = "Cast ring",
  ["cursor.type.swing"] = "Swing timer",
  ["cursor.type.gcd.desc"] = "Shows the global cooldown, the short pause after each spell, as a ring that runs down.",
  ["cursor.type.cast.desc"] = "Shows the progress of the spell you are casting or channeling as a ring.",
  ["cursor.type.swing.desc"] = "Shows the time until your next weapon swing as a ring or a bar.",
  ["cursor.variant.swing.mainhand"] = "Swing timer: main hand",
  ["cursor.variant.swing.offhand"] = "Swing timer: off hand",
  ["cursor.variant.swing.ranged"] = "Swing timer: ranged",
  ["cursor.timers.swingOne"] = "Add one element per weapon: main hand, off hand and ranged each get their own swing timer.",
  ["cursor.preset.timers"] = "Timers (cooldown and cast)",
  ["cursor.preset.swing"] = "Swing timer",
  ["cursor.el.swing"] = "Main hand swing",
  ["cursor.el.swing2"] = "Off hand swing",
  ["cursor.panel.fills"] = "Fills while it runs",
  ["cursor.panel.idle"] = "When idle",
  ["cursor.panel.idle.hidden"] = "Hidden",
  ["cursor.panel.idle.faint"] = "Faint full ring",
  ["cursor.panel.castColor"] = "Cast color",
  ["cursor.panel.channelColor"] = "Channel color",
  ["cursor.panel.failColor"] = "Interrupt color",
  ["cursor.panel.spark"] = "Spark at the tip",
  ["cursor.panel.hand"] = "Weapon",
  ["cursor.panel.hand.mainhand"] = "Main hand",
  ["cursor.panel.hand.offhand"] = "Off hand",
  ["cursor.panel.hand.ranged"] = "Ranged",
  ["cursor.panel.style.ring"] = "Ring",
  ["cursor.panel.style.bar"] = "Bar",
  ["cursor.timers.swingNative"] = "The game's own swing bars are switched on. They show in addition to this timer. Switch them off in the combat options of the game if you want only one.",
})
ns.AddLocale("deDE", {
  ["cursor.type.gcd"] = "Ring der globalen Abklingzeit",
  ["cursor.type.cast"] = "Zauberring",
  ["cursor.type.swing"] = "Schwung-Zeitgeber",
  ["cursor.type.gcd.desc"] = "Zeigt die globale Abklingzeit, die kurze Pause nach jedem Zauber, als Ring, der abläuft.",
  ["cursor.type.cast.desc"] = "Zeigt den Fortschritt des Zaubers, den du wirkst oder kanalisierst, als Ring.",
  ["cursor.type.swing.desc"] = "Zeigt die Zeit bis zu deinem nächsten Waffenschlag als Ring oder Balken.",
  ["cursor.variant.swing.mainhand"] = "Schwung-Zeitgeber: Waffenhand",
  ["cursor.variant.swing.offhand"] = "Schwung-Zeitgeber: Schildhand",
  ["cursor.variant.swing.ranged"] = "Schwung-Zeitgeber: Fernkampf",
  ["cursor.timers.swingOne"] = "Füge pro Waffe ein eigenes Element hinzu: Waffenhand, Schildhand und Fernkampf bekommen je einen eigenen Schwung-Zeitgeber.",
  ["cursor.preset.timers"] = "Zeitgeber (Abklingzeit und Zauber)",
  ["cursor.preset.swing"] = "Schwung-Zeitgeber",
  ["cursor.el.swing"] = "Schwung Waffenhand",
  ["cursor.el.swing2"] = "Schwung Schildhand",
  ["cursor.panel.fills"] = "Füllt sich beim Ablauf",
  ["cursor.panel.idle"] = "Im Ruhezustand",
  ["cursor.panel.idle.hidden"] = "Ausgeblendet",
  ["cursor.panel.idle.faint"] = "Blasser voller Ring",
  ["cursor.panel.castColor"] = "Zauberfarbe",
  ["cursor.panel.channelColor"] = "Farbe beim Kanalisieren",
  ["cursor.panel.failColor"] = "Farbe bei Abbruch",
  ["cursor.panel.spark"] = "Funke an der Spitze",
  ["cursor.panel.hand"] = "Waffe",
  ["cursor.panel.hand.mainhand"] = "Waffenhand",
  ["cursor.panel.hand.offhand"] = "Schildhand",
  ["cursor.panel.hand.ranged"] = "Fernkampf",
  ["cursor.panel.style.ring"] = "Ring",
  ["cursor.panel.style.bar"] = "Balken",
  ["cursor.timers.swingNative"] = "Die eigenen Schwungleisten des Spiels sind eingeschaltet. Sie erscheinen zusätzlich zu diesem Zeitgeber. Schalte sie in den Kampfoptionen des Spiels aus, wenn du nur eine Anzeige willst.",
})

-- Guarded game access ----------------------------------------------------------------------------------

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Whether the game keeps a value secret. A missing check means nothing is secret, a check that fails means
-- the value is treated as secret.
local function hidden(v)
  local check = rawget(_G, "issecretvalue")
  if type(check) ~= "function" then
    return false
  end
  local ok, secret = pcall(check, v)
  return not ok or secret == true
end

-- The value as a number when it is a readable finite one, else nil. Never compares a secret.
local function readable(v)
  if type(v) ~= "number" or hidden(v) then
    return nil
  end
  return finite(v) and v or nil
end

local function now()
  local fn = rawget(_G, "GetTime")
  if type(fn) ~= "function" then
    return 0
  end
  local ok, t = pcall(fn)
  return ok and finite(t) and t or 0
end

-- The function `name` of the table `group` (or a global when group is nil), nil when the client lacks it.
local function api(group, name)
  local holder = group and rawget(_G, group) or _G
  local fn = type(holder) == "table" and holder[name] or nil
  return type(fn) == "function" and fn or nil
end

-- Calls fn(...) protected; the results, or nothing when it is missing or raises.
local function try(fn, ...)
  if type(fn) ~= "function" then
    return
  end
  local ok, a, b, c, d, e = pcall(fn, ...)
  if ok then
    return a, b, c, d, e
  end
end

-- obj:name(...) protected; true when the method exists and did not raise.
local function method(obj, name, ...)
  local fn = obj and obj[name]
  if type(fn) ~= "function" then
    return false
  end
  return (pcall(fn, obj, ...))
end

local function after(seconds, fn)
  local timer = rawget(_G, "C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    return pcall(timer.After, seconds, fn)
  end
  return false
end

-- Props -----------------------------------------------------------------------------------------------

local function hex(v, default)
  local raw = type(v) == "string" and v:match("^#?(%x%x%x%x%x%x)$")
  return raw and raw:lower() or default
end

local function oneOf(v, list, default)
  for _, item in ipairs(list) do
    if v == item then
      return v
    end
  end
  return default
end

local function flag(v, default)
  if type(v) == "boolean" then
    return v
  end
  return default
end

local function common(raw, d)
  return {
    shape = oneOf(raw.shape, CU.SHAPE_IDS, d.shape),
    thickness = finite(raw.thickness)
        and U.clamp(math.floor(raw.thickness + 0.5), CU.RING_THICKNESS_MIN, CU.RING_THICKNESS_MAX)
      or d.thickness,
    color = hex(raw.color, d.color),
    alpha = finite(raw.alpha) and U.clamp(raw.alpha, 0, 1) or d.alpha,
    reverse = flag(raw.reverse, d.reverse),
  }
end

CU.Register("gcd", {
  defaults = { shape = "circle", thickness = 3, color = "ffffff", alpha = 0.9, reverse = true, idle = "hidden" },
  size = { 48, 48 },
  clean = function(raw, d)
    local p = common(raw, d)
    p.idle = oneOf(raw.idle, T.IDLES, d.idle)
    return p
  end,
})

CU.Register("cast", {
  defaults = {
    shape = "circle",
    thickness = 3,
    color = "ffd24a",
    alpha = 0.95,
    reverse = true,
    channelColor = "5fd3d8",
    failColor = "ff4d4d",
    spark = false,
  },
  size = { 72, 72 },
  clean = function(raw, d)
    local p = common(raw, d)
    p.channelColor = hex(raw.channelColor, d.channelColor)
    p.failColor = hex(raw.failColor, d.failColor)
    p.spark = flag(raw.spark, d.spark)
    return p
  end,
})

CU.Register("swing", {
  defaults = {
    hand = "mainhand",
    style = "ring",
    shape = "circle",
    thickness = 3,
    color = "ff9f43",
    alpha = 0.9,
    reverse = true,
    idle = "hidden",
  },
  size = { 56, 56 },
  clean = function(raw, d)
    local p = common(raw, d)
    p.hand = oneOf(raw.hand, T.HANDS, d.hand)
    p.style = oneOf(raw.style, T.STYLES, d.style)
    p.idle = oneOf(raw.idle, T.IDLES, d.idle)
    return p
  end,
})

-- Widgets ---------------------------------------------------------------------------------------------

-- Mean side of the frame in px, the size a ring thickness is measured against.
local function sideOf(frame, element)
  local w, h = frame:GetWidth(), frame:GetHeight()
  if not (finite(w) and finite(h) and w > 0 and h > 0) then
    w, h = element.w, element.h
  end
  return finite(w) and finite(h) and w > 0 and h > 0 and (w + h) / 2 or CU.Size("ring")[1]
end

-- The parts of a timer element, created once per frame: the faint track behind, the Cooldown with the ring
-- as swipe. Later parts (flash, spark, bar) are added by the type that needs them.
local function widgetOf(frame)
  local st = frame.fgTimer
  if st then
    return st
  end
  st = { frame = frame }
  st.track = frame:CreateTexture(nil, "BACKGROUND")
  st.track:SetAllPoints(frame)
  st.cd = CreateFrame("Cooldown", nil, frame)
  st.cd:SetAllPoints(frame)
  method(st.cd, "SetDrawEdge", false)
  method(st.cd, "SetDrawBling", false)
  method(st.cd, "SetHideCountdownNumbers", true)
  frame.fgTimer = st
  return st
end

-- Progress of the preview: a number 0..1 from the simulation, false while the simulation is between two
-- runs, the still value when no simulation writes the key.
local function previewProgress(ctx, key)
  local sim = type(ctx) == "table" and type(ctx.sim) == "table" and ctx.sim or nil
  local v = sim and sim[key]
  if v == false then
    return false
  end
  if finite(v) then
    return U.clamp(v, 0, 1)
  end
  return T.PREVIEW
end

-- A frozen ring at `progress` (the elapsed share) in the engine's own cooldown drawing, so the direction
-- and the look are the ones of the game; false clears it.
local function freezeRing(st, progress)
  if progress == false then
    method(st.cd, "Clear")
    return
  end
  method(st.cd, "SetCooldown", now() - progress * STILL, STILL)
end

-- Ring appearance of a Cooldown: texture of the nearest stroke, colour, direction, and the faint track.
local function paintRing(frame, element, p, color)
  local st = widgetOf(frame)
  local side = sideOf(frame, element)
  local path = E.Texture(A.NearestStroke(p.shape, p.thickness, side))
  st.p, st.path, st.side = p, path, side
  local r, g, b = U.hex(color)
  method(st.cd, "SetSwipeTexture", path)
  method(st.cd, "SetSwipeColor", r, g, b, p.alpha)
  method(st.cd, "SetReverse", p.reverse == true)
  st.cd:Show()
  if p.idle == "faint" then
    local tr, tg, tb = U.hex(p.color)
    st.track:SetTexture(path)
    st.track:SetVertexColor(tr, tg, tb, p.alpha * FAINT)
    st.track:Show()
  else
    st.track:Hide()
  end
  return st
end

-- Event frames ----------------------------------------------------------------------------------------

-- One event frame per type. Add(owner, st) registers on the first owner, Remove(owner) unregisters with the
-- last one; handler(st, event, ...) runs for every owner that is drawn.
local function newHub(events, unitEvents, handler)
  local hub, owners, count, frame = {}, {}, 0, nil
  function hub.Add(owner, st)
    if owners[owner] == nil then
      count = count + 1
    end
    owners[owner] = st
    if count ~= 1 then
      return
    end
    if not frame then
      frame = CreateFrame("Frame")
      frame:SetScript(
        "OnEvent",
        ns.Wrap("cursortimers-event", function(_, event, ...)
          for _, st2 in pairs(owners) do
            handler(st2, event, ...)
          end
        end)
      )
    end
    for _, event in ipairs(events) do
      pcall(frame.RegisterEvent, frame, event)
    end
    for _, event in ipairs(unitEvents) do
      pcall(frame.RegisterUnitEvent, frame, event, "player")
    end
  end
  function hub.Remove(owner)
    if owners[owner] == nil then
      return
    end
    owners[owner] = nil
    count = count - 1
    if count == 0 and frame then
      frame:UnregisterAllEvents()
    end
  end
  function hub.Count()
    return count
  end
  return hub
end

-- Global cooldown ---------------------------------------------------------------------------------------

local function feedGcd(st)
  local duration = try(api("C_Spell", "GetSpellCooldownDuration"), T.GCD_SPELL)
  if duration == nil then
    method(st.cd, "Clear")
    return
  end
  method(st.cd, "SetCooldownFromDurationObject", duration)
end

local gcdHub = newHub({ "SPELL_UPDATE_COOLDOWN" }, {}, function(st)
  feedGcd(st)
end)

local function renderGcd(frame, element, ctx)
  local p = CU.Props("gcd", element.props)
  local st = paintRing(frame, element, p, p.color)
  if ctx and ctx.editor then
    freezeRing(st, previewProgress(ctx, "gcdProgress"))
  end
end

local function driveGcd(frame, _, ctx)
  local st = frame.fgTimer
  if (ctx and ctx.editor) or not st then
    return
  end
  gcdHub.Add(frame, st)
  feedGcd(st)
end

local function releaseGcd(frame)
  gcdHub.Remove(frame)
  local st = frame.fgTimer
  if st then
    method(st.cd, "Clear")
  end
end

-- Cast and channel ------------------------------------------------------------------------------------

local CAST_EVENTS = {
  "UNIT_SPELLCAST_START",
  "UNIT_SPELLCAST_STOP",
  "UNIT_SPELLCAST_FAILED",
  "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_DELAYED",
  "UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_CHANNEL_UPDATE",
  "UNIT_SPELLCAST_CHANNEL_STOP",
}

-- Colour and direction of a cast ("cast") or a channel, which fills the other way round.
local function castLook(st, mode)
  local p = st.p
  local r, g, b = U.hex(mode == "channel" and p.channelColor or p.color)
  method(st.cd, "SetSwipeColor", r, g, b, p.alpha)
  method(st.cd, "SetReverse", (mode == "channel") ~= (p.reverse == true))
  st.mode = mode
end

local function sparkOf(st)
  if not st.spark then
    st.spark = st.frame:CreateTexture(nil, "OVERLAY")
    st.spark:SetTexture(E.Texture("spark"))
    st.spark:SetBlendMode("ADD")
  end
  return st.spark
end

-- The spark on the ring at `progress` (elapsed share, clockwise from the top).
local function placeSpark(st, progress)
  local p = st.p
  local spark = sparkOf(st)
  local size = math.max(8, p.thickness * 3)
  local radius = math.max(0, (st.side or 0) / 2 - p.thickness / 2)
  local angle = progress * 2 * math.pi
  spark:ClearAllPoints()
  spark:SetSize(size, size)
  spark:SetPoint("CENTER", st.frame, "CENTER", radius * math.sin(angle), radius * math.cos(angle))
  local r, g, b = U.hex(st.mode == "channel" and p.channelColor or p.color)
  spark:SetVertexColor(r, g, b, p.alpha)
  spark:Show()
end

local function stopSpark(st)
  st.run = nil
  if st.frame:GetScript("OnUpdate") then
    st.frame:SetScript("OnUpdate", nil)
  end
  if st.spark then
    st.spark:Hide()
  end
end

-- The spark follows the cast only while the start and end time are readable numbers.
local function startSpark(st, infoName)
  stopSpark(st)
  if not (st.p and st.p.spark) then
    return
  end
  local _, _, _, from, to = try(api(nil, infoName), "player")
  from, to = readable(from), readable(to)
  if not (from and to and to > from) then
    return
  end
  st.run = { from = from, to = to }
  st.frame:SetScript("OnUpdate", function()
    local run = st.run
    if not run then
      return
    end
    local progress = (now() * 1000 - run.from) / (run.to - run.from)
    placeSpark(st, U.clamp(progress, 0, 1))
  end)
end

local function clearCast(st)
  method(st.cd, "Clear")
  stopSpark(st)
  st.active, st.guid = nil, nil
end

-- Another cast that fails or stops (a different spell pressed during this one) must not end this one.
local function sameCast(st, guid)
  return st.guid == nil or guid == nil or hidden(guid) or guid == st.guid
end

local function beginCast(st, mode, guid)
  if st.flash then
    st.flash:Hide()
  end
  st.flashToken = (st.flashToken or 0) + 1
  st.active, st.failed = true, nil
  if type(guid) == "string" and not hidden(guid) then
    st.guid = guid
  end
  castLook(st, mode)
  local duration
  if mode == "channel" then
    duration = try(api(nil, "UnitChannelDuration"), "player")
  else
    duration = try(api(nil, "UnitCastingDuration"), "player")
  end
  if duration == nil then
    method(st.cd, "Clear")
  else
    method(st.cd, "SetCooldownFromDurationObject", duration)
  end
  startSpark(st, mode == "channel" and "UnitChannelInfo" or "UnitCastingInfo")
end

local function failCast(st)
  clearCast(st)
  local p = st.p
  if not st.flash then
    st.flash = st.frame:CreateTexture(nil, "OVERLAY")
    st.flash:SetAllPoints(st.frame)
  end
  local r, g, b = U.hex(p.failColor)
  st.flash:SetTexture(st.path)
  st.flash:SetVertexColor(r, g, b, p.alpha)
  st.flash:Show()
  st.flashToken = (st.flashToken or 0) + 1
  local token = st.flashToken
  if
    not after(FLASH, function()
      if st.flashToken == token and st.flash then
        st.flash:Hide()
      end
    end)
  then
    st.flash:Hide()
  end
end

local function castEvent(st, event, _, guid)
  if not st.p then
    return
  end
  if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
    beginCast(st, "cast", guid)
  elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
    beginCast(st, "channel", guid)
  elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    if sameCast(st, guid) and not st.failed then
      clearCast(st)
      st.stoppedAt = now()
    end
    st.failed = nil
  elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
    -- The client may send STOP just before the failure, so a cast that ended an instant ago still counts.
    local live = st.active or (st.stoppedAt ~= nil and now() - st.stoppedAt < LATE)
    if live and sameCast(st, guid) then
      st.failed = true
      failCast(st)
    end
  end
end

local castHub = newHub({}, CAST_EVENTS, castEvent)

local function renderCast(frame, element, ctx)
  local p = CU.Props("cast", element.props)
  local st = paintRing(frame, element, p, p.color)
  -- A redraw during a cast keeps the colour and direction of the cast or channel that runs.
  if st.mode then
    castLook(st, st.mode)
  end
  if ctx and ctx.editor then
    local sim = type(ctx.sim) == "table" and ctx.sim or {}
    local mode = sim.castMode == "channel" and "channel" or "cast"
    castLook(st, mode)
    local progress = previewProgress(ctx, "castProgress")
    freezeRing(st, progress)
    if p.spark and progress ~= false then
      placeSpark(st, progress)
    elseif st.spark then
      st.spark:Hide()
    end
  elseif not (p.spark and st.run) and st.spark then
    st.spark:Hide()
  end
end

local function driveCast(frame, _, ctx)
  local st = frame.fgTimer
  if (ctx and ctx.editor) or not st then
    return
  end
  castHub.Add(frame, st)
end

local function releaseCast(frame)
  castHub.Remove(frame)
  local st = frame.fgTimer
  if st then
    clearCast(st)
    st.mode, st.failed = nil, nil
    st.flashToken = (st.flashToken or 0) + 1
    if st.flash then
      st.flash:Hide()
    end
  end
end

-- Weapon swing ------------------------------------------------------------------------------------------

-- Number of a swing type: the value of the client's enum when it has one, else the documented number.
local function swingType(hand)
  local enum = rawget(_G, "Enum")
  local types = type(enum) == "table" and enum.PlayerSwingType or nil
  local value = type(types) == "table" and types[SWING_NAME[hand]] or nil
  return type(value) == "number" and value or SWING_TYPE[hand]
end

-- Whether the hand is in use: the main hand always, the off hand and the ranged weapon when the attack
-- speed of the player has a number above zero for them. An answer that is missing or unreadable shows it.
function T.HandAvailable(hand)
  local index = hand == "offhand" and 2 or hand == "ranged" and 3 or nil
  if not index then
    return true
  end
  local fn = api(nil, "UnitAttackSpeed")
  if not fn then
    return true
  end
  local answer = { pcall(fn, "player") }
  if not answer[1] then
    return true
  end
  -- A value the game does not return is a hand that is not in use.
  local value = answer[index + 1]
  if value == nil then
    return false
  end
  if hidden(value) or type(value) ~= "number" then
    return true
  end
  return value > 0
end

-- The hint for the settings and the element panel when the game's own swing bars are on, else nil. Only read.
function T.SwingHint()
  local value = try(api(nil, "GetCVar"), "showSwingTimer")
  if type(value) == "string" and not hidden(value) and value == "1" then
    return L["cursor.timers.swingNative"]
  end
  return nil
end

local function barOf(st)
  if not st.bar then
    st.bar = CreateFrame("StatusBar", nil, st.frame)
    st.bar:SetAllPoints(st.frame)
    st.bar:SetStatusBarTexture(E.Texture("fill-square"))
    method(st.bar, "SetMinMaxValues", 0, 1)
    method(st.bar, "SetValue", 0)
  end
  return st.bar
end

local function stopBar(st)
  st.running = false
  if st.bar then
    if st.bar:GetScript("OnUpdate") then
      st.bar:SetScript("OnUpdate", nil)
    end
    st.bar:Hide()
  end
end

-- The look of the swing element: ring (Cooldown) or bar (StatusBar), the idle track for either.
local function paintSwing(frame, element, p, editor)
  local st = paintRing(frame, element, p, p.color)
  local r, g, b = U.hex(p.color)
  if p.style == "bar" then
    st.cd:Hide()
    local bar = barOf(st)
    bar:SetStatusBarColor(r, g, b, p.alpha)
    bar:SetShown(editor or st.running == true)
    if p.idle == "faint" then
      st.track:SetColorTexture(r, g, b, p.alpha * FAINT)
      st.track:Show()
    end
  else
    stopBar(st)
  end
  return st
end

local function renderSwing(frame, element, ctx)
  local p = CU.Props("swing", element.props)
  local editor = ctx and ctx.editor == true
  local st = paintSwing(frame, element, p, editor)
  if editor then
    local progress = previewProgress(ctx, "swingProgress")
    if p.style == "bar" then
      st.bar:SetValue(progress or 0)
    else
      freezeRing(st, progress)
    end
    frame:Show()
    return
  end
  frame:SetShown(T.HandAvailable(p.hand))
end

-- A duration object for the swing from the start now, for a duration the game keeps secret or a bar.
local function swingObject(st, seconds)
  local create = api("C_DurationUtil", "CreateDuration")
  if not create then
    return nil
  end
  st.duration = st.duration or try(create)
  if st.duration == nil or not method(st.duration, "SetTimeFromStart", now(), seconds) then
    return nil
  end
  return st.duration
end

local function startSwing(st, seconds)
  local p = st.p
  local length = readable(seconds)
  st.token = (st.token or 0) + 1
  local token = st.token
  if p.style == "bar" then
    local bar = barOf(st)
    bar:SetScript("OnUpdate", nil)
    local object = swingObject(st, seconds)
    if not (object and method(bar, "SetTimerDuration", object)) then
      if not (length and length > 0) then
        stopBar(st)
        return
      end
      -- No duration object: the bar follows the clock, which needs a number the game lets us read.
      local from = now()
      bar:SetScript("OnUpdate", function()
        bar:SetValue(U.clamp((now() - from) / length, 0, 1))
      end)
    end
    st.running = true
    bar:Show()
    if length and length > 0 then
      after(length, function()
        if st.token == token then
          stopBar(st)
        end
      end)
    end
    return
  end
  if length then
    method(st.cd, "SetCooldown", now(), length)
    return
  end
  local object = swingObject(st, seconds)
  if object then
    method(st.cd, "SetCooldownFromDurationObject", object)
  end
end

local function swingEvent(st, event, duration, kind)
  local p = st.p
  if not p then
    return
  end
  if event == "PLAYER_SWING" then
    local which = readable(kind)
    if which == nil then
      which = swingType("mainhand")
    end
    if which == swingType(p.hand) then
      startSwing(st, duration)
    end
  end
  st.frame:SetShown(T.HandAvailable(p.hand))
end

local swingHub = newHub({ "PLAYER_SWING", "PLAYER_EQUIPMENT_CHANGED" }, { "UNIT_ATTACK_SPEED" }, swingEvent)

local function driveSwing(frame, _, ctx)
  local st = frame.fgTimer
  if (ctx and ctx.editor) or not st then
    return
  end
  swingHub.Add(frame, st)
end

local function releaseSwing(frame)
  swingHub.Remove(frame)
  local st = frame.fgTimer
  if st then
    st.token = (st.token or 0) + 1
    method(st.cd, "Clear")
    stopBar(st)
  end
end

-- How many elements of each type are drawn in the game (and so listen), for the diagnosis and tests.
function T.Listening()
  return { gcd = gcdHub.Count(), cast = castHub.Count(), swing = swingHub.Count() }
end

-- Simulation (editor) ----------------------------------------------------------------------------------

-- One source per type; step writes the progress (elapsed share 0..1, false between two runs) into sim.
S.RegisterSource("gcd", {
  reset = function(sim)
    sim.gcdProgress = nil
  end,
  step = function(sim, _, t)
    local c = t % 3
    sim.gcdProgress = c < 1.5 and c / 1.5 or false
  end,
})

-- Two seconds of cast, half a second of pause, two seconds of channel, half a second of pause.
S.RegisterSource("cast", {
  reset = function(sim)
    sim.castProgress, sim.castMode = nil, nil
  end,
  step = function(sim, _, t)
    local c = t % 5
    if c < 2 then
      sim.castMode, sim.castProgress = "cast", c / 2
    elseif c >= 2.5 and c < 4.5 then
      sim.castMode, sim.castProgress = "channel", (c - 2.5) / 2
    else
      sim.castProgress = false
    end
  end,
})

S.RegisterSource("swing", {
  reset = function(sim)
    sim.swingProgress = nil
  end,
  step = function(sim, _, t)
    sim.swingProgress = (t % 2.4) / 2.4
  end,
})

-- Panels ----------------------------------------------------------------------------------------------

local HINT_H = 64

local function controls()
  return ns.CanvasEditor.Controls
end

local function newPanel(parent, kind, element, onChange, build)
  return controls().NewPanel(parent, {
    element = element,
    onChange = onChange,
    build = build,
    props = function(raw)
      return CU.Props(kind, raw)
    end,
  })
end

local function shapeRow(state, add, shown)
  local items = {}
  for i, shape in ipairs(A.SHAPES) do
    items[i] = { shape.id, A.RingStem(shape.id, 4), shape.key }
  end
  local gallery = controls().Gallery(state.panel, {
    label = "cursor.panel.shape",
    items = items,
    resolve = E.Texture,
    get = function()
      return state.get("shape")
    end,
    set = function(value)
      state.write("shape", value)
    end,
  })
  add(gallery, gallery:GetHeight(), shown)
end

local function thicknessRow(state, add, shown)
  local C = controls()
  add(
    C.Slider(state.panel, {
      label = "cursor.panel.thickness",
      min = CU.RING_THICKNESS_MIN,
      max = CU.RING_THICKNESS_MAX,
      step = 1,
      get = function()
        return state.get("thickness")
      end,
      set = function(v)
        state.write("thickness", v)
      end,
      format = function(v)
        return v .. " px"
      end,
    }),
    C.HEIGHT.slider,
    shown
  )
end

-- Colour and opacity of the main colour, `label` names it.
local function colorRow(state, add, label)
  local C = controls()
  add(
    C.ColorAlpha(state.panel, {
      label = label,
      owner = state.owner(),
      default = "ffffff",
      get = function()
        return state.get("color")
      end,
      alpha = function()
        return state.get("alpha")
      end,
      set = function(color, alpha)
        state.write("color", color)
        state.write("alpha", alpha)
      end,
    }),
    C.HEIGHT.colorAlpha
  )
end

local function toggleRow(state, add, label, key, shown)
  local C = controls()
  add(
    C.Toggle(state.panel, {
      label = label,
      get = function()
        return state.get(key)
      end,
      set = function(on)
        state.write(key, on == true)
      end,
    }),
    C.HEIGHT.toggle,
    shown
  )
end

local function choiceRow(state, add, label, key, list, prefix)
  local C = controls()
  add(
    C.Choice(state.panel, {
      label = label,
      options = C.Choices(list, prefix),
      get = function()
        return state.get(key)
      end,
      set = function(value)
        state.write(key, value)
      end,
    }),
    C.HEIGHT.choice
  )
end

function T.GcdPanel(parent, element, onChange)
  return newPanel(parent, "gcd", element, onChange, function(state, add)
    shapeRow(state, add)
    thicknessRow(state, add)
    colorRow(state, add, "cursor.panel.color")
    toggleRow(state, add, "cursor.panel.fills", "reverse")
    choiceRow(state, add, "cursor.panel.idle", "idle", T.IDLES, "cursor.panel.idle.")
  end)
end

function T.CastPanel(parent, element, onChange)
  return newPanel(parent, "cast", element, onChange, function(state, add)
    shapeRow(state, add)
    thicknessRow(state, add)
    colorRow(state, add, "cursor.panel.castColor")
    controls().ColorRow(state, add, "cursor.panel.channelColor", "channelColor", "5fd3d8")
    controls().ColorRow(state, add, "cursor.panel.failColor", "failColor", "ff4d4d")
    toggleRow(state, add, "cursor.panel.fills", "reverse")
    toggleRow(state, add, "cursor.panel.spark", "spark")
  end)
end

function T.SwingPanel(parent, element, onChange)
  return newPanel(parent, "swing", element, onChange, function(state, add)
    local isRing = function()
      return state.get("style") == "ring"
    end
    controls().TextRow(state, add, "cursor.timers.swingOne")
    choiceRow(state, add, "cursor.panel.hand", "hand", T.HANDS, "cursor.panel.hand.")
    choiceRow(state, add, "cursor.panel.style", "style", T.STYLES, "cursor.panel.style.")
    local hint = ns.W.Text(state.panel, { role = "ui", color = "warning", wrap = true })
    add(hint, HINT_H, function()
      local text = T.SwingHint()
      if text then
        ns.W.SetText(hint, nil, text)
      end
      return text ~= nil
    end)
    shapeRow(state, add, isRing)
    thicknessRow(state, add, isRing)
    colorRow(state, add, "cursor.panel.color")
    toggleRow(state, add, "cursor.panel.fills", "reverse", isRing)
    choiceRow(state, add, "cursor.panel.idle", "idle", T.IDLES, "cursor.panel.idle.")
  end)
end

-- Presets ---------------------------------------------------------------------------------------------

-- Each builder gets el(id, kind, w, h, props) and build(id, elements) of CursorLogic.
local PRESETS = {
  timers = function(el, build)
    return build("timers", {
      el("ring", "ring", 64, 64, { thickness = 1, alpha = 0.85 }),
      el("gcd", "gcd", 48, 48, { thickness = 2 }),
      el("cast", "cast", 80, 80, { thickness = 2 }),
    })
  end,
  swing = function(el, build)
    return build("swing", {
      el("ring", "ring", 64, 64, { thickness = 1, alpha = 0.85 }),
      el("swing", "swing", 80, 80, { thickness = 2 }),
      el("swing2", "swing", 48, 48, { thickness = 2, hand = "offhand", color = "5fd3d8" }),
    })
  end,
}
T.PRESET_IDS = { "timers", "swing" }

for _, id in ipairs(T.PRESET_IDS) do
  CU.RegisterPreset(id, PRESETS[id])
end

-- The presets of this module as the editor lists them: { id, name, layout } in the language of now.
function T.Presets()
  local out = {}
  for _, id in ipairs(T.PRESET_IDS) do
    local layout = CU.Preset(id)
    layout.name = L["cursor.preset." .. id]
    out[#out + 1] = { id = id, name = layout.name, layout = layout }
  end
  return out
end

-- Registry ---------------------------------------------------------------------------------------------

E.Register("gcd", { render = renderGcd, drive = driveGcd, release = releaseGcd, panel = T.GcdPanel })
E.Register("cast", { render = renderCast, drive = driveCast, release = releaseCast, panel = T.CastPanel })
-- One Add entry per weapon, so the player sees that every weapon can have its own timer.
T.VARIANTS = {}
for i, hand in ipairs(T.HANDS) do
  T.VARIANTS[i] = { id = hand, label = "cursor.variant.swing." .. hand, props = { hand = hand } }
end

-- Whether `name` is a name the editor gave on its own (empty, the type label or a variant label in any
-- language), so the list may show the weapon instead.
local function isDefaultName(name)
  if name == "" then
    return true
  end
  for _, strings in pairs(ns.Locales) do
    if name == strings["cursor.type.swing"] then
      return true
    end
    for _, hand in ipairs(T.HANDS) do
      if name == strings["cursor.variant.swing." .. hand] then
        return true
      end
    end
  end
  return false
end

-- The title of a swing element in the editor list: a name the player chose, else the weapon it times.
function T.SwingTitle(element)
  local name = type(element.name) == "string" and element.name or ""
  if not isDefaultName(name) then
    return name
  end
  return L["cursor.variant.swing." .. CU.Props("swing", element.props).hand]
end

E.Register("swing", {
  render = renderSwing,
  drive = driveSwing,
  release = releaseSwing,
  panel = T.SwingPanel,
  variants = T.VARIANTS,
  title = T.SwingTitle,
})
