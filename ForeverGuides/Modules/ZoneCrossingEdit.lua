-- Meeting point of the zone arrow layers and the editor for the zone crossings, a separate tool that is not part
-- of the release. The layers (MapZoneArrows on the add-on map, WorldMapZoneArrows on Blizzard's map) register as
-- hosts and hand every pin they create to the decorators; the editor switches the mode and attaches its handlers
-- there. Without the editor nothing in here does anything.
-- A host is { id, canvas(), view() (the zone view shown, nil when none), zones() (zone records by slug),
-- aspect() (canvas height / width), place(pin, x, y) (moves a pin to a zone position), level() (frame level of
-- the pins), refresh(), pins() }.
local _, ns = ...

local ZE = { hosts = {}, decorators = {} }
ns.ZoneCrossingEdit = ZE

-- Size of the arrows while editing, as a factor.
ZE.GROW = 1.4

-- Locale key of the tooltip line that replaces the click hint while editing (set by the editor).
ZE.hintKey = nil

function ZE.Active()
  return ZE.on == true
end

-- Editing never happens in combat: the handlers of the editor ask this before they touch anything.
function ZE.Allowed()
  return ZE.on == true and not ns.InCombat()
end

function ZE.SetActive(on, hintKey)
  on = on == true
  if on == ZE.on then
    return
  end
  ZE.on, ZE.hintKey = on, on and hintKey or nil
  ns.Emit("FG_ZONECROSS_EDIT", on)
end

function ZE.Register(host)
  ZE.hosts[host.id] = host
end

-- fn(pin, host), called once for every pin a host creates; pins that exist when the decorator is added
-- are handed over too.
function ZE.AddDecorator(fn)
  ZE.decorators[#ZE.decorators + 1] = fn
  for _, host in pairs(ZE.hosts) do
    for _, pin in ipairs(host.pins()) do
      fn(pin, host)
    end
  end
end

function ZE.Decorate(pin, host)
  for _, fn in ipairs(ZE.decorators) do
    ns.Safe("zone-crossing-decorate", fn, pin, host)
  end
end

-- Size factor of an arrow.
function ZE.Scale()
  return ZE.on and ZE.GROW or 1
end

-- The hint line of an arrow tooltip: the editor's text while editing, else the key the layer would use.
function ZE.HintKey(default)
  return ZE.on and ZE.hintKey or default
end
