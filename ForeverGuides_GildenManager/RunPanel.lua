-- The run of the tab "Rules": starts Actions.StartRun on the ticked entries, asks for the confirmation
-- (the typed name of every removal, the typed number from three removals on), then one click per step
-- (a series only when the settings say so), a stop button, the progress and the result of every step.
-- A rank change can be taken back from here. The run itself, its checks on fresh data and the pauses
-- live in RunLogic.lua; nothing in this file calls the game.
local _, gm = ...
if not gm.ext then
  return
end
local FG, RUL, K, B = gm.FG, gm.RulesUiLogic, gm.RulesKit, gm.Backend
local W, L = FG.W, FG.L

local RP = {}
gm.RunPanel = RP

RP.MAX_STEPS = 25
local ROW_GAP = 8
local FIELD_HEIGHT = 26
local FIELD_WIDTH = 260
local UNDOABLE = { promote = true, demote = true, setRank = true }
local DONE = { sent = true, verified = true, unverified = true }

local function text(key, fallback)
  local s = L[key]
  return s ~= key and s or fallback
end

-- The words for a code of a refused step or a wait.
local function reasonText(code)
  if not code then
    return ""
  end
  return text("gm.why." .. code, text("gm.rules.wait." .. code, tostring(code)))
end

local function newRow(panel)
  local row = CreateFrame("Frame", nil, panel)
  row.fgId = "gm-run-row"
  row.line = W.Text(row, { role = "small", color = "text", wrap = true })
  row.name = W.EditBox(row, { placeholder = "gm.confirm.name" })
  row.name.fgId = "gm-run-name"
  row.undo = K.Button(row, "gm.rules.undo", function()
    local e = row.log and row.log.stored
    if e then
      gm.Actions.Undo(e, panel.hooks.ctx)
    end
  end, nil, "gm-run-undo")
  row.undo.fgHeight = 24
  return row
end

