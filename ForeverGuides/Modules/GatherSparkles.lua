-- Gathering sparkles: ore, herbs and (optionally) quest objects glitter when the player gets close, and
-- the glitter of the game for lootable quest items stays on. Written by Wosande for forever-guides.com.
--
-- The client always picks a soft target ("softinteract") and can give it a name plate. The effect hangs
-- on that plate, the kind of object comes from the cursor icon of the target (tooltip and quest log as
-- fallbacks), the state from the interaction range. The console variables this needs are written once,
-- their original values are kept in the SavedVariables and written back when the switch goes off.
-- Nothing here is protected, console variables are never touched in combat.
-- Style: own particles with the textures of the client, or the effect model of the client (see Logic.ResolveStyle).
local _, ns = ...
local Logic = ns.GatherSparklesLogic

local G = {}
ns.GatherSparkles = G

ns.AddLocale("enUS", {
  ["sparkles.notice"] = "Gathering sparkles are on. Turn them off in the settings.",
  ["sparkles.noModel"] = "The original sparkle model does not load here, own particles are used.",
  ["sparkles.diag.heading"] = "Gathering spots:",
  ["sparkles.diag.yes"] = "yes",
  ["sparkles.diag.no"] = "no",
  ["sparkles.diag.noDistance"] = "no distance for objects",
  ["sparkles.measure.chat"] = "Gathering spots: detection from %d yards (at most %d, %d measurements).",
  ["sparkles.measure.chatOne"] = "Gathering spots: detection from %d yards (at most %d, %d measurement).",
})
ns.AddLocale("deDE", {
  ["sparkles.notice"] = "Sammelpunkte funkeln ist aktiv. Abschalten unter Einstellungen.",
  ["sparkles.noModel"] = "Das Original-Modell lässt sich hier nicht laden, eigene Partikel werden genutzt.",
  ["sparkles.diag.heading"] = "Sammelpunkte:",
  ["sparkles.diag.yes"] = "ja",
  ["sparkles.diag.no"] = "nein",
  ["sparkles.diag.noDistance"] = "keine Entfernung für Objekte",
  ["sparkles.measure.chat"] = "Sammelpunkte: Erkennung ab %d Yards (höchstens %d, %d Messungen).",
  ["sparkles.measure.chatOne"] = "Sammelpunkte: Erkennung ab %d Yards (höchstens %d, %d Messung).",
})

local UNIT = "softinteract"
local STEP = Logic.STEP
-- Longest time one frame may feed the fixed step loop (a long frame must not run a burst of steps).
local MAX_CATCH_UP = 0.25
local LOGIN_DELAY = 2

local state = Logic.NewState()
local target = { cat = nil, locked = false, guid = nil, checks = 0 }
local host, probeTexture, attached, watcher
local activeUnits, directWorks, retarget = {}, false, false
local seenExists, seenGuid, unknownTarget = nil, nil, false
local dots = {}
local glow, dark
local want, style, modelLoaded, built
local sparkling, pendingApply, modelWarned = false, false, false
-- The distances seen to soft targets (largest plausible one, samples taken).
local distSeen, distTried = nil, 0
-- The measurement of the detection range (see Logic.SampleReady) and where the last position came from.
local measure, posSource = Logic.NewMeasure(), "none"
local acc, pollAcc, clock, watchAcc = 0, 0, 0, 0
local staticPlaced, paused = false, false
local lastR, lastG, lastB

local function global(name)
  return rawget(_G, name)
end

-- The value, or nil when it is secret or the client says the addon may not read it.
local function readable(value)
  if value == nil then
    return nil
  end
  local secret = global("issecretvalue")
  if type(secret) == "function" then
    local ok, hidden = pcall(secret, value)
    if not ok or hidden then
      return nil
    end
  end
  local access = global("canaccessvalue")
  if type(access) == "function" then
    local ok, allowed = pcall(access, value)
    if not ok or allowed == false then
      return nil
    end
  end
  return value
end

local function config()
  local settings = ns.db and ns.db.settings
  return settings and settings.sparkles
end

local function active()
  local c = config()
  return c ~= nil and c.enabled == true
end

local function reduced()
  return ns.Theme ~= nil and ns.Theme.reduceMotion() == true
end

local function inCombat()
  local f = global("InCombatLockdown")
  if type(f) ~= "function" then
    return false
  end
  local ok, result = pcall(f)
  return ok and result == true
end

-- Console variables -----------------------------------------------------------------------------------

local function cvarFunction(name)
  local api = global("C_CVar")
  local f = type(api) == "table" and api[name] or nil
  if type(f) ~= "function" then
    f = global(name)
  end
  return type(f) == "function" and f or nil
end

-- The value as text, nil when the client has no such variable.
local function getCVar(name)
  local f = cvarFunction("GetCVar")
  if not f then
    return nil
  end
  local ok, value = pcall(f, name)
  value = ok and readable(value) or nil
  return value ~= nil and tostring(value) or nil
end

local function setCVar(name, value)
  local f = cvarFunction("SetCVar")
  if not f then
    return false
  end
  local ok, result = pcall(f, name, value)
  return ok and result ~= false
end

