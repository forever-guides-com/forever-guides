-- The run of a plan in steps, no game calls: a state machine that executes ready entries one by one,
-- looks at fresh data before each step, keeps the pauses, stops on any doubt and writes one protocol
-- entry per step. Also the central rank base conversion and the undo of a rank change.
--
-- States: ready -> confirmed -> running <-> paused -> done | aborted. Nothing runs before Confirm, a
-- removal needs the typed name of its member (and the typed count from SettingsLogic.CONFIRM_COUNT on),
-- and a series (many steps after one trigger) needs the setting runMode = "series" AND the direct way.
--
-- Everything the game decides comes in through `env` (all optional except exec):
--   now()               clock in seconds (GetTime), time() epoch seconds for the protocol, rand() in [0, 1)
--   snapshot()          { members = { [key] = row }, me = row, rights, lowest, takenAt, combat } or nil
--   request()           asks the game for a fresh roster
--   rule(step, snap)    true, or false and a reason: does the rule still apply to fresh data
--   exec(step)          the action through the backend: "sent", "dry", "copy", "armed" or false and a reason
--   values(step)        old and new text of the step for the protocol
--   log(entry, event)   called with "new" and "update"; finish(summary, run) once at the end
-- A row is { key, name, rank, note, officerNote }, rank indexes count from 0 (guild master).
local _, gm = ...
if not gm.ext then
  return
end
local AL = gm.ActionsLogic

local RL = {}
gm.RunLogic = RL

RL.STATES = { "ready", "confirmed", "running", "paused", "done", "aborted" }
-- Seconds a roster may be old before a step, how long a stale roster or a missing confirmation is waited
-- for before the run stops, and after how many steps the long pause comes.
RL.MAX_AGE = 60
RL.WAIT_LIMIT = 15
RL.LONG_EVERY = 5
-- Share of the pause that is added at random so the steps do not fall into a fixed rhythm.
RL.JITTER = 0.2
local MAX_RANK = 9
-- Actions on a rank: the guild master is never their target.
local RANKED = { promote = true, demote = true, setRank = true, remove = true }

-- Rank base ------------------------------------------------------------------------------------------

-- The roster counts ranks from 0 (guild master), SetGuildRankOrder from 1. The one place that converts.
function RL.RankOrderOf(index)
  if type(index) == "number" and index % 1 == 0 and index >= 0 and index <= MAX_RANK then
    return index + 1
  end
end

function RL.IndexOfOrder(order)
  if type(order) == "number" and order % 1 == 0 and order >= 1 and order <= MAX_RANK + 1 then
    return order - 1
  end
end

-- Steps ----------------------------------------------------------------------------------------------

local function rank(v)
  return type(v) == "number" and v % 1 == 0 and v >= 0 and v <= MAX_RANK and v or nil
end

-- Plan entry (PlanLogic) or step -> step { action, key, name, guid, index, fromRank, toRank, value, rule }
-- with the action named like the backend does; nil for an entry this run cannot execute.
function RL.Step(entry)
  if type(entry) ~= "table" or type(entry.key) ~= "string" or entry.key == "" then
    return nil
  end
  local kind = type(entry.action) == "table" and entry.action.kind or entry.action
  local from, to = rank(entry.fromRank), rank(entry.toRank)
  local action
  if kind == "promote" or kind == "demote" then
    action = kind
  elseif kind == "setRank" and from and to and from ~= to then
    action = math.abs(from - to) == 1 and (to < from and "promote" or "demote") or "setRank"
  elseif kind == "remove" then
    action = "remove"
  elseif kind == "setNote" or kind == "editNote" or kind == "editOfficerNote" then
    local public = type(entry.action) == "table" and entry.action.public ~= false
    action = kind == "setNote" and (public and "editNote" or "editOfficerNote") or kind
  end
  if not action then
    return nil
  end
  if action == "promote" and from and not to then
    to = from - 1
  elseif action == "demote" and from and not to then
    to = from + 1
  end
  local value = entry.value
  if value == nil and type(entry.action) == "table" then
    value = entry.action.note
  end
  return {
    action = action,
    key = entry.key,
    name = entry.name,
    guid = entry.guid,
    index = entry.index,
    fromRank = from,
    toRank = to,
    value = type(value) == "string" and value or nil,
    rule = entry.ruleName or entry.rule,
    undoOf = entry.undoOf,
  }
end

-- True when the member row shows the result of the step. A rank change needs the new rank, a removal
-- the member gone, a note the new text.
function RL.Landed(step, member)
  if step.action == "remove" then
    return member == nil
  elseif type(member) ~= "table" then
    return false
  elseif step.action == "editNote" then
    return member.note == step.value
  elseif step.action == "editOfficerNote" then
    return member.officerNote == step.value
  end
  return step.toRank ~= nil and member.rank == step.toRank
