-- The native aura container (ns.AuraNative): the game side of AuraNativeLogic. An AuraContainer is a frame of the
-- game (add-on Blizzard_AuraContainer, template CustomAuraContainerTemplate) whose slots the engine fills itself
-- with the buttons of the auras that pass a spell id filter, in combat too: icon, ring, time and stacks come from
-- the engine and Lua never reads a value. A container cannot be destroyed and its slots cannot be rebuilt in
-- combat, so the add-on keeps a pool of them: Acquire gives one to an element (an aura element frame, the owner),
-- Release hides it and keeps it for the next one, Reconfigure changes the spell ids outside a fight and waits for
-- the end of it otherwise. Every call to the game is protected, a refusal puts the element back on its computed
-- display (state "fallback"), and in combat only the calls of AuraNativeLogic.COMBAT_CALLS reach the container.
--
-- Everything the engine builds is drawn by a "face": a frame under the button the engine made, with the widgets
-- of an aura element (CursorCooldowns.Kit.widgetOf: icon, ring, number, stacks, bar) so the native display has
-- the look of the element. The face is bound once per button (initializeFrame, which the engine calls whenever it
-- builds one, in combat too) and styled with the props of the element. The container sits in a plain holder frame
-- that moves to the element frame (the container itself never gets a new parent); its alpha shows or hides the
-- native display (see Show). Not measured in the client: the shape of the filter options of AddAuraSlot (three
-- forms are tried), whether SetDurationText takes the formatter and colour curve options, SetDurationBar, and
-- everything done to a container in combat except the whitelisted calls.
local _, ns = ...
local NL, SL, TL = ns.AuraNativeLogic, ns.ShowLogic, ns.TimeFormatLogic
local Kit = ns.CursorCooldowns.Kit
local TF = ns.TimeFormat
local G = ns.CursorTimers.Guard
local api, try = G.api, G.try

local AN = {}
ns.AuraNative = AN

local ADDON = "Blizzard_AuraContainer"
local TEMPLATE = "CustomAuraContainerTemplate"
local KEY = "fg"
-- Buttons one container may have faces for (one aura makes one button; a rebuilt slot makes a new one).
local FACE_MAX = 8
-- Containers kept ready beyond the ones in use, so an element that appears later finds one.
local SPARE = 1

-- What the session learned: the slot form that worked, the text ways the game refused, whether the client has the
-- container at all (nil until the first container was tried).
local session = { form = nil, refused = {}, available = nil, why = nil }
local pool = {}
local holding = setmetatable({}, { __mode = "k" })
local wanted = setmetatable({}, { __mode = "k" })

-- What the diagnosis windows read: the calls that were made and refused.
AN.diag = { calls = 0, failed = 0, last = nil }

-- Game access --------------------------------------------------------------------------------------------------

-- Whether builds have to wait: the game withholds aura values or the player is in combat.
local function restricted()
  local secret = Kit.flagOf(try(api("C_Secrets", "ShouldAurasBeSecret")))
  local combat = Kit.flagOf(try(api(nil, "InCombatLockdown"))) == true
    or Kit.flagOf(try(api(nil, "UnitAffectingCombat"), "player")) == true
  return NL.Restricted(secret, combat)
end

AN.Restricted = restricted

-- container:name(...) protected and checked against the combat whitelist: true and the first result, or false and
-- the reason.
local function invoke(entry, locked, name, ...)
  if not NL.Allowed(name, locked) then
    return false, "restricted"
  end
  local container = entry.container
  local ok, fn = pcall(function()
    return container[name]
  end)
  if not ok or type(fn) ~= "function" then
    return false, "absent"
  end
  local done, a = pcall(fn, container, ...)
  local diag = AN.diag
  diag.calls = diag.calls + 1
  if not done then
    diag.failed, diag.last = diag.failed + 1, name .. ": " .. tostring(a)
    return false, tostring(a)
  end
  return true, a
end

local function fail(entry, why)
  entry.state = NL.Next(entry.state, "fail")
  entry.why = why
  return false, why
end

local function policyNone()
  local policy = rawget(_G, "CustomAuraContainerAuraProcessingPolicy")
  return type(policy) == "table" and type(policy.None) == "number" and policy.None or nil
end

-- Face ---------------------------------------------------------------------------------------------------------

