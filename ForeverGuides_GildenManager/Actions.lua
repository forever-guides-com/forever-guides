-- Writing guild actions from the detail card: promote, demote, guild note, officer note and remove.
-- Every action checks the rights and the rank rules (ActionsLogic.lua), shows a preview in a
-- confirm dialog and goes out through Backend.lua only (direct call, secure button or copy window, by
-- the setting actionBackend). Not in combat, a pause between two actions (setting pauseSec), optional
-- dry run. Plan runs in steps go through RunLogic.lua (A.StartRun).
local _, gm = ...
if not gm.ext then
  return
end
local FG, AL, B, RL = gm.FG, gm.ActionsLogic, gm.Backend, gm.RunLogic
local W, L, PN = FG.W, FG.L, FG.PlayerName
local GD, GE = FG.GuildData, FG.GuildExt

local A = {}
gm.Actions = A

-- Buttons of the detail card in this order.
local BUTTONS = { "promote", "demote", "editNote", "editOfficerNote", "remove" }
local NOTES = { editNote = true, editOfficerNote = true }

-- Game access ----------------------------------------------------------------------------------------

-- Settings of the guild record through SettingsLogic (loaded after this file, so looked up on use).
local function setting(id)
  return gm.SettingsLogic.Get({ guild = gm.Guild(), prefs = gm.db.prefs }, id)
end

local function inCombat()
  local ok, fighting = pcall(InCombatLockdown)
  return ok and fighting == true
end

local function clock()
  local ok, now = pcall(GetTime)
  return ok and tonumber(now) or 0
end

local function endpoint(name)
  local info = rawget(_G, "C_GuildInfo")
  local fn = type(info) == "table" and info[name]
  return type(fn) == "function" and fn or nil
end

-- Number of ranks as the game reports it, nil when the client has no such function.
local function rankCount()
  if GD.Source() then
    return #GD.Get().ranks
  end
  local fn = endpoint("GuildControlGetNumRanks") or rawget(_G, "GuildControlGetNumRanks")
  if type(fn) ~= "function" then
    return nil
  end
  local ok, n = pcall(fn)
  return ok and tonumber(n) or nil
end

local function find(roster, key)
  for _, m in ipairs(roster.members) do
    if m.key == key then
      return m
    end
  end
end

-- Own roster row, target and lowest rank for the rank rules.
local function context(roster, target)
  return {
    self = find(roster, PN.Key(PN.Self())),
    target = target,
    lowest = AL.Lowest(roster.ranks, rankCount()),
  }
end

-- Officer notes are only changed by someone who can read them, so the old value in the preview
-- and in the log is real.
local function verdict(action, rights, ctx)
  local v = AL.Check(action, rights, ctx)
  if v.ok and action == "editOfficerNote" then
    v = AL.Check("viewOfficerNote", rights, ctx)
  end
  return v
end

local function rankName(roster, index)
  if type(index) ~= "number" then
    return "?"
  end
  for _, r in ipairs(roster.ranks) do
    if r.index == index then
      return r.name
    end
  end
  return string.format(L["gm.pv.rankN"], index + 1)
end

-- Old and new value of the action for the preview and the log.
local function values(action, roster, m, value)
  if action == "promote" or action == "demote" then
    return rankName(roster, m.rank), rankName(roster, AL.NewRank(action, m))
  elseif action == "remove" then
    return rankName(roster, m.rank), ""
  elseif action == "editNote" then
    return m.note, value
  end
  return m.officerNote, value
end

-- Result of the roster after a change went out: the entry in the log gets "verified" when the member
-- shows it, "unverified" when the roster did not show it in time.
local WATCH_SECONDS = 60

local function watch(stored, step)
  A.watch = stored and { stored = stored, step = step, since = clock() } or nil
end

FG.On("FG_GUILD_UPDATE", function()
  local w = A.watch
  if not w then
    return
  end
  if RL.Landed(w.step, find(GD.Get(), w.step.key)) then
    w.stored.result, A.watch = "verified", nil
  elseif clock() - w.since > WATCH_SECONDS then
    w.stored.result, A.watch = "unverified", nil
  end
end)

-- The step the backend takes: who, with which identifiers, the target rank or the new text.
local function stepOf(action, m, value)
  return { name = m.name, guid = m.guid, index = m.index, toRank = AL.NewRank(action, m), value = value }
end

