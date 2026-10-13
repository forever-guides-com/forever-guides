-- Writing guild actions from the detail card: promote, demote, guild note, officer note and remove.
-- Every action checks the rights and the rank rules (ActionsLogic.lua), shows a preview in a
-- confirm dialog and runs through C_GuildInfo only. The one file of the add-on that changes the
-- guild. Not in combat, at most one action every ActionsLogic.GAP seconds, optional dry run.
local _, gm = ...
if not gm.ext then
  return
end
local FG, AL = gm.FG, gm.ActionsLogic
local W, L, PN = FG.W, FG.L, FG.PlayerName
local GD, GE = FG.GuildData, FG.GuildExt

local A = {}
gm.Actions = A

-- C_GuildInfo function per action and what it takes first: the roster GUID ("guid", the name only
-- where `fallback` is set) or the member name. Notes also take the text and the public flag.
local CALLS = {
  promote = { fn = "Promote", by = "name" },
  demote = { fn = "Demote", by = "name" },
  remove = { fn = "RemoveFromGuild", by = "guid", fallback = true },
  editNote = { fn = "SetNote", by = "guid", public = true },
  editOfficerNote = { fn = "SetNote", by = "guid", public = false },
}
-- Buttons of the detail card in this order.
local BUTTONS = { "promote", "demote", "editNote", "editOfficerNote", "remove" }
local NOTES = { editNote = true, editOfficerNote = true }

-- Game access ----------------------------------------------------------------------------------------

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

local function argument(call, m)
  if call.by == "guid" and m.guid then
    return m.guid
  end
  if call.by == "name" or call.fallback then
    return m.name
  end
end

-- Runs a confirmed action. Answers "sent" (the call went out), "dry" (dry run, nothing sent), "source"
-- (a stand-in source took it, the game was not called) or false and a reason code. The roster is read again here: rank and rights may have changed while
-- the dialog was open. value: the new text of a note.
function A.Run(action, member, value)
  local call = CALLS[action]
  if not (call and type(member) == "table") then
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
  local source = GD.Source()
  if source then
    -- A stand-in source takes the action on its own rows and the log (a copy in memory) gets the entry,
    -- the game is never called.
    if not source.apply(action, m.key, value) then
      return false, "failed"
    end
    AL.Record(gm.db, { action = action, name = m.name, old = old, new = new }, FG.U.now())
    FG.Notify(string.format(L[source.done], L["gm.act." .. action], m.name), "info")
    return "source"
  end
  if gm.db.dryRun then
    FG.Notify(string.format(L["gm.dry.done"], L["gm.act." .. action], m.name), "info")
    return "dry"
  end
  if AL.Wait(A.last, clock()) > 0 then
    return false, "throttle"
  end
  local fn = endpoint(call.fn)
  if not fn then
    return false, "noApi"
  end
  local target = argument(call, m)
  if not target then
    return false, "noGuid"
  end
  A.last = clock()
  local ok
  if call.public == nil then
    ok = pcall(fn, target)
  else
    ok = pcall(fn, target, value, call.public)
  end
  if not ok then
    return false, "failed"
  end
  AL.Record(gm.db, { action = action, name = m.name, old = old, new = new }, FG.U.now())
  GD.Request()
  FG.Notify(string.format(L["gm.sent." .. action], m.name), "success")
  return "sent"
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
  if action == "remove" then
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
  local status, why = A.Run(d.action, d.member, value)
  if not status then
    d.msg:SetText(L["gm.why." .. why])
    return
  end
  d:Hide()
  if d.ctx and d.ctx.Refresh then
    d.ctx.Refresh()
  end
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

-- Opens the confirm dialog of an action for a member of the roster. False (and a hint) when the
-- action is not allowed right now.
function A.Open(action, member, ctx)
  local roster = GD.Get()
  local m = find(roster, member.key)
  local v = verdict(action, GE.Rights(), context(roster, m))
  local why = not v.ok and v.reason or inCombat() and "combat" or nil
  if why then
    FG.Notify(L["gm.why." .. why], "warning")
    return false
  end
  dialog = dialog or build()
  local d = dialog
  d.action, d.member, d.ctx = action, m, ctx
  W.SetText(d.title, "gm.act." .. action)
  d.who:SetText(m.name)
  d.msg:SetText("")
  local source = GD.Source()
  W.SetText(d.dry, source and source.hint or "gm.dry.hint")
  d.dry:SetShown(source ~= nil or gm.db.dryRun == true)
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