local function sizeOf(entry)
  local look = entry.look
  local element = look and look.element
  local w, h = element and element.w, element and element.h
  if type(w) ~= "number" or w <= 0 then
    w = entry.holder:GetWidth()
  end
  if type(h) ~= "number" or h <= 0 then
    h = entry.holder:GetHeight()
  end
  return w, h
end

-- Puts the engine's button over the element: the whole container, or in the clip variant the element's size from
-- the left edge of the container (the container's own width then follows what the engine builds).
local function placeButton(entry, button)
  if entry.clip then
    local w, h = sizeOf(entry)
    local sized = pcall(button.SetSize, button, w, h)
    return sized and pcall(button.SetPoint, button, "TOPLEFT", entry.container, "TOPLEFT", 0, 0)
  end
  if pcall(button.SetAllPoints, button, entry.container) then
    return true
  end
  local w, h = sizeOf(entry)
  return pcall(button.SetSize, button, w, h)
    and pcall(button.SetPoint, button, "CENTER", entry.container, "CENTER", 0, 0)
end

-- The number: the formatter (with a gate when the element shows only below a time) and the colour curve go to the
-- engine as options of SetDurationText, the first way it accepts. A refusal outside a fight is remembered.
local function bindText(face, p, locked)
  local gate = p.showWhen == "below" and p.showBelow + SL.EPSILON or nil
  local formatter = TF.Formatter(p, gate) or (gate and TF.Formatter(p)) or nil
  local curve
  if p.colorCurve and (p.curveTarget == "text" or p.curveTarget == "all") then
    curve = Kit.curveOf(face.st)
  end
  local property = Kit.enumValue("DurationTextBindingProperty", "RemainingDuration")
  local key = table.concat({ TL.Key(p, nil, gate), tostring(formatter), tostring(curve) }, "|")
  if face.textKey == key and face.text ~= nil then
    return
  end
  face.textKey, face.text = key, "none"
  for _, way in ipairs(NL.TextWays(formatter ~= nil, curve ~= nil and property ~= nil, session.refused)) do
    local options = NL.TextOptions(way, formatter, curve, property)
    local ok
    if options == nil then
      ok = pcall(face.button.SetDurationText, face.button, face.st.timer)
    else
      ok = pcall(face.button.SetDurationText, face.button, face.st.timer, options)
    end
    if ok then
      face.text = way
      return
    elseif not locked then
      session.refused[way] = true
    end
  end
end

-- Look, text and bar of one face from the props of the element (stored as entry.look).
local function styleFace(entry, face, locked)
  local look = entry.look
  if not look then
    return
  end
  face.st.p = look.p
  pcall(Kit.layout, face.st, look.element)
  if not locked or face.fresh then
    bindText(face, look.p, locked)
  end
  if face.st.bar and not face.bar then
    face.bar = pcall(face.button.SetDurationBar, face.button, face.st.bar)
  end
  face.fresh = nil
end

-- Called by the engine for every button it builds (in combat too): the face with the widgets, bound to the button.
local function bindFace(entry, button)
  if #entry.faces >= FACE_MAX then
    return
  end
  local frame = CreateFrame("Frame", nil, button)
  frame:SetAllPoints(button)
  local st = Kit.widgetOf(frame)
  local face = { button = button, frame = frame, st = st, fresh = true }
  entry.faces[#entry.faces + 1] = face
  face.placed = placeButton(entry, button)
  face.icon = pcall(button.SetIcon, button, st.icon)
  pcall(st.cd.SetUseAuraDisplayTime, st.cd, true)
  face.ring = pcall(button.SetDurationCooldown, button, st.cd)
  face.count = pcall(button.SetApplicationCount, button, st.charges)
  styleFace(entry, face, restricted())
end

local function initializer(entry)
  return function(button)
    local ok, err = pcall(bindFace, entry, button)
    if not ok then
      entry.why = "bind: " .. tostring(err)
    end
  end
end

-- Container --------------------------------------------------------------------------------------------------

local function makeContainer(holder)
  local load = api("C_AddOns", "LoadAddOn")
  if load then
    pcall(load, ADDON)
  end
  local container = CreateFrame("AuraContainer", nil, holder, TEMPLATE)
  for _, name in ipairs(NL.REQUIRED) do
    if type(container[name]) ~= "function" then
      error("container method " .. name .. " is missing", 0)
    end
  end
  return container
end

-- A new entry: the holder and a disabled container for the player. nil and the reason when the client has none.
local function create()
  if session.available == false then
    return nil, session.why
  end
  local none = policyNone()
  local holder = CreateFrame("Frame", nil, UIParent)
  holder:Hide()
  local made, container = pcall(makeContainer, holder)
  if not made or none == nil then
    session.available, session.why = false, made and "no processing policy enum" or tostring(container)
    return nil, session.why
  end
  local entry = { container = container, holder = holder, state = "free", faces = {}, keys = 0 }
  entry.initialize = initializer(entry)
  container:SetAllPoints(holder)
  local ok, why = invoke(entry, false, "SetEnabled", false)
  if ok then
    ok, why = invoke(entry, false, "SetAuraProcessingPolicy", none)
  end
  if ok then
    ok, why = invoke(entry, false, "SetUnit", NL.UNIT)
  end
  if not ok then
    session.available, session.why = false, tostring(why)
    return nil, session.why
  end
  session.available = true
  pool[#pool + 1] = entry
  return entry
end

-- Adds a slot for the spec: the forms of the options one after the other, the first the game takes without an
-- error is remembered. A new key for every try (a refused slot may exist half-made).
local function addSlot(entry, spec)
  for _, form in ipairs(NL.FormOrder(session.form)) do
    if entry.keys >= NL.SLOT_MAX then
      return false, "no free slot key"
    end
    entry.keys = entry.keys + 1
    local key = KEY .. entry.keys
    local ok, why =
      invoke(entry, false, "AddAuraSlot", key, spec.filter, NL.SlotOptions(form, spec.ids, entry.initialize))
    if ok then
      session.form = form
      entry.slotKey = key
      return true
    end
    entry.why = why
  end
  return false, entry.why
end

-- Changes the filters of the slot; a game without the update calls (or one that refuses them) gets a new slot
-- and the old one is switched off.
local function changeSlot(entry, spec)
  local key = entry.slotKey
  local ok = key ~= nil
    and invoke(entry, false, "SetAuraSlotCandidateFilters", key, NL.FilterOptions(spec.ids))
    and invoke(entry, false, "SetAuraSlotFilterString", key, spec.filter)
  if ok then
    return true
  end
  if key then
    invoke(entry, false, "SetAuraSlotEnabled", key, false)
  end
  return addSlot(entry, spec)
end

local function placeContainer(entry)
  local container, holder = entry.container, entry.holder
  container:ClearAllPoints()
  if entry.clip then
    container:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    container:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
  else
    container:SetAllPoints(holder)
  end
end

-- The clip variant of the condition "missing": a frame over the element from the right edge of the container to
-- the right edge of the element that clips its child, the grey symbol. The symbol is at the element's place, so
-- the clip shows it only where the container is not, hoping the container is as wide as the buttons the engine
-- builds and has no width while the aura is missing. Not measured.
local function clipOf(entry)
  if not entry.clipFrame then
    local frame = CreateFrame("Frame", nil, entry.holder)
    frame:SetClipsChildren(true)
    frame:SetPoint("TOPLEFT", entry.container, "TOPRIGHT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", entry.holder, "BOTTOMRIGHT", 0, 0)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", entry.holder, "TOPLEFT", 0, 0)
    icon:SetPoint("BOTTOMRIGHT", entry.holder, "BOTTOMRIGHT", 0, 0)
    icon:SetDesaturated(true)
    entry.clipFrame, entry.clipIcon = frame, icon
  end
  return entry.clipFrame, entry.clipIcon
end

-- Builds the slot of `want` (outside a fight only): the first slot or a change of the held one.
local function build(entry, want)
  entry.look, entry.clip = want, want.clip == true
  placeContainer(entry)
  if entry.clip then
    clipOf(entry)
  end
  local key = NL.SpecKey(want.spec)
  local ok, why
  if entry.applied == nil then
    ok, why = addSlot(entry, want.spec)
  else
    ok, why = changeSlot(entry, want.spec)
  end
  if not ok then
    return fail(entry, why)
  end
  entry.applied, entry.applyClip, entry.want = key, entry.clip, nil
  for _, face in ipairs(entry.faces) do
    styleFace(entry, face, false)
  end
  entry.state = NL.Next(entry.state, "acquire")
  return true
end

-- The holder goes under the element frame (outside a fight only).
local function attachHolder(entry, owner)
  local holder = entry.holder
  holder:SetParent(owner.frame)
  holder:ClearAllPoints()
  holder:SetAllPoints(owner.frame)
  holder:SetFrameLevel((owner.top and owner.top:GetFrameLevel() or owner.frame:GetFrameLevel() + 2) + 1)
end

local function takeFree(owner)
  local best
  for _, entry in ipairs(pool) do
    if entry.owner == nil and (best == nil or entry.lastOwner == owner) then
      best = entry
    end
  end
  return best
end

local function freeCount()
  local n = 0
  for _, entry in ipairs(pool) do
    if entry.owner == nil then
      n = n + 1
    end
  end
  return n
end

-- A free container that still holds exactly this configuration for this owner (nothing to rebuild).
local function findWarm(owner, want)
  local key = NL.SpecKey(want.spec)
  for _, entry in ipairs(pool) do
    if
      entry.owner == nil
      and entry.lastOwner == owner
      and entry.applied == key
      and entry.applyClip == (want.clip == true)
      and entry.state ~= "fallback"
    then
      return entry
    end
  end
  return nil
end

local function use(entry, owner, locked)
  entry.owner, entry.lastOwner, entry.shown = owner, owner, false
  holding[owner] = entry
  entry.holder:SetAlpha(0)
  entry.holder:Show()
  local ok, why = invoke(entry, locked, "SetEnabled", true)
  if not ok then
    return fail(entry, why)
  end
  invoke(entry, locked, "UpdateAllAuras")
  entry.state = NL.Next(entry.state, "acquire")
  return true
end

-- Public --------------------------------------------------------------------------------------------------------

-- Whether the client has the native container: true, false, or nil while nothing could be tried yet (no container
-- is made in a fight). The first call outside a fight makes a container, which stays in the pool.
function AN.Available()
  if session.available == nil and NL.CanBuild(restricted()) then
    create()
  end
  return session.available
end

-- Why the container is not available (for the diagnosis), nil while it is or while unknown.
function AN.Why()
  return session.why
end

-- Makes containers until `n` exist, outside a fight only; returns how many there are.
function AN.Reserve(n)
  while #pool < math.min(n, NL.POOL_MAX) and NL.CanBuild(restricted()) and session.available ~= false do
    if not create() then
      break
    end
  end
  return #pool
end

local function inUse()
  local n = 0
  for _ in pairs(holding) do
    n = n + 1
  end
  return n
end

-- Gives `owner` (an aura element frame state with `frame`) a container for `want` = { spec (AuraNativeLogic.Spec),
-- p (the props), element, clip, onChange(owner) }. Returns the entry and its state: "active", "pending" (a build
-- waits for the end of the fight, onChange runs then), "fallback" (the game refused) or "limit" (the pool is full),
-- the entry is nil in the last three.
function AN.Acquire(owner, want)
  if holding[owner] then
    return AN.Reconfigure(owner, want)
  end
  if not AN.Available() then
    if session.available == nil then
      wanted[owner] = want
      return nil, "pending"
    end
    return nil, "fallback"
  end
  local locked = restricted()
  local warm = findWarm(owner, want)
  local action = NL.AcquireAction({
    restricted = locked,
    warm = warm ~= nil,
    free = freeCount(),
    total = #pool,
    max = NL.POOL_MAX,
  })
  if action == "pending" then
    wanted[owner] = want
    return nil, "pending"
  elseif action == "limit" then
    return nil, "limit"
  end
  local entry = warm
  if action == "warm" then
    entry.look = want
  else
    entry = action == "cold" and takeFree(owner) or create()
    if not entry then
      return nil, "fallback"
    end
    attachHolder(entry, owner)
    if not build(entry, want) then
      return nil, "fallback"
    end
  end
  if not use(entry, owner, locked) then
    holding[owner], entry.owner = nil, nil
    return nil, "fallback"
  end
  for _, face in ipairs(entry.faces) do
    styleFace(entry, face, locked)
  end
  return entry, entry.state
end

-- Hides the container of `owner` and keeps it for the next element (it still holds its configuration, so the same
-- element finds it again at once, even in a fight).
function AN.Release(owner)
  wanted[owner] = nil
  local entry = holding[owner]
  if not entry then
    return
  end
  holding[owner] = nil
  entry.owner, entry.want, entry.shown = nil, nil, false
  entry.state = NL.Next(entry.state, "release")
  invoke(entry, restricted(), "SetEnabled", false)
  entry.holder:SetAlpha(0)
  entry.holder:Hide()
end

-- The spec or the look of a held container changed. Outside a fight the slot is rebuilt at once, in a fight the
-- last configuration stays and the change is applied when it ends. Same arguments as Acquire.
function AN.Reconfigure(owner, want)
  local entry = holding[owner]
  if not entry then
    if wanted[owner] then
      wanted[owner] = want
      return nil, "pending"
    end
    return AN.Acquire(owner, want)
  end
  local locked = restricted()
  local same = NL.SpecKey(want.spec) == entry.applied
    and (want.clip == true) == entry.applyClip
    and entry.state ~= "fallback"
  local action = NL.ReconfigureAction({ same = same, restricted = locked })
  entry.look = want
  if action == "apply" then
    if not build(entry, want) then
      return nil, "fallback"
    end
    invoke(entry, false, "UpdateAllAuras")
    entry.holder:SetAlpha(entry.shown and 1 or 0)
  elseif action == "defer" then
    entry.want = want
    entry.state = NL.Next(entry.state, "defer")
  end
  for _, face in ipairs(entry.faces) do
    styleFace(entry, face, locked)
  end
  return entry, entry.state
end

-- The native display of `owner` is on show (true: in combat) or hidden. The container keeps running in both cases,
-- only the alpha of its holder changes, an own frame whose alpha combat allows.
function AN.Show(owner, on)
  local entry = holding[owner]
  if entry then
    entry.shown = on == true
    entry.holder:SetAlpha(on and 1 or 0)
  end
end

-- The grey symbol of the clip variant (a texture) or none: shown or hidden with the clip frame.
function AN.Missing(owner, texture)
  local entry = holding[owner]
  if not entry then
    return
  end
  if texture ~= nil and entry.clip then
    local frame, icon = clipOf(entry)
    icon:SetTexture(texture)
    frame:Show()
  elseif entry.clipFrame then
    entry.clipFrame:Hide()
  end
end

-- The held entry of `owner` when its container works (state active), else nil.
function AN.Entry(owner)
  local entry = holding[owner]
  return entry and entry.state == "active" and entry or nil
end

-- What the pool and one owner look like, for the diagnosis windows and the panel.
function AN.Info(owner)
  local entry = holding[owner]
  local info = {
    available = session.available,
    why = session.why,
    total = #pool,
    free = freeCount(),
    used = inUse(),
    max = NL.POOL_MAX,
    pending = 0,
    deferred = 0,
    form = session.form,
  }
  for _ in pairs(wanted) do
    info.pending = info.pending + 1
  end
  for _, e in ipairs(pool) do
    if e.want then
      info.deferred = info.deferred + 1
    end
  end
  if entry then
    info.state, info.entryWhy, info.faces = entry.state, entry.why, #entry.faces
    info.text = entry.faces[1] and entry.faces[1].text or nil
    info.deferredOwn = entry.want ~= nil
    info.shown = entry.shown
  elseif wanted[owner] then
    info.state = "pending"
  end
  info.full = NL.Full(#pool, NL.POOL_MAX) and freeCount() == 0
  return info
end

-- Builds what waited for the end of a fight (new containers, deferred changes) and keeps the spare containers.
local function flush()
  local list = {}
  for owner, want in pairs(wanted) do
    list[#list + 1] = { owner, want }
  end
  wanted = setmetatable({}, { __mode = "k" })
  for _, item in ipairs(list) do
    AN.Acquire(item[1], item[2])
    if item[2].onChange then
      item[2].onChange(item[1])
    end
  end
  for _, entry in ipairs(pool) do
    if entry.want and entry.owner then
      local owner, want = entry.owner, entry.want
      AN.Reconfigure(owner, want)
      if want.onChange then
        want.onChange(owner)
      end
    end
  end
  if inUse() > 0 then
    AN.Reserve(inUse() + SPARE)
  end
end

ns.On("PLAYER_REGEN_ENABLED", flush)
ns.On("PLAYER_ENTERING_WORLD", function()
  if inUse() > 0 and NL.CanBuild(restricted()) then
    AN.Reserve(inUse() + SPARE)
  end
end)