-- Sends one action: a stand-in source takes it on its own rows, a dry run sends nothing, else the
-- backend. Answers "source", "dry", the answer of Backend.Do (status, info) or false and a reason.
-- noPause: the caller keeps the pause itself (a run). toRank: the target of a jump over several ranks.
local function dispatch(action, m, value, onClick, noPause, toRank)
  local source = GD.Source()
  if source then
    if source.apply(action, m.key, value, toRank) then
      return "source"
    end
    return false, "failed"
  end
  if gm.Guild().settings.dryRun then
    return "dry"
  end
  if not noPause and AL.Wait(A.last, clock(), setting("pauseSec")) > 0 then
    return false, "throttle"
  end
  local status, info = B.Do(action, stepOf(action, m, value), { choice = setting("actionBackend"), onClick = onClick })
  if status == "sent" then
    A.last = clock()
  end
  return status, info
end

-- Runs a confirmed action. Answers "sent" (the call went out), "dry" (dry run, nothing sent), "source"
-- (a stand-in source took it, the game was not called), "armed" and the button (macro way: one click on
-- the button sends it), "copy" and the text (copy window) or false and a reason code. The roster is read
-- again here: rank and rights may have changed while the dialog was open.
-- value: the new text of a note. opts: { undo = log entry this action takes back, onSent = function }.
function A.Run(action, member, value, opts)
  opts = opts or {}
  if not (AL.RIGHT[action] and AL.LOGGED[action] and type(member) == "table") then
    return false, "unknownAction"
  end
  local roster = GD.Get()
  local m = find(roster, member.key)
  local v = verdict(action, GE.Rights(), context(roster, m))
  if not v.ok then
    return false, v.reason
  end
  if inCombat() then
    return false, "combat"
  end
  if NOTES[action] then
    value = AL.CleanNote(value)
    if value == m[action == "editNote" and "note" or "officerNote"] then
      return false, "unchanged"
    end
  end
  local old, new = values(action, roster, m, value)
  local step = { action = action, key = m.key, toRank = AL.NewRank(action, m), value = value }
  local entry = { action = action, name = m.name, old = old, new = new, from = m.rank, to = step.toRank }
  -- The change went out: log it, ask for the roster, tell the player and wait for the roster to show it.
  local function sent(toastKey)
    local _, stored = AL.Record(
      gm.Guild(),
      { action = action, name = m.name, old = old, new = new, result = "sent", from = entry.from, to = entry.to },
      gm.History.Epoch()
    )
    watch(stored, step)
    if opts.undo then
      opts.undo.undone = true
    end
    A.last = clock()
    GD.Request()
    FG.Notify(string.format(L[toastKey], m.name), "success")
    if opts.onSent then
      opts.onSent()
    end
  end
  local status, info = dispatch(action, m, value, function()
    sent("gm.macro.sent")
  end)
  if not status then
    return false, info
  elseif status == "source" then
    -- The log (a copy in memory) gets the entry, the game is never called.
    AL.Record(gm.Guild(), entry, gm.History.Epoch())
    FG.Notify(string.format(L[GD.Source().done], L["gm.act." .. action], m.name), "info")
  elseif status == "dry" then
    FG.Notify(string.format(L["gm.dry.done"], L["gm.act." .. action], m.name), "info")
  elseif status == "copy" then
    FG.Notify(string.format(L["gm.copy.done"], m.name), "info")
  elseif status == "sent" then
    sent("gm.sent." .. action)
  end
  return status, info
end

-- Dialog ---------------------------------------------------------------------------------------------

local dialog

local function shown(s)
  return s ~= "" and s or L["gm.pv.empty"]
end

-- The preview: who gets what, old and new value.
local function render(d)
  local roster, m, action = GD.Get(), d.member, d.action
  local text
  if action == "invite" then
    text = string.format(L["gm.pv.invite"], m.name)
  elseif action == "remove" then
    text = string.format(L["gm.pv.remove"], m.name)
      .. "\n"
      .. string.format(L["guild.detail.rank"], rankName(roster, m.rank))
  elseif NOTES[action] then
    local old = values(action, roster, m)
    text = string.format(L["gm.pv.old"], shown(old))
      .. "\n"
      .. string.format(L["gm.pv.new"], shown(AL.CleanNote(d.text.edit:GetText())))
  else
    local old, new = values(action, roster, m)
    text = string.format(L["gm.pv.rank"], old, new)
  end
  d.body:SetText(text)
end