end

local INVERSE = { promote = "demote", demote = "promote", setRank = "setRank" }

-- The step that takes a logged rank change back. e: log entry { t, action, from, to, result, undone },
-- member: the row the member has now (nil when gone), now: epoch seconds, days: the undo window.
-- Answers the step, or nil and a reason code (the member must still be in the rank the change set).
function RL.Undo(e, member, now, days)
  if type(e) ~= "table" or not INVERSE[e.action] then
    return nil, "unknownAction"
  end
  if e.undone == true then
    return nil, "alreadyDone"
  end
  if e.result == "dry" or e.result == "copy" or e.result == "failed" or e.result == "mismatch" then
    return nil, "unchanged"
  end
  local from, to = rank(e.from), rank(e.to)
  if not (from and to) then
    return nil, "unknownRank"
  end
  if type(now) ~= "number" or type(e.t) ~= "number" or type(days) ~= "number" or now - e.t > days * 86400 then
    return nil, "expired"
  end
  if type(member) ~= "table" then
    return nil, "gone"
  end
  if member.rank ~= to then
    return nil, "rankChanged"
  end
  return RL.Step({
    action = "setRank",
    key = member.key,
    name = member.name,
    guid = member.guid,
    index = member.index,
    fromRank = to,
    toRank = from,
    ruleName = "undo",
    undoOf = e,
  })
end

-- The rule check of a run: build() answers the plan (PlanLogic.Build result) on fresh data. A step passes when
-- the member is still a ready entry with the same action; otherwise the reason of the entry (a code of
-- PlanLogic.REASONS) or "ruleChanged".
function RL.RuleCheck(build)
  return function(step)
    local ok, plan = pcall(build)
    for _, e in ipairs(ok and type(plan) == "table" and plan.entries or {}) do
      if e.key == step.key then
        local fresh = e.maturity == "ready" and RL.Step(e)
        if fresh and fresh.action == step.action then
          return true
        end
        return false, e.maturity ~= "ready" and e.reason or "ruleChanged"
      end
    end
    return false, "ruleChanged"
  end
end

-- Settings ---------------------------------------------------------------------------------------------

-- The values of the options the run reads; get(id) is SettingsLogic.Get on the settings of the guild.
function RL.Settings(get)
  return {
    series = get("runMode") == "series",
    pause = get("pauseSec"),
    longPause = get("longPauseSec"),
    maxTotal = get("maxTotal"),
    undoDays = get("undoDays"),
    notify = get("notifyDone") == true,
  }
end

-- Run ----------------------------------------------------------------------------------------------------

local Run = {}
Run.__index = Run

local function zero()
  return 0
end

