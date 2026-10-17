-- The network part of the layer window (LayerWindow.lua): the two opt-in switches with the short privacy
-- note, the buttons "Pick best host" and "Cancel", the progress line of a switch, and the list of the hosts
-- of the zone that the window shows when nobody feeds it another list. The window places and paints what is
-- made here. Nothing is sent from this file: a click asks LayerSwitch, a switch asks LayerNet. A button that
-- cannot work now is disabled and says why in its tooltip; the same reason is written in the progress line,
-- so it does not depend on the mouse.
local _, ns = ...
local W, L = ns.W, ns.L
local NL, PN, Layer = ns.LayerNetLogic, ns.PlayerName, ns.Layer

local LWN = {}
ns.LayerWindowNet = LWN

ns.AddLocale("enUS", {
  ["layer.win.best"] = "Pick best host",
  ["layer.win.bestTip"] = "Asks the hosts of this zone one after the other, most free places first.",
  ["layer.win.cancel"] = "Cancel",
  ["layer.win.cancelTip"] = "Stops the switch and leaves the temporary group.",
  ["layer.win.switchTip"] = "Asks this host for an invite. You join its group and land on its layer.",
  ["layer.win.empty.off"] = "Sharing is off. Switch it on above to see hosts.",
  ["layer.win.empty.layer"] = "Layer unknown: target an NPC.",
  ["layer.win.empty.none"] = "No hosts in this zone.",
  ["layer.win.hostsHeader"] = "Hosts in %s: %d",
  ["layer.win.hostLine"] = "  %s, %s, %s",
  ["layer.win.noSwitch"] = "No switch is running.",
})
ns.AddLocale("deDE", {
  ["layer.win.best"] = "Besten Host wählen",
  ["layer.win.bestTip"] = "Fragt die Hosts dieser Zone der Reihe nach, mit den meisten freien Plätzen zuerst.",
  ["layer.win.cancel"] = "Abbrechen",
  ["layer.win.cancelTip"] = "Beendet den Wechsel und verlässt die vorübergehende Gruppe.",
  ["layer.win.switchTip"] = "Fragt diesen Host nach einer Einladung. Du kommst in seine Gruppe und auf seinen Layer.",
  ["layer.win.empty.off"] = "Teilen ist aus. Schalte es oben ein, um Hosts zu sehen.",
  ["layer.win.empty.layer"] = "Layer unbekannt: NPC anvisieren.",
  ["layer.win.empty.none"] = "Keine Hosts in dieser Zone.",
  ["layer.win.hostsHeader"] = "Hosts in %s: %d",
  ["layer.win.hostLine"] = "  %s, %s, %s",
  ["layer.win.noSwitch"] = "Es läuft kein Wechsel.",
})

local TOGGLE_H, BUTTON_H, GAP = 24, 26, 6

local function toggle(f, key, tip, get, set)
  local control = W.Toggle(f, { key = key, tooltip = key, tooltipText = tip, get = get, set = set })
  control.fgId = "layerwin-" .. key:match("[^.]+$")
  return control
end

-- A button whose tooltip shows the reason while it is disabled.
local function button(f, key, variant, tipKey, onClick)
  local b = W.Action(f, { key = key, variant = variant, height = BUTTON_H, manual = true, onClick = onClick })
  b:HookScript("OnEnter", function(self)
    ns.ShowTooltip(self, ns.L[key], self.fgBlock or ns.L[tipKey])
  end)
  b:HookScript("OnLeave", ns.HideTooltip)
  return b
end

-- Makes the controls on window f. Returns { share, host, best, cancel, progress, privacy, texts }.
function LWN.Create(f)
  local net = {}
  net.share = toggle(f, "layer.net.share", "layer.net.shareTip", function()
    return ns.LayerNet.Sharing()
  end, function(on)
    ns.LayerNet.SetShare(on)
  end)
  net.host = toggle(f, "layer.net.host", "layer.net.hostTip", function()
    return ns.db.settings.layerHost == true
  end, function(on)
    ns.LayerNet.SetHost(on)
  end)
  net.privacy = W.Text(f, { key = "layer.net.privacy", role = "micro", color = "textMuted", wrap = true })
  net.best = button(f, "layer.win.best", "primary", "layer.win.bestTip", LWN.Best)
  net.cancel = button(f, "layer.win.cancel", "secondary", "layer.win.cancelTip", LWN.Cancel)
  net.progress = W.Text(f, { role = "ui", color = "textSecondary", wrap = true })
  net.texts = { net.privacy, net.progress, net.share.label, net.share.state, net.host.label, net.host.state }
  return net
end

-- What a redraw asks of the game once: the own layer, whether a switch can start, the hosts of the zone.
local snapshot

function LWN.Refresh()
  snapshot = { own = Layer.Get(), block = ns.LayerSwitch.CanStart(), hosts = ns.LayerNet.Hosts() }
  return snapshot
end

