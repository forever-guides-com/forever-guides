-- Reset question on entering an instance (rules in Modules/BossResetLogic.lua): when boss progress of an earlier
-- run is stored for it, a small own window asks whether a new run begins. Yes forgets the progress of that
-- instance (ns.BossProgress.Reset), No keeps it; Esc and the close button count as No. An answer holds for the
-- instance for BossResetLogic.ANSWER_TTL. In combat the question waits for its end. Also the manual reset (with
-- a confirmation) for the boss tab of the dungeon map and the setting "ask when entering".
local _, ns = ...
local W, L, Store = ns.W, ns.L, ns.Store
local BP, Logic = ns.BossProgress, ns.BossResetLogic

local BR = {}
ns.BossReset = BR

ns.AddLocale("enUS", {
  ["bossreset.question"] = "The saved boss progress of this instance comes from an earlier run. Start a new run and reset the progress?",
  ["bossreset.yes"] = "Yes, reset",
  ["bossreset.no"] = "No, keep progress",
  ["bossreset.done"] = "Boss progress of %s reset.",
  ["bossreset.manual.title"] = "Reset boss progress",
  ["bossreset.manual.text"] = "Delete the saved boss progress of this instance? A new run then starts without defeated bosses.",
  ["bossreset.set.heading"] = "Boss progress",
  ["bossreset.set.hint"] = "When you enter an instance with saved boss progress, the addon asks whether a new run begins. The question does not appear in combat, shortly after the latest kill or when the game itself knows a lockout for the instance.",
  ["bossreset.set.ask"] = "Ask when entering after a reset",
  ["bossreset.set.askTip"] = "Shows a window with the instance and the saved progress when you enter it again after more than 10 minutes.",
  ["bossreset.set.warn"] = "Caution: Yes deletes the saved progress of that instance and it cannot be restored. The game and your lockouts stay as they are. Without the question an old progress keeps showing defeated bosses.",
})

ns.AddLocale("deDE", {
  ["bossreset.question"] = "Der gespeicherte Boss-Fortschritt dieser Instanz stammt von einem früheren Durchlauf. Neuen Durchlauf beginnen und den Stand zurücksetzen?",
  ["bossreset.yes"] = "Ja, zurücksetzen",
  ["bossreset.no"] = "Nein, Stand behalten",
  ["bossreset.done"] = "Boss-Fortschritt von %s zurückgesetzt.",
  ["bossreset.manual.title"] = "Boss-Fortschritt zurücksetzen",
  ["bossreset.manual.text"] = "Den gespeicherten Boss-Fortschritt dieser Instanz löschen? Ein neuer Durchlauf beginnt dann ohne besiegte Bosse.",
  ["bossreset.set.heading"] = "Boss-Fortschritt",
  ["bossreset.set.hint"] = "Betrittst du eine Instanz mit gespeichertem Boss-Fortschritt, fragt das Addon, ob ein neuer Durchlauf beginnt. Die Frage kommt nicht im Kampf, nicht kurz nach dem letzten Kill und nicht, wenn das Spiel selbst eine Sperre für die Instanz kennt.",
  ["bossreset.set.ask"] = "Beim Betreten nach Zurücksetzen fragen",
  ["bossreset.set.askTip"] = "Zeigt ein Fenster mit Instanz und gespeichertem Stand, wenn du sie nach mehr als 10 Minuten wieder betrittst.",
  ["bossreset.set.warn"] = "Achtung: Ja löscht den gespeicherten Stand dieser Instanz, er lässt sich nicht wiederherstellen. Das Spiel und deine Sperren bleiben unverändert. Ohne die Frage zeigt ein alter Stand weiter besiegte Bosse an.",
})

local WIDTH, PAD, IMG_H, GAP = 460, 16, 120, 8

-- Where the player was after the latest zone change (instance ID, nil outside), the time of the answer per
-- instance (memory only), the instance whose question waits for the end of combat, the window and its instance.
local previous
local answeredAt = {}
local pending
local dialog, shownFor

local function now()
  return ns.CharRoster.Now()
end

local function enabled()
  local s = ns.db and ns.db.settings
  return not s or s.bossResetPrompt ~= false
end

local function inCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- The Data.Instances entry of an instance ID.
local function instanceOf(id)
  local _, inst = ns.PinLogic.BossList(id)
  return inst
end

-- True when the question is due for this instance now.
local function due(id)
  local summary = BP.Summary(id)
  return Logic.Skip({
    enabled = enabled(),
    killed = summary and summary.killed,
    lastKill = BP.LastKill(id),
    now = now(),
    locked = BP.Locked(id),
    answeredAt = answeredAt[id],
  }) == nil
end

-- Window ------------------------------------------------------------------------------------------

