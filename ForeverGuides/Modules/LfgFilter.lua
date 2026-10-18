-- Settings card "Group finder": shows and changes the CVar disableSuggestedLevelActivityFilter ("show all
-- dungeons"). The CVar is the only source of truth, read live whenever the card needs it. It is written only on a
-- click of the user (switch or reset button), never at load, and the addon keeps no copy of the value. The
-- frames of the group finder are neither touched nor hooked.
-- A write from addon code taints the CVAR_UPDATE dispatch: the game's CVarCallbackRegistry caches the value in
-- the tainted stack and every later read taints the game's own search until the cache is refilled, in practice
-- until a reload. No call path avoids that (SetCVar and C_CVar.SetCVar dispatch the event inside the caller),
-- so after a write the card asks for a reload and /fg diag reports it.
local _, ns = ...
local Guard, L, LL = ns.AutoGuard, ns.L, ns.LfgFilterLogic
local W = ns.W

local R = {}
ns.LfgFilter = R

ns.AddLocale("enUS", {
  ["lfg.set.heading"] = "Group finder",
  ["lfg.set.all"] = "Switch here (reload afterwards)",
  ["lfg.set.hint"] = "The best way is the gear icon at the top right of the group finder.\nIt needs no reload.",
  ["lfg.reload.notice"] = "Blizzard's group finder needs a reload to work cleanly.",
  ["lfg.reload.button"] = "Reload now",
  ["lfg.set.reset"] = "Reset to default",
  ["lfg.state.on"] = "Show all dungeons: On",
  ["lfg.state.off"] = "Show all dungeons: Off (only activities for your level)",
  ["lfg.state.unknown"] = "Show all dungeons: Unknown",
  ["lfg.blocked.combat"] = "Not changeable in combat.",
  ["lfg.blocked.api"] = "This client cannot change the setting.",
  ["lfg.error"] = "The setting was not applied.",
  ["lfg.set.panel"] = "Offer filter panel",
  ["lfg.set.panelHint"] = "Panel and tab at the group finder.\nWith LFG Filter Forever (/lfgf) the filter stays off.",
  ["lfg.set.panelAuto"] = "Show panel on open",
  ["lfg.set.panelAutoHint"] = "Opens with the group finder.\nX or tab closes it until the next opening.",
  ["lfg.set.panelDock"] = "Dock panel to window",
  ["lfg.set.panelDockHint"] = "Moves Blizzard's tabs to the panel edge.\nOff: panel right of the tabs.",
})
ns.AddLocale("deDE", {
  ["lfg.set.heading"] = "Gruppensuche",
  ["lfg.set.all"] = "Hier umschalten (danach Neuladen)",
  ["lfg.set.hint"] = "Am besten änderst du das mit dem Zahnrad oben rechts in der Gruppensuche.\nDort ist kein Neuladen nötig.",
  ["lfg.reload.notice"] = "Damit Blizzards Gruppensuche sauber arbeitet, ist ein Neuladen nötig.",
  ["lfg.reload.button"] = "Jetzt neu laden",
  ["lfg.set.reset"] = "Auf Standard zurücksetzen",
  ["lfg.state.on"] = "Alle Dungeons zeigen: An",
  ["lfg.state.off"] = "Alle Dungeons zeigen: Aus (nur Aktivitäten für deine Stufe)",
  ["lfg.state.unknown"] = "Alle Dungeons zeigen: Unbekannt",
  ["lfg.blocked.combat"] = "Im Kampf nicht änderbar.",
  ["lfg.blocked.api"] = "Dieser Client kann die Einstellung nicht ändern.",
  ["lfg.error"] = "Die Einstellung wurde nicht übernommen.",
  ["lfg.set.panel"] = "Filter-Panel anbieten",
  ["lfg.set.panelHint"] = "Panel und Reiter an der Gruppensuche.\nMit LFG Filter Forever (/lfgf) bleibt der Filter aus.",
  ["lfg.set.panelAuto"] = "Panel beim Öffnen zeigen",
  ["lfg.set.panelAutoHint"] = "Öffnet mit der Gruppensuche.\nX oder Reiter schließt es bis zum nächsten Öffnen.",
  ["lfg.set.panelDock"] = "Panel am Fenster andocken",
  ["lfg.set.panelDockHint"] = "Schiebt Blizzards Reiter an den Panelrand.\nAus: Panel rechts neben den Reitern.",
})

local STATE_COLOR = { on = "success", off = "textSecondary", unknown = "warning" }

-- The raw value of the CVar, nil when the client has none or the value is secret.
function R.Raw()
  return Guard.Safe(ns.GetCVar(LL.CVAR))
end

-- "on", "off" or "unknown", read live.
function R.Current()
  return LL.State(R.Raw())
end

-- True after a write of this addon until the next reload (the tainted cache of the game lives that long).
local reloadNeeded = false

function R.ReloadNeeded()
  return reloadNeeded
end

function R.DiagLine()
  return "lfg: showAllDungeons=" .. LL.DiagValue(R.Raw()) .. (reloadNeeded and " reloadNeeded=ja" or "")
end

local function setFunction()
  local api = rawget(_G, "C_CVar")
  local fn = type(api) == "table" and api.SetCVar or nil
  if type(fn) ~= "function" then
    fn = rawget(_G, "SetCVar")
  end
  return type(fn) == "function" and fn or nil
end

-- Controls of the card built last (switch and status line); a rebuilt page replaces them.
local built = {}

function R.Refresh()
  if not built.status then
    return
  end
  built.toggle:Refresh()
  built.status:Refresh()
  built.notice:SetShown(reloadNeeded)
  built.reload:SetShown(reloadNeeded)
  if built.status:IsVisible() then
    built.card:Layout()
  end
end

-- Writes a value on a click and reads it back. True when the game holds the value afterwards.
function R.Write(wanted)
  local set = setFunction()
  local ok, reason = LL.CanWrite({ canSet = set ~= nil, combat = Guard.Blocked() })
  if not ok then
    ns.Notify(L[reason], "warning")
    return false
  end
  local before = R.Raw()
  local called = pcall(set, LL.CVAR, wanted)
  -- A write that raised may still have gone through, so a changed value counts as well.
  reloadNeeded = reloadNeeded or called or R.Raw() ~= before
  local confirmed = called and LL.Confirmed(wanted, R.Raw())
  if not confirmed then
    ns.Notify(L["lfg.error"], "error")
  end
  R.Refresh()
  return confirmed
end

-- Settings ---------------------------------------------------------------------------------------

-- The reload of the game from a click; asks first in a group or instance, tells when the game refuses.
local function reloadClick()
  ns.SaveUI.ConfirmedReload()
end

function R.AddSettings(card)
  built = { card = card }
  ns.AddHeading(card, "lfg.set.heading")

  local status = W.Text(card.content, { role = "ui", wrap = true })
  status.fgId = "lfg-state"
  function status:Refresh()
    local state = R.Current()
    W.SetText(self, "lfg.state." .. state)
    W.SetColor(self, STATE_COLOR[state])
  end
  status:Refresh()
  card.stack:Add(status, { gap = 6 })

  ns.AddParagraph(card, "lfg.set.hint", { role = "micro", color = "textMuted", gap = 10 })

  local toggle = W.Toggle(card.content, {
    key = "lfg.set.all",
    get = function()
      return R.Current() == "on"
    end,
    set = function(on)
      R.Write(LL.Target(on))
    end,
  })
  toggle.fgId = "lfg-all"
  card.stack:Add(toggle, { height = 24, gap = 10 })

  local reset = W.Button(card.content, {
    key = "lfg.set.reset",
    width = 220,
    onClick = function()
      R.Write(LL.DEFAULT)
    end,
  })
  reset.fgId = "lfg-reset"
  card.stack:Add(reset, { height = 28, width = 220, gap = 10 })

  local notice = W.Text(card.content, { key = "lfg.reload.notice", role = "ui", color = "warning", wrap = true })
  notice.fgId = "lfg-reload-notice"
  notice:Hide()
  card.stack:Add(notice, { gap = 6 })

  local reload = W.Button(card.content, {
    key = "lfg.reload.button",
    width = 220,
    onClick = ns.SaveState.Click(reloadClick),
  })
  reload.fgId = "lfg-reload"
  reload:Hide()
  card.stack:Add(reload, { height = 28, width = 220, gap = 14 })

  local panel = W.Toggle(card.content, {
    key = "lfg.set.panel",
    get = function()
      return ns.db.settings.lfgPanel ~= false
    end,
    set = function(on)
      ns.Store.set("settings.lfgPanel", on)
    end,
  })
  panel.fgId = "lfg-panel"
  card.stack:Add(panel, { height = 24, gap = 6 })
  ns.AddParagraph(card, "lfg.set.panelHint", { role = "micro", color = "textMuted", gap = 8 })

  local auto = W.Toggle(card.content, {
    key = "lfg.set.panelAuto",
    get = function()
      return ns.db.settings.lfgPanelAuto ~= false
    end,
    set = function(on)
      ns.Store.set("settings.lfgPanelAuto", on)
    end,
  })
  auto.fgId = "lfg-panel-auto"
  card.stack:Add(auto, { height = 24, gap = 6 })
  ns.AddParagraph(card, "lfg.set.panelAutoHint", { role = "micro", color = "textMuted", gap = 8 })

  local dock = W.Toggle(card.content, {
    key = "lfg.set.panelDock",
    get = function()
      return ns.db.settings.lfgPanelDock ~= false
    end,
    set = function(on)
      ns.Store.set("settings.lfgPanelDock", on)
    end,
  })
  dock.fgId = "lfg-panel-dock"
  card.stack:Add(dock, { height = 24, gap = 6 })
  ns.AddParagraph(card, "lfg.set.panelDockHint", { role = "micro", color = "textMuted", gap = 8 })
  built.toggle, built.status, built.notice, built.reload = toggle, status, notice, reload
  R.Refresh()
end

-- The frames of the group finder stay untouched here; the tab and the hook follow the switch themselves.

-- Blizzard or the player changed the variable elsewhere (the gear icon of the group finder, /console).
ns.On("CVAR_UPDATE", function(_, name)
  if LL.IsCVar(Guard.Safe(name)) then
    R.Refresh()
  end
end)

ns.SettingsPage.Add(R.AddSettings, "social")