-- Macro way: the secure button takes the place of the confirm button, one click on it sends the command.
local function arm(d, button)
  d.sendButton = button
  button:SetParent(d)
  button:ClearAllPoints()
  button:SetAllPoints(d.ok)
  if not button.fgLabel then
    W.Fill(button, "surface", 1)
    W.Border(button, "white", 0.4)
    button.fgLabel = W.Text(button, { key = "gm.macro.send", role = "ui", justify = "CENTER" })
    button.fgLabel:SetPoint("CENTER")
  end
  d.ok:Hide()
  d.msg:SetText("")
  d.note:SetText(L["gm.macro.tip"])
end

-- Gives the secure button back and restores the confirm button.
local function release(d)
  if d.sendButton then
    B.Disarm(d.sendButton)
    d.sendButton = nil
  end
  d.ok:Show()
  d.note:SetText("")
end

local function close(d)
  d:Hide()
  if d.ctx and d.ctx.Refresh then
    d.ctx.Refresh()
  end
end

local function confirm()
  local d = dialog
  local value
  if d.action == "remove" then
    if not AL.NameConfirmed(d.name.edit:GetText(), d.member.name) then
      d.msg:SetText(L["gm.why.nameMismatch"])
      return
    end
  elseif NOTES[d.action] then
    value = d.text.edit:GetText()
  end
  local function sent()
    close(d)
  end
  local status, info
  if d.action == "invite" then
    status, info = A.RunInvite(d.member.name, { onSent = sent })
  else
    status, info = A.Run(d.action, d.member, value, { undo = d.undo, onSent = sent })
  end
  if not status then
    d.msg:SetText(L["gm.why." .. info])
    return
  end
  if status == "armed" then
    arm(d, info)
    return
  end
  close(d)
end

local function build()
  local d = FG.Dialogs.Create("ForeverGuidesGMAction", 420, 310)
  d.who = W.Text(d, { role = "ui", color = "accent2" })
  d.who:SetPoint("TOPLEFT", 16, -48)
  d.who:SetPoint("RIGHT", -16, 0)
  d.body = W.Text(d, { role = "ui", wrap = true })
  d.body:SetPoint("TOPLEFT", 16, -76)
  d.body:SetPoint("RIGHT", -16, 0)
  d.label = W.Text(d, { role = "ui" })
  d.label:SetPoint("TOPLEFT", 16, -150)
  d.text = W.EditBox(d, {
    placeholder = "gm.pv.empty",
    onChange = function()
      render(d)
    end,
    onEnter = confirm,
  })
  d.text:SetPoint("TOPLEFT", 16, -172)
  d.text:SetWidth(388)
  d.text.edit:SetMaxLetters(AL.MAX_NOTE)
  d.name = W.EditBox(d, { placeholder = "gm.confirm.name", onEnter = confirm })
  d.name:SetPoint("TOPLEFT", 16, -172)
  d.name:SetWidth(388)
  d.name.edit:SetMaxLetters(PN.MAX_PART * 3 + 2)
  d.dry = W.Text(d, { key = "gm.dry.hint", role = "micro", color = "warning" })
  d.dry:SetPoint("TOPLEFT", 16, -210)
  d.msg = W.Text(d, { role = "ui", color = "danger", wrap = true })
  d.msg:SetPoint("TOPLEFT", 16, -230)
  d.msg:SetPoint("RIGHT", -16, 0)
  local ok = W.Action(d, {
    label = "act.confirm",
    icon = "check",
    tooltip = "gm.act.confirm",
    variant = "primary",
    width = 110,
    onClick = confirm,
  })
  ok.fgId = "gm-action-confirm"
  ok:SetPoint("BOTTOMRIGHT", -16, 14)
  d.ok = ok
  d.note = W.Text(d, { role = "ui", color = "textSecondary", wrap = true })
  d.note:SetPoint("TOPLEFT", 16, -230)
  d.note:SetPoint("RIGHT", -16, 0)
  d:HookScript("OnHide", function()
    release(d)
  end)
  local cancel = W.Action(d, {
    label = "act.cancel",
    icon = "close",
    tooltip = "common.cancel",
    width = 110,
    onClick = function()
      d:Hide()
    end,
  })
  cancel:SetPoint("RIGHT", ok, "LEFT", -8, 0)
  return d
end

-- The dialog set up for an action and its target: title, name, dry run hint, nothing armed.
local function prepare(action, member, ctx, undo)
  dialog = dialog or build()
  local d = dialog
  d.action, d.member, d.ctx, d.undo = action, member, ctx, undo
  release(d)
  W.SetText(d.title, "gm.act." .. action)
  d.who:SetText(member.name)
  d.msg:SetText("")
  local source = GD.Source()
  W.SetText(d.dry, source and source.hint or "gm.dry.hint")
  d.dry:SetShown(source ~= nil or gm.Guild().settings.dryRun == true)
  return d
