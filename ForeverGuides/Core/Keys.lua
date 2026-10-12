-- Registry of the key combinations the player can change (settings card "Key combinations",
-- Modules/KeysSettings.lua). Every action is a mouse gesture with modifier keys: id, area, kind of
-- gesture, default combination, scope (the place or object it acts on). The code asks
-- ns.Keys.Matches(id) instead of IsControlKeyDown() and friends, texts name the current combination
-- with {key:id} and {mod:id} (see ns.L), so a hint never names a key the player has changed.
-- Editor conventions (Ctrl+C, Shift+Tab, Shift for a straight line ...) are not registered, they stay
-- fixed (docs/TASTENKOMBINATIONEN.md). Stored per action in settings.modKeys, a missing or invalid
-- entry means the default.
local _, ns = ...

local K = {}
ns.Keys = K

-- Allowed values, in the order of the list in the settings. Modifiers always in the order ctrl, shift, alt.
K.COMBOS = { "none", "ctrl", "shift", "alt", "ctrl+shift", "ctrl+alt", "shift+alt" }
K.KINDS = { "click", "leftclick", "wheel", "drag" }

local IS_COMBO, IS_KIND = {}, {}
for _, c in ipairs(K.COMBOS) do
  IS_COMBO[c] = true
end
for _, k in ipairs(K.KINDS) do
  IS_KIND[k] = true
end

local MODIFIERS = {
  { id = "ctrl", fn = "IsControlKeyDown" },
  { id = "shift", fn = "IsShiftKeyDown" },
  { id = "alt", fn = "IsAltKeyDown" },
}

local actions, order = {}, {}