-- Writes the variables the settings ask for and puts the originals back for the rest. In combat it
-- waits for the end of the fight.
function G.Apply()
  local c = config()
  if not c then
    return
  end
  if inCombat() then
    pendingApply = true
    return
  end
  pendingApply = false
  if type(c.saved) ~= "table" then
    c.saved = {}
  end
  c.range = Logic.NormalizeRange(c.range)
  local legacy = Logic.LegacyRestore(c.saved, getCVar(Logic.LEGACY_CVAR))
  if legacy ~= nil then
    setCVar(Logic.LEGACY_CVAR, legacy)
  end
  c.saved[Logic.LEGACY_CVAR] = nil
  local current = {}
  for _, name in ipairs(Logic.ManagedNames()) do
    current[name] = getCVar(name)
  end
  local plan = Logic.PlanCVars(
    c.saved,
    current,
    Logic.Desired({
      enabled = c.enabled == true,
      questItems = c.questItems == true,
      ore = c.ore == true,
      herbs = c.herbs == true,
      quest = c.quest == true,
      gameIcons = c.gameIcons ~= false,
      range = c.range,
      sparkling = sparkling or unknownTarget,
    })
  )
  for name, value in pairs(plan.remember) do
    c.saved[name] = value
  end
  for name, value in pairs(plan.set) do
    setCVar(name, value)
  end
  for name, value in pairs(plan.restore) do
    if setCVar(name, value) then
      c.saved[name] = nil
    end
  end
  for _, name in ipairs(plan.forget) do
    c.saved[name] = nil
  end
end

-- Kind of object -------------------------------------------------------------------------------------

-- true or false as the client says it, nil when the function is missing or the answer is secret; the
-- second value is true for a secret answer.
local function unitFlag(name, unit, other)
  local f = global(name)
  if type(f) ~= "function" then
    return nil, false
  end
  local ok, result = pcall(f, unit or UNIT, other)
  if not ok or result == nil then
    return nil, false
  end
  local value = readable(result)
  if value == true or value == false then
    return value, false
  end
  return nil, value == nil
end

-- World objects do not "exist" for UnitExists, UnitIsGameObject counts as well (see Logic.Exists).
local function unitExists()
  return Logic.Exists(unitFlag("UnitExists"), unitFlag("UnitIsGameObject")) == true
end

-- True when the client hides the answer: the module then leaves the target of the game alone.
local function targetUnknown()
  local exists, secretA = unitFlag("UnitExists")
  local isObject, secretB = unitFlag("UnitIsGameObject")
  return Logic.Exists(exists, isObject) == nil and (secretA or secretB)
end

-- A creature or corpse: only world objects get the effect.
local function isCreature()
  return unitFlag("UnitExists") == true and unitFlag("UnitIsGameObject") == false
end

local function targetGuid()
  local f = global("UnitGUID")
  if type(f) ~= "function" then
    return nil
  end
  local ok, guid = pcall(f, UNIT)
  return ok and readable(guid) or nil
end

-- The cursor icon of the target lands in a texture nobody sees: its file or atlas names the object.
-- Where the client takes a second argument (low priority icons) it is tried first, then the plain call.
-- Returns file, atlas and what the client said (for the support report): { ok, ret }.
local CURSOR_CALLS = { { true }, {} }

local function cursorName()
  local set = global("SetUnitCursorTexture")
  if type(set) ~= "function" then
    return nil, nil, {}
  end
  if not probeTexture then
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    probeTexture = frame:CreateTexture(nil, "ARTWORK")
  end
  local tex = probeTexture
  local file, atlas, said
  for _, extra in ipairs(CURSOR_CALLS) do
    pcall(tex.SetTexture, tex, nil)
    local ok, result = pcall(set, tex, UNIT, unpack(extra))
    said = said or { ok = ok, ret = ok and readable(result) or nil }
    local okAtlas, gotAtlas = pcall(tex.GetAtlas, tex)
    local okFile, gotFile = pcall(tex.GetTexture, tex)
    atlas = okAtlas and readable(gotAtlas) or nil
    file = okFile and readable(gotFile) or nil
    if file ~= nil or atlas ~= nil then
      break
    end
  end
  if type(file) == "number" then
    local api = global("C_Texture")
    local path = type(api) == "table" and type(api.GetFilePathFromFileID) == "function" and api.GetFilePathFromFileID
    if path then
      local okPath, name = pcall(path, file)
      file = okPath and readable(name) or file
    end
  end
  said.file, said.atlas = file, atlas
  return file, atlas, said
end

-- The tooltip data of the soft target, nil where the client has no such call or gives nothing.
local function tooltipData()
  local api = global("C_TooltipInfo")
  if type(api) ~= "table" or type(api.GetUnit) ~= "function" then
    return nil
  end
  local ok, data = pcall(api.GetUnit, UNIT)
  return ok and type(data) == "table" and data or nil
end

