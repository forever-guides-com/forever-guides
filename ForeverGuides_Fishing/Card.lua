-- The settings cards of the fishing helper (tab "Fishing" of the main settings): status, cast and reel in, sound
-- and display, journal. Every option has one sentence of explanation. The cards only show and store, the
-- controller decides. A change goes through Controller.Set.
local _, fish = ...
if not fish.FG then
  return
end

local FG = fish.FG
local W = FG.W
local Options, Status, Controller = fish.Options, fish.Status, fish.Controller

local Card = {}
fish.Card = Card

-- The card that was built last: the status repaints while the page is hidden too.
local current

local function toggle(view, id)
  local t = W.Toggle(view.content, {
    key = "fishing.opt." .. id,
    get = function()
      return Controller.Options()[id] == true
    end,
    set = function(value)
      Controller.Set(id, value)
    end,
  })
  t.fgId = "fishing-" .. id
  view.stack:Add(t, { height = 24, gap = 2 })
  FG.AddParagraph(view, "fishing.opt." .. id .. ".hint", { role = "micro", color = "textMuted", gap = 8 })
end

local function slider(view, id, pattern)
  local def = Options.SLIDERS[id]
  local s = W.Slider(view.content, {
    key = "fishing.opt." .. id,
    min = def.min,
    max = def.max,
    step = def.step,
    get = function()
      return Controller.Options()[id]
    end,
    set = function(value)
      Controller.Set(id, value)
    end,
    format = function(value)
      return string.format(pattern, value)
    end,
  })
  s.fgId = "fishing-" .. id
  view.stack:Add(s, { height = 42, gap = 2 })
  FG.AddParagraph(view, "fishing.opt." .. id .. ".hint", { role = "micro", color = "textMuted", gap = 8 })
end

local function statusText()
  return Status.Text(FG.L, Controller.Snapshot(true))
end

-- The status card: whether fishing is possible now and why not, and the button to check again.
function Card.AddStatus(view)
  -- The switches work on the saved data: make sure the helper has started, whatever the client delivered.
  Controller.Bootstrap()
  FG.AddHeading(view, "settings.card.fishing.status")
  FG.AddParagraph(view, "fishing.set.intro", { role = "micro", color = "textMuted" })
  FG.AddParagraph(view, "fishing.set.status", { role = "ui", color = "text", gap = 2 })
  local status = W.Text(view.content, { role = "ui", color = "textSecondary", wrap = true, text = " " })
  status.fgId = "fishing-status"
  view.stack:Add(status, { gap = 6 })
  local function paint()
    status:SetText(statusText())
  end
  status.Refresh = paint
  FG.Bind(status, paint)
  local recheck = W.Button(view.content, {
    key = "fishing.set.recheck",
    width = 200,
    onClick = function()
      Controller.Retry()
      paint()
      view:Layout()
    end,
  })
  recheck.fgId = "fishing-recheck"
  view.stack:Add(recheck, { height = 26, width = 200, gap = 2 })
  FG.AddParagraph(view, "fishing.set.recheckHint", { role = "micro", color = "textMuted", gap = 8 })
  current = { status = status, view = view }
end

-- Cast and reel in: the key, the double click and the recast.
function Card.AddCast(view)
  Controller.Bootstrap()
  FG.AddHeading(view, "settings.card.fishing.cast")
  toggle(view, "oneKey")
  toggle(view, "doubleClick")
  local more = W.Accordion(view, { id = view.id or "fishing.cast" })
  slider(more, "doubleClickTime", "%.2f s")
  toggle(more, "doubleClickMounted")
  toggle(more, "recast")
  toggle(more, "recastInvert")
  slider(more, "recastPause", "%.1f s")
end

-- Sound and display while fishing.
function Card.AddSound(view)
  Controller.Bootstrap()
  FG.AddHeading(view, "settings.card.fishing.sound")
  toggle(view, "improveSound")
  local more = W.Accordion(view, { id = view.id or "fishing.sound" })
  slider(more, "soundVolume", "%d %%")
  slider(more, "effectVolume", "%d %%")
  toggle(more, "hideNames")
  toggle(more, "hideBobberIcon")
  toggle(more, "bobberMark")
  slider(more, "markOffset", "%d px")
  toggle(more, "autoLoot")
end

-- The catch journal: recording and the way to the window.
function Card.AddJournal(view)
  Controller.Bootstrap()
  FG.AddHeading(view, "settings.card.fishing.journal")
  toggle(view, "recordCatches")
  local open = W.Button(view.content, {
    key = "fishj.open",
    width = 220,
    opens = true,
    onClick = function()
      fish.JournalView.Open()
    end,
  })
  open.fgId = "fishing-journal"
  view.stack:Add(open, { height = 26, width = 220, gap = 2 })
  FG.AddParagraph(view, "fishj.set.hint", { role = "micro", color = "textMuted", gap = 8 })
end

-- The status changed (fishing became possible, a key was set, a call was blocked): the text follows even
-- while the page is hidden, so it is right when the page opens.
FG.On("FG_FISHING_STATUS", function()
  if not current then
    return
  end
  current.status:SetText(statusText())
  if current.status:IsVisible() then
    -- The whole tab: a longer status text makes the card taller, and a card that kept its old height would
    -- lie under the next one and take the clicks meant for its switches.
    current.view:Layout()
  end
end)

FG.SettingsPage.Add(Card.AddStatus, "fishing", "fishing.status")
FG.SettingsPage.Add(Card.AddCast, "fishing", "fishing.cast")
FG.SettingsPage.Add(Card.AddSound, "fishing", "fishing.sound")
FG.SettingsPage.Add(Card.AddJournal, "fishing", "fishing.journal")

-- What the main add-on asks for: the status as text and the way to the card.
function Card.Show()
  FG.SettingsPage.Select("fishing", "fishing.status")
  FG.Main.Show("settings")
end