end

-- Opens the confirm dialog of an action for a member of the roster. False (and a hint) when the
-- action is not allowed right now.
function A.Open(action, member, ctx, opts)
  local roster = GD.Get()
  local m = find(roster, member.key)
  local v = verdict(action, GE.Rights(), context(roster, m))
  local why = not v.ok and v.reason or inCombat() and "combat" or nil
  if why then
    FG.Notify(L["gm.why." .. why], "warning")
    return false
  end
  local d = prepare(action, m, ctx, opts and opts.undo)
  local isNote, isRemove = NOTES[action] == true, action == "remove"
  d.text:SetShown(isNote)
  d.name:SetShown(isRemove)
  d.label:SetShown(isNote or isRemove)
  W.SetText(d.label, isNote and "gm.field.note" or "gm.confirm.name")
  d.name.edit:SetText("")
  d.text.edit:SetText(isNote and (values(action, roster, m)) or "")
  render(d)
  d:Show()
  return true
end

-- Invite -----------------------------------------------------------------------------------------------

local function inRoster(name)
  for _, row in ipairs(GD.Get().members) do
    if PN.Equal(row.name, name) then
      return true
    end
  end
  return false
end

-- Whether an invite for this name makes sense: the right is there and the name is not in the guild.
function A.CanInvite(name)
  return type(name) == "string"
    and name ~= ""
    and AL.Check("invite", GE.Rights()).ok
    and not PN.Equal(name, PN.Self())
    and not inRoster(name)
end

-- The reason an invite cannot go out right now, nil when it can.
local function inviteWhy(name)
  if type(name) ~= "string" or name == "" then
    return "noTarget"
  end
  local v = AL.Check("invite", GE.Rights())
  if not v.ok then
    return v.reason
  end
  if inCombat() then
    return "combat"
  end
  if PN.Equal(name, PN.Self()) or inRoster(name) then
    return "alreadyDone"
  end
end

-- Runs a confirmed invite, same answers as A.Run. Never logged: an invite changes nothing until it is accepted.
function A.RunInvite(name, opts)
  opts = opts or {}
  local why = inviteWhy(name)
  if why then
    return false, why
  end
  local function sent(toastKey)
    A.last = clock()
    GD.Request()
    FG.Notify(string.format(L[toastKey], name), "success")
    if opts.onSent then
      opts.onSent()
    end
  end
  local source = GD.Source()
  if source then
    FG.Notify(string.format(L[source.done], L["gm.act.invite"], name), "info")
    return "source"
  end
  if gm.Guild().settings.dryRun then
    FG.Notify(string.format(L["gm.dry.done"], L["gm.act.invite"], name), "info")
    return "dry"
  end
  if AL.Wait(A.last, clock(), setting("pauseSec")) > 0 then
    return false, "throttle"
  end
  local status, info = B.Do("invite", { name = name }, {
    choice = setting("actionBackend"),
    onClick = function()
      sent("gm.macro.sent")
    end,
  })
  if status == "sent" then
    sent("gm.sent.invite")
  elseif status == "copy" then
    FG.Notify(string.format(L["gm.copy.done"], name), "info")
  end
  return status, info
end

-- Opens the confirm dialog to invite a name again. False and a hint when it cannot go out now.
function A.OpenInvite(name, ctx)
  local why = inviteWhy(name)
  if why then
    FG.Notify(L["gm.why." .. why], "warning")
    return false
  end
  local d = prepare("invite", { name = name, key = PN.Key(name) }, ctx)
  d.text:Hide()
  d.name:Hide()
  d.label:Hide()
  render(d)
  d:Show()
  return true
end

-- Runs in steps ---------------------------------------------------------------------------------------

-- The roster, the rights and the combat state as a run reads them before each step.
local function snapshot()
  local roster = GD.Get()
  local members = {}
  for _, m in ipairs(roster.members) do
    members[m.key] = m
  end
  return {
    members = members,
    me = members[PN.Key(PN.Self())],
    rights = GE.Rights(),
    lowest = AL.Lowest(roster.ranks, rankCount()),
    takenAt = roster.takenAt or clock(),
    combat = inCombat(),
  }
end

-- The plan context fields the settings decide (protection periods, maximum), for the caller that builds
-- a plan; the same values are read again when a run checks a step against a fresh plan.
function A.PlanContext()
  return gm.SettingsLogic.PlanContext({ guild = gm.Guild(), prefs = gm.db.prefs })