-- entries: plan entries (PlanLogic) or steps; only "ready" ones run, the guild master never, one step
-- per member. opts: { settings = RL.Settings(..), backend = "direct" | "macro" | "copy", env }.
function RL.New(entries, opts)
  opts = type(opts) == "table" and opts or {}
  local env = type(opts.env) == "table" and opts.env or {}
  local s = type(opts.settings) == "table" and opts.settings or {}
  local run = setmetatable({
    state = "ready",
    env = env,
    pause = type(s.pause) == "number" and s.pause or 3,
    longPause = type(s.longPause) == "number" and s.longPause or 10,
    notify = s.notify == true,
    -- A series needs the setting and the direct way: macro and copy take one click per member.
    series = s.series == true and opts.backend == "direct",
    steps = {},
    skipped = {},
    log = {},
    counts = { sent = 0, dry = 0, copy = 0, skipped = 0, failed = 0, verified = 0, unverified = 0 },
    i = 1,
    executed = 0,
  }, Run)
  env.now, env.time, env.rand = env.now or zero, env.time or zero, env.rand or zero
  env.exec = env.exec or function()
    return false, "noApi"
  end
  local limit = type(s.maxTotal) == "number" and s.maxTotal or 10
  local seen = {}
  for _, entry in ipairs(type(entries) == "table" and entries or {}) do
    local ready = type(entry) == "table" and (entry.maturity == nil or entry.maturity == "ready")
    local step = ready and RL.Step(entry)
    if step and not seen[step.key] and #run.steps < limit then
      if step.fromRank == 0 or step.toRank == 0 then
        run.skipped[#run.skipped + 1] = { key = step.key, reason = "leader" }
      else
        seen[step.key] = true
        run.steps[#run.steps + 1] = step
      end
    end
  end
  return run
end

local function entryOf(self, step, result, reason)
  local env = self.env
  local old, new = "", ""
  if env.values then
    old, new = env.values(step)
  end
  local e = {
    t = env.time(),
    action = step.action,
    key = step.key,
    name = step.name,
    old = old,
    new = new,
    rule = step.rule,
    result = result,
    reason = reason,
    from = step.fromRank,
    to = step.toRank,
    undoOf = step.undoOf,
  }
  self.log[#self.log + 1] = e
  if env.log then
    env.log(e, "new")
  end
  return e
end

local function setResult(self, e, result)
  e.result = result
  if self.env.log then
    self.env.log(e, "update")
  end
end

local function finish(self, state, reason)
  if self.state == "done" or self.state == "aborted" then
    return
  end
  self.state, self.reason = state, reason
  if self.pendingButton and self.env.disarm then
    self.env.disarm(self.pendingButton)
  end
  self.pendingButton = nil
  if self.env.finish and self.notify then
    self.env.finish(self:Summary(), self)
  end
end

-- Stops the run at any time, also twice. Nothing runs afterwards.
function Run:Abort(reason)
  finish(self, "aborted", reason or "stopped")
end

function Run:Summary()
  local c = self.counts
  return {
    state = self.state,
    reason = self.reason,
    total = #self.steps,
    sent = c.sent,
    dry = c.dry,
    copy = c.copy,
    skipped = c.skipped,
    failed = c.failed,
    verified = c.verified,
    unverified = c.unverified,
  }
end

-- Confirmation. token = { names = { [key] = typed name }, count = typed number }: every removal needs
-- the typed name of its member, from CONFIRM_COUNT removals on the typed number of them as well.
-- True, or false and a reason code; the state stays "ready" on a refusal.
function Run:Confirm(token)
  if self.state ~= "ready" then
    return false, "state"
  end
  token = type(token) == "table" and token or {}
  local names = type(token.names) == "table" and token.names or {}
  local removals = 0
  for _, step in ipairs(self.steps) do
    if step.action == "remove" then
      removals = removals + 1
      if not AL.NameConfirmed(names[step.key], step.name) then
        return false, "nameMismatch"
      end
    end
  end
  local from = gm.SettingsLogic and gm.SettingsLogic.CONFIRM_COUNT or 3
  if removals >= from and tonumber(token.count) ~= removals then
    return false, "needCount"
  end
  for _, step in ipairs(self.steps) do
    step.confirmed = step.action == "remove" or nil
  end
  self.state = "confirmed"
  return true
end

local function wait(self, why, seconds)
  self.state, self.why, self.nextAt = "paused", why, seconds and self.env.now() + seconds or self.nextAt
end

-- Seconds until the next step after one that ran: the pause, plus the long one after each fifth step.
local function gap(self)
  local seconds = self.pause + self.pause * RL.JITTER * self.env.rand()
  if self.longPause > 0 and self.executed % RL.LONG_EVERY == 0 then
    seconds = seconds + self.longPause
  end
  return seconds
end

-- The answer of the game after a step that went out: did the roster change as the step says.
local function settle(self, snap, now)
  local p = self.pending
  if not p then
    return nil
  end
  if snap and not snap.combat and type(snap.takenAt) == "number" and snap.takenAt > p.sentAt then
    local landed = RL.Landed(p.step, snap.members and snap.members[p.step.key])
    self.pending = nil
    if landed then
      self.counts.verified = self.counts.verified + 1
      setResult(self, p.log, "verified")
      return "ok"
    end
    setResult(self, p.log, "mismatch")
    finish(self, "aborted", "rankMismatch")
    return "abort"
  end
  if now - p.sentAt > RL.WAIT_LIMIT then
    self.pending = nil
    self.counts.unverified = self.counts.unverified + 1
    setResult(self, p.log, "unverified")
    if self.series and self.i <= #self.steps then
      finish(self, "aborted", "unverified")
      return "abort"
    end
    return "ok"
  end
  return "wait"
end

local function done(self)
  if self.i > #self.steps and not self.pending and not self.awaitingClick then
    finish(self, "done")
  end
end

-- Why an entry may not run now, checked on fresh data: nil when it may. A second value "abort" marks a
-- reason that ends the whole run (the right is gone).
local function recheck(self, step, snap)
  if step.action == "remove" and step.confirmed ~= true then
    return "nameMismatch", "abort"
  end
  local member = snap.members and snap.members[step.key]
  if not member then
    return "gone"
  end
  if RANKED[step.action] and (member.rank == 0 or step.fromRank == 0) then
    return "leader"
  end
  if step.action ~= "remove" and RL.Landed(step, member) then
    return "alreadyDone"
  end
  if step.fromRank and member.rank ~= step.fromRank then
    return "rankChanged"
  end
  local action = step.action
  local check = action
  if action == "setRank" then
    check = step.toRank < member.rank and "promote" or "demote"
  end
  local ctx = { self = snap.me, target = member, lowest = snap.lowest }
  local v = AL.Check(check, snap.rights, ctx)
  if v.ok and action == "editOfficerNote" then
    v = AL.Check("viewOfficerNote", snap.rights, ctx)
  end
  if v.ok and action == "setRank" then
    local mine = snap.me and snap.me.rank
    if type(mine) ~= "number" or step.toRank <= mine then
      v = { ok = false, reason = "promoteCap" }
    elseif step.toRank > (snap.lowest or -1) then
      v = { ok = false, reason = "lowest" }
    end
  end
  if not v.ok then
    return v.reason, v.reason == "noRight" and "abort" or nil
  end
  if self.env.rule then
    local yes, why = self.env.rule(step, snap)
    if not yes then
      return why or "ruleChanged"
    end
  end
end

-- Runs the next step when it may run now. Answers true and the result of the step ("sent", "dry",
-- "copy", "armed"), or false and why: "state", "wait" (and the seconds), "combat", "roster", "verify",
-- "click", or the reason the run ended.
function Run:Step()
  local env = self.env
  if self.state ~= "confirmed" and self.state ~= "running" and self.state ~= "paused" then
    return false, "state"
  end
  local now = env.now()
  if self.awaitingClick then
    return false, "click"
  end
  if self.nextAt and now < self.nextAt then
    return false, "wait", self.nextAt - now
  end
  local snap = env.snapshot and env.snapshot()
  if snap and snap.combat then
    wait(self, "combat")
    return false, "combat"
  end
  local verdict = settle(self, snap, now)
  if verdict == "abort" then
    return false, self.reason
  elseif verdict == "wait" then
    wait(self, "verify")
    return false, "verify"
  end
  while self.i <= #self.steps do
    local step = self.steps[self.i]
    local stale = not snap or type(snap.takenAt) ~= "number" or now - snap.takenAt > RL.MAX_AGE
    if stale then
      if env.request then
        env.request()
      end
      self.staleSince = self.staleSince or now
      if now - self.staleSince > RL.WAIT_LIMIT then
        finish(self, "aborted", "rosterStale")
        return false, "rosterStale"
      end
      wait(self, "roster", 1)
      return false, "roster"
    end
    self.staleSince = nil
    local why, severity = recheck(self, step, snap)
    if why then
      self.i = self.i + 1
      self.counts.skipped = self.counts.skipped + 1
      entryOf(self, step, "skipped", why)
      if severity == "abort" then
        finish(self, "aborted", why)
        return false, why
      end
    else
      local status, info = env.exec(step)
      if status == false then
        if info == "combat" then
          wait(self, "combat")
          return false, "combat"
        end
        self.i = self.i + 1
        self.counts.failed = self.counts.failed + 1
        entryOf(self, step, "failed", info)
        finish(self, "aborted", info or "failed")
        return false, info or "failed"
      end
      self.state = "running"
      if status == "armed" then
        -- One click on the secure button runs the command; Clicked() goes on from there.
        self.awaitingClick, self.pendingStep, self.pendingButton = true, step, info
        return true, "armed", info
      end
      self.i = self.i + 1
      self.executed = self.executed + 1
      if status == "dry" or status == "copy" then
        self.counts[status] = self.counts[status] + 1
        entryOf(self, step, status)
      else
        self.counts.sent = self.counts.sent + 1
        self.pending = { step = step, log = entryOf(self, step, "sent"), sentAt = now }
      end
      wait(self, "gap", gap(self))
      done(self)
      return true, status
    end
  end
  done(self)
  return false, self.state
end

-- The click on the secure button happened (the command went out): counts as sent, the roster tells the rest.
function Run:Clicked()
  local step = self.awaitingClick and self.pendingStep
  if not step then
    return false
  end
  self.awaitingClick, self.pendingStep, self.pendingButton = nil, nil, nil
  self.i = self.i + 1
  self.executed = self.executed + 1
  self.counts.sent = self.counts.sent + 1
  local now = self.env.now()
  self.pending = { step = step, log = entryOf(self, step, "sent"), sentAt = now }
  wait(self, "gap", gap(self))
  return true
end

-- Called regularly while the run is open: a series goes on when its pause is over, every run settles the
-- last step against the roster and ends when nothing is left.
function Run:Tick()
  if self.state == "done" or self.state == "aborted" or self.state == "ready" then
    return
  end
  if self.series and self.state ~= "confirmed" and not self.awaitingClick then
    self:Step()
    return
  end
  local snap = self.env.snapshot and self.env.snapshot()
  settle(self, snap, self.env.now())
  done(self)
end