-- Places the parts for the width and sets the height; the two buttons share a row when they fit, else stack.
local function layout(d)
  local inner = WIDTH - PAD * 2
  local y = 48
  d.box:SetShown(d.image ~= nil)
  if d.image then
    d.box:ClearAllPoints()
    d.box:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -y)
    d.box:SetSize(inner, IMG_H)
    local probe = ns.AssetFiles.cache[d.image.fid]
    d.picture:SetTexCoord(ns.InstanceView.Crop(d.image.src, inner, IMG_H, probe and probe.w, probe and probe.h))
    y = y + IMG_H + 12
  end
  for _, text in ipairs({ d.question, d.count }) do
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -y)
    text:SetWidth(inner)
    y = y + math.ceil(text:GetStringHeight()) + GAP
  end
  local yesW, noW = d.yes:FullWidth(), d.no:FullWidth()
  local h = d.yes:GetHeight()
  d.yes:SetWidth(yesW)
  d.no:SetWidth(noW)
  d.yes:ClearAllPoints()
  d.no:ClearAllPoints()
  y = y + 6
  if yesW + noW + GAP <= inner then
    d.no:SetPoint("TOPLEFT", d, "TOPLEFT", PAD, -y)
    d.yes:SetPoint("TOPRIGHT", d, "TOPRIGHT", -PAD, -y)
    y = y + h
  else
    d.yes:SetPoint("TOPRIGHT", d, "TOPRIGHT", -PAD, -y)
    y = y + h + GAP
    d.no:SetPoint("TOPRIGHT", d, "TOPRIGHT", -PAD, -y)
    y = y + h
  end
  d:SetSize(WIDTH, y + PAD)
end

local function build()
  local d = ns.Dialogs.Create("ForeverGuidesBossReset", WIDTH, 240)
  d.box = CreateFrame("Frame", nil, d)
  W.Fill(d.box, "surface", 1)
  d.picture = d.box:CreateTexture(nil, "ARTWORK")
  d.picture:SetPoint("TOPLEFT", 1, -1)
  d.picture:SetPoint("BOTTOMRIGHT", -1, 1)
  W.Border(d.box, "white")
  d.question = W.Text(d, { key = "bossreset.question", role = "text", wrap = true })
  d.count = W.Text(d, { role = "ui", color = "accent2", wrap = true })
  d.yes = W.Action(d, {
    key = "bossreset.yes",
    icon = "reset",
    variant = "primary",
    height = 28,
    onClick = function()
      local id = shownFor
      d:Hide()
      if id and BP.Reset(id) then
        local inst = instanceOf(id)
        ns.Notify(string.format(L["bossreset.done"], inst and ns.T(inst.n) or tostring(id)), "info")
      end
    end,
  })
  d.no = W.Action(d, {
    key = "bossreset.no",
    icon = "close",
    height = 28,
    onClick = function()
      d:Hide()
    end,
  })
  -- Every way to close the window except the silent ones (see closeSilently) is an answer: the question
  -- does not come back for this instance for a while.
  d:HookScript("OnHide", function()
    if shownFor and not d.silent then
      answeredAt[shownFor] = now()
    end
    shownFor, d.silent = nil, false
  end)
  return d
end

local function show(id)
  local inst = instanceOf(id)
  local summary = BP.Summary(id)
  if not (inst and summary) then
    return
  end
  dialog = dialog or build()
  shownFor = id
  W.SetText(dialog.title, nil, ns.T(inst.n) or "?")
  W.SetText(dialog.count, nil, BP.SummaryText(summary, "saved"))
  dialog.image = ns.InstanceView.LoadingImage(inst)
  dialog.picture:SetTexture(dialog.image and dialog.image.fid or nil)
  dialog:Show()
  layout(dialog)
end

-- Hides the window without an answer (the player left, or the game's own lockout took over).
local function closeSilently()
  if dialog and dialog:IsShown() then
    dialog.silent = true
    dialog:Hide()
  end
  shownFor = nil
end

-- Asks now or, in combat, after it. Does nothing when the question is not due or already open.
local function consider(id)
  if shownFor == id or not due(id) then
    return
  end
  if inCombat() then
    pending = id
    return
  end
  pending = nil
  show(id)
end

-- Public API --------------------------------------------------------------------------------------

-- Manual reset (boss tab): asks first, then forgets the progress of the instance.
function BR.ConfirmReset(id)
  ns.Dialogs.Confirm("bossreset.manual.title", "bossreset.manual.text", function()
    BP.Reset(id)
  end)
end

-- State for the tests.
function BR.State()
  return { previous = previous, pending = pending, shownFor = shownFor, dialog = dialog, answeredAt = answeredAt }
end

-- Settings -----------------------------------------------------------------------------------------

function BR.AddSettings(view)
  ns.AddHeading(view, "bossreset.set.heading")
  ns.AddParagraph(view, "bossreset.set.hint", { role = "micro", color = "textMuted" })
  view.stack:Add(
    W.Toggle(view.content, {
      key = "bossreset.set.ask",
      get = enabled,
      set = function(v)
        Store.set("settings.bossResetPrompt", v == true)
      end,
      tooltip = "bossreset.set.ask",
      tooltipText = "bossreset.set.askTip",
    }),
    { height = 24, gap = 6 }
  )
  ns.AddParagraph(view, "bossreset.set.warn", { role = "micro", color = "warning" })
end

-- On the map tab, next to the dungeon map setting.
ns.SettingsPage.Add(BR.AddSettings, "map")

-- Events --------------------------------------------------------------------------------------------

ns.On("PLAYER_ENTERING_WORLD", function(_, initialLogin, reloadingUi)
  local id = BP.CurrentInstance()
  local entered = Logic.IsEntry(previous, id, initialLogin, reloadingUi)
  previous = id
  if pending ~= id then
    pending = nil
  end
  if shownFor and shownFor ~= id then
    closeSilently()
  end
  if entered then
    consider(id)
  end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  local id = pending
  pending = nil
  if id and id == previous then
    consider(id)
  end
end)

-- A lockout that lists kills decides for the game: the open question has no point then.
ns.On("UPDATE_INSTANCE_INFO", function()
  if shownFor and BP.Locked(shownFor) then
    closeSilently()
  end
end)