end

local runs, driver = {}, nil

-- Calls Tick of every open run twice a second; a run that ended drops out.
local function drive(run)
  runs[#runs + 1] = run
  if not driver then
    local elapsed = 0
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(self, dt)
      elapsed = elapsed + (tonumber(dt) or 0)
      if elapsed < 0.5 then
        return
      end
      elapsed = 0
      for i = #runs, 1, -1 do
        runs[i]:Tick()
        if runs[i].state == "done" or runs[i].state == "aborted" then
          table.remove(runs, i)
        end
      end
      self:SetShown(#runs > 0)
    end)
  end
  driver:Show()
end

-- A run of plan entries (PlanLogic, ready ones) with the pause, mode, maximum and message of the
-- settings. opts.plan: function that builds the plan again on fresh data, so each step also checks that
-- its rule and protections still hold (see RunLogic.RuleCheck). Answers the run in state "ready": the
-- caller shows the preview, confirms (run:Confirm), triggers (run:Step) and may stop it (run:Abort).
function A.StartRun(entries, opts)
  opts = opts or {}
  local settings = RL.Settings(setting)
  local run
  run = RL.New(entries, {
    settings = settings,
    backend = B.Resolve(setting("actionBackend"), "promote"),
    env = {
      now = clock,
      time = gm.History.Epoch,
      rand = math.random,
      snapshot = snapshot,
      request = GD.Request,
      rule = opts.plan and RL.RuleCheck(opts.plan) or nil,
      disarm = B.Disarm,
      exec = function(step)
        local m = find(GD.Get(), step.key)
        if not m then
          return false, "gone"
        end
        return dispatch(step.action, m, step.value, function()
          run:Clicked()
        end, true, step.toRank)
      end,
      values = function(step)
        local roster = GD.Get()
        local m = find(roster, step.key)
        if NOTES[step.action] then
          return m and (step.action == "editNote" and m.note or m.officerNote) or "", step.value or ""
        end
        return rankName(roster, step.fromRank), step.action == "remove" and "" or rankName(roster, step.toRank)
      end,
      log = function(e, event)
        if event == "new" and e.result == "sent" then
          -- A jump over several ranks is logged by its direction.
          local action = e.action == "setRank" and (e.to < e.from and "promote" or "demote") or e.action
          local _, stored = AL.Record(gm.Guild(), {
            action = action,
            name = e.name,
            old = e.old,
            new = e.new,
            rule = e.rule,
            result = "sent",
            from = e.from,
            to = e.to,
          }, e.t)
          e.stored = stored
          if e.undoOf then
            e.undoOf.undone = true
          end
        elseif event == "update" and e.stored and AL.RESULTS[e.result] then
          e.stored.result = e.result
        end
      end,
      finish = function(summary)
        FG.Notify(
          string.format(L["gm.run.done"], summary.sent + summary.dry + summary.copy, summary.skipped, summary.failed),
          "info"
        )
        if summary.state == "aborted" and summary.reason then
          FG.Notify(string.format(L["gm.run.stopped"], L["gm.why." .. summary.reason]), "warning")
        end
      end,
    },
  })
  drive(run)
  return run
end

-- Takes a logged rank change back: opens the same dialog (preview, confirmation, pause) for the opposite
-- step. entry: an entry of the action log. False and a hint when it cannot be undone now.
function A.Undo(entry, ctx)
  local roster = GD.Get()
  local m
  for _, row in ipairs(roster.members) do
    if type(entry) == "table" and PN.Equal(row.name, entry.name) then
      m = row
    end
  end
  local step, why = RL.Undo(entry, m, gm.History.Epoch(), setting("undoDays"))
  if step and step.action ~= "promote" and step.action ~= "demote" then
    step, why = nil, "noApi"
  end
  if not step then
    FG.Notify(L["gm.why." .. why], "warning")
    return false
  end
  return A.Open(step.action, m, ctx, { undo = entry })
end

gm.ext.RegisterDetail({
  id = "gm-actions",
  order = 20,
  actions = function(m, ctx)
    local roster, rights = ctx.Roster(), GE.Rights()
    local c = context(roster, m)
    local out = {}
    for _, action in ipairs(BUTTONS) do
      if verdict(action, rights, c).ok then
        out[#out + 1] = {
          key = "gm.act." .. action,
          onClick = function(member, hookCtx)
            A.Open(action, member, hookCtx)
          end,
        }
      end
    end
    return out
  end,
})
