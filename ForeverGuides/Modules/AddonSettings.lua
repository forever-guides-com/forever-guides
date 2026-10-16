-- Settings tab "Addons": one card per optional add-on of Core/SubAddons.lua with a switch for the
-- account default, a choice for this character and a status line in plain words. The switches only
-- call SubAddons.SetEnabled / ClearOverride; the card follows FG_SUBADDON_CHANGED.
local _, ns = ...
local W, S = ns.W, ns.SubAddons

local AS = {}
ns.AddonSettings = AS

ns.AddLocale("enUS", {
  ["settings.tab.addons"] = "Addons",
  ["addons.set.heading"] = "Optional add-ons",
  ["addons.set.intro"] = "Each add-on has a default for all your characters. A single character can differ.",
  ["addons.set.hint"] = "Switching off takes effect after /reload or a restart, switching on loads it right away.",
  ["addons.set.default"] = "Default for all characters",
  ["addons.set.char"] = "This character",
  ["addons.set.sameOn"] = "Same as default (on)",
  ["addons.set.sameOff"] = "Same as default (off)",
  ["addons.set.on"] = "On",
  ["addons.set.off"] = "Off",
  ["addons.state.active"] = "Active.",
  ["addons.state.pendingOff"] = "Switched off. Stays active until /reload or a restart.",
  ["addons.state.offChar"] = "Off for this character.",
  ["addons.state.offAll"] = "Off for all characters.",
  ["addons.state.waitingGuild"] = "Waiting for a guild. Loads once this character is in a guild.",
  ["addons.state.waiting"] = "Waiting. Loads after combat or at the next start.",
  ["addons.state.missing"] = "Not installed (folder %s).",
  ["addons.state.disabled"] = "Switched off in the add-on list of the game for this character. Switch it on under AddOns on the character selection screen.",
  ["addons.state.failed"] = "Failed to load. Details on the page Errors.",
  ["addons.state.outdated"] = "Outdated version. Update all Forever Guides folders together.",
  ["addons.list.enabled"] = "In the game's AddOn list: enabled (loads only on demand).",
  ["addons.list.disabled"] = "In the game's AddOn list: disabled.",
  ["addons.loaded.yes"] = "Loaded: yes.",
  ["addons.loaded.no"] = "Loaded: no.",
})
ns.AddLocale("deDE", {
  ["settings.tab.addons"] = "Addons",
  ["addons.set.heading"] = "Optionale Addons",
  ["addons.set.intro"] = "Jedes Addon hat einen Standard für alle deine Charaktere. Ein einzelner Charakter kann abweichen.",
  ["addons.set.hint"] = "Ausschalten wirkt nach /reload oder einem Neustart, Einschalten lädt sofort.",
  ["addons.set.default"] = "Standard für alle Charaktere",
  ["addons.set.char"] = "Dieser Charakter",
  ["addons.set.sameOn"] = "Wie Standard (an)",
  ["addons.set.sameOff"] = "Wie Standard (aus)",
  ["addons.set.on"] = "An",
  ["addons.set.off"] = "Aus",
  ["addons.state.active"] = "Aktiv.",
  ["addons.state.pendingOff"] = "Ausgeschaltet. Bleibt aktiv bis /reload oder Neustart.",
  ["addons.state.offChar"] = "Für diesen Charakter aus.",
  ["addons.state.offAll"] = "Für alle Charaktere aus.",
  ["addons.state.waitingGuild"] = "Wartet auf eine Gilde. Lädt, sobald dieser Charakter in einer Gilde ist.",
  ["addons.state.waiting"] = "Wartet. Lädt nach dem Kampf oder beim nächsten Start.",
  ["addons.state.missing"] = "Nicht installiert (Ordner %s).",
  ["addons.state.disabled"] = "In der Addon-Liste des Spiels für diesen Charakter ausgeschaltet. Einschalten unter AddOns auf dem Charakterauswahl-Bildschirm.",
  ["addons.state.failed"] = "Laden fehlgeschlagen. Details auf der Seite Fehler.",
  ["addons.state.outdated"] = "Veraltete Version. Alle Forever-Guides-Ordner gemeinsam aktualisieren.",
  ["addons.list.enabled"] = "Im Spiel-Addon-Menü: aktiviert (wird nur bei Bedarf geladen).",
  ["addons.list.disabled"] = "Im Spiel-Addon-Menü: deaktiviert.",
  ["addons.loaded.yes"] = "Geladen: ja.",
  ["addons.loaded.no"] = "Geladen: nein.",
})

local FIELD_WIDTH = 240

local STATE_KEY = {
  active = "addons.state.active",
  ["pending-off"] = "addons.state.pendingOff",
  missing = "addons.state.missing",
  disabled = "addons.state.disabled",
  failed = "addons.state.failed",
  outdated = "addons.state.outdated",
}

-- Colors only back up the words of the line.
local STATE_COLOR = {
  active = "success",
  ["pending-off"] = "warning",
  waiting = "warning",
  disabled = "warning",
  failed = "danger",
  outdated = "danger",
}

