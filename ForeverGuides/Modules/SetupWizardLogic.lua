-- Setup wizard logic (no UI): step registry, persisted state, first-run decisions, session
-- navigation and the reset to defaults. State lives in ForeverGuidesDB.setup:
-- { fresh, done, skipped, version, seenSteps = { [stepId] = true }, baselined, noticeVersion }.
--
--   SW.RegisterStep({ id, order, titleKey, textKey, since = "0.1.0", when = function() end,
--     closing = true (summary step: shown again whenever another step is new),
--     layout = { "title", "text", "controls", ... }, blocks = { name = ... },
--     controls = { { type = "toggle" | "dropdown" | "slider" | "custom" | "consent", key = "settings.x",
--     labelKey, hintKey, options = { { value, key|text } }, min, max, step, format(v), invert,
--     build(view) (custom: adds its own widgets), when(), apply(value),
--     action = true (custom: a button, not a setting: no change entry, no reset),
--     tab = "automation" (Settings tab that holds it, named in the summary) } } })
--
-- A control exists only while its key has a default in Store.defaults, so a step can be
-- registered before the module that owns the key. A step without controls is an info step.
-- A consent control (fn, aud) is no Store key: it reads and writes the send and receive flag of one
-- sharing function through ns.Consent (account scope, by "wizard"), off by default, and exists only
-- while the function is available.
local _, ns = ...
local U, Store = ns.U, ns.Store

local SW = { steps = {}, VERSION = 1 }
ns.SetupWizard = SW

local seq = 0
local TYPES = { toggle = true, dropdown = true, slider = true, custom = true, consent = true }
local DIRECTIONS = { send = true, receive = true }

local function validControl(c)
  if type(c) ~= "table" or not TYPES[c.type] or type(c.key) ~= "string" or c.key == "" then
    return false
  end
  if c.type == "slider" then
    return type(c.min) == "number" and type(c.max) == "number" and type(c.step) == "number" and c.step > 0
  elseif c.type == "dropdown" then
    return type(c.options) == "table" and #c.options > 0
  elseif c.type == "custom" then
    return type(c.build) == "function"
  elseif c.type == "consent" then
    return type(c.fn) == "string" and c.fn ~= "" and type(c.aud) == "string" and c.aud ~= ""
  end
  return true
end