-- def: id, area, kind (click, leftclick, wheel, drag), default (a combination), scope (actions with the
-- same scope and kind collide when they share a combination), allowNone (default false: the action
-- changes a plain gesture, so "no modifier" would take that gesture over).
-- Texts: keys.name.<id>, keys.desc.<id>, keys.area.<area> in the locale tables.
function K.Register(def)
  assert(type(def) == "table" and type(def.id) == "string", "key action needs an id")
  assert(IS_KIND[def.kind], "key action " .. def.id .. ": unknown kind")
  assert(IS_COMBO[def.default], "key action " .. def.id .. ": unknown default")
  assert(def.default ~= "none" or def.allowNone, "key action " .. def.id .. ": default needs allowNone")
  local entry = {
    id = def.id,
    area = def.area or "general",
    kind = def.kind,
    default = def.default,
    scope = def.scope or def.id,
    allowNone = def.allowNone == true,
  }
  if not actions[def.id] then
    order[#order + 1] = def.id
  end
  actions[def.id] = entry
  return entry
end

function K.Def(id)
  return actions[id]
end

function K.List()
  local out = {}
  for i, id in ipairs(order) do
    out[i] = id
  end
  return out
end

local function stored(id)
  local settings = ns.db and ns.db.settings
  local map = settings and settings.modKeys
  return type(map) == "table" and map[id] or nil
end

local function valid(def, value)
  return type(value) == "string" and IS_COMBO[value] == true and (value ~= "none" or def.allowNone)
end

-- Combinations the list offers for this action.
function K.Options(id)
  local def = actions[id]
  local out = {}
  for _, c in ipairs(K.COMBOS) do
    if def and (c ~= "none" or def.allowNone) then
      out[#out + 1] = c
    end
  end
  return out
end

function K.Default(id)
  return actions[id] and actions[id].default
end

-- Current combination of the action; a stored value that is no longer allowed gives the default.
function K.Get(id)
  local def = actions[id]
  if not def then
    return nil
  end
  local value = stored(id)
  return valid(def, value) and value or def.default
end

-- Stores a combination; the default is stored as "no entry". Returns false for an unknown action or a
-- value that is not allowed.
function K.Set(id, value)
  local def = actions[id]
  if not (def and valid(def, value)) then
    return false
  end
  ns.Store.set("settings.modKeys." .. id, value ~= def.default and value or nil)
  return true
end

function K.Reset(id)
  if not actions[id] then
    return false
  end
  ns.Store.set("settings.modKeys." .. id, nil)
  return true
end

function K.ResetAll()
  for _, id in ipairs(order) do
    K.Reset(id)
  end
end

function K.IsDefault(id)
  return K.Get(id) == K.Default(id)
end

local function held(name)
  local fn = rawget(_G, name)
  return type(fn) == "function" and fn() and true or false
end

-- The modifier keys held right now as a combination ("none", "ctrl", "ctrl+shift" ...). Three keys at
-- once are no allowed combination, so nothing matches then.
function K.Current()
  local parts = {}
  for _, m in ipairs(MODIFIERS) do
    if held(m.fn) then
      parts[#parts + 1] = m.id
    end
  end
  return #parts == 0 and "none" or table.concat(parts, "+")
end

-- True when exactly the stored combination is held: Ctrl does not match while Ctrl+Shift is held.
function K.Matches(id)
  local combo = K.Get(id)
  return combo ~= nil and combo == K.Current()
end

-- Names of the modifiers of a combination: "Ctrl+Shift", "No modifier" for none.
function K.ModLabel(combo)
  if not IS_COMBO[combo] then
    return ns.L["keys.combo.none"]
  end
  return ns.L["keys.combo." .. combo]
end

-- Name of a combination with its gesture: "Ctrl+Click", "Mouse wheel" for none.
function K.ComboLabel(combo, kind)
  local noun = ns.L["keys.kind." .. (IS_KIND[kind] and kind or "click")]
  if combo == "none" or not IS_COMBO[combo] then
    return noun
  end
  return K.ModLabel(combo) .. "+" .. noun
end

-- "Ctrl+Click" for tooltips and hints.
function K.Label(id)
  local def = actions[id]
  return def and K.ComboLabel(K.Get(id), def.kind) or id
end

-- "Ctrl" only, for texts that say "Ctrl: to the top".
function K.Mods(id)
  return actions[id] and K.ModLabel(K.Get(id)) or id
end

-- Actions that share a scope, a kind and a combination with the given one (ids, empty when alone).
function K.ConflictsOf(id)
  local def = actions[id]
  local out = {}
  if not def then
    return out
  end
  local combo = K.Get(id)
  for _, other in ipairs(order) do
    local o = actions[other]
    if other ~= id and o.scope == def.scope and o.kind == def.kind and K.Get(other) == combo then
      out[#out + 1] = other
    end
  end
  return out
end

-- Every group of actions that collide: { { combo, ids = { a, b } } }. Conflicts are shown, not blocked.
function K.Conflicts()
  local out, seen = {}, {}
  for _, id in ipairs(order) do
    if not seen[id] then
      local others = K.ConflictsOf(id)
      if #others > 0 then
        local ids = { id }
        seen[id] = true
        for _, other in ipairs(others) do
          ids[#ids + 1] = other
          seen[other] = true
        end
        out[#out + 1] = { combo = K.Get(id), ids = ids }
      end
    end
  end
  return out
end

-- Replaces {key:id} (full name) and {mod:id} (modifiers only) in a text by the current combination.
function K.Expand(text)
  if type(text) ~= "string" or not text:find("{", 1, true) then
    return text
  end
  return (
    text:gsub("{(%a+):(%w+)}", function(form, id)
      if not actions[id] then
        return nil
      end
      if form == "key" then
        return K.Label(id)
      elseif form == "mod" then
        return K.Mods(id)
      end
    end)
  )
end

ns.AddLocale("enUS", {
  ["keys.combo.none"] = "No modifier",
  ["keys.combo.ctrl"] = "Ctrl",
  ["keys.combo.shift"] = "Shift",
  ["keys.combo.alt"] = "Alt",
  ["keys.combo.ctrl+shift"] = "Ctrl+Shift",
  ["keys.combo.ctrl+alt"] = "Ctrl+Alt",
  ["keys.combo.shift+alt"] = "Shift+Alt",
  ["keys.kind.click"] = "Click",
  ["keys.kind.leftclick"] = "Left Click",
  ["keys.kind.wheel"] = "Mouse Wheel",
  ["keys.kind.drag"] = "Drag",
  ["keys.area.merchant"] = "Merchant",
  ["keys.area.map"] = "Map",
  ["keys.area.windows"] = "Windows",
  ["keys.area.lists"] = "Lists",
  ["keys.name.sellSwap"] = "Junk button: other mode",
  ["keys.desc.sellSwap"] = "Click with this key does the other of the two modes (sell now or open the selection).",
  ["keys.name.mapMarker"] = "Map: set a marker",
  ["keys.desc.mapMarker"] = "Sets a marker at the mouse position in any map mode.",
  ["keys.name.windowScale"] = "Windows: change size",
  ["keys.desc.windowScale"] = "On the title bar of our windows: the mouse wheel changes the size.",
  ["keys.name.frameNativeDrag"] = "Game windows: default drag",
  ["keys.desc.frameNativeDrag"] = "Drag with this key moves a game window without saving its position.",
  ["keys.name.scaleSnap"] = "Game windows: snapped zoom",
  ["keys.desc.scaleSnap"] = "While pulling the zoom grip the value snaps to 5 % steps.",
  ["keys.name.listToEdge"] = "Lists: move to the end",
  ["keys.desc.listToEdge"] = "Click on an arrow of a note or drawing moves it to the end of the list.",
  ["keys.name.rosterNote"] = "Characters: open note",
  ["keys.desc.rosterNote"] = "Click on a to-do cell opens its note (the right click does that as well).",
})
ns.AddLocale("deDE", {
  ["keys.combo.none"] = "Keine Zusatztaste",
  ["keys.combo.ctrl"] = "Strg",
  ["keys.combo.shift"] = "Umschalt",
  ["keys.combo.alt"] = "Alt",
  ["keys.combo.ctrl+shift"] = "Strg+Umschalt",
  ["keys.combo.ctrl+alt"] = "Strg+Alt",
  ["keys.combo.shift+alt"] = "Umschalt+Alt",
  ["keys.kind.click"] = "Klick",
  ["keys.kind.leftclick"] = "Linksklick",
  ["keys.kind.wheel"] = "Mausrad",
  ["keys.kind.drag"] = "Ziehen",
  ["keys.area.merchant"] = "Händler",
  ["keys.area.map"] = "Karte",
  ["keys.area.windows"] = "Fenster",
  ["keys.area.lists"] = "Listen",
  ["keys.name.sellSwap"] = "Plunder-Knopf: anderer Modus",
  ["keys.desc.sellSwap"] = "Klick mit dieser Taste löst den jeweils anderen der beiden Modi aus (schnell verkaufen oder Auswahl öffnen).",
  ["keys.name.mapMarker"] = "Karte: Marker setzen",
  ["keys.desc.mapMarker"] = "Setzt in jedem Kartenmodus einen Marker an der Mausposition.",
  ["keys.name.windowScale"] = "Fenster: Größe ändern",
  ["keys.desc.windowScale"] = "Auf der Titelleiste unserer Fenster ändert das Mausrad die Größe.",
  ["keys.name.frameNativeDrag"] = "Spielfenster: Standard-Ziehen",
  ["keys.desc.frameNativeDrag"] = "Ziehen mit dieser Taste verschiebt ein Spielfenster, ohne die Position zu speichern.",
  ["keys.name.scaleSnap"] = "Spielfenster: Zoom gerastet",
  ["keys.desc.scaleSnap"] = "Beim Ziehen des Zoom-Griffs rastet der Wert in 5-%-Schritten ein.",
  ["keys.name.listToEdge"] = "Listen: ans Ende schieben",
  ["keys.desc.listToEdge"] = "Klick auf einen Pfeil bei Notiz oder Zeichnung schiebt sie ans Ende der Liste.",
  ["keys.name.rosterNote"] = "Charaktere: Notiz öffnen",
  ["keys.desc.rosterNote"] = "Klick auf eine Aufgabenzelle öffnet ihre Notiz (der Rechtsklick tut das ebenfalls).",
})

K.Register({ id = "sellSwap", area = "merchant", kind = "click", default = "ctrl" })
K.Register({ id = "mapMarker", area = "map", kind = "leftclick", default = "alt" })
K.Register({ id = "windowScale", area = "windows", kind = "wheel", default = "ctrl", allowNone = true })
K.Register({ id = "frameNativeDrag", area = "windows", kind = "drag", default = "ctrl+shift" })
K.Register({ id = "scaleSnap", area = "windows", kind = "drag", default = "shift", allowNone = true })
K.Register({ id = "listToEdge", area = "lists", kind = "click", default = "shift" })
K.Register({ id = "rosterNote", area = "lists", kind = "click", default = "shift" })