-- Locale key of the status line of an add-on, from State and Source of the core.
function AS.StatusKey(id)
  local state = S.State(id)
  if state == "off" then
    return S.Source(id) == "char" and "addons.state.offChar" or "addons.state.offAll"
  elseif state == "waiting" then
    local entry = S.Get(id)
    local forGuild = entry and entry.loadWhen == "inGuild" and not S.Ready(id)
    return forGuild and "addons.state.waitingGuild" or "addons.state.waiting"
  end
  return STATE_KEY[state] or STATE_KEY.failed
end

-- Text and color name of the status line.
function AS.StatusText(id)
  local state = S.State(id)
  local text = ns.L[AS.StatusKey(id)]
  if state == "missing" then
    local entry = S.Get(id)
    text = string.format(text, entry and entry.addon or id)
  end
  return text, STATE_COLOR[state] or "textMuted"
end

-- What the game itself says: the entry in its add-on list and whether the folder is loaded. A
-- check mark in that list only allows loading on request, the switch of this tab decides.
-- Nil for an add-on that is not installed.
function AS.ListText(id)
  if S.State(id) == "missing" then
    return nil
  end
  local list = S.ListState(id)
  local loaded = ns.L[S.IsLoaded(id) and "addons.loaded.yes" or "addons.loaded.no"]
  if not list then
    return loaded
  end
  return ns.L["addons.list." .. list] .. " " .. loaded
end

local function accountValue(id)
  local t = ns.db.settings.subaddons
  if type(t) == "table" then
    return t[id]
  end
end

-- The default for all characters as the toggle shows it.
local function defaultOn(entry)
  return (S.Resolve(entry.defaultOn, nil, accountValue(entry.id)))
end

local function override(id)
  local t = ns.charDB and ns.charDB.subaddons
  if type(t) == "table" and type(t[id]) == "boolean" then
    return t[id]
  end
end

-- Cards of the page that was built last; a rebuilt page replaces the list.
local built = {}

local function addCard(card, entry)
  local id, s = entry.id, card.stack
  ns.AddHeading(card, entry.titleKey)
  ns.AddParagraph(card, entry.descKey, { role = "micro", color = "textMuted" })

  local default = W.Toggle(card.content, {
    key = "addons.set.default",
    get = function()
      return defaultOn(entry)
    end,
    set = function(v)
      S.SetEnabled(id, v, "account")
    end,
  })
  default.fgId = "addons-" .. id .. "-default"
  s:Add(default, { height = 24, gap = 8 })

  local options = {
    { value = "same", key = "addons.set.sameOn" },
    { value = "on", key = "addons.set.on" },
    { value = "off", key = "addons.set.off" },
  }
  local char = W.Dropdown(card.content, {
    key = "addons.set.char",
    width = FIELD_WIDTH,
    options = options,
    get = function()
      options[1].key = defaultOn(entry) and "addons.set.sameOn" or "addons.set.sameOff"
      local o = override(id)
      if o == nil then
        return "same"
      end
      return o and "on" or "off"
    end,
    set = function(v)
      if v == "same" then
        S.ClearOverride(id)
      else
        S.SetEnabled(id, v == "on", "char")
      end
    end,
  })
  char.fgId = "addons-" .. id .. "-char"
  s:Add(char, { height = 46, width = FIELD_WIDTH, gap = 4 })

  local status = W.Text(card.content, { role = "micro", wrap = true })
  status.fgId = "addons-" .. id .. "-state"
  local function paint()
    local text, color = AS.StatusText(id)
    status:SetText(text)
    W.SetColor(status, color)
  end
  ns.Bind(status, paint)
  status.Refresh = paint
  s:Add(status, { gap = 2 })

  local list = W.Text(card.content, { role = "micro", color = "textMuted", wrap = true })
  list.fgId = "addons-" .. id .. "-list"
  local function paintList()
    list:SetText(AS.ListText(id) or "")
  end
  ns.Bind(list, paintList)
  list.Refresh = paintList
  s:Add(list, { gap = 2 })
  built[#built + 1] = { card = card, status = status }
end

-- Fills the card it gets with the explanation and adds one more card per add-on to its grid.
function AS.AddSettings(view)
  built = {}
  ns.AddHeading(view, "addons.set.heading")
  ns.AddParagraph(view, "addons.set.intro", { role = "micro", color = "textMuted" })
  ns.AddParagraph(view, "addons.set.hint", { role = "micro", color = "textSecondary" })
  for _, entry in ipairs(S.List()) do
    addCard(view.grid:Card(), entry)
  end
end

-- A switch changed (here, in the wizard or on the guild page): every card reads its state again.
ns.On("FG_SUBADDON_CHANGED", function()
  for _, item in ipairs(built) do
    item.card:Refresh()
    if item.status:IsVisible() then
      item.card:Layout()
    end
  end
end)