function SW.RegisterStep(step)
  if type(step) ~= "table" or type(step.id) ~= "string" or step.id == "" then
    return false
  end
  local controls = {}
  for _, c in ipairs(step.controls or {}) do
    if validControl(c) then
      controls[#controls + 1] = c
    end
  end
  step.controls = controls
  step.order = tonumber(step.order) or 100
  step.since = step.since or "0.0.0"
  local old = SW.steps[step.id]
  seq = seq + 1
  step.seq = old and old.seq or seq
  SW.steps[step.id] = step
  return true
end

-- Registered steps by order, then by registration.
function SW.Steps()
  local list = {}
  for _, step in pairs(SW.steps) do
    list[#list + 1] = step
  end
  table.sort(list, function(a, b)
    if a.order ~= b.order then
      return a.order < b.order
    end
    return a.seq < b.seq
  end)
  return list
end

local function check(fn)
  if type(fn) ~= "function" then
    return true
  end
  local ok, result = pcall(fn)
  return ok and result and true or false
end

function SW.DefaultOf(path)
  local node = Store.defaults
  for part in tostring(path):gmatch("[^.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = node[part]
  end
  return node
end

function SW.ControlActive(c)
  if c.type == "consent" then
    return ns.Consent ~= nil and ns.Consent.IsAvailable(c.fn) and check(c.when)
  end
  return SW.DefaultOf(c.key) ~= nil and check(c.when)
end

function SW.ActiveControls(step)
  local list = {}
  for _, c in ipairs(step.controls) do
    if SW.ControlActive(c) then
      list[#list + 1] = c
    end
  end
  return list
end

function SW.StepActive(step)
  if not check(step.when) then
    return false
  end
  return #step.controls == 0 or #SW.ActiveControls(step) > 0
end

-- State ----------------------------------------------------------------------------------------

function SW.State()
  local db = ns.db
  local defaults = Store.defaults.setup
  if type(db.setup) ~= "table" then
    db.setup = U.copy(defaults)
  end
  U.applyDefaults(db.setup, defaults)
  if type(db.setup.seenSteps) ~= "table" then
    db.setup.seenSteps = {}
  end
  return db.setup
end

local function parseVersion(v)
  local a, b, c = tostring(v or ""):match("^(%d+)%.?(%d*)%.?(%d*)")
  return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 }
end

-- -1, 0 or 1 for "0.1.0" style versions; anything unreadable counts as 0.0.0.
function SW.CompareVersions(a, b)
  local x, y = parseVersion(a), parseVersion(b)
  for i = 1, 3 do
    if x[i] ~= y[i] then
      return x[i] < y[i] and -1 or 1
    end
  end
  return 0
end

-- onlyNew keeps the steps this user has not been shown yet. A closing step (the summary) is shown
-- again whenever any other step is new, so every run ends with it.
function SW.ActiveSteps(onlyNew)
  local seen = onlyNew and SW.State().seenSteps or {}
  local active, anyNew = {}, false
  for _, step in ipairs(SW.Steps()) do
    if SW.StepActive(step) then
      active[#active + 1] = step
      anyNew = anyNew or (not seen[step.id] and not step.closing)
    end
  end
  local list = {}
  for _, step in ipairs(active) do
    if not seen[step.id] or (step.closing and anyNew) then
      list[#list + 1] = step
    end
  end
  return list
end

function SW.Pending()
  return SW.ActiveSteps(true)
end

-- Existing users already know every step that shipped up to their last version.
function SW.Baseline()
  local state = SW.State()
  if state.baselined == true then
    return
  end
  state.baselined = true
  if state.fresh == true then
    return
  end
  for _, step in ipairs(SW.Steps()) do
    if SW.CompareVersions(step.since, Store.previousVersion) <= 0 then
      state.seenSteps[step.id] = true
    end
  end
end

-- Only a first install opens the wizard by itself.
function SW.ShouldAutoOpen()
  if not ns.db then
    return false
  end
  local state = SW.State()
  return state.fresh == true and state.done ~= true and #SW.ActiveSteps() > 0
end

-- Existing users get one hint: the first time, then once per version that adds steps.
function SW.NoticeDue()
  if not ns.db or SW.ShouldAutoOpen() then
    return false
  end
  local state = SW.State()
  if state.noticeVersion == ns.version then
    return false
  end
  -- A fresh install was offered the wizard itself, so it only hears about later steps.
  if state.noticeVersion == "" and state.fresh ~= true then
    return true
  end
  return #SW.Pending() > 0
end

function SW.MarkNotified()
  SW.State().noticeVersion = ns.version
end

-- Values --------------------------------------------------------------------------------------

-- The value a session compares: the stored value, for a consent control the letters of the flags that
-- are on ("", "S", "R" or "SR").
function SW.Raw(c)
  if c.type == "consent" then
    local Consent = ns.Consent
    return (Consent.Allows(c.fn, "send", c.aud) and "S" or "") .. (Consent.Allows(c.fn, "receive", c.aud) and "R" or "")
  end
  return Store.get(c.key)
end

-- Shown value of a control: its stored value, else the default; toggles can be inverted. A consent
-- control answers for one direction ("send" or "receive"), off when unknown.
function SW.Get(c, dir)
  if c.type == "consent" then
    return DIRECTIONS[dir] == true and ns.Consent.Allows(c.fn, dir, c.aud) or false
  end
  local v = Store.get(c.key)
  if v == nil then
    v = SW.DefaultOf(c.key)
  end
  if c.type == "toggle" then
    v = v and true or false
    if c.invert then
      v = not v
    end
  end
  return v
end

local function runApply(c, value)
  if c.apply then
    ns.Safe("setup-apply", c.apply, value)
  end
end

-- Stores a shown value (the wizard is the trust boundary: unknown options and non-numbers
-- are refused) and returns whether it was accepted. A consent control also needs the direction.
function SW.Put(c, value, dir)
  if c.type == "consent" then
    local Consent = ns.Consent
    if type(value) ~= "boolean" or not DIRECTIONS[dir] or not Consent then
      return false
    end
    if not Consent.Set(c.fn, dir, c.aud, value, "wizard", "account") then
      return false
    end
    -- The window shows the effective value: an own setting of this character would hide the choice.
    if Consent.Allows(c.fn, dir, c.aud) ~= value then
      Consent.Reset(c.fn, dir, c.aud, "wizard")
    end
    return true
  end
  if c.type == "toggle" then
    value = value and true or false
    if c.invert then
      value = not value
    end
  elseif c.type == "slider" then
    local n = tonumber(value)
    if not n or n ~= n then
      return false
    end
    value = U.round(U.clamp(n, c.min, c.max), c.step)
  elseif c.type == "dropdown" then
    local known = false
    for _, o in ipairs(c.options) do
      known = known or o.value == value
    end
    if not known then
      return false
    end
  elseif type(value) ~= type(SW.DefaultOf(c.key)) then
    return false
  end
  Store.set(c.key, value)
  runApply(c, value)
  return true
end

-- Every key any step touches goes back to its Store default, the other settings stay. Sharing goes
-- fully off: every function is withdrawn (by "wizard", written to the consent log).
function SW.ResetToDefaults()
  local count, consent = 0, false
  for _, step in ipairs(SW.Steps()) do
    for _, c in ipairs(step.controls) do
      local default = SW.DefaultOf(c.key)
      if c.type == "consent" then
        consent = true
        count = count + 1
      elseif default ~= nil and not c.action then
        default = U.copy(default)
        Store.set(c.key, default)
        runApply(c, default)
        count = count + 1
      end
    end
  end
  if consent and ns.Consent then
    ns.Consent.WithdrawAll("wizard")
  end
  return count
end

-- Top guard ------------------------------------------------------------------------------------
-- The window must be clickable at any time: it sits in the highest strata at a high level, and
-- a guard puts back what the game or another add-on changed. Pure decisions, the UI applies them.

SW.GUARD = { strata = "TOOLTIP", level = 9000, interval = 1, hintSeconds = 20 }

-- The window background is an exact preview of the window opacity of the Settings (percent, 0 = invisible).
-- Text, buttons, sliders and the title strip are no background and stay fully visible.
function SW.BackgroundAlpha(percent)
  local v = tonumber(percent)
  if not v or v ~= v then
    return 1
  end
  return math.max(0, math.min(1, v / 100))
end

-- Below this opacity (percent) the look step warns that text can be hard to read.
SW.LOW_ALPHA = 20

function SW.IsVeryTransparent(percent)
  local v = tonumber(percent)
  return v ~= nil and v == v and v < SW.LOW_ALPHA
end

-- Events that bring the window to the front again while it is open. Names the client does not
-- know are skipped by the registration.
SW.GUARD_EVENTS = {
  "CINEMATIC_START",
  "CINEMATIC_STOP",
  "PLAY_MOVIE",
  "STOP_MOVIE",
  "LOADING_SCREEN_DISABLED",
  "PLAYER_ENTERING_WORLD",
  "UI_SCALE_CHANGED",
  "DISPLAY_SIZE_CHANGED",
  "PLAYER_REGEN_ENABLED",
  "TUTORIAL_TRIGGER",
  "SHOW_TUTORIAL",
  "NPE_TUTORIAL_UPDATE",
}

local STRATA_RANK = {
  BACKGROUND = 1,
  LOW = 2,
  MEDIUM = 3,
  HIGH = 4,
  DIALOG = 5,
  FULLSCREEN = 6,
  FULLSCREEN_DIALOG = 7,
  TOOLTIP = 8,
}

-- What differs from the wanted state, in a fixed order. state: { strata, level (own baseline
-- or minimum), wantLevel, mouse, alpha (of the whole frame, always full), uiShown }; a missing value is not
-- judged. The background fill is no part of it: its opacity is the player's choice.
-- Returns the list of fixes ("strata", "level", "mouse", "alpha") and whether UIParent is hidden
-- (nothing the window can fix).
function SW.GuardCheck(state)
  local fixes = {}
  if type(state.strata) == "string" and state.strata ~= SW.GUARD.strata then
    fixes[#fixes + 1] = "strata"
  end
  if type(state.level) == "number" and state.level < (state.wantLevel or SW.GUARD.level) then
    fixes[#fixes + 1] = "level"
  end
  if state.mouse == false then
    fixes[#fixes + 1] = "mouse"
  end
  if type(state.alpha) == "number" and state.alpha < 1 then
    fixes[#fixes + 1] = "alpha"
  end
  return fixes, state.uiShown == false
end

-- counts: { total = n, kinds = { [fix] = n } }; adds the fixes of one check.
function SW.GuardRecord(counts, fixes)
  counts.kinds = counts.kinds or {}
  for _, fix in ipairs(fixes) do
    counts.total = (counts.total or 0) + 1
    counts.kinds[fix] = (counts.kinds[fix] or 0) + 1
  end
  return counts
end

function SW.GuardSummary(counts)
  if not counts or (counts.total or 0) == 0 then
    return "guard: no correction needed"
  end
  local names = {}
  for _, fix in ipairs({ "strata", "level", "mouse", "alpha" }) do
    if counts.kinds and counts.kinds[fix] then
      names[#names + 1] = fix
    end
  end
  return string.format("guard: corrected %d times: %s", counts.total, table.concat(names, ", "))
end

-- True when a frame at (strata, level) is drawn over the window at (wStrata, wLevel).
function SW.IsAbove(strata, level, wStrata, wLevel)
  local a, b = STRATA_RANK[strata], STRATA_RANK[wStrata]
  if not (a and b and type(level) == "number" and type(wLevel) == "number") then
    return false
  end
  return a > b or (a == b and level > wLevel)
end

-- True when a frame of w x h covers more than `share` of a screen of sw x sh.
function SW.CoversScreen(w, h, sw, sh, share)
  if not (type(w) == "number" and type(h) == "number" and type(sw) == "number" and type(sh) == "number") then
    return false
  end
  if sw <= 0 or sh <= 0 then
    return false
  end
  return (w * h) / (sw * sh) > (share or 0.8)
end

-- Session ----------------------------------------------------------------------------------------

local Session = {}
Session.__index = Session

-- opts.onlyNew: only the steps not shown yet. Returns nil when no step is active.
function SW.Begin(opts)
  local steps = SW.ActiveSteps(opts and opts.onlyNew)
  if #steps == 0 then
    return nil
  end
  local state = SW.State()
  local session = setmetatable({
    steps = steps,
    index = 1,
    firstRun = state.fresh == true and state.done ~= true,
    snapshot = {},
    visited = { [steps[1].id] = true },
  }, Session)
  for _, step in ipairs(steps) do
    for _, c in ipairs(SW.ActiveControls(step)) do
      session.snapshot[c.key] = SW.Raw(c)
    end
  end
  return session
end

function Session:Current()
  return self.steps[self.index]
end

function Session:Progress()
  return self.index, #self.steps
end

function Session:IsFirst()
  return self.index == 1
end

function Session:IsLast()
  return self.index == #self.steps
end

function Session:Go(index)
  if self.closed or type(index) ~= "number" or index < 1 or index > #self.steps then
    return false
  end
  self.index = math.floor(index)
  self.visited[self.steps[self.index].id] = true
  return true
end

function Session:Next()
  return self:Go(self.index + 1)
end

function Session:Back()
  return self:Go(self.index - 1)
end

-- What differs from the values at the start: { { control, old, new } }.
function Session:Changes()
  local list = {}
  for _, step in ipairs(self.steps) do
    for _, c in ipairs(SW.ActiveControls(step)) do
      local old, new = self.snapshot[c.key], SW.Raw(c)
      if old ~= new and not c.action then
        list[#list + 1] = { control = c, old = old, new = new }
      end
    end
  end
  return list
end

local function conclude(self, how)
  if self.closed then
    return false
  end
  local state = SW.State()
  for id in pairs(self.visited) do
    state.seenSteps[id] = true
  end
  state.done = true
  state.version = SW.VERSION
  state.noticeVersion = ns.version
  if how == "finish" then
    state.skipped = false
  elseif how == "skip" then
    state.skipped = true
  end
  self.closed = how
  ns.Emit("FG_SETUP_CHANGED", how)
  return true
end

function Session:Finish()
  return conclude(self, "finish")
end

-- Skipping on a first run loads the defaults for every step key.
function Session:Skip()
  if self.closed then
    return false
  end
  for _, step in ipairs(self.steps) do
    self.visited[step.id] = true
  end
  SW.ResetToDefaults()
  return conclude(self, "skip")
end

-- Closing early keeps what was changed so far and does not come back by itself.
function Session:Cancel()
  return conclude(self, "cancel")
end