-- hooks: ctx (the page context for the dialogs), info() -> { dry = text, way = text }, onEnd().
function RP.New(parent, hooks)
  local panel = CreateFrame("Frame", nil, parent)
  panel.fgId = "gm-run"
  panel.hooks, panel.rows = hooks, {}
  panel.status = W.Text(panel, { role = "ui", color = "text", wrap = true })
  panel.dry = W.Text(panel, { role = "small", color = "warning", wrap = true })
  panel.way = W.Text(panel, { role = "small", color = "textSecondary", wrap = true })
  panel.count = W.EditBox(panel, { placeholder = "gm.rules.countHint" })
  panel.count.fgId = "gm-run-count"
  panel.msg = W.Text(panel, { role = "small", color = "danger", wrap = true })
  panel.confirmBtn = K.Button(panel, "gm.rules.confirmRun", function()
    panel:Confirm()
  end, "primary", "gm-run-confirm")
  panel.nextBtn = K.Button(panel, "gm.rules.next", function()
    panel:Next()
  end, "primary", "gm-run-next")
  panel.againBtn = K.Button(panel, "gm.rules.again", function()
    panel:Again()
  end, nil, "gm-run-again")
  panel.stopBtn = K.Button(panel, "gm.rules.stop", function()
    panel:Stop()
  end, "danger", "gm-run-stop")
  panel.closeBtn = K.Button(panel, "gm.rules.closeRun", function()
    panel:Close()
  end, nil, "gm-run-close")
  panel.flow = K.Flow(panel, { panel.confirmBtn, panel.nextBtn, panel.againBtn, panel.stopBtn, panel.closeBtn })
  panel.flow.fgId = "gm-run-buttons"

  local elapsed = 0
  panel:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed >= 0.5 then
      elapsed = 0
      if self.run and self:IsVisible() then
        self:Refresh()
      end
    end
  end)

  -- The overlay of the macro way hangs on UIParent: it follows the panel when this is shown or hidden.
  local function follow(self)
    if self.armed then
      B.Place(self.armed, self.nextBtn, self)
    end
  end
  panel:HookScript("OnHide", follow)
  panel:HookScript("OnShow", follow)

  -- entries: the ticked ready entries of the plan, plan(): builds the plan again on fresh data.
  function panel:Start(entries, plan)
    self:Close(true)
    self.run = gm.Actions.StartRun(entries, { plan = plan })
    self.msg:SetText("")
    self.count.edit:SetText("")
    self:Refresh()
    return self.run
  end

  function panel:Active()
    return self.run ~= nil
  end

  function panel:Confirm()
    local run = self.run
    if not run then
      return
    end
    local names = {}
    for i, step in ipairs(run.steps) do
      local row = self.rows[i]
      if step.action == "remove" and row then
        names[step.key] = row.name.edit:GetText()
      end
    end
    local ok, why = run:Confirm({ names = names, count = tonumber(self.count.edit:GetText()) })
    self.msg:SetText(ok and "" or reasonText(why))
    self:Refresh()
    return ok
  end

  -- Shows the command of the waiting step in the copy window once more.
  function panel:Again()
    if self.run then
      self.run:Again()
    end
  end

  -- One click, one step. The macro way hands over a secure button that takes the place of this one. While a
  -- typed command waits for the roster the click moves on without it (the step stays open).
  function panel:Next()
    local run = self.run
    if not run then
      return
    end
    if run.awaitingChange then
      run:Skip()
      self.msg:SetText("")
      self:Refresh()
      self.hooks.ctx.Refresh()
      return
    end
    local ok, info, extra = run:Step()
    if ok and info == "armed" then
      self.armed = extra
    elseif not ok then
      self.msg:SetText(reasonText(info))
    else
      self.msg:SetText("")
    end
    self:Refresh()
    self.hooks.ctx.Refresh()
  end

  function panel:Stop()
    if self.run then
      self.run:Abort()
    end
    self:Refresh()
  end

  local function release(self)
    if self.armed then
      B.Disarm(self.armed)
      self.armed = nil
    end
  end

  -- Ends the panel: a run that is still open is stopped first.
  function panel:Close(silent)
    local run = self.run
    if run and run.state ~= "done" and run.state ~= "aborted" then
      run:Abort()
    end
    release(self)
    self.run = nil
    if not silent then
      self.hooks.onEnd()
    end
  end

  function panel:Refresh()
    local run = self.run
    if not run then
      return
    end
    local state = run.state
    local finished = state == "done" or state == "aborted"
    local byKey = {}
    for _, e in ipairs(run.log) do
      byKey[e.key] = e
    end
    local info = self.hooks.info()
    self.dry:SetText(info.dry)
    W.SetColor(self.dry, info.live and "danger" or "warning")
    self.way:SetText(info.way)
    local total = #run.steps
    if total == 0 then
      self.status:SetText(L["gm.rules.noSteps"])
    elseif state == "ready" then
      self.status:SetText(string.format(L["gm.rules.runReady"], total))
    elseif finished then
      local c = run:Summary()
      self.status:SetText(
        string.format(L["gm.rules.runDone"], c.sent + c.dry + c.copy, c.skipped, c.failed)
          .. (run.reason and (" " .. reasonText(run.reason)) or "")
      )
    else
      self.status:SetText(
        string.format(L["gm.rules.runStep"], math.min(run.i, total), total) .. " " .. reasonText(run.why)
      )
    end
    local removals = 0
    for i = 1, math.min(total, RP.MAX_STEPS) do
      local step = run.steps[i]
      local row = self.rows[i] or newRow(self)
      self.rows[i] = row
      local e = byKey[step.key]
      row.log = e
      local res = e
          and (text("gm.rules.res." .. e.result, e.result) .. (e.reason and (": " .. reasonText(e.reason)) or ""))
        or L["gm.rules.res.pending"]
      row.line:SetText(step.name .. " - " .. RUL.ActionLine({
        action = { kind = step.action },
        fromRank = step.fromRank,
        toRank = step.toRank,
      }, self.hooks.names(), L) .. " - " .. res)
      local askName = state == "ready" and step.action == "remove"
      row.name:SetShown(askName)
      removals = removals + (step.action == "remove" and 1 or 0)
      row.undo:SetShown(
        e ~= nil and e.stored ~= nil and UNDOABLE[e.action] == true and DONE[e.result] == true and not e.stored.undone
      )
    end
    for i = #self.rows, 1, -1 do
      self.rows[i]:SetShown(i <= math.min(total, RP.MAX_STEPS))
    end
    self.count:SetShown(state == "ready" and removals >= gm.SettingsLogic.CONFIRM_COUNT)
    self.confirmBtn:SetShown(state == "ready" and total > 0)
    local waiting = state == "confirmed" or state == "running" or state == "paused"
    local clicking = run.awaitingClick == true and self.armed ~= nil
    -- The button stays under the secure overlay of the macro way, which has its own place on the screen.
    self.nextBtn:SetShown(waiting)
    self.againBtn:SetShown(waiting and run.awaitingChange ~= nil)
    self.stopBtn:SetShown(waiting or state == "ready")
    self.closeBtn:SetShown(finished or state == "ready")
    if run.awaitingChange then
      W.SetText(self.nextBtn.label, "gm.rules.skip")
    elseif run.series and waiting then
      W.SetText(self.nextBtn.label, "gm.rules.startSeries")
    else
      W.SetText(self.nextBtn.label, "gm.rules.next")
    end
    if self.armed then
      if clicking then
        B.Place(self.armed, self.nextBtn, self)
      else
        release(self)
      end
    end
    if finished then
      release(self)
    end
  end

  function panel:fgGridLayout(width)
    local y = 0
    local function place(item, h)
      item:ClearAllPoints()
      item:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      y = y + h + ROW_GAP
    end
    for _, fs in ipairs({ self.status, self.dry, self.way }) do
      fs:SetWidth(width)
      place(fs, math.ceil(fs:GetStringHeight()))
    end
    for _, row in ipairs(self.rows) do
      if row:IsShown() then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        row:SetWidth(width)
        row.line:SetWidth(width)
        row.line:ClearAllPoints()
        row.line:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        local h = math.ceil(row.line:GetStringHeight()) + 2
        if row.name:IsShown() then
          row.name:ClearAllPoints()
          row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -h)
          row.name:SetSize(math.min(FIELD_WIDTH, width), FIELD_HEIGHT)
          h = h + FIELD_HEIGHT + 4
        end
        if row.undo:IsShown() then
          row.undo:ClearAllPoints()
          row.undo:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -h)
          row.undo:SetSize(math.min(math.ceil(row.undo.label:GetStringWidth()) + 24, width), 24)
          h = h + 24 + 4
        end
        row:SetHeight(h)
        y = y + h + ROW_GAP
      end
    end
    if self.count:IsShown() then
      self.count:ClearAllPoints()
      self.count:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
      self.count:SetSize(math.min(FIELD_WIDTH, width), FIELD_HEIGHT)
      y = y + FIELD_HEIGHT + ROW_GAP
    end
    self.msg:SetWidth(width)
    place(self.msg, math.ceil(self.msg:GetStringHeight()))
    self.flow:SetWidth(width)
    place(self.flow, self.flow:fgGridLayout(width))
    y = math.max(y - ROW_GAP, 1)
    self:SetHeight(y)
    return y
  end
  return panel
end