-- The progress line: { text, color } of the switch, or of the reason none can start; nil for nothing to say.
local function progress()
  local status = ns.LayerSwitch.Status()
  if status.phase == "asking" then
    return string.format(L["layer.net.asking"], status.host or "?", status.index, status.total), "info"
  elseif status.phase == "joined" then
    return string.format(L["layer.net.joined"], status.host or "?", status.left or 0), "info"
  elseif status.result then
    return ns.LayerSwitch.ResultText(status.result), status.result.kind == "done" and "success" or "warning"
  end
  local reason = (snapshot or LWN.Refresh()).block
  if reason and reason ~= "share" then
    return L["layer.net.block." .. reason], "textMuted"
  end
  return nil
end

-- Actions -------------------------------------------------------------------------------------------------

local function told(reason)
  if reason then
    ns.Notify(L["layer.net.block." .. reason] or reason, "warning")
  end
end

function LWN.Best()
  local ok, reason = ns.LayerSwitch.Best()
  if not ok then
    told(reason)
  end
end

function LWN.Cancel()
  ns.LayerSwitch.Cancel()
end

-- /fg layer hosts: the hosts of the zone as lines in the chat.
function LWN.PrintHosts()
  local chat = ns.Notify.chat
  if not ns.LayerNet.Sharing() then
    return chat(L["layer.win.empty.off"])
  end
  local hosts = ns.LayerNet.Hosts()
  if #hosts == 0 then
    return chat(L["layer.win.empty.none"])
  end
  chat(string.format(L["layer.win.hostsHeader"], Layer.ZoneName(Layer.Map()), #hosts))
  local LL = ns.LayerLogic
  for _, host in ipairs(hosts) do
    chat(
      string.format(
        L["layer.win.hostLine"],
        PN.Normalize(host.name),
        LL.EntryLayerText(host, L),
        LL.EntryFreeText(host, L)
      )
    )
  end
end

-- /fg layer switch: the same as the button.
function LWN.SwitchBest()
  local ok, reason = ns.LayerSwitch.Best()
  if ok then
    local text = progress()
    if text then
      ns.Notify.chat(text)
    end
  else
    told(reason)
  end
end

-- /fg layer cancel
function LWN.CancelCommand()
  local phase = ns.LayerSwitch.Status().phase
  if phase == "asking" or phase == "joined" then
    ns.LayerSwitch.Cancel()
  else
    ns.Notify.chat(L["layer.win.noSwitch"])
  end
end

-- The hosts of the zone for the list: { name, class, layer, free, blocked (text), onClick }.
function LWN.Live()
  local now = snapshot or LWN.Refresh()
  local out = {}
  for _, host in ipairs(now.hosts) do
    local block = now.block or NL.TargetBlock(host, now.own)
    out[#out + 1] = {
      name = PN.Normalize(host.name),
      class = host.class,
      layer = host.layer,
      free = host.free,
      blocked = block and L["layer.net.block." .. block],
      onClick = function()
        local ok, reason = ns.LayerSwitch.StartWith(host.key)
        if not ok then
          told(reason)
        end
      end,
    }
  end
  return out
end

-- The text of the empty list: why there is nothing to show.
function LWN.EmptyKey()
  if not ns.LayerNet.Sharing() then
    return "layer.win.empty.off"
  elseif not (snapshot or LWN.Refresh()).own then
    return "layer.win.empty.layer"
  end
  return "layer.win.empty.none"
end

-- Drawing -------------------------------------------------------------------------------------------------

local COLORS = { info = "textSecondary", success = "success", warning = "warning", textMuted = "textMuted" }

-- Brings the controls in line with the settings and the switch.
function LWN.Render(f)
  local net = f.net
  net.share:Refresh()
  net.host:Refresh()
  local text, level = progress()
  W.SetText(net.progress, nil, text or "")
  W.SetColor(net.progress, COLORS[level] or "textSecondary")
  local status = ns.LayerSwitch.Status()
  local active = status.phase == "asking" or status.phase == "joined"
  local now = snapshot or LWN.Refresh()
  local block = now.block
  if not block and #NL.Targets(now.hosts, now.own) == 0 then
    block = "nohost"
  end
  net.best.fgBlock = block and L["layer.net.block." .. block] or nil
  net.best:SetEnabled(block == nil)
  net.cancel:SetShown(active)
end

-- Places the controls from y downwards inside the width and answers the y below them.
function LWN.Layout(f, y, width, put, pad)
  local net = f.net
  local height = ns.Theme.lineHeight(TOGGLE_H, "ui")
  for _, control in ipairs({ net.share, net.host }) do
    control:ClearAllPoints()
    control:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -y)
    control:SetSize(width, height)
    y = y + height + 2
  end
  y = put(f, net.privacy, y + 2, width) + GAP
  -- The buttons stand in a row and move to the next row where the width ends.
  local x, rowTop = 0, y
  for _, b in ipairs({ f.refresh, net.best, net.cancel }) do
    if b:IsShown() then
      local w = math.min(width, b:FullWidth())
      if x > 0 and x + w > width then
        x, rowTop = 0, rowTop + BUTTON_H + 4
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", f, "TOPLEFT", pad + x, -rowTop)
      b:SetWidth(w)
      x = x + w + GAP
    end
  end
  return put(f, net.progress, rowTop + BUTTON_H + GAP, width)
end