local function tooltipLines(data)
  local lines = {}
  if data and type(data.lines) == "table" then
    for _, line in ipairs(data.lines) do
      local text = type(line) == "table" and readable(line.leftText) or nil
      if type(text) == "string" then
        lines[#lines + 1] = text
      end
    end
  end
  return lines
end

-- true when the tooltip has a quest objective line, false when it has none, nil when the client cannot
-- tell (no tooltip data or no such line type).
local function tooltipQuestLine(data)
  local enum = global("Enum")
  local types = type(enum) == "table" and enum.TooltipDataLineType
  local questType = type(types) == "table" and types.QuestObjective or nil
  if questType == nil or not (data and type(data.lines) == "table") then
    return nil
  end
  for _, line in ipairs(data.lines) do
    if type(line) == "table" and readable(line.type) == questType then
      return true
    end
  end
  return false
end

-- The log entries as quest ids: the modern call first, the old title call for clients without it
-- (header rows skipped).
local function questIds()
  local ids = {}
  local log = global("C_QuestLog")
  local count, byIndex
  if type(log) == "table" and type(log.GetNumQuestLogEntries) == "function" then
    local ok, n = pcall(log.GetNumQuestLogEntries)
    count = ok and n or nil
    if type(log.GetQuestIDForLogIndex) == "function" then
      byIndex = function(i)
        local okId, id = pcall(log.GetQuestIDForLogIndex, i)
        return okId and id or nil
      end
    end
  end
  local oldCount, title = global("GetNumQuestLogEntries"), global("GetQuestLogTitle")
  if not byIndex and type(oldCount) == "function" and type(title) == "function" then
    local ok, n = pcall(oldCount)
    count = ok and n or nil
    byIndex = function(i)
      local okTitle, _, _, _, isHeader, _, _, _, id = pcall(title, i)
      return okTitle and not isHeader and id or nil
    end
  end
  if type(count) ~= "number" or not byIndex then
    return ids
  end
  for i = 1, count do
    local id = readable(byIndex(i))
    if type(id) == "number" and id > 0 then
      ids[#ids + 1] = id
    end
  end
  return ids
end

-- The raw texts of the open quest objectives of the quest log (finished ones and unreadable texts left out).
local function questObjectives()
  local out = {}
  local log = global("C_QuestLog")
  if type(log) ~= "table" or type(log.GetQuestObjectives) ~= "function" then
    return out
  end
  for _, id in ipairs(questIds()) do
    local ok, objectives = pcall(log.GetQuestObjectives, id)
    for _, objective in ipairs(ok and type(objectives) == "table" and objectives or {}) do
      if type(objective) == "table" and readable(objective.finished) ~= true then
        local text = readable(objective.text)
        if type(text) == "string" then
          out[#out + 1] = text
        end
      end
    end
  end
  return out
end

-- The normalized objective texts, built again after the quest log changed (QUEST_LOG_UPDATE), not on
-- every look at a target.
local questTexts, questStale = nil, true

local function openQuestTexts()
  if questStale or not questTexts then
    questTexts = Logic.QuestTexts(questObjectives())
    questStale = false
  end
  return questTexts
end

local function unitCall(name)
  local f = global(name)
  if type(f) ~= "function" then
    return nil, false
  end
  local ok, result = pcall(f, UNIT)
  if not ok then
    return nil, true
  end
  return readable(result), true
end

-- The three quest object checks, each true, false or nil (unknown): the client relates the target to an
-- active quest, its tooltip has a quest objective line, its name fits an open objective. Also the
-- number of cached objective texts and the name as compared.
local function questChecks(data, lines)
  local checks = {}
  local log = global("C_QuestLog")
  if type(log) == "table" and type(log.UnitIsRelatedToActiveQuest) == "function" then
    local ok, result = pcall(log.UnitIsRelatedToActiveQuest, UNIT)
    if ok then
      result = readable(result)
      if result == true or result == false then
        checks.related = result
      end
    end
  end
  checks.tooltipLine = tooltipQuestLine(data)
  local texts = openQuestTexts()
  checks.texts = #texts
  checks.nameMatch, checks.name = Logic.MatchesQuestText(lines[1] or unitCall("UnitName"), texts)
  return checks
end

-- Category ("ore", "herbs", "quest", the fallback "object" or nil), whether the object is locked for the
-- player, where the answer came from and what the cursor call said. Ore and herbs come
-- first (cursor icon, tooltip), then the quest checks for every other world object, whatever its cursor
-- icon says (a quest object often shows the plain interaction). The fallback is the last resort: a world
-- object the cursor icon of which names neither a quest nor a plain interaction. The settings are not
-- looked at here: the kind is known with a switch off, only the effect depends on it.
local function identify()
  local file, atlas, cursor = cursorName()
  local category, locked = Logic.Classify(file, atlas)
  if category then
    return category, locked, "cursor", cursor
  end
  local data = tooltipData()
  local lines = tooltipLines(data)
  category = Logic.ClassifyTooltip(lines)
  if category then
    return category, locked, "tooltip", cursor
  end
  if not isCreature() then
    local quest = questChecks(data, lines)
    local source = Logic.QuestSource(quest.related, quest.tooltipLine, quest.nameMatch)
    if source then
      return "quest", locked, "quest-" .. source, cursor
    end
  end
  local creatureType, known = unitCall("UnitCreatureType")
  if not known then
    creatureType = "?"
  end
  category = Logic.ClassifyObject(targetGuid(), unitCall("UnitIsPlayer"), creatureType, file, atlas)
  if category then
    return category, locked, "object", cursor
  end
  return nil, locked, nil, cursor
end

-- Effect ----------------------------------------------------------------------------------------------

local function plateOfUnit(unit)
  local api = global("C_NamePlate")
  if type(api) ~= "table" or type(api.GetNamePlateForUnit) ~= "function" then
    return nil
  end
  local ok, plate = pcall(api.GetNamePlateForUnit, unit)
  return ok and type(plate) == "table" and plate or nil
end

-- The plate of the soft target. When the direct way gives none and never did for a world object on this
-- client, the active plates are searched for the one of the target (or of a world object).
local function plateOfTarget()
  local plate = plateOfUnit(UNIT)
  if plate then
    if unitFlag("UnitIsGameObject") == true then
      directWorks = true
    end
    return plate
  end
  if directWorks then
    return nil
  end
  local object
  for unit in pairs(activeUnits) do
    if unitFlag("UnitIsUnit", unit, UNIT) == true then
      return plateOfUnit(unit)
    end
    if not object and unitFlag("UnitIsGameObject", unit) == true then
      object = unit
    end
  end
  return object and plateOfUnit(object) or nil
end

-- Lets go of the plate: hidden, no anchor, no parent.
local function release()
  retarget = false
  attached = nil
  if host then
    host:Hide()
    host:ClearAllPoints()
    pcall(host.SetParent, host, nil)
  end
end

-- Hangs the effect on the plate as its child: it takes the scale the client gives the plate with the
-- distance, so the gap below the plate center holds at every camera distance. The level is one under
-- the plate (its text stays readable), the plate itself is almost see-through for world objects, so
-- the effect ignores the alpha of its parent. false when the client refuses the anchor.
local function place(plate)
  if not pcall(host.SetParent, host, plate) then
    return false
  end
  local okLevel, level = pcall(plate.GetFrameLevel, plate)
  level = okLevel and Logic.HostLevel(readable(level)) or nil
  if level then
    host:SetFrameLevel(level)
  end
  host:ClearAllPoints()
  local c = config() or {}
  if not pcall(host.SetPoint, host, "CENTER", plate, "CENTER", 0, Logic.CleanOffset(c.offsetY)) then
    return false
  end
  host:SetIgnoreParentAlpha(true)
  return true
end

-- All sparks start anew at once.
local function restartDots()
  for _, d in ipairs(dots) do
    Logic.Respawn(d.p, math.random)
  end
  staticPlaced = false
end

-- Sets the wanted state from the range of the target (nil when it is gone).
local function poll()
  if not unitExists() then
    want = nil
    return
  end
  local inRange
  local f = global("UnitIsInInteractRange")
  if type(f) == "function" then
    local ok, result = pcall(f, UNIT)
    if ok then
      result = readable(result)
      if result == true or result == false then
        inRange = result
      end
    end
  end
  want = Logic.WantedState(inRange, target.locked)
end

local function paintModel(r, g, b, a)
  local m = host.model
  m:SetAlpha(a)
  if type(m.SetModelAlpha) == "function" then
    pcall(m.SetModelAlpha, m, a)
  end
  -- Tint through the light of the model where the client has it, only when the color moved.
  if type(m.SetLight) == "function" and (r ~= lastR or g ~= lastG or b ~= lastB) then
    lastR, lastG, lastB = r, g, b
    pcall(m.SetLight, m, true, false, 0, 0, -1, 1, r, g, b, 1, r, g, b)
  end
end

-- A texture size in pixels with the size setting applied (the host frame is never scaled).
local function scaled(base)
  local c = config()
  return Logic.ScaledSize(base, c and c.size)
end

-- The size setting changed: every texture of the effect takes the new size at once, no rebuild.
function G.Resize()
  if dark then
    dark:SetSize(scaled(Logic.DARK_SIZE), scaled(Logic.DARK_SIZE))
    glow:SetSize(scaled(Logic.GLOW_SIZE), scaled(Logic.GLOW_SIZE))
  end
  for _, d in ipairs(dots) do
    local size = scaled(staticPlaced and Logic.STAR_SIZE_MAX or d.p.size)
    d.tex:SetSize(size, size)
  end
end

local function paintDots(r, g, b, a, reduce)
  local t = not reduce and clock or nil
  local dr, dg, db = Logic.DarkLook(state)
  dark:SetVertexColor(dr, dg, db, Logic.DarkAlpha(a))
  glow:SetVertexColor(r, g, b, Logic.GlowAlpha(a, t))
  for i = 1, #dots do
    local d = dots[i]
    local envelope = 0.75
    if reduce then
      if not staticPlaced then
        local x, y = Logic.StaticSpot(i, #dots)
        d.tex:SetPoint("CENTER", host, "CENTER", x, y)
        local size = scaled(Logic.STAR_SIZE_MAX)
        d.tex:SetSize(size, size)
      end
    else
      if Logic.StepParticle(d.p, STEP, math.random) or staticPlaced then
        d.tex:SetPoint("CENTER", host, "CENTER", d.p.x, d.p.y)
        local size = scaled(d.p.size)
        d.tex:SetSize(size, size)
      end
      envelope = Logic.Envelope(d.p)
    end
    d.tex:SetVertexColor(r, g, b, envelope * a)
  end
  staticPlaced = reduce
end

local function step()
  local reduce = reduced()
  clock = clock + STEP
  Logic.Update(state, want, STEP, reduce)
  if state.burst then
    state.burst = false
    restartDots()
  end
  local r, g, b, a = Logic.Look(state)
  if style == "original" then
    if reduce ~= paused and type(host.model.SetPaused) == "function" then
      paused = reduce
      pcall(host.model.SetPaused, host.model, reduce)
    end
    paintModel(r, g, b, a)
  else
    paintDots(r, g, b, a, reduce)
  end
  if want == nil and state.alpha <= 0 then
    host:Hide()
  end
end

local function onUpdate(_, elapsed)
  pollAcc = pollAcc + elapsed
  if pollAcc >= Logic.POLL then
    pollAcc = 0
    poll()
  end
  acc = math.min(acc + elapsed, MAX_CATCH_UP)
  while acc >= STEP do
    acc = acc - STEP
    step()
  end
end

local function buildHost()
  if host then
    return
  end
  host = CreateFrame("Frame", nil, UIParent)
  host.fgId = "sparkles-host"
  host:SetSize(Logic.HOST_SIZE, Logic.HOST_SIZE)
  host:SetFrameStrata(Logic.HOST_STRATA)
  host:SetFrameLevel(Logic.HOST_LEVEL)
  host:EnableMouse(false)
  host:SetScript("OnUpdate", onUpdate)
  host:Hide()
end

-- True when the original model of the client loads: SetModel raises nothing and, where the client can
-- tell, names the file afterwards. Only the file data id works, a path is refused by the client.
local function loadModel()
  if modelLoaded ~= nil then
    return modelLoaded
  end
  local m = host.model
  if not m then
    m = CreateFrame("Model", nil, host)
    m:SetAllPoints(host)
    host.model = m
  end
  local hasGetter = type(m.GetModelFileID) == "function"
  local setOk = type(m.SetModel) == "function" and pcall(m.SetModel, m, Logic.MODEL_ID)
  local fileId
  if setOk and hasGetter then
    local okId, value = pcall(m.GetModelFileID, m)
    fileId = okId and readable(value) or nil
  end
  modelLoaded = Logic.ModelLoaded(setOk, hasGetter, fileId)
  if modelLoaded then
    local at = Logic.MODEL
    for method, args in pairs({
      SetModelScale = { at.scale },
      SetPosition = { at.x, at.y, at.z },
      SetFacing = { at.facing },
    }) do
      if type(m[method]) == "function" then
        pcall(m[method], m, unpack(args))
      end
    end
  end
  return modelLoaded
end

-- A texture of the effect: the id of the client, the fallback star when the client does not know it.
local function glowTexture(layer, sublevel, id, blend, size)
  local tex = host:CreateTexture(nil, layer, nil, sublevel)
  tex.fgLayer = true
  tex:SetBlendMode(blend)
  local ok, known = pcall(tex.SetTexture, tex, id)
  if not ok or known == false then
    tex:SetTexture(Logic.TEXTURE_FALLBACK)
  end
  tex:SetPoint("CENTER", host, "CENTER", 0, 0)
  size = scaled(size)
  tex:SetSize(size, size)
  return tex
end

-- From the back: a dark layer (blend, readable on bright ground), the soft glow (additive, pulses) and
-- the stars (additive, flash).
local function buildDots()
  if #dots > 0 then
    return
  end
  dark = glowTexture("BACKGROUND", 0, Logic.GLOW_TEXTURE, "BLEND", Logic.DARK_SIZE)
  glow = glowTexture("ARTWORK", 0, Logic.GLOW_TEXTURE, "ADD", Logic.GLOW_SIZE)
  for i = 1, Logic.PARTICLES do
    local tex = host:CreateTexture(nil, "OVERLAY")
    tex:SetBlendMode("ADD")
    local ok, known = pcall(tex.SetTexture, tex, Logic.STAR_TEXTURE)
    if not ok or known == false then
      tex:SetTexture(Logic.TEXTURE_FALLBACK)
    end
    local p = {}
    Logic.Respawn(p, math.random, 1)
    tex:SetPoint("CENTER", host, "CENTER", p.x, p.y)
    local size = scaled(p.size)
    tex:SetSize(size, size)
    dots[i] = { tex = tex, p = p }
  end
end

local function showDots(on)
  for i = 1, #dots do
    dots[i].tex:SetShown(on)
  end
  if dark then
    dark:SetShown(on)
    glow:SetShown(on)
  end
end

-- Chooses the style once per settings change and shows only its parts.
local function buildEffect()
  buildHost()
  local c = config()
  local choice = c and c.style
  local loaded
  if Logic.WantsModel(choice) then
    loaded = loadModel()
  end
  local resolved, warn = Logic.ResolveStyle(choice, loaded)
  if warn and not modelWarned then
    modelWarned = true
    ns.Notify.chat(ns.L["sparkles.noModel"])
  end
  style = resolved
  if resolved == "original" then
    showDots(false)
    host.model:Show()
  else
    buildDots()
    if host.model then
      host.model:Hide()
    end
    showDots(true)
    staticPlaced = false
  end
  built = true
end

local function stopEffect()
  if want == nil and not (host and host:IsShown()) then
    return
  end
  want = nil
  state = Logic.NewState()
  release()
end

-- Puts the effect on the name plate of the soft target, or hides it when there is none. The anchor is
-- the plate frame itself, its coordinates are never read (the client may hide them from addons), and
-- every call anchors anew, so a new soft target moves the effect along.
function G.Attach()
  if not (active() and target.cat) then
    stopEffect()
    return
  end
  if retarget then
    release()
  end
  local plate = plateOfTarget()
  if not plate then
    release()
    return
  end
  if not built then
    buildEffect()
  end
  local fresh = plate ~= attached
  if not place(plate) then
    release()
    return
  end
  if fresh then
    state = Logic.NewState()
    restartDots()
  end
  attached = plate
  poll()
  host:Show()
end

-- The gap setting changed: move the effect at once, no rebuild.
function G.Reposition()
  if host and attached then
    place(attached)
  end
end

-- Looks at the soft target again: its kind decides whether anything sparkles. Called when the target
-- changes and when the settings change; recheck is true for the later looks of the watcher.
local function refresh(recheck)
  local c = config()
  if not c then
    return
  end
  local exists = c.enabled == true and unitExists() and not isCreature()
  local unknown = c.enabled == true and targetUnknown()
  local category, locked
  if exists then
    -- The kind is found with every switch off; only the effect asks the settings.
    category, locked = identify()
    if category and not (Logic.CategoryOn(category, c) and Logic.ShowsTarget(locked, c.lockedNodes)) then
      category = nil
    end
  end
  target.checks = recheck and target.checks + 1 or 0
  local guid = category and targetGuid() or nil
  if guid ~= target.guid then
    state = Logic.NewState()
  end
  target.cat, target.locked, target.guid = category, locked == true, guid
  local now = category ~= nil
  if now ~= sparkling or unknown ~= unknownTarget then
    sparkling, unknownTarget = now, unknown
    G.Apply()
  end
  G.Attach()
  if c.enabled == true and not watcher then
    watcher = CreateFrame("Frame", nil, UIParent)
    watcher.fgId = "sparkles-watch"
    watcher:SetScript("OnUpdate", ns.Wrap("sparkles-watch", G.Watch))
  end
  if watcher then
    watcher:SetShown(c.enabled == true)
  end
end

function G.Refresh()
  refresh(false)
end

-- Distance to the soft target in yards (root of UnitDistanceSquared), nil where the client has no such
-- call, hides the answer or has no target.
local function softDistance()
  local f = global("UnitDistanceSquared")
  if type(f) ~= "function" then
    return nil
  end
  local ok, squared = pcall(f, UNIT)
  squared = ok and readable(squared) or nil
  if type(squared) ~= "number" or squared ~= squared or squared < 0 then
    return nil
  end
  return math.sqrt(squared)
end

-- The poller notes how far soft targets are: the largest plausible distance of the session.
local function sampleDistance()
  distTried = distTried + 1
  local d = softDistance()
  if d ~= nil and d > 0 and (distSeen == nil or d > distSeen) then
    distSeen = d
  end
end

-- Detection range measurement ---------------------------------------------------------------------------

local function inInstance()
  local f = global("IsInInstance")
  if type(f) ~= "function" then
    return false
  end
  local ok, inside = pcall(f)
  return ok and readable(inside) == true
end

-- UnitPosition answers y, x, z and the instance in yards where the client has it, nothing in some places.
local function unitPosition()
  local f = global("UnitPosition")
  if type(f) ~= "function" then
    return nil
  end
  local ok, y, x, z, map = pcall(f, "player")
  if not ok then
    return nil
  end
  y, x, z, map = readable(y), readable(x), readable(z), readable(map)
  if not (Logic.IsNumber(x) and Logic.IsNumber(y)) or (x == 0 and y == 0) then
    return nil
  end
  return { x = x, y = y, z = Logic.IsNumber(z) and z or nil, map = map, source = "UnitPosition" }
end

-- The position on the map in 0 to 1, scaled by the size of the map in yards.
local function mapPosition()
  local api = global("C_Map")
  if type(api) ~= "table" then
    return nil
  end
  if not (type(api.GetBestMapForUnit) == "function" and type(api.GetPlayerMapPosition) == "function") then
    return nil
  end
  if type(api.GetMapWorldSize) ~= "function" then
    return nil
  end
  local okMap, map = pcall(api.GetBestMapForUnit, "player")
  map = okMap and readable(map) or nil
  if not Logic.IsNumber(map) then
    return nil
  end
  local okPos, point = pcall(api.GetPlayerMapPosition, map, "player")
  if not okPos or type(point) ~= "table" or type(point.GetXY) ~= "function" then
    return nil
  end
  local okXY, x, y = pcall(point.GetXY, point)
  local okSize, width, height = pcall(api.GetMapWorldSize, map)
  x, y, width, height = readable(x), readable(y), readable(width), readable(height)
  if not (okXY and okSize and Logic.IsNumber(x) and Logic.IsNumber(y)) then
    return nil
  end
  if not (Logic.IsNumber(width) and Logic.IsNumber(height) and width > 0 and height > 0) then
    return nil
  end
  return { x = x * width, y = y * height, map = map, source = "MapPosition" }
end

-- The own position in yards: the first source that gives a usable value, nil in an instance or without
-- any. Remembers the source for the report (UnitPosition, MapPosition, none).
local function playerYards()
  local pos = nil
  if not inInstance() then
    pos = unitPosition() or mapPosition()
  end
  posSource = pos and pos.source or "none"
  return pos
end
G.PlayerYards = playerYards

-- The summary of the stored measurement, nil while there is none.
function G.Measured()
  local c = config()
  return Logic.MeasureSummary(c and c.measure)
end

function G.MeasureReset()
  local c = config()
  if c then
    c.measure = {}
  end
  ns.Emit("FG_SPARKLES_MEASURED")
end

-- Keeps one finished measurement: counters only, one chat line when the player asked for it.
local function recordSample(c, yards)
  if type(c.measure) ~= "table" then
    c.measure = {}
  end
  if not Logic.AddSample(c.measure, yards, ns.U.now()) then
    return
  end
  ns.Emit("FG_SPARKLES_MEASURED")
  local summary = G.Measured()
  if c.measureChat == true and summary then
    local key = summary.n == 1 and "sparkles.measure.chatOne" or "sparkles.measure.chat"
    ns.Notify.chat(
      string.format(ns.L[key], Logic.RoundYards(summary.last), Logic.RoundYards(summary.max), math.floor(summary.n))
    )
  end
end

-- One look of the poller at the measurement: only while an object of a recognized kind is the soft target.
local function sampleReach(c, object, guid)
  local inRange = nil
  if object then
    inRange = unitFlag("UnitIsInInteractRange")
  end
  local yards = Logic.SampleReady(measure, { object = object, guid = guid, inRange = inRange, read = playerYards })
  if yards then
    recordSample(c, yards)
  end
end

-- While a soft target exists: the plate may come after the event (or not at all for a moment) and the
-- cursor icon may follow a frame later, so look again a few times and anchor again when the plate moved.
function G.Watch(_, elapsed)
  watchAcc = watchAcc + (elapsed or 0)
  if watchAcc < Logic.WATCH then
    return
  end
  watchAcc = 0
  if not active() then
    return
  end
  -- The poller runs while the module is on: a target the events did not report is found here.
  local exists = unitExists()
  if exists then
    sampleDistance()
  end
  local guid = exists and targetGuid() or nil
  local changed = exists ~= seenExists or guid ~= seenGuid
  if changed then
    seenExists, seenGuid = exists, guid
    refresh(false)
  end
  sampleReach(config(), exists and target.cat ~= nil, guid)
  if changed or not exists then
    return
  end
  if target.cat == nil then
    if target.checks < Logic.RECHECKS then
      refresh(true)
    end
  elseif attached == nil or plateOfTarget() ~= attached then
    G.Attach()
  end
end

-- Support report -------------------------------------------------------------------------------------

local function frameValue(frame, method, ...)
  local f = frame and frame[method]
  if type(f) ~= "function" then
    return nil
  end
  local ok, value = pcall(f, frame, ...)
  if not ok then
    return nil
  end
  return readable(value)
end

-- What the support report prints about the module (see Logic.DiagLines). Reads the soft target anew, changes nothing.
function G.DiagInfo()
  local c = config() or {}
  local info = {
    enabled = c.enabled == true,
    ore = c.ore == true,
    herbs = c.herbs == true,
    quest = c.quest == true,
    lockedNodes = c.lockedNodes == true,
    styleSetting = c.style,
    styleActual = style,
    cursorApi = type(global("SetUnitCursorTexture")) == "function",
    soft = unitExists(),
    state = state.shown,
    kept = target.cat ~= nil,
    offsetY = c.offsetY,
    size = c.size,
    range = c.range,
    rangeNow = getCVar(Logic.RANGE_CVAR),
    effective = Logic.EffectiveRange(c.range),
    distSeen = distSeen,
    distTried = distTried > 0,
    measure = G.Measured(),
    measureState = measure.phase,
    measureStart = measure.start ~= nil,
    measureNote = measure.note,
    measureChat = c.measureChat,
    distance = unitExists() and softDistance() or nil,
    directWorks = directWorks,
    unitExists = unitFlag("UnitExists"),
    unitIsGameObject = unitFlag("UnitIsGameObject"),
    cvars = {},
  }
  -- Where a position comes from right now (no coordinates leave this function).
  playerYards()
  info.posSource = posSource
  local units = 0
  for _ in pairs(activeUnits) do
    units = units + 1
  end
  info.activeUnits = units
  if info.soft then
    info.name = unitCall("UnitName")
    info.category, info.locked, info.source, info.cursor = identify()
    local data = tooltipData()
    info.questCheck = questChecks(data, tooltipLines(data))
    local inRange = unitCall("UnitIsInInteractRange")
    if inRange == true or inRange == false then
      info.inRange = inRange
    end
  end
  local plate = plateOfTarget()
  info.plate = plate ~= nil
  if plate then
    info.plateSecret = frameValue(plate, "IsAnchoringSecret")
  end
  if host then
    local lit = 0
    if style == "particles" and state.alpha > 0 then
      for _, d in ipairs(dots) do
        if Logic.Envelope(d.p) > 0 then
          lit = lit + 1
        end
      end
    end
    local okPoint, point, relative = pcall(host.GetPoint, host, 1)
    info.host = {
      shown = host:IsShown(),
      visible = host:IsVisible(),
      width = frameValue(host, "GetWidth"),
      height = frameValue(host, "GetHeight"),
      alpha = frameValue(host, "GetAlpha"),
      strata = frameValue(host, "GetFrameStrata"),
      level = frameValue(host, "GetFrameLevel"),
      point = okPoint and readable(point) or nil,
      onPlate = okPoint and plate ~= nil and relative == plate,
      parentIsPlate = plate ~= nil and host:GetParent() == plate,
      plateLevel = plate and frameValue(plate, "GetFrameLevel") or nil,
      ignoreAlpha = frameValue(host, "IsIgnoringParentAlpha"),
      secret = frameValue(host, "IsAnchoringSecret"),
      active = lit,
      stars = #dots,
    }
  end
  for _, name in ipairs(Logic.ManagedNames()) do
    info.cvars[#info.cvars + 1] = { name = name, now = getCVar(name), saved = c.saved and c.saved[name] }
  end
  return info
end

function G.DiagLines()
  local words = {
    yes = ns.L["sparkles.diag.yes"],
    no = ns.L["sparkles.diag.no"],
    noDistance = ns.L["sparkles.diag.noDistance"],
  }
  local lines = Logic.DiagLines(G.DiagInfo(), words)
  table.insert(lines, 1, ns.L["sparkles.diag.heading"])
  return lines
end

-- Settings changed: other style, other categories, switch on or off.
local function onSettings()
  built = false
  refresh(false)
  G.Apply()
end

local function start()
  local c = config()
  if not c then
    return
  end
  -- The notice only where the client has the soft target variables, the effect has no use without.
  if c.enabled == true and c.noticed ~= true and getCVar("SoftTargetInteract") ~= nil then
    c.noticed = true
    ns.Notify.chat(ns.L["sparkles.notice"])
  end
  G.Apply()
  refresh(false)
end

ns.On("PLAYER_LOGIN", function()
  local timer = global("C_Timer")
  if type(timer) == "table" and type(timer.After) == "function" then
    timer.After(LOGIN_DELAY, ns.Wrap("sparkles-start", start))
  else
    start()
  end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if pendingApply then
    G.Apply()
  end
  G.Refresh()
end)
-- The name plate gate cannot change in combat: open it before the fight where the lock is not on yet,
-- so objects still sparkle during it (the rest waits for the end of the fight).
ns.On("PLAYER_REGEN_DISABLED", function()
  local c = config()
  if not (c and c.enabled == true and (c.ore or c.herbs or c.quest)) then
    return
  end
  if not inCombat() and getCVar(Logic.NAMEPLATE_CVAR) ~= "1" then
    setCVar(Logic.NAMEPLATE_CVAR, "1")
  end
  pendingApply = true
end)
-- The client hands a plate on from one target to the next without a trace on the frame: a change
-- between two readable targets while the effect hangs lets it go and hang anew.
ns.On("PLAYER_SOFT_INTERACT_CHANGED", function(_, old, new)
  local before, after = readable(old), readable(new)
  if attached and before ~= nil and after ~= nil and before ~= after then
    retarget = true
  end
  G.Refresh()
end)
-- The objective texts are built again at their next use.
ns.On("QUEST_LOG_UPDATE", function()
  questStale = true
end)
ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
  if type(unit) == "string" then
    activeUnits[unit] = true
  end
  G.Refresh()
end)
-- The plate the effect hangs on went away: hide at once and show again only on the next plate of the
-- soft target. Other plates leaving do not matter (the client may no longer know the removed unit,
-- then the effect looks for its plate anew).
ns.On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
  if type(unit) == "string" then
    activeUnits[unit] = nil
  end
  local removed = plateOfUnit(unit)
  if removed ~= nil and removed ~= attached then
    return
  end
  release()
  if removed == nil then
    G.Attach()
  end
end)
-- A graphics preset writes its own values: apply ours again a moment later.
ns.On("CVAR_UPDATE", function(_, name)
  if active() and Logic.IsWatched(readable(name)) then
    ns.Debounce("sparkles-cvars", 0.3, G.Apply)
  end
end)
ns.On("FG_SETTING_CHANGED", function(_, path)
  if type(path) ~= "string" then
    return
  end
  -- The gap, size and range sliders change the effect only (no rebuild), so they may run live while the thumb is dragged.
  if path == "settings.sparkles.offsetY" then
    G.Reposition()
  elseif path == "settings.sparkles.size" then
    G.Resize()
  elseif path == "settings.sparkles.range" then
    G.Apply()
  elseif path == "settings.sparkles.measureChat" or path == "settings.sparkles.measure" then
    return
  elseif path:find("^settings%.sparkles") then
    onSettings()
  end
end)
